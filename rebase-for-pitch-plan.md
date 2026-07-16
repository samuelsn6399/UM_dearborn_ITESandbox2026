# Rebase for Consulting Firm Pitch — Plan

## Top-Level Overview

**Goal:** Transform the UM-Dearborn ITE Sandbox simulation from a campus-specific MATLAB research script
into a generalizable, configuration-driven corridor simulation platform — implemented in Python — that can
be credibly pitched to a regional transportation consulting firm as a licensable product.

**Scope:** Full migration from MATLAB to Python, full generalization of the codebase (no UM-Dearborn
hard-coding), a configuration-file–driven input system so the firm's engineers never edit source code,
a comprehensive unit test suite that demonstrates correctness to clients, a web dashboard front-end so
non-engineers can run scenarios, and expanded scenario capabilities covering signal retiming, land-use
changes, and multi-modal demand. The UM-Dearborn corridor is retained as the packaged demo/reference case.

**Non-Goals:**
- Deployment-ready statistical validation against a second independent corridor (not required for pitch)
- Deciding a licensing model (pitch is exploratory)
- Real-time or hardware-in-the-loop simulation

**Approach:** Work in seven sequential sub-tasks: (1) Python migration, (2) platform/data separation,
(3) universal corridor initializer, (4) configuration-file input system, (5) expanded scenario engine,
(6) unit test suite, (7) front-end dashboard, (8) pitch-ready packaging and documentation.

**Front-End Technology Decision:** Python / Streamlit calling the Python engine — no MATLAB license
required on client machines, runs in a browser, deployable via a standard Python environment.

---

## Sub-Task 1 — Migrate Codebase from MATLAB to Python

### Intent
The entire codebase is currently MATLAB. Migrating to Python eliminates the MATLAB licensing cost
barrier for the firm and their clients, enables integration with GIS and data pipelines the firm already
uses, and makes the Streamlit dashboard (Sub-Task 7) straightforward to build. This is the foundational
step — all subsequent sub-tasks are written against the Python codebase.

### Expected Outcomes
- A Python package (`corridor_sim/`) at the repo root that faithfully replicates every computation
  currently performed by the MATLAB scripts
- `run_simulation.py` is the new top-level runner, accepting a project path argument
- All numerical outputs (density arrays, flow arrays, OD matrices, daily volumes) match the MATLAB
  reference to within floating-point tolerance for the UM-Dearborn demo case
- The MATLAB files are archived under `matlab_archive/` and are no longer part of the active codebase
- Python package dependencies are captured in `requirements.txt` or `pyproject.toml`

### Todo List
1. Set up Python project structure: `corridor_sim/` package with `__init__.py`, `requirements.txt`,
   and a `run_simulation.py` runner script
2. Translate `LWRModel.m` → `corridor_sim/lwr_model.py`:
   - `lwr_model(road, rho_n, demand, zone, sim)` function
   - `godunov_flux(fd, vf, rho_up, rho_down, n_lanes)` inner function
   - Use NumPy arrays throughout; match the exact update formula `rho_next[i] = rho_n[i] + (dt/dx)*(F_net + s)`
3. Translate `ClassicTrafficDemandModel.m` → `corridor_sim/demand_model.py`:
   - `classic_traffic_demand_model(zone)` function
   - Use `openpyxl` or `pandas` for xlsx reading instead of `readmatrix`
   - Preserve all four steps (productions, attractions, gravity distribution, mode choice, network loading)
4. Translate `MdotTruthData.m` → `corridor_sim/truth_data.py`:
   - `mdot_truth_data(roadway_name)` function returning the same `truth` dict
5. Translate each corridor constructor to Python dicts/dataclasses as a temporary step (will be replaced
   by the universal initializer in Sub-Task 3):
   - `corridor_sim/corridors/evergreen_sb.py`, `evergreen_nb.py`, `hubbard_eb.py`, `hubbard_wb.py`
6. Translate the top-level runner `UM_dearborn_ITESandbox2026_V05.m` → `run_simulation.py`:
   - All simulation loop logic, QuickTune application, and post-processing steps
   - Use `matplotlib` for all plots (replace MATLAB figure/subplot/imagesc calls)
   - Preserve all `plotfmt` styling controls as a Python dict
