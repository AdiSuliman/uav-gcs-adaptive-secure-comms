%% EVALUATE_POLICIES - Decision-layer comparison on the test pools
% Every policy runs the same episodes with the same frame draws (common random
% numbers) on the TEST split of data/policy_pools.mat: geometries never used in
% training or validation. Each episode is one geometry; every test geometry of
% every (cell, Eb/N0) is used, each with two onsets. Episode sets:
%   single    10 threats x 5 severities x 6 Eb/N0, static jammer
%   follower  jamming / reactive_jamming / spoofing / tone_jamming that re-acquire
%             the channel 2-5 cycles after every hop, 5 severities
%   combined  the 14 combined threats at 3 severities on test flights
%   unknown   single threats with the detector output withheld after onset
%             (unknown-threat path: the policy sees only the link measurements)
%   clean     no threat, one 30-cycle episode per flight; every change is a false
%             alarm. KPI 6 (one-sided 95% Clopper-Pearson bound, >= 600 episodes) is
%             computed on data/clean_test_pools.mat, one episode per new geometry,
%             with the false changes per cycle, per hour of flight and the mean time
%             between them (false_change_rate.m)
%   comb      jamming / reactive_jamming on every channel we can use: the jammer is
%             on the new channel at the hop itself and on frequency diversity's
%             second carrier, so only space and link budget can help (assumed: no
%             source jams every channel). Reported apart, not part of the KPI 4
%             pool; recoverable means some configuration without channel_switch and
%             freq_diversity restores the link
%   speed     single threats at nominal severity on dedicated flights at the two ends
%             of the speed envelope (hover and 161 km/h, the fourth pool split),
%             reported apart
%   delay2    the single set with a configuration change arriving two cycles late
%             instead of one (sensitivity to the signalling assumption), reported apart
% Policies: no response (the link that does not react), random, always-on MMSE,
% the best fixed configuration (train pools), expert rule with and without
% escalation, the rule with escalation without the detector (alarm from measured
% degradation only), class -> configuration table (train pools), the DQN of every
% discount factor (the selected one also with escalation), one-step oracle.
% The deployed policy, read by the KPIs, is the one train_dqn.m chose on validation: the
% selected DQN with escalation when it passed its gate, otherwise the rule with
% escalation on its own monitor (rule_sel). The agent must come from these pools'
% detector (check_det_id.m).
% Main metric (proposal KPI 4): RECOVERED episodes -- BER and packet loss back to
% <= 2x the clean link for 5 consecutive cycles -- among the RECOVERABLE ones
% (some configuration restores both in that geometry, link_env.m); the rest is
% the survivability boundary. Also: cycles restored after onset, goodput, cycles
% to recover, switches and false switches, mean reward.
% Intervals: 95% percentile bootstrap over flight geometries (boot_cluster.m;
% episodes of one geometry are resampled together); differences are paired per
% episode. Episode sets, runs and policies: policy_episodes.m, policy_run_set.m,
% policy_setup.m.
%
% Output: results/policy_evaluation.{txt,mat,png}, results/policy_breakdown.png

close all; clc;
fprintf('=== Decision-layer evaluation on the test pools ===\n\n');
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
Q = load('data/trained_dqn.mat', 'agent', 'agents', 'gammas', 'H', 'seed_summary', 'confirm', 'alarm_mode', 'drop_db', ...
    'deployed', 'rule_sel', 'det_id');
