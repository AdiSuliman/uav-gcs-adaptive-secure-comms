function varargout = rule_fix(cmd, varargin)
%RULE_FIX  Layered answers of the rule (PP.rule_fix): the option, the answers and the
%   escalation's merge. Off ('' or absent) leaves every rule answer and rung as it was.
%   F = rule_fix('parse', s)   s: '' (off) or tokens joined by '+', each at most once:
%       keep   the escalation keeps the frequency and space elements of the configuration in
%              use where the rung holds none, and its link-budget elements where the union is
%              a configuration (merge below)
%       st     the class tone_jamming takes spatial_diversity (adaptive space-time MMSE): a CW
%              is one dimension of the antennas x taps snapshot from any direction, so the
%              combiner's FIR nulls it in time where the antennas alone cannot (rx_taps.m nt)
%       rate   an answer that leaves the channel for in-channel interference adds rate_reduce:
%              the hop leaves the jammer ACR dB down, and the processing gain 10 log10(4) covers
%              part of the residual (Eb/J0 = (S/J)(W/R))
%       match  the same answer adds the link-budget configuration the residual needs: the
%              quiet slot's interference over thermal after the hop, predicted as
%              1 + (IoT - 1) / ACR before it and read directly after it, against the smallest
%              known gain that covers it (the rule's own link-budget match); nothing when the
%              predicted residual is below the quiet-slot alarm threshold
%       fec    a lost-branch class answered with power_control adds fec_interleave: one
%              codeword over p.fec_frames frames 20 ms apart, beyond the coherence time, gives
%              back time diversity the lost branch took (Tse & Viswanath 2005, ch. 3)
%       F: on, keep, st, inch ('' | 'rate' | 'match'), fec, name (the canonical string)
%   a = rule_fix('answer', a, cls, F, q_iot, q_thr, degraded, slot_on, budget)
%       the 36-configuration rule's answer a (rule_based_policy.m) with the layered elements
%   a = rule_fix('core', a, cls, F, q_iot, q_thr, degraded, slot_on, current, wide)
%       the core rule's answer a (rule_core_policy.m) with rate_reduce, the core set's only
%       link-budget element, where 'rate' or 'match' adds one; 'st' and 'fec' are outside it;
%       the class jamming keeps an answer chosen on validation (wide non-empty)
%   m = rule_fix('merge', cur, rung)   configuration name of a rung merged with cur
%   j = rule_fix('rung', A, c, ladder, tried)   the first rung of ladder (indices into A) whose
%       merge with configuration c is neither c nor tried; [] when none
%   r = rule_fix('residual', q_iot)    the quiet slot's IoT [dB] predicted after a hop
%   d = rule_fix('acr')                the rejection the prediction assumes [dB]
switch cmd
    case 'parse',    varargout{1} = parse(varargin{:});
    case 'answer',   varargout{1} = answer(varargin{:});
    case 'core',     varargout{1} = core(varargin{:});
    case 'merge',    varargout{1} = merge(varargin{:});
    case 'rung',     varargout{1} = rung(varargin{:});
    case 'residual', varargout{1} = residual(varargin{:});
    case 'acr',      varargout{1} = ACR();
    otherwise, error('rule_fix:cmd', 'rule_fix: unknown command %s', cmd);
end
end

function d = ACR()
% nRF24L01+ selectivity at 2 Mb/s from 6 to 12 MHz, the sheet's smallest beyond the first
% neighbours (band_reject.m; Nordic 2008, Table 8): a hop of at least 6 MHz rejects at least this.
d = 28;
end

function F = parse(s)
F = struct('on', false, 'keep', false, 'st', false, 'inch', '', 'fec', false, 'name', '');
if nargin < 1 || isempty(s), return; end
if isstruct(s) && isfield(s, 'on'), F = s; return; end
assert(ischar(s) || (isstring(s) && isscalar(s)), 'rule_fix:value', 'rule_fix: the option is a character string');
t = strsplit(char(s), '+');
ok = {'keep', 'st', 'rate', 'match', 'fec'};
bad = t(~ismember(t, ok));
assert(isempty(bad), 'rule_fix:token', 'rule_fix: unknown token %s', strjoin(bad, ', '));
assert(numel(unique(t)) == numel(t), 'rule_fix:token', 'rule_fix: a token twice in %s', char(s));
assert(~all(ismember({'rate', 'match'}, t)), 'rule_fix:token', 'rule_fix: rate and match exclude each other');
F.keep = any(strcmp(t, 'keep')); F.st = any(strcmp(t, 'st')); F.fec = any(strcmp(t, 'fec'));
if any(strcmp(t, 'rate')), F.inch = 'rate'; elseif any(strcmp(t, 'match')), F.inch = 'match'; end
F.on = true;
F.name = strjoin(ok(ismember(ok, t)), '+');
end

function a = answer(a, cls, F, q_iot, q_thr, degraded, slot_on, budget)
F = parse(F);
if ~F.on, return; end
if nargin < 8, budget = []; end
[f, s, b] = domains(a);
if F.st && strcmp(cls, 'tone_jamming') && strcmp(f, 'channel_switch'), s = true; end
if hop_answer(a, cls, q_iot, q_thr, degraded, slot_on) && ~isempty(F.inch)
    cur = ''; if ~isempty(budget) && isfield(budget, 'current'), cur = budget.current; end
    [fc, sc, bc] = domains(char(cur));
    add = inch_budget(F.inch, q_iot, q_thr, ~isempty(fc), budget);
    if ~isempty(fc)                                          % after the hop: add, never take away
        s = s || sc; add = union_budget(bc(ismember(bc, {'rate_reduce', 'power_control'})), add);
    end
    b = union_budget(b, add);
end
if F.fec && ismember(cls, {'antenna_fault', 'airframe_shadowing'}) && isempty(f) && isequal(b, {'power_control'})
    b = {'power_control', 'fec_interleave'};
end
a = compose(f, s, b);
end

function a = core(a, cls, F, q_iot, q_thr, degraded, slot_on, current, wide)
F = parse(F);
if ~F.on || isempty(F.inch), return; end
if nargin < 9, wide = ''; end
if strcmp(cls, 'jamming') && ~isempty(wide), return; end
if ~hop_answer(a, cls, q_iot, q_thr, degraded, slot_on), return; end
fc = domains(char(current));
if strcmp(F.inch, 'rate') || ~isempty(inch_budget('match', q_iot, q_thr, ~isempty(fc), [])) || ...
        (~isempty(fc) && contains(current, 'rate_reduce'))
    a = 'channel_switch+rate_reduce';
end
end

function h = hop_answer(a, cls, q_iot, q_thr, degraded, slot_on)
% The answer leaves the channel for interference on it: a hostile in-channel class, a degraded
% link read as benign_interference, or as none while the quiet slot holds interference.
h = false;
if ~startsWith(a, 'channel_switch'), return; end
if ismember(cls, {'jamming', 'reactive_jamming', 'spoofing', 'tone_jamming'}), h = true; return; end
if strcmp(cls, 'benign_interference') && degraded, h = true; return; end
if strcmp(cls, 'none') && degraded && slot_on && q_iot >= thr_of(q_thr), h = true; end
end

function t = thr_of(q_thr)
if isempty(q_thr) || isnan(q_thr), C = decision_config(); t = C.q_alarm_db; else, t = q_thr; end
end

function b = inch_budget(mode, q_iot, q_thr, hopped, budget)
% The link-budget elements an in-channel answer adds: rate_reduce, or the smallest known gain
% covering the quiet slot's interference over thermal after the hop (read after it, predicted
% before it), none below the slot's alarm threshold.
if strcmp(mode, 'rate'), b = {'rate_reduce'}; return; end
if hopped, r = q_iot; else, r = residual(q_iot); end
b = {};
if isempty(r) || ~isfinite(r) || r < thr_of(q_thr), return; end
names = {'power_control', 'rate_reduce', 'rate_reduce+power_control'};
g = [4 6.02 10.02];                                         % the rule's convention without the budget
if ~isempty(budget) && isfield(budget, 'names') && ~isempty(budget.names)
    [ok, j] = ismember(names, budget.names);
    names = names(ok); g = budget.gain_db(j(ok));
