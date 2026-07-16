"""
conftest.py — shared pytest fixtures for the corridor simulation test suite.

All fixtures use only synthetic, in-memory data.
No project xlsx files are loaded here.
"""

import numpy as np
import pytest

# ─── Fundamental diagram fixture ─────────────────────────────────────────────

@pytest.fixture
def fd():
    """Greenshields fundamental diagram with well-known parameters."""
    rho_j = 1.0 / 18.0          # [veh/ft/lane]  jam density
    rho_c = rho_j / 2.0         # critical density
    return {
        'model': 'Greenshields',
        'rho_j': rho_j,
        'rho_c': rho_c,
        'Q': lambda rho, vf: vf * rho * (1.0 - rho / rho_j),
    }


@pytest.fixture
def vf():
    """Free-flow speed: 40 mph → ft/s."""
    return 40.0 * 5280.0 / 3600.0


@pytest.fixture
def sim_small():
    """Minimal simulation settings for a 4-cell, 10-step corridor."""
    dt  = 1.0    # [s]
    dx  = 500.0  # [ft]
    Nt  = 10
    T   = (Nt - 1) * dt
    return {
        'dt':         dt,
        'dx':         dx,
        'T_end':      T,
        't':          np.arange(0, T + dt, dt),
        'Nt':         Nt,
        'mph_to_fts': 5280.0 / 3600.0,
        'n':          0,
        'h':          1,
        'mode':       'full',
    }
