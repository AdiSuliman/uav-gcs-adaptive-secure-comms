%% C2 - TRAIN DQN: sequential decision layer on measured frame pools
% Double DQN (van Hasselt et al., AAAI 2016) with experience replay and a target
% network (Mnih et al., Nature 2015) on link_env.m: 30-cycle episodes inside one
% seeded flight geometry, the threat (a single threat at any severity, or a combination)
% starts at a random cycle, a follower jammer re-acquires the channel after each
% hop (the intelligent jammer of Liu et al., 2018), and the agent sees what the
% receiver measures over the last cycles (policy_state.m): detector class
% probabilities, unknown flag, estimated BER, packet loss, SINR, IoT, spatial
% measurements, its own configuration, the time since its last change and the
% confirmed alarm. The shield of policy_mask.m (confirmed alarm, hold after a
% change) applies in training exactly as in deployment, and the Double DQN target
% maximizes over the configurations allowed in the next state.
% Data: the TRAIN split of data/policy_pools.mat for learning; the VALIDATION split
% (geometries never used in training) for checkpoints and selection; the test
% split is kept for evaluate_policies.m.
%
% Grid: monitor (alarm definition and m-of-n confirmation, CFG.monitors,
% policy_monitor.m; Richards, binary integration) x Eb/N0-drop threshold of the
% path_loss alarm (DROP_STEPS dB below the threshold of choose_drop_threshold.m)
% x false-switch penalty of the TRAINING reward (CFG.fa_penalty_grid) x
% CFG.dqn_gammas x CFG.dqn_seeds. Every run keeps the checkpoint with the best
% recovery on its own validation episodes. All runs are then compared on every
% (threat cell, Eb/N0, geometry) of the validation split: recovered episodes among
% the recoverable ones, per threat (severities pooled, as KPI 4) and pooled, and
% false alarms on the independent clean validation geometries
% (data/clean_val_pools.mat, one episode per geometry).
% Selection: among the runs whose one-sided 95% false-alarm bound is <= 5% (KPI 6
% as worded), the highest recovery of the weakest threat (KPI 4 as worded); within
% one point of it, the best pooled recovery, then the return.
% Gate: pooled recovery >= rule + escalation with the same monitor and the
% false-alarm bound. The best run of every gamma at the selected monitor, drop
% threshold and penalty is kept as an ablation. Reward-weight sensitivity:
% proposal mitigation 2.
%
% Output: data/trained_dqn.mat, results/dqn_training.txt, results/dqn_training_curves.png

close all; clc;
fprintf('=== C2: Train DQN ===\n\n');
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
K = link_env('tables', PP);
nA = numel(PP.actions);
[nS, cont] = policy_state_size(nA, numel(PP.classes));
SPLIT_TRAIN = 1; SPLIT_VAL = 2;
CD = decision_config();

%% 1. Hyperparameters
H = struct('gamma', 0.9, 'NE', 64, 'T', 30, 'episodes', 20000, 'buffer', 200000, 'warmup', 8000, ...
    'batch', 128, 'updates', 4, 'lr', 5e-4, 'lr_end', 5e-5, 'clip', 10, 'target_every', 500, ...
    'eps_end', 0.05, 'eps_frac', 0.6, 'huber', 1, 'p_unknown', 0.10, 'p_follow', 0.5, 'n_eval', 4, ...
    'hidden', [256 256]);
N_SEEDS = 3; GAMMAS = [0.5 0.9]; FA_PEN = 80;
ALARMS = {'class_drop 2/2', 'class_drop 3/3'};  % monitors: alarm definition, m/n confirmation
DROP_STEPS = [1 2];                      % path_loss alarm: 1 and 2 dB below the train-pool threshold
SENS_SCALES = [0.5 2];                   % reward-weight sensitivity: cost terms x scale
if exist('CFG', 'var') && isstruct(CFG)
    if isfield(CFG, 'dqn_seeds'), N_SEEDS = CFG.dqn_seeds; end
    if isfield(CFG, 'dqn_gammas'), GAMMAS = CFG.dqn_gammas; end
    if isfield(CFG, 'fa_penalty_grid'), FA_PEN = CFG.fa_penalty_grid; end
    if isfield(CFG, 'monitors'), ALARMS = CFG.monitors; end
    if isfield(CFG, 'dqn_episodes'), H.episodes = CFG.dqn_episodes; end
    if isfield(CFG, 'drop_steps'), DROP_STEPS = CFG.drop_steps; end
