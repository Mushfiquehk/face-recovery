import numpy as np
import pytest

from face_pipeline import research


def test_closed_form_loo_matches_refitting():
    rng = np.random.default_rng(0)
    x, y = rng.normal(size=(15, 3)), rng.normal(size=15)
    fast = research.loo_errors(x, y, alpha=3.0)
    # Same standardisation as loo_errors: fixed on all rows.
    z = np.concatenate([np.ones((15, 1)), (x - x.mean(axis=0)) / x.std(axis=0)], axis=1)
    penalty = 3.0 * np.eye(4)
    penalty[0, 0] = 0
    for i in range(15):
        train = np.delete(np.arange(15), i)
        beta = np.linalg.solve(z[train].T @ z[train] + penalty, z[train].T @ y[train])
        assert fast[i] == pytest.approx(abs(y[i] - z[i] @ beta))


def synthetic(n, signal, seed=1):
    rng = np.random.default_rng(seed)
    m = rng.normal(size=(n, len(research.MEASURES)))
    planted = research.MEASURES.index("under_eye_shadow")
    y = 65 + signal * 15 * m[:, planted] + rng.normal(scale=15 * (1 - signal) + 1, size=n)
    return {"measures": m}, y


def test_nested_search_finds_a_planted_signal():
    data, y = synthetic(40, signal=0.8)
    pool = research.candidates(data)
    pred, base, chosen = research.nested_loo(data, y, pool)
    mae = np.abs(pred - y).mean()
    assert mae < 0.6 * np.abs(base - y).mean()
    assert sum("under_eye_shadow" in c.columns for c in chosen) > 30
    assert research.permutation_p(data, y, pool, mae, permutations=20, seed=0) < 0.1


def test_noise_does_not_beat_the_mean_after_nesting():
    data, y = synthetic(30, signal=0.0, seed=3)
    pool = research.candidates(data)
    pred, base, _ = research.nested_loo(data, y, pool)
    # The search alone always finds *something*; nesting must not turn that into a win.
    assert np.abs(pred - y).mean() > 0.9 * np.abs(base - y).mean()


def test_column_with_no_values_is_harmless():
    x = np.array([[1.0, np.nan], [2.0, np.nan], [3.0, np.nan], [4.0, np.nan]])
    y = np.array([1.0, 2.0, 3.0, 4.0])
    assert np.isfinite(research.loo_errors(x, y, 1.0)).all()
    assert np.isfinite(research.ridge_predict(research.ridge_fit(x, y, 1.0), x)).all()


def test_run_refuses_tiny_datasets(tmp_path):
    (tmp_path / "dataset.csv").write_text(
        "image,local_date,is_canonical,usable,whoop_sleep_performance_percentage\n"
        "images/a.jpg,2026-09-01,True,,80\n")
    with pytest.raises(SystemExit, match="at least"):
        research.run(tmp_path, tmp_path / "out", "sleep")
