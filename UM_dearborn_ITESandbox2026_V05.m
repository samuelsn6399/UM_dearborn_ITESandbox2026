% ====================================================================
%% ITE Sandbox Competition 2026: University of Michigan - Dearborn
% ====================================================================
clear; close all; clc;
% ====================================================================
% DESCRIPTION:
% The model develops a macroscopic network flow model of traffic of an
% arterial road running North-South along the length of the University
% of Michigan - Dearborn. The simulation uses "truth" data at the
% boundaries of the road segment to set initial conditions. The model
% supports scenario testing for operational and policy interventions.
%
% Source and sink flows at mid-corridor access points are derived from
% a 4-step travel demand model (NCHRP 716) using:
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
%% Simulation Settings (User Input)
sim.dt      = 1;                 % [s] time step
sim.dx      = 500;               % [ft] spatial cell length
sim.T_end   = 24*3600;           % [s] total simulation time
fprintf('Done Setting up simulation...\n')
%% Configure Road Geometry (User Input)
road.name = 'Evergreen Rd';
road.length = 6500;     % [ft]
fprintf('Done Configuring road geometry...\n')
%% Traffic Flow Model (User Input)
FD.model = "Greenshields"; % only one model currently supported
FD.rho_j = 1/18;    % [veh/ft/lane] jamming density
fprintf('Done Selecting traffic flow model...\n')
%% Signal Configuration (User Input)
signal.x = 6000; % [ft]
signal.green = 45; % [s] signal green time
signal.red = 75; % [s] signal red time
signal.Qsat_per_lane = 1900/3600; % [veh/s/lane]
fprintf('Done Configuring signal(s)...\n')
%% Access Point Configuration (User Input)
% These define mid-corridor driveway locations where vehicles enter/exit
% the arterial. Each access point is associated with an internal TAZ.
% TAZ index:  1=MainCampus, 2=ShoppingCenter (see demand model below)
access.name = ["University Secondary Entrance 1", ...
               "University Primary Entrance",     ...
               "University Tertiary Entrance",    ...
               "University Secondary Entrance 2", ...
               "Shopping Center Entrance"];
access.xLocation = [1700, 3200, 4500, 5400, 6000]; % [ft] along corridor
access.taz_idx   = [1, 1, 1, 1, 2]; % which internal TAZ each belongs to

% Fraction of that TAZ's total corridor flow assigned to each access point
% (campus splits must sum to 1.0; shopping center has only 1 point)
access.taz_split = [0.10, 0.60, 0.20, 0.10, 1.00];

%% 4-Step Demand Model Parameters (User Input)
% ---- Zone Definitions ----
% Zones 1-2 are internal (mid-corridor access points exist)
% Zones 3-6 are external (affect boundary conditions only)
demand.zone_names = {'MainCampus',    'ShoppingCenter', 'StudentHousing', ...
                     'NorthBoundary', 'SouthBoundary',  'EastBoundary'};
% Approximate zone centroid position along the N-S corridor axis [ft]
% x = 0 ft is the NORTH end; x = road.length is the SOUTH end.
% Zones beyond the corridor: NorthBoundary has x < 0, SouthBoundary has x > road.length.
demand.zone_x  = [3500,   6000,  1000, -2000,   9000, 2000]; % [ft]
%                  ^       ^      ^      ^       ^     ^
%                Campus  Shop   StudHsg North  South East
% Off-corridor lateral offset for zones not on the main road axis [ft]
demand.zone_dy = [   0,      0,  5000,     0,      0, 5280];  % [ft]

% ---- Step 1 Parameters: Attraction Model ----
% Linear model: A_zone = rate_emp*Employment + rate_enroll*Enrollment
%               + rate_retail*RetailArea (NCHRP 716 Table 3-8 guidance)
demand.attr_rates = [1.5,    ...  % [person-trips/job/day]
                     0.8,    ...  % [person-trips/student/day]
                     0.002]; ...  % [person-trips/sqft/day]

