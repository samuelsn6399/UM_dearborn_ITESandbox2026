"""
demand_model.py
===============
Classic four-step travel demand model (NCHRP 716).

Step 1a: Trip Productions  — cross-classification using household data
Step 1b: Trip Attractions  — linear land-use model
Step 1c: Balance P and A
Step 2:  Trip Distribution — singly-constrained gravity model
Step 3:  Mode Choice       — average vehicle occupancy
Step 4:  Network Loading   — map OD matrix to corridor source/sink flows

Direct translation of ClassicTrafficDemandModel.m (MATLAB reference).
"""

from pathlib import Path
import numpy as np
import pandas as pd


def classic_traffic_demand_model(zone: dict,
                                  project_path=None,
                                  od_access: np.ndarray = None,
                                  auto_share: np.ndarray = None) -> dict:
    """
    Run the four-step travel demand model.

    Parameters
    ----------
    zone         : dict  TAZ configuration including:
        names         : list[str]       Zone names (must match xlsx sheet names).
        xLocation     : array-like      Zone centroid x-positions [ft].
        yLocation     : array-like      Zone centroid y-positions [ft].
    project_path : Path or str, optional
        Folder containing HouseholdData.xlsx and TripRateData.xlsx.
        Defaults to the current working directory.
    od_access    : ndarray (Nroads, Nzones, Nzones), optional
        Binary OD-access tensor: od_access[r, i, j] = 1 if trips from zone i
        to zone j use road r.  When None, a hard-coded UM-Dearborn fallback
        is used (backward-compatibility only — should always be supplied
        via project config in production use).
    auto_share   : ndarray (Nzones,), optional
        Per-zone fraction of person-trips made by private auto [0–1].
        When supplied, overrides the scalar ``auto_occupancy`` for Step 3
        (mode choice), enabling multi-modal scenario modelling.
        When None, the default scalar occupancy (1.25 persons/vehicle) is used.

    Returns
    -------
    demand : dict with keys:
        P               : ndarray (Nzones,)   Daily trip productions [person-trips/day].
        A               : ndarray (Nzones,)   Balanced daily attractions [person-trips/day].
        A_raw           : ndarray (Nzones,)   Unbalanced attractions.
        T_person        : ndarray (Nz, Nz)    Person-trip OD table [person-trips/day].
        T_vehicle       : ndarray (Nz, Nz)    Vehicle-trip OD table [veh/day].
        V_taz_arrive    : ndarray (Nroads, Nzones) Daily vehicle arrivals per road-TAZ pair.
        V_taz_depart    : ndarray (Nroads, Nzones) Daily vehicle departures per road-TAZ pair.
        attr_rates      : list[float]
        v_avg_mph       : float
        beta            : float
        auto_occupancy  : float
        AttractionParams: ndarray (Nzones, 3)
    """
    demand = {}

    # ------------------------------------------------------------------
    # Step 1 parameters: Attraction model
    # ------------------------------------------------------------------
    demand['attr_rates']    = [1.5, 0.4, 0.01]   # [trips/job, trips/student, trips/sqft]
    demand['v_avg_mph']     = 35.0                # [mph] average corridor speed
    demand['beta']          = 0.12                # [1/min] friction factor decay rate
    demand['gravity_on_off'] = False              # False = uniform friction
    demand['auto_occupancy'] = 1.25               # [persons/vehicle]

    print('Done configuring 4-step model parameters...')

    # Resolve data file paths
    base = Path(project_path) if project_path else Path('.')
    filename_hh = base / "HouseholdData.xlsx"
    filename_tr = base / "TripRateData.xlsx"

    # ------------------------------------------------------------------
    # Load household data
    # ------------------------------------------------------------------
    H_list = []
    for name in zone['names']:
        df = pd.read_excel(filename_hh, sheet_name=name, header=0, index_col=0)
        # Drop the last column (Totals) and the last row (Totals)
        arr = df.iloc[:-1, :-1].to_numpy(dtype=float)
        H_list.append(arr)
    print('Done loading household data...')

    # ------------------------------------------------------------------
    # Load trip production rate data and attraction parameters
    # ------------------------------------------------------------------
    R_list = []
    for name in zone['names']:
        df = pd.read_excel(filename_tr, sheet_name=name, header=0, index_col=0)
        arr = df.iloc[:-1, :-1].to_numpy(dtype=float)
        R_list.append(arr)

    ap_df = pd.read_excel(filename_tr, sheet_name='AttractionParameters',
                          header=0, index_col=0)
    demand['AttractionParams'] = ap_df.to_numpy(dtype=float)
    print('Done loading trip production data...')
    print('Done loading trip attraction data...')

    # ------------------------------------------------------------------
    # Step 1a: Trip Productions (cross-classification)
    # ------------------------------------------------------------------
    Nzones = len(zone['names'])
    demand['P'] = np.array([np.sum(H_list[iz] * R_list[iz])
                             for iz in range(Nzones)])

    # ------------------------------------------------------------------
    # Step 1b: Trip Attractions (linear land-use model, NCHRP 716)
    # ------------------------------------------------------------------
    attr_rates = np.array(demand['attr_rates'])
    demand['A_raw'] = demand['AttractionParams'] @ attr_rates   # (Nzones,)

    # ------------------------------------------------------------------
    # Step 1c: Balance P and A (scale A so sum(A) = sum(P))
    # ------------------------------------------------------------------
    P_total = demand['P'].sum()
    A_total = demand['A_raw'].sum()
    demand['A'] = demand['A_raw'] * (P_total / A_total)

    # ------------------------------------------------------------------
    # Step 2: Trip Distribution (singly-constrained gravity model)
    # ------------------------------------------------------------------
    mph_to_fts = 5280.0 / 3600.0
    v_avg_fts  = demand['v_avg_mph'] * mph_to_fts

    x_loc = np.array(zone['xLocation'], dtype=float)
    y_loc = np.array(zone['yLocation'], dtype=float)

    if demand['gravity_on_off']:
        F_matrix = np.zeros((Nzones, Nzones))
        for i in range(Nzones):
            for j in range(Nzones):
                if i == j:
                    F_matrix[i, j] = 0.0
                else:
                    d_ij = np.sqrt((x_loc[i] - x_loc[j]) ** 2 +
                                   (y_loc[i] - y_loc[j]) ** 2)
                    t_ij = max(d_ij / v_avg_fts / 60.0, 1.0)  # min 1 min
                    F_matrix[i, j] = np.exp(-demand['beta'] * t_ij)
    else:
        # Uniform friction, no internal-zone travel
        F_matrix = np.ones((Nzones, Nzones)) - np.eye(Nzones)

    T_person = np.zeros((Nzones, Nzones))
    for i in range(Nzones):
        denom = np.sum(demand['A'] * F_matrix[i, :])
        if denom > 0:
            T_person[i, :] = demand['P'][i] * (demand['A'] * F_matrix[i, :]) / denom
    demand['T_person'] = T_person

    # ------------------------------------------------------------------
    # Step 3: Mode Choice
    # Baseline: uniform scalar auto_occupancy (persons/vehicle).
    # Scenario: per-zone auto_share [fraction of person-trips by auto]
    #   T_vehicle[i,j] = T_person[i,j] * auto_share[i] / persons_per_vehicle
    #   where persons_per_vehicle defaults to auto_occupancy.
    # ------------------------------------------------------------------
    if auto_share is not None:
        # auto_share is fraction of trips by auto; convert to vehicle trips
        # using a fixed vehicle occupancy of 1.0 (auto_share already
        # accounts for mode split; person-trips × auto_share = auto person-trips;
        # divide by occupancy to get vehicle trips)
        occupancy = demand['auto_occupancy']
        share_matrix = np.outer(auto_share, np.ones(Nzones))  # broadcast over cols
        demand['T_vehicle'] = T_person * share_matrix / occupancy
        demand['auto_share_applied'] = auto_share.copy()
    else:
        demand['T_vehicle'] = T_person / demand['auto_occupancy']

    # ------------------------------------------------------------------
    # Step 4: Network Loading — map OD matrix to road source/sink flows
    # ------------------------------------------------------------------
    if od_access is not None:
        OD_access = np.asarray(od_access, dtype=float)
    else:
        # Fallback: UM-Dearborn hard-coded matrices (backward-compat only)
        # New projects must always supply od_access via project config.
        ev_sb = np.array([
            [0, 1, 0, 0, 1, 0],
            [0, 0, 0, 0, 1, 0],
            [1, 1, 0, 0, 1, 0],
            [1, 1, 1, 0, 1, 1],
            [0, 0, 0, 0, 0, 0],
            [1, 1, 0, 0, 1, 0],
        ], dtype=float)
        hub_eb = np.array([
            [0, 0, 1, 0, 0, 1],
            [0, 0, 1, 0, 0, 1],
            [0, 0, 0, 0, 0, 1],
            [0, 0, 1, 0, 0, 1],
            [0, 0, 1, 0, 0, 1],
            [0, 0, 0, 0, 0, 0],
        ], dtype=float)
        OD_access = np.stack([ev_sb, ev_sb.T, hub_eb, hub_eb.T], axis=0)

    Nroads = OD_access.shape[0]

    T_veh = demand['T_vehicle']
    V_arrive = np.zeros((Nroads, Nzones))
    V_depart = np.zeros((Nroads, Nzones))

    for l in range(Nroads):
        for k in range(Nzones):
            other = [j for j in range(Nzones) if j != k]
            V_arrive[l, k] = np.sum(
                T_veh[np.ix_(other, [k])] * OD_access[l][np.ix_(other, [k])]
            )
            V_depart[l, k] = np.sum(
                T_veh[np.ix_([k], other)] * OD_access[l][np.ix_([k], other)]
            )

    demand['V_taz_arrive'] = V_arrive   # [veh/day]  (Nroads, Nzones)
    demand['V_taz_depart'] = V_depart   # [veh/day]

    return demand
