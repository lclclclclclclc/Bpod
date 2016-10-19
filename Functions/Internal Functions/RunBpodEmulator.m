%{
----------------------------------------------------------------------------

This file is part of the Bpod Project
Copyright (C) 2014 Joshua I. Sanders, Cold Spring Harbor Laboratory, NY, USA

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
function [NewMessage OpCodeBytes VirtualCurrentEvents] = RunBpodEmulator(Op, ManualOverrideEvent)
global BpodSystem
VirtualCurrentEvents = zeros(1,10);
if BpodSystem.FirmwareBuild < 8
    TupState = 40;
else
    TupState = 29;
end
switch Op
    case 'init'
        BpodSystem.Emulator.nEvents = 0;
        BpodSystem.Emulator.CurrentState = 1;
        BpodSystem.Emulator.GlobalTimerEnd = zeros(1,5);
        BpodSystem.Emulator.GlobalTimersActive = zeros(1,5);
        BpodSystem.Emulator.GlobalCounterCounts = zeros(1,5);
        BpodSystem.Emulator.ConditionChannels = zeros(1,5);
        BpodSystem.Emulator.ConditionValues = zeros(1,5);
        BpodSystem.Emulator.Timestamps = zeros(1,10000);
        BpodSystem.Emulator.MeaningfulTimer = (BpodSystem.StateMatrix.InputMatrix(:,TupState)' ~= 1:length(BpodSystem.StateMatrix.StatesDefined));
        BpodSystem.Emulator.CurrentTime = now*100000;
        BpodSystem.Emulator.MatrixStartTime = BpodSystem.Emulator.CurrentTime;
        BpodSystem.Emulator.StateStartTime = BpodSystem.Emulator.CurrentTime;
        BpodSystem.Emulator.SoftCode = BpodSystem.StateMatrix.OutputMatrix(1,6);
        % Set global timer end-time (if triggered in first state)
        ThisGlobalTimer = BpodSystem.StateMatrix.OutputMatrix(BpodSystem.Emulator.CurrentState,8);
        if ThisGlobalTimer ~= 0
            BpodSystem.Emulator.GlobalTimerEnd(ThisGlobalTimer) = BpodSystem.Emulator.CurrentTime + BpodSystem.StateMatrix.GlobalTimers(ThisGlobalTimer);
            BpodSystem.Emulator.GlobalTimersActive(ThisGlobalTimer) = 1;
        end
    case 'loop'
        if BpodSystem.Emulator.SoftCode == 0
            BpodSystem.Emulator.CurrentTime = now*100000;
            BpodSystem.Emulator.nCurrentEvents = 0;
            % Add manual overrides to current events
            if ~isempty(ManualOverrideEvent)
                BpodSystem.Emulator.nCurrentEvents = BpodSystem.Emulator.nCurrentEvents + 1;
                VirtualCurrentEvents(BpodSystem.Emulator.nCurrentEvents) = ManualOverrideEvent;
            end
            % Evaluate condition transitions
            
            for x = 1:5
                ConditionEvent = 0;
                if BpodSystem.Emulator.ConditionChannels(x) > 0
                    ConditionValue = BpodSystem.Emulator.ConditionValues(x);
                    if ManualOverrideEvent < 9
                        if BpodSystem.HardwareState.PortSensors(BpodSystem.Emulator.ConditionChannels(x)) == ConditionValue
                            ConditionEvent = 79+x;
                        end
                    elseif ManualOverrideEvent < 11
                        if BpodSystem.HardwareState.BNCInputs(BpodSystem.Emulator.ConditionChannels(x)-8) == ConditionValue
                            ConditionEvent = 79+x;
                        end
                    elseif ManualOverrideEvent < 15
                        if BpodSystem.HardwareState.PortSensors(BpodSystem.Emulator.ConditionChannels(x)-10) == ConditionValue
                            ConditionEvent = 79+x;
                        end
                    end
                end
                if ConditionEvent > 0
                    VirtualCurrentEvents(BpodSystem.Emulator.nCurrentEvents+1) = ManualOverrideEvent;
                    VirtualCurrentEvents(BpodSystem.Emulator.nCurrentEvents) = ConditionEvent;
                    nCurrentEvents = nCurrentEvents + 1;
                end
            end
            % Evaluate global timer transitions
            for x = 1:5
                if BpodSystem.Emulator.GlobalTimersActive(x) == 1
                    if BpodSystem.Emulator.CurrentTime > BpodSystem.Emulator.GlobalTimerEnd(x)
                        BpodSystem.Emulator.nCurrentEvents = BpodSystem.Emulator.nCurrentEvents + 1;
                        VirtualCurrentEvents(BpodSystem.Emulator.nCurrentEvents) = 69+x;
                        BpodSystem.Emulator.GlobalTimersActive(x) = 0;
                    end
                end
            end
            % Evaluate global counter transitions
            for x = 1:5
                if BpodSystem.StateMatrix.GlobalCounterEvents(x) ~= 255
                    if BpodSystem.Emulator.GlobalCounterCounts(x) == BpodSystem.StateMatrix.GlobalCounterThresholds(x)
                        BpodSystem.Emulator.nCurrentEvents = BpodSystem.Emulator.nCurrentEvents + 1;
                        VirtualCurrentEvents(BpodSystem.Emulator.nCurrentEvents) = 74+x;
                    end
                    if VirtualCurrentEvents(1) == BpodSystem.StateMatrix.GlobalCounterEvents(x)
                        BpodSystem.Emulator.GlobalCounterCounts(x) = BpodSystem.Emulator.GlobalCounterCounts(x) + 1;
                    end
                end
            end
            % Evaluate condition transitions
            for x = 1:5
                if BpodSystem.StateMatrix.ConditionSet(x)
                    TargetState = BpodSystem.StateMatrix.ConditionMatrix(BpodSystem.Emulator.CurrentState, x);
                    if TargetState ~= BpodSystem.Emulator.CurrentState
                        ThisChannel = BpodSystem.StateMatrix.ConditionChannels(x);
                        if ThisChannel < 9
                            HWState = BpodSystem.HardwareState.PortSensors(ThisChannel);
                        elseif ThisChannel < 11
                            HWState = BpodSystem.HardwareState.BNCInputs(ThisChannel-9);
                        elseif ThisChannel < 13
                            HWState = BpodSystem.HardwareState.WireInputs(ThisChannel-11);
                        end
                        if HWState == BpodSystem.StateMatrix.ConditionValues(x)
                            BpodSystem.Emulator.nCurrentEvents = BpodSystem.Emulator.nCurrentEvents + 1;
                            VirtualCurrentEvents(BpodSystem.Emulator.nCurrentEvents) = 79+x;
                        end
                    end
                end
            end
            % Evaluate state timer transitions
            TimeInState = BpodSystem.Emulator.CurrentTime - BpodSystem.Emulator.StateStartTime;
            StateTimer = BpodSystem.StateMatrix.StateTimers(BpodSystem.Emulator.CurrentState);
            if (TimeInState > StateTimer) && (BpodSystem.Emulator.MeaningfulTimer(BpodSystem.Emulator.CurrentState) == 1)
                BpodSystem.Emulator.nCurrentEvents = BpodSystem.Emulator.nCurrentEvents + 1;
                VirtualCurrentEvents(BpodSystem.Emulator.nCurrentEvents) = TupState;
            end
            DominantEvent = VirtualCurrentEvents(1);
            if DominantEvent > 0
                NewMessage = 1;
                OpCodeBytes = [1 BpodSystem.Emulator.nCurrentEvents];
                VirtualCurrentEvents = VirtualCurrentEvents - 1; % Set to c++ index by 0
                BpodSystem.Emulator.Timestamps(BpodSystem.Emulator.nEvents+1:BpodSystem.Emulator.nEvents+BpodSystem.Emulator.nCurrentEvents) = BpodSystem.Emulator.CurrentTime - BpodSystem.Emulator.MatrixStartTime;
                BpodSystem.Emulator.nEvents = BpodSystem.Emulator.nEvents + BpodSystem.Emulator.nCurrentEvents;
            else
                NewMessage = 0;
                OpCodeBytes = [];
                VirtualCurrentEvents = [];
            end
            drawnow;
        else
            NewMessage = 1;
            OpCodeBytes = [2 BpodSystem.Emulator.SoftCode];
            VirtualCurrentEvents = [];
            BpodSystem.Emulator.SoftCode = 0;
        end    
end

