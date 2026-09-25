%% MAP_SURVIVABILITY_BOUNDARY — proposal deliverable #7 (primary research output)
% Maps, per threat, where an attack is recoverable versus non-recoverable over
% attack severity level and Eb/N0, using the system's REAL action set applied
% through apply_countermeasure.m (D28, D30). Every (threat, level, Eb/N0) cell
% is simulated with every action; a cell is classified by the best achievable
% BER relative to the clean link at the same Eb/N0.
%
%   Map A (without goodput loss) — channel_switch, freq_diversity, spatial_diversity,
%                                  power_control and their pairs
%   Map B (any action)           — every action of the agent, incl. rate_reduce and fec_interleave
%
% Gap cells (Map B recoverable/marginal, Map A non-recoverable) are the regime
% where the link survives only by trading throughput — the goodput trade-off
% named in the proposal. Each cell also records WHICH action achieves the best
% link, so the map shows both whether and how an attack can be survived.
%
% Output: results/survivability_boundary_mapA.txt, results/survivability_boundary_mapB.txt,
%         results/survivability_gap_analysis.txt, results/survivability_map_neutralization.png (Map A),
%         results/survivability_map_link.png (Map B), data/survivability_boundary.mat

close all; clc;
fprintf('=== Survivability Boundary Mapping (proposal deliverable #7, real action set) ===\n\n');

%% ========== CONFIG ==========
N_BASELINE_REPEATS = 5;
RATIO_RECOVERABLE  = 2;
RATIO_MARGINAL     = 5;
delay_bits = 20;

% Action set of the agent (dqn_agent.m, D39); Map A keeps the actions without
% goodput loss, Map B takes every action
evalc('agent0 = dqn_agent();');
ACTIONS = agent0.action_names;
p_ref = load_params_quiet();
MECH_B = ACTIONS(~strcmp(ACTIONS, 'no_action'));
MECH_A = MECH_B(cellfun(@(a) no_goodput_loss(p_ref, a), MECH_B));
ACT_CODE = containers.Map(MECH_B, cellfun(@act_code, MECH_B, 'UniformOutput', false));

% Severity levels per threat -- identical to run_dataset_sweep.m (A5) and the GUI
clear threat_cfg                                  % scripts share the base workspace
threat_cfg(1) = struct('name','jamming',             'level_field','jsr_db',        'levels',[0 4 8 12 16]);
threat_cfg(2) = struct('name','noise_burst',         'level_field','jsr_db',        'levels',[0 4 8 12 16]);
threat_cfg(3) = struct('name','reactive_jamming',    'level_field','jsr_db',        'levels',[0 4 8 12 16]);
threat_cfg(4) = struct('name','path_loss',           'level_field','path_loss_db',  'levels',[4 8 12 16 20]);
threat_cfg(5) = struct('name','spoofing',            'level_field','spoof_sir_db',  'levels',[-4 -1 2 5 8]);
threat_cfg(6) = struct('name','antenna_fault',       'level_field','fault_duty',    'levels',[0.1 0.2 0.3 0.4 0.5]);
threat_cfg(7) = struct('name','sweeping_jammer',     'level_field','jsr_db',        'levels',[0 4 8 12 16]);
threat_cfg(8) = struct('name','benign_interference', 'level_field','benign_int_db', 'levels',[-10 -8 -6 -4 -2]);

init_params;
p0 = load('params.mat').params;
modelName  = 'UAV_GCS_Threat_Link';
SNR_points = p0.EbNo_dB;
nS = numel(SNR_points);
t0 = tic;

%% ========== 1. Clean-link baseline per Eb/N0 ==========
fprintf('Measuring the clean link (none), %d repeats per Eb/N0...\n', N_BASELINE_REPEATS);
ber_clean = zeros(1, nS);
p = p0; p.active_threat = 'none';
params = p; save('params.mat','params');
evalc('build_threat_model');
for s = 1:nS
    set_param([modelName '/AWGN'], 'SNR', num2str(ebno2snr(SNR_points(s), p0)), 'SignalPower', num2str(1/p0.sps));
    reps = zeros(1, N_BASELINE_REPEATS);
    for r = 1:N_BASELINE_REPEATS
        out = sim(modelName);
        [~, ber_f] = extract_closed_loop_frames(out, p, delay_bits);
        reps(r) = mean(ber_f, 'omitnan');
    end
    ber_clean(s) = mean(reps);
    fprintf('  Eb/N0=%2g dB: clean BER = %.4e (std %.2e)\n', SNR_points(s), ber_clean(s), std(reps));
