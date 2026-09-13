%% EXPLORE_COUNTERMEASURES — Deep exploration of NEW mitigation strategies
% Standalone experiment script. Does NOT modify or depend on any existing
% C1/C2/C3 files (rule_based_policy.m, dqn_agent.m, run_closed_loop_with_detector.m).
% Only reuses already-validated building blocks: init_params, build_threat_model,
% quick_ber (untouched).
%
% GOAL: for every threat, across its FULL severity-level range (same 5 levels
% used in run_dataset_sweep.m/A5) and FULL SNR range (all 6 EbNo points), test
% MULTIPLE mitigation mechanisms/strengths that were NOT tested in C1-C3
% (which only used ONE fixed mitigation value per threat). Finds which
% mechanism + strength actually works best, per threat.
%
% TWO NEW MECHANISMS EXPLORED (neither used before):
%   1. field_reduction  — reduce the threat's own configured severity field
%      (models: frequency avoidance / better positioning / faster switching)
%      Swept over 5 magnitudes per threat.
%   2. awgn_margin_boost — DOES NOT touch the threat at all. Instead adds
%      coding-gain-equivalent SNR margin at the AWGN block (models: stronger
%      FEC / robust modulation via rate reduction). Universal mechanism,
%      applicable to every threat, swept over 5 magnitudes.
%   3. (antenna_fault only) atten_reduction — reduces fault_atten_db directly
%      (models: switching to a working backup antenna), separate from the
%      duty-cycle field used for severity levels.
%
% QUICK_MODE = true  -> tiny sanity-check run (~2 min) before committing to
%                        the full sweep (QUICK_MODE = false, ~45-60 min).
%
% Output: data/countermeasure_exploration.mat (full results table)
%         results/countermeasure_exploration_summary.png (best per threat)
%         results/countermeasure_exploration_curves.png  (magnitude sweeps)

close all; clc;
fprintf('=== EXPLORE COUNTERMEASURES: Deep Mitigation Search ===\n\n');

%% ========== CONFIG ==========
QUICK_MODE = false;   % set true first to sanity-check the script (~2 min)

init_params;
p0 = load('params.mat').params;
modelName = 'UAV_GCS_Threat_Link';

% Severity levels per threat — IDENTICAL to run_dataset_sweep.m (A5), so
% results are directly comparable to the training-data severity range.
clear threat_cfg
threat_cfg(1) = struct('name','jamming',          'level_field','jsr_db',       'levels',[0 4 8 12 16]);
threat_cfg(2) = struct('name','noise_burst',      'level_field','jsr_db',       'levels',[0 4 8 12 16]);
threat_cfg(3) = struct('name','reactive_jamming', 'level_field','jsr_db',       'levels',[0 4 8 12 16]);
threat_cfg(4) = struct('name','path_loss',        'level_field','path_loss_db','levels',[4 8 12 16 20]);
threat_cfg(5) = struct('name','spoofing',         'level_field','spoof_sir_db','levels',[-4 -1 2 5 8]);
threat_cfg(6) = struct('name','antenna_fault',    'level_field','fault_duty',  'levels',[0.1 0.2 0.3 0.4 0.5]);
threat_cfg(7) = struct('name','sweeping_jammer',      'level_field','jsr_db',        'levels',[0 4 8 12 16]);
threat_cfg(8) = struct('name','benign_interference',  'level_field','benign_int_db', 'levels',[-10 -8 -6 -4 -2]);
SNR_points = p0.EbNo_dB;   % 0:2:10, all 6 -- full range, unchanged

if QUICK_MODE
    fprintf('*** QUICK_MODE ON: reduced sweep for sanity check ***\n\n');
    for i = 1:numel(threat_cfg)
        threat_cfg(i).levels = threat_cfg(i).levels(1);   % 1 level only
    end
    SNR_points = SNR_points([1 end]);                     % 2 SNR points only
    mag_field_reduction = [10 20];                        % 2 magnitudes
    mag_awgn_boost      = [6 12];
    mag_fault_atten     = [10 20];
