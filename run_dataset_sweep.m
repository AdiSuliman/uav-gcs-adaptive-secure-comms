%% RUN_DATASET_SWEEP - Phase A5 (FULL): Multi-JSR labeled dataset generation
% Runs all 6 threats x 5 intensity levels x Eb/No sweep + balanced 'none' class.
% Per frame collects: IQ (spectrogram), BER/SNR/RSSI/PLR (features), label, level.
%
% Intensity levels per threat (validated ranges — impact threshold to pre-saturation):
%   jamming/noise_burst/reactive : JSR   = 0,4,8,12,16 dB
%   path_loss                    : atten = 4,8,12,16,20 dB
%   spoofing                     : SIR   = -4,-1,2,5,8 dB
%   antenna_fault                : duty  = 0.1,0.2,0.3,0.4,0.5 (atten fixed 30 dB)
%
% CLASS BALANCE: 'none' generates (n_levels x frames_per_config) frames per SNR,
% matching the total frames of any single threat -> prevents class imbalance.

close all; clc;

if ~exist('params.mat', 'file')
    error('params.mat not found. Run init_params.m first.');
end
S = load('params.mat');
p = S.params;
p0 = p;   % backup to restore threat params after each config

%% ---- Dataset configuration ----
EbNo_list         = p.EbNo_dB;    % 0:2:10 dB
frames_per_config = 50;           % frames per (threat, level, SNR)
delay_bits        = 20;           % validated RRC group delay
modelName         = 'UAV_GCS_Threat_Link';

% Threat -> parameter name + intensity levels
threat_cfg(1) = struct('name','jamming',          'param','jsr_db',       'levels',[0 4 8 12 16]);
threat_cfg(2) = struct('name','noise_burst',      'param','jsr_db',       'levels',[0 4 8 12 16]);
threat_cfg(3) = struct('name','reactive_jamming', 'param','jsr_db',       'levels',[0 4 8 12 16]);
threat_cfg(4) = struct('name','path_loss',        'param','path_loss_db', 'levels',[4 8 12 16 20]);
threat_cfg(5) = struct('name','spoofing',         'param','spoof_sir_db', 'levels',[-4 -1 2 5 8]);
threat_cfg(6) = struct('name','antenna_fault',    'param','fault_duty',   'levels',[0.1 0.2 0.3 0.4 0.5]);

n_levels = 5;   % all threats have 5 levels

% Class index map: 1=none, 2..7 = threats (in threat_cfg order)
class_names = ['none', {threat_cfg.name}];

frame_dur = p.frame_duration;
StopTime_cfg  = frames_per_config * frame_dur;              % one threat config
StopTime_none = n_levels * frames_per_config * frame_dur;   % balanced none (5x)

% Storage
iq_all={}; label_all=[]; level_all=[]; snr_all=[]; ber_all=[]; rssi_all=[]; plr_all=[];

fprintf('\n=== A5 FULL Dataset Generation (Multi-JSR) ===\n');
fprintf('Threats: %d x %d levels x %d SNR | +balanced none | %d frames/config\n', ...
    numel(threat_cfg), n_levels, numel(EbNo_list), frames_per_config);
fprintf('%-18s %6s %6s %10s %10s\n', 'Threat','Level','SNRs','meanBER','meanRSSI');

t_start = tic;


%% ---- Threat loop: threat x level x SNR ----
for tt = 1:numel(threat_cfg)
    cfg = threat_cfg(tt);
    cls_idx = tt + 1;   % class index (1 is none)

    for lv = 1:numel(cfg.levels)
        level_val = cfg.levels(lv);

        % Set threat + its intensity parameter, rebuild
        p = p0;
        p.active_threat = cfg.name;
        p.(cfg.param)   = level_val;
        params = p; save('params.mat','params');
        evalc('build_threat_model');

        ber_accum = []; rssi_accum = [];
        for s = 1:numel(EbNo_list)
            snr_dB = EbNo_list(s) + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
            set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), ...
                'SignalPower', num2str(1/p.sps));
            out = sim(modelName, 'StopTime', num2str(StopTime_cfg));

            [iqf,berf,rssif,plrf,nf] = local_extract(out, p, delay_bits);
            for f = 1:nf
                iq_all{end+1}=iqf{f}; label_all(end+1)=cls_idx; level_all(end+1)=level_val;
                snr_all(end+1)=EbNo_list(s); ber_all(end+1)=berf(f);
                rssi_all(end+1)=rssif(f); plr_all(end+1)=plrf(f);
            end
            ber_accum=[ber_accum berf]; rssi_accum=[rssi_accum rssif];
        end
        fprintf('%-18s %6g %6d %10.3e %10.2f\n', cfg.name, level_val, ...
            numel(EbNo_list), mean(ber_accum,'omitnan'), mean(rssi_accum));
    end
