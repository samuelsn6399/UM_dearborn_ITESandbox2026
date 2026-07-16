"""
test_initialize_corridor.py
============================
Unit tests for the universal corridor initializer.

All tests use a small synthetic CorridorConfig with no xlsx dependencies.
"""

import numpy as np
import pytest
from corridor_sim.engine.initialize_corridor import (
    CorridorConfig, LaneSegment, SpeedSegment, SignalConfig,
    initialize_corridor,
)


# ─── Fixture: minimal 4-cell corridor ────────────────────────────────────────

@pytest.fixture
def toy_config():
    """
    A 2000 ft corridor with 4 × 500 ft cells.
    Lanes: 0–1000 ft → 2 lanes, 1001–2000 ft → 3 lanes.
    Speed: uniform 40 mph.
    Signal at 1500 ft (cell 3, 1-based).
    """
    return CorridorConfig(
        name='ToyRoad',
        idx=1,
        length=2000.0,
        boundary_idx=[2, 3],
        lane_segments=[
            LaneSegment(x_start=1,    x_end=1000, n_lanes=2),
            LaneSegment(x_start=1001, x_end=2000, n_lanes=3),
        ],
        speed_segments=[
            SpeedSegment(x_start=1, x_end=2000, speed_mph=40.0),
        ],
        signal=SignalConfig(x=1500.0, green=45.0, red=75.0,
                            qsat_per_lane=1900.0/3600.0),
    )


@pytest.fixture
def road(toy_config, fd, sim_small):
    return initialize_corridor(toy_config, sim_small, fd)


# ─── Tests ───────────────────────────────────────────────────────────────────

class TestInitializeCorridor:

    def test_road_keys_present(self, road):
        """All required keys must be present in the road dict."""
        required = [
            'name', 'idx', 'length', 'Nx', 'x_edges', 'x_centers',
            'N_lanes', 'FD', 'signal', 'is_signal', 'boundary_idx',
            'rho', 'F', 'F_desired', 'g', 'g_eff', 's',
        ]
        missing = [k for k in required if k not in road]
        assert not missing, f"Missing keys: {missing}"

    def test_nx_equals_length_over_dx(self, road, sim_small):
        """Nx = length / dx (integer division)."""
        assert road['Nx'] == int(2000 / sim_small['dx'])

    def test_lane_segments_correct(self, road, sim_small):
        """
        Cells with x_centers in [1, 1000] → 2 lanes.
        Cells with x_centers in [1001, 2000] → 3 lanes.
        """
        xc = road['x_centers']
        dx = sim_small['dx']
        for i, xci in enumerate(xc):
            expected = 2 if xci <= 1000 else 3
            assert road['N_lanes'][i] == expected, (
                f"Cell {i} at x={xci}: expected {expected} lanes, "
                f"got {road['N_lanes'][i]}")

    def test_speed_segments_correct(self, road, sim_small):
        """All cells at 40 mph → vf = 40 * mph_to_fts."""
        expected_vf = 40.0 * sim_small['mph_to_fts']
        np.testing.assert_allclose(road['FD']['vf'],
                                    np.full(road['Nx'], expected_vf))

    def test_signal_cell_index(self, road):
        """
        Signal at x=1500 ft.  With dx=500, x_centers=[250,750,1250,1750].
        First center >= 1500 is 1750 → index 3 (0-based) → cell 4 (1-based).
        """
        assert road['signal']['cell'] == 4

    def test_is_signal_flags_exactly_one_cell(self, road):
        """Exactly one cell should be flagged as signalised."""
        assert road['is_signal'].sum() == 1

    def test_is_signal_correct_cell(self, road):
        """The flagged cell must match signal['cell'] (1-based → 0-based)."""
        sig_cell_0based = road['signal']['cell'] - 1
        assert road['is_signal'][sig_cell_0based]

    def test_state_array_shapes(self, road, sim_small):
        """All state arrays must have the expected shapes."""
        Nx = road['Nx']
        Nt = sim_small['Nt']
        assert road['rho'].shape       == (Nx,     Nt)
        assert road['F'].shape         == (Nx + 1, Nt)
        assert road['F_desired'].shape == (2,      Nt)
        assert road['g'].shape         == (1,      Nt - 1)
        assert road['g_eff'].shape     == (Nx,     Nt - 1)
        assert road['s'].shape         == (Nx,     Nt)

    def test_initial_density_low_but_positive(self, road, fd):
        """Initial density should be small positive (0.01 * rho_c)."""
        assert (road['rho'][:, 0] >= 0).all()
        assert (road['rho'][:, 0] <= fd['rho_c']).all()

    def test_signal_qsat_uses_lane_count(self, road, toy_config):
        """
        Qsat = Qsat_per_lane * N_lanes[signal_cell].
        Signal at cell 4 (1-based) → N_lanes = 3 (x_center=1750 > 1000).
        """
        sig_cell = road['signal']['cell'] - 1   # 0-based
        expected_qsat = toy_config.signal.qsat_per_lane * road['N_lanes'][sig_cell]
        assert road['signal']['Qsat'] == pytest.approx(expected_qsat)

    def test_boundary_idx_stored_correctly(self, road, toy_config):
        assert road['boundary_idx'] == toy_config.boundary_idx

    def test_x_centers_length(self, road):
        """x_centers must have length Nx."""
        assert len(road['x_centers']) == road['Nx']

    def test_x_edges_length(self, road):
        """x_edges must have length Nx + 1."""
        assert len(road['x_edges']) == road['Nx'] + 1
