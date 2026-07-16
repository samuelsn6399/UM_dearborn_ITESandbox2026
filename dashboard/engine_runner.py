"""
engine_runner.py
================
Thin wrapper around run_simulation.main() that captures stdout line-by-line
and delivers results back to the Streamlit session.

The runner is intentionally kept free of any Streamlit imports so it can be
unit-tested or called from a plain Python script.

Usage
-----
    from dashboard.engine_runner import run_engine

    for line in run_engine(project='projects/UM_Dearborn',
                           mode='full',
                           scenario='Baseline'):
        if isinstance(line, dict):
            results = line          # final payload
        else:
            print(line)             # progress message
"""

from __future__ import annotations
import io
import sys
import contextlib
from pathlib import Path


def run_engine(
    project: str = 'projects/UM_Dearborn',
    mode: str = 'full',
    scenario: str | None = None,
):
    """
    Run the simulation engine and yield progress lines then the results dict.

    Yields
    ------
    str   Progress log lines (from stdout).
    dict  Final results payload ``{'sim', 'demand', 'roads', 'TAZ'}`` as the
          last yielded item.

    Parameters
    ----------
    project  : str  Path to the project folder.
    mode     : str  'full' or 'demand_only'.
    scenario : str | None  Named scenario or None for baseline.
    """
    # Import here so the module loads even before corridor_sim is importable
    # (e.g. during a cold Streamlit import cycle)
    import run_simulation  # type: ignore

    # Capture all stdout written during main()
    buf = io.StringIO()
    results: dict = {}

    class _TeeStream:
        """Write to buf and collect newline-terminated lines for yielding."""
        def __init__(self):
            self._line = ''
            self.lines: list[str] = []

        def write(self, text):
            buf.write(text)
            self._line += text
            if '\n' in self._line:
                parts = self._line.split('\n')
                for p in parts[:-1]:
                    self.lines.append(p)
                self._line = parts[-1]

        def flush(self):
            pass

    tee = _TeeStream()
    old_stdout = sys.stdout
    sys.stdout = tee  # type: ignore

    try:
        results = run_simulation.main(
            project=project,
            mode=mode,
            scenario=scenario if scenario and scenario != 'Baseline' else None,
        )
    except Exception as exc:
        sys.stdout = old_stdout
        yield f'[ERROR] {exc}'
        return
    finally:
        sys.stdout = old_stdout

    # Yield any remaining buffered output
    for line in tee.lines:
        yield line
    if tee._line:
        yield tee._line

    # Flush remaining lines from the buffer not yet yielded
    buf.seek(0)

    # Final payload
    yield results


def list_projects(root: str = 'projects') -> list[str]:
    """
    Return subfolder names under *root* that look like valid projects
    (i.e. they contain a corridor_config.xlsx file).

    Parameters
    ----------
    root : str  Path to the projects directory.

    Returns
    -------
    names : list[str]  Project folder names (not full paths).
    """
    root_path = Path(root)
    if not root_path.is_dir():
        return []
    return sorted(
        p.name
        for p in root_path.iterdir()
        if p.is_dir() and (p / 'corridor_config.xlsx').exists()
    )


def list_scenarios(project: str) -> list[str]:
    """
    Return scenario names from scenario_config.xlsx, prepended with 'Baseline'.

    Parameters
    ----------
    project : str  Path to the project folder.

    Returns
    -------
    names : list[str]
    """
    from corridor_sim.engine.apply_scenario import (
        load_scenario_list, scenario_config_exists,
    )
    path = Path(project)
    all_names = ['Baseline']
    if scenario_config_exists(path):
        all_names += load_scenario_list(path)
    # Deduplicate while preserving insertion order
    seen: set[str] = set()
    unique: list[str] = []
    for n in all_names:
        if n not in seen:
            seen.add(n)
            unique.append(n)
    return unique
