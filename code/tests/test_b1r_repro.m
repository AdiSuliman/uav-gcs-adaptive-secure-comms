function tests = test_b1r_repro
%TEST_B1R_REPRO  The B1-R reproduction driver (tools/b1r/b1r_repro.m) on synthetic inputs: the run root
%   (copies with their dates, data as links, outputs left out), the exact comparison and its kinds,
%   the lecturer table's number-on-line check, the refusals, and a whole 'policy' stage with the
%   evaluation and the renderers stubbed. Temporary folders only; no pools, no real tree.
%   Run from the repository root: results = runtests('code/tests/test_b1r_repro.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root, 'code')); setup_paths;
addpath(fullfile(root, 'tools', 'b1r'));
tc.TestData.root = root;
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp);
end

function teardownOnce(tc)
rm_all(tc.TestData.tmp);
end

%% ---------- the synthetic tree ----------
function tree = make_tree(tc, name)
tree = fullfile(tc.TestData.tmp, name);
mkdir(fullfile(tree, 'results', 'sub')); mkdir(fullfile(tree, 'data'));
params = struct('n_rx', 3); %#ok<NASGU>
save(fullfile(tree, 'params.mat'), 'params');
RES = {1, [2 3; 4 5]}; KP = struct('a', 1.5, 'generated', 'x'); %#ok<NASGU>
save(fullfile(tree, 'results', 'policy_evaluation.mat'), 'RES', 'KP');
write(fullfile(tree, 'results', 'policy_evaluation.txt'), {'Generated: 1', 'row 1 0.50', 'row 2 0.75'});
write(fullfile(tree, 'results', 'kpi_summary.txt'), {'Generated: 1', 'KPI 5: 41.0'});
write(fullfile(tree, 'results', 'sub', 'keep.txt'), {'kept'});
x = 1:10; %#ok<NASGU>
save(fullfile(tree, 'data', 'pools.mat'), 'x');
fileattrib(fullfile(tree, 'data', 'pools.mat'), '-w');
t = java.nio.file.attribute.FileTime.fromMillis(java.lang.System.currentTimeMillis() - 86400000 * 30);
java.nio.file.Files.setLastModifiedTime(java.io.File(fullfile(tree, 'results', 'sub', 'keep.txt')).toPath(), t);
end

function write(f, lines)
fid = fopen(f, 'w'); fprintf(fid, '%s\n', lines{:}); fclose(fid);
end

function rm_all(d)
if isfolder(d), fileattrib(d, '+w', '', 's'); rmdir(d, 's'); end
end

%% ---------- run root ----------
function test_build_root_copies_links_and_leaves_out(tc)
tree = make_tree(tc, 'tree_a');
root = fullfile(tc.TestData.tmp, 'root_a');
b1r_repro('build_root', root, tree, {'results/policy_evaluation.mat', 'results/policy_evaluation.txt', 'results/kpi_summary.txt'});
tc.verifyFalse(isfile(fullfile(root, 'results', 'policy_evaluation.mat')));
tc.verifyFalse(isfile(fullfile(root, 'results', 'kpi_summary.txt')));
tc.verifyTrue(isfile(fullfile(root, 'params.mat')));
tc.verifyTrue(isfile(fullfile(root, 'results', 'sub', 'keep.txt')));
d1 = dir(fullfile(tree, 'results', 'sub', 'keep.txt')); d2 = dir(fullfile(root, 'results', 'sub', 'keep.txt'));
tc.verifyEqual(d2.datenum, d1.datenum, 'AbsTol', 1 / 86400, 'the copy keeps the date');
a = java.io.File(fullfile(tree, 'data', 'pools.mat')).toPath(); b = java.io.File(fullfile(root, 'data', 'pools.mat')).toPath();
tc.verifyTrue(java.nio.file.Files.isSameFile(a, b), 'data is a link');
tc.verifyFalse(java.io.File(fullfile(tree, 'data', 'pools.mat')).canWrite(), 'the tree file stays read-only');
tc.verifyError(@() b1r_repro('build_root', root, tree, {}), 'b1r_repro:exists');
tc.verifyError(@() b1r_repro('build_root', fullfile(tree, 'inner'), tree, {}), 'b1r_repro:inside');
end

