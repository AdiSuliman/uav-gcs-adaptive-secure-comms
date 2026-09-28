%% EVALUATE_POLICIES - Decision-layer comparison on the test pools (D44-D51, D59)
% Every policy runs the same episodes with the same frame draws (common random
% numbers) on the TEST split of data/policy_pools.mat: geometries never used in
% training or validation. Each episode is one geometry; every test geometry of
% every (cell, Eb/N0) is used, each with two onsets. Episode sets:
%   single    8 threats x 3 severities (low, nominal, high) x 6 Eb/N0, static jammer
%   follower  jamming / reactive_jamming / spoofing that re-acquire the channel
%             2-5 cycles after every hop, 3 severities
%   combined  the 4 test combinations (never seen in training)
%   unknown   single threats with the detector output withheld after onset
%             (unknown-threat path: the policy sees only the link measurements)
%   clean     no threat; every change is a false alarm. KPI 6 (one-sided 95%
%             Clopper-Pearson bound, >= 600 episodes) is computed on
%             data/clean_test_pools.mat, one episode per new geometry (D51)
% Policies: no response (the link that does not react), random, always-on MMSE,
% the best fixed configuration (train pools), expert rule with and without
% escalation, class -> configuration table (train pools), the DQN of every
% discount factor (the selected one also with escalation), one-step oracle.
% Main metric (proposal KPI 4): RECOVERED episodes -- BER and packet loss back to
% <= 2x the clean link for 5 consecutive cycles -- among the RECOVERABLE ones
% (some configuration restores both in that geometry, link_env.m); the rest is
% the survivability boundary. Also: cycles restored after onset, goodput, cycles
% to recover, switches and false switches, mean reward.
% Intervals: 95% percentile bootstrap over flight geometries (boot_cluster.m;
% episodes of one geometry are resampled together); differences are paired per
% episode.
%
% Output: results/policy_evaluation.{txt,mat,png}, results/policy_breakdown.png

close all; clc;
fprintf('=== Decision-layer evaluation on the test pools (D44-D51, D59) ===\n\n');
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
Q = load('data/trained_dqn.mat', 'agent', 'agents', 'gammas', 'H', 'seed_summary', 'confirm', 'alarm_mode', 'drop_db');
PP.confirm = Q.confirm; PP.alarm_mode = Q.alarm_mode;           % same monitor for every policy
if ~isempty(Q.drop_db), PP.drop_db = Q.drop_db; end
K = link_env('tables', PP);
C = decision_config();
tab = policy_table(PP, K);
TEST = 3; T = Q.H.T; NE = 64; REPS = 2;
if exist('SMOKE', 'var') && SMOKE, REPS = 1; end         % reduced chain check (run_stage smoke)
nA = numel(PP.actions); nS = numel(PP.ebno); nG = K.nR(TEST);
single_cells = find(ismember(PP.scen, PP.singles) & ~strcmp(PP.scen, 'none'));
combo_cells = find(ismember(PP.scen, PP.combos));
clean_cell = K.clean;
rs = RandStream('mt19937ar', 'Seed', 2027);
ebno_thr = PP.ebno(1);                                % FAR threshold: lowest Eb/N0 with detector macro-F1 >= 90%
if isfile('results/eval_detector_metrics.mat')
    Md = load('results/eval_detector_metrics.mat', 'metrics');
    if isfield(Md.metrics, 'kpi1_threshold_db') && isfinite(Md.metrics.kpi1_threshold_db)
        ebno_thr = Md.metrics.kpi1_threshold_db;
    end
end

%% 1. Episode sets
foll = single_cells(K.followable(single_cells));
sets = struct('name', {}, 'spec', {});
sets(end+1) = struct('name', 'single',   'spec', {episodes(single_cells, nS, nG, REPS, false, false, NE, T, rs)});
sets(end+1) = struct('name', 'follower', 'spec', {episodes(foll, nS, nG, REPS, true, false, NE, T, rs)});
sets(end+1) = struct('name', 'combined', 'spec', {episodes(combo_cells, nS, nG, REPS, false, false, NE, T, rs)});
sets(end+1) = struct('name', 'unknown',  'spec', {episodes(single_cells, nS, nG, 1, false, true, NE, T, rs)});
sets(end+1) = struct('name', 'clean',    'spec', {episodes(clean_cell, nS, nG, 8, false, false, NE, T, rs)});
iThreat = 1:3;                                         % sets pooled as "threat sets"