7. Translate helper functions (`parametricPeaks`, `hourIndex`, `applyFigureFormat`, `exportFigure`,
   `mapAccessPoints`, `mapIntersectionPoints`, `plotRoadGeometry`) to `corridor_sim/helpers.py`
8. Run the UM-Dearborn demo end-to-end in Python and compare key scalar outputs against the MATLAB
   reference (daily boundary volumes, peak density, OD matrix totals) — document the comparison

### Relevant Context
- Core solver update equation in `LWRModel.m` line 109:
  `rho_next(i) = rho_n(i) + (sim.dt/sim.dx)*(F_n_net + s_n(i))`
- Godunov flux in `LWRModel.m` lines 117–144: min(Demand, Supply) × N_lanes
- Greenshields FD in runner line 66: `Q = vf * rho * (1 - rho/rho_j)`
- OD demand injection per time step in `LWRModel.m` lines 54 and 68:
  `V_taz_depart(road.idx, taz) * f_depart(h, taz) / 3600`
- The MATLAB `struct` pattern maps cleanly to Python `dict` or `dataclasses.dataclass`
- `readmatrix` xlsx calls map to `pandas.read_excel(..., sheet_name=..., header=0)`
- MATLAB `zeros(Nx, Nt)` maps to `np.zeros((Nx, Nt))`
- MATLAB `imagesc` maps to `matplotlib.pyplot.imshow` with `aspect='auto'`

### Status
[x] done — Python package corridor_sim/ created; full 24-hour LWR simulation runs in 32 s;
    all scalar outputs (P, A, OD totals, MDOT AADT) match MATLAB reference exactly.

---

## Sub-Task 2 — Separate Platform Code from Project-Specific Data

### Intent
The current codebase has UM-Dearborn geometry, TAZ names, AADT counts, and household data baked into
`.m` files. Before anything else, a clean boundary must be drawn between the reusable simulation engine
(platform layer) and the project-specific inputs (data layer). This makes the generalization in Sub-Tasks
2–3 meaningful and makes the pitch argument about "platform vs. project" credible to the firm.

### Expected Outcomes
- All UM-Dearborn–specific values (road names, lengths, lane counts, signal positions, TAZ names/locations,
  AADT truth data) are isolated in a single `projects/UM_Dearborn/` folder
- The root directory contains only engine files and a top-level runner
- No hard-coded project strings remain in any engine `.m` file

### Todo List
1. Create a `projects/UM_Dearborn/` directory
2. Move `HouseholdData.xlsx`, `TripRateData.xlsx` into `projects/UM_Dearborn/`
3. Create `projects/UM_Dearborn/corridor_config.xlsx` capturing all values currently hard-coded in the
   four Python corridor modules from Sub-Task 1: name, index, length, boundary TAZ indices, lane ranges,
   signal params, speed ranges
4. Move the four Python corridor modules (`evergreen_sb.py`, etc.) into `projects/UM_Dearborn/` as
   archived reference; they will be replaced by the universal initializer in Sub-Task 3
5. Reorganize Python package: move solver and demand engine into `corridor_sim/engine/`
6. Create `projects/UM_Dearborn/taz_config.xlsx` capturing TAZ names, centroid coordinates, peak hours,
   and sigma values currently hard-coded in `run_simulation.py`
7. Update `run_simulation.py` to load all inputs from a given `projects/<name>/` path — no literals
   in the runner

### Relevant Context
- Hard-coded parameters identified per corridor (MATLAB source, now translated to Python in Sub-Task 1):
  name, idx, length, boundary_idx, lane ranges, signal x / green / red / Qsat, speed limit ranges
- TAZ hard-coding is in `UM_dearborn_ITESandbox2026_V05.m` lines 76–171 (now in `run_simulation.py`)
- MDOT AADT and hourly distributions: now in `corridor_sim/truth_data.py` from Sub-Task 1
- xlsx sheet names for demand data: now in `corridor_sim/demand_model.py` from Sub-Task 1

