function tests = test_smoke
%TEST_SMOKE  The deploy smoke's prerequisites for profile 3: the driver's start line and steps
%   (docs/d91_smoke_deploy.m.txt), its two forced cells (dep_OODk2, dep_B2Fext) and the release
%   check's forced-field assertion (profile_forced_fields.m). Run from the repository root:
%   results = runtests('code/tests/test_smoke.m').
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.cwd = pwd;
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp);
tc.TestData.src = fileread(fullfile(tc.TestData.root, 'docs', 'd91_smoke_deploy.m.txt'));
end

function teardownOnce(tc)
cd(tc.TestData.cwd);
rmdir(tc.TestData.tmp, 's');
end

%% ---------- fixtures ----------
function d = work_dir(tc)
% A fresh folder, entered; the test's cleanup returns to the repository.
d = tempname; mkdir(d); cd(d);
mkdir(fullfile(d, 'data'));
end

function write_text(f, t)
fid = fopen(f, 'w'); fwrite(fid, t); fclose(fid);
end

function s = smoke_form()
% profile 3's smoke form (STOP_SOFT step 7a bullet and the forced cells).
s = ['{"profile":"profile 3: four antennas","n_rx":4,"skip_stages":["OHP","GCSA"],' ...
    '"fec_rx":{"mode":"jsi","rev":"smoke-placeholder","q":0.05,"c":4,"h":1,"erase_sym":true,"frame":"c","thr":0.5,"flag_clean":0.01},' ...
    '"surv_v2":true,"deg_select":true,"dconf_select":true,"dconf_force":[1,1],"dconf_own":true,"s1g_select":true,"s1g_force":true,' ...
    '"relm_select":true,"relm_force":true,"r9_print":true,"k6_split":true,"lb_select":true,"lb_force":true,"fa_nothreat":true,' ...
    '"aprime_force":true,"speed_inference":true,"speed_band_table":true,"kpi7_union":"descriptive","edge161_n":48,' ...
    '"unseen_gap":true,"k2_0":true}'];
end

function s = real_form()
% the real profile.json after step 7a: the smoke form without its forced cells.
s = ['{"profile":"profile 3: four antennas","n_rx":4,"skip_stages":["OHP","GCSA"],' ...
    '"fec_rx":{"mode":"jsi","rev":"D122","q":0.05,"c":4,"h":1,"erase_sym":true,"frame":"c","thr":0.5,"flag_clean":0.01},' ...
    '"surv_v2":true,"deg_select":true,"dconf_select":true,"dconf_own":true,"s1g_select":true,' ...
    '"relm_select":true,"r9_print":true,"k6_split":true,"lb_select":true,"fa_nothreat":true,' ...
    '"speed_inference":true,"speed_band_table":true,"kpi7_union":"descriptive","edge161_n":48,' ...
    '"unseen_gap":true,"k2_0":true}'];
end

function lists = driver_lists(src)
% The driver's step lists: chain, tail, dep.
lists = struct();
for n = {'chain', 'tail', 'dep'}
    b = regexp(src, [n{1} ' = \{([^}]*)\}'], 'tokens', 'once');
    assert(~isempty(b), 'test:driver', 'no %s list in the driver', n{1});
    v = regexp(b{1}, '''(\w+)''', 'tokens'); lists.(n{1}) = [v{:}];
end
end

function load_local(src, names, d)
% Writes the driver's local functions of the given names into folder d, one file each.
for n = names
    t = regexp(src, ['function [^\n]*= ' n{1} '\(\).*?(?=\r?\n\r?\nfunction )'], 'match', 'once');
    assert(~isempty(t), 'test:driver', 'function %s not found in the driver', n{1});
    write_text(fullfile(d, [n{1} '.m']), regexprep(t, '\r\n', newline));
end
end