end

%% ---- None class (balanced: 5x frames per SNR) ----
p = p0; p.active_threat = 'none';
params = p; save('params.mat','params');
evalc('build_threat_model');
ber_accum=[]; rssi_accum=[];
for s = 1:numel(EbNo_list)
    snr_dB = EbNo_list(s) + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
    set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), ...
        'SignalPower', num2str(1/p.sps));
    out = sim(modelName, 'StopTime', num2str(StopTime_none));
    [iqf,berf,rssif,plrf,nf] = local_extract(out, p, delay_bits);
    for f = 1:nf
        iq_all{end+1}=iqf{f}; label_all(end+1)=1; level_all(end+1)=NaN;
        snr_all(end+1)=EbNo_list(s); ber_all(end+1)=berf(f);
        rssi_all(end+1)=rssif(f); plr_all(end+1)=plrf(f);
    end
    ber_accum=[ber_accum berf]; rssi_accum=[rssi_accum rssif];
end
fprintf('%-18s %6s %6d %10.3e %10.2f\n', 'none', '-', numel(EbNo_list), ...
    mean(ber_accum,'omitnan'), mean(rssi_accum));

% Restore original params
params = p0; save('params.mat','params');

%% ---- Package ----
dataset.iq=iq_all; dataset.label=label_all(:); dataset.level=level_all(:);
dataset.class_names=class_names; dataset.snr=snr_all(:);
dataset.ber=ber_all(:); dataset.rssi=rssi_all(:); dataset.plr=plr_all(:);
dataset.meta.frames_per_config=frames_per_config; dataset.meta.EbNo_list=EbNo_list;
dataset.meta.delay_bits=delay_bits; dataset.meta.mode='multi_JSR';
dataset.meta.threat_cfg=threat_cfg; dataset.meta.created=datestr(now);

if ~exist('data','dir'); mkdir('data'); end
save('data/dataset.mat','dataset','-v7.3');

%% ---- Summary + balance check ----
fprintf('\n=== Dataset Summary (Multi-JSR) ===\n');
fprintf('Total frames : %d\n', numel(label_all));
fprintf('Elapsed      : %.1f s\n', toc(t_start));
fprintf('\nFrames per class (balance check):\n');
for c = 1:numel(class_names)
    fprintf('  %-18s %d\n', class_names{c}, sum(label_all==c));
end
fprintf('\nSaved to data/dataset.mat. Next: run extract_spectrograms.\n');

%% ===== Local function: extract frames from one sim output =====
function [iq_frames, ber, rssi, plr, nf] = local_extract(out, p, delay_bits)
    txb = double(squeeze(out.get('tx_bits_out')));
    rxb = double(squeeze(out.get('rx_bits_out')));
    iq  = squeeze(out.get('Rx_IQ'));
    if isvector(txb), txb=txb(:); end
    if isvector(rxb), rxb=rxb(:); end
    if isvector(iq),  iq=iq(:);   end

    nf  = size(iq,2);
    bpf = p.frame_length;
    tx_all = txb(:); rx_all = rxb(:);
    Lmax = min(numel(tx_all),numel(rx_all)) - delay_bits;
    tx_al = tx_all(1:Lmax);
    rx_al = rx_all(delay_bits+1:delay_bits+Lmax);

    iq_frames = cell(1,nf); ber=zeros(1,nf); rssi=zeros(1,nf); plr=zeros(1,nf);
    for f = 1:nf
        iq_frames{f} = iq(:,f);
        i0=(f-1)*bpf+1; i1=f*bpf;
        if i1 <= numel(tx_al)
            ber(f) = mean(tx_al(i0:i1) ~= rx_al(i0:i1));
        else
            ber(f) = NaN;
        end
        rssi(f) = 10*log10(mean(abs(iq(:,f)).^2)+eps);
        plr(f)  = double(ber(f) > 0.1);
    end
end