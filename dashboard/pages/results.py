"""
results.py
==========
Dashboard page — Simulation Results.

Renders four tabbed panels from a completed simulation results dict:

  Space-Time    — density heatmap for each corridor
  OD Matrix     — vehicle trip OD matrix heatmap
  Boundary Flow — hourly OD model vs MDOT truth for each corridor
  Scenario Cmp  — side-by-side comparison if multiple scenarios were run

All plots are built with matplotlib then rendered via st.pyplot().
"""

from __future__ import annotations
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import streamlit as st


# ─── ITE colour maps (mirrors run_simulation.py) ──────────────────────────────

def _ite_cmap_full():
    res = 20
    R1 = np.linspace(100, 100, res // 2);  R2 = np.linspace(100, 234, res // 2 + 1)
    G1 = np.linspace( 38, 167, res // 2);  G2 = np.linspace(167, 170, res // 2 + 1)
    B1 = np.flip(np.linspace( 11, 103, res // 2))
    B2 = np.flip(np.linspace(  0,  11, res // 2 + 1))
    R = np.concatenate([R1, R2[1:]])
    G = np.concatenate([G1, G2[1:]])
    B = np.concatenate([B1, B2[1:]])
    return mcolors.ListedColormap(np.column_stack([R, G, B]) / 255.0)


def _ite_cmap_simple():
    n = 20
    Rs = np.flip(np.linspace(  0, 136, n))
    Gs = np.flip(np.linspace( 88, 139, n))
    Bs = np.flip(np.linspace(124, 141, n))
    return mcolors.ListedColormap(np.column_stack([Rs, Gs, Bs]) / 255.0)


# ─── Tab renderers ────────────────────────────────────────────────────────────

def _render_space_time(results: dict) -> None:
    """Space-time density heatmaps, one per corridor."""
    sim      = results['sim']
    all_roads = results['roads']
    road_keys = ['SB', 'NB', 'EB', 'WB'][:len(all_roads)]
    cmap     = _ite_cmap_full()

    if sim.get('mode', 'full') != 'full':
        st.info('Space-time diagrams require **full** simulation mode. '
                'Re-run with mode = full.')
        return

    for r, road in enumerate(all_roads):
        if 'rho' not in road:
            continue
        fig, ax = plt.subplots(figsize=(9, 4), facecolor='white')
        im = ax.imshow(
            road['rho'],
            aspect='auto', origin='lower',
            extent=[sim['t'][0] / 3600, sim['t'][-1] / 3600,
                    road['x_centers'][0], road['x_centers'][-1]],
            cmap=cmap,
        )
        cb = fig.colorbar(im, ax=ax)
        cb.set_label('Density [veh/ft]', fontsize=9)
        ax.set_xlabel('Time [hr]', fontsize=10)
        ax.set_ylabel('Position [ft]', fontsize=10)
        ax.set_title(f"Space-Time Density: {road['name']}", fontsize=11)
        fig.tight_layout()
        st.pyplot(fig, use_container_width=True)
        plt.close(fig)


def _render_od_matrix(results: dict) -> None:
    """OD vehicle-trip matrix heatmap."""
    demand = results['demand']
    taz    = results['TAZ']
    T_veh  = demand.get('T_vehicle')
    if T_veh is None:
        st.warning('No OD vehicle-trip matrix in results.')
        return

    zone_names = taz.get('names', [f'Zone {i}' for i in range(T_veh.shape[0])])
    Nz = len(zone_names)
    cmap = _ite_cmap_simple()

    fig, ax = plt.subplots(figsize=(7, 6), facecolor='white')
    im = ax.imshow(T_veh, cmap=cmap, aspect='auto')
    cb = fig.colorbar(im, ax=ax, location='bottom', pad=0.18)
    cb.set_label('Vehicles/Day', fontsize=9)
    ax.set_xticks(range(Nz)); ax.set_xticklabels(zone_names, rotation=30, ha='right', fontsize=8)
    ax.set_yticks(range(Nz)); ax.set_yticklabels(zone_names, fontsize=8)
    ax.set_xlabel('Destination Zone', fontsize=10)
    ax.set_ylabel('Origin Zone', fontsize=10)
    ax.set_title('OD Matrix: Vehicle Trips per Day (Gravity Model)', fontsize=11)
    for i in range(Nz):
        for j in range(Nz):
            ax.text(j, i, f"{T_veh[i, j]:.0f}",
                    ha='center', va='center', color='white', fontsize=8)
    fig.tight_layout()
    st.pyplot(fig, use_container_width=True)
    plt.close(fig)

    # Also show numeric table
    import pandas as pd
    df = pd.DataFrame(T_veh, index=zone_names, columns=zone_names)
    with st.expander('OD Matrix (numeric)', expanded=False):
        st.dataframe(df.style.format('{:.0f}'), use_container_width=True)


def _render_boundary_flow(results: dict) -> None:
    """Hourly OD model boundary flows vs MDOT truth data."""
    sim      = results['sim']
    demand   = results['demand']
    taz      = results['TAZ']
    all_roads = results['roads']
    road_keys = ['SB', 'NB', 'EB', 'WB'][:len(all_roads)]
    h_plot   = list(range(1, 25))

    dm = demand

    for r, road in enumerate(all_roads):
        truth = road.get('Truth')
        if truth is None:
            continue

        bnd_in_taz = road['boundary_idx'][0]
        intr_r = None
        # Try to get intersection info if boundary is an intersection (idx=0)
        if bnd_in_taz == 0:
            intr_r = next(
                (i for i in results.get('intersections', [])
                 if i['roadName'] == road['name']), None)

        if bnd_in_taz == 0 and intr_r is not None:
            od_in_hrly = np.zeros(24)
            for k in intr_r['taz_idx_external']:
                od_in_hrly += dm['V_taz_depart'][r, k - 1] * taz['f_depart'][:, k - 1]
        elif bnd_in_taz != 0:
            k0 = bnd_in_taz - 1
            od_in_hrly = dm['V_taz_depart'][r, k0] * taz['f_depart'][:, k0]
        else:
            od_in_hrly = np.zeros(24)

        bnd_out_taz = road['boundary_idx'][1]
        if bnd_out_taz == 0 and intr_r is not None:
            od_out_hrly = np.zeros(24)
            for k in intr_r['taz_idx_external']:
                od_out_hrly += dm['V_taz_arrive'][r, k - 1] * taz['f_arrive'][:, k - 1]
        elif bnd_out_taz != 0:
            k0 = bnd_out_taz - 1
            od_out_hrly = dm['V_taz_arrive'][r, k0] * taz['f_arrive'][:, k0]
        else:
            od_out_hrly = np.zeros(24)

        mdot_in  = truth['MDOT_inflow']  * 3600
        mdot_out = truth['MDOT_outflow'] * 3600

        fig, axes = plt.subplots(1, 3, figsize=(12, 3.5), facecolor='white')
        fig.suptitle(f"Boundary Flow vs MDOT — {road['name']}", fontsize=11)

        ax = axes[0]
        ax.bar(h_plot, mdot_in[:24], color=(0.2, 0.4, 0.8), alpha=0.5, label='MDOT Truth')
        ax.plot(h_plot, od_in_hrly, 'r-o', ms=4, label='OD Model')
        ax.set_title('Inflow'); ax.set_ylabel('Flow [veh/hr]'); ax.set_xlabel('Hour')
        ax.legend(fontsize=8); ax.grid(True); ax.set_xlim(0.5, 24.5)

        ax = axes[1]
        ax.bar(h_plot, mdot_out[:24], color=(0.2, 0.7, 0.3), alpha=0.5, label='MDOT Truth')
        ax.plot(h_plot, od_out_hrly, 'r-o', ms=4, label='OD Model')
        ax.set_title('Outflow'); ax.set_xlabel('Hour')
        ax.legend(fontsize=8); ax.grid(True); ax.set_xlim(0.5, 24.5)

        ax = axes[2]
        x_c = np.array([0, 1]); w = 0.35
        ax.bar(x_c - w/2, [mdot_in.sum(), mdot_out.sum()], w,
               label='MDOT Truth', color=(0.2, 0.4, 0.8))
        ax.bar(x_c + w/2, [od_in_hrly.sum(), od_out_hrly.sum()], w,
               label='OD Model',   color=(0.9, 0.3, 0.3))
        ax.set_xticks(x_c); ax.set_xticklabels(['Inflow', 'Outflow'])
        ax.set_ylabel('Vehicles [veh/day]'); ax.set_title('Daily Volume')
        ax.legend(fontsize=8); ax.grid(True)

        fig.tight_layout()
        st.pyplot(fig, use_container_width=True)
        plt.close(fig)

        # Error metrics
        in_err  = (od_in_hrly.sum() - mdot_in.sum())  / max(mdot_in.sum(),  1) * 100
        out_err = (od_out_hrly.sum() - mdot_out.sum()) / max(mdot_out.sum(), 1) * 100
        col1, col2 = st.columns(2)
        col1.metric(f'{road_keys[r]} Inflow error (daily)',  f'{in_err:+.1f}%')
        col2.metric(f'{road_keys[r]} Outflow error (daily)', f'{out_err:+.1f}%')


def _render_scenario_comparison(
    multi_results: dict,
    sim: dict,
    road_keys: list,
) -> None:
    """Render scenario comparison plots from multiple results dicts."""
    if len(multi_results) < 2:
        st.info('Run at least two different scenarios then use the '
                '"Add to comparison" button to compare them here.')
        return

    from corridor_sim.engine.plot_scenario_comparison import (
        plot_scenario_comparison, print_scenario_comparison_table,
    )

    plotfmt = {'sz_tall': (14, 6.5), 'sz_half': (10, 4),
               'sgtitle_fs': 13, 'title_fs': 11, 'label_fs': 10,
               'legend_fs': 9, 'lw': 2}

    figs = plot_scenario_comparison(multi_results, sim, road_keys, plotfmt)
    captions = [
        'Figure 1 — Hourly Boundary Flows per Corridor',
        'Figure 2 — Daily Boundary Volume Summary',
        'Figure 3 — Space-Time Density at Peak Hour',
    ]
    for fig, cap in zip(figs, captions):
        st.caption(cap)
        st.pyplot(fig, use_container_width=True)
        plt.close(fig)


# ─── Main page renderer ───────────────────────────────────────────────────────

def render(results: dict | None, multi_results: dict | None = None) -> None:
    """
    Render the Results page.

    Parameters
    ----------
    results       : dict | None  Latest simulation results (or None if not run yet).
    multi_results : dict | None  {scenario_name: results} for comparison tab.
    """
    st.header('📊 Simulation Results')

    if results is None:
        st.info('No results yet — configure a scenario in the sidebar and click **▶ Run Simulation**.')
        return

    road_keys = ['SB', 'NB', 'EB', 'WB'][:len(results.get('roads', []))]
    sim       = results['sim']

    tab_labels = ['Space-Time', 'OD Matrix', 'Boundary Flow', 'Scenario Compare']
    tabs       = st.tabs(tab_labels)

    with tabs[0]:
        _render_space_time(results)

    with tabs[1]:
        _render_od_matrix(results)

    with tabs[2]:
        _render_boundary_flow(results)

    with tabs[3]:
        _render_scenario_comparison(
            multi_results if multi_results else {},
            sim,
            road_keys,
        )
