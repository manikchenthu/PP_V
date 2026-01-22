function Pattern_plotter_V28_16_X_CM

    clearvars -except varargin; clc;
    
    % PERFORMANCE FIX: Force Hardware OpenGL for smoother 3D plots in .exe
    try opengl hardware; catch; end
    
    delete(findall(0, 'Name', 'Pattern Plotter V2.8.7.X.CM'));
    delete(findall(0, 'Name', 'TCC Editor'));
    delete(findall(0, 'Name', 'UK & STAT Table'));

    % === MAIN UI CREATION (Moved Up for Project Load Logic) ===
    fig = uifigure('Name', 'Pattern Plotter V2.8.7.X.CM', 'Position', [100 100 1200 800], 'CloseRequestFcn', @(src, event) closeMainApp(src));
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
                appData.handles = struct(); % Will be repopulated
                % Ensure history is clean or retained? Retain.
            else
                uialert(fig, 'Invalid Project File.', 'Error'); delete(fig); return;
            end
        catch ME
            uialert(fig, ['Error loading project: ' ME.message], 'Error'); delete(fig); return;
        end
        
    else
        % === NEW FROM CSV (Existing Logic) ===
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
        if isfile(prefFile)
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
            delete(fig); errordlg('User cancelled gear data input. Exiting.');
            return;
        end

        %% === Load CSV ===
        [filename, filepath] = uigetfile({'*.csv','CSV Files';'*.*','All Files'}, 'Select CSV');
        if isequal(filename, 0), delete(fig); return; end
        fullFilePath = fullfile(filepath, filename);
        if ~isfile(fullFilePath), delete(fig); errordlg('File not found.'); return; end

        opts = delimitedTextImportOptions("NumVariables", 122);
        opts.Delimiter = ["\t", ",", ";"];
        opts.VariableTypes = repmat("string", 1, 122);
        opts.ExtraColumnsRule = "ignore"; opts.EmptyLineRule = "read";
        opts = setvaropts(opts, opts.VariableNames, "WhitespaceRule", "preserve", "EmptyFieldRule", "auto");

        try
            T = readtable(fullFilePath, opts);
        catch ME
            delete(fig); errordlg(['Error reading CSV: ' ME.message]);
            return;
        end
        T = fillmissing(T, 'constant', "");

        %% === PRE-PROCESS TABLE (CLEANUP ONLY) ===
        T(startsWith(T.Var1, ["* format", "FUNCTION"], 'IgnoreCase', true), :) = [];
        filenameRow = T(1, :); filenameRow{1, :} = {''}; filenameRow{1, 1} = {filename};
        T = [filenameRow; T];

        % Convert numeric strings to actual numbers in the table cells
        for col = 1:width(T)
            numericValues = str2double(T{:, col}); isNumericMask = ~isnan(numericValues);
            T{isNumericMask, col} = num2cell(numericValues(isNumericMask));
        end
        
        %% === EXTRACT & VALIDATE PARAMETERS (Axle, Tire Circ) ===
    paramsUpdatedMsg = "";
    
    % Helper to extract single value from CSV (Function definition moved to end of file)

    % Capture Original Inputs for Comparison
    originalInputs = userInputs;

    % 1. Axle Ratio (Try multiple common keys including Final Drive)
    % Use partial match "FZGG_AxleRat" to handle variations like "FZGG_AxleRatMpgToldx"
    csvAxle = extractSingleParam(T, "FZGG_AxleRat", 'block');
    if isnan(csvAxle), csvAxle = extractSingleParam(T, "FZGG_RatFinalDrive", 'scalar'); end
    if isnan(csvAxle), csvAxle = extractSingleParam(T, "FZGG_AxleRatio", 'scalar'); end
    
    if ~isnan(csvAxle)
        if abs(userInputs.AxleRatio - csvAxle) > 0.001
            userInputs.AxleRatio = csvAxle;
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
        
        % If csvCirc also exists, check consistency? 
        % Generally Radius is "Dynamic Rolling Radius" which is key for speed calc.
        % We trust Radius over Circ if both are present but disagree, or sync them.
        
    elseif ~isnan(csvCirc)
        % Fallback: Radius not found, but Circumference found
        if csvCirc < 10, csvCirc = csvCirc * 1000; end
        
        if abs(userInputs.TireCircumference - csvCirc) > 1
            userInputs.TireCircumference = csvCirc;
            % Derive Radius
            userInputs.DynamicCircumference = csvCirc / (2 * pi);
        end
    end

    % 4. Low Range Ratio
    csvLow = extractSingleParam(T, "FZGG_RatLowRange", 'scalar');
    if isnan(csvLow), csvLow = extractSingleParam(T, "FZGG_RatioLowRange", 'scalar'); end
    
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
                       
    % Create Modal UIFIGURE
    % Centered and Resizable to prevent cutoff
    dVerify = uifigure('Name', 'Verify Parameters', 'Position', [100 100 550 600], 'WindowStyle', 'modal', 'Resize', 'on');
    movegui(dVerify, 'center');
    
    gVerify = uigridlayout(dVerify, [2, 1]);
    gVerify.RowHeight = {'1x', 50};
    
    lblMsg = uilabel(gVerify, 'Interpreter', 'html', 'Text', htmlMsg, 'VerticalAlignment', 'top');
    
    btnGrid = uigridlayout(gVerify, [1, 2]);
    btnGrid.Layout.Row = 2;
    
    btnCont = uibutton(btnGrid, 'Text', 'Continue', 'FontWeight', 'bold', 'BackgroundColor', [0.6 1 0.6], ...
        'ButtonPushedFcn', @(~,~) uiresume(dVerify));
    btnCont.Layout.Column = 1;
    
    btnCancel = uibutton(btnGrid, 'Text', 'Cancel', 'BackgroundColor', [1 0.8 0.8], ...
        'ButtonPushedFcn', @(~,~) delete(dVerify)); % Delete triggers close
    btnCancel.Layout.Column = 2;
    
    % Store selection in figure user data (default Cancel if closed)
    dVerify.UserData = 'Cancel';
    btnCont.ButtonPushedFcn = @(src,e) setSelection(dVerify, 'Continue');
    
    uiwait(dVerify);
    
    if ~isvalid(dVerify)
        % Window closed/deleted -> Cancel
        return; 
    end
    
    selection = dVerify.UserData;
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
        'Driving according to driver type', 'UKTYP', 1, 'UKTYP_SklId'; 'FastOff', 'UKFO', 3, 'UKFO_SklId'; 'Sequential Upshift', 'UKSUS', 4, 'UKSUS_SklId';
        'Curve', 'UKKE', 6, 'UKKE_SklId'; 'Program change function', 'UKPRW', 7, 'UKPRW_SklId'; 'Transmission control panel', 'UKGBF', 8, 'UKGBF_SklId';
        'Downhill', 'UKBA', 9, 'UKBA_SklId'; 'Winter (slip)', 'UKWE', 10, 'UKWE_SklId'; 'Tow/Haul', 'UKTOW', 11, 'UKTOW_SklId';
        'Spontaneous deceleration vehicle', 'UKSVF', 12, 'UKSVF_SklId'; 'ASC Mode', 'UKASC', 13, 'UKASC_SklId'; 'CDS Mode', 'UKCDS', 14, 'UKCDS_SklId';
        'Tip Mode', 'UKTIP', 15, 'TIPSKL_SklId'; 'Cruise Control', 'UKFGR', 16, 'UKFGR_SKLID'; 'Cruise Control', 'UKFGR', 16, 'UKFGR_SKLID_ACC';
        'Cruise Control', 'UKFGR', 16, 'UKFGR_SKLID_Vdiff'; 'Downshift Delay', 'UKDSD', 19, 'UKDSD_SklId'; 'Spontaneous downshift', 'UKSRS', 20, 'UKSRS_SKLID';
        'Spontaneous downshift', 'UKSRS', 20, 'UKSRS_SKLID_Lvl1'; 'Spontaneous downshift', 'UKSRS', 20, 'UKSRS_SklId_Lvl2'; 'Eco driving', 'UKECO', 21, 'UKECO_SklId';
        'Selector lever position', 'UKRPO', 22, 'UKRPO_SklId'; 'Extended downshift prevention /UKSW', 'UKSWG', 24, 'UKSWG_SKLID'; 'Low range', 'UKLOW', 27, 'UKLOW_SklId';
        'Gras/Gravel/Snow Mode', 'UKGGS', 28, 'UKGGS_SklId'; 'Gras/Gravel/Snow Mode', 'UKGGS', 28, 'UKGGS_SklIdLow'; 'Sand', 'UKSND', 30, 'UKSND_SklId';
        'Sand', 'UKSND', 30, 'UKSND_SklIdLow'; 'Cross Country or Mud/Ruts', 'UKXC', 31, 'UKXC_SklId'; 'Cross Country or Mud/Ruts', 'UKXC', 31, 'UKXC_SklIdLow';
        'Rock Crawl', 'UKRCK', 32, 'UKRCK_SklId'; 'Free Wheeling', 'UKFW', 34, 'UKFW_SklId'; 'End Of Line - Factory mode', 'UKEOL', 37, 'UKEOL_SklId';
        'Double downshift', 'UKDRS', 38, 'UKDRS_SklId'; 'Valet Mode', 'UKVAL', 39, 'UKVAL_SklId'; 'Cruise Control', 'UKCC', 44, 'UKCC_SklIdACC';
        'Cruise Control', 'UKCC', 44, 'UKCC_SklIdCC'; 'Cruise Control', 'UKCC', 44, 'UKCC_SklIdRRCC'; 'Cruise Control', 'UKCC', 44, 'UKCC_SklIdVDifACC';
        'Cruise Control', 'UKCC', 44, 'UKCC_SklIdVDifCC'; 'Cruise Control', 'UKCC', 44, 'UKCC_SklIdVDifRRCC'; 'Upshift interrupt', 'UKUSI', 45, 'UKUSI_SklId';
        'Torque Converter Clutch', 'UKTCC', 47, 'UKTCC_SklId'; 'Engine Speed Limitation', 'UKZW', 48, 'UKZW_SklId'; 'Overdrive', 'UKOD', 49, 'UKOD_SklId';
        'Electronic Valve Actuation', 'UKEVA', 50, 'UKEVA_SklId'; 'Hybrid Flow Manager', 'UKHYB', 51, 'UKHYB_SKLID'; 'Reverse Driving direction', 'UKREV', 59, 'UKREV_SklId';
        'Driving in position N', 'UKN', 60, 'UKN_SklIdRollout'; 'Stop And Go', 'UKSNG', 61, 'UKSNG_SklId'; 'Belt Starter Generator', 'UKBSG', 62, 'UKBSG_SklId';
        'Launch Gear', 'UKLG', 63, 'UKLG_SklId'; 'Adaption of Clutch', 'UKADA', 69, 'UKADA_SklId';
    };
    ukTableData(:, 5) = {'Not Found'};

    sCol2 = strtrim(string(T.Var2)); sCol1 = strtrim(string(T.Var1));
    for i = 1:size(ukTableData, 1)
        varName = ukTableData{i, 4}; rIdx = find(strcmpi(sCol2, varName), 1); if isempty(rIdx), rIdx = find(strcmpi(sCol1, varName), 1); end
        if ~isempty(rIdx)
            foundVals = []; currR = rIdx + 1; maxLookAhead = 50; safetyCtr = 0;
            while currR <= height(T) && safetyCtr < maxLookAhead
                raw1 = T{currR, 1}; if iscell(raw1), raw1 = raw1{1}; end; txt1 = strtrim(string(raw1));
                txt2 = ""; if width(T) >= 2, raw2 = T{currR, 2}; if iscell(raw2), raw2 = raw2{1}; end; txt2 = strtrim(string(raw2)); end
                isNewVar = false; if strlength(txt2) > 2 && ~startsWith(txt2, ":") && isnan(str2double(txt2)), if ~any(strcmpi(txt2, {'MAP','CURVE','Value','Label','Unit'})), isNewVar = true; end; end
                if isNewVar && safetyCtr > 0, break; end
                rowDat = string(table2cell(T(currR, :))); rowNums = str2double(rowDat); validNums = rowNums(~isnan(rowNums));
                if ~isempty(validNums), foundVals = [foundVals; validNums(:)]; end
                currR = currR + 1; safetyCtr = safetyCtr + 1;
            end
            if ~isempty(foundVals), ukTableData{i, 5} = char(strjoin(string(unique(foundVals)'), ', ')); else, ukTableData{i, 5} = 'Empty'; end
        end
    end
    %% === SHIFT COLUMNS (Must happen AFTER block extraction) ===
    if width(T) >= 2, T.Var2 = vertcat("", T.Var2(1:end-1)); end

    %% === EXTRACT MAIN SHIFT MAPS ===
    allMaps = {}; mapNames = {}; mapCount = 0; row = 1;
    while row <= height(T)
        label = string(strtrim(T.Var1(row))); mapName = string(T.Var2(row));
        if label == "MAP" && contains(mapName, "SKL_GKF_")
            mapCount = mapCount + 1; mapNames{mapCount} = mapName;
            rpmStart = row + 2; rpmEnd = rpmStart + 11;
            rpmData = T{rpmStart:rpmEnd, 3:16}; rpmMatrix = cellfun(@(x) safeToNum(x), rpmData);
            Z_up = rpmMatrix(:, 1:7); Z_down = rpmMatrix(:, 8:14);
            pedalRow = rpmEnd + 7; pedalRaw = T{pedalRow, 3:14}; pedal = cellfun(@(x) safeToNum(x), pedalRaw);
            allMaps{mapCount} = struct('name', mapName, 'Z_up', [Z_up(1,:); Z_up; Z_up(end,:)], ...
                'Z_down', [Z_down(1,:); Z_down; Z_down(end,:)], 'pedal', [0, pedal, 110], 'modified', false);
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
        mapNames = mapNames(sortedIdx); allMaps = allMaps(sortedIdx);
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
    appData.ukFig = gobjects(0);
    appData.tccFig = gobjects(0);
    appData.userInputs = userInputs;
    appData.workingCopy = []; appData.editIndex = -1; appData.history = {}; appData.lastSelectedIndices = [];
    appData.hysteresis = struct('Speed', 50, 'Pedal', 10, 'MPH', 2);
    appData.tableFig = gobjects(0); appData.tableHandle = gobjects(0); appData.infoLabel = gobjects(0);
    appData.sourceFilename = filename;
    
    end % End of "New from CSV" block

    % === COMMON UI INITIALIZATION ===
    if isempty(appData), delete(fig); return; end % Should not happen
    
    % Ensure mapNames exists (Derived from appData.allMaps)
    mapNames = string(cellfun(@(m) m.name, appData.allMaps, 'UniformOutput', false));
    if isempty(mapNames), mapNames = ["None"]; end

    % === MAIN GRID LAYOUT ===
    mainGrid = uigridlayout(fig, [4, 1]);
    mainGrid.RowHeight = {70, 100, '1x', 40}; % TopControls, ConfigPanels, Plot, Buttons
    mainGrid.Padding = [10 10 10 10];
    mainGrid.RowSpacing = 5;

    % --- ROW 1: TOP CONTROLS ---
    % Grid: 2 rows of controls.
    topPanel = uipanel(mainGrid, 'BorderType', 'none');
    topGrid = uigridlayout(topPanel, [2, 1]); 
    topGrid.RowHeight = {'1x', '1x'};
    topGrid.ColumnWidth = {'1x'};
    topGrid.Padding = [0 0 0 0];
    topGrid.RowSpacing = 0;

    % Row 1: Map Selection
    mapGrid = uigridlayout(topGrid, [1, 12]);
    % Cols: Spacer, Save, Load, Spacer, LabelA, DD A, CB A, LabelB, DD B, CB B, Spacer, Help
    mapGrid.ColumnWidth = {10, 100, 100, '1x', 'fit', 220, 'fit', 40, 'fit', 220, 'fit', '1x', 80};
    mapGrid.Padding = [0 5 0 0];
    mapGrid.Layout.Row = 1;

    uilabel(mapGrid, 'Text', ''); % Spacer
    
    % Save/Load Buttons (Top Left)
    uibutton(mapGrid, 'Text', 'Save Project', 'BackgroundColor', [0.9 0.9 0.9], 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~) saveProject(fig));
    uibutton(mapGrid, 'Text', 'Load Project', 'BackgroundColor', [0.9 0.9 0.9], 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~) loadProject(fig));
    
    % File Info Label
    fileLbl = uilabel(mapGrid, 'Text', 'No File Loaded', 'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'FontColor', [0.2 0.2 0.6]);
    
    uilabel(mapGrid, 'Text', 'Map A:', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    dd1 = uidropdown(mapGrid, 'Items', mapNames, 'BackgroundColor', [0.95 1 0.95]); 
    cb1 = uicheckbox(mapGrid, 'Text', 'Show', 'Value', true);
    
    uilabel(mapGrid, 'Text', ''); % Middle Spacer

    uilabel(mapGrid, 'Text', 'Map B:', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    dd2 = uidropdown(mapGrid, 'Items', mapNames, 'BackgroundColor', [1 0.95 0.95]); 
    cb2 = uicheckbox(mapGrid, 'Text', 'Show', 'Value', false);
    uilabel(mapGrid, 'Text', ''); % Spacer
    
    % Help Button (Right Corner)
    uibutton(mapGrid, 'Text', 'Help', 'BackgroundColor', [0.9 0.9 0.9], 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~) showHelp(fig));

    % Row 2: Options
    optGrid = uigridlayout(topGrid, [1, 11]);
    optGrid.ColumnWidth = {'1x', 'fit', 'fit', 'fit', 'fit', '2x', 'fit', 'fit', 'fit', 'fit', '1x'};
    optGrid.Padding = [0 0 0 5];
    optGrid.ColumnSpacing = 15;
    optGrid.Layout.Row = 2;

    uilabel(optGrid, 'Text', ''); % Spacer
    
    % Map A Options
    cbEdit = uicheckbox(optGrid, 'Text', 'âœï¸ Edit Map A', 'Value', true);
    cbAllowY = uicheckbox(optGrid, 'Text', 'Allow Y-axis Edit', 'Value', false);
    
    uilabel(optGrid, 'Text', '2nd Axis:', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    ddAxis = uidropdown(optGrid, 'Items', {'None', 'MPH', 'KPH'}, 'Value', 'None', 'BackgroundColor', [1 1 0.9]);
    uilabel(optGrid, 'Text', ''); % Middle Spacer

    % Global Options
    cb4Lo = uicheckbox(optGrid, 'Text', '4Lo Mode', 'Value', false);
    cbLines = uicheckbox(optGrid, 'Text', 'Show Shift Lines', 'Value', true);
    cbTCC = uicheckbox(optGrid, 'Text', 'Show TCC', 'Value', false);
    cbLegend = uicheckbox(optGrid, 'Text', 'Show Legend', 'Value', true);
    
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
    for i = 1:7
        c = uicheckbox(plGrid, "Text", upGears{i}, "Value", true);
        c.Layout.Row = 1; c.Layout.Column = i;
        gearChecks(upGears{i}) = c;
        
        c = uicheckbox(plGrid, "Text", downGears{i}, "Value", true);
        c.Layout.Row = 2; c.Layout.Column = i;
        gearChecks(downGears{i}) = c;
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
    for i = 1:8
        % Map A (Row 1)
        c = uicheckbox(ptGrid, "Text", ["G" num2str(i)], "Value", true);
        c.Layout.Row = 1; c.Layout.Column = i;
        tccChecksA(num2str(i)) = c;
        
        % Map B (Row 2)
        c = uicheckbox(ptGrid, "Text", ["G" num2str(i)], "Value", true);
        c.Layout.Row = 2; c.Layout.Column = i;
        tccChecksB(num2str(i)) = c;
    end

    % Panel 3: Context Info
    appData.contextLabel = uilabel(configGrid, 'HorizontalAlignment', 'center', ...
        'FontSize', 12, 'Interpreter', 'html', 'Text', '<b>Select a Map...</b>', 'BackgroundColor', [0.94 0.94 0.94]);
    appData.contextLabel.Layout.Row = 1; appData.contextLabel.Layout.Column = 3;
    
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

    hold(ax, 'on');

    vLine = plot(ax, [-100 -100], ylim(ax), '--k', 'Tag', 'permCrosshair', 'PickableParts', 'none', 'HitTest', 'off', 'HandleVisibility', 'off');
    hLine = plot(ax, xlim(ax), [-100 -100], '--k', 'Tag', 'permCrosshair', 'PickableParts', 'none', 'HitTest', 'off', 'HandleVisibility', 'off');
    crossText = text(ax, 0, 0, '', 'BackgroundColor', 'w', 'EdgeColor', 'k', 'Visible', 'off', 'Tag', 'permCrosshair', 'PickableParts', 'none', 'Interpreter', 'tex');

    legendPanel = uipanel(plotGrid, 'Title', 'Legend', 'Scrollable', 'on');
    
    % === CONTEXT MENU ===
    refreshCM = uicontextmenu(fig);
    uimenu(refreshCM, 'Text', 'Refresh Plot', 'MenuSelectedFcn', @(~,~) updatePlot(fig));
    ax.ContextMenu = refreshCM;

    % --- ROW 4: BUTTONS ---
    btnGrid = uigridlayout(mainGrid, [1, 8]);
    btnGrid.Padding = [0 0 0 0];
    
    buttonStyle = {'BackgroundColor', [0.9 0.95 1], 'FontWeight', 'bold'};
    uibutton(btnGrid, 'Text', 'Save Modified Map', buttonStyle{:}, 'ButtonPushedFcn', @(~,~) saveModifiedMap(fig));
    uibutton(btnGrid, 'Text', 'Export', buttonStyle{:}, 'ButtonPushedFcn', @(~,~) exportHandler(fig));
    uibutton(btnGrid, 'Text', 'Edit Map A', buttonStyle{:}, 'ButtonPushedFcn', @(~,~) openTableEditor(fig));
    uibutton(btnGrid, 'Text', 'Edit Multi Maps', buttonStyle{:}, 'ButtonPushedFcn', @(~,~) openMultiMapEditor(fig));
    uibutton(btnGrid, 'Text', 'STAT & UK Table', buttonStyle{:}, 'ButtonPushedFcn', @(~,~) openUKTable(fig));
    uibutton(btnGrid, 'Text', 'TCC Editor', buttonStyle{:},'ButtonPushedFcn', @(~,~) openTCCEditor(fig));
    uibutton(btnGrid, 'Text', 'Interpolation', buttonStyle{:},'ButtonPushedFcn', @(~,~) Intermaps(fig));
    uibutton(btnGrid, 'Text', '2D & 3D Plots', buttonStyle{:},'ButtonPushedFcn', @(~,~) Genplots(fig));

    % === HANDLES & CALLBACKS ===
    handles = struct('ax', ax, 'ax2', ax2, 'ax3', ax3, 'vLine', vLine, 'hLine', hLine, 'crossText', crossText, 'legendPanel', legendPanel);
    handles.refreshCM = refreshCM;
    handles.fileLabel = fileLbl;
    handles.dd1 = dd1; handles.dd2 = dd2; handles.cb1 = cb1; handles.cb2 = cb2;
    handles.cbEdit = cbEdit; handles.cbAllowY = cbAllowY; handles.cb4Lo = cb4Lo; handles.cbLines = cbLines; handles.cbTCC = cbTCC;
    handles.cbLegend = cbLegend;
    handles.ddAxis = ddAxis;
    handles.gearChecks = gearChecks;
    handles.tccChecksA = tccChecksA;
    handles.tccChecksB = tccChecksB;
    handles.plotGrid = plotGrid; % Save grid handle for toggling

    appData.handles = handles; appData.currentMapName = dd1.Value; 
    
    % Update File Label
    if isfield(appData, 'sourceFilename')
        handles.fileLabel.Text = ['Loaded: ' appData.sourceFilename];
    else
        handles.fileLabel.Text = 'Loaded: Project';
    end
    
    fig.UserData = appData;

    % Callbacks
    updateWrap = @(~,~) updatePlot(fig);
    
    dd1.ValueChangedFcn = @(src, event) checkMapSwitch(fig, src, event);
    dd2.ValueChangedFcn = updateWrap; 
    cb1.ValueChangedFcn = updateWrap; cb2.ValueChangedFcn = updateWrap;
    cbEdit.ValueChangedFcn = updateWrap; cbLines.ValueChangedFcn = updateWrap; cb4Lo.ValueChangedFcn = updateWrap;
    cbTCC.ValueChangedFcn = updateWrap;
    ddAxis.ValueChangedFcn = updateWrap;
    
    % Legend Toggle Callback
    cbLegend.ValueChangedFcn = @(src, event) toggleLegendLayout(fig, src.Value);
    
    % Connect Gear Checks
    keysG = gearChecks.keys;
    for i=1:length(keysG)
        cb = gearChecks(keysG{i});
        cb.ValueChangedFcn = updateWrap; 
    end
    
    % Connect TCC Checks
    keysTA = tccChecksA.keys;
    for i=1:length(keysTA)
        cb = tccChecksA(keysTA{i});
        cb.ValueChangedFcn = updateWrap; 
    end
    keysTB = tccChecksB.keys;
    for i=1:length(keysTB)
        cb = tccChecksB(keysTB{i});
        cb.ValueChangedFcn = updateWrap; 
    end

    fig.WindowButtonMotionFcn = @(src, event) passiveCrosshair(fig);
    fig.WindowKeyPressFcn = @(src, event) onKeyPress(fig, event);

    updatePlot(fig);
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
    if isfield(appData, 'ukFig') && ~isempty(appData.ukFig) && isvalid(appData.ukFig), figure(appData.ukFig); return; end
    ukFig = uifigure('Name', 'UK & STAT Table', 'Position', [150 150 900 650]);
    ukFig.CloseRequestFcn = @(src,e) delete(src);
    ukFig.WindowKeyPressFcn = @(src,e) onUKKeyPress(fig, e);
    appData.ukFig = ukFig;

    appData.ukHistory = {}; appData.statShadowData = appData.statTabul;
    fig.UserData = appData;

    gl = uigridlayout(ukFig, [1 1]); tg = uitabgroup(gl);
    
    % === PRE-PROCESS FSIT DATA FOR UK TABLE LOGIC ===
    % Define FSIT Variables List
    fsitVars = { ...
        'FSIT_SWIFO', 'FSIT_SWIKE', 'FSIT_SWIDSD', 'FSIT_SWIBA', 'FSIT_SWIBE', ...
        'FSIT_SWIHM', 'FSIT_SWISUS', 'FSIT_SWIZW', 'FSIT_SWIVSA', 'FSIT_SWIECO', ...
        'FSIT_SWIFCO', 'FSIT_SWIWA', 'FSIT_SWISNG', 'FSIT_SWIEVA', 'FSIT_SWICM', ...
        'FSIT_SWISW_SWVrnt1', 'FSIT_SWISW_SWVrnt2', 'FSIT_SWISW_SWVrnt3', ...
        'FSIT_SWIOD', 'FSIT_SWIREV', 'FSIT_SWISUS', 'FSIT_SWIWE', 'FSIT_SWIALT' ...
    };
    fsitVars = unique(fsitVars, 'stable');
    
    % FSIT Description Map
    fsitDescMap = containers.Map();
    fsitDescMap('FSIT_SWIFO') = 'ALL UKSVF_, UKBA_, UKUSI_, UKTOW_, UKCC_, UKOD_';
    fsitDescMap('FSIT_SWIKE') = 'UKSVF_KD_, UKSVF_PBR_, UKSRS_*';
    fsitDescMap('FSIT_SWIDSD') = 'UKDSD_, UKSVF_DSD_, UKSRS_*';
    fsitDescMap('FSIT_SWIBA') = 'UKBA_, UKSVF_BRAKE_, UKUSI_*';
    fsitDescMap('FSIT_SWIBE') = 'UKBA_ENTRY_, UKSVF_BRAKE_ENTRY_';
    fsitDescMap('FSIT_SWIHM') = 'UKBA_GRADE_, UKSVF_HILL_, UKUSI_*';
    fsitDescMap('FSIT_SWISUS') = 'UKUSI_, UKBA_, UKTOW_*, UKOFFROAD_, UKLOW_'; 
    fsitDescMap('FSIT_SWIZW') = 'UKTOW_, UKTOW_VSA_, UKOD_, UKUSI_';
    fsitDescMap('FSIT_SWIVSA') = 'UKVSA_, UKSVF_VSA_, UKTOW_VSA_*';
    fsitDescMap('FSIT_SWIECO') = 'UKECO_, UKSVF_ECO_';
    fsitDescMap('FSIT_SWIFCO') = 'UKSVF_DFCO_, UKCC_DFCO_';
    fsitDescMap('FSIT_SWIWA') = 'UKSVF_WARMUP_, UKUSI_WARM_';
    fsitDescMap('FSIT_SWISNG') = 'UKWE_, UKSVF_SNOW_, UKUSI_*';
    fsitDescMap('FSIT_SWIEVA') = 'UKSVF_TQ_SCALE_, UKCC_TQ_SCALE_';
    fsitDescMap('FSIT_SWICM') = 'UKCL_, UKSVF_CLUTCH_PROT_, UKFO_BLOCK_*';
    fsitDescMap('FSIT_SWISW_SWVrnt1') = 'UKWARN_L1_, UKSVF_WARN_LIM_L1_';
    fsitDescMap('FSIT_SWISW_SWVrnt2') = 'UKWARN_L2_, UKSVF_WARN_LIM_L2_';
    fsitDescMap('FSIT_SWISW_SWVrnt3') = 'UKWARN_L3_, UKSVF_WARN_LIM_L3_, UKFO_BLOCK_*';
    fsitDescMap('FSIT_SWIOD') = 'UKOD_, UKTOW_OD_, UKBA_OD_*';
    fsitDescMap('FSIT_SWIREV') = 'UKREV_ (UK forward logic disabled)*';
    fsitDescMap('FSIT_SWIWE') = 'UKWEATHER_, UKSVF_WEATHER_, UKUSI_*';
    fsitDescMap('FSIT_SWIALT') = 'UKSVF_ALT_, UKCC_ALT_';

    fsitData = cell(length(fsitVars), 3);
    activeAbbrevs = {};
    
    for k = 1:length(fsitVars)
        varKey = fsitVars{k};
        fsitData{k, 1} = varKey;
        val = extractFSITValue(appData.T, varKey);
        fsitData{k, 2} = val;
        
        desc = '';
        if isKey(fsitDescMap, varKey)
            desc = fsitDescMap(varKey);
            fsitData{k, 3} = desc;
        end
        
        if ~isnan(val) && val > 0 && ~isempty(desc)
            tokens = strtrim(split(desc, {',', ' ', '_'}));
            activeAbbrevs = [activeAbbrevs; tokens];
        end
    end
    activeAbbrevs = unique(activeAbbrevs);

    % === PRE-PROCESS UK TABLE DATA ===
    origUK = appData.ukData;
    newUK = cell(size(origUK, 1), 6);
    newUK(:, [1, 2, 4, 5, 6]) = origUK(:, [1, 2, 3, 4, 5]); 
    
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
    pnlFilter = uipanel(gl1); flayout = uigridlayout(pnlFilter, [1 2]); flayout.ColumnWidth = {100, 200};
    uilabel(flayout, 'Text', 'Filter by SKLID:', 'FontWeight', 'bold', 'HorizontalAlignment', 'right');
    efFilter = uieditfield(flayout, 'text', 'ValueChangedFcn', @(src,e) updateUKTableStyles(src, ukFig, fig));
    
    tUK = uitable(gl1, 'Data', newUK, ...
        'ColumnName', {'UK', 'Abbrev', 'FSIT_Act', 'ID', 'SKLID', 'Map Number'}, ...
        'CellSelectionCallback', @(src, e) onUKTableSelect(src, e, fig));
    tUK.ColumnWidth = {220, 80, 70, 40, 150, '1x'};
    
    tab2 = uitab(tg, 'Title', 'STAT_TABUL'); gl2 = uigridlayout(tab2, [2 1]); gl2.RowHeight = {40, '1x'};

    pnlStatTools = uipanel(gl2);
    statLayout = uigridlayout(pnlStatTools, [1 2]); statLayout.ColumnWidth = {200, '1x'}; statLayout.Padding = [5 5 5 5];
    uibutton(statLayout, 'Text', 'SAVE CHANGES', 'BackgroundColor', [1 0.8 0], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) saveStatChanges(ukFig, fig));

    rowsVar = appData.statRowNames; if length(rowsVar) < size(appData.statTabul,1), rowsVar = [rowsVar; repmat({''}, size(appData.statTabul,1)-length(rowsVar),1)]; end
    % Generate 0-based RowNames
    rowNames0 = cellstr(string(0 : size(appData.statTabul,1)-1));
    tStat = uitable(gl2, 'Data', [rowsVar, num2cell(appData.statTabul)], ...
        'ColumnName', [{'Mode'}, cellstr(string(1:size(appData.statTabul,2)))], ...
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

    ukFig.UserData = struct('tUK', tUK, 'tStat', tStat, 'tFSIT', tFSIT, 'filterField', efFilter, 'statSelection', [], 'fsitSelection', [], 'fullDisplayData', {newUK}); updateUKTableStyles(efFilter, ukFig, fig);
end

function onFSITEdit(src, event)
    addStyle(src, uistyle('BackgroundColor', [1 1 0], 'FontWeight', 'bold'), 'cell', event.Indices);
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
    addStyle(tFSIT, uistyle('BackgroundColor', [1 1 0], 'FontWeight', 'bold'), 'cell', sel);
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
    
    appData.T = T; mainFig.UserData = appData;
    removeStyle(tFSIT);
    
    % Refresh FSIT Status in UK Table
    refreshFSITStatus(ukFig, mainFig);
    
    uialert(ukFig, 'FSIT Variables Saved.', 'Success');
end

function refreshFSITStatus(ukFig, mainFig)
    h = ukFig.UserData;
    tFSIT = h.tFSIT;
    fsitData = tFSIT.Data;
    
    % Re-calculate active abbreviations
    activeAbbrevs = {};
    for k = 1:size(fsitData, 1)
        val = fsitData{k, 2};
        desc = fsitData{k, 3};
        
        if ~isnan(val) && val > 0 && ~isempty(desc)
            tokens = strtrim(split(desc, {',', ' ', '_'}));
            activeAbbrevs = [activeAbbrevs; tokens];
        end
    end
    activeAbbrevs = unique(activeAbbrevs);
    
    % Update fullDisplayData
    fullData = h.fullDisplayData;
    for i = 1:size(fullData, 1)
        abbrev = fullData{i, 2};
        match = false;
        for j = 1:length(activeAbbrevs)
            token = activeAbbrevs{j};
            if ~isempty(token) && contains(abbrev, token, 'IgnoreCase', true)
                match = true;
                break;
            end
        end
        
        if match
            fullData{i, 3} = 'Yes';
        else
            fullData{i, 3} = 'No';
        end
    end
    
    h.fullDisplayData = fullData;
    ukFig.UserData = h;
    
    % Refresh View
    updateUKTableStyles(h.filterField, ukFig, mainFig); % Access main fig via hierarchy or passed arg? 
    % Wait, mainFig is not stored in ukFig.UserData. But updateUKTableStyles needs mainFig for appData.
    % We can pass mainFig to refreshFSITStatus or retrieve it.
    % In saveFSITChanges, we have mainFig.
    % But updateUKTableStyles signature is (src, ukFig, mainFig).
    % Let's retrieve mainFig from ukFig's creator if possible, or pass it.
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

function success = saveProject(fig)
    success = false;
    appData = fig.UserData;
    [file, path] = uiputfile('*.mat', 'Save Project As');
    if isequal(file, 0), return; end
    
    % Prepare data to save (strip handles)
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
    if isfield(saveStruct.appData, 'tableAx'), saveStruct.appData = rmfield(saveStruct.appData, 'tableAx'); end
    
    try
        save(fullfile(path, file), '-struct', 'saveStruct');
        uialert(fig, 'Project Saved Successfully.', 'Success');
        success = true;
    catch ME
        uialert(fig, ['Error Saving: ' ME.message], 'Error');
    end
end

function loadProject(fig)
    selection = uiconfirm(fig, 'Do you want to save the current project before loading a new one?', 'Load Project', ...
        'Options', {'Yes', 'No', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'question');
    
    if strcmp(selection, 'Cancel')
        return;
    elseif strcmp(selection, 'Yes')
        saved = saveProject(fig);
        if ~saved
            return; % Abort if save failed or cancelled
        end
    end
    
    [f, p] = uigetfile('*.mat', 'Select Project File');
    if isequal(f, 0) || ~isvalid(fig), return; end
    
    try
        loaded = load(fullfile(p, f));
        if ~isfield(loaded, 'appData'), uialert(fig, 'Invalid Project File.', 'Error'); return; end
        
        newAppData = loaded.appData;
        
        % Close sub-windows
        % Do NOT call closeMainApp(fig) as it deletes the figure itself
        
        oldAppData = fig.UserData;
        if isfield(oldAppData, 'ukFig') && ~isempty(oldAppData.ukFig) && isvalid(oldAppData.ukFig), delete(oldAppData.ukFig); end
        if isfield(oldAppData, 'tccFig') && ~isempty(oldAppData.tccFig) && isvalid(oldAppData.tccFig), delete(oldAppData.tccFig); end
        if isfield(oldAppData, 'tableFig') && ~isempty(oldAppData.tableFig) && isvalid(oldAppData.tableFig), delete(oldAppData.tableFig); end
        
        % Restore handles from current session
        newAppData.handles = oldAppData.handles;
        newAppData.ukFig = gobjects(0);
        newAppData.tccFig = gobjects(0);
        newAppData.tableFig = gobjects(0);
        newAppData.tableHandle = gobjects(0);
        newAppData.infoLabel = gobjects(0);
        newAppData.contextLabel = oldAppData.contextLabel; % Restore label handle
        
        % Save filename
        newAppData.sourceFilename = f;
        
        fig.UserData = newAppData;
        
        % Refresh UI
        h = newAppData.handles;
        h.fileLabel.Text = ['Loaded: ' f];
        
        % Update Map Dropdowns
        mapNames = string(cellfun(@(m) m.name, newAppData.allMaps, 'UniformOutput', false));
        if isempty(mapNames), mapNames = ["None"]; end
        
        h = newAppData.handles;
        h.dd1.Items = mapNames; 
        h.dd2.Items = mapNames;
        
        % Set Values (Check if valid)
        if ~ismember(newAppData.currentMapName, mapNames)
             if ~isempty(mapNames), newAppData.currentMapName = mapNames(1); end
        end
        h.dd1.Value = newAppData.currentMapName;
        
        % We might need to update 2nd map choice too? 
        % Just default or keep as is? Keep as is if valid.
        if ~ismember(h.dd2.Value, mapNames) && ~isempty(mapNames), h.dd2.Value = mapNames(1); end
        
        fig.UserData = newAppData;
        
        % Update Plot
        updatePlot(fig);
        updateContextPanel(fig);
        
        uialert(fig, 'Project Loaded.', 'Success');
        
    catch ME
        if isvalid(fig), uialert(fig, ['Error Loading: ' ME.message], 'Error'); end
    end
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

    addStyle(tStat, uistyle('BackgroundColor',[1 1 0], 'FontWeight', 'bold'), 'cell', sel);
end
function updateUKTableStyles(src, ukFig, mainFig)
    appData = mainFig.UserData; h = ukFig.UserData; tUK = h.tUK; tStat = h.tStat; filterVal = strtrim(src.Value);
    statMatrix = []; if isfield(appData, 'statTabul'), statMatrix = appData.statTabul; end

    % Check if we have the new fullDisplayData (6 columns)
    % Ensure h is scalar to avoid "Too many input arguments" for isempty if h is a struct array
    hasFullData = false;
    if isscalar(h) && isfield(h, 'fullDisplayData')
        hasFullData = ~isempty(h.fullDisplayData);
    elseif isstruct(h) && numel(h) > 1 && isfield(h, 'fullDisplayData')
        % If h somehow became an array, take the first one
        hasFullData = ~isempty(h(1).fullDisplayData);
        h = h(1); % Enforce scalar for subsequent access
    end

    if hasFullData
        sourceData = h.fullDisplayData;
        colID = 4; colName = 5; colVal = 6; colFSIT = 3;
    else
        % Fallback for safety
        sourceData = appData.ukData;
        colID = 3; colName = 4; colVal = 5; colFSIT = 0;
    end

    % 1. Filter Logic & ID Extraction
    filteredIDs = [];
    if isempty(filterVal)
        tUK.Data = sourceData;
    else
        % Filter by SKLID (colName) using 'startsWith'
        rawSklIdData = string(sourceData(:, colName));
        idx = startsWith(rawSklIdData, filterVal, 'IgnoreCase', true);
        tUK.Data = sourceData(idx, :);

        % Extract IDs
        rawIDs = tUK.Data(:, colID);
        for k = 1:length(rawIDs)
            val = str2double(string(rawIDs{k}));
            if ~isnan(val), filteredIDs(end+1) = val; end
        end
    end

    % 2. Style UK Table
    removeStyle(tUK);
    for i=1:size(tUK.Data,1)
        if strcmp(tUK.Data{i, colVal}, 'Not Found')
            addStyle(tUK, uistyle('FontColor',[0.6 0.6 0.6]), 'row', i);
        else
            % Highlight Name Column (was Col 4, now Col 5)
            addStyle(tUK, uistyle('FontColor','blue','FontWeight','bold'), 'cell', [i, colName]);
            
            % Highlight ID Column (was Col 3, now Col 4)
            id = str2double(string(tUK.Data{i, colID}));
            if ~isnan(id) && ismember(id, statMatrix)
                addStyle(tUK, uistyle('BackgroundColor',[0.8 1 0.8]), 'cell', [i, colID]);
            else
                addStyle(tUK, uistyle('BackgroundColor',[1 1 0.8]), 'cell', [i, colID]);
            end
        end
        
        % Highlight FSIT_Act Column (Col 3) if active - ALWAYS CHECK regardless of Found status
        if colFSIT > 0
            valFSIT = string(tUK.Data{i, colFSIT});
            if strcmpi(valFSIT, 'Yes')
                 addStyle(tUK, uistyle('BackgroundColor', [0.4 0.6 1], 'FontColor', 'black', 'FontWeight', 'bold'), 'cell', [i, colFSIT]);
            end
        end
    end

    % 3. Style STAT_TABUL
    removeStyle(tStat);
    if ~isempty(filteredIDs)
        statData = appData.statTabul;
        [r, c] = find(ismember(statData, filteredIDs));
        if ~isempty(r)
            uiCols = c + 1;
            sHighlight = uistyle('BackgroundColor', [0 1 1], 'FontWeight', 'bold');
            addStyle(tStat, sHighlight, 'cell', [r, uiCols]);
            scroll(tStat, 'cell', [r(1), uiCols(1)]);
        end
    end
end

function showHelp(fig)
    % 1. Create the main modal window
    d = uifigure('Name', 'Help & Credits', ...
        'Position', [100 100 550 500], ...
        'WindowStyle', 'modal', ...
        'Resize', 'off', ...
        'Color', [1 1 1]); 
    movegui(d, 'center');

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
        'â€¢ Kyle Schumaker\n' ...
        'â€¢ Javed Dada\n' ...
        'â€¢ Anthony Bootka\n' ...
        'â€¢ Paul Tuttle\n' ...
        'â€¢ Stephen Arno\n' ...
        'â€¢ Dustin Kolodge \n' ...
        'â€¢ Joonhyuck Kim\n' ...
        'â€¢ Uzair Mazhar\n' ...
        'â€¢ Maneesh Mallikarjunaswamy\n' ...
        'â€¢ Krishna Soundarajan']);
    
    txtThanks = uitextarea(t2Grid);
    txtThanks.Value = split(namesList, newline);
    txtThanks.Editable = 'off';
    txtThanks.FontSize = 16;
    txtThanks.FontName = 'Segoe UI'; % Clean font
    txtThanks.HorizontalAlignment = 'center';
    txtThanks.BackgroundColor = [1 1 1];
    % Remove border visually by matching color if desired, or keep default

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
    % NESTED HELPER FUNCTION
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

end
function onStatEdit(fig, src, event)
    appData = fig.UserData; appData.ukHistory{end+1} = appData.statShadowData;
    if length(appData.ukHistory) > 20, appData.ukHistory(1) = []; end
    fullData = src.Data; numericPart = cell2mat(fullData(:, 2:end)); appData.statShadowData = numericPart;
    fig.UserData = appData; addStyle(src, uistyle('BackgroundColor', [1 1 0], 'FontWeight', 'bold'), 'cell', event.Indices);
end
function onUKKeyPress(fig, event)
    if strcmp(event.Key, 'z') && ~isempty(event.Modifier) && any(strcmp(event.Modifier, 'control'))
        appData = fig.UserData; if isempty(appData.ukHistory), return; end
        lastData = appData.ukHistory{end}; appData.ukHistory(end) = []; appData.statShadowData = lastData; fig.UserData = appData;
        h = appData.ukFig.UserData; currentT = h.tStat.Data; h.tStat.Data = [currentT(:,1), num2cell(lastData)];

        % Restore Highlights by comparing with Saved Memory
        removeStyle(h.tStat);
        savedData = appData.statTabul;
        if size(savedData, 1) == size(lastData, 1) && size(savedData, 2) == size(lastData, 2)
            diffMask = savedData ~= lastData;
            [r, c] = find(diffMask);
            if ~isempty(r)
                addStyle(h.tStat, uistyle('BackgroundColor',[1 1 0], 'FontWeight', 'bold'), 'cell', [r, c+1]);
            end
        end
    end
end
function onUKTableSelect(src, event, fig)
    if isempty(event.Indices), return; end
    r = event.Indices(end, 1); c = event.Indices(end, 2); 
    % Column 5 is Name in the new 6-column layout
    if c ~= 5, return; end
    varName = src.Data{r, 5}; foundVal = src.Data{r, 6}; 
    if strcmp(foundVal, 'Not Found') || strcmp(foundVal, 'Empty'), return; end
    openGenericVarEditor(fig, varName, r);
end
function openGenericVarEditor(fig, varName, ukRowIdx)
    appData = fig.UserData; T = appData.T;
    
    % Recalculate correct ukRowIdx in appData.ukData to handle filtered views
    % ukTableData Cols: 1=UK, 2=Abbrev, 3=ID, 4=Name, 5=Values
    realUkRowIdx = find(strcmp(appData.ukData(:, 4), varName), 1);
    if isempty(realUkRowIdx), realUkRowIdx = ukRowIdx; end % Fallback
    
    sCol2 = strtrim(string(T.Var2)); sCol1 = strtrim(string(T.Var1)); rIdx = find(strcmpi(sCol2, varName), 1); if isempty(rIdx), rIdx = find(strcmpi(sCol1, varName), 1); end
    if isempty(rIdx), return; end
    rowStart = rIdx; for r = rowStart:min(rowStart+10, height(T)), vals = str2double(string(table2cell(T(r, 3:end)))); if sum(~isnan(vals)) >= 1, rowStart = r; break; end, end
    rowEnd = rowStart; for r = rowStart:min(rowStart+50, height(T)), vals = str2double(string(table2cell(T(r, 3:end)))); if all(isnan(vals)), break; end, rowEnd = r; end
    maxCol = 3; firstRow = str2double(string(table2cell(T(rowStart, :)))); lastValid = find(~isnan(firstRow), 1, 'last'); if ~isempty(lastValid), maxCol = max(maxCol, lastValid); end
    rawData = str2double(string(table2cell(T(rowStart:rowEnd, 3:maxCol))));

    d = uifigure('Name', ['Edit: ' varName], 'Position', [200 200 600 400], 'WindowStyle', 'alwaysontop');
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

    d.UserData = struct('history', {{}}, 'selection', []);
end
function onPopupSelect(d, event)
    h = d.UserData; h.selection = event.Indices; d.UserData = h;
end
function onPopupEdit(d, src, event)
    % Reconstruct old data for undo history
    oldData = src.Data;
    if ~isempty(event.Indices)
        oldData(event.Indices(1), event.Indices(2)) = event.PreviousData;
    end
    pushPopupHistory(d, oldData);

    % Re-apply styles after edit to keep colors correct
    applyHeatmapStyles(src);
    % Highlight edited cell in yellow to show modification
    addStyle(src, uistyle('BackgroundColor',[1 1 0], 'FontWeight', 'bold'), 'cell', event.Indices);
end
function onPopupKeyPress(d, event)
    if strcmp(event.Key, 'z') && ~isempty(event.Modifier) && any(strcmp(event.Modifier, 'control'))
        performPopupUndo(d);
    end
end
function pushPopupHistory(d, data)
    h = d.UserData;
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

    tEd = findobj(d, 'Type', 'uitable');
    if ~isempty(tEd)
        tEd.Data = lastData;
        applyHeatmapStyles(tEd);
    end
end
function applyPopupMath(d, op)
    h = d.UserData;
    tEd = findobj(d, 'Type', 'uitable');
    sel = h.selection;
    if isempty(sel) || isempty(tEd), uialert(d, 'Select cells first.', 'Error'); return; end

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
    data = tTable.Data;
    removeStyle(tTable);

    % Get unique numeric values
    uniqueVals = unique(data(~isnan(data)));
    if isempty(uniqueVals), return; end

    % Generate Colors (using parula or jet colormap logic)
    nColors = length(uniqueVals);
    colors = parula(nColors);
    % Brighten colors slightly for readability
    colors = min(colors + 0.2, 1);

    for i = 1:nColors
        val = uniqueVals(i);
        color = colors(i, :);
        [r, c] = find(data == val);
        if ~isempty(r)
            s = uistyle('BackgroundColor', color);
            addStyle(tTable, s, 'cell', [r(:), c(:)]);
        end
    end
end
function saveGenericVar(fig, popFig, tEd, varName, ukRowIdx, rowStart, maxCol)
    appData = fig.UserData; newData = tEd.Data;
    for r=1:size(newData,1), for c=1:size(newData,2), appData.T{rowStart+r-1, 2+c} = {newData(r,c)}; end, end
    
    valStr = char(strjoin(string(unique(newData(~isnan(newData))')), ', '));
    appData.ukData{ukRowIdx, 5} = valStr;
    
    fig.UserData = appData; 
    
    if isvalid(appData.ukFig)
        h = appData.ukFig.UserData;
        % Update fullDisplayData if it exists (for filtered view consistency)
        if isfield(h, 'fullDisplayData')
             % fullDisplayData is cell array. Col 6 corresponds to Values (ukData Col 5)
             % Ensure h is treated as scalar if needed, but here we access struct fields.
             % If h is struct array, we can't easily update. But previous fix made it scalar.
             if isscalar(h)
                 h.fullDisplayData{ukRowIdx, 6} = valStr;
                 appData.ukFig.UserData = h;
             end
        end
        updateUKTableStyles(h.filterField, appData.ukFig, fig); 
    end
    delete(popFig);
end
function saveStatChanges(ukFig, mainFig)
    if strcmp(uiconfirm(ukFig, 'Overwrite original values?', 'Save', 'Options', {'Yes','Cancel'}), 'Cancel'), return; end
    h = ukFig.UserData; fullData = h.tStat.Data;
    appData = mainFig.UserData; appData.statRowNames = fullData(:,1);
    numData = cell2mat(fullData(:, 2:end));
    appData.statTabul = numData;
    appData.ukHistory = {};
    mainFig.UserData = appData;
    updateUKTableStyles(h.filterField, ukFig, mainFig);
end
%% === TCC EDITOR LOGIC (V10.0 - Gold Buttons) ===
function openTCCEditor(fig)
    appData = fig.UserData;
    if isfield(appData, 'tccFig') && ~isempty(appData.tccFig) && isvalid(appData.tccFig)
        figure(appData.tccFig); updateTCCEditor(fig); return;
    end

    d = uifigure('Name', 'TCC Editor', 'Position', [100 100 1000 600]);
    d.CloseRequestFcn = @(src,e) delete(src);
    d.WindowKeyPressFcn = @(src,e) onTCCKeyPress(fig, e);

    appData.tccFig = d;
    appData.tccHistory = {};
    fig.UserData = appData;

    gl = uigridlayout(d, [2 1]); gl.RowHeight = {'1x', 50};
    tg = uitabgroup(gl);

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

    % Main Controls
    pnl = uipanel(gl);
    pnl.Layout.Row = 2; pnl.Layout.Column = 1;
    bl = uigridlayout(pnl, [1 3]); bl.ColumnWidth = {'1x', 150, '1x'};

    btnCancel = uibutton(bl, 'Text', 'Close / Cancel', 'ButtonPushedFcn', @(~,~) delete(d));
    btnCancel.Layout.Row = 1; btnCancel.Layout.Column = 2;

    d.UserData = struct('tTCC', tTCC, 'tZustand', tZustand, 'tKWK', tKWK, 'tabGroup', tg, 'activeMapStructs', [], 'tccSelection', []);
    updateTCCEditor(fig);
end
function updateTCCEditor(fig)
    appData = fig.UserData;
    if ~isfield(appData, 'tccFig') || isempty(appData.tccFig) || ~isvalid(appData.tccFig) || isempty(appData.tccFig.UserData), return; end

    h = appData.tccFig.UserData; tTCC = h.tTCC; tZustand = h.tZustand; tKWK = h.tKWK;

    % === Explicit Reset of TCC Table ===
    tTCC.Data = []; tTCC.ColumnName = {};

    activeState = -1; activeMapID = -999;

    % Populate WT_ZUSTAND
    if ~isempty(appData.wtZustand)
        zData = appData.wtZustand';
        tZustand.Data = zData; tZustand.RowName = string(0 : size(zData,1)-1);
        appData.tccShadowData.zustand = zData; removeStyle(tZustand);
        mapName = appData.currentMapName; mapNumStr = regexp(mapName, 'SKL_GKF_(\d+)', 'tokens');
        if ~isempty(mapNumStr)
            activeMapID = str2double(mapNumStr{1}{1});
            idx = find(zData(:, 1) == activeMapID, 1);
            if ~isempty(idx), activeState = zData(idx, 2); addStyle(tZustand, uistyle('BackgroundColor', [0.6 1 0.6], 'FontWeight', 'bold'), 'row', idx); scroll(tZustand, 'row', idx); end
        end
    else, tZustand.Data = []; end

    % Populate WT_KWK_ZTAB
    if ~isempty(appData.kwkData)
        tKWK.Data = appData.kwkData; tKWK.RowName = string(0 : size(appData.kwkData,1)-1);
        appData.tccShadowData.kwk = appData.kwkData; removeStyle(tKWK);
        if activeState ~= -1
            rowIndex = activeState + 1;
            if rowIndex >= 1 && rowIndex <= size(appData.kwkData, 1), addStyle(tKWK, uistyle('BackgroundColor', [0.6 1 0.6], 'FontWeight', 'bold'), 'row', rowIndex); scroll(tKWK, 'row', rowIndex); end
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

    combinedData = []; colNames = {'Pedal %'}; activeMapStructs = []; hasYAxis = false;

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
                for c = 1:length(matchIdx), activeMapStructs = [activeMapStructs; struct('mapIdx', m, 'colIdxInMap', matchIdx(c))]; end

                % Break here to stop searching other maps for the same ID
                break;
            end
        end
    end
    tTCC.Data = combinedData; tTCC.ColumnName = colNames;
    h.activeMapStructs = activeMapStructs; appData.tccFig.UserData = h;
    appData.tccShadowData.curves = combinedData; fig.UserData = appData; removeStyle(tTCC);
    drawnow; % Force UI Refresh
end
%% === TCC INTERACTION FUNCTIONS (MISSING FROM PREVIOUS CODE) ===
function onTCCSelect(fig, src, event)
    if isempty(event.Indices), return; end
    h = fig.UserData.tccFig.UserData;
    h.tccSelection = event.Indices;
    fig.UserData.tccFig.UserData = h;
end
function onTCCEdit(fig, src, event, type)
    pushTCCHistory(fig);
    appData = fig.UserData;
    % Shadow Update
    if strcmp(type, 'curves')
        appData.tccShadowData.curves = src.Data;
    elseif strcmp(type, 'zustand')
        appData.tccShadowData.zustand = src.Data;
    elseif strcmp(type, 'kwk')
        appData.tccShadowData.kwk = src.Data;
    end
    fig.UserData = appData;
    addStyle(src, uistyle('BackgroundColor',[1 1 0], 'FontWeight', 'bold'), 'cell', event.Indices);
end
function onTCCKeyPress(fig, event)
    if strcmp(event.Key, 'z') && ~isempty(event.Modifier) && any(strcmp(event.Modifier, 'control'))
        performTCCUndo(fig);
    end
end
function applyTCCMath(fig, op)
    h = fig.UserData.tccFig.UserData;
    tTCC = h.tTCC;
    sel = h.tccSelection;
    if isempty(sel), uialert(fig.UserData.tccFig, 'Select cells first.', 'Error'); return; end

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
    fig.UserData.tccShadowData.curves = data;
end
function saveTCCData(fig)
    h = fig.UserData.tccFig.UserData;
    if strcmp(uiconfirm(fig.UserData.tccFig, 'Overwrite original values?', 'Save', 'Options', {'Yes','Cancel'}), 'Cancel'), return; end
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
    removeStyle(h.tTCC);
    uialert(fig.UserData.tccFig, 'TCC Curves Saved to Memory.', 'Success');
end
function saveZustand(fig)
    if strcmp(uiconfirm(fig.UserData.tccFig, 'Overwrite original values?', 'Save', 'Options', {'Yes','Cancel'}), 'Cancel'), return; end
    appData = fig.UserData;
    appData.tccHistory = {};
    newData = appData.tccShadowData.zustand;
    % Transpose back if needed (WT_ZUSTAND was transposed for display)
    appData.wtZustand = newData';

    % Update T (The main table) - Find where WT_ZUSTAND is and write back
    % This is complex because WT_ZUSTAND structure varies.
    % For now, we update the appData struct which is used for export/display.
    % To actually write to CSV export later, we need to implement T update.
    % Simplified: Update Internal Memory Only
    fig.UserData = appData;
    removeStyle(fig.UserData.tccFig.UserData.tZustand);
    uialert(fig.UserData.tccFig, 'Zustand Saved to Memory.', 'Success');
    updateTCCEditor(fig); % Refresh to show changes affecting selection
end
function saveKWK(fig)
    if strcmp(uiconfirm(fig.UserData.tccFig, 'Overwrite original values?', 'Save', 'Options', {'Yes','Cancel'}), 'Cancel'), return; end
    appData = fig.UserData;
    appData.tccHistory = {};
    newData = appData.tccShadowData.kwk;
    appData.kwkData = newData;
    fig.UserData = appData;
    removeStyle(fig.UserData.tccFig.UserData.tKWK);
    uialert(fig.UserData.tccFig, 'KWK Table Saved to Memory.', 'Success');
    updateTCCEditor(fig);
end
function pushTCCHistory(fig)
    appData = fig.UserData;
    if ~isfield(appData, 'tccShadowData'), return; end
    appData.tccHistory{end+1} = appData.tccShadowData;
    if length(appData.tccHistory) > 20, appData.tccHistory(1) = []; end
    fig.UserData = appData;
end
function performTCCUndo(fig)
    appData = fig.UserData;
    if isempty(appData.tccHistory), return; end
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
                    addStyle(h.tTCC, uistyle('BackgroundColor',[1 1 0], 'FontWeight', 'bold'), 'cell', [r, c+1]);
                end
            end
        end
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
                 addStyle(h.tZustand, uistyle('BackgroundColor',[1 1 0], 'FontWeight', 'bold'), 'cell', [r, c]);
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
                 addStyle(h.tKWK, uistyle('BackgroundColor',[1 1 0], 'FontWeight', 'bold'), 'cell', [r, c]);
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
    for r = rowStart:min(rowStart+100, height(T))
        vals = str2double(string(table2cell(T(r, 3:end))));
        if sum(~isnan(vals)) < 2, break; end
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
    if isempty(appData.contextLabel) || ~isvalid(appData.contextLabel), return; end
    function txt = getMapInfo(mapName)
        if isempty(mapName) || mapName == "", txt = "None Selected"; return; end
        mapNumStr = regexp(mapName, 'SKL_GKF_(\d+)', 'tokens');
        if isempty(mapNumStr), txt = mapName; return; end
        mapNum = str2double(mapNumStr{1}{1});
        modeTxt = "Refer UK Table"; colorHex = "black"; slopeTxt = "";
        if mapNum >= 0 && mapNum <= 24
            if mapNum <= 4, slopeTxt = "Downhill"; elseif mapNum <= 9, slopeTxt = "Flat"; else, slopeTxt = "Uphill"; end
            if ismember(mapNum, [1 6 11 16 21]), modeTxt = "Normal ADT"; colorHex = "green";
            elseif ismember(mapNum, [3 8 13 18 23]), modeTxt = "Sport/Track ADT"; colorHex = "red";
            elseif ismember(mapNum, [0 5 10 15 20]), modeTxt = "Normal"; colorHex = "green";
            elseif ismember(mapNum, [2 7 12 17 22]), modeTxt = "Sport"; colorHex = "red";
            elseif ismember(mapNum, [4 9 14 19 24]), modeTxt = "Track/Baja"; colorHex = "blue"; end
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
%         txt = sprintf('<b>Map %d:</b> %s | <font color="%s">%s</font> | <b>TCC:</b> <font color="%s">%s</font>', mapNum, slopeTxt, colorHex, modeTxt, tccColor, tccVal);
% Try "4" instead of "9"
        txt = sprintf('<font size="3"><b>Map %d: %s | <font color="%s">%s</font> | TCC: <font color="%s">%s</font></b></font>', ...
            mapNum, slopeTxt, colorHex, modeTxt, tccColor, tccVal);         
    end
    infoA = getMapInfo(appData.handles.dd1.Value); infoB = getMapInfo(appData.handles.dd2.Value);
    appData.contextLabel.Text = sprintf('%s<br><br>%s', infoA, infoB);
end
%% === HELPER: WINDOW MANAGEMENT ===
function closeMainApp(fig)
    if isvalid(fig)
        selection = uiconfirm(fig, 'Do you want to save the project before closing?', 'Close Application', ...
            'Options', {'Yes', 'No', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'question');

        if strcmp(selection, 'Cancel')
            return;
        elseif strcmp(selection, 'Yes')
            if ~saveProject(fig)
                return;
            end
        end

        appData = fig.UserData;
        if isfield(appData, 'tableFig') && ~isempty(appData.tableFig) && isvalid(appData.tableFig), delete(appData.tableFig); end
        if isfield(appData, 'ukFig') && ~isempty(appData.ukFig) && isvalid(appData.ukFig), delete(appData.ukFig); end
        if isfield(appData, 'tccFig') && ~isempty(appData.tccFig) && isvalid(appData.tccFig), delete(appData.tccFig); end
        if isfield(appData, 'multiMapFig') && ~isempty(appData.multiMapFig) && isvalid(appData.multiMapFig), delete(appData.multiMapFig); end
        if isfield(appData, 'analysisFig') && ~isempty(appData.analysisFig) && isvalid(appData.analysisFig), delete(appData.analysisFig); end
        if isfield(appData, 'genericFig') && ~isempty(appData.genericFig) && isvalid(appData.genericFig), delete(appData.genericFig); end
        delete(fig);
    end
end
function toggleTablePriority(fig, makeNormal)
    appData = fig.UserData;
    if ~isempty(appData.tableFig) && isvalid(appData.tableFig)
        if makeNormal, appData.tableFig.WindowStyle = 'normal'; figure(fig);
        else, appData.tableFig.WindowStyle = 'alwaysontop'; end
        drawnow;
    end
end
%% === SUB-FUNCTIONS ===
function checkMapSwitch(fig, src, event)
    appData = fig.UserData;
    targetMap = src.Value;
    
    if appData.handles.cbEdit.Value && ~isempty(appData.workingCopy) && isfield(appData.workingCopy, 'modified') && appData.workingCopy.modified
        toggleTablePriority(fig, true);
        selection = uiconfirm(fig, 'You have unsaved changes. Save before switching?', 'Unsaved Changes', ...
            'Options', {'Yes', 'No', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'warning');
        toggleTablePriority(fig, false);
        
        if strcmp(selection, 'Cancel')
            src.Value = appData.currentMapName; 
            return;
        elseif strcmp(selection, 'Yes')
            saved = saveModifiedMap(fig); 
            if ~saved
                src.Value = appData.currentMapName; 
                return; 
            end
            % Reload appData because saveModifiedMap may have modified it (Save as New)
            appData = fig.UserData;
        end
    end
    
    % Enforce the switch to the originally selected map
    % (Override whatever saveAsNew might have set the dropdown to)
    src.Value = targetMap; 
    
    appData.currentMapName = targetMap; 
    fig.UserData = appData; 
    updatePlot(fig); 
    updateTCCEditor(fig);
end
function updatePlot(fig)
    appData = fig.UserData; h = appData.handles; ax = h.ax;

    % --- 0. UPDATE 2ND AXIS ---
    if isfield(h, 'ddAxis') && isfield(h, 'ax2') && isvalid(h.ax2)
        axisType = h.ddAxis.Value;
        if strcmp(axisType, 'None')
            h.ax2.Visible = 'off';
        else
            h.ax2.Visible = 'on';
            h.ax2.XLim = ax.XLim;
            
            % Conversion Factors
            axleRatio = appData.userInputs.AxleRatio;
            is4Lo = h.cb4Lo.Value;
            if is4Lo, ratioEff = appData.userInputs.LowRangeRatio * axleRatio; else, ratioEff = axleRatio; end
            tireCirc = appData.userInputs.TireCircumference / 25.4;
            
            % RPM to Speed Factor (MPH) = (RPM / ratioEff * tireCirc) / 1056
            % RPM = Speed * 1056 * ratioEff / tireCirc
            
            factorMPH = (1 / ratioEff * tireCirc) / 1056;
            factorKPH = factorMPH * 1.60934;
            
            xLimits = ax.XLim;
            
            lblText = '';
            if strcmp(axisType, 'MPH')
                h.ax2.XLim = xLimits * factorMPH;
                lblText = 'Vehicle Speed (MPH)';
            elseif strcmp(axisType, 'KPH')
                h.ax2.XLim = xLimits * factorKPH;
                lblText = 'Vehicle Speed (KPH)';
            end
            
            if ~isempty(lblText)
                lb = xlabel(h.ax2, lblText);
                lb.Units = 'normalized';
                % Position at top right
                % Standard Position is [0.5, -0.1ish, 0] for bottom or [0.5, 1.something, 0] for top?
                % Since XAxisLocation is top, label is above.
                % We want X=1 (right edge). Y should be kept as is or slightly adjusted if needed.
                % But usually just setting X and HorizontalAlignment is enough.
                currentPos = lb.Position;
                lb.Position = [1, currentPos(2), currentPos(3)];
                lb.HorizontalAlignment = 'right';
            end
        end
    end

    % --- 0.5 UPDATE 3RD AXIS (Engine RPM) ---
    if isfield(h, 'ax3') && isvalid(h.ax3)
        if isfield(appData.userInputs, 'IdleRPM') && isfield(appData.userInputs, 'MaxRPM')
            idle = appData.userInputs.IdleRPM;
            maxR = appData.userInputs.MaxRPM;
            % 0% Pedal = Idle, 100% Pedal = Max
            % Y = Pedal%
            % RPM = Idle + (Y / 100) * (Max - Idle)
            
            % Map YLim [0 110] to RPM
            yLimits = ax.YLim;
            
            rpmLow = idle + (yLimits(1)/100) * (maxR - idle);
            rpmHigh = idle + (yLimits(2)/100) * (maxR - idle);
            
            h.ax3.YLim = [rpmLow, rpmHigh];
            h.ax3.Visible = 'on';
        else
            h.ax3.Visible = 'off';
        end
    end

    % --- 1. CLEANUP PREVIOUS PLOTS ---
    % Cleanup logic handled in renderMapOnAxes()

    % --- 2. GET UI STATE ---
    appData.handles = h; fig.UserData = appData;
    showA = h.cb1.Value; mapA_Name = h.dd1.Value; showB = h.cb2.Value; mapB_Name = h.dd2.Value;
    isEdit = h.cbEdit.Value; showLines = h.cbLines.Value; showTCC = h.cbTCC.Value;

    % --- 3. TCC CONFIGURATION ---
    % Colors for Gears 1-8
    tccGearColors = [
        0 0 0;       % 1st: Black
        1 0 0;       % 2nd: Red
        0 0 1;       % 3rd: Blue
        1 0 1;       % 4th: Magenta
        0 0.7 0.7;   % 5th: Teal
        0.5 0 0.8;   % 6th: Purple
        0.6 0 0;     % 7th: Maroon
        0.6 0.6 0.6  % 8th: Gray
    ];

    % Styles for the 4 Modes (RO, OR, RC, COC)
    % 1=RO (Rel), 2=OR (HiSlip), 3=RC (LoSlip), 4=COC (Lock)
    tccModeStyles = {'--', '-.', '-', '-'};
    tccModeMarkers = {'none', 'none', 'none', '.'};
    tccLineWidths = [1, 1, 1, 1.5];

    % Suffixes to append to the ID found in KWK table
    tccSuffixes = ["_RO", "_OR", "_RC", "_COC"];

    % --- 4. MAP SELECTION LOGIC ---
    if isEdit && isempty(appData.workingCopy)
        allNames = string(cellfun(@(m) m.name, appData.allMaps, 'UniformOutput',false));
        idx = find(allNames == mapA_Name, 1);
        if ~isempty(idx), appData.workingCopy = appData.allMaps{idx}; appData.editIndex = idx; appData.history = {}; fig.UserData = appData; end
    elseif isEdit && ~isempty(appData.workingCopy)
        if ~strcmp(appData.workingCopy.name, mapA_Name)
             allNames = string(cellfun(@(m) m.name, appData.allMaps, 'UniformOutput',false));
             idx = find(allNames == mapA_Name, 1);
             if ~isempty(idx), appData.workingCopy = appData.allMaps{idx}; appData.editIndex = idx; appData.history = {}; fig.UserData = appData; end
        end
        updateTableDisplay(fig);
    elseif ~isEdit
        appData.workingCopy = []; appData.editIndex = -1; fig.UserData = appData;
        if ~isempty(appData.tableFig) && isvalid(appData.tableFig), close(appData.tableFig); end
    end
    updateContextPanel(fig);

    % --- 5. CHECKBOXES FOR GEARS ---
    visibleUp = false(1,7); visibleDown = false(1,7);
    for i = 1:7
        cbU = h.gearChecks(sprintf('%d%d', i, i+1)); visibleUp(i) = cbU.Value;
        cbD = h.gearChecks(sprintf('%d%d', i+1, i)); visibleDown(i) = cbD.Value;
    end

    % --- 6. PLOT SHIFT LINES (Main Axis) ---
    legendItems = renderMapOnAxes(fig, ax, true);
    
    % --- 7. PLOT ON SECONDARY TABLE AXIS (If Exists) ---
    if isfield(appData, 'tableAx') && ~isempty(appData.tableAx) && isvalid(appData.tableAx)
        renderMapOnAxes(fig, appData.tableAx, false);
    end
    
    % Ensure correct stacking order: Crosshairs above curves, Dots above crosshairs, Text above all
    uistack([h.vLine, h.hLine], 'top');
    
    % Bring drag dots to top (if they exist)
    dots = findobj(ax, 'Tag', 'shiftPoint');
    if ~isempty(dots), uistack(dots, 'top'); end
    
    uistack(h.crossText, 'top');
    
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
    
    % Updated Width for narrower legend (160px)
    panelWidth = 140; % Slightly less than column width

    axL = axes('Parent', pnl, 'Units', 'pixels', 'Position', [5, 0, panelWidth, totalHeight], ...
        'Visible', 'off', 'XLim', [0 1], 'YLim', [0 nItems]);
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
end
function updateTableDisplay(fig)
    appData = fig.UserData;
    if ~isempty(appData.tableHandle) && isvalid(appData.tableHandle) && ~isempty(appData.workingCopy)
         wc = appData.workingCopy; 
         
         % Base Data (RPM)
         dataRPM = [wc.pedal(:), round(wc.Z_up), round(wc.Z_down)];
         
         % Calculate Factors
         axleRatio = appData.userInputs.AxleRatio;
         is4Lo = findobj(fig, 'Text', '4Lo Mode').Value;
         if is4Lo, ratioEff = appData.userInputs.LowRangeRatio * axleRatio; else, ratioEff = axleRatio; end
         tireCirc = appData.userInputs.TireCircumference / 25.4;
         gearRatios = appData.userInputs.GearRatios;
         
         % MPH Data
         dataMPH = dataRPM;
         % Iterate columns 2 to end (skip pedal)
         for c = 2:size(dataRPM, 2)
             dataMPH(:, c) = (dataRPM(:, c) / ratioEff * tireCirc) / 1056;
         end
         
         % KPH Data
         dataKPH = dataRPM;
         for c = 2:size(dataRPM, 2)
             dataKPH(:, c) = dataMPH(:, c) * 1.60934;
         end
         
         % Turbine RPM Data
         dataTurbine = dataRPM;
         % Columns: Pedal, 1-2, 2-3, ... 7-8, 2-1, ... 8-7
         % 1-2 (Col 2) -> Gear 1
         % 8-7 (Col 15) -> Gear 8
         for c = 2:15
             c_rpm = c - 1;
             if c_rpm <= 7, gearIdx = c_rpm; else, gDown = c_rpm - 7; gearIdx = gDown + 1; end
             
             if gearIdx >= 1 && gearIdx <= length(gearRatios)
                 dataTurbine(:, c) = dataRPM(:, c) * gearRatios(gearIdx);
             end
         end
         
         % Update Tables
         if isfield(appData, 'editorTables')
             % PERFORMANCE: Only update currently visible table to reduce rendering lag
             activeTabTitle = '';
             if isfield(appData, 'editorTabGroup') && isvalid(appData.editorTabGroup)
                 activeTabTitle = appData.editorTabGroup.SelectedTab.Title;
             end
             
             switch activeTabTitle
                 case 'Output RPM', appData.editorTables.RPM.Data = dataRPM;
                 case 'MPH', appData.editorTables.MPH.Data = round(dataMPH, 2);
                 case 'KPH', appData.editorTables.KPH.Data = round(dataKPH, 2);
                 case 'Turbine RPM', appData.editorTables.Turbine.Data = round(dataTurbine);
                 case 'Engine RPM', appData.editorTables.Engine.Data = round(dataTurbine);
                 otherwise, appData.editorTables.RPM.Data = dataRPM; % Fallback
             end
         else
             appData.tableHandle.Data = dataRPM;
         end

         if ~isempty(appData.tableFig) && isvalid(appData.tableFig), appData.tableFig.Name = ['Table Editor: ' char(wc.name)]; end
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
                 end
             end
             
             updateInfoPanel(fig, r, c, currentVal, activeType); 
         end
    end
end
function createDragDot(ax, xData, yData, colIdx, isUp, color)
    s = scatter(ax, xData, yData, 100, color, 'filled', 'Marker', ifelse(isUp, 'o', 's'), 'Tag', 'shiftPoint', 'PickableParts', 'visible');
    
    % Assign Context Menu
    fig = ancestor(ax, 'figure');
    if isfield(fig.UserData.handles, 'refreshCM')
        s.ContextMenu = fig.UserData.handles.refreshCM;
    end
    
    s.UserData = struct('col', colIdx, 'isUp', isUp); s.ButtonDownFcn = @(src,evt) startDrag(src, ax); uistack(s, 'top');
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
    origMap = appData.allMaps{appData.editIndex};
    if src.UserData.isUp
        origX = origMap.Z_up(rowIdx, src.UserData.col);
    else
        origX = origMap.Z_down(rowIdx, src.UserData.col);
    end
    origY = origMap.pedal(rowIdx);
    
    ghost = scatter(ax, origX, origY, 100, [0.5 0.5 0.5], 'filled', ...
        'Marker', ifelse(src.UserData.isUp, 'o', 's'), ...
        'MarkerFaceAlpha', 0.5, 'HitTest', 'off', 'PickableParts', 'none');
    appData.dragGhost = ghost;
    fig.UserData = appData;
    
    dragData = struct('src', src, 'rowIdx', rowIdx, 'colIdx', src.UserData.col, 'isUp', src.UserData.isUp, 'allowY', h.cbAllowY.Value, 'ax', ax, 'origX', origX, 'origY', origY);
    fig.WindowButtonMotionFcn = @(f,e) dragging(fig, dragData); fig.WindowButtonUpFcn = @(f,e) stopDrag(fig);
end
function dragging(fig, d)
    try
        ax = d.ax; cp = ax.CurrentPoint; newX = max(0, min(8000, cp(1,1))); newY = max(0, min(110, cp(1,2)));
        d.src.XData(d.rowIdx) = newX; if d.allowY, d.src.YData(d.rowIdx) = newY; end
        appData = fig.UserData; wc = appData.workingCopy;

        if d.isUp
            wc.Z_up(d.rowIdx, d.colIdx) = newX; gearIdx = d.colIdx; lbl = sprintf('%d-%d Up Shift', gearIdx, gearIdx+1);
        else
            wc.Z_down(d.rowIdx, d.colIdx) = newX; gearIdx = d.colIdx + 1; lbl = sprintf('%d-%d Down Shift', gearIdx, gearIdx-1);
        end

        if d.allowY, wc.pedal(d.rowIdx) = newY; end
        
        wc = enforceRowConstraints(wc);
        wc.modified = true; appData.workingCopy = wc; 
        % Update selected indices so Info Panel updates live
        tCol = ifelse(d.isUp, d.colIdx + 1, d.colIdx + 8);
        appData.lastSelectedIndices = [d.rowIdx, tCol];
        fig.UserData = appData; 
        
        % OPTIMIZATION: Do NOT update entire table display during drag.
        % Just update Info Panel for performance.
        activeType = 'RPM';
        if isfield(appData, 'editorTabGroup') && isvalid(appData.editorTabGroup)
             activeTab = appData.editorTabGroup.SelectedTab;
             if strcmp(activeTab.Title, 'MPH'), activeType = 'MPH';
             elseif strcmp(activeTab.Title, 'KPH'), activeType = 'KPH';
             elseif strcmp(activeTab.Title, 'Turbine RPM'), activeType = 'Turbine';
             end
        end
        updateInfoPanel(fig, d.rowIdx, tCol, 0, activeType);

        h = appData.handles;
        h.vLine.XData = [newX newX]; h.vLine.Visible = 'on';
        h.hLine.YData = [newY newY]; h.hLine.Visible = 'on';

        % --- UPDATE TEXT PROPERTIES ---
        h.crossText.Position = [newX+80, newY+2.1];
        h.crossText.String = getShiftInfoText(newX, newY, lbl, gearIdx, appData, h.cb4Lo.Value, d.origX, d.origY);
        h.crossText.FontWeight = 'bold';
        h.crossText.FontSize = 11;

        h.crossText.Visible = 'on'; 
        % Do NOT stack lines top here, as it covers drag dots. 
        % Dots are already on top from updatePlot.
        uistack(h.crossText, 'top'); 
        drawnow limitrate;
    catch
        stopDrag(fig);
    end
end
function stopDrag(fig)
    appData = fig.UserData;
    if isfield(appData, 'dragGhost') && isvalid(appData.dragGhost)
        delete(appData.dragGhost);
        appData = rmfield(appData, 'dragGhost');
        fig.UserData = appData;
    end

    if appData.handles.cbAllowY.Value && ~isempty(appData.tableHandle) && isvalid(appData.tableHandle)
        appData.tableHandle.RowName = compose("%.1f%%", appData.workingCopy.pedal);
    end
    
    % Sync table data now that drag is done
    updateTableDisplay(fig); 
    
    fig.WindowButtonMotionFcn = @(src, event) passiveCrosshair(fig); fig.WindowButtonUpFcn = '';
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
            
            % Retrieve original map for comparison
            if appData.editIndex > 0 && appData.editIndex <= length(appData.allMaps)
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
        % Do NOT stack lines top here, as it covers drag dots.
        uistack(h.crossText, 'top');
    catch
    end
end
function pushHistory(fig)
    appData = fig.UserData; if isempty(appData.workingCopy), return; end
    appData.history{end+1} = appData.workingCopy; if length(appData.history) > 50, appData.history(1) = []; end
    fig.UserData = appData;
end
function onKeyPress(fig, event)
    if strcmp(event.Key, 'z') && ~isempty(event.Modifier) && any(strcmp(event.Modifier, 'control')), performUndo(fig);
    elseif strcmp(event.Key, 'v') && ~isempty(event.Modifier) && any(strcmp(event.Modifier, 'control')), pasteTableData(fig); end
end
function performUndo(fig)
    appData = fig.UserData; if isempty(appData.history), return; end
    lastState = appData.history{end}; appData.history(end) = []; appData.workingCopy = lastState; fig.UserData = appData; updatePlot(fig);
end
function applyMath(fig, type)
    appData = fig.UserData;
    if isempty(appData.tableHandle) || isempty(appData.lastSelectedIndices), uialert(appData.tableFig, 'Please select cells first.', 'Selection Error'); return; end
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
    wc.modified = true; appData.workingCopy = wc; fig.UserData = appData; updatePlot(fig);
end
function pasteTableData(fig)
    appData = fig.UserData;
    if isempty(appData.workingCopy) || isempty(appData.tableHandle) || ~isvalid(appData.tableHandle), return; end
    try
        str = clipboard('paste'); if isempty(str), return; end
        cleanStr = regexprep(str, '[^0-9\.\-\+\s\n\t]', ''); rows = split(cleanStr, newline); rows = rows(~cellfun('isempty', rows));
        if isempty(rows), return; end
        if isempty(appData.lastSelectedIndices), startR = 1; startC = 1; else, startR = min(appData.lastSelectedIndices(:,1)); startC = min(appData.lastSelectedIndices(:,2)); end
        pushHistory(fig); appData = fig.UserData; wc = appData.workingCopy; wc = appData.workingCopy; maxRows = size(wc.Z_up, 1); maxCols = 15;
        for r = 1:length(rows)
            numStrs = regexp(rows{r}, '[-+]?[0-9]*\.?[0-9]+', 'match'); vals = str2double(numStrs); if isempty(vals), continue; end
            for c = 1:length(vals)
                targetR = startR + r - 1; targetC = startC + c - 1; if targetR > maxRows || targetC > maxCols, continue; end
                val = vals(c); if targetC > 1, val = round(val); end
                if targetC == 1, wc.pedal(targetR) = val; elseif targetC <= 8, wc.Z_up(targetR, targetC-1) = val; else, wc.Z_down(targetR, targetC-8) = val; end
            end
        end
        wc = enforceRowConstraints(wc);
        wc.modified = true; appData.workingCopy = wc; fig.UserData = appData; updatePlot(fig);
    catch, uialert(appData.tableFig, 'Invalid data.', 'Paste Error'); end
end
function openTableEditor(fig)
    appData = fig.UserData;
    if isempty(appData.workingCopy), uialert(fig, 'Please enable "Edit Map A" and select a map first.', 'No Map Selected'); return; end
    if ~isempty(appData.tableFig) && isvalid(appData.tableFig), figure(appData.tableFig); return; end
    wc = appData.workingCopy;
    
    % INCREASE HEIGHT AND CHANGE LAYOUT TO VERTICAL STACK
    try, tFig = uifigure('Name', ['Table Editor: ' char(wc.name)], 'Position', [50 50 1450 700], 'WindowStyle', 'alwaysontop');
    catch, tFig = uifigure('Name', ['Table Editor: ' char(wc.name)], 'Position', [50 50 1450 700]); end
    tFig.CloseRequestFcn = @(src,event) closeTable(fig, src); tFig.WindowKeyPressFcn = @(src, event) onKeyPress(fig, event);
    
    % Main Layout: 2 Rows (Table/Controls Top, Plot Bottom)
    mainGl = uigridlayout(tFig, [2 1]); 
    mainGl.RowHeight = {'1x', '1x'};
    mainGl.Padding = [5 5 5 5];
    
    % --- TOP SECTION (Table & Controls) ---
    topGl = uigridlayout(mainGl, [1 2]); 
    topGl.Layout.Row = 1; topGl.Layout.Column = 1;
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
    
    rightGrid = uigridlayout(topGl, [3 1]); rightGrid.Layout.Column = 2; rightGrid.Layout.Row = 1; rightGrid.RowHeight = {'1x', 120, 40}; rightGrid.Padding = [0 0 0 0];
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
    
    % --- BOTTOM SECTION (Plot) ---
    pnlPlot = uipanel(mainGl, 'BorderType', 'none');
    pnlPlot.Layout.Row = 2; pnlPlot.Layout.Column = 1;
    plotLayout = uigridlayout(pnlPlot, [1 1]);
    
    axTable = uiaxes(plotLayout);
    title(axTable, 'Interactive Map View (Output RPM vs Pedal%)');
    xlabel(axTable, 'Output Shaft RPM');
    ylabel(axTable, 'Pedal %');
    grid(axTable, 'on');
    xlim(axTable, [0 8000]); ylim(axTable, [0 110]);
    
    appData.tableFig = tFig; appData.tableHandle = t; appData.editorTables = tables; 
    appData.editorTabGroup = tg; % Save for detecting active tab
    appData.infoLabel = lbl; 
    appData.tableAx = axTable; % Store Axes Handle
    
    fig.UserData = appData; 
    updateTableDisplay(fig); 
    updatePlot(fig); % Initial population of the plot
    drawnow;
end
function updateHysteresis(fig, field, value)
    appData = fig.UserData; appData.hysteresis.(field) = value; fig.UserData = appData; refreshTableStyles(fig);
end
function copyTableData(fig)
    appData = fig.UserData; if isempty(appData.workingCopy), return; end
    wc = appData.workingCopy; 
    
    % Get full data (excluding Pedal %)
    fullData = round([wc.Z_up, wc.Z_down]);
    
    % Skip first and last row (copy rows 2 to 13 typically)
    if size(fullData, 1) >= 3
        dataToCopy = fullData(2:end-1, :);
    else
        dataToCopy = fullData; % Fallback if table is too small
    end
    
    str = ''; [rows, cols] = size(dataToCopy);
    for r = 1:rows, rowStr = sprintf('%.0f\t', dataToCopy(r,:)); str = [str, rowStr(1:end-1), newline]; end
    clipboard('copy', str); uialert(appData.tableFig, 'Table data copied to clipboard (Rows 2-13, No Pedal %).', 'Success');
end
function closeTable(mainFig, tFig)
    appData = mainFig.UserData; appData.tableFig = gobjects(0); appData.tableHandle = gobjects(0);
    if isfield(appData, 'editorTables'), appData = rmfield(appData, 'editorTables'); end
    if isfield(appData, 'tableAx'), appData = rmfield(appData, 'tableAx'); end
    appData.infoLabel = gobjects(0); appData.hysteresisInputs = []; appData.lastSelectedIndices = []; mainFig.UserData = appData; delete(tFig);
end
function onTableEdit(fig, src, event)
    onGenericTableEdit(fig, src, event, 'RPM');
end

function onGenericTableEdit(fig, src, event, type)
    pushHistory(fig); appData = fig.UserData; wc = appData.workingCopy; 
    
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
        is4Lo = findobj(fig, 'Text', '4Lo Mode').Value;
        if is4Lo, ratioEff = appData.userInputs.LowRangeRatio * axleRatio; else, ratioEff = axleRatio; end
        tireCirc = appData.userInputs.TireCircumference / 25.4;
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
    
    wc.modified = true; appData.workingCopy = wc; fig.UserData = appData; 
    updatePlot(fig); 
    
    % Update Info Panel with the converted RPM value (as it expects RPM)
    % Or calculate what to show. updateInfoPanel expects the value in the table.
    % If we edited MPH, the table still shows MPH until updateTableDisplay? 
    % updateTableDisplay will refresh all tables.
    % We should call updateTableDisplay first.
    updateTableDisplay(fig);
    
    % updateInfoPanel uses tableHandle.Data. Since we updated, it should match.
    updateInfoPanel(fig, event.Indices(1), event.Indices(2), val, type); % Pass the raw typed value? No, let it pick from table.
end
function onTableSelect(fig, src, event, type)
    if ~isvalid(fig), return; end
    if isempty(event.Indices), return; end
    r = event.Indices(end, 1); c = event.Indices(end, 2); val = src.Data(r, c); appData = fig.UserData; appData.lastSelectedIndices = event.Indices; fig.UserData = appData; updateInfoPanel(fig, r, c, val, type);
end
function refreshTableStyles(fig)
    appData = fig.UserData; 
    
    % Collect all tables
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
    elseif ~isempty(appData.tableHandle) && isvalid(appData.tableHandle)
        tablesToStyle = {appData.tableHandle};
    else
        return;
    end
    
    wc = appData.workingCopy; origMap = appData.allMaps{appData.editIndex};
    currDataRPM = [wc.pedal(:), round(wc.Z_up), round(wc.Z_down)]; 
    origDataRPM = [origMap.pedal(:), round(origMap.Z_up), round(origMap.Z_down)];
    
    % Calculations for checks
    threshSpeed = appData.hysteresis.Speed; threshMPH = appData.hysteresis.MPH;
    axleRatio = appData.userInputs.AxleRatio; is4Lo = findobj(fig, 'Text', '4Lo Mode').Value;
    if is4Lo, ratioEff = appData.userInputs.LowRangeRatio * axleRatio; else, ratioEff = axleRatio; end
    tireCirc = appData.userInputs.TireCircumference / 25.4;
    
    % Diff mask based on RPM (applies to all tables cells)
    diffMask = abs(currDataRPM - origDataRPM) > 0.001;
    [rDiff, cDiff] = find(diffMask);
    
    % Styles
    sGray = uistyle('BackgroundColor', [0.7 0.7 0.7]);
    sBlue = uistyle('BackgroundColor', [0.9 0.85 1], 'FontWeight', 'bold');
    sYellow = uistyle('BackgroundColor', [1 1 0.6]);
    sRed = uistyle('BackgroundColor', [1 0 0], 'FontWeight', 'bold', 'FontColor', 'white'); 
    sMagenta = uistyle('BackgroundColor', [1 0 1], 'FontWeight', 'bold');
    
    nRows = size(currDataRPM, 1);
    
    % Collect Indices for styles
    redIdx = [];
    magIdx = [];
    
    % Logic checks (Regression, Hysteresis)
    % These are logical checks on RPM values, but we highlight the corresponding cells in ALL tables.
    for r = 1:nRows
        % Regression Checks
        for c = 3:8
            if currDataRPM(r, c) < currDataRPM(r, c-1)
                redIdx = [redIdx; r, c; r, c-1];
            end
        end
        for c = 10:15
            if currDataRPM(r, c) < currDataRPM(r, c-1)
                redIdx = [redIdx; r, c; r, c-1];
            end
        end
        
        % Hysteresis Checks
        for g = 1:7
            colUp = g + 1; colDown = g + 8; valUp = currDataRPM(r, colUp); valDown = currDataRPM(r, colDown);
            mphUp = (valUp / ratioEff * tireCirc) / 1056; mphDown = (valDown / ratioEff * tireCirc) / 1056;
            
            if (mphUp - mphDown) < threshMPH
                magIdx = [magIdx; r, colUp; r, colDown];
            end
            if valDown >= (valUp - threshSpeed)
                redIdx = [redIdx; r, colUp; r, colDown];
            end
        end
    end
    
    if ~isempty(redIdx), redIdx = unique(redIdx, 'rows'); end
    if ~isempty(magIdx), magIdx = unique(magIdx, 'rows'); end
    
    % Apply to each table
    for tIdx = 1:length(tablesToStyle)
        t = tablesToStyle{tIdx};
        if ~isvalid(t), continue; end
        removeStyle(t);
        
        addStyle(t, sGray, 'row', [1, nRows]);
        addStyle(t, sBlue, 'column', 1);
        
        if ~isempty(rDiff), addStyle(t, sYellow, 'cell', [rDiff, cDiff]); end
        
        if ~isempty(redIdx), addStyle(t, sRed, 'cell', redIdx); end
        if ~isempty(magIdx), addStyle(t, sMagenta, 'cell', magIdx); end
    end
end
function updateInfoPanel(fig, r, c, currentVal, type)
    if nargin < 5, type = 'RPM'; end
    appData = fig.UserData; if isempty(appData.infoLabel) || ~isvalid(appData.infoLabel), return; end
    
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
    is4Lo = findobj(fig, 'Text', '4Lo Mode').Value;
    if is4Lo, modeStr = '<font color="green"><b>ACTIVE</b></font>'; else, modeStr = '<font color="black">Not Active</font>'; end
    
    if gearIdx >= 1 && gearIdx <= length(gearRatios)
        ratio = gearRatios(gearIdx);
        axleRatio = appData.userInputs.AxleRatio;
        ratioEff = ifelse(is4Lo, appData.userInputs.LowRangeRatio * axleRatio, axleRatio);
        tireCirc = appData.userInputs.TireCircumference / 25.4; 
        
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
    appData = fig.UserData; if isempty(appData.workingCopy) || ~isfield(appData.workingCopy, 'modified') || ~appData.workingCopy.modified, uialert(fig, 'No modifications.', 'Info'); success = true; return; end
    wc = appData.workingCopy; msg = sprintf('Overwrite "%s" or create new?', wc.name);
    toggleTablePriority(fig, true); selection = uiconfirm(fig, msg, 'Save', 'Options', {'Overwrite Original', 'Save as New', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 3); toggleTablePriority(fig, false);
    success = false;
    if strcmp(selection, 'Overwrite Original')
        idx = appData.editIndex; if idx > 0, wc.modified = false; appData.allMaps{idx} = wc; appData.history = {}; fig.UserData = appData; refreshTableStyles(fig); uialert(fig, 'Saved.', 'Saved'); success = true; else, success = saveAsNew(fig); end
    elseif strcmp(selection, 'Save as New'), success = saveAsNew(fig); end
end
function success = saveAsNew(fig)
    appData = fig.UserData; wc = appData.workingCopy; defaultName = wc.name + "_MOD";
    toggleTablePriority(fig, true); answer = inputdlg('Name:', 'Save As', [1 50], {char(defaultName)}); toggleTablePriority(fig, false);
    if isempty(answer), success = false; return; end
    newName = string(answer{1}); wc.name = newName; wc.modified = false; appData.allMaps{end+1} = wc;
    newNames = string(cellfun(@(m) m.name, appData.allMaps, 'UniformOutput', false));
    appData.handles.dd1.Items = newNames; appData.handles.dd1.Value = newName; appData.handles.dd2.Items = newNames;
    appData.editIndex = length(appData.allMaps); appData.workingCopy = wc; appData.history = {};
    if ~isempty(appData.tableFig) && isvalid(appData.tableFig), appData.tableFig.Name = ['Table: ' char(wc.name)]; refreshTableStyles(fig); end
    fig.UserData = appData; uialert(fig, 'Saved.', 'Success'); success = true;
end
function txt = getShiftInfoText(rpm, pedal, label, gearIdx, appData, is4Lo, origRPM, origPedal)
    if nargin < 7 || isempty(origRPM), origRPM = rpm; end
    if nargin < 8 || isempty(origPedal), origPedal = pedal; end

    % Ensure scalar doubles
    rpm = double(rpm(1)); pedal = double(pedal(1));
    origRPM = double(origRPM(1)); origPedal = double(origPedal(1));

    gearRatios = appData.userInputs.GearRatios; axleRatio = appData.userInputs.AxleRatio; tireCirc = appData.userInputs.TireCircumference / 25.4;
    ratioEff = ifelse(is4Lo, appData.userInputs.LowRangeRatio * axleRatio, axleRatio);
    
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

    cGreen = '\color[rgb]{0,0.5,0}';
    cBlack = '\color{black}';
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
        
        if diffVal > 0.001
            diffStr = sprintf(['%s(+' fmt '%s)'], cBlue, diffVal, suffix);
        elseif diffVal < -0.001
            diffStr = sprintf(['%s(' fmt '%s)'], cRed, diffVal, suffix);
        else
            diffStr = [cBlack '(0)'];
        end
        
        % FixedWidth Alignment: Name(5) Cur(7) Orig(7)
        sName = sprintf('%-5s', name);
        sCur  = sprintf([fmt '%s'], cur, suffix);
        sOrig = sprintf([fmt '%s'], orig, suffix);
        
        % Pad values
        sCur = sprintf('%7s', sCur);
        sOrig = sprintf('%7s', sOrig);
        
        % Using %s for colors ensures no escape character warnings and proper rendering
        str = sprintf('%s %s%s %s%s %s', sName, cGreen, sCur, cBlack, sOrig, diffStr);
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
    appData = fig.UserData; maps = appData.allMaps; fn = 'Shift_Maps_Export.xlsx';
    if ~isempty(appData.workingCopy)
         m = appData.workingCopy; T1 = array2table(m.Z_up, 'VariableNames', compose("Upshift_%d", 1:7));
         T2 = array2table(m.Z_down, 'VariableNames', compose("Downshift_%d", 1:7));
         T3 = array2table(m.pedal', 'VariableNames', {'Pedal'});
         writetable([T3 T1 T2], fn, 'Sheet', extractBefore(m.name, min(31, strlength(m.name)))); uialert(fig, ['Exported to ' fn], 'Success');
    else, uialert(fig, 'No active map.', 'Info'); end
end
function exportAllDCM(fig)
    appData = fig.UserData;
    if isempty(appData.allMaps), uialert(fig, 'No maps available.', 'Error'); return; end
    [file, path] = uiputfile('*.dcm', 'Save DCM File', 'Shift_Maps.dcm');
    if isequal(file, 0), return; end
    fullPath = fullfile(path, file);
    fid = fopen(fullPath, 'w');
    if fid == -1, uialert(fig, 'Could not open file for writing.', 'Error'); return; end

    % === HEADER ===
    fprintf(fid, '* encoding="ISO-8859-1"\n');
    fprintf(fid, '* DAMOS format\n');
    fprintf(fid, '* Created by Pattern Plotter V20.1\n');
    fprintf(fid, '* Creation date: %s\n', datestr(now, 'mm/dd/yyyy HH:MM:SS'));
    fprintf(fid, '*\n');
    fprintf(fid, '* Project: Export\n');
    fprintf(fid, '* Dataset: User_Export\n\n');
    fprintf(fid, 'KONSERVIERUNG_FORMAT 2.0\n\n');
    
    % Memory segments (Generic placeholder as per request for format consistency)
    fprintf(fid, '* Address EPK: 0xA01E0429\n');
    fprintf(fid, '* EPK: FCME25C2D04287\n');
    fprintf(fid, '* Memory segments:\n');
    fprintf(fid, '*  _CAL_ROM_APD0._M DATA INTERN 0xA01E0000 0xE8000\n');
    fprintf(fid, '*  _CAL_ROM_APD1._M DATA INTERN 0xA05A0000 0x60000\n');
    fprintf(fid, '\n\n');

    % === FUNKTIONEN BLOCK ===
    fprintf(fid, 'FUNKTIONEN\n');
    fprintf(fid, '   FKT jSklDaten_Fktn "" "Calibration values of the Instance jSklDaten" \n');
    fprintf(fid, 'END\n\n');

    % === MAP EXPORT ===
    % Column Labels for 14 columns
    colLabels = { ...
        '"US12"', '"US23"', '"US34"', '"US45"', '"US56"', '"US67"', '"US78"', ...
        '"DS21"', '"DS32"', '"DS43"', '"DS54"', '"DS65"', '"DS76"', '"DS87"'};

    for i = 1:length(appData.allMaps)
        map = appData.allMaps{i};
        mapName = map.name;
        
        % Combine Data: 14 Columns (7 Up + 7 Down)
        % Ensure Z_up and Z_down are same size
        zUp = map.Z_up; 
        zDn = map.Z_down;
        
        % Handle pedal (Y-axis)
        pedal = map.pedal;
        
        numRows = length(pedal);
        numCols = 14; 
        
        fprintf(fid, 'KENNFELD %s %d %d\n', mapName, numCols, numRows);
        fprintf(fid, '   LANGNAME "Shifting characteristic curves (ID==%d)"\n', i); % Using index as ID, or extract from name if possible
        fprintf(fid, '   FUNKTION jSklDaten_Fktn \n');
        fprintf(fid, '   EINHEIT_X ""\n');
        fprintf(fid, '   EINHEIT_Y "%%"\n');
        fprintf(fid, '   EINHEIT_W "1/min"\n');
        
        % Write ST_TX/X (Text Axis)
        % Wrap every 6 items
        fprintf(fid, '   ST_TX/X');
        for c = 1:numCols
            if mod(c-1, 6) == 0 && c > 1
                fprintf(fid, '\n   ST_TX/X');
            end
            fprintf(fid, '   %s', colLabels{c});
        end
        fprintf(fid, '\n');
        
        % Write Data Rows (Interleaved ST/Y and WERT)
        for r = 1:numRows
            % ST/Y value
            fprintf(fid, '   ST/Y   %.16f\n', pedal(r));
            
            % WERT values (14 cols)
            rowVals = [zUp(r, :), zDn(r, :)];
            
            fprintf(fid, '   WERT');
            for c = 1:numCols
                if mod(c-1, 6) == 0 && c > 1
                    fprintf(fid, '\n   WERT');
                end
                fprintf(fid, '   %.16f', rowVals(c));
            end
            fprintf(fid, '\n');
        end
        
        fprintf(fid, 'END\n\n');
    end
    
    fclose(fid);
    uialert(fig, 'DCM Export Complete (Advanced Format).', 'Success');
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
        % Handle errors gracefully
        if exist('d', 'var') && isvalid(d)
            delete(d);
        end
        errordlg(ME.message, 'Gear Data Error');
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
function out = ifelse(cond, a, b)
    if cond, out = a; else, out = b; end
end
function onPopupPaste(d, src)
    % Called after pasting into the Popup Editor table
    % pushPopupHistory(d, src.Data); % Could support undo if needed, but risky for bulk
    
    % Re-apply heatmap styles since values changed
    if exist('applyHeatmapStyles', 'file') == 2 || exist('applyHeatmapStyles', 'var')
         try applyHeatmapStyles(src); catch, end
    end
end
function copySelection(t)
    if isempty(t.Selection), return; end
    rows = unique(t.Selection(:,1));
    cols = unique(t.Selection(:,2));
    minR = min(rows); maxR = max(rows);
    minC = min(cols); maxC = max(cols);
    data = t.Data;
    subData = data(minR:maxR, minC:maxC);
    str = '';
    [nR, nC] = size(subData);
    for r = 1:nR
        rowStr = '';
        for c = 1:nC
            if iscell(subData)
                val = subData{r,c};
            else
                val = subData(r,c);
            end
            if isnumeric(val), val = num2str(val); end
            if ismissing(val), val = ''; end
            rowStr = [rowStr, char(string(val)), sprintf('\t')];
        end
        str = [str, rowStr(1:end-1), newline];
    end
    clipboard('copy', str);
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
        numericData = cellfun(@double, tData(:, 2:end)); 
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
    
    % Determine effective axle ratio (including 4Lo)
    ratioEff = ar;
    if isfield(userInputs, 'LowRangeRatio') && isfield(appData, 'handles') && isvalid(appData.handles.cb4Lo) && appData.handles.cb4Lo.Value
        ratioEff = ratioEff * userInputs.LowRangeRatio;
    end
    
    rpm = val;
    switch type
        case 'MPH'
            % RPM = MPH * 1056 / TireCirc * RatioEff
            rpm = (val * 1056 * ratioEff) / tc;
        case 'KPH'
             mph = val / 1.60934;
             rpm = (mph * 1056 * ratioEff) / tc;
        case 'Turbine'
            rpm = val / gr(gear);
        case 'Engine'
            rpm = val / gr(gear);
    end
end

%% === MULTI MAP EDITOR ===
function openMultiMapEditor(fig)
    appData = fig.UserData;
    if isempty(appData.allMaps), uialert(fig, 'No maps available.', 'Error'); return; end
    
    d = uifigure('Name', 'Multi Map Editor', 'Position', [100 100 1200 600]);
    appData.multiMapFig = d; fig.UserData = appData;

    gl = uigridlayout(d, [2, 1]);
    gl.RowHeight = {'1x', 50};
    
    tg = uitabgroup(gl);
    
    % Get Map Names as String Array
    mapNames = string(cellfun(@(m) m.name, appData.allMaps, 'UniformOutput', false));
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
        'ButtonPushedFcn', @(~,~) loadTab1Data(fig, d));
    
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
        'CellEditCallback', @(src, e) onMultiMapEdit(src, e));
    
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
        'ValueChangedFcn', @(~,~) loadTab2Data(fig, d));
    uibutton(distGrid, 'Text', '+', 'ButtonPushedFcn', @(~,~) adjustDistance(fig, d, 10));
    
    % 5. Load/Reset Button
    btnCalc = uibutton(dsGrid, 'Text', 'Load / Reset', 'BackgroundColor', [0.6 1 0.6], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) loadTab2Data(fig, d));
    btnCalc.Layout.Row = 2; btnCalc.Layout.Column = 5;
    
    % Table Area
    tDS = uitable(gl2, 'Data', {}, 'ColumnName', {'Pedal %', 'Center (Avg)', 'Map A New', 'Map B New'}, ...
        'ColumnEditable', [false, false, true, true], ...
        'RowName', 'numbered', 'CellEditCallback', @(src, e) onMultiMapEdit(src, e));

    %% --- BOTTOM PANEL ---
    pnlBot = uipanel(gl);
    botGrid = uigridlayout(pnlBot, [1, 3]);
    botGrid.ColumnWidth = {'1x', 200, '1x'};
    
    uibutton(botGrid, 'Text', 'SAVE CHANGES', 'BackgroundColor', [1 0.8 0], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) saveDispatcher(fig, d));
        
    d.UserData = struct('tabGroup', tg, ...
        'tab1', struct('mapDDs', mapDDs, 'ddGear', ddGear, 'table', t, 'loadedData', []), ...
        'tab2', struct('ddRef', ddRef, 'ddTgt', ddTgt, 'ddGear', ddDSGear, 'efOffset', efOffset, 'table', tDS, 'loadedData', []));
    
    % Initial Load Tab 1
    try
        loadTab1Data(fig, d);
    catch
    end
end

function loadTab1Data(fig, multiFig)
    appData = fig.UserData;
    h = multiFig.UserData;
    t1 = h.tab1;
    
    if isempty(appData.allMaps), return; end
    allMapNames = string(cellfun(@(m) m.name, appData.allMaps, 'UniformOutput', false));
    
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
    allNames = string(cellfun(@(m) m.name, appData.allMaps, 'UniformOutput', false));
    
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
    sYellow = uistyle('BackgroundColor', [1 1 0.8]);
    addStyle(t2.table, sBlue, 'column', 3);
    addStyle(t2.table, sYellow, 'column', 4);
    
    t2.loadedData = struct('refIdx', refIdx, 'tgtIdx', tgtIdx, 'colIdx', colIdx, 'isUp', isUp);
    h.tab2 = t2; multiFig.UserData = h;
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
    
    fig.UserData = appData;
    if isNew
        newMapList = cellfun(@(m) m.name, appData.allMaps, 'UniformOutput', false);
        appData.handles.dd1.Items = newMapList; appData.handles.dd2.Items = newMapList;
        for k=1:5, t1.mapDDs(k).Items = newMapList; h.tab2.ddRef.Items = newMapList; h.tab2.ddTgt.Items = newMapList; end
    end
    uialert(multiFig, 'Maps Saved Successfully.', 'Success');
    applyMultiMapStyles(t1.table); updatePlot(fig);
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
    
    fig.UserData = appData;
    uialert(multiFig, 'Both Maps Updated Successfully.', 'Success');
    updatePlot(fig);
end

function onMultiMapEdit(src, event)
    % Highlight edited cell in Dark Yellow until save
    addStyle(src, uistyle('BackgroundColor', [1 0.8 0], 'FontWeight', 'bold'), 'cell', event.Indices);
end

function applyMultiMapStyles(t)
    removeStyle(t);
    nCols = size(t.Data, 2);
    if nCols == 0, return; end
    
    % Colors
    cPedal = [0.95 0.85 1]; % Light Purple
    cOld   = [0.85 0.95 1]; % Light Blue
    cNew   = [1 1 0.8];     % Light Yellow
    
    sPedal = uistyle('BackgroundColor', cPedal);
    sOld   = uistyle('BackgroundColor', cOld);
    sNew   = uistyle('BackgroundColor', cNew);
    
    % Apply to columns (1,4,7... | 2,5,8... | 3,6,9...)
    % Indices: 1:3:nCols, 2:3:nCols, 3:3:nCols
    addStyle(t, sPedal, 'column', 1:3:nCols);
    addStyle(t, sOld,   'column', 2:3:nCols);
    addStyle(t, sNew,   'column', 3:3:nCols);
end

function [isUp, colIdx] = getGearIndex(gearStr)
    % Returns isUp boolean and Column Index for Z_up or Z_down matrices
    % Z_up columns: 1->2, 2->3, 3->4, 4->5, 5->6, 6->7, 7->8 (Indices 1 to 7)
    % Z_down columns: 2->1, 3->2, 4->3, 5->4, 6->5, 7->6, 8->7 (Indices 1 to 7)
    
    tokens = regexp(gearStr, '(\d+)->(\d+)', 'tokens');
    if isempty(tokens), isUp=[]; colIdx=[]; return; end
    
    g1 = str2double(tokens{1}{1});
    g2 = str2double(tokens{1}{2});
    
    if g2 > g1
        isUp = true;
        colIdx = g1; % 1->2 is index 1
        if colIdx < 1 || colIdx > 7, colIdx = []; end
    else
        isUp = false;
        colIdx = g2; % 2->1 is index 1 (Target Gear)
                     % 3->2 is index 2
                     % 8->7 is index 7
        if colIdx < 1 || colIdx > 7, colIdx = []; end
    end
end

function wc = enforceRowConstraints(wc)
    % Ensures Row 1 = Row 2 and Last Row = Second to Last Row
    nRows = size(wc.Z_up, 1);
    if nRows >= 2
        % Sync Row 1 to Row 2
        wc.Z_up(1, :) = wc.Z_up(2, :);
        wc.Z_down(1, :) = wc.Z_down(2, :);
        
        % Sync Last Row to Second to Last Row
        wc.Z_up(nRows, :) = wc.Z_up(nRows-1, :);
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
        idx = find(strcmp(cellfun(@(m) m.name, appData.allMaps, 'UniformOutput', false), mapAName), 1);
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
               'NumberTitle', 'off', 'MenuBar', 'figure', 'ToolBar', 'figure');
    
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
    [X, Y] = meshgrid(1:7, map.pedal);
    
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
        pedal = map.pedal;
        
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

function updateTCC3DPlot(ax, map, appData)
    cla(ax);
    hold(ax, 'on');
    
    % 1. Get Map ID
    mapName = map.name;
    mapNumStr = regexp(mapName, 'SKL_GKF_(\d+)', 'tokens');
    if isempty(mapNumStr), title(ax, 'Invalid Map Name'); return; end
    mapID = str2double(mapNumStr{1}{1});
    
    if isempty(appData.wtZustand), title(ax, 'No WT_ZUSTAND'); return; end
    stateIdx = find(appData.wtZustand(1,:) == mapID, 1);
    if isempty(stateIdx), title(ax, 'Map not in ZUSTAND'); return; end
    stateVal = appData.wtZustand(2, stateIdx);
    
    kwkRow = stateVal + 1;
    if kwkRow > size(appData.kwkData, 1), title(ax, 'KWK Index OOB'); return; end
    
    % Loop Gears
    % Mode Colors: RO=Red, OR=Blue, RC=Magenta
    modeColors = containers.Map({1, 2, 3}, {'r', 'b', 'm'}); 
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
                    
                    color = modeColors(mIdx);
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

function Intermaps(fig)
% Intermaps - Interpolation Tables Editor with INCA-style display
    appData = fig.UserData;
    if isfield(appData, 'interpFig') && ~isempty(appData.interpFig) && isvalid(appData.interpFig)
        figure(appData.interpFig); return;
    end
    
    % Loading
    loadFig = uifigure('Name', 'Loading...', 'Position', [500 400 280 70], 'WindowStyle', 'modal');
    uilabel(loadFig, 'Text', 'Loading Interpolation Data...', 'Position', [15 25 250 25], 'FontSize', 12, 'FontWeight', 'bold');
    drawnow;
    
    % Pre-load all data
    varDefs = getInterpVarDefs();
    interpData = struct();
    T = appData.T;
    for i = 1:size(varDefs, 1)
        vn = varDefs{i, 1};
        sn = matlab.lang.makeValidName(vn);
        interpData.(sn) = extractInterpVariable(T, vn);
    end
    delete(loadFig);
    
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
    
    buildInterpTabs(fig, d, tg, interpData);
    
    % Buttons
    btnPnl = uipanel(mainGl, 'BorderType', 'none');
    btnPnl.Layout.Row = 2;
    btnGl = uigridlayout(btnPnl, [1 6]);
    btnGl.ColumnWidth = {140, 120, 120, 120, '1x', 90};
    btnGl.Padding = [8 3 8 3];
    
    uibutton(btnGl, 'Text', 'SAVE CHANGES', 'BackgroundColor', [1 0.8 0], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) saveInterpData(fig, d));
    uibutton(btnGl, 'Text', 'Refresh', 'BackgroundColor', [0.85 0.92 1], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) refreshInterpWin(fig, d, tg));
    uibutton(btnGl, 'Text', 'Export', 'BackgroundColor', [0.92 0.92 0.92], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) exportInterpData(fig));
    uibutton(btnGl, 'Text', 'Undo', 'BackgroundColor', [1 0.9 0.9], 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~,~) undoInterpEdit(fig));
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
        'FSIT_SWIOD','SiOD'; 'SIOD_RGA_EXIT','SiOD'; 'SIOD_VEntr1G','SiOD'; 'SIOD_VEntr2G','SiOD'; 'SIOD_VEntr3G','SiOD'; 'SIOD_VEntr4G','SiOD'; 'SIOD_NabEntr5G','SiOD'; 'SIOD_NabEntr6G','SiOD'; 'SIOD_NabEntr7G','SiOD'; 'SIOD_Voffs','SiOD';
        'SIBE_AdiffMidPar1','Grade_Tables'; 'SIBE_AdiffMidPar2','Grade_Tables'; 'SIBE_AdiffMidPar3','Grade_Tables'; 'SIBE_AdiffMidPar4','Grade_Tables'; 'SIBE_AdiffMidPar5','Grade_Tables';
        'SIBE_AdiffMidParForUKTYP','Grade_Shift'; 'SIBE_AdiffMidParForUKFGR','Grade_Shift'; 'SIBE_AdiffMidParForUKBSG','Grade_Shift';
        'SIBE_AdiffMidForUKECO','Grade_ECO'; 'SIBE_AdiffMidForUKTOW','Grade_Tow'; 'SIBE_AdiffMidForUKLOW','Grade_4Lo';
        'SIBE_AdiffMidForUKGGS','Grade_GGS'; 'SIBE_AdiffMidForUKGGS_LOW','Grade_GGS';
        'SIBE_AdiffMidForUKSND','Grade_Sand'; 'SIBE_AdiffMidForUKSND_LOW','Grade_Sand';
        'SIBE_AdiffMidForUKXC','Grade_Mud'; 'SIBE_AdiffMidForUKXC_LOW','Grade_Mud';
        'UKSVF_NABADIFF_21RS','Brake_ADIFF'; 'UKSVF_NABADIFF_32RS','Brake_ADIFF'; 'UKSVF_NABADIFF_43RS','Brake_ADIFF'; 'UKSVF_NABADIFF_54RS','Brake_ADIFF'; 'UKSVF_NABADIFF_65RS','Brake_ADIFF'; 'UKSVF_NABADIFF_76RS','Brake_ADIFF'; 'UKSVF_NABADIFF_87RS','Brake_ADIFF';
        'UKSVF_NABKF_21RS','Brake_KF'; 'UKSVF_NABKF_32RS','Brake_KF'; 'UKSVF_NABKF_43RS','Brake_KF'; 'UKSVF_NABKF_54RS','Brake_KF'; 'UKSVF_NABKF_65RS','Brake_KF'; 'UKSVF_NABKF_76RS','Brake_KF'; 'UKSVF_NABKF_87RS','Brake_KF';
    };
