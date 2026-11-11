function L = lb_log_lines(ALL, POL, LBL, HA)
%LB_LOG_LINES  The lost-branch log of the pooled threat episodes (C2e). For every policy that
%   carries a count (rollout_policy.m: lb_na, s1_withheld, s1_blocked; only with the calibrated
%   acceptance or the lost-branch gate): the cycles and the episodes with such a cycle, split by HA,
%   the episodes no response does not restore (harmed). {} when no policy carries a count.
%   ALL{k}: policy k's pooled result struct, POL / LBL: its names and labels.
L = {};
thr = ALL{1}.threat(:)'; HA = logical(HA(:)');
fld = {'lb_na', 'lost-branch class not accepted (class alarm withheld)'; ...
    's1_withheld', 'class answer withheld by the lost-branch gate'; ...
    's1_blocked', 'escalation blocked by the lost-branch gate'};
mh = thr & HA; mu = thr & ~HA;
for pk = 1:numel(POL)
    R = ALL{pk};
    for f = 1:size(fld, 1)
        if ~isfield(R, fld{f, 1}), continue; end
        n = R.(fld{f, 1})(:)';
        L{end+1} = sprintf(['  %s: %s, %d cycles in %d of %d harmed episodes | %d cycles in %d of %d unharmed ' ...
            'episodes'], LBL{pk}, fld{f, 2}, sum(n(mh)), sum(n(mh) > 0), sum(mh), sum(n(mu)), sum(n(mu) > 0), ...
            sum(mu)); %#ok<AGROW>
    end
end
if ~isempty(L)
    L = [{['Lost-branch log, threat episodes pooled (harmed = no response does not restore the geometry; ' ...
        'cycles summed over the episodes, episodes with at least one such cycle):']}, L];
end
end
