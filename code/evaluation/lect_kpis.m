function [L, lines] = lect_kpis(ALL, POL, LBL, iDQN, scen, payload_bps, period_ms)
%LECT_KPIS  The revised proposal's link KPIs from the pooled threat sets of evaluate_policies.m.
%   [L, lines] = lect_kpis(ALL, POL, LBL, iDQN, scen, payload_bps, period_ms)
%   ALL     1 x policies, per-episode results (rollout_policy.m, policy_run_set.m), the same
%           episodes under every policy (common random numbers)
%   POL, LBL, iDQN  policy keys, labels and the deployed policy's index; scen  PP.scen
%   payload_bps     nominal payload rate [bit/s]: payload bits per frame / decision cycle
%   period_ms       decision period [ms]
%   PER (packet error rate, true packet loss by CRC; per_metrics.m) on the RECOVERABLE episodes
%   of the jamming threats (JAM below): reduction vs the static link (no response) = 1 - mean
%   PER under the policy / mean PER under no response, paired by episode, 95% bootstrap over
%   flight geometries (per_reduction.m), for rule + escalation (CNN-based adaptive), the
%   escalation without the detector (metric-only adaptive) and the deployed policy.
%   Primary verdict (L.verdict), the lecturer's two jamming scenarios each on its own:
%   narrowband = tone_jamming, wideband = jamming; rule + escalation's reduction >= 30% is
%   MET (committed) when the 95% lower bound clears it, MET (not committed) when only the
%   point does, NOT MET otherwise. The five jamming threats pooled (L.per) are an extension,
%   with the same verdict words.
%   The CNN's share: rule + escalation against the same response without the detector, in
%   PER and goodput (paired) and in recovery time (onset to detection and detection to
%   restored of each, on the recoverable jamming episodes).
%   Recoverable: the static link's episode flags (ALL{1}, link_env.m), fixed by the pools and
%   the episode specs before any policy is read: some configuration of the 36 restores the
%   geometry (recoverable), or some configuration of the core action set does (recoverable_core).
%   Recovery time (lecturer): cycles from the first confirmed alarm's frame until the packet
%     loss is restored (<= 2x clean + one loss event) for 5 consecutive cycles (t_rec_det),
%     beside the onset-to-detection time (t_conf) and the existing T_rec from onset (BER and
%     packet loss); median and p90 over the episodes where they occur, with the share where
%     they never do.
%   Goodput: delivered payload after onset in bit/s (payload_bps x dlv_post), mean with a 95%
%     bootstrap over flight geometries, beside the normalized goodput (gput_post).
%   These are the full action set's (the 36 configurations). L.core holds the same readings on
%   the revised proposal's core action set (decision_config.m C.core_actions: channel
%   switching and rate adaptation), for the rule with escalation with and without the
%   detector there (rule_core, blind_core; rule_core_policy.m) against the same static link,
%   the CNN's share rule_core against blind_core; [] when neither ran. Its primary reading
%   is on the episodes a core configuration recovers (recoverable_core); L.core.all36 holds
%   the same on the episodes any of the 36 recovers (a second, conservative line: an episode
%   only a configuration outside the core set restores counts against it).
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
X = struct('ALL', {ALL}, 'has', has, 'col', col, 'lab', lab, 'R1', R1, 'nm', {nm}, 'mrec', mrec, 'mj', mj, ...
    'ref', ALL{iN}.per_post, 'JAM', {JAM}, 'BAND', {BAND}, 'TARGET', TARGET, 'N_RUN', N_RUN, 'B', B, ...
    'payload_bps', payload_bps, 'period_ms', period_ms, 'rec_txt', 'some configuration of the 36 restores the geometry');
L = struct('jam', {JAM}, 'target_pct', TARGET, 'run', N_RUN, 'payload_bps', payload_bps, 'period_ms', period_ms, ...
    'recoverable', 'all36');