end

%% === TAB BUILDING ===
function buildInterpTabs(mainFig, interpFig, tg, interpData)
    buildScrollTab(mainFig, interpFig, uitab(tg,'Title','SiFCO'), interpData, {'FSIT_SWIFCO','SIFCO_EngSpdMin','SIFCO_EngSpdMinBSG','SIZW_FacNMoMinProgIdFCO'});
    buildScrollTab(mainFig, interpFig, uitab(tg,'Title','SiALT'), interpData, {'FSIT_SWIALT','SIALT_EngSpdMinAcpt','SIALT_EngSpdMin','SIALT_EngSpdMinM','SIZW_FacNMoMinProgIdAlti'});
    buildScrollTab(mainFig, interpFig, uitab(tg,'Title','Nab Min Tables'), interpData, {'UKZW_NabMin','UKZW_NabMin_LOW','UKZW_NabMinAlti','UKZW_NabMinAltiLow'});
    buildScrollTab(mainFig, interpFig, uitab(tg,'Title','SiOD'), interpData, {'FSIT_SWIOD','SIOD_RGA_EXIT','SIOD_VEntr1G','SIOD_VEntr2G','SIOD_VEntr3G','SIOD_VEntr4G','SIOD_NabEntr5G','SIOD_NabEntr6G','SIOD_NabEntr7G','SIOD_Voffs'});
    
    gradeTab = uitab(tg,'Title','Grade');
    gTg = uitabgroup(gradeTab);
    buildScrollTab(mainFig, interpFig, uitab(gTg,'Title','Grade Tables'), interpData, {'SIBE_AdiffMidPar1','SIBE_AdiffMidPar2','SIBE_AdiffMidPar3','SIBE_AdiffMidPar4','SIBE_AdiffMidPar5'});
    buildScrollTab(mainFig, interpFig, uitab(gTg,'Title','Shifting Situation'), interpData, {'SIBE_AdiffMidParForUKTYP','SIBE_AdiffMidParForUKFGR','SIBE_AdiffMidParForUKBSG'});
    buildScrollTab(mainFig, interpFig, uitab(gTg,'Title','ECO Grade'), interpData, {'SIBE_AdiffMidForUKECO'});
    buildScrollTab(mainFig, interpFig, uitab(gTg,'Title','Tow Grade'), interpData, {'SIBE_AdiffMidForUKTOW'});
    buildScrollTab(mainFig, interpFig, uitab(gTg,'Title','4Lo Grade'), interpData, {'SIBE_AdiffMidForUKLOW'});
    buildScrollTab(mainFig, interpFig, uitab(gTg,'Title','GGS Grade'), interpData, {'SIBE_AdiffMidForUKGGS','SIBE_AdiffMidForUKGGS_LOW'});
    buildScrollTab(mainFig, interpFig, uitab(gTg,'Title','Sand Grade'), interpData, {'SIBE_AdiffMidForUKSND','SIBE_AdiffMidForUKSND_LOW'});
    buildScrollTab(mainFig, interpFig, uitab(gTg,'Title','Mud Grade'), interpData, {'SIBE_AdiffMidForUKXC','SIBE_AdiffMidForUKXC_LOW'});
    
    brakeTab = uitab(tg,'Title','Brake');
    bTg = uitabgroup(brakeTab);
    buildScrollTab(mainFig, interpFig, uitab(bTg,'Title','NAB ADIFF (Grade)'), interpData, {'UKSVF_NABADIFF_21RS','UKSVF_NABADIFF_32RS','UKSVF_NABADIFF_43RS','UKSVF_NABADIFF_54RS','UKSVF_NABADIFF_65RS','UKSVF_NABADIFF_76RS','UKSVF_NABADIFF_87RS'});
    buildScrollTab(mainFig, interpFig, uitab(bTg,'Title','NAB KF (Driver)'), interpData, {'UKSVF_NABKF_21RS','UKSVF_NABKF_32RS','UKSVF_NABKF_43RS','UKSVF_NABKF_54RS','UKSVF_NABKF_65RS','UKSVF_NABKF_76RS','UKSVF_NABKF_87RS'});
