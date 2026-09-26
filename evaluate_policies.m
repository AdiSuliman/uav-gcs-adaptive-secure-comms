%% EVALUATE_POLICIES - Decision-layer comparison on the test pools (D44-D46)
% Every policy runs the same episodes with the same frame draws (common random
% numbers) on the TEST split of data/policy_pools.mat: sub-runs (flight
% geometries) with seeds never used in training. Episode sets:
%   single    8 threats x 6 Eb/N0, static jammer
%   follower  jamming / reactive_jamming / spoofing that re-acquire the channel
%             2-5 cycles after every hop
%   combined  the 4 test combinations (never seen in training; the agent trains
%             on 4 other combinations)
%   unknown   single threats with the detector output withheld after onset
%             (unknown-threat path: the policy sees only the link measurements)
%   clean     no threat; every change is a false alarm (KPI: FAR, one-sided 95%
%             Clopper-Pearson bound over >= 600 episodes above the Eb/N0 threshold)
% Policies: random; always-on adaptive combining (fixed spatial_diversity); the
% best fixed configuration (chosen on the train pools); expert rule, with and
% without escalation; class -> configuration table tuned on the train pools;
% the DQN of every discount factor trained (the selected one also with
% escalation); one-step oracle (true scenario, follower state and geometry).
% Metrics per episode (after onset unless noted): mean reward per cycle,
% restored cycles (BER <= 2x clean), normalized goodput, cycles to recover
% (restored for 5 consecutive cycles), switches, false switches (whole episode).
% Breakdowns: per threat, per Eb/N0, per interferer direction, per UAV speed.
% Intervals: 95% t over episodes; differences are paired per episode.
%
% Output: results/policy_evaluation.{txt,mat,png}, results/policy_breakdown.png

close all; clc;
fprintf('=== Decision-layer evaluation on the test pools (D44-D46) ===\n\n');
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
Q = load('data/trained_dqn.mat', 'agent', 'agents', 'gammas', 'H', 'seed_summary');
K = link_env('tables', PP);
tab = policy_table(PP, K);
T = Q.H.T; NE = 64;
nSing = numel(PP.singles); nA = numel(PP.actions); nS = numel(PP.ebno);
test_combos = find(ismember(PP.scen, PP.combos));
rs = RandStream('mt19937ar', 'Seed', 2027);
ebno_thr = PP.ebno(1);                                % FAR threshold: lowest Eb/N0 with detector macro-F1 >= 90%
if isfile('results/eval_detector_metrics.mat')
    Md = load('results/eval_detector_metrics.mat', 'metrics');
    if isfield(Md.metrics, 'kpi1_threshold_db') && isfinite(Md.metrics.kpi1_threshold_db)
        ebno_thr = Md.metrics.kpi1_threshold_db;
    end
end

%% 1. Episode sets
foll = find(K.followable(1:nSing));
sets = struct('name', {}, 'spec', {});
sets(end+1) = struct('name', 'single',   'spec', {cells_to_specs(2:nSing, 12, false, false, NE, T, nS, rs)});
sets(end+1) = struct('name', 'follower', 'spec', {cells_to_specs(foll, 16, true, false, NE, T, nS, rs)});
sets(end+1) = struct('name', 'combined', 'spec', {cells_to_specs(test_combos, 16, false, false, NE, T, nS, rs)});
sets(end+1) = struct('name', 'unknown',  'spec', {cells_to_specs(2:nSing, 4, false, true, NE, T, nS, rs)});
sets(end+1) = struct('name', 'clean',    'spec', {cells_to_specs(1, 128, false, false, NE, T, nS, rs)});
iThreat = 1:3;                                         % sets pooled as "threat sets"

%% 2. Best fixed configuration, chosen on the train pools
vspec = cells_to_specs(1:nSing, 4, false, false, NE, T, nS, RandStream('mt19937ar', 'Seed', 11));
fr = zeros(1, nA);
for a = 1:nA
    r = [];
    for b = 1:numel(vspec)
        R = rollout_policy('fixed', PP, K, vspec{b}, 1, [], struct('fixed', a), 900 + b);
        r = [r, R.ret]; %#ok<AGROW>
    end
    fr(a) = mean(r);
