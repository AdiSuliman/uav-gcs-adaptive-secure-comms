function validate_phy()
%% VALIDATE_PHY - Link physics against theory, multi-antenna UAV receiver (D41)
% Runs the threat model (UAV_GCS_Threat_Link) and compares the measured BER with
% closed-form results:
%   V1  AWGN (K = 60 dB, 1 antenna)          vs berawgn (Proakis)
%   V2  Rician K = 10 dB, 1 antenna          vs MGF integral (Simon & Alouini)
%   V3  Rician K = 10 dB, MRC 2 antennas     vs MGF integral, independent branches
%   V4  Rician K = 10 dB, MRC 3 antennas     vs MGF integral, independent branches
%   V5  default link (2 antennas, rho = 0.3) against V3 theory (correlation penalty)
%   V6  jamming JSR 10 dB: MRC vs MMSE vs jammer-free MRC (spatial nulling)
%   V7  seeds: same seed -> identical run, different seed -> different run
% Gap = Eb/N0 shift between measured and theoretical BER, points with >= 100 errors.
% Outputs: results/phy_validation.txt, results/phy_validation.png

if ~exist('params.mat', 'file')
    error('params.mat not found. Run init_params.m first.');
end
warning('off', 'Simulink:cgxe:LeakedJITEngine');
S = load('params.mat'); p0 = S.params;
if ~isfield(p0, 'n_rx')
    error('params.mat predates D41. Run init_params.m first.');
end
p0.quiet_build = true;
p0.active_threat = 'none';

CFG.EbNo      = 0:2:10;      % [dB] per branch
CFG.sim_time  = 0.5;         % [s] per Eb/N0 point (1e6 bits)
CFG.min_err   = 100;         % errors needed for a point to enter the gap metric
CFG.gap_ok    = 0.3;         % [dB] pass threshold
modelName     = 'UAV_GCS_Threat_Link';
delay_bits    = 20;
t0 = tic;

cases = {
  % name                       n_rx  K    rho  threat     combiner  theory
  'V1 AWGN, 1 ant',             1,   60,  0,   'none',    'mrc',    1
  'V2 Rician, 1 ant',           1,   10,  0,   'none',    'mrc',    1
  'V3 Rician, MRC 2 ant',       2,   10,  0,   'none',    'mrc',    2
  'V4 Rician, MRC 3 ant',       3,   10,  0,   'none',    'mrc',    3
  'V5 default, MRC 2 ant',      2,   10,  0.3, 'none',    'mrc',    2
  'V6a jam 10 dB, MRC',         2,   10,  0.3, 'jamming', 'mrc',    0
  'V6b jam 10 dB, MMSE',        2,   10,  0.3, 'jamming', 'mmse',   0
};
nC = size(cases, 1); nS = numel(CFG.EbNo);
BER = nan(nC, nS); NERR = zeros(nC, nS); TH = nan(nC, nS); GAP = nan(nC, 1);
DLY = nan(nC, 1);

for c = 1:nC
    p = p0;
    p.n_rx = cases{c,2}; p.rician_k = cases{c,3}; p.int_rician_k = 10;
    p.rx_corr = cases{c,4}; p.active_threat = cases{c,5}; p.rx_combiner = cases{c,6};
    p.jsr_db = 10; p.seed = 1000 + c;
    [BER(c,:), NERR(c,:), DLY(c)] = run_curve(p, modelName, CFG, delay_bits);
    L = cases{c,7};
    if L > 0
        TH(c,:) = ber_theory(CFG.EbNo, p.rician_k, L);
        GAP(c) = ebno_gap(CFG.EbNo, BER(c,:), NERR(c,:), TH(c,:), CFG.min_err);
    end
    fprintf('%-26s gap %+5.2f dB | BER %s | %.1f min\n', cases{c,1}, GAP(c), ...
        sprintf('%.2e ', BER(c,:)), toc(t0)/60);
end

%% V7 seeds (default link, 4 dB)
p = p0; p.rician_k = 10; p.active_threat = 'none';
sd = [2001 2001 2002]; bs = nan(1, 3);
for i = 1:3
    p.seed = sd(i);
    b = run_curve(p, modelName, struct('EbNo', 4, 'sim_time', 0.1), delay_bits);
    bs(i) = b;
end
seed_same = bs(1) == bs(2);
seed_diff = bs(1) ~= bs(3);

%% Report
g_ok = abs(GAP(1:5)) <= CFG.gap_ok;
jam_gain = 10*log10(BER(6,:) ./ BER(7,:));
rep = {};
rep{end+1} = '=== PHY VALIDATION (D41): multi-antenna UAV receiver vs theory ===';
rep{end+1} = sprintf('Generated: %s | %.1f s per point | fd %.0f Hz | CSI block %d sym (MRC), window %d sym (MMSE)', ...
    datestr(now), CFG.sim_time, p0.fd_max, p0.csi_block, p0.mmse_window);
rep{end+1} = sprintf('Eb/N0 per branch [dB]: %s', mat2str(CFG.EbNo));
rep{end+1} = '';
for c = 1:nC
    rep{end+1} = sprintf('%-26s BER  %s', cases{c,1}, sprintf('%9.2e', BER(c,:))); %#ok<SAGROW>
    rep{end+1} = sprintf('%-26s err  %s', '', sprintf('%9d', NERR(c,:))); %#ok<SAGROW>
    if cases{c,7} > 0
        rep{end+1} = sprintf('%-26s th.  %s', '', sprintf('%9.2e', TH(c,:))); %#ok<SAGROW>
    end
    if c <= 5
        rep{end+1} = sprintf('%-26s gap %+.2f dB -> %s  (bit delay found: %d)', '', GAP(c), ...
            passfail(abs(GAP(c)) <= CFG.gap_ok), DLY(c)); %#ok<SAGROW>
    end
