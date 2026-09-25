function [p, snr_gain_db, cm] = apply_countermeasure(p, threat, action)
%APPLY_COUNTERMEASURE  Physical effect of a recovery action on the link model (D28).
%
%   [p, snr_gain_db, cm] = apply_countermeasure(p, threat, action)
%
%   p           params with the threat already configured (any severity)
%   threat      TRUE threat on the link (physics), not the detected class;
%               a combined threat 'a+b' applies the action to each component (D32)
%   action      no_action | channel_switch | rate_reduce | freq_diversity |
%               spatial_diversity | power_control | fec_interleave
%               (channel_switch_fast is treated as channel_switch); two actions
%               joined with '+' are applied together (D39)
%
%   p           params with the countermeasure applied to the threat model
%   snr_gain_db Eb/N0 gain to ADD to the AWGN block SNR after rebuilding
%   cm          .goodput_factor (data-rate cost), .bw_factor (spectrum cost),
%               .power_factor (transmit-power cost), .effect (text)
%
%   Threat groups:
%     in-channel  jamming, reactive_jamming, spoofing, benign_interference
%                 (occupy our operating channel only)
%     swept       sweeping_jammer (visits every channel for a fraction of time)
%     broadband   noise_burst (covers all channels while ON)
%     signal-side path_loss, antenna_fault (attenuate our own signal)
%
%   Actions (constants in init_params: cm_acr_db, cm_rate_factor, cm_n_rx):
%     channel_switch     move to a channel the interferer does not occupy:
%                        in-channel interference drops by the adjacent-channel
%                        rejection; no effect on swept, broadband or signal-side threats
%     freq_diversity     same data on two channels, best branch selected:
%                        in-channel interference drops by the rejection; a swept
%                        jammer must hit both channels at once (duty -> duty^2);
%                        no effect on broadband or signal-side threats; 2x spectrum
%     spatial_diversity  second receive antenna, MRC: +10*log10(n_rx) dB against
%                        noise and spatially uncorrelated interference; with an
%                        antenna fault the healthy antenna replaces the faulty one
%     rate_reduce        rate / cm_rate_factor: +10*log10(factor) dB processing gain
%                        against noise and noise-like interference; no gain against
%                        a coherent spoofer; goodput / factor
%     power_control      transmit power +cm_power_db: the signal rises by that much
%                        against noise and every additive interferer, including a
%                        spoofer; attenuation threats keep their loss; x4 power (D39)
%     fec_interleave     rate-1/2 convolutional code (K = 7) with a random interleaver
%                        over the run and erasure decoding of symbols hit by an energy
%                        burst; same channel symbols, so no Eb/N0 change here -- the
%                        decoding is applied to the measured error pattern in
%                        extract_closed_loop_frames.m (p.fec); goodput x1/2 (D39)

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
n_rx   = getf(p, 'cm_n_rx', 2);
pwr_db = getf(p, 'cm_power_db', 6);

snr_gain_db = 0;
cm = struct('goodput_factor', 1, 'bw_factor', 1, 'power_factor', 1, 'effect', 'none');

if strcmp(action, 'channel_switch_fast'), action = 'channel_switch'; end

inChannel = ismember(threat, {'jamming','reactive_jamming','spoofing','benign_interference'});
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
            p.sweep_duty = p.sweep_duty^2;
            cm.effect = 'both branches hit only simultaneously (duty^2)';
        else
            cm.effect = 'no effect (broadband or signal-side threat)';
        end

    case 'spatial_diversity'
        g = 10*log10(n_rx);
        if strcmp(threat, 'antenna_fault')
            p.fault_atten_db = 0;
            cm.effect = 'faulty antenna replaced by the healthy one';
        else
            snr_gain_db = g;
            if ~isempty(field) && ~strcmp(threat, 'path_loss')
                p.(field) = p.(field) - g;
            end
            cm.effect = sprintf('MRC gain +%.1f dB', g);
        end

    case 'rate_reduce'
        g = 10*log10(rate_f);
        snr_gain_db = g;
        cm.goodput_factor = 1 / rate_f;
        if ~isempty(field) && ~ismember(threat, {'spoofing','path_loss','antenna_fault'})
            p.(field) = p.(field) - g;
        end
        cm.effect = sprintf('processing gain +%.1f dB, goodput x%.2f', g, 1/rate_f);

    case 'power_control'
        snr_gain_db = pwr_db;
        cm.power_factor = 10^(pwr_db/10);
        if ~isempty(field) && ~ismember(threat, {'path_loss','antenna_fault'})
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
end

function [p, snr_gain_db, cm] = apply_pair(p, threat, action)
% Two actions at once (D39): each acts on the link in turn. Eb/N0 gains add,
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
% Combined threat 'a+b' (D32): the action acts on each component. The Eb/N0 gain is
% one property of the action, so it is applied once (the smallest component gain);
% with an antenna fault, spatial diversity only replaces the faulty antenna.
parts = strsplit(threat, '+');
fields = cellfun(@interference_field, parts, 'UniformOutput', false);
fields = fields(~cellfun(@isempty, fields));
if numel(unique(fields)) < numel(fields)
    error('apply_countermeasure: components of ''%s'' share a severity field', threat);
end
if any(strcmp(action, 'spatial_diversity')) && any(strcmp(parts, 'antenna_fault'))
    parts = {'antenna_fault'};
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
    otherwise,                  f = '';
end
end

function v = getf(p, name, default)
if isfield(p, name), v = p.(name); else, v = default; end
end