check_det_id(PP, Q, 'evaluate_policies');
PP.confirm = Q.confirm; PP.alarm_mode = Q.alarm_mode;           % same monitor for every policy but the rule fallback
if ~isempty(Q.drop_db), PP.drop_db = Q.drop_db; end
K = link_env('tables', PP);
C = decision_config();
tab = policy_table(PP, K);
VAL = 2; TEST = 3; SPEED = 4; T = Q.H.T; NE = 64; REPS = 2;
ENV_MIN = 90; ENV_N = 10;     % envelope predicted on validation: >= ENV_MIN % of >= ENV_N recoverable episodes
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
sets = struct('name', {}, 'spec', {}, 'split', {});
sets(end+1) = struct('name', 'single',   'spec', {policy_episodes(single_cells, nS, 1:nG, REPS, false, false, NE, T, rs)}, 'split', TEST);
sets(end+1) = struct('name', 'follower', 'spec', {policy_episodes(foll, nS, 1:nG, REPS, true, false, NE, T, rs)}, 'split', TEST);
sets(end+1) = struct('name', 'combined', 'spec', {policy_episodes(combo_cells, nS, 1:nG, REPS, false, false, NE, T, rs)}, 'split', TEST);
sets(end+1) = struct('name', 'unknown',  'spec', {policy_episodes(single_cells, nS, 1:nG, 1, false, true, NE, T, rs)}, 'split', TEST);
sets(end+1) = struct('name', 'clean',    'spec', {policy_episodes(clean_cell, nS, 1:nG, 1, false, false, NE, T, rs)}, 'split', TEST);
jam = foll(ismember(PP.scen(foll), {'jamming', 'reactive_jamming'}));
cm = policy_episodes(jam, nS, 1:nG, 1, true, false, NE, T, rs, [0 0]);
for b = 1:numel(cm), cm{b}.comb = true(1, NE); end
sets(end+1) = struct('name', 'comb',     'spec', {cm}, 'split', TEST);
if numel(PP.runs) >= SPEED
    nom_cells = single_cells(PP.sev(single_cells) == C.nominal);
    sets(end+1) = struct('name', 'speed', 'spec', {policy_episodes(nom_cells, nS, 1:K.nR(SPEED), REPS, false, false, NE, T, rs)}, ...
        'split', SPEED);
end
d2 = policy_episodes(single_cells, nS, 1:nG, 1, false, false, NE, T, rs);
for b = 1:numel(d2), d2{b}.delay = 2 * C.switch_delay; end
sets(end+1) = struct('name', 'delay2', 'spec', {d2}, 'split', TEST);
iThreat = 1:3;                                         % sets pooled as "threat sets"

%% 2. Best fixed configuration, chosen on the train pools
vspec = policy_episodes([clean_cell, single_cells], nS, 1:K.nR(1), 1, false, false, NE, T, RandStream('mt19937ar', 'Seed', 11));
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
POL = [{'none', 'random', 'fixed_mmse', 'fixed', 'rule', 'rule_esc', 'blind_esc', 'table'}, ...
       arrayfun(@(g) sprintf('dqn_g%d', g), 1:nGam, 'UniformOutput', false), {'dqn_esc', 'oracle'}];
LBL = [{'no response', 'random', 'always-on MMSE', ['fixed: ' PP.actions{fixed_best}], 'rule', 'rule + escalation', ...
        'no detector + escalation', 'table (train pools)'}, ...
       arrayfun(@(g) sprintf('DQN gamma=%.2f%s', Q.gammas(g), ternary(g == sel, ' (selected)', '')), 1:nGam, ...
       'UniformOutput', false), {'DQN + escalation', 'oracle (one-step)'}];
if strcmp(Q.deployed, 'rule_sel')                    % the rule fallback on its own monitor
    POL = [POL(1:end-1), {'rule_sel'}, POL(end)];
    LBL = [LBL(1:end-1), {sprintf('rule + escalation, own monitor (%s)', Q.rule_sel.alarm)}, LBL(end)];
end
iBase = find(strcmp(POL, sprintf('dqn_g%d', sel)));  % selected DQN alone
iDQN = find(strcmp(POL, Q.deployed));                % deployed policy (train_dqn.m)
LBL{iDQN} = [LBL{iDQN} ' (deployed)'];
col = @(p) find(strcmp(POL, p));

RES = cell(numel(sets), numel(POL));
t0 = tic;
for si = 1:numel(sets)
    for pk = 1:numel(POL)
        [kind, ag, opt] = policy_setup(POL{pk}, Q, sel, fixed_best, fixed_mmse, tab, K.na);
        RES{si, pk} = policy_run_set(kind, PP, K, sets(si).spec, sets(si).split, ag, opt, 30000 + 100*si);
    end
    fprintf('  set %-9s %5d episodes x %d policies (%.1f min)\n', sets(si).name, numel(RES{si, 1}.ret), ...
        numel(POL), toc(t0)/60);