else
    mag_field_reduction = [5 10 15 20 25];                 % dB, 5 magnitudes
    mag_awgn_boost      = [3 6 9 12 15];                    % dB, 5 magnitudes
    mag_fault_atten     = [5 10 15 20 25];                  % dB, antenna_fault only
end

%% ========== Pre-count total work for ETA ==========
total_builds = 0; total_resims = 0;
for t = 1:numel(threat_cfg)
    nLevels = numel(threat_cfg(t).levels);
    nSNR    = numel(SNR_points);
    total_builds = total_builds + nLevels*nSNR;            % baseline builds
    total_builds = total_builds + nLevels*nSNR*numel(mag_field_reduction);  % field_reduction
    total_resims = total_resims + nLevels*nSNR*numel(mag_awgn_boost);       % awgn_boost (no rebuild)
    if strcmp(threat_cfg(t).name, 'antenna_fault')
        total_builds = total_builds + nLevels*nSNR*numel(mag_fault_atten); % atten_reduction
    end
end
fprintf('Planned work: %d model builds, %d resims (no rebuild)\n', total_builds, total_resims);
fprintf('Rough estimate: %.0f-%.0f minutes (varies by machine)\n\n', ...
    (total_builds+total_resims)*0.8/60, (total_builds+total_resims)*2/60);

%% ========== Result storage ==========
R = struct('threat',{},'level',{},'snr',{},'mechanism',{},'magnitude',{}, ...
    'ber_before',{},'ber_after',{},'recovery_pct',{});

t_start = tic;
iter_count = 0;
last_report = 0;

%% ========== Main sweep ==========
for t = 1:numel(threat_cfg)
    cfg = threat_cfg(t);
    fprintf('--- Threat %d/%d: %s ---\n', t, numel(threat_cfg), cfg.name);

    for lv = 1:numel(cfg.levels)
        level_val = cfg.levels(lv);

        for s = 1:numel(SNR_points)
            ebno = SNR_points(s);
            snr_dB = ebno + 10*log10(p0.bits_per_symbol) - 10*log10(p0.sps);

            %% --- Reset to clean baseline for this (threat, level) ---
            p = p0;
            p.active_threat = cfg.name;
            p.(cfg.level_field) = level_val;
            params = p; save('params.mat', 'params');
            build_threat_model;
            set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), ...
                'SignalPower', num2str(1/p.sps));
            ber_before = quick_ber(modelName);
            iter_count = iter_count + 1;

            %% --- Mechanism 1: field_reduction (rebuild required) ---
            for m = 1:numel(mag_field_reduction)
                mag = mag_field_reduction(m);
                p2 = p;
                p2.(cfg.level_field) = level_val - mag;
                params = p2; save('params.mat', 'params');
                build_threat_model;
                set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), ...
                    'SignalPower', num2str(1/p2.sps));
                ber_after = quick_ber(modelName);
                iter_count = iter_count + 1;

                recov = 100*(ber_before-ber_after)/max(ber_before,eps);
                R(end+1) = struct('threat',cfg.name,'level',level_val,'snr',ebno, ...
                    'mechanism','field_reduction','magnitude',mag, ...
                    'ber_before',ber_before,'ber_after',ber_after,'recovery_pct',recov);
            end

            %% --- Mechanism 2: awgn_margin_boost (NO rebuild — reuse model) ---
            % Rebuild once at baseline threat params, then just bump AWGN SNR
            params = p; save('params.mat', 'params');
            build_threat_model;
            for m = 1:numel(mag_awgn_boost)
                mag = mag_awgn_boost(m);
                set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB + mag), ...
                    'SignalPower', num2str(1/p.sps));
                ber_after = quick_ber(modelName);
                iter_count = iter_count + 1;

                recov = 100*(ber_before-ber_after)/max(ber_before,eps);
                R(end+1) = struct('threat',cfg.name,'level',level_val,'snr',ebno, ...
                    'mechanism','awgn_margin_boost','magnitude',mag, ...
                    'ber_before',ber_before,'ber_after',ber_after,'recovery_pct',recov);
            end

            %% --- Mechanism 3: atten_reduction (antenna_fault ONLY, rebuild) ---
            if strcmp(cfg.name, 'antenna_fault')
                for m = 1:numel(mag_fault_atten)
                    mag = mag_fault_atten(m);
                    p3 = p;   % level_field (fault_duty) stays at level_val
                    p3.fault_atten_db = p0.fault_atten_db - mag;
                    params = p3; save('params.mat', 'params');
                    build_threat_model;
                    set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), ...
                        'SignalPower', num2str(1/p3.sps));
                    ber_after = quick_ber(modelName);
                    iter_count = iter_count + 1;

                    recov = 100*(ber_before-ber_after)/max(ber_before,eps);
                    R(end+1) = struct('threat',cfg.name,'level',level_val,'snr',ebno, ...
                        'mechanism','atten_reduction','magnitude',mag, ...
                        'ber_before',ber_before,'ber_after',ber_after,'recovery_pct',recov);
                end
            end

            %% --- Progress report ---
            if iter_count - last_report >= 50
                elapsed = toc(t_start);
                total_est = elapsed / max(iter_count,1) * (total_builds+total_resims);
                fprintf('  [progress] %d/%d sims | elapsed=%.1fmin | ETA total=%.1fmin\n', ...
                    iter_count, total_builds+total_resims, elapsed/60, total_est/60);
                last_report = iter_count;
            end
        end
    end
