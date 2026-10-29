function out = aprime_fresh(cmd, varargin)
%APRIME_FRESH  The no-threat penalty form's runs (A', train_dqn.m section 7,
%   data/aprime_agents.mat) on P1R's fresh clean test set: flown in C2e's single reading of the
%   set, on the same flights and frame draws as every policy, and reported as KPI 6 rows after
%   theirs; descriptive, never the deployed policy's KPI 6.
%   ap = aprime_fresh('load', Q, cfg, f)   before any fresh flight (evaluate_policies.m with
%       kpi6_set fresh). Q: data/trained_dqn.mat as C2e loads it; cfg: CFG or []; f: default
%       data/aprime_agents.mat. [] when f is absent and C2's switch (fa_nothreat_on.m, CFG
%       first) is off; else the runs' agents (as trained, without the escalation), their
%       settings, names, labels and the file's SHA-256. Stops when only one of the two holds, or
%       when f is not the file of this trained policy's C2 (monitor, drop threshold, false-alarm
%       threshold, label, form).
%   R = aprime_fresh('fly', ap, PPw, Kw, specs, split, seed, n)   every run on the clean set's
%       world, episodes and frame-draw seed (fly_clean_set in evaluate_policies.m), with the
%       selected monitor and the grid's settings (ap.S on top of the deployed DQN's), the padding
%       of the last batch dropped
%   aprime_fresh('flown', ap, R, n, f)   stops when f exists and R lacks a run of ap or an episode
%   L = aprime_fresh('lines', ap, F)   F: the A' rows of far_report; the block after KPI 6's
%       lines: what the rows are, then the seed mean per penalty and discount factor
%   aprime_fresh('done', ap, F, f)   stops when f exists and KPI 6's rows F lack a row of ap
LABEL = 'pre-registered candidate (D107), validation-scored, not deployed, descriptive';
FILE = 'data/aprime_agents.mat';
out = [];
switch cmd
    case 'load'
        Q = varargin{1}; cfg = []; f = FILE;
        if numel(varargin) >= 2, cfg = varargin{2}; end
        if numel(varargin) >= 3 && ~isempty(varargin{3}), f = varargin{3}; end
        out = load_runs(Q, cfg, f, LABEL);
    case 'fly'
        [ap, PPw, Kw, specs, split, seed, n] = varargin{:};
        PPa = decision_settings(PPw, ap.S);
        out = cell(1, numel(ap.agents));
        for i = 1:numel(ap.agents)
            R = policy_run_set('dqn', PPa, Kw, specs, split, ap.agents{i}, struct(), seed);
            fn = fieldnames(R);
            for j = 1:numel(fn), R.(fn{j}) = R.(fn{j})(:, 1:n); end
            out{i} = R;
        end
    case 'flown'
        [ap, R, n] = varargin{1:3}; f = FILE;
        if numel(varargin) >= 4 && ~isempty(varargin{4}), f = varargin{4}; end
        if isempty(ap) && ~isfile(f), return; end
        ok = ~isempty(ap) && iscell(R) && numel(R) == numel(ap.pol) && ...
            all(cellfun(@(x) isstruct(x) && isfield(x, 's') && numel(x.s) == n, R));
        if ~ok
            error('aprime_fresh:row', ['kpi6_set fresh: %s exists and its runs were not flown on every fresh clean ' ...
                'flight; the fresh set is read once, with the A'' rows'], f);
        end
    case 'lines'
        [ap, F] = varargin{:};
        out = block_lines(ap, F);
    case 'done'
        [ap, F] = varargin{1:2}; f = FILE;
        if numel(varargin) >= 3 && ~isempty(varargin{3}), f = varargin{3}; end
        if isempty(ap) && ~isfile(f), return; end
        if isempty(ap) || isempty(F) || ~all(ismember(ap.lbl, {F.policy}))
            error('aprime_fresh:row', ['kpi6_set fresh: %s exists and KPI 6 on the fresh clean test set lacks its ' ...
                'A'' rows; the fresh set is read once, with them'], f);
        end
    otherwise
        error('aprime_fresh:cmd', 'aprime_fresh: unknown command %s', cmd);
end
end