end

%% 3b. Envelope predicted on the VALIDATION split, fixed before the test is read
% The deployed policy runs the validation flights of the same threat sets as the
% test (single, follower, combined). A (threat, severity) is inside the envelope
% when it restores >= ENV_MIN % of its recoverable episodes there (at least ENV_N). The
% commitment is edge_map.m's, on the test flights.
foll_cells = single_cells(K.followable(single_cells));
vsets = {policy_episodes(single_cells, nS, 1:K.nR(VAL), REPS, false, false, NE, T, rs), ...
         policy_episodes(foll_cells, nS, 1:K.nR(VAL), REPS, true, false, NE, T, rs), ...
         policy_episodes(combo_cells, nS, 1:K.nR(VAL), REPS, false, false, NE, T, rs)};
[kind, ag, opt] = policy_setup(POL{iDQN}, Q, sel, fixed_best, fixed_mmse, tab, K.na);
RV = policy_run_set(kind, PP, K, vsets{1}, VAL, ag, opt, 70000);
for vs = 2:3, RV = cat_struct(RV, policy_run_set(kind, PP, K, vsets{vs}, VAL, ag, opt, 70000 + 100*vs)); end
fprintf('  envelope (validation) %d episodes (%.1f min)\n', numel(RV.ret), toc(t0)/60);

%% 4. Report
rep = {};
rep{end+1} = '=== DECISION-LAYER EVALUATION, TEST POOLS ===';
rep{end+1} = sprintf(['Generated: %s | %d-cycle episodes, onset at cycle 3-10 | %d test geometries per (cell, Eb/N0), ' ...
    'never used in training or validation | interferer AoA %s'], datestr(now), T, nG, ...
    ternary(PP.aoa_random, 'random per geometry', 'fixed'));
rep{end+1} = sprintf('Decision period %d ms (decision_config.m): a recovery time of n cycles is n x %d ms.', C.period_ms, C.period_ms);
rep{end+1} = ['recovered = BER and packet loss <= 2x clean for 5 consecutive cycles, among RECOVERABLE episodes ' ...
    '(some configuration restores both in that geometry); restored / ok = cycles after onset with BER / BER and ' ...
    'packet loss restored; false sw = changes on a healthy link, whole episode.'];
rep{end+1} = sprintf(['Selected DQN: gamma %.2f, training false-switch penalty %d; alarm ''%s'', confirmation ' ...
    '%d-of-%d for every monitored policy but the rule fallback. Combined threats (%d) in training and test, new ' ...
    'flights in test. ' ...
    'Intervals: 95%% bootstrap over geometries.'], ...
    Q.seed_summary.selected_gamma, Q.seed_summary.selected_fa_pen, PP.alarm_mode, PP.confirm, numel(PP.combos));
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
show = {'none', 'fixed', 'rule_esc', 'blind_esc', 'table', POL{iBase}, 'dqn_esc', 'oracle'};
hdr = {'no resp.', 'fixed best', 'rule+esc', 'no det.+esc', 'table', 'DQN', 'DQN+esc', 'oracle'};
if strcmp(POL{iDQN}, 'rule_sel'), show{end+1} = 'rule_sel'; hdr{end+1} = 'rule (own)'; end
rep{end+1} = '';
rep{end+1} = 'Recovered episodes among the recoverable, per threat (single + follower + combined sets), %:';
rep{end+1} = sprintf('%-30s %8s %11s%s', 'threat', 'episodes', 'recoverable', sprintf('%11s', hdr{:}));
threats = [PP.singles(2:end), PP.combos];
nV = numel(PP.sev_names);
PT = nan(numel(threats), numel(show)); PTsev = nan(numel(threats), nV, numel(show)); RECsh = nan(numel(threats), 1);
for ti = 1:numel(threats)
    m = strcmp(PP.scen(ALL{1}.scn), threats{ti}) & ALL{1}.threat;
    mr = m & ALL{1}.recoverable;
    RECsh(ti) = mean(ALL{1}.recoverable(m));
    for c = 1:numel(show)
        PT(ti, c) = 100 * mean(ALL{col(show{c})}.recovered(mr));
        for v = 1:nV
            mv = mr & PP.sev(ALL{1}.scn) == v;
            PTsev(ti, v, c) = 100 * mean(ALL{col(show{c})}.recovered(mv));
        end
    end
    rep{end+1} = sprintf('%-30s %8d %10.1f%%%s', threats{ti}, sum(m), 100 * RECsh(ti), sprintf('%11.1f', PT(ti, :))); %#ok<SAGROW>
