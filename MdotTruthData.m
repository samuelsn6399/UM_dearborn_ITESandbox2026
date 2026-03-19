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
function truth = MdotTruthData(roadway)
% ====================================================================
%% =============== MDOT Data Inputs (Truth Data) =====================
% ====================================================================
if roadway == "Evergreen Rd Southbound"
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
elseif roadway == "Evergreen Rd Northbound"
    %           hour = [1    2    3    4    5    6  ]
    MDOT_inflow_hour =[180, 160, 150, 140, 180, 450,... % [veh/hour]
    ...%        hour = [7     8     9     10    11    12 ]
                        1000, 1600, 1700, 1300, 1200, 1100,... % [veh/hour]
    ...%        hour = [13    14    15    16    17    18  ]
                        1150, 1200, 1300, 1800, 2100, 2000,... % [veh/hour]
    ...%        hour = [19    20    21   22   23   24 ]
                        1500, 1000, 700, 450, 300, 220]; % [veh/hour]
    
    %           hour = [1    2    3    4    5     6 ]
    MDOT_outflow_hour = [200, 180, 160, 150, 200, 500,... % [veh/hour]
    ...%        hour = [7     8     9     10    11    12 ]
                        1200, 1800, 1500, 1100, 1000, 900,... % [veh/hour]
    ...%        hour = [13   14    15    16    17    18  ]
                        950, 1000, 1100, 1600, 1900, 1700,... % [veh/hour]
    ...%        hour = [19    20   21   22   23   24 ]
                        1200, 800, 500, 350, 250, 200]; % [veh/hour]
elseif roadway == "Hubbard Rd Eastbound"
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
elseif roadway == "Hubbard Rd Westbound"
    %           hour = [1    2    3    4    5    6  ]
    MDOT_inflow_hour =[180, 160, 150, 140, 180, 450,... % [veh/hour]
    ...%        hour = [7     8     9     10    11    12 ]
                        1000, 1600, 1700, 1300, 1200, 1100,... % [veh/hour]
    ...%        hour = [13    14    15    16    17    18  ]
                        1150, 1200, 1300, 1800, 2100, 2000,... % [veh/hour]
    ...%        hour = [19    20    21   22   23   24 ]
                        1500, 1000, 700, 450, 300, 220]; % [veh/hour]
    
    %           hour = [1    2    3    4    5     6 ]
    MDOT_outflow_hour = [200, 180, 160, 150, 200, 500,... % [veh/hour]
    ...%        hour = [7     8     9     10    11    12 ]
                        1200, 1800, 1500, 1100, 1000, 900,... % [veh/hour]
    ...%        hour = [13   14    15    16    17    18  ]
                        950, 1000, 1100, 1600, 1900, 1700,... % [veh/hour]
    ...%        hour = [19    20   21   22   23   24 ]
                        1200, 800, 500, 350, 250, 200]; % [veh/hour]
else
    error("MDOTTRUTHDATA: No Roadway Found")
end

truth.MDOT_inflow_s  = MDOT_inflow_hour  / 3600; % [veh/s]
truth.MDOT_outflow_s = MDOT_outflow_hour / 3600; % [veh/s]
end