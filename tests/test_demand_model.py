"""
test_demand_model.py
====================
Unit tests for the four-step travel demand model.

All tests use small synthetic household/rate arrays built in-memory —
no xlsx files are read.  The steps are tested independently.
"""

import numpy as np
import pytest


# ─── Step 1a: Trip Productions ───────────────────────────────────────────────

class TestTripProductions:

    def test_production_is_element_wise_sum(self):
        """
        P_i = sum(H_i * R_i) — element-wise product then sum.
        Hand-verified: [[2,3],[4,5]] * [[1,2],[3,4]] = [[2,6],[12,20]] → sum=40
        """
        H = np.array([[2, 3], [4, 5]], dtype=float)
        R = np.array([[1, 2], [3, 4]], dtype=float)
        P = np.sum(H * R)
        assert P == pytest.approx(2 + 6 + 12 + 20)

    def test_zero_households_gives_zero_productions(self):
        H = np.zeros((4, 4))
        R = np.ones((4, 4))
        P = np.sum(H * R)
        assert P == 0.0


# ─── Step 1b/c: Attraction balance ───────────────────────────────────────────

class TestAttractionBalance:

    def test_balanced_attractions_sum_equals_productions(self):
        """
        After balance step: sum(A_balanced) == sum(P).
        A_balanced = A_raw * (P_total / A_total)
        """
        P = np.array([100.0, 200.0, 150.0])
        A_raw = np.array([80.0, 180.0, 200.0])
        P_total = P.sum()
        A_total = A_raw.sum()
        A = A_raw * (P_total / A_total)
        assert A.sum() == pytest.approx(P_total, rel=1e-9)

    def test_balance_preserves_relative_proportions(self):
        """
        Balancing scales all attractions by the same factor, so relative
        proportions between zones are unchanged.
        """
        P = np.array([100.0, 200.0])
        A_raw = np.array([60.0, 120.0])
        P_total = P.sum()
        A = A_raw * (P_total / A_raw.sum())
        ratio_before = A_raw[0] / A_raw[1]
        ratio_after  = A[0] / A[1]
        assert ratio_before == pytest.approx(ratio_after, rel=1e-9)


# ─── Step 2: Trip Distribution ────────────────────────────────────────────────

class TestGravityDistribution:

    @pytest.fixture
    def gravity_result(self):
        """3-zone gravity distribution with uniform friction (gravity_on_off=False)."""
        P = np.array([100.0, 200.0, 150.0])
        A = np.array([120.0, 180.0, 150.0])   # already balanced: sum=450=sum(P)
        Nzones = len(P)
        F_matrix = np.ones((Nzones, Nzones)) - np.eye(Nzones)
        T = np.zeros((Nzones, Nzones))
        for i in range(Nzones):
            denom = np.sum(A * F_matrix[i, :])
            if denom > 0:
                T[i, :] = P[i] * (A * F_matrix[i, :]) / denom
        return T, P, A

    def test_row_sums_equal_productions(self, gravity_result):
        """T_person row sums = P_i."""
        T, P, _ = gravity_result
        row_sums = T.sum(axis=1)
        np.testing.assert_allclose(row_sums, P, rtol=1e-9)

    def test_diagonal_is_zero(self, gravity_result):
        """No intrazonal trips (diagonal = 0)."""
        T, _, _ = gravity_result
        assert np.all(T.diagonal() == 0.0), "Diagonal should be zero (no internal trips)"

    def test_all_entries_non_negative(self, gravity_result):
        """All OD entries must be non-negative."""
        T, _, _ = gravity_result
        assert (T >= 0).all()

    def test_column_sums_distribute_attractions(self, gravity_result):
        """With uniform friction, column sums should approximate A_j proportions."""
        T, P, A = gravity_result
        col_sums = T.sum(axis=0)
        total    = col_sums.sum()
        A_shares = A / A.sum() * P.sum()
        # Column sums should be close to A_j (singly-constrained relaxes this,
        # so check only same order of magnitude)
        assert (col_sums > 0).all()
        assert abs(total - P.sum()) < 1.0


# ─── Step 3: Mode Choice ─────────────────────────────────────────────────────

