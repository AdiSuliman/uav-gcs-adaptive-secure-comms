function [ok, msg] = lb_selfcheck()
%LB_SELFCHECK  The static and parity checks of the link-budget completion that C2 reads before it
%   adopts it (lb_adopt.m, condition d); test_lb.m runs the same checks beside its own cases.
%   Static: neither lb_complete.m nor policy_monitor.m's lb_track reads a class, an unknown-threat
%   score, a truth field of the episode, or the drop alarm's threshold of PP (a CUSUM level in dB^2
%   under class_cusum, not a deficit in dB).
%   Parity: for deficits from D_min (lb_complete.m) to 25 dB the link-budget factor that replaces a no_action proposal
%   is the smallest of rate_reduce, power_control and both whose known gain covers it, else the
%   largest, and is the action of rule_based_policy.m's link-budget match.
%   ok: every check passes; msg: the failing ones.
msg = {};
bad = '\<(cls|probs|unknown|maha|sc_eff|ended|healthy|scn|truth)\>|PP\s*\.\s*drop_db|PP\s*,\s*''drop_db''';
src = {fileread(which('lb_complete')), function_text(fileread(which('policy_monitor')), 'lb_track')};
nm = {'lb_complete.m', 'policy_monitor.m lb_track'};
for k = 1:2
    if isempty(src{k}), msg{end+1} = sprintf('%s not found', nm{k}); continue; end %#ok<AGROW>
    t = regexp(regexprep(src{k}, '%[^\n]*', ''), bad, 'match');
    if ~isempty(t), msg{end+1} = sprintf('%s reads %s', nm{k}, strjoin(unique(t), ', ')); end %#ok<AGROW>
end
A = policy_actions(); na = find(strcmp(A, 'no_action'));
PP = struct('actions', {A}, 'cfg_gain_db', 6.5 * contains(A, 'power_control') + 3.5 * contains(A, 'rate_reduce'));
names = {'rate_reduce', 'power_control', 'rate_reduce+power_control'}; gains = [3.5 6.5 10];
M = struct('confirmed', true, 'drop_alarm', true);
bud = struct('drop_db', 0, 'current', 'no_action', 'current_db', 0, 'names', {names}, 'gain_db', gains);
for D = decision_config().sev.path_loss.levels(1) / 2:0.25:25
    mem =struct('lb_dc', D, 'drop_n', 3, 'since', 10, 'pend', false);
    [b, acted] = lb_complete(na, na, M, mem, PP);
    j = find(gains >= D, 1); if isempty(j), j = numel(gains); end
    bud.drop_db = D;
    if ~acted || ~strcmp(A{b}, names{j}) || ~strcmp(A{b}, rule_based_policy('path_loss', false, 0, -Inf, NaN, true, bud))
        msg{end+1} = sprintf('parity at %.2f dB', D); %#ok<AGROW>
    end
end
ok = isempty(msg);
end

function t = function_text(src, name)
% The text of the local function `name` of src: its header up to the next function's.
i = regexp(src, ['\nfunction [^\n]*\<' name '\>'], 'once');
if isempty(i), t = ''; return; end
r = src(i+1:end);
j = regexp(r(2:end), '\nfunction ', 'once');
if isempty(j), t = r; else, t = r(1:j); end
end
