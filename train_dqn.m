%% C2 - TRAIN DQN: sequential decision layer on measured frame pools (D44, D45)
% Double DQN (van Hasselt et al., AAAI 2016) with experience replay and a target
% network (Mnih et al., Nature 2015 [7]) on link_env.m: 30-cycle episodes inside
% one seeded flight geometry, the threat starts at a random cycle, a follower
% jammer re-acquires the channel after each hop (Liu et al. [6], Yuan et al. [5]),
% and the agent sees what the detector sees (class probabilities, unknown flag),
% the link features, its own configuration, the time since its last change and
% the confirmed alarm (policy_state.m). The shield of policy_mask.m applies in
% training exactly as in deployment: without a confirmed alarm the agent can only
% keep its configuration or release it, and the Double DQN target maximizes over
% the configurations allowed in the next state.
% Training uses the train split of data/policy_pools.mat and single threats
% only; combined threats and the test split are kept for evaluate_policies.m.
%
% Seeds: CFG.dqn_seeds (default 3). Each seed keeps the checkpoint with the best
% greedy return on its own evaluation episodes (train pools), then all seeds are
% compared on 1280 validation episodes (train pools, fresh draws) with the rule
% and table baselines. Selected: the best validation return among the seeds with
% no more false-alarm episodes than max(5%, rule + escalation). A myopic variant
% (gamma = 0, same network, data and shield) is the contextual-bandit ablation.
%
% Output: data/trained_dqn.mat, results/dqn_training.txt, results/dqn_training_curves.png

close all; clc;
fprintf('=== C2: Train sequential DQN (D44, D45) ===\n\n');
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
K = link_env('tables', PP);
nA = numel(PP.actions);
[nS, cont] = policy_state_size(nA);

%% 1. Hyperparameters
H = struct('gamma', 0.9, 'NE', 64, 'T', 30, 'episodes', 12000, 'buffer', 150000, 'warmup', 6000, ...
    'batch', 128, 'updates', 4, 'lr', 5e-4, 'lr_end', 5e-5, 'clip', 10, 'target_every', 500, ...
    'eps_end', 0.05, 'eps_frac', 0.6, 'huber', 1, 'p_unknown', 0.10, 'p_follow', 0.5, 'n_eval', 4);
N_SEEDS = 3;
if exist('CFG', 'var') && isstruct(CFG) && isfield(CFG, 'dqn_seeds'), N_SEEDS = CFG.dqn_seeds; end
SEEDS = 42 + (0:N_SEEDS-1);
N_VAL = 20;                              % validation batches of H.NE episodes

%% 2. State normalization from random-policy rollouts
rs = RandStream('mt19937ar', 'Seed', 7);
S_all = [];
for b = 1:20
    spec = make_spec(H, PP, K, rs);
    [E, obs] = link_env('reset', PP, K, spec, 1, rs);
    mem = policy_monitor('init', H.NE, nA);
    for t = 1:H.T
        [mem, M] = policy_monitor('update', mem, obs, PP);
        S_all = [S_all, policy_state(obs, E.cfg, mem.since, M.ber_avg, M.confirmed, PP)]; %#ok<AGROW>
        a = randi(rs, nA, 1, H.NE);
        ch = a ~= E.cfg; mem.since(ch) = 0; mem.since(~ch) = mem.since(~ch) + 1;
        [E, ~, obs] = link_env('step', E, PP, K, a);
    end
end
norm_in = struct('mu', zeros(nS, 1), 'sd', ones(nS, 1));
norm_in.mu(cont) = mean(S_all(cont, :), 2);
norm_in.sd(cont) = max(std(S_all(cont, :), 0, 2), 1e-3);

%% 3. Validation episodes and baselines (same for every seed)
val_spec = cell(1, N_VAL);
rv = RandStream('mt19937ar', 'Seed', 99);
for b = 1:N_VAL, val_spec{b} = make_spec(H, PP, K, rv); end
healthy_ep = arrayfun(@(b) val_spec{b}.scn == 1, 1:N_VAL, 'UniformOutput', false);
hv = [healthy_ep{:}];
tab = policy_table(PP, K);
Rrule = eval_batches('rule_esc', PP, K, val_spec, [], struct(), 5000);
Rtab = eval_batches('table', PP, K, val_spec, [], tab, 5000);
fa_rule = mean(Rrule.false_sw(hv) > 0);
fa_limit = max(0.05, fa_rule);
fprintf('Rule + escalation on validation: return %.3f, restored %.1f%%, false-alarm episodes %.1f%%\n', ...
    mean(Rrule.ret), 100*mean(Rrule.restored_post), 100*fa_rule);
fprintf('Table on validation:             return %.3f, restored %.1f%%\n\n', mean(Rtab.ret), 100*mean(Rtab.restored_post));

%% 4. Training
runs = struct('seed', {}, 'agent', {}, 'curve', {}, 'loss', {}, 'best_ep', {}, 'val', {}, 'fa', {});
for k = 1:N_SEEDS
    fprintf('--- Seed %d (%d/%d) ---\n', SEEDS(k), k, N_SEEDS);
    [ag, curve, lossc, best_ep] = train_one(H, PP, K, norm_in, SEEDS(k), nS);
    V = eval_batches('dqn', PP, K, val_spec, ag, struct(), 5000);
    fa = mean(V.false_sw(hv) > 0);
    fprintf('    checkpoint at episode %d | validation: return %.3f | restored %.1f%% | goodput %.3f | false-alarm episodes %.1f%%\n', ...
        best_ep, mean(V.ret), 100*mean(V.restored_post), mean(V.gput_post), 100*fa);
    runs(end+1) = struct('seed', SEEDS(k), 'agent', ag, 'curve', curve, 'loss', lossc, 'best_ep', best_ep, ...
        'val', V, 'fa', fa); %#ok<SAGROW>
