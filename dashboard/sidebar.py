"""
sidebar.py
==========
Streamlit sidebar component for the corridor simulation dashboard.

Renders:
  - Project selector (scans projects/ directory)
  - Simulation mode radio button
  - Scenario selector with description tooltip
  - Optional parameter override expanders (Signal, Land-Use, Mode-Split,
    QuickTune) that write back to session_state without touching xlsx files

The sidebar never calls the engine — it only sets ``st.session_state`` keys
that the main app reads before calling ``run_engine``.

Session-state keys written
--------------------------
project_name : str   Selected project folder name (e.g. 'UM_Dearborn')
project_path : str   Full relative path  (e.g. 'projects/UM_Dearborn')
sim_mode     : str   'full' | 'demand_only'
scenario     : str   Scenario name or 'Baseline'
overrides    : dict  {type: {field: value}} — in-memory overrides (not saved)
"""

from __future__ import annotations
from pathlib import Path

import pandas as pd
import streamlit as st

from dashboard.engine_runner import list_projects, list_scenarios


def _load_scenario_descriptions(project_path: str) -> dict[str, str]:
    """Return {ScenarioName: Description} from scenario_config.xlsx."""
    xf = Path(project_path) / 'scenario_config.xlsx'
    if not xf.exists():
        return {}
    try:
        df = pd.read_excel(xf, sheet_name='ScenarioList', header=0)
        return dict(zip(df['ScenarioName'], df['Description'].fillna('')))
    except Exception:
        return {}


def _load_road_names(project_path: str) -> list[str]:
    """Return corridor names from corridor_config.xlsx."""
    xf = Path(project_path) / 'corridor_config.xlsx'
    if not xf.exists():
        return []
    try:
        df = pd.read_excel(xf, sheet_name='Corridors', header=0)
        return df['Name'].tolist()
    except Exception:
        return []


def _load_zone_names(project_path: str) -> list[str]:
    """Return zone names from taz_config.xlsx."""
    xf = Path(project_path) / 'taz_config.xlsx'
    if not xf.exists():
        return []
    try:
        df = pd.read_excel(xf, sheet_name='Zones', header=0)
        return df['ZoneName'].tolist()
    except Exception:
        return []


def _load_quicktune_keys(project_path: str) -> list[str]:
    """Return QuickTune keys from taz_config.xlsx."""
    xf = Path(project_path) / 'taz_config.xlsx'
    if not xf.exists():
        return []
    try:
        df = pd.read_excel(xf, sheet_name='QuickTune', header=0)
        return df['Key'].tolist()
    except Exception:
        return []


# ─── Main sidebar renderer ────────────────────────────────────────────────────

