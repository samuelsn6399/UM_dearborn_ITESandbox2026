% ====================================================================
%% ITE Sandbox Competition 2026: University of Michigan - Dearborn
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
function road = EvergreenRdSouthbound(sim, FD)
%% Configure Road Geometry (User Input)
road.name = 'Evergreen Rd Southbound';
road.idx = 1;
road.length = 6500;     % [ft]
road.Nx = road.length/sim.dx;               % number of road segments
road.x_edges = 0:sim.dx:road.length;             % cell boundaries
road.x_centers = road.x_edges(1:end-1) + sim.dx/2;   % cell centers

%% Set Boundary Conditions For a Road with TAZ's Index
% [inflow, outflow]
road.boundary_idx = [4, 5]; % [North Boundary index, South Boundary index]

%% Configure Lanes and Corridor Width
road.N_lanes = zeros(1, road.Nx);               % lanes at a segment
road.N_lanes(road.x_centers>=   1 & road.x_centers<=2000) = 4;
road.N_lanes(road.x_centers>=2001 & road.x_centers<=3000) = 3;
road.N_lanes(road.x_centers>=3001 & road.x_centers<=3500) = 5;
road.N_lanes(road.x_centers>=3501 & road.x_centers<=4500) = 3;
road.N_lanes(road.x_centers>=4501 & road.x_centers<=5500) = 2;
road.N_lanes(road.x_centers>=5501 & road.x_centers<=6500) = 3;

%% Signal Configuration (User Input)
road.signal.x = 6000; % [ft]
road.signal.green = 45; % [s] signal green time
road.signal.red = 75; % [s] signal red time
road.signal.Qsat_per_lane = 1900/3600; % [veh/s/lane]
road.signal.cell   = find(road.x_centers >= road.signal.x, 1);
road.signal.period = road.signal.green + road.signal.red;
road.signal.Qsat   = road.signal.Qsat_per_lane * road.N_lanes(road.signal.cell);
road.is_signal     = false(1, road.Nx);
road.is_signal(road.signal.cell) = true;

%% Speed Limit Configuration (User Input)
idx_30 = road.x_centers>=3501 & road.x_centers<=5500;% 30 mph segments
idx_40 = ~idx_30;                                    % 40 mph segments
u_free = zeros(1, road.Nx);                 % [ft/s] initialize speed limit vector
u_free(idx_30) = 30*sim.mph_to_fts;
u_free(idx_40) = 40*sim.mph_to_fts;

%% Traffic Flow Model (Inherited From Top Level Sim)
road.FD = FD;
road.FD.vf = u_free;

%% Initialize State Variables 
road.rho = zeros(road.Nx,sim.Nt);
road.rho(:,1) = 0.01*FD.rho_c;
road.rho(max(1,road.signal.cell-1):min(road.Nx,road.signal.cell+1), 1) = 0.01*FD.rho_c;
road.F      = zeros(road.Nx+1, sim.Nt);
road.F_desired      = zeros(2, sim.Nt); % [input_1; output_1 ... input_n; output_n] unsaturated OD model values
road.g      = zeros(1, sim.Nt-1);
road.g_eff  = zeros(road.Nx, sim.Nt-1);
road.s      = zeros(road.Nx,sim.Nt);
end