end
[~, fixed_best] = max(fr);
fixed_mmse = find(strcmp(PP.actions, 'spatial_diversity'));
fprintf('Best fixed configuration (train pools): %s\n', PP.actions{fixed_best});
fprintf('Class table (train pools): %s | unknown -> %s\n\n', ...
    strjoin(strcat(PP.classes, '->', tab.names), ', '), PP.actions{tab.table_unknown});

%% 3. Policies
nG = numel(Q.gammas);
sel = find(Q.gammas == Q.seed_summary.selected_gamma, 1);
POL = [{'random', 'fixed_mmse', 'fixed', 'rule', 'rule_esc', 'table'}, ...
       arrayfun(@(g) sprintf('dqn_g%d', g), 1:nG, 'UniformOutput', false), {'dqn_esc', 'oracle'}];
LBL = [{'random', 'always adaptive combining', ['fixed: ' PP.actions{fixed_best}], 'rule', 'rule + escalation', ...
        'table (train pools)'}, ...
       arrayfun(@(g) sprintf('DQN gamma=%.2f%s', Q.gammas(g), ternary(g == sel, ' (selected)', '')), 1:nG, ...
       'UniformOutput', false), {'DQN (selected) + escalation', 'oracle (one-step)'}];
iDQN = find(strcmp(POL, sprintf('dqn_g%d', sel)));
col = @(p) find(strcmp(POL, p));

RES = cell(numel(sets), numel(POL));
t0 = tic;
for si = 1:numel(sets)
    for pk = 1:numel(POL)
        kind = POL{pk}; ag = Q.agent; opt = struct();
        switch kind
            case 'fixed',      opt.fixed = fixed_best;
            case 'fixed_mmse', kind = 'fixed'; opt.fixed = fixed_mmse;
            case 'table',      opt = tab;
            case 'dqn_esc',    ag = Q.agents{sel};
        end
        if startsWith(kind, 'dqn_g'), ag = Q.agents{sscanf(kind, 'dqn_g%d')}; kind = 'dqn'; end
        R = [];
        for b = 1:numel(sets(si).spec)
            Rb = rollout_policy(kind, PP, K, sets(si).spec{b}, 2, ag, opt, 30000 + 100*si + b);
            Rb.scn = sets(si).spec{b}.scn; Rb.s = sets(si).spec{b}.s;
            Rb = rmfield(Rb, 'cfg_trace');
            if isempty(R), R = Rb; else, R = cat_struct(R, Rb); end
        end
        R.speed = arrayfun(@(i) pool_speed(PP, R.scn(i), R.s(i), R.r(i)), 1:numel(R.ret));
        RES{si, pk} = R;
    end
    fprintf('  set %-9s %4d episodes x %d policies (%.1f min)\n', sets(si).name, numel(RES{si, 1}.ret), ...
        numel(POL), toc(t0)/60);
end

%% 4. Report
rep = {};
rep{end+1} = '=== DECISION-LAYER EVALUATION, TEST POOLS (D44-D46) ===';
rep{end+1} = sprintf(['Generated: %s | %d-cycle episodes, onset at cycle 3-10 | test sub-runs (geometries) never ' ...
    'used in training | interferer AoA %s'], datestr(now), T, ternary(PP.aoa_random, 'random per sub-run', 'fixed'));
rep{end+1} = 'return = mean reward per cycle (1 = restored at no cost); restored / goodput / recovery after onset;';
rep{end+1} = 'recovered = restored for 5 consecutive cycles; false sw = switches on a healthy link, whole episode.';
rep{end+1} = sprintf('Selected DQN: gamma %.2f (validation, train pools). Training combinations: %s', ...
    Q.seed_summary.selected_gamma, strjoin(PP.train_combos, ', '));
for si = 1:numel(sets)
    rep{end+1} = ''; %#ok<SAGROW>
    rep{end+1} = sprintf('--- %s (%d episodes) ---', sets(si).name, numel(RES{si, 1}.ret)); %#ok<SAGROW>
    rep = [rep, policy_table_lines(RES(si, :), LBL)]; %#ok<AGROW>
    rep{end+1} = paired_line(RES(si, :), POL, LBL, iDQN); %#ok<SAGROW>
end
ALL = cell(1, numel(POL));
for pk = 1:numel(POL)
    ALL{pk} = RES{iThreat(1), pk};
    for si = iThreat(2:end), ALL{pk} = cat_struct(ALL{pk}, RES{si, pk}); end
