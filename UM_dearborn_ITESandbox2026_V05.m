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
%% Simulation Settings (User Input)
sim.dt      = 1;                 % [s] time step
sim.dx      = 500;               % [ft] spatial cell length
sim.T_end   = 24*3600;           % [s] total simulation time
fprintf('Done setting up simulation...\n')

%% Configure Road Geometry (User Input)
road.name = 'Evergreen Rd';
road.length = 6500;     % [ft]
fprintf('Done configuring road geometry...\n')

%% Traffic Flow Model (User Input)
FD.model = "Greenshields"; % only one model currently supported
FD.rho_j = 1/18;    % [veh/ft/lane] jamming density
fprintf('Done selecting traffic flow model...\n')

%% Road 1 Signal Configuration - Evergreen Rd Southbound (User Input)
% x = 0 at NORTH end; x = 6500 at SOUTH end
signal.x = 6000; % [ft]
signal.green = 45; % [s] signal green time
signal.red = 75; % [s] signal red time
signal.Qsat_per_lane = 1900/3600; % [veh/s/lane]
fprintf('Done configuring Road 1 (SB) signal...\n')

%% Road 2 Configuration - Evergreen Rd Northbound (User Input)
% x = 0 at SOUTH end; x = 6500 at NORTH end
% Access point and signal positions use NB coordinates: x_NB = 6500 - x_SB
road2.name   = 'Evergreen Rd - Northbound';
road2.length = 6500; % [ft]

% Signal 2: mirrors physical intersection at SB x=6000 → NB x = 6500-6000 = 500 ft
signal2.x              = 500;          % [ft]
signal2.green          = 45;           % [s]
signal2.red            = 75;           % [s]
signal2.Qsat_per_lane  = 1900/3600;    % [veh/s/lane]

% Lane counts for Road 2 segments (NB, x=0 is SOUTH)
% Each entry is the number of lanes in the corresponding physical segment.
%               Seg:  [ 1,  2,  3,  4,  5,  6]
%        x-range (ft): [0-1k,1k-2k,2k-3k,3k-3.5k,3.5k-4.5k,4.5k-6.5k]
% Mirrors SB physical: [5.5k-6.5k,4.5k-5.5k,3.5k-4.5k,3k-3.5k,2k-3k,0-2k]
road2.seg_lanes = [2, 1, 3, 4, 3, 4]; % [lanes] user-confirmed per segment
fprintf('Done configuring Road 2 (NB)...\n')

%% 4-Step Demand Model Parameters (User Input)
% ---- Zone Definitions ----
demand.zone_names = {'MainCampus',    'ShoppingCenter', 'StudentHousing', ...
                     'NorthBoundary', 'SouthBoundary',  'EastBoundary'};
% Approximate zone centroid position along the N-S corridor axis [ft]
% x = 0 ft is the NORTH end; x = road.length is the SOUTH end.
% y = 0 ft is the WEST end; y = road2.length is the EAST end. (road2 does not exist in sim yet)
% Zones beyond the corridor are boundaries: NorthBoundary has x < 0, SouthBoundary has x > road.length.
%           key: [Campus, Shop, StudHsg, North, South, East]
demand.zone_x  = [3500,   6000,  1000, -2000,   9000, 1000]; % [ft]
% Off-corridor lateral offset for zones not on the main road axis [ft]
%           key: [Campus, Shop, StudHsg, North, South, East]
demand.zone_dy = [   0,      0,  5000,     0,      0, 5280];  % [ft]
% Note: the west end of the east-west corridor terminates at the north-south corridor

% ---- Access Point Definitions ----
% These define driveway locations where vehicles enter/exit
% the arterial. A TAZ can be split between multiple access points.
MainCampus_access.name = ["University Secondary Entrance 1", ...
               "University Primary Entrance",     ...
               "University Tertiary Entrance",    ...
               "University Secondary Entrance 2"];
MainCampus_access.xLocation = [1700, 3200, 4500, 5400]; % [ft] along corridor
% Fraction of that TAZ's total corridor flow assigned to each access point
% (campus splits must sum to 1.0)
MainCampus_access.taz_split = [0.10, 0.60, 0.20, 0.10];
ShoppingCenter_access.name = "Shopping Center";
ShoppingCenter_access.xLocation = demand.zone_x(2); % shopping center location

