%{
----------------------------------------------------------------------------

This file is part of the Sanworks Bpod repository
Copyright (C) 2016 Sanworks LLC, Sound Beach, New York, USA

----------------------------------------------------------------------------

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, version 3.

This program is distributed  WITHOUT ANY WARRANTY and without even the 
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
%}
function CW_Light2AFC
% This protocol is a visual 2AFC task for use with the Choice Wheel module.
% Port 2 is lit for an idle period at the beginning of each trial.
% After keeping the wheel still for 1 second,
% a light flashes to indicate the correct side - port 1 (left) or port 3 (right).
% The subject is rewarded for choosing the side that was lit, by rocking
% the choice wheel in that direction. 
% Written by Josh Sanders, 12/2016.
%
% SETUP
% You will need:
% - A Bpod MouseBox (or equivalent) configured with 3 ports.
% > Display Port1 LED on the left side of the subject.
% > Display Port3 LED on the right side of the subject.
% > Display Port2 LED in front of the subject, and connect its valve to a lickometer.
% > The choice ball module connected to a Bpod serial port by CAT6 cable, and to the Bpod computer by USB cable 
% > Make sure the liquid calibration table for port 2 is set up.

global BpodSystem

%% Define parameters
S = BpodSystem.ProtocolSettings; % Load settings chosen in launch manager into current workspace as a struct called S
if isempty(fieldnames(S))  % If settings file was an empty struct, populate struct with default settings
    S.GUI.RewardAmount = 3; %ul
    S.GUI.CueDelay = 1; % How long the mouse must stop moving to initiate the trial
    S.GUI.CueDelayMotionGrace = 10; % How many degrees the wheel can turn during the CueDelay without triggering a CueDelay period reset.
    S.GUI.CueDuration = 0.1; % Duration of the visual cue
    S.GUI.leftResponsePosition = 160; % Each trial begins with the wheel at 180 degrees. Rocking the wheel to this position indicates a left choice.
    S.GUI.rightResponsePosition = 200; % Each trial begins with the wheel at 180 degrees. Rocking the wheel to this position indicates a right choice.
    S.GUI.ResponseTimeout = 5; % How long until the subject must make a choice, or forefeit the trial
    S.GUI.PunishDelay = 3; % How long the subject must wait before a trial can start if it made an error
end

%% Define trials
MaxTrials = 5000;
TrialTypes = ceil(rand(1,MaxTrials)*2);
BpodSystem.Data.TrialTypes = []; % The trial type of each trial completed will be added here.
BpodSystem.Data.WheelData = cell(1,1);

%% Initialize plots
BpodSystem.ProtocolFigures.SideOutcomePlotFig = figure('Position', [50 540 1000 200],'name','Outcome plot','numbertitle','off', 'MenuBar', 'none', 'Resize', 'off');
BpodSystem.GUIHandles.SideOutcomePlot = axes('Position', [.075 .3 .89 .6]);
SideOutcomePlot(BpodSystem.GUIHandles.SideOutcomePlot,'init',2-TrialTypes);
BpodParameterGUI('init', S); % Initialize parameter GUI plugin

%% Initialize ChoiceWheel system
Wheel = ChoiceWheelModule('/dev/cu.usbmodem1421'); % Set to the correct COM port for ChoiceWheel on your system

