function agent = dqn_dense(agent)
%DQN_DENSE  Weights of a trained Q-network as plain matrices (D60), so one
%   decision cycle evaluates the network with a few single-precision matrix
%   products instead of a dlnetwork call (policy_decide.m): same function, same
%   precision, about 1 ms less per cycle. Added to the saved agents by
%   train_dqn.m; an agent without it is evaluated with predict.
L = agent.qNetwork.Learnables;
fc = unique(L.Layer, 'stable');
W = cell(1, numel(fc)); b = cell(1, numel(fc));
for i = 1:numel(fc)
    W{i} = single(extractdata(L.Value{strcmp(L.Layer, fc{i}) & strcmp(L.Parameter, 'Weights')}));
    b{i} = single(extractdata(L.Value{strcmp(L.Layer, fc{i}) & strcmp(L.Parameter, 'Bias')}));
end
agent.dense = struct('W', {W}, 'b', {b}, 'mu', single(agent.norm.mu(:)), 'sd', single(agent.norm.sd(:)));
end