%% 2. Best fixed configuration, chosen on the train pools
vspec = episodes([clean_cell, single_cells], nS, K.nR(1), 1, false, false, NE, T, RandStream('mt19937ar', 'Seed', 11));
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
nGam = numel(Q.gammas);
sel = find(Q.gammas == Q.seed_summary.selected_gamma, 1);
POL = [{'none', 'random', 'fixed_mmse', 'fixed', 'rule', 'rule_esc', 'table'}, ...
       arrayfun(@(g) sprintf('dqn_g%d', g), 1:nGam, 'UniformOutput', false), {'dqn_esc', 'oracle'}];
LBL = [{'no response', 'random', 'always-on MMSE', ['fixed: ' PP.actions{fixed_best}], 'rule', 'rule + escalation', ...
        'table (train pools)'}, ...
       arrayfun(@(g) sprintf('DQN gamma=%.2f%s', Q.gammas(g), ternary(g == sel, ' (selected)', '')), 1:nGam, ...
       'UniformOutput', false), {'DQN (selected) + escalation', 'oracle (one-step)'}];
iDQN = find(strcmp(POL, sprintf('dqn_g%d', sel)));
col = @(p) find(strcmp(POL, p));

RES = cell(numel(sets), numel(POL));
t0 = tic;
for si = 1:numel(sets)
    for pk = 1:numel(POL)
        [kind, ag, opt] = policy_setup(POL{pk}, Q, sel, fixed_best, fixed_mmse, tab, K.na);
        RES{si, pk} = run_set(kind, PP, K, sets(si).spec, TEST, ag, opt, 30000 + 100*si);
    end
    fprintf('  set %-9s %5d episodes x %d policies (%.1f min)\n', sets(si).name, numel(RES{si, 1}.ret), ...
        numel(POL), toc(t0)/60);
end

%% 4. Report
rep = {};
rep{end+1} = '=== DECISION-LAYER EVALUATION, TEST POOLS (D44-D51, D59) ===';
rep{end+1} = sprintf(['Generated: %s | %d-cycle episodes, onset at cycle 3-10 | %d test geometries per (cell, Eb/N0), ' ...
    'never used in training or validation | interferer AoA %s'], datestr(now), T, nG, ...
    ternary(PP.aoa_random, 'random per geometry', 'fixed'));
rep{end+1} = ['recovered = BER and packet loss <= 2x clean for 5 consecutive cycles, among RECOVERABLE episodes ' ...
    '(some configuration restores both in that geometry); restored / ok = cycles after onset with BER / BER and ' ...
    'packet loss restored; false sw = changes on a healthy link, whole episode.'];
rep{end+1} = sprintf(['Selected DQN: gamma %.2f, training false-switch penalty %d; alarm ''%s'', confirmation ' ...
    '%d-of-%d for every monitored policy. Training combinations: %s. Intervals: 95%% bootstrap over geometries.'], ...
    Q.seed_summary.selected_gamma, Q.seed_summary.selected_fa_pen, PP.alarm_mode, PP.confirm, strjoin(PP.train_combos, ', '));
for si = 1:numel(sets)
    rep{end+1} = ''; %#ok<SAGROW>
    R1 = RES{si, 1};
    rep{end+1} = sprintf('--- %s (%d episodes, %d recoverable) ---', sets(si).name, numel(R1.ret), ...
        sum(R1.recoverable & R1.threat)); %#ok<SAGROW>
    rep = [rep, policy_table_lines(RES(si, :), LBL)]; %#ok<AGROW>
    if si ~= find(strcmp({sets.name}, 'clean')), rep{end+1} = paired_line(RES(si, :), POL, LBL, iDQN); end %#ok<SAGROW>
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

