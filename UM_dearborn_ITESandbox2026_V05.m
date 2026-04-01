% ====================================================================
%% ITE Sandbox Competition 2026: University of Michigan - Dearborn
% ====================================================================
clear; close all; clc;
% ====================================================================
% DESCRIPTION:
% The model develops a macroscopic network flow model of traffic of an
% arterial road running North-South along the length of the University
% of Michigan - Dearborn. The model supports scenario testing for 
% operational and policy interventions.
%
% Source and sink flows at access points and boundaries are derived from
% the 4-step travel demand model (NCHRP 716) using:
%   Step 1 - Trip Generation: cross-classification (productions) and
%            linear land-use model (attractions)
%   Step 2 - Trip Distribution: singly-constrained gravity model
%   Step 3 - Mode Choice: average vehicle occupancy factor
%   Step 4 - Network Loading: OD flows mapped to corridor source/sinks
% ====================================================================
% RELEASE VERSION - USER GUIDE:
% 1. Only edit sections labeled "USER INPUT"
% 2. Do not edit solver or helper functions
% 3. All units are specified next to variables
% 4. This model is intended for planning-level analysis
% ====================================================================
%% ================ USER INPUTS (EDIT HERE) ==========================
% ====================================================================
%% Configure Simulation Settings (User Input)
sim.dt      = 1;                 % [s] time step
sim.dx      = 500;               % [ft] spatial cell length
sim.T_end   = 24*3600;           % [s] total simulation time
sim.t = 0:sim.dt:sim.T_end;                     % time vector
sim.Nt = numel(sim.t);                          % time vector length
sim.mph_to_fts = 5280/3600;                     % unit conversion
sim.mode = 'full'; % 'demand_only' = skip LWR solver (fast calibration) | 'full' = run simulation
fprintf('Done setting up simulation...\n')

%% Quick Tune: Manual Boundary Scale Factors (User Input)
% Multiply each OD model boundary flow by the factor below WITHOUT
% changing the spreadsheets.  Run once with all 1.0, read the
% "Rec. Scale" column in the console Boundary Tuning Report, then paste
% those values here and re-run — the report will confirm residual error.
%
%   Road  Dir   Boundary TAZ driven by this factor
%   SB    In    NorthBoundary departures onto Evergreen SB
%   SB    Out   SouthBoundary arrivals from  Evergreen SB
%   NB    In    SouthBoundary departures onto Evergreen NB
%   NB    Out   NorthBoundary arrivals from  Evergreen NB
%   EB    In    Intersection departures onto Hubbard EB
%   EB    Out   EastBoundary  arrivals from  Hubbard EB
%   WB    In    EastBoundary  departures onto Hubbard WB
%   WB    Out   Intersection  arrivals from  Hubbard WB
QUICKTUNE.SB_in  = 1.0;
QUICKTUNE.SB_out = 1.0;
QUICKTUNE.NB_in  = 1.2;
QUICKTUNE.NB_out = 1.2;
QUICKTUNE.EB_in  = 2.5;
QUICKTUNE.EB_out = 2.1;
QUICKTUNE.WB_in  = 1.3;
QUICKTUNE.WB_out = 1.3;

%% Configure Fundamental Diagram (User Input)
FD.model = "Greenshields";  % only one model currently supported
FD.rho_j = 1/18;            % [veh/ft/lane] jamming density
FD.rho_c = FD.rho_j/2;      % [veh/ft] critical density
FD.Q = @(rho, vf) vf .* rho .* (1 - rho/FD.rho_j);

%% Configure Road Geometry (User Input)
evergreenRdSouthbound = EvergreenRdSouthbound(sim, FD);
evergreenRdNorthbound = EvergreenRdNorthbound(sim, FD);
hubbardRdEastbound = HubbardRdEastbound(sim, FD);
hubbardRdWestbound = HubbardRdWestbound(sim,FD);
fprintf('Done configuring road geometry...\n')

%% Configure TAZs (User Input)
TAZ.names = {'MainCampus',    'ShoppingCenter', 'StudentHousing', ...
             'NorthBoundary', 'SouthBoundary',  'EastBoundary'};

% Coordinate Frame Definition:
% Global: 2D
% x = 0 ft is the NORTH end of Evergreen Rd; x = 6500 ft is the SOUTH end of Evergreen Road.
% y = 0 ft is the WEST end of Hubbard Rd; y = 4500 ft is the EAST end of Hubbard Rd. (Hubbard Rd does not exist in sim yet)
% Local: 1D
% x = 0 ft at the local roadways' inflow boundary and x = road.length at the local roadways' outflow boundary
% Approximate zone centroid position [ft]
% A TAZ can either belong along a corridor making it a source/sink or can be outside of a corridor making it a boundaryZones beyond the corridor are boundaries: NorthBoundary has x < 0, SouthBoundary has x > road.length.
%           key: [Campus, Shop, StudHsg,  North,  South,  East]
TAZ.xLocation  = [  3500, 6000,    2000, -10000,  16500,  2000]; % [ft]
% Off-corridor lateral offset for zones not on the main road axis [ft]
%           key: [Campus, Shop, StudHsg, North,   South,  East]
TAZ.yLocation = [      0,    0,    1900,      0,      0, 14500];  % [ft]
% Note: the west end of the east-west corridor terminates at the north-south corridor
% Each TAZ has an arrival peak (inbound) and departure peak (outbound)
% Arrivals effectively become sinks from the roadway's perspective
% Departures become sources from the roadway's perspective
TAZ.peak_arrive = [14, 14, 14, 16, 16, 14];      % [hour of day] arrival peak per TAZ
% [Strategic Class Scheduling] sigma increased to 6 on all TAZs to spread traffic volume over more time
TAZ.sigma_arrive = [6, 6, 6, 6, 6, 6];  % [hours] arrival peak spread per TAZ
TAZ.peak_depart = [14, 14, 14, 16, 16, 14];    % [hour of day] departure peak per TAZ
% [Strategic Class Scheduling] sigma increased to 6 on all TAZs to spread traffic volume over more time
TAZ.sigma_depart = [6, 6, 6, 6, 6, 6]; % [hours] departure peak spread per TAZ
% Convert daily vehicle volumes to hourly rates using parametric Gaussian peaks
% f_norm(h) = fraction of daily traffic in hour h  [24-element vector]
% Arrival and departure profiles are computed per TAZ
% Per-TAZ temporal profiles (parametricPeaks returns raw Gaussian; normalize)
Nzones = numel(TAZ.names);
TAZ.f_arrive = zeros(24, Nzones);
TAZ.f_depart = zeros(24, Nzones);
for k = 1:Nzones
    F_arr.w     = 1;
    F_arr.mu    = TAZ.peak_arrive(k);
    F_arr.sigma = TAZ.sigma_arrive(k);
    f_raw_arr   = parametricPeaks(F_arr);
    f_norm_arr  = f_raw_arr / sum(f_raw_arr); % normalize to fractional shares

    F_dep.w     = 1;
    F_dep.mu    = TAZ.peak_depart(k);
    F_dep.sigma = TAZ.sigma_depart(k);
    f_raw_dep   = parametricPeaks(F_dep);
    f_norm_dep  = f_raw_dep / sum(f_raw_dep);

    TAZ.f_arrive(:, k) = f_norm_arr(:);
    TAZ.f_depart(:, k) = f_norm_dep(:);
end

