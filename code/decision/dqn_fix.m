function varargout = dqn_fix(cmd, varargin)
%DQN_FIX  Decision-time layers on the DQN's action (policy_decide.m, dqn kinds): the options
%   PP.dqn_harm and PP.dqn_hop, and the parse of PP.lb_more (lb_complete.m). Each is '' or absent
%   for off, which leaves every action, rung and memory field as it was.
%   F = dqn_fix('parse', field, s)   field 'dqn_harm', 'dqn_hop' or 'lb_more'; s the setting:
%       dqn_harm  'q' | 'rule' | 'fec'    a lost-branch class with harm evidence, held at no_action
%                 by the DQN for C.esc confirmed cycles, takes one step out of it: q the highest-Q
%                 configuration not tried (the escalation's step), rule the rule's lost-branch
%                 answer (power_control; spatial_diversity beside it where the predicted MMSE gain
%                 reaches the rule's nulling threshold), fec that answer with fec_interleave
%       dqn_hop   'q' | 'rule'            a hop that left the link degraded for C.esc cycles from
%                 its first frame under an in-channel hostile class takes a configuration with no
%                 frequency element: q the highest-Q one not tried, rule the space element where
%                 separable (or already held) and the largest link-budget gain
%       lb_more   tokens 'fec', 'step' joined by '+' (lb_complete.m)
%       F: on, mode (dqn_harm, dqn_hop), fec and step (lb_more), name (canonical)
%   [a, acted, mem] = dqn_fix('harm', a, cfg, M, mem, PP, F, q, gain, qi, qt, mt, so)
%   [a, acted, mem] = dqn_fix('hop', a, cfg, M, mem, PP, F, q, gain, mt)
%   [a, acted] = dqn_fix('step', a, cfg, M, mem, PP, done)   lb_more's step, after the link-budget
%       completion (done: the episodes it changed, left alone): where the DQN keeps the configuration
%       in use, the drop alarm is confirmed for C.esc cycles, the completion's deficit D_c is at
%       least D_min (lb_complete.m) and the link stayed degraded, with or without RF evidence, for
%       C.esc cycles from that configuration's first frame (mem.hq_n, policy_monitor.m), rate_reduce
%       is added to its link-budget factor, or rate_reduce+power_control taken when the union is not
%       a configuration, the frequency and space factors kept. D_c is our signal's power alone: a
%       residual interferer or the fading margin at the lower mean power is not in it, and the
%       processing gain (Eb/N0 = S/N0 x 1/R, Sklar 2001, ch. 5) raises the margin whatever its cause.
%       a the DQN's action after the link-budget completion, cfg the configuration in use, M and
%       mem the monitor's reading and memory, q the Q-values (nA x NE), gain the predicted MMSE
%       gain [dB], qi the quiet slot's IoT, qt its threshold, mt the nulling threshold, so the
%       quiet-slot branch; acted(i): episode i's action was replaced. A configuration taken is
%       marked tried in this incident (mem.tried, cleared by the monitor on recovery), so each
%       layer steps once per configuration.
%   The layers read receiver measurements only: the class, the harm evidence, the degradation
%   and the configurations' known gains; no truth field.
switch cmd
    case 'parse', varargout{1} = parse(varargin{:});
    case 'harm',  [varargout{1:3}] = harm(varargin{:});
    case 'hop',   [varargout{1:3}] = hop(varargin{:});
    case 'step',  [varargout{1:2}] = step(varargin{:});
    otherwise, error('dqn_fix:cmd', 'dqn_fix: unknown command %s', cmd);
end
end

function F = parse(field, s)
F = struct('on', false, 'mode', '', 'fec', false, 'step', false, 'name', '');
if nargin < 2 || isempty(s) || (isstring(s) && all(strlength(s) == 0)), return; end
if isstruct(s) && isfield(s, 'on'), F = s; return; end
assert(ischar(s) || (isstring(s) && isscalar(s)), 'dqn_fix:value', 'dqn_fix: %s is a character string', field);
s = char(s);
switch field
    case 'dqn_harm', ok = {'q', 'rule', 'fec'};
    case 'dqn_hop',  ok = {'q', 'rule'};
    case 'lb_more'
        t = strsplit(s, '+'); ok = {'fec', 'step'};
        bad = t(~ismember(t, ok));
        assert(isempty(bad), 'dqn_fix:token', 'dqn_fix: unknown lb_more token %s', strjoin(bad, ', '));
        assert(numel(unique(t)) == numel(t), 'dqn_fix:token', 'dqn_fix: a token twice in %s', s);
        F.fec = any(strcmp(t, 'fec')); F.step = any(strcmp(t, 'step'));
        F.on = true; F.name = strjoin(ok(ismember(ok, t)), '+');
        return
    otherwise, error('dqn_fix:field', 'dqn_fix: unknown option %s', field);
end
assert(ismember(s, ok), 'dqn_fix:token', 'dqn_fix: %s takes %s, not %s', field, strjoin(ok, ', '), s);
F.on = true; F.mode = s; F.name = s;
end

function [a, acted, mem] = harm(a, cfg, M, mem, PP, F, q, gain, qi, qt, mt, so)
% A lost branch that harms the link (degraded, degraded without RF evidence or the drop alarm in
% the confirmation's cycles, M.harm): the other branches no longer carry it, so it is answered.
% Losing one of N branches costs 10 log10(N / (N - 1)) dB of the combined power and one order of
% diversity (Brennan 1959); the rule's answer raises the link budget (power_control) and nulls a
% separable interferer; fec_interleave gives back time diversity over frames beyond the coherence
% time (Tse & Viswanath 2005, ch. 3).
C = decision_config();
A = PP.actions; nA = numel(A); NE = numel(a);
acted = false(1, NE);
F = parse('dqn_harm', F);
if ~F.on || ~isfield(M, 'harm'), return; end
na = find(strcmp(A, 'no_action'));
allowed = policy_mask(cfg, M.confirmed, mem.since, nA, na);
for i = 1:NE
    if ~(ismember(M.cls{i}, {'antenna_fault', 'airframe_shadowing'}) && M.harm(i) && M.confirmed(i) && cfg(i) == na ...
            && a(i) == na && mem.conf_n(i) >= C.esc && mem.since(i) >= C.esc && ~mem.pend(i))
        continue
    end
    j = [];
    if strcmp(F.mode, 'q')
        if ~isempty(q)
            v = q(:, i); v(mem.tried(i, :)) = -inf; v(na) = -inf; v(~allowed(:, i)) = -inf;
            [vm, b] = max(v); if isfinite(vm), j = b; end
        end
    else
        r = rule_based_policy(M.cls{i}, M.degraded(i), gain(i), qi(i), qt, false, [], mt, so, {}, true, '');
        if strcmp(F.mode, 'fec'), r = rule_fix('answer', r, M.cls{i}, 'fec', qi(i), qt, M.degraded(i), so, [], true); end
        j = find(strcmp(A, r), 1);
    end
    if isempty(j) || j == na || mem.tried(i, j) || ~allowed(j, i), continue; end
    mem.tried(i, cfg(i)) = true; mem.tried(i, j) = true;
    a(i) = j; acted(i) = true;
end
end

function [a, acted, mem] = hop(a, cfg, M, mem, PP, F, q, gain, mt)
% A hop that failed: the configuration in use leaves the channel (channel_switch or
% freq_diversity), the class is in-channel hostile and the link stayed degraded for C.esc cycles
% from the first frame received with it (mem.deg_n is cleared on that frame). A jammer that
% follows the link defeats band switching (Barajas et al. 2026; the tracking jammer of Yuan et al.
% 2021), and its re-acquisition takes the hop's gain away (link_env.m fdelay, C.fdelay); the
% answers left are space (M antennas null M - 1 interferers, Winters, Salz & Gitlin 1994) and link
% budget (processing gain 10 log10 of the rate factor, Eb/J0 = (S/J)(W/R), and the power step,
% power_step_db.m).
C = decision_config();
A = PP.actions; nA = numel(A); NE = numel(a);
acted = false(1, NE);
F = parse('dqn_hop', F);
if ~F.on, return; end
na = find(strcmp(A, 'no_action'));
hasF = contains(A, 'channel_switch') | contains(A, 'freq_diversity');
allowed = policy_mask(cfg, M.confirmed, mem.since, nA, na);
inch = {'jamming', 'reactive_jamming', 'spoofing', 'tone_jamming'};
for i = 1:NE
    if ~(hasF(cfg(i)) && ismember(M.cls{i}, inch) && M.confirmed(i) && mem.deg_n(i) >= C.esc && mem.since(i) >= C.esc ...
            && ~mem.pend(i) && (a(i) == cfg(i) || hasF(a(i))))
        continue
    end
    j = [];
    if strcmp(F.mode, 'q')
        if ~isempty(q)
            v = q(:, i); v(hasF) = -inf; v(mem.tried(i, :)) = -inf; v(na) = -inf; v(~allowed(:, i)) = -inf;
            [vm, b] = max(v); if isfinite(vm), j = b; end
        end
    else
        s = gain(i) >= mt || contains(A{cfg(i)}, 'spatial_diversity');
        r = 'rate_reduce+power_control'; if s, r = ['spatial_diversity+' r]; end
        j = find(strcmp(A, r), 1);
    end
    if isempty(j) || j == cfg(i) || mem.tried(i, j) || ~allowed(j, i), continue; end
    mem.tried(i, cfg(i)) = true; mem.tried(i, j) = true;
    a(i) = j; acted(i) = true;
end
end

function [a, acted] = step(a, cfg, M, mem, PP, done)
C = decision_config();
A = PP.actions; nA = numel(A); NE = numel(a);
acted = false(1, NE);
if ~isfield(mem, 'hq_n') || ~isfield(mem, 'lb_dc') || ~isfield(mem, 'drop_n'), return; end
gk = config_gain_db(PP);
na = find(strcmp(A, 'no_action'));
allowed = policy_mask(cfg, M.confirmed, mem.since, nA, na);
dmin = C.sev.path_loss.levels(1) / 2;
keep = {'channel_switch', 'freq_diversity', 'spatial_diversity'};
for i = 1:NE
    if ~(~done(i) && a(i) == cfg(i) && M.confirmed(i) && M.drop_alarm(i) && mem.drop_n(i) >= C.esc && mem.hq_n(i) >= C.esc ...
            && mem.since(i) >= C.hold && ~mem.pend(i) && mem.lb_dc(i) >= dmin)
        continue
    end
    p = strsplit(A{cfg(i)}, '+');
    if ismember('rate_reduce', p), continue; end
    fs = p(ismember(p, keep));
    j = find(strcmp(A, strjoin([fs, {'rate_reduce'}, p(ismember(p, {'power_control'}))], '+')), 1);
    if isempty(j), j = find(strcmp(A, strjoin([fs, {'rate_reduce', 'power_control'}], '+')), 1); end
    if isempty(j) || j == cfg(i) || gk(j) <= gk(cfg(i)) || ~allowed(j, i), continue; end
    a(i) = j; acted(i) = true;
end
end
