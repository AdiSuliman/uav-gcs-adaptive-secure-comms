function F = extract_closed_loop_frames(out, p, delay_bits)
%EXTRACT_CLOSED_LOOP_FRAMES  Every frame of one sim() run: what the UAV receiver
% measures, and the ground truth kept for evaluation. Single source for the
% per-frame measurements of the dataset, the decision-layer pools and the GUI.
%
% Inputs:
%   out         Simulink SimulationOutput of the threat link (build_threat_model.m)
%   p           params of the run (frame_length, sps, rolloff, filter_span, fec)
%   delay_bits  Tx + Rx filter delay in bits (20)
%
% Output F (vectors 1 x nf, one entry per frame):
%   nf, iq{f}   number of frames; antenna-1 received IQ of frame f
%   Ground truth (evaluation and training reward only, never an input of the
%   detector or of a policy):
%     ber       bit error rate (with p.fec: decoded information bits); NaN when the
%               frame runs past the aligned bit range (the last frame of a run)
%     fer       1 when the frame has at least one bit error
%   Receiver measurements (the transmitted bits and waveform are never used):
%     rssi      antenna-1 received power [dB]
%     crc_fail  CRC-32 check of the frame failed: the packet is lost. The frame
%               carries 1000 information bits + 32 CRC bits (p.crc_bits); the
%               channel's actual error pattern of the frame is applied to a
%               CRC-protected codeword and the codeword is checked (a CRC is
%               linear, so the check depends only on the error pattern)
%     ber_est   BER estimated from the combiner output: decision-directed SNR per
%               32-symbol block, BER = mean of Q(sqrt(SNR)) over the blocks (QPSK,
%               Alouini & Goldsmith 1999, eq. (15)), so bursts are averaged as conditional BERs
%     snr_post  post-combining SNR estimate [dB]
%     sinr      antenna-1 SINR [dB]: LS fit of the waveform re-modulated from the
%               receiver's own decisions to the received samples
%     env_corr  correlation between the residual power and the re-modulated
%               envelope (32-sample block fit): ~0 for interference independent of
%               our transmission, > 0 when it is triggered by it (reactive jamming)
%     iot       interference over thermal [dB] (iot_db.m); the thermal floor is the
%               receiver's calibration constant (the AWGN setting of the run)
%     coh       spatial coherence of interference + noise between the antennas
%               (0 = thermal noise, 1 = one directional source)
%     mmse_gain predicted SINR gain of MMSE over MRC combining [dB] from the
%               interference covariance and the channel estimate (Shebert et al.)
%     align     alignment of the dominant interference direction with the GCS
%               channel (0 = orthogonal, 1 = same direction: no spatial null)
%     branch_dip deepest drop of one antenna's channel gain inside the frame [dB]:
%               per antenna, median minus minimum of the 32-symbol channel-gain
%               estimates, the larger of the antennas. A fading branch
%               changes little within 0.5 ms (fd <= 267 Hz); a failing antenna
%               drops by tens of dB (per-branch monitoring of a diversity receiver)
%     branch_gap gap between the antennas' mean channel gains over the frame [dB]:
%               fading moves both around the same mean, a shadowed antenna (the
%               airframe between it and the GCS in a banking turn) stays tens of
%               dB below the other (Khawaja et al.)
%   The last five come from the receiver's channel estimator (per-32-symbol
%   channel estimates and the frame's interference + noise covariance, the
%   quantities MMSE combining uses; known symbols = ideal pilots, proposal risk 8).
% With p.fec (fec_interleave) ber, fer and crc_fail are those of the decoded
% information bits (half a frame each, 484 + 32 CRC).

txb = double(squeeze(out.get('tx_bits_out')));
rxb = double(squeeze(out.get('rx_bits_out')));
iq  = squeeze(out.get('Rx_IQ'));
zc  = squeeze(out.get('Rx_Z'));
Hq  = out.get('Rx_H');
Rq  = out.get('Rx_R');
if isvector(iq), iq = iq(:); end
if isvector(zc), zc = zc(:); end
nf  = size(iq, 2);

bpf = p.frame_length;
tx_all = txb(:); rx_all = rxb(:);
Lmax = min(numel(tx_all), numel(rx_all)) - delay_bits;
tx_al = tx_all(1:Lmax);
rx_al = rx_all(delay_bits+1:delay_bits+Lmax);

F = struct('nf', nf, 'iq', {num2cell(iq, 1)});
F.rssi = 10*log10(mean(abs(iq).^2, 1) + eps);

