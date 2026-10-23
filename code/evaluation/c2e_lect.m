function c2e_lect(step)
%C2E_LECT  The revised proposal's KPIs for profile 1 from an isolated copy of its C2e
%   (protocol: docs/c2e_lect_protocol.md on branch lect-kpi; the copy is made by
%   tools/c2e_lect_isolated.sh there). Runs in that copy's root, never in profile 1's tree.
%   c2e_lect('eval')  evaluate_policies.m of this branch (profile 1's code with rule_core and
%                     blind_core appended and the per-episode PER, delivered payload and
%                     recovery-from-detection fields) on profile 1's own C2e inputs
%   c2e_lect('gate')  c2e_lect_gate.m against profile 1's own results (ref/): every number of
%                     profile 1's C2e must come out unchanged; a mismatch stops here
%   c2e_lect('read')  only after a pass, once: c2e_lect_read.m (lect_kpis.m, the KPI
%                     summary's lines, the three link states of profile 1's KPI 1 reading and
%                     the false alarms on the clean link) into results/c2e_lect.{txt,mat}
%   c2e_lect or c2e_lect('all')  the three in turn
%   The evaluation runs on MATLAB's default number of computational threads, as profile 1's
%   chain MATLAB (started without -singleCompThread); results/c2e_lect_threads.txt records it.
if nargin < 1, step = 'all'; end
switch step
    case 'all'
        c2e_lect('eval'); c2e_lect('gate'); c2e_lect('read');
    case 'eval'
        root = guard();
        if isfile('results/policy_evaluation.mat') || isfile('results/c2e_lect_gate.txt')
            error('c2e_lect:rerun', ['c2e_lect: %s already holds an evaluation; a new run starts from a new copy ' ...
                '(tools/c2e_lect_isolated.sh prepare)'], root);
        end
        n0 = maxNumCompThreads;
        try maxNumCompThreads('automatic'); catch, end   % profile 1's chain MATLAB runs without -singleCompThread
        n1 = maxNumCompThreads;
        fid = fopen('results/c2e_lect_threads.txt', 'w');
        fprintf(fid, 'computational threads: %d at start, %d for evaluate_policies (MATLAB''s default)\n', n0, n1);
        fclose(fid);
        eval_script('evaluate_policies');
    case 'gate'
        guard();
        P = load('ref/p1_policy_evaluation.mat'); S = load('results/policy_evaluation.mat');
        G = c2e_lect_gate(P, S, read_lines('ref/p1_policy_evaluation.txt'), read_lines('results/policy_evaluation.txt'));
        d = dir('results/policy_evaluation.mat'); G.mat_stamp = [d.datenum, d.bytes];
        G.det_id = ''; if isfield(P.KP, 'det_id'), G.det_id = P.KP.det_id; end
        G.policy_stamp = ''; if isfield(P.KP, 'policy_stamp'), G.policy_stamp = P.KP.policy_stamp; end
        fid = fopen('results/c2e_lect_gate.txt', 'w'); fprintf(fid, '%s\n', G.lines{:}); fclose(fid);
        save('results/c2e_lect_gate.mat', 'G');
        fprintf('%s\n', G.lines{:});
        if ~G.pass
            error('c2e_lect:gate', 'c2e_lect: the isolated run differs from profile 1''s C2e (results/c2e_lect_gate.txt); no reading');
        end
    case 'read'
        guard();
        if ~isfile('results/c2e_lect_gate.mat'), error('c2e_lect:nogate', 'c2e_lect: no gate result; run the gate first'); end
        Gs = load('results/c2e_lect_gate.mat'); G = Gs.G;
        d = dir('results/policy_evaluation.mat');
        if ~G.pass || ~isequal(G.mat_stamp, [d.datenum, d.bytes])
            error('c2e_lect:nogate', 'c2e_lect: the gate did not pass on this results/policy_evaluation.mat; no reading');
        end
        if isfile('results/c2e_lect.txt'), error('c2e_lect:read', 'c2e_lect: read once; results/c2e_lect.txt exists'); end
        c2e_lect_read(G);
    otherwise
        error('c2e_lect:step', 'c2e_lect: unknown step %s', step);
end
end

function root = guard()
% The isolated copy only: its marker file, its own code on the path, never a live tree.
root = pwd;
if ~isfile('C2E_LECT_ISOLATED')
    error('c2e_lect:isolation', 'c2e_lect: %s holds no C2E_LECT_ISOLATED marker (tools/c2e_lect_isolated.sh prepare)', root);
end
w = lower(strrep(root, '/', '\'));
live = {'uav-gcs-v7', 'uav-gcs-v7-p3', 'uav-gcs-v7-p2', 'uav-gcs-v7-deploy', 'uav-gcs-logs'};
[~, leaf] = fileparts(w);
if ismember(leaf, live) || contains(w, '\d91q')
    error('c2e_lect:isolation', 'c2e_lect: %s is a live tree; the reading runs in its own copy', root);
end
if ~strcmpi(strrep(setup_paths(), '/', '\'), strrep(root, '/', '\')) || ~startsWith(lower(which('evaluate_policies')), w)
    error('c2e_lect:isolation', 'c2e_lect: the code on the path is not this copy''s (%s)', which('evaluate_policies'));
end
if ~isfolder('results'), mkdir('results'); end
end

function eval_script(name)
% A script in a workspace of its own.
run(name);
end

function L = read_lines(f)
L = splitlines(string(fileread(f)));
if ~isempty(L) && L(end) == "", L = L(1:end-1); end
L = cellstr(L);
end
