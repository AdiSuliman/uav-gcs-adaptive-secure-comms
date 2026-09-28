function agent = dqn_agent(norm, hidden)
%DQN_AGENT  Q-network of the sequential decision layer (D44, D45, D59).
%   State (policy_state.m): the receiver observations of the last cycles
%   (class probabilities, unknown flag, estimated BER, degradation, packet loss,
%   SINR, IoT, post-combining SNR, spatial features, Eb/N0 drop), current
%   configuration (one-hot), cycles since the last change, confirmed alarm.
%   Output: one Q-value per configuration (policy_actions.m).
%   norm: fields mu, sd (z-score of the state, from rollouts); hidden: layer sizes.
if nargin < 2, hidden = [256 256]; end
names = policy_actions();
nA = numel(names); nS = policy_state_size(nA);
if nargin < 1 || isempty(norm)
    norm = struct('mu', zeros(nS, 1), 'sd', ones(nS, 1));
end
layers = [featureInputLayer(nS, 'Name', 'state', 'Normalization', 'zscore', ...
          'Mean', norm.mu(:)', 'StandardDeviation', norm.sd(:)')];
for i = 1:numel(hidden)
    layers = [layers
        fullyConnectedLayer(hidden(i), 'Name', sprintf('fc%d', i))
        reluLayer('Name', sprintf('relu%d', i))]; %#ok<AGROW>
end
layers = [layers; fullyConnectedLayer(nA, 'Name', 'qvalues')];
agent = struct('qNetwork', dlnetwork(layers), 'action_names', {names}, 'numStates', nS, ...
    'numActions', nA, 'norm', norm, 'hidden', hidden);
end
