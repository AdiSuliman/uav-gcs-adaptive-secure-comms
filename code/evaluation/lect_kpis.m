function [L, lines] = lect_kpis(ALL, POL, LBL, iDQN, scen, payload_bps, period_ms)
%LECT_KPIS  The revised proposal's link KPIs from the pooled threat sets of evaluate_policies.m.
%   [L, lines] = lect_kpis(ALL, POL, LBL, iDQN, scen, payload_bps, period_ms)
%   ALL     1 x policies, per-episode results (rollout_policy.m, policy_run_set.m), the same
%           episodes under every policy (common random numbers)
%   POL, LBL, iDQN  policy keys, labels and the deployed policy's index; scen  PP.scen
%   payload_bps     nominal payload rate [bit/s]: payload bits per frame / decision cycle
%   period_ms       decision period [ms]
%   PER (packet error rate, true packet loss by CRC; per_metrics.m) on the RECOVERABLE episodes
%   of the jamming threats (JAM below; narrowband tone_jamming, wideband barrage jamming):
%     reduction vs the static link (no response) = 1 - mean PER under the policy / mean PER
%     under no response, paired by episode, 95% bootstrap over flight geometries
%     (per_reduction.m); target >= 30% for rule + escalation (CNN-based adaptive), also read
%     for the escalation without the detector (metric-only adaptive) and the deployed policy;
%     the CNN's share: rule + escalation against the same response without the detector.
%   Recovery time (lecturer): cycles from the first confirmed alarm's frame until the packet
%     loss is restored (<= 2x clean + one loss event) for 5 consecutive cycles (t_rec_det),
%     beside the onset-to-detection time (t_conf) and the existing T_rec from onset (BER and
%     packet loss); median and p90 over the episodes where they occur, with the share where
%     they never do.
%   Goodput: delivered payload after onset in bit/s (payload_bps x dlv_post), mean with a 95%
%     bootstrap over flight geometries, beside the normalized goodput (gput_post).
JAM = {'jamming', 'noise_burst', 'reactive_jamming', 'sweeping_jammer', 'tone_jamming'};
BAND = {'wideband', '', '', '', 'narrowband'};
TARGET = 30; N_RUN = 5; B = 2000;
has = @(p) any(strcmp(POL, p));
col = @(p) find(strcmp(POL, p), 1);
R1 = ALL{1};
nm = reshape(scen(R1.scn), 1, []);
mrec = R1.recoverable & R1.threat;
jam = ismember(nm, JAM);
mj = mrec & jam;
iN = col('none');
dep = POL{iDQN};
dqk = 'dqn_esc'; if startsWith(dep, 'dqn'), dqk = dep; end
kp = unique({'rule_esc', 'blind_esc', dep}, 'stable'); kp = kp(cellfun(has, kp));
kr = unique({'none', 'blind_esc', 'rule_esc', dqk, dep}, 'stable'); kr = kr(cellfun(has, kr));
kg = unique([kr, {'oracle'}], 'stable'); kg = kg(cellfun(has, kg));
lab = @(p) LBL{col(p)};
L = struct('jam', {JAM}, 'target_pct', TARGET, 'run', N_RUN, 'payload_bps', payload_bps, 'period_ms', period_ms);
lines = {'', sprintf(['--- Revised-proposal KPIs: PER vs the static link, recovery time from detection, goodput in ' ...
    'bit/s (threat sets pooled; jamming threats: %s) ---'], strjoin(JAM, ', '))};

% PER reduction vs the static link
ref = ALL{iN}.per_post;
lines{end+1} = sprintf(['PER after onset on the recoverable jamming episodes (%d), reduction vs the static link (no response), ' ...
    'paired by episode, 95%% bootstrap over flight geometries; target >= %d%% for rule + escalation:'], sum(mj), TARGET);
L.per = struct('policy', {}, 'label', {}, 'n', {}, 'per_ref_pct', {}, 'per_pct', {}, 'red_pct', {}, 'ci', {}, ...
    'met', {}, 'ci_above', {});
