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
% 'none' gets n_levels x N_SUB sub-runs per Eb/N0 (class balance). The sweeping jammer is
% on our channel in a share of the frames only (its sweep period and phase per flight,
% jam_timing.m): its cells fly N_SUB over the share of the frames the frame rule labels
% (sweep_hit_share.m without idle sensing), the labels of the per-frame network, so its
% labelled frames match the other threats'; its other frames are clean frames. Likewise the
% WLAN with a packet in the frame (benign_hit_share.m). With idle sensing (p.idle_rssi_hz) a
% decision cycle is the idle time before the frame and the frame, and the per-cycle labels
% count the gated threats while they are on the air anywhere in it (threat_active.m,
% act_idle): a larger share, so the cells fly the larger of the two needs, N_SUB over the
% smaller share. A path-loss step starts inside the sub-run (p.pl_onset_det) and its frames
% count while their link-feature window of TW frames still holds a frame before the onset
% (threat_active.m): TW - 1 of F_SUB frames, so its cells fly N_SUB F_SUB / (TW - 1). The
% sub-runs of a threat beyond N_SUB per cell go round the folds from cell to cell, so every
% fold holds the same share of them; each level starts one fold further, so they fall on
% every Eb/N0 point in turn. An antenna fault and airframe shadowing start inside
% the sub-run too, at a frame drawn per sub-run in the same range (frames before it carry
% no threat): the connector opens within one frame (p.fault_onset_frames), and the UAV rolls
% into its turn so that the hidden antenna's loss first reaches p.shadow_evt_db at that
% frame (p.roll_in_frames, flight_draws.m: the loss ramps in as the burial grows,
% shadow_frame.m); both count from there on, so their cells fly N_SUB F_SUB over the mean
% count of frames from the onset. Every other turning flight, of the clean link and of every
% threat, rolls in too (p0.roll_in_frames), its start uniform over the times that put some of
% the roll-in inside the sub-run, its labels its class's. Airframe shadowing counts only while
% the attitude lets the airframe hide an antenna in an event whose deepest burial, through its
% equivalent roll, lies in the level's band (shadow_frame.m, shadow_equiv_roll.m,
% shadow_roll_band.m): its cells fly flights that hide one in some frame, found from the
% flights' draws before they are simulated (hides_antenna.m: flight_draws.m, d.hidden; the
% roll-in has to bring the airframe into the line of sight); a flight that hides none
% would be the clean link. The share of such flights per level (shadow_hit_share.m) is
% printed with the flights tried.
%
% Per frame: reference-antenna IQ, label (per decision cycle), label_frame (the frame rule:
% threat_active.m without the idle time, what the frame itself holds; the labels of the
% per-frame network, frame_labels.m), class_run (the class of its sub-run), level, configured
% Eb/N0, the received Eb/N0
% (ebno_rx: the configured value less a path-loss step from its onset, received_ebno.m),
% the receiver measurements of extract_closed_loop_frames.m, the true BER and frame
% error (analysis only), speed, run id and seed, fold (1..N_SUB), the frame's position in its
% sub-run and the mean channel gain of every antenna (for measurements over several
% decision cycles), the share of the frame with the threat on the air (act; act_comp per
% component; lev_db the level an interferer reaches over our signal on the weakest antenna),
% and the sub-run's draws (flight_draws.m, analysis only): K-factors of our signal and of the
% interferers, first interferer direction and its alignment with the GCS (align_gcs), GCS direction,
% heading rate, bank, roll, pitch and pitch-wobble amplitude, receive correlation, GCS
% pointing loss, altitude, the UAV antenna's gain toward the GCS in level flight and at the
% attitude, the spread of the airframe loss over the antennas, the timing of the gated
% jammers (sweep period and phase, burst start and duty), the RMS delay spreads of our
% signal and of the first interferer (0 on a flat channel), every antenna's level
% calibration error (cal_db) and the roll-in (roll_in: its start [s] and roll rate
% [deg/s], 0 0 without one). Frames whose BER is incomplete are dropped.
% Branch record (extract_closed_loop_frames.m): bch, every antenna's channel estimates per
% frame (frames x 9 n_rx, branch_record.m), a receiver input of the fusion (window_cues.m).
% Idle time (extract_closed_loop_frames.m): idle, the record of the idle time before each
% frame (frames x 24, idle_summary.m), a receiver input of the fusion; act_idle, the share of
% that idle time with the threat on the air (labels); idle_amb (frames x 15), for antenna
% fault and airframe shadowing only, the per-antenna idle levels with an emitter of
% opportunity per condition (emitter_idle.m: the reading per condition of
% emitter_reading.m, never the default link), NaN elsewhere.
%
% With FRESH_TEST true in the calling workspace (build_fresh_test.m) the same recipe gives a
% second, independent test set: 4 sub-runs per cell (the compensated counts of the gated
% threats, path loss and the lost branches scaled alike), every one in the test fold (6), seeds
% 3,500,000 + run id and their own speed stream, saved as data/dataset_fresh.mat. With
% FRESH_SET = 2 as well (stage B3m) the same recipe gives a third test set: seeds 6,500,000 +
% run id (above every dataset, B4 and B4s seed, below the pools' shadowing candidates,
% test_seed_streams_disjoint) and a speed stream of its own, saved as data/dataset_fresh2.mat.
% With FRESH_SET = 3 (stage B3q) the same recipe gives a fourth test set: seeds 6,000,000 + run
% id (between the second B4s reading's and the third test set's) and a speed stream of its
% own, saved as data/dataset_fresh3.mat.