end
rep{end+1} = '';
iK = find(strcmp(show, POL{iDQN}));                  % deployed policy's column
rep{end+1} = sprintf('Deployed policy (%s) per threat and severity (%s), recovered among recoverable, %%:', ...
    erase(LBL{iDQN}, ' (deployed)'), strjoin(PP.sev_names, ' / '));
for ti = 1:numel(threats)
    rep{end+1} = sprintf('  %-34s %s', threats{ti}, sprintf('%8.1f', squeeze(PTsev(ti, :, iK)))); %#ok<SAGROW>
end
kpi4 = PT(:, iK) >= 90;
rep{end+1} = sprintf(['KPI 4 over every level (deployed policy >= 90%% of the recoverable episodes of every threat): ' ...
    '%d of %d threats | lowest %s %.1f%%'], sum(kpi4), numel(kpi4), threats{find(PT(:, iK) == min(PT(:, iK)), 1)}, min(PT(:, iK)));

% Envelope predicted on validation and KPI 4 inside it (test)
ENV = false(numel(threats), nV); ENVv = nan(numel(threats), nV); PTenv = nan(numel(threats), 1);
for ti = 1:numel(threats)
    mvr = strcmp(PP.scen(RV.scn), threats{ti}) & RV.threat & RV.recoverable;
    for v = 1:nV
        mv = mvr & PP.sev(RV.scn) == v;
        if sum(mv) >= ENV_N
            ENVv(ti, v) = 100 * mean(RV.recovered(mv));
            ENV(ti, v) = ENVv(ti, v) >= ENV_MIN;
        end
    end
    mt = strcmp(PP.scen(ALL{1}.scn), threats{ti}) & ALL{1}.threat & ALL{1}.recoverable & ...
        ismember(PP.sev(ALL{1}.scn), find(ENV(ti, :)));
    if any(mt), PTenv(ti) = 100 * mean(ALL{iDQN}.recovered(mt)); end
end
has = any(ENV, 2);
kpi4_env = PTenv(has) >= 90;
rep{end+1} = '';
rep{end+1} = sprintf(['Envelope predicted on validation (fixed before the test reading: >= %d%% of >= %d recoverable ' ...
    'validation episodes), levels %s inside:'], ENV_MIN, ENV_N, strjoin(PP.sev_names, ' / '));
for ti = 1:numel(threats)
    rep{end+1} = sprintf('  %-34s %s   test inside: %s', threats{ti}, ...
        strjoin(arrayfun(@(v) ternary(ENV(ti, v), 'in', ternary(isnan(ENVv(ti, v)), '-', 'out')), 1:nV, ...
        'UniformOutput', false), ' '), ternary(isnan(PTenv(ti)), 'no level inside', sprintf('%.1f%%', PTenv(ti)))); %#ok<SAGROW>
end
rep{end+1} = sprintf(['KPI 4 inside the envelope: %d of %d threats >= 90%% | envelope covers %d of %d (threat, level) ' ...
    'cells with enough validation episodes'], sum(kpi4_env), numel(kpi4_env), sum(ENV(:)), sum(~isnan(ENVv(:))));

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
    dirn = ~ismember(PP.scen(R1.scn), {'path_loss', 'antenna_fault', 'airframe_shadowing'});
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