for j = 1:numel(kp)
    pol = ALL{col(kp{j})}.per_post;
    ok = mj & isfinite(pol) & isfinite(ref);
    [r, lo, hi] = per_reduction(pol(ok), ref(ok), R1.geom(ok), B, 200 + j);
    L.per(j) = struct('policy', kp{j}, 'label', lab(kp{j}), 'n', sum(ok), 'per_ref_pct', 100 * mean(ref(ok)), ...
        'per_pct', 100 * mean(pol(ok)), 'red_pct', 100 * r, 'ci', 100 * [lo hi], 'met', 100 * r >= TARGET, ...
        'ci_above', 100 * lo >= TARGET);
    q = L.per(j);
    lines{end+1} = sprintf('  %-44s PER %6.2f%% vs %6.2f%% static: reduction %6.1f%% [%.1f, %.1f]%s', q.label, ...
        q.per_pct, q.per_ref_pct, q.red_pct, q.ci, ternary(strcmp(q.policy, 'rule_esc'), sprintf(' -> %s (interval %s %d%%)', ...
        ternary(q.met, 'MET', 'NOT MET'), ternary(q.ci_above, 'above', 'not wholly above'), TARGET), '')); %#ok<AGROW>
end
L.per_threat = struct('threat', {}, 'band', {}, 'n', {}, 'per_ref_pct', {}, 'red_pct', {}, 'ci', {});
lines{end+1} = sprintf('  per jamming threat, reduction %% [95%%] (%s):', strjoin(cellfun(lab, kp, 'UniformOutput', false), ' | '));
for t = 1:numel(JAM)
    mt = mj & strcmp(nm, JAM{t});
    if ~any(mt), continue; end
    rr = nan(1, numel(kp)); cc = nan(numel(kp), 2);
    for j = 1:numel(kp)
        pol = ALL{col(kp{j})}.per_post;
        ok = mt & isfinite(pol) & isfinite(ref);
        [rr(j), cc(j, 1), cc(j, 2)] = per_reduction(pol(ok), ref(ok), R1.geom(ok), B, 300 + 10 * t + j);
    end
    L.per_threat(end+1) = struct('threat', JAM{t}, 'band', BAND{t}, 'n', sum(mt), ...
        'per_ref_pct', 100 * mean(ref(mt), 'omitnan'), 'red_pct', 100 * rr, 'ci', 100 * cc);
    lines{end+1} = sprintf('    %-30s %4d, static PER %6.2f%%: %s', strtrim(sprintf('%s %s', JAM{t}, ...
        ternary(isempty(BAND{t}), '', ['(' BAND{t} ')']))), sum(mt), 100 * mean(ref(mt), 'omitnan'), ...
        strjoin(arrayfun(@(j) sprintf('%.1f [%.1f, %.1f]', 100 * rr(j), 100 * cc(j, 1), 100 * cc(j, 2)), 1:numel(kp), ...
        'UniformOutput', false), ' | ')); %#ok<AGROW>
end
L.cnn = struct('per_red_pct', NaN, 'per_ci', [NaN NaN], 'gput_bps', NaN, 'gput_ci', [NaN NaN], 'n', 0);
if has('rule_esc') && has('blind_esc')
    pr = ALL{col('rule_esc')}.per_post; pb = ALL{col('blind_esc')}.per_post;
    ok = mj & isfinite(pr) & isfinite(pb);
    [r, lo, hi] = per_reduction(pr(ok), pb(ok), R1.geom(ok), B, 400);
    dg = payload_bps * (ALL{col('rule_esc')}.dlv_post - ALL{col('blind_esc')}.dlv_post);
    [g, gl, gh] = boot_cluster(dg(ok), ones(1, sum(ok)), R1.geom(ok), B, 401);
    L.cnn = struct('per_red_pct', 100 * r, 'per_ci', 100 * [lo hi], 'gput_bps', g, 'gput_ci', [gl gh], 'n', sum(ok));
    lines{end+1} = sprintf(['  CNN contribution (rule + escalation vs the same escalation without the detector, the same %d ' ...
        'episodes): PER reduction %.1f%% [%.1f, %.1f], goodput %+.0f bit/s [%+.0f, %+.0f]'], sum(ok), 100 * r, 100 * lo, ...
        100 * hi, g, gl, gh);
end

% Recovery time from detection, onset-to-detection, T_rec from onset
lines{end+1} = sprintf(['Recovery time (lecturer): from the first confirmed alarm''s frame until the packet loss stays <= 2x ' ...
    'clean for %d consecutive cycles; beside it the onset-to-detection time and T_rec from onset (BER and packet loss); ' ...
    'median / p90 [cycles of %g ms] (never %%):'], N_RUN, period_ms);
