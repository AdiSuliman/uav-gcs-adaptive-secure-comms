%% C2 — TRAIN DQN AGENT
% Trains the DQN on a real, threat-specific reward table (measured via
% actual Simulink runs, not synthetic). Includes reward shaping for
% benign_interference/none (fixed false-alarm penalty) and a post-training
% validation gate that blocks saving an agent that violates that shaping,
% or that fails to react on a real threat.
close all; clc;
fprintf('=== C2: Train DQN Agent ===\n\n');

rng(42, 'twister');   % reproducibility

%% 1. Initialize agent
agent = dqn_agent();

%% 2. Setup: threats, actions
num_episodes = 50;
num_threats = 9;

% Order must match the threat_list inside build_dqn_state.m
threat_list = {'jamming', 'reactive_jamming', 'sweeping_jammer', 'noise_burst', ...
               'path_loss', 'spoofing', 'antenna_fault', 'benign_interference', 'none'};

action_names = agent.action_names;
action_mitigation_db = struct('no_action',0,'channel_switch',25,'rate_reduce',15, ...
    'freq_diversity',25,'spatial_diversity',25);
strength_field = containers.Map( ...
    {'jamming','reactive_jamming','sweeping_jammer','noise_burst','path_loss','antenna_fault','spoofing','benign_interference','none'}, ...
    {'jsr_db', 'jsr_db',           'jsr_db',          'jsr_db',   'path_loss_db','fault_atten_db','spoof_sir_db','benign_int_db','jsr_db'});

init_params;
p0 = load('params.mat').params;
baseline = struct('jsr_db',p0.jsr_db,'path_loss_db',p0.path_loss_db, ...
    'fault_atten_db',p0.fault_atten_db,'spoof_sir_db',p0.spoof_sir_db, ...
    'benign_int_db',p0.benign_int_db);

%% 3. Build reward table (real Simulink runs, 9 threats x 5 actions)
% Also records each threat's baseline BER/RSSI, reused later by the
% validation gate so it checks the agent on real, in-distribution states.
fprintf('Building reward table...\n\n');
reward_table = zeros(num_threats, 5);
ber_after_table = zeros(num_threats, 5);
base_ber = zeros(num_threats, 1);
base_rssi = zeros(num_threats, 1);

for ti = 1:num_threats
    threat = threat_list{ti};
    field = strength_field(threat);

    p = p0; p.jsr_db=baseline.jsr_db; p.path_loss_db=baseline.path_loss_db;
    p.fault_atten_db=baseline.fault_atten_db; p.spoof_sir_db=baseline.spoof_sir_db;
    p.benign_int_db=baseline.benign_int_db;
    p.active_threat = threat;
    params = p; save('params.mat', 'params');
    build_threat_model;

    [ber_before, iq_before] = quick_ber_with_iq('UAV_GCS_Threat_Link');
    ber_before = double(ber_before);
    if ~isempty(iq_before)
        rssi_before = 10*log10(mean(abs(iq_before).^2) + eps);
    else
        rssi_before = -50;
    end
    base_ber(ti) = ber_before;
    base_rssi(ti) = rssi_before;

    fprintf('  %-20s baseline BER=%.3e | ', threat, ber_before);
    for ai = 1:5
        action = action_names{ai};
        mitigation_db = action_mitigation_db.(action);
        p2 = p;
        p2.(field) = baseline.(field) - mitigation_db;
        if any(strcmp(field, {'path_loss_db','fault_atten_db'}))
            p2.(field) = max(p2.(field), 0);
        end
        params = p2; save('params.mat', 'params');
        build_threat_model;
        ber_after = quick_ber('UAV_GCS_Threat_Link');

        recov = 100*(ber_before-ber_after)/max(ber_before,eps);
        reward_table(ti, ai) = recov;
        ber_after_table(ti, ai) = ber_after;
        fprintf('%s=%.0f%% ', action, recov);
    end
    fprintf('\n');

    % Non-hostile classes: reward is fixed, not derived from raw BER
    % recovery. The magnitude of BER improvement is meaningless here --
    % any reaction is a false alarm regardless of how much it happened to
    % reduce BER.
    if any(strcmp(threat, {'benign_interference', 'none'}))
        no_action_idx = find(strcmp(action_names, 'no_action'));
        for ai = 1:5
            if ai == no_action_idx
                reward_table(ti, ai) = 0;
            else
                reward_table(ti, ai) = -40;
            end
        end
        fprintf('  %-20s [reward fixed: no_action=0, all other actions=-40]\n', threat);
    end
end

params = p0; save('params.mat', 'params');

fprintf('\nReward table built. Best action per threat:\n');
for ti = 1:num_threats
    [best_r, best_a] = max(reward_table(ti,:));
    fprintf('  %-20s -> %s (%.0f%% recovery)\n', threat_list{ti}, action_names{best_a}, best_r);
end

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

%% 4. Training loop
training_loss = [];
avg_rewards_per_episode = [];
episode_rewards = [];

