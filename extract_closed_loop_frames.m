function [iq_frames, ber, rssi, plr, nf] = extract_closed_loop_frames(out, p, delay_bits)
%EXTRACT_CLOSED_LOOP_FRAMES Single source of truth for pulling all frames
% (not just the first) out of a single sim() call's output, with per-frame
% BER/RSSI/PLR -- the building block for real sliding-window temporal
% features (var_rssi_10, dber_dt, burst_ratio) in any closed-loop-style
% script (single sim() call, CNN decides on the last valid frame).
%
% HISTORY: originally a local function inside run_closed_loop_diagnostic.m
% (D16 fix, 2026-09-18). Extracted to a shared file 2026-09-19 (D20) after
% diagnose_far_measurement.m was found still using the pre-D16 neutral
% placeholder (0,0,1) for temporal features -- the same failure mode D16
% fixed (none/reactive_jamming misclassification), just never propagated to
% a second script. A duplicated local copy is exactly how that happened:
% single source of truth prevents a third recurrence.
%
% Inputs:
%   out         - Simulink SimulationOutput from sim(modelName)
%   p           - active params struct (needs p.frame_length)
%   delay_bits  - RRC group delay in bits (20, see build_threat_model.m)
%
% Outputs (all length nf, one entry per frame in this run):
%   iq_frames{f} - IQ samples for frame f
%   ber(f)       - bit error rate for frame f (NaN if the frame runs past
%                  the valid tx/rx bit range -- always true for the last
%                  frame of a run, by construction; guard before use)
%   rssi(f)      - 10*log10(mean power)) for frame f, in dB
%   plr(f)       - 1 if ber(f) > 0.1, else 0 (NaN propagates from ber)
%
% With p.fec (fec_interleave, D39) BER and PLR are those of the decoded
% information bits (local function fec_frames).
%   nf           - number of frames in this run (Rx_IQ returns ~20 per
%                  sim() call, not 1 -- see D16)

txb = double(squeeze(out.get('tx_bits_out')));
rxb = double(squeeze(out.get('rx_bits_out')));
iq  = squeeze(out.get('Rx_IQ'));
if isvector(txb), txb=txb(:); end
if isvector(rxb), rxb=rxb(:); end
if isvector(iq),  iq=iq(:);   end

nf  = size(iq,2);
bpf = p.frame_length;
tx_all = txb(:); rx_all = rxb(:);
Lmax = min(numel(tx_all),numel(rx_all)) - delay_bits;
tx_al = tx_all(1:Lmax);
rx_al = rx_all(delay_bits+1:delay_bits+Lmax);

if isfield(p, 'fec') && p.fec
    [ber, plr] = fec_frames(tx_al, rx_al, iq, p, delay_bits, nf);
    iq_frames = cell(1,nf); rssi = zeros(1,nf);
    for f = 1:nf
        iq_frames{f} = iq(:,f);
        rssi(f) = 10*log10(mean(abs(iq(:,f)).^2)+eps);
    end
    return;
end

iq_frames = cell(1,nf); ber=zeros(1,nf); rssi=zeros(1,nf); plr=zeros(1,nf);
for f = 1:nf
    iq_frames{f} = iq(:,f);
    i0=(f-1)*bpf+1; i1=f*bpf;
    if i1 <= numel(tx_al)
        ber(f) = mean(tx_al(i0:i1) ~= rx_al(i0:i1));
    else
        ber(f) = NaN;
    end
    rssi(f) = 10*log10(mean(abs(iq(:,f)).^2)+eps);
    plr(f)  = double(ber(f) > 0.1);
end
end

function [ber, plr] = fec_frames(tx_al, rx_al, iq, p, delay_bits, nf)
% fec_interleave (D39): the channel bit errors of this run are applied to a
% rate-1/2 convolutionally coded, randomly interleaved stream. Symbols whose
% received energy is more than 6 dB above the run's median are erased (a burst
% is visible at the receiver), the rest are hard decisions; the Viterbi decoder
% works on +1/-1/0 values. Per-frame BER is counted on the information bits
% (half a frame each), so a frame carries half the data of an uncoded frame.
e = double(tx_al(:) ~= rx_al(:));
L = numel(e);

sps = p.sps;
x = iq(:);
nsym = floor(numel(x) / sps);
Es = mean(reshape(abs(x(1:nsym*sps)).^2, sps, nsym), 1);
hot = movmax(double(Es > 4 * median(Es)), [3 3]) > 0;   % tolerate filter delay and alignment
d = round(delay_bits / 4);                           % Tx filter delay in symbols
sym = floor((0:L-1)' / 2) + 1 + d;
er = false(L, 1);
in = sym <= nsym;
er(in) = hot(sym(in));

trellis = poly2trellis(7, [171 133]);
K = floor(L / 2) - 6;
ber = nan(1, nf); plr = nan(1, nf);
if K < 64, return; end
rs = RandStream('mt19937ar', 'Seed', 11);
u = randi(rs, [0 1], K, 1);
c = convenc([u; zeros(6, 1)], trellis);
Lc = numel(c);
perm = randperm(rs, Lc)';
r = xor(c(perm), e(1:Lc));
soft = (1 - 2*double(r)) .* ~er(1:Lc);
softc = zeros(Lc, 1);
softc(perm) = soft;
dec = vitdec(softc, trellis, 35, 'term', 'unquant');
err = double(dec(1:K) ~= u);

kf = p.frame_length / 2;                             % information bits per frame
for f = 1:nf
    i0 = (f-1)*kf + 1; i1 = f*kf;
    if i1 <= K
        ber(f) = mean(err(i0:i1));
        plr(f) = double(ber(f) > 0.1);
    end
end
end