% ---- Step 1 Parameters: Attraction Model ----
% Linear model: A_zone = rate_emp*Employment + rate_enroll*Enrollment
%               + rate_retail*RetailArea (NCHRP 716 Table 3-8 guidance)
demand.attr_rates = [1.5,    ...  % [person-trips/job/day]
                     0.1,    ...  % [person-trips/student/day]
                     0.002]; ...  % [person-trips/sqft/day]

% ---- Step 2 Parameters: Gravity Model ----
% Friction factor: F(t_ij) = exp(-beta * t_ij)
% beta controls how sensitive trip distribution is to travel time
demand.v_avg_mph = 35;                  % [mph] average corridor travel speed
demand.beta      = 0.12;               % [1/min] friction factor decay rate

% ---- Step 3 Parameters: Mode Choice ----
demand.auto_occupancy = 1.25;           % [persons/vehicle] average occupancy

% ---- Step 4 Parameters: Temporal Distribution ----
% Each TAZ has an arrival peak (inbound) and departure peak (outbound)
% Arrivals effectively become sinks from the roadway's perspective
% Departures become sources from the roadway's perspective
demand.taz_peak_arrive = [8, 13, 12, 12, 12, 12];      % [hour of day] arrival peak per TAZ
demand.taz_sigma_arrive = [1.5, 2.0, 5, 5, 5, 5];  % [hours] arrival peak spread per TAZ
demand.taz_peak_depart = [17, 14, 12, 12, 12, 12];    % [hour of day] departure peak per TAZ
demand.taz_sigma_depart = [1.5, 2.0, 5, 5, 5, 5]; % [hours] departure peak spread per TAZ
fprintf('Done configuring 4-step model parameters...\n')

% ====================================================================
%% =============== Check For Valid User Inputs =======================
% ====================================================================
assert(sim.dt > 0, "Time step must be positive")
assert(mod(road.length, sim.dx) == 0, ...
    "Road length must be divisible by dx")
assert(88*sim.dt/sim.dx <= 1, ...
    "CFL condition violated - reduce dt or increase dx")
assert(abs(sum(MainCampus_access.taz_split) - 1.0) < 1e-6, ...
    "Campus access point TAZ splits must sum to 1.0")
assert(mod(road2.length, sim.dx) == 0, ...
    "Road 2 length must be divisible by sim.dx")
assert(length(road2.seg_lanes) == 6, ...
    "Road 2 must have exactly 6 lane segments defined")
fprintf('Done checking for valid inputs...\n')

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
fprintf('Done loading household data...\n')

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
fprintf('Done loading trip production data...\n')

% ====================================================================
%% =========== Load Attraction Parameter Data ========================
% ====================================================================
% AttractionParameters sheet: rows = zones, cols = [Employment, Enrollment, RetailArea]
AP_raw = readmatrix(filename_tripRateData, 'Sheet', 'AttractionParameters');
AP_raw = AP_raw(1:end, 2:end); % omit zone name column and header row
% Columns: [Employment [jobs], Enrollment [students], RetailArea [sqft]]
demand.AttractionParams = AP_raw; % Nzones x 3 matrix
fprintf('Done loading trip attraction data...\n')

% ====================================================================
%% ============= 4-STEP TRAVEL DEMAND MODEL ==========================
% ====================================================================
%% Step 1a: Trip Productions (Cross-Classification)
% P_i = sum over all (autos, household-size) cells of H_i(a,s) * R_i(a,s)
% Units: [person-trips/day] produced by zone i
% temporary change: increase north boundary trip production to align with MDOT data
H_list = {H_mainCampus, H_shoppingCenter, H_studentHousing, ...
          H_northBoundary, H_southBoundary, H_eastBoundary};
R_list = {R_mainCampus, R_shoppingCenter, R_studentHousing, ...
          R_northBoundary, R_southBoundary, R_eastBoundary};
Nzones = length(demand.zone_names);
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
% Scale attractions so sum(A) = sum(P) by holding trip productions, P,
% constant and scaling trip attractions, A
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

% Daily vehicle trips arriving at / departing from each TAZ
% Arrivals: sum of T_vehicle(other_taz -> this_taz) for each k
% Departures: sum of T_vehicle(this_taz -> other_taz) for each k
demand.V_taz_arrive = zeros(1, Nzones); % [veh/day]
demand.V_taz_depart = zeros(1, Nzones); % [veh/day]
for k = 1:Nzones
    this_taz = k;
    other_taz = ismember(1:Nzones, k);
    demand.V_taz_arrive(this_taz) = sum(demand.T_vehicle(other_taz, this_taz));
    demand.V_taz_depart(this_taz) = sum(demand.T_vehicle(this_taz, other_taz));
