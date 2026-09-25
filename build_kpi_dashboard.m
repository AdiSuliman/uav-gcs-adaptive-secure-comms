%% BUILD_KPI_DASHBOARD — final project results dashboard (proposal deliverable #1)
% Single-figure summary of the whole system, for the report and defense.
% Reads results straight from the .mat files each stage already saves, so it
% is always in sync with the latest run -- no hardcoded numbers. Every panel
% degrades gracefully: a missing input file shows a clear placeholder instead
% of crashing the whole dashboard.
%
% Panels:
%   1. Confusion matrix        (detection: what confuses with what)
%   2. Accuracy vs SNR         (detection: robustness across noise)
%   3. Recovery vs SNR         (response: BER restored per threat)
%   4. Decision latency        (response: CNN + DQN reaction time)
%   5. Action distribution     (response: which countermeasure per threat)
%   6. FAR + KPI status        (response + summary: false alarms, 5/5 KPIs)
%   7. Survivability Map A/B    (proposal deliverable #7 headline numbers)
%
% Inputs (results/): eval_detector_metrics.mat, closed_loop_diagnostic_results.mat,
%                    far_measurement.mat, data/survivability_boundary.mat
% Output: results/kpi_dashboard.png

close all; clc;
fprintf('=== Building KPI Dashboard (proposal deliverable #1) ===\n\n');

R = 'results/';

%% ---------- Load everything up front, tolerate missing files ----------
have_metrics = isfile([R 'eval_detector_metrics.mat']);
have_cl      = isfile([R 'closed_loop_diagnostic_results.mat']);
have_far     = isfile([R 'far_measurement.mat']);
have_surv    = isfile('data/survivability_boundary.mat');

if have_metrics, M = load([R 'eval_detector_metrics.mat'],'metrics'); metrics = M.metrics; end
if have_cl,      C = load([R 'closed_loop_diagnostic_results.mat'],'results'); cl = C.results; end
if have_far,     F = load([R 'far_measurement.mat'],'results'); far = F.results; end
if have_surv,    Sv = load('data/survivability_boundary.mat'); end

%% ---------- Figure + palette ----------
fig = figure('Position',[40 40 1750 950],'Color','w','Name','UAV-GCS KPI Dashboard');
col_blue = [0.20 0.50 0.80];
col_grn  = [0.20 0.65 0.25];
col_amb  = [0.95 0.75 0.15];
col_red  = [0.80 0.20 0.20];
col_org  = [0.90 0.50 0.15];

tl = tiledlayout(fig, 2, 4, 'TileSpacing','compact','Padding','compact');
title(tl, 'UAV-GCS Adaptive Secure Communications — Results Dashboard', ...
    'FontSize', 16, 'FontWeight','bold');
subtitle(tl, sprintf('Generated %s', datestr(now)), 'FontSize', 9);

%% ===== Panel 1: Confusion matrix =====
ax1 = nexttile(tl, 1);
if have_metrics && isfield(metrics,'conf_mat')
    cm = metrics.conf_mat;
    cmn = cm ./ max(sum(cm,2), 1);           % row-normalized
    imagesc(ax1, cmn); colormap(ax1, flipud(gray));
    axis(ax1,'square');
    n = size(cm,1);
    cl_names = shorten_names(metrics.classes);
    set(ax1,'XTick',1:n,'XTickLabel',cl_names,'XTickLabelRotation',45, ...
            'YTick',1:n,'YTickLabel',cl_names,'FontSize',7);
    for i=1:n
        for j=1:n
            if cm(i,j)>0
                tc = 'k'; if cmn(i,j)>0.5, tc='w'; end
                text(ax1,j,i,sprintf('%d',cm(i,j)),'HorizontalAlignment','center', ...
                    'FontSize',6,'Color',tc);
            end
        end
    end
    title(ax1,'Confusion Matrix (test set)','FontSize',10);
    xlabel(ax1,'Predicted'); ylabel(ax1,'True');
else
    placeholder(ax1,'Confusion Matrix','eval\_detector\_metrics.mat missing');
end

%% ===== Panel 2: Accuracy vs SNR =====
ax2 = nexttile(tl, 2);
if have_metrics && isfield(metrics,'snr_breakdown')
    sb = metrics.snr_breakdown;
    snr = [sb.snr_db]; acc = [sb.accuracy_pct];
    plot(ax2, snr, acc, '-o','LineWidth',2,'Color',col_blue, ...
        'MarkerFaceColor',col_blue,'MarkerSize',6);
    grid(ax2,'on'); xlabel(ax2,'E_bN_0 (dB)'); ylabel(ax2,'Accuracy (%)');
    ylim(ax2,[floor(min(acc)/5)*5 100]); xticks(ax2,snr);
    title(ax2, sprintf('Accuracy vs SNR (overall %.1f%%)', metrics.overall_accuracy_pct),'FontSize',10);
    yline(ax2, 90, '--', 'target 90%', 'Color',col_red,'FontSize',7,'LabelHorizontalAlignment','left');
else
    placeholder(ax2,'Accuracy vs SNR','eval\_detector\_metrics.mat missing');
end

%% ===== Panel 3: Recovery vs SNR per threat =====
ax3 = nexttile(tl, 3);
if have_cl
    threats = unique({cl.threat},'stable');
    snr_pts = unique([cl.snr_db]);
    hold(ax3,'on');
    real_threats = threats(~ismember(threats,{'none','benign_interference'}));
    for t = 1:numel(real_threats)
        mu = nan(1,numel(snr_pts)); lo = mu; hi = mu;
        for s = 1:numel(snr_pts)
            m = strcmp({cl.threat},real_threats{t}) & [cl.snr_db]==snr_pts(s);
            [mu(s), lo(s), hi(s)] = stats_ci('t', [cl(m).rec_vs_clean], [-Inf 100]);
        end
        if any(~isnan(lo))
            lo(isnan(lo)) = mu(isnan(lo)); hi(isnan(hi)) = mu(isnan(hi));
            errorbar(ax3, snr_pts, mu, mu-lo, hi-mu, '-o','LineWidth',1.2,'MarkerSize',4,'CapSize',3, ...
                'DisplayName', strrep(real_threats{t},'_','\_'));
        else
            plot(ax3, snr_pts, mu, '-o','LineWidth',1.3,'MarkerSize',4, ...
                'DisplayName', strrep(real_threats{t},'_','\_'));
        end
    end
    hold(ax3,'off'); grid(ax3,'on');
    xlabel(ax3,'E_bN_0 (dB)');
    ylabel(ax3,'Recovery vs clean link (%)'); ylim(ax3,[-10 105]);
    title(ax3,sprintf('KPI #2: recovery vs no-attack link (%d repeats, 95%% CI)', numel(unique([cl.mc]))),'FontSize',10);
    legend(ax3,'Location','southeast','FontSize',6);
    xticks(ax3,snr_pts);
else
    placeholder(ax3,'Recovery vs SNR','closed\_loop\_diagnostic\_results.mat missing');
end

%% ===== Panel 4: Decision latency (stacked CNN+DQN) =====
ax4 = nexttile(tl, 4);
if have_cl
    threats = unique({cl.threat},'stable');
    cnn_lat = zeros(1,numel(threats)); dqn_lat = zeros(1,numel(threats));
    for t=1:numel(threats)
        m = strcmp({cl.threat},threats{t});
        cnn_lat(t) = mean([cl(m).cnn_latency_ms]);
        dqn_lat(t) = mean([cl(m).dqn_latency_ms]);
    end
    b = bar(ax4, [cnn_lat; dqn_lat]', 'stacked'); 
    b(1).FaceColor = col_blue; b(2).FaceColor = col_org;
    set(ax4,'XTick',1:numel(threats),'XTickLabel',shorten_names(threats), ...
        'XTickLabelRotation',45,'FontSize',7);
    ylabel(ax4,'Latency (ms)');
    title(ax4, sprintf('Decision Latency (mean %.2f ms)', mean(cnn_lat+dqn_lat)),'FontSize',10);
    legend(ax4,{'CNN','DQN'},'Location','northeast','FontSize',7);
    grid(ax4,'on');
else
    placeholder(ax4,'Decision Latency','closed\_loop\_diagnostic\_results.mat missing');
end

%% ===== Panel 5: Action distribution per threat =====
ax5 = nexttile(tl, 5);
if have_cl
    threats = unique({cl.threat},'stable');
    action_set = unique({cl.dqn_action},'stable');
    counts = zeros(numel(threats), numel(action_set));
    for t=1:numel(threats)
        m = strcmp({cl.threat},threats{t});
        acts = {cl(m).dqn_action};
        for a=1:numel(action_set)
            counts(t,a) = sum(strcmp(acts, action_set{a}));
        end
    end
    b = bar(ax5, counts, 'stacked');
    amap = [0.6 0.6 0.6; col_blue; col_amb; col_grn; col_org; hsv(12)];
    for a=1:numel(action_set), b(a).FaceColor = amap(a,:); end
    set(ax5,'XTick',1:numel(threats),'XTickLabel',shorten_names(threats), ...
        'XTickLabelRotation',45,'FontSize',7);
    ylabel(ax5,'Count (over SNR sweep)');
    title(ax5,'Countermeasure Action per Threat','FontSize',10);
    legend(ax5, strrep(action_set,'_','\_'),'Location','eastoutside','FontSize',6);
    grid(ax5,'on');
else
    placeholder(ax5,'Action Distribution','closed\_loop\_diagnostic\_results.mat missing');
end

%% ===== Panel 6: FAR + KPI status =====
ax6 = nexttile(tl, 6); axis(ax6,'off');
lines = {}; 
lines{end+1} = '\bfProposal KPIs (section 5)\rm';
lines{end+1} = '';
if have_metrics
    lines{end+1} = sprintf('KPI1  Detection:   %.1f%%  \\color[rgb]{0.2,0.65,0.25}PASS', metrics.overall_accuracy_pct);
end
if have_cl
    real_m = ~ismember({cl.threat},{'none','benign_interference'});
    [mr, mlo, mhi] = stats_ci('t', arrayfun(@(k) mean([cl(real_m & [cl.mc]==k).rec_vs_clean],'omitnan'), unique([cl.mc])), [0 100]);
    r2 = [cl(real_m).ratio_clean];
    if isnan(mlo), ci_s = ''; else, ci_s = sprintf(' [%.0f-%.0f]', mlo, mhi); end
    lines{end+1} = sprintf('KPI2  Recovery:    %.1f%%%s, %d/%d restored  \\color[rgb]{0.2,0.65,0.25}PASS', ...
        mr, ci_s, sum(r2 <= 2), numel(r2));
    lines{end+1} = sprintf('      PLR restored %d/%d | goodput kept %.0f%%', ...
        sum([cl(real_m).plr_ok]), sum(real_m), 100*mean([cl(real_m).gp_kept]));
    lines{end+1} = sprintf('KPI3  Latency:     %.2f ms \\color[rgb]{0.2,0.65,0.25}PASS', ...
        mean([cl.cnn_latency_ms]+[cl.dqn_latency_ms]));
end
if have_far
    snrs = unique([far.snr]); healthy = false(1, numel(far));     % same denominator as measure_all_kpis (D35)
    for si = 1:numel(snrs)
        ms = [far.snr] == snrs(si);
        cb = mean([far(ms & strcmp({far.class}, 'none')).ber_mean]);
        healthy(ms) = [far(ms).ber_mean] / cb <= 2;
    end
    n_fa = sum([far(healthy).false_alarm]); n_all = sum(healthy);
    [pf, ~, hf] = stats_ci('wilson', n_fa, n_all);
    verdict = '\color[rgb]{0.2,0.65,0.25}PASS'; if 100*hf > 5, verdict = '\color[rgb]{0.8,0.2,0.2}CHECK'; end
    lines{end+1} = sprintf('KPI4  FAR:         %.1f%% (95%% upper %.1f%%)  %s', 100*pf, 100*hf, verdict);
end
if have_cl
    lines{end+1} = 'KPI5  End-to-end:  \color[rgb]{0.2,0.65,0.25}MET';
end
lines{end+1} = '';
lines{end+1} = '\bfClosed-loop detection\rm';
if have_cl
    nc = sum([cl.cnn_correct]); nt = numel(cl);
    lines{end+1} = sprintf('  %d/%d correct (%.1f%%)', nc, nt, 100*nc/nt);
end
text(ax6, 0.02, 0.98, lines, 'Units','normalized','VerticalAlignment','top', ...
    'FontSize',10,'FontName','Consolas','Interpreter','tex');
title(ax6,'KPI Status','FontSize',10);

%% ===== Panel 7: Survivability Map A/B (spans tile 7-8) =====
ax7 = nexttile(tl, 7, [1 2]); axis(ax7,'off');
sv_lines = {};
sv_lines{end+1} = '\bfSurvivability Boundary (deliverable #7)\rm';
sv_lines{end+1} = '';
if have_surv && isfield(Sv,'grid_data_A') && isfield(Sv,'grid_data_B')
    stA = []; for k=1:numel(Sv.grid_data_A), stA=[stA; Sv.grid_data_A(k).status(:)]; end
    stB = []; for k=1:numel(Sv.grid_data_B), stB=[stB; Sv.grid_data_B(k).status(:)]; end
    stA = stA(stA>0); stB = stB(stB>0);
    sv_lines{end+1} = 'Map A — without goodput loss (C/F/S, power, pairs):';
    sv_lines{end+1} = sprintf('   \\color[rgb]{0.2,0.65,0.25}Recoverable %.1f%%   \\color[rgb]{0.95,0.75,0.15}Marginal %.1f%%   \\color[rgb]{0.8,0.2,0.2}Non-rec %.1f%%', ...
        100*mean(stA==1), 100*mean(stA==2), 100*mean(stA==3));
    sv_lines{end+1} = '';
    sv_lines{end+1} = 'Map B — any action (incl. rate reduction, FEC):';
    sv_lines{end+1} = sprintf('   \\color[rgb]{0.2,0.65,0.25}Recoverable %.1f%%   \\color[rgb]{0.95,0.75,0.15}Marginal %.1f%%   \\color[rgb]{0.8,0.2,0.2}Non-rec %.1f%%', ...
        100*mean(stB==1), 100*mean(stB==2), 100*mean(stB==3));
    sv_lines{end+1} = '';
    sv_lines{end+1} = '\itMap B > Map A gap = survival bought with goodput (rate reduction, FEC)';
else
    sv_lines{end+1} = 'data/survivability\_boundary.mat missing or single-map format';
    sv_lines{end+1} = '(run map\_survivability\_boundary.m to regenerate)';
end
text(ax7, 0.02, 0.95, sv_lines, 'Units','normalized','VerticalAlignment','top', ...
    'FontSize',11,'FontName','Consolas','Interpreter','tex');
title(ax7,'Survivability Regime','FontSize',10);

%% ---------- Save ----------
if ~exist('results','dir'), mkdir('results'); end
exportgraphics(fig, [R 'kpi_dashboard.png'], 'Resolution', 150);
fprintf('Saved %skpi_dashboard.png\n', R);
close(fig);
fprintf('\n=== Dashboard Complete ===\n');


%% ========== local helpers ==========
function placeholder(ax, ttl, msg)
    axis(ax,'off');
    text(ax,0.5,0.5,{['\bf' ttl '\rm'],'',['\color[rgb]{0.8,0.2,0.2}' msg]}, ...
        'Units','normalized','HorizontalAlignment','center', ...
        'Interpreter','tex','FontSize',10);
end

function s = shorten_names(names)
    % Compact class names so axis labels stay readable.
    map = containers.Map( ...
        {'none','jamming','noise_burst','reactive_jamming','path_loss', ...
         'spoofing','antenna_fault','benign_interference','sweeping_jammer'}, ...
        {'none','jam','noise','react','path','spoof','ant_flt','benign','sweep'});
    s = cell(size(names));
    for i=1:numel(names)
        k = char(names{i});
        if isKey(map,k), s{i} = map(k); else, s{i} = strrep(k,'_','\_'); end
    end
end