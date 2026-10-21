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
%       from detection (NaN never) on the same episodes; B bootstrap resamples
%   v = core_bw_rules('verdict', m, lo, target, n)   the PER-reduction verdict (6.5)
%   J = core_bw_rules('guard', X)   the test stage's refusals (6.6, G4) in order: no frozen
%       protocol, the protocol or the recoverable list changed, the test read already (the
%       smoke deletes its own marker and readings instead), the frozen copy missing or not byte
%       for byte, the protocol or the copy not committed; J the frozen choices
%   h = core_bw_rules('sha', f)     SHA-256 of a file, as sha256sum prints it
switch cmd
    case 'recoverable', varargout{1} = recoverable(varargin{:});
    case 'choose_w',    [varargout{1}, varargout{2}] = choose_w(varargin{:});
    case 'verdict',     varargout{1} = verdict(varargin{:});
    case 'guard',       varargout{1} = guard(varargin{:});
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
if n == 0, v = 'not read (no episodes)';
elseif isfinite(lo) && lo >= target, v = 'met (committed)';
elseif isfinite(m) && m >= target, v = 'met (not committed)';
else, v = 'not met'; end
end

function J = guard(X)
assert(isfile(X.proto_json) && isfile(X.recov), 'experiment_core_bw:protocol', ...
    'the frozen protocol (%s, %s) comes first: run the val stage', X.proto_json, X.recov);
J = jsondecode(fileread(X.proto_json));
assert(strcmp(J.protocol_sha256, file_sha(X.protocol)), 'experiment_core_bw:protocol_changed', ...
    '%s changed since the validation choices were frozen', X.protocol);
assert(strcmp(J.recoverable_sha256, file_sha(X.recov)), 'experiment_core_bw:recoverable_changed', ...
    '%s changed since it was frozen', X.recov);
if X.smoke                                          % the chain check reads its own flights again
    for f = {X.marker, X.test}, if isfile(f{1}), delete(f{1}); end, end
    return
end
assert(~isfile(X.marker) && ~isfile(X.test), 'experiment_core_bw:read', ...
    'the test split was read already (%s or %s): it is read once', X.marker, X.test);
assert(isfile(X.frozen) && strcmp(file_sha(X.frozen), file_sha(X.proto_json)), 'experiment_core_bw:frozen', ...
    'the frozen protocol must be committed as %s, byte for byte %s', X.frozen, X.proto_json);
assert(git_clean({X.frozen, X.protocol}), 'experiment_core_bw:uncommitted', ...
    '%s and %s must be committed without local changes before the test reading', X.frozen, X.protocol);
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
