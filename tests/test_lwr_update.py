"""
test_lwr_update.py
==================
Unit tests for the LWR density-update step.

Tests use a minimal synthetic road (4 cells, no access points, no
intersection) to verify the discrete update equation:

    rho_next[i] = rho_n[i] + (dt/dx) * (F[i] - F[i+1] + s[i])

in isolation from the full demand model.
"""

import numpy as np
import pytest
from corridor_sim.engine.lwr_model import lwr_model


# ─── Fixture helpers ──────────────────────────────────────────────────────────

def _make_road(fd, sim, Nx=4, n_lanes=2, signal_x=None, boundary_idx=None):
    """Build a minimal synthetic road dict (no access points, no intersections)."""
    dx   = sim['dx']
    Nt   = sim['Nt']
    length = Nx * dx

    x_edges   = np.arange(0, length + dx, dx, dtype=float)
    x_centers = x_edges[:-1] + dx / 2.0

    # Signal: place far out of range by default (no signalised cell)
    sig_x = signal_x if signal_x is not None else length * 10
    sig_cells = np.where(x_centers >= sig_x)[0]
    sig_cell = int(sig_cells[0]) + 1 if len(sig_cells) > 0 else Nx

    signal = {
        'x':             sig_x,
        'green':         45.0,
        'red':           75.0,
        'Qsat_per_lane': 1900.0 / 3600.0,
        'period':        120.0,
        'cell':          sig_cell,
        'Qsat':          (1900.0 / 3600.0) * n_lanes,
    }
    is_signal = np.zeros(Nx, dtype=bool)
    if 1 <= sig_cell <= Nx:
        is_signal[sig_cell - 1] = True

    road_fd = dict(fd)
    road_fd['vf'] = np.full(Nx, 40.0 * sim['mph_to_fts'])

    road = {
        'name':          'TestRoad',
        'idx':           1,
        'length':        length,
        'Nx':            Nx,
        'x_edges':       x_edges,
        'x_centers':     x_centers,
        'N_lanes':       np.full(Nx, n_lanes, dtype=int),
        'FD':            road_fd,
        'signal':        signal,
        'is_signal':     is_signal,
        'boundary_idx':  boundary_idx if boundary_idx else [0, 0],
        'AccessPoints':  [],
        'intersection':  [{'xSegment': [], 'taz_idx_external': []}],
    }
    return road


def _make_zero_demand(Nroads=1, Nzones=1):
    """Demand dict with all flows set to zero (no TAZ activity)."""
    return {
        'V_taz_arrive': np.zeros((Nroads, Nzones)),
        'V_taz_depart': np.zeros((Nroads, Nzones)),
    }


def _make_zone(Nzones=1):
    """TAZ zone dict with flat temporal profiles (uniform hourly distribution)."""
    return {
        'names':    ['Z0'] * Nzones,
        'f_arrive': np.ones((24, Nzones)) / 24.0,
        'f_depart': np.ones((24, Nzones)) / 24.0,
    }


# ─── Tests ───────────────────────────────────────────────────────────────────

