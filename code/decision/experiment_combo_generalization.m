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
% over geometries. The trained agent and the pools come from the same detector
% (check_det_id.m).
% Every combination is one entity (run_cache.m 'each'): with "run_cache": true in profile.json
% or CFG.run_cache each is kept in data/run_cache/C2g as it finishes, an entity that stops is
% reported while the others still run, and the stage then stops naming it; started again, only
% the entities not kept are computed. Without it the first error stops at once, naming its
% combination. The smoke runs the first combination only, or every one (still reduced) with
% CFG.smoke_all_entities = true.
%
% Output: results/combo_generalization.{txt,mat}

close all; clc;
fprintf('=== Combined threats never trained on: leave-one-combination-out ===\n\n');
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
Q = load('data/trained_dqn.mat', 'agent', 'H', 'norm_in', 'seed_summary', 'confirm', 'alarm_mode', 'drop_db', 'det_id', 'maha_thr', ...
    'dec', 'deployed');
check_det_id(PP, Q, 'experiment_combo_generalization');
PP = decision_settings(PP, Q);                       % the agent's monitor and decision-time settings (train_dqn.m)
DK = 'dqn_esc'; if isfield(Q, 'deployed') && strcmp(Q.deployed, 'dqn'), DK = 'dqn'; end   % the DQN as selected
LBC = isfield(Q, 'dec') && isstruct(Q.dec) && isfield(Q.dec, 'lb_complete');   % C2 stored the link-budget completion's switch (train_dqn.m)
K = link_env('tables', PP);
TEST = 3; NE = 64; REPS = 2;
H = Q.H; H.gamma = Q.seed_summary.selected_gamma;
seed = Q.seed_summary.selected_seed;
nA = numel(PP.actions); nS = policy_state_size(nA, numel(PP.classes));
combos = PP.combos;
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    if ~(exist('CFG', 'var') && isstruct(CFG) && isfield(CFG, 'smoke_all_entities') && isequal(CFG.smoke_all_entities, true))
        combos = combos(1);               % CFG.smoke_all_entities: every entity, still reduced
    end
    REPS = 1; H.episodes = 1280; H.buffer = 20000; H.warmup = 2000; H.n_eval = 1;
end

res = struct('combo', {}, 'n', {}, 'dqn_out', {}, 'dqn_in', {}, 'rule', {}, 'table', {}, 'ci_out', {}, 'ci_in', {});
if LBC
    res = struct('combo', {}, 'n', {}, 'dqn_out', {}, 'dqn_in', {}, 'rule', {}, 'table', {}, 'ci_out', {}, 'ci_in', {}, ...
        'dqn_out_lb', {}, 'dqn_in_lb', {}, 'ci_out_lb', {}, 'ci_in_lb', {});
end
cfgc = []; if exist('CFG', 'var'), cfgc = CFG; end
CDIR = run_cache('dir', run_cache('on', cfgc), 'C2g'); CID = '';     % every combination kept as it finishes (run_cache.m)
if ~isempty(CDIR), CID = run_cache('inputs', {'data/policy_pools.mat', 'data/trained_dqn.mat'}); end
lbkey = {}; if LBC, lbkey = {'lb_columns'}; end          % the entities' results hold the completion's columns
keys = cellfun(@(cn) run_cache('key', [{CID, 'C2g', cn, H, seed, REPS, NE, TEST, DK}, lbkey]), combos, 'UniformOutput', false);
t0 = tic;
out = run_cache('each', CDIR, keys, @(ci) one_combo(ci, combos, PP, K, Q, H, seed, nS, TEST, REPS, NE, DK, t0, LBC), combos);
for ci = 1:numel(combos), res(end+1) = out{ci}; end %#ok<SAGROW>

