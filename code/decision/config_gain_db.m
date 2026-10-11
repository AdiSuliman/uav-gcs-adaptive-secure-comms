function g = config_gain_db(A, p)
%CONFIG_GAIN_DB  Known Eb/N0 gain of every configuration [dB], 1 x numel(actions).
%   g = config_gain_db(actions, p)  from the params p: the gain apply_countermeasure.m
%       gives our signal over thermal noise on the clean link, the power step of
%       power_control (power_step_db.m: the received power follows the transmitted one,
%       Friis) and the processing gain 10 log10(p.cm_rate_factor) of rate_reduce
%       (Eb/N0 = S/N0 x 1/R); every other action adds none
%   g = config_gain_db(actions)     the same from params.mat of the current folder, or
%       apply_countermeasure.m's defaults without one
%   g = config_gain_db(PP)          PP.cfg_gain_db when the pools carry it, else the
%       gains of PP.actions as above (pools built before it was stored)
persistent key cache
if isstruct(A)
    if isfield(A, 'cfg_gain_db') && ~isempty(A.cfg_gain_db), g = A.cfg_gain_db; return; end
    A = A.actions;
end
if nargin < 2
    t = -1; if isfile('params.mat'), t = dir('params.mat').datenum; end
    k = sprintf('%s|%.10f|%s', strjoin(A, ','), t, pwd);
    if isequal(key, k), g = cache; return; end
    p = struct();
    if isfile('params.mat'), S = load('params.mat'); p = S.params; end
    g = config_gain_db(A, p);
    key = k; cache = g;
    return
end
g = zeros(1, numel(A));
for a = 1:numel(A)
    [~, g(a)] = apply_countermeasure(p, 'none', A{a});
end
end
