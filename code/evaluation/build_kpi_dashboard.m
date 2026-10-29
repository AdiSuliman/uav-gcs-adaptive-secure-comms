%% BUILD_KPI_DASHBOARD - Results dashboard (proposal deliverable 1)
% One figure for the report and the defense, drawn from the result files of
% the pipeline (no numbers typed in). A missing input shows a placeholder.
%
% Panels:
%   1. Confusion matrix (detection)
%   2. Macro-F1 vs Eb/N0 (detection, KPI 1)
%   3. Unknown-threat AUROC per held-out threat (KPI 2)
%   4. Recovered episodes per threat, DQN / rule + escalation / oracle (KPI 4)
%   5. Recovered episodes vs Eb/N0, single threats, key policies (KPI 5)
%   6. Recovered episodes vs interferer direction (geometry)
%   7. Survivability map summary per threat and geometry (deliverable 7)
%   8. KPI status (results/kpi_summary.mat)
% Every policy keeps one color in panels 5 and 6 (kpi_print_text.m 'palette'); the targets of
% panels 2, 3 and 4 are in the legends, not on the bars; KPI 5's Eb/N0 points are tagged L
% where the clean link is limited (2 x its packet loss >= 1, from results/edge_map.mat); the
% status text is wrapped to the panel.
%
% Inputs: the KPI 1 reading (kpi1_file.m on the set of kpi1_set.m: results/eval_detector_metrics_fresh2.mat,
%         the third test set, when it exists, else results/eval_detector_metrics.mat; _fresh3, the
%         fourth, once kpi1_set.m names it), results/ood_detection.mat,
%         results/policy_evaluation.mat, data/survivability_boundary.mat,
%         results/kpi_summary.mat, results/edge_map.mat (optional: the L tags of panel 5)
% Output: results/kpi_dashboard.png

close all; clc;
fprintf('=== KPI dashboard ===\n\n');
ld = @(f, varargin) load_if(f, varargin{:});
Md = ld(kpi1_file('eval_detector_metrics'), 'metrics');
O  = ld('results/ood_detection.mat', 'R', 'SC', 'sel', 'NEST');
P  = ld('results/policy_evaluation.mat');
Sv = ld('data/survivability_boundary.mat', 'grid_data_A', 'grid_data_B');
Kp = ld('results/kpi_summary.mat', 'KPI');
Em = ld('results/edge_map.mat', 'EM');

fig = figure('Position', [30 30 1800 950], 'Color', 'w', 'Name', 'UAV-GCS KPI dashboard');
tl = tiledlayout(fig, 2, 4, 'TileSpacing', 'compact', 'Padding', 'compact');

% 1. Confusion matrix
ax = nexttile(tl);
if ~isempty(Md)
    m = Md.metrics; C = m.conf_mat ./ max(sum(m.conf_mat, 2), 1);
    imagesc(ax, 100 * C, [0 100]); colormap(ax, flipud(gray)); colorbar(ax);
    cl = strrep(cellstr(string(m.classes)), '_', ' ');
    set(ax, 'XTick', 1:numel(cl), 'XTickLabel', cl, 'YTick', 1:numel(cl), 'YTickLabel', cl, 'FontSize', 7);
    xtickangle(ax, 45); title(ax, {sprintf('Detection, accuracy %.1f%%', m.overall_accuracy_pct), set_txt(m)});
    xlabel(ax, 'predicted'); ylabel(ax, 'true');
else
    placeholder(ax, 'Confusion matrix', 'eval_detector');
end

% 2. Macro-F1 vs Eb/N0
ax = nexttile(tl);
if ~isempty(Md)
    b = Md.metrics.snr_breakdown;
    hf = plot(ax, [b.snr_db], [b.macro_f1_pct], '-o', 'LineWidth', 1.6); hold(ax, 'on');
    hy = yline(ax, 90, 'r--'); hy.LineWidth = 1; grid(ax, 'on'); ylim(ax, [50 100]);
    legend(ax, [hf, hy], {'macro-F1', '90% target'}, 'Location', 'southeast', 'FontSize', 7);
    xlabel(ax, 'E_b/N_0 [dB]'); ylabel(ax, 'macro-F1 [%]'); title(ax, {'KPI 1: detection vs E_b/N_0', set_txt(Md.metrics)});
else
    placeholder(ax, 'Macro-F1 vs Eb/N0', 'eval_detector');
end

