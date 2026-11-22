function tests = test_core_bw_switches
%TEST_CORE_BW_SWITCHES  Tests of core_bw_switches.m on synthetic RES structs.
%   Run from the repository root: results = runtests('code/tests/test_core_bw_switches.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc) %#ok<INUSD>
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root, 'code'));
setup_paths;
end

function test_means_and_pairing(tc)
RES = synth(false);
evalc('out = core_bw_switches(struct(''RES'', RES), 200, 5);');
r = pick(out.rows, 'rule_core3', 'switches');
verifyEqual(tc, r.mean, 2, 'AbsTol', 1e-12);
verifyEqual(tc, r.n, 8);
verifyTrue(tc, r.lo <= 2 && r.hi >= 2);
r = pick(out.rows, 'rule_core', 'switches');
verifyEqual(tc, r.mean, 3, 'AbsTol', 1e-12);
d = out.diffs(strcmp({out.diffs.b}, 'rule_core') & strcmp({out.diffs.metric}, 'switches'));
verifyEqual(tc, d.mean, -1, 'AbsTol', 1e-12);
verifyEqual(tc, d.lo, -1, 'AbsTol', 1e-12);          % constant difference: degenerate interval
verifyEqual(tc, d.hi, -1, 'AbsTol', 1e-12);
d = out.diffs(strcmp({out.diffs.b}, 'blind_core') & strcmp({out.diffs.metric}, 'false_sw'));
verifyEqual(tc, d.mean, -0.5, 'AbsTol', 1e-12);
end

function test_pairing_by_episode_index(tc)
% rule_core stored in a different order: the pairing follows R.ep, not the position.
RES = synth(true);
evalc('out = core_bw_switches(struct(''RES'', RES), 200, 5);');
d = out.diffs(strcmp({out.diffs.b}, 'rule_core') & strcmp({out.diffs.metric}, 'switches'));
verifyEqual(tc, d.mean, -1, 'AbsTol', 1e-12);
d = out.diffs(strcmp({out.diffs.b}, 'rule_core') & strcmp({out.diffs.metric}, 'false_sw'));
verifyEqual(tc, d.mean, -0.5, 'AbsTol', 1e-12);
end

function test_mismatched_episode_sets_refused(tc)
RES = synth(false);
i = find(strcmp({RES.policy}, 'rule_core'), 1);
RES(i).R.ep(end) = 99;
verifyError(tc, @() core_bw_switches(struct('RES', RES), 50, 5), 'core_bw_switches:episodes');
end

function test_geometry_mismatch_refused(tc)
RES = synth(false);
i = find(strcmp({RES.policy}, 'rule_core'), 1);
RES(i).R.geom(1) = RES(i).R.geom(1) + 1;
verifyError(tc, @() core_bw_switches(struct('RES', RES), 50, 5), 'core_bw_switches:geometry');
end

function test_fixed_seed_and_file_input(tc)
RES = synth(false);
f = [tempname '.mat'];
save(f, 'RES');
evalc('o1 = core_bw_switches(f, 300);');
evalc('o2 = core_bw_switches(f, 300);');
verifyEqual(tc, o1, o2);
end

function RES = synth(shuffle)
% Two geometries x four episodes. rule_core3: 2 changes per episode on average, rule_core 3.
ep = 1:8; geom = [1 1 1 1 2 2 2 2];
mk = @(sw, fs, p) struct('ep', ep(p), 'geom', geom(p), 'switches', sw(p), 'false_sw', fs(p));
p = 1:8; if shuffle, p = [8 3 5 1 7 2 6 4]; end
sw3 = [1 3 2 2 1 3 2 2];
RES = struct('rule', {}, 'set', {}, 'policy', {}, 'R', {});
RES(end+1) = struct('rule', 'LL', 'set', 'primary', 'policy', 'none', 'R', mk(zeros(1, 8), zeros(1, 8), 1:8));
RES(end+1) = struct('rule', 'LL', 'set', 'primary', 'policy', 'blind_core', 'R', mk(2.5 * ones(1, 8), 1.5 * ones(1, 8), 1:8));
RES(end+1) = struct('rule', 'LL', 'set', 'primary', 'policy', 'rule_core', 'R', mk(sw3 + 1, [1 1 2 2 1 1 2 2], p));
RES(end+1) = struct('rule', 'LL', 'set', 'primary', 'policy', 'rule_core3', 'R', mk(sw3, ones(1, 8), 1:8));
end

function r = pick(rows, pol, met)
r = rows(strcmp({rows.policy}, pol) & strcmp({rows.metric}, met));
end
