function varargout = core_cnn_eval(cmd, varargin)
%CORE_CNN_EVAL  The three-state reading (train_core_cnn.m, docs/core_cnn_protocol.md).
%   [L, rank] = core_cnn_eval('logp', P, run, pos, N)
%       mean log-probability log(max(p, 1e-6)) of every class over the last N frames of the
%       frame's own sub-run, in position order (causal; shorter at a sub-run's start, never
%       across sub-runs): the first columns of temporal_evidence.m. P frames x C; rank the
%       frame's place in its sub-run (its window is full from rank N on).
%   M = core_cnn_eval('metrics', y, yp, nS)
%       y true state 1..nS, yp the state read, 0 for another class (an error, never a hit).
%       M.cm nS x (nS + 1) frames (last column 'other'); M.n frames per state; M.recall,
%       M.precision (over the nS states' columns), M.f1 per state; M.macro_f1 their mean over
%       the states with frames (three_state_view.m's figures); M.fa the share of state-1
%       (clean) frames read as anything else; M.fa_jam its part read as a jamming state.
%   [N, T] = core_cnn_eval('choose', P, y, run, pos, NS, K, seed)
%       the window: macro-F1 of the argmax of 'logp' for every N of NS, on K folds of whole
%       sub-runs (RandStream mt19937ar, seed, as select_fusion.m); the shortest N within one
%       standard error (over the folds) of the best. T.cv, T.fold (numel(NS) x K), T.se, T.best.
%   B = core_cnn_eval('boot', y, YP, run, eb, nS, nB, seed)
%       95% percentile intervals over nB resamples of whole sub-runs. YP frames x R, the states
%       read by R readers; eb the frame's Eb/N0 bin. B.macro_f1, B.fa, B.fa_jam R x 2;
%       B.recall R x nS x 2; B.ebno the bins, B.macro_f1_ebno R x bins x 2; B.diff (R x 2)
%       of the paired difference of each reader's macro-F1 minus reader 1's.
%   s = core_cnn_eval('verdict', p, ci, thr, dir)
%       'met (committed)' when the interval ci clears thr, 'met (not committed)' when only the
%       point p does, 'not met' otherwise; dir '>=' or '<='.
%   D = core_cnn_eval('delay', y, yp, run, pos, states)
%       per sub-run of the given states: cycles from its first frame to its first frame read
%       as its own state (NaN: never). D.state, D.cycles per sub-run; D.median, D.p90 over
%       the sub-runs read right and D.never, the share never read right, per state.
switch cmd
    case 'logp',    [varargout{1}, varargout{2}] = logp(varargin{:});
    case 'metrics', varargout{1} = metrics(varargin{:});
    case 'choose',  [varargout{1}, varargout{2}] = choose(varargin{:});
    case 'boot',    varargout{1} = boot(varargin{:});
    case 'verdict', varargout{1} = verdict(varargin{:});
    case 'delay',   varargout{1} = delay(varargin{:});
    otherwise, error('core_cnn_eval:cmd', 'core_cnn_eval: unknown command %s', cmd);
end
end

function [L, rank] = logp(P, run, pos, N)
n = size(P, 1);
lp = log(max(double(P), 1e-6));
L = zeros(size(lp)); rank = zeros(n, 1);
for ix = by_run(run, pos)
    ix = ix{1};
    c = cumsum(lp(ix, :), 1);
    k = (1:numel(ix))';
    lo = max(k - N, 0);
    s = c; s(lo > 0, :) = c(lo > 0, :) - c(lo(lo > 0), :);
    L(ix, :) = s ./ (k - lo);
    rank(ix) = k;
end
end

function M = metrics(y, yp, nS)
y = double(y(:)); yp = double(yp(:));
k = yp; k(k == 0) = nS + 1;
cm = accumarray([y k], 1, [nS nS + 1]);
n = sum(cm, 2)';
tp = diag(cm(:, 1:nS))';
cs = sum(cm(:, 1:nS), 1);
M.cm = cm; M.n = n;
M.recall = tp ./ n;
M.precision = tp ./ cs;
M.f1 = 2 * tp ./ (n + cs);
M.macro_f1 = mean(M.f1(n > 0));
M.fa = (n(1) - tp(1)) / n(1);
M.fa_jam = sum(cm(1, 2:nS)) / n(1);
end

function [N, T] = choose(P, y, run, pos, NS, K, seed)
y = double(y(:)); run = run(:);
runs = unique(run);
rs = RandStream('mt19937ar', 'Seed', seed);
fold_of_run = mod(randperm(rs, numel(runs)), K) + 1;
[~, ir] = ismember(run, runs);
fold = reshape(fold_of_run(ir), [], 1);
nS = size(P, 2);
cv = zeros(1, numel(NS)); ff = zeros(numel(NS), K);
for a = 1:numel(NS)
    [~, yh] = max(logp(P, run, pos, NS(a)), [], 2);
    cv(a) = metrics(y, yh, nS).macro_f1;
    for k = 1:K
        ff(a, k) = metrics(y(fold == k), yh(fold == k), nS).macro_f1;
    end
end
[mx, a1] = max(cv);
se = std(ff(a1, :)) / sqrt(K);
a = find(cv >= mx - se, 1);
N = NS(a);
T = struct('NS', NS, 'cv', cv, 'fold', ff, 'se', se, 'best', NS(a1), 'pick', N);
end

function B = boot(y, YP, run, eb, nS, nB, seed)
y = double(y(:)); eb = eb(:); R = size(YP, 2);
[~, ~, g] = unique(run(:));
members = accumarray(g, (1:numel(y))', [], @(v) {v});
nU = numel(members);
bins = unique(eb(~isnan(eb)))';
mf = nan(nB, R); fa = mf; fj = mf; rc = nan(nB, R, nS); me = nan(nB, R, numel(bins));
rs = RandStream('mt19937ar', 'Seed', seed);
for b = 1:nB
    ix = vertcat(members{randi(rs, nU, nU, 1)});
    ex = eb(ix);
    for r = 1:R
        M = metrics(y(ix), YP(ix, r), nS);
        mf(b, r) = M.macro_f1; fa(b, r) = M.fa; fj(b, r) = M.fa_jam; rc(b, r, :) = M.recall;
        for e = 1:numel(bins)
            k = ix(ex == bins(e));
            if ~isempty(k), me(b, r, e) = metrics(y(k), YP(k, r), nS).macro_f1; end
        end
    end
end
B.n_boot = nB; B.ebno = bins;
B.macro_f1 = ci(mf); B.fa = ci(fa); B.fa_jam = ci(fj);
B.recall = zeros(R, nS, 2); B.macro_f1_ebno = zeros(R, numel(bins), 2);
for s = 1:nS, B.recall(:, s, :) = permute(ci(rc(:, :, s)), [1 3 2]); end
for e = 1:numel(bins), B.macro_f1_ebno(:, e, :) = permute(ci(me(:, :, e)), [1 3 2]); end
B.diff = ci(mf - mf(:, 1));
end

function c = ci(X)
% 2.5 and 97.5 percentiles of every column (resamples in rows), NaN ignored: columns x 2.
c = nan(size(X, 2), 2);
for j = 1:size(X, 2)
    q = sort(X(~isnan(X(:, j)), j));
    if isempty(q), continue; end
    m = numel(q);
    c(j, :) = [q(max(1, round(0.025 * m))), q(min(m, max(1, round(0.975 * m))))];
end
end

function s = verdict(p, c, thr, dir)
if isnan(p), s = 'no frames'; return; end
switch dir
    case '>=', met = p >= thr; com = c(1) >= thr;
    case '<=', met = p <= thr; com = c(2) <= thr;
    otherwise, error('core_cnn_eval:dir', 'core_cnn_eval: direction %s', dir);
end
if met && com
    s = 'met (committed)';
elseif met
    s = 'met (not committed)';
else
    s = 'not met';
end
end

function D = delay(y, yp, run, pos, states)
y = double(y(:)); yp = double(yp(:));
st = []; cy = [];
for ix = by_run(run, pos)
    ix = ix{1};
    s = y(ix(1));
    if ~ismember(s, states), continue; end
    j = find(yp(ix) == s, 1);
    st(end + 1) = s; %#ok<AGROW>
    if isempty(j), cy(end + 1) = NaN; else, cy(end + 1) = j - 1; end %#ok<AGROW>
end
D = struct('state', st, 'cycles', cy, 'states', states, 'median', nan(1, numel(states)), ...
    'p90', nan(1, numel(states)), 'never', nan(1, numel(states)), 'n', zeros(1, numel(states)));
for k = 1:numel(states)
    c = cy(st == states(k));
    D.n(k) = numel(c);
    if isempty(c), continue; end
    D.never(k) = mean(isnan(c));
    q = sort(c(~isnan(c)));
    if isempty(q), continue; end
    D.median(k) = median(q);
    D.p90(k) = q(ceil(0.9 * numel(q)));
end
end

function G = by_run(run, pos)
% The frame indices of every sub-run in position order (a 1 x runs cell).
[~, ~, rid] = unique(run(:));
G = accumarray(rid, (1:numel(rid))', [], @(v) {v})';
for r = 1:numel(G)
    [~, o] = sort(pos(G{r})); G{r} = G{r}(o);
end
end
