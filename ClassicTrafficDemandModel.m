% ====================================================================
%% ITE Sandbox Competition 2026: University of Michigan - Dearborn
% ====================================================================
% ====================================================================
% DESCRIPTION:
% EVERGREENRDSOUTHBOUND.m
% The function configures the Evergreen Rd southbound corridor properties
% used in the simulation
% x = 0 at NORTH end; x = 6500 at SOUTH end
% INPUTS:
% sim       -> a struct storing the simulation properties
% OUTPUTS:
% road      -> a struct storing the roadway properties
%   ^ name
%   ^ length
%   ^ signal
%       ^ x
%       ^ green
%       ^ red
%       ^ Qsat_per_lane
%   ^ 
% =====================================================================
function demand = ClassicTrafficDemandModel(zone)

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

% ---- Step 4 Parameters: Route Choice ----
% ???

fprintf('Done configuring 4-step model parameters...\n')

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
Nzones = length(zone.names);
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
        d_ij = sqrt( (zone.xLocation(i) - zone.xLocation(j))^2 + ...
                     (zone.yLocation(i) - zone.yLocation(j))^2 ); % [ft]
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

end