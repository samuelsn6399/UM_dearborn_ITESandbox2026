"""
load_od_access.py
=================
Load the OD-access tensor from a project's taz_config.xlsx.

The OD-access tensor (shape: Nroads × Nzones × Nzones) indicates which
origin–destination pairs use each road.  It is stored as four sheets in
taz_config.xlsx:
    ODAccess_Depart     — SB (road index 1)
    ODAccess_Depart_NB  — NB (road index 2)
    ODAccess_Depart_EB  — EB (road index 3)
    ODAccess_Depart_WB  — WB (road index 4)

Each sheet has zone names as both row index (origin) and column headers
(destination), with values 0 or 1.
"""

from pathlib import Path
import numpy as np
import pandas as pd


def load_od_access(project_path, road_names: list) -> np.ndarray:
    """
    Load the OD-access tensor from taz_config.xlsx.

    The function reads sheets in road-index order (SB, NB, EB, WB) and
    stacks them into a 3-D tensor.

    Parameters
    ----------
    project_path : Path or str  Project folder containing taz_config.xlsx.
    road_names   : list[str]    Ordered list of road names matching the
                                Corridors sheet order (SB, NB, EB, WB).

    Returns
    -------
    od_access : ndarray (Nroads, Nzones, Nzones)  Binary access tensor.
    """
    xf = Path(project_path) / "taz_config.xlsx"
    # Sheet names written by generate_project_configs.py, in road-index order
    sheet_names = [
        'ODAccess_Depart',
        'ODAccess_Depart_NB',
        'ODAccess_Depart_EB',
        'ODAccess_Depart_WB',
    ]

    matrices = []
    for sheet in sheet_names:
        df = pd.read_excel(xf, sheet_name=sheet, header=0, index_col=0)
        matrices.append(df.to_numpy(dtype=float))

    return np.stack(matrices, axis=0)   # shape (Nroads, Nzones, Nzones)
