function L = frame_layout(p)
%FRAME_LAYOUT  Symbol layout of one transmitted frame (one decision cycle).
%   [quiet slot | short training | long training | data with pilot blocks | guard]
%   Quiet slot: the GCS is silent right before the frame (the gap between command
%   packets): the UAV measures interference + noise there, just before it has to
%   find the frame.
%   Short training: p.stf_rep repeats of a p.stf_len-symbol sequence: frame
%   detection and coarse frequency offset (unambiguous within +-1/(2 stf_len T)).
%   Long training: p.ltf_rep repeats of a p.ltf_len-symbol sequence: timing, fine
%   frequency offset and the first channel estimate. As the 802.11 preamble: ten
%   identical short symbols, then two identical long ones (Pirayesh & Zeng).
%   Pilots: a block of p.pilot_block known symbols after every p.pilot_every data
%   symbols and after the last ones: channel and phase tracking (802.11: 4 pilots
%   per 52 subcarriers). Training sequences are Zadoff-Chu (constant amplitude,
%   flat periodic spectrum); pilots are fixed QPSK symbols.
%   Guard: silence after the frame, long enough for the filter tails at the latest
%   arrival, so the next quiet slot holds no signal of ours.
%   L.air          symbols on the air per frame, quiet slot and guard included
%   L.NQ, L.G      quiet-slot and guard symbols; L.n_sig = training + data + pilots
%   L.pre          training symbols (n_pre x 1), L.stf / L.ltf their two parts
%   L.pil          pilot symbols in transmission order
%   L.idx_data     frame positions of the data symbols (n_data x 1)
%   L.idx_pil      frame positions of the pilot symbols
%   L.pil_center   frame position (centre) of every pilot block
%   L.ltf_center   frame position (centre) of the long training
%   L.tmpl         frame template: training and pilots in place, data, quiet slot and guard 0

zc = @(N) exp(-1j * pi * (0:N-1)'.^2 / N);           % Zadoff-Chu, root 1, even length
L.stf = repmat(zc(p.stf_len), p.stf_rep, 1);
L.ltf = repmat(zc(p.ltf_len), p.ltf_rep, 1);
L.pre = [L.stf; L.ltf];
L.n_pre = numel(L.pre);
L.n_data = p.frame_length / p.bits_per_symbol;
L.NQ = p.quiet_symbols;
L.G = 2 * p.filter_span + ceil(p.timing_max_sym);

nb = ceil(L.n_data / p.pilot_every);                  % pilot blocks
L.n_pil = nb * p.pilot_block;
L.n_sig = L.n_pre + L.n_data + L.n_pil;
L.air = L.NQ + L.n_sig + L.G;
L.idx_data = zeros(L.n_data, 1); L.idx_pil = zeros(L.n_pil, 1); L.pil_center = zeros(nb, 1);
k = L.NQ + L.n_pre; d = 0;
for b = 1:nb
    nd = min(p.pilot_every, L.n_data - d);
    L.idx_data(d + (1:nd)) = k + (1:nd); k = k + nd; d = d + nd;
    L.idx_pil((b-1)*p.pilot_block + (1:p.pilot_block)) = k + (1:p.pilot_block);
    L.pil_center(b) = k + (p.pilot_block + 1) / 2;
    k = k + p.pilot_block;
end
L.ltf_center = L.NQ + numel(L.stf) + (numel(L.ltf) + 1) / 2;

rs = RandStream('mt19937ar', 'Seed', 5);
L.pil = exp(1j * pi / 4 * (2 * randi(rs, [0 3], L.n_pil, 1) + 1));

L.tmpl = complex(zeros(L.air, 1));
L.tmpl(L.NQ + (1:L.n_pre)) = L.pre;
L.tmpl(L.idx_pil) = L.pil;
end
