%% ANALYZE_EXPLORATION_RESULTS — Post-hoc diagnostic: best treatment per threat, per severity level
% Loads the already-computed data/countermeasure_exploration.mat (no re-simulation,
% runs in seconds). Filters out PHYSICALLY INVALID combinations before ranking:
%   - antenna_fault + field_reduction: EXCLUDED ENTIRELY. Uses magnitudes designed
%     for dB fields (5-25) on fault_duty (a 0-1 fraction) -> always drives duty
%     negative -> clamped/interpreted as duty=0 -> threat fully disabled, not a
%     real "treatment effect". This explains the flat ~74% line in the curves plot.
%   - path_loss + field_reduction: excluded when (level - magnitude) < 0, since
%     negative path_loss_db implies signal AMPLIFICATION, which "better positioning"
%     cannot legitimately produce (floor is 0 dB path loss, not negative).
%   - jsr_db / spoof_sir_db based field_reduction: NOT filtered — negative dB is
%     physically meaningful here (jammer/spoofer weaker than signal).
%   - awgn_margin_boost: never filtered (adding SNR margin has no physical floor issue).
%   - atten_reduction (antenna_fault only, targets fault_atten_db from a 30dB
%     baseline): kept as-is, all tested magnitudes (5-25) stay non-negative.
%
% Output: console diagnostic table (per threat, per severity level: best legitimate
%         mechanism + magnitude + recovery%) and results/exploration_diagnosis.txt

close all; clc;
fprintf('=== Diagnostic Analysis: Legitimate Best Treatment Per Threat, Per Level ===\n\n');

%% 1. Load raw results (no Simulink re-run needed)
L = load('data/countermeasure_exploration.mat', 'R', 'threat_cfg');
R = L.R;
threat_cfg = L.threat_cfg;

fprintf('Loaded %d raw scenario records.\n', numel(R));

%% 2. Apply physical-legitimacy filter
keep = true(1, numel(R));
for i = 1:numel(R)
    r = R(i);
    if strcmp(r.threat, 'antenna_fault') && strcmp(r.mechanism, 'field_reduction')
        keep(i) = false;   % wrong units entirely -> always invalid
    elseif strcmp(r.threat, 'path_loss') && strcmp(r.mechanism, 'field_reduction')
        if (r.level - r.magnitude) < 0
            keep(i) = false;   % negative path_loss_db = amplification, not legitimate
        end
    end
    % jamming/reactive_jamming/noise_burst (jsr_db) and spoofing (spoof_sir_db)
    % field_reduction: no filter, negative dB is physically fine here.
    % awgn_margin_boost and atten_reduction: no filter needed.
end

n_excluded = sum(~keep);
R_legit = R(keep);
fprintf('Excluded %d physically-invalid records (%.1f%%). %d legitimate records remain.\n\n', ...
    n_excluded, 100*n_excluded/numel(R), numel(R_legit));

%% 3. Per-threat, per-level diagnostic breakdown (using ONLY legitimate records)
threat_names = unique({R_legit.threat}, 'stable');
report_lines = {};
report_lines{end+1} = '=== DIAGNOSTIC: Best Legitimate Treatment, Per Threat, Per Severity Level ===';
report_lines{end+1} = sprintf('Generated: %s (post-hoc analysis, no re-simulation)', datestr(now));
report_lines{end+1} = '';

fprintf('%-18s %-8s %-20s %10s %14s\n', 'Threat', 'Level', 'Best Mechanism', 'Magnitude', 'Recovery%');
report_lines{end+1} = sprintf('%-18s %-8s %-20s %10s %14s', 'Threat', 'Level', 'Best Mechanism', 'Magnitude', 'Recovery%');

overall_best = struct('threat',{},'mechanism',{},'magnitude',{},'avg_recovery',{});

