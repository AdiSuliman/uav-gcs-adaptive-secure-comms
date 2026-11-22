function tests = test_side_a5
%TEST_SIDE_A5  Tests of the A5 side readers on synthetic inputs built here, in temporary folders.
%   results = runtests('code/tests/test_side_a5.m')   from the repository root
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.tmp = tempname;
mkdir(tc.TestData.tmp);
[tc.TestData.fold_dir, tc.TestData.sel] = synth_folds(fullfile(tc.TestData.tmp, 'folds'), 11);
end

function teardownOnce(tc)
if isfolder(tc.TestData.tmp), rmdir(tc.TestData.tmp, 's'); end
end

%% ---------- helpers ----------
function [fd, selp] = synth_folds(fd, seed)
% Three folds over four classes; the emitters move s0, path loss moves the cue score.
rng(seed);
mkdir(fd);
cls = {'none', 'jamming', 'path_loss', 'tone_jamming'};
held = {'jamming', 'path_loss', 'tone_jamming'};
NW = 5; nR = 160; L = 20; nb = 50;
rlab = cls(mod(0:nR - 1, 4) + 1)'; rlab = rlab(randperm(nR));
run = repelem((1:nR)', L); pos = repmat((1:L)', nR, 1); n = numel(run);
y = rlab(run);
fitR = mod(1:nR, 2)' == 0; fit = fitR(run);
emit = ismember(y, {'jamming', 'tone_jamming'});
s0 = randn(n, 1) - 1.5 * emit - 0.2 * strcmp(y, 'path_loss');
cue = randn(n, 1) - 2.0 * strcmp(y, 'path_loss') + 0.5 * strcmp(y, 'jamming');
full = pos >= NW;
T = numel(held); A = nan(T, 5); Bd = nan(nb, T, 5);
for h = 1:T
    k = held{h}; known = setdiff(cls, {k}, 'stable');
    own = strcmp(y, k);
    F = struct('vfit', fit & ~own & ~strcmp(y, k), 'sel', ~fit, 'own', own, ...
        'kn', ~fit & ~own & ~strcmp(y, k), 'un', strcmp(y, k), 'known', {known});
    p0 = unk_stat('p', unk_stat('cal', s0(F.vfit)), s0);
    pc = ones(n, 1); pc(full) = unk_stat('p', unk_stat('cal', cue(F.vfit & full)), cue(full));
    c3 = pc; c3(~full) = p0(~full);
    Wv = [s0, min(p0, pc), min(p0, pc), c3, -(-2 * (log(p0) + log(pc)))];
    pr = 0.02 * ones(numel(known), n);
    ne = ismember(known, {'none', 'path_loss'});
    fam = ~emit;
    pr(find(ne, 1), fam) = 0.9; pr(find(~ne, 1), ~fam) = 0.9;
    pr = pr ./ sum(pr, 1);
    Sv = struct('probs', pr);
    V = struct('run', run, 'pos', pos, 'kn', F.kn, 'un', F.un);
    for j = 1:5, A(h, j) = ood_k2_rules('auroc', Wv(F.kn, j), Wv(F.un, j)); end
    Bd(:, h, :) = reshape(ood_k2_rules('boot_auroc', Wv, F.kn, F.un, run, nb, 9800 + h), nb, 1, 5);
    save(fullfile(fd, sprintf('fold_%d.mat', h)), 'k', 'known', 'Sv', 'V', 'Wv', 'F', '-v7.3');
end
held_out = held; CN = {'C0', 'C1', 'C2', 'C3', 'C4'}; %#ok<NASGU>
selp = fullfile(fileparts(fd), 'sel', 'ood_k2_select.mat'); mkdir(fileparts(selp));
save(selp, 'A', 'Bd', 'held_out', 'CN', 'NW', '-v7.3');
end

function [p, KP] = synth_pe(d)
mkdir(d);
th = {'jamming', 'antenna_fault'}; nV = 5; show = {'none', 'fixed', 'rule_esc', 'blind_esc', 'table', 'dqn', 'dqn_esc', 'oracle'};
PT = 90 * ones(2, 8); PT(2, 6) = 84.7; PT(2, 7) = 96.1;
PTh = 80 * ones(2, 8); PTh(2, 6) = 32.9; PTh(2, 7) = 82.9;
PTsev = 90 * ones(2, nV, 8); PTsev(2, :, 6) = [83.3 86.8 84.0 84.7 84.7];
KP = struct('per_threat', PT, 'per_threat_sev', PTsev, 'threats', {th}, 'recoverable_share', [1; 1], ...
    'envelope', logical([1 1 1 1 1; 0 1 0 0 0]), 'envelope_val', [95 95 95 95 95; 88 91 87 89 85], ...
    'per_threat_env', [96; 86.8], 'per_threat_env_ci', [94 98; 78.5 93.8], 'env_rule', [90 10], ...
    'sev_names', {{'very low', 'low', 'nominal', 'high', 'very high'}}, 'show', {show}, ...
    'per_threat_h', PTh, 'n_harmed', [1440; 164], 'n_harmed_sev', [288 288 288 288 288; 30 32 34 34 34], ...
    'envelope_val_h', nan(2, nV));
POL = {'none', 'dqn'}; iDQN = 2; %#ok<NASGU>
p = fullfile(d, 'policy_evaluation.mat');
save(p, 'KP', 'POL', 'iDQN');
end

