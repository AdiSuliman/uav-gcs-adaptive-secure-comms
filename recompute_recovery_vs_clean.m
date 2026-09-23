%% RECOMPUTE_RECOVERY_VS_CLEAN.m — KPI #2 re-scored against the no-attack link
% Post-processing only, no simulation. Re-scores the saved closed-loop and
% speed-robustness results with recovery relative to the clean-link BER (the
% proposal's KPI #2 definition), side by side with the current before/after
% metric, over exactly the same runs.
%
% Clean reference: the 'none' run at the same Eb/N0 (and speed) inside the
% same result set. The EXP clean BER is printed next to it as a cross-check.
%
% Inputs : results/closed_loop_diagnostic_results.mat
%          results/speed_robustness.mat          (optional)
%          data/survivability_boundary.mat       (optional: thresholds, EXP clean BER)
% Outputs: results/recovery_vs_clean.txt, results/recovery_vs_clean.mat

%% Setup
R_OK = 2; R_MARG = 5;
S = struct();
if isfile('data/survivability_boundary.mat')
    S = load('data/survivability_boundary.mat');
    if isfield(S, 'RATIO_RECOVERABLE'), R_OK   = S.RATIO_RECOVERABLE; end
    if isfield(S, 'RATIO_MARGINAL'),    R_MARG = S.RATIO_MARGINAL;    end
end
nonHostile = {'benign_interference', 'none'};
report = {};
report{end+1} = '=== KPI #2 re-scored against the no-attack (clean) link ===';
report{end+1} = sprintf('Old metric: 100*(before-after)/before   New metric: 100*(before-after)/(before-clean), capped at 100');
report{end+1} = sprintf('Link verdict thresholds: ratio after/clean <= %g recoverable, <= %g marginal', R_OK, R_MARG);
report{end+1} = '';

%% Closed-loop diagnostic: clean reference per Eb/N0
C  = load('results/closed_loop_diagnostic_results.mat');
cl = C.results;
snr_cl = C.SNR_points;
clean_cl = nan(size(snr_cl));
for s = 1:numel(snr_cl)
    m = strcmp({cl.threat}, 'none') & [cl.snr_db] == snr_cl(s);
    if any(m), clean_cl(s) = mean([cl(m).ber_before]); end
end

report{end+1} = '--- Clean-link BER reference (closed-loop none runs vs EXP) ---';
for s = 1:numel(snr_cl)
    expTxt = 'n/a';
    if isfield(S, 'ber_clean') && isfield(S, 'SNR_points')
        k = find(S.SNR_points == snr_cl(s), 1);
        if ~isempty(k), expTxt = sprintf('%.3e', S.ber_clean(k)); end
    end
    report{end+1} = sprintf('  Eb/N0 %4g dB : none-run %.3e | EXP %s', snr_cl(s), clean_cl(s), expTxt); %#ok<SAGROW>
end
report{end+1} = '';

%% Closed-loop diagnostic: per-run scoring
n = numel(cl);
cl_new = nan(1, n); cl_ratio = nan(1, n); cl_missed = false(1, n);
for i = 1:n
    if ismember(cl(i).threat, nonHostile), continue; end
    s = find(snr_cl == cl(i).snr_db, 1);
    if isempty(s), continue; end
    if strcmp(cl(i).dqn_action, 'no_action')
        cl_missed(i) = true;
        cl_ratio(i)  = cl(i).ber_before / clean_cl(s);
        continue;
    end
    [cl_new(i), cl_ratio(i)] = recovery_vs_clean(cl(i).ber_before, cl(i).ber_after, clean_cl(s));
end

report{end+1} = '--- Closed loop, 9 threats x 6 Eb/N0 (runs with an active countermeasure) ---';
report{end+1} = sprintf('  %-20s %4s %9s %9s %11s %6s %6s %6s', 'threat', 'n', 'old', 'new', 'ratio(mean)', 'rec', 'marg', 'fail');
threats_real = setdiff(C.threats, nonHostile, 'stable');
per_old = nan(1, numel(threats_real)); per_new = per_old;
for t = 1:numel(threats_real)
    m = strcmp({cl.threat}, threats_real{t}) & ~cl_missed;
    r = cl_ratio(m);
    per_old(t) = mean([cl(m).recovery_pct], 'omitnan');
    per_new(t) = mean(cl_new(m), 'omitnan');
    report{end+1} = sprintf('  %-20s %4d %8.1f%% %8.1f%% %10.2fx %6d %6d %6d', threats_real{t}, sum(m), ...
        per_old(t), per_new(t), mean(r, 'omitnan'), sum(r <= R_OK), sum(r > R_OK & r <= R_MARG), sum(r > R_MARG)); %#ok<SAGROW>
end
act = ~ismember({cl.threat}, nonHostile) & ~cl_missed;
report{end+1} = sprintf('  KPI #2 per-run mean      : old %.1f%% -> new %.1f%%', ...
    mean([cl(act).recovery_pct], 'omitnan'), mean(cl_new(act), 'omitnan'));
report{end+1} = sprintf('  KPI #2 mean of per-threat: old %.1f%% -> new %.1f%%', ...
    mean(per_old, 'omitnan'), mean(per_new, 'omitnan'));
report{end+1} = sprintf('  Link restored (ratio <= %g): %d/%d runs', R_OK, sum(cl_ratio(act) <= R_OK), sum(act));
for i = find(cl_missed)
    report{end+1} = sprintf('  Missed (no_action on a real threat): %s @ %g dB, BER %.1fx clean', ...
        cl(i).threat, cl(i).snr_db, cl_ratio(i)); %#ok<SAGROW>
end
report{end+1} = '';

out.closed_loop = struct('clean_ber', clean_cl, 'snr', snr_cl, 'rec_new', cl_new, ...
    'ratio', cl_ratio, 'missed', cl_missed, 'threats', {threats_real}, 'per_old', per_old, 'per_new', per_new);

%% Speed robustness: clean reference per (speed, Eb/N0) and per-speed scoring
if isfile('results/speed_robustness.mat')
    V  = load('results/speed_robustness.mat');
    sr = V.results;
    m_ns = numel(sr);
    sr_new = nan(1, m_ns); sr_ratio = nan(1, m_ns); sr_act = false(1, m_ns);
    for i = 1:m_ns
        if ismember(sr(i).threat, nonHostile) || strcmp(sr(i).dqn_action, 'no_action'), continue; end
        m = strcmp({sr.threat}, 'none') & [sr.speed_kmh] == sr(i).speed_kmh & [sr.snr_db] == sr(i).snr_db;
        if ~any(m), continue; end
        sr_act(i) = true;
        [sr_new(i), sr_ratio(i)] = recovery_vs_clean(sr(i).ber_before, sr(i).ber_after, mean([sr(m).ber_before]));
    end

    report{end+1} = '--- Speed robustness (runs with an active countermeasure) ---';
    report{end+1} = sprintf('  %8s %9s %9s %14s', 'km/h', 'old', 'new', 'restored');
    speeds = V.SPEEDS_KMH;
    for k = 1:numel(speeds)
        m = sr_act & [sr.speed_kmh] == speeds(k);
        report{end+1} = sprintf('  %8.1f %8.1f%% %8.1f%% %8d/%-5d', speeds(k), ...
            mean([sr(m).recovery_pct], 'omitnan'), mean(sr_new(m), 'omitnan'), ...
            sum(sr_ratio(m) <= R_OK), sum(m)); %#ok<SAGROW>
    end
    report{end+1} = sprintf('  Overall: old %.1f%% -> new %.1f%%', ...
        mean([sr(sr_act).recovery_pct], 'omitnan'), mean(sr_new(sr_act), 'omitnan'));
    report{end+1} = '';
    out.speed = struct('rec_new', sr_new, 'ratio', sr_ratio, 'active', sr_act);
end

%% Save
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/recovery_vs_clean.txt', 'w');
fprintf(fid, '%s\n', report{:});
fclose(fid);
fprintf('%s\n', report{:});
save('results/recovery_vs_clean.mat', 'out', 'R_OK', 'R_MARG');
fprintf('Saved results/recovery_vs_clean.txt and .mat\n');