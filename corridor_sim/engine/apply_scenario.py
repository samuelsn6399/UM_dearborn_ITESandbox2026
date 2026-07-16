"""
apply_scenario.py
=================
Scenario engine — applies named overrides on top of a base project configuration.

A scenario is a named set of parameter overrides stored in
``projects/<name>/scenario_config.xlsx``.  Three override types are supported:

SignalOverrides
    Change green time, red time, or saturation flow on any corridor.
    The corridor is re-initialised so ``is_signal`` and ``signal['Qsat']``
    are recomputed correctly.

LandUseOverrides
    Change the employment, enrollment, or retail-area attraction parameters
    for any zone, shifting the gravity-model distribution.

ModeSplitOverrides
    Replace the scalar ``auto_occupancy`` with per-zone auto-share fractions,
    enabling mode-shift scenario modelling (e.g. transit investment reducing
    auto trips on specific zones).

QuickTuneOverrides
    Override individual boundary scale factors for scenario-specific calibration.

Usage (from run_simulation.py)
------------------------------
    from corridor_sim.engine.apply_scenario import apply_scenario

    corridor_configs, fd, taz, intersections, quicktune, od_access = apply_scenario(
        base_corridor_configs,
        base_fd,
        base_taz,
        base_intersections,
        base_quicktune,
        base_od_access,
        scenario_name='SignalRetiming_A',
        project_path=Path('projects/UM_Dearborn'),
    )
"""

from __future__ import annotations
import copy
from pathlib import Path

import numpy as np
import pandas as pd

from corridor_sim.engine.initialize_corridor import (
    CorridorConfig, SignalConfig, initialize_corridor
)


# ─── Public API ───────────────────────────────────────────────────────────────