end
fprintf('Done loading 4-step model...\n')

% ====================================================================
%% ============= Generate Hourly Temporal Factors ====================
% ====================================================================
% Convert daily vehicle volumes to hourly rates using parametric Gaussian peaks
% f_norm(h) = fraction of daily traffic in hour h  [24-element vector]
% Arrival and departure profiles are computed per TAZ
% Per-TAZ temporal profiles (parametricPeaks returns raw Gaussian; normalize)
demand.f_arrive = zeros(24, Nzones);
demand.f_depart = zeros(24, Nzones);
for k = 1:Nzones
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

    demand.f_arrive(:, k) = f_norm_arr(:);
    demand.f_depart(:, k) = f_norm_dep(:);
end
% Convert daily flow across the boundaries to hourly rates
% In-flow and out-flow profiles computed per boundary taz
% boundary.f = zeros([size(boundary.V_pass),24]);
% % boundar.f(1,1,1) = [boundary 1, inflow, hour 1]
% for z = 1:length(external_idx)
%     F_in.w = 1;
%     F_in.mu = boundary.taz_peak_inflow(z);
%     F_in.sigma = boundary.taz_peak_inflow(z);
%     f_raw_in = parametricPeaks(F_in);
%     f_norm_in = f_raw_in/sum(f_raw_in);
%     F_out.w = 1;
%     F_out.mu = boundary.taz_peak_outflow(z);
%     F_out.sigma = boundary.taz_peak_outflow(z);
%     f_raw_out = parametricPeaks(F_out);
%     f_norm_out = f_raw_out/sum(f_raw_out);
%     boundary.f(z,1,:) = f_norm_in;
%     boundary.f(z,2,:) = f_norm_out;
% end
fprintf('Done loading temporal factors...\n')

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
MDOT_inflow_s  = MDOT_inflow_hour  / 3600; % [veh/s]
MDOT_outflow_s = MDOT_outflow_hour / 3600; % [veh/s]

% Road 2 (NB): inflow enters from SOUTH boundary; outflow exits at NORTH boundary
% NB peak pattern is approximately the reverse of SB (PM-heavy inflow, AM-heavy outflow)
MDOT_inflow_hour_NB  = MDOT_outflow_hour; % [veh/hr] NB inflow mirrors SB outflow pattern
MDOT_outflow_hour_NB = MDOT_inflow_hour;  % [veh/hr] NB outflow mirrors SB inflow pattern
MDOT_inflow_s_NB  = MDOT_inflow_hour_NB  / 3600; % [veh/s]
MDOT_outflow_s_NB = MDOT_outflow_hour_NB / 3600;  % [veh/s]
fprintf('Done loading MDOT data...\n')

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
NmainCampus_access = length(MainCampus_access.xLocation);
MainCampus_access.xSegment = zeros(1, NmainCampus_access);
for k = 1:NmainCampus_access
    MainCampus_access.xSegment(k) = find( ...
        x_edges(1:end-1) <= MainCampus_access.xLocation(k) & ...
        x_edges(2:end)   >  MainCampus_access.xLocation(k), 1, 'first');
end
NshoppingCenter_access = length(ShoppingCenter_access.xLocation);
ShoppingCenter_access.xSegment = find( ...
        x_edges(1:end-1) <= ShoppingCenter_access.xLocation & ...
        x_edges(2:end)   >  ShoppingCenter_access.xLocation, 1, 'first');
access_combine.log = zeros(road.Nx, Nt); % [veh/ft/s] source/sink log for visualization
fprintf('Done setting up Road 1 (SB)...\n')

% ====================================================================
%% =========== Road 2 (Northbound) Simulation Setup ==================
% ====================================================================
road2.Nx     = road2.length / sim.dx;
x_edges2     = 0:sim.dx:road2.length;
x_centers2   = x_edges2(1:end-1) + sim.dx/2;

% Speed limits for Road 2 (mirrored from Road 1)
% SB 30 mph zone x=3501–5500 maps to NB x=1000–2999 → use x=1001–3000
u_free2 = zeros(1, road2.Nx);
idx_30_2 = x_centers2 >= 1001 & x_centers2 <= 3000; % 30 mph
idx_40_2 = ~idx_30_2;                                % 40 mph
u_free2(idx_30_2) = 30*mph_to_fts;
u_free2(idx_40_2) = 40*mph_to_fts;
FD2    = FD;   % same fundamental diagram model and jam density
FD2.vf = u_free2;

