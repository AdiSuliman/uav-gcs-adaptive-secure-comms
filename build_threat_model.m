function build_threat_model()
%% BUILD_THREAT_MODEL - GCS -> UAV link with a multi-antenna UAV receiver (D41)
% [Tx: QPSK+RRC] -> [Channel: Rician per UAV antenna] -> [Threat] -> [AWGN per antenna]
%   -> [Rx: RRC per antenna, coherent combining, QPSK demod]
%
% Link: command uplink, single GCS antenna -> p.n_rx omni antennas on the UAV
% (ULA, spacing p.ant_spacing_wl). The GCS antenna gain is part of Eb/N0.
% Eb/N0 is per receive antenna (per branch).
%
% Channel   LoS steering vector (direction p.gcs_aoa_deg) + diffuse Rayleigh part
%           (sum of 32 sinusoids per antenna with random Doppler angles and phases,
%           Jakes spectrum up to fd; receive correlation p.rx_corr), K = p.rician_k.
% Threat    signal-side threats scale our signal (antenna_fault hits antenna 1 only);
%           every additive threat is ONE waveform arriving through its own spatial
%           channel (direction p.int_aoa_deg(c), own diffuse fading).
% Rx        data-aided estimation per window (transmitted symbols known = ideal
%           pilots): h = LS channel estimate from the OTHER symbols of the window
%           (leave-one-out, so a symbol never helps estimate its own channel),
%           Rin = covariance of the residual r - h*s (interference + noise).
%           'mrc'  : w = h,          window p.csi_block symbols (baseline)
%           'mmse' : w = Rin^-1 * h, window p.mmse_window symbols (spatial_diversity
%                    action: nulls up to n_rx-1 interferers, tracks a faulty branch)
%           Output 2 = antenna-1 received IQ (sensing tap for the detector).
% Seeds     p.seed, or drawn from the global stream when empty; channel, interferer
%           channels, threat waveforms, AWGN and bit source all derive from it.
%           Seed and Doppler reach the blocks through the Constant blocks 'Seed' and
%           'Doppler', so link_seed.m changes them without a rebuild and the compiled
%           block code is reused across seeds and UAV speeds.

modelName = 'UAV_GCS_Threat_Link';

if ~exist('params.mat', 'file')
    error('params.mat not found. Run init_params.m first.');
end
S = load('params.mat');
p = S.params;
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
add_block('simulink/Sinks/To Workspace', [modelName '/tx_sink'], 'Position', [150 30 230 60]);
add_block('simulink/Sinks/To Workspace', [modelName '/rx_sink'], 'Position', [870 90 950 120]);
add_block('simulink/Sinks/To Workspace', [modelName '/Tx_IQ'],   'Position', [300 30 380 60]);
add_block('simulink/Sinks/To Workspace', [modelName '/Rx_IQ'],   'Position', [870 150 950 180]);

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

%% ---- Wiring ----
add_line(modelName, 'BitSource/1', 'Tx/1',      'autorouting', 'on');
add_line(modelName, 'Tx/1',        'Channel/1', 'autorouting', 'on');
add_line(modelName, 'Seed/1',      'Channel/2', 'autorouting', 'on');
add_line(modelName, 'Doppler/1',   'Channel/3', 'autorouting', 'on');
add_line(modelName, 'Seed/1',      'Threat/2',  'autorouting', 'on');
add_line(modelName, 'Doppler/1',   'Threat/3',  'autorouting', 'on');
add_line(modelName, 'Channel/1',   'Threat/1',  'autorouting', 'on');
add_line(modelName, 'Threat/1',    'AWGN/1',    'autorouting', 'on');
add_line(modelName, 'AWGN/1',      'Rx/1',      'autorouting', 'on');
add_line(modelName, 'BitSource/1', 'Rx/2',      'autorouting', 'on');
add_line(modelName, 'BitSource/1', 'tx_sink/1', 'autorouting', 'on');
add_line(modelName, 'Rx/1',        'rx_sink/1', 'autorouting', 'on');
add_line(modelName, 'Tx/1',        'Tx_IQ/1',   'autorouting', 'on');
add_line(modelName, 'Rx/2',        'Rx_IQ/1',   'autorouting', 'on');

set_param(modelName, 'SolverType', 'Fixed-step', 'Solver', 'FixedStepDiscrete', 'StopTime', '0.01');
link_seed(modelName, seed, p.fd_max);

%% ---- Save ----
if ~exist('models', 'dir'); mkdir('models'); end
save_system(modelName, ['models/' modelName '.slx']);
fprintf('Model saved to models/%s.slx\n', modelName);
fprintf('Done. threat=%s, JSR=%.1f dB, K=%.1f dB, fd=%.1f Hz, n_rx=%d, rho=%.2f, Rx=%s.\n', ...
    p.active_threat, p.jsr_db, p.rician_k, p.fd_max, nr, p.rx_corr, p.rx_combiner);
