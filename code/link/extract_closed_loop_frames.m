function F = extract_closed_loop_frames(out, p, delay_bits)
%EXTRACT_CLOSED_LOOP_FRAMES  Every frame of one sim() run: what the UAV receiver
% measures, and the ground truth kept for evaluation. Single source for the
% per-frame measurements of the dataset, the decision-layer pools and the GUI.
%
% Inputs:
%   out         Simulink SimulationOutput of the threat link (build_threat_model.m)
%   p           params of the run (frame_length, sps, rolloff, filter_span, fec)
%   delay_bits  Tx + Rx filter delay in bits (20); 0 with a quiet slot longer than
%               the filter delay (the receiver then outputs each frame's own bits)
%
% Output F (vectors 1 x nf, one entry per frame):
%   nf, iq{f}   number of frames; received IQ of frame f on the reference antenna
%   ref         reference antenna of each frame: the antenna with the highest SINR
%   sinr_ant    SINR of every antenna [dB] (antennas x frames), diagnostics only
%   Ground truth (evaluation and training reward only, never an input of the
%   detector or of a policy):
%     ber       bit error rate (with p.fec: decoded information bits); NaN when the
%               frame runs past the aligned bit range (the last frame of a run
%               without a quiet slot), and with p.fec for a last frame without its pair
%     fer       1 when the frame has at least one bit error
%   Receiver measurements (the transmitted bits and waveform are never used):
%   The IQ measurements (rssi, sinr, env_corr, iot) are taken on the reference
%   antenna, so a fault or airframe shadowing on either antenna does not bias them;
%   the other antenna is compared with it (sinr_gap, branch_dip, branch_gap).
%     rssi      received power on the reference antenna [dB]
%     crc_fail  CRC-32 check of the frame failed: the packet is lost. The frame
%               carries 1000 information bits + 32 CRC bits (p.crc_bits); the
%               channel's actual error pattern of the frame is applied to a
%               CRC-protected codeword and the codeword is checked (crc32_fail.m)
%     ber_est   BER estimated from the combiner output: decision-directed SNR per
%               32-symbol block, BER = mean of Q(sqrt(SNR)) over the blocks (QPSK,
%               Alouini & Goldsmith 1999, eq. (15)), so bursts are averaged as conditional BERs
%     snr_post  post-combining SNR estimate [dB]
%     sinr      SINR on the reference antenna [dB]: LS fit of the waveform
%               re-modulated from the receiver's own decisions to the received samples
%     sinr_gap  SINR of the reference antenna minus the lowest SINR of the others [dB]
%     env_corr  correlation between the residual power and the re-modulated
%               envelope (32-sample block fit): ~0 for interference independent of
%               our transmission, > 0 when it is triggered by it (reactive jamming)
%     iot       interference over thermal [dB] (iot_db.m); the thermal floor is the
%               receiver's calibration constant (the AWGN setting of the run)
%     mmse_gain predicted SINR gain of MMSE over MRC combining [dB] from the
%               interference covariance and the channel estimate (optimum combining, Winters)
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
%   The last four come from the receiver's channel estimator (per-32-symbol
%   channel estimates and the frame's interference + noise covariance, the
%   quantities MMSE combining uses; from the training, the pilots and the decision-directed passes).
%   Quiet slot (p.quiet_symbols): the start of every frame carries no signal of ours.
%     q_iot     interference over thermal in the quiet slot [dB], mean of the
%               antennas: what occupies the channel while we are silent
%     q_react   residual power while we transmit over the quiet-slot power on the
%               reference antenna [dB]: ~0 for interference independent of us,
%               large for a jammer that transmits only while it senses our signal
%     coh       spatial coherence of the quiet slot: mean over the antenna pairs of
%               |R_ij| / sqrt(R_ii R_jj) of the matched-filtered quiet-slot
%               covariance (interference + noise, none of our signal; the
%               covariance the real receiver whitens with before synchronization):
%               thermal noise alone stays at its estimation floor at every Eb/N0,
%               one directional source -> 1
%     gain_ant  mean channel gain of every antenna over the frame [dB] (antennas x
%               frames), for measurements over several decision cycles
%   Synchronization (receiver output 6; zeros with an ideal receiver):
%     sync_d    arrival of the frame found from its training [samples]
%     cfo_hz    frequency offset found from the training [Hz]
%     sync_pk   timing peak over the mean of the arrival window (a clean frame stands out)
%     sync_p2   second timing peak, more than one symbol away, over the first (two
%               frames with our training on the air: a spoofer)
%   Ground truth: act, share of the frame with the threat on the air (packet traffic
%   of benign interference, the sweeping jammer on our channel), analysis and labels only.
% With p.fec (fec_interleave) ber, fer and crc_fail are those of the decoded packet,
% 1000 + 32 bits over two frames: ber and fer on both frames, crc_fail on the second only,
% when the receiver has decoded it (NaN on the first; fec_packets.m).

