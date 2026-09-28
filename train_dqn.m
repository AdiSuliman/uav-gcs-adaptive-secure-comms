%% C2 - TRAIN DQN: sequential decision layer on measured frame pools (D44-D52, D59)
% Double DQN (van Hasselt et al., AAAI 2016) with experience replay and a target
% network (Mnih et al., Nature 2015) on link_env.m: 30-cycle episodes inside one
% seeded flight geometry, the threat (any severity, or a training combination)
% starts at a random cycle, a follower jammer re-acquires the channel after each
% hop (the intelligent jammer of Liu et al., 2018), and the agent sees what the
% receiver measures over the last cycles (policy_state.m): detector class
% probabilities, unknown flag, estimated BER, packet loss, SINR, IoT, spatial
% measurements, its own configuration, the time since its last change and the
% confirmed alarm. The shield of policy_mask.m applies in training exactly as in
% deployment, and the Double DQN target maximizes over the configurations allowed
% in the next state.
% Data: the TRAIN split of data/policy_pools.mat for learning; the VALIDATION split
% (geometries never used in training) for checkpoints and selection; the test
% split and the test combinations are kept for evaluate_policies.m.
%
% Grid: alarm definition (CFG.alarm_modes, policy_monitor.m) x false-switch
% penalty of the TRAINING reward (CFG.fa_penalty_grid) x CFG.dqn_gammas x
% CFG.dqn_seeds. Every run keeps the checkpoint with the best recovery on its own
% validation episodes; all runs are compared on the validation set: recovered
% episodes among the recoverable threat episodes (proposal KPI: BER and packet
% loss back to <= 2x clean) and false alarms on the independent clean validation
% geometries (data/clean_val_pools.mat, one episode per geometry).
% Selection: among the runs whose one-sided 95% false-alarm bound is <= 5% (KPI 6
% as worded), the best validation recovery; a return within 0.005 breaks ties.
% Gate: recovery >= rule + escalation with the same alarm and the false-alarm
% bound. The best run of every gamma at the selected alarm and penalty is kept as
% an ablation. Reward-weight sensitivity: proposal mitigation 2.
%
% Output: data/trained_dqn.mat, results/dqn_training.txt, results/dqn_training_curves.png

close all; clc;
fprintf('=== C2: Train DQN (D44-D52, D59) ===\n\n');
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
N_SEEDS = 3; GAMMAS = [0.5 0.9]; FA_PEN = [20 80];
ALARMS = {'class', 'class_drop'};
SENS_SCALES = [0.5 2];                   % reward-weight sensitivity: cost terms x scale
if exist('CFG', 'var') && isstruct(CFG)
    if isfield(CFG, 'dqn_seeds'), N_SEEDS = CFG.dqn_seeds; end
    if isfield(CFG, 'dqn_gammas'), GAMMAS = CFG.dqn_gammas; end
    if isfield(CFG, 'fa_penalty_grid'), FA_PEN = CFG.fa_penalty_grid; end
    if isfield(CFG, 'alarm_modes'), ALARMS = CFG.alarm_modes; end
    if isfield(CFG, 'dqn_episodes'), H.episodes = CFG.dqn_episodes; end
end
N_VAL = 24;                              % validation batches of H.NE episodes (validation split)
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    N_SEEDS = 1; GAMMAS = 0.5; FA_PEN = 80; ALARMS = {'class_drop'}; SENS_SCALES = 2; N_VAL = 2;
    H.episodes = 1280; H.buffer = 20000; H.warmup = 2000; H.n_eval = 1;
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
    spec = make_spec(H, PP, K, rs, SPLIT_TRAIN);
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
rv = RandStream('mt19937ar', 'Seed', 99);
val_spec = cell(1, N_VAL);
for b = 1:N_VAL, val_spec{b} = make_spec(H, PP, K, rv, SPLIT_VAL); end
tab = policy_table(PP, K);

%% 4. Training: alarm x false-switch penalty x discount factor x seeds
runs = struct('alarm', {}, 'fa_pen', {}, 'gamma', {}, 'seed', {}, 'agent', {}, 'curve', {}, 'loss', {}, ...
    'best_ep', {}, 'val', {}, 'rec', {}, 'fa_w', {}, 'n_w', {});