def render_sidebar() -> None:
    """
    Render the full sidebar and update ``st.session_state``.

    Called once per Streamlit rerun from ``app.py``.
    """
    st.sidebar.title('🚦 Corridor Sim')
    st.sidebar.caption('ITE Macroscopic Traffic Simulation Platform')
    st.sidebar.markdown('---')

    # ── Project selection ─────────────────────────────────────────────────────
    projects = list_projects()
    if not projects:
        st.sidebar.error('No projects found under `projects/`. '
                         'Create a project folder with corridor_config.xlsx.')
        return

    prev_proj = st.session_state.get('project_name', projects[0])
    proj_idx  = projects.index(prev_proj) if prev_proj in projects else 0
    project_name = st.sidebar.selectbox(
        'Project', projects, index=proj_idx,
        help='Folder name under projects/')
    project_path = f'projects/{project_name}'

    if project_name != st.session_state.get('project_name'):
        # Reset scenario selection when project changes
        st.session_state['scenario'] = 'Baseline'

    st.session_state['project_name'] = project_name
    st.session_state['project_path'] = project_path

    # ── Simulation mode ───────────────────────────────────────────────────────
    mode = st.sidebar.radio(
        'Simulation mode',
        ['full', 'demand_only'],
        index=0 if st.session_state.get('sim_mode', 'full') == 'full' else 1,
        help=('**full** — run the LWR solver (≈30 s for UM-Dearborn).\n\n'
              '**demand_only** — skip the solver; fast calibration of demand '
              'boundary flows (< 1 s).'),
    )
    st.session_state['sim_mode'] = mode

    # ── Scenario selection ────────────────────────────────────────────────────
    scenarios    = list_scenarios(project_path)
    descriptions = _load_scenario_descriptions(project_path)

    prev_scen  = st.session_state.get('scenario', 'Baseline')
    scen_idx   = scenarios.index(prev_scen) if prev_scen in scenarios else 0
    scenario   = st.sidebar.selectbox('Scenario', scenarios, index=scen_idx)
    desc       = descriptions.get(scenario, '')
    if desc:
        st.sidebar.caption(f'ℹ️ {desc}')

    st.session_state['scenario'] = scenario

    st.sidebar.markdown('---')

    # ── Override forms (collapsible) ──────────────────────────────────────────
    overrides: dict = st.session_state.get('overrides', {})

    road_names = _load_road_names(project_path)
    zone_names = _load_zone_names(project_path)
    qt_keys    = _load_quicktune_keys(project_path)

    # Signal Overrides
    with st.sidebar.expander('Signal Overrides', expanded=False):
        st.caption('Override signal timing for one corridor. Leave blank to use config values.')
        sig_road = st.selectbox('Road', ['(none)'] + road_names, key='sig_road_sel')
        if sig_road != '(none)':
            sig_green = st.number_input('Green [s]', min_value=1, max_value=300,
                                        value=int(overrides.get('signal', {})
                                                  .get(sig_road, {}).get('green', 60)),
                                        key='sig_green')
            sig_red   = st.number_input('Red [s]', min_value=1, max_value=300,
                                        value=int(overrides.get('signal', {})
                                                  .get(sig_road, {}).get('red', 60)),
                                        key='sig_red')
            sig_qsat  = st.number_input('Qsat per lane [veh/s]', min_value=0.01,
                                        max_value=1.0, step=0.01,
                                        value=float(overrides.get('signal', {})
                                                    .get(sig_road, {}).get('qsat', 0.5)),
                                        key='sig_qsat')
            overrides.setdefault('signal', {})[sig_road] = {
                'green': sig_green, 'red': sig_red, 'qsat': sig_qsat,
            }

    # Land-Use Overrides
    with st.sidebar.expander('Land-Use Overrides', expanded=False):
        st.caption('Override attraction parameters for one zone.')
        lu_zone = st.selectbox('Zone', ['(none)'] + zone_names, key='lu_zone_sel')
        if lu_zone != '(none)':
            lu_emp    = st.number_input('Employment', min_value=0, step=100,
                                        value=int(overrides.get('land_use', {})
                                                  .get(lu_zone, {}).get('employment', 0)),
                                        key='lu_emp')
            lu_enroll = st.number_input('Enrollment', min_value=0, step=100,
                                        value=int(overrides.get('land_use', {})
                                                  .get(lu_zone, {}).get('enrollment', 0)),
                                        key='lu_enroll')
            lu_retail = st.number_input('Retail area [sqft]', min_value=0, step=1000,
                                        value=int(overrides.get('land_use', {})
                                                  .get(lu_zone, {}).get('retail', 0)),
                                        key='lu_retail')
            overrides.setdefault('land_use', {})[lu_zone] = {
                'employment': lu_emp, 'enrollment': lu_enroll, 'retail': lu_retail,
            }

    # Mode-Split Overrides
    with st.sidebar.expander('Mode-Split Overrides', expanded=False):
        st.caption('Override auto share for one zone (0–1).')
        ms_zone = st.selectbox('Zone', ['(none)'] + zone_names, key='ms_zone_sel')
        if ms_zone != '(none)':
            ms_auto = st.slider(
                'Auto share', 0.0, 1.0,
                value=float(overrides.get('mode_split', {})
                            .get(ms_zone, {}).get('auto_share', 0.8)),
                step=0.01, key='ms_auto',
            )
            overrides.setdefault('mode_split', {})[ms_zone] = {'auto_share': ms_auto}

    # QuickTune Overrides
    with st.sidebar.expander('QuickTune Overrides', expanded=False):
        st.caption('Scale boundary flow for calibration. 1.0 = no change.')
        for qk in qt_keys:
            default = float(overrides.get('quicktune', {}).get(qk, 1.0))
            val = st.number_input(qk, min_value=0.01, max_value=5.0,
                                  value=default, step=0.05, key=f'qt_{qk}')
            overrides.setdefault('quicktune', {})[qk] = val

    st.session_state['overrides'] = overrides

    st.sidebar.markdown('---')
    st.sidebar.caption('v0.7 · UM-Dearborn ITE Sandbox')
