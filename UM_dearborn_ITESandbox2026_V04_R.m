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
% ====================================================================
% RELEASE VERSION – USER GUIDE:
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

%% Configure Road Geometry (User Input)
road.name = 'Evergreen Rd';
road.length = 6500;     % [ft]

%% Traffic Flow Model (User Input)
FD.model = "Greenshields"; % only one model currently supported
FD.rho_j = 1/18;    % [veh/ft/lane] jamming density

%% Signal Configuration (User Input)
signal.x = 6000; % [ft]
signal.green = 45; % [s] signal green time
signal.red = 75; % [s] signal red time
signal.Qsat_per_lane = 1900/3600; % [veh/s/lane] STANDARD ITE METRIC??? NEEDS RESEARCH

%% Source and Sinks (User Input)
% source.source:
%   +1 = adds vehicles to road
%   -1 = removes vehicles from road
%    0 = inactive
source.name      = ["University Secondary Entrance 1",...
                    "University Primary Entrance",...
                    "University Tertiary Entrance",...
                    "University Secondary Entrance 2",...
                    "Shopping Center Entrance"];
source.xLocation = [1700,3200,4500,5400,6000]; % [ft] location of source/sink
source.rho       = [0.004,... % [Percent of critical density] peak density from secondary entrance
                    0.010,... % [Percent of critical density] peak density from primary campus entrance
                    0.003,... % [Percent of critical density] peak density from tertiary entrance
                    0.002,... % [Percent of critical density] peak density from secondary entrance
                    0.006]; % [Percent of critical density] peak density from shopping center
source.peakTime  = [ 7,... % [hour of day] time of peak from secondary entrance
                     8,... % [hour of day] time of peak from primary campus entrance
                    17,... % [hour of day] time of peak from tertiary entrance
                    16,... % [hour of day] time of peak from secondary entrance
                    13]; % [hour of day] time of peak from shopping center
source.source    = [-1,... % entering campus (sink)
                    -1,... % entering campus (sink)
                     1,... % leaving campus (source)
                     1,... % leaving campus (source)
                    -1]; % entering shopping center (sink)

% ====================================================================
%% =============== Check For Valid User Inputs =======================
% ====================================================================
assert(sim.dt > 0, "Time step must be positive")
assert(mod(road.length, sim.dx) == 0, ...
    "Road length must be divisible by dx")
assert(88*sim.dt/sim.dx <= 1, ...
    "CFL condition violated — reduce dt or increase dx")


% ====================================================================
%% ==================== Load House Hold Data =========================
% ====================================================================
filename_householdData = "HouseholdData.xlsx";
H_mainCampus = readmatrix(filename_householdData,'Sheet','MainCampus');
H_mainCampus = H_mainCampus(2:end-1,2:end-1); % omit row titles, column titles and totals
H_shoppingCenter = readmatrix(filename_householdData,'Sheet','ShoppingCenter');
H_shoppingCenter = H_shoppingCenter(2:end-1,2:end-1); % omit row titles, column titles and totals
H_studentHousing = readmatrix(filename_householdData,'Sheet','StudentHousing');
H_studentHousing = H_studentHousing(2:end-1,2:end-1); % omit row titles, column titles and totals
H_northBoundary = readmatrix(filename_householdData,'Sheet','NorthBoundary');
H_northBoundary = H_northBoundary(2:end-1,2:end-1); % omit row titles, column titles and totals
H_southBoundary = readmatrix(filename_householdData,'Sheet','SouthBoundary');
H_southBoundary = H_southBoundary(2:end-1,2:end-1); % omit row titles, column titles and totals
H_eastBoundary = readmatrix(filename_householdData,'Sheet','EastBoundary');
H_eastBoundary = H_eastBoundary(2:end-1,2:end-1); % omit row titles, column titles and totals

