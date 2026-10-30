function varargout = lb_complete(cmd, varargin)
%LB_COMPLETE  Link-budget completion of a DQN's action at decision time (policy_decide.m).
%   on = lb_complete('on', PP)
%   [mem, dc] = lb_complete('track', mem, obs, gp, ok, ex, M)
%   [a, acted] = lb_complete('apply', a, cfg, M, mem, PP)
%
%   A DQN that was never rewarded for a link-budget answer to a loss of our signal can
%   keep a frequency or space answer and leave the link budget at its old level. The
%   completion replaces the link-budget factor of the proposed configuration by the
%   rule's match (rule_based_policy.m): the smallest of power_control, rate_reduce and
%   both whose known gain covers the deficit, the largest when none does. The
%   frequency and space factors are kept. It reads receiver measurements only: the
%   monitor's drop alarm and confirmation, the antennas' channel gains, the
%   configurations' known gains. No class and no truth field.
%   The switch PP.lb_complete (decision_settings.m; default off) is stored with the
%   agent like the alarm mode. Off, the monitor keeps no extra state and the decision
%   cycle runs as without this file.
%
%   'track' (policy_monitor.m, once per cycle, after the alarm and its confirmation)
%   keeps the monitor's memory for the completion and returns the deficit dc (1 x NE):
%   the drop of the combined channel gain of all antennas, 10 log10 sum 10^(g_i / 10),
%   with g_i the antenna's gain less the power step of the configuration its frame was
%   received with (gp, 1 x NE). Maximum-ratio combining adds the branches' SNRs, so a
%   lost single branch costs only what the others do not cover. The deficit is the
%   reference less the median of the last cycles, the reference held with its own state as
%   drop_ref.m holds the monitor's: mem.gref, mem.grp, mem.grx, the window mem.gc.
%   ex is the monitor's excursion measure of this cycle ([] with a monitor that has no
%   drop alarm), M its alarm outputs (drop_alarm, confirmed), ok (NE x 1) the cycles that
%   may join the reference. mem.drop_n counts the consecutive cycles of a confirmed
%   drop alarm.
%
%   'apply' (after the argmax, before the escalation) acts on an episode when all hold:
%   the confirmed drop alarm has lasted C.esc cycles, C.hold cycles have passed since
%   the last change reached the link, no change is pending, the deficit is at least half
%   the smallest path-loss level of the envelope (the drop below which the monitor's
%   CUSUM does not grow, drop_cusum.m), and the proposal's known gain is below the
%   deficit. A proposal that holds fec_interleave is left unchanged: the coding domain
%   answers bursts, not loss. The result must pass the shield (policy_mask.m).
%   acted (1 x NE): the proposal was changed.
switch cmd
    case 'on'
        PP = varargin{1};
        varargout{1} = isfield(PP, 'lb_complete') && ~isempty(PP.lb_complete) && logical(PP.lb_complete(1));
    case 'track'
        [varargout{1:2}] = track(varargin{:});
    case 'apply'
        [varargout{1:2}] = apply(varargin{:});
    otherwise
        error('lb_complete: unknown command %s', cmd);
end
end

function [mem, dc] = track(mem, obs, gp, ok, ex, M)
NE = numel(mem.since);
if ~isfield(mem, 'drop_n')
    mem.drop_n = zeros(1, NE);
    mem.gc = nan(NE, size(mem.ebno, 2));
    mem.gref = nan(NE, size(mem.ref, 2)); mem.grp = nan(NE, size(mem.ref, 2)); mem.grx = false(NE, 1);
end
gc = nan(NE, 1);                                                % combined gain of all antennas [dB]
if isfield(obs, 'gant') && ~isempty(obs.gant)
    g = obs.gant - reshape(gp, [], 1);
    gc = 10 * log10(sum(10 .^ (g / 10), 2, 'omitnan'));
    gc(all(isnan(g), 2)) = NaN;
end
mem.gc = [mem.gc(:, 2:end), gc];
e3 = median(mem.gc, 2, 'omitnan');
ref = median(mem.gref, 2, 'omitnan');
ref(isnan(ref)) = e3(isnan(ref));
dc = (ref - e3)';
if ~isempty(ex)
    [mem.gref, mem.grp, mem.grx] = drop_ref(mem.gref, mem.grp, mem.grx, gc, ok(:), ex, M.drop_alarm(:));
end
k = M.confirmed & M.drop_alarm;
mem.drop_n(k) = mem.drop_n(k) + 1; mem.drop_n(~k) = 0;
end

function [a, acted] = apply(a, cfg, M, mem, PP)
C = decision_config();
A = PP.actions; nA = numel(A); NE = numel(cfg);
na = find(strcmp(A, 'no_action'));
a = a(:)'; acted = false(1, NE);
gk = config_gain_db(PP);
dc = M.dcomb;
dmin = C.sev.path_loss.levels(1) / 2;
fec = contains(A, 'fec_interleave');
go = mem.drop_n >= C.esc & mem.since >= C.hold & ~mem.pend & dc >= dmin & gk(a) < dc & ~fec(a);
if ~any(go), return; end
lbi = find(ismember(A, {'power_control', 'rate_reduce', 'rate_reduce+power_control'}));   % link-budget configurations
mask = policy_mask(cfg, M.confirmed, mem.since, nA, na);
for i = find(go)
    bud = struct('drop_db', dc(i), 'current', A{a(i)}, 'current_db', gk(a(i)), 'names', {A(lbi)}, 'gain_db', gk(lbi));
    m = rule_based_policy('path_loss', false, 0, -Inf, NaN, false, bud);          % the rule's link-budget match
    p = strsplit(A{a(i)}, '+');
    p = p(ismember(p, {'channel_switch', 'freq_diversity', 'spatial_diversity'}));   % frequency and space factors kept
    j = find(strcmp(A, strjoin([p, {m}], '+')), 1);
    if ~isempty(j) && j ~= a(i) && mask(j, i)
        a(i) = j; acted(i) = true;
    end
end
end
