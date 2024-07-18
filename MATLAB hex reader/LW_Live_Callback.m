function LW_Live_Callback
% LW_Live connects to the Livewire through a serial port. It reads in data,
% plots it, and writes commands back out to the system.

%% Get COM Port
clc; clear; format compact; close all;
disp("Program start, getting COM Port")
prompt = "Enter COM Port (Ex: 'COM14' )";
dlgtitle = 'COM Check';
COM = inputdlg(prompt,dlgtitle);
COM = COM{1};

%% Create figure window
disp("Creating figure window")
fig = uifigure;
fig.Name = "LiveWire HQ";
fig.CloseRequestFcn = @(src,event)my_closereq(src); % closes figure, serial port when exiting

%% Manage app layout
disp("Creating GUI layout")
gl = uigridlayout(fig,[5,2]);
gl.RowHeight = {30,250,250,'1x'};
gl.ColumnWidth = {'fit','1x'};

%% Initialize Device
disp("Initializing Device")
BR = 115200;
Device = serialport(COM,BR);

%% Create UI Components
disp("Creating UI Components")
%labels
labelInput = uilabel(gl);
labelInfo = uilabel(gl);
labelStates = uilabel(gl);
%input field
inputfld = uieditfield(gl,"text","ValueChangedFcn",@(inputfld,event) inputEntered(inputfld,Device));
%text box
txa = uitextarea(gl);
%axes
axDepth = uiaxes(gl);
yyaxis(axDepth,'right')
set(axDepth.YAxis,'Color',axDepth.XAxis.Color)
ylabel(axDepth,'Displacement (m)','Color','r')
yyaxis(axDepth,'left')
ylabel(axDepth,'Pressure (dB)','Color','b')
xlabel(axDepth,'Time (s)')

axSystem = uiaxes(gl);
yyaxis(axSystem,'right')
set(axSystem.YAxis,'Color',axSystem.XAxis.Color)
ylabel(axSystem,'Current (A)','Color','r')
yyaxis(axSystem,'left')
ylabel(axSystem,'Voltage (V)','Color','b')
ylim(axSystem,[20 45]);
xlabel(axSystem,'Time (s)')

%% Lay out UI components
disp("Positioning UI Components")
% Position labels
labelInput.Layout.Row = 1;
labelInput.Layout.Column = 1;

labelInfo.Layout.Row = 4;
labelInfo.Layout.Column = 1;

labelStates.Layout.Row = 5;
labelStates.Layout.Column = 1;

% Position editfield
inputfld.Layout.Row = 1;
inputfld.Layout.Column = 2;

% Position Text Area
txa.Layout.Row = [4,5];
txa.Layout.Column = 2;

% Position axes
axDepth.Layout.Row = 2;
axDepth.Layout.Column = [1,2];
axSystem.Layout.Row = 3;
axSystem.Layout.Column = [1,2];

%% Initial Conditions
TorqueSet = 0; VelocitySet = 0; VelGain = 0; VelIntGain = 0; CurrentError = 0;
UpperLim = 0; LowerLim = 0; Time0 = 0;
Time = []; Pressure=[]; Displacement = []; Current = []; Voltage = [];
ProfStKey = ["initialize" "idle" "profiling up" "profiling down"];
CrntStKey = ["Undefined" "Idle" "Startup Sequence" "Full Calibration Sequence" "Motor Calibration" "" "Encoder Index Search" "Encoder Offset Calibration" "Closed Loop Control" "Lockin Spin" "Encoder Dir Find" "Homing" "Encoder Hall Pol Cal" "Encoder Hall Phase Cal" "Anticlogging Cal"];
CntrlMdKey = ["Voltage" "Torque" "Velocity" "Position"];
CurrentState = CrntStKey(1);
ProfileState = ProfStKey(1);
ControlMode = CntrlMdKey(1);

%% Configure UI Component Appearence
labelInput.Text = "Write to Serial Port:";
labelInfo.Text = sprintf("Current Torque Setpoint: "+TorqueSet+"\nCurrent Velocity Setpoint: "+VelocitySet+"\nVelocity Gain: "+VelGain+"\nVelocity Integrator Gain: "+VelIntGain+"\n");
labelStates.Text = sprintf("Upper Limit: "+UpperLim+"\nLower Limit: "+LowerLim+"\nProfiling State: "+ProfileState+"\nCurrent State: "+CurrentState+"\nControl Mode: "+ControlMode);

%% Program App Behavior
TextOut(1,1) = "Start Line";
txa.Value = TextOut;
configureCallback(Device,"terminator",@newData)

