%% THREAT_GALLERY - One figure per threat for the report, from the simulated link
% Every threat at its nominal severity (init_params.m) on one seeded flight
% (Eb/N0 6 dB, 90 km/h, interferers at fixed directions 45, -55, 70 deg), next to
% the clean link on the same seed:
%   (a) spectrogram of a received frame on the reference antenna: what the detector sees
%   (b) combiner output symbols of that frame: clean link vs threat
%   (c) BER per frame: clean link, the threat with no response, and the threat
%       under the configuration the selected DQN ends with most often on the test
%       pools (top_cfg of results/policy_evaluation.mat; the expert rule's choice
%       when that file does not exist yet)
% plus an overview figure with the spectrogram of every threat.
%
% Output: results/threat_gallery/<threat>.png, results/threat_gallery/overview.png

close all; clc;
fprintf('=== Threat gallery ===\n');
THREATS = {'jamming', 'reactive_jamming', 'sweeping_jammer', 'noise_burst', 'tone_jamming', 'spoofing', ...
    'benign_interference', 'path_loss', 'antenna_fault', 'airframe_shadowing'};
EBNO = 9; V_KMH = 90; SEED = 424242; NF = 40; SHOW = 20;   % frames simulated, frame shown
OUT = fullfile('results', 'threat_gallery');
if ~isfolder(OUT), mkdir(OUT); end

p0 = load('params.mat').params;
p0.quiet_build = true; p0.int_aoa_random = false; p0.k_random = false; p0.yaw_random = false; p0.corr_random = false; p0.gcs_tracked = false;
p0.gcs_aoa_random = false;
p0.jam_timing_random = false;           % the shortest sweep at phase 0: the sweeper on our channel in every frame
p0.tdl_random = false;                  % the median delay spreads (p0.tdl_ds_ns), with the delay line on
fs =p0.symbol_rate * p0.sps;
fd = V_KMH / 3.6 * p0.carrier_freq / p0.c_light;
top = struct('threat', {}, 'action', {}, 'share', {});
if isfile('results/policy_evaluation.mat') && any(strcmp({whos('-file', 'results/policy_evaluation.mat').name}, 'top_cfg'))
    top = load('results/policy_evaluation.mat', 'top_cfg').top_cfg;
end