rep = {'=== COMBINED THREATS NEVER TRAINED ON: LEAVE-ONE-COMBINATION-OUT ==='};
rep{end+1} = sprintf(['Generated: %s | DQN retrained without the combination (train and validation pools removed), ' ...
    'selected settings: monitor %s %d/%d, penalty %d, gamma %.2f, seed %d | test flights of the combination, %d per Eb/N0'], ...
    datestr(now), PP.alarm_mode, PP.confirm, Q.seed_summary.selected_fa_pen, H.gamma, seed, numel(K.geo{K.clean, TEST}));
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
if LBC
    rep{end+1} = '';
    rep{end+1} = ['The columns above are the learner''s generalisation, the link-budget completion off (lb_complete.m). ' ...
        'Beside them, the same agents on the same episodes with the completion on: DQN + link-budget completion (hybrid, not learned).'];
    rep{end+1} = sprintf('%-32s %6s %24s %24s %10s', 'combination', 'n', 'DQN + LB, never trained', 'DQN + LB, trained', 'rule+esc');
    for i = 1:numel(res)
        r = res(i);
        rep{end+1} = sprintf('%-32s %6d %9.1f%% [%4.1f, %4.1f] %9.1f%% [%4.1f, %4.1f] %9.1f%%', r.combo, r.n, ...
            100*r.dqn_out_lb, 100*r.ci_out_lb, 100*r.dqn_in_lb, 100*r.ci_in_lb, 100*r.rule); %#ok<SAGROW>
    end
    rep{end+1} = sprintf('%-32s %6d %9.1f%% %14s %9.1f%% %14s %9.1f%%', 'mean', sum([res.n]), 100*mean([res.dqn_out_lb]), '', ...
        100*mean([res.dqn_in_lb]), '', 100*mean([res.rule]));
    pl = cellfun(@(c) any(strcmp(strsplit(c, '+'), 'path_loss')), {res.combo});
    if any(pl)
        w = [res(pl).n] / sum([res(pl).n]);
        rep{end+1} = sprintf(['The %d combinations that hold a path loss, pooled: never trained %.1f%% (completion off), %.1f%% ' ...
            '(hybrid); trained %.1f%%, %.1f%%'], sum(pl), 100*sum(w .* [res(pl).dqn_out]), 100*sum(w .* [res(pl).dqn_out_lb]), ...
            100*sum(w .* [res(pl).dqn_in]), 100*sum(w .* [res(pl).dqn_in_lb]));
    end
end
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/combo_generalization.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
save('results/combo_generalization.mat', 'res');
fprintf('\nSaved results/combo_generalization.{txt,mat} (%.1f min)\n', toc(t0)/60);

