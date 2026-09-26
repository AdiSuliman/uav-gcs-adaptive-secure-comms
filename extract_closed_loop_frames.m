function [iq_frames, ber, rssi, plr, nf, sinr, env_corr, iot] = extract_closed_loop_frames(out, p, delay_bits)
%EXTRACT_CLOSED_LOOP_FRAMES  Every frame of one sim() run with its BER, RSSI,
% PLR, SINR, envelope correlation and IoT: the single source for the per-frame
% measurements and the temporal features of link_features.m.
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
%   sinr(f)      - data-aided SINR estimate on antenna 1 [dB]: LS fit of the
%                  transmitted waveform to the received one, signal power over
%                  residual power (a receiver-side estimate, not the configured Eb/N0)
%   env_corr(f)  - correlation between the residual power and our own signal
%                  envelope (residual after a 32-sample block LS fit): ~0 for
%                  interference independent of our transmission, > 0 when the
%                  interference is triggered by it (reactive jamming, D42)
%   iot(f)       - interference over thermal [dB] (iot_db.m); the thermal floor is
%                  the AWGN setting of the run, read from the model (D43)
%
% With p.fec (fec_interleave, D39) BER and PLR are those of the decoded
% information bits (local function fec_frames).
%   nf           - number of frames in this run (Rx_IQ returns ~20 per
%                  sim() call, not 1 -- see D16)

txb = double(squeeze(out.get('tx_bits_out')));
rxb = double(squeeze(out.get('rx_bits_out')));
iq  = squeeze(out.get('Rx_IQ'));
txi = squeeze(out.get('Tx_IQ'));
if isvector(txi), txi=txi(:); end
if isvector(txb), txb=txb(:); end
if isvector(rxb), rxb=rxb(:); end
if isvector(iq),  iq=iq(:);   end

nf  = size(iq,2);
bpf = p.frame_length;
[sinr, env_corr] = residual_metrics(txi, iq, nf);
iot = iot_of(out, p, iq, sinr, nf);
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

function [sinr, ec] = residual_metrics(tx, rx, nf)
% Per frame: whole-frame LS gain for the SINR estimate; 32-sample block LS gains
% (absorb fading and gain steps) for the residual used in the envelope correlation.
B = 32;
sinr = nan(1, nf); ec = nan(1, nf);
for f = 1:min(nf, size(tx, 2))
    x = tx(:, f); r = rx(:, f);
    px = real(x' * x);
    if px <= 0, continue; end
    h = (x' * r) / px;
    e = r - h * x;
    sinr(f) = 10*log10(abs(h)^2 * px / max(real(e' * e), eps));
    n = floor(numel(x) / B) * B;
    X = reshape(x(1:n), B, []); R = reshape(r(1:n), B, []);
    hb = sum(conj(X) .* R, 1) ./ max(sum(abs(X).^2, 1), eps);
    E = R - X .* hb;
    a = abs(E(:)).^2; b = abs(X(:)).^2;
    c = corrcoef(a, b);
    ec(f) = c(1, 2);
end
end

function iot = iot_of(out, p, iq, sinr, nf)
iot = nan(1, nf);
try
    mdl = out.SimulationMetadata.ModelInfo.ModelName;
    snr_s = str2double(get_param([mdl '/AWGN'], 'SNR'));
catch
    return;
end
for f = 1:nf
    iot(f) = iot_db(10*log10(mean(abs(iq(:, f)).^2) + eps), sinr(f), snr_s, p.sps);
end
end