### Status
[x] done — projects/UM_Dearborn/ created; corridor_config.xlsx + taz_config.xlsx written;
    corridor_sim/engine/ reorganised; initialize_corridor.py built; run_simulation.py loads
    all inputs from project path; full 24-hour simulation produces identical outputs.

---

## Sub-Task 3 — Build a Universal Corridor Initializer

### Intent
The four corridor `.m` files (`EvergreenRdSouthbound.m`, etc.) are structurally identical — they differ
only in hard-coded values. Replace them with a single `engine/initializeCorridor.m` function that accepts
a corridor configuration struct and returns the same `road` struct the solver already expects. This is
the core generalization step — after this, adding a new road to any project requires only a new row in the
config file, not a new `.m` file.

### Expected Outcomes
- `engine/initializeCorridor.m` exists and accepts `(corridorConfig, sim, FD)` as inputs
- The function replicates the exact output struct currently produced by each of the four corridor files
- The UM-Dearborn demo runs correctly using this function loaded from `corridor_config.xlsx`
- The four original corridor `.m` files are no longer called by the runner

### Todo List
1. Define the `CorridorConfig` dataclass schema in Python:
   - `name`, `idx`, `length`, `boundary_idx`
   - `lane_segments`: list of `{x_start, x_end, n_lanes}` dicts
   - `speed_segments`: list of `{x_start, x_end, mph}` dicts
   - `signal`: `{x, green, red, Qsat_per_lane}` dict
2. Write `corridor_sim/engine/initialize_corridor.py` — `initialize_corridor(config, sim, fd)` function:
   - Computes `road['Nx']`, `road['x_edges']`, `road['x_centers']` from `length` and `sim['dx']`
   - Builds `road['N_lanes']` from `lane_segments` using a vectorized NumPy range lookup
   - Builds `road['FD']['vf']` from `speed_segments` using a vectorized NumPy range lookup
   - Configures `road['signal']` and `road['is_signal']` from `signal` config
   - Initializes all state arrays (`rho`, `F`, `F_desired`, `g`, `g_eff`, `s`) to the same shapes
     the solver expects
3. Write `corridor_sim/engine/load_corridor_config.py` — `load_corridor_config(project_path)` that reads
   `corridor_config.xlsx` and returns a list of `CorridorConfig` objects
4. Update `run_simulation.py` to replace the four direct corridor imports with a loop over
   `load_corridor_config(project_path)`
5. Validate: run the UM-Dearborn demo end-to-end and confirm numerical outputs are unchanged from
   Sub-Task 1 baseline

### Relevant Context
- Output dict keys required by `lwr_model.py` (translated in Sub-Task 1): `name`, `idx`, `length`, `Nx`,
  `x_edges`, `x_centers`, `N_lanes`, `FD`, `signal`, `is_signal`, `boundary_idx`, `rho`, `F`,
  `F_desired`, `g`, `g_eff`, `s`
- `lwr_model.py`: `vf` is accessed per-cell as a NumPy array of shape `(Nx,)` — must remain so
- `lwr_model.py`: `is_signal` is a boolean NumPy array of shape `(Nx,)` — must remain so
- Signal cell index: `np.argmax(x_centers >= signal['x'])` — move this into the initializer

### Status
[x] done — CorridorConfig dataclass, initialize_corridor(), and load_corridor_config() delivered
    in corridor_sim/engine/initialize_corridor.py. All 4 corridors load from corridor_config.xlsx
    with correct keys, shapes, lane/speed profiles, and signal configuration. PASS.

---

## Sub-Task 4 — Configuration-File–Driven TAZ and Demand Inputs

### Intent
TAZ geometry, demand parameters, access points, intersection connections, and AADT truth data are all
currently hard-coded in the runner or in `MdotTruthData.m`. Externalizing these into structured config
files completes the generalization — a new corridor study requires only new data files, zero code changes.
This is a critical pitch differentiator: show the firm that a new engagement is a data-entry exercise,
not a software project.

