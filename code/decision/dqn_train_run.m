function [agent, curve, loss_hist, best_ep] = dqn_train_run(H, PP, K, Kval, norm_in, seed, nS, split_tr, split_val)
%DQN_TRAIN_RUN  One Double DQN training run (Mnih et al., van Hasselt
%   et al.): experience replay, target network, Huber loss, gradient clipping,
%   epsilon-greedy over the configurations the shield allows (policy_mask.m). K is
%   the training reward, Kval the standard reward of the validation checkpoints;
%   the checkpoint with the best validation recovery (then return) is kept.
rng(seed, 'twister');
rs = RandStream('mt19937ar', 'Seed', seed);
agent = dqn_agent(norm_in, H.hidden);
net = agent.qNetwork; tgt = net;
nA = numel(PP.actions); na = K.na; nB = H.buffer; NE = H.NE;
B.S = zeros(nS, nB, 'single'); B.S2 = zeros(nS, nB, 'single'); B.M2 = false(nA, nB);
B.A = zeros(1, nB); B.R = zeros(1, nB, 'single'); B.D = zeros(1, nB, 'single');
nb = 0; ptr = 0; nupd = 0;
avgG = []; avgSq = [];
n_iter = ceil(H.episodes / NE);
loss_hist = zeros(1, n_iter * H.T * H.updates);
curve = [];
eval_spec = arrayfun(@(k) dqn_episode_spec(H, PP, K, RandStream('mt19937ar', 'Seed', seed + 500 + k), split_val), ...
    1:H.n_eval, 'UniformOutput', false);
best = -inf; best_net = net; best_ep = 0;
for it = 1:n_iter
    epsg = max(H.eps_end, 1 - (1 - H.eps_end) * (it - 1) / (H.eps_frac * n_iter));
    lr = H.lr * (H.lr_end / H.lr) ^ ((it - 1) / max(n_iter - 1, 1));
    spec = dqn_episode_spec(H, PP, K, rs, split_tr);
    [E, obs] = link_env('reset', PP, K, spec, split_tr, rs);
    mem = policy_monitor('init', NE, nA);
    [mem, M] = policy_monitor('update', mem, obs, PP, E.cfg);
    s = policy_state(mem, E.cfg, M.confirmed, nA);
    mk = policy_mask(E.cfg, M.confirmed, mem.since, nA, na);
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
        [mem, M] = policy_monitor('update', mem, obs, PP, E.cfg);
        s2 = policy_state(mem, E.cfg, M.confirmed, nA);
        mk2 = policy_mask(E.cfg, M.confirmed, mem.since, nA, na);
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
        Re = dqn_eval_batches('dqn_esc', PP, Kval, eval_spec, ag, struct(), seed + 700, split_val);
        sc = dqn_recovered(Re) + 1e-3 * mean(Re.ret);
        curve(end+1, :) = [it * NE, dqn_recovered(Re)]; %#ok<AGROW>
        if sc > best && nb >= H.warmup, best = sc; best_net = net; best_ep = it * NE; end
        fprintf('    episode %5d/%d | eps %.2f | lr %.1e | validation recovered %.1f%% return %.3f | updates %d\n', ...
            it * NE, n_iter * NE, epsg, lr, 100 * dqn_recovered(Re), mean(Re.ret), nupd);
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
