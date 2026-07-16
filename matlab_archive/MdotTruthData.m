% ====================================================================
%% ITE Sandbox Competition 2026: University of Michigan - Dearborn
% ====================================================================
% DESCRIPTION:
% MDOTTRUTHDATA.m
% The function sets the truth values for simulation tuning. These values
% are outputs only; they are not used to propogate the sim states.
% Two sources are used to provide truth data: Michigan Traffic AADT at
% experience.arcgis.com and MDOT Traffic Viewer at mdot.public.ms2soft.com
% INPUTS:
% roadway    -> a member of the road struct storing the roadway name
% OUTPUTS:
% truth      -> average hourly flow provided truth data for a 24 hour
% period
% =====================================================================
function truth = MdotTruthData(roadway)
% ====================================================================
%% =============== MDOT Data Inputs (Truth Data) =====================
% ====================================================================

% AADT
evergreenRdSouthbound_AADT = 2518; % [vehicles/day] (2025)
evergreenRdNorthbound_AADT = 3042; % [vehicles/day] (2025)
hubbardRdEastbound_AADT = 7280; % [vehicles/day] (2025)
hubbardRdWestbound_AADT = 4497; % [vehicles/day] (2025)

% Temporal Distribution Ratios (Daily -> Hourly)
evergreenRdSouthbound_rawDistribution = ...
    [14, 1, 7, 8, 9, 38, 66, 75, 134, 132, 152, 169, ...
     172, 185, 206, 203, 206, 212, 144, 126, 100, 57, 39, 16]; % [vehicles/hourOfDay] (March 2021)
evergreenRdSouthbound_distribution = ...
    evergreenRdSouthbound_rawDistribution./sum(evergreenRdSouthbound_rawDistribution); % [dimensionless]
evergreenRdNorthbound_rawDistribution = ...
    [23, 10, 10, 5, 14, 21, 85, 109, 155, 155, 173, 165, ...
     229, 223, 275, 262, 237, 249, 198, 138, 127, 78, 46, 35]; % [vehicles/hourOfDay] (March 2021)
evergreenRdNorthbound_distribution = ...
    evergreenRdNorthbound_rawDistribution./sum(evergreenRdNorthbound_rawDistribution); % [dimensionless]
hubbardRdEastbound_rawDistribution = ...
    [36, 38, 17, 22, 17, 38, 72, 108, 161, 238, 331, 491, ...
     610, 524, 638, 647, 683, 596, 598, 532, 309, 172, 133, 69]; % [vehicles/hourOfDay] (July 2021)
hubbardRdEastbound_distribution = ...
    hubbardRdEastbound_rawDistribution./sum(hubbardRdEastbound_rawDistribution); % [dimensionless]
hubbardRdWestbound_rawDistribution = ...
    [31, 18, 16, 19, 21, 51, 136, 192, 236, 236, 330, 335, ...
     376, 372, 370, 370, 363, 355, 298, 173, 150, 90, 80, 38]; % [vehicles/hourOfDay] (July 2021)
hubbardRdWestbound_distribution = ...
    hubbardRdWestbound_rawDistribution./sum(hubbardRdWestbound_rawDistribution); % [dimensionless]

if roadway == "Evergreen Rd Southbound"
    AADT = evergreenRdSouthbound_AADT;
    hourlyDistribution = evergreenRdSouthbound_distribution;
elseif roadway == "Evergreen Rd Northbound"
    AADT = evergreenRdNorthbound_AADT;
    hourlyDistribution = evergreenRdNorthbound_distribution;
elseif roadway == "Hubbard Rd Eastbound"
    AADT = hubbardRdEastbound_AADT;
    hourlyDistribution = hubbardRdEastbound_distribution;
elseif roadway == "Hubbard Rd Westbound"
    AADT = hubbardRdWestbound_AADT;
    hourlyDistribution = hubbardRdWestbound_distribution;
else
    error("MDOTTRUTHDATA: No Roadway Found")
end

% inflow equals outflow by conservation of cars; assuming equivalent
% temporal factors and a very small time delay between inflow and outflow
% dynamics
truth.MDOT_inflow  = AADT.*hourlyDistribution./ 3600; % [veh/s]
truth.MDOT_outflow  = AADT.*hourlyDistribution./ 3600; % [veh/s]
end