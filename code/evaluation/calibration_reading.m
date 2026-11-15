function out = calibration_reading(varargin)
%CALIBRATION_READING  Calibration of the detector's class probabilities, a report-only reading of
%   saved outputs: expected calibration error (top label, 15 equal-width confidence bins; Naeini
%   et al. 2015, Guo et al. 2017), the multi-class Brier score (Brier 1950) and a reliability
%   table per class (one class against the rest, the same bins). Nothing is selected or changed.
%   calibration_reading(tree, tag)         every source of the finished tree tree ->
%       results/calibration/<tag>/calibration_reading.txt and .mat (never overwritten)
%   calibration_reading(tree, tag, true)   also the decision-layer pools' test splits (loads
%       data/policy_pools.mat whole: run it only when no other stage holds the memory)
%   C = calibration_reading('stats', P, y, nb)   the readings of probabilities P (N x classes,
%       rows renormalized) against true class indices y (N x 1), nb bins (default 15, bin k holds
%       [(k-1)/nb, k/nb), the last one 1 too); rows with a non-finite value are dropped and counted:
%       C.ece, C.brier, C.acc, C.n, C.n_dropped, C.rowsum_dev (largest |row sum - 1| before renormalizing),
%       C.top (nb x 4: count, mean confidence, accuracy, |gap|), C.cls (per class: ece, n_pos,
%       table nb x 3: count, mean probability, observed frequency)
%   Sources, each read where it exists:
%     results/detector_predictions*.mat  the test sets of the detector (eval_detector.m): their
%                                        probabilities when the file holds them (p_fused or probs,
%                                        frames x classes); a file of labels alone is listed as such
%     data/fusion.mat                    the fused probabilities of the validation frames out of
%                                        fold (val_probs_oof) against their target (val_target)
%     data/policy_pools.mat (opt-in)     the per-frame probabilities of the test (3) and second test
%                                        (5) splits under no_action, single threats and the clean
%                                        link, labelled per decision cycle (threat_active.m); path
%                                        loss left out (its label needs the window of its onset)
if nargin >= 1 && ischar(varargin{1}) && strcmp(varargin{1}, 'stats')
    out = stats(varargin{2:end});
    return
end
reading(varargin{:});
end

function reading(tree, tag, pools)
if nargin < 3 || isempty(pools), pools = false; end
assert(ischar(tag) && ~isempty(regexp(tag, '^[A-Za-z0-9_]+$', 'once')), 'calibration_reading:tag', ...
    'calibration_reading: the tag is letters, digits and _');
od = fullfile(project_root(), 'results', 'calibration', tag);
fo = fullfile(od, 'calibration_reading.txt'); fm = fullfile(od, 'calibration_reading.mat');
assert(~isfile(fo) && ~isfile(fm), 'calibration_reading:exists', 'calibration_reading: %s already holds a reading', od);
if ~isfolder(od), mkdir(od); end
c0 = cd(tree); back = onCleanup(@() cd(c0)); %#ok<NASGU>
cls = class_names();
lines = {sprintf('=== DETECTOR CALIBRATION (%s, tree %s) ===', tag, tree), sprintf('Generated: %s', datestr(now)), ...
    ['ECE: top-label expected calibration error, 15 equal-width confidence bins; Brier: mean over frames of the sum over ' ...
    'classes of (p - 1[true])^2 (0 perfect, 2 worst); reliability per class: one class against the rest, the same bins. ' ...
    'Report only.']};
