function [ok, v12] = validate_phy(only, rows)
%% VALIDATE_PHY - Link physics against theory, multi-antenna UAV receiver
%   ok = validate_phy()                 every check
%   ok = validate_phy('flat')           every check but V12c (V12c alone below)
%   [ok, v12] = validate_phy('V12c')    V12c alone (results/phy_validation_v12c.txt); rows
%   [ok, v12] = validate_phy('V12c', rows)  picks cases of its table, v12 its results
%   [ok, v13] = validate_phy('V13')     V13 alone (results/phy_validation_v13.txt)
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
%   V8  jamming JSR 10 dB: MRC vs MMSE vs jammer-free MRC (spatial nulling); V8c/V8d, MMSE
%       with the jammer at the fixed direction nearest endfire, where its LoS Doppler
%       fd sin(aoa) is largest, against the same jammer with a frozen LoS (informational)
%   V9  seeds: same seed -> identical run, different seed -> different run
%   V10 tone jammer: in-band power after the receive filter equals that of a noise
%       jammer of the same JSR (tone_jamming uses the same JSR definition)
%   V1-V8 run the ideal receiver (known timing, frequency and symbols), the reference
%   of the closed forms. V11: the real receiver (training, pilots, synchronization,
%   frequency offset and arrival time on the air) on V1, V5 and V8b, and its Eb/N0 loss
%   against the ideal receiver.
%   V12: a specular ground reflection 0.8 of the line of sight with the measured excess
%   delay (80 ns) against the same ray without delay: the cost of the delay itself (a
%   flat channel model holds when it is small). V12b, informational (it does not gate):
%   the same ray 480 ns late, a 234 ns RMS delay spread, the median at 15-105 m of the
%   second environment of Rodriguez-Pineiro et al.
%   V12c, a gate on the flat channel: the tapped delay line (build_threat_model.m) against
%   the flat channel, real receiver, RMS delay spread 64-2250 ns (v12c). It stops the run
%   when the flat channel fails it while the link runs flat (p.tdl false). With the line on
%   the same table is the receiver's own verdict on the delay line, reported apart (it does
%   not stop the run: a failing case leaves its cells to the commitment).
%   V1-V12 run the flat channel of the closed forms.
%   V13, its own verdict (the rules above unchanged): the predicted MMSE gain over MRC
%   (mmse_predict.m, the policies' nulling input) against the theory of optimum combining
%   (Winters, Salz & Gitlin 1994) on the true channel and interference of every frame (our
%   own received component, the threat block's output 4 with p.own_out): the clean link, the
%   V8b and V11 jammer, the V12c jammers, the tone at 4/16/30 dB and the reactive jammer, on
%   the delay line as the profile runs it (V8b: flat, the closed forms' ideal receiver); the
%   clean link over the pools' draws; two dispersive clean corners, informational (v13).
%   It stops the run with the other checks.
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
p0.corr_random = false;                % each case sets its receive correlation
p0.k_random = false;                   % K-factor of each case fixed
p0.gcs_tracked = false;                % the GCS antenna on its axis: Eb/N0 as set
p0.gcs_aoa_random = false;             % the GCS at broadside
p0.body_random = false;                % equal branches, as the closed forms assume
p0.active_threat = 'none';
tdl_on = isfield(p0, 'tdl') && p0.tdl;  % the link runs the delay line
p0.tdl = false;

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
flat_only = nargin >= 1 && strcmpi(only, 'flat');
if nargin >= 1 && strcmpi(only, 'V12c')
    if nargin < 2, rows = []; end
    v12 = v12c(p0, modelName, delay_bits, rows);
    rep = [v12.rep, v12c_verdict(v12, tdl_on)];
    rep{end+1} = sprintf('V12c run time %.1f min', toc(t0)/60);
    if ~exist('results', 'dir'); mkdir('results'); end
    fid = fopen('results/phy_validation_v12c.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
    fprintf('\n%s\n', rep{:});
    if bdIsLoaded(modelName), close_system(modelName, 0); end
    ok = v12.pass || tdl_on;               % the channel model's gate; the receiver's verdict is v12.pass
    return
end
if nargin >= 1 && strcmpi(only, 'V13')
    v12 = v13(p0, modelName, delay_bits, S.params, tdl_on);
    rep = [v12.rep, {sprintf('V13 run time %.1f min', toc(t0)/60), sprintf('params_id %s', params_id(S.params))}];
    if ~exist('results', 'dir'); mkdir('results'); end
    fid = fopen('results/phy_validation_v13.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
    fprintf('\n%s\n', rep{:});
    if bdIsLoaded(modelName), close_system(modelName, 0); end
    ok = v12.pass;
    return
end

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
  'V8c jam endfire, MMSE',      0,   10,  0.3, 'jamming', 'mmse',  -1
  'V8d jam endfire, no LoS fd', 0,   10,  0.3, 'jamming', 'mmse',  -1
};
nC = size(cases, 1); nS = numel(CFG.EbNo);
% n_rx 0 = the system's antennas (params); theory order = antennas, -1 = no closed form
dflt = cell2mat(cases(:, 2)) == 0;
cases(dflt, 2) = {p0.n_rx};
cases(dflt, 1) = cellfun(@(n) sprintf('%s %d ant', n, p0.n_rx), cases(dflt, 1), 'UniformOutput', false);
th = cell2mat(cases(:, 7)); th(dflt & th == 0) = p0.n_rx; cases(:, 7) = num2cell(max(th, 0));
iTh = find(cell2mat(cases(:, 7))' > 0); nTh = numel(iTh);
iMRCj = find(startsWith(cases(:, 1), 'V8a')); iMMSEj = find(startsWith(cases(:, 1), 'V8b'));
iEnd = find(startsWith(cases(:, 1), 'V8c')); iFroz = find(startsWith(cases(:, 1), 'V8d'));
iDef = find(startsWith(cases(:, 1), 'V5 default'));
BER = nan(nC, nS); NERR = zeros(nC, nS); TH = nan(nC, nS); GAP = nan(nC, 1); GSE = nan(nC, 1);
DLY = nan(nC, 1);

for c = 1:nC
    p = p0;
    p.n_rx = cases{c,2}; p.rician_k = cases{c,3}; p.int_rician_k = 10;
    p.rx_corr = cases{c,4}; p.active_threat = cases{c,5}; p.rx_combiner = cases{c,6};
    p.jsr_db = 10; p.seed = 1000 + c; p.rx_sync = 'ideal';
    if ismember(c, [iEnd iFroz])
        p.int_aoa_deg(1) = p0.int_aoa_deg(end); p.seed = 1000 + iEnd;    % same flights, LoS Doppler on and off
        p.int_los_doppler = c == iEnd;
    end
    [BER(c,:), NERR(c,:), DLY(c), BR] = run_curve(p, modelName, CFG, delay_bits);
    L = cases{c,7};
    if L > 0
        TH(c,:) = ber_theory(CFG.EbNo, p.rician_k, L, p.rx_corr);
        [GAP(c), GSE(c)] = ebno_gap(CFG.EbNo, BER(c,:), NERR(c,:), TH(c,:), CFG.min_err, BR);
    end
    fprintf('%-26s gap %+5.2f dB | BER %s | %.1f min\n', cases{c,1}, GAP(c), ...
        sprintf('%.2e ', BER(c,:)), toc(t0)/60);
end

%% V11 real receiver against the ideal one
iReal = find(startsWith(cases(:, 1), 'V1 ') | startsWith(cases(:, 1), 'V5 default') | startsWith(cases(:, 1), 'V8b'))';
BERR = nan(numel(iReal), nS); LOSS = nan(numel(iReal), 1);
for i = 1:numel(iReal)
    c = iReal(i);
    p = p0;
    p.n_rx = cases{c,2}; p.rician_k = cases{c,3}; p.int_rician_k = 10;
    p.rx_corr = cases{c,4}; p.active_threat = cases{c,5}; p.rx_combiner = cases{c,6};
    p.jsr_db = 10; p.seed = 1000 + c; p.rx_sync = 'real';
    [BERR(i,:), ne] = run_curve(p, modelName, CFG, delay_bits);
    LOSS(i) = real_loss(CFG.EbNo, BERR(i,:), ne, BER(c,:), CFG.min_err);
    fprintf('V11 real, %-22s loss %+5.2f dB | BER %s | %.1f min\n', cases{c,1}, LOSS(i), ...
        sprintf('%.2e ', BERR(i,:)), toc(t0)/60);
end

%% V12 ground reflection: the measured excess delay against no delay
% specular ray 0.8 of the line of sight (the strongest measured, Sun et al.), excess delay
% 80 ns (the largest measured for it; a ground reflection's delay 2 h1 h2 / (d c) is about
% 10 ns at 2 km); the same ray without delay is the reference, so the shift is the cost
% of the delay alone. The late components behind the 153 ns RMS spread are weak (more
% than 25 dB down at 1.3 us, Sun), and the receiver has no equalizer for strong ones.
% V12b: 480 ns, whose RMS delay spread (0.8 / 1.64 of the delay) is the 234 ns median at
% 15-105 m of Rodriguez-Pineiro et al.'s second environment.
p = p0; p.rician_k = 10; p.active_threat = 'none'; p.rx_sync = 'ideal'; p.seed = 3001;
p.spec_amp = 0.8; p.spec_delay_ns = 0;
[BREF, ~] = run_curve(p, modelName, CFG, delay_bits);
DLY12 = [80 480]; BSP = nan(numel(DLY12), nS); SH12 = nan(1, numel(DLY12));
for i = 1:numel(DLY12)
    p.spec_delay_ns = DLY12(i);
    [BSP(i, :), ne] = run_curve(p, modelName, CFG, delay_bits);
    SH12(i) = real_loss(CFG.EbNo, BSP(i, :), ne, BREF, CFG.min_err);
    fprintf('V12 specular 0.8, %3d ns  shift %+5.2f dB | %.1f min\n', DLY12(i), SH12(i), toc(t0)/60);
end

%% V12c delay line against the flat channel (gate)
if flat_only
    v12 = struct('pass', true, 'rep', {{'V12c: not run here (validate_phy(''V12c''))'}});
else
    v12 = v12c(p0, modelName, delay_bits, []);
end
v12_ok = v12.pass || tdl_on;

%% V13 predicted MMSE gain against optimum-combining theory (its own verdict)
r13 = v13(p0, modelName, delay_bits, S.params, tdl_on);

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
rep{end+1} = sprintf(['V8c MMSE, jammer at %g deg (LoS Doppler %.0f Hz) vs V8d, the same flights with a frozen ' ...
    'jammer LoS: BER ratio %s'], p0.int_aoa_deg(end), CFG.fd_val * sind(p0.int_aoa_deg(end)), ...
    sprintf('%8.2f', BER(iEnd,:) ./ BER(iFroz,:)));
rep{end+1} = sprintf('V9 seeds: same seed identical %s, different seed differs %s (BER %s)', ...
    passfail(seed_same), passfail(seed_diff), mat2str(bs, 4));
rep{end+1} = sprintf('V10 tone jammer: in-band JSR after the receive filter %.2f dB (noise jammer %.2f dB, set %g dB) -> %s', ...
    jsr_tone, jsr_noise, p0.tone_jsr_db, passfail(tone_ok));
rep{end+1} = sprintf('V12 ground reflection (specular 0.8 of the LoS), no delay BER %s', sprintf('%9.2e', BREF));
for i = 1:numel(DLY12)
    rep{end+1} = sprintf('V12 excess delay %3d ns: BER %s | shift vs no delay %+.2f dB', DLY12(i), ...
        sprintf('%9.2e', BSP(i, :)), SH12(i)); %#ok<AGROW>
end
for i = 1:numel(iReal)
    rep{end+1} = sprintf('V11 real receiver, %-22s BER %s | loss vs ideal %+.2f dB', cases{iReal(i),1}, ...
        sprintf('%9.2e', BERR(i,:)), LOSS(i)); %#ok<AGROW>
end
rep = [rep, {''}, v12.rep];
if ~flat_only, rep = [rep, v12c_verdict(v12, tdl_on)]; end
rep = [rep, {''}, r13.rep];
rep{end+1} = sprintf(['Overall: theory gaps %d/%d within %.1f dB, seeds %s, tone %s, V12c channel model %s, ' ...
    'receiver on the delay line %s, V13 predicted MMSE gain %s | %.1f min'], sum(g_ok), nTh, CFG.gap_ok, ...
    passfail(seed_same && seed_diff), passfail(tone_ok), ternary(flat_only, 'not run', passfail(v12_ok)), ...
    ternary(flat_only || ~tdl_on, 'not run', passfail(v12.pass)), passfail(r13.pass), toc(t0)/60);
rep{end+1} = sprintf('Pass rule: |gap| <= %.1f dB or within 2 standard errors (spread over %d channel realizations).', CFG.gap_ok, CFG.n_real);
rep{end+1} = sprintf('params_id %s', params_id(S.params));
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

if bdIsLoaded(modelName), close_system(modelName, 0); end
ok = all(g_ok) && seed_same && seed_diff && tone_ok && v12_ok && r13.pass;
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

function R = v12c(p0, modelName, delay_bits, rows)
% V12c: the tapped delay line against the flat channel on the same flights, real receiver
% (with the line, its taps span the line's delays: rx_taps.m), at the nominal speed, so
% the shift is the delay spread's alone. RMS delay spreads: Lyu et al.'s 64 ns, the
% medians of Rodriguez-Pineiro et al. (138, 234, 302 ns; 372 ns, their directional fit at
% 75-105 m), 1 us and the clip of the drawn spreads, 2.25 us (p.tdl_clip_ns; the line
% reaches its flat profile there, about 1.5 us at K -5 dB and 1.4 us at K 2 dB, only the
% rows whose K lets it go beyond 1 us run it). (i) Clean link, our signal dispersive, MRC:
% shift <= 0.5 dB.
% (ii) A noise jammer at K 10 dB (16 and 30 dB, the jammer at p0.int_aoa_deg(1)), its
% channel dispersive and ours flat, MMSE: shift <= 3 dB. Shift: the largest over the
% points with >= 100 errors of the Eb/N0 shift to the flat curve's BER; a BER above the
% flat curve's highest counts from the lowest Eb/N0 (worst_shift).
% Informational (no limit): the 16 dB jammer at 234 ns and the envelope's top Doppler
% (161 km/h, 358 Hz), where the interferer's space-time null ages fastest.
CFG = struct('EbNo', 0:3:15, 'sim_time', 0.5, 'n_real', 20, 'fd_val', p0.fd_max, 'min_err', 100);
DS = [64 138 234 302 372 1000 2250];
D6 = DS(1:6);                         % the K 10 dB line holds its flat profile (767 ns) from 1 us
fdt = p0.v_max * p0.carrier_freq / p0.c_light;
C = {
  % name                          K    JSR  rho  threat     combiner  limit [dB] fd [Hz]    spreads [ns]
  'clean K -5 dB, MRC',           -5,  0,   0.3, 'none',    'mrc',    0.5,       p0.fd_max, DS
  'clean K 2 dB, MRC',             2,  0,   0.3, 'none',    'mrc',    0.5,       p0.fd_max, DS
  'clean K 10 dB, MRC',           10,  0,   0.3, 'none',    'mrc',    0.5,       p0.fd_max, D6
  'jam 16 dB, rho 0.3, MMSE',     10,  16,  0.3, 'jamming', 'mmse',   3,         p0.fd_max, D6
  'jam 16 dB, rho 0.9, MMSE',     10,  16,  0.9, 'jamming', 'mmse',   3,         p0.fd_max, D6
  'jam 30 dB, rho 0.3, MMSE',     10,  30,  0.3, 'jamming', 'mmse',   3,         p0.fd_max, D6
  'jam 30 dB, rho 0.9, MMSE',     10,  30,  0.9, 'jamming', 'mmse',   3,         p0.fd_max, D6
  'jam 16 dB, rho 0.3, 358 Hz',   10,  16,  0.3, 'jamming', 'mmse',   NaN,       fdt,       234
  'jam 16 dB, rho 0.9, 358 Hz',   10,  16,  0.9, 'jamming', 'mmse',   NaN,       fdt,       234
};
if isempty(rows), rows = 1:size(C, 1); end
nC = numel(rows); nD = numel(DS); nS = numel(CFG.EbNo);
nt = 1 + floor(p0.tdl_max_ns / p0.tdl_step_ns);
R = struct('name', {C(rows, 1)}, 'ds', DS, 'reached', nan(nC, nD), 'shift', nan(nC, nD), ...
    'limit', cell2mat(C(rows, 7)), 'fd', cell2mat(C(rows, 8)), 'ber_flat', nan(nC, nS), 'ber', nan(nC, nD, nS), ...
    'pass', true, 'rep', {{}});
t0 = tic;
for i = 1:nC
    c = rows(i);
    jam = ~strcmp(C{c,5}, 'none');
    p = p0; CFG.fd_val = C{c,8};
    p.rician_k = C{c,2}; p.int_rician_k = 10; p.jsr_db = C{c,3}; p.rx_corr = C{c,4};
    p.active_threat = C{c,5}; p.rx_combiner = C{c,6}; p.rx_sync = 'real'; p.seed = 4000 + c;
    [R.ber_flat(i, :), ~] = run_curve(p, modelName, CFG, delay_bits);
    p.tdl = true; p.tdl_random = false;
    for j = find(ismember(DS, C{c,9}))
        p.tdl_ds_ns = DS(j) * [~jam, jam];
        [b, ne] = run_curve(p, modelName, CFG, delay_bits);
        R.ber(i, j, :) = b;
        [~, R.reached(i, j)] = tdl_profile(DS(j), p.rician_k * ~jam + p.int_rician_k * jam, nt, p.tdl_step_ns);
        R.shift(i, j) = worst_shift(CFG.EbNo, b, ne, R.ber_flat(i, :), CFG.min_err);
        fprintf('V12c %-26s %4d ns  shift %+5.2f dB | %.1f min\n', C{c,1}, DS(j), R.shift(i, j), toc(t0)/60);
    end
end
ok = ~(R.shift > R.limit);                  % no point with enough errors, or no limit: no measurable loss
R.pass = all(ok(:));
R.rep{end+1} = sprintf(['V12c delay line vs flat channel: real receiver, fd %.0f Hz (358 Hz rows: %.0f Hz), %.1f s ' ...
    'per point over %d flights, taps %g ns apart up to %g ns, Eb/N0 %s dB'], p0.fd_max, fdt, CFG.sim_time, CFG.n_real, ...
    p0.tdl_step_ns, p0.tdl_max_ns, mat2str(CFG.EbNo));
R.rep{end+1} = sprintf('%-28s %s', 'RMS delay spread [ns]', sprintf('%8d', DS));
for i = 1:nC
    R.rep{end+1} = sprintf('%-28s %s', R.name{i}, sprintf('%8.0f', R.reached(i, :)));
    R.rep{end+1} = sprintf('%-28s %s  (%s)', '  shift [dB]', sprintf('%+8.2f', R.shift(i, :)), ...
        ternary(isfinite(R.limit(i)), sprintf('limit %.1f dB', R.limit(i)), 'informational'));
    R.rep{end+1} = sprintf('%-28s %s', '  flat BER', sprintf('%9.2e', R.ber_flat(i, :)));
    for j = find(isfinite(R.reached(i, :)))
        R.rep{end+1} = sprintf('%-28s %s -> %s', sprintf('  %4d ns BER', DS(j)), ...
            sprintf('%9.2e', squeeze(R.ber(i, j, :))), ternary(isfinite(R.limit(i)), passfail(ok(i, j)), 'info'));
    end
end
R.rep{end+1} = 'Rows: the spread the delay line reached at the case''s K (the flat profile when its window holds less).';
end

function R = v13(p0, modelName, delay_bits, P, tdl_on)
% V13: the predicted MMSE gain over MRC (mmse_predict.m, F.mmse_pred) against the theory of
% optimum combining on the true channel and interference of every frame, the real receiver
% (V8b: the ideal one), the frames after each run's first. The rows run the delay line as the
% profile P runs it ('run': P.tdl, the spreads drawn per flight with P.tdl_random), V8b the
% flat channel of the closed forms, the V12c jammers V12c's line (their channel at 234 ns,
% ours flat); 6 flights of 20 frames at Eb/N0 6 dB, K 10 dB. The clean link over the pools'
% draws (every draw of P: K, correlation, directions, attitude and spreads; the speed
% uniform over the envelope, the GCS at the distance of the Eb/N0, as pool_cell.m runs a
% flight), 100 flights of 12 frames at the grid's top Eb/N0, 15 dB, where our own echoes
% stand highest over the noise. Informational: two clean corners of the drawn range (K -5 dB
% at 1000 ns, K 0 dB at 300 ns), where the single-tap DMI suppresses our own echoes at
% whole-symbol lags that the single-tap MRC leaves (the deployed receivers equalize them,
% rx_taps.m), so G reads a few dB there.
% Theory (v13_theory): per held-out group of known symbols, our own received component on
% the true symbols around the group gives the channel h, the samples less h s the
% interference + noise covariance Rn; a combiner w reaches |w' h|^2 / (w' Rn w), the optimum
% w = Rn^-1 h reaches h' Rn^-1 h and MRC on the true channel |h|^4 / (h' Rn h) (Winters,
% Salz & Gitlin 1994); pooled over the groups as the measurement pools its held-out symbols.
% The closed form of one directional interferer, (1 + JMc)(1 - JMc / (1 + JM)), about
% JMc(1 - c) for a large JM (28 dB at J = 30 dB, M = 3, c = 1/3), from the largest
% eigenvalue of Rn over the floor (JM) and the share c of the channel's power in its
% direction, is printed beside.
% Checks: (a) the clean rows: at most 2% of their frames read G at or above the rule's
% threshold (decision_config.m rule_mmse_db: a false nulling flag); the fixed clean link's
% median G within 1 dB of the theory of its own combiners (the DMI's estimation loss, about
% 10 log10((K + 2 - M) / (K + 1)) with K = 16 training snapshots: -0.5 dB at M = 3, -0.8 dB
% at M = 4, the Reed-Mallett-Brennan mean, Besson 2021 eq. 21); over the pools' draws within
% 1 dB of 0;
% (b) every interferer row's median G within 3 dB of the theory of the two combiners the
% predictor formed (its DMI and MRC weights on the true channel and interference, each SINR
% floored at the measurement's resolution, 1 / the held-out symbols): the measurement;
% (c) every interferer row's median G at most 3 dB below the optimum-combining theory or the
% measurement's ceiling (the measured MMSE SINR over that floor), the lower: no collapse;
% (d) the tone's median G at least 3 dB higher at 16 dB than at 4 dB, and at 30 dB at most
% 3 dB below the lower of its 16 dB value and its own ceiling (a decision-directed reading
% stays near 0 dB at every level instead).
C = {
  % name                     threat              field          level  sync     combiner  line         rho  K    Eb/N0 flights frames kind
  'clean link',              'none',             'jsr_db',      0,     'real',  'mrc',    'run',       0.3, 10,  6,    6,      20,    'clean'
  'V8b jam 10 dB',           'jamming',          'jsr_db',      10,    'ideal', 'mmse',   'flat',      0.3, 10,  6,    6,      20,    'int'
  'V11 jam 10 dB',           'jamming',          'jsr_db',      10,    'real',  'mmse',   'run',       0.3, 10,  6,    6,      20,    'int'
  'V12c jam 16 dB rho 0.3',  'jamming',          'jsr_db',      16,    'real',  'mmse',   [0 234],     0.3, 10,  6,    6,      20,    'int'
  'V12c jam 16 dB rho 0.9',  'jamming',          'jsr_db',      16,    'real',  'mmse',   [0 234],     0.9, 10,  6,    6,      20,    'int'
  'V12c jam 30 dB rho 0.3',  'jamming',          'jsr_db',      30,    'real',  'mmse',   [0 234],     0.3, 10,  6,    6,      20,    'int'
  'V12c jam 30 dB rho 0.9',  'jamming',          'jsr_db',      30,    'real',  'mmse',   [0 234],     0.9, 10,  6,    6,      20,    'int'
  'tone 4 dB',               'tone_jamming',     'tone_jsr_db', 4,     'real',  'mrc',    'run',       0.3, 10,  6,    6,      20,    'int'
  'tone 16 dB',              'tone_jamming',     'tone_jsr_db', 16,    'real',  'mrc',    'run',       0.3, 10,  6,    6,      20,    'int'
  'tone 30 dB',              'tone_jamming',     'tone_jsr_db', 30,    'real',  'mrc',    'run',       0.3, 10,  6,    6,      20,    'int'
  'reactive 16 dB',          'reactive_jamming', 'jsr_db',      16,    'real',  'mrc',    'run',       0.3, 10,  6,    6,      20,    'int'
  'clean, pools'' draws',    'none',             'jsr_db',      0,     'real',  'mrc',    'run',       NaN, NaN, 15,   100,    12,    'pool'
  'clean K -5 dB 1000 ns',   'none',             'jsr_db',      0,     'real',  'mrc',    [1000 1000], 0.3, -5,  15,   6,      20,    'info'
  'clean K 0 dB 300 ns',     'none',             'jsr_db',      0,     'real',  'mrc',    [300 300],   0.3, 0,   15,   6,      20,    'info'
};
TOL = 3; FLAG = 0.02;
nC = size(C, 1); thr = decision_config().rule_mmse_db;
Q = nan(nC, 11);   % medians: G, theory of the predictor's combiners, optimum theory, ceiling, closed form,
                   % MMSE measured / theory (its weights), MRC measured / theory (its weights); share >= thr
NFM = zeros(nC, 1); LN = cell(nC, 1);
t0 = tic;
for c = 1:nC
    pool = strcmp(C{c,13}, 'pool');
    if pool, p = P; p.quiet_build = true; else, p = p0; p.rician_k = C{c,9}; p.int_rician_k = 10; p.rx_corr = C{c,8}; end
    p.active_threat = C{c,2}; p.(C{c,3}) = C{c,4}; p.rx_sync = C{c,5}; p.rx_combiner = C{c,6};
    p.own_out = true; p.seed = 7000 + c;
    if ischar(C{c,7})
        p.tdl = strcmp(C{c,7}, 'run') && tdl_on; p.tdl_random = isfield(P, 'tdl_random') && P.tdl_random;
    else
        p.tdl = true; p.tdl_random = false; p.tdl_ds_ns = C{c,7};
    end
    LN{c} = line_name(p);
    EB = C{c,10}; NSEED = C{c,11}; NFR = C{c,12};
    evalc('build_threat_model(p)');
    set_link_snr(modelName, EB + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
    rs = RandStream('mt19937ar', 'Seed', p.seed);
    A = [];
    for r = 1:NSEED
        if pool
            v = P.speed_kmh_min + (P.speed_kmh_max - P.speed_kmh_min) * rand(rs);
            link_seed(modelName, p.seed * 100 + r, v / 3.6 * p.carrier_freq / p.c_light, struct('ebno', EB, 'frames', NFR));
        else
            link_seed(modelName, p.seed * 100 + r, p.v_max * p.carrier_freq / p.c_light);
        end
        out = sim(modelName, 'StopTime', num2str((NFR - 1) * p.frame_duration));
        disk_guard;
        F = extract_closed_loop_frames(out, p, delay_bits);
        [~, D] = mmse_predict(out.get('Rx_IQ'), p, [F.sync_d; F.cfo_hz]);
        T = v13_theory(out, p, [F.sync_d; F.cfo_hz], D);
        v = 2:numel(F.mmse_pred);
        A = [A; [F.mmse_pred(v); T.mmse_est(v) - T.mrc_est(v); T.opt(v) - T.mrc(v); D.mmse_db(v) + 10*log10(D.n_ref); ...
            T.cf(v); D.mmse_db(v); T.mmse_est(v); D.mrc_db(v); T.mrc_est(v)]']; %#ok<AGROW>
    end
    Q(c, 1:9) = median(A, 1, 'omitnan');
    Q(c, 10) = mean(A(:, 1) >= thr); Q(c, 11) = mean(A(:, 3) >= thr); NFM(c) = sum(isfinite(A(:, 1)));
    fprintf('V13 %-24s G %+6.1f dB (its combiners %+6.1f, optimum %+6.1f), >= %g dB %4.1f%% | %.1f min\n', C{c,1}, ...
        Q(c, 1:3), thr, 100 * Q(c, 10), toc(t0)/60);
end
kind = C(:, 13);
ic = strcmp(kind, 'clean'); ip = strcmp(kind, 'pool'); ii = strcmp(kind, 'int'); gate = ~strcmp(kind, 'info');
ok = true(nC, 1);
ok(ii) = abs(Q(ii, 1) - Q(ii, 2)) <= TOL & Q(ii, 1) >= min(Q(ii, 3), Q(ii, 4)) - TOL;
ok(ic) = abs(Q(ic, 1) - Q(ic, 2)) <= 1 & Q(ic, 10) <= FLAG;
ok(ip) = abs(Q(ip, 1)) <= 1 & Q(ip, 10) <= FLAG;
it = find(startsWith(C(:, 1), 'tone'));
tone_ok = Q(it(2), 1) >= Q(it(1), 1) + 3 && Q(it(3), 1) >= min(Q(it(2), 1), Q(it(3), 4)) - TOL;
R = struct('name', {C(:, 1)}, 'Q', Q, 'ok', ok, 'gate', gate, 'tone_ok', tone_ok, 'pass', all(ok(gate)) && tone_ok, ...
    'rep', {{}});
grp = mmse_predict('groups', p0);
R.rep{end+1} = sprintf(['V13 predicted MMSE gain over MRC (mmse_predict.m) vs optimum combining on the true channel: ' ...
    '%d antennas, %d held-out known symbols per frame, the frames after each run''s first; medians [dB]'], p0.n_rx, ...
    sum(cellfun(@numel, grp(2:end))));
R.rep{end+1} = sprintf('%-24s %-9s %5s %6s %7s %9s %8s %8s %8s %13s %13s %13s', 'row', 'line [ns]', 'Eb/N0', 'frames', 'G', ...
    'its comb.', 'optimum', 'ceiling', 'JMc(1-c)', 'MMSE meas/th', 'MRC meas/th', sprintf('>=%g dB G/opt', thr));
for c = 1:nC
    vd = passfail(ok(c)); if ~gate(c), vd = 'info'; end
    R.rep{end+1} = sprintf('%-24s %-9s %5g %6d %+7.1f %+9.1f %+8.1f %+8.1f %+8.1f %6.1f/%6.1f %6.1f/%6.1f %5.1f%%/%4.0f%%  %s', ...
        C{c,1}, LN{c}, C{c,10}, NFM(c), Q(c, 1:5), Q(c, 6:9), 100 * Q(c, 10:11), vd);
end
R.rep{end+1} = sprintf(['V13 rules: the clean rows at most %g%% of frames at or above %g dB, the clean link within 1 dB of ' ...
    'the theory of its combiners (the DMI''s estimation loss), the pools'' draws within 1 dB of 0; every interferer row ' ...
    'within %g dB of the theory of its combiners and at most %g dB below the optimum or the ceiling, the lower; the ' ...
    'tone rising from 4 to 16 dB and holding at 30 dB (%+.1f, %+.1f, %+.1f dB) -> %s; the corners informational'], ...
    100 * FLAG, thr, TOL, TOL, Q(it, 1), passfail(tone_ok));
R.rep{end+1} = sprintf('V13 predicted MMSE gain: %d/%d rows -> %s', sum(ok & gate), sum(gate), passfail(R.pass));
end

function s = line_name(p)
% The channel a V13 row runs: flat, the drawn delay line, or its fixed spreads [ns].
if ~p.tdl, s = 'flat';
elseif p.tdl_random, s = 'drawn';
else, s = sprintf('%g/%g', p.tdl_ds_ns(1), p.tdl_ds_ns(end));
end
end

function T = v13_theory(out, p, sy, D)
% Optimum combining and the predictor's own combiners on the true channel and interference of
% every frame of one run, per held-out group of known symbols (mmse_predict.m), pooled over the
% groups as the measurement pools its held-out symbols (one gain fitted over all of them) [dB]:
% opt and mrc, the optimum and MRC on the true channel at the arrival and frequency the
% predictor measured MMSE at; mmse_est, the predictor's DMI weights there, and mrc_est, its MRC
% weights at the receiver's arrival and frequency, where it measured MRC, both floored at
% 1 / the held-out symbols; cf, the closed form of one directional interferer.
own = out.get('Thr_sig') * str2double(get_param([out.SimulationMetadata.ModelInfo.ModelName '/Level'], 'Gain'));
iq = out.get('Rx_IQ');
nf = size(iq, 3); own = own(:, :, 1:nf);
[Y, Yo] = v13_snapshots(iq, own, p, [D.arrival; sy(2, :)], D.df_hz);
[Yr, Yor] = v13_snapshots(iq, own, p, [round(sy(1, :)); sy(2, :)], D.df_mrc_hz);
[grp, sk] = mmse_predict('groups', p);
L = frame_layout(p); bpf = p.frame_length; NS = L.n_sig; ng = numel(grp); fl = 1 / D.n_ref;
txb = double(squeeze(out.get('tx_bits_out'))); txb = txb(:);
T = struct('opt', nan(1, nf), 'mrc', nan(1, nf), 'mmse_est', nan(1, nf), 'mrc_est', nan(1, nf), 'cf', nan(1, nf));
pool0 = @(n, c, v) abs(sum(n .* c) / sum(n))^2 / (sum(n .* (abs(c - sum(n .* c) / sum(n)).^2 + v)) / sum(n));
pool = @(n, c, v) max(pool0(n, c, v), fl);
for f = 1:nf
    if f * bpf > numel(txb) || any(isnan(reshape(Y(:, :, f), [], 1))) || any(isnan(reshape(Yr(:, :, f), [], 1)))
        continue
    end
    s = sk; s(L.idx_data - L.NQ) = pskmod(txb((f-1)*bpf + (1:bpf)), 4, pi/4, 'gray', 'InputType', 'bit');
    n = zeros(1, ng - 1); vo = n; vr = n; cr = n; ver = n; cm = n; vem = n; jm = n; cc = n;
    for g = 2:ng
        i = g - 1; k = grp{g}; c0 = round(mean(k)); kw = max(1, c0 - 32):min(NS, c0 + 32);
        h = Yo(kw, :, f).' * conj(s(kw)) / numel(kw);
        E = Y(kw, :, f).' - h * s(kw).'; Rn = E * E' / numel(kw);
        n(i) = numel(k);
        vo(i) = 1 / real(h' * (Rn \ h));
        vr(i) = real(h' * Rn * h) / real(h' * h)^2;
        hr = Yor(kw, :, f).' * conj(s(kw)) / numel(kw);
        E = Yr(kw, :, f).' - hr * s(kw).'; Rr = E * E' / numel(kw);
        wr = D.w_mrc(:, g, f); wm = D.w_mmse(:, g, f); rm = D.r_mmse(:, g, f);
        cr(i) = (wr' * hr) / real(wr' * wr); ver(i) = real(wr' * Rr * wr) / real(wr' * wr)^2;
        cm(i) = (wm' * h) / (wm' * rm); vem(i) = real(wm' * Rn * wm) / abs(wm' * rm)^2;
        [V, Lm] = eig((Rn + Rn') / 2); [lm, o] = sort(real(diag(Lm)), 'descend');
        s2 = mean(lm(2:end)); jm(i) = (lm(1) - s2) / s2; cc(i) = abs(V(:, o(1))' * h)^2 / real(h' * h);
    end
    u = ones(1, ng - 1);
    T.opt(f) = 10*log10(pool0(n, u, vo)); T.mrc(f) = 10*log10(pool0(n, u, vr));
    T.mrc_est(f) = 10*log10(pool(n, cr, ver)); T.mmse_est(f) = 10*log10(pool(n, cm, vem));
    JM = median(jm); c = median(cc);
    T.cf(f) = 10*log10((1 + JM * c) * (1 - JM * c / (1 + JM)));
end
end

function [Y, Yo] = v13_snapshots(iq, own, p, sa, df)
% The received and our own component's snapshots at arrival and frequency sa (2 x frames), the
% frequency df [Hz] removed as mmse_predict.m removes it.
Y = mmse_predict('snapshots', iq, p, sa); Yo = mmse_predict('snapshots', own, p, sa);
rot = exp(-1j * 2*pi * (0:size(Y, 1) - 1)' .* reshape(df, 1, 1, []) / p.symbol_rate);
rot(isnan(rot)) = 1;
Y = Y .* rot; Yo = Yo .* rot;
end

function r = v12c_verdict(v12, tdl_on)
% V12c's two readings: whether the flat channel holds (the channel model's gate) and, with
% the delay line on, whether the receiver meets the limits on it (its own verdict).
if all(~isfinite(v12.limit))
    r = {'V12c: informational cases only, no verdict'};
    return
elseif v12.pass
    r = {'V12c channel model: the flat channel holds -> PASS'};
elseif tdl_on
    r = {'V12c channel model: the flat channel fails, the link runs the delay line -> PASS'};
else
    r = {'V12c channel model: the flat channel fails and the link runs flat -> FAIL'};
end
if tdl_on
    bad = v12.name(any(v12.shift > v12.limit, 2));
    r{end+1} = sprintf('V12c receiver on the delay line: %s%s', passfail(v12.pass), ...
        ternary(isempty(bad), '', sprintf(' (above the limit: %s)', strjoin(bad', '; '))));
end
end

function d = worst_shift(ebno, ber, nerr, ref, min_err)
% Largest Eb/N0 shift [dB] at which the reference curve reaches each measured BER, over
% the points with enough errors; a BER above the reference's highest counts from the
% reference's lowest Eb/N0 (a floor), one below its lowest is skipped.
r = find(ref > 0);
d = NaN;
if numel(r) < 2, return; end
lr = log10(cummin(ref(r)));                % the reference falls with Eb/N0
[lr, u] = unique(lr, 'stable'); er = ebno(r(u));
x = nan(1, numel(ebno));
for j = find(nerr >= min_err & ber > 0)
    lb = log10(ber(j));
    if lb > lr(1)
        x(j) = ebno(j) - er(1);
    elseif lb >= lr(end)
        x(j) = ebno(j) - interp1(lr, er, lb, 'linear');
    end
end
d = max(x, [], 'omitnan');
end

%% ===================== Local functions =====================
function [ber, nerr, dly, BR] = run_curve(p, modelName, CFG, delay_bits)
tb = tic; evalc('build_threat_model(p)');                 % built in memory: params.mat is not written
set_param(modelName, 'SimulationCommand', 'update');
fprintf('    build + compile %.1f s\n', toc(tb));
nS = numel(CFG.EbNo); ber = nan(1, nS); nerr = zeros(1, nS); dly = NaN; BR = [];
for s = 1:nS
    snr_dB = CFG.EbNo(s) + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
    set_link_snr(modelName, snr_dB, p);
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

function d = real_loss(ebno, ber, nerr, ref, min_err)
% Mean Eb/N0 shift [dB] at which the reference curve reaches each measured BER, over
% the points with enough errors where the reference has errors too.
v = find(nerr >= min_err & ber > 0);
r = ref > 0;
d = NaN;
if isempty(v) || sum(r) < 2, return; end
x = nan(1, numel(v));
for i = 1:numel(v)
    j = v(i);
    if ber(j) > max(ref(r)) || ber(j) < min(ref(r)), continue; end
    x(i) = ebno(j) - interp1(log10(ref(r)), ebno(r), log10(ber(j)), 'linear');
end
d = mean(x, 'omitnan');
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

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