close all; clc;
warning('off', 'Simulink:cgxe:LeakedJITEngine');
if ~exist('params.mat', 'file')
    error('params.mat not found. Run init_params.m first.');
end
S = load('params.mat');
p0 = S.params; p0.quiet_build = true;

%% ---- Configuration ----
FRESH      = exist('FRESH_TEST', 'var') && FRESH_TEST;
SET2       = FRESH && exist('FRESH_SET', 'var') && isequal(FRESH_SET, 2);   % the third test set (B3m)
SET3       = FRESH && exist('FRESH_SET', 'var') && isequal(FRESH_SET, 3);   % the fourth test set (B3q)
EbNo_list  = p0.EbNo_dB;          % Eb/N0 grid of init_params
N_SUB      = 6;                   % independent sub-runs per cell (split unit)
F_SUB      = 20;                  % frames per sub-run
TW         = 10;                  % link-feature window [frames], as extract_spectrograms.m
delay_bits = 20;
modelName  = 'UAV_GCS_Threat_Link';
SEED0      = 3000000;             % sub-run seed: SEED0 + run id
FOLD       = @(k) mod(k - 1, N_SUB) + 1;   % fold of the k-th sub-run of a threat, counted over its cells
f_out      = 'data/dataset.mat';
rng(2027, 'twister');             % speeds of every sub-run
if FRESH
    N_SUB = 4; SEED0 = 3500000; FOLD = @(k) 6; f_out = 'data/dataset_fresh.mat';
    rng(2029, 'twister');
end
if SET2
    SEED0 = 6500000; f_out = 'data/dataset_fresh2.mat';
    rng(2035, 'twister');
end
if SET3
    SEED0 = 6000000; f_out = 'data/dataset_fresh3.mat';
    rng(2037, 'twister');
end

clear threat_cfg
threat_cfg = dataset_levels();
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    for t = 1:numel(threat_cfg), threat_cfg(t).levels = threat_cfg(t).levels([1 end]); end
    EbNo_list = EbNo_list([2 5]);
