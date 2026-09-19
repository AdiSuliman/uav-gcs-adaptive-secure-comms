function state = build_dqn_state(threat_name, ber, rssi, snr, plr)
%BUILD_DQN_STATE Build the 13-dim DQN state vector for a given threat class.
%   One-hot encodes the threat class (9 classes) and appends the four
%   continuous link measurements. Single source of truth for state
%   construction -- train_dqn.m and both closed-loop scripts call this, so
%   the encoding cannot drift between training and inference.
%
%   An unrecognized threat_name yields an all-zero one-hot: a valid
%   "unknown threat" state where the agent must rely on the link metrics
%   alone (proposal risk #13 mitigation).
%
%   threat_name : char/string, one of the 9 class names
%   Returns     : [13 x 1] column vector

threat_list = {'jamming', 'reactive_jamming', 'sweeping_jammer', 'noise_burst', ...
    'path_loss', 'spoofing', 'antenna_fault', 'benign_interference', 'none'};

onehot = zeros(numel(threat_list), 1);
idx = find(strcmp(threat_list, char(threat_name)), 1);
if ~isempty(idx)
    onehot(idx) = 1;
end

state = [onehot; double(ber); double(rssi); double(snr); double(plr)];
end