end

% Restore original params
params = p0; save('params.mat', 'params');

fprintf('\nSweep complete. Total time: %.1f minutes\n', toc(t_start)/60);

%% ========== Save raw results ==========
if ~exist('data', 'dir'), mkdir('data'); end
save('data/countermeasure_exploration.mat', 'R', 'threat_cfg', 'SNR_points', '-v7.3');
fprintf('Saved data/countermeasure_exploration.mat (%d records)\n\n', numel(R));

%% ========== Analysis: best mechanism+magnitude per threat ==========
fprintf('=== Best Strategy Per Threat (averaged over all levels & SNR) ===\n');
fprintf('%-18s %-20s %10s %12s\n', 'Threat', 'Best Mechanism', 'Magnitude', 'Avg Recovery%');

threat_names = unique({R.threat}, 'stable');
best_per_threat = struct('threat',{},'mechanism',{},'magnitude',{},'avg_recovery',{});
current_best_static = struct('jamming',31.7,'reactive_jamming',33.9,'noise_burst',21.9, ...
    'path_loss',76.9,'spoofing',39.5,'antenna_fault',4.7);
    % NOTE: sweeping_jammer / benign_interference have NO prior static baseline
    % (never tested in original C1/C3, which only knew 6 threats) -- comparison
    % section below skips them gracefully instead of erroring.

for i = 1:numel(threat_names)
    tname = threat_names{i};
    mask = strcmp({R.threat}, tname);
    sub = R(mask);

    mechs = unique({sub.mechanism}, 'stable');
    best_avg = -inf; best_mech = ''; best_mag = 0;
    for mi = 1:numel(mechs)
        mech = mechs{mi};
        mag_vals = unique([sub(strcmp({sub.mechanism},mech)).magnitude]);
        for mv = mag_vals
            idx = strcmp({sub.mechanism},mech) & [sub.magnitude]==mv;
            avg_recov = mean([sub(idx).recovery_pct]);
            if avg_recov > best_avg
                best_avg = avg_recov; best_mech = mech; best_mag = mv;
            end
        end
    end
    best_per_threat(end+1) = struct('threat',tname,'mechanism',best_mech, ...
        'magnitude',best_mag,'avg_recovery',best_avg);
    fprintf('%-18s %-20s %10.1f %11.1f%%\n', tname, best_mech, best_mag, best_avg);
end

fprintf('\n=== Comparison vs Current C1/C3 Static Mitigation ===\n');
fprintf('%-18s %14s %14s %10s\n', 'Threat', 'Current(C3)', 'Best Found', 'Improvement');
for i = 1:numel(best_per_threat)
    b = best_per_threat(i);
    if isfield(current_best_static, b.threat)
        cur = current_best_static.(b.threat);
        fprintf('%-18s %13.1f%% %13.1f%% %+9.1f%%\n', b.threat, cur, b.avg_recovery, b.avg_recovery-cur);
    else
        fprintf('%-18s %13s %13.1f%% %10s\n', b.threat, 'N/A (new)', b.avg_recovery, 'N/A');
    end
