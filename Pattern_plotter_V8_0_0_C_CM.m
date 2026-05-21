function Pattern_plotter_V7_6_4_C_CM
% Pattern Plotter V7.6.4.C.CM
%#function uigetfile uiputfile uigetdir uiconfirm uialert inputdlg
%#function readtable writetable load save print
%#function movegui isdeployed prefdir isfile mkdir
%#function addStyle removeStyle uistyle
%#function exportgraphics actxserver actxGetRunningServer xlsfinfo datetime web
%#function imwrite getframe saveas
%#function pca kmeans pdist squareform timer setenv clipboard dir fopen fclose rng
%#function regexp strsplit strjoin contains startsWith endsWith
%#function uitabgroup uitab uigridlayout uipanel uiaxes uitable uibutton
%#function uibuttongroup uiradiobutton uiprogressdlg uimenu uicontextmenu
%#function uitextarea uislider uilistbox uiwait uiresume uistack
%#function uilabel uicheckbox uidropdown uicontextmenu uimenu
%#function uifigure uieditfield uilistbox scatter uistack uiprogressdlg
%#function ancestor findall gobjects isprop drawnow matlab.lang.makeValidName
% ^^^ MCR deployment: declare dynamically-referenced/late-bound functions.

    clearvars -except varargin; clc;
    
    % NOTE: opengl() is deprecated in R2024b+. uifigure auto-selects the best
    % renderer, so no explicit renderer setting is needed for smooth 3D plots.
    
    delete(findall(0, 'Name', 'Pattern Plotter V7.6.4.C.CM'));
    delete(findall(0, 'Name', 'TCC Editor'));
    delete(findall(0, 'Name', 'UK & STAT Table'));

    % === MAIN UI CREATION (Moved Up for Project Load Logic) ===
    % ── Centre the main GUI on screen regardless of screen size ─────────────
    scrn   = get(0, 'ScreenSize');          % [1, 1, screenW, screenH]
    figW   = min(1200, scrn(3) - 40);       % cap width  to screen - 40px margin
    figH   = min(800,  scrn(4) - 80);       % cap height to screen - 80px (taskbar)
    figX   = scrn(1) + (scrn(3) - figW) / 2;
    figY   = scrn(2) + (scrn(4) - figH) / 2;
    fig = uifigure('Name', 'Pattern Plotter V7.6.4.C.CM', ...
        'Position', [figX figY figW figH], ...
        'CloseRequestFcn', @(src, event) closeMainApp(src));
    configureMCRSpeedup(fig);
    
    % === STARTUP CHOICE ===
    choice = uiconfirm(fig, 'Start New Project from CSV or Load Existing Project?', 'Welcome', ...
        'Options', {'New from CSV', 'Load Project', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'question');
    
    appData = [];
    
    if strcmp(choice, 'Cancel')
        delete(fig); return;
        
    elseif strcmp(choice, 'Load Project')
        % === LOAD PROJECT ===
        [f, p] = uigetfile('*.mat', 'Select Project File');
        if isequal(f, 0), delete(fig); return; end
        try
            loaded = load(fullfile(p, f));
            if isfield(loaded, 'appData')
                appData = loaded.appData;
                % Restore Transient Handles (Init to empty)
                appData.ukFig = gobjects(0);
                appData.tccFig = gobjects(0);
                appData.tableFig = gobjects(0);
                appData.tableHandle = gobjects(0);
                appData.infoLabel = gobjects(0);
                appData.handles      = struct(); % Will be repopulated
                appData.multiMapFig  = gobjects(0);
                appData.gbfssactFig  = gobjects(0);
                appData.genericFig   = gobjects(0);
                appData.interpFig    = gobjects(0);
                appData.analysisFig  = gobjects(0);
                appData.multiMapDirty = false;
                appData.multiHistory  = {};
                % Strip session state — never persists across file loads
                if isfield(appData,'holdSession'), appData = rmfield(appData,'holdSession'); end
                if isfield(appData,'dragGhost'),   appData = rmfield(appData,'dragGhost'); end
                if isfield(appData,'swapping'),    appData = rmfield(appData,'swapping');   end
                % Guard fields added since old project files were saved
                if ~isfield(appData,'history'),    appData.history = {}; end
                if ~isfield(appData,'editIndex'),  appData.editIndex = -1; end
                if ~isfield(appData,'workingCopy'),appData.workingCopy = []; end
                if ~isfield(appData,'sessionLog'), appData.sessionLog = {}; end
                if ~isfield(appData,'lastSelectedIndices'), appData.lastSelectedIndices = []; end
                if ~isfield(appData,'hysteresis'), appData.hysteresis = struct('Speed',50,'Pedal',10,'MPH',2); end
                % Rebuild allMapNames cache
                if isfield(appData,'allMaps') && ~isempty(appData.allMaps)
                    appData.allMapNames = string(cellfun(@(m) m.name, appData.allMaps, 'UniformOutput', false))';
                end
            else
                uialert(fig, 'Invalid Project File.', 'Error'); delete(fig); return;
            end
        catch ME
            uialert(fig, sprintf('Error loading project:\n%s', ME.message), 'Error'); delete(fig); return;
        end
        
    else
        % === NEW FROM CSV ===
        appData = loadFromCSV(fig);
        if ~isempty(appData) && isfield(appData,'sourceFilename')
            try, recentFilesAdd(appData.sourceFilename); catch; end
        end
    end % End of startup choice block

    % === COMMON UI INITIALIZATION ===
    if isempty(appData), delete(fig); return; end % Should not happen
    
    % Ensure mapNames exists (Derived from appData.allMaps)
    mapNames = getMapNames(appData);
    if isempty(mapNames), mapNames = ["None"]; end

    % === MAIN GRID LAYOUT ===
    mainGrid = uigridlayout(fig, [4, 1]);
    mainGrid.RowHeight = {95, 100, '1x', 40}; % TopControls(status moved to top-right of topPanel), ConfigPanels, Plot, Buttons
    mainGrid.Padding = [10 10 10 10];
    mainGrid.RowSpacing = 5;

    % --- ROW 1: TOP CONTROLS (V7.6.3 — restructured) ---
    % Layout:
    %   topGrid (1 row × 2 cols)
    %     ├── leftPanel: 3-row stack of file labels (A:, B:, C:) — one per map slot
    %     └── rightPanel: 2-row grid (mapGrid + optGrid) where Map A: and
    %         Edit Map A share the same column width → aligned vertically
    topPanel = uipanel(mainGrid, 'BorderType', 'none');
    topGrid = uigridlayout(topPanel, [1, 2]);
    topGrid.RowHeight   = {'1x'};
    topGrid.ColumnWidth = {300, '1x'};
    topGrid.Padding     = [0 0 0 0];
    topGrid.ColumnSpacing = 8;

    % LEFT side — 3 stacked file/source labels (A:, B:, C:)
    leftPanel = uipanel(topGrid, 'BorderType','none');
    leftGrid  = uigridlayout(leftPanel, [3, 1]);
    leftGrid.RowHeight   = {'1x', '1x', '1x'};
    leftGrid.ColumnWidth = {'1x'};
    leftGrid.Padding     = [5 2 5 2]; leftGrid.RowSpacing = 0;

    fileLbl  = uilabel(leftGrid, 'Text', 'A: No File Loaded', ...
        'FontWeight','bold', 'FontColor',[0.15 0.5 0.15], ...
        'HorizontalAlignment','left', 'FontSize',11, ...
        'Tooltip','Source file or vehicle for the map currently in Map A');
    fileLblB = uilabel(leftGrid, 'Text', 'B: —', ...
        'FontWeight','bold', 'FontColor',[0.5 0.15 0.15], ...
        'HorizontalAlignment','left', 'FontSize',11, ...
        'Tooltip','Source file or vehicle for the map currently in Map B');
    fileLblC = uilabel(leftGrid, 'Text', 'C: —', ...
        'FontWeight','bold', 'FontColor',[0.15 0.15 0.5], ...
        'HorizontalAlignment','left', 'FontSize',11, ...
        'Tooltip','Source file or vehicle for the map currently in Map C');

    % RIGHT side — 2-row grid: mapGrid (dropdowns) above optGrid (options).
    % Status bar moved into figure title bar (V7.6.3 — see updateStatusBar/refreshStatusBar).
    rightPanel = uipanel(topGrid, 'BorderType','none');
    rightGrid  = uigridlayout(rightPanel, [2, 1]);
    rightGrid.RowHeight   = {'1x', '1x'};
    rightGrid.ColumnWidth = {'1x'};
    rightGrid.Padding     = [0 0 0 0];
    rightGrid.RowSpacing  = 2;

    % Row 1 of rightGrid: mapGrid (Map A/B/C dropdowns, swap, Help)
    % Col 1 fixed at 90 to align "Map A:" with "Edit Map A" below.
    mapGrid = uigridlayout(rightGrid, [1, 13]);
    mapGrid.ColumnWidth = {90, 180, 'fit', 50, 'fit', 'fit', 180, 'fit', 'fit', 180, 'fit', '1x', 80};
    mapGrid.Padding     = [5 5 0 0];
    mapGrid.ColumnSpacing = 6;
    mapGrid.Layout.Row  = 1;

    uilabel(mapGrid, 'Text','Map A:', 'HorizontalAlignment','right', 'FontWeight','bold');
    dd1 = uidropdown(mapGrid, 'Items', mapNames, 'BackgroundColor', [0.95 1 0.95]);
    cb1 = uicheckbox(mapGrid, 'Text','Show', 'Value', true);

    uibutton(mapGrid, 'Text','⇄', 'FontSize',14, 'FontWeight','bold', ...
        'BackgroundColor',[0.68 0.85 0.95], ...
        'Tooltip','Swap maps (A↔B, or A→C→B cycle when 3-way is on)', ...
        'ButtonPushedFcn', @(~,~) swapMaps(fig));
    cbSwapC = uicheckbox(mapGrid, 'Text','3⟳', 'Value', false, ...
        'Tooltip','Enable 3-way cycle: A→C  B→A  C→B', 'FontSize',9);

    lblMapB = uilabel(mapGrid, 'Text','Map B:', 'HorizontalAlignment','right', 'FontWeight','bold');
    dd2 = uidropdown(mapGrid, 'Items', mapNames, 'BackgroundColor', [1 0.95 0.95]);
    cb2 = uicheckbox(mapGrid, 'Text','Show', 'Value', false);

    uilabel(mapGrid, 'Text','Map C:', 'HorizontalAlignment','right', 'FontWeight','bold');
    dd3 = uidropdown(mapGrid, 'Items', mapNames, 'BackgroundColor', [0.95 0.95 1]);
    cb3 = uicheckbox(mapGrid, 'Text','Show', 'Value', false);

    % Reference vehicle label — moved here in V7.6.3 to use the wide space
    % between Map C and Help (was previously cramped between Clear All and 4Lo)
    refLbl = uilabel(mapGrid, 'Text', '', 'HorizontalAlignment','left', ...
        'FontWeight','bold', 'FontColor',[0.0 0.35 0.65], ...
        'Tooltip','Reference vehicle loaded (use Swap to view its maps in Map A)');

    uibutton(mapGrid, 'Text','Help', 'BackgroundColor',[0.9 0.9 0.9], ...
        'FontWeight','bold', 'ButtonPushedFcn', @(~,~) showHelp(fig));

    % Row 2 of rightGrid: optGrid (Edit Map A in col 1 — aligned with Map A: above)
    optGrid = uigridlayout(rightGrid, [1, 14]);
    optGrid.ColumnWidth = {90, 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', '1x'};
    optGrid.Padding     = [5 0 5 5];
    optGrid.ColumnSpacing = 12;
    optGrid.Layout.Row  = 2;

    % Edit Map A (col 1 — aligned vertically with "Map A:" label above)
    cbEdit   = uicheckbox(optGrid, 'Text', 'Edit Map A',       'Value', true);
    cbAllowY = uicheckbox(optGrid, 'Text', 'Allow Y-axis Edit','Value', false);
    uilabel(optGrid, 'Text', '2nd Axis:', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    ddAxis = uidropdown(optGrid, 'Items', {'None','MPH','KPH'}, 'Value', 'None', 'BackgroundColor', [1 1 0.9]);
    cbClearAll = uicheckbox(optGrid, 'Text', '✕ Clear All Lines', 'Value', false, ...
        'Tooltip', 'Uncheck all Gear Shift Lines and TCC Lines so you can turn on only what you need');

    % Wide flexible spacer between Clear All and 4Lo (refLbl moved to mapGrid)
    uilabel(optGrid, 'Text', '');

    % Global Options
    cb4Lo = uicheckbox(optGrid, 'Text', '4Lo Mode', 'Value', false);
    cbLines = uicheckbox(optGrid, 'Text', 'Show Shift Lines', 'Value', true);
    cbTCC = uicheckbox(optGrid, 'Text', 'Show TCC', 'Value', false);
    cbLegend = uicheckbox(optGrid, 'Text', 'Show Legend', 'Value', true);

    % Hold & Save Session checkbox
    cbHoldSave = uicheckbox(optGrid, 'Text', '📌 Hold & Save Session', 'Value', false, ...
        'FontWeight', 'bold', 'FontColor', [0.1 0.4 0.1], ...
        'Tooltip', sprintf(['Lock Maps A, B and C for a multi-map editing session.\n' ...
            'Use the swap button to rotate between maps.\n' ...
            'When done, press Save All to save each map in turn.']));

    % Sync to INCA checkbox
    cbSyncINCA = uicheckbox(optGrid, 'Text', '🔗 Sync to INCA', 'Value', false, ...
        'FontWeight', 'bold', 'FontColor', [0.0 0.3 0.7], ...
        'Tooltip', sprintf(['When enabled, every shift-map edit is pushed live to INCA.\n' ...
            'INCA must be running and connected to an active dataset.\n' ...
            'Edits apply to the currently selected map''s parameter in INCA.']));
    
    cbRefMode = uicheckbox(optGrid, 'Text', '📘 Ref Mode', 'Value', false, ...
        'FontWeight', 'bold', 'FontColor', [0.0 0.35 0.65], ...
        'Tooltip', 'Load a reference vehicle from the database into Map B for comparison');

    uilabel(optGrid, 'Text', ''); % Spacer

    % --- ROW 2: CONFIG PANELS ---
    configPanel = uipanel(mainGrid, "BorderType", "none");
    configGrid = uigridlayout(configPanel, [1, 3]);
    configGrid.ColumnWidth = {"1x", "1.15x", "1.5x"}; % Shift Lines, TCC Combined, Context Info
    configGrid.Padding = [0 0 0 0];

    % Panel 1: Gear Shift Lines
    pnlShift = uipanel(configGrid, "Title", "Gear Shift Lines", "FontWeight", "bold");
    pnlShift.Layout.Row = 1; pnlShift.Layout.Column = 1;
    plGrid = uigridlayout(pnlShift, [2, 7]);
    plGrid.Padding = [2 2 2 2];
    plGrid.RowHeight = {"1x", "1x"};
    plGrid.ColumnWidth = repmat({"1x"}, 1, 7);
    
    upGears = {"12","23","34","45","56","67","78"}; downGears = {"21","32","43","54","65","76","87"};
    gearChecks = containers.Map();
    gearChecksList = {};   % flat list for direct iteration in Clear All
    for i = 1:7
        c = uicheckbox(plGrid, "Text", upGears{i}, "Value", true);
        c.Layout.Row = 1; c.Layout.Column = i;
        gearChecks(upGears{i}) = c;
        gearChecksList{end+1} = c; %#ok<AGROW>
        
        c = uicheckbox(plGrid, "Text", downGears{i}, "Value", true);
        c.Layout.Row = 2; c.Layout.Column = i;
        gearChecks(downGears{i}) = c;
        gearChecksList{end+1} = c; %#ok<AGROW>
    end

    % Panel 2: TCC Lines (Combined)
    pnlTCC = uipanel(configGrid, "Title", "TCC Lines", "FontWeight", "bold");
    pnlTCC.Layout.Row = 1; pnlTCC.Layout.Column = 2;
    ptGrid = uigridlayout(pnlTCC, [2, 8]);
    ptGrid.Padding = [2 2 2 2];
    ptGrid.RowHeight = {"1x", "1x"};
    ptGrid.ColumnWidth = repmat({"1x"}, 1, 8);
    
    tccChecksA = containers.Map();
    tccChecksB = containers.Map();
    tccChecksList = {};   % flat list for Clear All
    for i = 1:8
        % Map A (Row 1)
        c = uicheckbox(ptGrid, "Text", ["G" num2str(i)], "Value", true);
        c.Layout.Row = 1; c.Layout.Column = i;
        tccChecksA(num2str(i)) = c;
        tccChecksList{end+1} = c; %#ok<AGROW>
        
        % Map B (Row 2)
        c = uicheckbox(ptGrid, "Text", ["G" num2str(i)], "Value", true);
        c.Layout.Row = 2; c.Layout.Column = i;
        tccChecksB(num2str(i)) = c;
        tccChecksList{end+1} = c; %#ok<AGROW>
    end

    % Panel 3: Context Info — simple grid, no scroll, original compact style
    ctxPanel = uipanel(configGrid, 'BorderType', 'line', ...
        'BackgroundColor', [0.94 0.94 0.94]);
    ctxPanel.Layout.Row = 1; ctxPanel.Layout.Column = 3;
    ctxInnerGrid = uigridlayout(ctxPanel, [1,1], ...
        'RowHeight', {'1x'}, 'ColumnWidth', {'1x'}, ...
        'Padding', [4 2 4 2], 'BackgroundColor', [0.94 0.94 0.94]);
    appData.contextLabel = uilabel(ctxInnerGrid, 'HorizontalAlignment', 'left', ...
        'VerticalAlignment', 'top', 'WordWrap', 'on', ...
        'FontSize', 10, 'Interpreter', 'html', 'Text', '<b>Select a Map...</b>', ...
        'BackgroundColor', [0.94 0.94 0.94]);
    appData.contextLabel.Layout.Row = 1; appData.contextLabel.Layout.Column = 1;
    
    % --- ROW 3: PLOT AREA ---
    plotGrid = uigridlayout(mainGrid, [1, 2]);
    plotGrid.ColumnWidth = {'1x', 160}; % Legend Width Reduced to 160
    plotGrid.Padding = [0 0 0 0];
    plotGrid.ColumnSpacing = 0;

    ax = uiaxes(plotGrid);
    xlim(ax, [0 8000]); ylim(ax, [0 110]); grid(ax, 'on');
    title(ax, 'Shift Pattern Comparison'); xlabel(ax, 'Output Shaft RPM'); ylabel(ax, 'Pedal (%)');
    % --- 2nd Axis Setup ---
    ax2 = uiaxes(plotGrid);
    ax2.Layout.Row = 1; ax2.Layout.Column = 1;
    ax2.Color = "none"; ax2.Box = "off";
    ax2.XAxisLocation = "top"; ax2.YAxis.Visible = "off";
    ax2.Visible = "off";
    ax2.HitTest = "off"; ax2.PickableParts = "none";

    % --- 3rd Axis Setup (Engine RPM) ---
    ax3 = uiaxes(plotGrid);
    ax3.Layout.Row = 1; ax3.Layout.Column = 1;
    ax3.Color = 'none'; ax3.Box = 'off';
    ax3.YAxisLocation = 'right'; ax3.XAxis.Visible = 'off';
    ax3.HitTest = 'off'; ax3.PickableParts = 'none';
    ylabel(ax3, 'Engine RPM');

    % --- Listeners: sync ax2/ax3 on zoom/pan/reset ---------------------------
    % XLim/YLim  -> fires on zoom-in and pan
    % XLimMode/YLimMode -> fires on zoom-reset (mode goes auto, then limits recalc)
    addlistener(ax, 'XLim',     'PostSet', @(~,~) syncSecondaryAxes(fig));
    addlistener(ax, 'YLim',     'PostSet', @(~,~) syncSecondaryAxes(fig));
    addlistener(ax, 'XLimMode', 'PostSet', @(~,~) syncSecondaryAxesDeferred(fig));
    addlistener(ax, 'YLimMode', 'PostSet', @(~,~) syncSecondaryAxesDeferred(fig));
    % Resize sync: fires when window resizes, ax.Position changes
    addlistener(ax, 'Position', 'PostSet', @(~,~) syncSecondaryAxesDeferred(fig));

    hold(ax, 'on');

    vLine = plot(ax, [-100 -100], ylim(ax), '--', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8, 'Tag', 'permCrosshair', 'PickableParts', 'none', 'HitTest', 'off', 'HandleVisibility', 'off');
    hLine = plot(ax, xlim(ax), [-100 -100], '--', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8, 'Tag', 'permCrosshair', 'PickableParts', 'none', 'HitTest', 'off', 'HandleVisibility', 'off');
    crossText = text(ax, 0, 0, '', 'BackgroundColor', 'w', 'EdgeColor', 'k', 'Visible', 'off', 'Tag', 'permCrosshair', 'PickableParts', 'none', 'Interpreter', 'tex');

    legendPanel = uipanel(plotGrid, 'Title', 'Legend', 'Scrollable', 'on');
    
    % === CONTEXT MENU ===
    refreshCM = uicontextmenu(fig);
    uimenu(refreshCM, 'Text', 'Refresh Plot', 'MenuSelectedFcn', @(~,~) updatePlot(fig));
    ax.ContextMenu = refreshCM;

    % --- ROW 4: BUTTONS ---
    btnGrid = uigridlayout(mainGrid, [1, 10]);
    btnGrid.Padding = [0 0 0 0];
    
    buttonStyle = {'BackgroundColor', [0.9 0.95 1], 'FontWeight', 'bold'};
    uibutton(btnGrid, 'Text', 'Save Modified Map', buttonStyle{:}, 'ButtonPushedFcn', @(~,~) saveModifiedMap(fig));
    uibutton(btnGrid, 'Text', 'Export', buttonStyle{:}, 'ButtonPushedFcn', @(~,~) exportHandler(fig));
    uibutton(btnGrid, 'Text', 'Edit Map A', buttonStyle{:}, 'ButtonPushedFcn', @(~,~) openTableEditor(fig));
    uibutton(btnGrid, 'Text', 'Edit Multi Maps', buttonStyle{:}, 'ButtonPushedFcn', @(~,~) openMultiMapEditor(fig));
    uibutton(btnGrid, 'Text', 'STAT & UK Table', buttonStyle{:}, 'ButtonPushedFcn', @(~,~) openUKTable(fig));
    uibutton(btnGrid, 'Text', 'TCC Editor', buttonStyle{:},'ButtonPushedFcn', @(~,~) openTCCEditor(fig));
    uibutton(btnGrid, 'Text', 'Interpolation', buttonStyle{:},'ButtonPushedFcn', @(~,~) openInterpWithWarning(fig));    
    uibutton(btnGrid, 'Text', '2D & 3D Plots', buttonStyle{:},'ButtonPushedFcn', @(~,~) Genplots(fig));
    uibutton(btnGrid, 'Text', 'Analyse Maps', 'BackgroundColor', [0.9 0.95 1], ...
        'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~) openMapAnalysis(fig));
    % Save All Session button — visible only when Hold & Save Session is active
    btnSaveAll = uibutton(btnGrid, 'Text', '💾 Save All (A+B+C)', ...
        'BackgroundColor', [0.1 0.55 0.1], 'FontColor', [1 1 1], 'FontWeight', 'bold', ...
        'Tooltip', 'Save all 3 maps (A, B, C) one by one through the Save Modified Map dialog', ...
        'Visible', 'off', ...
        'ButtonPushedFcn', @(~,~) saveHoldSession(fig));

    % Status bar moved to top-right of topPanel — see rightGrid row 1

    % === HANDLES & CALLBACKS ===
    handles = struct('ax', ax, 'ax2', ax2, 'ax3', ax3, 'vLine', vLine, 'hLine', hLine, 'crossText', crossText, 'legendPanel', legendPanel);
    handles.refreshCM = refreshCM;
    handles.fileLabel = fileLbl;
    handles.refLabel   = refLbl;
    handles.lblMapB     = lblMapB;
    handles.cbRefMode   = cbRefMode;
    % handles.statusBar removed in V7.6.3 — status now lives in figure title bar
    handles.fileLabelB  = fileLblB;   % stacked B label on left side
    handles.fileLabelC  = fileLblC;   % stacked C label on left side
    handles.dd1 = dd1; handles.dd2 = dd2; handles.dd3 = dd3;
    handles.cb1 = cb1; handles.cb2 = cb2; handles.cb3 = cb3;
    handles.cbSwapC = cbSwapC;
    % Save/Load buttons removed in V7.6.3 — fields no longer set
    handles.cbEdit = cbEdit; handles.cbAllowY = cbAllowY; handles.cb4Lo = cb4Lo; handles.cbLines = cbLines; handles.cbTCC = cbTCC;
    handles.cbLegend = cbLegend;
    handles.ddAxis = ddAxis;
    handles.cbClearAll = cbClearAll;
    handles.cbHoldSave = cbHoldSave;
    handles.cbSyncINCA = cbSyncINCA;
    handles.btnSaveAll = btnSaveAll;
    handles.gearChecks = gearChecks;
    handles.gearChecksList = gearChecksList;
    handles.tccChecksA = tccChecksA;
    handles.tccChecksB = tccChecksB;
    handles.tccChecksList = tccChecksList;
    handles.plotGrid = plotGrid; % Save grid handle for toggling

    appData.handles = handles; appData.currentMapName = dd1.Value; 
    
    % Update File Label
    if isfield(appData, 'sourceFilename')
        handles.fileLabel.Text = ['A: ' appData.sourceFilename];
    else
        handles.fileLabel.Text = 'A: (Project)';
    end
    
    fig.UserData = appData;

    % Callbacks
    updateWrap = @(~,~) updatePlot(fig);
    
    dd1.ValueChangedFcn = @(src, event) checkMapSwitch(fig, src, event);
    dd2.ValueChangedFcn = @(src,~) onMapBSwitch(fig, src);
    dd3.ValueChangedFcn = updateWrap;
    cb1.ValueChangedFcn = updateWrap; cb2.ValueChangedFcn = updateWrap; cb3.ValueChangedFcn = updateWrap;
    cbEdit.ValueChangedFcn  = updateWrap;
    cbLines.ValueChangedFcn = updateWrap;
    cb4Lo.ValueChangedFcn = updateWrap;
    cbTCC.ValueChangedFcn = updateWrap;
    ddAxis.ValueChangedFcn = updateWrap;

    % Hold & Save Session — toggle Save All button visibility
    cbHoldSave.ValueChangedFcn = @(src,~) onHoldSaveToggle(fig, src.Value);

    % Sync to INCA — verify INCA is reachable when enabling
    cbSyncINCA.ValueChangedFcn = @(src,~) onSyncINCAToggle(fig, src);
    cbRefMode.ValueChangedFcn  = @(src,~) onRefModeToggle(fig, src);

    % Clear All Lines — toggles every gear and TCC checkbox off/on
    cbClearAll.ValueChangedFcn = @(src,~) onClearAllLines(fig, src.Value);

    % Legend Toggle Callback
    cbLegend.ValueChangedFcn = @(src, event) toggleLegendLayout(fig, src.Value);
    
    % Connect Gear Checks via flat list — avoids containers.Map string/char key mismatch
    for i = 1:numel(gearChecksList)
        gearChecksList{i}.ValueChangedFcn = @(src,~) onIndividualLineCheck(fig, src);
    end

    % Connect TCC Checks via flat list
    for i = 1:numel(tccChecksList)
        tccChecksList{i}.ValueChangedFcn = @(src,~) onIndividualLineCheck(fig, src);
    end

    fig.WindowButtonMotionFcn = @(src, event) passiveCrosshair(fig);
    fig.WindowKeyPressFcn = @(src, event) onKeyPress(fig, event);

    % === MENU BAR (V7.6.3) ===
    try
        mFile = uimenu(fig, 'Text', '&File');
        mnuLoadProject = uimenu(mFile, 'Text', 'Load Project...', 'Accelerator','O', ...
            'MenuSelectedFcn', @(~,~) loadProject(fig));
        mnuSaveProject = uimenu(mFile, 'Text', 'Save Project', 'Accelerator','S', ...
            'MenuSelectedFcn', @(~,~) saveProject(fig));
        mnuRecent = uimenu(mFile, 'Text', 'Recent Files', 'Separator','on');
        uimenu(mFile, 'Text', 'Reference Database Builder...', 'Separator','on', ...
            'MenuSelectedFcn', @(~,~) launchRefDBBuilder());

        % Stash menu handles so session-lock and recent-files can find them
        appData2 = fig.UserData;
        appData2.handles.mnuRecent      = mnuRecent;
        appData2.handles.mnuLoadProject = mnuLoadProject;
        appData2.handles.mnuSaveProject = mnuSaveProject;
        fig.UserData = appData2;
        recentFilesMenuRefresh(fig);

        mEdit = uimenu(fig, 'Text', '&Edit');
        uimenu(mEdit, 'Text', 'Undo', 'Accelerator','Z', ...
            'MenuSelectedFcn', @(~,~) performUndo(fig));

        mHelp = uimenu(fig, 'Text', '&Help');
        uimenu(mHelp, 'Text', 'Support && Contact', ...
            'MenuSelectedFcn', @(~,~) showHelp(fig, 1));
        uimenu(mHelp, 'Text', 'Special Thanks', ...
            'MenuSelectedFcn', @(~,~) showHelp(fig, 2));
        uimenu(mHelp, 'Text', 'Report && Request', ...
            'MenuSelectedFcn', @(~,~) showHelp(fig, 3));
        uimenu(mHelp, 'Text', 'Version History', ...
            'MenuSelectedFcn', @(~,~) showHelp(fig, 4));
        uimenu(mHelp, 'Text', 'Session History...', 'Separator','on', ...
            'MenuSelectedFcn', @(~,~) showSessionLog(fig));
        uimenu(mHelp, 'Text', 'Diagnostic Log', ...
            'MenuSelectedFcn', @(~,~) showDiagnosticLog(fig));
        uimenu(mHelp, 'Text', 'About...', 'Separator','on', ...
            'MenuSelectedFcn', @(~,~) showAboutDialog(fig));
    catch ME
        diagnosticLogPush('MenuBar', ME);
    end

    % === AUTO-SAVE TIMER (V7.5.2) — saves snapshot every 60s ===
    try
        autoSaveTimer = timer('ExecutionMode','fixedSpacing','Period',60,...
            'BusyMode','drop','TimerFcn',@(~,~) autoSaveTick(fig),...
            'Name','PP_AutoSaveTimer');
        start(autoSaveTimer);
        appData2 = fig.UserData;
        appData2.handles.autoSaveTimer = autoSaveTimer;
        fig.UserData = appData2;
    catch ME
        diagnosticLogPush('AutoSaveTimer', ME);
    end

    % === STARTUP TASKS ===
    refreshStatusBar(fig);
    try, updateMapSourceLabels(fig); catch; end
    updatePlot(fig);

    % Check for orphaned auto-save (deferred so main UI is fully visible first)
    try
        drawnow;
        checkAutoSaveOnStartup(fig);
    catch ME
        diagnosticLogPush('StartupAutoSave', ME);
    end
end
%% === LEGEND TOGGLE FUNCTION ===
function toggleLegendLayout(fig, isVisible)
    appData = fig.UserData;
    pg = appData.handles.plotGrid;
    if isVisible
        pg.ColumnWidth = {'1x', 160}; % Reduced width
        appData.handles.legendPanel.Visible = 'on';
        updatePlot(fig); % Refresh legend content
    else
        pg.ColumnWidth = {'1x', 0};
        appData.handles.legendPanel.Visible = 'off';
    end
end
%% === UK TABLE WINDOW ===
function openUKTable(fig)
    appData = fig.UserData;
    if isfield(appData, 'ukFig') && hasValidHandle(appData, 'ukFig')
        appData.ukFig.Visible = 'on'; figure(appData.ukFig); return;
    end

    % UK table always opens with WORKING FILE data.
    % The swap button triggers refreshAllUKTabsIfOpen which switches to ref data
    % when Map A holds a [REF] map (isWCRef && isRefMode).
    srcUKData    = appData.ukData;
    srcStatTabul = appData.statTabul;
    srcStatRows  = appData.statRowNames;
    srcT         = appData.T;
    % Label: show ref notice if ref mode is on so user knows ref is loaded
    isRefMode = isfield(appData,'isRefMode') && appData.isRefMode && isfield(appData,'refVehicle');

    ukFig = uifigure('Name', 'UK & STAT Table', 'Position', [150 150 900 650]);
    ukFig.CloseRequestFcn = @(src,e) closeUKTable(fig, src);
    ukFig.WindowKeyPressFcn = @(src,e) onUKKeyPress(fig, e);
    appData.ukFig = ukFig;

    appData.ukHistory = {}; appData.statShadowData = appData.statTabul;
    fig.UserData = appData;

    gl = uigridlayout(ukFig, [1 1]); tg = uitabgroup(gl);

    % === PRE-PROCESS FSIT DATA FOR UK TABLE LOGIC ===
    % Use canonical FSIT variable list (shared with computeActiveAbbrevs)
    fsitVars = { ...
        'FSIT_SWIFO', 'FSIT_SWIKE', 'FSIT_SWIDSD', 'FSIT_SWIBA', 'FSIT_SWIBE', ...
        'FSIT_SWIHM', 'FSIT_SWISUS', 'FSIT_SWIZW', 'FSIT_SWIVSA', 'FSIT_SWIECO', ...
        'FSIT_SWIFCO', 'FSIT_SWIWA', 'FSIT_SWISNG', 'FSIT_SWIEVA', 'FSIT_SWICM', ...
        'FSIT_SWISW_SWVrnt1', 'FSIT_SWISW_SWVrnt2', 'FSIT_SWISW_SWVrnt3', ...
        'FSIT_SWIOD', 'FSIT_SWIREV', 'FSIT_SWIWE', 'FSIT_SWIALT' ...
    };
    fsitVars = unique(fsitVars, 'stable');

    % Build FSIT display data — from working file T only (ref vehicle T not stored)
    fsitData = cell(length(fsitVars), 3);
    for k = 1:length(fsitVars)
        fsitData{k, 1} = fsitVars{k};
        if ~isempty(srcT)
            fsitData{k, 2} = extractFSITValue(srcT, fsitVars{k});
        else
            fsitData{k, 2} = '(N/A)';  % ref vehicle — no T matrix
        end
        fsitData{k, 3} = getFSITDesc(fsitVars{k});
    end
    if ~isempty(srcT) && isfield(appData,'activeAbbrevs') && ~isempty(appData.activeAbbrevs)
        activeAbbrevs = appData.activeAbbrevs;
    elseif ~isempty(srcT)
        activeAbbrevs = computeActiveAbbrevs(srcT);
    else
        activeAbbrevs = {};
    end

    % === PRE-PROCESS UK TABLE DATA (from correct source) ===
    origUK = ukEnsureULUSPDSP(srcUKData);
    if ~isRefMode
        % Only update appData.ukData for working file (don't overwrite with ref data)
        appData.ukData = origUK;
        fig.UserData   = appData;
    end

    newUK = cell(size(origUK, 1), 9);
    % Col layout: 1=UK, 2=Abbrev, 3=FSIT_Act(computed), 4=ID, 5=SKLID, 6=UL, 7=USP, 8=DSP, 9=Map Numbers
    newUK(:, [1, 2, 4, 5, 6, 7, 8, 9]) = origUK(:, [1, 2, 3, 4, 5, 6, 7, 8]);
    
    for i = 1:size(newUK, 1)
        abbrev = newUK{i, 2};
        % Check if abbreviation matches any active FSIT token
        % Simple partial match or exact match logic? Requirement says "matches Abbrev"
        % We will do a basic contains or exact match.
        % Based on "UKSVF_" in FSIT vs "UKSVF" in table, we might need contains.
        % But for now, let's try exact match against the token list.
        % Actually, tokens like 'UKSVF_' are prefixes. 
        % Let's use `contains` for safety if abbrev is a subset.
        match = false;
        for j = 1:length(activeAbbrevs)
            token = activeAbbrevs{j};
            if ~isempty(token) && contains(abbrev, token, 'IgnoreCase', true)
                match = true;
                break;
            end
        end
        
        if match
            newUK{i, 3} = 'Yes';
        else
            newUK{i, 3} = 'No';
        end
    end

    tab1 = uitab(tg, 'Title', 'UK Table'); gl1 = uigridlayout(tab1, [2 1]); gl1.RowHeight = {40, '1x'};
    pnlFilter = uipanel(gl1); flayout = uigridlayout(pnlFilter, [1 8]); flayout.ColumnWidth = {100, 150, 20, 120, 150, 10, '1x', 130}; flayout.Padding = [5 4 5 4]; flayout.RowSpacing = 0;
    uilabel(flayout, 'Text', 'Filter by SKLID:', 'FontWeight', 'bold', 'HorizontalAlignment', 'right');
    efFilter = uieditfield(flayout, 'text', 'ValueChangedFcn', @(src,e) updateUKTableFilters(ukFig, fig));
    uilabel(flayout, 'Text', ''); % spacer
    uilabel(flayout, 'Text', 'Filter by Map #:', 'FontWeight', 'bold', 'HorizontalAlignment', 'right');
    efMapFilter = uieditfield(flayout, 'text', 'ValueChangedFcn', @(src,e) updateUKTableFilters(ukFig, fig));
    uilabel(flayout, 'Text', ''); % spacer
    % Filename label — shows the source file used to populate this table
    % Show source filename — or reference vehicle description if ref mode active
    % Show filename; if ref mode on, hint that swap will show ref data
    if isRefMode && isfield(appData,'refVehicle')
        ukSrcName = [char(appData.sourceFilename) '  |  Swap → [REF] ' char(appData.refVehicle.meta.description)];
    else
        ukSrcName = char(appData.sourceFilename);
    end
    ukFileLabel = uilabel(flayout, ...
        'Text', ukSrcName, ...
        'HorizontalAlignment', 'right', ...
        'FontAngle', 'italic', ...
        'FontColor', [0.3 0.3 0.3], ...
        'Tooltip', 'Source file used to populate this UK & STAT table');
    uibutton(flayout, 'Text', 'Export to Excel', ...
        'BackgroundColor', [0.13 0.54 0.13], 'FontColor', [1 1 1], 'FontWeight', 'bold', 'FontSize', 11, ...
        'ButtonPushedFcn', @(~,~) exportUKTableToExcel(ukFig, fig));
    
    tUK = uitable(gl1, 'Data', newUK, ...
        'ColumnName', {'UK', 'Abbrev', 'FSIT_Act', 'ID', 'SKLID', 'UL', 'USP', 'DSP', 'Map Number'}, ...
        'CellSelectionCallback', @(src, e) onUKTableSelect(src, e, fig));
    tUK.ColumnWidth = {220, 70, 65, 40, 150, 45, 55, 55, '1x'};
    
    tab2 = uitab(tg, 'Title', 'STAT_TABUL'); gl2 = uigridlayout(tab2, [2 1]); gl2.RowHeight = {40, '1x'};

    pnlStatTools = uipanel(gl2);
    statLayout = uigridlayout(pnlStatTools, [1 2]); statLayout.ColumnWidth = {200, '1x'}; statLayout.Padding = [5 5 5 5];
    uibutton(statLayout, 'Text', 'SAVE CHANGES', 'BackgroundColor', [1 0.8 0], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) saveStatChanges(ukFig, fig));

    rowsVar = srcStatRows;
    if length(rowsVar) < size(srcStatTabul,1)
        rowsVar = [rowsVar; repmat({''},size(srcStatTabul,1)-length(rowsVar),1)];
    end
    % Generate 0-based RowNames
    rowNames0 = cellstr(string(0 : size(srcStatTabul,1)-1));
    tStat = uitable(gl2, 'Data', [rowsVar, num2cell(srcStatTabul)], ...
        'ColumnName', [{'Mode'}, cellstr(string(1:size(srcStatTabul,2)))], ...
        'RowName', rowNames0, ...
        'ColumnEditable', true, 'CellEditCallback', @(src, event) onStatEdit(fig, src, event), ...
        'CellSelectionCallback', @(src,e) onStatSelect(ukFig, e));

    cm = uicontextmenu(ukFig);
    uimenu(cm, 'Text', 'Add Offset (+/-)...', 'MenuSelectedFcn', @(~,~) applyStatMath(ukFig, fig, 'add'));
    uimenu(cm, 'Text', 'Multiply (*)...', 'MenuSelectedFcn', @(~,~) applyStatMath(ukFig, fig, 'mult'));
    uimenu(cm, 'Text', 'Divide (/)...', 'MenuSelectedFcn', @(~,~) applyStatMath(ukFig, fig, 'div'));
    uimenu(cm, 'Text', 'Percentage (%)...', 'MenuSelectedFcn', @(~,~) applyStatMath(ukFig, fig, 'percent'));
    uimenu(cm, "Text", "Copy", "Separator", "on", "MenuSelectedFcn", @(~,~) copySelection(tStat));
    uimenu(cm, "Text", "Paste", "MenuSelectedFcn", @(~,~) pasteSelection(tStat, @(s) onStatPaste(ukFig, fig, s)));
    tStat.ContextMenu = cm;

    cmUK = uicontextmenu(ukFig);
    uimenu(cmUK, "Text", "Copy", "MenuSelectedFcn", @(~,~) copySelection(tUK));
    tUK.ContextMenu = cmUK;
    
    % === TAB 3: FSIT VARIABLES ===
    tab3 = uitab(tg, 'Title', 'FSIT');
    gl3 = uigridlayout(tab3, [2 1]);
    gl3.RowHeight = {40, '1x'};
    
    % Toolbar for FSIT
    pnlFSIT = uipanel(gl3);
    fLayout = uigridlayout(pnlFSIT, [1 2]); fLayout.ColumnWidth = {200, '1x'}; fLayout.Padding = [5 5 5 5];
    uibutton(fLayout, 'Text', 'SAVE CHANGES', 'BackgroundColor', [1 0.8 0], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) saveFSITChanges(ukFig, fig));
    
    tFSIT = uitable(gl3, 'Data', fsitData, 'ColumnName', {'Variable', 'Value', 'UK_Tables_Activated'}, ...
        'RowName', [], 'ColumnWidth', {200, 80, 450}, ...
        'ColumnEditable', [false true false], ...
        'CellEditCallback', @(src, e) onFSITEdit(src, e), ...
        'CellSelectionCallback', @(src, e) onFSITSelect(ukFig, e));
    
    % Context Menu
    cmFSIT = uicontextmenu(ukFig);
    uimenu(cmFSIT, 'Text', 'Add Offset (+/-)...', 'MenuSelectedFcn', @(~,~) applyFSITMath(ukFig, 'add'));
    uimenu(cmFSIT, 'Text', 'Multiply (*)...', 'MenuSelectedFcn', @(~,~) applyFSITMath(ukFig, 'mult'));
    uimenu(cmFSIT, 'Text', 'Divide (/)...', 'MenuSelectedFcn', @(~,~) applyFSITMath(ukFig, 'div'));
    uimenu(cmFSIT, "Text", "Copy", "Separator", "on", "MenuSelectedFcn", @(~,~) copySelection(tFSIT));
    uimenu(cmFSIT, "Text", "Paste", "MenuSelectedFcn", @(~,~) pasteSelection(tFSIT));
    tFSIT.ContextMenu = cmFSIT;

    % === TAB 4: GEAR RATIO ===
    goldBtnStyle = {'BackgroundColor', [1 0.8 0], 'FontWeight', 'bold'};
    tab4 = uitab(tg, 'Title', 'Gear Ratio');
    gl4 = uigridlayout(tab4, [2 1]); gl4.RowHeight = {'1x', 45};
    
    % Create gear ratio data table from userInputs
    if isRefMode && isfield(appData.refVehicle,'vehicle')
        gearRatioData = getGearRatioDataFromInputStruct(appData.refVehicle.vehicle);
    else
        gearRatioData = getGearRatioDataFromUserInputs(fig);
    end
    if isempty(gearRatioData)
        gearRatioData = {'No Data', 0, '-', 'Load CSV to populate'};
    end
    tGearRatio = uitable(gl4, 'Data', gearRatioData, ...
        'ColumnName', {'Parameter', 'Value', 'Unit', 'Description'}, ...
        'ColumnWidth', {180, 120, 80, 350}, ...
        'ColumnEditable', [false true false false], ...
        'FontSize', 12, ...
        'CellEditCallback', @(src,e) onGearRatioEditUK(ukFig, src, e), ...
        'CellSelectionCallback', @(src,e) onGearRatioSelect(ukFig, e));
    
    cmGR = uicontextmenu(ukFig);
    uimenu(cmGR, 'Text', 'Add Offset (+/-)...', 'MenuSelectedFcn', @(~,~) applyGearRatioMath(ukFig, fig, 'add'));
    uimenu(cmGR, 'Text', 'Multiply (*)...', 'MenuSelectedFcn', @(~,~) applyGearRatioMath(ukFig, fig, 'mult'));
    uimenu(cmGR, 'Text', 'Divide (/)...', 'MenuSelectedFcn', @(~,~) applyGearRatioMath(ukFig, fig, 'div'));
    uimenu(cmGR, 'Text', 'Percentage (%)...', 'MenuSelectedFcn', @(~,~) applyGearRatioMath(ukFig, fig, 'percent'));
    uimenu(cmGR, "Text", "Copy", "Separator", "on", "MenuSelectedFcn", @(~,~) copySelection(tGearRatio));
    uimenu(cmGR, "Text", "Paste", "MenuSelectedFcn", @(~,~) pasteSelection(tGearRatio, @(s) onGearRatioPasteUK(ukFig, fig, s)));
    tGearRatio.ContextMenu = cmGR;
    
    pnlGR = uipanel(gl4);
    grLayout = uigridlayout(pnlGR, [1 2]); grLayout.ColumnWidth = {200, '1x'}; grLayout.Padding = [5 5 5 5];
    uibutton(grLayout, 'Text', 'SAVE CHANGES', goldBtnStyle{:}, 'ButtonPushedFcn', @(~,~) saveGearRatioDataUK(ukFig, fig));

    % === TAB 5: GBF_TABSS (MAP format) ===
    tab5 = uitab(tg, 'Title', 'GBF_TABSS');
    gl5 = uigridlayout(tab5, [2 1]); gl5.RowHeight = {'1x', 45};
    
    % Extract GBF_TABSS data using extractInterpVariable approach
    gbfVI = []; if ~isempty(srcT), gbfVI = extractInterpVariable(srcT, 'GBF_TABSS'); end
    if ~isempty(gbfVI) && ~isempty(gbfVI.data)
        if ~isempty(gbfVI.yAxis)
            gbfRowNames = cellstr(string(gbfVI.yAxis));
        else
            gbfRowNames = cellstr(string(1:size(gbfVI.data, 1)));
        end
        if ~isempty(gbfVI.xAxis)
            gbfColNames = cellstr(string(gbfVI.xAxis));
        else
            gbfColNames = cellstr(string(1:size(gbfVI.data, 2)));
        end
        tGBFData = num2cell(gbfVI.data);
    else
        gbfColNames = {'1', '2', '3'};
        gbfRowNames = {'1'};
        tGBFData = {0, 0, 0};
        gbfVI = struct('data', zeros(1,3), 'xAxis', [], 'yAxis', []);
    end
    
    tGBFTabss = uitable(gl5, 'Data', tGBFData, ...
        'ColumnName', gbfColNames, ...
        'RowName', gbfRowNames, ...
        'ColumnEditable', true, ...
        'CellEditCallback', @(src,e) onGBFEdit(ukFig, src, e), ...
        'CellSelectionCallback', @(src,e) onGBFSelect(ukFig, e));
    
    cmGBF = uicontextmenu(ukFig);
    uimenu(cmGBF, 'Text', 'Add Offset (+/-)...', 'MenuSelectedFcn', @(~,~) applyGBFMath(ukFig, fig, 'add'));
    uimenu(cmGBF, 'Text', 'Multiply (*)...', 'MenuSelectedFcn', @(~,~) applyGBFMath(ukFig, fig, 'mult'));
    uimenu(cmGBF, 'Text', 'Divide (/)...', 'MenuSelectedFcn', @(~,~) applyGBFMath(ukFig, fig, 'div'));
    uimenu(cmGBF, 'Text', 'Percentage (%)...', 'MenuSelectedFcn', @(~,~) applyGBFMath(ukFig, fig, 'percent'));
    uimenu(cmGBF, "Text", "Copy", "Separator", "on", "MenuSelectedFcn", @(~,~) copySelection(tGBFTabss));
    uimenu(cmGBF, "Text", "Paste", "MenuSelectedFcn", @(~,~) pasteSelection(tGBFTabss, @(s) onGBFPaste(ukFig, fig, s)));
    tGBFTabss.ContextMenu = cmGBF;
    
    pnlGBF = uipanel(gl5);
    gbfLayout = uigridlayout(pnlGBF, [1 2]); gbfLayout.ColumnWidth = {200, '1x'}; gbfLayout.Padding = [5 5 5 5];
    uibutton(gbfLayout, 'Text', 'SAVE CHANGES', goldBtnStyle{:}, 'ButtonPushedFcn', @(~,~) saveGBFChanges(ukFig, fig));

    % === TAB 6: Curve Eng Spd (UKKE_FacEngSpdMax + UKKE_NMAX) ===
    tab6 = uitab(tg, 'Title', 'Curve Eng Spd');
    gl6 = uigridlayout(tab6, [3 1]); gl6.RowHeight = {'2x', '1x', 45};
    
    % Panel for UKKE_FacEngSpdMax (MAP format)
    pnlFacEngSpd = uipanel(gl6, 'Title', 'UKKE_FacEngSpdMax (MAP)', 'FontWeight', 'bold');
    glFac = uigridlayout(pnlFacEngSpd, [1 1]);
    
    facVI = []; if ~isempty(srcT), facVI = extractInterpVariable(srcT, 'UKKE_FacEngSpdMax'); end
    if ~isempty(facVI) && ~isempty(facVI.data)
        if ~isempty(facVI.yAxis)
            facRowNames = cellstr(string(facVI.yAxis));
        else
            facRowNames = cellstr(string(1:size(facVI.data, 1)));
        end
        if ~isempty(facVI.xAxis)
            facColNames = cellstr(string(facVI.xAxis));
        else
            facColNames = cellstr(string(1:size(facVI.data, 2)));
        end
        tFacData = num2cell(facVI.data);
    else
        facColNames = {'1'};
        facRowNames = {'1'};
        tFacData = {0};
        facVI = struct('data', 0, 'xAxis', [], 'yAxis', []);
    end
    
    tFacEngSpd = uitable(glFac, 'Data', tFacData, ...
        'ColumnName', facColNames, ...
        'RowName', facRowNames, ...
        'ColumnEditable', true, ...
        'CellEditCallback', @(src,e) onFacEngSpdEdit(ukFig, src, e), ...
        'CellSelectionCallback', @(src,e) onFacEngSpdSelect(ukFig, e));
    
    cmFac = uicontextmenu(ukFig);
    uimenu(cmFac, 'Text', 'Add Offset (+/-)...', 'MenuSelectedFcn', @(~,~) applyFacEngSpdMath(ukFig, fig, 'add'));
    uimenu(cmFac, 'Text', 'Multiply (*)...', 'MenuSelectedFcn', @(~,~) applyFacEngSpdMath(ukFig, fig, 'mult'));
    uimenu(cmFac, 'Text', 'Divide (/)...', 'MenuSelectedFcn', @(~,~) applyFacEngSpdMath(ukFig, fig, 'div'));
    uimenu(cmFac, 'Text', 'Percentage (%)...', 'MenuSelectedFcn', @(~,~) applyFacEngSpdMath(ukFig, fig, 'percent'));
    uimenu(cmFac, "Text", "Copy", "Separator", "on", "MenuSelectedFcn", @(~,~) copySelection(tFacEngSpd));
    uimenu(cmFac, "Text", "Paste", "MenuSelectedFcn", @(~,~) pasteSelection(tFacEngSpd, @(s) onFacEngSpdPaste(ukFig, fig, s)));
    tFacEngSpd.ContextMenu = cmFac;
    
    % Panel for UKKE_NMAX (CURVE format)
    pnlNmax = uipanel(gl6, 'Title', 'UKKE_NMAX (CURVE)', 'FontWeight', 'bold');
    glNmax = uigridlayout(pnlNmax, [1 1]);
    
    nmaxVI = []; if ~isempty(srcT), nmaxVI = extractInterpVariable(srcT, 'UKKE_NMAX'); end
    if ~isempty(nmaxVI) && ~isempty(nmaxVI.data)
        if ~isempty(nmaxVI.xAxis)
            nmaxColNames = cellstr(string(nmaxVI.xAxis));
        else
            nmaxColNames = cellstr(string(1:length(nmaxVI.data)));
        end
        % Build 2-row table like INCA style: X-axis + Value
        tNmaxData = cell(2, length(nmaxVI.data));
        for c = 1:length(nmaxVI.data)
            if ~isempty(nmaxVI.xAxis) && c <= length(nmaxVI.xAxis)
                tNmaxData{1, c} = nmaxVI.xAxis(c);
            else
                tNmaxData{1, c} = c;
            end
            tNmaxData{2, c} = nmaxVI.data(c);
        end
        nmaxColNamesNum = cellstr(string(1:length(nmaxVI.data)));
    else
        nmaxColNamesNum = {'1', '2', '3', '4', '5', '6', '7'};
        tNmaxData = {1,2,3,4,5,6,7; 0,0,0,0,0,0,0};
        nmaxVI = struct('data', zeros(1,7), 'xAxis', 1:7);
    end
    
    tNmax = uitable(glNmax, 'Data', tNmaxData, ...
        'ColumnName', nmaxColNamesNum, ...
        'RowName', {'Gear', 'RPM'}, ...
        'ColumnEditable', true, ...
        'CellEditCallback', @(src,e) onNmaxEdit(ukFig, src, e), ...
        'CellSelectionCallback', @(src,e) onNmaxSelect(ukFig, e));
    
    cmNmax = uicontextmenu(ukFig);
    uimenu(cmNmax, 'Text', 'Add Offset (+/-)...', 'MenuSelectedFcn', @(~,~) applyNmaxMath(ukFig, fig, 'add'));
    uimenu(cmNmax, 'Text', 'Multiply (*)...', 'MenuSelectedFcn', @(~,~) applyNmaxMath(ukFig, fig, 'mult'));
    uimenu(cmNmax, 'Text', 'Divide (/)...', 'MenuSelectedFcn', @(~,~) applyNmaxMath(ukFig, fig, 'div'));
    uimenu(cmNmax, 'Text', 'Percentage (%)...', 'MenuSelectedFcn', @(~,~) applyNmaxMath(ukFig, fig, 'percent'));
    uimenu(cmNmax, "Text", "Copy", "Separator", "on", "MenuSelectedFcn", @(~,~) copySelection(tNmax));
    uimenu(cmNmax, "Text", "Paste", "MenuSelectedFcn", @(~,~) pasteSelection(tNmax, @(s) onNmaxPaste(ukFig, fig, s)));
    tNmax.ContextMenu = cmNmax;
    
    % Save button panel
    pnlCurveEngSpd = uipanel(gl6);
    curveLayout = uigridlayout(pnlCurveEngSpd, [1 2]); curveLayout.ColumnWidth = {200, '1x'}; curveLayout.Padding = [5 5 5 5];
    uibutton(curveLayout, 'Text', 'SAVE CHANGES', goldBtnStyle{:}, 'ButtonPushedFcn', @(~,~) saveCurveEngSpdChanges(ukFig, fig));

    % Store handles and data info
    % Store handles and data info – add ukDirty flag for save-before-close tracking
    ukFig.UserData = struct('tUK', tUK, 'tStat', tStat, 'tFSIT', tFSIT, 'tGearRatio', tGearRatio, 'ukFileLabel', ukFileLabel, ...
        'tGBFTabss', tGBFTabss, 'tFacEngSpd', tFacEngSpd, 'tNmax', tNmax, ...
        'gbfVI', gbfVI, 'facVI', facVI, 'nmaxVI', nmaxVI, ...
        'filterField', efFilter, 'mapFilterField', efMapFilter, ...
        'statSelection', [], 'fsitSelection', [], ...
        'gearRatioSelection', [], 'gbfSelection', [], 'facEngSpdSelection', [], 'nmaxSelection', [], ...
        'fullDisplayData', {newUK}, 'ukDirty', false, 'mainFig', fig);
    updateUKTableFilters(ukFig, fig);
end

function onFSITEdit(src, event)
    if isempty(event.Indices), return; end
    addStyle(src, getYellowStyle(), 'cell', event.Indices);
    fig2 = ancestor(src, 'figure');
    if ~isempty(fig2) && isvalid(fig2)
        h2 = fig2.UserData; h2.ukDirty = true; fig2.UserData = h2;
        try
            if event.Indices(2) == 2
                r = event.Indices(1);
                fsitVar = char(src.Data{r,1}); newVal = src.Data{r,2};
                mainFig = h2.mainFig;
                if ~isempty(mainFig) && isvalid(mainFig), showFSITImpact(mainFig, fsitVar, newVal); end
            end
        catch; end
    end
end

function onFSITSelect(ukFig, event)
    h = ukFig.UserData; h.fsitSelection = event.Indices; ukFig.UserData = h;
end

function applyFSITMath(ukFig, op)
    h = ukFig.UserData; tFSIT = h.tFSIT; sel = h.fsitSelection;
    if isempty(sel), uialert(ukFig, 'Select cells first.', 'Error'); return; end
    
    prompt = ""; def = "0";
    switch op
        case 'add', prompt = "Add Value:";
        case 'mult', prompt = "Multiply by:"; def="1";
        case 'div', prompt = "Divide by:"; def="1";
    end
    answer = inputdlg(prompt, 'Math', [1 40], {char(def)});
    if isempty(answer), return; end
    val = str2double(answer{1}); if isnan(val), return; end
    
    data = tFSIT.Data;
    for i = 1:size(sel, 1)
        r = sel(i, 1); c = sel(i, 2);
        if c == 2 % Only modify value column
            curr = data{r, c};
            if isnumeric(curr)
                switch op
                    case 'add', curr = curr + val;
                    case 'mult', curr = curr * val;
                    case 'div', if val~=0, curr = curr / val; end
                end
                data{r, c} = curr;
            end
        end
    end
    tFSIT.Data = data;
    addStyle(tFSIT, getYellowStyle(), 'cell', sel);
end

function saveFSITChanges(ukFig, mainFig)
    if strcmp(uiconfirm(ukFig, 'Overwrite original values?', 'Save', 'Options', {'Yes','Cancel'}), 'Cancel'), return; end
    
    h = ukFig.UserData; tFSIT = h.tFSIT; data = tFSIT.Data;
    appData = mainFig.UserData; T = appData.T;
    
    for i = 1:size(data, 1)
        varName = data{i, 1};
        newVal = data{i, 2};
        
        % Search Logic
        idx = find(contains(T.Var2, varName, 'IgnoreCase', true), 1);
        if isempty(idx) && width(T) >= 1, idx = find(contains(T.Var1, varName, 'IgnoreCase', true), 1); end
        
        if ~isempty(idx)
            % Look for VALUE row
            for r = idx : min(idx + 10, height(T))
                rowTxt = string(table2cell(T(r, 1:min(3, width(T)))));
                if any(contains(rowTxt, "VALUE", 'IgnoreCase', true))
                    if width(T) >= 3, T{r, 3} = {newVal}; end
                    break; 
                end
            end
        end
    end
    
    appData.T = T;
    appData.activeAbbrevs = computeActiveAbbrevs(T);   % refresh FSIT active flags
    mainFig.UserData = appData;
    removeStyle(tFSIT);
    % Reset dirty flag
    h = ukFig.UserData; h.ukDirty = false; ukFig.UserData = h;
    logAction(ukFig, 'FSIT Save', sprintf('%d variables', size(data,1)));
    % Refresh FSIT Status in UK Table
    refreshFSITStatus(ukFig, mainFig);
    uialert(ukFig, 'FSIT Variables Saved.', 'Success');
end

function refreshFSITStatus(ukFig, mainFig)
    h = ukFig.UserData;
    appData = mainFig.UserData;

    % Use cached activeAbbrevs from appData (rebuilt by saveFSITChanges after each save)
    if isfield(appData,'activeAbbrevs') && ~isempty(appData.activeAbbrevs)
        activeAbbrevs = appData.activeAbbrevs;
    else
        activeAbbrevs = computeActiveAbbrevs(appData.T);
    end

    % Update fullDisplayData FSIT_Act column
    fullData = h.fullDisplayData;
    for i = 1:size(fullData, 1)
        abbrev = fullData{i, 2};
        match = false;
        for j = 1:length(activeAbbrevs)
            token = activeAbbrevs{j};
            if ~isempty(token) && contains(abbrev, token, 'IgnoreCase', true)
                match = true; break;
            end
        end
        if match, fullData{i, 3} = 'Yes'; else, fullData{i, 3} = 'No'; end
    end

    h.fullDisplayData = fullData;
    ukFig.UserData = h;

    % Refresh View
    updateUKTableFilters(ukFig, mainFig);
end

function val = extractFSITValue(T, keyword)
    val = NaN;
    % Search Var2 then Var1
    idx = find(contains(T.Var2, keyword, 'IgnoreCase', true), 1);
    if isempty(idx) && width(T) >= 1
        idx = find(contains(T.Var1, keyword, 'IgnoreCase', true), 1);
    end
    
    if ~isempty(idx)
        % Look for VALUE row below
        rStart = idx; 
        rEnd = min(idx + 10, height(T));
        for r = rStart:rEnd
            rowTxt = string(table2cell(T(r, 1:min(3, width(T)))));
            % Check if row starts with VALUE or contains value in 3rd col
            if any(contains(rowTxt, "VALUE", 'IgnoreCase', true))
                % Usually value is in 3rd column (index 3)
                if width(T) >= 3
                    v = str2double(string(T{r, 3}));
                    if ~isnan(v), val = v; return; end
                end
                
                % Fallback: Check numeric conversion of the whole row
                nums = str2double(rowTxt);
                valid = nums(~isnan(nums));
                if ~isempty(valid), val = valid(1); return; end
            end
        end
    end
end

function appData = loadFromCSV(fig)
% Load a new project from a CSV file.
% Returns populated appData on success, or [] if the user cancels at any step.
    appData = [];

    %% === Default Gear Data ===
    defaultData = struct( ...
        'GearRatios', [5.5, 3.52, 2.2, 1.72, 1.301, 1, 0.833, 0.64], ...
        'DynamicCircumference', 407, ...
        'AxleRatio', 3.7, ...
        'LowRangeRatio', 2.72, ...
        'TireCircumference', 2425, ...
        'IdleRPM', 750, ...
        'MaxRPM', 6400 ...
    );
    prefFile = fullfile(prefdir, 'PatternPlotter_Defaults.mat');
    if ~isempty(dir(prefFile))
        try
            savedDefaults = load(prefFile);
            if isfield(savedDefaults, 'userInputs')
                % Merge loaded fields into defaultData to ensure robustness
                loaded = savedDefaults.userInputs;
                fNames = fieldnames(defaultData);
                for k = 1:length(fNames)
                    if isfield(loaded, fNames{k})
                        defaultData.(fNames{k}) = loaded.(fNames{k});
                    end
                end
            end
        catch
            % Ignore load errors, stick to hardcoded defaults
        end
    end

    try
        userInputs = promptGearData(defaultData, prefFile);
    catch
        return;  % User cancelled gear data input
    end

    %% === Load CSV ===
    [filename, filepath] = uigetfile({'*.csv','CSV Files';'*.*','All Files'}, 'Select CSV');
    if isequal(filename, 0), return; end
    fullFilePath = fullfile(filepath, filename);
    if isempty(dir(fullFilePath)), uialert(fig,'File not found.','Error'); return; end

    opts = delimitedTextImportOptions("NumVariables", 122);
    opts.Delimiter = ["\t", ",", ";"];
    opts.VariableTypes = repmat("string", 1, 122);
    opts.ExtraColumnsRule = "ignore"; opts.EmptyLineRule = "read";
    opts = setvaropts(opts, opts.VariableNames, "WhitespaceRule", "preserve", "EmptyFieldRule", "auto");

    try
        T = readtable(fullFilePath, opts);
    catch ME
        uialert(fig, sprintf('Error reading CSV:\n%s', ME.message), 'Error'); return;
    end
    T = fillmissing(T, 'constant', "");

    %% === PRE-PROCESS TABLE (CLEANUP ONLY) ===
    T(startsWith(T.Var1, ["* format", "FUNCTION"], 'IgnoreCase', true), :) = [];
    filenameRow = T(1, :); filenameRow{1, :} = {''}; filenameRow{1, 1} = {filename};
    T = [filenameRow; T];

    % Convert numeric strings to actual numbers — fully vectorized, no loops
    % Extract all cells as a string matrix, convert en-masse, write back numeric cells only
    rawStr = T{:,:};                       % string matrix (all cells)
    rawMat = str2double(rawStr);           % double matrix: NaN for non-numeric
    numMask = ~isnan(rawMat);              % logical mask of purely numeric cells
    if any(numMask(:))
        % Build cell array and assign back in one shot per column (avoids row-loop)
        for cIdx = 1:size(rawMat,2)
            rowIdx = find(numMask(:,cIdx));
            if ~isempty(rowIdx)
                T{rowIdx, cIdx} = num2cell(rawMat(rowIdx, cIdx));
            end
        end
    end
    
    %% === EXTRACT & VALIDATE PARAMETERS (Axle, Tire Circ) ===

% Helper to extract single value from CSV (Function definition moved to end of file)

% Capture Original Inputs for Comparison
originalInputs = userInputs;

% 1. Axle Ratio + Low Range Ratio
% FZGG_AxleRatMpgToldx is a MAP block with structure:
%   Row "[-]": axis values (1, 1, 1...)
%   Row 1:     axle ratio   (3.45, 3.45, 3.45...)  ← use this
%   Row 2:     total ratio  (9.38, 9.38, 9.38...)  ← low range = row2/row1
[csvAxle, csvTotalRatio] = extractAxleMapParam(T, "FZGG_AxleRat");
if isnan(csvAxle), [csvAxle, csvTotalRatio] = extractAxleMapParam(T, "FZGG_AxleRatMpg"); end
if isnan(csvAxle), csvAxle = extractSingleParam(T, "FZGG_RatFinalDrive", 'scalar'); end
if isnan(csvAxle), csvAxle = extractSingleParam(T, "FZGG_AxleRatio", 'scalar'); end

if ~isnan(csvAxle)
    if abs(userInputs.AxleRatio - csvAxle) > 0.001
        userInputs.AxleRatio = csvAxle;
    end
    % Derive low range ratio from the MAP block (total/axle) if explicit key not found
    if ~isnan(csvTotalRatio) && csvAxle > 0.01
        derivedLowRange = csvTotalRatio / csvAxle;
        if derivedLowRange > 1.0 && abs(derivedLowRange - 1.0) > 0.01
            % Derived 4Lo ratio; an explicit FZGG_RatLowRange key below
            % takes priority and overrides this if present.
            userInputs.LowRangeRatio = round(derivedLowRange, 4);
        end
    end
end

% 2. Tire Parameters (Radius & Circumference are coupled)
% Priority: Radius (FZGG_RDYN) > Circumference (FZGG_DynTyreCirc...)

csvRadius = extractSingleParam(T, "FZGG_RDYN", 'scalar');
csvCirc = extractSingleParam(T, "FZGG_DynTyreCircMpgToIdx", 'block');

if ~isnan(csvRadius)
    % Check units (ensure mm). If very small (e.g. < 2.0), likely meters.
    if csvRadius < 2.0, csvRadius = csvRadius * 1000; end
    
    if abs(userInputs.DynamicCircumference - csvRadius) > 1
         userInputs.DynamicCircumference = csvRadius;
         % Force update of Circumference based on Radius
         userInputs.TireCircumference = round(csvRadius * 2 * pi);
    end      
    
elseif ~isnan(csvCirc)
    % Fallback: Radius not found, but Circumference found
    if csvCirc < 10, csvCirc = csvCirc * 1000; end
    
    if abs(userInputs.TireCircumference - csvCirc) > 1
        userInputs.TireCircumference = csvCirc;
        % Derive Radius
        userInputs.DynamicCircumference = csvCirc / (2 * pi);
    end
end

% 4. Low Range Ratio (explicit key takes priority over value derived from axle MAP block)
csvLow = extractSingleParam(T, "FZGG_RatLowRange", 'scalar');
if isnan(csvLow), csvLow = extractSingleParam(T, "FZGG_RatioLowRange", 'scalar'); end
if isnan(csvLow), csvLow = extractSingleParam(T, "FZGG_LowRangeRatio", 'scalar'); end

if ~isnan(csvLow)
    if abs(userInputs.LowRangeRatio - csvLow) > 0.001
        userInputs.LowRangeRatio = csvLow;
    end
end

% 5. Idle RPM
csvIdle = extractSingleParam(T, "MOT_nIdle", 'scalar');
if isnan(csvIdle), csvIdle = extractSingleParam(T, "FZGG_IdleSpeed", 'scalar'); end

if ~isnan(csvIdle)
    if abs(userInputs.IdleRPM - csvIdle) > 1
        userInputs.IdleRPM = csvIdle;
    end
end

% 6. Max RPM
csvMax = extractSingleParam(T, "MOT_nMax", 'scalar');
if isnan(csvMax), csvMax = extractSingleParam(T, "FZGG_MaxSpeed", 'scalar'); end

if ~isnan(csvMax)
    if abs(userInputs.MaxRPM - csvMax) > 1
        userInputs.MaxRPM = csvMax;
    end
end

% === CUSTOM HTML CONFIRMATION DIALOG ===
% Build HTML string highlighting changes in RED

strAxle   = fmtParam('Axle Ratio', originalInputs.AxleRatio, userInputs.AxleRatio, '%.4f');
strRadius = fmtParam('Tire Radius', originalInputs.DynamicCircumference, userInputs.DynamicCircumference, '%.1f mm');
strCirc   = fmtParam('Tire Circ', originalInputs.TireCircumference, userInputs.TireCircumference, '%.0f mm');
strLow    = fmtParam('Low Range', originalInputs.LowRangeRatio, userInputs.LowRangeRatio, '%.4f');
strIdle   = fmtParam('Idle RPM', originalInputs.IdleRPM, userInputs.IdleRPM, '%.0f');
strMax    = fmtParam('Max RPM', originalInputs.MaxRPM, userInputs.MaxRPM, '%.0f');

grStr = strjoin(string(userInputs.GearRatios), ', ');

htmlMsg = sprintf(['<font size="4"><b>Verify Calculation Parameters</b></font><br><br>' ...
                   '%s<br>%s<br>%s<br>%s<br>%s<br>%s<br><br>' ...
                   '<b>Gear Ratios:</b> %s<br><br>' ...
                   'Values in <font color="red">RED</font> were updated from the loaded CSV.<br>' ...
                   'Continue with these values?'], ...
                   strAxle, strRadius, strCirc, strLow, strIdle, strMax, grStr);
                   
% Create Modal UIFIGURE with editable override fields
dVerify = uifigure('Name', 'Verify Parameters', 'Position', [100 100 620 720], 'WindowStyle', 'modal', 'Resize', 'on');
movegui(dVerify, 'center');

gVerify = uigridlayout(dVerify, [3, 1]);
gVerify.RowHeight  = {'1x', 230, 44};
gVerify.Padding    = [10 10 10 10];
gVerify.RowSpacing = 8;

% Row 1: summary label
uilabel(gVerify, 'Interpreter', 'html', 'Text', htmlMsg, 'VerticalAlignment', 'top', 'WordWrap', 'on');

% Row 2: editable override panel
ovPanel = uipanel(gVerify, 'Title', '  Edit values below to override before loading', ...
    'BorderType', 'line', 'BackgroundColor', [0.96 1.0 0.96]);
ovGrid  = uigridlayout(ovPanel, [5, 4]);
ovGrid.ColumnWidth  = {110, '1x', 110, '1x'};
ovGrid.RowHeight    = {30, 30, 30, 30, 30};
ovGrid.Padding      = [10 6 10 6];
ovGrid.ColumnSpacing = 10;
ovGrid.RowSpacing   = 5;

uilabel(ovGrid,'Text','Axle Ratio:','HorizontalAlignment','right','FontWeight','bold');
efAxle = uieditfield(ovGrid,'numeric','Value',userInputs.AxleRatio,'Limits',[0.1 20],...
    'BackgroundColor',[1 1 0.88],'Tooltip','Final drive axle ratio');
uilabel(ovGrid,'Text','Tire Circ (mm):','HorizontalAlignment','right','FontWeight','bold');
efTire = uieditfield(ovGrid,'numeric','Value',userInputs.TireCircumference,'Limits',[100 5000],...
    'BackgroundColor',[1 1 0.88],'Tooltip','Static tire circumference in mm');

uilabel(ovGrid,'Text','Tire Radius (mm):','HorizontalAlignment','right','FontWeight','bold');
efRad = uieditfield(ovGrid,'numeric','Value',userInputs.DynamicCircumference,'Limits',[0 5000],...
    'BackgroundColor',[1 1 0.88],'Tooltip','Dynamic tire radius in mm');
uilabel(ovGrid,'Text','Idle RPM:','HorizontalAlignment','right','FontWeight','bold');
efIdle = uieditfield(ovGrid,'numeric','Value',userInputs.IdleRPM,'Limits',[0 3000],...
    'BackgroundColor',[1 1 0.88],'Tooltip','Engine idle RPM');

uilabel(ovGrid,'Text','Max RPM:','HorizontalAlignment','right','FontWeight','bold');
efMaxR = uieditfield(ovGrid,'numeric','Value',userInputs.MaxRPM,'Limits',[0 20000],...
    'BackgroundColor',[1 1 0.88],'Tooltip','Engine max RPM');
uilabel(ovGrid,'Text','4Lo Ratio:','HorizontalAlignment','right','FontWeight','bold');
efLoRat = uieditfield(ovGrid,'numeric','Value',userInputs.LowRangeRatio,'Limits',[0 10],...
    'BackgroundColor',[1 1 0.88],'Tooltip','Low-range transfer case ratio');

uilabel(ovGrid,'Text','Dyn Circ (mm):','HorizontalAlignment','right','FontWeight','bold');
uieditfield(ovGrid,'numeric','Value',userInputs.TireCircumference,'Limits',[0 5000],...
    'Editable','off','BackgroundColor',[0.93 0.93 0.93], ...
    'Tooltip','Derived dynamic circumference in mm (display only)');
% Gear ratios — display only (editing done in promptGearData)
uilabel(ovGrid,'Text','Gear Ratios:','HorizontalAlignment','right','FontColor',[0.3 0.3 0.3]);
uilabel(ovGrid,'Text',strjoin(string(round(userInputs.GearRatios,3)),', '),...
    'FontColor',[0.3 0.3 0.3],'FontAngle','italic');

% Row 3: buttons — fixed height, always visible
btnGrid = uigridlayout(gVerify, [1, 2]);
btnGrid.Layout.Row    = 3;
btnGrid.ColumnWidth   = {'1x', '1x'};
btnGrid.Padding       = [0 0 0 0];
btnGrid.ColumnSpacing = 12;
btnCont   = uibutton(btnGrid, 'Text', '✔  Continue', 'FontWeight', 'bold', 'FontSize', 13, ...
    'BackgroundColor', [0.4 0.85 0.4], ...
    'Tooltip', 'Apply overrides and load this CSV');
btnCancel = uibutton(btnGrid, 'Text', '✖  Cancel', 'FontSize', 13, ...
    'BackgroundColor', [1 0.75 0.75], ...
    'ButtonPushedFcn', @(~,~) delete(dVerify));

dVerify.UserData = 'Cancel';
btnCont.ButtonPushedFcn = @(src,e) setSelection(dVerify, 'Continue');

uiwait(dVerify);

if ~isvalid(dVerify), return; end
selection = dVerify.UserData;

% Apply user overrides before closing
if strcmp(selection, 'Continue')
    userInputs.AxleRatio            = efAxle.Value;
    userInputs.TireCircumference    = efTire.Value;
    userInputs.DynamicCircumference = efRad.Value;
    userInputs.IdleRPM              = efIdle.Value;
    userInputs.MaxRPM               = efMaxR.Value;
    userInputs.LowRangeRatio        = efLoRat.Value;
end
delete(dVerify);

if strcmp(selection, 'Cancel')
    return; 
end

%% === EXTRACT DATA BLOCKS (Using Unshifted Var2) ===
statTabulData = extractNumericBlock(T, "STAT_TABUL");
if isempty(statTabulData), statTabulData = zeros(14, 16); end

% WT_ZUSTAND
wtZustandData = []; wtZustandInfo = struct('dataRow', 0, 'idRow', 0);
wtIdx = find(contains(T.Var2, "WT_ZUSTAND", 'IgnoreCase', true), 1);
if ~isempty(wtIdx)
    z_vals = []; x_vals = [];
    for r = wtIdx+1 : min(wtIdx+15, height(T))
        rowRaw = string(table2cell(T(r, 3:end))); nums = str2double(rowRaw); nums = nums(~isnan(nums));
        if length(nums) > 2, z_vals = nums; wtZustandInfo.dataRow = r; break; end
    end
    for r = wtIdx+1 : min(wtIdx+30, height(T))
        rowLabel = strjoin(string(table2cell(T(r, 1:3))), " ");
        if contains(rowLabel, "X_AXIS_PTS", 'IgnoreCase', true)
            rowRaw = string(table2cell(T(r, 3:end))); nums = str2double(rowRaw); x_vals = nums(~isnan(nums));
            wtZustandInfo.idRow = r; break;
        end
    end
    if ~isempty(x_vals) && ~isempty(z_vals), len = min(length(x_vals), length(z_vals)); wtZustandData = [x_vals(1:len); z_vals(1:len)]; end
end

% WT_KWK_ZTAB
[kwkData, kwkRowStart] = extractNumericBlockWithLoc(T, "WT_KWK_ZTAB");
kwkInfo = struct('rowStart', kwkRowStart);
% Guarantee exactly 120 rows (KWK states 0-119).
% The CSV may have fewer rows due to trailing zeros being omitted or a
% blank separator line cutting the scan early. Pad with zeros if needed.
KWK_TARGET_ROWS = 120;
if ~isempty(kwkData)
    nCols = size(kwkData, 2);
    if nCols < 1, nCols = 8; end          % ensure at least 8 curve-ID columns
    if size(kwkData, 1) < KWK_TARGET_ROWS
        kwkData(end+1 : KWK_TARGET_ROWS, 1:nCols) = 0;
    end
else
    % No KWK found at all — create a zero matrix so the table isn't empty
    kwkData = zeros(KWK_TARGET_ROWS, 8);
end

% WT_NWK_SK*
nwkMaps = struct('name', {}, 'headers', {}, 'yAxis', {}, 'data', {}, 'rowStart', {}, 'colStart', {});
nwkIndices = find(contains(T.Var2, "WT_NWK_SK", 'IgnoreCase', true));

for i = 1:length(nwkIndices)
    rIdx = nwkIndices(i); mapName = char(T.Var2(rIdx));
    explicitYAxis = []; headerRowIdx = 0; scanStart = rIdx; scanEnd = min(rIdx + 50, height(T));

    for r = scanStart:scanEnd
        rowLabel = string(T{r, 1});

        % 1. Check for Y_AXIS_PTS
        if contains(rowLabel, "Y_AXIS_PTS", 'IgnoreCase', true)
            rawCells = T{r, 3:end};
            if iscell(rawCells)
                 yVals = cellfun(@(x) safeToNum(x), rawCells);
            else
                 yVals = safeToNum(rawCells);
            end
            validMask = yVals ~= 0 & ~isnan(yVals);
            explicitYAxis = yVals(validMask);
            if size(explicitYAxis, 1) < size(explicitYAxis, 2), explicitYAxis = explicitYAxis'; end

            break; % Stop scanning once found
        end

        if headerRowIdx == 0
            rowRawStr = string(table2cell(T(r, :)));
            if any(contains(rowRawStr, ["_RO","_OR","_RC","_COC"], 'IgnoreCase', true)), headerRowIdx = r; end
        end
    end

    rStart = 0;
    for r = rIdx+1 : scanEnd
        rowTxt = strjoin(string(table2cell(T(r, 1:min(3,end)))), " ");
        if contains(rowTxt, ["Y_AXIS_PTS","X_AXIS_PTS","MAP",":%:"], 'IgnoreCase', true), continue; end
        if r == headerRowIdx, continue; end
        nums = str2double(string(table2cell(T(r, 3:end)))); if sum(~isnan(nums)) > 2, rStart = r; break; end
    end

    if rStart > 0
        rEnd = rStart; for r = rStart:min(rStart+100, height(T)), nums = str2double(string(table2cell(T(r, 3:end)))); if sum(~isnan(nums)) < 2, break; end, rEnd = r; end
        rawBlock = str2double(string(table2cell(T(rStart:rEnd, 3:end))));

        if ~isempty(rawBlock)
            finalYAxis = []; finalData = []; finalHeaders = {};
            if ~isempty(explicitYAxis)
                finalYAxis = explicitYAxis; finalData = rawBlock;
            else
                finalYAxis = rawBlock(:, 1); rawBlock(:, 1) = NaN; finalData = rawBlock;
            end
            validColsMask = any(~isnan(finalData), 1);
            if any(validColsMask)
                finalData = finalData(:, validColsMask);
                if headerRowIdx > 0
                    rawHeaderRow = string(table2cell(T(headerRowIdx, 3:end))); len = min(length(rawHeaderRow), length(validColsMask));
                    finalHeaders = rawHeaderRow(1:len); finalHeaders = finalHeaders(validColsMask(1:len));
                end
            end
            if ~isempty(finalYAxis) && ~isempty(finalData)
                if size(finalData, 1) ~= length(finalYAxis) && size(finalData, 2) == length(finalYAxis), finalData = finalData'; end
                nwkMaps(end+1) = struct('name', mapName, 'headers', {finalHeaders}, 'yAxis', finalYAxis, 'data', finalData, 'rowStart', rStart, 'colStart', 3);
            end
        end
    end
end

%% === EXTRACT UK LIST ===
ukTableData = { ...
%   UK-Name,                                    Abbrev,   ID, SKLID,                   UL,      USP,     DSP
'Driving according to driver type',          'UKTYP',  1,  'UKTYP_SklId',           'YES',   '',      '';
'FastOff',                                   'UKFO',   3,  'UKFO_SklId',            '',      'YES',   '';
'Sequential Upshift',                        'UKSUS',  4,  'UKSUS_SklId',           '',      'YES',   '';
'Curve',                                     'UKKE',   6,  'UKKE_SklId',            'YES',   'YES',   'YES';
'Program change function',                   'UKPRW',  7,  'UKPRW_SklId',           '',      'YES',   'YES';
'Transmission control panel',                'UKGBF',  8,  'UKGBF_SklId',           'YES',   'YES',   '';
'Downhill',                                  'UKBA',   9,  'UKBA_SklId',            'YES',   'YES',   '';
'Winter (slip)',                              'UKWE',   10, 'UKWE_SklId',            'YES',   'YES',   '';
'Tow/Haul',                                  'UKTOW',  11, 'UKTOW_SklId',           'YES',   '',      '';
'Spontaneous deceleration vehicle',          'UKSVF',  12, 'UKSVF_SklId',           'YES',   '(YES)', '';
'ASC Mode',                                  'UKASC',  13, 'UKASC_SklId',           'YES',   '',      '';
'CDS Mode',                                  'UKCDS',  14, 'UKCDS_SklId',           '',      'YES',   'YES';
'Tip Mode',                                  'UKTIP',  15, 'TIPSKL_SklId',          'YES',   '(YES)', '(YES)';
'Cruise Control',                            'UKFGR',  16, 'UKFGR_SklId',           'YES',   'YES',   'YES';
'Cruise Control',                            'UKFGR',  16, 'UKFGR_SKLID_ACC',       'YES',   'YES',   'YES';
'Cruise Control',                            'UKFGR',  16, 'UKFGR_SKLID_Vdiff',     'YES',   'YES',   'YES';
'Downshift Delay',                           'UKDSD',  19, 'UKDSD_SklId',           '',      '',      'YES';
'Spontaneous downshift',                     'UKSRS',  20, 'UKSRS_SKLID',           'YES',   '',      '';
'Spontaneous downshift',                     'UKSRS',  20, 'UKSRS_SKLID_Lvl1',      'YES',   '',      '';
'Spontaneous downshift',                     'UKSRS',  20, 'UKSRS_SKLID_Lvl2',      'YES',   '',      '';
'Eco driving',                               'UKECO',  21, 'UKECO_SklId',           'YES',   '',      '';
'Selector lever position',                   'UKRPO',  22, 'UKRPO_SklId',           'YES',   '',      '';
'Extended downshift prevention /UKSW',       'UKSWG',  24, 'UKSWG_SKLID',           'YES',   '',      'YES';
'Low range',                                 'UKLOW',  27, 'UKLOW_SklId',           'YES',   '',      '';
'Gras/Gravel/Snow Mode',                     'UKGGS',  28, 'UKGGS_SklId',           'YES',   '',      '';
'Gras/Gravel/Snow Mode',                     'UKGGS',  28, 'UKGGS_SklIdLow',        'YES',   '',      '';
'Sand',                                      'UKSND',  30, 'UKSND_SklId',           'YES',   '',      '';
'Sand',                                      'UKSND',  30, 'UKSND_SklIdLow',        'YES',   '',      '';
'Cross Country or Mud/Ruts',                 'UKXC',   31, 'UKXC_SklId',            'YES',   '',      '';
'Cross Country or Mud/Ruts',                 'UKXC',   31, 'UKXC_SklIdLow',         'YES',   '',      '';
'Rock Crawl',                                'UKRCK',  32, 'UKRCK_SklId',           'YES',   '',      '';
'Free Wheeling',                             'UKFW',   34, 'UKFW_SklId',            'YES',   'YES',   'YES';
'End Of Line - Factory mode',                'UKEOL',  37, 'UKEOL_SklId',           'YES',   '',      '';
'Double downshift',                          'UKDRS',  38, 'UKDRS_SklId',           'YES',   'YES',   '';
'Valet Mode',                                'UKVAL',  39, 'UKVAL_SklId',           'YES',   '',      '';
'Cruise Control',                            'UKCC',   44, 'UKCC_SklIdACC',         'YES',   'YES',   'YES';
'Cruise Control',                            'UKCC',   44, 'UKCC_SklIdCC',          'YES',   'YES',   'YES';
'Cruise Control',                            'UKCC',   44, 'UKCC_SklIdRRCC',        'YES',   'YES',   'YES';
'Cruise Control',                            'UKCC',   44, 'UKCC_SklIdVdifACC',     'YES',   'YES',   'YES';
'Cruise Control',                            'UKCC',   44, 'UKCC_SklIdVdifCC',      'YES',   'YES',   'YES';
'Cruise Control',                            'UKCC',   44, 'UKCC_SklIdVdifRRCC',    'YES',   'YES',   'YES';
'Cruise Control',                            'UKCC',   44, 'UKCC_SklIdVDifACC',     'YES',   'YES',   'YES';
'Cruise Control',                            'UKCC',   44, 'UKCC_SklIdVDifCC',      'YES',   'YES',   'YES';
'Cruise Control',                            'UKCC',   44, 'UKCC_SklIdVDifRRCC',    'YES',   'YES',   'YES';
'Upshift interrupt',                         'UKUSI',  45, 'UKUSI_SklId',           'YES',   '(YES)', '';
'Torque Converter Clutch',                   'UKTCC',  47, 'UKTCC_SklId',           '',      '',      'YES';
'Engine Speed Limitation',                   'UKZW',   48, 'UKZW_SklId',            'YES',   '(YES)', '(YES)';
'Overdrive',                                 'UKOD',   49, 'UKOD_SklId',            '',      'YES',   '';
'Electronic Valve Actuation',                'UKEVA',  50, 'UKEVA_SklId',           '',      'YES',   'YES';
'Hybrid Flow Manager',                       'UKHYB',  51, 'UKHYB_SKLID',           '',      'YES',   'YES';
'Reverse Driving direction',                 'UKREV',  59, 'UKREV_SklId',           '',      'YES',   '';
'Driving in position N',                     'UKN',    60, 'UKN_SklIdRollout',      'YES',   '',      '';
'Stop And Go',                               'UKSNG',  61, 'UKSNG_SklId',           '',      '',      'YES';
'Belt Starter Generator',                    'UKBSG',  62, 'UKBSG_SklId',           'YES',   '',      '';
'Launch Gear',                               'UKLG',   63, 'UKLG_SklId',            'YES',   '',      'YES';
'Adaption of Clutch',                        'UKADA',  69, 'UKADA_SklId',           '',      'YES',   '';
};
ukTableData(:, 8) = {'Not Found'};  % col 8 = Map Numbers (5=UL,6=USP,7=DSP are static)

sCol2 = strtrim(string(T.Var2)); sCol1 = strtrim(string(T.Var1));
for i = 1:size(ukTableData, 1)
    varName = ukTableData{i, 4}; rIdx = find(strcmpi(sCol2, varName), 1); if isempty(rIdx), rIdx = find(strcmpi(sCol1, varName), 1); end
    if ~isempty(rIdx)
        foundVals = []; currR = rIdx + 1; maxLookAhead = 300; safetyCtr = 0;
        while currR <= height(T) && safetyCtr < maxLookAhead
            raw1 = T{currR, 1}; if iscell(raw1), raw1 = raw1{1}; end; txt1 = strtrim(string(raw1));
            txt2 = ""; if width(T) >= 2, raw2 = T{currR, 2}; if iscell(raw2), raw2 = raw2{1}; end; txt2 = strtrim(string(raw2)); end
            isNewVar = false; if strlength(txt2) > 2 && ~startsWith(txt2, ":") && isnan(str2double(txt2)), if ~any(strcmpi(txt2, {'MAP','CURVE','Value','Label','Unit'})), isNewVar = true; end; end
            if isNewVar && safetyCtr > 0, break; end
            rowDat = string(table2cell(T(currR, :))); rowNums = str2double(rowDat); validNums = rowNums(~isnan(rowNums));
            if ~isempty(validNums), foundVals = [foundVals; validNums(:)]; end
            currR = currR + 1; safetyCtr = safetyCtr + 1;
        end
        if ~isempty(foundVals), ukTableData{i, 8} = char(strjoin(string(unique(foundVals)'), ', ')); else, ukTableData{i, 8} = 'Empty'; end
    end
end
%% === SHIFT COLUMNS (Must happen AFTER block extraction) ===
if width(T) >= 2, T.Var2 = vertcat("", T.Var2(1:end-1)); end

%% === EXTRACT MAIN SHIFT MAPS ===
allMaps = {}; mapNames = {}; mapCount = 0; row = 1;
% Pre-cache Var1/Var2 as string arrays for fast comparison in the loop
v1 = strtrim(string(T.Var1)); v2 = string(T.Var2);
while row <= height(T)
    label = v1(row); mapName = v2(row);
    if label == "MAP" && contains(mapName, "SKL_GKF_")
        mapCount = mapCount + 1; mapNames{mapCount} = mapName;
        rpmStart = row + 2; rpmEnd = rpmStart + 11;
        % str2double on raw cell block — faster than cellfun+safeToNum
        rpmMatrix = str2double(string(T{rpmStart:rpmEnd, 3:16}));
        rpmMatrix(isnan(rpmMatrix)) = 0;
        Z_up = rpmMatrix(:, 1:7); Z_down = rpmMatrix(:, 8:14);
        pedalRow = rpmEnd + 7;
        pedal = str2double(string(T{pedalRow, 3:14}));
        pedal(isnan(pedal)) = 0;
        allMaps{mapCount} = struct('name', mapName, ...
            'Z_up',   [Z_up(1,:);   Z_up;   Z_up(end,:)],   ...
            'Z_down', [Z_down(1,:); Z_down; Z_down(end,:)], ...
            'pedal',  [0, pedal, 110], 'modified', false);
        row = pedalRow + 2; continue;
    end
    row = row + 1;
end
mapNames = string(mapNames);
tokens = regexp(mapNames, '^SKL_GKF_(\d+)$', 'tokens');
validIdx = find(~cellfun(@isempty, tokens));
if ~isempty(validIdx)
    mapNums = cellfun(@(x) str2double(x{1}), tokens(validIdx));
    [~, sortOrder] = sort(mapNums);
    sortedIdx = validIdx(sortOrder);
    % Keep ALL maps — SKL_GKF ones sorted numerically, any others appended at end
    otherIdx = setdiff(1:length(mapNames), validIdx);
    finalIdx = [sortedIdx, otherIdx];
    mapNames = mapNames(finalIdx); allMaps = allMaps(finalIdx);
end

%% === UI Setup (Refactored with uigridlayout) ===

% Construct appData from CSV variables
appData = struct();
appData.allMaps = allMaps;
appData.ukData = ukTableData;
appData.statTabul = statTabulData;
appData.wtZustand = wtZustandData;
appData.wtZustandInfo = wtZustandInfo;
appData.kwkData = kwkData;
appData.kwkInfo = kwkInfo;
appData.nwkMaps = nwkMaps;
appData.tccHistory = struct('curves', {{}}, 'zustand', {{}}, 'kwk', {{}});
appData.tccShadowData = struct('curves', [], 'zustand', [], 'kwk', []);

defaultStatRows = {'Auto'; 'P R N'; 'Eco'; 'Not defined'; 'Sports'; 'Snow'; 'Tow'; 'Valet'; '4 Lo'; 'Track'; 'Rock'; 'Sand / Off road'; 'Calibrator Choice'; 'Calibrator Choice'};
nDataRows = size(statTabulData, 1);
nNameRows = length(defaultStatRows);
if nDataRows > nNameRows, defaultStatRows = [defaultStatRows; repmat({''}, nDataRows - nNameRows, 1)];
elseif nDataRows < nNameRows, defaultStatRows = defaultStatRows(1:nDataRows); end
appData.statRowNames = defaultStatRows;

appData.T = T;
appData.activeAbbrevs = computeActiveAbbrevs(T);
appData.allMapNames = string(cellfun(@(m) m.name, allMaps, 'UniformOutput', false))';
appData.ukFig = gobjects(0);
appData.tccFig = gobjects(0);
appData.tableFig = gobjects(0); appData.tableHandle = gobjects(0); appData.infoLabel = gobjects(0);
appData.multiMapFig  = gobjects(0); appData.gbfssactFig = gobjects(0);
appData.genericFig   = gobjects(0); appData.interpFig   = gobjects(0);
appData.analysisFig  = gobjects(0);
appData.userInputs = userInputs;
appData.workingCopy = []; appData.editIndex = -1; appData.history = {};
appData.lastSelectedIndices = [];
appData.currentMapName = '';
appData.hysteresis = struct('Speed', 50, 'Pedal', 10, 'MPH', 2);
appData.sessionLog = {};
appData.multiMapDirty = false; appData.multiHistory = {};
appData.sourceFilename = filename;
end % loadFromCSV

function success = saveProject(fig)
    success = false;
    appData = fig.UserData;
    tableEditorLower(fig);

    % ── Step 1: Warn user about open windows ─────────────────────────────────
    openWins = {};
    if isfield(appData,'ukFig')       && ~isempty(appData.ukFig)       && isvalid(appData.ukFig),       openWins{end+1} = '  - UK & STAT Table'; end
    if isfield(appData,'tccFig')      && ~isempty(appData.tccFig)      && isvalid(appData.tccFig),      openWins{end+1} = '  - TCC Curves'; end
    if isfield(appData,'tableFig')    && ~isempty(appData.tableFig)    && isvalid(appData.tableFig),    openWins{end+1} = '  - Table Editor'; end
    if isfield(appData,'multiMapFig') && hasValidHandle(appData, 'multiMapFig'), openWins{end+1} = '  - Multi-Map Editor'; end
    if isfield(appData,'gbfssactFig') && hasValidHandle(appData, 'gbfssactFig'), openWins{end+1} = '  - GBF SSact'; end
    if isfield(appData,'interpFig')   && ~isempty(appData.interpFig)   && isvalid(appData.interpFig),   openWins{end+1} = '  - Interpolation Tables'; end

    if ~isempty(openWins)
        msg = sprintf('The following windows are open:\n\n%s\n\nPlease save any unsaved changes in those windows first.\nAll open windows will be closed before saving.\n\nContinue?', ...
            strjoin(openWins, newline));
        choice = uiconfirm(fig, msg, 'Save Project', ...
            'Options', {'Continue & Close Windows', 'Cancel'}, ...
            'DefaultOption', 1, 'CancelOption', 2, 'Icon', 'warning');
        if strcmp(choice, 'Cancel'), tableEditorRestore(fig); return; end
    end

    % ── Step 2: Close all popup windows cleanly before saving ────────────────
    popupFields = {'ukFig','tccFig','tableFig','multiMapFig','gbfssactFig','interpFig','genericFig','analysisFig'};
    for pf = popupFields
        f = pf{1};
        if isfield(appData, f) && ~isempty(appData.(f)) && isvalid(appData.(f))
            try, delete(appData.(f)); catch, end
        end
        if isfield(appData, f), appData.(f) = gobjects(0); end
    end
    fig.UserData = appData;

    % ── Step 3: Pick save location ────────────────────────────────────────────
    [file, path] = uiputfile('*.mat', 'Save Project As');
    if isequal(file, 0), tableEditorRestore(fig); return; end

    % Prepare data to save (strip handles)
    appData = fig.UserData;
    saveStruct.appData = appData;
    
    % Remove transient handles
    if isfield(saveStruct.appData, 'handles'), saveStruct.appData = rmfield(saveStruct.appData, 'handles'); end
    if isfield(saveStruct.appData, 'ukFig'), saveStruct.appData.ukFig = gobjects(0); end
    if isfield(saveStruct.appData, 'tccFig'), saveStruct.appData.tccFig = gobjects(0); end
    if isfield(saveStruct.appData, 'tableFig'), saveStruct.appData.tableFig = gobjects(0); end
    if isfield(saveStruct.appData, 'tableHandle'), saveStruct.appData.tableHandle = gobjects(0); end
    if isfield(saveStruct.appData, 'infoLabel'), saveStruct.appData.infoLabel = gobjects(0); end
    if isfield(saveStruct.appData, 'contextLabel'), saveStruct.appData.contextLabel = gobjects(0); end
    if isfield(saveStruct.appData, 'editorTabGroup'), saveStruct.appData = rmfield(saveStruct.appData, 'editorTabGroup'); end
    if isfield(saveStruct.appData, 'editorTables'), saveStruct.appData = rmfield(saveStruct.appData, 'editorTables'); end
    if isfield(saveStruct.appData, 'tableAx'),       saveStruct.appData = rmfield(saveStruct.appData, 'tableAx'); end
    % Clear transient figure handles and runtime state not needed in .mat
    handleFields = {'multiMapFig','gbfssactFig','genericFig','interpFig','analysisFig'};
    for hf = handleFields
        if isfield(saveStruct.appData, hf{1}), saveStruct.appData.(hf{1}) = gobjects(0); end
    end
    % Clear large runtime caches — they are regenerated on load
    if isfield(saveStruct.appData, 'multiHistory'),  saveStruct.appData.multiHistory  = {}; end
    if isfield(saveStruct.appData, 'multiMapDirty'), saveStruct.appData.multiMapDirty = false; end
    % Strip session state — sessions should not persist across saves/loads
    if isfield(saveStruct.appData, 'holdSession'), saveStruct.appData = rmfield(saveStruct.appData, 'holdSession'); end
    if isfield(saveStruct.appData, 'dragGhost'),   saveStruct.appData = rmfield(saveStruct.appData, 'dragGhost'); end
    if isfield(saveStruct.appData, 'swapping'),    saveStruct.appData = rmfield(saveStruct.appData, 'swapping');   end
    if isfield(saveStruct.appData, 'refVehicle'),  saveStruct.appData = rmfield(saveStruct.appData, 'refVehicle');  end
    if isfield(saveStruct.appData, 'refItemsAll'), saveStruct.appData = rmfield(saveStruct.appData, 'refItemsAll'); end
    if isfield(saveStruct.appData, 'bulkUpdate'),  saveStruct.appData = rmfield(saveStruct.appData, 'bulkUpdate');  end
    if isfield(saveStruct.appData, 'diagLog'),     saveStruct.appData = rmfield(saveStruct.appData, 'diagLog');     end
    if isfield(saveStruct.appData, 'pendingCSVPath'), saveStruct.appData = rmfield(saveStruct.appData, 'pendingCSVPath'); end
    if isfield(saveStruct.appData, 'isRefMode'), saveStruct.appData = rmfield(saveStruct.appData, 'isRefMode'); end
    % dynoExcelFile is a plain string path — safe to keep in saved project
    
    try
        save(fullfile(path, file), '-struct', 'saveStruct');
        logAction(fig, 'Project Saved', fullfile(path, file));
        try, recentFilesAdd(fullfile(path,file)); recentFilesMenuRefresh(fig); catch; end
        try, updateStatusBar(fig, sprintf('Saved: %s', file), [0 0.5 0]); catch; end
        uialert(fig, 'Project Saved Successfully.', 'Success');
        success = true;
    catch ME
        uialert(fig, sprintf('Error saving:\n%s', ME.message), 'Error');
    end
    tableEditorRestore(fig);
end

function loadProject(fig)
    tableEditorLower(fig);
    % Offer two options: load a saved .mat project OR start fresh from a CSV file.
    loadChoice = uiconfirm(fig, ...
        'How would you like to load a project?', 'Load Project', ...
        'Options',       {'Load from .mat File', 'New from CSV', 'Cancel'}, ...
        'DefaultOption', 'Load from .mat File', ...
        'CancelOption',  'Cancel', ...
        'Icon',          'question');

    if strcmp(loadChoice, 'Cancel'), return; end

    % ── Ask to save current work before replacing it ─────────────────────────
    % Warn about active session first
    curAD = fig.UserData;
    if isfield(curAD,'holdSession') && isstruct(curAD.holdSession)
        hasEdits5 = false;
        for slk5 = {'A','B','C'}
            sl5 = curAD.holdSession.slots.(slk5{1});
            if ~isempty(sl5) && isfield(sl5,'modified') && sl5.modified, hasEdits5=true; break; end
        end
        if hasEdits5
            warn5 = uiconfirm(fig,'A Hold & Save Session has unsaved edits. Load anyway?', ...
                'Active Session','Options',{'Load Anyway','Cancel'},'DefaultOption',2,'CancelOption',2,'Icon','warning');
            if strcmp(warn5,'Cancel'), return; end
        end
    end

    selection = uiconfirm(fig, ...
        'Save the current project before loading a new one?', 'Save Current?', ...
        'Options', {'Yes', 'No', 'Cancel'}, 'DefaultOption', 'Yes', 'CancelOption', 'Cancel', ...
        'Icon', 'question');
    if strcmp(selection, 'Cancel'), return; end
    if strcmp(selection, 'Yes')
        saved = saveProject(fig);
        if ~saved, return; end
    end

    % ── Close all sub-windows before replacing appData ────────────────────────
    oldAppData = fig.UserData;
    subWins = {'ukFig','tccFig','tableFig','multiMapFig','gbfssactFig','interpFig','genericFig'};
    for sw = subWins
        f2 = sw{1};
        if isfield(oldAppData,f2) && ~isempty(oldAppData.(f2)) && isvalid(oldAppData.(f2))
            delete(oldAppData.(f2));
        end
    end

    if strcmp(loadChoice, 'Load from .mat File')
        % ── Load from saved .mat ──────────────────────────────────────────────
        [f, p] = uigetfile('*.mat', 'Select Project File');
        if isequal(f, 0) || ~isvalid(fig), return; end
        try
            loaded = load(fullfile(p, f));
            if ~isfield(loaded, 'appData')
                uialert(fig, 'Invalid project file — appData not found.', 'Error'); return;
            end
            newAppData = loaded.appData;
            % Restore transient handles
            newAppData.handles      = oldAppData.handles;
            newAppData.contextLabel = oldAppData.contextLabel;
            newAppData.ukFig        = gobjects(0);
            newAppData.tccFig       = gobjects(0);
            newAppData.tableFig     = gobjects(0);
            newAppData.tableHandle  = gobjects(0);
            newAppData.infoLabel    = gobjects(0);
            newAppData.multiMapFig  = gobjects(0);
            newAppData.sourceFilename = f;
            % Rebuild allMapNames cache
            newAppData.allMapNames = string(cellfun(@(m) m.name, newAppData.allMaps, 'UniformOutput', false))';
            applyLoadedProject(fig, newAppData);
            try, recentFilesAdd(fullfile(p,f)); recentFilesMenuRefresh(fig); catch; end
            try, refreshStatusBar(fig); catch; end
            uialert(fig, sprintf('Project "%s" loaded successfully.', f), 'Success');
        catch ME
            if isvalid(fig)
                uialert(fig, sprintf('Error loading project:\n%s', ME.message), 'Error');
            end
        end

    else
        % ── New from CSV ──────────────────────────────────────────────────────
        newAppData = loadFromCSV(fig);
        if isempty(newAppData), return; end   % user cancelled
        % Restore transient UI handles from current session
        newAppData.handles      = oldAppData.handles;
        newAppData.contextLabel = oldAppData.contextLabel;
        applyLoadedProject(fig, newAppData);
        if isfield(newAppData,'sourceFilename')
            try, recentFilesAdd(newAppData.sourceFilename); recentFilesMenuRefresh(fig); catch; end
        end
        try, refreshStatusBar(fig); catch; end
        uialert(fig, 'New project loaded from CSV successfully.', 'Success');
    end
    tableEditorRestore(fig);
end

function applyLoadedProject(fig, newAppData)
    % Common finalisation after any project load (mat or CSV or auto-save).
    %
    % CRITICAL: any field that holds a graphics handle, sub-window, or other
    % runtime state must be re-seeded here. Some callers (like auto-save restore)
    % deliberately strip these fields before save — and downstream functions
    % (updatePlot, updateContextPanel, refreshTableStyles) read them without
    % isfield() guards, so missing fields cause "Unrecognized field" crashes.
    % Sub-window / table handles: seed empty (sub-windows reopen on demand)
    subwinFields = {'tableFig','tableHandle','tableAx','infoLabel', ...
                    'ukFig','tccFig','multiMapFig','gbfssactFig','interpFig', ...
                    'genericFig','analysisFig','dragGhost','editorTabGroup','editorTables'};
    for ii = 1:numel(subwinFields)
        if ~isfield(newAppData, subwinFields{ii}) || isempty(newAppData.(subwinFields{ii}))
            newAppData.(subwinFields{ii}) = gobjects(0);
        end
    end
    % contextLabel must come from the LIVE figure (uilabel in the main window).
    % If the loaded struct has a stale handle or none at all, take it from the live appData.
    liveAD = fig.UserData;
    if ~isfield(newAppData,'contextLabel') || isempty(newAppData.contextLabel) ...
            || ~isvalid(newAppData.contextLabel)
        if isfield(liveAD,'contextLabel') && isvalid(liveAD.contextLabel)
            newAppData.contextLabel = liveAD.contextLabel;
        else
            newAppData.contextLabel = gobjects(0);
        end
    end

    % Always reset runtime state that is not safe to carry from a saved file
    newAppData.multiMapDirty = false;
    newAppData.multiHistory  = {};
    if ~isfield(newAppData,'multiMapFig') || isempty(newAppData.multiMapFig)
        newAppData.multiMapFig = gobjects(0);
    end
    if ~isfield(newAppData,'gbfssactFig') || isempty(newAppData.gbfssactFig)
        newAppData.gbfssactFig = gobjects(0);
    end
    if ~isfield(newAppData,'interpFig') || isempty(newAppData.interpFig)
        newAppData.interpFig = gobjects(0);
    end
    if ~isfield(newAppData,'genericFig') || isempty(newAppData.genericFig)
        newAppData.genericFig = gobjects(0);
    end
    if ~isfield(newAppData,'analysisFig') || isempty(newAppData.analysisFig)
        newAppData.analysisFig = gobjects(0);
    end
    % Guard new fields not present in old project files
    if ~isfield(newAppData,'sessionLog'),    newAppData.sessionLog = {};    end
    if ~isfield(newAppData,'history'),       newAppData.history    = {};    end
    if ~isfield(newAppData,'hysteresis'),    newAppData.hysteresis = struct('Speed',50,'Pedal',10,'MPH',2); end
    if ~isfield(newAppData,'editIndex'),     newAppData.editIndex  = -1;    end
    if ~isfield(newAppData,'workingCopy'),   newAppData.workingCopy = [];   end
    if ~isfield(newAppData,'lastSelectedIndices'), newAppData.lastSelectedIndices = []; end
    % Remove any [REF] tagged maps from a previously saved session
    if isfield(newAppData,'allMaps') && ~isempty(newAppData.allMaps)
        isRefMap = cellfun(@(m) isfield(m,'isRef') && m.isRef, newAppData.allMaps);
        if any(isRefMap)
            newAppData.allMaps(isRefMap) = [];
            newAppData.allMapNames = string(cellfun(@(m) m.name, newAppData.allMaps, 'UniformOutput', false))';
        end
    end
    % Migrate ukData from old format (< 8 cols) — col 8 = Map Numbers was added later.
    % Without this, accessing ukData{row,8} crashes on projects saved before the column existed.
    if isfield(newAppData,'ukData') && ~isempty(newAppData.ukData) && size(newAppData.ukData,2) < 8
        newAppData.ukData = ukEnsureULUSPDSP(newAppData.ukData);
    end
    % Always clear stale session state on project load
    if isfield(newAppData,'holdSession'), newAppData = rmfield(newAppData,'holdSession'); end
    if isfield(newAppData,'dragGhost'),  newAppData = rmfield(newAppData,'dragGhost'); end
    if isfield(newAppData,'swapping'),   newAppData = rmfield(newAppData,'swapping');   end
    if isfield(newAppData,'refVehicle'),  newAppData = rmfield(newAppData,'refVehicle');  end
    if isfield(newAppData,'isRefMode'),   newAppData = rmfield(newAppData,'isRefMode');   end
    if isfield(newAppData,'refItemsAll'), newAppData = rmfield(newAppData,'refItemsAll'); end
    if isfield(newAppData,'bulkUpdate'),  newAppData = rmfield(newAppData,'bulkUpdate');  end
    if isfield(newAppData,'diagLog'),     newAppData = rmfield(newAppData,'diagLog');     end
    if isfield(newAppData,'pendingCSVPath'), newAppData = rmfield(newAppData,'pendingCSVPath'); end
    % Reset Reference Mode UI
    h = fig.UserData.handles;   % get live handles from figure
    if isfield(h,'cbRefMode') && isvalid(h.cbRefMode), h.cbRefMode.Value = false; end
    if isfield(h,'refLabel')  && isvalid(h.refLabel)
        h.refLabel.Text = ''; h.refLabel.Visible = 'off';
    end
    if isfield(h,'lblMapB') && isvalid(h.lblMapB)
        h.lblMapB.Text = 'Map B:'; h.lblMapB.FontColor = [0 0 0];
    end
    if isfield(h,'dd2') && isvalid(h.dd2)
        h.dd2.BackgroundColor = [1 0.95 0.95];
        h.dd2.Tooltip         = '';
    end
    if isfield(h,'cbEdit')   && isvalid(h.cbEdit),   h.cbEdit.Enable   = 'on'; end
    if isfield(h,'cbAllowY') && isvalid(h.cbAllowY), h.cbAllowY.Enable = 'on'; end
    % Always use the LIVE handles from the figure, not whatever was in the loaded struct.
    % Auto-save strips 'handles' deliberately, and stale handles from .mat would point to
    % deleted UI components from a previous session.
    if isfield(h,'cbHoldSave') && isvalid(h.cbHoldSave), h.cbHoldSave.Value = false; end
    if isfield(h,'btnSaveAll') && isvalid(h.btnSaveAll), h.btnSaveAll.Visible = 'off'; end
    % Unlock all session-locked controls (in case project was saved mid-session)
    setSessionLock(h, false, '', '', '');
    newAppData.handles = h;   % attach the live handles to the new appData
    fig.UserData = newAppData;
    % Re-read h from UserData so dropdown writes below go to the live handle
    h = fig.UserData.handles;
    mapNames = getMapNames(newAppData);
    if isempty(mapNames), mapNames = ["None"]; end
    h.dd1.Items = mapNames;
    h.dd2.Items = mapNames;
    if isfield(h,'dd3') && isvalid(h.dd3), h.dd3.Items = mapNames; end
    if isfield(newAppData,'currentMapName') && ismember(newAppData.currentMapName, mapNames)
        h.dd1.Value = newAppData.currentMapName;
    else
        h.dd1.Value = mapNames(1);
    end
    if ~ismember(h.dd2.Value, mapNames), h.dd2.Value = mapNames(1); end
    if isfield(h,'dd3') && isvalid(h.dd3) && ~ismember(h.dd3.Value, mapNames), h.dd3.Value = mapNames(1); end
    if isfield(newAppData,'sourceFilename')
        h.fileLabel.Text = ['A: ' char(newAppData.sourceFilename)];
    end
    updatePlot(fig);
    updateContextPanel(fig);
    try, updateMapSourceLabels(fig); catch; end
end
function onStatSelect(ukFig, event)
    h = ukFig.UserData; h.statSelection = event.Indices; ukFig.UserData = h;
end
function applyStatMath(ukFig, fig, op)
    h = ukFig.UserData;
    tStat = h.tStat;
    sel = h.statSelection;
    if isempty(sel), uialert(ukFig, 'Select cells first.', 'Error'); return; end

    appData = fig.UserData;
    if ~isfield(appData,'ukHistory'),    appData.ukHistory    = {}; end
    if ~isfield(appData,'statShadowData'), appData.statShadowData = appData.statTabul; end
    appData.ukHistory{end+1} = appData.statShadowData;
    if length(appData.ukHistory) > 20, appData.ukHistory(1) = []; end

    prompt = ""; def = "0";
    switch op
        case 'add', prompt = "Add Value:";
        case 'mult', prompt = "Multiply by:"; def="1";
        case 'div', prompt = "Divide by:"; def="1";
        case 'percent', prompt = "Percent Change:";
    end
    answer = inputdlg(prompt, 'Math', [1 40], {char(def)});
    if isempty(answer), return; end
    val = str2double(answer{1});
    if isnan(val), return; end

    data = tStat.Data;
    statMatrix = appData.statShadowData;

    for i=1:size(sel,1)
        r = sel(i,1); c = sel(i,2);
        if c <= 1, continue; end

        curr = data{r,c};
        if isempty(curr) || isnan(curr), continue; end
        switch op
            case 'add', curr = curr + val;
            case 'mult', curr = curr * val;
            case 'div', if val~=0, curr = curr / val; end
            case 'percent', curr = curr * (1 + val/100);
        end
        data{r,c} = curr;
        statMatrix(r, c-1) = curr;
    end
    tStat.Data = data;
    appData.statShadowData = statMatrix;
    fig.UserData = appData;

    addStyle(tStat, getYellowStyle(), 'cell', sel);
end
function refreshUKStatIfOpen(fig)
% FAST: UK+STAT only. Working file by default; ref data only after swap (isWCRef&&isRefMode).
    try
        appData=fig.UserData;
        if ~isfield(appData,'ukFig')||isempty(appData.ukFig)||~isvalid(appData.ukFig),return;end
        ukFig=appData.ukFig; h=ukFig.UserData;
        isWCRef=~isempty(appData.workingCopy)&&isfield(appData.workingCopy,'isRef')&&appData.workingCopy.isRef;
        isRefMode=isfield(appData,'isRefMode')&&appData.isRefMode&&isfield(appData,'refVehicle');
        useRef=isWCRef&&isRefMode;
        if useRef
            srcUK=appData.refVehicle.ukData; srcStat=appData.refVehicle.statTabul;
            refDesc=char(appData.refVehicle.meta.description);
        else
            srcUK=appData.ukData; srcStat=appData.statTabul; refDesc='';
        end
        if isfield(h,'fullDisplayData')
            h.fullDisplayData=buildUKDisplayData(fig,srcUK,srcStat); ukFig.UserData=h;
        end
        if isfield(h,'tStat')&&isvalid(h.tStat)&&~isempty(srcStat)
            if useRef&&isfield(appData.refVehicle,'statRowNames'), rv=appData.refVehicle.statRowNames;
            else, rv=appData.statRowNames; end
            nR=size(srcStat,1);
            if length(rv)<nR,rv=[rv;repmat({''},nR-length(rv),1)];elseif length(rv)>nR,rv=rv(1:nR);end
            h.tStat.Data=[rv,num2cell(srcStat)];
        end
        if isfield(h,'ukFileLabel')&&isvalid(h.ukFileLabel)
            if useRef
                h.ukFileLabel.Text=['[REF] ' refDesc]; h.ukFileLabel.FontColor=[0.0 0.35 0.65];
            elseif isRefMode&&isfield(appData,'refVehicle')
                h.ukFileLabel.Text=[char(appData.sourceFilename) '  |  Swap -> [REF] ' char(appData.refVehicle.meta.description)];
                h.ukFileLabel.FontColor=[0.3 0.3 0.3];
            else
                h.ukFileLabel.Text=char(appData.sourceFilename); h.ukFileLabel.FontColor=[0.3 0.3 0.3];
            end
        end
        ukFig.UserData=h;
        updateUKTableFilters(ukFig,fig);
    catch; end
end


function refreshAllUKTabsIfOpen(fig)
% FULL: all 6 tabs. Called from swapMaps and onRefModeToggle only.
% Uses ref data only when isWCRef&&isRefMode (Map A holds a [REF] map after swap).
    try
        appData=fig.UserData;
        if ~isfield(appData,'ukFig')||isempty(appData.ukFig)||~isvalid(appData.ukFig),return;end
        ukFig=appData.ukFig; h=ukFig.UserData;
        isWCRef=~isempty(appData.workingCopy)&&isfield(appData.workingCopy,'isRef')&&appData.workingCopy.isRef;
        isRefMode=isfield(appData,'isRefMode')&&appData.isRefMode&&isfield(appData,'refVehicle');
        useRef=isWCRef&&isRefMode;
        if useRef
            srcUK=appData.refVehicle.ukData; srcStat=appData.refVehicle.statTabul;
            srcT=[]; refDesc=char(appData.refVehicle.meta.description);
        else
            srcUK=appData.ukData; srcStat=appData.statTabul; srcT=appData.T; refDesc='';
        end
        if isfield(h,'fullDisplayData'), h.fullDisplayData=buildUKDisplayData(fig,srcUK,srcStat); ukFig.UserData=h; end
        if isfield(h,'tStat')&&isvalid(h.tStat)&&~isempty(srcStat)
            if useRef&&isfield(appData.refVehicle,'statRowNames'), rv=appData.refVehicle.statRowNames;
            else, rv=appData.statRowNames; end
            nR=size(srcStat,1);
            if length(rv)<nR,rv=[rv;repmat({''},nR-length(rv),1)];elseif length(rv)>nR,rv=rv(1:nR);end
            h.tStat.Data=[rv,num2cell(srcStat)];
        end
        if isfield(h,'tFSIT')&&isvalid(h.tFSIT)
            if ~isempty(srcT)
                fv={'FSIT_SWITYP','FSIT_SWIFO','FSIT_SWIKE','FSIT_SWIDSD','FSIT_SWIBA','FSIT_SWIBE','FSIT_SWIHM','FSIT_SWISUS','FSIT_SWIZW','FSIT_SWIVSA','FSIT_SWIECO','FSIT_SWIFCO','FSIT_SWIWA','FSIT_SWISNG','FSIT_SWIEVA','FSIT_SWICM','FSIT_SWISW_SWVrnt1','FSIT_SWISW_SWVrnt2','FSIT_SWISW_SWVrnt3','FSIT_SWIOD','FSIT_SWIREV','FSIT_SWIWE','FSIT_SWIALT'};
                nd=cell(numel(fv),3);
                for k=1:numel(fv);nd{k,1}=fv{k};nd{k,2}=extractFSITValue(srcT,fv{k});nd{k,3}=getFSITDesc(fv{k});end
                h.tFSIT.Data=nd;
            else, h.tFSIT.Data={'(Not available for reference vehicle)','',''}; end
        end
        if isfield(h,'tGearRatio')&&isvalid(h.tGearRatio)
            if useRef&&isfield(appData.refVehicle,'vehicle')
                h.tGearRatio.Data=getGearRatioDataFromInputStruct(appData.refVehicle.vehicle);
            else, h.tGearRatio.Data=getGearRatioDataFromUserInputs(fig); end
        end
        if isfield(h,'tGBFTabss')&&isvalid(h.tGBFTabss)&&~isempty(srcT)
            g=extractInterpVariable(srcT,'GBF_TABSS');
            if ~isempty(g)&&~isempty(g.data),h.tGBFTabss.Data=num2cell(g.data);h.gbfVI=g;end
        end
        if isfield(h,'tFacEngSpd')&&isvalid(h.tFacEngSpd)&&~isempty(srcT)
            f=extractInterpVariable(srcT,'UKKE_FacEngSpdMax');
            if ~isempty(f)&&~isempty(f.data),h.tFacEngSpd.Data=num2cell(reshape(f.data,1,[]));h.facVI=f;end
        end
        if isfield(h,'tNmax')&&isvalid(h.tNmax)&&~isempty(srcT)
            n=extractInterpVariable(srcT,'UKKE_NMAX');
            if ~isempty(n)&&~isempty(n.data)
                tn=cell(2,length(n.data));
                for c=1:length(n.data);tn{1,c}=n.xAxis(min(c,end));tn{2,c}=n.data(c);end
                h.tNmax.Data=tn; h.nmaxVI=n;
            end
        end
        if isfield(h,'ukFileLabel')&&isvalid(h.ukFileLabel)
            if useRef, h.ukFileLabel.Text=['[REF] ' refDesc]; h.ukFileLabel.FontColor=[0.0 0.35 0.65];
            else, h.ukFileLabel.Text=char(appData.sourceFilename); h.ukFileLabel.FontColor=[0.3 0.3 0.3]; end
        end
        ukFig.UserData=h;
        updateUKTableFilters(ukFig,fig);
    catch; end
end


function newUK = buildUKDisplayData(fig, ukData, srcStat)
% Rebuild enriched UK display table. srcStat: correct STAT matrix (ref or working).
    try
        appData = fig.UserData;
        activeAbbrevs = appData.activeAbbrevs;
        if nargin < 3 || isempty(srcStat)
            statMatrix = appData.statTabul;
        else
            statMatrix = srcStat;
        end

        nRows = size(ukData,1);
        newUK = cell(nRows, 9);
        if nRows == 0, return; end

        % Vectorise column assignments (no row loop needed for static cols)
        newUK(:,1) = ukData(:,1);   % UK Name
        newUK(:,2) = ukData(:,2);   % Abbrev
        newUK(:,4) = ukData(:,3);   % ID
        newUK(:,5) = ukData(:,4);   % SKLID
        newUK(:,6) = ukData(:,5);   % UL
        newUK(:,7) = ukData(:,6);   % USP
        newUK(:,8) = ukData(:,7);   % DSP
        if size(ukData,2) >= 8
            newUK(:,9) = cellfun(@(x) char(strtrim(string(x))), ukData(:,8), 'UniformOutput', false);
        else
            newUK(:,9) = repmat({'Not Found'}, nRows, 1);
        end

        % FSIT_Act column — single pass: check abbrev against activeAbbrevs list
        if isempty(activeAbbrevs)
            newUK(:,3) = repmat({''}, nRows, 1);
        else
            abbrevCol = string(ukData(:,2));
            fsitMatch = false(nRows,1);
            for k = 1:numel(activeAbbrevs)
                tk = activeAbbrevs{k};
                if ~isempty(tk)
                    fsitMatch = fsitMatch | contains(abbrevCol, tk, 'IgnoreCase', true);
                end
            end
            newUK(fsitMatch, 3)  = {'Yes'};
            newUK(~fsitMatch, 3) = {''};
        end
    catch
        newUK = ukData;
    end
end

function updateUKTableFilters(ukFig, mainFig)
    appData = mainFig.UserData; h = ukFig.UserData; tUK = h.tUK; tStat = h.tStat;
    filterSKLID = strtrim(h.filterField.Value);
    filterMapNum = strtrim(h.mapFilterField.Value);

    % Use ref vehicle statTabul only when Map A holds a ref map (isWCRef&&isRefMode)
    isWCRefUKF=~isempty(appData.workingCopy)&&isfield(appData.workingCopy,'isRef')&&appData.workingCopy.isRef;
    isRefModeUKF=isfield(appData,'isRefMode')&&appData.isRefMode&&isfield(appData,'refVehicle');
    if isWCRefUKF&&isRefModeUKF&&isfield(appData.refVehicle,'statTabul'), statMatrix=appData.refVehicle.statTabul;
    elseif isfield(appData,'statTabul'), statMatrix=appData.statTabul;
    else, statMatrix=[]; end

    % Check if we have the new fullDisplayData (6 columns)
    hasFullData = false;
    if isscalar(h) && isfield(h, 'fullDisplayData')
        hasFullData = ~isempty(h.fullDisplayData);
    elseif isstruct(h) && numel(h) > 1 && isfield(h, 'fullDisplayData')
        hasFullData = ~isempty(h(1).fullDisplayData);
        h = h(1);
    end

    if hasFullData
        sourceData = h.fullDisplayData;
        colID = 4; colName = 5; colVal = 9; colFSIT = 3; colUL = 6; colUSP = 7; colDSP = 8;
    else
        sourceData = appData.ukData;
        colID = 3; colName = 4; colVal = 8; colFSIT = 0; colUL = 5; colUSP = 6; colDSP = 7;
    end

    % 1. Filter Logic - Apply both filters
    filteredIDs = [];
    isFilterActive = ~isempty(filterSKLID) || ~isempty(filterMapNum);
    idxKeep = true(size(sourceData, 1), 1);
    
    % Filter by SKLID (column 5 - colName)
    if ~isempty(filterSKLID)
        rawSklIdData = string(sourceData(:, colName));
        idxKeep = idxKeep & startsWith(rawSklIdData, filterSKLID, 'IgnoreCase', true);
    end
    
    % Filter by Map Number (column 6 - colVal)
    if ~isempty(filterMapNum)
        rawMapData = string(sourceData(:, colVal));
        % Check if map number is contained in the Map Number column
        idxMap = false(size(sourceData, 1), 1);
        for i = 1:size(sourceData, 1)
            mapStr = rawMapData(i);
            if ~ismissing(mapStr) && ~strcmp(mapStr, 'Not Found')
                % Split by comma and check for exact match
                mapParts = strsplit(char(mapStr), ',');
                for p = 1:length(mapParts)
                    partNum = strtrim(mapParts{p});
                    if strcmp(partNum, filterMapNum)
                        idxMap(i) = true;
                        break;
                    end
                end
            end
        end
        idxKeep = idxKeep & idxMap;
    end
    
    % Apply filter
    tUK.Data = sourceData(idxKeep, :);
    
    % Extract IDs from filtered data ONLY if filter is active
    if isFilterActive
        rawIDs = tUK.Data(:, colID);
        tmp = zeros(1, size(tUK.Data, 1));  % pre-allocate
        nIDs = 0;
        for k = 1:size(tUK.Data, 1)
            v = str2double(string(rawIDs{k}));
            if ~isnan(v), nIDs = nIDs + 1; tmp(nIDs) = v; end
        end
        filteredIDs = tmp(1:nIDs);
    end

    % 2. Style UK Table — collect indices first, then batch addStyle (huge perf gain)
    removeStyle(tUK);
    nUKRows  = size(tUK.Data, 1);
    if nUKRows > 0
        % Pre-read entire column vectors once (avoids per-row table access)
        colValData  = tUK.Data(:, colVal);
        colNameData = tUK.Data(:, colName);
        colIDData   = tUK.Data(:, colID);
        hasFSITCol  = colFSIT > 0 && colFSIT <= size(tUK.Data,2);  % renamed: bool guard
        if hasFSITCol
            colFSITData = tUK.Data(:, colFSIT);   % pre-read only if column exists
        end
        colULData   = tUK.Data(:, colUL);
        colUSPData  = tUK.Data(:, colUSP);
        colDSPData  = tUK.Data(:, colDSP);

        % Pre-build fast ID lookup from statMatrix (avoids ismember inside loop)
        statIDs = unique(statMatrix(:));   % flat unique values for fast lookup
        statIDs = statIDs(~isnan(statIDs) & statIDs > 0);
        isInStat = @(id) ~isempty(statIDs) && any(statIDs == id);

        % Categorise rows into index buckets
        notFoundRows = []; nameRows = []; greenIDRows = []; yellowIDRows = [];
        fsitYesRows = [];
        ulYesRows = []; ulDimRows = []; uspYesRows = []; uspDimRows = [];
        dspYesRows = []; dspDimRows = [];

        for i = 1 : nUKRows
            isNF = strcmp(char(string(colValData{i})), 'Not Found');
            if isNF
                notFoundRows(end+1) = i; %#ok<AGROW>
            else
                nameRows(end+1) = i; %#ok<AGROW>
                id = str2double(string(colIDData{i}));
                if ~isnan(id) && isInStat(id)
                    greenIDRows(end+1) = i; %#ok<AGROW>
                else
                    yellowIDRows(end+1) = i; %#ok<AGROW>
                end
            end
            if hasFSITCol && strcmpi(char(string(colFSITData{i})), 'Yes')
                fsitYesRows(end+1) = i; %#ok<AGROW>
            end
            % UL/USP/DSP
            ulV = char(string(colULData{i}));
            if strcmp(ulV,'YES'), ulYesRows(end+1)=i; elseif startsWith(ulV,'(YES)'), ulDimRows(end+1)=i; end %#ok<AGROW>
            uspV = char(string(colUSPData{i}));
            if strcmp(uspV,'YES'), uspYesRows(end+1)=i; elseif startsWith(uspV,'(YES)'), uspDimRows(end+1)=i; end %#ok<AGROW>
            dspV = char(string(colDSPData{i}));
            if strcmp(dspV,'YES'), dspYesRows(end+1)=i; elseif startsWith(dspV,'(YES)'), dspDimRows(end+1)=i; end %#ok<AGROW>
        end

        % Apply batched styles — one addStyle call per style category
        % Cache all style objects as persistent to avoid per-call allocation
        persistent sGray_ sBlue_ sGreenBg_ sFsitBlue_ sULYes_ sULDim_ sUSPYes_ sUSPDim_ sDSPYes_ sDSPDim_ sCyan_;
        if isempty(sGray_)
            sGray_    = uistyle('FontColor',[0.6 0.6 0.6]);
            sBlue_    = uistyle('FontColor','blue','FontWeight','bold');
            sGreenBg_ = uistyle('BackgroundColor',[0.8 1 0.8]);
            sFsitBlue_= uistyle('BackgroundColor',[0.4 0.6 1],'FontColor','black','FontWeight','bold');
            sULYes_   = uistyle('BackgroundColor',[0.82 0.94 0.82],'FontWeight','bold');
            sULDim_   = uistyle('BackgroundColor',[0.85 0.95 0.85],'FontColor',[0.4 0.4 0.4],'FontAngle','italic');
            sUSPYes_  = uistyle('BackgroundColor',[0.95 0.88 0.72],'FontWeight','bold');
            sUSPDim_  = uistyle('BackgroundColor',[0.93 0.90 0.78],'FontColor',[0.4 0.4 0.4],'FontAngle','italic');
            sDSPYes_  = uistyle('BackgroundColor',[0.72 0.88 0.95],'FontWeight','bold');
            sDSPDim_  = uistyle('BackgroundColor',[0.80 0.90 0.93],'FontColor',[0.4 0.4 0.4],'FontAngle','italic');
            sCyan_    = uistyle('BackgroundColor',[0 1 1],'FontWeight','bold');
        end
        if ~isempty(notFoundRows),  addStyle(tUK, sGray_,    'row', notFoundRows); end
        if ~isempty(nameRows),      addStyle(tUK, sBlue_,    'cell', [nameRows(:), repmat(colName, numel(nameRows),1)]); end
        if ~isempty(greenIDRows),   addStyle(tUK, sGreenBg_, 'cell', [greenIDRows(:), repmat(colID, numel(greenIDRows),1)]); end
        if ~isempty(yellowIDRows),  addStyle(tUK, getSoftYellowStyle(), 'cell', [yellowIDRows(:), repmat(colID, numel(yellowIDRows),1)]); end
        if hasFSITCol && ~isempty(fsitYesRows), addStyle(tUK, sFsitBlue_, 'cell', [fsitYesRows(:), repmat(colFSIT, numel(fsitYesRows),1)]); end
        if ~isempty(ulYesRows),  addStyle(tUK, sULYes_,  'cell', [ulYesRows(:),  repmat(colUL, numel(ulYesRows),1)]); end
        if ~isempty(ulDimRows),  addStyle(tUK, sULDim_,  'cell', [ulDimRows(:),  repmat(colUL, numel(ulDimRows),1)]); end
        if ~isempty(uspYesRows), addStyle(tUK, sUSPYes_, 'cell', [uspYesRows(:), repmat(colUSP,numel(uspYesRows),1)]); end
        if ~isempty(uspDimRows), addStyle(tUK, sUSPDim_, 'cell', [uspDimRows(:), repmat(colUSP,numel(uspDimRows),1)]); end
        if ~isempty(dspYesRows), addStyle(tUK, sDSPYes_, 'cell', [dspYesRows(:), repmat(colDSP,numel(dspYesRows),1)]); end
        if ~isempty(dspDimRows), addStyle(tUK, sDSPDim_, 'cell', [dspDimRows(:), repmat(colDSP,numel(dspDimRows),1)]); end
    end

    % 3. Style STAT_TABUL - ONLY when filter is active
    removeStyle(tStat);
    if isFilterActive && ~isempty(filteredIDs)
        statData = statMatrix;  % resolved above to ref or working file data
        [r, c] = find(ismember(statData, filteredIDs));
        if ~isempty(r)
            uiCols = c + 1;
            if isempty(sCyan_), sCyan_ = uistyle('BackgroundColor',[0 1 1],'FontWeight','bold'); end
            addStyle(tStat, sCyan_, 'cell', [r, uiCols]);
            scroll(tStat, 'cell', [r(1), uiCols(1)]);
        end
    end
end

function exportUKTableToExcel(ukFig, mainFig)
% Export UK Table to Excel with colours matching the MATLAB table exactly.

    h = ukFig.UserData;
    tUK = h.tUK;
    data = tUK.Data;
    colNames = tUK.ColumnName;
    appData = mainFig.UserData;
    statMatrix = []; if isfield(appData,'statTabul'), statMatrix = appData.statTabul; end

    if isempty(data)
        uialert(ukFig,'No data to export.','Export'); return;
    end

    [file, path] = uiputfile('*.xlsx','Save UK Table as Excel','UK_Table.xlsx');
    if isequal(file,0), return; end
    fullPath = fullfile(path, file);

    % ── Find column indices by name (robust — independent of hasFullData) ─────
    colID   = find(strcmp(colNames,'ID'),        1);
    colName = find(strcmp(colNames,'SKLID'),     1);
    colFSIT = find(strcmp(colNames,'FSIT_Act'),  1);
    colUL   = find(strcmp(colNames,'UL'),        1);
    colUSP  = find(strcmp(colNames,'USP'),       1);
    colDSP  = find(strcmp(colNames,'DSP'),       1);
    colVal  = find(strcmp(colNames,'Map Number'),1);

    % ── Build export cell array ───────────────────────────────────────────────
    nRows = size(data,1); nCols = size(data,2);
    exportData = cell(nRows+1, nCols);
    exportData(1,:) = colNames(:)';
    for r = 1:nRows
        for c = 1:nCols
            v = data{r,c};
            if isempty(v),        exportData{r+1,c} = '';
            elseif isnumeric(v),  exportData{r+1,c} = v;
            else,                 exportData{r+1,c} = char(string(v));
            end
        end
    end
    try
        writecell(exportData, fullPath, 'Sheet', 1);
    catch ME
        uialert(ukFig, sprintf('Export failed:\n%s', ME.message), 'Export Error','Icon','error');
        return;
    end

    % ── COM colour coding (Windows only) ─────────────────────────────────────
    if ~ispc
        uialert(ukFig, sprintf('Exported (colours require Windows):\n%s', fullPath), ...
            'Export Complete','Icon','success');
        return;
    end

    % Pre-computed OLE integers: R + G*256 + B*65536  (each channel rounded 0-255)
    % Verified against exact MATLAB uistyle values in updateUKTableFilters
    C_GREY_FONT  = 10066329;  % [0.6 0.6 0.6]  Not Found row
    C_BLUE_FONT  = 16711680;  % [0 0 1]        SKLID blue
    C_GREEN_BG   = 13434828;  % [0.8 1 0.8]    ID in STAT_TABUL
    C_YELLOW_BG  = 13434879;  % [1 1 0.8]      ID not in STAT_TABUL
    C_FSIT_BG    = 16750950;  % [0.4 0.6 1]    FSIT_Act Yes bg
    C_UL_BG      = 13758673;  % [0.82 0.94 0.82] UL YES
    C_USP_BG     = 12116210;  % [0.95 0.88 0.72] USP YES  (amber/peach)
    C_DSP_BG     = 15917240;  % [0.72 0.88 0.95] DSP YES  (sky blue)
    C_UL_DIM     = 14217944;  % UL (YES)  = [0.82 0.94 0.82].*0.85+0.15
    C_USP_DIM    = 12772852;  % USP (YES) = [0.95 0.88 0.72].*0.85+0.15
    C_DSP_DIM    = 16049602;  % DSP (YES) = [0.72 0.88 0.95].*0.85+0.15
    C_DIM_FONT   =  6710886;  % [0.4 0.4 0.4]  (YES) italic font
    C_HDR_BG     =  3355443;  % [0.2 0.2 0.2]  header dark bg
    C_WHITE_FONT = 16777215;  % [1 1 1]        header font

    xlApp = []; xlWb = [];
    try
        % COM requires an absolute Windows path with backslashes
        fullPathCOM = strrep(char(java.io.File(fullPath).getAbsolutePath()), '/', '\');
        xlApp = actxserver('Excel.Application');
        xlApp.Visible = false;
        xlWb = xlApp.Workbooks.Open(fullPathCOM);
        xlSh = xlWb.Sheets.Item(1);

        % Header row
        hdr = xlSh.Range(sprintf('A1:%s1', xlColLetter(nCols)));
        hdr.Interior.Color = C_HDR_BG;
        hdr.Font.Color     = C_WHITE_FONT;
        hdr.Font.Bold      = true;

        % Data rows
        for r = 1:nRows
            exR = r + 1;
            isNF = ~isempty(colVal) && strcmp(char(string(data{r,colVal})), 'Not Found');

            if isNF
                % Grey entire row font
                xlSh.Range(sprintf('A%d:%s%d', exR, xlColLetter(nCols), exR)).Font.Color = C_GREY_FONT;
            else
                % SKLID: blue bold
                if ~isempty(colName)
                    sc = xlSh.Range(sprintf('%s%d', xlColLetter(colName), exR));
                    sc.Font.Color = C_BLUE_FONT; sc.Font.Bold = true;
                end
                % ID: green bg if in STAT_TABUL, yellow otherwise
                if ~isempty(colID)
                    id = str2double(char(string(data{r,colID})));
                    ic = xlSh.Range(sprintf('%s%d', xlColLetter(colID), exR));
                    if ~isnan(id) && ~isempty(statMatrix) && ismember(id, statMatrix)
                        ic.Interior.Color = C_GREEN_BG;
                    else
                        ic.Interior.Color = C_YELLOW_BG;
                    end
                end
            end

            % FSIT_Act: blue bg when Yes
            if ~isempty(colFSIT) && strcmpi(char(string(data{r,colFSIT})), 'Yes')
                fc = xlSh.Range(sprintf('%s%d', xlColLetter(colFSIT), exR));
                fc.Interior.Color = C_FSIT_BG;
                fc.Font.Bold = true;
            end

            % UL / USP / DSP
            if ~isempty(colUL)
                applyYesBg(xlSh, data{r,colUL}, xlColLetter(colUL), exR, C_UL_BG,  C_UL_DIM,  C_DIM_FONT);
            end
            if ~isempty(colUSP)
                applyYesBg(xlSh, data{r,colUSP}, xlColLetter(colUSP), exR, C_USP_BG, C_USP_DIM, C_DIM_FONT);
            end
            if ~isempty(colDSP)
                applyYesBg(xlSh, data{r,colDSP}, xlColLetter(colDSP), exR, C_DSP_BG, C_DSP_DIM, C_DIM_FONT);
            end
        end

        xlSh.Columns.AutoFit();
        xlWb.Save(); xlWb.Close(false); xlApp.Quit(); xlApp.delete();
        uialert(ukFig, sprintf('Exported with colours:\n%s', fullPath), ...
            'Export Complete','Icon','success');
    catch ME
        try, xlWb.Close(false); catch, end
        try, xlApp.Quit(); xlApp.delete(); catch, end
        uialert(ukFig, sprintf('Colour styling failed:\n%s\n\nFile saved without colours.', ME.message), ...
            'Export Warning','Icon','warning');
    end
end

function applyYesBg(xlSh, cellVal, colLtr, exRow, bgFull, bgDim, dimFont)
    s = char(string(cellVal));
    if strcmp(s, 'YES')
        xc = xlSh.Range(sprintf('%s%d', colLtr, exRow));
        xc.Interior.Color = bgFull; xc.Font.Bold = true;
    elseif strncmp(s,'(YES)',5)
        xc = xlSh.Range(sprintf('%s%d', colLtr, exRow));
        xc.Interior.Color = bgDim; xc.Font.Color = dimFont; xc.Font.Italic = true;
    end
end


function showHelp(fig, tabIdx)
% Open the Help window. Optional tabIdx (1..4) selects which tab is shown:
%   1 = Support & Contact (default)
%   2 = Special Thanks
%   3 = Report & Request
%   4 = Version History
    if nargin < 2, tabIdx = 1; end
    % 1. Create the main window - ALWAYS ON TOP
    d = uifigure('Name', 'Help & Credits', ...
        'Position', [100 100 550 550], ...
        'WindowStyle', 'alwaysontop', ...
        'Resize', 'on', ...
        'Color', [1 1 1]); 
    movegui(d, 'center');
    drawnow limitrate;

    % 2. Main Layout (Top = Tabs, Bottom = Close Button)
    mainGrid = uigridlayout(d, [2, 1]);
    mainGrid.RowHeight = {'1x', 50}; % Tabs take all space, Button gets 50px at bottom
    mainGrid.Padding = [10 10 10 10];

    % 3. Create Tab Group
    tg = uitabgroup(mainGrid);
    
    % ============================================================
    % TAB 1: CONTACTS & DEVELOPER
    % ============================================================
    t1 = uitab(tg, 'Title', 'Support & Contact');
    
    % Grid specifically for Tab 1
    t1Grid = uigridlayout(t1, [3, 1]); 
    t1Grid.RowHeight = {40, '1x', 140}; % Header, Contacts, Dev Info
    t1Grid.Padding = [20 20 20 20];
    t1Grid.RowSpacing = 15;

    % --- Tab 1 Header ---
    lblHeader = uilabel(t1Grid);
    lblHeader.Text = "Support Contacts";
    lblHeader.FontSize = 22;
    lblHeader.FontWeight = 'bold';
    lblHeader.FontColor = [0 0.3 0.6]; 

    % --- Contact List ---
    contactGrid = uigridlayout(t1Grid, [3, 2]); 
    contactGrid.ColumnWidth = {'1x', '2x'}; 
    contactGrid.RowHeight = {'1x', '1x', '1x'};
    contactGrid.RowSpacing = 10;

    addContactRow(contactGrid, 'Paul Tuttle', 'paul.tuttle@stellantis.com');
    addContactRow(contactGrid, 'Kyle Schumaker', 'kyle.schumaker@stellantis.com');
    addContactRow(contactGrid, 'Chenthu Manikasingam', 'chenthuran.manikasingam@external.stellantis.com');

    % --- Developer Info ---
    pnlDev = uipanel(t1Grid);
    pnlDev.Title = "About the Developer";
    pnlDev.FontSize = 14;
    pnlDev.FontWeight = 'bold';
    pnlDev.BackgroundColor = [0.96 0.96 0.96]; 
    
    devGrid = uigridlayout(pnlDev, [3, 1]);
    devGrid.RowHeight = {30, 30, 30}; 
    devGrid.Padding = [10 10 10 10];
    devGrid.RowSpacing = 5;
    
    uilabel(devGrid, 'Text', 'Developed by: Chenthu Manikasingam', 'FontWeight', 'bold');
    uilabel(devGrid, 'Text', 'Organization: ASIS, Department 7220');
    
    efDev = uieditfield(devGrid, 'text');
    efDev.Value = "chenthuran.manikasingam@external.stellantis.com";
    efDev.Editable = 'off'; 
    efDev.BackgroundColor = [1 1 1]; 

    % ============================================================
    % TAB 2: SPECIAL THANKS
    % ============================================================
    t2 = uitab(tg, 'Title', 'Special Thanks');
    
    % Grid for Tab 2
    t2Grid = uigridlayout(t2, [2, 1]);
    t2Grid.RowHeight = {60, '1x'};
    t2Grid.Padding = [40 20 40 20];
    
    % Header
    lblThanks = uilabel(t2Grid);
    lblThanks.Text = "Acknowledgements";
    lblThanks.FontSize = 20;
    lblThanks.FontWeight = 'bold';
    lblThanks.FontColor = [0 0.3 0.6]; 
    lblThanks.HorizontalAlignment = 'center';

    % Names List (Using a TextArea for a clean list look)
    % Formatting names nicely
    namesList = sprintf([...
        'Special thanks to the following contributors:\n\n' ...
        ' Eric Boldenow\n' ...
        ' Kyle Schumaker\n' ...
        ' Javed Dada\n' ...
        ' Anthony Bootka\n' ...
        ' Paul Tuttle\n' ...
        ' Stephen Arno\n' ...
        ' Dustin Kolodge \n' ...
        ' Joonhyuck Kim\n' ...
        ' Uzair Mazhar\n' ...
        ' John Keyser\n' ...
        ' Gabriella Mirakaj\n' ...
        ' Maneesh Mallikarjunaswamy\n' ...
        ' Krishna Soundarajan']);
    
    txtThanks = uitextarea(t2Grid);
    txtThanks.Value = split(namesList, newline);
    txtThanks.Editable = 'off';
    txtThanks.FontSize = 16;   % restored original size
    txtThanks.FontName = 'Segoe UI';
    txtThanks.HorizontalAlignment = 'center';
    txtThanks.BackgroundColor = [1 1 1];

    % ============================================================
    % TAB 3: REPORT & REQUEST
    % ============================================================
    t3 = uitab(tg, 'Title', '📋 Report & Request');

    t3Grid = uigridlayout(t3, [5, 1]);
    t3Grid.RowHeight = {50, 70, '1x', 70, 44};
    t3Grid.Padding   = [30 24 30 24];
    t3Grid.RowSpacing = 14;
    t3Grid.BackgroundColor = [1 1 1];

    % Header
    lblR = uilabel(t3Grid);
    lblR.Text = 'Report & Request';
    lblR.FontSize = 22;
    lblR.FontWeight = 'bold';
    lblR.FontColor = [0 0.3 0.6];

    % Description
    lblDesc = uilabel(t3Grid);
    lblDesc.Text = sprintf(['Found a bug or have an idea for the next release?\n' ...
        'Use the button below to open the feedback form.']);
    lblDesc.FontSize = 12;
    lblDesc.FontColor = [0.25 0.25 0.25];
    lblDesc.WordWrap = 'on';
    lblDesc.VerticalAlignment = 'top';

    % What you can report panel
    pnlInfo = uipanel(t3Grid, 'Title', 'What you can submit', ...
        'FontWeight', 'bold', 'FontSize', 11, ...
        'BackgroundColor', [0.96 0.97 1]);
    infoGL = uigridlayout(pnlInfo, [2, 2], ...
        'RowHeight', {28, 28}, 'ColumnWidth', {'1x','1x'}, ...
        'Padding', [12 8 12 8], 'RowSpacing', 4, ...
        'BackgroundColor', [0.96 0.97 1]);
    uilabel(infoGL, 'Text', '🐛  Bug Report',          'FontSize', 12, 'BackgroundColor', [0.96 0.97 1]);
    uilabel(infoGL, 'Text', '✨  Feature Request',      'FontSize', 12, 'BackgroundColor', [0.96 0.97 1]);
    uilabel(infoGL, 'Text', '💡  Improvement Idea',    'FontSize', 12, 'BackgroundColor', [0.96 0.97 1]);
    uilabel(infoGL, 'Text', '📝  General Feedback',    'FontSize', 12, 'BackgroundColor', [0.96 0.97 1]);

    % Main form button
    btnForm = uibutton(t3Grid, 'push');
    btnForm.Text     = '🔗  Open Feedback Form';
    btnForm.FontSize = 14;
    btnForm.FontWeight = 'bold';
    btnForm.BackgroundColor = [0.0 0.45 0.74];
    btnForm.FontColor = [1 1 1];
    btnForm.Tooltip  = 'Opens the feedback form in your default web browser';
    btnForm.ButtonPushedFcn = @(~,~) openFeedbackForm();

    % Version note
    lblVer = uilabel(t3Grid);
    lblVer.Text = 'Pattern Plotter V7.6.4.C.CM  —  Your feedback shapes future releases.';
    lblVer.FontSize = 10;
    lblVer.FontColor = [0.55 0.55 0.55];
    lblVer.HorizontalAlignment = 'center';

    % ============================================================
    % TAB 4: VERSION HISTORY
    % ============================================================
    t4 = uitab(tg, 'Title', '📦 Version History');

    t4Grid = uigridlayout(t4, [3, 1]);
    t4Grid.RowHeight = {56, 40, '1x'};
    t4Grid.Padding   = [24 20 24 16];
    t4Grid.RowSpacing = 10;
    t4Grid.BackgroundColor = [1 1 1];

    % Header row — tool name + current version badge
    hdrGrid = uigridlayout(t4Grid, [1, 2]);
    hdrGrid.ColumnWidth = {'1x', 160};
    hdrGrid.Padding = [0 0 0 0];
    hdrGrid.BackgroundColor = [1 1 1];

    lblToolName = uilabel(hdrGrid);
    lblToolName.Text = 'Pattern Plotter';
    lblToolName.FontSize = 22;
    lblToolName.FontWeight = 'bold';
    lblToolName.FontColor = [0 0.3 0.6];

    lblBadge = uilabel(hdrGrid);
    lblBadge.Text = 'Current: V7.6.4.C.CM';
    lblBadge.FontSize = 11;
    lblBadge.FontWeight = 'bold';
    lblBadge.FontColor = [1 1 1];
    lblBadge.BackgroundColor = [0.0 0.45 0.74];
    lblBadge.HorizontalAlignment = 'center';
    lblBadge.VerticalAlignment = 'center';

    % Short tool summary
    lblSummary = uilabel(t4Grid);
    lblSummary.Text = sprintf(['A MATLAB-based calibration tool for visualising, comparing and editing ' ...
        'ZF 8-speed transmission shift maps from CSV calibration files.']);
    lblSummary.FontSize = 11;
    lblSummary.FontColor = [0.3 0.3 0.3];
    lblSummary.WordWrap = 'on';
    lblSummary.VerticalAlignment = 'top';

    % Version history text area
    verHistory = sprintf([...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        ' V7.6.4.C.CM  (Current Release)\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        '  • Full bug-fix audit pass — fixes below\n' ...
        '  • FIX: Level Comparison tab crashed when Process was pressed\n' ...
        '    (summary status banner was never created) — now shows results\n' ...
        '  • FIX: window title bar / About box showed the previous version\n' ...
        '  • FIX: Table Editor Add-Offset and Ctrl+V paste applied raw RPM\n' ...
        '    values on the MPH/KPH/Turbine/Engine tabs — now guarded\n' ...
        '  • FIX: Multi-Map editor distance field discarded a typed value\n' ...
        '  • FIX: Consistency check reports L1 and L2 hysteresis separately\n' ...
        '  • FIX: INCA registry scan aborted on the first non-INCA key;\n' ...
        '    INCA diagnostic failed to locate the main window\n' ...
        '  • FIX: Dyno Excel export — corrected dark-gold cell font colour\n' ...
        '  • FIX: Interpolation undo guarded against linked-table resize\n' ...
        '  • Removed dead/no-op code; corrected layout grid column counts\n' ...
        '\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        ' V7.6.3.C.CM\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        '  • Interpolation window REWRITTEN: uses uigridlayout instead of\n' ...
        '    pixel-positioned panels — fixes missing tables, cut-off rows,\n' ...
        '    and slow load on R2024b + Windows DPI scaling (125%/150%)\n' ...
        '  • buildScrollTab + buildSiODTab now use auto-managed grid with\n' ...
        '    Scrollable=on — MATLAB handles all sizing/positioning\n' ...
        '  • Removed all getpixelposition() calls in interp loaders\n' ...
        '    (each call forced a layout pass = slow + unreliable)\n' ...
        '  • Row heights properly account for uipanel title bar (28px) so\n' ...
        '    bottom rows are always fully visible\n' ...
        '\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        ' V7.6.2.C.CM\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        '  • Status bar moved into figure title bar — saves another 18px\n' ...
        '    (combined w/ V7.6.1 bottom-bar removal: +40px for the plot)\n' ...
        '  • GUI gaps closed: Map A: right-aligned next to dropdown;\n' ...
        '    4Lo Mode pulled left toward Clear All Lines\n' ...
        '  • Interpolation loader now progressive — per-tab try/catch,\n' ...
        '    drawnow yields, and diagnostic logging tell you exactly\n' ...
        '    which tab fails if the window hangs (Help → Diagnostic Log)\n' ...
        '  • INCA-MIP detection improved — searches C:\\Apps\\ETASData,\n' ...
        '    D:/E: drives, and accepts .m / .p / .mexw64 entry points\n' ...
        '    (covers Stellantis enterprise MIP installs in INCA 7.4)\n' ...
        '  • INCA diagnostic now probes for CalibrationMatrixData wrapper\n' ...
        '    factory + ProgID — needed for direct COM writes on INCA 7.4\n' ...
        '  • Auto-save: recursive graphics-handle scrubber prevents the\n' ...
        '    "Figure is saved in ...mat" warning during background saves\n' ...
        '  • About dialog: 2 maintainers (Chenthu Manikasingam, Paul Tuttle)\n' ...
        '\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        ' V7.6.1.C.CM\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        '  • Bug fix: Edit Map A is now editable when Ref Mode is ON until\n' ...
        '    a [REF] map is actually swapped INTO Map A (was incorrectly\n' ...
        '    blocking edits as soon as Ref Mode toggled on)\n' ...
        '  • Same bug fixed in 3 places: edit handler, Turbine/Engine RPM\n' ...
        '    gear ratio selection, and Save Modified Map guard\n' ...
        '  • GUI restructure: top-right red status bar (was bottom);\n' ...
        '    3-row file label stack on left (A:/B:/C: per slot, updates on\n' ...
        '    swap); Map A: and Edit Map A vertically aligned (col 1 = 90px);\n' ...
        '    refLbl moved to wide space between Map C and Help button;\n' ...
        '    bottom 22px status bar removed → +4px vertical space\n' ...
        '  • Save Project / Load Project / DB / History moved from main GUI\n' ...
        '    to top menu bar (File menu and Help menu)\n' ...
        '  • TCC Editor: Turbine RPM tab guaranteed-populate via\n' ...
        '    SelectionChangedFcn; works without Edit Map A open\n' ...
        '  • R2024b compatibility — removed deprecated opengl() call\n' ...
        '    (uifigure auto-selects renderer; no warning on launch)\n' ...
        '  • INCA Sync now compatible with INCA 7.4.x — MIP path is\n' ...
        '    optional (used for 7.5.5 only); raw COM API works for both\n' ...
        '  • TCC Editor: Turbine RPM tab guaranteed-populate via\n' ...
        '    SelectionChangedFcn; works without Edit Map A open\n' ...
        '  • Full audit pass: 154/154 checks; 41 hasValidHandle calls,\n' ...
        '    207 try/catch blocks, 14 MCR pragma lines covering all 28\n' ...
        '    UI functions; ready for MATLAB Compiler deployment\n' ...
        '\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        ' V7.5.6.C.CM\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        '  • TCC Editor → Turbine RPM tab (NEW) — literal duplicate of\n' ...
        '    Edit Map A turbine table; same callbacks, colors, math menus;\n' ...
        '    updates live via updateTableDisplay + refreshTableStyles hooks\n' ...
        '\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        ' V7.5.5.C.CM\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        '  • hasValidHandle() helper — 38 unsafe field reads replaced with\n' ...
        '    a single safe pattern; eliminates "Unrecognized field name"\n' ...
        '    crashes for tableHandle, ukFig, tccFig, contextLabel, etc.\n' ...
        '  • applyLoadedProject re-seeds 13 handle fields with gobjects(0)\n' ...
        '    so loaded projects never miss critical UI state\n' ...
        '  • Auto-save restore prompt now shows source filename and timestamp\n' ...
        '  • Auto-save snapshot strips 8 additional runtime fields\n' ...
        '\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        ' V7.5.4.C.CM\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        '  • Help menu mirrors Help button — 4 tabs accessible from\n' ...
        '    top menu (Support & Contact, Special Thanks, Report,\n' ...
        '    Version History) plus Diagnostic Log and About\n' ...
        '  • showHelp() now accepts optional tab index parameter\n' ...
        '\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        ' V7.5.3.C.CM\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        '  • Auto-save / crash recovery — silent snapshot every 60 seconds\n' ...
        '    to prefdir; offers to restore on next launch if a crash occurred\n' ...
        '  • Recent Files menu (File > Recent Files) — quick access to last\n' ...
        '    8 opened CSVs and .mat projects; persists across sessions\n' ...
        '  • Status bar at bottom of main window — live display of:\n' ...
        '       Map A name + row count   |   REF vehicle (when loaded)\n' ...
        '       INCA Sync status         |   Hold Session active\n' ...
        '       Auto-save timestamp on every successful save\n' ...
        '  • New top menu bar — File / Edit / Help with keyboard shortcuts\n' ...
        '  • Diagnostic Log viewer (Help > Diagnostic Log) — collects errors\n' ...
        '    caught by silent try/catch blocks for support troubleshooting\n' ...
        '  • About dialog (Help > About) — shows version, MATLAB runtime,\n' ...
        '    deployed status, INCA-MIP path, RefDB path, contributors\n' ...
        '  • Auto-save timer cleanup on close — no orphaned timer objects\n' ...
        '\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        ' V7.4.9.C.CM\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        '  • Reference Vehicle Mode — load a second vehicle from RefDB for\n' ...
        '    side-by-side shift map comparison (Map B = ref map selector)\n' ...
        '  • RefDB Builder — build & manage reference vehicle database from CSV;\n' ...
        '    extracts UK, STAT, TCC, KWK, NWK, Gear Ratios, Axle Ratio\n' ...
        '  • UK & STAT tables update on map swap — ref vehicle data shown\n' ...
        '    when Map A holds a [REF] map; all 6 tabs refresh correctly\n' ...
        '  • Axle ratio MAP-block extraction (FZGG_AxleRatMpgToldx) —\n' ...
        '    reads row 1 = final axle ratio, derives 4Lo from row 2 / row 1\n' ...
        '  • Verify Parameters dialog — editable override fields for\n' ...
        '    Axle Ratio, Tire Circ, Idle RPM, Max RPM, 4Lo Ratio\n' ...
        '  • Context info panel (Map 60 / Map 5 display) reads correct\n' ...
        '    data source for [REF] maps after swap\n' ...
        '  • [REF] map label on Map A file-name label after swap\n' ...
        '  • applyLoadedProject h-guard fix (prevents crash on project load)\n' ...
        '  • swapMaps OFF-path: dd1 reset when it held a [REF] map\n' ...
        '  • ⚠ INCA Sync (🔗 button) — feature under active development;\n' ...
        '    do not rely on it for production calibration writes\n' ...
        '\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        ' V7.0.9.C.CM\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        '  • INCA-MIP integration — live sync of shift maps to INCA 7.5.5\n' ...
        '    via MIP INCA_SetValue with raw COM fallback\n' ...
        '  • INCA-MIP path dialog — saved per session, auto-detects install\n' ...
        '  • Hold & Save Session — dropdown lock during active session;\n' ...
        '    swap bug fixed (re-entrant callback guard)\n' ...
        '  • Engine RPM coast-down fix — uses current gear ratio (not destination)\n' ...
        '  • Report & Request tab — in-tool feedback form link\n' ...
        '  • ukData col-8 migration — old .mat projects load without crash\n' ...
        '  • enforceRowConstraints — pedal boundary rows preserved (0 / 110)\n' ...
        '  • Full code audit: stale appData, session lock, MCR pragmas\n' ...
        '\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        ' V6.2.8.J.CM\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        '  • INCA COM automation — initial Inca.Inca connection\n' ...
        '    (GetOpenedExperiment / GetCalibrationElement)\n' ...
        '  • Registry scan for INCA ProgID auto-discovery\n' ...
        '  • Hold & Save Session — 3-slot A/B/C working copy persistence\n' ...
        '  • Table editor — Engine RPM / Turbine RPM / MPH / KPH tabs\n' ...
        '  • Drag editing with ghost point visualisation\n' ...
        '  • Hysteresis & consistency checks (vectorised)\n' ...
        '  • DCM / PNG / Excel export\n' ...
        '  • Multi-map heatmap & deviation analysis\n' ...
        '  • UK table — Map Number scanning (maxLookAhead = 300)\n' ...
        '  • Drive mode auto-assignment (Auto/Sport/Track)\n' ...
        '\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        ' V5.4.6  (8-Speed Foundation)\n' ...
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' ...
        '  • Initial release — CSV import, plot, compare 8-speed ZF maps\n' ...
        '  • SKL_GKF shift map visualisation (Output RPM vs Pedal %)\n' ...
        '  • Map A / Map B overlay with swap button\n' ...
        '  • TCC torque converter clutch map editor\n' ...
        '  • UK / STAT table viewer\n' ...
        '  • Save Modified Map to allMaps\n' ...
        '  • Project save / load (.mat)\n' ...
        '  • Gear ratio input & 4Lo mode\n' ...
        '  • Compiled Windows .exe via MATLAB Compiler\n' ...
        ]);

    txtVer = uitextarea(t4Grid);
    txtVer.Value    = split(verHistory, newline);
    txtVer.Editable = 'off';
    txtVer.FontSize = 11;
    txtVer.FontName = 'Courier New';
    txtVer.BackgroundColor = [0.97 0.98 1];

    % ============================================================
    % SHARED FOOTER (CLOSE BUTTON)
    % ============================================================
    btnClose = uibutton(mainGrid, 'push');
    btnClose.Text = 'Close Window';
    btnClose.FontSize = 14;
    btnClose.BackgroundColor = [0.2 0.2 0.2]; 
    btnClose.FontColor = [1 1 1]; 
    btnClose.ButtonPushedFcn = @(~,~) delete(d);

    % ---------------------------------------------------------
    % NESTED HELPER FUNCTIONS
    % ---------------------------------------------------------
    function addContactRow(parentGrid, name, email)
        l = uilabel(parentGrid);
        l.Text = name;
        l.FontWeight = 'bold';
        
        e = uieditfield(parentGrid, 'text');
        e.Value = email;
        e.Editable = 'off'; 
        e.BackgroundColor = [0.95 0.98 1]; 
        e.HorizontalAlignment = 'left';
    end

    function openFeedbackForm()
        % Feedback form URL — Report & Request tab
        formURL = 'https://forms.office.com/Pages/DesignPageV2.aspx?subpage=design&FormId=zdVS2ExyKEGIEv-l2z-FB80y8R2G6RJEo3Z2KajnuOhUOVBTVkJVMVpOVlY2RkpXSElXUkM5TVBZSyQlQCN0PWcu&Token=1b4c64bca0b54514bb294e7e8ef0fc07';
        try
            web(formURL, '-browser');
        catch
            if ispc
                system(['start "" "' formURL '"']);
            elseif ismac
                system(['open "' formURL '"']);
            else
                system(['xdg-open "' formURL '"']);
            end
        end
    end

    % Select the requested tab (default is tab 1)
    try
        tabsArr = tg.Children;
        if tabIdx >= 1 && tabIdx <= numel(tabsArr)
            tg.SelectedTab = tabsArr(tabIdx);
        end
    catch; end
end
function onStatEdit(fig, src, event)
    if isempty(event.Indices), return; end  % guard: spurious callback
    appData = fig.UserData;
    if ~isfield(appData,'ukHistory'),    appData.ukHistory    = {}; end
    if ~isfield(appData,'statShadowData'), appData.statShadowData = appData.statTabul; end
    appData.ukHistory{end+1} = appData.statShadowData;
    if length(appData.ukHistory) > 20, appData.ukHistory(1) = []; end
    fullData = src.Data;
    numPart = fullData(:, 2:end);
    numericPart = zeros(size(numPart));
    for rr2 = 1:size(numPart,1)
        for cc2 = 1:size(numPart,2)
            v2 = numPart{rr2,cc2};
            if isnumeric(v2), numericPart(rr2,cc2) = v2;
            else, n2 = str2double(string(v2)); if ~isnan(n2), numericPart(rr2,cc2) = n2; else, numericPart(rr2,cc2) = 0; end; end
        end
    end
    appData.statShadowData = numericPart;
    fig.UserData = appData;
    addStyle(src, getYellowStyle(), 'cell', event.Indices);
    if isfield(appData,'ukFig') && hasValidHandle(appData, 'ukFig')
        h2 = appData.ukFig.UserData;
        if isstruct(h2), h2.ukDirty = true; appData.ukFig.UserData = h2; end
    end
end
function closeUKTable(mainFig, ukFigSrc)
% Checks for unsaved edits, prompts user, then clears appData.ukFig and deletes.
    if ~isempty(ukFigSrc) && isvalid(ukFigSrc)
        % Check dirty flag
        isDirty = false;
        try
            h = ukFigSrc.UserData;
            if isstruct(h) && isfield(h,'ukDirty'), isDirty = h.ukDirty; end
        catch; end

        if isDirty
            sel = uiconfirm(ukFigSrc, ...
                ['You have unsaved changes in the UK & STAT Table.' newline newline ...
                 'Changes made in any tab (STAT, FSIT, Gear Ratio, GBF, Curve Eng Spd) ' ...
                 'must be saved using the gold "SAVE CHANGES" button in each tab.' newline newline ...
                 'Close anyway and DISCARD all unsaved changes?'], ...
                'Unsaved Changes', ...
                'Options',       {'Discard & Close', 'Cancel'}, ...
                'DefaultOption', 'Cancel', ...
                'CancelOption',  'Cancel', ...
                'Icon',          'warning');
            if strcmp(sel, 'Cancel'), return; end
        end
    end

    if ~isempty(mainFig) && isvalid(mainFig)
        try
            ad = mainFig.UserData;
            ad.ukFig = gobjects(0);
            mainFig.UserData = ad;
        catch; end
    end
    if ~isempty(ukFigSrc) && isvalid(ukFigSrc), delete(ukFigSrc); end
end

function onUKKeyPress(fig, event)
    if strcmp(event.Key, 'z') && ~isempty(event.Modifier) && any(strcmp(event.Modifier, 'control'))
        appData = fig.UserData;
        if isempty(appData.ukHistory), return; end
        if ~isfield(appData,'ukFig') || ~hasValidHandle(appData, 'ukFig'), return; end
        lastData = appData.ukHistory{end}; appData.ukHistory(end) = []; appData.statShadowData = lastData; fig.UserData = appData;
        h = appData.ukFig.UserData; currentT = h.tStat.Data; h.tStat.Data = [currentT(:,1), num2cell(lastData)];

        % Restore Highlights by comparing with Saved Memory
        removeStyle(h.tStat);
        savedData = appData.statTabul;
        if size(savedData, 1) == size(lastData, 1) && size(savedData, 2) == size(lastData, 2)
            diffMask = savedData ~= lastData;
            [r, c] = find(diffMask);
            if ~isempty(r)
                addStyle(h.tStat, getYellowStyle(), 'cell', [r, c+1]);
            end
        end
    end
end
function onUKTableSelect(src, event, fig)
    if isempty(event.Indices), return; end
    r = event.Indices(end, 1); c = event.Indices(end, 2);
    % Column 5 = SKLID (variable name), column 9 = Map Number in 9-col layout
    if c ~= 5, return; end
    varName  = src.Data{r, 5};
    mapNum   = src.Data{r, 9};   % col 9 = Map Number (was col 6 before expansion)
    if strcmp(mapNum, 'Not Found') || strcmp(mapNum, 'Empty'), return; end
    openGenericVarEditor(fig, varName, r);
end
function openGenericVarEditor(fig, varName, ukRowIdx)
    appData = fig.UserData; T = appData.T;
    
    % Recalculate correct ukRowIdx in appData.ukData to handle filtered views
    % ukTableData Cols: 1=UK, 2=Abbrev, 3=ID, 4=SKLID, 5=UL, 6=USP, 7=DSP, 8=Map Numbers
    realUkRowIdx = find(strcmp(appData.ukData(:, 4), varName), 1);
    if isempty(realUkRowIdx), realUkRowIdx = ukRowIdx; end % Fallback
    
    sCol2 = strtrim(string(T.Var2)); sCol1 = strtrim(string(T.Var1)); rIdx = find(strcmpi(sCol2, varName), 1); if isempty(rIdx), rIdx = find(strcmpi(sCol1, varName), 1); end
    if isempty(rIdx), return; end
    rowStart = rIdx; for r = rowStart:min(rowStart+10, height(T)), vals = str2double(string(table2cell(T(r, 3:end)))); if sum(~isnan(vals)) >= 1, rowStart = r; break; end, end
    rowEnd = rowStart; for r = rowStart:min(rowStart+50, height(T)), vals = str2double(string(table2cell(T(r, 3:end)))); if all(isnan(vals)), break; end, rowEnd = r; end
    maxCol = 3; firstRow = str2double(string(table2cell(T(rowStart, :)))); lastValid = find(~isnan(firstRow), 1, 'last'); if ~isempty(lastValid), maxCol = max(maxCol, lastValid); end
    rawData = str2double(string(table2cell(T(rowStart:rowEnd, 3:maxCol))));

    d = uifigure('Name', ['Edit: ' varName], 'Position', [200 200 600 400], 'WindowStyle', 'normal');
    d.CloseRequestFcn = @(src,e) closeGenericEditor(fig, src);
    d.WindowKeyPressFcn = @(src,e) onPopupKeyPress(src, e);
    
    appData.genericFig = d; fig.UserData = appData;

    gl = uigridlayout(d, [2, 1]); gl.RowHeight = {'1x', 60};

    % === CREATE POPUP TABLE ===
    tEd = uitable(gl, 'Data', rawData, 'ColumnEditable', true, ...
        'RowName', cellstr(string(0 : size(rawData, 1)-1)), ...
        'CellEditCallback', @(src,e) onPopupEdit(d, src, e), ...
        'CellSelectionCallback', @(src,e) onPopupSelect(d, e));

    cm = uicontextmenu(d);
    uimenu(cm, 'Text', 'Add Offset (+/-)...', 'MenuSelectedFcn', @(~,~) applyPopupMath(d, 'add'));
    uimenu(cm, 'Text', 'Multiply (*)...', 'MenuSelectedFcn', @(~,~) applyPopupMath(d, 'mult'));
    uimenu(cm, 'Text', 'Divide (/)...', 'MenuSelectedFcn', @(~,~) applyPopupMath(d, 'div'));
    uimenu(cm, "Text", "Copy", "Separator", "on", "MenuSelectedFcn", @(~,~) copySelection(tEd));
    uimenu(cm, "Text", "Paste", "MenuSelectedFcn", @(~,~) pasteSelection(tEd, @(src) onPopupPaste(d, src)));
    uimenu(cm, 'Text', 'Percentage (%)...', 'MenuSelectedFcn', @(~,~) applyPopupMath(d, 'percent'));
    tEd.ContextMenu = cm;

    % === APPLY HEATMAP STYLES ===
    applyHeatmapStyles(tEd);

    pnl = uipanel(gl); bl = uigridlayout(pnl, [1, 2]);
    uibutton(bl, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) delete(d));
    uibutton(bl, 'Text', 'Save', 'BackgroundColor', [1 0.8 0], 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~) saveGenericVar(fig, d, tEd, varName, realUkRowIdx, rowStart, maxCol));

    d.UserData = struct('history', {{}}, 'selection', [], 'tEd', tEd);
end
function closeGenericEditor(mainFig, src)
% Prompts if generic variable edits are unsaved.
    if ~isempty(src) && isvalid(src)
        hasPending = false;
        try
            h = src.UserData;
            hasPending = isstruct(h) && isfield(h,'history') && ~isempty(h.history);
        catch; end

        if hasPending
            sel = uiconfirm(src, ...
                ['You have unsaved changes in this variable editor.' newline ...
                 'Use the "Save" button to write changes back to the project.' newline newline ...
                 'Close anyway and DISCARD changes?'], ...
                'Unsaved Changes', ...
                'Options',       {'Discard & Close', 'Cancel'}, ...
                'DefaultOption', 'Cancel', ...
                'CancelOption',  'Cancel', ...
                'Icon',          'warning');
            if strcmp(sel, 'Cancel'), return; end
        end
    end

    if ~isempty(mainFig) && isvalid(mainFig)
        try
            ad = mainFig.UserData; ad.genericFig = gobjects(0); mainFig.UserData = ad;
        catch; end
    end
    if ~isempty(src) && isvalid(src), delete(src); end
end
function onPopupSelect(d, event)
    h = d.UserData; h.selection = event.Indices; d.UserData = h;
end
function onPopupEdit(d, src, event)
    if isempty(event.Indices), return; end
    oldData = src.Data;
    oldData(event.Indices(1), event.Indices(2)) = event.PreviousData;
    pushPopupHistory(d, oldData);
    applyHeatmapStyles(src);
    addStyle(src, getYellowStyle(), 'cell', event.Indices);
end
function onPopupKeyPress(d, event)
    if strcmp(event.Key, 'z') && ~isempty(event.Modifier) && any(strcmp(event.Modifier, 'control'))
        performPopupUndo(d);
    end
end
function pushPopupHistory(d, data)
    h = d.UserData;
    if ~isfield(h,'history'), h.history = {}; end
    h.history{end+1} = data;
    if length(h.history) > 20, h.history(1) = []; end
    d.UserData = h;
end
function performPopupUndo(d)
    h = d.UserData;
    if isempty(h.history), return; end
    lastData = h.history{end};
    h.history(end) = [];
    d.UserData = h;

    % Use stored handle directly instead of findobj (findobj scans all children — slow)
    if isfield(h,'tEd') && ~isempty(h.tEd) && isvalid(h.tEd)
        h.tEd.Data = lastData;
        applyHeatmapStyles(h.tEd);
    end
end
function applyPopupMath(d, op)
    h = d.UserData;
    % Use stored handle directly
    if ~isfield(h,'tEd') || isempty(h.tEd) || ~isvalid(h.tEd)
        return;
    end
    tEd = h.tEd;
    sel = h.selection;
    if isempty(sel), uialert(d, 'Select cells first.', 'Error'); return; end

    pushPopupHistory(d, tEd.Data);

    prompt = ""; def = "0";
    switch op
        case 'add', prompt = "Add Value:";
        case 'mult', prompt = "Multiply by:"; def="1";
        case 'div', prompt = "Divide by:"; def="1";
        case 'percent', prompt = "Percent Change:";
    end
    answer = inputdlg(prompt, 'Math', [1 40], {char(def)});
    if isempty(answer), return; end
    val = str2double(answer{1});
    if isnan(val), return; end

    data = tEd.Data;
    for i=1:size(sel,1)
        r = sel(i,1); c = sel(i,2);
        curr = data(r,c);
        if isnan(curr), continue; end
        switch op
            case 'add', curr = curr + val;
            case 'mult', curr = curr * val;
            case 'div', if val~=0, curr = curr / val; end
            case 'percent', curr = curr * (1 + val/100);
        end
        data(r,c) = curr;
    end
    tEd.Data = data;
    applyHeatmapStyles(tEd);
end
function applyHeatmapStyles(tTable)
    persistent parulaCache;   % Cache parula(64) once — avoids repeated colormap generation
    data = tTable.Data;
    if isempty(data), return; end
    removeStyle(tTable);

    % Flatten to numeric values
    flatData = data(:);
    if iscell(flatData)
        numMask  = cellfun(@isnumeric, flatData);
        filtered = flatData(numMask);
        if isempty(filtered), return; end
        flatData = cell2mat(filtered);
    end
    flatData = flatData(~isnan(flatData));
    uniqueVals = unique(flatData);
    if isempty(uniqueVals), return; end

    % Cap at 64 unique values to limit addStyle calls
    nColors = min(length(uniqueVals), 64);
    uniqueVals = uniqueVals(round(linspace(1, length(uniqueVals), nColors)));

    % Use persistent cache — build once per session
    if isempty(parulaCache) || size(parulaCache,1) < nColors
        parulaCache = min(parula(max(nColors,2)) + 0.2, 1);
    end
    colors = parulaCache(round(linspace(1, size(parulaCache,1), nColors)), :);

    for i = 1:nColors
        val = uniqueVals(i);
        color = colors(i, :);
        if iscell(data)
            mask = cellfun(@(x) isnumeric(x) && ~isnan(x) && x == val, data);
        else
            mask = (~isnan(data)) & (data == val);
        end
        [r, c] = find(mask);
        if ~isempty(r)
            addStyle(tTable, uistyle('BackgroundColor', color), 'cell', [r(:), c(:)]);
        end
    end
    drawnow limitrate;
end
function saveGenericVar(fig, popFig, tEd, varName, ukRowIdx, rowStart, maxCol)
    appData = fig.UserData; newData = tEd.Data;
    for r=1:size(newData,1), for c=1:size(newData,2), appData.T{rowStart+r-1, 2+c} = {newData(r,c)}; end, end
    
    valStr = char(strjoin(string(unique(newData(~isnan(newData))')), ', '));
    appData.ukData{ukRowIdx, 8} = valStr;  % col 8 = Map Numbers
    
    fig.UserData = appData; 
    
    if hasValidHandle(appData, 'ukFig')
        h = appData.ukFig.UserData;
        % Update fullDisplayData if it exists (for filtered view consistency)
        if isfield(h, 'fullDisplayData')
             % fullDisplayData col 9 = Map Numbers (newUK layout: UK,Abbrev,FSIT,ID,SKLID,UL,USP,DSP,MapNums)
             % Ensure h is treated as scalar if needed, but here we access struct fields.
             % If h is struct array, we can't easily update. But previous fix made it scalar.
             if isscalar(h)
                 h.fullDisplayData{ukRowIdx, 9} = valStr;
                 appData.ukFig.UserData = h;
             end
        end
        updateUKTableFilters(appData.ukFig, fig); 
    end
    delete(popFig);
end
function saveStatChanges(ukFig, mainFig)
    if strcmp(uiconfirm(ukFig, 'Overwrite original values?', 'Save', 'Options', {'Yes','Cancel'}), 'Cancel'), return; end
    h = ukFig.UserData; fullData = h.tStat.Data;
    appData = mainFig.UserData; appData.statRowNames = fullData(:,1);
    % Use str2double conversion so text/empty cells become NaN instead of crashing cell2mat
    numPart = fullData(:, 2:end);
    numData = zeros(size(numPart));
    for rr = 1:size(numPart,1)
        for cc = 1:size(numPart,2)
            v = numPart{rr,cc};
            if isnumeric(v), numData(rr,cc) = v;
            else, n = str2double(string(v)); if ~isnan(n), numData(rr,cc) = n; else, numData(rr,cc) = 0; end; end
        end
    end
    appData.statTabul = numData;
    appData.ukHistory = {};
    mainFig.UserData = appData;
    % Reset dirty flag — changes are now saved
    h.ukDirty = false; ukFig.UserData = h;
    logAction(ukFig, 'STAT Save', sprintf('%d rows', size(fullData,1)));
    updateUKTableFilters(ukFig, mainFig);
    uialert(ukFig, 'STAT_TABUL saved successfully.', 'Saved', 'Icon', 'success');
end
%% === TCC EDITOR LOGIC (V10.0 - Gold Buttons) ===
function openTCCEditor(fig)
    appData = fig.UserData;
    if isfield(appData, 'tccFig') && hasValidHandle(appData, 'tccFig')
        appData.tccFig.Visible = 'on'; figure(appData.tccFig); updateTCCEditor(fig); return;
    end

    d = uifigure('Name', 'TCC Editor', 'Position', [100 100 1000 600]);
    d.CloseRequestFcn = @(src,e) closeTCCEditor(fig, src);
    d.WindowKeyPressFcn = @(src,e) onTCCKeyPress(fig, e);

    appData.tccFig = d;
    appData.tccHistory = {};
    fig.UserData = appData;

    gl = uigridlayout(d, [2 1]); gl.RowHeight = {'1x', 50};
    tg = uitabgroup(gl, 'SelectionChangedFcn', @(~,~) onTCCTabChanged(fig));

    % GOLD BUTTON STYLE
    goldBtnStyle = {'BackgroundColor', [1 0.8 0], 'FontWeight', 'bold'};

    % TAB 1: CURVES
    tab1 = uitab(tg, 'Title', 'TCC Curves');
    gl1 = uigridlayout(tab1, [2 1]); gl1.RowHeight = {'1x', 45};
    tTCC = uitable(gl1, 'Data', [], 'ColumnName', {}, 'ColumnEditable', true, 'RowName', 'numbered', ...
        'CellEditCallback', @(src,e) onTCCEdit(fig, src,e, 'curves'), ...
        'CellSelectionCallback', @(src,e) onTCCSelect(fig, src, e));

    cm = uicontextmenu(d);
    uimenu(cm, 'Text', 'Add Offset (+/-)...', 'MenuSelectedFcn', @(~,~) applyTCCMath(fig, 'add'));
    uimenu(cm, 'Text', 'Multiply (*)...', 'MenuSelectedFcn', @(~,~) applyTCCMath(fig, 'mult'));
    uimenu(cm, 'Text', 'Divide (/)...', 'MenuSelectedFcn', @(~,~) applyTCCMath(fig, 'div'));
    uimenu(cm, 'Text', 'Percentage (%)...', 'MenuSelectedFcn', @(~,~) applyTCCMath(fig, 'percent'));
    uimenu(cm, "Text", "Copy", "Separator", "on", "MenuSelectedFcn", @(~,~) copySelection(tTCC));
    uimenu(cm, "Text", "Paste", "MenuSelectedFcn", @(~,~) pasteSelection(tTCC));
    tTCC.ContextMenu = cm;

    pnlC = uipanel(gl1);
    cLayout = uigridlayout(pnlC, [1 2]); cLayout.ColumnWidth = {200, '1x'}; cLayout.Padding = [5 5 5 5];
    uibutton(cLayout, 'Text', 'SAVE CHANGES', goldBtnStyle{:}, 'ButtonPushedFcn', @(~,~) saveTCCData(fig));

    % TAB 2: WT_ZUSTAND
    tab2 = uitab(tg, 'Title', 'WT_ZUSTAND');
    gl2 = uigridlayout(tab2, [2 1]); gl2.RowHeight = {'1x', 45};
    tZustand = uitable(gl2, 'Data', [], 'ColumnName', {'Map ID', 'TCC State'}, ...
        'ColumnEditable', true, 'ColumnWidth', {100, 100}, 'CellEditCallback', @(src,e) onTCCEdit(fig,src,e, 'zustand'));
    cmZ = uicontextmenu(d);
    uimenu(cmZ, "Text", "Copy", "MenuSelectedFcn", @(~,~) copySelection(tZustand));
    uimenu(cmZ, "Text", "Paste", "MenuSelectedFcn", @(~,~) pasteSelection(tZustand));
    tZustand.ContextMenu = cmZ;
    pnlZ = uipanel(gl2);
    zLayout = uigridlayout(pnlZ, [1 2]); zLayout.ColumnWidth = {200, '1x'}; zLayout.Padding = [5 5 5 5];
    uibutton(zLayout, 'Text', 'SAVE CHANGES', goldBtnStyle{:}, 'ButtonPushedFcn', @(~,~) saveZustand(fig));

    % TAB 3: WT_KWK_ZTAB
    tab3 = uitab(tg, 'Title', 'WT_KWK_ZTAB');
    gl3 = uigridlayout(tab3, [2 1]); gl3.RowHeight = {"1x", 45};
    tKWK = uitable(gl3, "Data", [], "ColumnEditable", true, "CellEditCallback", @(src,e) onTCCEdit(fig,src,e, "kwk"));
    cmK = uicontextmenu(d);
    uimenu(cmK, "Text", "Copy", "MenuSelectedFcn", @(~,~) copySelection(tKWK));
    uimenu(cmK, "Text", "Paste", "MenuSelectedFcn", @(~,~) pasteSelection(tKWK));
    tKWK.ContextMenu = cmK;
    pnlK = uipanel(gl3);
    kLayout = uigridlayout(pnlK, [1 2]); kLayout.ColumnWidth = {200, '1x'}; kLayout.Padding = [5 5 5 5];
    uibutton(kLayout, 'Text', 'SAVE CHANGES', goldBtnStyle{:}, 'ButtonPushedFcn', @(~,~) saveKWK(fig));

    % TAB 4: TURBINE RPM (V7.5.6) — literal duplicate of Edit Map A → Turbine RPM
    turbineColNames = {'Pedal %','1->2','2->3','3->4','4->5','5->6','6->7','7->8', ...
                      '2->1','3->2','4->3','5->4','6->5','7->6','8->7'};
    tab4 = uitab(tg, 'Title', 'Turbine RPM');
    gl4 = uigridlayout(tab4, [1 1]);
    tTurbine = uitable(gl4, 'Data', [], 'ColumnName', turbineColNames, ...
        'ColumnEditable', true, 'ColumnWidth', 'auto', ...
        'CellEditCallback',      @(src, event) onGenericTableEdit(fig, src, event, 'Turbine'), ...
        'CellSelectionCallback', @(src, event) onTableSelect(fig, src, event, 'Turbine'));
    cmT = uicontextmenu(d);
    uimenu(cmT, 'Text', 'Add Offset (+/-)...', 'MenuSelectedFcn', @(s,e) applyMath(fig, 'add'));
    uimenu(cmT, 'Text', 'Multiply (*)...',     'MenuSelectedFcn', @(s,e) applyMath(fig, 'mult'));
    uimenu(cmT, 'Text', 'Divide (/)...',       'MenuSelectedFcn', @(s,e) applyMath(fig, 'div'));
    uimenu(cmT, 'Text', 'Percentage (%)...',   'MenuSelectedFcn', @(s,e) applyMath(fig, 'percent'));
    uimenu(cmT, 'Text', 'Copy', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) copySelection(tTurbine));
    uimenu(cmT, 'Text', 'Paste', 'MenuSelectedFcn', @(~,~) pasteSelection(tTurbine, @(src) onGenericTablePaste(fig, src, 'Turbine')));
    tTurbine.ContextMenu = cmT;

    % Main Controls
    pnl = uipanel(gl);
    pnl.Layout.Row = 2; pnl.Layout.Column = 1;
    bl = uigridlayout(pnl, [1 3]); bl.ColumnWidth = {'1x', 150, '1x'};

    btnCancel = uibutton(bl, 'Text', 'Close / Cancel', 'ButtonPushedFcn', @(~,~) delete(d));
    btnCancel.Layout.Row = 1; btnCancel.Layout.Column = 2;

    d.UserData = struct('tTCC', tTCC, 'tZustand', tZustand, 'tKWK', tKWK, 'tTurbine', tTurbine, 'tabGroup', tg, 'activeMapStructs', struct('mapIdx', {}, 'colIdxInMap', {}), 'tccSelection', []);
    updateTCCEditor(fig);
    % Eagerly populate the Turbine tab so it has data on first open (V7.5.6)
    try, onTCCTabChanged(fig); catch; end
    try, refreshTableStyles(fig); catch; end
end

%% === GEAR RATIO DATA FUNCTIONS (Used by UK Table) ===
function gearRatioData = getGearRatioDataFromInputStruct(ui)
% Build gear ratio table from a userInputs struct (used for ref vehicle gear ratios)
    if ~isstruct(ui) || ~isfield(ui,'GearRatios') || isempty(ui.GearRatios)
        gearRatioData = {}; return;
    end
    gr  = ui.GearRatios;  nG = length(gr);
    dyn = 0; axle = 1;
    if isfield(ui,'DynamicCircumference'), dyn  = ui.DynamicCircumference; end
    if isfield(ui,'AxleRatio'),            axle = ui.AxleRatio;            end
    gearRatioData = cell(4, nG);
    for k = 1:nG
        gearRatioData{1,k} = k;
        gearRatioData{2,k} = gr(k);
        if dyn > 0 && axle > 0 && gr(k) > 0
            gearRatioData{3,k} = round((dyn * axle) / (gr(k) * 1000) * 60, 2);
            gearRatioData{4,k} = round((dyn * axle) / (gr(k) * 1000 * 1.609) * 60, 2);
        else
            gearRatioData{3,k} = 0; gearRatioData{4,k} = 0;
        end
    end
end

function gearData = getGearRatioDataFromUserInputs(fig)
    % Get gear ratio parameters from userInputs (the Verify Parameters data)
    appData = fig.UserData;
    
    if ~isfield(appData, 'userInputs')
        gearData = {};
        return;
    end
    
    ui = appData.userInputs;
    
    % Build gear ratio table from userInputs
    gearData = cell(0, 4);  % Parameter, Value, Unit, Description
    
    % Gear Ratios (1-8)
    if isfield(ui, 'GearRatios') && ~isempty(ui.GearRatios)
        gr = ui.GearRatios;
        for i = 1:min(length(gr), 8)
            gearData{end+1, 1} = sprintf('Gear %d Ratio', i);
            gearData{end, 2} = gr(i);
            gearData{end, 3} = '-';
            gearData{end, 4} = sprintf('Gear %d transmission ratio', i);
        end
    end
    
    % Axle Ratio
    if isfield(ui, 'AxleRatio')
        gearData{end+1, 1} = 'Axle Ratio';
        gearData{end, 2} = ui.AxleRatio;
        gearData{end, 3} = '-';
        gearData{end, 4} = 'Final drive (axle) ratio';
    end
    
    % Tire Radius (Dynamic Circumference)
    if isfield(ui, 'DynamicCircumference')
        gearData{end+1, 1} = 'Tire Radius';
        gearData{end, 2} = ui.DynamicCircumference;
        gearData{end, 3} = 'mm';
        gearData{end, 4} = 'Dynamic tire radius';
    end
    
    % Tire Circumference
    if isfield(ui, 'TireCircumference')
        gearData{end+1, 1} = 'Tire Circumference';
        gearData{end, 2} = ui.TireCircumference;
        gearData{end, 3} = 'mm';
        gearData{end, 4} = 'Tire rolling circumference';
    end
    
    % Low Range Ratio
    if isfield(ui, 'LowRangeRatio')
        gearData{end+1, 1} = 'Low Range Ratio';
        gearData{end, 2} = ui.LowRangeRatio;
        gearData{end, 3} = '-';
        gearData{end, 4} = 'Transfer case low range ratio';
    end
    
    % Idle RPM
    if isfield(ui, 'IdleRPM')
        gearData{end+1, 1} = 'Idle RPM';
        gearData{end, 2} = ui.IdleRPM;
        gearData{end, 3} = '1/min';
        gearData{end, 4} = 'Engine idle speed';
    end
    
    % Max RPM
    if isfield(ui, 'MaxRPM')
        gearData{end+1, 1} = 'Max RPM';
        gearData{end, 2} = ui.MaxRPM;
        gearData{end, 3} = '1/min';
        gearData{end, 4} = 'Engine maximum speed';
    end
end

function gearData = getGearRatioData(fig)
    % Wrapper function for backward compatibility
    gearData = getGearRatioDataFromUserInputs(fig);
end

function val = findCSVValue(T, varName)
    val = [];
    idx = find(contains(string(T.Var2), varName, 'IgnoreCase', true), 1);
    if isempty(idx)
        idx = find(contains(string(T.Var1), varName, 'IgnoreCase', true), 1);
    end
    if isempty(idx), return; end
    
    % Look for VALUE row after variable name
    for r = idx:min(idx+5, height(T))
        c1 = strtrim(string(T{r, 1}));
        if startsWith(c1, 'VALUE', 'IgnoreCase', true)
            vals = str2double(string(table2cell(T(r, 2:min(10, width(T))))));
            vv = vals(~isnan(vals));
            if ~isempty(vv)
                val = vv(1);
                return;
            end
        end
    end
end

function updateTCCEditor(fig)
    appData = fig.UserData;
    if ~isfield(appData, 'tccFig') || ~hasValidHandle(appData, 'tccFig') || isempty(appData.tccFig.UserData), return; end
    % Refresh the Turbine RPM tab whenever Map A changes (V7.5.6)
    try, onTCCTabChanged(fig); catch; end
    if ~isfield(appData,'currentMapName') || isempty(appData.currentMapName), return; end

    % Use ref TCC data when the ACTIVE map (workingCopy) is a ref map
    isWCRef   = ~isempty(appData.workingCopy) && isfield(appData.workingCopy,'isRef') ...
                && appData.workingCopy.isRef;
    isRefMode = isfield(appData,'isRefMode') && appData.isRefMode && isfield(appData,'refVehicle');
    if isWCRef && isRefMode
        if isfield(appData.refVehicle,'wtZustand'), appData.wtZustand = appData.refVehicle.wtZustand; end
        if isfield(appData.refVehicle,'kwkData'),   appData.kwkData   = appData.refVehicle.kwkData;   end
        if isfield(appData.refVehicle,'nwkMaps'),   appData.nwkMaps   = appData.refVehicle.nwkMaps;   end
    end

    persistent tccGreen_;
    if isempty(tccGreen_), tccGreen_ = uistyle('BackgroundColor',[0.6 1 0.6],'FontWeight','bold'); end

    h = appData.tccFig.UserData; tTCC = h.tTCC; tZustand = h.tZustand; tKWK = h.tKWK;

    tTCC.Data = []; tTCC.ColumnName = {};

    activeState = -1; activeMapID = -999;

    if ~isempty(appData.wtZustand)
        zData = appData.wtZustand';
        tZustand.Data = zData; tZustand.RowName = string(0 : size(zData,1)-1);
        appData.tccShadowData.zustand = zData; removeStyle(tZustand);
        mapName = appData.currentMapName; mapNumStr = regexp(mapName, 'SKL_GKF_(\d+)', 'tokens');
        if ~isempty(mapNumStr)
            activeMapID = str2double(mapNumStr{1}{1});
            idx = find(zData(:, 1) == activeMapID, 1);
            if ~isempty(idx), activeState = zData(idx, 2); addStyle(tZustand, tccGreen_, 'row', idx); scroll(tZustand, 'row', idx); end
        end
    else, tZustand.Data = []; end

    if ~isempty(appData.kwkData)
        tKWK.Data = appData.kwkData; tKWK.RowName = string(0 : size(appData.kwkData,1)-1);
        appData.tccShadowData.kwk = appData.kwkData; removeStyle(tKWK);
        if activeState ~= -1
            rowIndex = activeState + 1;
            if rowIndex >= 1 && rowIndex <= size(appData.kwkData, 1), addStyle(tKWK, tccGreen_, 'row', rowIndex); scroll(tKWK, 'row', rowIndex); end
        end
    else, tKWK.Data = []; end

    % Populate TCC Curves
    if activeState == -1, tTCC.Data = {}; tTCC.ColumnName = {'State Not Found / No Map'}; appData.tccFig.Name = 'TCC Editor - State Not Found'; return; end
    appData.tccFig.Name = ['TCC Editor - Map ' num2str(activeMapID) ' (State ' num2str(activeState) ')'];

    idList = []; if ~isempty(appData.kwkData), rIdx = activeState + 1; if rIdx <= size(appData.kwkData, 1), idList = appData.kwkData(rIdx, :); end, end

    % FIX 1: Filter for UNIQUE IDs to prevent duplicate columns
    idList = unique(idList);
    % FIX 2: Remove '0' (No Curve)
    idList(idList == 0) = [];

    combinedData = []; colNames = {'Pedal %'}; hasYAxis = false;
    % Initialize as typed struct array — avoids "Conversion to double from struct" error
    activeMapStructs = struct('mapIdx', {}, 'colIdxInMap', {});

    for i = 1:length(idList)
        idVal = idList(i);
        prefix = string(idVal) + "_";
        for m = 1:length(appData.nwkMaps)
            map = appData.nwkMaps(m); headers = string(map.headers);
            matchIdx = find(startsWith(headers, prefix, 'IgnoreCase', true));
            if ~isempty(matchIdx)
                colsData = map.data(:, matchIdx); colsHead = headers(matchIdx);

                % --- FIX START: Dynamic Y-Axis Handling ---
                if ~hasYAxis
                    combinedData = map.yAxis; hasYAxis = true;
                end

                if size(colsData,1) > size(combinedData,1), combinedData = [combinedData; nan(size(colsData,1)-size(combinedData,1), size(combinedData,2))];
                elseif size(colsData,1) < size(combinedData,1), colsData = [colsData; nan(size(combinedData,1)-size(colsData,1), size(colsData,2))]; end
                combinedData = [combinedData, colsData]; colNames = [colNames, cellstr(colsHead)];
                for c = 1:length(matchIdx)
                    activeMapStructs(end+1) = struct('mapIdx', m, 'colIdxInMap', matchIdx(c)); %#ok<AGROW>
                end

                % Break here to stop searching other maps for the same ID
                break;
            end
        end
    end
    tTCC.Data = combinedData; tTCC.ColumnName = colNames;
    h.activeMapStructs = activeMapStructs; appData.tccFig.UserData = h;
    appData.tccShadowData.curves = combinedData; fig.UserData = appData;
    removeStyle(tTCC);
    applyTCCPedalStyles(tTCC);
    drawnow limitrate; % Force UI Refresh
end
%% === TCC INTERACTION FUNCTIONS (MISSING FROM PREVIOUS CODE) ===
function onTCCSelect(fig, src, event)
    if isempty(event.Indices), return; end
    appData = fig.UserData;
    if ~hasValidHandle(appData, 'tccFig'), return; end
    h = appData.tccFig.UserData;
    h.tccSelection = event.Indices;
    appData.tccFig.UserData = h;
end
function onTCCEdit(fig, src, event, type)
    if isempty(event.Indices), return; end  % guard: spurious callback
    pushTCCHistory(fig);
    appData = fig.UserData;
    if strcmp(type, 'curves'),   appData.tccShadowData.curves  = src.Data;
    elseif strcmp(type, 'zustand'), appData.tccShadowData.zustand = src.Data;
    elseif strcmp(type, 'kwk'),  appData.tccShadowData.kwk     = src.Data;
    end
    fig.UserData = appData;
    addStyle(src, getYellowStyle(), 'cell', event.Indices);
    if strcmp(type, 'curves'), applyTCCPedalStyles(src); end
end
function onTCCKeyPress(fig, event)
    if strcmp(event.Key, 'z') && ~isempty(event.Modifier) && any(strcmp(event.Modifier, 'control'))
        performTCCUndo(fig);
    end
end

function applyTCCPedalStyles(tTCC)
% Validate column 1 (Pedal %) of the TCC curves table.
% Red   = duplicate value (exact repeat — most critical)
% Orange = decreasing value (non-monotonic)
% Applied ON TOP of any existing yellow edit highlights.
    persistent tccOrange_ tccRed_;
    if isempty(tccOrange_)
        tccOrange_ = uistyle('BackgroundColor',[1 0.5 0],'FontWeight','bold','FontColor','white');
        tccRed_    = uistyle('BackgroundColor',[1 0 0],'FontWeight','bold','FontColor','white');
    end
    if ~isvalid(tTCC), return; end
    d = tTCC.Data;
    if isempty(d) || size(d,1) < 2 || size(d,2) < 1, return; end
    try
        % Extract column 1 as numeric
        col1 = d(:,1);
        if iscell(col1)
            pedalVals = zeros(size(col1));
            for idxPedal=1:numel(col1)
                tmpP = col1{idxPedal};
                if isnumeric(tmpP), pedalVals(idxPedal) = double(tmpP); else, pedalVals(idxPedal) = str2double(string(tmpP)); end
            end
        else
            pedalVals = double(col1);
        end

        pd = diff(pedalVals);

        % Orange: strictly decreasing
        decrRows = find(pd < 0);
        orangeRows = unique([decrRows; decrRows+1]);

        % Red: exact duplicate
        dupeRows = find(pd == 0);
        redRows = unique([dupeRows; dupeRows+1]);

        % Apply styles (orange first, red overwrites)
        if ~isempty(orangeRows)
            addStyle(tTCC, tccOrange_, 'cell', [orangeRows, ones(numel(orangeRows),1)]);
        end
        if ~isempty(redRows)
            addStyle(tTCC, tccRed_, 'cell', [redRows, ones(numel(redRows),1)]);
        end
    catch; end
end
function applyTCCMath(fig, op)
    appData = fig.UserData;
    if ~hasValidHandle(appData, 'tccFig'), return; end
    h = appData.tccFig.UserData;
    tTCC = h.tTCC;
    sel = h.tccSelection;
    if isempty(sel), uialert(appData.tccFig, 'Select cells first.', 'Error'); return; end

    pushTCCHistory(fig);

    prompt = ""; def = "0";
    switch op
        case 'add', prompt = "Add Value:";
        case 'mult', prompt = "Multiply by:"; def="1";
        case 'div', prompt = "Divide by:"; def="1";
        case 'percent', prompt = "Percent Change:";
    end
    answer = inputdlg(prompt, 'Math', [1 40], {char(def)});
    if isempty(answer), return; end
    val = str2double(answer{1});
    if isnan(val), return; end

    data = tTCC.Data;
    for i=1:size(sel,1)
        r = sel(i,1); c = sel(i,2);
        curr = data(r,c);
        if isnan(curr), continue; end
        switch op
            case 'add', curr = curr + val;
            case 'mult', curr = curr * val;
            case 'div', if val~=0, curr = curr / val; end
            case 'percent', curr = curr * (1 + val/100);
        end
        data(r,c) = curr;
    end
    tTCC.Data = data;
    % Update shadow
    appData = fig.UserData;
    appData.tccShadowData.curves = data;
    fig.UserData = appData;
end
function saveTCCData(fig)
    appData = fig.UserData;
    if ~hasValidHandle(appData, 'tccFig'), return; end
    h = appData.tccFig.UserData;
    if strcmp(uiconfirm(appData.tccFig, 'Overwrite original values?', 'Save', 'Options', {'Yes','Cancel'}), 'Cancel'), return; end
    appData = fig.UserData;
    appData.tccHistory = {};

    if isempty(h.activeMapStructs), return; end

    % Data in table (excluding col 1 usually is Y-Axis, but checking construction)
    % In updateTCCEditor: combinedData = [map.yAxis, colsData]
    % So Col 1 is Y-Axis. Data cols start at 2.

    tData = h.tTCC.Data;
    mapStructs = h.activeMapStructs;

    % Loop through mapStructs (which correspond to columns 2, 3, 4... of tData)
    for i = 1:length(mapStructs)
        ms = mapStructs(i);
        tableColIdx = i + 1; % Skip Y-Axis column

        if tableColIdx > size(tData, 2), break; end

        newColData = tData(:, tableColIdx);

        % Update the specific NWK Map in memory
        % Check sizes - if edited table is longer (padded), trim it back
        origLen = size(appData.nwkMaps(ms.mapIdx).data, 1);
        if length(newColData) > origLen
            newColData = newColData(1:origLen);
        elseif length(newColData) < origLen
            % Should not happen if logic is correct, but pad if needed
            newColData = [newColData; nan(origLen-length(newColData), 1)];
        end

        appData.nwkMaps(ms.mapIdx).data(:, ms.colIdxInMap) = newColData;
    end

    fig.UserData = appData;
    logAction(fig, 'TCC Save', sprintf('%d curves', length(mapStructs)));
    try; removeStyle(fig.UserData.tccFig.UserData.tTCC); catch; end
    try; applyTCCPedalStyles(fig.UserData.tccFig.UserData.tTCC); catch; end
    try; uialert(fig.UserData.tccFig, 'TCC Curves Saved to Memory.', 'Success'); catch; end
end
function saveZustand(fig)
    appData = fig.UserData;
    if ~hasValidHandle(appData, 'tccFig'), return; end
    if ~isfield(appData,'tccShadowData') || ~isfield(appData.tccShadowData,'zustand') || isempty(appData.tccShadowData.zustand)
        uialert(appData.tccFig,'No Zustand data to save. Edit the table first.','Save','Icon','warning'); return;
    end
    if strcmp(uiconfirm(appData.tccFig, 'Overwrite original values?', 'Save', 'Options', {'Yes','Cancel'}), 'Cancel'), return; end
    appData = fig.UserData;
    appData.tccHistory = {};
    newData = appData.tccShadowData.zustand;
    appData.wtZustand = newData';
    fig.UserData = appData;
    try; removeStyle(fig.UserData.tccFig.UserData.tZustand); catch; end
    uialert(fig.UserData.tccFig, 'Zustand Saved to Memory.', 'Success');
    updateTCCEditor(fig);
end
function saveKWK(fig)
    appData = fig.UserData;
    if ~hasValidHandle(appData, 'tccFig'), return; end
    if ~isfield(appData,'tccShadowData') || ~isfield(appData.tccShadowData,'kwk') || isempty(appData.tccShadowData.kwk)
        uialert(appData.tccFig,'No KWK data to save. Edit the table first.','Save','Icon','warning'); return;
    end
    if strcmp(uiconfirm(appData.tccFig, 'Overwrite original values?', 'Save', 'Options', {'Yes','Cancel'}), 'Cancel'), return; end
    appData = fig.UserData;
    appData.tccHistory = {};
    newData = appData.tccShadowData.kwk;
    appData.kwkData = newData;
    fig.UserData = appData;
    try; removeStyle(fig.UserData.tccFig.UserData.tKWK); catch; end
    uialert(fig.UserData.tccFig, 'KWK Table Saved to Memory.', 'Success');
    updateTCCEditor(fig);
end
function closeTCCEditor(mainFig, tccFigSrc)
% Prompts if TCC edits are unsaved, then clears appData.tccFig and deletes.
    if ~isempty(tccFigSrc) && isvalid(tccFigSrc)
        % Check if there is unsaved TCC edit history
        hasPending = false;
        if ~isempty(mainFig) && isvalid(mainFig)
            try
                ad = mainFig.UserData;
                hasPending = isfield(ad,'tccHistory') && ~isempty(ad.tccHistory);
            catch; end
        end

        if hasPending
            sel = uiconfirm(tccFigSrc, ...
                ['You have unsaved changes in the TCC Editor.' newline newline ...
                 'Use the gold "SAVE CHANGES" buttons in each tab to save TCC Curves, ' ...
                 'WT_ZUSTAND, and WT_KWK_ZTAB.' newline newline ...
                 'Close anyway and DISCARD unsaved changes?'], ...
                'Unsaved TCC Changes', ...
                'Options',       {'Discard & Close', 'Cancel'}, ...
                'DefaultOption', 'Cancel', ...
                'CancelOption',  'Cancel', ...
                'Icon',          'warning');
            if strcmp(sel, 'Cancel'), return; end
        end
    end

    if ~isempty(mainFig) && isvalid(mainFig)
        try
            ad = mainFig.UserData;
            ad.tccFig     = gobjects(0);
            ad.tccHistory = {};   % clear history on close
            mainFig.UserData = ad;
        catch; end
    end
    if ~isempty(tccFigSrc) && isvalid(tccFigSrc), delete(tccFigSrc); end
end

function pushTCCHistory(fig)
    appData = fig.UserData;
    if ~isfield(appData, 'tccShadowData'), return; end
    if ~isfield(appData, 'tccHistory'), appData.tccHistory = {}; end
    appData.tccHistory{end+1} = appData.tccShadowData;
    if length(appData.tccHistory) > 20, appData.tccHistory(1) = []; end
    fig.UserData = appData;
end
function performTCCUndo(fig)
    appData = fig.UserData;
    if ~isfield(appData,'tccHistory') || isempty(appData.tccHistory), return; end
    lastState = appData.tccHistory{end};
    appData.tccHistory(end) = [];
    appData.tccShadowData = lastState;
    fig.UserData = appData;

    h = appData.tccFig.UserData;

    % Restore Curves & Highlight Diff
    if ~isempty(lastState.curves)
        h.tTCC.Data = lastState.curves;
        removeStyle(h.tTCC);
        % Reconstruct Saved Data View
        if ~isempty(h.activeMapStructs)
            savedView = []; hasY = false;
            for i = 1:length(h.activeMapStructs)
                ms = h.activeMapStructs(i);
                map = appData.nwkMaps(ms.mapIdx);
                if ~hasY, savedView = map.yAxis; hasY = true; end
                col = map.data(:, ms.colIdxInMap);
                if size(col,1) > size(savedView,1), savedView = [savedView; nan(size(col,1)-size(savedView,1), size(savedView,2))];
                elseif size(col,1) < size(savedView,1), col = [col; nan(size(savedView,1)-size(col,1), size(col,2))]; end
                savedView = [savedView, col];
            end
            % Compare
            currData = lastState.curves;
            if size(currData, 1) == size(savedView, 1) && size(currData, 2) == size(savedView, 2)
                % Skip Y-Axis (Col 1)
                diffMask = (currData(:, 2:end) ~= savedView(:, 2:end)) & ~(isnan(currData(:, 2:end)) & isnan(savedView(:, 2:end)));
                [r, c] = find(diffMask);
                if ~isempty(r)
                    addStyle(h.tTCC, getYellowStyle(), 'cell', [r, c+1]);
                end
            end
        end
        % Apply pedal % validation on col 1
        applyTCCPedalStyles(h.tTCC);
    end

    % Restore Zustand & Highlight Diff
    if ~isempty(lastState.zustand)
        h.tZustand.Data = lastState.zustand;
        removeStyle(h.tZustand);
        savedData = appData.wtZustand'; % Transposed in UI
        currData = lastState.zustand;
        if size(savedData, 1) == size(currData, 1) && size(savedData, 2) == size(currData, 2)
             diffMask = (savedData ~= currData) & ~(isnan(savedData) & isnan(currData));
             [r, c] = find(diffMask);
             if ~isempty(r)
                 addStyle(h.tZustand, getYellowStyle(), 'cell', [r, c]);
             end
        end
    end

    % Restore KWK & Highlight Diff
    if ~isempty(lastState.kwk)
        h.tKWK.Data = lastState.kwk;
        removeStyle(h.tKWK);
        savedData = appData.kwkData;
        currData = lastState.kwk;
        if size(savedData, 1) == size(currData, 1) && size(savedData, 2) == size(currData, 2)
             diffMask = (savedData ~= currData) & ~(isnan(savedData) & isnan(currData));
             [r, c] = find(diffMask);
             if ~isempty(r)
                 addStyle(h.tKWK, getYellowStyle(), 'cell', [r, c]);
             end
        end
    end
end
%% === HELPER: GENERIC EXTRACTOR WITH LOC ===
function [data, rowStart] = extractNumericBlockWithLoc(T, keyword)
    data = []; rowStart = 0;
    idx = find(contains(T.Var2, keyword, 'IgnoreCase', true), 1);
    if isempty(idx), return; end
    rowStart = idx + 1; found = false;
    for r = rowStart:min(rowStart+10, height(T))
        vals = str2double(string(table2cell(T(r, 3:end))));
        if sum(~isnan(vals)) > 2, rowStart = r; found = true; break; end
    end
    if ~found, rowStart = 0; return; end
    rowEnd = rowStart;
    for r = rowStart:min(rowStart+150, height(T))
        vals = str2double(string(table2cell(T(r, 3:end))));
        if sum(~isnan(vals)) < 1, break; end   % <1 = fully empty row only
        rowEnd = r;
    end
    firstRow = str2double(string(table2cell(T(rowStart, :))));
    lastValid = find(~isnan(firstRow), 1, 'last'); maxCol = max(3, lastValid);
    data = str2double(string(table2cell(T(rowStart:rowEnd, 3:maxCol))));
    data(isnan(data)) = 0;
end
%% === HELPER: GENERIC EXTRACTOR (Simple) ===
function data = extractNumericBlock(T, keyword)
    [data, ~] = extractNumericBlockWithLoc(T, keyword);
end
%% === UPDATE CONTEXT PANEL ===
function updateContextPanel(fig)
    appData = fig.UserData;
    if ~hasValidHandle(appData, 'contextLabel'), return; end

    % ── PERFORMANCE: skip rebuild if inputs haven't changed since last call ─
    persistent lastSig_;
    h = appData.handles;
    sig = sprintf('%s|%s|%d|%d|%d', char(string(h.dd1.Value)), char(string(h.dd2.Value)), ...
        h.cb1.Value*1, h.cb2.Value*1, ...
        ~isempty(appData.workingCopy) && isfield(appData.workingCopy,'isRef') && appData.workingCopy.isRef);
    if ~isempty(lastSig_) && strcmp(sig, lastSig_)
        % Inputs unchanged — context label is already correct, skip the 250-line rebuild
        return;
    end
    lastSig_ = sig;

    foundSklid = "";   % first low-range SKLID found for Map A (used for notification)

    function txt = getMapInfo(mapName)
        if isempty(mapName) || mapName == "", txt = "None Selected"; return; end
        mapNumStr = regexp(mapName, 'SKL_GKF_(\d+)', 'tokens');
        if isempty(mapNumStr), txt = mapName; return; end
        mapNum = str2double(mapNumStr{1}{1});
        modeTxt = "Not Defined"; colorHex = "gray"; slopeTxt = "";
        ukMatches = {};   % Nx4 cell: {ukName, sklid, idNum, idColor} — one row per match
        if mapNum >= 0 && mapNum <= 24
            % ── Fixed map block (0-24) ───────────────────────────────────────
            if mapNum <= 4,      slopeTxt = "Downhill";
            elseif mapNum <= 9,  slopeTxt = "Flat";
            else,                slopeTxt = "Uphill"; end
            if     ismember(mapNum, [1 6 11 16 21]), modeTxt = "Normal ADT";       colorHex = "green";
            elseif ismember(mapNum, [3 8 13 18 23]), modeTxt = "Sport/Track ADT";  colorHex = "red";
            elseif ismember(mapNum, [0 5 10 15 20]), modeTxt = "Normal";            colorHex = "green";
            elseif ismember(mapNum, [2 7 12 17 22]), modeTxt = "Sport";             colorHex = "red";
            elseif ismember(mapNum, [4 9 14 19 24]), modeTxt = "Track/Baja";        colorHex = "blue"; end
        elseif mapNum >= 25
            % ── Dynamic map block (25-119): collect ALL matching UK rows ──────
            modeTxt = "Not Defined"; colorHex = "gray";
            if isfield(appData, 'ukData') && ~isempty(appData.ukData)
                ukD = appData.ukData;
                if size(ukD,2) < 8, ukD = ukEnsureULUSPDSP(ukD); appData.ukData = ukD; fig.UserData = appData; end
                for ukRow = 1:size(ukD, 1)
                    if size(ukD,2) < 8, continue; end
                    mapNumsStr = string(ukD{ukRow, 8});
                    if mapNumsStr == "Not Found" || mapNumsStr == "Empty", continue; end
                    toks2 = strsplit(mapNumsStr, ',');
                    if any(str2double(strtrim(toks2)) == mapNum)
                        sk = string(ukD{ukRow, 4});   % SKLID
                        nm = string(ukD{ukRow, 1});   % UK name
                        rawID2 = ukD{ukRow, 3};       % ID
                        idNum2 = str2double(string(rawID2));
                        if isnan(idNum2), idNum2 = NaN; end
                        % ID colour: green = in STAT_TABUL, yellow = not in use
                        if ~isnan(idNum2) && isfield(appData,'statTabul') && ...
                                ~isempty(appData.statTabul) && ismember(idNum2, appData.statTabul)
                            ic = "green";
                        else
                            ic = "#B8860B";
                        end
                        ukMatches(end+1,:) = {nm, sk, idNum2, ic}; %#ok<AGROW>
                        if foundSklid == "", foundSklid = sk; end  % track first low-range SKLID for notification
                    end
                end
                if ~isempty(ukMatches)
                    modeTxt  = ukMatches{1,2};  % first SKLID as primary
                    colorHex = "blue";
                end
            end
        end
        if isempty(appData.wtZustand)
            tccVal = "Table Missing"; tccColor = "red";
        else
            tccVal = "N/A"; tccColor = "black";
            if size(appData.wtZustand, 1) >= 2
                row1_ids = appData.wtZustand(1, :); idx = find(row1_ids == mapNum, 1);
                if ~isempty(idx)
                    stateVal = appData.wtZustand(2, idx);
                    if isfield(appData, 'kwkData') && ~isempty(appData.kwkData)
                        kwkRow = stateVal + 1;
                        if kwkRow >= 1 && kwkRow <= size(appData.kwkData, 1)
                            rowVals = appData.kwkData(kwkRow, :);
                            if length(rowVals) > 8, rowVals = rowVals(1:8); end
                            tccVal = strjoin(string(rowVals), ', ');
                            tccColor = "blue";
                        else
                            tccVal = "KWK Index Error"; tccColor = "red";
                        end
                    else
                        tccVal = num2str(stateVal); tccColor = "blue";
                    end
                end
            end
        end

        % ── Build HTML display ────────────────────────────────────────────────
        % Line 1: Map number | mode/slopeTxt | TCC
        if mapNum >= 0 && mapNum <= 24
            txt = sprintf('<font size="3"><b>Map %d: %s | <font color="%s">%s</font> | TCC: <font color="%s">%s</font></b></font>', ...
                mapNum, slopeTxt, colorHex, modeTxt, tccColor, tccVal);
        elseif ~isempty(ukMatches)
            % Header line: Map # + TCC
            hdrLine = sprintf('<font size="3"><b>Map %d: | TCC: <font color="%s">%s</font></b></font>', ...
                mapNum, tccColor, tccVal);

            % Group matches by UK name so it only appears once per group.
            % Build ordered list of unique UK names (preserve order of first occurrence).
            seenNames = {};
            for ei = 1:size(ukMatches,1)
                nm = char(ukMatches{ei,1});
                if ~any(strcmp(seenNames, nm)), seenNames{end+1} = nm; end %#ok<AGROW>
            end

            groupLines = '';
            for gi = 1:length(seenNames)
                gName = seenNames{gi};
                % Collect all SKLIDs for this UK name
                skParts = '';
                for ei = 1:size(ukMatches,1)
                    if ~strcmp(char(ukMatches{ei,1}), gName), continue; end
                    eSk = char(ukMatches{ei,2});
                    eID = ukMatches{ei,3};
                    eIC = char(ukMatches{ei,4});
                    if ~isnan(eID)
                        skParts = [skParts, sprintf( ...
                            '&nbsp;<font color="blue">%s</font>&nbsp;<font color="%s"><b>[%d]</b></font>&nbsp;·', ...
                            eSk, eIC, eID)]; %#ok<AGROW>
                    else
                        skParts = [skParts, sprintf( ...
                            '&nbsp;<font color="blue">%s</font>&nbsp;·', eSk)]; %#ok<AGROW>
                    end
                end
                % Strip trailing ·
                if ~isempty(skParts) && (skParts(end) == 183 || skParts(end) == char(183))  % strip trailing ·
                    skParts = skParts(1:end-1);
                end
                % Replace spaces with &nbsp; so HTML never wraps inside the UK name
                gNameHtml = strrep(gName, ' ', '&nbsp;');
                groupLines = [groupLines, sprintf( ...
                    '<br><font color="purple"><b>%s:</b></font>%s', ...
                    gNameHtml, skParts)]; %#ok<AGROW>
            end
            txt = [hdrLine, groupLines];
        else
            % No match found
            txt = sprintf('<font size="3"><b>Map %d: <font color="gray">Not Defined</font> | TCC: <font color="%s">%s</font></b></font>', ...
                mapNum, tccColor, tccVal);
        end
    end

    % ── Build display for Map A (dd1) and Map B / Ref Map (dd2) ─────────────
    % Map A: if it's a [REF] map (after swap), use ref vehicle data
    mapA_name = string(appData.handles.dd1.Value);
    isRefA = startsWith(mapA_name,'[REF]') && isfield(appData,'isRefMode') && ...
             appData.isRefMode && isfield(appData,'refVehicle');
    if isRefA
        saved_ukData_A   = appData.ukData;
        saved_stat_A     = appData.statTabul;
        saved_wtz_A      = appData.wtZustand;
        saved_kwk_A      = appData.kwkData;
        saved_nwk_A      = appData.nwkMaps;
        if isfield(appData.refVehicle,'ukData'),    appData.ukData    = appData.refVehicle.ukData;    end
        if isfield(appData.refVehicle,'statTabul'), appData.statTabul = appData.refVehicle.statTabul; end
        if isfield(appData.refVehicle,'wtZustand'), appData.wtZustand = appData.refVehicle.wtZustand; end
        if isfield(appData.refVehicle,'kwkData'),   appData.kwkData   = appData.refVehicle.kwkData;   end
        if isfield(appData.refVehicle,'nwkMaps'),   appData.nwkMaps   = appData.refVehicle.nwkMaps;   end
    end
    foundSklid = "";
    infoA = getMapInfo(mapA_name);
    sklidA = foundSklid;
    if isRefA
        appData.ukData    = saved_ukData_A;
        appData.statTabul = saved_stat_A;
        appData.wtZustand = saved_wtz_A;
        appData.kwkData   = saved_kwk_A;
        appData.nwkMaps   = saved_nwk_A;
    end

    % For Map B: if it is a [REF] map and ref mode is ON, temporarily swap
    % appData data sources so getMapInfo reads from the reference vehicle.
    mapB_name = string(appData.handles.dd2.Value);
    isRefB = startsWith(mapB_name,'[REF]') && isfield(appData,'isRefMode') && ...
             appData.isRefMode && isfield(appData,'refVehicle');
    if isRefB
        % Swap in reference vehicle data for getMapInfo
        saved_ukData   = appData.ukData;
        saved_stat     = appData.statTabul;
        saved_wtz      = appData.wtZustand;
        saved_kwk      = appData.kwkData;
        saved_nwk      = appData.nwkMaps;
        if isfield(appData.refVehicle,'ukData'),    appData.ukData    = appData.refVehicle.ukData;    end
        if isfield(appData.refVehicle,'statTabul'), appData.statTabul = appData.refVehicle.statTabul; end
        if isfield(appData.refVehicle,'wtZustand'), appData.wtZustand = appData.refVehicle.wtZustand; end
        if isfield(appData.refVehicle,'kwkData'),   appData.kwkData   = appData.refVehicle.kwkData;   end
        if isfield(appData.refVehicle,'nwkMaps'),   appData.nwkMaps   = appData.refVehicle.nwkMaps;   end
    end
    foundSklid = "";
    infoB = getMapInfo(mapB_name);
    if isRefB
        % Restore working file data
        appData.ukData    = saved_ukData;
        appData.statTabul = saved_stat;
        appData.wtZustand = saved_wtz;
        appData.kwkData   = saved_kwk;
        appData.nwkMaps   = saved_nwk;
    end

    appData.contextLabel.Text = sprintf('%s<br><br>%s', infoA, infoB);

    % ── 4Lo safety: reset 4Lo ONLY when map changes, then notify if needed ─────
    % Detection: compare current dd1 value to last known map (appData.lastMapA).
    % This prevents the reset from firing when the user merely ticks the checkbox
    % (which also triggers updateContextPanel via updatePlot).
    % Keywords (case-insensitive): sklidlow | uklow | ukrck
    if isfield(appData,'handles') && isfield(appData.handles,'cb4Lo') && isvalid(appData.handles.cb4Lo)
        loKW     = {'sklidlow', 'uklow', 'ukrck'};
        currentMapA = string(appData.handles.dd1.Value);
        lastMapA    = "";
        if isfield(appData,'lastMapA'), lastMapA = string(appData.lastMapA); end
        mapChanged  = (currentMapA ~= lastMapA);

        if mapChanged
            % ── Step 1: Turn 4Lo OFF whenever the selected map changes ────────
            appData.lastMapA = currentMapA;   % record new map before any updatePlot
            if appData.handles.cb4Lo.Value
                appData.handles.cb4Lo.Value = false;
                fig.UserData = appData;
                updatePlot(fig);              % re-render with 4Lo off
                appData = fig.UserData;       % re-read after updatePlot modifies it
            else
                fig.UserData = appData;       % save lastMapA even if 4Lo was already off
            end

            % ── Step 2: Check if new Map A has a low-range SKLID ─────────────
            matchedLoSklid = "";
            if any(cellfun(@(k) contains(char(sklidA), k, 'IgnoreCase', true), loKW))
                matchedLoSklid = sklidA;
            end
            if matchedLoSklid == "" && isfield(appData,'ukData') && ~isempty(appData.ukData)
                mapNS = regexp(currentMapA, 'SKL_GKF_(\d+)', 'tokens');
                if ~isempty(mapNS)
                    mnA  = str2double(mapNS{1}{1});
                    ukD2 = appData.ukData;
                    if size(ukD2,2) < 8, ukD2 = ukEnsureULUSPDSP(ukD2); appData.ukData = ukD2; fig.UserData = appData; end
                    for ukR2 = 1:size(ukD2,1)
                        if size(ukD2,2) < 8, break; end
                        mns2 = string(ukD2{ukR2,8});
                        if mns2=="Not Found" || mns2=="Empty", continue; end
                        if any(str2double(strtrim(strsplit(mns2,','))) == mnA)
                            sk2str = char(ukD2{ukR2,4});
                            if any(cellfun(@(k) contains(sk2str, k, 'IgnoreCase', true), loKW))
                                matchedLoSklid = string(sk2str);
                                break;
                            end
                        end
                    end
                end
            end

            % ── Step 3: Notify user only if this map belongs to 4Lo ──────────
            if matchedLoSklid ~= ""
                uialert(fig, ...
                    sprintf('This map uses a Low Range SKLID:\n\n  %s\n\n4Lo Mode has been turned OFF.\nEnable it manually (top-left checkbox) if required.\nLow Range ratio: x%.3f', ...
                        matchedLoSklid, appData.userInputs.LowRangeRatio), ...
                    '4Lo Mode — Manual Activation Required', 'Icon', 'warning');
            end
        end
    end
end
%% === HELPER: WINDOW MANAGEMENT ===
function closeMainApp(fig)
    % ── Re-entrancy guard — prevents double-fire from async CloseRequestFcn ──
    if isempty(fig) || ~isvalid(fig), return; end
    persistent isClosing;
    if ~isempty(isClosing) && isClosing, return; end
    isClosing = true;

    % ── 0. Stop auto-save timer (V7.5.2) ─────────────────────────────────────
    try
        ad0 = fig.UserData;
        if isfield(ad0,'handles') && isfield(ad0.handles,'autoSaveTimer')
            t = ad0.handles.autoSaveTimer;
            if isvalid(t)
                stop(t); delete(t);
            end
        end
    catch; end

    % ── 1. Warn if Hold & Save Session has unsaved edits ─────────────────────
    try
        ad = fig.UserData;
        if isfield(ad,'holdSession') && isstruct(ad.holdSession)
            hasEdits = false;
            for slotK = {'A','B','C'}
                sl = ad.holdSession.slots.(slotK{1});
                if ~isempty(sl) && isfield(sl,'modified') && sl.modified
                    hasEdits = true; break;
                end
            end
            if hasEdits
                warn = uiconfirm(fig, ...
                    'A Hold & Save Session has unsaved edits in one or more maps. Close anyway?', ...
                    'Unsaved Session Edits', ...
                    'Options', {'Close Anyway','Cancel'}, ...
                    'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
                if strcmp(warn,'Cancel'), isClosing = false; return; end
            end
        end
    catch; end

    % ── 2. Ask to save ────────────────────────────────────────────────────────
    try
        selection = uiconfirm(fig, ...
            'Do you want to save the project before closing?', ...
            'Close Application', ...
            'Options', {'Yes', 'No', 'Cancel'}, ...
            'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'question');
    catch
        selection = 'No';   % fig went invalid mid-dialog — just close
    end

    if strcmp(selection, 'Cancel')
        isClosing = false;  % allow future close attempt
        return;
    elseif strcmp(selection, 'Yes')
        if ~saveProject(fig)
            isClosing = false;
            return;
        end
    end

    % ── 3. Disable main CloseRequestFcn to prevent re-entry during cleanup ───
    try, fig.CloseRequestFcn = ''; catch; end

    % ── 4. Silently close every sub-window ───────────────────────────────────
    % Strategy:
    %   a) Strip each sub-window's own CloseRequestFcn first (prevents their
    %      callbacks from trying to write back to fig.UserData mid-delete).
    %   b) Remove alwaysontop WindowStyle (blocks deletion on some platforms).
    %   c) delete() the figure.
    %   All steps wrapped in individual try/catch — one bad window must never
    %   stop the rest from closing.

    function safeClose(f)
        if isempty(f) || ~isvalid(f), return; end
        try, f.CloseRequestFcn = ''; catch; end   % disarm callback
        try
            if isprop(f,'WindowStyle') && strcmpi(f.WindowStyle,'alwaysontop')
                f.WindowStyle = 'normal';
            end
        catch; end
        try, delete(f); catch; end
    end

    % a) Known handles stored in appData
    try
        appData = fig.UserData;
        knownFields = {'tableFig','ukFig','tccFig','multiMapFig', ...
                       'interpFig','gbfssactFig','analysisFig','genericFig'};
        for kk = 1:numel(knownFields)
            fn = knownFields{kk};
            if isfield(appData, fn)
                safeClose(appData.(fn));
            end
        end
    catch; end

    % b) Stop deferred sync timer if running (prevents post-delete callback crash)
    try
        syncSecondaryAxesDeferred(gobjects(0));  % pass invalid fig to trigger cleanup path
    catch; end

    % b) Sweep — catches orphaned windows (Help, Verify, Loading, Edit:, etc.)
    %    findall(groot,'Type','figure') returns ALL figures including uifigures
    %    in R2019b+. Do NOT use 'ui.figure' — it is not a valid Type string.
    skipNames = {fig.Name};   % the main window — skip
    try
        allFigs = findall(groot, 'Type', 'figure');
        for ii = 1:numel(allFigs)
            f = allFigs(ii);
            if isempty(f) || ~isvalid(f) || f == fig, continue; end
            try
                nm = get(f, 'Name');
                if any(strcmp(nm, skipNames)), continue; end
                safeClose(f);
            catch; end
        end
    catch; end

    % ── 5. Give MATLAB one event-loop tick to process pending async callbacks ─
    drawnow limitrate;

    % ── 6. Delete main figure ─────────────────────────────────────────────────
    try, delete(fig); catch; end
    isClosing = false;
end
function toggleTablePriority(fig, makeNormal)
    % All windows are now 'normal' style — just bring the right one to front.
    appData = fig.UserData;
    if hasValidHandle(appData, 'tableFig')
        if makeNormal
            fig.Visible = 'on'; figure(fig);           % bring main to front
        else
            appData.tableFig.Visible = 'on'; figure(appData.tableFig);  % bring table to front
        end
        drawnow limitrate;
    end
end
%% === SUB-FUNCTIONS ===

function swapMaps(fig)
% Swap maps.
% Normal (cbSwapC off): A ↔ B
% 3-way cycle (cbSwapC on): A→C, B→A, C→B
% Hold & Save Session: saves current wc into active slot before swap,
%   loads next slot's wc after swap — edits persist across swaps.
    appData = fig.UserData;
    h = appData.handles;

    holdActive = isfield(h,'cbHoldSave') && isvalid(h.cbHoldSave) && h.cbHoldSave.Value;
    sessionActive = holdActive && isfield(appData,'holdSession') && isstruct(appData.holdSession);

    % Set re-entrant guard: prevents checkMapSwitch from firing when we
    % programmatically change dd1/dd2/dd3 values below during slot rotation.
    appData.swapping = true;
    fig.UserData = appData;

    % Save current working copy back into its session slot BEFORE swapping
    if sessionActive && ~isempty(appData.workingCopy)
        curSlot = appData.holdSession.activeSlot;
        appData.holdSession.slots.(curSlot) = appData.workingCopy;
        fig.UserData = appData;
    end

    % Prompt unsaved changes only if NOT in session mode
    if ~holdActive && h.cbEdit.Value && ~isempty(appData.workingCopy) && ...
            isfield(appData.workingCopy,'modified') && appData.workingCopy.modified
        selection = uiconfirm(fig, ...
            'Map A has unsaved changes. Save before swapping?', 'Unsaved Changes', ...
            'Options', {'Yes','No','Cancel'}, 'DefaultOption', 1, 'CancelOption', 3, ...
            'Icon', 'warning');
        if strcmp(selection, 'Cancel'), return; end
        if strcmp(selection, 'Yes')
            saved = saveModifiedMap(fig);
            if ~saved, return; end
            appData = fig.UserData;
            h = appData.handles;
        end
    end

    % Check 3-way mode
    threeWay = isfield(h,'cbSwapC') && isvalid(h.cbSwapC) && h.cbSwapC.Value;

    if threeWay && isfield(h,'dd3') && isvalid(h.dd3) && isfield(h,'cb3') && isvalid(h.cb3)
        % Cycle dropdowns: new A = old B, new B = old C, new C = old A
        valA = h.dd1.Value; valB = h.dd2.Value; valC = h.dd3.Value;
        % Expand Items so all Values can be assigned regardless of current filtering
        allNFull3 = getMapNames(appData);
        allNCell3 = cellstr(allNFull3);
        if ~ismember(string(valB), string(h.dd1.Items)), h.dd1.Items = allNCell3; end
        if ~ismember(string(valC), string(h.dd2.Items)), h.dd2.Items = allNCell3; end
        if ~ismember(string(valA), string(h.dd3.Items)), h.dd3.Items = allNCell3; end
        h.dd1.Value = valB; h.dd2.Value = valC; h.dd3.Value = valA;

        if sessionActive
            appData = fig.UserData;
            % Rotate slot CONTENTS to match the new dropdown order.
            % Slots A/B/C always correspond to Map A/B/C position (dd1/dd2/dd3).
            % new slot A = old slot B (old Map B moves into Map A position)
            % new slot B = old slot C (old Map C moves into Map B position)
            % new slot C = old slot A (old Map A moves into Map C position)
            oldA = appData.holdSession.slots.A;
            oldB = appData.holdSession.slots.B;
            oldC = appData.holdSession.slots.C;
            appData.holdSession.slots.A = oldB;
            appData.holdSession.slots.B = oldC;
            appData.holdSession.slots.C = oldA;
            % Rotate orig_ references too (for table highlight comparison)
            oldOA = appData.holdSession.orig_A;
            oldOB = appData.holdSession.orig_B;
            oldOC = appData.holdSession.orig_C;
            appData.holdSession.orig_A = oldOB;
            appData.holdSession.orig_B = oldOC;
            appData.holdSession.orig_C = oldOA;
            % Rotate names
            oldNA = appData.holdSession.nameA;
            oldNB = appData.holdSession.nameB;
            oldNC = appData.holdSession.nameC;
            appData.holdSession.nameA = oldNB;
            appData.holdSession.nameB = oldNC;
            appData.holdSession.nameC = oldNA;
            % Active slot is always A (Map A position is always what user edits)
            appData.holdSession.activeSlot = 'A';
            appData.workingCopy = appData.holdSession.slots.A;
            if isempty(appData.workingCopy)
                allN = getMapNames(appData);
                idx = find(allN == string(char(h.dd1.Value)),1);
                if ~isempty(idx), appData.workingCopy = appData.allMaps{idx}; end
            end
            appData.editIndex = -1;
            appData.history = {};
            appData.currentMapName = char(h.dd1.Value);
            appData.handles = h;
            fig.UserData = appData;
            updateHoldSessionTitle(fig, 'A', char(h.dd1.Value));
        end
    else
        % Simple A ↔ B swap
        valA = h.dd1.Value; valB = h.dd2.Value;
        % Expand Items temporarily so both Values can be assigned regardless
        % of current ref-mode item filtering (dd1=originals, dd2=[REF] only).
        allNFull = getMapNames(appData);
        allNCell = cellstr(allNFull);
        if ~ismember(string(valB), string(h.dd1.Items))
            h.dd1.Items = allNCell;
        end
        if ~ismember(string(valA), string(h.dd2.Items))
            h.dd2.Items = allNCell;
        end
        h.dd1.Value = valB; h.dd2.Value = valA;
        % Swap Show checkboxes too
        if sessionActive
            % Swap slots A ↔ B
            appData = fig.UserData;
            tmp = appData.holdSession.slots.A;
            appData.holdSession.slots.A = appData.holdSession.slots.B;
            appData.holdSession.slots.B = tmp;
            % Swap orig references so table highlights compare correctly
            tmpO = appData.holdSession.orig_A;
            appData.holdSession.orig_A = appData.holdSession.orig_B;
            appData.holdSession.orig_B = tmpO;
            tmpN = appData.holdSession.nameA;
            appData.holdSession.nameA = appData.holdSession.nameB;
            appData.holdSession.nameB = tmpN;
            appData.holdSession.activeSlot = 'A';
            appData.workingCopy = appData.holdSession.slots.A;
            appData.editIndex = -1;
            appData.history = {};
            appData.currentMapName = char(h.dd1.Value);
            appData.handles = h;
            fig.UserData = appData;
            updateHoldSessionTitle(fig, 'A', char(h.dd1.Value));
        end
    end

    if ~sessionActive
        % Normal mode: load workingCopy from allMaps for new Map A
        appData = fig.UserData;
        allNSwap = getMapNames(appData);
        newMapA  = string(h.dd1.Value);
        idxSwap  = find(allNSwap == newMapA, 1);
        if ~isempty(idxSwap)
            appData.workingCopy = appData.allMaps{idxSwap};
            appData.editIndex   = idxSwap;
        else
            appData.workingCopy = [];
            appData.editIndex   = -1;
        end
        appData.history = {};
        appData.currentMapName = h.dd1.Value;
        appData.handles = h;
        fig.UserData = appData;
    end

    % Clear swapping guard
    appData = fig.UserData;
    appData.swapping = false;
    fig.UserData = appData;

    % After swap: set each dropdown's Items to match the TYPE of map it now holds.
    % Rule: dropdown holding a [REF] map → Items = all [REF] maps (browse all refs)
    %        dropdown holding an original  → Items = all originals (browse all originals)
    % After A↔B swap in ref mode: dd1=[REF] items, dd2=original items (or vice versa).
    h3 = appData.handles;
    appData.swapping = true; fig.UserData = appData;

    isRefModeOn = isfield(appData,'isRefMode') && appData.isRefMode;
    allN3  = getMapNames(appData);
    origC3 = cellstr(allN3(~startsWith(allN3,'[REF]')));
    if isfield(appData,'refItemsAll') && ~isempty(appData.refItemsAll)
        refC3 = cellstr(appData.refItemsAll(:));
    else
        refC3 = cellstr(allN3(startsWith(allN3,'[REF]')));
    end

    % ── dd1 (Map A) ──────────────────────────────────────────────────────────
    if isfield(h3,'dd1') && isvalid(h3.dd1)
        curA3 = string(h3.dd1.Value);
        if isRefModeOn && startsWith(curA3,'[REF]')
            % Map A holds a ref map (after swap) — show ALL ref maps so user can
            % browse/change which ref is in Map A position without needing to swap back.
            h3.dd1.Items           = refC3;
            h3.dd1.BackgroundColor = [0.88 0.95 1.0];
            if ~ismember(curA3, string(refC3)) && ~isempty(refC3)
                h3.dd1.Value = refC3{1};
            end
            % Update Map A label to show it holds a ref map
            if isfield(h3,'fileLabel') && isvalid(h3.fileLabel)
                h3.fileLabel.Text = sprintf('[REF] %s', char(appData.refVehicle.meta.description));
                h3.fileLabel.FontColor = [0.0 0.35 0.65];
            end
        else
            % Map A is original → dd1 shows originals only
            h3.dd1.Items           = origC3;
            h3.dd1.BackgroundColor = [0.95 1 0.95];
            if ~ismember(curA3, string(origC3)) && ~isempty(origC3)
                h3.dd1.Value = origC3{1};
            end
            % Restore Map A label to working file name
            if isfield(h3,'fileLabel') && isvalid(h3.fileLabel)
                if isfield(appData,'sourceFilename') && ~isempty(appData.sourceFilename)
                    h3.fileLabel.Text = ['A: ' char(appData.sourceFilename)];
                end
                h3.fileLabel.FontColor = [0.15 0.5 0.15];
            end
        end
    end

    % ── dd2 (Map B / Ref Map) ────────────────────────────────────────────────
    if isfield(h3,'dd2') && isvalid(h3.dd2)
        curB3 = string(h3.dd2.Value);
        if isRefModeOn && startsWith(curB3,'[REF]')
            % Map B holds a ref map → show all [REF] maps, label = "Ref Map:"
            h3.dd2.Items           = refC3;
            h3.dd2.BackgroundColor = [0.88 0.95 1.0];
            if isfield(h3,'lblMapB') && isvalid(h3.lblMapB)
                h3.lblMapB.Text = 'Ref Map:'; h3.lblMapB.FontColor = [0.0 0.35 0.65];
            end
            if ~ismember(curB3, string(refC3)) && ~isempty(refC3)
                h3.dd2.Value = refC3{1};
            end
        else
            % Map B holds an original map → show original maps, label = "Map B:"
            h3.dd2.Items           = origC3;
            h3.dd2.BackgroundColor = [1 0.95 0.95];
            if isfield(h3,'lblMapB') && isvalid(h3.lblMapB)
                h3.lblMapB.Text = 'Map B:'; h3.lblMapB.FontColor = [0 0 0];
            end
            if ~ismember(curB3, string(origC3)) && ~isempty(origC3)
                h3.dd2.Value = origC3{1};
            end
        end
    end

    appData.swapping = false;
    appData.handles  = h3;
    fig.UserData     = appData;

    updatePlot(fig);
    appData = fig.UserData;
    if isfield(appData,'tableFig') && hasValidHandle(appData, 'tableFig')
        if ~isempty(appData.workingCopy)
            if sessionActive
                updateHoldSessionTitle(fig, appData.holdSession.activeSlot, char(appData.workingCopy.name));
            else
                appData.tableFig.Name = ['Table Editor: ' char(appData.workingCopy.name)];
            end
        end
    end
    fig.UserData = appData;
    updateTableDisplay(fig);
    updateTCCEditor(fig);
    try, updateMapSourceLabels(fig); catch; end
    refreshAllUKTabsIfOpen(fig);  % all 6 tabs after swap
    try, refreshStatusBar(fig); catch; end
end

function onMapBSwitch(fig, src)
% Called when Map B / Ref Map dropdown changes.
    appData = fig.UserData;
    if isfield(appData,'swapping') && appData.swapping, return; end

    h = appData.handles;

    % Self-heal dd2.Items ONLY when dd2 holds a [REF] map.
    % When dd2 holds an original (after A↔B swap), leave items as originals.
    % This prevents the deferred callback from overwriting the post-swap state.
    selectedB = string(src.Value);
    if isfield(appData,'isRefMode') && appData.isRefMode && ...
            isfield(appData,'refItemsAll') && ~isempty(appData.refItemsAll) && ...
            isfield(h,'dd2') && isvalid(h.dd2) && startsWith(selectedB,'[REF]')
        needed = cellstr(appData.refItemsAll(:));
        if ~isequal(h.dd2.Items, needed)
            appData.swapping = true; fig.UserData = appData;
            h.dd2.Items = needed;
            if ismember(selectedB, string(needed)), h.dd2.Value = selectedB;
            else, h.dd2.Value = needed{1}; end
            appData.swapping = false;
            appData.handles  = h;
            fig.UserData     = appData;
        end
    end

    appData.handles = h;
    fig.UserData    = appData;
    updatePlot(fig);
    updateTCCEditor(fig);
    refreshUKStatIfOpen(fig);
    try, updateMapSourceLabels(fig); catch; end
end


function checkMapSwitch(fig, src, event)
    appData = fig.UserData;
    % Guard: swapMaps sets this flag to prevent re-entrant interference.
    if isfield(appData,'swapping') && appData.swapping, return; end

    targetMap = src.Value;

    % Guard: dd1 (Map A) only contains original maps — [REF] maps never appear
    % in dd1.Items in the new design, so no guard needed here.

    holdActive = isfield(appData.handles,'cbHoldSave') && isvalid(appData.handles.cbHoldSave) && appData.handles.cbHoldSave.Value;
    sessionActive = holdActive && isfield(appData,'holdSession') && isstruct(appData.holdSession);

    if sessionActive
        % Save current working copy back into slot A before switching map
        if ~isempty(appData.workingCopy)
            appData.holdSession.slots.A = appData.workingCopy;
        end
        % Load the new map into slot A (preserve edits if already modified)
        allN = getMapNames(appData);
        idx = find(allN == string(targetMap), 1);
        if ~isempty(idx)
            existingSlot = appData.holdSession.slots.A;
            if ~isempty(existingSlot) && isfield(existingSlot,'name') && ...
                    strcmp(char(existingSlot.name), targetMap) && ...
                    isfield(existingSlot,'modified') && existingSlot.modified
                % Slot already has edits for this map — keep them
            else
                % Fresh map: load from allMaps, reset orig for diff highlighting
                appData.holdSession.slots.A = appData.allMaps{idx};
                appData.holdSession.orig_A  = appData.allMaps{idx};
            end
        end
        appData.holdSession.nameA = targetMap;
        appData.holdSession.activeSlot = 'A';
        appData.workingCopy = appData.holdSession.slots.A;
        appData.editIndex = -1;
        appData.currentMapName = targetMap;
        src.Value = targetMap;
        fig.UserData = appData;
        updateHoldSessionTitle(fig, 'A', targetMap);
        updatePlot(fig);
        updateTCCEditor(fig);
        refreshUKStatIfOpen(fig);
        return;
    end

    % Normal mode: prompt if unsaved changes
    if ~holdActive && appData.handles.cbEdit.Value && ~isempty(appData.workingCopy) && isfield(appData.workingCopy, 'modified') && appData.workingCopy.modified
        toggleTablePriority(fig, true);
        selection = uiconfirm(fig, 'You have unsaved changes. Save before switching?', 'Unsaved Changes', ...
            'Options', {'Yes', 'No', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'warning');
        toggleTablePriority(fig, false);
        if strcmp(selection, 'Cancel')
            src.Value = appData.currentMapName; return;
        elseif strcmp(selection, 'Yes')
            saved = saveModifiedMap(fig);
            if ~saved, src.Value = appData.currentMapName; return; end
            appData = fig.UserData;
        end
    end

    src.Value = targetMap;
    appData.currentMapName = targetMap;
    % Load workingCopy for the new map (including [REF] maps)
    allNload = getMapNames(appData);
    idxLoad  = find(allNload == string(targetMap), 1);
    if ~isempty(idxLoad)
        appData.workingCopy = appData.allMaps{idxLoad};
        if ~startsWith(string(targetMap),'[REF]'), appData.editIndex = idxLoad; end
    end
    appData.history = {};
    fig.UserData = appData;
    % Update refLbl
    h2 = appData.handles;
    if isfield(h2,'refLabel') && isvalid(h2.refLabel)
        if startsWith(string(targetMap),'[REF]') && isfield(appData,'refVehicle')
            h2.refLabel.Text    = sprintf('📘 REF: %s  |  %s  |  %s  |  Axle: %.3f  |  Tire: %.0f mm', ...
                appData.refVehicle.meta.description, num2str(appData.refVehicle.meta.MY), ...
                appData.refVehicle.meta.transGen, ...
                appData.refVehicle.vehicle.AxleRatio, appData.refVehicle.vehicle.TireCircumference);
            h2.refLabel.Visible = 'on';
        end
    end
    updatePlot(fig);
    updateTableDisplay(fig);
    updateTCCEditor(fig);
    refreshUKStatIfOpen(fig);
    try, refreshStatusBar(fig); catch; end
    try, updateMapSourceLabels(fig); catch; end
end
function syncSecondaryAxesDeferred(fig)
% Debounced deferred sync — cancels and restarts timer on each call.
% Prevents timer pile-up during continuous resize/zoom events.
% Called with gobjects(0) or invalid fig during app close to stop pending timer.
    persistent dTimer;
    % Always stop any pending timer first
    if ~isempty(dTimer)
        try
            if isvalid(dTimer), stop(dTimer); delete(dTimer); end
        catch
        end
        dTimer = [];
    end
    % If fig is invalid or empty, we were called for cleanup only — stop here
    if isempty(fig) || ~isvalid(fig), return; end
    dTimer = timer('ExecutionMode','singleShot','StartDelay',0.15, ...
        'TimerFcn', @(t,~) runSync(t,fig));
    start(dTimer);
    function runSync(t,f)
        try
            if isvalid(f), drawnow limitrate; syncSecondaryAxes(f); end
        catch
        end
        try, stop(t); delete(t); catch, end
        dTimer = [];
    end
end


function syncSecondaryAxes(fig)
% Sync ax2 (MPH/KPH top axis) and ax3 (Engine RPM right axis) to ax.
% Called after rendering AND by XLim/YLim listeners on zoom/pan.
    if ~isvalid(fig), return; end
    appData = fig.UserData;
    if ~isfield(appData,'handles') || ~isfield(appData,'userInputs'), return; end
    h = appData.handles;
    ax = h.ax;

    % ── 2nd axis: MPH or KPH on top X axis ───────────────────────────────────
    if isfield(h,'ddAxis') && isfield(h,'ax2') && ~isempty(h.ax2) && isvalid(h.ax2)
        axisType = h.ddAxis.Value;
        if strcmp(axisType,'None')
            h.ax2.Visible = 'off';
        else
            % Match overlay position/size to main axis exactly
            h.ax2.InnerPosition = ax.InnerPosition;
            axleRatio = appData.userInputs.AxleRatio;
            is4Lo = isfield(h,'cb4Lo') && isvalid(h.cb4Lo) && h.cb4Lo.Value;
            if is4Lo, ratioEff = appData.userInputs.LowRangeRatio * axleRatio;
            else,     ratioEff = axleRatio; end
            if ratioEff == 0, ratioEff = 1; end   % prevent division by zero
            % TireCircumference stored in mm → convert to inches
            tireCirc_in = appData.userInputs.TireCircumference / 25.4;
            if tireCirc_in == 0, tireCirc_in = 1; end   % prevent division by zero
            % MPH = (OutputRPM / ratioEff) * tireCirc_in / 1056
            factorMPH = tireCirc_in / ratioEff / 1056;
            xLim = ax.XLim;
            lblText = '';
            if strcmp(axisType,'MPH')
                h.ax2.XLim = xLim * factorMPH;
                lblText = 'Vehicle Speed (MPH)';
            elseif strcmp(axisType,'KPH')
                h.ax2.XLim = xLim * factorMPH * 1.60934;
                lblText = 'Vehicle Speed (KPH)';
            end
            h.ax2.Visible = 'on';
            if ~isempty(lblText)
                lb = xlabel(h.ax2, lblText);
                lb.Units = 'normalized';
                pos = lb.Position;
                lb.Position = [1, pos(2), pos(3)];
                lb.HorizontalAlignment = 'right';
            end
        end
    end

    % ── 3rd axis: Engine RPM on right Y axis ──────────────────────────────────
    if isfield(h,'ax3') && ~isempty(h.ax3) && isvalid(h.ax3)
        if isfield(appData.userInputs,'IdleRPM') && isfield(appData.userInputs,'MaxRPM')
            h.ax3.InnerPosition = ax.InnerPosition;
            idle = appData.userInputs.IdleRPM;
            maxR = appData.userInputs.MaxRPM;
            yLim = ax.YLim;
            h.ax3.YLim = [idle + (yLim(1)/100)*(maxR-idle), ...
                          idle + (yLim(2)/100)*(maxR-idle)];
            h.ax3.Visible = 'on';
        else
            h.ax3.Visible = 'off';
        end
    end
end


function updatePlot(fig)
    if isempty(fig) || ~isvalid(fig), return; end
    appData = fig.UserData; h = appData.handles;
    if ~isfield(h,'ax') || isempty(h.ax) || ~isvalid(h.ax), return; end

    % ── PERFORMANCE: bulk-mode flag suppresses redraws during multi-step ops ──
    if isfield(appData,'bulkUpdate') && appData.bulkUpdate, return; end

    ax = h.ax;

    % --- 1. GET UI STATE ---
    showA = h.cb1.Value; mapA_Name = h.dd1.Value; showB = h.cb2.Value; mapB_Name = h.dd2.Value;
    % Edit Map A: disabled when Map A holds a ref map (workingCopy.isRef).
    % cbAllowY always disabled in ref mode. Edit blocked in onGenericTableEdit.
    isRefMap = ~isempty(appData.workingCopy) && isfield(appData.workingCopy,'isRef') ...
               && appData.workingCopy.isRef;
    if isfield(h,'cbEdit') && isvalid(h.cbEdit)
        h.cbEdit.Enable = 'on';   % always enabled — ref maps open table in view mode
        if isRefMap
            % Disable Y-axis editing on ref maps (no axis changes make sense for view)
            if isfield(h,'cbAllowY') && isvalid(h.cbAllowY), h.cbAllowY.Value = false; h.cbAllowY.Enable = 'off'; end
        else
            if isfield(h,'cbAllowY') && isvalid(h.cbAllowY), h.cbAllowY.Enable = 'on'; end
        end
    end
    isEdit = h.cbEdit.Value; showLines = h.cbLines.Value; showTCC = h.cbTCC.Value;

    % --- 2. MAP SELECTION LOGIC ---
    sessionActive = isfield(h,'cbHoldSave') && isvalid(h.cbHoldSave) && h.cbHoldSave.Value ...
                    && isfield(appData,'holdSession') && isstruct(appData.holdSession);

    % Session mode: same as normal edit mode but workingCopy is managed by swapMaps.
    % updatePlot must NOT reload from allMaps — only load if workingCopy is missing/wrong map.
    if sessionActive
        % Only load from slot if workingCopy is empty or points to a different map
        needLoad = isempty(appData.workingCopy) || ...
                   ~strcmp(char(appData.workingCopy.name), char(mapA_Name));
        if needLoad
            curSlot = appData.holdSession.activeSlot;
            slotWC  = appData.holdSession.slots.(curSlot);
            if ~isempty(slotWC) && strcmp(char(slotWC.name), char(mapA_Name))
                appData.workingCopy = slotWC;
            else
                % Slot empty or wrong map — load fresh from allMaps into slot
                allNames = getMapNames(appData);
                idx = find(allNames == string(mapA_Name), 1);
                if ~isempty(idx)
                    appData.workingCopy = appData.allMaps{idx};
                    appData.holdSession.slots.(curSlot) = appData.workingCopy;
                end
            end
            appData.editIndex = -1;
            fig.UserData = appData;
        end
        if ~isempty(appData.workingCopy), updateTableDisplay(fig); end
    elseif isEdit && isempty(appData.workingCopy)
        allNames = getMapNames(appData);
        idx = find(allNames == mapA_Name, 1);
        if ~isempty(idx), appData.workingCopy = appData.allMaps{idx}; appData.editIndex = idx; appData.history = {}; fig.UserData = appData; end
    elseif isEdit && ~isempty(appData.workingCopy)
        if ~strcmp(appData.workingCopy.name, mapA_Name)
             allNames = getMapNames(appData);
             idx = find(allNames == mapA_Name, 1);
             if ~isempty(idx), appData.workingCopy = appData.allMaps{idx}; appData.editIndex = idx; appData.history = {}; fig.UserData = appData; end
        end
        updateTableDisplay(fig);
    elseif ~isEdit
        appData.workingCopy = []; appData.editIndex = -1; fig.UserData = appData;
        if hasValidHandle(appData, 'tableFig'), delete(appData.tableFig); end
    end
    updateContextPanel(fig);

    % --- 3. PLOT SHIFT LINES (Main Axis) ---
    legendItems = renderMapOnAxes(fig, ax, true);

    % --- 4. PLOT ON SECONDARY TABLE AXIS (If Exists) ---
    if isfield(appData, 'tableAx') && hasValidHandle(appData, 'tableAx')
        renderMapOnAxes(fig, appData.tableAx, false);
    end

    % --- 5. SYNC SECONDARY AXES (MPH/KPH top axis + Engine RPM right axis) -----
    % Called here after rendering so ax limits are final.
    % The same function is also called by XLim/YLim listeners on zoom/pan.
    syncSecondaryAxes(fig);

    % --- 7. STACKING ORDER ---
    try
        if isvalid(h.vLine) && isvalid(h.hLine), uistack([h.vLine, h.hLine], 'bottom'); end
        if isvalid(h.crossText), uistack(h.crossText, 'top'); end
    catch; end

    % Only render legend if visible
    if strcmp(h.legendPanel.Visible, 'on')
        renderLegend(fig, legendItems);
    end
end
function renderLegend(fig, items)
    h = fig.UserData.handles;
    pnl = h.legendPanel;
    delete(pnl.Children);

    nItems = length(items);
    if nItems == 0, return; end

    rowHeight = 20;
    totalHeight = nItems * rowHeight + 10;
    panelWidth = 140; % Slightly less than column width

    % Use uiaxes (supported inside uifigure) instead of legacy axes()
    axL = uiaxes(pnl, 'Units', 'pixels', 'Position', [5, 0, panelWidth, totalHeight]);
    axL.Visible = 'off';
    axL.XLim = [0 1]; axL.YLim = [0 nItems];
    axL.XColor = 'none'; axL.YColor = 'none';
    axL.Color = 'none';
    hold(axL, 'on');

    for i = 1:nItems
        % Draw from top down
        y = nItems - i + 0.5;
        item = items(i);

        % Draw line swatch
        plot(axL, [0.05 0.25], [y y], 'Color', item.color, 'LineStyle', item.style, 'LineWidth', 2, 'Marker', item.marker, 'MarkerFaceColor', item.color);

        % Draw text
        text(axL, 0.3, y, item.text, 'VerticalAlignment', 'middle', 'FontSize', 9, 'Interpreter', 'none');
    end
    drawnow limitrate;
end
function updateTableDisplay(fig)
    appData = fig.UserData;
    if hasValidHandle(appData, 'tableHandle') && ~isempty(appData.workingCopy)
         wc = appData.workingCopy;

         % Base Data (RPM) — build once
         dataRPM = [wc.pedal(:), round(wc.Z_up), round(wc.Z_down)];

         % Determine active tab FIRST — only compute the needed conversion
         activeTabTitle = 'Output RPM';
         if isfield(appData,'editorTabGroup') && isvalid(appData.editorTabGroup)
             activeTabTitle = appData.editorTabGroup.SelectedTab.Title;
         end

         if isfield(appData,'editorTables')
             switch activeTabTitle
                 case 'Output RPM'
                     appData.editorTables.RPM.Data = dataRPM;

                 case 'MPH'
                     axleRatio = appData.userInputs.AxleRatio;
                     is4Lo = isfield(appData,'handles') && isfield(appData.handles,'cb4Lo') && isvalid(appData.handles.cb4Lo) && appData.handles.cb4Lo.Value;
                     if is4Lo, ratioEff = appData.userInputs.LowRangeRatio*axleRatio; else, ratioEff = axleRatio; end
                     if ratioEff==0, ratioEff=1; end
                     tireCirc = appData.userInputs.TireCircumference/25.4;
                     if tireCirc==0, tireCirc=1; end
                     dataMPH = dataRPM;
                     dataMPH(:,2:end) = dataRPM(:,2:end) / ratioEff * tireCirc / 1056;
                     appData.editorTables.MPH.Data = round(dataMPH,2);

                 case 'KPH'
                     axleRatio = appData.userInputs.AxleRatio;
                     is4Lo = isfield(appData,'handles') && isfield(appData.handles,'cb4Lo') && isvalid(appData.handles.cb4Lo) && appData.handles.cb4Lo.Value;
                     if is4Lo, ratioEff = appData.userInputs.LowRangeRatio*axleRatio; else, ratioEff = axleRatio; end
                     if ratioEff==0, ratioEff=1; end
                     tireCirc = appData.userInputs.TireCircumference/25.4;
                     if tireCirc==0, tireCirc=1; end
                     dataMPH = dataRPM;
                     dataMPH(:,2:end) = dataRPM(:,2:end) / ratioEff * tireCirc / 1056;
                     dataKPH = dataMPH; dataKPH(:,2:end) = dataMPH(:,2:end) * 1.60934;
                     appData.editorTables.KPH.Data = round(dataKPH,2);

                 case {'Turbine RPM','Engine RPM'}
                     % Use ref vehicle gear ratios ONLY when Map A actually holds a [REF] map.
                     % Ref Mode being on alone doesn't switch the ratios — only after a ref
                     % map is swapped INTO the Map A slot (so wc.isRef == true).
                     isWCRefMap = isfield(wc,'isRef') && wc.isRef;
                     if isWCRefMap && isfield(appData,'refVehicle') && isfield(appData.refVehicle,'vehicle')
                         gearRatios = appData.refVehicle.vehicle.GearRatios;
                     else
                         gearRatios = appData.userInputs.GearRatios;
                     end
                     dataTurbine = dataRPM;
                     nG = min(7, length(gearRatios));
                     dataTurbine(:,2:nG+1)   = dataRPM(:,2:nG+1)   .* gearRatios(1:nG);
                     nGdown = min(nG, length(gearRatios)-1);
                     if nGdown >= 1
                         dataTurbine(:,9:nGdown+8) = dataRPM(:,9:nGdown+8) .* gearRatios(2:nGdown+1);
                     end
                     dataTurbineRound = round(dataTurbine);
                     appData.editorTables.Turbine.Data = dataTurbineRound;
                     appData.editorTables.Engine.Data  = dataTurbineRound;
                     % Mirror to TCC Editor → Turbine RPM duplicate if open (V7.5.6)
                     if isfield(appData,'tccFig') && hasValidHandle(appData,'tccFig')
                         try
                             ad2 = appData.tccFig.UserData;
                             if isfield(ad2,'tTurbine') && isvalid(ad2.tTurbine) ...
                                     && ad2.tTurbine ~= appData.editorTables.Turbine
                                 ad2.tTurbine.Data = dataTurbineRound;
                             end
                         catch; end
                     end

                 otherwise
                     appData.editorTables.RPM.Data = dataRPM;
             end
         else
             appData.tableHandle.Data = dataRPM;
         end

         if hasValidHandle(appData, 'tableFig')
             % Preserve [Session X] title during session
             isSession = isfield(appData,'handles') && isfield(appData.handles,'cbHoldSave') ...
                 && isvalid(appData.handles.cbHoldSave) && appData.handles.cbHoldSave.Value ...
                 && isfield(appData,'holdSession') && isstruct(appData.holdSession);
             if isSession
                 updateHoldSessionTitle(fig, appData.holdSession.activeSlot, char(wc.name));
             else
                 appData.tableFig.Name = ['Table Editor: ' char(wc.name)];
             end
         end
         refreshTableStyles(fig);
         if ~isempty(appData.lastSelectedIndices)
             r = appData.lastSelectedIndices(end, 1); 
             c = appData.lastSelectedIndices(end, 2); 
             
             % Determine active type and value
             activeType = 'RPM';
             currentVal = dataRPM(r,c);
             if isfield(appData, 'editorTabGroup') && isvalid(appData.editorTabGroup)
                 activeTab = appData.editorTabGroup.SelectedTab;
                 if strcmp(activeTab.Title, 'MPH')
                     activeType = 'MPH';
                     currentVal = appData.editorTables.MPH.Data(r,c);
                 elseif strcmp(activeTab.Title, 'KPH')
                     activeType = 'KPH';
                     currentVal = appData.editorTables.KPH.Data(r,c);
                 elseif strcmp(activeTab.Title, 'Turbine RPM')
                     activeType = 'Turbine';
                     currentVal = appData.editorTables.Turbine.Data(r,c);
                 elseif strcmp(activeTab.Title, 'Engine RPM')
                     activeType = 'Engine';
                     currentVal = appData.editorTables.Engine.Data(r,c);
                 end
             end
             
             updateInfoPanel(fig, r, c, currentVal, activeType); 
         end
    end
end
function createDragDot(ax, xData, yData, colIdx, isUp, color)
    if isUp, mkr = 'o'; else, mkr = 's'; end
    s = scatter(ax, xData, yData, 100, color, 'filled', 'Marker', mkr, 'Tag', 'shiftPoint', 'PickableParts', 'visible');
    
    % Assign Context Menu
    fig = ancestor(ax, 'figure');
    if isfield(fig.UserData.handles, 'refreshCM')
        s.ContextMenu = fig.UserData.handles.refreshCM;
    end
    
    s.UserData = struct('col', colIdx, 'isUp', isUp); s.ButtonDownFcn = @(src,evt) startDrag(src, ax);
    % Note: uistack done once after all dots created (see renderMapOnAxes)
end
function startDrag(src, ax)
    fig = ancestor(ax, 'figure'); 
    
    % Check for Right Click to allow Context Menu
    if strcmp(fig.SelectionType, 'alt')
        return; 
    end
    
    pushHistory(fig); h = fig.UserData.handles;
    cp = ax.CurrentPoint; xClick = cp(1,1); yClick = cp(1,2);
    [~, rowIdx] = min(abs(src.XData - xClick) + abs(src.YData - yClick));
    
    % --- Get Original Values & Create Ghost ---
    appData = fig.UserData;

    % Resolve the original (pre-edit) map.
    % In session mode editIndex is -1, so fall back to allMaps lookup or workingCopy.
    sessionActive = isfield(h,'cbHoldSave') && isvalid(h.cbHoldSave) && h.cbHoldSave.Value ...
                    && isfield(appData,'holdSession') && isstruct(appData.holdSession);
    if sessionActive && ~isempty(appData.workingCopy)
        % Ghost should show PRE-EDIT position — use stored session original, not current wc
        if isfield(appData.holdSession,'orig_A') && ~isempty(appData.holdSession.orig_A)
            origMap = appData.holdSession.orig_A;
        else
            origMap = appData.workingCopy;
        end
    elseif isempty(appData.editIndex) || appData.editIndex < 1 || appData.editIndex > length(appData.allMaps)
        return;
    else
        origMap = appData.allMaps{appData.editIndex};
    end
    if src.UserData.isUp
        origX = origMap.Z_up(rowIdx, src.UserData.col);
    else
        origX = origMap.Z_down(rowIdx, src.UserData.col);
    end
    origY = origMap.pedal(rowIdx);
    
    if src.UserData.isUp, mkr = 'o'; else, mkr = 's'; end
    ghost = scatter(ax, origX, origY, 100, [0.5 0.5 0.5], 'filled', ...
        'Marker', mkr, ...
        'MarkerFaceAlpha', 0.5, 'HitTest', 'off', 'PickableParts', 'none');
    appData.dragGhost = ghost;
    fig.UserData = appData;
    
    dragData = struct('src', src, 'rowIdx', rowIdx, 'colIdx', src.UserData.col, 'isUp', src.UserData.isUp, 'allowY', h.cbAllowY.Value, 'ax', ax, 'origX', origX, 'origY', origY);
    fig.WindowButtonMotionFcn = @(f,e) dragging(fig, dragData); fig.WindowButtonUpFcn = @(f,e) stopDrag(fig);
end
function dragging(fig, d)
    try
        ax = d.ax; cp = ax.CurrentPoint;
        newX = max(0, min(8000, cp(1,1)));
        newY = max(0, min(110, cp(1,2)));

        % Move the dot visually — fastest possible update
        d.src.XData(d.rowIdx) = newX;
        if d.allowY, d.src.YData(d.rowIdx) = newY; end

        % Update data in workingCopy — direct field write, no enforceRowConstraints here
        appData = fig.UserData; wc = appData.workingCopy;
        if d.isUp
            wc.Z_up(d.rowIdx, d.colIdx) = newX;
            gearIdx = d.colIdx; lbl = sprintf('%d-%d Up Shift', gearIdx, gearIdx+1);
        else
            wc.Z_down(d.rowIdx, d.colIdx) = newX;
            gearIdx = d.colIdx + 1; lbl = sprintf('%d-%d Down Shift', gearIdx, gearIdx-1);
        end
        if d.allowY, wc.pedal(d.rowIdx) = newY; end
        wc.modified = true;
        appData.workingCopy = wc;
        if d.isUp, tCol = d.colIdx + 1; else, tCol = d.colIdx + 8; end
        appData.lastSelectedIndices = [d.rowIdx, tCol];
        fig.UserData = appData;

        % Crosshair + info text only — NO table update, NO renderMapOnAxes during drag
        h = appData.handles;
        h.vLine.XData = [newX newX]; h.vLine.Visible = 'on';
        h.hLine.YData = [newY newY]; h.hLine.Visible = 'on';
        h.crossText.Position = [newX+80, newY+2.1];
        h.crossText.String = getShiftInfoText(newX, newY, lbl, gearIdx, appData, h.cb4Lo.Value, d.origX, d.origY);
        h.crossText.FontWeight = 'bold'; h.crossText.FontSize = 11;
        h.crossText.Visible = 'on';
        drawnow limitrate;
    catch
        stopDrag(fig);
    end
end
function stopDrag(fig)
    appData = fig.UserData;
    try
        if isfield(appData, 'dragGhost') && hasValidHandle(appData, 'dragGhost')
            delete(appData.dragGhost);
        end
    catch; end
    if isfield(appData, 'dragGhost'), appData = rmfield(appData, 'dragGhost'); end

    % Apply row constraints once, now that drag is complete
    if ~isempty(appData.workingCopy)
        appData.workingCopy = enforceRowConstraints(appData.workingCopy);
    end

    % Sync edited working copy into active session slot
    if isfield(appData,'holdSession') && isstruct(appData.holdSession) && ~isempty(appData.workingCopy)
        appData.holdSession.slots.(appData.holdSession.activeSlot) = appData.workingCopy;
    end

    % Update pedal row labels if Y-axis editing was enabled
    if isfield(appData,'handles') && isfield(appData.handles,'cbAllowY') && ...
       isvalid(appData.handles.cbAllowY) && appData.handles.cbAllowY.Value && ...
       hasValidHandle(appData, 'tableHandle')
        appData.tableHandle.RowName = compose("%.1f%%", appData.workingCopy.pedal);
    end

    fig.UserData = appData;

    % One lightweight pass: update table data + highlights only
    updateTableDisplay(fig);
    refreshTableStyles(fig);

    % Push dragged map to INCA if Sync is active
    % Re-read from fig.UserData — must be live after the updates above
    liveAD = fig.UserData;
    if isfield(liveAD,'handles') && isfield(liveAD.handles,'cbSyncINCA') ...
            && isvalid(liveAD.handles.cbSyncINCA) && liveAD.handles.cbSyncINCA.Value ...
            && ~isempty(liveAD.workingCopy)
        pushMapToINCA(fig, liveAD.workingCopy);
    end

    fig.WindowButtonMotionFcn = @(src, event) passiveCrosshair(fig);
    fig.WindowButtonUpFcn = '';
end
function passiveCrosshair(fig)
    try
        if ~isvalid(fig), return; end
        h = fig.UserData.handles; ax = h.ax; cp = ax.CurrentPoint; x = cp(1,1); y = cp(1,2);
        if x < ax.XLim(1) || x > ax.XLim(2) || y < ax.YLim(1) || y > ax.YLim(2)
            h.vLine.Visible='off'; h.hLine.Visible='off'; h.crossText.Visible='off'; return;
        end
        h.vLine.XData = [x x]; h.vLine.Visible = 'on'; 
        h.hLine.YData = [y y]; h.hLine.Visible = 'on';
        h.crossText.Position = [x + 80, y + 2.1];
        appData = fig.UserData; txt = sprintf('RPM: %.0f\nPedal: %.1f%%', x, y);
        if ~isempty(appData.workingCopy)
            wc = appData.workingCopy; [~, rIdx] = min(abs(wc.pedal - y));
            [minUp, gUp] = min(abs(wc.Z_up(rIdx, :) - x)); [minDn, gDn] = min(abs(wc.Z_down(rIdx, :) - x));
            
            % Retrieve original map for comparison (session-aware)
            sessionActivePC = isfield(appData,'handles') && isfield(appData.handles,'cbHoldSave') ...
                && isvalid(appData.handles.cbHoldSave) && appData.handles.cbHoldSave.Value ...
                && isfield(appData,'holdSession') && isstruct(appData.holdSession);
            if sessionActivePC && isfield(appData.holdSession,'orig_A') && ~isempty(appData.holdSession.orig_A)
                origMap = appData.holdSession.orig_A;
            elseif appData.editIndex > 0 && appData.editIndex <= length(appData.allMaps)
                origMap = appData.allMaps{appData.editIndex};
            else
                origMap = wc;
            end
            
            if minUp < minDn && minUp < 200
                origX = origMap.Z_up(rIdx, gUp); origY = origMap.pedal(rIdx);
                txt = getShiftInfoText(x, y, sprintf('%d-%d Up Shift', gUp, gUp+1), gUp, appData, h.cb4Lo.Value, origX, origY);
            elseif minDn < 200
                origX = origMap.Z_down(rIdx, gDn); origY = origMap.pedal(rIdx);
                txt = getShiftInfoText(x, y, sprintf('%d-%d Down Shift', gDn+1, gDn), gDn+1, appData, h.cb4Lo.Value, origX, origY);
            end
        end
        h.crossText.String = txt; h.crossText.Visible = 'on';
        drawnow limitrate;   % throttle: max ~25 fps, prevents UI lag on fast mouse moves
    catch
        % Silently ignore crosshair errors (non-critical UI update)
    end
end
function pushHistory(fig)
    appData = fig.UserData; if isempty(appData.workingCopy), return; end
    appData.history{end+1} = appData.workingCopy; if length(appData.history) > 50, appData.history(1) = []; end
    fig.UserData = appData;
end

function logAction(figOrUkFig, action, detail)
% Central logger — records every user action to appData.sessionLog.
% figOrUkFig: either the main fig, or a ukFig whose UserData has .mainFig
% action:  short string like 'Map Edit', 'FSIT Change', 'UK Table Save'
% detail:  context string like map name, variable name, etc.
    try
        if nargin < 3, detail = ''; end
        % Resolve main fig
        if isfield(figOrUkFig.UserData, 'mainFig') && isvalid(figOrUkFig.UserData.mainFig)
            mainFig = figOrUkFig.UserData.mainFig;
        else
            mainFig = figOrUkFig;
        end
        appData = mainFig.UserData;
        if ~isfield(appData,'sessionLog'), appData.sessionLog = {}; end
        ts = char(datetime('now','Format','HH:mm:ss'));
        appData.sessionLog{end+1} = {ts, detail, action};
        mainFig.UserData = appData;
    catch; end
end
function onKeyPress(fig, event)
    if strcmp(event.Key, 'z') && ~isempty(event.Modifier) && any(strcmp(event.Modifier, 'control')), performUndo(fig);
    elseif strcmp(event.Key, 'v') && ~isempty(event.Modifier) && any(strcmp(event.Modifier, 'control')), pasteTableData(fig); end
end

function onHoldSaveToggle(fig, isActive)
% Called when Hold & Save Session checkbox changes.
% ON:  captures working copies for A/B/C, then locks map dropdowns so
%      the user cannot navigate away from the 3 session maps.
% OFF: clears session, unlocks all controls.
    appData = fig.UserData;
    h = appData.handles;

    % Show/hide the Save All button
    if isfield(h,'btnSaveAll') && isvalid(h.btnSaveAll)
        if isActive, h.btnSaveAll.Visible = 'on'; else, h.btnSaveAll.Visible = 'off'; end
    end

    if isActive
        % ── Initialise session slots ──────────────────────────────────────────
        allN = getMapNames(appData);
        slots = struct();

        nmA = char(h.dd1.Value);
        idxA = find(allN == string(nmA),1);
        if ~isempty(appData.workingCopy) && strcmp(char(appData.workingCopy.name), nmA)
            slots.A = appData.workingCopy;
        elseif ~isempty(idxA)
            slots.A = appData.allMaps{idxA};
        else
            slots.A = [];
        end

        nmB = char(h.dd2.Value);
        idxB = find(allN == string(nmB),1);
        if ~isempty(idxB), slots.B = appData.allMaps{idxB}; else, slots.B = []; end

        nmC = '';
        if isfield(h,'dd3') && isvalid(h.dd3)
            nmC = char(h.dd3.Value);
            idxC = find(allN == string(nmC),1);
            if ~isempty(idxC), slots.C = appData.allMaps{idxC}; else, slots.C = []; end
        else
            slots.C = [];
        end

        appData.holdSession = struct('slots', slots, 'activeSlot', 'A', ...
            'nameA', nmA, 'nameB', nmB, 'nameC', nmC, ...
            'orig_A', slots.A, 'orig_B', slots.B, 'orig_C', slots.C);
        appData.workingCopy = slots.A;

        % ── Lock controls — user works only on the 3 session maps ────────────
        setSessionLock(h, true, nmA, nmB, nmC);

        % Ensure all 3 Show checkboxes are ticked
        h.cb1.Value = true;
        h.cb2.Value = true;
        if isfield(h,'cb3') && isvalid(h.cb3), h.cb3.Value = true; end

        appData.handles = h;
        fig.UserData = appData;

        updateHoldSessionTitle(fig, 'A', nmA);

        uialert(fig, sprintf(['Hold & Save Session ACTIVE\n\n' ...
            'Slot A: %s\nSlot B: %s\nSlot C: %s\n\n' ...
            '• Map dropdowns are locked to these 3 maps.\n' ...
            '• Edit Map A freely — edits persist when you swap.\n' ...
            '• Use ⇄ (with 3⟳) to cycle between slots.\n' ...
            '• Modified points stay highlighted across swaps.\n' ...
            '• Press  💾 Save All  when done.'], nmA, nmB, nmC), ...
            'Hold & Save Session Active', 'Icon','info');
    else
        % ── Unlock all controls ───────────────────────────────────────────────
        setSessionLock(h, false, '', '', '');

        if isfield(appData,'holdSession'), appData = rmfield(appData,'holdSession'); end

        % Restore full map list to all 3 dropdowns (session narrowed them to 3)
        allN = getMapNames(appData);
        if ~isempty(allN)
            if isfield(h,'dd1') && isvalid(h.dd1)
                curVal = char(h.dd1.Value);
                h.dd1.Items = cellstr(allN);
                if ismember(curVal, allN), h.dd1.Value = curVal; end
            end
            if isfield(h,'dd2') && isvalid(h.dd2)
                curVal = char(h.dd2.Value);
                h.dd2.Items = cellstr(allN);
                if ismember(curVal, allN), h.dd2.Value = curVal; end
            end
            if isfield(h,'dd3') && isvalid(h.dd3)
                curVal = char(h.dd3.Value);
                h.dd3.Items = cellstr(allN);
                if ismember(curVal, allN), h.dd3.Value = curVal; end
            end
        end

        if ~isempty(appData.workingCopy)
            restoredIdx = find(allN == string(appData.workingCopy.name), 1);
            if ~isempty(restoredIdx), appData.editIndex = restoredIdx; else, appData.editIndex = -1; end
        end
        appData.handles = h;
        fig.UserData = appData;
        if ~isempty(appData.workingCopy)
            updateHoldSessionTitle(fig, '', char(appData.workingCopy.name));
        end
    end
    try, refreshStatusBar(fig); catch; end
end

function setSessionLock(h, lock, nmA, nmB, nmC)
% Lock or unlock map-selection controls during a Hold & Save Session.
% When locked:
%   - Dropdowns restricted to only the 3 session maps (Items narrowed)
%   - Show checkboxes disabled (maps stay visible)
%   - Load Project / Save Project buttons disabled (prevents wiping session)
%   - cbSwapC (3-way toggle) disabled (session already manages 3 maps)
% The ⇄ swap button is NOT disabled — it works programmatically on dd values.
    if lock
        % Narrow dropdown Items to only the 3 session maps
        sessionMaps = unique({nmA, nmB, nmC}, 'stable');
        sessionMaps = sessionMaps(~cellfun(@isempty, sessionMaps));
        if isfield(h,'dd1') && isvalid(h.dd1)
            h.dd1.Items = sessionMaps;
            h.dd1.Value = nmA;
        end
        if isfield(h,'dd2') && isvalid(h.dd2)
            h.dd2.Items = sessionMaps;
            h.dd2.Value = nmB;
        end
        if isfield(h,'dd3') && isvalid(h.dd3)
            h.dd3.Items = sessionMaps;
            if ~isempty(nmC), h.dd3.Value = nmC; end
        end
        % Lock show checkboxes — user cannot hide session maps
        if isfield(h,'cb1') && isvalid(h.cb1), h.cb1.Enable = 'off'; end
        if isfield(h,'cb2') && isvalid(h.cb2), h.cb2.Enable = 'off'; end
        if isfield(h,'cb3') && isvalid(h.cb3), h.cb3.Enable = 'off'; end
        % Lock cbSwapC — session manages the 3-way cycle
        if isfield(h,'cbSwapC') && isvalid(h.cbSwapC)
            h.cbSwapC.Value  = true;   % force 3-way on for session
            h.cbSwapC.Enable = 'off';
        end
        % Lock Load/Save Project menu items — prevent wiping session data
        if isfield(h,'mnuLoadProject') && isvalid(h.mnuLoadProject)
            h.mnuLoadProject.Enable = 'off';
        end
        if isfield(h,'mnuSaveProject') && isvalid(h.mnuSaveProject)
            h.mnuSaveProject.Enable = 'off';
        end
    else
        % Restore full map list to dropdowns
        % (caller should update Items from allMaps after session ends —
        %  but we re-enable interactive state here)
        if isfield(h,'dd1') && isvalid(h.dd1), h.dd1.Enable = 'on'; end
        if isfield(h,'dd2') && isvalid(h.dd2), h.dd2.Enable = 'on'; end
        if isfield(h,'dd3') && isvalid(h.dd3), h.dd3.Enable = 'on'; end
        if isfield(h,'cb1') && isvalid(h.cb1), h.cb1.Enable = 'on'; end
        if isfield(h,'cb2') && isvalid(h.cb2), h.cb2.Enable = 'on'; end
        if isfield(h,'cb3') && isvalid(h.cb3), h.cb3.Enable = 'on'; end
        if isfield(h,'cbSwapC') && isvalid(h.cbSwapC), h.cbSwapC.Enable = 'on'; end
        if isfield(h,'mnuLoadProject') && isvalid(h.mnuLoadProject)
            h.mnuLoadProject.Enable = 'on';
        end
        if isfield(h,'mnuSaveProject') && isvalid(h.mnuSaveProject)
            h.mnuSaveProject.Enable = 'on';
        end
    end
end

function updateHoldSessionTitle(fig, slot, mapName)
% Update the table editor title to show which session slot is active.
    try
        appData = fig.UserData;
        if hasValidHandle(appData, 'tableFig')
            if ~isempty(slot)
                appData.tableFig.Name = sprintf('[Session %s] %s', slot, mapName);
            else
                appData.tableFig.Name = ['Table Editor: ' mapName];
            end
        end
    catch; end
end

function saveHoldSession(fig)
% Save all session slots one by one via the standard saveModifiedMap dialog.
    appData = fig.UserData;
    h = appData.handles;

    if ~isfield(appData,'holdSession') || ~isstruct(appData.holdSession)
        uialert(fig,'No active session. Tick "Hold & Save Session" first.','Nothing to Save','Icon','warning');
        return;
    end
    sess = appData.holdSession;
    slotKeys  = {'A','B','C'};
    slotNames = {sess.nameA, sess.nameB, sess.nameC};

    savedCount = 0; skippedCount = 0;

    for si = 1:3
        slot = slotKeys{si};
        nm   = slotNames{si};
        if isempty(nm), continue; end

        appData = fig.UserData;
        wc = appData.holdSession.slots.(slot);
        if isempty(wc), skippedCount = skippedCount+1; continue; end

        % Skip unmodified slots
        if ~isfield(wc,'modified') || ~wc.modified
            skippedCount = skippedCount + 1;
            continue;
        end

        % Set swapping flag BEFORE touching dd1.Value so checkMapSwitch
        % does not fire and corrupt the holdSession slots mid-loop.
        appData.swapping = true;

        allN    = getMapNames(appData);
        idxOrig = find(allN == string(nm), 1);
        if isempty(idxOrig), idxOrig = -1; end

        appData.workingCopy            = wc;
        appData.workingCopy.modified   = true;
        appData.editIndex              = idxOrig;
        appData.currentMapName         = nm;
        appData.holdSession.activeSlot = slot;
        appData.handles                = h;
        fig.UserData                   = appData;   % write flag + state first

        h.dd1.Value = nm;                           % now safe — flag is set
        appData = fig.UserData;
        appData.handles = h;
        fig.UserData = appData;

        updateHoldSessionTitle(fig, slot, nm);
        updatePlot(fig);

        % Clear swapping flag now that rendering is done
        appData = fig.UserData;
        appData.swapping = false;
        fig.UserData = appData;

        uialert(fig, sprintf(['Saving slot %s  (%d of 3)\n\nMap: %s\n\n' ...
            'Click OK then choose how to save.'], slot, si, nm), ...
            sprintf('Save Session Slot %s', slot), 'Icon','info');

        success = saveModifiedMap(fig);

        % Re-read after save
        appData = fig.UserData;
        h = appData.handles;

        if success
            savedCount = savedCount + 1;
            if isfield(appData,'holdSession')
                appData.holdSession.slots.(slot).modified = false;
                fig.UserData = appData;
            end
        else
            sel = uiconfirm(fig, sprintf('Slot %s (%s) not saved. Continue?', slot, nm), ...
                'Save Skipped', 'Options', {'Continue','Stop'}, 'DefaultOption', 1);
            if strcmp(sel,'Stop'), break; end
            skippedCount = skippedCount + 1;
        end
    end

    % Restore dropdown to slot A map after saving all slots
    appData = fig.UserData; h = appData.handles;
    if isfield(appData,'holdSession') && isstruct(appData.holdSession)
        sessionMaps = {appData.holdSession.nameA, appData.holdSession.nameB, appData.holdSession.nameC};
        sessionMaps = sessionMaps(~cellfun(@isempty, sessionMaps));
        if ~isempty(sessionMaps)
            % For dd1, only allow non-ref items (Map A stays on original maps)
            origSession = sessionMaps(~startsWith(string(sessionMaps),'[REF]'));
            if isempty(origSession), origSession = sessionMaps; end
            if isfield(h,'dd1') && isvalid(h.dd1)
                h.dd1.Items = cellstr(origSession);
                if ismember(appData.holdSession.nameA, origSession)
                    h.dd1.Value = appData.holdSession.nameA;
                end
            end
            if isfield(h,'dd2') && isvalid(h.dd2), h.dd2.Items = cellstr(sessionMaps); h.dd2.Value = appData.holdSession.nameB; end
            if isfield(h,'dd3') && isvalid(h.dd3), h.dd3.Items = cellstr(sessionMaps); h.dd3.Value = appData.holdSession.nameC; end
        end
        appData.workingCopy    = appData.holdSession.slots.A;
        appData.currentMapName = appData.holdSession.nameA;
        appData.holdSession.activeSlot = 'A';
    end
    appData.swapping = false;
    appData.handles  = h;
    fig.UserData     = appData;
    updateHoldSessionTitle(fig, 'A', appData.holdSession.nameA);
    updatePlot(fig);

    msg = sprintf('%d slot(s) saved.', savedCount);
    if skippedCount > 0, msg = [msg sprintf('\n%d slot(s) skipped.', skippedCount)]; end
    uialert(fig, msg, 'Save All Complete', 'Icon', ternary(skippedCount==0,'success','warning'));
end

function autoSaveTick(fig)
% Auto-save handler — fires every 60s. Saves a snapshot of appData to prefdir
% so that if MATLAB crashes or user closes accidentally, work is recoverable.
    try
        if ~isvalid(fig), return; end
        ad = fig.UserData;
        if isempty(ad) || ~isfield(ad,'workingCopy'), return; end
        % Skip if nothing meaningful loaded yet (require both allMaps and a source filename)
        if ~isfield(ad,'allMaps') || isempty(ad.allMaps), return; end
        if ~isfield(ad,'sourceFilename') || isempty(ad.sourceFilename), return; end
        % Skip if user is mid-drag or session save in progress
        if isfield(ad,'swapping') && ad.swapping, return; end
        if isfield(ad,'bulkUpdate') && ad.bulkUpdate, return; end

        snapshot = ad;
        % Strip known non-serialisable runtime state (handles, gobjects, sub-windows, transient flags)
        runtimeFields = {'handles','tableFig','tableHandle','tableAx','editorTabGroup','editorTables',...
            'tccFig','ukFig','contextLabel','infoLabel','dragGhost','swapping','bulkUpdate',...
            'refVehicle','refItemsAll','isRefMode','holdSession','multiMapFig','gbfssactFig',...
            'interpFig','interpActTbl','interpTbls','interpInfo','genericFig','analysisFig',...
            'kwkInfo','wtZustandInfo','diagLog','pendingCSVPath','autoSaveTimer'};
        for ii = 1:numel(runtimeFields)
            if isfield(snapshot, runtimeFields{ii}), snapshot = rmfield(snapshot, runtimeFields{ii}); end
        end
        % Belt-and-braces: recursively scrub any remaining graphics handles to silence
        % "Figure is saved in ...mat" warnings from save() when an unexpected uifigure
        % handle is found anywhere inside nested structs (e.g. inside history slots).
        snapshot = stripGraphicsHandles(snapshot);

        snapshot.autoSaveStamp   = datestr(now,'yyyy-mm-dd HH:MM:SS');
        snapshot.autoSaveVersion = 'V7.6.4.C.CM';
        savePath = fullfile(prefdir, 'PP_AutoSave.mat');
        % Suppress the rare residual figure-saving warning if anything still slips through.
        ws = warning('off', 'MATLAB:Figure:FigureSavedToMATFile');
        cleanupWS = onCleanup(@() warning(ws));
        save(savePath, '-struct', 'snapshot', '-v7');
        % Update title bar with auto-save timestamp
        updateStatusBar(fig, sprintf('Auto-saved %s', datestr(now,'HH:MM:SS')));
    catch
    end
end


function s = stripGraphicsHandles(s)
% Recursively walk a struct and remove any field whose value is, or contains,
% a MATLAB graphics handle. Used to make autosave snapshots clean for save().
    if isstruct(s)
        if numel(s) > 1
            % Struct array — process each element
            for i = 1:numel(s)
                s(i) = stripGraphicsHandles(s(i));
            end
            return;
        end
        f = fieldnames(s);
        for ii = 1:numel(f)
            v = s.(f{ii});
            if isFieldGraphicsLike(v)
                s = rmfield(s, f{ii});
            elseif isstruct(v)
                s.(f{ii}) = stripGraphicsHandles(v);
            elseif iscell(v)
                s.(f{ii}) = stripGraphicsCell(v);
            end
        end
    end
end


function c = stripGraphicsCell(c)
% Recursively scrub graphics handles out of a cell array.
    for i = 1:numel(c)
        v = c{i};
        if isFieldGraphicsLike(v)
            c{i} = [];
        elseif isstruct(v)
            c{i} = stripGraphicsHandles(v);
        elseif iscell(v)
            c{i} = stripGraphicsCell(v);
        end
    end
end


function tf = isFieldGraphicsLike(v)
% Returns true if v is a graphics handle (or array of them).
    tf = false;
    try
        if isobject(v)
            cn = class(v);
            if strncmp(cn, 'matlab.ui.', 10) || strncmp(cn, 'matlab.graphics.', 16)
                tf = true; return;
            end
        end
        if any(ishghandle(v(:)))
            tf = true; return;
        end
    catch
    end
end


function checkAutoSaveOnStartup(fig)
% On startup check if an auto-save file exists and offer to restore.
    try
        savePath = fullfile(prefdir, 'PP_AutoSave.mat');
        if exist(savePath, 'file') ~= 2, return; end
        info = dir(savePath);
        ageMin = (now - datenum(info.date)) * 24 * 60;
        if ageMin > 60*24*7, return; end   % older than 7 days, ignore
        % Peek inside to show the user what they would be restoring
        srcDesc = '(unknown source)';
        try
            peek = load(savePath, 'sourceFilename', 'autoSaveStamp');
            if isfield(peek,'sourceFilename') && ~isempty(peek.sourceFilename)
                srcDesc = char(peek.sourceFilename);
            end
            if isfield(peek,'autoSaveStamp') && ~isempty(peek.autoSaveStamp)
                info.date = char(peek.autoSaveStamp);
            end
        catch
        end
        msg = sprintf(['An auto-saved session was found:\n\n' ...
                       '   Source: %s\n' ...
                       '   Saved:  %s\n\n' ...
                       'Would you like to restore it?'], srcDesc, info.date);
        sel = uiconfirm(fig, msg, 'Restore Auto-Save?', ...
            'Options', {'Restore','Discard','Skip'}, 'DefaultOption','Skip','CancelOption','Skip');
        if strcmp(sel,'Restore')
            try
                loaded = load(savePath);
                % Strip the auto-save markers — they shouldn't pollute appData
                if isfield(loaded,'autoSaveStamp'),   loaded = rmfield(loaded,'autoSaveStamp');   end
                if isfield(loaded,'autoSaveVersion'), loaded = rmfield(loaded,'autoSaveVersion'); end
                applyLoadedProject(fig, loaded);
                try, recentFilesMenuRefresh(fig); catch; end
                try, refreshStatusBar(fig); catch; end
                updateStatusBar(fig, 'Auto-save restored successfully', [0.0 0.45 0.74]);
            catch ME
                uialert(fig, sprintf('Could not restore auto-save: %s', ME.message), ...
                    'Restore Failed', 'Icon','error');
                diagnosticLogPush('AutoSaveRestore', ME);
            end
        elseif strcmp(sel,'Discard')
            try, delete(savePath); catch, end
        end
    catch
    end
end


function recentFilesAdd(filePath)
% Add a file path to the recent files list (kept in prefdir, max 8).
    try
        if isempty(filePath) || ~ischar(filePath) && ~isstring(filePath), return; end
        filePath = char(filePath);
        prefFile = fullfile(prefdir, 'PP_RecentFiles.mat');
        recent = {};
        if exist(prefFile,'file') == 2
            try, s = load(prefFile); recent = s.recent; catch, end
        end
        if ~iscell(recent), recent = {}; end
        % Remove if already present (will be re-added at top)
        recent = recent(~strcmp(recent, filePath));
        % Add at front
        recent = [{filePath}, recent];
        % Cap at 8
        if numel(recent) > 8, recent = recent(1:8); end
        save(prefFile, 'recent');
    catch
    end
end


function recent = recentFilesGet()
% Return cell array of recent file paths (oldest removed if file no longer exists).
    recent = {};
    try
        prefFile = fullfile(prefdir, 'PP_RecentFiles.mat');
        if exist(prefFile,'file') == 2
            s = load(prefFile);
            recent = s.recent;
        end
        % Filter out files that no longer exist
        if ~isempty(recent)
            recent = recent(cellfun(@(p) exist(p,'file')==2, recent));
        end
    catch
        recent = {};
    end
end


function recentFilesMenuRefresh(fig)
% Rebuild the Recent Files menu attached to the main figure.
    try
        ad = fig.UserData;
        if ~isfield(ad,'handles') || ~isfield(ad.handles,'mnuRecent'), return; end
        m = ad.handles.mnuRecent;
        if ~isvalid(m), return; end
        % Clear children
        delete(m.Children);
        recent = recentFilesGet();
        if isempty(recent)
            uimenu(m, 'Text', '(none)', 'Enable', 'off');
            return;
        end
        for k = 1:numel(recent)
            [~, fn, ext] = fileparts(recent{k});
            label = sprintf('%d. %s%s', k, fn, ext);
            p = recent{k};
            uimenu(m, 'Text', label, 'MenuSelectedFcn', @(~,~) recentFilesOpen(fig, p));
        end
        uimenu(m, 'Text', 'Clear Recent List', 'Separator','on', ...
            'MenuSelectedFcn', @(~,~) recentFilesClear(fig));
    catch
    end
end


function recentFilesOpen(fig, filePath)
% Open a file from the recent list — works for .csv (calls loadFromCSV path)
% and .mat (calls applyLoadedProject path).
    try
        if exist(filePath, 'file') ~= 2
            uialert(fig, sprintf('File no longer exists:\n%s', filePath), 'Not Found', 'Icon','warning');
            return;
        end
        [~, ~, ext] = fileparts(filePath);
        if strcmpi(ext, '.mat')
            try
                loaded = load(filePath);
                if isfield(loaded,'appData'), loaded = loaded.appData; end
                applyLoadedProject(fig, loaded);
                recentFilesAdd(filePath);
                recentFilesMenuRefresh(fig);
                updateStatusBar(fig, sprintf('Opened: %s', filePath), [0 0.4 0]);
            catch ME
                uialert(fig, sprintf('Failed to load: %s', ME.message), 'Load Error','Icon','error');
            end
        elseif strcmpi(ext, '.csv')
            % Trigger CSV load with this path — same path the load CSV button uses
            ad = fig.UserData; ad.pendingCSVPath = filePath; fig.UserData = ad;
            newAD = loadFromCSV(fig);
            if ~isempty(newAD)
                applyLoadedProject(fig, newAD);
                recentFilesAdd(filePath);
                recentFilesMenuRefresh(fig);
                updateStatusBar(fig, sprintf('Loaded: %s', filePath), [0 0.4 0]);
            end
        end
    catch ME
        uialert(fig, sprintf('Could not open: %s', ME.message), 'Error','Icon','error');
    end
end


function recentFilesClear(fig)
% Clear the recent files list.
    try
        prefFile = fullfile(prefdir, 'PP_RecentFiles.mat');
        if exist(prefFile, 'file') == 2, delete(prefFile); end
        recentFilesMenuRefresh(fig);
        updateStatusBar(fig, 'Recent files cleared', [0.4 0.4 0.4]);
    catch
    end
end


function updateStatusBar(fig, msg, ~)
% Update the figure title bar with a transient status message (V7.6.3).
% The 3rd arg (color) is kept for backward compatibility but ignored —
% title bars don't support per-segment text colour.
%   Title format: 'Pattern Plotter V7.6.4.C.CM  |  <status text>'
% After a transient message, a refreshStatusBar call rebuilds the
% persistent state (Map A name, INCA, Hold, Ref) into the title.
    try
        if ~isvalid(fig), return; end
        baseName = 'Pattern Plotter V7.6.4.C.CM';
        if nargin < 2 || isempty(msg)
            fig.Name = baseName;
        else
            fig.Name = sprintf('%s  |  %s', baseName, char(msg));
        end
    catch
    end
end


function refreshStatusBar(fig)
% Rebuild the persistent state portion of the figure title bar (V7.6.3).
% Format: 'Pattern Plotter V7.6.4.C.CM  |  Map A: <name> (<n> rows)  |  REF: ... | INCA: ... | Hold: ...'
    try
        if ~isvalid(fig), return; end
        ad = fig.UserData;
        baseName = 'Pattern Plotter V7.6.4.C.CM';

        parts = {};
        % Map A name and row count
        if isfield(ad,'workingCopy') && ~isempty(ad.workingCopy) && isfield(ad.workingCopy,'name')
            nR = 0;
            if isfield(ad.workingCopy,'pedal'), nR = numel(ad.workingCopy.pedal); end
            parts{end+1} = sprintf('Map A: %s (%d rows)', char(ad.workingCopy.name), nR);
        else
            parts{end+1} = 'Map A: (none)';
        end
        % Ref mode indicator (only when actually loaded)
        if isfield(ad,'isRefMode') && ad.isRefMode && isfield(ad,'refVehicle') && ~isempty(ad.refVehicle)
            parts{end+1} = sprintf('REF: %s', char(ad.refVehicle.meta.description));
        end
        % INCA sync status
        if isfield(ad,'handles') && isfield(ad.handles,'cbSyncINCA') ...
                && isvalid(ad.handles.cbSyncINCA) && ad.handles.cbSyncINCA.Value
            parts{end+1} = 'INCA: SYNC ON';
        end
        % Hold session
        if isfield(ad,'handles') && isfield(ad.handles,'cbHoldSave') ...
                && isvalid(ad.handles.cbHoldSave) && ad.handles.cbHoldSave.Value
            parts{end+1} = 'Hold: ACTIVE';
        end

        if isempty(parts)
            fig.Name = baseName;
        else
            fig.Name = sprintf('%s  |  %s', baseName, strjoin(parts, '  |  '));
        end
    catch
    end
end


function showAboutDialog(fig)
% About dialog showing version, paths, and contributors.
    try
        d = uifigure('Name','About Pattern Plotter','Position',[200 200 520 460], ...
            'WindowStyle','modal','Resize','off','Color',[1 1 1]);
        movegui(d,'center');
        gl = uigridlayout(d,[5,1]); gl.RowHeight = {70, 30, '1x', 30, 44};
        gl.Padding = [20 20 20 20]; gl.RowSpacing = 8;

        lblTitle = uilabel(gl,'Text','Pattern Plotter','FontSize',26,'FontWeight','bold',...
            'FontColor',[0 0.3 0.6]); lblTitle.Layout.Row = 1;
        lblVer = uilabel(gl,'Text','V7.6.4.C.CM','FontSize',13,'FontColor',[0.3 0.3 0.3]);
        lblVer.Layout.Row = 2;

        % Build info text
        infoLines = {};
        infoLines{end+1} = sprintf('MATLAB Runtime: %s', version);
        infoLines{end+1} = sprintf('Deployed:       %s', mat2str(isdeployed));
        infoLines{end+1} = sprintf('Pref folder:    %s', prefdir);
        try
            mipFile = fullfile(prefdir,'PP_MIP_path.mat');
            if exist(mipFile,'file')==2, ld=load(mipFile);
                if isfield(ld,'mipPath'), infoLines{end+1}=sprintf('INCA-MIP path:  %s',ld.mipPath); end
            end
        catch, end
        try
            dbFile = fullfile(prefdir,'PatternPlotter_RefDB.mat');
            if exist(dbFile,'file')==2, infoLines{end+1}=sprintf('RefDB path:     %s',dbFile); end
        catch, end
        infoLines{end+1} = '';
        infoLines{end+1} = 'Maintainers: Chenthu Manikasingam';
        infoLines{end+1} = '             Paul Tuttle';
        infoLines{end+1} = '';
        infoLines{end+1} = 'A MATLAB-based calibration tool for visualising,';
        infoLines{end+1} = 'comparing and editing automotive transmission';
        infoLines{end+1} = 'shift maps from CSV calibration files.';

        ta = uitextarea(gl,'Value',infoLines,'Editable','off','FontName','Consolas','FontSize',11);
        ta.Layout.Row = 3;

        lblBuild = uilabel(gl,'Text',sprintf('Build date: %s', datestr(now,'yyyy-mm-dd')),...
            'FontSize',10,'FontColor',[0.5 0.5 0.5]); lblBuild.Layout.Row = 4;

        btn = uibutton(gl,'Text','Close','BackgroundColor',[0.85 0.85 0.85],...
            'ButtonPushedFcn',@(~,~) delete(d));
        btn.Layout.Row = 5;
    catch ME
        uialert(fig, sprintf('About dialog error: %s', ME.message),'Error','Icon','error');
    end
end


function diagnosticLogPush(area, ME)
% Append an error to the in-memory diagnostic log buffer (kept on the main figure).
    try
        figs = findall(0,'Type','figure');
        for f = figs(:)'
            if isfield(f.UserData,'workingCopy')
                ad = f.UserData;
                if ~isfield(ad,'diagLog'), ad.diagLog = {}; end
                entry = sprintf('[%s] %s: %s (%s)', datestr(now,'HH:MM:SS'), ...
                    char(area), char(ME.message), char(ME.identifier));
                ad.diagLog{end+1} = entry;
                if numel(ad.diagLog) > 200, ad.diagLog = ad.diagLog(end-199:end); end
                f.UserData = ad;
                return;
            end
        end
    catch
    end
end


function showDiagnosticLog(fig)
% Display the in-memory diagnostic log buffer in a modal window.
% This buffer collects errors caught by diagnosticLogPush throughout the session.
    try
        ad = fig.UserData;
        logEntries = {};
        if isfield(ad,'diagLog') && ~isempty(ad.diagLog)
            logEntries = ad.diagLog;
        end
        if isempty(logEntries)
            logEntries = {'(No diagnostic entries yet — this log captures errors from try/catch blocks during the session.)'};
        end

        d = uifigure('Name','Diagnostic Log','Position',[200 200 700 500],...
            'WindowStyle','modal','Color',[1 1 1]);
        movegui(d,'center');
        gl = uigridlayout(d,[3,1]);
        gl.RowHeight = {30,'1x',44}; gl.Padding=[12 12 12 12]; gl.RowSpacing=8;

        uilabel(gl,'Text',sprintf('Diagnostic Log — %d entries',numel(logEntries)),...
            'FontSize',13,'FontWeight','bold');

        ta = uitextarea(gl,'Value',logEntries,'Editable','off',...
            'FontName','Consolas','FontSize',11);

        btnGrid = uigridlayout(gl,[1,3]);
        btnGrid.ColumnWidth = {'1x','1x','1x'}; btnGrid.Padding=[0 0 0 0];
        uibutton(btnGrid,'Text','Copy to Clipboard',...
            'BackgroundColor',[0.85 0.95 1],...
            'ButtonPushedFcn',@(~,~) clipboard('copy', strjoin(logEntries, sprintf('\n'))));
        uibutton(btnGrid,'Text','Clear Log',...
            'BackgroundColor',[1 0.9 0.85],...
            'ButtonPushedFcn',@(~,~) clearDiagLog(fig,d));
        uibutton(btnGrid,'Text','Close',...
            'BackgroundColor',[0.85 0.85 0.85],...
            'ButtonPushedFcn',@(~,~) delete(d));
    catch ME
        uialert(fig,sprintf('Could not open diagnostic log: %s',ME.message),...
            'Error','Icon','error');
    end
end


function clearDiagLog(fig, d)
% Helper — clear the diagnostic log and close the dialog.
    try
        ad = fig.UserData;
        if isfield(ad,'diagLog'), ad.diagLog = {}; fig.UserData = ad; end
    catch; end
    try, delete(d); catch; end
end


function onTCCTabChanged(fig)
% Called when user switches tabs inside the TCC Editor.
% Forces the Turbine RPM tab to populate with current Map A data, even if
% Edit Map A is not open (which is the path that normally populates it).
    try
        appData = fig.UserData;
        if ~isfield(appData,'tccFig') || ~hasValidHandle(appData,'tccFig'), return; end
        ad = appData.tccFig.UserData;
        if ~isfield(ad,'tabGroup') || ~isvalid(ad.tabGroup), return; end
        if ~strcmp(ad.tabGroup.SelectedTab.Title, 'Turbine RPM'), return; end
        if ~isfield(ad,'tTurbine') || ~isvalid(ad.tTurbine), return; end

        wc = appData.workingCopy;
        if isempty(wc) || ~isfield(wc,'pedal'), ad.tTurbine.Data = []; return; end

        % Compute Turbine RPM = Output Shaft RPM × gear ratio
        dataRPM = [wc.pedal(:), round(wc.Z_up), round(wc.Z_down)];
        isWCRefT  = isfield(wc,'isRef') && wc.isRef;
        isRefModT = isfield(appData,'isRefMode') && appData.isRefMode && isfield(appData,'refVehicle');
        if isWCRefT && isRefModT && isfield(appData.refVehicle,'vehicle')
            gearRatios = appData.refVehicle.vehicle.GearRatios;
        else
            gearRatios = appData.userInputs.GearRatios;
        end
        dataTurbine = dataRPM;
        nG = min(7, length(gearRatios));
        dataTurbine(:, 2:nG+1) = dataRPM(:, 2:nG+1) .* gearRatios(1:nG);
        nGdown = min(nG, length(gearRatios)-1);
        if nGdown >= 1
            dataTurbine(:, 9:nGdown+8) = dataRPM(:, 9:nGdown+8) .* gearRatios(2:nGdown+1);
        end
        ad.tTurbine.Data = round(dataTurbine);

        % Apply colours via the standard pipeline (handles boundary rows, yellow diff,
        % red regression, magenta hysteresis, orange/red pedal validation)
        try, refreshTableStyles(fig); catch; end
    catch ME
        diagnosticLogPush('TCC_Turbine_TabChanged', ME);
    end
end


function updateMapSourceLabels(fig)
% Update the 3 stacked source labels on the LEFT side of the GUI:
%   handles.fileLabel   ← Map A (dd1) → "A: <filename>" or "A: [REF] <vehicle>"
%   handles.fileLabelB  ← Map B (dd2) → "B: <filename>" or "B: [REF] <vehicle>"
%   handles.fileLabelC  ← Map C (dd3) → "C: <filename>" or "C: [REF] <vehicle>"
% Called from: swapMaps, onRefModeToggle, checkMapSwitch, onMapBSwitch,
% applyLoadedProject, startup.
    try
        if ~isvalid(fig), return; end
        ad = fig.UserData;
        if ~isfield(ad,'handles'), return; end
        h = ad.handles;

        wfName = '';
        if isfield(ad,'sourceFilename') && ~isempty(ad.sourceFilename)
            wfName = char(ad.sourceFilename);
        end
        refDesc = '';
        if isfield(ad,'refVehicle') && isstruct(ad.refVehicle) && isfield(ad.refVehicle,'meta')
            refDesc = char(ad.refVehicle.meta.description);
        end
        if isempty(refDesc), refDesc = '(vehicle)'; end

        ddNames  = {'dd1',          'dd2',          'dd3'};
        lblNames = {'fileLabel',    'fileLabelB',   'fileLabelC'};
        prefixes = {'A: ',          'B: ',          'C: '};
        wfColors = {[0.15 0.5 0.15], [0.5 0.15 0.15], [0.15 0.15 0.5]};
        refColor = [0.0 0.35 0.65];

        for k = 1:3
            ddF  = ddNames{k};
            lblF = lblNames{k};
            if ~isfield(h,ddF)  || ~isvalid(h.(ddF)),  continue; end
            if ~isfield(h,lblF) || ~isvalid(h.(lblF)), continue; end
            ddVal = char(string(h.(ddF).Value));
            if startsWith(ddVal, '[REF] ')
                h.(lblF).Text      = [prefixes{k} '[REF] ' refDesc];
                h.(lblF).FontColor = refColor;
                h.(lblF).FontAngle = 'italic';
            elseif isempty(wfName)
                h.(lblF).Text      = [prefixes{k} '—'];
                h.(lblF).FontColor = [0.5 0.5 0.5];
                h.(lblF).FontAngle = 'normal';
            else
                h.(lblF).Text      = [prefixes{k} wfName];
                h.(lblF).FontColor = wfColors{k};
                h.(lblF).FontAngle = 'normal';
            end
        end
    catch ME
        try, diagnosticLogPush('updateMapSourceLabels', ME); catch; end
    end
end


function exitBulkMode(fig)
% onCleanup helper — clears bulkUpdate flag even on error/exception
    try
        if isvalid(fig)
            ad = fig.UserData;
            if isfield(ad,'bulkUpdate'), ad.bulkUpdate=false; fig.UserData=ad; end
        end
    catch; end
end


function tf = hasValidHandle(appData, fname)
% Returns true if appData has the named field AND that field is a non-empty valid handle.
% Safe to call when the field is missing entirely (no "Unrecognized field name" crash).
    tf = isfield(appData, fname) && ~isempty(appData.(fname)) && isvalid(appData.(fname));
end


function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end

function onClearAllLines(fig, clearState)
% Toggle all gear shift + TCC checkboxes off (clearState=true) or back on (clearState=false).
    try
        h = fig.UserData.handles;
        newVal = ~clearState;

        % Use pre-built flat lists — no containers.Map key lookup needed
        if isfield(h,'gearChecksList')
            for i = 1:numel(h.gearChecksList)
                try, h.gearChecksList{i}.Value = newVal; catch; end
            end
        end
        if isfield(h,'tccChecksList')
            for i = 1:numel(h.tccChecksList)
                try, h.tccChecksList{i}.Value = newVal; catch; end
            end
        end
    catch; end  % non-critical UI callback — silently ignore
    updatePlot(fig);
end

function onIndividualLineCheck(fig, src)
% When user manually turns any single line back ON, clear the "Clear All" flag.
    try
        if src.Value
            h = fig.UserData.handles;
            if isfield(h,'cbClearAll') && isvalid(h.cbClearAll)
                h.cbClearAll.Value = false;
            end
        end
    catch; end
    updatePlot(fig);
end
function performUndo(fig)
    appData = fig.UserData; if isempty(appData.history), return; end
    lastState = appData.history{end}; appData.history(end) = [];
    appData.workingCopy = lastState;
    % Sync undone state back into active session slot
    if isfield(appData,'holdSession') && isstruct(appData.holdSession)
        appData.holdSession.slots.(appData.holdSession.activeSlot) = lastState;
    end
    fig.UserData = appData; updatePlot(fig); refreshTableStyles(fig);
end
function applyMath(fig, type)
    appData = fig.UserData;
    if ~hasValidHandle(appData,'tableHandle') || isempty(appData.lastSelectedIndices), uialert(appData.tableFig, 'Please select cells first.', 'Selection Error'); return; end
    % 'add' applies a raw Output-RPM offset to the working copy. On the
    % MPH/KPH/Turbine/Engine tabs the cells are shown in converted units, so a
    % raw offset would be wrong. Multiply/Divide/Percentage are scale-invariant.
    if strcmp(type,'add')
        try
            if isfield(appData,'editorTabGroup') && isvalid(appData.editorTabGroup) ...
                    && ismember(appData.editorTabGroup.SelectedTab.Title, ...
                               {'MPH','KPH','Turbine RPM','Engine RPM'})
                uialert(appData.tableFig, ...
                    ['Add Offset adds a raw Output-RPM value. Switch to the RPM tab ' ...
                     'to add an offset. (Multiply / Divide / Percentage work on any tab.)'], ...
                    'Use RPM Tab'); return;
            end
        catch
        end
    end
    prompt = ""; def = "0";
    switch type
        case 'add', prompt = "Add Value (e.g. 50 or -50):";
        case 'mult', prompt = "Multiply by (e.g. 1.1):"; def = "1";
        case 'div', prompt = "Divide by:"; def = "1";
        case 'percent', prompt = "Percentage Change (e.g. 10 or -5):";
    end
    toggleTablePriority(fig, true); answer = inputdlg(prompt, 'Batch Edit', [1 40], {char(def)}); toggleTablePriority(fig, false);
    if isempty(answer), return; end
    val = str2double(answer{1}); if isnan(val), return; end
    pushHistory(fig); appData = fig.UserData; wc = appData.workingCopy; sel = appData.lastSelectedIndices;
    for i = 1:size(sel, 1)
        r = sel(i, 1); c = sel(i, 2);
        if c == 1, curr = wc.pedal(r); elseif c <= 8, curr = wc.Z_up(r, c-1); else, curr = wc.Z_down(r, c-8); end
        switch type
            case 'add', curr = curr + val; case 'mult', curr = curr * val; case 'div', if val ~= 0, curr = curr / val; end; case 'percent', curr = curr * (1 + val/100);
        end
        if c > 1, curr = round(curr); end
        if c == 1, wc.pedal(r) = curr; elseif c <= 8, wc.Z_up(r, c-1) = curr; else, wc.Z_down(r, c-8) = curr; end
    end
    wc = enforceRowConstraints(wc);
    wc.modified = true; appData.workingCopy = wc;
    % Sync to session slot so edits persist across swaps
    if isfield(appData,'holdSession') && isstruct(appData.holdSession)
        appData.holdSession.slots.(appData.holdSession.activeSlot) = wc;
    end
    fig.UserData = appData; updatePlot(fig);
end
function pasteTableData(fig)
    appData = fig.UserData;
    if isempty(appData.workingCopy) || ~hasValidHandle(appData, 'tableHandle'), return; end
    % Ctrl+V paste writes raw Output-RPM values into the working copy. On the
    % MPH/KPH/Turbine/Engine tabs the cells are shown in converted units, so
    % redirect the user to the type-aware right-click Paste instead.
    try
        if isfield(appData,'editorTabGroup') && isvalid(appData.editorTabGroup) ...
                && ismember(appData.editorTabGroup.SelectedTab.Title, ...
                           {'MPH','KPH','Turbine RPM','Engine RPM'})
            uialert(appData.tableFig, ...
                ['Ctrl+V paste writes raw Output-RPM values. On the ' ...
                 'MPH/KPH/Turbine/Engine tab use right-click > Paste instead, ' ...
                 'or switch to the RPM tab.'], 'Use RPM Tab'); return;
        end
    catch
    end
    try
        str = clipboard('paste'); if isempty(str), return; end
        cleanStr = regexprep(str, '[^0-9\.\-\+\s\n\t]', ''); rows = split(cleanStr, newline); rows = rows(~cellfun('isempty', rows));
        if isempty(rows), return; end
        if isempty(appData.lastSelectedIndices), startR = 1; startC = 1; else, startR = min(appData.lastSelectedIndices(:,1)); startC = min(appData.lastSelectedIndices(:,2)); end
        pushHistory(fig); appData = fig.UserData; wc = appData.workingCopy; maxRows = size(wc.Z_up, 1); maxCols = 15;
        for r = 1:length(rows)
            numStrs = regexp(rows{r}, '[-+]?[0-9]*\.?[0-9]+', 'match'); vals = str2double(numStrs); if isempty(vals), continue; end
            for c = 1:length(vals)
                targetR = startR + r - 1; targetC = startC + c - 1; if targetR > maxRows || targetC > maxCols, continue; end
                val = vals(c); if targetC > 1, val = round(val); end
                if targetC == 1, wc.pedal(targetR) = val; elseif targetC <= 8, wc.Z_up(targetR, targetC-1) = val; else, wc.Z_down(targetR, targetC-8) = val; end
            end
        end
        wc = enforceRowConstraints(wc);
        wc.modified = true; appData.workingCopy = wc;
        % Sync to session slot
        if isfield(appData,'holdSession') && isstruct(appData.holdSession)
            appData.holdSession.slots.(appData.holdSession.activeSlot) = wc;
        end
        fig.UserData = appData; updatePlot(fig);
    catch, uialert(appData.tableFig, 'Invalid data.', 'Paste Error'); end
end
function openTableEditor(fig)
    appData = fig.UserData;
    % Allow opening in session mode even if cbEdit checkbox is off
    isSession = isfield(appData.handles,'cbHoldSave') && isvalid(appData.handles.cbHoldSave) ...
                && appData.handles.cbHoldSave.Value;
    if isempty(appData.workingCopy)
        if ~isSession
            uialert(fig, 'Please enable "Edit Map A" and select a map first.', 'No Map Selected'); return;
        end
    end
    if hasValidHandle(appData, 'tableFig')
        appData.tableFig.Visible = 'on'; figure(appData.tableFig); return;
    end
    wc = appData.workingCopy;
    if isempty(wc), uialert(fig,'No map loaded in Map A.','No Map Selected'); return; end
    
    % INCREASE HEIGHT AND CHANGE LAYOUT TO VERTICAL STACK
    % Open at compact height — plot is hidden until user clicks Show Plot.
    % Screen-aware: cap to screen size so nothing goes off-screen.
    scrn = get(0,'ScreenSize');
    tW = min(1680, scrn(3) - 20);   % wider to show all 15 columns
    tH_compact = min(520, scrn(4) - 80);
    tX = scrn(1) + (scrn(3) - tW) / 2;
    tY = scrn(2) + (scrn(4) - tH_compact) / 2;
    % Title reflects session slot if active
    isSession2 = isfield(appData.handles,'cbHoldSave') && isvalid(appData.handles.cbHoldSave) ...
                 && appData.handles.cbHoldSave.Value && isfield(appData,'holdSession');
    if isSession2
        tTitle = sprintf('[Session %s] %s', appData.holdSession.activeSlot, char(wc.name));
    else
        tTitle = ['Table Editor: ' char(wc.name)];
    end
    try, tFig = uifigure('Name', tTitle, ...
            'Position', [tX tY tW tH_compact], 'WindowStyle', 'normal');
    catch, tFig = uifigure('Name', tTitle, ...
            'Position', [tX tY tW tH_compact]); end
    tFig.CloseRequestFcn = @(src,event) closeTable(fig, src);
    tFig.WindowKeyPressFcn = @(src, event) onKeyPress(fig, event);

    % Main Layout: 2 Rows (Table top, Plot bottom hidden by default)
    mainGl = uigridlayout(tFig, [2 1]);
    mainGl.RowHeight = {0, '1x'};   % plot row (top) starts collapsed
    mainGl.Padding = [5 5 5 5];
    
    % --- TOP SECTION (Table & Controls) ---
    topGl = uigridlayout(mainGl, [1 2]); 
    topGl.Layout.Row = 2; topGl.Layout.Column = 1;
    topGl.ColumnWidth = {'3x', 250};
    topGl.Padding = [0 0 0 0];
    
    % --- TAB GROUP SETUP ---
    tg = uitabgroup(topGl, 'SelectionChangedFcn', @(~,~) updateTableDisplay(fig));
    tg.Layout.Column = 1; tg.Layout.Row = 1;
    
    colNames = {'Pedal %','1->2','2->3','3->4','4->5','5->6','6->7','7->8','2->1','3->2','4->3','5->4','6->5','7->6','8->7'};
    
    % Create Tabs
    tabs.RPM = uitab(tg, 'Title', 'Output RPM');
    tabs.MPH = uitab(tg, 'Title', 'MPH');
    tabs.KPH = uitab(tg, 'Title', 'KPH');
    tabs.Turbine = uitab(tg, 'Title', 'Turbine RPM');
    tabs.Engine = uitab(tg, 'Title', 'Engine RPM');
    
    % Helper to create table
    function t = createTabTable(parentTab, type)
        glT = uigridlayout(parentTab, [1 1]);
        t = uitable(glT, 'Data', [], 'ColumnName', colNames, 'ColumnEditable', true, ...
            'ColumnWidth', 'auto', ...
            'CellEditCallback', @(src, event) onGenericTableEdit(fig, src, event, type), ...
            'CellSelectionCallback', @(src, event) onTableSelect(fig, src, event, type));
        cm = uicontextmenu(ancestor(parentTab, 'figure'));
        uimenu(cm, 'Text', 'Add Offset (+/-)...', 'MenuSelectedFcn', @(s,e) applyMath(fig, 'add'));
        uimenu(cm, 'Text', 'Multiply (*)...', 'MenuSelectedFcn', @(s,e) applyMath(fig, 'mult'));
        uimenu(cm, 'Text', 'Divide (/)...', 'MenuSelectedFcn', @(s,e) applyMath(fig, 'div'));
        uimenu(cm, 'Text', 'Percentage (%)...', 'MenuSelectedFcn', @(s,e) applyMath(fig, 'percent'));
        uimenu(cm, 'Text', 'Copy', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) copySelection(t));
        uimenu(cm, 'Text', 'Paste', 'MenuSelectedFcn', @(~,~) pasteSelection(t, @(src) onGenericTablePaste(fig, src, type)));
        t.ContextMenu = cm;
    end

    tables = struct();
    tables.RPM = createTabTable(tabs.RPM, 'RPM');
    tables.MPH = createTabTable(tabs.MPH, 'MPH');
    tables.KPH = createTabTable(tabs.KPH, 'KPH');
    tables.Turbine = createTabTable(tabs.Turbine, 'Turbine');
    tables.Engine = createTabTable(tabs.Engine, 'Engine');
    
    t = tables.RPM; % Set primary table for legacy compatibility if needed
    
    rightGrid = uigridlayout(topGl, [4 1]); rightGrid.Layout.Column = 2; rightGrid.Layout.Row = 1;
    rightGrid.RowHeight = {'1x', 120, 40, 36}; rightGrid.Padding = [0 0 0 0];
    pnlInfo = uipanel(rightGrid, 'BackgroundColor', [0.95 0.95 0.95]); pnlInfo.Layout.Row = 1;
    infoInner = uigridlayout(pnlInfo, [1 1]); infoInner.Padding = [10 10 10 10];
    lbl = uilabel(infoInner, 'Text', 'Select a cell.', 'VerticalAlignment', 'top', 'FontSize', 12, 'Interpreter', 'html');
    pnlHyst = uipanel(rightGrid, 'Title', 'Min Hysteresis Thresholds', 'BackgroundColor', [0.6 0.8 1], 'FontWeight', 'bold'); pnlHyst.Layout.Row = 2;
    hystGrid = uigridlayout(pnlHyst, [2 3]); hystGrid.RowHeight = {'1x','1x'}; hystGrid.ColumnWidth = {'1x','1x','1x'}; hystGrid.Padding = [2 2 2 2];
    uilabel(hystGrid, 'Text', 'Speed', 'HorizontalAlignment','center', 'FontWeight','bold'); uilabel(hystGrid, 'Text', 'Pedal', 'HorizontalAlignment','center', 'FontWeight','bold'); uilabel(hystGrid, 'Text', 'MPH', 'HorizontalAlignment','center', 'FontWeight','bold');
    uieditfield(hystGrid, 'numeric', 'Value', appData.hysteresis.Speed, 'BackgroundColor', [1 0.5 0], 'HorizontalAlignment', 'center', 'ValueChangedFcn', @(src,e) updateHysteresis(fig, 'Speed', src.Value));
    uieditfield(hystGrid, 'numeric', 'Value', appData.hysteresis.Pedal, 'BackgroundColor', [0 0.8 1], 'HorizontalAlignment', 'center', 'ValueChangedFcn', @(src,e) updateHysteresis(fig, 'Pedal', src.Value));
    uieditfield(hystGrid, 'numeric', 'Value', appData.hysteresis.MPH, 'BackgroundColor', [1 0 1], 'HorizontalAlignment', 'center', 'ValueChangedFcn', @(src,e) updateHysteresis(fig, 'MPH', src.Value));
    btnCopy = uibutton(rightGrid, 'Text', 'Copy Data', 'BackgroundColor', [0.9 1 0.9], 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~) copyTableData(fig)); btnCopy.Layout.Row = 3;

    % --- SHOW PLOT + ALWAYS ON TOP — side by side in one row ---
    btmRow = uipanel(rightGrid, 'BorderType', 'none'); btmRow.Layout.Row = 4;
    btmGl  = uigridlayout(btmRow, [1 2]); btmGl.ColumnWidth = {'1x','fit'}; btmGl.Padding = [0 2 0 2];
    btnShowPlot = uibutton(btmGl, 'Text', 'Show Plot ▼', ...
        'BackgroundColor', [0.2 0.5 0.9], 'FontColor', [1 1 1], ...
        'FontWeight', 'bold', 'FontSize', 11);
    btnShowPlot.ButtonPushedFcn = @(src,~) toggleTablePlot(src, mainGl, fig);
    cbOnTop = uicheckbox(btmGl, 'Text', 'Always on Top', 'Value', false, ...
        'FontWeight', 'bold', 'FontSize', 10);
    cbOnTop.ValueChangedFcn = @(src,~) setTableOnTop(tFig, src.Value);

    % --- BOTTOM SECTION (Plot — hidden by default) ---
    pnlPlot = uipanel(mainGl, 'BorderType', 'none');
    pnlPlot.Layout.Row = 1; pnlPlot.Layout.Column = 1;
    plotLayout = uigridlayout(pnlPlot, [1 1]);

    axTable = uiaxes(plotLayout);
    title(axTable, 'Interactive Map View (Output RPM vs Pedal%)');
    xlabel(axTable, 'Output Shaft RPM');
    ylabel(axTable, 'Pedal %');
    grid(axTable, 'on');
    xlim(axTable, [0 8000]); ylim(axTable, [0 110]);

    appData.tableFig = tFig; appData.tableHandle = t; appData.editorTables = tables;
    appData.editorTabGroup = tg;
    appData.infoLabel = lbl;
    appData.tableAx = axTable;

    fig.UserData = appData;
    updateTableDisplay(fig);
    drawnow limitrate;
end

function toggleTablePlot(btn, mainGl, fig)
    % Resize window AND toggle plot row so no wasted blank space
    appData = fig.UserData;
    tFig = appData.tableFig;
    scrn = get(0,'ScreenSize');
    tH_compact = min(520,  scrn(4) - 80);
    tH_full    = min(920,  scrn(4) - 80);
    if mainGl.RowHeight{1} == 0
        % Expand: grow window upward, show plot row (row 1 = top)
        pos = tFig.Position;
        newY = pos(2) - (tH_full - pos(4));   % keep bottom edge fixed
        newY = max(scrn(2) + 10, newY);
        tFig.Position = [pos(1), newY, pos(3), tH_full];
        mainGl.RowHeight = {'1x', '1x'};
        btn.Text = 'Hide Plot ▲';
        btn.BackgroundColor = [0.75 0.15 0.15];
        btn.FontColor = [1 1 1];
        updatePlot(fig);
    else
        % Collapse: shrink window, hide plot row
        pos = tFig.Position;
        tFig.Position = [pos(1), pos(2) + (pos(4) - tH_compact), pos(3), tH_compact];
        mainGl.RowHeight = {0, '1x'};
        btn.Text = 'Show Plot ▼';
        btn.BackgroundColor = [0.2 0.5 0.9];
        btn.FontColor = [1 1 1];
    end
end
function updateHysteresis(fig, field, value)
    appData = fig.UserData; appData.hysteresis.(field) = value; fig.UserData = appData; refreshTableStyles(fig);
end
function copyTableData(fig)
    appData = fig.UserData; if isempty(appData.workingCopy), return; end
    wc = appData.workingCopy;

    fullData = round([wc.Z_up, wc.Z_down]);
    if size(fullData, 1) >= 3
        dataToCopy = fullData(2:end-1, :);
    else
        dataToCopy = fullData;
    end

    % Vectorized: build each row with sprintf, join with newline — no string concat loop
    rows = size(dataToCopy, 1);
    rowStrs = cell(rows, 1);
    for r = 1:rows
        rowStrs{r} = strtrim(sprintf('%.0f\t', dataToCopy(r,:)));
    end
    clipboard('copy', [strjoin(rowStrs, newline), newline]);
    uialert(appData.tableFig, 'Table data copied to clipboard (Rows 2-13, No Pedal %).', 'Success');
end


function tableEditorLower(fig)
% Temporarily lower the Table Editor from alwaysontop so dialogs appear above it.
    appData = fig.UserData;
    if isfield(appData,'tableFig') && hasValidHandle(appData, 'tableFig')
        try
            if strcmp(appData.tableFig.WindowStyle,'alwaysontop')
                appData.tableFig.WindowStyle = 'normal';
                appData.tableFig.UserData = struct('wasOnTop', true);
            end
        catch; end
    end
end

function tableEditorRestore(fig)
% Restore Table Editor to alwaysontop if it was lowered by tableEditorLower.
    appData = fig.UserData;
    if isfield(appData,'tableFig') && hasValidHandle(appData, 'tableFig')
        try
            ud = appData.tableFig.UserData;
            if isstruct(ud) && isfield(ud,'wasOnTop') && ud.wasOnTop
                appData.tableFig.WindowStyle = 'alwaysontop';
                appData.tableFig.UserData = struct('wasOnTop', false);
            end
        catch; end
    end
end

function setTableOnTop(tFig, onTop)
% Toggle Table Editor always-on-top (silently skipped if unsupported on this platform).
    if ~isvalid(tFig), return; end
    try
        if onTop, tFig.WindowStyle = 'alwaysontop';
        else,     tFig.WindowStyle = 'normal'; end
    catch; end
end

function closeTable(mainFig, tFig)
    if ~isempty(mainFig) && isvalid(mainFig) && ~isempty(tFig) && isvalid(tFig)
        try
            appData = mainFig.UserData;
            % Suppress unsaved prompt during Hold & Save Session —
            % edits are held intentionally; Save All handles saving.
            holdActive = isfield(appData,'handles') && isfield(appData.handles,'cbHoldSave') ...
                && isvalid(appData.handles.cbHoldSave) && appData.handles.cbHoldSave.Value;
            if ~holdActive && ~isempty(appData.workingCopy) ...
                    && isfield(appData.workingCopy,'modified') && appData.workingCopy.modified
                sel = uiconfirm(tFig, ...
                    ['Map A has unsaved changes.' newline newline ...
                     'Would you like to save before closing?'], ...
                    'Unsaved Map Changes', ...
                    'Options',       {'Save & Close', 'Discard & Close', 'Cancel'}, ...
                    'DefaultOption', 'Save & Close', ...
                    'CancelOption',  'Cancel', ...
                    'Icon',          'warning');
                if strcmp(sel, 'Cancel'), return;
                elseif strcmp(sel, 'Save & Close')
                    saved = saveModifiedMap(mainFig);
                    if ~saved, return; end
                end
            end
        catch; end
    end

    if ~isempty(mainFig) && isvalid(mainFig)
        try
            appData = mainFig.UserData;
            appData.tableFig      = gobjects(0);
            appData.tableHandle   = gobjects(0);
            appData.infoLabel     = gobjects(0);
            appData.lastSelectedIndices  = [];
            if isfield(appData, 'editorTables'),   appData = rmfield(appData, 'editorTables'); end
            if isfield(appData, 'editorTabGroup'), appData = rmfield(appData, 'editorTabGroup'); end
            if isfield(appData, 'tableAx'),        appData = rmfield(appData, 'tableAx'); end
            mainFig.UserData = appData;
        catch
            % Ignore — main figure may be mid-deletion
        end
    end
    % Delete the table figure only if it still exists
    if ~isempty(tFig) && isvalid(tFig)
        delete(tFig);
    end
end
function onTableEdit(fig, src, event)
    onGenericTableEdit(fig, src, event, 'RPM');
end

function onGenericTableEdit(fig, src, event, type)
    appData = fig.UserData; wc = appData.workingCopy;
    % Guard: only block edits when Map A actually HOLDS a [REF] map (after swap).
    % Ref Mode being ON alone doesn't make the working file's maps read-only —
    % only after a ref map has been swapped INTO the Map A slot.
    isWCRefMap = ~isempty(wc) && isfield(wc,'isRef') && wc.isRef;
    if isWCRefMap
        % Revert the attempted edit in the table
        try
            if ~isempty(event.Indices)
                if iscell(src.Data)
                    src.Data{event.Indices(1), event.Indices(2)} = event.PreviousData;
                else
                    src.Data(event.Indices(1), event.Indices(2)) = event.PreviousData;
                end
            end
        catch; end
        if isfield(appData,'infoLabel') && hasValidHandle(appData, 'infoLabel')
            appData.infoLabel.Text = '<font color="#AA4400"><b>📘 Reference map — view only. Changes are not saved.</b></font>';
        end
        return;
    end
    pushHistory(fig); appData = fig.UserData; wc = appData.workingCopy;
    if isempty(wc), return; end  % guard: no map loaded
    if isempty(event.Indices) || isempty(event.NewData), return; end  % guard: no valid edit
    
    % Determine Conversion Logic based on type
    val = event.NewData;
    
    % We process this relative to the specific column being edited to convert back to RPM
    % Logic needs to handle bulk edit if selectedIndices > 1
    
    selectedIndices = appData.lastSelectedIndices;
    
    % Helper to convert value back to RPM
    function rpmVal = convertToRPM(v, c_idx)
        if c_idx == 1 % Pedal
            rpmVal = v; % No conversion for pedal
            return;
        end
        
        axleRatio = appData.userInputs.AxleRatio;
        is4Lo = isfield(appData, 'handles') && isfield(appData.handles, 'cb4Lo') && isvalid(appData.handles.cb4Lo) && appData.handles.cb4Lo.Value;
        if is4Lo, ratioEff = appData.userInputs.LowRangeRatio * axleRatio; else, ratioEff = axleRatio; end
        if ratioEff == 0, ratioEff = 1; end   % prevent division by zero
        tireCirc = appData.userInputs.TireCircumference / 25.4;
        if tireCirc == 0, tireCirc = 1; end   % prevent division by zero
        gearRatios = appData.userInputs.GearRatios;
        
        if strcmp(type, 'RPM')
            rpmVal = v;
        elseif strcmp(type, 'MPH')
            % MPH = (RPM / ratioEff * tireCirc) / 1056
            % RPM = MPH * 1056 / tireCirc * ratioEff
            rpmVal = v * 1056 / tireCirc * ratioEff;
        elseif strcmp(type, 'KPH')
            mphVal = v / 1.60934;
            rpmVal = mphVal * 1056 / tireCirc * ratioEff;
        elseif strcmp(type, 'Turbine') || strcmp(type, 'Engine')
            % Turbine/Engine = RPM * GearRatio
            % RPM = Turbine / GearRatio
            c_rpm = c_idx - 1;
            if c_rpm <= 7, gearIdx = c_rpm; else, gDown = c_rpm - 7; gearIdx = gDown + 1; end
            
            if gearIdx >= 1 && gearIdx <= length(gearRatios)
                rpmVal = v / gearRatios(gearIdx);
            else
                rpmVal = v; % Should not happen
            end
        end
    end

    % Apply edits
    if size(selectedIndices, 1) > 1
        clickedR = event.Indices(1); clickedC = event.Indices(2); 
        isInside = ismember([clickedR, clickedC], selectedIndices, 'rows');
        
        targetCells = [];
        if isInside
            targetCells = selectedIndices;
        else
            targetCells = [clickedR, clickedC];
        end
        
        for k = 1:size(targetCells, 1)
            r = targetCells(k, 1); c = targetCells(k, 2);
            
            % If multiple cells, we might need to apply the NEW value or relative? 
            % Usually standard table edit applies the typed value to all selected cells.
            
            rpmVal = round(convertToRPM(val, c));
            
            if c == 1, wc.pedal(r) = rpmVal; 
            elseif c <= 8, wc.Z_up(r, c-1) = rpmVal; 
            else, wc.Z_down(r, c-8) = rpmVal; 
            end
        end
    else
        r = event.Indices(1); c = event.Indices(2); 
        rpmVal = round(convertToRPM(val, c));
        
        if c == 1, wc.pedal(r) = rpmVal; 
        elseif c <= 8, wc.Z_up(r, c-1) = rpmVal; 
        else, wc.Z_down(r, c-8) = rpmVal; 
        end
    end
    
    wc = enforceRowConstraints(wc);
    
    wc.modified = true; appData.workingCopy = wc;
    % Sync to session slot
    if isfield(appData,'holdSession') && isstruct(appData.holdSession)
        appData.holdSession.slots.(appData.holdSession.activeSlot) = wc;
    end
    fig.UserData = appData;
    updateTableDisplay(fig);
    updatePlot(fig);
    updateInfoPanel(fig, event.Indices(1), event.Indices(2), val, type);

    % Push edited cell(s) to INCA if Sync is active
    % Re-read from fig.UserData — appData may be stale after updatePlot
    liveAD = fig.UserData;
    if isfield(liveAD,'handles') && isfield(liveAD.handles,'cbSyncINCA') ...
            && isvalid(liveAD.handles.cbSyncINCA) && liveAD.handles.cbSyncINCA.Value
        r0 = event.Indices(1); c0 = event.Indices(2);
        % Read the RPM value directly from wc — already converted and enforced
        % Skip boundary rows (row 1 = pedal 0, last row = pedal 110)
        nRows = size(wc.Z_up, 1);
        if r0 >= 2 && r0 <= nRows-1 && c0 >= 2
            if c0 <= 8
                rpmOut = wc.Z_up(r0, c0-1);
            else
                rpmOut = wc.Z_down(r0, c0-8);
            end
            pushCellToINCA(fig, wc, r0, c0, rpmOut);
        end
    end
end
function onTableSelect(fig, src, event, type)
    if ~isvalid(fig), return; end
    if isempty(event.Indices), return; end
    r = event.Indices(end, 1); c = event.Indices(end, 2);
    appData = fig.UserData; appData.lastSelectedIndices = event.Indices; fig.UserData = appData;
    % Safe cell/numeric access — avoid indexing errors on cell tables
    try
        d = src.Data;
        if iscell(d), val = d{r,c}; else, val = d(r,c); end
        if isempty(val), val = 0; end
    catch
        val = 0;
    end
    updateInfoPanel(fig, r, c, val, type);
end
function refreshTableStyles(fig)
    appData = fig.UserData;
    if isempty(appData) || ~isfield(appData,'workingCopy') || isempty(appData.workingCopy), return; end
    tablesToStyle = {};
    if isfield(appData, 'editorTables') && ~isempty(appData.editorTables)
        % PERFORMANCE: Only style the currently visible table
        activeTabTitle = '';
        if isfield(appData, 'editorTabGroup') && isvalid(appData.editorTabGroup)
            activeTabTitle = appData.editorTabGroup.SelectedTab.Title;
        end
        switch activeTabTitle
            case 'Output RPM', tablesToStyle = {appData.editorTables.RPM};
            case 'MPH', tablesToStyle = {appData.editorTables.MPH};
            case 'KPH', tablesToStyle = {appData.editorTables.KPH};
            case 'Turbine RPM', tablesToStyle = {appData.editorTables.Turbine};
            case 'Engine RPM', tablesToStyle = {appData.editorTables.Engine};
            otherwise, tablesToStyle = {appData.editorTables.RPM};
        end
        % Also include TCC Editor → Turbine RPM duplicate if open (V7.5.6)
        if isfield(appData,'tccFig') && hasValidHandle(appData,'tccFig')
            try
                ad = appData.tccFig.UserData;
                if isfield(ad,'tTurbine') && isvalid(ad.tTurbine)
                    if isempty(tablesToStyle) || ad.tTurbine ~= tablesToStyle{1}
                        tablesToStyle{end+1} = ad.tTurbine;
                    end
                end
            catch; end
        end
    elseif hasValidHandle(appData, 'tableHandle')
        tablesToStyle = {appData.tableHandle};
    else
        return;
    end
    
    wc = appData.workingCopy;
    if isempty(wc), return; end

    % Resolve the original (unedited) map for comparison.
    % During session mode editIndex=-1, so look up by name or use session orig.
    sessionActive = isfield(appData,'handles') && isfield(appData.handles,'cbHoldSave') ...
        && isvalid(appData.handles.cbHoldSave) && appData.handles.cbHoldSave.Value ...
        && isfield(appData,'holdSession') && isstruct(appData.holdSession);

    if sessionActive
        % Use the stored original from the session slot (captured at session start)
        curSlot = appData.holdSession.activeSlot;
        origField = ['orig_' curSlot];
        if isfield(appData.holdSession, origField) && ~isempty(appData.holdSession.(origField))
            origMap = appData.holdSession.(origField);
        else
            % Fallback: look up by name in allMaps
            allN = getMapNames(appData);
            idx = find(allN == string(wc.name), 1);
            if isempty(idx), return; end
            origMap = appData.allMaps{idx};
        end
    elseif isempty(appData.editIndex) || appData.editIndex < 1 || appData.editIndex > length(appData.allMaps)
        return;
    else
        origMap = appData.allMaps{appData.editIndex};
    end
    currDataRPM = [wc.pedal(:), round(wc.Z_up), round(wc.Z_down)];
    origDataRPM = [origMap.pedal(:), round(origMap.Z_up), round(origMap.Z_down)];

    % Calculations for checks
    threshSpeed = appData.hysteresis.Speed; threshMPH = appData.hysteresis.MPH;
    axleRatio = appData.userInputs.AxleRatio; is4Lo = isfield(appData, 'handles') && isfield(appData.handles, 'cb4Lo') && isvalid(appData.handles.cb4Lo) && appData.handles.cb4Lo.Value;
    if is4Lo, ratioEff = appData.userInputs.LowRangeRatio * axleRatio; else, ratioEff = axleRatio; end
    if ratioEff == 0, ratioEff = 1; end   % prevent division by zero
    tireCirc = appData.userInputs.TireCircumference / 25.4;
    if tireCirc == 0, tireCirc = 1; end   % prevent division by zero

    % ── Pedal % column validation (col 1): non-increasing or duplicate values ──
    pedalCol  = currDataRPM(:,1);
    pedalDiff = diff(pedalCol);
    pedalOrangeRows = [];   % non-increasing (decreasing)
    pedalRedRows    = [];   % exact duplicate values

    nonIncr = find(pedalDiff < 0);    % strictly decreasing
    dupe    = find(pedalDiff == 0);   % exact repeat

    if ~isempty(nonIncr)
        pedalOrangeRows = unique([nonIncr; nonIncr+1]);
    end
    if ~isempty(dupe)
        pedalRedRows = unique([dupe; dupe+1]);
    end

    % Diff mask — only compute when sizes match (pedal count may differ after edits)
    rDiff = []; cDiff = [];
    if isequal(size(currDataRPM), size(origDataRPM))
        diffMask = abs(currDataRPM - origDataRPM) > 0.001;
        [rDiff, cDiff] = find(diffMask);
    end
    
    % Cache style objects — creating uistyle is expensive, reuse across calls
    persistent sGray_ sBlue_ sYellow_ sRed_ sMagenta_ sPedalDupe_ sPedalDecr_;
    if isempty(sGray_)
        sGray_      = uistyle('BackgroundColor', [0.7 0.7 0.7]);
        sBlue_      = uistyle('BackgroundColor', [0.9 0.85 1], 'FontWeight', 'bold');
        sYellow_    = uistyle('BackgroundColor', [1 1 0.6]);
        sRed_       = uistyle('BackgroundColor', [1 0 0], 'FontWeight', 'bold', 'FontColor', 'white');
        sMagenta_   = uistyle('BackgroundColor', [1 0 1], 'FontWeight', 'bold');
        sPedalDupe_ = uistyle('BackgroundColor', [1 0 0], 'FontWeight', 'bold', 'FontColor', 'white');
        sPedalDecr_ = uistyle('BackgroundColor', [1 0.5 0], 'FontWeight', 'bold', 'FontColor', 'white');
    end
    sGray=sGray_; sBlue=sBlue_; sYellow=sYellow_; sRed=sRed_; sMagenta=sMagenta_;
    sPedalDupe=sPedalDupe_; sPedalDecr=sPedalDecr_;
    
    nRows = size(currDataRPM, 1);

    % ── Vectorized regression check (no nested for-loops) ───────────────────
    % Upshift cols 2-8: col c should be >= col c-1
    upMat   = currDataRPM(:, 2:8);
    upDiff  = diff(upMat, 1, 2);                        % nRows x 6
    [rU, cU] = find(upDiff < 0);
    % cU maps to column pairs (cU → col cU+1 and cU+2 in currDataRPM)
    redIdxUp = [];
    if ~isempty(rU)
        redIdxUp = [rU, cU+2; rU, cU+1];               % both flagged cols
    end
    % Downshift cols 9-15
    dnMat   = currDataRPM(:, 9:15);
    dnDiff  = diff(dnMat, 1, 2);
    [rD, cD] = find(dnDiff < 0);
    redIdxDn = [];
    if ~isempty(rD)
        redIdxDn = [rD, cD+10; rD, cD+9];
    end

    % ── Vectorized hysteresis check ──────────────────────────────────────────
    upCols  = currDataRPM(:, 2:8);                      % nRows x 7
    dnCols  = currDataRPM(:, 9:15);
    mphUp   = upCols / ratioEff * tireCirc / 1056;
    mphDn   = dnCols / ratioEff * tireCirc / 1056;
    magMask = (mphUp - mphDn) < threshMPH;
    redMask = dnCols >= (upCols - threshSpeed);
    [rM, gM] = find(magMask);
    magIdx = [];
    if ~isempty(rM)
        magIdx = [rM, gM+1; rM, gM+8];                 % upshift col and downshift col
    end
    [rR2, gR2] = find(redMask);
    redIdxHyst = [];
    if ~isempty(rR2)
        redIdxHyst = [rR2, gR2+1; rR2, gR2+8];
    end

    redIdx = unique([redIdxUp; redIdxDn; redIdxHyst], 'rows');
    magIdx = unique(magIdx, 'rows');
    
    % Apply to each table
    for tIdx = 1:length(tablesToStyle)
        t = tablesToStyle{tIdx};
        if ~isvalid(t), continue; end
        removeStyle(t);
        
        addStyle(t, sGray, 'row', [1, nRows]);
        addStyle(t, sBlue, 'column', 1);
        
        % Pedal % errors — applied in priority order (red overwrites orange)
        % Orange: pedal value is decreasing (non-monotonic)
        if ~isempty(pedalOrangeRows)
            addStyle(t, sPedalDecr, 'cell', [pedalOrangeRows, ones(numel(pedalOrangeRows),1)]);
        end
        % Red: pedal value is an exact duplicate of previous row
        if ~isempty(pedalRedRows)
            addStyle(t, sPedalDupe, 'cell', [pedalRedRows, ones(numel(pedalRedRows),1)]);
        end
        
        if ~isempty(rDiff), addStyle(t, sYellow, 'cell', [rDiff, cDiff]); end
        
        if ~isempty(redIdx), addStyle(t, sRed, 'cell', redIdx); end
        if ~isempty(magIdx), addStyle(t, sMagenta, 'cell', magIdx); end
    end
end
function updateInfoPanel(fig, r, c, currentVal, type)
    if nargin < 5, type = 'RPM'; end
    appData = fig.UserData; if ~hasValidHandle(appData, 'infoLabel'), return; end
    
    wc = appData.workingCopy; 
    
    % Get RPM from working copy (which is always up to date)
    if c == 1
        rpmVal = wc.pedal(r);
    elseif c <= 8
        rpmVal = wc.Z_up(r, c-1);
    else
        rpmVal = wc.Z_down(r, c-8);
    end
    
    % Calculate all Units
    calcRPM = rpmVal;
    calcTurbine = 0; calcMPH = 0; calcKPH = 0;
    origRPM = 0; origTurbine = 0; origMPH = 0; origKPH = 0;
    
    pedal = wc.pedal(r);
    % Guard: editIndex must be valid before accessing allMaps
    if isempty(appData.editIndex) || appData.editIndex < 1 || appData.editIndex > length(appData.allMaps)
        appData.infoLabel.Text = '<b>Select a cell.</b>';
        return;
    end
    origMap = appData.allMaps{appData.editIndex};
    
    if c == 1
        origVal = origMap.pedal(r); 
        txt = sprintf('<font size="4"><b>Pedal Point</b></font><br>Old: %.1f<br>New: %.1f', origVal, currentVal); 
        appData.infoLabel.Text = txt; 
        return; 
    end
    
    c_rpm = c - 1; 
    if c_rpm <= 7
        origRPM = origMap.Z_up(r, c_rpm); 
        label = sprintf('Upshift %d->%d', c_rpm, c_rpm+1); 
        gearIdx = c_rpm; 
    else
        gDown = c_rpm - 7; 
        origRPM = origMap.Z_down(r, gDown); 
        gearIdx = gDown + 1; 
        label = sprintf('Downshift %d->%d', gearIdx, gearIdx-1); 
    end
    
    gearRatios = appData.userInputs.GearRatios; 
    is4Lo = isfield(appData, 'handles') && isfield(appData.handles, 'cb4Lo') && isvalid(appData.handles.cb4Lo) && appData.handles.cb4Lo.Value;
    if is4Lo, modeStr = '<font color="green"><b>ACTIVE</b></font>'; else, modeStr = '<font color="black">Not Active</font>'; end
    
    if gearIdx >= 1 && gearIdx <= length(gearRatios)
        ratio = gearRatios(gearIdx);
        axleRatio = appData.userInputs.AxleRatio;
        if is4Lo, ratioEff = appData.userInputs.LowRangeRatio * axleRatio; else, ratioEff = axleRatio; end
        if ratioEff == 0, ratioEff = 1; end
        tireCirc = appData.userInputs.TireCircumference / 25.4;
        if tireCirc == 0, tireCirc = 1; end
        
        calcTurbine = calcRPM * ratio;
        calcMPH = (calcRPM / ratioEff * tireCirc) / 1056; 
        calcKPH = calcMPH * 1.60934;
        
        origTurbine = origRPM * ratio;
        origMPH = (origRPM / ratioEff * tireCirc) / 1056;
        origKPH = origMPH * 1.60934;
    end
    
    % Determine Display Values based on Type
    origDisplay = 0;
    newDisplay = currentVal; % currentVal matches the type passed in
    
    % Physics Lines
    physLine1 = ''; physLine2 = ''; physLine3 = '';
    
    switch type
        case 'RPM'
            origDisplay = origRPM;
            newDisplay = calcRPM;
            physLine1 = sprintf('Turbine: %.0f', calcTurbine);
            physLine2 = sprintf('MPH: %.2f', calcMPH);
            physLine3 = sprintf('KPH: %.2f', calcKPH);
        case 'MPH'
            origDisplay = origMPH;
            newDisplay = calcMPH; 
            physLine1 = sprintf('Output RPM: %.0f', calcRPM);
            physLine2 = sprintf('Turbine: %.0f', calcTurbine);
            physLine3 = sprintf('KPH: %.2f', calcKPH);
        case 'KPH'
            origDisplay = origKPH;
            newDisplay = calcKPH;
            physLine1 = sprintf('Output RPM: %.0f', calcRPM);
            physLine2 = sprintf('Turbine: %.0f', calcTurbine);
            physLine3 = sprintf('MPH: %.2f', calcMPH);
        case 'Turbine'
            origDisplay = origTurbine;
            newDisplay = calcTurbine;
            physLine1 = sprintf('Output RPM: %.0f', calcRPM);
            physLine2 = sprintf('MPH: %.2f', calcMPH);
            physLine3 = sprintf('KPH: %.2f', calcKPH);
        case 'Engine'
            origDisplay = origTurbine; % Engine ~ Turbine
            newDisplay = calcTurbine;
            physLine1 = sprintf('Output RPM: %.0f', calcRPM);
            physLine2 = sprintf('MPH: %.2f', calcMPH);
            physLine3 = sprintf('KPH: %.2f', calcKPH);
    end
    
    delta = newDisplay - origDisplay;
    
    fmt = '%.0f';
    if strcmp(type, 'MPH') || strcmp(type, 'KPH'), fmt = '%.2f'; end
    
    origStr = sprintf(['<font color="blue"><b>' fmt '</b></font>'], origDisplay); 
    newStr = sprintf(['<font color="red"><b>' fmt '</b></font>'], newDisplay);
    
    if delta > 0, diffStr = sprintf(['<font color="green">(+' fmt ')</font>'], delta); 
    elseif delta < 0, diffStr = sprintf(['<font color="#D4AC0D">(' fmt ')</font>'], delta); 
    else, diffStr = '<font color="gray">(0)</font>'; end
    
    txt = sprintf(['<font size="4"><b>%s</b></font><br>Pedal: %.1f%%<br><br>Original: %s<br>New: %s %s<br>4Lo: %s<br><br>' ...
                   '<u>Physics:</u><br>%s<br>%s<br>%s'], ...
                   label, pedal, origStr, newStr, diffStr, modeStr, physLine1, physLine2, physLine3); 
    appData.infoLabel.Text = txt;
end
function success = saveModifiedMap(fig)
    appData = fig.UserData;
    % Guard: cannot save a reference map (only when Map A actually holds a [REF] map)
    wc = appData.workingCopy;
    isWCRefMap = ~isempty(wc) && isfield(wc,'isRef') && wc.isRef;
    if isWCRefMap
        uialert(fig, 'Reference maps are view-only and cannot be saved.', 'Read-Only', 'Icon','warning');
        success = false; return;
    end
    if isempty(appData.workingCopy) || ~isfield(appData.workingCopy, 'modified') || ~appData.workingCopy.modified, uialert(fig, 'No modifications.', 'Info'); success = true; return; end
    wc = appData.workingCopy; msg = sprintf('Overwrite "%s" or create new?', wc.name);
    toggleTablePriority(fig, true); selection = uiconfirm(fig, msg, 'Save', 'Options', {'Overwrite Original', 'Save as New', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 3); toggleTablePriority(fig, false);
    success = false;
    if strcmp(selection, 'Overwrite Original')
        idx = appData.editIndex;
        % During session mode editIndex=-1; resolve by name instead
        if idx < 1
            allN = getMapNames(appData);
            idx = find(allN == string(wc.name), 1);
        end
        if ~isempty(idx) && idx > 0
            wc.modified = false;
            appData.allMaps{idx}  = wc;
            appData.workingCopy   = wc;   % ← keeps working copy in sync, clears modified flag
            appData.history = {};
            % Keep name cache in sync (name could have been changed)
            if isfield(appData,'allMapNames'), appData.allMapNames(idx) = string(wc.name); end
            % Log to session history
            if ~isfield(appData,'sessionLog'), appData.sessionLog = {}; end
            appData.sessionLog{end+1} = {char(datetime('now','Format','yyyy-MM-dd HH:mm')), char(wc.name), 'Overwritten'};
            fig.UserData = appData; refreshTableStyles(fig); uialert(fig,'Saved.','Saved'); success = true;
        else, success = saveAsNew(fig); end
    elseif strcmp(selection, 'Save as New'), success = saveAsNew(fig); end
end
function success = saveAsNew(fig)
    appData = fig.UserData; wc = appData.workingCopy; defaultName = wc.name + "_MOD";
    toggleTablePriority(fig, true); answer = inputdlg('Name:', 'Save As', [1 50], {char(defaultName)}); toggleTablePriority(fig, false);
    if isempty(answer), success = false; return; end
    newName = string(answer{1}); wc.name = newName; wc.modified = false; appData.allMaps{end+1} = wc;
    % Rebuild cache safely
    existingNames = getMapNames(appData);
    appData.allMapNames = [existingNames(:); string(newName)];
    allNamesNow = appData.allMapNames(:);
    origNamesNow = cellstr(allNamesNow(~startsWith(allNamesNow,'[REF]')));
    newNames = cellstr(allNamesNow);
    appData.editIndex = length(appData.allMaps);
    appData.workingCopy = wc;
    appData.history = {};
    if ~isfield(appData,'sessionLog'), appData.sessionLog = {}; end
    appData.sessionLog{end+1} = {char(datetime('now','Format','yyyy-MM-dd HH:mm')), char(newName), 'Saved as New'};

    % Update dropdowns with swapping guard so no callbacks fire during Items change
    appData.swapping = true;
    fig.UserData = appData;
    appData.handles.dd1.Items = origNamesNow;   % dd1: originals only (no [REF])
    % dd2: in ref mode stay as [REF] items; otherwise all maps
    if isfield(appData,'isRefMode') && appData.isRefMode && ...
            isfield(appData,'refItemsAll') && ~isempty(appData.refItemsAll)
        appData.handles.dd2.Items = cellstr(appData.refItemsAll(:));
    else
        appData.handles.dd2.Items = newNames;
    end
    if isfield(appData.handles,'dd3') && isvalid(appData.handles.dd3)
        appData.handles.dd3.Items = newNames;
    end
    % During session: keep dd1 pointing at the session map, not the new name
    isSession = isfield(appData,'holdSession') && isstruct(appData.holdSession);
    if ~isSession && ismember(string(newName), string(origNamesNow))
        appData.handles.dd1.Value = newName;
    end
    appData.swapping = false;
    if hasValidHandle(appData, 'tableFig')
        appData.tableFig.Name = ['Table: ' char(wc.name)];
        refreshTableStyles(fig);
    end
    fig.UserData = appData; uialert(fig, 'Saved.', 'Success'); success = true;
end
function txt = getShiftInfoText(rpm, pedal, label, gearIdx, appData, is4Lo, origRPM, origPedal)
    if nargin < 7 || isempty(origRPM), origRPM = rpm; end
    if nargin < 8 || isempty(origPedal), origPedal = pedal; end

    % Ensure scalar doubles
    rpm = double(rpm(1)); pedal = double(pedal(1));
    origRPM = double(origRPM(1)); origPedal = double(origPedal(1));

    gearRatios = appData.userInputs.GearRatios; axleRatio = appData.userInputs.AxleRatio; tireCirc = appData.userInputs.TireCircumference / 25.4;
    if tireCirc == 0, tireCirc = 1; end   % prevent division by zero
    if is4Lo, ratioEff = appData.userInputs.LowRangeRatio * axleRatio; else, ratioEff = axleRatio; end
    if ratioEff == 0, ratioEff = 1; end
    if tireCirc  == 0, tireCirc  = 1; end
    
    function [turb, mph, kph] = calcVals(r, gIdx)
        turb = 0; mph = 0; kph = 0;
        if gIdx >= 1 && gIdx <= length(gearRatios)
            turb = r * gearRatios(gIdx);
            mph = (r / ratioEff * tireCirc) / 1056;
            kph = mph * 1.60934;
        end
    end

    [turb, mph, kph] = calcVals(rpm, gearIdx);
    [oTurb, oMph, oKph] = calcVals(origRPM, gearIdx);

    cBlack = '\color{black}';
    cGreen = '\color[rgb]{0,0.5,0}';
    cBlue  = '\color{blue}';
    cRed   = '\color{red}';

    function str = fmtLine(name, cur, orig, isPct, isInt)
        diffVal = cur - orig;

        if isInt
            cur = round(cur); orig = round(orig); diffVal = round(diffVal);
            fmt = '%.0f';
        else
            fmt = '%.1f';
        end

        if isPct, suffix = '%'; else, suffix = ''; end

        % Diff column (last): blue = positive, red = negative, black = zero
        if diffVal > 0.001
            diffStr = sprintf(['%s(+' fmt '%s)%s'], cBlue, diffVal, suffix, cBlack);
        elseif diffVal < -0.001
            diffStr = sprintf(['%s(' fmt '%s)%s'], cRed, diffVal, suffix, cBlack);
        else
            diffStr = sprintf('%s(0)', cBlack);
        end

        % Name=black, Current=green (live value), Original=black, Diff=blue/red
        sName = sprintf('%-5s', name);
        sCur  = sprintf('%7s', sprintf([fmt '%s'], cur,  suffix));
        sOrig = sprintf('%7s', sprintf([fmt '%s'], orig, suffix));

        str = sprintf('%s%s %s%s %s%s %s', ...
            cBlack, sName, cGreen, sCur, cBlack, sOrig, diffStr);
    end

    l1 = sprintf('\\bf%s', label);
    l2 = fmtLine('Pdl %', pedal, origPedal, true, false);
    l3 = fmtLine('O RPM', rpm, origRPM, false, true);
    l4 = fmtLine('Tbr  ', turb, oTurb, false, true);
    l5 = fmtLine('MPH  ', mph, oMph, false, false);
    l6 = fmtLine('KPH  ', kph, oKph, false, false);

    txt = sprintf('%s\n%s\n%s\n%s\n%s\n%s', l1, l2, l3, l4, l5, l6);
end
function exportModifiedMaps(fig)
    appData = fig.UserData;
    if isempty(appData.workingCopy), uialert(fig, 'No active map to export.', 'Info'); return; end
    m = appData.workingCopy;

    % Ask user where to save
    [file, path] = uiputfile('*.xlsx', 'Export Shift Map As', 'Shift_Maps_Export.xlsx');
    if isequal(file, 0), return; end
    fn = fullfile(path, file);

    % Excel sheet names are limited to 31 characters
    rawName = char(m.name);
    if length(rawName) > 31
        sheetName = rawName(1:31);
    else
        sheetName = rawName;
    end

    T1 = array2table(m.Z_up,    'VariableNames', compose("Upshift_%d",   1:7));
    T2 = array2table(m.Z_down,  'VariableNames', compose("Downshift_%d", 1:7));
    T3 = array2table(m.pedal(:), 'VariableNames', {'Pedal'});
    try
        writetable([T3 T1 T2], fn, 'Sheet', sheetName);
        uialert(fig, sprintf('Exported to:\n%s', fn), 'Success');
    catch ME
        uialert(fig, sprintf('Export failed:\n%s', ME.message), 'Export Error');
    end
end
function exportAllDCM(fig)
    appData = fig.UserData;
    if isempty(appData.allMaps), uialert(fig,'No maps available.','Error'); return; end
    [file, path] = uiputfile('*.dcm','Save DCM File','Shift_Maps.dcm');
    if isequal(file,0), return; end
    fullPath = fullfile(path,file);
    fid = fopen(fullPath,'w');
    if fid==-1, uialert(fig,'Could not open file for writing.','Error'); return; end

    try
        % ── HEADER ────────────────────────────────────────────────────────────
        fprintf(fid,'* DAMOS format\r\n');
        fprintf(fid,'* Created by 8HP Pattern Plotter\r\n');
        fprintf(fid,'* Creation date:                 %s\r\n', ...
            char(datetime('now','Format','M/d/yyyy')));
        fprintf(fid,'*\r\n');
        fprintf(fid,'* Project: Unknown\r\n');
        fprintf(fid,'* Dataset: Unknown\r\n\r\n');
        fprintf(fid,'KONSERVIERUNG_FORMAT 2.0\r\n\r\n');
        fprintf(fid,'* Address EPK: 0x190100\r\n');
        fprintf(fid,'* Memory segments:\r\n');
        fprintf(fid,'*  Dst190000 DATA INTERN 0x190000 0x6FFFF\r\n\r\n\r\n');

        % ── FUNKTIONEN ────────────────────────────────────────────────────────
        fprintf(fid,'FUNKTIONEN\r\n');
        fprintf(fid,'   FKT jFsitDaten_Fktn "" "Calibration values of the Instance jFsitDaten"\r\n');
        fprintf(fid,'   FKT jFzggDaten_Fktn "" "Calibration values of the Instance jFzggDaten"\r\n');
        fprintf(fid,'   FKT jSklDaten_Fktn "" "Calibration values of the Instance jSklDaten"\r\n');
        fprintf(fid,'   FKT jWtDaten_Fktn "" "Calibration values of the Instance jWtDaten"\r\n');
        fprintf(fid,'END\r\n\r\n');

        % ── FSIT switches (scalar values from CSV) ────────────────────────────
        if isfield(appData,'T') && ~isempty(appData.T)
            T = appData.T;
            fsitVars = {'FSIT_SWIALT','FSIT_SWIFCO','FSIT_SWIFO','FSIT_SWIKE', ...
                'FSIT_SWIDSD','FSIT_SWIBA','FSIT_SWIBE','FSIT_SWIHM','FSIT_SWISUS', ...
                'FSIT_SWIZW','FSIT_SWIVSA','FSIT_SWIECO','FSIT_SWICM','FSIT_SWIWA', ...
                'FSIT_SWISNG','FSIT_SWIEVA','FSIT_SWIOD','FSIT_SWIREV'};
            % Use getFSITDesc (persistent map, built once) — avoids rebuilding here
            sCol2 = strtrim(string(T.Var2));
            for fv = 1:length(fsitVars)
                vn = fsitVars{fv};
                rIdx = find(strcmpi(sCol2, vn), 1);
                if ~isempty(rIdx)
                    for r2 = rIdx+1:min(rIdx+5,height(T))
                        raw = T{r2,3:end};
                        if iscell(raw), raw = raw(~cellfun(@isempty,raw));
                            if ~isempty(raw), v = str2double(string(raw{1})); else, continue; end
                        else, v = str2double(string(raw(1))); end
                        if ~isnan(v)
                            desc = getFSITDesc(vn);
                            dcmFestWert(fid, vn, v, '-', 'jFsitDaten_Fktn', desc);
                            break;
                        end
                    end
                end
            end
        end

        % ── FZGG_RDYN (tire radius) ───────────────────────────────────────────
        if isfield(appData,'userInputs') && isfield(appData.userInputs,'DynamicCircumference')
            dcmFestWert(fid,'FZGG_RDYN', appData.userInputs.DynamicCircumference, ...
                'mm','jFzggDaten_Fktn','Tire radius');
        end

        % ── SKL SHIFT MAPS ────────────────────────────────────────────────────
        colLbls = {'"US12"','"US23"','"US34"','"US45"','"US56"','"US67"','"US78"', ...
                   '"DS21"','"DS32"','"DS43"','"DS54"','"DS65"','"DS76"','"DS87"'};
        for i = 1:length(appData.allMaps)
            map = appData.allMaps{i};
            % Extract map number from name for LANGNAME
            tok = regexp(char(map.name),'SKL_GKF_(\d+)','tokens');
            if ~isempty(tok), mapID = str2double(tok{1}{1}); else, mapID = i-1; end
            dcmKennfeld(fid, char(map.name), colLbls, map.pedal, ...
                [map.Z_up, map.Z_down], '', '%', '1/min', 'jSklDaten_Fktn', ...
                sprintf('Shifting characteristic curves (ID==%d)', mapID));
        end

        % ── WT_ZUSTAND (FESTKENNLINIE) ────────────────────────────────────────
        if isfield(appData,'wtZustand') && ~isempty(appData.wtZustand)
            wtz = appData.wtZustand;
            if size(wtz,1)==2
                xV = wtz(1,:); wV = wtz(2,:);
            else
                xV = 0:size(wtz,2)-1; wV = wtz(1,:);
            end
            dcmFestKennlinie(fid,'WT_ZUSTAND',xV,wV,'-','-','jWtDaten_Fktn', ...
                'Determines line of WT_KWK_ZTAB for current driving program');
        end

        % ── WT_KWK_ZTAB (FESTKENNFELD) ────────────────────────────────────────
        if isfield(appData,'kwkData') && ~isempty(appData.kwkData)
            kwk = appData.kwkData;
            nKR = size(kwk,1); nKC = size(kwk,2);
            xAxis = 1:nKC; yAxis = 0:nKR-1;
            dcmFestKennfeld(fid,'WT_KWK_ZTAB',xAxis,yAxis,kwk,'-','-','-', ...
                'jWtDaten_Fktn','State table for WK shifting characteristics selection');
        end

        % ── WT_NWK maps (KENNFELD with text axis) ────────────────────────────
        if isfield(appData,'nwkMaps') && ~isempty(appData.nwkMaps)
            for mn = 1:length(appData.nwkMaps)
                nm = appData.nwkMaps(mn);
                if isempty(nm.data), continue; end
                % Build text labels from headers
                nCols = size(nm.data,2);
                if ~isempty(nm.headers) && numel(nm.headers)==nCols
                    txtLbls = arrayfun(@(h) sprintf('"%s"',char(h)), nm.headers, ...
                        'UniformOutput',false);
                else
                    txtLbls = arrayfun(@(c) sprintf('"%d"',c), 1:nCols, ...
                        'UniformOutput',false);
                end
                varN = strrep(char(nm.name),' ','_');
                langN = sprintf('WK-shifting characteristics (%s)', char(nm.name));
                dcmKennfeld(fid, varN, txtLbls, nm.yAxis(:)', nm.data, ...
                    '', '%', '1/min', 'jWtDaten_Fktn', langN);
            end
        end

        fclose(fid);
        nM = length(appData.allMaps);
        uialert(fig, sprintf('DCM Export Complete.\n\n%d SKL maps + FSIT + WT_ZUSTAND + WT_KWK_ZTAB + NWK curves\n\nFile: %s', ...
            nM, fullPath), 'Export Complete','Icon','success');

    catch ME
        try, fclose(fid); catch, end
        uialert(fig, sprintf('DCM Export failed:\n%s\n\nLine: %d', ME.message, ME.stack(1).line), ...
            'Export Error','Icon','error');
    end
end

% ── DCM helper: format a number as DAMOS %16g ────────────────────────────────
function s = dcmNum(v)
    s = sprintf('%16g', v);
end

% ── Write values 6 per line with given keyword (WERT, ST/X etc.) ──────────────
function dcmVals(fid, keyword, vals)
    n = numel(vals);
    for k = 1:n
        if mod(k-1,6)==0
            if k>1, fprintf(fid,'\r\n'); end
            fprintf(fid,'   %s', keyword);
        end
        fprintf(fid,'%s', dcmNum(vals(k)));
    end
    fprintf(fid,'\r\n');
end

% ── Write text labels 6 per line ─────────────────────────────────────────────
function dcmTxtVals(fid, keyword, lbls)
    n = numel(lbls);
    for k = 1:n
        if mod(k-1,6)==0
            if k>1, fprintf(fid,'\r\n'); end
            fprintf(fid,'   %s', keyword);
        end
        fprintf(fid,'  %s', lbls{k});
    end
    fprintf(fid,'\r\n');
end

% ── FESTWERT (scalar) ─────────────────────────────────────────────────────────
function dcmFestWert(fid, name, val, unit, fkt, desc)
    fprintf(fid,'FESTWERT %s\r\n', name);
    if ~isempty(desc), fprintf(fid,'   LANGNAME "%s"\r\n', desc); end
    fprintf(fid,'   FUNKTION %s\r\n', fkt);
    fprintf(fid,'   EINHEIT_W "%s"\r\n', unit);
    fprintf(fid,'   WERT%s\r\n', dcmNum(val));
    fprintf(fid,'END\r\n\r\n');
end

% ── FESTKENNLINIE (1D fixed curve) ────────────────────────────────────────────
function dcmFestKennlinie(fid, name, xVals, wVals, xUnit, wUnit, fkt, desc)
    n = numel(xVals);
    fprintf(fid,'FESTKENNLINIE %s %d\r\n', name, n);
    if ~isempty(desc), fprintf(fid,'   LANGNAME "%s"\r\n', desc); end
    fprintf(fid,'   FUNKTION %s\r\n', fkt);
    fprintf(fid,'   EINHEIT_X "%s"\r\n', xUnit);
    fprintf(fid,'   EINHEIT_W "%s"\r\n', wUnit);
    dcmVals(fid,'ST/X', xVals);
    dcmVals(fid,'WERT', wVals);
    fprintf(fid,'END\r\n\r\n');
end

% ── FESTKENNFELD (2D fixed map) ───────────────────────────────────────────────
function dcmFestKennfeld(fid, name, xAxis, yAxis, data, xUnit, yUnit, wUnit, fkt, desc)
    nCols = numel(xAxis); nRows = min(numel(yAxis), size(data,1));
    fprintf(fid,'FESTKENNFELD %s %d %d\r\n', name, nCols, nRows);
    if ~isempty(desc), fprintf(fid,'   LANGNAME "%s"\r\n', desc); end
    fprintf(fid,'   FUNKTION %s\r\n', fkt);
    fprintf(fid,'   EINHEIT_X "%s"\r\n', xUnit);
    fprintf(fid,'   EINHEIT_Y "%s"\r\n', yUnit);
    fprintf(fid,'   EINHEIT_W "%s"\r\n', wUnit);
    dcmVals(fid,'ST/X', xAxis);
    for r = 1:nRows
        fprintf(fid,'   ST/Y%s\r\n', dcmNum(yAxis(r)));
        dcmVals(fid,'WERT', data(r,1:min(end,nCols)));
    end
    fprintf(fid,'END\r\n\r\n');
end

% ── KENNFELD (2D map with text or numeric X labels) ───────────────────────────
function dcmKennfeld(fid, name, xLabels, yAxis, data, xUnit, yUnit, wUnit, fkt, desc)
    nCols = numel(xLabels); nRows = min(numel(yAxis), size(data,1));
    fprintf(fid,'KENNFELD %s %d %d\r\n', name, nCols, nRows);
    if ~isempty(desc), fprintf(fid,'   LANGNAME "%s"\r\n', desc); end
    fprintf(fid,'   FUNKTION %s\r\n', fkt);
    fprintf(fid,'   EINHEIT_X "%s"\r\n', xUnit);
    fprintf(fid,'   EINHEIT_Y "%s"\r\n', yUnit);
    fprintf(fid,'   EINHEIT_W "%s"\r\n', wUnit);
    if isnumeric(xLabels)
        dcmVals(fid,'ST_TX/X',xLabels);
    else
        dcmTxtVals(fid,'ST_TX/X',xLabels);
    end
    for r = 1:nRows
        fprintf(fid,'   ST/Y%s\r\n', dcmNum(yAxis(r)));
        dcmVals(fid,'WERT', data(r,1:min(end,nCols)));
    end
    fprintf(fid,'END\r\n\r\n');
end


function userInputs = promptGearData(defaultData, savePath)
    try
        if nargin < 2, savePath = ''; end
        presets.GEN4 = [5.500; 3.520; 2.200; 1.720; 1.301; 1.000; 0.833; 0.640]; presets.GEN2 = [4.714; 3.143; 2.100; 1.670; 1.290; 1.000; 0.840; 0.667]; presets.Powerline = [4.890; 3.123; 2.033; 1.639; 1.254; 1.000; 0.840; 0.639];
        if isempty(defaultData.GearRatios), activeRatios = presets.GEN4; else, activeRatios = defaultData.GearRatios(:); end
        
        d = uifigure('Position', [300, 300, 520, 500], 'Name', 'Select Gear Ratios', 'WindowStyle', 'modal');
        gl = uigridlayout(d, [4, 1]); 
        gl.RowHeight = {50, '1x', 160, 50};
        gl.Padding = [10 10 10 10];
        gl.RowSpacing = 10;
        
        % --- Row 1: Radio Buttons (Must use uibuttongroup for older runtimes compatibility) ---
        bg = uibuttongroup(gl, 'BorderType', 'none', 'BackgroundColor', [0.94 0.94 0.94]);
        bg.Layout.Row = 1; bg.Layout.Column = 1;
        
        % Manual positioning within ButtonGroup because uiradiobutton must be direct child
        % Assumes width ~500px.
        uiradiobutton(bg, 'Text', 'GEN4', 'Position', [20 15 60 22], 'Tag', 'GEN4', 'FontWeight', 'bold');
        uiradiobutton(bg, 'Text', 'GEN2', 'Position', [100 15 60 22], 'Tag', 'GEN2', 'FontWeight', 'bold');
        uiradiobutton(bg, 'Text', 'Powerline', 'Position', [180 15 90 22], 'Tag', 'Powerline', 'FontWeight', 'bold');
        uiradiobutton(bg, 'Text', 'Enter New Ratios', 'Position', [290 15 150 22], 'Tag', 'Custom', 'FontWeight', 'bold');
        
        % --- Row 2: Table ---
        tableData = [presets.GEN4, presets.GEN2, presets.Powerline, activeRatios]; 
        colNames = {'GEN4', 'GEN2', 'Powerline', 'Ratios In use'};
        
        t = uitable(gl, 'Data', tableData, 'ColumnName', colNames, ...
            'RowName', {'1st','2nd','3rd','4th','5th','6th','7th','8th'}, ...
            'ColumnEditable', [false false false true], ...
            'Tag', 'gt');
        t.Layout.Row = 2; t.Layout.Column = 1;
        
        % Connect Radio Button Logic
        bg.SelectionChangedFcn = @(src, event) updateTableValues(t, event.NewValue.Tag, presets);
        
        % --- Row 3: Inputs ---
        inpGrid = uigridlayout(gl, [4, 4]);
        inpGrid.Layout.Row = 3; inpGrid.Layout.Column = 1;
        inpGrid.ColumnWidth = {'fit', '1x', 'fit', '1x'};
        inpGrid.RowHeight = {'fit', 'fit', 'fit', 'fit'};
        inpGrid.RowSpacing = 5;
        inpGrid.ColumnSpacing = 10;
        
        % Labels (Col 1 & 3)
        l1 = uilabel(inpGrid, 'Text', 'Tire Radius (mm):', 'HorizontalAlignment', 'right');
        l1.Layout.Row=1; l1.Layout.Column=1;
        
        dc = uieditfield(inpGrid, 'numeric', 'Value', defaultData.DynamicCircumference);
        dc.Layout.Row=1; dc.Layout.Column=2;
        
        l2 = uilabel(inpGrid, 'Text', 'Idle RPM:', 'HorizontalAlignment', 'right');
        l2.Layout.Row=1; l2.Layout.Column=3;
        
        idR = uieditfield(inpGrid, 'numeric', 'Value', defaultData.IdleRPM);
        idR.Layout.Row=1; idR.Layout.Column=4;
        
        l3 = uilabel(inpGrid, 'Text', 'Axle Ratio:', 'HorizontalAlignment', 'right');
        l3.Layout.Row=2; l3.Layout.Column=1;
        
        ar = uieditfield(inpGrid, 'numeric', 'Value', defaultData.AxleRatio);
        ar.Layout.Row=2; ar.Layout.Column=2;
        
        l4 = uilabel(inpGrid, 'Text', 'Max RPM:', 'HorizontalAlignment', 'right');
        l4.Layout.Row=2; l4.Layout.Column=3;
        
        mxR = uieditfield(inpGrid, 'numeric', 'Value', defaultData.MaxRPM);
        mxR.Layout.Row=2; mxR.Layout.Column=4;
        
        l5 = uilabel(inpGrid, 'Text', '4Lo Ratio:', 'HorizontalAlignment', 'right');
        l5.Layout.Row=3; l5.Layout.Column=1;
        
        lo = uieditfield(inpGrid, 'numeric', 'Value', defaultData.LowRangeRatio);
        lo.Layout.Row=3; lo.Layout.Column=2;
        
        % Spacer labels not needed if we just place things correctly
        
        l6 = uilabel(inpGrid, 'Text', 'Tire Circ (mm):', 'HorizontalAlignment', 'right');
        l6.Layout.Row=4; l6.Layout.Column=1;
        
        tc = uieditfield(inpGrid, 'numeric', 'Value', defaultData.TireCircumference);
        tc.Layout.Row=4; tc.Layout.Column=2;
        
        % --- Row 4: OK Button & Save Default ---
        btnPnl = uigridlayout(gl, [1, 4]);
        btnPnl.Layout.Row = 4; btnPnl.Layout.Column = 1;
        btnPnl.ColumnWidth = {'1x', 100, 120, '1x'}; % Spacer, OK, Checkbox, Spacer
        btnPnl.Padding = [0 0 0 0];
        
        btnOK = uibutton(btnPnl, 'Text', 'OK', 'BackgroundColor', [0.6 1 0.6], 'FontWeight', 'bold', ...
            'ButtonPushedFcn', @(~,~) uiresume(d));
        btnOK.Layout.Row = 1; btnOK.Layout.Column = 2;
        
        cbSaveDefault = uicheckbox(btnPnl, 'Text', 'Save as Default', 'Value', false);
        cbSaveDefault.Layout.Row = 1; cbSaveDefault.Layout.Column = 3;
        
        if isempty(savePath)
            cbSaveDefault.Visible = 'off';
        end
            
        uiwait(d); 
        
        if ~isvalid(d)
            error('User cancelled gear data input.');
        end
        
        % Extract Data
        finalRatios = t.Data(:, 4); 
        userInputs.GearRatios = finalRatios';
        userInputs.DynamicCircumference = dc.Value; 
        userInputs.AxleRatio = ar.Value;
        userInputs.LowRangeRatio = lo.Value; 
        userInputs.TireCircumference = tc.Value; 
        userInputs.IdleRPM = idR.Value; 
        userInputs.MaxRPM = mxR.Value;
        
        % Save defaults if requested
        if ~isempty(savePath) && cbSaveDefault.Value
            try
                save(savePath, 'userInputs');
            catch
                % Silently ignore save errors
            end
        end
        
        delete(d);
        
    catch ME
        % Handle errors gracefully — 'fig' is not in scope here; use d if still valid
        if exist('d','var') && ~isempty(d) && isvalid(d)
            delete(d);
        end
        % Re-throw so loadFromCSV can catch it and abort cleanly
        rethrow(ME);
    end
end
function updateTableValues(t, selectedTag, presets)
    d = t.Data; switch selectedTag, case 'GEN4', d(:, 4) = presets.GEN4; case 'GEN2', d(:, 4) = presets.GEN2; case 'Powerline', d(:, 4) = presets.Powerline; end
    t.Data = d;
end
function val = safeToNum(x)
    if ismissing(x), val = 0; return; end
    if iscell(x), x = x{1}; end
    val = str2double(string(x)); if isnan(val), val = 0; end
end
function out = getMapNames(ad)
% Safe accessor for allMapNames cache — always returns Nx1 column string array.
    if isfield(ad,'allMapNames') && ~isempty(ad.allMapNames)
        out = ad.allMapNames(:);
    elseif isfield(ad,'allMaps') && ~isempty(ad.allMaps)
        out = string(cellfun(@(m) m.name, ad.allMaps, 'UniformOutput', false))';
    else
        out = string.empty(0,1);   % safe empty — no crash on empty project
    end
end

function onPopupPaste(d, src)
    % Called after pasting into the Popup Editor table
    % Re-apply heatmap styles since values changed
    try; applyHeatmapStyles(src); catch; end
end
function copySelection(t)
    if isempty(t.Selection), return; end
    rows = unique(t.Selection(:,1));
    cols = unique(t.Selection(:,2));
    minR = min(rows); maxR = max(rows);
    minC = min(cols); maxC = max(cols);
    data = t.Data;
    subData = data(minR:maxR, minC:maxC);
    [nR, nC] = size(subData);

    % Build using cell array then strjoin — avoids O(n²) string concat in loops
    rowStrs = cell(nR, 1);
    for r = 1:nR
        cellRow = cell(1, nC);
        for c = 1:nC
            if iscell(subData), val = subData{r,c}; else, val = subData(r,c); end
            if isnumeric(val), val = num2str(val); end
            try; if ismissing(val), val = ''; end; catch; end
            cellRow{c} = char(string(val));
        end
        rowStrs{r} = strjoin(cellRow, sprintf('\t'));
    end
    clipboard('copy', [strjoin(rowStrs, newline), newline]);
end
function pasteSelection(t, updateCallback)
    str = clipboard('paste');
    if isempty(str), return; end
    rows = split(str, newline);
    rows = rows(~cellfun('isempty', rows));
    if isempty(rows), return; end
    if isempty(t.Selection), startR = 1; startC = 1; else, startR = min(t.Selection(:,1)); startC = min(t.Selection(:,2)); end
    data = t.Data;
    [maxR, maxC] = size(data);
    dataChanged = false;
    isNum = isnumeric(data);
    for r = 1:length(rows)
        rowTxt = rows{r};
        vals = split(rowTxt, sprintf('\t'));
        targetR = startR + r - 1;
        if targetR > maxR, break; end
        for c = 1:length(vals)
            targetC = startC + c - 1;
            if targetC > maxC, break; end
            valStr = vals{c};
            
            if isNum
                currentVal = data(targetR, targetC);
            else
                currentVal = data{targetR, targetC};
            end
            
            newVal = valStr;
            if isNum || isnumeric(currentVal)
                 numVal = str2double(valStr);
                 if ~isnan(numVal), newVal = numVal; end
            end
            
            if isNum
                data(targetR, targetC) = newVal;
            else
                data{targetR, targetC} = newVal;
            end
            dataChanged = true;
        end
    end
    if dataChanged
        t.Data = data;
        if exist('updateCallback', 'var') && ~isempty(updateCallback)
            updateCallback(t);
        end
    end
end
function onStatPaste(ukFig, fig, src)
    appData = fig.UserData;
    tData = src.Data;
    if iscell(tData)
        numericData = str2double(string(tData(:, 2:end)));
    else
        numericData = tData(:, 2:end);
    end
    appData.statTabul = numericData;
    fig.UserData = appData;
end

function onTCCPaste(fig, src, type)
    pushTCCHistory(fig);
    appData = fig.UserData;
    if strcmp(type, 'curves')
        appData.tccShadowData.curves = src.Data;
    elseif strcmp(type, 'zustand')
        appData.tccShadowData.zustand = src.Data;
    elseif strcmp(type, 'kwk')
        appData.tccShadowData.kwk = src.Data;
    end
    fig.UserData = appData;
end

function onGenericTablePaste(fig, src, type)
    appData = fig.UserData;
    wc = appData.workingCopy; 
    
    data = src.Data;
    [rows, cols] = size(data);
    
    Z_up = wc.Z_up;
    Z_down = wc.Z_down;
    pedal = wc.pedal;
    
    for r = 1:rows
        pVal = data{r, 1};
        if isnumeric(pVal), pedal(r) = pVal; end
        
        for c = 2:cols
            val = data{r, c};
            if ~isnumeric(val), continue; end
            
            rpmVal = val;
            if ~strcmp(type, 'RPM')
                 isUpshift = (c <= 8);
                 if isUpshift
                     gear = c - 1; 
                 else
                     gear = c - 8 + 1; 
                 end
                 rpmVal = convertFromUnit(fig, val, type, gear);
            end
            
            if c <= 8
                Z_up(r, c-1) = round(rpmVal);
            else
                Z_down(r, c-8) = round(rpmVal);
            end
        end
    end
    
    wc.pedal = pedal;
    wc.Z_up = Z_up;
    wc.Z_down = Z_down;
    
    wc = enforceRowConstraints(wc);
    wc.modified = true;
    
    pushHistory(fig);
    appData.workingCopy = wc;
    fig.UserData = appData;
    
    updateTableDisplay(fig);
    updatePlot(fig);
end

function rpm = convertFromUnit(fig, val, type, gear)
    appData = fig.UserData;
    userInputs = appData.userInputs;
    gr = userInputs.GearRatios;
    ar = userInputs.AxleRatio;
    tc = userInputs.TireCircumference;

    ratioEff = ar;
    if isfield(userInputs, 'LowRangeRatio') && isfield(appData, 'handles') && ...
       isfield(appData.handles, 'cb4Lo') && isvalid(appData.handles.cb4Lo) && appData.handles.cb4Lo.Value
        ratioEff = ratioEff * userInputs.LowRangeRatio;
    end
    if ratioEff == 0, ratioEff = 1; end
    if tc == 0, tc = 1; end

    rpm = val;
    switch type
        case 'MPH'
            rpm = (val * 1056 * ratioEff) / tc;
        case 'KPH'
            mph = val / 1.60934;
            rpm = (mph * 1056 * ratioEff) / tc;
        case 'Turbine'
            if gear >= 1 && gear <= length(gr) && gr(gear) ~= 0
                rpm = val / gr(gear);
            end
        case 'Engine'
            if gear >= 1 && gear <= length(gr) && gr(gear) ~= 0
                rpm = val / gr(gear);
            end
    end
end

%% === MULTI MAP EDITOR ===
function openMultiMapEditor(fig)
    appData = fig.UserData;
    if isempty(appData.allMaps), uialert(fig, 'No maps available.', 'Error'); return; end
    % If already open, just bring to front
    if isfield(appData,'multiMapFig') && hasValidHandle(appData, 'multiMapFig')
        appData.multiMapFig.Visible = 'on'; figure(appData.multiMapFig); return;
    end
    
    d = uifigure('Name', 'Multi Map Editor', 'Position', [100 100 1200 600]);
    d.CloseRequestFcn = @(src,~) closeMultiMapEditor(fig, src);
    appData.multiMapFig = d; fig.UserData = appData;

    gl = uigridlayout(d, [2, 1]);
    gl.RowHeight = {'1x', 50};
    
    tg = uitabgroup(gl);
    
    % Get Map Names as String Array
    mapNames = getMapNames(appData);
    if isempty(mapNames), mapNames = ["None"]; end

    %% --- TAB 1: GENERAL EDITOR ---
    tab1 = uitab(tg, 'Title', 'Multi-Map View');
    gl1 = uigridlayout(tab1, [3, 1]); gl1.RowHeight = {40, 60, '1x'};
    
    % --- TOP: Gear & Load ---
    pnlControls = uipanel(gl1, 'BorderType', 'none');
    ctlGrid = uigridlayout(pnlControls, [1, 5]); 
    ctlGrid.ColumnWidth = {'1x', 60, 120, 100, 20}; % Right align controls
    ctlGrid.Padding = [0 5 0 0];
    
    uilabel(ctlGrid, 'Text', ''); % Spacer
    
    lblGear = uilabel(ctlGrid, 'Text', 'Gear:', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    
    ddGear = uidropdown(ctlGrid, 'Items', {'1->2', '2->3', '3->4', '4->5', '5->6', '6->7', '7->8', ...
                                           '2->1', '3->2', '4->3', '5->4', '6->5', '7->6', '8->7'});
    
    btnLoad = uibutton(ctlGrid, 'Text', 'Load Data', 'BackgroundColor', [0.9 1 0.9], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) guardedLoadTab1(fig, d));
    
    uilabel(ctlGrid, 'Text', ''); % Spacer
    
    % --- MIDDLE: Map Dropdowns ---
    pnlMaps = uipanel(gl1);
    mapGrid = uigridlayout(pnlMaps, [2, 5]);
    mapGrid.ColumnWidth = {'1x', '1x', '1x', '1x', '1x'};
    mapGrid.RowHeight = {20, 25};
    mapGrid.Padding = [2 2 2 2];
    
    mapDDs = gobjects(1, 5);
    for i = 1:5
        lbl = uilabel(mapGrid, 'Text', sprintf('Map %d', i), 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
        lbl.Layout.Row = 1; lbl.Layout.Column = i;
        
        val = mapNames(1);
        if i <= length(mapNames), val = mapNames(i); end
        
        dd = uidropdown(mapGrid, 'Items', mapNames, 'Value', val);
        dd.Layout.Row = 2; dd.Layout.Column = i;
        mapDDs(i) = dd;
    end
    
    % --- BOTTOM: Table Area ---
    t = uitable(gl1, 'Data', {}, 'ColumnName', {}, 'ColumnEditable', true, 'RowName', 'numbered', ...
        'CellEditCallback',      @(src, e) onMultiMapEdit(fig, d, src, e, 'tab1'), ...
        'CellSelectionCallback', @(src, e) onMultiMapSelect(d, src, e, 'tab1'));
    % Right-click context menu for Tab 1
    cm1 = uicontextmenu(d);
    uimenu(cm1, 'Text', 'Add Offset (+/-)...',  'MenuSelectedFcn', @(~,~) applyMultiMapMath(fig, d, 'add'));
    uimenu(cm1, 'Text', 'Multiply (×)...',       'MenuSelectedFcn', @(~,~) applyMultiMapMath(fig, d, 'mult'));
    uimenu(cm1, 'Text', 'Divide (÷)...',         'MenuSelectedFcn', @(~,~) applyMultiMapMath(fig, d, 'div'));
    uimenu(cm1, 'Text', 'Percentage (%)...',     'MenuSelectedFcn', @(~,~) applyMultiMapMath(fig, d, 'percent'));
    uimenu(cm1, 'Text', 'Copy',  'Separator','on', 'MenuSelectedFcn', @(~,~) copySelection(t));
    uimenu(cm1, 'Text', 'Paste', 'MenuSelectedFcn', @(~,~) multiMapPaste(fig, d, t));
    uimenu(cm1, 'Text', 'Undo (Ctrl+Z)', 'Separator','on', 'MenuSelectedFcn', @(~,~) undoMultiMap(fig, d));
    t.ContextMenu = cm1;
    
    %% --- TAB 2: DOWN SHIFT LINES ---
    tab2 = uitab(tg, 'Title', 'Down Shift Lines');
    gl2 = uigridlayout(tab2, [2, 1]); gl2.RowHeight = {80, '1x'};
    
    pnlDS = uipanel(gl2);
    dsGrid = uigridlayout(pnlDS, [2, 5]); % Ref, Target, Gear, Offset, Calculate
    dsGrid.ColumnWidth = {'1x', '1x', '1x', 120, 120};
    dsGrid.RowHeight = {25, 25};
    
    % 1. Reference Map
    uilabel(dsGrid, 'Text', 'Reference Map (A)', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    ddRef = uidropdown(dsGrid, 'Items', mapNames, 'Value', mapNames(1));
    ddRef.Layout.Row = 2; ddRef.Layout.Column = 1;
    
    % 2. Target Map
    uilabel(dsGrid, 'Text', 'Target Map (B)', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    ddTgt = uidropdown(dsGrid, 'Items', mapNames, 'Value', mapNames(min(2,length(mapNames))));
    ddTgt.Layout.Row = 2; ddTgt.Layout.Column = 2;
    
    % 3. Gear (Downshift only)
    uilabel(dsGrid, 'Text', 'Downshift Gear', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    ddDSGear = uidropdown(dsGrid, 'Items', {'2->1', '3->2', '4->3', '5->4', '6->5', '7->6', '8->7'});
    ddDSGear.Layout.Row = 2; ddDSGear.Layout.Column = 3;
    
    % 4. Distance Control (Grid for -, Value, +)
    uilabel(dsGrid, 'Text', 'Distance', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    distGrid = uigridlayout(dsGrid, [1, 3]);
    distGrid.ColumnWidth = {25, '1x', 25};
    distGrid.Layout.Row = 2; distGrid.Layout.Column = 4;
    distGrid.Padding = [0 0 0 0]; distGrid.ColumnSpacing = 2;
    
    uibutton(distGrid, 'Text', '-', 'ButtonPushedFcn', @(~,~) adjustDistance(fig, d, -10));
    efOffset = uieditfield(distGrid, 'numeric', 'Value', 0, 'HorizontalAlignment', 'center', ...
        'ValueChangedFcn', @(~,~) loadTab2Data(fig, d, true));
    uibutton(distGrid, 'Text', '+', 'ButtonPushedFcn', @(~,~) adjustDistance(fig, d, 10));
    
    % 5. Load/Reset Button
    btnCalc = uibutton(dsGrid, 'Text', 'Load / Reset', 'BackgroundColor', [0.6 1 0.6], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) guardedLoadTab2(fig, d));
    btnCalc.Layout.Row = 2; btnCalc.Layout.Column = 5;
    
    % Table Area
    tDS = uitable(gl2, 'Data', {}, 'ColumnName', {'Pedal %', 'Center (Avg)', 'Map A New', 'Map B New'}, ...
        'ColumnEditable', [false, false, true, true], ...
        'RowName', 'numbered', ...
        'CellEditCallback',      @(src, e) onMultiMapEdit(fig, d, src, e, 'tab2'), ...
        'CellSelectionCallback', @(src, e) onMultiMapSelect(d, src, e, 'tab2'));
    % Right-click context menu for Tab 2
    cm2 = uicontextmenu(d);
    uimenu(cm2, 'Text', 'Add Offset (+/-)...',  'MenuSelectedFcn', @(~,~) applyMultiMapMath(fig, d, 'add'));
    uimenu(cm2, 'Text', 'Multiply (×)...',       'MenuSelectedFcn', @(~,~) applyMultiMapMath(fig, d, 'mult'));
    uimenu(cm2, 'Text', 'Divide (÷)...',         'MenuSelectedFcn', @(~,~) applyMultiMapMath(fig, d, 'div'));
    uimenu(cm2, 'Text', 'Percentage (%)...',     'MenuSelectedFcn', @(~,~) applyMultiMapMath(fig, d, 'percent'));
    uimenu(cm2, 'Text', 'Copy',  'Separator','on', 'MenuSelectedFcn', @(~,~) copySelection(tDS));
    uimenu(cm2, 'Text', 'Paste', 'MenuSelectedFcn', @(~,~) multiMapPaste(fig, d, tDS));
    uimenu(cm2, 'Text', 'Undo (Ctrl+Z)', 'Separator','on', 'MenuSelectedFcn', @(~,~) undoMultiMap(fig, d));
    tDS.ContextMenu = cm2;

    %% --- BOTTOM PANEL ---
    pnlBot = uipanel(gl);
    botGrid = uigridlayout(pnlBot, [1, 3]);
    botGrid.ColumnWidth = {'1x', 200, '1x'};
    
    uibutton(botGrid, 'Text', '↩ Undo (Ctrl+Z)', 'BackgroundColor', [0.85 0.85 0.95], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) undoMultiMap(fig, d));
    uibutton(botGrid, 'Text', 'SAVE CHANGES', 'BackgroundColor', [1 0.8 0], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) saveDispatcher(fig, d));
    % Keyboard shortcuts: Ctrl+Z = undo, Ctrl+V = paste
    d.WindowKeyPressFcn = @(~, event) onMultiMapKeyPress(fig, d, event);

    % Build UserData field-by-field — avoids struct() creating 1xN arrays
    % when gobjects handles (mapDDs is 1x5) are passed to the struct() constructor.
    mmd_h = struct();
    mmd_h.tabGroup     = tg;
    mmd_h.tab1         = struct('ddGear', ddGear, 'table', t, 'loadedData', []);
    mmd_h.tab1.mapDDs  = mapDDs;          % assign gobjects after struct init
    mmd_h.tab2         = struct('ddRef', ddRef, 'ddTgt', ddTgt, 'ddGear', ddDSGear, ...
                                'efOffset', efOffset, 'table', tDS, 'loadedData', []);
    mmd_h.lastSelection = [];
    mmd_h.activeTab    = 'tab1';
    d.UserData = mmd_h;
    
    % Initial Load Tab 1
    try
        loadTab1Data(fig, d);
    catch ME
        % Suppress tab1 load errors on first open — data may not be ready yet
        warning(ME.identifier, '%s', ME.message);
    end
end

function loadTab1Data(fig, multiFig)
    appData = fig.UserData;
    h = multiFig.UserData;
    t1 = h.tab1;
    
    if isempty(appData.allMaps), return; end
    allMapNames = getMapNames(appData);
    
    selectedMapsIndices = zeros(1, 5);
    selectedMapsNames = strings(1, 5);
    
    for i = 1:5
        name = string(t1.mapDDs(i).Value);
        idx = find(allMapNames == name, 1);
        if ~isempty(idx)
            selectedMapsIndices(i) = idx; selectedMapsNames(i) = name;
        else
            selectedMapsIndices(i) = -1; selectedMapsNames(i) = "None";
        end
    end
    
    gearStr = t1.ddGear.Value;
    [isUp, colIdx] = getGearIndex(gearStr);
    if isempty(colIdx), uialert(multiFig, 'Invalid Gear', 'Error'); return; end
    
    maxLen = 0;
    for i = 1:5
        if selectedMapsIndices(i) > 0
            map = appData.allMaps{selectedMapsIndices(i)};
            maxLen = max(maxLen, length(map.pedal));
        end
    end
    if maxLen == 0, maxLen = 10; end
    
    tableData = []; colNames = {}; colEditable = [];
    loadedDataInfo = struct('indices', selectedMapsIndices, 'isUp', isUp, 'colIdx', colIdx);
    
    for i = 1:5
        mIdx = selectedMapsIndices(i);
        if mIdx > 0
            map = appData.allMaps{mIdx};
            p = map.pedal(:);
            if isUp
                if colIdx <= size(map.Z_up, 2), v = map.Z_up(:, colIdx); else, v = zeros(size(p)); end
            else
                if colIdx <= size(map.Z_down, 2), v = map.Z_down(:, colIdx); else, v = zeros(size(p)); end
            end
            v = v(:); v = round(v);
            
            currLen = length(p);
            if currLen < maxLen
                p = [p; nan(maxLen - currLen, 1)]; v = [v; nan(maxLen - currLen, 1)];
            elseif currLen > maxLen
                p = p(1:maxLen); v = v(1:maxLen);
            end
            
            vStr = cellstr(compose("%.0f", v));
            pCell = num2cell(p);
            block = [pCell, vStr, vStr];
            
            colNames = [colNames, {sprintf('M%d Pedal', i), sprintf('M%d Old', i), sprintf('M%d New', i)}];
            colEditable = [colEditable, false, false, true];
        else
            block = repmat({nan}, maxLen, 3);
            colNames = [colNames, {sprintf('M%d -', i), '-', '-'}];
            colEditable = [colEditable, false, false, false];
        end
        tableData = [tableData, block];
    end
    
    t1.table.Data = tableData;
    t1.table.ColumnName = colNames;
    t1.table.ColumnEditable = logical(colEditable);
    t1.loadedData = loadedDataInfo;
    
    h.tab1 = t1; multiFig.UserData = h;
    applyMultiMapStyles(t1.table);
end

function loadTab2Data(fig, multiFig, skipRecalc)
    appData = fig.UserData;
    h = multiFig.UserData;
    t2 = h.tab2;
    
    refName = t2.ddRef.Value;
    tgtName = t2.ddTgt.Value;
    gearStr = t2.ddGear.Value;
    
    if isempty(appData.allMaps), return; end
    allNames = getMapNames(appData);
    
    refIdx = find(allNames == refName, 1);
    tgtIdx = find(allNames == tgtName, 1);
    
    if isempty(refIdx) || isempty(tgtIdx)
        uialert(multiFig, 'Please select valid maps.', 'Error'); return;
    end
    
    mapRef = appData.allMaps{refIdx};
    mapTgt = appData.allMaps{tgtIdx};
    
    [isUp, colIdx] = getGearIndex(gearStr);
    
    % Get Data
    p = mapRef.pedal(:);
    
    if colIdx <= size(mapRef.Z_down, 2), vRef = mapRef.Z_down(:, colIdx); else, vRef = zeros(size(p)); end
    
    if length(mapTgt.pedal) == length(p)
         if colIdx <= size(mapTgt.Z_down, 2), vTgt = mapTgt.Z_down(:, colIdx); else, vTgt = zeros(size(p)); end
    else
         uialert(multiFig, 'Maps have different pedal vectors. Cannot calibrate directly.', 'Error'); return;
    end
    
    % --- SYMMETRY LOGIC ---
    % Calculate Center (Avg)
    vAvg = (vRef + vTgt) / 2;
    
    % Calculate Initial Spread if not set or just use user input as delta?
    % The user wants to adjust distance. Let's calculate the mean distance in the window.
    if nargin < 3 % Only reset offset if called via Load button or dropdown change (not adjustDistance)
        % Calculate current mean spread in 20-80 range
        mask = (p >= 20 & p <= 80);
        if any(mask)
            currentSpread = mean(vTgt(mask) - vRef(mask));
            % Or absolute difference? "Distance" implies positive. 
            % But orientation matters. Let's stick to signed diff.
            % But user wants symmetry. So spread = vTgt - vRef.
            % However, if vRef > vTgt, diff is negative. 
            % Let's use scalar distance. 
            % Ideally we want vTgt - vRef = Dist. 
            % Let's initialize the field to the current max spread? or mean?
            % Let's just default to 0 offset change, so field = 0?
            % No, field represents "Distance". 
            % Let's set field to the mean absolute distance.
            meanDist = mean(abs(vTgt(mask) - vRef(mask)));
            t2.efOffset.Value = round(meanDist);
        end
    end
    
    dist = t2.efOffset.Value;
    
    vRefNew = vRef;
    vTgtNew = vTgt;
    
    for i = 1:length(p)
        if p(i) >= 20 && p(i) <= 80
            % Symmetry: Center +/- Dist/2
            % Assuming Map A (Ref) is "lower" or "upper"? 
            % Let's preserve original relative orientation.
            % If originally vRef < vTgt, then vRefNew = Avg - Dist/2.
            % If originally vRef > vTgt, then vRefNew = Avg + Dist/2.
            
            % Check local orientation
            if vRef(i) <= vTgt(i)
                vRefNew(i) = vAvg(i) - dist/2;
                vTgtNew(i) = vAvg(i) + dist/2;
            else
                vRefNew(i) = vAvg(i) + dist/2;
                vTgtNew(i) = vAvg(i) - dist/2;
            end
        end
    end
    
    vAvg = round(vAvg);
    vRefNew = round(vRefNew);
    vTgtNew = round(vTgtNew);
    
    % Strings for display
    vAvgStr = cellstr(compose("%.0f", vAvg));
    vRefStr = cellstr(compose("%.0f", vRefNew));
    vTgtStr = cellstr(compose("%.0f", vTgtNew));
    pCell = num2cell(p);
    
    t2.table.Data = [pCell, vAvgStr, vRefStr, vTgtStr];
    
    % Highlighting (Blue = A, Yellow = B?)
    removeStyle(t2.table);
    sBlue = uistyle('BackgroundColor', [0.85 0.95 1]); 
    sYellow = getSoftYellowStyle();
    addStyle(t2.table, sBlue, 'column', 3);
    addStyle(t2.table, sYellow, 'column', 4);
    
    t2.loadedData = struct('refIdx', refIdx, 'tgtIdx', tgtIdx, 'colIdx', colIdx, 'isUp', isUp);
    h.tab2 = t2; multiFig.UserData = h;
    % Clear dirty flag and history — fresh load
    mmSetDirty(fig, false);
    mmClearHistory(fig);
end

function adjustDistance(fig, multiFig, delta)
    h = multiFig.UserData;
    t2 = h.tab2;
    val = t2.efOffset.Value;
    t2.efOffset.Value = val + delta;
    loadTab2Data(fig, multiFig, true); % Pass true to skip re-calculating initial mean
end

function saveDispatcher(fig, multiFig)
    h = multiFig.UserData;
    activeTitle = h.tabGroup.SelectedTab.Title;
    
    if strcmp(activeTitle, 'Multi-Map View')
        saveTab1(fig, multiFig);
    elseif strcmp(activeTitle, 'Down Shift Lines')
        saveTab2(fig, multiFig);
    end
end

function saveTab1(fig, multiFig)
    h = multiFig.UserData;
    t1 = h.tab1;
    tableData = t1.table.Data;
    info = t1.loadedData;
    appData = fig.UserData;
    
    if isempty(info) || isempty(tableData), return; end
    
    selection = uiconfirm(multiFig, 'Overwrite existing maps or Save as New Maps?', 'Save Changes', ...
        'Options', {'Overwrite', 'Save as New', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 3);
    
    if strcmp(selection, 'Cancel'), return; end
    isNew = strcmp(selection, 'Save as New');
    newNames = {};
    
    if isNew
        prompts = {}; defaults = {};
        for i = 1:5
            if info.indices(i) > 0
                prompts{end+1} = sprintf('Name for Map %d (%s):', i, appData.allMaps{info.indices(i)}.name);
                defaults{end+1} = char(appData.allMaps{info.indices(i)}.name + "_MOD");
            end
        end
        if isempty(prompts), uialert(multiFig, 'No valid maps.', 'Error'); return; end
        newNames = inputdlg(prompts, 'New Map Names', [1 50], defaults);
        if isempty(newNames), return; end
    end
    
    count = 0;
    for i = 1:5
        mIdx = info.indices(i);
        if mIdx > 0
            map = appData.allMaps{mIdx};
            colBase = (i-1)*3;
            newVals = tableData(:, colBase + 3);
            if iscell(newVals), newVals = str2double(string(newVals)); end
            validLen = length(map.pedal);
            newVals = round(newVals(1:validLen));
            
            if info.isUp, map.Z_up(:, info.colIdx) = newVals;
            else, map.Z_down(:, info.colIdx) = newVals; end
            map.modified = true;
            
            if isNew
                map.name = string(newNames{count+1});
                appData.allMaps{end+1} = map;
                count = count + 1;
            else
                appData.allMaps{mIdx} = map;
            end
        end
    end
    
    % ── Rebuild allMapNames cache ────────────────────────────────────────────
    appData.allMapNames = string(cellfun(@(m) m.name, appData.allMaps, 'UniformOutput', false))';
    fig.UserData = appData;

    % ── Refresh dropdowns ────────────────────────────────────────────────────
    allNDel  = getMapNames(appData);
    origNDel = cellstr(allNDel(~startsWith(allNDel,'[REF]')));
    newMapList = cellstr(allNDel);
    appData.handles.dd1.Items = origNDel;    % dd1: originals only
    appData.handles.dd2.Items = newMapList;  % dd2: all maps
    if isfield(appData.handles,'dd3') && isvalid(appData.handles.dd3), appData.handles.dd3.Items = newMapList; end
    for k = 1:5, t1.mapDDs(k).Items = newMapList; end
    h.tab2.ddRef.Items = newMapList; h.tab2.ddTgt.Items = newMapList;

    % ── Sync workingCopy if the currently edited map was changed ─────────────
    % Check all 5 map slots — if any match the open Edit Map A, update it.
    syncDone = false;
    if ~isempty(appData.workingCopy) && appData.editIndex > 0
        for i = 1:5
            mIdx = info.indices(i);
            if mIdx <= 0, continue; end
            if ~isNew && mIdx == appData.editIndex
                % Overwrite path: map edited in-place — sync workingCopy
                appData.workingCopy = appData.allMaps{mIdx};
                appData.workingCopy.modified = true;
                fig.UserData = appData;
                updateTableDisplay(fig);
                refreshTableStyles(fig);
                syncDone = true;
                break;
            end
        end
    end
    if ~syncDone
        fig.UserData = appData;
    end

    % ── Sync session slots if session active ─────────────────────────────────
    appData = fig.UserData;
    if ~isNew && isfield(appData,'holdSession') && isstruct(appData.holdSession)
        for slotK6 = {'A','B','C'}
            sl6 = appData.holdSession.slots.(slotK6{1});
            if isempty(sl6), continue; end
            allN6 = getMapNames(appData);
            sidx6 = find(allN6 == string(sl6.name),1);
            if ~isempty(sidx6)
                for i=1:5
                    if info.indices(i)==sidx6
                        appData.holdSession.slots.(slotK6{1}) = appData.allMaps{sidx6};
                        break;
                    end
                end
            end
        end
        fig.UserData = appData;
    end

    uialert(multiFig, 'Maps Saved Successfully.', 'Success');
    applyMultiMapStyles(t1.table);
    mmSetDirty(fig, false);
    mmClearHistory(fig);
    updatePlot(fig);
end

function saveTab2(fig, multiFig)
    h = multiFig.UserData;
    t2 = h.tab2;
    info = t2.loadedData;
    appData = fig.UserData;
    
    if isempty(info), return; end
    
    % Extract Data (Cols 3 & 4: Map A New, Map B New)
    vRefNew = t2.table.Data(:, 3);
    vTgtNew = t2.table.Data(:, 4);
    
    if iscell(vRefNew), vRefNew = str2double(string(vRefNew)); end
    if iscell(vTgtNew), vTgtNew = str2double(string(vTgtNew)); end
    
    vRefNew = round(vRefNew);
    vTgtNew = round(vTgtNew);
    
    refIdx = info.refIdx;
    tgtIdx = info.tgtIdx;
    
    mapRef = appData.allMaps{refIdx};
    mapTgt = appData.allMaps{tgtIdx};
    
    msg = sprintf('Overwrite Map "%s" AND Map "%s"?', mapRef.name, mapTgt.name);
    selection = uiconfirm(multiFig, msg, 'Save Downshift Lines', ...
        'Options', {'Overwrite Both', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2);
    
    if strcmp(selection, 'Cancel'), return; end
    
    % Update Reference Map
    mapRef.Z_down(:, info.colIdx) = vRefNew;
    mapRef.modified = true;
    appData.allMaps{refIdx} = mapRef;
    
    % Update Target Map
    mapTgt.Z_down(:, info.colIdx) = vTgtNew;
    mapTgt.modified = true;
    appData.allMaps{tgtIdx} = mapTgt;
    
    % ── Rebuild allMapNames cache ────────────────────────────────────────────
    appData.allMapNames = string(cellfun(@(m) m.name, appData.allMaps, 'UniformOutput', false))';
    fig.UserData = appData;

    % ── Sync workingCopy and session slots ───────────────────────────────────
    appData = fig.UserData;
    if ~isempty(appData.workingCopy) && appData.editIndex > 0
        if appData.editIndex == refIdx || appData.editIndex == tgtIdx
            appData.workingCopy = appData.allMaps{appData.editIndex};
            appData.workingCopy.modified = true;
            fig.UserData = appData;
            updateTableDisplay(fig);
            refreshTableStyles(fig);
        else
            fig.UserData = appData;
        end
    else
        fig.UserData = appData;
    end

    % ── Sync session slots if session is active ───────────────────────────────
    appData = fig.UserData;
    if isfield(appData,'holdSession') && isstruct(appData.holdSession)
        for slotK5 = {'A','B','C'}
            sl5 = appData.holdSession.slots.(slotK5{1});
            if isempty(sl5), continue; end
            allN5 = getMapNames(appData);
            sidx5 = find(allN5 == string(sl5.name),1);
            if ~isempty(sidx5) && (sidx5==refIdx || sidx5==tgtIdx)
                appData.holdSession.slots.(slotK5{1}) = appData.allMaps{sidx5};
            end
        end
        fig.UserData = appData;
    end

    uialert(multiFig, 'Both Maps Updated Successfully.', 'Success');
    mmSetDirty(fig, false);
    mmClearHistory(fig);
    updatePlot(fig);
end

function onMultiMapEdit(fig, multiFig, src, event, tabName)
    if isempty(event.Indices), return; end  % guard: spurious callback
    % CellEditCallback — fires AFTER the cell value has been changed in ONE cell.
    % Mirror onGenericTableEdit from Edit Map A:
    %   if multiple cells are selected AND the edited cell is inside the selection,
    %   apply the same typed value to ALL selected editable cells.
    editedR = event.Indices(1);
    editedC = event.Indices(2);
    newVal  = event.NewData;

    % Reconstruct the state BEFORE this edit for the history snapshot
    dataBefore = src.Data;
    dataBefore{editedR, editedC} = event.PreviousData;
    pushMultiHistory(fig, multiFig, tabName, dataBefore);
    mmSetDirty(fig, true);   % mark unsaved changes

    % --- Multi-cell apply (same as Edit Map A) ---
    sel    = src.Selection;   % current live selection
    edCols = src.ColumnEditable;
    data   = src.Data;

    % Determine target cells: all selected if edited cell is inside selection,
    % otherwise just the one cell that was edited.
    if size(sel,1) > 1 && ~isempty(sel)
        insideSel = ismember([editedR, editedC], sel, 'rows');
    else
        insideSel = false;
    end

    if insideSel
        targets = sel;
    else
        targets = [editedR, editedC];
    end

    for k = 1:size(targets,1)
        r = targets(k,1);  c = targets(k,2);
        if r > size(data,1) || c > size(data,2), continue; end
        if numel(edCols) >= c && ~edCols(c), continue; end  % skip read-only
        if isnumeric(newVal)
            data{r,c} = num2str(round(double(newVal)));
        else
            numV = str2double(string(newVal));
            if ~isnan(numV), data{r,c} = num2str(round(numV)); end
        end
    end
    src.Data = data;
    refreshMultiMapDiffStyles(multiFig, tabName);
end

function onMultiMapSelect(multiFig, src, event, tabName)
    % Track which tab is active — stored in multiFig.UserData (stable for UI state)
    h = multiFig.UserData;
    h.activeTab = tabName;
    multiFig.UserData = h;
end

function onMultiMapKeyPress(fig, multiFig, event)
    if strcmp(event.Key,'z') && ~isempty(event.Modifier) && any(strcmp(event.Modifier,'control'))
        undoMultiMap(fig, multiFig);
    elseif strcmp(event.Key,'v') && ~isempty(event.Modifier) && any(strcmp(event.Modifier,'control'))
        h = multiFig.UserData;
        multiMapPaste(fig, multiFig, h.(h.activeTab).table);
    end
end

function pushMultiHistory(fig, multiFig, tabName, dataBefore)
    % Store history in fig.UserData (appData.multiHistory) — same pattern as
    % Edit Map A which uses appData.history.  This survives any d.UserData rebuild.
    appData = fig.UserData;
    if ~isfield(appData, 'multiHistory') || isempty(appData.multiHistory)
        appData.multiHistory = {};
    end
    if numel(appData.multiHistory) >= 50
        appData.multiHistory = appData.multiHistory(2:end);
    end
    appData.multiHistory{end+1} = {tabName, dataBefore};
    fig.UserData = appData;
end

function undoMultiMap(fig, multiFig)
    % Mirror performUndo(fig) from Edit Map A — pops from appData.multiHistory.
    appData = fig.UserData;
    if ~isfield(appData,'multiHistory') || isempty(appData.multiHistory)
        uialert(multiFig, 'Nothing to undo.', 'Undo'); return;
    end
    entry   = appData.multiHistory{end};
    tabName = entry{1};
    data    = entry{2};
    appData.multiHistory = appData.multiHistory(1:end-1);
    fig.UserData = appData;
    % Restore table data
    h = multiFig.UserData;
    h.(tabName).table.Data = data;
    multiFig.UserData = h;
    refreshMultiMapDiffStyles(multiFig, tabName);
end

function refreshMultiMapDiffStyles(multiFig, tabName)
% Reapply base colours, then highlight changed cells in orange (batched).
    h   = multiFig.UserData;
    tbl = h.(tabName).table;
    applyMultiMapStyles(tbl);
    data = tbl.Data;
    if isempty(data), return; end

    nRows = size(data, 1);
    nCols = size(data, 2);
    sChanged = uistyle('BackgroundColor',[1 0.65 0],'FontWeight','bold');

    % Collect all changed [row,col] indices via logical mask — vectorised
    changeMask = false(nRows, nCols);
    if strcmp(tabName, 'tab1')
        newCols = 3:3:nCols;
        for ci = 1:length(newCols)
            c = newCols(ci); cOld = c - 1;
            if cOld < 1 || cOld > nCols, continue; end
            for r = 1:nRows
                nv = mmVal(data{r,c}); ov = mmVal(data{r,cOld});
                if ~isnan(nv) && ~isnan(ov) && abs(nv-ov) > 0.001
                    changeMask(r,c) = true;
                end
            end
        end
    else
        for c = 3:min(4,nCols)
            for r = 1:nRows
                nv = mmVal(data{r,c}); rv = mmVal(data{r,2});
                if ~isnan(nv) && ~isnan(rv) && abs(nv-rv) > 0.001
                    changeMask(r,c) = true;
                end
            end
        end
    end
    [rIdx, cIdx] = find(changeMask);
    if ~isempty(rIdx)
        addStyle(tbl, sChanged, 'cell', [rIdx, cIdx]);
    end
end

function v = mmVal(raw)
    % Safe numeric conversion for multi-map table cells (string or numeric)
    if isnumeric(raw),  v = double(raw);
    else,               v = str2double(string(raw)); end
end

function applyMultiMapMath(fig, multiFig, type)
    % Mirror applyMath(fig,type) from Edit Map A.
    h       = multiFig.UserData;
    tabName = h.activeTab;
    tbl     = h.(tabName).table;
    sel     = tbl.Selection;
    if isempty(sel)
        uialert(multiFig, 'Select cells first (click/drag), then right-click.', 'No Selection');
        return;
    end
    edCols = tbl.ColumnEditable;
    prompt = ''; def = '0';
    switch type
        case 'add',     prompt = 'Add Value (e.g. 50 or -50):';
        case 'mult',    prompt = 'Multiply by (e.g. 1.1):';  def = '1';
        case 'div',     prompt = 'Divide by (e.g. 2):';      def = '1';
        case 'percent', prompt = 'Percentage change (e.g. 10 or -5):';
    end
    answer = inputdlg(prompt, 'Batch Edit', [1 40], {def});
    if isempty(answer), return; end
    val = str2double(answer{1});
    if isnan(val), uialert(multiFig, 'Invalid number.', 'Error'); return; end

    % Snapshot current data BEFORE changes — stored in fig.UserData
    pushMultiHistory(fig, multiFig, tabName, tbl.Data);

    data = tbl.Data;
    for si = 1:size(sel,1)
        r = sel(si,1);  c = sel(si,2);
        if r > size(data,1) || c > size(data,2), continue; end
        if numel(edCols) >= c && ~edCols(c), continue; end
        curr = mmVal(data{r,c});
        if isnan(curr), continue; end
        switch type
            case 'add',     curr = curr + val;
            case 'mult',    curr = curr * val;
            case 'div',     if val ~= 0, curr = curr / val; end
            case 'percent', curr = curr * (1 + val/100);
        end
        data{r,c} = num2str(round(curr));
    end
    tbl.Data = data;
    mmSetDirty(fig, true);
    refreshMultiMapDiffStyles(multiFig, tabName);
end

function multiMapPaste(fig, multiFig, tbl)
    % Mirror pasteTableData(fig) from Edit Map A.
    str = clipboard('paste');
    if isempty(str), return; end
    h       = multiFig.UserData;
    tabName = h.activeTab;
    sel     = tbl.Selection;
    if isempty(sel), startR = 1; startC = 1;
    else,            startR = min(sel(:,1)); startC = min(sel(:,2)); end
    edCols = tbl.ColumnEditable;
    data   = tbl.Data;
    % Snapshot BEFORE changes
    pushMultiHistory(fig, multiFig, tabName, data);
    [maxR, maxC] = size(data);
    lines = splitlines(strtrim(str));
    lines = lines(~cellfun('isempty', lines));
    for ri = 1:numel(lines)
        tgtR = startR + ri - 1;
        if tgtR > maxR, break; end
        vals = strsplit(strtrim(lines{ri}), sprintf('\t'));
        for ci = 1:numel(vals)
            tgtC = startC + ci - 1;
            if tgtC > maxC, break; end
            if numel(edCols) >= tgtC && ~edCols(tgtC), continue; end
            numV = str2double(strtrim(vals{ci}));
            if isnan(numV), continue; end
            data{tgtR, tgtC} = num2str(round(numV));
        end
    end
    tbl.Data = data;
    mmSetDirty(fig, true);
    refreshMultiMapDiffStyles(multiFig, tabName);
end

function mmSetDirty(fig, tf)
    appData = fig.UserData;
    appData.multiMapDirty = tf;
    fig.UserData = appData;
end

function mmClearHistory(fig)
    appData = fig.UserData;
    appData.multiHistory = {};
    fig.UserData = appData;
end

function isDirty = mmIsDirty(fig)
    appData = fig.UserData;
    isDirty = isfield(appData,'multiMapDirty') && appData.multiMapDirty;
end

function proceed = mmCheckUnsaved(fig, multiFig)
    % Returns true if caller should proceed (load or close).
    % Prompts Save / Discard / Cancel when unsaved changes exist.
    proceed = true;
    if ~mmIsDirty(fig), return; end
    sel = uiconfirm(multiFig, ...
        'You have unsaved changes. What would you like to do?', ...
        'Unsaved Changes', ...
        'Options',       {'Save Changes', 'Discard Changes', 'Cancel'}, ...
        'DefaultOption', 'Save Changes', ...
        'CancelOption',  'Cancel', ...
        'Icon',          'warning');
    switch sel
        case 'Save Changes'
            saveDispatcher(fig, multiFig);
            proceed = true;
        case 'Discard Changes'
            mmSetDirty(fig, false);
            mmClearHistory(fig);
            proceed = true;
        otherwise   % Cancel
            proceed = false;
    end
end

function guardedLoadTab1(fig, multiFig)
    if mmCheckUnsaved(fig, multiFig)
        loadTab1Data(fig, multiFig);
    end
end

function guardedLoadTab2(fig, multiFig)
    if mmCheckUnsaved(fig, multiFig)
        loadTab2Data(fig, multiFig);
    end
end

function closeMultiMapEditor(fig, multiFig)
    if ~isempty(fig) && isvalid(fig)
        if ~mmCheckUnsaved(fig, multiFig), return; end
        try
            appData = fig.UserData;
            appData.multiMapFig   = gobjects(0);
            appData.multiMapDirty = false;
            appData.multiHistory  = {};
            fig.UserData = appData;
        catch; end
    end
    if ~isempty(multiFig) && isvalid(multiFig), delete(multiFig); end
end

function applyMultiMapStyles(t)
    removeStyle(t);
    nCols = size(t.Data, 2);
    if nCols == 0, return; end

    % Persistent style cache — avoid re-creating uistyle objects on every refresh
    persistent sPedal_ sOld_ sNew_;
    if isempty(sPedal_)
        sPedal_ = uistyle('BackgroundColor', [0.95 0.85 1]);  % Light Purple
        sOld_   = uistyle('BackgroundColor', [0.85 0.95 1]);  % Light Blue
        sNew_   = uistyle('BackgroundColor', [1 1 0.8]);      % Light Yellow
    end

    % Apply to columns (1,4,7... | 2,5,8... | 3,6,9...)
    addStyle(t, sPedal_, 'column', 1:3:nCols);
    addStyle(t, sOld_,   'column', 2:3:nCols);
    addStyle(t, sNew_,   'column', 3:3:nCols);
end

function [isUp, colIdx] = getGearIndex(gearStr)
    % Returns isUp boolean and Column Index for Z_up or Z_down matrices
    % Z_up columns: 1->2, 2->3, 3->4, 4->5, 5->6, 6->7, 7->8 (Indices 1 to 7)
    % Z_down columns: 2->1, 3->2, 4->3, 5->4, 6->5, 7->6, 8->7 (Indices 1 to 7)
    
    isUp = []; colIdx = [];
    tokens = regexp(gearStr, '(\d+)->(\d+)', 'tokens', 'once');
    if isempty(tokens) || numel(tokens) < 2, return; end
    
    % regexp 'tokens','once' returns a flat cell: {match1, match2}
    g1 = str2double(tokens{1});
    g2 = str2double(tokens{2});
    if isnan(g1) || isnan(g2), return; end
    
    if g2 > g1
        isUp = true;
        colIdx = g1; % 1->2 is index 1
        if colIdx < 1 || colIdx > 7, colIdx = []; end
    else
        isUp = false;
        colIdx = g2; % 2->1 is index 1, 8->7 is index 7
        if colIdx < 1 || colIdx > 7, colIdx = []; end
    end
end

function wc = enforceRowConstraints(wc)
% Ensures boundary rows (row 1 and last row) mirror their adjacent data rows
% for Z_up and Z_down (RPM values).
% NOTE: pedal boundary values are FIXED AXIS POINTS (0 and 110) — do NOT copy
% from neighbours. They are set at CSV load and must never be overwritten here.
    nRows = size(wc.Z_up, 1);
    if nRows >= 2
        wc.Z_up(1, :)       = wc.Z_up(2, :);
        wc.Z_down(1, :)     = wc.Z_down(2, :);
        wc.Z_up(nRows, :)   = wc.Z_up(nRows-1, :);
        wc.Z_down(nRows, :) = wc.Z_down(nRows-1, :);
    end
end



%% === 2D & 3D ANALYSIS TOOLS ===
function Genplots(fig)
    appData = fig.UserData;
    
    % Determine Map A Data
    mapAName = appData.handles.dd1.Value;
    map = [];
    
    % Check working copy first
    if ~isempty(appData.workingCopy) && isfield(appData.workingCopy, 'name') && strcmp(appData.workingCopy.name, mapAName)
        map = appData.workingCopy;
    else
        % Find in allMaps
        idx = find(getMapNames(appData) == string(mapAName), 1);
        if ~isempty(idx)
            map = appData.allMaps{idx};
        end
    end
    
    if isempty(map)
        uialert(fig, 'Map A data not found.', 'Error');
        return;
    end

    % PERFORMANCE FIX: Use legacy figure instead of uifigure for 3D plots
    % This provides native OpenGL acceleration which is much smoother in .exe
    d = figure('Name', ['Analysis: ' char(map.name)], ...
               'Units', 'normalized', 'Position', [0.1 0.1 0.8 0.8], ...
               'NumberTitle', 'off', 'MenuBar', 'figure', 'ToolBar', 'figure', ...
               'CloseRequestFcn', @(src,~) closeAnalysisFig(fig, src));

    appData.analysisFig = d; fig.UserData = appData;

    d.WindowState = 'maximized';
    
    % Use uitabgroup directly on figure
    tg = uitabgroup(d);
    
    %% TAB 1: SHIFT MAP SURFACE (3D)
    tSurf = uitab(tg, 'Title', 'Shift Surface (3D)');
    % Use tiledlayout instead of uigridlayout
    tlSurf = tiledlayout(tSurf, 1, 1, 'Padding', 'compact');
    axSurf = nexttile(tlSurf);
    title(axSurf, 'Shift Map Surface (Up & Down)');
    xlabel(axSurf, 'Gear Transition');
    ylabel(axSurf, 'Pedal %');
    zlabel(axSurf, 'Output RPM');
    view(axSurf, 3); grid(axSurf, 'on');
    
    updateSurfPlot(axSurf, map);
    
    %% TAB 2: RPM DROP ANALYSIS
    tRPM = uitab(tg, 'Title', 'RPM Drop Analysis');
    tlRPM = tiledlayout(tRPM, 1, 1, 'Padding', 'compact');
    axRPM = nexttile(tlRPM);
    title(axRPM, 'Predicted Engine RPM Drop on Upshift');
    xlabel(axRPM, 'Pedal %');
    ylabel(axRPM, 'RPM Drop');
    grid(axRPM, 'on');
    
    updateRPMPlot(axRPM, map, appData.userInputs.GearRatios);
    
    %% TAB 3: HYSTERESIS ANALYSIS (ALL SHIFTS)
    tHyst = uitab(tg, 'Title', 'Hysteresis (All Shifts)');
    tlHyst = tiledlayout(tHyst, 1, 1, 'Padding', 'compact');
    axHyst = nexttile(tlHyst);
    title(axHyst, 'Hysteresis (Upshift - Downshift)');
    xlabel(axHyst, 'Shift Speed (RPM)');
    ylabel(axHyst, 'Pedal %');
    zlabel(axHyst, 'Delta RPM');
    view(axHyst, 3); grid(axHyst, 'on');
    
    updateHystPlot(axHyst, map);
    
    %% TAB 4: TCC 3D OVERVIEW
    tTCC = uitab(tg, 'Title', 'TCC 3D Overview');
    tlTCC = tiledlayout(tTCC, 1, 1, 'Padding', 'compact');
    axTCC = nexttile(tlTCC);
    title(axTCC, 'TCC Lockup Schedule (All Gears)');
    xlabel(axTCC, 'Output Speed (RPM)');
    ylabel(axTCC, 'Pedal %');
    zlabel(axTCC, 'Gear');
    view(axTCC, 3); grid(axTCC, 'on');
    
    updateTCC3DPlot(axTCC, map, appData);
end

function updateSurfPlot(ax, map)
    cla(ax);
    % Z_up is Rows(Pedal) x Cols(GearTransitions 1-7)
    % meshgrid needs a column vector for Y; force pedal to column
    [X, Y] = meshgrid(1:7, map.pedal(:));
    
    % Upshift Surface
    surf(ax, X, Y, map.Z_up, 'FaceAlpha', 0.7, 'EdgeColor', 'interp', 'DisplayName', 'Upshift');
    hold(ax, 'on');
    
    % Downshift Mesh (Offset slightly or just mesh)
    % Z_down columns: 2->1 (1) ... 8->7 (7)
    % Align X axis: 1->2 vs 2->1?
    % Usually plotted on same index for comparison.
    mesh(ax, X, Y, map.Z_down, 'EdgeColor', 'r', 'FaceAlpha', 0, 'DisplayName', 'Downshift');
    
    legend(ax, 'show', 'Location', 'best');
end

function updateRPMPlot(ax, map, ratios)
    cla(ax);
    hold(ax, 'on');
    colors = parula(7);
    
    for g = 1:7
        if g+1 > length(ratios), break; end
        
        shiftRPM = map.Z_up(:, g);
        pedal = map.pedal(:);   % force column vector to match shiftRPM
        
        ratioOld = ratios(g);
        ratioNew = ratios(g+1);
        
        % Engine RPM Drop
        rpmDrop = shiftRPM .* (ratioOld - ratioNew);
        
        plot(ax, pedal, rpmDrop, 'LineWidth', 2, 'Color', colors(g,:), 'DisplayName', sprintf('%d->%d', g, g+1));
    end
    legend(ax, 'show', 'Location', 'best');
end

function updateHystPlot(ax, map)
    cla(ax);
    hold(ax, 'on');
    colors = jet(7);
    
    for g = 1:7
        upCurve = map.Z_up(:, g);
        downCurve = map.Z_down(:, g);
        pedal = map.pedal;
        if size(pedal,1) < size(pedal,2), pedal = pedal'; end
        
        hyst = upCurve - downCurve;
        
        plot3(ax, upCurve, pedal, hyst, 'LineWidth', 2, 'Color', colors(g,:), 'DisplayName', sprintf('Shift %d', g));
    end
    
    % Min Safe Plane (50 RPM)
    xLim = [0 8000];
    yLim = [0 110];
    fill3(ax, [xLim(1) xLim(2) xLim(2) xLim(1)], [yLim(1) yLim(1) yLim(2) yLim(2)], [50 50 50 50], 'r', 'FaceAlpha', 0.1, 'EdgeColor', 'none', 'DisplayName', 'Min Safe (50rpm)');
    
    legend(ax, 'show', 'Location', 'best');
end

function closeAnalysisFig(mainFig, src)
% Bulletproof close handler for the analysis window.
% Order matters:
%   1. Disarm the figure's own CloseRequestFcn FIRST so any stale callback chain
%      can't prevent or recurse into deletion.
%   2. Strip alwaysontop if set (blocks deletion on some Windows MATLAB builds).
%   3. Clear the analysisFig field on the main figure (so the next "Analyse Maps"
%      click opens a fresh window, not just brings nothing to front).
%   4. Force-delete the figure.
%   Each step wrapped in its own try/catch — one bad step must not block the rest.
    if ~isempty(src) && isvalid(src)
        try, src.CloseRequestFcn = ''; catch; end
        try
            if isprop(src,'WindowStyle') && strcmpi(src.WindowStyle,'alwaysontop')
                src.WindowStyle = 'normal';
            end
        catch; end
    end
    if ~isempty(mainFig) && isvalid(mainFig)
        try
            ad = mainFig.UserData;
            ad.analysisFig = gobjects(0);
            mainFig.UserData = ad;
        catch
        end
    end
    try
        if ~isempty(src) && isvalid(src), delete(src); end
    catch
        % Last resort: force-delete by tag
        try, delete(findall(0,'Type','figure','-and','Name',src.Name)); catch; end
    end
end

function updateTCC3DPlot(ax, map, appData)
    cla(ax);
    hold(ax, 'on');
    
    % 1. Get Map ID
    mapName = map.name;
    mapNumStr = regexp(mapName, 'SKL_GKF_(\d+)', 'tokens');
    if isempty(mapNumStr), title(ax, 'Invalid Map Name'); return; end
    mapID = str2double(mapNumStr{1}{1});
    
    if isempty(appData.wtZustand), title(ax, 'No WT ZUSTAND'); return; end
    stateIdx = find(appData.wtZustand(1,:) == mapID, 1);
    if isempty(stateIdx), title(ax, 'Map not in ZUSTAND'); return; end
    stateVal = appData.wtZustand(2, stateIdx);
    
    kwkRow = stateVal + 1;
    if kwkRow > size(appData.kwkData, 1), title(ax, 'KWK Index OOB'); return; end
    
    % Loop Gears
    % Mode Colors: RO=Red, OR=Blue, RC=Magenta
    % Use cell array instead of containers.Map with integer keys (unreliable in compiled .exe)
    modeColorList = {'r', 'b', 'm'};   % index 1=RO, 2=OR, 3=RC
    modeNames = {'Release (RO)', 'Open/Slip (OR)', 'Closed (RC)'};
    modeStyles = {'--', ':', '-'};
    
    legendEntriesCreated = false(1, 3);

    for g = 1:8
        if g > size(appData.kwkData, 2), break; end
        curveID = appData.kwkData(kwkRow, g);
        if curveID == 0, continue; end
        
        % Plot RO, OR, RC (Modes 1, 2, 3) - Skip COC (4)
        modesToPlt = [1, 2, 3]; 
        
        for k = 1:length(modesToPlt)
            mIdx = modesToPlt(k);
            suffix = getTCCSuffix(mIdx);
            searchStr = string(curveID) + suffix;
            
            % Search NWK
            for m = 1:length(appData.nwkMaps)
                nMap = appData.nwkMaps(m);
                matchIdx = find(contains(string(nMap.headers), searchStr, 'IgnoreCase', true), 1);
                if ~isempty(matchIdx)
                    xData = nMap.data(:, matchIdx);
                    yData = nMap.yAxis;
                    len = min(length(xData), length(yData));
                    
                    % Plot in 3D: X=Speed, Y=Pedal, Z=Gear
                    zData = ones(len, 1) * g;
                    
                    color = modeColorList{mIdx};
                    style = modeStyles{k};
                    
                    if ~legendEntriesCreated(mIdx)
                        % Create legend entry
                        plot3(ax, xData(1:len), yData(1:len), zData, 'Color', color, 'LineStyle', style, 'LineWidth', 1.5, 'DisplayName', modeNames{k});
                        legendEntriesCreated(mIdx) = true;
                    else
                        plot3(ax, xData(1:len), yData(1:len), zData, 'Color', color, 'LineStyle', style, 'LineWidth', 1.5, 'HandleVisibility', 'off');
                    end
                    break;
                end
            end
        end
    end
    legend(ax, 'show');
end

function s = getTCCSuffix(i)
    modes = {'_RO', '_OR', '_RC', '_COC'};
    s = modes{i};
end


function openMapAnalysis(fig)
% MAP ANALYSIS — with UK Table map filtering and drive-mode grouping for maps 0-24.
% Tab 1: Clustering  Tab 2: Anomaly Detection  Tab 3: Base Map Deviation  Tab 4: Consistency

    appData = fig.UserData;
    if isempty(appData.allMaps) || length(appData.allMaps) < 2
        uialert(fig,'Need at least 2 maps loaded for analysis.','Analyse Maps'); return;
    end
    if isfield(appData,'analysisFig') && hasValidHandle(appData, 'analysisFig')
        figure(appData.analysisFig); return;
    end

    % ── Helper: get map numbers listed in UK table ────────────────────────────
    function ukNums = getUKMapNumbers(ad)
        ukNums = [];
        if ~isfield(ad,'ukData') || isempty(ad.ukData), return; end
        for ri = 1:size(ad.ukData,1)
            if size(ad.ukData,2) < 8, continue; end
            s = strtrim(string(ad.ukData{ri,8}));
            if s == "" || s == "Not Found" || s == "Empty", continue; end
            parts = strsplit(s,',');
            for pi = 1:numel(parts)
                n = str2double(strtrim(parts{pi}));
                if ~isnan(n), ukNums(end+1) = n; end %#ok<AGROW>
            end
        end
        ukNums = unique(ukNums);
    end

    % ── Drive-mode map sets (maps 0-24) ───────────────────────────────────────
    driveModeMaps = struct( ...
        'Auto',  {{0,5,10,15,20}}, ...
        'Sport', {{2,7,12,17,22}}, ...
        'Track', {{4,9,14,19,24}});
    % SxBx grid labels (rows=Hill B0-B4, cols=Driver S0-S4)
    sxbxNums = [0,1,2,3,4; 5,6,7,8,9; 10,11,12,13,14; 15,16,17,18,19; 20,21,22,23,24];
    hillLabels = {'B0 Downhill','B1 Plain','B2 Slight','B3 Mean','B4 Steep'};
    driverLabels = {'S0','S1','S2','S3','S4'};

    % ── Get all SKL_GKF map numbers from allMaps ──────────────────────────────
    allMapNums = nan(1, length(appData.allMaps));
    for ii = 1:length(appData.allMaps)
        tok = regexp(char(appData.allMaps{ii}.name),'SKL_GKF_(\d+)','tokens','once');
        if ~isempty(tok), allMapNums(ii) = str2double(tok{1}); end
    end

    % ── Get UK table map numbers ──────────────────────────────────────────────
    ukMapNums = getUKMapNumbers(appData);

    % ── Build filtered index list: UK maps + maps 0-24 (always include) ───────
    maps024 = 0:24;
    allRelevant = union(ukMapNums, maps024);
    keepIdx = [];
    for ii = 1:length(appData.allMaps)
        n = allMapNums(ii);
        if isnan(n), continue; end
        if ismember(n, allRelevant), keepIdx(end+1) = ii; end %#ok<AGROW>
    end
    if isempty(keepIdx)
        keepIdx = 1:length(appData.allMaps);  % fallback: use all
    end

    % ── Filtered working set ──────────────────────────────────────────────────
    filtMaps  = appData.allMaps(keepIdx);
    filtNums  = allMapNums(keepIdx);
    nMaps     = length(filtMaps);
    mapNames  = strings(nMaps,1);
    for ii = 1:nMaps, mapNames(ii) = string(filtMaps{ii}.name); end

    % Tag each map: which category does it belong to?
    mapCategory = strings(nMaps,1);   % 'Auto','Sport','Track','UK','Other'
    for ii = 1:nMaps
        n = filtNums(ii);
        if ismember(n, [driveModeMaps.Auto{:}]),  mapCategory(ii) = "Auto";
        elseif ismember(n, [driveModeMaps.Sport{:}]), mapCategory(ii) = "Sport";
        elseif ismember(n, [driveModeMaps.Track{:}]), mapCategory(ii) = "Track";
        elseif ismember(n, ukMapNums),              mapCategory(ii) = "UK";
        else,                                        mapCategory(ii) = "Other";
        end
    end

    % ── Feature matrix ────────────────────────────────────────────────────────
    minRows = min(cellfun(@(m) size(m.Z_up,1), filtMaps));
    nFeat   = 14;
    X = zeros(nMaps, minRows * nFeat);
    for ii = 1:nMaps
        m  = filtMaps{ii};
        zu = m.Z_up(1:minRows,:);
        zd = m.Z_down(1:minRows,:);
        X(ii,:) = [zu(:)', zd(:)'];
    end

    % ── PCA ──────────────────────────────────────────────────────────────────
    Xc = X - mean(X,1);
    scores = zeros(nMaps,2); explained = [0;0];
    try
        ws = warning('off','stats:pca:ColRankDeficiency');
        [~, sc, ~, ~, expl] = pca(Xc); warning(ws);
        if size(sc,2)>=1, scores(:,1)=sc(:,1); explained(1)=expl(1); end
        if size(sc,2)>=2, scores(:,2)=sc(:,2); explained(2)=expl(2); end
    catch
        scores(:,1)=Xc(:,1);
        if size(Xc,2)>1, scores(:,2)=Xc(:,2); else, scores(:,2)=zeros(nMaps,1); end
    end

    % ── K-means ──────────────────────────────────────────────────────────────
    k = min(5, nMaps);
    try
        rng(42);
        clusterIDs = kmeans(scores(:,1:min(2,end)), k, 'Replicates',5);
    catch
        clusterIDs = ones(nMaps,1);
    end

    % ── Pairwise distances ───────────────────────────────────────────────────
    try,  D = squareform(pdist(X,'euclidean')); catch, D = zeros(nMaps); end

    % ── Anomaly scores ────────────────────────────────────────────────────────
    nPC = min(10,size(scores,2)); Xrecon = zeros(size(Xc));
    try, [coeff,~]=pca(Xc); Xrecon=scores(:,1:nPC)*coeff(:,1:nPC)'; catch; end
    reconErr = sum((Xc-Xrecon).^2,2);
    muErr=mean(reconErr); sigErr=std(reconErr); if sigErr==0, sigErr=1; end
    anomalyZ = (reconErr-muErr)/sigErr;
    isAnomaly = anomalyZ > 2;

    % ── Colour per category ───────────────────────────────────────────────────
    catColors = containers.Map( ...
        {'Auto','Sport','Track','UK','Other'}, ...
        {[0.2 0.7 0.3], [0.85 0.3 0.3], [0.3 0.5 0.85], [0.7 0.4 0.85], [0.6 0.6 0.6]});
    function c = catColor(cat)
        if catColors.isKey(char(cat)), c = catColors(char(cat));
        else, c = [0.5 0.5 0.5]; end
    end

    % ── Window ────────────────────────────────────────────────────────────────
    scrn = get(0,'ScreenSize');
    aW=min(1300,scrn(3)-60); aH=min(860,scrn(4)-80);
    aFig = uifigure('Name',sprintf('Map Analysis  (%d maps, %d from UK table)', ...
        nMaps, sum(ismember(filtNums,ukMapNums))), ...
        'Position',[scrn(1)+(scrn(3)-aW)/2, scrn(2)+(scrn(4)-aH)/2, aW, aH], ...
        'Color',[0.97 0.97 0.97]);
    aFig.CloseRequestFcn = @(src,~) closeAnalysisFig(fig,src);
    appData.analysisFig = aFig; fig.UserData = appData;

    glMain = uigridlayout(aFig,[2 1]);
    glMain.RowHeight = {50,'1x'};
    glMain.Padding = [8 8 8 4];
    glMain.RowSpacing = 4;

    % ── Build unified dropdown items from drive modes + UK table entries ─────
    % Fixed drive mode entries
    fixedItems  = {'All maps', 'Auto / Normal', 'Sport', 'Track / Baha'};
    fixedNums   = {[], [0 1 5 6 10 11 15 16 20 21], [2 3 7 8 12 13 17 18 22 23], [4 9 14 19 24]};

    % UK table entries: "Sand UKSND" format (col 1 = UK name, col 2 = Abbrev)
    % Multiple rows can share the same UK+Abbrev (e.g. Cruise Control UKCC has
    % many SKLIDs). We UNION all their map numbers into one dropdown entry.
    ukDropItems = {};
    ukDropNums  = {};   % cell of numeric arrays, one per UK entry
    if isfield(appData,'ukData') && ~isempty(appData.ukData) && size(appData.ukData,2) >= 8
        ud = appData.ukData;
        for ri = 1:size(ud,1)
            ukName   = strtrim(char(ud{ri,1}));
            abbrev   = strtrim(char(ud{ri,2}));
            mapStr   = strtrim(string(ud{ri,8}));
            if mapStr == "" || mapStr == "Not Found" || mapStr == "Empty", continue; end
            parts = strsplit(mapStr, ',');
            nums  = [];
            for pi2 = 1:numel(parts)
                n2 = str2double(strtrim(parts{pi2}));
                if ~isnan(n2), nums(end+1) = n2; end %#ok<AGROW>
            end
            if isempty(nums), continue; end
            label = strtrim([ukName ' ' abbrev]);
            if isempty(label), label = abbrev; end
            existPos = find(strcmp(ukDropItems, label), 1);
            if isempty(existPos)
                % First time we see this label — add new entry
                ukDropItems{end+1} = label;          %#ok<AGROW>
                ukDropNums{end+1}  = nums;           %#ok<AGROW>
            else
                % Same UK+Abbrev seen again — union the map numbers
                ukDropNums{existPos} = unique([ukDropNums{existPos}, nums]);
            end
        end
    end

    allDropItems = [fixedItems, ukDropItems];
    allDropNums  = [fixedNums,  ukDropNums];

    % ── TOP FILTER BAR ────────────────────────────────────────────────────────
    pnlFilter = uipanel(glMain,'BorderType','line','BackgroundColor',[0.93 0.96 0.99]);
    pnlFilter.Layout.Row = 1;
    glFilt = uigridlayout(pnlFilter,[1 4]);
    glFilt.ColumnWidth = {'fit','1x','fit','fit'};
    glFilt.Padding = [10 4 10 4];

    uilabel(glFilt,'Text','Filter by mode / UK entry:','FontWeight','bold','FontSize',10);
    ddMode = uidropdown(glFilt,'Items',allDropItems,'Value','All maps','FontSize',10);
    lblCount = uilabel(glFilt,'Text', ...
        sprintf('%d maps shown  |  UK entries: %d', nMaps, numel(ukDropItems)), ...
        'FontSize',9,'FontColor',[0.3 0.3 0.5],'FontAngle','italic');
    uibutton(glFilt,'Text','ℹ Drive Mode Info','BackgroundColor',[0.94 0.94 0.94], ...
        'FontSize',9,'ButtonPushedFcn',@(~,~) showDriveModeInfo());

    tgMain = uitabgroup(glMain);
    tgMain.Layout.Row = 2;

    % ── Shared filter: get visible map indices from dropdown selection ─────────
    function visIdx = getVisibleIdx()
        selItem = ddMode.Value;
        selPos  = find(strcmp(allDropItems, selItem), 1);
        if isempty(selPos) || isempty(allDropNums{selPos})
            visIdx = 1:nMaps;   % "All maps"
            return;
        end
        targetNums = allDropNums{selPos};
        visIdx = find(ismember(filtNums, targetNums));
        if isempty(visIdx), visIdx = 1:nMaps; end
    end

    % ══════════════════════════════════════════════════════════════════════════
    % TAB 1 — CLUSTERING
    % ══════════════════════════════════════════════════════════════════════════
    tab1 = uitab(tgMain,'Title','🔵  Clustering');
    gl1  = uigridlayout(tab1,[3 2]);
    gl1.RowHeight   = {28, 20, '1x'};
    gl1.ColumnWidth = {'2x','1x'};
    gl1.Padding = [6 6 6 6];

    % Row 1: toolbar (title + About button)
    pnlT1 = uipanel(gl1,'BorderType','none');
    pnlT1.Layout.Row=1; pnlT1.Layout.Column=[1 2];
    glT1 = uigridlayout(pnlT1,[1 2]); glT1.ColumnWidth={'1x','fit'}; glT1.Padding=[0 0 0 0];
    lblT1 = uilabel(glT1,'Text','PCA Cluster Plot  (click dot = load as Map A)', ...
        'FontWeight','bold','FontSize',10);
    uibutton(glT1,'Text','ℹ About','BackgroundColor',[0.94 0.94 0.94],'FontWeight','bold', ...
        'ButtonPushedFcn',@(~,~) showTabAbout(aFig,'clustering'));

    % Row 2: colour-coded category legend
    cats = {'Auto','Sport','Track','UK','Other'};
    catLbls = {'Auto/Normal','Sport','Track/Baha','UK table','Other'};
    legTxt = '';
    for ci=1:numel(cats)
        c = catColors(cats{ci})*255;
        legTxt = [legTxt sprintf('<font color="rgb(%d,%d,%d)">■ %s</font>  ', ...
            round(c(1)),round(c(2)),round(c(3)), catLbls{ci})]; %#ok<AGROW>
    end
    legLbl = uilabel(gl1,'Text',legTxt,'Interpreter','html','FontSize',9, ...
        'HorizontalAlignment','left');
    legLbl.Layout.Row=2; legLbl.Layout.Column=[1 2];

    axPCA = uiaxes(gl1); hold(axPCA,'on'); grid(axPCA,'on'); box(axPCA,'on');
    axPCA.Layout.Row=3; axPCA.Layout.Column=1;
    xlabel(axPCA,sprintf('PC1 (%.1f%%)',explained(1)));
    ylabel(axPCA,sprintf('PC2 (%.1f%%)',explained(2)));

    pnlInfo = uipanel(gl1,'Title','Selected Map','FontWeight','bold');
    pnlInfo.Layout.Row=3; pnlInfo.Layout.Column=2;
    glInfo = uigridlayout(pnlInfo,[4 1]);
    glInfo.RowHeight = {'fit','fit','fit','1x'};
    lblClu = uilabel(glInfo,'Text','Click a dot','FontSize',10,'WordWrap','on');
    lblClu.Layout.Row=1;
    lblCat = uilabel(glInfo,'Text','','FontSize',10,'FontWeight','bold');
    lblCat.Layout.Row=2;
    lstCluster = uilistbox(glInfo,'Items',{},'FontSize',9);
    lstCluster.Layout.Row=[3 4];

    % Draw PCA scatter
    dotHandles = gobjects(nMaps,1);
    clrMap = lines(k);
    for ii = 1:nMaps
        c = catColor(mapCategory(ii));
        ms = 10; mk = 'o';
        if isAnomaly(ii), ms=16; mk='p'; end
        dotHandles(ii) = plot(axPCA, scores(ii,1), scores(ii,2), mk, ...
            'MarkerSize',ms,'MarkerFaceColor',c,'MarkerEdgeColor',c*0.6, ...
            'LineWidth',1.2,'UserData',ii,'ButtonDownFcn',@(s,~) onDot(s.UserData));
        text(axPCA, scores(ii,1), scores(ii,2), sprintf('  %g',filtNums(ii)), ...
            'FontSize',7,'Color',c*0.7,'PickableParts','none');
    end

    function onDot(idx)
        nm = char(mapNames(idx));
        lblClu.Text = sprintf('%s\nCluster %d  |  Z=%.2f', nm, clusterIDs(idx), anomalyZ(idx));
        lblCat.Text = sprintf('Category: %s', mapCategory(idx));
        lblCat.FontColor = catColor(mapCategory(idx));
        cIdx = find(clusterIDs == clusterIDs(idx));
        items = cell(1,numel(cIdx));
        for ci2=1:numel(cIdx), items{ci2}=char(mapNames(cIdx(ci2))); end
        lstCluster.Items = items;
        h2 = appData.handles;
        if ismember(nm, h2.dd1.Items)
            h2.dd1.Value = nm; appData.currentMapName = nm;
            fig.UserData = appData; updatePlot(fig); appData = fig.UserData;
        end
    end

    function refreshPCA()
        vis = getVisibleIdx();
        for ii2=1:nMaps
            if ismember(ii2,vis), dotHandles(ii2).Visible = 'on'; else, dotHandles(ii2).Visible = 'off'; end
        end
        lblT1.Text = sprintf('PCA Cluster Plot — %d / %d maps shown  (click dot = load as Map A)', ...
            numel(vis), nMaps);
    end

    % ══════════════════════════════════════════════════════════════════════════
    % TAB 2 — ANOMALY DETECTION
    % ══════════════════════════════════════════════════════════════════════════
    tab2 = uitab(tgMain,'Title','⚠  Anomaly Detection');
    gl2  = uigridlayout(tab2,[3 2]);
    gl2.RowHeight   = {28,'1x','1.2x'};
    gl2.ColumnWidth = {'2x','1x'};
    gl2.Padding = [6 6 6 6];

    pnlT2 = uipanel(gl2,'BorderType','none');
    pnlT2.Layout.Row=1; pnlT2.Layout.Column=[1 2];
    glT2 = uigridlayout(pnlT2,[1 2]); glT2.ColumnWidth={'1x','fit'}; glT2.Padding=[0 0 0 0];
    lblT2 = uilabel(glT2,'Text','Anomaly Detection — maps with unusual shift patterns', ...
        'FontWeight','bold','FontSize',10);
    uibutton(glT2,'Text','ℹ About','BackgroundColor',[0.94 0.94 0.94],'FontWeight','bold', ...
        'ButtonPushedFcn',@(~,~) showTabAbout(aFig,'anomaly'));

    axBar = uiaxes(gl2); hold(axBar,'on'); grid(axBar,'on');
    axBar.Layout.Row=2; axBar.Layout.Column=[1 2];
    xlabel(axBar,'Map'); ylabel(axBar,'Anomaly Z-score');
    yline(axBar,2,'r--','2σ threshold','LineWidth',1.5,'LabelHorizontalAlignment','left');

    pnlList = uipanel(gl2,'Title','Anomalous Maps','FontWeight','bold');
    pnlList.Layout.Row=3; pnlList.Layout.Column=2;
    glList = uigridlayout(pnlList,[2 1]); glList.RowHeight={'fit','1x'};
    lblAnom = uilabel(glList,'Text','','FontSize',11,'FontWeight','bold');
    lstAnom = uilistbox(glList,'Items',{},'FontSize',10, ...
        'ValueChangedFcn',@(src,~) onAnomalySelect(src));

    pnlDetail = uipanel(gl2,'Title','Selected Map — Shift Point Heatmap','FontWeight','bold','FontSize',10);
    pnlDetail.Layout.Row=3; pnlDetail.Layout.Column=1;
    axDet = uiaxes(uigridlayout(pnlDetail,[1 1]));
    axis(axDet,'off'); title(axDet,'Select a map from the list');

    function refreshAnomaly()
        vis = getVisibleIdx();
        cla(axBar);
        hold(axBar,'on'); grid(axBar,'on');
        yline(axBar,2,'r--','2σ','LineWidth',1.5,'LabelHorizontalAlignment','left');
        anomIdx2 = []; anomItems2 = {};
        for bi=1:numel(vis)
            ii2=vis(bi); z=anomalyZ(ii2);
            if isAnomaly(ii2), c = [0.9 0.2 0.2]; else, c = [0.3 0.6 0.8]; end
            b = bar(axBar,bi,z,'FaceColor',c,'EdgeColor',c*0.7);
            b.UserData = ii2;
            b.ButtonDownFcn = @(s,~) onBarClick(s.UserData);
            if isAnomaly(ii2)
                anomIdx2(end+1) = ii2;
                anomItems2{end+1} = sprintf('Z=%.2f  %s',z,char(mapNames(ii2)));
            end
        end
        lbls = cell(1,numel(vis));
        for j = 1:numel(vis)
            idx = vis(j);
            if ~isnan(filtNums(idx))
                fNum = filtNums(idx);
            else
                fNum = -1;
            end
            lbls{j} = sprintf('%g', fNum);
        end
        set(axBar,'XTick',1:numel(vis),'XTickLabel',lbls,'XTickLabelRotation',45);
        nAnom2 = numel(anomIdx2);
        if nAnom2==0, lblAnom.Text='✅ No anomalies'; lblAnom.FontColor=[0.1 0.6 0.1];
        else, lblAnom.Text=sprintf('⚠ %d anomalies',nAnom2); lblAnom.FontColor=[0.85 0.2 0.2]; end
        lstAnom.Items = anomItems2;
        lblT2.Text = sprintf('Anomaly Detection — %d / %d maps shown', numel(vis), nMaps);
    end

    function onBarClick(idx)
        tgMain.SelectedTab = tab2;
        nm = char(mapNames(idx));
        h2 = appData.handles;
        if ismember(nm,h2.dd1.Items)
            h2.dd1.Value=nm; appData.currentMapName=nm;
            fig.UserData=appData; updatePlot(fig); appData=fig.UserData;
        end
        drawHeatmap(idx);
    end
    function onAnomalySelect(src)
        parts = strsplit(char(src.Value),'  ');
        if numel(parts)<2, return; end
        nm = strjoin(parts(2:end),'  ');
        idx = find(strcmp(mapNames,string(nm)),1);
        if ~isempty(idx), onBarClick(idx); end
    end
    function drawHeatmap(idx)
        cla(axDet); axis(axDet,'on');
        m   = filtMaps{idx}; cid = clusterIDs(idx);
        cIdx2 = find(clusterIDs==cid);
        meanUp=zeros(minRows,7); meanDn=zeros(minRows,7);
        for ci3=1:numel(cIdx2)
            mm=filtMaps{cIdx2(ci3)};
            meanUp=meanUp+mm.Z_up(1:minRows,:);
            meanDn=meanDn+mm.Z_down(1:minRows,:);
        end
        meanUp=meanUp/numel(cIdx2); meanDn=meanDn/numel(cIdx2);
        devUp=(m.Z_up(1:minRows,:)-meanUp)./max(1,meanUp);
        devDn=(m.Z_down(1:minRows,:)-meanDn)./max(1,meanDn);
        devAll=[devUp,devDn]*100;
        imagesc(axDet,devAll);
        nC=64;
        cmap=[linspace(0.9,1,nC/2)',linspace(0.2,0.95,nC/2)',linspace(0.2,0.2,nC/2)'; ...
              linspace(1,0.2,nC/2)',linspace(0.95,0.7,nC/2)',linspace(0.2,0.2,nC/2)'];
        colormap(axDet,cmap); clim(axDet,[-30 30]);
        cb=colorbar(axDet); cb.Label.String='% deviation from cluster mean';
        xlabel(axDet,'Gear column'); ylabel(axDet,'Pedal row');
        colLbls={'US12','US23','US34','US45','US56','US67','US78','DS21','DS32','DS43','DS54','DS65','DS76','DS87'};
        title(axDet,sprintf('%s — Cluster %d deviation',char(mapNames(idx)),cid));
        set(axDet,'XTick',1:14,'XTickLabel',colLbls,'XTickLabelRotation',45);
    end

    % ══════════════════════════════════════════════════════════════════════════
    % TAB 3 — BASE MAP DEVIATION
    % ══════════════════════════════════════════════════════════════════════════
    tab3 = uitab(tgMain,'Title','📊  Base Map Deviation');
    gl3  = uigridlayout(tab3,[3 1]);
    gl3.RowHeight = {35,'2x','1x'};
    gl3.Padding = [8 8 8 8];

    baseIdx = find(strcmp(mapNames,'SKL_GKF_5'),1);
    % Pre-declare Tab 3 shared variables (used in refreshDeviation nested function)
    ddDev=[]; axRank=[]; totalDev=zeros(nMaps,1); barColours=zeros(nMaps,3);
    state3=containers.Map({'curOrder'},{1:nMaps}); doUpdatePlots3=@(x)x;
    if isempty(baseIdx)
        uilabel(gl3,'Text','SKL_GKF_5 not found in loaded maps.', ...
            'HorizontalAlignment','center','FontSize',13);
    else
        baseMap = filtMaps{baseIdx};
        baseUp  = baseMap.Z_up(1:minRows,:);
        baseDn  = baseMap.Z_down(1:minRows,:);
        devMatrix = zeros(nMaps,14);
        for ii=1:nMaps
            m2=filtMaps{ii};
            zu2=m2.Z_up(1:minRows,:); zd2=m2.Z_down(1:minRows,:);
            dUp=mean(abs(zu2-baseUp)./max(1,abs(baseUp)),1)*100;
            dDn=mean(abs(zd2-baseDn)./max(1,abs(baseDn)),1)*100;
            devMatrix(ii,:)=[dUp,dDn];
        end
        totalDev = mean(devMatrix,2);
        [~,sortI] = sort(totalDev,'descend');
        colLbls3 = {'US12','US23','US34','US45','US56','US67','US78','DS21','DS32','DS43','DS54','DS65','DS76','DS87'};

        pnlCtrl = uipanel(gl3,'BorderType','none'); pnlCtrl.Layout.Row=1;
        glCtrl  = uigridlayout(pnlCtrl,[1 6]);
        glCtrl.ColumnWidth={'fit','1x',20,'fit','fit','fit'};
        glCtrl.Padding=[0 2 0 2];
        uilabel(glCtrl,'Text','Compare map:','FontWeight','bold');
        ddDev = uidropdown(glCtrl,'Items',cellstr(mapNames),'Value',char(mapNames(sortI(1))));
        uilabel(glCtrl,'Text','');
        uilabel(glCtrl,'Text','Sort by:','FontWeight','bold');
        ddSort = uidropdown(glCtrl,'Items',{'Most different','Least different','Map number'},'Value','Most different');
        uibutton(glCtrl,'Text','ℹ About','BackgroundColor',[0.94 0.94 0.94],'FontWeight','bold', ...
            'ButtonPushedFcn',@(~,~) showTabAbout(aFig,'basemap'));

        pnlGear=uipanel(gl3,'Title','Deviation per gear column  (selected map vs SKL_GKF_5)', ...
            'FontWeight','bold','FontSize',10); pnlGear.Layout.Row=2;
        glGear=uigridlayout(pnlGear,[2 1]); glGear.RowHeight={22,'1x'};
        uilabel(glGear,'Text','📈  Select map → loads as Map A.  SKL_GKF_5 auto-loaded as Map B.', ...
            'FontSize',9,'FontColor',[0.3 0.3 0.7],'FontAngle','italic','HorizontalAlignment','center');
        axGear=uiaxes(glGear); hold(axGear,'on'); grid(axGear,'on');
        xlabel(axGear,'Gear column'); ylabel(axGear,'% deviation from base');

        pnlRank=uipanel(gl3,'Title','All maps ranked by deviation  (click bar = select)', ...
            'FontWeight','bold','FontSize',10); pnlRank.Layout.Row=3;
        axRank=uiaxes(uigridlayout(pnlRank,[1 1])); hold(axRank,'on'); grid(axRank,'on');
        ylabel(axRank,'Avg % deviation');

        devNorm=(totalDev-min(totalDev))/max(1,max(totalDev)-min(totalDev));
        barColours=[devNorm,1-devNorm*0.8,0.2*ones(nMaps,1)];
        state3=containers.Map({'curOrder'},{sortI});

        doDrawRanking3 = @(order) localDrawRanking(order,state3,axRank,totalDev,barColours,mapNames,nMaps,ddDev);
        doUpdatePlots3 = @(nm) localUpdateDevPlots(nm,state3,axGear,axRank,devMatrix,totalDev, ...
            colLbls3,mapNames,baseMap,baseUp,filtMaps,fig,nMaps,barColours,ddDev);

        ddDev.ValueChangedFcn  = @(src,~) doUpdatePlots3(src.Value);
        ddSort.ValueChangedFcn = @(src,~) localRefreshRanking(src.Value,state3,totalDev,nMaps,doDrawRanking3);

        doDrawRanking3(sortI);
        doUpdatePlots3(char(mapNames(sortI(1))));
    end  % end if ~isempty(baseIdx)

    % ══════════════════════════════════════════════════════════════════════════
    % TAB 4 — CONSISTENCY CHECK
    % ══════════════════════════════════════════════════════════════════════════
    tab4 = uitab(tgMain,'Title','✅  Consistency Check');
    gl4  = uigridlayout(tab4,[3 1]);
    gl4.RowHeight={28,'fit','1x'}; gl4.Padding=[6 6 6 6];

    pnlT4=uipanel(gl4,'BorderType','none'); pnlT4.Layout.Row=1;
    glT4=uigridlayout(pnlT4,[1 2]); glT4.ColumnWidth={'1x','fit'}; glT4.Padding=[0 0 0 0];
    lblT4=uilabel(glT4,'Text','Consistency Check — monotonicity and hysteresis', ...
        'FontWeight','bold','FontSize',10);
    uibutton(glT4,'Text','ℹ About','BackgroundColor',[0.94 0.94 0.94],'FontWeight','bold', ...
        'ButtonPushedFcn',@(~,~) showTabAbout(aFig,'consistency'));

    colNames4={'Map','Category','Up Monotonic','Down Monotonic','Up>Down (Hyst)','Violations'};
    lblSum4=uilabel(gl4,'Text','','FontSize',12,'FontWeight','bold', ...
        'HorizontalAlignment','center'); lblSum4.Layout.Row=2;
    tbl4=uitable(gl4,'ColumnName',colNames4,'ColumnWidth',{150,80,120,130,120,'1x'},'RowName',{});
    tbl4.Layout.Row=3;

    function refreshConsistency()
        vis=getVisibleIdx();
        nV=numel(vis); tblData=cell(nV,6); totalViol=0;
        for bi3=1:nV
            ii2=vis(bi3); m3=filtMaps{ii2};
            zu3=m3.Z_up; zd3=m3.Z_down;
            violations={};
            upMono=true;
            for g=1:7, if any(diff(zu3(:,g))<0), upMono=false; violations{end+1}=sprintf('US%d%d',g,g+1); end, end %#ok<AGROW>
            dnMono=true;
            for g=1:7, if any(diff(zd3(:,g))<0), dnMono=false; violations{end+1}=sprintf('DS%d%d',g+1,g); end, end %#ok<AGROW>
            hystOK=true;
            for g=1:7
                nR2=min(size(zu3,1),size(zd3,1));
                if any(zu3(1:nR2,g)<=zd3(1:nR2,g)), hystOK=false; violations{end+1}=sprintf('HystG%d',g); end %#ok<AGROW>
            end
            if ~isempty(violations), totalViol=totalViol+1; end
            tblData{bi3,1}=char(mapNames(ii2));
            tblData{bi3,2}=char(mapCategory(ii2));
            tblData{bi3,3}=tf2str(upMono); tblData{bi3,4}=tf2str(dnMono);
            tblData{bi3,5}=tf2str(hystOK); tblData{bi3,6}=strjoin(violations,', ');
        end
        tbl4.Data=tblData;
        if totalViol==0
            lblSum4.Text=sprintf('✅  All %d maps passed consistency checks.',nV);
            lblSum4.FontColor=[0.1 0.6 0.1];
        else
            lblSum4.Text=sprintf('⚠  %d / %d maps have violations.',totalViol,nV);
            lblSum4.FontColor=[0.85 0.2 0.2];
        end
        lblT4.Text=sprintf('Consistency Check — %d / %d maps shown',nV,nMaps);
        try
            removeStyle(tbl4);
            failRows=find(cellfun(@(x)~isempty(x),tblData(:,6)));
            if ~isempty(failRows)
                addStyle(tbl4,uistyle('BackgroundColor',[1 0.92 0.92]),'row',failRows');
            end
        catch; end
    end

    function s = tf2str(v)
        if v, s='✅ OK'; else, s='❌ FAIL'; end
    end

    % ── refreshDeviation — updates Tab 3 for current filter selection ─────────
    function refreshDeviation()
        if isempty(baseIdx), return; end
        vis = getVisibleIdx();
        visNames = cellstr(mapNames(vis));
        cur = ddDev.Value;
        ddDev.Items = visNames;
        if ismember(cur, visNames), ddDev.Value = cur;
        else, ddDev.Value = visNames{1}; end
        visDev = totalDev(vis);
        [~,vsI] = sort(visDev,'descend');
        vsOrder = vis(vsI);
        state3('curOrder') = vsOrder;
        cla(axRank); hold(axRank,'on'); grid(axRank,'on'); ylabel(axRank,'Avg % deviation');
        for bi2 = 1:numel(vis)
            mi2 = vis(vsI(bi2)); c2 = barColours(mi2,:);
            b2 = bar(axRank, bi2, totalDev(mi2), 'FaceColor',c2,'EdgeColor',c2*0.7);
            b2.UserData = mi2;
            b2.ButtonDownFcn = @(s,~) doUpdatePlots3(char(mapNames(s.UserData)));
            if ~isnan(filtNums(mi2)), fNum = filtNums(mi2); else, fNum = -1; end
            text(axRank, bi2, totalDev(mi2)+0.5, ...
                sprintf('%g', fNum), ...
                'HorizontalAlignment','center','FontSize',7,'Rotation',45);
        end
        doUpdatePlots3(ddDev.Value);
    end

    % ── Filter application ────────────────────────────────────────────────────
    function applyFilter()
        refreshPCA();
        refreshAnomaly();
        if ~isempty(baseIdx), refreshDeviation(); end
        refreshConsistency();
    end

    % ── Drive mode info dialog ────────────────────────────────────────────────
    function showDriveModeInfo()
        msg = sprintf(['Drive Mode Map Assignment (SxBx grid):\n\n' ...
            'Auto / Normal  → Maps  0,1, 5,6, 10,11, 15,16, 20,21  (S0+S1 columns)\n' ...
            'Sport          → Maps  2,3, 7,8, 12,13, 17,18, 22,23  (S2+S3 columns)\n' ...
            'Track / Baha   → Maps  4,  9,   14,    19,    24      (S4 column)\n\n' ...
            'Hill grades (rows): B0=Downhill, B1=Plain, B2=Slight, B3=Mean, B4=Steep\n\n' ...
            'UK entries are loaded directly from the UK & STAT Table map numbers.']);
        uialert(aFig, msg, 'Drive Mode Info', 'Icon','info');
    end

    % ══════════════════════════════════════════════════════════════════════════
    % TAB 5 — LEVEL COMPARISON  (Normal vs Aggressive)
    % ══════════════════════════════════════════════════════════════════════════
    tab5 = uitab(tgMain,'Title','⚖  Level Comparison');
    gl5  = uigridlayout(tab5,[4 1]);
    gl5.RowHeight={28,100,22,'1x'}; gl5.Padding=[6 6 6 6]; gl5.RowSpacing=4;

    % ── Toolbar ──────────────────────────────────────────────────────────────
    pnlT5=uipanel(gl5,'BorderType','none'); pnlT5.Layout.Row=1;
    glT5=uigridlayout(pnlT5,[1 2]); glT5.ColumnWidth={'1x','fit'}; glT5.Padding=[0 0 0 0];
    uilabel(glT5,'Text','Level 1 vs Level 2 — Logic Analysis', ...
        'FontWeight','bold','FontSize',10);
    uibutton(glT5,'Text','ℹ About','BackgroundColor',[0.94 0.94 0.94],'FontWeight','bold', ...
        'ButtonPushedFcn',@(~,~) showTabAbout(aFig,'levelcomp'));

    % ── Selector panel: single row with maps + tolerances + process ───────────
    pnlSel=uipanel(gl5,'BorderType','none','BackgroundColor',[0.93 0.93 1]);
    pnlSel.Layout.Row=2;
    glSel=uigridlayout(pnlSel,[2 1]);
    glSel.RowHeight={32,32}; glSel.Padding=[6 6 6 6]; glSel.RowSpacing=6;

    % ── Row 1: Map dropdowns + Process + Export ───────────────────────────────
    glR1=uigridlayout(glSel,[1 7]);
    glR1.ColumnWidth={'fit',180,'fit',180,'1x','fit','fit'};
    glR1.Padding=[0 0 0 0]; glR1.ColumnSpacing=8;
    uilabel(glR1,'Text','Level 1 (Normal):','FontWeight','bold');
    ddL1=uidropdown(glR1,'Items',cellstr(mapNames),'BackgroundColor',[0.9 1 0.9]);
    uilabel(glR1,'Text','Level 2 (Aggressive):','FontWeight','bold');
    ddL2=uidropdown(glR1,'Items',cellstr(mapNames),'BackgroundColor',[1 0.9 0.9]);
    if numel(mapNames)>=2, ddL2.Value=char(mapNames(2)); end
    uilabel(glR1,'Text','');
    btnProcess=uibutton(glR1,'Text','Process','BackgroundColor',[0.2 0.55 0.9],'FontColor',[1 1 1],'FontWeight','bold','FontSize',11);
    btnExport5=uibutton(glR1,'Text','Export','BackgroundColor',[0.9 0.9 0.9],'FontWeight','bold');

    % ── Row 2: Tolerances ─────────────────────────────────────────────────────
    glR2=uigridlayout(glSel,[1 17]);
    glR2.ColumnWidth={'fit',38,'fit','fit',38,'fit','fit',30,'fit','fit',30,'fit',30,'fit',36,'fit','1x'};
    glR2.Padding=[0 0 0 0]; glR2.ColumnSpacing=5;
    uilabel(glR2,'Text','L2-L1 margin:','FontColor',[0.25 0.25 0.55],'FontWeight','bold');
    efRPM=uieditfield(glR2,'numeric','Value',0,'Limits',[-500 500],'BackgroundColor',[1 1 0.88],'Tooltip','Min RPM that L2 must exceed L1. 0=strict.');
    uilabel(glR2,'Text','RPM');
    uilabel(glR2,'Text','  Full-pedal min delta:','FontColor',[0.25 0.25 0.55],'FontWeight','bold');
    efMinDelta=uieditfield(glR2,'numeric','Value',50,'Limits',[0 2000],'BackgroundColor',[1 1 0.88],'Tooltip','Min RPM L2 must exceed L1 at the last N full-throttle rows.');
    uilabel(glR2,'Text','RPM');
    uilabel(glR2,'Text','  Full-pedal rows:','FontColor',[0.25 0.25 0.55],'FontWeight','bold');
    efFullPedRows=uieditfield(glR2,'numeric','Value',3,'Limits',[1 10],'BackgroundColor',[1 1 0.88],'Tooltip','How many bottom rows count as full throttle.');
    uilabel(glR2,'Text','rows');
    uilabel(glR2,'Text','  Low-pedal ignore <:','FontColor',[0.25 0.25 0.55],'FontWeight','bold');
    efLowPed=uieditfield(glR2,'numeric','Value',10,'Limits',[0 50],'BackgroundColor',[1 1 0.88],'Tooltip','Skip pedal rows below this % (idle/creep region).');
    uilabel(glR2,'Text','%');
    efSpread=uieditfield(glR2,'numeric','Value',15,'Limits',[0 50],'BackgroundColor',[1 1 0.88],'Tooltip','Spread tolerance %: how much narrower L2 spread can be vs L1.');
    uilabel(glR2,'Text','% spread-tol');
    efSpreadIssue=uieditfield(glR2,'numeric','Value',2,'Limits',[0 50],'BackgroundColor',[1 0.88 0.88],'Tooltip','Spread violations above this count = ISSUE (else WARN).');
    uilabel(glR2,'Text','rows=issue');
    uilabel(glR2,'Text','');

    % Row 3: summary status banner (updated by runLevelComparison)
    lblSum5 = uilabel(gl5,'Text','', ...
        'FontWeight','bold','FontSize',11,'HorizontalAlignment','center');
    lblSum5.Layout.Row=3;

    splitPnl=uipanel(gl5,'BorderType','none'); splitPnl.Layout.Row=4;
    glSplit=uigridlayout(splitPnl,[1 2]);
    glSplit.ColumnWidth={'1x','1x'}; glSplit.Padding=[0 0 0 0]; glSplit.ColumnSpacing=6;

    % LEFT: summary table — click row to drill down
    pnlLeft=uipanel(glSplit,'Title','Check Summary  (click a row to inspect violations)','FontWeight','bold');
    pnlLeft.Layout.Column=1;
    glLeft=uigridlayout(pnlLeft,[1 1]);
    colNames5={'Gear Pair','Check','Avg L1','Avg L2','Status','Violations'};
    tbl5=uitable(glLeft,'ColumnName',colNames5, ...
        'ColumnWidth',{75,145,60,60,75,'1x'},'RowName',{});
    tbl5.SelectionChangedFcn=@(~,e) onTableRowSelect(e);

    % RIGHT: detail panel — violation table + plot (no listbox)
    pnlRight=uipanel(glSplit,'Title','Violation Detail','FontWeight','bold');
    pnlRight.Layout.Column=2;
    glRight=uigridlayout(pnlRight,[2 1]);
    glRight.RowHeight={100,'1x'}; glRight.Padding=[4 4 4 4]; glRight.RowSpacing=4;

    colNamesD={'Pedal %','L1 RPM','L2 RPM','Diff (L2-L1)','Rule Broken'};
    tblDetail=uitable(glRight,'ColumnName',colNamesD, ...
        'ColumnWidth',{60,70,70,90,'1x'},'RowName',{},'Data',{});
    tblDetail.Layout.Row=1;

    axCmp=uiaxes(glRight); hold(axCmp,'on'); grid(axCmp,'on'); box(axCmp,'on');
    axCmp.Layout.Row=2;
    xlabel(axCmp,'Output RPM'); ylabel(axCmp,'Pedal %');
    title(axCmp,'Click a row in the summary table to plot');

    % ── Process callback ──────────────────────────────────────────────────────
    btnProcess.ButtonPushedFcn = @(~,~) runLevelComparison();
    btnExport5.ButtonPushedFcn = @(~,~) exportLevelResults();

    function runLevelComparison()
        allN = getMapNames(appData);
        idxL1 = find(allN == string(ddL1.Value),1);
        idxL2 = find(allN == string(ddL2.Value),1);
        if isempty(idxL1)||isempty(idxL2)
            lblSum5.Text='❌  One or both maps not found.'; lblSum5.FontColor=[0.8 0 0]; return;
        end
        if idxL1==idxL2
            lblSum5.Text='❌  Level 1 and Level 2 must be different maps.'; lblSum5.FontColor=[0.8 0 0]; return;
        end
        m1=appData.allMaps{idxL1}; m2=appData.allMaps{idxL2};
        nR=min([size(m1.Z_up,1),size(m2.Z_up,1),size(m1.Z_down,1),size(m2.Z_down,1)]);
        nC=min([size(m1.Z_up,2),size(m2.Z_up,2),7]);
        ped1=double(m1.pedal(1:nR));

        % Read user tolerance inputs
        rpmMargin    = efRPM.Value;
        spreadTolPct = efSpread.Value/100;
        spreadIssueThr = efSpreadIssue.Value;
        minDeltaFP   = efMinDelta.Value;       % min RPM L2 must exceed L1 at full pedal
        fullPedRows  = round(efFullPedRows.Value); % how many bottom rows = full throttle
        lowPedIgnore = efLowPed.Value;         % ignore pedal rows below this %

        % Derive which rows are "active" (above low-pedal threshold)
        activeRows = find(ped1 >= lowPedIgnore);
        fullPedIdx = max(1, nR-fullPedRows+1):nR;  % last N rows

        rows5={}; vd={}; issueCount=0;

        % ── CHECK 1: L2 upshift ≥ L1 (active pedal rows only) ────────────────
        for g=1:nC
            u1v=double(m1.Z_up(1:nR,g)); u2v=double(m2.Z_up(1:nR,g));
            bad=intersect(find(u2v < u1v+rpmMargin), activeRows);
            avg1=mean(u1v); avg2=mean(u2v);
            if isempty(bad), st='✅ OK'; vStr='None';
            else, st='❌ ISSUE'; issueCount=issueCount+1; vStr=sprintf('%d violation(s)',numel(bad)); end
            rows5(end+1,:)={sprintf('%d→%d Up',g,g+1),'L2 upshift ≥ L1', ...
                num2str(round(avg1)),num2str(round(avg2)),st,vStr}; %#ok<AGROW>
            dRows=buildDetailRows(ped1,u1v,u2v,bad,'L2 below L1');
            vd{end+1}=struct('detailRows',{dRows},'u1',u1v,'u2',u2v,'pedal',ped1,'label', ...
                sprintf('%d→%d Up',g,g+1),'vRows',bad(:)); %#ok<AGROW>
        end

        % ── CHECK 2: L2 downshift ≥ L1 (active pedal rows only) ──────────────
        for g=1:nC
            d1v=double(m1.Z_down(1:nR,g)); d2v=double(m2.Z_down(1:nR,g));
            bad=intersect(find(d2v < d1v+rpmMargin), activeRows);
            avg1=mean(d1v); avg2=mean(d2v);
            if isempty(bad), st='✅ OK'; vStr='None';
            else, st='❌ ISSUE'; issueCount=issueCount+1; vStr=sprintf('%d violation(s)',numel(bad)); end
            rows5(end+1,:)={sprintf('%d→%d Dn',g+1,g),'L2 downshift ≥ L1', ...
                num2str(round(avg1)),num2str(round(avg2)),st,vStr}; %#ok<AGROW>
            dRows=buildDetailRows(ped1,d1v,d2v,bad,'L2 below L1');
            vd{end+1}=struct('detailRows',{dRows},'u1',d1v,'u2',d2v,'pedal',ped1,'label', ...
                sprintf('%d→%d Dn',g+1,g),'vRows',bad(:)); %#ok<AGROW>
        end

        % ── CHECK 3: Hysteresis (Up > Down) — L1 and L2 reported separately ───
        for g=1:nC
            u1v=double(m1.Z_up(1:nR,g)); d1v=double(m1.Z_down(1:nR,g));
            u2v=double(m2.Z_up(1:nR,g)); d2v=double(m2.Z_down(1:nR,g));
            bad1=find(u1v<=d1v); bad2=find(u2v<=d2v);
            % Level 1 hysteresis
            if isempty(bad1), st='✅ OK'; vStr='None';
            else, st='❌ ISSUE'; issueCount=issueCount+1; vStr=sprintf('%d violation(s)',numel(bad1)); end
            rows5(end+1,:)={sprintf('Gear %d L1 Hyst',g),'Hysteresis (Up>Down)','—','—',st,vStr}; %#ok<AGROW>
            dRows=buildDetailRows(ped1,u1v,d1v,bad1,'L1 Up≤Down');
            vd{end+1}=struct('detailRows',{dRows},'u1',u1v,'u2',d1v,'pedal',ped1,'label', ...
                sprintf('Gear %d L1 Hyst',g),'vRows',bad1(:)); %#ok<AGROW>
            % Level 2 hysteresis
            if isempty(bad2), st='✅ OK'; vStr='None';
            else, st='❌ ISSUE'; issueCount=issueCount+1; vStr=sprintf('%d violation(s)',numel(bad2)); end
            rows5(end+1,:)={sprintf('Gear %d L2 Hyst',g),'Hysteresis (Up>Down)','—','—',st,vStr}; %#ok<AGROW>
            dRows=buildDetailRows(ped1,u2v,d2v,bad2,'L2 Up≤Down');
            vd{end+1}=struct('detailRows',{dRows},'u1',u2v,'u2',d2v,'pedal',ped1,'label', ...
                sprintf('Gear %d L2 Hyst',g),'vRows',bad2(:)); %#ok<AGROW>
        end

        % ── CHECK 4: Spread L2 ≥ L1 ──────────────────────────────────────────
        for g=1:nC
            sp1=double(m1.Z_up(1:nR,g))-double(m1.Z_down(1:nR,g));
            sp2=double(m2.Z_up(1:nR,g))-double(m2.Z_down(1:nR,g));
            bad=find(sp2 < sp1*(1-spreadTolPct)); avg1=mean(sp1); avg2=mean(sp2);
            if isempty(bad), st='✅ OK'; vStr='None';
            elseif numel(bad)<=spreadIssueThr, st='⚠ WARN'; issueCount=issueCount+1; vStr=sprintf('%d violation(s)',numel(bad));
            else, st='❌ ISSUE'; issueCount=issueCount+1; vStr=sprintf('%d violation(s)',numel(bad)); end
            rows5(end+1,:)={sprintf('Gear %d',g),'Hyst spread L2≥L1', ...
                num2str(round(avg1)),num2str(round(avg2)),st,vStr}; %#ok<AGROW>
            dRows=buildDetailRows(ped1,sp1,sp2,bad,'L2 spread narrower');
            vd{end+1}=struct('detailRows',{dRows},'u1',sp1,'u2',sp2,'pedal',ped1,'label', ...
                sprintf('Gear %d spread',g),'vRows',bad(:)); %#ok<AGROW>
        end

        % ── CHECK 5: Monotonicity ─────────────────────────────────────────────
        for g=1:nC
            u1v=double(m1.Z_up(1:nR,g)); u2v=double(m2.Z_up(1:nR,g));
            d1v=double(m1.Z_down(1:nR,g)); d2v=double(m2.Z_down(1:nR,g));
            b1=find(diff(u1v)<0)+1; b2=find(diff(u2v)<0)+1;
            b3=find(diff(d1v)<0)+1; b4=find(diff(d2v)<0)+1;
            badUp=union(b1(:),b2(:)); badDn=union(b3(:),b4(:));
            if isempty(badUp), stU='✅ OK'; vStrU='None';
            else, stU='❌ ISSUE'; issueCount=issueCount+1; vStrU=sprintf('%d violation(s)',numel(badUp)); end
            if isempty(badDn), stD='✅ OK'; vStrD='None';
            else, stD='❌ ISSUE'; issueCount=issueCount+1; vStrD=sprintf('%d violation(s)',numel(badDn)); end
            rows5(end+1,:)={sprintf('Gear %d Up mono',g),'L1 & L2 upshift mono','—','—',stU,vStrU}; %#ok<AGROW>
            dRows=buildDetailRows(ped1,u1v,u2v,badUp,'Non-monotonic up');
            vd{end+1}=struct('detailRows',{dRows},'u1',u1v,'u2',u2v,'pedal',ped1,'label', ...
                sprintf('Gear %d Up mono',g),'vRows',badUp(:)); %#ok<AGROW>
            rows5(end+1,:)={sprintf('Gear %d Dn mono',g),'L1 & L2 downshift mono','—','—',stD,vStrD}; %#ok<AGROW>
            dRows=buildDetailRows(ped1,d1v,d2v,badDn,'Non-monotonic dn');
            vd{end+1}=struct('detailRows',{dRows},'u1',d1v,'u2',d2v,'pedal',ped1,'label', ...
                sprintf('Gear %d Dn mono',g),'vRows',badDn(:)); %#ok<AGROW>
        end

        % ── CHECK 6: Full-throttle minimum delta (L2 must be meaningfully higher) ──
        for g=1:nC
            u1v=double(m1.Z_up(1:nR,g)); u2v=double(m2.Z_up(1:nR,g));
            fp=intersect(fullPedIdx,1:nR);
            if isempty(fp), continue; end
            delta=u2v(fp)-u1v(fp);
            bad=fp(delta < minDeltaFP)';
            avgDelta=mean(delta);
            if isempty(bad), st='✅ OK'; vStr=sprintf('Avg delta=+%.0f RPM',avgDelta);
            else, st='❌ ISSUE'; issueCount=issueCount+1; vStr=sprintf('%d row(s) delta<%d RPM',numel(bad),round(minDeltaFP)); end
            rows5(end+1,:)={sprintf('%d→%d Up',g,g+1),'Full-pedal L2 delta', ...
                num2str(round(mean(u1v(fp)))),num2str(round(mean(u2v(fp)))),st,vStr}; %#ok<AGROW>
            dRows=buildDetailRows(ped1,u1v,u2v,bad,sprintf('Delta<%d RPM',round(minDeltaFP)));
            vd{end+1}=struct('detailRows',{dRows},'u1',u1v,'u2',u2v,'pedal',ped1,'label', ...
                sprintf('%d→%d Full-pedal delta',g,g+1),'vRows',bad(:)); %#ok<AGROW>
        end

        % ── CHECK 7: Average delta per gear (aggressiveness summary) ──────────
        for g=1:nC
            u1v=double(m1.Z_up(1:nR,g)); u2v=double(m2.Z_up(1:nR,g));
            d1v=double(m1.Z_down(1:nR,g)); d2v=double(m2.Z_down(1:nR,g));
            ar=activeRows(activeRows<=nR);
            if isempty(ar), continue; end
            avgUpDelta=mean(u2v(ar)-u1v(ar));
            avgDnDelta=mean(d2v(ar)-d1v(ar));
            if avgUpDelta>=0 && avgDnDelta>=0, st='✅ OK';
            elseif avgUpDelta>=0 || avgDnDelta>=0, st='⚠ WARN'; issueCount=issueCount+1;
            else, st='❌ ISSUE'; issueCount=issueCount+1; end
            vStr=sprintf('Up:+%.0f  Dn:+%.0f RPM avg',avgUpDelta,avgDnDelta);
            rows5(end+1,:)={sprintf('Gear %d',g),'Aggressiveness delta', ...
                '—','—',st,vStr}; %#ok<AGROW>
            vd{end+1}=struct('detailRows',{},'u1',u1v,'u2',u2v,'pedal',ped1,'label', ...
                sprintf('Gear %d avg delta',g),'vRows',[]); %#ok<AGROW>
        end

        % ── CHECK 8: Cross-level hysteresis (L2 downshift > L1 upshift) ───────
        for g=1:nC
            u1v=double(m1.Z_up(1:nR,g));
            d2v=double(m2.Z_down(1:nR,g));
            bad=find(d2v <= u1v);
            if isempty(bad), st='✅ OK'; vStr='None';
            elseif numel(bad)<=2, st='⚠ WARN'; issueCount=issueCount+1; vStr=sprintf('%d row(s)',numel(bad));
            else, st='❌ ISSUE'; issueCount=issueCount+1; vStr=sprintf('%d violation(s)',numel(bad)); end
            rows5(end+1,:)={sprintf('Gear %d',g),'Cross-level: L2 Dn > L1 Up', ...
                num2str(round(mean(u1v))),num2str(round(mean(d2v))),st,vStr}; %#ok<AGROW>
            dRows=buildDetailRows(ped1,u1v,d2v,bad,'L2 Dn ≤ L1 Up');
            vd{end+1}=struct('detailRows',{dRows},'u1',u1v,'u2',d2v,'pedal',ped1,'label', ...
                sprintf('Gear %d cross-level',g),'vRows',bad(:)); %#ok<AGROW>
        end

        % ── Store in aFig.UserData — avoids nested scoping issues ─────────────
        try
            ud5=aFig.UserData; if ~isstruct(ud5), ud5=struct(); end
            ud5.levelViolData=vd; aFig.UserData=ud5;
        catch; end

        tbl5.Data=rows5;
        tblDetail.Data={};
        cla(axCmp); title(axCmp,'Click a row in the summary table to plot');

        % Colour summary rows
        try
            removeStyle(tbl5);
            for ri5=1:size(rows5,1)
                if contains(rows5{ri5,5},'ISSUE')
                    addStyle(tbl5,uistyle('BackgroundColor',[1 0.85 0.85]),'row',ri5);
                elseif contains(rows5{ri5,5},'WARN')
                    addStyle(tbl5,uistyle('BackgroundColor',[1 0.97 0.78]),'row',ri5);
                else
                    addStyle(tbl5,uistyle('BackgroundColor',[0.9 1 0.9]),'row',ri5);
                end
            end
        catch; end

        nChecks=size(rows5,1);
        if issueCount==0
            lblSum5.Text=sprintf('✅  No issues — %d checks passed (%s vs %s)',nChecks,char(ddL1.Value),char(ddL2.Value));
            lblSum5.FontColor=[0.1 0.55 0.1];
        else
            lblSum5.Text=sprintf('⚠  %d issue(s) in %d checks (%s vs %s)  |  Click a row to see violations',issueCount,nChecks,char(ddL1.Value),char(ddL2.Value));
            lblSum5.FontColor=[0.75 0.15 0.05];
        end
        drawnow limitrate;
    end

    % ── Table row click → drill down ─────────────────────────────────────────
    function onTableRowSelect(e)
        % e.Selection = [startRow endRow startCol endCol] for SelectionChangedFcn
        try
            if isempty(e.Selection), return; end
            ri = e.Selection(1);
        catch, return; end

        try
            ud5=aFig.UserData;
            if ~isstruct(ud5) || ~isfield(ud5,'levelViolData') || ri>numel(ud5.levelViolData), return; end
            vd5=ud5.levelViolData{ri};
        catch, return; end
        if isempty(vd5), return; end

        % Violation detail table
        try
            tblDetail.Data=vd5.detailRows;
            removeStyle(tblDetail);
            for dr=1:size(vd5.detailRows,1)
                dv=vd5.detailRows{dr,4};
                if isnumeric(dv) && dv<0
                    addStyle(tblDetail,uistyle('BackgroundColor',[1 0.82 0.82],'FontWeight','bold'),'row',dr);
                elseif isnumeric(dv) && dv==0
                    addStyle(tblDetail,uistyle('BackgroundColor',[1 0.95 0.75]),'row',dr);
                end
            end
        catch; end

        % Plot
        try
            cla(axCmp); hold(axCmp,'on'); grid(axCmp,'on');
            u1p=double(vd5.u1(:)); u2p=double(vd5.u2(:)); pedp=double(vd5.pedal(:));
            plot(axCmp,u1p,pedp,'b-o','LineWidth',2,'MarkerSize',5,'DisplayName','L1 (Normal)');
            plot(axCmp,u2p,pedp,'r-s','LineWidth',2,'MarkerSize',5,'DisplayName','L2 (Aggressive)');
            vr=vd5.vRows(:);
            if ~isempty(vr)
                scatter(axCmp,u1p(vr),pedp(vr),100,[0.8 0 0],'filled','DisplayName','Violation L1');
                scatter(axCmp,u2p(vr),pedp(vr),100,[0.5 0 0],'^','filled','DisplayName','Violation L2');
                for vvi=1:numel(vr)
                    plot(axCmp,[u1p(vr(vvi)),u2p(vr(vvi))],[pedp(vr(vvi)),pedp(vr(vvi))], ...
                        'r--','LineWidth',1.5,'HandleVisibility','off');
                end
            end
            legend(axCmp,'show','Location','best','FontSize',8);
            xlabel(axCmp,'Output RPM'); ylabel(axCmp,'Pedal %');
            title(axCmp,vd5.label,'FontSize',9,'Interpreter','none');
            hold(axCmp,'off');
            drawnow limitrate;
        catch ME5
            title(axCmp,sprintf('Plot error: %s',ME5.message),'FontSize',8,'Interpreter','none');
        end
    end

    function exportLevelResults()
        if isempty(tbl5.Data)
            uialert(aFig,'Run ▶ Process first.','Nothing to Export','Icon','warning'); return;
        end
        [f,p]=uiputfile('*.xlsx','Save Level Comparison','LevelComparison.xlsx');
        if isequal(f,0), return; end
        try
            T5=cell2table(tbl5.Data,'VariableNames',{'GearPair','Check','AvgL1','AvgL2','Status','Violations'});
            writetable(T5,fullfile(p,f));
            uialert(aFig,'Exported successfully.','Done','Icon','success');
        catch ME
            uialert(aFig,ME.message,'Export Failed','Icon','error');
        end
    end

    % ── Wire filter dropdown to update L1/L2 dropdowns ───────────────────────
    function updateL1L2Items()
        names=cellstr(mapNames);
        ddL1.Items=names; ddL2.Items=names;
        if numel(names)>=2 && strcmp(ddL1.Value,ddL2.Value)
            ddL2.Value=names{min(2,numel(names))};
        end
    end

    % Wrap the existing onModeChange to also refresh L1/L2 dropdown items
    ddMode.ValueChangedFcn = @(src,~) onModeChangeFull(src.Value);
    function onModeChangeFull(val)
        onModeChange(val);
        updateL1L2Items();
    end

    function onModeChange(val)
        selPos = find(strcmp(allDropItems, val), 1);
        nVis = numel(getVisibleIdx());
        lblCount.Text = sprintf('%d maps shown  |  Selection: %s', nVis, val);
        applyFilter();
    end

    % Initial draw
    refreshPCA();
    refreshAnomaly();
    refreshConsistency();
    drawnow limitrate;
end



function localDrawRanking(order, state, axRank, totalDev, barColours, mapNames, nMaps, ddDev)
    state('curOrder') = order;
    nOrd = length(order);   % may be smaller than nMaps when filter is active
    cla(axRank);
    for bi = 1:nOrd
        mi = order(bi);
        nm = char(mapNames(mi));
        bar(axRank, bi, totalDev(mi), 'FaceColor', barColours(mi,:), 'EdgeColor','none', ...
            'ButtonDownFcn', @(~,~) safeSetDDValue(ddDev, nm));
    end
    lbls = cellstr(mapNames(order));
    set(axRank,'XTick',1:nOrd,'XTickLabel',lbls,'XTickLabelRotation',70,'FontSize',6);
    grid(axRank,'on');
    selNm = ddDev.Value;
    selPos = find(strcmp(lbls, selNm),1);
    ch = get(axRank,'Children');
    bars = ch(strcmp(get(ch,'Type'),'bar'));
    if ~isempty(selPos) && selPos <= numel(bars)
        bars(end-selPos+1).EdgeColor = [0 0 0];
        bars(end-selPos+1).LineWidth = 2;
    end
end

function localRefreshRanking(sortType, state, totalDev, nMaps, doDrawRanking)
    switch sortType
        case 'Most different',  [~,ord] = sort(totalDev,'descend');
        case 'Least different', [~,ord] = sort(totalDev,'ascend');
        otherwise,              ord = (1:nMaps)';
    end
    doDrawRanking(ord);
end

function localUpdateDevPlots(nm, state, axGear, axRank, devMatrix, ...
        totalDev, colLbls3, mapNames, baseMap, baseUp, filtMaps, mainFig, nMaps, barColours, ddDev)
    idx3 = find(strcmp(mapNames, string(nm)),1);
    if isempty(idx3), return; end
    m3   = filtMaps{idx3};   % use filtered map list, not appData.allMaps
    dev3 = devMatrix(idx3,:);

    % NOTE: Map A switch intentionally removed — the analysis window should
    % never change the main GUI map automatically. Only explicit user actions
    % (e.g. clicking a dot in the Clustering tab) should switch maps.

    % ── Gear column deviation bar chart ──────────────────────────────────────
    cla(axGear);
    clrs3 = [linspace(0.2,0.9,14)', linspace(0.8,0.2,14)', 0.2*ones(14,1)];
    bar(axGear, 1:14, dev3,'FaceColor','flat','CData',clrs3,'EdgeColor','none');
    set(axGear,'XTick',1:14,'XTickLabel',colLbls3,'XTickLabelRotation',45,'FontSize',8);
    yline(axGear,  5,'r--','Label','5%');
    yline(axGear, 10,'r-', 'LineWidth',1.5,'Label','10%');
    title(axGear, sprintf('%s  vs  SKL GKF 5  -  avg %.1f%% deviation', nm, totalDev(idx3)));
    grid(axGear,'on');

    % ── Redraw ranking to highlight selection ─────────────────────────────────
    localDrawRanking(state('curOrder'), state, axRank, totalDev, barColours, mapNames, nMaps, ddDev);
end


function s = getYellowStyle()
% Cached yellow highlight style — avoids expensive uistyle() creation on every edit callback.
    persistent s_;
    if isempty(s_), s_ = uistyle('BackgroundColor',[1 1 0],'FontWeight','bold'); end
    s = s_;
end

function s = getSoftYellowStyle()
% Cached soft-yellow style for secondary highlights.
    persistent s_;
    if isempty(s_), s_ = uistyle('BackgroundColor',[1 1 0.8]); end
    s = s_;
end



%% === INCA SYNC ===
function onRefModeToggle(fig, src)
% Reference Mode toggle.
% ON:  Loads chosen vehicle's maps into Map B dropdown (shows [REF] maps only).
%      Map A stays on original maps. dd2 becomes the Ref Map selector.
% OFF: Restores Map B to normal original-map list.
    appData = fig.UserData;
    h       = appData.handles;

    % ── PERFORMANCE: enter bulk mode — suppresses intermediate updatePlot calls ──
    appData.bulkUpdate = true; fig.UserData = appData;
    onCleanup_bulk = onCleanup(@() exitBulkMode(fig));

    % ── OFF ──────────────────────────────────────────────────────────────────
    if ~src.Value
        % Strip [REF] maps from allMaps
        if isfield(appData,'allMaps') && ~isempty(appData.allMaps)
            isRef = cellfun(@(m) isfield(m,'isRef') && m.isRef, appData.allMaps);
            appData.allMaps(isRef) = [];
        end
        appData.allMapNames = string(cellfun(@(m) m.name, appData.allMaps, 'UniformOutput', false))';
        if isfield(appData,'refVehicle'),  appData = rmfield(appData,'refVehicle');  end
        if isfield(appData,'refItemsAll'), appData = rmfield(appData,'refItemsAll'); end
        appData.isRefMode = false;

        % Restore dd2 label and items to original maps
        origN = cellstr(appData.allMapNames);
        if isfield(h,'lblMapB') && isvalid(h.lblMapB)
            h.lblMapB.Text      = 'Map B:';
            h.lblMapB.FontColor = [0 0 0];
        end
        if isfield(h,'refLabel') && isvalid(h.refLabel)
            h.refLabel.Text    = '';
            h.refLabel.Visible = 'off';
        end
        if isfield(h,'cbEdit')   && isvalid(h.cbEdit),   h.cbEdit.Enable   = 'on'; end
        if isfield(h,'cbAllowY') && isvalid(h.cbAllowY), h.cbAllowY.Enable = 'on'; end
        % Reset workingCopy if it was a ref map (from swap)
        if ~isempty(appData.workingCopy) && isfield(appData.workingCopy,'isRef') ...
                && appData.workingCopy.isRef
            appData.workingCopy = []; appData.editIndex = -1; appData.history = {};
        end

        appData.swapping = true; appData.handles = h; fig.UserData = appData;

        % Reset dd1 (Map A) — if it holds a [REF] map (after swap), force back to originals
        if isfield(h,'dd1') && isvalid(h.dd1)
            if isempty(origN)
                % safety: should never happen
            else
                h.dd1.Items = origN;
                if ismember(string(h.dd1.Value), string(origN))
                    % current value is a valid original — keep it
                else
                    h.dd1.Value = origN{1};  % was a [REF] map — reset to first original
                end
                h.dd1.BackgroundColor = [0.95 1 0.95];
            end
        end

        % Reset dd2 (Map B / Ref Map) back to original maps
        if isfield(h,'dd2') && isvalid(h.dd2)
            h.dd2.Items           = origN;
            h.dd2.Value           = origN{1};
            h.dd2.BackgroundColor = [1 0.95 0.95];
            h.dd2.Tooltip         = '';
        end

        appData.swapping = false;
        % Restore fileLabel to working file name (may have shown ref name after swap)
        if isfield(h,'fileLabel') && isvalid(h.fileLabel)
            if isfield(appData,'sourceFilename') && ~isempty(appData.sourceFilename)
                h.fileLabel.Text = ['A: ' char(appData.sourceFilename)];
            end
            h.fileLabel.FontColor = [0.15 0.5 0.15];
        end
        appData.handles = h; fig.UserData = appData;
        updatePlot(fig); refreshAllUKTabsIfOpen(fig);
        try, updateMapSourceLabels(fig); catch; end
        try, refreshStatusBar(fig); catch; end
        return;
    end

    % ── ON ───────────────────────────────────────────────────────────────────
    % Load database
    dbPath = findRefDB();
    if isempty(dbPath)
        src.Value = false;
        uialert(fig, sprintf(['PatternPlotter_RefDB.mat not found.\n\n' ...
            'Place the database file next to the .exe or in the working directory.\n' ...
            'Build it using RefDB_Builder.']), 'Database Not Found', 'Icon','error');
        return;
    end
    try, s = load(dbPath); db = s.db; catch ME
        src.Value = false;
        uialert(fig, sprintf('Failed to load database:\n%s', ME.message), 'Error', 'Icon','error');
        return;
    end
    if isempty(db)
        src.Value = false;
        uialert(fig, 'Database is empty. Add vehicles using RefDB_Builder.', 'Empty', 'Icon','warning');
        return;
    end

    chosen = selectRefVehicle(fig, db);
    if isempty(chosen), src.Value = false; return; end

    % ── Re-read appData AFTER selectRefVehicle — dialog may have processed events ──
    appData = fig.UserData;
    h       = appData.handles;

    % Strip any existing [REF] maps
    if ~isempty(appData.allMaps)
        wasRef = cellfun(@(m) isfield(m,'isRef') && m.isRef, appData.allMaps);
        appData.allMaps(wasRef) = [];
    end

    % Tag and append reference maps
    refMaps = chosen.allMaps;
    for k = 1:numel(refMaps)
        refMaps{k}.name     = string(['[REF] ' char(refMaps{k}.name)]);
        refMaps{k}.modified = false;
        refMaps{k}.isRef    = true;
    end
    if isempty(refMaps)
        src.Value = false;
        uialert(fig, 'Selected vehicle has no shift maps.', 'No Maps', 'Icon','warning');
        return;
    end
    appData.allMaps     = [appData.allMaps, refMaps];
    appData.allMapNames = string(cellfun(@(m) m.name, appData.allMaps, 'UniformOutput', false))';
    appData.refVehicle  = chosen;
    appData.isRefMode   = true;

    % Build ref-map name list for dd2
    refN = string(cellfun(@(m) m.name, refMaps, 'UniformOutput', false))';
    refNcell = cellstr(refN);

    % Auto-match ref map to current Map A number
    curA       = string(h.dd1.Value);
    matchedRef = refNcell{1};   % default: first ref map
    tok = regexp(curA,'SKL_GKF_(\d+)','tokens');
    if ~isempty(tok)
        mn = tok{1}{1};
        ri = find(contains(refN,['SKL_GKF_' mn]),1);
        if ~isempty(ri), matchedRef = refNcell{ri}; end
    end

    % Store for self-healing
    appData.refItemsAll = refN;

    % Write state to fig FIRST with swapping=true, then update UI
    appData.swapping = true;
    appData.handles  = h;
    fig.UserData     = appData;
    drawnow limitrate;

    % Rename Map B label → "Ref Map:" to make purpose clear
    if isfield(h,'lblMapB') && isvalid(h.lblMapB)
        h.lblMapB.Text      = 'Ref Map:';
        h.lblMapB.FontColor = [0.0 0.35 0.65];
    end

    % dd2 now shows ONLY [REF] maps (no originals mixed in)
    h.dd2.Items           = refNcell;
    h.dd2.Value           = matchedRef;
    h.dd2.BackgroundColor = [0.88 0.95 1.0];   % light blue = ref mode
    h.dd2.Tooltip         = 'Reference maps — select to compare against Map A';
    h.cb2.Value           = true;

    % dd1 stays on originals (dd1.Items unchanged)
    % dd3 unchanged

    % Update refLbl
    if isfield(h,'refLabel') && isvalid(h.refLabel)
        h.refLabel.Text = sprintf('📘 %s  |  %s  |  %s  |  Axle: %.3f  |  Tire: %.0f mm', ...
            chosen.meta.description, num2str(chosen.meta.MY), chosen.meta.transGen, ...
            chosen.vehicle.AxleRatio, chosen.vehicle.TireCircumference);
        h.refLabel.Visible = 'on';
    end

    % Commit and render
    appData.swapping = false;
    appData.handles  = h;
    fig.UserData     = appData;
    drawnow limitrate;
    updatePlot(fig);
    refreshUKStatIfOpen(fig);
    try, refreshStatusBar(fig); catch; end
    try, updateMapSourceLabels(fig); catch; end
end


function dbPath = findRefDB()
    dbPath = '';
    candidates = {};
    try; candidates{end+1} = fullfile(fileparts(which(mfilename)), 'PatternPlotter_RefDB.mat'); catch; end
    candidates{end+1} = fullfile(pwd, 'PatternPlotter_RefDB.mat');
    candidates{end+1} = fullfile(prefdir, 'PatternPlotter_RefDB.mat');
    if isdeployed
        try
            [exeDir,~,~] = fileparts(which(mfilename('fullpath')));
            candidates{end+1} = fullfile(exeDir,'PatternPlotter_RefDB.mat');
        catch; end
    end
    for k = 1:numel(candidates)
        if exist(candidates{k},'file'), dbPath = candidates{k}; return; end
    end
    [f,p] = uigetfile('*.mat','Locate PatternPlotter_RefDB.mat');
    if ~isequal(f,0), dbPath = fullfile(p,f); end
end

function chosen = selectRefVehicle(fig, db)
% Modal vehicle selector with MY / Trans Gen / Variant filters.
    chosen = [];
    dlg = uifigure('Name','Select Reference Vehicle',...
        'Position',[200 200 740 440],'WindowStyle','modal','Resize','on',...
        'Color',[0.94 0.94 0.94]);
    movegui(dlg,'center');
    gl = uigridlayout(dlg,[3,1],'RowHeight',{44,'1x',44},...
        'Padding',[12 10 12 10],'RowSpacing',8,'BackgroundColor',[0.94 0.94 0.94]);

    fGL = uigridlayout(gl,[1,8],...
        'ColumnWidth',{38,'fit',80,'fit',110,'fit',100,'1x'},...
        'Padding',[0 0 0 0],'ColumnSpacing',6,'BackgroundColor',[0.94 0.94 0.94]);
    uilabel(fGL,'Text','Filter:','FontWeight','bold','BackgroundColor',[0.94 0.94 0.94]);
    allMYs  = unique(arrayfun(@(d) num2str(d.meta.MY),      db, 'UniformOutput', false));
    allGens = unique(arrayfun(@(d) d.meta.transGen,          db, 'UniformOutput', false));
    allVars = unique(arrayfun(@(d) d.meta.variant,           db, 'UniformOutput', false));
    uilabel(fGL,'Text','MY:','BackgroundColor',[0.94 0.94 0.94]);
    ddMY  = uidropdown(fGL,'Items',['All',allMYs],'Value','All');
    uilabel(fGL,'Text','Trans Gen:','BackgroundColor',[0.94 0.94 0.94]);
    ddGen = uidropdown(fGL,'Items',['All',allGens],'Value','All');
    uilabel(fGL,'Text','Variant:','BackgroundColor',[0.94 0.94 0.94]);
    ddVar = uidropdown(fGL,'Items',['All',allVars],'Value','All');
    uilabel(fGL,'Text','','BackgroundColor',[0.94 0.94 0.94]);

    tbl = uitable(gl,...
        'ColumnName',{'MY','Vehicle Line','Trans Gen','Variant','Description','Maps','Source File'},...
        'ColumnWidth',{45,110,90,70,185,40,130},...
        'RowName',{},'ColumnEditable',false);

    bGL = uigridlayout(gl,[1,3],'ColumnWidth',{'1x',170,100},...
        'Padding',[0 0 0 0],'ColumnSpacing',8,'BackgroundColor',[0.94 0.94 0.94]);
    uilabel(bGL,'Text','','BackgroundColor',[0.94 0.94 0.94]);
    uibutton(bGL,'Text','Load as Reference','FontWeight','bold',...
        'BackgroundColor',[0.13 0.54 0.13],'FontColor',[1 1 1],...
        'ButtonPushedFcn',@(~,~) doSelect());
    uibutton(bGL,'Text','Cancel','FontWeight','bold',...
        'BackgroundColor',[0.9 0.9 0.9],'ButtonPushedFcn',@(~,~) delete(dlg));

    filteredIdx = 1:numel(db);
    populateTable(filteredIdx);
    ddMY.ValueChangedFcn  = @(~,~) applyFilter();
    ddGen.ValueChangedFcn = @(~,~) applyFilter();
    ddVar.ValueChangedFcn = @(~,~) applyFilter();
    uiwait(dlg);

    function populateTable(idx)
        filteredIdx = idx;
        rows = cell(numel(idx),7);
        for i=1:numel(idx)
            k=idx(i);
            rows{i,1}=db(k).meta.MY; rows{i,2}=db(k).meta.vehicleLine;
            rows{i,3}=db(k).meta.transGen; rows{i,4}=db(k).meta.variant;
            rows{i,5}=db(k).meta.description; rows{i,6}=numel(db(k).allMaps);
            rows{i,7}=db(k).sourceFile;
        end
        tbl.Data = rows;
    end
    function applyFilter()
        myF=ddMY.Value; genF=ddGen.Value; varF=ddVar.Value; idx=[];
        for k=1:numel(db)
            if ~strcmp(myF,'All')  && ~strcmp(num2str(db(k).meta.MY),myF),    continue; end
            if ~strcmp(genF,'All') && ~strcmp(db(k).meta.transGen,genF),       continue; end
            if ~strcmp(varF,'All') && ~strcmp(db(k).meta.variant,varF),        continue; end
            idx(end+1)=k; %#ok<AGROW>
        end
        populateTable(idx);
    end
    function doSelect()
        sel=tbl.Selection;
        if isempty(sel), uialert(dlg,'Select a vehicle first.','Nothing Selected','Icon','warning'); return; end
        row=sel(1,1);
        if row<1||row>numel(filteredIdx), return; end
        chosen=db(filteredIdx(row));
        if isvalid(dlg), delete(dlg); end
    end
end


function launchRefDBBuilder()
% Launch RefDB_Builder as a standalone tool.
% Works both in MATLAB and compiled .exe (searches for RefDB_Builder.m or .exe).
    try
        % In MATLAB — run directly
        if ~isdeployed
            if exist('RefDB_Builder','file')
                RefDB_Builder();
            else
                uialert([], ['RefDB_Builder.m not found in the MATLAB path.' newline ...
                    'Place RefDB_Builder.m in the same folder as Pattern_plotter.m'], ...
                    'Not Found', 'Icon', 'error');
            end
        else
            % In compiled .exe — try launching the companion exe
            [exeDir,~,~] = fileparts(which(mfilename('fullpath')));
            builderExe = fullfile(exeDir, 'RefDB_Builder.exe');
            if exist(builderExe,'file')
                system(['"' builderExe '" &']);
            else
                uialert([], ['RefDB_Builder.exe not found next to Pattern_plotter.exe.' newline ...
                    'Compile RefDB_Builder.m separately and place it in the same folder.'], ...
                    'Not Found', 'Icon', 'warning');
            end
        end
    catch ME
        uialert([], sprintf('Could not launch RefDB_Builder:%s%s', newline, ME.message), ...
            'Error', 'Icon', 'error');
    end
end

function onSyncINCAToggle(fig, src)
% Called when user clicks "Sync to INCA" checkbox.
%
% Compatible with BOTH INCA 7.4.x (raw COM only — no MIP) and INCA 7.5.5 (MIP + COM).
%
% Flow:
%   1. Try to resolve MIP path (only relevant for INCA 7.5.5+)
%   2. Connect to INCA via COM regardless of MIP availability
%   3. If COM works → enabled (pushMapToINCA will use MIP if available, else raw COM)
%   4. If COM fails → uncheck and show diagnostic
    if ~src.Value
        incaCOMCache([]);
        try, refreshStatusBar(fig); catch; end
        return;
    end

    % ── Step 1: try to resolve MIP path silently (used by INCA 7.5.5 only) ──
    mipAvailable = false;
    try
        mipAvailable = ensureMIPOnPath();   % returns true if MIP found and on path
    catch
        mipAvailable = false;
    end

    % ── Step 2: connect to INCA COM (works on both 7.4.x and 7.5.5) ─────────
    incaCOMCache([]);
    regProgIDs = scanRegistryForINCA();
    [inca, foundID] = connectToINCA(regProgIDs);

    if ~isempty(inca)
        incaCOMCache(inca);
        mode = detectINCAMode(inca);
        if mipAvailable
            iconText = 'INCA-MIP ready'; pathLine = sprintf('MIP path: %s', mipPathCache());
        else
            iconText = 'INCA COM ready (no MIP)';
            pathLine = 'MIP not detected — using raw COM API (compatible with INCA 7.4.x)';
        end
        uialert(fig, sprintf(['%s  —  ProgID: %s\nMode: %s\n\n' ...
            'Edits will sync to the open INCA dataset.\n%s'], ...
            iconText, foundID, mode, pathLine), ...
            'INCA Sync Active', 'Icon', 'success');
        try, refreshStatusBar(fig); catch; end
        return;
    end

    % ── Step 3: INCA COM failed — offer to set MIP path manually ────────────
    src.Value = false;
    sel = uiconfirm(fig, ['Could not connect to INCA via COM.' newline newline ...
        'Possible causes:' newline ...
        '  • INCA is not running (open INCA and try again)' newline ...
        '  • INCA COM/automation server is not registered' newline ...
        '  • For INCA 7.5.5 only: MIP path may need to be set manually' newline newline ...
        'Would you like to browse for the INCA-MIP folder (7.5.5 only)?'], ...
        'INCA Connection Failed', ...
        'Options', {'Browse for MIP...', 'Cancel'}, ...
        'DefaultOption', 'Cancel', 'CancelOption', 'Cancel', 'Icon', 'error');
    if strcmp(sel, 'Browse for MIP...')
        try, promptForMIPPath(fig); catch; end
    end
    try, refreshStatusBar(fig); catch; end
end

function ok = promptForMIPPath(fig)
% MIP path dialog — styled to match Pattern Plotter UI conventions.
% Shows saved path pre-filled; allows Browse, Auto-detect, or Cancel.
    ok = false;

    savedPath = mipPathCache();
    autoPath  = '';
    if isempty(savedPath)
        autoPath = autoDetectMIPPath();
    end

    if ~isempty(savedPath)
        currentPath = savedPath;
        headerText  = 'INCA-MIP path from previous session:';
    elseif ~isempty(autoPath)
        currentPath = autoPath;
        headerText  = 'INCA-MIP path auto-detected:';
    else
        currentPath = '';
        headerText  = 'No INCA-MIP path saved. Browse to the MIP MATLAB folder.';
    end

    % ── Dialog figure ─────────────────────────────────────────────────────────
    dlgFig = uifigure('Name', 'INCA-MIP Setup', ...
        'Position', [400 340 480 210], ...
        'WindowStyle', 'modal', 'Resize', 'off', ...
        'Color', [0.94 0.94 0.94]);

    gl = uigridlayout(dlgFig, [4 1], ...
        'RowHeight', {26, 28, 36, 36}, ...
        'Padding',   [14 12 14 12], ...
        'RowSpacing', 6, ...
        'BackgroundColor', [0.94 0.94 0.94]);

    % Row 1 — header label
    uilabel(gl, 'Text', headerText, ...
        'FontWeight', 'bold', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', [0.94 0.94 0.94]);

    % Row 2 — path display box
    pathLabel = uilabel(gl, 'Text', currentPath, ...
        'HorizontalAlignment', 'left', ...
        'FontWeight', 'normal', ...
        'BackgroundColor', [1 1 1], ...
        'FontColor', [0.15 0.15 0.55], ...
        'WordWrap', 'on');

    % Row 3 — Browse / Auto-detect
    row3 = uigridlayout(gl, [1 3], ...
        'ColumnWidth', {'1x', 130, 120}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 8, ...
        'BackgroundColor', [0.94 0.94 0.94]);
    uilabel(row3, 'Text', 'Folder must contain  INCA_SetValue.m / .p / .mexw64', ...
        'FontColor', [0.35 0.35 0.35], ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', [0.94 0.94 0.94]);
    uibutton(row3, 'Text', 'Browse...', ...
        'BackgroundColor', [0.9 0.9 0.9], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) doBrowse());
    uibutton(row3, 'Text', 'Auto-detect', ...
        'BackgroundColor', [0.9 0.9 0.9], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) doAutoDetect());

    % Row 4 — Confirm / Cancel
    row4 = uigridlayout(gl, [1 3], ...
        'ColumnWidth', {'1x', 130, 100}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 8, ...
        'BackgroundColor', [0.94 0.94 0.94]);
    uilabel(row4, 'Text', '', 'BackgroundColor', [0.94 0.94 0.94]);
    uibutton(row4, 'Text', 'Confirm Path', ...
        'BackgroundColor', [0.13 0.54 0.13], ...
        'FontColor', [1 1 1], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) doConfirm());
    uibutton(row4, 'Text', 'Cancel', ...
        'BackgroundColor', [0.9 0.9 0.9], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) doCancel());

    % Shared state
    chosenPath = currentPath;
    confirmed  = false;

    uiwait(dlgFig);
    ok = confirmed;

    % ── Callbacks ─────────────────────────────────────────────────────────────
    function doBrowse()
        startDir = chosenPath;
        if isempty(startDir), startDir = 'C:\ETAS'; end
        p = uigetdir(startDir, 'Select INCA-MIP folder (contains INCA_SetValue.m / .p / .mexw64)');
        if isequal(p, 0), return; end
        if ~hasMIPEntryPoint(p)
            uialert(dlgFig, ...
                sprintf('INCA_SetValue.m / .p / .mexw64 not found in:\n%s\n\nPlease select the correct folder.', p), ...
                'Wrong Folder', 'Icon', 'warning');
            return;
        end
        chosenPath = p;
        pathLabel.Text = p;
    end

    function doAutoDetect()
        p = autoDetectMIPPath();
        if isempty(p)
            uialert(dlgFig, ...
                sprintf('Could not auto-detect INCA-MIP folder in C:\\ETAS\\...\n\nUse Browse to locate it manually.'), ...
                'Not Found', 'Icon', 'warning');
        else
            chosenPath = p;
            pathLabel.Text = p;
        end
    end

    function doConfirm()
        if isempty(strtrim(chosenPath))
            uialert(dlgFig, 'No path selected. Use Browse to locate the MIP folder.', ...
                'No Path', 'Icon', 'warning');
            return;
        end
        if ~hasMIPEntryPoint(chosenPath)
            choice = uiconfirm(dlgFig, ...
                sprintf(['INCA_SetValue.m / .p / .mexw64 not found in:\n%s\n\n' ...
                    'If you do not have INCA-MIP, please contact tool support.\n\n' ...
                    'Proceed anyway or browse to a different folder?'], chosenPath), ...
                'MIP Not Confirmed', ...
                'Options',   {'Proceed Anyway', 'Browse Again', 'Cancel'}, ...
                'DefaultOption', 2, 'CancelOption', 3, 'Icon', 'warning');
            if strcmp(choice, 'Browse Again'), doBrowse(); return; end
            if strcmp(choice, 'Cancel')
                if isvalid(dlgFig), delete(dlgFig); end
                uialert(fig, ...
                    sprintf('INCA-MIP is required for INCA Sync.\n\nPlease contact tool support to obtain INCA-MIP for INCA 7.5.5.'), ...
                    'INCA-MIP Required', 'Icon', 'error');
                return;
            end
        end
        mipPathCache(chosenPath);
        if ~isdeployed, addpath(chosenPath); end   % MCR: path not needed — functions compiled in
        confirmed = true;
        if isvalid(dlgFig), delete(dlgFig); end
    end

    function doCancel()
        if isvalid(dlgFig), delete(dlgFig); end
        uialert(fig, ...
            sprintf('INCA Sync requires INCA-MIP (MATLAB Integration Package).\n\nPlease contact tool support to obtain INCA-MIP for INCA 7.5.5.'), ...
            'INCA-MIP Required', 'Icon', 'error');
    end
end

function saved = mipPathCache(newPath)
% Persistent store for the user-chosen MIP path.
% Persists across sessions via a small preferences file in the app data folder.
    persistent path_;
    prefFile = fullfile(prefdir, 'PP_MIP_path.txt');

    if nargin == 1
        % Write new path
        path_ = newPath;
        try
            fid = fopen(prefFile,'w');
            if fid ~= -1
                fprintf(fid,'%s', newPath);
                fclose(fid);
            end
        catch; end
    end

    if isempty(path_)
        % Try to load from file
        try
            if exist(prefFile,'file')
                fid = fopen(prefFile,'r');
                if fid ~= -1
                    path_ = strtrim(fgetl(fid));
                    fclose(fid);
                end
            end
        catch; end
    end

    saved = '';
    if ~isempty(path_) && ischar(path_)
        saved = path_;
    end
end

function p = autoDetectMIPPath()
% Silently search common ETAS installation locations for INCA_SetValue.m.
% Covers standard ETAS install paths AND known enterprise/custom paths
% (e.g. Stellantis machines install MIP under C:\Apps\ETASData\...).
    p = '';
    candidates = {
        % --- Stellantis / enterprise custom paths ---
        'C:\Apps\ETASData\INCA7.5\INCA-MIPx64',
        'C:\Apps\ETASData\INCA7.4\INCA-MIPx64',
        'C:\Apps\ETASData\INCA7.5\MATLAB',
        'C:\Apps\ETASData\INCA7.4\MATLAB',
        % --- Standard ETAS install paths ---
        'C:\ETAS\INCA7.5\INCA-MIPx64',
        'C:\ETAS\INCA7.4\INCA-MIPx64',
        'C:\ETAS\INCA7.5\MATLAB',
        'C:\ETAS\INCA7.4\MATLAB',
        'C:\Program Files\ETAS\INCA7.5\INCA-MIPx64',
        'C:\Program Files\ETAS\INCA7.4\INCA-MIPx64',
        'C:\Program Files\ETAS\INCA7.5\MATLAB',
        'C:\Program Files\ETAS\INCA7.4\MATLAB',
        'C:\Program Files (x86)\ETAS\INCA7.5\MATLAB',
        'C:\Program Files (x86)\ETAS\INCA7.4\MATLAB',
    };
    for k = 1:numel(candidates)
        if exist(candidates{k},'dir') && hasMIPEntryPoint(candidates{k})
            p = candidates{k}; return;
        end
    end
    % Deep search across multiple drives and base folders. Looks for ANY of
    % INCA_SetValue.m / .p / .mexw64 (INCA 7.4 ships pre-compiled .p files).
    drives = {'C:','D:','E:'};
    relativeBases = {
        '\Apps\ETASData',
        '\ETAS',
        '\Program Files\ETAS',
        '\Program Files (x86)\ETAS',
    };
    for di = 1:numel(drives)
        for bi = 1:numel(relativeBases)
            base = [drives{di} relativeBases{bi}];
            if ~exist(base,'dir'), continue; end
            for ext = {'.m','.p','.mexw64'}
                try
                    hits = dir(fullfile(base,'**',['INCA_SetValue' ext{1}]));
                    if ~isempty(hits), p = hits(1).folder; return; end
                catch; end
            end
        end
    end
end

function tf = hasMIPEntryPoint(folder)
% Return true if `folder` contains the INCA_SetValue function in any form
% (.m source, .p pcode, or .mexw64 MEX) — INCA 7.4 typically ships .p only.
    tf = exist(fullfile(folder,'INCA_SetValue.m'),'file') == 2 ...
      || exist(fullfile(folder,'INCA_SetValue.p'),'file') == 6 ...
      || exist(fullfile(folder,'INCA_SetValue.mexw64'),'file') == 3;
end

function ids = scanRegistryForINCA()
% Scan HKCR and HKCU\SOFTWARE\Classes for INCA COM ProgID registrations.
% Returns a cell array of ProgID strings that have a CLSID subkey (valid COM objects).
    ids = {};
    if ~ispc, return; end
    % Query both system-wide and per-user class registrations
    queries = {
        'reg query "HKCR" /f "INCA" /k 2>nul', ...
        'reg query "HKCU\SOFTWARE\Classes" /f "INCA" /k 2>nul', ...
    };
    for q = 1:numel(queries)
        try
            [~, out] = system(queries{q});
            lines = strsplit(strtrim(out), newline);
            for k = 1:numel(lines)
                ln = strtrim(lines{k});
                if isempty(ln), continue; end
                % Extract the part after the last backslash
                parts  = strsplit(ln, '\');
                key    = strtrim(parts{end});
                % Only keep ProgID-style entries (contain 'Application' OR match Inca.Inca pattern)
                if ~contains(key, 'Application', 'IgnoreCase', true) && ...
                   isempty(regexpi(key, '^Inca\.Inca', 'once'))
                    continue;
                end
                % Verify it has a CLSID subkey (confirms it's a real COM server)
                [st, ~] = system(sprintf('reg query "%s\\%s\\CLSID" 2>nul', ...
                    regexprep(ln, '\\[^\\]+$',''), key));
                if st ~= 0
                    % Try without CLSID verification — still add it
                end
                if ~any(strcmp(ids, key))
                    ids{end+1} = key; %#ok<AGROW>
                end
            end
        catch; end
    end
end

function [inca, foundID] = tryProgID(progID)
% Try actxGetRunningServer then actxserver for a single ProgID.
    inca = []; foundID = '';
    try
        inca = actxGetRunningServer(progID);
        foundID = progID; return;
    catch; end
    try
        inca = actxserver(progID);
        foundID = progID;
    catch; end
end

function savedID = incaProgIDCache(newID)
% Persistent cache for a manually confirmed working ProgID.
    persistent pid_;
    if nargin == 1, pid_ = newID; end
    savedID = pid_;
end

function [inca, foundID] = connectToINCA(extraIDs)
% Connect to INCA. Tries saved manual ProgID first, then registry discoveries,
% then hardcoded list. Uses actxGetRunningServer (existing instance) before actxserver.
    if nargin < 1, extraIDs = {}; end
    inca = []; foundID = '';

    % Try the saved manual ProgID first (from a previous successful manual connect)
    savedID = incaProgIDCache();
    if ~isempty(savedID)
        [inca, foundID] = tryProgID(savedID);
        if ~isempty(inca), return; end
    end

    % Try registry-discovered IDs next
    for k = 1:numel(extraIDs)
        [inca, foundID] = tryProgID(extraIDs{k});
        if ~isempty(inca), return; end
    end

    % Hardcoded list — correct ETAS INCA ProgIDs first (confirmed from registry)
    candidates = {
        'Inca.Inca.7.4',          ...  % INCA 7.4.x — confirmed
        'Inca.Inca.7',            ...  % INCA 7.x
        'Inca.Inca',              ...  % generic — works across all versions
        'INCA74.Application',     ...  % alternate naming (some installs)
        'INCA74.Application.1',   ...
        'INCA73.Application',     ...
        'INCA72.Application',     ...
        'INCA71.Application',     ...
        'INCA7.Application',      ...
        'INCA7.Application.1',    ...
        'INCA6.Application',      ...
        'INCA6.Application.1',    ...
        'INCA5.Application',      ...
        'ETASInca.Application',   ...
        'INCA.Application',       ...
        'INCA.Application.1',     ...
    };
    for k = 1:numel(candidates)
        [inca, foundID] = tryProgID(candidates{k});
        if ~isempty(inca), return; end
    end
end

function mode = detectINCAMode(inca)
% Returns 'Online (ECU connected)' or 'Offline (dataset only)'.
    mode = 'Offline (dataset only)';
    try
        m = inca.ActiveDataset.Measurement; %#ok<NASGU>
        mode = 'Online (ECU connected)';
    catch; end
end

function inca = incaCOMCache(newVal)
% Persistent cache for the INCA COM handle.
% incaCOMCache([]) = clear/release   incaCOMCache(obj) = set   incaCOMCache() = get+validate
    persistent cached_;
    if nargin == 1
        if isempty(newVal)
            try; if ~isempty(cached_), cached_.release; end; catch; end
            cached_ = [];
        else
            cached_ = newVal;
        end
        inca = [];
    else
        if isempty(cached_)
            [cached_, ~] = connectToINCA();
        else
            try, cached_.Name; catch   % probe — stale: rediscover
                [cached_, ~] = connectToINCA();
            end
        end
        inca = cached_;
    end
end

function exp = getINCAExperiment(inca)
% Get opened experiment (raw COM fallback only — MIP path preferred).
    exp = [];
    try
        exp = inca.GetOpenedExperiment();
        try; exp.SwitchCalibrationAccessOn(); catch; end
    catch; end
end

function mipPath = findMIPPath()
% Returns the confirmed MIP path from cache, or auto-detects as fallback.
    mipPath = mipPathCache();
    if isempty(mipPath)
        mipPath = autoDetectMIPPath();
    end
end

function ok = ensureMIPOnPath()
% Add MIP folder to MATLAB path using saved/detected path.
% Returns true if INCA_SetValue is callable in any form (.m/.p/.mexw64).
%   exist() return values:  2 = .m file   3 = MEX file   6 = P-code file
    ok = ismember(exist('INCA_SetValue'), [2 3 6]);
    if ok, return; end
    p = findMIPPath();
    if ~isempty(p)
        if ~isdeployed, addpath(p); end   % MCR: compiled exe has MIP on path already
        ok = ismember(exist('INCA_SetValue'), [2 3 6]);
    end
end

function ok = writeMIPMap(paramName, fullMatrix)
% Write calibration map via INCA-MIP toolbox (INCA_SetValue).
% This is the correct, type-safe path — MIP handles all COM marshaling.
%
% INCA_SetValue(label, value) writes the value to the working page.
% The matrix must match the map dimensions (INCA figures out orientation).
    ok = false;
    if ~ensureMIPOnPath()
        return;
    end
    try
        INCA_SetValue(paramName, fullMatrix);
        ok = true; return;
    catch; end
    % Try transposed (MIP may expect [nX x nY] instead of [nY x nX])
    try
        INCA_SetValue(paramName, fullMatrix');
        ok = true; return;
    catch; end
end

function pushCellToINCA(fig, wc, rowIdx, colIdx, rpmVal)
% Push one edited cell to INCA.
% Primary path: INCA-MIP INCA_SetValue (writes full map, correctly typed).
% Fallback: raw COM via writeFullMatrix.
    try
        if isempty(wc) || ~ispc, return; end
        if isempty(incaCOMCache()), return; end
        if colIdx <= 1, return; end

        paramName = char(wc.name);
        incaRow0  = rowIdx - 2;
        nDataRows = size(wc.Z_up,1) - 2;
        if incaRow0 < 0 || incaRow0 >= nDataRows, return; end

        nRows  = nDataRows;
        nGears = size(wc.Z_up,2);
        fullMatrix = zeros(nRows, nGears*2);
        for r = 1:nRows
            fullMatrix(r, 1:nGears)          = wc.Z_up(r+1,:);
            fullMatrix(r, nGears+1:nGears*2) = wc.Z_down(r+1,:);
        end

        try
            % Primary: INCA-MIP
            if writeMIPMap(paramName, fullMatrix)
                return;
            end
            % Fallback: raw COM
            inca = incaCOMCache();
            if isempty(inca), error('INCA not connected.'); end
            exp    = getINCAExperiment(inca);
            elem   = exp.GetCalibrationElement(paramName);
            valObj = elem.GetValue();
            ok = writeFullMatrix(exp, elem, valObj, fullMatrix);
            if ~ok
                error('All write paths failed for %s.', paramName);
            end
        catch ME2
            disableSyncWithError(fig, paramName, incaRow0, colIdx-2, ME2.message);
        end
    catch; end
end

function pushMapToINCA(fig, wc)
% Push full map to INCA. Primary: MIP. Fallback: raw COM.
%
% IMPORTANT — boundary rows are stripped:
%   wc.Z_up / wc.Z_down include 2 EXTRA rows that exist only for the editor's
%   own interpolation visualisation (the gray boundary rows at top and bottom
%   of the Edit Map A table). INCA's actual SKL_GKF map does NOT have these
%   rows — they're tool-side reference only.
%
%   So we slice rows 2..end-1 before sending: nRows = size - 2, indexed via
%   r+1 below. This produces the matrix that exactly matches INCA's structure
%   (e.g. 11 rows × 14 cols for the SKL_GKF_5 map).
    try
        if isempty(wc) || ~ispc, return; end
        if isempty(incaCOMCache()), return; end

        paramName = char(wc.name);
        nRows  = size(wc.Z_up,1) - 2;     % strip first + last (boundary rows)
        nGears = size(wc.Z_up,2);
        fullMatrix = zeros(nRows, nGears*2);
        for r = 1:nRows
            fullMatrix(r, 1:nGears)          = wc.Z_up(r+1,:);     % skip row 1
            fullMatrix(r, nGears+1:nGears*2) = wc.Z_down(r+1,:);   % skip last row
        end

        try
            if writeMIPMap(paramName, fullMatrix)
                return;
            end
            inca = incaCOMCache();
            if isempty(inca), error('INCA not connected.'); end
            exp    = getINCAExperiment(inca);
            elem   = exp.GetCalibrationElement(paramName);
            valObj = elem.GetValue();
            ok = writeFullMatrix(exp, elem, valObj, fullMatrix);
            if ~ok, error('All write paths failed for %s.', paramName); end
        catch ME2
            disableSyncWithError(fig, paramName, 0, 0, ME2.message);
        end
    catch; end
end

function ok = writeFullMatrix(exp, elem, valObj, fullMatrix)
% Raw COM fallback when MIP is not available.
% INCA 7.4 SetValue requires a 2D CELL ARRAY of strings (verified by user diagnostic
% showing only ResetValueToRP / SetValue / SetWeakBound* / SetX/YDistribution exist;
% no SetValueAt, no SetMatrixValue, no PutMatrix). INCA 7.5 also accepts cell arrays.
    ok = false;
    if isempty(valObj) || isempty(exp) || isempty(elem), return; end
    m  = double(fullMatrix);
    mt = m';

    % ── PRIMARY: cell array of strings (INCA 7.4 + 7.5 native format) ────────
    cellM  = arrayfun(@num2str, m,  'UniformOutput', false);
    cellMt = arrayfun(@num2str, mt, 'UniformOutput', false);
    try; valObj.SetValue(cellM);  ok=true; return; catch; end
    try; valObj.SetValue(cellMt); ok=true; return; catch; end
    try; invoke(valObj,'SetValue',cellM);  ok=true; return; catch; end
    try; invoke(valObj,'SetValue',cellMt); ok=true; return; catch; end

    % ── SECONDARY: 2D cell array of doubles (some INCA builds accept this) ──
    cellMd  = num2cell(m);
    cellMtd = num2cell(mt);
    try; valObj.SetValue(cellMd);  ok=true; return; catch; end
    try; valObj.SetValue(cellMtd); ok=true; return; catch; end

    % ── TERTIARY: raw double matrix (INCA 7.5 vectorised path) ──────────────
    try; valObj.SetValue(m);  ok=true; return; catch; end
    try; valObj.SetValue(mt); ok=true; return; catch; end

    % ── FALLBACK: ChangeWorkingData on the experiment object ────────────────
    try; exp.ChangeWorkingData(elem,cellM);  ok=true; return; catch; end
    try; exp.ChangeWorkingData(elem,cellMt); ok=true; return; catch; end
    try; exp.ChangeWorkingData(elem,m);      ok=true; return; catch; end
end

function diagnoseINCAAPI(fig)
% INCA MIP + COM diagnostic.
    inca = incaCOMCache();
    if isempty(inca)
        uialert(fig,'INCA not connected.','Not Connected'); return;
    end
    appData = fig.UserData;
    testParam = '';
    if isfield(appData,'handles') && isfield(appData.handles,'dd1') && isvalid(appData.handles.dd1)
        testParam = char(appData.handles.dd1.Value);
    end
    lines = {};

    % MIP status
    lines{end+1}='=== INCA-MIP Status ===';
    mipPath = findMIPPath();
    if ~isempty(mipPath)
        lines{end+1}=sprintf('  MIP folder found: %s', mipPath);
    else
        lines{end+1}='  MIP folder NOT found (this is NORMAL on INCA 7.4 — MIP is';
        lines{end+1}='  only shipped with INCA 7.5.5+). Tool will use raw COM API.';
    end
    mipOk = ensureMIPOnPath();
    lines{end+1}=sprintf('  INCA_SetValue callable: %s', mat2str(mipOk));
    if ~mipOk
        lines{end+1}='  → Using raw COM API (compatible with INCA 7.4 and 7.5)';
    end

    % MIP write test
    if mipOk && ~isempty(testParam)
        lines{end+1}=sprintf('--- MIP write test for ''%s'' ---',testParam);
        tm = ones(12,14)*300;
        try; INCA_SetValue(testParam, tm);  lines{end+1}='  [OK] INCA_SetValue(12x14)  <- USE MIP';
        catch ME; lines{end+1}=sprintf('  [X] INCA_SetValue(12x14): %s',ME.message(1:min(80,length(ME.message)))); end
        try; INCA_SetValue(testParam, tm'); lines{end+1}='  [OK] INCA_SetValue(14x12)  <- USE MIP transposed';
        catch ME; lines{end+1}=sprintf('  [X] INCA_SetValue(14x12): %s',ME.message(1:min(80,length(ME.message)))); end
    end

    % Use the WORKING COPY's known dimensions — INCA 7.4's GetXDistribution/Y
    % return scalars (counts, not arrays), so they cannot be trusted here.
    % The shift map structure is fixed: pedalRows × (7 upshifts + 7 downshifts)
    % for an 8-speed map, with first and last rows stripped (boundary rows).
    if ~isempty(testParam)
        lines{end+1}=sprintf('--- Map dimensions for ''%s'' ---',testParam);

        % Try to read live working copy from main figure to know the true size
        nX = 0; nY = 0; haveWC = false;
        try
            % Find the main figure by name PREFIX — fig.Name now appends live status.
            allFigs = findall(0,'Type','figure');
            mainFig = [];
            for fi = 1:numel(allFigs)
                try
                    nm = char(allFigs(fi).Name);
                    if startsWith(nm, 'Pattern Plotter')
                        mainFig = allFigs(fi); break;
                    end
                catch; end
            end
            if ~isempty(mainFig)
                ad = mainFig(1).UserData;
                if isfield(ad,'workingCopy') && ~isempty(ad.workingCopy) ...
                        && isfield(ad.workingCopy,'Z_up') && isfield(ad.workingCopy,'Z_down')
                    nGears = size(ad.workingCopy.Z_up, 2);
                    nY = size(ad.workingCopy.Z_up, 1) - 2;   % strip boundary rows
                    nX = nGears * 2;
                    haveWC = true;
                end
            end
        catch; end

        if haveWC
            lines{end+1}=sprintf('  Working copy says: %d rows × %d cols (boundary rows stripped)', nY, nX);
            lines{end+1}='  Note: first + last rows of the editor are tool-side reference only';
            lines{end+1}='        and are NOT written to INCA — see pushMapToINCA().';
        else
            lines{end+1}='  No working copy loaded — cannot verify dimensions.';
        end

        try
            exp = getINCAExperiment(inca);
            elem = exp.GetCalibrationElement(testParam);
            v = elem.GetValue();

            % Show what methods INCA 7.4 actually exposes on the value object
            try
                methodList = methods(v);
                relevantMethods = methodList(contains(methodList, {'Set', 'Put', 'Change'}, 'IgnoreCase', true));
                if ~isempty(relevantMethods)
                    lines{end+1}='--- Available SetValue-like methods on INCA value object ---';
                    for k = 1:min(15, numel(relevantMethods))
                        lines{end+1}=sprintf('  • %s', relevantMethods{k});
                    end
                end
            catch; end

            if haveWC
                % Test 9 different argument formats. Print FULL error messages so we can
                % see exactly which type INCA 7.4 wants (the "Unable to cast" error is
                % usually followed by ".. of type Object[,] to type Double[,] ..." etc.)
                tc = ones(nY, nX) * 300;
                cellStr2D   = arrayfun(@num2str, tc,  'UniformOutput', false);
                cellStr2DT  = arrayfun(@num2str, tc', 'UniformOutput', false);
                cellDbl2D   = num2cell(tc);
                flatRow     = reshape(tc.', 1, []);          % row-major 1D
                flatCol     = tc(:).';                        % col-major 1D
                flatStrRow  = arrayfun(@num2str, flatRow, 'UniformOutput', false);

                lines{end+1}=sprintf('--- SetValue test (%dx%d, dummy 300, full error msgs) ---', nY, nX);
                wroteOK = false;

                tests = {
                    'cell-string 2D',         cellStr2D;
                    'cell-string 2D transp',  cellStr2DT;
                    'cell-double 2D',         cellDbl2D;
                    'double 2D',              tc;
                    'double 2D transp',       tc';
                    'double 1D row-major',    flatRow;
                    'double 1D col-major',    flatCol;
                    'cell-string 1D',         flatStrRow
                };

                for ti = 1:size(tests,1)
                    label = tests{ti,1}; arg = tests{ti,2};
                    try
                        v.SetValue(arg);
                        lines{end+1}=sprintf('  [OK] SetValue(%s) — WORKS!', label);
                        wroteOK = true;
                        break;
                    catch ME
                        msg = ME.message;
                        if length(msg) > 240, msg = [msg(1:240) '...']; end
                        lines{end+1}=sprintf('  [X] SetValue(%s):', label);
                        lines{end+1}=sprintf('       %s', msg);
                    end
                end

                % If SetValue family fails, try the property-setter path (the lowercase
                % 'set' method visible in the available methods list — generic setter)
                if ~wroteOK
                    lines{end+1}='--- Trying property-setter path (set-method) ---';
                    propTests = {'Value','Values','MapValue','Data'};
                    for pi = 1:numel(propTests)
                        try
                            set(v, propTests{pi}, tc);
                            lines{end+1}=sprintf('  [OK] set(v, ''%s'', double 2D) — WORKS!', propTests{pi});
                            wroteOK = true; break;
                        catch ME
                            msg = ME.message; if length(msg)>180, msg=[msg(1:180) '...']; end
                            lines{end+1}=sprintf('  [X] set(v, ''%s''): %s', propTests{pi}, msg);
                        end
                    end
                end

                % Also dump available PROPERTIES (different from methods) of the value object
                try
                    p = fieldnames(v);
                    if ~isempty(p)
                        lines{end+1}='--- Available PROPERTIES on INCA value object ---';
                        for k = 1:min(20, numel(p))
                            try, val = v.(p{k}); cls = class(val);
                                if numel(val) > 0 && (isnumeric(val) || ischar(val) || isstring(val))
                                    sval = strtrim(evalc('disp(val)'));
                                    if length(sval) > 60, sval = [sval(1:60) '...']; end
                                    lines{end+1}=sprintf('  • %s (%s) = %s', p{k}, cls, sval);
                                else
                                    lines{end+1}=sprintf('  • %s (%s, %dx%d)', p{k}, cls, size(val,1), size(val,2));
                                end
                            catch
                                lines{end+1}=sprintf('  • %s (read-error)', p{k});
                            end
                        end
                    end
                catch; end

                if wroteOK
                    lines{end+1}='';
                    lines{end+1}='  ⚠ TEST WROTE DUMMY VALUES (300) TO INCA. Reload the dataset';
                    lines{end+1}='    in INCA, or push the real map again from Pattern Plotter.';
                end

                % ── KEY DISCOVERY: SetValue wants a CalibrationMatrixData wrapper ──
                % Probe for factory methods + direct ProgID instantiation
                lines{end+1}='';
                lines{end+1}='--- Searching for CalibrationMatrixData factory ---';

                % 1. Methods on inca root, exp, elem, valObj that contain Create/New/Make
                roots = {'inca',inca; 'exp',exp; 'elem',elem; 'valObj',v};
                for ri = 1:size(roots,1)
                    rname = roots{ri,1}; robj = roots{ri,2};
                    if isempty(robj), continue; end
                    try
                        m = methods(robj);
                        m = m(contains(m, {'Create','New','Make','Build','Matrix','Data'}, 'IgnoreCase', true));
                        if ~isempty(m)
                            lines{end+1}=sprintf('  Methods on %s containing Create/New/Make/Matrix/Data:', rname);
                            for k = 1:min(15, numel(m))
                                lines{end+1}=sprintf('    • %s.%s', rname, m{k});
                            end
                        end
                    catch; end
                end

                % 2. Try direct ProgID instantiation of common wrapper-class names
                wrapperProgIDs = {
                    'IncaCOM.CalibrationMatrixData',
                    'CebraCom.CalibrationMatrixData',
                    'IncaCOM.CalMatrixData',
                    'IncaCOM.MatrixData',
                    'Inca.CalibrationMatrixData'
                };
                lines{end+1}='--- Trying direct ProgID for CalibrationMatrixData wrapper ---';
                wrapperFound = false;
                for wi = 1:numel(wrapperProgIDs)
                    try
                        wrap = actxserver(wrapperProgIDs{wi});
                        lines{end+1}=sprintf('  [OK] actxserver(''%s'') succeeded', wrapperProgIDs{wi});
                        try
                            wm = methods(wrap);
                            lines{end+1}=sprintf('       methods: %s', strjoin(wm(1:min(8,numel(wm)))','  '));
                        catch; end
                        wrapperFound = true;
                        % Try to fill it and pass to SetValue
                        try
                            % Common method names on these wrappers
                            for setterName = {'SetValues','SetValue','SetData','SetMatrix','set_Values'}
                                try, wrap.(setterName{1})(tc); break; catch; end
                            end
                            v.SetValue(wrap);
                            lines{end+1}=sprintf('  [OK] SetValue(wrap) — WORKS via %s!', wrapperProgIDs{wi});
                            wroteOK = true;
                        catch ME
                            msg=ME.message; if length(msg)>180, msg=[msg(1:180) '...']; end
                            lines{end+1}=sprintf('       [X] SetValue(wrap) failed: %s', msg);
                        end
                        try, release(wrap); catch; end
                        if wroteOK, break; end
                    catch
                        % silent — try next ProgID
                    end
                end
                if ~wrapperFound
                    lines{end+1}='  No direct-instantiate ProgID found — must use a factory method.';
                end

                % 3. Try invoking common factory names on inca/exp objects
                if ~wroteOK
                    lines{end+1}='--- Trying factory methods to build wrapper ---';
                    factoryAttempts = {
                        inca, 'CreateCalibrationMatrixData';
                        inca, 'NewCalibrationMatrixData';
                        inca, 'CreateMatrixData';
                        exp,  'CreateCalibrationMatrixData';
                        exp,  'NewCalibrationMatrixData';
                        elem, 'CreateValue';
                        elem, 'NewValue'
                    };
                    for fi = 1:size(factoryAttempts,1)
                        host = factoryAttempts{fi,1}; mname = factoryAttempts{fi,2};
                        if isempty(host), continue; end
                        try
                            wrap = host.(mname)();
                            lines{end+1}=sprintf('  [OK] %s() returned an object', mname);
                            try
                                for setterName = {'SetValues','SetValue','SetData','SetMatrix'}
                                    try, wrap.(setterName{1})(tc); break; catch; end
                                end
                                v.SetValue(wrap);
                                lines{end+1}=sprintf('  [OK] SetValue(%s()) — WORKS!', mname);
                                wroteOK = true; break;
                            catch ME
                                msg=ME.message; if length(msg)>180, msg=[msg(1:180) '...']; end
                                lines{end+1}=sprintf('       [X] %s wrap fill/SetValue: %s', mname, msg);
                            end
                        catch
                            % silent — method doesn't exist
                        end
                    end
                end

                if ~wroteOK
                    lines{end+1}='';
                    lines{end+1}='  → No write path worked. Share this output so we can';
                    lines{end+1}='    identify the correct CalibrationMatrixData factory.';
                end
            else
                lines{end+1}='  (No working copy — skipping SetValue dimension test.)';
            end
        catch ME3; lines{end+1}=sprintf('  Error reading INCA element: %s', ME3.message); end
    end

    diagFig=uifigure('Name','INCA API Diagnostic','Position',[200 80 700 600]);
    gl=uigridlayout(diagFig,[2,1],'RowHeight',{'1x',44},'Padding',[10 10 10 10]);
    uitextarea(gl,'Value',lines,'Editable','off','FontName','Courier New','FontSize',9);
    btnG=uigridlayout(gl,[1,2],'ColumnWidth',{'1x','1x'},'Padding',[0 0 0 0]);
    uibutton(btnG,'Text','Copy to Clipboard','ButtonPushedFcn',@(~,~)clipboard('copy',strjoin(lines,newline)));
    uibutton(btnG,'Text','Close','ButtonPushedFcn',@(~,~)delete(diagFig));
end


function disableSyncWithError(fig, paramName, row, col, errMsg)
% Show sync error. Offer Diagnose button so user can inspect INCA API.
% Does NOT auto-disable — user decides whether to keep sync on.
    try
        appData = fig.UserData;
        locStr = '';
        if row > 0, locStr = sprintf(' [row %d, col %d]', row, col); end
        choice = uiconfirm(fig, ...
            sprintf(['INCA write failed for ''%s''%s.\n\n' ...
                'Error: %s\n\n' ...
                'This usually means the parameter access path needs adjustment.\n' ...
                'Use "Diagnose INCA API" to see available methods, then share\n' ...
                'the output so the correct path can be hardcoded.\n\n' ...
                'Keep Sync to INCA enabled?'], paramName, locStr, errMsg), ...
            'INCA Sync Error', ...
            'Options', {'Keep Enabled','Diagnose API','Disable Sync'}, ...
            'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'warning');
        switch choice
            case 'Diagnose API'
                diagnoseINCAAPI(fig);
            case 'Disable Sync'
                if isfield(appData,'handles') && isfield(appData.handles,'cbSyncINCA') ...
                        && isvalid(appData.handles.cbSyncINCA)
                    appData.handles.cbSyncINCA.Value = false;
                    fig.UserData = appData;
                end
                incaCOMCache([]);
        end
        % 'Keep Enabled' — do nothing, sync stays on
    catch; end
end


function dRows = buildDetailRows(ped, u1v, u2v, vRows, ruleTxt)
% Build violation detail rows: one per bad pedal index.
    dRows = {};
    for vi = 1:numel(vRows)
        r = vRows(vi);
        if r < 1 || r > numel(ped), continue; end
        p  = round(double(ped(r)));
        r1 = round(double(u1v(r)));
        r2 = round(double(u2v(r)));
        dRows(end+1,:) = {p, r1, r2, r2-r1, ruleTxt}; %#ok<AGROW>
    end
end

function safeSetDDValue(dd, val)
% Set dropdown value only if val is in Items - avoids crash when filter has changed.
    try
        if isvalid(dd) && ismember(val, dd.Items)
            dd.Value = val;
        end
    catch; end
end

function showTabAbout(fig, tabName)
    switch tabName
        case 'clustering'
            msg = [...
                'CLUSTERING (PCA + K-Means)' newline newline ...
                'What it does:' newline ...
                '  Groups all shift maps into clusters based on their overall' newline ...
                '  shift pattern similarity using Principal Component Analysis (PCA).' newline newline ...
                'What you see:' newline ...
                '  - Each dot = one shift map' newline ...
                '  - Dots close together = similar shift behaviour' newline ...
                '  - Colour = cluster group' newline ...
                '  - Red triangle = anomaly (unusual map)' newline newline ...
                'How to use:' newline ...
                '  Click any dot to load that map as Map A on the main plot.'];
        case 'anomaly'
            msg = [...
                'ANOMALY DETECTION (PCA Reconstruction Error)' newline newline ...
                'What it does:' newline ...
                '  Identifies shift maps that behave differently from the majority' newline ...
                '  by measuring how well each map fits the typical pattern.' newline newline ...
                'What you see:' newline ...
                '  - Bar height = anomaly score (Z-score)' newline ...
                '  - Red bars above 2sigma line = flagged anomalies' newline ...
                '  - Bottom panel = gear-level detail for the selected map' newline newline ...
                'How to use:' newline ...
                '  Click any bar to load that map as Map A on the main plot.'];
        case 'basemap'
            msg = [...
                'BASE MAP DEVIATION (vs SKL_GKF_5)' newline newline ...
                'What it does:' newline ...
                '  Measures how much each map deviates from the base map' newline ...
                '  (SKL_GKF_5) across all 14 gear columns (7 upshift + 7 downshift).' newline newline ...
                'What you see:' newline ...
                '  - Bar chart = % deviation per gear column for the selected map' newline ...
                '  - Ranking chart = all maps sorted by total deviation' newline ...
                '  - Main GUI plot = selected map (A) vs base (B) overlay' newline newline ...
                'How to use:' newline ...
                '  Select a map from the dropdown — it loads into Map A.' newline ...
                '  SKL_GKF_5 is loaded into Map B automatically for comparison.' newline ...
                '  Click a bar in the ranking to jump to that map.'];
        case 'consistency'
            msg = [...
                'CONSISTENCY CHECK' newline newline ...
                'What it does:' newline ...
                '  Validates every shift map against three engineering rules:' newline newline ...
                '  1. Upshift Monotonic' newline ...
                '     Upshift RPM must increase with pedal position.' newline ...
                '  2. Downshift Monotonic' newline ...
                '     Downshift RPM must increase with pedal position.' newline ...
                '  3. Hysteresis (Up > Down)' newline ...
                '     Upshift RPM must always be greater than downshift RPM' newline ...
                '     for the same gear pair — prevents shift hunting.' newline newline ...
                'What you see:' newline ...
                '  - Green OK = passes that check' newline ...
                '  - Red FAIL = violation found (detail in last column)' newline newline ...
                'How to use:' newline ...
                '  Click any row to load that map as Map A for inspection.'];
        case 'levelcomp'
            msg = [...
                'LEVEL 1 vs LEVEL 2 — LOGIC ANALYSIS' newline newline ...
                'PURPOSE' newline ...
                '  Validates that a Level 2 (aggressive/sport) map is correctly' newline ...
                '  more aggressive than a Level 1 (normal) map.' newline newline ...
                '━━━━━ TOLERANCE INPUTS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' newline ...
                '  L2≥L1 margin (RPM)' newline ...
                '    Min RPM L2 must exceed L1 at each active pedal row.' newline ...
                '    0=strict, +50=L2 must be at least 50 RPM higher,' newline ...
                '    -30=allow L2 up to 30 RPM below L1.' newline newline ...
                '  Min delta - full pedal (RPM)' newline ...
                '    At full-throttle rows, L2 must exceed L1 by at least' newline ...
                '    this amount. Catches calibrations that are aggressive' newline ...
                '    at part-throttle but identical at wide-open throttle.' newline newline ...
                '  Full pedal rows' newline ...
                '    How many rows from the bottom count as full throttle.' newline ...
                '    Typically 2-4 rows depending on pedal resolution.' newline newline ...
                '  Low pedal ignore (<%)' newline ...
                '    Pedal rows below this threshold are excluded from' newline ...
                '    Checks 1 & 2. Crossings in the creep/idle region' newline ...
                '    (e.g. <10%) are common and acceptable.' newline newline ...
                '  Spread tol (%)' newline ...
                '    Allowed narrowing of L2 hysteresis vs L1 before' newline ...
                '    flagging. 15% means L2 spread ≥ 85% of L1 spread.' newline newline ...
                '  Issue at > rows' newline ...
                '    For the spread check: violations ≤ this = ⚠ WARN,' newline ...
                '    violations > this = ❌ ISSUE.' newline newline ...
                '━━━━━ CHECKS (per gear pair) ━━━━━━━━━━━━━━━━━━━━━━━━━' newline ...
                '  1. L2 upshift ≥ L1 + margin  (active pedal rows only)' newline ...
                '  2. L2 downshift ≥ L1 + margin  (active pedal rows only)' newline ...
                '  3. Hysteresis (Up > Down) in both L1 and L2' newline ...
                '  4. Hysteresis spread: L2 ≥ L1 × (1 - spread tol)' newline ...
                '  5. Monotonicity: RPM increases with pedal in both maps' newline ...
                '  6. Full-throttle delta: L2 exceeds L1 by min delta RPM' newline ...
                '     at the last N rows (ensures meaningful aggressiveness' newline ...
                '     at high load, not just at part-throttle)' newline ...
                '  7. Average aggressiveness delta per gear' newline ...
                '     Reports avg RPM difference over active pedal rows.' newline ...
                '     ⚠ WARN if positive in one direction only.' newline ...
                '  8. Cross-level: L2 downshift > L1 upshift' newline ...
                '     Prevents a situation where switching from Sport→Normal' newline ...
                '     causes an immediate upshift (L2 Dn ≤ L1 Up at the' newline ...
                '     same gear means the two modes conflict).' newline newline ...
                'RESULTS' newline ...
                '  ✅ OK — Check passed   ⚠ WARN — Borderline   ❌ ISSUE — Violation' newline ...
                '  Click any row in the summary table to inspect violations.'];
        otherwise
            msg = 'No description available for this tab.';
    end
    uialert(fig, msg, 'About This View', 'Icon', 'info');
end

function showSessionLog(fig)
% Show a window with the full action history for this session.
    appData = fig.UserData;
    if ~isfield(appData,'sessionLog'), appData.sessionLog = {}; end
    if isempty(appData.sessionLog)
        uialert(fig, 'No actions recorded yet in this session.', 'Session History', 'Icon','info');
        return;
    end

    scrn = get(0,'ScreenSize');
    lFig = uifigure('Name','Session History','Position', ...
        [scrn(1)+(scrn(3)-680)/2, scrn(2)+(scrn(4)-480)/2, 680, 480]);
    gl = uigridlayout(lFig,[3 1]);
    gl.RowHeight = {28,'1x',36}; gl.Padding = [10 10 10 10];

    log = appData.sessionLog;
    n   = numel(log);
    uilabel(gl,'Text',sprintf('Session history — %d actions recorded (newest first):', n), ...
        'FontWeight','bold','FontSize',11);

    % Build table — newest first
    dat = cell(n, 3);
    for i = 1:n
        entry  = log{n+1-i};
        dat{i,1} = entry{1};   % timestamp
        dat{i,2} = entry{3};   % action category
        dat{i,3} = entry{2};   % detail
    end

    tbl = uitable(gl,'Data',dat, ...
        'ColumnName',{'Time','Action','Detail'}, ...
        'ColumnWidth',{80,160,'1x'},'RowName',{});

    % Colour-code rows by action type
    mapEditRows    = find(contains(dat(:,2), 'Map Edit'));
    interpRows     = find(contains(dat(:,2), 'Interp'));
    saveRows       = find(contains(dat(:,2), 'Save') & ~contains(dat(:,2), 'Project'));
    projectRows    = find(contains(dat(:,2), 'Project'));
    fsitRows       = find(contains(dat(:,2), 'FSIT'));

    if ~isempty(mapEditRows),  addStyle(tbl, uistyle('BackgroundColor',[0.88 0.95 1]),   'row', mapEditRows');  end
    if ~isempty(interpRows),   addStyle(tbl, uistyle('BackgroundColor',[0.92 1 0.88]),   'row', interpRows');   end
    if ~isempty(saveRows),     addStyle(tbl, uistyle('BackgroundColor',[1 0.95 0.75],'FontWeight','bold'), 'row', saveRows'); end
    if ~isempty(projectRows),  addStyle(tbl, uistyle('BackgroundColor',[0.8 1 0.8],'FontWeight','bold'),  'row', projectRows'); end
    if ~isempty(fsitRows),     addStyle(tbl, uistyle('BackgroundColor',[0.95 0.88 1]),   'row', fsitRows');     end

    pnlBot = uipanel(gl,'BorderType','none');
    glBot  = uigridlayout(pnlBot,[1 3]);
    glBot.ColumnWidth = {'1x',130,80}; glBot.Padding = [0 0 0 0];
    uilabel(glBot,'Text', ...
        '🔵 Map edit  🟢 Save  🟡 Interp  🟣 FSIT  🟩 Project');
    uibutton(glBot,'Text','Clear History', ...
        'ButtonPushedFcn', @(~,~) clearLog(fig, lFig));
    uibutton(glBot,'Text','Close', ...
        'ButtonPushedFcn', @(~,~) delete(lFig));

    function clearLog(mainFig, logFig)
        ad = mainFig.UserData;
        ad.sessionLog = {};
        mainFig.UserData = ad;
        delete(logFig);
        uialert(mainFig,'History cleared.','History','Icon','info');
    end
end

function showFSITImpact(fig, fsitVar, newVal)
% Show which maps are affected when an FSIT switch changes value.
    try
        appData = fig.UserData;
        if ~isfield(appData,'allMaps') || isempty(appData.allMaps), return; end

        desc     = getFSITDesc(fsitVar);
        rawParts = strtrim(strsplit(desc, ','));
        % Strip trailing _ and * so 'UKSVF_' becomes 'UKSVF' for startsWith
        prefixes = cellfun(@(p) strtrim(strrep(strrep(p,'*',''),'_','')), rawParts, 'UniformOutput', false);
        prefixes = prefixes(~cellfun(@isempty, prefixes));

        affected = {};
        for i = 1:numel(appData.allMaps)
            nm  = char(appData.allMaps{i}.name);
            nmC = strrep(nm,'_','');  % also strip underscores from map name for comparison
            hit = false;
            for p = 1:numel(prefixes)
                if startsWith(nmC, prefixes{p}, 'IgnoreCase', true)
                    hit = true; break;
                end
            end
            if hit, affected{end+1} = nm; end %#ok<AGROW>
        end

        if isempty(affected)
            uialert(fig, sprintf('No maps found matching prefixes for:\n%s\n\nDesc: %s', fsitVar, desc), ...
                'FSIT Impact', 'Icon','info');
            return;
        end

        scrn = get(0,'ScreenSize');
        iFig = uifigure('Name',sprintf('FSIT Impact: %s', fsitVar), ...
            'Position',[scrn(1)+(scrn(3)-500)/2, scrn(2)+(scrn(4)-400)/2, 500, 400]);
        igl  = uigridlayout(iFig,[4 1]);
        igl.RowHeight = {28, 22, '1x', 32}; igl.Padding = [10 10 10 10];

        uilabel(igl,'Text',sprintf('FSIT: %s  →  new value: %s', fsitVar, num2str(newVal)), ...
            'FontWeight','bold','FontSize',12,'FontColor',[0.1 0.4 0.8]);
        uilabel(igl,'Text',sprintf('Prefixes: %s', desc), ...
            'FontSize',9,'FontColor',[0.4 0.4 0.4],'FontAngle','italic');

        tbl2 = uitable(igl,'Data',affected(:), ...
            'ColumnName',{sprintf('Maps affected (%d of %d)', numel(affected), numel(appData.allMaps))}, ...
            'ColumnWidth',{'1x'},'RowName',{});
        addStyle(tbl2, uistyle('BackgroundColor',[0.9 1 0.9],'FontWeight','bold'), 'column', 1);

        uibutton(igl,'Text','Close','ButtonPushedFcn',@(~,~) delete(iFig));
    catch; end
end

function loadBaseToMapB(fig, baseMap)
% Load the base map (SKL_GKF_5) into Map B on the main GUI.
    try
        ad = fig.UserData;
        if ~isfield(ad,'handles') || ~isfield(ad.handles,'dd2') || ~isvalid(ad.handles.dd2)
            return;
        end
        baseName = char(baseMap.name);
        if ismember(baseName, ad.handles.dd2.Items)
            ad.handles.dd2.Value = baseName;
            ad.currentMapNameB = baseName;
            fig.UserData = ad;
            updatePlot(fig);
        end
    catch; end
end

function openInterpWithWarning(fig)
    choice = uiconfirm(fig, ...
        sprintf('Interpolation is still under development.\n\nSome features may be incomplete or unstable.\n\nDo you want to continue?'), ...
        'Under Development', ...
        'Options', {'Continue', 'Cancel'}, ...
        'DefaultOption', 'Continue', 'CancelOption', 'Cancel', ...
        'Icon', 'warning');
    if strcmp(choice, 'Continue')
        Intermaps(fig);
    end
end

function Intermaps(fig)
% Intermaps - Interpolation Tables Editor with INCA-style display
    appData = fig.UserData;
    if isfield(appData, 'interpFig') && hasValidHandle(appData, 'interpFig')
        appData.interpFig.Visible = 'on'; figure(appData.interpFig); return;
    end
    
    % Loading dialog (non-modal so it doesn't deadlock if anything blocks below)
    loadFig = uifigure('Name', 'Loading...', 'Position', [500 400 360 90]);
    loadLbl = uilabel(loadFig, 'Text', 'Loading Interpolation Data...', ...
        'Position', [15 50 330 25], 'FontSize', 12, 'FontWeight', 'bold');
    loadSub = uilabel(loadFig, 'Text', '', ...
        'Position', [15 20 330 22], 'FontSize', 10, 'FontColor', [0.4 0.4 0.4]);
    drawnow limitrate;

    % Pre-load all data with progress updates
    varDefs = getInterpVarDefs();
    interpData = struct();
    T = appData.T;
    nVars = size(varDefs, 1);
    for i = 1:nVars
        vn = varDefs{i, 1};
        sn = matlab.lang.makeValidName(vn);
        try
            interpData.(sn) = extractInterpVariable(T, vn);
        catch ME
            interpData.(sn) = [];
            try, diagnosticLogPush(sprintf('Interp:extract %s', vn), ME); catch; end
        end
        if mod(i, 5) == 0 || i == nVars
            try
                if isvalid(loadSub), loadSub.Text = sprintf('Parsed %d / %d variables', i, nVars); end
                drawnow limitrate;
            catch; end
        end
    end
    try, if isvalid(loadFig), loadFig.delete; end; catch; end
    
    % Main window
    d = uifigure('Name', 'Interpolation Tables', 'Position', [40 40 1400 900]);
    d.CloseRequestFcn = @(~,~) closeInterpWin(fig, d);
    d.WindowKeyPressFcn = @(~,e) interpKeyPress(fig, e);
    
    appData.interpFig = d;
    appData.interpData = interpData;
    appData.interpHist = {};
    appData.interpTbls = {};
    appData.interpInfo = {};
    appData.interpSel = [];
    appData.interpActTbl = [];
    fig.UserData = appData;
    
    % Layout
    mainGl = uigridlayout(d, [2 1]);
    mainGl.RowHeight = {'1x', 45};
    mainGl.Padding = [5 5 5 5];
    
    tg = uitabgroup(mainGl);
    tg.Layout.Row = 1;
    
    % Build all tabs with progressive status feedback
    buildInterpTabs(fig, d, tg, interpData);
    drawnow limitrate;  % force layout to settle after tab building so scroll panels size correctly
    
    % Buttons
    btnPnl = uipanel(mainGl, 'BorderType', 'none');
    btnPnl.Layout.Row = 2;
    btnGl = uigridlayout(btnPnl, [1 7]);
    btnGl.ColumnWidth = {140, 120, 120, 120, 140, '1x', 90};
    btnGl.Padding = [8 3 8 3];
    
    uibutton(btnGl, 'Text', 'SAVE CHANGES', 'BackgroundColor', [1 0.8 0], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) saveInterpData(fig, d));
    uibutton(btnGl, 'Text', 'Refresh', 'BackgroundColor', [0.85 0.92 1], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) refreshInterpWin(fig, d, tg));
    uibutton(btnGl, 'Text', 'Export', 'BackgroundColor', [0.92 0.92 0.92], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) exportInterpData(fig));
    uibutton(btnGl, 'Text', 'Undo', 'BackgroundColor', [1 0.9 0.9], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) undoInterpEdit(fig));
    % NEW: GBF_SSact button in the middle
    uibutton(btnGl, 'Text', 'GBF_SSact', 'BackgroundColor', [0.7 0.9 0.7], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) openGBFSSact(fig));
    uilabel(btnGl, 'Text', '');
    uibutton(btnGl, 'Text', 'Close', 'ButtonPushedFcn', @(~,~) closeInterpWin(fig, d));
    
    d.UserData = struct('tg', tg);
end

%% === VARIABLE DEFINITIONS ===
function varDefs = getInterpVarDefs()
    varDefs = {
        'FSIT_SWIFCO','SiFCO'; 'SIFCO_EngSpdMin','SiFCO'; 'SIFCO_EngSpdMinBSG','SiFCO'; 'SIZW_FacNMoMinProgIdFCO','SiFCO';
        'FSIT_SWIALT','SiALT'; 'SIALT_EngSpdMinAcpt','SiALT'; 'SIALT_EngSpdMin','SiALT'; 'SIALT_EngSpdMinM','SiALT'; 'SIZW_FacNMoMinProgIdAlti','SiALT';
        'UKZW_NabMin','NabMin'; 'UKZW_NabMin_LOW','NabMin'; 'UKZW_NabMinAlti','NabMin'; 'UKZW_NabMinAltiLow','NabMin';
        'FSIT_SWIOD','SiOD'; 'SIOD_RGA_EXIT','SiOD'; 'SIOD_VEntr1G','SiOD'; 'SIOD_VEntr2G','SiOD'; 'SIOD_VEntr3G','SiOD'; 'SIOD_VEntr4G','SiOD'; 'SIOD_VEntr5G','SiOD'; 'SIOD_VEntr6G','SiOD'; 'SIOD_VEntr7G','SiOD'; 'SIOD_Voffs','SiOD';
        'SIBE_AdiffMidPar1','Grade_Tables'; 'SIBE_AdiffMidPar2','Grade_Tables'; 'SIBE_AdiffMidPar3','Grade_Tables'; 'SIBE_AdiffMidPar4','Grade_Tables'; 'SIBE_AdiffMidPar5','Grade_Tables';
        'SIBE_AdiffMidParForUKTYP','Grade_Shift'; 'SIBE_AdiffMidParForUKFGR','Grade_Shift'; 'SIBE_AdiffMidParForUKBSG','Grade_Shift';
        'SIBE_AdiffMidForUKECO','Grade_ECO'; 'SIBE_AdiffMidForUKTOW','Grade_Tow'; 'SIBE_AdiffMidForUKLOW','Grade_4Lo';
        'SIBE_AdiffMidForUKGGS','Grade_GGS'; 'SIBE_AdiffMidForUKGGS_LOW','Grade_GGS';
        'SIBE_AdiffMidForUKSND','Grade_Sand'; 'SIBE_AdiffMidForUKSND_LOW','Grade_Sand';
        'SIBE_AdiffMidForUKXC','Grade_Mud'; 'SIBE_AdiffMidForUKXC_LOW','Grade_Mud';
        'UKSVF_NABADIFF_21RS','Brake_ADIFF'; 'UKSVF_NABADIFF_32RS','Brake_ADIFF'; 'UKSVF_NABADIFF_43RS','Brake_ADIFF'; 'UKSVF_NABADIFF_54RS','Brake_ADIFF'; 'UKSVF_NABADIFF_65RS','Brake_ADIFF'; 'UKSVF_NABADIFF_76RS','Brake_ADIFF'; 'UKSVF_NABADIFF_87RS','Brake_ADIFF';
        'UKSVF_NABKF_21RS','Brake_KF'; 'UKSVF_NABKF_32RS','Brake_KF'; 'UKSVF_NABKF_43RS','Brake_KF'; 'UKSVF_NABKF_54RS','Brake_KF'; 'UKSVF_NABKF_65RS','Brake_KF'; 'UKSVF_NABKF_76RS','Brake_KF'; 'UKSVF_NABKF_87RS','Brake_KF';
        'TYRNG_CNT_SS','DriverTyCnt';
    };
end

%% === TAB BUILDING ===
function buildInterpTabs(mainFig, interpFig, tg, interpData)
% Per-tab try/catch + drawnow yields between tabs so:
%   1. One bad tab can't kill the whole window (others still build)
%   2. UI stays responsive — no apparent freeze
%   3. Any failure is logged to diagnosticLogPush for later inspection
%
% If you ever see the window hang again, click Help → Diagnostic Log
% to see exactly which tab failed.
    tryBuildTab(@() buildMapViewTab(mainFig, interpFig, uitab(tg, 'Title', 'MAP View')), 'MAP View');
    tryBuildTab(@() buildHillInterpTab(mainFig, interpFig, uitab(tg, 'Title', 'Hill Interp'), interpData), 'Hill Interp');
    tryBuildTab(@() buildScrollTab(mainFig, interpFig, uitab(tg,'Title','Driver Ty Cnt'), interpData, {'TYRNG_CNT_SS'}), 'Driver Ty Cnt');
    tryBuildTab(@() buildScrollTab(mainFig, interpFig, uitab(tg,'Title','SiFCO'), interpData, {'FSIT_SWIFCO','SIFCO_EngSpdMin','SIFCO_EngSpdMinBSG','SIZW_FacNMoMinProgIdFCO'}), 'SiFCO');
    tryBuildTab(@() buildScrollTab(mainFig, interpFig, uitab(tg,'Title','SiALT'), interpData, {'FSIT_SWIALT','SIALT_EngSpdMinAcpt','SIALT_EngSpdMin','SIALT_EngSpdMinM','SIZW_FacNMoMinProgIdAlti'}), 'SiALT');
    tryBuildTab(@() buildScrollTab(mainFig, interpFig, uitab(tg,'Title','Nab Min Tables'), interpData, {'UKZW_NabMin','UKZW_NabMin_LOW','UKZW_NabMinAlti','UKZW_NabMinAltiLow'}), 'Nab Min Tables');
    tryBuildTab(@() buildSiODTab(mainFig, interpFig, uitab(tg,'Title','SiOD'), interpData, {'FSIT_SWIOD','SIOD_RGA_EXIT','SIOD_VEntr1G','SIOD_VEntr2G','SIOD_VEntr3G','SIOD_VEntr4G','SIOD_VEntr5G','SIOD_VEntr6G','SIOD_VEntr7G','SIOD_Voffs'}), 'SiOD');

    % Grade tab — has nested sub-tabs
    gradeTab = uitab(tg,'Title','Grade');
    glG = uigridlayout(gradeTab, [1 1]); glG.Padding = [0 0 0 0];
    gTg = uitabgroup(glG);
    tryBuildTab(@() buildScrollTab(mainFig, interpFig, uitab(gTg,'Title','Grade Tables'), interpData, {'SIBE_AdiffMidPar1','SIBE_AdiffMidPar2','SIBE_AdiffMidPar3','SIBE_AdiffMidPar4','SIBE_AdiffMidPar5'}), 'Grade>Grade Tables');
    tryBuildTab(@() buildScrollTab(mainFig, interpFig, uitab(gTg,'Title','Shifting Situation'), interpData, {'SIBE_AdiffMidParForUKTYP','SIBE_AdiffMidParForUKFGR','SIBE_AdiffMidParForUKBSG'}), 'Grade>Shifting Situation');
    tryBuildTab(@() buildScrollTab(mainFig, interpFig, uitab(gTg,'Title','ECO Grade'), interpData, {'SIBE_AdiffMidForUKECO'}), 'Grade>ECO');
    tryBuildTab(@() buildScrollTab(mainFig, interpFig, uitab(gTg,'Title','Tow Grade'), interpData, {'SIBE_AdiffMidForUKTOW'}), 'Grade>Tow');
    tryBuildTab(@() buildScrollTab(mainFig, interpFig, uitab(gTg,'Title','4Lo Grade'), interpData, {'SIBE_AdiffMidForUKLOW'}), 'Grade>4Lo');
    tryBuildTab(@() buildScrollTab(mainFig, interpFig, uitab(gTg,'Title','GGS Grade'), interpData, {'SIBE_AdiffMidForUKGGS','SIBE_AdiffMidForUKGGS_LOW'}), 'Grade>GGS');
    tryBuildTab(@() buildScrollTab(mainFig, interpFig, uitab(gTg,'Title','Sand Grade'), interpData, {'SIBE_AdiffMidForUKSND','SIBE_AdiffMidForUKSND_LOW'}), 'Grade>Sand');
    tryBuildTab(@() buildScrollTab(mainFig, interpFig, uitab(gTg,'Title','Mud Grade'), interpData, {'SIBE_AdiffMidForUKXC','SIBE_AdiffMidForUKXC_LOW'}), 'Grade>Mud');

    % Brake tab — has nested sub-tabs
    brakeTab = uitab(tg,'Title','Brake');
    glB = uigridlayout(brakeTab, [1 1]); glB.Padding = [0 0 0 0];
    bTg = uitabgroup(glB);
    tryBuildTab(@() buildScrollTab(mainFig, interpFig, uitab(bTg,'Title','NAB ADIFF (Grade)'), interpData, {'UKSVF_NABADIFF_21RS','UKSVF_NABADIFF_32RS','UKSVF_NABADIFF_43RS','UKSVF_NABADIFF_54RS','UKSVF_NABADIFF_65RS','UKSVF_NABADIFF_76RS','UKSVF_NABADIFF_87RS'}), 'Brake>NAB ADIFF');
    tryBuildTab(@() buildScrollTab(mainFig, interpFig, uitab(bTg,'Title','NAB KF (Driver)'), interpData, {'UKSVF_NABKF_21RS','UKSVF_NABKF_32RS','UKSVF_NABKF_43RS','UKSVF_NABKF_54RS','UKSVF_NABKF_65RS','UKSVF_NABKF_76RS','UKSVF_NABKF_87RS'}), 'Brake>NAB KF');
end


function tryBuildTab(buildFcn, tabName)
% Wrapper: runs a tab-build function with try/catch + drawnow yield.
% Records the result to the diagnostic log so failures are visible later.
    t0 = tic;
    try
        buildFcn();
        try, drawnow limitrate; catch; end
        try, diagnosticLogPush(sprintf('Interp:%s', tabName), sprintf('built OK in %.2fs', toc(t0))); catch; end
    catch ME
        try, diagnosticLogPush(sprintf('Interp:%s', tabName), ME); catch; end
        % Don't rethrow — keep building remaining tabs
    end
end

%% === MAP VIEW TAB ===
function buildMapViewTab(mainFig, interpFig, tab)
    appData = mainFig.UserData;
    
    % Main layout: Left = Plot, Right = Controls
    gl = uigridlayout(tab, [1 2]);
    gl.ColumnWidth = {'1x', 320};
    gl.Padding = [5 5 5 5];
    gl.ColumnSpacing = 10;
    
    % === LEFT PANEL: Plot Area ===
    plotPanel = uipanel(gl, 'Title', 'Pedal % vs Output Shaft RPM', 'FontWeight', 'bold', 'FontSize', 12);
    plotGl = uigridlayout(plotPanel, [1 1]);
    plotGl.Padding = [5 5 5 5];
    
    % Create axes for the plot
    ax = uiaxes(plotGl);
    ax.XLabel.String = 'Output Shaft RPM';
    ax.YLabel.String = 'Pedal %';
    ax.Title.String = 'MAP Visualization';
    ax.FontSize = 11;
    ax.XGrid = 'on';
    ax.YGrid = 'on';
    hold(ax, 'on');
    
    % === RIGHT PANEL: Controls ===
    ctrlPanel = uipanel(gl, 'Title', 'Controls', 'FontWeight', 'bold', 'FontSize', 12);
    ctrlGl = uigridlayout(ctrlPanel, [10 2]);
    ctrlGl.RowHeight = {30, 50, 30, 50, 30, 50, 30, 50, 30, '1x'};
    ctrlGl.ColumnWidth = {120, '1x'};
    ctrlGl.Padding = [10 10 10 10];
    ctrlGl.RowSpacing = 5;
    
    % 1. Drive Mode Dropdown - AT TOP with data from GBF_SSact table
    uilabel(ctrlGl, 'Text', 'Drive Mode:', 'FontWeight', 'bold', 'FontSize', 11);
    uilabel(ctrlGl, 'Text', '');
    
    % Get Shifting Situations from GBF_SSact table
    shiftingSituations = getShiftingSituationsFromGBFSSact(mainFig);
    
    % If GBF_SSact not available, fallback to old method
    if isempty(shiftingSituations)
        % Fallback: Get active SKLID maps from UK table
        activeSKLIDs = getActiveSKLIDMaps(mainFig);
        
        % Add 3 special predefined modes at the beginning
        specialModes = {'Auto (0,5,10,15,20)', 'Sport (2,7,12,17,22)', 'Track (4,9,14,19,24)'};
        
        % Combine: Special modes first, then SKLIDs
        if isempty(activeSKLIDs)
            allModes = specialModes;
        else
            allModes = [specialModes, activeSKLIDs];
        end
    else
        % Use Shifting Situations from GBF_SSact
        allModes = shiftingSituations;
    end
    
    % Create dropdown with ALL modes
    modeDropdown = uidropdown(ctrlGl, 'Items', allModes, 'Value', allModes{1}, 'FontSize', 10);
    modeDropdown.Layout.Column = [1 2];
    
    % 2. Pedal % (0-100%)
    uilabel(ctrlGl, 'Text', 'Pedal %:', 'FontWeight', 'bold', 'FontSize', 11);
    uilabel(ctrlGl, 'Text', '');
    pedalSlider = uislider(ctrlGl, 'Limits', [0 100], 'Value', 50, 'MajorTicks', 0:20:100);
    pedalSlider.Layout.Column = [1 2];
    
    % 3. Brake (0-50)
    uilabel(ctrlGl, 'Text', 'Brake:', 'FontWeight', 'bold', 'FontSize', 11);
    uilabel(ctrlGl, 'Text', '');
    brakeSlider = uislider(ctrlGl, 'Limits', [0 50], 'Value', 0, 'MajorTicks', 0:10:50);
    brakeSlider.Layout.Column = [1 2];
    
    % 4. Grade (-50 to 50 degrees)
    uilabel(ctrlGl, 'Text', 'Grade (°):', 'FontWeight', 'bold', 'FontSize', 11);
    uilabel(ctrlGl, 'Text', '');
    gradeSlider = uislider(ctrlGl, 'Limits', [-50 50], 'Value', 0, 'MajorTicks', -50:25:50);
    gradeSlider.Layout.Column = [1 2];
    
    % 5. Driver Type Counter (5-600: Auto 5-200 | Sport 201-400 | Track 401-600)
    uilabel(ctrlGl, 'Text', 'Driver Type:', 'FontWeight', 'bold', 'FontSize', 11);
    uilabel(ctrlGl, 'Text', '');
    driverSlider = uislider(ctrlGl, 'Limits', [5 600], 'Value', 100, 'MajorTicks', [5,100,200,300,400,500,600]);
    driverSlider.Layout.Column = [1 2];
    
    % 6. SIMPLIFIED Information Display
    uilabel(ctrlGl, 'Text', '');
    uilabel(ctrlGl, 'Text', '');
    
    mapInfoPanel = uipanel(ctrlGl, 'Title', 'Mode Information', 'FontSize', 10, 'FontWeight', 'bold');
    mapInfoPanel.Layout.Column = [1 2];
    mapInfoGl = uigridlayout(mapInfoPanel, [1 1]);
    mapInfoGl.Padding = [5 5 5 5];
    
    % Simplified text area - clean display
    mapInfoText = uitextarea(mapInfoGl, 'Value', {'Select a drive mode...'}, ...
        'Editable', 'off', 'FontSize', 10, 'FontName', 'Consolas');
    
    % Store handles
    mapViewHandles = struct();
    mapViewHandles.ax = ax;
    mapViewHandles.pedalSlider = pedalSlider;
    mapViewHandles.brakeSlider = brakeSlider;
    mapViewHandles.gradeSlider = gradeSlider;
    mapViewHandles.driverSlider = driverSlider;
    mapViewHandles.modeDropdown = modeDropdown;
    mapViewHandles.mapInfoText = mapInfoText;
    
    % Store in interpFig
    ud = interpFig.UserData;
    if isempty(ud), ud = struct(); end
    ud.mapViewHandles = mapViewHandles;
    interpFig.UserData = ud;
    
    % Set callbacks - AUTO UPDATE
    modeDropdown.ValueChangedFcn = @(src, e) onDriveModeChanged(mainFig, interpFig);
    pedalSlider.ValueChangedFcn = @(src, e) updateMapViewPlot(mainFig, interpFig);
    brakeSlider.ValueChangedFcn = @(src, e) updateMapViewPlot(mainFig, interpFig);
    gradeSlider.ValueChangedFcn = @(src, e) updateMapViewPlot(mainFig, interpFig);
    driverSlider.ValueChangedFcn = @(src, e) updateMapViewPlot(mainFig, interpFig);
    
    % Initial update
    onDriveModeChanged(mainFig, interpFig);
end

function activeMaps = getActiveSKLIDMaps(mainFig)
    % Get list of active SKLID map names from UK Table data
    % Only returns SKLIDs where FSIT_Act = "Yes" (blue highlighted)
    appData = mainFig.UserData;
    activeMaps = {};
    
    % Check for ukData field
    if ~isfield(appData, 'ukData') || isempty(appData.ukData)
        return;
    end

    origUK = appData.ukData;

    % Use cached activeAbbrevs — never rebuild FSIT map here
    if isfield(appData,'activeAbbrevs') && ~isempty(appData.activeAbbrevs)
        activeAbbrevs = appData.activeAbbrevs;
    else
        activeAbbrevs = computeActiveAbbrevs(appData.T);
    end

    % Now check each UK entry - ukData columns: UK, Abbrev, ID, SKLID, UL, USP, DSP, Map Numbers
    for i = 1:size(origUK, 1)
        abbrev = origUK{i, 2};  % Column 2 is Abbrev
        sklid = string(origUK{i, 4});  % Column 4 is SKLID
        
        % Check if this abbreviation is active (FSIT_Act = "Yes")
        match = false;
        for j = 1:length(activeAbbrevs)
            token = activeAbbrevs{j};
            if ~isempty(token) && contains(abbrev, token, 'IgnoreCase', true)
                match = true;
                break;
            end
        end
        
        % Only add if FSIT_Act would be "Yes" AND SKLID exists
        if match && ~isempty(strtrim(char(sklid))) && ~strcmp(sklid, 'Not Found')
            activeMaps{end+1} = char(sklid);
        end
    end
    
    % Remove duplicates and sort
    activeMaps = unique(activeMaps);
end

function onDriveModeChanged(mainFig, interpFig)
    ud = interpFig.UserData;
    if ~isfield(ud, 'mapViewHandles'), return; end
    h = ud.mapViewHandles;
    
    appData = mainFig.UserData;
    selectedMode = h.modeDropdown.Value;
    
    % First, check if selectedMode is a Shifting Situation from GBF_SSact
    % If so, get the corresponding SKL_ID
    actualSKLID = getSKLIDFromShiftingSituation(mainFig, selectedMode);
    if ~isempty(actualSKLID)
        % Found matching SKL_ID in GBF_SSact, use it
        selectedMode = actualSKLID;
    end
    
    % Check if it's a special predefined mode
    isSpecialMode = false;
    modeName = '';
    mapsUsed = [];
    
    if contains(selectedMode, 'Auto')
        isSpecialMode = true;
        modeName = 'Auto (Normal Mode)';
        mapsUsed = [0, 5, 10, 15, 20];
    elseif contains(selectedMode, 'Sport')
        isSpecialMode = true;
        modeName = 'Sport';
        mapsUsed = [2, 7, 12, 17, 22];
    elseif contains(selectedMode, 'Track')
        isSpecialMode = true;
        modeName = 'Track / Baha';
        mapsUsed = [4, 9, 14, 19, 24];
    end
    
    if isSpecialMode
        % SIMPLIFIED display for special modes
        infoLines = {};
        infoLines{end+1} = '──────────────────────────────';
        infoLines{end+1} = sprintf('Mode: %s', modeName);
        infoLines{end+1} = '──────────────────────────────';
        infoLines{end+1} = ' ';
        infoLines{end+1} = 'Maps Used for Interpolation:';
        infoLines{end+1} = sprintf('  %s', strjoin(string(mapsUsed), ', '));
        infoLines{end+1} = ' ';
        infoLines{end+1} = 'Drive Type Mapping:';
        infoLines{end+1} = sprintf('  Aggressive 0 → Map %d (Downhill)', mapsUsed(1));
        infoLines{end+1} = sprintf('  Aggressive 1 → Map %d (Flat)', mapsUsed(2));
        infoLines{end+1} = sprintf('  Aggressive 2 → Map %d', mapsUsed(3));
        infoLines{end+1} = sprintf('  Aggressive 3 → Map %d', mapsUsed(4));
        infoLines{end+1} = sprintf('  Aggressive 4 → Map %d (Uphill)', mapsUsed(5));
        infoLines{end+1} = '──────────────────────────────';
        
        h.mapInfoText.Value = infoLines;
    else
        % SIMPLIFIED display for SKLID modes
        ukName = '';
        fsitAct = '';
        ukID = '';
        mapNums = [];
        
        if isfield(appData, 'ukData') && ~isempty(appData.ukData)
            origUK = appData.ukData;

            % Use cached activeAbbrevs — never rebuild FSIT map here
            if isfield(appData,'activeAbbrevs') && ~isempty(appData.activeAbbrevs)
                activeAbbrevs = appData.activeAbbrevs;
            else
                activeAbbrevs = computeActiveAbbrevs(appData.T);
            end

            % Find matching row
            for i = 1:size(origUK, 1)
                sklid = string(origUK{i, 4});
                abbrev = origUK{i, 2};

                if strcmp(sklid, selectedMode)
                    ukName = origUK{i, 1};
                    ukID = num2str(origUK{i, 3});
                    if size(origUK,2) >= 8, mapNumStr = origUK{i,8}; else, mapNumStr = ''; end  % col 8 = Map Numbers

                    % Check if active
                    match = false;
                    for j = 1:length(activeAbbrevs)
                        token = activeAbbrevs{j};
                        if ~isempty(token) && contains(abbrev, token, 'IgnoreCase', true)
                            match = true;
                            break;
                        end
                    end
                    if match, fsitAct = 'Yes'; else, fsitAct = 'No'; end

                    nums = parseMapNumbers(mapNumStr);
                    mapNums = nums;
                    break;
                end
            end
        end
        
        % SIMPLIFIED SKLID display
        if isempty(ukName)
            h.mapInfoText.Value = {'SKLID not found in UK table'};
        else
            infoLines = {};
            infoLines{end+1} = '──────────────────────────────';
            infoLines{end+1} = sprintf('SKLID: %s', selectedMode);
            infoLines{end+1} = '──────────────────────────────';
            infoLines{end+1} = sprintf('UK Name: %s', ukName);
            infoLines{end+1} = sprintf('ID: %s', ukID);
            infoLines{end+1} = sprintf('Status: %s', fsitAct);
            infoLines{end+1} = ' ';
            
            if isempty(mapNums)
                infoLines{end+1} = 'Maps: Not Found';
            else
                infoLines{end+1} = sprintf('Maps (%d total):', length(mapNums));
                % Display in rows of 10
                mapStr = strjoin(string(mapNums), ', ');
                mapArray = strtrim(split(mapStr, ','));
                for i = 1:10:length(mapArray)
                    endIdx = min(i+9, length(mapArray));
                    rowMaps = mapArray(i:endIdx);
                    infoLines{end+1} = sprintf('  %s', strjoin(rowMaps, ', '));
                end
            end
            infoLines{end+1} = '──────────────────────────────';
            
            h.mapInfoText.Value = infoLines;
        end
    end
    
    % Auto-update GBF_SSact table if it's open
    updateGBFSSactFromDriveMode(mainFig, selectedMode);
    
    % Update plot
    updateMapViewPlot(mainFig, interpFig);
end

function nums = parseMapNumbers(mapNumStr)
    nums = [];
    mapNumStr = char(mapNumStr);
    if isempty(mapNumStr) || strcmp(mapNumStr, 'Not Found')
        return;
    end
    
    % Try to parse as number
    n = str2double(mapNumStr);
    if ~isnan(n)
        nums = n;
        return;
    end
    
    % Try to parse comma-separated
    parts = strsplit(mapNumStr, ',');
    for i = 1:length(parts)
        n = str2double(strtrim(parts{i}));
        if ~isnan(n)
            nums(end+1) = n;
        end
    end
end

function updateMapViewPlot(mainFig, interpFig)
    ud = interpFig.UserData;
    if ~isfield(ud, 'mapViewHandles'), return; end
    h = ud.mapViewHandles;
    appData = mainFig.UserData;

    pedalPct    = h.pedalSlider.Value;
    selectedMode = h.modeDropdown.Value;

    cla(h.ax); hold(h.ax, 'on'); grid(h.ax, 'on');

    % Determine which map numbers correspond to the selected mode
    modeMapNums = [];
    if contains(selectedMode, 'Auto')
        modeMapNums = [0 1 5 6 10 11 15 16 20 21];
    elseif contains(selectedMode, 'Sport')
        modeMapNums = [2 3 7 8 12 13 17 18 22 23];
    elseif contains(selectedMode, 'Track')
        modeMapNums = [4 9 14 19 24];
    end

    % Find allMaps that match the selected mode numbers
    if ~isfield(appData,'allMaps') || isempty(appData.allMaps)
        title(h.ax,'No maps loaded'); hold(h.ax,'off'); return;
    end
    plotted = 0;
    colors  = lines(10);
    legendEntries = {};
    for i = 1:length(appData.allMaps)
        m   = appData.allMaps{i};
        tok = regexp(char(m.name),'SKL_GKF_(\d+)','tokens','once');
        if isempty(tok), continue; end
        mn = str2double(tok{1});
        if ~isempty(modeMapNums) && ~ismember(mn, modeMapNums), continue; end
        plotted = plotted + 1;
        if plotted > 8, break; end
        c = colors(mod(plotted-1,10)+1,:);
        % Plot upshift line 1-2 vs pedal
        if size(m.Z_up,2) >= 1
            plot(h.ax, m.Z_up(:,1), m.pedal, '-', 'Color',c, 'LineWidth',1.4, ...
                'DisplayName', sprintf('Map %d US12',mn));
        end
        legendEntries{end+1} = sprintf('Map %d',mn); %#ok<AGROW>
    end

    if ~isempty(legendEntries)
        legend(h.ax, legendEntries, 'Location','best','FontSize',8);
    end
    yline(h.ax, pedalPct, '--r', sprintf('Pedal: %.0f%%',pedalPct), ...
        'LineWidth',1.5,'LabelHorizontalAlignment','left');
    xlabel(h.ax,'Output RPM'); ylabel(h.ax,'Pedal %');
    title(h.ax, sprintf('%s — %d maps shown', selectedMode, plotted));
    hold(h.ax,'off');
end

function buildScrollTab(mainFig, interpFig, tab, interpData, varNames)
% V7.6.3 rewrite — uses uigridlayout with explicit row heights instead of
% pixel-positioned panels. The old pixel approach broke on R2024b + DPI
% scaling because:
%   1. Hardcoded per-row (30px) didn't match actual uitable row height
%   2. Some panels ended up at NEGATIVE Y (scrolled off-screen above) = missing tables
%   3. uipanel Title bar eats ~20px from content area = cut-off rows
% uigridlayout auto-manages all sizing, scales correctly with DPI, and adds
% scrollbars automatically when content exceeds the visible area.

    nv = length(varNames);
    if nv == 0, return; end

    % Per-variable row heights (panel = title + table + info label)
    rowHeights = cell(1, nv);
    for i = 1:nv
        sn = matlab.lang.makeValidName(varNames{i});
        if isfield(interpData, sn) && ~isempty(interpData.(sn))
            vi = interpData.(sn);
            switch vi.type
                case 'VALUE'
                    rowHeights{i} = 75;
                case 'MAP'
                    nr = size(vi.data, 1);
                    % Header + nr data rows × 27px + table chrome + info label + panel title
                    rowHeights{i} = 70 + (nr + 1) * 27 + 28;
                case 'CURVE'
                    rowHeights{i} = 145;   % 2 rows + chrome + info + title
                otherwise
                    rowHeights{i} = 120;
            end
        else
            rowHeights{i} = 70;
        end
    end

    % Single scrollable grid — uigridlayout handles all the layout math
    g = uigridlayout(tab, [nv, 1]);
    g.RowHeight   = rowHeights;
    g.ColumnWidth = {'1x'};
    g.Padding     = [8 8 8 8];
    g.RowSpacing  = 6;
    g.Scrollable  = 'on';

    for i = 1:nv
        vn = varNames{i};
        sn = matlab.lang.makeValidName(vn);

        pnl = uipanel(g, 'Title', vn, 'FontWeight', 'bold', 'FontSize', 11);
        pnl.Layout.Row    = i;
        pnl.Layout.Column = 1;

        if ~isfield(interpData, sn) || isempty(interpData.(sn))
            ig = uigridlayout(pnl, [1 1]); ig.Padding = [5 3 5 3];
            uilabel(ig, 'Text', ['Not found: ' vn], 'FontColor', [0.7 0 0], 'FontSize', 11);
            continue;
        end

        vi = interpData.(sn);
        switch vi.type
            case 'VALUE',  buildValueTbl(mainFig, interpFig, pnl, vi);
            case 'MAP',    buildMapTbl(mainFig, interpFig, pnl, vi);
            case 'CURVE',  buildCurveTbl(mainFig, interpFig, pnl, vi);
        end
    end
end

%% === TABLE BUILDERS ===
function t = buildValueTbl(mainFig, ~, pnl, vi)
    g = uigridlayout(pnl, [1 3]);
    g.ColumnWidth = {60, 80, 60};  % Compact: label, value, unit (no stretching)
    g.Padding = [5 5 5 5];  % Tighter padding
    
    % Display the value - ensure it's a number and readable
    dispVal = vi.value;
    if isnan(dispVal) || isempty(dispVal)
        dispVal = 0;
    end
    
    % Label
    uilabel(g, 'Text', 'Value:', 'FontWeight', 'bold', 'FontSize', 11, ...
        'HorizontalAlignment', 'right');
    
    % Single cell table for the value - compact
    t = uitable(g, 'Data', {dispVal}, 'ColumnName', {}, 'RowName', [], ...
        'ColumnEditable', true, 'ColumnWidth', {70}, 'FontSize', 11);
    t.CellEditCallback = @(s,e) onValueEditSimple(mainFig, s, e, vi);
    t.CellSelectionCallback = @(s,e) onInterpSel(mainFig, s, e, vi.name);
    
    % Show unit as label (if exists)
    unitStr = vi.unit;
    if isempty(unitStr) || strcmp(unitStr, '-')
        unitStr = '';
    end
    uilabel(g, 'Text', unitStr, 'FontSize', 10, 'FontAngle', 'italic', ...
        'FontColor', [0.4 0.4 0.5]);
    
    storeTbl(mainFig, t, vi);
end

function onValueEditSimple(mainFig, t, e, ~)
    if isempty(e.Indices), return; end
    storeInterpStateForUndo(mainFig, t, e);
    addStyle(t, getYellowStyle(), 'cell', e.Indices);
end


function t = buildMapTbl(mainFig, interpFig, pnl, vi)
% INCA-style MAP table: ALL cells editable including X-axis and Y-axis
% Layout:
%   Row 1: [VarName] [X1] [X2] [X3] ...  <- X-axis values (EDITABLE)
%   Row 2: [Y1]      [D]  [D]  [D]  ...  <- Y-axis + Data (EDITABLE)
%   Row 3: [Y2]      [D]  [D]  [D]  ...
    g = uigridlayout(pnl, [2 1]);
    g.RowHeight = {'1x', 14};
    g.Padding = [2 2 2 2];
    g.RowSpacing = 2;
    
    nr = size(vi.data, 1);
    nc = size(vi.data, 2);
    
    % Build INCA-style table data: (nr+1) rows x (nc+1) columns
    % Vectorized fill — replaces 4 nested for-loops (huge speedup on big tables).
    td = cell(nr + 1, nc + 1);
    td{1, 1} = vi.name;

    % Row 1, Cols 2+ = X-axis (use vi.xAxis where available, else column index)
    xRow = 1:nc;
    if ~isempty(vi.xAxis)
        m = min(nc, length(vi.xAxis));
        xRow(1:m) = vi.xAxis(1:m);
    end
    td(1, 2:end) = num2cell(xRow);

    % Col 1, Rows 2+ = Y-axis (use vi.yAxis where available, else row index)
    yCol = (1:nr).';
    if ~isempty(vi.yAxis)
        m = min(nr, length(vi.yAxis));
        yCol(1:m) = vi.yAxis(1:m);
    end
    td(2:end, 1) = num2cell(yCol);

    % Data block — single vectorized assignment instead of nr*nc loop
    td(2:end, 2:end) = num2cell(vi.data);
    
    % Column names (just numbers for reference)
    colNames = arrayfun(@(x) num2str(x), 1:(nc+1), 'UniformOutput', false);
    
    % Create table - ALL columns editable, font size 12
    t = uitable(g, 'Data', td, 'ColumnName', colNames, 'RowName', [], ...
        'ColumnEditable', true, 'FontSize', 12);
    
    % Set column widths - optimized for split view (50% of panel width)
    cw = max(65, min(95, floor(620 / (nc + 1))));  % Adjusted for 50/50 split
    t.ColumnWidth = repmat({cw}, 1, nc + 1);
    
    % Style: Gray background for header row + first column.
    % Cache the style object so we don't instantiate it once per table (slow).
    persistent gsInterpHeader_
    if isempty(gsInterpHeader_)
        gsInterpHeader_ = uistyle('BackgroundColor', [0.9 0.9 0.95], 'FontWeight', 'bold');
    end
    addStyle(t, gsInterpHeader_, 'row', 1);
    addStyle(t, gsInterpHeader_, 'column', 1);
    
    % Callbacks
    t.CellEditCallback = @(s,e) onMapEdit(mainFig, s, e, vi);
    t.CellSelectionCallback = @(s,e) onInterpSel(mainFig, s, e, vi.name);
    
    % Context menu
    cm = uicontextmenu(interpFig);
    uimenu(cm, 'Text', 'Add (+/-)...', 'MenuSelectedFcn', @(~,~) interpMath(mainFig, 'add'));
    uimenu(cm, 'Text', 'Multiply (*)...', 'MenuSelectedFcn', @(~,~) interpMath(mainFig, 'mult'));
    uimenu(cm, 'Text', 'Divide (/)...', 'MenuSelectedFcn', @(~,~) interpMath(mainFig, 'div'));
    uimenu(cm, 'Text', 'Percent (%)...', 'MenuSelectedFcn', @(~,~) interpMath(mainFig, 'pct'));
    uimenu(cm, 'Text', 'Copy', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) copySelection(t));
    uimenu(cm, 'Text', 'Paste', 'MenuSelectedFcn', @(~,~) pasteSelection(t, @(s) onInterpPaste(mainFig, s, vi.name)));
    t.ContextMenu = cm;
    
    % Info label
    uilabel(g, 'Text', sprintf('MAP (%dx%d) | Unit: %s', nr, nc, vi.unit), ...
        'FontSize', 9, 'FontAngle', 'italic', 'FontColor', [0.4 0.4 0.5]);
    
    vi.isINCA = true;
    storeTbl(mainFig, t, vi);
end

function t = buildCurveTbl(mainFig, interpFig, pnl, vi)
% INCA-style CURVE table: ALL cells editable
% Layout:
%   Row 1: [X1] [X2] [X3] ...  <- X-axis values (EDITABLE)
%   Row 2: [D1] [D2] [D3] ...  <- Data values (EDITABLE)
    g = uigridlayout(pnl, [2 1]);
    g.RowHeight = {'1x', 14};
    g.Padding = [2 2 2 2];
    g.RowSpacing = 2;
    
    nc = length(vi.data);
    td = cell(2, nc);

    % Row 1 = X-axis values (vectorized — replaces 2 for-loops)
    xRow = 0:(nc-1);
    if ~isempty(vi.xAxis)
        m = min(nc, length(vi.xAxis));
        xRow(1:m) = vi.xAxis(1:m);
    end
    td(1, :) = num2cell(xRow);

    % Row 2 = Data values (single vectorized assignment)
    td(2, :) = num2cell(vi.data(:).');
    
    % Column names (just numbers)
    colNames = arrayfun(@(x) num2str(x), 1:nc, 'UniformOutput', false);
    
    % Create table with row names for clarity, font size 12
    t = uitable(g, 'Data', td, 'ColumnName', colNames, 'RowName', {'X-Axis', 'Value'}, ...
        'ColumnEditable', true, 'FontSize', 12);
    
    % Column widths - optimized for split view (50% of panel width)
    cw = max(65, min(90, floor(620 / min(nc, 18))));  % Adjusted for 50/50 split
    t.ColumnWidth = repmat({cw}, 1, nc);
    
    % Style: Gray background for X-axis row (cached for speed)
    persistent gsInterpHeader_
    if isempty(gsInterpHeader_)
        gsInterpHeader_ = uistyle('BackgroundColor', [0.9 0.9 0.95], 'FontWeight', 'bold');
    end
    addStyle(t, gsInterpHeader_, 'row', 1);
    
    % Callbacks
    t.CellEditCallback = @(s,e) onCurveEdit(mainFig, s, e, vi);
    t.CellSelectionCallback = @(s,e) onInterpSel(mainFig, s, e, vi.name);
    
    % Context menu
    cm = uicontextmenu(interpFig);
    uimenu(cm, 'Text', 'Add (+/-)...', 'MenuSelectedFcn', @(~,~) interpMath(mainFig, 'add'));
    uimenu(cm, 'Text', 'Multiply (*)...', 'MenuSelectedFcn', @(~,~) interpMath(mainFig, 'mult'));
    uimenu(cm, 'Text', 'Copy', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) copySelection(t));
    uimenu(cm, 'Text', 'Paste', 'MenuSelectedFcn', @(~,~) pasteSelection(t, @(s) onInterpPaste(mainFig, s, vi.name)));
    t.ContextMenu = cm;
    
    % Info label
    uilabel(g, 'Text', sprintf('CURVE (%d pts) | Unit: %s', nc, vi.unit), ...
        'FontSize', 9, 'FontAngle', 'italic', 'FontColor', [0.4 0.4 0.5]);
    
    vi.isCurve = true;
    vi.isINCA = true;
    storeTbl(mainFig, t, vi);
end

function storeTbl(mainFig, t, vi)
    ad = mainFig.UserData;
    if ~isfield(ad,'interpTbls'), ad.interpTbls = {}; end
    if ~isfield(ad,'interpInfo'),  ad.interpInfo  = {}; end
    ad.interpTbls{end+1} = t;
    ad.interpInfo{end+1} = vi;
    mainFig.UserData = ad;
end

%% === DATA EXTRACTION - FULLY CORRECTED ===
function vi = extractInterpVariable(T, varName)
    vi = [];
    
    % Find variable name in Var2 (exact match preferred)
    idx = find(strcmpi(strtrim(string(T.Var2)), varName), 1);
    if isempty(idx)
        % Try contains as fallback
        idx = find(contains(T.Var2, varName, 'IgnoreCase', true), 1);
    end
    if isempty(idx) && width(T) >= 1
        idx = find(contains(T.Var1, varName, 'IgnoreCase', true), 1);
    end
    if isempty(idx), return; end
    
    % Find type marker - ONLY scan AFTER variable name row (not before!)
    % Pattern: varName in Var2 -> format comment -> TYPE marker
    dtype = ''; trow = 0; unit = '-';
    
    for r = idx : min(idx + 5, height(T))
        c1str = strtrim(string(T{r, 1}));
        
        % Extract unit if present
        rtxt = strjoin(string(table2cell(T(r, 1:min(5, width(T))))), ' ');
        um = regexp(rtxt, ':"([^"]+)":', 'tokens');
        if ~isempty(um), unit = um{1}{1}; end
        
        if strcmpi(c1str, 'VALUE') || startsWith(c1str, 'VALUE', 'IgnoreCase', true)
            dtype = 'VALUE'; trow = r; break;
        elseif strcmpi(c1str, 'MAP') || strcmpi(c1str, 'MAP,')
            dtype = 'MAP'; trow = r; break;
        elseif strcmpi(c1str, 'CURVE') || strcmpi(c1str, 'KURVE')
            dtype = 'CURVE'; trow = r; break;
        end
    end
    
    if isempty(dtype), return; end
    
    vi = struct('name', varName, 'type', dtype, 'row', idx, 'trow', trow, 'unit', unit, ...
        'xAxis', [], 'yAxis', [], 'data', [], 'value', NaN, 'headers', [], ...
        'dRowStart', 0, 'dRowEnd', 0, 'dColEnd', 0, 'isINCA', false, 'isCurve', false);
    
    if strcmp(dtype, 'VALUE')
        % Try extracting numeric value from columns 2-10
        rawVals = string(table2cell(T(trow, 2:min(10, width(T)))));
        vals = str2double(rawVals);
        vv = vals(~isnan(vals));
        
        if ~isempty(vv)
            vi.value = vv(1);
        else
            % Handle string values (e.g. boolean flags or text)
            nonEmpty = rawVals(strlength(strtrim(rawVals)) > 0 & ~ismissing(rawVals));
            % Filter out variable name itself if it was picked up
            nonEmpty(strcmpi(nonEmpty, varName)) = [];
            if ~isempty(nonEmpty)
                 vi.value = nonEmpty(1); % Store as string
            end
        end
        vi.dRowStart = trow;
    else
        % Find data rows
        rs = 0; headerRow = 0;
        for r = trow + 1 : min(trow + 8, height(T))
            % Check for data row (mostly numeric in columns 3+)
            % Some MAPs have unit pattern in column 1 like :"1/min":
            vals = str2double(string(table2cell(T(r, 3:end))));
            numCount = sum(~isnan(vals));
            if numCount >= 2
                rs = r;
                break;
            end
            
            % Check for header row (contains text in data columns, not system row)
            rowTxt = strjoin(string(table2cell(T(r, 1:min(3, width(T))))), " ");
            if ~contains(rowTxt, ["X_AXIS","Y_AXIS","MAP","CURVE","VALUE"], 'IgnoreCase', true)
                 rowC = string(table2cell(T(r, 3:end)));
                 if any(strlength(rowC) > 0 & ~ismissing(rowC))
                     headerRow = r;
                 end
            end
        end
        if rs == 0, return; end
        
        re = rs;
        for r = rs : min(rs + 50, height(T))
            vals = str2double(string(table2cell(T(r, 3:end))));
            if sum(~isnan(vals)) < 1, break; end
            re = r;
        end
        
        fr = str2double(string(table2cell(T(rs, :))));
        lv = find(~isnan(fr), 1, 'last');
        mc = max(3, lv);
        
        if headerRow > 0
             % Extract headers up to mc
             rawHeaders = string(table2cell(T(headerRow, 3:mc)));
             vi.headers = rawHeaders;
        end
        
        data = str2double(string(table2cell(T(rs:re, 3:mc))));
        vi.dRowStart = rs;
        vi.dRowEnd = re;
        vi.dColEnd = mc;
        
        if strcmp(dtype, 'CURVE')
            vi.data = data(1, :);
            vi.data = vi.data(~isnan(vi.data));
        else
            vi.data = data;
            vi.data(isnan(vi.data)) = 0;
        end
        
        % === CORRECTED AXIS EXTRACTION ===
        % Pattern in CSV:
        %   Row N:   ,SIBE_AdiffMidForUKTOW    (varName in Var2)
        %   Row N+1: X_AXIS_PTS,:"-":,-120,-24,0,14,...  (axisType in Var1, values in col 3+)
        vi.xAxis = findAxisValuesCorrect(T, varName, 'X_AXIS_PTS', idx);
        if strcmp(dtype, 'MAP')
            vi.yAxis = findAxisValuesCorrect(T, varName, 'Y_AXIS_PTS', idx);
        end
    end
end

function axisPts = findAxisValuesCorrect(T, varName, axisType, startRow)
% CORRECTED axis extraction:
% Look for row where Var1 starts with axisType (X_AXIS_PTS or Y_AXIS_PTS)
% AND the previous row (or r-2) has varName in Var2
% Values are in columns 3+ of the axisType row
    axisPts = [];
    
    for r = startRow : min(startRow + 80, height(T))
        % Check if current row's Var1 starts with axisType
        v1 = strtrim(string(T{r, 1}));
        if startsWith(v1, axisType, 'IgnoreCase', true)
            % Check if current row (r), previous row (r-1) OR row before that (r-2) has our variable name in Var2
            match = false;
            % Check current row
            v2curr = strtrim(string(T.Var2(r)));
            if contains(v2curr, varName, 'IgnoreCase', true), match = true; end
            
            if ~match && r > 1
                v2prev = strtrim(string(T.Var2(r-1)));
                if contains(v2prev, varName, 'IgnoreCase', true), match = true; end
            end
            if ~match && r > 2
                v2prev2 = strtrim(string(T.Var2(r-2)));
                if contains(v2prev2, varName, 'IgnoreCase', true), match = true; end
            end
            
            if match
                % Extract values from columns 3 onwards of THIS row
                vals = str2double(string(table2cell(T(r, 3:end))));
                axisPts = vals(~isnan(vals));
                return;
            end
        end
    end
end

%% === CALLBACKS ===
function onInterpSel(mainFig, ~, e, vn)
    if isempty(e.Indices), return; end
    ad = mainFig.UserData;
    ad.interpSel = e.Indices;
    ad.interpActTbl = e.Source;
    ad.interpActVar = vn;
    mainFig.UserData = ad;
end

function onInterpEdit(mainFig, t, e, ~)
    if isempty(e.Indices), return; end
    storeInterpStateForUndo(mainFig, t, e);
    persistent interpYellow_;
    if isempty(interpYellow_), interpYellow_ = getYellowStyle(); end
    addStyle(t, interpYellow_, 'cell', e.Indices);
end

function onMapEdit(mainFig, t, e, ~)
    if isempty(e.Indices), return; end
    storeInterpStateForUndo(mainFig, t, e);
    persistent mapYellow_;
    if isempty(mapYellow_), mapYellow_ = getYellowStyle(); end
    addStyle(t, mapYellow_, 'cell', e.Indices);
end

function onCurveEdit(mainFig, t, e, ~)
    if isempty(e.Indices), return; end
    storeInterpStateForUndo(mainFig, t, e);
    persistent curveYellow_;
    if isempty(curveYellow_), curveYellow_ = getYellowStyle(); end
    addStyle(t, curveYellow_, 'cell', e.Indices);
end

function onInterpPaste(mainFig, ~, ~)
    pushInterpHist(mainFig);
end

function storeInterpStateForUndo(mainFig, t, e)
    try
        prevVal = e.PreviousData;
        newVal  = e.NewData;

        d = t.Data;
        d{e.Indices(1), e.Indices(2)} = prevVal;
        t.Data = d;

        pushInterpHist(mainFig);

        d{e.Indices(1), e.Indices(2)} = newVal;
        t.Data = d;
    catch; end
end

function pushInterpHist(mainFig)
    ad = mainFig.UserData;
    if ~isfield(ad,'interpTbls') || isempty(ad.interpTbls), return; end
    if ~isfield(ad,'interpHist'), ad.interpHist = {}; end
    st = struct();
    for i = 1:length(ad.interpTbls)
        sn = matlab.lang.makeValidName(ad.interpInfo{i}.name);
        st.(sn) = ad.interpTbls{i}.Data;
    end
    ad.interpHist{end+1} = st;
    if length(ad.interpHist) > 40, ad.interpHist = ad.interpHist(end-39:end); end
    mainFig.UserData = ad;
end

function undoInterpEdit(mainFig)
    ad = mainFig.UserData;
    if ~isfield(ad,'interpHist') || isempty(ad.interpHist), return; end
    if ~isfield(ad,'interpTbls') || isempty(ad.interpTbls), return; end
    st = ad.interpHist{end};
    ad.interpHist(end) = [];
    for i = 1:length(ad.interpTbls)
        t = ad.interpTbls{i};
        vi = ad.interpInfo{i};
        sn = matlab.lang.makeValidName(vi.name);
        if isfield(st, sn)
            t.Data = st.(sn);
            removeStyle(t);
            applyGrayHdr(t, vi);
            
            % If there's a linked table (e.g. MPH view), sync it
            if isprop(t, 'UserData') && isstruct(t.UserData) && isfield(t.UserData, 'linkedTable') && isvalid(t.UserData.linkedTable)
                tLinked = t.UserData.linkedTable;
                % Force update of linked table based on restored data
                % Create dummy event for sync logic, or call sync logic directly
                % Since we don't have the original event, we manually iterate cells or just refresh
                % Easier: Re-run conversion for all data cells
                
                % We need 'vi' to know type. 'vi' is available here.
                kph2mph = 0.621371;
                
                dKPH = t.Data;
                dMPH = tLinked.Data;
                % Clamp to the smaller of the two tables — guards against a
                % linked table that was resized to a different geometry.
                nr = min(size(dKPH,1), size(dMPH,1));
                nc = min(size(dKPH,2), size(dMPH,2));

                % Determine range of data cells based on type
                if strcmp(vi.type, 'VALUE')
                    dMPH{1,1} = dKPH{1,1} * kph2mph;
                elseif strcmp(vi.type, 'MAP')
                    % Copy axis (Row 1, Col 1)
                    dMPH(1,1:nc) = dKPH(1,1:nc);
                    dMPH(1:nr,1) = dKPH(1:nr,1);
                    % Convert Data (Row 2+, Col 2+)
                    for r=2:nr, for c=2:nc
                        if isnumeric(dKPH{r,c}), dMPH{r,c} = dKPH{r,c} * kph2mph; end
                    end, end
                elseif strcmp(vi.type, 'CURVE')
                    % Copy X-Axis (Row 1)
                    dMPH(1,1:nc) = dKPH(1,1:nc);
                    % Convert Values (Row 2)
                    if nr >= 2
                        for c=1:nc
                            if isnumeric(dKPH{2,c}), dMPH{2,c} = dKPH{2,c} * kph2mph; end
                        end
                    end
                end
                
                tLinked.Data = dMPH;
                removeStyle(tLinked);
                applyGrayHdr(tLinked, vi);
                
                % Highlight restored cells in yellow? Maybe not, undo usually clears highlight or reverts to saved state.
                % But user asked for undo function. Standard undo restores previous state.
                % If previous state was "saved" (no highlight), it should be no highlight.
                % removeStyle above handles this.
            end
        end
    end
    mainFig.UserData = ad;
end


function applyGrayHdr(t, vi)
    persistent gs_;
    if isempty(gs_), gs_ = uistyle('BackgroundColor', [0.9 0.9 0.95], 'FontWeight', 'bold'); end
    gs = gs_;
    if strcmp(vi.type, 'MAP') && isfield(vi, 'isINCA') && vi.isINCA
        addStyle(t, gs, 'row', 1);
        addStyle(t, gs, 'column', 1);
    elseif strcmp(vi.type, 'CURVE') && isfield(vi, 'isINCA') && vi.isINCA
        addStyle(t, gs, 'row', 1);
    end
end

function interpMath(mainFig, op)
    ad = mainFig.UserData;
    if ~isfield(ad,'interpSel') || isempty(ad.interpSel) || ...
       ~isfield(ad,'interpActTbl') || isempty(ad.interpActTbl)
        uialert(ad.interpFig, 'Select cells first.', 'Error'); return;
    end
    pushInterpHist(mainFig);
    
    switch op
        case 'add', pr = 'Add:'; df = '0';
        case 'mult', pr = 'Multiply:'; df = '1';
        case 'div', pr = 'Divide:'; df = '1';
        case 'pct', pr = 'Percent:'; df = '0';
    end
    answer = inputdlg(pr, 'Math', [1 30], {df});
    if isempty(answer), return; end
    v = str2double(answer{1});
    if isnan(v), return; end
    
    t = ad.interpActTbl;
    sel = ad.interpSel;
    d = t.Data;
    
    for i = 1:size(sel, 1)
        r = sel(i, 1); c = sel(i, 2);
        cv = d{r, c};
        if ~isnumeric(cv) || isnan(cv), continue; end
        switch op
            case 'add', cv = cv + v;
            case 'mult', cv = cv * v;
            case 'div', if v ~= 0, cv = cv / v; end
            case 'pct', cv = cv * (1 + v/100);
        end
        d{r, c} = cv;
        if r > 1 && c > 1
            addStyle(t, getYellowStyle(), 'cell', [r c]);
        end
    end
    t.Data = d;
end

function interpKeyPress(mainFig, e)
    if strcmp(e.Key, 'z') && any(strcmp(e.Modifier, 'control'))
        undoInterpEdit(mainFig);
    end
end

%% === SAVE / REFRESH / EXPORT / CLOSE ===
function saveInterpData(mainFig, interpFig)
    if ~strcmp(uiconfirm(interpFig, 'Save all changes to CSV data?', 'Confirm Save', 'Options', {'Yes','Cancel'}), 'Yes')
        return;
    end
    ad = mainFig.UserData;
    if ~isfield(ad,'interpTbls') || isempty(ad.interpTbls)
        uialert(interpFig,'No interpolation data to save.','Info'); return;
    end
    T = ad.T;
    
    for i = 1:length(ad.interpTbls)
        t = ad.interpTbls{i};
        vi = ad.interpInfo{i};
        d = t.Data;
        
        if strcmp(vi.type, 'VALUE')
            % VALUE: save the single value (simple table format)
            if vi.dRowStart > 0
                val = d{1, 1};  % Single cell table
                if isnumeric(val)
                    T{vi.dRowStart, 3} = {val};
                end
            end
            
        elseif strcmp(vi.type, 'MAP') && isfield(vi, 'isINCA') && vi.isINCA
            % INCA-style MAP: Row 1 = X-axis, Col 1 = Y-axis, rest = data
            % Only save actual data rows (not empty padding rows)
            actualDataRows = size(vi.data, 1);
            nc = size(vi.data, 2);
            
            % Save data values (rows 2 to actualDataRows+1, cols 2+) to CSV
            for dr = 1:actualDataRows
                tr = vi.dRowStart + dr - 1;
                if tr <= height(T)
                    for dc = 1:nc
                        val = d{dr + 1, dc + 1};
                        if isnumeric(val), T{tr, 2 + dc} = {val}; end
                    end
                end
            end
            
        elseif strcmp(vi.type, 'CURVE') && isfield(vi, 'isINCA') && vi.isINCA
            % INCA-style CURVE: Row 1 = X-axis, Row 2 = data
            if vi.dRowStart > 0 && vi.dRowStart <= height(T)
                nc = length(vi.data);  % Use original data length, not padded
                for dc = 1:nc
                    val = d{2, dc};
                    if isnumeric(val), T{vi.dRowStart, 2 + dc} = {val}; end
                end
            end
        end
        
        % Reset styles
        removeStyle(t);
        applyGrayHdr(t, vi);
    end
    
    ad.T = T;
    ad.interpHist = {};
    mainFig.UserData = ad;
    logAction(mainFig, 'Interp Save', sprintf('%d variables saved to memory', length(ad.interpTbls)));
    uialert(interpFig, 'Changes saved to memory. Use main Save to export CSV.', 'Saved', 'Icon', 'success');
end

function refreshInterpWin(mainFig, interpFig, tg)
    ad = mainFig.UserData;
    varDefs = getInterpVarDefs();
    interpData = struct();
    for i = 1:size(varDefs, 1)
        sn = matlab.lang.makeValidName(varDefs{i, 1});
        interpData.(sn) = extractInterpVariable(ad.T, varDefs{i, 1});
    end
    ad.interpData = interpData;
    ad.interpTbls = {};
    ad.interpInfo = {};
    ad.interpHist = {};
    mainFig.UserData = ad;
    delete(tg.Children);
    drawnow limitrate;  % let layout settle so getpixelposition works correctly in buildScrollTab
    buildInterpTabs(mainFig, interpFig, tg, interpData);
    drawnow limitrate;  % ensure all panels are rendered at correct sizes
    uialert(interpFig, 'Refreshed!', 'OK', 'Icon', 'info');
end

function exportInterpData(mainFig)
    ad = mainFig.UserData;
    if ~isfield(ad,'interpTbls') || isempty(ad.interpTbls)
        uialert(ad.interpFig, 'No interpolation data loaded.', 'Export', 'Icon','info'); return;
    end
    out = sprintf('=== Interpolation Tables ===\n\n');
    for i = 1:length(ad.interpTbls)
        t = ad.interpTbls{i};
        vi = ad.interpInfo{i};
        out = [out sprintf('--- %s (%s) ---\n', vi.name, vi.type)];
        d = t.Data;
        for r = 1:size(d, 1)
            for c = 1:size(d, 2)
                val = d{r, c};
                if isnumeric(val), out = [out sprintf('%.4f\t', val)];
                else, out = [out sprintf('%s\t', string(val))]; end
            end
            out = [out sprintf('\n')];
        end
        out = [out sprintf('\n')];
    end
    clipboard('copy', out);
    uialert(ad.interpFig, 'Copied!', 'Export', 'Icon', 'info');
end

function closeInterpWin(mainFig, interpFig)
    if ~isempty(mainFig) && isvalid(mainFig)
        try
            ad = mainFig.UserData;
            if isfield(ad,'gbfssactFig') && ~isempty(ad.gbfssactFig) && isvalid(ad.gbfssactFig)
                delete(ad.gbfssactFig);
            end
            ad.gbfssactFig = gobjects(0);
            ad.interpFig   = gobjects(0);
            ad.interpTbls  = {};
            ad.interpInfo  = {};
            ad.interpHist  = {};
            if isfield(ad, 'interpData'), ad = rmfield(ad, 'interpData'); end
            mainFig.UserData = ad;
        catch; end
    end
    if ~isempty(interpFig) && isvalid(interpFig), delete(interpFig); end
end

function openGBFSSact(mainFig)
    % Open GBF_SSact (Shifting Situation Active) table
    appData = mainFig.UserData;
    
    % Check if already open
    if isfield(appData, 'gbfssactFig') && hasValidHandle(appData, 'gbfssactFig')
        appData.gbfssactFig.Visible = 'on'; figure(appData.gbfssactFig);
        return;
    end
    
    % Create window (wider to accommodate Map Number column)
    gbfFig = uifigure('Name', 'GBF_SSact - Shifting Situation Active', 'Position', [100 100 1400 650]);
    gbfFig.CloseRequestFcn = @(src,e) closeGBFSSact(mainFig, src);
    
    % Initialize GBF_SSact data if not exists
    if ~isfield(appData, 'gbfssactData') || isempty(appData.gbfssactData)
        appData.gbfssactData = initializeGBFSSactData();
        mainFig.UserData = appData;
    end
    
    % Main layout
    gl = uigridlayout(gbfFig, [2 1]);
    gl.RowHeight = {'1x', 50};
    gl.Padding = [10 10 10 10];
    
    % Table with Map Number column (matching UK table) - ALL EDITABLE
    tGBF = uitable(gl, 'Data', appData.gbfssactData, ...
        'ColumnName', {'GBF_SSact', 'Shifting Situation', 'Downhill', 'Flat', 'Uphill', 'SKL_ID', 'FSIT_Act', 'ID', 'Map Number'}, ...
        'ColumnEditable', true, ...
        'ColumnWidth', {90, 150, 100, 100, 140, 180, 80, 60, 200}, ...
        'CellEditCallback', @(src, e) onGBFSSactEdit(mainFig, src, e), ...
        'CellSelectionCallback', @(src, e) onGBFSSactSelect(src, e));
    
    % Apply initial color coding
    applyGBFSSactColors(mainFig, tGBF);
    
    % Button panel
    btnPnl = uipanel(gl);
    btnPnl.BorderType = 'none';
    btnGl = uigridlayout(btnPnl, [1 4]);
    btnGl.ColumnWidth = {150, 150, '1x', 100};
    btnGl.Padding = [5 5 5 5];
    
    uibutton(btnGl, 'Text', 'SAVE CHANGES', 'BackgroundColor', [1 0.8 0], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) saveGBFSSactData(mainFig, gbfFig));
    uibutton(btnGl, 'Text', 'Refresh from UK', 'BackgroundColor', [0.7 0.9 1], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) refreshGBFSSactFromUK(mainFig, gbfFig));
    uilabel(btnGl, 'Text', 'Edit SKL_ID to auto-update from UK Table', ...
        'FontSize', 10, 'FontAngle', 'italic', 'HorizontalAlignment', 'center');
    uibutton(btnGl, 'Text', 'Close', 'ButtonPushedFcn', @(~,~) closeGBFSSact(mainFig, gbfFig));
    
    % Store reference
    appData.gbfssactFig = gbfFig;
    gbfFig.UserData = struct('tGBF', tGBF);
    mainFig.UserData = appData;
end

function data = initializeGBFSSactData()
    % Initialize GBF_SSact table with default data (9 columns to match UK table)
    data = {
        0,  'Auto',            '0,1',       '5,6',       '10,11,15,16,20,21',  '',                  '',  '',  '';
        0,  'Cruise UKCC',     '',          '',          '',                    'UKCC_SklidACC',     '',  '',  '';
        0,  'Cruise UKFGR',    '',          '',          '',                    'UKFGR_SKLID',       '',  '',  '';
        1,  'P R N',           '',          '',          '',                    '',                  '',  '',  '';
        2,  'Eco',             '',          '',          '',                    'UKECO_SklId',       '',  '',  '';
        3,  '',                '',          '',          '',                    '',                  '',  '',  '';
        4,  'Sports',          '2,3',       '7,8',       '12,13,17,18,22,23',  '',                  '',  '',  '';
        5,  'Snow',            '',          '',          '',                    'UKGGS_SklId',       '',  '',  '';
        5,  'Snow_4Lo',        '',          '',          '',                    'UKGGS_SklIdLow',    '',  '',  '';
        6,  'Tow',             '',          '',          '',                    'UKTOW_SklId',       '',  '',  '';
        7,  'Valet',           '',          '',          '',                    'UKVAL_SklId',       '',  '',  '';
        8,  '4 Lo',            '',          '',          '',                    'UKLOW_SklId',       '',  '',  '';
        9,  'Track',           '4,3',       '9,8',       '14,13,19,18,24,23',  '',                  '',  '',  '';
        10, 'Rock',            '',          '',          '',                    'UKRCK_SklId',       '',  '',  '';
        11, 'Sand / Off road', '',          '',          '',                    'UKSND_SklId',       '',  '',  '';
        11, 'Sand_4Lo',        '',          '',          '',                    'UKSND_SklIdLow',    '',  '',  '';
        12, 'Calibrator Choice','',         '',          '',                    '',                  '',  '',  '';
        13, 'Calibrator Choice','',         '',          '',                    '',                  '',  '',  '';
    };
end

function onGBFSSactEdit(mainFig, tbl, event)
    if isempty(event.Indices), return; end  % guard: spurious callback
    % Handle edits - auto-update FSIT_Act, ID, and Map Number when SKL_ID changes
    appData = mainFig.UserData;
    
    % Save edited data
    appData.gbfssactData = tbl.Data;
    
    % Check if SKL_ID column was edited (column 6)
    if event.Indices(2) == 6
        row = event.Indices(1);
        sklid = string(tbl.Data{row, 6});
        
        % Update FSIT_Act, ID, and Map Number based on SKL_ID
        if ~isempty(strtrim(char(sklid))) && ~strcmp(sklid, '')
            [fsit, ukID, mapNumber] = lookupSKLIDInfo(mainFig, sklid);
            tbl.Data{row, 7} = fsit;        % FSIT_Act column
            tbl.Data{row, 8} = ukID;        % ID column
            tbl.Data{row, 9} = mapNumber;   % Map Number column
            appData.gbfssactData = tbl.Data;
        end
    end
    
    % Apply color coding after any edit
    applyGBFSSactColors(mainFig, tbl);
    
    mainFig.UserData = appData;
end

function [fsit, ukID, mapNumber] = lookupSKLIDInfo(mainFig, sklid)
% Lookup FSIT_Act, ID, and Map Number for a given SKL_ID from ukData.
% Uses cached appData.activeAbbrevs (computed once on CSV load / FSIT save) — fast.
    appData = mainFig.UserData;
    fsit = ''; ukID = ''; mapNumber = '';

    if ~isfield(appData, 'ukData') || isempty(appData.ukData), return; end

    % Use pre-computed activeAbbrevs cache (avoids re-scanning T on every call)
    if isfield(appData, 'activeAbbrevs') && ~isempty(appData.activeAbbrevs)
        activeAbbrevs = appData.activeAbbrevs;
    else
        activeAbbrevs = computeActiveAbbrevs(appData.T);
    end

    origUK = appData.ukData;
    sklidStr = string(sklid);
    nCols = size(origUK, 2);
    for i = 1:size(origUK, 1)
        if strcmpi(string(origUK{i, 4}), sklidStr)
            ukID     = num2str(origUK{i, 3});
            if nCols >= 8, mapNumber = char(origUK{i, 8}); else, mapNumber = ''; end
            abbrev   = origUK{i, 2};
            match = false;
            for j = 1:length(activeAbbrevs)
                tk = activeAbbrevs{j};
                if ~isempty(tk) && contains(abbrev, tk, 'IgnoreCase', true)
                    match = true; break;
                end
            end
            if match, fsit = 'Yes'; else, fsit = 'No'; end
            return;
        end
    end
end

function onGBFSSactSelect(tbl, event)
    % Handle selection (optional - for future enhancements)
end

function saveGBFSSactData(mainFig, gbfFig)
    % Save GBF_SSact data to main appData
    appData = mainFig.UserData;
    h = gbfFig.UserData;
    
    appData.gbfssactData = h.tGBF.Data;
    mainFig.UserData = appData;
    logAction(mainFig, 'GBF_SSact Save', sprintf('%d rows', size(h.tGBF.Data,1)));
    uialert(gbfFig, 'GBF_SSact data saved to memory.', 'Success', 'Icon', 'success');
end

function applyGBFSSactColors(mainFig, tGBF)
    data = tGBF.Data;
    nRows = size(data, 1);
    if nRows == 0, return; end

    try; removeStyle(tGBF); catch; end

    appData = mainFig.UserData;
    statMatrix = [];
    if isfield(appData, 'statTabul'), statMatrix = appData.statTabul; end

    % Vectorised row collection — pre-allocate then trim
    fsitMask   = false(nRows,1);
    greenMask  = false(nRows,1);
    yellowMask = false(nRows,1);
    for i = 1:nRows
        try
            if size(data,2) >= 7 && strcmp(char(data{i,7}), 'Yes'), fsitMask(i) = true; end
            if size(data,2) >= 8
                id = str2double(char(data{i,8}));
                if ~isnan(id)
                    if ~isempty(statMatrix) && ismember(id, statMatrix)
                        greenMask(i)  = true;
                    else
                        yellowMask(i) = true;
                    end
                end
            end
        catch; end
    end

    fsitRows   = find(fsitMask);
    greenRows  = find(greenMask);
    yellowRows = find(yellowMask);

    persistent gbfBlue_ gbfGreen_;
    if isempty(gbfBlue_)
        gbfBlue_  = uistyle('BackgroundColor',[0.4 0.6 1],'FontColor','black','FontWeight','bold');
        gbfGreen_ = uistyle('BackgroundColor',[0.8 1 0.8]);
    end
    if ~isempty(fsitRows),   addStyle(tGBF, gbfBlue_,           'cell', [fsitRows,  repmat(7,numel(fsitRows),1)]); end
    if ~isempty(greenRows),  addStyle(tGBF, gbfGreen_,          'cell', [greenRows,  repmat(8,numel(greenRows),1)]); end
    if ~isempty(yellowRows), addStyle(tGBF, getSoftYellowStyle(),'cell', [yellowRows, repmat(8,numel(yellowRows),1)]); end
end

function refreshGBFSSactFromUK(mainFig, gbfFig)
    % Refresh all SKL_ID entries from UK & STAT Table
    h = gbfFig.UserData;
    tGBF = h.tGBF;
    data = tGBF.Data;
    
    % Update each row that has a SKL_ID
    for i = 1:size(data, 1)
        if size(data,2) < 6, continue; end
        sklid = char(data{i, 6});  % Column 6 = SKL_ID
        if ~isempty(sklid) && ~strcmp(sklid, '')
            [fsit, ukID, mapNumber] = lookupSKLIDInfo(mainFig, sklid);
            if ~isempty(fsit)
                data{i, 7} = fsit;        % Update FSIT_Act
                data{i, 8} = ukID;        % Update ID
                data{i, 9} = mapNumber;   % Update Map Number
            end
        end
    end
    
    % Update table
    tGBF.Data = data;
    
    % Reapply colors
    applyGBFSSactColors(mainFig, tGBF);
    
    % Save to appData
    appData = mainFig.UserData;
    appData.gbfssactData = data;
    mainFig.UserData = appData;
    
    uialert(gbfFig, 'All SKL_IDs refreshed from UK & STAT Table!', 'Success', 'Icon', 'success');
end

function updateGBFSSactFromDriveMode(mainFig, selectedMode)
    % Update GBF_SSact table when drive mode is selected
    appData = mainFig.UserData;
    
    % Check if GBF_SSact window is open
    if ~isfield(appData, 'gbfssactFig') || ~hasValidHandle(appData, 'gbfssactFig')
        return;  % Window not open, nothing to do
    end
    
    % Get GBF_SSact table
    gbfFig = appData.gbfssactFig;
    h = gbfFig.UserData;
    if ~isfield(h, 'tGBF') || isempty(h.tGBF)
        return;
    end
    
    tGBF = h.tGBF;
    data = tGBF.Data;
    
    % Determine if special mode or SKLID mode
    if contains(selectedMode, 'Auto') || contains(selectedMode, 'Sport') || contains(selectedMode, 'Track')
        % Special mode - find matching row by Shifting Situation
        targetSituation = '';
        if contains(selectedMode, 'Auto')
            targetSituation = 'Auto';
        elseif contains(selectedMode, 'Sport')
            targetSituation = 'Sports';
        elseif contains(selectedMode, 'Track')
            targetSituation = 'Track';
        end
        
        % Find and refresh that row
        for i = 1:size(data, 1)
            situation = char(data{i, 2});  % Column 2 = Shifting Situation
            if strcmp(situation, targetSituation)
                % Row found - data already in table, just refresh colors
                applyGBFSSactColors(mainFig, tGBF);
                return;
            end
        end
    else
        % SKLID mode - find matching row and update it
        for i = 1:size(data, 1)
            if size(data,2) < 6, continue; end
            sklid = char(data{i, 6});  % Column 6 = SKL_ID
            if strcmpi(sklid, selectedMode)
                % Found matching row - update FSIT_Act, ID, Map Number
                [fsit, ukID, mapNumber] = lookupSKLIDInfo(mainFig, selectedMode);
                if ~isempty(fsit)
                    data{i, 7} = fsit;        % FSIT_Act
                    data{i, 8} = ukID;        % ID
                    data{i, 9} = mapNumber;   % Map Number
                    tGBF.Data = data;
                    
                    % Save to appData
                    appData.gbfssactData = data;
                    mainFig.UserData = appData;
                    
                    % Apply colors
                    applyGBFSSactColors(mainFig, tGBF);
                end
                return;
            end
        end
    end
end

function shiftingSituations = getShiftingSituationsFromGBFSSact(mainFig)
    % Get list of Shifting Situations from GBF_SSact table for Drive Mode dropdown
    shiftingSituations = {};
    
    appData = mainFig.UserData;
    
    % Check if GBF_SSact data exists
    if ~isfield(appData, 'gbfssactData') || isempty(appData.gbfssactData)
        return;  % Return empty if no data
    end
    
    data = appData.gbfssactData;
    
    % Extract Shifting Situation column (column 2)
    for i = 1:size(data, 1)
        situation = char(data{i, 2});  % Column 2 = Shifting Situation
        
        % Skip empty rows
        if isempty(situation) || strcmp(strtrim(situation), '')
            continue;
        end
        
        % Add to list if not already there
        if ~ismember(situation, shiftingSituations)
            shiftingSituations{end+1} = situation;
        end
    end
end

function sklid = getSKLIDFromShiftingSituation(mainFig, shiftingSituation)
    % Get SKL_ID corresponding to a Shifting Situation from GBF_SSact table
    sklid = '';
    
    appData = mainFig.UserData;
    
    % Check if GBF_SSact data exists
    if ~isfield(appData, 'gbfssactData') || isempty(appData.gbfssactData)
        return;
    end
    
    data = appData.gbfssactData;
    
    % Search for matching Shifting Situation
    for i = 1:size(data, 1)
        if size(data,2) < 6, continue; end
        situation = char(data{i, 2});  % Column 2 = Shifting Situation
        currentSKLID = char(data{i, 6});  % Column 6 = SKL_ID
        
        % If Shifting Situation matches and has a SKL_ID
        if strcmp(situation, shiftingSituation) && ~isempty(strtrim(currentSKLID))
            sklid = currentSKLID;
            return;
        end
    end
end

function closeGBFSSact(mainFig, gbfFig)
    if ~isempty(mainFig) && isvalid(mainFig)
        try
            appData = mainFig.UserData;
            appData.gbfssactFig = gobjects(0);
            mainFig.UserData = appData;
        catch; end
    end
    if ~isempty(gbfFig) && isvalid(gbfFig), delete(gbfFig); end
end


function exportHandler(fig)
    % Step 1: Choose category (uiconfirm max = 4 options)
    step1 = uiconfirm(fig, 'Choose export category:', 'Export', ...
        'Options', {'Shift Maps (Excel/DCM)', 'Dyno Export', 'Cancel'}, ...
        'DefaultOption', 1, 'CancelOption', 3);

    switch step1
        case 'Cancel'
            return;

        case 'Dyno Export'
            exportDyno(fig);

        case 'Shift Maps (Excel/DCM)'
            % Step 2: Excel / DCM / Both
            step2 = uiconfirm(fig, 'Export shift maps as:', 'Shift Maps Export', ...
                'Options', {'Excel Sheet', 'DCM', 'Both', 'Cancel'}, ...
                'DefaultOption', 1, 'CancelOption', 4);
            switch step2
                case 'Excel Sheet'
                    exportModifiedMaps(fig);
                case 'DCM'
                    exportAllDCM(fig);
                case 'Both'
                    exportModifiedMaps(fig);
                    exportAllDCM(fig);
            end
    end
end

function configureMCRSpeedup(fig)
% Set MCR_CACHE_ROOT for faster deployed-app startup.
% Runs silently if already configured. Only prompts on first run.
    if ~isdeployed || ~ispc, return; end

    envVar   = 'MCR_CACHE_ROOT';
    try
        cachePath = fullfile(tempdir, 'MCR_Cache_PatternPlotter');
    catch
        cachePath = fullfile(getenv('TEMP'), 'MCR_Cache_PatternPlotter');
    end

    % Already set — nothing to do, skip the dialog entirely
    if ~isempty(getenv(envVar)), return; end
    % Try to apply silently first (no prompt) — works if process has rights
    applied = false;
    try
        if ~exist(cachePath,'dir'), mkdir(cachePath); end
        setenv(envVar, cachePath);           % sets for this process immediately
        [s,~] = system(sprintf('setx %s "%s"', envVar, cachePath)); % persist
        applied = (s == 0);
    catch; end

    if ~applied
        % Silent attempt failed — inform user once, non-blocking
        uialert(fig, ...
            sprintf('MCR cache not configured. For faster startup, set:\n  %s = %s\n(Windows System Properties > Environment Variables)', ...
                    envVar, cachePath), ...
            'Startup Tip', 'Icon', 'info');
    end
end

%% === HELPER FUNCTIONS (MOVED FROM NESTED) ===
function [axleRatio, totalRatio] = extractAxleMapParam(T, keyword)
% Extract axle ratio and total ratio from a MAP block like FZGG_AxleRatMpgToldx.
% Structure: keyword row → format comment → MAP → empty → axis row → data row1 → data row2
% Returns: axleRatio = first numeric data row value, totalRatio = second row value
    axleRatio = NaN; totalRatio = NaN;
    idx = find(contains(T.Var2, keyword, 'IgnoreCase', true), 1);
    if isempty(idx), idx = find(contains(T.Var1, keyword, 'IgnoreCase', true), 1); end
    if isempty(idx), return; end

    dataRows = [];
    for r = idx+1 : min(idx+25, height(T))
        rowRaw = string(table2cell(T(r, 3:min(10,width(T)))));
        nums = str2double(rowRaw);
        validNums = nums(~isnan(nums));
        % Skip axis rows that contain only 1s (e.g. 1,1,1 for "[-]" header)
        if isempty(validNums), continue; end
        if all(validNums == 1) && numel(validNums) >= 2, continue; end
        % Skip very small values (e.g. indices 0,1,2)
        if all(validNums <= 1) && numel(validNums) <= 2, continue; end
        dataRows(end+1) = median(validNums(validNums > 0.5)); %#ok<AGROW>
        if numel(dataRows) >= 2, break; end
    end

    if ~isempty(dataRows),   axleRatio  = dataRows(1); end
    if numel(dataRows) >= 2, totalRatio = dataRows(2); end
end

function val = extractSingleParam(T, keyword, type)
    if nargin < 3, type = 'block'; end % 'block' (default) or 'scalar'
    val = NaN;
    idx = find(contains(T.Var2, keyword, 'IgnoreCase', true), 1);
    if isempty(idx) && width(T) >= 1
        idx = find(contains(T.Var1, keyword, 'IgnoreCase', true), 1);
    end
    if isempty(idx), return; end
    
    rStart = 0;
    for r = idx+1 : min(idx+20, height(T))
        if width(T) >= 5
            vals = str2double(string(table2cell(T(r, 2:5))));
        else
            vals = str2double(string(table2cell(T(r, :))));
        end
        if sum(~isnan(vals)) >= 1, rStart = r; break; end
    end
    
    if rStart > 0
        if strcmp(type, 'scalar')
            rEnd = min(rStart, height(T)); 
            chunk = str2double(string(table2cell(T(rStart:rEnd, :))));
            validNums = chunk(~isnan(chunk));
            if ~isempty(validNums), val = validNums(1); end
        else
            rEnd = min(rStart + 2, height(T));
            chunk = str2double(string(table2cell(T(rStart:rEnd, :))));
            if size(chunk, 1) >= 2
                row2 = chunk(2, :);
                validCols = find(~isnan(row2));
                if ~isempty(validCols), val = row2(validCols(1)); end
            elseif size(chunk, 1) == 1
                validNums = chunk(~isnan(chunk));
                if ~isempty(validNums), val = validNums(1); end
            end
        end
    end
end

function str = fmtParam(label, oldVal, newVal, fmt)
    if abs(oldVal - newVal) > 0.001
        valStr = sprintf(fmt, newVal);
        oldStr = sprintf(fmt, oldVal);
        str = sprintf('<b>%s:</b> <font color="red">%s</font> (User: %s)', label, valStr, oldStr);
    else
        valStr = sprintf(fmt, newVal);
        str = sprintf('<b>%s:</b> %s', label, valStr);
    end
end

function setSelection(fig, val)
    fig.UserData = val;
    uiresume(fig);
end
    
function legendItems = renderMapOnAxes(fig, ax, isInteractive)
    appData = fig.UserData; h = appData.handles;
    
    % --- CLEANUP: delete all children except permanent crosshair in one call ---
    ch = ax.Children;
    if ~isempty(ch)
        keep = arrayfun(@(c) isprop(c,'Tag') && strcmp(c.Tag,'permCrosshair'), ch);
        delete(ch(~keep));
    end
    hold(ax, 'on');
    
    % --- GET UI STATE ---
    showA = h.cb1.Value; mapA_Name = h.dd1.Value;
    showB = h.cb2.Value; mapB_Name = h.dd2.Value;
    showC = isfield(h,'cb3') && isvalid(h.cb3) && h.cb3.Value;
    if isfield(h,'dd3') && isvalid(h.dd3), mapC_Name = h.dd3.Value; else, mapC_Name = ""; end
    isEdit = h.cbEdit.Value; showLines = h.cbLines.Value; showTCC = h.cbTCC.Value;
    % Session mode: always edit Map A regardless of cbEdit checkbox
    if isfield(h,'cbHoldSave') && isvalid(h.cbHoldSave) && h.cbHoldSave.Value ...
            && isfield(appData,'holdSession') && isstruct(appData.holdSession)
        isEdit = true;
    end
    
    % --- GEAR CHECKBOXES: read all 14 values via flat list — avoids Map key type mismatch ---
    visibleUp   = false(1,7);
    visibleDown = false(1,7);
    if isfield(h,'gearChecksList') && numel(h.gearChecksList) >= 14
        for i = 1:7
            try, visibleUp(i)   = h.gearChecksList{2*i-1}.Value; catch, visibleUp(i)   = true; end
            try, visibleDown(i) = h.gearChecksList{2*i  }.Value; catch, visibleDown(i) = true; end
        end
    else  % fallback for legacy handles without flat list
        gearKeys = {'12','21','23','32','34','43','45','54','56','65','67','76','78','87'};
        for i = 1:7
            try, visibleUp(i)   = h.gearChecks(gearKeys{2*i-1}).Value; catch, visibleUp(i)   = true; end
            try, visibleDown(i) = h.gearChecks(gearKeys{2*i  }).Value; catch, visibleDown(i) = true; end
        end
    end

    shiftColors = [1 0 0; 0 0 1; 1 0 1; 0 0.6 0.5; 0.5 0 1; 0.4 0 0; 0.6 0.6 0.6];
    legendItems = struct('text', {}, 'color', {}, 'style', {}, 'marker', {});
    nLI = 0;  % counter avoids repeated end+1 struct array growth
    
    % --- TCC CONFIGURATION (constants, defined once) ---
    tccGearColors = [0 0 0; 1 0 0; 0 0 1; 1 0 1; 0 0.7 0.7; 0.5 0 0.8; 0.6 0 0; 0.6 0.6 0.6];
    tccModeStyles = {'--', '-.', '-', '-'};
    tccModeMarkers = {'none', 'none', 'none', '.'};
    tccLineWidths = [1, 1, 1, 1.5];
    tccSuffixes = ["_RO", "_OR", "_RC", "_COC"];
    
    % Use cached map name list — avoids cellfun on every render
    allNames = getMapNames(appData);

    % --- PLOT SHIFT LINES ---
    for kIdx = 1:3
        if kIdx == 1,     k="A"; currentMapName = mapA_Name; show=showA;
        elseif kIdx == 2, k="B"; currentMapName = mapB_Name; show=showB;
        else,             k="C"; currentMapName = mapC_Name; show=showC; end
        if ~show, continue; end

        idx = find(allNames == currentMapName, 1);
        if isempty(idx), continue; end

        % Choose map data source:
        % - Map A in session/edit mode → workingCopy (has all edits)
        % - Map B/C in session mode    → session slot (has their edits too)
        % - Otherwise                  → allMaps (original)
        sessionActiveR = isfield(h,'cbHoldSave') && isvalid(h.cbHoldSave) && h.cbHoldSave.Value ...
                       && isfield(appData,'holdSession') && isstruct(appData.holdSession);
        if k=="A" && isEdit && ~isempty(appData.workingCopy)
            map = appData.workingCopy;
        elseif sessionActiveR && (k=="B" || k=="C")
            slotWC = appData.holdSession.slots.(char(k));
            if ~isempty(slotWC)
                map = slotWC;
            else
                map = appData.allMaps{idx};
            end
        else
            map = appData.allMaps{idx};
        end
        pedal = map.pedal;
        if k=="A", lsUp = '-'; elseif k=="B", lsUp = ':'; else, lsUp = '-.'; end
        if k=="A", lsDn = '--'; elseif k=="B", lsDn = '-.'; else, lsDn = ':'; end
        showMarkers = (k=="A" && showA) || (k=="B" && showB) || (k=="C" && showC);

        for i = 1:7
            c = shiftColors(i, :);
            if showLines
                if visibleUp(i)
                    plot(ax, map.Z_up(:,i), pedal, lsUp, 'Color', c, 'LineWidth', 1.5, ...
                        'PickableParts','none','HitTest','off');
                    nLI = nLI + 1; legendItems(nLI) = struct('text', sprintf('Map %s: %d-%d Up', k, i, i+1), ...
                        'color', c, 'style', lsUp, 'marker', 'none');
                end
                if visibleDown(i)
                    plot(ax, map.Z_down(:,i), pedal, lsDn, 'Color', c, 'LineWidth', 1.2, ...
                        'PickableParts','none','HitTest','off');
                    nLI = nLI + 1; legendItems(nLI) = struct('text', sprintf('Map %s: %d-%d Dn', k, i+1, i), ...
                        'color', c, 'style', lsDn, 'marker', 'none');
                end
            end
            
            % Markers — use plot() not scatter() for much faster rendering
            if isInteractive && k=="A" && isEdit
                if visibleUp(i),   createDragDot(ax, map.Z_up(:,i),   pedal, i, true,  c); end
                if visibleDown(i), createDragDot(ax, map.Z_down(:,i), pedal, i, false, c); end
            elseif showMarkers
                if visibleUp(i)
                    plot(ax, map.Z_up(:,i), pedal, 'x', 'Color', c, 'MarkerSize', 6, ...
                        'LineStyle','none','PickableParts','none','HitTest','off');
                end
                if visibleDown(i)
                    plot(ax, map.Z_down(:,i), pedal, '^', 'Color', c, 'MarkerSize', 5, ...
                        'MarkerFaceColor', c, 'LineStyle','none','PickableParts','none','HitTest','off');
                end
            end
        end

        % --- TCC PLOTTING LOGIC ---
        if showTCC && ~isempty(appData.wtZustand) && ~isempty(appData.kwkData)
            mapNumStr = regexp(currentMapName, 'SKL_GKF_(\d+)', 'tokens');
            if ~isempty(mapNumStr)
                activeMapID = str2double(mapNumStr{1}{1});
                stateIdx = find(appData.wtZustand(1,:) == activeMapID, 1);
                if ~isempty(stateIdx)
                    stateVal = appData.wtZustand(2, stateIdx);
                    kwkRowIdx = stateVal + 1;
                    if kwkRowIdx >= 1 && kwkRowIdx <= size(appData.kwkData, 1)
                        rowIDs = appData.kwkData(kwkRowIdx, :);
                        if kIdx == 3, break; end  % Map C is reference only — no TCC overlay
                        for g = 1:8
                            % tccChecksList: {A_G1,B_G1,A_G2,B_G2,...} — use flat list to avoid Map key mismatch
                            tccVisible = true;
                            if isfield(h,'tccChecksList') && numel(h.tccChecksList) >= 2*g
                                if kIdx == 1, tccVisible = h.tccChecksList{2*g-1}.Value;
                                else,         tccVisible = h.tccChecksList{2*g  }.Value; end
                            elseif kIdx == 1 && isfield(h,'tccChecksA')
                                try, tccVisible = h.tccChecksA(num2str(g)).Value; catch; end
                            elseif isfield(h,'tccChecksB')
                                try, tccVisible = h.tccChecksB(num2str(g)).Value; catch; end
                            end
                            if ~tccVisible, continue; end
                            if g > length(rowIDs), break; end
                            idVal = rowIDs(g); if idVal == 0, continue; end
                            for type = 1:4
                                suffix = tccSuffixes(type); searchStr = string(idVal) + suffix;
                                for m = 1:length(appData.nwkMaps)
                                    thisMap = appData.nwkMaps(m); headers = string(thisMap.headers);
                                    matchIdx = find(contains(headers, searchStr, 'IgnoreCase',true), 1);
                                    if ~isempty(matchIdx)
                                        xData = thisMap.data(:, matchIdx); yData = thisMap.yAxis; len = min(length(xData), length(yData));
                                        plot(ax, xData(1:len), yData(1:len), tccModeStyles{type}, 'Color', tccGearColors(g, :), 'LineWidth', tccLineWidths(type), 'Marker', tccModeMarkers{type}, 'MarkerSize', 12, 'MarkerFaceColor', tccGearColors(g, :), 'PickableParts','none','HitTest','off');
                                        modeNames = {'RO', 'OR', 'RC', 'COC'};
                                        nLI = nLI + 1; legendItems(nLI) = struct('text', sprintf('Map %s TCC G%d %s', k, g, modeNames{type}), 'color', tccGearColors(g, :), 'style', tccModeStyles{type}, 'marker', tccModeMarkers{type});
                                        break; 
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

%% === CALLBACK FUNCTIONS FOR UK TABLE NEW TABS ===

% Gear Ratio Tab Callbacks
function onGearRatioEditUK(ukFig, src, e)
    if isempty(e.Indices), return; end
    addStyle(src, getYellowStyle(), 'cell', e.Indices);
    h = ukFig.UserData; h.ukDirty = true; ukFig.UserData = h;
end

function onGearRatioSelect(ukFig, e)
    h = ukFig.UserData;
    h.gearRatioSelection = e.Indices;
    ukFig.UserData = h;
end

function onGearRatioPasteUK(ukFig, ~, ~)
    h = ukFig.UserData;
    addStyle(h.tGearRatio, getYellowStyle(), 'cell', h.gearRatioSelection);
end

function applyGearRatioMath(ukFig, ~, op)
    h = ukFig.UserData;
    tGR = h.tGearRatio;
    sel = h.gearRatioSelection;
    if isempty(sel), uialert(ukFig, 'Select cells first.', 'Error'); return; end
    
    % Only allow editing column 2 (Value column)
    sel = sel(sel(:,2) == 2, :);
    if isempty(sel), uialert(ukFig, 'Select Value cells (column 2) for math operations.', 'Error'); return; end

    prompt = ""; def = "0";
    switch op
        case 'add', prompt = "Add Value:";
        case 'mult', prompt = "Multiply by:"; def="1";
        case 'div', prompt = "Divide by:"; def="1";
        case 'percent', prompt = "Percentage change (%):"; def="0";
    end
    answer = inputdlg(prompt, 'Math', [1 40], {char(def)});
    if isempty(answer), return; end
    val = str2double(answer{1});
    if isnan(val), return; end

    data = tGR.Data;
    for i = 1:size(sel, 1)
        r = sel(i,1); c = sel(i,2);
        curr = data{r,c};
        if isempty(curr) || (isnumeric(curr) && isnan(curr)), continue; end
        if ~isnumeric(curr), curr = str2double(curr); end
        switch op
            case 'add', curr = curr + val;
            case 'mult', curr = curr * val;
            case 'div', if val~=0, curr = curr / val; end
            case 'percent', curr = curr * (1 + val/100);
        end
        data{r,c} = curr;
    end
    tGR.Data = data;
    addStyle(tGR, getYellowStyle(), 'cell', sel);
end

function saveGearRatioDataUK(ukFig, fig)
    h = ukFig.UserData;
    appData = fig.UserData;
    
    % Get the edited data from table
    tblData = h.tGearRatio.Data;
    
    % Update userInputs based on table values
    if isfield(appData, 'userInputs')
        for i = 1:size(tblData, 1)
            paramName = tblData{i, 1};
            paramVal = tblData{i, 2};
            
            if contains(paramName, 'Gear') && contains(paramName, 'Ratio') && ~contains(paramName, 'Axle') && ~contains(paramName, 'Low')
                % Extract gear number
                gearNum = regexp(paramName, 'Gear (\d+)', 'tokens', 'once');
                if ~isempty(gearNum)
                    gIdx = str2double(gearNum{1}{1});
                    if gIdx >= 1 && gIdx <= length(appData.userInputs.GearRatios)
                        appData.userInputs.GearRatios(gIdx) = paramVal;
                    end
                end
            elseif strcmp(paramName, 'Axle Ratio')
                appData.userInputs.AxleRatio = paramVal;
            elseif strcmp(paramName, 'Tire Radius')
                appData.userInputs.DynamicCircumference = paramVal;
            elseif strcmp(paramName, 'Tire Circumference')
                appData.userInputs.TireCircumference = paramVal;
            elseif strcmp(paramName, 'Low Range Ratio')
                appData.userInputs.LowRangeRatio = paramVal;
            elseif strcmp(paramName, 'Idle RPM')
                appData.userInputs.IdleRPM = paramVal;
            elseif strcmp(paramName, 'Max RPM')
                appData.userInputs.MaxRPM = paramVal;
            end
        end
        fig.UserData = appData;
    end
    
    removeStyle(h.tGearRatio);
    h.ukDirty = false; ukFig.UserData = h;
    logAction(ukFig, 'Gear Ratio Save', 'Vehicle parameters updated');
    uialert(ukFig, 'Gear ratio values saved to memory.', 'Saved', 'Icon', 'success');
end

function refreshGearRatioDataUK(ukFig, fig)
    h = ukFig.UserData;
    gearData = getGearRatioDataFromUserInputs(fig);
    if isempty(gearData)
        gearData = {'No Data', 0, '-', 'Load CSV to populate'};
    end
    h.tGearRatio.Data = gearData;
    removeStyle(h.tGearRatio);
end

% GBF_TABSS Tab Callbacks
function onGBFEdit(ukFig, src, e)
    if isempty(e.Indices), return; end
    h = ukFig.UserData;
    h.gbfSelection = e.Indices;
    h.ukDirty = true;
    ukFig.UserData = h;
    addStyle(src, getYellowStyle(), 'cell', e.Indices);
end

function onGBFSelect(ukFig, e)
    h = ukFig.UserData;
    h.gbfSelection = e.Indices;
    ukFig.UserData = h;
end

function applyGBFMath(ukFig, ~, op)
    h = ukFig.UserData;
    tGBF = h.tGBFTabss;
    sel = h.gbfSelection;
    if isempty(sel), uialert(ukFig, 'Select cells first.', 'Error'); return; end

    prompt = ""; def = "0";
    switch op
        case 'add', prompt = "Add Value:";
        case 'mult', prompt = "Multiply by:"; def="1";
        case 'div', prompt = "Divide by:"; def="1";
        case 'percent', prompt = "Percentage change (%):"; def="0";
    end
    answer = inputdlg(prompt, 'Math', [1 40], {char(def)});
    if isempty(answer), return; end
    val = str2double(answer{1});
    if isnan(val), return; end

    data = tGBF.Data;
    for i = 1:size(sel, 1)
        r = sel(i,1); c = sel(i,2);
        curr = data{r,c};
        if isempty(curr) || (isnumeric(curr) && isnan(curr)), continue; end
        if ~isnumeric(curr), curr = str2double(curr); end
        switch op
            case 'add', curr = curr + val;
            case 'mult', curr = curr * val;
            case 'div', if val~=0, curr = curr / val; end
            case 'percent', curr = curr * (1 + val/100);
        end
        data{r,c} = curr;
    end
    tGBF.Data = data;
    addStyle(tGBF, getYellowStyle(), 'cell', sel);
end

function onGBFPaste(ukFig, ~, ~)
    h = ukFig.UserData;
    addStyle(h.tGBFTabss, getYellowStyle(), 'cell', h.gbfSelection);
end

function saveGBFChanges(ukFig, ~)
    if strcmp(uiconfirm(ukFig, 'Save GBF_TABSS changes to memory?', 'Save', 'Options', {'Yes','Cancel'}), 'Cancel'), return; end
    h = ukFig.UserData;
    removeStyle(h.tGBFTabss);
    h.ukDirty = false; ukFig.UserData = h;
    logAction(ukFig, 'GBF Save', 'GBF_TABSS');
    uialert(ukFig, 'GBF_TABSS Saved to Memory.', 'Success');
end

% UKKE_FacEngSpdMax Tab Callbacks
function onFacEngSpdEdit(ukFig, src, e)
    if isempty(e.Indices), return; end
    h = ukFig.UserData;
    h.facEngSpdSelection = e.Indices;
    h.ukDirty = true;
    ukFig.UserData = h;
    addStyle(src, getYellowStyle(), 'cell', e.Indices);
end

function onFacEngSpdSelect(ukFig, e)
    h = ukFig.UserData;
    h.facEngSpdSelection = e.Indices;
    ukFig.UserData = h;
end

function applyFacEngSpdMath(ukFig, ~, op)
    h = ukFig.UserData;
    tFac = h.tFacEngSpd;
    sel = h.facEngSpdSelection;
    if isempty(sel), uialert(ukFig, 'Select cells first.', 'Error'); return; end

    prompt = ""; def = "0";
    switch op
        case 'add', prompt = "Add Value:";
        case 'mult', prompt = "Multiply by:"; def="1";
        case 'div', prompt = "Divide by:"; def="1";
        case 'percent', prompt = "Percentage change (%):"; def="0";
    end
    answer = inputdlg(prompt, 'Math', [1 40], {char(def)});
    if isempty(answer), return; end
    val = str2double(answer{1});
    if isnan(val), return; end

    data = tFac.Data;
    for i = 1:size(sel, 1)
        r = sel(i,1); c = sel(i,2);
        curr = data{r,c};
        if isempty(curr) || (isnumeric(curr) && isnan(curr)), continue; end
        if ~isnumeric(curr), curr = str2double(curr); end
        switch op
            case 'add', curr = curr + val;
            case 'mult', curr = curr * val;
            case 'div', if val~=0, curr = curr / val; end
            case 'percent', curr = curr * (1 + val/100);
        end
        data{r,c} = curr;
    end
    tFac.Data = data;
    addStyle(tFac, getYellowStyle(), 'cell', sel);
end

function onFacEngSpdPaste(ukFig, ~, ~)
    h = ukFig.UserData;
    addStyle(h.tFacEngSpd, getYellowStyle(), 'cell', h.facEngSpdSelection);
end

% UKKE_NMAX Tab Callbacks
function onNmaxEdit(ukFig, src, e)
    if isempty(e.Indices), return; end
    h = ukFig.UserData;
    h.nmaxSelection = e.Indices;
    h.ukDirty = true;
    ukFig.UserData = h;
    addStyle(src, getYellowStyle(), 'cell', e.Indices);
end

function onNmaxSelect(ukFig, e)
    h = ukFig.UserData;
    h.nmaxSelection = e.Indices;
    ukFig.UserData = h;
end

function applyNmaxMath(ukFig, ~, op)
    h = ukFig.UserData;
    tNmax = h.tNmax;
    sel = h.nmaxSelection;
    if isempty(sel), uialert(ukFig, 'Select cells first.', 'Error'); return; end

    prompt = ""; def = "0";
    switch op
        case 'add', prompt = "Add Value:";
        case 'mult', prompt = "Multiply by:"; def="1";
        case 'div', prompt = "Divide by:"; def="1";
        case 'percent', prompt = "Percentage change (%):"; def="0";
    end
    answer = inputdlg(prompt, 'Math', [1 40], {char(def)});
    if isempty(answer), return; end
    val = str2double(answer{1});
    if isnan(val), return; end

    data = tNmax.Data;
    for i = 1:size(sel, 1)
        r = sel(i,1); c = sel(i,2);
        curr = data{r,c};
        if isempty(curr) || (isnumeric(curr) && isnan(curr)), continue; end
        if ~isnumeric(curr), curr = str2double(curr); end
        switch op
            case 'add', curr = curr + val;
            case 'mult', curr = curr * val;
            case 'div', if val~=0, curr = curr / val; end
            case 'percent', curr = curr * (1 + val/100);
        end
        data{r,c} = curr;
    end
    tNmax.Data = data;
    addStyle(tNmax, getYellowStyle(), 'cell', sel);
end

function onNmaxPaste(ukFig, ~, ~)
    h = ukFig.UserData;
    addStyle(h.tNmax, getYellowStyle(), 'cell', h.nmaxSelection);
end

function saveCurveEngSpdChanges(ukFig, mainFig)
    if strcmp(uiconfirm(ukFig, 'Save Curve Eng Spd changes to memory?', 'Save', 'Options', {'Yes','Cancel'}), 'Cancel'), return; end
    h = ukFig.UserData;

    % Write FacEngSpd MAP data back to appData.T
    try
        ad = mainFig.UserData; T = ad.T;
        facVI = h.facVI;
        if isstruct(facVI) && isfield(facVI,'dRowStart') && facVI.dRowStart > 0
            d = h.tFacEngSpd.Data;
            [nr, nc] = size(d);
            for dr = 1:nr
                tr = facVI.dRowStart + dr - 1;
                if tr <= height(T)
                    for dc = 1:nc
                        val = d{dr, dc};
                        if isnumeric(val), T{tr, 2+dc} = {val}; end
                    end
                end
            end
        end
        % Write Nmax CURVE data back to appData.T
        nmaxVI = h.nmaxVI;
        if isstruct(nmaxVI) && isfield(nmaxVI,'dRowStart') && nmaxVI.dRowStart > 0
            d = h.tNmax.Data;
            nc = size(d, 2);
            tr = nmaxVI.dRowStart;
            if tr <= height(T) && size(d,1) >= 2
                for dc = 1:nc
                    val = d{2, dc};   % row 2 = values, row 1 = x-axis
                    if isnumeric(val), T{tr, 2+dc} = {val}; end
                end
            end
        end
        ad.T = T;
        mainFig.UserData = ad;
    catch; end

    removeStyle(h.tFacEngSpd);
    removeStyle(h.tNmax);
    h.ukDirty = false; ukFig.UserData = h;
    logAction(ukFig, 'Curve Eng Spd Save', 'FacEngSpd + Nmax');
    uialert(ukFig, 'Curve Eng Spd Data Saved to Memory.', 'Success');
end

function buildSiODTab(mainFig, interpFig, tab, interpData, varNames)
% V7.6.3 rewrite — uigridlayout with auto-managed scrolling.
% Each variable gets a panel split 50/50 between KPH (left) and MPH (right) tables.

    nv = length(varNames);
    if nv == 0, return; end

    rowHeights = cell(1, nv);
    for i = 1:nv
        sn = matlab.lang.makeValidName(varNames{i});
        if isfield(interpData, sn) && ~isempty(interpData.(sn))
            vi = interpData.(sn);
            switch vi.type
                case 'VALUE'
                    rowHeights{i} = 75;
                case 'MAP'
                    nr = size(vi.data, 1);
                    rowHeights{i} = 70 + (nr + 1) * 27 + 28;
                case 'CURVE'
                    rowHeights{i} = 145;
                otherwise
                    rowHeights{i} = 120;
            end
        else
            rowHeights{i} = 70;
        end
    end

    g = uigridlayout(tab, [nv, 1]);
    g.RowHeight   = rowHeights;
    g.ColumnWidth = {'1x'};
    g.Padding     = [8 8 8 8];
    g.RowSpacing  = 6;
    g.Scrollable  = 'on';

    for i = 1:nv
        vn = varNames{i};
        sn = matlab.lang.makeValidName(vn);

        pnl = uipanel(g, 'Title', vn, 'FontWeight', 'bold', 'FontSize', 11);
        pnl.Layout.Row    = i;
        pnl.Layout.Column = 1;

        if ~isfield(interpData, sn) || isempty(interpData.(sn))
            ig = uigridlayout(pnl, [1 1]); ig.Padding = [5 3 5 3];
            uilabel(ig, 'Text', ['Not found: ' vn], 'FontColor', [0.7 0 0], 'FontSize', 11);
            continue;
        end

        vi = interpData.(sn);

        % 50/50 split: KPH (left) | MPH (right)
        glSplit = uigridlayout(pnl, [1 2]);
        glSplit.ColumnWidth   = {'1x', '1x'};
        glSplit.Padding       = [0 0 0 0];
        glSplit.ColumnSpacing = 5;

        pnlKPH = uipanel(glSplit, 'BorderType', 'none');
        pnlMPH = uipanel(glSplit, 'BorderType', 'none', 'BackgroundColor', [0.98 1 0.98]);

        tKPH = gobjects(0);
        switch vi.type
            case 'VALUE',  tKPH = buildValueTbl(mainFig, interpFig, pnlKPH, vi);
            case 'MAP',    tKPH = buildMapTbl(mainFig, interpFig, pnlKPH, vi);
            case 'CURVE',  tKPH = buildCurveTbl(mainFig, interpFig, pnlKPH, vi);
        end

        tMPH = buildMPHTable(mainFig, interpFig, pnlMPH, vi, tKPH);

        % Link tables for undo
        if ~isempty(tKPH) && isvalid(tKPH)
            tKPH.UserData.linkedTable = tMPH;
            origCb = tKPH.CellEditCallback;
            tKPH.CellEditCallback = @(s,e) onKphEdit(mainFig, s, e, tMPH, vi, origCb);
        end
    end
end

function tMPH = buildMPHTable(mainFig, interpFig, pnl, vi, tKPH)
    % Persistent cache — same gray header style used twice in this function
    persistent sMPHHdr_;
    if isempty(sMPHHdr_), sMPHHdr_ = uistyle('BackgroundColor', [0.9 0.9 0.95], 'FontWeight', 'bold'); end
    % Mirror KPH table structure but with converted data
    
    % Factor
    kph2mph = 0.621371;
    
    % Convert Data
    viMPH = vi;
    viMPH.name = [vi.name ' (MPH)'];
    viMPH.unit = 'mph';
    
    % Convert ONLY data parts, keep Axes same as KPH (as requested "x and y axiz are same only the values")
    % However, vi.data usually contains the values.
    % If it's a MAP, vi.data is the Z values. vi.xAxis/yAxis are axes.
    % So we just convert vi.data.
    
    if isnumeric(vi.data)
        viMPH.data = vi.data * kph2mph;
    end
    if isnumeric(vi.value)
        viMPH.value = vi.value * kph2mph;
    end
    
    % Do NOT set isINCA to true if we want to avoid saving?
    % No, build*Tbl logic depends on isINCA flag for layout.
    % We reuse build logic but we DON'T register it in interpTbls.
    
    % To reuse build logic without registering, we need to bypass storeTbl.
    % Or we just copy the build logic here simplified.
    
    g = uigridlayout(pnl, [2 1]);  % FIX: 2 rows for table + label
    g.RowHeight = {'1x', 14};  % Table gets all space, label gets 14px
    g.Padding = [2 2 2 2];
    g.RowSpacing = 2;
    
    tMPH = gobjects(0);
    
    if strcmp(vi.type, 'VALUE')
        % Simple Value Table - COMPACT
        dispVal = viMPH.value;
        if isnan(dispVal) || isempty(dispVal), dispVal = 0; end
        
        gSub = uigridlayout(g, [1 3]);
        gSub.Layout.Row = 1;  % Place in row 1
        gSub.ColumnWidth = {80, 80, 60};  % Compact layout
        uilabel(gSub, 'Text', 'Value (MPH):', 'FontWeight', 'bold', 'HorizontalAlignment', 'right', 'FontSize', 11);
        tMPH = uitable(gSub, 'Data', {dispVal}, 'ColumnEditable', true, 'ColumnWidth', {70}, 'FontSize', 11);
        uilabel(gSub, 'Text', 'mph', 'FontAngle', 'italic', 'FontSize', 10);
        
    elseif strcmp(vi.type, 'MAP')
        nr = size(viMPH.data, 1);
        nc = size(viMPH.data, 2);
        td = cell(nr + 1, nc + 1);
        td{1, 1} = viMPH.name;
        
        % Copy Axes from KPH (Do not convert)
        if ~isempty(vi.xAxis)
            for c = 1:min(nc, length(vi.xAxis)), td{1, c+1} = vi.xAxis(c); end
            for c = length(vi.xAxis)+1:nc, td{1, c+1} = c; end
        else
            for c = 1:nc, td{1, c+1} = c; end
        end
        
        if ~isempty(vi.yAxis)
            for r = 1:min(nr, length(vi.yAxis)), td{r+1, 1} = vi.yAxis(r); end
            for r = length(vi.yAxis)+1:nr, td{r+1, 1} = r; end
        else
            for r = 1:nr, td{r+1, 1} = r; end
        end
        
        % Fill Data (Converted)
        for r = 1:nr
            for c = 1:nc
                td{r+1, c+1} = viMPH.data(r, c);
            end
        end
        
        colNames = arrayfun(@(x) num2str(x), 1:(nc+1), 'UniformOutput', false);
        tMPH = uitable(g, 'Data', td, 'ColumnName', colNames, 'ColumnEditable', true, 'FontSize', 12);
        tMPH.Layout.Row = 1;  % Place in row 1
        cw = max(65, min(95, floor(620 / (nc + 1))));  % Match KPH table sizing
        tMPH.ColumnWidth = repmat({cw}, 1, nc + 1);
        
        gs = uistyle('BackgroundColor', [0.9 0.9 0.95], 'FontWeight', 'bold');
        addStyle(tMPH, gs, 'row', 1);
        addStyle(tMPH, gs, 'column', 1);
        
    elseif strcmp(vi.type, 'CURVE')
        nc = length(viMPH.data);
        td = cell(2, nc);
        
        % Copy Axis
        if ~isempty(vi.xAxis)
            for c = 1:min(nc, length(vi.xAxis)), td{1, c} = vi.xAxis(c); end
            for c = length(vi.xAxis)+1:nc, td{1, c} = c - 1; end
        else
            for c = 1:nc, td{1, c} = c - 1; end
        end
        
        % Fill Data
        for c = 1:nc
            td{2, c} = viMPH.data(c);
        end
        
        colNames = arrayfun(@(x) num2str(x), 1:nc, 'UniformOutput', false);
        tMPH = uitable(g, 'Data', td, 'ColumnName', colNames, 'RowName', {'X-Axis', 'Value (MPH)'}, ...
            'ColumnEditable', true, 'FontSize', 12);
        tMPH.Layout.Row = 1;  % Place in row 1
        cw = max(65, min(90, floor(620 / min(nc, 18))));  % Match KPH table sizing
        tMPH.ColumnWidth = repmat({cw}, 1, nc);
        
        gs = uistyle('BackgroundColor', [0.9 0.9 0.95], 'FontWeight', 'bold');
        addStyle(tMPH, gs, 'row', 1);
    end
    
    % Set Callback
    if ~isempty(tMPH) && isgraphics(tMPH)
        tMPH.CellEditCallback = @(s,e) onMphEdit(mainFig, s, e, tKPH, vi);
        % Info Label in row 2
        lbl = uilabel(g, 'Text', '(MPH View - Calibration Only)', 'FontSize', 9, 'FontAngle', 'italic', 'FontColor', [0 0.5 0]);
        lbl.Layout.Row = 2;  % Explicitly place in bottom row
    end
end

function onKphEdit(mainFig, tKPH, e, tMPH, vi, origCallback)
    if isempty(e.Indices), return; end
    if ~isempty(origCallback), origCallback(tKPH, e); end
    kph2mph = 0.621371;
    r = e.Indices(1); c = e.Indices(2); val = e.NewData;
    isData = false;
    if strcmp(vi.type,'VALUE'), isData = true;
    elseif strcmp(vi.type,'MAP') && r>1 && c>1, isData = true;
    elseif strcmp(vi.type,'CURVE') && r==2, isData = true; end
    if isData
        if isnumeric(val), tMPH.Data{r,c} = val * kph2mph; end
        addStyle(tMPH, getYellowStyle(), 'cell', [r,c]);
    else
        tMPH.Data{r,c} = val;
    end
end

function onMphEdit(mainFig, tMPH, e, tKPH, vi)
    if isempty(e.Indices), return; end
    mph2kph = 1.60934;
    r = e.Indices(1); c = e.Indices(2); val = e.NewData;
    isData = false;
    if strcmp(vi.type,'VALUE'), isData = true;
    elseif strcmp(vi.type,'MAP') && r>1 && c>1, isData = true;
    elseif strcmp(vi.type,'CURVE') && r==2, isData = true; end
    if isData
        if isnumeric(val)
            kphVal = val * mph2kph;
            oldKph = tKPH.Data{r,c}; tKPH.Data{r,c} = kphVal;
            eKPH = struct('Indices',[r,c],'PreviousData',oldKph,'NewData',kphVal,'Source',tKPH);
            storeInterpStateForUndo(mainFig, tKPH, eKPH);
            addStyle(tKPH, getYellowStyle(), 'cell', [r,c]);
        end
    else
        tKPH.Data{r,c} = val;
    end
    addStyle(tMPH, getYellowStyle(), 'cell', [r,c]);
end


%% =========================================================================
%% HILL INTERPOLATION TAB — SIBE Module (ZF CalGuide)
%% =========================================================================
%  STALE-TRACE FIX: generation counter (ud.gen).
%    Every mode switch / par change increments ud.gen.
%    hillDo captures gen at entry; aborts before any drawing if gen changed.
%    This kills lines drawn by hillDo calls that were on the call stack
%    when the user switched mode.
%
%  Drive mode S-column groups:
%    Auto/Normal : sColLow=1(S0)→sColHigh=2(S1)   flat base=GKF_5
%    Sport       : sColLow=3(S2)→sColHigh=4(S3)   flat base=GKF_7
%    Track/Baha  : sColLow=5(S4)→sColHigh=4(S3)   flat base=GKF_9
%
%  Grade slider: ADIFF ÷ 10 = road grade %  (ADIFF stored as grade%×10 for INCA integer headers)
%    e.g. ADIFF=100 → 10.0% grade  |  ADIFF=400 → 40.0% grade (trailer)
%    Range -40..+40 covers downhill → steep uphill (incl. trailer resistance)
%  Output Speed slider: REMOVED (not needed for 1D CURVE AdiffMidPar)
%
%  4-corner blend (ZF MATLAB formula):
%    X1 = (D2H1-D1H1)*Inter_D + D1H1
%    X2 = (D2H2-D1H2)*Inter_D + D1H2
%    Final = (X2-X1)*Inter_H + X1

function buildHillInterpTab(mainFig, interpFig, tab, interpData)

    SXBX = [ 0  1  2  3  4;
              5  6  7  8  9;
             10 11 12 13 14;
             15 16 17 18 19;
             20 21 22 23 24];

    % Exact main-GUI shiftColors
    GC = [1.00 0.00 0.00;
          0.00 0.00 1.00;
          1.00 0.00 1.00;
          0.00 0.60 0.50;
          0.50 0.00 1.00;
          0.40 0.00 0.00;
          0.60 0.60 0.60];

    MODES = {'Auto / Normal', [1 2], 2, [0.12 0.62 0.12];
             'Sport',         [3 4], 2, [0.78 0.10 0.10];
             'Track / Baha',  [5 4], 2, [0.16 0.40 0.82]};

    COL_BG={[0.82 0.97 0.82];[0.65 0.90 0.65];
            [1.00 0.80 0.80];[1.00 1.00 0.55];[0.74 0.88 1.00]};
    ROW_BG={[0.84 0.87 1.00];[0.93 0.93 0.93];
            [1.00 0.96 0.84];[1.00 0.88 0.70];[1.00 0.74 0.66]};

    cntRanges = hillParseTyrng(interpData);

    %% ── LAYOUT ──────────────────────────────────────────────────────────────
    outerGl = uigridlayout(tab,[1 2]);
    outerGl.ColumnWidth = {'1x',450};
    outerGl.Padding     = [8 8 8 8];
    outerGl.ColumnSpacing = 10;

    leftGl = uigridlayout(outerGl,[3 1]);
    leftGl.RowHeight  = {'1x',28,32};
    leftGl.Padding    = [0 0 0 0];
    leftGl.RowSpacing = 4;

    plotPnl = uipanel(leftGl,'Title','Interpolated Shift Pattern  —  SIBE Hill Mode', ...
        'FontWeight','bold','FontSize',11);
    plotPnl.Layout.Row=1;
    pGl = uigridlayout(plotPnl,[1 1]); pGl.Padding=[4 4 4 4];
    ax  = uiaxes(pGl);
    ax.XLabel.String='Output RPM'; ax.YLabel.String='Pedal %';
    ax.Title.String='Select Drive Mode then move sliders';
    ax.FontSize=11; ax.XGrid='on'; ax.YGrid='on';
    ax.XLim=[0 8000]; ax.YLim=[0 110];
    hold(ax,'on');

    % ── Visibility controls row (row 2) ─────────────────────────────────────────────────────────────────────
    visGl = uigridlayout(leftGl,[1 2]);
    visGl.Layout.Row=2;
    visGl.Padding=[8 2 8 2]; visGl.ColumnWidth={'fit','1x'}; visGl.ColumnSpacing=12;
    cbShowRefs = uicheckbox(visGl,'Text','Show reference maps','Value',false, ...
        'FontSize',10,'FontWeight','bold', ...
        'Tooltip','Show/hide the 4 faded corner reference maps (blend line always visible)');
    cbShowRefs.Layout.Column=1;
    tmpLbl = uilabel(visGl,'Text','  Bold lines = interpolated blend result','FontSize',9, ...
        'FontColor',[0.35 0.35 0.35],'FontAngle','italic');
    tmpLbl.Layout.Column=2;

    statusLbl = uilabel(leftGl,'Text','—', ...
        'HorizontalAlignment','center','FontSize',10, ...
        'FontWeight','bold','FontColor',[0.08 0.38 0.08],'FontAngle','italic');
    statusLbl.Layout.Row=3;

    %% ── RIGHT PANELS ─────────────────────────────────────────────────────────
    rGl = uigridlayout(outerGl,[4 1]);
    rGl.RowHeight  = {68,214,240,170};
    rGl.Padding    = [0 0 0 0];
    rGl.RowSpacing = 8;

    %% P1: DRIVE MODE
    dmPnl=uipanel(rGl,'Title','  Drive Mode','FontWeight','bold','FontSize',11);
    dmPnl.Layout.Row=1;
    dmGl=uigridlayout(dmPnl,[1 4]);
    dmGl.Padding=[10 6 10 6]; dmGl.ColumnWidth={120,82,120,'1x'};
    dmGl.ColumnSpacing=6;
    mAcc={[0.12 0.58 0.12];[0.72 0.10 0.10];[0.14 0.40 0.80]};
    dmBtns=cell(1,3);
    for k=1:3
        dmBtns{k}=uibutton(dmGl,'state','Text',MODES{k,1}, ...
            'FontWeight','bold','FontSize',11, ...
            'BackgroundColor',mAcc{k}*0.18+[0.82 0.82 0.82]*0.82);
    end
    dmBtns{1}.Value=true;
    ddPar=uidropdown(dmGl,'Items', ...
        {'SIBE_AdiffMidPar1','SIBE_AdiffMidPar2','SIBE_AdiffMidPar3', ...
         'SIBE_AdiffMidPar4','SIBE_AdiffMidPar5'},'FontSize',10);
    ddPar.Tooltip='AdiffMidPar: maps ADIFF → HillMode (0–4)';

    %% P2: SxBx MATRIX
    mxPnl=uipanel(rGl,'Title','  SxBx  —  Map Assignment  (Hill Mode × Driver Type)', ...
        'FontWeight','bold','FontSize',11);
    mxPnl.Layout.Row=2;
    mxGl=uigridlayout(mxPnl,[6 7]);
    mxGl.Padding=[8 4 8 4]; mxGl.ColumnSpacing=2; mxGl.RowSpacing=2;
    mxGl.RowHeight={16,30,30,30,30,30};
    mxGl.ColumnWidth={78,38,38,38,38,38,'fit'};
    sTips={'Auto/Normal – Economy','Auto/Normal – Normal', ...
           'Sport','Sport & Track shared aggressive','Track/Baha – Economy'};
    uilabel(mxGl,'Text','Hill \\ S','FontSize',9,'FontWeight','bold', ...
        'HorizontalAlignment','center','FontColor',[0.2 0.2 0.2]);
    for s=1:5
        hh=uilabel(mxGl,'Text',sprintf('S%d',s-1),'FontSize',10,'FontWeight','bold', ...
            'HorizontalAlignment','center','BackgroundColor',COL_BG{s});
        hh.Tooltip=sTips{s};
    end
    uilabel(mxGl,'Text','Mode','FontSize',9,'FontWeight','bold', ...
        'HorizontalAlignment','center','FontColor',[0.2 0.2 0.2]);
    hillNames={'Downhill','Plain','Slight','Mean','Steep'};
    mxCells=cell(5,5);
    for b=1:5
        rl=uilabel(mxGl,'Text',sprintf('B%d',b-1),'FontSize',10,'FontWeight','bold', ...
            'HorizontalAlignment','center','BackgroundColor',ROW_BG{b});
        rl.Tooltip=hillNames{b};
        for s=1:5
            c_=min(1,max(0,COL_BG{s}*0.52+ROW_BG{b}*0.48));
            cl=uilabel(mxGl,'Text',num2str(SXBX(b,s)),'FontSize',11,'FontWeight','bold', ...
                'HorizontalAlignment','center','BackgroundColor',c_);
            cl.Tooltip=sprintf('SKL_GKF_%d  B%d=%s  S%d=%s', ...
                SXBX(b,s),b-1,hillNames{b},s-1,sTips{s});
            mxCells{b,s}=cl;
        end
        uilabel(mxGl,'Text',hillNames{b},'FontSize',9, ...
            'HorizontalAlignment','left','FontAngle','italic');
    end

    %% P3: SLIDERS — Grade/ADIFF + Driver Counter only (Output Speed removed)
    slPnl=uipanel(rGl,'Title','  Inputs  —  move sliders to interpolate live', ...
        'FontWeight','bold','FontSize',11);
    slPnl.Layout.Row=3;
    slGl=uigridlayout(slPnl,[3 1]);
    slGl.Padding=[12 10 12 8]; slGl.RowHeight={'1x','1x',20};
    slGl.RowSpacing=10;

    % ── Grade / ADIFF ──────────────────────────────────────────────────────
    grGl=uigridlayout(slGl,[3 3]);
    grGl.Layout.Row=1;
    grGl.RowHeight={22,22,'1x'}; grGl.ColumnWidth={'1x',110,52};
    grGl.Padding=[0 0 0 0]; grGl.RowSpacing=0; grGl.ColumnSpacing=6;

    tmp=uilabel(grGl,'Text','Grade / ADIFF','FontSize',12,'FontWeight','bold');
    tmp.Layout.Row=1; tmp.Layout.Column=1;
    lblAdiff=uilabel(grGl,'Text','0.0','FontSize',16,'FontWeight','bold', ...
        'HorizontalAlignment','right','FontColor',[0.06 0.15 0.76]);
    lblAdiff.Layout.Row=1; lblAdiff.Layout.Column=2;
    tmp=uilabel(grGl,'Text','[-]','FontSize',11,'FontColor',[0.42 0.42 0.42]);
    tmp.Layout.Row=1; tmp.Layout.Column=3;

    tmp=uilabel(grGl,'Text','  % grade','FontSize',9,'FontColor',[0.48 0.48 0.48], ...
        'FontAngle','italic');
    tmp.Layout.Row=2; tmp.Layout.Column=1;
    lblDeg=uilabel(grGl,'Text','0.0','FontSize',13,'FontWeight','bold', ...
        'HorizontalAlignment','right','FontColor',[0.08 0.50 0.08]);
    lblDeg.Layout.Row=2; lblDeg.Layout.Column=2;
    tmp=uilabel(grGl,'Text','%','FontSize',11,'FontColor',[0.42 0.42 0.42]);
    tmp.Layout.Row=2; tmp.Layout.Column=3;

    slGrade=uislider(grGl,'Limits',[-40 40],'Value',0, ...
        'MajorTicks',-40:10:40,'MinorTicks',[],'FontSize',9);
    slGrade.Layout.Row=3; slGrade.Layout.Column=[1 3];
    slGrade.Tooltip='ADIFF ÷ 10 = road grade %  (e.g. ADIFF=100 → 10.0% grade)';

    % ── Driver Type Counter ─────────────────────────────────────────────────
    autoR=cntRanges.auto;
    drGl=uigridlayout(slGl,[2 3]);
    drGl.Layout.Row=2;
    drGl.RowHeight={22,'1x'}; drGl.ColumnWidth={'1x',110,52};
    drGl.Padding=[0 0 0 0]; drGl.RowSpacing=0; drGl.ColumnSpacing=6;

    tmp=uilabel(drGl,'Text','Driver Type Counter','FontSize',12,'FontWeight','bold');
    tmp.Layout.Row=1; tmp.Layout.Column=1;
    lblDriver=uilabel(drGl,'Text',sprintf('%d',autoR(1)), ...
        'FontSize',16,'FontWeight','bold', ...
        'HorizontalAlignment','right','FontColor',[0.06 0.15 0.76]);
    lblDriver.Layout.Row=1; lblDriver.Layout.Column=2;
    tmp=uilabel(drGl,'Text','cnt','FontSize',11,'FontColor',[0.42 0.42 0.42]);
    tmp.Layout.Row=1; tmp.Layout.Column=3;
    slDriver=uislider(drGl,'Limits',[autoR(1) autoR(2)],'Value',autoR(1), ...
        'MajorTicks',unique([autoR(1):(autoR(2)-autoR(1))/4:autoR(2), autoR(2)]), ...
        'MinorTicks',[],'FontSize',9);
    slDriver.Layout.Row=2; slDriver.Layout.Column=[1 3];
    slDriver.Tooltip='TYRNG_CNT_SS counter. Range auto-set per Drive Mode.';

    cntInfoLbl=uilabel(slGl,'Text','—', ...
        'FontSize',9,'FontColor',[0.36 0.36 0.36],'FontAngle','italic', ...
        'HorizontalAlignment','center');
    cntInfoLbl.Layout.Row=3;

    %% P4: SIBE SIGNALS
    sigPnl=uipanel(rGl,'Title','  SIBE Computed Signals','FontWeight','bold','FontSize',11);
    sigPnl.Layout.Row=4;
    sigGl=uigridlayout(sigPnl,[6 3]);
    sigGl.ColumnWidth={175,'1x',46}; sigGl.RowHeight=repmat({22},1,6);
    sigGl.Padding=[10 6 10 6]; sigGl.RowSpacing=3;
    sigDefs={'SIBE_HillMode','—','[-]','0.00=downhill .. 4.00=steep uphill';
             'SIBE_ModeLow', '—','[-]','floor(HillMode)';
             'SIBE_ModeUp',  '—','[-]','ModeLow+1';
             'SIBE_ModeIPF', '—','[%]','Inter_H = frac×100';
             'Low Maps (D1H1, D2H1)','—','','Corner maps at modeLow row';
             'High Maps (D1H2, D2H2)','—','','Corner maps at modeUp row'};
    sigVals=cell(1,6);
    for i=1:6
        l=uilabel(sigGl,'Text',[sigDefs{i,1} ':'],'FontSize',10,'FontWeight','bold', ...
            'HorizontalAlignment','right'); l.Tooltip=sigDefs{i,4};
        sigVals{i}=uilabel(sigGl,'Text',sigDefs{i,2},'FontSize',12, ...
            'FontColor',[0.05 0.14 0.76],'FontWeight','bold');
        sigVals{i}.Tooltip=sigDefs{i,4};
        uilabel(sigGl,'Text',sigDefs{i,3},'FontSize',9,'FontColor',[0.46 0.46 0.46]);
    end

    %% ── STATE ───────────────────────────────────────────────────────────────
    ud.ax            = ax;
    ud.statusLbl     = statusLbl;
    ud.mxCells       = mxCells;
    ud.COL_BG        = COL_BG;
    ud.ROW_BG        = ROW_BG;
    ud.GC            = GC;
    ud.MODES         = MODES;
    ud.SXBX          = SXBX;
    ud.dmBtns        = dmBtns;
    ud.ddPar         = ddPar;
    ud.slGrade       = slGrade;
    ud.slDriver      = slDriver;
    ud.lblAdiff      = lblAdiff;
    ud.lblDeg        = lblDeg;
    ud.lblDriver     = lblDriver;
    ud.cntInfoLbl    = cntInfoLbl;
    ud.sigVals       = sigVals;
    ud.activeModeIdx = 1;
    ud.cntRanges     = cntRanges;
    ud.cbShowRefs    = cbShowRefs;       % show/hide reference maps checkbox
    ud.hRefLines     = [];               % 4x7x2 gobjects, created on first hillDo
    ud.hBlendLines   = [];               % 7x2 gobjects, created on first hillDo
    ud.lastMapNums   = [-1 -1 -1 -1];   % track corner-map changes for XData refresh
    tab.UserData = ud;

    %% ── CALLBACKS ────────────────────────────────────────────────────────────
    for k=1:3
        kk=k;
        dmBtns{k}.ValueChangedFcn=@(src,~) hillModeBtn(mainFig,tab,interpData,src,kk);
    end
    slGrade.ValueChangingFcn  =@(~,e) hillDrag(mainFig,tab,interpData,e.Value,NaN);
    slDriver.ValueChangingFcn =@(~,e) hillDrag(mainFig,tab,interpData,NaN,e.Value);
    slGrade.ValueChangedFcn   =@(~,~) hillDo(mainFig,tab,interpData,false);
    slDriver.ValueChangedFcn  =@(~,~) hillDo(mainFig,tab,interpData,false);
    ddPar.ValueChangedFcn     =@(~,~) hillResetAndRun(mainFig,tab,interpData);
    cbShowRefs.ValueChangedFcn=@(~,~) hillToggleRefs(tab);

    hillResetAndRun(mainFig,tab,interpData);
end

% ─────────────────────────────────────────────────────────────────────────────
function ranges = hillParseTyrng(interpData)
    % Default ranges: Auto 5-200 | Sport 201-400 | Track 401-600
    ranges.auto=[5,200]; ranges.sport=[201,400]; ranges.track=[401,600];
    fn=matlab.lang.makeValidName('TYRNG_CNT_SS');
    if ~isfield(interpData,fn)||isempty(interpData.(fn)), return; end
    vi=interpData.(fn);
    if isempty(vi.data)||size(vi.data,2)<2, return; end
    c1=vi.data(:,1); c2=vi.data(:,2);
    aL=[]; aH=[]; sL=[]; sH=[]; tL=[]; tH=[];
    for r=1:length(c1)
        lo0=c1(r); hi0=c2(r);
        if lo0==0&&hi0==0, continue; end
        lo=max(1,lo0); hi=max(1,hi0);
        if hi<lo, continue; end
        if     lo>=1  &&hi<=200, aL(end+1)=lo; aH(end+1)=hi; %#ok  Auto
        elseif lo>=201&&hi<=400, sL(end+1)=lo; sH(end+1)=hi; %#ok  Sport
        elseif lo>=401&&hi<=600, tL(end+1)=lo; tH(end+1)=hi; %#ok  Track
        end
    end
    if ~isempty(aL), ranges.auto=[min(aL),max(aH)];   end
    if ~isempty(sL), ranges.sport=[min(sL),max(sH)];  end
    if ~isempty(tL), ranges.track=[min(tL),max(tH)];  end
end

% ─────────────────────────────────────────────────────────────────────────────
function hillApplyDriverSlider(tab)
% Set driver slider range for current mode.
% NOTE: does NOT call hillDo — only adjusts slider properties.
    ud=tab.UserData; mIdx=ud.activeModeIdx; r=ud.cntRanges;
    switch mIdx
        case 1, lo=r.auto(1);  hi=r.auto(2);
        case 2, lo=r.sport(1); hi=r.sport(2);
        case 3, lo=r.track(1); hi=r.track(2);
        otherwise, lo=5; hi=200;
    end
    if lo==hi
        ud.slDriver.Limits=[lo-0.5 lo+0.5];
        ud.slDriver.Value=lo;
        ud.slDriver.MajorTicks=[lo]; ud.slDriver.MinorTicks=[];
        ud.slDriver.Enable='off';
        ud.lblDriver.Text=sprintf('%d  (fixed)',lo);
    else
        ud.slDriver.Enable='on';
        ud.slDriver.Limits=[lo hi];
        cur=ud.slDriver.Value;
        if cur<lo||cur>hi, cur=lo; end
        ud.slDriver.Value=cur;
        step=(hi-lo)/4;
        ud.slDriver.MajorTicks=unique([lo:step:hi,hi]);
        ud.slDriver.MinorTicks=[];
        ud.lblDriver.Text=sprintf('%d',round(cur));
    end
    tab.UserData=ud;
end

% ─────────────────────────────────────────────────────────────────────────────
function dFrac = hillCounterToFrac(cntVal,mIdx,cntRanges)
    switch mIdx
        case 1, lo=cntRanges.auto(1);  hi=cntRanges.auto(2);
        case 2, lo=cntRanges.sport(1); hi=cntRanges.sport(2);
        case 3, lo=cntRanges.track(1); hi=cntRanges.track(2);
        otherwise, dFrac=0; return;
    end
    if hi<=lo, dFrac=0; return; end
    dFrac=max(0,min(1,(cntVal-lo)/(hi-lo)));
end

% ─────────────────────────────────────────────────────────────────────────────
function hillResetAndRun(mainFig,tab,interpData)
    ud=tab.UserData;
    ud.cntRanges=hillParseTyrng(interpData);
    r=ud.cntRanges;
    ud.cntInfoLbl.Text=sprintf( ...
        'Counter:  Auto %d–%d  |  Sport %d–%d  |  Track %d–%d', ...
        r.auto(1),r.auto(2),r.sport(1),r.sport(2),r.track(1),r.track(2));
    pField=matlab.lang.makeValidName(ud.ddPar.Value);
    lo=-40; hi=40;
    if isfield(interpData,pField)&&~isempty(interpData.(pField))
        vi=interpData.(pField);
        try
            if ~isempty(vi.xAxis)
                xa=double(vi.xAxis(:)'); xa=xa(isfinite(xa));
                lo=floor(min(xa)); hi=ceil(max(xa));
            end
        catch; end
    end
    if hi-lo<2, lo=-40; hi=40; end
    ud.slGrade.Limits=[lo hi];
    ud.slGrade.Value=max(lo,min(hi,ud.slGrade.Value));
    span=hi-lo; if span<=20, step=5; elseif span<=40, step=10; else, step=20; end
    ud.slGrade.MajorTicks=lo:step:hi; ud.slGrade.MinorTicks=[];
    tab.UserData=ud;
    hillApplyDriverSlider(tab);
    hillDo(mainFig,tab,interpData);
end

% ─────────────────────────────────────────────────────────────────────────────
function hillModeBtn(mainFig,tab,interpData,src,idx)
% Mode switch: enforce radio, immediately clear axes, then rebuild.
    ud=tab.UserData;
    if ~src.Value, src.Value=true; return; end
    for k=1:3; if k~=idx, ud.dmBtns{k}.Value=false; end; end
    ud.activeModeIdx=idx;
    % Clear axes immediately so user sees a clean plot right away
    cla(ud.ax); hold(ud.ax,'on');
    ud.ax.Title.String=sprintf('Loading %s ...', ud.MODES{idx,1});
    ud.hRefLines   = [];           % force full line rebuild on next hillDo
    ud.hBlendLines = [];
    ud.lastMapNums = [-1 -1 -1 -1];
    tab.UserData=ud;
    % Disable BOTH ValueChangedFcn AND ValueChangingFcn on both sliders
    % to prevent ANY spurious hillDo/hillDrag calls while we adjust limits.
    % Without this, changing slDriver.Value fires ValueChangingFcn → hillDrag
    % → hillDo with the old mode still set, drawing stale lines.
    slG=ud.slGrade; slD=ud.slDriver;
    oldGc=slG.ValueChangedFcn;  oldGgc=slG.ValueChangingFcn;
    oldDc=slD.ValueChangedFcn;  oldDgc=slD.ValueChangingFcn;
    slG.ValueChangedFcn=[]; slG.ValueChangingFcn=[];
    slD.ValueChangedFcn=[]; slD.ValueChangingFcn=[];
    hillApplyDriverSlider(tab);
    slG.ValueChangedFcn=oldGc;  slG.ValueChangingFcn=oldGgc;
    slD.ValueChangedFcn=oldDc;  slD.ValueChangingFcn=oldDgc;
    hillDo(mainFig,tab,interpData);
end

% ─────────────────────────────────────────────────────────────────────────────
function hillDrag(mainFig,tab,interpData,gv,dv)
% ValueChangingFcn — update labels then throttled rebuild skipping legend.
    ud=tab.UserData;
    if ~isnan(gv)
        ud.lblAdiff.Text=sprintf('%.1f',gv);
        ud.lblDeg.Text=sprintf('%.1f',gv/10);
    end
    if ~isnan(dv)&&strcmp(ud.slDriver.Enable,'on')
        ud.lblDriver.Text=sprintf('%d',round(dv));
    end
    tab.UserData=ud;
    hillDo(mainFig,tab,interpData,true);  % isDrag=true skips legend for speed
    drawnow limitrate;
end

% ─────────────────────────────────────────────────────────────────────────────
function hillDo(mainFig,tab,interpData,isDrag)
% Fast hill interpolation draw.
% FIRST call (or after mode switch): creates all 70 line objects, stores handles.
% SUBSEQUENT calls (drag): only updates XData/YData — no object creation, no cla.
% Ref lines are only updated when corner-map assignments change (modeLow steps).
    if nargin<4, isDrag=false; end
    ud=tab.UserData;

    try
        appData = mainFig.UserData;
        adiff   = ud.slGrade.Value;
        cntVal  = ud.slDriver.Value;
        mIdx    = ud.activeModeIdx;

        % ── Labels ────────────────────────────────────────────────────────────
        ud.statusLbl.FontColor=[0.08 0.38 0.08];  % reset from any previous error
        ud.lblAdiff.Text=sprintf('%.1f',adiff);
        ud.lblDeg.Text=sprintf('%.1f',adiff/10);
        if strcmp(ud.slDriver.Enable,'on')
            ud.lblDriver.Text=sprintf('%d',round(cntVal));
        end

        % ── Inter_D (driver fraction) ──────────────────────────────────────
        dFrac  = hillCounterToFrac(cntVal,mIdx,ud.cntRanges);
        sCols  = ud.MODES{mIdx,2};
        sColL  = sCols(1); sColH = sCols(end);
        Inter_D = dFrac;

        % ── ADIFF → HillMode via SIBE_AdiffMidPar curve ───────────────────
        pField   = matlab.lang.makeValidName(ud.ddPar.Value);
        hillMode = NaN; parMissing = true;
        if isfield(interpData,pField) && ~isempty(interpData.(pField))
            vi=interpData.(pField);
            try
                if strcmp(vi.type,'CURVE') && ~isempty(vi.xAxis)
                    xAx=double(vi.xAxis(:)'); D=double(vi.data(:)');
                    [xAx,ia]=unique(xAx); D=D(ia);
                    xq=max(min(adiff,max(xAx)),min(xAx));
                    hillMode=interp1(xAx,D,xq,'linear'); parMissing=false;
                elseif strcmp(vi.type,'MAP') && ~isempty(vi.xAxis) && ~isempty(vi.yAxis)
                    xAx=double(vi.xAxis(:)'); yAx=double(vi.yAxis(:)); D=double(vi.data);
                    [xAx,ia]=unique(xAx); D=D(:,ia);
                    [yAx,ib]=unique(yAx); D=D(ib,:);
                    xq=max(min(adiff,max(xAx)),min(xAx));
                    yq=yAx(round(length(yAx)/2));
                    hillMode=interp2(xAx,yAx,D,xq,yq,'linear'); parMissing=false;
                end
            catch; end
        end
        if isnan(hillMode)||~isfinite(hillMode)
            lim=ud.slGrade.Limits;
            hillMode=max(0,min(4, 1+adiff/max(abs(lim(2)),1)*3));
        end
        hillMode=max(0,min(4,hillMode));

        % ── SIBE signals ──────────────────────────────────────────────────
        modeLow = max(0,min(3,floor(hillMode)));
        modeUp  = modeLow+1;
        hillIPF = max(0,min(100,(hillMode-modeLow)*100));
        Inter_H = hillIPF/100;

        mapD1H1 = ud.SXBX(modeLow+1,sColL);
        mapD2H1 = ud.SXBX(modeLow+1,sColH);
        mapD1H2 = ud.SXBX(modeUp+1, sColL);
        mapD2H2 = ud.SXBX(modeUp+1, sColH);

        % ── Bilinear weights ──────────────────────────────────────────────
        wD1H1 = (1-Inter_D)*(1-Inter_H)*100;
        wD2H1 =    Inter_D *(1-Inter_H)*100;
        wD1H2 = (1-Inter_D)* Inter_H   *100;
        wD2H2 =    Inter_D * Inter_H   *100;

        % ── Signal panel (fast label updates, no graphics objects) ────────
        ud.sigVals{1}.Text=sprintf('%.3f',hillMode);
        ud.sigVals{2}.Text=sprintf('%d',modeLow);
        ud.sigVals{3}.Text=sprintf('%d',modeUp);
        ud.sigVals{4}.Text=sprintf('%.1f %%',hillIPF);
        ud.sigVals{5}.Text=sprintf('GKF_%d(%.0f%%) & GKF_%d(%.0f%%)',mapD1H1,wD1H1,mapD2H1,wD2H1);
        ud.sigVals{6}.Text=sprintf('GKF_%d(%.0f%%) & GKF_%d(%.0f%%)',mapD1H2,wD1H2,mapD2H2,wD2H2);

        % ── SxBx highlight ────────────────────────────────────────────────
        for b=1:5
            for s=1:5
                orig=min(1,max(0,ud.COL_BG{s}*0.52+ud.ROW_BG{b}*0.48));
                if any(sCols==s)
                    ud.mxCells{b,s}.BackgroundColor=orig;
                else
                    ud.mxCells{b,s}.BackgroundColor=orig*0.52+[0.48 0.48 0.48]*0.48;
                end
            end
        end
        for s=sCols
            ud.mxCells{modeLow+1,s}.BackgroundColor=[1.00 0.90 0.10];
            ud.mxCells{modeUp+1, s}.BackgroundColor=[1.00 0.52 0.05];
        end

        % ── Get corner map data ───────────────────────────────────────────
        allMaps = appData.allMaps;
        allMN   = getMapNames(appData);   % safe: builds from allMaps if cache absent
        objD1H1 = hillGetMap(allMaps,allMN,mapD1H1);
        objD2H1 = hillGetMap(allMaps,allMN,mapD2H1);
        objD1H2 = hillGetMap(allMaps,allMN,mapD1H2);
        objD2H2 = hillGetMap(allMaps,allMN,mapD2H2);

        % ── Blend calculation (fast matrix math) ──────────────────────────
        [bUp,bDn,blendOK,pedalB] = hillBlend4(objD1H1,objD2H1,objD1H2,objD2H2,Inter_D,Inter_H);

        % ── INITIALISE line handles on first call (or after mode switch) ──
        needInit = isempty(ud.hBlendLines) || ~all(isvalid(ud.hBlendLines(:)));
        if needInit
            cla(ud.ax); hold(ud.ax,'on');
            ud = hillInitLineHandles(ud.ax, ud);
        end

        % ── UPDATE reference lines only when corner-map assignments change ─
        % (modeLow/modeUp step is infrequent during a drag; most frames skip this)
        mapNums = [mapD1H1,mapD2H1,mapD1H2,mapD2H2];
        if ~isequal(mapNums, ud.lastMapNums)
            refObjs = {objD1H1,objD2H1,objD1H2,objD2H2};
            lblFmt  = {
                sprintf('GKF_%d D1\xB7H%d  %.0f%%',mapD1H1,modeLow,wD1H1);
                sprintf('GKF_%d D2\xB7H%d  %.0f%%',mapD2H1,modeLow,wD2H1);
                sprintf('GKF_%d D1\xB7H%d  %.0f%%',mapD1H2,modeUp, wD1H2);
                sprintf('GKF_%d D2\xB7H%d  %.0f%%',mapD2H2,modeUp, wD2H2);
            };
            for ri=1:4
                obj_ = refObjs{ri};
                for g=1:7
                    if ~isempty(obj_) && g<=size(obj_.Z_up,2)
                        xUp = obj_.Z_up(:,g);  xDn = obj_.Z_down(:,g);
                        ped = obj_.pedal(:);
                    else
                        xUp = NaN; xDn = NaN; ped = NaN;
                    end
                    ud.hRefLines(ri,g,1).XData = xUp;
                    ud.hRefLines(ri,g,1).YData = ped;
                    ud.hRefLines(ri,g,2).XData = xDn;
                    ud.hRefLines(ri,g,2).YData = ped;
                end
                % Update legend label (gear-1 line only)
                if isvalid(ud.hRefLines(ri,1,1))
                    ud.hRefLines(ri,1,1).DisplayName = [lblFmt{ri} ' ' char(8593)];
                    ud.hRefLines(ri,1,2).DisplayName = [lblFmt{ri} ' ' char(8595)];
                end
            end
            ud.lastMapNums = mapNums;
        end

        % ── Apply ref-line visibility (checkbox) ──────────────────────────
        showRefs = ud.cbShowRefs.Value;
        if showRefs, refVis = 'on'; else, refVis = 'off'; end
        set(ud.hRefLines(:), 'Visible', refVis);

        % ── UPDATE blend lines (XData only — always changes with sliders) ─
        nPed = length(pedalB);
        if blendOK && nPed>0
            nGu = size(bUp,2); nGd = size(bDn,2);
            for g=1:7
                if g<=nGu
                    ud.hBlendLines(g,1).XData = bUp(:,g);
                    ud.hBlendLines(g,1).YData = pedalB(:);
                else
                    ud.hBlendLines(g,1).XData = NaN;
                    ud.hBlendLines(g,1).YData = NaN;
                end
                if g<=nGd
                    ud.hBlendLines(g,2).XData = bDn(:,g);
                    ud.hBlendLines(g,2).YData = pedalB(:);
                else
                    ud.hBlendLines(g,2).XData = NaN;
                    ud.hBlendLines(g,2).YData = NaN;
                end
            end
        else
            % No valid blend — blank all blend lines
            for g=1:7
                ud.hBlendLines(g,1).XData=NaN; ud.hBlendLines(g,1).YData=NaN;
                ud.hBlendLines(g,2).XData=NaN; ud.hBlendLines(g,2).YData=NaN;
            end
            if isempty(objD1H1) && isempty(objD1H2) && needInit
                text(ud.ax,0.5,0.5, ...
                    {sprintf('Maps GKF_%d/%d/%d/%d not loaded.',mapD1H1,mapD2H1,mapD1H2,mapD2H2), ...
                     ['Load a CSV with SKL_GKF_0' char(8230) '24.']}, ...
                    'Units','normalized','HorizontalAlignment','center', ...
                    'FontSize',11,'Color',[0.65 0.08 0.08],'FontWeight','bold');
            end
        end

        % ── Axis limits / title ───────────────────────────────────────────
        ud.ax.XLim=[0 8000]; ud.ax.YLim=[0 110];
        mNames={'Auto/Normal','Sport','Track'};
        ud.ax.Title.String=sprintf( ...
            'Mode: %s  |  ADIFF=%.1f (%.1f%% grade)  |  HillMode=%.2f  |  H%d(%.0f%%)%sH%d(%.0f%%)  |  cnt=%d  D=%.2f', ...
            mNames{mIdx},adiff,adiff/10,hillMode, ...
            modeLow,100-hillIPF,char(8596),modeUp,hillIPF,round(cntVal),Inter_D);

        % ── Legend (skipped during drag — legend() is the slowest call) ───
        if ~isDrag
            legend(ud.ax,'Location','southeast','FontSize',8,'Interpreter','none', ...
                'Box','on','NumColumnsMode','auto');
        end

        baseMap = ud.SXBX(ud.MODES{mIdx,3},sColL);
        if parMissing, parNote = sprintf(' [%s fallback]',ud.ddPar.Value); else, parNote = ''; end
        ud.statusLbl.Text=sprintf( ...
            'GKF_%d(%.0f%%)  GKF_%d(%.0f%%)  GKF_%d(%.0f%%)  GKF_%d(%.0f%%)  |  Base: GKF_%d%s', ...
            mapD1H1,wD1H1,mapD2H1,wD2H1,mapD1H2,wD1H2,mapD2H2,wD2H2,baseMap,parNote);

    catch ME
        ud.statusLbl.Text=sprintf('Error: %s', ME.message);
        ud.statusLbl.FontColor=[0.80 0.10 0.10];
    end
    tab.UserData=ud;
end

% ─────────────────────────────────────────────────────────────────────────────
function ud = hillInitLineHandles(ax, ud)
% Create all 70 line objects once with NaN data. Called on first hillDo
% invocation or after a mode switch. Stores handles in ud.hRefLines and
% ud.hBlendLines so subsequent calls only need XData/YData updates.
    GC       = ud.GC;
    % Reference lines: 4 corner maps, positional fade/style (fixed per position)
    refFades = [0.68, 0.50, 0.55, 0.38];
    refLsU   = {':', '--', ':', '--'};
    refLsD   = {':', '--', ':', '--'};
    ud.hRefLines  = gobjects(4,7,2);
    for ri=1:4
        fade = refFades(ri);
        lsU=refLsU{ri}; lsD=refLsD{ri};
        for g=1:7
            col = min(1,max(0, GC(g,:)*(1-fade)+[1 1 1]*fade));
            if g==1, hv='on'; else, hv='off'; end
            ud.hRefLines(ri,g,1)=plot(ax,NaN,NaN,lsU,'Color',col,'LineWidth',0.70, ...
                'DisplayName','','HandleVisibility',hv, ...
                'PickableParts','none','HitTest','off');
            ud.hRefLines(ri,g,2)=plot(ax,NaN,NaN,lsD,'Color',col,'LineWidth',0.55, ...
                'DisplayName','','HandleVisibility',hv, ...
                'PickableParts','none','HitTest','off');
        end
    end
    % Blend lines: 7 gears, bold, always visible in legend
    gStr={'1-2','2-3','3-4','4-5','5-6','6-7','7-8'};
    ud.hBlendLines = gobjects(7,2);
    for g=1:7
        col=GC(g,:);
        ud.hBlendLines(g,1)=plot(ax,NaN,NaN,'-','Color',col,'LineWidth',2.2, ...
            'DisplayName',[gStr{g} ' ' char(8593)], ...
            'HandleVisibility','on','PickableParts','none','HitTest','off');
        ud.hBlendLines(g,2)=plot(ax,NaN,NaN,'--','Color',col,'LineWidth',1.5, ...
            'DisplayName',[gStr{g} ' ' char(8595)], ...
            'HandleVisibility','on','PickableParts','none','HitTest','off');
    end
    ud.lastMapNums = [-1 -1 -1 -1];   % force ref-line XData update on first draw
end

% ─────────────────────────────────────────────────────────────────────────────
function hillToggleRefs(tab)
% Instant show/hide of reference maps — just flips Visible, no redraw needed.
    ud = tab.UserData;
    if isempty(ud.hRefLines) || ~all(isvalid(ud.hRefLines(:))), return; end
    if ud.cbShowRefs.Value, vis = 'on'; else, vis = 'off'; end
    set(ud.hRefLines(:),'Visible',vis);
end

% ─────────────────────────────────────────────────────────────────────────────
function [bUp,bDn,ok,pedal]=hillBlend4(objD1H1,objD2H1,objD1H2,objD2H2,Inter_D,Inter_H)
    bUp=[]; bDn=[]; ok=false; pedal=[];
    if isempty(objD1H1), return; end
    pedal=objD1H1.pedal(:);
    try
        sz=size(objD1H1.Z_up);
        hD2=~isempty(objD2H1)&&isequal(sz,size(objD2H1.Z_up));
        hH2=~isempty(objD1H2)&&isequal(sz,size(objD1H2.Z_up));
        hDH=~isempty(objD2H2)&&isequal(sz,size(objD2H2.Z_up));
        if hD2&&hH2&&hDH
            X1u=(objD2H1.Z_up   -objD1H1.Z_up)  *Inter_D+objD1H1.Z_up;
            X2u=(objD2H2.Z_up   -objD1H2.Z_up)  *Inter_D+objD1H2.Z_up;
            bUp=(X2u-X1u)*Inter_H+X1u;
            X1d=(objD2H1.Z_down -objD1H1.Z_down)*Inter_D+objD1H1.Z_down;
            X2d=(objD2H2.Z_down -objD1H2.Z_down)*Inter_D+objD1H2.Z_down;
            bDn=(X2d-X1d)*Inter_H+X1d;
        elseif hH2
            bUp=objD1H1.Z_up*(1-Inter_H)+objD1H2.Z_up*Inter_H;
            bDn=objD1H1.Z_down*(1-Inter_H)+objD1H2.Z_down*Inter_H;
        elseif hD2
            bUp=objD1H1.Z_up*(1-Inter_D)+objD2H1.Z_up*Inter_D;
            bDn=objD1H1.Z_down*(1-Inter_D)+objD2H1.Z_down*Inter_D;
        else
            bUp=objD1H1.Z_up; bDn=objD1H1.Z_down;
        end
        ok=true;
    catch; end
end

% ─────────────────────────────────────────────────────────────────────────────
function map=hillGetMap(allMaps,allMapNames,mapNum)
% Fast lookup using cached allMapNames string array instead of linear strcmp loop.
    map=[];
    if isempty(allMaps), return; end
    tgt=sprintf('SKL_GKF_%d',mapNum);
    if ~isempty(allMapNames)
        idx=find(allMapNames==tgt,1);
    else
        % Fallback: linear search (no cache available)
        idx=[];
        for i=1:length(allMaps)
            if strcmp(allMaps{i}.name,tgt), idx=i; break; end
        end
    end
    if ~isempty(idx), map=allMaps{idx}; end
end

% ─────────────────────────────────────────────────────────────────────────────
function origUK = ukEnsureULUSPDSP(origUK)
% Guarantees ukData always has 8 columns with correct UL/USP/DSP values.
% Works for:  (a) old 5-col projects  (b) fresh CSVs  (c) any partially-filled data.
% Matches rows by SKLID (col 4) against the hardcoded static lookup table.
% Returns origUK with layout: UK(1) Abbrev(2) ID(3) SKLID(4) UL(5) USP(6) DSP(7) MapNums(8)

    % ── Hardcoded static lookup: SKLID → [UL, USP, DSP] ─────────────────────
    % Columns: SKLID, UL, USP, DSP
    lut = {
        'UKTYP_SklId',          'YES', '',      '';
        'UKFO_SklId',           '',    'YES',   '';
        'UKSUS_SklId',          '',    'YES',   '';
        'UKKE_SklId',           'YES', 'YES',   'YES';
        'UKPRW_SklId',          '',    'YES',   'YES';
        'UKGBF_SklId',          'YES', 'YES',   '';
        'UKBA_SklId',           'YES', 'YES',   '';
        'UKWE_SklId',           'YES', 'YES',   '';
        'UKTOW_SklId',          'YES', '',      '';
        'UKSVF_SklId',          'YES', '(YES)', '';
        'UKASC_SklId',          'YES', '',      '';
        'UKCDS_SklId',          '',    'YES',   'YES';
        'TIPSKL_SklId',         'YES', '(YES)', '(YES)';
        'UKFGR_SklId',          'YES', 'YES',   'YES';
        'UKFGR_SKLID',          'YES', 'YES',   'YES';
        'UKFGR_SKLID_ACC',      'YES', 'YES',   'YES';
        'UKFGR_SKLID_Vdiff',    'YES', 'YES',   'YES';
        'UKDSD_SklId',          '',    '',      'YES';
        'UKSRS_SKLID',          'YES', '',      '';
        'UKSRS_SKLID_Lvl1',     'YES', '',      '';
        'UKSRS_SklId_Lvl2',     'YES', '',      '';
        'UKSRS_SKLID_Lvl2',     'YES', '',      '';
        'UKECO_SklId',          'YES', '',      '';
        'UKRPO_SklId',          'YES', '',      '';
        'UKSWG_SKLID',          'YES', '',      'YES';
        'UKLOW_SklId',          'YES', '',      '';
        'UKGGS_SklId',          'YES', '',      '';
        'UKGGS_SklIdLow',       'YES', '',      '';
        'UKSND_SklId',          'YES', '',      '';
        'UKSND_SklIdLow',       'YES', '',      '';
        'UKXC_SklId',           'YES', '',      '';
        'UKXC_SklIdLow',        'YES', '',      '';
        'UKRCK_SklId',          'YES', '',      '';
        'UKFW_SklId',           'YES', 'YES',   'YES';
        'UKEOL_SklId',          'YES', '',      '';
        'UKDRS_SklId',          'YES', 'YES',   '';
        'UKVAL_SklId',          'YES', '',      '';
        'UKCC_SklIdACC',        'YES', 'YES',   'YES';
        'UKCC_SklIdCC',         'YES', 'YES',   'YES';
        'UKCC_SklIdRRCC',       'YES', 'YES',   'YES';
        'UKCC_SklIdVdifACC',    'YES', 'YES',   'YES';
        'UKCC_SklIdVdifCC',     'YES', 'YES',   'YES';
        'UKCC_SklIdVdifRRCC',   'YES', 'YES',   'YES';
        'UKCC_SklIdVDifACC',    'YES', 'YES',   'YES';
        'UKCC_SklIdVDifCC',     'YES', 'YES',   'YES';
        'UKCC_SklIdVDifRRCC',   'YES', 'YES',   'YES';
        'UKUSI_SklId',          'YES', '(YES)', '';
        'UKTCC_SklId',          '',    '',      'YES';
        'UKZW_SklId',           'YES', '(YES)', '(YES)';
        'UKOD_SklId',           '',    'YES',   '';
        'UKEVA_SklId',          '',    'YES',   'YES';
        'UKHYB_SKLID',          '',    'YES',   'YES';
        'UKREV_SklId',          '',    'YES',   '';
        'UKN_SklIdRollout',     'YES', '',      '';
        'UKSNG_SklId',          '',    '',      'YES';
        'UKBSG_SklId',          'YES', '',      '';
        'UKLG_SklId',           'YES', '',      'YES';
        'UKADA_SklId',          '',    'YES',   '';
    };
    lutSklid = string(lut(:,1));

    % ── Normalise to 8 columns ────────────────────────────────────────────────
    nCols = size(origUK, 2);
    nRows = size(origUK, 1);

    if nCols < 5
        % Completely empty / degenerate — just ensure 8 cols exist
        for c = (nCols+1):8, origUK(:,c) = {''}; end
        return;
    end

    if nCols == 5
        % Old layout: UK Abbrev ID SKLID MapNums
        % Shift MapNums from col5 → col8, insert blank UL/USP/DSP
        origUK(:,8) = origUK(:,5);
        origUK(:,5) = {''};
        origUK(:,6) = {''};
        origUK(:,7) = {''};
    elseif nCols < 8
        for c = (nCols+1):8, origUK(:,c) = {''}; end
    end

    % ── Backfill UL/USP/DSP from LUT wherever empty ───────────────────────────
    sklids = string(origUK(:, 4));
    for r = 1:nRows
        needsFill = isempty(origUK{r,5}) || isempty(origUK{r,6}) || isempty(origUK{r,7});
        if ~needsFill, continue; end
        idx = find(strcmpi(lutSklid, sklids(r)), 1);
        if ~isempty(idx)
            if isempty(origUK{r,5}), origUK{r,5} = lut{idx,2}; end
            if isempty(origUK{r,6}), origUK{r,6} = lut{idx,3}; end
            if isempty(origUK{r,7}), origUK{r,7} = lut{idx,4}; end
        end
    end
end
function exportDyno(fig)
% EXPORTDYNO  Export Map A shift data + all editor tables + TCC curves to Excel.
%
% Sheet layout per map (sheet name = map name, max 31 chars):
%   Row  1     : Section header  "=== Shift Map: <mapName> ==="
%   Row  2     : Sub-header      "Pedal% vs Output Shaft RPM"
%   Row  3     : Column headers  Pedal% | 1->2 Up | 2->3 Up | ... | 2->1 Dn | ...
%   Rows 4..N  : Numeric data
%   Gap of 2 rows, then each of: Output RPM / MPH / KPH / Turbine RPM / Engine RPM
%   Gap of 2 rows, then TCC Curves table (if available)
%
% File memory: appData.dynoExportFile stores the chosen path between calls.
% If the same file is chosen again a new sheet is added; existing sheets kept.

    appData = fig.UserData;

    % ── 1. Get Map A ─────────────────────────────────────────────────────────
    mapName = '';
    wc = [];
    if ~isempty(appData.workingCopy)
        wc = appData.workingCopy;
        mapName = char(wc.name);
    elseif isfield(appData,'handles') && isfield(appData.handles,'dd1') && isvalid(appData.handles.dd1)
        mapName = char(appData.handles.dd1.Value);
        idx = find(strcmp(cellfun(@(m) char(m.name), appData.allMaps, 'UniformOutput', false), mapName), 1);
        if ~isempty(idx), wc = appData.allMaps{idx}; end
    end

    if isempty(wc)
        uialert(fig, 'No Map A is active. Select or edit a map first.', 'Dyno Export');
        return;
    end

    % ── 1b. Look up ALL UK matches for this map (mirrors main GUI panel logic) ──
    mapNumStr2 = regexp(mapName, 'SKL_GKF_(\d+)', 'tokens');
    dynoMapNum   = NaN;
    dynoSlopeTxt = '';    % Downhill / Flat / Uphill  (maps 0-24)
    dynoModeTxt  = '';    % Normal / Sport / Track etc (maps 0-24)
    dynoMatches  = {};    % Nx4: {ukName, sklid, idNum, idColor}  (maps 25+)

    if ~isempty(mapNumStr2)
        mn = str2double(mapNumStr2{1}{1});
        dynoMapNum = mn;
        if mn >= 0 && mn <= 24
            if mn<=4, dynoSlopeTxt='Downhill'; elseif mn<=9, dynoSlopeTxt='Flat'; else, dynoSlopeTxt='Uphill'; end
            if     ismember(mn,[1 6 11 16 21]), dynoModeTxt='Normal ADT';
            elseif ismember(mn,[3 8 13 18 23]), dynoModeTxt='Sport/Track ADT';
            elseif ismember(mn,[0 5 10 15 20]), dynoModeTxt='Normal';
            elseif ismember(mn,[2 7 12 17 22]), dynoModeTxt='Sport';
            elseif ismember(mn,[4 9 14 19 24]), dynoModeTxt='Track/Baja';
            end
        elseif mn >= 25 && isfield(appData,'ukData') && ~isempty(appData.ukData)
            ukD = appData.ukData;
            if size(ukD,2) < 8, ukD = ukEnsureULUSPDSP(ukD); appData.ukData = ukD; end
            for ukR = 1:size(ukD,1)
                if size(ukD,2) < 8, continue; end
                mnStr = string(ukD{ukR,8});
                if mnStr=="Not Found"||mnStr=="Empty", continue; end
                toks2 = strsplit(mnStr,',');
                if any(str2double(strtrim(toks2))==mn)
                    sk2   = char(ukD{ukR,4});
                    nm2   = char(ukD{ukR,1});
                    idN2  = str2double(string(ukD{ukR,3}));
                    if ~isnan(idN2) && isfield(appData,'statTabul') && ...
                            ~isempty(appData.statTabul) && ismember(idN2, appData.statTabul)
                        ic2 = 'green';
                    else
                        ic2 = 'yellow';
                    end
                    dynoMatches(end+1,:) = {nm2, sk2, idN2, ic2}; %#ok<AGROW>
                end
            end
        end
    end

    % ── 2. Compute all table data (same logic as updateTableDisplay) ──────────
    colHdr = {'Pedal %','1->2','2->3','3->4','4->5','5->6','6->7','7->8', ...
               '2->1','3->2','4->3','5->4','6->5','7->6','8->7'};

    pedalCol   = wc.pedal(:);
    dataRPM    = [pedalCol, round(wc.Z_up), round(wc.Z_down)];

    axleRatio  = appData.userInputs.AxleRatio;
    is4Lo      = isfield(appData,'handles') && isfield(appData.handles,'cb4Lo') ...
                 && isvalid(appData.handles.cb4Lo) && appData.handles.cb4Lo.Value;
    if is4Lo
        ratioEff = appData.userInputs.LowRangeRatio * axleRatio;
    else
        ratioEff = axleRatio;
    end
    if ratioEff == 0, ratioEff = 1; end
    tireCirc   = appData.userInputs.TireCircumference / 25.4;
    if tireCirc == 0, tireCirc = 1; end
    gearRatios = appData.userInputs.GearRatios;
    factorMPH  = (1 / ratioEff * tireCirc) / 1056;
    factorKPH  = factorMPH * 1.60934;

    dataMPH    = dataRPM;
    dataKPH    = dataRPM;
    dataTurbine= dataRPM;
    for c = 2:size(dataRPM,2)
        dataMPH(   :,c) = dataRPM(:,c) * factorMPH;
        dataKPH(   :,c) = dataRPM(:,c) * factorKPH;
        c_rpm = c - 1;
        if c_rpm <= 7, gearIdx = c_rpm; else, gearIdx = (c_rpm-7)+1; end
        if gearIdx >= 1 && gearIdx <= length(gearRatios)
            dataTurbine(:,c) = dataRPM(:,c) * gearRatios(gearIdx);
        end
    end
    dataMPH    = round(dataMPH, 2);
    dataKPH    = round(dataKPH, 2);
    dataTurbine= round(dataTurbine);
    dataEngine = dataTurbine;   % same calculation

    % ── 3. TCC Curves — computed directly from appData for Map A ─────────────
    % Mirrors updateTCCEditor logic exactly so TCC window does not need to be open.
    tccData   = [];
    tccColHdr = {};
    tccNote   = '(TCC data not available — CSV may not contain NWK/KWK tables)';
    try
        % Step A: get map number from Map A name  e.g. "SKL_GKF_5" → 5
        mapNumTok = regexp(mapName, 'SKL_GKF_(\d+)', 'tokens');
        if ~isempty(mapNumTok) && ~isempty(appData.wtZustand) && ~isempty(appData.kwkData) ...
                && isfield(appData,'nwkMaps') && ~isempty(appData.nwkMaps)

            activeMapID = str2double(mapNumTok{1}{1});

            % Step B: look up active state in wtZustand  (col1=mapID, col2=state)
            zData     = appData.wtZustand';   % same transpose as updateTCCEditor
            stateRow  = find(zData(:,1) == activeMapID, 1);
            if ~isempty(stateRow)
                activeState = zData(stateRow, 2);

                % Step C: get curve ID list from kwkData row = activeState+1
                kwkRow = activeState + 1;
                if kwkRow >= 1 && kwkRow <= size(appData.kwkData,1)
                    idList = appData.kwkData(kwkRow, :);
                    idList = unique(idList);
                    idList(idList == 0) = [];   % remove "No Curve" entries

                    % Step D: assemble curve columns from nwkMaps (same as updateTCCEditor)
                    combinedData = [];
                    colNames     = {'Pedal %'};
                    hasYAxis     = false;
                    for i = 1:length(idList)
                        prefix = string(idList(i)) + "_";
                        for m = 1:length(appData.nwkMaps)
                            nmap    = appData.nwkMaps(m);
                            headers = string(nmap.headers);
                            matchIdx = find(startsWith(headers, prefix, 'IgnoreCase', true));
                            if ~isempty(matchIdx)
                                colsData = nmap.data(:, matchIdx);
                                colsHead = headers(matchIdx);
                                if ~hasYAxis
                                    combinedData = nmap.yAxis;
                                    hasYAxis = true;
                                end
                                % Pad rows if needed
                                nR = size(combinedData,1);
                                nC = size(colsData,1);
                                if nC > nR
                                    combinedData = [combinedData; nan(nC-nR, size(combinedData,2))];
                                elseif nC < nR
                                    colsData = [colsData; nan(nR-nC, size(colsData,2))];
                                end
                                combinedData = [combinedData, colsData];
                                colNames     = [colNames, cellstr(colsHead)];
                                break;
                            end
                        end
                    end

                    if ~isempty(combinedData) && size(combinedData,2) > 1
                        tccData   = combinedData;
                        tccColHdr = colNames;
                        tccNote   = sprintf('Map %d  |  State %d  |  Curve IDs: %s', ...
                            activeMapID, activeState, num2str(idList));
                    else
                        tccNote = sprintf('Map %d  |  State %d — no matching NWK curve columns found', ...
                            activeMapID, activeState);
                    end
                else
                    tccNote = sprintf('Map %d — KWK row %d out of range (kwkData has %d rows)', ...
                        activeMapID, kwkRow, size(appData.kwkData,1));
                end
            else
                tccNote = sprintf('Map %d not found in WT_ZUSTAND table', activeMapID);
            end
        end
    catch ME_tcc
        tccNote = sprintf('TCC lookup error: %s', ME_tcc.message);
    end

    % ── 4. Resolve file path ─────────────────────────────────────────────────
    if isfield(appData,'dynoExportFile') && ~isempty(appData.dynoExportFile) ...
            && ~isempty(dir(appData.dynoExportFile))
        % Ask: use existing or choose new?
        ans2 = uiconfirm(fig, ...
            sprintf('Add sheet to existing file?\n%s', appData.dynoExportFile), ...
            'Dyno Export', 'Options', {'Add to Existing','Choose New File','Cancel'}, ...
            'DefaultOption', 1, 'CancelOption', 3);
        if strcmp(ans2, 'Cancel'), return; end
        if strcmp(ans2, 'Choose New File')
            appData.dynoExportFile = '';
        end
    end

    if ~isfield(appData,'dynoExportFile') || isempty(appData.dynoExportFile)
        defName = 'Dyno_Export.xlsx';
        [fn, fp] = uiputfile({'*.xlsx','Excel Workbook'}, 'Save Dyno Export As', defName);
        if isequal(fn,0), return; end
        appData.dynoExportFile = fullfile(fp,fn);
        fig.UserData = appData;
    end
    xlFile = appData.dynoExportFile;

    % ── 5. Build sheet name (Excel max 31 chars, no special chars) ───────────
    sheetName = regexprep(mapName, '[\\/:*?"\[\]]', '_');
    if strlength(sheetName) > 31, sheetName = sheetName(1:31); end
    if isempty(sheetName), sheetName = 'Map'; end

    % ── 6. Export plot to PNG (hidden temp figure, always works) ─────────────
    ui = appData.userInputs;
    is4Lo = isfield(appData,'handles') && isfield(appData.handles,'cb4Lo') ...
            && isvalid(appData.handles.cb4Lo) && appData.handles.cb4Lo.Value;

    [xlDir, xlBase, ~] = fileparts(xlFile);
    pngFile = fullfile(xlDir, sprintf('%s_%s.png', xlBase, sheetName));
    pngOK   = false;
    try
        % Build a hidden classic figure so exportgraphics works without UI restrictions
        tmpFig = figure('Visible','off','Color','w', ...
            'Position',[100 100 1100 600]);
        tmpAx  = axes(tmpFig, 'Position',[0.07 0.12 0.88 0.78]);
        hold(tmpAx,'on'); grid(tmpAx,'on');

        gearColors = lines(7);
        upStyles   = {'-o','-s','-^','-d','-v','-p','-h'};
        dnStyles   = {'--o','--s','--^','--d','--v','--p','--h'};
        gearLabels = {'1-2','2-3','3-4','4-5','5-6','6-7','7-8'};

        for g = 1:min(7, size(wc.Z_up,2))
            clr = gearColors(g,:);
            plot(tmpAx, wc.Z_up(:,g),   wc.pedal(:), upStyles{g}, ...
                'Color',clr,'LineWidth',1.4,'MarkerSize',5, ...
                'DisplayName',[gearLabels{g} ' Up']);
            plot(tmpAx, wc.Z_down(:,g), wc.pedal(:), dnStyles{g}, ...
                'Color',clr,'LineWidth',1.0,'MarkerSize',4, ...
                'DisplayName',[gearLabels{g} ' Dn']);
        end

        xlabel(tmpAx,'Output Shaft RPM','FontSize',11);
        ylabel(tmpAx,'Pedal (%)','FontSize',11);
        if is4Lo, tcSub = sprintf('4LO  (×%.3f)', ui.LowRangeRatio); else, tcSub = '4HI'; end; tcStr = sprintf('Transfer Case: %s', tcSub);
        title(tmpAx, sprintf('Shift Map: %s  |  Axle: %.3f  |  Tire: %.0f mm  |  %s', ...
            mapName, ui.AxleRatio, ui.TireCircumference, tcStr), 'FontSize',10);
        legend(tmpAx,'show','Location','eastoutside','FontSize',8,'NumColumns',2);
        xlim(tmpAx,[0, max([wc.Z_up(:); wc.Z_down(:)])*1.05]);
        ylim(tmpAx,[0 110]);

        exportgraphics(tmpFig, pngFile, 'Resolution',150);
        pngOK = true;
        close(tmpFig);
    catch ME_png
        try, close(tmpFig); catch, end
        % exportgraphics failed (common in compiled .exe) — fallback to getframe+imwrite
        try
            if isfield(appData,'handles') && isfield(appData.handles,'ax') && isvalid(appData.handles.ax)
                drawnow limitrate;
                frame = getframe(appData.handles.ax);
                imwrite(frame.cdata, pngFile);
                pngOK = true;
            end
        catch
        end
        if ~pngOK
            pngFile = sprintf('(plot export failed: %s)', ME_png.message);
        end
    end

    % ── 7. Write to Excel ─────────────────────────────────────────────────────
    try
        % Check / warn if sheet already exists
        if ~isempty(dir(xlFile))
            try, [~, existSheets] = xlsfinfo(xlFile); catch, existSheets = {}; end
            if any(strcmpi(existSheets, sheetName))
                ow = uiconfirm(fig, ...
                    sprintf('Sheet "%s" already exists.\nOverwrite it?', sheetName), ...
                    'Dyno Export','Options',{'Overwrite','Cancel'}, ...
                    'DefaultOption',1,'CancelOption',2);
                if strcmp(ow,'Cancel'), return; end
            end
        end

        % ── Row 1: "Dyno Export | mapName | date" ───────────────────────────────
        writecell({sprintf('Dyno Export  |  %s  |  %s', mapName, char(datetime('now','Format','yyyy-MM-dd HH:mm')))}, ...
            xlFile,'Sheet',sheetName,'Range','A1','AutoFitWidth',false);

        % ── Row 2+: detail rows written to separate cells for COM colouring ────
        % detailCells: {row, col, text, colourName}
        detailCells = {};
        curDetailRow = 2;
        colLetters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

        if ~isnan(dynoMapNum) && dynoMapNum >= 0 && dynoMapNum <= 24
            % Maps 0-24: slope (col A, blue) + mode (col B, mode colour)
            if ~isempty(dynoSlopeTxt)
                detailCells(end+1,:) = {curDetailRow, 1, dynoSlopeTxt, 'blue'};
                writecell({dynoSlopeTxt}, xlFile,'Sheet',sheetName,'Range',sprintf('A%d',curDetailRow),'AutoFitWidth',false);
            end
            if     ismember(dynoMapNum,[0 1 5 6 10 11 15 16 20 21]), modeClr='green';
            elseif ismember(dynoMapNum,[2 3 7 8 12 13 17 18 22 23]), modeClr='red';
            else,  modeClr='blue'; end
            if ~isempty(dynoModeTxt)
                detailCells(end+1,:) = {curDetailRow, 2, dynoModeTxt, modeClr};
                writecell({dynoModeTxt}, xlFile,'Sheet',sheetName,'Range',sprintf('B%d',curDetailRow),'AutoFitWidth',false);
            end
            curDetailRow = curDetailRow + 1;

        elseif ~isempty(dynoMatches)
            % Maps 25+: one row per unique UK name
            % Col A = UK name (purple), Col B+ alternating SKLID (blue) [ID] (green/#B8860B)
            seenNm = {};
            for dm = 1:size(dynoMatches,1)
                nm3 = dynoMatches{dm,1};
                if any(strcmp(seenNm, nm3)), continue; end
                seenNm{end+1} = nm3; %#ok<AGROW>
                % Col A: UK name in purple
                detailCells(end+1,:) = {curDetailRow, 1, nm3, 'purple'};
                writecell({nm3}, xlFile,'Sheet',sheetName,'Range',sprintf('A%d',curDetailRow),'AutoFitWidth',false);
                col3 = 2;
                for dm2 = 1:size(dynoMatches,1)
                    if ~strcmp(dynoMatches{dm2,1}, nm3), continue; end
                    sk3 = dynoMatches{dm2,2};
                    id3 = dynoMatches{dm2,3};
                    ic3 = dynoMatches{dm2,4};
                    % SKLID in blue
                    if col3 <= 26
                        detailCells(end+1,:) = {curDetailRow, col3, sk3, 'blue'};
                        writecell({sk3}, xlFile,'Sheet',sheetName,'Range',sprintf('%s%d',colLetters(col3),curDetailRow),'AutoFitWidth',false);
                        col3 = col3 + 1;
                    end
                    % [ID] in green or dark yellow
                    if ~isnan(id3) && col3 <= 26
                        if strcmp(ic3,'green'), idClr = 'green'; else, idClr = '#B8860B'; end
                        idTxt = sprintf('[%d]', id3);
                        detailCells(end+1,:) = {curDetailRow, col3, idTxt, idClr};
                        writecell({idTxt}, xlFile,'Sheet',sheetName,'Range',sprintf('%s%d',colLetters(col3),curDetailRow),'AutoFitWidth',false);
                        col3 = col3 + 1;
                    end
                end
                curDetailRow = curDetailRow + 1;
            end
        else
            detailCells(end+1,:) = {curDetailRow, 1, 'Not Defined', 'gray'};
            writecell({'Not Defined'}, xlFile,'Sheet',sheetName,'Range',sprintf('A%d',curDetailRow),'AutoFitWidth',false);
            curDetailRow = curDetailRow + 1;
        end

        % ── Next row: PNG path ────────────────────────────────────────────────
        writecell({sprintf('Plot: %s', pngFile)}, ...
            xlFile,'Sheet',sheetName,'Range',sprintf('A%d',curDetailRow),'AutoFitWidth',false);
        detailRowsUsed = curDetailRow;

        % ── Vehicle & Gear Ratio table (starts 2 rows after last detail row) ──────
        gr = ui.GearRatios;
        nG = length(gr);
        gearStartRow = detailRowsUsed + 2;
        gearHdrs = [{'Parameter','Value'}, arrayfun(@(g) sprintf('Gear %d',g), 1:nG, 'UniformOutput',false)];
        writecell(gearHdrs, xlFile,'Sheet',sheetName,'Range',sprintf('A%d',gearStartRow),'AutoFitWidth',false);
        writecell([{'Gear Ratio',''}, num2cell(gr)], ...
            xlFile,'Sheet',sheetName,'Range',sprintf('A%d',gearStartRow+1),'AutoFitWidth',false);
        overallHI = gr * ui.AxleRatio;
        writecell([{'Overall Ratio (4HI)','Axle x Gear'}, num2cell(round(overallHI,4))], ...
            xlFile,'Sheet',sheetName,'Range',sprintf('A%d',gearStartRow+2),'AutoFitWidth',false);
        overallLO = gr * ui.AxleRatio * ui.LowRangeRatio;
        writecell([{sprintf('Overall Ratio (4LO x%.3f)',ui.LowRangeRatio),'Axle x Gear x TC'}, ...
            num2cell(round(overallLO,4))], ...
            xlFile,'Sheet',sheetName,'Range',sprintf('A%d',gearStartRow+3),'AutoFitWidth',false);

        % Vehicle params block
        if is4Lo, tcAct = '4LO ACTIVE'; else, tcAct = '4HI active'; end
        paramRows = {
            'Axle Ratio',          sprintf('%.4f',      ui.AxleRatio);
            'Transfer Case Ratio', sprintf('%.4f  (%s)',ui.LowRangeRatio, tcAct);
            'Tire Circumference',  sprintf('%.0f mm',   ui.TireCircumference);
            'Tire Dynamic Radius', sprintf('%.1f mm',   ui.DynamicCircumference);
            'Idle RPM',            sprintf('%.0f',      ui.IdleRPM);
            'Max RPM',             sprintf('%.0f',      ui.MaxRPM);
            'Active Map',          mapName;
        };
        paramStartRow = gearStartRow + 5;
        writecell({'--- Vehicle Parameters ---',''}, ...
            xlFile,'Sheet',sheetName,'Range',sprintf('A%d',paramStartRow),'AutoFitWidth',false);
        for pr = 1:size(paramRows,1)
            writecell(paramRows(pr,:), xlFile,'Sheet',sheetName, ...
                'Range',sprintf('A%d',paramStartRow+pr),'AutoFitWidth',false);
        end

        % ── Data sections starting after param block ───────────────────────────
        row = paramStartRow + size(paramRows,1) + 3;
        row = dynoWriteSection(xlFile, sheetName, ...
            'Pedal% vs Output Shaft RPM', colHdr, dataRPM,     row);
        row = dynoWriteSection(xlFile, sheetName, ...
            'MPH  (Vehicle Speed - Miles/Hour)', colHdr, dataMPH, row);
        row = dynoWriteSection(xlFile, sheetName, ...
            'KPH  (Vehicle Speed - Km/Hour)',    colHdr, dataKPH, row);
        row = dynoWriteSection(xlFile, sheetName, ...
            'Turbine RPM  (Transmission Input Shaft)', colHdr, dataTurbine, row);
        row = dynoWriteSection(xlFile, sheetName, ...
            'Engine RPM  (Estimated Engine Speed)',    colHdr, dataEngine,  row);

        % TCC Curves section
        if ~isempty(tccData) && ~isempty(tccColHdr)
            hdrTCC = cellstr(string(tccColHdr(:)'));
            datTCC = tccData;
            if ~isnumeric(datTCC), datTCC = str2double(string(datTCC)); end
            row = dynoWriteSection(xlFile, sheetName, ...
                ['TCC Curves  |  ' tccNote], hdrTCC, datTCC, row);  %#ok<NASGU>
        else
            writecell({['TCC Curves  |  ' tccNote]}, xlFile,'Sheet',sheetName, ...
                'Range',sprintf('A%d',row),'AutoFitWidth',false);
            row = row + 2;  %#ok<NASGU>
        end

        % ── COM: cell colouring + PNG embed (Windows only) ─────────────────────
        imgEmbedMsg = '';
        if ispc
            try
                xlFileCOM  = strrep(char(java.io.File(xlFile).getAbsolutePath()), '/', '\');
                if pngOK
                    pngFileCOM = strrep(char(java.io.File(pngFile).getAbsolutePath()), '/', '\');
                else
                    pngFileCOM = '';
                end
                xlApp  = actxserver('Excel.Application');
                xlApp.Visible = false;
                xlWb   = xlApp.Workbooks.Open(xlFileCOM);
                shIdx  = 0;
                for si = 1:xlWb.Sheets.Count
                    if strcmpi(xlWb.Sheets.Item(si).Name, sheetName)
                        shIdx = si; break;
                    end
                end
                if shIdx > 0
                    xlSh = xlWb.Sheets.Item(shIdx);
                    r1 = xlSh.Range('A1');
                    r1.Interior.Color = 3100495;
                    r1.Font.Color     = 16777215;
                    r1.Font.Bold      = true;
                    r1.Font.Size      = 12;
                    colLetters2 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
                    for dci2 = 1:size(detailCells,1)
                        dcR2  = detailCells{dci2,1};
                        dcC2  = detailCells{dci2,2};
                        dcClr = lower(char(detailCells{dci2,4}));
                        if dcC2 > 26, continue; end
                        cel = xlSh.Range(sprintf('%s%d', colLetters2(dcC2), dcR2));
                        cel.Font.Bold = true;
                        cel.Font.Size = 10;
                        switch dcClr
                            case 'purple',   cel.Font.Color = 8388736;
                            case 'blue',     cel.Font.Color = 13395456;
                            case 'green',    cel.Font.Color = 32768;
                            case {'yellow','#b8860b'}, cel.Font.Color = 755384;
                            case 'red',      cel.Font.Color = 255;
                            case 'gray',     cel.Font.Color = 8421504;
                        end
                    end
                    if pngOK
                        anchorCell = xlSh.Range('P4');
                        xlSh.Shapes.AddPicture(pngFileCOM, 0, 1, ...
                            anchorCell.Left, anchorCell.Top, 520, 300);
                        imgEmbedMsg = '  (chart embedded in sheet)';
                    end
                end
                xlWb.Save(); xlWb.Close(false); xlApp.Quit();
                xlApp.delete();
            catch ME2
                try, xlWb.Close(false); catch; end
                try, xlApp.Quit(); xlApp.delete(); catch; end
                imgEmbedMsg = sprintf('\nCOM styling failed: %s', ME2.message);
            end
        elseif pngOK
            imgEmbedMsg = sprintf('\nChart saved separately: %s', pngFile);
        end

        fig.UserData = appData;
        uialert(fig, ...
            sprintf('Dyno Export complete!\n\nFile:  %s\nSheet: %s%s', ...
                xlFile, sheetName, imgEmbedMsg), ...
            'Dyno Export', 'Icon','success');

    catch ME
        uialert(fig, sprintf('Dyno Export failed:\n%s', ME.message), 'Dyno Export Error');
    end
end

function letter = xlColLetter(colNum)
% Convert a 1-based column number to an Excel column letter string.
% Examples: 1->'A', 26->'Z', 27->'AA', 703->'AAA'
% REQUIRED by exportUKTableToExcel for COM range addressing.
    letter = '';
    while colNum > 0
        rem_val = mod(colNum - 1, 26);
        letter  = [char(rem_val + 65), letter];  %#ok<AGROW>
        colNum  = floor((colNum - 1) / 26);
    end
end

function desc = getFSITDesc(varKey)
% Single source of truth for FSIT variable descriptions.
% Eliminates 5+ duplicate containers.Map builds across the codebase.
    persistent fsitMap;
    if isempty(fsitMap)
        fsitMap = containers.Map( ...
            {'FSIT_SWIFO','FSIT_SWIKE','FSIT_SWIDSD','FSIT_SWIBA','FSIT_SWIBE', ...
             'FSIT_SWIHM','FSIT_SWISUS','FSIT_SWIZW','FSIT_SWIVSA','FSIT_SWIECO', ...
             'FSIT_SWIFCO','FSIT_SWIWA','FSIT_SWISNG','FSIT_SWIEVA','FSIT_SWICM', ...
             'FSIT_SWISW_SWVrnt1','FSIT_SWISW_SWVrnt2','FSIT_SWISW_SWVrnt3', ...
             'FSIT_SWIOD','FSIT_SWIREV','FSIT_SWIWE','FSIT_SWIALT'}, ...
            {'ALL UKSVF_, UKBA_, UKUSI_, UKTOW_, UKCC_, UKOD_', ...
             'UKSVF_KD_, UKSVF_PBR_, UKSRS_*', ...
             'UKDSD_, UKSVF_DSD_, UKSRS_*', ...
             'UKBA_, UKSVF_BRAKE_, UKUSI_*', ...
             'UKBA_ENTRY_, UKSVF_BRAKE_ENTRY_', ...
             'UKBA_GRADE_, UKSVF_HILL_, UKUSI_*', ...
             'UKUSI_, UKBA_, UKTOW_*, UKOFFROAD_, UKLOW_', ...
             'UKTOW_, UKTOW_VSA_, UKOD_, UKUSI_', ...
             'UKVSA_, UKSVF_VSA_, UKTOW_VSA_*', ...
             'UKECO_, UKSVF_ECO_', ...
             'UKSVF_DFCO_, UKCC_DFCO_', ...
             'UKSVF_WARMUP_, UKUSI_WARM_', ...
             'UKWE_, UKSVF_SNOW_, UKUSI_*', ...
             'UKSVF_TQ_SCALE_, UKCC_TQ_SCALE_', ...
             'UKCL_, UKSVF_CLUTCH_PROT_, UKFO_BLOCK_*', ...
             'UKWARN_L1_, UKSVF_WARN_LIM_L1_', ...
             'UKWARN_L2_, UKSVF_WARN_LIM_L2_', ...
             'UKWARN_L3_, UKSVF_WARN_LIM_L3_, UKFO_BLOCK_*', ...
             'UKOD_, UKTOW_OD_, UKBA_OD_*', ...
             'UKREV_ (UK forward logic disabled)*', ...
             'UKWEATHER_, UKSVF_WEATHER_, UKUSI_*', ...
             'UKSVF_ALT_, UKCC_ALT_'});
    end
    if isKey(fsitMap, varKey), desc = fsitMap(varKey); else, desc = ''; end
end

function abbrevs = computeActiveAbbrevs(T)
% Compute active UK abbreviation tokens from FSIT switch values in T.
% Stored in appData.activeAbbrevs so all callers share one cached result.
    fsitVars = { ...
        'FSIT_SWIFO','FSIT_SWIKE','FSIT_SWIDSD','FSIT_SWIBA','FSIT_SWIBE', ...
        'FSIT_SWIHM','FSIT_SWISUS','FSIT_SWIZW','FSIT_SWIVSA','FSIT_SWIECO', ...
        'FSIT_SWIFCO','FSIT_SWIWA','FSIT_SWISNG','FSIT_SWIEVA','FSIT_SWICM', ...
        'FSIT_SWISW_SWVrnt1','FSIT_SWISW_SWVrnt2','FSIT_SWISW_SWVrnt3', ...
        'FSIT_SWIOD','FSIT_SWIREV','FSIT_SWIWE','FSIT_SWIALT' ...
    };
    % Pre-allocate result cell (max ~200 tokens) to avoid growing in loop
    allToks = cell(200, 1);  nToks = 0;
    for k = 1:length(fsitVars)
        vk = fsitVars{k};
        val = extractFSITValue(T, vk);
        if ~isnan(val) && val > 0
            desc = getFSITDesc(vk);
            if ~isempty(desc)
                toks = strtrim(split(desc, {',', ' ', '_'}));
                toks = toks(~cellfun('isempty', toks));
                n = numel(toks);
                if nToks + n > numel(allToks)
                    allToks{end + 200} = '';   % grow if needed
                end
                allToks(nToks+1 : nToks+n) = toks;
                nToks = nToks + n;
            end
        end
    end
    abbrevs = unique(allToks(1:nToks));
end

function nextR = dynoWriteSection(xlFile, sheet, label, hdr, datMat, startR)
% Write a labelled data block to an Excel sheet at a specific row.
% Returns the next free row (after data + 2 blank gap rows).
    % Section title
    writecell({label}, xlFile, 'Sheet', sheet, ...
        'Range', sprintf('A%d', startR), 'AutoFitWidth', false);
    % Column header row (ensure it is a 1×N cell row vector)
    writecell(hdr(:)', xlFile, 'Sheet', sheet, ...
        'Range', sprintf('A%d', startR+1), 'AutoFitWidth', false);
    % Numeric data block
    writematrix(datMat, xlFile, 'Sheet', sheet, ...
        'Range', sprintf('A%d', startR+2), 'AutoFitWidth', false);
    % Next free row = title(1) + header(1) + data(N) + 2 blank rows
    nextR = startR + 2 + size(datMat,1) + 2;
end
