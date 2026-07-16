# Unit Test Suite — Corridor Traffic Simulation Platform

This directory contains the unit tests for `corridor_sim/engine/`.

Tests are **fully isolated** from the main codebase:
- No imports from `tests/` exist anywhere in `corridor_sim/` or `run_simulation.py`
- No project xlsx files are required — all inputs are synthetic, in-memory data
- Tests can be run on any machine with Python 3.9+ and the packages in `requirements.txt`

---

## Running the tests

From the repo root:

```bash
# Run all tests (quiet)
pytest

# Run with coverage report
pytest --cov=corridor_sim/engine --cov-report=term-missing

# Run a specific module
pytest tests/test_godunov_flux.py -v
```

---

## Test modules

| Module | What it covers |
|--------|---------------|
| `test_godunov_flux.py` | Godunov numerical flux — free-flow, congested, capacity, zero, jam, lane scaling, non-negativity |
| `test_lwr_update.py` | LWR density update — conservation, source injection, sink removal, non-negativity, signal red phase, CFL stability |
| `test_demand_model.py` | 4-step demand model — trip productions, attraction balance, gravity distribution row sums / diagonal, mode choice scalar vs per-zone, network loading |
| `test_initialize_corridor.py` | Corridor initializer — required keys, Nx, lane array, speed array, signal cell index, state array shapes, initial density |
| `test_temporal_profiles.py` | `parametric_peaks()` — normalisation, 24 elements, peak location, non-negativity, sigma width, bimodal, weight scaling |

---

## conftest.py fixtures

| Fixture | Description |
|---------|-------------|
| `fd` | Greenshields FD: rho_j=1/18, rho_c=1/36, Q(rho,vf) |
| `vf` | Free-flow speed: 40 mph → ft/s |
| `sim_small` | 4-cell, 10-step simulation settings dict |
