%% EXPLORE_COUNTERMEASURES — Deep exploration of mitigation strategies
% Standalone experiment. Reuses only validated building blocks (init_params,
% build_threat_model, quick_ber) and does not modify any C1/C2/C3 file.
%
% For every threat, across its full severity range (same 5 levels as
% run_dataset_sweep.m) and full SNR range (all 6 EbNo points), tests several
% mitigation mechanisms and strengths -- unlike C1-C3, which use one fixed
% mitigation value per threat.
%
% Mechanisms:
%   1. field_reduction   - reduce the threat's own severity field
%                          (frequency avoidance / repositioning / faster switching)
%   2. awgn_margin_boost - add coding-gain-equivalent SNR margin at the AWGN
%                          block, without touching the threat at all
%                          (stronger FEC / robust modulation). Universal.
%   3. atten_reduction   - antenna_fault only: reduce fault_atten_db directly
%                          (switching to a working backup antenna)
%
% IMPORTANT: Sections 1-2 of this script's report rank ALL mechanisms,
% including physically invalid ones (e.g. field_reduction applied to
% antenna_fault's fault_duty, a 0-1 fraction, using dB-scale magnitudes).
% Run analyze_exploration_results.m afterwards -- it filters those out and
% produces the authoritative ranking in results/exploration_diagnosis.txt.
%
% QUICK_MODE = true -> tiny sanity run (~2 min) before the full sweep (~45-60 min).
%
% Output: data/countermeasure_exploration.mat
%         results/countermeasure_exploration_summary.png
%         results/countermeasure_exploration_curves.png
%         results/countermeasure_exploration_report.txt

close all; clc;
fprintf('=== EXPLORE COUNTERMEASURES: Deep Mitigation Search ===\n\n');

%% ========== CONFIG ==========
QUICK_MODE = false;   % set true first to sanity-check the script (~2 min)

init_params;
p0 = load('params.mat').params;
modelName = 'UAV_GCS_Threat_Link';

% Severity levels per threat -- identical to run_dataset_sweep.m (A5), so
% results are directly comparable to the training-data severity range.
clear threat_cfg
threat_cfg(1) = struct('name','jamming',             'level_field','jsr_db',        'levels',[0 4 8 12 16]);
threat_cfg(2) = struct('name','noise_burst',         'level_field','jsr_db',        'levels',[0 4 8 12 16]);
threat_cfg(3) = struct('name','reactive_jamming',    'level_field','jsr_db',        'levels',[0 4 8 12 16]);
threat_cfg(4) = struct('name','path_loss',           'level_field','path_loss_db',  'levels',[4 8 12 16 20]);
threat_cfg(5) = struct('name','spoofing',            'level_field','spoof_sir_db',  'levels',[-4 -1 2 5 8]);
threat_cfg(6) = struct('name','antenna_fault',       'level_field','fault_duty',    'levels',[0.1 0.2 0.3 0.4 0.5]);
threat_cfg(7) = struct('name','sweeping_jammer',     'level_field','jsr_db',        'levels',[0 4 8 12 16]);
threat_cfg(8) = struct('name','benign_interference', 'level_field','benign_int_db', 'levels',[-10 -8 -6 -4 -2]);
SNR_points = p0.EbNo_dB;   % 0:2:10, full range

if QUICK_MODE
    fprintf('*** QUICK_MODE ON: reduced sweep for sanity check ***\n\n');
    for i = 1:numel(threat_cfg)
        threat_cfg(i).levels = threat_cfg(i).levels(1);
    end
    SNR_points = SNR_points([1 end]);
    mag_field_reduction = [10 20];
    mag_awgn_boost      = [6 12];
    mag_fault_atten     = [10 20];
else
    mag_field_reduction = [5 10 15 20 25];
    mag_awgn_boost      = [3 6 9 12 15];
    mag_fault_atten     = [5 10 15 20 25];
end

%% ========== Pre-count total work for ETA ==========
total_builds = 0; total_resims = 0;
for t = 1:numel(threat_cfg)
    nLevels = numel(threat_cfg(t).levels);
    nSNR    = numel(SNR_points);
    total_builds = total_builds + nLevels*nSNR;
    total_builds = total_builds + nLevels*nSNR*numel(mag_field_reduction);
    total_resims = total_resims + nLevels*nSNR*numel(mag_awgn_boost);
    if strcmp(threat_cfg(t).name, 'antenna_fault')
        total_builds = total_builds + nLevels*nSNR*numel(mag_fault_atten);
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

            %% --- Mechanism 2: awgn_margin_boost (no rebuild, reuse model) ---
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

            %% --- Mechanism 3: atten_reduction (antenna_fault only, rebuild) ---
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
fprintf('NOTE: unfiltered -- includes physically invalid combinations.\n');
fprintf('      See analyze_exploration_results.m for the filtered ranking.\n\n');
fprintf('%-18s %-20s %10s %12s\n', 'Threat', 'Best Mechanism', 'Magnitude', 'Avg Recovery%');

threat_names = unique({R.threat}, 'stable');
best_per_threat = struct('threat',{},'mechanism',{},'magnitude',{},'avg_recovery',{});

% Historical C3 recovery figures, kept for continuity only. These predate
% the spoofing threat-model fix and the one-hot DQN, so the "Improvement"
% column below compares against a system that no longer exists.
current_best_static = struct('jamming',31.7,'reactive_jamming',33.9,'noise_burst',21.9, ...
    'path_loss',76.9,'spoofing',39.5,'antenna_fault',4.7);

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

fprintf('\n=== Comparison vs Historical C1/C3 Static Mitigation (STALE baseline) ===\n');
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

%% ========== Plot 1: Best achievable vs historical static approach ==========
fig1 = figure('Position', [100 100 900 450], 'Color', 'w');
tnames_plot = {best_per_threat.threat};
cur_vals = zeros(size(tnames_plot));
for i = 1:numel(tnames_plot)
    if isfield(current_best_static, tnames_plot{i})
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
title('Historical Static Mitigation vs Best Found Strategy (full sweep)');
legend('Historical C1/C3 (single value, stale)', 'Best found (this exploration)', 'Location', 'northwest');
grid on;
if ~exist('results', 'dir'), mkdir('results'); end
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

%% ========== Full final report (console + saved .txt) ==========
report_lines = {};
report_lines{end+1} = '=== FULL COUNTERMEASURE EXPLORATION REPORT ===';
report_lines{end+1} = sprintf('Generated: %s', datestr(now));
report_lines{end+1} = sprintf('Total scenarios tested: %d', numel(R));
report_lines{end+1} = sprintf('Total runtime: %.1f minutes', toc(t_start)/60);
report_lines{end+1} = '';
report_lines{end+1} = 'WARNING: Sections 1-2 below are UNFILTERED and rank physically invalid';
report_lines{end+1} = 'combinations alongside valid ones (e.g. field_reduction applied to';
report_lines{end+1} = 'antenna_fault''s fault_duty, a 0-1 fraction, using dB-scale magnitudes).';
report_lines{end+1} = 'The authoritative ranking is results/exploration_diagnosis.txt, produced';
report_lines{end+1} = 'by analyze_exploration_results.m, which filters those out.';
report_lines{end+1} = '';
report_lines{end+1} = 'WARNING: the "Current(C3)" column in Section 2 is a STALE historical';
report_lines{end+1} = 'baseline, measured before the spoofing threat-model fix and before the';
report_lines{end+1} = 'one-hot DQN. Do not cite the Improvement column as a current result.';
report_lines{end+1} = '';

% --- Section 1: Best mechanism per threat ---
report_lines{end+1} = '--- Section 1: Best Strategy Per Threat (avg over all levels & SNR, UNFILTERED) ---';
report_lines{end+1} = sprintf('%-18s %-20s %10s %12s', 'Threat', 'Best Mechanism', 'Magnitude', 'Avg Recovery%');
for i = 1:numel(best_per_threat)
    b = best_per_threat(i);
    report_lines{end+1} = sprintf('%-18s %-20s %10.1f %11.1f%%', b.threat, b.mechanism, b.magnitude, b.avg_recovery);
end
report_lines{end+1} = '';

% --- Section 2: Comparison vs historical static approach ---
report_lines{end+1} = '--- Section 2: vs Historical C1/C3 Static Mitigation (STALE baseline) ---';
report_lines{end+1} = sprintf('%-18s %14s %14s %10s', 'Threat', 'Current(C3)', 'Best Found', 'Improvement');
for i = 1:numel(best_per_threat)
    b = best_per_threat(i);
    if isfield(current_best_static, b.threat)
        cur = current_best_static.(b.threat);
        report_lines{end+1} = sprintf('%-18s %13.1f%% %13.1f%% %+9.1f%%', b.threat, cur, b.avg_recovery, b.avg_recovery-cur);
    else
        report_lines{end+1} = sprintf('%-18s %13s %13.1f%% %10s', b.threat, 'N/A (new)', b.avg_recovery, 'N/A');
    end
end
report_lines{end+1} = '';

% --- Section 3: Per-threat breakdown by severity level ---
report_lines{end+1} = '--- Section 3: Best Recovery Per Threat, Per Severity Level (avg over SNR) ---';
for i = 1:numel(threat_names)
    tname = threat_names{i};
    cfg_i = threat_cfg(strcmp({threat_cfg.name}, tname));
    report_lines{end+1} = sprintf('  %s:', tname);
    for lv = cfg_i.levels
        mask = strcmp({R.threat},tname) & [R.level]==lv;
        sub = R(mask);
        if isempty(sub)
            continue;
        end
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

% --- Section 4: Hard cases (best mechanism still gave <20% recovery) ---
report_lines{end+1} = '--- Section 4: Hard Cases (best mechanism still gave <20% recovery) ---';
hard_count = 0;
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

fprintf('\n');
for i = 1:numel(report_lines)
    fprintf('%s\n', report_lines{i});
end

fid = fopen('results/countermeasure_exploration_report.txt', 'w');
for i = 1:numel(report_lines)
    fprintf(fid, '%s\n', report_lines{i});
end
fclose(fid);
fprintf('\nSaved results/countermeasure_exploration_report.txt\n');

fprintf('\n=== Exploration Complete ===\n');