%% ---------- comparison ----------
function test_diff_paths_and_stamps(tc)
A = struct('v', [1 2 NaN], 'c', {{1, 'a'}}, 's', struct('generated', 'x', 'k', 1), 'g', 'Generated: 5');
B = A; B.s.generated = 'y'; B.g = 'Generated: 6';
tc.verifyEmpty(b1r_repro('diff', A, B), 'a generated field and a Generated string are set aside');
B.v(2) = 3; B.c{2} = 'b'; B.s.k = 2; B.extra = 1;
D = b1r_repro('diff', A, B);
tc.verifyEqual(numel(D), 4);
tc.verifyTrue(any(contains(D, 'x.v: 1 of 3 values differ, max abs 1')));
tc.verifyTrue(any(contains(D, 'x.c{2}')));
tc.verifyTrue(any(contains(D, 'x.s.k')));
tc.verifyTrue(any(contains(D, 'x.extra (only registered)')));
tc.verifyEmpty(b1r_repro('diff', struct('v', NaN), struct('v', NaN)), 'NaN equals NaN');
end

function test_compare_kinds(tc)
d = fullfile(tc.TestData.tmp, 'cmp'); mkdir(d);
write(fullfile(d, 'a.txt'), {'Generated: 1', 'x 1'}); write(fullfile(d, 'b.txt'), {'Generated: 1', 'x 1'});
write(fullfile(d, 'c.txt'), {'Generated: 2', 'x 1'}); write(fullfile(d, 'e.txt'), {'Generated: 1', 'x 2'});
write(fullfile(d, 'f.txt'), {'Generated: 1', 'run took (12.3 min)'}); write(fullfile(d, 'g.txt'), {'Generated: 1', 'run took (12.9 min)'});
r = b1r_repro('compare', 's', 'n', fullfile(d, 'a.txt'), fullfile(d, 'b.txt')); tc.verifyEqual(r.kind, 'exact');
r = b1r_repro('compare', 's', 'n', fullfile(d, 'c.txt'), fullfile(d, 'a.txt')); tc.verifyEqual(r.kind, 'equal-lines'); tc.verifyTrue(r.ok);
r = b1r_repro('compare', 's', 'n', fullfile(d, 'e.txt'), fullfile(d, 'a.txt')); tc.verifyEqual(r.kind, 'DIFF'); tc.verifyFalse(r.ok);
tc.verifyTrue(contains(r.detail, 'line 2'));
r = b1r_repro('compare', 's', 'n', fullfile(d, 'f.txt'), fullfile(d, 'g.txt')); tc.verifyEqual(r.kind, 'DIFF-timing'); tc.verifyFalse(r.ok);
r = b1r_repro('compare', 's', 'n', fullfile(d, 'nope.txt'), fullfile(d, 'a.txt')); tc.verifyEqual(r.kind, 'DIFF');
r = b1r_repro('compare', 's', 'n', fullfile(d, 'a.txt'), fullfile(d, 'nope.txt')); tc.verifyEqual(r.kind, 'info');
write(fullfile(d, 'h.txt'), {'Generated: 1', 'x 1', 'new side line'});
r = b1r_repro('compare', 's', 'n', fullfile(d, 'h.txt'), fullfile(d, 'a.txt')); tc.verifyEqual(r.kind, 'DIFF-additive'); tc.verifyFalse(r.ok);
% .mat: stamps aside equal, a numeric field differs
M1 = struct('v', 1, 'generated', 'a'); M2 = struct('v', 1, 'generated', 'b'); M3 = struct('v', 2, 'generated', 'a');
save(fullfile(d, 'm1.mat'), '-struct', 'M1'); save(fullfile(d, 'm2.mat'), '-struct', 'M2'); save(fullfile(d, 'm3.mat'), '-struct', 'M3');
r = b1r_repro('compare', 's', 'n', fullfile(d, 'm2.mat'), fullfile(d, 'm1.mat')); tc.verifyEqual(r.kind, 'equal-fields');
r = b1r_repro('compare', 's', 'n', fullfile(d, 'm3.mat'), fullfile(d, 'm1.mat')); tc.verifyEqual(r.kind, 'DIFF');
M4 = struct('v', 1, 'generated', 'a', 'more', 5); save(fullfile(d, 'm4.mat'), '-struct', 'M4');
r = b1r_repro('compare', 's', 'n', fullfile(d, 'm4.mat'), fullfile(d, 'm1.mat')); tc.verifyEqual(r.kind, 'DIFF-additive');
% images: a rendering is not an exact comparison
im = uint8(zeros(40, 40, 3)); imwrite(im, fullfile(d, 'i1.png')); im(1, 1, :) = 255; imwrite(im, fullfile(d, 'i2.png'));
r = b1r_repro('compare', 's', 'n', fullfile(d, 'i2.png'), fullfile(d, 'i1.png')); tc.verifyEqual(r.kind, 'rendering'); tc.verifyTrue(r.ok);
end