end
VAL_REPS = 2;                            % validation: every (cell, Eb/N0, geometry) of the split, twice
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    N_SEEDS = 1; GAMMAS = 0.5; FA_PEN = 80; ALARMS = {'class_drop 2/2'}; SENS_SCALES = 2; VAL_REPS = 1;
    DROP_STEPS = 1; H.episodes = 1280; H.buffer = 20000; H.warmup = 2000; H.n_eval = 1;
end
SEEDS = 42 + (0:N_SEEDS-1);
FA_BOUND = 0.05;                         % one-sided 95% bound of the clean-link false alarms (KPI 6)
DROP_DB = [];                            % path_loss alarm threshold of 'class_drop' (D52)
if isfile('data/drop_threshold.mat'), Dd = load('data/drop_threshold.mat', 'drop_db'); DROP_DB = Dd.drop_db; clear Dd; end
if ~isempty(DROP_DB), PP.drop_db = DROP_DB; end
CV = [];                                 % independent clean validation geometries (D52)
if isfile('data/clean_val_pools.mat'), Cv = load('data/clean_val_pools.mat', 'CT'); CV = Cv.CT; clear Cv; end

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
        ch = a ~= E.cfg; mem.since(ch) = 0; mem.since(~ch) = mem.since(~ch) + 1;
        [E, ~, obs] = link_env('step', E, PP, K, a);
    end
end
norm_in = struct('mu', zeros(nS, 1), 'sd', ones(nS, 1));
norm_in.mu(cont) = mean(S_all(cont, :), 2);
norm_in.sd(cont) = max(std(S_all(cont, :), 0, 2), 1e-3);

%% 3. Validation episodes and baselines
val_spec = full_val_spec(PP, K, H, SPLIT_VAL, VAL_REPS, RandStream('mt19937ar', 'Seed', 99));
val_thr = threat_of(PP, val_spec);                   % threat name per validation episode (severities pooled)
DROPS = [];
if ~isempty(DROP_DB), DROPS = DROP_DB - DROP_STEPS; DROPS = DROPS(DROPS > 0); end
if isempty(DROPS), DROPS = NaN; end
tab = policy_table(PP, K);

%% 4. Training: monitor x drop threshold x false-switch penalty x discount factor x seeds
runs = struct('alarm', {}, 'drop', {}, 'fa_pen', {}, 'gamma', {}, 'seed', {}, 'agent', {}, 'curve', {}, 'loss', {}, ...
    'best_ep', {}, 'val', {}, 'rec', {}, 'kmin', {}, 'kmin_thr', {}, 'fa_w', {}, 'n_w', {});
