"""
evergreen_sb.py
===============
Evergreen Rd Southbound corridor constructor.

x = 0 ft at NORTH end; x = 6500 ft at SOUTH end.
Road index: 1  (1-based, matching MATLAB convention).

NOTE: This is a temporary per-road constructor that will be replaced by
      the universal initialize_corridor() function in Sub-Task 3.

Direct translation of EvergreenRdSouthbound.m (MATLAB reference).
"""

import numpy as np


def evergreen_rd_southbound(sim: dict, fd: dict) -> dict:
    """
    Build the Evergreen Rd Southbound road configuration dict.

    Parameters
    ----------
    sim : dict  Simulation settings (dx, Nt, mph_to_fts).
    fd  : dict  Fundamental diagram (rho_j, rho_c, Q).

    Returns
    -------
    road : dict  Full road configuration and initialised state arrays.
    """
    road = {}
    road['name']   = 'Evergreen Rd Southbound'
    road['idx']    = 1
    road['length'] = 6500                            # [ft]
    road['Nx']     = road['length'] // sim['dx']

    road['x_edges']   = np.arange(0, road['length'] + sim['dx'],
                                   sim['dx'], dtype=float)
    road['x_centers'] = road['x_edges'][:-1] + sim['dx'] / 2.0

    # Boundary TAZ indices [inflow, outflow] — 1-based
    road['boundary_idx'] = [4, 5]   # [NorthBoundary, SouthBoundary]

    # Lane configuration
    xc = road['x_centers']
    N_lanes = np.zeros(road['Nx'], dtype=int)
    N_lanes[(xc >=    1) & (xc <= 2000)] = 4
    N_lanes[(xc >= 2001) & (xc <= 3000)] = 3
    N_lanes[(xc >= 3001) & (xc <= 3500)] = 5
    N_lanes[(xc >= 3501) & (xc <= 4500)] = 3
    N_lanes[(xc >= 4501) & (xc <= 5500)] = 2
    N_lanes[(xc >= 5501) & (xc <= 6500)] = 3
    road['N_lanes'] = N_lanes

    # Signal configuration
    signal = {}
    signal['x']            = 6000.0   # [ft]
    signal['green']        = 45.0     # [s]
    signal['red']          = 75.0     # [s]
    signal['Qsat_per_lane'] = 1900.0 / 3600.0  # [veh/s/lane]
    signal['period']       = signal['green'] + signal['red']
    sig_cells = np.where(xc >= signal['x'])[0]
    signal['cell'] = int(sig_cells[0]) + 1 if len(sig_cells) > 0 else road['Nx']  # 1-based
    signal['Qsat'] = signal['Qsat_per_lane'] * N_lanes[signal['cell'] - 1]
    road['signal']    = signal
    road['is_signal'] = np.zeros(road['Nx'], dtype=bool)
    road['is_signal'][signal['cell'] - 1] = True

    # Speed limit configuration [ft/s]
    u_free = np.zeros(road['Nx'])
    idx_30 = (xc >= 3501) & (xc <= 5500)
    idx_40 = ~idx_30
    u_free[idx_30] = 30.0 * sim['mph_to_fts']
    u_free[idx_40] = 40.0 * sim['mph_to_fts']

    # Fundamental diagram (per-cell vf)
    road['FD'] = dict(fd)
    road['FD']['vf'] = u_free

    # State arrays
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
