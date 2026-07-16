"""
evergreen_nb.py
===============
Evergreen Rd Northbound corridor constructor.

x = 0 ft at SOUTH end; x = 6500 ft at NORTH end.
Road index: 2  (1-based, matching MATLAB convention).

NOTE: Temporary constructor — will be replaced by initialize_corridor()
      in Sub-Task 3.

Direct translation of EvergreenRdNorthbound.m (MATLAB reference).
"""

import numpy as np


def evergreen_rd_northbound(sim: dict, fd: dict) -> dict:
    """
    Build the Evergreen Rd Northbound road configuration dict.

    Parameters
    ----------
    sim : dict  Simulation settings (dx, Nt, mph_to_fts).
    fd  : dict  Fundamental diagram (rho_j, rho_c, Q).

    Returns
    -------
    road : dict  Full road configuration and initialised state arrays.
    """
    road = {}
    road['name']   = 'Evergreen Rd Northbound'
    road['idx']    = 2
    road['length'] = 6500
    road['Nx']     = road['length'] // sim['dx']

    road['x_edges']   = np.arange(0, road['length'] + sim['dx'],
                                   sim['dx'], dtype=float)
    road['x_centers'] = road['x_edges'][:-1] + sim['dx'] / 2.0

    road['boundary_idx'] = [5, 4]   # [SouthBoundary, NorthBoundary]

    xc = road['x_centers']
    N_lanes = np.zeros(road['Nx'], dtype=int)
    N_lanes[(xc >=   1) & (xc <=  500)] = 3
    N_lanes[(xc >= 501) & (xc <= 2500)] = 2
    N_lanes[(xc >= 2501) & (xc <= 6500)] = 3
    road['N_lanes'] = N_lanes

    signal = {}
    signal['x']             = 500.0
    signal['green']         = 45.0
    signal['red']           = 75.0
    signal['Qsat_per_lane'] = 1900.0 / 3600.0
    signal['period']        = signal['green'] + signal['red']
    sig_cells = np.where(xc >= signal['x'])[0]
    signal['cell'] = int(sig_cells[0]) + 1 if len(sig_cells) > 0 else road['Nx']
    signal['Qsat'] = signal['Qsat_per_lane'] * N_lanes[signal['cell'] - 1]
    road['signal']    = signal
    road['is_signal'] = np.zeros(road['Nx'], dtype=bool)
    road['is_signal'][signal['cell'] - 1] = True

    u_free = np.full(road['Nx'], 40.0 * sim['mph_to_fts'])

    road['FD'] = dict(fd)
    road['FD']['vf'] = u_free

    Nx, Nt = road['Nx'], sim['Nt']
    road['rho']       = np.zeros((Nx, Nt))
    road['rho'][:, 0] = 0.01 * fd['rho_c']
    sc = signal['cell'] - 1
    # MATLAB uses signal.cell-1 : signal.cell+1 (inclusive) — guard bounds
    road['rho'][max(0, sc - 1):min(Nx, sc + 2), 0] = 0.01 * fd['rho_c']
    road['F']         = np.zeros((Nx + 1, Nt))
    road['F_desired'] = np.zeros((2, Nt))
    road['g']         = np.zeros((1, Nt - 1))
    road['g_eff']     = np.zeros((Nx, Nt - 1))
    road['s']         = np.zeros((Nx, Nt))

    return road