%% Setup Access Points for each TAZ and Intersection
% ---- Access Point Definitions ----
% These define driveway locations where vehicles enter/exit
% the arterial. A TAZ can be split between multiple access points.
% one entry per TAZ-road connection
TAZ.AccessPoints(1).taz_idx  = 1;                    % index into TAZ.names (MainCampus)
TAZ.AccessPoints(1).roadName = evergreenRdSouthbound.name;
% [Valleyview Dr Roundabout] removed access at 5400 ft; [Lone Oak Dr Roundabout] removed access at 3200 ft
% Remaining splits renormalized: original [0.10, 0.60, 0.20, 0.10] → keep indices 1 and 3 → [0.10, 0.20] → /0.30
TAZ.AccessPoints(1).xLocal   = [1700, 4500]; % [ft] in road-local coords
TAZ.AccessPoints(1).split    = [1/3, 2/3];   % must sum to 1.0
TAZ.AccessPoints(1).name     = ["University Secondary Entrance 1", ...
               "University Tertiary Entrance"];

TAZ.AccessPoints(2).taz_idx  = 1;                    % MainCampus on the NB road
TAZ.AccessPoints(2).roadName = evergreenRdNorthbound.name;
% [Valleyview Dr Roundabout] removed access at 1100 ft; [Lone Oak Dr Roundabout] removed access at 2000 ft
% Remaining splits renormalized: original [0.10, 0.20, 0.60, 0.10] → keep indices 3 and 4 → [0.60, 0.10] → /0.70
TAZ.AccessPoints(2).xLocal   = [3300, 4800];
TAZ.AccessPoints(2).split    = [6/7, 1/7];   % must sum to 1.0
TAZ.AccessPoints(2).name     = ["University Tertiary Entrance", ...
               "University Secondary Entrance 2"];

TAZ.AccessPoints(3).taz_idx  = 2;
TAZ.AccessPoints(3).roadName = evergreenRdSouthbound.name;
TAZ.AccessPoints(3).xLocal   = 6000;
TAZ.AccessPoints(3).split    = 1;
TAZ.AccessPoints(3).name     = "Shopping Center";

TAZ.AccessPoints(4).taz_idx  = 2;
TAZ.AccessPoints(4).roadName = evergreenRdNorthbound.name;
TAZ.AccessPoints(4).xLocal   = 500;
TAZ.AccessPoints(4).split    = 1;
TAZ.AccessPoints(4).name     = "Shopping Center";
fprintf('Done configuring TAZs...\n')

TAZ.AccessPoints(5).taz_idx  = 3;
TAZ.AccessPoints(5).roadName = hubbardRdEastbound.name;
TAZ.AccessPoints(5).xLocal   = [1200 3000];
TAZ.AccessPoints(5).split    = [0.75 0.25];
TAZ.AccessPoints(5).name     = "Student Housing";

TAZ.AccessPoints(6).taz_idx  = 3;
TAZ.AccessPoints(6).roadName = hubbardRdWestbound.name;
TAZ.AccessPoints(6).xLocal   = [1500 3300];
TAZ.AccessPoints(6).split    = [0.25 0.75];
TAZ.AccessPoints(6).name     = "Student Housing";
fprintf('Done configuring TAZs...\n')

% ---- Intersection Point Definitions ----
% These define locations where vehicles enter/exit the arterial at an 
% intersection. An intersection connection is split between 2 possible
% road choices, assuming no u-turns and a T-intersection.
% one entry per road at intersection
intersection(1).roadName = evergreenRdSouthbound.name;
intersection(1).xLocal = 2100;
intersection(1).taz_idx_external = [3,6]; % TAZ's not located on the coridor that must pass through the intersection

intersection(2).roadName = evergreenRdNorthbound.name;
intersection(2).xLocal = 4400;
intersection(2).taz_idx_external = [3,6]; % TAZ's not located on the coridor that must pass through the intersection

intersection(3).roadName = hubbardRdEastbound.name;
intersection(3).xLocal = 0;
intersection(3).taz_idx_external = [1,4,5]; % TAZ's not located on the coridor that must pass through the intersection

intersection(4).roadName = hubbardRdWestbound.name;
intersection(4).xLocal = 4400;
intersection(4).taz_idx_external = [1,4,5]; % TAZ's not located on the coridor that must pass through the intersection

%% Map TAZ Access Points and Intersections to Road Segments
evergreenRdSouthbound = mapAccessPoints(evergreenRdSouthbound, TAZ);
evergreenRdSouthbound = mapIntersectionPoints(evergreenRdSouthbound, intersection);
evergreenRdNorthbound = mapAccessPoints(evergreenRdNorthbound, TAZ);
evergreenRdNorthbound = mapIntersectionPoints(evergreenRdNorthbound, intersection);
hubbardRdEastbound = mapIntersectionPoints(hubbardRdEastbound, intersection);
hubbardRdEastbound = mapAccessPoints(hubbardRdEastbound, TAZ);
hubbardRdWestbound = mapIntersectionPoints(hubbardRdWestbound, intersection);
hubbardRdWestbound = mapAccessPoints(hubbardRdWestbound, TAZ);

%% Load (4-Step) Classic Traffic Demand Model
classicTrafficDemandModel = ClassicTrafficDemandModel(TAZ);
fprintf('Done loading 4-step model...\n')

%% Apply Quick Tune Scale Factors to OD Model Boundary Flows
% Save unscaled copy for the console report, then apply QUICKTUNE multipliers
% to the specific road-TAZ entries that drive each boundary flow.
qt_raw = classicTrafficDemandModel; % unscaled reference (used in report only)

classicTrafficDemandModel.V_taz_depart(1, 4) = classicTrafficDemandModel.V_taz_depart(1, 4) * QUICKTUNE.SB_in;
classicTrafficDemandModel.V_taz_arrive(1, 5) = classicTrafficDemandModel.V_taz_arrive(1, 5) * QUICKTUNE.SB_out;

classicTrafficDemandModel.V_taz_depart(2, 5) = classicTrafficDemandModel.V_taz_depart(2, 5) * QUICKTUNE.NB_in;
classicTrafficDemandModel.V_taz_arrive(2, 4) = classicTrafficDemandModel.V_taz_arrive(2, 4) * QUICKTUNE.NB_out;

for k_qt = intersection(3).taz_idx_external
    classicTrafficDemandModel.V_taz_depart(3, k_qt) = classicTrafficDemandModel.V_taz_depart(3, k_qt) * QUICKTUNE.EB_in;
end
classicTrafficDemandModel.V_taz_arrive(3, 6) = classicTrafficDemandModel.V_taz_arrive(3, 6) * QUICKTUNE.EB_out;

classicTrafficDemandModel.V_taz_depart(4, 6) = classicTrafficDemandModel.V_taz_depart(4, 6) * QUICKTUNE.WB_in;
for k_qt = intersection(4).taz_idx_external
    classicTrafficDemandModel.V_taz_arrive(4, k_qt) = classicTrafficDemandModel.V_taz_arrive(4, k_qt) * QUICKTUNE.WB_out;
end
fprintf('Done applying Quick Tune scale factors...\n')

%% Load Truth Data To Support Model Tuning
evergreenRdSouthbound.Truth = MdotTruthData(evergreenRdSouthbound.name);
evergreenRdNorthbound.Truth = MdotTruthData(evergreenRdNorthbound.name);
hubbardRdEastbound.Truth = MdotTruthData(hubbardRdEastbound.name);
hubbardRdWestbound.Truth = MdotTruthData(hubbardRdWestbound.name);
fprintf('Done loading MDOT data...\n')

% ====================================================================
%% ====================== Sim Solver Loop ============================
% All roads advance in parallel within a single time loop.
% Road segment loops are independent and uncoupled.
% ====================================================================
if strcmp(sim.mode, 'full')
% Extract state matrices before loop to avoid copy-on-write overhead
rho_SB = evergreenRdSouthbound.rho;   F_SB    = evergreenRdSouthbound.F;
F_SB_desired = evergreenRdSouthbound.F_desired;
g_SB   = evergreenRdSouthbound.g;     g_eff_SB = evergreenRdSouthbound.g_eff;
s_SB   = evergreenRdSouthbound.s;
evergreenRdSouthbound = rmfield(evergreenRdSouthbound, {'rho','F', 'F_desired','g','g_eff','s'});

