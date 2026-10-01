function cfg = dataset_levels()
%DATASET_LEVELS  Threats of the detector dataset and their severity levels: one
%   definition for run_dataset_sweep.m, eval_unseen_snr.m and eval_unseen_severity.m.
%   cfg(i): name, param (params field of the severity), levels (8 per threat).
%   The levels span the range of the decision layer (decision_config.m) and of the
%   survivability map, up to the most severe value of the sources: in-band
%   interferers up to 30 dB over our signal (Liu et al.); a spoofer on the same
%   hardware as the jammer, up to the same 30 dB (it captures the receiver from a
%   0.2-3 dB advantage, Whitehouse et al.; Mekdad et al.); WLAN packets up to 30 dB;
%   path loss up to 22 dB (building blockage, Cui et al.); airframe shadowing up to
%   40 dB (Sun). A threat as strong as the sources measured is then never "stronger
%   than anything seen" for the unknown-threat score.
jsr = [0 4 8 12 16 20 25 30];
cfg = struct('name', {}, 'param', {}, 'levels', {});
cfg(1)  = struct('name', 'jamming',             'param', 'jsr_db',        'levels', jsr);
cfg(2)  = struct('name', 'noise_burst',         'param', 'jsr_db',        'levels', jsr);
cfg(3)  = struct('name', 'reactive_jamming',    'param', 'jsr_db',        'levels', jsr);
cfg(4)  = struct('name', 'path_loss',           'param', 'path_loss_db',  'levels', [4 7 10 13 16 18 20 22]);
cfg(5)  = struct('name', 'spoofing',            'param', 'spoof_sir_db',  'levels', [-4 0 3 6 10 15 22 30]);
cfg(6)  = struct('name', 'antenna_fault',       'param', 'fault_duty',    'levels', [0.05 0.1 0.15 0.2 0.3 0.4 0.5 0.6]);
cfg(7)  = struct('name', 'benign_interference', 'param', 'benign_int_db', 'levels', [-12 -8 -4 0 5 12 20 30]);
cfg(8)  = struct('name', 'sweeping_jammer',     'param', 'jsr_db',        'levels', jsr);
cfg(9)  = struct('name', 'tone_jamming',        'param', 'tone_jsr_db',   'levels', jsr);
cfg(10) = struct('name', 'airframe_shadowing',  'param', 'shadow_db',     'levels', [5 10 15 20 25 30 35 40]);
end
