function ok = validate_phy()
%% VALIDATE_PHY - Link physics against theory, multi-antenna UAV receiver
% Runs the threat model (UAV_GCS_Threat_Link) and compares the measured BER with
% closed-form results:
%   V1  AWGN (K = 60 dB, 1 antenna)          vs berawgn (closed-form QPSK in AWGN)
%   V2  Rician K = 10 dB, 1 antenna          vs MGF integral (Alouini & Goldsmith, 1999)
%   V3  Rician K = 10 dB, MRC 2 antennas     vs MGF integral, independent branches
%   V4  Rician K = 10 dB, MRC 3 antennas     vs MGF integral, independent branches
%   V5  default link (params n_rx antennas, rho = 0.3) vs MGF integral, correlated
%       branches (non-central quadratic form, Ramirez-Espinosa et al., 2018)
%   V6  K = -5 dB and V7 K = 20 dB, the default antennas: the ends of the K-factor
%       range drawn per flight (channel_k.m)
%   V8  jamming JSR 10 dB: MRC vs MMSE vs jammer-free MRC (spatial nulling)
%   V9  seeds: same seed -> identical run, different seed -> different run
%   V10 tone jammer: in-band power after the receive filter equals that of a noise
%       jammer of the same JSR (tone_jamming uses the same JSR definition)
% Gap = Eb/N0 shift between measured and theoretical BER, points with >= 100 errors.
% Outputs: results/phy_validation.txt, results/phy_validation.png

if ~exist('params.mat', 'file')
    error('params.mat not found. Run init_params.m first.');
end
warning('off', 'Simulink:cgxe:LeakedJITEngine');
S = load('params.mat'); p0 = S.params;
if ~isfield(p0, 'n_rx')
    error('params.mat has no antenna fields. Run init_params.m first.');
end
p0.quiet_build = true;
p0.int_aoa_random = false;             % V8 nulling test at the fixed direction p0.int_aoa_deg(1)
p0.yaw_random = false;                 % fixed geometry through every run
p0.k_random = false;                   % K-factor of each case fixed
p0.active_threat = 'none';

CFG.EbNo      = 0:2:10;      % [dB] per branch
CFG.sim_time  = 1.0;         % [s] per Eb/N0 point (2e6 bits), split over CFG.n_real channel realizations
CFG.n_real    = 20;          % independent seeds per Eb/N0 point
CFG.fd_val    = p0.v_max * p0.carrier_freq / p0.c_light;   % [Hz] the envelope's worst-case Doppler (358 Hz).
                             % Every frame is one decision cycle of channel time apart (p0.cycle_s), so
                             % each frame is an independent fade (~1900 per point); the theory assumes the
                             % channel constant over the 64-symbol estimation window (358 Hz x 64 us = 0.023)
CFG.min_err   = 100;         % errors needed for a point to enter the gap metric
CFG.gap_ok    = 0.3;         % [dB] pass threshold (or within 2 standard errors of the fading Monte Carlo)
modelName     = 'UAV_GCS_Threat_Link';
delay_bits    = 20;
t0 = tic;

