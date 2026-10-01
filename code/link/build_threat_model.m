function build_threat_model(p)
%% BUILD_THREAT_MODEL - GCS -> UAV link with a multi-antenna UAV receiver
% build_threat_model      params from params.mat, model saved to models/
% build_threat_model(p)   params struct p, model built in memory only (parallel
%                         workers of build_policy_pools.m)
% [Tx: frame + QPSK + RRC] -> [Channel: Rician per UAV antenna] -> [Threat] -> [AWGN per antenna]
%   -> [Rx: RRC per antenna, synchronization, channel estimation, combining, QPSK demod]
%
% Link: command uplink, single GCS antenna -> p.n_rx omni antennas on the UAV
% (line array over p.ant_aperture_m, spacing from the number of antennas).
% The GCS antenna gain is part of Eb/N0.
% Eb/N0 is per receive antenna (per branch).
%
% Tx        frame_layout.m: quiet slot, short and long training, data with pilot blocks, guard.
% Channel   LoS steering vector (direction p.gcs_aoa_deg, turning at the heading rate of
%           the 'Yaw' block, heading_rate.m) + diffuse Rayleigh part
%           (sum of 32 sinusoids per antenna with random Doppler angles and phases,
%           Jakes spectrum up to fd; receive correlation p.rx_corr). K-factors of
%           our signal and of the interferers come from the Constant block 'Kfac':
%           [p.rician_k p.int_rician_k], or, with p.k_random, drawn per seed from
%           p.k_range_db by link_seed.m (channel_k.m).
%           With p.rx_sync 'real': carrier frequency offset of the two radios per flight
%           (uniform within +-2 p.cfo_ppm of the carrier), Doppler shift of the LoS
%           path (fd cos of a direction drawn per flight), and an unknown arrival
%           time of every frame (uniform fractional delay up to p.timing_max_sym).
% Threat    signal-side threats scale our signal (antenna_fault and
%           airframe_shadowing hit one antenna, drawn per seeded run); every additive threat is ONE
%           waveform arriving through its own spatial channel (own diffuse fading).
%           Output 2: share of the frame's samples with the threat on the air
%           (benign packet traffic, an antenna fault with its contact open; 1 for
%           every other threat, 0 for none).
%           Last, every antenna's receive chain: a gain and phase error fixed per flight
%           (p.chain_amp_db, p.chain_phase_deg).
%           Interferer directions come from the Constant block 'AoA': p.int_aoa_deg,
%           or, with p.int_aoa_random, drawn per seed from p.int_aoa_range_deg by
%           link_seed.m (interferer_aoa.m); they turn with the heading as our LoS does.
% Rx        'real': coarse frequency from the repeats of the short training, timing from
%           the long training over the arrival window, fine frequency from the two long
%           repeats; every statistic over all antennas in a whitened domain: whitening
%           with the quiet slot before the frame (interference already on the air) or with
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
%           the phase progression over the pilot blocks, removed before interpolation.
%           Decision-directed passes (p.rx_dd_iter) treat the previous decisions as known
%           symbols and repeats the per-window estimation of the 'ideal' receiver, so
%           an interferer channel that changes within the frame is followed; the
%           channel estimator's outputs 4-5 come from the last pass.
%           'ideal': known timing, frequency and transmitted symbols; per window of
%           data symbols the LS channel estimate from the OTHER symbols of the window
%           (leave-one-out) and the covariance of the residual r - h*s.
%           'mrc'  : w = h,          window p.csi_block symbols (baseline)
%           'mmse' : w = R^-1 * h, window p.mmse_window symbols (spatial_diversity
%                    action: nulls up to n_rx-1 interferers, tracks a faulty branch);
%                    'real' first pass: per window, whitening with the covariance of
%                    the window and its neighbourhood (needs no symbol knowledge), the
%                    nearest known symbols give the channel in that domain, MRC there
%           Output 2 = received IQ of every antenna (sensing tap for the detector),
%           output 3 = combiner output (data soft symbols), outputs 4-5 = the channel
%           estimator's per-32-data-symbol channel estimates and the frame's
%           interference + noise covariance, output 6 = synchronization: arrival
%           [samples], frequency offset [Hz], timing peak over the window mean,
%           second timing peak (more than one symbol away) over the first,
%           fractional arrival [samples] from a parabola through the timing peak.
%           The receiver measurements of extract_closed_loop_frames.m use only
%           outputs 1-6.
% Seeds     p.seed, or drawn from the global stream when empty; channel, interferer
%           channels, threat waveforms, AWGN and bit source all derive from it.
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
    seed = randi(2^31 - 1000);
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
add_block('commchan3/AWGN Channel',                          [modelName '/AWGN'],    'Position', [580 95 650 125]);
add_block('simulink/User-Defined Functions/MATLAB Function', [modelName '/Rx'],      'Position', [710 90 810 150]);
add_block('simulink/Sources/Constant', [modelName '/Seed'],    'Position', [150 190 220 210]);
add_block('simulink/Sources/Constant', [modelName '/Doppler'], 'Position', [150 230 220 250]);
add_block('simulink/Sources/Constant', [modelName '/AoA'],     'Position', [150 270 220 290]);
add_block('simulink/Sources/Constant', [modelName '/Kfac'],    'Position', [150 310 220 330]);
add_block('simulink/Sources/Constant', [modelName '/Yaw'],     'Position', [150 350 220 370]);
add_block('simulink/Sources/Constant', [modelName '/Corr'],    'Position', [150 390 220 410]);
add_block('simulink/Sinks/To Workspace', [modelName '/tx_sink'], 'Position', [150 30 230 60]);
add_block('simulink/Sinks/To Workspace', [modelName '/rx_sink'], 'Position', [870 90 950 120]);
add_block('simulink/Sinks/To Workspace', [modelName '/Tx_IQ'],   'Position', [300 30 380 60]);
add_block('simulink/Sinks/To Workspace', [modelName '/Rx_IQ'],   'Position', [870 150 950 180]);
add_block('simulink/Sinks/To Workspace', [modelName '/Rx_Z'],    'Position', [870 210 950 240]);
add_block('simulink/Sinks/To Workspace', [modelName '/Rx_H'],    'Position', [870 270 950 300]);
add_block('simulink/Sinks/To Workspace', [modelName '/Rx_R'],    'Position', [870 330 950 360]);
add_block('simulink/Sinks/To Workspace', [modelName '/Thr_act'], 'Position', [580 30 660 60]);
add_block('simulink/Sinks/To Workspace', [modelName '/Rx_S'],    'Position', [870 390 950 420]);

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

