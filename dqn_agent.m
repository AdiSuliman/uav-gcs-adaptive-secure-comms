%% C2 — DQN AGENT: Deep Q-Network for Adaptive Countermeasure Selection
% Learns to map threat state → optimal countermeasure action
% State: [threat_class_encoded, BER, RSSI, SNR, PLR] (5-dim)
% Actions: {no_action, channel_switch, rate_reduce, freq_diversity, spatial_diversity} (5 discrete)
% Reward: BER improvement (ΔBer) when action applied
%
% Architecture: 2-layer FC network (state → 64 → 32 → Q(s,a))
% Training: offline (batch) from collected (state, action, reward, next_state) tuples
% Usage: train_dqn.m builds the dataset; this file constructs + initializes the network

function agent = dqn_agent()
    fprintf('=== C2: Initializing DQN Agent ===\n\n');

    %% 1. Define state and action specs
    % State: 5-dim vector [threat_encoded, BER, RSSI, SNR, PLR]
    %   threat_encoded: 0-5 (6 threats: jamming, reactive, spoofing, path_loss, burst, fault)
    %   BER, RSSI, SNR, PLR: continuous observations
    numStates = 5;
    
    % Actions: 5 discrete (0-4)
    %   0: no_action
    %   1: channel_switch
    %   2: rate_reduce
    %   3: freq_diversity
    %   4: spatial_diversity
    numActions = 5;
    action_names = {'no_action', 'channel_switch', 'rate_reduce', 'freq_diversity', 'spatial_diversity'};
    
    stateSpec = rlNumericSpec([numStates 1], 'Lower', [0 0 0 0 0]', 'Upper', [5 1 0 20 1]');
    stateSpec.Name = 'threat_state';
    stateSpec.Description = 'threat_encoded, BER, RSSI, SNR, PLR';
    
    actionSpec = rlFiniteSetSpec({1, 2, 3, 4, 5});
    actionSpec.Name = 'countermeasure_action';
    
    fprintf('State spec: %d-dim\n', numStates);
    fprintf('  threat_class: [0,5] (6 threats)\n');
    fprintf('  BER: [0,1]\n');
    fprintf('  RSSI: [0,0] (placeholder)\n');
    fprintf('  SNR: [0,20] dB\n');
    fprintf('  PLR: [0,1]\n');
    fprintf('Action spec: %d discrete actions\n', numActions);
    for a = 1:numActions
        fprintf('  %d: %s\n', a, action_names{a});
    end
    
    %% 2. Build Q-network (value function approximator)
    % Input: state (5-dim) → Hidden(64) → Hidden(32) → Output Q-values (5 actions)
    qNetwork = [
        featureInputLayer(numStates, 'Name', 'state_input')
        fullyConnectedLayer(64, 'Name', 'fc1')
        reluLayer('Name', 'relu1')
        fullyConnectedLayer(32, 'Name', 'fc2')
        reluLayer('Name', 'relu2')
        fullyConnectedLayer(numActions, 'Name', 'qvalues')
    ];
    
    qNet = dlnetwork(qNetwork);
    fprintf('\nQ-Network architecture:\n');
    fprintf('  Input: 5-dim state\n');
    fprintf('  Hidden1: 64 neurons + ReLU\n');
    fprintf('  Hidden2: 32 neurons + ReLU\n');
    fprintf('  Output: 5 Q-values (one per action)\n');
    fprintf('  Total params: %d\n', sum(cellfun(@numel, {qNet.Learnables.Value{:}})));
    
    %% 3. Create RL agent
    % Q-learning with epsilon-greedy exploration
    agent = struct();
    agent.qNetwork = qNet;
    agent.stateSpec = stateSpec;
    agent.actionSpec = actionSpec;
    agent.action_names = action_names;
    
    % Hyperparameters
    agent.learning_rate = 1e-3;
    agent.gamma = 0.99;              % discount factor
    agent.epsilon = 1.0;              % exploration rate (start high)
    agent.epsilon_min = 0.01;         % min exploration
    agent.epsilon_decay = 0.995;      % decay per episode
    agent.replay_buffer_size = 10000; % experience buffer
    agent.batch_size = 32;            % training batch size
    agent.target_update_freq = 5;     % update target network every N episodes
    
    % Replay buffer (initialize empty)
    agent.replay_buffer = struct('states', [], 'actions', [], 'rewards', [], 'next_states', [], 'dones', []);
    agent.episode_count = 0;
    
    fprintf('\nDQN Hyperparameters:\n');
    fprintf('  Learning rate: %.0e\n', agent.learning_rate);
    fprintf('  Discount (gamma): %.2f\n', agent.gamma);
    fprintf('  Replay buffer size: %d\n', agent.replay_buffer_size);
    fprintf('  Batch size: %d\n', agent.batch_size);
    fprintf('  Epsilon start: %.2f → %.2f (decay %.3f)\n', agent.epsilon, agent.epsilon_min, agent.epsilon_decay);
    
    fprintf('\n=== DQN Agent Initialized ===\n');
end

function action = selectAction(agent, state, training)
    %% Epsilon-greedy action selection
    if training && rand() < agent.epsilon
        % Explore: random action
        action = randperm(5, 1);
    else
        % Exploit: greedy Q(s, a)
        state_dl = dlarray(single(state), 'CB');
        if canUseGPU
            state_dl = gpuArray(state_dl);
        end
        qvals = predict(agent.qNetwork, state_dl);
        [~, action] = max(extractdata(qvals), [], 1);
    end
end

function storeExperience(agent, state, action, reward, next_state, done)
    %% Add (s, a, r, s', done) to replay buffer
    if isempty(agent.replay_buffer.states)
        agent.replay_buffer.states = state;
        agent.replay_buffer.actions = action;
        agent.replay_buffer.rewards = reward;
        agent.replay_buffer.next_states = next_state;
        agent.replay_buffer.dones = done;
    else
        agent.replay_buffer.states = [agent.replay_buffer.states; state'];
        agent.replay_buffer.actions = [agent.replay_buffer.actions; action];
        agent.replay_buffer.rewards = [agent.replay_buffer.rewards; reward];
        agent.replay_buffer.next_states = [agent.replay_buffer.next_states; next_state'];
        agent.replay_buffer.dones = [agent.replay_buffer.dones; done];
    end
    
    % Keep buffer size under limit
    if size(agent.replay_buffer.states, 1) > agent.replay_buffer_size
        idx_keep = size(agent.replay_buffer.states, 1) - agent.replay_buffer_size + 1 : size(agent.replay_buffer.states, 1);
        agent.replay_buffer.states = agent.replay_buffer.states(idx_keep, :);
        agent.replay_buffer.actions = agent.replay_buffer.actions(idx_keep);
        agent.replay_buffer.rewards = agent.replay_buffer.rewards(idx_keep);
        agent.replay_buffer.next_states = agent.replay_buffer.next_states(idx_keep, :);
        agent.replay_buffer.dones = agent.replay_buffer.dones(idx_keep);
    end
end