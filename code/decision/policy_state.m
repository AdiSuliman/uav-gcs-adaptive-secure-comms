function st = policy_state(mem, cfg, confirmed, nA)
%POLICY_STATE  Decision-layer state, one column per episode.
%   Single source for training, evaluation and deployment. Size: policy_state_size.
%   mem        policy memory of policy_monitor.m (after its update this cycle):
%              mem.hist holds the observation vectors of the last C.hist cycles,
%              newest first (class probabilities, unknown flag, estimated BER,
%              degradation, packet loss, SINR, IoT, post-combining SNR, spatial
%              coherence, predicted MMSE gain, alignment, antenna gain gap, Eb/N0
%              drop) -- the
%              history of the spectrum waterfall (Liu et al.) and of the stacked
%              frames (Mnih et al.)
%   cfg        current configuration index (1 x NE); nA configurations
%   confirmed  confirmed alarm (policy_monitor.m), 1 x NE
%   Rows: history (observation x cycle), configuration one-hot, min(dwell, 10)/10,
%   confirmed alarm.
NE = numel(cfg);
H = reshape(permute(double(mem.hist), [1 3 2]), [], NE);   % (observation, cycle) x episode
oh = zeros(nA, NE); oh(sub2ind([nA NE], cfg(:)', 1:NE)) = 1;
st = [H; oh; min(mem.since(:)', 10) / 10; double(confirmed(:)')];
end