function ap = load_runs(Q, cfg, f, LABEL)
ap = [];
on = fa_nothreat_on(cfg);
has = isfile(f);
if ~has && ~on, return; end
if ~has
    error('aprime_fresh:absent', ['kpi6_set fresh: C2''s no-threat form is on and %s is absent (C2 writes it); ' ...
        'the fresh set is read once, so its A'' rows could never be added'], f);
end
if ~on
    error('aprime_fresh:switch', ['kpi6_set fresh: %s exists and C2''s no-threat form is off, so its runs are not ' ...
        'this C2''s; the fresh set is read once: remove or explain the file first'], f);
end
L = load(f, 'aprime');
assert(isfield(L, 'aprime') && isstruct(L.aprime), 'aprime_fresh:file', '%s holds no aprime', f);
A = L.aprime;
need = {'label', 'form', 'alarm', 'drop', 'S', 'fa_ebno_thr', 'runs'};
miss = need(~isfield(A, need));
if ~isempty(miss), error('aprime_fresh:file', '%s: aprime lacks %s', f, strjoin(miss, ', ')); end
if ~strcmp(A.label, LABEL) || ~strcmp(A.form, 'nothreat') || isempty(A.runs) || ~(isstruct(A.S) && isscalar(A.S))
    error('aprime_fresh:file', '%s: not the no-threat form''s runs (label, form, runs, settings)', f);
end
ss = Q.seed_summary;
if ~(strcmp(A.alarm, ss.selected_alarm) && isequaln(A.drop, ss.selected_drop) && isequaln(A.fa_ebno_thr, ss.fa_ebno_thr))
    error('aprime_fresh:file', ['%s is not of this trained policy''s C2: monitor %s, drop %g, false-alarm threshold %g ' ...
        'against %s, %g, %g'], f, A.alarm, A.drop, A.fa_ebno_thr, ss.selected_alarm, ss.selected_drop, ss.fa_ebno_thr);
end
n = numel(A.runs);
ag = cell(1, n);
for i = 1:n
    r = A.runs(i);
    if ~(isfield(r, 'nothreat') && isfield(r.nothreat, 'agent') && isfield(r.nothreat.agent, 'dense'))
        error('aprime_fresh:file', '%s: run %d holds no agent in matrix form', f, i);
    end
    ag{i} = r.nothreat.agent;
end
pen = [A.runs.pen]; gam = [A.runs.gamma]; sd = [A.runs.seed];
pol = arrayfun(@(i) sprintf('aprime_%d', i), 1:n, 'UniformOutput', false);
lbl = arrayfun(@(i) sprintf('A'' penalty %d, gamma %.2f, seed %d (%s)', pen(i), gam(i), sd(i), LABEL), 1:n, ...
    'UniformOutput', false);
ap = struct('file', f, 'sha256', kpi6_fresh_marker('sha', f), 'label', LABEL, 'S', A.S, 'pen', pen, 'gamma', gam, ...
    'seed', sd, 'pol', {pol}, 'lbl', {lbl}, 'agents', {ag});
end

function L = block_lines(ap, F)
% What the A' rows are, then per penalty and discount factor the mean count over the seeds and
% its one-sided 95% Clopper-Pearson bound (the count rounded), as train_dqn.m reports them.
L = {sprintf(['  The A'' rows above: the no-threat penalty form''s runs (%s, sha256 %s), %s; each as trained, ' ...
    'without the escalation, with the selected monitor and the grid''s settings, on the same flights and frame ' ...
    'draws; never the deployed policy''s KPI 6'], ap.file, ap.sha256, ap.label)};
for p = unique(ap.pen)
    for g = unique(ap.gamma)
        m = ap.pen == p & ap.gamma == g;
        if ~any(m), continue; end
        k = mean([F(m).k]); n = F(find(m, 1)).n;
        L{end+1} = sprintf('  A'' penalty %d, gamma %.2f, mean of %d seeds: %.1f of %d episodes with >= 1 change, bound %.2f%%', ...
            p, g, sum(m), k, n, 100 * cp_upper(round(k), n)); %#ok<AGROW>
    end
end
end

function u = cp_upper(k, n)
% One-sided 95% Clopper-Pearson upper bound of a binomial proportion.
if k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end
