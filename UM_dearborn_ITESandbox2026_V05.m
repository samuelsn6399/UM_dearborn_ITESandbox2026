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
TAZ.peak_arrive = [14, 14, 14, 16, 16, 14];      % [hour of day] arrival peak per TAZ
TAZ.sigma_arrive = [4, 4, 4, 4, 4, 5];  % [hours] arrival peak spread per TAZ
TAZ.peak_depart = [14, 14, 14, 16, 16, 14];    % [hour of day] departure peak per TAZ
TAZ.sigma_depart = [4, 4, 4, 4, 4, 5]; % [hours] departure peak spread per TAZ
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

% ====================================================================
%% ====================== PLOT CONTROLS (USER INPUT) ================
% ====================================================================
% Toggle each plot group on (true) or off (false).
plots.tuning_boundary     = true;   % Hourly boundary flow vs MDOT truth (one fig per road)
plots.tuning_conservation = true;   % Daily trip conservation summary across all roads
plots.space_time          = false;   % Space-time density diagrams
plots.signal_timing       = false;  % Signal phase space-time diagrams
plots.source_sink         = false;  % Net source/sink time series at access points
plots.od_matrix           = false;  % OD matrix heatmap
plots.road_geometry       = false;  % Road geometry with lane widths and access points

% Road filter — applies to space_time, signal_timing, source_sink, road_geometry only.
% tuning_boundary and tuning_conservation always cover all roads.
plots.road_SB = true;
plots.road_NB = true;
plots.road_EB = true;
plots.road_WB = true;

% ====================================================================
%% ======================== Plot Results =============================
% ====================================================================
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

% ====================================================================
%% Tuning: Hourly Boundary Flow vs MDOT Truth
% One figure per road; 2x3 subplot layout:
%   Row 1: inflow time series | outflow time series | daily totals bar
%   Row 2: inflow % error     | outflow % error     | daily % error bar
% ====================================================================
if plots.tuning_boundary
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

        figure('Name',['boundaryTuning_' road_keys{r}], ...
               'Position',[50 50 1400 650],'Color','w')
        sgtitle(['Boundary Flow Tuning: ' road.name],'FontSize',13,'FontWeight','bold')

        % (1,1) Upstream inflow — hourly
        subplot(2,3,1); hold on
        if has_mdot
            bar(hrs, mdot_in_hrly,'FaceColor',[0.2 0.4 0.8],'FaceAlpha',0.5,'DisplayName','MDOT Truth')
        end
        plot(hrs, F_in_des_hrly,'k--o','LineWidth',1.5,'MarkerSize',4,'DisplayName','OD Desired')
        plot(hrs, F_in_hrly,    'r-o', 'LineWidth',1.5,'MarkerSize',4,'DisplayName','Sim Actual')
        hold off
        ylabel('Flow [veh/hr]'); xlabel('Hour of Day'); title('Upstream Inflow')
        grid on; legend('Location','northwest','FontSize',8); xticks(hrs); xlim([0.5 Nhrs+0.5])

        % (1,2) Downstream outflow — hourly
        subplot(2,3,2); hold on
        if has_mdot
            bar(hrs, mdot_out_hrly,'FaceColor',[0.2 0.7 0.3],'FaceAlpha',0.5,'DisplayName','MDOT Truth')
        end
        plot(hrs, F_out_des_hrly,'k--o','LineWidth',1.5,'MarkerSize',4,'DisplayName','OD Desired')
        plot(hrs, F_out_hrly,    'r-o', 'LineWidth',1.5,'MarkerSize',4,'DisplayName','Sim Actual')
        hold off
        ylabel('Flow [veh/hr]'); xlabel('Hour of Day'); title('Downstream Outflow')
        grid on; legend('Location','northwest','FontSize',8); xticks(hrs); xlim([0.5 Nhrs+0.5])

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
        legend('Location','northeast','FontSize',8); grid on

        % (2,1) Inflow % error vs MDOT — hourly
        subplot(2,3,4)
        if has_mdot
            denom = max(mdot_in_hrly, 1);
            hold on
            bar(hrs, (F_in_des_hrly - mdot_in_hrly) ./ denom * 100, ...
                'FaceColor',[0.7 0.7 0.7],'FaceAlpha',0.7,'DisplayName','OD Desired')
            plot(hrs, (F_in_hrly - mdot_in_hrly) ./ denom * 100, ...
                'r-o','LineWidth',1.5,'MarkerSize',4,'DisplayName','Sim Actual')
            yline(0,'k--','LineWidth',1)
            hold off
            ylabel('Error [%]'); xlabel('Hour of Day'); title('Inflow % Error vs MDOT')
            grid on; legend('Location','northeast','FontSize',8); xticks(hrs); xlim([0.5 Nhrs+0.5])
        else
            text(0.5,0.5,'No MDOT data','HorizontalAlignment','center', ...
                'Units','normalized','FontSize',11); axis off
        end

        % (2,2) Outflow % error vs MDOT — hourly
        subplot(2,3,5)
        if has_mdot
            denom = max(mdot_out_hrly, 1);
            hold on
            bar(hrs, (F_out_des_hrly - mdot_out_hrly) ./ denom * 100, ...
                'FaceColor',[0.7 0.7 0.7],'FaceAlpha',0.7,'DisplayName','OD Desired')
            plot(hrs, (F_out_hrly - mdot_out_hrly) ./ denom * 100, ...
                'r-o','LineWidth',1.5,'MarkerSize',4,'DisplayName','Sim Actual')
            yline(0,'k--','LineWidth',1)
            hold off
            ylabel('Error [%]'); xlabel('Hour of Day'); title('Outflow % Error vs MDOT')
            grid on; legend('Location','northeast','FontSize',8); xticks(hrs); xlim([0.5 Nhrs+0.5])
        else
            text(0.5,0.5,'No MDOT data','HorizontalAlignment','center', ...
                'Units','normalized','FontSize',11); axis off
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
                'Units','normalized','FontSize',11); axis off
        end
    end
