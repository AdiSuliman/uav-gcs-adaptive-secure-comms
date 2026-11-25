function tests = test_adopt_hop_options
%TEST_ADOPT_HOP_OPTIONS  The dqn_hop adoption in adopt_options.m: the hop layer reaches the deployed row
%   only, the run_cache key gains nothing when off, and opt.monitor reaches policy_decide.m through
%   decision_settings.m. Temporary folders only. Run from the repository root:
%   results = runtests('code/tests/test_adopt_hop_options.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.cwd = pwd;
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp); cd(tc.TestData.tmp);
end

function teardownOnce(tc)
cd(tc.TestData.cwd);
try, rmdir(tc.TestData.tmp, 's'); catch, end %#ok<NOCOM,CTCH>
end

%% ---------- adopt_options.m ----------
function test_hop_row_only(tc)
A = adopt_options(struct('adopt', struct('rule_fix', 'keep+st+rate', 'dqn_hop', 'rule')));
verifyEqual(tc, A.names, {'rule_fix', 'dqn_hop'});
verifyError(tc, @() adopt_options('opt', A, 'dqn_g1', struct()), 'adopt_options:row');   % the deployed row first
A = adopt_options('deployed', A, 'dqn_g1');
o = adopt_options('opt', A, 'dqn_g1', struct());
verifyEqual(tc, o, struct('monitor', struct('dqn_hop', 'rule')));
o = adopt_options('opt', A, 'dqn_g1', struct('monitor', struct('lb_complete', true)));
verifyEqual(tc, o.monitor, struct('lb_complete', true, 'dqn_hop', 'rule'));
for n = {'dqn_g2', 'dqn_esc', 'dqn_g1_relm', 'dqn_g1_norelm', 'none', 'oracle', 'table', 'fixed'}
    verifyEqual(tc, adopt_options('opt', A, n{1}, struct('k', 1)), struct('k', 1), n{1});   % not the deployed row
end
o = adopt_options('opt', A, 'rule_esc', struct());
verifyEqual(tc, o.monitor, struct('rule_fix', 'keep+st+rate'));    % the rule rows: the rule fix alone
verifyTrue(tc, contains(adopt_options('note', A), 'dqn_g1') && contains(adopt_options('note', A), 'dqn_hop=rule') ...
    && contains(adopt_options('note', A), 'keep+st+rate'));
end

function test_dqn_call_and_key(tc)
A = adopt_options(struct('adopt', struct('rule_fix', 'keep+st+rate', 'dqn_hop', 'rule')));
o = adopt_options('dqn', A, struct('monitor', struct('lb_complete', true)));
verifyEqual(tc, o.monitor, struct('lb_complete', true, 'dqn_hop', 'rule'));
verifyEqual(tc, adopt_options('key', A), {'dqn_hop=rule'});
verifyTrue(tc, contains(adopt_options('note', A, 'dqn'), 'hybrid'));
R = adopt_options(struct('adopt', struct('rule_fix', 'keep+st+rate')));          % the rule fix alone
verifyEqual(tc, adopt_options('dqn', R, struct('x', 1)), struct('x', 1));
verifyEqual(tc, adopt_options('key', R), {});
verifyEqual(tc, adopt_options('note', R, 'dqn'), '');
for c = {[], struct(), struct('adopt', struct('dqn_hop', '')), struct('adopt', struct('dqn_hop', ""))}
    Z = adopt_options(c{1});
    verifyFalse(tc, Z.on);
    verifyEqual(tc, adopt_options('dqn', Z, struct('monitor', struct('lb_complete', true))), ...
        struct('monitor', struct('lb_complete', true)));
    verifyEqual(tc, adopt_options('key', Z), {});
    verifyEqual(tc, adopt_options('opt', Z, 'dqn_g1', struct()), struct());
end
verifyError(tc, @() adopt_options(struct('adopt', struct('dqn_hop', struct('on', true)))), 'adopt_options:value');
end

function test_the_layer_reads_the_option(tc)
% opt.monitor reaches PP through decision_settings.m, and policy_decide.m reads PP.dqn_hop.
A = adopt_options('deployed', adopt_options(struct('adopt', struct('dqn_hop', 'rule'))), 'dqn_g1');
o = adopt_options('opt', A, 'dqn_g1', struct());
PP = decision_settings(struct('confirm', [2 3]), o.monitor);
verifyEqual(tc, PP.dqn_hop, 'rule');
pd = strrep(fileread(which('policy_decide')), char(13), '');
verifyNotEmpty(tc, strfind(pd, 'if isfield(opt, ''monitor''), PP = decision_settings(PP, opt.monitor); end'));
verifyNotEmpty(tc, strfind(pd, 'dp = dqn_fix(''parse'', ''dqn_hop'', PP.dqn_hop)'));
w = strrep(fileread(which('weak19_reading')), char(13), '');   % the test read set it the same way
verifyNotEmpty(tc, strfind(w, 'opt1 = opt0; for f = fieldnames(Sa)'', opt1.monitor.(f{1}) = Sa.(f{1}); end'));
end
