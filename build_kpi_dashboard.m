%% BUILD_KPI_DASHBOARD - Results dashboard (proposal deliverable 1) (D46)
% One figure for the report and the defense, drawn from the result files of
% the pipeline (no numbers typed in). A missing input shows a placeholder.
%
% Panels:
%   1. Confusion matrix (detection)
%   2. Macro-F1 vs Eb/N0 (detection, KPI 1)
%   3. Unknown-threat AUROC per held-out threat (KPI 2)
%   4. Mean reward per cycle per episode set, key policies (KPI 5)
%   5. Restored cycles vs Eb/N0, single threats (KPI 4)
%   6. Restored cycles vs interferer direction (geometry)
%   7. Survivability map summary per threat and geometry (deliverable 8)
%   8. KPI status (results/kpi_summary.mat)
%
% Inputs: results/eval_detector_metrics.mat, results/ood_detection.mat,
%         results/policy_evaluation.mat, data/survivability_boundary.mat,
%         results/kpi_summary.mat
% Output: results/kpi_dashboard.png

close all; clc;
fprintf('=== KPI dashboard (D46) ===\n\n');
ld = @(f, varargin) load_if(f, varargin{:});
Md = ld('results/eval_detector_metrics.mat', 'metrics');
O  = ld('results/ood_detection.mat', 'R', 'SC');
P  = ld('results/policy_evaluation.mat');
Sv = ld('data/survivability_boundary.mat', 'grid_data_A', 'grid_data_B');
Kp = ld('results/kpi_summary.mat', 'KPI');

fig = figure('Position', [30 30 1800 950], 'Color', 'w', 'Name', 'UAV-GCS KPI dashboard');
tl = tiledlayout(fig, 2, 4, 'TileSpacing', 'compact', 'Padding', 'compact');

% 1. Confusion matrix
ax = nexttile(tl);
if ~isempty(Md)
    m = Md.metrics; C = m.conf_mat ./ max(sum(m.conf_mat, 2), 1);
    imagesc(ax, 100 * C, [0 100]); colormap(ax, flipud(gray)); colorbar(ax);
    cl = strrep(cellstr(string(m.classes)), '_', ' ');
    set(ax, 'XTick', 1:numel(cl), 'XTickLabel', cl, 'YTick', 1:numel(cl), 'YTickLabel', cl, 'FontSize', 7);
    xtickangle(ax, 45); title(ax, sprintf('Detection, accuracy %.1f%%', m.overall_accuracy_pct));
    xlabel(ax, 'predicted'); ylabel(ax, 'true');
else
    placeholder(ax, 'Confusion matrix', 'eval_detector');
end

% 2. Macro-F1 vs Eb/N0
ax = nexttile(tl);
if ~isempty(Md)
    b = Md.metrics.snr_breakdown;
    plot(ax, [b.snr_db], [b.macro_f1_pct], '-o', 'LineWidth', 1.6); hold(ax, 'on');
    yline(ax, 90, 'r--', '90%'); grid(ax, 'on'); ylim(ax, [50 100]);
    xlabel(ax, 'E_b/N_0 [dB]'); ylabel(ax, 'macro-F1 [%]'); title(ax, 'KPI 1: detection vs E_b/N_0');
else
    placeholder(ax, 'Macro-F1 vs Eb/N0', 'eval_detector');
end

% 3. Unknown threats
ax = nexttile(tl);
if ~isempty(O)
    j = strcmp(O.SC, 'maha'); A = vertcat(O.R.auroc);
    bar(ax, A(:, j)); hold(ax, 'on'); yline(ax, 0.8, 'r--', '0.8'); grid(ax, 'on'); ylim(ax, [0.4 1]);
    set(ax, 'XTickLabel', strrep({O.R.held_out}, '_', ' '), 'FontSize', 7); xtickangle(ax, 40);
    ylabel(ax, 'AUROC'); title(ax, sprintf('KPI 2: unknown threats (LOTO), mean %.3f', mean(A(:, j))));
else
    placeholder(ax, 'Unknown-threat AUROC', 'eval_ood_detection');
end

% 4-6. Decision layer
if ~isempty(P)
    col = @(p) find(strcmp(P.POL, p));
    key = {'random', 'fixed', 'rule_esc', 'table', P.POL{P.iDQN}, 'oracle'};
    kl = {'random', 'best fixed', 'rule + esc.', 'table', 'DQN', 'oracle'};
    ax = nexttile(tl);
    Y = zeros(numel(P.set_names), numel(key));
    for si = 1:numel(P.set_names), Y(si, :) = cellfun(@(p) mean(P.RES{si, col(p)}.ret), key); end
    bar(ax, Y); grid(ax, 'on'); set(ax, 'XTickLabel', P.set_names);
    legend(ax, kl, 'Location', 'southoutside', 'NumColumns', 3, 'FontSize', 7);
    ylabel(ax, 'mean reward per cycle'); title(ax, 'KPI 5: policies on the test pools');

    ax = nexttile(tl);
    plot(ax, P.KP.ebno, P.KP.per_ebno, '-o', 'LineWidth', 1.3); grid(ax, 'on'); ylim(ax, [0 105]);
    legend(ax, P.KP.show_lbl, 'Location', 'southeast', 'FontSize', 7);
    xlabel(ax, 'E_b/N_0 [dB]'); ylabel(ax, 'restored cycles after onset [%]'); title(ax, 'KPI 4: single threats');

    ax = nexttile(tl);
    if ~isempty(P.KP.per_aoa)
        bar(ax, P.KP.per_aoa); grid(ax, 'on'); ylim(ax, [0 105]);
        b = P.KP.aoa_bins;
        set(ax, 'XTickLabel', arrayfun(@(i) sprintf('%d-%d', b(i), b(i+1)), 1:numel(b) - 1, 'UniformOutput', false));
        xlabel(ax, '|interferer - GCS direction| [deg]'); ylabel(ax, 'restored [%]');
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
    title(ax, 'Survivability boundary (any action)');
else
    placeholder(ax, 'Survivability map', 'map_survivability_boundary');
end

% 8. KPI status
ax = nexttile(tl); axis(ax, 'off');
if ~isempty(Kp)
    y = 0.97;
    text(ax, 0, y, 'KPI status (proposal section 5)', 'FontWeight', 'bold', 'FontSize', 10);
    for k = 1:numel(Kp.KPI)
        q = Kp.KPI(k); y = y - 0.115;
        switch q.status
            case 'MET', c = [0.10 0.55 0.20];
            case {'NOT MET', 'MISSING'}, c = [0.75 0.15 0.15];
            otherwise, c = [0.80 0.50 0.05];
        end
        text(ax, 0, y, sprintf('%d  %s  [%s]', q.id, q.name, q.status), 'Color', c, 'FontSize', 8.5, 'FontWeight', 'bold');
        text(ax, 0.04, y - 0.045, q.value, 'FontSize', 7.5, 'Interpreter', 'none');
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

function placeholder(ax, ttl, src)
axis(ax, 'off');
text(ax, 0.5, 0.5, sprintf('%s\n(run %s)', ttl, src), 'HorizontalAlignment', 'center', 'Interpreter', 'none');
end