end
fprintf('\n');

%% ========== 2. Every threat x level x action x Eb/N0 ==========
nT = numel(threat_cfg); nAct = numel(ACTIONS);
ber_all = cell(1, nT);                 % {t}(level, action, snr)
for t = 1:nT
    cfg = threat_cfg(t);
    nL = numel(cfg.levels);
    B = nan(nL, nAct, nS);
    for li = 1:nL
        p = p0; p.active_threat = cfg.name; p.(cfg.level_field) = cfg.levels(li);
        for a = 1:nAct
            [p2, g_db] = apply_countermeasure(p, cfg.name, ACTIONS{a});
            params = p2; save('params.mat','params');
            evalc('build_threat_model');
            for s = 1:nS
                set_param([modelName '/AWGN'], 'SNR', num2str(ebno2snr(SNR_points(s), p2) + g_db), ...
                    'SignalPower', num2str(1/p2.sps));
                out = sim(modelName);
                [~, ber_f] = extract_closed_loop_frames(out, p2, delay_bits);
                B(li, a, s) = mean(ber_f, 'omitnan');
            end
        end
    end
    ber_all{t} = B;
    fprintf('  [%d/%d] %-20s mapped (%.1f min)\n', t, nT, cfg.name, toc(t0)/60);
end
params = p0; save('params.mat','params');
fprintf('\n');

%% ========== 3. Build both maps ==========
fprintf('Classifying (ratio to clean link): recoverable <= %gx, marginal <= %gx\n\n', ...
    RATIO_RECOVERABLE, RATIO_MARGINAL);
grid_data_A = build_map(ber_all, threat_cfg, ACTIONS, MECH_A, ber_clean, RATIO_RECOVERABLE, RATIO_MARGINAL);
grid_data_B = build_map(ber_all, threat_cfg, ACTIONS, MECH_B, ber_clean, RATIO_RECOVERABLE, RATIO_MARGINAL);

%% ========== 4. Reports ==========
if ~exist('results','dir'), mkdir('results'); end
report_A = build_report(grid_data_A, ber_clean, SNR_points, RATIO_RECOVERABLE, RATIO_MARGINAL, ...
    'MAP A — WITHOUT GOODPUT LOSS', MECH_A, ACT_CODE);
write_report(report_A, 'results/survivability_boundary_mapA.txt');
report_B = build_report(grid_data_B, ber_clean, SNR_points, RATIO_RECOVERABLE, RATIO_MARGINAL, ...
    'MAP B — ANY ACTION (incl. rate reduction and FEC)', MECH_B, ACT_CODE);
write_report(report_B, 'results/survivability_boundary_mapB.txt');
fprintf('\n--- MAP A (without goodput loss) ---\n');  fprintf('%s\n', report_A{:});
fprintf('\n--- MAP B (any action) ---\n');             fprintf('%s\n', report_B{:});

%% ========== 5. Gap analysis ==========
gap_report = {};
gap_report{end+1} = '=== SURVIVABILITY GAP ANALYSIS ===';
gap_report{end+1} = 'Cells where the link survives only with a goodput cost (Map B: recoverable/marginal)';
gap_report{end+1} = 'but not with any goodput-free action (Map A: non-recoverable): survival bought';
gap_report{end+1} = 'with throughput -- the goodput trade-off named in the proposal.';
gap_report{end+1} = '';
n_gap_total = 0;
for t = 1:nT
    gA = grid_data_A(t); gB = grid_data_B(t);
    gap_mask = (gB.status >= 1 & gB.status <= 2) & (gA.status == 3);
    n_gap = sum(gap_mask(:));
    n_gap_total = n_gap_total + n_gap;
    if n_gap == 0, continue; end
    gap_report{end+1} = sprintf('%s: %d gap cell(s)', gA.threat, n_gap); %#ok<SAGROW>
    [li_idx, s_idx] = find(gap_mask);
    for k = 1:numel(li_idx)
        li = li_idx(k); s = s_idx(k);
        gap_report{end+1} = sprintf('  level=%g, Eb/N0=%gdB: Map A %.2fx (%s) | Map B %.2fx (%s)', ...
            gA.levels(li), SNR_points(s), gA.ratio(li,s), gA.best_action{li,s}, ...
            gB.ratio(li,s), gB.best_action{li,s}); %#ok<SAGROW>
    end