NQ = 0; if isfield(p, 'quiet_symbols'), NQ = p.quiet_symbols; end
if NQ >= p.filter_span, delay_bits = 0; end              % the receiver aligns each frame's bits
txb = double(squeeze(out.get('tx_bits_out')));
rxb = double(squeeze(out.get('rx_bits_out')));
iqa = out.get('Rx_IQ');                                  % samples x antennas x frames
zc  = squeeze(out.get('Rx_Z'));
Hq  = out.get('Rx_H');
Rq  = out.get('Rx_R');
sy  = zeros(5, size(iqa, ndims(iqa)));
try
    sy = reshape(out.get('Rx_S'), 5, []);
catch
end
if ismatrix(iqa), iqa = reshape(iqa, size(iqa, 1), 1, []); end
if isvector(zc), zc = zc(:); end
[ns, na, nf] = size(iqa);

bpf = p.frame_length;
tx_all = txb(:); rx_all = rxb(:);
Lmax = min(numel(tx_all), numel(rx_all)) - delay_bits;
tx_al = tx_all(1:Lmax);
rx_al = rx_all(delay_bits+1:delay_bits+Lmax);

F = struct('nf', nf);
if size(sy, 2) < nf, sy(:, end+1:nf) = 0; end
F.sync_d = sy(1, 1:nf); F.cfo_hz = sy(2, 1:nf); F.sync_pk = sy(3, 1:nf); F.sync_p2 = sy(4, 1:nf);

% Ground truth and CRC
if isfield(p, 'fec') && p.fec
    [F.ber, F.fer, F.crc_fail] = fec_packets(tx_al, rx_al, reshape(iqa(:, 1, :), ns, nf), p, nf);
else
    err = double(tx_al ~= rx_al);
    F.ber = nan(1, nf); F.fer = nan(1, nf); F.crc_fail = nan(1, nf);
    for f = 1:nf
        i0 = (f-1)*bpf + 1; i1 = f*bpf;
        if i1 > numel(err), continue; end
        e = err(i0:i1);
        F.ber(f) = mean(e);
        F.fer(f) = double(any(e));
        F.crc_fail(f) = crc32_fail(tx_al(i0:i0 + bpf - p.crc_bits - 1), e);
    end
end

% Decision-directed link quality, channel-estimator spatial measurements
[F.ber_est, F.snr_post] = symbol_metrics(zc, p);
[F.mmse_gain, F.align] = spatial_metrics(Hq, Rq, nf);
F.branch_dip = branch_dip(Hq, nf);
F.branch_gap = branch_gap(Hq, nf);
F.gain_ant = gain_ant(Hq, nf);
xh = remod_frames(rx_all(delay_bits+1:end), p, ns, nf, sy(1, 1:nf) + sy(5, 1:nf), sy(2, 1:nf));
qn = NQ * p.sps;                                         % quiet slot before the frame: free of our pulse tails
F.coh = quiet_coherence(iqa, p, qn);
dat = (qn + 1:ns)';                                      % samples that carry our signal
rs = nan(na, nf); sn = nan(na, nf); ec = nan(na, nf); io = nan(na, nf); pe = nan(na, nf); pq = nan(na, nf);
for a = 1:na
    ia = reshape(iqa(:, a, :), ns, nf);
    rs(a, :) = 10*log10(mean(abs(ia(dat, :)).^2, 1) + eps);
    [sn(a, :), ec(a, :), pe(a, :)] = residual_metrics(xh(dat, :), ia(dat, :));
    io(a, :) = iot_of(out, p, rs(a, :), sn(a, :));
    if qn > 0, pq(a, :) = mean(abs(ia(1:qn, :)).^2, 1); end
end
s0 = sn; s0(isnan(s0)) = -Inf;
[~, ref] = max(s0, [], 1);                                  % reference antenna per frame
k = sub2ind([na nf], ref, 1:nf);
F.ref = ref; F.sinr_ant = sn;
F.iq = arrayfun(@(f) iqa(:, ref(f), f), 1:nf, 'UniformOutput', false);
F.rssi = rs(k); F.sinr = sn(k); F.env_corr = ec(k); F.iot = io(k);
F.sinr_gap = F.sinr - min(sn, [], 1);
F.act = ones(1, nf);
try
    a = squeeze(out.get('Thr_act')); F.act = reshape(a(1:min(nf, numel(a))), 1, []);
    if numel(F.act) < nf, F.act(end+1:nf) = F.act(end); end
catch
end
nv = thermal_of(out, p);                                 % thermal noise power per sample
F.q_iot = 10*log10(mean(pq, 1) / nv);
F.q_react = 10*log10(pe(k) ./ pq(k));
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