oversample_factor = containers.Map(threat_list, {1, 1, 1, 1, 1, 1, 3, 3, 3});
threat_schedule = [];
for ti = 1:num_threats
    threat_schedule = [threat_schedule, repmat(ti, 1, num_episodes * oversample_factor(threat_list{ti}))]; %#ok<AGROW>
end
threat_schedule = threat_schedule(randperm(numel(threat_schedule)));
total_episodes = numel(threat_schedule);

fprintf('Training on %d episodes\n\n', total_episodes);

prev_threat = '';
for ep = 1:total_episodes
    threat_idx = threat_schedule(ep);
    threat = threat_list{threat_idx};
    field = strength_field(threat);

    if ~strcmp(threat, prev_threat)
        fprintf('  Threat: %s\n', threat);
        prev_threat = threat;
    end

    p = p0; p.jsr_db=baseline.jsr_db; p.path_loss_db=baseline.path_loss_db;
    p.fault_atten_db=baseline.fault_atten_db; p.spoof_sir_db=baseline.spoof_sir_db;
    p.benign_int_db=baseline.benign_int_db;
    p.active_threat = threat;
    params = p; save('params.mat', 'params');
    build_threat_model;
    [ber_baseline, iq_rx] = quick_ber_with_iq('UAV_GCS_Threat_Link');
    ber_baseline = double(ber_baseline);

    if ~isempty(iq_rx)
        rssi = 10*log10(mean(abs(iq_rx).^2) + eps);
    else
        rssi = -50;
    end
    snr_val = p.EbNo_dB(1);
    plr = double(ber_baseline > 0.1);

    state = build_dqn_state(threat, ber_baseline, rssi, snr_val, plr);
    action = selectAction(agent, state, true);

    recovery_frac = reward_table(threat_idx, action) / 100;
    ber_after = ber_baseline * (1 - recovery_frac);
    reward = reward_table(threat_idx, action);

    next_state = build_dqn_state(threat, ber_after, -50, 5, 0.05);
    done = 1;

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

%% 5. Post-training validation gate
% Gate A: benign_interference/none must pick no_action (false-alarm check).
% Gate B: every REAL threat must NOT pick no_action (missed-detection check).
% Both use each threat's real baseline BER/RSSI (recorded in Section 3) and
% real training-time SNR, so the check is in-distribution. Refuses to save
% if either gate fails.
fprintf('\nRunning post-training validation gate...\n');
gate_pass = true;

fprintf('  Gate A: non-hostile classes must choose no_action\n');
gate_a_classes = {'benign_interference', 'none'};
for gi = 1:numel(gate_a_classes)
    threat = gate_a_classes{gi};
    ti = find(strcmp(threat_list, threat));
    check_state = build_dqn_state(threat, base_ber(ti), base_rssi(ti), p0.EbNo_dB(1), double(base_ber(ti) > 0.1));
    state_dl = dlarray(single(check_state), 'CB');
    qvals = extractdata(predict(agent.qNetwork, state_dl));
    [~, chosen] = max(qvals);
    chosen_action = action_names{chosen};
    fprintf('    %-20s -> %-16s (no_action Q=%.2f, chosen Q=%.2f)\n', ...
        threat, chosen_action, qvals(1), qvals(chosen));
    if ~strcmp(chosen_action, 'no_action')
        gate_pass = false;
    end
end

fprintf('  Gate B: real threats must NOT choose no_action\n');
gate_b_classes = setdiff(threat_list, gate_a_classes, 'stable');
for gi = 1:numel(gate_b_classes)
    threat = gate_b_classes{gi};
    ti = find(strcmp(threat_list, threat));
    check_state = build_dqn_state(threat, base_ber(ti), base_rssi(ti), p0.EbNo_dB(1), double(base_ber(ti) > 0.1));
    state_dl = dlarray(single(check_state), 'CB');
    qvals = extractdata(predict(agent.qNetwork, state_dl));
    [~, chosen] = max(qvals);
    chosen_action = action_names{chosen};
    fprintf('    %-20s -> %-16s (no_action Q=%.2f, chosen Q=%.2f)\n', ...
        threat, chosen_action, qvals(1), qvals(chosen));
    if strcmp(chosen_action, 'no_action')
        gate_pass = false;
    end
end

if ~gate_pass
    error(['Validation gate FAILED -- see per-class breakdown above. Either a ' ...
           'non-hostile class chose an action other than no_action (false ' ...
           'alarm), or a real threat chose no_action (missed detection). ' ...
           'NOT saving trained_dqn.mat -- rerun this script (try a ' ...
           'different rng seed if it fails repeatedly).']);
end
fprintf('Validation gate PASSED.\n\n');

%% 6. Save
fprintf('Training complete. Saving agent...\n');
save('data/trained_dqn.mat', 'agent', 'reward_table', 'threat_list', 'action_names', '-v7.3');

%% 7. Plot training curves
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
    title('DQN Average Episode Reward'); grid on;
end
sgtitle('C2: DQN Training Curves');
saveas(fig, 'results/dqn_training_curves.png');
fprintf('Saved results/dqn_training_curves.png\n');
close(fig);

fprintf('\n=== C2 Complete ===\n');

%% Helper functions
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