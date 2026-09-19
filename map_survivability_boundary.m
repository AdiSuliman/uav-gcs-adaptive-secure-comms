%% MAP_SURVIVABILITY_BOUNDARY — proposal deliverable #7 (primary research output)
% Maps, per threat, the regime where an attack is recoverable versus
% non-recoverable, over attack severity level and channel SNR.
%
% Produces TWO maps, not one:
%   Map A (Threat Neutralization) — mechanisms: atten_reduction, field_reduction.
%     "How much of the attack itself can be removed." This is the literal
%     reading of proposal deliverable #7.
%   Map B (Link Survivability)    — all mechanisms, including awgn_margin_boost.
%     "What the link can achieve by any available means." awgn_margin_boost
%     raises the effective SNR rather than neutralizing the threat, so it can
%     make the link outperform the nominal clean-channel floor without the
%     attack itself being weakened. Map B alone overstates neutralization.
%
% Gap analysis: cells where Map B is recoverable/marginal but Map A is
% non-recoverable are exactly the goodput-tradeoff regime the proposal
% describes (rate/margin changes that trade throughput for survival without
% removing the threat).
%
% METHOD
% 1. Measure clean-channel (none) BER at every SNR point (physical floor).
% 2. For each (threat, level, SNR), take the best ber_after within each
%    mechanism set separately (Map A set vs Map B set).
% 3. Classify by ratio to the clean floor.
%
% Input:  data/countermeasure_exploration.mat
% Output: results/survivability_boundary_mapA.txt
%         results/survivability_boundary_mapB.txt
%         results/survivability_gap_analysis.txt
%         results/survivability_map_neutralization.png  (Map A)
%         results/survivability_map_link.png             (Map B)
%         data/survivability_boundary.mat

close all; clc;
fprintf('=== Survivability Boundary Mapping (proposal deliverable #7) ===\n\n');

%% ========== CONFIG ==========
N_BASELINE_REPEATS = 5;
RATIO_RECOVERABLE = 2;
RATIO_MARGINAL    = 5;

MECH_A = {'atten_reduction','field_reduction'};   % true threat neutralization
MECH_B = {'atten_reduction','field_reduction','awgn_margin_boost'};  % all means

init_params;
p0 = load('params.mat').params;
modelName = 'UAV_GCS_Threat_Link';

if ~exist('data/countermeasure_exploration.mat','file')
    error('data/countermeasure_exploration.mat not found. Run explore_countermeasures.m first.');
end
L = load('data/countermeasure_exploration.mat', 'R', 'threat_cfg', 'SNR_points');
R = L.R; threat_cfg = L.threat_cfg; SNR_points = L.SNR_points;
fprintf('Loaded %d exploration records across %d threats, %d SNR points.\n\n', ...
    numel(R), numel(threat_cfg), numel(SNR_points));

%% ========== 1. Clean-channel baseline per SNR ==========
fprintf('Measuring clean-channel (none) baseline, %d repeats per SNR...\n', N_BASELINE_REPEATS);
ber_clean = zeros(1, numel(SNR_points));

p = p0; p.active_threat = 'none';
params = p; save('params.mat','params');
build_threat_model;

for s = 1:numel(SNR_points)
    ebno = SNR_points(s);
    snr_dB = ebno + 10*log10(p0.bits_per_symbol) - 10*log10(p0.sps);
    set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), ...
        'SignalPower', num2str(1/p0.sps));

    reps = zeros(1, N_BASELINE_REPEATS);
    for r = 1:N_BASELINE_REPEATS
        reps(r) = quick_ber(modelName);
    end
    ber_clean(s) = mean(reps);
    fprintf('  SNR=%2g dB: clean BER = %.4e (std %.2e)\n', ebno, ber_clean(s), std(reps));
end
params = p0; save('params.mat','params');
fprintf('\n');

%% ========== 2. Legitimacy filter ==========
keep = true(1, numel(R));
for i = 1:numel(R)
    r = R(i);
    if strcmp(r.threat,'antenna_fault') && strcmp(r.mechanism,'field_reduction')
        keep(i) = false;
    elseif strcmp(r.threat,'path_loss') && strcmp(r.mechanism,'field_reduction')
        if (r.level - r.magnitude) < 0
            keep(i) = false;
        end
    end
end
R_legit = R(keep);
fprintf('Legitimacy filter: %d of %d records excluded, %d remain.\n\n', ...
    sum(~keep), numel(R), numel(R_legit));

%% ========== 3. Build both maps ==========
threat_names = unique({R_legit.threat}, 'stable');

fprintf('Classifying (ratio to clean channel): recoverable <= %gx, marginal <= %gx\n\n', ...
    RATIO_RECOVERABLE, RATIO_MARGINAL);

grid_data_A = build_map(R_legit, MECH_A, threat_names, threat_cfg, SNR_points, ...
    ber_clean, RATIO_RECOVERABLE, RATIO_MARGINAL);
