"""Searches for any combination of Signals that predicts a WHOOP target, and measures honestly
whether it beats guessing. A check on the Sleep Model, not the model itself (see sleep_model.py).

Features come from two families:
  measures - the app's own on-device Signals (FaceMeasurement.swift via measure.py), on photos its
             Capture Quality accepts. Computed on this Mac; no photo leaves it.
  signals  - LLM Signals already in dataset.csv, when photos were scored, from one Scoring Run setup.

The search tries every candidate (family x feature subset x ridge strength) and keeps the one with
the lowest leave-one-out error. Because picking the best of many candidates on few photos flatters
the winner, the reported error is *nested*: every held-out photo is predicted by a search that never
saw it. A permutation test (re-running the whole search on shuffled targets) then says how often
pure noise does as well. Only a nested error clearly below the guess-the-mean baseline, with a small
permutation p-value, is evidence that the face carries information about the target.
"""

from __future__ import annotations

import csv
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from face_pipeline import measure, scoring, sleep_model

TARGETS = {
    "sleep": "whoop_sleep_performance_percentage",
    "recovery": "whoop_recovery",
}
SIGNAL_COLUMNS = [key for key, _ in scoring.SIGNALS] + ["holistic_tiredness"]
MEASURES = [c.signal for cue in sleep_model.CUES for c in cue.candidates]
RIDGE_ALPHAS = [0.3, 3.0, 30.0, 300.0]
MIN_ROWS = 8  # below this, leave-one-out has nothing to learn from
MIN_ROWS_FOR_CLAIMS = 30  # below this, say so loudly whatever the numbers look like


# ---------------------------------------------------------------- model search

@dataclass(frozen=True)
class Candidate:
    family: str  # "measures", "signals", or "measures+signals"
    columns: tuple[str, ...]
    alpha: float

    @property
    def name(self) -> str:
        cols = "all" if len(self.columns) > 1 else self.columns[0]
        return f"{self.family}[{cols}], alpha={self.alpha:g}"


def candidates(available: dict[str, np.ndarray]) -> list[Candidate]:
    """Every model the search may pick. Single features are included because with few photos one
    honest number often beats a regression over many."""
    out: list[Candidate] = []
    for alpha in RIDGE_ALPHAS:
        for family in ("measures", "signals"):
            if family in available:
                cols = tuple(_columns(family))
                out.append(Candidate(family, cols, alpha))
                out.extend(Candidate(family, (c,), alpha) for c in cols)
        if "measures" in available and "signals" in available:
            out.append(Candidate("measures+signals", tuple(MEASURES + SIGNAL_COLUMNS), alpha))
    return out


def _columns(family: str) -> list[str]:
    return MEASURES if family == "measures" else SIGNAL_COLUMNS


def design(candidate: Candidate, data: dict[str, np.ndarray], rows: np.ndarray) -> np.ndarray:
    """Feature matrix of `candidate`'s columns for `rows`."""
    parts = []
    for family in candidate.family.split("+"):
        cols = _columns(family)
        idx = [cols.index(c) for c in candidate.columns if c in cols]
        parts.append(data[family][:, idx])
    return np.concatenate(parts, axis=1)[rows]


def ridge_fit(x: np.ndarray, y: np.ndarray, alpha: float) -> tuple[np.ndarray, np.ndarray, float, np.ndarray]:
    """Standardised ridge. Returns (mean, scale, intercept, coef); NaN features take the train mean."""
    mean = _column_means(x)
    x = np.where(np.isnan(x), mean, x)
    scale = x.std(axis=0)
    scale[scale == 0] = 1.0
    z = (x - mean) / scale
    coef = np.linalg.solve(z.T @ z + alpha * np.eye(z.shape[1]), z.T @ (y - y.mean()))
    return mean, scale, float(y.mean()), coef


def _column_means(x: np.ndarray) -> np.ndarray:
    """Per-column mean ignoring NaN; a column with no values at all counts as 0 (it then has no spread)."""
    with np.errstate(invalid="ignore"):
        counts = (~np.isnan(x)).sum(axis=0)
        sums = np.nansum(x, axis=0)
    return np.where(counts > 0, sums / np.maximum(counts, 1), 0.0)


def ridge_predict(model: tuple, x: np.ndarray) -> np.ndarray:
    mean, scale, intercept, coef = model
    x = np.where(np.isnan(x), mean, x)
    return intercept + ((x - mean) / scale) @ coef


def loo_errors(x: np.ndarray, y: np.ndarray, alpha: float) -> np.ndarray:
    """Exact leave-one-out absolute errors of ridge with a free intercept, in closed form (hat matrix),
    with standardisation fixed on these rows. Used for the inner search, where speed matters."""
    mean = _column_means(x)
    x = np.where(np.isnan(x), mean, x)
    scale = x.std(axis=0)
    scale[scale == 0] = 1.0
    z = np.concatenate([np.ones((len(x), 1)), (x - mean) / scale], axis=1)
    penalty = alpha * np.eye(z.shape[1])
    penalty[0, 0] = 0.0  # never shrink the intercept
    hat = z @ np.linalg.solve(z.T @ z + penalty, z.T)
    residual = y - hat @ y
    return np.abs(residual / np.clip(1 - np.diag(hat), 1e-9, None))


