%% RUN_DATASET_SWEEP - Phase A5: labeled dataset from independent seeded sub-runs (D42)
% 8 threats x 5 severity levels x 6 Eb/N0 points + 'none', on the multi-antenna
% link of D41. Every (threat, level, Eb/N0) cell is simulated as N_SUB independent
% sub-runs: own seed (fading, interferer channels, threat waveform, noise, bits)
% and own UAV speed drawn uniformly in 50-120 km/h. The sub-run is the unit of the
% train/val/test split (prepare_data.m), so no two splits share a channel
% realization or a temporal-feature window.
%
% Severity levels (impact threshold to pre-saturation):
%   jamming / noise_burst / reactive / sweeping : JSR   0,4,8,12,16 dB
%   path_loss                                    : atten 4,8,12,16,20 dB
%   spoofing                                     : SIR   -4,-1,2,5,8 dB
%   antenna_fault                                : duty  0.1..0.5 (30 dB)
%   benign_interference                          : power -10..-2 dB
% 'none' gets n_levels x N_SUB sub-runs per Eb/N0 (class balance).
%
% Per frame: antenna-1 IQ, label, level, configured Eb/N0, BER, RSSI, PLR,
% SINR estimate, envelope correlation, speed, run id, fold (1..N_SUB).
% Frames whose BER is incomplete (last frame of a sub-run) are dropped.

close all; clc;
warning('off', 'Simulink:cgxe:LeakedJITEngine');
if ~exist('params.mat', 'file')
    error('params.mat not found. Run init_params.m first.');
end
S = load('params.mat');
p0 = S.params; p0.quiet_build = true;

%% ---- Configuration ----
EbNo_list  = p0.EbNo_dB;          % 0:2:10 dB
N_SUB      = 5;                   % independent sub-runs per cell (split unit)
F_SUB      = 20;                  % frames per sub-run
delay_bits = 20;
modelName  = 'UAV_GCS_Threat_Link';
rng(2026, 'twister');             % seeds and speeds of every sub-run

clear threat_cfg
threat_cfg(1) = struct('name','jamming',             'param','jsr_db',        'levels',[0 4 8 12 16]);
threat_cfg(2) = struct('name','noise_burst',         'param','jsr_db',        'levels',[0 4 8 12 16]);
threat_cfg(3) = struct('name','reactive_jamming',    'param','jsr_db',        'levels',[0 4 8 12 16]);
threat_cfg(4) = struct('name','path_loss',           'param','path_loss_db',  'levels',[4 8 12 16 20]);
threat_cfg(5) = struct('name','spoofing',            'param','spoof_sir_db',  'levels',[-4 -1 2 5 8]);
threat_cfg(6) = struct('name','antenna_fault',       'param','fault_duty',    'levels',[0.1 0.2 0.3 0.4 0.5]);
threat_cfg(7) = struct('name','benign_interference', 'param','benign_int_db', 'levels',[-10 -8 -6 -4 -2]);
threat_cfg(8) = struct('name','sweeping_jammer',     'param','jsr_db',        'levels',[0 4 8 12 16]);
n_levels    = 5;
class_names = ['none', {threat_cfg.name}];
stop_time   = num2str(F_SUB * p0.frame_duration);

D = struct('iq', {{}}, 'label', [], 'level', [], 'snr', [], 'ber', [], 'rssi', [], 'plr', [], ...
    'sinr', [], 'env_corr', [], 'iot', [], 'speed', [], 'run', [], 'fold', []);
run_id = 0;
t0 = tic;
fprintf('\n=== A5 dataset: %d threats x %d levels x %d Eb/N0 x %d sub-runs x %d frames (+ none) ===\n', ...
    numel(threat_cfg), n_levels, numel(EbNo_list), N_SUB, F_SUB);
fprintf('%-22s %6s %10s %10s %9s\n', 'class', 'level', 'meanBER', 'meanSINR', 'envcorr');

%% ---- Threat classes ----
for tt = 1:numel(threat_cfg)
    cfg = threat_cfg(tt);
    for lv = 1:n_levels
        p = p0; p.active_threat = cfg.name; p.(cfg.param) = cfg.levels(lv); p.seed = [];
        build(p, modelName);
        i_start = numel(D.label) + 1;
        for s = 1:numel(EbNo_list)
            for sub = 1:N_SUB
                run_id = run_id + 1;
                D = add_subrun(D, p, modelName, EbNo_list(s), stop_time, delay_bits, ...
                    tt + 1, cfg.levels(lv), run_id, sub);
            end
        end
        report_row(cfg.name, cfg.levels(lv), D, i_start);
    end