end

%% ========== Plot 1: Best achievable vs current static approach ==========
fig1 = figure('Position', [100 100 900 450], 'Color', 'w');
tnames_plot = {best_per_threat.threat};
has_baseline = cellfun(@(t) isfield(current_best_static, t), tnames_plot);
cur_vals = zeros(size(tnames_plot));
for i = 1:numel(tnames_plot)
    if has_baseline(i)
        cur_vals(i) = current_best_static.(tnames_plot{i});
    else
        cur_vals(i) = NaN;   % no bar drawn for threats with no prior baseline
    end
end
best_vals = [best_per_threat.avg_recovery];
b = bar([cur_vals(:), best_vals(:)]);
b(1).FaceColor = [0.6 0.6 0.6]; b(2).FaceColor = [0.20 0.63 0.17];
set(gca, 'XTickLabel', tnames_plot, 'XTickLabelRotation', 25);
ylabel('Avg BER Recovery (%)');
title('Current Static Mitigation vs Best Found Strategy (full sweep)');
legend('Current (C1/C3, single value)', 'Best found (this exploration)', 'Location', 'northwest');
grid on;
saveas(fig1, 'results/countermeasure_exploration_summary.png');
close(fig1);

%% ========== Plot 2: Recovery vs magnitude curves per mechanism ==========
fig2 = figure('Position', [100 100 1200 700], 'Color', 'w');
for i = 1:numel(threat_names)
    tname = threat_names{i};
    subplot(2,4,i);
    mask = strcmp({R.threat}, tname);
    sub = R(mask);
    mechs = unique({sub.mechanism}, 'stable');
    hold on;
    for mi = 1:numel(mechs)
        mech = mechs{mi};
        mag_vals = sort(unique([sub(strcmp({sub.mechanism},mech)).magnitude]));
        avg_recov = zeros(size(mag_vals));
        for k = 1:numel(mag_vals)
            idx = strcmp({sub.mechanism},mech) & [sub.magnitude]==mag_vals(k);
            avg_recov(k) = mean([sub(idx).recovery_pct]);
        end
        plot(mag_vals, avg_recov, '-o', 'LineWidth', 1.5, 'DisplayName', mech);
    end
    hold off;
    xlabel('Mitigation Magnitude'); ylabel('Avg Recovery %');
    title(tname, 'Interpreter', 'none');
    legend('Location', 'best', 'FontSize', 7);
    grid on;
end
sgtitle('Recovery % vs Mitigation Magnitude, per Mechanism (avg over levels & SNR)');
saveas(fig2, 'results/countermeasure_exploration_curves.png');
close(fig2);

fprintf('\nSaved results/countermeasure_exploration_summary.png\n');
fprintf('Saved results/countermeasure_exploration_curves.png\n');

%% ========== FULL FINAL REPORT (console + saved .txt) ==========
report_lines = {};
report_lines{end+1} = sprintf('=== FULL COUNTERMEASURE EXPLORATION REPORT ===');
report_lines{end+1} = sprintf('Generated: %s', datestr(now));
report_lines{end+1} = sprintf('Total scenarios tested: %d', numel(R));
report_lines{end+1} = sprintf('Total runtime: %.1f minutes', toc(t_start)/60);
report_lines{end+1} = '';

% --- Section 1: Best mechanism per threat (already computed above) ---
report_lines{end+1} = '--- Section 1: Best Strategy Per Threat (avg over all levels & SNR) ---';
report_lines{end+1} = sprintf('%-18s %-20s %10s %12s', 'Threat', 'Best Mechanism', 'Magnitude', 'Avg Recovery%');
for i = 1:numel(best_per_threat)
    b = best_per_threat(i);
    report_lines{end+1} = sprintf('%-18s %-20s %10.1f %11.1f%%', b.threat, b.mechanism, b.magnitude, b.avg_recovery);
end
report_lines{end+1} = '';

