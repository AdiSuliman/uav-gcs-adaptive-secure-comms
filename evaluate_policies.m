%% EVALUATE_POLICIES - Decision-layer comparison on the test pools (D44, D45)
% Every policy runs the same episodes with the same frame draws (common random
% numbers) on the TEST split of data/policy_pools.mat: sub-runs (flight
% geometries) with seeds never used in training. Episode sets:
%   single    8 threats x 6 Eb/N0, static jammer
%   follower  jamming / reactive_jamming / spoofing that re-acquire the channel
%             2-5 cycles after every hop
%   combined  4 combined threats never seen in training
%   clean     no threat (every change is a false alarm)
% Policies: random; always-on adaptive combining (fixed spatial_diversity); the
% best fixed configuration (chosen on the train pools); expert rule, with and
% without escalation; class -> configuration table tuned on the train pools;
% DQN with gamma = 0 (contextual bandit); DQN, with and without escalation;
% one-step oracle (true scenario, follower state and geometry).
% Metrics per episode (after onset unless noted): mean reward per cycle,
% restored cycles (BER <= 2x clean), normalized goodput, cycles to recover
% (restored for 5 consecutive cycles), switches, false switches (whole episode).
% Intervals: 95% t over episodes; differences are paired per episode.
%
% Output: results/policy_evaluation.{txt,mat,png}

close all; clc;
fprintf('=== Decision-layer evaluation on the test pools (D44, D45) ===\n\n');
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
Q = load('data/trained_dqn.mat', 'agent', 'agent_bandit', 'H');
K = link_env('tables', PP);
tab = policy_table(PP, K);
T = Q.H.T; NE = 64;
nSing = numel(PP.singles); nA = numel(PP.actions); nS = numel(PP.ebno);
rs = RandStream('mt19937ar', 'Seed', 2027);

%% 1. Episode sets
foll = find(K.followable(1:nSing));
sets = struct('name', {}, 'spec', {});
sets(end+1) = struct('name', 'single',   'spec', {cells_to_specs(2:nSing, 12, false, NE, T, nS, rs)});
sets(end+1) = struct('name', 'follower', 'spec', {cells_to_specs(foll, 16, true, NE, T, nS, rs)});
sets(end+1) = struct('name', 'combined', 'spec', {cells_to_specs(nSing+1:numel(PP.scen), 16, false, NE, T, nS, rs)});
sets(end+1) = struct('name', 'clean',    'spec', {cells_to_specs(1, 32, false, NE, T, nS, rs)});

%% 2. Best fixed configuration, chosen on the train pools
vspec = cells_to_specs(1:nSing, 4, false, NE, T, nS, RandStream('mt19937ar', 'Seed', 11));
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

%% 3. Run every policy on every set
POL = {'random', 'fixed_mmse', 'fixed', 'rule', 'rule_esc', 'table', 'bandit', 'dqn', 'dqn_esc', 'oracle'};
LBL = {'random', 'always adaptive combining', ['fixed: ' PP.actions{fixed_best}], 'rule', 'rule + escalation', ...
       'table (train pools)', 'DQN gamma=0 (bandit)', 'DQN', 'DQN + escalation', 'oracle (one-step)'};
RES = cell(numel(sets), numel(POL));
t0 = tic;
for si = 1:numel(sets)
    for pk = 1:numel(POL)
        kind = POL{pk}; ag = Q.agent; opt = struct();
        switch kind
            case 'bandit',     kind = 'dqn'; ag = Q.agent_bandit;
            case 'fixed',      opt.fixed = fixed_best;
            case 'fixed_mmse', kind = 'fixed'; opt.fixed = fixed_mmse;
            case 'table',      opt = tab;
        end
        R = [];
        for b = 1:numel(sets(si).spec)
            Rb = rollout_policy(kind, PP, K, sets(si).spec{b}, 2, ag, opt, 30000 + 100*si + b);
            Rb.scn = sets(si).spec{b}.scn; Rb.s = sets(si).spec{b}.s;
            Rb = rmfield(Rb, 'cfg_trace');
            if isempty(R), R = Rb; else, R = cat_struct(R, Rb); end
        end
        RES{si, pk} = R;
    end
    fprintf('  set %-9s %4d episodes x %d policies (%.1f min)\n', sets(si).name, numel(RES{si, 1}.ret), ...
        numel(POL), toc(t0)/60);
