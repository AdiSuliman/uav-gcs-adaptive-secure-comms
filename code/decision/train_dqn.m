%% C2 - TRAIN DQN: sequential decision layer on measured frame pools
% Double DQN (van Hasselt et al., AAAI 2016) with experience replay and a target
% network (Mnih et al., Nature 2015) on link_env.m: 30-cycle episodes inside one
% seeded flight geometry, the threat (a single threat at any severity, or a combination)
% starts at a random cycle, a follower jammer re-acquires the channel 0-5 cycles
% after each hop (the intelligent jammer of Liu et al., 2018; 0 = their comb
% jammer, C.fdelay), and the agent sees what the
% receiver measures over the last cycles (policy_state.m): detector class
% probabilities, unknown flag, estimated BER, packet loss, SINR, IoT, spatial
% measurements, its own configuration, the time since its last change and the
% confirmed alarm. The shield of policy_mask.m (confirmed alarm, hold after a
% change) applies in training exactly as in deployment, and the Double DQN target
% maximizes over the configurations allowed in the next state.
% Data: the TRAIN split of data/policy_pools.mat for learning; the VALIDATION split
% (geometries never used in training) for checkpoints and selection; the test
% split is kept for evaluate_policies.m. Recovery is read two ways on every episode: KPI 4's
% 'recovered' (BER and packet loss restored for 5 consecutive cycles) and 'held' (restored
% from then to the end, but one follower re-acquisition, rollout_policy.m), the edge map's
% committed reading (edge_map.m REC, PROT); checkpoints, runs, the gate and the fallback
% are chosen on held, both are printed.
%
% Grid: monitor (alarm definition and m-of-n confirmation, C.monitors, policy_monitor.m;
% Barajas et al.) x threshold of the drop alarm in the form choose_drop_threshold.m chose on
% validation (drop_alarm: the monitors' 'class_drop' reads as that form), each monitor at its
% own threshold from the whole monitor's false-alarm bound (choose_drop_threshold.m MONP) and
% the steps C.drop_steps around it (the median window: dB, above the moving-away floor it
% records; the CUSUM: one grid step per step), the sweeping jammer's own confirmation as
% choose_drop_threshold.m adopted it (PP.confirm_sweep), and its degradation test when it chose one
% (PP.deg_mode, PP.ber_q; every policy, the rule fallback's own monitor included)
% x false-switch penalty of the TRAINING reward (CFG.fa_penalty_grid) x
% CFG.dqn_gammas x CFG.dqn_seeds. Every run keeps the checkpoint with the best held
% recovery on its own validation episodes (scored with the escalation). All runs are then
% compared on every (threat cell, Eb/N0, geometry) of the validation split, each with and
% without the escalation (policy_decide.m 'dqn_esc', 'dqn'): held and recovered among the
% recoverable episodes, per threat (severities pooled, as KPI 4) and pooled, and false
% alarms on the independent clean validation geometries (data/clean_val_pools.mat, one
% 30-cycle episode per geometry) at the Eb/N0 of KPI 6: from the KPI 1 threshold up
% (results/eval_detector_metrics.mat; every Eb/N0 when it has none).
% The rule's settings, on validation before the grid (rule + escalation at the reference
% monitor, C.confirm at its own drop threshold), one coordinate at a time, each against the
% setting in force: the nulling threshold on the predicted MMSE gain (mmse_predict.m) among
% mu + 3 sigma and mu + 3 sigma + 2 dB of the clean validation frames (Kazim et al. 2026,
% eq. 1.3: a threshold from interference-free samples, as q_thr), 3, 6 (the earlier
% constant) and 9 dB, with the quiet-slot branch on and off; the proposal dwell, consecutive
% ('run') or m of n by group ('group', policy_decide.m); the unknown-threat flag's
% retention (0.95, 0.99 of the validation windows, unk_threshold.m) and the classes it
% overrides ('all', 'nonhostile', policy_monitor.m); the escalation on a drop alarm read as
% none (esc_drop). The chosen settings run the baselines of every monitor and the grid.
% The rule's answer to the class noise_burst (rule_nb, burst_candidates.m), after the nulling
% threshold that decides its branch: the answer when the interferer is not separable, then
% when it is, each among its candidates, uncoded on pools decoded with the D78 erasure rules;
% then the core rule's (core_nb, scored as rule_core). These steps pick by the held
% recovery of the recoverable episodes whose threat holds a noise burst (nb_pick, ten at
% least, else the ties' chain alone), among the candidates within the false-alarm bound and
% half a point of the best pooled held recovery; within one point the pooled recovered, the
% return, then the cheaper. The class mapping's coded answer is reported, not a candidate
% (docs/noise_burst_protocol.md).
% After the grid, coordinate steps at the selected monitor, drop threshold and penalty, the
% same seeds: the discount factor 0 (the bandit), running and switching costs x1, and, when
% the unknown-threat flag's settings moved from the default, the default for the agent; the
% escalation on a drop alarm is scored on the selected agent both ways.
% Selection: among the candidates (run, with or without escalation) whose one-sided 95%
% false-alarm bound is <= 5% (KPI 6 as worded), the highest held recovery of the weakest
% threat; within one point of it, the best pooled held recovery (within half a point), then
% the pooled recovered (KPI 4), then the return.
% Gate: pooled held recovery >= rule + escalation with the same monitor and settings, and
% the false-alarm bound. The DQN is deployed when it passed the gate and recovers at least
% as much as the best rule setting within the bound (choose_deployed.m); otherwise rule +
% escalation with its own monitor and drop threshold from the grid (rule_sel): the best held
% recovery among the settings whose false-alarm bound is <= 5%. When no setting meets the
% bound either, the policy with the lowest bound is deployed and fa_bound_met is false: the
% edge map then commits no point; the same without clean validation flights (the bound
% not measured). The best run of every discount factor at the selected monitor, drop
% threshold, penalty and settings is kept as an ablation. Reward-weight sensitivity:
% proposal mitigation 2.
%
% With "lb_select": true in profile.json (lb_options.m) the link-budget completion of the DQN's
% action (lb_complete.m) is scored on the selected agent alone, off against on, on the validation
% split's single, follower, combined and unknown episodes and its clean flights, and adopted or
% not by lb_adopt.m (one comparison, nothing tuned); the switch is stored in dec (dec.lb_complete),
% the readings in lb. Without the field none of it runs.
%
% Finished runs (every training run and the reward-sensitivity retrains) are kept in
% data/run_cache/C2 when profile.json says "run_cache": true or CFG.run_cache is true
% (run_cache.m): keyed by the code, the input files, the run's settings and seed, so a C2
% started again after a stop reads them instead of training them and its results are those of
% an uninterrupted C2. Off by default: nothing is kept.
%
% Output: data/trained_dqn.mat (also deployed, rule_sel, fa_bound_met, the pools' det_id and
% created, dec: the deployed DQN's decision-time settings, decision_settings.m, and maha_thr),
% results/dqn_training.txt, results/dqn_training_curves.png

close all; clc;
fprintf('=== C2: Train DQN ===\n\n');
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
K = link_env('tables', PP);
PP.pools(:, :, :, 3:end) = {[]};         % C2 reads the train and validation splits only (memory)
nA = numel(PP.actions);
[nS, cont] = policy_state_size(nA, numel(PP.classes));
SPLIT_TRAIN = 1; SPLIT_VAL = 2;
CD = decision_config();

%% 1. Hyperparameters
H = struct('gamma', 0.9, 'NE', 64, 'T', 30, 'episodes', 50000, 'buffer', 200000, 'warmup', 8000, ...
    'batch', 128, 'updates', 4, 'lr', 5e-4, 'lr_end', 5e-5, 'clip', 10, 'target_every', 500, ...
    'eps_end', 0.05, 'eps_frac', 0.6, 'huber', 1, 'p_unknown', 0.10, 'p_follow', 0.5, 'n_eval', 4, ...
    'hidden', [256 256]);
N_SEEDS = 3; GAMMAS = 0.5;
% monitor: alarm definition, m/n confirmation (k-out-of-n detection: Norouzi 2006; Barajas et al. 2026), selected on
% validation; 4/5 and 5/5 trade a later alarm for fewer false ones
ALARMS = CD.monitors;
DROP_STEPS = CD.drop_steps;              % drop alarm: around each monitor's validation threshold (selected on validation)
% Training reward variants, one entry each: false-switch penalty, scale of the
% running costs (goodput, spectrum, power, combining) and of the switching cost
FA_PEN = [80 120 160]; COST_SCALE = [0.5 0.5 0.5]; SW_SCALE = [1 1 1];
SENS_SCALES = [0.5 2];                   % reward-weight sensitivity: cost terms x scale
COORD = true;                            % coordinate steps after the grid (gamma 0, costs x1, the unknown flag's default)
if exist('CFG', 'var') && isstruct(CFG)
    if isfield(CFG, 'dqn_seeds'), N_SEEDS = CFG.dqn_seeds; end
    if isfield(CFG, 'dqn_gammas'), GAMMAS = CFG.dqn_gammas; end
    if isfield(CFG, 'fa_penalty_grid'), FA_PEN = CFG.fa_penalty_grid; end
    if isfield(CFG, 'cost_scale_grid'), COST_SCALE = CFG.cost_scale_grid; end
    if isfield(CFG, 'switch_scale_grid'), SW_SCALE = CFG.switch_scale_grid; end
    if isfield(CFG, 'monitors'), ALARMS = CFG.monitors; end
    if isfield(CFG, 'dqn_episodes'), H.episodes = CFG.dqn_episodes; end
    if isfield(CFG, 'drop_steps'), DROP_STEPS = CFG.drop_steps; end
    if isfield(CFG, 'dqn_coordinate'), COORD = CFG.dqn_coordinate; end
end
VAL_REPS = 2;                            % validation: every (cell, Eb/N0, geometry) of the split, twice
cfgc = []; if exist('CFG', 'var'), cfgc = CFG; end
RC = struct('dir', run_cache('dir', run_cache('on', cfgc), 'C2'), 'id', '');   % finished runs kept on disk (run_cache.m)
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    N_SEEDS = 1; GAMMAS = 0.5; FA_PEN = 80; COST_SCALE = 1; SW_SCALE = 1; ALARMS = {'class_drop 4/5'}; SENS_SCALES = 2; VAL_REPS = 1;
    DROP_STEPS = [0 2]; H.episodes = 1280; H.buffer = 20000; H.warmup = 2000; H.n_eval = 1;
end
SEEDS = 42 + (0:N_SEEDS-1);
FA_BOUND = 0.05;                         % one-sided 95% bound of the clean-link false alarms (KPI 6)
DROP_DB = [];                            % drop alarm threshold of 'class_drop'
DROP_FLOOR = 0;                          % moving away over the monitor's window (choose_drop_threshold.m)
DROP_MODE = 'class_drop';                % form of the drop alarm (choose_drop_threshold.m, on validation)
DROP_FROM = 'train pools';               % where the median window's threshold was chosen
THC = []; MONP = [];                     % the CUSUM's grid; every monitor's threshold on the whole monitor
if isfile('data/drop_threshold.mat')
    Dd = load('data/drop_threshold.mat'); DROP_DB = Dd.drop_db;
    if isfield(Dd, 'floor_db'), DROP_FLOOR = Dd.floor_db; end
    if isfield(Dd, 'drop_from'), DROP_FROM = Dd.drop_from; end
    if isfield(Dd, 'drop_alarm') && strcmp(Dd.drop_alarm, 'class_cusum')
        DROP_MODE = Dd.drop_alarm; DROP_DB = Dd.cusum_db; THC = Dd.THC;
    end
    if isfield(Dd, 'MONP'), MONP = Dd.MONP; end
    if isfield(Dd, 'confirm_sweep'), PP.confirm_sweep = Dd.confirm_sweep; end   % the sweeper's own confirmation
    if isfield(Dd, 'deg_mode'), PP.deg_mode = Dd.deg_mode; PP.ber_q = Dd.ber_q; end   % the degradation test chosen at C1d
    if isfield(Dd, 'DEG') && isfield(Dd.DEG, 'forced')       % a forced test (deg_force.m): the smoke only
        deg_force('smoke', Dd.DEG.forced, exist('SMOKE', 'var') && SMOKE, 'train_dqn');
        PP.deg_forced = Dd.DEG.forced;
    end
    clear Dd
end
if ~isempty(DROP_DB), PP.drop_db = DROP_DB; end
CV = [];                                 % independent clean validation geometries
if isfile('data/clean_val_pools.mat')
    Cv = load('data/clean_val_pools.mat', 'CT'); CV = Cv.CT; clear Cv
    check_det_id(PP, CV, 'train_dqn', 'data/clean_val_pools.mat');
end
EBNO_THR = PP.ebno(1);                   % false alarms from the KPI 1 threshold up (KPI 6), fixed on validation
if isfile('results/eval_detector_metrics.mat')
    Md = load('results/eval_detector_metrics.mat', 'metrics');
    if isfield(Md.metrics, 'kpi1_threshold_db') && isfinite(Md.metrics.kpi1_threshold_db)
        EBNO_THR = Md.metrics.kpi1_threshold_db;
    end
    clear Md
end

%% 2. State normalization from random-policy rollouts
rs = RandStream('mt19937ar', 'Seed', 7);
S_all = [];
for b = 1:20
    spec = dqn_episode_spec(H, PP, K, rs, SPLIT_TRAIN);
    [E, obs] = link_env('reset', PP, K, spec, SPLIT_TRAIN, rs);
    mem = policy_monitor('init', H.NE, nA);
    for t = 1:H.T
        [mem, M] = policy_monitor('update', mem, obs, PP, E.cfg);
        S_all = [S_all, policy_state(mem, E.cfg, M.confirmed, nA)]; %#ok<AGROW>
        a = randi(rs, nA, 1, H.NE);
        mem = policy_monitor('change', mem, a ~= E.cfg);
        [E, ~, obs] = link_env('step', E, PP, K, a);
    end
end
norm_in = struct('mu', zeros(nS, 1), 'sd', ones(nS, 1));
norm_in.mu(cont) = mean(S_all(cont, :), 2);
norm_in.sd(cont) = max(std(S_all(cont, :), 0, 2), 1e-3);

%% 3. Validation episodes, the rule's settings and the baselines
val_spec = full_val_spec(PP, K, H, SPLIT_VAL, VAL_REPS, RandStream('mt19937ar', 'Seed', 99));
if ~isempty(RC.dir)                      % the identity of every run's inputs: code, files, hyperparameters
    RC.id = run_cache('key', {run_cache('inputs', {'data/policy_pools.mat', 'data/drop_threshold.mat', ...
        'data/clean_val_pools.mat', 'results/eval_detector_metrics.mat'}), H, norm_in, VAL_REPS, EBNO_THR, val_spec, ...
        exist('SMOKE', 'var') && SMOKE});
    fprintf('Finished runs kept in %s (inputs %s): a run finished before a restart is read, not trained\n', RC.dir, RC.id);
end
val_thr = threat_of(PP, val_spec);                   % threat name per validation episode (severities pooled)
DU = drop_unit(DROP_MODE);               % unit of the drop thresholds
tab = policy_table(PP, K);
ENT = struct('alarm', {}, 'drop', {});   % (monitor, drop threshold) of the grid
for ai = 1:numel(ALARMS)
    for dd = drops_of(ALARMS{ai}, MONP, DROP_MODE, DROP_DB, THC, DROP_STEPS, DROP_FLOOR)
        ENT(end+1) = struct('alarm', ALARMS{ai}, 'drop', dd); %#ok<SAGROW>
    end
end
ev = @(kind, PPc, ag, opt) eval_policy(kind, PPc, K, val_spec, ag, opt, CV, H, EBNO_THR, val_thr);
% 3a. The rule's settings, one coordinate at a time, at the reference monitor
mt = PP.ebno >= EBNO_THR; mp = [];                   % the predicted MMSE gain of the clean validation frames
for s = find(mt)
    P = PP.pools{K.clean, s, K.na, SPLIT_VAL};
    if isfield(P, 'mmse_pred') && ~isempty(P.mmse_pred), mp = [mp; double(P.mmse_pred(:))]; end %#ok<AGROW>
end
mp = mp(isfinite(mp));
U0 = 0.95; if isfield(PP, 'unk_retain') && ~isempty(PP.unk_retain), U0 = PP.unk_retain; end
S0 = struct('rule_mmse_db', CD.rule_mmse_db, 'rule_slot', true, 'rule_dwell', 'run', 'unk_mode', 'all', ...
    'unk_retain', U0, 'maha_thr', PP.maha_thr, 'esc_drop', false);
BC = burst_candidates(fec_rx_of(PP));               % the noise-burst answers, uncoded on D78 pools
S0.rule_nb = BC.start; S0.core_nb = BC.core_start;
TH = [3 CD.rule_mmse_db 9]; th_txt = {'3 dB', sprintf('%g dB (the earlier constant)', CD.rule_mmse_db), '9 dB'};
if numel(mp) >= 30
    mu_s = [mean(mp), std(mp)];
    TH = [mu_s(1) + 3 * mu_s(2), mu_s(1) + 3 * mu_s(2) + 2, TH];
    th_txt = [{sprintf('mu + 3 sigma = %.2f dB', TH(1)), sprintf('mu + 3 sigma + 2 = %.2f dB', TH(2))}, th_txt];
else
    mu_s = [NaN NaN];
end
STEPS = struct('name', {}, 'var', {});
v = {}; for i = 1:numel(TH), for so = [true false], v{end+1} = struct('rule_mmse_db', TH(i), 'rule_slot', so); end, end %#ok<SAGROW>
STEPS(end+1) = struct('name', 'nulling threshold and quiet slot', 'var', {v});
NBS = {'noise-burst answer, not separable', 'noise-burst answer, separable', 'noise-burst answer, core rule'};
v = cellfun(@(a) @(S) with_nb(S, 1, a), BC.ns, 'UniformOutput', false);
STEPS(end+1) = struct('name', NBS{1}, 'var', {v});
v = cellfun(@(a) @(S) with_nb(S, 2, a), BC.sep, 'UniformOutput', false);
STEPS(end+1) = struct('name', NBS{2}, 'var', {v});
PK = struct('name', NBS, 'rank', {@(S) find(strcmp(BC.ns, S.rule_nb{1})), @(S) find(strcmp(BC.sep, S.rule_nb{2})), ...
    @(S) find(strcmp(BC.core, S.core_nb))});      % steps nb_pick picks, by their candidates' cost order
STEPS(end+1) = struct('name', 'proposal dwell', 'var', {{struct('rule_dwell', 'run'), struct('rule_dwell', 'group')}});
v = {};
for md = {'all', 'nonhostile'}
    for rt = [0.95 0.99]
        if isfield(PP, 'maha_val') && ~isempty(PP.maha_val)
            v{end+1} = struct('unk_mode', md{1}, 'unk_retain', rt, 'maha_thr', unk_threshold(PP.maha_val, rt)); %#ok<SAGROW>
        elseif rt == U0
            v{end+1} = struct('unk_mode', md{1}, 'unk_retain', rt, 'maha_thr', PP.maha_thr); %#ok<SAGROW>
        end
    end
end
STEPS(end+1) = struct('name', 'unknown-threat flag: classes overridden, retention', 'var', {v});
STEPS(end+1) = struct('name', 'escalation on a drop alarm read as none', 'var', {{struct('esc_drop', false), struct('esc_drop', true)}});
iref = find(strcmp({ENT.alarm}, sprintf('class_drop %d/%d', CD.confirm)), 1);   % the reference monitor at its own threshold
if isempty(iref), iref = 1; end
jr = find(strcmp({ENT.alarm}, ENT(iref).alarm)); iref = jr(ceil(numel(jr) / 2));
PPr = with_entry(PP, ENT(iref), DROP_MODE);
[Ssel, SROWS] = choose_settings(S0, STEPS, @(S) ev('rule_esc', decision_settings(PPr, S), [], struct()), FA_BOUND, PK);
CSTEP = struct('name', NBS{3}, 'var', {cellfun(@(a) struct('core_nb', a), BC.core, 'UniformOutput', false)});
[Ssel, CROWS] = choose_settings(Ssel, CSTEP, @(S) ev('rule_esc', decision_settings(PPr, S), [], struct('core', true)), ...
    FA_BOUND, PK);
Sref = Ssel; Sref.rule_nb = {};                     % the class mapping's coded answer: reported only
xref = ev('rule_esc', decision_settings(PPr, Sref), [], struct());
fprintf('=== Rule settings at %s, drop %.1f %s: %s\n', mon_txt(ENT(iref).alarm, DROP_MODE), ENT(iref).drop, DU, set_txt(Ssel));
% 3b. Baselines of every monitor and drop threshold at the chosen settings
base = struct('alarm', {}, 'drop', {}, 'rule', {}, 'tab', {});
for e = 1:numel(ENT)
    PPc = decision_settings(with_entry(PP, ENT(e), DROP_MODE), Ssel);
    base(e).alarm = ENT(e).alarm; base(e).drop = ENT(e).drop;
    base(e).rule = ev('rule_esc', PPc, [], struct()); base(e).tab = ev('table', PPc, [], tab);
    fprintf(['=== Monitor %s, drop %.1f %s: rule+esc held %.1f%%, recovered %.1f%%, return %.3f, FA %s | table held ' ...
        '%.1f%%, recovered %.1f%%, return %.3f\n'], mon_txt(ENT(e).alarm, DROP_MODE), ENT(e).drop, DU, 100*base(e).rule.held, ...
        100*base(e).rule.rec, base(e).rule.ret, pct_txt(base(e).rule.fa_w), 100*base(e).tab.held, 100*base(e).tab.rec, base(e).tab.ret);
end

%% 4. Training: monitor x drop threshold x false-switch penalty x discount factor x seeds
runs = struct('alarm', {}, 'drop', {}, 'fa_pen', {}, 'cost_scale', {}, 'sw_scale', {}, 'gamma', {}, 'seed', {}, 'S', {}, ...
    'step', {}, 'agent', {}, 'curve', {}, 'loss', {}, 'best_ep', {}, 'esc', {}, 'noesc', {});
for e = 1:numel(ENT)
    PPc = decision_settings(with_entry(PP, ENT(e), DROP_MODE), Ssel);
    for fi = 1:numel(FA_PEN)
        for g = GAMMAS
            for k = 1:N_SEEDS
                runs(end+1) = cached(RC, {'train_one', ENT(e), FA_PEN(fi), COST_SCALE(fi), SW_SCALE(fi), g, SEEDS(k), ...
                    Ssel, 'grid', DROP_MODE}, PPc, PP, @() train_one(H, PPc, K, norm_in, nS, ENT(e), FA_PEN(fi), ...
                    COST_SCALE(fi), SW_SCALE(fi), g, SEEDS(k), Ssel, 'grid', ev, DROP_MODE, DU, SPLIT_TRAIN, SPLIT_VAL), ...
                    @(r) run_lines(r, DROP_MODE, DU, RC.dir)); %#ok<SAGROW>
            end
        end
    end
end
[cand, best, sel_rule] = select_run(runs, FA_BOUND);
% Coordinate steps at the selected monitor, drop threshold and penalty
CO = {};
if COORD
    r0 = runs(cand(best).run); e0 = struct('alarm', r0.alarm, 'drop', r0.drop);
    PPs = decision_settings(with_entry(PP, e0, DROP_MODE), r0.S);
    if ~any(GAMMAS == 0), CO(end+1, :) = {'discount factor 0 (the bandit)', 0, r0.cost_scale, r0.sw_scale, r0.S}; end
    if r0.cost_scale ~= 1 || r0.sw_scale ~= 1, CO(end+1, :) = {'running and switching costs x1', r0.gamma, 1, 1, r0.S}; end
    if ~strcmp(r0.S.unk_mode, S0.unk_mode) || r0.S.unk_retain ~= S0.unk_retain
        Sd = r0.S; Sd.unk_mode = S0.unk_mode; Sd.unk_retain = S0.unk_retain; Sd.maha_thr = S0.maha_thr;
        CO(end+1, :) = {'the unknown-threat flag at its default', r0.gamma, r0.cost_scale, r0.sw_scale, Sd};
    end
    for c = 1:size(CO, 1)
        PPc = decision_settings(PPs, CO{c, 5});
        for k = 1:N_SEEDS
            runs(end+1) = cached(RC, {'train_one', e0, r0.fa_pen, CO{c, 3}, CO{c, 4}, CO{c, 2}, SEEDS(k), CO{c, 5}, ...
                CO{c, 1}, DROP_MODE}, PPc, PP, @() train_one(H, PPc, K, norm_in, nS, e0, r0.fa_pen, CO{c, 3}, CO{c, 4}, ...
                CO{c, 2}, SEEDS(k), CO{c, 5}, CO{c, 1}, ev, DROP_MODE, DU, SPLIT_TRAIN, SPLIT_VAL), ...
                @(r) run_lines(r, DROP_MODE, DU, RC.dir)); %#ok<SAGROW>
        end
    end
    % the escalation on a drop alarm, both ways on the agent selected so far
    [cand, best] = select_run(runs, FA_BOUND);
    r1 = cand(best).run; Sx = runs(r1).S; Sx.esc_drop = ~Sx.esc_drop;
    PPx = decision_settings(with_entry(PP, struct('alarm', runs(r1).alarm, 'drop', runs(r1).drop), DROP_MODE), Sx);
    x = runs(r1); x.S = Sx; x.step = sprintf('escalation on a drop alarm %s (the same agent)', ternary(Sx.esc_drop, 'on', 'off'));
    x.esc = ev('dqn_esc', PPx, x.agent, struct()); x.noesc = [];
    runs(end+1) = x;
    CO(end+1, :) = {x.step, x.gamma, x.cost_scale, x.sw_scale, Sx};
    [cand, best, sel_rule] = select_run(runs, FA_BOUND);
end
B = cand(best); rb = runs(B.run);
agent = rb.agent; sel_kind = B.kind; Sdep = rb.S;
gamma_sel = rb.gamma; fa_pen_sel = rb.fa_pen; alarm_sel = rb.alarm; drop_sel = rb.drop;
cs_sel = rb.cost_scale; ss_sel = rb.sw_scale;
GAM = unique([GAMMAS, [runs.gamma]]);
same = @(r) r.fa_pen == fa_pen_sel & r.cost_scale == cs_sel & r.sw_scale == ss_sel & strcmp(r.alarm, alarm_sel) ...
    & isequaln(r.drop, drop_sel) & isequal(r.S, Sdep);
agents = cell(1, numel(GAM));                        % best run per discount factor at the chosen monitor, drop, penalty, settings
for gi = 1:numel(GAM)
    m = find([runs.gamma] == GAM(gi) & arrayfun(same, runs));
    if isempty(m), m = find([runs.gamma] == GAM(gi)); end
    [cm, jj] = select_run(runs(m), FA_BOUND);
    agents{gi} = runs(m(cm(jj).run)).agent;
end
agents{find(GAM == gamma_sel, 1)} = agent;

%% 4b. Link-budget completion on the selected agent, off against on (lb_complete.m, lb_adopt.m)
% Only with "lb_select": true in profile.json (lb_options.m, or CFG.lb_select): judged on the agent
% selected above alone, on the validation split, nothing tuned, and stored with it (dec.lb_complete);
% without it nothing here runs and no switch is stored.
LBo = lb_options(); LBon = false; LBforced = false; LBR = []; LBlines = {};
if exist('CFG', 'var') && isstruct(CFG) && isfield(CFG, 'lb_select'), LBo.on = CFG.lb_select; end
if exist('CFG', 'var') && isstruct(CFG) && isfield(CFG, 'lb_force'), LBo.force = CFG.lb_force; end
if LBo.force && ~(LBo.on && exist('SMOKE', 'var') && SMOKE)
    error('train_dqn:lb_force', 'train_dqn: lb_force needs lb_select and the smoke (a forced link-budget completion is no adoption)');
end
if LBo.on
    PPl = decision_settings(with_entry(PP, struct('alarm', alarm_sel, 'drop', drop_sel), DROP_MODE), Sdep);
    LBX = lb_readings(sel_kind, PPl, K, agent, CV, H, EBNO_THR, VAL_REPS);
    [LBok, LBmsg] = lb_selfcheck();
    [LBon, LBR, LBlines] = lb_adopt(LBX, FA_BOUND, LBok);
    if ~LBok, LBlines{end+1} = ['  static or parity check failed: ' strjoin(LBmsg, '; ')]; end
    if LBo.force
        LBlines{end+1} = sprintf(['  FORCED for the smoke (lb_force): the completion is on, not an adoption; the rule above ' ...
            'reads %s'], ternary(LBon, 'on', 'off'));
        LBon = true; LBforced = true;
    end
    if LBon                                           % the gate and the deployment choice read the agent as it is deployed
        xl = ev(sel_kind, decision_settings(PPl, struct('lb_complete', true)), agent, struct());
        up = NaN; if ~isnan(xl.fa_w), up = cp_upper(round(xl.fa_w * xl.n_w), xl.n_w); end
        [B.rec, B.held, B.kmin, B.ret] = deal(xl.rec, xl.held, xl.kmin, xl.ret);
        [B.fa_w, B.n_w, B.sw_w, B.fa_ok] = deal(xl.fa_w, xl.n_w, xl.sw_w, isnan(up) || up <= FA_BOUND);
        LBlines{end+1} = sprintf(['  the gate and choose_deployed read the DQN with the completion on: held %.1f%%, recovered ' ...
            '%.1f%%, false alarms %s'], 100 * xl.held, 100 * xl.rec, fa_txt(xl.fa_w, xl.n_w));
    end
    fprintf('%s\n', LBlines{:});
end

%% 5. Gate, deployed policy and report
eb = find(strcmp({base.alarm}, alarm_sel) & arrayfun(@(b) isequaln(b.drop, drop_sel), base), 1);
bsel = base(eb).rule;
if ~isequal(Sdep, Ssel)                              % the rule at the same monitor and settings as the DQN
    bsel = ev('rule_esc', decision_settings(with_entry(PP, ENT(eb), DROP_MODE), Sdep), [], struct());
end
fa_up = @(fa, n) cp_upper(round(fa * n), n);         % one-sided 95% bound (NaN without clean geometries)
gate = B.held >= bsel.held && B.fa_ok;
rr = arrayfun(@(b) b.rule.held, base); rb_up = arrayfun(@(b) fa_up(b.rule.fa_w, b.rule.n_w), base);
[deployed, fa_bound_met, ir] = choose_deployed(gate, fa_up(B.fa_w, B.n_w), rr, rb_up, FA_BOUND, B.held, sel_kind);
rok = any(rb_up <= FA_BOUND | isnan(rb_up));
rule_sel = struct('alarm', base(ir).alarm, 'drop', base(ir).drop, 'rec', base(ir).rule.rec, 'held', base(ir).rule.held, ...
    'fa_w', base(ir).rule.fa_w, 'n_w', base(ir).rule.n_w, 'fa_upper', rb_up(ir), 'alarm_mode', '', 'confirm', [], 'drop_db', DROP_DB);
[rule_sel.alarm_mode, rule_sel.confirm] = monitor(base(ir).alarm, DROP_MODE);
if ~isnan(base(ir).drop), rule_sel.drop_db = base(ir).drop; end
for f = fieldnames(Ssel)', rule_sel.(f{1}) = Ssel.(f{1}); end
rule_sel.confirm_sweep = []; if isfield(PP, 'confirm_sweep'), rule_sel.confirm_sweep = PP.confirm_sweep; end
if isfield(PP, 'deg_mode'), rule_sel.deg_mode = PP.deg_mode; rule_sel.ber_q = PP.ber_q; end
FD = false_change_rate(B.sw_w, H.T, 1:numel(B.sw_w), CD.period_ms);
FR = false_change_rate(base(ir).rule.sw_w, H.T, 1:numel(base(ir).rule.sw_w), CD.period_ms);
rep = {};
rep{end+1} = '=== DQN TRAINING ===';
rep{end+1} = sprintf(['Generated: %s | Double DQN + shield, state history %d cycles, hidden %s, replay %d, target every ' ...
    '%d updates, lr %.0e -> %.0e, %d episodes x %d cycles | monitor %s, each at its drop thresholds %s x penalty %s x ' ...
    'gamma %s x %d seeds'], datestr(now), CD.hist, mat2str(H.hidden), H.buffer, H.target_every, H.lr, H.lr_end, ...
    H.episodes, H.T, strjoin(ALARMS, '/'), DU, mat2str(FA_PEN), mat2str(GAMMAS), N_SEEDS);
rep{end+1} = 'False-switch penalty and cost scales: training reward only; validation and test use the standard reward.';
rep{end+1} = sprintf(['Every run scored with and without the escalation; checkpoints by held recovery with it. Follower ' ...
    'jammers re-acquire the channel %d-%d cycles after a hop (training and validation).'], CD.fdelay(1), CD.fdelay(2));
rep{end+1} = sprintf(['Validation: %d episodes, every (threat cell, Eb/N0, geometry) of the VALIDATION split (geometries ' ...
    'never used in training) %d times: single threats at five severities, combined threats at three, clean link. Recovered = ' ...
    'BER and packet loss <= 2x clean for 5 consecutive cycles (KPI 4); held = recovered and restored from then to the end, ' ...
    'but one follower re-acquisition (the edge map''s REC); among recoverable threat episodes; weakest threat = lowest ' ...
    'per-threat held recovery (severities pooled). FA: false-alarm episodes on %s independent clean validation geometries ' ...
    '(data/clean_val_pools.mat, one 30-cycle episode each) at Eb/N0 >= %g dB (KPI 6).'], ...
    numel(val_thr), VAL_REPS, n_txt(CV, PP, EBNO_THR), EBNO_THR);
if ~isempty(DROP_DB) && strcmp(DROP_MODE, 'class_cusum')
    rep{end+1} = sprintf(['''class_drop'' read as ''class_cusum'' (chosen on validation, data/drop_threshold.mat): drop ' ...
        'alarm (and the path_loss class) when the window-limited CUSUM of the Eb/N0 drop reaches the run''s threshold; ' ...
        'its threshold alone on validation %.1f dB^2'], DROP_DB);
elseif ~isempty(DROP_DB)
    rep{end+1} = sprintf(['''class_drop'': drop alarm (and the path_loss class) after an Eb/N0 drop >= the run''s ' ...
        'threshold; the median window''s threshold alone %.1f dB (%s), moving-away floor %.2f dB (data/drop_threshold.mat)'], ...
        DROP_DB, DROP_FROM, DROP_FLOOR);
end
rep{end+1} = sprintf(['Each monitor''s drop thresholds (its own on the whole monitor''s false-alarm bound, choose_drop_threshold.m, ' ...
    'and the steps %s around it): %s'], mat2str(DROP_STEPS), strjoin(arrayfun(@(a) sprintf('%s %s', a{1}, ...
    mat2str([ENT(strcmp({ENT.alarm}, a{1})).drop], 4)), ALARMS, 'UniformOutput', false), ' | '));
rep{end+1} = sprintf('The sweeping jammer''s own confirmation: %s (choose_drop_threshold.m, on validation)', ...
    ternary(isfield(PP, 'confirm_sweep') && ~isempty(PP.confirm_sweep), sprintf('%d of the last %d cycles', ...
    PP.confirm_sweep), 'not adopted'));
if isfield(PP, 'deg_mode')
    rep{end+1} = sprintf('The degradation test: %s (choose_drop_threshold.m, on validation, docs/deg_fix_protocol.md)', PP.deg_mode);
end
if isfield(PP, 'deg_forced')
    rep{end+1} = sprintf('  FORCED for the smoke (deg_force %s), not an adoption (docs/p1r_protocol.md)', PP.deg_forced);
end
rep{end+1} = '';
rep{end+1} = sprintf(['Rule settings on validation, rule + escalation at %s, drop %.1f %s, one coordinate at a time (the ' ...
    'selection rule below, the setting in force first); the predicted MMSE gain of %d clean validation frames: mean %.2f, ' ...
    'std %.2f dB; thresholds %s:'], mon_txt(ENT(iref).alarm, DROP_MODE), ENT(iref).drop, DU, numel(mp), mu_s, strjoin(th_txt, ', '));
rep = [rep, SROWS];
rep{end+1} = sprintf('  core rule (rule_core, the same monitor and settings), %s:', NBS{3});
rep = [rep, CROWS];
rep{end+1} = sprintf('  %-52s %s', 'reference, not a candidate:', row_txt(Sref, xref));
rep{end+1} = sprintf(['  noise-burst candidates (%s pools): not separable %s; separable %s; core %s. Pools decoded with ' ...
    'the D78 erasure rules keep the coded answers out (docs/noise_burst_protocol.md)'], upper(BC.mode), ...
    strjoin(BC.ns, ', '), strjoin(BC.sep, ', '), strjoin(BC.core, ', '));
rep{end+1} = sprintf('Chosen: %s', set_txt(Ssel));
rep{end+1} = '';
rep{end+1} = sprintf('%-62s %4s %9s %10s %28s %9s %9s %12s %12s', 'run', 'esc', 'held', 'recovered', 'weakest threat (held)', ...
    'restored', 'return', 'FA indep.', 'switches/ep');
for k = 1:numel(runs)
    for q = {'esc', 'noesc'}
        x = runs(k).(q{1});
        if isempty(x), continue; end
        rep{end+1} = sprintf('%-62s %4s %8.1f%% %9.1f%% %28s %8.1f%% %9.3f %12s %12.2f   (checkpoint %d%s)', ...
            sprintf('%s drop %.1f pen %d costs x%.1f sw x%.1f g=%.2f seed %d', runs(k).alarm, runs(k).drop, runs(k).fa_pen, ...
            runs(k).cost_scale, runs(k).sw_scale, runs(k).gamma, runs(k).seed), ternary(strcmp(q{1}, 'esc'), 'yes', 'no'), ...
            100*x.held, 100*x.rec, sprintf('%s %.1f%%', x.kmin_thr, 100*x.kmin), 100*x.restored, x.ret, fa_txt(x.fa_w, x.n_w), ...
            x.switches, runs(k).best_ep, ternary(strcmp(runs(k).step, 'grid'), '', ['; ' runs(k).step])); %#ok<SAGROW>
    end
end
rep{end+1} = '';
rep{end+1} = 'Baselines on the same validation episodes (the chosen rule settings):';
for e = 1:numel(base)
    rep{end+1} = sprintf(['  %-15s drop %.1f %s  rule + escalation: held %.1f%%, recovered %.1f%%, return %.3f, FA %s | table: ' ...
        'held %.1f%%, recovered %.1f%%, return %.3f, FA %s'], base(e).alarm, base(e).drop, DU, 100*base(e).rule.held, ...
        100*base(e).rule.rec, base(e).rule.ret, pct_txt(base(e).rule.fa_w), 100*base(e).tab.held, 100*base(e).tab.rec, ...
        base(e).tab.ret, pct_txt(base(e).tab.fa_w)); %#ok<SAGROW>
end
if ~isempty(CO)
    rep{end+1} = sprintf('Coordinate steps at the selected monitor, drop threshold and penalty (%d seeds each): %s', N_SEEDS, ...
        strjoin(CO(:, 1)', '; '));
end
rep{end+1} = sprintf(['Selected: monitor %s, drop %.1f %s, false-switch penalty %d, running costs x%.1f, switching ' ...
    'x%.1f, gamma %.2f, seed %d, %s; %s (%s). Gate (held recovery >= rule + escalation with the same monitor and ' ...
    'settings, %.1f%%; false-alarm bound <= %.0f%%): %s'], mon_txt(alarm_sel, DROP_MODE), drop_sel, DU, fa_pen_sel, cs_sel, ...
    ss_sel, gamma_sel, rb.seed, ternary(strcmp(sel_kind, 'dqn_esc'), 'with the escalation', 'without the escalation'), ...
    set_txt(Sdep), sel_rule, 100*bsel.held, 100*FA_BOUND, ternary(gate, 'PASS', 'FAIL'));
rep{end+1} = sprintf(['  the DQN held %.1f%% (recovered %.1f%%) against the best rule setting within the bound, %s drop %.1f %s, ' ...
    'held %.1f%% (recovered %.1f%%)'], 100*B.held, 100*B.rec, base(ir).alarm, base(ir).drop, DU, 100*base(ir).rule.held, ...
    100*base(ir).rule.rec);
rep{end+1} = sprintf(['Fallback, rule + escalation with its own monitor (the best held recovery among the settings whose ' ...
    'false-alarm bound is <= %.0f%%%s): monitor %s, drop %.1f %s, held %.1f%%, recovered %.1f%%, FA %s, bound %s'], ...
    100*FA_BOUND, ternary(rok, '', '; none is: the lowest bound'), mon_txt(rule_sel.alarm, DROP_MODE), rule_sel.drop, DU, ...
    100*rule_sel.held, 100*rule_sel.rec, fa_txt(rule_sel.fa_w, rule_sel.n_w), pct_txt(rule_sel.fa_upper));
rep{end+1} = sprintf('Deployed: %s | false-alarm bound met on validation: %s%s', dep_txt(deployed), ...
    ternary(fa_bound_met, 'YES', 'NO'), ternary(fa_bound_met, '', [ternary(isempty(CV), ...
    ' (not measured: no clean validation flights)', '') ' -- the edge map commits no point']));
rep{end+1} = sprintf(['False changes on the clean link (validation, Eb/N0 >= %g dB, %d ms per cycle): DQN %s | ' ...
    'rule fallback %s'], EBNO_THR, CD.period_ms, rate_txt(FD), rate_txt(FR));
if ~isempty(LBR), rep = [rep, {''}, LBlines]; end
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/dqn_training.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
if ~gate, warning('train_dqn:gate', 'DQN validation gate FAILED -- see results/dqn_training.txt'); end

ES = [runs.esc];
seed_summary = struct('alarms', {{runs.alarm}}, 'drops', [runs.drop], 'fa_pens', [runs.fa_pen], 'cost_scales', [runs.cost_scale], ...
    'sw_scales', [runs.sw_scale], 'gammas', [runs.gamma], 'seeds', [runs.seed], 'steps', {{runs.step}}, ...
    'val_recovered', [ES.rec], 'val_held', [ES.held], 'val_weakest', [ES.kmin], 'val_weakest_threat', {{ES.kmin_thr}}, ...
    'val_return', [ES.ret], 'fa_indep', [ES.fa_w], 'n_indep', [ES.n_w], 'best_ep', [runs.best_ep], 'selected_alarm', alarm_sel, ...
    'selected_drop', drop_sel, 'selected_fa_pen', fa_pen_sel, 'selected_cost_scale', cs_sel, 'selected_sw_scale', ss_sel, ...
    'selected_gamma', gamma_sel, 'selected_seed', rb.seed, 'selected_kind', sel_kind, 'selection_rule', sel_rule, ...
    'gate_pass', gate, 'rule_recovered', bsel.rec, 'rule_held', bsel.held, 'rule_return', bsel.ret, ...
    'table_return', base(eb).tab.ret, 'deployed', deployed, 'fa_bound_met', fa_bound_met, 'fa_ebno_thr', EBNO_THR, ...
    'fa_rate_dqn', FD, 'fa_rate_rule', FR, 'dqn_held', B.held, 'dqn_recovered', B.rec, ...
    'nb_reference', rmfield(xref, 'sw_w'), 'nb_candidates', BC);
H.gamma = gamma_sel; H.fa_pen = fa_pen_sel; H.cost_scale = cs_sel; H.sw_scale = ss_sel;
action_names = PP.actions;
gammas = GAM;
[alarm_mode, confirm] = monitor(alarm_sel, DROP_MODE);
drop_db = drop_sel; if isnan(drop_db), drop_db = DROP_DB; end
dec = Sdep; dec.alarm_mode = alarm_mode; dec.confirm = confirm; dec.drop_db = drop_db;
dec.confirm_sweep = []; if isfield(PP, 'confirm_sweep'), dec.confirm_sweep = PP.confirm_sweep; end
if isfield(PP, 'deg_mode'), dec.deg_mode = PP.deg_mode; dec.ber_q = PP.ber_q; end
if isfield(PP, 'deg_forced'), dec.deg_forced = PP.deg_forced; end   % the smoke's forced test, in the stamp
if ~isempty(LBR), dec.lb_complete = LBon; if LBforced, dec.lb_forced = true; end, end   % step 4b, only with lb_select
agent = dqn_dense(agent);                          % matrix form for deployment
for gi = find(~cellfun(@isempty, agents)), agents{gi} = dqn_dense(agents{gi}); end
det_id = PP.det_id; pools_created = PP.created;    % the pools (and their detector) the agent learned on
maha_thr = dec.maha_thr;                           % the unknown-threat threshold it ran with (decision_settings.m)
save('data/trained_dqn.mat', 'agent', 'agents', 'gammas', 'confirm', 'alarm_mode', 'drop_db', 'H', ...
    'norm_in', 'seed_summary', 'action_names', 'tab', 'deployed', 'rule_sel', 'fa_bound_met', 'det_id', ...
    'pools_created', 'maha_thr', 'dec', '-v7.3');
if ~isempty(LBR)                                   % the completion's readings, beside the switch in dec
    lb = struct('on', LBon, 'forced', LBforced, 'readings', LBR); save('data/trained_dqn.mat', 'lb', '-append');
end
fprintf('Saved data/trained_dqn.mat\n');

fig = figure('Position', [100 100 1000 430], 'Color', 'w');
subplot(1, 2, 1); hold on; grid on;
cols = lines(numel(FA_PEN)); hl = gobjects(1, numel(FA_PEN));
same_mon = @(r) strcmp(r.alarm, alarm_sel) & isequaln(r.drop, drop_sel) & strcmp(r.step, 'grid');
for k = find(arrayfun(same_mon, runs))
    ci = find(FA_PEN == runs(k).fa_pen, 1);
    c = runs(k).curve;
    hl(ci) = plot(c(:, 1), 100 * c(:, 3), 'Color', cols(ci, :), 'LineWidth', 1.1);
    plot(c(:, 1), 100 * c(:, 2), ':', 'Color', cols(ci, :), 'HandleVisibility', 'off');
    [~, m] = max(c(:, 3));
    plot(c(m, 1), 100 * c(m, 3), 'o', 'Color', cols(ci, :), 'MarkerSize', 5, 'HandleVisibility', 'off');
end
hr = yline(100 * bsel.held, 'k--');
xlabel('Episode'); ylabel('Held (solid) and recovered (dotted), validation checkpoints [%]');
title({'Learning curves (o = kept checkpoint)', ['monitor ' alarm_sel]}, 'Interpreter', 'none');
ok = isgraphics(hl);
legend([hl(ok) hr], [arrayfun(@(p) sprintf('false-switch penalty %d', p), FA_PEN(ok), 'UniformOutput', false), ...
    {'rule + escalation, held (validation)'}], 'Location', 'southoutside', 'NumColumns', 2);
subplot(1, 2, 2); plot(movmean(rb.loss, 200)); grid on;
xlabel('Update'); ylabel('Huber loss (moving mean 200)');
title(sprintf('Q-loss, selected run (penalty %d, \\gamma %.2f, seed %d)', fa_pen_sel, gamma_sel, rb.seed));
saveas(fig, 'results/dqn_training_curves.png'); close(fig);

%% 6. Reward-weight sensitivity (proposal mitigation 2)
% The DQN is retrained with every cost term (goodput, spectrum, power,
% processing, switching, false switch) scaled by SENS_SCALES at the selected
% alarm, penalty, gamma and settings; DQN (as deployed, with or without the escalation),
% rule + escalation and table are compared on the validation episodes. The conclusion holds
% when the DQN stays ahead of both baselines in held recovery, and in recovery, at every scale.
PPc = decision_settings(with_entry(PP, struct('alarm', alarm_sel, 'drop', drop_sel), DROP_MODE), Sdep);
sens = struct('scale', {}, 'dqn_rec', {}, 'rule_rec', {}, 'tab_rec', {}, 'dqn_held', {}, 'rule_held', {}, 'tab_held', {}, ...
    'dqn_ret', {}, 'dqn_gput', {});
for f = [1, SENS_SCALES]
    Kf = K; Kf.cost = f * K.cost; Kf.SW = f * K.SW; Kf.FA = f * K.FA;
    if f == 1
        ag = rb.agent;
    else
        fprintf('--- reward sensitivity: costs x %.1f ---\n', f);
        Hs = H; Hs.gamma = gamma_sel;
        Kft = Kf; Kft.FA = f * fa_pen_sel; Kft.cost = f * cs_sel * K.cost; Kft.SW = f * ss_sel * K.SW;
        ag = cached(RC, {'sens', f, Hs, fa_pen_sel, cs_sel, ss_sel, alarm_sel, drop_sel, Sdep, rb.seed, DROP_MODE}, PPc, PP, ...
            @() dqn_train_run(Hs, PPc, Kft, Kf, norm_in, rb.seed, nS, SPLIT_TRAIN, SPLIT_VAL), ...
            @(a) fprintf('    retrained agent read from %s (finished before a restart)\n', RC.dir));
    end
    Vd = dqn_eval_batches(sel_kind, PPc, Kf, val_spec, ag, struct(), 5000, SPLIT_VAL);
    Vr = dqn_eval_batches('rule_esc', PPc, Kf, val_spec, [], struct(), 5000, SPLIT_VAL);
    Vt = dqn_eval_batches('table', PPc, Kf, val_spec, [], policy_table(PP, Kf), 5000, SPLIT_VAL);
    sens(end+1) = struct('scale', f, 'dqn_rec', dqn_recovered(Vd), 'rule_rec', dqn_recovered(Vr), 'tab_rec', dqn_recovered(Vt), ...
        'dqn_held', dqn_held(Vd), 'rule_held', dqn_held(Vr), 'tab_held', dqn_held(Vt), ...
        'dqn_ret', mean(Vd.ret), 'dqn_gput', mean(Vd.gput_post, 'omitnan')); %#ok<SAGROW>
end
rs2 = {'', sprintf('Reward-weight sensitivity (validation; every cost term scaled, DQN retrained per scale, seed %d):', ...
    rb.seed), sprintf('%-8s %28s %28s %10s %10s', 'scale', 'held DQN/rule/table', 'recovered DQN/rule/table', 'DQN ret', 'DQN gput')};
for i = 1:numel(sens)
    x = sens(i);
    rs2{end+1} = sprintf('%-8s %28s %28s %10.3f %10.3f', sprintf('x %.1f', x.scale), ...
        sprintf('%.1f/%.1f/%.1f%%', 100*x.dqn_held, 100*x.rule_held, 100*x.tab_held), ...
        sprintf('%.1f/%.1f/%.1f%%', 100*x.dqn_rec, 100*x.rule_rec, 100*x.tab_rec), x.dqn_ret, x.dqn_gput); %#ok<SAGROW>
end
holds = all([sens.dqn_held] >= [sens.rule_held] & [sens.dqn_held] >= [sens.tab_held]);
holds_rec = all([sens.dqn_rec] >= [sens.rule_rec] & [sens.dqn_rec] >= [sens.tab_rec]);
rs2{end+1} = sprintf(['DQN held recovery at least that of rule + escalation and table at every scale: %s (recovered, ' ...
    'KPI 4''s reading: %s)'], ternary(holds, 'YES', 'NO'), ternary(holds_rec, 'YES', 'NO'));
fid = fopen('results/dqn_training.txt', 'a'); fprintf(fid, '%s\n', rs2{:}); fclose(fid);
fprintf('%s\n', rs2{:});
save('data/trained_dqn.mat', 'sens', '-append');
fprintf('=== C2 Complete ===\n');

%% ===================== Local functions =====================
function specs = full_val_spec(PP, K, H, split, reps, rs)
% Every (cell, Eb/N0, geometry the cell flies: link_env.m K.geo) of the split `reps` times,
% in batches of H.NE (the last one shorter): onset, follower jammer and follower delay drawn
% per episode.
C = decision_config();
cells = find(~cellfun(@isempty, PP.pools(:, 1, K.na, split))');
[c, s, r] = flight_triples(cells, K.geo(cells, split), 1:numel(PP.ebno));
c = repmat(c, 1, reps); s = repmat(s, 1, reps); r = repmat(r, 1, reps);
n = numel(c); nb = ceil(n / H.NE);
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*H.NE + 1:min(b*H.NE, n); m = numel(i);
    specs{b} = struct('scn', c(i), 's', s(i), 'r', r(i), 'onset', randi(rs, [3 10], 1, m), ...
        'follow', K.followable(c(i)) & rand(rs, 1, m) < H.p_follow, 'fdelay', randi(rs, C.fdelay, 1, m), ...
        'unk', false(1, m), 'T', H.T);
end
end

function t = threat_of(PP, specs)
% Threat of every validation episode, severities pooled (KPI 4 counts per threat).
t = PP.scen(cell2mat(cellfun(@(sp) sp.scn, specs, 'UniformOutput', false)));
end

function [kmin, name] = weakest_threat(V, thr, field)
% Lowest recovery (field 'recovered' or 'held') among the recoverable episodes of one threat
% (threats with at least 10 recoverable validation episodes).
m = V.recoverable & V.threat;
u = unique(thr(m));
rec = nan(1, numel(u));
for i = 1:numel(u)
    mi = m & strcmp(thr, u{i});
    if sum(mi) >= 10, rec(i) = mean(V.(field)(mi)); end
end
[kmin, j] = min(rec);
name = '-'; if ~isempty(j), name = u{j}; end
end

function x = eval_policy(kind, PPc, K, specs, ag, opt, CV, H, ebno_thr, thr)
% One policy on the validation episodes (common random numbers: every policy the same frame
% draws) and the clean validation geometries: KPI 4's recovered, held, the weakest threat's
% held (and recovered), return, restored cycles, switches, false alarms; nb_held over nb_n, the
% held recovery of the recoverable episodes whose threat holds a noise burst.
V = dqn_eval_batches(kind, PPc, K, specs, ag, opt, 5000, 2);
[kh, kt] = weakest_threat(V, thr, 'held'); [kr, krt] = weakest_threat(V, thr, 'recovered');
x = struct('rec', dqn_recovered(V), 'held', dqn_held(V), 'kmin', kh, 'kmin_thr', kt, 'kmin_rec', kr, 'kmin_rec_thr', krt, ...
    'ret', mean(V.ret), 'restored', mean(V.restored_post), 'switches', mean(V.switches), 'fa_w', NaN, 'n_w', 0, 'sw_w', []);
nb = V.recoverable & V.threat & contains(thr, 'noise_burst');
x.nb_n = sum(nb); x.nb_held = NaN; if x.nb_n > 0, x.nb_held = mean(V.held(nb)); end
[x.fa_w, x.n_w, x.sw_w] = eval_clean_wide(kind, PPc, CV, ag, opt, H, ebno_thr);
end

function X = lb_readings(kind, PPc, K, agent, CV, H, ebno_thr, reps)
% lb_adopt.m's paired readings of the agent without and with the link-budget completion (opt.monitor,
% policy_decide.m): the validation split's single, follower, combined and unknown episodes (the sets of
% evaluate_policies.m, new onsets from lb_seeds) and the clean validation flights (eval_clean_wide). The
% frame draws of a pair are the same (rollout_policy.m seed).
S = lb_seeds(); nS = numel(PPc.ebno); VAL = 2;
rs = RandStream('mt19937ar', 'Seed', S.specs);
sg = find(ismember(PPc.scen, PPc.singles) & ~strcmp(PPc.scen, 'none'));
cb = find(ismember(PPc.scen, PPc.combos));
fl = sg(K.followable(sg));
G = @(c) K.geo(c, VAL);
spec = {policy_episodes(sg, nS, G(sg), reps, false, false, H.NE, H.T, rs), ...
    policy_episodes(fl, nS, G(fl), reps, true, false, H.NE, H.T, rs), ...
    policy_episodes(cb, nS, G(cb), reps, false, false, H.NE, H.T, rs), ...
    policy_episodes(sg, nS, G(sg), 1, false, true, H.NE, H.T, rs)};
nm = {'single', 'follower', 'combined', 'unknown'};
off = struct('monitor', struct('lb_complete', false)); on = struct('monitor', struct('lb_complete', true));
X = struct('sets', struct('name', {}, 'x_off', {}, 'x_on', {}, 'cl', {}, 'fam', {}), 'clean', []);
for k = 1:numel(spec)
    if isempty(spec{k})                                   % no such episodes: the set is not read
        X.sets(end+1) = struct('name', nm{k}, 'x_off', [], 'x_on', [], 'cl', [], 'fam', false(1, 0)); continue
    end
    r0 = policy_run_set(kind, PPc, K, spec{k}, VAL, agent, off, S.frames + 100 * k);
    r1 = policy_run_set(kind, PPc, K, spec{k}, VAL, agent, on, S.frames + 100 * k);
    m = r0.recoverable & r0.threat;
    fam = cellfun(@(s) any(strcmp(strsplit(s, '+'), 'path_loss')), PPc.scen(r0.scn));
    X.sets(end+1) = struct('name', nm{k}, 'x_off', double(r0.recovered(m)), 'x_on', double(r1.recovered(m)), ...
        'cl', r0.geom(m), 'fam', fam(m));
end
[~, ~, sw0] = eval_clean_wide(kind, PPc, CV, agent, off, H, ebno_thr);
[~, ~, sw1] = eval_clean_wide(kind, PPc, CV, agent, on, H, ebno_thr);
X.clean = struct('sw_off', sw0, 'sw_on', sw1);
end

function [fa, n, sw] = eval_clean_wide(kind, PP, CT, agent, opt, H, ebno_thr)
% False-alarm episodes on the independent clean geometries of CT at the Eb/N0 from
% ebno_thr up: one 30-cycle clean episode per geometry and Eb/N0 (clean_wide_specs.m), as
% in evaluate_policies.m; sw: changes in every episode.
fa = NaN; n = 0; sw = [];
if isempty(CT), return; end
[PPw, Kw] = clean_world(PP, CT);
[specs, n] = clean_wide_specs(PP, CT, ebno_thr, H.T);
for b = 1:numel(specs)
    Rb = rollout_policy(kind, PPw, Kw, specs{b}, 2, agent, opt, 41000 + b);
    sw = [sw, Rb.switches]; %#ok<AGROW>
end
sw = sw(1:n);
fa = mean(sw > 0);
end

function r = train_one(H, PPc, K, norm_in, nS, en, fp, cs, ss, g, seed, S, step, ev, drop_mode, du, sp_tr, sp_val)
% One training run at monitor and drop en, penalty fp, cost and switch scales cs, ss, discount
% g, settings S (applied in PPc), scored with and without the escalation.
fprintf(['--- monitor %s, drop %.1f %s, false-switch penalty %d, costs x%.1f, switch x%.1f, gamma %.2f, seed %d%s ---\n'], ...
    mon_txt(en.alarm, drop_mode), en.drop, du, fp, cs, ss, g, seed, ternary(strcmp(step, 'grid'), '', [' (' step ')']));
Kt = K; Kt.FA = fp; Kt.cost = cs * K.cost; Kt.SW = ss * K.SW;   % training reward only
Hg = H; Hg.gamma = g;
[ag, curve, lossc, best_ep] = dqn_train_run(Hg, PPc, Kt, K, norm_in, seed, nS, sp_tr, sp_val);
xe = ev('dqn_esc', PPc, ag, struct()); xn = ev('dqn', PPc, ag, struct());
fprintf(['    checkpoint %d | validation with / without the escalation: held %.1f / %.1f%% | recovered %.1f / %.1f%% | ' ...
    'weakest threat %s %.1f%% | return %.3f / %.3f | FA %s / %s\n'], best_ep, 100*xe.held, 100*xn.held, 100*xe.rec, ...
    100*xn.rec, xe.kmin_thr, 100*xe.kmin, xe.ret, xn.ret, fa_txt(xe.fa_w, xe.n_w), fa_txt(xn.fa_w, xn.n_w));
r = struct('alarm', en.alarm, 'drop', en.drop, 'fa_pen', fp, 'cost_scale', cs, 'sw_scale', ss, 'gamma', g, 'seed', seed, ...
    'S', S, 'step', step, 'agent', ag, 'curve', curve, 'loss', lossc, 'best_ep', best_ep, 'esc', xe, 'noesc', xn);
end

function r = cached(RC, parts, PPc, PP, f, onhit)
% A run through the run cache (run_cache.m): keyed by the stage's inputs (RC.id), the run's
% settings and seed (parts) and the pools' settings it runs with (every field of PPc but the
% pools that PP lacks or holds otherwise). Started again, a finished run is read, not trained,
% and onhit prints its lines.
if isempty(RC.dir), r = f(); return; end
key = run_cache('key', [{RC.id}, parts, {pool_settings(PPc, PP)}]);
[r, hit] = run_cache('run', RC.dir, key, f);
if hit, onhit(r); end
end

function d = pool_settings(PPc, PP)
% The fields of PPc, the pools excepted, that PP lacks or holds with another value.
d = struct();
for fn = setdiff(fieldnames(PPc)', {'pools'})
    if ~isfield(PP, fn{1}) || ~isequaln(PPc.(fn{1}), PP.(fn{1})), d.(fn{1}) = PPc.(fn{1}); end
end
end

function run_lines(r, drop_mode, du, dirn)
% train_one's lines for a run read from the run cache.
fprintf(['--- monitor %s, drop %.1f %s, false-switch penalty %d, costs x%.1f, switch x%.1f, gamma %.2f, seed %d%s ' ...
    '(read from %s: finished before a restart) ---\n'], mon_txt(r.alarm, drop_mode), r.drop, du, r.fa_pen, r.cost_scale, ...
    r.sw_scale, r.gamma, r.seed, ternary(strcmp(r.step, 'grid'), '', [' (' r.step ')']), dirn);
xe = r.esc; xn = r.noesc;
fprintf(['    checkpoint %d | validation with / without the escalation: held %.1f / %.1f%% | recovered %.1f / %.1f%% | ' ...
    'weakest threat %s %.1f%% | return %.3f / %.3f | FA %s / %s\n'], r.best_ep, 100*xe.held, 100*xn.held, 100*xe.rec, ...
    100*xn.rec, xe.kmin_thr, 100*xe.kmin, xe.ret, xn.ret, fa_txt(xe.fa_w, xe.n_w), fa_txt(xn.fa_w, xn.n_w));
end

function [cand, best, why] = select_run(runs, bound)
% The selection rule over every (run, with or without the escalation): among those whose
% one-sided 95% false-alarm bound is <= bound (not measured: in), the highest held recovery
% of the weakest threat; within one point of it the best pooled held recovery (within half a
% point), then the pooled recovered (KPI 4), then the return; when none is within the bound,
% the three with the lowest bound. cand(k): run, kind, and the readings; best indexes cand.
cand = struct('run', {}, 'kind', {}, 'rec', {}, 'held', {}, 'kmin', {}, 'ret', {}, 'fa_w', {}, 'n_w', {}, 'sw_w', {}, ...
    'fa_ok', {});
for k = 1:numel(runs)
    for q = {'esc', 'dqn_esc'; 'noesc', 'dqn'}'
        x = runs(k).(q{1});
        if isempty(x), continue; end
        up = NaN; if ~isnan(x.fa_w), up = cp_upper(round(x.fa_w * x.n_w), x.n_w); end
        cand(end+1) = struct('run', k, 'kind', q{2}, 'rec', x.rec, 'held', x.held, 'kmin', x.kmin, 'ret', x.ret, ...
            'fa_w', x.fa_w, 'n_w', x.n_w, 'sw_w', x.sw_w, 'fa_ok', isnan(up) || up <= bound); %#ok<AGROW>
    end
end
[best, why] = rank_pick(cand, bound);
end

function [best, why] = rank_pick(X, bound)
% The selection rule over readings X (rec, held, kmin, ret, fa_w, n_w); see select_run.
up = arrayfun(@(x) ternary(isnan(x.fa_w), NaN, cp_upper(round(x.fa_w * x.n_w), x.n_w)), X);
c = find(isnan(up) | up <= bound);
why = sprintf(['the highest held recovery of the weakest threat among those with a one-sided 95%% false-alarm bound ' ...
    '<= %.0f%%; within 1 point, the best pooled held recovery, then the recovered (KPI 4), then the return'], 100 * bound);
if isempty(c)
    [~, o] = sort(up); c = o(1:min(3, numel(o)));
    why = 'none met the false-alarm bound: the three with the lowest bound, then the weakest threat';
end
km = [X(c).kmin]; km(isnan(km)) = -Inf;
top = c(km >= max(km) - 0.01);
top = top([X(top).held] >= max([X(top).held]) - 0.005);
top = top([X(top).rec] >= max([X(top).rec]));
[~, j] = max([X(top).ret]); best = top(j);
end

function S = with_nb(S, k, a)
% The noise-burst answer of branch k (1 not separable, 2 separable) set to a.
S.rule_nb{k} = a;
end

function [S, rows] = choose_settings(S, STEPS, evalf, bound, PK)
% The rule's settings, one coordinate (STEPS) at a time: every variant of a step against the
% setting in force (listed first, ties to it), the selection rule (rank_pick) picks. A variant
% is a struct of fields or a function of the settings in force. A step named in PK (name,
% rank: its candidates' cost order) is picked by nb_pick, without a tie to the setting in force.
if nargin < 5, PK = struct('name', {}, 'rank', {}); end
x0 = evalf(S); rows = {sprintf('  %-52s %s', 'in force', row_txt(S, x0))};
for k = 1:numel(STEPS)
    X = x0; V = {S};
    for v = STEPS(k).var
        if isa(v{1}, 'function_handle')
            Sv = v{1}(S);
        else
            Sv = S; for f = fieldnames(v{1})', Sv.(f{1}) = v{1}.(f{1}); end
        end
        if isequal(Sv, S), continue; end
        X(end+1) = evalf(Sv); V{end+1} = Sv; %#ok<AGROW>
        rows{end+1} = sprintf('  %-52s %s', [STEPS(k).name ':'], row_txt(Sv, X(end))); %#ok<AGROW>
    end
    j = find(strcmp({PK.name}, STEPS(k).name), 1);
    if isempty(j)
        b = rank_pick(X, bound);
    else
        b = nb_pick(X, bound, cellfun(PK(j).rank, V));
    end
    S = V{b}; x0 = X(b);
    rows{end+1} = sprintf('  -> %s: %s', STEPS(k).name, set_txt(S)); %#ok<AGROW>
end
end

function t = row_txt(S, x)
t = sprintf('%s | held %.1f%%, recovered %.1f%%, weakest %s %.1f%%, return %.3f, FA %s', set_txt(S), 100 * x.held, ...
    100 * x.rec, x.kmin_thr, 100 * x.kmin, x.ret, fa_txt(x.fa_w, x.n_w));
if isfield(x, 'nb_n'), t = sprintf('%s, noise-burst held %.1f%% of %d', t, 100 * x.nb_held, x.nb_n); end
end

function t = set_txt(S)
t = sprintf('nulling at %.2f dB, quiet slot %s, dwell %s, unknown flag over %s classes at retention %.2f, escalation on a drop %s', ...
    S.rule_mmse_db, ternary(S.rule_slot, 'on', 'off'), S.rule_dwell, S.unk_mode, S.unk_retain, ternary(S.esc_drop, 'on', 'off'));
if isfield(S, 'rule_nb') && isempty(S.rule_nb)
    t = [t, ', noise burst: the class mapping (power_control+fec_interleave / spatial_diversity+fec_interleave)'];
elseif isfield(S, 'rule_nb')
    t = sprintf('%s, noise burst %s / %s (separable)', t, S.rule_nb{:});
end
if isfield(S, 'core_nb') && ~isempty(S.core_nb), t = sprintf('%s, core rule on a noise burst %s', t, S.core_nb); end
end

function d = drops_of(mon, MONP, drop_mode, drop_db, THC, steps, floor_db)
% C2's drop thresholds of one monitor: its own from choose_drop_threshold.m (MONP; the form's
% alone when the file has none) and the steps around it: the median window that less the
% steps [dB] above the moving-away floor, the CUSUM one grid step per step's sign.
b = drop_db;
if ~isempty(MONP)
    k = find(strcmp({MONP.monitor}, mon), 1);
    if ~isempty(k) && isfinite(MONP(k).pick), b = MONP(k).pick; end
end
if isempty(b), d = NaN; return; end
if strcmp(drop_mode, 'class_cusum')
    [~, j] = min(abs(THC - b));
    d = unique(THC(min(max(j - sign(steps), 1), numel(THC))), 'stable');
else
    d = b - steps; d = d(d > floor_db);
end
if isempty(d), d = NaN; end
end

function PPc = with_entry(PP, en, drop_mode)
% The pools' settings with monitor and drop threshold en.
PPc = PP; [PPc.alarm_mode, PPc.confirm] = monitor(en.alarm, drop_mode);
if ~isnan(en.drop), PPc.drop_db = en.drop; end
end

function u = cp_upper(k, n)
% One-sided 95% Clopper-Pearson upper bound of a binomial proportion.
if k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

function t = fa_txt(fa, n)
if isnan(fa), t = '-'; else, t = sprintf('%d/%d', round(fa * n), n); end
end

function t = pct_txt(fa)
if isnan(fa), t = '-'; else, t = sprintf('%.1f%%', 100 * fa); end
end

function t = n_txt(CV, PP, thr)
if isempty(CV), t = '0'; else, t = sprintf('%d', sum(PP.ebno >= thr) * CV.n_geom); end
end

function t = rate_txt(F)
% False changes per cycle, per hour of flight and the mean time between them, with
% the 95% bound (false_change_rate.m).
if isnan(F.rate), t = '-'; return; end
t = sprintf('%d in %d cycles, %.2g per cycle (<= %.2g), %.0f per hour (<= %.0f), one every %.3g s (>= %.3g s)', ...
    F.k, F.cycles, F.rate, F.hi, F.per_hour, F.per_hour_hi, F.mtbf_s, F.mtbf_lo_s);
end

function t = dep_txt(d)
switch d
    case 'dqn_esc', t = 'the selected DQN + escalation';
    case 'dqn',     t = 'the selected DQN without escalation';
    otherwise,      t = 'rule + escalation (fallback)';
end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end

function t = mon_txt(name, drop_mode)
% A monitor of the grid as reported: its label, and the deployed form of its drop alarm
% when 'class_drop' reads as another.
t = sprintf('''%s''', name);
if ~strcmp(drop_mode, 'class_drop'), t = sprintf('''%s'' (%s)', name, strrep(name, 'class_drop', drop_mode)); end
end

function [mode, confirm] = monitor(name, drop_mode)
% 'class_drop 3/3' -> alarm definition 'class_drop', confirmation on 3 of the last 3 cycles;
% 'class_drop' reads as the drop alarm's form drop_mode.
t = strsplit(name);
mode = t{1};
if strcmp(mode, 'class_drop'), mode = drop_mode; end
confirm = sscanf(t{2}, '%d/%d')';
end
