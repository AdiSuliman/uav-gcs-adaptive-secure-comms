function build_link_model()
%% BUILD_LINK_MODEL - Programmatically builds the clean UAV-GCS link
% Phase A1: Tx -> AWGN Channel -> Rx -> BER (ideal sync, AWGN only)
% Driven by init_params.m. Saves a reusable .slx model.
% AWGN uses SNR mode; sweep converts Eb/No -> SNR:
%   SNR_dB = EbNo_dB + 10*log10(bits_per_symbol) - 10*log10(sps)

modelName = 'UAV_GCS_Base_Link';

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

%% ---- Add blocks (exact R2026a library paths) ----
add_block('commrandsrc3/Bernoulli Binary Generator', ...
    [modelName '/BitSource'], 'Position', [30 100 90 140]);
add_block('commdigbbndpm3/QPSK Modulator Baseband', ...
    [modelName '/QPSK_Mod'], 'Position', [150 100 210 140]);
add_block('commchan3/AWGN Channel', ...
    [modelName '/AWGN'], 'Position', [270 100 330 140]);
add_block('commdigbbndpm3/QPSK Demodulator Baseband', ...
    [modelName '/QPSK_Demod'], 'Position', [390 100 450 140]);
add_block('commsink2/Error Rate Calculation', ...
    [modelName '/ErrRate'], 'Position', [510 130 590 180]);
add_block('simulink/Sinks/To Workspace', ...
    [modelName '/Tx_IQ'], 'Position', [270 30 330 60]);
add_block('simulink/Sinks/To Workspace', ...
    [modelName '/Rx_IQ'], 'Position', [390 30 450 60]);
add_block('simulink/Sinks/To Workspace', ...
    [modelName '/BER_out'], 'Position', [660 140 740 170]);

%% ---- Configure blocks (driven by params) ----
Tsym = 1 / p.symbol_rate;

set_param([modelName '/BitSource'], ...
    'ProbabilityOfZero', '0.5', ...
    'SampleTime', num2str(Tsym / p.bits_per_symbol), ...
    'SamplesPerFrame', num2str(p.frame_length));

set_param([modelName '/QPSK_Mod'],   'InType',  'Bit');
set_param([modelName '/QPSK_Demod'], 'OutType', 'Bit');

% AWGN: default SNR mode; write only the SNR value
snr0 = p.EbNo_dB(1) + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
set_param([modelName '/AWGN'], 'SNR', num2str(snr0));

% Error Rate: switch to Port output so BER becomes a signal (not workspace)
set_param([modelName '/ErrRate'], 'PMode', 'Port');

for b = {'Tx_IQ','Rx_IQ','BER_out'}
    set_param([modelName '/' b{1}], 'SaveFormat', 'Array', ...
        'VariableName', b{1});
end

%% ---- Wire it up ----
add_line(modelName, 'BitSource/1', 'QPSK_Mod/1',  'autorouting','on');
add_line(modelName, 'QPSK_Mod/1',  'AWGN/1',      'autorouting','on');
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
fprintf('Done. Model is built and wired.\n');
end