lines = {'', sprintf(['--- Revised-proposal KPIs: PER vs the static link, recovery time from detection, goodput in ' ...
    'bit/s (threat sets pooled; jamming threats: %s) ---'], strjoin(JAM, ', '))};
lines{end+1} = 'Full action set (the 36 configurations):';

[P, PT, V, CN, l] = per_block(X, kp, 'rule_esc', 'blind_esc', '', 'rule + escalation', ...
    'rule + escalation vs the same escalation without the detector', 200);
L.verdict = V; L.per = P; L.per_threat = PT; L.cnn = CN; lines = [lines, l];
[L.rec, l] = rec_block(X, kr, ''); lines = [lines, l];
[L.gput, l] = gput_block(X, kg, '', 500); lines = [lines, l];

% The core action set: the same readings, the same episodes and static link
L.core = [];
kc = {'rule_core', 'blind_core'}; kc = kc(cellfun(has, kc));
if isempty(kc), return; end
C = decision_config();
if ~isfield(R1, 'recoverable_core')
    error('lect_kpis:core_flags', 'lect_kpis: the core policies ran but the episodes carry no recoverable_core (rollout_policy.m)');
end
Xc = X; Xc.mrec = R1.recoverable_core & R1.threat; Xc.mj = Xc.mrec & jam;
Xc.rec_txt = 'some configuration of the core action set restores the geometry';
kcr = {'none', 'blind_core', 'rule_core'}; kcr = kcr(cellfun(has, kcr));
lines{end+1} = sprintf(['Core action set {%s} (the revised proposal''s predefined actions, channel switching and ' ...
    'transmission-rate adaptation; escalation %s), the same episodes and static link; primary: the episodes a core ' ...
    'configuration recovers (%d recoverable threat episodes, %d jamming):'], strjoin(C.core_actions, ', '), ...
    strjoin(C.ladder_core, ' -> '), sum(Xc.mrec), sum(Xc.mj));
[S, l] = core_reading(Xc, kc, kcr, 'Core action set: ', 1200, 1500); lines = [lines, l];
lines{end+1} = sprintf(['Core action set, conservative line: the episodes any of the 36 configurations recovers ' ...
    '(%d recoverable threat episodes, %d jamming; one only a configuration outside the core set restores counts ' ...
    'against it):'], sum(X.mrec), sum(X.mj));
[S36, l] = core_reading(X, kc, kcr, 'Core action set (recoverable by the 36): ', 2200, 2500); lines = [lines, l];
S36.recoverable = 'all36';
L.core = struct('actions', {C.core_actions}, 'ladder', {C.ladder_core}, 'recoverable', 'core', 'verdict', S.verdict, ...
    'per', S.per, 'per_threat', S.per_threat, 'cnn', S.cnn, 'rec', S.rec, 'gput', S.gput, 'all36', S36);
end

function [S, lines] = core_reading(X, kc, kcr, pre, s0, g0)
% The core action set's readings on the recoverable episodes of X: PER (bootstrap seeds
% from s0), recovery time and goodput (from g0).
[P, PT, V, CN, lines] = per_block(X, kc, 'rule_core', 'blind_core', pre, 'core rule + escalation', ...
    'core rule + escalation vs the same core escalation without the detector', s0);
[RC, l] = rec_block(X, kcr, pre); lines = [lines, l];
[GC, l] = gput_block(X, kcr, pre, g0); lines = [lines, l];
S = struct('verdict', V, 'per', P, 'per_threat', PT, 'cnn', CN, 'rec', RC, 'gput', GC);
end

function [P, PT, V, CN, lines] = per_block(X, kp, tgt, conv, pre, ttl, cnn_ttl, s0)
% PER reduction vs the static link of the policies kp on the recoverable jamming episodes:
% the primary verdict of tgt per lecturer scenario (V), the five threats pooled (P, the
% extension), per jamming threat (PT), and the CNN's share: tgt (with the detector) against
% conv (the same without it); bootstrap seeds from s0.
ALL = X.ALL; R1 = X.R1; ref = X.ref; mj = X.mj; col = X.col; lab = X.lab; JAM = X.JAM; BAND = X.BAND;
TARGET = X.TARGET; B = X.B;
P = struct('policy', {}, 'label', {}, 'n', {}, 'per_ref_pct', {}, 'per_pct', {}, 'red_pct', {}, 'ci', {}, ...
    'met', {}, 'ci_above', {}, 'verdict', {});
