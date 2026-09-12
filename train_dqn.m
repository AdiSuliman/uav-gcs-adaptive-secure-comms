%% C2 — TRAIN DQN: Offline training on collected threat episodes
% For each threat: run a simulated episode (build threat model, measure BER),
% collect (state, action, reward, next_state) transitions, train the Q-network
% via mini-batch gradient descent.
%
% Simplified offline training (no real-time Simulink loop yet — that's C3).
% Here we collect synthetic episodes and learn from them.
%
% Output: trained_dqn.mat (agent after training)
%         results/dqn_training_curves.png (loss + avg_reward)

close all; clc;
fprintf('=== C2: Train DQN Agent ===\n\n');

%% 1. Initialize agent
agent = dqn_agent();

%% 2. Training parameters
num_episodes = 50;      % episodes per threat family
num_threats = 6;
total_episodes = num_episodes * num_threats;

threat_list = {'jamming', 'reactive_jamming', 'noise_burst', ...
               'path_loss', 'spoofing', 'antenna_fault'};
threat_encode = [0 1 2 3 4 5];  % encoding for state

init_params;
p = load('params.mat').params;

% Track training progress
training_loss = [];
avg_rewards_per_episode = [];
episode_rewards = [];

fprintf('Training on %d episodes (%d threats × %d episodes each)\n\n', ...
    total_episodes, num_threats, num_episodes);

%% 3. Collect episodes and train
for ep = 1:total_episodes
    threat_idx = mod(ep - 1, num_threats) + 1;
    threat = threat_list{threat_idx};
    threat_enc = threat_encode(threat_idx);
    
    if mod(ep, num_episodes) == 1
        fprintf('  Threat: %s\n', threat);
    end
    
    % --- Simulate this threat episode ---
    p.active_threat = threat;
    save('params.mat', 'p', '-append');
    build_threat_model;
    ber_baseline = quick_ber('UAV_GCS_Threat_Link');
    
    % --- Mock state (synthetic for now) ---
    % In C3, this comes from real CNN detector + link metrics
    state = [threat_enc; ber_baseline; -50; 5; 0.1];  % [threat, BER, RSSI, SNR, PLR]
    
    % --- Agent selects action (epsilon-greedy) ---
    action = selectAction(agent, state, true);
    
    % --- Simulate countermeasure effect (simplified) ---
    % Action quality: better actions → better (lower) BER
    action_effectiveness = [0, 0.4, 0.3, 0.35, 0.4];  % per action (no_action=0, others=0.3-0.4)
    ber_after = ber_baseline * (1 - action_effectiveness(action));
    
    % --- Reward: BER improvement (negative = lower is better) ---
    reward = (ber_baseline - ber_after) / ber_baseline * 100;  % % improvement
    
    % --- Next state (after action) ---
    next_state = [threat_enc; ber_after; -50; 5; 0.05];
    done = 1;  % episode ends after one step (simplified)
    
    % --- Store in replay buffer ---
    agent.replay_buffer.states = [agent.replay_buffer.states; state'];
    agent.replay_buffer.actions = [agent.replay_buffer.actions; action];
    agent.replay_buffer.rewards = [agent.replay_buffer.rewards; reward];
    agent.replay_buffer.next_states = [agent.replay_buffer.next_states; next_state'];
    agent.replay_buffer.dones = [agent.replay_buffer.dones; done];
    
    episode_rewards(ep) = reward;
    
    % --- Train on random mini-batch ---
    if size(agent.replay_buffer.states, 1) >= agent.batch_size
        batch_idx = randperm(size(agent.replay_buffer.states, 1), agent.batch_size);
        
        S = single(agent.replay_buffer.states(batch_idx, :)');
        A = agent.replay_buffer.actions(batch_idx);
        R = single(agent.replay_buffer.rewards(batch_idx)');
        S_next = single(agent.replay_buffer.next_states(batch_idx, :)');
        Done = single(agent.replay_buffer.dones(batch_idx)');
        
        % Compute target Q-values
        Q_next = predict(agent.qNetwork, dlarray(S_next, 'CB'));
        Q_max_next = max(extractdata(Q_next), [], 1);
        target = R + agent.gamma * Q_max_next .* (1 - Done);
        
        % Gradient step on Q-network
        [loss, grads, ~] = dlfeval(@qLoss, agent.qNetwork, dlarray(S, 'CB'), A, target);
        agent.qNetwork = adamupdate(agent.qNetwork, grads, [], [], 1, agent.learning_rate);
        
        training_loss(end+1) = double(extractdata(loss));
    end
    
    % Decay epsilon
    agent.epsilon = max(agent.epsilon_min, agent.epsilon * agent.epsilon_decay);
    
    if mod(ep, 10) == 0
        avg_reward = mean(episode_rewards(max(1, ep-9):ep));
        avg_rewards_per_episode(end+1) = avg_reward;
        fprintf('    Episode %3d/%d: reward=%.1f%%, epsilon=%.3f\n', ...
            ep, total_episodes, avg_reward, agent.epsilon);
    end
end

fprintf('\nTraining complete. Saving agent...\n');
save('data/trained_dqn.mat', 'agent', '-v7.3');

%% 4. Plot training curves
fig = figure('Position', [100 100 900 400], 'Color', 'w');

subplot(1, 2, 1);
if ~isempty(training_loss)
    plot(training_loss, 'b-', 'LineWidth', 1.5);
    xlabel('Training Step'); ylabel('Q-Loss');
    title('DQN Training Loss');
    grid on;
end

subplot(1, 2, 2);
if ~isempty(avg_rewards_per_episode)
    plot(1:numel(avg_rewards_per_episode), avg_rewards_per_episode, 'g-', 'LineWidth', 1.5);
    xlabel('Episode (×10)'); ylabel('Avg Reward (% BER improvement)');
    title('DQN Average Episode Reward');
    grid on;
end

sgtitle('C2: DQN Training Curves');
if ~exist('results', 'dir'), mkdir('results'); end
saveas(fig, 'results/dqn_training_curves.png');
fprintf('Saved results/dqn_training_curves.png\n');
close(fig);

fprintf('\n=== C2 Complete ===\n');

%% Helper: Q-loss function
function [loss, gradients, state] = qLoss(qNet, S, A, target)
    [Q_pred, state] = forward(qNet, S);
    % Select Q-values for taken actions
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