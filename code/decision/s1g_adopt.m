function A = s1g_adopt(V0, V1, thr, s, sw0, sw1)
%S1G_ADOPT  Whether the rule's lost-branch gate (PP.s1_gate, policy_decide.m) stays on after the
%   selection rule (train_dqn.m rank_pick) picked it: two conditions on validation.
%   V0, V1   rule + escalation without and with the gate on the validation episodes
%            (dqn_eval_batches.m: recovered, recoverable, threat, r per episode)
%   thr      the threat of every episode, severities pooled; s the Eb/N0 index of every episode
%   sw0, sw1 the changes of the two on the clean validation flights, one entry per flight
%            (the same flights); [] when there are none
%   (g1) every threat other than antenna_fault, airframe_shadowing and their combinations: the
%        rule's recovered (KPI 4's reading, the episodes recoverable under both) moves by no less
%        than -1.0 point, paired, and its one-sided 95% lower bound is no lower than -2.0
%        (cluster bootstrap over the flights, a geometry at an Eb/N0; 2000 draws, fixed seed)
%   (g2) the clean flights with a change fall, by the exact one-sided McNemar test, p < 0.05
%   A.keep: both hold; A.g1, A.g2, A.p; A.rows the threats' readings; A.lost the same reading on
%   the lost-branch threats (reported, not a condition).
thr = thr(:)'; s = s(:)';
cl = 1000 * s + V0.r(:)';
m = V0.recoverable(:)' & V1.recoverable(:)' & V0.threat(:)';
lost = contains(thr, 'antenna_fault') | contains(thr, 'airframe_shadowing');
A = struct('keep', false, 'g1', false, 'g2', false, 'p', NaN, 'rows', {{}}, 'lost', {{}});
g1 = true; nt = 0;
for t = unique(thr(m & ~lost), 'stable')
    mt = m & strcmp(thr, t{1});
    d = double(V1.recovered(mt)) - double(V0.recovered(mt));
    [pt, lb] = paired_stats('boot', d, cl(mt), 2000, 113);
    ok = 100 * pt >= -1.0 && 100 * lb >= -2.0;
    g1 = g1 && ok; nt = nt + 1;
    A.rows{end+1} = sprintf('    %-34s n %5d: recovered %+.2f points, lower bound %+.2f: %s', t{1}, sum(mt), 100 * pt, 100 * lb, ternary(ok, 'ok', 'below the floor'));
end
A.g1 = g1 && nt > 0;
for t = unique(thr(m & lost), 'stable')
    mt = m & strcmp(thr, t{1});
    [~, lo, hi] = paired_stats('boot', double(V0.recovered(mt)), cl(mt), 2000, 114);
    [~, lo1, hi1] = paired_stats('boot', double(V1.recovered(mt)), cl(mt), 2000, 115);
    A.lost{end+1} = sprintf('    %-34s n %5d: recovered without the gate %.1f%% [%.1f, %.1f] (the reference), with it %.1f%% [%.1f, %.1f]', ...
        t{1}, sum(mt), 100 * mean(V0.recovered(mt)), 100 * lo, 100 * hi, 100 * mean(V1.recovered(mt)), 100 * lo1, 100 * hi1);
end
if ~isempty(sw0) && numel(sw0) == numel(sw1)
    f0 = sw0(:) > 0; f1 = sw1(:) > 0;
    A.p = paired_stats('mcnemar', sum(f0 & ~f1), sum(f1 & ~f0));
    A.g2 = A.p < 0.05;
    A.rows{end+1} = sprintf('    clean validation flights with a change: %d without the gate, %d with it, %d fall and %d rise, exact McNemar p = %.3g: %s', ...
        sum(f0), sum(f1), sum(f0 & ~f1), sum(f1 & ~f0), A.p, ternary(A.g2, 'ok', 'not significant'));
else
    A.rows{end+1} = '    clean validation flights: not measured, the gate stays off';
end
A.keep = A.g1 && A.g2;
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