cases = {
  % name                       n_rx  K    rho  threat     combiner  theory
  'V1 AWGN, 1 ant',             1,   60,  0,   'none',    'mrc',    1
  'V2 Rician, 1 ant',           1,   10,  0,   'none',    'mrc',    1
  'V3 Rician, MRC 2 ant',       2,   10,  0,   'none',    'mrc',    2
  'V4 Rician, MRC 3 ant',       3,   10,  0,   'none',    'mrc',    3
  'V5 default, MRC',            0,   10,  0.3, 'none',    'mrc',    0
  'V6 K = -5 dB, MRC',          0,   -5,  0.3, 'none',    'mrc',    0
  'V7 K = 20 dB, MRC',          0,   20,  0.3, 'none',    'mrc',    0
  'V8a jam 10 dB, MRC',         0,   10,  0.3, 'jamming', 'mrc',   -1
  'V8b jam 10 dB, MMSE',        0,   10,  0.3, 'jamming', 'mmse',  -1
};
nC = size(cases, 1); nS = numel(CFG.EbNo);
% n_rx 0 = the system's antennas (params); theory order = antennas, -1 = no closed form
dflt = cell2mat(cases(:, 2)) == 0;
cases(dflt, 2) = {p0.n_rx};
cases(dflt, 1) = cellfun(@(n) sprintf('%s %d ant', n, p0.n_rx), cases(dflt, 1), 'UniformOutput', false);
th = cell2mat(cases(:, 7)); th(dflt & th == 0) = p0.n_rx; cases(:, 7) = num2cell(max(th, 0));
iTh = find(cell2mat(cases(:, 7))' > 0); nTh = numel(iTh);
iMRCj = find(startsWith(cases(:, 1), 'V8a')); iMMSEj = find(startsWith(cases(:, 1), 'V8b'));
iDef = find(startsWith(cases(:, 1), 'V5 default'));
BER = nan(nC, nS); NERR = zeros(nC, nS); TH = nan(nC, nS); GAP = nan(nC, 1); GSE = nan(nC, 1);
DLY = nan(nC, 1);

for c = 1:nC
    p = p0;
    p.n_rx = cases{c,2}; p.rician_k = cases{c,3}; p.int_rician_k = 10;
    p.rx_corr = cases{c,4}; p.active_threat = cases{c,5}; p.rx_combiner = cases{c,6};
    p.jsr_db = 10; p.seed = 1000 + c;
    [BER(c,:), NERR(c,:), DLY(c), BR] = run_curve(p, modelName, CFG, delay_bits);
    L = cases{c,7};
    if L > 0
        TH(c,:) = ber_theory(CFG.EbNo, p.rician_k, L, p.rx_corr);
        [GAP(c), GSE(c)] = ebno_gap(CFG.EbNo, BER(c,:), NERR(c,:), TH(c,:), CFG.min_err, BR);
    end
    fprintf('%-26s gap %+5.2f dB | BER %s | %.1f min\n', cases{c,1}, GAP(c), ...
        sprintf('%.2e ', BER(c,:)), toc(t0)/60);
end

%% V9 seeds (default link, 4 dB)
p = p0; p.rician_k = 10; p.active_threat = 'none';
sd = [2001 2001 2002]; bs = nan(1, 3);
for i = 1:3
    p.seed = sd(i);
    b = run_curve(p, modelName, struct('EbNo', 4, 'sim_time', 0.1), delay_bits);
    bs(i) = b;
end
seed_same = bs(1) == bs(2);
seed_diff = bs(1) ~= bs(3);

%% V10 tone jammer calibration
[jsr_noise, jsr_tone] = tone_check(p0);
tone_ok = abs(jsr_tone - jsr_noise) <= 0.5;

%% Report
g_ok = abs(GAP(iTh)) <= max(CFG.gap_ok, 2 * GSE(iTh));
jam_gain = 10*log10(BER(iMRCj,:) ./ BER(iMMSEj,:));
rep = {};
rep{end+1} = '=== PHY VALIDATION: multi-antenna UAV receiver vs theory ===';
rep{end+1} = sprintf('Generated: %s | %.1f s per point, %d channel realizations, fd %.0f Hz | CSI block %d sym (MRC), window %d sym (MMSE)', ...
    datestr(now), CFG.sim_time, CFG.n_real, CFG.fd_val, p0.csi_block, p0.mmse_window);
rep{end+1} = sprintf('Eb/N0 per branch [dB]: %s', mat2str(CFG.EbNo));
rep{end+1} = '';
for c = 1:nC
    rep{end+1} = sprintf('%-26s BER  %s', cases{c,1}, sprintf('%9.2e', BER(c,:))); %#ok<SAGROW>
    rep{end+1} = sprintf('%-26s err  %s', '', sprintf('%9d', NERR(c,:))); %#ok<SAGROW>
    if cases{c,7} > 0
        rep{end+1} = sprintf('%-26s th.  %s', '', sprintf('%9.2e', TH(c,:))); %#ok<SAGROW>
    end
    if cases{c,7} > 0
        rep{end+1} = sprintf('%-26s gap %+.2f dB (standard error %.2f dB) -> %s  (bit delay found: %d)', '', ...
            GAP(c), GSE(c), passfail(g_ok(iTh == c)), DLY(c)); %#ok<SAGROW>
    end
end
rep{end+1} = '';
rep{end+1} = sprintf('V8 MMSE vs MRC under jamming (JSR 10 dB, interferer at %g deg): BER ratio [dB] %s', ...
    p0.int_aoa_deg(1), sprintf('%6.1f', jam_gain));
rep{end+1} = sprintf('V8 MMSE under jamming vs jammer-free MRC (V5): BER ratio %s', ...
    sprintf('%8.2f', BER(iMMSEj,:) ./ BER(iDef,:)));
rep{end+1} = sprintf('V9 seeds: same seed identical %s, different seed differs %s (BER %s)', ...
    passfail(seed_same), passfail(seed_diff), mat2str(bs, 4));
rep{end+1} = sprintf('V10 tone jammer: in-band JSR after the receive filter %.2f dB (noise jammer %.2f dB, set %g dB) -> %s', ...
    jsr_tone, jsr_noise, p0.tone_jsr_db, passfail(tone_ok));
rep{end+1} = sprintf('Overall: theory gaps %d/%d within %.1f dB, seeds %s, tone %s | %.1f min', ...
    sum(g_ok), nTh, CFG.gap_ok, passfail(seed_same && seed_diff), passfail(tone_ok), toc(t0)/60);
rep{end+1} = sprintf('Pass rule: |gap| <= %.1f dB or within 2 standard errors (spread over %d channel realizations).', CFG.gap_ok, CFG.n_real);
if ~exist('results', 'dir'); mkdir('results'); end
fid = fopen('results/phy_validation.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});

%% Figure
f = figure('Position', [100 100 1150 450], 'Color', 'w');
subplot(1, 2, 1); hold on; grid on; box on;
col = lines(nTh);
for k = 1:nTh
    c = iTh(k);
    v = NERR(c,:) > 0;
    semilogy(CFG.EbNo(v), BER(c,v), 'o', 'Color', col(k,:), 'MarkerFaceColor', col(k,:), ...
        'DisplayName', [cases{c,1} ' (sim)']);
    semilogy(CFG.EbNo, TH(c,:), '-', 'Color', col(k,:), 'HandleVisibility', 'off');
end
set(gca, 'YScale', 'log'); ylim([1e-6 0.2]);
xlabel('E_b/N_0 per antenna [dB]'); ylabel('BER');
title('QPSK, coherent MRC: simulation (markers) vs theory (lines)'); legend('Location', 'southwest', 'FontSize', 7);
subplot(1, 2, 2); hold on; grid on; box on;
semilogy(CFG.EbNo, BER(iMRCj,:), 'rs-', 'DisplayName', 'jamming 10 dB, MRC');
semilogy(CFG.EbNo, BER(iMMSEj,:), 'bo-', 'DisplayName', 'jamming 10 dB, MMSE (spatial action)');
semilogy(CFG.EbNo, BER(iDef,:), 'k--', 'DisplayName', 'no jammer, MRC');
set(gca, 'YScale', 'log'); ylim([1e-6 1]);
xlabel('E_b/N_0 per antenna [dB]'); ylabel('BER');
title(sprintf('Spatial nulling, %d antennas, jammer at %g deg', p0.n_rx, p0.int_aoa_deg(1)));
legend('Location', 'southwest', 'FontSize', 8);
exportgraphics(f, 'results/phy_validation.png', 'Resolution', 150);

params = S.params; save('params.mat', 'params');
if bdIsLoaded(modelName), close_system(modelName, 0); end
ok = all(g_ok) && seed_same && seed_diff && tone_ok;
end

function [jn, jt] = tone_check(p)
% In-band power over our signal after the receive filter [dB], for a noise jammer
% of power 10^(JSR/10) per sample and for the tone of build_threat_model.m at
% 60% of its largest offset, both at p.tone_jsr_db.
rs = RandStream('mt19937ar', 'Seed', 5);
h = rcosdesign(p.rolloff, p.filter_span, p.sps, 'sqrt');
fs = p.symbol_rate * p.sps; N = 2^16;
bits = randi(rs, [0 1], 2 * N / p.sps, 1);
x = upfirdn(pskmod(bits, 4, pi/4, 'gray', 'InputType', 'bit'), h, p.sps);
g = 10^(p.tone_jsr_db / 10);
w = sqrt(g / 2) * complex(randn(rs, N, 1), randn(rs, N, 1));
t = (0:N-1)' / fs;
v = sqrt(g / p.sps) * exp(1j * 2*pi * 0.6 * p.tone_offset_hz * t);
pw = @(y) mean(abs(y(numel(h):end - numel(h))).^2);
ps = pw(filter(h, 1, x(1:N)));
jn = 10*log10(pw(filter(h, 1, w)) / ps);
jt = 10*log10(pw(filter(h, 1, v)) / ps);
end

%% ===================== Local functions =====================
function [ber, nerr, dly, BR] = run_curve(p, modelName, CFG, delay_bits)
params = p; save('params.mat', 'params'); %#ok<NASGU>
tb = tic; evalc('build_threat_model');
set_param(modelName, 'SimulationCommand', 'update');
fprintf('    build + compile %.1f s\n', toc(tb));
nS = numel(CFG.EbNo); ber = nan(1, nS); nerr = zeros(1, nS); dly = NaN; BR = [];
for s = 1:nS
    snr_dB = CFG.EbNo(s) + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
    set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), 'SignalPower', num2str(1/p.sps));
    nr = 1; if isfield(CFG, 'n_real'), nr = CFG.n_real; end
    fdv = p.fd_max; if isfield(CFG, 'fd_val'), fdv = CFG.fd_val; end
    e_tot = 0; n_tot = 0; br = zeros(1, nr);
    for r = 1:nr
        if nr > 1, link_seed(modelName, p.seed * 100 + r, fdv); end
        out = sim(modelName, 'StopTime', num2str(CFG.sim_time / nr));
        tx = double(squeeze(out.get('tx_bits_out'))); tx = tx(:);
        rx = double(squeeze(out.get('rx_bits_out'))); rx = rx(:);
        disk_guard;
        if s == 1 && r == 1
            b = inf(1, 61);
            for d = 0:60
                L = min(numel(tx), numel(rx) - d);
                b(d+1) = mean(tx(1:min(L, 20000)) ~= rx(d+1:d+min(L, 20000)));
            end
            [~, i] = min(b); dly = i - 1;
        end
        dl = delay_bits;
        if isfield(p, 'quiet_symbols') && p.quiet_symbols >= p.filter_span, dl = 0; end   % receiver aligns each frame
        L = min(numel(tx), numel(rx) - dl);
        er = sum(tx(1:L) ~= rx(dl+1:dl+L));
        br(r) = er / L;
        e_tot = e_tot + er;
        n_tot = n_tot + L;
    end
    nerr(s) = e_tot; ber(s) = e_tot / n_tot;
    BR(:, s) = br(:);
