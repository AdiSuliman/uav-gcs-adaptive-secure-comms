function varargout = lect_lines(cmd, varargin)
%LECT_LINES  The KPI summary's lines of the revised proposal's readings, for a reader that runs
%   without the whole KPI stage (c2e_lect.m):
%   [V, Va, lines] = lect_lines('three', m, fp)  three link states of a detector reading m
%                    (eval_detector.m metrics), above the KPI 1 threshold from its predictions fp
%   lines = lect_lines('per', Lk, S, tgt, tag)   PER vs the static link (lect_kpis.m), beside KPI 4
%   lines = lect_lines('rec', Lk, S, tag)        recovery time and goodput in bit/s, beside KPI 5
%   tf = lect_lines('has_core', Lk)              the core action set's readings are in Lk
%   s = lect_lines('core_tag', S)                name of the core action set
%   The local functions are measure_all_kpis.m's of branch lect-kpi word for word
%   (tools/c2e_lect_isolated.sh check compares them).
switch cmd
    case 'three',    [varargout{1}, varargout{2}, varargout{3}] = three_states(varargin{:});
    case 'per',      varargout{1} = per_lines(varargin{:});
    case 'rec',      varargout{1} = rec_lines(varargin{:});
    case 'has_core', varargout{1} = has_core(varargin{:});
    case 'core_tag', varargout{1} = core_tag(varargin{:});
    otherwise, error('lect_lines:cmd', 'lect_lines: unknown command %s', cmd);
end
end

function [V, Va, lines] = three_states(m, fp)
% The three link states (three_state_view.m) from the saved reading: every Eb/N0 from its
% confusion matrix, and above the KPI 1 threshold from the saved predictions of the same
% reading (as many frames); no new test reading.
V = []; Va = []; lines = {};
if ~isfield(m, 'conf_mat') || ~isfield(m, 'classes'), return; end
V = three_state_view(m.conf_mat, m.classes);
ts = 'the test set'; if isfield(m, 'test_set'), ts = m.test_set; end
lines{1} = sprintf(['beside KPI 1, three link states (revised proposal; %s, saved confusion matrix, every Eb/N0; frames ' ...
    'of none / tone_jamming / jamming, another class read is an error): %s'], ts, three_txt(V));
if ~isfile(fp) || ~isfield(m, 'kpi1_threshold_db') || ~isfinite(m.kpi1_threshold_db), return; end
Pd = load(fp, 'pred'); pr = Pd.pred;
if numel(pr.y_true) ~= sum(m.conf_mat(:)), return; end   % predictions of another reading
ab = pr.ebno(:) >= m.kpi1_threshold_db;
[~, it] = ismember(cellstr(pr.y_true(ab)), m.classes); [~, ip] = ismember(cellstr(pr.y_pred(ab)), m.classes);
ok = it > 0 & ip > 0; nc = numel(m.classes);
Va = three_state_view(accumarray([it(ok) ip(ok)], 1, [nc nc]), m.classes);
lines{2} = sprintf('beside KPI 1, three link states from %g dB (the KPI 1 threshold, saved predictions): %s', ...
    m.kpi1_threshold_db, three_txt(Va));
end

function s = three_txt(V)
s = sprintf(['recall narrowband %.2f%%, wideband %.2f%% (>= 85%% each: %s), clean %.2f%%; 3-state macro-F1 %.2f%% ' ...
    '(>= 85%%: %s); frames %d / %d / %d'], 100 * V.recall(2), 100 * V.recall(3), ternary(all(V.recall(2:3) >= 0.85), ...
    'met', 'not met'), 100 * V.recall(1), 100 * V.macro_f1, ternary(V.macro_f1 >= 0.85, 'met', 'not met'), V.n);
end

function lines = per_lines(Lk, S, tgt, tag)
% PER vs the static link (lect_kpis.m), beside KPI 4: S the readings of one action set (Lk,
% Lk.core or Lk.core.all36), tgt its rule with the detector, tag the set's name. The verdict
% per lecturer scenario first, the five jamming threats pooled as the extension.
lines = {};
q = S.per(strcmp({S.per.policy}, tgt));
if isempty(q), return; end
o = S.per(~strcmp({S.per.policy}, tgt));
if isfield(S, 'verdict') && ~isempty(S.verdict)
    lines{1} = sprintf(['beside KPI 4, PER vs the static link (revised proposal, %s), PRIMARY per jamming scenario ' ...
        '(lecturer: reduction >= %d%%; committed when the 95%% lower bound clears it), %s: %s'], tag, Lk.target_pct, ...
        S.verdict(1).label, strjoin(arrayfun(@(v) sprintf('%s (%s, %d recoverable episodes) %.1f%% [%.1f, %.1f] -> %s', ...
        v.scenario, v.threat, v.n, v.red_pct, v.ci, v.verdict), S.verdict, 'UniformOutput', false), '; '));