end

function buildScrollTab(mainFig, interpFig, tab, interpData, varNames)
    % Single scrollable panel for entire tab content
    gl = uigridlayout(tab, [1 1]);
    gl.Padding = [0 0 0 0];
    
    % Scrollable panel - scrollbar on right side of tab
    sp = uipanel(gl, 'Scrollable', 'on', 'BorderType', 'none');
    
    % Calculate heights
    nv = length(varNames);
    heights = zeros(1, nv);
    for i = 1:nv
        sn = matlab.lang.makeValidName(varNames{i});
        if isfield(interpData, sn) && ~isempty(interpData.(sn))
            vi = interpData.(sn);
            if strcmp(vi.type, 'VALUE')
                heights(i) = 55;
            elseif strcmp(vi.type, 'MAP')
                nr = size(vi.data, 1);
                heights(i) = 60 + (nr + 1) * 24;
            elseif strcmp(vi.type, 'CURVE')
                heights(i) = 60 + 2 * 24;
            else
                heights(i) = 60;
            end
        else
            heights(i) = 50;
        end
    end
    
    cgl = uigridlayout(sp, [nv 1]);
    cgl.RowHeight = num2cell(heights);
    cgl.Padding = [8 8 8 8];
    cgl.RowSpacing = 10;
    
    for i = 1:nv
        vn = varNames{i};
        sn = matlab.lang.makeValidName(vn);
        
        pnl = uipanel(cgl, 'Title', vn, 'FontWeight', 'bold', 'FontSize', 10);
        pnl.Layout.Row = i;
        
        if ~isfield(interpData, sn) || isempty(interpData.(sn))
            g = uigridlayout(pnl, [1 1]); g.Padding = [5 3 5 3];
            uilabel(g, 'Text', ['Not found: ' vn], 'FontColor', [0.7 0 0], 'FontSize', 10);
            continue;
        end
        
        vi = interpData.(sn);
        if strcmp(vi.type, 'VALUE')
            buildValueTbl(mainFig, interpFig, pnl, vi);
        elseif strcmp(vi.type, 'MAP')
            buildMapTbl(mainFig, interpFig, pnl, vi);
        elseif strcmp(vi.type, 'CURVE')
            buildCurveTbl(mainFig, interpFig, pnl, vi);
        end
    end
