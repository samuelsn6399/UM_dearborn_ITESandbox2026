"""
project_setup.py
================
Dashboard page — Project Setup.

Displays a schematic of the road network geometry and TAZ locations loaded
from the project's corridor_config.xlsx and taz_config.xlsx files.

No simulation results are required — this page renders from config data only.
"""

from __future__ import annotations
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import streamlit as st


def _load_corridor_summary(project_path: str) -> pd.DataFrame | None:
    xf = Path(project_path) / 'corridor_config.xlsx'
    if not xf.exists():
        return None
    try:
        df = pd.read_excel(xf, sheet_name='Corridors', header=0)
        return df
    except Exception as exc:
        st.error(f'Could not read corridor_config.xlsx: {exc}')
        return None


def _load_taz_summary(project_path: str) -> pd.DataFrame | None:
    xf = Path(project_path) / 'taz_config.xlsx'
    if not xf.exists():
        return None
    try:
        df = pd.read_excel(xf, sheet_name='Zones', header=0)
        return df
    except Exception as exc:
        st.error(f'Could not read taz_config.xlsx: {exc}')
        return None


def _load_access_points(project_path: str) -> pd.DataFrame | None:
    xf = Path(project_path) / 'taz_config.xlsx'
    if not xf.exists():
        return None
    try:
        df = pd.read_excel(xf, sheet_name='AccessPoints', header=0)
        return df
    except Exception as exc:
        return None


def _build_network_schematic(
    corridors: pd.DataFrame,
    zones: pd.DataFrame,
    access_points: pd.DataFrame | None,
) -> plt.Figure:
    """
    Draw a 2-D schematic of corridors (lines) and TAZ centroids (circles).

    Corridors are plotted as horizontal/vertical line segments using their
    x/y start and end coordinates from the Corridors sheet.
    TAZ centroids are plotted as labelled dots.
    """
    fig, ax = plt.subplots(figsize=(9, 7))
    fig.patch.set_facecolor('white')
    ax.set_facecolor('#f7f8fa')

    dir_colors = {
        'Southbound': '#3b6fd4',
        'Northbound': '#2eaa5c',
        'Eastbound':  '#c0392b',
        'Westbound':  '#8e44ad',
    }
    legend_handles = []

    # ── Corridors ─────────────────────────────────────────────────────────────
    col_map = {c.lower(): c for c in corridors.columns}

    def _col(preferred, fallback=None):
        """Return actual column name case-insensitively."""
        for p in ([preferred] + ([fallback] if fallback else [])):
            if p and p.lower() in col_map:
                return col_map[p.lower()]
        return None

    x_start_col = _col('XStart_ft', 'xStart_ft')
    y_start_col = _col('YStart_ft', 'yStart_ft')
    x_end_col   = _col('XEnd_ft',   'xEnd_ft')
    y_end_col   = _col('YEnd_ft',   'yEnd_ft')
    name_col    = _col('Name')
    dir_col     = _col('Direction')

    has_coords = all(c is not None for c in
                     [x_start_col, y_start_col, x_end_col, y_end_col])

    for _, row in corridors.iterrows():
        rname = str(row[name_col]) if name_col else 'Road'
        direction = str(row[dir_col]) if dir_col else ''
        color = dir_colors.get(direction, '#555555')

        if has_coords:
            xs = float(row[x_start_col])
            ys = float(row[y_start_col])
            xe = float(row[x_end_col])
            ye = float(row[y_end_col])
        else:
            # Fallback: stack corridors vertically as symbolic lines
            idx = corridors.index.get_loc(row.name)
            xs, ys, xe, ye = 0, idx * 3000, 10000, idx * 3000

        ax.annotate('', xy=(xe, ye), xytext=(xs, ys),
                    arrowprops=dict(arrowstyle='->', color=color, lw=2.5))
        mx, my = (xs + xe) / 2, (ys + ye) / 2
        ax.text(mx, my + 200, rname, ha='center', fontsize=8,
                color=color, fontweight='bold')
        legend_handles.append(
            mpatches.Patch(facecolor=color, label=rname))

    # ── TAZ centroids ─────────────────────────────────────────────────────────
    col_map_z = {c.lower(): c for c in zones.columns}

    def _zcol(name):
        return col_map_z.get(name.lower())

    zname_col = _zcol('ZoneName')
    zx_col    = _zcol('XLocation_ft') or _zcol('xLocation_ft') or _zcol('xlocation_ft')
    zy_col    = _zcol('YLocation_ft') or _zcol('yLocation_ft') or _zcol('ylocation_ft')

    if zx_col and zy_col:
        for _, row in zones.iterrows():
            zx = float(row[zx_col])
            zy = float(row[zy_col])
            zn = str(row[zname_col]) if zname_col else ''
            ax.plot(zx, zy, 'o', color='#e67e22', markersize=9, zorder=5)
            ax.text(zx + 150, zy + 150, zn, fontsize=7, color='#333333')

        legend_handles.append(
            plt.Line2D([0], [0], marker='o', color='w',
                       markerfacecolor='#e67e22', markersize=9,
                       label='TAZ Centroid'))

    # ── Access points ─────────────────────────────────────────────────────────
    if access_points is not None and has_coords:
        # We can't directly map xLocal → 2-D without corridor geometry;
        # just note them as a legend entry
        legend_handles.append(
            mpatches.Patch(facecolor='#27ae60', alpha=0.4,
                           label='Access Points (see geometry tab)'))

    ax.set_xlabel('X Coordinate [ft]', fontsize=10)
    ax.set_ylabel('Y Coordinate [ft]', fontsize=10)
    ax.set_title('Corridor Network Schematic', fontsize=13, fontweight='bold')
    ax.legend(handles=legend_handles, loc='lower right',
              fontsize=8, framealpha=0.9)
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    return fig


# ─── Page renderer ────────────────────────────────────────────────────────────

def render(project_path: str) -> None:
    """
    Render the Project Setup page.

    Parameters
    ----------
    project_path : str  e.g. 'projects/UM_Dearborn'
    """
    st.header('📋 Project Setup')

    corridors = _load_corridor_summary(project_path)
    zones     = _load_taz_summary(project_path)

    if corridors is None or zones is None:
        st.warning('Project config files not found or could not be parsed.')
        return

    access_points = _load_access_points(project_path)

    # ── Network schematic ─────────────────────────────────────────────────────
    st.subheader('Road Network & TAZ Schematic')
    fig = _build_network_schematic(corridors, zones, access_points)
    st.pyplot(fig, use_container_width=True)
    plt.close(fig)

    # ── Corridor summary table ────────────────────────────────────────────────
    with st.expander('Corridor Configuration', expanded=False):
        st.dataframe(corridors, use_container_width=True)

    # ── Zone summary table ────────────────────────────────────────────────────
    with st.expander('TAZ Zone Definitions', expanded=False):
        st.dataframe(zones, use_container_width=True)

    if access_points is not None:
        with st.expander('Access Points', expanded=False):
            st.dataframe(access_points, use_container_width=True)

    # ── Scenario list ─────────────────────────────────────────────────────────
    xf = Path(project_path) / 'scenario_config.xlsx'
    if xf.exists():
        try:
            sc_df = pd.read_excel(xf, sheet_name='ScenarioList', header=0)
            with st.expander('Available Scenarios', expanded=False):
                st.dataframe(sc_df, use_container_width=True)
        except Exception:
            pass