end

%% ===================== Block scripts =====================
function s = tx_script(p)
s = sprintf([ ...
    'function y = fcn(bits)\n' ...
    '%%#codegen\n' ...
    'persistent txf\n' ...
    'if isempty(txf)\n' ...
    '    txf = comm.RaisedCosineTransmitFilter(''RolloffFactor'', %.6f, ''FilterSpanInSymbols'', %d, ''OutputSamplesPerSymbol'', %d);\n' ...
    'end\n' ...
    'sym = pskmod(bits, 4, pi/4, ''gray'', ''InputType'', ''bit'');\n' ...
    'y = txf(sym);\n' ...
    'end\n'], p.rolloff, p.filter_span, p.sps);
end

function s = channel_script(p, fs)
% Signal channel: LoS steering vector toward the GCS + correlated diffuse fading.
nr = p.n_rx;
K  = 10^(p.rician_k/10);
a  = steering(p, p.gcs_aoa_deg);
s = [sprintf('function y = fcn(x, seed, fd)\n%%%%#codegen\npersistent f0 ph n\n') ...
    sprintf('if isempty(f0)\n    rng(seed, ''twister'');\nend\n') ...
    sos_init('f0', 'ph', nr) ...
    sprintf('if isempty(n)\n    n = 0;\nend\nNs = size(x, 1);\nt = (n + (0:Ns-1).'') / %.1f;\nn = n + Ns;\n', fs) ...
    sos_gains('D', 'f0', 'ph', p) ...
    sprintf(['a = %s;\n' ...
    'y = complex(zeros(Ns, %d));\n' ...
    'for k = 1:%d\n' ...
    '    y(:, k) = x .* (%.10f * a(k) + %.10f * D(:, k));\n' ...
    'end\n' ...
    'end\n'], cvec(a), nr, nr, sqrt(K/(K+1)), sqrt(1/(K+1)))];
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
sig  = parts(ismember(parts, {'path_loss', 'antenna_fault'}));
addc = parts(~ismember(parts, {'path_loss', 'antenna_fault'}));
if numel(addc) > numel(p.int_aoa_deg)
    error('build_threat_model: %d additive components, only %d interferer directions', numel(addc), numel(p.int_aoa_deg));
end

pers = {}; init = {}; body = {};
body{end+1} = sprintf('Ns = size(u, 1);\ny = u;\nt = (nI + (0:Ns-1).'') / %.1f;\nnI = nI + Ns;\n', fs);

for i = 1:numel(sig)
    switch sig{i}
        case 'path_loss'
            body{end+1} = sprintf('y = y * %.8f;\n', 10^(-p.path_loss_db/20)); %#ok<AGROW>
        case 'antenna_fault'
            ps = p.fault_period * sps; on = round(p.fault_duty * ps);
            pers{end+1} = 'k_af'; init{end+1} = 'k_af = 0;'; %#ok<AGROW>
            body{end+1} = sprintf(['for i = 1:Ns\n    if mod(k_af, %d) < %d\n' ...
                '        y(i, 1) = y(i, 1) * %.8f;\n    end\n' ...
                '    k_af = k_af + 1;\nend\n'], ps, on, 10^(-p.fault_atten_db/20)); %#ok<AGROW>
    end
end
if ~isempty(addc)
    body{end+1} = sprintf('ys = y(:, 1);\n');       % our signal as the reactive jammer senses it
end

Ki = 10^(p.int_rician_k/10);
for c = 1:numel(addc)
    comp = addc{c};
    switch comp
        case 'jamming'
            w = sprintf('w = sqrt(%.8f/2) * complex(randn(Ns, 1), randn(Ns, 1));\n', 10^(p.jsr_db/10));
        case 'benign_interference'
            w = sprintf('w = sqrt(%.8f/2) * complex(randn(Ns, 1), randn(Ns, 1));\n', 10^(p.benign_int_db/10));
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
    aI = steering(p, p.int_aoa_deg(c));
    body{end+1} = [w sos_gains('dI', fI, pI, p) sprintf([ ...
        'aI = %s;\n' ...
        'for k = 1:%d\n' ...
        '    y(:, k) = y(:, k) + w .* (%.10f * aI(k) + %.10f * dI(:, k));\n' ...
        'end\n'], cvec(aI), nr, sqrt(Ki/(Ki+1)), sqrt(1/(Ki+1)))]; %#ok<AGROW>
end