def apply_scenario(
    corridor_configs: list,
    fd: dict,
    taz: dict,
    intersections: list,
    quicktune: dict,
    od_access: np.ndarray,
    scenario_name: str,
    project_path,
    sim: dict,
) -> tuple:
    """
    Apply a named scenario's overrides and return updated configs.

    Base configs are never mutated — deep copies are made before any override
    is applied, so the caller can run multiple scenarios from the same base.

    Parameters
    ----------
    corridor_configs : list[CorridorConfig]  Base corridor configurations.
    fd               : dict                  Base fundamental diagram.
    taz              : dict                  Base TAZ configuration.
    intersections    : list                  Base intersection definitions.
    quicktune        : dict                  Base QuickTune scale factors.
    od_access        : ndarray               Base OD-access tensor.
    scenario_name    : str                   Name matching a row in ScenarioList sheet.
    project_path     : Path or str           Project folder containing scenario_config.xlsx.
    sim              : dict                  Simulation settings (needed to re-init corridors).

    Returns
    -------
    (corridor_configs, fd, taz, intersections, quicktune, od_access, auto_share)
        All modified deep copies; auto_share is a per-zone array or None if
        no ModeSplitOverrides were applied.
    """
    project_path = Path(project_path)
    xf = project_path / "scenario_config.xlsx"

    # ── Validate scenario exists ──────────────────────────────────────────────
    sl_df = pd.read_excel(xf, sheet_name='ScenarioList', header=0)
    if scenario_name not in sl_df['ScenarioName'].values:
        raise ValueError(
            f"apply_scenario: scenario '{scenario_name}' not found in "
            f"ScenarioList sheet of {xf}.\n"
            f"Available: {sl_df['ScenarioName'].tolist()}"
        )

    # Deep-copy all mutable inputs so base configs are never touched
    corridor_configs = copy.deepcopy(corridor_configs)
    fd               = copy.deepcopy(fd)
    taz              = copy.deepcopy(taz)
    intersections    = copy.deepcopy(intersections)
    quicktune        = copy.deepcopy(quicktune)
    od_access        = od_access.copy()
    auto_share       = None   # populated only if ModeSplitOverrides present

    # ── Signal overrides ─────────────────────────────────────────────────────
    try:
        sig_df = pd.read_excel(xf, sheet_name='SignalOverrides', header=0)
        sig_df = sig_df[sig_df['ScenarioName'] == scenario_name]
        for _, row in sig_df.iterrows():
            for cfg in corridor_configs:
                if cfg.name == str(row['RoadName']):
                    new_sig = SignalConfig(
                        x=cfg.signal.x,
                        green=float(row['Green_s']),
                        red=float(row['Red_s']),
                        qsat_per_lane=float(row['Qsat_per_lane_vehsperlane']),
                    )
                    cfg.signal = new_sig
                    print(f"  [Scenario] Signal override on '{cfg.name}': "
                          f"green={new_sig.green}s, red={new_sig.red}s")
    except Exception:
        pass   # sheet absent or no rows for this scenario

    # ── Land-use overrides ───────────────────────────────────────────────────
    try:
        lu_df = pd.read_excel(xf, sheet_name='LandUseOverrides', header=0)
        lu_df = lu_df[lu_df['ScenarioName'] == scenario_name]
        if len(lu_df) > 0 and 'AttractionParams' in taz:
            zone_names = taz['names']
            for _, row in lu_df.iterrows():
                z_name = str(row['ZoneName'])
                if z_name in zone_names:
                    idx = zone_names.index(z_name)
                    taz['AttractionParams'][idx, 0] = float(row['Employment'])
                    taz['AttractionParams'][idx, 1] = float(row['Enrollment'])
                    taz['AttractionParams'][idx, 2] = float(row['RetailArea_sqft'])
                    print(f"  [Scenario] Land-use override for '{z_name}': "
                          f"emp={row['Employment']}, enroll={row['Enrollment']}, "
                          f"retail={row['RetailArea_sqft']}")
    except Exception:
        pass

    # ── Mode-split overrides ─────────────────────────────────────────────────
    try:
        ms_df = pd.read_excel(xf, sheet_name='ModeSplitOverrides', header=0)
        ms_df = ms_df[ms_df['ScenarioName'] == scenario_name]
        if len(ms_df) > 0:
            zone_names = taz['names']
            Nzones = len(zone_names)
            auto_share = np.ones(Nzones) * taz.get('auto_occupancy_default',
                                                    1.0 / 1.25)
            for _, row in ms_df.iterrows():
                z_name = str(row['ZoneName'])
                if z_name in zone_names:
                    idx = zone_names.index(z_name)
                    auto_share[idx] = float(row['AutoShare'])
                    print(f"  [Scenario] Mode-split override for '{z_name}': "
                          f"auto_share={row['AutoShare']:.3f}")
    except Exception:
        pass

    # ── QuickTune overrides ──────────────────────────────────────────────────
    try:
        qt_df = pd.read_excel(xf, sheet_name='QuickTuneOverrides', header=0)
        qt_df = qt_df[qt_df['ScenarioName'] == scenario_name]
        for _, row in qt_df.iterrows():
            key = str(row['Key'])
            quicktune[key] = float(row['ScaleFactor'])
            print(f"  [Scenario] QuickTune override: {key} = {row['ScaleFactor']}")
    except Exception:
        pass

    return corridor_configs, fd, taz, intersections, quicktune, od_access, auto_share


def load_scenario_list(project_path) -> list:
    """
    Return a list of scenario names defined in scenario_config.xlsx.

    Parameters
    ----------
    project_path : Path or str

    Returns
    -------
    names : list[str]
    """
    xf = Path(project_path) / "scenario_config.xlsx"
    df = pd.read_excel(xf, sheet_name='ScenarioList', header=0)
    return df['ScenarioName'].tolist()


def scenario_config_exists(project_path) -> bool:
    """Return True if scenario_config.xlsx exists in the project folder."""
    return (Path(project_path) / "scenario_config.xlsx").exists()
