function [nS, cont] = policy_state_size(nA)
%POLICY_STATE_SIZE  Length of the policy_state.m vector for nA configurations,
%   and the rows that are z-scored (continuous link measurements and dwell).
nS = 17 + nA;
cont = [11:15, 16 + nA];
end