end

%% === TABLE BUILDERS ===
function buildValueTbl(mainFig, ~, pnl, vi)
    g = uigridlayout(pnl, [1 3]);
    g.ColumnWidth = {55, 90, '1x'};
    g.Padding = [5 2 5 2];
    
    uilabel(g, 'Text', 'Value:', 'FontWeight', 'bold', 'FontSize', 10);
    t = uitable(g, 'Data', {vi.value}, 'ColumnName', {vi.unit}, 'RowName', [], ...
        'ColumnEditable', true, 'ColumnWidth', {70}, 'FontSize', 10);
    t.CellEditCallback = @(s,e) onInterpEdit(mainFig, s, e, vi);
    t.CellSelectionCallback = @(s,e) onInterpSel(mainFig, s, e, vi.name);
    uilabel(g, 'Text', '');
    storeTbl(mainFig, t, vi);
end

function buildMapTbl(mainFig, interpFig, pnl, vi)
    g = uigridlayout(pnl, [2 1]);
    g.RowHeight = {'1x', 14};
    g.Padding = [2 2 2 2];
    g.RowSpacing = 2;
    
    nr = size(vi.data, 1);
    nc = size(vi.data, 2);
    
    % INCA format table
    td = cell(nr + 1, nc + 1);
    td{1, 1} = vi.name;
    
    % X-axis in first row
    if ~isempty(vi.xAxis)
        for c = 1:min(nc, length(vi.xAxis))
            td{1, c+1} = vi.xAxis(c);
        end
    else
        for c = 1:nc, td{1, c+1} = c; end
    end
    
    % Y-axis in first column
    if ~isempty(vi.yAxis)
        for r = 1:min(nr, length(vi.yAxis))
            td{r+1, 1} = vi.yAxis(r);
        end
    else
        for r = 1:nr, td{r+1, 1} = r; end
    end
    
    % Data
    for r = 1:nr
        for c = 1:nc
            td{r+1, c+1} = vi.data(r, c);
        end
    end
    
    cn = arrayfun(@(x) num2str(x), 1:(nc+1), 'UniformOutput', false);

    % Use extracted headers for ColumnName if available
    if isfield(vi, 'headers') && ~isempty(vi.headers)
        hLen = length(vi.headers);
        if hLen == nc
            cn(2:end) = cellstr(vi.headers);
        elseif hLen < nc
            cn(2:1+hLen) = cellstr(vi.headers);
        elseif hLen > nc
            cn(2:end) = cellstr(vi.headers(1:nc));
        end
    end

    t = uitable(g, 'Data', td, 'ColumnName', cn, 'RowName', [], ...
        'ColumnEditable', true, 'FontSize', 10);
    
    cw = max(55, min(85, floor(1200 / (nc + 1))));
    t.ColumnWidth = repmat({cw}, 1, nc + 1);
    
    gs = uistyle('BackgroundColor', [0.85 0.85 0.85], 'FontWeight', 'bold');
    addStyle(t, gs, 'row', 1);
    addStyle(t, gs, 'column', 1);
    
    t.CellEditCallback = @(s,e) onMapEdit(mainFig, s, e, vi);
    t.CellSelectionCallback = @(s,e) onInterpSel(mainFig, s, e, vi.name);
    
    cm = uicontextmenu(interpFig);
    uimenu(cm, 'Text', 'Add (+/-)...', 'MenuSelectedFcn', @(~,~) interpMath(mainFig, 'add'));
    uimenu(cm, 'Text', 'Multiply (*)...', 'MenuSelectedFcn', @(~,~) interpMath(mainFig, 'mult'));
    uimenu(cm, 'Text', 'Divide (/)...', 'MenuSelectedFcn', @(~,~) interpMath(mainFig, 'div'));
    uimenu(cm, 'Text', 'Percent (%)...', 'MenuSelectedFcn', @(~,~) interpMath(mainFig, 'pct'));
    uimenu(cm, 'Text', 'Copy', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) copySelection(t));
    uimenu(cm, 'Text', 'Paste', 'MenuSelectedFcn', @(~,~) pasteSelection(t, @(s) onInterpPaste(mainFig, s, vi.name)));
    t.ContextMenu = cm;
    
    uilabel(g, 'Text', sprintf('MAP (%dx%d) | Unit: %s', nr, nc, vi.unit), ...
        'FontSize', 9, 'FontAngle', 'italic', 'FontColor', [0.4 0.4 0.5]);
    
    vi.isINCA = true;
    storeTbl(mainFig, t, vi);
