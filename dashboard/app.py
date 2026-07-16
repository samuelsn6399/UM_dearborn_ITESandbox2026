"""
app.py
======
Streamlit entry point for the Corridor Traffic Simulation dashboard.

Run with:
    streamlit run dashboard/app.py

Layout
------
Left sidebar  — project/scenario selector, parameter override forms (sidebar.py)
Main area     — two top-level pages driven by st.session_state['page']:
                  • Project Setup  (project_setup.py)
                  • Results        (results.py)

A "▶ Run Simulation" button triggers the engine runner in-process, streaming
stdout progress into an expandable log panel and storing results in
st.session_state so the Results page can render without re-running.

Session-state keys used (in addition to those written by sidebar.py)
--------------------------------------------------------------------
page          : str   'setup' | 'results'
results       : dict  Last completed simulation output (or None)
multi_results : dict  {scenario_name: results} for comparison tab
log_lines     : list  Captured stdout lines from last run
run_complete  : bool  True after a successful run
"""

from __future__ import annotations
from pathlib import Path

import streamlit as st

# ─── Page configuration (must be first Streamlit call) ────────────────────────
st.set_page_config(
    page_title='Corridor Sim — ITE Platform',
    page_icon='🚦',
    layout='wide',
    initial_sidebar_state='expanded',
)

from dashboard.sidebar        import render_sidebar
from dashboard.pages          import project_setup, results as results_page
from dashboard.engine_runner  import run_engine


# ─── Session-state defaults ───────────────────────────────────────────────────

def _init_state():
    defaults = {
        'page':          'setup',
        'results':       None,
        'multi_results': {},
        'log_lines':     [],
        'run_complete':  False,
        'overrides':     {},
        'sim_mode':      'full',
        'scenario':      'Baseline',
    }
    for key, val in defaults.items():
        if key not in st.session_state:
            st.session_state[key] = val


# ─── Top nav bar ──────────────────────────────────────────────────────────────

def _render_topbar():
    col_logo, col_nav, col_run = st.columns([3, 4, 2])

    with col_logo:
        st.markdown(
            '### 🚦 Corridor Simulation Platform',
            help='ITE Macroscopic Traffic Simulation — UM-Dearborn ITE Sandbox'
        )

    with col_nav:
        c1, c2 = st.columns(2)
        if c1.button('📋 Project Setup',
                     type='secondary' if st.session_state['page'] == 'results' else 'primary',
                     use_container_width=True):
            st.session_state['page'] = 'setup'
            st.rerun()
        if c2.button('📊 Results',
                     type='secondary' if st.session_state['page'] == 'setup' else 'primary',
                     use_container_width=True,
                     disabled=st.session_state['results'] is None):
            st.session_state['page'] = 'results'
            st.rerun()

    with col_run:
        run_clicked = st.button(
            '▶ Run Simulation',
            type='primary',
            use_container_width=True,
            help='Run the simulation engine with the current project + scenario settings.',
        )
    return run_clicked


# ─── Run controller ───────────────────────────────────────────────────────────

def _run_simulation():
    """Execute the engine and stream progress into a log expander."""
    project_path = st.session_state.get('project_path', 'projects/UM_Dearborn')
    sim_mode     = st.session_state.get('sim_mode', 'full')
    scenario     = st.session_state.get('scenario', 'Baseline')

    st.session_state['log_lines']    = []
    st.session_state['run_complete'] = False

    log_expander = st.expander('▼ Simulation Log', expanded=True)
    log_area     = log_expander.empty()

    progress_bar = st.progress(0, text='Initialising…')
    _progress_steps = {
        'Done setting up simulation':   5,
        'Done configuring road geometry': 10,
        'Done configuring TAZs':         15,
        'Done loading 4-step model':     25,
        'Done applying Quick Tune':      30,
        'Done loading MDOT data':        35,
        'BEGIN SIMULATION':              40,
        'Sim Hour:  1':                  42,
        'Sim Hour:  2':                  44,
        'Sim Hour:  4':                  48,
        'Sim Hour:  6':                  52,
        'Sim Hour:  8':                  56,
        'Sim Hour: 10':                  60,
        'Sim Hour: 12':                  64,
        'Sim Hour: 14':                  68,
        'Sim Hour: 16':                  72,
        'Sim Hour: 18':                  76,
        'Sim Hour: 20':                  80,
        'Sim Hour: 22':                  84,
        'Sim Hour: 24':                  88,
        'Simulation complete':           92,
        'All plots complete':            98,
    }

    lines  = []
    result = None

    try:
        for item in run_engine(project=project_path, mode=sim_mode,
                               scenario=scenario if scenario != 'Baseline' else None):
            if isinstance(item, dict):
                result = item
                continue
            lines.append(item)
            st.session_state['log_lines'] = lines.copy()
            log_area.code('\n'.join(lines[-40:]), language=None)

            # Update progress bar heuristically
            for key, pct in _progress_steps.items():
                if key in item:
                    progress_bar.progress(pct, text=item[:80])
                    break

        progress_bar.progress(100, text='Complete ✓')

    except Exception as exc:
        progress_bar.progress(0, text=f'Error: {exc}')
        st.error(f'Simulation failed: {exc}')
        return

    if result is not None:
        st.session_state['results']       = result
        st.session_state['run_complete']  = True
        # Store in multi_results for comparison tab
        scen_key = st.session_state.get('scenario', 'Baseline')
        st.session_state['multi_results'][scen_key] = {
            'roads':  result['roads'],
            'demand': result['demand'],
        }
        # Auto-navigate to results
        st.session_state['page'] = 'results'
        st.rerun()
    else:
        st.error('Simulation produced no results. Check the log above.')


# ─── App entry point ──────────────────────────────────────────────────────────

def main():
    _init_state()
    render_sidebar()
    run_clicked = _render_topbar()
    st.markdown('---')

    if run_clicked:
        _run_simulation()
        return   # rerun handles navigation

    page = st.session_state.get('page', 'setup')

    if page == 'setup':
        project_path = st.session_state.get('project_path', 'projects/UM_Dearborn')
        project_setup.render(project_path)

    elif page == 'results':
        results_page.render(
            results=st.session_state.get('results'),
            multi_results=st.session_state.get('multi_results'),
        )


if __name__ == '__main__':
    main()
