function L = lb_columns(nm, dep, names, X, cl, ebno_thr)
%LB_COLUMNS  The link-budget completion's two columns beside the deployed row (evaluate_policies.m,
%   C2e): the selected DQN without the completion (the learner's own result) and with it (the hybrid,
%   not learned), rule + escalation beside, on the same episodes.
%   L = lb_columns(nm, dep, names, X, cl, ebno_thr)
%   nm      the selected DQN's policy name; dep 'on' or 'off', the switch the agent was deployed with
%   names   the sets' names (single, follower, combined, unknown); X(k) the readings of set k over
%           its recoverable threat episodes, paired: x0 and x1 (recovered, 0/1, without and with the
%           completion), xr (rule + escalation), g (the flight, the bootstrap cluster) and fam (the
%           episodes whose threat holds a path loss)
%   cl      clean link, episodes with a change at Eb/N0 >= ebno_thr: [without, with, episodes]
%   Recovered among the recoverable episodes; the paired difference with a 95% bootstrap over flights
%   (lb_seeds.m, 2000 resamples); the path-loss family (single, combined and unknown sets) pooled; the
%   threat sets single, follower and combined pooled for the line KPI 5 prints.
%   L.sets: the readings per set and the family; L.lines: the report; L.kpi: the KPI 5 line.
S = lb_seeds();
fmt = ['  %-9s %5d: DQN, completion off %5.1f%% | DQN + link-budget completion (hybrid) %5.1f%% | ' ...
    'paired %+5.1f points [%+5.1f, %+5.1f] | rule + escalation %5.1f%%'];
lines = {sprintf(['Link-budget completion beside the deployed row (test sets, the main runs'' frame draws; the selected DQN ' ...
    '%s without and with it; the deployed switch is %s; recovered among the recoverable episodes; paired difference with a 95%% ' ...
    'bootstrap over flights). The learner''s own result is the column with the completion off; ''DQN + link-budget ' ...
    'completion (hybrid)'' adds a hand-made part:'], nm, dep)};
LS = struct('set', {}, 'n', {}, 'off', {}, 'on', {}, 'delta', {}, 'ci', {}, 'rule', {});
for k = 1:numel(names)
    x = X(k);
    [d, lo, hi] = boot_cluster(x.x1 - x.x0, ones(size(x.x0)), x.g, 2000, S.cols(k));
    LS(end+1) = struct('set', names{k}, 'n', numel(x.x0), 'off', mean(x.x0), 'on', mean(x.x1), 'delta', d, ...
        'ci', [lo hi], 'rule', mean(x.xr)); %#ok<AGROW>
    lines{end+1} = sprintf(fmt, names{k}, LS(end).n, 100 * LS(end).off, 100 * LS(end).on, 100 * d, 100 * lo, 100 * hi, ...
        100 * LS(end).rule); %#ok<AGROW>
end
[p0, p1, pr, pg] = deal([]);                                   % the path-loss family
for k = find(ismember(names, {'single', 'combined', 'unknown'}))
    q = logical(X(k).fam(:))';
    p0 = [p0, X(k).x0(q)]; p1 = [p1, X(k).x1(q)]; pr = [pr, X(k).xr(q)]; pg = [pg, X(k).g(q)]; %#ok<AGROW>
end
[d, lo, hi] = boot_cluster(p1 - p0, ones(size(p0)), pg, 2000, S.cols(end));
LS(end+1) = struct('set', 'path-loss family', 'n', numel(p0), 'off', mean(p0), 'on', mean(p1), 'delta', d, ...
    'ci', [lo hi], 'rule', mean(pr));
lines{end+1} = [sprintf(fmt, 'family', LS(end).n, 100 * LS(end).off, 100 * LS(end).on, 100 * d, 100 * lo, 100 * hi, ...
    100 * LS(end).rule) '   (path-loss family: single, combined, unknown)'];
lines{end+1} = sprintf(['  clean link, Eb/N0 >= %g dB: episodes with a change %d/%d without the completion, %d/%d with it'], ...
    ebno_thr, cl(1), cl(3), cl(2), cl(3));
t = ismember(names, {'single', 'follower', 'combined'});
t0 = [X(t).x0]; t1 = [X(t).x1]; tr = [X(t).xr];
kpi = {sprintf(['beside KPI 5, the link-budget completion (a hand-made part beside the learned one; threat sets pooled, ' ...
    'recovered among the recoverable): DQN, learned part alone (completion off) %.1f%% | DQN + link-budget completion ' ...
    '(hybrid) %.1f%% | rule + escalation %.1f%%; deployed switch %s'], 100 * mean(t0), 100 * mean(t1), 100 * mean(tr), dep)};
L = struct('policy', nm, 'deployed', strcmp(dep, 'on'), 'sets', LS, 'clean', cl, 'lines', {lines}, 'kpi', {kpi});
end
