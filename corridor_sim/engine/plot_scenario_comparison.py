"""
plot_scenario_comparison.py
===========================
Scenario comparison visualisation.

Overlays boundary flow time series, daily volume bars, and peak-hour density
summaries for two or more named scenario result sets.

Usage
-----
    from corridor_sim.engine.plot_scenario_comparison import plot_scenario_comparison

    results = {
        'Baseline':        {'roads': all_roads_base,   'demand': demand_base},
        'SignalRetiming_A':{'roads': all_roads_sig,    'demand': demand_sig},
        'LandUse_Campus+': {'roads': all_roads_lu,    'demand': demand_lu},
    }
    figs = plot_scenario_comparison(results, sim, road_keys, plotfmt)
"""

from __future__ import annotations
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

# Palette: one colour per scenario (up to 8)
_PALETTE = [
    (0.20, 0.40, 0.80),   # blue
    (0.85, 0.25, 0.25),   # red
    (0.20, 0.65, 0.35),   # green
    (0.80, 0.55, 0.10),   # amber
    (0.55, 0.20, 0.75),   # purple
    (0.10, 0.65, 0.75),   # teal
    (0.90, 0.45, 0.10),   # orange
    (0.45, 0.45, 0.45),   # grey
]


def plot_scenario_comparison(
    results: dict,
    sim: dict,
    road_keys: list,
    plotfmt: dict,
) -> list:
    """
    Produce scenario comparison figures.

    Figure 1 — Hourly boundary flows per road:
        For each road: inflow and outflow time series, one line per scenario.

    Figure 2 — Daily volume summary:
        Grouped bar chart: roads × [inflow, outflow], one bar group per scenario.

    Figure 3 — Peak-hour density heatmap comparison:
        Space-time density at peak hour for each scenario side-by-side.

    Parameters
    ----------
    results   : dict  {scenario_name: {'roads': list[road_dict], 'demand': demand_dict}}
    sim       : dict  Simulation settings (dt, Nt, t).
    road_keys : list  Short road labels ['SB','NB','EB','WB'].
    plotfmt   : dict  Plot formatting settings.

    Returns
    -------
    figs : list[matplotlib.Figure]
    """
    scenario_names = list(results.keys())
    Nscenarios = len(scenario_names)
    Nroads     = len(road_keys)
    pts_per_hr = round(3600 / sim['dt'])
    Nhrs       = (sim['Nt'] - 1) // pts_per_hr
    hrs        = np.arange(1, Nhrs + 1)
    figs       = []

    # ── Figure 1: hourly boundary flows ──────────────────────────────────────
    fig1, axes = plt.subplots(Nroads, 2, facecolor='white',
                               figsize=plotfmt.get('sz_tall', (14, 6.5)))
    fig1.suptitle('Scenario Comparison: Hourly Boundary Flows',
                  fontsize=plotfmt.get('sgtitle_fs', 14), fontweight='bold')

    for r, rkey in enumerate(road_keys):
        for s_idx, s_name in enumerate(scenario_names):
            road = results[s_name]['roads'][r]
            Npts = Nhrs * pts_per_hr
            F_in  = road['F'][0,           :Npts].reshape(pts_per_hr, Nhrs, order='F').sum(axis=0) * sim['dt']
            F_out = road['F'][road['Nx'],   :Npts].reshape(pts_per_hr, Nhrs, order='F').sum(axis=0) * sim['dt']
            color = _PALETTE[s_idx % len(_PALETTE)]

            axes[r, 0].plot(hrs, F_in,  color=color, lw=plotfmt.get('lw', 2),
                            label=s_name)
            axes[r, 1].plot(hrs, F_out, color=color, lw=plotfmt.get('lw', 2),
                            label=s_name)

        axes[r, 0].set_ylabel(f'{rkey}\nFlow [veh/hr]')
        axes[r, 0].grid(True); axes[r, 0].set_xlim(1, 24)
        axes[r, 1].grid(True); axes[r, 1].set_xlim(1, 24)
        if r == 0:
            axes[r, 0].set_title('Upstream Inflow')
            axes[r, 1].set_title('Downstream Outflow')
            axes[r, 0].legend(fontsize=plotfmt.get('legend_fs', 9),
                              loc='upper left', framealpha=0.7)
        if r == Nroads - 1:
            axes[r, 0].set_xlabel('Hour of Day')
            axes[r, 1].set_xlabel('Hour of Day')

    fig1.tight_layout()
    figs.append(fig1)

    # ── Figure 2: daily volume summary bar chart ──────────────────────────────
    x_pos  = np.arange(Nroads)
    width  = 0.8 / Nscenarios
    fig2, axes2 = plt.subplots(1, 2, facecolor='white',
                                figsize=plotfmt.get('sz_half', (10, 4)))
    fig2.suptitle('Scenario Comparison: Daily Boundary Volumes',
                  fontsize=plotfmt.get('sgtitle_fs', 14), fontweight='bold')

    for s_idx, s_name in enumerate(scenario_names):
        Npts   = Nhrs * pts_per_hr
        color  = _PALETTE[s_idx % len(_PALETTE)]
        offset = (s_idx - (Nscenarios - 1) / 2) * width

        daily_in  = np.array([
            results[s_name]['roads'][r]['F'][0,                            :Npts].sum() * sim['dt']
            for r in range(Nroads)
        ])
        daily_out = np.array([
            results[s_name]['roads'][r]['F'][results[s_name]['roads'][r]['Nx'], :Npts].sum() * sim['dt']
            for r in range(Nroads)
        ])

        axes2[0].bar(x_pos + offset, daily_in,  width, color=color,
                     label=s_name, alpha=0.85)
        axes2[1].bar(x_pos + offset, daily_out, width, color=color,
                     label=s_name, alpha=0.85)

    for ax, title in zip(axes2, ['Upstream Inflow: Daily Total',
                                  'Downstream Outflow: Daily Total']):
        ax.set_xticks(x_pos)
        ax.set_xticklabels(road_keys)
        ax.set_ylabel('Vehicles [veh/day]')
        ax.set_title(title)
        ax.legend(fontsize=plotfmt.get('legend_fs', 9))
        ax.grid(True, axis='y')

    fig2.tight_layout()
    figs.append(fig2)

    # ── Figure 3: peak-hour density comparison ────────────────────────────────
    # Find global peak hour (hour with highest average density across all scenarios)
    def _peak_hour_density(roads):
        avg_density = np.zeros(Nhrs)
        for r_road in roads:
            for h in range(Nhrs):
                start = h * pts_per_hr
                end   = start + pts_per_hr
                avg_density[h] += r_road['rho'][:, start:end].mean()
        return int(np.argmax(avg_density))

    # Use first scenario's roads to determine peak hour
    ph = _peak_hour_density(list(results.values())[0]['roads'])
    ph_start = ph * pts_per_hr
    ph_end   = ph_start + pts_per_hr

    fig3, axes3 = plt.subplots(Nroads, Nscenarios, facecolor='white',
                                figsize=(4 * Nscenarios, 3 * Nroads))
    fig3.suptitle(f'Scenario Comparison: Space-Time Density — Peak Hour {ph+1}',
                  fontsize=plotfmt.get('sgtitle_fs', 14), fontweight='bold')

    for r, rkey in enumerate(road_keys):
        global_vmax = max(
            results[s]['roads'][r]['rho'][:, ph_start:ph_end].max()
            for s in scenario_names
        ) or 1e-6

        for s_idx, s_name in enumerate(scenario_names):
            ax = axes3[r, s_idx] if Nscenarios > 1 else axes3[r]
            road = results[s_name]['roads'][r]
            t_slice  = sim['t'][ph_start:ph_end] / 60   # minutes
            rho_slice = road['rho'][:, ph_start:ph_end]

            im = ax.imshow(
                rho_slice,
                aspect='auto', origin='lower',
                extent=[t_slice[0], t_slice[-1],
                        road['x_centers'][0], road['x_centers'][-1]],
                vmin=0, vmax=global_vmax,
                cmap='YlOrRd',
            )
            if r == 0:
                ax.set_title(s_name, fontsize=plotfmt.get('title_fs', 11))
            if s_idx == 0:
                ax.set_ylabel(f'{rkey}\nPosition [ft]',
                              fontsize=plotfmt.get('label_fs', 10))
            else:
                ax.set_yticklabels([])
            if r == Nroads - 1:
                ax.set_xlabel('Time [min]', fontsize=plotfmt.get('label_fs', 10))

    fig3.tight_layout()
    figs.append(fig3)

    return figs