end
n_levels    = numel(threat_cfg(1).levels);
n_sub       = N_SUB * ones(1, numel(threat_cfg));
q           = p0; q.idle_rssi_hz = 0;                   % the frame rule
hit         = sweep_hit_share(p0); hit_f = sweep_hit_share(q);
n_sub(strcmp({threat_cfg.name}, 'sweeping_jammer')) = max(round(N_SUB / hit_f), round(N_SUB / hit));
wlan        = benign_hit_share(p0, [], F_SUB); wlan_f = benign_hit_share(q, [], F_SUB);
n_sub(strcmp({threat_cfg.name}, 'benign_interference')) = max(round(N_SUB / wlan_f), round(N_SUB / wlan));
n_sub(strcmp({threat_cfg.name}, 'path_loss')) = round(N_SUB * F_SUB / (TW - 1));
on_frames   = F_SUB + 1 - mean(p0.pl_onset_det(1):p0.pl_onset_det(end));   % mean frames from an onset inside the sub-run
n_sub(ismember({threat_cfg.name}, {'antenna_fault', 'airframe_shadowing'})) = round(N_SUB * F_SUB / on_frames);
if exist('SMOKE', 'var') && SMOKE, n_sub(:) = N_SUB; end
class_names = ['none', {threat_cfg.name}];
stop_time   = num2str(F_SUB * p0.frame_duration);
p0.cap_frames = F_SUB;                                  % the cap holds over the sub-run
p0.roll_in_frames = p0.pl_onset_det;                    % every turning flight of every class rolls in inside the sub-run

MEAS = {'rssi', 'crc_fail', 'ber_est', 'snr_post', 'sinr', 'env_corr', 'iot', 'coh', 'mmse_gain', 'align', ...
        'branch_dip', 'branch_gap', 'sinr_gap', 'q_iot', 'q_react', 'q_sfm', 'q_par', 'duty', 'edges', 'est_margin'};
D = struct('iq', {{}}, 'label', [], 'label_frame', [], 'class_run', [], 'level', [], 'snr', [], 'ebno_rx', [], 'ber', [], 'fer', [], ...
    'speed', [], 'run', [], 'seed', [], 'fold', [], ...
    'pos', [], 'gain_ant', [], 'act', [], 'act_comp', [], 'lev_db', [], 'k_db', [], 'k_int', [], 'aoa', [], 'yaw', [], ...
    'rho', [], 'gcs_db', [], 'alt_m', [], 'el_db', [], 'align_gcs', [], 'gcs_aoa', [], 'bank', [], 'roll', [], 'pitch', [], ...
    'wob', [], 'att_db', [], 'body_spread_db', [], 'jam', [], 'ds_ns', [], 'ds_int', [], 'cal_db', [], 'roll_in', [], ...
    'idle', [], 'act_idle', [], 'idle_amb', [], 'bch', []);
dup = intersect(MEAS, fieldnames(D));                   % a measurement and a draw in one field would mix them
assert(isempty(dup), 'run_dataset_sweep: %s is both a measurement and a field of its own', strjoin(dup, ', '));
for i = 1:numel(MEAS), D.(MEAS{i}) = []; end
run_id = 0;
t0 = tic;
fprintf('\n=== A5 dataset: %d threats x %d levels x %d Eb/N0 x %d sub-runs x %d frames (+ none) ===\n', ...
    numel(threat_cfg), n_levels, numel(EbNo_list), N_SUB, F_SUB);
fprintf('sweeping jammer: on our channel in %.1f%% of the frames (frame rule), %.1f%% of the decision cycles, %d sub-runs per cell\n', ...
    100 * hit_f, 100 * hit, n_sub(strcmp({threat_cfg.name}, 'sweeping_jammer')));
fprintf('WLAN: a packet on the air in %.1f%% of the frames (frame rule), %.1f%% of the decision cycles, %d sub-runs per cell\n', ...
    100 * wlan_f, 100 * wlan, n_sub(strcmp({threat_cfg.name}, 'benign_interference')));
fprintf('path loss: a step at frame %d-%d, %d sub-runs per cell\n', p0.pl_onset_det, n_sub(strcmp({threat_cfg.name}, 'path_loss')));
fprintf(['antenna fault: the connector opens at frame %d-%d; airframe shadowing: a roll-in brings the loss to %g dB ' ...
    'there; %d and %d sub-runs per cell\n'], p0.pl_onset_det, p0.shadow_evt_db, n_sub(strcmp({threat_cfg.name}, 'antenna_fault')), ...
    n_sub(strcmp({threat_cfg.name}, 'airframe_shadowing')));
