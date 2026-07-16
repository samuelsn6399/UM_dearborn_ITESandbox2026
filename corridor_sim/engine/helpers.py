"""
helpers.py
==========
Utility functions for the corridor simulation platform.

Covers: temporal profile generation, figure formatting, PNG export, road
geometry plotting, and access-point / intersection mapping.

Direct translation of the helper functions embedded in
UM_dearborn_ITESandbox2026_V05.m (MATLAB reference implementation).
"""

import os
import numpy as np
import matplotlib
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches


# ---------------------------------------------------------------------------
# Time helpers
# ---------------------------------------------------------------------------

def hour_index(t: float) -> int:
    """
    Convert simulation time [s] to a 1-based hour index (1–24).

    Parameters
    ----------
    t : float  Simulation time [s].

    Returns
    -------
    h : int  Hour index in [1, 24].
    """
    h = int(t / 3600) + 1
    return max(1, min(h, 24))


# ---------------------------------------------------------------------------
# Temporal demand profiles
# ---------------------------------------------------------------------------

def parametric_peaks(peak_params: dict) -> np.ndarray:
    """
    Build a raw 24-element Gaussian hourly profile.

    Normalise the output (f / f.sum()) to obtain fractional daily shares.

    Parameters
    ----------
    peak_params : dict with keys:
        w     : float or array-like  Peak weight(s).
        mu    : float or array-like  Peak hour(s) [1–24].
        sigma : float or array-like  Peak spread(s) [hours].

    Returns
    -------
    f : ndarray (24,)  Raw Gaussian profile (not normalised).
    """
    w     = np.atleast_1d(peak_params['w'])
    mu    = np.atleast_1d(peak_params['mu'])
    sigma = np.atleast_1d(peak_params['sigma'])
    h = np.arange(1, 25, dtype=float)
    f = np.zeros(24)
    for wi, mi, si in zip(w, mu, sigma):
        f += wi * np.exp(-((h - mi) ** 2) / (2 * si ** 2))
    return f


# ---------------------------------------------------------------------------
# Figure formatting and export
# ---------------------------------------------------------------------------

def apply_figure_format(fig, sz: tuple, pf: dict):
    """
    Resize a figure and apply report-grade text formatting.

    Parameters
    ----------
    fig : matplotlib Figure
    sz  : (width_in, height_in)  Physical size in inches.
    pf  : dict  Plot-format settings (font sizes, line widths, etc.).
    """
    fig.set_size_inches(sz)
    for ax in fig.get_axes():
        ax.tick_params(labelsize=pf['tick_fs'])
        ax.set_box_aspect(None)
        for spine in ax.spines.values():
            spine.set_linewidth(pf['ax_lw'])
        if pf['ax_box'] == 'off':
            ax.set_frame_on(False)
        ax.tick_params(direction=pf['tick_dir'])
        if ax.get_title():
            ax.title.set_fontsize(pf['title_fs'])
        if ax.get_xlabel():
            ax.xaxis.label.set_fontsize(pf['label_fs'])
        if ax.get_ylabel():
            ax.yaxis.label.set_fontsize(pf['label_fs'])
        leg = ax.get_legend()
        if leg:
            for text in leg.get_texts():
                text.set_fontsize(pf['legend_fs'])
    fig.tight_layout()


def export_figure(fig, name: str, pf: dict):
    """
    Save a figure as a PNG when pf['export'] is True.

    Parameters
    ----------
    fig  : matplotlib Figure
    name : str  Filename stem (no extension, no path).
    pf   : dict  Must contain 'export', 'export_dir', 'dpi'.
    """
    if not pf.get('export', False):
        return
    os.makedirs(pf['export_dir'], exist_ok=True)
    out_path = os.path.join(pf['export_dir'], f"{name}.png")
    fig.savefig(out_path, dpi=pf['dpi'], bbox_inches='tight',
                facecolor='white')
    print(f"  Exported: {out_path}")


# ---------------------------------------------------------------------------
# Road geometry visualisation
# ---------------------------------------------------------------------------

