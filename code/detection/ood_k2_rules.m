function varargout = ood_k2_rules(cmd, varargin)
%OOD_K2_RULES  D111's pre-registered rules (docs: DECISIONS.md D111), committed with their
%   SHA-256 before any of their data: gate K2-1, the adoption rule of items 5-6, its bootstrap,
%   the static test, and the guards of the OOD run and K2-1.
%   [go, L] = ood_k2_rules('k21_go', names, a)  gate K2-1 (item 1): a, cue-Maha's validation AUROC
%       per held-out threat names; go only if >= 0.80 on at least 2 of {path_loss, jamming,
%       antenna_fault, airframe_shadowing} and >= 0.70 on their mean; it selects no variant
%   D = ood_k2_rules('decide', A, B, F, N, ok, rows)  items 5-6 on the held-out threats rows:
%       A    threats x candidates validation AUROC, C0 first (C0, C1, C2, C3)
%       B    draws x threats x candidates, their bootstrap AUROC (boot_auroc, the same draws for
%            every candidate)
%       F    threats x classes x candidates, the known validation windows (selection half) of each
%            class flagged unknown at the threshold keeping 95% of them; N threats x classes their
%            number
%       ok   1 x candidates, (d) (the static and parity tests) and D80's latency admission
%       (a) mean AUROC >= C0's + 0.010 and the 5th percentile of the draws' mean paired difference
%       > 0; (b) no threat loses more than 0.03; (c) no class flagged more than twice as often as
%       under C0, nor above 10%; D.eligible, D.pick (1 = C0: none eligible; else the eligible
%       candidate with the highest mean AUROC, ood_select.m's rule), D.mean, D.lb, D.a, D.b, D.c
%   A = ood_k2_rules('boot_auroc', S, kn, un, run, nB, seed)  nB x columns of S: the AUROC of every
%       score column (higher = known) of the known windows kn against the held-out ones un, the
%       sub-runs resampled with replacement within each group, one fixed-seed stream
%   a = ood_k2_rules('auroc', p, q)  P(known p > held-out q) + half the ties (ood_fold_metrics.m)
%   tf = ood_k2_rules('static', names)  no class probability, label or truth field in a cue row
%   [h, L] = ood_k2_rules('registered', repo, commit)  the docs repository's commit that registers
%       D110-D118 (its DECISIONS.md holds D111's heading): its full hash, or an error; an empty
%       commit or repo is read from profile.json (registration_commit, docs_repo), the repo else
%       from the environment variable V7_DOCS_REPO
%   L = ood_k2_rules('sha', files)  'rule_sha256 <file> <SHA-256>' of each code file (by name)
%   tf = ood_k2_rules('b3r_recorded', pid)  a committed B3r record, docs/d91_fresh3_read_*.txt
%       (aborted ones aside), names params_id pid
%   [v, S] = ood_k2_rules('select_record', f)  the committed select record f (tracked, unchanged):
%       its verdict ('C0' to 'C3') and its rule_sha256 lines
%   [cm, tr] = ood_k2_rules('commit')  the code checkout's commit and code tree
NAMED = {'path_loss', 'jamming', 'antenna_fault', 'airframe_shadowing'};
switch cmd
    case 'k21_go'
        [names, a] = varargin{:};
        [ok, j] = ismember(NAMED, names);
        assert(all(ok), 'ood_k2_rules:k21', 'K2-1 needs the AUROC of %s', strjoin(NAMED, ', '));
        x = a(j);
        go = sum(x >= 0.80) >= 2 && mean(x) >= 0.70;
        L = sprintf(['Gate K2-1 (D111 item 1): cue-Maha validation AUROC %s; >= 0.80 on %d of 4 (need 2), mean %.3f ' ...
            '(need 0.70) -> %s'], strjoin(arrayfun(@(i) sprintf('%s %.3f', NAMED{i}, x(i)), 1:4, 'UniformOutput', false), ...
            ', '), sum(x >= 0.80), mean(x), ternary(go, 'GO (K2-2 is built)', 'NO-GO (K2-2 is not built; KPI 2 stays 0.763)'));
        varargout = {go, L};
    case 'decide'
        varargout{1} = decide(varargin{:});
    case 'boot_auroc'
        varargout{1} = boot_auroc(varargin{:});
    case 'auroc'
        [p, q] = varargin{:};
        varargout{1} = wauroc(p(:), q(:), ones(numel(p), 1), ones(numel(q), 1));
    case 'static'
        n = lower(varargin{1});
        bad = startsWith(n, {'logp', 'prob', 'p_', 'label', 'y_'}) | ismember(n, {'y', 'class', 'class_run', 'k_db', ...
            'lev_db', 'level', 'ebno', 'ebno_rx', 'speed', 'roll_in', 'alt_m', 'bank', 'ds_ns', 'aoa', 'act', 'act_idle', ...
            'draws', 'run', 'pos'});
        varargout{1} = ~any(bad);
    case 'registered'
        [repo, commit] = varargin{:};
        P = struct(); if isfile('profile.json'), P = jsondecode(fileread('profile.json')); end
        if isempty(commit) && isfield(P, 'registration_commit'), commit = P.registration_commit; end
        if isempty(repo) && isfield(P, 'docs_repo'), repo = P.docs_repo; end
        if isempty(repo), repo = getenv('V7_DOCS_REPO'); end
        assert(~isempty(commit) && ~isempty(repo), 'ood_k2_rules:registration', ['name the docs repository and the commit ' ...
            'that registers D110-D118 (REG_COMMIT and DOCS_REPO, or registration_commit and docs_repo in profile.json)']);
        assert(~isempty(regexp(commit, '^[0-9a-f]{7,40}$', 'once')), 'ood_k2_rules:registration', '%s is not a commit hash', commit);
        g = sprintf('git --no-optional-locks -C "%s" ', repo);
        [s1, h] = system([g 'rev-parse --verify "' commit '^{commit}"']);
        assert(s1 == 0, 'ood_k2_rules:registration', 'no commit %s in %s: D110-D118 are not registered there', commit, repo);
        h = strtrim(h);
        [s2, txt] = system([g 'show ' h ':docs/DECISIONS.md']);
        assert(s2 == 0 && contains(txt, '## D111 '), 'ood_k2_rules:registration', ...
            'docs/DECISIONS.md of %s holds no D111: the run starts only after the commit that registers it', h);
        varargout = {h, sprintf('registration commit %s (%s)', h, repo)};
    case 'sha'
        f = varargin{1};
        varargout{1} = cellfun(@(x) sprintf('rule_sha256 %s %s', x, file_sha(which(x))), f, 'UniformOutput', false);
    case 'b3r_recorded'
        pid = varargin{1}; yes = false;
        for r = dir('docs/d91_fresh3_read_*.txt')'
            if contains(r.name, '_aborted'), continue; end
            f = ['docs/' r.name];
            yes = yes || (committed(f) && any(strcmp(strtrim(splitlines(fileread(f))), ['params_id ' pid])));
        end
        varargout{1} = yes;
    case 'select_record'
        f = varargin{1};
        assert(isfile(f) && committed(f), 'ood_k2_rules:select_record', ...
            '%s is missing, not committed or changed since: the read phase needs the committed select record', f);
        L = strtrim(splitlines(fileread(f)));
        v = regexp(L, '^verdict (C[0-3])\b', 'tokens', 'once'); v = v(~cellfun(@isempty, v));
        assert(numel(v) == 1, 'ood_k2_rules:select_record', '%s holds no single verdict line', f);
        varargout = {v{1}{1}, L(startsWith(L, 'rule_sha256 '))};
    case 'commit'
        [varargout{1}, varargout{2}] = code_commit();
    otherwise
        error('ood_k2_rules:cmd', 'ood_k2_rules: unknown command %s', cmd);
end
end

function D = decide(A, B, F, N, ok, rows)
J = size(A, 2); rows = rows(:)';
D = struct('eligible', false(1, J), 'pick', 1, 'mean', mean(A(rows, :), 1), 'lb', nan(1, J), ...
    'a', false(1, J), 'b', false(1, J), 'c', false(1, J));
s0 = sum(F(rows, :, 1), 1) ./ sum(N(rows, :), 1);
has = sum(N(rows, :), 1) > 0;
for j = 2:J
    m = mean(B(:, rows, j) - B(:, rows, 1), 2);
    D.lb(j) = prctile(m, 5);
    D.a(j) = D.mean(j) >= D.mean(1) + 0.010 && D.lb(j) > 0;
    D.b(j) = all(A(rows, j) - A(rows, 1) >= -0.03);
    sj = sum(F(rows, :, j), 1) ./ sum(N(rows, :), 1);
    D.c(j) = all(sj(has) <= 2 * s0(has) & sj(has) <= 0.10);
    D.eligible(j) = D.a(j) && D.b(j) && D.c(j) && ok(j);
end
if any(D.eligible)
    m = D.mean; m(~D.eligible) = -inf;
    [~, D.pick] = max(m);
end
end

function A = boot_auroc(S, kn, un, run, nB, seed)
rs = RandStream('mt19937ar', 'Seed', seed);
ik = find(kn(:)); iu = find(un(:));
[~, ~, gk] = unique(run(ik)); [~, ~, gu] = unique(run(iu));
nk = max(gk); nu = max(gu); J = size(S, 2);
G = cell(1, J); V = zeros(1, J);
for j = 1:J
    [v, ~, G{j}] = unique([S(ik, j); S(iu, j)]); V(j) = numel(v);
end
np = numel(ik); A = zeros(nB, J);
for b = 1:nB
    ck = accumarray(randi(rs, nk, nk, 1), 1, [nk 1]); cu = accumarray(randi(rs, nu, nu, 1), 1, [nu 1]);
    wk = ck(gk); wu = cu(gu);
    for j = 1:J
        Wp = accumarray(G{j}(1:np), wk, [V(j) 1]); Wq = accumarray(G{j}(np + 1:end), wu, [V(j) 1]);
        A(b, j) = sum(Wp .* (cumsum(Wq) - Wq + 0.5 * Wq)) / (sum(wk) * sum(wu));
    end
end
end

function a = wauroc(p, q, wp, wq)
[v, ~, g] = unique([p; q]); np = numel(p);
if isempty(p) || isempty(q), a = NaN; return; end
Wp = accumarray(g(1:np), wp, [numel(v) 1]); Wq = accumarray(g(np + 1:end), wq, [numel(v) 1]);
a = sum(Wp .* (cumsum(Wq) - Wq + 0.5 * Wq)) / (sum(wp) * sum(wq));
end

function yes = committed(f)
% f is tracked by the checkout's git and unchanged since its commit.
g = sprintf('git --no-optional-locks -C "%s" ', pwd);
[s1, ~] = system([g 'ls-files --error-unmatch -- "' f '"']);
[s2, d] = system([g 'status --porcelain -- "' f '"']);
yes = s1 == 0 && s2 == 0 && isempty(strtrim(d));
end

function [cm, tr] = code_commit()
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
g = sprintf('git --no-optional-locks -C "%s" ', root);
[st, o] = system([g 'rev-parse HEAD HEAD:code']);
[sd, d] = system([g 'status --porcelain --untracked-files=all -- code']);
o = strsplit(strtrim(o)); cm = 'unknown'; tr = 'unknown';
if st == 0 && numel(o) == 2, cm = o{1}; tr = o{2}; end
if st == 0 && (sd ~= 0 || ~isempty(strtrim(d))), cm = [cm ' + local changes in code']; end
end

function h = file_sha(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
assert(fid > 0, 'ood_k2_rules:read', 'cannot read %s', f);
b = fread(fid, Inf, '*uint8'); fclose(fid);
if ~isempty(b), md.update(b); end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