end
end

function pb = ber_theory(ebno_db, k_db, L, rho)
% QPSK (Gray) = BPSK per bit; L-branch MRC over Rician branches with LoS mean mu
% and diffuse covariance Sig = rho^|i-j| / (K+1), per-branch Eb/N0. Average BER as
% the Craig-form integral of the MGF of the combined SNR (Alouini & Goldsmith, 1999,
% eqs. (20), (37)); MGF of the non-central quadratic form ||h||^2 (Ramirez-Espinosa
% et al., 2018, eq. (11) and Sec. V):
%   M(s) = exp(s*mu'*(I - s*Sig)^-1*mu) / det(I - s*Sig),  s = -(Eb/N0)/sin^2(theta)
% rho = 0 reduces to the product of independent Rician MGFs. K = 60 dB gives AWGN.
if nargin < 4, rho = 0; end
K = 10^(k_db/10);
mu = sqrt(K/(K+1)) * ones(L, 1);
Sig = rho .^ abs((1:L)' - (1:L)) / (K+1);
pb = zeros(size(ebno_db));
for i = 1:numel(ebno_db)
    if k_db >= 50
        pb(i) = berawgn(ebno_db(i), 'psk', 4, 'nondiff');
        continue;
    end
    g = 10^(ebno_db(i)/10);
    pb(i) = integral(@(t) arrayfun(@(tt) mgf(-g / sin(tt)^2, mu, Sig, L), t), 0, pi/2) / pi;
end
end

function m = mgf(s, mu, Sig, L)
A = eye(L) - s * Sig;
m = real(exp(s * (mu' * (A \ mu))) / det(A));
end

function [gap, se] = ebno_gap(ebno, ber, nerr, th, min_err, BR)
% Mean Eb/N0 shift [dB] at which theory reaches each measured BER (positive = worse).
% Standard error by batch means: the realizations are split into 5 batches, the gap
% is computed per batch on the same Eb/N0 points, SE = std(batch gaps)/sqrt(5).
% This keeps the correlation between Eb/N0 points (same channels at every point).
v = find(nerr >= min_err & ber > 0);
gap = NaN; se = NaN;
if isempty(v), return; end
gap = shift(ebno, ber, th, v);
nb = 5; nr = size(BR, 1);
if nr >= nb
    g = zeros(1, nb);
    for b = 1:nb
        rows = b:nb:nr;
        g(b) = shift(ebno, mean(BR(rows, :), 1), th, v);
    end
    se = std(g(isfinite(g))) / sqrt(sum(isfinite(g)));
end
end

function d = shift(ebno, ber, th, v)
lt = log10(th); x = zeros(1, numel(v));
for i = 1:numel(v)
    j = v(i);
    if ber(j) <= 0, x(i) = NaN; continue; end
    x(i) = ebno(j) - interp1(fliplr(lt), fliplr(ebno), log10(ber(j)), 'linear', 'extrap');
end
d = mean(x, 'omitnan');
end

function s = passfail(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end