rho_NB = evergreenRdNorthbound.rho;   F_NB    = evergreenRdNorthbound.F;
F_NB_desired = evergreenRdNorthbound.F_desired;
g_NB   = evergreenRdNorthbound.g;     g_eff_NB = evergreenRdNorthbound.g_eff;
s_NB   = evergreenRdNorthbound.s;
evergreenRdNorthbound = rmfield(evergreenRdNorthbound, {'rho','F', 'F_desired','g','g_eff','s'});

rho_EB = hubbardRdEastbound.rho;   F_EB    = hubbardRdEastbound.F;
F_EB_desired = hubbardRdEastbound.F_desired;
g_EB   = hubbardRdEastbound.g;     g_eff_EB = hubbardRdEastbound.g_eff;
s_EB   = hubbardRdEastbound.s;
hubbardRdEastbound = rmfield(hubbardRdEastbound, {'rho','F', 'F_desired','g','g_eff','s'});

rho_WB = hubbardRdWestbound.rho;   F_WB    = hubbardRdWestbound.F;
F_WB_desired = hubbardRdWestbound.F_desired;
g_WB   = hubbardRdWestbound.g;     g_eff_WB = hubbardRdWestbound.g_eff;
s_WB   = hubbardRdWestbound.s;
hubbardRdWestbound = rmfield(hubbardRdWestbound, {'rho','F', 'F_desired','g','g_eff','s'});

fprintf('==================\n')
fprintf('\n BEGIN SIMULATION \n')
fprintf('==================\n')
sim_tic = tic;
for n = 1:sim.Nt-1
    sim.n = n;
    sim.h = hourIndex(sim.t(n));
    if mod(n-1, 3600) == 0
        fprintf('Sim Hour: %2d / 24  (wall time: %.1f s)\n', sim.h, toc(sim_tic))
    end
    %% Road 1 (Southbound) — x=0 at North, x=6500 at South
    % ----------------------------------------------------------------
    [rho_SB(:,n+1), F_SB(:,n), F_SB_desired(:,n), g_SB(n), g_eff_SB(:,n), s_SB(:,n)] = ...
        LWRModel(evergreenRdSouthbound, rho_SB(:,n), classicTrafficDemandModel, TAZ, sim);

    %% Road 2 (Northbound) — x=0 at South, x=6500 at North
    % ----------------------------------------------------------------
    [rho_NB(:,n+1), F_NB(:,n), F_NB_desired(:,n), g_NB(n), g_eff_NB(:,n), s_NB(:,n)] = ...
        LWRModel(evergreenRdNorthbound, rho_NB(:,n), classicTrafficDemandModel, TAZ, sim);

    %% Road 3 (Eastbound) — x=0 at West, x=6500 at East
    % ----------------------------------------------------------------
    [rho_EB(:,n+1), F_EB(:,n), F_EB_desired(:,n), g_EB(n), g_eff_EB(:,n), s_EB(:,n)] = ...
        LWRModel(hubbardRdEastbound, rho_EB(:,n), classicTrafficDemandModel, TAZ, sim);

    %% Road 4 (Westbound) — x=0 at East, x=6500 at West
    % ----------------------------------------------------------------
    [rho_WB(:,n+1), F_WB(:,n), F_WB_desired(:,n), g_WB(n), g_eff_WB(:,n), s_WB(:,n)] = ...
        LWRModel(hubbardRdWestbound, rho_WB(:,n), classicTrafficDemandModel, TAZ, sim);
end
fprintf('Simulation complete. Wall time: %.1f s\n', toc(sim_tic))

% Restore state matrices to road structs for plotting
evergreenRdSouthbound.rho = rho_SB; evergreenRdSouthbound.F = F_SB;
evergreenRdSouthbound.F_desired = F_SB_desired;
evergreenRdSouthbound.g   = g_SB;   evergreenRdSouthbound.g_eff = g_eff_SB;
evergreenRdSouthbound.s   = s_SB;

evergreenRdNorthbound.rho = rho_NB; evergreenRdNorthbound.F = F_NB;
evergreenRdNorthbound.F_desired = F_NB_desired;
evergreenRdNorthbound.g   = g_NB;   evergreenRdNorthbound.g_eff = g_eff_NB;
evergreenRdNorthbound.s   = s_NB;

hubbardRdEastbound.rho = rho_EB; hubbardRdEastbound.F = F_EB;
hubbardRdEastbound.F_desired = F_EB_desired;
hubbardRdEastbound.g   = g_EB;   hubbardRdEastbound.g_eff = g_eff_EB;
hubbardRdEastbound.s   = s_EB;
% Note: Hubbard East Bound eminates from the intersection and has no
% boundary condition; therfore, the flow measured immediately after the
% intersection (seg. idx = 2) is taken as the boundary condition (seg. idx = 1) 
% for tuning visualization.
hubbardRdEastbound.F(1,:) = F_EB(2,:);

hubbardRdWestbound.rho = rho_WB; hubbardRdWestbound.F = F_WB;
hubbardRdWestbound.F_desired = F_WB_desired;
hubbardRdWestbound.g   = g_WB;   hubbardRdWestbound.g_eff = g_eff_WB;
hubbardRdWestbound.s   = s_WB;

% Note F_desired exceptions for Hubbard Rd; must manually
% assign due to intersection dynamics
evergreenRdSouthboundTemporal = evergreenRdSouthbound.F(1,:)./sum(evergreenRdSouthbound.F(1,:));
evergreenRdNorthboundTemporal = evergreenRdNorthbound.F(1,:)./sum(evergreenRdNorthbound.F(1,:));
average_temporal_factor = (evergreenRdSouthboundTemporal+evergreenRdNorthboundTemporal)./sum(evergreenRdSouthboundTemporal+evergreenRdNorthboundTemporal);
hubbardRdEastbound.F_desired(1,:) = average_temporal_factor...
        .*sum(classicTrafficDemandModel.V_taz_depart(3,intersection(3).taz_idx_external),'all');
hubbardRdWestbound.F_desired(2,:) = average_temporal_factor...
        .*sum(classicTrafficDemandModel.V_taz_arrive(4,intersection(4).taz_idx_external),'all');
end % if strcmp(sim.mode, 'full')

% ====================================================================
%% ====================== PLOT CONTROLS (USER INPUT) ================
% ====================================================================
% Toggle each plot group on (true) or off (false).
% NOTE: demand_boundary works in both modes.
%       tuning_boundary and tuning_conservation require sim.mode = 'full'.
%       All other plots require sim.mode = 'full'.
plots.demand_boundary     = true;   % Hourly OD boundary profile vs MDOT truth (demand_only safe)
plots.tuning_boundary     = false;  % Hourly sim boundary flow vs MDOT truth (requires 'full')
plots.tuning_conservation = false;  % Daily trip conservation summary (requires 'full')
plots.space_time          = true;  % Space-time density diagrams
plots.signal_timing       = false;  % Signal phase space-time diagrams
plots.source_sink         = false;  % Net source/sink time series at access points
plots.od_matrix           = true;  % OD matrix heatmap
plots.road_geometry       = true;  % Road geometry with lane widths and access points

% Road filter — applies to space_time, signal_timing, source_sink, road_geometry only.
% tuning_boundary and tuning_conservation always cover all roads.
plots.road_SB = true;
plots.road_NB = true;
plots.road_EB = true;
plots.road_WB = true;

