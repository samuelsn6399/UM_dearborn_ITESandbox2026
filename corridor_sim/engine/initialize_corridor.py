"""
initialize_corridor.py
======================
Universal corridor initializer — replaces the four hard-coded per-road
constructor files (evergreen_sb.py, evergreen_nb.py, etc.) with a single
data-driven function.

A corridor is fully described by a CorridorConfig dataclass whose values
come from corridor_config.xlsx in the project folder.

Direct replacement for the temporary corridor constructors created in
Sub-Task 1 (projects/UM_Dearborn/evergreen_sb.py, etc.).
"""

from __future__ import annotations
from dataclasses import dataclass, field
from pathlib import Path
from typing import List

import numpy as np
import pandas as pd


# ─── Configuration schema ────────────────────────────────────────────────────

@dataclass
class LaneSegment:
    x_start: float   # [ft] segment start (inclusive)
    x_end:   float   # [ft] segment end   (inclusive)
    n_lanes: int


@dataclass
class SpeedSegment:
    x_start: float   # [ft]
    x_end:   float   # [ft]
    speed_mph: float


@dataclass
class SignalConfig:
    x:              float   # [ft] signal location
    green:          float   # [s]
    red:            float   # [s]
    qsat_per_lane:  float   # [veh/s/lane]


@dataclass
class CorridorConfig:
    name:           str
    idx:            int            # 1-based road index
    length:         float          # [ft]
    boundary_idx:   List[int]      # [inflow_taz, outflow_taz]  0 = intersection side
    lane_segments:  List[LaneSegment]  = field(default_factory=list)
    speed_segments: List[SpeedSegment] = field(default_factory=list)
    signal:         SignalConfig = None


# ─── Initializer ─────────────────────────────────────────────────────────────

def initialize_corridor(config: CorridorConfig, sim: dict, fd: dict) -> dict:
    """
    Build a road configuration dict from a CorridorConfig.

    The returned dict has the exact same keys as the per-road constructors
    in Sub-Task 1, so the LWR solver requires no changes.

    Parameters
    ----------
    config : CorridorConfig
    sim    : dict  Simulation settings (dx, Nt, mph_to_fts).
    fd     : dict  Fundamental diagram (rho_j, rho_c, Q).

    Returns
    -------
    road : dict  Full road configuration and initialised state arrays.
    """
    road = {}
    road['name']   = config.name
    road['idx']    = config.idx
    road['length'] = float(config.length)
    road['Nx']     = int(config.length // sim['dx'])

    road['x_edges']   = np.arange(0, config.length + sim['dx'], sim['dx'], dtype=float)
    road['x_centers'] = road['x_edges'][:-1] + sim['dx'] / 2.0

    road['boundary_idx'] = list(config.boundary_idx)

    # ── Lane configuration ────────────────────────────────────────────
    xc = road['x_centers']
    N_lanes = np.zeros(road['Nx'], dtype=int)
    for seg in config.lane_segments:
        mask = (xc >= seg.x_start) & (xc <= seg.x_end)
        N_lanes[mask] = seg.n_lanes
    road['N_lanes'] = N_lanes

    # ── Speed configuration ───────────────────────────────────────────
    u_free = np.zeros(road['Nx'])
    for seg in config.speed_segments:
        mask = (xc >= seg.x_start) & (xc <= seg.x_end)
        u_free[mask] = seg.speed_mph * sim['mph_to_fts']
    road['FD']       = dict(fd)
    road['FD']['vf'] = u_free

    # ── Signal configuration ──────────────────────────────────────────
    sig = config.signal
    signal = {}
    signal['x']             = sig.x
    signal['green']         = sig.green
    signal['red']           = sig.red
    signal['Qsat_per_lane'] = sig.qsat_per_lane
    signal['period']        = sig.green + sig.red
    sig_cells = np.where(xc >= sig.x)[0]
    signal['cell'] = int(sig_cells[0]) + 1 if len(sig_cells) > 0 else road['Nx']  # 1-based
    signal['Qsat'] = sig.qsat_per_lane * N_lanes[signal['cell'] - 1]
    road['signal']    = signal
    road['is_signal'] = np.zeros(road['Nx'], dtype=bool)
    road['is_signal'][signal['cell'] - 1] = True

    # ── State array initialisation ────────────────────────────────────
    Nx, Nt = road['Nx'], sim['Nt']
    road['rho']       = np.zeros((Nx, Nt))
    road['rho'][:, 0] = 0.01 * fd['rho_c']
    sc = signal['cell'] - 1   # 0-based
    road['rho'][max(0, sc - 1):min(Nx, sc + 2), 0] = 0.01 * fd['rho_c']
    road['F']         = np.zeros((Nx + 1, Nt))
    road['F_desired'] = np.zeros((2, Nt))
    road['g']         = np.zeros((1, Nt - 1))
    road['g_eff']     = np.zeros((Nx, Nt - 1))
    road['s']         = np.zeros((Nx, Nt))

    return road


# ─── Config loader ────────────────────────────────────────────────────────────

def load_corridor_config(project_path) -> List[CorridorConfig]:
    """
    Read corridor_config.xlsx from a project folder and return a list of
    CorridorConfig objects, one per corridor row, in index order.

    Parameters
    ----------
    project_path : Path or str

    Returns
    -------
    configs : list[CorridorConfig]
    """
    project_path = Path(project_path)
    xf = project_path / "corridor_config.xlsx"

    corridors_df  = pd.read_excel(xf, sheet_name="Corridors",     header=0)
    lanes_df      = pd.read_excel(xf, sheet_name="LaneSegments",  header=0)
    speeds_df     = pd.read_excel(xf, sheet_name="SpeedSegments", header=0)
    signals_df    = pd.read_excel(xf, sheet_name="Signals",       header=0)

    configs = []
    for _, row in corridors_df.iterrows():
        name = str(row['Name'])

        # Lane segments for this corridor
        lane_segs = [
            LaneSegment(
                x_start=float(r['XStart_ft']),
                x_end=float(r['XEnd_ft']),
                n_lanes=int(r['NLanes']),
            )
            for _, r in lanes_df[lanes_df['CorridorName'] == name].iterrows()
        ]

        # Speed segments
        speed_segs = [
            SpeedSegment(
                x_start=float(r['XStart_ft']),
                x_end=float(r['XEnd_ft']),
                speed_mph=float(r['Speed_mph']),
            )
            for _, r in speeds_df[speeds_df['CorridorName'] == name].iterrows()
        ]

        # Signal
        sig_row = signals_df[signals_df['CorridorName'] == name].iloc[0]
        signal = SignalConfig(
            x=float(sig_row['SignalX_ft']),
            green=float(sig_row['Green_s']),
            red=float(sig_row['Red_s']),
            qsat_per_lane=float(sig_row['Qsat_per_lane_vehsperlane']),
        )

        configs.append(CorridorConfig(
            name=name,
            idx=int(row['Idx']),
            length=float(row['Length_ft']),
            boundary_idx=[int(row['BoundaryIdx_In']), int(row['BoundaryIdx_Out'])],
            lane_segments=lane_segs,
            speed_segments=speed_segs,
            signal=signal,
        ))

    # Return in ascending idx order so all_roads[0] == SB, [1] == NB, etc.
    configs.sort(key=lambda c: c.idx)
    return configs