base = struct('alarm', {}, 'drop', {}, 'rule_rec', {}, 'rule_ret', {}, 'rule_fa_w', {}, 'tab_rec', {}, 'tab_ret', {}, 'tab_fa_w', {});
for ai = 1:numel(ALARMS)
    for dd = DROPS
        PPc = PP; [PPc.alarm_mode, PPc.confirm] = monitor(ALARMS{ai});
        if ~isnan(dd), PPc.drop_db = dd; end
        Rr = dqn_eval_batches('rule_esc', PPc, K, val_spec, [], struct(), 5000, SPLIT_VAL);
        Rt = dqn_eval_batches('table', PPc, K, val_spec, [], tab, 5000, SPLIT_VAL);
        [rw, ~] = eval_clean_wide('rule_esc', PPc, CV, [], struct(), H);
        [tw, ~] = eval_clean_wide('table', PPc, CV, [], tab, H);
        base(end+1) = struct('alarm', ALARMS{ai}, 'drop', dd, 'rule_rec', dqn_recovered(Rr), 'rule_ret', mean(Rr.ret), ...
            'rule_fa_w', rw, 'tab_rec', dqn_recovered(Rt), 'tab_ret', mean(Rt.ret), 'tab_fa_w', tw); %#ok<SAGROW>
        fprintf('=== Monitor ''%s'', drop %.1f dB: rule+esc recovered %.1f%%, return %.3f, FA %s | table recovered %.1f%%, return %.3f\n', ...
            ALARMS{ai}, dd, 100*base(end).rule_rec, base(end).rule_ret, pct_txt(rw), 100*base(end).tab_rec, base(end).tab_ret);
        for fp = FA_PEN
            Kt = K; Kt.FA = fp;                        % training reward only
            for g = GAMMAS
                for k = 1:N_SEEDS
                    fprintf('--- monitor ''%s'', drop %.1f dB, false-switch penalty %d, gamma %.2f, seed %d ---\n', ...
                        ALARMS{ai}, dd, fp, g, SEEDS(k));
                    Hg = H; Hg.gamma = g;
                    [ag, curve, lossc, best_ep] = dqn_train_run(Hg, PPc, Kt, K, norm_in, SEEDS(k), nS, SPLIT_TRAIN, SPLIT_VAL);
                    V = dqn_eval_batches('dqn', PPc, K, val_spec, ag, struct(), 5000, SPLIT_VAL);
                    [kmin, kthr] = weakest_threat(V, val_thr);
                    [fa_w, n_w] = eval_clean_wide('dqn', PPc, CV, ag, struct(), H);
                    fprintf(['    checkpoint %d | validation: recovered %.1f%% | weakest threat %s %.1f%% | restored %.1f%% | ' ...
                        'return %.3f | FA %s\n'], best_ep, 100*dqn_recovered(V), kthr, 100*kmin, 100*mean(V.restored_post), ...
                        mean(V.ret), fa_txt(fa_w, n_w));
                    runs(end+1) = struct('alarm', ALARMS{ai}, 'drop', dd, 'fa_pen', fp, 'gamma', g, 'seed', SEEDS(k), ...
                        'agent', ag, 'curve', curve, 'loss', lossc, 'best_ep', best_ep, 'val', V, 'rec', dqn_recovered(V), ...
                        'kmin', kmin, 'kmin_thr', kthr, 'fa_w', fa_w, 'n_w', n_w); %#ok<SAGROW>
                end
            end
        end
    end
end
vrec = [runs.rec]; vret = arrayfun(@(r) mean(r.val.ret), runs); vmin = [runs.kmin];
fa_ok = arrayfun(@(r) isnan(r.fa_w) || cp_upper(round(r.fa_w * r.n_w), r.n_w) <= FA_BOUND, runs);
cand = find(fa_ok);
if isempty(cand)
    [~, o] = sort([runs.fa_w]); cand = o(1:min(3, numel(o)));
    sel_rule = 'no run met the false-alarm bound: the three with the fewest false alarms, then the weakest threat';
else
    sel_rule = sprintf(['highest recovery of the weakest threat among runs with a one-sided 95%% false-alarm bound ' ...
        '<= %.0f%%; within 1 point, the best pooled recovery'], 100*FA_BOUND);
end
top = cand(vmin(cand) >= max(vmin(cand)) - 0.01);
top = top(vrec(top) >= max(vrec(top)) - 0.005);
[~, j] = max(vret(top)); best = top(j);
agent = runs(best).agent;
gamma_sel = runs(best).gamma; fa_pen_sel = runs(best).fa_pen; alarm_sel = runs(best).alarm; drop_sel = runs(best).drop;
same = @(r) r.fa_pen == fa_pen_sel & strcmp(r.alarm, alarm_sel) & isequaln(r.drop, drop_sel);
agents = cell(1, numel(GAMMAS));                     % best run per discount factor at the chosen monitor, drop and penalty
for gi = 1:numel(GAMMAS)
    m = find([runs.gamma] == GAMMAS(gi) & arrayfun(same, runs));
    mk = m(fa_ok(m)); if isempty(mk), mk = m; end
    [~, jj] = max(vmin(mk));
    agents{gi} = runs(mk(jj)).agent;
