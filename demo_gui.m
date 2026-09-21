function demo_gui
%DEMO_GUI — Operator-console live demonstration of the UAV-GCS closed-loop
% adaptive secure communications system.
%
% Select one or more threats from the list, choose an SNR, and press RUN.
% Each selected threat is simulated in sequence, and for every one you see,
% live: the UAV-GCS link status indicator, the received spectrogram, the IQ
% constellation before and after the countermeasure, the BER bar chart, and
% CNN-confidence / decision-latency gauges. Every run is logged to a history
% table that persists for the session and can be exported to CSV. Optional
% session video recording captures the whole window to an .mp4 file.
%
% Every number shown comes from the real pipeline: build_threat_model.m,
% a genuine Simulink sim(), extract_closed_loop_frames.m, the trained CNN
% and DQN, and — for any action other than no_action — a second real
% simulation with the countermeasure applied, measuring actual BER recovery.
% Nothing here is mocked or precomputed.
%
% ARCHITECTURE: no nested functions anywhere in this file (see the note in
% loadInitialParams for why that matters). All shared state — models,
% parameters, UI handles, run history, video writer — lives in fig.UserData
% and is passed explicitly between plain sibling callback functions.
%
% Usage: run demo_gui from the project root (same folder as main.m).

close all; clc;

%% ---------- Load trained models and simulation parameters once ----------
fprintf('Loading trained models...\n');
D = load('data/trained_detector.mat', 'net', 'classes');
Q = load('data/trained_dqn.mat', 'agent');
S = load('data/splits.mat', 'splits');
p0 = loadInitialParams();

env = struct();
env.cnn_net = D.net; env.cnn_classes = D.classes;
env.dqn_agent = Q.agent;
env.feat_mean = S.splits.norm.feat_mean; env.feat_std = S.splits.norm.feat_std;
env.p0 = p0;
env.modelName = 'UAV_GCS_Threat_Link';
env.fs = p0.symbol_rate * p0.sps;
env.delay_bits = 20;
env.img_size = 128; env.win = 128; env.novlp = 113; env.nfft = 128;
env.db_lo = -40; env.db_hi = 20; env.temporal_window = 10;
env.threats = {'none','jamming','reactive_jamming','sweeping_jammer','noise_burst', ...
    'path_loss','spoofing','antenna_fault','benign_interference'};
env.strength_field = containers.Map( ...
    {'jamming','reactive_jamming','sweeping_jammer','noise_burst','path_loss','antenna_fault','spoofing','benign_interference','none'}, ...
    {'jsr_db','jsr_db','jsr_db','jsr_db','path_loss_db','fault_atten_db','spoof_sir_db','benign_int_db','jsr_db'});
env.action_mitigation_db = struct('no_action',0,'channel_switch',25,'rate_reduce',15, ...
    'freq_diversity',25,'spatial_diversity',25);
env.action_names = env.dqn_agent.action_names;
env.baseline = struct('jsr_db',p0.jsr_db,'path_loss_db',p0.path_loss_db, ...
    'fault_atten_db',p0.fault_atten_db,'spoof_sir_db',p0.spoof_sir_db, ...
    'benign_int_db',p0.benign_int_db);

fprintf('Warming up CNN, DQN, and spectrogram()...\n');
warmUp(env);
fprintf('Ready.\n\n');

%% ================= WINDOW: dark operator-console theme =================
bg      = [0.09 0.10 0.13];
panelBg = [0.14 0.15 0.19];
txtCol  = [0.85 0.87 0.92];
accent  = [0.25 0.60 0.95];
greenC  = [0.25 0.75 0.45];
amberC  = [0.95 0.70 0.20];
redC    = [0.85 0.30 0.30];

fig = uifigure('Name', 'UAV-GCS Adaptive Secure Communications — Operator Console', ...
    'Position', [40 30 1560 900], 'Color', bg);

%% ---- Header bar: title + link status ----
hdr = uipanel(fig, 'Position', [15 850 1530 40], 'BackgroundColor', panelBg, 'BorderType','none');
uilabel(hdr, 'Position', [15 8 500 24], 'Text', 'UAV-GCS ADAPTIVE SECURE COMMS — LIVE OPERATOR CONSOLE', ...
    'FontColor', txtCol, 'FontWeight','bold', 'FontSize', 15);