end

%% 4. Report
col = @(p) find(strcmp(POL, p));
rep = {};
rep{end+1} = '=== DECISION-LAYER EVALUATION, TEST POOLS (D44, D45) ===';
rep{end+1} = sprintf(['Generated: %s | %d-cycle episodes, onset at cycle 3-10 | test sub-runs (geometries) never ' ...
    'used in training | interferer AoA %s'], datestr(now), T, ternary(PP.aoa_random, 'random per sub-run', 'fixed'));
rep{end+1} = 'return = mean reward per cycle (1 = restored at no cost); restored / goodput / recovery after onset;';
rep{end+1} = 'recovered = restored for 5 consecutive cycles; false sw = switches on a healthy link, whole episode.';
for si = 1:numel(sets)
    rep{end+1} = ''; %#ok<SAGROW>
    rep{end+1} = sprintf('--- %s (%d episodes) ---', sets(si).name, numel(RES{si, 1}.ret)); %#ok<SAGROW>
    rep = [rep, policy_table_lines(RES(si, :), LBL)]; %#ok<AGROW>
    rep{end+1} = paired_line(RES(si, :), col); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = sprintf('--- all sets pooled (%d episodes: %s) ---', sum(cellfun(@(R) numel(R.ret), RES(:, 1))), ...
    strjoin(arrayfun(@(si) sprintf('%s %d', sets(si).name, numel(RES{si, 1}.ret)), 1:numel(sets), ...
    'UniformOutput', false), ', '));
ALL = cell(1, numel(POL));
for pk = 1:numel(POL)
    ALL{pk} = RES{1, pk};
    for si = 2:numel(sets), ALL{pk} = cat_struct(ALL{pk}, RES{si, pk}); end
end
rep = [rep, policy_table_lines(ALL, LBL)];
rep{end+1} = paired_line(ALL, col);

rep{end+1} = '';
rep{end+1} = 'Restored cycles after onset per threat (single + follower + combined sets), %:';
show = {'fixed_mmse', 'fixed', 'rule_esc', 'table', 'dqn', 'dqn_esc', 'oracle'};
hdr = {'always MMSE', 'fixed best', 'rule+esc', 'table', 'DQN', 'DQN+esc', 'oracle'};
rep{end+1} = sprintf('%-26s%s', 'scenario', sprintf('%12s', hdr{:}));
for sc = 2:numel(PP.scen)
    v = zeros(1, numel(show));
    for c = 1:numel(show)
        x = [];
        for si = 1:3
            R = RES{si, col(show{c})}; x = [x, R.restored_post(R.scn == sc)]; %#ok<AGROW>
        end
        v(c) = 100 * mean(x);
    end
    rep{end+1} = sprintf('%-26s%s', PP.scen{sc}, sprintf('%12.1f', v)); %#ok<SAGROW>
end

if PP.aoa_random
    rep{end+1} = '';
    rep{end+1} = 'Restored cycles after onset vs interferer direction (single set, directional threats), %:';
    bins = [0 20 45 90]; dirn = find(~ismember(PP.scen(1:nSing), {'none', 'path_loss', 'antenna_fault'}));
    rep{end+1} = sprintf('%-18s%s', '|AoA| from GCS', sprintf('%12s', hdr{:}));
    R1 = RES{1, 1}; th = abs(R1.aoa(1, :)); isd = ismember(R1.scn, dirn);
    for bi = 1:numel(bins) - 1
        sel = isd & th >= bins(bi) & th < bins(bi+1);
        v = arrayfun(@(c) 100 * mean(RES{1, col(show{c})}.restored_post(sel)), 1:numel(show));
        rep{end+1} = sprintf('%-18s%s', sprintf('%d-%d deg (%d)', bins(bi), bins(bi+1), sum(sel)), ...
            sprintf('%12.1f', v)); %#ok<SAGROW>
    end
