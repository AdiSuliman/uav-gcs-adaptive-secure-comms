function build_threat_model()
%% BUILD_THREAT_MODEL - Phase A4: Rician + AWGN + Threat Injection (signal-level, Approach A)
% Tx -> QPSK_Mod -> Rician -> [THREAT] -> AWGN -> QPSK_Demod -> BER
% Threats injected as real interference waveforms added to the IQ signal (Approach A).
% First threat: Barrage Jamming (additive wideband noise) after channel, before receiver noise.
% params.active_threat selects the threat; 'none' reproduces the A3 baseline.

modelName = 'UAV_GCS_Threat_Link';

if ~exist('params.mat', 'file')
    error('params.mat not found. Run init_params.m first.');
end
S = load('params.mat');
p = S.params;

if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
new_system(modelName);
open_system(modelName);

fprintf('Building model "%s" (threat: %s)...\n', modelName, p.active_threat);

%% ---- Add blocks ----
add_block('commrandsrc3/Bernoulli Binary Generator', ...
    [modelName '/BitSource'], 'Position', [30 100 90 140]);
add_block('commdigbbndpm3/QPSK Modulator Baseband', ...
    [modelName '/QPSK_Mod'], 'Position', [150 100 210 140]);
add_block('simulink/User-Defined Functions/MATLAB Function', ...
    [modelName '/Rician'], 'Position', [270 100 350 140]);
add_block('simulink/User-Defined Functions/MATLAB Function', ...
    [modelName '/Threat'], 'Position', [410 100 490 140]);
add_block('commchan3/AWGN Channel', ...
    [modelName '/AWGN'], 'Position', [550 100 610 140]);
add_block('commdigbbndpm3/QPSK Demodulator Baseband', ...
    [modelName '/QPSK_Demod'], 'Position', [670 100 730 140]);
add_block('commsink2/Error Rate Calculation', ...
    [modelName '/ErrRate'], 'Position', [800 130 880 180]);
add_block('simulink/Sinks/To Workspace', ...
    [modelName '/Tx_IQ'], 'Position', [270 30 350 60]);
add_block('simulink/Sinks/To Workspace', ...
    [modelName '/Rx_IQ'], 'Position', [550 180 630 210]);
add_block('simulink/Sinks/To Workspace', ...
    [modelName '/BER_out'], 'Position', [950 140 1030 170]);

%% ---- Inject Rician code (Stateflow API) ----
sf_root = sfroot;
chart = sf_root.find('-isa','Stateflow.EMChart','Path',[modelName '/Rician']);
k_linear = 10^(p.rician_k / 10);
chart.Script = sprintf([ ...
    'function y = fcn(u)\n' ...
    '%%#codegen\n' ...
    'persistent rc\n' ...
    'if isempty(rc)\n' ...
    '    rc = comm.RicianChannel(''KFactor'', %.6f, ...\n' ...
    '        ''MaximumDopplerShift'', %.6f, ''SampleRate'', %g);\n' ...
    'end\n' ...
    'y = rc(u);\n' ...
    'end\n'], k_linear, p.fd_max, p.symbol_rate);

%% ---- Inject Threat code (Stateflow API) ----
% Approach A: additive interference waveform. Barrage jamming = wideband complex Gaussian noise.
chart_th = sf_root.find('-isa','Stateflow.EMChart','Path',[modelName '/Threat']);
switch lower(p.active_threat)
    case 'jamming'
        jammerPower = 10^(p.jsr_db / 10);   % relative to unit-power QPSK signal
        chart_th.Script = sprintf([ ...
            'function y = fcn(u)\n' ...
            '%%#codegen\n' ...
            'jammerPower = %.6f;\n' ...
            'n = sqrt(jammerPower/2) * (randn(size(u)) + 1i*randn(size(u)));\n' ...
            'y = u + n;\n' ...
            'end\n'], jammerPower);
    otherwise   % 'none' -> passthrough (reproduces A3 baseline)
        chart_th.Script = sprintf([ ...
            'function y = fcn(u)\n' ...
            '%%#codegen\n' ...
            'y = u;\n' ...
            'end\n']);
end

%% ---- Configure blocks ----
Tsym = 1 / p.symbol_rate;
set_param([modelName '/BitSource'], ...
    'ProbabilityOfZero', '0.5', ...
    'SampleTime', num2str(Tsym / p.bits_per_symbol), ...
    'SamplesPerFrame', num2str(p.frame_length));
set_param([modelName '/QPSK_Mod'], 'InType', 'Bit');
set_param([modelName '/QPSK_Demod'], 'OutType', 'Bit');

snr0 = p.EbNo_dB(1) + 10*log10(p.bits_per_symbol);
set_param([modelName '/AWGN'], 'SNR', num2str(snr0));

set_param([modelName '/ErrRate'], 'PMode', 'Port');
for b = {'Tx_IQ','Rx_IQ','BER_out'}
    set_param([modelName '/' b{1}], 'SaveFormat', 'Array', ...
        'VariableName', b{1});
end

%% ---- Wire it up ----
add_line(modelName, 'BitSource/1', 'QPSK_Mod/1',  'autorouting','on');
add_line(modelName, 'QPSK_Mod/1',  'Rician/1',    'autorouting','on');
add_line(modelName, 'Rician/1',    'Threat/1',    'autorouting','on');
add_line(modelName, 'Threat/1',    'AWGN/1',      'autorouting','on');
add_line(modelName, 'AWGN/1',      'QPSK_Demod/1','autorouting','on');
add_line(modelName, 'BitSource/1', 'ErrRate/1',   'autorouting','on');
add_line(modelName, 'QPSK_Demod/1','ErrRate/2',   'autorouting','on');
add_line(modelName, 'QPSK_Mod/1',  'Tx_IQ/1',     'autorouting','on');
add_line(modelName, 'AWGN/1',      'Rx_IQ/1',     'autorouting','on');
add_line(modelName, 'ErrRate/1',   'BER_out/1',   'autorouting','on');

%% ---- Solver settings ----
set_param(modelName, 'SolverType', 'Fixed-step', ...
    'Solver', 'FixedStepDiscrete', ...
    'StopTime', '0.01');

%% ---- Save ----
if ~exist('models', 'dir'); mkdir('models'); end
save_system(modelName, ['models/' modelName '.slx']);
fprintf('Model saved to models/%s.slx\n', modelName);
fprintf('Done. Threat model built (threat=%s, JSR=%.1f dB, K=%.1f dB, fd=%.1f Hz).\n', ...
    p.active_threat, p.jsr_db, p.rician_k, p.fd_max);
end