function varargout = ood_cue(cmd, varargin)
%OOD_CUE  The physics row of a decision window and its novelty scores (D111): the fusion's
%   non-probability columns, the 11 persistence measurements of temporal_evidence.m and the 52
%   window_cues.m columns (branch K and contrast, coherence and line-of-sight share, the step
%   of the received level, idle-time occupancy and burst timing), as the monitor builds them
%   every cycle (policy_monitor.m); no class probability, label or truth field.
%   n = ood_cue('names', C)        the row's 63 column names (C classes)
%   j = ood_cue('cols', C)         its columns in the rows of fuse_classes('windows', S, P, N)
%   X = ood_cue('rows', Z, C)      the rows of fuse_classes('windows', S, P, N) (P any C columns)
%   X = ood_cue('rows', Z, C, Zs)  with the level-step columns of Zs, the same split's rows over
%                                  the step window (step_n)
%   X = ood_cue('step', X, Ws)     the level-step columns of rows X from Ws (52 window_cues
%                                  columns over the step window)
%   X = ood_cue('split', S, fn, C, N)  the rows of every frame of a split S of data/splits*.mat
%                                  (feature names fn, C classes, fusion window N, the step window
%                                  of step_n), without its probabilities
%   n = ood_cue('step_n', N)       the step window: TW = 10 frames, the label rule's link-feature
%                                  window (run_dataset_sweep.m, threat_active.m), when the fusion
%                                  window N is shorter, so every labelled path-loss frame's step
%                                  is inside it (D111 point 4); 0 otherwise
%   f = ood_cue('fill', run, pos)  every frame's place in its own sub-run, 1 for the first: its
%                                  window is full from fill >= the window's length on
%   S = ood_cue('scale_fit', X)    median and interquartile range of every column (fit windows)
%   Xs = ood_cue('scale', S, X)    (X - median) / IQR clipped at +-10, non-finite values 0
%   M = ood_cue('maha_fit', Xs, y) class means and one tied covariance shrunk by 10% toward a
%                                  scaled identity (fit_ood_model.m tied_gauss; Lee et al. 2018,
%                                  eqs. 1-2), y the class of every row
%   s = ood_cue('maha', M, Xs)     Lee et al.'s confidence: minus the smallest class distance
%   M = ood_cue('if_fit', Xs, seed) isolation forest on the rows (Liu, Ting & Zhou 2008), the
%                                  sub-sample of fit_ood_model.m, its trees packed
%                                  (iforest_pack.m); the global stream is restored
%   s = ood_cue('if', M, Xs)       minus its anomaly score (iforest_score.m)
%   Rows are windows, scores rows x 1; lower = more novel.
TW = 10;                                                    % run_dataset_sweep.m TW
switch cmd
    case 'names'
        te = temporal_evidence('names', varargin{1});
        varargout{1} = [te(varargin{1} + 1:end), window_cues('names')];
    case 'cols'
        varargout{1} = varargin{1} + (1:n_cols());
    case 'rows'
        [Z, C] = varargin{1:2};
        X = Z(:, C + (1:n_cols()));
        if nargin >= 4 && ~isempty(varargin{3})
            X = step_cols(X, varargin{3}(:, C + n_te() + (1:numel(window_cues('names')))));
        end
        varargout{1} = X;
    case 'step'
        varargout{1} = step_cols(varargin{:});
    case 'split'
        [S, fn, C, N] = varargin{:};
        S.feat_names = fn;
        P = ones(numel(S.run), C) / C;                      % the row reads no probability
        Zs = []; if N < TW, Zs = fuse_classes('windows', S, P, TW); end
        varargout{1} = ood_cue('rows', fuse_classes('windows', S, P, N), C, Zs);
    case 'step_n'
        varargout{1} = TW * (varargin{1} < TW);
    case 'fill'
        varargout{1} = fill_pos(varargin{:});
    case 'scale_fit'
        X = double(varargin{1});
        q = prctile(X, [25 50 75], 1);
        iq = q(3, :) - q(1, :); iq(~(iq > 1e-9)) = 1;
        varargout{1} = struct('med', q(2, :), 'iqr', iq, 'clip', 10);
    case 'scale'
        [S, X] = varargin{:};
        Xs = (double(X) - S.med) ./ S.iqr;
        Xs(~isfinite(Xs)) = 0;
        varargout{1} = min(max(Xs, -S.clip), S.clip);
    case 'maha_fit'
        varargout{1} = maha_fit(varargin{:});
    case 'maha'
        [M, X] = varargin{:};
        d = inf(size(X, 1), 1);
        for c = 1:size(M.mu, 1)
            D = X - M.mu(c, :);
            d = min(d, sum((D * M.P) .* D, 2));
        end
        varargout{1} = -d;
    case 'if_fit'
        [X, seed] = varargin{:};
        g = rng; back = onCleanup(@() rng(g));
        rng(seed, 'twister');
        F = iforest(X, 'NumLearners', 100, 'NumObservationsPerLearner', min(8192, size(X, 1)));
        varargout{1} = struct('pack', iforest_pack(F));
    case 'if'
        [M, X] = varargin{:};
        varargout{1} = -iforest_score(M.pack, X')';
    otherwise
        error('ood_cue:cmd', 'ood_cue: unknown command %s', cmd);
end
end

function n = n_te()
% temporal_evidence.m's non-probability columns.
n = numel(temporal_evidence('names', 1)) - 1;
end

function n = n_cols()
n = n_te() + numel(window_cues('names'));
end

function X = step_cols(X, Ws)
% The level-step columns of the cue rows X from the window_cues columns Ws.
j = find(ismember(window_cues('names'), {'stp_t', 'stp_db', 'stp_age', 'stp_t_mon', 'stp_db_mon'}));
X(:, n_te() + j) = Ws(:, j);
end

function f = fill_pos(run, pos)
% Place of every frame in its own sub-run, in position order.
n = numel(run); f = zeros(n, 1);
if n == 0, return; end
[~, ~, rid] = unique(run(:));
byrun = accumarray(rid, (1:n)', [], @(v) {v});
for r = 1:numel(byrun)
    ix = byrun{r};
    [~, o] = sort(pos(ix)); ix = ix(o);
    f(ix) = (1:numel(ix))';
end
end

function M = maha_fit(X, y)
% Class means and the inverse tied covariance, 10% shrinkage (fit_ood_model.m tied_gauss).
X = double(X);
[~, ~, yi] = unique(y(:));
d = size(X, 2); nC = max(yi);
mu = zeros(nC, d); R = zeros(size(X));
for c = 1:nC
    m = yi == c;
    mu(c, :) = mean(X(m, :), 1);
    R(m, :) = X(m, :) - mu(c, :);
end
Sig = (R' * R) / size(X, 1);
Sig = 0.9 * Sig + 0.1 * trace(Sig) / d * eye(d);
M = struct('mu', mu, 'P', inv(Sig));
end