% Lane counts per segment for Road 2 (NB)
N_lanes2 = zeros(1, road2.Nx);
N_lanes2(x_centers2 >=    1 & x_centers2 <= 1000) = road2.seg_lanes(1); % 2 lanes
N_lanes2(x_centers2 >= 1001 & x_centers2 <= 2000) = road2.seg_lanes(2); % 1 lane
N_lanes2(x_centers2 >= 2001 & x_centers2 <= 3000) = road2.seg_lanes(3); % 3 lanes
N_lanes2(x_centers2 >= 3001 & x_centers2 <= 3500) = road2.seg_lanes(4); % 4 lanes
N_lanes2(x_centers2 >= 3501 & x_centers2 <= 4500) = road2.seg_lanes(5); % 3 lanes
N_lanes2(x_centers2 >= 4501 & x_centers2 <= 6500) = road2.seg_lanes(6); % 4 lanes

% Signal 2 setup
signal2.cell   = find(x_centers2 >= signal2.x, 1);
signal2.period = signal2.green + signal2.red;
signal2.Qsat   = signal2.Qsat_per_lane * N_lanes2(signal2.cell);
is_signal2     = false(1, road2.Nx);
is_signal2(signal2.cell) = true;

% Map Road 2 access points to road segments
% Physical positions are mirrored: x_NB = road.length - x_SB
% Sorted ascending so they appear south-to-north on the NB road
MainCampus_access2.xLocation = sort(road.length - MainCampus_access.xLocation, 'ascend');
%   NB: [1100, 2000, 3300, 4800] ft  (mirrors SB: [5400,4500,3200,1700])
MainCampus_access2.name      = ["University Secondary Entrance 2", ...
                                 "University Tertiary Entrance",    ...
                                 "University Primary Entrance",     ...
                                 "University Secondary Entrance 1"];
MainCampus_access2.taz_split = [0.10, 0.20, 0.60, 0.10];

ShoppingCenter_access2.xLocation = road.length - ShoppingCenter_access.xLocation;
%   NB: 500 ft  (mirrors SB: 6000 ft)
ShoppingCenter_access2.name = ShoppingCenter_access.name;

NmainCampus_access2 = length(MainCampus_access2.xLocation);
MainCampus_access2.xSegment = zeros(1, NmainCampus_access2);
for k = 1:NmainCampus_access2
    MainCampus_access2.xSegment(k) = find( ...
        x_edges2(1:end-1) <= MainCampus_access2.xLocation(k) & ...
        x_edges2(2:end)   >  MainCampus_access2.xLocation(k), 1, 'first');
end
NshoppingCenter_access2 = length(ShoppingCenter_access2.xLocation);
ShoppingCenter_access2.xSegment = find( ...
    x_edges2(1:end-1) <= ShoppingCenter_access2.xLocation & ...
    x_edges2(2:end)   >  ShoppingCenter_access2.xLocation, 1, 'first');

access_combine2.log = zeros(road2.Nx, Nt); % [veh/ft/s] source/sink log
fprintf('Done setting up Road 2 (NB)...\n')

% ====================================================================
%% ================ Initialize State Variables =======================
% ====================================================================
% Road 1 (SB)
rho = zeros(road.Nx,Nt);
rho(:,1) = 0.6*FD.rho_c;
rho(signal.cell-1:signal.cell+1, 1) = 0.9*FD.rho_c;
F      = zeros(road.Nx+1, Nt);
g      = zeros(1, Nt-1);
g_eff  = zeros(road.Nx, Nt-1);

% Road 2 (NB)
rho2 = zeros(road2.Nx,Nt);
rho2(:,1) = 0.6*FD2.rho_c;
rho2(signal2.cell-1:signal2.cell+1, 1) = 0.9*FD2.rho_c;
F2     = zeros(road2.Nx+1, Nt);
g2     = zeros(1, Nt-1);
g_eff2 = zeros(road2.Nx, Nt-1);
fprintf('\n BEGIN SIMULATION \n')
fprintf('==================\n')