% Per threat and severity (KPI 4: >= 90% of the recoverable episodes of every threat)
show = {'none', 'fixed', 'rule_esc', 'table', POL{iDQN}, 'dqn_esc', 'oracle'};
hdr = {'no resp.', 'fixed best', 'rule+esc', 'table', 'DQN', 'DQN+esc', 'oracle'};
rep{end+1} = '';
rep{end+1} = 'Recovered episodes among the recoverable, per threat (single + follower + combined sets), %:';
rep{end+1} = sprintf('%-30s %8s %11s%s', 'threat', 'episodes', 'recoverable', sprintf('%11s', hdr{:}));
threats = [PP.singles(2:end), PP.combos];
PT = nan(numel(threats), numel(show)); PTsev = nan(numel(threats), 3, numel(show)); RECsh = nan(numel(threats), 1);
for ti = 1:numel(threats)
    m = strcmp(PP.scen(ALL{1}.scn), threats{ti}) & ALL{1}.threat;
    mr = m & ALL{1}.recoverable;
    RECsh(ti) = mean(ALL{1}.recoverable(m));
    for c = 1:numel(show)
        PT(ti, c) = 100 * mean(ALL{col(show{c})}.recovered(mr));
        for v = 1:3
            mv = mr & PP.sev(ALL{1}.scn) == v;
            PTsev(ti, v, c) = 100 * mean(ALL{col(show{c})}.recovered(mv));
        end
    end
    rep{end+1} = sprintf('%-30s %8d %10.1f%%%s', threats{ti}, sum(m), 100 * RECsh(ti), sprintf('%11.1f', PT(ti, :))); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = 'Selected DQN per threat and severity (low / nominal / high), recovered among recoverable, %:';
for ti = 1:numel(PP.singles) - 1
    rep{end+1} = sprintf('  %-26s %s', threats{ti}, sprintf('%8.1f', squeeze(PTsev(ti, :, 5)))); %#ok<SAGROW>
end
kpi4 = PT(:, 5) >= 90;
rep{end+1} = sprintf('KPI 4 (DQN >= 90%% of the recoverable episodes of every threat): %d of %d threats | lowest %s %.1f%%', ...
    sum(kpi4), numel(kpi4), threats{find(PT(:, 5) == min(PT(:, 5)), 1)}, min(PT(:, 5)));

% Per Eb/N0 (single set)
rep{end+1} = '';
rep{end+1} = 'Recovered among recoverable per Eb/N0 (single set), %:';
rep{end+1} = sprintf('%-12s%s', 'Eb/N0 [dB]', sprintf('%11s', hdr{:}));
PE = nan(nS, numel(show)); R1 = RES{1, 1}; mrec = R1.recoverable & R1.threat;
for s = 1:nS
    PE(s, :) = arrayfun(@(c) 100 * mean(RES{1, col(show{c})}.recovered(mrec & R1.s == s)), 1:numel(show));
    rep{end+1} = sprintf('%-12g%s', PP.ebno(s), sprintf('%11.1f', PE(s, :))); %#ok<SAGROW>
end

% Per interferer direction (single set, directional threats)
bins_aoa = [0 20 45 90]; PA = [];
if PP.aoa_random
    rep{end+1} = '';
    rep{end+1} = 'Recovered among recoverable vs interferer direction (single set, directional threats), %:';
    dirn = ~ismember(PP.scen(R1.scn), {'path_loss', 'antenna_fault'});
    rep{end+1} = sprintf('%-18s%s', '|AoA| from GCS', sprintf('%11s', hdr{:}));
    th = abs(R1.aoa(1, :));
    PA = nan(numel(bins_aoa) - 1, numel(show));
    for bi = 1:numel(bins_aoa) - 1
        m = mrec & dirn & th >= bins_aoa(bi) & th < bins_aoa(bi+1);
        PA(bi, :) = arrayfun(@(c) 100 * mean(RES{1, col(show{c})}.recovered(m)), 1:numel(show));
        rep{end+1} = sprintf('%-18s%s', sprintf('%d-%d deg (%d)', bins_aoa(bi), bins_aoa(bi+1), sum(m)), ...
            sprintf('%11.1f', PA(bi, :))); %#ok<SAGROW>
    end
    rep{end+1} = sprintf('  recoverable share per direction bin: %s', strjoin(arrayfun(@(bi) sprintf('%d-%d deg %.1f%%', ...
        bins_aoa(bi), bins_aoa(bi+1), 100 * mean(R1.recoverable(R1.threat & dirn & th >= bins_aoa(bi) & ...
        th < bins_aoa(bi+1)))), 1:numel(bins_aoa) - 1, 'UniformOutput', false), ' | '));
end