% ====================================================================
%% =============== Load Trip Production Rate Data ====================
% ====================================================================
filename_tripRateData = "TripRateData.xlsx";
R_mainCampus = readmatrix(filename_tripRateData,'Sheet','MainCampus');
R_mainCampus = R_mainCampus(2:end-1,2:end-1); % omit row titles, column titles and totals
R_shoppingCenter = readmatrix(filename_tripRateData,'Sheet','ShoppingCenter');
R_shoppingCenter = R_shoppingCenter(2:end-1,2:end-1); % omit row titles, column titles and totals
R_studentHousing = readmatrix(filename_tripRateData,'Sheet','StudentHousing');
R_studentHousing = R_studentHousing(2:end-1,2:end-1); % omit row titles, column titles and totals
R_northBoundary = readmatrix(filename_tripRateData,'Sheet','NorthBoundary');
R_northBoundary = R_northBoundary(2:end-1,2:end-1); % omit row titles, column titles and totals
R_southBoundary = readmatrix(filename_tripRateData,'Sheet','SouthBoundary');
R_southBoundary = R_southBoundary(2:end-1,2:end-1); % omit row titles, column titles and totals
R_eastBoundary = readmatrix(filename_tripRateData,'Sheet','EastBoundary');
R_eastBoundary = R_eastBoundary(2:end-1,2:end-1); % omit row titles, column titles and totals

% ====================================================================
%% ================== Generate Hourly Factors ========================
% ====================================================================
% w = peak weight [fraction of daily traffic]
% mu = peak time [hour of day (1-24)]
% sigma = peak duration 1-sigma value[hours]
% N = num peaks
% summation of gaussian distribution function for each N to get hourly
% factor
F_mainCampus.w = [1]; F_mainCampus.mu = [16]; F_mainCampus.sigma = [1];
f_mainCampus = parametricPeaks(F_mainCampus);
F_shoppingCenter.w = [1]; F_shoppingCenter.mu = [16]; F_shoppingCenter.sigma = [1];
f_shoppingCenter = parametricPeaks(F_shoppingCenter);
F_studentHousing.w = [1]; F_studentHousing.mu = [16]; F_studentHousing.sigma = [1];
f_studentHousing = parametricPeaks(F_studentHousing);
F_northBoundary.w = [1]; F_northBoundary.mu = [16]; F_northBoundary.sigma = [1];
f_northBoundary = parametricPeaks(F_northBoundary);
F_southBoundary.w = [1]; F_southBoundary.mu = [16]; F_southBoundary.sigma = [1];
f_southBoundary = parametricPeaks(F_southBoundary);
F_eastBoundary.w = [1]; F_eastBoundary.mu = [16]; F_eastBoundary.sigma = [1];
f_eastBoundary = parametricPeaks(F_eastBoundary);
figure('Name','debugHourlyFactors')
plot(f_mainCampus)
grid on

% ====================================================================
%% ==================== Load Trip Rate Data ==========================
% ====================================================================

% ====================================================================
%% ================= Load Attraction Rate Data =======================
% ====================================================================

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
q_in_hour = MDOT_inflow_hour/3600; % [veh/sec] convert to sim time step units
q_out_hour = MDOT_outflow_hour/3600; % [veh/sec] convert to sim time step units

% ====================================================================
%% =================== Simulation Setup ==============================
% ====================================================================
t = 0:sim.dt:sim.T_end;                     % time vector
Nt = numel(t);                              % time vecotr length

mph_to_fts = 5280/3600;                     % unit conversion

road.Nx = road.length/sim.dx;               % number of road segments
x_edges = 0:sim.dx:road.length;             % cell boundaries
x_centers = x_edges(1:end-1) + sim.dx/2;    % cell centers

u_free = zeros(1,road.Nx);                  % [ft/s] initialize speed limit vector
idx_30 = x_centers>=3501 & x_centers<=5500; % 30 mph segments
idx_40 = ~idx_30;                           % 40 mph segments
u_free(idx_30) = 30*mph_to_fts;             % [ft/s] set the speed limit
u_free(idx_40) = 40*mph_to_fts;             % [ft/s] set the speed limit
FD.vf = u_free;                             % add speed limit to fundamental diagram

FD.rho_c = FD.rho_j/2;                      % [veh/ft] critical density
FD.Q = @(rho, vf) rho.*vf.*(1 - rho./FD.rho_j);% Greenshields Fundamental Diagram function