L.rec = struct('set', {}, 'policy', {}, 'label', {}, 'n', {}, 'det', {}, 'rec_det', {}, 't_rec', {});
sets = {mrec, mj}; sn = {'recoverable threat episodes', 'recoverable jamming episodes'};
for si = 1:2
    m = sets{si};
    lines{end+1} = sprintf('  %s (%d): onset -> detection | detection -> PER restored | T_rec from onset', sn{si}, sum(m)); %#ok<AGROW>
    for j = 1:numel(kr)
        R = ALL{col(kr{j})};
        d = R.t_conf(m); dt = isfinite(d);
        rd = R.t_rec_det(m); rd = rd(dt);
        q = struct('set', sn{si}, 'policy', kr{j}, 'label', lab(kr{j}), 'n', sum(m), 'det', tstat(d), ...
            'rec_det', tstat(rd), 't_rec', tstat(R.t_rec(m)));
        L.rec(end+1) = q;
        lines{end+1} = sprintf('    %-44s %s | %s | %s', q.label, ttxt(q.det, period_ms), ttxt(q.rec_det, period_ms), ...
            ttxt(q.t_rec, period_ms)); %#ok<AGROW>
    end
end

% Goodput in bit/s beside the normalized goodput
lines{end+1} = sprintf(['Goodput after onset in bit/s (nominal payload rate %s: payload bits per frame per decision ' ...
    'cycle; a frame delivers goodput factor x (1 - packet loss), none before a coded link''s first packet), mean ' ...
    '[95%%] beside the normalized goodput:'], bps_txt(payload_bps));
L.gput = struct('policy', {}, 'label', {}, 'bps', {}, 'ci', {}, 'bps_jam', {}, 'ci_jam', {}, 'norm', {}, 'norm_jam', {});
mt = R1.threat;
for j = 1:numel(kg)
    R = ALL{col(kg{j})};
    a = payload_bps * R.dlv_post;
    [g, gl, gh] = boot_cluster(a(mt), ones(1, sum(mt)), R1.geom(mt), B, 500 + j);
    [gj, gjl, gjh] = boot_cluster(a(mj), ones(1, sum(mj)), R1.geom(mj), B, 600 + j);
    L.gput(end+1) = struct('policy', kg{j}, 'label', lab(kg{j}), 'bps', g, 'ci', [gl gh], 'bps_jam', gj, ...
        'ci_jam', [gjl gjh], 'norm', mean(R.gput_post(mt), 'omitnan'), 'norm_jam', mean(R.gput_post(mj), 'omitnan'));
    q = L.gput(end);
    lines{end+1} = sprintf(['  %-44s threat episodes (%d) %s [%s, %s], normalized %.3f | recoverable jamming (%d) %s ' ...
        '[%s, %s], normalized %.3f'], q.label, sum(mt), bps_txt(g), bps_txt(gl), bps_txt(gh), q.norm, sum(mj), ...
        bps_txt(gj), bps_txt(gjl), bps_txt(gjh), q.norm_jam); %#ok<AGROW>
end
end

function s = tstat(x)
% Median and p90 (nearest rank) of the finite values, the share of NaN (never).
x = x(:)'; f = sort(x(isfinite(x)));
s = struct('n', numel(x), 'median', NaN, 'p90', NaN, 'never_pct', 100 * mean(~isfinite(x)));
if isempty(x), s.never_pct = NaN; end
if ~isempty(f), s.median = median(f); s.p90 = f(min(numel(f), max(1, round(0.9 * numel(f))))); end
end

function s = ttxt(q, period_ms)
if isnan(q.median), s = sprintf('- (never %.1f%%)', q.never_pct); return; end
s = sprintf('%g / %g (%g / %g ms, never %.1f%%)', q.median, q.p90, q.median * period_ms, q.p90 * period_ms, q.never_pct);
end

function s = bps_txt(x)
if ~isfinite(x), s = 'n/a'; elseif abs(x) >= 1e3, s = sprintf('%.2f kb/s', x / 1e3); else, s = sprintf('%.0f b/s', x); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