%% Plot Formatting (User Input)
% Controls figure appearance and PNG export.  Sizes are in inches so that
% exported PNGs have predictable physical dimensions at the chosen DPI.
% -----------------------------------------------------------------------
% Typography
plotfmt.font        = 'Times New Roman';    % typeface ('Arial', 'Times New Roman', etc.)
plotfmt.sgtitle_fs  = 42;         % super-title (sgtitle) font size [pt]
plotfmt.title_fs    = 36;         % subplot title font size [pt]
plotfmt.label_fs    = 36;         % axis label (xlabel/ylabel) font size [pt]
plotfmt.tick_fs     = 36;          % tick label font size [pt]
plotfmt.legend_fs   = 36;          % legend font size [pt]
% Lines
plotfmt.lw          = 1.5;        % data line width [pt]
plotfmt.ms          = 4;          % marker size [pt]
% Axes appearance
plotfmt.ax_box      = 'on';       % 'on' | 'off' — axis border box
plotfmt.tick_dir    = 'in';       % 'in' | 'out' — tick direction
plotfmt.ax_lw       = 0.75;       % axes border line width [pt]
% Figure sizes  [width, height]  in inches
plotfmt.sz_wide     = [12.0, 4.5]; % 1x3 subplots  (demand boundary)
plotfmt.sz_tall     = [14.0, 6.5]; % 2x3 subplots  (boundary tuning)
plotfmt.sz_half     = [10.0, 4.0]; % 1x2 subplots  (trip conservation)
plotfmt.sz_single   = [ 7.0, 5.0]; % single axes   (space-time, OD matrix)
plotfmt.sz_stack    = [ 7.0, 8.0]; % stacked panels (source/sink)
% PNG export
plotfmt.export      = false;       % true = auto-save each figure as PNG
plotfmt.dpi         = 300;         % export resolution [dots per inch]
plotfmt.export_dir  = 'figures';   % output folder (created automatically)

% ====================================================================
%% ======================== Plot Results =============================
% ====================================================================
% Apply report-grade MATLAB defaults for all figures in this session.
% These set the baseline; applyFigureFormat() refines sizes after creation.
set(groot, 'defaultAxesFontName',   plotfmt.font);
set(groot, 'defaultTextFontName',   plotfmt.font);
set(groot, 'defaultLineLineWidth',  plotfmt.lw);
set(groot, 'defaultLineMarkerSize', plotfmt.ms);

% Road lookup for loop-based plotting
all_roads    = {evergreenRdSouthbound, evergreenRdNorthbound, ...
                hubbardRdEastbound,    hubbardRdWestbound};
road_keys    = {'SB', 'NB', 'EB', 'WB'};
road_enabled = [plots.road_SB, plots.road_NB, plots.road_EB, plots.road_WB];
Nroads       = numel(all_roads);
pts_per_hr   = round(3600 / sim.dt);           % time steps per hour
Nhrs         = floor((sim.Nt-1) / pts_per_hr); % complete simulated hours
hrs          = 1:Nhrs;

%% Demand Model Console Summary
fprintf('\n========== 4-Step Demand Model Summary ==========\n');
fprintf('%-20s %10s %10s %10s\n', 'Zone', 'P [p-t/d]', 'A [p-t/d]', 'P-A');
for iz = 1:Nzones
    fprintf('%-20s %10.0f %10.0f %10.0f\n', ...
        TAZ.names{iz}, classicTrafficDemandModel.P(iz), classicTrafficDemandModel.A(iz), ...
        classicTrafficDemandModel.P(iz) - classicTrafficDemandModel.A(iz));
end
fprintf('%-20s %10.0f %10.0f\n', 'TOTAL', sum(classicTrafficDemandModel.P), sum(classicTrafficDemandModel.A));

%% Boundary Tuning Console Report (available in both modes)
% Columns: MDOT truth | Raw OD (unscaled) | QT scale applied | Scaled OD | Error% | Rec. Scale
% "Rec. Scale" is how much more you'd need to multiply to hit MDOT exactly.
% When QT scale = Rec. Scale from the previous run, Rec. Scale -> 1.000.
dm = classicTrafficDemandModel; % scaled (post Quick Tune) reference

fprintf('\n========== Boundary Tuning Report ==========\n')
fprintf('%-6s %-4s %-16s %10s %10s %9s %10s %8s %10s\n', ...
    'Road','Dir','Boundary TAZ','MDOT[v/d]','RawOD[v/d]','QT Scale','Scaled[v/d]','Error%','Rec.Scale')
fprintf('%s\n', repmat('-',1,90))

% [road_idx, direction, boundary_taz_idx (0=intersection), road_key, taz_label, qt_field_name]
bnd_cfg = { ...
    1, 'In',  4, 'SB', 'NorthBoundary', 'SB_in';  ...
    1, 'Out', 5, 'SB', 'SouthBoundary', 'SB_out'; ...
    2, 'In',  5, 'NB', 'SouthBoundary', 'NB_in';  ...
    2, 'Out', 4, 'NB', 'NorthBoundary', 'NB_out'; ...
    3, 'In',  0, 'EB', 'Intersection',  'EB_in';  ...
    3, 'Out', 6, 'EB', 'EastBoundary',  'EB_out'; ...
    4, 'In',  6, 'WB', 'EastBoundary',  'WB_in';  ...
    4, 'Out', 0, 'WB', 'Intersection',  'WB_out'  ...
};
for b = 1:size(bnd_cfg, 1)
    r        = bnd_cfg{b,1};
    dir      = bnd_cfg{b,2};
    taz      = bnd_cfg{b,3};
    rkey     = bnd_cfg{b,4};
    taz_lbl  = bnd_cfg{b,5};
    qt_field = bnd_cfg{b,6};
    road_b   = all_roads{r};
    mdot_daily  = sum(road_b.Truth.MDOT_inflow) * 3600;
    qt_applied  = QUICKTUNE.(qt_field);

    % Raw OD (before Quick Tune scaling)
    if strcmp(dir, 'In')
        if taz == 0
            raw_od = sum(qt_raw.V_taz_depart(r, intersection(r).taz_idx_external));
            od_daily = sum(dm.V_taz_depart(r, intersection(r).taz_idx_external));
        else
            raw_od   = qt_raw.V_taz_depart(r, taz);
            od_daily = dm.V_taz_depart(r, taz);
        end
    else
        if taz == 0
            raw_od   = sum(qt_raw.V_taz_arrive(r, intersection(r).taz_idx_external));
            od_daily = sum(dm.V_taz_arrive(r, intersection(r).taz_idx_external));
        else
            raw_od   = qt_raw.V_taz_arrive(r, taz);
            od_daily = dm.V_taz_arrive(r, taz);
        end
    end

    err_pct   = (od_daily - mdot_daily) / max(mdot_daily, 1) * 100;
    rec_scale = mdot_daily / max(od_daily, 1);  % multiply QT by this to hit MDOT
    fprintf('%-6s %-4s %-16s %10.0f %10.0f %9.3f %10.0f %7.1f%% %10.3f\n', ...
        rkey, dir, taz_lbl, mdot_daily, raw_od, qt_applied, od_daily, err_pct, rec_scale);
end
fprintf('\n  Tip: set QUICKTUNE.<field> = (current QT Scale) x (Rec. Scale) to converge.\n\n')

% Weighted-mean / sigma recommendations for TAZ temporal parameters
fprintf('========== TAZ Temporal Parameter Recommendations ==========\n')
fprintf('(from MDOT hourly distribution; use to set peak_depart/arrive and sigma)\n')
h_vec = (1:24)';
for r = 1:Nroads
    road_b   = all_roads{r};
    dist_in  = road_b.Truth.MDOT_inflow(:);   % [veh/s], 24-element
    dist_out = road_b.Truth.MDOT_outflow(:);
    if sum(dist_in) > 0
        mu_in    = sum(h_vec .* dist_in)  / sum(dist_in);
        sig_in   = sqrt(max(sum((h_vec - mu_in).^2  .* dist_in)  / sum(dist_in), 0));
        mu_out   = sum(h_vec .* dist_out) / sum(dist_out);
        sig_out  = sqrt(max(sum((h_vec - mu_out).^2 .* dist_out) / sum(dist_out), 0));
        fprintf('  %s: peak_arrive=%.1f h, sigma_arrive=%.1f h | peak_depart=%.1f h, sigma_depart=%.1f h\n', ...
            road_keys{r}, mu_in, sig_in, mu_out, sig_out);
    end