N_lanes = zeros(1, road.Nx);                % define number of lanes on road segment
N_lanes(x_centers>=   1 & x_centers<=2000) = 4;
N_lanes(x_centers>=2001 & x_centers<=3000) = 3;
N_lanes(x_centers>=3001 & x_centers<=3500) = 5;
N_lanes(x_centers>=3501 & x_centers<=4500) = 3;
N_lanes(x_centers>=4501 & x_centers<=5500) = 2;
N_lanes(x_centers>=5501 & x_centers<=6500) = 3;

signal.cell = find(x_centers>=signal.x,1);  % setup signal logic
signal.period = signal.green + signal.red;  % [s] one green-red cycle
signal.Qsat = signal.Qsat_per_lane * N_lanes(signal.cell);
is_signal = false(1,road.Nx);
is_signal(signal.cell) = true;

source.rho = source.rho.*FD.rho_c;
source.xSegment =  zeros(size(source.xLocation)); % convert position in feet to a road segment
for k = 1:length(source.xLocation)
    source.xSegment(k) = find( ...
        x_edges(1:end-1) <= source.xLocation(k) & ...
        x_edges(2:end)   >  source.xLocation(k), ...
        1, 'first');
end
source.log = zeros(road.Nx,Nt); % initialize a log of the source and sink contribution to traffic

% ====================================================================
%% ================ Initialize State Variables =======================
% ====================================================================
% initialized to 60% the critical density
rho(:,1) = 0.6*FD.rho_c;                % background traffic at sim start
rho(signal.cell-1:signal.cell+1,1) = 0.9*FD.rho_c;  % pre-existing queue at stop light is 90% the critical density
F  = zeros(road.Nx+1,Nt);               % initialize total flow  [veh/s]
g_eff = zeros(road.Nx,Nt-1);            % initialize effective signal at segment boundaries

% ====================================================================
%% ====================== Sim Solver Loop ============================
% ====================================================================
% time loop
for n = 1:Nt-1
    if mod(t(n), signal.period) < signal.green
        g(n) = 1;
    else
        g(n) = 0;
    end

    % Compute flux within boundaries
    for i = 1:road.Nx-1
        F_base = godunovFlux( ...
            FD, ...
            rho(i,n), ...
            rho(i+1,n), ...
            FD.vf(i), ...
            N_lanes(i), ...
            1);
        
        % check for stop light signal
        if is_signal(i)
            F(i+1,n) = min(F_base, g(n)*signal.Qsat);
        else
            F(i+1,n) = F_base;
        end
        
        % track signal on/off for visualization
        g_eff(i,n) = is_signal(i) * g(n);
    end

    % Update upstream boundary data (source)
    h = hourIndex(t(n));
    if rho(1,n) <= FD.rho_c
        S1 = FD.Q(FD.rho_c, FD.vf(1)); % Supply at cell 1
    else
        S1 = FD.Q(rho(1,n), FD.vf(1));
    end
    F(1,n) = min(q_in_hour(h), S1);

    % Update downstream boundary data (sink)
    if rho(road.Nx,n) <= FD.rho_c
        D_Nx = FD.Q(rho(road.Nx,n), FD.vf(end)); % Demand at final cell
    else
        D_Nx = FD.Q(FD.rho_c, FD.vf(end));
    end
    F(road.Nx+1,n) = min( q_out_hour(h), D_Nx);

    % Update density based on flux and sources/sinks
    for i = 1:road.Nx
        if any(i==source.xSegment)
            source_idx = find(i==source.xSegment,1,"first");
            source_peakHour = source.peakTime(source_idx);
            source_peak = source.rho(source_idx);
            source_sink = source.source(source_idx);
            source_source = source.source(source_idx);
            s = timeVaryingSource(t(n), source_peakHour, source_peak, source_source); % [cars/ft/s]
        else
            s = 0; % [cars/ft/s]
        end
        source.log(i,n) = s;
        rho(i,n+1) = rho(i,n) - (sim.dt/sim.dx)*(F(i+1,n) - F(i,n)) + sim.dt*s;
    end
end

% ====================================================================
%% ======================== Plot Results =============================
% ====================================================================
% space-time density diagram
figure('Name','spaceTimeDiagram')
imagesc(t/3600, x_centers, rho)
colorbar
xlabel('Time [min]')
ylabel('Position [ft]')
title('Space–Time Density Diagram')

