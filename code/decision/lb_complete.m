function [a, acted] = lb_complete(a, cfg, M, mem, PP)
%LB_COMPLETE  Link-budget completion of the DQN's action (policy_decide.m, PP.lb_complete).
%   [a, acted] = lb_complete(a, cfg, M, mem, PP)
%   a     configuration the DQN proposes (1 x NE; its argmax under the shield), cfg the one in use
%   M, mem   the monitor's reading and memory of this cycle (policy_monitor.m): M.confirmed,
%         M.drop_alarm, mem.drop_n, mem.lb_dc, mem.since, mem.pend
%   acted(i): the link-budget factor of episode i's proposal was replaced
%   A loss of our own signal is settled by the link budget alone: the received power falls by
%   the drop and the known gain of a configuration raises Eb/N0 by that gain (Friis; Eb/N0 =
%   S/N0 x 1/R, Sklar 2001, ch. 5), the physics rule_based_policy.m registers. A learner that
%   was never rewarded for that answer to a given threat does not give it. The layer reads
%   receiver measurements only: no class, no truth field.
%   It acts when all of these hold:
%     - the drop alarm is confirmed for at least C.esc consecutive cycles (mem.drop_n);
%     - at least C.hold cycles since the last change reached the link, and none is pending;
%     - the deficit D_c, the drop of the combined channel gain of all antennas less the power
%       step (policy_monitor.m lb_track; maximum-ratio combining adds the branches' powers,
%       Brennan 1959), is at least D_min = half the smallest path-loss level of the envelope
%       (decision_config.m), in dB: the drop below which drop_cusum.m does not grow. A lost
%       single branch leaves only 10 log10(N / (N - 1)) dB of it, 1.76 dB on 3 antennas;
%     - the known gain of the proposal is below D_c, and the proposal holds no fec_interleave
%       (the coding domain answers bursts, not loss).
%   The proposal's link-budget factor is then the one rule_based_policy.m's link-budget match
%   gives for D_c (the smallest of rate_reduce, power_control and both that covers it, else
%   the largest); its frequency and space factors are kept, and the result must pass the
%   shield (policy_mask.m).
C = decision_config();
A = PP.actions; nA = numel(A); NE = numel(a);
acted = false(1, NE);
if ~isfield(mem, 'lb_dc') || ~isfield(mem, 'drop_n'), return; end   % the monitor has no drop alarm
gk = config_gain_db(PP);
na = find(strcmp(A, 'no_action'));
bl = find(ismember(A, {'power_control', 'rate_reduce', 'rate_reduce+power_control'}));
bud = struct('drop_db', 0, 'current', '', 'current_db', -Inf, 'names', {A(bl)}, 'gain_db', gk(bl));
allowed = policy_mask(cfg, M.confirmed, mem.since, nA, na);
dmin = C.sev.path_loss.levels(1) / 2;
keep = {'channel_switch', 'freq_diversity', 'spatial_diversity'};
for i = 1:NE
    dc = mem.lb_dc(i);
    if ~(M.confirmed(i) && M.drop_alarm(i) && mem.drop_n(i) >= C.esc && mem.since(i) >= C.hold && ~mem.pend(i) ...
            && dc >= dmin && gk(a(i)) < dc)
        continue
    end
    p = strsplit(A{a(i)}, '+');
    if ismember('fec_interleave', p), continue; end
    bud.drop_db = dc;
    b = rule_based_policy('path_loss', false, 0, -Inf, NaN, true, bud);
    j = find(strcmp(A, strjoin([p(ismember(p, keep)), strsplit(b, '+')], '+')), 1);
    if isempty(j) || j == a(i) || ~allowed(j, i), continue; end
    a(i) = j; acted(i) = true;
end
end
