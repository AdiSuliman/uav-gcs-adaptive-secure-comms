function varargout = core_bw_rules(cmd, varargin)
%CORE_BW_RULES  The fixed rules of the bandwidth study (docs/core_bw_protocol.md), apart from
%   experiment_core_bw.m so the tests read them.
%   T = core_bw_rules('recoverable', key, rec, per, thr, env_min)
%       the recoverable-scenario rule (6.4) over validation episodes: key (1 x n) the
%       scenario of each episode, rec its episode-level recoverable flag, per the static link's
%       PER after onset, thr its restoration threshold. Per unique key (T.key): rec_pct (share
%       recoverable [%]), per and thr (pooled means), harm (per > thr), ok (rec_pct >= env_min
%       and harm)
%   [W, tab] = core_bw_rules('choose_w', Wn, bj, tot, cl, per, gput, trec, B)
%       the choice of the wideband action (6.3): Wn candidate names in their tie-break order;
%       bj, tot, cl (1 x n) each episode's width, total JSR and flight geometry; per, gput,
%       trec (numel(Wn) x n) each candidate's PER after onset, delivered payload and recovery
%       from detection (NaN never) on the same episodes; B bootstrap resamples. The same rule
%       chooses blind_core's first response (docs/core_bw_v2_note.txt)
%   v = core_bw_rules('verdict', m, lo, target, n)   the PER-reduction verdict (6.5), C2e's
%       words: MET (committed) when the 95% lower bound lo >= target, MET (not committed) when
%       only the point m is, NOT MET otherwise and without episodes (n = 0)
%   [V, lines] = core_bw_rules('per_verdicts', P, target, prim)   the PER lines of a reading:
%       P (struct array: policy, type 'narrowband' / 'wideband' / 'pooled', n, red, lo, hi, per,
%       per_ref) gains verdict and primary (rule_core per jamming type, when prim); per policy
%       the narrowband, then the wideband line (PRIMARY when primary), then the pooled one,
%       labelled the second line
%   f = core_bw_rules('flip', A, S)   whether a sensitivity's reading S would flip a primary
%       verdict of A (both per_verdicts output): some primary entry of A whose policy and type
%       S reads on episodes of its own with another verdict; a primary type without episodes
%       reads NOT MET and can flip
%   s = core_bw_rules('gap_text', m, x)   G3's distance from an escaped hop's R_eff to its
%       layer, mean m and largest x [dB] (NaN without an escaped hop)
%   P = core_bw_rules('p1', tr, tb, near, cl, B)   prediction P1's reading at JSR_tot 30 dB
%       (section 5): tr, tb (1 x n) rule_core's and blind_core's detection-to-restored times
%       on the same recoverable CW episodes (NaN never), near the episodes whose first hop
%       lands 6-12 MHz from the tone, cl their flight geometry. P.med [rule blind] medians
%       (never as the longest); P.ci the 95% interval of their difference over geometries (B
%       resamples); P.near the medians on the near episodes ([NaN NaN] without one); P.holds
%       the interval holds 0 (without one, the point is 0) and, where near episodes exist, the
%       rule's median there is the longer. No episode holds.
%   J = core_bw_rules('guard', X)   the test stage's refusals (6.6, G4) in order: no frozen
%       protocol, the protocol, the recoverable list or the deviation note (X.note, when set)
%       changed, the test read already (the smoke deletes its own marker and readings instead),
%       the frozen copy missing or not byte for byte, the protocol, the note or the copy not
%       committed; J the frozen choices
%   v = core_bw_rules('clean_ref', v)   the clean reference the monitor reads at 9 dB
%       (clean_ber_ref.m 'ber_est'), refused unless finite: without data/policy_pools.mat
%       policy_monitor.m falls to C.deg_floor and the alarm fires on the clean link
%   h = core_bw_rules('sha', f)     SHA-256 of a file, as sha256sum prints it
switch cmd
    case 'recoverable', varargout{1} = recoverable(varargin{:});
    case 'choose_w',    [varargout{1}, varargout{2}] = choose_w(varargin{:});
    case 'verdict',     varargout{1} = verdict(varargin{:});
    case 'per_verdicts', [varargout{1}, varargout{2}] = per_verdicts(varargin{:});
    case 'flip',        varargout{1} = flips(varargin{:});
    case 'gap_text',    varargout{1} = gap_text(varargin{:});
    case 'p1',          varargout{1} = p1_reading(varargin{:});
    case 'guard',       varargout{1} = guard(varargin{:});
    case 'clean_ref',   varargout{1} = clean_ref(varargin{:});
    case 'sha',         varargout{1} = file_sha(varargin{:});
    otherwise, error('core_bw_rules:cmd', 'core_bw_rules: unknown command %s', cmd);