% 3. Unknown threats
ax = nexttile(tl);
if ~isempty(O)
    j = strcmp(O.SC, O.sel); A = vertcat(O.R.auroc);
    hb = bar(ax, [A(:, j), O.NEST.auroc(:)]); hold(ax, 'on'); grid(ax, 'on'); ylim(ax, [0.4 1]);
    names = {strrep(O.sel, '_', ' '), 'nested'}; ht = gobjects(0);
    if ~isempty(Kp) && any([Kp.KPI.id] == 2)
        k2 = Kp.KPI([Kp.KPI.id] == 2);
        ht = yline(ax, sscanf(k2.target, '>= %f'), 'r--'); ht.LineWidth = 1;
        names{end+1} = ['target ' k2.target];
    end
    set(ax, 'XTickLabel', strrep({O.R.held_out}, '_', ' '), 'FontSize', 7); xtickangle(ax, 40);
    legend(ax, [hb, ht], names, 'Location', 'southoutside', 'NumColumns', 3, 'FontSize', 7);
    ylabel(ax, 'AUROC'); title(ax, sprintf('KPI 2: unknown threats (LOTO), nested mean %.3f', mean(O.NEST.auroc)));
else
    placeholder(ax, 'Unknown-threat AUROC', 'eval_ood_detection');
end

% 4-6. Decision layer
if ~isempty(P)
    col = @(p) find(strcmp(P.POL, p));
    ax = nexttile(tl);
    sh = P.KP.show; cD = strcmp(sh, P.POL{P.iDQN}); cR = strcmp(sh, 'rule_esc'); cO = strcmp(sh, 'oracle');
    hb = barh(ax, P.KP.per_threat(:, [find(cD) find(cR) find(cO)])); hold(ax, 'on');
    hx = xline(ax, 90, 'r--'); hx.LineWidth = 1;
    set(ax, 'YTick', 1:numel(P.KP.threats), 'YTickLabel', strrep(P.KP.threats, '_', ' '), 'FontSize', 7, 'YDir', 'reverse');
    xlim(ax, [0 105]); grid(ax, 'on'); xlabel(ax, 'recovered among recoverable [%]');
    legend(ax, [hb, hx], {erase(P.LBL{P.iDQN}, ' (deployed)'), 'rule + esc.', 'oracle', '90% target'}, 'Location', 'southoutside', ...
        'NumColumns', 2, 'FontSize', 7);
    title(ax, 'KPI 4: recovery per threat (test pools)');

    ax = nexttile(tl);
    cols = kpi_print_text('palette', size(P.KP.per_ebno, 2));
    hp = plot(ax, P.KP.ebno, P.KP.per_ebno, '-o', 'LineWidth', 1.3); grid(ax, 'on'); ylim(ax, [0 105]);
    for q = 1:numel(hp), hp(q).Color = cols(q, :); end
    legend(ax, P.KP.show_lbl, 'Location', 'southoutside', 'NumColumns', 4, 'FontSize', 7);
    Ll = kpi_print_text('edge_limited', Em, P.KP.ebno, decision_config().ratio_ok);
    set(ax, 'XTick', P.KP.ebno, 'XTickLabel', kpi_print_text('ebno_ticks', P.KP.ebno, Ll));
    xl = {'E_b/N_0 [dB]'}; if any(Ll), xl{2} = 'L: link-limited (2 x the clean packet loss >= 1)'; end
    xlabel(ax, xl, 'FontSize', 8); ylabel(ax, 'recovered among recoverable [%]'); title(ax, 'KPI 5: single threats vs E_b/N_0');

    ax = nexttile(tl);
    if ~isempty(P.KP.per_aoa)
        hA = bar(ax, P.KP.per_aoa); grid(ax, 'on'); ylim(ax, [0 105]);
        for q = 1:min(numel(hA), size(cols, 1)), hA(q).FaceColor = cols(q, :); end
        legend(ax, hA, P.KP.show_lbl, 'Location', 'southoutside', 'NumColumns', 4, 'FontSize', 6);
        b = P.KP.aoa_bins;
        set(ax, 'XTickLabel', arrayfun(@(i) sprintf('%d-%d', b(i), b(i+1)), 1:numel(b) - 1, 'UniformOutput', false));
        xlabel(ax, '|interferer - GCS direction| [deg]'); ylabel(ax, 'recovered [%]');
        title(ax, 'Directional threats vs geometry');
    else
        placeholder(ax, 'Geometry', 'evaluate_policies (random AoA)');
    end
