%% VALIDATE_NEW_THREATS — Quick sanity check for benign_interference + sweeping_jammer
% Standalone, one-shot BER check for the 2 newly-added threats, BEFORE touching
% run_dataset_sweep.m, extract_spectrograms.m, or any training pipeline.
% Confirms the new case blocks in build_threat_model.m work and produce
% sensible BER (benign should be close to 'none'; sweeping should sit between
% noise_burst and full jamming).

close all; clc;
fprintf('=== Validate New Threats: benign_interference + sweeping_jammer ===\n\n');

init_params;
p0 = load('params.mat').params;

test_threats = {'none', 'benign_interference', 'noise_burst', 'sweeping_jammer', 'jamming'};

fprintf('%-22s %12s\n', 'Threat', 'BER');
for i = 1:numel(test_threats)
    p = p0;
    p.active_threat = test_threats{i};
    params = p; save('params.mat', 'params');
    build_threat_model;
    ber = quick_ber('UAV_GCS_Threat_Link');
    fprintf('%-22s %12.3e\n', test_threats{i}, ber);
end

% Restore baseline
params = p0; save('params.mat', 'params');

fprintf('\nExpected sanity ordering: none < benign_interference < noise_burst <~ sweeping_jammer < jamming\n');
fprintf('=== Validation Complete ===\n');