end
end

function T = recoverable(key, rec, per, thr, env_min)
[u, ~, j] = unique(key(:)');
mean_by = @(x) accumarray(j(:), double(x(:)), [], @mean)';
T = struct('key', u, 'rec_pct', 100 * mean_by(rec), 'per', mean_by(per), 'thr', mean_by(thr));
T.harm = T.per > T.thr;
T.ok = T.rec_pct >= env_min & T.harm;
end

function [W, tab] = choose_w(Wn, bj, tot, cl, per, gput, trec, B)
nW = numel(Wn);
tab = struct('W', Wn, 'per', NaN, 'gput', NaN, 'trec', NaN, 'tie_per', false, 'tie_gput', false);
if isempty(bj), W = Wn{1}; return; end
[~, ~, g] = unique([bj(:), tot(:)], 'rows');
w = 1 ./ accumarray(g, 1); w = w(g)' / max(g);         % equal weight per (B_J, JSR_tot)
P = per * w'; G = gput * w';
tr = median(fillmissing(trec, 'constant', Inf), 2)';
[~, b] = min(P);
tie = false(1, nW); tie(b) = true;
for k = setdiff(1:nW, b)
    [~, lo, hi] = boot_cluster(w .* (per(k, :) - per(b, :)), w, cl, B, 71);
    tie(k) = lo <= 0 && hi >= 0;
end
c = find(tie);
[~, i] = max(G(c)); i = c(i);
tie2 = false(1, nW); tie2(i) = true;
for k = setdiff(c, i)
    [~, lo, hi] = boot_cluster(w .* (gput(k, :) - gput(i, :)), w, cl, B, 72);
    tie2(k) = lo <= 0 && hi >= 0;
end
c = find(tie2);
[~, o] = sortrows([tr(c)', c(:)]);
W = Wn{c(o(1))};
tab = struct('W', Wn, 'per', num2cell(P'), 'gput', num2cell(G'), 'trec', num2cell(tr), 'tie_per', num2cell(tie), ...
    'tie_gput', num2cell(tie2));
end

function v = verdict(m, lo, target, n)
if n > 0 && isfinite(lo) && lo >= target, v = 'MET (committed)';
elseif n > 0 && isfinite(m) && m >= target, v = 'MET (not committed)';
else, v = 'NOT MET'; end
end

function [V, lines] = per_verdicts(P, target, prim)
V = P; lines = {};
if isempty(V), V = struct('policy', {}, 'type', {}, 'n', {}, 'red', {}, 'lo', {}, 'hi', {}, 'per', {}, 'per_ref', {}, ...
        'verdict', {}, 'primary', {}); return; end
for i = 1:numel(V)
    V(i).verdict = verdict(V(i).red, V(i).lo, target, V(i).n);
    V(i).primary = prim && strcmp(V(i).policy, 'rule_core') && ~strcmp(V(i).type, 'pooled');
end
name = struct('narrowband', 'narrowband (CW)', 'wideband', 'wideband (4-83.5 MHz)', ...
    'pooled', 'second line, both types pooled');
for pk = unique({V.policy}, 'stable')
    for t = {'narrowband', 'wideband', 'pooled'}
        i = find(strcmp({V.policy}, pk{1}) & strcmp({V.type}, t{1}), 1);
        if isempty(i), continue; end
        v = V(i); tag = name.(t{1});
        if v.primary, tag = ['PRIMARY ' tag]; end
        if v.n == 0
            lines{end+1} = sprintf('  PER %-10s %s: no recoverable episodes -> %s', v.policy, tag, v.verdict); %#ok<AGROW>
        else
            lines{end+1} = sprintf('  PER %-10s %s, n=%d: %.4f vs %.4f static, reduction %.1f%% [%.1f, %.1f] -> %s', ...
                v.policy, tag, v.n, v.per, v.per_ref, 100 * v.red, 100 * v.lo, 100 * v.hi, v.verdict); %#ok<AGROW>
        end
    end
end
end

function f = flips(A, S)
f = false;
for i = find([A.primary])
    j = find(strcmp({S.policy}, A(i).policy) & strcmp({S.type}, A(i).type), 1);
    if ~isempty(j) && S(j).n > 0 && ~strcmp(S(j).verdict, A(i).verdict), f = true; end
end
end

function s = gap_text(m, x)
if isnan(x), s = 'no escaped hop';
else, s = sprintf('an escaped hop above its layer by %.2f dB mean, %.2f max', m, x); end
end

function P = p1_reading(tr, tb, near, cl, B)
tr = fillmissing(tr(:)', 'constant', Inf); tb = fillmissing(tb(:)', 'constant', Inf);
P = struct('n', numel(tr), 'med', [NaN NaN], 'diff', NaN, 'ci', [NaN NaN], 'n_near', nnz(near), ...
    'near', [NaN NaN], 'holds', true);
if isempty(tr), return; end
P.med = [median(tr) median(tb)]; P.diff = med_diff(tr, tb);
[~, ~, j] = unique(cl(:));
nU = max(j);
if nU >= 2
    g = accumarray(j, (1:numel(tr))', [], @(x) {x});
    rs = RandStream('mt19937ar', 'Seed', 73);
    idx = randi(rs, nU, nU, B);
    d = zeros(1, B);
    for b = 1:B
        s = vertcat(g{idx(:, b)});
        d(b) = med_diff(tr(s), tb(s));
    end
    q = sort(d);
    P.ci = [q(max(1, round(0.025 * B))), q(min(B, round(0.975 * B)))];
    eq = P.ci(1) <= 0 && P.ci(2) >= 0;
else
    eq = P.diff == 0;
end
if any(near)
    P.near = [median(tr(near)) median(tb(near))];
    eq = eq && P.near(1) > P.near(2);
end
P.holds = eq;
end

function d = med_diff(a, b)
% Median of a minus median of b; equal medians (never restored alike) differ by 0.
ma = median(a); mb = median(b);
if ma == mb, d = 0; else, d = ma - mb; end
end

function J = guard(X)
assert(isfile(X.proto_json) && isfile(X.recov), 'experiment_core_bw:protocol', ...
    'the frozen protocol (%s, %s) comes first: run the val stage', X.proto_json, X.recov);
J = jsondecode(fileread(X.proto_json));
assert(strcmp(J.protocol_sha256, file_sha(X.protocol)), 'experiment_core_bw:protocol_changed', ...
    '%s changed since the validation choices were frozen', X.protocol);
assert(strcmp(J.recoverable_sha256, file_sha(X.recov)), 'experiment_core_bw:recoverable_changed', ...
    '%s changed since it was frozen', X.recov);
note = {};
if isfield(X, 'note')
    assert(isfield(J, 'note_sha256') && strcmp(J.note_sha256, file_sha(X.note)), 'experiment_core_bw:note_changed', ...
        '%s changed since the validation choices were frozen', X.note);
    note = {X.note};
end
if X.smoke                                          % the chain check reads its own flights again
    for f = {X.marker, X.test}, if isfile(f{1}), delete(f{1}); end, end
    return
end
assert(~isfile(X.marker) && ~isfile(X.test), 'experiment_core_bw:read', ...
    'the test split was read already (%s or %s): it is read once', X.marker, X.test);
assert(isfile(X.frozen) && strcmp(file_sha(X.frozen), file_sha(X.proto_json)), 'experiment_core_bw:frozen', ...
    'the frozen protocol must be committed as %s, byte for byte %s', X.frozen, X.proto_json);
assert(git_clean([{X.frozen, X.protocol}, note]), 'experiment_core_bw:uncommitted', ...
    '%s must be committed without local changes before the test reading', strjoin([{X.frozen, X.protocol}, note], ', '));
end

function v = clean_ref(v)
assert(isscalar(v) && isfinite(v), 'experiment_core_bw:clean_ref', ['clean_ber_ref(9, ''ber_est'') is %g: ' ...
    'data/policy_pools.mat with its clean_ref must be in this tree, else the monitor falls to C.deg_floor'], v);
end

function ok = git_clean(files)
% Every file is tracked and has no local change.
root = fileparts(fileparts(fileparts(which('core_bw_rules'))));
g = sprintf('git --no-optional-locks -C "%s" ', root);
ok = true;
for f = files
    [s1, ~] = system([g 'ls-files --error-unmatch -- "' f{1} '"']);
    [s2, d] = system([g 'status --porcelain -- "' f{1} '"']);
    ok = ok && s1 == 0 && s2 == 0 && isempty(strtrim(d));
end
end

function h = file_sha(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
assert(fid > 0, 'core_bw_rules:sha', 'cannot read %s', f);
b = fread(fid, Inf, '*uint8'); fclose(fid);
if ~isempty(b), md.update(b); end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
