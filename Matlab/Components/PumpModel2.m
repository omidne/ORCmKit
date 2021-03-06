function [out,TS] = PumpModel2(P_su, h_su, P_ex, fluid, M_dot, param)

%% CODE DESCRIPTION
% ORCmKit - an open-source modelling library for ORC systems

% Remi Dickes - 01/06/2016 (University of Liege, Thermodynamics Laboratory)
% rdickes @ulg.ac.be
%
% "PumpModel2.m" is a single matlab function implementing three different modelling
% approaches to simulate a volumetric pump (see the
% Documentation/PumpModel_MatlabDoc). Unlike "PumpModel.m" which imposes N_pp 
% and deduces the mass flow rate, "PumpModel2.m" imposes the mass flow rate
% and derives the corresponding pump rotational speed.
%
% The model inputs are:
%       - P_su: inlet pressure of the WF                          	[Pa]
%       - h_su: inlet temperature of the WF                        	[J/kg]
%       - P_ex: outlet pressure of the WF                          	[Pa]
%       - fluid: nature of the fluid (string)                       [-]
%       - M_dot: fluid mass flow rate                             	[kg/s]
%       - param: structure variable containing the model parameters
%
% The model paramters provided in 'param' depends of the type of model selected:
%       - if param.modelType = 'CstEff':
%           param.V_s , machine displacement volume                	[m3]
%           param.V, volume of the pump                             [m^3]
%           param.epsilon_is, isentropic efficiency                	[-]
%           param.epsilon_vol, volumetric efficiency               	[-]
%           param.displayResults, flag to display the results or not[1/0]
%
%       - if param.modelType = 'PolEff':
%           param.V_s , machine displacement volume                	[m3]
%           param.V, volume of the pump                             [m^3]
%           param.M_dot_nom, nominal mass flow                   	[rpm]
%           param.coeffPol_is, polynmial coef for epsilon_is        [-]
%           param.coeffPol_vol, polynmial coef for epsilon_vol      [-]
%           param.displayResults, flag to display the results or not[1/0]
%
%       - if param.modelType = 'SemiEmp':
%           param.V_s , machine displacement volume               	[m3]
%           param.V, volume of the pump                             [m^3]
%           param.A_leak, leakage surface area                     	[m2]
%           param.W_dot_loss, constant power losses                	[W]
%           param.K_0_loss, term for the proportional losses       	[-]
%           param.displayResults, flag to display the results or not [1/0]
%
% The model outputs are:
%       - out: a structure variable which includes
%               - T_ex =  exhaust temperature                    [K]
%               - h_ex =  exhaust enthalpy                       [J/kg]
%               - N_pp = pump rotational speed                   [rpm]
%               - W_dot = mechanical power                       [W]
%               - epsilon_is = isentropic efficiency             [-]
%               - epsilon_vol = volumetric efficiency            [-]
%               - M = mass of fluid inside the pump              [kg]
%               - time = the code computational time             [sec]
%               - flag = simulation flag                         [-1/1]
%
%       - TS : a stucture variable which contains the vectors of temperature
%              and entropy of the fluid (useful to generate a Ts diagram 
%              when modelling the entire ORC system 
%
% See the documentation for further details or contact rdickes@ulg.ac.be


%% DEMONSTRATION CASE

if nargin == 0
    
    % Define a demonstration case if PumpModel.mat is not executed externally
    fluid = 'R245fa';               %Nature of the fluid
    P_su = 4.0001e5;                %Supply pressure        [Pa]
    P_ex = 3.6510e+06*0.99;         %Exhaust pressure       [Pa]
    h_su = 2.6676e+05;              %Supply enthalpy        [J/kg]
    M_dot = 0.1;                    %Mass flow rate         [kg/s]
    param.modelType = 'CstEff';     %Type of model          [CstEff, PolEff, SemiEmp]
    param.displayResults = 1;       %Flag to control the resustl display [0/1]
    
    switch param.modelType
        case 'CstEff'
            param.V_s = 1e-6;               %Machine swepts volume  [m^3]
            param.V =1.4e-3;                %Volume inside the pump
            param.epsilon_is = 0.5;         %Cst isentropic efficiency [-]
            param.epsilon_vol = 0.8;        %Cst volumetric efficiency [-]
        case 'PolEff'
            param.V_s = 1e-6;               %Machine swepts volume  [m^3]
            param.V =1.4e-3;                %Volume inside the pump

        case 'SemiEmp'
            param.V_s = 1e-6;               %Machine swepts volume  [m^3]
            param.V =1.4e-3;                %Volume inside the pump

    end
end

tstart_pp = tic;                    %Start to evaluate the simulation time

%% PUMP MODELING
% Modelling section of the code
if not(isfield(param, 'displayResults'))
    param.displayResults = 0;
    %if nothing specified by the user, the results are not displayed by
    %default.
end

if not(isfield(param,'h_min'))
    param.h_min =  CoolProp.PropsSI('H','P',5e4,'T',253.15,fluid);
end
if not(isfield(param,'h_max'))
    param.h_max =  CoolProp.PropsSI('H','P',4e6,'T',500,fluid);
end

T_su = CoolProp.PropsSI('T','P',P_su,'H',h_su,fluid);
s_su = CoolProp.PropsSI('S','P',P_su,'H',h_su,fluid);
rho_su = CoolProp.PropsSI('D','P',P_su,'H',h_su,fluid);
            
if P_su < P_ex && M_dot > 0      
   %If the external conditions are viable, we proceed to the modeling
    
    switch param.modelType
    %Select the proper model paradigm chosen by the user
        case 'CstEff'       
            h_ex_s = CoolProp.PropsSI('H','P',P_ex,'S',s_su,fluid);
            V_s = param.V_s;
            epsilon_is = param.epsilon_is;
            epsilon_vol = param.epsilon_vol;
            N_pp  = 60*M_dot/(epsilon_vol*V_s*rho_su);
            W_dot = M_dot*(h_ex_s-h_su)/epsilon_is;
            h_ex = h_su+W_dot/M_dot;
            if h_ex > param.h_min && h_ex < param.h_max
                out.flag = 1;
            else
                out.flag = -1;
            end
        case 'PolEff'
            h_ex_s = CoolProp.PropsSI('H','P',P_ex,'S',s_su,fluid);
            V_s = param.V_s;
            M_dot_nom = param.M_dot_nom;
            a_is = param.coeffPol_is;
            a_vol = param.coeffPol_vol;
            epsilon_is = max(0.01,min(a_is(1) + a_is(2)*(P_ex/P_su) + a_is(3)*(M_dot/M_dot_nom) + a_is(4)*(P_ex/P_su)^2 + a_is(5)*(P_ex/P_su)*(M_dot/M_dot_nom) + a_is(6)*(M_dot/M_dot_nom)^2,1));
            epsilon_vol = max(0.01,min(a_vol(1) + a_vol(2)*(P_ex/P_su) + a_vol(3)*(M_dot/M_dot_nom) + a_vol(4)*(P_ex/P_su)^2 + a_vol(5)*(P_ex/P_su)*(M_dot/M_dot_nom) + a_vol(6)*(M_dot/M_dot_nom)^2,1));
            N_pp  = 60*M_dot/(epsilon_vol*V_s*rho_su);
            W_dot = max(0,M_dot*(h_ex_s-h_su)/epsilon_is);
            h_ex = h_su+W_dot/M_dot;
            if h_ex > param.h_min && h_ex < param.h_max
                out.flag = 1;
            else
                out.flag = -1;
            end
        case 'SemiEmp'
            h_ex_s = CoolProp.PropsSI('H','P',P_ex,'S',s_su,fluid);
            V_s = param.V_s;
            A_leak = param.A_leak;
            W_dot_loss = param.W_dot_0_loss;
            K_0_loss = param.K_0_loss;
            M_dot_leak = A_leak*sqrt(2*rho_su*(P_ex-P_su));
            M_dot_th = M_dot-M_dot_leak;
            N_pp = 60*M_dot_th/(V_s*rho_su);
            epsilon_vol = M_dot/(N_pp/60*V_s*rho_su);
            W_dot = W_dot_loss + K_0_loss*M_dot/rho_su*(P_ex-P_su);
            epsilon_is = (M_dot*(h_ex_s-h_su))/W_dot;
            h_ex = h_su+W_dot/M_dot;
            if h_ex > param.h_min && h_ex < param.h_max
                out.flag = 1;
            else
                out.flag = -1;
            end
        otherwise
            disp('Error: type of pump model not valid');
    end  
  
else 
    % If the external conditions are not viable, we fake a perfect machine 
    % but we notice the user with a negative flag
    out.flag = -2;
end

if out.flag > 0
    out.h_ex = h_ex;
    out.T_ex = CoolProp.PropsSI('T','P',P_ex,'H',out.h_ex,fluid);
    out.N_pp = N_pp;
    out.W_dot = W_dot;
    out.epsilon_is = epsilon_is;
    out.epsilon_vol = epsilon_vol;
    out.M = (CoolProp.PropsSI('D','H',h_su,'P',P_su,fluid)+CoolProp.PropsSI('D','H',out.h_ex,'P',P_ex,fluid))/2*param.V;
else
    out.T_ex = T_su;
    out.h_ex = h_su;
    h_ex_s = CoolProp.PropsSI('H','P',P_ex,'S',s_su,fluid);
    out.N_pp = 60*M_dot/(param.V_s*rho_su);
    out.W_dot = M_dot*(h_ex_s-h_su);
    out.epsilon_is = 1;
    out.epsilon_vol = 1;
    out.M =(CoolProp.PropsSI('D','H',h_su,'P',P_su,fluid)+CoolProp.PropsSI('D','H',out.h_ex,'P',P_ex,fluid))/2*param.V;
end
out.time = toc(tstart_pp);

%% TS DIAGRAM and DISPLAY

% Generate the output variable TS 
TS.T = [T_su out.T_ex];
TS.s = [s_su CoolProp.PropsSI('S','H',out.h_ex,'P',P_ex,fluid)];

% If the param.displayResults flag is activated (=1), the results are displayed on the
% command window
if param.displayResults ==1
    in.fluid = fluid;
    in.N_pp = N_pp;
    in.T_su = T_su;
    in.h_su = h_su;
    in.P_su = P_su;
    in.P_su = P_ex;
    in.V_s = param.V_s;
    in.modelType= param.modelType;
    if nargin ==0
        fprintf ( 1, '\n' );
        disp('-------------------------------------------------------')
        disp('--------------------   Demo Code   --------------------')
        disp('-------------------------------------------------------')
        fprintf ( 1, '\n' );
    end
    disp('Working conditions:')
    fprintf ( 1, '\n' );
    disp(in)
    disp('Results:')
    disp(out)
end
end

