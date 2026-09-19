%% C2 — DQN AGENT: Deep Q-Network for Adaptive Countermeasure Selection
% State: [one-hot(9 threat classes), BER, RSSI, SNR, PLR] = 13-dim
%   One-hot replaces the previous scalar threat code. A scalar makes the
%   network interpolate Q-values between unrelated classes sitting at
%   adjacent codes; one-hot gives each class an independent axis. It also
%   implements the proposal's risk #13 mitigation: an unrecognized threat
%   maps to an all-zero one-hot, so the agent falls back on the functional
%   link metrics (BER/RSSI/SNR/PLR) rather than on a threat label it was
%   never trained on.
% Actions: {no_action, channel_switch, rate_reduce, freq_diversity, spatial_diversity}
% Reward: BER improvement when action applied
% Architecture: state -> 64 -> 32 -> Q(s,a)

function agent = dqn_agent()
    fprintf('=== C2: Initializing DQN Agent ===\n\n');

    %% 1. State and action specs
    numThreatClasses = 9;
    numContinuous    = 4;                                  % BER, RSSI, SNR, PLR
    numStates        = numThreatClasses + numContinuous;   % 13

    numActions = 5;
    action_names = {'no_action', 'channel_switch', 'rate_reduce', 'freq_diversity', 'spatial_diversity'};

    % One-hot entries are [0,1]; continuous entries keep their physical
    % ranges. RSSI is in dBm and negative, so its bounds are explicit rather
    % than the [0,0] placeholder the scalar version used.
    lower_bounds = [zeros(numThreatClasses,1);  0;  -100;  0;  0];
    upper_bounds = [ones(numThreatClasses,1);   1;    20; 20;  1];

    stateSpec = rlNumericSpec([numStates 1], 'Lower', lower_bounds, 'Upper', upper_bounds);
    stateSpec.Name = 'threat_state';
    stateSpec.Description = 'onehot(9 threat classes), BER, RSSI, SNR, PLR';

    actionSpec = rlFiniteSetSpec({1, 2, 3, 4, 5});
    actionSpec.Name = 'countermeasure_action';

    fprintf('State spec: %d-dim\n', numStates);
    fprintf('  threat class: one-hot [%d classes]\n', numThreatClasses);
    fprintf('  BER:  [0,1]\n');
    fprintf('  RSSI: [-100,20] dBm\n');
    fprintf('  SNR:  [0,20] dB\n');
    fprintf('  PLR:  [0,1]\n');
    fprintf('Action spec: %d discrete actions\n', numActions);
    for a = 1:numActions
        fprintf('  %d: %s\n', a, action_names{a});
    end

    %% 2. Q-network
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
    fprintf('  Input: %d-dim state\n', numStates);
    fprintf('  Hidden1: 64 neurons + ReLU\n');
    fprintf('  Hidden2: 32 neurons + ReLU\n');
    fprintf('  Output: %d Q-values (one per action)\n', numActions);
    fprintf('  Total params: %d\n', sum(cellfun(@numel, {qNet.Learnables.Value{:}})));

    %% 3. Agent struct
    agent = struct();
    agent.qNetwork   = qNet;
    agent.stateSpec  = stateSpec;
    agent.actionSpec = actionSpec;
    agent.action_names = action_names;
    agent.numThreatClasses = numThreatClasses;
    agent.numStates = numStates;

    % Hyperparameters
    agent.learning_rate = 1e-3;
    agent.gamma = 0.99;
    agent.epsilon = 1.0;
    agent.epsilon_min = 0.01;
    agent.epsilon_decay = 0.995;
    agent.replay_buffer_size = 10000;
    agent.batch_size = 32;
    agent.target_update_freq = 5;

    agent.replay_buffer = struct('states', [], 'actions', [], 'rewards', [], 'next_states', [], 'dones', []);
    agent.episode_count = 0;

    fprintf('\nDQN Hyperparameters:\n');
    fprintf('  Learning rate: %.0e\n', agent.learning_rate);
    fprintf('  Discount (gamma): %.2f\n', agent.gamma);
    fprintf('  Replay buffer size: %d\n', agent.replay_buffer_size);
    fprintf('  Batch size: %d\n', agent.batch_size);
    fprintf('  Epsilon start: %.2f -> %.2f (decay %.3f)\n', agent.epsilon, agent.epsilon_min, agent.epsilon_decay);

    fprintf('\n=== DQN Agent Initialized ===\n');
end