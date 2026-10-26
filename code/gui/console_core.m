function varargout = console_core(cmd, varargin)
%CONSOLE_CORE  The proposal's link-state view and the core policy for the operator console
%   (demo_gui.m, episode_cycle.m), apart from the figure so that a headless run exercises the
%   same code.
%   M = console_core('load')
%       the three-state CNN of stage B3c (data/core_cnn_model.mat): net, N (window, cycles),
%       names, groups. [] when the model is not in the folder or is a reduced chain check
%       (marked smoke), so the console shows no state it cannot stand behind.
%   P = console_core('window', P, N)
%       P frames x states, class probabilities of consecutive frames of one link: the
%       probabilities of the window, the normalised geometric mean of the last N rows (the
%       mean log-probability core_cnn_eval 'logp' reads, as the stage's official reading).
%   S = console_core('read', M, P)
%       the link state read from P (frames x states, the model's probabilities of consecutive
%       frames of one link): S.frame (last frame's), S.win (the window's), S.idx and S.name
%       (the state read), S.n frames used, S.N the window.
%   S = console_core('state', M, X)
%       the same for images X (128 x 128 x 1 x n, consecutive frames of one link)
%   k = console_core('truth', M, threat)
%       the state a threat belongs to (0 when it is none of the model's states).
%   opt = console_core('policy_opt')
%       the policy_decide.m option that selects the core action set (rule_core).
%   lines = console_core('kpi_lines', folder)
%       the lecturer's KPI lines written by the pipeline, read only: the section of
%       results/core_cnn.txt and the lecturer lines of results/kpi_summary.txt (folder
%       default 'results'); {} when neither is present.
switch cmd
    case 'load',        varargout{1} = load_model();
    case 'window',      varargout{1} = window_probs(varargin{:});
    case 'read',        varargout{1} = read(varargin{:});
    case 'state',       varargout{1} = read(varargin{1}, spec_scores(varargin{1}.net, varargin{2}));
    case 'truth',       varargout{1} = truth(varargin{:});
    case 'policy_opt',  varargout{1} = struct('core', true);
    case 'kpi_lines',   varargout{1} = kpi_lines(varargin{:});
    otherwise, error('console_core:cmd', 'console_core: unknown command %s', cmd);
end
end

function M = load_model()
M = [];
f = 'data/core_cnn_model.mat';
if ~isfile(f), return; end
v = who('-file', f);
if all(ismember({'net', 'N', 'names', 'groups'}, v))
    S = load(f, 'net', 'N', 'names', 'groups');
    sm = false;
    if ismember('smoke', v), sm = load(f, 'smoke').smoke; end
    if isequal(sm, true), return; end
    M = struct('net', S.net, 'N', S.N, 'names', {S.names}, 'groups', {S.groups});
end
end

function W = window_probs(P, N)
n = size(P, 1);
L = core_cnn_eval('logp', P, ones(n, 1), (1:n)', N);
l = L(end, :);
W = exp(l - max(l));
W = W / sum(W);
end

function S = read(M, P)
P = P(max(1, end - M.N + 1):end, :);
W = window_probs(P, M.N);
[~, k] = max(W);
S = struct('frame', P(end, :), 'win', W, 'idx', k, 'name', M.names{k}, 'n', size(P, 1), 'N', M.N);
end

function k = truth(M, threat)
k = find(strcmp(M.groups, threat), 1);
if isempty(k), k = 0; end
end

function L = kpi_lines(folder)
if nargin < 1 || isempty(folder), folder = 'results'; end
L = {};
f = fullfile(folder, 'core_cnn.txt');
if isfile(f)
    t = splitlines(fileread(f));
    i = find(startsWith(t, '--- The lecturer''s KPIs'), 1);
    if ~isempty(i)
        j = i;
        while j < numel(t) && ~isempty(strtrim(t{j + 1})), j = j + 1; end
        L = [L; t(i:j)];
    end
end
f = fullfile(folder, 'kpi_summary.txt');
if isfile(f)
    t = splitlines(fileread(f));
    L = [L; strtrim(t(contains(t, 'lecturer')))];
end
L = L(:);
end