end

function buildCurveTbl(mainFig, interpFig, pnl, vi)
    g = uigridlayout(pnl, [2 1]);
    g.RowHeight = {'1x', 14};
    g.Padding = [2 2 2 2];
    g.RowSpacing = 2;
    
    nc = length(vi.data);
    td = cell(2, nc);
    
    if ~isempty(vi.xAxis)
        for c = 1:min(nc, length(vi.xAxis))
            td{1, c} = vi.xAxis(c);
        end
    else
        for c = 1:nc, td{1, c} = c - 1; end
    end
    
    for c = 1:nc, td{2, c} = vi.data(c); end
    
    cn = arrayfun(@(x) num2str(x), 1:nc, 'UniformOutput', false);

    % Use extracted headers for ColumnName if available
    if isfield(vi, 'headers') && ~isempty(vi.headers)
        hLen = length(vi.headers);
        if hLen == nc
            cn = cellstr(vi.headers);
        elseif hLen > nc
            cn = cellstr(vi.headers(1:nc));
        end
    end

    t = uitable(g, 'Data', td, 'ColumnName', cn, 'RowName', {'X-Axis','Value'}, ...
        'ColumnEditable', true, 'FontSize', 10);
    
    cw = max(50, min(75, floor(1200 / min(nc, 18))));
    t.ColumnWidth = repmat({cw}, 1, nc);
    
    gs = uistyle('BackgroundColor', [0.85 0.85 0.85], 'FontWeight', 'bold');
    addStyle(t, gs, 'row', 1);
    
    t.CellEditCallback = @(s,e) onCurveEdit(mainFig, s, e, vi);
    t.CellSelectionCallback = @(s,e) onInterpSel(mainFig, s, e, vi.name);
    
    cm = uicontextmenu(interpFig);
    uimenu(cm, 'Text', 'Add (+/-)...', 'MenuSelectedFcn', @(~,~) interpMath(mainFig, 'add'));
    uimenu(cm, 'Text', 'Multiply (*)...', 'MenuSelectedFcn', @(~,~) interpMath(mainFig, 'mult'));
    uimenu(cm, 'Text', 'Copy', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) copySelection(t));
    uimenu(cm, 'Text', 'Paste', 'MenuSelectedFcn', @(~,~) pasteSelection(t, @(s) onInterpPaste(mainFig, s, vi.name)));
    t.ContextMenu = cm;
    
    uilabel(g, 'Text', sprintf('CURVE (%d pts) | Unit: %s', nc, vi.unit), ...
        'FontSize', 9, 'FontAngle', 'italic', 'FontColor', [0.4 0.4 0.5]);
    
    vi.isCurve = true;
    storeTbl(mainFig, t, vi);
