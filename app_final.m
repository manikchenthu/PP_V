classdef app_final < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure            matlab.ui.Figure
        MainGrid            matlab.ui.container.GridLayout

        % Visualization Containers
        VizGrid             matlab.ui.container.GridLayout
        UIAxes_Top          matlab.ui.control.UIAxes
        UIAxes_Front        matlab.ui.control.UIAxes
        UIAxes_Side         matlab.ui.control.UIAxes

        % Control Containers
        RightPanel          matlab.ui.container.Panel
        ControlsGrid        matlab.ui.container.GridLayout

        % Gauges & Labels
        SteeringGauge       matlab.ui.control.SemicircularGauge
        GasGauge            matlab.ui.control.LinearGauge
        GasLabel            matlab.ui.control.Label
        BrakeGauge          matlab.ui.control.LinearGauge
        BrakeLabel          matlab.ui.control.Label

        % Buttons
        ButtonGrid          matlab.ui.container.GridLayout
        PlayButton          matlab.ui.control.Button
        StopButton          matlab.ui.control.Button

        % Brake Torque
        BrakeTorqueGauge    matlab.ui.control.LinearGauge
        BrakeTorqueLabel    matlab.ui.control.Label

        % Bottom Graphs
        GraphsGrid          matlab.ui.container.GridLayout
        Axes_TimeX          matlab.ui.control.UIAxes
        Axes_TimeY          matlab.ui.control.UIAxes
        Axes_TimeZ          matlab.ui.control.UIAxes
        Axes_TimeTorque     matlab.ui.control.UIAxes

        % Time Slider
        SliderGrid          matlab.ui.container.GridLayout
        TimeSlider          matlab.ui.control.Slider
        TimeLabel           matlab.ui.control.Label

        % Top Container (to hold Viz and Controls)
        TopGrid             matlab.ui.container.GridLayout
    end

    properties (Access = private)
        CarTransform_Top
        CarTransform_Side
        CarTransform_Front
        VehicleData
        IsPlaying = false
        CursorLines         % Array of ConstantLines for the 4 graphs
        TimeVector          % Cache for time data
    end

    methods (Access = private)

        function startupFcn(app)
            % 1. Create the 3 Car Objects
            [app.CarTransform_Top, ~]   = createVehiclePatch(app.UIAxes_Top);
            [app.CarTransform_Front, ~] = createVehiclePatch(app.UIAxes_Front);
            [app.CarTransform_Side, ~]  = createVehiclePatch(app.UIAxes_Side);

            % 2. Set Camera Views
            view(app.UIAxes_Top, 0, 90);    % Top View
            view(app.UIAxes_Front, 90, 0);  % Front View
            view(app.UIAxes_Side, 0, 0);    % Side View

            % 3. Set Axes Limits
            limits = [-6 6];
            xlim(app.UIAxes_Top, limits); ylim(app.UIAxes_Top, limits);
            ylim(app.UIAxes_Front, limits); zlim(app.UIAxes_Front, [-1 4]);
            xlim(app.UIAxes_Side, limits); zlim(app.UIAxes_Side, [-1 4]);
        end

        function loadData(app)
            if isempty(app.VehicleData)
                try
                    app.VehicleData = readtable('vehicle_data_full.csv');
                catch
                    uialert(app.UIFigure, 'Data file missing!', 'Error');
                    return;
                end

                data = app.VehicleData;
                app.TimeVector = data.Time;

                % Update Slider Limits
                app.TimeSlider.Limits = [min(app.TimeVector) max(app.TimeVector)];
                app.TimeSlider.Value = min(app.TimeVector);

                % Plot Data on Bottom Graphs
                plot(app.Axes_TimeX, data.Time, data.X);
                plot(app.Axes_TimeY, data.Time, data.Y);
                plot(app.Axes_TimeZ, data.Time, data.Z);
                plot(app.Axes_TimeTorque, data.Time, data.BrakeTorque);

                % Initialize Cursor Lines (Vertical lines at t=0)
                hold(app.Axes_TimeX, 'on');
                l1 = xline(app.Axes_TimeX, data.Time(1), 'r', 'LineWidth', 1.5);
                hold(app.Axes_TimeX, 'off');

                hold(app.Axes_TimeY, 'on');
                l2 = xline(app.Axes_TimeY, data.Time(1), 'r', 'LineWidth', 1.5);
                hold(app.Axes_TimeY, 'off');

                hold(app.Axes_TimeZ, 'on');
                l3 = xline(app.Axes_TimeZ, data.Time(1), 'r', 'LineWidth', 1.5);
                hold(app.Axes_TimeZ, 'off');

                hold(app.Axes_TimeTorque, 'on');
                l4 = xline(app.Axes_TimeTorque, data.Time(1), 'r', 'LineWidth', 1.5);
                hold(app.Axes_TimeTorque, 'off');

                app.CursorLines = [l1, l2, l3, l4];
            end
        end

        function updateVisuals(app, t_idx)
            data = app.VehicleData;
            if isempty(data) || t_idx > height(data) || t_idx < 1, return; end

            % Update Gauges
            app.GasGauge.Value = max(0, min(100, data.GasPedal(t_idx)));
            app.BrakeGauge.Value = max(0, min(100, data.BrakePressure(t_idx)));
            app.SteeringGauge.Value = max(-450, min(450, data.SteeringAngle(t_idx)));
            app.BrakeTorqueGauge.Value = max(0, min(500, data.BrakeTorque(t_idx)));

            % Calculate Transforms
            yaw = deg2rad(data.Yaw(t_idx));
            roll = deg2rad(data.Roll(t_idx));
            pitch = deg2rad(-data.AccelX(t_idx)*2);

            M = makehgtform('zrotate', yaw, 'yrotate', pitch, 'xrotate', roll);

            app.CarTransform_Top.Matrix = M;
            app.CarTransform_Front.Matrix = M;
            app.CarTransform_Side.Matrix = M;

            % Update Time Slider and Label
            t_val = data.Time(t_idx);
            app.TimeLabel.Text = sprintf('Time: %.2fs', t_val);

            % Only update slider value if we are playing to avoid fighting user dragging
            if app.IsPlaying
                 app.TimeSlider.Value = t_val;
            end

            % Update Graph Cursors
            if ~isempty(app.CursorLines)
                for k = 1:4
                    app.CursorLines(k).Value = t_val;
                end
            end
        end

        function PlayButtonPushed(app, ~)
            loadData(app);
            if isempty(app.VehicleData), return; end

            app.IsPlaying = true;

            % Find start index based on slider
            t_start = app.TimeSlider.Value;
            [~, idx_start] = min(abs(app.TimeVector - t_start));

            % Handle case where we are at the end
            if idx_start >= height(app.VehicleData)
                idx_start = 1;
            end

            % Animation Loop
            for i = idx_start:height(app.VehicleData)
                if ~app.IsPlaying, break; end

                updateVisuals(app, i);

                drawnow limitrate;
                pause(0.05);
            end
            app.IsPlaying = false;
        end

        function StopButtonPushed(app, ~)
            app.IsPlaying = false;
        end

        function TimeSliderValueChanging(app, event)
            app.IsPlaying = false; % Stop playback when scrubbing

            t_val = event.Value;

            if ~isempty(app.VehicleData)
                [~, idx] = min(abs(app.TimeVector - t_val));
                updateVisuals(app, idx);
            end
        end
    end

    % Component initialization
    methods (Access = private)

        function createComponents(app)
            % 1. Main Figure
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 1000 800]; % Increased height for graphs
            app.UIFigure.Name = 'Vehicle Dynamics Visualizer';
            app.UIFigure.Color = [0.95 0.95 0.95];

            % 2. Main Grid - 3 Rows
            app.MainGrid = uigridlayout(app.UIFigure);
            app.MainGrid.ColumnWidth = {'1x'};
            app.MainGrid.RowHeight = {'2x', '1x', 50};

            % --- ROW 1: TOP CONTAINER (Viz + Controls) ---
            app.TopGrid = uigridlayout(app.MainGrid);
            app.TopGrid.Layout.Row = 1;
            app.TopGrid.Layout.Column = 1;
            app.TopGrid.ColumnWidth = {'1x', 280};
            app.TopGrid.RowHeight = {'1x'};
            app.TopGrid.Padding = [0 0 0 0];

            % --- LEFT SIDE: VISUALIZATION GRID ---
            app.VizGrid = uigridlayout(app.TopGrid);
            app.VizGrid.Layout.Row = 1;
            app.VizGrid.Layout.Column = 1;
            app.VizGrid.ColumnWidth = {'1x', '1x'};
            app.VizGrid.RowHeight = {'1x', '1x'};

            % Axes Setup
            app.UIAxes_Top = uiaxes(app.VizGrid);
            title(app.UIAxes_Top, 'Top View', 'FontWeight', 'bold');
            app.UIAxes_Top.Layout.Row = 1; app.UIAxes_Top.Layout.Column = 1;

            app.UIAxes_Front = uiaxes(app.VizGrid);
            title(app.UIAxes_Front, 'Front View', 'FontWeight', 'bold');
            app.UIAxes_Front.Layout.Row = 1; app.UIAxes_Front.Layout.Column = 2;

            app.UIAxes_Side = uiaxes(app.VizGrid);
            title(app.UIAxes_Side, 'Side View', 'FontWeight', 'bold');
            app.UIAxes_Side.Layout.Row = 2; app.UIAxes_Side.Layout.Column = [1 2];

            % --- RIGHT SIDE: CONTROLS PANEL ---
            app.RightPanel = uipanel(app.TopGrid);
            app.RightPanel.Layout.Row = 1;
            app.RightPanel.Layout.Column = 2;
            app.RightPanel.Title = 'Driver Inputs';
            app.RightPanel.FontWeight = 'bold';
            app.RightPanel.FontSize = 14;
            app.RightPanel.BackgroundColor = [0.94 0.94 0.94];

            % Controls Grid
            app.ControlsGrid = uigridlayout(app.RightPanel);
            app.ControlsGrid.ColumnWidth = {'1x'};
            % CHANGED: Added row for Brake Torque
            app.ControlsGrid.RowHeight = {100, '1x', '1x', '1x', 80};

            % 1. Steering
            app.SteeringGauge = uigauge(app.ControlsGrid, 'semicircular');
            app.SteeringGauge.Layout.Row = 1;
            app.SteeringGauge.Limits = [-450 450];
            app.SteeringGauge.ScaleColors = [0.2 0.4 0.8];

            % 2. Gas Gauge
            GasContainer = uigridlayout(app.ControlsGrid);
            GasContainer.Layout.Row = 2;
            GasContainer.ColumnWidth = {'1x', 60, '1x'};
            GasContainer.RowHeight = {'1x', 20};

            app.GasGauge = uigauge(GasContainer, 'linear');
            app.GasGauge.Layout.Row = 1; app.GasGauge.Layout.Column = 2;
            app.GasGauge.Orientation = 'vertical';
            app.GasGauge.Limits = [0 100];

            app.GasLabel = uilabel(GasContainer);
            app.GasLabel.Text = 'Gas';
            app.GasLabel.HorizontalAlignment = 'center';
            app.GasLabel.Layout.Row = 2; app.GasLabel.Layout.Column = 2;

            % 3. Brake Gauge
            BrakeContainer = uigridlayout(app.ControlsGrid);
            BrakeContainer.Layout.Row = 3;
            BrakeContainer.ColumnWidth = {'1x', 60, '1x'};
            BrakeContainer.RowHeight = {'1x', 20};

            app.BrakeGauge = uigauge(BrakeContainer, 'linear');
            app.BrakeGauge.Layout.Row = 1; app.BrakeGauge.Layout.Column = 2;
            app.BrakeGauge.Orientation = 'vertical';
            app.BrakeGauge.Limits = [0 100];
            app.BrakeGauge.ScaleColors = [1 0 0];
            app.BrakeGauge.ScaleColorLimits = [0 100];

            app.BrakeLabel = uilabel(BrakeContainer);
            app.BrakeLabel.Text = 'Brake';
            app.BrakeLabel.HorizontalAlignment = 'center';
            app.BrakeLabel.Layout.Row = 2; app.BrakeLabel.Layout.Column = 2;

            % 4. Brake Torque Gauge
            TorqueContainer = uigridlayout(app.ControlsGrid);
            TorqueContainer.Layout.Row = 4;
            TorqueContainer.ColumnWidth = {'1x', 60, '1x'};
            TorqueContainer.RowHeight = {'1x', 20};

            app.BrakeTorqueGauge = uigauge(TorqueContainer, 'linear');
            app.BrakeTorqueGauge.Layout.Row = 1; app.BrakeTorqueGauge.Layout.Column = 2;
            app.BrakeTorqueGauge.Orientation = 'vertical';
            app.BrakeTorqueGauge.Limits = [0 500]; % Adjust limit as needed
            app.BrakeTorqueGauge.ScaleColors = [1 0.5 0];

            app.BrakeTorqueLabel = uilabel(TorqueContainer);
            app.BrakeTorqueLabel.Text = 'Torque';
            app.BrakeTorqueLabel.HorizontalAlignment = 'center';
            app.BrakeTorqueLabel.Layout.Row = 2; app.BrakeTorqueLabel.Layout.Column = 2;

            % 5. Buttons (Bottom)
            app.ButtonGrid = uigridlayout(app.ControlsGrid);
            app.ButtonGrid.Layout.Row = 5;
            app.ButtonGrid.ColumnWidth = {'1x', '1x'};
            app.ButtonGrid.Padding = [5 5 5 5];

            % --- BIGGER PLAY BUTTON ---
            app.PlayButton = uibutton(app.ButtonGrid, 'push');
            app.PlayButton.Text = 'Play';
            app.PlayButton.FontSize = 14;
            app.PlayButton.FontWeight = 'bold';
            app.PlayButton.BackgroundColor = [0.6 0.9 0.6];
            app.PlayButton.ButtonPushedFcn = @(src, event) PlayButtonPushed(app, event);

            % --- BIGGER STOP BUTTON ---
            app.StopButton = uibutton(app.ButtonGrid, 'push');
            app.StopButton.Text = 'Stop';
            app.StopButton.FontSize = 14;
            app.StopButton.FontWeight = 'bold';
            app.StopButton.BackgroundColor = [0.9 0.6 0.6];
            app.StopButton.ButtonPushedFcn = @(src, event) StopButtonPushed(app, event);

            % --- ROW 2: BOTTOM GRAPHS ---
            app.GraphsGrid = uigridlayout(app.MainGrid);
            app.GraphsGrid.Layout.Row = 2;
            app.GraphsGrid.Layout.Column = 1;
            app.GraphsGrid.ColumnWidth = {'1x', '1x', '1x', '1x'};
            app.GraphsGrid.RowHeight = {'1x'};

            % Graph 1: Time vs X
            app.Axes_TimeX = uiaxes(app.GraphsGrid);
            title(app.Axes_TimeX, 'Time vs X');
            app.Axes_TimeX.Layout.Row = 1; app.Axes_TimeX.Layout.Column = 1;

            % Graph 2: Time vs Y
            app.Axes_TimeY = uiaxes(app.GraphsGrid);
            title(app.Axes_TimeY, 'Time vs Y');
            app.Axes_TimeY.Layout.Row = 1; app.Axes_TimeY.Layout.Column = 2;

            % Graph 3: Time vs Z
            app.Axes_TimeZ = uiaxes(app.GraphsGrid);
            title(app.Axes_TimeZ, 'Time vs Z');
            app.Axes_TimeZ.Layout.Row = 1; app.Axes_TimeZ.Layout.Column = 3;

            % Graph 4: Time vs Brake Torque
            app.Axes_TimeTorque = uiaxes(app.GraphsGrid);
            title(app.Axes_TimeTorque, 'Time vs Torque');
            app.Axes_TimeTorque.Layout.Row = 1; app.Axes_TimeTorque.Layout.Column = 4;

            % --- ROW 3: TIME SLIDER ---
            app.SliderGrid = uigridlayout(app.MainGrid);
            app.SliderGrid.Layout.Row = 3;
            app.SliderGrid.Layout.Column = 1;
            app.SliderGrid.ColumnWidth = {80, '1x'};
            app.SliderGrid.RowHeight = {'1x'};

            app.TimeLabel = uilabel(app.SliderGrid);
            app.TimeLabel.Text = 'Time: 0.00s';
            app.TimeLabel.Layout.Row = 1; app.TimeLabel.Layout.Column = 1;

            app.TimeSlider = uislider(app.SliderGrid);
            app.TimeSlider.Layout.Row = 1; app.TimeSlider.Layout.Column = 2;
            app.TimeSlider.Limits = [0 100]; % Placeholder, updated on load
            app.TimeSlider.ValueChangingFcn = @(src, event) TimeSliderValueChanging(app, event);
            app.TimeSlider.ValueChangedFcn = @(src, event) TimeSliderValueChanging(app, event);

            % Show the figure
            app.UIFigure.Visible = 'on';
        end
    end

    methods (Access = public)
        function app = app_final
            createComponents(app)
            registerApp(app, app.UIFigure)
            startupFcn(app);
            if nargout == 0
                clear app
            end
        end

        function delete(app_final)
            delete(app.UIFigure)
        end
    end
end