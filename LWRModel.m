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
function road = LWRModel(road, demand, zone, sim)
% Signal state
if mod(sim.t(sim.n), road.signal.period) < road.signal.green
    road.g(sim.n) = 1;
else
    road.g(sim.n) = 0;
end

% Compute flux within boundaries
for i = 1:road.Nx-1
    F_base = godunovFlux(road.FD, road.FD.vf(i), road.rho(i,sim.n), road.rho(i+1,sim.n), road.N_lanes(i));
    if road.is_signal(i)
        road.F(i+1,sim.n) = min(F_base, road.g(sim.n)*road.signal.Qsat);
    else
        road.F(i+1,sim.n) = F_base;
    end
    road.g_eff(i,sim.n) = road.is_signal(i) * road.g(sim.n);
end

% Upstream boundary
road.F(1,sim.n) = demand.V_taz_depart(road.boundary_idx(1)) * zone.f_depart(sim.h,road.boundary_idx(1)) / 3600; % (veh/s) inbound flux across Northern Boundary

% Downstream boundary; possible problem for cases where boundary is not removing cars fast enough
% possible solution is to let cars flow freely out of the boundary rather than coding a value
road.F(road.Nx+1,sim.n) = demand.V_taz_arrive(road.boundary_idx(2)) * zone.f_arrive(sim.h,road.boundary_idx(2)) / 3600; % (veh/s) outbound flux across Southern boundary

Nsource = length(road.AccessPoints); % number of TAZ's with access points on the road
% Update density: LWR finite-volume + demand-model source/sink terms
for i = 1:road.Nx
    s_n = zeros(1, Nsource); % reset each segment: only one source per TAZ is tracked
    for j = 1:Nsource
        access_match = find(i == road.AccessPoints(j).xSegment, 1, 'first');
        if ~isempty(access_match)
            q_arr = demand.V_taz_arrive(road.AccessPoints(j).taz_idx) * zone.f_arrive(sim.h, road.AccessPoints(j).taz_idx) / 3600 * road.AccessPoints(j).split(access_match); % [veh/s]
            q_dep = demand.V_taz_depart(road.AccessPoints(j).taz_idx) * zone.f_depart(sim.h, road.AccessPoints(j).taz_idx) / 3600 * road.AccessPoints(j).split(access_match); % [veh/s]
            s_n(j) = (q_dep - q_arr) / sim.dx; % [veh/s/ft]
        end
    end
    road.s(i,sim.n) = sum(s_n); % [veh/s/ft] total source and sink effects at a road segment
    road.rho(i,sim.n+1) = road.rho(i,sim.n) - (sim.dt/sim.dx)*(road.F(i+1,sim.n) - road.F(i,sim.n)) + sim.dt*road.s(i,sim.n); % [veh/ft]
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