class TestLWRDensityUpdate:

    def test_uniform_free_flow_no_source_density_conserved(self, fd, sim_small):
        """
        Uniform density in free-flow with no source/sink terms.
        Mass is conserved: sum(rho_next) * dx ≈ sum(rho_n) * dx.
        (Small boundary losses are expected due to outflow BC.)
        """
        Nx   = 4
        road = _make_road(fd, sim_small, Nx=Nx)
        rho_c = fd['rho_c']
        rho_n = np.full(Nx, rho_c * 0.3)   # uniform, below critical

        sim_small['n'] = 0
        sim_small['h'] = 1

        rho_next, *_ = lwr_model(road, rho_n, _make_zero_demand(), _make_zone(),
                                  sim_small)
        # Conservation: interior cells should see very small change
        # (boundary cells lose vehicles to outflow)
        interior_change = np.abs(rho_next[1:-1] - rho_n[1:-1])
        assert interior_change.max() < rho_c * 0.01, (
            f"Interior density changed unexpectedly: {interior_change}")

    def test_source_injection_increases_density(self, fd, sim_small):
        """
        A positive source at a specific cell increases density by (dt/dx)*s.
        """
        Nx   = 4
        road = _make_road(fd, sim_small, Nx=Nx)
        rho_n = np.zeros(Nx)

        # Inject a source at cell index 1 (0-based) via access point
        s_rate = 0.001   # [veh/s]
        road['AccessPoints'] = [{
            'taz_idx':  1,
            'roadName': 'TestRoad',
            'xLocal':   [sim_small['dx'] * 1.5],   # cell 2 (1-based)
            'xSegment': [2],                         # 1-based
            'split':    np.array([1.0]),
        }]
        demand = {
            'V_taz_arrive': np.zeros((1, 1)),
            'V_taz_depart': np.array([[s_rate * 3600]]),  # [veh/day]
        }
        zone = {
            'names':    ['Z0'],
            'f_arrive': np.ones((24, 1)) / 24.0,
            'f_depart': np.ones((24, 1)) / 24.0,
        }
        sim_small['n'] = 0
        sim_small['h'] = 1

        rho_next, _, _, _, _, s_n = lwr_model(road, rho_n, demand, zone, sim_small)

        # Cell 2 (index 1) should have received vehicles
        assert s_n[1] > 0, "Expected positive source at injection cell"
        assert rho_next[1] > 0, "Density should increase at injection cell"

    def test_sink_removal_decreases_density(self, fd, sim_small):
        """
        A negative source (sink) at a cell should decrease density.
        """
        Nx    = 4
        road  = _make_road(fd, sim_small, Nx=Nx)
        rho_n = np.full(Nx, fd['rho_c'] * 0.5)

        # Arrival sink at cell 3 (1-based)
        road['AccessPoints'] = [{
            'taz_idx':  1,
            'roadName': 'TestRoad',
            'xLocal':   [sim_small['dx'] * 2.5],
            'xSegment': [3],
            'split':    np.array([1.0]),
        }]
        demand = {
            'V_taz_arrive': np.array([[0.001 * 3600]]),   # arrivals > departures
            'V_taz_depart': np.zeros((1, 1)),
        }
        zone = {
            'names':    ['Z0'],
            'f_arrive': np.ones((24, 1)) / 24.0,
            'f_depart': np.ones((24, 1)) / 24.0,
        }
        sim_small['n'] = 0
        sim_small['h'] = 1

        _, _, _, _, _, s_n = lwr_model(road, rho_n, demand, zone, sim_small)
        assert s_n[2] < 0, "Expected negative source (sink) at arrival cell"

    def test_density_never_goes_negative(self, fd, sim_small):
        """
        LWR update must clamp density to zero — never produce negative values.
        """
        Nx    = 4
        road  = _make_road(fd, sim_small, Nx=Nx)
        rho_n = np.zeros(Nx)   # start empty

        # Large outflow sink
        road['AccessPoints'] = [{
            'taz_idx':  1,
            'roadName': 'TestRoad',
            'xLocal':   [sim_small['dx'] * 1.5],
            'xSegment': [2],
            'split':    np.array([1.0]),
        }]
        demand = {
            'V_taz_arrive': np.array([[1e6]]),   # huge sink
            'V_taz_depart': np.zeros((1, 1)),
        }
        zone = {
            'names':    ['Z0'],
            'f_arrive': np.ones((24, 1)) / 24.0,
            'f_depart': np.ones((24, 1)) / 24.0,
        }
        sim_small['n'] = 0
        sim_small['h'] = 1

        rho_next, *_ = lwr_model(road, rho_n, demand, zone, sim_small)
        assert (rho_next >= 0).all(), f"Negative density detected: {rho_next}"

    def test_signal_red_caps_flux(self, fd, sim_small):
        """
        During red phase (t=0, period=120s, green=45s → red at t≥45),
        signal at cell 2 caps the flux crossing into cell 3.
        With sim time = 0, period=120, green=45 → 0 < 45 → GREEN.
        Advance t to 50 s (> green time=45) → RED → Qsat is the cap.
        """
        Nx = 4
        # Set signal at cell 2 (x_centers[1])
        signal_x = sim_small['dx'] * 1.5   # lands in cell 2
        road = _make_road(fd, sim_small, Nx=Nx, n_lanes=2, signal_x=signal_x)

        rho_c = fd['rho_c']
        rho_n = np.full(Nx, rho_c * 0.9)   # congested — would produce high flux

        # t[0]=0 → 0 < 45 → green, flux uncapped
        sim_small['n'] = 0
        sim_small['h'] = 1
        _, F_green, *_ = lwr_model(road, rho_n, _make_zero_demand(),
                                    _make_zone(), sim_small)

        # Advance to t=50 → 50 mod 120 = 50 > 45 → RED
        sim_small['t'] = np.arange(0, sim_small['T_end'] + sim_small['dt'],
                                    sim_small['dt']) + 50.0
        sim_small['n'] = 0
        _, F_red, *_ = lwr_model(road, rho_n, _make_zero_demand(),
                                  _make_zone(), sim_small)

        Qsat = road['signal']['Qsat']
        sig_cell = road['signal']['cell']   # 1-based
        # During red: flux at signal interface = 0 (g_n * Qsat = 0)
        assert F_red[sig_cell] == pytest.approx(0.0, abs=1e-12), (
            f"Expected zero flux during red; got {F_red[sig_cell]}")

    def test_cfl_condition_stability(self, fd, sim_small):
        """
        With dt=1s, dx=500ft, vf≈58.7 ft/s → CFL = vf*dt/dx ≈ 0.117 << 1.
        Density should remain bounded within [0, rho_j].
        """
        Nx    = 4
        rho_j = fd['rho_j']
        road  = _make_road(fd, sim_small, Nx=Nx)
        rho_n = np.full(Nx, rho_j * 0.8)   # congested initial condition

        sim_small['n'] = 0
        sim_small['h'] = 1
        rho_next, *_ = lwr_model(road, rho_n, _make_zero_demand(),
                                   _make_zone(), sim_small)

        assert (rho_next >= 0).all()
        assert (rho_next <= rho_j * 1.01).all(), (
            f"Density exceeded jam density: {rho_next.max()}")