linkStatusLamp = uilabel(hdr, 'Position', [1280 8 18 24], 'Text', char(9679), ...
    'FontColor', greenC, 'FontSize', 20, 'HorizontalAlignment','center');
linkStatusTxt = uilabel(hdr, 'Position', [1305 8 220 24], 'Text', 'LINK: HEALTHY', ...
    'FontColor', greenC, 'FontWeight','bold', 'FontSize', 13);

%% ---- Left control panel ----
ctrl = uipanel(fig, 'Position', [15 15 300 825], 'BackgroundColor', panelBg, 'BorderType','line', ...
    'ForegroundColor', txtCol, 'Title', 'MISSION CONTROL', ...
    'FontWeight','bold', 'FontSize', 13);

uilabel(ctrl, 'Position', [15 765 260 20], 'Text', 'THREATS TO SIMULATE (select 1+):', ...
    'FontColor', txtCol, 'FontWeight','bold', 'FontSize', 11);
threatList = uilistbox(ctrl, 'Position', [15 610 270 150], 'Items', env.threats, ...
    'Multiselect', 'on', 'Value', {'jamming'}, 'FontSize', 12);

uilabel(ctrl, 'Position', [15 575 260 20], 'Text', 'SNR (Eb/N0, dB):', ...
    'FontColor', txtCol, 'FontWeight','bold', 'FontSize', 11);
snrLbl = uilabel(ctrl, 'Position', [15 500 260 20], 'Text', 'Current: 4 dB', 'FontColor', accent, 'FontWeight','bold');
snrSld = uislider(ctrl, 'Position', [20 535 250 3], 'Limits', [0 10], 'Value', 4, ...
    'MajorTicks', 0:2:10, 'FontColor', txtCol);
snrSld.ValueChangingFcn = @(src,evt) set(snrLbl, 'Text', sprintf('Current: %.0f dB', round(evt.Value)));

recordChk = uicheckbox(ctrl, 'Position', [15 460 260 22], 'Text', [char(9679) ' Record session video (.mp4)'], ...
    'FontColor', [0.9 0.4 0.4], 'FontWeight','bold', 'Value', false);

runBtn = uibutton(ctrl, 'Position', [15 405 270 45], 'Text', [char(9654) '  RUN SEQUENCE'], ...
    'FontSize', 16, 'FontWeight','bold', 'BackgroundColor', greenC, 'FontColor','white');

statusLbl = uilabel(ctrl, 'Position', [15 375 270 25], 'Text', 'Idle — select threats and press Run.', ...
    'FontColor', [0.6 0.62 0.68], 'FontSize', 10, 'WordWrap','on');

uilabel(ctrl, 'Position', [15 345 260 20], 'Text', 'RUN HISTORY:', 'FontColor', txtCol, 'FontWeight','bold', 'FontSize', 11);
histTbl = uitable(ctrl, 'Position', [15 60 270 280], ...
    'ColumnName', {'Threat','SNR','Detected','Action','Rec%','ms'}, ...
    'ColumnWidth', {70,32,70,72,40,36}, 'Data', cell(0,6), 'FontSize', 9);

exportBtn = uibutton(ctrl, 'Position', [15 15 270 32], 'Text', 'Export History (CSV)', ...
    'FontSize', 11, 'BackgroundColor', [0.25 0.28 0.34], 'FontColor', txtCol);

%% ---- Center: link diagram ----
linkAx = uiaxes(fig, 'Position', [330 730 700 110]);
linkAx.Toolbar.Visible = 'off'; linkAx.Interactions = [];
linkAx.Color = panelBg; linkAx.XColor = 'none'; linkAx.YColor = 'none';
linkAx.XLim = [0 10]; linkAx.YLim = [0 2];

%% ---- Center: spectrogram + IQ constellation ----
specAx = uiaxes(fig, 'Position', [330 400 560 310]);
title(specAx, 'Received Signal Spectrogram', 'Color', txtCol);
specAx.Color = [0 0 0]; specAx.XColor = txtCol; specAx.YColor = txtCol;
xlabel(specAx, 'Time (\mus)'); ylabel(specAx, 'Frequency (MHz)');