base = struct('alarm', {}, 'rule_rec', {}, 'rule_ret', {}, 'rule_fa_w', {}, 'tab_rec', {}, 'tab_ret', {}, 'tab_fa_w', {});
for ai = 1:numel(ALARMS)
    PPc = PP; PPc.alarm_mode = ALARMS{ai};
    Rr = eval_batches('rule_esc', PPc, K, val_spec, [], struct(), 5000, SPLIT_VAL);
    Rt = eval_batches('table', PPc, K, val_spec, [], tab, 5000, SPLIT_VAL);
    [rw, ~] = eval_clean_wide('rule_esc', PPc, CV, [], struct(), H);
    [tw, ~] = eval_clean_wide('table', PPc, CV, [], tab, H);
    base(end+1) = struct('alarm', ALARMS{ai}, 'rule_rec', rec_rate(Rr), 'rule_ret', mean(Rr.ret), 'rule_fa_w', rw, ...
        'tab_rec', rec_rate(Rt), 'tab_ret', mean(Rt.ret), 'tab_fa_w', tw); %#ok<SAGROW>
    fprintf('=== Alarm ''%s'': rule+esc recovered %.1f%%, return %.3f, FA %s | table recovered %.1f%%, return %.3f\n', ...
        ALARMS{ai}, 100*base(end).rule_rec, base(end).rule_ret, pct_txt(rw), 100*base(end).tab_rec, base(end).tab_ret);
    for fp = FA_PEN
        Kt = K; Kt.FA = fp;                            % training reward only
        for g = GAMMAS
            for k = 1:N_SEEDS
                fprintf('--- alarm ''%s'', false-switch penalty %d, gamma %.2f, seed %d ---\n', ALARMS{ai}, fp, g, SEEDS(k));
                Hg = H; Hg.gamma = g;
                [ag, curve, lossc, best_ep] = train_one(Hg, PPc, Kt, K, norm_in, SEEDS(k), nS, SPLIT_TRAIN, SPLIT_VAL);
                V = eval_batches('dqn', PPc, K, val_spec, ag, struct(), 5000, SPLIT_VAL);
                [fa_w, n_w] = eval_clean_wide('dqn', PPc, CV, ag, struct(), H);
                fprintf('    checkpoint %d | validation: recovered %.1f%% | restored %.1f%% | return %.3f | FA %s\n', ...
                    best_ep, 100*rec_rate(V), 100*mean(V.restored_post), mean(V.ret), fa_txt(fa_w, n_w));
                runs(end+1) = struct('alarm', ALARMS{ai}, 'fa_pen', fp, 'gamma', g, 'seed', SEEDS(k), 'agent', ag, ...
                    'curve', curve, 'loss', lossc, 'best_ep', best_ep, 'val', V, 'rec', rec_rate(V), ...
                    'fa_w', fa_w, 'n_w', n_w); %#ok<SAGROW>
            end
        end
    end
end
vrec = [runs.rec]; vret = arrayfun(@(r) mean(r.val.ret), runs);
fa_ok = arrayfun(@(r) isnan(r.fa_w) || cp_upper(round(r.fa_w * r.n_w), r.n_w) <= FA_BOUND, runs);
cand = find(fa_ok);
if isempty(cand)
    [~, o] = sort([runs.fa_w]); cand = o(1:min(3, numel(o)));
    sel_rule = 'no run met the false-alarm bound: the three with the fewest false alarms, then the best recovery';
else
    sel_rule = sprintf('best validation recovery among runs with a one-sided 95%% false-alarm bound <= %.0f%%', 100*FA_BOUND);
end
top = cand(vrec(cand) >= max(vrec(cand)) - 0.005);
[~, j] = max(vret(top)); best = top(j);
agent = runs(best).agent;
gamma_sel = runs(best).gamma; fa_pen_sel = runs(best).fa_pen; alarm_sel = runs(best).alarm;
agents = cell(1, numel(GAMMAS));                     % best run per discount factor at the chosen alarm and penalty
for gi = 1:numel(GAMMAS)
    m = find([runs.gamma] == GAMMAS(gi) & [runs.fa_pen] == fa_pen_sel & strcmp({runs.alarm}, alarm_sel));
    mk = m(fa_ok(m)); if isempty(mk), mk = m; end
    [~, jj] = max(vrec(mk));
    agents{gi} = runs(mk(jj)).agent;
end
agents{find(GAMMAS == gamma_sel, 1)} = agent;

%% 5. Gate and report
bsel = base(strcmp({base.alarm}, alarm_sel));
gate = vrec(best) >= bsel.rule_rec && fa_ok(best);
rep = {};
rep{end+1} = '=== DQN TRAINING (D44-D52, D59) ===';
rep{end+1} = sprintf(['Generated: %s | Double DQN + shield, state history %d cycles, hidden %s, replay %d, target every ' ...
    '%d updates, lr %.0e -> %.0e, %d episodes x %d cycles | alarm %s x penalty %s x gamma %s x %d seeds'], ...
    datestr(now), CD.hist, mat2str(H.hidden), H.buffer, H.target_every, H.lr, H.lr_end, H.episodes, H.T, ...
    strjoin(ALARMS, '/'), mat2str(FA_PEN), mat2str(GAMMAS), N_SEEDS);