end
rep{end+1} = '';
rep{end+1} = sprintf('--- threat sets pooled (single + follower + combined, %d episodes) ---', numel(ALL{1}.ret));
rep = [rep, policy_table_lines(ALL, LBL)];
rep{end+1} = paired_line(ALL, POL, LBL, iDQN);

% Per threat
show = {'fixed_mmse', 'fixed', 'rule_esc', 'table', POL{iDQN}, 'dqn_esc', 'oracle'};
hdr = {'always MMSE', 'fixed best', 'rule+esc', 'table', 'DQN', 'DQN+esc', 'oracle'};
rep{end+1} = '';
rep{end+1} = 'Restored cycles after onset per threat (single + follower + combined sets), %:';
rep{end+1} = sprintf('%-32s%s', 'scenario', sprintf('%12s', hdr{:}));
test_scn = [2:nSing, test_combos];
PT = nan(numel(test_scn), numel(show));
for ti = 1:numel(test_scn)
    sc = test_scn(ti);
    for c = 1:numel(show)
        x = [];
        for si = iThreat
            R = RES{si, col(show{c})}; x = [x, R.restored_post(R.scn == sc)]; %#ok<AGROW>
        end
        PT(ti, c) = 100 * mean(x);
    end
    rep{end+1} = sprintf('%-32s%s', PP.scen{sc}, sprintf('%12.1f', PT(ti, :))); %#ok<SAGROW>
end

% Per Eb/N0 (single set)
rep{end+1} = '';
rep{end+1} = 'Restored cycles after onset per Eb/N0 (single set), %:';
rep{end+1} = sprintf('%-12s%s', 'Eb/N0 [dB]', sprintf('%12s', hdr{:}));
PE = nan(nS, numel(show));
for s = 1:nS
    PE(s, :) = arrayfun(@(c) 100 * mean(RES{1, col(show{c})}.restored_post(RES{1, 1}.s == s)), 1:numel(show));
    rep{end+1} = sprintf('%-12g%s', PP.ebno(s), sprintf('%12.1f', PE(s, :))); %#ok<SAGROW>
end

% Per interferer direction (single set, directional threats)
bins_aoa = [0 20 45 90]; PA = [];
if PP.aoa_random
    rep{end+1} = '';
    rep{end+1} = 'Restored cycles after onset vs interferer direction (single set, directional threats), %:';
    dirn = find(~ismember(PP.scen(1:nSing), {'none', 'path_loss', 'antenna_fault'}));
    rep{end+1} = sprintf('%-18s%s', '|AoA| from GCS', sprintf('%12s', hdr{:}));
    th = abs(RES{1, 1}.aoa(1, :)); isd = ismember(RES{1, 1}.scn, dirn);
    PA = nan(numel(bins_aoa) - 1, numel(show));
    for bi = 1:numel(bins_aoa) - 1
        m = isd & th >= bins_aoa(bi) & th < bins_aoa(bi+1);
        PA(bi, :) = arrayfun(@(c) 100 * mean(RES{1, col(show{c})}.restored_post(m)), 1:numel(show));
        rep{end+1} = sprintf('%-18s%s', sprintf('%d-%d deg (%d)', bins_aoa(bi), bins_aoa(bi+1), sum(m)), ...
            sprintf('%12.1f', PA(bi, :))); %#ok<SAGROW>
    end
end

% Per UAV speed (single set)
bins_v = linspace(PP.speed_range(1), PP.speed_range(2), 5);
rep{end+1} = '';
rep{end+1} = 'Restored cycles after onset vs UAV speed (single set), %:';
rep{end+1} = sprintf('%-18s%s', 'speed [km/h]', sprintf('%12s', hdr{:}));
PV = nan(numel(bins_v) - 1, numel(show));
v1 = RES{1, 1}.speed;
for bi = 1:numel(bins_v) - 1
    m = v1 >= bins_v(bi) & v1 < bins_v(bi+1) + (bi == numel(bins_v) - 1);
    PV(bi, :) = arrayfun(@(c) 100 * mean(RES{1, col(show{c})}.restored_post(m)), 1:numel(show));
    rep{end+1} = sprintf('%-18s%s', sprintf('%.0f-%.0f (%d)', bins_v(bi), bins_v(bi+1), sum(m)), ...
        sprintf('%12.1f', PV(bi, :))); %#ok<SAGROW>