fprintf('%-22s %6s %10s %10s %9s %7s %7s\n', 'class', 'level', 'meanBER', 'meanSINR', 'envcorr', 'coh', 'Gmmse');

%% ---- Threat classes ----
for tt = 1:numel(threat_cfg)
    cfg = threat_cfg(tt);
    shd = strcmp(cfg.name, 'airframe_shadowing');
    nk = 0;                                             % sub-runs of the threat so far: their folds go round
    for lv = 1:n_levels
        p = p0; p.active_threat = cfg.name; p.(cfg.param) = cfg.levels(lv); p.seed = [];
        p.pl_onset_frames = p0.pl_onset_det;           % a path-loss step inside the sub-run
        p.fault_onset_frames = p0.pl_onset_det;        % the connector opens inside it
        build(p);
        i_start = numel(D.label) + 1; tried = 0;
        for s = 1:numel(EbNo_list)
            for sub = 1:n_sub(tt)
                run_id = run_id + 1; tried = tried + 1;
                v_kmh = p.speed_kmh_min + rand() * (p.speed_kmh_max - p.speed_kmh_min);
                while shd && ~hides_antenna(SEED0 + run_id, v_kmh, p, ...   % a flight that hides an antenna
                        struct('ebno', EbNo_list(s), 'alt_m', NaN, 'k_sig_db', NaN))
                    run_id = run_id + 1; tried = tried + 1;
                    v_kmh = p.speed_kmh_min + rand() * (p.speed_kmh_max - p.speed_kmh_min);
                end
                nk = nk + 1;
                D = add_subrun(D, p, modelName, EbNo_list(s), v_kmh, stop_time, delay_bits, ...
                    tt + 1, cfg.levels(lv), run_id, FOLD(nk + lv - 1), MEAS, SEED0, TW);
            end
        end
        report_row(cfg.name, cfg.levels(lv), D, i_start);
        if shd
            fprintf('    rolls %.1f-%.1f deg: %d of %d flights tried hide an antenna (%.1f%%)\n', ...
                shadow_roll_band(cfg.levels(lv), p), n_sub(tt) * numel(EbNo_list), tried, ...
                100 * n_sub(tt) * numel(EbNo_list) / tried);
        end
    end
end

%% ---- None class (n_levels x N_SUB sub-runs per Eb/N0) ----
p = p0; p.active_threat = 'none'; p.seed = [];
build(p);
i_start = numel(D.label) + 1;
for s = 1:numel(EbNo_list)
    for k = 1:n_levels * N_SUB
        run_id = run_id + 1;
        v_kmh = p.speed_kmh_min + rand() * (p.speed_kmh_max - p.speed_kmh_min);
        D = add_subrun(D, p, modelName, EbNo_list(s), v_kmh, stop_time, delay_bits, 1, NaN, run_id, FOLD(k), MEAS, SEED0, TW);
    end
end
report_row('none', NaN, D, i_start);