% ---- Step 2 Parameters: Gravity Model ----
% Friction factor: F(t_ij) = exp(-beta * t_ij)
% beta controls how sensitive trip distribution is to travel time
demand.v_avg_mph = 35;                  % [mph] average corridor travel speed
demand.beta      = 0.12;               % [1/min] friction factor decay rate

% ---- Step 3 Parameters: Mode Choice ----
demand.auto_occupancy = 1.25;           % [persons/vehicle] average occupancy

% ---- Step 4 Parameters: Temporal Distribution ----
% Each internal TAZ has an arrival peak (inbound) and departure peak (outbound)
% MainCampus: arrivals peak in AM (students/workers arrive), departures peak PM
demand.taz_peak_arrive = [8,  13];      % [hour of day] arrival peak per TAZ
demand.taz_sigma_arrive = [1.5, 2.0];  % [hours] arrival peak spread per TAZ
demand.taz_peak_depart = [17,  14];    % [hour of day] departure peak per TAZ
demand.taz_sigma_depart = [1.5, 2.0]; % [hours] departure peak spread per TAZ
fprintf('Done Configuring 4-step model parameters...\n')
% ====================================================================
%% =============== Check For Valid User Inputs =======================
% ====================================================================
assert(sim.dt > 0, "Time step must be positive")
assert(mod(road.length, sim.dx) == 0, ...
    "Road length must be divisible by dx")
assert(88*sim.dt/sim.dx <= 1, ...
    "CFL condition violated - reduce dt or increase dx")
assert(abs(sum(access.taz_split(access.taz_idx == 1)) - 1.0) < 1e-6, ...
    "Campus access point TAZ splits must sum to 1.0")
assert(abs(sum(access.taz_split(access.taz_idx == 2)) - 1.0) < 1e-6, ...
    "Shopping center access point TAZ splits must sum to 1.0")
fprintf('Done Checking for valid inputs...\n')
% ====================================================================
%% ==================== Load House Hold Data =========================
% ====================================================================
filename_householdData = "HouseholdData.xlsx";
H_mainCampus    = readmatrix(filename_householdData,'Sheet','MainCampus');
H_mainCampus    = H_mainCampus(1:end-1, 2:end-1); % omit headers and totals
H_shoppingCenter = readmatrix(filename_householdData,'Sheet','ShoppingCenter');
H_shoppingCenter = H_shoppingCenter(1:end-1, 2:end-1);
H_studentHousing = readmatrix(filename_householdData,'Sheet','StudentHousing');
H_studentHousing = H_studentHousing(1:end-1, 2:end-1);
H_northBoundary = readmatrix(filename_householdData,'Sheet','NorthBoundary');
H_northBoundary = H_northBoundary(1:end-1, 2:end-1);
H_southBoundary = readmatrix(filename_householdData,'Sheet','SouthBoundary');
H_southBoundary = H_southBoundary(1:end-1, 2:end-1);
H_eastBoundary  = readmatrix(filename_householdData,'Sheet','EastBoundary');
H_eastBoundary  = H_eastBoundary(1:end-1, 2:end-1);
fprintf('Done Loading household data...\n')
% ====================================================================
%% =============== Load Trip Production Rate Data ====================
% ====================================================================
filename_tripRateData = "TripRateData.xlsx";
R_mainCampus    = readmatrix(filename_tripRateData,'Sheet','MainCampus');
R_mainCampus    = R_mainCampus(1:end-1, 2:end-1); % omit headers and averages
R_shoppingCenter = readmatrix(filename_tripRateData,'Sheet','ShoppingCenter');
R_shoppingCenter = R_shoppingCenter(1:end-1, 2:end-1);
R_studentHousing = readmatrix(filename_tripRateData,'Sheet','StudentHousing');
R_studentHousing = R_studentHousing(1:end-1, 2:end-1);
R_northBoundary = readmatrix(filename_tripRateData,'Sheet','NorthBoundary');
R_northBoundary = R_northBoundary(1:end-1, 2:end-1);
R_southBoundary = readmatrix(filename_tripRateData,'Sheet','SouthBoundary');
R_southBoundary = R_southBoundary(1:end-1, 2:end-1);
R_eastBoundary  = readmatrix(filename_tripRateData,'Sheet','EastBoundary');
R_eastBoundary  = R_eastBoundary(1:end-1, 2:end-1);
fprintf('Done Loading trip production data...\n')
% ====================================================================
%% =========== Load Attraction Parameter Data ========================
% ====================================================================
% AttractionParameters sheet: rows = zones, cols = [Employment, Enrollment, RetailArea]
AP_raw = readmatrix(filename_tripRateData, 'Sheet', 'AttractionParameters');
AP_raw = AP_raw(1:end, 2:end); % omit zone name column and header row
% Columns: [Employment [jobs], Enrollment [students], RetailArea [sqft]]
demand.AttractionParams = AP_raw; % Nzones x 3 matrix
fprintf('Done Loading trip attraction data...\n')
% ====================================================================
%% ============= 4-STEP TRAVEL DEMAND MODEL ==========================
% ====================================================================
Nzones = length(demand.zone_names);

