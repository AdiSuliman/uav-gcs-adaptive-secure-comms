%% EXPERIMENT_COMBO_GENERALIZATION - Combined threats never trained on
% The agent trains on every combined threat and is tested on new flights of
% them (KPI 4). This experiment measures a combination it has never seen.
% Leave-one-combination-out: for each
% combined threat the train and validation pools of that combination (every
% severity) are removed
% and a DQN is retrained with the selected settings of train_dqn.m (monitor,
% false-switch penalty, discount factor, seed; dqn_train_run.m); it is then
% tested on the test flights of the removed combination, next to the selected
% DQN (which trained on it), rule + escalation and the class table built without
% it. Recovered = BER and packet loss <= 2x clean for 5 consecutive cycles, among
% the recoverable episodes (as evaluate_policies.m). 95% intervals by bootstrap
% over geometries.
%
% Output: results/combo_generalization.{txt,mat}

close all; clc;
fprintf('=== Combined threats never trained on: leave-one-combination-out ===\n\n');
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
Q = load('data/trained_dqn.mat', 'agent', 'H', 'norm_in', 'seed_summary', 'confirm', 'alarm_mode', 'drop_db');
PP.confirm = Q.confirm; PP.alarm_mode = Q.alarm_mode;
if ~isempty(Q.drop_db), PP.drop_db = Q.drop_db; end
K = link_env('tables', PP);
TEST = 3; NE = 64; REPS = 2;
H = Q.H; H.gamma = Q.seed_summary.selected_gamma;
seed = Q.seed_summary.selected_seed;
nA = numel(PP.actions); nS = policy_state_size(nA, numel(PP.classes));
combos = PP.combos;
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    combos = combos(1); REPS = 1; H.episodes = 1280; H.buffer = 20000; H.warmup = 2000; H.n_eval = 1;
end

res = struct('combo', {}, 'n', {}, 'dqn_out', {}, 'dqn_in', {}, 'rule', {}, 'table', {}, 'ci_out', {}, 'ci_in', {});
t0 = tic;
for ci = 1:numel(combos)
    c = find(strcmp(PP.scen, combos{ci}));
    fprintf('[%d/%d] %s left out of training and validation\n', ci, numel(combos), combos{ci});
    PPx = PP;
    PPx.pools(c, :, :, 1:2) = {[]};
    Kx = link_env('tables', PPx);
    Kt = Kx; Kt.FA = Q.seed_summary.selected_fa_pen;
    if isfield(Q.seed_summary, 'selected_cost_scale')          % training reward variant
        Kt.cost = Q.seed_summary.selected_cost_scale * Kx.cost; Kt.SW = Q.seed_summary.selected_sw_scale * Kx.SW;
    end
    ag = dqn_train_run(H, PPx, Kt, Kx, Q.norm_in, seed, nS, 1, 2);
    specs = test_episodes(c, numel(PP.ebno), K.nR(TEST), REPS, NE, H.T, RandStream('mt19937ar', 'Seed', 300 + ci));
    Ro = dqn_eval_batches('dqn_esc', PP, K, specs, ag, struct(), 7000, TEST);
    Ri = dqn_eval_batches('dqn_esc', PP, K, specs, Q.agent, struct(), 7000, TEST);
    Rr = dqn_eval_batches('rule_esc', PP, K, specs, [], struct(), 7000, TEST);
    Rt = dqn_eval_batches('table', PP, K, specs, [], policy_table(PPx, Kx), 7000, TEST);
    [Ro, Ri, Rr, Rt] = deal(mark(Ro, specs, PP), mark(Ri, specs, PP), mark(Rr, specs, PP), mark(Rt, specs, PP));
    m = Ro.recoverable & Ro.threat;
    [~, lo1, hi1] = boot_cluster(double(Ro.recovered(m)), ones(1, sum(m)), Ro.geom(m), 2000, 1);
    [~, lo2, hi2] = boot_cluster(double(Ri.recovered(m)), ones(1, sum(m)), Ri.geom(m), 2000, 2);
    res(end+1) = struct('combo', combos{ci}, 'n', sum(m), 'dqn_out', mean(Ro.recovered(m)), 'dqn_in', mean(Ri.recovered(m)), ...
        'rule', mean(Rr.recovered(m)), 'table', mean(Rt.recovered(m)), 'ci_out', [lo1 hi1], 'ci_in', [lo2 hi2]); %#ok<SAGROW>
    fprintf('    recovered among %d recoverable: never trained %.1f%% | trained %.1f%% | rule+esc %.1f%% | table %.1f%% (%.1f min)\n\n', ...
        sum(m), 100*res(end).dqn_out, 100*res(end).dqn_in, 100*res(end).rule, 100*res(end).table, toc(t0)/60);
