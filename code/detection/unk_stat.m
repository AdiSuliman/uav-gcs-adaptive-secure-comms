function varargout = unk_stat(cmd, varargin)
%UNK_STAT  D111's unknown-threat statistic U: the frozen per-frame score s0 (P.maha, its mean
%   over the last ood.win cycles) and the novelty of the window's physics row (ood_cue.m),
%   combined by their marginal conformal p-values (Bates, Candes, Lei, Romano & Sesia 2023,
%   Sec. 2): p(w) = (1 + #{calibration windows with s <= s(w)}) / (n + 1), lower = more novel,
%   U = min(p0, p_cue). min(p) alone is not a valid level (2 min(p) is, by Bonferroni), so U's
%   threshold is the quantile of U on known windows disjoint from the calibration windows
%   (FM.unk.val, unk_threshold.m). The model is FM.unk of data/fusion.mat; without it every
%   reader runs as before.
%   tf = unk_stat('on', PP)            PP.fuse holds FM.unk
%   C = unk_stat('cal', s)             calibration of a score: its sorted distinct values u, the
%                                      count of values <= each (c) and their number n (finite)
%   p = unk_stat('p', C, s)            conformal p-values of s (any shape; -Inf the lowest, NaN NaN)
%   s = unk_stat('cue', U, X)          the cue score of raw cue rows X (U.scale, U.cue, U.model)
%   s = unk_stat('cue', U, X, true)    the same, every row scored alone, as the monitor scores
%                                      one episode (the offline readings: a batch's rounding
%                                      never moves a window's rank against its own calibration)
%   u = unk_stat('U', U, s0, X, full)  U of windows (column): s0 their s0 statistic, X their cue
%                                      rows, full false where the cue window is not full
%                                      (p_cue = 1 there, so U = p0 for every candidate: the first
%                                      cycles behave as today, D111 item 7); U.use0 false (C3,
%                                      the cue alone): U = p_cue where the cue window is full; a
%                                      NaN s0 gives NaN (never flagged)
%   u = unk_stat('U', U, s0, X, full, true)  the same, every row scored alone
%   u = unk_stat('frame', U, s0)       U of frames without their window (p_cue = 1, so p0): the
%                                      per-frame flag of link_env.m and episode_cycle.m
%   U = unk_stat('model', S)           FM.unk from the fields of S, checked: cand ('C1', 'C2',
%                                      'C3'), use0, cue ('maha', 'if'), scale, model, cal0, cal1,
%                                      val (U on the selection half's known windows),
%                                      nw (the cue window, cycles), step_n (ood_cue.m), N (the
%                                      fusion window), score and win (s0's)
switch cmd
    case 'on'
        PP = varargin{1};
        varargout{1} = isfield(PP, 'fuse') && isstruct(PP.fuse) && isfield(PP.fuse, 'unk') && ~isempty(PP.fuse.unk);
    case 'cal'
        s = double(varargin{1}(:)); s = s(~isnan(s));
        assert(all(isfinite(s)), 'unk_stat:cal', 'unk_stat: a calibration score is not finite');
        [u, ~, g] = unique(s);
        varargout{1} = struct('u', u, 'c', cumsum(accumarray(g, 1, [numel(u) 1])), 'n', numel(s));
    case 'p'
        varargout{1} = pval(varargin{:});
    case 'cue'
        varargout{1} = cue_score(varargin{:});
    case 'U'
        [U, s0, X, full] = varargin{1:4};
        alone = numel(varargin) >= 5 && varargin{5};
        s0 = double(s0(:)); n = numel(s0);
        if isscalar(full), full = repmat(logical(full), n, 1); else, full = logical(full(:)); end
        p0 = pval(U.cal0, s0); pc = ones(n, 1);
        if any(full), pc(full) = pval(U.cal1, cue_score(U, X(full, :), alone)); end
        if U.use0, u = min(p0, pc); else, u = pc; u(~full) = p0(~full); end
        u(isnan(s0)) = NaN;
        varargout{1} = u;
    case 'frame'
        [U, s0] = varargin{:};
        varargout{1} = pval(U.cal0, s0);
    case 'model'
        varargout{1} = model(varargin{1});
    otherwise
        error('unk_stat:cmd', 'unk_stat: unknown command %s', cmd);
end
end

function p = pval(C, s)
s = double(s);
k = zeros(size(s));
if C.n > 0
    b = discretize(s, [C.u; Inf]);                       % the largest calibration value <= s
    m = ~isnan(b);
    k(m) = C.c(b(m));
end
p = (1 + k) / (C.n + 1);
p(isnan(s)) = NaN;
end

function s = cue_score(U, X, alone)
if nargin < 3, alone = false; end
if alone && size(X, 1) > 1
    s = zeros(size(X, 1), 1);
    for i = 1:size(X, 1), s(i) = cue_score(U, X(i, :)); end
    return
end
Xs = ood_cue('scale', U.scale, X);
switch U.cue
    case 'maha', s = ood_cue('maha', U.model, Xs);
    case 'if',   s = ood_cue('if', U.model, Xs);
    otherwise, error('unk_stat:cue', 'unk_stat: unknown cue score %s', U.cue);
end
end

function U = model(S)
need = {'cand', 'use0', 'cue', 'scale', 'model', 'cal0', 'cal1', 'val', 'nw', 'step_n', 'N', 'score', 'win'};
miss = need(~isfield(S, need));
assert(isempty(miss), 'unk_stat:model', 'unk_stat: FM.unk lacks %s', strjoin(miss, ', '));
assert(ismember(S.cand, {'C1', 'C2', 'C3'}) && ismember(S.cue, {'maha', 'if'}), 'unk_stat:model', ...
    'unk_stat: FM.unk is candidate %s with cue score %s', S.cand, S.cue);
assert(S.use0 == ~strcmp(S.cand, 'C3') && strcmp(S.cue, 'if') == strcmp(S.cand, 'C2'), 'unk_stat:model', ...
    'unk_stat: candidate %s with use0 %d and cue score %s', S.cand, S.use0, S.cue);
assert(isstruct(S.cal0) && isstruct(S.cal1), 'unk_stat:model', 'unk_stat: FM.unk lacks a calibration');
v = double(S.val(:));
assert(~isempty(v) && all(isfinite(v)) && issorted(v), 'unk_stat:model', 'unk_stat: FM.unk.val must be sorted and finite');
assert(S.nw >= max([S.N, S.step_n, S.win, window_cues('branch_window')]), 'unk_stat:model', ...
    'unk_stat: the cue window %d is shorter than its parts', S.nw);
U = S; U.val = v; U.use0 = logical(S.use0);
end