grid_data_B = build_map(R_legit, MECH_B, threat_names, threat_cfg, SNR_points, ...
    ber_clean, RATIO_RECOVERABLE, RATIO_MARGINAL);

%% ========== 4. Reports ==========
if ~exist('results','dir'), mkdir('results'); end

report_A = build_report(grid_data_A, ber_clean, SNR_points, RATIO_RECOVERABLE, RATIO_MARGINAL, ...
    'MAP A — THREAT NEUTRALIZATION', MECH_A);
write_report(report_A, 'results/survivability_boundary_mapA.txt');

report_B = build_report(grid_data_B, ber_clean, SNR_points, RATIO_RECOVERABLE, RATIO_MARGINAL, ...
    'MAP B — LINK SURVIVABILITY', MECH_B);
write_report(report_B, 'results/survivability_boundary_mapB.txt');

fprintf('\n--- MAP A (Threat Neutralization) ---\n');
for i = 1:numel(report_A), fprintf('%s\n', report_A{i}); end
fprintf('\n--- MAP B (Link Survivability) ---\n');
for i = 1:numel(report_B), fprintf('%s\n', report_B{i}); end

%% ========== 5. Gap analysis ==========
gap_report = {};
gap_report{end+1} = '=== SURVIVABILITY GAP ANALYSIS ===';
gap_report{end+1} = 'Cells where the link survives (Map B: recoverable/marginal) but the';
gap_report{end+1} = 'threat itself is not neutralized (Map A: non-recoverable). This is the';
gap_report{end+1} = 'regime where survival comes from trading link margin/rate, not from';
gap_report{end+1} = 'removing the attack.';
gap_report{end+1} = '';

n_gap_total = 0;
for t = 1:numel(threat_names)
    tname = threat_names{t};
    gA = grid_data_A(strcmp({grid_data_A.threat}, tname));
    gB = grid_data_B(strcmp({grid_data_B.threat}, tname));
    if isempty(gA) || isempty(gB), continue; end

    gap_mask = (gB.status <= 2) & (gA.status == 3);
    n_gap = sum(gap_mask(:));
    n_gap_total = n_gap_total + n_gap;
    if n_gap == 0, continue; end

    gap_report{end+1} = sprintf('%s: %d gap cell(s)', tname, n_gap); %#ok<SAGROW>
    [li_idx, s_idx] = find(gap_mask);
    for k = 1:numel(li_idx)
        li = li_idx(k); s = s_idx(k);
        gap_report{end+1} = sprintf('  level=%g, SNR=%gdB: Map A ratio=%.2fx (non-rec) | Map B ratio=%.2fx', ...
            gA.levels(li), SNR_points(s), gA.ratio(li,s), gB.ratio(li,s)); %#ok<SAGROW>
    end
end
gap_report{end+1} = '';
gap_report{end+1} = sprintf('Total gap cells: %d', n_gap_total);

write_report(gap_report, 'results/survivability_gap_analysis.txt');
fprintf('\n--- GAP ANALYSIS ---\n');
for i = 1:numel(gap_report), fprintf('%s\n', gap_report{i}); end

save('data/survivability_boundary.mat','grid_data_A','grid_data_B','ber_clean', ...
    'SNR_points','RATIO_RECOVERABLE','RATIO_MARGINAL','MECH_A','MECH_B');

%% ========== 6. Figures ==========
draw_map(grid_data_A, SNR_points, RATIO_RECOVERABLE, RATIO_MARGINAL, ...
    'Map A: Threat Neutralization (atten\_reduction, field\_reduction only)', ...
    'results/survivability_map_neutralization.png');
draw_map(grid_data_B, SNR_points, RATIO_RECOVERABLE, RATIO_MARGINAL, ...
    'Map B: Link Survivability (all mechanisms, incl. awgn\_margin\_boost)', ...
    'results/survivability_map_link.png');

fprintf('\nSaved results/survivability_boundary_mapA.txt\n');
fprintf('Saved results/survivability_boundary_mapB.txt\n');
fprintf('Saved results/survivability_gap_analysis.txt\n');
fprintf('Saved results/survivability_map_neutralization.png\n');
fprintf('Saved results/survivability_map_link.png\n');
fprintf('\n=== Survivability Mapping Complete ===\n');


%% ========== LOCAL FUNCTIONS ==========

