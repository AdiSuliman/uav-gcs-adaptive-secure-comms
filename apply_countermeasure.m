function [p, snr_gain_db, cm] = apply_countermeasure(p, threat, action)
%APPLY_COUNTERMEASURE  Physical effect of a recovery action on the link model (D28).
%
%   [p, snr_gain_db, cm] = apply_countermeasure(p, threat, action)
%
%   p           params with the threat already configured (any severity)
%   threat      TRUE threat on the link (physics), not the detected class
%   action      no_action | channel_switch | rate_reduce | freq_diversity |
%               spatial_diversity   (channel_switch_fast is treated as channel_switch)
%
%   p           params with the countermeasure applied to the threat model
%   snr_gain_db Eb/N0 gain to ADD to the AWGN block SNR after rebuilding
%   cm          .goodput_factor (data-rate cost), .bw_factor (spectrum cost), .effect (text)
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

acr_db = getf(p, 'cm_acr_db', 30);
rate_f = getf(p, 'cm_rate_factor', 4);
n_rx   = getf(p, 'cm_n_rx', 2);

snr_gain_db = 0;
cm = struct('goodput_factor', 1, 'bw_factor', 1, 'effect', 'none');

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

    otherwise
        error('apply_countermeasure: unknown action ''%s''', action);
end

if isfield(p, 'path_loss_db'),   p.path_loss_db   = max(p.path_loss_db, 0); end
if isfield(p, 'fault_atten_db'), p.fault_atten_db = max(p.fault_atten_db, 0); end
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