% Ground truth and CRC
if isfield(p, 'fec') && p.fec
    [F.ber, F.fer, F.crc_fail] = fec_frames(tx_al, rx_al, iq, p, delay_bits, nf);
else
    err = double(tx_al ~= rx_al);
    F.ber = nan(1, nf); F.fer = nan(1, nf); F.crc_fail = nan(1, nf);
    for f = 1:nf
        i0 = (f-1)*bpf + 1; i1 = f*bpf;
        if i1 > numel(err), continue; end
        e = err(i0:i1);
        F.ber(f) = mean(e);
        F.fer(f) = double(any(e));
        F.crc_fail(f) = crc_check(tx_al(i0:i0 + bpf - p.crc_bits - 1), e);
    end
end

% Decision-directed link quality, channel-estimator spatial measurements
[F.ber_est, F.snr_post] = symbol_metrics(zc, p);
[F.coh, F.mmse_gain, F.align] = spatial_metrics(Hq, Rq, nf);
F.branch_dip = branch_dip(Hq, nf);
F.branch_gap = branch_gap(Hq, nf);
xh = remod_frames(rx_all(delay_bits+1:end), p, size(iq, 1), nf);
[F.sinr, F.env_corr] = residual_metrics(xh, iq);
F.iot = iot_of(out, p, F.rssi, F.sinr);
end

%% ===================== CRC =====================
function fail = crc_check(payload, e)
% CRC-32 (IEEE 802.3 polynomial) over the payload; the frame's error pattern e
% (payload + CRC bits) is applied to the codeword, which is then checked.
persistent cfg
if isempty(cfg)
    cfg = crcConfig('Polynomial', 'z^32 + z^26 + z^23 + z^22 + z^16 + z^12 + z^11 + z^10 + z^8 + z^7 + z^5 + z^4 + z^2 + z + 1');
end
cw = crcGenerate(payload(:), cfg);
[~, fail] = crcDetect(xor(cw, e(:) ~= 0), cfg);
fail = double(fail);
end

%% ===================== FEC =====================
function [ber, fer, crcf] = fec_frames(tx_al, rx_al, iq, p, delay_bits, nf)
% fec_interleave: the channel bit errors of this run are applied to a
% rate-1/2 convolutionally coded, randomly interleaved stream. Symbols whose
% received energy is more than 6 dB above the run's median are erased (a burst
% is visible at the receiver), the rest are hard decisions; the Viterbi decoder
% works on +1/-1/0 values. Per frame: the decoded information bits (half a
% frame), their BER, and the CRC check of the 484 + 32 bits.
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
ber = nan(1, nf); fer = nan(1, nf); crcf = nan(1, nf);
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
    if i1 > K, continue; end
    ef = err(i0:i1);
    ber(f) = mean(ef);
    fer(f) = double(any(ef));
    crcf(f) = crc_check(u(i0:i1 - p.crc_bits), ef);
end
end

%% ===================== Symbol-level estimates =====================
function [ber_est, snr_post] = symbol_metrics(zc, p)
% Decisions of the combiner output are the reference: per 32-symbol block the
% complex gain g and the error z - g*s give the SNR (error vector magnitude).
B = 32; Dt = p.filter_span;
nf = size(zc, 2);
ber_est = nan(1, nf); snr_post = nan(1, nf);
for f = 1:nf
    z = zc(:, f);
    if f == 1, z = z(Dt+1:end); end                    % filter transient of the first frame
    s = (sign0(real(z)) + 1j * sign0(imag(z))) / sqrt(2);
    nb = floor(numel(z) / B);
    pb = zeros(1, nb); gs = zeros(1, nb); es = zeros(1, nb);
    for b = 1:nb
        k = (b-1)*B + (1:B);
        g = mean(z(k) .* conj(s(k)));
        gs(b) = abs(g)^2; es(b) = mean(abs(z(k) - g * s(k)).^2);
        pb(b) = 0.5 * erfc(sqrt(gs(b) / max(es(b), eps) / 2));
    end
    ber_est(f) = mean(pb);
    snr_post(f) = 10*log10(mean(gs) / max(mean(es), eps));
end
end

function y = sign0(x)
y = sign(x); y(y == 0) = 1;
end

