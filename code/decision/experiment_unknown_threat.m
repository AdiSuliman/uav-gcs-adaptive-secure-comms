%% EXPERIMENT_UNKNOWN_THREAT - Link recovery under a threat the agent never trained on
% The unknown-threat test of evaluate_policies.m withholds the detector output
% after the onset, but the agent has trained on that threat. Here it has not.
% Leave-one-threat-out: for each single threat, the train and validation pools of
% every cell that contains it (its severities and the combined threats with it) are
% removed and a DQN is retrained with the selected settings of train_dqn.m
% (dqn_train_run.m). It is tested on the test and second test flights of the removed
% threat (72 per point), every severity, with the detector output withheld after the
% onset (the path of a threat flagged unknown: only the link measurements, the
% quiet-slot measurements and the persistence measurements remain), next to the
% selected DQN (which trained on it) and rule + escalation on the same episodes.
% Recovered = BER and packet loss <= 2x clean for 5 consecutive cycles, among the
% recoverable episodes. 95% intervals by bootstrap over flights. Every leave-one-out
% agent is kept, so the edge map can read it later. Evidence only: no rate is committed
% for an emitter outside the modelled classes.
%
% Output: results/unknown_threat_policy.{txt,mat} (res, and every episode: EP),
% data/unknown_threat_agents.mat (agents_loo, threats, det_id)

close all; clc;
fprintf('=== Link recovery under a threat never trained on: leave-one-threat-out ===\n\n');
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
Q = load('data/trained_dqn.mat', 'agent', 'H', 'norm_in', 'seed_summary', 'confirm', 'alarm_mode', 'drop_db');
PP.confirm = Q.confirm; PP.alarm_mode = Q.alarm_mode;
if ~isempty(Q.drop_db), PP.drop_db = Q.drop_db; end
K = link_env('tables', PP);
TEST = 3; TEST2 = 5; NE = 64; REPS = 2;
H = Q.H; H.gamma = Q.seed_summary.selected_gamma;
seed = Q.seed_summary.selected_seed;
nA = numel(PP.actions); nS = policy_state_size(nA, numel(PP.classes));
threats = setdiff(PP.singles, {'none'}, 'stable');
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    threats = threats(1); REPS = 1; H.episodes = 1280; H.buffer = 20000; H.warmup = 2000; H.n_eval = 1;
end

res = struct('threat', {}, 'n', {}, 'dqn_out', {}, 'dqn_in', {}, 'rule', {}, 'ci_out', {}, 'ci_in', {});
EP = struct('threat', {}, 'out', {}, 'in', {}, 'rule', {});
agents_loo = cell(1, numel(threats));
SPL = TEST; if numel(PP.runs) >= TEST2, SPL = [TEST TEST2]; end
c1 = find(strcmp(PP.scen, threats{1}), 1);
nfl = sum(arrayfun(@(sp) numel(PP.cell_geo{c1}{sp}), SPL));       % flights per (cell, Eb/N0)
t0 = tic;
for ti = 1:numel(threats)
    th = threats{ti};
    hit = cellfun(@(s) any(strcmp(strsplit(s, '+'), th)), PP.scen);
    c = find(strcmp(PP.scen, th));
    fprintf('[%d/%d] %s left out of training and validation (%d cells)\n', ti, numel(threats), th, sum(hit));
    PPx = PP;
    PPx.pools(hit, :, :, 1:2) = {[]};
    Kx = link_env('tables', PPx);
    Kt = Kx; Kt.FA = Q.seed_summary.selected_fa_pen;
    if isfield(Q.seed_summary, 'selected_cost_scale')          % training reward variant
        Kt.cost = Q.seed_summary.selected_cost_scale * Kx.cost; Kt.SW = Q.seed_summary.selected_sw_scale * Kx.SW;
    end
    ag = dqn_train_run(H, PPx, Kt, Kx, Q.norm_in, seed, nS, 1, 2);
    agents_loo{ti} = dqn_dense(ag);
    [Ro, Ri, Rr] = deal([]);
    for sp = SPL
        specs = test_episodes(c, numel(PP.ebno), PP.cell_geo{c(1)}{sp}, REPS, NE, H.T, ...
            RandStream('mt19937ar', 'Seed', 500 + 100 * sp + ti));
        Ro = cat_struct(Ro, mark(dqn_eval_batches('dqn_esc', PP, K, specs, ag, struct(), 7000, sp), specs, PP, sp));
        Ri = cat_struct(Ri, mark(dqn_eval_batches('dqn_esc', PP, K, specs, Q.agent, struct(), 7000, sp), specs, PP, sp));
        Rr = cat_struct(Rr, mark(dqn_eval_batches('rule_esc', PP, K, specs, [], struct(), 7000, sp), specs, PP, sp));
    end
    EP(end+1) = struct('threat', th, 'out', Ro, 'in', Ri, 'rule', Rr); %#ok<SAGROW>
    m = Ro.recoverable & Ro.threat;
    [~, lo1, hi1] = boot_cluster(double(Ro.recovered(m)), ones(1, sum(m)), Ro.geom(m), 2000, 1);
    [~, lo2, hi2] = boot_cluster(double(Ri.recovered(m)), ones(1, sum(m)), Ri.geom(m), 2000, 2);
    res(end+1) = struct('threat', th, 'n', sum(m), 'dqn_out', mean(Ro.recovered(m)), 'dqn_in', mean(Ri.recovered(m)), ...
        'rule', mean(Rr.recovered(m)), 'ci_out', [lo1 hi1], 'ci_in', [lo2 hi2]); %#ok<SAGROW>
    fprintf('    recovered among %d recoverable: never trained %.1f%% | trained %.1f%% | rule+esc %.1f%% (%.1f min)\n\n', ...
        sum(m), 100*res(end).dqn_out, 100*res(end).dqn_in, 100*res(end).rule, toc(t0)/60);
