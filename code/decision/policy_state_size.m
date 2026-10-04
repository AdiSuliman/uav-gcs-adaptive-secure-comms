function [nS, cont] = policy_state_size(nA, nC)
%POLICY_STATE_SIZE  Length of the policy_state.m vector for nA configurations and
%   nC detector classes (default 11), and the rows that are z-scored (everything but
%   the class probabilities, the flags and the configuration one-hot).
if nargin < 2, nC = 11; end
C = decision_config();
nTe = numel(temporal_evidence('names', 0));       % persistence measurements of the window
nObs = nC + 14 + nTe;                             % policy_monitor.m observation vector
nS = nObs * C.hist + nA + 2;
contObs = nC + (2:14 + nTe);                      % estimated BER .. persistence (not probs, not the unknown flag)
cont = reshape((contObs(:) + (0:C.hist-1) * nObs), 1, []);
cont = [cont, nObs * C.hist + nA + 1];            % dwell
end
