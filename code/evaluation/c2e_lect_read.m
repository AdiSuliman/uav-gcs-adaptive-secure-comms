function c2e_lect_read(G)
%C2E_LECT_READ  The revised proposal's readings from the gated results/policy_evaluation.mat of
%   the current folder (c2e_lect.m 'read', after its gate G passed): lect_kpis.m on the pooled
%   threat sets, the KPI summary's lines (lect_lines.m), the three link states and the clean
%   frames' false alarms of the KPI 1 reading (results/eval_detector_metrics_fresh2.mat when it
%   exists, as measure_all_kpis.m reads it, else results/eval_detector_metrics.mat; its saved
%   confusion matrix and predictions, no new test reading), and the false alarms of each system
%   configuration on KPI 6's clean flights (one-sided 95% bound <= 5%: MET (committed); the
%   point only: MET (not committed); else NOT MET). Output results/c2e_lect.{txt,mat}.
E = load('results/policy_evaluation.mat', 'ALL', 'POL', 'LBL', 'iDQN', 'KP', 'lect_in');
li = E.lect_in;
[LK, lk_lines] = lect_kpis(E.ALL, E.POL, E.LBL, E.iDQN, li.scen, li.payload_bps, li.period_ms);
rep = {'=== REVISED-PROPOSAL KPIs, PROFILE 1 (isolated reading of its C2e; docs/c2e_lect_protocol.md) ===', ...
    sprintf('Generated: %s | det_id %s | policy stamp %s', datestr(now), G.det_id, G.policy_stamp), G.lines{1}, ''};
