# New Corridor Project Guide

## Setting Up a New Corridor Study

This guide walks through creating a new project for any arterial corridor — no MATLAB, no code changes required. All inputs are Excel files placed in a `projects/<YourProject>/` folder.

**Time estimate:** 2–4 hours for a two-road corridor with 4–6 TAZ zones.

---

## Prerequisites

- Python 3.9+ with the platform installed (`pip install -r requirements.txt`)
- MDOT (or equivalent state DOT) AADT counts and hourly distributions for each modeled road
- Household data by census block group (obtainable from ACS PUMS or local MPO model)
- Land-use data for each TAZ (employment, enrollment, retail area)
- Road geometry: length, lane configuration by segment, signal location and timing

---

## Step 0 — Create the Project Folder

```
projects/
└── YourProject/
    ├── corridor_config.xlsx      ← Step 1
    ├── taz_config.xlsx           ← Step 2
    ├── truth_data.xlsx           ← Step 3
    ├── HouseholdData.xlsx        ← Step 4
    ├── TripRateData.xlsx         ← Step 5
    └── scenario_config.xlsx      ← Step 6 (optional)
```

Copy the blank templates from `templates/` to your project folder:

```bash
xcopy /E templates\  projects\YourProject\
```

Or on macOS/Linux:
```bash
cp -r templates/ projects/YourProject/
```

---

## Step 1 — corridor_config.xlsx

Defines the road geometry: corridor names, lengths, lane configurations, speed limits, and signal timing.

### Sheet: Corridors

One row per road. Roads are modeled as independent 1-D corridors.

| Column | Type | Description | Example |
|---|---|---|---|
| `Name` | text | Full road name (must be unique; used in all other sheets) | `Main St Northbound` |
| `Idx` | integer | 1-based road index; determines order in `all_roads` | `1` |
| `Length_ft` | number | Total corridor length in feet | `7920` (1.5 mi) |
| `BoundaryIdx_In` | integer | TAZ index for the inflow boundary (from `taz_config.xlsx` Zones sheet row number, 1-based); `0` = intersection side | `3` |
| `BoundaryIdx_Out` | integer | TAZ index for the outflow boundary; `0` = intersection side | `4` |

> **Tip:** Draw your corridor with `x = 0` at the inflow end (where vehicles enter) and `x = Length_ft` at the outflow end. Match the direction to how MDOT measures inflow vs outflow.

### Sheet: LaneSegments

One row per lane-count segment per corridor. A corridor with a turn pocket or merge will have multiple rows.

| Column | Type | Description | Example |
|---|---|---|---|
| `CorridorName` | text | Must exactly match a `Name` in Corridors sheet | `Main St Northbound` |
| `XStart_ft` | number | Segment start position [ft] (x = 0 is inflow end) | `0` |
| `XEnd_ft` | number | Segment end position [ft] | `2640` |
| `NLanes` | integer | Number of through lanes in this segment | `3` |

**Coverage rule:** Every foot of the corridor must be covered by exactly one segment. Gaps produce zero lanes and will cause a division-by-zero in the flux calculation.

### Sheet: SpeedSegments

Same structure as LaneSegments but for free-flow speed. Posted speed limits work as a starting point; adjust during calibration.

| Column | Type | Description | Example |
|---|---|---|---|
| `CorridorName` | text | Matches Corridors sheet | `Main St Northbound` |
| `XStart_ft` | number | | `0` |
| `XEnd_ft` | number | | `7920` |
| `Speed_mph` | number | Free-flow speed [mph] | `35` |

### Sheet: Signals

One row per corridor (even if the corridor has no signal — use large values for green/red then).

| Column | Type | Description | Example |
|---|---|---|---|
| `CorridorName` | text | | `Main St Northbound` |
| `SignalX_ft` | number | Signal location along corridor [ft] | `5280` |
| `Green_s` | number | Green phase duration [s] | `45` |
| `Red_s` | number | Red phase duration [s] | `75` |
| `Qsat_per_lane_vehsperlane` | number | Saturation flow rate [veh/s/lane] | `0.528` |

> **Note:** Qsat = 1 900 veh/hr/lane = 0.528 veh/s/lane is a typical NACTO/HCM default.

---

## Step 2 — taz_config.xlsx

Defines the Traffic Analysis Zones: their locations, temporal demand profiles, access points, intersection connections, OD-access matrices, and QuickTune calibration factors.

### Sheet: Zones

One row per TAZ. Zone order defines the 1-based TAZ index used throughout.

| Column | Type | Description | Example |
|---|---|---|---|
| `ZoneName` | text | Unique zone name (used as sheet name in HouseholdData.xlsx and TripRateData.xlsx) | `Downtown` |
| `xLocation_ft` | number | Zone centroid x-coordinate [ft] in corridor coordinate system | `3960` |
| `yLocation_ft` | number | Zone centroid y-coordinate [ft] | `0` |
| `PeakArrive_hr` | number | Peak arrival hour [1–24] | `8` |
| `SigmaArrive_hr` | number | Arrival peak spread [hours] | `2` |
| `PeakDepart_hr` | number | Peak departure hour [1–24] | `17` |
| `SigmaDepart_hr` | number | Departure peak spread [hours] | `2` |

