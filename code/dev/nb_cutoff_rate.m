function R0 = nb_cutoff_rate(pattern, jsr_db)
%NB_CUTOFF_RATE  Cutoff rate R0(1) per coded bit of the coded link under noise bursts, with
%   ideal interleaving and per-symbol jammer state information: R0(1) = -log2 E{2^-R0_s} over
%   the bursts' noise states s (McEliece and Stark 1984, (4.9)), with R0_s = 1 - log2(1 +
%   exp(-1/(2 v_s))) of a BPSK rail of unit amplitude and noise variance v_s.
%   R0 = nb_cutoff_rate(pattern, jsr_db): one rail at Eb/N0 9 dB (thermal variance 10^-1.2),
%   single branch, jsr_db the in-band JSR [dB] (a vector):
%   'j4'    Marti et al.'s J4, each one-symbol slot jammed with probability 0.2; a burst falls
%           on its symbol with 0.847 of its power and on four neighbours each side with the
%           RRC leaks 0.068, 0.0073, 0.0013, 0.0002 (roll-off 0.25, span 10)
%   'r50', 'r775'  Xu et al.'s random jammer at duty 0.5 and 0.775, the burst on the symbol
%   Our own calculation from the model's parameters (docs/noise_burst_protocol.md, section 1).
v0 = 10^-1.2;
lk = [0.0002 0.0013 0.0073 0.068 0.847 0.068 0.0073 0.0013 0.0002];
switch pattern
    case 'j4'
        b = dec2bin(0:2^numel(lk) - 1) == '1';         % every on/off pattern of the nine slots
        w = prod(0.2 .^ b .* 0.8 .^ ~b, 2); g = double(b) * lk';
    case 'r50', w = [0.5; 0.5]; g = [0; 1];
    case 'r775', w = [0.225; 0.775]; g = [0; 1];
    otherwise, error('nb_cutoff_rate:pattern', 'unknown pattern %s', pattern);
end
r0s = @(v) 1 - log2(1 + exp(-1 ./ (2 * v)));
R0 = arrayfun(@(J) -log2(sum(w .* 2 .^ -r0s(v0 + J * g))), 10 .^ (jsr_db / 10));
end
