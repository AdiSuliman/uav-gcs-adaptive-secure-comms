function ber = quick_ber(model)
%QUICK_BER Run a link model once and return BER via delay-scan alignment.
%   Robust to RRC group delay in multirate models: scans 0..60 bit delays and
%   picks the minimum-BER alignment (finddelay is unreliable here). Used by
%   main.m for fast per-stage validation.
out = sim(model);
tx = double(squeeze(out.get('tx_bits_out'))); tx = tx(:);
rx = double(squeeze(out.get('rx_bits_out'))); rx = rx(:);
best = 1;
for d = 0:60
    L = min(numel(tx)-d, numel(rx)-d);
    if L < 100, continue; end
    b = mean(tx(1:L) ~= rx(d+1:d+L));
    if b < best, best = b; end
end
ber = best;
end