> **Tip:** Boundary zones (representing the external network, e.g., "NorthBoundary") should have coordinates outside the modeled corridor and peak hours matching MDOT's observed peak direction.

### Sheet: AccessPoints

One row per access-point–road combination. A TAZ can have multiple access points on the same road (e.g., two driveways).

| Column | Type | Description | Example |
|---|---|---|---|
| `TazIndex` | integer | 1-based zone index (row number in Zones sheet) | `1` |
| `RoadName` | text | Must match `Name` in corridor_config.xlsx | `Main St Northbound` |
| `XLocal_ft` | number | Driveway position along road [ft] | `1320` |
| `Split` | number | Fraction of this TAZ's road volume at this driveway; all rows for same (TAZ, Road) pair must sum to 1.0 | `0.6` |
| `AccessPointName` | text | Descriptive label (shown in plots) | `North Driveway` |

### Sheet: Intersections

One row per road end that connects to an intersection (boundary_idx = 0 in corridor_config.xlsx).

| Column | Type | Description | Example |
|---|---|---|---|
| `RoadName` | text | Road with the intersection boundary | `Cross St Eastbound` |
| `XLocal_ft` | number | Intersection location along road [ft] | `0` |
| `ExternalTazIndices` | text | Comma-separated TAZ indices that supply/receive traffic at this intersection | `4,5` |

### Sheets: ODAccess_Depart, ODAccess_Depart_NB, ODAccess_Depart_EB, ODAccess_Depart_WB

One sheet per road (sheet suffix matches direction abbreviation or road order in `corridor_config.xlsx`). Each sheet is a square Nzones × Nzones binary matrix.

- **Row i, Column j = 1** means trips from zone i to zone j use this road.
- Diagonal = 0 (no intra-zonal auto trips).
- Row/column headers should be zone names (first row = header, first column = header).

> **Example:** For a northbound arterial, zones south of an access point depart northward (row = 1) while zones north of it arrive from the south (column = 1). Draw a simple OD connectivity sketch before filling in the matrix.

### Sheet: QuickTune

One row per boundary calibration knob. Typical setup: one `_in` and one `_out` entry per road.

| Column | Type | Description | Example |
|---|---|---|---|
| `Key` | text | Unique key matching pattern `{DirectionAbbrev}_{in\|out}` | `NB_in` |
| `ScaleFactor` | number | Multiplier applied to boundary OD flow (1.0 = no change) | `1.0` |

---

## Step 3 — truth_data.xlsx

Provides MDOT AADT and observed hourly distributions for calibration comparison.

### One sheet per road (sheet name = corridor `Name`)

| Column | Type | Description |
|---|---|---|
| `Hour` | integer | Hour index 1–24 |
| `AADT` | number | Annual Average Daily Traffic [veh/day] (same value in every row) |
| `HourlyFraction` | number | Fraction of daily traffic in this hour (all 24 rows must sum to 1.0) |

> **If AADT data is unavailable:** Enter the best available count and set HourlyFraction to 1/24 for all hours. The model will still run; the tuning report will show large errors, indicating calibration is needed.

---

## Step 4 — HouseholdData.xlsx

Provides household cross-classification data for trip production (Step 1a).

### One sheet per zone (sheet name = `ZoneName` from taz_config.xlsx)

The sheet is a matrix where:
- **Rows** = household size categories (e.g., 1-person, 2-person, 3-person, 4+ person)
- **Columns** = auto-ownership categories (e.g., 0-car, 1-car, 2-car, 3+-car)
- **Values** = number of households in that cell

**Include a "Totals" row at the bottom and a "Totals" column on the right** — the engine automatically strips the last row and column, so the totals are not included in the calculation.

> **Data source:** ACS 5-Year Estimates Table B08201 (household size by vehicle availability) or local MPO household survey. Boundary zones (e.g., NorthBoundary) typically have small household counts representing through-trip generators.

---

## Step 5 — TripRateData.xlsx

Provides trip rate tables and attraction parameters.

### Zone sheets (same names as HouseholdData.xlsx)

Same row/column structure as HouseholdData.xlsx. Values are **daily person-trip rates per household** for each auto-ownership / household-size category.

> **Source:** NCHRP 716 Exhibit 4-2 or locally calibrated rates from the MPO travel demand model.

### Sheet: AttractionParameters

One row per zone. Columns must be `Employment`, `Enrollment`, `RetailArea_sqft`.

| Column | Type | Description | Example |
|---|---|---|---|
| `Employment` | number | Number of jobs in the zone | `1200` |
| `Enrollment` | number | Student enrollment (or 0 if not applicable) | `8500` |
| `RetailArea_sqft` | number | Retail gross floor area [sqft] | `45000` |

Row labels (first column) should be zone names matching the sheet names.

---

## Step 6 — scenario_config.xlsx (optional)

Defines named scenarios as parameter overrides on the base configuration.

### Sheet: ScenarioList