%% Main trial loop
for currentTrial = 1:MaxTrials
    S = BpodParameterGUI('sync', S); % Sync parameters with BpodParameterGUI plugin
    R = GetValveTimes(S.GUI.RewardAmount, [1 3]); LeftValveTime = R(1); RightValveTime = R(2); % Update reward amounts
    setChoiceWheelSettings(Wheel, S);
    switch TrialTypes(currentTrial) % Determine trial-specific state matrix fields
        case 1
            LeftChoiceAction = 'LeftReward'; RightChoiceAction = 'Punish'; StimulusOutput = {'PWM1', 255};
        case 2
            LeftChoiceAction = 'Punish'; RightChoiceAction = 'RightReward'; StimulusOutput = {'PWM3', 255};
    end
    % Assemble state machine
    sma = NewStateMachine();
    sma = AddState(sma, 'Name', 'TrialStart', ...
        'Timer', 0,...
        'StateChangeConditions', {'Tup', 'CueDelay'},...
        'OutputActions', {'Serial1', 'T'}); % Code to start the trial
    sma = AddState(sma, 'Name', 'CueDelay', ...
        'Timer', 0,...
        'StateChangeConditions', {'Serial1_4', 'DeliverCue'},...
        'OutputActions', {'PWM2', 64});
    sma = AddState(sma, 'Name', 'DeliverCue', ...
        'Timer', S.GUI.CueDuration,...
        'StateChangeConditions', {'Tup', 'WaitForResponse', 'Serial1_1', LeftChoiceAction, 'Serial1_2', RightChoiceAction, 'Serial1_3', 'exit'},...
        'OutputActions', StimulusOutput);
    sma = AddState(sma, 'Name', 'WaitForResponse', ...
        'Timer', 0,...
        'StateChangeConditions', {'Serial1_1', LeftChoiceAction, 'Serial1_2', RightChoiceAction, 'Serial1_3', 'exit'},...
        'OutputActions', {}); 
    sma = AddState(sma, 'Name', 'LeftReward', ...
        'Timer', LeftValveTime,...
        'StateChangeConditions', {'Tup', 'Drinking'},...
        'OutputActions', {'Valve', 1}); 
    sma = AddState(sma, 'Name', 'RightReward', ...
        'Timer', RightValveTime,...
        'StateChangeConditions', {'Tup', 'Drinking'},...
        'OutputActions', {'Valve', 3}); 
    sma = AddState(sma, 'Name', 'Drinking', ...
        'Timer', 0.5,...
        'StateChangeConditions', {'Tup', 'exit', 'Port2In', 'DrinkingGrace'},...
        'OutputActions', {});
    sma = AddState(sma, 'Name', 'DrinkingGrace', ...
        'Timer', 0,...
        'StateChangeConditions', {'Tup', 'Drinking'},...
        'OutputActions', {});
    sma = AddState(sma, 'Name', 'Punish', ...
        'Timer', 0.1,...
        'StateChangeConditions', {'Tup', 'PunishDelay'},...
        'OutputActions', {'LED', 1, 'LED', 2, 'LED', 3});
    sma = AddState(sma, 'Name', 'PunishDelay', ...
        'Timer', S.GUI.PunishDelay,...
        'StateChangeConditions', {'Tup', 'exit'},...
        'OutputActions', {});
    SendStateMatrix(sma);
    Wheel.runTrial('SerialStart')
    RawEvents = RunStateMatrix;
    if ~isempty(fieldnames(RawEvents)) % If trial data was returned
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Computes trial events from raw data
        BpodSystem.Data.TrialSettings(currentTrial) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
        BpodSystem.Data.TrialTypes(currentTrial) = TrialTypes(currentTrial); % Adds the trial type of the current trial to data
        UpdateSideOutcomePlot(TrialTypes, BpodSystem.Data);
        BpodSystem.Data.WheelData{currentTrial} = Wheel.getLastTrialData;
        SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
    end
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end
end

function UpdateSideOutcomePlot(TrialTypes, Data)
global BpodSystem
Outcomes = zeros(1,Data.nTrials);
for x = 1:Data.nTrials
    if ~isnan(Data.RawEvents.Trial{x}.States.Drinking(1))
        Outcomes(x) = 1;
    elseif ~isnan(Data.RawEvents.Trial{x}.States.Punish(1))
        Outcomes(x) = 0;
    else
        Outcomes(x) = 3;
    end
end
SideOutcomePlot(BpodSystem.GUIHandles.SideOutcomePlot,'update',Data.nTrials+1,2-TrialTypes,Outcomes);

function setChoiceWheelSettings(Wheel, S)
Wheel.autoSync = 0;
Wheel.idleTime2Start = S.GUI.CueDelay;
Wheel.leftThreshold = S.GUI.leftResponsePosition;
Wheel.rightThreshold = S.GUI.rightResponsePosition;
Wheel.timeout = S.GUI.ResponseTimeout;
Wheel.idleTimeMotionGrace = S.GUI.CueDelayMotionGrace;
Wheel.syncParams();
Wheel.autoSync = 1;