% Per UAV speed (single set)
bins_v = linspace(PP.speed_range(1), PP.speed_range(2), 5);
rep{end+1} = '';
rep{end+1} = 'Recovered among recoverable vs UAV speed (single set), %:';
rep{end+1} = sprintf('%-18s%s', 'speed [km/h]', sprintf('%11s', hdr{:}));
PV = nan(numel(bins_v) - 1, numel(show));
for bi = 1:numel(bins_v) - 1
    m = mrec & R1.speed >= bins_v(bi) & R1.speed < bins_v(bi+1) + (bi == numel(bins_v) - 1);
    PV(bi, :) = arrayfun(@(c) 100 * mean(RES{1, col(show{c})}.recovered(m)), 1:numel(show));
    rep{end+1} = sprintf('%-18s%s', sprintf('%.0f-%.0f (%d)', bins_v(bi), bins_v(bi+1), sum(m)), ...
        sprintf('%11.1f', PV(bi, :))); %#ok<SAGROW>
end

% False alarms on the clean link: test pools (nG geometries per Eb/N0)
iC = find(strcmp({sets.name}, 'clean'));
cls_list = [PP.classes, {'unknown'}];
Rc = RES{iC, 1}; above = PP.ebno(Rc.s) >= ebno_thr;
rep{end+1} = '';
rep{end+1} = sprintf(['False alarms on the clean link, test pools (%d geometries per Eb/N0), Eb/N0 >= %g dB ' ...
    '(%d episodes x %d cycles): episodes with >= 1 change, one-sided 95%% Clopper-Pearson upper bound; per-cycle rate'], ...
    nG, ebno_thr, sum(above), T);
[FAR, FD, lines] = far_report(RES(iC, :), POL, LBL, above, T, iDQN, PP.ebno, cls_list);
rep = [rep, lines];

% False alarms over many independent geometries: one episode per geometry (KPI 6, D51)
FAR_t = FAR; FD_t = FD; n_geom = 0; RW = {};
if isfile('data/clean_test_pools.mat')
    Ct = load('data/clean_test_pools.mat', 'CT'); CT = Ct.CT; clear Ct
    n_geom = CT.n_geom;
    PPw = PP;
    PPw.pools(:, :, :, TEST) = {[]};
    PPw.pools(clean_cell, :, :, TEST) = reshape(CT.pools(1, :, :), [1 nS nA]);
    PPw.runs{TEST} = CT.runs;
    Kw = link_env('tables', PPw);
    [ss, rr] = ndgrid(1:nS, 1:n_geom); ss = ss(:)'; rr = rr(:)';
    n = numel(ss); nb = ceil(n / NE); pad = nb * NE - n;
    ss = [ss, ss(1:pad)]; rr = [rr, rr(1:pad)];
    specs = cell(1, nb);
    for b = 1:nb
        i = (b-1)*NE + (1:NE);
        specs{b} = struct('scn', clean_cell * ones(1, NE), 's', ss(i), 'onset', 3 * ones(1, NE), 'follow', false(1, NE), ...
            'fdelay', 2 * ones(1, NE), 'unk', false(1, NE), 'T', T, 'r', rr(i));
    end
    RW = cell(1, numel(POL));
    for pk = 1:numel(POL)
        [kind, ag, opt] = policy_setup(POL{pk}, Q, sel, fixed_best, fixed_mmse, tab, K.na);
        R = run_set(kind, PPw, Kw, specs, TEST, ag, opt, 40000);
        f = fieldnames(R);
        for j = 1:numel(f), R.(f{j}) = R.(f{j})(:, 1:n); end        % drop the padding
        RW{pk} = R;
    end
    aboveW = PP.ebno(RW{1}.s) >= ebno_thr;
    rep{end+1} = '';
    rep{end+1} = sprintf(['False alarms on the clean link, %d new geometries per Eb/N0 (data/clean_test_pools.mat), ' ...
        'one episode per geometry, Eb/N0 >= %g dB (%d independent episodes x %d cycles) -> KPI 6'], n_geom, ...
        ebno_thr, sum(aboveW), T);
    [FAR, FD, lines] = far_report(RW, POL, LBL, aboveW, T, iDQN, PP.ebno, cls_list);
    rep = [rep, lines];
end