end
vd = ternary(q.met, 'MET', 'NOT MET');
if isfield(q, 'verdict'), vd = q.verdict; end
lines{end+1} = sprintf(['beside KPI 4, PER vs the static link (revised proposal, %s), extension: the five jamming threats ' ...
    'pooled, recoverable jamming episodes (%d), paired, 95%% bootstrap over flight geometries: %s %.2f%% vs %.2f%% ' ...
    'static, reduction %.1f%% [%.1f, %.1f] -> %s (target >= %d%%)%s'], tag, q.n, q.label, q.per_pct, q.per_ref_pct, ...
    q.red_pct, q.ci, vd, Lk.target_pct, strjoin(arrayfun(@(x) sprintf('; %s %.1f%% [%.1f, %.1f]', ...
    x.label, x.red_pct, x.ci), o, 'UniformOutput', false), ''));
if ~isempty(S.per_threat)
    lines{end+1} = sprintf('beside KPI 4, PER reduction per jamming threat, %s (%s): %s', tag, strjoin({S.per.label}, ' | '), ...
        strjoin(arrayfun(@(t) sprintf('%s%s %s', t.threat, ternary(isempty(t.band), '', [' (' t.band ')']), ...
        strjoin(compose('%.1f%%', t.red_pct), ' | ')), S.per_threat, 'UniformOutput', false), ', '));
end
if isfinite(S.cnn.per_red_pct)
    rt = '';
    if isfield(S.cnn, 'rec_det')
        rt = sprintf('; with vs without the detector, onset->detection %s vs %s, detection->restored %s vs %s', ...
            tq(S.cnn.det(1)), tq(S.cnn.det(2)), tq(S.cnn.rec_det(1)), tq(S.cnn.rec_det(2)));
    end
    lines{end+1} = sprintf(['beside KPI 4, CNN contribution, %s (%s vs the same escalation without the detector): ' ...
        'PER reduction %.1f%% [%.1f, %.1f], goodput %+.0f bit/s [%+.0f, %+.0f] (%d episodes)%s'], tag, q.label, ...
        S.cnn.per_red_pct, S.cnn.per_ci, S.cnn.gput_bps, S.cnn.gput_ci, S.cnn.n, rt);
end
end

function lines = rec_lines(Lk, S, tag)
% Recovery time from detection, onset-to-detection time and goodput in bit/s (lect_kpis.m), beside
% KPI 5: S the readings of one action set (Lk, Lk.core or Lk.core.all36), tag the set's name.
lines = {};
for sn = unique({S.rec.set}, 'stable')
    r = S.rec(strcmp({S.rec.set}, sn{1}));
    lines{end+1} = sprintf(['beside KPI 5, recovery time (revised proposal, %s: first confirmed alarm until the packet loss ' ...
        'stays <= 2x clean for %d cycles), %s (%d) [cycles of %g ms, median/p90]: %s'], tag, Lk.run, sn{1}, r(1).n, ...
        Lk.period_ms, strjoin(arrayfun(@(x) sprintf('%s: onset->detection %s, detection->restored %s, T_rec from onset %s', ...
        x.label, tq(x.det), tq(x.rec_det), tq(x.t_rec)), r, 'UniformOutput', false), ' | ')); %#ok<AGROW>
end
lines{end+1} = sprintf(['beside KPI 5, goodput after onset in bit/s (%s; nominal payload %.0f bit/s), threat episodes | ' ...
    'recoverable jamming episodes, normalized beside: %s'], tag, Lk.payload_bps, strjoin(arrayfun(@(g) sprintf(['%s %.0f ' ...
    '[%.0f, %.0f] (%.3f) | %.0f [%.0f, %.0f] (%.3f)'], g.label, g.bps, g.ci, g.norm, g.bps_jam, g.ci_jam, g.norm_jam), ...
    S.gput, 'UniformOutput', false), '; '));
end

function tf = has_core(Lk)
% The core action set's readings are in the policy evaluation (lect_kpis.m L.core).
tf = isfield(Lk, 'core') && ~isempty(Lk.core);
end

function s = core_tag(S)
% Name of the core action set with its configurations.
s = sprintf('core action set {%s}', strjoin(S.actions, ', '));
end

function s = tq(t)
% Median / p90 and the share never reached of a time statistic (lect_kpis.m).
if isnan(t.median), s = sprintf('- (never %.0f%%)', t.never_pct); else, s = sprintf('%g/%g (never %.0f%%)', t.median, t.p90, t.never_pct); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