### Expected Outcomes
- TAZ definitions, access points, and intersection connections are read from `projects/<name>/taz_config.xlsx`
- AADT and hourly distribution truth data are read from `projects/<name>/truth_data.xlsx`
- `ClassicTrafficDemandModel.m` reads sheet names dynamically from a list of zone names rather than
  hard-coded strings
- The OD-access connectivity matrix (currently hard-coded in `ClassicTrafficDemandModel.m` lines 165–178)
  is stored in the project config, not in engine code
- A new project folder with correctly formatted xlsx files is all that is required to run the platform on
  a new corridor

### Todo List
1. Define the `taz_config.xlsx` schema:
   - Sheet `Zones`: columns — ZoneName, xLocation, yLocation, PeakArrive, SigmaArrive, PeakDepart,
     SigmaDepart
   - Sheet `AccessPoints`: columns — TazIndex, RoadName, xLocal, Split, AccessPointName
   - Sheet `Intersections`: columns — RoadName, xLocal, ExternalTazIndices (comma-separated)
   - Sheets `ODAccess_Depart` and `ODAccess_Arrive`: one row per road, one column per zone, values 0 or 1
2. Define the `truth_data.xlsx` schema:
   - One sheet per road: columns — Hour (1–24), AADT, HourlyCount
3. Write `corridor_sim/engine/load_taz_config.py` — `load_taz_config(project_path)` that reads
   `taz_config.xlsx` and returns the `taz` dict and `intersection` list in the format `lwr_model.py`
   and `demand_model.py` expect
4. Update `corridor_sim/engine/demand_model.py` to accept `zone_names` as a parameter for sheet lookups —
   removing all hard-coded sheet name strings
5. Update `corridor_sim/engine/demand_model.py` to accept the OD-access tensor as a parameter
6. Write `corridor_sim/engine/load_truth_data.py` — `load_truth_data(project_path, road_name)` reading
   from `truth_data.xlsx`, returning the same `truth` dict structure
7. Update `run_simulation.py` to use these loaders — no project-specific literals anywhere in the runner

### Relevant Context
- `demand_model.py` (from Sub-Task 1): six hard-coded `pd.read_excel(..., sheet_name='MainCampus')` etc.
- `demand_model.py` (from Sub-Task 1): four hard-coded OD-access matrices built inline
- `truth_data.py` (from Sub-Task 1): AADT values and raw hourly distributions still as Python literals
- `run_simulation.py` (from Sub-Task 1): TAZ dict, access points list, and intersection list still inline

### Status
[x] done — truth_data.xlsx written; load_truth_data.py and load_od_access.py added to engine;
    demand_model.py accepts od_access parameter; QuickTune loop is data-driven from config;
    run_simulation.py contains zero hard-coded project literals. Full simulation: PASS.

---

## Sub-Task 5 — Expanded Scenario Engine

### Intent
The firm's core use case is corridor alternatives analysis. The current model supports only a single
scenario per run, with no structured way to define, compare, or report on multiple alternatives. This
sub-task adds a scenario layer: signal retiming, land-use changes, and multi-modal demand switches, each
representable as a named parameter override on top of a base configuration. This is the feature that
makes the pitch compelling — the firm can show a client three alternatives in one report.

### Expected Outcomes
- A `scenarios/` folder structure where each scenario is a named set of overrides on the base config
- Signal retiming scenario: override `signal.green`, `signal.red` per corridor without editing base files
- Land-use scenario: override `AttractionParams` (employment, enrollment, retail sqft) per zone
- Multi-modal demand scenario: add a mode split table (auto, transit, bike, walk) so OD person-trips are
  apportioned to vehicle trips via a configurable, scenario-dependent mode share rather than a fixed
  occupancy factor
- A scenario comparison report: console table and bar chart comparing daily volumes and peak-hour densities
  across named scenarios

### Todo List
1. Define a `scenario_config.xlsx` schema:
   - Sheet `ScenarioList`: ScenarioName, BaseProject, Description
   - Sheet `SignalOverrides`: ScenarioName, RoadName, Green_s, Red_s, Qsat_per_lane
   - Sheet `LandUseOverrides`: ScenarioName, ZoneName, Employment, Enrollment, RetailArea_sqft
   - Sheet `ModeSplitOverrides`: ScenarioName, ZoneName, AutoShare, TransitShare, BikeShare, WalkShare