% ====================================================================
%% ====================== Sim Solver Loop ============================
% Both roads advance in parallel within a single time loop.
% Road segment loops are independent and uncoupled.
% ====================================================================
for n = 1:Nt-1
    h = hourIndex(t(n));
    fprintf('Sim Time: %6.0f || Hour idx: %3.0f\n', t(n), h)

    % ----------------------------------------------------------------
    %% Road 1 (Southbound) — x=0 at North, x=6500 at South
    % ----------------------------------------------------------------

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

    % Upstream boundary (north inflow)
    if rho(1,n) <= FD.rho_c
        S1 = FD.Q(FD.rho_c, FD.vf(1));
    else
        S1 = FD.Q(rho(1,n), FD.vf(1));
    end
    F(1,n) = demand.V_taz_depart(4) * demand.f_depart(h,4) / 3600; % (veh/s) inbound flux across Northern Boundary

    % Downstream boundary (south outflow)
    if rho(road.Nx,n) <= FD.rho_c
        D_Nx = FD.Q(rho(road.Nx,n), FD.vf(end));
    else
        D_Nx = FD.Q(FD.rho_c, FD.vf(end));
    end
    F(road.Nx+1,n) = demand.V_taz_arrive(5) * demand.f_arrive(h,5) / 3600; % (veh/s) outbound flux across Southern boundary

    % Update density: LWR finite-volume + demand-model source/sink terms
    for i = 1:road.Nx
        s1 = 0;
        s2 = 0;
        MainCampus_access_match = find(i == MainCampus_access.xSegment, 1, 'first');
        if ~isempty(MainCampus_access_match)
            q_arr = demand.V_taz_arrive(1) * demand.f_arrive(h, 1) / 3600 * MainCampus_access.taz_split(MainCampus_access_match);
            q_dep = demand.V_taz_depart(1) * demand.f_depart(h, 1) / 3600 * MainCampus_access.taz_split(MainCampus_access_match);
            s1 = (q_dep - q_arr) / sim.dx;
        end
        ShoppingCenter_access_match = find(i == ShoppingCenter_access.xSegment, 1, 'first');
        if ~isempty(ShoppingCenter_access_match)
            q_arr = demand.V_taz_arrive(2) * demand.f_arrive(h, 2) / 3600;
            q_dep = demand.V_taz_depart(2) * demand.f_depart(h, 2) / 3600;
            s2 = (q_dep - q_arr) / sim.dx;
        end
        s = s1 + s2;
        access_combine.log(i,n) = s;
        rho(i,n+1) = rho(i,n) - (sim.dt/sim.dx)*(F(i+1,n) - F(i,n)) + sim.dt*s;
    end

    % ----------------------------------------------------------------
    %% Road 2 (Northbound) — x=0 at South, x=6500 at North
    % ----------------------------------------------------------------

    % Signal state
    if mod(t(n), signal2.period) < signal2.green
        g2(n) = 1;
    else
        g2(n) = 0;
    end

    % Compute flux within boundaries
    for i = 1:road2.Nx-1
        F2_base = godunovFlux(FD2, rho2(i,n), rho2(i+1,n), FD2.vf(i), N_lanes2(i), 1);
        if is_signal2(i)
            F2(i+1,n) = min(F2_base, g2(n)*signal2.Qsat);
        else
            F2(i+1,n) = F2_base;
        end
        g_eff2(i,n) = is_signal2(i) * g2(n);
    end

    % Upstream boundary (south inflow for NB road)
    if rho2(1,n) <= FD2.rho_c
        S1_2 = FD2.Q(FD2.rho_c, FD2.vf(1));
    else
        S1_2 = FD2.Q(rho2(1,n), FD2.vf(1));
    end
    % SouthBoundary zone (index 5) departures heading north
    F2(1,n) = demand.V_taz_depart(5) * demand.f_depart(h,5) / 3600;

    % Downstream boundary (north outflow for NB road)
    if rho2(road2.Nx,n) <= FD2.rho_c
        D_Nx2 = FD2.Q(rho2(road2.Nx,n), FD2.vf(end));
    else
        D_Nx2 = FD2.Q(FD2.rho_c, FD2.vf(end));
    end
    % NorthBoundary zone (index 4) arrivals coming from south
    F2(road2.Nx+1,n) = demand.V_taz_arrive(4) * demand.f_arrive(h,4) / 3600;

    % Update density: LWR finite-volume + demand-model source/sink terms
    for i = 1:road2.Nx
        s_camp2 = 0;
        s_shop2 = 0;
        MainCampus_access_match2 = find(i == MainCampus_access2.xSegment, 1, 'first');
        if ~isempty(MainCampus_access_match2)
            q_arr2  = demand.V_taz_arrive(1) * demand.f_arrive(h,1) / 3600 ...
                      * MainCampus_access2.taz_split(MainCampus_access_match2);
            q_dep2  = demand.V_taz_depart(1) * demand.f_depart(h,1) / 3600 ...
                      * MainCampus_access2.taz_split(MainCampus_access_match2);
            s_camp2 = (q_dep2 - q_arr2) / sim.dx;
        end
        ShoppingCenter_access_match2 = find(i == ShoppingCenter_access2.xSegment, 1, 'first');
        if ~isempty(ShoppingCenter_access_match2)
            q_arr2  = demand.V_taz_arrive(2) * demand.f_arrive(h,2) / 3600;
            q_dep2  = demand.V_taz_depart(2) * demand.f_depart(h,2) / 3600;
            s_shop2 = (q_dep2 - q_arr2) / sim.dx;
        end
        s_total2 = s_camp2 + s_shop2;
        access_combine2.log(i,n) = s_total2;
        rho2(i,n+1) = rho2(i,n) - (sim.dt/sim.dx)*(F2(i+1,n) - F2(i,n)) + sim.dt*s_total2;
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

