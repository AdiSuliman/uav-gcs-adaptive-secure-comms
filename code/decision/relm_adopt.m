function A = relm_adopt(Std, Off, Per, Cln)
%RELM_ADOPT  Whether the release to no_action on evidence (PP.release_m, policy_decide.m) is adopted for
%   the agent train_dqn.m selected, from the same episodes flown without it (X.off) and with it (X.on)
%   on the validation split. Each set X is a struct: off, on (per-episode readings of the two runs:
%   recovered, held, recoverable, threat; rel_on and cost_end where named), thr (the threat of every
%   episode, severities pooled), cl (the cluster of every episode: a flight geometry at an Eb/N0).
%   Std  the standard validation sets (every threat, combined threats and the clean link)
%   Off  the single threats ending 20 cycles after the onset, 50-cycle episodes (cost_end)
%   Per  the same threats persisting, 50-cycle episodes (rel_on: releases while the threat is on)
%   Cln  false changes on the clean validation flights: sw_off, sw_on (per flight), T the cycles of a
%        flight, period_ms
%   Adopted only if all hold:
%   (a) the running cost per cycle after the end falls: the one-sided 95% upper bound of the paired
%       difference is below 0 (cluster bootstrap, 10000 draws, fixed seed)
%   (b) per threat, on the persistent set: the share of episodes with a release while the threat is on
%       rises by at most 0.5 point, and the exact one-sided McNemar test of a rise is not significant at 0.05
%   (c) on the persistent set and the standard sets: held recovery per threat falls by at most 1 point,
%       pooled held by at most 0.5 point, recovered per threat by at most 1 point
%   (d) the false-change rate on the clean flights with the release is at most the one-sided 95% Garwood
%       upper bound of the rate without it (non-inferiority, the margin that bound's half-width)
%   A.adopt, A.a, A.b, A.c, A.d; A.lines the readings.
A = struct('adopt', false, 'a', false, 'b', false, 'c', false, 'd', false, 'lines', {{}});
% (a)
m = isfinite(Off.off.cost_end(:)') & isfinite(Off.on.cost_end(:)') & Off.off.threat(:)';
d = Off.on.cost_end(m) - Off.off.cost_end(m);
cl = Off.cl(:)';
[pm, ~, ub] = paired_stats('boot', d, cl(m), 10000, 114);
A.a = ub < 0;
A.lines{end+1} = sprintf(['  (a) running cost held after the end: %.2f points per cycle without, %.2f with it, paired difference %+.3f, ' ...
    'one-sided 95%% upper bound %+.3f over %d episodes: %s'], mean(Off.off.cost_end(m)), mean(Off.on.cost_end(m)), pm, ub, sum(m), ...
    ternary(A.a, 'ok', 'not below 0'));
% (b)
thr = Per.thr(:)'; pt = Per.off.threat(:)' & Per.on.threat(:)';
r0 = Per.off.rel_on(:)' > 0; r1 = Per.on.rel_on(:)' > 0;
A.b = true; txt = {};
for t = unique(thr(pt), 'stable')
    mt = pt & strcmp(thr, t{1});
    rise = mean(r1(mt)) - mean(r0(mt));
    p = paired_stats('mcnemar', sum(r1(mt) & ~r0(mt)), sum(r0(mt) & ~r1(mt)));
    ok = rise <= 0.005 && p >= 0.05;
    A.b = A.b && ok;
    txt{end+1} = sprintf('%s %.1f%% -> %.1f%% (p %.2g)%s', t{1}, 100 * mean(r0(mt)), 100 * mean(r1(mt)), p, ternary(ok, '', ' FAILS')); %#ok<AGROW>
end
A.b = A.b && ~isempty(txt);
A.lines{end+1} = sprintf('  (b) episodes with a release while the threat is on, persistent set, without -> with: %s: %s', ...
    strjoin(txt, ', '), ternary(A.b, 'ok', 'a threat fails'));
% (c)
A.c = true;
for S = {Per, 'persistent set'; Std, 'standard validation sets'}'
    X = S{1};
    thr = X.thr(:)';
    k0 = X.off.recoverable(:)' & X.off.threat(:)'; k1 = X.on.recoverable(:)' & X.on.threat(:)';
    dh = mean(X.on.held(k1)) - mean(X.off.held(k0));
    ok = dh >= -0.005; bad = {};
    for t = unique(thr(k0 | k1), 'stable')
        i0 = k0 & strcmp(thr, t{1}); i1 = k1 & strcmp(thr, t{1});
        if ~any(i0) || ~any(i1), continue; end
        h = mean(X.on.held(i1)) - mean(X.off.held(i0)); r = mean(X.on.recovered(i1)) - mean(X.off.recovered(i0));
        if h < -0.01 || r < -0.01, bad{end+1} = sprintf('%s held %+.1f recovered %+.1f', t{1}, 100 * h, 100 * r); end %#ok<AGROW>
    end
    ok = ok && isempty(bad);
    A.c = A.c && ok;
    A.lines{end+1} = sprintf('  (c) %s: pooled held %+.2f points%s: %s', S{2}, 100 * dh, ...
        ternary(isempty(bad), '', ['; ' strjoin(bad, ', ')]), ternary(ok, 'ok', 'a recovery cost'));
end
% (d)
k0 = sum(Cln.sw_off); k1 = sum(Cln.sw_on); cyc = Cln.T * numel(Cln.sw_off);
hr = 3600e3 / Cln.period_ms;
u0 = paired_stats('garwood', k0, cyc);
A.d = numel(Cln.sw_on) == numel(Cln.sw_off) && k1 / cyc <= u0;
A.lines{end+1} = sprintf(['  (d) false changes on the %d clean validation flights: %d without (%.1f per hour, one-sided 95%% upper bound %.1f), ' ...
    '%d with the release (%.1f per hour); non-inferiority margin %.1f per hour, the plain DQN''s one-sided 95%% Garwood half-width: %s'], ...
    numel(Cln.sw_off), k0, hr * k0 / cyc, hr * u0, k1, hr * k1 / cyc, hr * (u0 - k0 / cyc), ...
    ternary(A.d, 'ok, within the margin', 'above the margin'));
A.adopt = A.a && A.b && A.c && A.d;
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