%% ---- Package ----
dataset = struct();
dataset.iq = D.iq; dataset.label = D.label(:); dataset.label_frame = D.label_frame(:); dataset.level = D.level(:);
dataset.class_run = D.class_run(:);        % the class of the frame's sub-run (1 = none)
dataset.class_names = class_names; dataset.snr = D.snr(:); dataset.ebno_rx = D.ebno_rx(:);
dataset.ber = D.ber(:); dataset.fer = D.fer(:);
dataset.meas = struct();
for i = 1:numel(MEAS), dataset.meas.(MEAS{i}) = D.(MEAS{i})(:); end
dataset.speed_kmh = D.speed(:); dataset.run = D.run(:); dataset.seed = D.seed(:); dataset.fold = D.fold(:);
dataset.pos = D.pos(:); dataset.gain_ant = D.gain_ant'; dataset.act = D.act(:);
dataset.act_comp = D.act_comp'; dataset.lev_db = D.lev_db';   % per component (frames x 3)
dataset.k_db = D.k_db(:); dataset.k_int = D.k_int(:); dataset.aoa = D.aoa(:); dataset.yaw = D.yaw(:);
dataset.rho = D.rho(:); dataset.gcs_db = D.gcs_db(:); dataset.alt_m = D.alt_m(:); dataset.el_db = D.el_db(:);
dataset.align_gcs = D.align_gcs(:); dataset.gcs_aoa = D.gcs_aoa(:); dataset.bank = D.bank(:); dataset.roll = D.roll(:);
dataset.pitch = D.pitch(:); dataset.wob = D.wob(:); dataset.att_db = D.att_db(:); dataset.body_spread_db = D.body_spread_db(:);
dataset.jam = D.jam';                      % sweep period [s], sweep phase [s], burst start, burst duty per frame
dataset.ds_ns = D.ds_ns(:); dataset.ds_int = D.ds_int(:);
dataset.cal_db = D.cal_db';                % level calibration error of every antenna [dB] (frames x antennas)
dataset.roll_in = D.roll_in';              % roll-in start [s] and roll rate [deg/s] per frame (0 0 without one)
dataset.idle = D.idle'; dataset.act_idle = D.act_idle(:);   % the idle time before each frame (frames x 24) and its on-air share
dataset.idle_amb = D.idle_amb';            % with an emitter of opportunity, per condition (frames x 15; fault and shadowing)
dataset.idle_names = idle_summary('names');
dataset.bch = D.bch'; dataset.bch_names = branch_record('names', p0.n_rx);   % every antenna's channel estimates per frame (frames x 9 n_rx, window_cues.m)
dataset.meta = struct('N_SUB', N_SUB, 'n_sub', n_sub, 'F_SUB', F_SUB, 'EbNo_list', EbNo_list, 'delay_bits', delay_bits, ...
    'mode', 'seeded_subruns_D59', 'n_rx', p0.n_rx, 'speed_range_kmh', [p0.speed_kmh_min p0.speed_kmh_max], ...
    'threat_cfg', threat_cfg, 'fresh', FRESH, 'seed0', SEED0, 'created', datestr(now), ...
    'sweep_hit', hit, 'wlan_hit', wlan, 'sweep_hit_frame', hit_f, 'wlan_hit_frame', wlan_f);
assert_frames(D, numel(D.label), 'run_dataset_sweep', {}, 2);   % every field one entry per frame
assert_frames(dataset.meas, numel(dataset.run), 'run_dataset_sweep: the receiver measurements');
if ~isfolder('data'), mkdir('data'); end         % a folder of that name elsewhere on the path does not count
save(f_out, 'dataset', '-v7.3');

fprintf('\n=== Dataset summary ===\n');
fprintf('Frames: %d | sub-runs: %d | speed %.1f-%.1f km/h | %.1f min\n', numel(D.label), numel(unique(D.run)), ...
    min(D.speed), max(D.speed), toc(t0)/60);
fprintf('Labelled frames per class (and frames of the class''s own sub-runs; by the frame rule):\n');
for c = 1:numel(class_names)
    fprintf('  %-22s %d (%d; %d)\n', class_names{c}, sum(D.label == c), sum(D.class_run == c), sum(D.label_frame == c));
end
fprintf('Saved %s. Next: extract_spectrograms.\n', f_out);
clear D dataset   % large arrays; main.m runs the stages in one workspace

%% ===================== Local functions =====================
function build(p) %#ok<INUSD>
% The level's model, built in memory from p; params.mat is not written.
evalc('build_threat_model(p)');
end

function D = add_subrun(D, p, modelName, ebno, v_kmh, stop_time, delay_bits, label, level, run_id, fold, MEAS, seed0, tw)
% One seeded sub-run at its UAV speed v_kmh; appends its complete frames.
fd = v_kmh / 3.6 * p.carrier_freq / p.c_light;
seed = seed0 + run_id;                                  % own seed range, fixed by the run id
d = link_seed(modelName, seed, fd, struct('ebno', ebno, 'alt_m', NaN, 'k_sig_db', NaN));
snr_dB = ebno + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
set_link_snr(modelName, snr_dB, p);
F = extract_closed_loop_frames(sim(modelName, 'StopTime', stop_time), p, delay_bits);
disk_guard;
v = find(~isnan(F.ber));
n = numel(v);
D.iq = [D.iq, F.iq(v)];
lab = label * ones(1, n);
lab(~threat_active(p.active_threat, F.act(v), v, tw, F.act_idle(v))) = 1;   % a cycle without a WLAN packet or the
                                                        % sweep on the air (frame or idle time), no antenna hidden by
                                                        % the event's loss, a fault frame before the connector opens, a
                                                        % path-loss frame before its step or past its onset's window: clean
