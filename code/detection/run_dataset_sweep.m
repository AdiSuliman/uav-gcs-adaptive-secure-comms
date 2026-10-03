%% RUN_DATASET_SWEEP - Phase A5: labeled dataset from independent seeded sub-runs
% 10 threats x 8 severity levels x 6 Eb/N0 points + 'none', on the multi-antenna
% link (build_threat_model.m). Every (threat, level, Eb/N0) cell is simulated as N_SUB independent
% sub-runs: own seed, 3,000,000 + run id (fading and its K-factors, interferer channels and directions,
% threat waveform, noise, bits) and own UAV speed drawn uniformly over the envelope (init_params.m). The sub-run is the unit of the
% train/val/test split (prepare_data.m), so no two splits share a channel
% realization or a temporal-feature window.
%
% Severity levels: dataset_levels.m (8 per threat, spanning the decision layer's levels and
% the survivability map, up to the sources' most severe values).
% 'none' gets n_levels x N_SUB sub-runs per Eb/N0 (class balance).
%
% Per frame: reference-antenna IQ, label, level, configured Eb/N0, the receiver
% measurements of extract_closed_loop_frames.m, the true BER and frame
% error (analysis only), speed, run id and seed, fold (1..N_SUB), the frame's position in its
% sub-run and the mean channel gain of every antenna (for measurements over several
% decision cycles), the share of the frame with the threat on the air, and the sub-run's
% draws (flight_draws.m, analysis only): K-factors of our signal and of the interferers,
% first interferer direction, heading rate, receive correlation, GCS pointing loss,
% altitude and the UAV antenna's gain toward the GCS. Frames whose BER is incomplete
% are dropped.

close all; clc;
warning('off', 'Simulink:cgxe:LeakedJITEngine');
if ~exist('params.mat', 'file')
    error('params.mat not found. Run init_params.m first.');
end
S = load('params.mat');
p0 = S.params; p0.quiet_build = true;

%% ---- Configuration ----
EbNo_list  = p0.EbNo_dB;          % Eb/N0 grid of init_params
N_SUB      = 6;                   % independent sub-runs per cell (split unit)
F_SUB      = 20;                  % frames per sub-run
delay_bits = 20;
modelName  = 'UAV_GCS_Threat_Link';
rng(2027, 'twister');             % speeds of every sub-run

clear threat_cfg
threat_cfg = dataset_levels();
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    for t = 1:numel(threat_cfg), threat_cfg(t).levels = threat_cfg(t).levels([1 end]); end
    EbNo_list = EbNo_list([2 5]);
end
n_levels    = numel(threat_cfg(1).levels);
class_names = ['none', {threat_cfg.name}];
stop_time   = num2str(F_SUB * p0.frame_duration);

MEAS = {'rssi', 'crc_fail', 'ber_est', 'snr_post', 'sinr', 'env_corr', 'iot', 'coh', 'mmse_gain', 'align', ...
        'branch_dip', 'branch_gap', 'sinr_gap', 'q_iot', 'q_react'};
D = struct('iq', {{}}, 'label', [], 'level', [], 'snr', [], 'ber', [], 'fer', [], 'speed', [], 'run', [], 'seed', [], 'fold', [], ...
    'pos', [], 'gain_ant', [], 'act', [], 'k_db', [], 'k_int', [], 'aoa', [], 'yaw', [], 'rho', [], 'gcs_db', [], ...
    'alt_m', [], 'el_db', []);
for i = 1:numel(MEAS), D.(MEAS{i}) = []; end
run_id = 0;
t0 = tic;
fprintf('\n=== A5 dataset: %d threats x %d levels x %d Eb/N0 x %d sub-runs x %d frames (+ none) ===\n', ...
    numel(threat_cfg), n_levels, numel(EbNo_list), N_SUB, F_SUB);
fprintf('%-22s %6s %10s %10s %9s %7s %7s\n', 'class', 'level', 'meanBER', 'meanSINR', 'envcorr', 'coh', 'Gmmse');

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
                    tt + 1, cfg.levels(lv), run_id, sub, MEAS);
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
        D = add_subrun(D, p, modelName, EbNo_list(s), stop_time, delay_bits, 1, NaN, run_id, mod(k-1, N_SUB) + 1, MEAS);
    end
end
report_row('none', NaN, D, i_start);
params = S.params; save('params.mat', 'params');

