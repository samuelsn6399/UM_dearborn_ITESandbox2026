# Methodology Reference

## Corridor Traffic Simulation Platform — Technical Documentation

**Audience:** PE-licensed transportation engineers reviewing simulation methodology for client engagements.  
**Reference standard:** NCHRP Report 716 — *Travel Demand Forecasting: Parameters and Techniques* (2012).

---

## 1. System Overview

The platform combines a macroscopic **four-step travel demand model** (supply of vehicle trips to the network) with a **first-order LWR traffic flow solver** (propagation of those trips through space and time). Both components operate on the same 24-hour simulation horizon and are linked through road-level vehicle source/sink flows.

```
Household Data   Trip Rate Data   Attraction Parameters
       │                │                  │
       └────────────────┴──────────────────┘
                        │
               ┌────────▼─────────┐
               │  4-Step Demand   │   Steps 1–4 (NCHRP 716)
               │     Model        │
               └────────┬─────────┘
                        │  V_taz_depart / V_taz_arrive
                        │  [veh/day] per road–TAZ pair
               ┌────────▼─────────┐
               │   LWR Solver     │   Godunov FV, Greenshields FD
               │  (Godunov FVM)   │   Δt = 1 s, Δx = 500 ft, 24 hr
               └────────┬─────────┘
                        │
              Space-time density ρ(x,t)
              Hourly boundary flows F(t)
```

---

## 2. Fundamental Diagram — Greenshields Model

The **Greenshields fundamental diagram (FD)** relates vehicle density ρ [veh/ft/lane] to flow F [veh/s/lane]:

```
F(ρ, v_f) = v_f · ρ · (1 − ρ / ρ_j)
```

| Parameter | Symbol | Value | Units |
|---|---|---|---|
| Jam density | ρ_j | 1/18 ≈ 0.0556 | veh/ft/lane (≈ 293 veh/mi/lane) |
| Critical density | ρ_c = ρ_j / 2 | 1/36 ≈ 0.0278 | veh/ft/lane |
| Free-flow speed | v_f | 30–45 mph (varies by segment) | mph (converted to ft/s) |
| Capacity | Q_max = v_f · ρ_c · (1 − ρ_c/ρ_j) | — | veh/s/lane |

The critical density ρ_c separates the **free-flow regime** (ρ < ρ_c, vehicles travel near free-flow speed) from the **congested regime** (ρ > ρ_c, speed falls below free-flow). Capacity Q_max = v_f · ρ_j / 4 is attained at ρ_c.

*Rationale:* The Greenshields model is analytically tractable, produces a unique Riemann solution (no sonic-point ambiguity), and is appropriate for arterial corridors at the mesoscopic resolution of this model (500-ft cells, 1-s time steps). More complex FDs (e.g., Newell-Daganzo triangular, Drake) can be substituted by modifying `lwr_model.py` without changing any other component.

---

## 3. LWR Traffic Flow Model

### 3.1 Conservation Law

The Lighthill-Whitham-Richards (LWR) model [Lighthill & Whitham 1955; Richards 1956] expresses conservation of vehicle density:

```
∂ρ/∂t + ∂F/∂x = s(x, t)
```

- **ρ(x, t)** [veh/ft/lane] — vehicle density at position x and time t  
- **F(ρ, v_f)** [veh/s] — traffic flow (Greenshields FD above)  
- **s(x, t)** [veh/s/ft] — net source/sink rate from TAZ access points and intersections

This first-order hyperbolic PDE models density waves propagating forward (in free-flow) or backward (in congestion) along the corridor.

### 3.2 Godunov Finite-Volume Scheme

The spatial domain is discretized into N_x cells of width Δx = 500 ft. Time is advanced in steps of Δt = 1 s. The explicit update rule for cell i at time step n is:

```
ρᵢⁿ⁺¹ = ρᵢⁿ + (Δt / Δx) · (Fᵢⁿ − Fᵢ₊₁ⁿ + sᵢⁿ)
```

where F_i is the **Godunov numerical flux** at the left face of cell i.

### 3.3 Godunov Flux — Supply/Demand Formulation

The Godunov flux at the interface between cells i (upstream) and i+1 (downstream) is:

```
F_interface = N_lanes · min( D(ρᵢ), S(ρᵢ₊₁) )
```

**Demand function** D(ρ) [veh/s/lane] — the maximum flow that the upstream cell can send:
```
D(ρ) = F(ρ,   v_f)   if ρ ≤ ρ_c   (free-flow: demand = actual flow)
D(ρ) = F(ρ_c, v_f)   if ρ > ρ_c   (congested: demand = capacity)
```

**Supply function** S(ρ) [veh/s/lane] — the maximum flow that the downstream cell can receive:
```
S(ρ) = F(ρ_c,   v_f)  if ρ ≤ ρ_c   (free-flow: supply = capacity)
S(ρ) = F(ρ,     v_f)  if ρ > ρ_c   (congested: supply = actual flow)
```

This supply/demand construction guarantees that traffic can only flow forward (no negative flux) and respects both the upstream sending capacity and the downstream receiving capacity simultaneously.

