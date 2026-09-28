%% DIAGNOSE_ANTENNA_FAULT_REWARD.m
% Investigates the gap between train_dqn.m's single-run reward table
% estimate for antenna_fault (channel_switch=24%) and EXP's multi-run
% finding (atten_reduction=60.5%, same 25dB magnitude, same physical
% mechanism -- both act on fault_atten_db).
%
% Hypothesis: the 24% figure is a noisy single-realization estimate
% (one Rician fading draw), not a stable expected value, causing
% train_dqn's 650-episode training to learn a consistently wrong
% (negative) Q-value for effective actions on this one threat.

close all; clc;
fprintf('=== DIAGNOSE: antenna_fault reward variance across repeated runs ===\n\n');

modelName = 'UAV_GCS_Threat_Link';
N_REPEATS = 8;

% Load the CURRENT params.mat once to capture the untouched baseline
S0 = load('params.mat');
params_orig = S0.params;
baseline_atten = params_orig.fault_atten_db;   % e.g. 30 dB, per project convention

actions = {'no_action','channel_switch','rate_reduce','freq_diversity','spatial_diversity'};
action_mitigation_db = struct('no_action',0,'channel_switch',25,'rate_reduce',15, ...
    'freq_diversity',25,'spatial_diversity',25);

results = nan(N_REPEATS, numel(actions));

for a = 1:numel(actions)
    action_name = actions{a};
    mag = action_mitigation_db.(action_name);
    fprintf('--- Action: %-18s (magnitude=%d dB) ---\n', action_name, mag);

    for r = 1:N_REPEATS
        params = params_orig;                       % fresh copy each run
        params.active_threat  = 'antenna_fault';
        params.fault_atten_db = max(0, baseline_atten - mag);   % physical floor

        save('params.mat', 'params');                % build_threat_model reads THIS
        build_threat_model();                         % no arguments, reads params.mat

        [ber, ~] = quick_ber_with_iq(modelName);
        results(r, a) = ber;
        fprintf('  run %d/%d: BER=%.4e\n', r, N_REPEATS, ber);
    end
end

%% Summary
fprintf('\n=== SUMMARY: mean +/- std BER per action (antenna_fault, %d runs each) ===\n', N_REPEATS);
for a = 1:numel(actions)
    fprintf('  %-18s mean=%.4e  std=%.4e  min=%.4e  max=%.4e  (std/mean=%.1f%%)\n', ...
        actions{a}, mean(results(:,a)), std(results(:,a)), min(results(:,a)), max(results(:,a)), ...
        100*std(results(:,a))/mean(results(:,a)));
end

baseline_mean = mean(results(:,1));
fprintf('\n=== Recovery %% relative to no_action baseline (mean BER=%.4e) ===\n', baseline_mean);
for a = 2:numel(actions)
    recovery = 100 * (baseline_mean - mean(results(:,a))) / baseline_mean;
    fprintf('  %-18s recovery=%.1f%% (train_dqn single-run said 24%% for channel_switch)\n', ...
        actions{a}, recovery);
end

if ~exist('results', 'dir'); mkdir('results'); end
save('results/antenna_fault_reward_variance.mat', 'results', 'actions');
fprintf('\nSaved results/antenna_fault_reward_variance.mat\n');

% Restore original params.mat so this diagnostic run doesn't leave the
% pipeline's shared state file modified for the next script that runs.
params = params_orig;
save('params.mat', 'params');
fprintf('params.mat restored to pre-diagnostic state.\n');