rep{end+1} = 'False-switch penalty: training reward only; validation and test use the standard reward.';
rep{end+1} = sprintf(['Validation: %d episodes on the VALIDATION split (geometries never used in training): single ' ...
    'threats at three severities, training combinations, clean link. Recovered = BER and packet loss <= 2x clean ' ...
    'for 5 consecutive cycles, among recoverable threat episodes. FA: false-alarm episodes on %s independent clean ' ...
    'validation geometries (data/clean_val_pools.mat).'], N_VAL * H.NE, n_txt(CV, PP));
if ~isempty(DROP_DB), rep{end+1} = sprintf('''class_drop'': path_loss alarm after an Eb/N0 drop >= %.1f dB (data/drop_threshold.mat)', DROP_DB); end
rep{end+1} = sprintf('%-40s %10s %10s %9s %14s %12s', 'run', 'recovered', 'restored', 'return', 'FA indep.', 'switches/ep');
for k = 1:numel(runs)
    R = runs(k).val;
    rep{end+1} = sprintf('%-40s %9.1f%% %9.1f%% %9.3f %14s %12.2f   (checkpoint %d)', ...
        sprintf('%s pen %d g=%.2f seed %d', runs(k).alarm, runs(k).fa_pen, runs(k).gamma, runs(k).seed), ...
        100*runs(k).rec, 100*mean(R.restored_post), mean(R.ret), fa_txt(runs(k).fa_w, runs(k).n_w), ...
        mean(R.switches), runs(k).best_ep); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = 'Baselines on the same validation episodes:';
for ai = 1:numel(base)
    rep{end+1} = sprintf('  %-12s rule + escalation: recovered %.1f%%, return %.3f, FA %s | table: recovered %.1f%%, return %.3f, FA %s', ...
        base(ai).alarm, 100*base(ai).rule_rec, base(ai).rule_ret, pct_txt(base(ai).rule_fa_w), 100*base(ai).tab_rec, ...
        base(ai).tab_ret, pct_txt(base(ai).tab_fa_w)); %#ok<SAGROW>
end
rep{end+1} = sprintf(['Selected: alarm ''%s'', false-switch penalty %d, gamma %.2f, seed %d (%s). Gate (recovery >= ' ...
    'rule + escalation with the same alarm, false-alarm bound <= %.0f%%): %s'], alarm_sel, fa_pen_sel, gamma_sel, ...
    runs(best).seed, sel_rule, 100*FA_BOUND, ternary(gate, 'PASS', 'FAIL'));
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/dqn_training.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
if ~gate, warning('train_dqn:gate', 'DQN validation gate FAILED -- see results/dqn_training.txt'); end

seed_summary = struct('alarms', {{runs.alarm}}, 'fa_pens', [runs.fa_pen], 'gammas', [runs.gamma], ...
    'seeds', [runs.seed], 'val_recovered', vrec, 'val_return', vret, 'fa_indep', [runs.fa_w], 'n_indep', [runs.n_w], ...
    'best_ep', [runs.best_ep], 'selected_alarm', alarm_sel, 'selected_fa_pen', fa_pen_sel, 'selected_gamma', gamma_sel, ...
    'selected_seed', runs(best).seed, 'selection_rule', sel_rule, 'gate_pass', gate, ...
    'rule_recovered', bsel.rule_rec, 'rule_return', bsel.rule_ret, 'table_return', bsel.tab_ret);
H.gamma = gamma_sel; H.fa_pen = fa_pen_sel;
action_names = PP.actions;
gammas = GAMMAS;
confirm = CD.confirm;
alarm_mode = alarm_sel;
drop_db = DROP_DB;
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
PPc = PP; PPc.alarm_mode = alarm_sel;
sens = struct('scale', {}, 'dqn_rec', {}, 'rule_rec', {}, 'tab_rec', {}, 'dqn_ret', {}, 'dqn_gput', {});
for f = [1, SENS_SCALES]
    Kf = K; Kf.cost = f * K.cost; Kf.SW = f * K.SW; Kf.FA = f * K.FA;
    if f == 1
        ag = agent;
    else
        fprintf('--- reward sensitivity: costs x %.1f ---\n', f);
        Hs = H; Hs.gamma = gamma_sel;
        Kft = Kf; Kft.FA = f * fa_pen_sel;
        ag = train_one(Hs, PPc, Kft, Kf, norm_in, runs(best).seed, nS, SPLIT_TRAIN, SPLIT_VAL);
    end
    Vd = eval_batches('dqn', PPc, Kf, val_spec, ag, struct(), 5000, SPLIT_VAL);
    Vr = eval_batches('rule_esc', PPc, Kf, val_spec, [], struct(), 5000, SPLIT_VAL);
    Vt = eval_batches('table', PPc, Kf, val_spec, [], policy_table(PP, Kf), 5000, SPLIT_VAL);
    sens(end+1) = struct('scale', f, 'dqn_rec', rec_rate(Vd), 'rule_rec', rec_rate(Vr), 'tab_rec', rec_rate(Vt), ...
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
function spec = make_spec(H, PP, K, rs, split)
% Episodes on the cells present in the split: single threats (every severity),
% the clean link and the training combinations; the test combinations never.
avail = find(~cellfun(@isempty, PP.pools(:, 1, K.na, split))');
avail = avail(~ismember(PP.scen(avail), PP.combos));
w = ones(1, numel(avail));
w(strcmp(PP.scen(avail), 'none')) = 4;              % the clean link as often as a threat at all severities
w(strcmp(PP.scen(avail), 'benign_interference')) = 1.5;
w(ismember(PP.scen(avail), PP.train_combos)) = 2;
cw = cumsum(w) / sum(w);
NE = H.NE;
scn = avail(arrayfun(@(u) find(u <= cw, 1), rand(rs, 1, NE)));
spec = struct('scn', scn, 's', randi(rs, numel(PP.ebno), 1, NE), 'onset', randi(rs, [3 10], 1, NE), ...
    'follow', K.followable(scn) & rand(rs, 1, NE) < H.p_follow, 'fdelay', randi(rs, [2 5], 1, NE), ...
    'unk', ~strcmp(PP.scen(scn), 'none') & rand(rs, 1, NE) < H.p_unknown, 'T', H.T);
end

function r = rec_rate(R)
% Recovered episodes among the recoverable threat episodes.
m = R.recoverable & R.threat;
r = mean(R.recovered(m));
end

function R = eval_batches(kind, PP, K, specs, agent, opt, seed0, split)
R = [];
for b = 1:numel(specs)
    Rb = rollout_policy(kind, PP, K, specs{b}, split, agent, opt, seed0 + b);
    Rb = rmfield(Rb, 'cfg_trace');
    Rb.threat = ~strcmp(PP.scen(specs{b}.scn), 'none');
    if isempty(R), R = Rb; else, R = structfun_cat(R, Rb); end
end
end

function R = structfun_cat(R, Rb)
f = fieldnames(R);
for i = 1:numel(f), R.(f{i}) = [R.(f{i}), Rb.(f{i})]; end
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
ss = [ss, ss(1:pad)]; rr = [rr, rr(1:pad)];
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
persistent key cache
k = sprintf('%s|%s', CT.created, PP.created);
if isequal(key, k), PPw = cache.PPw; Kw = cache.Kw; return; end
nS = numel(PP.ebno); nA = numel(PP.actions);
PPw = PP;
PPw.pools(:, :, :, 2) = {[]};
ic = find(strcmp(PP.scen, 'none'), 1);
PPw.pools(ic, :, :, 2) = reshape(CT.pools(1, :, :), [1 nS nA]);
PPw.runs{2} = CT.runs;
Kw = link_env('tables', PPw);
key = k; cache = struct('PPw', PPw, 'Kw', Kw);
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

function [agent, curve, loss_hist, best_ep] = train_one(H, PP, K, Kval, norm_in, seed, nS, split_tr, split_val)
% One training run; K is the training reward, Kval the standard reward for the
% validation checkpoints (recovered episodes, then return).
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
eval_spec = arrayfun(@(k) make_spec(H, PP, K, RandStream('mt19937ar', 'Seed', seed + 500 + k), split_val), ...
    1:H.n_eval, 'UniformOutput', false);
best = -inf; best_net = net; best_ep = 0;
for it = 1:n_iter
    epsg = max(H.eps_end, 1 - (1 - H.eps_end) * (it - 1) / (H.eps_frac * n_iter));
    lr = H.lr * (H.lr_end / H.lr) ^ ((it - 1) / max(n_iter - 1, 1));
    spec = make_spec(H, PP, K, rs, split_tr);
    [E, obs] = link_env('reset', PP, K, spec, split_tr, rs);
    mem = policy_monitor('init', NE, nA);
    [mem, M] = policy_monitor('update', mem, obs, PP, E.cfg);
    s = policy_state(mem, E.cfg, M.confirmed, nA);
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
        [mem, M] = policy_monitor('update', mem, obs, PP, E.cfg);
        s2 = policy_state(mem, E.cfg, M.confirmed, nA);
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
        Re = eval_batches('dqn', PP, Kval, eval_spec, ag, struct(), seed + 700, split_val);
        sc = rec_rate(Re) + 1e-3 * mean(Re.ret);
        curve(end+1, :) = [it * NE, rec_rate(Re)]; %#ok<AGROW>
        if sc > best && nb >= H.warmup, best = sc; best_net = net; best_ep = it * NE; end
        fprintf('    episode %5d/%d | eps %.2f | lr %.1e | validation recovered %.1f%% return %.3f | updates %d\n', ...
            it * NE, n_iter * NE, epsg, lr, 100 * rec_rate(Re), mean(Re.ret), nupd);
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