%% Step 1a: Trip Productions (Cross-Classification)
% P_i = sum over all (autos, household-size) cells of H_i(a,s) * R_i(a,s)
% Units: [person-trips/day] produced by zone i
H_list = {H_mainCampus, H_shoppingCenter, H_studentHousing, ...
          H_northBoundary, H_southBoundary, H_eastBoundary};
R_list = {R_mainCampus, R_shoppingCenter, R_studentHousing, ...
          R_northBoundary, R_southBoundary, R_eastBoundary};

demand.P = zeros(1, Nzones);
for iz = 1:Nzones
    demand.P(iz) = sum(H_list{iz} .* R_list{iz}, 'all');
end

%% Step 1b: Trip Attractions (Linear Land-Use Model, NCHRP 716)
% A_j = rate_emp*Employment_j + rate_enroll*Enrollment_j + rate_retail*RetailArea_j
% Units: [person-trips/day] attracted to zone j
demand.A_raw = demand.AttractionParams * demand.attr_rates'; % [Nzones x 1]

%% Step 1c: Balance Productions and Attractions
% Conservation: total P must equal total A (NCHRP 716 Section 3.2)
% Scale attractions so sum(A) = sum(P)
P_total = sum(demand.P);
A_total = sum(demand.A_raw);
demand.A = demand.A_raw * (P_total / A_total); % [person-trips/day] balanced

%% Step 2: Trip Distribution (Singly-Constrained Gravity Model)
% T_ij = P_i * [A_j * F_ij / sum_k(A_k * F_ik)]
% F_ij = exp(-beta * t_ij)  friction factor (NCHRP 716 Eq. 6-3)
% t_ij = travel time between zone centroids [min]
v_avg_fts = demand.v_avg_mph * 5280 / 3600; % [ft/s]

F_matrix = zeros(Nzones, Nzones);
for i = 1:Nzones
    for j = 1:Nzones
        d_ij = sqrt( (demand.zone_x(i) - demand.zone_x(j))^2 + ...
                     (demand.zone_dy(i) - demand.zone_dy(j))^2 ); % [ft]
        t_ij = d_ij / v_avg_fts / 60; % [min]
        t_ij = max(t_ij, 1.0); % minimum 1-minute intrazonal travel time
        F_matrix(i,j) = exp(-demand.beta * t_ij);
    end
end

demand.T_person = zeros(Nzones, Nzones); % [person-trips/day] OD table
for i = 1:Nzones
    denom = sum(demand.A .* F_matrix(i,:));
    if denom > 0
        demand.T_person(i,:) = demand.P(i) * (demand.A .* F_matrix(i,:)) / denom;
    end
end

%% Step 3: Mode Choice (Average Vehicle Occupancy)
% Convert person-trips to vehicle-trips
% For a single-corridor auto-dominated model, a uniform occupancy factor
% is applied (NCHRP 716 Section 5.3)
demand.T_vehicle = demand.T_person / demand.auto_occupancy; % [veh/day] OD table