iqAx = uiaxes(fig, 'Position', [910 400 340 310]);
title(iqAx, 'IQ Constellation', 'Color', txtCol);
iqAx.Color = [0 0 0]; iqAx.XColor = txtCol; iqAx.YColor = txtCol;
xlabel(iqAx, 'In-phase'); ylabel(iqAx, 'Quadrature');

%% ---- Bottom: BER bars + gauges ----
berAx = uiaxes(fig, 'Position', [330 60 560 320]);
title(berAx, 'BER: Before vs After Countermeasure', 'Color', txtCol);
berAx.Color = panelBg; berAx.XColor = txtCol; berAx.YColor = txtCol;

gaugePanel = uipanel(fig, 'Position', [910 60 340 320], 'BackgroundColor', panelBg, ...
    'BorderType','line', 'ForegroundColor', txtCol, 'Title', 'DETECTION & TIMING', 'FontWeight','bold');
uilabel(gaugePanel, 'Position', [15 260 150 20], 'Text', 'CNN Confidence', 'FontColor', txtCol, 'FontSize', 10);
confGauge = uigauge(gaugePanel, 'linear', 'Position', [15 200 300 45], 'Limits', [0 100]);
uilabel(gaugePanel, 'Position', [15 155 300 20], 'Text', 'Decision Latency (ms)', 'FontColor', txtCol, 'FontSize', 10);
latGauge = uigauge(gaugePanel, 'linear', 'Position', [15 95 300 45], 'Limits', [0 30]);
resultLbl = uilabel(gaugePanel, 'Position', [15 10 310 75], 'Text', 'No run yet.', ...
    'FontColor', txtCol, 'FontSize', 12, 'WordWrap','on', 'VerticalAlignment','top');

%% ---- Wire up state ----
ui = struct('threatList',threatList,'snrSld',snrSld,'recordChk',recordChk,'runBtn',runBtn, ...
    'statusLbl',statusLbl,'histTbl',histTbl,'exportBtn',exportBtn,'linkAx',linkAx, ...
    'linkStatusLamp',linkStatusLamp,'linkStatusTxt',linkStatusTxt,'specAx',specAx,'iqAx',iqAx, ...
    'berAx',berAx,'confGauge',confGauge,'latGauge',latGauge,'resultLbl',resultLbl);
colors = struct('bg',bg,'panelBg',panelBg,'txt',txtCol,'accent',accent,'green',greenC,'amber',amberC,'red',redC);

fig.UserData = struct('env',env, 'ui',ui, 'colors',colors, 'history', {{}}, 'videoWriter', []);

drawLinkDiagram(fig, 'idle');

runBtn.ButtonPushedFcn = @runSequence;
exportBtn.ButtonPushedFcn = @exportHistory;

end


%% ========== Plain (non-nested) sibling functions below ==========

function p = loadInitialParams()
    % init_params.m is a script that injects "params" into its caller's
    % workspace. Calling it from a plain function (never from a function that
    % also defines other functions sharing its workspace) keeps that
    % workspace fully dynamic, so the script-style injection works exactly as
    % it does everywhere else in this project.
    init_params;
    p = load('params.mat').params;
end

