# MATLAB Archive

This folder contains the original MATLAB implementation of the corridor traffic
simulation platform, preserved as a reference.

These files are **not used by the active Python codebase** and are kept solely
for:
- Cross-validation of numerical outputs against the Python translation
- Historical reference and methodology documentation

## File Index

| File | Description |
|------|-------------|
| `UM_dearborn_ITESandbox2026_V05.m` | Original top-level runner |
| `LWRModel.m` | LWR solver with Godunov flux |
| `ClassicTrafficDemandModel.m` | Four-step NCHRP 716 demand model |
| `MdotTruthData.m` | MDOT ground-truth AADT data |
| `EvergreenRdSouthbound.m` | Evergreen Rd SB corridor constructor |
| `EvergreenRdNorthbound.m` | Evergreen Rd NB corridor constructor |
| `HubbardRdEastbound.m` | Hubbard Rd EB corridor constructor |
| `HubbardRdWestbound.m` | Hubbard Rd WB corridor constructor |

## Python equivalents

| MATLAB file | Python equivalent |
|-------------|-------------------|
| `LWRModel.m` | `corridor_sim/engine/lwr_model.py` |
| `ClassicTrafficDemandModel.m` | `corridor_sim/engine/demand_model.py` |
| `MdotTruthData.m` | `corridor_sim/engine/truth_data.py` |
| `EvergreenRd*.m` / `HubbardRd*.m` | `corridor_sim/engine/initialize_corridor.py` (Sub-Task 3) |
| `UM_dearborn_ITESandbox2026_V05.m` | `run_simulation.py` |