def plot_road_geometry(sim: dict, road: dict, x_edges, x_centers,
                       n_lanes, signal: dict, access: dict):
    """
    Visualise a corridor with lane geometry, signals, and access points.

    Parameters
    ----------
    sim      : dict  Simulation settings (dx).
    road     : dict  Road struct (name, length, Nx).
    x_edges  : ndarray  Cell boundary positions [ft].
    x_centers: ndarray  Cell centre positions [ft].
    n_lanes  : ndarray  Lanes per segment.
    signal   : dict     Signal configuration (cell index).
    access   : dict     Access points (xSegment, name).
    """
    max_lanes = int(np.max(n_lanes))
    fig, ax = plt.subplots(figsize=(7, 10))
    fig.patch.set_facecolor('white')
    ax.set_facecolor('white')

    for i in range(road['Nx']):
        y1 = x_edges[i]
        y2 = x_edges[i + 1]
        w  = n_lanes[i]
        rect = mpatches.FancyBboxPatch(
            (0, y1), w, y2 - y1,
            boxstyle='square,pad=0', linewidth=0,
            facecolor=(0.85, 0.85, 0.85))
        ax.add_patch(rect)
        ax.plot([0, w], [y1, y1], 'k--', linewidth=0.5)

    ax.plot([0, max_lanes], [road['length'], road['length']], 'k--', linewidth=0.5)

    # Signal
    sig_cells = np.atleast_1d(signal.get('cell', []))
    for cell in sig_cells:
        if cell:
            y_sig = x_centers[int(cell) - 1]   # cell is 1-based from MATLAB
            ax.axhline(y_sig, color='red', linewidth=3)
            ax.text(max_lanes * 0.02, y_sig + 80, 'Signal',
                    color='red', fontweight='bold', fontsize=8)

    # Access points
    band_half = sim['dx'] / 2
    if access.get('xSegment') is not None:
        segs  = np.atleast_1d(access['xSegment'])
        names = access.get('name', [''] * len(segs))
        for idx_k, seg in enumerate(segs):
            y = x_centers[int(seg) - 1]   # 1-based
            rect_ap = mpatches.FancyBboxPatch(
                (0, y - band_half), max_lanes, 2 * band_half,
                boxstyle='square,pad=0', linewidth=0,
                facecolor=(0.2, 0.8, 0.4), alpha=0.22)
            ax.add_patch(rect_ap)
            label = names[idx_k] if idx_k < len(names) else ''
            ax.text(max_lanes * 0.5, y, str(label),
                    ha='center', fontsize=8)

    ax.set_xlim(0, max_lanes)
    ax.set_ylim(0, road['length'])
    ax.set_xlabel('Road Width [# lanes]')
    ax.set_ylabel('Distance Along Corridor [ft]')
    ax.set_title(f"Road Geometry with Signals and Access Points: {road['name']}")
    ax.grid(True)
    ax.set_frame_on(True)

    h_road   = mpatches.Patch(facecolor=(0.85, 0.85, 0.85), label='Roadway (Lane Geometry)')
    h_signal = plt.Line2D([0], [0], color='red', linewidth=3, label='Signalized Intersection')
    h_access = mpatches.Patch(facecolor=(0.2, 0.8, 0.4), alpha=0.22, label='Access Point')
    ax.legend(handles=[h_road, h_signal, h_access], loc='upper right',
              bbox_to_anchor=(1.35, 1.0))

    fig.tight_layout()
    return fig


# ---------------------------------------------------------------------------
# Access point and intersection mapping
# ---------------------------------------------------------------------------

def map_access_points(road: dict, taz: dict) -> dict:
    """
    Filter TAZ access points by road name and resolve x-coordinates to
    finite-volume segment indices (1-based, matching MATLAB convention).

    Parameters
    ----------
    road : dict  Must contain 'name' and 'x_edges'.
    taz  : dict  Must contain 'AccessPoints' list.

    Returns
    -------
    road : dict  Same dict with 'AccessPoints' key populated.
    """
    x_edges = np.array(road['x_edges'])
    matching = [ap for ap in taz['AccessPoints']
                if ap['roadName'] == road['name']]
    resolved = []
    for ap in matching:
        ap = dict(ap)   # shallow copy — don't mutate original
        x_locals = np.atleast_1d(ap['xLocal'])
        segments = []
        for x_loc in x_locals:
            # find cell where x_edges[i] <= x_loc < x_edges[i+1]
            idx = np.where(
                (x_edges[:-1] <= x_loc) & (x_edges[1:] > x_loc)
            )[0]
            segments.append(int(idx[0]) + 1 if len(idx) > 0 else 1)  # 1-based
        ap['xSegment'] = segments
        ap['split']    = np.atleast_1d(ap['split'])
        resolved.append(ap)
    road = dict(road)
    road['AccessPoints'] = resolved
    return road


def map_intersection_points(road: dict, intersections: list) -> dict:
    """
    Filter intersections by road name and resolve x-coordinates to
    finite-volume segment indices (1-based).

    Parameters
    ----------
    road          : dict  Must contain 'name' and 'x_edges'.
    intersections : list  List of intersection dicts.

    Returns
    -------
    road : dict  Same dict with 'intersection' key populated.
    """
    x_edges = np.array(road['x_edges'])
    matching = [intr for intr in intersections
                if intr['roadName'] == road['name']]
    resolved = []
    for intr in matching:
        intr = dict(intr)
        x_locals = np.atleast_1d(intr['xLocal'])
        segments = []
        for x_loc in x_locals:
            idx = np.where(
                (x_edges[:-1] <= x_loc) & (x_edges[1:] > x_loc)
            )[0]
            segments.append(int(idx[0]) + 1 if len(idx) > 0 else 1)  # 1-based
        intr['xSegment'] = segments
        resolved.append(intr)
    road = dict(road)
    road['intersection'] = resolved
    return road