end

function storeTbl(mainFig, t, vi)
    ad = mainFig.UserData;
    ad.interpTbls{end+1} = t;
    ad.interpInfo{end+1} = vi;
    mainFig.UserData = ad;
end

%% === DATA EXTRACTION - FULLY CORRECTED ===
function vi = extractInterpVariable(T, varName)
    vi = [];
    
    % Find variable name in Var2
    idx = find(contains(T.Var2, varName, 'IgnoreCase', true), 1);
    if isempty(idx), return; end
    
    % Find type marker
    dtype = ''; trow = 0; unit = '-';
    for r = idx : min(idx + 8, height(T))
        c1str = strtrim(string(T{r, 1}));
        
        % Extract unit
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
        vals = str2double(string(table2cell(T(trow, 3:end))));
        vv = vals(~isnan(vals));
        if ~isempty(vv), vi.value = vv(1); end
        vi.dRowStart = trow;
    else
        % Find data rows
        rs = 0; headerRow = 0;
        for r = trow + 1 : min(trow + 8, height(T))
            % Check for data row (mostly numeric)
            vals = str2double(string(table2cell(T(r, 3:end))));
            if sum(~isnan(vals)) > 2, rs = r; break; end

            % Check for header row (contains text in data columns, not system row)
            % Heuristic: First column is empty or not system keyword, and cols 3+ have content
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
            if sum(~isnan(vals)) < 2, break; end
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
        vi.xAxis = findAxisValuesCorrect(T, varName, 'X_AXIS_PTS', re);
        if strcmp(dtype, 'MAP')
            vi.yAxis = findAxisValuesCorrect(T, varName, 'Y_AXIS_PTS', re);
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
            % Check if previous row (r-1) OR row before that (r-2) has our variable name in Var2
            match = false;
            if r > 1
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
    pushInterpHist(mainFig);
    addStyle(t, uistyle('BackgroundColor', [1 1 0]), 'cell', e.Indices);
