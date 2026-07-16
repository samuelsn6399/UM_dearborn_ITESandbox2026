"""
load_truth_data.py
==================
Load MDOT ground-truth AADT data from a project's truth_data.xlsx file.

Replaces the hard-coded AADT literals in corridor_sim/engine/truth_data.py
with a file-driven approach — supporting any corridor project.

Schema of truth_data.xlsx (one sheet per road):
    Column 1: Hour_1to24         [int 1–24]
    Column 2: AADT_veh_per_day   [int]
    Column 3: HourlyCount_raw    [int]  unnormalised hourly vehicle counts

The loader normalises HourlyCount_raw so the fractions sum to 1, then
scales by AADT / 3600 to produce per-second flow rates matching the
existing truth_data.py output format.
"""

from pathlib import Path
import numpy as np
import pandas as pd


def load_truth_data(project_path, road_name: str) -> dict:
    """
    Return MDOT ground-truth hourly flow data for a named roadway.

    Parameters
    ----------
    project_path : Path or str  Project folder containing truth_data.xlsx.
    road_name    : str          Roadway name matching a sheet in truth_data.xlsx.

    Returns
    -------
    truth : dict with keys:
        MDOT_inflow  : ndarray (24,)  [veh/s] per hour of day.
        MDOT_outflow : ndarray (24,)  [veh/s] per hour of day.
    """
    xf = Path(project_path) / "truth_data.xlsx"

    try:
        df = pd.read_excel(xf, sheet_name=road_name, header=0)
    except Exception as e:
        raise ValueError(
            f"load_truth_data: could not read sheet '{road_name}' "
            f"from {xf}. Original error: {e}"
        )

    aadt = float(df['AADT_veh_per_day'].iloc[0])
    raw  = df['HourlyCount_raw'].to_numpy(dtype=float)
    dist = raw / raw.sum()               # normalise to fractional shares
    hourly_flow = aadt * dist / 3600.0   # [veh/s] per hour

    return {
        'MDOT_inflow':  hourly_flow.copy(),
        'MDOT_outflow': hourly_flow.copy(),
    }