end

% False alarms on the clean link
iC = find(strcmp({sets.name}, 'clean'));
Rc = RES{iC, 1}; above = PP.ebno(Rc.s) >= ebno_thr;
rep{end+1} = '';
rep{end+1} = sprintf(['False alarms on the clean link, Eb/N0 >= %g dB (%d episodes x %d cycles): episodes with ' ...
    '>= 1 change, one-sided 95%% Clopper-Pearson upper bound; per-cycle rate'], ebno_thr, sum(above), T);
FAR = struct('policy', {}, 'k', {}, 'n', {}, 'p', {}, 'upper', {}, 'per_cycle', {});
for pk = 1:numel(POL)
    if strcmp(POL{pk}, 'oracle') || strcmp(POL{pk}, 'random'), continue; end
    R = RES{iC, pk}; kf = sum(R.switches(above) > 0); n = sum(above);
    FAR(end+1) = struct('policy', LBL{pk}, 'k', kf, 'n', n, 'p', kf / n, 'upper', cp_upper(kf, n), ...
        'per_cycle', sum(R.switches(above)) / (n * T)); %#ok<SAGROW>
    rep{end+1} = sprintf('  %-32s %4d / %4d = %6.2f%%   upper %6.2f%%   per cycle %.4f%%', LBL{pk}, kf, n, ...
        100 * kf / n, 100 * FAR(end).upper, 100 * FAR(end).per_cycle); %#ok<SAGROW>
end

% Final configuration of the selected DQN per threat (single set)
rep{end+1} = '';
rep{end+1} = 'Configuration at the end of the episode, selected DQN (single set): most frequent two per threat';
Rd = RES{1, iDQN};
for sc = 2:nSing
    cf = Rd.cfg_final(Rd.scn == sc);
    [u, ~, j] = unique(cf); cnt = accumarray(j(:), 1); [cnt, o] = sort(cnt, 'descend'); u = u(o);
    txt = strjoin(arrayfun(@(i) sprintf('%s %.0f%%', PP.actions{u(i)}, 100 * cnt(i) / numel(cf)), ...
        1:min(2, numel(u)), 'UniformOutput', false), ', ');
    rep{end+1} = sprintf('  %-22s %s', PP.scen{sc}, txt); %#ok<SAGROW>
end