% Edge speeds and signalling-delay sensitivity (reported apart from KPI 4)
PS = []; PD = [];
iS = find(strcmp({sets.name}, 'speed'));
if ~isempty(iS)
    Rs = RES{iS, 1}; ms = Rs.recoverable & Rs.threat;
    lo = Rs.speed >= PP.speed_out(1, 1) & Rs.speed <= PP.speed_out(1, 2);
    hi = Rs.speed >= PP.speed_out(2, 1) & Rs.speed <= PP.speed_out(2, 2);
    PS = [arrayfun(@(c) 100 * mean(RES{iS, col(show{c})}.recovered(ms & lo)), 1:numel(show)); ...
          arrayfun(@(c) 100 * mean(RES{iS, col(show{c})}.recovered(ms & hi)), 1:numel(show))];
    rep{end+1} = '';
    rep{end+1} = sprintf(['Recovered among recoverable on dedicated flights at the ends of the speed envelope (single threats, nominal ' ...
        'severity, %d geometries per Eb/N0), %%:'], K.nR(SPEED));
    rep{end+1} = sprintf('%-18s%s', 'speed [km/h]', sprintf('%11s', hdr{:}));
    rep{end+1} = sprintf('%-18s%s', sprintf('%s (%d)', band_txt(PP.speed_out(1, :)), sum(ms & lo)), sprintf('%11.1f', PS(1, :)));
    rep{end+1} = sprintf('%-18s%s', sprintf('%s (%d)', band_txt(PP.speed_out(2, :)), sum(ms & hi)), sprintf('%11.1f', PS(2, :)));
end
iD2 = find(strcmp({sets.name}, 'delay2'));
Rd2 = RES{iD2, 1}; md2 = Rd2.recoverable & Rd2.threat;
R1b = RES{1, 1}; m1 = R1b.recoverable & R1b.threat;
PD = [arrayfun(@(c) 100 * mean(RES{1, col(show{c})}.recovered(m1)), 1:numel(show)); ...
      arrayfun(@(c) 100 * mean(RES{iD2, col(show{c})}.recovered(md2)), 1:numel(show))];
rep{end+1} = '';
rep{end+1} = 'Signalling delay of a configuration change (single set), recovered among recoverable, %:';
rep{end+1} = sprintf('%-18s%s', 'delay [cycles]', sprintf('%11s', hdr{:}));
rep{end+1} = sprintf('%-18s%s', sprintf('%d (deployed)', C.switch_delay), sprintf('%11.1f', PD(1, :)));
rep{end+1} = sprintf('%-18s%s', sprintf('%d', 2 * C.switch_delay), sprintf('%11.1f', PD(2, :)));

% False alarms on the clean link: test pools (nG geometries per Eb/N0)
iC = find(strcmp({sets.name}, 'clean'));
cls_list = [PP.classes, {'unknown'}];
Rc = RES{iC, 1}; above = PP.ebno(Rc.s) >= ebno_thr;
rep{end+1} = '';
rep{end+1} = sprintf(['False alarms on the clean link, test pools (%d geometries per Eb/N0), Eb/N0 >= %g dB ' ...
    '(%d episodes x %d cycles): episodes with >= 1 change, one-sided 95%% Clopper-Pearson upper bound; false ' ...
    'changes per cycle and per hour of flight (95%% upper bound), mean time between them'], nG, ebno_thr, sum(above), T);
[FAR, FD, lines] = far_report(RES(iC, :), POL, LBL, above, T, iDQN, PP.ebno, cls_list, C.period_ms);
rep = [rep, lines];