for t = 1:numel(threat_names)
    tname = threat_names{t};
    cfg_i = threat_cfg(strcmp({threat_cfg.name}, tname));
    mask_t = strcmp({R_legit.threat}, tname);
    sub_t = R_legit(mask_t);

    fprintf('\n');
    report_lines{end+1} = '';

    % --- Per-level diagnosis ---
    for lv = cfg_i.levels
        mask_lv = [sub_t.level] == lv;
        sub_lv = sub_t(mask_lv);
        if isempty(sub_lv)
            fprintf('%-18s %-8g %-20s %10s %14s\n', tname, lv, '(no legit data)', '-', '-');
            continue;
        end

        mechs = unique({sub_lv.mechanism}, 'stable');
        best_avg = -inf; best_mech = ''; best_mag = 0;
        for mi = 1:numel(mechs)
            mag_vals = unique([sub_lv(strcmp({sub_lv.mechanism},mechs{mi})).magnitude]);
            for mv = mag_vals
                idx = strcmp({sub_lv.mechanism},mechs{mi}) & [sub_lv.magnitude]==mv;
                avgr = mean([sub_lv(idx).recovery_pct]);   % averaged over SNR
                if avgr > best_avg
                    best_avg = avgr; best_mech = mechs{mi}; best_mag = mv;
                end
            end
        end

        fprintf('%-18s %-8g %-20s %10.1f %13.1f%%\n', tname, lv, best_mech, best_mag, best_avg);
        report_lines{end+1} = sprintf('%-18s %-8g %-20s %10.1f %13.1f%%', tname, lv, best_mech, best_mag, best_avg);
    end

    % --- Overall best for this threat (across all legit levels) ---
    mechs_all = unique({sub_t.mechanism}, 'stable');
    best_avg_all = -inf; best_mech_all = ''; best_mag_all = 0;
    for mi = 1:numel(mechs_all)
        mag_vals = unique([sub_t(strcmp({sub_t.mechanism},mechs_all{mi})).magnitude]);
        for mv = mag_vals
            idx = strcmp({sub_t.mechanism},mechs_all{mi}) & [sub_t.magnitude]==mv;
            avgr = mean([sub_t(idx).recovery_pct]);
            if avgr > best_avg_all
                best_avg_all = avgr; best_mech_all = mechs_all{mi}; best_mag_all = mv;
            end
        end
    end
    overall_best(end+1) = struct('threat',tname,'mechanism',best_mech_all, ...
        'magnitude',best_mag_all,'avg_recovery',best_avg_all);
end

%% 4. Corrected overall summary (replaces the flawed Section 1 from before)
fprintf('\n\n=== CORRECTED Overall Best Per Threat (legitimate mechanisms only) ===\n');
fprintf('%-18s %-20s %10s %12s\n', 'Threat', 'Best Mechanism', 'Magnitude', 'Avg Recovery%');
report_lines{end+1} = '';
report_lines{end+1} = '=== CORRECTED Overall Best Per Threat (legitimate mechanisms only) ===';
report_lines{end+1} = sprintf('%-18s %-20s %10s %12s', 'Threat', 'Best Mechanism', 'Magnitude', 'Avg Recovery%');

current_best_static = struct('jamming',31.7,'reactive_jamming',33.9,'noise_burst',21.9, ...
    'path_loss',76.9,'spoofing',39.5,'antenna_fault',4.7);

for i = 1:numel(overall_best)
    b = overall_best(i);
    fprintf('%-18s %-20s %10.1f %11.1f%%\n', b.threat, b.mechanism, b.magnitude, b.avg_recovery);
    report_lines{end+1} = sprintf('%-18s %-20s %10.1f %11.1f%%', b.threat, b.mechanism, b.magnitude, b.avg_recovery);
end

fprintf('\n=== CORRECTED Improvement vs Current C1/C3 Static Mitigation ===\n');
fprintf('%-18s %14s %14s %10s\n', 'Threat', 'Current(C3)', 'Best Found', 'Improvement');
report_lines{end+1} = '';
report_lines{end+1} = '=== CORRECTED Improvement vs Current C1/C3 Static Mitigation ===';
report_lines{end+1} = sprintf('%-18s %14s %14s %10s', 'Threat', 'Current(C3)', 'Best Found', 'Improvement');
for i = 1:numel(overall_best)
    b = overall_best(i);
    if isfield(current_best_static, b.threat)
        cur = current_best_static.(b.threat);
        fprintf('%-18s %13.1f%% %13.1f%% %+9.1f%%\n', b.threat, cur, b.avg_recovery, b.avg_recovery-cur);
        report_lines{end+1} = sprintf('%-18s %13.1f%% %13.1f%% %+9.1f%%', b.threat, cur, b.avg_recovery, b.avg_recovery-cur);
    else
        fprintf('%-18s %13s %13.1f%% %10s\n', b.threat, 'N/A (new)', b.avg_recovery, 'N/A');
        report_lines{end+1} = sprintf('%-18s %13s %13.1f%% %10s', b.threat, 'N/A (new)', b.avg_recovery, 'N/A');
    end
end

report_lines{end+1} = '';
report_lines{end+1} = '=== END OF DIAGNOSIS ===';

%% 5. Save corrected report
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/exploration_diagnosis.txt', 'w');
for i = 1:numel(report_lines)
    fprintf(fid, '%s\n', report_lines{i});
end
fclose(fid);
fprintf('\nSaved results/exploration_diagnosis.txt\n');
fprintf('\n=== Diagnostic Analysis Complete ===\n');