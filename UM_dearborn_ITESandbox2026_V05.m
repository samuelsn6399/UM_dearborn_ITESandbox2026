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
fprintf('Done setting up simulation...\n')

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
TAZ.peak_arrive = [8, 13, 12, 12, 12, 12];      % [hour of day] arrival peak per TAZ
TAZ.sigma_arrive = [1.5, 2.0, 5, 5, 5, 5];  % [hours] arrival peak spread per TAZ
TAZ.peak_depart = [17, 14, 12, 12, 12, 12];    % [hour of day] departure peak per TAZ
TAZ.sigma_depart = [1.5, 2.0, 5, 5, 5, 5]; % [hours] departure peak spread per TAZ
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
TAZ.AccessPoints(1).xLocal   = [1700, 3200, 4500, 5400]; % [ft] in road-local coords
TAZ.AccessPoints(1).split    = [0.10, 0.60, 0.20, 0.10]; % must sum to 1.0
TAZ.AccessPoints(1).name     = ["University Secondary Entrance 1", ...
               "University Primary Entrance",     ...
               "University Tertiary Entrance",    ...
               "University Secondary Entrance 2"];

TAZ.AccessPoints(2).taz_idx  = 1;                    % MainCampus on the NB road
TAZ.AccessPoints(2).roadName = evergreenRdNorthbound.name;
TAZ.AccessPoints(2).xLocal   = [1100, 2000, 3300, 4800];
TAZ.AccessPoints(2).split    = [0.10, 0.20, 0.60, 0.10];
TAZ.AccessPoints(2).name     = ["University Secondary Entrance 1", ...
               "University Primary Entrance",     ...
               "University Tertiary Entrance",    ...
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
        LWRModel(hubbardRdWestbound, rho_NB(:,n), classicTrafficDemandModel, TAZ, sim);
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

hubbardRdWestbound.rho = rho_WB; hubbardRdWestbound.F = F_WB;
hubbardRdWestbound.F_desired = F_WB_desired;
hubbardRdWestbound.g   = g_WB;   hubbardRdWestbound.g_eff = g_eff_WB;
hubbardRdWestbound.s   = s_WB;

% ====================================================================
%% ======================== Plot Results =============================
% ====================================================================

%% Demand Model Summary
fprintf('\n========== 4-Step Demand Model Summary ==========\n');
fprintf('%-20s %10s %10s %10s\n', 'Zone', 'P [p-t/d]', 'A [p-t/d]', 'P-A');
for iz = 1:Nzones
    fprintf('%-20s %10.0f %10.0f %10.0f\n', ...
        TAZ.names{iz}, classicTrafficDemandModel.P(iz), classicTrafficDemandModel.A(iz), ...
        classicTrafficDemandModel.P(iz) - classicTrafficDemandModel.A(iz));
end
fprintf('%-20s %10.0f %10.0f\n', 'TOTAL', sum(classicTrafficDemandModel.P), sum(classicTrafficDemandModel.A));
fprintf('\nOD Matrix [vehicle-trips/day]:\n');
header = sprintf('%15s', '');
for j = 1:Nzones
    header = [header sprintf('%15s', TAZ.names{j}(1:min(end,12)))]; %#ok<AGROW>
end
fprintf('%s\n', header);
for i = 1:Nzones
    row = sprintf('%15s', TAZ.names{i}(1:min(end,12)));
    for j = 1:Nzones
        row = [row sprintf('%15.0f', classicTrafficDemandModel.T_vehicle(i,j))]; %#ok<AGROW>
    end
    fprintf('%s\n', row);
end

%% Space-Time Density Diagrams
figure('Name','spaceTimeDiagram_Road1')
imagesc(sim.t/3600, evergreenRdSouthbound.x_centers, evergreenRdSouthbound.rho)
colorbar
xlabel('Time [hr]')
ylabel('Position [ft]')
title(['Space-Time Density: ' evergreenRdSouthbound.name])

figure('Name','spaceTimeDiagram_Road2')
imagesc(sim.t/3600, evergreenRdNorthbound.x_centers, evergreenRdNorthbound.rho)
colorbar
xlabel('Time [hr]')
ylabel('Position [ft]')
title(['Space-Time Density: ' evergreenRdNorthbound.name])

%% OD Tuning – Road 1 (Southbound)
figure('Name', 'odTuning_Road1')
subplot(2,2,1)
hold on
plot(sim.t, evergreenRdSouthbound.F(1,:), 'r-', 'DisplayName', 'Incoming Flow (Actual OD Model)')
plot(sim.t, evergreenRdSouthbound.F_desired(1,:), 'r:', 'DisplayName', 'Incoming Flow (Desired OD Model)')
plot(sim.t, [repelem(evergreenRdSouthbound.Truth.MDOT_inflow_s, 3600), 0], 'b:', 'DisplayName', 'Incoming Flow (MDOT Truth Data)')
hold off; ylabel('Flow (veh/s)'); title('SB: North Boundary Inflow'); xlabel('time (s)'); grid on; legend();
subplot(2,2,2)
plot(sim.t, evergreenRdSouthbound.F(1,:) - [repelem(evergreenRdSouthbound.Truth.MDOT_inflow_s, 3600), 0], 'r-', 'DisplayName', 'OD Model - MDOT Truth Data')
title('SB: Difference North Inflow'); xlabel('time (s)'); grid on; legend();
subplot(2,2,3)
hold on
plot(sim.t, evergreenRdSouthbound.F(evergreenRdSouthbound.Nx+1,:), 'r-', 'DisplayName', 'Outgoing Flow (Actual OD Model)')
plot(sim.t, evergreenRdSouthbound.F_desired(2,:), 'r:', 'DisplayName', 'Incoming Flow (Desired OD Model)')
plot(sim.t, [repelem(evergreenRdSouthbound.Truth.MDOT_outflow_s, 3600), 0], 'b:', 'DisplayName', 'Outgoing Flow (MDOT Truth Data)')
hold off; ylabel('Flow (veh/s)'); title('SB: South Boundary Outflow'); xlabel('time (s)'); grid on; legend();
subplot(2,2,4)
plot(sim.t, evergreenRdSouthbound.F(evergreenRdSouthbound.Nx+1,:) - [repelem(evergreenRdSouthbound.Truth.MDOT_outflow_s, 3600), 0], 'r-', 'DisplayName', 'OD Model - MDOT Truth Data')
title('SB: Difference South Outflow'); xlabel('time (s)'); grid on; legend();

%% OD Tuning – Road 2 (Northbound)
figure('Name', 'odTuning_Road2')
subplot(2,2,1)
hold on
plot(sim.t, evergreenRdNorthbound.F(1,:), 'r-', 'DisplayName', 'Incoming Flow (Actual OD Model)')
plot(sim.t, evergreenRdNorthbound.F_desired(1,:), 'r:', 'DisplayName', 'Incoming Flow (Desired OD Model)')
plot(sim.t, [repelem(evergreenRdNorthbound.Truth.MDOT_inflow_s, 3600), 0], 'b:', 'DisplayName', 'Incoming Flow (MDOT Truth Data)')
hold off; ylabel('Flow (veh/s)'); title('NB: South Boundary Inflow'); xlabel('time (s)'); grid on; legend();
subplot(2,2,2)
plot(sim.t, evergreenRdNorthbound.F(1,:) - [repelem(evergreenRdNorthbound.Truth.MDOT_inflow_s, 3600), 0], 'r-', 'DisplayName', 'OD Model - MDOT Truth Data')
title('NB: Difference South Inflow'); xlabel('time (s)'); grid on; legend();
subplot(2,2,3)
hold on
plot(sim.t, evergreenRdNorthbound.F(evergreenRdNorthbound.Nx+1,:), 'r-', 'DisplayName', 'Outgoing Flow (Actual OD Model)')
plot(sim.t, evergreenRdNorthbound.F_desired(2,:), 'r:', 'DisplayName', 'Outgoing Flow (Desired OD Model)')
plot(sim.t, [repelem(evergreenRdNorthbound.Truth.MDOT_outflow_s, 3600), 0], 'b:', 'DisplayName', 'Outgoing Flow (MDOT Truth Data)')
hold off; ylabel('Flow (veh/s)'); title('NB: North Boundary Outflow'); xlabel('time (s)'); grid on; legend();
subplot(2,2,4)
plot(sim.t, evergreenRdNorthbound.F(evergreenRdNorthbound.Nx+1,:) - [repelem(evergreenRdNorthbound.Truth.MDOT_outflow_s, 3600), 0], 'r-', 'DisplayName', 'OD Model - MDOT Truth Data')
title('NB: Difference North Outflow'); xlabel('time (s)'); grid on; legend();

%% Signal Timing – Road 1 (SB)
g_SB = evergreenRdSouthbound.g;
g_SB_plot = g_SB;
g_SB_plot(g_SB == 0) = -1;
signal_band_SB = zeros(evergreenRdSouthbound.Nx, sim.Nt-1);
signal_band_SB(evergreenRdSouthbound.signal.cell, :) = g_SB_plot;
figure('Name','signalSpaceTime_Road1')
imagesc(sim.t(1:end-1)/60, evergreenRdSouthbound.x_centers, signal_band_SB)
colormap([0.6 0 0; 1 1 1; 0 0.6 0])
clim([-1 1])
colorbar('Ticks',[-1 0 1],'TickLabels',{'Red','No Signal','Green'})
xlabel('Time [min]'); ylabel('Position [ft]')
title(['Signal Location and Timing: ' evergreenRdSouthbound.name])

%% Signal Timing – Road 2 (NB)
g_NB = evergreenRdNorthbound.g;
g_NB_plot = g_NB;
g_NB_plot(g_NB == 0) = -1;
signal_band_NB = zeros(evergreenRdNorthbound.Nx, sim.Nt-1);
signal_band_NB(evergreenRdNorthbound.signal.cell, :) = g_NB_plot;
figure('Name','signalSpaceTime_Road2')
imagesc(sim.t(1:end-1)/60, evergreenRdNorthbound.x_centers, signal_band_NB)
colormap([0.6 0 0; 1 1 1; 0 0.6 0])
clim([-1 1])
colorbar('Ticks',[-1 0 1],'TickLabels',{'Red','No Signal','Green'})
xlabel('Time [min]'); ylabel('Position [ft]')
title(['Signal Location and Timing: ' evergreenRdNorthbound.name])

%% Road Geometry – Road 1 (SB)
ap_SB.name = []; ap_SB.xSegment = [];
for k = 1:length(evergreenRdSouthbound.AccessPoints)
    ap_SB.name     = [ap_SB.name,     evergreenRdSouthbound.AccessPoints(k).name];     %#ok<AGROW>
    ap_SB.xSegment = [ap_SB.xSegment, evergreenRdSouthbound.AccessPoints(k).xSegment]; %#ok<AGROW>
end
plotRoadGeometry(sim, evergreenRdSouthbound, evergreenRdSouthbound.x_edges, ...
    evergreenRdSouthbound.x_centers, evergreenRdSouthbound.N_lanes, ...
    evergreenRdSouthbound.signal, ap_SB);

%% Road Geometry – Road 2 (NB)
ap_NB.name = []; ap_NB.xSegment = [];
for k = 1:length(evergreenRdNorthbound.AccessPoints)
    ap_NB.name     = [ap_NB.name,     evergreenRdNorthbound.AccessPoints(k).name];     %#ok<AGROW>
    ap_NB.xSegment = [ap_NB.xSegment, evergreenRdNorthbound.AccessPoints(k).xSegment]; %#ok<AGROW>
end
plotRoadGeometry(sim, evergreenRdNorthbound, evergreenRdNorthbound.x_edges, ...
    evergreenRdNorthbound.x_centers, evergreenRdNorthbound.N_lanes, ...
    evergreenRdNorthbound.signal, ap_NB);

%% Net Source/Sink – Road 1 (SB)
figure('Name','netSourceSinkLog_Road1')
Nap_SB = length(ap_SB.xSegment);
for k = 1:Nap_SB
    subplot(Nap_SB, 1, k)
    plot(sim.t/3600, evergreenRdSouthbound.s(ap_SB.xSegment(k),:), 'LineWidth', 1)
    ylabel('[veh/ft/s]')
    title(ap_SB.name(k), 'FontSize', 8)
    grid on
end
xlabel('Time [hr]')
sgtitle(['Net Source/Sink Term [veh/ft/s]: ' evergreenRdSouthbound.name])

%% Net Source/Sink – Road 2 (NB)
figure('Name','netSourceSinkLog_Road2')
Nap_NB = length(ap_NB.xSegment);
for k = 1:Nap_NB
    subplot(Nap_NB, 1, k)
    plot(sim.t/3600, evergreenRdNorthbound.s(ap_NB.xSegment(k),:), 'LineWidth', 1)
    ylabel('[veh/ft/s]')
    title(ap_NB.name(k), 'FontSize', 8)
    grid on
end
xlabel('Time [hr]')
sgtitle(['Net Source/Sink Term [veh/ft/s]: ' evergreenRdNorthbound.name])

%% OD Matrix Heatmap
figure('Name','odMatrixVehicleTripsDay')
imagesc(classicTrafficDemandModel.T_vehicle)
colorbar
xticks(1:Nzones); xticklabels(TAZ.names); xtickangle(30)
yticks(1:Nzones); yticklabels(TAZ.names)
xlabel('Destination Zone')
ylabel('Origin Zone')
title('OD Matrix: Vehicle Trips per Day (Gravity Model)')
for i = 1:Nzones
    for j = 1:Nzones
        text(j, i, sprintf('%.0f', classicTrafficDemandModel.T_vehicle(i,j)), ...
            'HorizontalAlignment','center','FontSize',7,'Color','w')
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