def print_scenario_comparison_table(results: dict, sim: dict, road_keys: list):
    """
    Print a console table comparing daily volumes across scenarios.

    Parameters
    ----------
    results   : dict  {scenario_name: {'roads': list[road_dict]}}
    sim       : dict
    road_keys : list
    """
    pts_per_hr = round(3600 / sim['dt'])
    Nhrs       = (sim['Nt'] - 1) // pts_per_hr
    Npts       = Nhrs * pts_per_hr
    scenario_names = list(results.keys())

    col_w = 14
    header = f"{'Road':<6}" + ''.join(
        f"{'In: ' + s[:9]:>{col_w}} {'Out: ' + s[:9]:>{col_w}}"
        for s in scenario_names
    )
    print('\n========== Scenario Comparison: Daily Volumes [veh/day] ==========')
    print(header)
    print('-' * len(header))
    for r, rkey in enumerate(road_keys):
        row = f"{rkey:<6}"
        for s_name in scenario_names:
            road = results[s_name]['roads'][r]
            d_in  = road['F'][0,          :Npts].sum() * sim['dt']
            d_out = road['F'][road['Nx'], :Npts].sum() * sim['dt']
            row += f"{d_in:>{col_w}.0f} {d_out:>{col_w}.0f}"
        print(row)
    print()