% False alarms over many independent geometries: one episode per geometry (KPI 6)
FAR_t = FAR; FD_t = FD; n_geom = 0; RW = {};
if isfile('data/clean_test_pools.mat')
    Ct = load('data/clean_test_pools.mat', 'CT'); CT = Ct.CT; clear Ct
    n_geom = CT.n_geom;
    PPw = PP;
    PPw.pools(:, :, :, TEST) = {[]};
    PPw.pools(clean_cell, :, :, TEST) = reshape(CT.pools(1, :, :), [1 nS nA]);
    PPw.runs{TEST} = CT.runs;
    PPw.speed{TEST} = CT.speed;
    Kw = link_env('tables', PPw);
    [ss, rr] = ndgrid(1:nS, 1:n_geom); ss = ss(:)'; rr = rr(:)';
    n = numel(ss); nb = ceil(n / NE); pad = nb * NE - n;
    k_ = mod(0:n + pad - 1, n) + 1; ss = ss(k_); rr = rr(k_);                 % cyclic padding of the last batch
    specs = cell(1, nb);
    for b = 1:nb
        i = (b-1)*NE + (1:NE);
        specs{b} = struct('scn', clean_cell * ones(1, NE), 's', ss(i), 'onset', 3 * ones(1, NE), 'follow', false(1, NE), ...
            'fdelay', 2 * ones(1, NE), 'unk', false(1, NE), 'T', T, 'r', rr(i));
    end
    RW = cell(1, numel(POL));
    for pk = 1:numel(POL)
        [kind, ag, opt] = policy_setup(POL{pk}, Q, sel, fixed_best, fixed_mmse, tab, K.na);
        R = policy_run_set(kind, PPw, Kw, specs, TEST, ag, opt, 40000);
        f = fieldnames(R);
        for j = 1:numel(f), R.(f{j}) = R.(f{j})(:, 1:n); end        % drop the padding
        RW{pk} = R;
    end
    aboveW = PP.ebno(RW{1}.s) >= ebno_thr;
    rep{end+1} = '';
    rep{end+1} = sprintf(['False alarms on the clean link, %d new geometries per Eb/N0 (data/clean_test_pools.mat), ' ...
        'one episode per geometry, Eb/N0 >= %g dB (%d independent episodes x %d cycles) -> KPI 6'], n_geom, ...
        ebno_thr, sum(aboveW), T);
    [FAR, FD, lines] = far_report(RW, POL, LBL, aboveW, T, iDQN, PP.ebno, cls_list, C.period_ms);
    rep = [rep, lines];
end

% Final configuration of the deployed policy per threat (single set)
rep{end+1} = '';
rep{end+1} = 'Configuration at the end of the episode, deployed policy (single set): most frequent two per threat';
Rd = RES{1, iDQN};
top_cfg = struct('threat', {}, 'action', {}, 'share', {});      % most frequent final configuration (threat_gallery.m)
for ti = 1:numel(PP.singles) - 1
    cf = Rd.cfg_final(strcmp(PP.scen(Rd.scn), threats{ti}));
    if isempty(cf), continue; end
    [u, ~, j] = unique(cf); cnt = accumarray(j(:), 1); [cnt, o] = sort(cnt, 'descend'); u = u(o);
    top_cfg(end+1) = struct('threat', threats{ti}, 'action', PP.actions{u(1)}, 'share', cnt(1) / numel(cf)); %#ok<SAGROW>
    txt = strjoin(arrayfun(@(i) sprintf('%s %.0f%%', PP.actions{u(i)}, 100 * cnt(i) / numel(cf)), ...
        1:min(2, numel(u)), 'UniformOutput', false), ', ');
    rep{end+1} = sprintf('  %-22s %s', threats{ti}, txt); %#ok<SAGROW>
end