clean = run_link(p0, 'none', 'no_action', EBNO, SEED, fd, NF);
ov = figure('Position', [40 40 1500 700], 'Color', 'w', 'Visible', 'off');
tlo = tiledlayout(ov, 2, 5, 'TileSpacing', 'compact', 'Padding', 'compact');
for t = 1:numel(THREATS)
    th = THREATS{t};
    k = find(strcmp({top.threat}, th), 1);
    if isempty(k), act = rule_based_policy(th); src = 'expert rule';
    else, act = top(k).action; src = sprintf('DQN, %.0f%% of test episodes', 100 * top(k).share); end
    base = run_link(p0, th, 'no_action', EBNO, SEED, fd, NF);
    resp = run_link(p0, th, act, EBNO, SEED, fd, NF);
    fprintf('  %-20s BER clean %.2e | no response %.2e | %s %.2e\n', th, mean(clean.ber, 'omitnan'), ...
        mean(base.ber, 'omitnan'), act, mean(resp.ber, 'omitnan'));

    fig = figure('Position', [60 60 1500 420], 'Color', 'w', 'Visible', 'off');
    tl = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(tl); spec_axes(ax, base.iq{SHOW}, fs, '(a) Received spectrum, reference antenna');
    ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on'); axis(ax, 'equal');
    zc = clean.z(:, SHOW); zt = base.z(:, SHOW);
    s = max(rms(zc), eps);
    plot(ax, real(zt) / s, imag(zt) / s, '.', 'Color', [0.85 0.33 0.10], 'MarkerSize', 5);
    plot(ax, real(zc) / s, imag(zc) / s, '.', 'Color', [0 0.45 0.74], 'MarkerSize', 5);
    lim = 2.5; xlim(ax, [-lim lim]); ylim(ax, [-lim lim]);
    xlabel(ax, 'In-phase'); ylabel(ax, 'Quadrature'); legend(ax, {'under threat', 'clean link'}, 'Location', 'southoutside', ...
        'Orientation', 'horizontal');
    title(ax, '(b) Symbols after combining');
    ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on');
    fl = 0.5 / p0.frame_length;
    semilogy(ax, max(clean.ber, fl), '-', 'Color', [0 0.45 0.74], 'LineWidth', 1.4);
    semilogy(ax, max(base.ber, fl), '-', 'Color', [0.85 0.33 0.10], 'LineWidth', 1.4);
    semilogy(ax, max(resp.ber, fl), '-', 'Color', [0.47 0.67 0.19], 'LineWidth', 1.8);
    yline(ax, max(2 * mean(clean.ber, 'omitnan'), fl), '--k', '2x clean');
    set(ax, 'YScale', 'log'); ylim(ax, [fl * 0.8 1]); xlim(ax, [1 NF]);
    xlabel(ax, sprintf('Decision cycle (one %.2f ms frame every %g ms)', 1000 * p0.air_symbols / p0.symbol_rate, 1000 * p0.cycle_s)); ylabel(ax, 'BER');
    legend(ax, {'clean link', 'no response', strrep(strrep(act, '_', ' '), '+', ' + ')}, 'Location', 'southoutside', ...
        'NumColumns', 2);                                        % long configurations wrap instead of being cut
    title(ax, sprintf('(c) Response: %s', src));
    title(tl, sprintf('%s, nominal severity, E_b/N_0 %d dB, %d km/h', strrep(th, '_', ' '), EBNO, V_KMH));
    exportgraphics(fig, fullfile(OUT, [th '.png']), 'Resolution', 200); close(fig);

    ax = nexttile(tlo); spec_axes(ax, base.iq{SHOW}, fs, strrep(th, '_', ' '));
end
title(tlo, sprintf('Received spectrum of one frame per threat (E_b/N_0 %d dB, nominal severity)', EBNO));
exportgraphics(ov, fullfile(OUT, 'overview.png'), 'Resolution', 200); close(ov);
fprintf('Saved %s\n', OUT);

%% ===================== Local functions =====================
function R = run_link(p0, threat, action, ebno, seed, fd, nf)
% One seeded run of the threat link with a configuration applied (apply_countermeasure.m).
p = p0; p.active_threat = threat;
[p2, g_db] = apply_countermeasure(p, threat, action);
evalc('build_threat_model(p2)');
mdl = 'UAV_GCS_Threat_Link';
set_param([mdl '/AWGN'], 'SNR', num2str(ebno + g_db + 10*log10(p2.bits_per_symbol) - 10*log10(p2.sps)), ...
    'SignalPower', num2str(1/p2.sps));
link_seed(mdl, seed, fd);
out = sim(mdl, 'StopTime', num2str(nf * p2.frame_duration));
F = extract_closed_loop_frames(out, p2, 20);
disk_guard;
z = squeeze(out.get('Rx_Z')); if isvector(z), z = z(:); end
R = struct('iq', {F.iq}, 'ber', F.ber, 'z', z);
end

function spec_axes(ax, iq, fs, ttl)
% Spectrogram of one frame in dB, time in microseconds, frequency in MHz.
[S, f, t] = spectrogram(iq, hann(128), 113, 128, fs, 'centered');
imagesc(ax, 1e6 * t, f / 1e6, 20*log10(abs(S) + eps)); axis(ax, 'xy');
colormap(ax, turbo); clim(ax, [-40 40]); c = colorbar(ax); c.Label.String = 'dB';
xlabel(ax, 'Time [\mus]'); ylabel(ax, 'Frequency [MHz]'); title(ax, ttl);
end