%% ===================== Local functions =====================
function r = one_combo(ci, combos, PP, K, Q, H, seed, nS, TEST, REPS, NE, DK, t0, LBC)
% Combination ci left out of training and validation: the retrained DQN, the selected one, rule +
% escalation and the class table on its test flights. With LBC (C2 stored the link-budget
% completion's switch) the DQNs run with the completion off, the learner's own result, and again
% with it on, the hybrid (_lb fields).
c = find(strcmp(PP.scen, combos{ci}));
fprintf('[%d/%d] %s left out of training and validation\n', ci, numel(combos), combos{ci});
PPx = PP;
if isfield(PPx, 'lb_complete'), PPx.lb_complete = false; end   % the retrained learner trains and keeps its checkpoint without the completion
PPx.pools(c, :, :, 1:2) = {[]};
Kx = link_env('tables', PPx);
Kt = Kx; Kt.FA = Q.seed_summary.selected_fa_pen;
if isfield(Q.seed_summary, 'selected_cost_scale')          % training reward variant
    Kt.cost = Q.seed_summary.selected_cost_scale * Kx.cost; Kt.SW = Q.seed_summary.selected_sw_scale * Kx.SW;
end
ag = dqn_train_run(H, PPx, Kt, Kx, Q.norm_in, seed, nS, 1, 2);
specs = test_episodes(c, numel(PP.ebno), K.geo(c, TEST), REPS, NE, H.T, RandStream('mt19937ar', 'Seed', 300 + ci));
opt0 = struct(); if LBC, opt0 = struct('monitor', struct('lb_complete', false)); end
Ro = dqn_eval_batches(DK, PP, K, specs, ag, opt0, 7000, TEST);
Ri = dqn_eval_batches(DK, PP, K, specs, Q.agent, opt0, 7000, TEST);
Rr = dqn_eval_batches('rule_esc', PP, K, specs, [], struct(), 7000, TEST);
Rt = dqn_eval_batches('table', PP, K, specs, [], policy_table(PPx, Kx), 7000, TEST);
[Ro, Ri, Rr, Rt] = deal(mark(Ro, specs, PP), mark(Ri, specs, PP), mark(Rr, specs, PP), mark(Rt, specs, PP));
m = Ro.recoverable & Ro.threat;
[~, lo1, hi1] = boot_cluster(double(Ro.recovered(m)), ones(1, sum(m)), Ro.geom(m), 2000, 1);
[~, lo2, hi2] = boot_cluster(double(Ri.recovered(m)), ones(1, sum(m)), Ri.geom(m), 2000, 2);
r = struct('combo', combos{ci}, 'n', sum(m), 'dqn_out', mean(Ro.recovered(m)), 'dqn_in', mean(Ri.recovered(m)), ...
    'rule', mean(Rr.recovered(m)), 'table', mean(Rt.recovered(m)), 'ci_out', [lo1 hi1], 'ci_in', [lo2 hi2]);
if LBC
    opt1 = struct('monitor', struct('lb_complete', true));
    Ro1 = mark(dqn_eval_batches(DK, PP, K, specs, ag, opt1, 7000, TEST), specs, PP);
    Ri1 = mark(dqn_eval_batches(DK, PP, K, specs, Q.agent, opt1, 7000, TEST), specs, PP);
    [~, lo3, hi3] = boot_cluster(double(Ro1.recovered(m)), ones(1, sum(m)), Ro1.geom(m), 2000, 3);
    [~, lo4, hi4] = boot_cluster(double(Ri1.recovered(m)), ones(1, sum(m)), Ri1.geom(m), 2000, 4);
    r.dqn_out_lb = mean(Ro1.recovered(m)); r.dqn_in_lb = mean(Ri1.recovered(m));
    r.ci_out_lb = [lo3 hi3]; r.ci_in_lb = [lo4 hi4];
end
fprintf('    recovered among %d recoverable: never trained %.1f%% | trained %.1f%% | rule+esc %.1f%% | table %.1f%% (%.1f min)\n\n', ...
    sum(m), 100*r.dqn_out, 100*r.dqn_in, 100*r.rule, 100*r.table, toc(t0)/60);
end

function specs = test_episodes(c, nS, rr, reps, NE, T, rs)
% Every (cell, Eb/N0, test geometry the cell flies: rr, one list per cell) of the cells c
% (the severities of one combination) `reps` times, in batches of NE (cyclic padding of the
% last batch, dropped again by mark()).
[cc, s, r] = flight_triples(c(:)', rr, 1:nS);
cc = repmat(cc, 1, reps); s = repmat(s, 1, reps); r = repmat(r, 1, reps);
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
% Geometry id per episode (for the bootstrap); padding of the last batch dropped. R.threat
% keeps dqn_eval_batches.m's reading: a threat on the air in the geometry (link_env.m K.on).
g = cell2mat(cellfun(@(sp) sp.s * 1000 + sp.r, specs, 'UniformOutput', false));
n = numel(g) - (numel(specs{end}.scn) - specs{end}.n_valid);
f = fieldnames(R);
for i = 1:numel(f)
    if size(R.(f{i}), 2) == numel(g), R.(f{i}) = R.(f{i})(:, 1:n); end
end
R.geom = g(1:n);
R.threat = R.threat(1:n) & ~strcmp(PP.scen(specs{1}.scn(1)), 'none');
end
