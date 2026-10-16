function [g, gw] = config_gain_db(A, p)
%CONFIG_GAIN_DB  Known Eb/N0 gain of every configuration [dB], 1 x numel(actions).
%   g = config_gain_db(actions, p)  from the params p: the gain apply_countermeasure.m
%       gives our signal over thermal noise on the clean link, the power step of
%       power_control (power_step_db.m: the received power follows the transmitted one,
%       Friis) and the processing gain 10 log10(p.cm_rate_factor) of rate_reduce
%       (Eb/N0 = S/N0 x 1/R); every other action adds none
%   g = config_gain_db(actions)     the same from params.mat of the current folder, or
%       apply_countermeasure.m's defaults without one
%   g = config_gain_db(PP)          PP.cfg_gain_db when the pools carry it, else the
%       gains of PP.actions as above (pools that do not carry it)
%   [g, gw] = ...  gw: the part of g in the received field, the power step of the
%       configurations holding power_control (10 log10 of their power factor, PP.pw when
%       the pools carry it); the processing gain is in the despread SINR only, the
%       antennas' channel gains are measured at the chip rate (extract_closed_loop_frames.m)
persistent key cache
if isstruct(A)
    if isfield(A, 'cfg_gain_db') && ~isempty(A.cfg_gain_db)
        g = A.cfg_gain_db;
        if nargout > 1
            if isfield(A, 'pw') && ~isempty(A.pw)
                gw = 10 * log10(A.pw);
            elseif any(strcmp(A.actions, 'power_control'))   % the power step of the gains the pools carry
                gw = g(strcmp(A.actions, 'power_control')) * ...
                    cellfun(@(a) any(strcmp(strsplit(a, '+'), 'power_control')), A.actions);
            else
                [~, gw] = config_gain_db(A.actions);
            end
        end
        return
    end
    A = A.actions;
end
if nargin < 2
    t = -1; if isfile('params.mat'), t = dir('params.mat').datenum; end
    k = sprintf('%s|%.10f|%s', strjoin(A, ','), t, pwd);
    if isequal(key, k), g = cache.g; gw = cache.gw; return; end
    p = struct();
    if isfile('params.mat'), S = load('params.mat'); p = S.params; end
    [g, gw] = config_gain_db(A, p);
    key = k; cache = struct('g', g, 'gw', gw);
    return
end
g = zeros(1, numel(A)); gw = zeros(1, numel(A));
for a = 1:numel(A)
    [~, g(a), cm] = apply_countermeasure(p, 'none', A{a});
    gw(a) = 10 * log10(cm.power_factor);
end
end