%% ---------- the driver ----------
function test_driver_steps(tc)
% Fifty-five steps; dep_OODk2 after B2Fsave and before the re-key, dep_B2Fext last (it rewrites
% data/fusion.mat); every dep step reaches its own case, not the stage fallback.
src = tc.TestData.src;
L = driver_lists(src);
verifyEqual(tc, numel(L.chain) + numel(L.tail) + numel(L.dep), 55);
k = @(n) find(strcmp(L.dep, n));
verifyTrue(tc, isscalar(k('OODk2')) && isscalar(k('B2Fext')) && isscalar(k('B2Fsave')) && isscalar(k('REKEY')), strjoin(L.dep, ' '));
verifyEqual(tc, k('OODk2'), k('B2Fsave') + 1);
verifyEqual(tc, k('REKEY'), k('OODk2') + 1);
verifyEqual(tc, k('B2Fext'), numel(L.dep));
for n = {'dep_OODk2', 'dep_B2Fext'}
    verifyNumElements(tc, strfind(src, ['case ''' n{1} '''']), 1, n{1});
end
% the cases precede the fallback that would call run_stage('smoke', 'OODk2')
verifyLessThan(tc, strfind(src, 'case ''dep_B2Fext'''), strfind(src, 'run_stage(''smoke'', regexprep(st'));
end

function test_driver_forced_cells(tc)
% The two forced cells are the registered ones, smoke only, and the steps check that the result is
% marked and cannot be read as a reading.
src = strrep(tc.TestData.src, sprintf('\r'), '');
b = regexp(src, 'function ood_forced\(\).*?\nend\n', 'match', 'once');
verifyNotEmpty(tc, strfind(b, 'SMOKE = true; OOD_PHASE = ''select''; OOD_FORCE = ''C1'';'));
verifyNotEmpty(tc, strfind(b, 'run(''ood_k2_run'');'));
b = regexp(src, 'function b2f_ext\(\).*?\nend\n', 'match', 'once');
verifyNotEmpty(tc, strfind(b, ['SMOKE = true; FUSION_REV = true; FUSION_FIT = ''enlarged''; FUSION_RULE_LOG = true; ' ...
    'FUSION_EXT_FORCE = ''GCC+CFAR'';']));
verifyNotEmpty(tc, strfind(b, 'run(''select_fusion'');'));
b = regexp(src, 'case ''dep_OODk2''.*?case ''dep_REKEY''', 'match', 'once');
verifyNotEmpty(tc, strfind(b, 'FM.unk.forced'));
verifyNotEmpty(tc, strfind(b, 'results/ood_k2_select.mat'));          % the real run's files stay absent
b = regexp(src, 'case ''dep_B2Fext''.*?otherwise', 'match', 'once');
for s = {'fusion_rev_id(''enlarged'', P)', 'fusion_reading(''_fresh2'')', 'deploy_state()', 'check.ext.adopted'}
    verifyNotEmpty(tc, strfind(b, s{1}), s{1});
end
end

function test_forced_fusion_is_no_reading(tc)
% What dep_B2Fext asserts: a fusion saved with a candidate over the pick carries its own revision
% id, so it reads as no deployed revision and deploy_state stays 'none'.
d = work_dir(tc); back = onCleanup(@() cd(tc.TestData.cwd)); %#ok<NASGU>
P = fusion_pick('GCC+CFAR');
verifyNotEqual(tc, fusion_rev_id('enlarged', P), fusion_rev_id('enlarged'));
fusion_rev = fusion_rev_id('enlarged', P); %#ok<NASGU>
deployed_pick = P; deployed_pick.check = struct('kept', struct('N', P.N, 'lambda', P.lambda, 'latch', false, 'cues', false)); %#ok<NASGU>
FM = struct('latch', false, 'cues', P.cues); N = P.N; lambda = P.lambda; %#ok<NASGU>
save(fullfile(d, 'data', 'fusion.mat'), 'FM', 'N', 'lambda', 'fusion_rev', 'deployed_pick');
R = fusion_reading('_fresh2');
verifyEmpty(tc, R.state);
verifyEmpty(tc, R.sample);
verifyEqual(tc, deploy_state(), 'none');
end

function test_forced_candidate_needs_the_old_layout(tc)
% dep_B2Fext runs select_fusion with FUSION_EXT_FORCE over the kept fusion: the pick deployed before
% is no base for a candidate (select_fusion:pick_base), the old layout at the pick's N, lambda and
% latch is, so the step restores it first (old_fusion in the driver).
w = fullfile(tc.TestData.tmp, 'b2f_ext'); mkdir(fullfile(w, 'data'));
c0 = cd(w); back = onCleanup(@() cd(c0)); %#ok<NASGU>
for f = {'data/dataset.mat', 'data/splits_fresh.mat', 'data/dataset_fresh.mat', 'data/splits_fresh2.mat', 'data/dataset_fresh2.mat'}
    x = 1; save(f{1}, 'x');
end
E = struct('SMOKE', true, 'FUSION_REV', true, 'FUSION_FIT', 'enlarged', 'FUSION_RULE_LOG', true, 'FUSION_EXT_FORCE', 'GCC+CFAR');
P = fusion_pick(); N = P.N; lambda = P.lambda; %#ok<NASGU>
FM = struct('latch', P.latch, 'cues', P.cues); fusion_rev = fusion_rev_id('enlarged', P);
deployed_pick = P; deployed_pick.check = struct('all', [0 0 0]); %#ok<NASGU>
save('data/fusion.mat', 'N', 'lambda', 'FM', 'deployed_pick', 'fusion_rev');          % the pick deployed (dep_B2Fsave)
verifyEqual(tc, b2f_err(E).identifier, 'select_fusion:pick_base');
delete('data/fusion_nogo.mat');
FM = struct('latch', P.latch); save('data/fusion.mat', 'N', 'lambda', 'FM');          % the old layout (old_fusion)
ex = b2f_err(E); verifyFalse(tc, startsWith(ex.identifier, 'select_fusion:'), ex.identifier);   % past the checks, stopped at the data
end

function ex = b2f_err(o)
% The error select_fusion stops with when run with the variables of struct o set.
for f = fieldnames(o)'
    eval([f{1} ' = o.(f{1});']);
end
ex = MException('test:none', 'no error');
try
    evalc('run(''select_fusion'')');
catch ex
end
end

function test_driver_start_line(tc)
% rx_count reads the profile before params.mat (3 before A0 has run); the start line prints n_rx,
% the decoder's mode, surv_v2, deg_select and every switch of the step-7a form.
src = tc.TestData.src;
d = work_dir(tc); back = onCleanup(@() cd(tc.TestData.cwd)); %#ok<NASGU>
load_local(src, {'rx_count', 'profile_text'}, d);
params = struct('n_rx', 3); save('params.mat', 'params');
verifyEqual(tc, rx_count(), 3);                                       % no profile.json: params.mat
write_text('profile.json', '{"profile":"x"}');
verifyEqual(tc, rx_count(), 3);                                       % no n_rx in the profile
write_text('profile.json', smoke_form());
verifyEqual(tc, rx_count(), 4);                                       % the profile wins over params.mat
s = profile_text();
verifyEqual(tc, numel(strfind(s, newline)), 0);
want = {'n_rx 4,', 'fec_rx jsi,', 'surv_v2 1,', 'deg_select 1,', 'deg_force none,', 'dconf_select 1,', 'dconf_force [1 1],', ...
    'dconf_own 1,', 's1g_select 1,', 's1g_force 1,', 'relm_select 1,', 'relm_force 1,', 'r9_print 1,', 'k6_split 1,', ...
    'core3_pools 0,', 'lb_select 1,', 'lb_force 1,', 'fa_nothreat 1,', 'aprime_force 1,', 'speed_inference 1,', ...
    'speed_band_table 1,', 'kpi7_union descriptive,', 'edge161_n 48,', 'unseen_gap 1,', 'k2_0 1'};
for w = want
    verifyNotEmpty(tc, strfind(s, w{1}), [w{1} ' in: ' s]);
end
write_text('profile.json', real_form());
s = profile_text();
for w = {'n_rx 4,', 'fec_rx jsi,', 'surv_v2 1,', 'deg_select 1,', 'dconf_force none,', 's1g_force 0,', 'relm_force 0,', ...
        'lb_force 0,', 'aprime_force 0,'}
    verifyNotEmpty(tc, strfind(s, w{1}), [w{1} ' in: ' s]);
end
delete('profile.json');                                               % profile 1's checkout: nothing stated
s = profile_text();
verifyNotEmpty(tc, strfind(s, 'n_rx 3, fec_rx none, surv_v2 0, deg_select 0,'));
end

%% ---------- the release check ----------
function test_profile_forced_fields(tc)
d = work_dir(tc); back = onCleanup(@() cd(tc.TestData.cwd)); %#ok<NASGU>
verifyEmpty(tc, profile_forced_fields());                             % no file
write_text('profile.json', real_form());
verifyEmpty(tc, profile_forced_fields());
write_text('profile.json', '[1, 2]');
verifyEmpty(tc, profile_forced_fields());
write_text('profile.json', smoke_form());
verifyEqual(tc, sort(profile_forced_fields()), sort({'dconf_force', 's1g_force', 'relm_force', 'lb_force', 'aprime_force'}));
write_text('profile.json', strrep(real_form(), '"n_rx":4', '"n_rx":4,"deg_force":"win"'));
verifyEqual(tc, profile_forced_fields(), {'deg_force'});
write_text('profile.json', strrep(real_form(), '"n_rx":4', '"n_rx":4,"ood_force":"C1","fusion_ext_force":"GCC+CFAR"'));
verifyEqual(tc, sort(profile_forced_fields()), {'fusion_ext_force', 'ood_force'});
write_text('other.json', smoke_form());
verifyNumElements(tc, profile_forced_fields('other.json'), 5);
end

function test_release_check_expression(tc)
% The release check of STOP_SOFT step 8 (the note p3_deploy_prep.md, section 3.11): the real form
% passes; the smoke form, and each forced field alone, stop it.
d = work_dir(tc); back = onCleanup(@() cd(tc.TestData.cwd)); %#ok<NASGU>
chk = ['P = jsondecode(fileread(''profile.json'')); R = fec_rx_config(); S = surv_options(); G = deg_options(); ' ...
    'Fz = profile_forced_fields(); assert(P.n_rx == 4 && ~isempty(R) && S.v2 && G.on && isempty(Fz), ''release:profile'', ' ...
    '''profile.json lacks n_rx 4, fec_rx, surv_v2 true or deg_select true, or holds a forced field: %s'', strjoin(Fz, '' '')); ' ...
    'fprintf(''V7RELEASE profile.json OK: n_rx %d, fec_rx %s, surv_v2 %d, deg_select %d, forced fields %d\n'', ' ...
    'P.n_rx, R.mode, S.v2, G.on, numel(Fz));'];
write_text('profile.json', real_form());
out = release_run(chk);
verifyNotEmpty(tc, strfind(out, 'V7RELEASE profile.json OK: n_rx 4, fec_rx jsi, surv_v2 1, deg_select 1, forced fields 0'));
write_text('profile.json', smoke_form());
verifyError(tc, @() release_run(chk), 'release:profile');
for f = {'"dconf_force":[1,1]', '"s1g_force":true', '"relm_force":true', '"lb_force":true', '"aprime_force":true', '"deg_force":"win"'}
    write_text('profile.json', strrep(real_form(), '"n_rx":4', ['"n_rx":4,' f{1}]));
    verifyError(tc, @() release_run(chk), 'release:profile', f{1});
end
write_text('profile.json', strrep(real_form(), '"deg_select":true,', ''));    % the four fields keep their meaning
verifyError(tc, @() release_run(chk), 'release:profile');
end

function out = release_run(chk)
% The release check's expression in this function's workspace; its printed text.
out = evalc(chk);
end
