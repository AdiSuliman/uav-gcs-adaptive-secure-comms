function state = build_dqn_state(threat_name, ber, rssi, snr, plr)
%BUILD_DQN_STATE Build the 13-dim DQN state vector for a given threat class.
%   One-hot encodes the threat class (9 classes) and appends the four link
%   measurements: log10(BER), RSSI (dB), Eb/N0 (dB), PLR. Single source of
%   truth for state construction -- training, evaluation and the GUI all call
%   this, so the encoding cannot drift between training and inference.
%
%   BER enters as log10 (floored at 1e-6) because it spans several decades
%   across the Eb/N0 range and the policy depends on BER relative to the
%   clean link at that Eb/N0 (D29).
%
%   An unrecognized threat_name (e.g. 'unknown') yields an all-zero one-hot:
%   the agent must rely on the link metrics alone (proposal risk #13).

threat_list = {'jamming', 'reactive_jamming', 'sweeping_jammer', 'noise_burst', ...
    'path_loss', 'spoofing', 'antenna_fault', 'benign_interference', 'none'};

onehot = zeros(numel(threat_list), 1);
idx = find(strcmp(threat_list, char(threat_name)), 1);
if ~isempty(idx)
    onehot(idx) = 1;
end

state = [onehot; log10(max(double(ber), 1e-6)); double(rssi); double(snr); double(plr)];
end
