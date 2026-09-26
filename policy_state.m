function st = policy_state(obs, cfg, dwell, ber_avg, confirmed, PP)
%POLICY_STATE  Decision-layer state, one column per episode (D44, D45). Single
%   source for training, evaluation and deployment. Size: policy_state_size.
%   obs        probs (NE x 9), unknown (NE x 1), feat (NE x 9, link_features order)
%   cfg        current configuration index (1 x NE); dwell cycles since last change
%   ber_avg    mean BER of the last 5 frames (NE x 1)
%   confirmed  confirmed alarm (policy_monitor.m), 1 x NE
%   Rows: probs(9), unknown, log10 BER, SINR, IoT, PLR, degradation, cfg one-hot
%   (nA), min(dwell, 10)/10, confirmed. Degradation = log10 of the BER over the
%   clean BER at the receiver's own Eb/N0 estimate (SINR + IoT = signal over
%   thermal), clipped to [-1, 3].
NE = size(obs.probs, 1);
nA = numel(PP.actions);
sinr = obs.feat(:, 1); iot = obs.feat(:, 9);
ebno_est = sinr + iot + 10*log10(PP.sps) - 10*log10(PP.bps);
bc = max(clean_ber_ref(ebno_est), 1e-4);
deg = min(3, max(-1, log10(max(ber_avg, 1e-4) ./ bc)));
oh = zeros(nA, NE); oh(sub2ind([nA NE], cfg(:)', 1:NE)) = 1;
st = [obs.probs'; double(obs.unknown(:)'); log10(max(obs.feat(:, 2)', 1e-4)); sinr'; iot'; ...
      obs.feat(:, 4)'; deg'; oh; min(dwell(:)', 10) / 10; double(confirmed(:)')];
end
