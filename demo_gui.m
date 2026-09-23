function demo_gui
%DEMO_GUI - UAV-GCS Adaptive Secure Comms: operator console (v3, proposal-complete).
%
% One application, four tabs:
%   LIVE OPERATIONS  - run the REAL closed loop (Simulink -> CNN -> DQN -> real
%                      mitigation sim) for any threat x Eb/N0 x UAV speed x severity.
%                      Shows detection (with UNKNOWN-threat handling), the DQN
%                      decision side by side with the rule-based policy, the BER /
%                      RSSI timeline before and after the countermeasure, the
%                      outcome vs the clean channel (survivability regime) and the
%                      goodput trade-off.
%   KPI & RESULTS    - the five proposal KPIs, confusion matrix, accuracy vs SNR,
%                      recovery vs SNR, latency, action distribution and robustness
%                      vs UAV speed, read from the saved result files.
%   SURVIVABILITY MAP- proposal deliverable #7 (Map A / Map B, per threat) with the
%                      last live run marked on the grid.
%   SESSION LOG      - every run of the session, exportable to CSV / MAT.
%
% Speed: any real value 50-120 km/h. Channel Doppler follows fd = v*fc/c and is
% applied to the Simulink channel of EVERY run (2.4 GHz -> ~2.22 Hz per km/h).
%
% Decision latency = CNN path (spectrogram + normalise + resize + forward pass)
% + DQN forward pass, timed with tic/toc around exactly that computation. GUI
% drawing and the demo pauses are NOT inside the timed block, so the number is
% the same quantity reported by run_closed_loop_diagnostic.m.
%
% ARCHITECTURE: no nested functions anywhere in this file (see D24). Static state
% (models, parameters, UI handles, colours) lives in fig.UserData; state that
% changes while a sequence runs (history, video writer, log file, abort flag,
% last run) lives in appdata so a callback can never overwrite it with a stale
% copy of UserData.
%
% Usage: run demo_gui from the project root (same folder as main.m).

close all; clc;

%% ---------- Load trained models and simulation parameters once ----------
tBoot = tic;
fprintf('Loading trained models and parameters...\n');
D = load('data/trained_detector.mat', 'net', 'classes');
Q = load('data/trained_dqn.mat', 'agent');
[featMean, featStd] = loadNormStats();
p0 = loadInitialParams();
fprintf('  models + parameters loaded (%.1f s)\n', toc(tBoot));

env = struct();
env.cnn_net    = D.net;
env.class_list = cellstr(D.classes(:));
env.dqn_agent  = Q.agent;
env.feat_mean  = featMean;
env.feat_std   = featStd;
env.p0         = p0;
env.modelName  = 'UAV_GCS_Threat_Link';
env.fs         = p0.symbol_rate * p0.sps;
env.delay_bits = 20;
env.img_size = 128; env.win = 128; env.novlp = 113; env.nfft = 128;
env.db_lo = -40; env.db_hi = 20; env.temporal_window = 10;
env.threats = {'jamming','reactive_jamming','sweeping_jammer','noise_burst', ...
    'path_loss','spoofing','antenna_fault','benign_interference','none'};
env.snr_levels = p0.EbNo_dB(:)';
if isfield(p0, 'speed_kmh_min')
    env.speed_range = [p0.speed_kmh_min p0.speed_kmh_max];
else
    env.speed_range = [50 120];
end
env.action_names = env.dqn_agent.action_names;
env.baseline = struct('jsr_db',p0.jsr_db,'path_loss_db',p0.path_loss_db, ...
    'fault_atten_db',p0.fault_atten_db,'spoof_sir_db',p0.spoof_sir_db, ...
    'benign_int_db',p0.benign_int_db);
env.sev = buildSeverityTable();
env.surv = loadSurvReference();
env.ber_floor = 0.5 / p0.frame_length;      % "zero errors in a frame" plotting floor

fprintf('Warming up CNN, DQN, and spectrogram()...\n');
warmUp(env);
fprintf('  warm-up done (%.1f s total)\n', toc(tBoot));

%% ---------- Look & feel ----------
c = struct();
c.bg      = [0.055 0.066 0.090];
c.panelBg = [0.105 0.120 0.160];
c.axBg    = [0.072 0.086 0.120];
c.termBg  = [0.030 0.040 0.055];
c.txt     = [0.90 0.92 0.96];
c.mut     = [0.62 0.66 0.74];
c.accent  = [0.30 0.62 0.98];
c.green   = [0.22 0.80 0.48];
c.amber   = [0.97 0.72 0.22];
c.red     = [0.93 0.32 0.32];
c.purp    = [0.68 0.44 0.95];
c.cyan    = [0.30 0.80 0.85];
c.term    = [0.45 0.95 0.55];
c.font    = 'Segoe UI';
c.mono    = 'Consolas';

fig = uifigure('Name', 'UAV-GCS Adaptive Secure Communications - Operator Console', ...
    'Position', [20 20 1680 940], 'Color', c.bg);

root = uigridlayout(fig, [2 1]);
root.RowHeight = {54, '1x'}; root.Padding = [8 8 8 8]; root.RowSpacing = 6;
root.BackgroundColor = c.bg;

%% ---------- Header ----------
hdr = uipanel(root, 'BackgroundColor', c.panelBg, 'BorderType', 'none');
hdr.Layout.Row = 1;
hg = uigridlayout(hdr, [1 4]);
hg.ColumnWidth = {'1x', 470, 30, 270}; hg.Padding = [14 4 14 4]; hg.BackgroundColor = c.panelBg;
place(mkLabel(hg, 'UAV-GCS ADAPTIVE SECURE COMMUNICATIONS', c, 'FontSize', 17, 'FontWeight', 'bold'), 1, 1);
place(mkLabel(hg, 'CNN 9-class detector | DQN 5-action | Rician K=10 dB @ 2.4 GHz', c, ...
    'FontColor', c.mut, 'FontSize', 11, 'HorizontalAlignment', 'right'), 1, 2);
lamp = place(mkLabel(hg, char(9679), c, 'FontSize', 22, 'FontColor', c.mut, 'HorizontalAlignment', 'center'), 1, 3);
lampTxt = place(mkLabel(hg, 'LINK: STANDBY', c, 'FontSize', 14, 'FontWeight', 'bold', 'FontColor', c.mut), 1, 4);

%% ---------- Tabs ----------
tg = uitabgroup(root); tg.Layout.Row = 2;
tabLive = uitab(tg, 'Title', '  LIVE OPERATIONS  ',   'BackgroundColor', c.bg);
tabKpi  = uitab(tg, 'Title', '  KPI & RESULTS  ',     'BackgroundColor', c.bg);
tabSurv = uitab(tg, 'Title', '  SURVIVABILITY MAP  ', 'BackgroundColor', c.bg);
tabLog  = uitab(tg, 'Title', '  SESSION LOG  ',       'BackgroundColor', c.bg);

ui = buildLiveTab(tabLive, env, c);
ui = mergeStructs(ui, buildKpiTab(tabKpi, c));
ui = mergeStructs(ui, buildSurvTab(tabSurv, env, c));
ui = mergeStructs(ui, buildLogTab(tabLog, c));
ui.linkLamp = lamp; ui.linkTxt = lampTxt; ui.tabGroup = tg;

fprintf('  UI built (%.1f s total)\n', toc(tBoot));
fig.UserData = struct('env', env, 'ui', ui, 'colors', c);
setappdata(fig, 'history', {});
setappdata(fig, 'videoWriter', []);
setappdata(fig, 'logFid', -1);
setappdata(fig, 'abortFlag', false);
setappdata(fig, 'lastRun', []);

ui.matrixTbl.CellEditCallback    = @matrixEditCallback;
ui.speedSpin.ValueChangedFcn     = @speedChanged;
ui.thrSlider.ValueChangingFcn    = @thrChanging;
ui.thrSlider.ValueChangedFcn     = @thrChanged;
ui.runBtn.ButtonPushedFcn        = @runSequence;
ui.abortBtn.ButtonPushedFcn      = @abortSequence;
ui.exportBtn.ButtonPushedFcn     = @exportHistory;
ui.clearBtn.ButtonPushedFcn      = @clearHistory;
ui.kpiRefreshBtn.ButtonPushedFcn = @refreshKpi;
ui.survMapDD.ValueChangedFcn     = @survChanged;
ui.survThreatDD.ValueChangedFcn  = @survChanged;
fig.CloseRequestFcn              = @closeApp;

speedChanged(ui.speedSpin, []);
thrChanged(ui.thrSlider, []);
resetRunViews(fig);
drawLinkDiagram(fig, 'idle', '', '', struct());
setProgress(fig, 0);
loadKpiTab(fig);
updateSurvMap(fig);
updateSessionSummary(fig);
fprintf('System ready (%.1f s total).\n\n', toc(tBoot));
appLog(fig, 'SYSTEM INITIALIZED AND STANDBY.');
if isempty(env.surv)
    appLog(fig, 'NOTE: data/survivability_boundary.mat not found - survivability verdicts disabled.');
end

end

