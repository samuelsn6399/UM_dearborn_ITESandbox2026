"""
demo_script.py
==============
One-click pitch demo for the UM-Dearborn reference project.

Runs three scenarios back-to-back (Baseline, SignalRetiming_A,
LandUseCampus+), exports all figures to the figures/ directory, and
prints a scenario comparison table to the console.

Usage
-----
    python projects/UM_Dearborn/demo_script.py

Output
------
    figures/demandBoundary_*.png   (4 roads × 3 scenarios)
    figures/spaceTime_*.png        (4 roads × 3 scenarios)
    figures/odMatrix_*.png         (3 scenarios)
    figures/roadGeometry_*.png     (4 roads)
    Console: scenario comparison table

Runtime: ~90 s total (three full LWR runs).
"""

import sys
import os
import time

# Add repo root to path so run_simulation and corridor_sim are importable
_repo_root = os.path.join(os.path.dirname(__file__), '..', '..')
sys.path.insert(0, os.path.abspath(_repo_root))

import matplotlib
matplotlib.use('Agg')   # non-interactive; saves to PNG only

import run_simulation  # type: ignore
from corridor_sim.engine.plot_scenario_comparison import (
    plot_scenario_comparison, print_scenario_comparison_table,
)
import matplotlib.pyplot as plt

PROJECT = 'projects/UM_Dearborn'
SCENARIOS = ['Baseline', 'SignalRetiming_A', 'LandUseCampus+']
FIGURES_DIR = 'figures'


def _run_scenario(scenario_name: str) -> dict:
    """Run one full scenario and return results dict."""
    print(f'\n{"=" * 60}')
    print(f'  Running scenario: {scenario_name}')
    print('=' * 60)
    scen_arg = None if scenario_name == 'Baseline' else scenario_name

    # Monkey-patch plotfmt.export = True so all figures are saved
    _orig_main = run_simulation.main

    def _patched_main(project, mode, scenario):
        import run_simulation as rs_mod
        result = _orig_main(project=project, mode=mode, scenario=scenario)
        return result

    t0 = time.time()
    result = run_simulation.main(
        project=PROJECT,
        mode='full',
        scenario=scen_arg,
    )
    print(f'  Wall time: {time.time() - t0:.1f} s')
    return result


def main():
    os.makedirs(FIGURES_DIR, exist_ok=True)

    print('\n🚦  Corridor Simulation Platform — UM-Dearborn Demo')
    print('    Produces all pitch figures automatically.\n')

    all_results = {}

    for scen in SCENARIOS:
        all_results[scen] = _run_scenario(scen)

    # ── Scenario comparison ───────────────────────────────────────────────────
    print(f'\n{"=" * 60}')
    print('  Generating scenario comparison figures …')
    print('=' * 60)

    # Build the multi-results dict expected by plot_scenario_comparison
    sim = list(all_results.values())[0]['sim']
    road_keys = ['SB', 'NB', 'EB', 'WB']
    comparison = {
        scen: {
            'roads':  all_results[scen]['roads'],
            'demand': all_results[scen]['demand'],
        }
        for scen in SCENARIOS
    }

    plotfmt = {
        'sz_tall':    (14, 6.5),
        'sz_half':    (10, 4.0),
        'sgtitle_fs': 13,
        'title_fs':   11,
        'label_fs':   10,
        'legend_fs':   9,
        'lw':          2,
    }
    figs = plot_scenario_comparison(comparison, sim, road_keys, plotfmt)

    fig_names = [
        'scenario_comparison_boundary_flows',
        'scenario_comparison_daily_volumes',
        'scenario_comparison_peak_density',
    ]
    for fig, name in zip(figs, fig_names):
        out_path = os.path.join(FIGURES_DIR, f'{name}.png')
        fig.savefig(out_path, dpi=200, bbox_inches='tight', facecolor='white')
        print(f'  Saved: {out_path}')
        plt.close(fig)

    # ── Console table ─────────────────────────────────────────────────────────
    print_scenario_comparison_table(comparison, sim, road_keys)

    print('\n✅  Demo complete.')
    print(f'   All figures saved to: {os.path.abspath(FIGURES_DIR)}/')
    print('\n   To launch the interactive dashboard:')
    print('   streamlit run dashboard/app.py')


if __name__ == '__main__':
    main()
