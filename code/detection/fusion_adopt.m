function varargout = fusion_adopt(cmd, varargin)
%FUSION_ADOPT  The paired comparison of a fusion's further columns against the fusion
%   without them, and the rules that adopt them (select_fusion.m with FUSION_REV).
%   B = fusion_adopt('boot', run, nb, seed)   nb resamples of the sub-runs with replacement
%   d = fusion_adopt('paired', yt, ya, yb, above, low, classes, B)
%       b - a in points, [value, 2.5%, 97.5%] over the sub-run bootstrap B, of: all and above
%       (macro-F1 over every frame and over the frames above the KPI 1 threshold), cl and lb
%       (the clean frames read as any threat and as a lost branch, share of the clean
%       frames), fault and shad (antenna_fault and airframe_shadowing F1), fault_low and
%       shad_low (the same over the frames of low, the flights whose K is at most 0 dB)
%   ok = fusion_adopt('cfar', d)    the idle time against the radio's own noise: macro-F1
%       above the threshold loses nothing (lower bound >= -0.1), every frame's gains (lower
%       bound > 0), the clean frames read as a threat do not rise (lower bound <= 0)
%   ok = fusion_adopt('branch', d)  a lost branch's evidence: antenna_fault F1 gains (lower
%       bound > 0), macro-F1 gains over every frame and above the threshold (lower bounds >
%       0), airframe_shadowing F1 loses nothing beyond its interval (upper bound >= 0), at K
%       <= 0 dB neither lost-branch class loses beyond its interval (upper bounds >= 0: the
%       onset latch read faults as ramps there, d87), and the clean frames read as a threat
%       or as a lost branch do not rise (lower bounds <= 0)
%   [pick, bs] = fusion_adopt('choose', G)   G{v} the paired comparison of variant v against
%       none (v = 2 the idle-time columns, 3 on the branch variants; G{1} unused): pick the
%       variant (1 none), or 0 with bs, the adopted branch variant with the largest gain over
%       every frame, when the idle-time columns are adopted too and their combination with it
%       is to be compared
%   pick = fusion_adopt('combo', G, bs, d)   d the combination's comparison: numel(G) + 1 (the
%       combination) when both rules hold for it, else the single one with the larger gain
%   Macro-F1 over the classes present among the targets (eval_detector.m).
%
%   The candidates over the d91 pick (the base B; fusion_cand.m), out of fold:
%   d = fusion_adopt('paired_cls', yt, ya, yb, above, low, set, classes, B)  'paired' and, in
%       points: cls (every class's F1, C x 3 in the classes' order), cb (the clean frames read
%       as benign_interference), set_shad and set_benign (the airframe_shadowing and
%       benign_interference F1 gains of each component set of the fit set, set 1-4, points)
%   [ok, s] = fusion_adopt('head', d, t)   rule S (the head or the gated coherence columns):
%       S1 airframe_shadowing F1 gains (point >= +1.0, lower bound > 0); S2 macro-F1 over
%       every frame and above the threshold gains (lower bounds > 0); S3 every other class
%       loses nothing beyond its interval (upper bound >= 0, point >= -0.5); S4 antenna_fault
%       and airframe_shadowing F1 at K <= 0 dB (points >= -1.0, upper bounds >= 0); S5 the
%       clean frames read as a threat and as a lost branch do not rise (lower bounds <= 0,
%       points <= +0.05); S6 the shadowing gain in each component set (points >= 0); S7 with
%       t (a head): its single-row call p95 <= 1.0 ms and the detector with it within the
%       KPI 7 budget (kpi7_admit.m; t.median_ms, t.p95_ms the head's, t.det_median_ms,
%       t.det_p95_ms the detector's); s the conditions
%   [ok, s] = fusion_adopt('cfar', d)      with d from 'paired_cls', rule W (the idle columns):
%       W1 benign_interference F1 gains (point >= +0.5, lower bound > 0); W2 macro-F1 above
%       the threshold (lower bound >= -0.1) and over every frame (lower bound > 0); W3 every
%       class but benign_interference as S3, S5, and the clean frames read as
%       benign_interference do not rise (lower bound <= 0); W4 the clean gaps of the held-out
%       folds above T1 and above T2 (d.exc, percent) at most 1%; W5 the benign gain in each
%       component set (points >= 0)
%   [ok, s] = fusion_adopt('cand', name, d, t)  'LBH', 'GCC', 'CFAR', 'LBH+CFAR', 'GCC+CFAR':
%       rule S for LBH, GCC and the head part of a combination (S7 for a head; a head without
%       t fails it), rule W for the CFAR part
%   [k, ok] = fusion_adopt('pick', names, G, t)  of the candidates passing their rules, the one
%       with the largest macro-F1 gain over every frame (k index into names, 0 none: B)
%   [ok, s] = fusion_adopt('nested', picks, d, t)  the nested reading d (each outer fold's
%       inner pick, picks its names, '' B) passes rule S if any outer fold picked LBH, GCC or a
%       combination, and rule W if any picked CFAR or a combination; with no candidate picked
%       anywhere there is nothing to pass (false)
switch cmd
    case 'boot', varargout{1} = boot(varargin{:});
    case 'paired', varargout{1} = paired(varargin{:});
    case 'paired_cls', varargout{1} = paired_cls(varargin{:});
    case 'head', [varargout{1}, varargout{2}] = rule_s(varargin{:});
    case 'cand', [varargout{1}, varargout{2}] = cand(varargin{:});
    case 'pick', [varargout{1}, varargout{2}] = pick_cand(varargin{:});
    case 'nested', [varargout{1}, varargout{2}] = nested(varargin{:});
    case 'cfar'
        d = varargin{1};
        if isfield(d, 'cls'), [varargout{1}, varargout{2}] = rule_w(d); return; end
        varargout{1} = d.above(2) >= -0.1 && d.all(2) > 0 && d.cl(2) <= 0;
    case 'branch'
        d = varargin{1};
        varargout{1} = d.fault(2) > 0 && d.all(2) > 0 && d.above(2) > 0 && d.shad(3) >= 0 && ...
            d.fault_low(3) >= 0 && d.shad_low(3) >= 0 && d.cl(2) <= 0 && d.lb(2) <= 0;
    case 'choose'
        [varargout{1}, varargout{2}] = choose(varargin{1});
    case 'combo'
        G = varargin{1}; bs = varargin{2}; d = varargin{3};
        if fusion_adopt('cfar', d) && fusion_adopt('branch', d), varargout{1} = numel(G) + 1;
        elseif G{2}.all(1) >= G{bs}.all(1), varargout{1} = 2;
        else, varargout{1} = bs;
        end
    otherwise, error('fusion_adopt: unknown command %s', cmd);
end
end

function [pick, bs] = choose(G)
ac = fusion_adopt('cfar', G{2});
ab = cellfun(@(d) fusion_adopt('branch', d), G(3:end));
g = cellfun(@(d) d.all(1), G(3:end)); g(~ab) = -Inf;
[~, j] = max(g); bs = [];
if any(ab), bs = j + 2; end
if ac && ~isempty(bs), pick = 0;
elseif ac, pick = 2;
elseif ~isempty(bs), pick = bs;
else, pick = 1;
end
end

function B = boot(run, nb, seed)
[u, ~, ri] = unique(run(:));
s = RandStream('mt19937ar', 'Seed', seed);
B = struct('ri', ri, 'n', numel(u), 'w', zeros(nb, numel(u)));
for b = 1:nb, B.w(b, :) = accumarray(randi(s, numel(u), numel(u), 1), 1, [numel(u) 1])'; end
end

function d = paired(yt, ya, yb, above, low, classes, B)
classes = cellstr(string(classes)); C = numel(classes); nr = B.n;
yt = yt(:); ya = ya(:); yb = yb(:);
i0 = find(strcmp(classes, 'none')); ia = find(strcmp(classes, 'antenna_fault')); is = find(strcmp(classes, 'airframe_shadowing'));
cmr = @(m, yh) accumarray([B.ri(m), sub2ind([C C], yt(m), yh(m))], 1, [nr C * C]);
al = true(size(yt));
M = {cmr(al, ya), cmr(al, yb), cmr(above, ya), cmr(above, yb), cmr(low, ya), cmr(low, yb)};
cl = yt == i0; cnt = @(x) accumarray(B.ri(cl), double(x(cl)), [nr 1]);
n1a = cnt(ya ~= i0); n1b = cnt(yb ~= i0); n2a = cnt(ismember(ya, [ia is])); n2b = cnt(ismember(yb, [ia is])); dn = cnt(al);
    function v = one(w)
        cm = cellfun(@(X) reshape(w * X, C, C), M, 'UniformOutput', false);
        v = 100 * [mf1(cm{2}) - mf1(cm{1}), mf1(cm{4}) - mf1(cm{3}), (w * (n1b - n1a)) / max(w * dn, 1), ...
            (w * (n2b - n2a)) / max(w * dn, 1), cf1(cm{2}, ia) - cf1(cm{1}, ia), cf1(cm{2}, is) - cf1(cm{1}, is), ...
            cf1(cm{6}, ia) - cf1(cm{5}, ia), cf1(cm{6}, is) - cf1(cm{5}, is)];
    end
x = zeros(size(B.w, 1), 8);
for b = 1:size(B.w, 1), x(b, :) = one(B.w(b, :)); end
pt = one(ones(1, nr));
ci = prctile(x, [2.5 97.5]);
f = {'all', 'above', 'cl', 'lb', 'fault', 'shad', 'fault_low', 'shad_low'};
d = struct();
for k = 1:numel(f), d.(f{k}) = [pt(k) ci(:, k)']; end
end

function f = mf1(cm)
pr = diag(cm) ./ sum(cm, 1)'; rc = diag(cm) ./ sum(cm, 2);
f1 = 2 * pr .* rc ./ (pr + rc);
f = mean(f1(sum(cm, 2) > 0), 'omitnan');
end

function f = cf1(cm, c)
% F1 of class c (0 where it is never read and never true)
if isempty(c), f = NaN; return; end
tp = cm(c, c); f = 2 * tp / max(sum(cm(c, :)) + sum(cm(:, c)), eps);
end

function f = f1v(cm)
% F1 of every class (0 where it is never read and never true)
f = 2 * diag(cm)' ./ max(sum(cm, 2)' + sum(cm, 1), eps);
end

function d = paired_cls(yt, ya, yb, above, low, st, classes, B)
d = paired(yt, ya, yb, above, low, classes, B);
classes = cellstr(string(classes)); C = numel(classes); nr = B.n;
yt = yt(:); ya = ya(:); yb = yb(:); st = st(:);
i0 = find(strcmp(classes, 'none')); ib = find(strcmp(classes, 'benign_interference'));
is = find(strcmp(classes, 'airframe_shadowing'));
cmr = @(m, yh) accumarray([B.ri(m), sub2ind([C C], yt(m), yh(m))], 1, [nr C * C]);
al = true(size(yt));
Ma = cmr(al, ya); Mb = cmr(al, yb);
cl = yt == i0; cnt = @(x) accumarray(B.ri(cl), double(x(cl)), [nr 1]);
nba = zeros(nr, 1); nbb = nba; dn = cnt(al);
if ~isempty(ib), nba = cnt(ya == ib); nbb = cnt(yb == ib); end
    function v = one_cls(w)
        v = [100 * (f1v(reshape(w * Mb, C, C)) - f1v(reshape(w * Ma, C, C))), 100 * (w * (nbb - nba)) / max(w * dn, 1)];
    end
x = zeros(size(B.w, 1), C + 1);
for b = 1:size(B.w, 1), x(b, :) = one_cls(B.w(b, :)); end
pt = one_cls(ones(1, nr));
ci = prctile(x, [2.5 97.5]);
d.cls = [pt(1:C)', ci(:, 1:C)'];
d.cb = [pt(end), ci(:, end)'];
if isempty(ib), d.cb = nan(1, 3); end
d.classes = classes;
u = 1:max(st);
cmk = @(k, yh) accumarray([yt(st == k), yh(st == k)], 1, [C C]);
d.set_shad = arrayfun(@(k) 100 * (cf1(cmk(k, yb), is) - cf1(cmk(k, ya), is)), u);
d.set_benign = arrayfun(@(k) 100 * (cf1(cmk(k, yb), ib) - cf1(cmk(k, ya), ib)), u);
end

function [ok, s] = rule_s(d, t)
if nargin < 2, t = []; end
is = find(strcmp(d.classes, 'airframe_shadowing'));
o = setdiff(1:numel(d.classes), is);
s = struct();
s.S1 = d.shad(1) >= 1.0 && d.shad(2) > 0;
s.S2 = d.all(2) > 0 && d.above(2) > 0;
s.S3 = all(d.cls(o, 3) >= 0 & d.cls(o, 1) >= -0.5);
s.S4 = d.fault_low(1) >= -1.0 && d.fault_low(3) >= 0 && d.shad_low(1) >= -1.0 && d.shad_low(3) >= 0;
s.S5 = clean_ok(d);
s.S6 = all(d.set_shad >= 0);
s.S7 = true;
if ~isempty(t), s.S7 = t.p95_ms <= 1.0 && kpi7_admit(t.det_median_ms + t.median_ms, t.det_p95_ms + t.p95_ms); end
ok = all(cell2mat(struct2cell(s)));
end

function [ok, s] = rule_w(d)
ib = find(strcmp(d.classes, 'benign_interference'));
o = setdiff(1:numel(d.classes), ib);
s = struct();
s.W1 = d.cls(ib, 1) >= 0.5 && d.cls(ib, 2) > 0;
s.W2 = d.above(2) >= -0.1 && d.all(2) > 0;
s.W3 = all(d.cls(o, 3) >= 0 & d.cls(o, 1) >= -0.5) && clean_ok(d) && d.cb(2) <= 0;
s.W4 = isfield(d, 'exc') && numel(d.exc) == 2 && all(d.exc <= 1);
s.W5 = all(d.set_benign >= 0);
ok = all(cell2mat(struct2cell(s)));
end

function ok = clean_ok(d)
ok = d.cl(2) <= 0 && d.cl(1) <= 0.05 && d.lb(2) <= 0 && d.lb(1) <= 0.05;
end

function [ok, s] = cand(name, d, t)
if nargin < 3, t = []; end
[hs, hw, hh] = parts(name);
ok = true; s = struct();
if hs
    th = []; if hh, th = head_t(t); end
    [a, s1] = rule_s(d, th); ok = ok && a; s = s1;
end
if hw
    [a, s2] = rule_w(d); ok = ok && a;
    for f = fieldnames(s2)', s.(f{1}) = s2.(f{1}); end
end
end

function t = head_t(t)
% A head's timing for S7; a head judged without one fails it.
if isempty(t), t = struct('median_ms', NaN, 'p95_ms', NaN, 'det_median_ms', NaN, 'det_p95_ms', NaN); end
end

function [hs, hw, hh] = parts(name)
% Rule S applies (head or gated columns), rule W applies (idle columns), a head is in it.
ok = ismember(name, {'LBH', 'GCC', 'CFAR', 'LBH+CFAR', 'GCC+CFAR'});
assert(ok, 'fusion_adopt:cand', 'unknown candidate %s', name);
hh = contains(name, 'LBH'); hs = hh || contains(name, 'GCC'); hw = contains(name, 'CFAR');
end

function [k, ok] = pick_cand(names, G, t)
if nargin < 3, t = []; end
ok = cellfun(@(n, d) cand(n, d, t), names, G);
g = cellfun(@(d) d.all(1), G); g(~ok) = -Inf;
k = 0;
if any(ok), [~, k] = max(g); end
end

function [ok, s] = nested(picks, d, t)
if nargin < 3, t = []; end
p = picks(~cellfun(@isempty, picks));
s = struct();
if isempty(p), ok = false; return; end
[hs, hw, hh] = cellfun(@parts, p);
ok = true;
if any(hs)
    th = []; if any(hh), th = head_t(t); end
    [a, s1] = rule_s(d, th); ok = ok && a; s = s1;
end
if any(hw)
    [a, s2] = rule_w(d); ok = ok && a;
    for f = fieldnames(s2)', s.(f{1}) = s2.(f{1}); end
end
end