%% Step 4: Network Loading (Map OD Matrix to Corridor Source/Sink Flows)
% For each internal TAZ (MainCampus=1, ShoppingCenter=2):
%   Daily corridor arrivals (SINK) = vehicles attracted from external zones
%                                    that traveled along this corridor
%   Daily corridor departures (SOURCE) = vehicles produced at this TAZ
%                                        that depart via this corridor
%
% External zone indices (zones 3-6 feed/exit via corridor boundaries)
internal_idx = [1, 2];          % TAZ indices for corridor-internal zones
external_idx = [3, 4, 5, 6];   % TAZ indices for boundary zones

% Daily vehicle trips arriving at / departing from each internal TAZ
% Arrivals: sum of T_vehicle(external_i -> internal_j) for each internal j
% Departures: sum of T_vehicle(internal_i -> external_j) for each internal i
demand.V_taz_arrive = zeros(1, length(internal_idx)); % [veh/day]
demand.V_taz_depart = zeros(1, length(internal_idx)); % [veh/day]
for k = 1:length(internal_idx)
    iz = internal_idx(k);
    demand.V_taz_arrive(k) = sum(demand.T_vehicle(external_idx, iz));
    demand.V_taz_depart(k) = sum(demand.T_vehicle(iz, external_idx));
end

% Distribute TAZ totals across individual access points using split factors
Naccess = length(access.xLocation);
access.V_arrive = zeros(1, Naccess); % [veh/day] arriving at each access point
access.V_depart = zeros(1, Naccess); % [veh/day] departing from each access point
for k = 1:Naccess
    taz_k = access.taz_idx(k);           % which internal TAZ this belongs to
    sp    = access.taz_split(k);         % fraction of that TAZ's flow here
    taz_local = find(internal_idx == taz_k, 1);
    access.V_arrive(k) = demand.V_taz_arrive(taz_local) * sp;
    access.V_depart(k) = demand.V_taz_depart(taz_local) * sp;
end
fprintf('Done Loading 4-step model...\n')
% ====================================================================
%% ============= Generate Hourly Temporal Factors ====================
% ====================================================================
% Convert daily vehicle volumes to hourly rates using parametric Gaussian peaks
% f_norm(h) = fraction of daily traffic in hour h  [24-element vector]
%
% Arrival and departure profiles are computed per internal TAZ,
% then assigned to access points using the same split factors.

% Per-TAZ temporal profiles (parametricPeaks returns raw Gaussian; normalize)
access.f_arrive = zeros(24, Naccess);
access.f_depart = zeros(24, Naccess);
for k = 1:length(internal_idx)
    F_arr.w     = 1;
    F_arr.mu    = demand.taz_peak_arrive(k);
    F_arr.sigma = demand.taz_sigma_arrive(k);
    f_raw_arr   = parametricPeaks(F_arr);
    f_norm_arr  = f_raw_arr / sum(f_raw_arr); % normalize to fractional shares

    F_dep.w     = 1;
    F_dep.mu    = demand.taz_peak_depart(k);
    F_dep.sigma = demand.taz_sigma_depart(k);
    f_raw_dep   = parametricPeaks(F_dep);
    f_norm_dep  = f_raw_dep / sum(f_raw_dep);

    % Assign to all access points belonging to this TAZ
    pts = find(access.taz_idx == internal_idx(k));
    for p = pts
        access.f_arrive(:, p) = f_norm_arr(:);
        access.f_depart(:, p) = f_norm_dep(:);
    end
end
fprintf('Done Loading temporal factors...\n')
% ====================================================================
%% =============== MDOT Data Inputs (Truth Data) =====================
% ====================================================================
%           hour = [1    2    3    4    5     6 ]
MDOT_inflow_hour = [200, 180, 160, 150, 200, 500,... % [veh/hour]
...%        hour = [7     8     9     10    11    12 ]
                    1200, 1800, 1500, 1100, 1000, 900,... % [veh/hour]
...%        hour = [13   14    15    16    17    18  ]
                    950, 1000, 1100, 1600, 1900, 1700,... % [veh/hour]
...%        hour = [19    20   21   22   23   24 ]
                    1200, 800, 500, 350, 250, 200]; % [veh/hour]
