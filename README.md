# Corridor Traffic Simulation Platform

**A configuration-driven macroscopic traffic corridor simulation platform for transportation consulting.**

Built on the Lighthill-Whitham-Richards (LWR) flow model and a NCHRP 716-compliant four-step demand model, the platform enables corridor alternatives analysis — signal retiming, land-use changes, and multi-modal demand shifts — without writing a single line of code.

---

## Key Capabilities

| Capability | Description |
|---|---|
| 🛣️ Multi-corridor LWR solver | 24-hour Godunov finite-volume solver on arterial corridors |
| 📊 4-Step demand model | NCHRP 716: trip generation, gravity distribution, mode choice, network loading |
| 🔀 Scenario engine | Signal retiming, land-use changes, mode-split overrides — all config-driven |
| 🖥️ Web dashboard | Streamlit front-end — no MATLAB, no coding required |
| 📁 Project-based data model | One Excel folder per study corridor; zero engine code changes |
| 🧪 Unit test suite | 62 isolated tests, 86%+ engine coverage — credible to clients |
| 📄 Open platform | Python 3.9+, no proprietary dependencies |

---

## Quick Start

### Option A — Web Dashboard (recommended)

```bash
# 1. Install dependencies (once)
pip install -r requirements.txt

# 2. Launch the dashboard
streamlit run dashboard/app.py
```

On **Windows**, double-click [`run_dashboard.bat`](run_dashboard.bat).  
On **macOS / Linux**, run `./run_dashboard.sh`.

The dashboard opens at **http://localhost:8501** and provides:
- **Project Setup** — road network schematic, corridor and TAZ config tables, scenario list
- **▶ Run Simulation** — one-click run with live progress log (`demand_only` < 1 s, `full` ≈ 30 s)
- **Results** — Space-Time density · OD Matrix · Boundary Flow vs MDOT · Scenario Comparison

---

### Option B — Command Line

```bash
# Baseline full run (UM-Dearborn demo)
python run_simulation.py --project projects/UM_Dearborn --mode full

# Fast demand-only calibration
python run_simulation.py --project projects/UM_Dearborn --mode demand_only

# Named scenario
python run_simulation.py --project projects/UM_Dearborn --mode full --scenario SignalRetiming_A
```

---

### Option C — MATLAB (archived reference)

The original MATLAB implementation is preserved in [`matlab_archive/`](matlab_archive/README.md).  
**Requires MATLAB R2020b or later.** No active development occurs in MATLAB.

---

## Repository Structure

```
.
├── corridor_sim/
│   └── engine/
│       ├── lwr_model.py              # LWR Godunov solver
│       ├── demand_model.py           # NCHRP 716 four-step demand model
│       ├── initialize_corridor.py    # Universal corridor initializer
│       ├── apply_scenario.py         # Scenario override engine
│       ├── plot_scenario_comparison.py
│       ├── helpers.py                # Temporal profiles, plotting utilities
│       ├── load_truth_data.py        # Read MDOT AADT from project xlsx
│       └── load_od_access.py         # Read OD-access tensor from project xlsx
│
├── dashboard/
│   ├── app.py                        # Streamlit entry point
│   ├── engine_runner.py              # Engine wrapper (stdout capture)
│   ├── sidebar.py                    # Project/scenario/override controls
│   └── pages/
│       ├── project_setup.py          # Network schematic page
│       └── results.py                # Tabbed results page
│
├── projects/
│   └── UM_Dearborn/                  # Demo / reference project
│       ├── corridor_config.xlsx      # Road geometry, lanes, signals
│       ├── taz_config.xlsx           # TAZ zones, access points, OD-access
│       ├── truth_data.xlsx           # MDOT AADT truth data
│       ├── scenario_config.xlsx      # Named scenario overrides
│       ├── HouseholdData.xlsx        # Household cross-classification data
│       ├── TripRateData.xlsx         # Trip rate tables + attraction params
│       └── demo_script.py            # One-click pitch demo
│
├── templates/                        # Blank xlsx templates for new projects
│   ├── corridor_config_template.xlsx
│   ├── taz_config_template.xlsx
│   └── truth_data_template.xlsx
│
├── tests/                            # Isolated unit tests (no xlsx deps)
├── matlab_archive/                   # Original MATLAB reference implementation
├── docs/
│   ├── methodology.md                # Technical reference (PE audience)
│   └── new_project_guide.md          # Step-by-step guide for new corridors
│
├── run_simulation.py                 # CLI runner
├── run_dashboard.bat                 # Windows launcher
├── run_dashboard.sh                  # macOS/Linux launcher
└── requirements.txt
```

---

## How to Add a New Corridor

A new corridor study requires **only Excel files** — no code changes.

1. Copy [`templates/`](templates/) to `projects/<YourProject>/`
2. Fill in **`corridor_config.xlsx`** — road names, lengths, lane segments, signal timing
3. Fill in **`taz_config.xlsx`** — zone centroids, access points, intersection connections, OD-access matrices
4. Fill in **`truth_data.xlsx`** — MDOT (or equivalent agency) AADT and hourly distributions
5. Add household and trip rate data in **`HouseholdData.xlsx`** and **`TripRateData.xlsx`** (one sheet per zone)
6. Optionally define scenarios in **`scenario_config.xlsx`**
7. Run:

```bash
python run_simulation.py --project projects/YourProject --mode demand_only
```

See [`docs/new_project_guide.md`](docs/new_project_guide.md) for a full annotated walkthrough.

---

## Running the Tests

```bash
pytest                          # all 62 tests, ~0.7 s
pytest --cov=corridor_sim/engine --cov-report=term-missing
```

Tests are fully isolated — no project Excel files required. See [`tests/README.md`](tests/README.md).

---

## Documentation

| Document | Audience |
|---|---|
| [`docs/methodology.md`](docs/methodology.md) | PE-licensed transportation engineers |
| [`docs/new_project_guide.md`](docs/new_project_guide.md) | Consulting staff / project setup |
| [`matlab_archive/README.md`](matlab_archive/README.md) | MATLAB reference implementation notes |
| [`projects/UM_Dearborn/README.md`](projects/UM_Dearborn/README.md) | Demo project documentation |

---

## Methodology Summary

The platform implements a macroscopic traffic flow simulation chain:

1. **Trip Generation** — NCHRP 716 cross-classification household model (productions) and linear land-use model (attractions)
2. **Trip Distribution** — singly-constrained gravity model with exponential friction factor
3. **Mode Choice** — scalar auto-occupancy (baseline) or per-zone auto-share (scenario)
4. **Network Loading** — OD-access tensor maps person-trips to road-level vehicle source/sink flows
5. **LWR Solver** — Godunov finite-volume scheme on the Greenshields fundamental diagram, 1-second time step, 500-ft spatial cells, 24-hour horizon

See [`docs/methodology.md`](docs/methodology.md) for full mathematical detail.

---

## License

See [`LICENSE`](LICENSE).

---

*Developed at the University of Michigan–Dearborn ITE Student Chapter.  
Reference implementation: `matlab_archive/UM_dearborn_ITESandbox2026_V05.m`.*
