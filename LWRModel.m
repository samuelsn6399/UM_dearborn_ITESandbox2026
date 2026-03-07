% ====================================================================
%% ITE Sandbox Competition 2026: University of Michigan - Dearborn
% ====================================================================
% ====================================================================
% DESCRIPTION:
% LWRMODEL.m
% The function uses the Lighthill-Williams-Richards model to calculate
% the density at each road segment
% INPUTS:
% sim       -> a struct storing the simulation properties
% road1     -> a struct storing the road properties and simulation data at n
% OUTPUTS:
% road2     -> a struct storing the road properties and simulation data at n+1
%   ^ name
%   ^ length
%   ^ signal
%       ^ x
%       ^ green
%       ^ red
%       ^ Qsat_per_lane
%   ^ 
% =====================================================================
function [rho_next, F_n, g_n, g_eff_n, s_n] = LWRModel(road, rho_n, demand, zone, sim)
% Signal state
if mod(sim.t(sim.n), road.signal.period) < road.signal.green
    g_n = 1;
else
    g_n = 0;
end

% Compute interior fluxes
F_n     = zeros(road.Nx+1, 1);
g_eff_n = zeros(road.Nx, 1);
for i = 1:road.Nx-1
    F_base = godunovFlux(road.FD, road.FD.vf(i), rho_n(i), rho_n(i+1), road.N_lanes(i));
    if road.is_signal(i)
        F_n(i+1) = min(F_base, g_n * road.signal.Qsat);
    else
        F_n(i+1) = F_base;
    end
    g_eff_n(i) = road.is_signal(i) * g_n;
end

% Boundary fluxes
F_n(1)         = demand.V_taz_depart(road.boundary_idx(1)) * zone.f_depart(sim.h, road.boundary_idx(1)) / 3600; % (veh/s) inbound flux across upstream boundary
F_n(road.Nx+1) = demand.V_taz_arrive(road.boundary_idx(2)) * zone.f_arrive(sim.h, road.boundary_idx(2)) / 3600; % (veh/s) outbound flux across downstream boundary

% Source/sink and density update
Nsource  = length(road.AccessPoints);
s_n      = zeros(road.Nx, 1);
rho_next = zeros(road.Nx, 1);
for i = 1:road.Nx
    s_i = zeros(1, Nsource);
    for j = 1:Nsource
        access_match = find(i == road.AccessPoints(j).xSegment, 1, 'first');
        if ~isempty(access_match)
            q_arr = demand.V_taz_arrive(road.AccessPoints(j).taz_idx) * zone.f_arrive(sim.h, road.AccessPoints(j).taz_idx) / 3600 * road.AccessPoints(j).split(access_match); % [veh/s]
            q_dep = demand.V_taz_depart(road.AccessPoints(j).taz_idx) * zone.f_depart(sim.h, road.AccessPoints(j).taz_idx) / 3600 * road.AccessPoints(j).split(access_match); % [veh/s]
            s_i(j) = (q_dep - q_arr) / sim.dx; % [veh/s/ft]
        end
    end
    s_n(i)      = sum(s_i); % [veh/s/ft]
    rho_next(i) = rho_n(i) - (sim.dt/sim.dx) * (F_n(i+1) - F_n(i)) + sim.dt * s_n(i); % [veh/ft]
end
end

function F = godunovFlux(FD, vf, rhoUp, rhoDown, N_lanes)
% godunovFlux
% Computes the Godunov numerical flux for the LWR traffic model
% using the Greenshields Fundamental Diagram.
%
% INPUTS:
%   FD       - struct with .rho_j, .rho_c, .Q
%   rhoUp    - upstream density [veh/ft/lane]
%   rhoDown  - downstream density [veh/ft/lane]
%   vf       - free-flow speed [ft/s]
%   N_lanes  - number of lanes at interface
%   xSegment - local road segment
% OUTPUT:
%   F        - flux across boundary [veh/s]

if rhoUp <= FD.rho_c
    D = FD.Q(rhoUp, vf);
else
    D = FD.Q(FD.rho_c, vf);
end

if rhoDown <= FD.rho_c
    S = FD.Q(FD.rho_c, vf);
else
    S = FD.Q(rhoDown, vf);
end

F = N_lanes * min(D, S);
end