%% Space-Time Density Diagrams
figure('Name','spaceTimeDiagram_Road1')
imagesc(t/3600, x_centers, rho)
colorbar
xlabel('Time [hr]')
ylabel('Position [ft]')
title(['Space-Time Density: ' road.name ' (Southbound)'])

figure('Name','spaceTimeDiagram_Road2')
imagesc(t/3600, x_centers2, rho2)
colorbar
xlabel('Time [hr]')
ylabel('Position [ft]')
title(['Space-Time Density: ' road2.name ' (Northbound)'])

%% OD Tuning – Road 1 (Southbound)
figure('Name', 'odTuning_Road1')
subplot(2,2,1)
hold on
plot(t,F(1,:),'r-','DisplayName','Incoming Flow (OD Model)')
plot(t,[repelem(MDOT_inflow_s,3600),0],'b:','DisplayName','Incoming Flow (MDOT Truth Data)')
hold off; ylabel('Flow (veh/s)'); title('SB: North Boundary Inflow'); xlabel('time (s)'); grid on; legend();
subplot(2,2,2)
northBoundary_inFlow_diff = F(1,:)-[repelem(MDOT_inflow_s,3600),0];
plot(t,northBoundary_inFlow_diff,'r-','DisplayName','OD Model - MDOT Truth Data')
title('SB: Difference North Inflow'); xlabel('time (s)'); grid on; legend();
subplot(2,2,3)
hold on
plot(t,F(road.Nx+1,:),'r-','DisplayName','Outgoing Flow (OD Model)')
plot(t,[repelem(MDOT_outflow_s,3600),0],'b:','DisplayName','Outgoing Flow (MDOT Truth Data)')
hold off; ylabel('Flow (veh/s)'); title('SB: South Boundary Outflow'); xlabel('time (s)'); grid on; legend();
subplot(2,2,4)
southBoundary_outFlow_diff = F(road.Nx+1,:)-[repelem(MDOT_outflow_s,3600),0];
plot(t,southBoundary_outFlow_diff,'r-','DisplayName','OD Model - MDOT Truth Data')
title('SB: Difference South Outflow'); xlabel('time (s)'); grid on; legend();

%% OD Tuning – Road 2 (Northbound)
figure('Name', 'odTuning_Road2')
subplot(2,2,1)
hold on
plot(t,F2(1,:),'r-','DisplayName','Incoming Flow (OD Model)')
plot(t,[repelem(MDOT_inflow_s_NB,3600),0],'b:','DisplayName','Incoming Flow (MDOT Truth Data)')
hold off; ylabel('Flow (veh/s)'); title('NB: South Boundary Inflow'); xlabel('time (s)'); grid on; legend();
subplot(2,2,2)
southBoundary_inFlow_diff2 = F2(1,:)-[repelem(MDOT_inflow_s_NB,3600),0];
plot(t,southBoundary_inFlow_diff2,'r-','DisplayName','OD Model - MDOT Truth Data')
title('NB: Difference South Inflow'); xlabel('time (s)'); grid on; legend();
subplot(2,2,3)
hold on
plot(t,F2(road2.Nx+1,:),'r-','DisplayName','Outgoing Flow (OD Model)')
plot(t,[repelem(MDOT_outflow_s_NB,3600),0],'b:','DisplayName','Outgoing Flow (MDOT Truth Data)')
hold off; ylabel('Flow (veh/s)'); title('NB: North Boundary Outflow'); xlabel('time (s)'); grid on; legend();
subplot(2,2,4)
northBoundary_outFlow_diff2 = F2(road2.Nx+1,:)-[repelem(MDOT_outflow_s_NB,3600),0];
plot(t,northBoundary_outFlow_diff2,'r-','DisplayName','OD Model - MDOT Truth Data')
title('NB: Difference North Outflow'); xlabel('time (s)'); grid on; legend();

