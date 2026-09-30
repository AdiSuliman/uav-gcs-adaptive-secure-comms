function cfg = dataset_levels()
%DATASET_LEVELS  Threats of the detector dataset and their severity levels: one
%   definition for run_dataset_sweep.m, eval_unseen_snr.m and eval_unseen_severity.m.
%   cfg(i): name, param (params field of the severity), levels (8 per threat).
%   The levels span the range of the decision layer (decision_config.m) and of the
%   survivability map: in-band interferers up to 28 dB over our signal (a 30 dB
%   jammer as in Liu et al.), path loss up to 25 dB, a spoofer up to 10 dB over our
%   signal, airframe shadowing up to 33 dB (above 35 dB measured, Khawaja et al.).
jsr = 0:4:28;
cfg = struct('name', {}, 'param', {}, 'levels', {});
cfg(1)  = struct('name', 'jamming',             'param', 'jsr_db',        'levels', jsr);
cfg(2)  = struct('name', 'noise_burst',         'param', 'jsr_db',        'levels', jsr);
cfg(3)  = struct('name', 'reactive_jamming',    'param', 'jsr_db',        'levels', jsr);
cfg(4)  = struct('name', 'path_loss',           'param', 'path_loss_db',  'levels', 4:3:25);
cfg(5)  = struct('name', 'spoofing',            'param', 'spoof_sir_db',  'levels', -4:2:10);
cfg(6)  = struct('name', 'antenna_fault',       'param', 'fault_duty',    'levels', [0.05 0.1 0.15 0.2 0.3 0.4 0.5 0.6]);
cfg(7)  = struct('name', 'benign_interference', 'param', 'benign_int_db', 'levels', -12:1.5:-1.5);
cfg(8)  = struct('name', 'sweeping_jammer',     'param', 'jsr_db',        'levels', jsr);
cfg(9)  = struct('name', 'tone_jamming',        'param', 'tone_jsr_db',   'levels', jsr);
cfg(10) = struct('name', 'airframe_shadowing',  'param', 'shadow_db',     'levels', 5:4:33);
end
