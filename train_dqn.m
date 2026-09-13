%% C2 — TRAIN DQN: Offline training with REAL threat-specific reward table
% FIX (v2): the original synthetic reward (action_effectiveness = [0,0.4,0.3,0.35,0.4],
% identical for every threat) made the agent learn a single "generalist" action
% regardless of threat -- confirmed by C3-diagnostic showing only 12.5% agreement
% with rule-based policy. This version pre-computes a REAL 8-threat x 5-action
% reward table via actual Simulink runs (using the SAME action_mitigation_db
% and per-threat strength fields as run_closed_loop_with_detector.m), so the
% agent now learns genuinely threat-differentiated Q-values.
%
% Output: trained_dqn.mat (agent after training)
%         results/dqn_training_curves.png (loss + avg_reward)
%         results/dqn_reward_table.png (heatmap of the real threat x action table)

close all; clc;
fprintf('=== C2: Train DQN Agent (v2 — real threat-specific reward) ===\n\n');

%% 1. Initialize agent
agent = dqn_agent();

%% 2. Setup
num_episodes = 50;      % episodes per threat family
num_threats = 8;
total_episodes = num_episodes * num_threats;

threat_list = {'jamming', 'reactive_jamming', 'sweeping_jammer', 'noise_burst', ...
               'path_loss', 'spoofing', 'antenna_fault', 'benign_interference'};
threat_encode = [0 1 2 3 4 5 6 7];  % matches dqn_agent.m stateSpec [0,7]

action_names = agent.action_names;   % {'no_action','channel_switch','rate_reduce','freq_diversity','spatial_diversity'}
action_mitigation_db = struct('no_action',0,'channel_switch',15,'rate_reduce',8, ...
    'freq_diversity',8,'spatial_diversity',12);
strength_field = containers.Map( ...
    {'jamming','reactive_jamming','sweeping_jammer','noise_burst','path_loss','antenna_fault','spoofing','benign_interference'}, ...
    {'jsr_db', 'jsr_db',           'jsr_db',          'jsr_db',   'path_loss_db','fault_atten_db','spoof_sir_db','benign_int_db'});

init_params;
p0 = load('params.mat').params;
baseline = struct('jsr_db',p0.jsr_db,'path_loss_db',p0.path_loss_db, ...
    'fault_atten_db',p0.fault_atten_db,'spoof_sir_db',p0.spoof_sir_db, ...
    'benign_int_db',p0.benign_int_db);

%% 3. Pre-compute REAL threat x action reward table (8 threats x 5 actions = 40 combos)
fprintf('Building real threat-specific reward table (40 combos, real Simulink runs)...\n\n');
reward_table = zeros(num_threats, 5);   % recovery_pct
ber_after_table = zeros(num_threats, 5);

for ti = 1:num_threats
    threat = threat_list{ti};
    field = strength_field(threat);

    % Baseline (no countermeasure)
    p = p0; p.jsr_db=baseline.jsr_db; p.path_loss_db=baseline.path_loss_db;
    p.fault_atten_db=baseline.fault_atten_db; p.spoof_sir_db=baseline.spoof_sir_db;
    p.benign_int_db=baseline.benign_int_db;
    p.active_threat = threat;
    params = p; save('params.mat', 'params');
    build_threat_model;
    ber_before = quick_ber('UAV_GCS_Threat_Link');

    fprintf('  %-20s baseline BER=%.3e | ', threat, ber_before);
    for ai = 1:5
        action = action_names{ai};
        mitigation_db = action_mitigation_db.(action);
        p2 = p;
        p2.(field) = baseline.(field) - mitigation_db;
        params = p2; save('params.mat', 'params');
        build_threat_model;
        ber_after = quick_ber('UAV_GCS_Threat_Link');

        recov = 100*(ber_before-ber_after)/max(ber_before,eps);
        reward_table(ti, ai) = recov;
        ber_after_table(ti, ai) = ber_after;
        fprintf('%s=%.0f%% ', action, recov);
    end
    fprintf('\n');
end

% Restore baseline
params = p0; save('params.mat', 'params');

fprintf('\nReward table built. Best action per threat (for sanity check):\n');
for ti = 1:num_threats
    [best_r, best_a] = max(reward_table(ti,:));
    fprintf('  %-20s -> %s (%.0f%% recovery)\n', threat_list{ti}, action_names{best_a}, best_r);
end

% Save + plot the reward table as a heatmap (useful diagnostic for the report)
fig0 = figure('Position',[100 100 700 500],'Color','w');
imagesc(reward_table); colorbar;
set(gca, 'XTick', 1:5, 'XTickLabel', action_names, 'XTickLabelRotation', 25, ...
    'YTick', 1:num_threats, 'YTickLabel', threat_list);
title('Real Reward Table: Recovery % per (Threat, Action)');
xlabel('Action'); ylabel('Threat');
for ti = 1:num_threats
    for ai = 1:5
        text(ai, ti, sprintf('%.0f', reward_table(ti,ai)), 'HorizontalAlignment','center', 'Color','w');
    end
end
if ~exist('results', 'dir'), mkdir('results'); end
saveas(fig0, 'results/dqn_reward_table.png');
close(fig0);
fprintf('\nSaved results/dqn_reward_table.png\n\n');

%% 4. Training loop — now draws reward from the REAL table (threat-differentiated)
training_loss = [];
avg_rewards_per_episode = [];
episode_rewards = [];

