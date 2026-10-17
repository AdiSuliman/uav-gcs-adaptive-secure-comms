function build_threat_model(p)
%% BUILD_THREAT_MODEL - GCS -> UAV link with a multi-antenna UAV receiver
% build_threat_model      params from params.mat, model saved to models/
% build_threat_model(p)   params struct p, model built in memory only (parallel
%                         workers of build_policy_pools.m)
% [Tx: frame + QPSK + RRC] -> [Channel: Rician per UAV antenna] -> [Threat] -> [Level]
%   -> [AWGN per antenna] -> [Rx: RRC per antenna, synchronization, channel estimation,
%   combining, QPSK demod]
%
% Level     the receiver's thermal noise is fixed (thermal_nv.m, the AWGN block); the gain
%           block 'Level' scales everything the antennas receive, our signal and every
%           interferer, to the Eb/N0 of the run (set_link_snr.m), as distance does: the
%           received power the receiver measures is absolute, and every interferer keeps
%           its level over our received signal.
%
% Link: command uplink, tracked directional GCS antenna -> p.n_rx omni antennas on the UAV
% (line array along the fuselage over p.ant_aperture_m, spacing from the number of antennas).
% The GCS antenna gain is part of Eb/N0; the pointing loss of each flight and the gain of
% the tilted UAV antenna toward the GCS at the flight's altitude and attitude scale our
% signal through the Constant block 'GCS' (flight_draws.m, set by link_seed.m).
% Eb/N0 is per receive antenna (per branch).
%
% Tx        frame_layout.m: quiet slot, short and long training, data with pilot blocks, guard.
% Channel   LoS steering vector toward the GCS + diffuse Rayleigh part (sum of 32 sinusoids
%           per antenna with random Doppler angles and phases, Jakes spectrum up to fd;
%           receive correlation p.rx_corr, centred on the GCS direction). The Constant
%           block 'Att' holds the GCS direction and elevation (cone angle on the array),
%           the roll and the pitch with its wobble (hover_attitude.m): the pitch tilts the
%           array and swings the antennas on their lever arm below the centre of rotation
%           (a phase on every path, Banagar & Dhillon); with the roll it sets the gain of
%           the tilted antenna toward the GCS on our LoS (uav_attitude_db.m; its
%           flight-start value is in 'GCS'). The direction turns at the heading rate of
%           the 'Yaw' block (heading_rate.m); a flight that rolls into its turn ('Att'
%           holds the roll-in's start and rate, and the roll at which a shadowing event
%           started) flies level, then rolls at that rate up to
%           the bank, its heading rate following the roll (turn_attitude.m), the roll and
%           the direction taken at every frame. 'Body' scales our signal on each antenna by
%           the airframe loss (body_loss.m). K-factors of
%           our signal and of the interferers come from the Constant block 'Kfac':
%           [p.rician_k p.int_rician_k], or, with p.k_random, drawn per seed from
%           p.k_range_db by link_seed.m (channel_k.m).
%           With p.rx_sync 'real': carrier frequency offset of the two radios per flight
%           (uniform within +-2 p.cfo_ppm of the carrier), Doppler shift of the LoS
%           path from the GCS direction, fd cos(elevation) sin(direction) at the frame,
%           and an unknown arrival time of every frame (uniform fractional delay up to
%           p.timing_max_sym; Channel output 2).
%           With p.tdl, a tapped delay line: the diffuse part on taps p.tdl_step_ns apart up
%           to p.tdl_max_ns, the LoS on tap 0, every tap with its own sinusoids and centred
%           on its source; the Constant block 'Tdl' holds the diffuse tap amplitudes of our
%           signal and of every interferer (flight_draws.m, tdl_profile.m).
% Threat    signal-side threats: path loss scales our signal from its onset frame
%           (p.pl_onset_frames, drawn per run when a range: a step of attenuation, an
%           obstruction or terrain masking; frames before it carry no threat); airframe
%           shadowing, applied in the channel, hides the end of the array farther from
%           the GCS while the attitude puts the airframe in its line of sight in a turn
%           whose bank buries it, at its deepest with the GCS abeam, as deep as the rolls
%           the level is measured at do in Sun et al.'s geometry (shadow_frame.m,
%           shadow_equiv_roll.m, shadow_roll_band.m: the GCS above the belly's horizon, the
%           heading against the GCS azimuth; never while hovering): the hidden antenna loses
%           the share of the depth the burial has reached (Sun et al.'s shape of an event,
%           over a roll-in and as the turn carries the GCS), and it counts as on the air
%           while that loss is at least p.shadow_evt_db, its K-factor the shadow's from
%           then on; no threat on the air otherwise. An antenna fault (one antenna, drawn
%           per seeded run) is an open or lossy connector between the antenna and its
%           receiver, so it attenuates
%           everything that antenna receives, our signal and every interferer, before the
%           receiver's thermal noise, from its onset frame (p.fault_onset_frames, drawn per
%           run when a range: a step within one frame; frames before it carry no threat).
%           Every additive threat is ONE waveform arriving through its own spatial channel
%           (own diffuse fading). The reactive jammer listens to our transmitted frame (the
%           Tx output, before any channel) with an energy detector and is on from its
%           start plus p.reactive_delay_s until its end, at the frame's arrival at the UAV.
%           In-band cap: every additive component reaches at most p.inband_cap_db
%           over our received signal on every antenna over the run: its power is fixed
%           against the 'Cap' block, our signal's weakest antenna at the worst frame
%           of the run (flight_draws.m: the 'GCS' block's loss, the 'Body' block's
%           airframe loss, the attitude, the airframe-shadowing depth), and the path-loss
%           step (inband_cap_amp.m), taken on its level before any countermeasure
%           (p.inband_ref, apply_countermeasure.m), so a countermeasure still lowers it
%           by its own amount.
%           Output 2: share of the frame's samples with the threat on the air, the union
%           over its components: 1 while a component that is not gated is on the air (path
%           loss and an antenna fault from their onset, airframe shadowing while an antenna is
%           hidden by at least p.shadow_evt_db, every other threat always), else the largest
%           share of a gated one (benign packet traffic,
%           the sweeping jammer on our channel); 0 for none. Output 3: [actc levc], each
%           component's share and the level an additive one reaches over our signal on the
%           weakest antenna in the frame [dB], in the threat's order (NaN beyond it); with
%           p.idle_rssi_hz > 0 then, component by component, the on-share of a WLAN's
%           packets or the noise bursts in every RSSI bin of the idle time before the frame
%           (idle_rssi.m; NaN for the other components and the run's first frame), recorded
%           from the schedule's own draws in their own order, so no draw moves.
%           With p.proc_gain_db > 0 (rate_reduce) or p.own_out, output 4 is our own received component
%           (after the path-loss step, a faulty connector and the chain errors), logged as
%           Thr_sig: the receiver-side emulation of the chip-rate field its level
%           measurements read (extract_closed_loop_frames.m), never a decision input.
%           The gated jammers run with the timing of the Constant block 'Gate'
%           (jam_timing.m): the sweeping jammer is on our channel while
%           mod(t + p0, T) of the channel clock lies in sweep_window_s.m, and the
%           noise bursts switch on and off at random with the flight's duty: a random
%           jammer (Xu et al.) at their duties, or a sparse jammer of one-symbol slots
%           (Marti et al.'s J4) at its own.
%           Last, every antenna's receive chain: a gain and phase error fixed per flight
%           (p.chain_amp_db, p.chain_phase_deg). The 'Cal' block (to the 'Cal_db' sink)
%           holds each antenna's level calibration error [dB], applied to the levels the
%           receiver reports (extract_closed_loop_frames.m).
%           Interferer directions come from the Constant block 'AoA': p.int_aoa_deg,
%           or, with p.int_aoa_random, drawn per seed from p.int_aoa_range_deg by
%           link_seed.m (interferer_aoa.m); they turn with the heading and the pitch
%           as our LoS does, in the UAV's horizontal plane. Every interferer's LoS has
%           the Doppler shift of its direction as it turns, fd sin(aoa + heading
%           change), its phase that frequency's integral (los_phase.m), and its diffuse
%           part is centred on its own direction. With p.tdl every interferer has a delay line
%           as ours, its waveform running from the line's longest delay before the frame.
% Rx        Front end (p.adc_bits, adc_frontend.m): per antenna an AGC that sets its gain
%           from the quiet slot and the start of the short training and steps it down
%           within the frame when a block of 16 samples rises p.adc_attack_db above that
%           level (fast attack; Inf: held), and an ADC of p.adc_bits per rail with hard
%           clipping at full scale, p.adc_backoff_db above the rail RMS; before
%           synchronization and combining, and on output 2.
%           'real': coarse frequency from the repeats of the short training, timing from
%           the long training over the arrival window, fine frequency from the two long
%           repeats; every statistic over all antennas in a whitened domain: whitening
%           with the quiet slot before the frame (interference already on the air; from
%           its first sample whose receive-filter memory lies in the frame) or with
%           the training region (also an interferer that appears only with the frame,
%           at the cost of nulling part of our signal: power inversion, Ogawa et al.), or
%           power inversion local to each long-training-sized segment of the training
%           (an interferer channel that changes fast); the one whose timing peak stands
%           out more. Timing and coarse frequency are found jointly on the whole known
%           training (de-modulated at every arrival, a frequency grid search by FFT:
%           Morelli & D'Amico; La Pan et al.). Channel per antenna
%           from the long training and every pilot block (pilot blocks smoothed
%           [1 2 1]/4, linear interpolation between them), estimated on the whitened
%           samples and mapped back to the antennas; interference + noise
%           covariance from the residuals at the known symbols; residual frequency from
%           the phase progression over the pilot blocks, removed before interpolation
%           (MMSE: each step weighed by the inverse covariance of the samples between the
%           two blocks, the interferer as it is there).
%           Decision-directed passes (p.rx_dd_iter) treat the previous decisions as known
%           symbols and repeats the per-window estimation of the 'ideal' receiver, so
%           an interferer channel that changes within the frame is followed; the
%           channel estimator's outputs 4-5 come from the last pass.
%           With the delay line the real receiver spans its delays (rx_taps.m):
%           MRC over the antennas and the channel's symbol lags, then a linear MMSE
%           equalizer of that channel and a white noise level (no spatial nulling: the
%           baseline). Its synchronization searches the training's energy over the
%           arrival window and the line's delays after it: the frequency where that
%           energy summed over the delays peaks (a path one symbol off an arrival peaks
%           1/(16 T) away on the chirp of the long training), the whitening whose
%           frequency peak stands out more, the arrival the largest energy at that
%           frequency, and the lags moved by whole symbols to where they hold the most of
%           it. Its first pass takes the channel of every lag by LS on the training, its
%           phase at every pilot block from the pilots' share of the block's samples.
%           MMSE over space-time vectors, every antenna's samples half a
%           symbol apart around each symbol. Its synchronization: frequency first from
%           the space-time coherence of the training (loaded with the noise floor, the
%           median eigenvalue of the quiet slot's space-time covariance), the arrival
%           from the antennas' coherence at that frequency. Its passes: the channel of
%           our signal by LS on the symbols around every snapshot (the training's in
%           the first pass, the whole frame's known and decided ones after), the
%           interference + noise covariance of the residuals free of our signal, loaded
%           with the noise floor; the first pass window by window with the phase of every
%           window and the residual frequency from their slope, then DDI passes over the
%           frame; per frame the space-time or the antennas-alone output, whichever
%           reproduces the pilots better under weights whose last pass excludes the pilot
%           rows.
%           'ideal': known timing, frequency and transmitted symbols; per window of
%           data symbols the LS channel estimate from the OTHER symbols of the window
%           (leave-one-out) and the covariance of the residual r - h*s.
%           'mrc'  : w = h,          window p.csi_block symbols (baseline)
%           'mmse' : w = R^-1 * h, window p.mmse_window symbols (spatial_diversity
%                    action: nulls up to n_rx-1 interferers; with white noise alone it is
%                    MRC with an estimation loss);
%                    'real' first pass: per window, whitening with the covariance of
%                    the window and its neighbourhood (needs no symbol knowledge), the
%                    nearest known symbols give the channel in that domain, MRC there
%           Output 2 = received IQ of every antenna (sensing tap for the detector),
%           output 3 = combiner output (data soft symbols), outputs 4-5 = the channel
%           estimator's per-32-data-symbol channel estimates and the frame's
%           interference + noise covariance, output 6 = synchronization: arrival
%           [samples], frequency offset [Hz], timing peak over the window mean,
%           second timing peak (more than one symbol away) over the first,
%           fractional arrival [samples] from a parabola through the timing peak, sync
%           coherence (0..1: the training's space-time coherence at the frame's arrival
%           and frequency), the sync-failure flag (1: coherence below p.sync_coh_min,
%           the training was not found; reported, not an erasure) and the pilots' mean
%           squared error under the frame's final weights (space-time: the pilot rows
%           excluded from the last pass's weights, of the output kept;
%           antennas alone: MVDR weights from the decisions only; equalizer: its last
%           pass); zeros with an ideal receiver.
%           The receiver measurements of extract_closed_loop_frames.m use only
%           outputs 1-6.
% Seeds     p.seed, or drawn from the global stream when empty; channel, interferer
%           channels, threat waveforms, AWGN and bit source all derive from it, each
%           from its own stream (link_seed.m, seed_stream.m).
%           Seed and Doppler reach the blocks through the Constant blocks 'Seed' and
%           'Doppler', so link_seed.m changes them without a rebuild and the compiled
%           block code is reused across seeds and UAV speeds.

modelName = 'UAV_GCS_Threat_Link';

save_model = nargin < 1;
if save_model
    if ~exist('params.mat', 'file')
        error('params.mat not found. Run init_params.m first.');
    end
    S = load('params.mat');
    p = S.params;
end
p = antenna_defaults(p);
sps = p.sps;
fs  = p.symbol_rate * sps;
nr  = p.n_rx;

if isempty(p.seed)
    seed = randi(2^26 - 1);                     % flight seeds stay below 2^26 (seed_base.m)
else
    seed = p.seed;
end

if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
new_system(modelName);
quiet_build = isfield(p, 'quiet_build') && p.quiet_build;
if ~quiet_build
    open_system(modelName);
end

fprintf('Building model "%s" (threat: %s, %d UAV antennas, %s, seed %d)...\n', ...
    modelName, p.active_threat, nr, upper(p.rx_combiner), seed);

%% ---- Blocks ----
add_block('commrandsrc3/Bernoulli Binary Generator', [modelName '/BitSource'], 'Position', [30 100 90 140]);
add_block('simulink/User-Defined Functions/MATLAB Function', [modelName '/Tx'],      'Position', [150 95 250 145]);
add_block('simulink/User-Defined Functions/MATLAB Function', [modelName '/Channel'], 'Position', [300 90 390 150]);
add_block('simulink/User-Defined Functions/MATLAB Function', [modelName '/Threat'],  'Position', [440 90 530 150]);
add_block('simulink/Math Operations/Gain',                    [modelName '/Level'],   'Position', [560 95 590 125]);
add_block('commchan3/AWGN Channel',                          [modelName '/AWGN'],    'Position', [610 95 670 125]);
add_block('simulink/User-Defined Functions/MATLAB Function', [modelName '/Rx'],      'Position', [710 90 810 150]);
add_block('simulink/Sources/Constant', [modelName '/Seed'],    'Position', [150 190 220 210]);
add_block('simulink/Sources/Constant', [modelName '/Doppler'], 'Position', [150 230 220 250]);
add_block('simulink/Sources/Constant', [modelName '/AoA'],     'Position', [150 270 220 290]);
add_block('simulink/Sources/Constant', [modelName '/Kfac'],    'Position', [150 310 220 330]);
add_block('simulink/Sources/Constant', [modelName '/Yaw'],     'Position', [150 350 220 370]);
add_block('simulink/Sources/Constant', [modelName '/Corr'],    'Position', [150 390 220 410]);
add_block('simulink/Sources/Constant', [modelName '/GCS'],     'Position', [150 430 220 450]);
add_block('simulink/Sources/Constant', [modelName '/Att'],     'Position', [150 470 220 490]);
add_block('simulink/Sources/Constant', [modelName '/Body'],    'Position', [150 510 220 530]);
add_block('simulink/Sources/Constant', [modelName '/Gate'],    'Position', [150 550 220 570]);
add_block('simulink/Sources/Constant', [modelName '/Tdl'],     'Position', [150 590 220 610]);
add_block('simulink/Sources/Constant', [modelName '/Cap'],     'Position', [150 630 220 650]);
add_block('simulink/Sources/Constant', [modelName '/Cal'],     'Position', [150 670 220 690]);
add_block('simulink/Sinks/To Workspace', [modelName '/tx_sink'], 'Position', [150 30 230 60]);
add_block('simulink/Sinks/To Workspace', [modelName '/rx_sink'], 'Position', [870 90 950 120]);
add_block('simulink/Sinks/To Workspace', [modelName '/Tx_IQ'],   'Position', [300 30 380 60]);
add_block('simulink/Sinks/To Workspace', [modelName '/Rx_IQ'],   'Position', [870 150 950 180]);
add_block('simulink/Sinks/To Workspace', [modelName '/Rx_Z'],    'Position', [870 210 950 240]);
add_block('simulink/Sinks/To Workspace', [modelName '/Rx_H'],    'Position', [870 270 950 300]);
add_block('simulink/Sinks/To Workspace', [modelName '/Rx_R'],    'Position', [870 330 950 360]);
add_block('simulink/Sinks/To Workspace', [modelName '/Thr_act'], 'Position', [580 30 660 60]);
add_block('simulink/Sinks/To Workspace', [modelName '/Rx_S'],    'Position', [870 390 950 420]);
add_block('simulink/Sinks/To Workspace', [modelName '/Thr_comp'], 'Position', [580 -10 660 20]);
add_block('simulink/Sinks/To Workspace', [modelName '/Cal_db'],  'Position', [300 670 380 690]);
if own_output(p), add_block('simulink/Sinks/To Workspace', [modelName '/Thr_sig'], 'Position', [580 -50 660 -20]); end

sf_root = sfroot;
chart_tx = sf_root.find('-isa', 'Stateflow.EMChart', 'Path', [modelName '/Tx']);
if isempty(chart_tx)                       % chart objects not reachable on a loaded-only model
    open_system(modelName);
end
set_script(sf_root, [modelName '/Tx'],      tx_script(p));
set_script(sf_root, [modelName '/Channel'], channel_script(p, fs));
set_script(sf_root, [modelName '/Threat'],  threat_script(p, fs));
set_script(sf_root, [modelName '/Rx'],      rx_script(p));

%% ---- Block parameters ----
set_param([modelName '/BitSource'], ...
    'ProbabilityOfZero', '0.5', ...
    'SampleTime', num2str(1 / p.symbol_rate / p.bits_per_symbol), ...
    'SamplesPerFrame', num2str(p.frame_length));

set_param([modelName '/AWGN'], 'NoiseMethod', 'Variance', 'VarianceSource', 'Parameter', 'Variance', sprintf('%.12g', thermal_nv(p)));
set_link_snr(modelName, p.EbNo_dB(1) + 10*log10(p.bits_per_symbol) - 10*log10(sps), p);

set_param([modelName '/tx_sink'], 'VariableName', 'tx_bits_out', 'SaveFormat', 'Array');
set_param([modelName '/rx_sink'], 'VariableName', 'rx_bits_out', 'SaveFormat', 'Array');
set_param([modelName '/Tx_IQ'],   'VariableName', 'Tx_IQ',       'SaveFormat', 'Array');
set_param([modelName '/Rx_IQ'],   'VariableName', 'Rx_IQ',       'SaveFormat', 'Array');
set_param([modelName '/Rx_Z'],    'VariableName', 'Rx_Z',        'SaveFormat', 'Array');
set_param([modelName '/Rx_H'],    'VariableName', 'Rx_H',        'SaveFormat', 'Array');
set_param([modelName '/Rx_R'],    'VariableName', 'Rx_R',        'SaveFormat', 'Array');
set_param([modelName '/Thr_act'], 'VariableName', 'Thr_act',     'SaveFormat', 'Array');
set_param([modelName '/Rx_S'],    'VariableName', 'Rx_S',        'SaveFormat', 'Array');
set_param([modelName '/Thr_comp'], 'VariableName', 'Thr_comp',   'SaveFormat', 'Array');
set_param([modelName '/Cal_db'],  'VariableName', 'Cal_db',      'SaveFormat', 'Array', 'SampleTime', num2str(p.frame_duration));
if own_output(p), set_param([modelName '/Thr_sig'], 'VariableName', 'Thr_sig', 'SaveFormat', 'Array'); end

%% ---- Wiring ----
add_line(modelName, 'BitSource/1', 'Tx/1',      'autorouting', 'on');
add_line(modelName, 'Tx/1',        'Channel/1', 'autorouting', 'on');
add_line(modelName, 'Seed/1',      'Channel/2', 'autorouting', 'on');
add_line(modelName, 'Doppler/1',   'Channel/3', 'autorouting', 'on');
add_line(modelName, 'Seed/1',      'Threat/2',  'autorouting', 'on');
add_line(modelName, 'Doppler/1',   'Threat/3',  'autorouting', 'on');
add_line(modelName, 'AoA/1',       'Threat/4',  'autorouting', 'on');
add_line(modelName, 'Kfac/1',      'Channel/4', 'autorouting', 'on');
add_line(modelName, 'Kfac/1',      'Threat/5',  'autorouting', 'on');
add_line(modelName, 'Yaw/1',       'Channel/5', 'autorouting', 'on');
add_line(modelName, 'Yaw/1',       'Threat/6',  'autorouting', 'on');
add_line(modelName, 'Corr/1',      'Channel/6', 'autorouting', 'on');
add_line(modelName, 'Corr/1',      'Threat/7',  'autorouting', 'on');
add_line(modelName, 'GCS/1',       'Channel/7', 'autorouting', 'on');
add_line(modelName, 'GCS/1',       'Threat/8',  'autorouting', 'on');
add_line(modelName, 'Att/1',       'Channel/8', 'autorouting', 'on');
add_line(modelName, 'Att/1',       'Threat/9',  'autorouting', 'on');
add_line(modelName, 'Body/1',      'Channel/9', 'autorouting', 'on');
add_line(modelName, 'Gate/1',      'Threat/10', 'autorouting', 'on');
add_line(modelName, 'Tdl/1',       'Channel/10', 'autorouting', 'on');
add_line(modelName, 'Tdl/1',       'Threat/11', 'autorouting', 'on');
add_line(modelName, 'Body/1',      'Threat/12', 'autorouting', 'on');
add_line(modelName, 'Tx/1',        'Threat/13', 'autorouting', 'on');
add_line(modelName, 'Channel/2',   'Threat/14', 'autorouting', 'on');
add_line(modelName, 'Cap/1',       'Threat/15', 'autorouting', 'on');
add_line(modelName, 'Threat/3',    'Thr_comp/1', 'autorouting', 'on');
if own_output(p), add_line(modelName, 'Threat/4', 'Thr_sig/1', 'autorouting', 'on'); end
add_line(modelName, 'Cal/1',       'Cal_db/1',  'autorouting', 'on');
add_line(modelName, 'Channel/1',   'Threat/1',  'autorouting', 'on');
add_line(modelName, 'Threat/1',    'Level/1',   'autorouting', 'on');
add_line(modelName, 'Level/1',     'AWGN/1',    'autorouting', 'on');
add_line(modelName, 'Threat/2',    'Thr_act/1', 'autorouting', 'on');
add_line(modelName, 'AWGN/1',      'Rx/1',      'autorouting', 'on');
add_line(modelName, 'BitSource/1', 'Rx/2',      'autorouting', 'on');
add_line(modelName, 'BitSource/1', 'tx_sink/1', 'autorouting', 'on');
add_line(modelName, 'Rx/1',        'rx_sink/1', 'autorouting', 'on');
add_line(modelName, 'Tx/1',        'Tx_IQ/1',   'autorouting', 'on');
add_line(modelName, 'Rx/2',        'Rx_IQ/1',   'autorouting', 'on');
add_line(modelName, 'Rx/3',        'Rx_Z/1',    'autorouting', 'on');
add_line(modelName, 'Rx/4',        'Rx_H/1',    'autorouting', 'on');
add_line(modelName, 'Rx/5',        'Rx_R/1',    'autorouting', 'on');
add_line(modelName, 'Rx/6',        'Rx_S/1',    'autorouting', 'on');

set_param(modelName, 'SolverType', 'Fixed-step', 'Solver', 'FixedStepDiscrete', 'StopTime', '0.01');
set_param([modelName '/AoA'], 'Value', mat2str(p.int_aoa_deg(:)', 8));
set_param([modelName '/AoA'], 'UserDataPersistent', 'on', 'UserData', struct('int_aoa_random', logical(p.int_aoa_random), ...
    'int_aoa_range_deg', p.int_aoa_range_deg, 'int_aoa_deg', p.int_aoa_deg(:)'));
set_param([modelName '/Kfac'], 'Value', mat2str([p.rician_k p.int_rician_k], 8));
set_param([modelName '/Kfac'], 'UserDataPersistent', 'on', 'UserData', struct('k_random', logical(p.k_random), ...
    'k_range_db', p.k_range_db, 'rician_k', p.rician_k, 'int_rician_k', p.int_rician_k));
set_param([modelName '/Yaw'], 'Value', '0');
set_param([modelName '/Corr'], 'Value', sprintf('%.6f', p.rx_corr));
set_param([modelName '/Corr'], 'UserDataPersistent', 'on', 'UserData', struct('corr_random', logical(p.corr_random), ...
    'corr_range', p.corr_range, 'rx_corr', p.rx_corr));
set_param([modelName '/Yaw'], 'UserDataPersistent', 'on', 'UserData', struct('yaw_random', logical(p.yaw_random), ...
    'roll_max_deg', p.roll_max_deg, 'turn_v_floor', p.turn_v_floor, 'yaw_rate_max', p.yaw_rate_max, 'roll_deg', p.roll_deg, ...
    'c_light', p.c_light, 'carrier_freq', p.carrier_freq));
set_param([modelName '/GCS'], 'Value', '1');
set_param([modelName '/GCS'], 'UserDataPersistent', 'on', 'UserData', struct('gcs_tracked', logical(p.gcs_tracked), ...
    'gcs_ant_dbi', p.gcs_ant_dbi, 'gcs_err_deg', p.gcs_err_deg, 'gcs_floor_db', p.gcs_floor_db, ...
    'alt_random', logical(p.alt_random), 'alt_range_m', p.alt_range_m, 'gcs_h_m', p.gcs_h_m, 'uav_null_db', p.uav_null_db, ...
    'gcs_pt_dbm', p.gcs_pt_dbm, 'carrier_freq', p.carrier_freq, 'lb_uav_dbi', p.lb_uav_dbi, 'lb_nf_db', p.lb_nf_db, ...
    'lb_margin_db', p.lb_margin_db, 'lb_rate_bps', p.lb_rate_bps));
set_param([modelName '/Att'], 'Value', mat2str([p.gcs_aoa_deg 0 p.roll_deg zeros(1, 7)], 8));   % ... wobble, roll-in start, rate and event start roll
set_param([modelName '/Att'], 'UserDataPersistent', 'on', 'UserData', struct('gcs_aoa_random', logical(p.gcs_aoa_random), ...
    'gcs_aoa_range_deg', p.gcs_aoa_range_deg, 'gcs_aoa_deg', p.gcs_aoa_deg, 'wobble_random', logical(p.wobble_random), ...
    'wobble_v_max', p.wobble_v_max, 'wobble_roll_deg', p.wobble_roll_deg, 'wobble_pitch_deg', p.wobble_pitch_deg, ...
    'wobble_amp_deg', p.wobble_amp_deg, 'wobble_pitch_lim_deg', p.wobble_pitch_lim_deg, 'wobble_freq_hz', p.wobble_freq_hz, ...
    'n_rx', nr, 'ant_spacing_wl', p.ant_spacing_wl, 'roll_in_frames', p.roll_in_frames, 'roll_rate_lo', p.roll_rate_lo, ...
    'roll_rate_win', p.roll_rate_win, 'shadow_evt_db', p.shadow_evt_db, 'shadow_hdg_deg', p.shadow_hdg_deg, ...
    'shadow_v_min', p.shadow_v_min, 'shadow_el_deg', p.shadow_el_deg));
set_param([modelName '/Body'], 'Value', mat2str(ones(1, nr)));
set_param([modelName '/Body'], 'UserDataPersistent', 'on', 'UserData', struct('body_random', logical(p.body_random), ...
    'body_loss_db', p.body_loss_db));
set_param([modelName '/Gate'], 'Value', mat2str([p.sweep_period_s(1) 0 0 p.burst_duty], 10));
set_param([modelName '/Gate'], 'UserDataPersistent', 'on', 'UserData', struct('jam_timing_random', ...
    logical(p.jam_timing_random), 'sweep_period_s', p.sweep_period_s, 'burst_duty_range', p.burst_duty_range, ...
    'burst_duty', p.burst_duty, 'burst_j4', p.burst_j4));
NT = tdl_taps(p, fs); ni = numel(p.int_aoa_deg);
set_param([modelName '/Tdl'], 'Value', mat2str([ones(1, 1 + ni); zeros(NT - 1, 1 + ni)]));
set_param([modelName '/Tdl'], 'UserDataPersistent', 'on', 'UserData', struct('tdl', logical(p.tdl), ...
    'tdl_random', logical(p.tdl_random), 'tdl_ds_ns', p.tdl_ds_ns, 'tdl_step_ns', p.tdl_step_ns, ...
    'tdl_max_ns', p.tdl_max_ns, 'tdl_sig_ds', p.tdl_sig_ds, 'tdl_sig_alt_m', p.tdl_sig_alt_m, ...
    'tdl_int_ds', p.tdl_int_ds, 'tdl_clip_ns', p.tdl_clip_ns));
set_param([modelName '/Cap'], 'Value', '1');
set_param([modelName '/Cap'], 'UserDataPersistent', 'on', 'UserData', struct('cap_frames', p.cap_frames, ...
    'cycle_s', p.cycle_s, 'air_s', (p.samples_per_frame - 1) / fs, 'shadow_spec', shadow_spec(p)));
set_param([modelName '/Cal'], 'Value', mat2str(zeros(1, nr)));
set_param([modelName '/Cal'], 'UserDataPersistent', 'on', 'UserData', struct('cal_random', logical(p.cal_random), ...
    'cal_err_db', p.cal_err_db));
link_seed(modelName, seed, p.fd_max);

%% ---- Save ----
if save_model
    if ~isfolder('models'); mkdir('models'); end
    save_system(modelName, ['models/' modelName '.slx']);
    fprintf('Model saved to models/%s.slx\n', modelName);
end
fprintf('Done. threat=%s, JSR=%.1f dB, K %s, fd=%.1f Hz, n_rx=%d, rho=%.2f, Rx=%s, AoA %s.\n', ...
    p.active_threat, p.jsr_db, ternary(p.k_random, sprintf('%g-%g dB per seed', p.k_range_db), ...
    sprintf('%.1f dB', p.rician_k)), p.fd_max, nr, p.rx_corr, p.rx_combiner, ...
    ternary(p.int_aoa_random, 'random per seed', 'fixed'));
end

%% ===================== Block scripts =====================
function s = tx_script(p)
% Frame (frame_layout.m): training and pilots from the template, the data symbols in
% their positions, QPSK + RRC; the quiet slot before the frame and the guard after it are silent.
L = frame_layout(p);
s = sprintf([ ...
    'function y = fcn(bits)\n' ...
    '%%#codegen\n' ...
    'persistent txf\n' ...
    'if isempty(txf)\n' ...
    '    txf = comm.RaisedCosineTransmitFilter(''RolloffFactor'', %.6f, ''FilterSpanInSymbols'', %d, ''OutputSamplesPerSymbol'', %d);\n' ...
    'end\n' ...
    'f = %s;\n' ...
    'f(%s) = pskmod(bits, 4, pi/4, ''gray'', ''InputType'', ''bit'');\n' ...
    'y = txf(f);\n' ...
    'end\n'], p.rolloff, p.filter_span, p.sps, cvec2(L.tmpl), mat2str(L.idx_data(:)'));
end

function s = channel_script(p, fs)
% Signal channel: our signal scaled by the 'GCS' block (the flight's pointing loss and the
% gain of the UAV antenna toward the GCS at the start of the flight), then LoS steering
% vector toward the GCS + correlated diffuse fading centred on it; K-factor kdb(1) from the
% 'Kfac' block. The 'Att' block [GCS direction, elevation, roll, pitch, wobble amplitude,
% frequency, phase, roll-in start, roll rate, roll at a shadowing event's start] sets the
% cone angle of the GCS on the array,
% the antenna gain on the LoS as the attitude changes (the direction and the roll at the
% frame, turn_attitude.m), and the lever-arm phase of every path; 'Body' our signal's
% amplitude on each antenna. With a real receiver: frequency offset of
% the two radios and LoS Doppler shift per flight, unknown arrival time per frame
% (fractional delay applied in the frequency domain; the frame ends in its guard; output 2,
% the delay in samples, for the reactive jammer). Our LoS Doppler is that of the GCS
% direction at the frame, fd cos(elevation) sin(direction): the UAV flies along its
% heading, 90 deg the GCS ahead (gcs_aoa.m). With the delay line, tap m carries the frame m taps
% later (our signal is silent before the frame) with the diffuse amplitude of column 1
% of the 'Tdl' block.
nr = p.n_rx;
cyc = round(p.cycle_s * fs);          % channel samples from one frame to the next (one decision cycle)
real_rx = strcmpi(p.rx_sync, 'real');
if real_rx
    pers = ' cfo';
    imp = sprintf('if isempty(cfo)\n    cfo = %.6f * (2*rand - 1);\nend\n', 2 * p.cfo_ppm * 1e-6 * p.carrier_freq);
    dly = sprintf(['tau = rand * %.6f;\n' ...
        'kk = [0:ceil(Ns/2)-1, -floor(Ns/2):-1].'';\n' ...
        'x = ifft(fft(x) .* exp(-1j*2*pi*kk*tau/Ns));\n' ...
        'r = exp(1j*2*pi*cfo*t);\n' ...
        'fl = cosd(att(2)) * sind(bt);\n' ...
        'los = exp(1j*2*pi*fd*fl*t);\n'], p.timing_max_sym * p.sps);
    mix = '    y(:, k) = gk * bdy(k) * x .* r .* (sqrt(Kk/(Kk+1)) * a(:, k) .* gl .* los + sqrt(1/(Kk+1)) * D(:, k));\n';
else
    pers = ''; imp = ''; dly = sprintf('tau = 0;\n');
    mix = '    y(:, k) = gk * bdy(k) * x .* (sqrt(Kk/(Kk+1)) * a(:, k) .* gl + sqrt(1/(Kk+1)) * D(:, k));\n';
end
% airframe shadowing: the antenna the airframe hides from the GCS at this frame's attitude
% (shadow_frame.m; none while the attitude leaves the line of sight clear, the turn's bank
% does not bury it as the level's rolls do, or the UAV hovers) loses the share gs of
% p.shadow_db the event has reached; its K-factor is its own until that loss counts as an
% event (p.shadow_evt_db) and the shadow's from then on (p.shadow_k_db: about 15 dB
% outside the shadowing area, -16 dB inside it, Sun et al., Sec. III, Fig. 12)
thr = lower(p.active_threat);
shd = any(strcmp(strsplit(thr, '+'), 'airframe_shadowing'));
if shd
    sel = sprintf(['    Kk = K; gk = 1;\n    if k == hs\n        if %.6f * gs >= %.6f\n            Kk = %.10g;\n        end\n' ...
        '        gk = 10^(-%.6f * gs / 20);\n    end\n'], p.shadow_db, p.shadow_evt_db, 10^(p.shadow_k_db / 10), p.shadow_db);
else
    sel = sprintf('    Kk = K; gk = 1;\n');
end
% specular ground reflection (optional): a copy of our line-of-sight term, p.spec_amp of its
% amplitude, p.spec_delay_ns later, with a phase drawn per flight; the reflection point lies
% under the UAV-GCS line, so it arrives at nearly the same broadside angle (Sun et al.)
if isfield(p, 'spec_amp') && p.spec_amp > 0
    pers = [pers ' sph'];
    imp = [imp sprintf('if isempty(sph)\n    sph = 2*pi*rand;\nend\n')];
    xs = sprintf(['kk2 = [0:ceil(Ns/2)-1, -floor(Ns/2):-1].'';\n' ...
        'xs = ifft(fft(x) .* exp(-1j*2*pi*kk2*%.6f/Ns)) * (%.8f * exp(1j*sph));\n'], ...
        p.spec_delay_ns * 1e-9 * fs, p.spec_amp);
    if real_rx
        mix = ['    y(:, k) = gk * bdy(k) * (x .* r .* (sqrt(Kk/(Kk+1)) * a(:, k) .* gl .* los + sqrt(1/(Kk+1)) * D(:, k))' ...
            ' + xs .* r .* (sqrt(Kk/(Kk+1)) * a(:, k) .* gl .* los));\n'];
    else
        mix = ['    y(:, k) = gk * bdy(k) * (x .* (sqrt(Kk/(Kk+1)) * a(:, k) .* gl + sqrt(1/(Kk+1)) * D(:, k))' ...
            ' + xs .* (sqrt(Kk/(Kk+1)) * a(:, k) .* gl));\n'];
    end
else
    xs = '';
end
% the antenna's gain toward the GCS relative to its flight-start value in 'GCS', and the
% lever-arm phase of the LoS (the sign of the Doppler terms); the array tilts with the
% pitch (uav_attitude_db.m)
tilt = sprintf(['[ga, ca, cz] = uav_attitude_db(att(2), bt, rt, th, %.6f);\n' ...
    'gl = 10.^((ga - uav_attitude_db(att(2), att(1), r0, att(4), %.6f)) / 20) .* exp(1j * %.12f * cz);\n' ...
    'a = exp(-1j * %.12f * ca * %s);\n' ...
    'D = D .* a;\n'], p.uav_null_db, p.uav_null_db, lever_k(p), 2*pi*p.ant_spacing_wl, ant_pos(nr));
[NT, S] = tdl_taps(p, fs);
lt = '';
if NT > 1
    pers = [pers ' fT pT'];
    imp = [imp sprintf('if isempty(fT)\n    fT = cos(2*pi*rand(32, %d, %d));\nend\nif isempty(pT)\n    pT = 2*pi*rand(32, %d, %d);\nend\n', ...
        nr, NT-1, nr, NT-1)];
    rr = ''; if real_rx, rr = sprintf(' .* r(m*%d+1:Ns)', S); end
    lt = [tdl_code('Dt', 'fT', 'pT', 'a', 1, p, fs, NT) sprintf(['xd = complex(zeros(Ns, %d));\nfor m = 1:%d\n' ...
        '    xd(m*%d+1:Ns, m) = x(1:Ns-m*%d)%s;\nend\n'], NT-1, NT-1, S, S, rr)];
    mix = [strrep(mix, 'sqrt(1/(Kk+1)) * D(:, k)', 'sqrt(1/(Kk+1)) * tdl(1, 1) * D(:, k)') sprintf(['    for m = 1:%d\n' ...
        '        y(:, k) = y(:, k) + gk * bdy(k) * sqrt(1/(Kk+1)) * tdl(m+1, 1) * xd(:, m) .* Dt(:, k, m);\n    end\n'], NT-1)];
end
s = [sprintf('function [y, tau] = fcn(x, seed, fd, kdb, yaw, rho, gcs, att, bdy, tdl)\n%%%%#codegen\npersistent f0 ph n%s\n', pers) ...
    sprintf('if isempty(f0)\n    rng(seed, ''twister'');\nend\nx = gcs * x;\n') ...
    sos_init('f0', 'ph', nr) imp ...
    sprintf('if isempty(n)\n    n = 0;\nend\nNs = size(x, 1);\nt = (n + (0:Ns-1).'') / %.1f;\nn = n + max(Ns, %d);\n', fs, cyc) ...
    sprintf('[bt, rt] = turn_attitude(att, yaw, t(1));\n[~, r0] = turn_attitude(att, yaw, 0);\n') ...
    pitch_code() sos_gains('D', 'f0', 'ph', p) dly xs ...
    sprintf('K = 10^(kdb(1)/10);\n') tilt lt shadow_code(p, shd) ...
    sprintf(['y = complex(zeros(Ns, %d));\n' ...
    'for k = 1:%d\n' sel mix ...
    'end\n' ...
    'end\n'], nr, nr)];
s = strrep(s, '%%#codegen', '%#codegen');
end

function s = threat_script(p, fs)
% Signal-side components first (they act on our signal), then every
% additive component as one waveform through its own spatial channel, held to the
% in-band cap over our received signal. An emitter stays in the UAV's horizontal plane:
% its LoS turns with the heading, is seen by the array tilted by the pitch ('Att' block)
% and has the Doppler shift of its direction at the frame, fd sin(aoa + heading change),
% its phase at the frame's start the integral of that shift (los_phase.m, as the idle time
% takes it, idle_rssi.m); its diffuse part is centred on
% its own direction; the antennas' lever arm moves the phase of every path. With the
% delay line, every waveform runs Nw samples at times tw, from the line's longest delay
% before the frame, and tap m carries it m taps late with the diffuse amplitude of the
% interferer's column of the 'Tdl' block.
% Per frame every component's share on the air, actc, in the threat's order; output 2 their
% union (1 while a component that is not gated is on the air, else the largest gated
% share), output 3 [actc levc]: levc the level each additive component reaches over our
% signal on its weakest antenna in the frame [dB] (sig_weak_db.m).
nr  = p.n_rx;
sps = p.sps;
thr = lower(p.active_threat);
if any(strcmp(thr, {'', 'none'}))
    parts = {};
else
    parts = strsplit(thr, '+');
end
if numel(parts) > 3
    error('build_threat_model: at most three threat components, not %d', numel(parts));
end
SIGSIDE = {'path_loss', 'antenna_fault', 'airframe_shadowing'};
sig  = parts(ismember(parts, SIGSIDE));
addc = parts(~ismember(parts, SIGSIDE));
if numel(addc) > numel(p.int_aoa_deg)
    error('build_threat_model: %d additive components, only %d interferer directions', numel(addc), numel(p.int_aoa_deg));
end
slot = @(c) find(strcmp(parts, c), 1);             % a component's place in actc and levc
PL = 0;
if ismember('path_loss', sig), PL = p.path_loss_db; end
shd = shadow_spec(p);
VC = p.c_light / p.carrier_freq;                   % speed per Hz of Doppler

pers = {}; init = {}; body = {}; tpers = {}; tinit = {};
if any(ismember(sig, {'antenna_fault'}))
    pers{end+1} = 'hit_ant'; init{end+1} = sprintf('hit_ant = randi(%d);', nr);   % the antenna with the open connector
end
body{end+1} = sprintf(['Ns = size(u, 1);\ny = u;\nt = (nI + (0:Ns-1).'') / %.1f;\nnI = nI + max(Ns, %d);\nnfr = nfr + 1;\n' ...
    'actc = nan(1, 3);\nlevc = nan(1, 3);\nplon = 0;\n[bt, rt, dp] = turn_attitude(att, yaw, t(1));\n'], fs, round(p.cycle_s * fs));   % interferer channels on the same clock as ours; nfr: frame of the run; the attitude at the frame

on1 = p.pl_onset_frames(1); on2 = p.pl_onset_frames(end);
fo1 = p.fault_onset_frames(1); fo2 = p.fault_onset_frames(end);
for i = 1:numel(sig)
    k = slot(sig{i});
    switch sig{i}
        case 'path_loss'
            % a step of attenuation from the onset frame on, drawn per run in the range
            % (an obstruction or terrain masking; a constant loss from the first frame is a
            % longer range)
            body{end+1} = sprintf('actc(%d) = 0;\nif nfr >= pl_on\n    y = y * %.8f;\n    actc(%d) = 1;\n    plon = %.8f;\nend\n', ...
                k, 10^(-PL/20), k, PL); %#ok<AGROW>
        case 'antenna_fault'
            % applied after the interferers: the connector sits between the antenna and its
            % receiver; it opens at its onset frame, within one frame
            body{end+1} = sprintf('actc(%d) = double(nfr >= af_on);\n', k); %#ok<AGROW>
        case 'airframe_shadowing'
            % applied in the channel: the hidden antenna loses its line of sight there; the
            % event counts while its loss reaches p.shadow_evt_db
            body{end+1} = sprintf(['[hs, gs] = shadow_frame(bt, att(2), rt, [abs(att(3)) att(10)], att(4), %d, %s, %.6f, fd * %.12g, %.6f, %.6f);\n' ...
                'actc(%d) = double(hs > 0 && %.6f * gs >= %.6f);\n'], nr, mat2str(shd(2:3), 10), shd(4), VC, shd(5), shd(8), ...
                k, shd(1), shd(7)); %#ok<AGROW>
    end
end
own = own_output(p);
if own, body{end+1} = sprintf('ys = y;\n'); end         % our own received component (rate_reduce's chip-rate field)
[NT, S] = tdl_taps(p, fs); E = (NT - 1) * S;
if NT > 1 && ~isempty(addc)
    body{end+1} = sprintf('Nw = Ns + %d;\ntw = [t(1) - (%d:-1:1).'' / %.1f; t];\n', E, E, fs);
elseif ~isempty(addc)
    body{end+1} = sprintf('Nw = Ns;\ntw = t;\n');
end
% the receiver's idle time between frames: a gated schedule's on-share per RSSI bin
% (idle_rssi.m), recorded from the schedule's own draws in their own order
[NBI, TBI] = idle_bins(p, fs, E);
if NBI > 0, body{end+1} = sprintf('idl = nan(3, %d);\n', NBI); end

if ~isempty(addc)
    % our signal on its weakest antenna in this frame [dB], the path-loss step included
    body{end+1} = [sprintf('Ki = 10^(kdb(2)/10);\n') pitch_code() ...
        sprintf('wk = 20*log10(gcs) + sig_weak_db(att, yaw, t(1), [t(1); t(Ns)], kdb(1), bdy, %s, fd * %.12g, %.6f) - plon;\n', ...
        mat2str(shd, 10), VC, p.uav_null_db)];
end
for c = 1:numel(addc)
    comp = addc{c};
    k = slot(comp);
    lf = 'jsr_db';                                  % level field of the component
    gated = false;
    switch comp
        case 'jamming'
            w = sprintf('w = sqrt(%.8f/2) * complex(randn(Nw, 1), randn(Nw, 1));\n', 10^(p.jsr_db/10));
        case 'tone_jamming'
            % CW tone at a random offset inside the flat part of our band; power
            % scaled so its in-band power over our signal equals tone_jsr_db
            lf = 'tone_jsr_db';
            pers{end+1} = 'tone_f'; init{end+1} = sprintf('tone_f = %.4f * (2*rand - 1);', p.tone_offset_hz); %#ok<AGROW>
            pers{end+1} = 'tone_ph'; init{end+1} = 'tone_ph = 2*pi*rand;'; %#ok<AGROW>
            w = sprintf('w = sqrt(%.8f) * exp(1j * (2*pi*tone_f*tw + tone_ph));\n', 10^(p.tone_jsr_db/10) * tone_gain(p));
        case 'benign_interference'
            lf = 'benign_int_db';
            if ~isempty(p.benign_occ)
                % WLAN packets: log-uniform durations; idle gaps gamma-distributed with the
                % field shape, their mean set by the flight's occupancy (Marsaglia-Tsang
                % sampler, boosted for a shape below 1); the schedule runs on the channel
                % clock, on with the occupancy's probability from t = 0 (its first switch)
                gated = true;
                d = p.benign_pkt_s; md = (d(2) - d(1)) / log(d(2) / d(1));
                pers{end+1} = 'b_occ'; init{end+1} = sprintf('b_occ = %.6f + %.6f * rand;', p.benign_occ(1), diff(p.benign_occ)); %#ok<AGROW>
                pers{end+1} = 'b_on'; init{end+1} = 'b_on = rand >= b_occ;'; %#ok<AGROW>
                pers{end+1} = 'b_next'; init{end+1} = 'b_next = 0;'; %#ok<AGROW>
                sw_on = sprintf(['        if b_on\n            b_on = false;\n' gamma_draw(p.benign_idle_shape, 'gg') ...
                    '            b_next = b_next + gg * %.10f * (1 - b_occ) / b_occ / %.10f;\n' ...
                    '        else\n            b_on = true; b_next = b_next + exp(%.8f + %.8f * rand);\n        end\n'], ...
                    md, p.benign_idle_shape, log(d(1)), log(d(2) / d(1)));
                w = [idle_code('b_on', 'b_next', sw_on, k, NBI, TBI, p.cycle_s, fs) ...
                    sprintf('on = false(Nw, 1);\nfor i = 1:Nw\n    while tw(i) >= b_next\n') sw_on ...
                    sprintf(['    end\n    on(i) = b_on;\nend\nactc(%d) = mean(double(on(Nw-Ns+1:Nw)));\n' ...
                    'w = sqrt(%.8f/2) * complex(randn(Nw, 1), randn(Nw, 1)) .* on;\n'], k, 10^(p.benign_int_db/10))];
            else
                w = sprintf('w = sqrt(%.8f/2) * complex(randn(Nw, 1), randn(Nw, 1));\n', 10^(p.benign_int_db/10));
            end
        case 'noise_burst'
            % the flight's duty a = gate(4) sets the pattern, on the channel clock. From
            % Xu et al.'s duties up (p.burst_duty_range): a random jammer, bursts of
            % U[0, p.burst_on_sym] symbols and sleeps of U[0, p.burst_on_sym (1 - a) / a].
            % Below them: Marti et al.'s sparse jammer J4, each one-symbol slot of the
            % jammer's own clock (a random phase) jammed with probability a. On from the
            % run's start when gate(3) < a, its first switch inside that burst, sleep or slot
            sj = p.burst_duty_range(1); ts = 1 / p.symbol_rate;
            pers{end+1} = 'nb_on'; init{end+1} = 'nb_on = gate(3) < gate(4);'; %#ok<AGROW>
            pers{end+1} = 'nb_next'; init{end+1} = sprintf(['nb_next = rand * ((gate(4) < %.10g) * %.10g + ' ...
                '(gate(4) >= %.10g) * %.10g * (nb_on + (~nb_on) * (1 - gate(4)) / gate(4)));'], ...
                sj, ts, sj, p.burst_on_sym / p.symbol_rate); %#ok<AGROW>
            sw_on = sprintf(['        if gate(4) < %.10g\n            nb_on = rand < gate(4); nb_next = nb_next + %.10g;\n' ...
                '        elseif nb_on\n            nb_on = false; nb_next = nb_next + rand * toff;\n' ...
                '        else\n            nb_on = true; nb_next = nb_next + rand * ton;\n        end\n'], sj, ts);
            w = [sprintf('ton = %.10g;\ntoff = ton * (1 - gate(4)) / gate(4);\n', p.burst_on_sym / p.symbol_rate) ...
                idle_code('nb_on', 'nb_next', sw_on, k, NBI, TBI, p.cycle_s, fs) ...
                sprintf('on = false(Nw, 1);\nfor i = 1:Nw\n    while tw(i) >= nb_next\n') sw_on ...
                sprintf('    end\n    on(i) = nb_on;\nend\nw = sqrt(%.8f/2) * complex(randn(Nw, 1), randn(Nw, 1)) .* on;\n', ...
                10^(p.jsr_db/10))];
        case 'sweeping_jammer'
            % on our channel while the sweep's window covers it, on the channel clock: the
            % flight's sweep period gate(1) and phase gate(2)
            gated = true;
            g = sweep_window_s(p);
            w = sprintf(['tsw = mod(tw + gate(2), gate(1));\non = tsw >= %.10g & tsw < %.10g;\n' ...
                'actc(%d) = mean(double(on(Nw-Ns+1:Nw)));\n' ...
                'w = sqrt(%.8f/2) * complex(randn(Nw, 1), randn(Nw, 1)) .* on;\n'], g(1), g(2), k, 10^(p.jsr_db/10));
        case 'reactive_jamming'
            % on from our transmitted frame's start, as an energy detector hears the GCS's
            % transmitter output xt (before any channel: no fading, path loss or airframe
            % loss of ours reaches it), plus the reaction delay p.reactive_delay_s, until the
            % frame's end; at the frame's arrival at the UAV, tau samples late (Channel output 2)
            w = sprintf(['i1 = 0; i2 = 0;\nfor i = 1:Ns\n    if abs(xt(i))^2 > %.8f\n        if i1 == 0\n' ...
                '            i1 = i;\n        end\n        i2 = i;\n    end\nend\non = false(Nw, 1);\nif i1 > 0\n' ...
                '    for i = 1:Ns\n        on(%d + i) = i - i1 >= tau + %.6f && i - i2 <= tau;\n    end\nend\n' ...
                'w = sqrt(%.8f/2) * complex(randn(Nw, 1), randn(Nw, 1)) .* on;\n'], ...
                p.reactive_threshold / sps, E, p.reactive_delay_s * fs, 10^(p.jsr_db/10));
        case 'spoofing'
            lf = 'spoof_sir_db';
            pers{end+1} = 'spoof_txf'; %#ok<AGROW>
            init{end+1} = sprintf(['spoof_txf = comm.RaisedCosineTransmitFilter(''RolloffFactor'', %.6f, ' ...
                '''FilterSpanInSymbols'', %d, ''OutputSamplesPerSymbol'', %d);'], p.rolloff, p.filter_span, sps); %#ok<AGROW>
            w = sprintf(['nSym = ceil(Nw / %d);\n' ...
                'sp = spoof_txf(pskmod(randi([0 1], nSym*2, 1), 4, pi/4, ''gray'', ''InputType'', ''bit''));\n' ...
                'w = %.8f * sp(1:Nw);\n'], sps, 10^(p.spoof_sir_db/20));
        otherwise
            error('build_threat_model: unsupported threat component ''%s''', comp);
    end
    if ~gated
        w = [w sprintf('actc(%d) = 1;\n', k)]; %#ok<AGROW>
    end
    if isfinite(p.inband_cap_db)
        % in-band cap on the level before any countermeasure, against our signal's weakest
        % antenna over the run (the 'Cap' block, flight_draws.m) and the path-loss step: the
        % emitter's power stays fixed; the countermeasure's own reduction (the level field of
        % p) still applies on top
        L = p.(lf);
        if isfield(p, 'inband_ref') && isfield(p.inband_ref, lf), L = p.inband_ref.(lf); end
        w = [w sprintf('cf = min(1, %.10g * cap);\nw = w * cf;\nlevc(%d) = %.6f + 20*log10(cf) - wk;\n', ...
            inband_cap_amp(L, PL, p.inband_cap_db), k, p.(lf))]; %#ok<AGROW>
    else
        w = [w sprintf('levc(%d) = %.6f - wk;\n', k, p.(lf))]; %#ok<AGROW>
    end
    fI = sprintf('fI%d', c); pI = sprintf('pI%d', c);
    pers{end+1} = fI; init{end+1} = sprintf('%s = cos(2*pi*rand(32, %d));', fI, nr); %#ok<AGROW>
    pers{end+1} = pI; init{end+1} = sprintf('%s = 2*pi*rand(32, %d);', pI, nr); %#ok<AGROW>
    dop = '0 * t';
    if p.int_los_doppler, dop = sprintf('los_phase(aoa(%d), att, yaw, fd, t(1)) + 2*pi*fd*sind(aoa(%d) + dp) * (t - t(1))', c, c); end
    mx = sprintf('    y(:, k) = y(:, k) + w .* (sqrt(Ki/(Ki+1)) * aI(:, k) .* lI + sqrt(1/(Ki+1)) * dI(:, k));\n');
    lt = '';
    if NT > 1
        fT = sprintf('fT%d', c); pT = sprintf('pT%d', c);
        tpers = [tpers {fT pT}]; %#ok<AGROW>
        tinit = [tinit {sprintf('%s = cos(2*pi*rand(32, %d, %d));', fT, nr, NT-1), ...
            sprintf('%s = 2*pi*rand(32, %d, %d);', pT, nr, NT-1)}]; %#ok<AGROW>
        lt = tdl_code('Dt', fT, pT, 'aI', 1 + c, p, fs, NT);
        mx = [sprintf('    y(:, k) = y(:, k) + w(%d:Nw) .* (sqrt(Ki/(Ki+1)) * aI(:, k) .* lI + sqrt(1/(Ki+1)) * tdl(1, %d) * dI(:, k));\n', ...
            E + 1, 1 + c) sprintf(['    for m = 1:%d\n' ...
            '        y(:, k) = y(:, k) + sqrt(1/(Ki+1)) * tdl(m+1, %d) * w(%d-m*%d+(0:Ns-1).'') .* Dt(:, k, m);\n' ...
            '    end\n'], NT-1, 1 + c, E + 1, S)];
    end
    body{end+1} = [w sos_gains('dI', fI, pI, p) sprintf([ ...
        'sI = sind(aoa(%d) + dp);\n' ...
        'aI = exp(-1j * %.12f * (cosd(th) * sI) * %s);\n' ...
        'lI = exp(1j * (%s + %.12f * cosd(rt) * sI * sind(th)));\n' ...
        'dI = dI .* aI;\n'], c, 2*pi*p.ant_spacing_wl, ant_pos(nr), dop, lever_k(p)) lt ...
        sprintf('for k = 1:%d\n', nr) mx sprintf('end\n')]; %#ok<AGROW>
end
if ismember('antenna_fault', sig)
    % the faulty connector attenuates everything its antenna receives, our signal and every
    % interferer, ahead of the receiver's thermal noise (an attenuator at ambient
    % temperature leaves the noise floor at kTB)
    body{end+1} = sprintf('if nfr >= af_on\n    y(:, hit_ant) = y(:, hit_ant) * %.8f;\nend\n', 10^(-p.fault_atten_db/20));
    if own, body{end+1} = sprintf('if nfr >= af_on\n    ys(:, hit_ant) = ys(:, hit_ant) * %.8f;\nend\n', 10^(-p.fault_atten_db/20)); end
end
if p.chain_amp_db > 0 || p.chain_phase_deg > 0
    % receive chains: a gain and phase error per antenna, fixed for the flight (everything
    % the antenna receives passes its chain)
    pers{end+1} = 'gch'; %#ok<AGROW>
    init{end+1} = sprintf('gch = 10.^(%.6f * randn(1, %d) / 20) .* exp(1j * %.8f * randn(1, %d));', ...
        p.chain_amp_db, nr, deg2rad(p.chain_phase_deg), nr); %#ok<AGROW>
    body{end+1} = sprintf('for k = 1:%d\n    y(:, k) = y(:, k) * gch(k);\nend\n', nr); %#ok<AGROW>
    if own, body{end+1} = sprintf('for k = 1:%d\n    ys(:, k) = ys(:, k) * gch(k);\nend\n', nr); end %#ok<AGROW>
end
% union of the components on the air: 1 while one that is not gated is, else the largest
% gated share
body{end+1} = sprintf('act = 0;\nfor i = 1:3\n    if ~isnan(actc(i)) && actc(i) > act\n        act = actc(i);\n    end\nend\ncomp = [actc levc];\n');
if NBI > 0, body{end+1} = sprintf('comp = [comp, reshape(idl.'', 1, [])];\n'); end   % the idle on-shares, component by component

pers = [{'nI', 'nfr'}, pers, tpers]; init = [{'nI = 0;', 'nfr = 0;'}, init, tinit];   % the delay line's sinusoids drawn last
if ismember('path_loss', sig)                       % then the onset frame of the path-loss step
    pers{end+1} = 'pl_on'; init{end+1} = sprintf('pl_on = %d + floor(%d * rand);', on1, on2 - on1 + 1);
end
if ismember('antenna_fault', sig)                   % then the connector's, drawn only over a range
    pers{end+1} = 'af_on'; init{end+1} = sprintf('af_on = %d;', fo1);
    if fo2 > fo1, init{end} = sprintf('af_on = %d + floor(%d * rand);', fo1, fo2 - fo1 + 1); end
end
outs = 'y, act, comp'; if own, outs = 'y, act, comp, ys'; end
head = sprintf(['function [%s] = fcn(u, seed, fd, aoa, kdb, yaw, rho, gcs, att, gate, tdl, bdy, xt, tau, cap)\n' ...
    '%%#codegen\npersistent seeded\n'], outs);
for i = 1:numel(pers)
    head = [head sprintf('persistent %s\n', pers{i})]; %#ok<AGROW>
end
head = [head sprintf('if isempty(seeded)\n    seeded = true;\n    rng(seed + 7, ''twister'');\nend\n')];
for i = 1:numel(init)
    head = [head sprintf('if isempty(%s)\n    %s\nend\n', pers{i}, init{i})]; %#ok<AGROW>
end
s = [head strjoin(body, '') sprintf('end\n')];
end

function s = rx_script(p)
% Per-antenna matched filter at p.sps samples per symbol; synchronization from the
% training ('real') or known timing and frequency ('ideal'); channel estimation;
% MRC or MMSE per window of data symbols; QPSK demod of the data symbols.
L = frame_layout(p);
nr = p.n_rx;
Dt = p.filter_span;                       % Tx + Rx filter delay [symbols]
switch lower(p.rx_combiner)
    case 'mrc',  mode = 1; B = p.csi_block;
    case 'mmse', mode = 2; B = p.mmse_window;
    otherwise, error('build_threat_model: unknown rx_combiner ''%s''', p.rx_combiner);
end
ideal = ~strcmpi(p.rx_sync, 'real');
tp = rx_taps(p);                          % the real receiver's taps for the channel's delays
nt = 1; ne = 1; rk = [0 0];
if ~ideal && mode == 2
    nt = tp.nt; B = tp.window;
elseif ~ideal
    ne = tp.ne; rk = tp.lags;
end
NS = L.n_sig;                             % symbols carrying our signal
TM = round(p.timing_max_sym * p.sps);     % arrival window [samples]
TE = TM;                                  % delays the training's energy is searched over [samples]
if ne > 1                                 % the equalizer: the arrival window and the line's delays after it
    TE = TM + ceil(p.tdl_max_ns * 1e-9 * p.symbol_rate * p.sps);
end
QN = L.NQ * p.sps;                        % quiet-slot samples before the leading pulse tail of the frame
Q0 = Dt * p.sps + 1;                      % first quiet-slot sample with the receive filter's memory in this frame
if QN - Q0 + 1 < 4 * nr
    error('build_threat_model: quiet slot too short for the interference covariance');
end
c = {
    'function [bits, iqa, z, Hq, Rq, sy] = fcn(u, txbits)'
    '%#codegen'
    'persistent rxf'
    sprintf('NR = %d; SPS = %d; Dt = %d; B = %d; MODE = %d; IDEAL = %d; DDI = %d; HW = %d;', nr, p.sps, Dt, B, mode, ideal, p.rx_dd_iter, ceil((p.pilot_every + p.pilot_block) / 2) + 4)
    sprintf('NT = %d; T0 = %d; HS = %d; NV = %d; HWD = %d; Q0 = %d; BA = %d;', nt, (nt - 1) / 2, p.sps / 2, nr * nt, ...
        ternary(nt > 1, ceil((p.pilot_every + p.pilot_block) / 2) + 4, p.pilot_block), Q0, ternary(nt > 1, p.mmse_window, B))
    sprintf('NE = %d; E0 = %d; RP = %d; RQ = %d; NRK = %d; XO = %d; HWE = %d;', ne, (ne - 1) / 2, rk(1), rk(2), ...
        sum(rk) + 1, (ne - 1) / 2 + max(rk), B / 2)
    sprintf('NTS = %d; NTN = %d; MH = %d; BS = %d; FIT = %d; TAU = %.4f;', tp.ns, tp.nn, tp.mh * (nt > 1), ...
        p.mmse_window, 2 * (nt == 1 && ne == 1), p.sync_coh_min)
    sprintf('ADCB = %d; ABO = %.2f; IS0 = %d; AAT = %.2f;', ternary(isfinite(p.adc_bits) && p.adc_bits > 0, p.adc_bits, 0), ...
        p.adc_backoff_db, L.NQ * p.sps + p.filter_span / 2 * p.sps + TM, p.adc_attack_db)
    sprintf('FS = %.1f; SR = %.1f; NSTF = %d; LS = %d; NLTF = %d; LL = %d;', p.symbol_rate * p.sps, p.symbol_rate, ...
        numel(L.stf), p.stf_len, numel(L.ltf), p.ltf_len)
    sprintf('NS = %d; ND = %d; NP = %d; PB = %d; NB = %d; TM = %d; TE = %d; LC = %.1f; QN = %d; NPRE = %d; SEGL = %d;', NS, L.n_data, ...
        L.n_pil, p.pilot_block, numel(L.pil_center), TM, TE, L.ltf_center - L.NQ, QN, L.n_pre, numel(L.ltf))
    sprintf('LTF = %s;', cvec2(L.ltf))
    sprintf('PRE = %s;', cvec2(L.pre))
    sprintf('NFFT = 512; FB = %d;', ceil((2 * p.cfo_ppm * 1e-6 * p.carrier_freq + p.v_max * p.carrier_freq / p.c_light) / p.symbol_rate * 512))
    sprintf('PIL = %s;', cvec2(L.pil))
    sprintf('IDXD = %s;', mat2str(L.idx_data(:) - L.NQ))
    sprintf('IDXP = %s;', mat2str(L.idx_pil(:) - L.NQ))
    sprintf('PC = %s;', mat2str(L.pil_center(:) - L.NQ))
    'SK = complex(zeros(NS, 1)); SK(1:NPRE) = PRE; SK(IDXP) = PIL;   % known symbols of the frame'
    'KN = false(NS, 1); KN(1:NPRE) = true; KN(IDXP) = true;'
    'if isempty(rxf)'
    sprintf(['    rxf = comm.RaisedCosineReceiveFilter(''RolloffFactor'', %.6f, ''FilterSpanInSymbols'', %d, ' ...
        '''InputSamplesPerSymbol'', SPS, ''DecimationFactor'', 1);'], p.rolloff, p.filter_span)
    'end'
    'ua = u;'
    'if ADCB > 0'
    '    % receive front end: AGC and ADCB-bit ADC on every antenna (adc_frontend.m)'
    '    ua = adc_frontend(u, ADCB, ABO, 1:QN, IS0 + (1:16*SPS), AAT);'
    'end'
    'iqa = ua;'
    'rf = rxf(ua);'
    'Ns = size(rf, 1);'
    'base = Dt * SPS + QN;'
    'sy = zeros(8, 1);'
    'y = complex(zeros(NS, NR));'
    'yw = complex(zeros(NS, NR));'
    'Wi = complex(eye(NR));'
    'Rq0 = complex(zeros(NR, NR)); rw = complex(zeros(Ns, NR)); d = 0; deq = 0; fa = 0; dst = 0; s2 = 1; Rqs = complex(eye(NV)); nq = 0;'
    'Y = complex(zeros(NS, NV)); yx = complex(zeros(NS + 2*XO, NR));'
    'if IDEAL'
    '    for k = 1:NS'
    '        y(k, :) = rf(base + (k-1)*SPS + 1, :);'
    '    end'
    'else'
    '    % Two whitenings of the antennas before synchronization: the quiet slot before the'
    '    % frame (interference + noise without our signal: suppresses an interferer that is'
    '    % already on the air, leaves our signal untouched) and the training region over'
    '    % every arrival (also suppresses an interferer that appears only with the frame,'
    '    % a reactive jammer, but nulls part of our own signal: power inversion). Each'
    '    % hypothesis runs coarse frequency and timing; the one whose timing peak stands'
    '    % out more over its search window is kept (with the equalizer, the one whose frequency'
    '    % peak stands out more: the training''s energy spreads over the line''s delays). The'
    '    % quiet slot counts from its first'
    '    % sample whose receive-filter memory lies in this frame (consecutive frames are a'
    '    % decision cycle apart in channel time).'
    '    Rq0 = complex(zeros(NR, NR));'
    '    for m = Q0:QN'
    '        v = rf(m, :).'';'
    '        Rq0 = Rq0 + v * v'';'
    '    end'
    '    Rq0 = (Rq0 + Rq0'') / (2 * (QN - Q0 + 1));'
    '    Rt0 = complex(zeros(NR, NR));'
    '    for m = base + 1 : base + TE + NPRE*SPS'
    '        v = rf(m, :).'';'
    '        Rt0 = Rt0 + v * v'';'
    '    end'
    '    Rt0 = (Rt0 + Rt0'') / (2 * (TE + NPRE*SPS));'
    '    lag = LS * SPS;'
    '    best = -1; bsel = -1; qf = 0; d = 0; fc = 0; pk = 0; m2 = 0; im = 1; met = zeros(TE + 1, 1);'
    '    W = complex(eye(NR)); Wi = complex(eye(NR)); rws = complex(zeros(Ns, NR)); hsel = 1;'
    '    Wsel = complex(eye(NR)); Lsel = ones(NR, 1); Vsel = complex(eye(NR));'
    '    % noise floor: the median eigenvalue of the quiet slot''s covariance over NTN space-time'
    '    % taps per antenna (a jammer fills fewer than half of its dimensions: within -1 to'
    '    % +4 dB of the thermal level under the 16-30 dB dispersive jammers of V12c)'
    '    Rn = st_quiet(rf, Q0, QN, NTN, HS);'
    '    s2 = max(median(real(eig(Rn))), 1e-30);'
    '    NHYP = 3;'
    '    if NT > 1'
    '        NHYP = 0;'
    '    end'
    '    for hyp = 1:NHYP'
    '        % 1: quiet slot, 2: training region, 3: power inversion local to each segment'
    '        % of the training (the interferer as it is there, when its channel changes fast)'
    '        NSEG = 1;'
    '        if hyp == 3'
    '            NSEG = NPRE / SEGL;'
    '        end'
    '        P = complex(0);'
    '        rwh = complex(zeros(Ns, NR));'
    '        rwh(:, :) = rf;'
    '        for sg = 1:NSEG'
    '            if hyp == 1'
    '                Rh = Rq0;'
    '                ma = 1; mb = Ns;'
    '            elseif hyp == 2'
    '                Rh = Rt0;'
    '                ma = 1; mb = Ns;'
    '            else'
    '                ma = base + (sg-1)*SEGL*SPS + 1; mb = min(Ns, base + sg*SEGL*SPS + TE);'
    '                Rh = complex(zeros(NR, NR));'
    '                for m = ma:mb'
    '                    v = rf(m, :).'';'
    '                    Rh = Rh + v * v'';'
    '                end'
    '                Rh = (Rh + Rh'') / (2 * (mb - ma + 1));'
    '                if sg == NSEG'
    '                    mb = Ns;'
    '                end'
    '            end'
    '            [Vh, Dh] = eig(Rh);'
    '            lh = max(real(diag(Dh)), 1e-6 * max(real(diag(Dh))) + 1e-30);'
    '            Wh = Vh * diag(1 ./ sqrt(lh)) * Vh'';'
    '            if hyp == 3 && sg == 1'
    '                ma = 1;'
    '            end'
    '            for m = ma:mb'
    '                rwh(m, :) = rf(m, :) * Wh.'';'
    '            end'
    '            if hyp == 3 && sg == 1'
    '                Wsel = Wh; Lsel = lh; Vsel = Vh;'
    '            elseif hyp < 3'
    '                Wsel = Wh; Lsel = lh; Vsel = Vh;'
    '            end'
    '        end'
    '        % joint timing and frequency: the whole known training de-modulated at every'
    '        % arrival and transformed (a grid search over the frequency range), energy'
    '        % summed over the antennas (and over the segments of hypothesis 3)'
    '        mh = zeros(TE + 1, 1); PF = zeros(NFFT, TE + 1);'
    '        NSG = 1;'
    '        if hyp == 3'
    '            NSG = ceil(NPRE / SEGL);'
    '        end'
    '        for dd = 0:TE'
    '            Pf = zeros(NFFT, 1);'
    '            for sg = 1:NSG'
    '                V = complex(zeros(NFFT, NR));'
    '                for k = 1:NPRE'
    '                    if hyp < 3 || floor((k - 1) / SEGL) + 1 == sg'
    '                        V(k, :) = rwh(base + dd + (k-1)*SPS + 1, :) * conj(PRE(k));'
    '                    end'
    '                end'
    '                X = fft(V);'
    '                for a = 1:NR'
    '                    Pf = Pf + abs(X(:, a)).^2;'
    '                end'
    '            end'
    '            for bb = FB + 2 : NFFT - FB'
    '                Pf(bb) = 0;'
    '            end'
    '            PF(:, dd + 1) = Pf;'
    '            mh(dd + 1) = max(Pf);'
    '        end'
    '        if NE > 1'
    '            % the delay line: the frequency at which the training''s energy summed over every'
    '            % delay peaks (each path''s periodogram peaks at the offset; a path one symbol off'
    '            % an arrival peaks 1/(LL T) away on the chirp of the long training), the arrival'
    '            % the largest energy at that frequency'
    '            Ps = sum(PF, 2);'
    '            [~, bb] = max(Ps);'
    '            mh(:) = PF(bb, :).'';'
    '            [pkh, imh] = max(mh);'
    '            p0 = Ps(bb); pmn = Ps(mod(bb - 2, NFFT) + 1); ppl = Ps(mod(bb, NFFT) + 1);'
    '            qf = Ps(bb) / max(mean(Ps([1:FB+1, NFFT-FB+1:NFFT])), 1e-30);'
    '        else'
    '            [pkh, imh] = max(mh);'
    '            [~, bb] = max(PF(:, imh));'
    '            p0 = PF(bb, imh); pmn = PF(mod(bb - 2, NFFT) + 1, imh); ppl = PF(mod(bb, NFFT) + 1, imh);'
    '        end'
    '        kb = bb - 1;'
    '        if kb >= NFFT / 2'
    '            kb = kb - NFFT;'
    '        end'
    '        den = pmn - 2*p0 + ppl; de = 0;'
    '        if den < 0'
    '            de = 0.5 * (pmn - ppl) / den;'
    '        end'
    '        fch = (kb + de) * SR / NFFT;'
    '        Wh = Wsel; lh = Lsel; Vh = Vsel;'
    '        qh = pkh / max(mean(mh), 1e-30);'
    '        if NE == 1'
    '            qf = qh;'
    '        end'
    '        if qf > bsel'
    '            bsel = qf; best = qh; d = imh - 1; im = imh; fc = fch; pk = pkh; met = mh;'
    '            W = Wh; Wi = Vh * diag(sqrt(lh)) * Vh''; rws(:, :) = rwh; hsel = hyp;'
    '        end'
    '    end'
    '    if NT > 1'
    '        % space-time taps: a dispersive jammer fills every antenna dimension, so a spatial'
    '        % whitening leaves it on the training. Frequency first (Morelli & D''Amico, eq. 24'
    '        % and 31; coarse then fine, Bertolucci et al., Fig. 3): at every arrival the'
    '        % training''s NTS-tap snapshots whitened by their own covariance loaded with the noise'
    '        % floor and correlated with the training on the FFT grid, the coherence'
    '        % a = g''(R + s2 I)^-1 g / K^2 (JASS, Marti et al. 2024, eq. 10 and Alg. 1: with the'
    '        % training projected out of R the statistic is a / (1 - a), the same maximum;'
    '        % loading in place of the projection, Besson 2021, eq. 81). The space-time taps sit'
    '        % on the arrival of the largest a (the placement whose filter reaches the most SINR);'
    '        % the arrival itself is the peak of the spatial coherence at that frequency within'
    '        % SPS + 2 samples of it (JASS''s timing statistic on the antennas)'
    '        [dst, fc] = st_sync(rf, base, TM, PRE, NTS, HS, SPS, NFFT, FB, SR, s2);'
    '        for dd = 0:TM'
    '            met(dd + 1) = st_coh(rf, base + dd, fc, PRE, 1, HS, SPS, SR, s2);'
    '        end'
    '        im = max(1, dst - SPS - 1); pk = met(im);'
    '        for dd = max(0, dst - SPS - 2) : min(TM, dst + SPS + 2)'
    '            if met(dd + 1) > pk'
    '                pk = met(dd + 1); im = dd + 1;'
    '            end'
    '        end'
    '        d = im - 1; best = pk / max(mean(met), 1e-30);'
    '    end'
    '    for dd = 0:TE'
    '        if abs(dd - d) > SPS && met(dd + 1) > m2'
    '            m2 = met(dd + 1);'
    '        end'
    '    end'
    '    % sync coherence of the frame (the space-time statistic at the arrival its taps sit on'
    '    % and the found frequency); below TAU the training was not found: the sync-failure'
    '    % flag, reported, not an erasure'
    '    dsy = d;'
    '    if NT > 1'
    '        dsy = dst;'
    '    end'
    '    sy(6) = st_coh(rf, base + dsy, fc, PRE, NTS, HS, SPS, SR, s2);'
    '    sy(7) = double(sy(6) < TAU);'
    '    ph = exp(-1j*2*pi*fc*(0:Ns-1).''/FS);'
    '    for a = 1:NR'
    '        rf(:, a) = rf(:, a) .* ph;'
    '    end'
    '    rw = complex(zeros(Ns, NR));'
    '    if hsel == 3'
    '        rw(:, :) = rws;'
    '        for a = 1:NR'
    '            rw(:, a) = rw(:, a) .* ph;'
    '        end'
    '    else'
    '        rw(:, :) = rf * W.'';'
    '    end'
    '    for k = 1:NS'
    '        y(k, :) = rf(base + d + (k-1)*SPS + 1, :);'
    '        yw(k, :) = rw(base + d + (k-1)*SPS + 1, :);'
    '    end'
    '    % fine frequency: lag of one long sequence, chosen whitened domain'
    '    Q = complex(0);'
    '    for k = NSTF + 1 : NSTF + LL'
    '        Q = Q + conj(yw(k, :)) * yw(k + LL, :).'';'
    '    end'
    '    ff = angle(Q) / (2*pi*LL/SR);'
    '    if NT > 1'
    '        % space-time taps: the antennas alone do not whiten a dispersive interferer, so'
    '        % the 16 lag pairs err by kHz; the pilots and the decisions refine the coarse'
    '        % frequency instead'
    '        ff = 0;'
    '    end'
    '    ph2 = exp(-1j*2*pi*ff*(0:NS-1).''/SR);'
    '    for a = 1:NR'
    '        y(:, a) = y(:, a) .* ph2;'
    '        yw(:, a) = yw(:, a) .* ph2;'
    '    end'
    '    fa = ff;'
    '    fr = 0;'
    '    if im > 1 && im < TE + 1'
    '        den = met(im-1) - 2*met(im) + met(im+1);'
    '        if den < 0'
    '            fr = 0.5 * (met(im-1) - met(im+1)) / den;'
    '        end'
    '    end'
    '    sy(1:5) = [d; fc + ff; best; m2 / max(pk, 1e-30); fr];'
    '    deq = d;'
    '    if NE > 1'
    '        % the equalizer''s lags (RP symbols before its timing, RQ after) moved by whole symbols'
    '        % from the arrival (its sampling phase kept) to where they hold the most of the'
    '        % training''s energy, unless that is within 1% of their energy at the arrival'
    '        Ew = zeros(TE + 1, 1);'
    '        for dq = 0:TE'
    '            for t = max(0, dq - RP*SPS) : min(TE, dq + RQ*SPS)'
    '                Ew(dq + 1) = Ew(dq + 1) + met(t + 1);'
    '            end'
    '        end'
    '        jb = 0; eb = Ew(d + 1);'
    '        for j = -RQ:RP'
    '            dq = d + j*SPS;'
    '            if dq >= 0 && dq <= TE && Ew(dq + 1) > eb'
    '                eb = Ew(dq + 1); jb = j;'
    '            end'
    '        end'
    '        if Ew(d + 1) < 0.99 * eb'
    '            deq = d + jb*SPS;'
    '        end'
    '    end'
    'end'
    'z = complex(zeros(ND, 1));'
    'NBo = floor(ND / 32);'
    'Hq = complex(zeros(NR, NBo));'
    'Rq = complex(zeros(NR, NR));'
    'if IDEAL'
    '    % known symbols: LS channel per window from the other symbols, residual covariance'
    '    sd = pskmod(txbits, 4, pi/4, ''gray'', ''InputType'', ''bit'');'
    '    nb = max(1, floor(ND / B));'
    '    for bi = 1:nb'
    '        i0 = (bi-1)*B + 1; i1 = bi*B; if bi == nb, i1 = ND; end; n = i1 - i0 + 1;'
    '        hs = complex(zeros(NR, 1)); es = 0;'
    '        for m = i0:i1'
    '            hs = hs + y(IDXD(m), :).'' * conj(sd(m));'
    '            es = es + abs(sd(m))^2;'
    '        end'
    '        h = hs / max(es, 1e-12);'
    '        Ri = complex(eye(NR));'
    '        if MODE == 2'
    '            R = complex(zeros(NR, NR));'
    '            for m = i0:i1'
    '                e = y(IDXD(m), :).'' - h * sd(m);'
    '                R = R + e * e'';'
    '            end'
    '            R = R / n;'
    '            R = R + (1e-3 * real(trace(R)) / NR + 1e-12) * eye(NR);'
    '            Ri = inv(R);'
    '        end'
    '        for m = i0:i1'
    '            v = y(IDXD(m), :).'';'
    '            hm = (hs - v * conj(sd(m))) / max(es - abs(sd(m))^2, 1e-12);'
    '            w = Ri * hm;'
    '            z(m) = w'' * v;'
    '        end'
    '    end'
    '    for bo = 1:NBo'
    '        hb = complex(zeros(NR, 1)); eb = 0;'
    '        for m = (bo-1)*32 + 1 : bo*32'
    '            hb = hb + y(IDXD(m), :).'' * conj(sd(m));'
    '            eb = eb + abs(sd(m))^2;'
    '        end'
    '        hb = hb / max(eb, 1e-12);'
    '        Hq(:, bo) = hb;'
    '        for m = (bo-1)*32 + 1 : bo*32'
    '            e = y(IDXD(m), :).'' - hb * sd(m);'
    '            Rq = Rq + e * e'';'
    '        end'
    '    end'
    '    Rq = Rq / (NBo * 32);'
    'else'
    '    % channel at the long training and at every pilot block, on the whitened samples'
    '    % (an interferer suppressed by the whitening does not bias it)'
    '    Hp = complex(zeros(NR, NB + 1)); tp = zeros(NB + 1, 1);'
    '    for k = 1:NLTF'
    '        Hp(:, 1) = Hp(:, 1) + yw(NSTF + k, :).'' * conj(LTF(k));'
    '    end'
    '    Hp(:, 1) = Hp(:, 1) / NLTF; tp(1) = LC;'
    '    for b = 1:NB'
    '        for j = 1:PB'
    '            q = (b-1)*PB + j;'
    '            Hp(:, b+1) = Hp(:, b+1) + yw(IDXP(q), :).'' * conj(PIL(q));'
    '        end'
    '        Hp(:, b+1) = Hp(:, b+1) / PB; tp(b+1) = PC(b);'
    '    end'
    '    % MMSE with space-time taps: every symbol''s NT samples HS apart around it on every'
    '    % antenna, T0 of them before it (NV = NR NT degrees of freedom), placed by the sync'
    '    if NT > 1'
    '        Y = st_snap(rf, base + dst, fa, NS, NT, HS, SPS, FS);'
    '    end'
    '    % residual frequency from the phase progression over the pilot blocks (the long'
    '    % baseline across the frame), removed from the samples and the estimates (FIT passes;'
    '    % with space-time taps the first pass finds it, below)'
    '    for it = 1:FIT'
    '        if NT == 1'
    '            Y(:, :) = y;'
    '        end'
    '        if MODE == 2'
    '            % MMSE: the phase step between consecutive pilot blocks weighed by the inverse'
    '            % covariance of the samples between them (the interferer as it is there, not'
    '            % as the training''s whitening saw it)'
    '            Hr = complex(zeros(NV, NB));'
    '            for b = 1:NB'
    '                for jj = 1:PB'
    '                    q = (b-1)*PB + jj;'
    '                    Hr(:, b) = Hr(:, b) + Y(IDXP(q), :).'' * conj(PIL(q));'
    '                end'
    '            end'
    '            G = complex(0);'
    '            for b = 1:NB-1'
    '                kA = max(1, round(PC(b)) - HWD); kB = min(NS, round(PC(b+1)) + HWD);'
    '                Rl = complex(zeros(NV, NV));'
    '                for k = kA:kB'
    '                    vv = Y(k, :).'';'
    '                    Rl = Rl + vv * vv'';'
    '                end'
    '                Rl = Rl / (kB - kA + 1);'
    '                Rl = Rl + (1e-3 * real(trace(Rl)) / NV + 1e-12) * eye(NV);'
    '                G = G + Hr(:, b+1)'' * (Rl \ Hr(:, b));'
    '            end'
    '        else'
    '            G = complex(0);'
    '            for b = 2:NB'
    '                G = G + Hp(:, b+1)'' * Hp(:, b);'
    '            end'
    '        end'
    '        df = -angle(G) / (2*pi*(PC(2) - PC(1))/SR);'
    '        sy(2) = sy(2) + df;'
    '        ph3 = exp(-1j*2*pi*df*(0:NS-1).''/SR);'
    '        for a = 1:NR'
    '            y(:, a) = y(:, a) .* ph3;'
    '            yw(:, a) = yw(:, a) .* ph3;'
    '        end'
    '        fa = fa + df;'
    '        for b = 1:NB+1'
    '            Hp(:, b) = Hp(:, b) * exp(-1j*2*pi*df*(tp(b) - 1)/SR);'
    '        end'
    '    end'
    '    Hs = Hp;'
    '    for b = 2:NB+1'
    '        if b == 2'
    '            Hs(:, b) = (2*Hp(:, b) + Hp(:, b+1)) / 3;'
    '        elseif b == NB+1'
    '            Hs(:, b) = (Hp(:, b-1) + 2*Hp(:, b)) / 3;'
    '        else'
    '            Hs(:, b) = (Hp(:, b-1) + 2*Hp(:, b) + Hp(:, b+1)) / 4;'
    '        end'
    '    end'
    '    Hkw = complex(zeros(NR, NS));'
    '    j = 1;'
    '    for k = 1:NS'
    '        if k <= tp(1)'
    '            Hkw(:, k) = Hs(:, 1);'
    '        elseif k >= tp(NB+1)'
    '            Hkw(:, k) = Hs(:, NB+1);'
    '        else'
    '            while k >= tp(j+1)'
    '                j = j + 1;'
    '            end'
    '            g = (k - tp(j)) / (tp(j+1) - tp(j));'
    '            Hkw(:, k) = (1 - g) * Hs(:, j) + g * Hs(:, j+1);'
    '        end'
    '    end'
    '    Hk = Wi * Hkw;'
    '    if NT == 1'
    '        Y(:, :) = y;'
    '    end'
    '    % first pass. MRC: the pilot channel of the antennas. MMSE: per window, whitening'
    '    % with the covariance of the window and its neighbourhood (every sample: the'
    '    % interferer as it is there), the nearest known symbols estimate the channel in'
    '    % the same whitened domain, and MRC there (= MVDR); the null follows an interferer'
    '    % channel that changes within the frame'
    '    nb = max(1, floor(ND / B));'
    '    za = complex(zeros(ND, 1));'
    '    if NE > 1'
    '        % equalizer, first pass (eq_train): the channel of every lag by joint LS on the'
    '        % training, its phase at every pilot block from the known symbols'' share of the'
    '        % block''s samples (on the whitened samples: an interferer the whitening suppresses'
    '        % does not move it); the residual frequency from the slope of those phases over the'
    '        % frame (the pilots'' phase steps on one tap at the arrival err by kHz on a channel'
    '        % spread over the line), twice; then MRC over the antennas and the lags with every'
    '        % antenna''s gain followed over the frame, and the linear MMSE equalizer'
    '        yx = complex(zeros(NS + 2*XO, NR)); ywx = complex(zeros(NS + 2*XO, NR));'
    '        for k = 1 - XO : NS + XO'
    '            tk = (k-1)*SPS;'
    '            if base + deq + tk >= 0 && base + deq + tk < Ns'
    '                phk = exp(-1j*2*pi*fa*tk/FS);'
    '                yx(k + XO, :) = rf(base + deq + tk + 1, :) * phk;'
    '                ywx(k + XO, :) = rw(base + deq + tk + 1, :) * phk;'
    '            end'
    '        end'
    '        tq = zeros(NB + 1, 1); pq = zeros(NB + 1, 1);'
    '        for itf = 1:3'
    '            [~, ~, pq, tq] = eq_train(ywx, PRE, SK, KN, IDXP, PC, NRK, RP, RQ, XO, PB);'
    '            if itf < 3'
    '                tm = mean(tq); pm = mean(pq); sxx = 0; sxy = 0;'
    '                for b = 1:NB + 1'
    '                    sxx = sxx + (tq(b) - tm)^2; sxy = sxy + (tq(b) - tm) * (pq(b) - pm);'
    '                end'
    '                bf = sxy / max(sxx, 1e-30);'
    '                for k = 1 - XO : NS + XO'
    '                    yx(k + XO, :) = yx(k + XO, :) * exp(-1j * bf * (k - 1));'
    '                    ywx(k + XO, :) = ywx(k + XO, :) * exp(-1j * bf * (k - 1));'
    '                end'
    '                ph3 = exp(-1j * bf * (0:NS-1).'');'
    '                for a = 1:NR'
    '                    y(:, a) = y(:, a) .* ph3;'
    '                    yw(:, a) = yw(:, a) .* ph3;'
    '                end'
    '                fa = fa + bf * SR / (2*pi); sy(2) = sy(2) + bf * SR / (2*pi);'
    '            end'
    '        end'
    '        [Gt, s2] = eq_train(yx, PRE, SK, KN, IDXP, PC, NRK, RP, RQ, XO, PB);'
    '        % every antenna''s gain at every pilot block against the training''s channel (the'
    '        % fading over the frame: at 358 Hz the channel decorrelates to 0.6 over it), from'
    '        % the known symbols'' share of the block''s samples; a block whose fit leaves more'
    '        % than 4 times the median residual (a burst) keeps the common phase; smoothed'
    '        % [1 2 1]/4 over the blocks and interpolated'
    '        ga = complex(ones(NR, NB + 1)); rb = zeros(NB, 1);'
    '        for b = 1:NB'
    '            num = complex(zeros(NR, 1)); den = zeros(NR, 1);'
    '            for n = IDXP((b-1)*PB + 1) - RP : IDXP(b*PB) + RQ'
    '                kn = eq_known(Gt, SK, KN, n, RP);'
    '                num = num + conj(kn) .* yx(n + XO, :).''; den = den + abs(kn).^2;'
    '            end'
    '            ga(:, b + 1) = num ./ max(den, 1e-30);'
    '            for n = IDXP((b-1)*PB + 1) - RP : IDXP(b*PB) + RQ'
    '                ev = yx(n + XO, :).'' - ga(:, b + 1) .* eq_known(Gt, SK, KN, n, RP);'
    '                rb(b) = rb(b) + real(ev'' * ev);'
    '            end'
    '        end'
    '        mr = median(rb);'
    '        for b = 1:NB'
    '            if rb(b) > 4 * mr'
    '                ga(:, b + 1) = complex(ones(NR, 1)) * exp(1j * pq(b + 1));'
    '            end'
    '        end'
    '        gs = ga;'
    '        for b = 2:NB + 1'
    '            if b == 2'
    '                gs(:, b) = (2*ga(:, b) + ga(:, b+1)) / 3;'
    '            elseif b == NB + 1'
    '                gs(:, b) = (ga(:, b-1) + 2*ga(:, b)) / 3;'
    '            else'
    '                gs(:, b) = (ga(:, b-1) + 2*ga(:, b) + ga(:, b+1)) / 4;'
    '            end'
    '        end'
    '        rr = complex(zeros(NS + 2*E0, 1));'
    '        j = 1;'
    '        for k = 1 - E0 : NS + E0'
    '            kc = min(max(k, 1), NS); gk = gs(:, 1);'
    '            if kc >= tq(NB + 1)'
    '                gk = gs(:, NB + 1);'
    '            elseif kc > tq(1)'
    '                while kc >= tq(j + 1)'
    '                    j = j + 1;'
    '                end'
    '                gi = (kc - tq(j)) / (tq(j + 1) - tq(j));'
    '                gk = (1 - gi) * gs(:, j) + gi * gs(:, j + 1);'
    '            end'
    '            for l = 1:NRK'
    '                rr(k + E0) = rr(k + E0) + (gk .* Gt(:, l))'' * yx(k + l - 1 - RP + XO, :).'';'
    '            end'
    '        end'
    '        fe = le_taps(Gt, s2, NE);'
    '        for m = 1:ND'
    '            z(m) = fe'' * rr(IDXD(m) : IDXD(m) + NE - 1);'
    '        end'
    '    else'
    '        if NT > 1'
    '            % space-time, first pass from the training (Marti et al. 2023, Sec. V-C: the'
    '            % frame''s known symbols start it, no window''s weights from an earlier one''s):'
    '            % the channel of our signal from the training, the interference + noise'
    '            % covariance free of our signal (Besson 2021, eq. 22-23: our signal in it costs'
    '            % a penalty that grows with its SNR) and loaded with the noise floor (Gershman'
    '            % et al. 1996, Sec. 3.2; Besson 2021, eq. 68 and 80), window by window from the'
    '            % residuals of the rows whose symbols are known or decided; the phase of every'
    '            % window from its decisions and pilots, the residual frequency from their slope'
    '            % over the frame. Twice, the second at the frequency of the first.'
    '            Rqs = st_quiet(rf, Q0, QN, NT, HS); nq = QN - Q0 - 2*T0*HS + 1;'
    '            for r = 1:2'
    '                [z, bf] = st_first(Y, Rqs, nq, SK, KN, IDXD, MH, BS, B, NPRE, s2);'
    '                df = bf * SR / (2*pi);'
    '                fa = fa + df; sy(2) = sy(2) + df;'
    '                Y = st_snap(rf, base + dst, fa, NS, NT, HS, SPS, FS);'
    '                ph3 = exp(-1j*2*pi*df*(0:NS-1).''/SR);'
    '                for a = 1:NR'
    '                    y(:, a) = y(:, a) .* ph3;'
    '                    yw(:, a) = yw(:, a) .* ph3;'
    '                end'
    '            end'
    '        end'
    '        % the antennas alone: the receiver of the flat channel, and with space-time taps the'
    '        % alternative the frame may keep (below)'
    '        nba = max(1, floor(ND / BA));'
    '        for bi = 1:nba'
    '            i0 = (bi-1)*BA + 1; i1 = bi*BA; if bi == nba, i1 = ND; end'
    '            if MODE == 2'
    '                kA = max(1, IDXD(i0) - HW); kB = min(NS, IDXD(i1) + HW);'
    '                R = complex(zeros(NR, NR));'
    '                for k = kA:kB'
    '                    v = y(k, :).'';'
    '                    R = R + v * v'';'
    '                end'
    '                R = (R + R'') / (2 * (kB - kA + 1));'
    '                [V, D] = eig(R);'
    '                lr = max(real(diag(D)), 1e-6 * max(real(diag(D))) + 1e-30);'
    '                Wl = V * diag(1 ./ sqrt(lr)) * V'';'
    '                hl = complex(zeros(NR, 1)); nk = 0;'
    '                for k = 1:NLTF'
    '                    kk = NSTF + k;'
    '                    if kk >= kA && kk <= kB'
    '                        hl = hl + Wl * y(kk, :).'' * conj(LTF(k)); nk = nk + 1;'
    '                    end'
    '                end'
    '                for qq = 1:NP'
    '                    kk = IDXP(qq);'
    '                    if kk >= kA && kk <= kB'
    '                        hl = hl + Wl * y(kk, :).'' * conj(PIL(qq)); nk = nk + 1;'
    '                    end'
    '                end'
    '                hl = hl / max(nk, 1);'
    '                g = real(hl'' * hl);'
    '                for m = i0:i1'
    '                    if g > 1e-12'
    '                        za(m) = (hl'' * (Wl * y(IDXD(m), :).'')) / g;'
    '                    end'
    '                end'
    '            else'
    '                for m = i0:i1'
    '                    k = IDXD(m);'
    '                    h = Hk(:, k);'
    '                    g = real(h'' * h);'
    '                    if g > 1e-12'
    '                        za(m) = (h'' * y(k, :).'') / g;'
    '                    end'
    '                end'
    '            end'
    '        end'
    '        if NT == 1'
    '            z(:) = za;'
    '        end'
    '    end'
    '    % second pass, decision directed: the first-pass decisions act as known symbols for'
    '    % the channel of every window'
    '    if NE > 1'
    '        sh = (sign(real(z)) + 1j * sign(imag(z))) / sqrt(2);'
    '        sh(real(sh) == 0) = sh(real(sh) == 0) + 1 / sqrt(2);'
    '        sh(imag(sh) == 0) = sh(imag(sh) == 0) + 1j / sqrt(2);'
    '        for it = 1:DDI'
    '        if it > 1'
    '            sh = (sign(real(z)) + 1j * sign(imag(z))) / sqrt(2);'
    '        end'
    '        % equalizer: per window and its neighbourhood, every known or decided symbol of the'
    '        % frame gives the channel of every lag (joint LS, the lags weaker than their'
    '        % estimation noise shrunk) and the white noise level of the residual; MRC over the'
    '        % antennas and the lags, then the linear MMSE equalizer of that channel'
    '        sf = complex(zeros(NS, 1));'
    '        sf(1:NPRE) = PRE;'
    '        sf(IDXP) = PIL;'
    '        sf(IDXD) = sh;'
    '        ep = 0;'
    '        for bi = 1:nb'
    '            i0 = (bi-1)*B + 1; i1 = bi*B; if bi == nb, i1 = ND; end'
    '            kA = max(1, IDXD(i0) - HWE); kB = min(NS, IDXD(i1) + HWE);'
    '            Al = complex(zeros(NRK, NRK)); Cl = complex(zeros(NR, NRK));'
    '            for k = kA:kB'
    '                sv = complex(zeros(NRK, 1));'
    '                for l = 1:NRK'
    '                    kl = k - (l - 1 - RP);'
    '                    if kl >= 1 && kl <= NS'
    '                        sv(l) = sf(kl);'
    '                    end'
    '                end'
    '                Al = Al + sv * sv'';'
    '                Cl = Cl + yx(k + XO, :).'' * sv'';'
    '            end'
    '            Al = Al + 1e-6 * real(trace(Al)) / NRK * eye(NRK);'
    '            Ai = inv(Al);'
    '            Gw = Cl * Ai;'
    '            e2 = 0;'
    '            for k = kA:kB'
    '                sv = complex(zeros(NRK, 1));'
    '                for l = 1:NRK'
    '                    kl = k - (l - 1 - RP);'
    '                    if kl >= 1 && kl <= NS'
    '                        sv(l) = sf(kl);'
    '                    end'
    '                end'
    '                ev = yx(k + XO, :).'' - Gw * sv;'
    '                e2 = e2 + real(ev'' * ev);'
    '            end'
    '            s2 = max(e2 / (NR * max(kB - kA + 1 - NRK, 1)), 1e-30);'
    '            for l = 1:NRK'
    '                if l ~= RP + 1'
    '                    gl = real(Gw(:, l)'' * Gw(:, l));'
    '                    Gw(:, l) = Gw(:, l) * max(0, 1 - NR * s2 * real(Ai(l, l)) / max(gl, 1e-30));'
    '                end'
    '            end'
    '            fe = le_taps(Gw, s2, NE);'
    '            % the window''s symbols and the pilots after the previous window''s last data'
    '            % symbol up to its own; the MRC output once per symbol, E0 symbols beyond them'
    '            lo = 0; hi = IDXD(i1);'
    '            if bi > 1'
    '                lo = IDXD(i0 - 1);'
    '            end'
    '            if bi == nb'
    '                hi = NS;'
    '            end'
    '            ra = lo + 1 - E0;'
    '            rm = complex(zeros(hi + E0 - ra + 1, 1));'
    '            for k = ra : hi + E0'
    '                for l = 1:NRK'
    '                    rm(k - ra + 1) = rm(k - ra + 1) + Gw(:, l)'' * yx(k + l - 1 - RP + XO, :).'';'
    '                end'
    '            end'
    '            for m = i0:i1'
    '                z(m) = fe'' * rm(IDXD(m) - E0 - ra + 1 : IDXD(m) + E0 - ra + 1);'
    '            end'
    '            for q = 1:numel(IDXP)'
    '                if IDXP(q) > lo && IDXP(q) <= hi'
    '                    ep = ep + abs(fe'' * rm(IDXP(q) - E0 - ra + 1 : IDXP(q) + E0 - ra + 1) - PIL(q))^2;'
    '                end'
    '            end'
    '        end'
    '        sy(8) = ep / numel(IDXP);'
    '        end'
    '    else'
    '        if NT > 1'
    '            % space-time: DDI passes over the whole frame (Marti et al. 2023, eq. 15: the'
    '            % channel by LS on the frame''s known and decided symbols), the covariance of the'
    '            % residuals around every window, loaded; the last pass excludes the rows that'
    '            % carry a pilot from its weights and returns the pilots'' error under them. The'
    '            % frame keeps the space-time or the antennas-alone output, whichever reproduces'
    '            % its pilots better under weights whose last pass excludes them: on a nearly'
    '            % flat interferer the space-time degrees of freedom cost more estimation noise'
    '            % than they null'
    '            [z, est] = st_dd(Y, z, SK, IDXD, IDXP, PIL, MH, B, B / 2, s2, DDI);'
    '            za = dd_mvdr(y, za, IDXD, BA, true, DDI);'
    '            ea = pilot_mse(y, za, IDXD, IDXP, PIL, BA);'
    '            if ea < est'
    '                z(:) = za;'
    '            end'
    '            sy(8) = min(ea, est);'
    '        else'
    '            z = dd_mvdr(Y, z, IDXD, B, MODE == 2, DDI);'
    '            sy(8) = pilot_mse(Y, z, IDXD, IDXP, PIL, B);'
    '        end'
    '    end'
    '    % per-32-symbol antenna channel and frame residual covariance from the decisions'
    '    sh = (sign(real(z)) + 1j * sign(imag(z))) / sqrt(2);'
    '    Rq = complex(zeros(NR, NR));'
    '    for bo = 1:NBo'
    '        hb = complex(zeros(NR, 1));'
    '        for m = (bo-1)*32 + 1 : bo*32'
    '            hb = hb + y(IDXD(m), :).'' * conj(sh(m));'
    '        end'
    '        hb = hb / 32;'
    '        Hq(:, bo) = hb;'
    '        for m = (bo-1)*32 + 1 : bo*32'
    '            e = y(IDXD(m), :).'' - hb * sh(m);'
    '            Rq = Rq + e * e'';'
    '        end'
    '    end'
    '    Rq = Rq / (NBo * 32);'
    'end'
    'bits = pskdemod(z, 4, pi/4, ''gray'', ''OutputType'', ''bit'');'
    'end'
    ''
    'function R = st_quiet(rf, Q0, QN, NT, HS)'
    '% Covariance of the quiet slot''s space-time snapshots (NT taps HS apart on every antenna)'
    '% at every sample whose taps lie between Q0 and QN.'
    'NR = size(rf, 2); T0 = (NT - 1) / 2; NV = NR * NT;'
    'R = complex(zeros(NV, NV)); v = complex(zeros(NV, 1)); n = 0;'
    'for m = Q0 + T0*HS : QN - T0*HS'
    '    for l = 1:NT'
    '        v((l-1)*NR + (1:NR)) = rf(m + (l-1-T0)*HS, :).'';'
    '    end'
    '    R = R + v * v''; n = n + 1;'
    'end'
    'R = (R + R'') / (2 * max(n, 1));'
    'end'
    ''
    'function Y = st_snap(rf, b0, f, NS, NT, HS, SPS, FS)'
    '% Space-time snapshots: per symbol a row of the NT samples HS apart around it on every'
    '% antenna (symbol 1 at sample b0 + 1), frequency f removed.'
    'NR = size(rf, 2); T0 = (NT - 1) / 2;'
    'Y = complex(zeros(NS, NR * NT));'
    'for k = 1:NS'
    '    for l = 1:NT'
    '        tk = (k-1)*SPS + (l-1-T0)*HS;'
    '        Y(k, (l-1)*NR + (1:NR)) = rf(b0 + tk + 1, :) * exp(-1j*2*pi*f*tk/FS);'
    '    end'
    'end'
    'end'
    ''
    'function a = st_coh(rf, b0, f, PRE, NT, HS, SPS, SR, s2)'
    '% Coherence of the training with the space-time snapshots (NT taps; 1: the antennas) at'
    '% arrival b0 and frequency f: a = g''(R + s2 I)^-1 g / K^2, g their correlation with the'
    '% training, R their covariance (JASS, Marti et al. 2024, eq. 10, the loaded inverse in'
    '% place of the projection). Near 1 for the training alone, about NV / K without it.'
    'K = numel(PRE); Z = st_snap(rf, b0, 0, K, NT, HS, SPS, SR * SPS); NV = size(Z, 2);'
    'g = complex(zeros(NV, 1));'
    'for k = 1:K'
    '    g = g + Z(k, :).'' * (conj(PRE(k)) * exp(-1j*2*pi*f*(k-1)/SR));'
    'end'
    'R = st_load(Z.'' * conj(Z) / K, s2);'
    'a = real(g'' * (R \ g)) / K^2;'
    'end'
    ''
    'function [dst, fc] = st_sync(rf, base, TM, PRE, NT, HS, SPS, NFFT, FB, SR, s2)'
    '% Arrival and frequency of the largest space-time coherence (st_coh) over the arrivals'
    '% 0..TM and the FFT frequency grid within +-FB bins (zero padded to NFFT, Morelli &'
    '% D''Amico, eq. 24), the frequency refined by a parabola through the peak (their eq. 31).'
    '% Per arrival one Cholesky factor whitens the snapshots: a(f) = ||FFT of the whitened'
    '% snapshots times the conjugate training||^2 / K^2.'
    'K = numel(PRE); NV = size(rf, 2) * NT;'
    'PF = zeros(NFFT, TM + 1); V = complex(zeros(NFFT, NV));'
    'for dd = 0:TM'
    '    Z = st_snap(rf, base + dd, 0, K, NT, HS, SPS, SR * SPS);'
    '    Lc = chol(st_load(Z.'' * conj(Z) / K, s2), ''lower'');'
    '    Zw = (Lc \ Z.'').'';'
    '    for k = 1:K'
    '        V(k, :) = Zw(k, :) * conj(PRE(k));'
    '    end'
    '    X = fft(V);'
    '    Pf = sum(real(X .* conj(X)), 2) / K^2;'
    '    for bb = FB + 2 : NFFT - FB'
    '        Pf(bb) = 0;'
    '    end'
    '    PF(:, dd + 1) = Pf;'
    'end'
    '[~, ix] = max(PF(:));'
    'bb = mod(ix - 1, NFFT) + 1; dst = floor((ix - 1) / NFFT);'
    'p0 = PF(bb, dst + 1); pmn = PF(mod(bb - 2, NFFT) + 1, dst + 1); ppl = PF(mod(bb, NFFT) + 1, dst + 1);'
    'den = pmn - 2*p0 + ppl; de = 0;'
    'if den < 0'
    '    de = 0.5 * (pmn - ppl) / den;'
    'end'
    'kb = bb - 1;'
    'if kb >= NFFT / 2'
    '    kb = kb - NFFT;'
    'end'
    'fc = (kb + de) * SR / NFFT;'
    'end'
    ''
    'function R = st_load(R, s2)'
    '% The snapshots'' covariance R made Hermitian and loaded with the noise floor s2; a floor'
    '% that does not reach 1e-9 of the mean eigenvalue (a noise-free or empty quiet slot)'
    '% is replaced by 1e-3 of it, so R stays positive definite for the Cholesky factor.'
    'NV = size(R, 1); R = (R + R'') / 2; t = real(trace(R)) / NV; mu = s2;'
    'if ~(mu > 1e-9 * t)'
    '    mu = 1e-3 * t + 1e-12;'
    'end'
    'R = R + mu * eye(NV);'
    'end'
    ''
    'function s = st_reg(sv, k, MH)'
    '% Symbols k-MH..k+MH of sv (0 outside the frame): the regressors of snapshot k.'
    's = complex(zeros(2*MH + 1, 1));'
    'for m = -MH:MH'
    '    if k + m >= 1 && k + m <= numel(sv)'
    '        s(m + MH + 1) = sv(k + m);'
    '    end'
    'end'
    'end'
    ''
    'function [z, bf] = st_first(Y, Rq, nq, SK, KN, IDXD, MH, BS, HWS, NPRE, s2)'
    '% First space-time pass. Channel of our signal from the training: LS of every snapshot'
    '% on the symbols that reach it (NV x (2 MH + 1)). Per window of BS data symbols, MVDR'
    '% weights (R + ISI + s2 I)^-1 h0: R the covariance of the residuals (snapshot less our'
    '% signal at its phase) of the rows within HWS of the window whose symbols are all known'
    '% or decided, with the training and quiet-slot residuals (Rq over nq rows) while fewer'
    '% than twice the dimensions; ISI the other symbols'' channels. The window''s phase from its'
    '% pilots and decisions (decided at the previous window''s phase); bf [rad/symbol]: the'
    '% slope of the windows'' phases over the frame, through the training.'
    'NS = size(Y, 1); NV = size(Y, 2); ND = numel(IDXD); NM = 2*MH + 1;'
    'A = complex(zeros(NM, NM)); C = complex(zeros(NV, NM));'
    'for k = MH + 1 : NPRE - MH'
    '    sv = st_reg(SK, k, MH);'
    '    A = A + sv * sv''; C = C + Y(k, :).'' * sv'';'
    'end'
    'H = C / A;'
    'Rt = Rq * nq; nt = nq;'
    'for k = MH + 1 : NPRE - MH'
    '    e = Y(k, :).'' - H * st_reg(SK, k, MH);'
    '    Rt = Rt + e * e''; nt = nt + 1;'
    'end'
    'h0 = H(:, MH + 1); Ri = complex(s2 * eye(NV));'
    'for m = 1:NM'
    '    if m ~= MH + 1'
    '        Ri = Ri + H(:, m) * H(:, m)'';'
    '    end'
    'end'
    'sq = SK; kd = KN; ph = complex(ones(NS, 1)); g = complex(1);'
    'nb = max(1, floor(ND / BS)); z = complex(zeros(ND, 1)); pw = zeros(nb, 1); kw = zeros(nb, 1);'
    'for bi = 1:nb'
    '    i0 = (bi-1)*BS + 1; i1 = bi*BS; if bi == nb, i1 = ND; end'
    '    kA = max(1, IDXD(i0) - HWS); kB = min(NS, IDXD(i1) + HWS);'
    '    R = complex(zeros(NV, NV)); n = 0;'
    '    for k = kA:kB'
    '        ok = true;'
    '        for m = max(1, k - MH) : min(NS, k + MH)'
    '            ok = ok && kd(m);'
    '        end'
    '        if ok'
    '            e = Y(k, :).'' - ph(k) * (H * st_reg(sq, k, MH));'
    '            R = R + e * e''; n = n + 1;'
    '        end'
    '    end'
    '    if n < 2 * NV'
    '        R = R + Rt; n = n + nt;'
    '    end'
    '    w = (R / n + Ri) \ h0;'
    '    c = w'' * h0;'
    '    if abs(c) > 1e-12'
    '        w = w / conj(c);'
    '    else'
    '        w = complex(zeros(NV, 1));      % no gain towards our signal: the window outputs 0'
    '    end'
    '    gn = complex(0);'
    '    for k = IDXD(i0) : IDXD(i1)'
    '        zk = Y(k, :) * conj(w);'
    '        if KN(k)'
    '            gn = gn + zk * conj(SK(k));'
    '        else'
    '            gn = gn + zk * conj(qpsk_dec(zk * conj(g)));'
    '        end'
    '    end'
    '    g = gn / max(abs(gn), 1e-30);'
    '    j = i0;'
    '    for k = IDXD(i0) : IDXD(i1)'
    '        if ~KN(k)'
    '            z(j) = Y(k, :) * conj(w) * conj(g); sq(k) = qpsk_dec(z(j)); j = j + 1;'
    '        end'
    '        kd(k) = true; ph(k) = g;'
    '    end'
    '    pw(bi) = angle(g); kw(bi) = (IDXD(i0) + IDXD(i1)) / 2;'
    'end'
    'pu = 0; sxx = 0; sxy = 0;'
    'for bi = 1:nb'
    '    pu = pu + angle(exp(1j * (pw(bi) - pu)));'
    '    x = kw(bi) - (NPRE + 1) / 2;'
    '    sxx = sxx + x^2; sxy = sxy + x * pu;'
    'end'
    'bf = sxy / max(sxx, 1e-30);'
    'end'
    ''
    'function [z, e] = st_dd(Y, z, SK, IDXD, IDXP, PIL, MH, B, HWR, s2, DDI)'
    '% DDI decision-directed space-time passes. The frame''s channel by LS on its known and'
    '% decided symbols; per window of B data symbols, MVDR weights (R + ISI + s2 I)^-1 h0 with'
    '% R the covariance of the residuals within HWR of the window. The last pass leaves out'
    '% the rows that carry a pilot (in their snapshot or their regressors) and returns e, the'
    '% mean squared error of the pilots under its weights (the pilots after the previous'
    '% window''s last data symbol up to its own, the last window to the frame''s end).'
    'NS = size(Y, 1); NV = size(Y, 2); ND = numel(IDXD); NM = 2*MH + 1; NP = numel(IDXP);'
    'nb = max(1, floor(ND / B)); E = complex(zeros(NS, NV)); use = true(NS, 1); sf = SK; e = 0;'
    'for it = 1:DDI'
    '    sf(IDXD) = qpsk_dec(z);'
    '    if it == DDI'
    '        for q = 1:NP'
    '            for k = max(1, IDXP(q) - MH) : min(NS, IDXP(q) + MH)'
    '                use(k) = false;'
    '            end'
    '        end'
    '    end'
    '    A = complex(zeros(NM, NM)); C = complex(zeros(NV, NM));'
    '    for k = 1:NS'
    '        if use(k)'
    '            sv = st_reg(sf, k, MH);'
    '            A = A + sv * sv''; C = C + Y(k, :).'' * sv'';'
    '        end'
    '    end'
    '    H = C / A;'
    '    for k = 1:NS'
    '        E(k, :) = Y(k, :) - (H * st_reg(sf, k, MH)).'';'
    '    end'
    '    h0 = H(:, MH + 1); Ri = complex(s2 * eye(NV));'
    '    for m = 1:NM'
    '        if m ~= MH + 1'
    '            Ri = Ri + H(:, m) * H(:, m)'';'
    '        end'
    '    end'
    '    for bi = 1:nb'
    '        i0 = (bi-1)*B + 1; i1 = bi*B; if bi == nb, i1 = ND; end'
    '        kA = max(1, IDXD(i0) - HWR); kB = min(NS, IDXD(i1) + HWR);'
    '        R = complex(zeros(NV, NV)); n = 0;'
    '        for k = kA:kB'
    '            if use(k)'
    '                R = R + E(k, :).'' * conj(E(k, :)); n = n + 1;'
    '            end'
    '        end'
    '        w = (R / max(n, 1) + Ri) \ h0;'
    '        c = w'' * h0;'
    '        if abs(c) <= 1e-12'
    '            w = complex(zeros(NV, 1)); c = complex(1);   % no gain towards our signal: the window outputs 0'
    '        end'
    '        for m = i0:i1'
    '            z(m) = (Y(IDXD(m), :) * conj(w)) / c;'
    '        end'
    '        if it == DDI'
    '            lo = 0; hi = IDXD(i1);'
    '            if bi > 1'
    '                lo = IDXD(i0 - 1);'
    '            end'
    '            if bi == nb'
    '                hi = NS;'
    '            end'
    '            for q = 1:NP'
    '                if IDXP(q) > lo && IDXP(q) <= hi'
    '                    e = e + abs((Y(IDXP(q), :) * conj(w)) / c - PIL(q))^2;'
    '                end'
    '            end'
    '        end'
    '    end'
    'end'
    'e = e / NP;'
    'end'
    ''
    'function z = dd_mvdr(X, z, IDXD, B, MV, DDI)'
    '% DDI decision-directed passes on the samples X (a row per symbol): the decisions act as'
    '% known symbols for the leave-one-out LS channel of every window of B data symbols; MV'
    '% weighs it with the covariance of the window''s received samples (MVDR: no decision'
    '% error enters the covariance, so a wrong decision cannot pull our own direction into'
    '% it), else MRC.'
    'ND = numel(z); NV = size(X, 2); nb = max(1, floor(ND / B));'
    'sh = qpsk_dec(z);'
    'for it = 1:DDI'
    'if it > 1'
    '    sh = (sign(real(z)) + 1j * sign(imag(z))) / sqrt(2);'
    'end'
    'for bi = 1:nb'
    '    i0 = (bi-1)*B + 1; i1 = bi*B; if bi == nb, i1 = ND; end; n = i1 - i0 + 1;'
    '    hs = complex(zeros(NV, 1));'
    '    for m = i0:i1'
    '        v = X(IDXD(m), :).'';'
    '        hs = hs + v * conj(sh(m));'
    '    end'
    '    h = hs / n;'
    '    Ri = complex(eye(NV));'
    '    if MV'
    '        R = complex(zeros(NV, NV));'
    '        for m = i0:i1'
    '            v = X(IDXD(m), :).'';'
    '            R = R + v * v'';'
    '        end'
    '        R = R / n;'
    '        R = R + (1e-3 * real(trace(R)) / NV + 1e-12) * eye(NV);'
    '        Ri = inv(R);'
    '    end'
    '    for m = i0:i1'
    '        v = X(IDXD(m), :).'';'
    '        hm = (hs - v * conj(sh(m))) / (n - 1);'
    '        w = Ri * hm;'
    '        g = w'' * hm;'
    '        if abs(g) > 1e-12'
    '            z(m) = (w'' * v) / g;'
    '        end'
    '    end'
    'end'
    'end'
    'end'
    ''
    'function e = pilot_mse(X, z, IDXD, IDXP, PIL, B)'
    '% Mean squared error of the pilots under the MVDR weights of the decision-directed'
    '% passes (dd_mvdr) on the samples X: every window''s LS channel from the decisions z and'
    '% the covariance of its data samples, applied to the pilots after the previous window''s'
    '% last data symbol up to its own (the first and last windows to the frame''s ends).'
    'ND = numel(z); NV = size(X, 2); nb = max(1, floor(ND / B));'
    'sh = qpsk_dec(z); e = 0;'
    'for bi = 1:nb'
    '    i0 = (bi-1)*B + 1; i1 = bi*B; if bi == nb, i1 = ND; end; n = i1 - i0 + 1;'
    '    h = complex(zeros(NV, 1)); R = complex(zeros(NV, NV));'
    '    for m = i0:i1'
    '        v = X(IDXD(m), :).'';'
    '        h = h + v * conj(sh(m)); R = R + v * v'';'
    '    end'
    '    h = h / n; R = R / n; R = R + (1e-3 * real(trace(R)) / NV + 1e-12) * eye(NV);'
    '    w = R \ h; g = w'' * h;'
    '    lo = 0; hi = IDXD(i1);'
    '    if bi > 1'
    '        lo = IDXD(i0 - 1);'
    '    end'
    '    if bi == nb'
    '        hi = size(X, 1);'
    '    end'
    '    for q = 1:numel(IDXP)'
    '        if IDXP(q) > lo && IDXP(q) <= hi'
    '            zq = complex(0);'
    '            if abs(g) > 1e-12'
    '                zq = (w'' * X(IDXP(q), :).'') / g;'
    '            end'
    '            e = e + abs(zq - PIL(q))^2;'
    '        end'
    '    end'
    'end'
    'e = e / numel(IDXP);'
    'end'
    ''
    'function [G, s2, pq, tq] = eq_train(yx, PRE, SK, KN, IDXP, PC, NRK, RP, RQ, XO, PB)'
    '% Channel G of every lag by joint LS on the training''s rows whose symbols are all known'
    '% (yx: a row per symbol, XO rows before the first), robust to a burst over part of them,'
    '% the white level s2 of its residual, and'
    '% its phase pq at the training (0) and at every pilot block (tq: their centres [symbols])'
    '% from the correlation of the block''s rows with the known symbols'' share of them,'
    '% unwrapped.'
    'NR = size(yx, 2); NPRE = numel(PRE); NB = numel(PC);'
    'A = complex(zeros(NRK, NRK)); C = complex(zeros(NR, NRK)); nt = 0;'
    'for k = 1 + RQ : NPRE - RP'
    '    sv = complex(zeros(NRK, 1));'
    '    for l = 1:NRK'
    '        sv(l) = PRE(k - (l - 1 - RP));'
    '    end'
    '    A = A + sv * sv''; C = C + yx(k + XO, :).'' * sv''; nt = nt + 1;'
    'end'
    'A = A + 1e-6 * real(trace(A)) / NRK * eye(NRK);'
    'G = C / A;'
    '% once more with the rows whose residual exceeds 4 times the median weighed down by that'
    '% ratio (an interferer burst over part of the training), and the level of that fit'
    'er = zeros(nt, 1);'
    'for k = 1 + RQ : NPRE - RP'
    '    sv = complex(zeros(NRK, 1));'
    '    for l = 1:NRK'
    '        sv(l) = PRE(k - (l - 1 - RP));'
    '    end'
    '    ev = yx(k + XO, :).'' - G * sv;'
    '    er(k - RQ) = real(ev'' * ev);'
    'end'
    'me = median(er);'
    'A = complex(zeros(NRK, NRK)); C = complex(zeros(NR, NRK)); ws = 0;'
    'for k = 1 + RQ : NPRE - RP'
    '    sv = complex(zeros(NRK, 1));'
    '    for l = 1:NRK'
    '        sv(l) = PRE(k - (l - 1 - RP));'
    '    end'
    '    w = min(1, 4 * me / max(er(k - RQ), 1e-30));'
    '    A = A + w * (sv * sv''); C = C + w * (yx(k + XO, :).'' * sv''); ws = ws + w;'
    'end'
    'A = A + 1e-6 * real(trace(A)) / NRK * eye(NRK);'
    'G = C / A;'
    'e2 = 0;'
    'for k = 1 + RQ : NPRE - RP'
    '    sv = complex(zeros(NRK, 1));'
    '    for l = 1:NRK'
    '        sv(l) = PRE(k - (l - 1 - RP));'
    '    end'
    '    ev = yx(k + XO, :).'' - G * sv;'
    '    e2 = e2 + min(1, 4 * me / max(er(k - RQ), 1e-30)) * real(ev'' * ev);'
    'end'
    's2 = max(e2 / (NR * max(ws - NRK, 1)), 1e-30);'
    'tq = zeros(NB + 1, 1); pq = zeros(NB + 1, 1); tq(1) = (1 + RQ + NPRE - RP) / 2; pu = 0;'
    'for b = 1:NB'
    '    cb = complex(0);'
    '    for n = IDXP((b-1)*PB + 1) - RP : IDXP(b*PB) + RQ'
    '        cb = cb + eq_known(G, SK, KN, n, RP)'' * yx(n + XO, :).'';'
    '    end'
    '    pu = pu + angle(exp(1j * (angle(cb) - pu)));'
    '    tq(b + 1) = PC(b); pq(b + 1) = pu;'
    'end'
    'end'
    ''
    'function kn = eq_known(G, SK, KN, n, RP)'
    '% The known symbols'' share of row n of the lag model (G: a column per lag, RP lags before).'
    'kn = complex(zeros(size(G, 1), 1));'
    'for l = 1:size(G, 2)'
    '    kl = n - (l - 1 - RP);'
    '    if kl >= 1 && kl <= numel(SK) && KN(kl)'
    '        kn = kn + G(:, l) * SK(kl);'
    '    end'
    'end'
    'end'
    ''
    'function f = le_taps(G, s2, NE)'
    '% Linear MMSE equalizer on the MRC output r(k) = sum_l G(:, l)'' y(k + l): its symbol'
    '% response rho_i = sum_l G(:, l)'' G(:, l + i) and noise s2 rho; NE taps centred on the'
    '% symbol, scaled to an unbiased output.'
    'NRK = size(G, 2); E0 = (NE - 1) / 2;'
    'rho = complex(zeros(2*NRK - 1, 1));'
    'for i = 1 - NRK : NRK - 1'
    '    for l = 1:NRK'
    '        if l + i >= 1 && l + i <= NRK'
    '            rho(i + NRK) = rho(i + NRK) + G(:, l)'' * G(:, l + i);'
    '        end'
    '    end'
    'end'
    'Ruu = complex(zeros(NE, NE)); pv = complex(zeros(NE, 1));'
    'for a = 1:NE'
    '    ja = a - 1 - E0;'
    '    pv(a) = rget(rho, ja, NRK);'
    '    for b = 1:NE'
    '        jb = b - 1 - E0;'
    '        acc = s2 * rget(rho, ja - jb, NRK);'
    '        for i = 1 - NRK : NRK - 1'
    '            acc = acc + rget(rho, i, NRK) * conj(rget(rho, i + jb - ja, NRK));'
    '        end'
    '        Ruu(a, b) = acc;'
    '    end'
    'end'
    'f = Ruu \ pv;'
    'g = real(f'' * pv);'
    'if g > 1e-30'
    '    f = f / g;'
    'end'
    'end'
    ''
    'function v = rget(rho, i, NRK)'
    'v = complex(0);'
    'if abs(i) <= NRK - 1'
    '    v = rho(i + NRK);'
    'end'
    'end'
    ''
    'function s = qpsk_dec(z)'
    '% QPSK decisions (Gray, pi/4); a zero component goes to the positive side.'
    's = (sign(real(z)) + 1j * sign(imag(z))) / sqrt(2);'
    's(real(s) == 0) = s(real(s) == 0) + 1 / sqrt(2);'
    's(imag(s) == 0) = s(imag(s) == 0) + 1j / sqrt(2);'
    'end'
    };
s = sprintf('%s\n', c{:});
end

%% ===================== Helpers =====================
function c = shadow_code(p, on)
% Hidden antenna hs of the frame and the share gs of the depth it has lost, from the
% attitude at the frame (bt, rt: turn_attitude.m), the turn's bank and the speed
% (shadow_frame.m, shadow_spec.m).
c = '';
if ~on, return; end
s = shadow_spec(p);
c = sprintf('[hs, gs] = shadow_frame(bt, att(2), rt, [abs(att(3)) att(10)], att(4), %d, %s, %.6f, fd * %.12g, %.6f, %.6f);\n', ...
    p.n_rx, mat2str(s(2:3), 10), s(4), p.c_light / p.carrier_freq, s(5), s(8));
end

function g = tone_gain(p)
% Power of a unit-JSR tone: a noise jammer of power JSR per sample puts JSR/sps
% into our band after the receive filter, a tone inside the passband puts all of
% its power there, so the tone gets JSR/sps for the same in-band ratio.
g = 1 / p.sps;
end

function c = sos_init(fv, pv, nr)
% Random direction cosines cos(alpha) to the fuselage axis and phases of 32 sinusoids
% per antenna (Doppler fd*cos(alpha), sos_gains).
c = sprintf(['if isempty(%s)\n    %s = cos(2*pi*rand(32, %d));\nend\n' ...
    'if isempty(%s)\n    %s = 2*pi*rand(32, %d);\nend\n'], fv, fv, nr, pv, pv, nr);
end

function c = sos_gains(dv, fv, pv, p)
% Unit-power Rayleigh gains (Ns x n_rx) from the sinusoids at times t, then the
% receive correlation (Cholesky factor of rho^|i-j|). The pitch th moves the antennas
% fore and aft on their lever arm: phase k aD cos(alpha) sin(th) on each path
% (Banagar & Dhillon).
nr = p.n_rx;

c = sprintf(['%s = complex(zeros(Ns, %d));\n' ...
    'sw = %.12f * sind(th);\n' ...
    'for k = 1:%d\n' ...
    '    %s(:, k) = exp(1j * (2*pi*t*(fd*%s(:, k).'') + sw*%s(:, k).'' + repmat(%s(:, k).'', Ns, 1))) * ones(32, 1) / sqrt(32);\n' ...
    'end\n' ...
    'Rr = zeros(%d, %d);\nfor i = 1:%d\n    for j = 1:%d\n        Rr(i, j) = rho ^ abs(i - j);\n    end\nend\n' ...
    '%s = %s * chol(Rr);\n'], dv, nr, lever_k(p), nr, dv, fv, fv, pv, nr, nr, nr, nr, dv, dv);
end

function [nt, S] = tdl_taps(p, fs)
% Taps of the delay line (1: flat channel) and the samples between them; the line must
% end inside the guard, where the receive filter of the frame's last pulse ends
% (frame_layout.m).
nt = 1 + p.tdl * floor(p.tdl_max_ns / p.tdl_step_ns);
S = round(p.tdl_step_ns * 1e-9 * fs);
if nt > 1
    L = frame_layout(p);
    if abs(S - p.tdl_step_ns * 1e-9 * fs) > 1e-9 || (nt - 1) * S > (L.G - p.filter_span - ceil(p.timing_max_sym)) * p.sps
        error('build_threat_model: delay line taps must be whole samples and end inside the guard');
    end
end
end

function c = tdl_code(dv, fv, pv, av, col, p, fs, nt)
% Late taps 1..nt-1 of one source's delay line, dv (Ns x n_rx x nt-1): on every tap and
% antenna its own 32 sinusoids as sos_gains, evaluated every 64 samples (16 us, in which a
% sinusoid's phase moves by at most 2 pi 358 Hz 16 us = 0.04 rad) and interpolated, the
% receive correlation (Rr of sos_gains), then centred on the source by its steering
% vectors av; a tap without power in column col of 'Tdl' stays 0.
nr = p.n_rx;
c = sprintf(['tc = t(1) + (0:64:Ns+63).'' / %.1f;\n' ...
    'swc = %.12f * sind(att(4) + att(5) * sin(2*pi*att(6)*tc + att(7)));\n' ...
    'jj = floor((0:Ns-1).'' / 64) + 1;\nww = mod((0:Ns-1).'', 64) / 64;\nRc = chol(Rr);\n' ...
    '%s = complex(zeros(Ns, %d, %d));\n' ...
    'for m = 1:%d\n' ...
    '    if tdl(m+1, %d) == 0\n        continue;\n    end\n' ...
    '    Dc = complex(zeros(numel(tc), %d));\n' ...
    '    for k = 1:%d\n' ...
    '        Dc(:, k) = exp(1j * (2*pi*tc*(fd*%s(:, k, m).'') + swc*%s(:, k, m).'' + repmat(%s(:, k, m).'', numel(tc), 1))) * ones(32, 1) / sqrt(32);\n' ...
    '    end\n' ...
    '    Dc = Dc * Rc;\n' ...
    '    for k = 1:%d\n' ...
    '        %s(:, k, m) = (Dc(jj, k) .* (1 - ww) + Dc(jj + 1, k) .* ww) .* %s(:, k);\n' ...
    '    end\n' ...
    'end\n'], fs, lever_k(p), dv, nr, nt-1, nt-1, col, nr, nr, fv, fv, pv, nr, dv, av);
end

function c = pitch_code()
% Pitch over the frame [deg]: static tilt and wobble of the 'Att' block.
c = sprintf('th = att(4) + att(5) * sin(2*pi*att(6)*t + att(7));\n');
end

function k = lever_k(p)
% Phase per unit displacement cosine of antennas p.wobble_arm_m from the centre of rotation [rad].
k = 2*pi * p.wobble_arm_m * p.carrier_freq / p.c_light;
end

function s = ant_pos(nr)
% Antenna positions along the array from its centre [element spacings], a row literal.
s = mat2str((0:nr-1) - (nr-1)/2);
end

function [n, tb] = idle_bins(p, fs, E)
% RSSI bins of the idle time between two frames: p.idle_rssi_hz of them per second from the
% previous frame's last sample to this frame's earliest delay-line sample; 0 without a rate
% (no recording: the threat block as before).
tb = 0; n = 0;
if ~isfield(p, 'idle_rssi_hz') || isempty(p.idle_rssi_hz) || p.idle_rssi_hz <= 0, return; end
tb = 1 / p.idle_rssi_hz;
n = max(0, floor((round(p.cycle_s * fs) - p.samples_per_frame - E) / (fs * tb)));
end

function own = own_output(p)
% Our own received component as output 4 of the threat block (rate_reduce: the chip-rate
% field of the level measurements, extract_closed_loop_frames.m; p.own_out: the true
% channel of the predicted MMSE gain's check, validate_phy.m). The link is the same.
own = (isfield(p, 'proc_gain_db') && ~isempty(p.proc_gain_db) && p.proc_gain_db > 0) || ...
    (isfield(p, 'own_out') && p.own_out);
end

function c = idle_code(on, nxt, sw, k, n, tb, cyc, fs)
% Code recording component k's on-share in every idle bin before this frame (the gap from
% the previous frame's end): the schedule's events are drawn by its own switch code sw, in
% time order, before the frame's samples draw theirs, so every draw keeps its place.
c = '';
if n == 0, return; end
c = [sprintf(['if nfr > 1\n    ga = t(1) - %.12g + Ns / %.1f;\n    for q = 1:%d\n' ...
    '        qa = ga + (q - 1) * %.12g; qb = qa + %.12g; qs = 0; tc = qa;\n' ...
    '        while %s < qb\n            if %s > tc\n                qs = qs + double(%s) * (%s - tc); tc = %s;\n            end\n'], ...
    round(cyc * fs) / fs, fs, n, tb, tb, nxt, nxt, on, nxt, nxt) sw ...
    sprintf('        end\n        qs = qs + double(%s) * (qb - tc);\n        idl(%d, q) = qs / %.12g;\n    end\nend\n', on, k, tb)];
end

function c = gamma_draw(k, v)
% Code drawing v ~ Gamma(k, 1): Marsaglia-Tsang for shape k + 1, times U^(1/k) when k < 1.
a = k + (k < 1);
d = a - 1/3; cc = 1 / sqrt(9 * d);
c = sprintf(['            %s = 0;\n            while %s == 0\n                zx = randn; zv = (1 + %.10f * zx)^3;\n' ...
    '                if zv > 0 && log(rand) < 0.5 * zx^2 + %.10f - %.10f * zv + %.10f * log(zv)\n' ...
    '                    %s = %.10f * zv;\n                end\n            end\n'], v, v, cc, d, d, d, v, d);
if k < 1
    c = [c sprintf('            %s = %s * rand^(%.10f);\n', v, v, 1 / k)];
end
end

function a = steering(p, aoa_deg)
% ULA steering vector, element k at (k-1)*spacing, direction measured from broadside.
k = (0:p.n_rx-1).';
a = exp(-1j * 2*pi * p.ant_spacing_wl * k * sind(aoa_deg));
end

function s = cvec2(a)
% Complex column literal from its real and imaginary parts.
s = sprintf('complex(%s, %s)', mat2str(real(a(:)), 12), mat2str(imag(a(:)), 12));
end

function s = cvec(a)
s = '[';
for i = 1:numel(a)
    s = [s sprintf('complex(%.12f, %.12f); ', real(a(i)), imag(a(i)))]; %#ok<AGROW>
end
s = [s(1:end-2) ']'];
end

function set_script(sf_root, path, script)
chart = sf_root.find('-isa', 'Stateflow.EMChart', 'Path', path);
chart.Script = script;
end

function p = antenna_defaults(p)
% Defaults for params.mat files without the antenna fields.
d = struct('n_rx', 3, 'ant_aperture_m', 1.2, 'rx_corr', 0.3, 'gcs_aoa_deg', 0, ...
    'int_aoa_deg', [42 -52.2 61.3], 'int_rician_k', p.rician_k, 'rx_combiner', 'mrc', ...
    'csi_block', 64, 'mmse_window', 32, 'seed', [], 'int_aoa_random', false, 'int_aoa_range_deg', [-90 90], ...
    'k_random', false, 'k_range_db', [-5 20], 'tone_jsr_db', 16, 'tone_offset_hz', 300e3, 'shadow_db', 20, ...
    'yaw_random', false, 'roll_max_deg', 57.9, 'turn_v_floor', 8, 'yaw_rate_max', 28.7, ...
    'quiet_symbols', 0, 'cycle_s', 0, 'benign_occ', [], 'benign_pkt_s', [], 'benign_idle_shape', 1, ...
    'corr_random', false, 'corr_range', [0.3 0.9], 'shadow_k_db', -16, 'fault_atten_db', 18, ...
    'chain_amp_db', 0, 'chain_phase_deg', 0, 'spec_amp', 0, 'spec_delay_ns', 0, ...
    'stf_len', 4, 'stf_rep', 10, 'ltf_len', 16, 'ltf_rep', 2, 'pilot_block', 4, 'pilot_every', 48, ...
    'rx_sync', 'ideal', 'cfo_ppm', 25, 'timing_max_sym', 4, 'rx_dd_iter', 2, 'sync_coh_min', 0, ...
    'adc_bits', 0, 'adc_backoff_db', 12, 'adc_attack_db', Inf, ...
    'gcs_tracked', false, 'gcs_ant_dbi', 12, 'gcs_err_deg', [5.62 1.51], 'gcs_floor_db', 14, 'gcs_pt_dbm', -6, ...
    'alt_random', false, 'alt_range_m', [15 120], 'gcs_h_m', 10, 'uav_null_db', -30, 'inband_cap_db', 30, ...
    'lb_uav_dbi', 2, 'lb_nf_db', 5, 'lb_margin_db', 10, 'lb_rate_bps', 2e6, ...
    'gcs_aoa_random', false, 'gcs_aoa_range_deg', [-90 90], 'body_random', false, 'body_loss_db', [3.03 2.53 0.016 10.96], ...
    'wobble_random', false, 'wobble_v_max', 8, 'wobble_roll_deg', [-17.5 19.3], 'wobble_pitch_deg', [-11.0 14.9], ...
    'wobble_amp_deg', 10, 'wobble_pitch_lim_deg', [-17.7 21.1], 'wobble_freq_hz', [5 25], 'wobble_arm_m', 0.4, 'int_los_doppler', true, 'c_light', 3e8, ...
    'sweep_speed_hz_s', 1e9, 'sweep_bw_hz', 4e6, 'sweep_period_s', [20e-3 83.5e-3], 'jam_timing_random', false, ...
    'fdiv_spacing_hz', 25e6, 'sweep_fdiv', false, ...
    'tdl', false, 'tdl_random', false, 'tdl_ds_ns', [0 0], 'tdl_step_ns', 250, 'tdl_max_ns', 4500, ...
    'tdl_sig_ds', [-6.52 0.32; -6.63 0.16; -6.43 0.26], 'tdl_sig_alt_m', [25 75], 'tdl_int_ds', [-6.63 0.16], ...
    'tdl_clip_ns', 2250, ...
    'pl_onset_frames', [1 1], 'shadow_roll_deg', 16.1, 'shadow_hdg_deg', 30, 'roll_deg', 0, ...
    'fault_onset_frames', [1 1], 'roll_in_frames', [], 'roll_rate_lo', 30 / 1.6, 'roll_rate_win', [0.5 45.4; 1 35.5], ...
    'shadow_evt_db', 0, 'shadow_el_deg', 2.9, ...
    'shadow_fit', [12.4 0.25 4.4], 'shadow_fit_z', 1.96, 'shadow_v_min', 8, 'reactive_delay_s', 0, ...
    'burst_duty_range', [0.5 0.5], 'burst_duty', 0.5, 'burst_on_sym', 31, 'burst_j4', [0.2 0], 'cap_frames', 1, ...
    'cal_random', false, 'cal_err_db', 0);
f = fieldnames(d);
for i = 1:numel(f)
    if ~isfield(p, f{i}), p.(f{i}) = d.(f{i}); end
end
p.ant_spacing_wl = p.ant_aperture_m / (3e8 / p.carrier_freq) / max(p.n_rx - 1, 1);   % same aperture for 2 or 3 antennas
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
