"""
run_simulation.py
=================
Top-level runner for the macroscopic corridor traffic simulation platform.

Usage
-----
    python run_simulation.py                                   # UM-Dearborn demo, full mode
    python run_simulation.py --project projects/UM_Dearborn   # explicit project path
    python run_simulation.py --mode demand_only               # skip LWR solver (fast calibration)

Modes
-----
    full         Run the LWR solver and produce all enabled plots.
    demand_only  Skip the LWR solver; only build demand model and boundary
                 plots (fast calibration).

All project-specific data (geometry, TAZs, demand data) is read from the
given --project directory.  No project literals remain in this file.
"""

import argparse
import time
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')           # non-interactive backend; swap to 'TkAgg' for live display
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors

from corridor_sim.engine.demand_model        import classic_traffic_demand_model
from corridor_sim.engine.load_truth_data     import load_truth_data
from corridor_sim.engine.load_od_access      import load_od_access
from corridor_sim.engine.apply_scenario      import (apply_scenario, load_scenario_list,
                                                      scenario_config_exists)
from corridor_sim.engine.plot_scenario_comparison import (plot_scenario_comparison,
                                                           print_scenario_comparison_table)
from corridor_sim.engine.helpers             import (
    parametric_peaks, hour_index,
    apply_figure_format, export_figure,
    plot_road_geometry, map_access_points, map_intersection_points,
)
from corridor_sim.engine.lwr_model           import lwr_model
from corridor_sim.engine.initialize_corridor import (initialize_corridor,
                                                      load_corridor_config)


# ============================================================
#  Project config loaders
# ============================================================

def _load_taz_config(project_path: Path) -> tuple:
    """
    Read taz_config.xlsx from the project folder.

    Returns
    -------
    TAZ           : dict  Zone definitions and temporal profiles.
    intersections : list  Intersection connection definitions.
    QUICKTUNE     : dict  Boundary flow scale factors.
    """
    xf = project_path / "taz_config.xlsx"

    # Zones
    z_df = pd.read_excel(xf, sheet_name="Zones", header=0)
    TAZ = {
        'names':        z_df['ZoneName'].tolist(),
        'xLocation':    z_df['xLocation_ft'].tolist(),
        'yLocation':    z_df['yLocation_ft'].tolist(),
        'peak_arrive':  z_df['PeakArrive_hr'].tolist(),
        'sigma_arrive': z_df['SigmaArrive_hr'].tolist(),
        'peak_depart':  z_df['PeakDepart_hr'].tolist(),
        'sigma_depart': z_df['SigmaDepart_hr'].tolist(),
    }

    # Build temporal profiles
    Nzones = len(TAZ['names'])
    TAZ['f_arrive'] = np.zeros((24, Nzones))
    TAZ['f_depart'] = np.zeros((24, Nzones))
    for k in range(Nzones):
        f_raw_arr = parametric_peaks({
            'w': 1, 'mu': TAZ['peak_arrive'][k], 'sigma': TAZ['sigma_arrive'][k]
        })
        TAZ['f_arrive'][:, k] = f_raw_arr / f_raw_arr.sum()
        f_raw_dep = parametric_peaks({
            'w': 1, 'mu': TAZ['peak_depart'][k], 'sigma': TAZ['sigma_depart'][k]
        })
        TAZ['f_depart'][:, k] = f_raw_dep / f_raw_dep.sum()

    # Access points — each row in the sheet is one (TAZ, road, x, split, name) entry
    ap_df = pd.read_excel(xf, sheet_name="AccessPoints", header=0)
    # Group by (TazIndex, RoadName) to reconstruct multi-point access point dicts
    ap_groups = {}
    for _, row in ap_df.iterrows():
        key = (int(row['TazIndex']), str(row['RoadName']))
        ap_groups.setdefault(key, {'xLocal': [], 'split': [], 'name': []})
        ap_groups[key]['xLocal'].append(float(row['XLocal_ft']))
        ap_groups[key]['split'].append(float(row['Split']))
        ap_groups[key]['name'].append(str(row['AccessPointName']))
    TAZ['AccessPoints'] = [
        {
            'taz_idx':  k[0],
            'roadName': k[1],
            'xLocal':   v['xLocal'],
            'split':    v['split'],
            'name':     v['name'],
        }
        for k, v in ap_groups.items()
    ]

    # Intersections
    i_df = pd.read_excel(xf, sheet_name="Intersections", header=0)
    intersections = []
    for _, row in i_df.iterrows():
        ext_tazs = [int(x.strip()) for x in str(row['ExternalTazIndices']).split(',')]
        intersections.append({
            'roadName':          str(row['RoadName']),
            'xLocal':            float(row['XLocal_ft']),
            'taz_idx_external':  ext_tazs,
        })

    # QuickTune
    qt_df = pd.read_excel(xf, sheet_name="QuickTune", header=0)
    QUICKTUNE = dict(zip(qt_df['Key'].tolist(),
                         qt_df['ScaleFactor'].tolist()))

    return TAZ, intersections, QUICKTUNE


# ============================================================
#  CLI argument parsing
# ============================================================
def _parse_args():
    parser = argparse.ArgumentParser(description='Corridor Traffic Simulation')
    parser.add_argument(
        '--project', default='projects/UM_Dearborn',
        help='Path to the project folder (default: projects/UM_Dearborn)')
    parser.add_argument('--mode', default='full',
                        choices=['full', 'demand_only'],
                        help="'full' = run LWR solver; "
                             "'demand_only' = skip solver (fast calibration)")
    parser.add_argument(
        '--scenario', default=None,
        help='Named scenario to apply (must exist in scenario_config.xlsx). '
             'Omit or leave blank to run the baseline.')
    return parser.parse_args()