% --- Section 2: Comparison vs current static approach ---
report_lines{end+1} = '--- Section 2: Improvement vs Current C1/C3 Static Mitigation ---';
report_lines{end+1} = sprintf('%-18s %14s %14s %10s', 'Threat', 'Current(C3)', 'Best Found', 'Improvement');
for i = 1:numel(best_per_threat)
    b = best_per_threat(i);
    cur = current_best_static.(b.threat);
    report_lines{end+1} = sprintf('%-18s %13.1f%% %13.1f%% %+9.1f%%', b.threat, cur, b.avg_recovery, b.avg_recovery-cur);
end
report_lines{end+1} = '';

% --- Section 3: Per-threat breakdown by SEVERITY LEVEL (best mechanism per level) ---
report_lines{end+1} = '--- Section 3: Best Recovery Per Threat, Per Severity Level (avg over SNR) ---';
for i = 1:numel(threat_names)
    tname = threat_names{i};
    cfg_i = threat_cfg(strcmp({threat_cfg.name}, tname));
    report_lines{end+1} = sprintf('  %s:', tname);
    for lv = cfg_i.levels
        mask = strcmp({R.threat},tname) & [R.level]==lv;
        sub = R(mask);
        [best_recov, bidx] = max(arrayfun(@(x) x.recovery_pct, sub));
        if isempty(sub)
            continue;
        end
        % average best-mechanism recovery at this level (take best mech/mag per SNR, then avg)
        mechs_here = unique({sub.mechanism}, 'stable');
        best_at_level = -inf;
        for mi = 1:numel(mechs_here)
            magvals = unique([sub(strcmp({sub.mechanism},mechs_here{mi})).magnitude]);
            for mv = magvals
                idx2 = strcmp({sub.mechanism},mechs_here{mi}) & [sub.magnitude]==mv;
                avgr = mean([sub(idx2).recovery_pct]);
                if avgr > best_at_level, best_at_level = avgr; end
            end
        end
        report_lines{end+1} = sprintf('    level=%-8g -> best avg recovery = %.1f%%', lv, best_at_level);
    end
end
report_lines{end+1} = '';

% --- Section 4: Hard cases -- scenarios where even the BEST mechanism failed (<20% recovery) ---
report_lines{end+1} = '--- Section 4: Hard Cases (best mechanism still gave <20% recovery) ---';
hard_count = 0;
% group by threat+level+snr, find max recovery across all mechanisms/magnitudes tested
keys = unique(arrayfun(@(x) sprintf('%s|%g|%g', x.threat, x.level, x.snr), R, 'UniformOutput', false));
for k = 1:numel(keys)
    parts = strsplit(keys{k}, '|');
    mask = strcmp({R.threat}, parts{1}) & [R.level]==str2double(parts{2}) & [R.snr]==str2double(parts{3});
    sub = R(mask);
    max_recov = max([sub.recovery_pct]);
    if max_recov < 20
        hard_count = hard_count + 1;
        [~, bi] = max([sub.recovery_pct]);
        report_lines{end+1} = sprintf('    %-18s level=%-8s snr=%-4s -> best only %.1f%% (mechanism=%s, mag=%g)', ...
            parts{1}, parts{2}, parts{3}, max_recov, sub(bi).mechanism, sub(bi).magnitude);
    end
end
if hard_count == 0
    report_lines{end+1} = '    None -- every tested scenario had at least one mechanism achieving >=20% recovery.';
else
    report_lines{end+1} = sprintf('    Total hard cases: %d / %d scenarios (%.1f%%)', ...
        hard_count, numel(keys), 100*hard_count/numel(keys));
end
report_lines{end+1} = '';
report_lines{end+1} = '=== END OF REPORT ===';

% Print to console
fprintf('\n');
for i = 1:numel(report_lines)
    fprintf('%s\n', report_lines{i});
end

% Save to file
fid = fopen('results/countermeasure_exploration_report.txt', 'w');
for i = 1:numel(report_lines)
    fprintf(fid, '%s\n', report_lines{i});
end
fclose(fid);
fprintf('\nSaved results/countermeasure_exploration_report.txt (full report, will not scroll away)\n');

fprintf('\n=== Exploration Complete ===\n');