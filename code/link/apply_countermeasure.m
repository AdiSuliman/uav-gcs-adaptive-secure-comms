function [p, snr_gain_db, cm] = apply_countermeasure(p, threat, action)
%APPLY_COUNTERMEASURE  Physical effect of a recovery action on the link model.
%
%   [p, snr_gain_db, cm] = apply_countermeasure(p, threat, action)
%
%   p           params with the threat already configured (any severity)
%   threat      TRUE threat on the link (physics), not the detected class;
%               a combined threat 'a+b' applies the action to each component
%   action      no_action | channel_switch | rate_reduce | freq_diversity |
%               spatial_diversity | power_control | fec_interleave
%               (channel_switch_fast is treated as channel_switch); two actions
%               joined with '+' are applied together
%
%   p           params with the countermeasure applied to the threat model
%   snr_gain_db Eb/N0 gain to ADD to the AWGN block SNR after rebuilding
%   cm          .goodput_factor (data-rate cost), .bw_factor (spectrum cost),
%               .power_factor (transmit-power cost), .effect (text)
%
%   Threat groups:
%     in-channel  jamming, reactive_jamming, spoofing, benign_interference,
%                 tone_jamming (occupy our operating channel only)
%     swept       sweeping_jammer (visits every channel for a fraction of time)
%     broadband   noise_burst (covers all channels while ON)
%     signal-side path_loss, antenna_fault, airframe_shadowing (attenuate our
%                 own signal, on both antennas or on one of them)
%
%   Actions (constants in init_params: cm_acr_db, cm_rate_factor, n_rx):
%     channel_switch     move to a channel the interferer does not occupy:
%                        in-channel interference drops by the adjacent-channel
%                        rejection; no effect on swept, broadband or signal-side threats
%     freq_diversity     same data on two channels p.fdiv_spacing_hz apart, the better
%                        branch selected per frame: in-channel interference drops by
%                        the rejection; a swept jammer loses a frame only while both
%                        carriers are inside its band at once (sweep_window_s.m);
%                        no effect on broadband or signal-side threats; 2x spectrum
%     spatial_diversity  the UAV receiver switches from MRC to adaptive MMSE combining
%                        over its n_rx antennas: sample-covariance weights null
%                        up to n_rx-1 interferers arriving from other directions and
%                        track a faulty branch; the effect is in the link model
%                        (p.rx_combiner), no Eb/N0 offset
%     rate_reduce        rate / cm_rate_factor: +10*log10(factor) dB processing gain
%                        against noise and noise-like interference; no gain against
%                        a coherent spoofer; goodput / factor
%     power_control      the GCS radio's largest power step under the licence-exempt
%                        e.i.r.p. cap, per carrier (power_step_db.m): the signal rises by
%                        that much against noise and every additive interferer,
%                        including a spoofer; attenuation threats keep their loss
%     fec_interleave     one 1000 + 32-bit packet per two frames: rate-1/2
%                        convolutional code (K = 7), its codeword interleaved over
%                        p.fec_frames = 4 frames, erasure decoding of the frames the
%                        receiver flags and of symbols hit by an energy burst; same
%                        channel symbols, so no Eb/N0 change here -- the decoding is
%                        applied to the measured error pattern (fec_packets.m, p.fec);
%                        goodput x1/2, the packet decoded after its fourth frame
%                        (three cycles, 60 ms, later than an uncoded packet)
%
%   p.inband_ref keeps the in-band levels before any countermeasure: the in-band cap
%   acts on them (build_threat_model.m), so a capped emitter keeps one power under every
%   configuration and an action still lowers it by its own amount.

if ~isfield(p, 'inband_ref')
    p.inband_ref = struct();
    for f = {'jsr_db', 'tone_jsr_db', 'spoof_sir_db', 'benign_int_db'}
        if isfield(p, f{1}), p.inband_ref.(f{1}) = p.(f{1}); end
    end
end
if contains(action, '+')
    [p, snr_gain_db, cm] = apply_pair(p, threat, action);
    return;
end
if contains(threat, '+')
    [p, snr_gain_db, cm] = apply_combined(p, threat, action);
    return;
end

acr_db = getf(p, 'cm_acr_db', 30);
rate_f = getf(p, 'cm_rate_factor', 4);
pwr_db = power_step_db(p);

snr_gain_db = 0;
cm = struct('goodput_factor', 1, 'bw_factor', 1, 'power_factor', 1, 'effect', 'none');

if strcmp(action, 'channel_switch_fast'), action = 'channel_switch'; end

inChannel = ismember(threat, {'jamming','reactive_jamming','spoofing','benign_interference','tone_jamming'});
field     = interference_field(threat);