%% ---- Package ----
dataset = struct();
dataset.iq = D.iq; dataset.label = D.label(:); dataset.level = D.level(:);
dataset.class_names = class_names; dataset.snr = D.snr(:);
dataset.ber = D.ber(:); dataset.fer = D.fer(:);
dataset.meas = struct();
for i = 1:numel(MEAS), dataset.meas.(MEAS{i}) = D.(MEAS{i})(:); end
dataset.speed_kmh = D.speed(:); dataset.run = D.run(:); dataset.seed = D.seed(:); dataset.fold = D.fold(:);
dataset.pos = D.pos(:); dataset.gain_ant = D.gain_ant'; dataset.act = D.act(:);
dataset.k_db = D.k_db(:); dataset.k_int = D.k_int(:); dataset.aoa = D.aoa(:); dataset.yaw = D.yaw(:);
dataset.rho = D.rho(:); dataset.gcs_db = D.gcs_db(:); dataset.alt_m = D.alt_m(:); dataset.el_db = D.el_db(:);
dataset.meta = struct('N_SUB', N_SUB, 'F_SUB', F_SUB, 'EbNo_list', EbNo_list, 'delay_bits', delay_bits, ...
    'mode', 'seeded_subruns_D59', 'n_rx', p0.n_rx, 'speed_range_kmh', [p0.speed_kmh_min p0.speed_kmh_max], ...
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

function D = add_subrun(D, p, modelName, ebno, stop_time, delay_bits, label, level, run_id, fold, MEAS)
% One seeded sub-run at its own random UAV speed; appends its complete frames.
v_kmh = p.speed_kmh_min + rand() * (p.speed_kmh_max - p.speed_kmh_min);
fd = v_kmh / 3.6 * p.carrier_freq / p.c_light;
seed = 3000000 + run_id;                                % own seed range, fixed by the run id
d = link_seed(modelName, seed, fd, struct('ebno', ebno, 'alt_m', NaN, 'k_sig_db', NaN));
snr_dB = ebno + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), 'SignalPower', num2str(1/p.sps));
F = extract_closed_loop_frames(sim(modelName, 'StopTime', stop_time), p, delay_bits);
disk_guard;
v = find(~isnan(F.ber));
n = numel(v);
D.iq = [D.iq, F.iq(v)];
lab = label * ones(1, n);
if strcmp(p.active_threat, 'benign_interference')
    lab(F.act(v) < 0.1) = 1;                            % no WLAN packet in this frame: a clean frame
elseif strcmp(p.active_threat, 'antenna_fault')
    lab(F.act(v) == 0) = 1;                             % a fault model with the contact closed in a frame: a clean frame
end
D.label = [D.label, lab]; D.level = [D.level, level * ones(1, n)];
D.snr = [D.snr, ebno * ones(1, n)]; D.speed = [D.speed, v_kmh * ones(1, n)];
D.run = [D.run, run_id * ones(1, n)]; D.seed = [D.seed, seed * ones(1, n)]; D.fold = [D.fold, fold * ones(1, n)];
D.pos = [D.pos, v]; D.gain_ant = [D.gain_ant, F.gain_ant(:, v)]; D.act = [D.act, F.act(v)];
o = ones(1, n);
D.k_db = [D.k_db, d.k_sig * o]; D.k_int = [D.k_int, d.k_int * o]; D.aoa = [D.aoa, d.aoa(1) * o];
D.yaw = [D.yaw, d.yaw * o]; D.rho = [D.rho, d.rho * o]; D.gcs_db = [D.gcs_db, d.gcs_point_db * o];
D.alt_m = [D.alt_m, d.alt_m * o]; D.el_db = [D.el_db, d.el_db * o];
D.ber = [D.ber, F.ber(v)]; D.fer = [D.fer, F.fer(v)];
for i = 1:numel(MEAS), D.(MEAS{i}) = [D.(MEAS{i}), F.(MEAS{i})(v)]; end
end

function report_row(name, level, D, i0)
i = i0:numel(D.label);
fprintf('%-22s %6g %10.3e %10.1f %9.3f %7.2f %7.1f\n', name, level, mean(D.ber(i)), mean(D.sinr(i)), ...
    mean(D.env_corr(i), 'omitnan'), mean(D.coh(i)), mean(D.mmse_gain(i)));
end