for j = 1:numel(kp)
    pol = ALL{col(kp{j})}.per_post;
    ok = mj & isfinite(pol) & isfinite(ref);
    [r, lo, hi] = per_reduction(pol(ok), ref(ok), R1.geom(ok), B, s0 + j);
    P(j) = struct('policy', kp{j}, 'label', lab(kp{j}), 'n', sum(ok), 'per_ref_pct', 100 * mean(ref(ok)), ...
        'per_pct', 100 * mean(pol(ok)), 'red_pct', 100 * r, 'ci', 100 * [lo hi], 'met', 100 * r >= TARGET, ...
        'ci_above', 100 * lo >= TARGET, 'verdict', verdict_word(100 * r, 100 * lo, TARGET));
end
PT = struct('threat', {}, 'band', {}, 'n', {}, 'per_ref_pct', {}, 'red_pct', {}, 'ci', {});
for t = 1:numel(JAM)
    mt = mj & strcmp(X.nm, JAM{t});
    if ~any(mt), continue; end
    rr = nan(1, numel(kp)); cc = nan(numel(kp), 2);
    for j = 1:numel(kp)
        pol = ALL{col(kp{j})}.per_post;
        ok = mt & isfinite(pol) & isfinite(ref);
        [rr(j), cc(j, 1), cc(j, 2)] = per_reduction(pol(ok), ref(ok), R1.geom(ok), B, s0 + 100 + 10 * t + j);
    end
    PT(end+1) = struct('threat', JAM{t}, 'band', BAND{t}, 'n', sum(mt), ...
        'per_ref_pct', 100 * mean(ref(mt), 'omitnan'), 'red_pct', 100 * rr, 'ci', 100 * cc); %#ok<AGROW>
end
% Primary: the lecturer's two scenarios, narrowband then wideband, each read on its own
jt = find(strcmp(kp, tgt), 1);
V = struct('scenario', {}, 'threat', {}, 'policy', {}, 'label', {}, 'n', {}, 'per_ref_pct', {}, 'red_pct', {}, ...
    'ci', {}, 'met', {}, 'committed', {}, 'verdict', {});
sc = {'narrowband', 'wideband'}; if isempty(jt), sc = {}; end
for b = sc
    th = JAM{strcmp(BAND, b{1})};
    q = PT(strcmp({PT.threat}, th));
    v = struct('scenario', b{1}, 'threat', th, 'policy', tgt, 'label', lab(tgt), 'n', 0, 'per_ref_pct', NaN, ...
        'red_pct', NaN, 'ci', [NaN NaN], 'met', false, 'committed', false, 'verdict', 'NOT MET');
    if ~isempty(q)
        v.n = q.n; v.per_ref_pct = q.per_ref_pct; v.red_pct = q.red_pct(jt); v.ci = q.ci(jt, :);
        v.met = v.red_pct >= TARGET; v.committed = v.ci(1) >= TARGET;
        v.verdict = verdict_word(v.red_pct, v.ci(1), TARGET);
    end
    V(end+1) = v; %#ok<AGROW>
end
lines = {sprintf([pre 'PER after onset vs the static link (no response), paired by episode, 95%% bootstrap over ' ...
    'flight geometries; recoverable episodes: %s. Target (lecturer) >= %d%% reduction for %s in each of the two ' ...
    'jamming scenarios: MET (committed) when the 95%% lower bound clears it, MET (not committed) when only the ' ...
    'point does, NOT MET otherwise:'], X.rec_txt, TARGET, ttl)};
