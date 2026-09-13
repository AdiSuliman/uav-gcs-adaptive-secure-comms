function [ber, iq_rx] = quick_ber_with_iq(model)
%QUICK_BER_WITH_IQ Run a link model once and return BER + received IQ samples.
%   For C3 closed-loop: need both BER (reward) and IQ_RX (to compute spectrogram)
%   Scans 0..60 bit delays for BER alignment (handles RRC group delay).
%
%   Input:  model    - Simulink model name (string)
%   Output: ber      - bit error rate (scalar 0-1)
%           iq_rx    - received IQ samples vector (complex, for spectrogram)

out = sim(model);

% Extract IQ samples for spectrogram computation
try
    iq_rx = double(out.get('Rx_IQ'));
    if iscolumn(iq_rx)
        iq_rx = iq_rx.';
    end
catch
    warning('Rx_IQ not found in model output — returning empty IQ');
    iq_rx = [];
end

% Extract bit streams for BER calculation
tx = double(squeeze(out.get('tx_bits_out'))); tx = tx(:);
rx = double(squeeze(out.get('rx_bits_out'))); rx = rx(:);

% Delay scan: find best alignment
best = 1;
for d = 0:60
    L = min(numel(tx)-d, numel(rx)-d);
    if L < 100, continue; end
    b = mean(tx(1:L) ~= rx(d+1:d+L));
    if b < best, best = b; end
end
ber = best;
end