%           hour = [1    2    3    4    5    6  ]
MDOT_outflow_hour =[180, 160, 150, 140, 180, 450,... % [veh/hour]
...%        hour = [7     8     9     10    11    12 ]
                    1000, 1600, 1700, 1300, 1200, 1100,... % [veh/hour]
...%        hour = [13    14    15    16    17    18  ]
                    1150, 1200, 1300, 1800, 2100, 2000,... % [veh/hour]
...%        hour = [19    20    21   22   23   24 ]
                    1500, 1000, 700, 450, 300, 220]; % [veh/hour]
q_in_hour  = MDOT_inflow_hour  / 3600; % [veh/s]
q_out_hour = MDOT_outflow_hour / 3600; % [veh/s]
fprintf('Done Loading MDOT data...\n')
% ====================================================================
%% =================== Simulation Setup ==============================
% ====================================================================
t = 0:sim.dt:sim.T_end;                     % time vector
Nt = numel(t);                              % time vector length

mph_to_fts = 5280/3600;                     % unit conversion

road.Nx = road.length/sim.dx;               % number of road segments
x_edges = 0:sim.dx:road.length;             % cell boundaries
x_centers = x_edges(1:end-1) + sim.dx/2;   % cell centers

u_free = zeros(1, road.Nx);                 % [ft/s] initialize speed limit vector
idx_30 = x_centers>=3501 & x_centers<=5500;% 30 mph segments
idx_40 = ~idx_30;                           % 40 mph segments
u_free(idx_30) = 30*mph_to_fts;
u_free(idx_40) = 40*mph_to_fts;
FD.vf = u_free;

FD.rho_c = FD.rho_j/2;                     % [veh/ft] critical density
FD.Q = @(rho, vf) rho.*vf.*(1 - rho./FD.rho_j); % Greenshields FD

N_lanes = zeros(1, road.Nx);               % lanes per segment
N_lanes(x_centers>=   1 & x_centers<=2000) = 4;
N_lanes(x_centers>=2001 & x_centers<=3000) = 3;
N_lanes(x_centers>=3001 & x_centers<=3500) = 5;
N_lanes(x_centers>=3501 & x_centers<=4500) = 3;
N_lanes(x_centers>=4501 & x_centers<=5500) = 2;
N_lanes(x_centers>=5501 & x_centers<=6500) = 3;

signal.cell   = find(x_centers >= signal.x, 1);
signal.period = signal.green + signal.red;
signal.Qsat   = signal.Qsat_per_lane * N_lanes(signal.cell);
is_signal     = false(1, road.Nx);
is_signal(signal.cell) = true;

% Map each access point to a road segment
access.xSegment = zeros(1, Naccess);
for k = 1:Naccess
    access.xSegment(k) = find( ...
        x_edges(1:end-1) <= access.xLocation(k) & ...
        x_edges(2:end)   >  access.xLocation(k), 1, 'first');
end
access.log = zeros(road.Nx, Nt); % [veh/ft/s] source/sink log for visualization