2. Write `corridor_sim/engine/apply_scenario.py` — `apply_scenario(base_configs, scenario_name,
   scenario_path)`: loads `scenario_config.xlsx`, applies overrides, returns modified configs without
   mutating base configs
3. Generalize `demand_model.py` Step 3 (mode choice) to use a per-zone `auto_share` list instead of
   a scalar `auto_occupancy`, enabling mode-shift scenario modeling
4. Update `run_simulation.py` to accept an optional `--scenario` argument; when provided, load
   `scenario_config.xlsx` and call `apply_scenario()` before initializing corridors
5. Add `corridor_sim/engine/plot_scenario_comparison.py` — overlays boundary flow time series and daily
   volume bars for two or more named scenario result sets using matplotlib
6. Re-run UM-Dearborn demo with a sample signal retiming scenario and a land-use scenario to validate
   the scenario engine end-to-end

### Relevant Context
- `demand_model.py` (Sub-Task 1): `T_vehicle = T_person / auto_occupancy` — single scalar; becomes
  a per-zone NumPy array when mode splits are enabled
- Signal parameters live inside `road['signal']` built at initialization time; `apply_scenario` must
  call `initialize_corridor` again for any corridor with signal overrides to regenerate `is_signal`
  and `signal['Qsat']`
- The `QUICKTUNE` dict in `run_simulation.py` (Sub-Task 1) is effectively a manual scenario override —
  fold it into the scenario config system as a special `QuickTune` scenario type

### Status
[x] done — apply_scenario.py, plot_scenario_comparison.py built; demand_model.py extended
    with auto_share parameter; scenario_config.xlsx written with 4 demo scenarios;
    run_simulation.py wired with --scenario arg; all 4 scenarios validated end-to-end.

---

## Sub-Task 6 — Unit Test Suite

### Intent
A consulting firm deploying this tool on client projects needs confidence that the simulation engine
produces correct results. A dedicated unit test suite — isolated from the main codebase in a `tests/`
folder — demonstrates that each computational component (Godunov flux, LWR update, gravity model,
trip generation, mode choice, temporal profiles, corridor initialization) produces verified outputs
against known analytical or hand-calculated values. The tests serve double duty: quality assurance
for the development team and a credibility artifact shown to the client during the pitch.

### Expected Outcomes
- A `tests/` directory at the repo root, containing only test files — no imports from `tests/` exist
  anywhere in `corridor_sim/` or `run_simulation.py`
- Tests cover all core engine functions with isolated, self-contained inputs (no project data files
  required to run the tests)
- All tests pass with a single `pytest` invocation from the repo root
- Test coverage report shows > 80% coverage of `corridor_sim/engine/`
- A `tests/README.md` explains what each test module covers and how to run them

### Todo List
1. Create `tests/` directory with a `conftest.py` (shared fixtures only — no project data dependencies)
   and `tests/README.md`
2. Write `tests/test_godunov_flux.py`:
   - Free-flow case: upstream density below critical → flux equals upstream demand
   - Congested case: downstream density above critical → flux equals downstream supply
   - Capacity case: both at critical density → flux equals capacity `Q(rho_c, vf)`
   - Zero density case: flux should be zero
   - Full jam case: downstream at jam density → flux should be zero
3. Write `tests/test_lwr_update.py`:
   - Single-cell conservation: net zero source/sink → density conserved over one timestep
   - Source injection: positive source term increases density by expected amount
   - Sink removal: negative source term decreases density by expected amount
   - CFL stability: timestep satisfying CFL condition produces non-negative densities
   - Boundary condition: inflow boundary correctly limits flux to supply capacity
4. Write `tests/test_demand_model.py`:
   - Trip generation: known household × rate table produces expected production total
   - Attraction balance: sum of balanced attractions equals sum of productions
   - Gravity distribution: row sums of T_person equal productions; no self-trips (diagonal = 0)
   - Mode choice: vehicle trips equal person trips divided by auto share
   - Network loading: V_taz_arrive and V_taz_depart sum correctly given a known OD table and access matrix