end
gap_report{end+1} = '';
gap_report{end+1} = sprintf('Total gap cells: %d', n_gap_total);
write_report(gap_report, 'results/survivability_gap_analysis.txt');
fprintf('\n--- GAP ANALYSIS ---\n'); fprintf('%s\n', gap_report{:});

if ~exist('data','dir'), mkdir('data'); end
save('data/survivability_boundary.mat','grid_data_A','grid_data_B','ber_clean', ...
    'SNR_points','RATIO_RECOVERABLE','RATIO_MARGINAL','MECH_A','MECH_B','ber_all','threat_cfg','ACTIONS');

%% ========== 6. Figures ==========
draw_map(grid_data_A, SNR_points, RATIO_RECOVERABLE, RATIO_MARGINAL, ...
    'Map A: without goodput loss (C, F, S, power control and their pairs)', ...
    'results/survivability_map_neutralization.png');
draw_map(grid_data_B, SNR_points, RATIO_RECOVERABLE, RATIO_MARGINAL, ...
    'Map B: any action (incl. rate reduction and FEC)', ...
    'results/survivability_map_link.png');
fprintf('\nSaved results/survivability_boundary_mapA.txt, mapB.txt, gap_analysis.txt, two PNG maps\n');
fprintf('Saved data/survivability_boundary.mat (%.1f min)\n\n=== Survivability Mapping Complete ===\n', toc(t0)/60);


%% ========== LOCAL FUNCTIONS ==========

function tf = no_goodput_loss(p, a)
    [~, ~, cm] = apply_countermeasure(p, 'none', a);
    tf = cm.goodput_factor == 1;
end

function c = act_code(a)
    parts = strsplit(a, '+');
    m = containers.Map({'channel_switch','freq_diversity','spatial_diversity','rate_reduce','power_control','fec_interleave'}, ...
        {'C','F','S','R','P','E'});
    c = strjoin(cellfun(@(x) m(x), parts, 'UniformOutput', false), '');
end

function p = load_params_quiet()
    evalc('init_params');
    p = load('params.mat').params;
end

function snr = ebno2snr(ebno, p)
    snr = ebno + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
end

function grid_data = build_map(ber_all, threat_cfg, ACTIONS, act_set, ber_clean, RATIO_RECOVERABLE, RATIO_MARGINAL)
    nS = numel(ber_clean);
    cols = find(ismember(ACTIONS, act_set));
    grid_data = struct('threat',{},'levels',{},'ber_best',{},'ratio',{}, ...
        'status',{},'ber_attacked',{},'best_action',{});
    for t = 1:numel(threat_cfg)
        B = ber_all{t};
        levels = threat_cfg(t).levels;
        nL = numel(levels);
        ber_best = nan(nL, nS); ratio = nan(nL, nS); status = zeros(nL, nS);
        best_action = cell(nL, nS);
        ber_attacked = squeeze(B(:, 1, :));
        if nL == 1, ber_attacked = ber_attacked(:)'; end
        for li = 1:nL
            for s = 1:nS
                [ber_best(li,s), k] = min(B(li, cols, s));
                best_action{li,s} = ACTIONS{cols(k)};
                ratio(li,s) = ber_best(li,s) / max(ber_clean(s), eps);
                if ratio(li,s) <= RATIO_RECOVERABLE,  status(li,s) = 1;
                elseif ratio(li,s) <= RATIO_MARGINAL, status(li,s) = 2;
                else,                                 status(li,s) = 3;
                end
            end
        end
        grid_data(end+1) = struct('threat',threat_cfg(t).name,'levels',levels, ...
            'ber_best',ber_best,'ratio',ratio,'status',status, ...
            'ber_attacked',ber_attacked,'best_action',{best_action}); %#ok<AGROW>
    end
end