%% Signal Timing – Road 1 (SB)
signal_band = zeros(size(g_eff));
g_signalPlot = g;
g_signalPlot(g==0) = -1;
signal_band(signal.cell, :) = g_signalPlot;
figure('Name','signalSpaceTime_Road1')
imagesc(t/60, x_centers, signal_band)
colormap([0.6 0 0;1 1 1; 0 0.6 0])
clim([-1 1])
colorbar('Ticks',[-1 0 1],'TickLabels',{'Red','No Signal','Green'})
xlabel('Time [min]'); ylabel('Position [ft]')
title(['Signal Location and Timing: ' road.name ' (Southbound)'])

%% Signal Timing – Road 2 (NB)
signal_band2 = zeros(size(g_eff2));
g_signalPlot2 = g2;
g_signalPlot2(g2==0) = -1;
signal_band2(signal2.cell, :) = g_signalPlot2;
figure('Name','signalSpaceTime_Road2')
imagesc(t/60, x_centers2, signal_band2)
colormap([0.6 0 0;1 1 1; 0 0.6 0])
clim([-1 1])
colorbar('Ticks',[-1 0 1],'TickLabels',{'Red','No Signal','Green'})
xlabel('Time [min]'); ylabel('Position [ft]')
title(['Signal Location and Timing: ' road2.name ' (Northbound)'])

%% Road Geometry – Road 1 (SB)
access_combine.name = [MainCampus_access.name ShoppingCenter_access.name];
access_combine.xLocation = [MainCampus_access.xLocation, ShoppingCenter_access.xLocation];
access_combine.xSegment = [MainCampus_access.xSegment, ShoppingCenter_access.xSegment];
plotRoadGeometry(sim, road, x_edges, x_centers, N_lanes, signal, access_combine);

%% Road Geometry – Road 2 (NB)
access_combine2.name = [MainCampus_access2.name ShoppingCenter_access2.name];
access_combine2.xLocation = [MainCampus_access2.xLocation, ShoppingCenter_access2.xLocation];
access_combine2.xSegment = [MainCampus_access2.xSegment, ShoppingCenter_access2.xSegment];
plotRoadGeometry(sim, road2, x_edges2, x_centers2, N_lanes2, signal2, access_combine2);

%% Net Source/Sink – Road 1 (SB)
figure('Name','netSourceSinkLog_Road1')
Naccess_combine = NmainCampus_access + NshoppingCenter_access;
active_log = access_combine.log(access_combine.xSegment, :);
for k = 1:Naccess_combine
    subplot(Naccess_combine, 1, k)
    plot(t/3600, active_log(k,:), 'LineWidth', 1)
    ylabel('[veh/ft/s]')
    title(access_combine.name(k), 'FontSize', 8)
    grid on
end
xlabel('Time [hr]')
sgtitle(['Net Source/Sink Term [veh/ft/s]: ' road.name ' (Southbound)'])

%% Net Source/Sink – Road 2 (NB)
figure('Name','netSourceSinkLog_Road2')
Naccess_combine2 = NmainCampus_access2 + NshoppingCenter_access2;
active_log2 = access_combine2.log(access_combine2.xSegment, :);
for k = 1:Naccess_combine2
    subplot(Naccess_combine2, 1, k)
    plot(t/3600, active_log2(k,:), 'LineWidth', 1)
    ylabel('[veh/ft/s]')
    title(access_combine2.name(k), 'FontSize', 8)
    grid on
end
xlabel('Time [hr]')
sgtitle(['Net Source/Sink Term [veh/ft/s]: ' road2.name ' (Northbound)'])

%% OD Matrix Heatmap
figure('Name','odMatrixVehicleTripsDay')
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