end
vret = arrayfun(@(r) mean(r.val.ret), runs);
ok_fa = [runs.fa] <= fa_limit;
cand = find(ok_fa); if isempty(cand), cand = 1:N_SEEDS; end
[~, j] = max(vret(cand)); best = cand(j);
agent = runs(best).agent;
fprintf('\n--- Contextual-bandit ablation (gamma = 0) ---\n');
Hb = H; Hb.gamma = 0;
agent_bandit = train_one(Hb, PP, K, norm_in, SEEDS(1), nS);
Vb = eval_batches('dqn', PP, K, val_spec, agent_bandit, struct(), 5000);

%% 5. Gate and report
Vd = runs(best).val;
gate = mean(Vd.ret) >= mean(Rrule.ret) && runs(best).fa <= fa_limit;
rep = {};
rep{end+1} = '=== SEQUENTIAL DQN TRAINING (D44, D45) ===';
rep{end+1} = sprintf(['Generated: %s | Double DQN + shield, replay %d, target every %d updates, gamma %.2f, ' ...
    'lr %.0e -> %.0e, %d episodes x %d cycles, %d seeds'], datestr(now), H.buffer, H.target_every, H.gamma, ...
    H.lr, H.lr_end, H.episodes, H.T, N_SEEDS);
rep{end+1} = sprintf('Validation: %d episodes (train pools, fresh draws), single threats + clean link', N_VAL * H.NE);
rep{end+1} = sprintf('%-22s %9s %10s %9s %13s %13s %12s', 'policy', 'return', 'restored', 'goodput', ...
    'false sw/ep', 'FA episodes', 'switches/ep');
line = @(n, R) sprintf('%-22s %9.3f %9.1f%% %9.3f %13.3f %12.1f%% %12.2f', n, mean(R.ret), 100*mean(R.restored_post), ...
    mean(R.gput_post), mean(R.false_sw), 100*mean(R.false_sw(hv) > 0), mean(R.switches));
for k = 1:N_SEEDS
    rep{end+1} = [line(sprintf('DQN seed %d', runs(k).seed), runs(k).val) ...
        sprintf('   (checkpoint %d)', runs(k).best_ep)]; %#ok<SAGROW>
end
rep{end+1} = line('DQN gamma=0 (bandit)', Vb);
rep{end+1} = line('table (train pools)', Rtab);
rep{end+1} = line('rule + escalation', Rrule);
rep{end+1} = sprintf('Seed return spread: %.3f to %.3f (std %.3f)', min(vret), max(vret), std(vret));
rep{end+1} = sprintf(['Selected seed %d. Gate (return >= rule+escalation, false-alarm episodes <= %.1f%% = ' ...
    'max(5%%, rule): %.1f%%): %s'], runs(best).seed, 100*fa_limit, 100*runs(best).fa, ternary(gate, 'PASS', 'FAIL'));
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/dqn_training.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
if ~gate, warning('train_dqn:gate', 'DQN validation gate FAILED -- see results/dqn_training.txt'); end

seed_summary = struct('seeds', SEEDS, 'val_return', vret, 'fa', [runs.fa], 'fa_limit', fa_limit, ...
    'best_ep', [runs.best_ep], 'selected_seed', runs(best).seed, 'gate_pass', gate);
action_names = PP.actions;
save('data/trained_dqn.mat', 'agent', 'agent_bandit', 'H', 'norm_in', 'seed_summary', 'action_names', 'tab', '-v7.3');
fprintf('Saved data/trained_dqn.mat\n');

fig = figure('Position', [100 100 1000 380], 'Color', 'w');
subplot(1, 2, 1); hold on; grid on;
for k = 1:N_SEEDS, plot(runs(k).curve(:, 1), runs(k).curve(:, 2), 'LineWidth', 1.2); end
for k = 1:N_SEEDS
    c = runs(k).curve; [~, m] = max(c(:, 2));
    plot(c(m, 1), c(m, 2), 'ko', 'MarkerSize', 6, 'HandleVisibility', 'off');
end
yline(mean(Rrule.ret), 'k--', 'rule + escalation (validation)');
xlabel('Episode'); ylabel(sprintf('Mean reward per cycle (greedy, %d episodes)', H.n_eval * H.NE));
title('Learning curves (o = kept checkpoint)');
legend(arrayfun(@(r) sprintf('seed %d', r.seed), runs, 'UniformOutput', false), 'Location', 'southeast');
subplot(1, 2, 2); plot(movmean(runs(best).loss, 200)); grid on;
xlabel('Update'); ylabel('Huber loss (moving mean 200)'); title(sprintf('Q-loss, seed %d', runs(best).seed));
saveas(fig, 'results/dqn_training_curves.png'); close(fig);
fprintf('=== C2 Complete ===\n');

%% ===================== Local functions =====================
function spec = make_spec(H, PP, K, rs)
% Training / validation episodes: single threats and the clean link.
nSing = numel(PP.singles);
w = ones(1, nSing); w(1) = 2; w(strcmp(PP.singles, 'benign_interference')) = 1.5;
cw = cumsum(w) / sum(w);
NE = H.NE;
scn = arrayfun(@(u) find(u <= cw, 1), rand(rs, 1, NE));
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
    s = policy_state(obs, E.cfg, mem.since, M.ber_avg, M.confirmed, PP);
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
        s2 = policy_state(obs, E.cfg, mem.since, M.ber_avg, M.confirmed, PP);
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
