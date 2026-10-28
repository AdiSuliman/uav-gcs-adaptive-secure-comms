function tests = test_v0_guard
%TEST_V0_GUARD  The V0 diagnostic refuses every split but validation, test inputs and outputs
%   outside results/ (synthetic data, no pools read). Run from the repository root:
%   results = runtests('code/tests/test_v0_guard.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
end

function test_split_refused(tc)
for s = [1 3 4 5]
    tc.verifyError(@() v0_guard('split', s), 'v0_guard:test_split');
end
tc.verifyError(@() v0_guard('split', [2 3]), 'v0_guard:test_split');
v0_guard('split', 2);
end

function test_strip_and_check(tc)
PP = synthetic_pools();
tc.verifyError(@() v0_guard('check', PP), 'v0_guard:test_split');
P2 = v0_guard('strip', PP);
tc.verifyTrue(all(cellfun(@isempty, P2.pools(:, :, :, 3:5)), 'all'));
tc.verifyFalse(any(cellfun(@isempty, P2.pools(:, :, :, 1:2)), 'all'));
v0_guard('check', P2);
end

function test_rollout_refuses_first(tc)
% The trace rollout stops before it touches the environment: a test split, or validation on
% pools that still hold a test split.
PP = synthetic_pools();
spec = struct('scn', 1, 's', 1, 'r', 1, 'onset', 3, 'follow', false, 'fdelay', 2, 'unk', false, 'T', 30);
for s = [3 4 5]
    tc.verifyError(@() v0_trace_rollout('dqn', v0_guard('strip', PP), struct(), spec, s, [], struct(), 1), ...
        'v0_guard:test_split');
end
tc.verifyError(@() v0_trace_rollout('dqn', PP, struct(), spec, 2, [], struct(), 1), 'v0_guard:test_split');
end

function test_inputs_and_outputs(tc)
r = tc.TestData.root;
for f = {'C:\x\data\clean_test_pools.mat', 'C:\x\results\policy_evaluation.mat', 'C:\x\results\detector_predictions_fresh3.mat'}
    tc.verifyError(@() v0_guard('input', f{1}), 'v0_guard:input');
end
v0_guard('input', 'C:\x\data\clean_val_pools.mat');
v0_guard('input', 'C:\x\data\policy_pools.mat');
v0_guard('input', 'C:\x\p1_first\data\trained_dqn.mat');
tc.verifyError(@() v0_guard('out', fullfile(r, 'data'), r), 'v0_guard:out');
tc.verifyError(@() v0_guard('out', fullfile(r, 'results', '..', 'data'), r), 'v0_guard:out');
tc.verifyError(@() v0_guard('out', fullfile(r, 'results_x'), r), 'v0_guard:out');
d = v0_guard('out', fullfile(r, 'results', 'v0'), r);
tc.verifyTrue(startsWith(lower(d), lower(fullfile(r, 'results'))));
end

function test_diag_refuses_before_loading(tc)
% v0_diag stops on a test input or an output outside results/ before it opens any file.
r = tc.TestData.root;
tc.verifyError(@() v0_diag('C:\nowhere\clean_test_pools.mat', 'C:\nowhere\clean_val_pools.mat', ...
    'C:\nowhere\trained_dqn.mat', 'C:\nowhere\MANIFEST.sha256'), 'v0_guard:input');
tc.verifyError(@() v0_diag('C:\nowhere\policy_pools.mat', 'C:\nowhere\clean_val_pools.mat', ...
    'C:\nowhere\trained_dqn.mat', 'C:\nowhere\MANIFEST.sha256', fullfile(r, 'data')), 'v0_guard:out');
% Allowed inputs pass the guard and stop only at the missing file.
tc.verifyError(@() v0_diag('C:\nowhere\policy_pools.mat', 'C:\nowhere\clean_val_pools.mat', ...
    'C:\nowhere\trained_dqn.mat', 'C:\nowhere\MANIFEST.sha256'), 'v0_diag:input');
end

function test_v0_files_parse(tc)
for f = {'v0_diag.m', 'v0_guard.m', 'v0_trace_rollout.m'}
    t = mtree(fileread(which(f{1})));
    tc.verifyNotEqual(t.root.kind, 'ERR', f{1});
end
end

function PP = synthetic_pools()
PP.pools = repmat({struct('ber', 1)}, 2, 1, 1, 5);
end
