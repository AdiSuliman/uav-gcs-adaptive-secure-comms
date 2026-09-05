function build_rician_model()
%% BUILD_RICIAN_MODEL - Phase A3 Step 1: Rician fading + AWGN (no sync)
% Tx -> QPSK_Mod -> Rician(fading) -> AWGN(noise) -> QPSK_Demod -> BER
% Demonstrates 1.46x BER degradation vs theory due to 160 Hz Doppler
% Motivates adaptive link recovery in later phases.

modelName = 'UAV_GCS_Rician_Link';

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

fprintf('Building model "%s"...\n', modelName);

%% ---- Add blocks ----
add_block('commrandsrc3/Bernoulli Binary Generator', ...
    [modelName '/BitSource'], 'Position', [30 100 90 140]);
add_block('commdigbbndpm3/QPSK Modulator Baseband', ...
    [modelName '/QPSK_Mod'], 'Position', [150 100 210 140]);
add_block('simulink/User-Defined Functions/MATLAB Function', ...
    [modelName '/Rician'], 'Position', [270 100 350 140]);
add_block('commchan3/AWGN Channel', ...
    [modelName '/AWGN'], 'Position', [410 100 470 140]);
add_block('commdigbbndpm3/QPSK Demodulator Baseband', ...
    [modelName '/QPSK_Demod'], 'Position', [530 100 590 140]);
add_block('commsink2/Error Rate Calculation', ...
    [modelName '/ErrRate'], 'Position', [650 130 730 180]);
add_block('simulink/Sinks/To Workspace', ...
    [modelName '/Tx_IQ'], 'Position', [270 30 350 60]);
add_block('simulink/Sinks/To Workspace', ...
    [modelName '/Rx_IQ'], 'Position', [410 180 490 210]);
add_block('simulink/Sinks/To Workspace', ...
    [modelName '/BER_out'], 'Position', [800 140 880 170]);

%% ---- Inject Rician code into the MATLAB Function block (Stateflow API) ----
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

%% ---- Configure blocks ----
Tsym = 1 / p.symbol_rate;
set_param([modelName '/BitSource'], ...
    'ProbabilityOfZero', '0.5', ...
    'SampleTime', num2str(Tsym / p.bits_per_symbol), ...
    'SamplesPerFrame', num2str(p.frame_length));
set_param([modelName '/QPSK_Mod'], 'InType', 'Bit');
set_param([modelName '/QPSK_Demod'], 'OutType', 'Bit');

% AWGN: start at a clean SNR (sweep will vary this later)
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
add_line(modelName, 'Rician/1',    'AWGN/1',      'autorouting','on');
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
fprintf('Done. Rician+AWGN link built (K=%.1f dB, fd=%.1f Hz, v=%.0f m/s, envelope %.0f-%.0f m/s).\n', ...
    p.rician_k, p.fd_max, p.v_nominal, p.v_min, p.v_max);
end