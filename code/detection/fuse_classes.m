function varargout = fuse_classes(cmd, varargin)
%FUSE_CLASSES  Temporal fusion: the class of the current decision cycle from the
%   evidence of the last N cycles (temporal_evidence.m) and of the current cycle, a
%   multinomial logistic regression on the window's mean detector log-probabilities,
%   the persistence measurements and the current frame's log-probabilities.
%   Z = fuse_classes('windows', S, probs, N)
%       evidence of every frame of split S (fields run, pos, gain_ant, feats_raw,
%       feat_names, and idle: frames x 24, the record of the idle time before each frame,
%       idle_summary.m, when present; bch: frames x 9nr, every antenna's channel estimates,
%       branch_record.m, when present) from the frames of its own sub-run at positions
%       pos-N+1..pos (causal; the branch records over the last window_cues('branch_window')
%       positions); probs frames x C. Z is frames x (C + 11 + 52 + C):
%       temporal_evidence.m's columns, window_cues.m's (the branch cues, the step of the
%       received level, the idle time), then log(max(p, 1e-6)) of the frame's own
%       probabilities, so a threat that hits single frames (a sweeping jammer crossing the
%       band) is not averaged away by its clean neighbours. policy_monitor.m builds the
%       same row per cycle.
%   Z = fuse_classes('windows', S, probs, N, opt)  the same with window_cues('extra', ..., opt)'s
%       columns last (opt = fuse_classes('cues', FM), a fusion's own further columns)
%   X = fuse_classes('extra', S, N, opt)          those columns alone (opt.held: branch_ref.m over
%                                                each sub-run's cycles from its first)
%   opt = fuse_classes('cues', FM)                the further columns of fusion FM ([] for none)
%   FM = fuse_classes('fit', Z, y, C, lambda)     y class index per frame
%   [pc, k] = fuse_classes('apply', FM, Z)        pc frames x C, k predicted class. With FM.gcc
%       the gated coherence columns are appended to Z first (fitted on them); with FM.head the
%       lost-branch and level head reshares the four level-family classes (fuse_head.m)
%   names = fuse_classes('names', C, opt)         the names of the row's columns
%   g = fuse_classes('gcc', C, opt)               the columns of the gated coherence columns:
%       coh_contrast, los_contrast, los_k, coh_weak, k_contrast, ps_k_contrast, each times
%       1[gl_db >= 3 dB], the drop at which branch_coherence reads a branch's step
%   X = fuse_classes('gcc_x', Z, g)               those six columns of the rows Z
%   FM = fuse_classes('refit', FMd, Z, y, C, lambda, fold, E)  a fusion of FMd's form fitted on
%       the rows Z (compare_architectures.m): the linear fusion, on FMd's gated columns when it
%       has them, and with FMd.head a head of its columns stacked on the linear fusion's
%       out-of-fold probabilities over the folds of these rows (fuse_head.m), its trees'
%       stream fuse_head('seed', 'LBH', E) for rows without the folds E; without either,
%       fuse_classes('fit', Z, y, C, lambda)
%   The fusion is fitted on the validation split (the detector's outputs on its own
%   training frames are overconfident), N and lambda by cross-validation over the
%   validation sub-runs (select_fusion.m); the test split is never used.
switch cmd
    case 'windows', varargout{1} = windows(varargin{:});
    case 'extra',   varargout{1} = extra(varargin{:});
    case 'cues',    varargout{1} = cues(varargin{:});
    case 'fit',     varargout{1} = fit(varargin{:});
    case 'apply',   [varargout{1}, varargout{2}] = apply(varargin{:});
    case 'names',   varargout{1} = names(varargin{:});
    case 'gcc',     varargout{1} = gcc(varargin{:});
    case 'gcc_x',   varargout{1} = gcc_x(varargin{:});
    case 'refit',   varargout{1} = refit(varargin{:});
    otherwise, error('fuse_classes: unknown command %s', cmd);
end
end

function Z = windows(S, probs, N, opt)
if nargin < 4, opt = []; end
[ok, jf] = ismember(link_features('names'), S.feat_names);
if ~all(ok), error('fuse_classes: feats_raw lacks link features (rerun extract_spectrograms, prepare_data)'); end
n = numel(S.run);
nT = numel(temporal_evidence('names', size(probs, 2))); nW = numel(window_cues('names'));
Z = zeros(n, nT + nW);
I = nan(n, numel(idle_summary('names')));
if isfield(S, 'idle') && ~isempty(S.idle), I = double(S.idle); end
B = []; if isfield(S, 'bch') && ~isempty(S.bch), B = double(S.bch); end   % every antenna's channel estimates
NB = window_cues('branch_window');
[~, ~, rid] = unique(S.run(:));
byrun = accumarray(rid, (1:n)', [], @(v) {v});
for r = 1:numel(byrun)
    ix = byrun{r};
    [~, o] = sort(S.pos(ix)); ix = ix(o);
    for j = 1:numel(ix)
        w = ix(max(1, j - N + 1):j);
        Gw = permute(S.gain_ant(w, :), [3 2 1]); Fw = permute(S.feats_raw(w, jf), [3 2 1]);
        Bw = []; if ~isempty(B), Bw = permute(B(ix(max(1, j - NB + 1):j), :), [3 2 1]); end
        Z(ix(j), :) = [temporal_evidence(permute(probs(w, :), [3 2 1]), Gw, Fw), ...
            window_cues(Gw, Fw, permute(I(w, :), [3 2 1]), Bw)];
    end
end
Z = [Z, log(max(double(probs), 1e-6))];                   % the current frame's own evidence
if ~isempty(window_cues('extra_names', opt)), Z = [Z, extra(S, N, opt)]; end
end

function X = extra(S, N, opt)
% window_cues('extra', ..., opt) of every frame of split S over its own sub-run's last N frames.
[~, jf] = ismember(link_features('names'), S.feat_names);
n = numel(S.run);
X = zeros(n, numel(window_cues('extra_names', opt)));
if isempty(X), return; end
I = nan(n, numel(idle_summary('names')));
if isfield(S, 'idle') && ~isempty(S.idle), I = double(S.idle); end
[~, ~, rid] = unique(S.run(:));
byrun = accumarray(rid, (1:n)', [], @(v) {v});
held = isfield(opt, 'held') && opt.held;
for r = 1:numel(byrun)
    ix = byrun{r};
    [~, o] = sort(S.pos(ix)); ix = ix(o);
    H = []; if held, H = branch_ref('run', S.gain_ant(ix, :), isfield(opt, 'phi1') && opt.phi1); end   % the held reference over the run's cycles
    for j = 1:numel(ix)
        w = ix(max(1, j - N + 1):j);
        a = {}; if held, a = {H(j, :)}; end
        X(ix(j), :) = window_cues('extra', permute(S.gain_ant(w, :), [3 2 1]), permute(S.feats_raw(w, jf), [3 2 1]), ...
            permute(I(w, :), [3 2 1]), opt, a{:});
    end
end
end

function opt = cues(FM)
% The further columns fusion FM was fitted with (select_fusion.m), [] for none.
opt = [];
if ~isempty(FM) && isfield(FM, 'cues'), opt = FM.cues; end
end

function FM = fit(Z, y, C, lambda)
mu = mean(Z, 1); sd = std(Z, 0, 1); sd(sd < 1e-6) = 1;
X = [(Z - mu) ./ sd, ones(size(Z, 1), 1)];
Y = full(sparse(1:numel(y), y(:), 1, numel(y), C));
W = zeros(size(X, 2), C);
m = zeros(size(W)); v = zeros(size(W)); lr = 0.05; b1 = 0.9; b2 = 0.999;
for it = 1:1500                                           % Adam on the regularized cross-entropy
    Pz = softmax_rows(X * W);
    g = X' * (Pz - Y) / size(X, 1);
    g(1:end-1, :) = g(1:end-1, :) + lambda * W(1:end-1, :);
    m = b1 * m + (1 - b1) * g; v = b2 * v + (1 - b2) * g.^2;
    W = W - lr * (m / (1 - b1^it)) ./ (sqrt(v / (1 - b2^it)) + 1e-8);
end
FM = struct('W', W, 'mu', mu, 'sd', sd, 'C', C, 'lambda', lambda);
end

function [pc, k] = apply(FM, Z)
if isfield(FM, 'gcc') && ~isempty(FM.gcc), Z = [Z, gcc_x(Z, FM.gcc)]; end
assert(size(Z, 2) == numel(FM.mu), 'fuse_classes:columns', 'fuse_classes: %d evidence columns, the fusion was fitted on %d (rerun select_fusion)', ...
    size(Z, 2), numel(FM.mu));
X = [(Z - FM.mu) ./ FM.sd, ones(size(Z, 1), 1)];
pc = softmax_rows(X * FM.W);
if isfield(FM, 'head') && ~isempty(FM.head), pc = fuse_head('apply', FM.head, pc, Z); end
[~, k] = max(pc, [], 2);
end

function n = names(C, opt)
% The row's columns: temporal_evidence.m's, window_cues.m's, the frame's own log-probabilities
% (now_c), the further columns of opt.
if nargin < 2, opt = []; end
n = [temporal_evidence('names', C), window_cues('names'), arrayfun(@(c) sprintf('now_%d', c), 1:C, 'UniformOutput', false), ...
    window_cues('extra_names', opt)];
end

function g = gcc(C, opt)
n = names(C, opt);
at = @(s) find(strcmp(n, s));
c = cellfun(at, {'coh_contrast', 'los_contrast', 'los_k', 'coh_weak', 'k_contrast', 'ps_k_contrast'}, 'UniformOutput', false);
assert(all(cellfun(@isscalar, c)) && isscalar(at('gl_db')), 'fuse_classes:gcc', ...
    'the gated coherence columns need the coherence columns and the glr and post further columns');
g = struct('gate', at('gl_db'), 'cols', [c{:}]);
end

function X = gcc_x(Z, g)
X = double(Z(:, g.gate) >= 3) .* Z(:, g.cols);
end

function FM = refit(FMd, Z, y, C, lambda, fold, E)
g = []; if isfield(FMd, 'gcc'), g = FMd.gcc; end
FM = fit_g(Z, y, C, lambda, g);
if ~isfield(FMd, 'head') || isempty(FMd.head), return; end
po = nan(size(Z, 1), C);
for j = unique(fold(:))'
    m = fold(:) == j;
    po(m, :) = apply(fit_g(Z(~m, :), y(~m), C, lambda, g), Z(m, :));
end
FM.head = fuse_head('fit', po, Z, y, FMd.head.L, FMd.head.cols, fuse_head('seed', 'LBH', E));
end

function FM = fit_g(Z, y, C, lambda, g)
% The linear fusion, on the gated coherence columns g when given.
if isempty(g), FM = fit(Z, y, C, lambda); return; end
FM = fit([Z, gcc_x(Z, g)], y, C, lambda);
FM.gcc = g;
end

function P = softmax_rows(A)
A = A - max(A, [], 2);
P = exp(A); P = P ./ sum(P, 2);
end