R = struct('source', {}, 'C', {});
d = dir(fullfile('results', 'detector_predictions*.mat'));
for k = 1:numel(d)
    f = fullfile('results', d(k).name);
    S = load(f, 'pred'); p = S.pred;
    pf = intersect({'p_fused', 'probs'}, fieldnames(p), 'stable');
    if isempty(pf)
        lines{end+1} = sprintf('%s: labels only (%s), no probabilities saved: no calibration reading from this file', ...
            f, strjoin(fieldnames(p)', ', ')); %#ok<AGROW>
        continue
    end
    cp = cls; if isfield(p, 'classes'), cp = cellstr(string(p.classes(:)')); end
    C = stats(double(p.(pf{1})), labels(p.y_true, cp));
    R(end+1) = struct('source', f, 'C', C); %#ok<AGROW>
    lines = [lines, block(sprintf('%s (%s)', f, pf{1}), C, cls)]; %#ok<AGROW>
end
if isfile(fullfile('data', 'fusion.mat'))
    v = whos('-file', fullfile('data', 'fusion.mat'));
    if all(ismember({'val_probs_oof', 'val_target'}, {v.name}))
        S = load(fullfile('data', 'fusion.mat'), 'val_probs_oof', 'val_target');
        C = stats(double(S.val_probs_oof), labels(S.val_target, cls));
        R(end+1) = struct('source', 'data/fusion.mat', 'C', C);
        lines = [lines, block('data/fusion.mat: fused probabilities of the validation frames, out of fold, against their target', C, cls)];
    end
end
if pools
    [P, y, src, cls_p] = pool_frames();
    for k = 1:numel(P)
        C = stats(P{k}, y{k});
        R(end+1) = struct('source', src{k}, 'C', C); %#ok<AGROW>
        lines = [lines, block(src{k}, C, cls_p)]; %#ok<AGROW>
    end
end
save(fm, 'R', 'cls');
fid = fopen(fo, 'w'); fprintf(fid, '%s\n', lines{:}); fclose(fid);
fprintf('%s\n', lines{:});
end

function C = stats(P, y, nb)
if nargin < 3 || isempty(nb), nb = 15; end
y = double(y(:)); K = size(P, 2);
assert(numel(y) == size(P, 1), 'calibration_reading:labels', 'calibration_reading: one label per row');
keep = all(isfinite(P), 2) & isfinite(y);
C.n_dropped = sum(~keep); P = P(keep, :); y = y(keep); N = numel(y);
assert(all(y >= 1 & y <= K & y == round(y)), 'calibration_reading:labels', ...
    'calibration_reading: one class index in 1..%d per row', K);
s = sum(P, 2);
C.rowsum_dev = max(abs(s - 1));
P = P ./ max(s, eps);
[cf, pr] = max(P, [], 2);
ok = pr == y;
b = bin_of(cf, nb);
C.top = zeros(nb, 4);
for i = 1:nb
    m = b == i; n = sum(m);
    if n == 0, C.top(i, :) = [0 NaN NaN NaN]; continue; end
    C.top(i, :) = [n, mean(cf(m)), mean(ok(m)), abs(mean(ok(m)) - mean(cf(m)))];
end
w = C.top(:, 1) / N; g = C.top(:, 4); g(isnan(g)) = 0;
C.ece = sum(w .* g);
Y = zeros(N, K); Y(sub2ind([N K], (1:N)', y)) = 1;
C.brier = mean(sum((P - Y) .^ 2, 2));
C.acc = mean(ok); C.n = N;
C.cls = struct('ece', cell(1, K), 'n_pos', cell(1, K), 'table', cell(1, K));
for k = 1:K
    bk = bin_of(P(:, k), nb); T = zeros(nb, 3);
    for i = 1:nb
        m = bk == i; n = sum(m);
        if n == 0, T(i, :) = [0 NaN NaN]; else, T(i, :) = [n, mean(P(m, k)), mean(y(m) == k)]; end
    end
    gk = abs(T(:, 3) - T(:, 2)); gk(isnan(gk)) = 0;
    C.cls(k) = struct('ece', sum(T(:, 1) / N .* gk), 'n_pos', sum(y == k), 'table', T);
end
end

function b = bin_of(p, nb)
% Equal-width bins on [0, 1]: bin k holds [(k-1)/nb, k/nb), the last one 1 too (integer index).
b = min(nb, max(1, floor(p * nb) + 1));
end

function y = labels(y, cls)
% Class indices in the order of the stored class list cls: a categorical label is matched by name.
if iscategorical(y) || isstring(y) || iscellstr(y)
    [ok, y] = ismember(cellstr(string(y(:))), cls);
    assert(all(ok), 'calibration_reading:labels', 'calibration_reading: a label outside the stored class list');
else
    y = double(y(:));
end
end

function lines = block(ttl, C, cls)
lines = {'', ttl, sprintf(['  frames %d (%d dropped: a non-finite probability or label), accuracy %.2f%%, ECE %.4f, Brier %.4f, ' ...
    'largest row-sum deviation %.2g'], C.n, C.n_dropped, 100 * C.acc, C.ece, C.brier, C.rowsum_dev), ...
    '  top-label reliability: bin, frames, mean confidence, accuracy'};
for i = 1:size(C.top, 1)
    if C.top(i, 1) > 0
        lines{end+1} = sprintf('    %2d  %7d  %.3f  %.3f', i, C.top(i, 1), C.top(i, 2), C.top(i, 3)); %#ok<AGROW>
    end
end
lines{end+1} = '  per class (one against the rest): ECE, frames of the class; bins with frames: count, mean p, frequency';
for k = 1:numel(C.cls)
    nm = sprintf('class %d', k); if k <= numel(cls), nm = cls{k}; end
    T = C.cls(k).table; r = find(T(:, 1) > 0)';
    cells = arrayfun(@(i) sprintf('%d:%d/%.2f/%.2f', i, T(i, 1), T(i, 2), T(i, 3)), r, 'UniformOutput', false);
    lines{end+1} = sprintf('    %-22s ECE %.4f, n %d | %s', nm, C.cls(k).ece, C.cls(k).n_pos, strjoin(cells, ' ')); %#ok<AGROW>
end
end

function cls = class_names()
% The detector's class names (data/trained_detector.mat), empty without them.
cls = {};
f = fullfile('data', 'trained_detector.mat');
if ~isfile(f), return; end
v = whos('-file', f);
if ~ismember('classes', {v.name}), return; end
S = load(f, 'classes'); cls = cellstr(string(S.classes(:)'));
end

function [P, y, src, cls] = pool_frames()
% Per-frame probabilities of the decision-layer pools' test splits under no_action.
L = load(fullfile('data', 'policy_pools.mat'), 'PP'); PP = L.PP; clear L
cls = cellstr(string(PP.classes(:)'));
na = find(strcmp(PP.actions, 'no_action'), 1);
cells = find((ismember(PP.scen, PP.singles) & ~strcmp(PP.scen, 'path_loss')) | strcmp(PP.scen, 'none'));
P = {}; y = {}; src = {};
for sp = [3 5]
    if size(PP.pools, 4) < sp, continue; end
    Pk = []; yk = [];
    for c = cells
        for s = 1:size(PP.pools, 2)
            Q = PP.pools{c, s, na, sp};
            if isempty(Q) || ~isfield(Q, 'probs') || isempty(Q.probs), continue; end
            on = true(size(Q.act));
            if ~strcmp(PP.scen{c}, 'none'), on = threat_active(PP.scen{c}, Q.act, [], [], Q.act_idle); end
            lab = repmat(find(strcmp(cls, 'none')), numel(on), 1);
            if ~strcmp(PP.scen{c}, 'none'), lab(on(:)) = find(strcmp(cls, PP.scen{c})); end
            Pk = [Pk; double(Q.probs)]; yk = [yk; lab]; %#ok<AGROW>
        end
    end
    if isempty(Pk), continue; end
    P{end+1} = Pk; y{end+1} = yk; %#ok<AGROW>
    src{end+1} = sprintf(['data/policy_pools.mat split %d (%s) under no_action: single threats but path_loss, and the clean ' ...
        'link, per-frame probabilities, labels per decision cycle (threat_active.m)'], sp, ternary(sp == 3, 'test', 'second test')); %#ok<AGROW>
end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