end
agents{find(GAMMAS == gamma_sel, 1)} = agent;

%% 5. Gate and report
bsel = base(strcmp({base.alarm}, alarm_sel) & arrayfun(@(b) isequaln(b.drop, drop_sel), base));
gate = vrec(best) >= bsel.rule_rec && fa_ok(best);
rep = {};
rep{end+1} = '=== DQN TRAINING ===';
rep{end+1} = sprintf(['Generated: %s | Double DQN + shield, state history %d cycles, hidden %s, replay %d, target every ' ...
    '%d updates, lr %.0e -> %.0e, %d episodes x %d cycles | monitor %s x drop %s dB x penalty %s x gamma %s x %d seeds'], ...
    datestr(now), CD.hist, mat2str(H.hidden), H.buffer, H.target_every, H.lr, H.lr_end, H.episodes, H.T, ...
    strjoin(ALARMS, '/'), mat2str(DROPS), mat2str(FA_PEN), mat2str(GAMMAS), N_SEEDS);
rep{end+1} = 'False-switch penalty: training reward only; validation and test use the standard reward.';
rep{end+1} = sprintf(['Validation: %d episodes, every (threat cell, Eb/N0, geometry) of the VALIDATION split (geometries ' ...
    'never used in training) %d times: single threats at three severities, combined threats, clean link. Recovered = ' ...
    'BER and packet loss <= 2x clean for 5 consecutive cycles, among recoverable threat episodes; weakest threat = ' ...
    'lowest per-threat recovery (severities pooled, KPI 4). FA: false-alarm episodes on %s independent clean ' ...
    'validation geometries (data/clean_val_pools.mat).'], numel(val_thr), VAL_REPS, n_txt(CV, PP));
