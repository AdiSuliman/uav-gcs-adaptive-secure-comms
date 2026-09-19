%% MAP_SURVIVABILITY_BOUNDARY — proposal deliverable #7 (primary research output)
% Maps, per threat, the regime where an attack is recoverable versus
% non-recoverable, over the two axes that define the operating envelope:
% attack severity level and channel SNR.
%
% METHOD
% 1. Measure the clean-channel (none) BER at every SNR point, averaged over
%    repeated runs. This is the physical floor: no countermeasure can take
%    BER below it, so it is the reference every attacked state is judged
%    against -- matching the proposal's "restore BER to a defined fraction
%    of the no-attack values".
% 2. For each (threat, level, SNR) in the EXP sweep, take the best BER
%    achievable by any physically legitimate mitigation.
% 3. Classify by ratio to the clean floor, not by relative improvement.
%    Relative improvement is bounded by the floor -- a threat whose attacked
%    BER is already close to the clean BER can never show a high recovery
%    percentage even when fully mitigated, which misreads as weakness.
%
% The legitimacy filter mirrors analyze_exploration_results.m: field_reduction
% on antenna_fault uses dB magnitudes against fault_duty (a 0-1 fraction) and
% is excluded entirely; field_reduction driving path_loss_db negative implies
% signal amplification and is excluded.
%
% Input:  data/countermeasure_exploration.mat
% Output: results/survivability_boundary.txt
%         results/survivability_map.png
%         data/survivability_boundary.mat

close all; clc;
fprintf('=== Survivability Boundary Mapping (proposal deliverable #7) ===\n\n');

%% ========== CONFIG ==========
N_BASELINE_REPEATS = 5;    % repeats per SNR for the clean-channel reference

% Classification thresholds, as a ratio of achieved BER to clean-channel BER
% at the same SNR. 2x is the primary boundary: the link is considered
% recovered when it performs within a factor of two of an unattacked channel.
RATIO_RECOVERABLE = 2;
RATIO_MARGINAL    = 5;

init_params;
p0 = load('params.mat').params;
modelName = 'UAV_GCS_Threat_Link';
delay_bits = 20;

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

%% ========== 2. Legitimacy filter (mirrors analyze_exploration_results.m) ==========
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

%% ========== 3. Build the map ==========
threat_names = unique({R_legit.threat}, 'stable');
nT = numel(threat_names);
nS = numel(SNR_points);

grid_data = struct('threat',{},'levels',{},'ber_best',{},'ratio',{}, ...
    'status',{},'ber_attacked',{});

fprintf('Classifying (ratio to clean channel): recoverable <= %gx, marginal <= %gx\n\n', ...
    RATIO_RECOVERABLE, RATIO_MARGINAL);

for t = 1:nT
    tname = threat_names{t};
    cfg_i = threat_cfg(strcmp({threat_cfg.name}, tname));
    levels = cfg_i.levels;
    nL = numel(levels);

    ber_best     = nan(nL, nS);
    ber_attacked = nan(nL, nS);
    ratio        = nan(nL, nS);
    status       = zeros(nL, nS);   % 1=recoverable 2=marginal 3=non-recoverable

    for li = 1:nL
        for s = 1:nS
            mask = strcmp({R_legit.threat}, tname) & ...
                   ([R_legit.level] == levels(li)) & ...
                   ([R_legit.snr]   == SNR_points(s));
            sub = R_legit(mask);
            if isempty(sub), continue; end

            ber_best(li,s)     = min([sub.ber_after]);
            ber_attacked(li,s) = sub(1).ber_before;   % same for all mechanisms here
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
        'ber_attacked',ber_attacked); %#ok<SAGROW>
end

%% ========== 4. Recovery ceiling analysis ==========
% How much of the theoretically available improvement was actually achieved.
% The ceiling is set by the clean-channel floor: a threat whose attacked BER
% is already near the clean BER has little room to improve, and a low
% recovery percentage there does not indicate a weak countermeasure.
fprintf('=== Recovery ceiling analysis (at SNR=%g dB) ===\n', SNR_points(1));
fprintf('%-22s %12s %12s %12s %12s\n', 'Threat', 'BER attack', 'ceiling %', 'achieved %', 'of ceiling');
ceiling_rows = {};
for t = 1:nT
    g = grid_data(t);
    li = ceil(numel(g.levels)/2);   % mid severity level
    b_att = g.ber_attacked(li,1);
    b_best = g.ber_best(li,1);
    if isnan(b_att) || isnan(b_best), continue; end
    ceil_pct = 100*(b_att - ber_clean(1))/max(b_att,eps);
    ach_pct  = 100*(b_att - b_best)/max(b_att,eps);
    frac     = 100*ach_pct/max(ceil_pct,eps);
    fprintf('%-22s %12.3e %11.1f%% %11.1f%% %11.1f%%\n', ...
        g.threat, b_att, ceil_pct, ach_pct, frac);
    ceiling_rows{end+1} = sprintf('%-22s %12.3e %11.1f%% %11.1f%% %11.1f%%', ...
        g.threat, b_att, ceil_pct, ach_pct, frac); %#ok<SAGROW>