labf = label * ones(1, n);
labf(~threat_active(p.active_threat, F.act(v), v, tw)) = 1;   % the frame rule: what the frame itself holds
D.label_frame = [D.label_frame, labf];
D.label = [D.label, lab]; D.class_run = [D.class_run, label * ones(1, n)]; D.level = [D.level, level * ones(1, n)];
D.snr = [D.snr, ebno * ones(1, n)]; D.speed = [D.speed, v_kmh * ones(1, n)];
D.ebno_rx = [D.ebno_rx, received_ebno(p.active_threat, ebno, F.act_comp(:, v), p.path_loss_db)];
D.run = [D.run, run_id * ones(1, n)]; D.seed = [D.seed, seed * ones(1, n)]; D.fold = [D.fold, fold * ones(1, n)];
D.pos = [D.pos, v]; D.gain_ant = [D.gain_ant, F.gain_ant(:, v)]; D.act = [D.act, F.act(v)];
D.act_comp = [D.act_comp, F.act_comp(:, v)]; D.lev_db = [D.lev_db, F.lev_db(:, v)];
o = ones(1, n);
D.k_db = [D.k_db, d.k_sig * o]; D.k_int = [D.k_int, d.k_int * o]; D.aoa = [D.aoa, d.aoa(1) * o];
D.yaw = [D.yaw, d.yaw * o]; D.rho = [D.rho, d.rho * o]; D.gcs_db = [D.gcs_db, d.gcs_point_db * o];
D.alt_m = [D.alt_m, d.alt_m * o]; D.el_db = [D.el_db, d.el_db * o];
D.align_gcs = [D.align_gcs, d.align(1) * o]; D.gcs_aoa = [D.gcs_aoa, d.gcs_aoa * o]; D.bank = [D.bank, d.bank * o];
D.roll = [D.roll, d.roll * o]; D.pitch = [D.pitch, d.pitch * o]; D.wob = [D.wob, d.wobble(1) * o];
D.att_db = [D.att_db, d.att_db * o]; D.body_spread_db = [D.body_spread_db, (max(d.body_db) - min(d.body_db)) * o];
D.jam = [D.jam, d.jam(:) * o];
D.ds_ns = [D.ds_ns, d.ds_ns(1) * o]; D.ds_int = [D.ds_int, d.ds_ns(min(2, end)) * o];
D.cal_db = [D.cal_db, d.cal_db(:) * o];
D.roll_in = [D.roll_in, d.roll_in(:) * o];
D.ber = [D.ber, F.ber(v)]; D.fer = [D.fer, F.fer(v)];
for i = 1:numel(MEAS), D.(MEAS{i}) = [D.(MEAS{i}), F.(MEAS{i})(v)]; end
D.idle = [D.idle, single(F.idle(:, v))]; D.act_idle = [D.act_idle, F.act_idle(v)];
D.bch = [D.bch, single(F.bch(:, v))];
amb = nan(n, 5 * numel(p.amb_inr_db));                 % an emitter of opportunity: fault and shadowing only
if any(strcmp(p.active_threat, {'antenna_fault', 'airframe_shadowing'})), amb = emitter_idle(F, p, seed, v); end
D.idle_amb = [D.idle_amb, single(amb')];
end

function report_row(name, level, D, i0)
i = i0:numel(D.label);
fprintf('%-22s %6g %10.3e %10.1f %9.3f %7.2f %7.1f\n', name, level, mean(D.ber(i)), mean(D.sinr(i)), ...
    mean(D.env_corr(i), 'omitnan'), mean(D.coh(i)), mean(D.mmse_gain(i)));
end