snr0 = p.EbNo_dB(1) + 10*log10(p.bits_per_symbol) - 10*log10(sps);
set_param([modelName '/AWGN'], 'SNR', num2str(snr0), 'SignalPower', num2str(1/sps));

set_param([modelName '/tx_sink'], 'VariableName', 'tx_bits_out', 'SaveFormat', 'Array');
set_param([modelName '/rx_sink'], 'VariableName', 'rx_bits_out', 'SaveFormat', 'Array');
set_param([modelName '/Tx_IQ'],   'VariableName', 'Tx_IQ',       'SaveFormat', 'Array');
set_param([modelName '/Rx_IQ'],   'VariableName', 'Rx_IQ',       'SaveFormat', 'Array');
set_param([modelName '/Rx_Z'],    'VariableName', 'Rx_Z',        'SaveFormat', 'Array');
set_param([modelName '/Rx_H'],    'VariableName', 'Rx_H',        'SaveFormat', 'Array');
set_param([modelName '/Rx_R'],    'VariableName', 'Rx_R',        'SaveFormat', 'Array');
set_param([modelName '/Thr_act'], 'VariableName', 'Thr_act',     'SaveFormat', 'Array');
set_param([modelName '/Rx_S'],    'VariableName', 'Rx_S',        'SaveFormat', 'Array');

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
add_line(modelName, 'Channel/1',   'Threat/1',  'autorouting', 'on');
add_line(modelName, 'Threat/1',    'AWGN/1',    'autorouting', 'on');
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
set_param([modelName '/AoA'], 'UserDataPersistent', 'on', 'UserData', struct('aoa_random', logical(p.int_aoa_random), ...
    'aoa_range', p.int_aoa_range_deg, 'aoa_fixed', p.int_aoa_deg(:)'));
set_param([modelName '/Kfac'], 'Value', mat2str([p.rician_k p.int_rician_k], 8));
set_param([modelName '/Kfac'], 'UserDataPersistent', 'on', 'UserData', struct('k_random', logical(p.k_random), ...
    'k_range', p.k_range_db));
set_param([modelName '/Yaw'], 'Value', '0');
set_param([modelName '/Corr'], 'Value', sprintf('%.6f', p.rx_corr));
set_param([modelName '/Corr'], 'UserDataPersistent', 'on', 'UserData', struct('corr_random', logical(p.corr_random), ...
    'corr_range', p.corr_range));
set_param([modelName '/Yaw'], 'UserDataPersistent', 'on', 'UserData', struct('yaw_random', logical(p.yaw_random), ...
    'roll_max_deg', p.roll_max_deg, 'turn_v_floor', p.turn_v_floor, 'yaw_rate_max', p.yaw_rate_max, ...
    'c_light', p.c_light, 'carrier_freq', p.carrier_freq));
link_seed(modelName, seed, p.fd_max);

%% ---- Save ----
if save_model
    if ~exist('models', 'dir'); mkdir('models'); end
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
% Signal channel: LoS steering vector toward the GCS + correlated diffuse fading;
% K-factor kdb(1) from the 'Kfac' block. With a real receiver: frequency offset of
% the two radios and LoS Doppler shift per flight, unknown arrival time per frame
% (fractional delay applied in the frequency domain; the frame ends in its guard).
nr = p.n_rx;
cyc = round(p.cycle_s * fs);          % channel samples from one frame to the next (one decision cycle)
real_rx = strcmpi(p.rx_sync, 'real');
if real_rx
    pers = ' cfo fl';
    imp = sprintf(['if isempty(cfo)\n    cfo = %.6f * (2*rand - 1);\nend\n' ...
        'if isempty(fl)\n    fl = cos(2*pi*rand);\nend\n'], 2 * p.cfo_ppm * 1e-6 * p.carrier_freq);
    dly = sprintf(['tau = rand * %.6f;\n' ...
        'kk = [0:ceil(Ns/2)-1, -floor(Ns/2):-1].'';\n' ...
        'x = ifft(fft(x) .* exp(-1j*2*pi*kk*tau/Ns));\n' ...
        'r = exp(1j*2*pi*cfo*t);\n' ...
        'los = exp(1j*2*pi*fd*fl*t);\n'], p.timing_max_sym * p.sps);
    mix = '    y(:, k) = gk * x .* r .* (sqrt(Kk/(Kk+1)) * a(k) * los + sqrt(1/(Kk+1)) * D(:, k));\n';
else
    pers = ''; imp = ''; dly = '';
    mix = '    y(:, k) = gk * x .* (sqrt(Kk/(Kk+1)) * a(k) + sqrt(1/(Kk+1)) * D(:, k));\n';
end
% airframe shadowing: one antenna, drawn per run, loses p.shadow_db and its line of sight
% (K-factor p.shadow_k_db, Sun et al.)
thr = lower(p.active_threat);
shd = any(strcmp(strsplit(thr, '+'), 'airframe_shadowing'));
if shd
    pers = [pers ' hs'];
    imp = [imp sprintf('if isempty(hs)\n    hs = randi(%d);\nend\n', nr)];
    sel = sprintf(['    Kk = K; gk = 1;\n    if k == hs\n        Kk = %.10f; gk = %.10f;\n    end\n'], ...
        10^(p.shadow_k_db/10), 10^(-p.shadow_db/20));
else
    sel = sprintf('    Kk = K; gk = 1;\n');
end
s = [sprintf('function y = fcn(x, seed, fd, kdb, yaw, rho)\n%%%%#codegen\npersistent f0 ph n%s\n', pers) ...
    sprintf('if isempty(f0)\n    rng(seed, ''twister'');\nend\n') ...
    sos_init('f0', 'ph', nr) imp ...
    sprintf('if isempty(n)\n    n = 0;\nend\nNs = size(x, 1);\nt = (n + (0:Ns-1).'') / %.1f;\nn = n + max(Ns, %d);\n', fs, cyc) ...
    sos_gains('D', 'f0', 'ph', p) dly ...
    sprintf(['K = 10^(kdb(1)/10);\n' ...
    'a = exp(-1j * %.12f * (0:%d).'' * sind(%.8f + yaw * t(1)));\n' ...
    'y = complex(zeros(Ns, %d));\n' ...
    'for k = 1:%d\n' sel mix ...
    'end\n' ...
    'end\n'], 2*pi*p.ant_spacing_wl, nr-1, p.gcs_aoa_deg, nr, nr)];
s = strrep(s, '%%#codegen', '%#codegen');
end

function s = threat_script(p, fs)
% Signal-side components first (they act on our signal), then every
% additive component as one waveform through its own spatial channel.
nr  = p.n_rx;
sps = p.sps;
thr = lower(p.active_threat);
if any(strcmp(thr, {'', 'none'}))
    parts = {};
else
    parts = strsplit(thr, '+');
end
SIGSIDE = {'path_loss', 'antenna_fault', 'airframe_shadowing'};
sig  = parts(ismember(parts, SIGSIDE));
addc = parts(~ismember(parts, SIGSIDE));
if numel(addc) > numel(p.int_aoa_deg)
    error('build_threat_model: %d additive components, only %d interferer directions', numel(addc), numel(p.int_aoa_deg));
end

pers = {}; init = {}; body = {};
if any(ismember(sig, {'antenna_fault'}))
    pers{end+1} = 'hit_ant'; init{end+1} = sprintf('hit_ant = randi(%d);', nr);   % the antenna with the open connector
end
body{end+1} = sprintf('Ns = size(u, 1);\ny = u;\nt = (nI + (0:Ns-1).'') / %.1f;\nnI = nI + max(Ns, %d);\nact = %d;\n', ...
    fs, round(p.cycle_s * fs), double(~isempty(parts)));   % interferer channels on the same clock as ours

for i = 1:numel(sig)
    switch sig{i}
        case 'path_loss'
            body{end+1} = sprintf('y = y * %.8f;\n', 10^(-p.path_loss_db/20)); %#ok<AGROW>
        case 'antenna_fault'
            % a connector of one antenna, drawn per run, is open for the flight
            body{end+1} = sprintf('y(:, hit_ant) = y(:, hit_ant) * %.8f;\n', 10^(-p.fault_atten_db/20)); %#ok<AGROW>
        case 'airframe_shadowing'
            % applied in the channel: the hidden antenna loses its line of sight there
    end
end
if ~isempty(addc)
    body{end+1} = sprintf('ys = y(:, 1);\n');       % our signal as the reactive jammer senses it
end

if ~isempty(addc)
    body{end+1} = sprintf('Ki = 10^(kdb(2)/10);\n');
end
for c = 1:numel(addc)
    comp = addc{c};
    switch comp
        case 'jamming'
            w = sprintf('w = sqrt(%.8f/2) * complex(randn(Ns, 1), randn(Ns, 1));\n', 10^(p.jsr_db/10));
        case 'tone_jamming'
            % CW tone at a random offset inside the flat part of our band; power
            % scaled so its in-band power over our signal equals tone_jsr_db
            pers{end+1} = 'tone_f'; init{end+1} = sprintf('tone_f = %.4f * (2*rand - 1);', p.tone_offset_hz); %#ok<AGROW>
            pers{end+1} = 'tone_ph'; init{end+1} = 'tone_ph = 2*pi*rand;'; %#ok<AGROW>
            w = sprintf('w = sqrt(%.8f) * exp(1j * (2*pi*tone_f*t + tone_ph));\n', 10^(p.tone_jsr_db/10) * tone_gain(p));
        case 'benign_interference'
            if ~isempty(p.benign_occ)
                % WLAN packets: log-uniform durations; idle gaps gamma-distributed with the
                % field shape, their mean set by the flight's occupancy (Marsaglia-Tsang
                % sampler, boosted for a shape below 1); the schedule runs on the channel clock
                d = p.benign_pkt_s; md = (d(2) - d(1)) / log(d(2) / d(1));
                pers{end+1} = 'b_occ'; init{end+1} = sprintf('b_occ = %.6f + %.6f * rand;', p.benign_occ(1), diff(p.benign_occ)); %#ok<AGROW>
                pers{end+1} = 'b_on'; init{end+1} = 'b_on = rand < b_occ;'; %#ok<AGROW>
                pers{end+1} = 'b_next'; init{end+1} = 'b_next = 0;'; %#ok<AGROW>
                w = sprintf(['on = false(Ns, 1);\nfor i = 1:Ns\n    while t(i) >= b_next\n' ...
                    '        if b_on\n            b_on = false;\n' gamma_draw(p.benign_idle_shape, 'gg') ...
                    '            b_next = b_next + gg * %.10f * (1 - b_occ) / b_occ / %.10f;\n' ...
                    '        else\n            b_on = true; b_next = b_next + exp(%.8f + %.8f * rand);\n        end\n' ...
                    '    end\n    on(i) = b_on;\nend\nact = mean(double(on));\n' ...
                    'w = sqrt(%.8f/2) * complex(randn(Ns, 1), randn(Ns, 1)) .* on;\n'], ...
                    md, p.benign_idle_shape, log(d(1)), log(d(2) / d(1)), 10^(p.benign_int_db/10));
            else
                w = sprintf('w = sqrt(%.8f/2) * complex(randn(Ns, 1), randn(Ns, 1));\n', 10^(p.benign_int_db/10));
            end
        case 'noise_burst'
            ps = p.burst_period * sps; on = round(p.burst_duty * ps);
            pers{end+1} = 'k_nb'; init{end+1} = 'k_nb = 0;'; %#ok<AGROW>
            w = gated_noise('k_nb', ps, on, 10^(p.jsr_db/10));
        case 'sweeping_jammer'
            ps = p.sweep_period * sps; on = round(p.sweep_duty * ps);
            pers{end+1} = 'k_sw'; init{end+1} = 'k_sw = 0;'; %#ok<AGROW>
            w = gated_noise('k_sw', ps, on, 10^(p.jsr_db/10));
        case 'reactive_jamming'
            w = sprintf(['w = complex(zeros(Ns, 1));\nfor i = 1:Ns\n    if abs(ys(i))^2 > %.8f\n' ...
                '        w(i) = sqrt(%.8f/2) * complex(randn, randn);\n    end\nend\n'], ...
                p.reactive_threshold / sps, 10^(p.jsr_db/10));
        case 'spoofing'
            pers{end+1} = 'spoof_txf'; %#ok<AGROW>
            init{end+1} = sprintf(['spoof_txf = comm.RaisedCosineTransmitFilter(''RolloffFactor'', %.6f, ' ...
                '''FilterSpanInSymbols'', %d, ''OutputSamplesPerSymbol'', %d);'], p.rolloff, p.filter_span, sps); %#ok<AGROW>
            w = sprintf(['nSym = floor(Ns / %d);\n' ...
                'sp = spoof_txf(pskmod(randi([0 1], nSym*2, 1), 4, pi/4, ''gray'', ''InputType'', ''bit''));\n' ...
                'w = %.8f * sp(1:Ns);\n'], sps, 10^(p.spoof_sir_db/20));
        otherwise
            error('build_threat_model: unsupported threat component ''%s''', comp);
    end
    fI = sprintf('fI%d', c); pI = sprintf('pI%d', c);
    pers{end+1} = fI; init{end+1} = sprintf('%s = fd * cos(2*pi*rand(32, %d));', fI, nr); %#ok<AGROW>
    pers{end+1} = pI; init{end+1} = sprintf('%s = 2*pi*rand(32, %d);', pI, nr); %#ok<AGROW>
    body{end+1} = [w sos_gains('dI', fI, pI, p) sprintf([ ...
        'aI = exp(-1j * %.12f * (0:%d).'' * sind(aoa(%d) + yaw * t(1)));\n' ...
        'for k = 1:%d\n' ...
        '    y(:, k) = y(:, k) + w .* (sqrt(Ki/(Ki+1)) * aI(k) + sqrt(1/(Ki+1)) * dI(:, k));\n' ...
        'end\n'], 2*pi*p.ant_spacing_wl, nr-1, c, nr)]; %#ok<AGROW>
end
if p.chain_amp_db > 0 || p.chain_phase_deg > 0
    % receive chains: a gain and phase error per antenna, fixed for the flight (everything
    % the antenna receives passes its chain)
    pers{end+1} = 'gch'; %#ok<AGROW>
    init{end+1} = sprintf('gch = 10.^(%.6f * randn(1, %d) / 20) .* exp(1j * %.8f * randn(1, %d));', ...
        p.chain_amp_db, nr, deg2rad(p.chain_phase_deg), nr); %#ok<AGROW>
    body{end+1} = sprintf('for k = 1:%d\n    y(:, k) = y(:, k) * gch(k);\nend\n', nr); %#ok<AGROW>
end

pers = [{'nI'}, pers]; init = [{'nI = 0;'}, init];
head = sprintf('function [y, act] = fcn(u, seed, fd, aoa, kdb, yaw, rho)\n%%#codegen\npersistent seeded\n');
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
NS = L.n_sig;                             % symbols carrying our signal
TM = round(p.timing_max_sym * p.sps);     % arrival window [samples]
QN = L.NQ * p.sps;                        % quiet-slot samples before the leading pulse tail of the frame
if QN < 4 * nr
    error('build_threat_model: quiet slot too short for the interference covariance');
end
c = {
    'function [bits, iqa, z, Hq, Rq, sy] = fcn(u, txbits)'
    '%#codegen'
    'persistent rxf'
    sprintf('NR = %d; SPS = %d; Dt = %d; B = %d; MODE = %d; IDEAL = %d; DDI = %d; HW = %d;', nr, p.sps, Dt, B, mode, ideal, p.rx_dd_iter, ceil((p.pilot_every + p.pilot_block) / 2) + 4)
    sprintf('FS = %.1f; SR = %.1f; NSTF = %d; LS = %d; NLTF = %d; LL = %d;', p.symbol_rate * p.sps, p.symbol_rate, ...
        numel(L.stf), p.stf_len, numel(L.ltf), p.ltf_len)
    sprintf('NS = %d; ND = %d; NP = %d; PB = %d; NB = %d; TM = %d; LC = %.1f; QN = %d; NPRE = %d; SEGL = %d;', NS, L.n_data, L.n_pil, ...
        p.pilot_block, numel(L.pil_center), TM, L.ltf_center - L.NQ, QN, L.n_pre, numel(L.ltf))
    sprintf('LTF = %s;', cvec2(L.ltf))
    sprintf('PRE = %s;', cvec2(L.pre))
    sprintf('NFFT = 512; FB = %d;', ceil((2 * p.cfo_ppm * 1e-6 * p.carrier_freq + p.v_max * p.carrier_freq / p.c_light) / p.symbol_rate * 512))
    sprintf('PIL = %s;', cvec2(L.pil))
    sprintf('IDXD = %s;', mat2str(L.idx_data(:) - L.NQ))
    sprintf('IDXP = %s;', mat2str(L.idx_pil(:) - L.NQ))
    sprintf('PC = %s;', mat2str(L.pil_center(:) - L.NQ))
    'if isempty(rxf)'
    sprintf(['    rxf = comm.RaisedCosineReceiveFilter(''RolloffFactor'', %.6f, ''FilterSpanInSymbols'', %d, ' ...
        '''InputSamplesPerSymbol'', SPS, ''DecimationFactor'', 1);'], p.rolloff, p.filter_span)
    'end'
    'iqa = u;'
    'rf = rxf(u);'
    'Ns = size(rf, 1);'
    'base = Dt * SPS + QN;'
    'sy = zeros(5, 1);'
    'y = complex(zeros(NS, NR));'
    'yw = complex(zeros(NS, NR));'
    'Wi = complex(eye(NR));'
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
    '    % out more over its search window is kept.'
    '    Rq0 = complex(zeros(NR, NR));'
    '    for m = 1:QN'
    '        v = rf(m, :).'';'
    '        Rq0 = Rq0 + v * v'';'
    '    end'
    '    Rq0 = (Rq0 + Rq0'') / (2 * QN);'
    '    Rt0 = complex(zeros(NR, NR));'
    '    for m = base + 1 : base + TM + NPRE*SPS'
    '        v = rf(m, :).'';'
    '        Rt0 = Rt0 + v * v'';'
    '    end'
    '    Rt0 = (Rt0 + Rt0'') / (2 * (TM + NPRE*SPS));'
    '    lag = LS * SPS;'
    '    best = -1; d = 0; fc = 0; pk = 0; m2 = 0; im = 1; met = zeros(TM + 1, 1);'
    '    W = complex(eye(NR)); Wi = complex(eye(NR)); rws = complex(zeros(Ns, NR)); hsel = 1;'
    '    Wsel = complex(eye(NR)); Lsel = ones(NR, 1); Vsel = complex(eye(NR));'
    '    for hyp = 1:3'
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
    '                ma = base + (sg-1)*SEGL*SPS + 1; mb = min(Ns, base + sg*SEGL*SPS + TM);'
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
    '        mh = zeros(TM + 1, 1); PF = zeros(NFFT, TM + 1);'
    '        NSG = 1;'
    '        if hyp == 3'
    '            NSG = ceil(NPRE / SEGL);'
    '        end'
    '        for dd = 0:TM'
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
    '        [pkh, imh] = max(mh);'
    '        [~, bb] = max(PF(:, imh));'
    '        kb = bb - 1;'
    '        if kb >= NFFT / 2'
    '            kb = kb - NFFT;'
    '        end'
    '        p0 = PF(bb, imh); pmn = PF(mod(bb - 2, NFFT) + 1, imh); ppl = PF(mod(bb, NFFT) + 1, imh);'
    '        den = pmn - 2*p0 + ppl; de = 0;'
    '        if den < 0'
    '            de = 0.5 * (pmn - ppl) / den;'
    '        end'
    '        fch = (kb + de) * SR / NFFT;'
    '        Wh = Wsel; lh = Lsel; Vh = Vsel;'
    '        qh = pkh / max(mean(mh), 1e-30);'
    '        if qh > best'
    '            best = qh; d = imh - 1; im = imh; fc = fch; pk = pkh; met = mh;'
    '            W = Wh; Wi = Vh * diag(sqrt(lh)) * Vh''; rws(:, :) = rwh; hsel = hyp;'
    '        end'
    '    end'
    '    for dd = 0:TM'
    '        if abs(dd - d) > SPS && met(dd + 1) > m2'
    '            m2 = met(dd + 1);'
    '        end'
    '    end'
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
    '    ph2 = exp(-1j*2*pi*ff*(0:NS-1).''/SR);'
    '    for a = 1:NR'
    '        y(:, a) = y(:, a) .* ph2;'
    '        yw(:, a) = yw(:, a) .* ph2;'
    '    end'
    '    fr = 0;'
    '    if im > 1 && im < TM + 1'
    '        den = met(im-1) - 2*met(im) + met(im+1);'
    '        if den < 0'
    '            fr = 0.5 * (met(im-1) - met(im+1)) / den;'
    '        end'
    '    end'
    '    sy = [d; fc + ff; best; m2 / max(pk, 1e-30); fr];'
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
    '    % residual frequency from the phase progression over the pilot blocks (the long'
    '    % baseline across the frame), removed from the samples and the estimates'
    '    for it = 1:2'
    '        G = complex(0);'
    '        for b = 2:NB'
    '            G = G + Hp(:, b+1)'' * Hp(:, b);'
    '        end'
    '        df = -angle(G) / (2*pi*(PC(2) - PC(1))/SR);'
    '        sy(2) = sy(2) + df;'
    '        ph3 = exp(-1j*2*pi*df*(0:NS-1).''/SR);'
    '        for a = 1:NR'
    '            y(:, a) = y(:, a) .* ph3;'
    '            yw(:, a) = yw(:, a) .* ph3;'
    '        end'
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
    '    % first pass. MRC: the pilot channel of the antennas. MMSE: per window, whitening'
    '    % with the covariance of the window and its neighbourhood (every sample: the'
    '    % interferer as it is there), the nearest known symbols estimate the channel in'
    '    % the same whitened domain, and MRC there (= MVDR); the null follows an interferer'
    '    % channel that changes within the frame'
    '    nb = max(1, floor(ND / B));'
    '    for bi = 1:nb'
    '        i0 = (bi-1)*B + 1; i1 = bi*B; if bi == nb, i1 = ND; end'
    '        if MODE == 2'
    '            kA = max(1, IDXD(i0) - HW); kB = min(NS, IDXD(i1) + HW);'
    '            R = complex(zeros(NR, NR));'
    '            for k = kA:kB'
    '                v = y(k, :).'';'
    '                R = R + v * v'';'
    '            end'
    '            R = (R + R'') / (2 * (kB - kA + 1));'
    '            [V, D] = eig(R);'
    '            lr = max(real(diag(D)), 1e-6 * max(real(diag(D))) + 1e-30);'
    '            Wl = V * diag(1 ./ sqrt(lr)) * V'';'
    '            hl = complex(zeros(NR, 1)); nk = 0;'
    '            for k = 1:NLTF'
    '                kk = NSTF + k;'
    '                if kk >= kA && kk <= kB'
    '                    hl = hl + Wl * y(kk, :).'' * conj(LTF(k)); nk = nk + 1;'
    '                end'
    '            end'
    '            for qq = 1:NP'
    '                kk = IDXP(qq);'
    '                if kk >= kA && kk <= kB'
    '                    hl = hl + Wl * y(kk, :).'' * conj(PIL(qq)); nk = nk + 1;'
    '                end'
    '            end'
    '            hl = hl / max(nk, 1);'
    '            g = real(hl'' * hl);'
    '            for m = i0:i1'
    '                if g > 1e-12'
    '                    z(m) = (hl'' * (Wl * y(IDXD(m), :).'')) / g;'
    '                end'
    '            end'
    '        else'
    '            for m = i0:i1'
    '                k = IDXD(m);'
    '                h = Hk(:, k);'
    '                g = real(h'' * h);'
    '                if g > 1e-12'
    '                    z(m) = (h'' * y(k, :).'') / g;'
    '                end'
    '            end'
    '        end'
    '    end'
    '    % second pass, decision directed: the first-pass decisions act as known symbols;'
    '    % per window the leave-one-out LS channel and the residual covariance follow an'
    '    % interferer channel that changes within the frame'
    '    sh = (sign(real(z)) + 1j * sign(imag(z))) / sqrt(2);'
    '    sh(real(sh) == 0) = sh(real(sh) == 0) + 1 / sqrt(2);'
    '    sh(imag(sh) == 0) = sh(imag(sh) == 0) + 1j / sqrt(2);'
    '    for it = 1:DDI'
    '    if it > 1'
    '        sh = (sign(real(z)) + 1j * sign(imag(z))) / sqrt(2);'
    '    end'
    '    for bi = 1:nb'
    '        i0 = (bi-1)*B + 1; i1 = bi*B; if bi == nb, i1 = ND; end; n = i1 - i0 + 1;'
    '        hs = complex(zeros(NR, 1));'
    '        for m = i0:i1'
    '            v = y(IDXD(m), :).'';'
    '            hs = hs + v * conj(sh(m));'
    '        end'
    '        h = hs / n;'
    '        Ri = complex(eye(NR));'
    '        if MODE == 2'
    '            R = complex(zeros(NR, NR));'
    '            for m = i0:i1'
    '                e = y(IDXD(m), :).'' - h * sh(m);'
    '                R = R + e * e'';'
    '            end'
    '            R = R / n;'
    '            R = R + (1e-3 * real(trace(R)) / NR + 1e-12) * eye(NR);'
    '            Ri = inv(R);'
    '        end'
    '        for m = i0:i1'
    '            v = y(IDXD(m), :).'';'
    '            hm = (hs - v * conj(sh(m))) / (n - 1);'
    '            w = Ri * hm;'
    '            g = w'' * hm;'
    '            if abs(g) > 1e-12'
    '                z(m) = (w'' * v) / g;'
    '            end'
    '        end'
    '    end'
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
    };
s = sprintf('%s\n', c{:});
end

%% ===================== Helpers =====================
function g = tone_gain(p)
% Power of a unit-JSR tone: a noise jammer of power JSR per sample puts JSR/sps
% into our band after the receive filter, a tone inside the passband puts all of
% its power there, so the tone gets JSR/sps for the same in-band ratio.
g = 1 / p.sps;
end

function w = gated_noise(k, period, on, pw)
w = sprintf(['w = complex(zeros(Ns, 1));\nfor i = 1:Ns\n    if mod(%s, %d) < %d\n' ...
    '        w(i) = sqrt(%.8f/2) * complex(randn, randn);\n    end\n    %s = %s + 1;\nend\n'], ...
    k, period, on, pw, k, k);
end

function c = sos_init(fv, pv, nr)
% Random Doppler frequencies fd*cos(alpha) and phases of 32 sinusoids per antenna.
c = sprintf(['if isempty(%s)\n    %s = fd * cos(2*pi*rand(32, %d));\nend\n' ...
    'if isempty(%s)\n    %s = 2*pi*rand(32, %d);\nend\n'], fv, fv, nr, pv, pv, nr);
end

function c = sos_gains(dv, fv, pv, p)
% Unit-power Rayleigh gains (Ns x n_rx) from the sinusoids at times t, then the
% receive correlation (Cholesky factor of rho^|i-j|).
nr = p.n_rx;

c = sprintf(['%s = complex(zeros(Ns, %d));\n' ...
    'for k = 1:%d\n' ...
    '    %s(:, k) = exp(1j * (2*pi*t*%s(:, k).'' + repmat(%s(:, k).'', Ns, 1))) * ones(32, 1) / sqrt(32);\n' ...
    'end\n' ...
    'Rr = zeros(%d, %d);\nfor i = 1:%d\n    for j = 1:%d\n        Rr(i, j) = rho ^ abs(i - j);\n    end\nend\n' ...
    '%s = %s * chol(Rr);\n'], dv, nr, nr, dv, fv, pv, nr, nr, nr, nr, dv, dv);
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
    'corr_random', false, 'corr_range', [0.3 0.9], 'shadow_k_db', -16, 'fault_atten_db', 31, ...
    'chain_amp_db', 0, 'chain_phase_deg', 0, ...
    'stf_len', 4, 'stf_rep', 10, 'ltf_len', 16, 'ltf_rep', 2, 'pilot_block', 4, 'pilot_every', 48, ...
    'rx_sync', 'ideal', 'cfo_ppm', 25, 'timing_max_sym', 4, 'rx_dd_iter', 2);
f = fieldnames(d);
for i = 1:numel(f)
    if ~isfield(p, f{i}), p.(f{i}) = d.(f{i}); end
end
p.ant_spacing_wl = p.ant_aperture_m / (3e8 / p.carrier_freq) / max(p.n_rx - 1, 1);   % same aperture for 2 or 3 antennas
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
