function tests = test_reader_guard
%TEST_READER_GUARD  The guard of the descriptive readers (reader_guard.m), the cluster contrast
%   (cluster_contrast.m) and the facts that keep the readers out of the pipeline: none of the pipeline's
%   files calls them, their files parse and are English, and they draw nothing from an unseeded stream.
%   Run from the repository root: results = runtests('code/tests/test_reader_guard.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
end

function f = reader_files()
f = {'diagnostics/reader_guard.m', 'diagnostics/spd_d_tables.m', 'diagnostics/spd_d_diag.m', 'diagnostics/combo_miss_tables.m', ...
    'diagnostics/combo_miss_diag.m', 'evaluation/cluster_contrast.m', 'evaluation/p1r_post_hoc.m', 'tests/test_reader_guard.m', ...
    'tests/test_spd_d.m', 'tests/test_combo_miss.m', 'tests/test_p1r_post_hoc.m'};
end

function test_out_folder(tc)
root = tc.TestData.root;
d = reader_guard('out', fullfile(root, 'results', 'x'), root);
verifyTrue(tc, endsWith(d, fullfile('results', 'x')));
verifyNotEmpty(tc, reader_guard('out', fullfile(root, 'results'), root));
verifyError(tc, @() reader_guard('out', fullfile(root, 'data'), root), 'reader_guard:out');
verifyError(tc, @() reader_guard('out', fullfile(root, 'results', '..', 'data'), root), 'reader_guard:out');
verifyError(tc, @() reader_guard('out', fullfile(root, 'resultsX'), root), 'reader_guard:out');
end

function test_input_names_and_live_trees(tc)
t = tempname;
f = fullfile(t, 'policy_pools.mat');
reader_guard('input', f, {'policy_pools.mat'});
verifyError(tc, @() reader_guard('input', fullfile(t, 'other.mat'), {'policy_pools.mat'}), 'reader_guard:input');
for live = {'uav-gcs-v7', 'uav-gcs-v7-p3', 'uav-gcs-v7-p2', 'uav-gcs-v7-p1r', 'uav-gcs-v7-bw'}
    g = fullfile(t, live{1}, 'data', 'policy_pools.mat');
    verifyError(tc, @() reader_guard('input', g, {'policy_pools.mat'}), 'reader_guard:input');
end
reader_guard('input', fullfile(t, 'uav-gcs-v7-copy', 'policy_pools.mat'), {'policy_pools.mat'});
end

function test_strip_keeps_only_the_allowed_splits(tc)
PP.pools = cell(3, 2, 4, 5);
for k = 1:numel(PP.pools), PP.pools{k} = struct('ber', 1); end
Q = reader_guard('strip', PP, [1 2]);
verifyTrue(tc, all(cellfun(@(c) ~isempty(c), Q.pools(:, :, :, 1:2)), 'all'));
verifyTrue(tc, all(cellfun(@isempty, Q.pools(:, :, :, 3:5)), 'all'));
verifyError(tc, @() reader_guard('check', PP, [1 2]), 'reader_guard:split');
verifyWarningFree(tc, @() reader_guard('check', Q, [1 2]));
V = reader_guard('strip', PP, 2);
verifyTrue(tc, all(cellfun(@isempty, V.pools(:, :, :, [1 3 4 5])), 'all'));
verifyTrue(tc, all(cellfun(@(c) ~isempty(c), V.pools(:, :, :, 2)), 'all'));
verifyError(tc, @() reader_guard('strip', PP, 6), 'reader_guard:split');
end

function test_clean_reference_copy(tc)
% The monitor's clean reference reaches the reading tree alone and is read as the pipeline reads it
% (clean_ber_ref.m, MATLAB's current folder); a pools file is never overwritten.
c0 = pwd;
a = tempname; b = tempname; d = tempname; e = tempname;
mkdir(a); mkdir(b); mkdir(d); mkdir(e);
tc.addTeardown(@() drop_dirs({a, b, d, e}));
tc.addTeardown(@() back_to(c0));
clean_ref = struct('ebno', [0 3 6 9], 'ber_est', [0.2 0.05 0.004 1e-4], 'ber', [0.2 0.05 0.004 1e-4], 'fer', [1 0.8 0.1 0]);
src = fullfile(a, 'policy_pools.mat');
save(src, 'clean_ref');
dst = reader_guard('ref', src, b);
verifyEqual(tc, char(java.io.File(pwd).getCanonicalPath()), char(java.io.File(b).getCanonicalPath()));
verifyTrue(tc, isfile(dst));
verifyEqual(tc, who('-file', dst), {'clean_ref'});
verifyEqual(tc, clean_ber_ref([3 9], 'ber_est'), [0.05 1e-4], 'RelTol', 1e-9);
verifyEqual(tc, reader_guard('ref', src, b), dst);                       % the same copy again
verifyError(tc, @() reader_guard('ref', dst, b), 'reader_guard:ref');    % a copy is not its own source
clean_ref = struct('ebno', [0 3], 'ber', [0.2 0.05]); %#ok<NASGU>
save(fullfile(a, 'no_estimate.mat'), 'clean_ref');
verifyError(tc, @() reader_guard('ref', fullfile(a, 'no_estimate.mat'), b), 'reader_guard:ref');
% a tree that holds a pools file keeps it
mkdir(fullfile(d, 'data'));
f = fullfile(d, 'data', 'policy_pools.mat');
PP = struct('x', 1); %#ok<NASGU>
clean_ref = struct('ebno', [0 3 6 9], 'ber_est', [0.2 0.05 0.004 1e-4]); %#ok<NASGU>
save(f, 'PP', 'clean_ref');
verifyError(tc, @() reader_guard('ref', src, d), 'reader_guard:ref');
verifyEqual(tc, sort(who('-file', f)), {'PP'; 'clean_ref'});
% a pipeline tree whose pools are not built (data files, no pools file) gets no reference planted
mkdir(fullfile(e, 'data'));
g = fullfile(e, 'data', 'trained_detector.mat');
det = struct('x', 1); %#ok<NASGU>
save(g, 'det');
verifyError(tc, @() reader_guard('ref', src, e), 'reader_guard:ref');
verifyFalse(tc, isfile(fullfile(e, 'data', 'policy_pools.mat')));
verifyEqual(tc, who('-file', g), {'det'});
end

function test_registration_commit(tc)
% Without a docs repository the commit is not checked, and the text that reaches the log says so.
verifyEqual(tc, reader_guard('registration', 'abc1234', ''), 'abc1234 (unverified: no docs repo)');
verifyEqual(tc, reader_guard('registration', 'abc1234'), 'abc1234 (unverified: no docs repo)');
verifyEqual(tc, reader_guard('registration', repmat('a1', 1, 20), ''), [repmat('a1', 1, 20) ' (unverified: no docs repo)']);
verifyError(tc, @() reader_guard('registration', '', ''), 'reader_guard:registration');
verifyError(tc, @() reader_guard('registration', 'XYZ1234', ''), 'reader_guard:registration');
verifyError(tc, @() reader_guard('registration', 'abc12', ''), 'reader_guard:registration');
end

function test_registration_commit_in_a_repository(tc)
% With a repository the commit must exist there and its docs/DECISIONS.md must hold D116.
[st, ~] = system('git --version');
assumeEqual(tc, st, 0);
t = tempname; mkdir(t); mkdir(fullfile(t, 'docs'));
fid = fopen(fullfile(t, 'docs', 'DECISIONS.md'), 'w'); fprintf(fid, '# Decisions\n\n## D116 - x\n'); fclose(fid);
g = @(c) system(sprintf('git -C "%s" -c user.name=t -c user.email=t@t.t -c commit.gpgsign=false %s', t, c));
[a, ~] = g('init -q'); assumeEqual(tc, a, 0);
[a, ~] = g('add docs/DECISIONS.md'); assumeEqual(tc, a, 0);
[a, ~] = g('commit -q -m one'); assumeEqual(tc, a, 0);
[a, h] = system(sprintf('git -C "%s" rev-parse HEAD', t)); assumeEqual(tc, a, 0);
h = strtrim(h);
verifyEqual(tc, reader_guard('registration', h, t), h);
verifyError(tc, @() reader_guard('registration', repmat('0', 1, 40), t), 'reader_guard:registration');
fid = fopen(fullfile(t, 'docs', 'DECISIONS.md'), 'w'); fprintf(fid, '# Decisions\n'); fclose(fid);
[a, ~] = g('commit -q -a -m two'); assumeEqual(tc, a, 0);
[a, h2] = system(sprintf('git -C "%s" rev-parse HEAD', t)); assumeEqual(tc, a, 0);
verifyError(tc, @() reader_guard('registration', strtrim(h2), t), 'reader_guard:registration');
[~, ~] = rmdir(t, 's');
end

function test_rule_code_hash_lists_cover_the_files_the_numbers_come_from(tc)
% The log prints the SHA-256 of the rule code: every interval comes from boot_cluster.m, R5's registered hit from det_frames.m.
root = tc.TestData.root;
req = struct('file', {'diagnostics/spd_d_diag.m', 'diagnostics/combo_miss_diag.m', 'evaluation/p1r_post_hoc.m'}, ...
    'names', {{'spd_d_tables.m', 'spd_d_diag.m', 'cluster_contrast.m', 'boot_cluster.m', 'reader_guard.m'}, ...
    {'combo_miss_tables.m', 'combo_miss_diag.m', 'det_frames.m', 'boot_cluster.m', 'reader_guard.m'}, ...
    {'p1r_post_hoc.m', 'cluster_contrast.m', 'boot_cluster.m', 'reader_guard.m'}});
for k = 1:numel(req)
    txt = fileread(fullfile(root, 'code', strrep(req(k).file, '/', filesep)));
    tok = regexp(txt, 'code = \{([^}]*)\};', 'tokens', 'once');
    verifyNotEmpty(tc, tok, req(k).file);
    if isempty(tok), continue; end
    listed = regexp(tok{1}, '''([^'']+)''', 'tokens');
    listed = cellfun(@(c) c{1}, listed, 'UniformOutput', false);
    verifyEmpty(tc, setdiff(req(k).names, listed), req(k).file);
    for q = req(k).names
        verifyNotEmpty(tc, which(q{1}), q{1});
    end
end
end

function test_reading_runs_once(tc)
f = [tempname '.txt'];
reader_guard('once', {f});
fid = fopen(f, 'w'); fclose(fid);
verifyError(tc, @() reader_guard('once', {f}), 'reader_guard:once');
delete(f);
end

function test_sha_and_manifest(tc)
f = [tempname '.bin'];
fid = fopen(f, 'w'); fwrite(fid, 'abc'); fclose(fid);
h = reader_guard('sha', f);
verifyEqual(tc, h, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
m = [tempname '.sha256'];
fid = fopen(m, 'w');
fprintf(fid, '%s  data/trained_dqn.mat\n%s  data/other.mat\n', h, repmat('0', 1, 64));
fclose(fid);
verifyEqual(tc, reader_guard('manifest', m, 'trained_dqn.mat'), h);
verifyEqual(tc, reader_guard('manifest', m, 'other.mat'), repmat('0', 1, 64));
verifyError(tc, @() reader_guard('manifest', m, 'absent.mat'), 'reader_guard:sha');
delete(f); delete(m);
end

function test_cluster_contrast_known_values(tc)
x = [ones(30, 1); 0.5 * ones(30, 1)];
a = [true(30, 1); false(30, 1)]; b = ~a;
cl = [repelem((1:10)', 3); repelem((11:20)', 3)];
[d, lo, hi, n] = cluster_contrast(x, a, b, cl, 500, 3);
verifyEqual(tc, d, 0.5, 'AbsTol', 1e-12);
verifyEqual(tc, lo, 0.5, 'AbsTol', 1e-12);
verifyEqual(tc, hi, 0.5, 'AbsTol', 1e-12);
verifyEqual(tc, n, [30 30 10 10]);
% a negative contrast and the pairing of the two groups
[d2, lo2, hi2] = cluster_contrast(x, b, a, cl, 500, 3);
verifyEqual(tc, [d2 lo2 hi2], [-0.5 -0.5 -0.5], 'AbsTol', 1e-12);
end

function test_cluster_contrast_interval_and_seed(tc)
rs = RandStream('mt19937ar', 'Seed', 5);
cl = repelem((1:40)', 5);
a = repmat([true; true; true; false; false], 40, 1); b = ~a;
x = double(rand(rs, 200, 1) < 0.5 + 0.2 * a);
[d, lo, hi, n] = cluster_contrast(x, a, b, cl, 800, 11);
verifyLessThan(tc, lo, d); verifyGreaterThan(tc, hi, d);
verifyGreaterThan(tc, lo, -0.3); verifyLessThan(tc, hi, 0.7);
verifyEqual(tc, n(3:4), [40 40]);
[d1, lo1, hi1] = cluster_contrast(x, a, b, cl, 800, 11);
verifyEqual(tc, [d lo hi], [d1 lo1 hi1]);
end

function test_cluster_contrast_empty_groups_and_nan(tc)
x = [1; 2; 3; NaN]; cl = [1; 1; 2; 3];
[d, lo, hi, n] = cluster_contrast(x, [true; true; false; true], [false; false; false; false], cl, 100, 1);
verifyTrue(tc, isnan(d) && isnan(lo) && isnan(hi));
verifyEqual(tc, n(1:2), [2 0]);
[d, ~, ~, n] = cluster_contrast(x, [true; true; false; true], [false; false; true; false], cl, 100, 1);
verifyEqual(tc, d, 1.5 - 3, 'AbsTol', 1e-12);
verifyEqual(tc, n, [2 1 1 1]);
[d, ~, ~, n] = cluster_contrast([], false(0, 1), false(0, 1), zeros(0, 1), 100, 1);
verifyTrue(tc, isnan(d)); verifyEqual(tc, n, [0 0 0 0]);
end

function test_pipeline_does_not_call_the_readers(tc)
% The readers are not wired into any stage: no file of the pipeline names them, so with them absent
% every stage runs as before.
root = tc.TestData.root;
own = reader_files();
own = cellfun(@(f) strrep(f, '/', filesep), own, 'UniformOutput', false);
names = {'spd_d_diag', 'spd_d_tables', 'combo_miss_diag', 'combo_miss_tables', 'p1r_post_hoc', 'reader_guard', 'cluster_contrast'};
f = dir(fullfile(root, 'code', '**', '*.m'));
f = f(~contains({f.folder}, [filesep 'legacy']));
n = 0;
for i = 1:numel(f)
    full = fullfile(f(i).folder, f(i).name);
    if any(endsWith(full, own)), continue; end
    txt = fileread(full);
    n = n + 1;
    for k = 1:numel(names)
        verifyEmpty(tc, strfind(txt, names{k}), sprintf('%s names %s', f(i).name, names{k}));
    end
end
verifyGreaterThan(tc, n, 100);
end

function test_new_files_parse_and_are_english(tc)
root = tc.TestData.root;
for k = reader_files()
    full = fullfile(root, 'code', strrep(k{1}, '/', filesep));
    verifyTrue(tc, isfile(full), full);
    txt = fileread(full);
    t = mtree(txt);
    verifyFalse(tc, strcmp(t.root.kind, 'ERR'), k{1});
    verifyTrue(tc, all(double(txt) < 128), sprintf('%s holds a character beyond ASCII', k{1}));
end
end

function test_no_unseeded_randomness(tc)
root = tc.TestData.root;
for k = reader_files()
    if startsWith(k{1}, 'tests/'), continue; end
    txt = fileread(fullfile(root, 'code', strrep(k{1}, '/', filesep)));
    verifyEmpty(tc, regexp(txt, '(?<![\w.])(rand|randn|randperm|rng|randsample)\s*\(', 'once'), k{1});
    verifyEmpty(tc, regexp(txt, '(?<![\w.])randi\s*\((?!rs\b)', 'once'), k{1});
end
end

function test_rollout_seeds_are_their_own(tc)
% SPD-D's frame draws (base + 1000 split + batch) lie above every other rollout base (edge_map.m
% 40000-299000, evaluate_policies.m, train_dqn.m) and below the first flight stream.
src = fileread(which('spd_d_diag'));
tok = regexp(src, 'SEED_RUN = (\d+);', 'tokens', 'once');
run0 = str2double(tok{1});
tok = regexp(src, 'SEED_EP = (\d+);', 'tokens', 'once');
ep0 = str2double(tok{1});
lo = run0 + 1000; hi = run0 + 2000 + 999;
verifyGreaterThan(tc, lo, 299000);
verifyLessThan(tc, hi, seed_base(700001));
verifyFalse(tc, any(ismember(ep0 + [1 2], [2027 2028 2074])));
end

function drop_dirs(items)
for k = 1:numel(items)
    if isfolder(items{k}), [~, ~] = rmdir(items{k}, 's'); end
end
end

function back_to(c0)
cd(c0);
clear('clean_ber_ref');
end