else
    for k = 1:3, placeholder(nexttile(tl), 'Decision layer', 'evaluate_policies'); end
end

% 7. Survivability
ax = nexttile(tl);
if ~isempty(Sv)
    g = Sv.grid_data_B; n = numel(g); Z = zeros(n, 3);
    for k = 1:n, st = g(k).status(g(k).status > 0); Z(k, :) = 100 * [mean(st == 1), mean(st == 2), mean(st == 3)]; end
    bh = barh(ax, Z, 'stacked'); bh(1).FaceColor = [0.20 0.65 0.25]; bh(2).FaceColor = [0.95 0.75 0.15];
    bh(3).FaceColor = [0.80 0.20 0.20];
    set(ax, 'YTick', 1:n, 'YTickLabel', strrep({g.threat}, '_', ' '), 'FontSize', 7, 'YDir', 'reverse');
    xlim(ax, [0 100]); xlabel(ax, '% of (severity, E_b/N_0) states');
    legend(ax, {'recoverable', 'marginal', 'non-recoverable'}, 'Location', 'southoutside', 'NumColumns', 3, 'FontSize', 7);
    title(ax, 'Survivability boundary (any configuration)');
else
    placeholder(ax, 'Survivability map', 'map_survivability_boundary');
end

% 8. KPI status
ax = nexttile(tl); axis(ax, 'off');
if ~isempty(Kp)
    hd = cell(1, numel(Kp.KPI)); vl = hd;
    for k = 1:numel(Kp.KPI)
        q = Kp.KPI(k);
        hd{k} = kpi_print_text('wrap', sprintf('%d  %s  [%s]', q.id, q.name, q.status), 44);
        vl{k} = kpi_print_text('wrap', q.value, 52);
    end
    uh = 0.035; uv = 0.031; gap = 0.012; top = 0.055;            % one line of a head, of a value, a gap, the title: axes units
    tot = top + sum(cellfun(@numel, hd)) * uh + sum(cellfun(@numel, vl)) * uv + numel(hd) * gap;
    sc = min(1, 0.95 / tot);                                     % everything shrinks together when it would not fit
    text(ax, 0, 1, 'KPI status (proposal wording)', 'FontWeight', 'bold', 'FontSize', 10 * max(sc, 0.8), 'VerticalAlignment', 'top');
    y = 1 - top * sc;
    for k = 1:numel(Kp.KPI)
        q = Kp.KPI(k);
        switch q.status
            case 'MET', c = [0.10 0.55 0.20];
            case {'NOT MET', 'MISSING'}, c = [0.75 0.15 0.15];
            otherwise, c = [0.80 0.50 0.05];
        end
        text(ax, 0, y, hd{k}, 'Color', c, 'FontSize', 8.5 * sc, 'FontWeight', 'bold', 'VerticalAlignment', 'top', 'Interpreter', 'none');
        y = y - numel(hd{k}) * uh * sc;
        text(ax, 0.04, y, vl{k}, 'FontSize', 7.5 * sc, 'VerticalAlignment', 'top', 'Interpreter', 'none');
        y = y - (numel(vl{k}) * uv + gap) * sc;
    end
else
    text(ax, 0, 0.5, 'results/kpi_summary.mat missing (measure_all_kpis)');
end
title(tl, 'UAV-GCS adaptive secure communications: results dashboard', 'FontWeight', 'bold');
exportgraphics(fig, 'results/kpi_dashboard.png', 'Resolution', 130);
close(fig);
fprintf('Saved results/kpi_dashboard.png\n');

%% ===================== Local functions =====================
function S = load_if(f, varargin)
if isfile(f), S = load(f, varargin{:}); else, S = []; fprintf('  missing %s\n', f); end
end

function t = set_txt(m)
% The test set a detector reading was read on (eval_detector.m metrics.test_set), and its
% in-sample label when the deployed fusion was fitted on it (metrics.sample).
t = 'test set'; if isfield(m, 'test_set') && ~isempty(m.test_set), t = char(m.test_set); end
if isfield(m, 'sample') && ~isempty(m.sample), t = [t ', ' char(m.sample)]; end
end

function placeholder(ax, ttl, src)
axis(ax, 'off');
text(ax, 0.5, 0.5, sprintf('%s\n(run %s)', ttl, src), 'HorizontalAlignment', 'center', 'Interpreter', 'none');
end