| Column | Type | Description |
|---|---|---|
| `ScenarioName` | text | Unique scenario identifier (no spaces recommended) |
| `BaseProject` | text | Project folder name this scenario is based on |
| `Description` | text | Human-readable description shown in the dashboard |

### Sheet: SignalOverrides

| Column | Type | Description |
|---|---|---|
| `ScenarioName` | text | Matches ScenarioList |
| `RoadName` | text | Matches corridor_config.xlsx Name |
| `Green_s` | number | Override green time [s] |
| `Red_s` | number | Override red time [s] |
| `Qsat_per_lane_vehsperlane` | number | Override saturation flow [veh/s/lane] |

### Sheet: LandUseOverrides

| Column | Type | Description |
|---|---|---|
| `ScenarioName` | text | |
| `ZoneName` | text | Matches taz_config.xlsx |
| `Employment` | number | Override employment count |
| `Enrollment` | number | Override enrollment |
| `RetailArea_sqft` | number | Override retail area |

### Sheet: ModeSplitOverrides

| Column | Type | Description |
|---|---|---|
| `ScenarioName` | text | |
| `ZoneName` | text | |
| `AutoShare` | number | Per-zone fraction of trips by auto [0–1] |

### Sheet: QuickTuneOverrides

| Column | Type | Description |
|---|---|---|
| `ScenarioName` | text | |
| `Key` | text | QuickTune key (matches taz_config.xlsx QuickTune sheet) |
| `ScaleFactor` | number | Override scale factor |

---

## Step 7 — First Run and Calibration

### 7.1 Fast check (demand-only, < 1 s)

```bash
python run_simulation.py --project projects/YourProject --mode demand_only
```

Read the console output:
- **4-Step Demand Model Summary** — verify production and attraction totals are reasonable
- **Boundary Tuning Report** — note the `Error%` column for each boundary
- **TAZ Temporal Parameter Recommendations** — note recommended peak hours and sigmas

### 7.2 Calibrate boundary volumes (QuickTune)

In `taz_config.xlsx`, sheet `QuickTune`, set each `ScaleFactor` to the `Rec. Scale` value from the tuning report. Re-run demand_only and iterate until errors are < 5%.

### 7.3 Calibrate temporal profiles

Update `PeakArrive_hr`, `SigmaArrive_hr`, `PeakDepart_hr`, `SigmaDepart_hr` in the Zones sheet of `taz_config.xlsx` to match the recommendations. Re-run.

### 7.4 Full simulation

```bash
python run_simulation.py --project projects/YourProject --mode full
```

Review the space-time diagram and boundary flow plots. A well-calibrated model should produce simulated boundary flows within 10–15% of MDOT truth across most hours.

### 7.5 Dashboard

```bash
streamlit run dashboard/app.py
```

Select your project from the sidebar dropdown.

---

## Common Issues

| Symptom | Likely cause | Fix |
|---|---|---|
| `KeyError: 'ZoneName'` when loading taz_config | Sheet column name typo | Check exact spelling and case in column headers |
| Zero flows everywhere | ODAccess matrix is all zeros | Verify at least one 1 in each ODAccess sheet for boundary zones |
| Demand model `P = 0` for a zone | HouseholdData sheet name doesn't match ZoneName | Zone names must match exactly |
| Simulation runs but density explodes | CFL violated | Reduce speed or increase Δx (edit `sim['dx']` in `run_simulation.py`) |
| Signal not taking effect | SignalX_ft is outside corridor length | Check corridor Length_ft vs SignalX_ft |

---

## Worked Example — Hypothetical "Oak Ave Corridor"

A two-road corridor: Oak Ave Northbound (NB) and Oak Ave Southbound (SB), each 1 mile (5 280 ft), with three TAZs (CommercialDistrict, ResidentialArea, NorthExternalBoundary) and a signalized intersection at x = 3 500 ft.

**corridor_config.xlsx → Corridors sheet:**

| Name | Idx | Length_ft | BoundaryIdx_In | BoundaryIdx_Out |
|---|---|---|---|---|
| Oak Ave Northbound | 1 | 5280 | 2 | 3 |
| Oak Ave Southbound | 2 | 5280 | 3 | 2 |

**corridor_config.xlsx → Signals sheet:**

| CorridorName | SignalX_ft | Green_s | Red_s | Qsat_per_lane_vehsperlane |
|---|---|---|---|---|
| Oak Ave Northbound | 3500 | 55 | 65 | 0.528 |
| Oak Ave Southbound | 3500 | 55 | 65 | 0.528 |

**taz_config.xlsx → Zones sheet:**

| ZoneName | xLocation_ft | yLocation_ft | PeakArrive_hr | SigmaArrive_hr | PeakDepart_hr | SigmaDepart_hr |
|---|---|---|---|---|---|---|
| CommercialDistrict | 2640 | 0 | 9 | 2 | 17 | 2 |
| ResidentialArea | 1320 | 500 | 7 | 1.5 | 16 | 2 |
| NorthExternalBoundary | -5000 | 0 | 16 | 4 | 16 | 4 |

For full worked data, see the UM-Dearborn reference project at `projects/UM_Dearborn/`.
