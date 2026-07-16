# UM-Dearborn Project

This folder contains all project-specific inputs for the University of Michigan–Dearborn
corridor study — the reference/demo case for the simulation platform.

## Contents

| File / Folder | Description |
|---------------|-------------|
| `corridor_config.xlsx` | Road geometry, lane counts, signal timing, speed limits (one row per corridor) |
| `taz_config.xlsx` | TAZ centroids, temporal profiles, access points, intersections, OD-access matrices, QuickTune factors |
| `HouseholdData.xlsx` | Household cross-classification data by TAZ (one sheet per zone) |
| `TripRateData.xlsx` | Trip production rates and attraction parameters by TAZ |
| `evergreen_sb.py` … | Archived corridor constructors (Sub-Task 1 — replaced by universal initializer) |

## How to run

From the repo root:

```bash
python run_simulation.py --project projects/UM_Dearborn --mode full
```

## Config file schemas

### corridor_config.xlsx

- **Corridors** sheet: `Name`, `Idx`, `Length_ft`, `BoundaryIdx_In`, `BoundaryIdx_Out`
- **LaneSegments** sheet: `CorridorName`, `XStart_ft`, `XEnd_ft`, `NLanes`
- **SpeedSegments** sheet: `CorridorName`, `XStart_ft`, `XEnd_ft`, `Speed_mph`
- **Signals** sheet: `CorridorName`, `SignalX_ft`, `Green_s`, `Red_s`, `Qsat_per_lane_vehsperlane`
- **QuickTune** sheet: `Key`, `ScaleFactor`, `Description`

### taz_config.xlsx

- **Zones** sheet: `ZoneName`, `xLocation_ft`, `yLocation_ft`, `PeakArrive_hr`, `SigmaArrive_hr`, `PeakDepart_hr`, `SigmaDepart_hr`
- **AccessPoints** sheet: `TazIndex`, `RoadName`, `XLocal_ft`, `Split`, `AccessPointName`
- **Intersections** sheet: `RoadName`, `XLocal_ft`, `ExternalTazIndices` (comma-separated 1-based)
- **ODAccess_Depart / _NB / _EB / _WB** sheets: 6×6 binary matrices (origin rows × destination columns)