switch action
    case 'no_action'

    case 'channel_switch'
        if inChannel
            p.(field) = p.(field) - acr_db;
            cm.effect = sprintf('interferer left behind (-%g dB)', acr_db);
        else
            cm.effect = 'no effect (threat not tied to our channel)';
        end

    case 'freq_diversity'
        cm.bw_factor = 2;
        if inChannel
            p.(field) = p.(field) - acr_db;
            cm.effect = sprintf('clean branch selected (-%g dB)', acr_db);
        elseif strcmp(threat, 'sweeping_jammer')
            p.sweep_fdiv = true;
            cm.effect = 'frame lost only while both carriers are in the sweep';
        else
            cm.effect = 'no effect (broadband or signal-side threat)';
        end

    case 'spatial_diversity'
        p.rx_combiner = 'mmse';
        cm.effect = sprintf('adaptive MMSE combining over %d antennas', getf(p, 'n_rx', 2));

    case 'rate_reduce'
        g = 10*log10(rate_f);
        snr_gain_db = g;
        cm.goodput_factor = 1 / rate_f;
        if ~isempty(field) && ~ismember(threat, {'spoofing','path_loss','antenna_fault','airframe_shadowing'})
            p.(field) = p.(field) - g;
        end
        cm.effect = sprintf('processing gain +%.1f dB, goodput x%.2f', g, 1/rate_f);

    case 'power_control'
        snr_gain_db = pwr_db;
        cm.power_factor = 10^(pwr_db/10);
        if ~isempty(field) && ~ismember(threat, {'path_loss','antenna_fault','airframe_shadowing'})
            p.(field) = p.(field) - pwr_db;
        end
        cm.effect = sprintf('transmit power +%g dB', pwr_db);

    case 'fec_interleave'
        p.fec = true;
        cm.goodput_factor = getf(p, 'cm_fec_rate', 1/2);
        cm.effect = sprintf('rate-%g code + interleaving, erasure decoding', cm.goodput_factor);

    otherwise
        error('apply_countermeasure: unknown action ''%s''', action);
end

if isfield(p, 'path_loss_db'),   p.path_loss_db   = max(p.path_loss_db, 0); end
if isfield(p, 'fault_atten_db'), p.fault_atten_db = max(p.fault_atten_db, 0); end
if isfield(p, 'shadow_db'),      p.shadow_db      = max(p.shadow_db, 0); end
end

function [p, snr_gain_db, cm] = apply_pair(p, threat, action)
% Two actions at once: each acts on the link in turn. Eb/N0 gains add,
% goodput and power costs multiply, spectrum cost is the larger one.
acts = strsplit(action, '+');
snr_gain_db = 0;
cm = struct('goodput_factor', 1, 'bw_factor', 1, 'power_factor', 1, 'effect', '');
eff = cell(1, numel(acts));
for i = 1:numel(acts)
    [p, g, ci] = apply_countermeasure(p, threat, acts{i});
    snr_gain_db = snr_gain_db + g;
    cm.goodput_factor = cm.goodput_factor * ci.goodput_factor;
    cm.power_factor   = cm.power_factor * ci.power_factor;
    cm.bw_factor      = max(cm.bw_factor, ci.bw_factor);
    eff{i} = sprintf('%s: %s', acts{i}, ci.effect);
end
cm.effect = strjoin(eff, ' | ');
end

function [p, snr_gain_db, cm] = apply_combined(p, threat, action)
% Combined threat 'a+b': the action acts on each component. The Eb/N0 gain is
% one property of the action, so it is applied once (the smallest component gain).
parts = strsplit(threat, '+');
fields = cellfun(@interference_field, parts, 'UniformOutput', false);
fields = fields(~cellfun(@isempty, fields));
if numel(unique(fields)) < numel(fields)
    error('apply_countermeasure: components of ''%s'' share a severity field', threat);
end
gains = zeros(1, numel(parts)); eff = cell(1, numel(parts));
for i = 1:numel(parts)
    [p, gains(i), cmi] = apply_countermeasure(p, parts{i}, action);
    eff{i} = sprintf('%s: %s', parts{i}, cmi.effect);
end
snr_gain_db = min(gains);
cm = cmi;
cm.effect = strjoin(eff, '; ');
end

function f = interference_field(threat)
switch threat
    case {'jamming','reactive_jamming','sweeping_jammer','noise_burst'}, f = 'jsr_db';
    case 'spoofing',            f = 'spoof_sir_db';
    case 'benign_interference', f = 'benign_int_db';
    case 'path_loss',           f = 'path_loss_db';
    case 'antenna_fault',       f = 'fault_atten_db';
    case 'tone_jamming',        f = 'tone_jsr_db';
    case 'airframe_shadowing',  f = 'shadow_db';
    otherwise,                  f = '';
end
end

function v = getf(p, name, default)
if isfield(p, name), v = p.(name); else, v = default; end
end