def select(data: dict[str, np.ndarray], y: np.ndarray, rows: np.ndarray, pool: list[Candidate]
           ) -> tuple[Candidate, float]:
    """Best candidate by leave-one-out MAE over `rows`."""
    best, best_mae = pool[0], float("inf")
    for c in pool:
        mae = float(loo_errors(design(c, data, rows), y[rows], c.alpha).mean())
        if mae < best_mae:
            best, best_mae = c, mae
    return best, best_mae


def nested_loo(data: dict[str, np.ndarray], y: np.ndarray, pool: list[Candidate]
               ) -> tuple[np.ndarray, np.ndarray, list[Candidate]]:
    """Outer leave-one-out around the whole search. Returns (predictions, mean-baseline predictions,
    the candidate chosen for each held-out row)."""
    n = len(y)
    pred, base, chosen = np.empty(n), np.empty(n), []
    for i in range(n):
        train = np.delete(np.arange(n), i)
        c, _ = select(data, y, train, pool)
        model = ridge_fit(design(c, data, train), y[train], c.alpha)
        # Both targets are percentages; on few nights an extrapolated line can leave that range.
        pred[i] = np.clip(ridge_predict(model, design(c, data, np.array([i])))[0], 0, 100)
        base[i] = y[train].mean()
        chosen.append(c)
    return pred, base, chosen


def permutation_p(data: dict[str, np.ndarray], y: np.ndarray, pool: list[Candidate], observed_mae: float,
                  permutations: int, seed: int) -> float:
    """Share of label shuffles whose whole nested search does at least as well as the real one."""
    rng = np.random.default_rng(seed)
    hits = 0
    for _ in range(permutations):
        shuffled = rng.permutation(y)
        pred, _, _ = nested_loo(data, shuffled, pool)
        hits += np.abs(pred - shuffled).mean() <= observed_mae
    return (hits + 1) / (permutations + 1)


def spearman(a: np.ndarray, b: np.ndarray) -> float:
    keep = ~(np.isnan(a) | np.isnan(b))
    if keep.sum() < 3:
        return float("nan")
    ra, rb = (np.argsort(np.argsort(v[keep])) for v in (a, b))
    return float(np.corrcoef(ra, rb)[0, 1])


# ---------------------------------------------------------------- driver

def run(dataset_dir: Path, out_dir: Path, target: str, permutations: int = 200, seed: int = 42) -> dict:
    column = TARGETS[target]
    rows = _load_rows(dataset_dir, column)
    if len(rows) < MIN_ROWS:
        raise SystemExit(
            f"Only {len(rows)} usable paired photo(s) with a {column} in {dataset_dir / 'dataset.csv'}; "
            f"the search needs at least {MIN_ROWS} and a claim needs about {MIN_ROWS_FOR_CLAIMS}+. "
            "Add dated photos (see pipeline/README.md) and re-run build-dataset.")

    measured = measure.measure([dataset_dir / r["image"] for r in rows], out_dir)
    kept, feats = [], []
    for r in rows:
        m = measured[dataset_dir / r["image"]].get("measurement")
        if m and m["quality"]["usable"]:
            kept.append(r)
            feats.append(m["signals"])
    dropped_unusable = len(rows) - len(kept)
    rows = kept
    if len(rows) < MIN_ROWS:
        raise SystemExit(f"Only {len(rows)} photos passed on-device Capture Quality (no face, glasses, "
                         f"light or blur rejected the rest); need at least {MIN_ROWS}.")

    y = np.array([float(r[column]) for r in rows])
    data: dict[str, np.ndarray] = {
        "measures": np.array([[f.get(k, np.nan) for k in MEASURES] for f in feats]),
    }
    signals, signal_run = _comparable_signals(rows)
    if signal_run:
        data["signals"] = signals

    pool = candidates(data)
    pred, base, chosen = nested_loo(data, y, pool)
    mae, base_mae = float(np.abs(pred - y).mean()), float(np.abs(base - y).mean())
    p = permutation_p(data, y, pool, mae, permutations, seed)

    final, final_inner_mae = select(data, y, np.arange(len(y)), pool)
    all_rows = np.arange(len(y))
    final_model = ridge_fit(design(final, data, all_rows), y, final.alpha)

    correlations = {name: spearman(data[fam][:, i], y)
                    for fam in ("measures", "signals") if fam in data
                    for i, name in enumerate(_columns(fam))}
    picks: dict[str, int] = {}
    for c in chosen:
        picks[c.name] = picks.get(c.name, 0) + 1

    beats = mae < base_mae and p < 0.05
    result = {
        "target": column,
        "photos": len(y),
        "dropped_unusable": dropped_unusable,
        "families": sorted(data),
        "signals_scoring_run": signal_run,
        "candidates_searched": len(pool),
        "nested_loo_mae": round(mae, 2),
        "baseline_mae_predict_mean": round(base_mae, 2),
        "improvement_points": round(base_mae - mae, 2),
        "permutation_p": round(p, 4),
        "permutations": permutations,
        "nested_spearman": round(spearman(pred, y), 3),
        "verdict": _verdict(beats, len(y)),
        "selected_model": {
            "candidate": final.name,
            "inner_loo_mae_optimistic": round(final_inner_mae, 2),
            "features": list(final.columns),
            "alpha": final.alpha,
            "feature_mean": final_model[0].tolist(),
            "feature_scale": final_model[1].tolist(),
            "intercept": final_model[2],
            "coef": final_model[3].tolist(),
        },
        "outer_fold_picks": dict(sorted(picks.items(), key=lambda kv: -kv[1])),
        "feature_spearman": {k: round(v, 3) for k, v in correlations.items()},
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / f"{target}_results.json").write_text(json.dumps(result, indent=2))
    (out_dir / f"{target}_report.md").write_text(_report(result))
    with (out_dir / f"{target}_predictions.csv").open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["image", "local_date", column, "predicted", "baseline"])
        for r, a, b in zip(rows, pred, base):
            writer.writerow([r["image"], r["local_date"], r[column], round(a, 1), round(b, 1)])
    return result


