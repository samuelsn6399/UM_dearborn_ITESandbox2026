"""
test_helpers.py
===============
Unit tests for pure helper functions in corridor_sim/engine/helpers.py.

Only tests functions that have no file I/O or matplotlib dependencies:
  - hour_index()
  - parametric_peaks()   (also covered in test_temporal_profiles.py)
  - map_access_points()
  - map_intersection_points()
"""

import numpy as np
import pytest
from corridor_sim.engine.helpers import (
    hour_index,
    map_access_points,
    map_intersection_points,
)


# ─── hour_index ──────────────────────────────────────────────────────────────

class TestHourIndex:

    def test_midnight_is_hour_1(self):
        assert hour_index(0.0) == 1

    def test_one_second_before_next_hour_still_same_hour(self):
        assert hour_index(3599.0) == 1

    def test_exact_hour_boundary(self):
        assert hour_index(3600.0) == 2

    def test_midday(self):
        assert hour_index(12 * 3600.0) == 13   # 1-based

    def test_end_of_day_clamps_to_24(self):
        assert hour_index(24 * 3600.0) == 24
        assert hour_index(25 * 3600.0) == 24   # clamped

    def test_hour_23(self):
        assert hour_index(22 * 3600.0) == 23


# ─── map_access_points ────────────────────────────────────────────────────────

def _make_road_stub(name, length=2000, dx=500):
    """Minimal road dict with x_edges only (no state arrays needed)."""
    x_edges = np.arange(0, length + dx, dx, dtype=float)
    return {
        'name':         name,
        'length':       float(length),
        'Nx':           length // dx,
        'x_edges':      x_edges,
        'x_centers':    x_edges[:-1] + dx / 2.0,
    }


class TestMapAccessPoints:

    def test_access_point_assigned_to_correct_segment(self):
        """
        Road: 4 × 500 ft cells. x_centers = [250, 750, 1250, 1750].
        Access point at x=800 ft → falls in cell with edges [500, 1000] → seg 2 (1-based).
        """
        road = _make_road_stub('TestRoad')
        taz = {
            'AccessPoints': [{
                'taz_idx':  1,
                'roadName': 'TestRoad',
                'xLocal':   [800],
                'split':    [1.0],
                'name':     ['Gate A'],
            }]
        }
        result = map_access_points(road, taz)
        assert result['AccessPoints'][0]['xSegment'] == [2]

    def test_multiple_access_points_same_road(self):
        """Two access points on the same road get distinct segment indices."""
        road = _make_road_stub('TestRoad')
        taz = {
            'AccessPoints': [{
                'taz_idx':  1,
                'roadName': 'TestRoad',
                'xLocal':   [300, 1300],
                'split':    [0.5, 0.5],
                'name':     ['Gate A', 'Gate B'],
            }]
        }
        result = map_access_points(road, taz)
        segs = result['AccessPoints'][0]['xSegment']
        assert segs[0] == 1   # x=300 → cell [0, 500) → seg 1
        assert segs[1] == 3   # x=1300 → cell [1000,1500) → seg 3

    def test_wrong_road_name_not_mapped(self):
        """Access points for a different road are not mapped."""
        road = _make_road_stub('RoadA')
        taz = {
            'AccessPoints': [{
                'taz_idx':  1,
                'roadName': 'RoadB',   # different road
                'xLocal':   [500],
                'split':    [1.0],
                'name':     ['Gate'],
            }]
        }
        result = map_access_points(road, taz)
        assert result['AccessPoints'] == []

    def test_does_not_mutate_original_taz(self):
        """map_access_points must not modify the original TAZ dict."""
        road = _make_road_stub('TestRoad')
        ap_original = {
            'taz_idx': 1, 'roadName': 'TestRoad',
            'xLocal': [600], 'split': [1.0], 'name': ['G'],
        }
        taz = {'AccessPoints': [ap_original]}
        _ = map_access_points(road, taz)
        assert 'xSegment' not in ap_original


# ─── map_intersection_points ─────────────────────────────────────────────────

class TestMapIntersectionPoints:

    def test_intersection_assigned_to_correct_segment(self):
        """
        Intersection at x=2100 ft on a 6500-ft road (dx=500).
        x_centers = [250,750,...,6250]. First ≥2100 = 2250 → index 4 → seg 5 (1-based).
        """
        road = _make_road_stub('Evergreen Rd Southbound', length=6500, dx=500)
        intersections = [{
            'roadName':         'Evergreen Rd Southbound',
            'xLocal':           2100,
            'taz_idx_external': [3, 6],
        }]
        result = map_intersection_points(road, intersections)
        # x_centers for 6500/500 = 13 cells: [250,750,1250,1750,2250,...]
        # 2100 falls in [2000,2500) → index 4 (0-based) → seg 5 (1-based)
        assert result['intersection'][0]['xSegment'] == [5]

    def test_intersection_at_origin(self):
        """
        Intersection at x=0 → first cell edge is [0,500) → seg 1.
        """
        road = _make_road_stub('HubbardRd', length=4500, dx=500)
        intersections = [{
            'roadName':         'HubbardRd',
            'xLocal':           0,
            'taz_idx_external': [1, 2],
        }]
        result = map_intersection_points(road, intersections)
        assert result['intersection'][0]['xSegment'] == [1]

    def test_wrong_road_not_mapped(self):
        """Intersections for a different road produce empty intersection list."""
        road = _make_road_stub('RoadA', length=3000, dx=500)
        intersections = [{'roadName': 'RoadB', 'xLocal': 500,
                           'taz_idx_external': [1]}]
        result = map_intersection_points(road, intersections)
        assert result['intersection'] == []