end

%% ---- None class (n_levels x N_SUB sub-runs per Eb/N0) ----
p = p0; p.active_threat = 'none'; p.seed = [];
build(p, modelName);
i_start = numel(D.label) + 1;
for s = 1:numel(EbNo_list)
    for k = 1:n_levels * N_SUB
        run_id = run_id + 1;
        D = add_subrun(D, p, modelName, EbNo_list(s), stop_time, delay_bits, 1, NaN, run_id, mod(k-1, N_SUB) + 1);
    end
end
report_row('none', NaN, D, i_start);
params = S.params; save('params.mat', 'params');

%% ---- Package ----
dataset = struct();
dataset.iq = D.iq; dataset.label = D.label(:); dataset.level = D.level(:);
dataset.class_names = class_names; dataset.snr = D.snr(:);
dataset.ber = D.ber(:); dataset.rssi = D.rssi(:); dataset.plr = D.plr(:);
dataset.sinr = D.sinr(:); dataset.env_corr = D.env_corr(:); dataset.iot = D.iot(:);
dataset.speed_kmh = D.speed(:); dataset.run = D.run(:); dataset.fold = D.fold(:);
dataset.meta = struct('N_SUB', N_SUB, 'F_SUB', F_SUB, 'EbNo_list', EbNo_list, 'delay_bits', delay_bits, ...
    'mode', 'seeded_subruns_D42', 'n_rx', p0.n_rx, 'speed_range_kmh', [p0.speed_kmh_min p0.speed_kmh_max], ...
    'threat_cfg', threat_cfg, 'created', datestr(now));
if ~exist('data', 'dir'); mkdir('data'); end
save('data/dataset.mat', 'dataset', '-v7.3');

fprintf('\n=== Dataset summary ===\n');
fprintf('Frames: %d | sub-runs: %d | speed %.1f-%.1f km/h | %.1f min\n', numel(D.label), run_id, ...
    min(D.speed), max(D.speed), toc(t0)/60);
for c = 1:numel(class_names)
    fprintf('  %-22s %d\n', class_names{c}, sum(D.label == c));
end
fprintf('Saved data/dataset.mat. Next: extract_spectrograms.\n');
clear D dataset   % large arrays; main.m runs the stages in one workspace

%% ===================== Local functions =====================
function build(p, modelName)
params = p; save('params.mat', 'params'); %#ok<NASGU>
evalc('build_threat_model');
end

function D = add_subrun(D, p, modelName, ebno, stop_time, delay_bits, label, level, run_id, fold)
% One seeded sub-run at its own random UAV speed; appends its complete frames.
v_kmh = p.speed_kmh_min + rand() * (p.speed_kmh_max - p.speed_kmh_min);
fd = v_kmh / 3.6 * p.carrier_freq / p.c_light;
link_seed(modelName, randi(2^31 - 1000), fd);
snr_dB = ebno + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), 'SignalPower', num2str(1/p.sps));
out = sim(modelName, 'StopTime', stop_time);
[iqf, ber, rssi, plr, nf, sinr, ec, io] = extract_closed_loop_frames(out, p, delay_bits);
for f = 1:nf
    if isnan(ber(f)), continue; end
    D.iq{end+1} = iqf{f};
    D.label(end+1) = label; D.level(end+1) = level; D.snr(end+1) = ebno;
    D.ber(end+1) = ber(f); D.rssi(end+1) = rssi(f); D.plr(end+1) = plr(f);
    D.sinr(end+1) = sinr(f); D.env_corr(end+1) = ec(f); D.iot(end+1) = io(f);
    D.speed(end+1) = v_kmh; D.run(end+1) = run_id; D.fold(end+1) = fold;
end
end

function report_row(name, level, D, i0)
i = i0:numel(D.label);
fprintf('%-22s %6g %10.3e %10.1f %9.3f\n', name, level, mean(D.ber(i)), mean(D.sinr(i)), mean(D.env_corr(i)));
end