if isfile('C2E_LECT_ISOLATED')
    rep = [rep, {'Inputs (copied read-only from profile 1 after its C2e; SHA-256):'}, ...
        strcat({'  '}, read_lines('C2E_LECT_ISOLATED')'), {''}];
end

% PER, recovery time, goodput, the CNN's share (KPI summary lines, then the C2e section)
rep{end+1} = '--- PER vs the static link (beside KPI 4) ---';
rep = [rep, lect_lines('per', LK, LK, 'rule_esc', 'full action set')];
if lect_lines('has_core', LK)
    tag = lect_lines('core_tag', LK.core);
    rep = [rep, lect_lines('per', LK, LK.core, 'rule_core', [tag ', recoverable by a core configuration'])];
    rep = [rep, lect_lines('per', LK, LK.core.all36, 'rule_core', [tag ', second line: recoverable by any of the 36 configurations'])];
end
rep{end+1} = '';
rep{end+1} = '--- Recovery time from detection and goodput in bit/s (beside KPI 5) ---';
rep = [rep, lect_lines('rec', LK, LK, 'full action set')];
if lect_lines('has_core', LK)
    rep = [rep, lect_lines('rec', LK, LK.core, [tag ', recoverable by a core configuration'])];
    rep = [rep, lect_lines('rec', LK, LK.core.all36, [tag ', second line: recoverable by any of the 36 configurations'])];
end
rep = [rep, lk_lines];

% The three link states of profile 1's KPI 1 reading (its saved confusion matrix and
% predictions; no new test reading) and the detector's false alarms on clean frames
F = 'results/eval_detector_metrics.mat'; Fp = 'results/detector_predictions.mat';
if isfile('results/eval_detector_metrics_fresh2.mat')       % profile 1's KPI 1 set (measure_all_kpis.m)
    F = 'results/eval_detector_metrics_fresh2.mat'; Fp = 'results/detector_predictions_fresh2.mat';
end
rep{end+1} = '';
rep{end+1} = '--- Detection: three link states and false alarms on clean frames (beside KPI 1) ---';
V = []; Va = []; FA = [];
if isfile(F)
    M = load(F, 'metrics'); m = M.metrics;
    [V, Va, l3] = lect_lines('three', m, Fp); rep = [rep, l3];
    [FA, lf] = clean_fa(m, Fp); rep = [rep, lf];
else
    rep{end+1} = sprintf('three link states: %s absent', F);
end

% False alarms of the three system configurations on the clean link (KPI 6's reading)
rep{end+1} = '';
rep{end+1} = sprintf('--- False alarms on the clean link per configuration (KPI 6''s flights: %s) ---', E.KP.far_src);
keys = unique({'none', 'blind_esc', 'rule_esc', 'blind_core', 'rule_core', E.POL{E.iDQN}}, 'stable');
FR = struct('policy', {}, 'label', {}, 'k', {}, 'n', {}, 'p_pct', {}, 'upper_pct', {}, 'verdict', {});
for k = keys
    j = find(strcmp(E.POL, k{1}), 1);
    if isempty(j), continue; end
    r = E.KP.far(strcmp({E.KP.far.policy}, E.LBL{j}));
    if isempty(r), continue; end
    FR(end+1) = struct('policy', k{1}, 'label', E.LBL{j}, 'k', r.k, 'n', r.n, 'p_pct', 100 * r.p, ...
        'upper_pct', 100 * r.upper, 'verdict', verdict_word(100 * r.p, 100 * r.upper, 5)); %#ok<AGROW>
    rep{end+1} = sprintf(['  %-44s %4d / %4d episodes with a change = %5.2f%%, one-sided 95%% bound %5.2f%% -> %s ' ...
        '(lecturer: <= 5%%; committed when the bound meets it)'], E.LBL{j}, r.k, r.n, 100 * r.p, 100 * r.upper, ...
        FR(end).verdict); %#ok<AGROW>
end

fid = fopen('results/c2e_lect.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
LECT = struct('pol', LK, 'three', V, 'three_above', Va, 'clean_fa', FA, 'far', FR, 'gate', G, 'kpi1_file', F);
save('results/c2e_lect.mat', 'LECT');
fprintf('Saved results/c2e_lect.{txt,mat}\n');
end

function [FA, lines] = clean_fa(m, fp)
% Clean frames (class none) of the KPI 1 reading read as a jamming state (tone_jamming,
% jamming) and as any class that raises an alarm (every class but none and
% benign_interference, policy_monitor.m): every Eb/N0 from the confusion matrix, above the KPI 1
% threshold from the saved predictions of the same reading.
FA = []; lines = {};
if ~isfield(m, 'conf_mat') || ~isfield(m, 'classes'), return; end
cl = cellstr(string(m.classes(:)'));
FA = fa_of(m.conf_mat, cl);
lines{1} = sprintf('beside KPI 1, clean frames read as a jamming state %.2f%%, as a class that raises an alarm %.2f%% (%d frames, every Eb/N0; <= 5%%: %s)', ...
    100 * FA.jam, 100 * FA.alarm, FA.n, ternary(FA.alarm <= 0.05, 'met', 'not met'));
if ~isfile(fp) || ~isfield(m, 'kpi1_threshold_db') || ~isfinite(m.kpi1_threshold_db), return; end
Pd = load(fp, 'pred'); pr = Pd.pred;
if numel(pr.y_true) ~= sum(m.conf_mat(:)), return; end
ab = pr.ebno(:) >= m.kpi1_threshold_db;
[~, it] = ismember(cellstr(pr.y_true(ab)), cl); [~, ip] = ismember(cellstr(pr.y_pred(ab)), cl);
ok = it > 0 & ip > 0; nc = numel(cl);
FA.above = fa_of(accumarray([it(ok) ip(ok)], 1, [nc nc]), cl);
lines{2} = sprintf('beside KPI 1, from %g dB (the KPI 1 threshold): clean frames read as a jamming state %.2f%%, as a class that raises an alarm %.2f%% (%d frames; <= 5%%: %s)', ...
    m.kpi1_threshold_db, 100 * FA.above.jam, 100 * FA.above.alarm, FA.above.n, ternary(FA.above.alarm <= 0.05, 'met', 'not met'));
end

function F = fa_of(cm, cl)
r = cm(strcmp(cl, 'none'), :); n = sum(r);
F = struct('n', n, 'jam', sum(r(ismember(cl, {'tone_jamming', 'jamming'}))) / n, ...
    'alarm', sum(r(~ismember(cl, {'none', 'benign_interference'}))) / n);
end

function w = verdict_word(p, up, target)
% At most target [%]: committed when the one-sided 95% bound meets it, else on the point.
if up <= target, w = 'MET (committed)'; elseif p <= target, w = 'MET (not committed)'; else, w = 'NOT MET'; end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end

function L = read_lines(f)
L = splitlines(string(fileread(f)));
if ~isempty(L) && L(end) == "", L = L(1:end-1); end
L = cellstr(L);
end