end
fid = fopen('results/policy_evaluation.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
set_names = {sets.name};
save('results/policy_evaluation.mat', 'RES', 'POL', 'LBL', 'set_names', 'fixed_best', 'tab');

fig = figure('Position', [60 60 1500 460], 'Color', 'w');
metric = {'ret', 'restored_post', 'gput_post'};
ttl = {'Mean reward per cycle', 'Restored cycles after onset', 'Normalized goodput after onset'};
for m = 1:3
    subplot(1, 3, m);
    Y = cellfun(@(R) mean(R.(metric{m})), RES(1:3, :));
    bar(Y); grid on; set(gca, 'XTickLabel', set_names(1:3));
    title(ttl{m});
end
lg = legend(LBL, 'Orientation', 'horizontal', 'NumColumns', 5, 'FontSize', 8);
lg.Position = [0.2 0.01 0.6 0.06];
sgtitle('Decision layer on the test pools (D44, D45)');
saveas(fig, 'results/policy_evaluation.png'); close(fig);
fprintf('Saved results/policy_evaluation.{txt,mat,png}\n');

%% ===================== Local functions =====================
function specs = cells_to_specs(scns, reps, follow, NE, T, nS, rs)
% Every (scenario, Eb/N0) cell `reps` times, packed into batches of NE episodes.
[sc, s] = ndgrid(scns, 1:nS);
sc = repmat(sc(:)', 1, reps); s = repmat(s(:)', 1, reps);
n = numel(sc); nb = ceil(n / NE);
pad = nb * NE - n;
sc = [sc, sc(1:pad)]; s = [s, s(1:pad)];
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*NE + (1:NE);
    specs{b} = struct('scn', sc(i), 's', s(i), 'onset', randi(rs, [3 10], 1, NE), ...
        'follow', repmat(follow, 1, NE), 'fdelay', randi(rs, [2 5], 1, NE), 'unk', false(1, NE), 'T', T);
end
end

function lines = policy_table_lines(RR, LBL)
lines = {sprintf('%-32s %22s %22s %9s %10s %6s %9s %9s', 'policy', 'return', 'restored %', 'goodput', ...
    'recovered', 'T_rec', 'switches', 'false sw')};
for pk = 1:numel(RR)
    R = RR{pk};
    rec = ~isnan(R.t_rec);
    lines{end+1} = sprintf('%-32s %22s %22s %9.3f %9.1f%% %6s %9.2f %9.3f', LBL{pk}, ci(R.ret, '%.3f'), ...
        ci(100*R.restored_post, '%.1f'), mean(R.gput_post), 100*mean(rec), med(R.t_rec(rec)), ...
        mean(R.switches), mean(R.false_sw)); %#ok<AGROW>
end
end

function s = paired_line(RR, col)
d = @(a, b) ci(RR{col(a)}.ret - RR{col(b)}.ret, '%+.3f');
s = sprintf('Paired return difference: DQN - rule+esc %s | DQN - table %s | DQN - fixed best %s | DQN - bandit %s', ...
    d('dqn', 'rule_esc'), d('dqn', 'table'), d('dqn', 'fixed'), d('dqn', 'bandit'));
end

function R = cat_struct(R, Rb)
f = fieldnames(R);
for i = 1:numel(f), R.(f{i}) = [R.(f{i}), Rb.(f{i})]; end
end

function s = ci(x, f)
[m, lo, hi] = stats_ci('t', x);
s = sprintf([f ' [' f ', ' f ']'], m, lo, hi);
end

function s = med(x)
if isempty(x), s = '-'; else, s = sprintf('%.0f', median(x)); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