if ~isempty(DROP_DB)
    rep{end+1} = sprintf(['''class_drop'': path_loss alarm after an Eb/N0 drop >= the run''s threshold; train-pool ' ...
        'threshold %.1f dB (data/drop_threshold.mat)'], DROP_DB);
end
rep{end+1} = sprintf('%-46s %10s %28s %10s %9s %14s %12s', 'run', 'recovered', 'weakest threat', 'restored', 'return', ...
    'FA indep.', 'switches/ep');
for k = 1:numel(runs)
    R = runs(k).val;
    rep{end+1} = sprintf('%-46s %9.1f%% %28s %9.1f%% %9.3f %14s %12.2f   (checkpoint %d)', ...
        sprintf('%s drop %.1f pen %d g=%.2f seed %d', runs(k).alarm, runs(k).drop, runs(k).fa_pen, runs(k).gamma, runs(k).seed), ...
        100*runs(k).rec, sprintf('%s %.1f%%', runs(k).kmin_thr, 100*runs(k).kmin), 100*mean(R.restored_post), mean(R.ret), ...
        fa_txt(runs(k).fa_w, runs(k).n_w), mean(R.switches), runs(k).best_ep); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = 'Baselines on the same validation episodes:';
for ai = 1:numel(base)
    rep{end+1} = sprintf(['  %-12s drop %.1f dB  rule + escalation: recovered %.1f%%, return %.3f, FA %s | table: ' ...
        'recovered %.1f%%, return %.3f, FA %s'], base(ai).alarm, base(ai).drop, 100*base(ai).rule_rec, base(ai).rule_ret, ...
        pct_txt(base(ai).rule_fa_w), 100*base(ai).tab_rec, base(ai).tab_ret, pct_txt(base(ai).tab_fa_w)); %#ok<SAGROW>
end
rep{end+1} = sprintf(['Selected: monitor ''%s'', drop %.1f dB, false-switch penalty %d, gamma %.2f, seed %d (%s). Gate ' ...
    '(recovery >= rule + escalation with the same monitor, false-alarm bound <= %.0f%%): %s'], alarm_sel, drop_sel, ...
    fa_pen_sel, gamma_sel, runs(best).seed, sel_rule, 100*FA_BOUND, ternary(gate, 'PASS', 'FAIL'));
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/dqn_training.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
if ~gate, warning('train_dqn:gate', 'DQN validation gate FAILED -- see results/dqn_training.txt'); end

seed_summary = struct('alarms', {{runs.alarm}}, 'drops', [runs.drop], 'fa_pens', [runs.fa_pen], 'gammas', [runs.gamma], ...
    'seeds', [runs.seed], 'val_recovered', vrec, 'val_weakest', vmin, 'val_weakest_threat', {{runs.kmin_thr}}, ...
    'val_return', vret, 'fa_indep', [runs.fa_w], 'n_indep', [runs.n_w], ...
    'best_ep', [runs.best_ep], 'selected_alarm', alarm_sel, 'selected_drop', drop_sel, 'selected_fa_pen', fa_pen_sel, ...
    'selected_gamma', gamma_sel, 'selected_seed', runs(best).seed, 'selection_rule', sel_rule, 'gate_pass', gate, ...
    'rule_recovered', bsel.rule_rec, 'rule_return', bsel.rule_ret, 'table_return', bsel.tab_ret);
H.gamma = gamma_sel; H.fa_pen = fa_pen_sel;
action_names = PP.actions;
gammas = GAMMAS;
[alarm_mode, confirm] = monitor(alarm_sel);
drop_db = drop_sel; if isnan(drop_db), drop_db = []; end
agent = dqn_dense(agent);                          % matrix form for deployment (D60)
for gi = find(~cellfun(@isempty, agents)), agents{gi} = dqn_dense(agents{gi}); end
save('data/trained_dqn.mat', 'agent', 'agents', 'gammas', 'confirm', 'alarm_mode', 'drop_db', 'H', ...
    'norm_in', 'seed_summary', 'action_names', 'tab', '-v7.3');
fprintf('Saved data/trained_dqn.mat\n');

fig = figure('Position', [100 100 1000 380], 'Color', 'w');
subplot(1, 2, 1); hold on; grid on;
cols = lines(numel(FA_PEN)); hl = gobjects(1, numel(FA_PEN));
for k = 1:numel(runs)
    ci = find(FA_PEN == runs(k).fa_pen, 1);
    c = runs(k).curve;
    hl(ci) = plot(c(:, 1), 100 * c(:, 2), 'Color', cols(ci, :), 'LineWidth', 1.1);
    [~, m] = max(c(:, 2));
    plot(c(m, 1), 100 * c(m, 2), 'o', 'Color', cols(ci, :), 'MarkerSize', 5, 'HandleVisibility', 'off');
end
yline(100 * bsel.rule_rec, 'k--', 'rule + escalation (validation)');
xlabel('Episode'); ylabel('Recovered episodes, validation checkpoints [%]');
title('Learning curves (o = kept checkpoint)');
legend(hl, arrayfun(@(p) sprintf('false-switch penalty %d', p), FA_PEN, 'UniformOutput', false), 'Location', 'southeast');
subplot(1, 2, 2); plot(movmean(runs(best).loss, 200)); grid on;
xlabel('Update'); ylabel('Huber loss (moving mean 200)');
title(sprintf('Q-loss, selected run (penalty %d, \\gamma %.2f, seed %d)', fa_pen_sel, gamma_sel, runs(best).seed));
saveas(fig, 'results/dqn_training_curves.png'); close(fig);

%% 6. Reward-weight sensitivity (proposal mitigation 2)
% The DQN is retrained with every cost term (goodput, spectrum, power,
% processing, switching, false switch) scaled by SENS_SCALES at the selected
% alarm, penalty and gamma; DQN, rule + escalation and table are compared on the
% validation episodes. The conclusion holds when the DQN stays ahead of both
% baselines in recovery at every scale.
PPc = PP; [PPc.alarm_mode, PPc.confirm] = monitor(alarm_sel);
if ~isempty(drop_db), PPc.drop_db = drop_db; end
sens = struct('scale', {}, 'dqn_rec', {}, 'rule_rec', {}, 'tab_rec', {}, 'dqn_ret', {}, 'dqn_gput', {});
for f = [1, SENS_SCALES]
    Kf = K; Kf.cost = f * K.cost; Kf.SW = f * K.SW; Kf.FA = f * K.FA;
    if f == 1
        ag = agent;
    else
        fprintf('--- reward sensitivity: costs x %.1f ---\n', f);
        Hs = H; Hs.gamma = gamma_sel;
        Kft = Kf; Kft.FA = f * fa_pen_sel;
        ag = dqn_train_run(Hs, PPc, Kft, Kf, norm_in, runs(best).seed, nS, SPLIT_TRAIN, SPLIT_VAL);
    end
    Vd = dqn_eval_batches('dqn', PPc, Kf, val_spec, ag, struct(), 5000, SPLIT_VAL);
    Vr = dqn_eval_batches('rule_esc', PPc, Kf, val_spec, [], struct(), 5000, SPLIT_VAL);
    Vt = dqn_eval_batches('table', PPc, Kf, val_spec, [], policy_table(PP, Kf), 5000, SPLIT_VAL);
    sens(end+1) = struct('scale', f, 'dqn_rec', dqn_recovered(Vd), 'rule_rec', dqn_recovered(Vr), 'tab_rec', dqn_recovered(Vt), ...
        'dqn_ret', mean(Vd.ret), 'dqn_gput', mean(Vd.gput_post, 'omitnan')); %#ok<SAGROW>
end
rs2 = {'', sprintf('Reward-weight sensitivity (validation; every cost term scaled, DQN retrained per scale, seed %d):', ...
    runs(best).seed), sprintf('%-8s %28s %10s %10s', 'scale', 'recovered DQN/rule/table', 'DQN ret', 'DQN gput')};
for i = 1:numel(sens)
    x = sens(i);
    rs2{end+1} = sprintf('%-8s %28s %10.3f %10.3f', sprintf('x %.1f', x.scale), ...
        sprintf('%.1f/%.1f/%.1f%%', 100*x.dqn_rec, 100*x.rule_rec, 100*x.tab_rec), x.dqn_ret, x.dqn_gput); %#ok<SAGROW>
end
holds = all([sens.dqn_rec] >= [sens.rule_rec] & [sens.dqn_rec] >= [sens.tab_rec]);
rs2{end+1} = sprintf('DQN recovery at least that of rule + escalation and table at every scale: %s', ternary(holds, 'YES', 'NO'));
fid = fopen('results/dqn_training.txt', 'a'); fprintf(fid, '%s\n', rs2{:}); fclose(fid);
fprintf('%s\n', rs2{:});
save('data/trained_dqn.mat', 'sens', '-append');
fprintf('=== C2 Complete ===\n');

%% ===================== Local functions =====================
function specs = full_val_spec(PP, K, H, split, reps, rs)
% Every (cell, Eb/N0, geometry) of the split `reps` times, in batches of H.NE (the
% last one shorter): onset, follower jammer and follower delay drawn per episode.
cells = find(~cellfun(@isempty, PP.pools(:, 1, K.na, split))');
[c, s, r] = ndgrid(cells, 1:numel(PP.ebno), 1:K.nR(split));
c = repmat(c(:)', 1, reps); s = repmat(s(:)', 1, reps); r = repmat(r(:)', 1, reps);
n = numel(c); nb = ceil(n / H.NE);
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*H.NE + 1:min(b*H.NE, n); m = numel(i);
    specs{b} = struct('scn', c(i), 's', s(i), 'r', r(i), 'onset', randi(rs, [3 10], 1, m), ...
        'follow', K.followable(c(i)) & rand(rs, 1, m) < H.p_follow, 'fdelay', randi(rs, [2 5], 1, m), ...
        'unk', false(1, m), 'T', H.T);
end
end

function t = threat_of(PP, specs)
% Threat of every validation episode, severities pooled (KPI 4 counts per threat).
t = PP.scen(cell2mat(cellfun(@(sp) sp.scn, specs, 'UniformOutput', false)));
end

function [kmin, name] = weakest_threat(V, thr)
% Lowest recovery among the recoverable episodes of one threat (threats with at
% least 10 recoverable validation episodes).
m = V.recoverable & V.threat;
u = unique(thr(m));
rec = nan(1, numel(u));
for i = 1:numel(u)
    mi = m & strcmp(thr, u{i});
    if sum(mi) >= 10, rec(i) = mean(V.recovered(mi)); end
end
[kmin, j] = min(rec);
name = u{j};
end

function [fa, n] = eval_clean_wide(kind, PP, CT, agent, opt, H)
% False-alarm episodes on the independent clean geometries of CT: one clean
% episode per geometry and Eb/N0, as in evaluate_policies.m (D51, D52).
fa = NaN; n = 0;
if isempty(CT), return; end
[PPw, Kw] = clean_world(PP, CT);
nS = numel(PP.ebno); NE = H.NE; ic = Kw.clean;
[ss, rr] = ndgrid(1:nS, 1:CT.n_geom); ss = ss(:)'; rr = rr(:)';
n = numel(ss); nb = ceil(n / NE); pad = nb * NE - n;
k_ = mod(0:n + pad - 1, n) + 1; ss = ss(k_); rr = rr(k_);                     % cyclic padding of the last batch
sw = [];
for b = 1:nb
    i = (b-1)*NE + (1:NE);
    spec = struct('scn', ic * ones(1, NE), 's', ss(i), 'onset', 3 * ones(1, NE), 'follow', false(1, NE), ...
        'fdelay', 2 * ones(1, NE), 'unk', false(1, NE), 'T', H.T, 'r', rr(i));
    Rb = rollout_policy(kind, PPw, Kw, spec, 2, agent, opt, 41000 + b);
    sw = [sw, Rb.switches]; %#ok<AGROW>
end
fa = mean(sw(1:n) > 0);
end

function [PPw, Kw] = clean_world(PP, CT)
% The pools with the validation split replaced by the independent clean geometries.
% Only the pools and their tables are cached: the monitor settings (alarm,
% confirmation, drop threshold) always come from the PP of this call.
persistent key cache
k = sprintf('%s|%s', CT.created, PP.created);
if ~isequal(key, k)
    nS = numel(PP.ebno); nA = numel(PP.actions);
    pools = PP.pools;
    pools(:, :, :, 2) = {[]};
    ic = find(strcmp(PP.scen, 'none'), 1);
    pools(ic, :, :, 2) = reshape(CT.pools(1, :, :), [1 nS nA]);
    runs = PP.runs; runs{2} = CT.runs;
    PPt = PP; PPt.pools = pools; PPt.runs = runs;
    key = k; cache = struct('pools', {pools}, 'runs', {runs}, 'Kw', link_env('tables', PPt));
end
PPw = PP; PPw.pools = cache.pools; PPw.runs = cache.runs;
Kw = cache.Kw;
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

function t = n_txt(CV, PP)
if isempty(CV), t = '0'; else, t = sprintf('%d', numel(PP.ebno) * CV.n_geom); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end

function [mode, confirm] = monitor(name)
% 'class_drop 3/3' -> alarm definition 'class_drop', confirmation on 3 of the last 3 cycles.
t = strsplit(name);
mode = t{1};
confirm = sscanf(t{2}, '%d/%d')';
end