end
fprintf('\n');

%% ========== 5. Report ==========
report = {};
report{end+1} = '=== SURVIVABILITY BOUNDARY MAP ===';
report{end+1} = sprintf('Generated: %s', datestr(now));
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
report{end+1} = 'The clean-channel BER is a floor no countermeasure can cross. A threat whose';
report{end+1} = 'attacked BER sits near that floor has little headroom, so a modest recovery';
report{end+1} = 'percentage there reflects the ceiling, not a weak countermeasure.';
report{end+1} = sprintf('%-22s %12s %12s %12s %12s', 'Threat', 'BER attack', 'ceiling %', 'achieved %', 'of ceiling');
for i = 1:numel(ceiling_rows), report{end+1} = ceiling_rows{i}; end
report{end+1} = '';

report{end+1} = '--- Boundary map, per threat (rows = severity level, cols = SNR) ---';
report{end+1} = 'Legend: R = recoverable | M = marginal | X = non-recoverable | . = no data';
report{end+1} = '';
for t = 1:nT
    g = grid_data(t);
    report{end+1} = sprintf('%s:', g.threat);
    hdr = sprintf('  %-10s', 'level\SNR');
    for s = 1:nS, hdr = [hdr sprintf('%8s', sprintf('%gdB', SNR_points(s)))]; end
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
            line = [line sprintf('%8s', c)];
        end
        report{end+1} = line;
    end

    % Boundary summary for this threat
    n_rec = sum(g.status(:)==1); n_mar = sum(g.status(:)==2);
    n_non = sum(g.status(:)==3); n_tot = n_rec+n_mar+n_non;
    if n_tot > 0
        report{end+1} = sprintf('  -> recoverable %d/%d (%.0f%%) | marginal %d | non-recoverable %d', ...
            n_rec, n_tot, 100*n_rec/n_tot, n_mar, n_non);
    end
    report{end+1} = '';
end

% Overall
all_status = [];
for t = 1:nT, all_status = [all_status; grid_data(t).status(:)]; end
all_status = all_status(all_status>0);
report{end+1} = '=== OVERALL ===';
report{end+1} = sprintf('Total states mapped: %d', numel(all_status));
report{end+1} = sprintf('  Recoverable     : %d (%.1f%%)', sum(all_status==1), 100*mean(all_status==1));
report{end+1} = sprintf('  Marginal        : %d (%.1f%%)', sum(all_status==2), 100*mean(all_status==2));
report{end+1} = sprintf('  Non-recoverable : %d (%.1f%%)', sum(all_status==3), 100*mean(all_status==3));

if ~exist('results','dir'), mkdir('results'); end
fid = fopen('results/survivability_boundary.txt','w');
for i=1:numel(report), fprintf(fid,'%s\n',report{i}); end
fclose(fid);
for i=1:numel(report), fprintf('%s\n',report{i}); end
fprintf('\nSaved results/survivability_boundary.txt\n');

save('data/survivability_boundary.mat','grid_data','ber_clean','SNR_points', ...
    'RATIO_RECOVERABLE','RATIO_MARGINAL');

%% ========== 6. Map figure ==========
fig = figure('Position',[50 50 1400 750],'Color','w');
cmap = [0.20 0.65 0.25;    % green  = recoverable
        0.95 0.75 0.15;    % amber  = marginal
        0.80 0.20 0.20];   % red    = non-recoverable

for t = 1:nT
    g = grid_data(t);
    subplot(2, ceil(nT/2), t);
    imagesc(g.status, [1 3]);
    colormap(gca, cmap);
    set(gca,'XTick',1:nS,'XTickLabel',compose('%g',SNR_points), ...
            'YTick',1:numel(g.levels),'YTickLabel',compose('%g',g.levels));
    xlabel('E_b/N_0 (dB)'); ylabel('Severity level');
    title(strrep(g.threat,'_','\_'), 'Interpreter','tex');

    % annotate each cell with the ratio
    for li = 1:numel(g.levels)
        for s = 1:nS
            if ~isnan(g.ratio(li,s))
                text(s, li, sprintf('%.1f', g.ratio(li,s)), ...
                    'HorizontalAlignment','center','FontSize',7,'Color','w');
            end
        end
    end
end
sgtitle(sprintf('Survivability Boundary: best achievable BER relative to clean channel (green <= %gx, amber <= %gx, red > %gx)', ...
    RATIO_RECOVERABLE, RATIO_MARGINAL, RATIO_MARGINAL));
saveas(fig,'results/survivability_map.png');
close(fig);
fprintf('Saved results/survivability_map.png\n');

fprintf('\n=== Survivability Mapping Complete ===\n');