%% ---------- lecturer numbers ----------
function test_lect_values(tc)
d = fullfile(tc.TestData.tmp, 'lect'); mkdir(d);
write(fullfile(d, 'src.txt'), {'first', 'PER 41.3% [38.0, 44.6]', 'gap +0.03 dB'});
write(fullfile(d, 'rep.txt'), {'inserted', 'first', 'PER 41.3% [38.0, 44.6]', 'gap +0.04 dB'});
src = strrep(fullfile(d, 'src.txt'), '\', '/');
write(fullfile(d, 'n.csv'), {'id,value,ci_lo,ci_hi,source_file,source_line', ...
    sprintf('N1,41.3,38.0,44.6,%s,2', src), sprintf('N2,+0.03,,,%s,3', src), sprintf('N3,99,,,%s,2', src)});
V = b1r_repro('lect_values', fullfile(d, 'n.csv'), containers.Map('KeyType', 'char', 'ValueType', 'char'));
tc.verifyEqual([V.n V.literal V.derived V.n_repro V.repro_missing], [3 2 1 0 0]);
m = containers.Map('KeyType', 'char', 'ValueType', 'char'); m(lower(src)) = fullfile(d, 'rep.txt');
V = b1r_repro('lect_values', fullfile(d, 'n.csv'), m);
tc.verifyEqual([V.n_repro V.repro_missing], [3 1], 'the cited line is looked for anywhere in the reproduced file: only the changed one (N2) is missing');
tc.verifyTrue(startsWith(V.missing{1}, 'N2'));
end

%% ---------- refusals ----------
function test_run_refuses_existing_and_inside(tc)
d = fullfile(tc.TestData.tmp, 'exists'); mkdir(d);
tc.verifyError(@() b1r_repro('run', 'p1', 'light', d), 'b1r_repro:exists');
C = b1r_repro('config', 'p1');
tc.verifyError(@() b1r_repro('run', 'p1', 'light', fullfile(C.tree, 'scratch')), 'b1r_repro:inside');
tc.verifyError(@() b1r_repro('run', 'p1', 'middle', fullfile(tc.TestData.tmp, 'x')), 'b1r_repro:part');
tc.verifyError(@() b1r_repro('config', 'p2'), 'b1r_repro:tag');
end

%% ---------- a whole policy stage on a synthetic tree ----------
function test_policy_stage_off_stubbed(tc)
tree = make_tree(tc, 'tree_p');
out = fullfile(tc.TestData.tmp, 'out_p'); mkdir(out);
C = b1r_repro('config', 'p1');
C.tree = tree; C.bundle_ref = fullfile(tc.TestData.tmp, 'no_bundle'); C.repo = tc.TestData.root;
% the stubs write what the registered run holds, so every comparison is exact; the second pass changes one value
ev = @(root, cfg) stub_eval(root, tree, 0);
rn = @(root, tab) stub_render(root, tree);
O = struct('eval_fn', ev, 'render_fn', rn);
rows = b1r_repro('policy', C, 'off', out, O);
kinds = {rows.kind}; names = {rows.name};
tc.verifyEqual(kinds{strcmp(names, 'results/policy_evaluation.mat')}, 'equal-fields', 'only the generated field differs');
tc.verifyEqual(kinds{strcmp(names, 'results/policy_evaluation.txt')}, 'equal-lines', 'only the Generated line differs');
tc.verifyEqual(kinds{strcmp(names, 'results/kpi_summary.txt')}, 'equal-lines');
tc.verifyEqual(kinds{strcmp(names, 'results/report_numbers.json')}, 'info', 'neither produced nor registered');
tc.verifyTrue(all([rows.ok]), strjoin(cellfun(@(n, k) [n ':' k], names, kinds, 'UniformOutput', false), ' '));
out2 = fullfile(tc.TestData.tmp, 'out_p2'); mkdir(out2);
O.eval_fn = @(root, cfg) stub_eval(root, tree, 1);
rows = b1r_repro('policy', C, 'off', out2, O);
k = {rows.kind}; n = {rows.name};
tc.verifyEqual(k{strcmp(n, 'results/policy_evaluation.mat')}, 'DIFF');
tc.verifyEqual(k{strcmp(n, 'results/policy_evaluation.txt')}, 'DIFF');
end

function stub_eval(root, tree, delta)
RES = {1, [2 3; 4 5] + delta}; KP = struct('a', 1.5, 'generated', 'y'); %#ok<NASGU>
save(fullfile(root, 'results', 'policy_evaluation.mat'), 'RES', 'KP');
L = {'Generated: 2', 'row 1 0.50', sprintf('row 2 %.2f', 0.75 + delta / 100)};
write(fullfile(root, 'results', 'policy_evaluation.txt'), L);
assert(isfile(fullfile(tree, 'params.mat')));
end

function err = stub_render(root, tree) %#ok<INUSD>
write(fullfile(root, 'results', 'kpi_summary.txt'), {'Generated: 3', 'KPI 5: 41.0'});
err = {};
end

%% ---------- the real inputs are where the configuration says ----------
function test_config_inputs_exist(tc)
% Skipped where the project's trees are not (another machine): the paths of both profiles and the overlay's CFG.
for tag = {'p1', 'p3'}
    C = b1r_repro('config', tag{1});
    tc.assumeTrue(isfolder(C.tree));
    for f = {fullfile(C.tree, 'results', 'policy_evaluation.mat'), fullfile(C.tree, 'data', 'policy_pools.mat'), ...
            fullfile(C.tree, 'data', 'trained_dqn.mat'), fullfile(C.ad_root, 'adoption.json'), fullfile(C.rf, 'test.mat'), ...
            fullfile(C.ad_root, 'on', 'results', 'policy_evaluation.mat'), fullfile(C.sysfa, 'results', 'policy_evaluation.mat'), ...
            fullfile(C.sysfa, 'results', 'system_fa_breakdown.mat'), fullfile(C.lect, 'lect_numbers.csv')}
        tc.verifyTrue(isfile(f{1}), f{1});
    end
    cfg = adopt_reading('cfg', jsondecode(fileread(fullfile(C.ad_root, 'adoption.json'))));
    tc.verifyEqual(cfg.adopt.rule_fix, 'keep+st+rate');
end
C = b1r_repro('config', 'p1');
for f = {'protocol.json', 'recoverable.txt', 'validation.mat', 'test_readings.mat', 'core_bw_report.txt', 'core_bw_kpis.mat'}
    tc.verifyTrue(isfile(fullfile(C.bw, 'results', 'core_bw', f{1})), f{1});
end
tc.verifyTrue(isfile(fullfile(C.bw, 'docs', 'core_bw_frozen.json')));
end

%% ---------- the return code ----------
function test_summary_return_code(tc)
% 0 all ok; 1 only additive or renderer-output differences; 2 any other difference or an error.
mk = @(stage, kind) struct('stage', stage, 'name', 'n', 'kind', kind, 'ok', ismember(kind, {'exact', 'equal-lines', 'info'}), 'detail', '');
d = fullfile(tc.TestData.tmp, 'sum'); mkdir(d);
R = b1r_repro('summary', [mk('off', 'exact'), mk('off', 'info')], 'p1', 'x', d);
tc.verifyEqual(R.rc, 0);
R = b1r_repro('summary', [mk('off', 'exact'), mk('bw', 'DIFF-additive'), mk('policy_off/render', 'DIFF')], 'p1', 'y', d);
tc.verifyEqual(R.rc, 1);
R = b1r_repro('summary', [mk('bw', 'DIFF-additive'), mk('off', 'DIFF')], 'p1', 'z', d);
tc.verifyEqual(R.rc, 2);
R = b1r_repro('summary', [mk('render', 'ERROR')], 'p1', 'w', d);
tc.verifyEqual(R.rc, 2, 'an error is hard even in a renderer stage');
tc.verifyTrue(isfile(fullfile(d, 'b1r_p1_z_summary.txt')));
end
