"""
truth_data.py
=============
MDOT ground-truth traffic count data used for model calibration and tuning.

Data sources:
  - Michigan Traffic AADT: experience.arcgis.com
  - MDOT Traffic Viewer: mdot.public.ms2soft.com

Direct translation of MdotTruthData.m (MATLAB reference implementation).
"""

import numpy as np


# ---------------------------------------------------------------------------
# AADT constants  [vehicles/day]  (2025)
# ---------------------------------------------------------------------------
_AADT = {
    'Evergreen Rd Southbound': 2518,
    'Evergreen Rd Northbound': 3042,
    'Hubbard Rd Eastbound':    7280,
    'Hubbard Rd Westbound':    4497,
}

# ---------------------------------------------------------------------------
# Raw hourly counts  [vehicles/hour-of-day]
# March 2021 (Evergreen) | July 2021 (Hubbard)
# ---------------------------------------------------------------------------
_RAW_DISTRIBUTION = {
    'Evergreen Rd Southbound': np.array([
        14,  1,  7,  8,  9, 38, 66,  75, 134, 132, 152, 169,
       172, 185, 206, 203, 206, 212, 144, 126, 100,  57,  39, 16,
    ], dtype=float),

    'Evergreen Rd Northbound': np.array([
        23, 10, 10,  5, 14, 21,  85, 109, 155, 155, 173, 165,
       229, 223, 275, 262, 237, 249, 198, 138, 127,  78,  46, 35,
    ], dtype=float),

    'Hubbard Rd Eastbound': np.array([
        36,  38,  17,  22,  17,  38,  72, 108, 161, 238, 331, 491,
       610, 524, 638, 647, 683, 596, 598, 532, 309, 172, 133,  69,
    ], dtype=float),

    'Hubbard Rd Westbound': np.array([
        31,  18,  16,  19,  21,  51, 136, 192, 236, 236, 330, 335,
       376, 372, 370, 370, 363, 355, 298, 173, 150,  90,  80,  38,
    ], dtype=float),
}


def mdot_truth_data(roadway_name: str) -> dict:
    """
    Return MDOT ground-truth hourly flow data for a named roadway.

    Inflow equals outflow by conservation of vehicles, assuming equivalent
    temporal factors and negligible travel-time delay between boundaries.

    Parameters
    ----------
    roadway_name : str
        One of 'Evergreen Rd Southbound', 'Evergreen Rd Northbound',
        'Hubbard Rd Eastbound', 'Hubbard Rd Westbound'.

    Returns
    -------
    truth : dict with keys:
        MDOT_inflow  : ndarray (24,)  [veh/s] per hour of day.
        MDOT_outflow : ndarray (24,)  [veh/s] per hour of day.
    """
    if roadway_name not in _AADT:
        raise ValueError(
            f"mdot_truth_data: no data for roadway '{roadway_name}'. "
            f"Valid names: {list(_AADT.keys())}"
        )

    aadt = _AADT[roadway_name]
    raw  = _RAW_DISTRIBUTION[roadway_name]
    dist = raw / raw.sum()           # normalise to fractional shares
    hourly_flow = aadt * dist / 3600  # [veh/s] per hour

    return {
        'MDOT_inflow':  hourly_flow.copy(),
        'MDOT_outflow': hourly_flow.copy(),
    }
