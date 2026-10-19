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
switch cmd
    case 'boot', varargout{1} = boot(varargin{:});
    case 'paired', varargout{1} = paired(varargin{:});
    case 'cfar'
        d = varargin{1};
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
