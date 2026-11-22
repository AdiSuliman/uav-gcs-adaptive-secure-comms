function tests = test_side_a7
%TEST_SIDE_A7  Tests of the A7 side readings (side_a7_*.m) on small synthetic inputs built here, in temporary folders.
%   No project data. Run from the repository root: results = runtests('code/tests/test_side_a7.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.tmp = tempname;
mkdir(tc.TestData.tmp);
mkdir(fullfile(tc.TestData.tmp, 'in'));
end

function teardownOnce(tc)
if isfolder(tc.TestData.tmp), rmdir(tc.TestData.tmp, 's'); end
end

%% ---------- C1: action equivalence ----------
function test_action_equiv_counts(tc)
cls = {'none'; 'jamming'; 'path_loss'; 'benign_interference'};
cm = [90 2 5 3; 1 80 0 4; 10 0 85 5; 6 1 2 91];
D = struct('classes', {cls}, 'conf_mat', cm, 'overall_accuracy_pct', 100 * 346 / 385, 'action_equiv_accuracy_pct', 100 * 355 / 385);
f = fullfile(tc.TestData.tmp, 'in', 'c1.json');
fid = fopen(f, 'w'); fwrite(fid, jsonencode(struct('detector_fourth', D))); fclose(fid);
S = side_a7_action_equiv(f, fullfile(tc.TestData.tmp, 'c1_out'));
verifyEqual(tc, S.n_err, 39);
verifyEqual(tc, S.k_keep, 9);
verifyEqual(tc, S.k_change, 30);
verifyEqual(tc, S.acc_equiv, 100 * 355 / 385, 'AbsTol', 1e-9);
[lo, hi] = side_cp(30, 39);
verifyEqual(tc, S.ci_change, [lo hi], 'AbsTol', 1e-12);
% none and benign_interference share no_action: the only same off-diagonal cells
verifyEqual(tc, find(S.same & ~eye(4, 'logical'))', [sub2ind([4 4], 4, 1), sub2ind([4 4], 1, 4)]);
verifyTrue(tc, isfile(fullfile(tc.TestData.tmp, 'c1_out', 'side_a7_action_equiv.txt')));
verifyEqual(tc, S.top(1).n, 10);
verifyTrue(tc, S.top(1).changes);
end

function test_action_equiv_refuses(tc)
f = fullfile(tc.TestData.tmp, 'in', 'c1b.json');
fid = fopen(f, 'w'); fwrite(fid, jsonencode(struct('other', 1))); fclose(fid);
verifyError(tc, @() side_a7_action_equiv(f, fullfile(tc.TestData.tmp, 'c1b_out')), 'side_a7:field');
verifyError(tc, @() side_a7_action_equiv(fullfile(tc.TestData.tmp, 'in', 'absent.json'), fullfile(tc.TestData.tmp, 'c1c_out')), 'side_a7:input');
f2 = fullfile(tc.TestData.tmp, 'in', 'c1.json');
verifyError(tc, @() side_a7_action_equiv(f2, fullfile(tc.TestData.tmp, 'c1_out')), 'side_out_dir:exists');
end

%% ---------- C5: false-alarm breakdown reprint ----------
function test_fa_breakdown(tc)
t = {'GATE PASS', '=== D103 3: system level', 'x', '(a) False-alarm episodes per Eb/N0 (episodes / flights):', ...
    '  policy        0 dB    3 dB     all', '  rule        1/10    2/10    3/20', '  dqn         0/10    1/10    1/20', '  bad         0/10    1/10    5/20', ...
    '', '(b) path', '', '=== D103 4: next'};
f = fullfile(tc.TestData.tmp, 'in', 'fa.txt');
fid = fopen(f, 'w'); fprintf(fid, '%s\n', t{:}); fclose(fid);
S = side_a7_fa_breakdown(f, fullfile(tc.TestData.tmp, 'c5_out'));
verifyEqual(tc, S.first_line, 2);
verifyEqual(tc, S.last_line, 10);
verifyEqual(tc, numel(S.table_a), 3);
verifyEqual(tc, [S.table_a.sum_ok], [true true false]);
verifyEqual(tc, S.table_a(1).policy, 'rule');
verifyEqual(tc, S.table_a(2).k, [0 1]);
end

%% ---------- C3: clean pool variables ----------
function test_clean_pool_vars(tc)
CT = struct('pools', {{struct('probs', ones(3, 11), 'ber', zeros(3, 1))}}, 'det_id', 'abc');
f1 = fullfile(tc.TestData.tmp, 'in', 'clean_a.mat'); save(f1, 'CT');
S = side_a7_clean_pool_vars({f1}, '', '', fullfile(tc.TestData.tmp, 'c3_a'));
verifyFalse(tc, S.replay);
verifyFalse(tc, S.files(1).has_probs3);
verifyTrue(tc, ismember('CT.pools.probs', S.files(1).fields));
verifyFalse(tc, S.model.present);
CT = struct('pools', {{struct('probs', ones(3, 11), 'probs3', ones(3, 3), 'ber', zeros(3, 1))}}); %#ok<NASGU>
f2 = fullfile(tc.TestData.tmp, 'in', 'clean_b.mat'); save(f2, 'CT');
S = side_a7_clean_pool_vars({f2}, '', '', fullfile(tc.TestData.tmp, 'c3_b'));
verifyTrue(tc, S.replay);
verifyTrue(tc, S.files(1).has_probs3);
end

%% ---------- C2: hover per Eb/N0 ----------
function test_hover_edge(tc)
eb = [0 3]; nS = 2; nr = 24;
[c, sp, s, r] = deal([]);
for ci = 1:2
    for spi = [3 4]
        for si = 1:nS
            for ri = 1:nr
                c(end+1, 1) = ci; sp(end+1, 1) = spi; s(end+1, 1) = si; r(end+1, 1) = ri; %#ok<AGROW>
            end
        end
    end
end
n = numel(c);
FT = struct('c', c, 'sp', sp, 's', s, 'r', r, 'eb', eb(s)', 'geo', 1e6 * sp + 1000 * s + r, ...
    'speed', 50 * (sp == 3), 'surv', true(n, 1), 'on', true(n, 1), 'harm', false(n, 1), ...
    'det_k', 10 * ones(n, 1), 'det_n', 10 * ones(n, 1), 'held_k', 5 * ones(n, 1), 'ep_n', 5 * ones(n, 1));
VAR = struct('kind', 'static', 'fd', NaN, 'D', 1, 'pol', 1);
BD = struct('name', {'0 km/h', '161 km/h'}, 'axis', 'edge', 'lo', {0, 161}, 'hi', {0, 161}, 'top', true, 'veto', false);
vz = struct('verdict', 1);
BT = struct('det', repmat(vz, 2, 2), 'surv', repmat(vz, 2, 2), 'rec', repmat(vz, 2, 2), 'prot', repmat(vz, 2, 2), ...
    'sys', ones(2, 2), 'commit', ones(2, 2));
EM = struct('ebno', eb, 'km', [1.5 1.1], 'targets', struct('det', 0.9, 'surv', 0.9, 'rec', 0.9, 'prot', 0.9, 'fa', 0.05, 'link', 0.014), ...
    'B', 400, 'delays', 1, 'fa_bound_met', true, 'ebno_thr', 0, 'cells', [1 2], 'labels', {{'jamming 4 dB', 'jamming 10 dB'}}, ...
    'bands', BD, 'bt', BT);
f = fullfile(tc.TestData.tmp, 'in', 'edge_map.mat'); save(f, 'EM', 'FT', 'VAR');
b = fullfile(tc.TestData.tmp, 'in', 'link_budget.txt');
fid = fopen(b, 'w');
fprintf(fid, '%s\n', 'x', 'Ground range of profile A tracked per altitude (km):       0 dB      3 dB', '15 m             1.50      1.10', '25 m             1.50      1.10');
fclose(fid);
S = side_a7_hover_edge(f, b, fullfile(tc.TestData.tmp, 'c2_out'));
verifyEqual(tc, numel(S.rows), 2);
verifyEqual(tc, S.rows(1).n, [24 24]);
verifyEqual(tc, S.rows(1).v(5, :), [0 0]);               % 24 flights: below the 36 a COMMITTED needs
verifyEqual(tc, S.rows(1).pooled', [1 1 1 1 1]);         % 48 flights, all successful
verifyTrue(tc, isnan(S.best_km(5, 1)));
verifyEqual(tc, S.best_km(5, 2), 1.5, 'AbsTol', 1e-12);
verifyEqual(tc, S.replay_mismatch, 0);
verifyEqual(tc, S.km_text, [1.5 1.1], 'AbsTol', 1e-12);
end

function test_hover_edge_refuses(tc)
f = fullfile(tc.TestData.tmp, 'in', 'noedge.mat'); x = 1; save(f, 'x');
verifyError(tc, @() side_a7_hover_edge(f, f, fullfile(tc.TestData.tmp, 'c2b_out')), 'side_a7:field');
end