for v = V
    if v.n == 0
        lines{end+1} = sprintf('  PRIMARY %s (%s): no recoverable episodes -> %s', v.scenario, v.threat, v.verdict); %#ok<AGROW>
    else
        lines{end+1} = sprintf('  PRIMARY %s (%s), %d recoverable episodes, static PER %.2f%%: %s reduction %.1f%% [%.1f, %.1f] -> %s', ...
            v.scenario, v.threat, v.n, v.per_ref_pct, v.label, v.red_pct, v.ci, v.verdict); %#ok<AGROW>
    end
end
lines{end+1} = sprintf('  extension, the five jamming threats pooled (%d recoverable episodes; %s):', sum(mj), strjoin(JAM, ', '));
for q = P
    lines{end+1} = sprintf('    %-42s PER %6.2f%% vs %6.2f%% static: reduction %6.1f%% [%.1f, %.1f]%s', q.label, ...
        q.per_pct, q.per_ref_pct, q.red_pct, q.ci, ternary(strcmp(q.policy, tgt), [' -> ' q.verdict], '')); %#ok<AGROW>
end
lines{end+1} = sprintf('  per jamming threat, reduction %% [95%%] (%s):', strjoin(cellfun(lab, kp, 'UniformOutput', false), ' | '));
for q = PT
    lines{end+1} = sprintf('    %-30s %4d, static PER %6.2f%%: %s', strtrim(sprintf('%s %s', q.threat, ...
        ternary(isempty(q.band), '', ['(' q.band ')']))), q.n, q.per_ref_pct, ...
        strjoin(arrayfun(@(j) sprintf('%.1f [%.1f, %.1f]', q.red_pct(j), q.ci(j, 1), q.ci(j, 2)), 1:numel(kp), ...
        'UniformOutput', false), ' | ')); %#ok<AGROW>
end
e = [tstat([]), tstat([])];
CN = struct('per_red_pct', NaN, 'per_ci', [NaN NaN], 'gput_bps', NaN, 'gput_ci', [NaN NaN], 'n', 0, 'det', e, 'rec_det', e);
if X.has(tgt) && X.has(conv)
    Rt = ALL{col(tgt)}; Rc = ALL{col(conv)};
    pr = Rt.per_post; pb = Rc.per_post;
    ok = mj & isfinite(pr) & isfinite(pb);
    [r, lo, hi] = per_reduction(pr(ok), pb(ok), R1.geom(ok), B, s0 + 200);
    dg = X.payload_bps * (Rt.dlv_post - Rc.dlv_post);
    [g, gl, gh] = boot_cluster(dg(ok), ones(1, sum(ok)), R1.geom(ok), B, s0 + 201);
    det = [tstat(Rt.t_conf(mj)), tstat(Rc.t_conf(mj))];
    rd = [tstat(Rt.t_rec_det(mj & isfinite(Rt.t_conf))), tstat(Rc.t_rec_det(mj & isfinite(Rc.t_conf)))];
    CN = struct('per_red_pct', 100 * r, 'per_ci', 100 * [lo hi], 'gput_bps', g, 'gput_ci', [gl gh], 'n', sum(ok), ...
        'det', det, 'rec_det', rd);
    lines{end+1} = sprintf(['  CNN contribution (%s, the same %d episodes): PER reduction %.1f%% [%.1f, %.1f], goodput ' ...
        '%+.0f bit/s [%+.0f, %+.0f]; recovery time on the %d recoverable jamming episodes, with vs without the ' ...
        'detector: onset -> detection %s vs %s, detection -> PER restored %s vs %s'], cnn_ttl, sum(ok), 100 * r, ...
        100 * lo, 100 * hi, g, gl, gh, sum(mj), ttxt(det(1), X.period_ms), ttxt(det(2), X.period_ms), ...
        ttxt(rd(1), X.period_ms), ttxt(rd(2), X.period_ms));
end
end

