"""
test_temporal_profiles.py
==========================
Unit tests for parametric_peaks() — the Gaussian hourly temporal profile
used to distribute daily demand across 24 hours.
"""

import numpy as np
import pytest
from corridor_sim.engine.helpers import parametric_peaks


class TestParametricPeaks:

    def test_normalised_profile_sums_to_one(self):
        """After normalisation, 24-element profile sums to 1.0."""
        params = {'w': 1, 'mu': 8.0, 'sigma': 2.0}
        f_raw = parametric_peaks(params)
        f_norm = f_raw / f_raw.sum()
        assert f_norm.sum() == pytest.approx(1.0, rel=1e-9)

    def test_profile_has_24_elements(self):
        """Output must always have exactly 24 elements."""
        params = {'w': 1, 'mu': 12.0, 'sigma': 3.0}
        f = parametric_peaks(params)
        assert len(f) == 24

    def test_peak_location_matches_mu(self):
        """
        argmax of profile should equal mu rounded to the nearest integer,
        within ±1 hour (Gaussian centre).
        """
        for mu in [7.0, 12.0, 17.0, 22.0]:
            params = {'w': 1, 'mu': mu, 'sigma': 1.5}
            f = parametric_peaks(params)
            # Hours are 1-indexed: h[k] = k+1 for k in range(24)
            peak_hour = np.argmax(f) + 1   # 1-based
            assert abs(peak_hour - round(mu)) <= 1, (
                f"Peak at hour {peak_hour} but mu={mu}")

    def test_all_values_non_negative(self):
        """Gaussian is always non-negative."""
        params = {'w': 1, 'mu': 10.0, 'sigma': 3.0}
        f = parametric_peaks(params)
        assert (f >= 0).all()

    def test_wider_sigma_gives_flatter_profile(self):
        """
        Larger sigma → more mass spread across hours → lower normalised peak.
        Compare normalised profiles: narrow peak > wide peak (after /sum).
        """
        params_narrow = {'w': 1, 'mu': 12.0, 'sigma': 1.0}
        params_wide   = {'w': 1, 'mu': 12.0, 'sigma': 4.0}
        f_narrow = parametric_peaks(params_narrow)
        f_wide   = parametric_peaks(params_wide)
        # Both peak at exp(0)=1.0 (unnormalised), so compare normalised max
        assert (f_narrow / f_narrow.sum()).max() > (f_wide / f_wide.sum()).max()

    def test_two_peaks_both_visible(self):
        """
        A bimodal profile (AM + PM peaks) should show two local maxima.
        """
        params = {'w': [1, 1], 'mu': [8.0, 17.0], 'sigma': [1.5, 1.5]}
        f = parametric_peaks(params)
        f_norm = f / f.sum()
        # Both peaks should contribute meaningfully
        am_mass = f_norm[5:11].sum()    # hours 6–11
        pm_mass = f_norm[14:20].sum()   # hours 15–20
        assert am_mass > 0.15, f"AM peak too small: {am_mass:.3f}"
        assert pm_mass > 0.15, f"PM peak too small: {pm_mass:.3f}"

    def test_very_narrow_sigma_concentrates_at_peak(self):
        """
        Extremely narrow sigma → nearly all mass at the peak hour.
        """
        params = {'w': 1, 'mu': 9.0, 'sigma': 0.1}
        f = parametric_peaks(params)
        f_norm = f / f.sum()
        peak_idx = np.argmax(f_norm)
        assert f_norm[peak_idx] > 0.9, (
            f"Expected >90% at peak, got {f_norm[peak_idx]:.3f}")

    def test_weight_scales_output(self):
        """
        Doubling the weight doubles every value in the raw profile.
        """
        params1 = {'w': 1, 'mu': 10.0, 'sigma': 2.0}
        params2 = {'w': 2, 'mu': 10.0, 'sigma': 2.0}
        f1 = parametric_peaks(params1)
        f2 = parametric_peaks(params2)
        np.testing.assert_allclose(f2, 2 * f1, rtol=1e-12)