function grid_data = build_map(R_legit, mech_set, threat_names, threat_cfg, SNR_points, ...
    ber_clean, RATIO_RECOVERABLE, RATIO_MARGINAL)
    nT = numel(threat_names);
    nS = numel(SNR_points);
    grid_data = struct('threat',{},'levels',{},'ber_best',{},'ratio',{}, ...
        'status',{},'ber_attacked',{});

    for t = 1:nT
        tname = threat_names{t};
        cfg_i = threat_cfg(strcmp({threat_cfg.name}, tname));
        levels = cfg_i.levels;
        nL = numel(levels);

        ber_best     = nan(nL, nS);
        ber_attacked = nan(nL, nS);
        ratio        = nan(nL, nS);
        status       = zeros(nL, nS);

        for li = 1:nL
            for s = 1:nS
                mask = strcmp({R_legit.threat}, tname) & ...
                       ([R_legit.level] == levels(li)) & ...
                       ([R_legit.snr]   == SNR_points(s)) & ...
                       ismember({R_legit.mechanism}, mech_set);
                sub = R_legit(mask);
                if isempty(sub), continue; end

                ber_best(li,s)     = min([sub.ber_after]);
                ber_attacked(li,s) = sub(1).ber_before;
                ratio(li,s)        = ber_best(li,s) / max(ber_clean(s), eps);

                if ratio(li,s) <= RATIO_RECOVERABLE
                    status(li,s) = 1;
                elseif ratio(li,s) <= RATIO_MARGINAL
                    status(li,s) = 2;
                else
                    status(li,s) = 3;
                end
            end
        end

        grid_data(end+1) = struct('threat',tname,'levels',levels, ...
            'ber_best',ber_best,'ratio',ratio,'status',status, ...
            'ber_attacked',ber_attacked); %#ok<AGROW>
    end
end

function report = build_report(grid_data, ber_clean, SNR_points, RATIO_RECOVERABLE, ...
    RATIO_MARGINAL, title_str, mech_set)
    nT = numel(grid_data);
    nS = numel(SNR_points);

    report = {};
    report{end+1} = sprintf('=== SURVIVABILITY BOUNDARY MAP — %s ===', title_str);
    report{end+1} = sprintf('Generated: %s', datestr(now));
    report{end+1} = sprintf('Mechanisms included: %s', strjoin(mech_set, ', '));
    report{end+1} = '';
    report{end+1} = 'A state is classified by how close the best achievable post-countermeasure';
    report{end+1} = 'BER comes to the clean-channel BER at the same SNR:';
    report{end+1} = sprintf('  RECOVERABLE      : within %gx of clean channel', RATIO_RECOVERABLE);
    report{end+1} = sprintf('  MARGINAL         : within %gx of clean channel', RATIO_MARGINAL);
    report{end+1} = sprintf('  NON-RECOVERABLE  : worse than %gx clean channel', RATIO_MARGINAL);
    report{end+1} = '';
    report{end+1} = 'Clean-channel reference BER per SNR:';
    for s = 1:nS
        report{end+1} = sprintf('  SNR=%2g dB : %.4e', SNR_points(s), ber_clean(s));
    end
    report{end+1} = '';

    report{end+1} = '--- Recovery ceiling (mid severity, lowest SNR) ---';
    report{end+1} = sprintf('%-22s %12s %12s %12s %12s', 'Threat', 'BER attack', 'ceiling %', 'achieved %', 'of ceiling');
    for t = 1:nT
        g = grid_data(t);
        li = ceil(numel(g.levels)/2);
        b_att = g.ber_attacked(li,1);
        b_best = g.ber_best(li,1);
        if isnan(b_att) || isnan(b_best), continue; end
        ceil_pct = 100*(b_att - ber_clean(1))/max(b_att,eps);
        ach_pct  = 100*(b_att - b_best)/max(b_att,eps);
        frac     = 100*ach_pct/max(ceil_pct,eps);
        report{end+1} = sprintf('%-22s %12.3e %11.1f%% %11.1f%% %11.1f%%', ...
            g.threat, b_att, ceil_pct, ach_pct, frac);
    end
    report{end+1} = '';

    report{end+1} = '--- Boundary map, per threat (rows = severity level, cols = SNR) ---';
    report{end+1} = 'Legend: R = recoverable | M = marginal | X = non-recoverable | . = no data';
    report{end+1} = '';
    for t = 1:nT
        g = grid_data(t);
        report{end+1} = sprintf('%s:', g.threat);
        hdr = sprintf('  %-10s', 'level\SNR');
        for s = 1:nS, hdr = [hdr sprintf('%8s', sprintf('%gdB', SNR_points(s)))]; end %#ok<AGROW>
        report{end+1} = hdr;
        for li = 1:numel(g.levels)
            line = sprintf('  %-10g', g.levels(li));
            for s = 1:nS
                switch g.status(li,s)
                    case 1, c = 'R';
                    case 2, c = 'M';
                    case 3, c = 'X';
                    otherwise, c = '.';
                end
                line = [line sprintf('%8s', c)]; %#ok<AGROW>
            end
            report{end+1} = line;
        end
        n_rec = sum(g.status(:)==1); n_mar = sum(g.status(:)==2);
        n_non = sum(g.status(:)==3); n_tot = n_rec+n_mar+n_non;
        if n_tot > 0
            report{end+1} = sprintf('  -> recoverable %d/%d (%.0f%%) | marginal %d | non-recoverable %d', ...
                n_rec, n_tot, 100*n_rec/n_tot, n_mar, n_non);
        end
        report{end+1} = '';
    end

    all_status = [];
    for t = 1:nT, all_status = [all_status; grid_data(t).status(:)]; end %#ok<AGROW>
    all_status = all_status(all_status>0);
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