end

rep = {'=== LINK RECOVERY UNDER A THREAT NEVER TRAINED ON: LEAVE-ONE-THREAT-OUT ==='};
rep{end+1} = sprintf(['Generated: %s | DQN retrained without the threat (its single and combined cells removed from ' ...
    'training and validation), selected settings: monitor %s %d/%d, penalty %d, gamma %.2f, seed %d | test and second ' ...
    'test flights of the threat, every severity, %d per Eb/N0, detector output withheld after the onset'], datestr(now), ...
    PP.alarm_mode, PP.confirm, Q.seed_summary.selected_fa_pen, H.gamma, seed, nfl);
rep{end+1} = 'Recovered = BER and packet loss <= 2x clean for 5 consecutive cycles, among recoverable episodes; [95% bootstrap over flights].';
rep{end+1} = 'Evidence only: no rate is committed for an emitter outside the modelled classes.';
rep{end+1} = '';
rep{end+1} = sprintf('%-22s %6s %24s %24s %10s', 'threat', 'n', 'DQN, never trained', 'DQN, trained', 'rule+esc');
for i = 1:numel(res)
    r = res(i);
    rep{end+1} = sprintf('%-22s %6d %9.1f%% [%4.1f, %4.1f] %9.1f%% [%4.1f, %4.1f] %9.1f%%', r.threat, r.n, ...
        100*r.dqn_out, 100*r.ci_out, 100*r.dqn_in, 100*r.ci_in, 100*r.rule); %#ok<SAGROW>
end
rep{end+1} = sprintf('%-22s %6d %9.1f%% %14s %9.1f%% %14s %9.1f%%', 'mean', sum([res.n]), 100*mean([res.dqn_out]), '', ...
    100*mean([res.dqn_in]), '', 100*mean([res.rule]));
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/unknown_threat_policy.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
save('results/unknown_threat_policy.mat', 'res', 'EP');
det_id = PP.det_id;
save('data/unknown_threat_agents.mat', 'agents_loo', 'threats', 'det_id', 'H', 'seed', '-v7.3');
fprintf('\nSaved results/unknown_threat_policy.{txt,mat}, data/unknown_threat_agents.mat (%.1f min)\n', toc(t0)/60);

%% ===================== Local functions =====================
function specs = test_episodes(c, nS, rr, reps, NE, T, rs)
% Every (cell, Eb/N0, geometry rr of the split) of the cells c (the severities of one
% threat) `reps` times, in batches of NE (cyclic padding of the last batch, dropped
% again by mark()), the detector output withheld after the onset.
[cc, s, r] = ndgrid(c(:)', 1:nS, rr);
cc = repmat(cc(:)', 1, reps); s = repmat(s(:)', 1, reps); r = repmat(r(:)', 1, reps);
n = numel(s); nb = ceil(n / NE); pad = nb * NE - n;
k_ = mod(0:n + pad - 1, n) + 1; cc = cc(k_); s = s(k_); r = r(k_);
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*NE + (1:NE);
    specs{b} = struct('scn', cc(i), 's', s(i), 'r', r(i), 'onset', randi(rs, [3 10], 1, NE), ...
        'follow', false(1, NE), 'fdelay', 2 * ones(1, NE), 'unk', true(1, NE), 'T', T);
end
specs{end}.n_valid = NE - pad;
end

function R = mark(R, specs, PP, split)
% Flight id per episode (for the bootstrap); padding of the last batch dropped.
g = cell2mat(cellfun(@(sp) 1e6 * split + sp.s * 1000 + sp.r, specs, 'UniformOutput', false));
n = numel(g) - (numel(specs{end}.scn) - specs{end}.n_valid);
f = fieldnames(R);
for i = 1:numel(f)
    if size(R.(f{i}), 2) == numel(g), R.(f{i}) = R.(f{i})(:, 1:n); end
end
R.geom = g(1:n);
R.threat = true(1, n) & ~strcmp(PP.scen(specs{1}.scn(1)), 'none');
end

function R = cat_struct(R, Rb)
if isempty(R), R = Rb; return; end
f = fieldnames(R);
for i = 1:numel(f), R.(f{i}) = [R.(f{i}), Rb.(f{i})]; end
end