end

% ====================================================================
%% Tuning: Daily Trip Conservation — All Roads
% Compares OD model desired daily volumes vs MDOT truth vs sim actual
% for each road's upstream and downstream boundaries.
% ====================================================================
if plots.tuning_conservation
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
    figure('Name','tripConservation','Position',[100 100 1100 480],'Color','w')
    sgtitle('Daily Trip Conservation: OD Model vs MDOT Truth vs Simulation', ...
        'FontSize',13,'FontWeight','bold')

    subplot(1,2,1)
    b = bar(categorical(road_keys), [daily_mdot_in; daily_des_in; daily_act_in]');
    b(1).DisplayName = 'MDOT Truth'; b(1).FaceColor = [0.2 0.4 0.8];
    b(2).DisplayName = 'OD Desired'; b(2).FaceColor = [0.7 0.7 0.7];
    b(3).DisplayName = 'Sim Actual'; b(3).FaceColor = [0.9 0.3 0.3];
    ylabel('Vehicles [veh/day]'); title('Upstream Inflow: Daily Total')
    legend('Location','northeast','FontSize',9); grid on

    subplot(1,2,2)
    b = bar(categorical(road_keys), [daily_mdot_out; daily_des_out; daily_act_out]');
    b(1).DisplayName = 'MDOT Truth'; b(1).FaceColor = [0.2 0.4 0.8];
    b(2).DisplayName = 'OD Desired'; b(2).FaceColor = [0.7 0.7 0.7];
    b(3).DisplayName = 'Sim Actual'; b(3).FaceColor = [0.9 0.3 0.3];
    ylabel('Vehicles [veh/day]'); title('Downstream Outflow: Daily Total')
    legend('Location','northeast','FontSize',9); grid on
end

% ====================================================================
%% Space-Time Density Diagrams
% ====================================================================
if plots.space_time
    for r = 1:Nroads
        if road_enabled(r)
            road = all_roads{r};
            figure('Name',['spaceTime_' road_keys{r}])
            imagesc(sim.t/3600, road.x_centers, road.rho)
            colorbar; xlabel('Time [hr]'); ylabel('Position [ft]')
            title(['Space-Time Density: ' road.name])
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
            figure('Name',['signalTiming_' road_keys{r}])
            imagesc(sim.t(1:end-1)/60, road.x_centers, band)
            colormap([0.6 0 0; 1 1 1; 0 0.6 0]); clim([-1 1])
            colorbar('Ticks',[-1 0 1],'TickLabels',{'Red','No Signal','Green'})
            xlabel('Time [min]'); ylabel('Position [ft]')
            title(['Signal Timing: ' road.name])
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
            figure('Name',['sourceSink_' road_keys{r}])
            for k = 1:length(ap_seg)
                subplot(length(ap_seg),1,k)
                plot(sim.t/3600, road.s(ap_seg(k),:),'LineWidth',1)
                ylabel('[veh/s]'); title(ap_name(k),'FontSize',8); grid on
            end
            xlabel('Time [hr]')
            sgtitle(['Net Source/Sink: ' road.name])
        end
    end
end

% ====================================================================
%% OD Matrix Heatmap
% ====================================================================
if plots.od_matrix
    figure('Name','odMatrix')
    imagesc(classicTrafficDemandModel.T_vehicle); colorbar
    xticks(1:Nzones); xticklabels(TAZ.names); xtickangle(30)
    yticks(1:Nzones); yticklabels(TAZ.names)
    xlabel('Destination Zone'); ylabel('Origin Zone')
    title('OD Matrix: Vehicle Trips per Day (Gravity Model)')
    for i = 1:Nzones
        for j = 1:Nzones
            text(j,i,sprintf('%.0f',classicTrafficDemandModel.T_vehicle(i,j)), ...
                'HorizontalAlignment','center','FontSize',7,'Color','w')
        end
    end
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