function report = build_report(grid_data, ber_clean, SNR_points, RATIO_RECOVERABLE, ...
    RATIO_MARGINAL, title_str, act_set, ACT_CODE)
    nT = numel(grid_data);
    nS = numel(SNR_points);
    report = {};
    report{end+1} = sprintf('=== SURVIVABILITY BOUNDARY MAP — %s ===', title_str);
    report{end+1} = sprintf('Generated: %s', datestr(now));
    report{end+1} = sprintf('Actions included: %s (apply_countermeasure.m, D28/D39)', strjoin(act_set, ', '));
    report{end+1} = '';
    report{end+1} = 'A state is classified by the best post-countermeasure BER relative to the clean link:';
    report{end+1} = sprintf('  RECOVERABLE (R) : within %gx | MARGINAL (M) : within %gx | NON-RECOVERABLE (X) : worse', ...
        RATIO_RECOVERABLE, RATIO_MARGINAL);
    report{end+1} = 'Letters after the status = action achieving it: C channel_switch, F freq_diversity, S spatial_diversity, R rate_reduce, P power_control, E fec_interleave (two letters = pair).';
    report{end+1} = '';
    report{end+1} = 'Clean-link reference BER per Eb/N0:';
    for s = 1:nS
        report{end+1} = sprintf('  %2g dB : %.4e', SNR_points(s), ber_clean(s)); %#ok<AGROW>
    end
    report{end+1} = '';
    report{end+1} = '--- Boundary map, per threat (rows = severity level, cols = Eb/N0) ---';
    for t = 1:nT
        g = grid_data(t);
        report{end+1} = sprintf('%s:', g.threat); %#ok<AGROW>
        hdr = sprintf('  %-10s', 'level\SNR');
        for s = 1:nS, hdr = [hdr sprintf('%8s', sprintf('%gdB', SNR_points(s)))]; end %#ok<AGROW>
        report{end+1} = hdr; %#ok<AGROW>
        for li = 1:numel(g.levels)
            line = sprintf('  %-10g', g.levels(li));
            for s = 1:nS
                switch g.status(li,s)
                    case 1, c = 'R'; case 2, c = 'M'; case 3, c = 'X'; otherwise, c = '.';
                end
                if g.status(li,s) > 0, c = [c ACT_CODE(g.best_action{li,s})]; end %#ok<AGROW>
                line = [line sprintf('%8s', c)]; %#ok<AGROW>
            end
            report{end+1} = line; %#ok<AGROW>
        end
        n_rec = sum(g.status(:)==1); n_mar = sum(g.status(:)==2); n_non = sum(g.status(:)==3);
        n_tot = n_rec + n_mar + n_non;
        report{end+1} = sprintf('  -> recoverable %d/%d (%.0f%%) | marginal %d | non-recoverable %d', ...
            n_rec, n_tot, 100*n_rec/max(n_tot,1), n_mar, n_non); %#ok<AGROW>
        report{end+1} = ''; %#ok<AGROW>
    end
    all_status = [];
    for t = 1:nT, all_status = [all_status; grid_data(t).status(:)]; end %#ok<AGROW>
    all_status = all_status(all_status > 0);
    report{end+1} = '=== OVERALL ===';
    report{end+1} = sprintf('Total states mapped: %d', numel(all_status));
    report{end+1} = sprintf('  Recoverable     : %d (%.1f%%)', sum(all_status==1), 100*mean(all_status==1));
    report{end+1} = sprintf('  Marginal        : %d (%.1f%%)', sum(all_status==2), 100*mean(all_status==2));
    report{end+1} = sprintf('  Non-recoverable : %d (%.1f%%)', sum(all_status==3), 100*mean(all_status==3));
end

function write_report(report, path)
    fid = fopen(path,'w');
    for i=1:numel(report), fprintf(fid,'%s\n',report{i}); end
    fclose(fid);
end

function draw_map(grid_data, SNR_points, RATIO_RECOVERABLE, RATIO_MARGINAL, sup_title, out_path)
    nT = numel(grid_data);
    nS = numel(SNR_points);
    fig = figure('Position',[50 50 1400 750],'Color','w');
    cmap = [0.20 0.65 0.25;
            0.95 0.75 0.15;
            0.80 0.20 0.20];

    for t = 1:nT
        g = grid_data(t);
        subplot(2, ceil(nT/2), t);
        imagesc(g.status, [1 3]);
        colormap(gca, cmap);
        set(gca,'XTick',1:nS,'XTickLabel',compose('%g',SNR_points), ...
                'YTick',1:numel(g.levels),'YTickLabel',compose('%g',g.levels));
        xlabel('E_b/N_0 (dB)'); ylabel('Severity level');
        title(strrep(g.threat,'_','\_'), 'Interpreter','tex');

        for li = 1:numel(g.levels)
            for s = 1:nS
                if ~isnan(g.ratio(li,s))
                    text(s, li, sprintf('%.1f', g.ratio(li,s)), ...
                        'HorizontalAlignment','center','FontSize',7,'Color','w');
                end
            end
        end
    end
    sgtitle(sup_title, 'Interpreter','tex');
    saveas(fig, out_path);
    close(fig);
end