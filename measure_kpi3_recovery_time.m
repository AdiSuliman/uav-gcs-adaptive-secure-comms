%% MEASURE_KPI3_RECOVERY_TIME.m — proposal KPI #3: DQN vs Rule-Based decision speed
%
% REFRAMED (2026-09-16): the original version of this script simulated
% "recovery cycles" with a mock BER-halving loop that never called sim() or
% consulted either policy's actual action choice -- the reported cycle counts
% were identical for DQN and Rule-Based regardless of which was "tested",
% because nothing in the loop actually depended on the policy at all.
%
% Root cause of why "cycles" was the wrong framing to begin with: in this
% system, every countermeasure action applies a FIXED, ONE-SHOT dB mitigation
% (action_mitigation_db, see rule_based_policy.m / run_closed_loop_*.m) to the
% threat's severity field. Both DQN and Rule-Based are deterministic policies
% -- given a fixed state, each picks exactly one action and converges
% immediately. There is no real iterative "cycles to converge" dynamic in
% this architecture to measure.
%
% What DOES meaningfully differ between the two policies, and IS already
% measured with real data, is DECISION SPEED: Rule-Based is a lookup table
% (a few dB and a switch-case -- effectively instant); DQN is a real neural
% network forward pass (a few ms). This script measures that directly:
%   - Rule-based latency: REAL timed call to rule_based_policy.m per threat
%   - DQN latency + rule agreement + recovery: pulled from the STRUCT saved
%     in results/closed_loop_diagnostic_results.mat by
%     run_closed_loop_diagnostic.m -- not parsed from the .txt report.
%
% FIX (2026-09-19): the previous version parsed closed_loop_diagnostic_report.txt
% with strsplit(txt,'--- Threat: ') and several regexes tuned to an OLDER
% report layout. The report format changed when the sliding-window fix (D16)
% was added (blocks are now "--- <threat> @ SNR=<x> dB ---", one per
% threat-SNR pair, not one per threat) -- the old parsing silently matched
% nothing and made this script throw "Could not parse any threat blocks".
% Reading the .mat struct directly is immune to any future report-text
% reformatting, since it is the same struct run_closed_loop_diagnostic.m
% already builds and saves.
%
% Each threat has one DQN/recovery data point per SNR (run_closed_loop_diagnostic.m
% sweeps all SNR points); this script averages across SNR to report one
% representative row per threat, and also reports the full-sweep means.
%
% Output: results/kpi3_measurement.txt

close all; clc;
fprintf('=== KPI #3: Decision Speed (DQN vs Rule-Based) ===\n\n');

MAX_STALE_DAYS = 0.5;   % 12 hours -- the pipeline changes faster than days

%% 1. Ensure a fresh diagnostic .mat exists (real Simulink+CNN+DQN data)
mat_path = 'results/closed_loop_diagnostic_results.mat';
need_rerun = ~exist(mat_path, 'file');
if ~need_rerun
    d = dir(mat_path);
    need_rerun = (now - datenum(d.date)) > MAX_STALE_DAYS;
end
if need_rerun
    fprintf('No fresh %s found -- running run_closed_loop_diagnostic...\n', mat_path);
    run_closed_loop_diagnostic;
end

L = load(mat_path, 'results');
res = L.results;
if isempty(res)
    error('results/closed_loop_diagnostic_results.mat contains an empty results struct.');
end

%% 2. Aggregate per-threat (averaged across the SNR sweep)
threats = unique({res.threat}, 'stable');
n = numel(threats);

dqn_latency_ms = zeros(1, n);
recovery_pct   = zeros(1, n);
agrees_frac    = zeros(1, n);
rule_action    = cell(1, n);

for i = 1:n
    mask = strcmp({res.threat}, threats{i});
    sub  = res(mask);
    dqn_latency_ms(i) = mean([sub.dqn_latency_ms]);
    recovery_pct(i)   = mean([sub.recovery_pct], 'omitnan');
    agrees_frac(i)    = mean([sub.agrees_with_rule]);
    rule_action{i}    = sub(1).rule_based_action;   % rule policy doesn't depend on SNR
end