% ====================================================================
%% ================ Initialize State Variables =======================
% ====================================================================
rho(:,1) = 0.6*FD.rho_c;
rho(signal.cell-1:signal.cell+1, 1) = 0.9*FD.rho_c;
F  = zeros(road.Nx+1, Nt);
g = zeros(1,Nt-1);
g_eff = zeros(road.Nx, Nt-1);
fprintf('\n BEGIN SIMULATION \n')
fprintf('==================\n')
% ====================================================================
%% ====================== Sim Solver Loop ============================
% ====================================================================
for n = 1:Nt-1
    h = hourIndex(t(n));
    fprintf('Sim Time: %6.0f || Hour idx: %3.0f\n', t(n), h)
    % Signal state
    if mod(t(n), signal.period) < signal.green
        g(n) = 1;
    else
        g(n) = 0;
    end

    % Compute flux within boundaries
    for i = 1:road.Nx-1
        F_base = godunovFlux(FD, rho(i,n), rho(i+1,n), FD.vf(i), N_lanes(i), 1);
        if is_signal(i)
            F(i+1,n) = min(F_base, g(n)*signal.Qsat);
        else
            F(i+1,n) = F_base;
        end
        g_eff(i,n) = is_signal(i) * g(n);
    end

    % Upstream boundary (south outflow)
    if rho(1,n) <= FD.rho_c
        S1 = FD.Q(FD.rho_c, FD.vf(1));
    else
        S1 = FD.Q(rho(1,n), FD.vf(1));
    end
    F(1,n) = min(q_in_hour(h), S1);

    % Downstream boundary (north inflow)
    if rho(road.Nx,n) <= FD.rho_c
        D_Nx = FD.Q(rho(road.Nx,n), FD.vf(end));
    else
        D_Nx = FD.Q(FD.rho_c, FD.vf(end));
    end
    F(road.Nx+1,n) = min(q_out_hour(h), D_Nx);

    % Update density: LWR finite-volume + demand-model source/sink terms
    for i = 1:road.Nx
        % Compute source/sink from 4-step demand model
        acc_match = find(i == access.xSegment, 1, 'first');
        if ~isempty(acc_match)
            % q_arrive: vehicles leaving the arterial (sink, negative contribution)
            % q_depart: vehicles entering the arterial (source, positive contribution)
            q_arr = access.V_arrive(acc_match) * access.f_arrive(h, acc_match) / 3600;
            q_dep = access.V_depart(acc_match) * access.f_depart(h, acc_match) / 3600;
            % Net source term [veh/ft/s]: positive = adds vehicles to road
            s = (q_dep - q_arr) / sim.dx;
        else
            s = 0;
        end
        access.log(i,n) = s;
        rho(i,n+1) = rho(i,n) - (sim.dt/sim.dx)*(F(i+1,n) - F(i,n)) + sim.dt*s;
    end
end

% ====================================================================
%% ======================== Plot Results =============================
% ====================================================================

%% Demand Model Summary
fprintf('\n========== 4-Step Demand Model Summary ==========\n');
fprintf('%-20s %10s %10s %10s\n', 'Zone', 'P [p-t/d]', 'A [p-t/d]', 'P-A');
for iz = 1:Nzones
    fprintf('%-20s %10.0f %10.0f %10.0f\n', ...
        demand.zone_names{iz}, demand.P(iz), demand.A(iz), ...
        demand.P(iz) - demand.A(iz));
end
fprintf('%-20s %10.0f %10.0f\n', 'TOTAL', sum(demand.P), sum(demand.A));
fprintf('\nOD Matrix [vehicle-trips/day]:\n');
header = sprintf('%15s', '');
for j = 1:Nzones
    header = [header sprintf('%15s', demand.zone_names{j}(1:min(end,12)))]; %#ok<AGROW>
end
fprintf('%s\n', header);
for i = 1:Nzones
    row = sprintf('%15s', demand.zone_names{i}(1:min(end,12)));
    for j = 1:Nzones
        row = [row sprintf('%15.0f', demand.T_vehicle(i,j))]; %#ok<AGROW>
    end
    fprintf('%s\n', row);
end
fprintf('\nAccess Point Daily Flows:\n');
fprintf('%-35s %12s %12s\n', 'Access Point', 'Arrive[veh]', 'Depart[veh]');
for k = 1:Naccess
    fprintf('%-35s %12.0f %12.0f\n', access.name(k), ...
        access.V_arrive(k), access.V_depart(k));
end
fprintf('==================================================\n\n');

%% Space-Time Density Diagram
figure('Name','spaceTimeDiagram')
imagesc(t/3600, x_centers, rho)
colorbar
xlabel('Time [hr]')
ylabel('Position [ft]')
title('Space-Time Density Diagram')

%% Signal Timing
signal_band = zeros(size(g_eff));
g_signalPlot = g;
g_signalPlot(g==0) = -1;
signal_band(signal.cell, :) = g_signalPlot;
figure('Name','Signal Space-Time')
imagesc(t/60, x_centers, signal_band)
colormap([0.6 0 0;1 1 1; 0 0.6 0])
clim([-1 1])
colorbar('Ticks',[-1 0 1],'TickLabels',{'Red','No Signal','Green'})
xlabel('Time [min]')
ylabel('Position [ft]')
title('Signal Location and Timing')