function [mmse_gain, align] = spatial_metrics(Hq, Rq, nf)
% Hq: antennas x blocks x frames channel estimates, Rq: antennas x antennas x
% frames interference + noise covariance, both from the receiver's estimator.
mmse_gain = nan(1, nf); align = nan(1, nf);
nr = size(Rq, 1);
for f = 1:min(nf, size(Rq, 3))
    R = Rq(:, :, f); R = (R + R') / 2;
    H = Hq(:, :, f);
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
function X = remod_frames(bits, p, ns, nf, dly, cfo)
% Transmit waveform rebuilt from the receiver's decisions (frame_layout.m: training,
% pilots, the decided data symbols, quiet slot; same QPSK mapping and RRC filter as
% the transmitter), cut into frames of ns samples and moved to the arrival time and
% frequency offset the receiver found; frames whose decisions are incomplete are NaN.
X = nan(ns, nf);
L = frame_layout(p);
nfr = min(nf, floor(numel(bits) / p.frame_length));
if nfr < 1, return; end
txf = comm.RaisedCosineTransmitFilter('RolloffFactor', p.rolloff, 'FilterSpanInSymbols', p.filter_span, ...
    'OutputSamplesPerSymbol', p.sps);
S = repmat(L.tmpl, 1, nfr);
S(L.idx_data, :) = reshape(pskmod(bits(1:nfr*p.frame_length), 4, pi/4, 'gray', 'InputType', 'bit'), L.n_data, nfr);
x = txf(S(:));
nc = min(nfr, floor(numel(x) / ns));
X(:, 1:nc) = reshape(x(1:nc*ns), ns, nc);
fs = p.symbol_rate * p.sps;
kk = [0:ceil(ns/2)-1, -floor(ns/2):-1]';
t = (0:ns-1)' / fs;
for f = 1:nc
    if dly(f) ~= 0
        X(:, f) = ifft(fft(X(:, f)) .* exp(-1j*2*pi*kk*dly(f)/ns));
    end
    if cfo(f) ~= 0
        X(:, f) = X(:, f) .* exp(1j*2*pi*cfo(f)*t);
    end
end
end

function [sinr, ec, pe] = residual_metrics(x, r)
% Per frame: whole-frame LS gain for the SINR and the residual power pe;
% 32-sample block LS gains (absorb fading and gain steps) for the residual used in
% the envelope correlation.
B = 32;
nf = size(r, 2);
sinr = nan(1, nf); ec = nan(1, nf); pe = nan(1, nf);
for f = 1:nf
    xf = x(:, f); rf = r(:, f);
    if any(isnan(xf)), continue; end
    px = real(xf' * xf);
    if px <= 0, continue; end
    h = (xf' * rf) / px;
    e = rf - h * xf;
    sinr(f) = 10*log10(abs(h)^2 * px / max(real(e' * e), eps));
    pe(f) = real(e' * e) / numel(e);
    n = floor(numel(xf) / B) * B;
    X = reshape(xf(1:n), B, []); R = reshape(rf(1:n), B, []);
    hb = sum(conj(X) .* R, 1) ./ max(sum(abs(X).^2, 1), eps);
    E = R - X .* hb;
    c = corrcoef(abs(E(:)).^2, abs(X(:)).^2);
    ec(f) = c(1, 2);
end
end

function coh = quiet_coherence(iqa, p, qn)
% Spatial coherence of every frame's quiet slot, no signal of ours. The receive filter
% runs over the whole run as in the receiver, and the slot counts, as there, from its
% first sample whose filter memory lies in this frame (consecutive frames are a
% decision cycle apart in channel time).
[ns, na, nf] = size(iqa);
coh = nan(1, nf);
q0 = p.filter_span * p.sps + 1;
if qn < q0, return; end
h = rcosdesign(p.rolloff, p.filter_span, p.sps, 'sqrt');
rf = reshape(filter(h, 1, reshape(permute(iqa, [1 3 2]), ns * nf, na)), ns, nf, na);
for f = 1:nf
    q = reshape(rf(q0:qn, f, :), qn - q0 + 1, na);
    coh(f) = pair_coherence(q' * q);
end
end

function c = pair_coherence(R)
% Mean over the antenna pairs of |R_ij| / sqrt(R_ii R_jj); 0 with one antenna.
nr = size(R, 1);
dg = real(diag(R));
c = 0; np = 0;
for i = 1:nr
    for j = i+1:nr
        c = c + abs(R(i, j)) / sqrt(max(dg(i) * dg(j), eps)); np = np + 1;
    end
end
c = c / max(np, 1);
end

function d = gain_ant(Hq, nf)
% Mean channel gain of every antenna over the frame [dB] (antennas x frames).
d = nan(size(Hq, 1), nf);
for f = 1:min(nf, size(Hq, 3))
    d(:, f) = 10*log10(mean(abs(Hq(:, :, f)).^2, 2) + eps);
end
end

function nv = thermal_of(out, p)
% Thermal noise power per sample: the receiver's calibration constant (the AWGN
% setting of the run, signal power 1/sps per sample).
nv = NaN;
try
    mdl = out.SimulationMetadata.ModelInfo.ModelName;
    snr_s = str2double(get_param([mdl '/AWGN'], 'SNR'));
    nv = (1 / p.sps) / 10^(snr_s / 10);
catch
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