end
rep{end+1} = '';
rep{end+1} = sprintf('V6 MMSE vs MRC under jamming (JSR 10 dB, interferer at %g deg): BER ratio [dB] %s', ...
    p0.int_aoa_deg(1), sprintf('%6.1f', jam_gain));
rep{end+1} = sprintf('V6 MMSE under jamming vs jammer-free MRC (V5): BER ratio %s', ...
    sprintf('%8.2f', BER(7,:) ./ BER(5,:)));
rep{end+1} = sprintf('V7 seeds: same seed identical %s, different seed differs %s (BER %s)', ...
    passfail(seed_same), passfail(seed_diff), mat2str(bs, 4));
rep{end+1} = sprintf('Overall: theory gaps V1-V5 %d/5 within %.1f dB, seeds %s | %.1f min', ...
    sum(g_ok), CFG.gap_ok, passfail(seed_same && seed_diff), toc(t0)/60);
if ~exist('results', 'dir'); mkdir('results'); end
fid = fopen('results/phy_validation.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});

%% Figure
f = figure('Position', [100 100 1150 450], 'Color', 'w');
subplot(1, 2, 1); hold on; grid on; box on;
col = lines(5);
for c = 1:5
    v = NERR(c,:) > 0;
    semilogy(CFG.EbNo(v), BER(c,v), 'o', 'Color', col(c,:), 'MarkerFaceColor', col(c,:), ...
        'DisplayName', [cases{c,1} ' (sim)']);
    if c <= 4
        semilogy(CFG.EbNo, TH(c,:), '-', 'Color', col(c,:), 'DisplayName', [cases{c,1}(1:2) ' theory']);
    end
end
set(gca, 'YScale', 'log'); ylim([1e-6 0.2]);
xlabel('E_b/N_0 per antenna [dB]'); ylabel('BER');
title('QPSK, coherent MRC vs theory'); legend('Location', 'southwest', 'FontSize', 7);
subplot(1, 2, 2); hold on; grid on; box on;
semilogy(CFG.EbNo, BER(6,:), 'rs-', 'DisplayName', 'jamming 10 dB, MRC');
semilogy(CFG.EbNo, BER(7,:), 'bo-', 'DisplayName', 'jamming 10 dB, MMSE (spatial action)');
semilogy(CFG.EbNo, BER(5,:), 'k--', 'DisplayName', 'no jammer, MRC');
set(gca, 'YScale', 'log'); ylim([1e-6 1]);
xlabel('E_b/N_0 per antenna [dB]'); ylabel('BER');
title(sprintf('Spatial nulling, %d antennas, jammer at %g deg', p0.n_rx, p0.int_aoa_deg(1)));
legend('Location', 'southwest', 'FontSize', 8);
exportgraphics(f, 'results/phy_validation.png', 'Resolution', 150);

params = S.params; save('params.mat', 'params');
end

%% ===================== Local functions =====================
function [ber, nerr, dly] = run_curve(p, modelName, CFG, delay_bits)
params = p; save('params.mat', 'params'); %#ok<NASGU>
evalc('build_threat_model');
nS = numel(CFG.EbNo); ber = nan(1, nS); nerr = zeros(1, nS); dly = NaN;
for s = 1:nS
    snr_dB = CFG.EbNo(s) + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
    set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), 'SignalPower', num2str(1/p.sps));
    out = sim(modelName, 'StopTime', num2str(CFG.sim_time));
    tx = double(squeeze(out.get('tx_bits_out'))); tx = tx(:);
    rx = double(squeeze(out.get('rx_bits_out'))); rx = rx(:);
    if s == 1
        b = inf(1, 61);
        for d = 0:60
            L = min(numel(tx), numel(rx) - d);
            b(d+1) = mean(tx(1:min(L, 20000)) ~= rx(d+1:d+min(L, 20000)));
        end
        [~, i] = min(b); dly = i - 1;
    end
    L = min(numel(tx), numel(rx) - delay_bits);
    e = tx(1:L) ~= rx(delay_bits+1:delay_bits+L);
    nerr(s) = sum(e); ber(s) = mean(e);
end
end

function pb = ber_theory(ebno_db, k_db, L)
% QPSK (Gray) = BPSK per bit; L-branch MRC, independent Rician branches, per-branch
% Eb/N0 (MGF form, Simon & Alouini). K = 60 dB gives the AWGN curve.
K = 10^(k_db/10);
pb = zeros(size(ebno_db));
for i = 1:numel(ebno_db)
    g = 10^(ebno_db(i)/10);
    if k_db >= 50
        pb(i) = berawgn(ebno_db(i), 'psk', 4, 'nondiff');
        continue;
    end
    M = @(t) ((1+K)*sin(t).^2 ./ ((1+K)*sin(t).^2 + g)) .* exp(-K*g ./ ((1+K)*sin(t).^2 + g));
    pb(i) = integral(@(t) M(t).^L, 0, pi/2) / pi;
end
end

function gap = ebno_gap(ebno, ber, nerr, th, min_err)
% Mean Eb/N0 shift [dB] at which theory reaches each measured BER (positive = worse).
v = find(nerr >= min_err & ber > 0);
if isempty(v), gap = NaN; return; end
lt = log10(th); d = zeros(1, numel(v));
for i = 1:numel(v)
    d(i) = interp1(fliplr(lt), fliplr(ebno), log10(ber(v(i))), 'linear', 'extrap');
    d(i) = ebno(v(i)) - d(i);
end
gap = mean(d);
end

function s = passfail(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end
