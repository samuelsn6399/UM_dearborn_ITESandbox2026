"""
lwr_model.py
============
Lighthill-Whitham-Richards (LWR) macroscopic traffic flow solver.

Advances a single road by one time step using the Godunov finite-volume
scheme with the Greenshields fundamental diagram.  Source/sink terms from
TAZ access points and intersection connections are applied cell-by-cell.

Direct translation of LWRModel.m (MATLAB reference implementation).
"""

import numpy as np


def lwr_model(road, rho_n, demand, zone, sim):
    """
    Advance a road's density field by one time step.

    Parameters
    ----------
    road   : dict  Road configuration and geometry (from corridor constructor).
    rho_n  : ndarray shape (Nx,)  Density at current time step [veh/ft/lane].
    demand : dict  Output of classic_traffic_demand_model().
    zone   : dict  TAZ configuration (names, f_arrive, f_depart, …).
    sim    : dict  Simulation settings (dt, dx, n, h, …).

    Returns
    -------
    rho_next   : ndarray (Nx,)   Density at next time step [veh/ft/lane].
    F_n        : ndarray (Nx+1,) Cell-interface fluxes [veh/s].
    F_n_desired: ndarray (2,)    Unsaturated OD boundary fluxes [veh/s].
    g_n        : int             Signal state (1 = green, 0 = red).
    g_eff_n    : ndarray (Nx,)   Effective green flag per cell.
    s_n        : ndarray (Nx,)   Net source/sink per cell [veh/s].
    """
    Nx = road['Nx']
    FD = road['FD']
    signal = road['signal']
    dt = sim['dt']
    dx = sim['dx']
    h  = sim['h']   # 1-based hour index (1–24)

    # ------------------------------------------------------------------
    # Signal state
    # ------------------------------------------------------------------
    if (sim['t'][sim['n']] % signal['period']) < signal['green']:
        g_n = 1
    else:
        g_n = 0

    # ------------------------------------------------------------------
    # Interior fluxes  F[1] … F[Nx-1]  (0-based index: F[1..Nx-1])
    # ------------------------------------------------------------------
    F_n     = np.zeros(Nx + 1)
    g_eff_n = np.zeros(Nx)

    for i in range(Nx - 1):          # interior interfaces 1 .. Nx-1
        F_base = _godunov_flux(FD, FD['vf'][i], rho_n[i], rho_n[i + 1],
                               road['N_lanes'][i])
        if road['is_signal'][i]:
            F_n[i + 1] = min(F_base, g_n * signal['Qsat'])
        else:
            F_n[i + 1] = F_base
        g_eff_n[i] = int(road['is_signal'][i]) * g_n

    # ------------------------------------------------------------------
    # Upstream boundary flux  F[0]
    # ------------------------------------------------------------------
    rho_c = FD['rho_c']
    if rho_n[0] <= rho_c:
        S1 = FD['Q'](rho_c, FD['vf'][0])
    else:
        S1 = FD['Q'](rho_n[0], FD['vf'][0])

    if road['boundary_idx'][0] == 0:   # road originates at intersection — no BC
        F_n_desired_in = 0.0
    else:
        taz_in = road['boundary_idx'][0] - 1   # convert to 0-based
        F_n_desired_in = (demand['V_taz_depart'][road['idx'] - 1, taz_in]
                          * zone['f_depart'][h - 1, taz_in] / 3600.0)

    F_n[0] = min(F_n_desired_in, S1 * road['N_lanes'][0])

    # ------------------------------------------------------------------
    # Downstream boundary flux  F[Nx]
    # ------------------------------------------------------------------
    if rho_n[Nx - 1] <= rho_c:
        D_Nx = FD['Q'](rho_n[Nx - 1], FD['vf'][Nx - 1])
    else:
        D_Nx = FD['Q'](rho_c, FD['vf'][Nx - 1])

    if road['boundary_idx'][1] == 0:   # road terminates at intersection — no BC
        F_n_desired_out = 0.0
    else:
        taz_out = road['boundary_idx'][1] - 1  # convert to 0-based
        F_n_desired_out = (demand['V_taz_arrive'][road['idx'] - 1, taz_out]
                           * zone['f_arrive'][h - 1, taz_out] / 3600.0)

    F_n[Nx] = D_Nx * road['N_lanes'][Nx - 1]

    F_n_desired = np.array([F_n_desired_in, F_n_desired_out])

    # ------------------------------------------------------------------
    # Source/sink terms and density update
    # ------------------------------------------------------------------
    s_n      = np.zeros(Nx)
    rho_next = np.zeros(Nx)

    for i in range(Nx):
        s_i = []

        # Access points
        for ap in road['AccessPoints']:
            match = np.where(np.array(ap['xSegment']) == (i + 1))[0]  # 1-based segs
            if len(match) > 0:
                m = match[0]
                taz_k = ap['taz_idx'] - 1  # 0-based
                split_k = ap['split'][m] if hasattr(ap['split'], '__len__') else ap['split']
                q_arr = (demand['V_taz_arrive'][road['idx'] - 1, taz_k]
                         * zone['f_arrive'][h - 1, taz_k] / 3600.0 * split_k)
                q_dep = (demand['V_taz_depart'][road['idx'] - 1, taz_k]
                         * zone['f_depart'][h - 1, taz_k] / 3600.0 * split_k)
                s_i.append(q_dep - q_arr)

        # Intersection
        intr = road['intersection'][0]
        if (i + 1) in np.atleast_1d(intr['xSegment']):
            for k_taz in intr['taz_idx_external']:
                taz_k = k_taz - 1  # 0-based
                road_idx_0 = road['idx'] - 1
                # EB (idx=3): arrivals at intersection are zero
                q_arr_int = (0.0 if road['idx'] == 3
                             else demand['V_taz_arrive'][road_idx_0, taz_k]
                                  * zone['f_arrive'][h - 1, taz_k] / 3600.0)
                # WB (idx=4): departures at intersection are zero
                q_dep_int = (0.0 if road['idx'] == 4
                             else demand['V_taz_depart'][road_idx_0, taz_k]
                                  * zone['f_depart'][h - 1, taz_k] / 3600.0)
                s_i.append(q_dep_int - q_arr_int)

        s_n[i] = sum(s_i)
        F_net   = F_n[i] - F_n[i + 1]
        rho_next[i] = rho_n[i] + (dt / dx) * (F_net + s_n[i])
        if rho_next[i] < 0:
            rho_next[i] = 0.0

    return rho_next, F_n, F_n_desired, g_n, g_eff_n, s_n


def _godunov_flux(FD, vf, rho_up, rho_down, n_lanes):
    """
    Godunov numerical flux for the LWR model with Greenshields FD.

    Parameters
    ----------
    FD       : dict   Fundamental diagram with keys rho_j, rho_c, Q.
    vf       : float  Free-flow speed at the interface [ft/s].
    rho_up   : float  Upstream cell density [veh/ft/lane].
    rho_down : float  Downstream cell density [veh/ft/lane].
    n_lanes  : int    Number of lanes at the interface.

    Returns
    -------
    F : float  Flux [veh/s].
    """
    rho_c = FD['rho_c']
    Q     = FD['Q']

    D = Q(rho_up,   vf) if rho_up   <= rho_c else Q(rho_c, vf)
    S = Q(rho_c,    vf) if rho_down <= rho_c else Q(rho_down, vf)
    return n_lanes * min(D, S)
