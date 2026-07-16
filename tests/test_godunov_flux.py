"""
test_godunov_flux.py
====================
Unit tests for the Godunov numerical flux function.

The Godunov flux for the Greenshields model is:
    F = N_lanes * min(D(rho_up), S(rho_down))
where
    D(rho) = Q(rho_c, vf)   if rho <= rho_c   (supply-limited demand)
           = Q(rho,   vf)   otherwise
    S(rho) = Q(rho_c, vf)   if rho <= rho_c   (unrestricted supply)
           = Q(rho,   vf)   otherwise

All expected values are computed analytically.
"""

import pytest
import numpy as np
from corridor_sim.engine.lwr_model import godunov_flux


# ─── Helpers ─────────────────────────────────────────────────────────────────

def Q(rho, vf, rho_j):
    return vf * rho * (1.0 - rho / rho_j)


# ─── Test cases ──────────────────────────────────────────────────────────────

class TestGodunovFlux:

    def test_free_flow_flux_equals_upstream_demand(self, fd, vf):
        """
        Both densities below critical → free-flow regime.
        Flux = N_lanes * Q(rho_up, vf)  (demand-limited).
        """
        rho_c  = fd['rho_c']
        rho_j  = fd['rho_j']
        rho_up = rho_c * 0.5     # well below critical
        rho_dn = rho_c * 0.3     # also below critical
        n      = 2

        F = godunov_flux(fd, vf, rho_up, rho_dn, n)
        expected = n * Q(rho_up, vf, rho_j)
        assert abs(F - expected) < 1e-12

    def test_congested_flux_equals_downstream_supply(self, fd, vf):
        """
        Both densities above critical → congested regime.
        Flux = N_lanes * Q(rho_dn, vf)  (supply-limited).
        """
        rho_c  = fd['rho_c']
        rho_j  = fd['rho_j']
        rho_up = rho_c * 1.5     # above critical
        rho_dn = rho_c * 1.8     # above critical
        n      = 3

        F = godunov_flux(fd, vf, rho_up, rho_dn, n)
        expected = n * Q(rho_dn, vf, rho_j)
        assert abs(F - expected) < 1e-12

    def test_capacity_flux_at_critical_density(self, fd, vf):
        """
        Both densities exactly at critical → flux equals capacity Q(rho_c, vf).
        """
        rho_c = fd['rho_c']
        rho_j = fd['rho_j']
        n     = 2

        F = godunov_flux(fd, vf, rho_c, rho_c, n)
        expected = n * Q(rho_c, vf, rho_j)
        assert abs(F - expected) < 1e-12

    def test_zero_upstream_density_gives_zero_flux(self, fd, vf):
        """
        Empty road upstream → no vehicles to propagate → flux = 0.
        """
        rho_dn = fd['rho_c'] * 0.5
        F = godunov_flux(fd, vf, 0.0, rho_dn, 1)
        assert F == pytest.approx(0.0, abs=1e-12)

    def test_jam_density_downstream_gives_zero_flux(self, fd, vf):
        """
        Downstream at jam density → road is blocked → supply = 0 → flux = 0.
        """
        rho_j  = fd['rho_j']
        rho_up = fd['rho_c'] * 0.8
        F = godunov_flux(fd, vf, rho_up, rho_j, 1)
        assert F == pytest.approx(0.0, abs=1e-10)

    def test_flux_scales_linearly_with_lanes(self, fd, vf):
        """
        Flux must scale exactly with number of lanes.
        """
        rho_up = fd['rho_c'] * 0.4
        rho_dn = fd['rho_c'] * 0.3
        F1 = godunov_flux(fd, vf, rho_up, rho_dn, 1)
        F3 = godunov_flux(fd, vf, rho_up, rho_dn, 3)
        assert abs(F3 - 3 * F1) < 1e-12

    def test_flux_non_negative(self, fd, vf):
        """Flux must be non-negative for any valid density pair."""
        rho_j = fd['rho_j']
        for rho_up in np.linspace(0, rho_j, 10):
            for rho_dn in np.linspace(0, rho_j, 10):
                F = godunov_flux(fd, vf, rho_up, rho_dn, 2)
                assert F >= -1e-14, (
                    f"Negative flux {F} for rho_up={rho_up}, rho_dn={rho_dn}")

    def test_mixed_regime_uses_min(self, fd, vf):
        """
        Upstream free-flow, downstream congested → min(D_up, S_down).
        D_up  = Q(rho_up, vf)   since rho_up <= rho_c
        S_down = Q(rho_dn, vf)  since rho_dn >  rho_c
        Flux = N_lanes * min(D_up, S_down).
        """
        rho_c  = fd['rho_c']
        rho_j  = fd['rho_j']
        rho_up = rho_c * 0.6    # <= rho_c  → D = Q(rho_up)
        rho_dn = rho_c * 1.4    # >  rho_c  → S = Q(rho_dn)
        n      = 2

        D = Q(rho_up, vf, rho_j)
        S = Q(rho_dn, vf, rho_j)
        expected = n * min(D, S)

        F = godunov_flux(fd, vf, rho_up, rho_dn, n)
        assert abs(F - expected) < 1e-12
