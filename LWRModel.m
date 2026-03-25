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
function [rho_next, F_n, F_n_desired, g_n, g_eff_n, s_n] = LWRModel(road, rho_n, demand, zone, sim)
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

% Upstream Boundary Fluxes (Inflow)
% Saturatation function for backlog at first road segment
if rho_n(1) <= road.FD.rho_c
    S1 = road.FD.Q(road.FD.rho_c, road.FD.vf(1));
else
    S1 = road.FD.Q(rho_n(1), road.FD.vf(1));
end
if road.boundary_idx(1) == 0 % for roads that originate at an intersection, no boundary condition is applied
    F_n_desired(1) = 0;
else    
    F_n_desired(1) = demand.V_taz_depart(road.idx,road.boundary_idx(1)) * zone.f_depart(sim.h, road.boundary_idx(1)) / 3600; % OD model inbound flux
end
F_n(1) = min(F_n_desired(1), S1*road.N_lanes(1)); % (veh/s) inbound flux across upstream boundary

% Downstream Boundary Fluxes (Outflow)
% Saturatation function to prevent black hole effect at the exit boundary
if rho_n(road.Nx) <= road.FD.rho_c
    D_Nx = road.FD.Q(rho_n(road.Nx), road.FD.vf(road.Nx));
else
    D_Nx = road.FD.Q(road.FD.rho_c, road.FD.vf(road.Nx));
end
if road.boundary_idx(2) == 0 % for roads that terminate at an intersection, no boundary condition is applied
    F_n_desired(2) = 0;
else
    F_n_desired(2) = demand.V_taz_arrive(road.idx,road.boundary_idx(2)) * zone.f_arrive(sim.h, road.boundary_idx(2)) / 3600; % OD model outbound flux
end
F_n(road.Nx+1) = D_Nx*road.N_lanes(road.Nx); % (veh/s) outbound flux across downstream boundary

% Source/sink and density update
Nsource  = length(road.AccessPoints);
s_n      = zeros(road.Nx, 1);
rho_next = zeros(road.Nx, 1);
for i = 1:road.Nx
    s_i = zeros(1, Nsource);
    % calculate s_i; a vector containing the net source and sinks at a
    % segment
    for j = 1:Nsource
        access_match = find(i == road.AccessPoints(j).xSegment, 1, 'first');
        if ~isempty(access_match)
            q_arr = demand.V_taz_arrive(road.idx,road.AccessPoints(j).taz_idx) * zone.f_arrive(sim.h, road.AccessPoints(j).taz_idx) / 3600 * road.AccessPoints(j).split(access_match); % [veh/s]
            q_dep = demand.V_taz_depart(road.idx,road.AccessPoints(j).taz_idx) * zone.f_depart(sim.h, road.AccessPoints(j).taz_idx) / 3600 * road.AccessPoints(j).split(access_match); % [veh/s]
            s_i(j) = (q_dep - q_arr); % [veh/s]
        end
    end
    % append intersection net source and sink effects to s_i
    % intersection(1) because only one intersection point per road
    intersection_match = find(i == road.intersection(1).xSegment, 1, 'first');
    if ~isempty(intersection_match)
        NtazExternal = length(road.intersection(1).taz_idx_external);
        for k = 1:NtazExternal
            if road.idx ~= 3 % Cars never access Hubbard East Bound via the inersection
                q_arr_intersection = demand.V_taz_arrive(road.idx, road.intersection(1).taz_idx_external(k)) * zone.f_arrive(sim.h, road.intersection(1).taz_idx_external(k)) / 3600; % [veh/s]
            else
                q_arr_intersection = 0;
            end
            if road.idx ~= 4 % Cars never leave Hubbard West Bound via the inersection
                q_dep_intersection = demand.V_taz_depart(road.idx, road.intersection(1).taz_idx_external(k)) * zone.f_depart(sim.h, road.intersection(1).taz_idx_external(k)) / 3600; % [veh/s]
            else
                q_dep_intersection = 0;
            end
            s_i(end + k) = (q_dep_intersection - q_arr_intersection); % [veh/s]
        end
    end
    s_n(i)      = sum(s_i); % [veh/s]
    F_n_net = F_n(i) - F_n(i+1);
    rho_next(i) = rho_n(i) + (sim.dt/sim.dx)*(F_n_net + s_n(i)); % [veh/ft]

    if rho_next(i) < 0
        rho_next(i) = 0; % Set density to zero if it becomes negative
    end
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