%% =====================================================================
%% =========================  BUILD: LIVE TAB  ==========================
%% =====================================================================
function ui = buildLiveTab(tab, env, c)
    g = uigridlayout(tab, [1 3]);
    g.ColumnWidth = {392, '1x', 452}; g.Padding = [4 4 4 4]; g.ColumnSpacing = 8;
    g.BackgroundColor = c.bg;

    %% ---------------- LEFT COLUMN ----------------
    gl = uigridlayout(g, [6 1]); gl.Layout.Column = 1;
    gl.RowHeight = {262, 236, 44, 46, 78, '1x'}; gl.Padding = [0 0 0 0];
    gl.RowSpacing = 6; gl.BackgroundColor = c.bg;

    % ---- 1. Test matrix ----
    p1 = mkPanel(gl, '1 - TEST MATRIX  (threat x Eb/N0 dB)', c); p1.Layout.Row = 1;
    g1 = uigridlayout(p1, [1 1]); g1.Padding = [6 4 6 6]; g1.BackgroundColor = c.panelBg;
    nS = numel(env.snr_levels);
    cnames   = [{'ALL','Threat'}, arrayfun(@(x) sprintf('%g', x), env.snr_levels, 'UniformOutput', false)];
    cformats = [{'logical','char'}, repmat({'logical'}, 1, nS)];
    cedit    = [true false true(1, nS)];
    tdata = cell(numel(env.threats), 2 + nS);
    tdata(:,1) = {false};
    tdata(:,2) = cellfun(@(x) upper(strrep(x,'_',' ')), env.threats(:), 'UniformOutput', false);
    tdata(:,3:end) = {false};
    k4 = find(env.snr_levels == 4, 1); if isempty(k4), k4 = 1; end
    tdata{1, 2 + k4} = true;                      % default: jamming @ 4 dB
    matrixTbl = uitable(g1, 'Data', tdata, 'ColumnName', cnames, 'ColumnFormat', cformats, ...
        'ColumnEditable', cedit, 'ColumnWidth', [{36, 124}, repmat({30}, 1, nS)], 'RowName', [], ...
        'FontSize', 10, 'FontName', c.font, 'BackgroundColor', [c.termBg; c.axBg], ...
        'ForegroundColor', c.txt);

    % ---- 2. Flight & threat settings ----
    p2 = mkPanel(gl, '2 - FLIGHT & THREAT SETTINGS', c); p2.Layout.Row = 2;
    g2 = uigridlayout(p2, [7 2]);
    g2.RowHeight = {26, 18, 26, 20, 34, 24, 24}; g2.ColumnWidth = {150, '1x'};
    g2.Padding = [8 6 8 6]; g2.RowSpacing = 4; g2.BackgroundColor = c.panelBg;

    place(mkLabel(g2, 'UAV speed (km/h)', c), 1, 1);
    speedSpin = uispinner(g2, 'Limits', env.speed_range, 'Step', 0.5, 'Value', 72, ...
        'ValueDisplayFormat', '%.1f', 'RoundFractionalValues', 'off', ...
        'BackgroundColor', c.termBg, 'FontColor', c.txt, 'FontName', c.font, 'FontSize', 12);
    place(speedSpin, 1, 2);
    speedInfo = place(mkLabel(g2, '', c, 'FontColor', c.cyan, 'FontSize', 10, 'FontName', c.mono), 2, [1 2]);

    place(mkLabel(g2, 'Threat severity', c), 3, 1);
    sevDD = uidropdown(g2, 'Items', {'Nominal (baseline)','Level 1 (lowest)','Level 2','Level 3','Level 4','Level 5 (highest)'}, ...
        'ItemsData', [0 1 2 3 4 5], 'Value', 0, 'BackgroundColor', c.termBg, 'FontColor', c.txt, ...
        'FontName', c.font);
    place(sevDD, 3, 2);

    thrLbl = place(mkLabel(g2, '', c, 'FontSize', 11), 4, [1 2]);
    thrSlider = uislider(g2, 'Limits', [0 100], 'Value', 50, 'MajorTicks', 0:25:100, ...
        'MinorTicks', [], 'FontColor', c.mut);
    place(thrSlider, 5, [1 2]);

    ruleChk = uicheckbox(g2, 'Text', 'Compare with rule-based policy (extra real sim)', ...
        'Value', true, 'FontColor', c.txt, 'FontName', c.font);
    place(ruleChk, 6, [1 2]);
    recordChk = uicheckbox(g2, 'Text', 'Capture session video (.mp4)', 'Value', false, ...
        'FontColor', c.red, 'FontWeight', 'bold', 'FontName', c.font);
    place(recordChk, 7, [1 2]);

    % ---- Run / abort ----
    gb = uigridlayout(gl, [1 2]); gb.Layout.Row = 3; gb.ColumnWidth = {'1x', 110};
    gb.Padding = [0 0 0 0]; gb.ColumnSpacing = 6; gb.BackgroundColor = c.bg;
    runBtn = uibutton(gb, 'Text', 'RUN SEQUENCE', 'FontSize', 15, 'FontWeight', 'bold', ...
        'BackgroundColor', c.green, 'FontColor', [0.03 0.10 0.06], 'FontName', c.font);
    place(runBtn, 1, 1);
    abortBtn = uibutton(gb, 'Text', 'ABORT', 'FontSize', 14, 'FontWeight', 'bold', ...
        'BackgroundColor', c.red, 'FontColor', 'white', 'Enable', 'off', 'FontName', c.font);
    place(abortBtn, 1, 2);

    % ---- Progress + timer ----
    p4 = uipanel(gl, 'BackgroundColor', c.panelBg, 'BorderType', 'none'); p4.Layout.Row = 4;
    g4 = uigridlayout(p4, [2 2]); g4.RowHeight = {20, '1x'}; g4.ColumnWidth = {'1x', 130};
    g4.Padding = [8 4 8 6]; g4.RowSpacing = 2; g4.BackgroundColor = c.panelBg;
    progLbl = place(mkLabel(g4, 'PROGRESS  0 / 0', c, 'FontSize', 11, 'FontWeight', 'bold', 'FontColor', c.accent), 1, 1);
    timeLbl = place(mkLabel(g4, '00:00.00', c, 'FontSize', 15, 'FontWeight', 'bold', 'FontColor', c.accent, ...
        'FontName', c.mono, 'HorizontalAlignment', 'right'), 1, 2);
    progAx = place(uiaxes(g4), 2, [1 2]);
    styleAx(progAx, c); progAx.Color = c.termBg;
    progAx.XTick = []; progAx.YTick = []; progAx.XColor = 'none'; progAx.YColor = 'none';
    progAx.XLim = [0 1]; progAx.YLim = [0 1];

    % ---- Queue ----
    p5 = mkPanel(gl, 'UPCOMING QUEUE', c); p5.Layout.Row = 5;
    g5 = uigridlayout(p5, [1 1]); g5.Padding = [6 2 6 6]; g5.BackgroundColor = c.panelBg;
    queueList = uilistbox(g5, 'Items', {'(empty)'}, 'FontSize', 10, 'FontName', c.mono, ...
        'BackgroundColor', c.termBg, 'FontColor', c.mut);

    % ---- Terminal ----
    p6 = mkPanel(gl, 'EVENT TERMINAL', c); p6.Layout.Row = 6;
    g6 = uigridlayout(p6, [1 1]); g6.Padding = [6 2 6 6]; g6.BackgroundColor = c.panelBg;
    termArea = uitextarea(g6, 'Value', {''}, 'Editable', 'off', 'FontName', c.mono, 'FontSize', 10, ...
        'BackgroundColor', c.termBg, 'FontColor', c.term);

    %% ---------------- CENTER COLUMN ----------------
    gc = uigridlayout(g, [4 1]); gc.Layout.Column = 2;
    gc.RowHeight = {168, 44, 252, '1x'}; gc.Padding = [0 0 0 0]; gc.RowSpacing = 6;
    gc.BackgroundColor = c.bg;

    pLink = mkPanel(gc, 'UAV <-> GCS LINK', c); pLink.Layout.Row = 1;
    gLink = uigridlayout(pLink, [1 1]); gLink.Padding = [4 2 4 4]; gLink.BackgroundColor = c.panelBg;
    linkAx = uiaxes(gLink); styleAx(linkAx, c); linkAx.Color = c.panelBg;
    linkAx.XTick = []; linkAx.YTick = []; linkAx.XColor = 'none'; linkAx.YColor = 'none';
    linkAx.XLim = [0 16]; linkAx.YLim = [0 3];

    verdictLbl = uilabel(gc, 'Text', 'AWAITING SEQUENCE', 'FontSize', 16, 'FontWeight', 'bold', ...
        'FontName', c.font, 'FontColor', c.mut, 'BackgroundColor', c.panelBg, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center');
    verdictLbl.Layout.Row = 2;

    pSig = mkPanel(gc, 'RECEIVED SIGNAL', c); pSig.Layout.Row = 3;
    gSig = uigridlayout(pSig, [1 2]); gSig.Padding = [6 2 6 6]; gSig.ColumnSpacing = 8;
    gSig.BackgroundColor = c.panelBg;
    specAx = place(uiaxes(gSig), 1, 1); styleAx(specAx, c);
    iqAx   = place(uiaxes(gSig), 1, 2); styleAx(iqAx, c);

    pTl = mkPanel(gc, 'LINK METRICS TIMELINE  (before / after countermeasure)', c); pTl.Layout.Row = 4;
    gTl = uigridlayout(pTl, [2 1]); gTl.Padding = [6 2 6 6]; gTl.RowSpacing = 6;
    gTl.BackgroundColor = c.panelBg;
    berAx  = place(uiaxes(gTl), 1, 1); styleAx(berAx, c);
    rssiAx = place(uiaxes(gTl), 2, 1); styleAx(rssiAx, c);

    %% ---------------- RIGHT COLUMN ----------------
    gr = uigridlayout(g, [3 1]); gr.Layout.Column = 3;
    gr.RowHeight = {320, 250, '1x'}; gr.Padding = [0 0 0 0]; gr.RowSpacing = 6;
    gr.BackgroundColor = c.bg;

    % ---- Detection ----
    pDet = mkPanel(gr, '3 - DETECTION  (CNN, sliding window)', c); pDet.Layout.Row = 1;
    gDet = uigridlayout(pDet, [4 2]); gDet.RowHeight = {18, 92, 34, '1x'};
    gDet.Padding = [8 4 8 6]; gDet.RowSpacing = 3; gDet.BackgroundColor = c.panelBg;
    place(mkLabel(gDet, 'CNN CONFIDENCE (%)', c, 'FontSize', 10, 'FontColor', c.mut, 'HorizontalAlignment', 'center'), 1, 1);
    place(mkLabel(gDet, 'DECISION LATENCY (ms)', c, 'FontSize', 10, 'FontColor', c.mut, 'HorizontalAlignment', 'center'), 1, 2);
    confGauge = place(uigauge(gDet, 'semicircular', 'Limits', [0 100], 'FontColor', c.txt, 'BackgroundColor', c.panelBg), 2, 1);
    confGauge.ScaleColors = {[0.93 0.32 0.32], [0.97 0.72 0.22], [0.22 0.80 0.48]};
    confGauge.ScaleColorLimits = [0 60; 60 90; 90 100];
    latGauge = place(uigauge(gDet, 'semicircular', 'Limits', [0 30], 'FontColor', c.txt, 'BackgroundColor', c.panelBg), 2, 2);
    latGauge.ScaleColors = {[0.22 0.80 0.48], [0.97 0.72 0.22], [0.93 0.32 0.32]};
    latGauge.ScaleColorLimits = [0 8; 8 15; 15 30];
    detLbl = place(mkLabel(gDet, '-', c, 'FontSize', 15, 'FontWeight', 'bold', 'HorizontalAlignment', 'center'), 3, [1 2]);
    probAx = place(uiaxes(gDet), 4, [1 2]); styleAx(probAx, c);

    % ---- Decision ----
    pDec = mkPanel(gr, '4 - DECISION  (DQN vs rule-based)', c); pDec.Layout.Row = 2;
    gDec = uigridlayout(pDec, [2 1]); gDec.RowHeight = {'1x', 50};
    gDec.Padding = [8 4 8 6]; gDec.RowSpacing = 3; gDec.BackgroundColor = c.panelBg;
    qAx = place(uiaxes(gDec), 1, 1); styleAx(qAx, c);
    decLbl = place(mkLabel(gDec, {'-'}, c, 'FontSize', 12, 'FontName', c.mono, 'VerticalAlignment', 'top'), 2, 1);

    % ---- Outcome ----
    pOut = mkPanel(gr, '5 - OUTCOME  (mean BER over all valid frames)', c); pOut.Layout.Row = 3;
    gOut = uigridlayout(pOut, [2 1]); gOut.RowHeight = {'1x', 84};
    gOut.Padding = [8 4 8 6]; gOut.RowSpacing = 3; gOut.BackgroundColor = c.panelBg;
    outAx = place(uiaxes(gOut), 1, 1); styleAx(outAx, c);
    outLbl = place(mkLabel(gOut, {'-'}, c, 'FontSize', 10, 'FontName', c.mono, 'VerticalAlignment', 'top'), 2, 1);

    ui = struct('matrixTbl',matrixTbl,'speedSpin',speedSpin,'speedInfo',speedInfo,'sevDD',sevDD, ...
        'thrLbl',thrLbl,'thrSlider',thrSlider,'ruleChk',ruleChk,'recordChk',recordChk, ...
        'runBtn',runBtn,'abortBtn',abortBtn,'progLbl',progLbl,'timeLbl',timeLbl,'progAx',progAx, ...
        'queueList',queueList,'termArea',termArea,'linkAx',linkAx,'verdictLbl',verdictLbl, ...
        'specAx',specAx,'iqAx',iqAx,'berAx',berAx,'rssiAx',rssiAx,'confGauge',confGauge, ...
        'latGauge',latGauge,'detLbl',detLbl,'probAx',probAx,'qAx',qAx,'decLbl',decLbl, ...
        'outAx',outAx,'outLbl',outLbl);
end

%% =====================================================================
%% =========================  BUILD: KPI TAB  ===========================
%% =====================================================================
function ui = buildKpiTab(tab, c)
    g = uigridlayout(tab, [3 1]); g.RowHeight = {112, '1x', '1x'}; g.Padding = [4 4 4 4];
    g.RowSpacing = 8; g.BackgroundColor = c.bg;

    top = uigridlayout(g, [1 7]); top.Layout.Row = 1; top.ColumnWidth = {'1x','1x','1x','1x','1x','1x',110};
    top.Padding = [0 0 0 0]; top.ColumnSpacing = 8; top.BackgroundColor = c.bg;
    titles = {'DETECTION  (KPI #1)','BER RECOVERY  (KPI #2)','DECISION LATENCY  (KPI #3)', ...
              'FALSE ALARMS  (KPI #4)','END-TO-END  (KPI #5)','SPEED ROBUSTNESS'};
    kpiVal = gobjects(1, 6); kpiSub = gobjects(1, 6);
    for k = 1:6
        card = uipanel(top, 'BackgroundColor', c.panelBg, 'BorderType', 'line');
        card.Layout.Row = 1; card.Layout.Column = k;
        cg = uigridlayout(card, [3 1]); cg.RowHeight = {20, '1x', 30}; cg.Padding = [8 4 8 4];
        cg.RowSpacing = 0; cg.BackgroundColor = c.panelBg;
        place(mkLabel(cg, titles{k}, c, 'FontSize', 10, 'FontWeight', 'bold', 'FontColor', c.mut, 'HorizontalAlignment', 'center'), 1, 1);
        kpiVal(k) = place(mkLabel(cg, 'N/A', c, 'FontSize', 26, 'FontWeight', 'bold', 'HorizontalAlignment', 'center'), 2, 1);
        kpiSub(k) = place(mkLabel(cg, '', c, 'FontSize', 9, 'FontColor', c.mut, 'HorizontalAlignment', 'center', 'WordWrap', 'on'), 3, 1);
    end
    kpiRefreshBtn = uibutton(top, 'Text', 'REFRESH', 'FontWeight', 'bold', 'FontName', c.font, ...
        'BackgroundColor', c.accent, 'FontColor', [0.03 0.06 0.12]);
    place(kpiRefreshBtn, 1, 7);

    mid = uigridlayout(g, [1 3]); mid.Layout.Row = 2; mid.Padding = [0 0 0 0]; mid.ColumnSpacing = 8;
    mid.BackgroundColor = c.bg;
    kCm  = place(uiaxes(mid), 1, 1); styleAx(kCm, c);
    kAcc = place(uiaxes(mid), 1, 2); styleAx(kAcc, c);
    kRec = place(uiaxes(mid), 1, 3); styleAx(kRec, c);

    bot = uigridlayout(g, [1 3]); bot.Layout.Row = 3; bot.Padding = [0 0 0 0]; bot.ColumnSpacing = 8;
    bot.BackgroundColor = c.bg;
    kLat = place(uiaxes(bot), 1, 1); styleAx(kLat, c);
    kAct = place(uiaxes(bot), 1, 2); styleAx(kAct, c);
    kSpd = place(uiaxes(bot), 1, 3); styleAx(kSpd, c);

    ui = struct('kpiVal',kpiVal,'kpiSub',kpiSub,'kpiRefreshBtn',kpiRefreshBtn, ...
        'kCm',kCm,'kAcc',kAcc,'kRec',kRec,'kLat',kLat,'kAct',kAct,'kSpd',kSpd);
end

%% =====================================================================
%% ====================  BUILD: SURVIVABILITY TAB  ======================
%% =====================================================================
function ui = buildSurvTab(tab, env, c)
    g = uigridlayout(tab, [1 2]); g.ColumnWidth = {330, '1x'}; g.Padding = [4 4 4 4];
    g.ColumnSpacing = 8; g.BackgroundColor = c.bg;

    pl = mkPanel(g, 'MAP CONTROLS', c); pl.Layout.Column = 1;
    gl = uigridlayout(pl, [8 1]); gl.RowHeight = {20, 28, 20, 28, 22, 22, 22, '1x'};
    gl.Padding = [10 6 10 10]; gl.RowSpacing = 4; gl.BackgroundColor = c.panelBg;
    place(mkLabel(gl, 'Map', c, 'FontColor', c.mut), 1, 1);
    survMapDD = uidropdown(gl, 'Items', {'Map A - threat neutralization','Map B - link survivability'}, ...
        'ItemsData', {'A','B'}, 'Value', 'A', 'BackgroundColor', c.termBg, 'FontColor', c.txt, 'FontName', c.font);
    place(survMapDD, 2, 1);
    place(mkLabel(gl, 'Threat', c, 'FontColor', c.mut), 3, 1);
    if ~isempty(env.surv)
        tnames = {env.surv.grid_data_A.threat};
    else
        tnames = {'(no data)'};
    end
    survThreatDD = uidropdown(gl, 'Items', tnames, 'BackgroundColor', c.termBg, 'FontColor', c.txt, 'FontName', c.font);
    place(survThreatDD, 4, 1);
    place(mkLabel(gl, [char(9632) '  RECOVERABLE  (BER <= 2x clean)'], c, 'FontColor', c.green, 'FontSize', 11), 5, 1);
    place(mkLabel(gl, [char(9632) '  MARGINAL  (<= 5x clean)'], c, 'FontColor', c.amber, 'FontSize', 11), 6, 1);
    place(mkLabel(gl, [char(9632) '  NON-RECOVERABLE  (> 5x clean)'], c, 'FontColor', c.red, 'FontSize', 11), 7, 1);
    survSummary = uitextarea(gl, 'Value', {''}, 'Editable', 'off', 'FontName', c.mono, 'FontSize', 10, ...
        'BackgroundColor', c.termBg, 'FontColor', c.txt);
    place(survSummary, 8, 1);

    pr = mkPanel(g, 'SURVIVABILITY BOUNDARY  (rows = severity level, columns = Eb/N0 dB, number = BER / clean BER)', c);
    pr.Layout.Column = 2;
    gr = uigridlayout(pr, [1 1]); gr.Padding = [8 4 8 8]; gr.BackgroundColor = c.panelBg;
    survAx = uiaxes(gr); styleAx(survAx, c);

    ui = struct('survMapDD',survMapDD,'survThreatDD',survThreatDD,'survSummary',survSummary,'survAx',survAx);
end

%% =====================================================================
%% =======================  BUILD: LOG TAB  =============================
%% =====================================================================
function ui = buildLogTab(tab, c)
    g = uigridlayout(tab, [2 1]); g.RowHeight = {'1x', 64}; g.Padding = [4 4 4 4]; g.RowSpacing = 8;
    g.BackgroundColor = c.bg;
    hdrNames = {'#','Threat','Eb/N0','Speed','Severity','Detected','Conf','DQN action','Rule action', ...
                'Rec DQN','Rec Rule','Verdict','Lat (ms)'};
    histTbl = uitable(g, 'Data', cell(0, numel(hdrNames)), 'ColumnName', hdrNames, ...
        'ColumnWidth', {40, 150, 60, 80, 130, 150, 60, 130, 130, 70, 70, 210, 70}, 'RowName', [], ...
        'FontSize', 11, 'FontName', c.font, 'BackgroundColor', [c.termBg; c.axBg], 'ForegroundColor', c.txt);
    histTbl.Layout.Row = 1;

    bg = uigridlayout(g, [1 3]); bg.Layout.Row = 2; bg.ColumnWidth = {'1x', 230, 150};
    bg.Padding = [0 0 0 0]; bg.ColumnSpacing = 8; bg.BackgroundColor = c.panelBg;
    sessionLbl = place(mkLabel(bg, {'No runs yet.'}, c, 'FontSize', 12, 'FontName', c.mono), 1, 1);
    exportBtn = uibutton(bg, 'Text', 'EXPORT HISTORY (CSV + MAT)', 'FontWeight', 'bold', 'FontName', c.font, ...
        'BackgroundColor', c.accent, 'FontColor', [0.03 0.06 0.12]);
    place(exportBtn, 1, 2);
    clearBtn = uibutton(bg, 'Text', 'CLEAR HISTORY', 'FontWeight', 'bold', 'FontName', c.font, ...
        'BackgroundColor', [0.30 0.34 0.42], 'FontColor', 'white');
    place(clearBtn, 1, 3);

    ui = struct('histTbl',histTbl,'sessionLbl',sessionLbl,'exportBtn',exportBtn,'clearBtn',clearBtn);
end

%% =====================================================================
%% ==========================  SMALL BUILDERS  ==========================
%% =====================================================================
function comp = place(comp, row, col)
    comp.Layout.Row = row; comp.Layout.Column = col;
end

function pnl = mkPanel(parent, ttl, c)
    pnl = uipanel(parent, 'Title', ttl, 'BackgroundColor', c.panelBg, 'ForegroundColor', c.accent, ...
        'FontWeight', 'bold', 'FontSize', 11, 'FontName', c.font, 'BorderType', 'line');
end

function lbl = mkLabel(parent, txt, c, varargin)
    lbl = uilabel(parent, 'Text', txt, 'FontColor', c.txt, 'FontName', c.font, 'FontSize', 11);
    for k = 1:2:numel(varargin)
        lbl.(varargin{k}) = varargin{k+1};
    end
end

function styleAx(ax, c)
    ax.Color = c.axBg; ax.XColor = c.mut; ax.YColor = c.mut;
    ax.GridColor = [0.55 0.60 0.70]; ax.GridAlpha = 0.25;
    ax.FontName = c.font; ax.FontSize = 10; ax.Box = 'off';
    try, ax.BackgroundColor = c.panelBg; catch, end %#ok<CTCH>
    try, ax.Toolbar.Visible = 'off'; catch, end %#ok<CTCH>
    try, disableDefaultInteractivity(ax); catch, end %#ok<CTCH>
end

function setTitle(ax, ttl, c)
    title(ax, ttl, 'Color', c.txt, 'FontSize', 11, 'FontWeight', 'bold', 'FontName', c.font);
end

function s = mergeStructs(a, b)
    s = a; f = fieldnames(b);
    for k = 1:numel(f), s.(f{k}) = b.(f{k}); end
end

function [mu, sd] = loadNormStats()
    % splits.mat is >1 GB; only two small vectors are needed. They are cached
    % in a tiny file and re-extracted only when splits.mat is newer.
    src = 'data/splits.mat'; cache = 'data/gui_norm_stats.mat';
    fresh = isfile(cache) && dir(cache).datenum >= dir(src).datenum;
    if ~fresh
        fprintf('  one-time extraction of normalisation stats from splits.mat (slow, next launches skip this)...\n');
        S = load(src, 'splits');
        feat_mean = S.splits.norm.feat_mean; feat_std = S.splits.norm.feat_std; %#ok<NASGU>
        save(cache, 'feat_mean', 'feat_std');
        clear S;
    end
    N = load(cache, 'feat_mean', 'feat_std');
    mu = N.feat_mean; sd = N.feat_std;
end

function p = loadInitialParams()
    % init_params.m is a SCRIPT that injects "params" into its caller's workspace.
    % It is called from this plain function (a file with no nested functions), so
    % the workspace stays dynamic and the injection works exactly as elsewhere.
    init_params;
    p = load('params.mat').params;
end

function sev = buildSeverityTable()
    % Same severity axes as run_dataset_sweep.m (dataset) / explore_countermeasures.m.
    sev = struct();
    sev.jamming             = struct('param','jsr_db',        'levels',[0 4 8 12 16]);
    sev.reactive_jamming    = struct('param','jsr_db',        'levels',[0 4 8 12 16]);
    sev.sweeping_jammer     = struct('param','jsr_db',        'levels',[0 4 8 12 16]);
    sev.noise_burst         = struct('param','jsr_db',        'levels',[0 4 8 12 16]);
    sev.path_loss           = struct('param','path_loss_db',  'levels',[4 8 12 16 20]);
    sev.spoofing            = struct('param','spoof_sir_db',  'levels',[-4 -1 2 5 8]);
    sev.antenna_fault       = struct('param','fault_duty',    'levels',[0.1 0.2 0.3 0.4 0.5]);
    sev.benign_interference = struct('param','benign_int_db', 'levels',[-10 -8 -6 -4 -2]);
    sev.none                = struct('param','',              'levels',[]);
end

function surv = loadSurvReference()
    surv = [];
    f = 'data/survivability_boundary.mat';
    if isfile(f)
        try
            L = load(f);
            if isfield(L,'grid_data_A') && isfield(L,'grid_data_B') && isfield(L,'ber_clean')
                surv = L;
            end
        catch
            surv = [];
        end
    end
end

function warmUp(env)
    dummy_iq = complex(randn(2064,1), randn(2064,1));
    for w = 1:3
        Sxx_dummy = spectrogram(dummy_iq, hann(env.win), env.novlp, env.nfft, env.fs, 'centered'); %#ok<NASGU>
    end
    dspec = dlarray(single(rand(env.img_size,env.img_size,1,1)), 'SSCB');
    dfeat = dlarray(single(rand(1,7))', 'CB');
    dstate = dlarray(single(rand(env.dqn_agent.numStates,1)), 'CB');
    if canUseGPU, dspec = gpuArray(dspec); dfeat = gpuArray(dfeat); dstate = gpuArray(dstate); end
    for w = 1:10
        predict(env.cnn_net, dspec, dfeat);
        predict(env.dqn_agent.qNetwork, dstate);
    end
    if canUseGPU, wait(gpuDevice); end
end

function restoreParams(p0)
    params = p0; %#ok<NASGU>
    save('params.mat', 'params');
end

function s = niceName(x)
    s = upper(strrep(x, '_', ' '));
end

%% =====================================================================
%% ===========================  CALLBACKS  ==============================
%% =====================================================================
function matrixEditCallback(src, event)
    r = event.Indices(1); col = event.Indices(2);
    d = src.Data;
    if col == 1
        for k = 3:size(d, 2), d{r, k} = event.NewData; end
    elseif col >= 3
        d{r, 1} = all(cell2mat(d(r, 3:end)));      % keep ALL in sync with the row
    end
    src.Data = d;
end

function speedChanged(src, ~)
    fig = ancestor(src, 'figure'); env = fig.UserData.env; ui = fig.UserData.ui;
    v = src.Value;
    fd = (v/3.6) * env.p0.carrier_freq / env.p0.c_light;
    ui.speedInfo.Text = sprintf('= %.2f m/s   |   max Doppler fd = %.1f Hz', v/3.6, fd);
end

function thrChanging(src, evt)
    fig = ancestor(src, 'figure'); ui = fig.UserData.ui;
    ui.thrLbl.Text = sprintf('UNKNOWN threat if CNN confidence < %.0f %%  (raise to test)', evt.Value);
end

function thrChanged(src, ~)
    fig = ancestor(src, 'figure'); ui = fig.UserData.ui;
    ui.thrLbl.Text = sprintf('UNKNOWN threat if CNN confidence < %.0f %%  (raise to test)', src.Value);
end

function abortSequence(btn, ~)
    fig = ancestor(btn, 'figure');
    setappdata(fig, 'abortFlag', true);
    btn.Text = 'ABORTING...'; btn.Enable = 'off';
    appLog(fig, 'ABORT SIGNAL SENT - waiting for the current stage to finish...');
end

function refreshKpi(btn, ~)
    fig = ancestor(btn, 'figure');
    loadKpiTab(fig);
    updateSurvMap(fig);
    appLog(fig, 'KPI / survivability results reloaded from disk.');
end

function survChanged(src, ~)
    fig = ancestor(src, 'figure');
    updateSurvMap(fig);
end

function closeApp(fig, ~)
    try
        vw = getappdata(fig, 'videoWriter');
        if ~isempty(vw), close(vw); end
        fid = getappdata(fig, 'logFid');
        if ~isempty(fid) && fid > 0, fclose(fid); end
    catch
    end
    delete(fig);
end

function checkAbort(fig)
    if getappdata(fig, 'abortFlag')
        error('demoGui:aborted', 'Sequence aborted by operator.');
    end
end

function clearHistory(btn, ~)
    fig = ancestor(btn, 'figure'); ui = fig.UserData.ui;
    setappdata(fig, 'history', {});
    ui.histTbl.Data = cell(0, size(ui.histTbl.Data, 2));
    updateSessionSummary(fig);
    appLog(fig, 'Session history cleared.');
end

function exportHistory(btn, ~)
    fig = ancestor(btn, 'figure');
    H = getappdata(fig, 'history');
    if isempty(H)
        appLog(fig, 'Export failed: no run history available.');
        return;
    end
    if ~exist('GUI_Results', 'dir'), mkdir('GUI_Results'); end
    baseName = sprintf('GUI_Results/demo_history_%s', datestr(now, 'yyyymmdd_HHMMSS'));
    T = struct2table([H{:}]);
    writetable(T, [baseName '.csv']);
    history = H; %#ok<NASGU>
    save([baseName '.mat'], 'history');
    appLog(fig, sprintf('Exported %d runs to %s (.csv / .mat). The event log is saved per sequence in GUI_Results/demo_session_*.log', ...
        numel(H), baseName));
end

%% =====================================================================
%% =========================  RUN A SEQUENCE  ===========================
%% =====================================================================
function runSequence(btn, ~)
    fig = ancestor(btn, 'figure');
    env = fig.UserData.env; ui = fig.UserData.ui; c = fig.UserData.colors;

    % ---- read the test matrix into an ordered run queue ----
    tbl = ui.matrixTbl.Data;
    queue = {};
    for r = 1:size(tbl, 1)
        for k = 1:numel(env.snr_levels)
            if tbl{r, 2 + k}
                queue(end+1, :) = {env.threats{r}, env.snr_levels(k)}; %#ok<AGROW>
            end
        end
    end
    nRuns = size(queue, 1);
    if nRuns == 0
        appLog(fig, 'ERROR: the test matrix is empty - tick at least one box.');
        return;
    end
    sevLevel = ui.sevDD.Value;
    sevName = ui.sevDD.Items{sevLevel + 1};

    ui.runBtn.Enable = 'off'; ui.abortBtn.Enable = 'on'; ui.abortBtn.Text = 'ABORT';
    setappdata(fig, 'abortFlag', false);
    qItems = cell(1, nRuns);
    for q = 1:nRuns
        qItems{q} = sprintf('%2d. %-20s @ %g dB', q, niceName(queue{q,1}), queue{q,2});
    end
    ui.queueList.Items = qItems; ui.queueList.FontColor = c.txt;

    if ~exist('GUI_Results', 'dir'), mkdir('GUI_Results'); end
    stamp = datestr(now, 'yyyymmdd_HHMMSS');
    setappdata(fig, 'logFid', fopen(sprintf('GUI_Results/demo_session_%s.log', stamp), 'w'));

    appLog(fig, '--- NEW SEQUENCE ---');
    appLog(fig, sprintf('%d run(s) queued | speed %.1f km/h | severity: %s', nRuns, ui.speedSpin.Value, sevName));
    setProgress(fig, 0); ui.progLbl.Text = sprintf('PROGRESS  0 / %d', nRuns);

    if ui.recordChk.Value
        vname = sprintf('GUI_Results/demo_session_%s.mp4', stamp);
        vw = VideoWriter(vname, 'MPEG-4'); vw.FrameRate = 1; open(vw);  % ~4 captures/run now (one per state), so 1 fps keeps playback slideshow-paced rather than a blur
        setappdata(fig, 'videoWriter', vw);
        appLog(fig, ['Recording video to ' vname]);
    end

    tSeq = tic;
    for i = 1:nRuns
        if getappdata(fig, 'abortFlag')
            appLog(fig, 'SEQUENCE ABORTED BY OPERATOR.'); break;
        end
        appLog(fig, sprintf('RUN %d/%d: %s @ %g dB', i, nRuns, niceName(queue{i,1}), queue{i,2}));
        try
            runOneRun(fig, queue{i,1}, queue{i,2}, sevLevel, tSeq);
        catch ME
            if strcmp(ME.identifier, 'demoGui:aborted')
                appLog(fig, 'SEQUENCE ABORTED BY OPERATOR.');
            else
                appLog(fig, ['ERROR: ' ME.message]);
            end
            break;
        end
        if i < nRuns, ui.queueList.Items = qItems(i+1:end); else, ui.queueList.Items = {'(empty)'}; end
        setProgress(fig, i / nRuns);
        ui.progLbl.Text = sprintf('PROGRESS  %d / %d', i, nRuns);
    end

    vw = getappdata(fig, 'videoWriter');
    if ~isempty(vw)
        close(vw); setappdata(fig, 'videoWriter', []);
        appLog(fig, 'Video recording saved.');
    end
    appLog(fig, 'SEQUENCE FINISHED - back to standby.');
    fid = getappdata(fig, 'logFid');
    if ~isempty(fid) && fid > 0, fclose(fid); end
    setappdata(fig, 'logFid', -1);
    setappdata(fig, 'abortFlag', false);

    ui.queueList.Items = {'(empty)'}; ui.queueList.FontColor = c.mut;
    ui.runBtn.Enable = 'on'; ui.abortBtn.Enable = 'off'; ui.abortBtn.Text = 'ABORT';
    setLinkHeader(fig, 'STANDBY', c.mut);
end

%% =====================================================================
%% ============================  ONE RUN  ===============================
%% =====================================================================
function runOneRun(fig, threat, ebno, sevLevel, tSeq)
    data = fig.UserData; env = data.env; ui = data.ui; c = data.colors;
    guard = onCleanup(@() restoreParams(env.p0)); %#ok<NASGU>   % params.mat is ALWAYS restored

    %% ---- settings for this run ----
    v_kmh   = ui.speedSpin.Value;
    thr_pct = ui.thrSlider.Value;
    doRule  = ui.ruleChk.Value;
    fd_hz   = (v_kmh/3.6) * env.p0.carrier_freq / env.p0.c_light;
    info0   = struct('v_kmh', v_kmh, 'fd', fd_hz);

    p = env.p0;
    p.jsr_db = env.baseline.jsr_db; p.path_loss_db = env.baseline.path_loss_db;
    p.fault_atten_db = env.baseline.fault_atten_db; p.spoof_sir_db = env.baseline.spoof_sir_db;
    p.benign_int_db = env.baseline.benign_int_db;
    p.active_threat = threat;
    sevTxt = 'nominal';
    sv = env.sev.(threat);
    if sevLevel > 0 && ~isempty(sv.param)
        p.(sv.param) = sv.levels(sevLevel);
        sevTxt = sprintf('L%d (%s=%g)', sevLevel, sv.param, sv.levels(sevLevel));
    end
    p.v_kmh = v_kmh; p.v = v_kmh/3.6; p.fd_max = fd_hz;            % speed -> channel Doppler
    snr_dB = ebno + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
    truth_idx = find(strcmp(env.class_list, threat), 1);

    refBer = NaN;                                                  % clean-channel BER at this Eb/N0
    if ~isempty(env.surv)
        kref = find(env.surv.SNR_points == ebno, 1);
        if ~isempty(kref), refBer = env.surv.ber_clean(kref); end
    end

    resetRunViews(fig);
    drawLinkDiagram(fig, 'scenario', threat, '', info0);
    appLog(fig, sprintf('Scenario: %s | severity %s | %.1f km/h (fd %.0f Hz) | Eb/N0 %g dB', ...
        niceName(threat), sevTxt, v_kmh, fd_hz, ebno));

    %% ---- 1. real Simulink run of the attacked link ----
    appLog(fig, 'Building Simulink threat model and simulating the link...');
    params = p; save('params.mat', 'params'); %#ok<NASGU>
    build_threat_model;
    set_param([env.modelName '/AWGN'], 'SNR', num2str(snr_dB), 'SignalPower', num2str(1/p.sps));
    out = sim(env.modelName);
    updateTimer(fig, tSeq); checkAbort(fig);

    [iq_frames, ber_f, rssi_f, plr_f, nf] = extract_closed_loop_frames(out, p, env.delay_bits);
    i_last = find(~isnan(ber_f), 1, 'last'); if isempty(i_last), i_last = nf; end
    w0 = max(1, i_last - env.temporal_window + 1);
    var_rssi_10 = var(rssi_f(w0:i_last), 0);
    burst_ratio = mean(plr_f(w0:i_last), 'omitnan');
    if i_last > 1 && ~isnan(ber_f(i_last)) && ~isnan(ber_f(i_last-1))
        dber_dt = (ber_f(i_last) - ber_f(i_last-1)) / p.frame_duration;
    else
        dber_dt = 0;
    end
    iq_before = iq_frames{i_last};
    ber_before_mean = mean(ber_f, 'omitnan');
    appLog(fig, sprintf('Channel: BER %.2e (mean of %d frames) | RSSI %.2f dB | burst ratio %.2f', ...
        ber_before_mean, nf, rssi_f(i_last), burst_ratio));

    % Pre-mitigation views (drawn BEFORE the timed decision block)
    nPts = min(400, numel(iq_before));
    Lq = max(0.6, min(6, 1.15 * max(abs([real(iq_before(1:nPts)); imag(iq_before(1:nPts))]))));
    drawIQ(fig, iq_before, c.red, 'IQ constellation - before', Lq);
    tl = struct('ber_b', ber_f, 'rssi_b', rssi_f, 'ber_d', [], 'rssi_d', [], ...
        'ber_r', [], 'rssi_r', [], 'ref', refBer);
    drawTimeline(fig, tl);
    smartPause(fig, 0.5, tSeq); checkAbort(fig);

    %% ---- 2. TIMED decision block: CNN path + DQN (no GUI work inside) ----
    t1 = tic;
    [Sxx, Fq, Tq] = spectrogram(iq_before, hann(env.win), env.novlp, env.nfft, env.fs, 'centered');
    Pw_db = 20*log10(abs(Sxx) + eps);
    Pw_n = min(max((Pw_db - env.db_lo) / (env.db_hi - env.db_lo), 0), 1);
    spec_img = imresize(Pw_n, [env.img_size env.img_size]);
    raw_feats = [ebno, ber_f(i_last), rssi_f(i_last), plr_f(i_last), var_rssi_10, dber_dt, burst_ratio];
    raw_feats(isnan(raw_feats)) = 0;
    norm_feats = (raw_feats - env.feat_mean) ./ env.feat_std;
    X_spec = dlarray(single(spec_img), 'SSCB'); X_feat = dlarray(single(norm_feats)', 'CB');
    if canUseGPU, X_spec = gpuArray(X_spec); X_feat = gpuArray(X_feat); end
    pred = predict(env.cnn_net, X_spec, X_feat);
    cnn_ms = toc(t1) * 1000;

    probs = gather(extractdata(pred)); probs = probs(:);
    [conf, idx] = max(probs);
    top_class = env.class_list{idx};
    is_unknown = (100 * conf) < thr_pct;
    if is_unknown, cnn_class = 'unknown'; else, cnn_class = top_class; end

    dqn_state = build_dqn_state(cnn_class, raw_feats(2), raw_feats(3), ebno, raw_feats(4));
    sdl = dlarray(single(dqn_state), 'CB'); if canUseGPU, sdl = gpuArray(sdl); end
    t2 = tic;
    qraw = predict(env.dqn_agent.qNetwork, sdl);
    dqn_ms = toc(t2) * 1000;
    qv = gather(extractdata(qraw)); qv = qv(:);
    [~, aidx] = max(qv);
    action_name = env.action_names{aidx};
    total_ms = cnn_ms + dqn_ms;

    if is_unknown
        rule_action = 'no_action';          % the rule table has no entry for an unknown threat
    else
        [ra, ~] = rule_based_policy(cnn_class);
        rule_action = strrep(ra, 'channel_switch_fast', 'channel_switch');
    end
    ridx = find(strcmp(env.action_names, rule_action), 1); if isempty(ridx), ridx = 0; end

    %% ---- 3. show detection + decision ----
    correct = strcmp(cnn_class, threat);
    drawSpec(fig, Pw_db, Fq, Tq, sprintf('Spectrogram - %s @ %g dB', niceName(threat), ebno));
    drawProbs(fig, probs, env.class_list, idx, truth_idx, is_unknown);
    ui.confGauge.Value = min(100, 100 * conf);
    ui.latGauge.Value = min(30, total_ms);
    if is_unknown
        ui.detLbl.Text = sprintf('UNKNOWN THREAT  (best guess %s, %.0f%%)', niceName(top_class), 100*conf);
        ui.detLbl.FontColor = c.amber;
    elseif correct
        ui.detLbl.Text = sprintf('%s   (%.1f%%)  -  CORRECT', niceName(cnn_class), 100*conf);
        ui.detLbl.FontColor = c.green;
    else
        ui.detLbl.Text = sprintf('%s   (%.1f%%)  -  TRUE: %s', niceName(cnn_class), 100*conf, niceName(threat));
        ui.detLbl.FontColor = c.red;
    end
    appLog(fig, sprintf('CNN: %s (%.1f%%) | decision latency %.2f ms (CNN %.2f + DQN %.2f)', ...
        niceName(cnn_class), 100*conf, total_ms, cnn_ms, dqn_ms));
    drawLinkDiagram(fig, 'detected', threat, cnn_class, ...
        struct('v_kmh', v_kmh, 'fd', fd_hz, 'conf', conf, 'correct', correct, 'unknown', is_unknown));
    drawQ(fig, qv, aidx, ridx);
    agree = strcmp(action_name, rule_action);
    if agree, agTxt = 'AGREE'; else, agTxt = 'DIFFER'; end
    ui.decLbl.Text = {sprintf('DQN  -> %s', niceName(action_name)), ...
                      sprintf('RULE -> %s   [%s]', niceName(rule_action), agTxt)};
    appLog(fig, sprintf('DQN: %s | RULE: %s (%s)', niceName(action_name), niceName(rule_action), agTxt));
    smartPause(fig, 0.7, tSeq); checkAbort(fig);

    %% ---- 4. real mitigation simulations (DQN choice, and rule choice if different) ----
    drawLinkDiagram(fig, 'mitigating', threat, action_name, struct('v_kmh', v_kmh, 'fd', fd_hz));
    Rd = []; Rr = [];
    dqnNone = strcmp(action_name, 'no_action');
    ruleNone = strcmp(rule_action, 'no_action');
    if ~dqnNone
        appLog(fig, sprintf('Applying DQN countermeasure (%s) and re-simulating the link...', niceName(action_name)));
        Rd = applyMitigation(env, p, threat, action_name, snr_dB);
        updateTimer(fig, tSeq); checkAbort(fig);
    else
        appLog(fig, 'DQN chose NO ACTION - monitoring the link.');
    end
    if doRule && ~ruleNone
        if strcmp(rule_action, action_name)
            Rr = Rd;
        else
            appLog(fig, sprintf('Re-simulating with the rule-based choice (%s) for comparison...', niceName(rule_action)));
            Rr = applyMitigation(env, p, threat, rule_action, snr_dB);
            updateTimer(fig, tSeq); checkAbort(fig);
        end
    end

    ber_dqn  = ber_before_mean; if ~isempty(Rd), ber_dqn  = Rd.ber_mean; end
    ber_rule = ber_before_mean; if ~isempty(Rr), ber_rule = Rr.ber_mean; end
    if isfinite(refBer)
        recOf = @(b) recovery_vs_clean(ber_before_mean, b, refBer);   % KPI #2: vs the clean link
    else
        recOf = @(b) 100 * (ber_before_mean - b) / max(ber_before_mean, eps);
    end
    if dqnNone && (ruleNone || ~doRule), rec_dqn = NaN; else, rec_dqn = recOf(ber_dqn); end
    if ~doRule || (dqnNone && ruleNone), rec_rule = NaN; else, rec_rule = recOf(ber_rule); end

    %% ---- 5. outcome views ----
    if ~isempty(Rd), iq_after = Rd.iq; else, iq_after = iq_before; end
    drawIQ(fig, iq_after, c.green, 'IQ constellation - after', Lq);
    if ~isempty(Rd), tl.ber_d = Rd.ber_f; tl.rssi_d = Rd.rssi_f; end
    if ~isempty(Rr) && ~strcmp(rule_action, action_name), tl.ber_r = Rr.ber_f; tl.rssi_r = Rr.rssi_f; end
    drawTimeline(fig, tl);

    [verdict, vcol, vstat] = verdictFor(env, c, ebno, ber_dqn, action_name);
    names = {'NO ACTION', 'DQN'}; vals = [ber_before_mean, ber_dqn]; cols = [c.red; c.green];
    if doRule
        names{end+1} = 'RULE'; vals(end+1) = ber_rule; cols = [cols; c.purp]; %#ok<AGROW>
    end
    drawOutcome(fig, vals, names, cols);

    [~, ~, cmD] = apply_countermeasure(p, threat, action_name);
    goodput = sprintf('COST (DQN): goodput x%.2f | spectrum x%d | %s', cmD.goodput_factor, cmD.bw_factor, cmD.effect);
    lines = {outLine('BER before', ber_before_mean, NaN), outLine('BER DQN   ', ber_dqn, rec_dqn)};
    if doRule, lines{end+1} = outLine('BER RULE  ', ber_rule, rec_rule); else, lines{end+1} = '(rule comparison off)'; end
    lines{end+1} = goodput;
    ui.outLbl.Text = lines;
    ui.verdictLbl.Text = verdict; ui.verdictLbl.FontColor = vcol;
    threatRemains = (vstat == 3) && ~ismember(threat, {'none','benign_interference'});
    drawLinkDiagram(fig, 'resolved', threat, action_name, struct('v_kmh', v_kmh, 'fd', fd_hz, ...
        'verdict', verdict, 'color', vcol, 'threatRemains', threatRemains));
    if isnan(rec_dqn)
        appLog(fig, sprintf('Outcome: no countermeasure applied - %s', verdict));
    else
        appLog(fig, sprintf('Outcome: BER %.2e -> %.2e (%.1f%% recovered) - %s', ber_before_mean, ber_dqn, rec_dqn, verdict));
    end
    smartPause(fig, 0.9, tSeq);

    %% ---- 6. log the run ----
    if is_unknown, detShown = ['UNKNOWN (' top_class ')']; else, detShown = cnn_class; end
    if correct, ok = 'PASS'; elseif is_unknown, ok = 'UNKNOWN'; else, ok = 'FAIL'; end
    if doRule, ruleShown = rule_action; else, ruleShown = '-'; end
    H = getappdata(fig, 'history');
    n = numel(H) + 1;
    entry = struct('run', n, 'timestamp', datestr(now), 'threat', threat, 'snr_dB', ebno, ...
        'speed_kmh', v_kmh, 'fd_hz', fd_hz, 'severity', sevTxt, ...
        'cnn_detected', cnn_class, 'cnn_top_guess', top_class, 'cnn_confidence', conf, ...
        'cnn_correct', correct, 'unknown', is_unknown, ...
        'dqn_action', action_name, 'rule_action', rule_action, 'agree', agree, ...
        'ber_before', ber_before_mean, 'ber_after_dqn', ber_dqn, 'ber_after_rule', ber_rule, ...
        'ber_clean_ref', refBer, 'rec_dqn', rec_dqn, 'rec_rule', rec_rule, ...
        'verdict', verdict, 'verdict_status', vstat, ...
        'cnn_latency_ms', cnn_ms, 'dqn_latency_ms', dqn_ms, 'decision_latency_ms', total_ms);
    H{end+1} = entry; setappdata(fig, 'history', H);
    ui.histTbl.Data = [ui.histTbl.Data; { n, niceName(threat), sprintf('%g dB', ebno), ...
        sprintf('%.1f', v_kmh), sevTxt, [niceName(detShown) ' [' ok ']'], sprintf('%.0f%%', 100*conf), ...
        niceName(action_name), niceName(ruleShown), pctStr(rec_dqn), pctStr(rec_rule), verdict, ...
        sprintf('%.1f', total_ms) }];
    setappdata(fig, 'lastRun', struct('threat', threat, 'level', sevLevel, 'snr', ebno, 'status', vstat));
    updateSessionSummary(fig);
    updateSurvMap(fig);
end

function s = pctStr(x)
    if isnan(x), s = 'N/A'; else, s = sprintf('%.1f%%', x); end
end

function s = outLine(lbl, ber, rec)
    if isnan(rec), s = sprintf('%s: %.2e', lbl, ber);
    else,          s = sprintf('%s: %.2e   (%.1f%% recovered)', lbl, ber, rec); end
end

function R = applyMitigation(env, p, threat, action_name, snr_dB) %#ok<INUSL>
    % Real second simulation of the link with the countermeasure applied to the
    % TRUE threat (same physics as training and evaluation, apply_countermeasure.m).
    [p2, g_db] = apply_countermeasure(p, threat, action_name);
    params = p2; save('params.mat', 'params'); %#ok<NASGU>
    build_threat_model;
    set_param([env.modelName '/AWGN'], 'SNR', num2str(snr_dB + g_db), 'SignalPower', num2str(1/p2.sps));
    out2 = sim(env.modelName);
    [iqf, berf, rssif, ~, nf2] = extract_closed_loop_frames(out2, p2, env.delay_bits);
    i2 = find(~isnan(berf), 1, 'last'); if isempty(i2), i2 = nf2; end
    R = struct('iq', iqf{i2}, 'ber_f', berf, 'rssi_f', rssif, 'ber_mean', mean(berf, 'omitnan'));
end

function [txt, col, status] = verdictFor(env, c, ebno, ber_final, action_name)
    % Classify the FINAL link state with the same criteria as the survivability
    % map (proposal deliverable #7): BER relative to the clean channel.
    status = 0; txt = 'VERDICT N/A (no survivability reference - run map_survivability_boundary)'; col = c.mut;
    if isempty(env.surv), return; end
    k = find(env.surv.SNR_points == ebno, 1);
    if isempty(k), return; end
    ratio = ber_final / max(env.surv.ber_clean(k), eps);
    if ratio <= env.surv.RATIO_RECOVERABLE, status = 1;
    elseif ratio <= env.surv.RATIO_MARGINAL, status = 2;
    else, status = 3; end
    noAct = strcmp(action_name, 'no_action');
    switch status
        case 1
            col = c.green;
            if noAct, txt = sprintf('LINK NOMINAL - no action needed  (BER = %.1fx clean)', ratio);
            else,     txt = sprintf('RECOVERABLE - link restored  (BER = %.1fx clean)', ratio); end
        case 2
            col = c.amber;
            if noAct, txt = sprintf('DEGRADED - no action taken  (BER = %.1fx clean)', ratio);
            else,     txt = sprintf('MARGINAL - partially restored  (BER = %.1fx clean)', ratio); end
        otherwise
            col = c.red;
            if noAct, txt = sprintf('UNMITIGATED - link degraded  (BER = %.1fx clean)', ratio);
            else,     txt = sprintf('NON-RECOVERABLE - countermeasure insufficient  (BER = %.1fx clean)', ratio); end
    end
end

%% =====================================================================
%% ============================  VIEW HELPERS  ==========================
%% =====================================================================
function resetRunViews(fig)
    data = fig.UserData; ui = data.ui; c = data.colors;
    axs = {ui.specAx, ui.iqAx, ui.berAx, ui.rssiAx, ui.probAx, ui.qAx, ui.outAx};
    for k = 1:numel(axs)
        legend(axs{k}, 'off'); cla(axs{k});
    end
    setTitle(ui.specAx, 'Spectrogram', c); setTitle(ui.iqAx, 'IQ constellation', c);
    ui.confGauge.Value = 0; ui.latGauge.Value = 0;
    ui.detLbl.Text = '-'; ui.detLbl.FontColor = c.txt;
    ui.decLbl.Text = {'-'}; ui.outLbl.Text = {'-'};
    ui.verdictLbl.Text = 'RUNNING...'; ui.verdictLbl.FontColor = c.accent;
end

function setProgress(fig, frac)
    data = fig.UserData; ax = data.ui.progAx; c = data.colors;
    cla(ax);
    if frac > 0
        patch(ax, [0 frac frac 0], [0 0 1 1], c.green, 'EdgeColor', 'none');
    end
    ax.XLim = [0 1]; ax.YLim = [0 1];
end

function drawSpec(fig, Pw_db, Fq, Tq, ttl)
    data = fig.UserData; ax = data.ui.specAx; c = data.colors;
    cla(ax);
    imagesc(ax, Tq * 1e3, Fq / 1e6, Pw_db);
    ax.YDir = 'normal'; ax.CLim = [data.env.db_lo data.env.db_hi];
    colormap(ax, 'turbo');
    xlabel(ax, 'Time (ms)', 'Color', c.mut); ylabel(ax, 'Frequency (MHz)', 'Color', c.mut);
    axis(ax, 'tight');
    setTitle(ax, ttl, c);
end

function drawIQ(fig, iq, colr, ttl, L)
    data = fig.UserData; ax = data.ui.iqAx; c = data.colors;
    cla(ax);
    s = iq(1:min(400, numel(iq)));
    scatter(ax, real(s), imag(s), 14, colr, 'filled', 'MarkerFaceAlpha', 0.55);
    ax.XLim = [-L L]; ax.YLim = [-L L]; grid(ax, 'on');
    xlabel(ax, 'In-phase', 'Color', c.mut); ylabel(ax, 'Quadrature', 'Color', c.mut);
    setTitle(ax, ttl, c);
end

function drawProbs(fig, probs, classes, idx, truth_idx, isUnknown)
    data = fig.UserData; ax = data.ui.probAx; c = data.colors;
    cla(ax); n = numel(probs);
    b = barh(ax, 1:n, 100 * probs, 'FaceColor', 'flat');
    cd = repmat([0.36 0.40 0.48], n, 1);
    if isUnknown, cd(idx, :) = c.amber; else, cd(idx, :) = c.accent; end
    b.CData = cd;
    ax.YDir = 'reverse'; ax.YTick = 1:n;
    ax.YTickLabel = cellfun(@(x) strrep(x, '_', ' '), classes(:)', 'UniformOutput', false);
    ax.TickLabelInterpreter = 'none'; ax.FontSize = 9;
    ax.XLim = [0 135]; ax.XTick = [0 25 50 75 100];
    for k = 1:n
        isTruth = ~isempty(truth_idx) && k == truth_idx;
        if probs(k) >= 0.005 || isTruth
            lab = sprintf('%.1f%%', 100 * probs(k));
            if isTruth, lab = [lab '  <- truth']; end %#ok<AGROW>
            text(ax, 100 * probs(k) + 2, k, lab, 'Color', c.txt, 'FontSize', 8, 'FontName', c.font);
        end
    end
    setTitle(ax, 'Class probabilities (%)', c);
end

function drawQ(fig, qv, aidx, ridx)
    data = fig.UserData; ax = data.ui.qAx; c = data.colors;
    cla(ax); hold(ax, 'on');
    b = bar(ax, 1:5, qv, 'FaceColor', 'flat');
    cd = repmat([0.36 0.40 0.48], 5, 1); cd(aidx, :) = c.accent; b.CData = cd;
    span = max(qv) - min(qv) + 1;
    for k = 1:5
        text(ax, k, qv(k), sprintf('%.1f', qv(k)), 'Color', c.txt, 'FontSize', 9, ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontName', c.font);
    end
    if ridx > 0
        plot(ax, ridx, qv(ridx) + 0.12 * span, 'v', 'MarkerSize', 11, 'MarkerFaceColor', c.purp, ...
            'MarkerEdgeColor', 'w');
    end
    hold(ax, 'off');
    ax.XTick = 1:5; ax.XTickLabel = {'NONE','CH-SWITCH','RATE-RED','FREQ-DIV','SPATIAL'};
    ax.XLim = [0.4 5.6]; ax.YLim = [min(0, min(qv) - 0.15*span), max(qv) + 0.32*span];
    grid(ax, 'on');
    setTitle(ax, 'DQN Q-values  (blue = DQN choice, purple v = rule choice)', c);
end

function drawOutcome(fig, vals, names, cols)
    data = fig.UserData; ax = data.ui.outAx; c = data.colors; fl = data.env.ber_floor;
    cla(ax); hold(ax, 'on');
    n = numel(vals); vp = max(vals, fl);
    b = bar(ax, 1:n, vp, 'FaceColor', 'flat'); b.CData = cols;
    for k = 1:n
        text(ax, k, vp(k), sprintf('%.2e', vals(k)), 'Color', c.txt, 'FontSize', 9, ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontName', c.font);
    end
    hold(ax, 'off');
    ax.YScale = 'log'; ax.XTick = 1:n; ax.XTickLabel = names; ax.XLim = [0.4 n + 0.6];
    ax.YLim = [fl * 0.6, 3]; grid(ax, 'on');
    setTitle(ax, 'Mean BER (log scale)', c);
end

function drawTimeline(fig, tl)
    data = fig.UserData; ui = data.ui; c = data.colors; env = data.env;
    fl = env.ber_floor;
    ms_per_frame = env.p0.frame_duration * 1e3;

    % ---------- BER ----------
    ax = ui.berAx; legend(ax, 'off'); cla(ax); hold(ax, 'on');
    nb = numel(tl.ber_b); h = gobjects(0); nm = {};
    h(end+1) = plot(ax, 1:nb, floorBer(tl.ber_b, fl), '-o', 'Color', c.red, 'LineWidth', 1.8, ...
        'MarkerSize', 4, 'MarkerFaceColor', c.red); nm{end+1} = 'Before (no action)'; %#ok<AGROW>
    xmax = nb;
    if ~isempty(tl.ber_d)
        xa = nb + (1:numel(tl.ber_d));
        h(end+1) = plot(ax, xa, floorBer(tl.ber_d, fl), '-o', 'Color', c.green, 'LineWidth', 1.8, ...
            'MarkerSize', 4, 'MarkerFaceColor', c.green); nm{end+1} = 'After - DQN'; %#ok<AGROW>
        xmax = max(xmax, xa(end));
    end
    if ~isempty(tl.ber_r)
        xr = nb + (1:numel(tl.ber_r));
        h(end+1) = plot(ax, xr, floorBer(tl.ber_r, fl), '--s', 'Color', c.purp, 'LineWidth', 1.5, ...
            'MarkerSize', 4, 'MarkerFaceColor', c.purp); nm{end+1} = 'After - RULE'; %#ok<AGROW>
        xmax = max(xmax, xr(end));
    end
    if xmax > nb
        xline(ax, nb + 0.5, '--', 'Color', c.amber, 'LineWidth', 1.2);
    end
    if ~isnan(tl.ref) && tl.ref > 0
        rv = max(tl.ref, fl);
        h(end+1) = plot(ax, [0.5, max(xmax, 2) + 0.5], [rv rv], ':', 'Color', c.cyan, 'LineWidth', 1.4); %#ok<AGROW>
        nm{end+1} = 'Clean channel'; %#ok<AGROW>
    end
    hold(ax, 'off');
    ax.YScale = 'log'; ax.YLim = [fl * 0.6, 1]; ax.XLim = [0.5 max(xmax, 2) + 0.5]; grid(ax, 'on');
    xlabel(ax, sprintf('Frame index (1 frame = %.2f ms)', ms_per_frame), 'Color', c.mut);
    ylabel(ax, 'BER', 'Color', c.mut);
    legend(ax, h, nm, 'Location', 'northeast', 'TextColor', c.txt, 'Color', c.panelBg, ...
        'EdgeColor', c.mut, 'FontSize', 9);
    setTitle(ax, 'BER per frame  (dashed amber line = countermeasure applied)', c);

    % ---------- RSSI ----------
    ax = ui.rssiAx; legend(ax, 'off'); cla(ax); hold(ax, 'on');
    plot(ax, 1:nb, tl.rssi_b, '-o', 'Color', c.red, 'LineWidth', 1.6, 'MarkerSize', 3, 'MarkerFaceColor', c.red);
    if ~isempty(tl.rssi_d)
        plot(ax, nb + (1:numel(tl.rssi_d)), tl.rssi_d, '-o', 'Color', c.green, 'LineWidth', 1.6, ...
            'MarkerSize', 3, 'MarkerFaceColor', c.green);
    end
    if ~isempty(tl.rssi_r)
        plot(ax, nb + (1:numel(tl.rssi_r)), tl.rssi_r, '--s', 'Color', c.purp, 'LineWidth', 1.4, 'MarkerSize', 3);
    end
    if xmax > nb, xline(ax, nb + 0.5, '--', 'Color', c.amber, 'LineWidth', 1.2); end
    hold(ax, 'off');
    ax.XLim = [0.5 max(xmax, 2) + 0.5]; grid(ax, 'on');
    xlabel(ax, 'Frame index', 'Color', c.mut); ylabel(ax, 'RSSI (dB)', 'Color', c.mut);
    setTitle(ax, 'RSSI per frame', c);
end

function v = floorBer(v, fl)
    v(v < fl) = fl;          % NaN stays NaN (gap in the plot)
end

%% ---------------------- link diagram ----------------------
function drawLinkDiagram(fig, state, scen, det, info)
    data = fig.UserData; c = data.colors; ax = data.ui.linkAx;
    cla(ax); hold(ax, 'on'); ax.XLim = [0 16]; ax.YLim = [0 3];
    hostile = ~ismember(scen, {'none','benign_interference',''});
    xg = 1.6; yg = 1.95; xu = 13.0; yu = 1.55;
    if strcmp(scen, 'path_loss') && ~strcmp(state, 'idle'), xu = 14.4; end

    % ----- state -> colours / message -----
    hdrState = 'idle';
    switch state
        case 'idle'
            lc = c.mut; ls = ':'; msg = 'STANDBY - AWAITING COMMAND'; mc = c.mut;
        case 'scenario'
            if hostile
                lc = c.red; ls = '--'; hdrState = 'attack';
            elseif strcmp(scen, 'benign_interference')
                lc = c.accent; ls = '-'; hdrState = 'benign';
            else
                lc = c.green; ls = '-'; hdrState = 'nominal';
            end
            mc = lc; msg = ['SCENARIO INJECTED (ground truth): ' niceName(scen)];
        case 'detected'
            lc = c.amber; ls = '--'; hdrState = 'attack';
            if strcmp(scen, 'benign_interference')
                lc = c.accent; ls = '-'; hdrState = 'benign';
            elseif strcmp(scen, 'none')
                lc = c.green; ls = '-'; hdrState = 'nominal';
            end
            if isfield(info, 'unknown') && info.unknown
                mc = c.amber; msg = sprintf('CNN: UNKNOWN THREAT  (%.0f%%)', 100*info.conf);
            elseif isfield(info, 'correct') && info.correct
                mc = c.green; msg = sprintf('CNN DETECTED: %s  (%.1f%%)', niceName(det), 100*info.conf);
            else
                mc = c.red; msg = sprintf('CNN DETECTED: %s  (%.1f%%) - MISMATCH', niceName(det), 100*info.conf);
            end
        case 'mitigating'
            lc = c.amber; ls = '--'; hdrState = 'recovering'; mc = c.amber;
            msg = ['DRL COUNTERMEASURE: ' niceName(det)];
        case 'resolved'
            lc = info.color; ls = '-'; mc = info.color; msg = info.verdict;
            hdrState = 'resolved';
        otherwise
            lc = c.mut; ls = ':'; msg = ''; mc = c.mut;
    end

    % ----- endpoints -----
    drawGCS(ax, xg, c);
    faulty = strcmp(scen, 'antenna_fault') && any(strcmp(state, {'scenario','detected','mitigating'}));
    drawUAV(ax, xu, yu, c, faulty);

    % ----- main link -----
    plot(ax, [xg xu], [yg yu], ls, 'Color', lc, 'LineWidth', 3);
    xm = (xg + xu) / 2; ym = (yg + yu) / 2;

    % ----- threat overlay -----
    showThreat = any(strcmp(state, {'scenario','detected','mitigating'})) || ...
        (strcmp(state, 'resolved') && isfield(info, 'threatRemains') && info.threatRemains);
    if showThreat, drawThreat(ax, scen, xm, ym, xg, yg, xu, yu, c); end

    % ----- countermeasure overlay -----
    if strcmp(state, 'mitigating'), drawCountermeasure(ax, det, xg, yg, xu, yu, c); end

    text(ax, 8, 2.72, msg, 'Color', mc, 'FontWeight', 'bold', 'FontSize', 13, ...
        'HorizontalAlignment', 'center', 'FontName', c.font, 'Interpreter', 'none');
    if isfield(info, 'v_kmh')
        text(ax, 15.85, 0.18, sprintf('v = %.1f km/h  |  fd = %.0f Hz', info.v_kmh, info.fd), ...
            'Color', c.cyan, 'FontSize', 10, 'HorizontalAlignment', 'right', 'FontName', c.mono);
    end
    hold(ax, 'off');

    % ----- header lamp -----
    switch hdrState
        case 'attack',     setLinkHeader(fig, 'UNDER ATTACK', c.red);
        case 'benign',     setLinkHeader(fig, 'BENIGN INTERFERENCE', c.accent);
        case 'nominal',    setLinkHeader(fig, 'NOMINAL', c.green);
        case 'recovering', setLinkHeader(fig, 'RECOVERING', c.amber);
        case 'resolved',   setLinkHeader(fig, 'RESULT READY', info.color);
        otherwise,         setLinkHeader(fig, 'STANDBY', c.mut);
    end
    drawnow;
    if ismember(state, {'scenario','detected','mitigating','resolved'})
        recordFrame(fig);  % one capture per real state transition, not per timer tick
    end
end

function setLinkHeader(fig, txt, col)
    ui = fig.UserData.ui;
    ui.linkLamp.FontColor = col; ui.linkTxt.FontColor = col; ui.linkTxt.Text = ['LINK: ' txt];
end

function drawGCS(ax, x, c)
    patch(ax, [x-0.9 x+0.9 x+0.7 x-0.7], [0.35 0.35 0.80 0.80], [0.20 0.26 0.34], ...
        'EdgeColor', c.accent, 'LineWidth', 1.5);
    plot(ax, [x x], [0.80 1.90], 'Color', [0.72 0.75 0.80], 'LineWidth', 3);
    scatter(ax, x, 1.95, 90, c.accent, 'filled', 'MarkerEdgeColor', 'w');
    text(ax, x, 0.14, 'GCS', 'Color', c.txt, 'FontWeight', 'bold', 'FontSize', 11, ...
        'HorizontalAlignment', 'center', 'FontName', c.font);
end

function drawUAV(ax, x, y, c, faulty)
    body = [0.30 0.35 0.42];
    patch(ax, [x-0.65 x+0.65 x+0.45 x-0.45], [y-0.14 y-0.14 y+0.14 y+0.14], body, ...
        'EdgeColor', c.accent, 'LineWidth', 1.5);
    plot(ax, [x-0.45 x-1.05], [y+0.10 y+0.32], 'Color', [0.65 0.68 0.75], 'LineWidth', 2.2);
    plot(ax, [x+0.45 x+1.05], [y+0.10 y+0.32], 'Color', [0.65 0.68 0.75], 'LineWidth', 2.2);
    t = linspace(-0.45, 0.45, 24); rr = 0.05 * sqrt(max(0, 1 - (t/0.45).^2));
    for s = [-1.05 1.05]
        patch(ax, x + s + t, y + 0.36 + rr, [0.80 0.88 0.90], 'EdgeColor', 'none');
        patch(ax, x + s + t, y + 0.36 - rr, [0.80 0.88 0.90], 'EdgeColor', 'none');
    end
    plot(ax, [x x], [y+0.14 y+0.50], 'Color', [0.72 0.75 0.80], 'LineWidth', 2);     % antenna
    if faulty
        plot(ax, [x-0.15 x+0.12 x-0.10 x+0.15], [y+0.50 y+0.62 y+0.74 y+0.88], 'Color', c.amber, 'LineWidth', 2);
        scatter(ax, x + 0.28, y + 0.85, 160, c.amber, '*');
    else
        scatter(ax, x, y + 0.52, 55, c.accent, 'filled', 'MarkerEdgeColor', 'w');
    end
    text(ax, x, y - 0.42, 'UAV', 'Color', c.txt, 'FontWeight', 'bold', 'FontSize', 11, ...
        'HorizontalAlignment', 'center', 'FontName', c.font);
end

function drawJammerIcon(ax, x, y, col, label, c)
    patch(ax, [x-0.35 x+0.35 x], [y-0.22 y-0.22 y+0.28], col, 'EdgeColor', 'w', 'LineWidth', 1);
    text(ax, x, y - 0.40, label, 'Color', col, 'FontWeight', 'bold', 'FontSize', 9, ...
        'HorizontalAlignment', 'center', 'FontName', c.font);
end

function drawWaves(ax, x, y, col)
    th = linspace(pi/2 - 0.85, pi/2 + 0.85, 24);
    for r = [0.55 0.95 1.35]
        plot(ax, x + r*cos(th), y + 0.25 + r*sin(th), 'Color', col, 'LineWidth', 1.6);
    end
end

function drawThreat(ax, scen, xm, ym, xg, yg, xu, yu, c)
    jy = 0.50;
    switch scen
        case 'jamming'
            drawJammerIcon(ax, xm, jy, c.red, 'BARRAGE JAMMER', c); drawWaves(ax, xm, jy, c.red);
        case 'noise_burst'
            drawJammerIcon(ax, xm, jy, c.red, 'BURST JAMMER', c); drawWaves(ax, xm, jy, c.red);
            for k = 1:6
                xx = xm - 2.0 + 0.7 * k;
                plot(ax, [xx xx], [ym - 0.18, ym + 0.18 + 0.12 * mod(k, 2)], 'Color', c.red, 'LineWidth', 2.2);
            end
        case 'reactive_jamming'
            drawJammerIcon(ax, xm, jy, c.red, 'REACTIVE JAMMER', c); drawWaves(ax, xm, jy, c.red);
            plot(ax, [xm + 0.5, xm + 2.2], [jy + 0.9, ym - 0.08], ':', 'Color', c.amber, 'LineWidth', 1.6);
            text(ax, xm + 2.3, ym - 0.22, 'senses Tx', 'Color', c.amber, 'FontSize', 8, 'FontName', c.font);
        case 'sweeping_jammer'
            drawJammerIcon(ax, xm, jy, c.red, 'SWEEPING JAMMER', c); drawWaves(ax, xm, jy, c.red);
            plot(ax, xm + [-2.2 -1.5 -1.5 -0.8 -0.8 -0.1], jy + [0.2 0.8 0.2 0.8 0.2 0.8], 'Color', c.red, 'LineWidth', 1.6);
        case 'spoofing'
            fx = xm + 1.6;
            patch(ax, [fx-0.7 fx+0.7 fx+0.5 fx-0.5], [0.25 0.25 0.62 0.62], [0.30 0.20 0.40], ...
                'EdgeColor', c.purp, 'LineWidth', 1.5);
            plot(ax, [fx fx], [0.62 1.10], 'Color', c.purp, 'LineWidth', 2.5);
            scatter(ax, fx, 1.14, 70, c.purp, 'filled', 'MarkerEdgeColor', 'w');
            plot(ax, [fx xu], [1.14, yu + 0.05], '--', 'Color', c.purp, 'LineWidth', 2.5);
            text(ax, fx, 0.08, 'FAKE GCS', 'Color', c.purp, 'FontWeight', 'bold', 'FontSize', 9, ...
                'HorizontalAlignment', 'center', 'FontName', c.font);
        case 'path_loss'
            for k = 1:5
                a = 0.15 + 0.17 * (k - 1);
                plot(ax, xg + (xu - xg) * [a, a + 0.12], yg + (yu - yg) * [a, a + 0.12] - 0.22, ...
                    'Color', c.amber, 'LineWidth', max(0.8, 3.2 - 0.6 * k));
            end
            text(ax, xm, ym - 0.5, 'RANGE / ATTENUATION', 'Color', c.amber, 'FontSize', 9, ...
                'HorizontalAlignment', 'center', 'FontName', c.font);
        case 'antenna_fault'
            text(ax, xu - 2.1, yu + 0.85, 'ANTENNA FAULT', 'Color', c.amber, 'FontWeight', 'bold', ...
                'FontSize', 9, 'HorizontalAlignment', 'center', 'FontName', c.font);
        case 'benign_interference'
            patch(ax, [xm-0.3 xm+0.3 xm+0.3 xm-0.3], [jy-0.2 jy-0.2 jy+0.2 jy+0.2], c.accent, ...
                'EdgeColor', 'w', 'LineWidth', 1);
            th = linspace(pi/2 - 0.7, pi/2 + 0.7, 18);
            for r = [0.4 0.7]
                plot(ax, xm + r*cos(th), jy + 0.25 + r*sin(th), ':', 'Color', c.accent, 'LineWidth', 1.3);
            end
            text(ax, xm, jy - 0.42, 'ISM DEVICE (BENIGN)', 'Color', c.accent, 'FontSize', 9, ...
                'HorizontalAlignment', 'center', 'FontName', c.font);
        otherwise
            text(ax, xm, ym - 0.5, 'CLEAN CHANNEL', 'Color', c.green, 'FontSize', 9, ...
                'HorizontalAlignment', 'center', 'FontName', c.font);
    end
end

function drawCountermeasure(ax, action, xg, yg, xu, yu, c)
    switch action
        case 'channel_switch'
            plot(ax, [xg xu], [yg + 0.40, yu + 0.40], '-', 'Color', c.green, 'LineWidth', 2.5);
            text(ax, (xg + xu)/2, yg + 0.62, 'NEW CHANNEL', 'Color', c.green, 'FontSize', 9, ...
                'HorizontalAlignment', 'center', 'FontName', c.font);
        case 'rate_reduce'
            plot(ax, [xg xu], [yg + 0.40, yu + 0.40], ':', 'Color', c.green, 'LineWidth', 2.5);
            text(ax, (xg + xu)/2, yg + 0.62, 'LOWER RATE  (goodput reduced)', 'Color', c.green, ...
                'FontSize', 9, 'HorizontalAlignment', 'center', 'FontName', c.font);
        case 'freq_diversity'
            plot(ax, [xg xu], [yg + 0.32, yu + 0.32], '-', 'Color', c.green, 'LineWidth', 2);
            plot(ax, [xg xu], [yg + 0.52, yu + 0.52], '-', 'Color', c.green, 'LineWidth', 2);
            text(ax, (xg + xu)/2, yg + 0.74, 'F1 + F2  (frequency diversity)', 'Color', c.green, ...
                'FontSize', 9, 'HorizontalAlignment', 'center', 'FontName', c.font);
        case 'spatial_diversity'
            plot(ax, [xg, xu - 0.6], [yg + 0.38, yu + 0.30], '-', 'Color', c.green, 'LineWidth', 2);
            plot(ax, [xg, xu + 0.6], [yg + 0.58, yu + 0.30], '-', 'Color', c.green, 'LineWidth', 2);
            text(ax, (xg + xu)/2, yg + 0.80, 'ANT 1 + ANT 2  (spatial diversity)', 'Color', c.green, ...
                'FontSize', 9, 'HorizontalAlignment', 'center', 'FontName', c.font);
        otherwise
            text(ax, (xg + xu)/2, yg + 0.55, 'NO ACTION - MONITORING', 'Color', c.mut, 'FontSize', 9, ...
                'HorizontalAlignment', 'center', 'FontName', c.font);
    end
end

%% =====================================================================
%% ==========================  LOG / TIMER  =============================
%% =====================================================================
function appLog(fig, msg)
    data = fig.UserData; ta = data.ui.termArea;
    line = sprintf('[%s] %s', datestr(now, 'HH:MM:SS'), msg);
    v = ta.Value;
    if ischar(v), v = {v}; end
    if numel(v) == 1 && isempty(v{1}), v = {}; end
    v = [v(:); {line}];
    if numel(v) > 200, v = v(end-199:end); end
    ta.Value = v;
    scroll(ta, 'bottom');
    fid = getappdata(fig, 'logFid');
    if ~isempty(fid) && fid > 0, fprintf(fid, '%s\n', line); end
    drawnow;
end

function updateTimer(fig, tSeq)
    ui = fig.UserData.ui;
    elap = toc(tSeq);
    ui.timeLbl.Text = sprintf('%02d:%05.2f', floor(elap / 60), mod(elap, 60));
    drawnow;
end

function recordFrame(fig)
    vw = getappdata(fig, 'videoWriter');
    if ~isempty(vw)
        try
            writeVideo(vw, getframe(fig));
        catch
        end
    end
end

function smartPause(fig, secs, tSeq)
    % Video frame capture no longer happens here — getframe(fig) on a
    % uifigure is expensive per call regardless of frequency (it round-trips
    % through the CEF-based renderer), so it is captured once per real state
    % transition inside drawLinkDiagram instead. This loop only drives the
    % on-screen timer.
    n = max(1, round(secs * 10));
    for k = 1:n
        updateTimer(fig, tSeq);
        pause(0.1);
    end
end

function updateSessionSummary(fig)
    ui = fig.UserData.ui;
    H = getappdata(fig, 'history');
    if isempty(H), ui.sessionLbl.Text = {'No runs yet.'}; return; end
    n = numel(H);
    corr = cellfun(@(h) h.cnn_correct, H); unk = cellfun(@(h) h.unknown, H);
    recD = cellfun(@(h) h.rec_dqn, H);     recR = cellfun(@(h) h.rec_rule, H);
    lat  = cellfun(@(h) h.decision_latency_ms, H);
    both = ~isnan(recD) & ~isnan(recR);
    better = sum(recD(both) > recR(both) + 1); worse = sum(recD(both) < recR(both) - 1);
    same = sum(both) - better - worse;
    ui.sessionLbl.Text = { ...
        sprintf('RUNS %d | detection %d/%d (%.1f%%) | unknown %d | mean latency %.2f ms', ...
            n, sum(corr), n, 100*mean(corr), sum(unk), mean(lat)), ...
        sprintf('mean recovery: DQN %.1f%% | RULE %.1f%% | DQN better/equal/worse than RULE: %d / %d / %d', ...
            mean(recD, 'omitnan'), mean(recR, 'omitnan'), better, same, worse)};
end

%% =====================================================================
%% ===========================  KPI TAB LOADER  =========================
%% =====================================================================
function loadKpiTab(fig)
    data = fig.UserData; ui = data.ui; c = data.colors;
    R = 'results/';
    metrics = []; cl = []; far = []; sp = [];
    try
        if isfile([R 'eval_detector_metrics.mat'])
            M = load([R 'eval_detector_metrics.mat'], 'metrics'); metrics = M.metrics;
        end
        if isfile([R 'closed_loop_diagnostic_results.mat'])
            C = load([R 'closed_loop_diagnostic_results.mat'], 'results'); cl = C.results;
        end
        if isfile([R 'far_measurement.mat'])
            F = load([R 'far_measurement.mat'], 'results'); far = F.results;
        end
        if isfile([R 'speed_robustness.mat'])
            Sp = load([R 'speed_robustness.mat'], 'results'); sp = Sp.results;
        end
    catch ME
        appLog(fig, ['KPI load problem: ' ME.message]);
    end

    for k = 1:6, setCard(ui, k, 'N/A', 'result file missing', c.mut); end

    % ---- KPI cards ----
    if ~isempty(metrics)
        col = c.amber; if metrics.macro_f1_pct >= 90, col = c.green; end
        setCard(ui, 1, sprintf('%.1f%%', metrics.overall_accuracy_pct), ...
            sprintf('macro-F1 %.1f%%  |  target >= 90%%', metrics.macro_f1_pct), col);
    end
    if ~isempty(cl)
        isReal = ~ismember({cl.threat}, {'none','benign_interference'});
        setCard(ui, 2, sprintf('%.1f%%', mean([cl(isReal).recovery_pct], 'omitnan')), ...
            'mean BER recovery, real threats (closed loop)', c.accent);
        lat = [cl.cnn_latency_ms] + [cl.dqn_latency_ms];
        setCard(ui, 3, sprintf('%.1f ms', mean(lat)), ...
            sprintf('median %.1f ms | DQN-vs-rule agreement %.0f%%', median(lat), 100*mean([cl.agrees_with_rule])), c.accent);
        tn = unique({cl(isReal).threat}, 'stable'); nOK = 0;
        for k = 1:numel(tn)
            if mean([cl(strcmp({cl.threat}, tn{k})).recovery_pct], 'omitnan') >= 50, nOK = nOK + 1; end
        end
        col = c.red; v = 'NOT MET'; if nOK >= 1, col = c.green; v = 'MET'; end
        setCard(ui, 5, v, sprintf('%d / %d real threat classes recovered >= 50%%', nOK, numel(tn)), col);
    end
    if ~isempty(far)
        nfa = sum([far.false_alarm]); nall = numel(far); pct = 100 * nfa / nall;
        col = c.green; if pct > 5, col = c.red; end
        sub = sprintf('%d / %d trials', nfa, nall);
        if nfa == 0, sub = sprintf('0 / %d trials | 95%% upper bound %.1f%% (rule of three)', nall, 300 / nall); end
        setCard(ui, 4, sprintf('%.1f%%', pct), sub, col);
    end
    if ~isempty(sp)
        vs = unique([sp.speed_kmh]); accv = zeros(size(vs));
        for k = 1:numel(vs), accv(k) = 100 * mean([sp([sp.speed_kmh] == vs(k)).correct]); end
        col = c.amber; if min(accv) >= 90, col = c.green; end
        setCard(ui, 6, sprintf('%.1f%%', min(accv)), ...
            sprintf('worst-speed detection over %.0f-%.0f km/h', min(vs), max(vs)), col);
    end

    % ---- plots (each guarded, one failure never kills the tab) ----
    guardedPlot(@() plotConfusion(ui.kCm, metrics, c), ui.kCm, 'Confusion matrix', 'eval_detector_metrics.mat', c);
    guardedPlot(@() plotAccSnr(ui.kAcc, metrics, c), ui.kAcc, 'Accuracy vs Eb/N0', 'eval_detector_metrics.mat', c);
    guardedPlot(@() plotRecSnr(ui.kRec, cl, c), ui.kRec, 'Recovery vs Eb/N0', 'closed_loop_diagnostic_results.mat', c);
    guardedPlot(@() plotLatency(ui.kLat, cl, c), ui.kLat, 'Decision latency', 'closed_loop_diagnostic_results.mat', c);
    guardedPlot(@() plotActions(ui.kAct, cl, c), ui.kAct, 'Action per threat', 'closed_loop_diagnostic_results.mat', c);
    guardedPlot(@() plotSpeed(ui.kSpd, sp, metrics, c), ui.kSpd, 'Robustness vs UAV speed', ...
        'speed_robustness.mat (run eval_speed_robustness)', c);
end

function setCard(ui, k, val, sub, col)
    ui.kpiVal(k).Text = val; ui.kpiVal(k).FontColor = col; ui.kpiSub(k).Text = sub;
end

function guardedPlot(fn, ax, ttl, srcName, c)
    legend(ax, 'off'); cla(ax);
    ax.XTickMode = 'auto'; ax.YTickMode = 'auto'; ax.XLimMode = 'auto'; ax.YLimMode = 'auto';
    ax.XTickLabelMode = 'auto'; ax.YTickLabelMode = 'auto';
    try
        ok = fn();
        if ~ok, placeholderAx(ax, ttl, [srcName ' missing'], c); end
    catch ME
        placeholderAx(ax, ttl, ['could not draw: ' ME.message], c);
    end
end

function placeholderAx(ax, ttl, msg, c)
    legend(ax, 'off'); cla(ax);
    ax.XTick = []; ax.YTick = []; ax.XLim = [0 1]; ax.YLim = [0 1];
    text(ax, 0.5, 0.5, msg, 'Color', c.mut, 'HorizontalAlignment', 'center', 'FontSize', 11, ...
        'FontName', c.font, 'Interpreter', 'none');
    setTitle(ax, ttl, c);
end

function ok = plotConfusion(ax, metrics, c)
    ok = ~isempty(metrics) && isfield(metrics, 'conf_mat');
    if ~ok, return; end
    cm = metrics.conf_mat; cmn = cm ./ max(sum(cm, 2), 1); n = size(cm, 1);
    imagesc(ax, cmn, [0 1]);
    colormap(ax, [linspace(0.10, 0.30, 64)', linspace(0.12, 0.75, 64)', linspace(0.17, 1.00, 64)']);
    nm = cellfun(@(x) strrep(x, '_', ' '), metrics.classes(:)', 'UniformOutput', false);
    ax.XTick = 1:n; ax.XTickLabel = nm; ax.XTickLabelRotation = 45;
    ax.YTick = 1:n; ax.YTickLabel = nm; ax.FontSize = 8; ax.YDir = 'reverse';
    for i = 1:n
        for j = 1:n
            if cm(i, j) > 0
                text(ax, j, i, sprintf('%d', cm(i, j)), 'HorizontalAlignment', 'center', ...
                    'FontSize', 7, 'Color', 'w');
            end
        end
    end
    xlabel(ax, 'Predicted', 'Color', c.mut); ylabel(ax, 'True', 'Color', c.mut);
    setTitle(ax, 'Confusion matrix (test set)', c);
end

function ok = plotAccSnr(ax, metrics, c)
    ok = ~isempty(metrics) && isfield(metrics, 'snr_breakdown');
    if ~ok, return; end
    sb = metrics.snr_breakdown; snr = [sb.snr_db]; acc = [sb.accuracy_pct];
    hold(ax, 'on');
    plot(ax, snr, acc, '-o', 'LineWidth', 2, 'Color', c.accent, 'MarkerFaceColor', c.accent);
    yline(ax, 90, '--', 'Color', c.red, 'LineWidth', 1.2);
    hold(ax, 'off');
    ax.XTick = snr; ax.YLim = [max(0, floor(min(acc)/5)*5 - 5) 100]; grid(ax, 'on');
    xlabel(ax, 'Eb/N0 (dB)', 'Color', c.mut); ylabel(ax, 'Accuracy (%)', 'Color', c.mut);
    setTitle(ax, sprintf('Detection accuracy vs Eb/N0  (overall %.1f%%, red = 90%% target)', metrics.overall_accuracy_pct), c);
end

function ok = plotRecSnr(ax, cl, c)
    ok = ~isempty(cl); if ~ok, return; end
    threats = unique({cl.threat}, 'stable'); snr = unique([cl.snr_db]);
    realT = threats(~ismember(threats, {'none','benign_interference'}));
    hold(ax, 'on'); h = gobjects(0); nm = {};
    for t = 1:numel(realT)
        rec = nan(1, numel(snr));
        for s = 1:numel(snr)
            m = strcmp({cl.threat}, realT{t}) & [cl.snr_db] == snr(s);
            if any(m), rec(s) = cl(find(m, 1)).recovery_pct; end
        end
        h(end+1) = plot(ax, snr, rec, '-o', 'LineWidth', 1.5, 'MarkerSize', 4); %#ok<AGROW>
        nm{end+1} = strrep(realT{t}, '_', ' '); %#ok<AGROW>
    end
    hold(ax, 'off'); ax.XTick = snr; grid(ax, 'on');
    xlabel(ax, 'Eb/N0 (dB)', 'Color', c.mut); ylabel(ax, 'BER recovery (%)', 'Color', c.mut);
    legend(ax, h, nm, 'Location', 'southeast', 'TextColor', c.txt, 'Color', c.panelBg, 'EdgeColor', c.mut, 'FontSize', 8);
    setTitle(ax, 'Recovery vs Eb/N0 (real threats)', c);
end

function ok = plotLatency(ax, cl, c)
    ok = ~isempty(cl); if ~ok, return; end
    threats = unique({cl.threat}, 'stable');
    a = zeros(1, numel(threats)); b = a;
    for t = 1:numel(threats)
        m = strcmp({cl.threat}, threats{t});
        a(t) = mean([cl(m).cnn_latency_ms]); b(t) = mean([cl(m).dqn_latency_ms]);
    end
    bb = bar(ax, [a; b]', 'stacked'); bb(1).FaceColor = c.accent; bb(2).FaceColor = c.amber;
    ax.XTick = 1:numel(threats); ax.XTickLabel = strrep(threats, '_', ' '); ax.XTickLabelRotation = 40;
    ax.FontSize = 8; grid(ax, 'on'); ylabel(ax, 'ms', 'Color', c.mut);
    legend(ax, {'CNN path','DQN'}, 'TextColor', c.txt, 'Color', c.panelBg, 'EdgeColor', c.mut, 'FontSize', 8);
    setTitle(ax, sprintf('Decision latency (mean %.2f ms)', mean(a + b)), c);
end

function ok = plotActions(ax, cl, c)
    ok = ~isempty(cl); if ~ok, return; end
    threats = unique({cl.threat}, 'stable');
    acts = {'no_action','channel_switch','rate_reduce','freq_diversity','spatial_diversity'};
    counts = zeros(numel(threats), numel(acts));
    for t = 1:numel(threats)
        m = strcmp({cl.threat}, threats{t});
        for a = 1:numel(acts), counts(t, a) = sum(strcmp({cl(m).dqn_action}, acts{a})); end
    end
    bb = bar(ax, counts, 'stacked');
    pal = [0.45 0.48 0.55; c.accent; c.amber; c.green; c.purp];
    for a = 1:numel(acts), bb(a).FaceColor = pal(a, :); end
    ax.XTick = 1:numel(threats); ax.XTickLabel = strrep(threats, '_', ' '); ax.XTickLabelRotation = 40;
    ax.FontSize = 8; grid(ax, 'on'); ylabel(ax, 'runs', 'Color', c.mut);
    legend(ax, strrep(acts, '_', ' '), 'TextColor', c.txt, 'Color', c.panelBg, 'EdgeColor', c.mut, ...
        'FontSize', 7, 'Location', 'eastoutside');
    setTitle(ax, 'DQN countermeasure per threat', c);
end

function ok = plotSpeed(ax, sp, metrics, c)
    haveOff = ~isempty(metrics) && isfield(metrics, 'speed_breakdown') && ~isempty(metrics.speed_breakdown);
    ok = ~isempty(sp) || haveOff; if ~ok, return; end
    hold(ax, 'on'); h = gobjects(0); nm = {};
    if ~isempty(sp)
        vs = unique([sp.speed_kmh]); acc = zeros(size(vs)); rec = nan(size(vs));
        isReal = ~ismember({sp.threat}, {'none','benign_interference'});
        for k = 1:numel(vs)
            m = [sp.speed_kmh] == vs(k);
            acc(k) = 100 * mean([sp(m).correct]);
            rec(k) = mean([sp(m & isReal).recovery_pct], 'omitnan');
        end
        h(end+1) = plot(ax, vs, acc, '-o', 'LineWidth', 2, 'Color', c.accent, 'MarkerFaceColor', c.accent); %#ok<AGROW>
        nm{end+1} = 'closed-loop detection (%)'; %#ok<AGROW>
        h(end+1) = plot(ax, vs, rec, '-s', 'LineWidth', 1.8, 'Color', c.amber, 'MarkerFaceColor', c.amber); %#ok<AGROW>
        nm{end+1} = 'mean BER recovery (%)'; %#ok<AGROW>
    end
    if haveOff
        sb = metrics.speed_breakdown; mid = ([sb.speed_lo_kmh] + [sb.speed_hi_kmh]) / 2;
        h(end+1) = plot(ax, mid, [sb.accuracy_pct], '--^', 'LineWidth', 1.6, 'Color', c.green, 'MarkerFaceColor', c.green); %#ok<AGROW>
        nm{end+1} = 'offline test accuracy (%)'; %#ok<AGROW>
    end
    hold(ax, 'off'); grid(ax, 'on'); ax.YLim = [0 105];
    xlabel(ax, 'UAV speed (km/h)', 'Color', c.mut); ylabel(ax, '%', 'Color', c.mut);
    legend(ax, h, nm, 'Location', 'southeast', 'TextColor', c.txt, 'Color', c.panelBg, 'EdgeColor', c.mut, 'FontSize', 8);
    setTitle(ax, 'Robustness vs UAV speed (Doppler)', c);
end

%% =====================================================================
%% ======================  SURVIVABILITY TAB LOADER  ====================
%% =====================================================================
function updateSurvMap(fig)
    data = fig.UserData; env = data.env; ui = data.ui; c = data.colors;
    ax = ui.survAx; legend(ax, 'off'); cla(ax);
    if isempty(env.surv)
        placeholderAx(ax, 'Survivability map', 'data/survivability_boundary.mat missing - run map_survivability_boundary', c);
        ui.survSummary.Value = {'No survivability data.'};
        return;
    end
    ax.XTickMode = 'auto'; ax.YTickMode = 'auto';
    mapKey = ui.survMapDD.Value;
    gd = env.surv.(['grid_data_' mapKey]);
    tname = ui.survThreatDD.Value;
    gi = find(strcmp({gd.threat}, tname), 1);
    if isempty(gi), return; end
    g = gd(gi); snrPts = env.surv.SNR_points;
    nL = numel(g.levels); nS = numel(snrPts);

    pal = [0.10 0.12 0.16; c.green; c.amber; c.red];      % row 1 = no data, rows 2..4 = R / M / X
    img = zeros(nL, nS, 3);
    for i = 1:nL
        for j = 1:nS
            img(i, j, :) = pal(g.status(i, j) + 1, :);
        end
    end
    image(ax, img);
    ax.YDir = 'reverse'; ax.XLim = [0.5 nS + 0.5]; ax.YLim = [0.5 nL + 0.5];
    ax.XTick = 1:nS; ax.XTickLabel = compose('%g', snrPts);
    ax.YTick = 1:nL; ax.YTickLabel = compose('%g', g.levels);
    hold(ax, 'on');
    for i = 1:nL
        for j = 1:nS
            if ~isnan(g.ratio(i, j))
                text(ax, j, i, sprintf('%.1f', g.ratio(i, j)), 'HorizontalAlignment', 'center', ...
                    'Color', [0.05 0.05 0.08], 'FontWeight', 'bold', 'FontSize', 11, 'FontName', c.font);
            else
                text(ax, j, i, '-', 'HorizontalAlignment', 'center', 'Color', c.mut, 'FontSize', 11);
            end
        end
    end
    lr = getappdata(fig, 'lastRun');
    if ~isempty(lr) && strcmp(lr.threat, tname) && lr.level >= 1 && lr.level <= nL
        j = find(snrPts == lr.snr, 1);
        if ~isempty(j)
            plot(ax, j, lr.level, 'p', 'MarkerSize', 22, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', 'k', 'LineWidth', 1.2);
            text(ax, j, lr.level + 0.36, 'last live run', 'Color', 'w', 'FontSize', 9, ...
                'HorizontalAlignment', 'center', 'FontName', c.font);
        end
    end
    hold(ax, 'off');
    xlabel(ax, 'Eb/N0 (dB)', 'Color', c.mut); ylabel(ax, 'Severity level (low -> high)', 'Color', c.mut);
    if strcmp(mapKey, 'A'), mt = 'Map A - threat neutralization'; else, mt = 'Map B - link survivability'; end
    setTitle(ax, [mt ' : ' niceName(tname)], c);

    % ---- summary text ----
    stAll = [];
    for k = 1:numel(gd), stAll = [stAll; gd(k).status(:)]; end %#ok<AGROW>
    stAll = stAll(stAll > 0); st = g.status(g.status > 0);
    L = {sprintf('%s (all threats)', mt), ...
         sprintf('  states mapped : %d', numel(stAll)), ...
         sprintf('  recoverable   : %.1f%%', 100*mean(stAll == 1)), ...
         sprintf('  marginal      : %.1f%%', 100*mean(stAll == 2)), ...
         sprintf('  non-recover.  : %.1f%%', 100*mean(stAll == 3)), '', ...
         sprintf('%s only:', niceName(tname)), ...
         sprintf('  recoverable %d | marginal %d | non-rec. %d', sum(st == 1), sum(st == 2), sum(st == 3)), ''};
    gapLines = {};
    for k = 1:numel(env.surv.grid_data_A)
        a = env.surv.grid_data_A(k).status; b = env.surv.grid_data_B(k).status;
        [ri, ci] = find(a == 3 & (b == 1 | b == 2));
        for m = 1:numel(ri)
            gapLines{end+1} = sprintf('  %s: level %g @ %g dB', env.surv.grid_data_A(k).threat, ... %#ok<AGROW>
                env.surv.grid_data_A(k).levels(ri(m)), snrPts(ci(m)));
        end
    end
    L{end+1} = 'Gap cells (survive via margin/rate,';
    L{end+1} = 'threat NOT neutralized):';
    if isempty(gapLines), L{end+1} = '  none'; else, L = [L gapLines]; end
    ui.survSummary.Value = L(:);
end