end

function onMapEdit(mainFig, t, e, ~)
    pushInterpHist(mainFig);
    if e.Indices(1) > 1 && e.Indices(2) > 1
        addStyle(t, uistyle('BackgroundColor', [1 1 0]), 'cell', e.Indices);
    end
end

function onCurveEdit(mainFig, t, e, ~)
    pushInterpHist(mainFig);
    if e.Indices(1) == 2
        addStyle(t, uistyle('BackgroundColor', [1 1 0]), 'cell', e.Indices);
    end
end

function onInterpPaste(mainFig, ~, ~)
    pushInterpHist(mainFig);
end

function pushInterpHist(mainFig)
    ad = mainFig.UserData;
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
    if isempty(ad.interpHist), return; end
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
        end
    end
    mainFig.UserData = ad;
end

function applyGrayHdr(t, vi)
    gs = uistyle('BackgroundColor', [0.85 0.85 0.85], 'FontWeight', 'bold');
    if isfield(vi, 'isINCA') && vi.isINCA
        addStyle(t, gs, 'row', 1);
        addStyle(t, gs, 'column', 1);
    elseif isfield(vi, 'isCurve') && vi.isCurve
        addStyle(t, gs, 'row', 1);
    end
end

function interpMath(mainFig, op)
    ad = mainFig.UserData;
    if isempty(ad.interpSel) || isempty(ad.interpActTbl)
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
            addStyle(t, uistyle('BackgroundColor', [1 1 0]), 'cell', [r c]);
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
    if ~strcmp(uiconfirm(interpFig, 'Save all changes?', 'Confirm', 'Options', {'Yes','Cancel'}), 'Yes')
        return;
    end
    ad = mainFig.UserData;
    T = ad.T;
    
    for i = 1:length(ad.interpTbls)
        t = ad.interpTbls{i};
        vi = ad.interpInfo{i};
        d = t.Data;
        
        if strcmp(vi.type, 'VALUE')
            if vi.dRowStart > 0
                for c = 3:width(T)
                    if ~isnan(str2double(string(T{vi.dRowStart, c})))
                        T{vi.dRowStart, c} = {d{1}}; break;
                    end
                end
            end
        elseif strcmp(vi.type, 'MAP') && vi.isINCA
            nr = size(d, 1) - 1;
            nc = size(d, 2) - 1;
            for dr = 1:nr
                tr = vi.dRowStart + dr - 1;
                if tr <= height(T)
                    for dc = 1:nc
                        val = d{dr + 1, dc + 1};
                        if isnumeric(val), T{tr, 2 + dc} = {val}; end
                    end
                end
            end
        elseif strcmp(vi.type, 'CURVE') && vi.isCurve
            if vi.dRowStart > 0 && vi.dRowStart <= height(T)
                for dc = 1:size(d, 2)
                    val = d{2, dc};
                    if isnumeric(val), T{vi.dRowStart, 2 + dc} = {val}; end
                end
            end
        end
        
        removeStyle(t);
        applyGrayHdr(t, vi);
    end
    
    ad.T = T;
    ad.interpHist = {};
    mainFig.UserData = ad;
    uialert(interpFig, 'Saved!', 'Success', 'Icon', 'success');
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
    buildInterpTabs(mainFig, interpFig, tg, interpData);
    uialert(interpFig, 'Refreshed!', 'OK', 'Icon', 'info');