5. Write `tests/test_initialize_corridor.py`:
   - Lane array: verify N_lanes vector matches expected values at given positions for a toy corridor config
   - Speed array: verify vf vector matches expected values at given positions
   - Signal cell: verify is_signal flags the correct cell index
   - State array shapes: verify rho, F, g, s arrays have correct dimensions given Nx and Nt
6. Write `tests/test_temporal_profiles.py`:
   - Profile normalization: sum of 24-element profile equals 1.0
   - Peak location: argmax of profile matches specified peak hour (within ±1 hr)
   - Zero sigma edge case: profile degenerates to a spike at the peak hour
7. Add `pytest` and `pytest-cov` to `requirements.txt`; add a `pytest.ini` or `pyproject.toml`
   `[tool.pytest]` section pointing to `tests/` with coverage target on `corridor_sim/engine/`

### Relevant Context
- `lwr_model.py` (Sub-Task 1): `godunov_flux` and the density update loop are the two core functions
  to unit-test first — they are the numerical heart of the product
- `demand_model.py` (Sub-Task 1): Steps 1a, 1b/c, 2, 3, and 4 are each independently testable with
  small synthetic inputs
- `initialize_corridor.py` (Sub-Task 3): the lane/speed range-to-array mapping is a pure function
  and easily unit-tested with toy corridor configs
- Tests must use only Python stdlib, NumPy, Pandas, and pytest — no MATLAB, no project xlsx files

### Status
[x] done — 62 tests across 6 modules; all pass (0.69 s); godunov_flux renamed public for
    testability; lwr_model.py 86%, initialize_corridor.py 83% coverage; all tests isolated
    with no xlsx deps; tests/README.md written; pyproject.toml configures pytest.

---

## Sub-Task 7 — Web / App Dashboard Front-End

### Intent
A consulting firm's project managers, planners, and clients are not MATLAB users. To be a deployable
product, the platform needs a front-end that lets a non-engineer define a corridor project, select a
scenario, run the simulation, and view results — all without opening a `.m` file. This sub-task delivers
that interface, positioning the platform as a product rather than a research script.

### Expected Outcomes
- A runnable Streamlit dashboard that exposes:
  - Project selection (load an existing `projects/` folder)
  - Scenario selection and parameter override entry (signal timing, land-use, mode split)
  - Run button that executes the Python simulation engine in a subprocess
  - Results viewer showing space-time density, OD matrix, boundary flow vs. truth, and scenario comparison
- The dashboard writes user inputs back to the correct config xlsx files before running — it is a front-end
  wrapper, not a reimplementation of the engine
- The dashboard can be demoed live during the pitch without the audience touching code

### Todo List
1. Add `streamlit`, `plotly` (or `matplotlib` with `st.pyplot`) to `requirements.txt`
2. Design the UI layout:
   - Left panel: Project selector, Scenario selector, parameter override form
   - Center panel: Run button, progress log
   - Right panel: Tabbed results (Space-Time | OD Matrix | Boundary Flow | Scenario Compare)
3. Build the Project Setup screen: load `taz_config.xlsx` and `corridor_config.xlsx`, display a map-like
   schematic of the road network and TAZ positions using the x/y coordinate system
4. Build the Scenario Editor screen: form fields populated from `scenario_config.xlsx`, with dropdowns
   for road and zone names, numeric inputs for overrides
5. Build the Run Controller: calls `run_simulation.py` as a subprocess with the selected project path
   and scenario; streams stdout progress to the dashboard log panel
6. Build the Results Viewer: render matplotlib figures from `corridor_sim/engine/` as embedded Plotly or
   `st.pyplot` charts; include space-time density, OD matrix, boundary flow, and scenario comparison tabs
7. Package a one-click launcher (`run_dashboard.bat` / `run_dashboard.sh`) and add startup instructions
   to `README.md`