fid = fopen('results/policy_evaluation.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
set_names = {sets.name};
KP = struct('per_threat', PT, 'per_threat_sev', PTsev, 'threats', {threats}, 'recoverable_share', RECsh, ...
    'envelope', ENV, 'envelope_val', ENVv, 'per_threat_env', PTenv, 'kpi4_env_met', kpi4_env, 'env_rule', [ENV_MIN ENV_N], ...
    'kpi4_met', kpi4, 'per_ebno', PE, 'ebno', PP.ebno, 'per_aoa', PA, 'aoa_bins', bins_aoa, 'per_speed', PV, ...
    'speed_bins', bins_v, 'show', {show}, 'show_lbl', {hdr}, 'far', FAR, 'far_diag', FD, 'far_testpools', FAR_t, ...
    'far_diag_testpools', FD_t, 'far_geoms', n_geom, 'cls_list', {cls_list}, 'ebno_thr', ebno_thr, ...
    'selected_gamma', Q.seed_summary.selected_gamma, 'confirm', PP.confirm, 'alarm_mode', PP.alarm_mode, ...
    'per_speed_out', PS, 'speed_out', PP.speed_out, 'per_delay', PD, 'sev_names', {PP.sev_names});
save('results/policy_evaluation.mat', 'RES', 'RW', 'POL', 'LBL', 'set_names', 'fixed_best', 'tab', 'iDQN', 'KP', ...
    'iThreat', 'ALL', 'top_cfg');

%% 5. Figures
key = unique({'none', 'fixed', 'rule_esc', 'blind_esc', 'table', 'dqn_esc', POL{iDQN}, 'oracle'}, 'stable');
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
sgtitle('Decision layer on the test pools');
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
function [FAR, FD, lines] = far_report(RR, POL, LBL, above, T, iDQN, ebno, cls_list, period_ms)
% False-alarm counts per policy (episodes with >= 1 change, Clopper-Pearson
% bound; false changes per cycle and per hour, false_change_rate.m), and for the
% deployed policy and rule + escalation the false-alarm episodes per Eb/N0 and the
% trigger at the first change.
lines = {};
FAR = struct('policy', {}, 'k', {}, 'n', {}, 'p', {}, 'upper', {}, 'per_cycle', {}, 'rate', {});
for pk = 1:numel(POL)
    if any(strcmp(POL{pk}, {'oracle', 'random'})), continue; end
    R = RR{pk}; kf = sum(R.switches(above) > 0); n = sum(above);
    F = false_change_rate(R.switches(above), T, R.geom(above) + 1e6 * R.split(above), period_ms);
    FAR(end+1) = struct('policy', LBL{pk}, 'k', kf, 'n', n, 'p', kf / n, 'upper', cp_upper(kf, n), ...
        'per_cycle', F.rate, 'rate', F); %#ok<AGROW>
    lines{end+1} = sprintf(['  %-40s %4d / %4d = %6.2f%%   upper %6.2f%%   per cycle %.4f%% (<= %.4f%%), %.0f per hour ' ...
        '(<= %.0f), one every %.3g s'], LBL{pk}, kf, n, 100 * kf / n, 100 * FAR(end).upper, 100 * F.rate, 100 * F.hi, ...
        F.per_hour, F.per_hour_hi, F.mtbf_s); %#ok<AGROW>
end
nS = numel(ebno);
FD = struct('policy', {}, 'by_ebno', {}, 'n_ebno', {}, 'cls', {}, 'deg', {}, 'drop', {});
for pk = unique([iDQN, find(strcmp(POL, 'rule_esc'))], 'stable')
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
% Paired differences of the deployed policy, per episode: recovered (recoverable
% episodes) and return, bootstrap over geometries.
Rd = RR{iDQN}; m = Rd.recoverable & Rd.threat;
parts = {};
for p = setdiff({'none', 'rule_esc', 'blind_esc', 'table', 'fixed', 'dqn_esc'}, POL(iDQN), 'stable')
    k = find(strcmp(POL, p{1})); Rk = RR{k};
    [a, lo, hi] = boot_cluster(double(Rd.recovered(m)) - double(Rk.recovered(m)), ones(1, sum(m)), Rd.geom(m), 2000, 9);
    [b, lo2, hi2] = boot_cluster(Rd.ret - Rk.ret, ones(size(Rd.ret)), Rd.geom, 2000, 10);
    parts{end+1} = sprintf('%s: recovered %+.1f [%+.1f, %+.1f] points, return %+.3f [%+.3f, %+.3f]', LBL{k}, ...
        100*a, 100*lo, 100*hi, b, lo2, hi2); %#ok<AGROW>
end
s = ['Paired, ' erase(LBL{iDQN}, ' (deployed)') ' (deployed) minus  ' strjoin(parts, ' | ')];
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

function s = band_txt(b)
% Speed band [km/h] as text, one value when the band is a single speed.
if b(1) == b(2), s = sprintf('%g', b(1)); else, s = sprintf('%g-%g', b); end
end