### 3.4 Boundary Conditions

**Upstream (inflow) boundary:**  
Flow enters from a TAZ boundary node. The inflow flux is limited by the downstream supply of cell 1:
```
F_upstream = min( F_OD_desired(t), S(ρ₁) · N_lanes )
```
where F_OD_desired is the demand model's hourly departure rate (see §5). When the road originates at an intersection (boundary_idx = 0), no explicit boundary flux is imposed — vehicles enter via the source term only.

**Downstream (outflow) boundary:**  
Free outflow — vehicles leave at the demand-limited rate of the last cell:
```
F_downstream = D(ρ_Nx) · N_lanes
```

### 3.5 Signal Gating

At cells containing a signalized intersection (`is_signal[i] = True`), the Godunov flux is additionally capped by the signal state:

```
F_signal_cell = min( F_Godunov, g(t) · Q_sat )
```

where:
- **g(t)** ∈ {0, 1} — green (1) or red (0) indicator at time t  
- **Q_sat** [veh/s] = Qsat_per_lane × N_lanes — saturation flow rate for the approach  
- **Period** = green + red [s]; phase advances cyclically from simulation start

Default signal: 45 s green / 75 s red (120-s cycle), Q_sat = 1 900 veh/hr/lane ≈ 0.528 veh/s/lane.

### 3.6 CFL Stability Condition

The explicit Godunov scheme is stable when the Courant-Friedrichs-Lewy (CFL) condition is satisfied:

```
C = v_f · Δt / Δx ≤ 1
```

With v_f = 45 mph = 66 ft/s, Δt = 1 s, Δx = 500 ft → C = 0.132 ≪ 1. The scheme is well within the stability limit for all modeled speed limits.

### 3.7 Source/Sink Formulation

Each TAZ access point on a road contributes a net source/sink to the cell it occupies:

```
s_k(t) = q_depart(k, t) − q_arrive(k, t)
```

where the hourly rates are:
```
q_depart(k, t) = V_taz_depart[road, k] · f_depart(h, k) / 3600   [veh/s]
q_arrive(k, t) = V_taz_arrive[road, k] · f_arrive(h, k) / 3600   [veh/s]
```

- **V_taz_depart[road, k]** — daily vehicle departures from TAZ k onto this road [veh/day]  
- **f_depart(h, k)** — fraction of daily departures occurring in hour h (24-element normalized Gaussian profile)  
- **h** — current 1-based hour index (1–24), updated each second

The net source/sink at each cell is the sum over all access points in that cell.

---

## 4. Four-Step Travel Demand Model

Implementation follows NCHRP 716 Chapter 4 (Cross-Classification Trip Generation) and Chapter 5 (Gravity Trip Distribution).

### Step 1a — Trip Generation: Productions

Trip productions for zone i are estimated by cross-classification:

```
P_i = Σ_{a,s}  H_i(a, s) · R_i(a, s)
```

- **H_i(a, s)** — number of households in zone i with auto-ownership a and household size s  
- **R_i(a, s)** — daily person-trip rate [trips/household] for that auto-ownership / size category  

Data source: `HouseholdData.xlsx` and `TripRateData.xlsx` (one sheet per zone).

### Step 1b — Trip Generation: Attractions

Attractions for zone j are estimated using a linear land-use model (ITE/NCHRP 716):

```
A_j (raw) = 1.5 · Employment_j + 0.4 · Enrollment_j + 0.01 · RetailArea_j [sqft]
```

Attraction rate coefficients [trips per unit]:

| Land-use category | Rate |
|---|---|
| Employment (jobs) | 1.5 trips/job/day |
| Enrollment (students) | 0.4 trips/student/day |
| Retail floor area | 0.01 trips/sqft/day |

These rates can be overridden per zone via the `LandUseOverrides` sheet in `scenario_config.xlsx`.

### Step 1c — Production/Attraction Balance

The raw attractions are scaled so the system total matches total productions (trip-end conservation):

```
A_j = A_j(raw) · ( Σ P_i / Σ A_j(raw) )
```

### Step 2 — Trip Distribution: Gravity Model

A singly-constrained gravity model distributes productions from each origin zone to destination zones:

```
T_person(i, j) = P_i · [ A_j · F(i,j) / Σ_k A_k · F(i,k) ]
```

The friction factor F(i, j) represents travel impedance between zones i and j. The default formulation is exponential decay with travel time:

```
F(i, j) = exp(−β · t_ij)
```

where t_ij [min] is computed from the Euclidean distance between zone centroids and an average corridor speed of 35 mph, and β = 0.12 /min is the decay coefficient. The diagonal F(i, i) = 0 (no intra-zonal auto trips).

A **uniform friction** option (all off-diagonal F = 1) is provided for simple, distance-insensitive distributions — useful when zone centroids are not precisely calibrated.

### Step 3 — Mode Choice

The baseline converts person-trips to vehicle trips using a scalar auto occupancy:

```
T_vehicle(i, j) = T_person(i, j) / auto_occupancy
```