### Relevant Context
- `corridor_sim/helpers.py` (Sub-Task 1): `apply_figure_format`, `export_figure`, `plot_road_geometry`
  produce matplotlib figures — wrap with `st.pyplot(fig)` for Streamlit embedding
- The `plots` dict in `run_simulation.py` (Sub-Task 1) is the current toggle UI — the dashboard
  replaces those flags with sidebar checkboxes
- Streamlit's `st.sidebar` is well suited to the project/scenario selector; `st.tabs` for result panels

### Status
[ ] pending

---

## Sub-Task 8 — Pitch-Ready Packaging and Documentation

### Intent
A consulting firm evaluating a software product will expect professional documentation, a clean repo
structure, and a reproducible demo. This sub-task delivers the materials needed for the pitch itself:
a README that reads like a product brochure, a methodology document suitable for client proposals, and
a repeatable demo script that walks through the UM-Dearborn reference case end-to-end.

### Expected Outcomes
- `README.md` rewritten as a product overview: what the platform does, who it is for, how to get started,
  what a new project requires
- `docs/methodology.md`: description of the 4-step demand model, LWR solver, Godunov flux, Greenshields FD,
  and QuickTune calibration — written for a PE-licensed transportation engineer audience
- `docs/new_project_guide.md`: step-by-step instructions for setting up a new corridor project using only
  Excel files — no MATLAB knowledge assumed
- `projects/UM_Dearborn/` contains a `demo_script.m` (or equivalent) that runs the full demo in one click
  and produces all pitch figures automatically
- Repo structure is clean: no stale `.m` files, no `_V05` version suffixes, clear `engine/`, `projects/`,
  `scenarios/`, `docs/`, `dashboard/` folders

### Todo List
1. Create `projects/UM_Dearborn/demo_script.py` that calls `run_simulation.py` with the UM-Dearborn
   project path and produces all pitch figures automatically in one command
2. Rewrite `README.md` as a product overview with sections: Overview, Key Capabilities, Quick Start,
   Project Structure, How to Add a New Corridor, Running Tests, License/Contact
3. Write `docs/methodology.md` covering: 4-step demand model (NCHRP 716 basis), LWR PDE, Greenshields FD,
   Godunov flux, source/sink formulation, QuickTune calibration procedure — written for a PE-licensed
   transportation engineer audience
4. Write `docs/new_project_guide.md` with annotated Excel templates and a worked example for a hypothetical
   new corridor
5. Create Excel template files `templates/corridor_config_template.xlsx`,
   `templates/taz_config_template.xlsx`, `templates/truth_data_template.xlsx` with column headers,
   data type annotations, and example rows
6. Archive all MATLAB source files under `matlab_archive/` with a `matlab_archive/README.md` explaining
   that they are the original reference implementation
7. Final repo audit: verify all Python modules have docstrings (function name, inputs, outputs, units),
   remove any remaining hard-coded UM-Dearborn literals from engine code

### Relevant Context
- `NCHRP716.pdf` at the repo root is the primary methodology reference — cite in `methodology.md`
- `roadwayClassificationV01.png` at the repo root is a geometry diagram — include in documentation
- Current `README.md` is minimal — fully rewrite it as a product-facing document

### Status
[ ] pending

---

## Dependency Order

```
Sub-Task 1  Python migration
     |
Sub-Task 2  Separate platform/data
     |
Sub-Task 3  Universal corridor initializer
     |
Sub-Task 4  Config-file TAZ + demand inputs
     |
Sub-Task 5  Scenario engine
     |
Sub-Task 6  Unit test suite
     |
Sub-Task 7  Dashboard front-end
     |
Sub-Task 8  Packaging + docs
```

Sub-Tasks 1–4 must be completed in order — each builds on the prior structural change.
Sub-Task 5 depends on Sub-Tasks 3 and 4 having externalized all configs.
Sub-Task 6 depends on Sub-Task 5 having a stable, finalized engine API to test against.
Sub-Task 7 depends on Sub-Task 5 for the scenario API and Sub-Task 6 for confidence the engine is correct.
Sub-Task 8 can begin documentation writing in parallel with Sub-Task 7, but the demo script requires
Sub-Tasks 1–5 to be complete.