def _load_rows(dataset_dir: Path, column: str) -> list[dict]:
    path = dataset_dir / "dataset.csv"
    if not path.exists():
        raise SystemExit(f"No {path}. Run: face-pipeline build-dataset")
    with path.open() as f:
        rows = list(csv.DictReader(f))
    # One photo per night (the Canonical Scan), never an Unusable Scan, and only rows with a target.
    return [r for r in rows
            if r.get("is_canonical") == "True" and r.get("usable") != "False" and r.get(column) not in ("", None)]


def _comparable_signals(rows: list[dict]) -> tuple[np.ndarray, str | None]:
    """Absolute Signals only mean something within one Scoring Run setup (CONTEXT.md), so keep the
    most common provider/model/prompt and blank the rest; blanks are then imputed like any gap.
    Returns (signals, that run), with run None when under 80% of rows share it."""
    runs = [(r.get("scoring_provider"), r.get("scoring_model"), r.get("prompt_version"))
            if r.get("prompt_version") else None for r in rows]
    counted = [run for run in runs if run]
    if not counted:
        return np.empty((len(rows), 0)), None
    dominant = max(set(counted), key=counted.count)
    signals = np.array([[_float(r.get(c)) if run == dominant else float("nan") for c in SIGNAL_COLUMNS]
                        for r, run in zip(rows, runs)])
    if counted.count(dominant) < 0.8 * len(rows):
        return signals, None
    return signals, " / ".join(dominant)


def _float(value) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return float("nan")


def _verdict(beats: bool, n: int) -> str:
    if n < MIN_ROWS_FOR_CLAIMS:
        return (f"Too few nights ({n}) to conclude anything; treat every number below as noise "
                f"until there are {MIN_ROWS_FOR_CLAIMS}+.")
    if beats:
        return "The face predicts the target better than guessing the mean, beyond what chance explains."
    return "No evidence the face predicts the target better than guessing the mean."


def _report(r: dict) -> str:
    s = r["selected_model"]
    lines = [
        f"# Face photo vs {r['target']}",
        "",
        f"**{r['verdict']}**",
        "",
        "| | |",
        "|---|---|",
        f"| Nights (canonical, passed Capture Quality) | {r['photos']} ({r['dropped_unusable']} dropped) |",
        f"| Feature families | {', '.join(r['families'])} |",
        f"| LLM signals from | {r['signals_scoring_run'] or 'not used (no single Scoring Run covers 80% of nights)'} |",
        f"| Candidates searched | {r['candidates_searched']} |",
        f"| **Nested leave-one-out MAE** | **{r['nested_loo_mae']}** points |",
        f"| Guess-the-mean MAE | {r['baseline_mae_predict_mean']} points |",
        f"| Improvement | {r['improvement_points']} points |",
        f"| Permutation p ({r['permutations']} shuffles) | {r['permutation_p']} |",
        f"| Spearman, prediction vs actual | {r['nested_spearman']} |",
        "",
        "The nested MAE is the honest number: each night was predicted by a search that never saw it.",
        f"The model picked on all nights is `{s['candidate']}`; its own leave-one-out MAE "
        f"({s['inner_loo_mae_optimistic']}) is optimistic because it won a search over the same nights.",
        "",
        "## What the search kept picking",
        "",
        *[f"- {name}: {count} of {r['photos']} folds" for name, count in list(r["outer_fold_picks"].items())[:8]],
        "",
        "## Each measure against the target (Spearman)",
        "",
        *[f"- {k}: {v}" for k, v in sorted(r["feature_spearman"].items(), key=lambda kv: -abs(np.nan_to_num(kv[1])))],
        "",
    ]
    return "\n".join(lines)