%% ---------- tests ----------
function test_auroc_orientation(tc)
% Lower = more novel: unknown below known gives 1, above gives 0, equal gives 0.5.
tc.verifyEqual(ood_k2_rules('auroc', [2 3 4], [0 1]), 1);
tc.verifyEqual(ood_k2_rules('auroc', [0 1], [2 3 4]), 0);
tc.verifyEqual(ood_k2_rules('auroc', [1 1], [1 1]), 0.5);
end

function test_route_reproduces_saved(tc)
R = side_a5_ood_route(tc.TestData.fold_dir, tc.TestData.sel, fullfile(tc.TestData.tmp, 'o1'), struct('nb', 50));
tc.verifyEqual(max(R.rep_err(:)), 0, 'AbsTol', 1e-12);
tc.verifyTrue(all(R.identity(:) == 1));
tc.verifyTrue(isfile(fullfile(tc.TestData.tmp, 'o1', 'a5_ood_route.txt')));
end

function test_route_gains_where_cue_informs(tc)
R = side_a5_ood_route(tc.TestData.fold_dir, tc.TestData.sel, fullfile(tc.TestData.tmp, 'o2'), struct('nb', 50));
ip = strcmp(R.held_out, 'path_loss'); j1 = strcmp(R.CN, 'R1');
tc.verifyGreaterThan(R.A(ip, j1), R.A(ip, 1) + 0.2);       % routed to the cue, which separates path loss
tc.verifyEqual(numel(R.nest), 3);
tc.verifyTrue(all(ismember(R.nest_pick, R.CN)));
end

function test_route_emitter_category_keeps_s0_order(tc)
% Held-out jamming: every window goes to the emitter category, where R1 is s0's Mondrian p-value,
% so against the known windows of that category R1 orders the windows as s0 does. Against all
% known windows R1 differs from s0: the other categories' known windows carry their own p-values.
d = load(fullfile(tc.TestData.fold_dir, 'fold_1.mat'));
tc.assertEqual(d.k, 'jamming');
S = load(tc.TestData.sel, 'NW');
Q = side_a5_ood_route('route', d, S.NW, {'none', 'path_loss', 'antenna_fault', 'airframe_shadowing'});
un = d.F.un(:); kn = d.F.kn(:); kE = kn & Q.d.ct == 1;
fprintf('jamming windows routed to s0: %.1f%%; known windows in the s0 category: %d of %d
', ...
    100 * mean(Q.d.ct(un) == 1), sum(kE), sum(kn));
aE0 = ood_k2_rules('auroc', d.Wv(kE, 1), d.Wv(un, 1)); aE1 = ood_k2_rules('auroc', Q.u.R1(kE), Q.u.R1(un));
a0 = ood_k2_rules('auroc', d.Wv(kn, 1), d.Wv(un, 1)); a1 = ood_k2_rules('auroc', Q.u.R1(kn), Q.u.R1(un));
fprintf('AUROC vs known in the s0 category: s0 %.3f, R1 %.3f; vs all known: s0 %.3f, R1 %.3f
', aE0, aE1, a0, a1);
tc.verifyEqual(mean(Q.d.ct(un) == 1), 1);
tc.verifyLessThan(abs(aE1 - aE0), 0.02);                  % monotone within the category (ties from the discrete p)
end

function test_route_full_window_share(tc)
% The full-window mask follows the cue window length; every fold gives seven candidates.
d = load(fullfile(tc.TestData.fold_dir, 'fold_1.mat'));
S = load(tc.TestData.sel, 'NW');
R = side_a5_ood_route(tc.TestData.fold_dir, tc.TestData.sel, fullfile(tc.TestData.tmp, 'o3'), struct('nb', 50));
tc.verifyEqual(size(R.A), [3 7]);
full = ood_cue('fill', d.V.run, d.V.pos) >= S.NW;
tc.verifyEqual(mean(full(d.F.kn)), 16 / 20, 'AbsTol', 1e-12);
end

function test_route_refuses_existing_and_fresh(tc)
o = fullfile(tc.TestData.tmp, 'o4'); mkdir(o);
tc.verifyError(@() side_a5_ood_route(tc.TestData.fold_dir, tc.TestData.sel, o, struct('nb', 10)), 'side_out_dir:exists');
tc.verifyError(@() side_a5_ood_route(fullfile(tc.TestData.tmp, 'splits_fresh'), tc.TestData.sel, ...
    fullfile(tc.TestData.tmp, 'o5'), struct('nb', 10)), 'side_a5_ood_route:fresh');
end

function test_kpi4_reader(tc)
p = synth_pe(fullfile(tc.TestData.tmp, 'pe'));
R = side_a5_kpi4_af(p, fullfile(tc.TestData.tmp, 'k1'), 'synth');
tc.verifyEqual(R.test_all, 84.7); tc.verifyEqual(R.test_h, 32.9);
tc.verifyEqual(R.esc_all, 96.1); tc.verifyEqual(R.esc_h, 82.9);
tc.verifyEqual(R.val_inside_mean, 91); tc.verifyEqual(R.test_inside_lv, 86.8);
tc.verifyEqual(R.val_all_mean, 88);
txt = fileread(fullfile(tc.TestData.tmp, 'k1', 'a5_kpi4_af.txt'));
tc.verifyTrue(contains(txt, 'implied if every unharmed one recovers: 719'));
end