function [coh, mmse_gain, align] = spatial_metrics(Hq, Rq, nf)
% Hq: antennas x blocks x frames channel estimates, Rq: antennas x antennas x
% frames interference + noise covariance, both from the receiver's estimator.
coh = nan(1, nf); mmse_gain = nan(1, nf); align = nan(1, nf);
nr = size(Rq, 1);
for f = 1:min(nf, size(Rq, 3))
    R = Rq(:, :, f); R = (R + R') / 2;
    H = Hq(:, :, f);
    dg = real(diag(R));
    c = 0; np = 0;
    for i = 1:nr
        for j = i+1:nr
            c = c + abs(R(i, j)) / sqrt(max(dg(i) * dg(j), eps)); np = np + 1;
        end
    end
    coh(f) = c / max(np, 1);
    [V, D] = eig(R);
    [~, im] = max(real(diag(D)));
    v1 = V(:, im);
    Ri = inv(R + 1e-9 * real(trace(R)) * eye(nr));
    nb = size(H, 2);
    G = zeros(1, nb); A = zeros(1, nb);
    for b = 1:nb
        h = H(:, b); hh = real(h' * h);
        G(b) = real(h' * Ri * h) * real(h' * R * h) / max(hh^2, eps);
        A(b) = abs(v1' * h)^2 / max(hh, eps);
    end
    mmse_gain(f) = 10*log10(mean(G));
    align(f) = mean(A);
end
end

function d = branch_dip(Hq, nf)
% Deepest within-frame drop of one antenna's channel gain [dB] (Hq: antennas x
% blocks x frames): per antenna, median minus minimum over the blocks.
d = nan(1, nf);
for f = 1:min(nf, size(Hq, 3))
    g = 20*log10(abs(Hq(:, :, f)) + eps);
    if f == 1, g = g(:, 2:end); end                      % filter transient in the first block of the run
    d(f) = max(median(g, 2) - min(g, [], 2));
end
end

function d = branch_gap(Hq, nf)
% Gap between the largest and smallest mean channel gain of the antennas over the
% frame [dB] (Hq: antennas x blocks x frames).
d = nan(1, nf);
for f = 1:min(nf, size(Hq, 3))
    g = 10*log10(mean(abs(Hq(:, :, f)).^2, 2) + eps);
    d(f) = max(g) - min(g);
end
end

%% ===================== Sample-level estimates =====================
function X = remod_frames(bits, p, ns, nf)
% Transmit waveform re-modulated from the receiver's decisions (same QPSK
% mapping and RRC filter as the transmitter), cut into frames of ns samples;
% frames whose decisions are incomplete are NaN.
X = nan(ns, nf);
nsym = floor(numel(bits) / 2);
if nsym < 1, return; end
txf = comm.RaisedCosineTransmitFilter('RolloffFactor', p.rolloff, 'FilterSpanInSymbols', p.filter_span, ...
    'OutputSamplesPerSymbol', p.sps);
x = txf(pskmod(bits(1:2*nsym), 4, pi/4, 'gray', 'InputType', 'bit'));
nc = min(nf, floor(numel(x) / ns));
X(:, 1:nc) = reshape(x(1:nc*ns), ns, nc);
end

function [sinr, ec] = residual_metrics(x, r)
% Per frame: whole-frame LS gain for the SINR; 32-sample block LS gains (absorb
% fading and gain steps) for the residual used in the envelope correlation.
B = 32;
nf = size(r, 2);
sinr = nan(1, nf); ec = nan(1, nf);
for f = 1:nf
    xf = x(:, f); rf = r(:, f);
    if any(isnan(xf)), continue; end
    px = real(xf' * xf);
    if px <= 0, continue; end
    h = (xf' * rf) / px;
    e = rf - h * xf;
    sinr(f) = 10*log10(abs(h)^2 * px / max(real(e' * e), eps));
    n = floor(numel(xf) / B) * B;
    X = reshape(xf(1:n), B, []); R = reshape(rf(1:n), B, []);
    hb = sum(conj(X) .* R, 1) ./ max(sum(abs(X).^2, 1), eps);
    E = R - X .* hb;
    c = corrcoef(abs(E(:)).^2, abs(X(:)).^2);
    ec(f) = c(1, 2);
end
end

function iot = iot_of(out, p, rssi, sinr)
iot = nan(size(rssi));
try
    mdl = out.SimulationMetadata.ModelInfo.ModelName;
    snr_s = str2double(get_param([mdl '/AWGN'], 'SNR'));
catch
    return;
end
iot = iot_db(rssi, sinr, snr_s, p.sps);
end