Default auto_occupancy = 1.25 persons/vehicle.

For **multi-modal scenarios**, a per-zone auto share vector replaces the scalar:

```
T_vehicle(i, j) = T_person(i, j) · auto_share_i / auto_occupancy
```

where `auto_share_i` ∈ [0, 1] is the fraction of person-trips in zone i made by private automobile. This enables modeling transit investments, TDM programs, or campus mode-shift initiatives without changing any base data.

### Step 4 — Network Loading

The OD vehicle-trip table T_vehicle is mapped to road-level daily volumes via a binary OD-access tensor **Ω[r, i, j]**:

```
V_taz_depart[r, k] = Σ_{j ≠ k}  T_vehicle(k, j) · Ω[r, k, j]
V_taz_arrive[r, k] = Σ_{i ≠ k}  T_vehicle(i, k) · Ω[r, i, k]
```

- **Ω[r, i, j]** = 1 if vehicle trips from zone i to zone j use road r; 0 otherwise  
- **V_taz_depart[r, k]** — daily vehicles departing TAZ k via road r  
- **V_taz_arrive[r, k]** — daily vehicles arriving at TAZ k via road r  

Ω is stored in `taz_config.xlsx` (sheets `ODAccess_Depart`, `ODAccess_Depart_NB`, etc.) and loaded by `load_od_access.py`.

---

## 5. Temporal Demand Profiles

Daily volumes V_taz_depart/arrive are distributed across 24 hours using a **parametric Gaussian profile**:

```
f_raw(h) = w · exp( −(h − μ)² / (2σ²) )    h = 1, 2, …, 24
f(h) = f_raw(h) / Σ f_raw(h)               (normalized to sum = 1)
```

| Parameter | Description |
|---|---|
| μ | Peak hour [1–24] |
| σ | Spread [hours] — controls the width of the AM or PM peak |
| w | Weight — for bimodal profiles, two peaks are superposed |

The per-second departure/arrival rate for the LWR solver is then:

```
q(t) = V_daily · f( hour_index(t) ) / 3600    [veh/s]
```

Temporal parameters are stored per zone in `taz_config.xlsx` (columns `PeakDepart_hr`, `SigmaDepart_hr`, etc.) and can be calibrated using the **TAZ Temporal Parameter Recommendations** printed by the console report.

---

## 6. QuickTune Calibration

The QuickTune system provides a fast, non-destructive calibration mechanism. Each boundary flow is multiplied by a scale factor before being passed to the solver:

```
V_boundary_scaled = V_boundary_OD · QT_factor
```

QuickTune factors are stored in `taz_config.xlsx` (sheet `QuickTune`) and overridden per scenario in `scenario_config.xlsx`.

**Calibration procedure:**

1. Set all QT factors to 1.0. Run in `demand_only` mode.
2. Read the **Boundary Tuning Report** console output.
3. For each boundary, the recommended scale is:  
   `Rec. Scale = MDOT_daily / OD_daily`
4. Set QT factors to the recommended values. Re-run.
5. Iterate until all `Rec. Scale ≈ 1.0` (error < 5% acceptable).

When calibration is stable, the QT factors should be rationalized back to the source data (household counts, attraction parameters, OD-access connectivity) so the model is physically self-consistent.

---

## 7. Simulation Discretization and Accuracy

| Parameter | Value | Notes |
|---|---|---|
| Spatial cell width Δx | 500 ft | ~152 m; appropriate for arterial-level resolution |
| Time step Δt | 1 s | Godunov explicit; CFL ≈ 0.13 for 45 mph |
| Simulation horizon | 24 hours (86 400 steps) | Full daily cycle |
| Wall-clock time (4 roads) | ≈ 30 s | Python, NumPy vectorized |
| Initial density | 1% of ρ_c | Near-empty initial condition |

The model is **macroscopic** — it does not represent individual vehicles. Lane-changing, turning movements, and pedestrian interactions are not modeled. The source/sink formulation approximates driveways and intersections as point-distributed flows within a 500-ft cell.

---

## 8. References

1. Lighthill, M. J., & Whitham, G. B. (1955). On kinematic waves II: A theory of traffic flow on long crowded roads. *Proceedings of the Royal Society A*, 229(1178), 317–345.
2. Richards, P. I. (1956). Shock waves on the highway. *Operations Research*, 4(1), 42–51.
3. Greenshields, B. D. (1935). A study of traffic capacity. *Highway Research Board Proceedings*, 14, 448–477.
4. Transportation Research Board. (2012). *NCHRP Report 716: Travel Demand Forecasting: Parameters and Techniques*. National Academies Press. [`NCHRP716.pdf`](../NCHRP716.pdf)
5. Daganzo, C. F. (1994). The cell transmission model: A dynamic representation of highway traffic consistent with the hydrodynamic theory. *Transportation Research Part B*, 28(4), 269–287.
6. Godunov, S. K. (1959). A difference scheme for numerical solution of discontinuous solution of hydrodynamic equations. *Matematicheskii Sbornik*, 47, 271–306.