end

rep = {'=== COMBINED THREATS NEVER TRAINED ON: LEAVE-ONE-COMBINATION-OUT ==='};
rep{end+1} = sprintf(['Generated: %s | DQN retrained without the combination (train and validation pools removed), ' ...
    'selected settings: monitor %s %d/%d, penalty %d, gamma %.2f, seed %d | test flights of the combination, %d per Eb/N0'], ...
    datestr(now), PP.alarm_mode, PP.confirm, Q.seed_summary.selected_fa_pen, H.gamma, seed, K.nR(TEST));
rep{end+1} = 'Recovered = BER and packet loss <= 2x clean for 5 consecutive cycles, among recoverable episodes; [95% bootstrap over geometries].';
rep{end+1} = '';
rep{end+1} = sprintf('%-32s %6s %24s %24s %10s %10s', 'combination', 'n', 'DQN, never trained', 'DQN, trained', 'rule+esc', 'table');
for i = 1:numel(res)
    r = res(i);
    rep{end+1} = sprintf('%-32s %6d %9.1f%% [%4.1f, %4.1f] %9.1f%% [%4.1f, %4.1f] %9.1f%% %9.1f%%', r.combo, r.n, ...
        100*r.dqn_out, 100*r.ci_out, 100*r.dqn_in, 100*r.ci_in, 100*r.rule, 100*r.table); %#ok<SAGROW>
end
rep{end+1} = sprintf('%-32s %6d %9.1f%% %14s %9.1f%% %14s %9.1f%% %9.1f%%', 'mean', sum([res.n]), 100*mean([res.dqn_out]), '', ...
    100*mean([res.dqn_in]), '', 100*mean([res.rule]), 100*mean([res.table]));
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/combo_generalization.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
save('results/combo_generalization.mat', 'res');
fprintf('\nSaved results/combo_generalization.{txt,mat} (%.1f min)\n', toc(t0)/60);

%% ===================== Local functions =====================
function specs = test_episodes(c, nS, nG, reps, NE, T, rs)
% Every (cell, Eb/N0, test geometry) of the cells c (the severities of one
% combination) `reps` times, in batches of NE (cyclic padding of the last batch,
% dropped again by mark()).
[cc, s, r] = ndgrid(c(:)', 1:nS, 1:nG);
cc = repmat(cc(:)', 1, reps); s = repmat(s(:)', 1, reps); r = repmat(r(:)', 1, reps);
n = numel(s); nb = ceil(n / NE); pad = nb * NE - n;
k_ = mod(0:n + pad - 1, n) + 1; cc = cc(k_); s = s(k_); r = r(k_);
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*NE + (1:NE);
    specs{b} = struct('scn', cc(i), 's', s(i), 'r', r(i), 'onset', randi(rs, [3 10], 1, NE), ...
        'follow', false(1, NE), 'fdelay', 2 * ones(1, NE), 'unk', false(1, NE), 'T', T);
end
specs{end}.n_valid = NE - pad;
end

function R = mark(R, specs, PP)
% Geometry id per episode (for the bootstrap); padding of the last batch dropped.
g = cell2mat(cellfun(@(sp) sp.s * 1000 + sp.r, specs, 'UniformOutput', false));
n = numel(g) - (numel(specs{end}.scn) - specs{end}.n_valid);
f = fieldnames(R);
for i = 1:numel(f)
    if size(R.(f{i}), 2) == numel(g), R.(f{i}) = R.(f{i})(:, 1:n); end
end
R.geom = g(1:n);
R.threat = true(1, n) & ~strcmp(PP.scen(specs{1}.scn(1)), 'none');
end