end

function exportInterpData(mainFig)
    ad = mainFig.UserData;
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
    ad = mainFig.UserData;
    ad.interpFig = gobjects(0);
    ad.interpTbls = {};
    ad.interpInfo = {};
    ad.interpHist = {};
    if isfield(ad, 'interpData'), ad = rmfield(ad, 'interpData'); end
    mainFig.UserData = ad;
    delete(interpFig);
end

function exportHandler(fig)
    selection = uiconfirm(fig, 'Do you wanna create an excel sheet or DCM or both or cancel?', 'Export', ...
        'Options', {'Excel Sheet', 'DCM', 'Both', 'Cancel'}, ...
        'DefaultOption', 1, 'CancelOption', 4);
    
    switch selection
        case 'Excel Sheet'
            exportModifiedMaps(fig);
        case 'DCM'
            exportAllDCM(fig);
        case 'Both'
            exportModifiedMaps(fig);
            exportAllDCM(fig);
    end
end

function configureMCRSpeedup(fig)
    % Checks for MCR_CACHE_ROOT and prompts user to set it for faster startup
    if ~isdeployed || ~ispc, return; end 
    
    envVar = 'MCR_CACHE_ROOT';
    cachePath = 'C:\MatlabCache';
    currentVal = getenv(envVar);
    
    if isempty(currentVal)
        msg = sprintf('To speed up future startups, it is recommended to set a persistent cache at %s.\n\nDo you want to apply this setting now?\n(Requires Restart of App)', cachePath);
        
        selection = uiconfirm(fig, msg, 'Optimize Startup Speed', ...
            'Options', {'Yes, Optimize', 'No, Skip'}, ...
            'DefaultOption', 1, 'CancelOption', 2, 'Icon', 'info');
            
        if strcmp(selection, 'Yes, Optimize')
            try
                if ~exist(cachePath, 'dir')
                    mkdir(cachePath);
                end
                
                % Use setx to set the variable persistently for the user
                [status, ~] = system(sprintf('setx %s "%s"', envVar, cachePath));
                
                if status == 0
                    uialert(fig, 'Optimization applied! The application will load significantly faster next time.', 'Success', 'Icon', 'success');
                else
                    uialert(fig, 'Could not set environment variable. Please run as Administrator or set manually.', 'Error', 'Icon', 'error');
                end
            catch ME
                uialert(fig, ['Error: ' ME.message], 'Error');
            end
        end
    end
end

%% === HELPER FUNCTIONS (MOVED FROM NESTED) ===
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
    
    % --- CLEANUP PREVIOUS PLOTS (Keep Crosshair) ---
    children = ax.Children;
    if ~isempty(children)
        toDelete = true(size(children));
        for k = 1:numel(children)
            if isprop(children(k), 'Tag') && strcmp(children(k).Tag, 'permCrosshair')
                toDelete(k) = false;
            end
        end
        delete(children(toDelete));
    end
    
    % FIX: Ensure we hold on so plots accumulate
    hold(ax, 'on');
    
    % --- GET UI STATE ---
    showA = h.cb1.Value; mapA_Name = h.dd1.Value; showB = h.cb2.Value; mapB_Name = h.dd2.Value;
    isEdit = h.cbEdit.Value; showLines = h.cbLines.Value; showTCC = h.cbTCC.Value;
    
    % --- CHECKBOXES FOR GEARS ---
    visibleUp = false(1,7); visibleDown = false(1,7);
    for i = 1:7
        cbU = h.gearChecks(sprintf('%d%d', i, i+1)); visibleUp(i) = cbU.Value;
        cbD = h.gearChecks(sprintf('%d%d', i+1, i)); visibleDown(i) = cbD.Value;
    end

    shiftColors = [1 0 0; 0 0 1; 1 0 1; 0 0.6 0.5; 0.5 0 1; 0.4 0 0; 0.6 0.6 0.6];
    legendItems = struct('text', {}, 'color', {}, 'style', {}, 'marker', {});
    
    % --- TCC CONFIGURATION ---
    tccGearColors = [0 0 0; 1 0 0; 0 0 1; 1 0 1; 0 0.7 0.7; 0.5 0 0.8; 0.6 0 0; 0.6 0.6 0.6];
    tccModeStyles = {'--', '-.', '-', '-'};
    tccModeMarkers = {'none', 'none', 'none', '.'};
    tccLineWidths = [1, 1, 1, 1.5];
    tccSuffixes = ["_RO", "_OR", "_RC", "_COC"];

    % --- PLOT SHIFT LINES ---
    for kIdx = 1:2
        if kIdx == 1, k="A"; currentMapName = mapA_Name; show=showA; else, k="B"; currentMapName = mapB_Name; show=showB; end
        if ~show, continue; end

        allNames = string(cellfun(@(m) m.name, appData.allMaps, 'UniformOutput',false)); idx = find(allNames == currentMapName, 1);
        if isempty(idx), continue; end

        if k=="A" && isEdit && isInteractive, map = appData.workingCopy; else, map = appData.allMaps{idx}; end
        % Note: If not interactive (secondary plot), we usually want to see the working copy if it is Map A
        if k=="A" && isEdit && ~isInteractive && ~isempty(appData.workingCopy)
             map = appData.workingCopy; 
        end
        
        pedal = map.pedal;

        for i = 1:7
            c = shiftColors(i, :);
            if showLines
                if visibleUp(i)
                    ls = ifelse(k=="A",'-',':');
                    plot(ax, map.Z_up(:,i), pedal, ls, 'Color', c, 'LineWidth', 1.5, 'PickableParts','none', 'HitTest', 'off');
                    legendItems(end+1) = struct('text', sprintf('Map %s: %d-%d Up', k, i, i+1), 'color', c, 'style', ls, 'marker', 'none');
                end
                if visibleDown(i)
                    ls = ifelse(k=="A",'--','-.');
                    plot(ax, map.Z_down(:,i), pedal, ls, 'Color', c, 'LineWidth', 1.2, 'PickableParts','none', 'HitTest', 'off');
                    legendItems(end+1) = struct('text', sprintf('Map %s: %d-%d Dn', k, i+1, i), 'color', c, 'style', ls, 'marker', 'none');
                end
            end
            
            % Drag Dots only on interactive (main) plot
            if isInteractive
                if k == "A" && isEdit
                    if visibleUp(i), createDragDot(ax, map.Z_up(:,i), pedal, i, true, c); end
                    if visibleDown(i), createDragDot(ax, map.Z_down(:,i), pedal, i, false, c); end
                elseif (k=="A" && showA) || (k=="B" && showB)
                    if visibleUp(i), scatter(ax, map.Z_up(:,i), pedal, 30, c, 'Marker', 'x', 'PickableParts','none'); end
                    if visibleDown(i), scatter(ax, map.Z_down(:,i), pedal, 30, c, 'filled', 'Marker', '^', 'PickableParts','none'); end
                end
            else
                % FIX: Show marks on secondary plot as well (Always show static marks)
                if (k=="A" && showA) || (k=="B" && showB)
                    if visibleUp(i), scatter(ax, map.Z_up(:,i), pedal, 30, c, 'Marker', 'x', 'PickableParts','none', 'HitTest', 'off'); end
                    if visibleDown(i), scatter(ax, map.Z_down(:,i), pedal, 30, c, 'filled', 'Marker', '^', 'PickableParts','none', 'HitTest', 'off'); end
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
                        for g = 1:8
                            if kIdx == 1, if ~h.tccChecksA(num2str(g)).Value, continue; end
                            else, if ~h.tccChecksB(num2str(g)).Value, continue; end; end
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
                                        legendItems(end+1) = struct('text', sprintf('Map %s TCC G%d %s', k, g, modeNames{type}), 'color', tccGearColors(g, :), 'style', tccModeStyles{type}, 'marker', tccModeMarkers{type});
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