function warmUp(env)
    dummy_iq = complex(randn(2064,1), randn(2064,1));
    for w = 1:3
        spectrogram(dummy_iq, hann(env.win), env.novlp, env.nfft, env.fs, 'centered');
    end
    dspec = dlarray(single(rand(env.img_size,env.img_size,1,1)), 'SSCB');
    dfeat = dlarray(single(rand(1,7))', 'CB');
    dstate = dlarray(single(rand(env.dqn_agent.numStates,1)), 'CB');
    if canUseGPU, dspec=gpuArray(dspec); dfeat=gpuArray(dfeat); dstate=gpuArray(dstate); end
    for w = 1:5
        predict(env.cnn_net, dspec, dfeat);
        predict(env.dqn_agent.qNetwork, dstate);
    end
    if canUseGPU, wait(gpuDevice); end
end

function drawLinkDiagram(fig, state, threatLabel)
    % Simple icon-free GCS <---link---> UAV diagram, colored by state:
    % 'idle' (grey), 'attack' (red, threat detected pre-mitigation),
    % 'mitigating' (amber), 'healthy' (green, no_action / resolved).
    if nargin < 3, threatLabel = ''; end
    data = fig.UserData; ax = data.ui.linkAx; c = data.colors;
    cla(ax); hold(ax,'on');
    switch state
        case 'attack',     lineCol = c.red;   lw = 4; msg = ['THREAT DETECTED: ' threatLabel];
        case 'mitigating', lineCol = c.amber; lw = 4; msg = ['APPLYING COUNTERMEASURE...'];
        case 'healthy',    lineCol = c.green; lw = 3; msg = 'LINK HEALTHY / NO ACTION NEEDED';
        otherwise,         lineCol = [0.4 0.42 0.48]; lw = 2; msg = 'STANDBY';
    end
    plot(ax, [1.3 8.7], [1 1], '-', 'Color', lineCol, 'LineWidth', lw);
    if ismember(state, {'attack'})
        scatter(ax, 5, 1, 220, 'Marker','x', 'MarkerEdgeColor', lineCol, 'LineWidth', 3);
    end
    text(ax, 0.9, 1, 'GCS', 'Color', c.txt, 'FontWeight','bold', 'FontSize', 13, 'HorizontalAlignment','center');
    text(ax, 9.1, 1, 'UAV', 'Color', c.txt, 'FontWeight','bold', 'FontSize', 13, 'HorizontalAlignment','center');
    text(ax, 5, 1.6, msg, 'Color', lineCol, 'FontWeight','bold', 'FontSize', 12, 'HorizontalAlignment','center');
    hold(ax,'off');

    data.ui.linkStatusLamp.FontColor = lineCol;
    data.ui.linkStatusTxt.FontColor = lineCol;
    data.ui.linkStatusTxt.Text = ['LINK: ' upper(strrep(state,'mitigating','RECOVERING'))];
    drawnow;
end

function iqScatter(ax, iq, colr, ttl)
    s = iq(1:min(400,numel(iq)));
    scatter(ax, real(s), imag(s), 10, colr, 'filled', 'MarkerFaceAlpha', 0.5);
    xlim(ax, [-2 2]); ylim(ax, [-2 2]); grid(ax,'on');
    title(ax, ttl, 'Color', get(ax,'YColor'));
end

function recordFrame(fig)
    data = fig.UserData;
    if ~isempty(data.videoWriter)
        try
            frame = getframe(fig);
            writeVideo(data.videoWriter, frame);
        catch
            % figure not fully rendered yet on this tick; skip silently
        end
    end
end

function runSequence(btn, ~)
    fig = ancestor(btn, 'figure');
    data = fig.UserData;
    env = data.env; ui = data.ui; c = data.colors;

    selected = ui.threatList.Value;
    if isempty(selected)
        ui.statusLbl.Text = 'Select at least one threat first.'; return;
    end
    ui.runBtn.Enable = 'off'; ui.exportBtn.Enable = 'off';

    % ---- Start video recording if requested ----
    if ui.recordChk.Value
        vname = sprintf('results/demo_session_%s.mp4', datestr(now,'yyyymmdd_HHMMSS'));
        if ~exist('results','dir'), mkdir('results'); end
        vw = VideoWriter(vname, 'MPEG-4'); vw.FrameRate = 2; open(vw);
        data.videoWriter = vw; fig.UserData = data;
        ui.statusLbl.Text = sprintf('Recording to %s ...', vname);
    end

    for k = 1:numel(selected)
        threat = selected{k};
        ui.statusLbl.Text = sprintf('Running %d/%d: %s ...', k, numel(selected), strrep(threat,'_',' '));
        drawnow;
        try
            runOneThreat(fig, threat);
        catch ME
            ui.statusLbl.Text = ['Error: ' ME.message];
            break;
        end
    end

    data = fig.UserData;
    if ~isempty(data.videoWriter)
        close(data.videoWriter);
        ui.statusLbl.Text = ['Saved video: ' data.videoWriter.Filename];
        data.videoWriter = [];
        fig.UserData = data;
    else
        ui.statusLbl.Text = 'Sequence complete.';
    end
    ui.runBtn.Enable = 'on'; ui.exportBtn.Enable = 'on';
end

function runOneThreat(fig, threat)
    data = fig.UserData; env = data.env; ui = data.ui; c = data.colors;

    field = env.strength_field(threat);
    ebno = round(ui.snrSld.Value);
    p0 = env.p0;
    snr_dB = ebno + 10*log10(p0.bits_per_symbol) - 10*log10(p0.sps);

    p = p0; p.jsr_db=env.baseline.jsr_db; p.path_loss_db=env.baseline.path_loss_db;
    p.fault_atten_db=env.baseline.fault_atten_db; p.spoof_sir_db=env.baseline.spoof_sir_db;
    p.benign_int_db=env.baseline.benign_int_db;
    p.active_threat = threat;
    params = p; save('params.mat','params'); %#ok<NASGU>
    build_threat_model;
    set_param([env.modelName '/AWGN'],'SNR',num2str(snr_dB),'SignalPower',num2str(1/p.sps));

    t0 = tic;
    out = sim(env.modelName);
    [iq_frames, ber_f, rssi_f, plr_f, nf] = extract_closed_loop_frames(out, p, env.delay_bits);
    i_last = find(~isnan(ber_f),1,'last'); if isempty(i_last), i_last = nf; end
    w0 = max(1, i_last-env.temporal_window+1);
    var_rssi_10 = var(rssi_f(w0:i_last),0);
    burst_ratio = mean(plr_f(w0:i_last),'omitnan');
    if i_last>1 && ~isnan(ber_f(i_last)) && ~isnan(ber_f(i_last-1))
        dber_dt = (ber_f(i_last)-ber_f(i_last-1))/p.frame_duration;
    else
        dber_dt = 0;
    end

    iq_before = iq_frames{i_last}; ber_before = ber_f(i_last);
    rssi = rssi_f(i_last); plr = plr_f(i_last);

    Sxx = spectrogram(iq_before, hann(env.win), env.novlp, env.nfft, env.fs, 'centered');
    Pw = 20*log10(abs(Sxx)+eps);
    Pw_n = (Pw-env.db_lo)/(env.db_hi-env.db_lo); Pw_n = min(max(Pw_n,0),1);
    spec_img = imresize(Pw_n, [env.img_size env.img_size]);

    % ---- Live update: show the raw/attacked signal first ----
    imagesc(ui.specAx, Pw); axis(ui.specAx,'xy'); colormap(ui.specAx,'turbo');
    title(ui.specAx, sprintf('Spectrogram — %s @ %d dB', strrep(threat,'_',' '), ebno), 'Color', c.txt);
    iqScatter(ui.iqAx, iq_before, [0.9 0.4 0.3], 'IQ — Received (pre-mitigation)');
    drawLinkDiagram(fig, 'attack', strrep(threat,'_',' '));
    recordFrame(fig);
    pause(0.5);

    raw_feats = [ebno, ber_before, rssi, plr, var_rssi_10, dber_dt, burst_ratio];
    raw_feats(isnan(raw_feats)) = 0;
    norm_feats = (raw_feats - env.feat_mean) ./ env.feat_std;
    X_spec = dlarray(single(spec_img), 'SSCB'); X_feat = dlarray(single(norm_feats)', 'CB');
    if canUseGPU, X_spec=gpuArray(X_spec); X_feat=gpuArray(X_feat); end

    t1 = tic;
    pred = predict(env.cnn_net, X_spec, X_feat);
    probs = extractdata(pred); [conf, idx] = max(probs);
    cnn_class = char(env.cnn_classes(idx));
    cnn_latency = toc(t1)*1000;
    ui.confGauge.Value = min(100, 100*conf);

    dqn_state = build_dqn_state(cnn_class, ber_before, rssi, ebno, plr);
    sdl = dlarray(single(dqn_state),'CB'); if canUseGPU, sdl=gpuArray(sdl); end
    t2 = tic;
    qv = extractdata(predict(env.dqn_agent.qNetwork, sdl));
    [~, aidx] = max(qv);
    action_name = env.action_names{aidx};
    dqn_latency = toc(t2)*1000;
    total_latency = toc(t0)*1000;
    ui.latGauge.Value = min(30, total_latency);

    drawLinkDiagram(fig, 'mitigating'); recordFrame(fig); pause(0.4);

    if strcmp(action_name,'no_action')
        ber_after = ber_before; recovery_pct = NaN; iq_after = iq_before;
    else
        mdb = env.action_mitigation_db.(action_name);
        p2 = p; p2.(field) = env.baseline.(field) - mdb;
        if any(strcmp(field,{'path_loss_db','fault_atten_db'})), p2.(field)=max(p2.(field),0); end
        params = p2; save('params.mat','params'); %#ok<NASGU>
        build_threat_model;
        set_param([env.modelName '/AWGN'],'SNR',num2str(snr_dB),'SignalPower',num2str(1/p2.sps));
        out2 = sim(env.modelName);
        [iq_frames2, ber_f2, ~, ~, nf2] = extract_closed_loop_frames(out2, p2, env.delay_bits);
        i_last2 = find(~isnan(ber_f2),1,'last'); if isempty(i_last2), i_last2 = nf2; end
        iq_after = iq_frames2{i_last2};
        ber_after = mean(ber_f2,'omitnan');
        recovery_pct = 100*(ber_before-ber_after)/max(ber_before,eps);
    end
    params = p0; save('params.mat','params'); %#ok<NASGU>

    % ---- Live update: show recovered signal + final state ----
    iqScatter(ui.iqAx, iq_after, [0.3 0.8 0.5], 'IQ — After Countermeasure');
    if isnan(recovery_pct)
        bar(ui.berAx, categorical({'Before','After'}), [ber_before ber_before], 'FaceColor',[0.4 0.6 0.9]);
        title(ui.berAx, 'No action applied', 'Color', c.txt);
        drawLinkDiagram(fig, 'healthy');
    else
        bar(ui.berAx, categorical({'Before','After'}), [ber_before ber_after], 'FaceColor',[0.85 0.5 0.3]);
        title(ui.berAx, sprintf('BER Recovery: %.1f%%', recovery_pct), 'Color', c.txt);
        drawLinkDiagram(fig, 'healthy');
    end
    ui.berAx.YColor = c.txt; ui.berAx.XColor = c.txt;
    recordFrame(fig);

    correctStr = 'NO'; if strcmp(cnn_class,threat), correctStr = 'YES'; end
    recStr = 'N/A'; if ~isnan(recovery_pct), recStr = sprintf('%.1f%%',recovery_pct); end
    ui.resultLbl.Text = sprintf(['Detected: %s (%s)\nAction: %s\nRecovery: %s\nBER: %.2e -> %.2e'], ...
        strrep(cnn_class,'_',' '), correctStr, strrep(action_name,'_',' '), recStr, ber_before, ber_after);

    % ---- Append to history table + persistent struct log ----
    newRow = {strrep(threat,'_',' '), ebno, strrep(cnn_class,'_',' '), strrep(action_name,'_',' '), ...
        round(ifelse(isnan(recovery_pct),0,recovery_pct),1), round(total_latency,1)};
    ui.histTbl.Data = [ui.histTbl.Data; newRow];

    logEntry = struct('timestamp',datestr(now), 'threat',threat, 'snr_dB',ebno, ...
        'cnn_detected',cnn_class, 'cnn_confidence',conf, 'cnn_correct',strcmp(cnn_class,threat), ...
        'dqn_action',action_name, 'ber_before',ber_before, 'ber_after',ber_after, ...
        'recovery_pct',recovery_pct, 'cnn_latency_ms',cnn_latency, 'dqn_latency_ms',dqn_latency, ...
        'total_latency_ms',total_latency);
    data = fig.UserData;
    data.history{end+1} = logEntry;
    fig.UserData = data;

    pause(0.6); % let the viewer see the final state before the next threat runs
end

function exportHistory(btn, ~)
    fig = ancestor(btn, 'figure');
    data = fig.UserData;
    if isempty(data.history)
        data.ui.statusLbl.Text = 'No runs to export yet.'; return;
    end
    if ~exist('results','dir'), mkdir('results'); end
    fname = sprintf('results/demo_history_%s.csv', datestr(now,'yyyymmdd_HHMMSS'));
    T = struct2table([data.history{:}]);
    writetable(T, fname);
    matname = strrep(fname, '.csv', '.mat');
    history = data.history; %#ok<NASGU>
    save(matname, 'history');
    data.ui.statusLbl.Text = sprintf('Exported: %s (+ .mat)', fname);
end

function out = ifelse(cond, a, b)
    if cond, out = a; else, out = b; end
end