end
fprintf('\n')

% ====================================================================
%% Tuning: Hourly Boundary Flow vs MDOT Truth
% One figure per road; 2x3 subplot layout:
%   Row 1: inflow time series | outflow time series | daily totals bar
%   Row 2: inflow % error     | outflow % error     | daily % error bar
% ====================================================================
% ====================================================================
%% Demand-Only: Hourly OD Boundary Profile vs MDOT Truth
% Works in both 'demand_only' and 'full' modes.
% Shows the OD model's predicted hourly boundary profile vs MDOT data.
% ====================================================================
if plots.demand_boundary
    h_plot = 1:24;
    for r = 1:Nroads
        road_b = all_roads{r};

        % --- compute OD hourly inflow profile ---
        bnd_in_taz = road_b.boundary_idx(1);
        if bnd_in_taz == 0  % intersection side: sum over external TAZs
            od_in_hrly = zeros(24,1);
            for k = intersection(r).taz_idx_external
                od_in_hrly = od_in_hrly + dm.V_taz_depart(r,k) .* TAZ.f_depart(:,k);
            end
        else
            od_in_hrly = dm.V_taz_depart(r, bnd_in_taz) .* TAZ.f_depart(:, bnd_in_taz);
        end

        % --- compute OD hourly outflow profile ---
        bnd_out_taz = road_b.boundary_idx(2);
        if bnd_out_taz == 0  % intersection side
            od_out_hrly = zeros(24,1);
            for k = intersection(r).taz_idx_external
                od_out_hrly = od_out_hrly + dm.V_taz_arrive(r,k) .* TAZ.f_arrive(:,k);
            end
        else
            od_out_hrly = dm.V_taz_arrive(r, bnd_out_taz) .* TAZ.f_arrive(:, bnd_out_taz);
        end

        mdot_in_hrly  = road_b.Truth.MDOT_inflow  * 3600; % [veh/hr]
        mdot_out_hrly = road_b.Truth.MDOT_outflow * 3600;

        figure('Name',['demandBoundary_' road_keys{r}],'Color','w')
        sgtitle(['OD Boundary Profile vs MDOT: ' road_b.name], ...
                'FontSize',plotfmt.sgtitle_fs,'FontWeight','bold')

        % Inflow
        subplot(1,3,1); hold on
        bar(h_plot, mdot_in_hrly, 'FaceColor',[0.2 0.4 0.8],'FaceAlpha',0.5,'DisplayName','MDOT Truth')
        plot(h_plot, od_in_hrly, 'r-o','DisplayName','OD Model')
        hold off
        ylabel('Flow [veh/hr]'); xlabel('Hour of Day'); title('Inflow')
        grid on; legend('Location','northoutside'); xticks(0:6:24); xlim([0.5 24.5])

        % Outflow
        subplot(1,3,2); hold on
        bar(h_plot, mdot_out_hrly,'FaceColor',[0.2 0.7 0.3],'FaceAlpha',0.5,'DisplayName','MDOT Truth')
        plot(h_plot, od_out_hrly, 'r-o','DisplayName','OD Model')
        hold off
        ylabel('Flow [veh/hr]'); xlabel('Hour of Day'); title('Outflow')
        grid on; legend('Location','northoutside'); xticks(0:6:24); xlim([0.5 24.5])

        % Daily totals bar
        subplot(1,3,3)
        daily_mat = [sum(mdot_in_hrly), sum(mdot_out_hrly);
                     sum(od_in_hrly),   sum(od_out_hrly)];
        b_hdl = bar(categorical({'Inflow','Outflow'}), daily_mat');
        b_hdl(1).DisplayName = 'MDOT Truth'; b_hdl(1).FaceColor = [0.2 0.4 0.8];
        b_hdl(2).DisplayName = 'OD Model';   b_hdl(2).FaceColor = [0.9 0.3 0.3];
        ylabel('Vehicles [veh/day]'); title('Daily Volume')
        legend('Location','northoutside'); grid on

        applyFigureFormat(gcf, plotfmt.sz_wide, plotfmt);
        exportFigure(gcf, ['demandBoundary_' road_keys{r}], plotfmt);
    end
end

if plots.tuning_boundary && strcmp(sim.mode, 'full')
    Npts = Nhrs * pts_per_hr;
    for r = 1:Nroads
        road     = all_roads{r};
        has_mdot = any(road.Truth.MDOT_inflow > 0) || any(road.Truth.MDOT_outflow > 0);

        % Aggregate per-second flux to hourly vehicle counts [veh/hr]
        F_in_hrly      = sum(reshape(road.F(1,          1:Npts), pts_per_hr, Nhrs)) * sim.dt;
        F_in_des_hrly  = sum(reshape(road.F_desired(1,  1:Npts), pts_per_hr, Nhrs)) * sim.dt;
        F_out_hrly     = sum(reshape(road.F(road.Nx+1,  1:Npts), pts_per_hr, Nhrs)) * sim.dt;
        F_out_des_hrly = sum(reshape(road.F_desired(2,  1:Npts), pts_per_hr, Nhrs)) * sim.dt;
        if has_mdot
            mdot_in_hrly  = road.Truth.MDOT_inflow(1:Nhrs)  * 3600; % [veh/hr]
            mdot_out_hrly = road.Truth.MDOT_outflow(1:Nhrs) * 3600;
        end

        figure('Name',['boundaryTuning_' road_keys{r}],'Color','w')
        sgtitle(['Boundary Flow Tuning: ' road.name], ...
                'FontSize',plotfmt.sgtitle_fs,'FontWeight','bold')

        % (1,1) Upstream inflow — hourly
        subplot(2,3,1); hold on
        if has_mdot
            bar(hrs, mdot_in_hrly,'FaceColor',[0.2 0.4 0.8],'FaceAlpha',0.5,'DisplayName','MDOT Truth')
        end
        plot(hrs, F_in_des_hrly,'k--o','DisplayName','OD Desired')
        plot(hrs, F_in_hrly,    'r-o', 'DisplayName','Sim Actual')
        hold off
        ylabel('Flow [veh/hr]'); xlabel('Hour of Day'); title('Upstream Inflow')
        grid on; legend('Location','northwest'); xticks(hrs); xlim([0.5 Nhrs+0.5])
        set(gca,'XLim',[0 24],'XTick',1:6:24)

        % (1,2) Downstream outflow — hourly
        subplot(2,3,2); hold on
        if has_mdot
            bar(hrs, mdot_out_hrly,'FaceColor',[0.2 0.7 0.3],'FaceAlpha',0.5,'DisplayName','MDOT Truth')
        end
        plot(hrs, F_out_des_hrly,'k--o','DisplayName','OD Desired')
        plot(hrs, F_out_hrly,    'r-o', 'DisplayName','Sim Actual')
        hold off
        ylabel('Flow [veh/hr]'); xlabel('Hour of Day'); title('Downstream Outflow')
        grid on; legend('Location','northwest'); xticks(hrs); xlim([0.5 Nhrs+0.5])
        set(gca,'XLim',[0 24],'XTick',0:6:24)

        % (1,3) Daily volume summary bar
        subplot(2,3,3)
        if has_mdot
            daily_mat = [sum(mdot_in_hrly),   sum(mdot_out_hrly);
                         sum(F_in_des_hrly),  sum(F_out_des_hrly);
                         sum(F_in_hrly),       sum(F_out_hrly)];
            b = bar(categorical({'Inflow','Outflow'}), daily_mat');
            b(1).DisplayName = 'MDOT Truth'; b(1).FaceColor = [0.2 0.4 0.8];
            b(2).DisplayName = 'OD Desired'; b(2).FaceColor = [0.7 0.7 0.7];
            b(3).DisplayName = 'Sim Actual'; b(3).FaceColor = [0.9 0.3 0.3];
        else
            daily_mat = [sum(F_in_des_hrly), sum(F_out_des_hrly);
                         sum(F_in_hrly),      sum(F_out_hrly)];
            b = bar(categorical({'Inflow','Outflow'}), daily_mat');
            b(1).DisplayName = 'OD Desired'; b(1).FaceColor = [0.7 0.7 0.7];
            b(2).DisplayName = 'Sim Actual'; b(2).FaceColor = [0.9 0.3 0.3];
        end
        ylabel('Vehicles [veh/day]'); title('Daily Volume Summary')
        legend('Location','northeast'); grid on
        set(gca,'XLim',[0 24],'XTick',0:6:24)

        % (2,1) Inflow % error vs MDOT — hourly
        subplot(2,3,4)
        if has_mdot
            denom = max(mdot_in_hrly, 1);
            hold on
            bar(hrs, (F_in_des_hrly - mdot_in_hrly) ./ denom * 100, ...
                'FaceColor',[0.7 0.7 0.7],'FaceAlpha',0.7,'DisplayName','OD Desired')
            plot(hrs, (F_in_hrly - mdot_in_hrly) ./ denom * 100, ...
                'r-o','DisplayName','Sim Actual')
            yline(0,'k--','LineWidth',1)
            hold off
            ylabel('Error [%]'); xlabel('Hour of Day'); title('Inflow % Error vs MDOT')
            grid on; legend('Location','northeast'); xticks(hrs); xlim([0.5 Nhrs+0.5])
        else
            text(0.5,0.5,'No MDOT data','HorizontalAlignment','center', ...
                'Units','normalized'); axis off
        end

        % (2,2) Outflow % error vs MDOT — hourly
        subplot(2,3,5)
        if has_mdot
            denom = max(mdot_out_hrly, 1);
            hold on
            bar(hrs, (F_out_des_hrly - mdot_out_hrly) ./ denom * 100, ...
                'FaceColor',[0.7 0.7 0.7],'FaceAlpha',0.7,'DisplayName','OD Desired')
            plot(hrs, (F_out_hrly - mdot_out_hrly) ./ denom * 100, ...
                'r-o','DisplayName','Sim Actual')
            yline(0,'k--','LineWidth',1)
            hold off
            ylabel('Error [%]'); xlabel('Hour of Day'); title('Outflow % Error vs MDOT')
            grid on; legend('Location','northeast'); xticks(hrs); xlim([0.5 Nhrs+0.5])
        else
            text(0.5,0.5,'No MDOT data','HorizontalAlignment','center', ...
                'Units','normalized'); axis off
        end

        % (2,3) Daily % error summary
        subplot(2,3,6)
        if has_mdot
            vals = [(sum(F_in_des_hrly)  - sum(mdot_in_hrly))  / sum(mdot_in_hrly)  * 100, ...
                    (sum(F_in_hrly)      - sum(mdot_in_hrly))  / sum(mdot_in_hrly)  * 100, ...
                    (sum(F_out_des_hrly) - sum(mdot_out_hrly)) / sum(mdot_out_hrly) * 100, ...
                    (sum(F_out_hrly)     - sum(mdot_out_hrly)) / sum(mdot_out_hrly) * 100];
            lbls = categorical({'In: Desired','In: Actual','Out: Desired','Out: Actual'}, ...
                               {'In: Desired','In: Actual','Out: Desired','Out: Actual'});
            b2 = bar(lbls, vals);
            b2.FaceColor = 'flat';
            b2.CData = [[0.7 0.7 0.7]; [0.9 0.3 0.3]; [0.7 0.7 0.7]; [0.9 0.3 0.3]];
            yline(0,'k--','LineWidth',1)
            ylabel('Daily Volume % Error vs MDOT'); title('Daily % Error Summary')
            grid on; xtickangle(15)
        else
            text(0.5,0.5,'No MDOT data','HorizontalAlignment','center', ...
                'Units','normalized'); axis off
        end

        applyFigureFormat(gcf, plotfmt.sz_tall, plotfmt);
        exportFigure(gcf, ['boundaryTuning_' road_keys{r}], plotfmt);
    end
end

% ====================================================================
%% Tuning: Daily Trip Conservation — All Roads
% Compares OD model desired daily volumes vs MDOT truth vs sim actual
% for each road's upstream and downstream boundaries.
% ====================================================================
if plots.tuning_conservation && strcmp(sim.mode, 'full')
    Npts = Nhrs * pts_per_hr;

    % Pre-compute daily totals for all roads
    daily_mdot_in  = zeros(1, Nroads);
    daily_des_in   = zeros(1, Nroads);
    daily_act_in   = zeros(1, Nroads);
    daily_mdot_out = zeros(1, Nroads);
    daily_des_out  = zeros(1, Nroads);
    daily_act_out  = zeros(1, Nroads);
    for r = 1:Nroads
        road = all_roads{r};
        daily_mdot_in(r)  = sum(road.Truth.MDOT_inflow(1:Nhrs))  * 3600;
        daily_des_in(r)   = sum(road.F_desired(1, 1:Npts)) * sim.dt;
        daily_act_in(r)   = sum(road.F(1,         1:Npts)) * sim.dt;
        daily_mdot_out(r) = sum(road.Truth.MDOT_outflow(1:Nhrs)) * 3600;
        daily_des_out(r)  = sum(road.F_desired(2, 1:Npts)) * sim.dt;
        daily_act_out(r)  = sum(road.F(road.Nx+1, 1:Npts)) * sim.dt;
    end

    % Console table
    fprintf('\n========== Daily Trip Conservation Summary ==========\n')
    fprintf('%-6s %12s %12s %12s %10s %10s\n', ...
        'Road','MDOT [veh]','OD Des [veh]','Sim Act [veh]','Err Des%','Err Act%')
    fprintf('--- Upstream Inflow ---\n')
    for r = 1:Nroads
        if daily_mdot_in(r) > 0
            fprintf('%-6s %12.0f %12.0f %12.0f %9.1f%% %9.1f%%\n', road_keys{r}, ...
                daily_mdot_in(r), daily_des_in(r), daily_act_in(r), ...
                (daily_des_in(r)-daily_mdot_in(r))/daily_mdot_in(r)*100, ...
                (daily_act_in(r)-daily_mdot_in(r))/daily_mdot_in(r)*100)
        else
            fprintf('%-6s %12s %12.0f %12.0f %10s %10s\n', ...
                road_keys{r},'N/A',daily_des_in(r),daily_act_in(r),'N/A','N/A')
        end
    end
    fprintf('--- Downstream Outflow ---\n')
    for r = 1:Nroads
        if daily_mdot_out(r) > 0
            fprintf('%-6s %12.0f %12.0f %12.0f %9.1f%% %9.1f%%\n', road_keys{r}, ...
                daily_mdot_out(r), daily_des_out(r), daily_act_out(r), ...
                (daily_des_out(r)-daily_mdot_out(r))/daily_mdot_out(r)*100, ...
                (daily_act_out(r)-daily_mdot_out(r))/daily_mdot_out(r)*100)
        else
            fprintf('%-6s %12s %12.0f %12.0f %10s %10s\n', ...
                road_keys{r},'N/A',daily_des_out(r),daily_act_out(r),'N/A','N/A')
        end
    end

    % Conservation figure — grouped bar charts for all roads
    figure('Name','tripConservation','Color','w')
    sgtitle('Daily Trip Conservation: OD Model vs MDOT Truth vs Simulation', ...
        'FontSize',plotfmt.sgtitle_fs,'FontWeight','bold')

    subplot(1,2,1)
    b = bar(categorical(road_keys), [daily_mdot_in; daily_des_in; daily_act_in]');
    b(1).DisplayName = 'MDOT Truth'; b(1).FaceColor = [0.2 0.4 0.8];
    b(2).DisplayName = 'OD Desired'; b(2).FaceColor = [0.7 0.7 0.7];
    b(3).DisplayName = 'Sim Actual'; b(3).FaceColor = [0.9 0.3 0.3];
    ylabel('Vehicles [veh/day]'); title('Upstream Inflow: Daily Total')
    legend('Location','northeast'); grid on
    set(gca,'XLim',[0 24],'XTick',0:6:24)

    subplot(1,2,2)
    b = bar(categorical(road_keys), [daily_mdot_out; daily_des_out; daily_act_out]');
    b(1).DisplayName = 'MDOT Truth'; b(1).FaceColor = [0.2 0.4 0.8];
    b(2).DisplayName = 'OD Desired'; b(2).FaceColor = [0.7 0.7 0.7];
    b(3).DisplayName = 'Sim Actual'; b(3).FaceColor = [0.9 0.3 0.3];
    ylabel('Vehicles [veh/day]'); title('Downstream Outflow: Daily Total')
    legend('Location','northeast'); grid on
    set(gca,'XLim',[0 24],'XTick',0:6:24)

    applyFigureFormat(gcf, plotfmt.sz_half, plotfmt);
    exportFigure(gcf, 'tripConservation', plotfmt);
end

% ====================================================================
%% Space-Time Density Diagrams
% ====================================================================
ite_colormap_full_res = 20;
ite_colormap_full_R1 = linspace(100,100,ite_colormap_full_res/2);
ite_colormap_full_R2 = linspace(100,234,ite_colormap_full_res/2+1);
ite_colormap_full_G1 = linspace( 38,167,ite_colormap_full_res/2);
ite_colormap_full_G2 = linspace(167,170,ite_colormap_full_res/2+1);
ite_colormap_full_B1 = flip(linspace(11,103,ite_colormap_full_res/2));
ite_colormap_full_B2 = flip(linspace(0,11,ite_colormap_full_res/2+1));
ite_colormap_full = zeros(20,3);
ite_colormap_full(:,1) = [ite_colormap_full_R1,ite_colormap_full_R2(2:end)]./255;
ite_colormap_full(:,2) = [ite_colormap_full_G1,ite_colormap_full_G2(2:end)]./255;
ite_colormap_full(:,3) = [ite_colormap_full_B1,ite_colormap_full_B2(2:end)]./255;

if plots.space_time
    for r = 1:Nroads
        if road_enabled(r)
            road = all_roads{r};
            figure('Name',['spaceTime_' road_keys{r}],'Color','w')
            imagesc(sim.t/3600, road.x_centers, road.rho)
            colormap(ite_colormap_full)
            c = colorbar; xlabel('Time [hr]'); ylabel('Position [ft]')
            c.Label.String = 'Vehicles/ft'
            title(['Space-Time Density: ' road.name])
            applyFigureFormat(gcf, plotfmt.sz_single, plotfmt);
            exportFigure(gcf, ['spaceTime_' road_keys{r}], plotfmt);
        end
    end
end

% ====================================================================
%% Signal Timing Diagrams
% ====================================================================
if plots.signal_timing
    for r = 1:Nroads
        if road_enabled(r)
            road   = all_roads{r};
            g_vec  = road.g; g_plot = g_vec; g_plot(g_vec == 0) = -1;
            band   = zeros(road.Nx, sim.Nt-1);
            band(road.signal.cell, :) = g_plot;
            figure('Name',['signalTiming_' road_keys{r}],'Color','w')
            imagesc(sim.t(1:end-1)/60, road.x_centers, band)
            colormap([0.6 0 0; 1 1 1; 0 0.6 0]); clim([-1 1])
            colorbar('Ticks',[-1 0 1],'TickLabels',{'Red','No Signal','Green'})
            xlabel('Time [min]'); ylabel('Position [ft]')
            title(['Signal Timing: ' road.name])
            applyFigureFormat(gcf, plotfmt.sz_single, plotfmt);
            exportFigure(gcf, ['signalTiming_' road_keys{r}], plotfmt);
        end
    end
end

% ====================================================================
%% Net Source/Sink Time Series
% ====================================================================
if plots.source_sink
    for r = 1:Nroads
        if road_enabled(r)
            road = all_roads{r};
            Nap  = length(road.AccessPoints);
            if Nap == 0; continue; end
            ap_seg  = cell2mat(arrayfun(@(k) road.AccessPoints(k).xSegment, ...
                                        1:Nap, 'UniformOutput', false));
            ap_name = [road.AccessPoints.name];
            figure('Name',['sourceSink_' road_keys{r}],'Color','w')
            for k = 1:length(ap_seg)
                subplot(length(ap_seg),1,k)
                plot(sim.t/3600, road.s(ap_seg(k),:))
                ylabel('[veh/s]'); title(ap_name(k)); grid on
            end
            xlabel('Time [hr]')
            sgtitle(['Net Source/Sink: ' road.name], ...
                    'FontSize',plotfmt.sgtitle_fs,'FontWeight','bold')
            applyFigureFormat(gcf, plotfmt.sz_stack, plotfmt);
            exportFigure(gcf, ['sourceSink_' road_keys{r}], plotfmt);
        end
    end
end

% ====================================================================
%% OD Matrix Heatmap
% ====================================================================
ite_colormap_simple_res = 20;
ite_colormap_simple_R = flip(linspace(0,136,ite_colormap_simple_res));
ite_colormap_simple_G = flip(linspace(88,139,ite_colormap_simple_res));
ite_colormap_simple_B = flip(linspace(124,141,ite_colormap_simple_res));
ite_colormap_simple = zeros(20,3);
ite_colormap_simple(:,1) = ite_colormap_simple_R./255;
ite_colormap_simple(:,2) = ite_colormap_simple_G./255;
ite_colormap_simple(:,3) = ite_colormap_simple_B./255;

if plots.od_matrix
    figure('Name','odMatrix','Color','w')
    imagesc(classicTrafficDemandModel.T_vehicle); colormap(ite_colormap_simple); c = colorbar("Location","southoutside");
    c.Label.String = 'Vehicles/Day';
    xticks(1:Nzones); xticklabels(TAZ.names); xtickangle(30)
    yticks(1:Nzones); yticklabels(TAZ.names)
    xlabel('Destination Zone'); ylabel('Origin Zone')
    title('OD Matrix: Vehicle Trips per Day (Gravity Model)')
    for i = 1:Nzones
        for j = 1:Nzones
            text(j,i,sprintf('%.0f',classicTrafficDemandModel.T_vehicle(i,j)), ...
                'HorizontalAlignment','center','Color','w','FontSize',plotfmt.legend_fs)
        end
    end
    applyFigureFormat(gcf, plotfmt.sz_single, plotfmt);
    exportFigure(gcf, 'odMatrix', plotfmt);
end

% ====================================================================
%% Road Geometry Diagrams
% ====================================================================
if plots.road_geometry
    for r = 1:Nroads
        if road_enabled(r)
            road = all_roads{r};
            Nap  = length(road.AccessPoints);
            ap.name = []; ap.xSegment = [];
            for k = 1:Nap
                ap.name     = [ap.name,     road.AccessPoints(k).name];
                ap.xSegment = [ap.xSegment, road.AccessPoints(k).xSegment];
            end
            plotRoadGeometry(sim, road, road.x_edges, road.x_centers, ...
                             road.N_lanes, road.signal, ap);
        end
    end
end

% ====================================================================
%% ====================== Helper Functions ===========================
% ====================================================================
function h = hourIndex(t)
% hourIndex
% Converts simulation time [s] to a 1-based hour index (1-24).
%
% INPUTS:  t - simulation time [s]
% OUTPUT:  h - hour index [1..24]
h = floor(t/3600) + 1;
h = max(1, min(h, 24));
end

function f = parametricPeaks(peakParameters)
% parametricPeaks
% Builds a 24-element raw Gaussian hourly profile from user-specified
% peak parameters. Normalize the output (f/sum(f)) to get fractional
% hourly shares of daily volume.
%
% INPUTS:
%   peakParameters.w     - peak weight(s) [scalar or vector]
%   peakParameters.mu    - peak hour(s) [hour of day, 1-24]
%   peakParameters.sigma - peak spread(s) [hours, 1-sigma]
% OUTPUT:
%   f - 24-element Gaussian profile (not normalized)

N = length(peakParameters.w);
h = 1:24;
f = zeros(size(h));
for idx = 1:N
    g = exp(-((h - peakParameters.mu(idx)).^2 ./ ...
              (2 * peakParameters.sigma(idx).^2)));
    f = f + peakParameters.w(idx) .* g;
end
end

function applyFigureFormat(fig, sz, pf)
% applyFigureFormat  Resize figure and apply report-grade text formatting.
% INPUTS
%   fig  figure handle
%   sz   [width, height] in inches
%   pf   plotfmt struct

% Resize (preserves screen position, sets physical dimensions)
fig.Units = 'inches';
pos = fig.Position;
pos(3:4) = sz;
fig.Position = pos;

% Axes: ticks, labels, titles, box style
ax_list = findall(fig, 'Type', 'axes');
for i = 1:numel(ax_list)
    ax = ax_list(i);
    ax.FontSize  = pf.tick_fs;
    ax.LineWidth = pf.ax_lw;
    ax.Box       = pf.ax_box;
    ax.TickDir   = pf.tick_dir;
    if isprop(ax, 'Title');  ax.Title.FontSize  = pf.title_fs; end
    if isprop(ax, 'XLabel'); ax.XLabel.FontSize = pf.label_fs; end
    if isprop(ax, 'YLabel'); ax.YLabel.FontSize = pf.label_fs; end
end

% Super-title
sg = findall(fig, 'Tag', 'sgtitle');
for i = 1:numel(sg)
    sg(i).FontSize   = pf.sgtitle_fs;
    sg(i).FontWeight = 'bold';
end

% Legends
leg_list = findall(fig, 'Type', 'legend');
for i = 1:numel(leg_list)
    leg_list(i).FontSize = pf.legend_fs;
end
end

function exportFigure(fig, name, pf)
% exportFigure  Save figure as PNG when pf.export is true.
% INPUTS
%   fig   figure handle
%   name  filename stem (no extension, no path)
%   pf    plotfmt struct
if ~pf.export; return; end
if ~isfolder(pf.export_dir); mkdir(pf.export_dir); end
out_path = fullfile(pf.export_dir, [name '.png']);
exportgraphics(fig, out_path, 'Resolution', pf.dpi, 'BackgroundColor', 'white');
fprintf('  Exported: %s\n', out_path)
end

function plotRoadGeometry(sim, road, x_edges, x_centers, N_lanes, signal, access)
% plotRoadGeometry
% Visualizes a north-south arterial with lane geometry, signals,
% and access point locations from the demand model.
%
% INPUTS:
%   sim      - struct with .dx
%   road     - struct with .length, .Nx
%   x_edges  - cell boundary positions [ft]
%   x_centers - cell center positions [ft]
%   N_lanes  - lanes per segment
%   signal   - struct with .cell
%   access   - struct with .xSegment, .taz_idx, .name

max_lanes = max(N_lanes);

figure('Name',['roadGeometry_' road.name],'Color','w');
hold on;

for i = 1:road.Nx
    y1 = x_edges(i);
    y2 = x_edges(i+1);
    width = N_lanes(i);
    fill([0 width width 0], [y1 y1 y2 y2], [0.85 0.85 0.85], 'EdgeColor','none');
    plot([0 width],[y1 y1],'k--','LineWidth',0.5);
end
plot([0 max_lanes],[road.length road.length],'k--','LineWidth',0.5);

if isfield(signal,'cell') && ~isempty(signal.cell)
    for k = 1:length(signal.cell(:))
        y_sig = x_centers(signal.cell(k));
        plot([0 max_lanes],[y_sig y_sig],'r','LineWidth',3);
        text(max_lanes*0.02, y_sig+80, 'Signal', 'Color','r','FontWeight','bold');
    end
end

if isfield(access,'xSegment') && ~isempty(access.xSegment)
    band_half = sim.dx/2;
    % taz_labels = {'Campus','Shopping'};
    for k = 1:length(access.xSegment)
        y = x_centers(access.xSegment(k));
        faceColor = [0.2 0.8 0.4];
        patch([0 max_lanes max_lanes 0], ...
              [y-band_half y-band_half y+band_half y+band_half], ...
              faceColor, 'FaceAlpha',0.22,'EdgeColor','none');
        text(max_lanes*0.5, y, access.name(k), ...
            'HorizontalAlignment','center','FontSize',8);
    end
end

xlim([0 max_lanes]); ylim([0 road.length])
xlabel('Road Width [# lanes]')
ylabel('Distance Along Corridor [ft]')
title(['Road Geometry with Signals and Access Points: ', road.name])
set(gca,'YDir','normal','FontSize',11)
grid on; box on

h_road   = patch(NaN,NaN,[0.85 0.85 0.85],'EdgeColor','none');
h_seg    = plot(NaN,NaN,'k--','LineWidth',0.6);
h_signal = plot(NaN,NaN,'r','LineWidth',3);
h_camp   = patch(NaN,NaN,[0.2 0.6 1.0],'FaceAlpha',0.25,'EdgeColor','none');
h_shop   = patch(NaN,NaN,[0.2 0.8 0.4],'FaceAlpha',0.25,'EdgeColor','none');
legend([h_road, h_seg, h_signal, h_camp, h_shop], ...
       ["Roadway (Lane Geometry)","Cell Boundary (FV Segment)", ...
        "Signalized Intersection","Campus Access Point","Shopping Access Point"], ...
       "Location","eastoutside");
legend boxoff
hold off
end

function road = mapAccessPoints(road, TAZ)
% mapAccessPoints
% Filters TAZ.AccessPoints by road name and resolves each access point's
% local x-coordinate to its corresponding finite-volume segment index.
%
% INPUTS:
%   road  - struct with .name, .x_edges (from EvergreenRd*() constructors)
%   TAZ   - struct with .AccessPoints array
% OUTPUT:
%   road  - same struct with .AccessPoints field populated

matching = find(strcmp({TAZ.AccessPoints.roadName}, road.name));
road.AccessPoints = TAZ.AccessPoints(matching);
for k = 1:length(road.AccessPoints)
    Np = length(road.AccessPoints(k).xLocal);
    road.AccessPoints(k).xSegment = zeros(1, Np);
    for p = 1:Np
        road.AccessPoints(k).xSegment(p) = find( ...
            road.x_edges(1:end-1) <= road.AccessPoints(k).xLocal(p) & ...
            road.x_edges(2:end)   >  road.AccessPoints(k).xLocal(p), 1, 'first');
    end
end
end

function road = mapIntersectionPoints(road, intersection)
% mapAccessPoints
% Filters intersection by road name and resolves each access point's
% local x-coordinate to its corresponding finite-volume segment index.
%
% INPUTS:
%   road  - struct with .name, .x_edges (from EvergreenRd*() constructors)
%   intersection   - struct
% OUTPUT:
%   road  - same struct with .intersection field populated

matching = find(strcmp({intersection.roadName}, road.name));
road.intersection = intersection(matching);
for k = 1:length(road.intersection)
    Np = length(road.intersection(k).xLocal);
    road.intersection(k).xSegment = zeros(1, Np);
    for p = 1:Np
        road.intersection(k).xSegment(p) = find( ...
            road.x_edges(1:end-1) <= road.intersection(k).xLocal(p) & ...
            road.x_edges(2:end)   >  road.intersection(k).xLocal(p), 1, 'first');
    end
end
end