% signals
figure('Name','Signal Timing')
stairs(t(1:Nt-1)/60, g, 'LineWidth', 2)
ylim([-0.1 1.1])
xlabel('Time [min]')
ylabel('Signal State')
title('Signal Green / Red Timing')
yticks([0 1])
yticklabels({'Red','Green'})
grid on

signal_band = zeros(size(g_eff));
signal_band(signal.cell, :) = g;

figure('Name','Signal Space–Time')
imagesc(t/60, x_centers, signal_band)
colormap([1 1 1; 0 0.6 0])   % white=red, green=green
caxis([0 1])
colorbar('Ticks',[0 1],'TickLabels',{'Red','Green'})
xlabel('Time [min]')
ylabel('Position [ft]')
title('Signal Location and Timing')

% road geometry
% custom plotting tool in helper functions below
plotRoadGeometry(sim, road, x_edges, x_centers, N_lanes, signal, source);

% Sources and Sinks
figure('Name','Sources and Sinks')
active_source_log = source.log(source.xSegment,:);
for i_subplot = 1:length(source.xSegment)
    subplot(length(source.xSegment),1,i_subplot)
    plot(t./3600,active_source_log(i_subplot,:))
    ylabel(source.name(i_subplot))
    grid on
end
sgtitle('Source Influence Over Time [rho/lane/s]')
xlabel('Time [hr]')

% ====================================================================
%% ====================== Helper Functions ===========================
% ====================================================================
function F = godunovFlux(FD, rhoL, rhoR, vf, N_lanes, g)
% godunovFlux
% Computes the Godunov numerical flux for the LWR traffic model
% Using Greenshields Fundamental Digram
%
% INPUTS:
%   FD       - struct with .rho_j and .rho_c and .Q
%   rhoL     - upstream density [veh/ft/lane]
%   rhoR     - downstream density [veh/ft/lane]
%   vf       - free-flow speed [ft/s]
%   rho_j    - jam density [veh/ft/lane]
%   N_lanes  - number of lanes at interface
%   g        - signal state (1 = green, 0 = red)
%
% OUTPUT:
%   F        - flux across boundary [veh/s]

% Demand (upstream)
if rhoL <= FD.rho_c
    D = FD.Q(rhoL, vf);
else
    D = FD.Q(FD.rho_c, vf);
end

% Supply (downstream)
if rhoR <= FD.rho_c
    S = FD.Q(FD.rho_c, vf);
else
    S = FD.Q(rhoR, vf);
end

% Godunov flux (per lane)
F_lane = min(D, S);

% Apply lanes and signal
F = g*N_lanes*F_lane;
end

function h = hourIndex(t)
% hourIndex
% Turns the simulation time in seconds into an index value by hour. For
% example, at simulation time 120 seconds, output we are at hour 1. An 
% important note is that this is an index value so no partial hours (ie.
% 0.1).
%
% INPUTS:
%   t     - sim time [s]
% OUTPUT:
%   h     - index  [hr]

h = floor(t/3600) + 1; % [hr]
h = max(1,min(h,24)); % [hr]
end

function plotRoadGeometry(sim, road, x_edges, x_centers, N_lanes, signal, source)
% plotRoadGeometry
% Visualizes a north–south arterial with lane geometry, signals,
% and source/sink locations
%
% INPUT:
%   sim         - struct with .dx and .dt
%   road        - struct with .length, .Nx
%   x_edges     - cell boundary positions [ft]
%   x_centers   - cell center positions [ft]
%   N_lanes     - lanes per segment
%   signal      - struct with .cell (can be scalar or vector)
%   source      - struct with .xSegment, .source, .name

max_lanes = max(N_lanes);

figure('Name','Road Geometry','Color','w');
hold on;
% draw road segments
for i = 1:road.Nx
    y1 = x_edges(i);
    y2 = x_edges(i+1);
    width = N_lanes(i);
    fill([0 width width 0], ...
         [y1 y1 y2 y2], ...
         [0.85 0.85 0.85], ...
         'EdgeColor','none');
    % dashed segment boundary
    plot([0 width],[y1 y1],'k--','LineWidth',0.5);