function [RC, lines] = rec_block(X, kr, pre)
% Onset to detection, detection to PER restored and T_rec from onset of the policies kr, on
% the recoverable threat episodes and on the recoverable jamming episodes.
lines = {sprintf([pre 'Recovery time (lecturer): from the first confirmed alarm''s frame until the packet loss stays ' ...
    '<= 2x clean for %d consecutive cycles; beside it the onset-to-detection time and T_rec from onset (BER and ' ...
    'packet loss); median / p90 [cycles of %g ms] (never %%):'], X.N_RUN, X.period_ms)};
RC = struct('set', {}, 'policy', {}, 'label', {}, 'n', {}, 'det', {}, 'rec_det', {}, 't_rec', {});
sets = {X.mrec, X.mj}; sn = {'recoverable threat episodes', 'recoverable jamming episodes'};
for si = 1:2
    m = sets{si};
    lines{end+1} = sprintf('  %s (%d): onset -> detection | detection -> PER restored | T_rec from onset', sn{si}, sum(m)); %#ok<AGROW>
    for j = 1:numel(kr)
        R = X.ALL{X.col(kr{j})};
        d = R.t_conf(m); dt = isfinite(d);
        rd = R.t_rec_det(m); rd = rd(dt);
        q = struct('set', sn{si}, 'policy', kr{j}, 'label', X.lab(kr{j}), 'n', sum(m), 'det', tstat(d), ...
            'rec_det', tstat(rd), 't_rec', tstat(R.t_rec(m)));
        RC(end+1) = q; %#ok<AGROW>
        lines{end+1} = sprintf('    %-44s %s | %s | %s', q.label, ttxt(q.det, X.period_ms), ttxt(q.rec_det, X.period_ms), ...
            ttxt(q.t_rec, X.period_ms)); %#ok<AGROW>
    end
end
end

function [GP, lines] = gput_block(X, kg, pre, s0)
% Goodput after onset in bit/s of the policies kg, on the threat episodes and on the
% recoverable jamming episodes, beside the normalized goodput; bootstrap seeds from s0.
R1 = X.R1; mj = X.mj; B = X.B;
lines = {sprintf([pre 'Goodput after onset in bit/s (nominal payload rate %s: payload bits per frame per decision ' ...
    'cycle; a frame delivers goodput factor x (1 - packet loss), none before a coded link''s first packet), mean ' ...
    '[95%%] beside the normalized goodput:'], bps_txt(X.payload_bps))};
GP = struct('policy', {}, 'label', {}, 'bps', {}, 'ci', {}, 'bps_jam', {}, 'ci_jam', {}, 'norm', {}, 'norm_jam', {});
mt = R1.threat;
for j = 1:numel(kg)
    R = X.ALL{X.col(kg{j})};
    a = X.payload_bps * R.dlv_post;
    [g, gl, gh] = boot_cluster(a(mt), ones(1, sum(mt)), R1.geom(mt), B, s0 + j);
    [gj, gjl, gjh] = boot_cluster(a(mj), ones(1, sum(mj)), R1.geom(mj), B, s0 + 100 + j);
    GP(end+1) = struct('policy', kg{j}, 'label', X.lab(kg{j}), 'bps', g, 'ci', [gl gh], 'bps_jam', gj, ...
        'ci_jam', [gjl gjh], 'norm', mean(R.gput_post(mt), 'omitnan'), 'norm_jam', mean(R.gput_post(mj), 'omitnan')); %#ok<AGROW>
    q = GP(end);
    lines{end+1} = sprintf(['  %-44s threat episodes (%d) %s [%s, %s], normalized %.3f | recoverable jamming (%d) %s ' ...
        '[%s, %s], normalized %.3f'], q.label, sum(mt), bps_txt(g), bps_txt(gl), bps_txt(gh), q.norm, sum(mj), ...
        bps_txt(gj), bps_txt(gjl), bps_txt(gjh), q.norm_jam); %#ok<AGROW>
end
end

function w = verdict_word(r, lo, target)
% The verdict of a reduction r [%] with 95% lower bound lo against the target [%].
if lo >= target, w = 'MET (committed)'; elseif r >= target, w = 'MET (not committed)'; else, w = 'NOT MET'; end
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
