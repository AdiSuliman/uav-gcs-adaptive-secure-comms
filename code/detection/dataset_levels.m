function cfg = dataset_levels()
%DATASET_LEVELS  Threats of the detector dataset and their severity levels: one
%   definition for run_dataset_sweep.m, eval_unseen_snr.m and eval_unseen_severity.m.
%   cfg(i): name, param (params field of the severity), levels (8 per threat).
%   The levels span the range of the decision layer (decision_config.m) and of the
%   survivability map, up to the most severe value of the sources: in-band
%   interferers up to 30 dB over our signal (Liu et al.); a spoofer on the same
%   radio as our GCS (Mekdad et al.), up to the same 30 dB by geometry (it captures
%   the receiver from a 0.2-3 dB advantage, Whitehouse et al.); WLAN packets up to
%   30 dB; path loss up to 22 dB (building blockage, Cui et al.); airframe shadowing
%   over the measured event depths, about 6-25 dB (Sun et al.); an antenna fault from a
%   partial loss to an open contact, 5-31 dB in eight even steps: a sustained diversity
%   imbalance above 5 dB marks a degraded antenna connection (Heath, US 10,404,368,
%   Table 2), a steady branch loss above 3 dB a loss in the RF path (Willgert,
%   US 8,548,029, Table 1), and real connector faults are small losses or intermittent
%   (Enquebecq et al.: fretting raises the loss by tenths of a dB; Smith et al. 2008);
%   the 26-36 dB of an open contact is a gap-capacitance estimate (0.01-0.03 pF). No
%   source gives the distribution of fault depths, so the levels are spread evenly over
%   the backed range. A threat as strong as the sources measured is then never
%   "stronger than anything seen" for the unknown-threat score.
jsr = [0 4 8 12 16 20 25 30];
cfg = struct('name', {}, 'param', {}, 'levels', {});
cfg(1)  = struct('name', 'jamming',             'param', 'jsr_db',        'levels', jsr);
cfg(2)  = struct('name', 'noise_burst',         'param', 'jsr_db',        'levels', jsr);
cfg(3)  = struct('name', 'reactive_jamming',    'param', 'jsr_db',        'levels', jsr);
cfg(4)  = struct('name', 'path_loss',           'param', 'path_loss_db',  'levels', [4 7 10 13 16 18 20 22]);
cfg(5)  = struct('name', 'spoofing',            'param', 'spoof_sir_db',  'levels', [-4 0 3 6 10 15 22 30]);
cfg(6)  = struct('name', 'antenna_fault',       'param', 'fault_atten_db', 'levels', linspace(5, 31, 8));
cfg(7)  = struct('name', 'benign_interference', 'param', 'benign_int_db', 'levels', [-12 -8 -4 0 5 12 20 30]);
cfg(8)  = struct('name', 'sweeping_jammer',     'param', 'jsr_db',        'levels', jsr);
cfg(9)  = struct('name', 'tone_jamming',        'param', 'tone_jsr_db',   'levels', jsr);
cfg(10) = struct('name', 'airframe_shadowing',  'param', 'shadow_db',     'levels', [6 9 12 15 18 21 23 25]);
end