fprintf('Loaded %d threats (SNR-averaged) from %s\n\n', n, mat_path);

%% 3. Time the REAL rule_based_policy.m call per threat (actual execution, not mocked)
rule_latency_ms = zeros(1, n);
N_TIMING_REPEATS = 1000;   % lookup is sub-ms; repeat and average for a stable reading
for i = 1:n
    t0 = tic;
    for r = 1:N_TIMING_REPEATS
        [~, ~] = rule_based_policy(threats{i});
    end
    rule_latency_ms(i) = (toc(t0) / N_TIMING_REPEATS) * 1000;
end

%% 4. Report
report = {};
report{end+1} = '=== KPI #3: Decision Speed (DQN vs Rule-Based) ===';
report{end+1} = sprintf('Generated: %s', datestr(now));
report{end+1} = '';
report{end+1} = 'NOTE: "recovery cycles" is not a meaningful metric for this architecture --';
report{end+1} = 'every action applies a fixed one-shot dB mitigation and both policies are';
report{end+1} = 'deterministic, so both converge in exactly 1 decision regardless of policy.';
report{end+1} = 'The metric that actually differs is DECISION LATENCY (real, timed below).';
report{end+1} = '';
report{end+1} = 'DQN latency/recovery/agreement are averaged across the full SNR sweep';
report{end+1} = '(each threat has one data point per SNR point in the diagnostic run).';
report{end+1} = '';
report{end+1} = sprintf('%-22s %14s %14s %10s %10s', 'Threat', 'DQN (ms)', 'Rule (ms)', 'Agree%', 'Recov%');
for i = 1:n
    if isnan(recovery_pct(i))
        report{end+1} = sprintf('%-22s %14.3f %14.5f %9.0f%% %10s', ...
            threats{i}, dqn_latency_ms(i), rule_latency_ms(i), 100*agrees_frac(i), 'N/A');
    else
        report{end+1} = sprintf('%-22s %14.3f %14.5f %9.0f%% %9.1f%%', ...
            threats{i}, dqn_latency_ms(i), rule_latency_ms(i), 100*agrees_frac(i), recovery_pct(i));
    end
end
report{end+1} = '';
report{end+1} = sprintf('Mean DQN latency:  %.3f ms', mean(dqn_latency_ms));
report{end+1} = sprintf('Mean Rule latency: %.5f ms', mean(rule_latency_ms));
report{end+1} = sprintf('Speed ratio: Rule-Based is ~%.0fx faster than DQN (lookup table vs neural net inference)', ...
    mean(dqn_latency_ms) / mean(rule_latency_ms));
report{end+1} = sprintf('DQN-vs-Rule agreement (overall, all threats x SNR): %.1f%%', 100*mean(agrees_frac));
report{end+1} = '';
report{end+1} = 'CAVEAT: agreement compares only the chosen ACTION NAME between policies.';
report{end+1} = 'rule_based_policy.m''s own per-threat mitigation_db values are computed but';
report{end+1} = 'never applied to any BER calculation -- both policies'' physical mitigation';
report{end+1} = 'effect goes through the same action_mitigation_db (25/15/25/25 dB). This is';
report{end+1} = 'a decision-policy comparison, not two independently-realized countermeasure';
report{end+1} = 'systems (see docs/DECISIONS.md).';
report{end+1} = '';
report{end+1} = 'Interpretation: Rule-Based is effectively instant (a dB lookup); DQN costs a';
report{end+1} = 'few ms of real neural-network inference. This is the genuine speed trade-off';
report{end+1} = 'of using a learned policy over a static one in this system -- DQN''s value is';
report{end+1} = 'not faster convergence (both converge in 1 step) but rather the potential to';
report{end+1} = 'learn better-than-rule-based action choices from data (measured separately as';
report{end+1} = 'recovery%% and agreement rate above).';

if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/kpi3_measurement.txt', 'w');
for i = 1:numel(report), fprintf(fid, '%s\n', report{i}); end
fclose(fid);
for i = 1:numel(report), fprintf('%s\n', report{i}); end
fprintf('\nSaved results/kpi3_measurement.txt\n');
fprintf('\n=== KPI #3 Complete ===\n');