% Final configuration of the selected DQN per threat (single set)
rep{end+1} = '';
rep{end+1} = 'Configuration at the end of the episode, selected DQN (single set): most frequent two per threat';
Rd = RES{1, iDQN};
for ti = 1:numel(PP.singles) - 1
    cf = Rd.cfg_final(strcmp(PP.scen(Rd.scn), threats{ti}));
    [u, ~, j] = unique(cf); cnt = accumarray(j(:), 1); [cnt, o] = sort(cnt, 'descend'); u = u(o);
    txt = strjoin(arrayfun(@(i) sprintf('%s %.0f%%', PP.actions{u(i)}, 100 * cnt(i) / numel(cf)), ...
        1:min(2, numel(u)), 'UniformOutput', false), ', ');
    rep{end+1} = sprintf('  %-22s %s', threats{ti}, txt); %#ok<SAGROW>
end

fid = fopen('results/policy_evaluation.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
set_names = {sets.name};
KP = struct('per_threat', PT, 'per_threat_sev', PTsev, 'threats', {threats}, 'recoverable_share', RECsh, ...
    'kpi4_met', kpi4, 'per_ebno', PE, 'ebno', PP.ebno, 'per_aoa', PA, 'aoa_bins', bins_aoa, 'per_speed', PV, ...
    'speed_bins', bins_v, 'show', {show}, 'show_lbl', {hdr}, 'far', FAR, 'far_diag', FD, 'far_testpools', FAR_t, ...
    'far_diag_testpools', FD_t, 'far_geoms', n_geom, 'cls_list', {cls_list}, 'ebno_thr', ebno_thr, ...
    'selected_gamma', Q.seed_summary.selected_gamma, 'confirm', PP.confirm, 'alarm_mode', PP.alarm_mode);
save('results/policy_evaluation.mat', 'RES', 'RW', 'POL', 'LBL', 'set_names', 'fixed_best', 'tab', 'iDQN', 'KP', ...
    'iThreat', 'ALL');

%% 5. Figures
key = {'none', 'fixed', 'rule_esc', 'table', POL{iDQN}, 'oracle'};
kl = cellfun(@(p) LBL{col(p)}, key, 'UniformOutput', false);
fig = figure('Position', [60 60 1500 460], 'Color', 'w');
metric = {'recovered', 'ok_post', 'gput_post'};
ttl = {'Recovered episodes (recoverable)', 'Cycles restored after onset (BER and packet loss)', 'Normalized goodput after onset'};
for m = 1:3
    subplot(1, 3, m);
    Y = zeros(4, numel(key));
    for si = 1:4
        for k = 1:numel(key)
            R = RES{si, col(key{k})};
            if m == 1, Y(si, k) = mean(R.recovered(R.recoverable & R.threat));
            else, Y(si, k) = mean(R.(metric{m}), 'omitnan'); end
        end
    end
    bar(Y); grid on; set(gca, 'XTickLabel', set_names(1:4));
    title(ttl{m});
end
lg = legend(kl, 'Orientation', 'horizontal', 'NumColumns', 6, 'FontSize', 8, 'Interpreter', 'none');
lg.Position = [0.15 0.01 0.7 0.05];
sgtitle('Decision layer on the test pools (D59)');
saveas(fig, 'results/policy_evaluation.png'); close(fig);

fig = figure('Position', [60 60 1500 420], 'Color', 'w');
subplot(1, 3, 1); plot(PP.ebno, PE, '-o', 'LineWidth', 1.3); grid on;
xlabel('E_b/N_0 [dB]'); ylabel('recovered among recoverable [%]'); title('Single threats vs E_b/N_0'); ylim([0 105]);
subplot(1, 3, 2);
if ~isempty(PA)
    bar(PA); grid on; ylim([0 105]);
    set(gca, 'XTickLabel', arrayfun(@(b) sprintf('%d-%d', bins_aoa(b), bins_aoa(b+1)), 1:numel(bins_aoa) - 1, ...
        'UniformOutput', false));
    xlabel('|interferer direction - GCS direction| [deg]'); title('Directional threats vs geometry');
end
subplot(1, 3, 3); plot((bins_v(1:end-1) + bins_v(2:end)) / 2, PV, '-s', 'LineWidth', 1.3); grid on; ylim([0 105]);
xlabel('UAV speed [km/h]'); title('Single threats vs UAV speed');
legend(hdr, 'Location', 'southoutside', 'NumColumns', 4, 'FontSize', 8, 'Interpreter', 'none');
sgtitle('Recovery breakdown, test pools');
saveas(fig, 'results/policy_breakdown.png'); close(fig);
fprintf('Saved results/policy_evaluation.{txt,mat,png}, results/policy_breakdown.png\n');

%% ===================== Local functions =====================
function specs = episodes(cells, nS, nG, reps, follow, unk, NE, T, rs)
% Every (cell, Eb/N0, test geometry) `reps` times, packed into batches of NE.
[c, s, r] = ndgrid(cells, 1:nS, 1:nG);
c = repmat(c(:)', 1, reps); s = repmat(s(:)', 1, reps); r = repmat(r(:)', 1, reps);
n = numel(c); nb = ceil(n / NE); pad = nb * NE - n;
c = [c, c(1:pad)]; s = [s, s(1:pad)]; r = [r, r(1:pad)];
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*NE + (1:NE);
    specs{b} = struct('scn', c(i), 's', s(i), 'r', r(i), 'onset', randi(rs, [3 10], 1, NE), ...
        'follow', repmat(follow, 1, NE), 'fdelay', randi(rs, [2 5], 1, NE), 'unk', repmat(unk, 1, NE), 'T', T);
end
specs{end}.n_valid = NE - pad;
end

function R = run_set(kind, PP, K, specs, split, ag, opt, seed0)
% All batches of one set; padding of the last batch dropped; geometry id and
% speed per episode.
R = [];
for b = 1:numel(specs)
    Rb = rollout_policy(kind, PP, K, specs{b}, split, ag, opt, seed0 + b);
    Rb.scn = specs{b}.scn; Rb.s = specs{b}.s;
    Rb.threat = ~strcmp(PP.scen(Rb.scn), 'none');
    Rb = rmfield(Rb, 'cfg_trace');
    if isfield(specs{b}, 'n_valid')
        f = fieldnames(Rb);
        for j = 1:numel(f), Rb.(f{j}) = Rb.(f{j})(:, 1:specs{b}.n_valid); end
    end
    if isempty(R), R = Rb; else, R = cat_struct(R, Rb); end
end
R.geom = 1000 * R.s + R.r;                              % flight geometry (bootstrap cluster)
[~, R.speed] = arrayfun(@(s, r) pool_seed(1, s, 2, r, PP.speed_range), R.s, R.r);
end

function [kind, ag, opt] = policy_setup(name, Q, sel, fixed_best, fixed_mmse, tab, na)
% Policy kind, agent and options of one evaluated policy.
kind = name; ag = Q.agent; opt = struct();
switch name
    case 'none',       kind = 'fixed'; opt.fixed = na;
    case 'fixed',      opt.fixed = fixed_best;
    case 'fixed_mmse', kind = 'fixed'; opt.fixed = fixed_mmse;
    case 'table',      opt = tab;
    case 'dqn_esc',    ag = Q.agents{sel};
end
if startsWith(name, 'dqn_g'), ag = Q.agents{sscanf(name, 'dqn_g%d')}; kind = 'dqn'; end
end

function [FAR, FD, lines] = far_report(RR, POL, LBL, above, T, iDQN, ebno, cls_list)
% False-alarm counts per policy (episodes with >= 1 change, Clopper-Pearson
% bound, per-cycle rate), and for the selected DQN and rule + escalation the
% false-alarm episodes per Eb/N0 and the trigger at the first change.
lines = {};
FAR = struct('policy', {}, 'k', {}, 'n', {}, 'p', {}, 'upper', {}, 'per_cycle', {});
for pk = 1:numel(POL)
    if any(strcmp(POL{pk}, {'oracle', 'random'})), continue; end
    R = RR{pk}; kf = sum(R.switches(above) > 0); n = sum(above);
    FAR(end+1) = struct('policy', LBL{pk}, 'k', kf, 'n', n, 'p', kf / n, 'upper', cp_upper(kf, n), ...
        'per_cycle', sum(R.switches(above)) / (n * T)); %#ok<AGROW>
    lines{end+1} = sprintf('  %-40s %4d / %4d = %6.2f%%   upper %6.2f%%   per cycle %.4f%%', LBL{pk}, kf, n, ...
        100 * kf / n, 100 * FAR(end).upper, 100 * FAR(end).per_cycle); %#ok<AGROW>
end
nS = numel(ebno);
FD = struct('policy', {}, 'by_ebno', {}, 'n_ebno', {}, 'cls', {}, 'deg', {}, 'drop', {});
for pk = [iDQN, find(strcmp(POL, 'rule_esc'))]
    R = RR{pk}; fe = above & R.switches > 0;
    byE = arrayfun(@(s) sum(fe & R.s == s), 1:nS); nE = arrayfun(@(s) sum(above & R.s == s), 1:nS);
    lines{end+1} = sprintf('  %s, false-alarm episodes per Eb/N0: %s', LBL{pk}, strjoin(arrayfun(@(s) ...
        sprintf('%g dB %d/%d', ebno(s), byE(s), nE(s)), 1:nS, 'UniformOutput', false), ' | ')); %#ok<AGROW>
    c = R.fc_cls(fe); d = R.fc_deg(fe); dr = R.fc_drop(fe); u = unique(c(c > 0));
    txt = strjoin(arrayfun(@(k) sprintf('%s %d (degraded %d, median Eb/N0 drop %.1f dB)', cls_list{k}, ...
        sum(c == k), sum(c == k & d), median(dr(c == k), 'omitnan')), u, 'UniformOutput', false), ', ');
    if isempty(txt), txt = '-'; end
    lines{end+1} = sprintf('    detector class at the first change: %s', txt); %#ok<AGROW>
    FD(end+1) = struct('policy', LBL{pk}, 'by_ebno', byE, 'n_ebno', nE, 'cls', c, 'deg', d, 'drop', dr); %#ok<AGROW>
end
end

function u = cp_upper(k, n)
% One-sided 95% Clopper-Pearson upper bound of a binomial proportion.
if k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

function lines = policy_table_lines(RR, LBL)
lines = {sprintf('%-38s %24s %22s %8s %8s %9s %6s %9s %9s %8s', 'policy', 'recovered % (recoverable)', ...
    'return', 'restored', 'ok', 'goodput', 'T_rec', 'switches', 'false sw', 'PLR ok')};
for pk = 1:numel(RR)
    R = RR{pk};
    m = R.recoverable & R.threat;
    [rm, rl, rh] = boot_cluster(double(R.recovered(m)), ones(1, sum(m)), R.geom(m), 2000, 7);
    [em, el, eh] = boot_cluster(R.ret, ones(size(R.ret)), R.geom, 2000, 8);
    rec = ~isnan(R.t_rec);
    lines{end+1} = sprintf('%-38s %24s %22s %7.1f%% %7.1f%% %9.3f %6s %9.2f %9.3f %7.1f%%', LBL{pk}, ...
        ci_txt(100*rm, 100*rl, 100*rh, '%.1f'), ci_txt(em, el, eh, '%.3f'), 100*mean(R.restored_post), ...
        100*mean(R.ok_post), mean(R.gput_post, 'omitnan'), med(R.t_rec(rec)), mean(R.switches), mean(R.false_sw), ...
        100*mean(R.plr_ok_post)); %#ok<AGROW>
end
end

function s = paired_line(RR, POL, LBL, iDQN)
% Paired differences of the selected DQN, per episode: recovered (recoverable
% episodes) and return, bootstrap over geometries.
Rd = RR{iDQN}; m = Rd.recoverable & Rd.threat;
parts = {};
for p = {'none', 'rule_esc', 'table', 'fixed'}
    k = find(strcmp(POL, p{1})); Rk = RR{k};
    [a, lo, hi] = boot_cluster(double(Rd.recovered(m)) - double(Rk.recovered(m)), ones(1, sum(m)), Rd.geom(m), 2000, 9);
    [b, lo2, hi2] = boot_cluster(Rd.ret - Rk.ret, ones(size(Rd.ret)), Rd.geom, 2000, 10);
    parts{end+1} = sprintf('%s: recovered %+.1f [%+.1f, %+.1f] points, return %+.3f [%+.3f, %+.3f]', LBL{k}, ...
        100*a, 100*lo, 100*hi, b, lo2, hi2); %#ok<AGROW>
end
s = ['Paired, selected DQN minus  ' strjoin(parts, ' | ')];
end

function R = cat_struct(R, Rb)
f = fieldnames(R);
for i = 1:numel(f), R.(f{i}) = [R.(f{i}), Rb.(f{i})]; end
end

function s = ci_txt(m, lo, hi, f)
s = sprintf([f ' [' f ', ' f ']'], m, lo, hi);
end

function s = med(x)
if isempty(x), s = '-'; else, s = sprintf('%.0f', median(x)); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