fprintf('Training on %d episodes (%d threats x %d episodes each)\n\n', ...
    total_episodes, num_threats, num_episodes);

for ep = 1:total_episodes
    threat_idx = mod(ep - 1, num_threats) + 1;
    threat = threat_list{threat_idx};
    threat_enc = threat_encode(threat_idx);
    field = strength_field(threat);

    if mod(ep, num_episodes) == 1
        fprintf('  Threat: %s\n', threat);
    end

    % --- Fresh baseline BER this episode (real per-episode noise realization) ---
    p = p0; p.jsr_db=baseline.jsr_db; p.path_loss_db=baseline.path_loss_db;
    p.fault_atten_db=baseline.fault_atten_db; p.spoof_sir_db=baseline.spoof_sir_db;
    p.benign_int_db=baseline.benign_int_db;
    p.active_threat = threat;
    params = p; save('params.mat', 'params');
    build_threat_model;
    ber_baseline = quick_ber('UAV_GCS_Threat_Link');

    state = [threat_enc; ber_baseline; -50; 5; 0.1];

    % --- Agent selects action (epsilon-greedy) ---
    action = selectAction(agent, state, true);

    % --- REAL, threat-specific effectiveness (from pre-computed table) ---
    recovery_frac = reward_table(threat_idx, action) / 100;
    ber_after = ber_baseline * (1 - recovery_frac);
    reward = reward_table(threat_idx, action);   % use real recovery% directly as reward

    next_state = [threat_enc; ber_after; -50; 5; 0.05];
    done = 1;

    % --- Store + train (unchanged from v1) ---
    agent.replay_buffer.states = [agent.replay_buffer.states; state'];
    agent.replay_buffer.actions = [agent.replay_buffer.actions; action];
    agent.replay_buffer.rewards = [agent.replay_buffer.rewards; reward];
    agent.replay_buffer.next_states = [agent.replay_buffer.next_states; next_state'];
    agent.replay_buffer.dones = [agent.replay_buffer.dones; done];

    episode_rewards(ep) = reward;

    if size(agent.replay_buffer.states, 1) >= agent.batch_size
        batch_idx = randperm(size(agent.replay_buffer.states, 1), agent.batch_size);

        S = single(agent.replay_buffer.states(batch_idx, :)');
        A = agent.replay_buffer.actions(batch_idx);
        R = single(agent.replay_buffer.rewards(batch_idx)');
        S_next = single(agent.replay_buffer.next_states(batch_idx, :)');
        Done = single(agent.replay_buffer.dones(batch_idx)');

        Q_next = predict(agent.qNetwork, dlarray(S_next, 'CB'));
        Q_max_next = max(extractdata(Q_next), [], 1);
        target = R + agent.gamma * Q_max_next .* (1 - Done);

        [loss, grads, ~] = dlfeval(@qLoss, agent.qNetwork, dlarray(S, 'CB'), A, target);
        agent.qNetwork = adamupdate(agent.qNetwork, grads, [], [], 1, agent.learning_rate);

        training_loss(end+1) = double(extractdata(loss));
    end

    agent.epsilon = max(agent.epsilon_min, agent.epsilon * agent.epsilon_decay);

    if mod(ep, 10) == 0
        avg_reward = mean(episode_rewards(max(1, ep-9):ep));
        avg_rewards_per_episode(end+1) = avg_reward;
        fprintf('    Episode %3d/%d: reward=%.1f%%, epsilon=%.3f\n', ...
            ep, total_episodes, avg_reward, agent.epsilon);
    end
end

params = p0; save('params.mat', 'params');

fprintf('\nTraining complete. Saving agent...\n');
save('data/trained_dqn.mat', 'agent', 'reward_table', 'threat_list', 'action_names', '-v7.3');

%% 5. Plot training curves
fig = figure('Position', [100 100 900 400], 'Color', 'w');
subplot(1, 2, 1);
if ~isempty(training_loss)
    plot(training_loss, 'b-', 'LineWidth', 1.5);
    xlabel('Training Step'); ylabel('Q-Loss'); title('DQN Training Loss'); grid on;
end
subplot(1, 2, 2);
if ~isempty(avg_rewards_per_episode)
    plot(1:numel(avg_rewards_per_episode), avg_rewards_per_episode, 'g-', 'LineWidth', 1.5);
    xlabel('Episode (x10)'); ylabel('Avg Reward (% BER improvement, real)');
    title('DQN Average Episode Reward (real, threat-specific)'); grid on;
end
sgtitle('C2: DQN Training Curves (v2 — real reward)');
saveas(fig, 'results/dqn_training_curves.png');
fprintf('Saved results/dqn_training_curves.png\n');
close(fig);

fprintf('\n=== C2 Complete (v2: threat-differentiated reward) ===\n');

%% Helper: Q-loss function
function [loss, gradients, state] = qLoss(qNet, S, A, target)
    [Q_pred, state] = forward(qNet, S);
    batch_size = size(A, 1);
    idx = sub2ind([size(Q_pred, 1), batch_size], A(:)', 1:batch_size);
    Q_selected = Q_pred(idx);
    loss = mean((Q_selected - target).^2, 'all');
    gradients = dlgradient(loss, qNet.Learnables);
end

function y = selectAction(agent, state, training)
    if training && rand() < agent.epsilon
        y = randi(5);
    else
        state_dl = dlarray(single(state), 'CB');
        qvals = predict(agent.qNetwork, state_dl);
        [~, y] = max(extractdata(qvals), [], 1);
    end
end