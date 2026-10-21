"""Autoresearch for the Sleep Model: choose Signals, fit weights, write the model the app ships.

A Sleep Prediction is the Sleep Model's starting value plus one Contribution per Signal:

    contribution = weight * clamp((value - personal_baseline) / typical_deviation, -3, 3)

so each Contribution is "points per typical day-to-day difference" and the explanation is exact.

The search runs in three steps, each answerable with little data:

1. Reliability. A Signal that changes between photos taken minutes apart is measuring noise.
   Photos are grouped into sessions (taken within two hours of each other) and each candidate's
   intraclass correlation says how much of its spread is between sessions rather than within one.
2. Lighting robustness. Every photo is re-measured darker, brighter, warmer and cooler. A Signal
   that moves more under those shifts than it does between days would read the light, not the face.
3. Weights. Each facial cue gets a prior weight from published facial signs of sleep loss
   (drooping eyelids, darker under-eyes, redder eyes, paler skin, drooping mouth corners). With
   enough usable nights the weights move toward the user's WHOOP Sleep Performance, by an amount
   chosen with nested leave-one-out so the reported error is on nights the fit never saw.

Only the best variant of each cue is kept, so the explanation never double-counts one feature.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

from face_pipeline import dataset, measure
from face_pipeline.config import Config
from face_pipeline.photos import Photo

MODEL_PATH = measure.REPO / "FaceRecovery" / "Analysis" / "SleepModel.json"
MODEL_VERSION = "s1"

SESSION_GAP = timedelta(hours=2)
CONTRIBUTION_CLAMP = 3.0  # typical deviations; one wild measurement cannot swing the prediction
MIN_ICC = 0.3
MAX_LIGHT_SENSITIVITY = 1.0
MIN_NIGHTS_TO_FIT = 8
BASELINE_WINDOW = 14
MIN_BASELINE = 3
LAMBDAS = [1.0, 3.0, 10.0, 30.0, 100.0, float("inf")]  # inf = keep the prior
STARTING_VALUE_NIGHTS = 90


@dataclass(frozen=True)
class Candidate:
    signal: str
    sign: int  # +1 when a higher value goes with better sleep
    higher: str  # plain words for a value above the user's usual
    lower: str


@dataclass(frozen=True)
class Cue:
    name: str  # shown to the user
    prior_points: float  # points per typical deviation, from the literature's rough ordering
    candidates: tuple[Candidate, ...]


# Signs and rough sizes from studies of how sleep-deprived faces look (e.g. Sundelin et al.,
# SLEEP 2013: hanging eyelids, darker circles and redder eyes were rated most). Sizes are a
# starting point only; the fit decides how much the user's own nights move them.
CUES = (
    Cue("Eyelid opening", 4, (
        Candidate("eye_aperture", +1, "eyes more open", "eyes less open"),
        Candidate("eye_height", +1, "eyes more open", "eyes less open"),
        Candidate("eye_opening_edges", +1, "eyes more open", "eyes less open"),
    )),
    Cue("Upper eyelid position", 2, (
        Candidate("brow_gap", -1, "upper eyelids lower", "upper eyelids higher"),
    )),
    Cue("Darkness under the eyes", 4, (
        Candidate("under_eye_shadow", -1, "darker under the eyes", "lighter under the eyes"),
        Candidate("under_eye_contrast", -1, "darker under the eyes", "lighter under the eyes"),
    )),
    Cue("Blue tint under the eyes", 2, (
        Candidate("under_eye_blue", -1, "bluer under the eyes", "less blue under the eyes"),
    )),
    Cue("Redness of the eyes", 3, (
        Candidate("sclera_redness", -1, "redder eyes", "whiter eyes"),
        Candidate("sclera_vs_skin_redness", -1, "redder eyes", "whiter eyes"),
    )),
    Cue("Skin colour", 2, (
        Candidate("skin_chroma", +1, "more colour in the skin", "paler skin"),
    )),
    Cue("Mouth corners", 2, (
        Candidate("mouth_corner_droop", -1, "mouth corners lower", "mouth corners higher"),
    )),
    Cue("Face fullness", 1, (
        Candidate("face_width", -1, "face looks fuller", "face looks slimmer"),
    )),
)

PERTURBATIONS = {
    "darker": (0.6, (1.0, 1.0, 1.0)),
    "brighter": (1.6, (1.0, 1.0, 1.0)),
    "warmer": (1.0, (1.12, 1.0, 0.85)),
    "cooler": (1.0, (0.88, 1.0, 1.15)),
}


# ---------------------------------------------------------------- statistics

def icc(groups: list[list[float]]) -> float:
    """One-way random-effects ICC(1) for unequal group sizes: the share of variance that is
    between groups. Single-photo sessions add to the between-session spread only."""
    groups = [g for g in groups if g]
    k, n = len(groups), sum(len(g) for g in groups)
    if k < 2 or n - k < 1:
        return float("nan")
    values = np.concatenate([np.asarray(g, dtype=float) for g in groups])
    grand = values.mean()
    msb = sum(len(g) * (np.mean(g) - grand) ** 2 for g in groups) / (k - 1)
    msw = sum(((np.asarray(g) - np.mean(g)) ** 2).sum() for g in groups) / (n - k)
    n0 = (n - sum(len(g) ** 2 for g in groups) / n) / (k - 1)
    denominator = msb + (n0 - 1) * msw
    return float((msb - msw) / denominator) if denominator > 0 else float("nan")


def between_session_sd(groups: list[list[float]]) -> float:
    means = [float(np.mean(g)) for g in groups if g]
    return float(np.std(means, ddof=1)) if len(means) > 1 else float("nan")


def fit_weights(z: np.ndarray, y: np.ndarray, start: float, prior: np.ndarray, lam: float) -> np.ndarray:
    """Weights minimising squared error plus lam * |w - prior|^2, with the starting value fixed.
    lam = inf returns the prior unchanged."""
    if np.isinf(lam) or len(y) == 0:
        return prior.copy()
    a = z.T @ z + lam * np.eye(z.shape[1])
    return np.linalg.solve(a, z.T @ (y - start) + lam * prior)


def predict(z: np.ndarray, start: float, w: np.ndarray) -> np.ndarray:
    return np.clip(start + z @ w, 0, 100)


def choose_lambda(z: np.ndarray, y: np.ndarray, start: float, prior: np.ndarray, rows: np.ndarray) -> float:
    best, best_err = float("inf"), float("inf")
    for lam in LAMBDAS:
        errors = []
        for i in rows:
            train = rows[rows != i]
            w = fit_weights(z[train], y[train], start, prior, lam)
            errors.append(abs(predict(z[i:i + 1], start, w)[0] - y[i]))
        err = float(np.mean(errors))
        if err < best_err - 1e-9:
            best, best_err = lam, err
    return best


def nested_errors(z: np.ndarray, y: np.ndarray, start: float, prior: np.ndarray) -> np.ndarray:
    """Each night predicted by weights whose strength was chosen without it."""
    rows = np.arange(len(y))
    errors = np.empty(len(y))
    for i in rows:
        train = rows[rows != i]
        lam = choose_lambda(z, y, start, prior, train)
        w = fit_weights(z[train], y[train], start, prior, lam)
        errors[i] = abs(predict(z[i:i + 1], start, w)[0] - y[i])
    return errors


# ---------------------------------------------------------------- photos

def sessions(photos: list[Photo]) -> list[list[Photo]]:
    """Photos taken within SESSION_GAP of a session's first photo share it; undated photos are
    sessions of one."""
    dated = sorted((p for p in photos if p.captured_at), key=lambda p: p.captured_at)
    out: list[list[Photo]] = []
    for p in dated:
        if out and p.captured_at - out[-1][0].captured_at <= SESSION_GAP:
            out[-1].append(p)
        else:
            out.append([p])
    return out + [[p] for p in photos if not p.captured_at]


def perturb(path: Path, kind: str, out: Path) -> Path:
    gain, tint = PERTURBATIONS[kind]
    target = out / f"{path.stem}-{kind}.jpg"
    if not target.exists():
        with Image.open(path) as img:
            rgb = np.asarray(ImageOps.exif_transpose(img).convert("RGB"), dtype=float) / 255
        linear = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
        linear = np.clip(linear * gain * np.asarray(tint), 0, 1)
        srgb = np.where(linear <= 0.0031308, 12.92 * linear, 1.055 * linear ** (1 / 2.4) - 0.055)
        target.parent.mkdir(parents=True, exist_ok=True)
        Image.fromarray((srgb * 255).round().astype(np.uint8)).save(target, quality=95)
    return target


def measurement_version() -> str:
    match = re.search(r'currentVersion = "([^"]+)"', measure.APP_SOURCE.read_text())
    return match.group(1) if match else "unknown"


# ---------------------------------------------------------------- driver

def run(cfg: Config, photos: list[Photo], sleeps: list[dict]) -> dict:
    work = cfg.research_dir
    results = measure.measure([p.path for p in photos], work)
    ok = {p: results[p.path]["measurement"] for p in photos if "measurement" in results[p.path]}

    # Reliability uses every photo the app would accept apart from glasses: glasses change the
    # level of a Signal, not how consistently it is measured within a session.
    reliable = {p: m for p, m in ok.items()
                if all("glasses" in problem for problem in m["quality"]["problems"])}
    groups = [[p for p in s if p in reliable] for s in sessions(list(reliable))]
    groups = [g for g in groups if g]

    perturbed_paths = {(p, k): perturb(p.path, k, work / "perturbed") for p in reliable for k in PERTURBATIONS}
    perturbed = measure.measure(list(perturbed_paths.values()), work)

    table, chosen = [], []
    for cue in CUES:
        scored = []
        for c in cue.candidates:
            values = [[reliable[p]["signals"].get(c.signal, np.nan) for p in g] for g in groups]
            values = [[v for v in g if np.isfinite(v)] for g in values]
            sd = between_session_sd(values)
            shifts = []
            for p, m in reliable.items():
                base = m["signals"].get(c.signal)
                for k in PERTURBATIONS:
                    other = perturbed[perturbed_paths[(p, k)]].get("measurement")
                    if base is not None and other and c.signal in other["signals"]:
                        shifts.append(abs(other["signals"][c.signal] - base))
            sensitivity = float(np.median(shifts)) / sd if shifts and sd > 0 else float("nan")
            reliability = icc(values)
            row = {"cue": cue.name, "signal": c.signal, "icc": reliability, "light_sensitivity": sensitivity,
                   "typical_deviation": sd, "sessions": len([g for g in values if g]),
                   "photos": sum(len(g) for g in values)}
            row["score"] = (reliability if np.isfinite(reliability) else -1) - (
                sensitivity if np.isfinite(sensitivity) else 9)
            row["passes"] = bool(np.isfinite(reliability) and reliability >= MIN_ICC
                                 and np.isfinite(sensitivity) and sensitivity <= MAX_LIGHT_SENSITIVITY)
            scored.append((row, c))
            table.append(row)
        best_row, best = max(scored, key=lambda rc: rc[0]["score"])
        best_row["chosen"] = best_row["passes"]
        if best_row["passes"]:
            chosen.append((cue, best, best_row))

    start, start_nights = _starting_value(sleeps)
    fit = _fit(cfg, ok, chosen, sleeps, start)
    model = _model(chosen, start, start_nights, fit)
    MODEL_PATH.write_text(json.dumps(model, indent=2) + "\n")
    examples = _examples(ok, model)
    report = _report(table, model, fit, examples, len(photos), len(ok), len(reliable), len(groups))
    work.mkdir(parents=True, exist_ok=True)
    (work / "autoresearch_report.md").write_text(report)
    (work / "autoresearch_candidates.json").write_text(json.dumps(table, indent=2, default=float))
    return {"model": model, "fit": fit, "candidates": table, "report": str(work / "autoresearch_report.md")}


def _starting_value(sleeps: list[dict]) -> tuple[float, int]:
    """Mean WHOOP Sleep Performance of the most recent main sleeps: what to predict for a face
    that looks exactly like its Personal Baseline."""
    main = sorted((s for s in sleeps if not s.get("nap") and (s.get("score") or {}).get("sleep_performance_percentage")
                   is not None), key=lambda s: s["end"])[-STARTING_VALUE_NIGHTS:]
    values = [s["score"]["sleep_performance_percentage"] for s in main]
    return (round(float(np.mean(values)), 1), len(values)) if values else (70.0, 0)


def _fit(cfg: Config, ok: dict[Photo, dict], chosen: list, sleeps: list[dict], start: float) -> dict:
    """Pairs usable scans with WHOOP Sleep Performance and fits the weights if there are enough."""
    by_id = {s["id"]: s for s in sleeps}
    nights: dict[str, tuple[Photo, dict]] = {}
    for p, m in sorted(((p, m) for p, m in ok.items() if p.captured_at and m["quality"]["usable"]),
                       key=lambda pm: pm[0].captured_at):
        candidates = [s for s in sleeps if not s.get("nap") and s.get("end")
                      and dataset.parse_ts(s["end"]) - dataset.WAKE_TOLERANCE <= p.captured_at]
        if not candidates:
            continue
        sleep = max(candidates, key=lambda s: dataset.parse_ts(s["end"]))
        hours = (p.captured_at - dataset.parse_ts(sleep["end"])).total_seconds() / 3600
        perf = (sleep.get("score") or {}).get("sleep_performance_percentage")
        if hours <= cfg.max_hours_after_wake and perf is not None and sleep["id"] not in nights:
            nights[sleep["id"]] = (p, m)  # earliest usable photo per night: the Canonical Scan

    ordered = sorted(nights.items(), key=lambda kv: kv[1][0].captured_at)
    signals = [c.signal for _, c, _ in chosen]
    sds = np.array([row["typical_deviation"] for _, _, row in chosen])
    prior = np.array([cue.prior_points * c.sign for cue, c, _ in chosen])
    z_rows, y = [], []
    for i, (sleep_id, (p, m)) in enumerate(ordered):
        history = [ordered[j][1][1]["signals"] for j in range(max(0, i - BASELINE_WINDOW), i)]
        if len(history) < MIN_BASELINE:
            continue  # Baseline Forming: no personal baseline to deviate from yet
        baseline = np.array([np.median([h[s] for h in history if s in h]) for s in signals])
        values = np.array([m["signals"].get(s, np.nan) for s in signals])
        z_rows.append(np.clip(np.nan_to_num((values - baseline) / sds), -CONTRIBUTION_CLAMP, CONTRIBUTION_CLAMP))
        y.append(by_id[sleep_id]["score"]["sleep_performance_percentage"])

    z = np.array(z_rows).reshape(len(z_rows), len(signals))
    y = np.array(y, dtype=float)
    result = {"usable_nights": len(nights), "nights_with_baseline": len(y), "lambda": float("inf"),
              "weights": prior.tolist(), "prior": prior.tolist()}
    if len(y) < MIN_NIGHTS_TO_FIT or not signals:
        result["method"] = (f"prior only: {len(y)} usable night(s) with a Personal Baseline and WHOOP Sleep "
                            f"Performance; fitting starts at {MIN_NIGHTS_TO_FIT}")
        return result
    lam = choose_lambda(z, y, start, prior, np.arange(len(y)))
    errors = nested_errors(z, y, start, prior)
    prior_errors = np.abs(predict(z, start, prior) - y)
    result.update({
        "method": "prior-anchored fit, strength chosen by leave-one-out",
        "lambda": lam,
        "weights": fit_weights(z, y, start, prior, lam).tolist(),
        "nested_mae": round(float(errors.mean()), 2),
        "prior_only_mae": round(float(prior_errors.mean()), 2),
        "starting_value_mae": round(float(np.abs(start - y).mean()), 2),
    })
    return result


def _model(chosen: list, start: float, start_nights: int, fit: dict) -> dict:
    return {
        "version": MODEL_VERSION,
        "measurementVersion": measurement_version(),
        "fittedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "method": fit["method"],
        "nightsUsed": fit["nights_with_baseline"],
        "startingValue": start,
        "startingValueNights": start_nights,
        "contributionClamp": CONTRIBUTION_CLAMP,
        "signals": [{
            "id": c.signal,
            "name": cue.name,
            "higherMeans": c.higher,
            "lowerMeans": c.lower,
            "typicalDeviation": round(row["typical_deviation"], 6),
            "weight": round(w, 3),
            "priorWeight": cue.prior_points * c.sign,
        } for (cue, c, row), w in zip(chosen, fit["weights"])],
    }


def explain(signals: dict, baseline: dict, model: dict) -> tuple[float, list[dict]]:
    """Sleep Prediction and its Contributions, exactly as the app computes them."""
    contributions = []
    for s in model["signals"]:
        if s["id"] not in signals or s["id"] not in baseline:
            continue
        deviation = (signals[s["id"]] - baseline[s["id"]]) / s["typicalDeviation"]
        clamped = max(-model["contributionClamp"], min(model["contributionClamp"], deviation))
        contributions.append({"id": s["id"], "name": s["name"], "deviation": deviation,
                              "points": s["weight"] * clamped,
                              "words": s["higherMeans"] if deviation > 0 else s["lowerMeans"]})
    total = model["startingValue"] + sum(c["points"] for c in contributions)
    return max(0.0, min(100.0, total)), contributions


def _examples(ok: dict[Photo, dict], model: dict) -> list[str]:
    """Worked explanations for the usable photos, each against the median of the others."""
    usable = [(p, m) for p, m in ok.items() if m["quality"]["usable"]]
    out = []
    for p, m in usable:
        others = [o["signals"] for q, o in usable if q != p]
        if not others:
            continue
        baseline = {s["id"]: float(np.median([o[s["id"]] for o in others if s["id"] in o])) for s in model["signals"]}
        value, parts = explain(m["signals"], baseline, model)
        when = p.captured_at.strftime("%Y-%m-%d %H:%M") if p.captured_at else p.path.name
        lines = [f"**{when}**: Sleep Prediction **{value:.0f}** = starting value {model['startingValue']:.0f}"]
        for c in sorted(parts, key=lambda c: -abs(c["points"])):
            lines.append(f"  - {c['name']}: {c['words']} ({c['deviation']:+.1f} typical differences) "
                         f"→ {c['points']:+.1f}")
        out.append("\n".join(lines))
    return out


def _report(table: list[dict], model: dict, fit: dict, examples: list[str], found: int, measured: int,
            reliable: int, sessions_n: int) -> str:
    def fmt(v: float) -> str:
        return f"{v:.2f}" if isinstance(v, float) and np.isfinite(v) else "-"

    lines = [
        "# Sleep Model autoresearch",
        "",
        f"{found} photos, {measured} with a face, {reliable} acceptable apart from glasses, in {sessions_n} sessions.",
        f"Sleep Model `{model['version']}` on measurement `{model['measurementVersion']}`: {model['method']}.",
        f"Starting value {model['startingValue']} = mean WHOOP Sleep Performance of the last "
        f"{model['startingValueNights']} nights.",
        "",
        "## Candidates",
        "",
        f"Kept when ICC >= {MIN_ICC} (consistent within a session) and light sensitivity <= "
        f"{MAX_LIGHT_SENSITIVITY} (a simulated lighting change moves it less than a typical day does); "
        "the best-scoring variant per cue.",
        "",
        "| Cue | Signal | ICC | Light sensitivity | Sessions | Kept |",
        "|---|---|---|---|---|---|",
        *[f"| {r['cue']} | `{r['signal']}` | {fmt(r['icc'])} | {fmt(r['light_sensitivity'])} | {r['sessions']} | "
          f"{'yes' if r.get('chosen') else ''} |" for r in table],
        "",
        "## Model",
        "",
        "| Signal | Shown as | Points per typical difference | Prior |",
        "|---|---|---|---|",
        *[f"| `{s['id']}` | {s['name']} | {s['weight']:+.2f} | {s['priorWeight']:+.0f} |" for s in model["signals"]],
        "",
    ]
    if "nested_mae" in fit:
        lines += [f"Held-out error {fit['nested_mae']} points vs {fit['starting_value_mae']} for always predicting "
                  f"the starting value and {fit['prior_only_mae']} for the prior alone.", ""]
    lines += ["## Example explanations", "", *(examples or ["No usable photos yet."]), ""]
    return "\n".join(lines)
