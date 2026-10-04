function [cap, share] = eirp_cap_dbm(psd_dbm_mhz, rolloff, symbol_rate)
%EIRP_CAP_DBM  Largest e.i.r.p. of our RRC signal under a density limit in any 1 MHz.
%   [cap, share] = eirp_cap_dbm(psd_dbm_mhz, rolloff, symbol_rate)
%   ETSI EN 300 328 (4.3.2.3) limits the mean e.i.r.p. density in a 1 MHz bandwidth
%   (10 dBm/MHz, non-FHSS). The densest 1 MHz of a root-raised-cosine signal is its
%   centre: share is the part of the power there (the raised-cosine spectrum, flat up to
%   (1 - a) Rs / 2, cosine roll-off up to (1 + a) Rs / 2), and cap = psd - 10 log10(share)
%   [dBm]: 10.20 dBm for a = 0.25 at 1 Msym/s (share 0.9546).
B = 1e6;
f1 = (1 - rolloff) * symbol_rate / 2;
x = min(B / 2, (1 + rolloff) * symbol_rate / 2);
inner = min(B / 2, f1);
if x > f1
    inner = inner + 0.5 * (x - f1) + rolloff * symbol_rate / (2*pi) * sin(pi * (x - f1) / (rolloff * symbol_rate));
end
share = inner / (symbol_rate / 2);
cap = psd_dbm_mhz - 10*log10(share);
end