end
[g, o] = sort(g); names = names(o);
k = find(g >= r, 1); if isempty(k), k = numel(g); end
b = strsplit(names{k}, '+');
end

function r = residual(q_iot)
% (I + N) / N after a hop of rejection ACR, from (I + N) / N before it [dB].
r = 10 * log10(1 + (10 .^ (q_iot / 10) - 1) * 10 ^ (-ACR() / 10));
end

function m = merge(cur, rg)
[f1, s1, b1] = domains(cur); [f2, s2, b2] = domains(rg);
f = f2; if isempty(f2), f = f1; end
b = union_budget(b1, b2);
m = compose(f, s1 || s2, b);
end

function j = rung(A, c, ladder, tried)
j = [];
for k = ladder(:)'
    m = find(strcmp(A, merge(A{c}, A{k})), 1);
    if ~isempty(m) && m ~= c && ~tried(m), j = m; return; end
end
end

function b = union_budget(b1, b2)
% Union of link-budget elements when it is one of the configurations' budgets, else b2.
u = order_budget(unique([b1(:)', b2(:)']));
ok = {{}, {'rate_reduce'}, {'power_control'}, {'fec_interleave'}, {'rate_reduce', 'power_control'}, ...
      {'power_control', 'fec_interleave'}};
if any(cellfun(@(x) isequal(x, u), ok)), b = u; else, b = order_budget(b2); end
end

function b = order_budget(b)
o = {'rate_reduce', 'power_control', 'fec_interleave'};
b = o(ismember(o, b));
end

function [f, s, b] = domains(a)
% Frequency element, spatial flag and link-budget elements of a configuration name.
p = strsplit(a, '+');
f = ''; if any(strcmp(p, 'channel_switch')), f = 'channel_switch'; elseif any(strcmp(p, 'freq_diversity')), f = 'freq_diversity'; end
s = any(strcmp(p, 'spatial_diversity'));
b = order_budget(p);
end

function a = compose(f, s, b)
% Configuration name from its domains, in policy_actions.m's order.
p = {};
if ~isempty(f), p{end+1} = f; end
if s, p{end+1} = 'spatial_diversity'; end
p = [p, order_budget(b)];
if isempty(p), a = 'no_action'; else, a = strjoin(p, '+'); end
end