%define what happens when receiving new line from serial port
    function newData(s,~)

        data = readline(s);

        %check if it's a starting line
        if strcmpi(extract(data,1),">")
            data = extractAfter(data,">  ");
        end

        if strlength(data)~=116    % non-data line
            disp("read a line that is not of length 116")
            % add new line to text field
            disp(data)
            TextOut(end+1,:) = data;
            %disp(TextOut)
            txa.Value = TextOut;
            scroll(txa,'bottom');
        else % data line
         % Extract desired info from line of data
        
            newTime = hex2dec(extractBetween(data,1,16))/10^3; % s
            if isempty(Time)
            Time0 = newTime; % set initial time 0s
            end
        
            newPres = cast(typecast(uint32(hex2dec(extractBetween(data,17,24))),'int32'),'double')/10^3;
            newDisp = cast(typecast(uint32(hex2dec(extractBetween(data,25,32))),'int32'),'double')/10^2; % meters
            newCurrent = cast(typecast(uint32(hex2dec(extractBetween(data,41,48))),'int32'),'double')/10^3; % Amps
            newVolt = cast(typecast(uint32(hex2dec(extractBetween(data,49,56))),'int32'),'double')/10^3; % Volts
            CurrentError = cast(typecast(uint32(hex2dec(extractBetween(data,57,64))),'int32'),'double');
            CrntSt = str2double(extract(data,65));
            CntrlMd = str2double(extract(data,66));
            VelocitySet = num2str(cast(typecast(uint32(hex2dec(extractBetween(data,67,74))),'int32'),'double'));
            TorqueSet = num2str(cast(typecast(uint32(hex2dec(extractBetween(data,75,82))),'int32'),'double'));
            VelGain = cast(typecast(uint32(hex2dec(extractBetween(data,83,90))),'int32'),'double');
            VelIntGain = cast(typecast(uint32(hex2dec(extractBetween(data,91,98))),'int32'),'double');
            UpperLim = cast(typecast(uint32(hex2dec(extractBetween(data,99,106))),'int32'),'double'); % m
            LowerLim = cast(typecast(uint32(hex2dec(extractBetween(data,107,114))),'int32'),'double'); % m
            
            ProfSt = str2double(extract(data,115)); % 0 = initialize, 1 = idle, 2 = profiling up, 3 = profiling down
            
            % translate profile state
            if (0<=ProfSt) && (ProfSt<=3)
                ProfileState = ProfStKey((ProfSt+1));
            else
                ProfileState = sprintf("Unkown Profiling State: "+ProfSt);
            end

            % translate current state
            if (0<=CrntSt) && (CrntSt<=14)
                CurrentState = CrntStKey(CrntSt+1);
            else
                CurrentState = sprintf("Undefined Current State: "+CrntSt);
            end

            %translate control mode
            if (0<=CntrlMd) && (CntrlMd<=3)
                ControlMode = CntrlMdKey(CntrlMd+1);
            else
                ControlMode = sprintf("Undefined Control Mode: "+CntrlMd);
            end


            % Add new values
            Time = [Time (newTime-Time0)];
            Pressure = [Pressure newPres];
            Displacement = [Displacement newDisp];
            Current = [Current newCurrent];
            Voltage = [Voltage newVolt];

            % Update GUI
            lim = 2*60; % [] minutes * seconds

            yyaxis(axDepth,"left")
            plot(axDepth,Time,Pressure,'b')
            yyaxis(axDepth,'right')
            plot(axDepth,Time,Displacement,'r')
            yyaxis(axSystem,'right') 
            plot(axSystem,Time,Current,'r')
            yyaxis(axSystem,'left')
            plot(axSystem,Time,Voltage,'b')
        
            if Time(end)>lim
                xlim(axDepth,[Time(end)-lim Time(end)])
                xlim(axSystem,[Time(end)-lim Time(end)])
            end
            labelInfo.Text = sprintf("Current Torque Setpoint: "+TorqueSet+"\nCurrent Velocity Setpoint: "+VelocitySet+"\nVelocity Gain: "+VelGain+"\nVelocity Integrator Gain: "+VelIntGain+"\n");
            labelStates.Text = sprintf("Upper Limit: "+UpperLim+" m\nLower Limit: "+LowerLim+" m\nProfiling State: "+ProfileState);
            drawnow limitrate
            end

    end

    % Define what happens when user closes figure
    % 1) Confirm intent to close
    % 2) Close serial port connection
    function my_closereq(fig)
        selection = uiconfirm(fig,'Close the figure window?','Confirmation');
        switch selection
            case 'OK'
                clear Device;
                delete(fig)
            case 'Cancel'
                return
        end
    end

end

% Define what happens when line is input to Input Field
% 1) Write input line to serial port and command window
% 2) Clear Input Field
function inputEntered(inputfld,Device)
    writeline(Device,inputfld.Value);
    disp("Sent line "+inputfld.Value);
    inputfld.Value = "";
end

% Streaming Digits
% 1-16: timestamp
% 17-24: pressure
% 25-32: displacement
% 33-40: velocity
% 41-48: current
% 49-56: voltage
% 57-64: current errors
% 65: current state
% 66: control mode
% 67-74: velocity set point
% 75-82: torque set point
% 83-90: velocity gain
% 91-98: velocity integrator gain
% 99-106: upper limit
% 107-114: lower limit
% 115: profiling state (0 = initialize, 1 = idle, 2 = profiling up, 3 = profiling down)