end

% final boundary
plot([0 max_lanes],[road.length road.length],'k--','LineWidth',0.5);

% plot signal locations (multiple supported) ---
if isfield(signal,'cell') && ~isempty(signal.cell)
    sig_cells = signal.cell(:);
    for k = 1:length(sig_cells)
        y_sig = x_centers(sig_cells(k));
        plot([0 max_lanes],[y_sig y_sig], ...
             'r','LineWidth',3);

        text(max_lanes*0.02, y_sig+80, ...
            'Signal', ...
            'Color','r','FontWeight','bold');
    end
end

% plot sources and sinks
if isfield(source,'xSegment') && ~isempty(source.xSegment)
    band_half_height = sim.dx/2;
    for k = 1:length(source.xSegment)
        y = x_centers(source.xSegment(k));

        % color logic
        if source.source(k) > 0
            faceColor = [0.2 0.6 1.0];   % source (blue)
            label = 'Source';
        elseif source.source(k) < 0
            faceColor = [1.0 0.5 0.2];   % sink (orange)
            label = 'Sink';
        else
            faceColor = [0.6 0.6 0.6];   % inactive
            label = 'Inactive';
        end

        patch([0 max_lanes max_lanes 0], ...
              [y-band_half_height y-band_half_height ...
               y+band_half_height y+band_half_height], ...
              faceColor, ...
              'FaceAlpha',0.18,'EdgeColor','none');

        % text label
        text(max_lanes*0.5, y, ...
            source.name(:,k), ...
            'HorizontalAlignment','center', ...
            'FontSize',9);
    end
end

% formatting
xlim([0 max_lanes])
ylim([0 road.length])
xlabel('Road Width [# lanes]')
ylabel('Distance Along Corridor [ft]')
title(['Road Geometry with Signals and Sources: ', road.name])
set(gca,'YDir','normal','FontSize',11)
grid on
box on


% legend
h_road   = patch(NaN,NaN,[0.85 0.85 0.85],'EdgeColor','none');
h_seg    = plot(NaN,NaN,'k--','LineWidth',0.6);
h_signal = plot(NaN,NaN,'r','LineWidth',3);
h_source = patch(NaN,NaN,[0.2 0.6 1.0],'FaceAlpha',0.25,'EdgeColor','none');
h_sink   = patch(NaN,NaN,[1.0 0.5 0.2],'FaceAlpha',0.25,'EdgeColor','none');
legend([h_road, h_seg, h_signal, h_source, h_sink], ...
       ["Roadway (Lane Geometry)", ...
        "Cell Boundary (FV Segment)", ...
        "Signalized Intersection", ...
        "Traffic Source (Ingress)", ...
        "Traffic Sink (Egress)"], ...
       "Location","eastoutside");
legend boxoff
hold off
end

function s = timeVaryingSource(t, peakHour, peak, source)
% timeVaryingSource
% generates a time varying source/sink
%
% INPUT:
%   t           - sim time [s]
%   peakHour    - hour of the day for peak source or sink influence [hour]
%   peak        - max output or input of cars from the source or sink [rho/s]
%   source      - net source (1) or net sink (-1)
% OUTPUT:
%   s           - net car density per second added or subtracted from roadway

s = source*peak*(1 + cos(pi*t/(12*60*60) + peakHour*60*60))/2;
end

function f = parametricPeaks(peakParameters)
% parametricPeaks
% calculates weights to convert daily traffic volume to hourly volume using
% a gaussian distribution and user specified peaks
%
% INPUT:
%   peakParameters   - User defined weights, duration, and time
% OUTPUT:
%   f                - 24 element vector of weights to convert daily 
%                       volume to hourly

% check size of inputs for number of peaks
N = length(peakParameters.w);
h = 1:24; % vector of 24 hour day
f_prev = zeros(size(h)); % initialize f
% calculate gaussian distribution for each peak and sum
for idx = 1:N
    g = exp(-((h-peakParameters.mu(idx)).^2./(2*peakParameters.sigma(idx).^2)));
    f = peakParameters.w(idx).*g + f_prev;
    f_prev = f;
end
end