pers = [{'nI'}, pers]; init = [{'nI = 0;'}, init];
head = sprintf('function y = fcn(u, seed, fd)\n%%#codegen\npersistent seeded\n');
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
% Per-antenna matched filter; per window: LS channel estimate from the known symbols,
% residual covariance, MRC or MMSE weights; QPSK demod.
nr = p.n_rx;
Dt = p.filter_span;                       % Tx + Rx filter delay [symbols]
switch lower(p.rx_combiner)
    case 'mrc',  mode = 1; B = p.csi_block;
    case 'mmse', mode = 2; B = p.mmse_window;
    otherwise, error('build_threat_model: unknown rx_combiner ''%s''', p.rx_combiner);
end
s = sprintf([ ...
    'function [bits, iq1] = fcn(u, txbits)\n' ...
    '%%#codegen\n' ...
    'persistent rxf sbuf\n' ...
    'NR = %d; SPS = %d; Dt = %d; B = %d; MODE = %d;\n' ...
    'if isempty(rxf)\n' ...
    '    rxf = comm.RaisedCosineReceiveFilter(''RolloffFactor'', %.6f, ''FilterSpanInSymbols'', %d, ' ...
    '''InputSamplesPerSymbol'', SPS, ''DecimationFactor'', SPS);\n' ...
    'end\n' ...
    'if isempty(sbuf)\n' ...
    '    sbuf = complex(zeros(Dt, 1));\n' ...
    'end\n' ...
    'iq1 = u(:, 1);\n' ...
    'r = rxf(u);\n' ...
    'Nsym = size(r, 1);\n' ...
    'st = pskmod(txbits, 4, pi/4, ''gray'', ''InputType'', ''bit'');\n' ...
    'sa = [sbuf; st(1:Nsym-Dt)];\n' ...
    'sbuf = st(Nsym-Dt+1:Nsym);\n' ...
    'z = complex(zeros(Nsym, 1));\n' ...
    'nb = ceil(Nsym / B);\n' ...
    'for bi = 1:nb\n' ...
    '    i0 = (bi-1)*B + 1; i1 = min(bi*B, Nsym); n = i1 - i0 + 1;\n' ...
    '    h = complex(zeros(NR, 1));\n' ...
    '    es = 0;\n' ...
    '    for m = i0:i1\n' ...
    '        h = h + r(m, :).'' * conj(sa(m));\n' ...
    '        es = es + abs(sa(m))^2;\n' ...
    '    end\n' ...
    '    hs = h;\n' ...
    '    h = h / max(es, 1e-12);\n' ...
    '    Ri = complex(eye(NR));\n' ...
    '    if MODE == 2\n' ...
    '        R = complex(zeros(NR, NR));\n' ...
    '        for m = i0:i1\n' ...
    '            e = r(m, :).'' - h * sa(m);\n' ...
    '            R = R + e * e'';\n' ...
    '        end\n' ...
    '        R = R / n;\n' ...
    '        R = R + (1e-3 * real(trace(R)) / NR + 1e-12) * eye(NR);\n' ...
    '        Ri = inv(R);\n' ...
    '    end\n' ...
    '    for m = i0:i1\n' ...
    '        hm = (hs - r(m, :).'' * conj(sa(m))) / max(es - abs(sa(m))^2, 1e-12);\n' ...
    '        w = Ri * hm;\n' ...
    '        z(m) = w'' * r(m, :).'';\n' ...
    '    end\n' ...
    'end\n' ...
    'bits = pskdemod(z, 4, pi/4, ''gray'', ''OutputType'', ''bit'');\n' ...
    'end\n'], nr, p.sps, Dt, B, mode, p.rolloff, p.filter_span);
end

%% ===================== Helpers =====================
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
Rr = p.rx_corr .^ abs((1:nr)' - (1:nr));
C  = chol(Rr);
c = sprintf(['%s = complex(zeros(Ns, %d));\n' ...
    'for k = 1:%d\n' ...
    '    %s(:, k) = exp(1j * (2*pi*t*%s(:, k).'' + repmat(%s(:, k).'', Ns, 1))) * ones(32, 1) / sqrt(32);\n' ...
    'end\n' ...
    '%s = %s * %s;\n'], dv, nr, nr, dv, fv, pv, dv, dv, mat2str(C, 12));
end

function a = steering(p, aoa_deg)
% ULA steering vector, element k at (k-1)*spacing, direction measured from broadside.
k = (0:p.n_rx-1).';
a = exp(-1j * 2*pi * p.ant_spacing_wl * k * sind(aoa_deg));
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
% Defaults for params.mat files written before D41.
d = struct('n_rx', 2, 'ant_spacing_wl', 0.5, 'rx_corr', 0.3, 'gcs_aoa_deg', 0, ...
    'int_aoa_deg', [40 -55 70], 'int_rician_k', p.rician_k, 'rx_combiner', 'mrc', ...
    'csi_block', 64, 'mmse_window', 32, 'seed', []);
f = fieldnames(d);
for i = 1:numel(f)
    if ~isfield(p, f{i}), p.(f{i}) = d.(f{i}); end
end
end