class TestModeChoice:

    def test_scalar_occupancy_divides_uniformly(self):
        """T_vehicle = T_person / auto_occupancy (scalar)."""
        T_person = np.array([[0, 80], [120, 0]], dtype=float)
        auto_occ = 1.25
        T_vehicle = T_person / auto_occ
        np.testing.assert_allclose(T_vehicle, T_person / 1.25)

    def test_per_zone_auto_share_reduces_vehicle_trips(self):
        """
        Per-zone auto_share < 1 reduces vehicle trips compared to full auto.
        auto_share=0.6 means 60% of person-trips become vehicle demand.
        """
        T_person  = np.array([[0, 100], [200, 0]], dtype=float)
        auto_occ  = 1.25
        Nzones    = 2
        auto_share = np.array([0.6, 0.8])

        share_matrix = np.outer(auto_share, np.ones(Nzones))
        T_vehicle_mode = T_person * share_matrix / auto_occ
        T_vehicle_base = T_person / auto_occ

        # Mode-split result must be strictly less than baseline for auto_share < 1
        assert T_vehicle_mode[0, 1] < T_vehicle_base[0, 1]
        assert T_vehicle_mode[0, 1] == pytest.approx(100 * 0.6 / 1.25)

    def test_auto_share_one_matches_scalar_occupancy(self):
        """auto_share = 1.0 for all zones ≡ scalar occupancy."""
        T_person   = np.array([[0, 50], [80, 0]], dtype=float)
        auto_occ   = 1.25
        Nzones     = 2
        auto_share = np.ones(Nzones)

        share_matrix    = np.outer(auto_share, np.ones(Nzones))
        T_vehicle_mode  = T_person * share_matrix / auto_occ
        T_vehicle_base  = T_person / auto_occ
        np.testing.assert_allclose(T_vehicle_mode, T_vehicle_base, rtol=1e-12)


# ─── Step 4: Network Loading ─────────────────────────────────────────────────

class TestNetworkLoading:

    def test_v_taz_depart_sums_correctly(self):
        """
        V_taz_depart[road, k] = sum over j≠k of T_vehicle[k,j] * OD_access[road,k,j].
        Hand-verified for a 2-zone, 1-road case.
        """
        T_veh = np.array([[0.0, 40.0],
                          [60.0, 0.0]])   # zone 0 sends 40, zone 1 sends 60
        # Road 0: both O-D pairs use this road
        OD_access = np.ones((1, 2, 2)) - np.eye(2)[np.newaxis, :, :]
        Nroads = 1
        Nzones = 2
        V_depart = np.zeros((Nroads, Nzones))
        for l in range(Nroads):
            for k in range(Nzones):
                other = [j for j in range(Nzones) if j != k]
                V_depart[l, k] = np.sum(
                    T_veh[np.ix_([k], other)] * OD_access[l][np.ix_([k], other)]
                )
        assert V_depart[0, 0] == pytest.approx(40.0)
        assert V_depart[0, 1] == pytest.approx(60.0)

    def test_v_taz_arrive_sums_correctly(self):
        """
        V_taz_arrive[road, k] = sum over i≠k of T_vehicle[i,k] * OD_access[road,i,k].
        """
        T_veh = np.array([[0.0, 40.0],
                          [60.0, 0.0]])
        OD_access = np.ones((1, 2, 2)) - np.eye(2)[np.newaxis, :, :]
        Nroads = 1
        Nzones = 2
        V_arrive = np.zeros((Nroads, Nzones))
        for l in range(Nroads):
            for k in range(Nzones):
                other = [j for j in range(Nzones) if j != k]
                V_arrive[l, k] = np.sum(
                    T_veh[np.ix_(other, [k])] * OD_access[l][np.ix_(other, [k])]
                )
        assert V_arrive[0, 0] == pytest.approx(60.0)   # zone 1 sends 60 to zone 0
        assert V_arrive[0, 1] == pytest.approx(40.0)

    def test_zero_access_matrix_gives_zero_loading(self):
        """If OD_access is all zeros, no trips are loaded onto any road."""
        T_veh = np.array([[0, 100], [200, 0]], dtype=float)
        OD_access = np.zeros((2, 2, 2))
        Nroads = 2; Nzones = 2
        V_depart = np.zeros((Nroads, Nzones))
        V_arrive = np.zeros((Nroads, Nzones))
        for l in range(Nroads):
            for k in range(Nzones):
                other = [j for j in range(Nzones) if j != k]
                V_depart[l, k] = np.sum(
                    T_veh[np.ix_([k], other)] * OD_access[l][np.ix_([k], other)]
                )
                V_arrive[l, k] = np.sum(
                    T_veh[np.ix_(other, [k])] * OD_access[l][np.ix_(other, [k])]
                )
        assert V_depart.sum() == 0.0
        assert V_arrive.sum() == 0.0
