%% C2 - TRAIN DQN: sequential decision layer on measured frame pools (D44-D50)
% Double DQN (van Hasselt et al., AAAI 2016) with experience replay and a target
% network (Mnih et al., Nature 2015) on link_env.m: 30-cycle episodes inside
% one seeded flight geometry, the threat starts at a random cycle, a follower
% jammer re-acquires the channel after each hop (smart jammer, Liu et al., 2018),
% and the agent sees what the detector sees (class probabilities, unknown flag),
% the link features, its own configuration, the time since its last change and
% the confirmed alarm (policy_state.m). The shield of policy_mask.m applies in
% training exactly as in deployment: without a confirmed alarm the agent can only
% keep its configuration or release it, and the Double DQN target maximizes over
% the configurations allowed in the next state.
% Training uses the train split of data/policy_pools.mat: single threats, the
% clean link and the training combinations (D46); the test combinations and the
% test split are kept for evaluate_policies.m.
%
% Grid: alarm definition (CFG.alarm_modes, policy_monitor.m: 'class' = hostile
% class or degradation; 'class_drop' = the same, with path_loss counted only
% after a drop of the Eb/N0 estimate from the episode's reference) x alarm
% confirmation (CFG.confirm_grid, m-of-n rows) x false-switch
% penalty of the TRAINING reward (CFG.fa_penalty_grid, points per change on a
% healthy link; link_env default 20) x CFG.dqn_gammas x CFG.dqn_seeds. The
% penalty only shapes training: every run is validated and every policy is
% evaluated with the standard reward, so returns stay comparable. Each run keeps
% the checkpoint with the best greedy return on its own evaluation episodes
% (train pools); all runs are compared on 1280 validation episodes and on 512
% clean-link validation episodes (train pools, fresh draws). Selected run: the
% best validation return among the runs whose clean-link false-alarm episodes
% stay <= CFG.fa_val (default 2%: margin for the one-sided 95% bound <= 5% of
% KPI 6 on the test set); if none qualifies, the fewest false alarms, then the
% best return. The rule and the table run with the same alarm. The best
% run of every gamma at the selected alarm and penalty is kept as an ablation.
%
% Output: data/trained_dqn.mat, results/dqn_training.txt, results/dqn_training_curves.png

close all; clc;
fprintf('=== C2: Train DQN (D44-D50) ===\n\n');
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
K = link_env('tables', PP);
nA = numel(PP.actions);
[nS, cont] = policy_state_size(nA);

%% 1. Hyperparameters
H = struct('gamma', 0.9, 'NE', 64, 'T', 30, 'episodes', 12000, 'buffer', 150000, 'warmup', 6000, ...
    'batch', 128, 'updates', 4, 'lr', 5e-4, 'lr_end', 5e-5, 'clip', 10, 'target_every', 500, ...
    'eps_end', 0.05, 'eps_frac', 0.6, 'huber', 1, 'p_unknown', 0.10, 'p_follow', 0.5, 'n_eval', 4);
N_SEEDS = 3; GAMMAS = [0 0.5 0.9]; CONFIRMS = [2 2]; FA_PEN = [20 80]; FA_VAL = 0.02;
ALARMS = {'class', 'class_drop'};
SENS_SCALES = [0.5 2];                   % reward-weight sensitivity: cost terms x scale
if exist('CFG', 'var') && isstruct(CFG) && isfield(CFG, 'dqn_seeds'), N_SEEDS = CFG.dqn_seeds; end
if exist('CFG', 'var') && isstruct(CFG) && isfield(CFG, 'dqn_gammas'), GAMMAS = CFG.dqn_gammas; end
if exist('CFG', 'var') && isstruct(CFG) && isfield(CFG, 'confirm_grid'), CONFIRMS = CFG.confirm_grid; end
if exist('CFG', 'var') && isstruct(CFG) && isfield(CFG, 'fa_val'), FA_VAL = CFG.fa_val; end
if exist('CFG', 'var') && isstruct(CFG) && isfield(CFG, 'fa_penalty_grid'), FA_PEN = CFG.fa_penalty_grid; end
if exist('CFG', 'var') && isstruct(CFG) && isfield(CFG, 'alarm_modes'), ALARMS = CFG.alarm_modes; end
SEEDS = 42 + (0:N_SEEDS-1);
N_VAL = 20;                              % validation batches of H.NE episodes
N_CLEAN = 8;                             % clean-link validation batches (false alarms)

%% 2. State normalization from random-policy rollouts
rs = RandStream('mt19937ar', 'Seed', 7);
S_all = [];
for b = 1:20
    spec = make_spec(H, PP, K, rs);
    [E, obs] = link_env('reset', PP, K, spec, 1, rs);
    mem = policy_monitor('init', H.NE, nA);
    for t = 1:H.T
        [mem, M] = policy_monitor('update', mem, obs, PP);
        S_all = [S_all, policy_state(obs, E.cfg, mem.since, M.ber_avg, M.confirmed, PP, M.drop)]; %#ok<AGROW>
        a = randi(rs, nA, 1, H.NE);
        ch = a ~= E.cfg; mem.since(ch) = 0; mem.since(~ch) = mem.since(~ch) + 1;
        [E, ~, obs] = link_env('step', E, PP, K, a);
    end
end
norm_in = struct('mu', zeros(nS, 1), 'sd', ones(nS, 1));
norm_in.mu(cont) = mean(S_all(cont, :), 2);
norm_in.sd(cont) = max(std(S_all(cont, :), 0, 2), 1e-3);

%% 3. Validation episodes and baselines
val_spec = cell(1, N_VAL);
rv = RandStream('mt19937ar', 'Seed', 99);
for b = 1:N_VAL, val_spec{b} = make_spec(H, PP, K, rv); end
clean_spec = cell(1, N_CLEAN);                       % clean-link episodes for the false-alarm estimate
for b = 1:N_CLEAN
    sc = make_spec(H, PP, K, rv);
    sc.scn(:) = 1; sc.follow(:) = false; sc.unk(:) = false;
    clean_spec{b} = sc;
end
tab = policy_table(PP, K);

%% 4. Training: alarm x confirmation x false-switch penalty x discount factor x seeds
runs = struct('alarm', {}, 'confirm', {}, 'fa_pen', {}, 'gamma', {}, 'seed', {}, 'agent', {}, 'curve', {}, ...
    'loss', {}, 'best_ep', {}, 'val', {}, 'fa', {});
base = struct('alarm', {}, 'confirm', {}, 'rule_ret', {}, 'rule_fa', {}, 'tab_ret', {}, 'tab_fa', {});
for ai = 1:numel(ALARMS)
    for ci = 1:size(CONFIRMS, 1)
        PPc = PP; PPc.confirm = CONFIRMS(ci, :); PPc.alarm_mode = ALARMS{ai};
        Rr = eval_batches('rule_esc', PPc, K, val_spec, [], struct(), 5000);
        Rt = eval_batches('table', PPc, K, val_spec, [], tab, 5000);
        Cr = eval_batches('rule_esc', PPc, K, clean_spec, [], struct(), 7000);
        Ct = eval_batches('table', PPc, K, clean_spec, [], tab, 7000);
        base(end+1) = struct('alarm', ALARMS{ai}, 'confirm', CONFIRMS(ci, :), 'rule_ret', mean(Rr.ret), ...
            'rule_fa', mean(Cr.switches > 0), 'tab_ret', mean(Rt.ret), 'tab_fa', mean(Ct.switches > 0)); %#ok<SAGROW>
        fprintf('=== Alarm ''%s'', confirmation %d of %d: rule+esc return %.3f, FA %.1f%% | table return %.3f, FA %.1f%%\n', ...
            ALARMS{ai}, CONFIRMS(ci, :), base(end).rule_ret, 100*base(end).rule_fa, base(end).tab_ret, 100*base(end).tab_fa);
        for fp = FA_PEN
            Kt = K; Kt.FA = fp;                            % training reward only
            for g = GAMMAS
                for k = 1:N_SEEDS
                    fprintf('--- alarm ''%s'', confirmation %d of %d, false-switch penalty %d, gamma %.2f, seed %d ---\n', ...
                        ALARMS{ai}, CONFIRMS(ci, :), fp, g, SEEDS(k));
                    Hg = H; Hg.gamma = g;
                    [ag, curve, lossc, best_ep] = train_one(Hg, PPc, Kt, norm_in, SEEDS(k), nS);
                    V = eval_batches('dqn', PPc, K, val_spec, ag, struct(), 5000);
                    C = eval_batches('dqn', PPc, K, clean_spec, ag, struct(), 7000);
                    fa = mean(C.switches > 0);             % on the clean link every change is a false alarm
                    fprintf(['    checkpoint %d | validation: return %.3f | restored %.1f%% | goodput %.3f | ' ...
                        'false-alarm episodes %.1f%%\n'], best_ep, mean(V.ret), 100*mean(V.restored_post), ...
                        mean(V.gput_post), 100*fa);
                    runs(end+1) = struct('alarm', ALARMS{ai}, 'confirm', CONFIRMS(ci, :), 'fa_pen', fp, 'gamma', g, ...
                        'seed', SEEDS(k), 'agent', ag, 'curve', curve, 'loss', lossc, 'best_ep', best_ep, 'val', V, ...
                        'fa', fa); %#ok<SAGROW>
                end
            end
        end
    end
end
vret = arrayfun(@(r) mean(r.val.ret), runs);
ok_fa = [runs.fa] <= FA_VAL;
if any(ok_fa)
    cand = find(ok_fa); [~, j] = max(vret(cand)); best = cand(j);
    sel_rule = sprintf('best validation return among runs with false-alarm episodes <= %.0f%%', 100*FA_VAL);
else
    [~, o] = sortrows([[runs.fa]', -vret']); best = o(1);
    sel_rule = sprintf('no run with false-alarm episodes <= %.0f%%: fewest false alarms, then best return', 100*FA_VAL);
end
agent = runs(best).agent;
gamma_sel = runs(best).gamma; confirm_sel = runs(best).confirm; fa_pen_sel = runs(best).fa_pen;
alarm_sel = runs(best).alarm;
same = @(r) strcmp({r.alarm}, alarm_sel) & ismember(vertcat(r.confirm), confirm_sel, 'rows')';
agents = cell(1, numel(GAMMAS));                     % best seed per discount factor at the chosen alarm and penalty
for gi = 1:numel(GAMMAS)
    m = find([runs.gamma] == GAMMAS(gi) & [runs.fa_pen] == fa_pen_sel & same(runs));
    mk = m(ok_fa(m)); if isempty(mk), mk = m; end
    [~, jj] = max(vret(mk));
    agents{gi} = runs(mk(jj)).agent;
end
agents{find(GAMMAS == gamma_sel, 1)} = agent;
agent_bandit = [];
if any(GAMMAS == 0), agent_bandit = agents{GAMMAS == 0}; end

%% 5. Gate and report
bsel = base(strcmp({base.alarm}, alarm_sel) & ismember(vertcat(base.confirm), confirm_sel, 'rows')');
gate = vret(best) >= bsel.rule_ret && runs(best).fa <= FA_VAL;
rep = {};
rep{end+1} = '=== DQN TRAINING (D44-D50) ===';
rep{end+1} = sprintf(['Generated: %s | Double DQN + shield, replay %d, target every %d updates, lr %.0e -> %.0e, ' ...
    '%d episodes x %d cycles | alarm %s x confirmation %s x false-switch penalty %s x gamma %s x %d seeds'], ...
    datestr(now), H.buffer, H.target_every, H.lr, H.lr_end, H.episodes, H.T, strjoin(ALARMS, '/'), ...
    strjoin(arrayfun(@(i) sprintf('%d-of-%d', CONFIRMS(i, :)), 1:size(CONFIRMS, 1), 'UniformOutput', false), ', '), ...
    mat2str(FA_PEN), mat2str(GAMMAS), N_SEEDS);
rep{end+1} = sprintf(['False-switch penalty: training reward only (points per change on a healthy link); ' ...
    'validation and test use the standard reward (penalty %d).'], K.FA);
rep{end+1} = sprintf(['Validation (train pools, fresh draws): return on %d episodes (single threats, training ' ...
    'combinations, clean link); false alarms on %d clean-link episodes (any change)'], N_VAL * H.NE, N_CLEAN * H.NE);
rep{end+1} = sprintf('%-44s %9s %10s %9s %13s %12s', 'run', 'return', 'restored', 'goodput', 'FA episodes', 'switches/ep');
for k = 1:numel(runs)
    R = runs(k).val;
    rep{end+1} = sprintf('%-44s %9.3f %9.1f%% %9.3f %12.1f%% %12.2f   (checkpoint %d)', ...
        sprintf('%s %d-of-%d pen %d g=%.2f seed %d', runs(k).alarm, runs(k).confirm, runs(k).fa_pen, runs(k).gamma, ...
        runs(k).seed), mean(R.ret), ...
        100*mean(R.restored_post), mean(R.gput_post), 100*runs(k).fa, mean(R.switches), runs(k).best_ep); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = 'Per alarm and confirmation (DQN: mean over runs):';
rep{end+1} = sprintf('%-20s %12s %12s %12s %12s %12s %12s', 'alarm / confirm', 'DQN return', 'DQN FA', ...
    'rule return', 'rule FA', 'table return', 'table FA');
for ci = 1:numel(base)
    m = strcmp({runs.alarm}, base(ci).alarm) & ismember(vertcat(runs.confirm), base(ci).confirm, 'rows')';
    rep{end+1} = sprintf('%-20s %12.3f %11.1f%% %12.3f %11.1f%% %12.3f %11.1f%%', ...
        sprintf('%s %d-of-%d', base(ci).alarm, base(ci).confirm), mean(vret(m)), 100*mean([runs(m).fa]), ...
        base(ci).rule_ret, 100*base(ci).rule_fa, base(ci).tab_ret, 100*base(ci).tab_fa); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = 'Per alarm, false-switch penalty and gamma (DQN: mean over seeds):';
rep{end+1} = sprintf('%-10s %-10s %8s %12s %12s %12s', 'alarm', 'penalty', 'gamma', 'return', 'restored', 'FA episodes');
for ai = 1:numel(ALARMS)
    for fp = FA_PEN
        for g = GAMMAS
            m = strcmp({runs.alarm}, ALARMS{ai}) & [runs.fa_pen] == fp & [runs.gamma] == g;
            rep{end+1} = sprintf('%-10s %-10d %8.2f %12.3f %11.1f%% %11.1f%%', ALARMS{ai}, fp, g, mean(vret(m)), ...
                100*mean(arrayfun(@(r) mean(r.val.restored_post), runs(m))), 100*mean([runs(m).fa])); %#ok<SAGROW>
        end
    end
end
rep{end+1} = sprintf(['Selected: alarm ''%s'', confirmation %d-of-%d, false-switch penalty %d, gamma %.2f, seed %d ' ...
    '(%s). Gate (return >= rule+escalation with the same alarm, FA <= %.0f%%): %s'], alarm_sel, confirm_sel, ...
    fa_pen_sel, gamma_sel, runs(best).seed, sel_rule, 100*FA_VAL, ternary(gate, 'PASS', 'FAIL'));
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/dqn_training.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
if ~gate, warning('train_dqn:gate', 'DQN validation gate FAILED -- see results/dqn_training.txt'); end

seed_summary = struct('alarms', {{runs.alarm}}, 'confirms', vertcat(runs.confirm), 'fa_pens', [runs.fa_pen], ...
    'gammas', [runs.gamma], ...
    'seeds', [runs.seed], 'val_return', vret, 'fa', [runs.fa], 'fa_limit', FA_VAL, 'best_ep', [runs.best_ep], ...
    'selected_alarm', alarm_sel, 'selected_confirm', confirm_sel, 'selected_fa_pen', fa_pen_sel, 'selected_gamma', gamma_sel, ...
    'selected_seed', runs(best).seed, 'selection_rule', sel_rule, ...
    'gate_pass', gate, 'rule_return', bsel.rule_ret, 'table_return', bsel.tab_ret);
H.gamma = gamma_sel; H.fa_pen = fa_pen_sel;
action_names = PP.actions;
gammas = GAMMAS;
confirm = confirm_sel;
alarm_mode = alarm_sel;
save('data/trained_dqn.mat', 'agent', 'agents', 'gammas', 'confirm', 'alarm_mode', 'agent_bandit', 'H', 'norm_in', ...
    'seed_summary', 'action_names', 'tab', '-v7.3');
fprintf('Saved data/trained_dqn.mat\n');

fig = figure('Position', [100 100 1000 380], 'Color', 'w');
subplot(1, 2, 1); hold on; grid on;
cols = lines(numel(FA_PEN)); hl = gobjects(1, numel(FA_PEN));
for k = 1:numel(runs)
    ci = find(FA_PEN == runs(k).fa_pen, 1);
    c = runs(k).curve;
    hl(ci) = plot(c(:, 1), c(:, 2), 'Color', cols(ci, :), 'LineWidth', 1.1);
    [~, m] = max(c(:, 2));
    plot(c(m, 1), c(m, 2), 'o', 'Color', cols(ci, :), 'MarkerSize', 5, 'HandleVisibility', 'off');
end
yline(bsel.rule_ret, 'k--', 'rule + escalation (validation)');
xlabel('Episode'); ylabel(sprintf('Mean reward per cycle (greedy, %d episodes)', H.n_eval * H.NE));
title('Learning curves (o = kept checkpoint)');
legend(hl, arrayfun(@(p) sprintf('false-switch penalty %d', p), FA_PEN, 'UniformOutput', false), ...
    'Location', 'southeast');
subplot(1, 2, 2); plot(movmean(runs(best).loss, 200)); grid on;
xlabel('Update'); ylabel('Huber loss (moving mean 200)');
title(sprintf('Q-loss, selected run (%d-of-%d, penalty %d, \\gamma %.2f, seed %d)', confirm_sel, fa_pen_sel, ...
    gamma_sel, runs(best).seed));
saveas(fig, 'results/dqn_training_curves.png'); close(fig);

%% 6. Reward-weight sensitivity (proposal mitigation 2)
% The DQN is retrained with every cost term (goodput, spectrum, power,
% processing, switching, false switch) scaled by SENS_SCALES, at the selected
% confirmation, penalty and gamma (the training penalty scales with the rest);
% DQN, rule + escalation and table are compared under the same scaled reward on
% the validation episodes. The conclusion holds when
% the DQN stays ahead of both baselines at every scale.
PPc = PP; PPc.confirm = confirm_sel; PPc.alarm_mode = alarm_sel;
sens = struct('scale', {}, 'dqn_ret', {}, 'rule_ret', {}, 'tab_ret', {}, 'dqn_rest', {}, 'rule_rest', {}, ...
    'tab_rest', {}, 'dqn_gput', {}, 'dqn_fa', {});
for f = [1, SENS_SCALES]
    Kf = K; Kf.cost = f * K.cost; Kf.SW = f * K.SW; Kf.FA = f * K.FA;
    if f == 1
        ag = agent;
    else
        fprintf('--- reward sensitivity: costs x %.1f ---\n', f);
        Hs = H; Hs.gamma = gamma_sel;
        Kft = Kf; Kft.FA = f * fa_pen_sel;
        ag = train_one(Hs, PPc, Kft, norm_in, runs(best).seed, nS);
    end
    Vd = eval_batches('dqn', PPc, Kf, val_spec, ag, struct(), 5000);
    Vr = eval_batches('rule_esc', PPc, Kf, val_spec, [], struct(), 5000);
    Vt = eval_batches('table', PPc, Kf, val_spec, [], policy_table(PP, Kf), 5000);
    Cd = eval_batches('dqn', PPc, Kf, clean_spec, ag, struct(), 7000);
    sens(end+1) = struct('scale', f, 'dqn_ret', mean(Vd.ret), 'rule_ret', mean(Vr.ret), 'tab_ret', mean(Vt.ret), ...
        'dqn_rest', mean(Vd.restored_post), 'rule_rest', mean(Vr.restored_post), 'tab_rest', mean(Vt.restored_post), ...
        'dqn_gput', mean(Vd.gput_post), 'dqn_fa', mean(Cd.switches > 0)); %#ok<SAGROW>
end
rs2 = {'', sprintf('Reward-weight sensitivity (validation; every cost term scaled, DQN retrained per scale, seed %d):', ...
    runs(best).seed), ...
    sprintf('%-8s %22s %22s %22s %10s %8s', 'scale', 'return DQN/rule/table', 'restored DQN/rule/table', ...
    'DQN - rule / - table', 'DQN gput', 'DQN FA')};
for i = 1:numel(sens)
    x = sens(i);
    rs2{end+1} = sprintf('%-8s %22s %22s %22s %10.3f %7.1f%%', sprintf('x %.1f', x.scale), ...
        sprintf('%.3f/%.3f/%.3f', x.dqn_ret, x.rule_ret, x.tab_ret), ...
        sprintf('%.1f/%.1f/%.1f%%', 100*x.dqn_rest, 100*x.rule_rest, 100*x.tab_rest), ...
        sprintf('%+.3f / %+.3f', x.dqn_ret - x.rule_ret, x.dqn_ret - x.tab_ret), x.dqn_gput, 100*x.dqn_fa); %#ok<SAGROW>
end
holds = all([sens.dqn_ret] > [sens.rule_ret] & [sens.dqn_ret] > [sens.tab_ret]);
rs2{end+1} = sprintf('DQN ahead of rule + escalation and table at every scale: %s', ternary(holds, 'YES', 'NO'));
fid = fopen('results/dqn_training.txt', 'a'); fprintf(fid, '%s\n', rs2{:}); fclose(fid);
fprintf('%s\n', rs2{:});
save('data/trained_dqn.mat', 'sens', '-append');
fprintf('=== C2 Complete ===\n');

%% ===================== Local functions =====================
function spec = make_spec(H, PP, K, rs)
% Training / validation episodes: single threats, the clean link and the
% training combinations.
nSing = numel(PP.singles);
idx = 1:nSing;
w = ones(1, nSing); w(1) = 2; w(strcmp(PP.singles, 'benign_interference')) = 1.5;
if isfield(PP, 'train_combos')
    ic = find(ismember(PP.scen, PP.train_combos));
    idx = [idx, ic]; w = [w, 0.75 * ones(1, numel(ic))];
end
cw = cumsum(w) / sum(w);
NE = H.NE;
scn = idx(arrayfun(@(u) find(u <= cw, 1), rand(rs, 1, NE)));
spec = struct('scn', scn, 's', randi(rs, numel(PP.ebno), 1, NE), 'onset', randi(rs, [3 10], 1, NE), ...
    'follow', K.followable(scn) & rand(rs, 1, NE) < H.p_follow, 'fdelay', randi(rs, [2 5], 1, NE), ...
    'unk', scn > 1 & rand(rs, 1, NE) < H.p_unknown, 'T', H.T);
end

function R = eval_batches(kind, PP, K, specs, agent, opt, seed0)
R = [];
for b = 1:numel(specs)
    Rb = rollout_policy(kind, PP, K, specs{b}, 1, agent, opt, seed0 + b);
    Rb = rmfield(Rb, 'cfg_trace');
    if isempty(R), R = Rb; else, R = structfun_cat(R, Rb); end
end
end

function R = structfun_cat(R, Rb)
f = fieldnames(R);
for i = 1:numel(f), R.(f{i}) = [R.(f{i}), Rb.(f{i})]; end
end

function [agent, curve, loss_hist, best_ep] = train_one(H, PP, K, norm_in, seed, nS)
rng(seed, 'twister');
rs = RandStream('mt19937ar', 'Seed', seed);
agent = dqn_agent(norm_in);
net = agent.qNetwork; tgt = net;
nA = numel(PP.actions); na = K.na; nB = H.buffer; NE = H.NE;
B.S = zeros(nS, nB, 'single'); B.S2 = zeros(nS, nB, 'single'); B.M2 = false(nA, nB);
B.A = zeros(1, nB); B.R = zeros(1, nB, 'single'); B.D = zeros(1, nB, 'single');
nb = 0; ptr = 0; nupd = 0;
avgG = []; avgSq = [];
n_iter = ceil(H.episodes / NE);
loss_hist = zeros(1, n_iter * H.T * H.updates);
curve = [];
eval_spec = arrayfun(@(k) make_spec(H, PP, K, RandStream('mt19937ar', 'Seed', seed + 500 + k)), 1:H.n_eval, ...
    'UniformOutput', false);
best = -inf; best_net = net; best_ep = 0;
for it = 1:n_iter
    epsg = max(H.eps_end, 1 - (1 - H.eps_end) * (it - 1) / (H.eps_frac * n_iter));
    lr = H.lr * (H.lr_end / H.lr) ^ ((it - 1) / max(n_iter - 1, 1));
    spec = make_spec(H, PP, K, rs);
    [E, obs] = link_env('reset', PP, K, spec, 1, rs);
    mem = policy_monitor('init', NE, nA);
    [mem, M] = policy_monitor('update', mem, obs, PP);
    s = policy_state(obs, E.cfg, mem.since, M.ber_avg, M.confirmed, PP, M.drop);
    mk = policy_mask(E.cfg, M.confirmed, nA, na);
    for t = 1:H.T
        q = extractdata(predict(net, dlarray(single(s), 'CB')));
        q(~mk) = -inf;
        [~, a] = max(q, [], 1);
        ex = rand(rs, 1, NE) < epsg;
        if any(ex)
            [~, ar] = max(rand(rs, nA, NE) .* mk, [], 1);          % uniform over the allowed set
            a(ex) = ar(ex);
        end
        prev = E.cfg;
        [E, r, obs] = link_env('step', E, PP, K, a);
        ch = a ~= prev; mem.since(ch) = 0; mem.since(~ch) = mem.since(~ch) + 1;
        [mem, M] = policy_monitor('update', mem, obs, PP);
        s2 = policy_state(obs, E.cfg, mem.since, M.ber_avg, M.confirmed, PP, M.drop);
        mk2 = policy_mask(E.cfg, M.confirmed, nA, na);
        done = t == H.T;
        idx = mod(ptr + (0:NE-1), nB) + 1;
        B.S(:, idx) = s; B.S2(:, idx) = s2; B.M2(:, idx) = mk2;
        B.A(idx) = a; B.R(idx) = r; B.D(idx) = done;
        ptr = mod(ptr + NE, nB); nb = min(nb + NE, nB);
        s = s2; mk = mk2;
        if nb >= H.warmup
            for u = 1:H.updates
                j = randi(rs, nb, 1, H.batch);
                S2 = dlarray(B.S2(:, j), 'CB');
                Qo = extractdata(predict(net, S2)); Qo(~B.M2(:, j)) = -inf;
                [~, an] = max(Qo, [], 1);                                   % Double DQN: online net picks
                Qt = extractdata(predict(tgt, S2));                          % target net evaluates
                y = B.R(j) + H.gamma * (1 - B.D(j)) .* Qt(sub2ind([nA H.batch], an, 1:H.batch));
                [L, g] = dlfeval(@dqn_loss, net, dlarray(B.S(:, j), 'CB'), B.A(j), single(y), H.huber, nA);
                g = clip_gradients(g, H.clip);
                nupd = nupd + 1;
                [net, avgG, avgSq] = adamupdate(net, g, avgG, avgSq, nupd, lr);
                loss_hist(nupd) = double(extractdata(L));
                if mod(nupd, H.target_every) == 0, tgt = net; end
            end
        end
    end
    if mod(it, max(1, round(n_iter / 25))) == 0 || it == n_iter
        ag = agent; ag.qNetwork = net;
        ret = 0;
        for b = 1:H.n_eval
            Re = rollout_policy('dqn', PP, K, eval_spec{b}, 1, ag, struct(), seed + 700 + b);
            ret = ret + mean(Re.ret) / H.n_eval;
        end
        curve(end+1, :) = [it * NE, ret]; %#ok<AGROW>
        if ret > best && nb >= H.warmup, best = ret; best_net = net; best_ep = it * NE; end
        fprintf('    episode %5d/%d | eps %.2f | lr %.1e | greedy return %.3f | updates %d\n', it * NE, ...
            n_iter * NE, epsg, lr, ret, nupd);
    end
end
loss_hist = loss_hist(1:nupd);
agent.qNetwork = best_net;
end

function [L, g] = dqn_loss(net, S, A, y, delta, nA)
% Huber loss between Q(s, a) of the taken actions and the Double DQN targets y.
Q = forward(net, S);
n = numel(A);
M = zeros(nA, n, 'single'); M(sub2ind([nA n], A, 1:n)) = 1;
q = sum(Q .* M, 1);
e = stripdims(q) - y;
ae = abs(e);
L = mean(min(ae, delta) .* (ae - 0.5 * min(ae, delta)));
g = dlgradient(L, net.Learnables);
end

function g = clip_gradients(g, c)
% Global-norm gradient clipping.
n = sqrt(sum(cellfun(@(x) sum(extractdata(x).^2, 'all'), g.Value)));
if n > c, g = dlupdate(@(x) x * (c / n), g); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