# ============================================================
#  Main entry point
# ============================================================
def main(project: str = 'projects/UM_Dearborn',
         mode:    str = 'full',
         scenario: str = None):
    project_path = Path(project)

    # ----------------------------------------------------------------
    # Simulation settings
    # ----------------------------------------------------------------
    sim = {}
    sim['dt']         = 1            # [s] time step
    sim['dx']         = 500          # [ft] spatial cell length
    sim['T_end']      = 24 * 3600    # [s] total simulation time
    sim['t']          = np.arange(0, sim['T_end'] + sim['dt'], sim['dt'], dtype=float)
    sim['Nt']         = len(sim['t'])
    sim['mph_to_fts'] = 5280.0 / 3600.0
    sim['mode']       = mode
    print('Done setting up simulation...')

    # ----------------------------------------------------------------
    # Fundamental Diagram (Greenshields)
    # ----------------------------------------------------------------
    FD = {}
    FD['model'] = 'Greenshields'
    FD['rho_j'] = 1.0 / 18.0                     # [veh/ft/lane] jam density
    FD['rho_c'] = FD['rho_j'] / 2.0              # critical density
    FD['Q']     = lambda rho, vf: vf * rho * (1.0 - rho / FD['rho_j'])

    # ----------------------------------------------------------------
    # Road geometry — loaded from corridor_config.xlsx
    # ----------------------------------------------------------------
    corridor_configs = load_corridor_config(project_path)
    all_roads = [initialize_corridor(cfg, sim, FD) for cfg in corridor_configs]
    _dir_map = {'Southbound': 'SB', 'Northbound': 'NB', 'Eastbound': 'EB', 'Westbound': 'WB'}
    road_keys = [_dir_map.get(road['name'].split()[-1], road['name'][:4].upper())
                 for road in all_roads]
    # Rebuild named references for downstream logic
    ev_sb, ev_nb, hub_eb, hub_wb = all_roads[0], all_roads[1], all_roads[2], all_roads[3]
    print('Done configuring road geometry...')

    # ----------------------------------------------------------------
    # TAZ, intersection, and QuickTune — loaded from taz_config.xlsx
    # ----------------------------------------------------------------
    TAZ, intersections, QUICKTUNE = _load_taz_config(project_path)
    Nzones = len(TAZ['names'])
    print('Done configuring TAZs...')

    # ----------------------------------------------------------------
    # Map access points and intersections to road segment indices
    # ----------------------------------------------------------------
    ev_sb  = map_access_points(ev_sb,  TAZ)
    ev_sb  = map_intersection_points(ev_sb,  intersections)
    ev_nb  = map_access_points(ev_nb,  TAZ)
    ev_nb  = map_intersection_points(ev_nb,  intersections)
    hub_eb = map_intersection_points(hub_eb, intersections)
    hub_eb = map_access_points(hub_eb, TAZ)
    hub_wb = map_intersection_points(hub_wb, intersections)
    hub_wb = map_access_points(hub_wb, TAZ)

    # Rebuild all_roads with the mapped road dicts
    all_roads = [ev_sb, ev_nb, hub_eb, hub_wb]

    # ----------------------------------------------------------------
    # OD-access tensor — loaded from taz_config.xlsx
    # ----------------------------------------------------------------
    od_access = load_od_access(project_path, [r['name'] for r in all_roads])

    # ----------------------------------------------------------------
    # Apply scenario overrides (before demand model runs)
    # ----------------------------------------------------------------
    auto_share = None
    if scenario and scenario_config_exists(project_path):
        print(f'Applying scenario: {scenario}')
        corridor_configs, FD, TAZ, intersections, QUICKTUNE, od_access, auto_share = \
            apply_scenario(
                corridor_configs, FD, TAZ, intersections, QUICKTUNE, od_access,
                scenario_name=scenario,
                project_path=project_path,
                sim=sim,
            )
        # Re-initialise corridors if signal overrides changed their parameters
        all_roads = [initialize_corridor(cfg, sim, FD) for cfg in corridor_configs]
        all_roads = [map_access_points(r, TAZ) for r in all_roads]
        all_roads = [map_intersection_points(r, intersections) for r in all_roads]
        ev_sb, ev_nb, hub_eb, hub_wb = all_roads[0], all_roads[1], all_roads[2], all_roads[3]
        print('Done applying scenario overrides...')

    # ----------------------------------------------------------------
    # Four-step demand model — reads xlsx from project_path
    # ----------------------------------------------------------------
    demand = classic_traffic_demand_model(TAZ,
                                          project_path=project_path,
                                          od_access=od_access,
                                          auto_share=auto_share)
    print('Done loading 4-step model...')

    # ----------------------------------------------------------------
    # Apply QuickTune scale factors
    # QuickTune keys are constructed as {direction_abbrev}_{in|out}
    # e.g. 'SB_in', 'SB_out', 'NB_in', ... loaded from taz_config.xlsx
    # ----------------------------------------------------------------
    qt_raw = {
        'V_taz_depart': demand['V_taz_depart'].copy(),
        'V_taz_arrive': demand['V_taz_arrive'].copy(),
    }

    for r_idx, road in enumerate(all_roads):
        rkey = road_keys[r_idx]
        bnd_in  = road['boundary_idx'][0]   # 1-based TAZ index, 0 = intersection
        bnd_out = road['boundary_idx'][1]

        # Scale upstream boundary inflow
        qt_in = QUICKTUNE.get(f'{rkey}_in', 1.0)
        if bnd_in != 0:
            demand['V_taz_depart'][r_idx, bnd_in - 1] *= qt_in
        else:
            # Intersection side: scale all external TAZ departures for this road
            intr = next(i for i in intersections if i['roadName'] == road['name'])
            for k in intr['taz_idx_external']:
                demand['V_taz_depart'][r_idx, k - 1] *= qt_in

        # Scale downstream boundary outflow
        qt_out = QUICKTUNE.get(f'{rkey}_out', 1.0)
        if bnd_out != 0:
            demand['V_taz_arrive'][r_idx, bnd_out - 1] *= qt_out
        else:
            intr = next(i for i in intersections if i['roadName'] == road['name'])
            for k in intr['taz_idx_external']:
                demand['V_taz_arrive'][r_idx, k - 1] *= qt_out

    print('Done applying Quick Tune scale factors...')

    # ----------------------------------------------------------------
    # Truth data (MDOT)
    # ----------------------------------------------------------------
    for road in all_roads:
        road['Truth'] = load_truth_data(project_path, road['name'])
    ev_sb, ev_nb, hub_eb, hub_wb = all_roads[0], all_roads[1], all_roads[2], all_roads[3]
    print('Done loading MDOT data...')

    all_roads  = [ev_sb, ev_nb, hub_eb, hub_wb]
    road_keys  = ['SB', 'NB', 'EB', 'WB']

    # ================================================================
    #  LWR simulation solver loop
    # ================================================================
    if mode == 'full':
        # Extract state arrays from road dicts for performance
        rho_SB = ev_sb['rho'];   F_SB = ev_sb['F']
        F_SB_desired = ev_sb['F_desired']
        g_SB   = ev_sb['g'];     g_eff_SB = ev_sb['g_eff'];  s_SB = ev_sb['s']
        del ev_sb['rho'], ev_sb['F'], ev_sb['F_desired'], ev_sb['g'], ev_sb['g_eff'], ev_sb['s']

        rho_NB = ev_nb['rho'];   F_NB = ev_nb['F']
        F_NB_desired = ev_nb['F_desired']
        g_NB   = ev_nb['g'];     g_eff_NB = ev_nb['g_eff'];  s_NB = ev_nb['s']
        del ev_nb['rho'], ev_nb['F'], ev_nb['F_desired'], ev_nb['g'], ev_nb['g_eff'], ev_nb['s']

        rho_EB = hub_eb['rho'];  F_EB = hub_eb['F']
        F_EB_desired = hub_eb['F_desired']
        g_EB   = hub_eb['g'];    g_eff_EB = hub_eb['g_eff']; s_EB = hub_eb['s']
        del hub_eb['rho'], hub_eb['F'], hub_eb['F_desired'], hub_eb['g'], hub_eb['g_eff'], hub_eb['s']

        rho_WB = hub_wb['rho'];  F_WB = hub_wb['F']
        F_WB_desired = hub_wb['F_desired']
        g_WB   = hub_wb['g'];    g_eff_WB = hub_wb['g_eff']; s_WB = hub_wb['s']
        del hub_wb['rho'], hub_wb['F'], hub_wb['F_desired'], hub_wb['g'], hub_wb['g_eff'], hub_wb['s']

        print('==================')
        print('\n BEGIN SIMULATION \n')
        print('==================')
        sim_tic = time.time()

        for n in range(sim['Nt'] - 1):
            sim['n'] = n
            sim['h'] = hour_index(sim['t'][n])
            if n % 3600 == 0:
                print(f"Sim Hour: {sim['h']:2d} / 24  "
                      f"(wall time: {time.time() - sim_tic:.1f} s)")

            (rho_SB[:, n+1], F_SB[:, n], F_SB_desired[:, n],
             g_SB[0, n], g_eff_SB[:, n], s_SB[:, n]) = \
                lwr_model(ev_sb, rho_SB[:, n], demand, TAZ, sim)

            (rho_NB[:, n+1], F_NB[:, n], F_NB_desired[:, n],
             g_NB[0, n], g_eff_NB[:, n], s_NB[:, n]) = \
                lwr_model(ev_nb, rho_NB[:, n], demand, TAZ, sim)

            (rho_EB[:, n+1], F_EB[:, n], F_EB_desired[:, n],
             g_EB[0, n], g_eff_EB[:, n], s_EB[:, n]) = \
                lwr_model(hub_eb, rho_EB[:, n], demand, TAZ, sim)

            (rho_WB[:, n+1], F_WB[:, n], F_WB_desired[:, n],
             g_WB[0, n], g_eff_WB[:, n], s_WB[:, n]) = \
                lwr_model(hub_wb, rho_WB[:, n], demand, TAZ, sim)

        print(f'Simulation complete. Wall time: {time.time() - sim_tic:.1f} s')

        # Restore state arrays into road dicts
        ev_sb['rho']  = rho_SB;  ev_sb['F']  = F_SB
        ev_sb['F_desired']  = F_SB_desired
        ev_sb['g']    = g_SB;    ev_sb['g_eff']  = g_eff_SB;   ev_sb['s']  = s_SB

        ev_nb['rho']  = rho_NB;  ev_nb['F']  = F_NB
        ev_nb['F_desired']  = F_NB_desired
        ev_nb['g']    = g_NB;    ev_nb['g_eff']  = g_eff_NB;   ev_nb['s']  = s_NB

        hub_eb['rho'] = rho_EB;  hub_eb['F'] = F_EB
        hub_eb['F_desired'] = F_EB_desired
        hub_eb['g']   = g_EB;    hub_eb['g_eff'] = g_eff_EB;   hub_eb['s'] = s_EB
        # Boundary proxy: use segment 2 flux as segment 1 (intersection side)
        hub_eb['F'][0, :] = F_EB[1, :]

        hub_wb['rho'] = rho_WB;  hub_wb['F'] = F_WB
        hub_wb['F_desired'] = F_WB_desired
        hub_wb['g']   = g_WB;    hub_wb['g_eff'] = g_eff_WB;   hub_wb['s'] = s_WB

        # F_desired special cases for Hubbard Rd intersection dynamics
        ev_sb_temporal = ev_sb['F'][0, :] / (np.sum(ev_sb['F'][0, :]) + 1e-12)
        ev_nb_temporal = ev_nb['F'][0, :] / (np.sum(ev_nb['F'][0, :]) + 1e-12)
        avg_temporal   = (ev_sb_temporal + ev_nb_temporal)
        avg_temporal   = avg_temporal / (avg_temporal.sum() + 1e-12)

        intr_eb_tazs = next(i for i in intersections if i['roadName'] == hub_eb['name'])['taz_idx_external']
        intr_wb_tazs = next(i for i in intersections if i['roadName'] == hub_wb['name'])['taz_idx_external']
        hub_eb['F_desired'][0, :] = (
            avg_temporal
            * np.sum(demand['V_taz_depart'][2, [k - 1 for k in intr_eb_tazs]])
        )
        hub_wb['F_desired'][1, :] = (
            avg_temporal
            * np.sum(demand['V_taz_arrive'][3, [k - 1 for k in intr_wb_tazs]])
        )

        # Rebuild all_roads list with updated dicts
        all_roads = [ev_sb, ev_nb, hub_eb, hub_wb]

    # ================================================================
    #  Plot controls
    # ================================================================
    plots = {
        'demand_boundary':     True,
        'tuning_boundary':     False,
        'tuning_conservation': False,
        'space_time':          True,
        'signal_timing':       False,
        'source_sink':         False,
        'od_matrix':           True,
        'road_geometry':       True,
        'road_SB': True,
        'road_NB': True,
        'road_EB': True,
        'road_WB': True,
    }
    road_enabled = [plots['road_SB'], plots['road_NB'],
                    plots['road_EB'], plots['road_WB']]

    # ================================================================
    #  Plot formatting
    # ================================================================
    plotfmt = {
        'font':       'DejaVu Sans',
        'sgtitle_fs': 14,
        'title_fs':   12,
        'label_fs':   11,
        'tick_fs':    10,
        'legend_fs':  10,
        'lw':          2,
        'ms':          5,
        'ax_box':    'on',
        'tick_dir':  'in',
        'ax_lw':      0.75,
        'sz_wide':   (12.0, 4.5),
        'sz_tall':   (14.0, 6.5),
        'sz_half':   (10.0, 4.0),
        'sz_single': ( 7.0, 5.0),
        'sz_stack':  ( 7.0, 8.0),
        'export':    False,
        'dpi':        300,
        'export_dir': 'figures',
    }

    pts_per_hr = round(3600 / sim['dt'])
    Nhrs       = (sim['Nt'] - 1) // pts_per_hr
    hrs        = list(range(1, Nhrs + 1))

    # ================================================================
    #  Console: demand model summary
    # ================================================================
    print('\n========== 4-Step Demand Model Summary ==========')
    print(f"{'Zone':<20} {'P [p-t/d]':>10} {'A [p-t/d]':>10} {'P-A':>10}")
    for iz in range(Nzones):
        print(f"{TAZ['names'][iz]:<20} "
              f"{demand['P'][iz]:>10.0f} "
              f"{demand['A'][iz]:>10.0f} "
              f"{demand['P'][iz] - demand['A'][iz]:>10.0f}")
    print(f"{'TOTAL':<20} {demand['P'].sum():>10.0f} {demand['A'].sum():>10.0f}")

    # ================================================================
    #  Console: boundary tuning report
    # ================================================================
    dm = demand
    print('\n========== Boundary Tuning Report ==========')
    print(f"{'Road':<6} {'Dir':<4} {'Boundary TAZ':<16} "
          f"{'MDOT[v/d]':>10} {'RawOD[v/d]':>10} {'QT Scale':>9} "
          f"{'Scaled[v/d]':>11} {'Error%':>8} {'Rec.Scale':>10}")
    print('-' * 90)

    bnd_cfg = [
        (0, 'In',  3, 'SB', 'NorthBoundary', 'SB_in'),
        (0, 'Out', 4, 'SB', 'SouthBoundary', 'SB_out'),
        (1, 'In',  4, 'NB', 'SouthBoundary', 'NB_in'),
        (1, 'Out', 3, 'NB', 'NorthBoundary', 'NB_out'),
        (2, 'In',  None, 'EB', 'Intersection',  'EB_in'),
        (2, 'Out', 5, 'EB', 'EastBoundary',  'EB_out'),
        (3, 'In',  5, 'WB', 'EastBoundary',  'WB_in'),
        (3, 'Out', None, 'WB', 'Intersection',  'WB_out'),
    ]
    for r, direction, taz_0based, rkey, taz_lbl, qt_field in bnd_cfg:
        road_b = all_roads[r]
        intr_r = next((i for i in intersections if i['roadName'] == road_b['name']), None)
        mdot_daily = np.sum(road_b['Truth']['MDOT_inflow']) * 3600
        qt_applied = QUICKTUNE[qt_field]

        if direction == 'In':
            if taz_0based is None:
                raw_od   = sum(qt_raw['V_taz_depart'][r, k - 1]
                               for k in intr_r['taz_idx_external'])
                od_daily = sum(dm['V_taz_depart'][r, k - 1]
                               for k in intr_r['taz_idx_external'])
            else:
                raw_od   = qt_raw['V_taz_depart'][r, taz_0based]
                od_daily = dm['V_taz_depart'][r, taz_0based]
        else:
            if taz_0based is None:
                raw_od   = sum(qt_raw['V_taz_arrive'][r, k - 1]
                               for k in intr_r['taz_idx_external'])
                od_daily = sum(dm['V_taz_arrive'][r, k - 1]
                               for k in intr_r['taz_idx_external'])
            else:
                raw_od   = qt_raw['V_taz_arrive'][r, taz_0based]
                od_daily = dm['V_taz_arrive'][r, taz_0based]

        err_pct   = (od_daily - mdot_daily) / max(mdot_daily, 1) * 100
        rec_scale = mdot_daily / max(od_daily, 1)
        print(f"{rkey:<6} {direction:<4} {taz_lbl:<16} "
              f"{mdot_daily:>10.0f} {raw_od:>10.0f} {qt_applied:>9.3f} "
              f"{od_daily:>11.0f} {err_pct:>7.1f}% {rec_scale:>10.3f}")
    print('\n  Tip: set QUICKTUNE[field] = current_QT × Rec.Scale to converge.\n')

    # TAZ temporal parameter recommendations
    print('========== TAZ Temporal Parameter Recommendations ==========')
    h_vec = np.arange(1, 25, dtype=float)
    for r, road_b in enumerate(all_roads):
        dist_in  = road_b['Truth']['MDOT_inflow']
        dist_out = road_b['Truth']['MDOT_outflow']
        if dist_in.sum() > 0:
            mu_in  = np.sum(h_vec * dist_in)  / dist_in.sum()
            sig_in = np.sqrt(max(np.sum((h_vec - mu_in) ** 2 * dist_in) / dist_in.sum(), 0))
            mu_out  = np.sum(h_vec * dist_out) / dist_out.sum()
            sig_out = np.sqrt(max(np.sum((h_vec - mu_out) ** 2 * dist_out) / dist_out.sum(), 0))
            print(f"  {road_keys[r]}: peak_arrive={mu_in:.1f} h, sigma_arrive={sig_in:.1f} h "
                  f"| peak_depart={mu_out:.1f} h, sigma_depart={sig_out:.1f} h")
    print()

    # ================================================================
    #  Custom ITE colour maps
    # ================================================================
    # Full-range colour map (space-time density)
    res = 20
    R1 = np.linspace(100, 100, res // 2)
    R2 = np.linspace(100, 234, res // 2 + 1)
    G1 = np.linspace( 38, 167, res // 2)
    G2 = np.linspace(167, 170, res // 2 + 1)
    B1 = np.flip(np.linspace( 11, 103, res // 2))
    B2 = np.flip(np.linspace(  0,  11, res // 2 + 1))
    R  = np.concatenate([R1, R2[1:]])
    G  = np.concatenate([G1, G2[1:]])
    B  = np.concatenate([B1, B2[1:]])
    ite_cmap_full = mcolors.ListedColormap(
        np.column_stack([R, G, B]) / 255.0)

    # Simple colour map (OD matrix)
    n_s = 20
    Rs = np.flip(np.linspace(  0, 136, n_s))
    Gs = np.flip(np.linspace( 88, 139, n_s))
    Bs = np.flip(np.linspace(124, 141, n_s))
    ite_cmap_simple = mcolors.ListedColormap(
        np.column_stack([Rs, Gs, Bs]) / 255.0)

    # ================================================================
    #  Demand boundary plots
    # ================================================================
    if plots['demand_boundary']:
        h_plot = list(range(1, 25))
        for r, road_b in enumerate(all_roads):
            bnd_in_taz = road_b['boundary_idx'][0]
            intr_r = next((i for i in intersections if i['roadName'] == road_b['name']), None)

            if bnd_in_taz == 0:
                od_in_hrly = np.zeros(24)
                for k in intr_r['taz_idx_external']:
                    od_in_hrly += (dm['V_taz_depart'][r, k - 1]
                                   * TAZ['f_depart'][:, k - 1])
            else:
                k0 = bnd_in_taz - 1
                od_in_hrly = dm['V_taz_depart'][r, k0] * TAZ['f_depart'][:, k0]

            bnd_out_taz = road_b['boundary_idx'][1]
            if bnd_out_taz == 0:
                od_out_hrly = np.zeros(24)
                for k in intr_r['taz_idx_external']:
                    od_out_hrly += (dm['V_taz_arrive'][r, k - 1]
                                    * TAZ['f_arrive'][:, k - 1])
            else:
                k0 = bnd_out_taz - 1
                od_out_hrly = dm['V_taz_arrive'][r, k0] * TAZ['f_arrive'][:, k0]

            mdot_in_hrly  = road_b['Truth']['MDOT_inflow']  * 3600
            mdot_out_hrly = road_b['Truth']['MDOT_outflow'] * 3600

            fig, axes = plt.subplots(1, 3, facecolor='white')
            fig.suptitle(f"OD Boundary Profile vs MDOT: {road_b['name']}")

            ax = axes[0]
            ax.bar(h_plot, mdot_in_hrly, color=(0.2, 0.4, 0.8), alpha=0.5, label='MDOT Truth')
            ax.plot(h_plot, od_in_hrly, 'r-o', label='OD Model')
            ax.set_ylabel('Flow [veh/hr]'); ax.set_xlabel('Hour of Day')
            ax.set_title('Inflow'); ax.grid(True); ax.legend(loc='upper left')
            ax.set_xticks([0, 6, 12, 18, 24]); ax.set_xlim(0.5, 24.5)

            ax = axes[1]
            ax.bar(h_plot, mdot_out_hrly, color=(0.2, 0.7, 0.3), alpha=0.5, label='MDOT Truth')
            ax.plot(h_plot, od_out_hrly, 'r-o', label='OD Model')
            ax.set_ylabel('Flow [veh/hr]'); ax.set_xlabel('Hour of Day')
            ax.set_title('Outflow'); ax.grid(True); ax.legend(loc='upper left')
            ax.set_xticks([0, 6, 12, 18, 24]); ax.set_xlim(0.5, 24.5)

            ax = axes[2]
            daily_mat = np.array([
                [sum(mdot_in_hrly), sum(mdot_out_hrly)],
                [sum(od_in_hrly),   sum(od_out_hrly)],
            ])
            x_cats = np.arange(2)
            w = 0.35
            ax.bar(x_cats - w/2, daily_mat[0], w, label='MDOT Truth',
                   color=(0.2, 0.4, 0.8))
            ax.bar(x_cats + w/2, daily_mat[1], w, label='OD Model',
                   color=(0.9, 0.3, 0.3))
            ax.set_xticks(x_cats); ax.set_xticklabels(['Inflow', 'Outflow'])
            ax.set_ylabel('Vehicles [veh/day]'); ax.set_title('Daily Volume')
            ax.legend(); ax.grid(True)

            apply_figure_format(fig, plotfmt['sz_wide'], plotfmt)
            export_figure(fig, f"demandBoundary_{road_keys[r]}", plotfmt)
            plt.close(fig)

    # ================================================================
    #  Tuning boundary plots (full mode only)
    # ================================================================
    if plots['tuning_boundary'] and mode == 'full':
        Npts = Nhrs * pts_per_hr
        for r, road_b in enumerate(all_roads):
            has_mdot = (any(road_b['Truth']['MDOT_inflow'] > 0) or
                        any(road_b['Truth']['MDOT_outflow'] > 0))

            F_in_hrly      = road_b['F'][0,           :Npts].reshape(pts_per_hr, Nhrs, order='F').sum(axis=0) * sim['dt']
            F_in_des_hrly  = road_b['F_desired'][0,   :Npts].reshape(pts_per_hr, Nhrs, order='F').sum(axis=0) * sim['dt']
            F_out_hrly     = road_b['F'][road_b['Nx'], :Npts].reshape(pts_per_hr, Nhrs, order='F').sum(axis=0) * sim['dt']
            F_out_des_hrly = road_b['F_desired'][1,    :Npts].reshape(pts_per_hr, Nhrs, order='F').sum(axis=0) * sim['dt']

            if has_mdot:
                mdot_in_hrly  = road_b['Truth']['MDOT_inflow'][:Nhrs]  * 3600
                mdot_out_hrly = road_b['Truth']['MDOT_outflow'][:Nhrs] * 3600

            fig, axes = plt.subplots(2, 3, facecolor='white')
            fig.suptitle(f"Boundary Flow Tuning: {road_b['name']}")

            ax = axes[0, 0]; ax.hold = True
            if has_mdot:
                ax.bar(hrs, mdot_in_hrly, color=(0.2, 0.4, 0.8), alpha=0.5, label='MDOT Truth')
            ax.plot(hrs, F_in_des_hrly, 'k--o', label='OD Desired')
            ax.plot(hrs, F_in_hrly,     'r-o',  label='Sim Actual')
            ax.set_ylabel('Flow [veh/hr]'); ax.set_xlabel('Hour of Day')
            ax.set_title('Upstream Inflow'); ax.grid(True)
            ax.legend(loc='upper left'); ax.set_xlim(0, 24)

            ax = axes[0, 1]
            if has_mdot:
                ax.bar(hrs, mdot_out_hrly, color=(0.2, 0.7, 0.3), alpha=0.5, label='MDOT Truth')
            ax.plot(hrs, F_out_des_hrly, 'k--o', label='OD Desired')
            ax.plot(hrs, F_out_hrly,     'r-o',  label='Sim Actual')
            ax.set_ylabel('Flow [veh/hr]'); ax.set_xlabel('Hour of Day')
            ax.set_title('Downstream Outflow'); ax.grid(True)
            ax.legend(loc='upper left'); ax.set_xlim(0, 24)

            ax = axes[0, 2]
            if has_mdot:
                daily_mat = np.array([
                    [sum(mdot_in_hrly),   sum(mdot_out_hrly)],
                    [sum(F_in_des_hrly),  sum(F_out_des_hrly)],
                    [sum(F_in_hrly),       sum(F_out_hrly)],
                ])
                x_c = np.arange(2); w = 0.25
                ax.bar(x_c - w, daily_mat[0], w, label='MDOT Truth', color=(0.2, 0.4, 0.8))
                ax.bar(x_c,     daily_mat[1], w, label='OD Desired',  color=(0.7, 0.7, 0.7))
                ax.bar(x_c + w, daily_mat[2], w, label='Sim Actual',  color=(0.9, 0.3, 0.3))
                ax.set_xticks(x_c); ax.set_xticklabels(['Inflow', 'Outflow'])
                ax.legend(); ax.grid(True)
            ax.set_ylabel('Vehicles [veh/day]'); ax.set_title('Daily Volume Summary')

            for col, (F_hrly, F_des, mdot_hrly, lbl) in enumerate([
                (F_in_hrly,  F_in_des_hrly,  mdot_in_hrly  if has_mdot else None, 'Inflow % Error vs MDOT'),
                (F_out_hrly, F_out_des_hrly, mdot_out_hrly if has_mdot else None, 'Outflow % Error vs MDOT'),
            ]):
                ax = axes[1, col]
                if has_mdot and mdot_hrly is not None:
                    denom = np.maximum(mdot_hrly, 1)
                    ax.bar(hrs, (F_des  - mdot_hrly) / denom * 100,
                           color=(0.7, 0.7, 0.7), alpha=0.7, label='OD Desired')
                    ax.plot(hrs, (F_hrly - mdot_hrly) / denom * 100,
                            'r-o', label='Sim Actual')
                    ax.axhline(0, color='k', linestyle='--', linewidth=1)
                    ax.set_ylabel('Error [%]'); ax.set_xlabel('Hour of Day')
                    ax.set_title(lbl); ax.grid(True); ax.legend()
                else:
                    ax.text(0.5, 0.5, 'No MDOT data', ha='center', transform=ax.transAxes)
                    ax.axis('off')

            ax = axes[1, 2]
            if has_mdot:
                vals = [
                    (sum(F_in_des_hrly)  - sum(mdot_in_hrly))  / sum(mdot_in_hrly)  * 100,
                    (sum(F_in_hrly)      - sum(mdot_in_hrly))  / sum(mdot_in_hrly)  * 100,
                    (sum(F_out_des_hrly) - sum(mdot_out_hrly)) / sum(mdot_out_hrly) * 100,
                    (sum(F_out_hrly)     - sum(mdot_out_hrly)) / sum(mdot_out_hrly) * 100,
                ]
                lbls = ['In: Desired', 'In: Actual', 'Out: Desired', 'Out: Actual']
                colors = [(0.7, 0.7, 0.7), (0.9, 0.3, 0.3),
                          (0.7, 0.7, 0.7), (0.9, 0.3, 0.3)]
                ax.bar(lbls, vals, color=colors)
                ax.axhline(0, color='k', linestyle='--', linewidth=1)
                ax.set_ylabel('Daily Volume % Error vs MDOT')
                ax.set_title('Daily % Error Summary'); ax.grid(True)
                plt.setp(ax.get_xticklabels(), rotation=15)

            apply_figure_format(fig, plotfmt['sz_tall'], plotfmt)
            export_figure(fig, f"boundaryTuning_{road_keys[r]}", plotfmt)
            plt.close(fig)

    # ================================================================
    #  Trip conservation plot (full mode only)
    # ================================================================
    if plots['tuning_conservation'] and mode == 'full':
        Npts = Nhrs * pts_per_hr
        daily_mdot_in  = np.array([r['Truth']['MDOT_inflow'][:Nhrs].sum() * 3600
                                    for r in all_roads])
        daily_des_in   = np.array([r['F_desired'][0, :Npts].sum() * sim['dt']
                                    for r in all_roads])
        daily_act_in   = np.array([r['F'][0, :Npts].sum() * sim['dt']
                                    for r in all_roads])
        daily_mdot_out = np.array([r['Truth']['MDOT_outflow'][:Nhrs].sum() * 3600
                                    for r in all_roads])
        daily_des_out  = np.array([r['F_desired'][1, :Npts].sum() * sim['dt']
                                    for r in all_roads])
        daily_act_out  = np.array([r['F'][r['Nx'], :Npts].sum() * sim['dt']
                                    for r in all_roads])

        fig, axes = plt.subplots(1, 2, facecolor='white')
        fig.suptitle('Daily Trip Conservation: OD Model vs MDOT Truth vs Simulation')
        x_c = np.arange(len(all_roads)); w = 0.25
        for ax_idx, (daily_vals, title) in enumerate([
            ((daily_mdot_in, daily_des_in, daily_act_in), 'Upstream Inflow: Daily Total'),
            ((daily_mdot_out, daily_des_out, daily_act_out), 'Downstream Outflow: Daily Total'),
        ]):
            ax = axes[ax_idx]
            ax.bar(x_c - w, daily_vals[0], w, label='MDOT Truth', color=(0.2, 0.4, 0.8))
            ax.bar(x_c,     daily_vals[1], w, label='OD Desired',  color=(0.7, 0.7, 0.7))
            ax.bar(x_c + w, daily_vals[2], w, label='Sim Actual',  color=(0.9, 0.3, 0.3))
            ax.set_xticks(x_c); ax.set_xticklabels(road_keys)
            ax.set_ylabel('Vehicles [veh/day]'); ax.set_title(title)
            ax.legend(); ax.grid(True)
        apply_figure_format(fig, plotfmt['sz_half'], plotfmt)
        export_figure(fig, 'tripConservation', plotfmt)
        plt.close(fig)

    # ================================================================
    #  Space-time density diagrams
    # ================================================================
    if plots['space_time'] and mode == 'full':
        for r, road_b in enumerate(all_roads):
            if not road_enabled[r]:
                continue
            fig, ax = plt.subplots(facecolor='white')
            im = ax.imshow(
                road_b['rho'],
                aspect='auto',
                origin='lower',
                extent=[sim['t'][0] / 3600, sim['t'][-1] / 3600,
                        road_b['x_centers'][0], road_b['x_centers'][-1]],
                cmap=ite_cmap_full,
            )
            cb = fig.colorbar(im, ax=ax)
            cb.set_label('Vehicles/ft')
            ax.set_xlabel('Time [hr]')
            ax.set_ylabel('Position [ft]')
            ax.set_title(f"Space-Time Density: {road_b['name']}")
            apply_figure_format(fig, plotfmt['sz_single'], plotfmt)
            export_figure(fig, f"spaceTime_{road_keys[r]}", plotfmt)
            plt.close(fig)

    # ================================================================
    #  Signal timing diagrams
    # ================================================================
    if plots['signal_timing'] and mode == 'full':
        for r, road_b in enumerate(all_roads):
            if not road_enabled[r]:
                continue
            g_vec  = road_b['g'][0, :]
            g_plot = np.where(g_vec == 0, -1, g_vec).astype(float)
            band   = np.zeros((road_b['Nx'], sim['Nt'] - 1))
            band[road_b['signal']['cell'] - 1, :] = g_plot
            fig, ax = plt.subplots(facecolor='white')
            im = ax.imshow(
                band, aspect='auto', origin='lower',
                extent=[sim['t'][0] / 60, sim['t'][-2] / 60,
                        road_b['x_centers'][0], road_b['x_centers'][-1]],
                cmap=mcolors.ListedColormap([(0.6, 0, 0), (1, 1, 1), (0, 0.6, 0)]),
                vmin=-1, vmax=1,
            )
            cb = fig.colorbar(im, ax=ax, ticks=[-1, 0, 1])
            cb.ax.set_yticklabels(['Red', 'No Signal', 'Green'])
            ax.set_xlabel('Time [min]'); ax.set_ylabel('Position [ft]')
            ax.set_title(f"Signal Timing: {road_b['name']}")
            apply_figure_format(fig, plotfmt['sz_single'], plotfmt)
            export_figure(fig, f"signalTiming_{road_keys[r]}", plotfmt)
            plt.close(fig)

    # ================================================================
    #  Net source/sink time series
    # ================================================================
    if plots['source_sink'] and mode == 'full':
        for r, road_b in enumerate(all_roads):
            if not road_enabled[r]:
                continue
            aps = road_b.get('AccessPoints', [])
            if not aps:
                continue
            ap_segs  = [seg for ap in aps for seg in ap['xSegment']]
            ap_names = [name for ap in aps
                        for name in (ap['name'] if isinstance(ap['name'], list)
                                     else [ap['name']])]
            n_panels = len(ap_segs)
            fig, axes_list = plt.subplots(n_panels, 1, facecolor='white',
                                          squeeze=False)
            fig.suptitle(f"Net Source/Sink: {road_b['name']}")
            for idx_k, seg in enumerate(ap_segs):
                ax = axes_list[idx_k, 0]
                ax.plot(sim['t'] / 3600, road_b['s'][seg - 1, :])
                ax.set_ylabel('[veh/s]')
                ax.set_title(ap_names[idx_k] if idx_k < len(ap_names) else '')
                ax.grid(True)
            axes_list[-1, 0].set_xlabel('Time [hr]')
            apply_figure_format(fig, plotfmt['sz_stack'], plotfmt)
            export_figure(fig, f"sourceSink_{road_keys[r]}", plotfmt)
            plt.close(fig)

    # ================================================================
    #  OD matrix heatmap
    # ================================================================
    if plots['od_matrix']:
        fig, ax = plt.subplots(facecolor='white')
        im = ax.imshow(demand['T_vehicle'], cmap=ite_cmap_simple, aspect='auto')
        cb = fig.colorbar(im, ax=ax, location='bottom', pad=0.15)
        cb.set_label('Vehicles/Day')
        ax.set_xticks(range(Nzones)); ax.set_xticklabels(TAZ['names'], rotation=30, ha='right')
        ax.set_yticks(range(Nzones)); ax.set_yticklabels(TAZ['names'])
        ax.set_xlabel('Destination Zone'); ax.set_ylabel('Origin Zone')
        ax.set_title('OD Matrix: Vehicle Trips per Day (Gravity Model)')
        for i in range(Nzones):
            for j in range(Nzones):
                ax.text(j, i, f"{demand['T_vehicle'][i, j]:.0f}",
                        ha='center', va='center', color='white',
                        fontsize=plotfmt['legend_fs'])
        apply_figure_format(fig, plotfmt['sz_single'], plotfmt)
        export_figure(fig, 'odMatrix', plotfmt)
        plt.close(fig)

    # ================================================================
    #  Road geometry diagrams
    # ================================================================
    if plots['road_geometry']:
        for r, road_b in enumerate(all_roads):
            if not road_enabled[r]:
                continue
            aps = road_b.get('AccessPoints', [])
            ap_combined = {'xSegment': [], 'name': []}
            for ap in aps:
                ap_combined['xSegment'].extend(ap['xSegment'])
                names = ap['name'] if isinstance(ap['name'], list) else [ap['name']]
                ap_combined['name'].extend(names)

            fig = plot_road_geometry(
                sim, road_b,
                road_b['x_edges'], road_b['x_centers'],
                road_b['N_lanes'], road_b['signal'], ap_combined,
            )
            export_figure(fig, f"roadGeometry_{road_keys[r]}", plotfmt)
            plt.close(fig)

    print('\nAll plots complete.')

    if plotfmt.get('export', False):
        print('Figures saved to:', plotfmt['export_dir'])
    else:
        print('(export=False — figures not saved to disk)')
        print('Set plotfmt["export"] = True to write PNGs.')

    return {
        'sim':    sim,
        'demand': demand,
        'roads':  all_roads,
        'TAZ':    TAZ,
    }


# ============================================================
if __name__ == '__main__':
    args = _parse_args()
    main(project=args.project, mode=args.mode, scenario=args.scenario)