%% Road Geometry
plotRoadGeometry(sim, road, x_edges, x_centers, N_lanes, signal, access);

%% Source/Sink Flows (Demand Model Output)
figure('Name','Access Point Flows (Demand Model)')
hours_vec = 1:24;
for k = 1:Naccess
    subplot(Naccess, 1, k)
    q_arr_hourly = access.V_arrive(k) * access.f_arrive(:,k)' / 3600; % [veh/s]
    q_dep_hourly = access.V_depart(k) * access.f_depart(:,k)' / 3600; % [veh/s]
    plot(hours_vec, q_arr_hourly*3600, 'r-', 'LineWidth', 1.5); hold on
    plot(hours_vec, q_dep_hourly*3600, 'b-', 'LineWidth', 1.5);
    ylabel('[veh/hr]')
    title(access.name(k), 'FontSize', 8)
    legend('Arrivals (sink)', 'Departures (source)', 'Location', 'best', 'FontSize', 7)
    grid on; xlim([1 24])
end
xlabel('Hour of Day')
sgtitle('Access Point Hourly Flows from 4-Step Demand Model')

%% Net Source/Sink Contribution Along Corridor Over Time
figure('Name','Net Source-Sink Log')
active_log = access.log(access.xSegment, :);
for k = 1:Naccess
    subplot(Naccess, 1, k)
    plot(t/3600, active_log(k,:), 'LineWidth', 1)
    ylabel('[veh/ft/s]')
    title(access.name(k), 'FontSize', 8)
    grid on
end
xlabel('Time [hr]')
sgtitle('Net Source/Sink Term in LWR Equation [veh/ft/s]')

%% OD Matrix Heatmap
figure('Name','OD Matrix (Vehicle Trips/Day)')
imagesc(demand.T_vehicle)
colorbar
xticks(1:Nzones); xticklabels(demand.zone_names); xtickangle(30)
yticks(1:Nzones); yticklabels(demand.zone_names)
xlabel('Destination Zone')
ylabel('Origin Zone')
title('OD Matrix: Vehicle Trips per Day (Gravity Model)')
for i = 1:Nzones
    for j = 1:Nzones
        text(j, i, sprintf('%.0f', demand.T_vehicle(i,j)), ...
            'HorizontalAlignment','center','FontSize',7,'Color','w')
    end
end

% ====================================================================
%% ====================== Helper Functions ===========================
% ====================================================================
function F = godunovFlux(FD, rhoL, rhoR, vf, N_lanes, g)
% godunovFlux
% Computes the Godunov numerical flux for the LWR traffic model
% using the Greenshields Fundamental Diagram.
%
% INPUTS:
%   FD       - struct with .rho_j, .rho_c, .Q
%   rhoL     - upstream density [veh/ft/lane]
%   rhoR     - downstream density [veh/ft/lane]
%   vf       - free-flow speed [ft/s]
%   N_lanes  - number of lanes at interface
%   g        - signal state (1=green, 0=red)
% OUTPUT:
%   F        - flux across boundary [veh/s]

if rhoL <= FD.rho_c
    D = FD.Q(rhoL, vf);
else
    D = FD.Q(FD.rho_c, vf);
end

if rhoR <= FD.rho_c
    S = FD.Q(FD.rho_c, vf);
else
    S = FD.Q(rhoR, vf);
end

F = g * N_lanes * min(D, S);
end

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

figure('Name','Road Geometry','Color','w');
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
    taz_colors = [0.2 0.6 1.0; 0.2 0.8 0.4]; % blue=MainCampus, green=Shopping
    taz_labels = {'Campus','Shopping'};
    for k = 1:length(access.xSegment)
        y = x_centers(access.xSegment(k));
        taz_k = access.taz_idx(k);
        faceColor = taz_colors(taz_k, :);
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