fid = fopen('results/policy_evaluation.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
set_names = {sets.name};
KP = struct('per_threat', PT, 'per_threat_scn', {PP.scen(test_scn)}, 'per_ebno', PE, 'ebno', PP.ebno, ...
    'per_aoa', PA, 'aoa_bins', bins_aoa, 'per_speed', PV, 'speed_bins', bins_v, 'show', {show}, 'show_lbl', {hdr}, ...
    'far', FAR, 'ebno_thr', ebno_thr, 'selected_gamma', Q.seed_summary.selected_gamma);
save('results/policy_evaluation.mat', 'RES', 'POL', 'LBL', 'set_names', 'fixed_best', 'tab', 'iDQN', 'KP', 'iThreat');

%% 5. Figures
key = {'random', 'fixed', 'rule_esc', 'table', POL{iDQN}, 'oracle'};
kl = cellfun(@(p) LBL{col(p)}, key, 'UniformOutput', false);
fig = figure('Position', [60 60 1500 460], 'Color', 'w');
metric = {'ret', 'restored_post', 'gput_post'};
ttl = {'Mean reward per cycle', 'Restored cycles after onset', 'Normalized goodput after onset'};
for m = 1:3
    subplot(1, 3, m);
    Y = zeros(4, numel(key));
    for si = 1:4, Y(si, :) = cellfun(@(p) mean(RES{si, col(p)}.(metric{m})), key); end
    bar(Y); grid on; set(gca, 'XTickLabel', set_names(1:4));
    title(ttl{m});
end
lg = legend(kl, 'Orientation', 'horizontal', 'NumColumns', 6, 'FontSize', 8);
lg.Position = [0.15 0.01 0.7 0.05];
sgtitle('Decision layer on the test pools (D44-D46)');
saveas(fig, 'results/policy_evaluation.png'); close(fig);

fig = figure('Position', [60 60 1500 420], 'Color', 'w');
subplot(1, 3, 1); plot(PP.ebno, PE, '-o', 'LineWidth', 1.3); grid on;
xlabel('E_b/N_0 [dB]'); ylabel('restored cycles after onset [%]'); title('Single threats vs E_b/N_0'); ylim([0 105]);
subplot(1, 3, 2);
if ~isempty(PA)
    bar(PA); grid on; ylim([0 105]);
    set(gca, 'XTickLabel', arrayfun(@(b) sprintf('%d-%d', bins_aoa(b), bins_aoa(b+1)), 1:numel(bins_aoa) - 1, ...
        'UniformOutput', false));
    xlabel('|interferer direction - GCS direction| [deg]'); title('Directional threats vs geometry');
end
subplot(1, 3, 3); plot((bins_v(1:end-1) + bins_v(2:end)) / 2, PV, '-s', 'LineWidth', 1.3); grid on; ylim([0 105]);
xlabel('UAV speed [km/h]'); title('Single threats vs UAV speed');
legend(hdr, 'Location', 'southoutside', 'NumColumns', 4, 'FontSize', 8);
sgtitle('Restoration breakdown, test pools');
saveas(fig, 'results/policy_breakdown.png'); close(fig);
fprintf('Saved results/policy_evaluation.{txt,mat,png}, results/policy_breakdown.png\n');

%% ===================== Local functions =====================
function specs = cells_to_specs(scns, reps, follow, unk, NE, T, nS, rs)
% Every (scenario, Eb/N0) cell `reps` times, packed into batches of NE episodes.
[sc, s] = ndgrid(scns, 1:nS);
sc = repmat(sc(:)', 1, reps); s = repmat(s(:)', 1, reps);
n = numel(sc); nb = ceil(n / NE);
pad = nb * NE - n;
sc = [sc, sc(1:pad)]; s = [s, s(1:pad)];
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*NE + (1:NE);
    specs{b} = struct('scn', sc(i), 's', s(i), 'onset', randi(rs, [3 10], 1, NE), ...
        'follow', repmat(follow, 1, NE), 'fdelay', randi(rs, [2 5], 1, NE), 'unk', repmat(unk, 1, NE), 'T', T);
end
end

function v = pool_speed(PP, sc, s, r)
[~, v] = pool_seed(sc, s, 2, r, PP.speed_range);
end

function u = cp_upper(k, n)
% One-sided 95% Clopper-Pearson upper bound of a binomial proportion.
if k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

function lines = policy_table_lines(RR, LBL)
lines = {sprintf('%-34s %22s %22s %9s %10s %6s %9s %9s', 'policy', 'return', 'restored %', 'goodput', ...
    'recovered', 'T_rec', 'switches', 'false sw')};
for pk = 1:numel(RR)
    R = RR{pk};
    rec = ~isnan(R.t_rec);
    lines{end+1} = sprintf('%-34s %22s %22s %9.3f %9.1f%% %6s %9.2f %9.3f', LBL{pk}, ci(R.ret, '%.3f'), ...
        ci(100*R.restored_post, '%.1f'), mean(R.gput_post), 100*mean(rec), med(R.t_rec(rec)), ...
        mean(R.switches), mean(R.false_sw)); %#ok<AGROW>
end
end

function s = paired_line(RR, POL, LBL, iDQN)
d = @(k) ci(RR{iDQN}.ret - RR{k}.ret, '%+.3f');
s = sprintf('Paired return difference, selected DQN minus: rule+esc %s | table %s | fixed best %s', ...
    d(find(strcmp(POL, 'rule_esc'))), d(find(strcmp(POL, 'table'))), d(find(strcmp(POL, 'fixed'))));
for k = find(startsWith(POL, 'dqn_g'))
    if k == iDQN, continue; end
    s = sprintf('%s | %s %s', s, strrep(LBL{k}, 'DQN ', ''), d(k));
end
end

function R = cat_struct(R, Rb)
f = fieldnames(R);
for i = 1:numel(f), R.(f{i}) = [R.(f{i}), Rb.(f{i})]; end
end

function s = ci(x, f)
[m, lo, hi] = stats_ci('t', x);
s = sprintf([f ' [' f ', ' f ']'], m, lo, hi);
end

function s = med(x)
if isempty(x), s = '-'; else, s = sprintf('%.0f', median(x)); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
