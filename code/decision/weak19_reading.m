function out = weak19_reading(stage, varargin)
%WEAK19_READING  Side reading of the DQN's decision-time fixes (dqn_fix.m: PP.dqn_harm, PP.dqn_hop;
%   lb_complete.m: PP.lb_more) on a finished tree: chosen on the VALIDATION split, frozen, then read
%   once on a FRESH test set no earlier reading flew (fresh_set_layout.m). Nothing in the tree is
%   overwritten; the fresh pools and two marker copies are new files of it.
%   weak19_reading('val', tree, tag, d124)   validation, once per tree: refused when this checkout's
%       or the tree's validation marker exists, or when the tree already holds the fresh pools;
%       first, every option off, the registered readings the selection leans on are reproduced and
%       any mismatch stops the run before a candidate is read (the agent as selected: held and
%       recovered, seed_summary; the deployed form: clean validation flights with a change,
%       lb.readings, and its false changes and their rate per hour, results/dqn_training.txt;
%       rule_sel: held, recovered and clean flights); then the three steps in order, each on the
%       setting the earlier ones adopted; frozen with the hash of every .m file of this checkout and
%       of the tree's inputs -> results/weak19/<tag>/selection.json, val.mat, weak19_reading.txt,
%       the validation marker last; the selection and the marker are copied into the tree's
%       results/read_once (X.tsel, X.tclaim_val). d124 (optional): the rule fix's frozen
%       selection.json of the same tree; refused when its gate moved the deployed policy off the
%       DQN (then these layers are not deployed)
%   weak19_reading('test', tree, tag)   the single test reading, once per tree: refused without the
%       frozen selection or its copy in the tree (the two equal), on another tree, a second time
%       (this checkout's or the tree's marker), when the code or the inputs changed, or without the
%       fresh pools (data/fresh_test_pools.mat, data/clean_w19_pools.mat; their seeds, detector and
%       link model checked); the deployed DQN's registered rows of evaluate_policies.m's first six
%       sets are reproduced off, exactly, before the marker; then the fresh sets, the deployed DQN
%       off and with the adopted setting, paired -> test.mat, the test section and its registered
%       verdict
%   weak19_reading('test', tree, tag, 'rulerows', d124test)   the same reading, and in the same
%       read of the fresh set the rule rows (none, rule_esc, blind_esc, rule_core, blind_core) off and
%       with the rule fix's adopted setting (R.rr.setting), on the same episodes and frame draws, with
%       the registered confirmation (rr_claims); d124test: the rule fix's test.mat of the same tree
%       (SHA-256 R.rr.d124_sha). Before the marker the rule rows of evaluate_policies.m's first
%       three sets are reproduced, off against the registered rows and on against d124test; any
%       mismatch stops the read. The deployed DQN's part, its files and its numbers are those of the
%       call without the option, which runs the statements above unchanged
%       -> rulerows_test.mat, rulerows_reading.txt beside the selection
%   weak19_reading('amend', tree, tag, base, why)   once, before the test: records that this
%       checkout's code differs from the frozen code only in R.amend_allowed. base: the checkout the
%       selection ran (its code must give the frozen hash, its HEAD R.amend_base_rev); the base
%       copies of the changed files are kept in amend_base/, so the guard derives the frozen hash
%       again from this checkout alone (amend_ok)
%   D = weak19_reading('code_diff', code, base_code)   h = weak19_reading('code_at', code, sub)
%   ok = weak19_reading('amend_ok', A, code, based, from, to)   O = weak19_reading('rr_option', args)
%   C = weak19_reading('rr_claims', I)   P = weak19_reading('rr_ratio', num, den, cl, B, seed)
%   X = weak19_reading('paths', tree, tag)   J = weak19_reading('guard', X)
%   S = weak19_reading('select', T)          A = weak19_reading('adopt', x, y, target, W, prot)
%   P = weak19_reading('ptest', d, cl, alpha, seed)   the paired test of one subgroup
%   V = weak19_reading('verdict', E)         the fresh read's registered verdict from its endpoints
%   R = weak19_reading('reg')                the registered constants
%   Registered selection (fixed before any reading), on the deployed DQN as deployed (its monitor,
%   settings and the link-budget completion) over train_dqn.m's validation episodes (every cell,
%   Eb/N0 and geometry twice, seed 99, frame draws 5000 + b), a validation comb set (the jamming
%   and reactive_jamming cells on every validation flight, the follower on the new channel at the
%   hop and on frequency diversity's second carrier, as evaluate_policies.m's comb set) and the
%   clean validation flights:
%   step 1 dqn_harm: q, rule, fec against off; target: the HARMED recoverable single antenna_fault
%          episodes (no response does not restore them)
%   step 2 dqn_hop: q, rule against the step-1 setting; target: the comb set's recoverable episodes
%   step 3 lb_more: fec, step, fec+step against the step-2 setting; target: the recoverable episodes
%          whose threat holds path_loss (the deployed agent, trained on every combination)
%   A candidate is adopted over the setting in force when
%   (a) on its target, recovered rises: the paired difference above 0 and its one-sided p-value
%       below R.alpha / k, k the step's number of candidates (Bonferroni); the p-value from the
%       cluster bootstrap with at least R.boot_cl clusters, else the exact sign-flip test over the
%       clusters' sums; fewer than R.min_cl clusters: not adopted
%   (b) every threat with at least 10 recoverable validation episodes, and the comb set pooled:
%       recovered falls by no more than 1.0 point, its lower bound by no more than 2.0; step 1 also
%       on the harmed single airframe_shadowing episodes and the harmed combinations holding a
%       lost branch, every later step on each earlier adopted target (with fewer than R.boot_cl
%       clusters the point alone, the bound not read)
%   (c) pooled held and pooled recovered: no lower than -0.5 point, lower bounds no lower than -1.0
%   (d) the clean validation flights with a change: one-sided 95% Clopper-Pearson bound within
%       max(5%, the setting in force's) and the share at most 1 point above it
%   (e) the false changes per hour of flight on them at most R.fph (the registered limit; a point
%       value, not a bound)
%   (f) the delivered payload after onset (dlv_post, the cost of rate_reduce): pooled no lower than
%       -0.5 point, lower bound no lower than -1.0; the comb set as (b)
%   Bounds: cluster bootstrap over the flights (a geometry at an Eb/N0), 2000 draws, fixed seeds.
%   Among the candidates of a step that pass, the highest pooled held; within 0.5 point the larger
%   target gain, then the higher return.
%   Registered verdict of the fresh read: one primary endpoint per adopted step (step 1 the harmed
%   single lost-branch episodes, both classes; step 2 the comb set; step 3 the path-loss family),
%   each a one-sided test of a gain, Holm across the adopted steps at R.alpha; guards: pooled
%   recovered and held lower bounds at least -1.0 point, pooled delivered lower bound at least
%   -1.0 point, the fresh KPI 6 Clopper-Pearson bound at most 5% and at most R.fph false changes per
%   hour. A step is confirmed when its endpoint passes Holm and every guard holds; every other row
%   is descriptive.
switch stage
    case 'val',     stage_val(varargin{:});
    case 'test',    stage_test(varargin{:});
    case 'paths',   out = paths(varargin{:});
    case 'guard',   out = guard(varargin{:});
    case 'select',  out = select(varargin{:});
    case 'adopt',   out = adopt(varargin{:});
    case 'ptest',   out = ptest(varargin{:});
    case 'verdict', out = verdict(varargin{:});
    case 'reg',     out = reg();
    case 'amend',   amend(varargin{:});
    case 'code_diff', out = code_diff(varargin{:});
    case 'code_at', out = code_at(varargin{:});
    case 'amend_ok', out = amend_ok(varargin{:});
    case 'rr_option', out = rr_option(varargin{:});
    case 'rr_claims', out = rr_claims(varargin{:});
    case 'rr_ratio', out = rr_ratio(varargin{:});
    otherwise, error('weak19_reading:stage', 'weak19_reading: unknown stage %s', stage);
end
end

%% ===================== Registered constants =====================
function R = reg()
R.steps = struct('field', {'dqn_harm', 'dqn_hop', 'lb_more'}, 'cand', {{'q', 'rule', 'fec'}, {'q', 'rule'}, ...
    {'fec', 'step', 'fec+step'}}, 'target', {'af_harmed', 'comb', 'path_loss'}, 'primary', {'lost_harmed', 'comb', 'path_loss'});
R.lost = {'antenna_fault', 'airframe_shadowing'};
R.B = 2000; R.bound = 0.05; R.alpha = 0.05; R.min_n = 10;
R.boot_cl = 30;                             % clusters below which a bootstrap bound is too narrow: sign-flip test
R.min_cl = 6;                               % fewest target clusters: 2^-6 is the smallest sign-flip p-value under 0.05 / 3
R.fph = 470;                                % false changes per hour: profile 3's registered limit (C2, dqn_training.txt)
R.thr = struct('a', 0, 'thr_pt', -0.010, 'thr_lb', -0.020, 'pool_pt', -0.005, 'pool_lb', -0.010, 'fa_pts', 0.010, 'tie', 0.005);
R.fresh_guard = struct('pool_lb', -0.010, 'dlv_lb', -0.010);
R.val_seed = 99; R.val_reps = 2; R.frames = 5000; R.clean_seed = 41000;
R.comb_seed = 99101; R.comb_frames = 5600;
R.test_rs = 2027; R.test_seed = 20000; R.test_sets = {'single', 'follower', 'combined', 'unknown', 'clean', 'comb'};
R.fresh_rs = 2091; R.fresh_seed = 300000; R.fresh_sets = {'single', 'follower', 'combined', 'comb'};
R.boot_seed = 1900; R.flip_seed = 1950;
R.amend_allowed = {'decision/weak19_reading.m', 'tests/test_w19_rulerows.m'};   % relative to code/
R.amend_base_rev = 'c689c2177c4c4fc50c171741aae22cc54c6d4a7a';
claims = struct('name', {'esc_recovered', 'core_narrowband', 'core_wideband'}, 'row', {'rule_esc', 'rule_core', 'rule_core'}, ...
    'threat', {'', 'tone_jamming', 'jamming'}, 'seed', {2701, 2702, 2703});
R.rr = struct('tag', 'p3', 'setting', 'keep+st+rate', 'pols', {{'none', 'rule_esc', 'blind_esc', 'rule_core', 'blind_core'}}, ...
    'on', {{'rule_esc', 'blind_esc', 'rule_core', 'blind_core'}}, 'nsets', 3, 'claims', {claims}, ...
    'd124_sha', '9f8f4e79ed4880647a6bbda7ef50dae194e5cf5bc6aa2d67a110fcfd7470d85c', ...
    'seed_g', 2710, 'seed_d', 2720, 'keep', {{'scn', 's', 'r', 'geom', 'recovered', 'held', 'recoverable', ...
    'recoverable_core', 'threat', 'per_post', 'dlv_post', 'gput_post', 'switches', 'ret', 't_rec', 't_rec_det', 't_conf'}});
end

%% ===================== Files =====================
function X = paths(tree, tag)
assert(ischar(tag) && ~isempty(regexp(tag, '^[A-Za-z0-9_]+$', 'once')), 'weak19_reading:tag', ...
    'weak19_reading: the tag is letters, digits and _');
X.tree = tree; X.tag = tag;
X.dir = fullfile(project_root(), 'results', 'weak19', tag);
X.sel = fullfile(X.dir, 'selection.json'); X.val = fullfile(X.dir, 'val.mat');
X.txt = fullfile(X.dir, 'weak19_reading.txt'); X.marker = fullfile(X.dir, 'test_read_started.txt');
X.test = fullfile(X.dir, 'test.mat');
X.amend = fullfile(X.dir, 'amend.json'); X.amend_base = fullfile(X.dir, 'amend_base');
X.rr_txt = fullfile(X.dir, 'rulerows_reading.txt'); X.rr_mat = fullfile(X.dir, 'rulerows_test.mat');
X.claim_val = read_once('claim', 'weak19', 'val', tree); X.claim_test = read_once('claim', 'weak19', 'test', tree);
tr = fullfile(tree, 'results', 'read_once');
X.tclaim_val = fullfile(tr, 'weak19_val.txt'); X.tclaim_test = fullfile(tr, 'weak19_test.txt');
X.tsel = fullfile(tr, 'weak19_selection.json');
X.inputs = cellfun(@(f) fullfile(tree, f), {fullfile('data', 'trained_dqn.mat'), fullfile('data', 'drop_threshold.mat'), ...
    fullfile('results', 'eval_detector_metrics.mat'), fullfile('results', 'dqn_training.txt'), 'profile.json', 'params.mat'}, ...
    'UniformOutput', false);
X.big = cellfun(@(f) fullfile(tree, f), {fullfile('data', 'policy_pools.mat'), fullfile('data', 'clean_val_pools.mat'), ...
    fullfile('results', 'policy_evaluation.mat')}, 'UniformOutput', false);
X.fresh = cellfun(@(f) fullfile(tree, f), {fresh_set_layout(false).out, clean_out()}, 'UniformOutput', false);
end

function f = clean_out()
[~, ~, f] = clean_set_layout(fresh_set_layout(false).clean);
end

function F = fingerprint(X)
F = struct('tree', read_once('tree', X.tree), 'code', read_once('code'), ...
    'inputs', {cellfun(@(f) read_once('file', f), X.inputs, 'UniformOutput', false)}, ...
    'big', {cellfun(@(f) read_once('big', f), X.big, 'UniformOutput', false)});
end

function J = guard(X)
% The test stage's refusals, in order.
J = {};
if ~isfile(X.sel), J{end+1} = 'no frozen selection (run the val stage first)'; return; end
if ~isfile(X.tsel) || ~strcmp(read_once('file', X.tsel), read_once('file', X.sel))
    J{end+1} = 'the tree''s copy of the selection is missing or differs';
end
S = jsondecode(fileread(X.sel));
F = fingerprint(X);
if ~strcmp(S.fingerprint.tree, F.tree), J{end+1} = 'the selection was frozen on another tree'; end
if isfile(X.claim_test) || isfile(X.marker) || isfile(X.tclaim_test), J{end+1} = 'the fresh test set of this tree was read already'; end
if ~strcmp(S.fingerprint.code, F.code) && ~amended(X, S.fingerprint.code, F.code)
    J{end+1} = 'the code differs from the code the selection ran';
end
if ~isequal(cellstr(S.fingerprint.inputs(:))', F.inputs) || ~isequal(cellstr(S.fingerprint.big(:))', F.big)
    J{end+1} = 'the tree''s inputs differ from those the selection read';
end
ad = S.adopted;
if isstruct(ad) && ~isempty(fieldnames(ad)) && ~all(cellfun(@isfile, X.fresh))
    J{end+1} = 'the fresh pools are not built (fresh_set_layout.m)';
end
end

%% ===================== Validation =====================
function stage_val(tree, tag, d124)
if nargin < 3, d124 = ''; end
X = paths(tree, tag); R = reg();
assert(~isfile(X.claim_val) && ~isfile(X.tclaim_val), 'weak19_reading:val_once', ...
    'weak19_reading: a selection was frozen on this tree already (%s or %s): it is chosen once', X.claim_val, X.tclaim_val);
assert(~any(cellfun(@isfile, X.fresh)), 'weak19_reading:fresh_exists', ...
    'weak19_reading: the tree holds the fresh pools already: they are built after the selection, never before');
assert(~isfile(X.sel) && ~isfile(X.val) && ~isfile(X.txt), 'weak19_reading:exists', ...
    'weak19_reading: %s already holds a reading; a reading is never overwritten', X.dir);
D = struct('adopted', '', 'file', d124);
if ~isempty(d124)
    S124 = jsondecode(fileread(d124));
    assert(strcmp(S124.fingerprint.tree, read_once('tree', tree)), 'weak19_reading:d124', ...
        'weak19_reading: the rule fix''s selection belongs to another tree');
    assert(strcmp(S124.deployed_on, S124.deployed_off), 'weak19_reading:d124', ...
        'weak19_reading: with the rule fix the deployed policy is %s: the DQN''s layers are not deployed', S124.deployed_on);
    D.adopted = S124.adopted;
end
F0 = fingerprint(X);
c0 = cd(tree); back = onCleanup(@() cd(c0)); %#ok<NASGU>
t0 = tic;
W = val_world(R);
lines = {sprintf('=== WEAK POINTS 19: VALIDATION (%s, tree %s) ===', tag, tree), sprintf('Generated: %s', datestr(now)), ...
    sprintf(['Validation split only: %d episodes (every cell, Eb/N0 and geometry x%d, seed %d), %d comb episodes, %d ' ...
    'clean validation flights from %.1f dB; deployed policy %s; rule fix of the same tree: %s.'], W.n, R.val_reps, R.val_seed, ...
    W.ncomb, W.ncl, W.ebno_thr, W.Q.deployed, name_txt(D.adopted))};
assert(startsWith(W.Q.deployed, 'dqn'), 'weak19_reading:deployed', 'weak19_reading: the deployed policy %s is no DQN', W.Q.deployed);
% 0. Off: the registered readings, reproduced before any candidate
ss = W.Q.seed_summary;
o = struct('sel', read_dqn(W, struct(), 'selected'), 'dep', read_dqn(W, struct(), 'deployed'), 'rule', read_rule(W));
chk = {'DQN as selected, held', o.sel.held, ss.dqn_held, 1e-9; 'DQN as selected, recovered', o.sel.rec, ss.dqn_recovered, 1e-9; ...
    'rule_sel held', o.rule.held, W.Q.rule_sel.held, 1e-9; 'rule_sel recovered', o.rule.rec, W.Q.rule_sel.rec, 1e-9; ...
    'rule_sel clean flights with a change', sum(o.rule.sw > 0), round(W.Q.rule_sel.fa_w * W.Q.rule_sel.n_w), 0};
if isfield(W.Q, 'lb') && isstruct(W.Q.lb) && W.Q.lb.on && ~field_or(W.Q.dec, 'release_m', false)
    chk(end+1, :) = {'deployed form, clean flights with a change', sum(o.dep.sw > 0), W.Q.lb.readings.clean.k_on, 0};
    chk(end+1, :) = {'deployed form, clean flights', numel(o.dep.sw), W.Q.lb.readings.clean.n, 0};
end
if ~isempty(W.fa_reg)
    chk(end+1, :) = {'deployed form, false changes on the clean flights', sum(o.dep.sw), W.fa_reg.k, 0};
    chk(end+1, :) = {'deployed form, false changes per hour', o.dep.fph, W.fa_reg.per_hour, 0.05 + 1e-9};
end
[ok, cl] = check_rows(chk);
lines = [lines, {'Off, the registered readings reproduced:'}, cl];
if ~ok
    read_once('write', X.txt, [lines, {'NOT REPRODUCED: no candidate is read and nothing is frozen.'}]);
    error('weak19_reading:reproduce', 'weak19_reading: the off readings do not reproduce %s (see %s)', tree, X.txt);
end
lines{end+1} = sprintf(['Deployed form off: held %.1f%%, recovered %.1f%%; recovered: harmed antenna_fault %.1f%% (%d in %d ' ...
    'clusters), harmed airframe_shadowing %.1f%% (%d), harmed combinations with a lost branch %.1f%% (%d), comb %.1f%% (%d), ' ...
    'path-loss family %.1f%% (%d); clean flights with a change %d of %d, %.1f per hour'], ...
    100 * o.dep.held, 100 * o.dep.rec, 100 * tmean(o.dep, W, 'af_harmed'), sum(tmask(o.dep, W, 'af_harmed')), ...
    numel(unique(o.dep.cl(tmask(o.dep, W, 'af_harmed')))), 100 * tmean(o.dep, W, 'as_harmed'), sum(tmask(o.dep, W, 'as_harmed')), ...
    100 * tmean(o.dep, W, 'lost_combo_harmed'), sum(tmask(o.dep, W, 'lost_combo_harmed')), ...
    100 * tmean(o.dep, W, 'comb'), sum(tmask(o.dep, W, 'comb')), 100 * tmean(o.dep, W, 'path_loss'), ...
    sum(tmask(o.dep, W, 'path_loss')), sum(o.dep.sw > 0), numel(o.dep.sw), o.dep.fph);
% 1. The three steps, each on the setting the earlier ones adopted
S = struct(); y = o.dep; Vs = struct('step', {}, 'S', {}, 'names', {}, 'sum', {}); prot = {};
for k = 1:numel(R.steps)
    st = R.steps(k);
    rd = struct('name', {''}, 'x', y);
    for c = st.cand
        Sc = S; Sc.(st.field) = c{1};
        rd(end+1) = struct('name', c{1}, 'x', read_dqn(W, Sc, 'deployed')); %#ok<AGROW>
    end
    Sk = select(struct('read', rd, 'target', st.target, 'W', W, 'prot', {prot}));
    lines = [lines, {'', sprintf('Step %d, %s, against %s:', k, st.field, set_txt(S))}, Sk.lines, ...
        {sprintf('  -> %s', name_txt(rd(Sk.best).name))}]; %#ok<AGROW>
    if Sk.best > 1, S.(st.field) = rd(Sk.best).name; y = rd(Sk.best).x; prot{end+1} = st.target; end %#ok<AGROW>
    Vs(end+1) = struct('step', st.field, 'S', S, 'names', {{rd.name}}, 'sum', {arrayfun(@(r) summ(r.x), rd, 'UniformOutput', false)}); %#ok<AGROW>
end
lines{end+1} = sprintf('Validation done in %.1f min. Selection frozen: %s.', toc(t0) / 60, set_txt(S));
sel = struct('tag', tag, 'tree', tree, 'adopted', S, 'adopted_txt', set_txt(S), 'created', datestr(now, 31), ...
    'fingerprint', F0, 'deployed', W.Q.deployed, 'd124', D);
read_once('save', X.val, struct('Vs', Vs, 'off', summ(o.dep)));
read_once('write', X.txt, lines);
sj = {jsonencode(sel, 'PrettyPrint', true)};
read_once('write', X.sel, sj);
read_once('write', X.tsel, sj);
cv = {sprintf('weak19 validation frozen %s', datestr(now, 31)), ['tree ' F0.tree], ['tag ' tag], ...
    ['code ' F0.code], ['selection ' X.sel], ['adopted ' set_txt(S)]};
read_once('write', X.claim_val, cv);
read_once('write', X.tclaim_val, cv);
fprintf('%s\n', lines{:});
end

function W = val_world(R)
% The pools, agent, monitor inputs and validation episodes as train_dqn.m reads them.
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
K = link_env('tables', PP);
PP.pools(:, :, :, 3:end) = {[]};
Q = load('data/trained_dqn.mat', 'agent', 'H', 'seed_summary', 'deployed', 'rule_sel', 'dec', 'det_id', 'maha_thr', 'lb');
check_det_id(PP, Q, 'weak19_reading');
DM = 'class_drop';
if isfile('data/drop_threshold.mat')
    Dd = load('data/drop_threshold.mat'); PP.drop_db = Dd.drop_db;
    if isfield(Dd, 'drop_alarm') && strcmp(Dd.drop_alarm, 'class_cusum'), DM = Dd.drop_alarm; PP.drop_db = Dd.cusum_db; end
    if isfield(Dd, 'MONP') && isfield(Dd.MONP, 'confirm_drop'), PP.dconf = struct('monitor', {Dd.MONP.monitor}, 'cd', {Dd.MONP.confirm_drop}); end
    if isfield(Dd, 'MONP') && isfield(Dd.MONP, 'lb_accept'), PP.lbacc = struct('monitor', {Dd.MONP.monitor}, 'la', {Dd.MONP.lb_accept}); end
    if isfield(Dd, 'confirm_sweep'), PP.confirm_sweep = Dd.confirm_sweep; end
    if isfield(Dd, 'deg_mode'), PP.deg_mode = Dd.deg_mode; PP.ber_q = Dd.ber_q; end
end
CV = load('data/clean_val_pools.mat', 'CT'); CV = CV.CT;
check_det_id(PP, CV, 'weak19_reading', 'data/clean_val_pools.mat');
et = PP.ebno(1);
if isfile('results/eval_detector_metrics.mat')
    Md = load('results/eval_detector_metrics.mat', 'metrics');
    if isfield(Md.metrics, 'kpi1_threshold_db') && isfinite(Md.metrics.kpi1_threshold_db), et = Md.metrics.kpi1_threshold_db; end
end
H = Q.H; VAL = 2;
spec = val_spec(PP, K, H, VAL, R.val_reps, RandStream('mt19937ar', 'Seed', R.val_seed));
comb = comb_spec(PP, K, H, VAL, R.val_reps, RandStream('mt19937ar', 'Seed', R.comb_seed));
W = struct('PP', PP, 'K', K, 'Q', Q, 'CV', CV, 'H', H, 'spec', {spec}, 'comb', {comb}, 'ebno_thr', et, 'drop_mode', DM, 'R', R);
W.thr = PP.scen(cat_f(spec, 'scn')); W.s = cat_f(spec, 's'); W.n = numel(W.thr);
W.ncomb = sum(cellfun(@(sp) field_or(sp, 'n_valid', numel(sp.scn)), comb));
[~, W.ncl] = clean_wide_specs(PP, CV, et, H.T);
W.fa_reg = registered_fa('results/dqn_training.txt', field_or(Q.dec, 'release_m', false));
end

function v = cat_f(spec, f)
v = cell2mat(cellfun(@(sp) sp.(f)(:)', spec, 'UniformOutput', false));
end

function F = registered_fa(f, relm)
% The deployed form's false changes on the clean validation flights (C2's release step), [] when
% C2's report holds no such line.
F = [];
if ~isfile(f), return; end
t = regexp(fileread(f), ['false changes on the (\d+) clean validation flights: (\d+) without \(([\d.]+) per hour[^)]*\), ' ...
    '(\d+) with the release \(([\d.]+) per hour'], 'tokens', 'once');
if isempty(t), return; end
v = str2double(t);
F = struct('n', v(1), 'k', v(2), 'per_hour', v(3));
if relm, F.k = v(4); F.per_hour = v(5); end
end

function specs = val_spec(PP, K, H, split, reps, rs)
% train_dqn.m's validation episodes (full_val_spec).
C = decision_config();
cells = find(~cellfun(@isempty, PP.pools(:, 1, K.na, split))');
[c, s, r] = flight_triples(cells, K.geo(cells, split), 1:numel(PP.ebno));
c = repmat(c, 1, reps); s = repmat(s, 1, reps); r = repmat(r, 1, reps);
n = numel(c); nb = ceil(n / H.NE);
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*H.NE + 1:min(b*H.NE, n); m = numel(i);
    specs{b} = struct('scn', c(i), 's', s(i), 'r', r(i), 'onset', randi(rs, [3 10], 1, m), ...
        'follow', K.followable(c(i)) & rand(rs, 1, m) < H.p_follow, 'fdelay', randi(rs, C.fdelay, 1, m), ...
        'unk', false(1, m), 'T', H.T);
end
end

function specs = comb_spec(PP, K, H, split, reps, rs)
% evaluate_policies.m's comb set on the given split: the jamming and reactive_jamming cells, the
% follower on every channel we can use.
sg = find(ismember(PP.scen, PP.singles) & ~strcmp(PP.scen, 'none'));
foll = sg(K.followable(sg));
jam = foll(ismember(PP.scen(foll), {'jamming', 'reactive_jamming'}));
specs = policy_episodes(jam, numel(PP.ebno), K.geo(jam, split), reps, true, false, H.NE, H.T, rs, [0 0]);
for b = 1:numel(specs), specs{b}.comb = true(1, numel(specs{b}.scn)); end
end

function x = read_dqn(W, S, form)
% The DQN on the validation episodes, the comb set and the clean validation flights: form
% 'selected' (the agent as selected: no completion, no release, no layer) or 'deployed' (as
% deployed, with the layers of S).
mon = W.Q.dec;
if strcmp(form, 'selected')
    mon.lb_complete = false; mon.release_m = false;
end
for f = fieldnames(S)', mon.(f{1}) = S.(f{1}); end
kind = W.Q.deployed; if strcmp(form, 'selected'), kind = field_or(W.Q.seed_summary, 'selected_kind', kind); end
opt = struct('monitor', mon);
V = dqn_eval_batches(kind, W.PP, W.K, W.spec, W.Q.agent, opt, W.R.frames, 2);
Vc = policy_run_set(kind, W.PP, W.K, W.comb, 2, W.Q.agent, opt, W.R.comb_frames);
x = struct('rec', dqn_recovered(V), 'held', dqn_held(V), 'ret', mean(V.ret), 'recovered', V.recovered, 'heldv', V.held, ...
    'recoverable', V.recoverable, 'threat', V.threat, 'r', V.r, 'cl', 1000 * W.s + V.r, 'dlv', V.dlv_post, ...
    'c_recovered', Vc.recovered, 'c_recoverable', Vc.recoverable & Vc.threat, 'c_cl', Vc.geom, 'c_dlv', Vc.dlv_post);
x.harmed = harmed_of(W.K, cat_f(W.spec, 'scn'), W.s, 2, V.r);
x.sw = clean_changes(W, kind, W.PP, W.Q.agent, opt);
C = decision_config();
Fr = false_change_rate(x.sw, W.H.T, 1:numel(x.sw), C.period_ms);
x.fph = Fr.per_hour;
end

function x = read_rule(W)
% rule_sel (rule + escalation at its own monitor and settings, without the release).
mon = W.Q.rule_sel; if isfield(mon, 'release_m'), mon.release_m = false; end
opt = struct('monitor', mon);
V = dqn_eval_batches('rule_esc', W.PP, W.K, W.spec, [], opt, W.R.frames, 2);
x = struct('rec', dqn_recovered(V), 'held', dqn_held(V), 'sw', clean_changes(W, 'rule_esc', W.PP, [], opt));
end

function sw = clean_changes(W, kind, PP, ag, opt)
% Changes per clean validation flight (train_dqn.m eval_clean_wide).
[PPw, Kw] = clean_world(PP, W.CV);
[specs, n] = clean_wide_specs(PP, W.CV, W.ebno_thr, W.H.T);
sw = [];
for b = 1:numel(specs)
    Rb = rollout_policy(kind, PPw, Kw, specs{b}, 2, ag, opt, W.R.clean_seed + b);
    sw = [sw, Rb.switches]; %#ok<AGROW>
end
sw = sw(1:n);
end

function h = harmed_of(K, scn, s, split, r)
% No response does not restore the geometry (evaluate_policies.m harmed).
ih = sub2ind(size(K.restored), scn, s, K.na + 0 * s, split + 0 * s, r);
h = ~(K.restored(ih) & K.restored_plr(ih));
end

function m = tmask(x, W, target)
% The target and guard episodes among the readings x.
base = x.recoverable & x.threat;
switch target
    case 'af_harmed'
        m = base & x.harmed & strcmp(W.thr, 'antenna_fault');
    case 'as_harmed'
        m = base & x.harmed & strcmp(W.thr, 'airframe_shadowing');
    case 'lost_combo_harmed'
        m = base & x.harmed & holds(W.thr, W.R.lost) & contains(W.thr, '+');
    case 'path_loss'
        m = base & holds(W.thr, {'path_loss'});
    case 'comb'
        m = x.c_recoverable;
    otherwise, error('weak19_reading:target', 'weak19_reading: unknown target %s', target);
end
end

function v = tmean(x, W, target)
m = tmask(x, W, target);
if strcmp(target, 'comb'), v = mean(x.c_recovered(m)); else, v = mean(x.recovered(m)); end
end

function h = holds(thr, comp)
h = cellfun(@(s) any(ismember(strsplit(s, '+'), comp)), thr);
end

%% ===================== Selection =====================
function S = select(T)
% T.read(1) the setting in force, T.read(2:end) the candidates; T.target the step's target; T.W
% the world (threat per episode, registered constants); T.prot the targets adopted before.
R = reg();
n = numel(T.read);
prot = {}; if isfield(T, 'prot'), prot = T.prot; end
S = struct('pass', false(1, n), 'adopt', {cell(1, n)}, 'best', 1, 'lines', {{}});
for k = 2:n
    A = adopt(T.read(k).x, T.read(1).x, T.target, T.W, prot);
    S.adopt{k} = rmfield(A, 'lines'); S.pass(k) = A.pass;
    S.lines = [S.lines, {sprintf('  %s: %s', name_txt(T.read(k).name), ternary(A.pass, 'passes', 'not adopted'))}, A.lines];
end
c = find(S.pass);
if isempty(c), return; end
h = arrayfun(@(k) T.read(k).x.held, c); c = c(h >= max(h) - R.thr.tie);
g = arrayfun(@(k) S.adopt{k}.gain, c); c = c(g >= max(g));
[~, j] = max(arrayfun(@(k) T.read(k).x.ret, c)); S.best = c(j);
end

function A = adopt(x, y, target, W, prot)
% The registered conditions (a)-(f) of candidate x over the setting in force y; prot: the targets
% earlier steps adopted.
if nargin < 5, prot = {}; end
R = reg(); t = R.thr;
thr = W.thr(:)';
m = x.recoverable & y.recoverable & x.threat;
A = struct('pass', false, 'a', false, 'b', true, 'c', false, 'd', false, 'e', false, 'f', false, 'gain', NaN, 'lines', {{}});
k = numel(R.steps(strcmp({R.steps.target}, target)).cand);
al = R.alpha / k;
mt = tmask(x, W, target) & tmask(y, W, target);
[d, cl] = tdiff(x, y, mt, target);
P = ptest(d, cl, al, R.boot_seed + 1);
A.gain = P.mean; A.a = P.ncl >= R.min_cl && P.mean > t.a && P.p < al;
A.lines{end+1} = sprintf('    (a) target %s (n %d, %d clusters, %s), recovered %+.2f points, one-sided p %.4f against %.4f: %s', ...
    target, sum(mt), P.ncl, P.how, 100 * P.mean, P.p, al, ok_txt(A.a));
for u = unique(thr(m), 'stable')
    mu = m & strcmp(thr, u{1});
    if sum(mu) < R.min_n, continue; end
    [p, l] = pdiff(x.recovered, y.recovered, mu, x.cl, R.boot_seed + 2);
    ok = p >= t.thr_pt && l >= t.thr_lb; A.b = A.b && ok;
    if ~ok || p ~= 0
        A.lines{end+1} = sprintf('    (b) %-36s n %5d recovered %+.2f, lower bound %+.2f: %s', u{1}, sum(mu), 100 * p, 100 * l, ok_txt(ok)); %#ok<AGROW>
    end
end
mc = x.c_recoverable & y.c_recoverable;
[p, l] = pdiff(x.c_recovered, y.c_recovered, mc, x.c_cl, R.boot_seed + 3);
ok = isnan(p) || (p >= t.thr_pt && l >= t.thr_lb); A.b = A.b && ok;
A.lines{end+1} = sprintf('    (b) %-36s n %5d recovered %+.2f, lower bound %+.2f: %s', 'comb set', sum(mc), 100 * p, 100 * l, ok_txt(ok));
g = {};
if strcmp(target, 'af_harmed'), g = {'as_harmed', 'lost_combo_harmed'}; end
g = [g, prot(~strcmp(prot, 'comb'))];
for j = 1:numel(g)
    mg = tmask(x, W, g{j}) & tmask(y, W, g{j});
    [ok, ln] = guard_sub(x, y, mg, g{j}, R.boot_seed + 6 + j);
    A.b = A.b && ok; A.lines{end+1} = ln; %#ok<AGROW>
end
[ph, lh] = pdiff(x.heldv, y.heldv, m, x.cl, R.boot_seed + 4); [pr, lr] = pdiff(x.recovered, y.recovered, m, x.cl, R.boot_seed + 5);
A.c = ph >= t.pool_pt && lh >= t.pool_lb && pr >= t.pool_pt && lr >= t.pool_lb;
A.lines{end+1} = sprintf('    (c) pooled held %+.2f (lb %+.2f), recovered %+.2f (lb %+.2f): %s', 100 * ph, 100 * lh, 100 * pr, 100 * lr, ok_txt(A.c));
kx = sum(x.sw > 0); ky = sum(y.sw > 0); nw = numel(x.sw);
if nw > 0 && numel(y.sw) == nw
    ux = cp_upper(kx, nw); uy = cp_upper(ky, nw);
    A.d = ux <= max(R.bound, uy) && (kx - ky) / nw <= t.fa_pts;
    A.lines{end+1} = sprintf('    (d) clean flights with a change %d -> %d of %d, bound %.2f%% -> %.2f%%: %s', ky, kx, nw, 100 * uy, 100 * ux, ok_txt(A.d));
else
    A.lines{end+1} = '    (d) clean flights: not measured';
end
A.e = isfinite(x.fph) && x.fph <= R.fph;
A.lines{end+1} = sprintf('    (e) false changes per hour %.1f -> %.1f (limit %g): %s', y.fph, x.fph, R.fph, ok_txt(A.e));
[pd, ld] = pdiff(x.dlv, y.dlv, m, x.cl, R.boot_seed + 9);
[pc, lc] = pdiff(x.c_dlv, y.c_dlv, mc, x.c_cl, R.boot_seed + 10);
A.f = pd >= t.pool_pt && ld >= t.pool_lb && (isnan(pc) || (pc >= t.thr_pt && lc >= t.thr_lb));
A.lines{end+1} = sprintf('    (f) delivered after onset, pooled %+.2f (lb %+.2f), comb set %+.2f (lb %+.2f): %s', ...
    100 * pd, 100 * ld, 100 * pc, 100 * lc, ok_txt(A.f));
A.pass = A.a && A.b && A.c && A.d && A.e && A.f;
end

function [d, cl] = tdiff(x, y, m, target)
if strcmp(target, 'comb'), d = double(x.c_recovered(m)) - double(y.c_recovered(m)); cl = x.c_cl(m);
else, d = double(x.recovered(m)) - double(y.recovered(m)); cl = x.cl(m); end
end

function [ok, ln] = guard_sub(x, y, m, name, seed)
% A subgroup that must not lose: at least R.boot_cl clusters, point and lower bound as (b); fewer,
% the point alone (no bound read).
R = reg(); t = R.thr;
[d, cl] = tdiff(x, y, m, name);
ncl = numel(unique(cl));
if ncl == 0, ok = true; ln = sprintf('    (b) %-36s n     0: ok', name); return; end
if ncl >= R.boot_cl
    [p, l] = paired_stats('boot', d, cl, R.B, seed);
    ok = p >= t.thr_pt && l >= t.thr_lb;
    ln = sprintf('    (b) %-36s n %5d recovered %+.2f, lower bound %+.2f: %s', name, numel(d), 100 * p, 100 * l, ok_txt(ok));
else
    p = mean(d); ok = p >= t.thr_pt;
    ln = sprintf('    (b) %-36s n %5d recovered %+.2f (%d clusters: the point alone): %s', name, numel(d), 100 * p, ncl, ok_txt(ok));
end
end

function [p, l] = pdiff(a, b, m, cl, seed)
p = NaN; l = NaN;
if ~any(m), return; end
[p, l] = paired_stats('boot', double(a(m)) - double(b(m)), cl(m), reg().B, seed);
end

function P = ptest(d, cl, alpha, seed)
% One-sided test of a gain of the paired differences d (clusters cl): mean, p-value, the
% (1 - alpha) lower bound where read. At least R.boot_cl clusters: cluster bootstrap, p the share
% of resample means at or below 0. Fewer: the sign-flip test of the clusters' sums (under no
% effect each cluster's sum is symmetric about 0; Good 2005, ch. 3), exact on integer sums by
% convolution, else 10^5 random flips from a fixed seed; no bound.
R = reg();
d = double(d(:)); cl = cl(:);
ok = isfinite(d); d = d(ok); cl = cl(ok);
P = struct('mean', NaN, 'p', 1, 'lb', NaN, 'ncl', 0, 'how', 'none');
if isempty(d), return; end
[~, ~, j] = unique(cl);
Sc = accumarray(j, d); P.ncl = numel(Sc); P.mean = mean(d);
if P.ncl >= R.boot_cl
    [~, q] = paired_stats('dist', d, cl, R.B, seed);
    P.p = mean(q <= 0); P.lb = q(max(1, round(alpha * R.B))); P.how = 'bootstrap';
elseif all(abs(Sc - round(Sc)) < 1e-9)
    Sc = abs(round(Sc)); T = sum(Sc); f = zeros(1, 2 * T + 1); f(T + 1) = 1;
    for k = 1:numel(Sc)
        if Sc(k) == 0, continue; end
        g = zeros(size(f)); s = Sc(k);
        g(1 + s:end) = g(1 + s:end) + 0.5 * f(1:end - s);
        g(1:end - s) = g(1:end - s) + 0.5 * f(1 + s:end);
        f = g;
    end
    v = -T:T; obs = round(sum(d));
    P.p = sum(f(v >= obs)); P.how = 'sign-flip, exact';
else
    rs = RandStream('mt19937ar', 'Seed', R.flip_seed + seed);
    nf = 1e5; z = sum(d);
    tz = sum((2 * (rand(rs, numel(Sc), nf) < 0.5) - 1) .* Sc, 1);
    P.p = (1 + sum(tz >= z - 1e-12)) / (1 + nf); P.how = 'sign-flip, 1e5 draws';
end
end

%% ===================== Test (read once, fresh set) =====================
function stage_test(tree, tag, varargin)
RR = rr_option(varargin);
X = paths(tree, tag); R = reg();
J = guard(X);
if ~isempty(J), error('weak19_reading:guard', 'weak19_reading: the test is not read: %s', strjoin(J, '; ')); end
S = jsondecode(fileread(X.sel));
Sa = S.adopted; if isempty(Sa) || ~isstruct(Sa), Sa = struct(); end
if RR.on, RR = rr_check(RR, X, S); end
if isempty(fieldnames(Sa))
    claim_test(X, S, 'nothing adopted: not read', {});
    read_once('write', X.txt, [splitlines(strtrim(fileread(X.txt)))', {'', '=== WEAK POINTS 19: TEST ===', ...
        'No setting was adopted on validation: the fresh set is not read.'}]);
    return
end
c0 = cd(tree); back = onCleanup(@() cd(c0)); %#ok<NASGU>
t0 = tic;
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
Q = load('data/trained_dqn.mat', 'agent', 'agents', 'gammas', 'H', 'seed_summary', 'deployed', 'rule_sel', 'dec', 'det_id', 'maha_thr');
check_det_id(PP, Q, 'weak19_reading');
PP = decision_settings(PP, Q);
K = link_env('tables', PP);
E = load('results/policy_evaluation.mat', 'RES', 'POL', 'set_names');
sel = find(Q.gammas == Q.seed_summary.selected_gamma, 1);
dpn = Q.deployed; if strcmp(dpn, 'dqn'), dpn = sprintf('dqn_g%d', sel); end
[kind, ag, opt0] = policy_setup(dpn, Q, sel, [], [], [], K.na);
if ~isfield(opt0, 'monitor') || ~isstruct(opt0.monitor), opt0.monitor = struct(); end
opt1 = opt0; for f = fieldnames(Sa)', opt1.monitor.(f{1}) = Sa.(f{1}); end
% Off first: the deployed DQN's registered rows of evaluate_policies.m's first six sets
sets = old_sets(PP, K, Q.H.T, R);
assert(isequal(E.set_names(1:numel(sets)), {sets.name}), 'weak19_reading:sets', ...
    'weak19_reading: the registered sets are not %s', strjoin({sets.name}, ', '));
bad = {};
for si = 1:numel(sets)
    R0 = policy_run_set(kind, PP, K, sets(si).spec, 3, ag, opt0, R.test_seed + 1000 * si);
    Rg = E.RES{si, strcmp(E.POL, dpn)};
    if ~(isequaln(R0.recovered, Rg.recovered) && isequaln(R0.held, Rg.held) && isequaln(R0.per_post, Rg.per_post) ...
            && isequaln(R0.switches, Rg.switches))
        bad{end+1} = sets(si).name; %#ok<AGROW>
    end
end
if ~isempty(bad)
    read_once('write', X.txt, [splitlines(strtrim(fileread(X.txt)))', {'', '=== WEAK POINTS 19: TEST ===', ...
        ['Off does not reproduce the deployed DQN''s registered rows (' strjoin(bad, ', ') '): the fresh set is not read.']}]);
    error('weak19_reading:reproduce', 'weak19_reading: off does not reproduce %s', strjoin(bad, ', '));
end
if RR.on, RR = rr_reproduce(RR, X, Q, sel, PP, K, sets, E, R); end
% The fresh pools: checked, then the marker
FL = fresh_set_layout(false);
Lf = load(FL.out, 'FT'); PPf = fresh_splice(PP, Lf.FT); clear Lf
check_fresh_seeds(PPf, FL);
CW = load(clean_out(), 'CT'); CW = CW.CT;
check_det_id(PP, CW, 'weak19_reading', clean_out());
check_clean_seeds(CW);
hf = cellfun(@(f) read_once('file', f), X.fresh, 'UniformOutput', false);
claim_test(X, S, sprintf('read for %s', S.adopted_txt), hf);
if RR.on, rr_mark(X, RR); end
Kf = link_env('tables', PPf);
fs = fresh_sets(PPf, Kf, Q.H.T, R);
RON = cell(numel(fs), 2);
for si = 1:numel(fs)
    RON{si, 1} = policy_run_set(kind, PPf, Kf, fs(si).spec, 3, ag, opt0, R.fresh_seed + 1000 * si);
    RON{si, 2} = policy_run_set(kind, PPf, Kf, fs(si).spec, 3, ag, opt1, R.fresh_seed + 1000 * si);
    fprintf('  fresh set %-9s (%.1f min)\n', fs(si).name, toc(t0) / 60);
end
et = PP.ebno(1);
if isfile('results/eval_detector_metrics.mat')
    Md = load('results/eval_detector_metrics.mat', 'metrics');
    if isfield(Md.metrics, 'kpi1_threshold_db') && isfinite(Md.metrics.kpi1_threshold_db), et = Md.metrics.kpi1_threshold_db; end
end
[PPw, Kw] = clean_world(PP, CW);
[cs, ncs] = clean_wide_specs(PP, CW, et, Q.H.T);
SW = zeros(2, 0);
for b = 1:numel(cs)
    Rb0 = rollout_policy(kind, PPw, Kw, cs{b}, 2, ag, opt0, R.fresh_seed + 500 + b);
    Rb1 = rollout_policy(kind, PPw, Kw, cs{b}, 2, ag, opt1, R.fresh_seed + 500 + b);
    SW = [SW, [Rb0.switches; Rb1.switches]]; %#ok<AGROW>
end
SW = SW(:, 1:ncs);
lines = {'', '=== WEAK POINTS 19: TEST (fresh set, read once) ===', sprintf(['Generated: %s | setting %s | fresh pools ' ...
    'block %d family %d, %d geometries per (cell, Eb/N0) | clean flights %s, %d from %.1f dB'], datestr(now), S.adopted_txt, ...
    PPf.fresh.block, PPf.fresh.fam, PPf.fresh.ngeo, CW.set, ncs, et), ...
    sprintf('Off reproduces the deployed DQN''s registered rows of %s: exact', strjoin({sets.name}, ', '))};
[fl, Ev] = fresh_lines(RON, fs, PPf, Kf, SW, Q.H.T, R, fieldnames(Sa));
lines = [lines, fl];
lines{end+1} = sprintf('Test done in %.1f min.', toc(t0) / 60);
RONs = cellfun(@(r) keep_fields(r), RON, 'UniformOutput', false);
read_once('save', X.test, struct('RONs', {RONs}, 'sets', {{fs.name}}, 'SW', SW, 'adopted', S.adopted_txt, 'fresh_sha', {hf}, ...
    'verdict', Ev));
read_once('write', X.txt, [splitlines(strtrim(fileread(X.txt)))', lines]);
fprintf('%s\n', lines{:});
if RR.on, rr_fresh(RR, X, Q, sel, PPf, Kf, fs, PPw, Kw, cs, ncs, RON(:, 1), dpn, R); end
end

function claim_test(X, S, what, hf)
txt = {sprintf('weak19 test %s %s', what, datestr(now, 31)), ['tree ' S.fingerprint.tree], ['tag ' X.tag], ...
    ['code ' S.fingerprint.code], ['inputs ' strjoin(cellstr(S.fingerprint.inputs(:))', ' ')], ['fresh ' strjoin(hf, ' ')], ...
    ['selection ' X.sel]};
read_once('write', X.claim_test, txt);
read_once('write', X.tclaim_test, txt);
read_once('write', X.marker, txt);
end

function check_fresh_seeds(PPf, FL)
% Every shared fresh flight takes the fresh family's seed of its block (pool_seed.m), and none is
% a flight of any other set (the shadowing flights take fresh_shadow_seed.m's range).
own = pool_seed_owner(PPf.fresh.fam, PPf.fresh.block);
assert(strcmp(own, 'fresh_threat') && PPf.fresh.fam == FL.fam && PPf.fresh.block == FL.block && PPf.fresh.ngeo == FL.ngeo, ...
    'weak19_reading:fresh', 'weak19_reading: the fresh pools are not the registered layout');
sd = PPf.cov{3}.seed;
for s = 1:size(sd, 1)
    sh = sd(s, 1:FL.ngeo); ex = arrayfun(@(r) pool_seed(FL.fam, s, FL.block, r), 1:FL.ngeo);
    assert(isequal(sh, ex), 'weak19_reading:fresh', 'weak19_reading: the shared fresh flights at Eb/N0 %d are not the registered ones', s);
    o = sd(s, FL.ngeo + 1:end); o = o(isfinite(o));
    assert(all(o >= 63000001 & o <= 66839999), 'weak19_reading:fresh', 'weak19_reading: a fresh shadowing flight outside its range');
end
end

function check_clean_seeds(CT)
% The clean flights are clean_set_layout.m's 'w19' flights.
[SP, FAMS] = clean_set_layout('w19');
assert(strcmp(CT.set, 'w19'), 'weak19_reading:clean', 'weak19_reading: the clean pools are not the w19 set');
for s = 1:size(CT.seed, 1)
    ex = arrayfun(@(k) clean_pool_seed(s, SP, k, [], FAMS), 1:CT.n_geom);
    assert(isequal(CT.seed(s, :), ex), 'weak19_reading:clean', 'weak19_reading: the w19 clean flights at Eb/N0 %d are not the registered ones', s);
end
end

function sets = old_sets(PP, K, T, R)
% evaluate_policies.m's first six sets, drawn from its stream in its order.
nS = numel(PP.ebno); NE = 64; REPS = 2; TEST = 3;
sg = find(ismember(PP.scen, PP.singles) & ~strcmp(PP.scen, 'none'));
cb = find(ismember(PP.scen, PP.combos));
G = @(cells) K.geo(cells, TEST);
rs = RandStream('mt19937ar', 'Seed', R.test_rs);
foll = sg(K.followable(sg));
sp = {policy_episodes(sg, nS, G(sg), REPS, false, false, NE, T, rs), ...
    policy_episodes(foll, nS, G(foll), REPS, true, false, NE, T, rs), ...
    policy_episodes(cb, nS, G(cb), REPS, false, false, NE, T, rs), ...
    policy_episodes(sg, nS, G(sg), 1, false, true, NE, T, rs), ...
    policy_episodes(K.clean, nS, G(K.clean), 1, false, false, NE, T, rs)};
jam = foll(ismember(PP.scen(foll), {'jamming', 'reactive_jamming'}));
cm = policy_episodes(jam, nS, G(jam), 1, true, false, NE, T, rs, [0 0]);
for b = 1:numel(cm), cm{b}.comb = true(1, NE); end
sp{end+1} = cm;
sets = struct('name', R.test_sets, 'spec', sp, 'split', TEST);
end

function sets = fresh_sets(PP, K, T, R)
% The fresh set's single, follower, combined and comb sets (evaluate_policies.m's layout, its own
% stream).
nS = numel(PP.ebno); NE = 64; REPS = 2; TEST = 3;
sg = find(ismember(PP.scen, PP.singles) & ~strcmp(PP.scen, 'none'));
cb = find(ismember(PP.scen, PP.combos));
G = @(cells) K.geo(cells, TEST);
rs = RandStream('mt19937ar', 'Seed', R.fresh_rs);
foll = sg(K.followable(sg));
jam = foll(ismember(PP.scen(foll), {'jamming', 'reactive_jamming'}));
sp = {policy_episodes(sg, nS, G(sg), REPS, false, false, NE, T, rs), ...
    policy_episodes(foll, nS, G(foll), REPS, true, false, NE, T, rs), ...
    policy_episodes(cb, nS, G(cb), REPS, false, false, NE, T, rs), ...
    policy_episodes(jam, nS, G(jam), REPS, true, false, NE, T, rs, [0 0])};
for b = 1:numel(sp{4}), sp{4}{b}.comb = true(1, numel(sp{4}{b}.scn)); end
sets = struct('name', R.fresh_sets, 'spec', sp, 'split', TEST);
end

function [lines, Ev] = fresh_lines(RON, fs, PP, K, SW, T, R, adopted)
% The registered verdict first (verdict below), then the descriptive rows: off -> on, paired,
% with the cluster-bootstrap 95% interval of the difference: the threat sets pooled, the harmed
% lost-branch episodes per threat, the path-loss family, tone_jamming+path_loss, every threat, the
% comb set; the clean flights' changes (KPI 6) and false changes per hour.
C = decision_config();
x0 = RON{1, 1}; x1 = RON{1, 2};
for si = 2:3, x0 = cat_struct(x0, RON{si, 1}); x1 = cat_struct(x1, RON{si, 2}); end
thr = PP.scen(x0.scn); m = x0.recoverable & x0.threat;
hm = harmed_of(K, x0.scn, x0.s, 3, x0.r);
ic = find(strcmp({fs.name}, 'comb'));
c0 = RON{ic, 1}; c1 = RON{ic, 2}; mc = c0.recoverable & c0.threat;
n = size(SW, 2);
F0 = false_change_rate(SW(1, :), T, 1:n, C.period_ms); F1 = false_change_rate(SW(2, :), T, 1:n, C.period_ms);
k0 = sum(SW(1, :) > 0); k1 = sum(SW(2, :) > 0);
% Registered endpoints and guards
lost = m & hm & ismember(thr, R.lost);
pl = m & holds(thr, {'path_loss'});
st = R.steps(ismember({R.steps.field}, adopted));
E = struct('step', {st.field}, 'primary', {st.primary}, 'P', []);
for k = 1:numel(st)
    switch st(k).primary
        case 'lost_harmed', E(k).P = ptest(double(x1.recovered(lost)) - double(x0.recovered(lost)), x0.geom(lost), R.alpha, R.boot_seed + 20);
        case 'comb', E(k).P = ptest(double(c1.recovered(mc)) - double(c0.recovered(mc)), c0.geom(mc), R.alpha, R.boot_seed + 21);
        otherwise, E(k).P = ptest(double(x1.recovered(pl)) - double(x0.recovered(pl)), x0.geom(pl), R.alpha, R.boot_seed + 22);
    end
end
[~, gr] = paired_stats('boot', double(x1.recovered(m)) - double(x0.recovered(m)), x0.geom(m), R.B, R.boot_seed + 23);
[~, gh] = paired_stats('boot', double(x1.held(m)) - double(x0.held(m)), x0.geom(m), R.B, R.boot_seed + 24);
[~, gd] = paired_stats('boot', x1.dlv_post(m) - x0.dlv_post(m), x0.geom(m), R.B, R.boot_seed + 25);
G = struct('rec_lb', gr, 'held_lb', gh, 'dlv_lb', gd, 'kpi6', cp_upper(k1, n), 'fph', F1.per_hour);
Ev = verdict(struct('E', E, 'G', G));
lines = [{'Registered verdict (one primary endpoint per adopted step, Holm; guards):'}, Ev.lines];
% Descriptive rows
lines{end+1} = 'Descriptive: recovered among the recoverable (single + follower + combined), off -> on [95% interval of the paired difference]:';
lines{end+1} = row('pooled', x0.recovered, x1.recovered, m, x0.geom, R.boot_seed + 10);
lines{end+1} = row('pooled, held', x0.held, x1.held, m, x0.geom, R.boot_seed + 11);
lines{end+1} = row('pooled, delivered after onset', x0.dlv_post, x1.dlv_post, m, x0.geom, R.boot_seed + 18);
lines{end+1} = row('harmed lost-branch episodes', x0.recovered, x1.recovered, lost, x0.geom, R.boot_seed + 12);
for u = unique(thr(lost), 'stable')
    lines{end+1} = row(['  harmed ' u{1}], x0.recovered, x1.recovered, lost & strcmp(thr, u{1}), x0.geom, R.boot_seed + 13); %#ok<AGROW>
end
lm = m & hm & holds(thr, R.lost) & contains(thr, '+');
lines{end+1} = row('harmed combinations with a lost branch', x0.recovered, x1.recovered, lm, x0.geom, R.boot_seed + 19);
lines{end+1} = row('path-loss family (trained)', x0.recovered, x1.recovered, pl, x0.geom, R.boot_seed + 14);
lines{end+1} = row('  tone_jamming+path_loss', x0.recovered, x1.recovered, m & strcmp(thr, 'tone_jamming+path_loss'), x0.geom, R.boot_seed + 15);
lines{end+1} = 'Per threat:';
for u = unique(thr(m), 'stable')
    lines{end+1} = row(['  ' u{1}], x0.recovered, x1.recovered, m & strcmp(thr, u{1}), x0.geom, R.boot_seed + 16); %#ok<AGROW>
end
lines{end+1} = row('comb set', c0.recovered, c1.recovered, mc, c0.geom, R.boot_seed + 17);
lines{end+1} = row('comb set, delivered after onset', c0.dlv_post, c1.dlv_post, mc, c0.geom, R.boot_seed + 26);
lines{end+1} = sprintf(['KPI 6, fresh clean flights: with a change %d -> %d of %d (one-sided 95%% bound %.2f%% -> %.2f%%, ' ...
    'against %.0f%%); false changes per hour %.1f -> %.1f'], k0, k1, n, 100 * cp_upper(k0, n), 100 * cp_upper(k1, n), ...
    100 * R.bound, F0.per_hour, F1.per_hour);
end

function V = verdict(I)
% I.E(k): step, primary, P (ptest.m's struct); I.G: rec_lb, held_lb, dlv_lb, kpi6, fph. Holm over the
% adopted steps' one-sided p-values at R.alpha (a mean at or below 0 never passes); a step is
% confirmed when it passes and every guard holds.
R = reg(); E = I.E; G = I.G; g = R.fresh_guard;
n = numel(E);
p = arrayfun(@(e) e.P.p, E); p(arrayfun(@(e) ~(e.P.mean > 0), E)) = 1;
[ps, o] = sort(p); hol = false(1, n);
for k = 1:n
    if ps(k) <= R.alpha / (n - k + 1), hol(o(k)) = true; else, break; end
end
gok = [G.rec_lb >= g.pool_lb, G.held_lb >= g.pool_lb, G.dlv_lb >= g.dlv_lb, G.kpi6 <= R.bound, G.fph <= R.fph];
gnm = {'pooled recovered lower bound', 'pooled held lower bound', 'pooled delivered lower bound', 'KPI 6 bound', 'false changes per hour'};
gv = [100 * G.rec_lb, 100 * G.held_lb, 100 * G.dlv_lb, 100 * G.kpi6, G.fph];
glim = [100 * g.pool_lb, 100 * g.pool_lb, 100 * g.dlv_lb, 100 * R.bound, R.fph];
V = struct('step', {{E.step}}, 'p', p, 'holm', hol, 'guards', gok, 'confirmed', hol & all(gok), 'lines', {{}});
for k = 1:n
    V.lines{end+1} = sprintf('  %-9s endpoint %-12s n clusters %3d (%s), gain %+.2f points, one-sided p %.4f: Holm %s', E(k).step, ...
        E(k).primary, E(k).P.ncl, E(k).P.how, 100 * E(k).P.mean, E(k).P.p, ternary(hol(k), 'passes', 'fails'));
end
for j = 1:numel(gok)
    V.lines{end+1} = sprintf('  guard %-30s %8.2f against %8.2f: %s', gnm{j}, gv(j), glim(j), ok_txt(gok(j)));
end
for k = 1:n
    V.lines{end+1} = sprintf('  -> %s: %s', E(k).step, ternary(V.confirmed(k), 'CONFIRMED', 'NOT CONFIRMED'));
end
end

function t = row(name, a0, a1, m, cl, seed)
if ~any(m), t = sprintf('  %-40s n     0', name); return; end
d = double(a1(m)) - double(a0(m));
[~, lo, hi] = boot_cluster(d, ones(1, sum(m)), cl(m), 2000, seed);
t = sprintf('  %-40s n %5d  %5.1f -> %5.1f  [%+.1f, %+.1f]', name, sum(m), 100 * mean(a0(m)), 100 * mean(a1(m)), 100 * lo, 100 * hi);
end

%% ===================== Code amendment =====================
function amend(tree, tag, base, reason)
% Once, while the fresh set is unread: this checkout's code differs from the frozen code only in
% R.amend_allowed. The base checkout must hold the frozen code (its hash, and its HEAD and a clean
% code/ where git answers); the base copies of the changed files are kept in X.amend_base.
X = paths(tree, tag); R = reg();
assert(isfile(X.sel), 'weak19_reading:amend', 'weak19_reading: no frozen selection in %s', X.dir);
assert(~isfile(X.amend), 'weak19_reading:amend', 'weak19_reading: %s exists; the code is amended once', X.amend);
assert(~isfile(X.claim_test) && ~isfile(X.marker) && ~isfile(X.tclaim_test), 'weak19_reading:amend', ...
    'weak19_reading: the fresh test set of this tree was read already');
assert(ischar(reason) && numel(reason) >= 20, 'weak19_reading:amend', 'weak19_reading: an amendment states its reason');
S = jsondecode(fileread(X.sel));
code = fullfile(project_root(), 'code'); bcode = fullfile(base, 'code');
assert(strcmp(code_at(bcode), S.fingerprint.code), 'weak19_reading:amend', ...
    'weak19_reading: the code of %s is not the frozen code', base);
h = code_at(code);
assert(~strcmp(h, S.fingerprint.code), 'weak19_reading:amend', 'weak19_reading: the code is the frozen code; nothing to amend');
[gh, gs] = git_state(base);
assert(strcmp(gh, 'unavailable') || (strcmp(gh, R.amend_base_rev) && isempty(gs)), 'weak19_reading:amend', ...
    'weak19_reading: %s is at %s with code changes [%s], not at %s', base, gh, gs, R.amend_base_rev);
D = code_diff(code, bcode);
bad = setdiff([D.changed, D.added, D.removed], R.amend_allowed);
assert(isempty(D.removed) && isempty(bad), 'weak19_reading:amend', ...
    'weak19_reading: files outside the registered amendment differ (%s; removed: %s)', strjoin(bad, ', '), strjoin(D.removed, ', '));
for k = 1:numel(D.changed)
    t = fullfile(X.amend_base, strrep(D.changed{k}, '/', filesep));
    if ~isfolder(fileparts(t)), mkdir(fileparts(t)); end
    [ok, msg] = copyfile(fullfile(bcode, strrep(D.changed{k}, '/', filesep)), t, 'f');
    assert(ok, 'weak19_reading:amend', 'weak19_reading: cannot copy %s: %s', D.changed{k}, msg);
end
A = struct('tag', tag, 'tree', tree, 'from', S.fingerprint.code, 'to', h, 'base', base, 'base_head', gh, ...
    'base_code_status', gs, 'changed', {D.changed}, 'added', {D.added}, 'reason', reason, ...
    'created', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
assert(amend_ok(A, code, X.amend_base, S.fingerprint.code, h), 'weak19_reading:amend', ...
    'weak19_reading: the base copies do not give back the frozen hash');
read_once('write', X.amend, {jsonencode(A, 'PrettyPrint', true)});
fprintf('Amendment recorded: %s -> %s (changed: %s; added: %s)\n', A.from, A.to, strjoin(D.changed, ', '), strjoin(D.added, ', '));
end

function ok = amended(X, from, to)
% The code differs from the frozen code only by the one recorded amendment.
ok = false;
if ~isfile(X.amend), return; end
ok = amend_ok(jsondecode(fileread(X.amend)), fullfile(project_root(), 'code'), X.amend_base, from, to);
end

function ok = amend_ok(A, code, based, from, to)
% The recorded pair is (from, to), only files of R.amend_allowed differ, the code now gives to, and
% with the added files left out and the changed ones read from based it gives from.
R = reg();
ch = cellstr_of(A.changed); ad = cellstr_of(A.added);
ok = strcmp(A.from, from) && strcmp(A.to, to) && all(ismember([ch, ad], R.amend_allowed));
if ~ok, return; end
ok = strcmp(code_at(code), to) && strcmp(code_at(code, struct('drop', {ad}, 'replace', {ch}, 'from', based)), from);
end

function h = code_at(code, sub)
% SHA-256 of a code folder as read_once('code') computes it; sub.drop: relative paths left out;
% sub.replace: relative paths read from sub.from instead.
if nargin < 2 || ~isstruct(sub), sub = struct(); end
drop = cellstr_of(field_or(sub, 'drop', {})); rep = cellstr_of(field_or(sub, 'replace', {}));
[rel, full] = code_files(code);
keep = ~ismember(rel, drop); rel = rel(keep); full = full(keep);
for k = find(ismember(rel, rep)), full{k} = fullfile(sub.from, strrep(rel{k}, '/', filesep)); end
md = java.security.MessageDigest.getInstance('SHA-256');
for k = 1:numel(rel)
    s = strrep(fileread(full{k}), char(13), '');
    md.update(unicode2native([rel{k} char(0) s char(0)], 'UTF-8'));
end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end

function [rel, full] = code_files(code)
% Every .m file under code, its path relative to code (with /), sorted by that path.
code = regexprep(code, '[\\/]+$', '');
if ispc, code = strrep(code, '/', '\'); end
d = dir(fullfile(code, '**', '*.m'));
full = cellfun(@(p, n) fullfile(p, n), {d.folder}, {d.name}, 'UniformOutput', false);
n = numel(code);
assert(all(strncmpi(full, code, n)), 'weak19_reading:code', 'weak19_reading: a file outside %s', code);
rel = cellfun(@(f) strrep(f(n + 2:end), '\', '/'), full, 'UniformOutput', false);
[rel, o] = sort(rel); full = full(o);
end

function D = code_diff(code, bcode)
% The .m files that differ between code and bcode (line ends removed): changed, added, removed.
[r1, f1] = code_files(code); [r0, f0] = code_files(bcode);
D = struct('changed', {{}}, 'added', {setdiff(r1, r0)}, 'removed', {setdiff(r0, r1)});
for k = find(ismember(r1, r0))
    j = find(strcmp(r0, r1{k}), 1);
    if ~strcmp(strrep(fileread(f1{k}), char(13), ''), strrep(fileread(f0{j}), char(13), '')), D.changed{end+1} = r1{k}; end
end
D.added = reshape(D.added, 1, []); D.removed = reshape(D.removed, 1, []);
end

function [h, s] = git_state(d)
[e1, h] = system(sprintf('git --no-optional-locks -C "%s" rev-parse HEAD', d));
[e2, s] = system(sprintf('git --no-optional-locks -C "%s" status --porcelain -- code', d));
if e1 ~= 0, h = 'unavailable'; else, h = strtrim(h); end
if e2 ~= 0, s = 'unavailable'; else, s = strtrim(s); end
end

function c = cellstr_of(v)
if isempty(v), c = {}; elseif ischar(v), c = {v}; else, c = reshape(cellstr(v), 1, []); end
end

%% ===================== Rule rows on the fresh set =====================
function O = rr_option(args)
% No option, or 'rulerows' and the rule fix's test.mat of the same tree.
O = struct('on', false, 'd124', '', 'd124_sha', '', 'lines', {{}});
if isempty(args), return; end
assert(numel(args) == 2 && (ischar(args{1}) || isstring(args{1})) && strcmpi(args{1}, 'rulerows') && ...
    (ischar(args{2}) || isstring(args{2})), 'weak19_reading:option', ...
    'weak19_reading: the test stage takes no option, or ''rulerows'' and the rule fix''s test.mat');
O.on = true; O.d124 = char(args{2});
end

function RR = rr_check(RR, X, S)
% Before anything is read: the registered tree, an adopted setting (the fresh set built), the rule
% fix's adopted setting and its test reading's file.
R = reg();
assert(strcmp(X.tag, R.rr.tag), 'weak19_reading:rulerows', 'weak19_reading: the rule rows are registered for %s only', R.rr.tag);
assert(isstruct(S.adopted) && ~isempty(fieldnames(S.adopted)), 'weak19_reading:rulerows', ...
    'weak19_reading: nothing adopted, the fresh set is not built: no rule rows');
assert(isfield(S, 'd124') && isstruct(S.d124) && strcmp(S.d124.adopted, R.rr.setting), 'weak19_reading:rulerows', ...
    'weak19_reading: the rule fix of this selection is not %s', R.rr.setting);
if isempty(regexp(RR.d124, '^([A-Za-z]:[\\/]|[\\/])', 'once')), RR.d124 = fullfile(pwd, RR.d124); end
RR.d124_sha = read_once('file', RR.d124);
assert(strcmp(RR.d124_sha, R.rr.d124_sha), 'weak19_reading:rulerows', ...
    'weak19_reading: %s is not the rule fix''s registered test reading', RR.d124);
assert(~isfile(X.rr_mat), 'weak19_reading:rulerows', 'weak19_reading: %s exists; a reading is never overwritten', X.rr_mat);
end

function RR = rr_reproduce(RR, X, Q, sel, PP, K, sets, E, R)
% Before the marker: the rule rows on evaluate_policies.m's first R.rr.nsets sets, off against the
% registered rows and with the setting against the rule fix's test reading of the same sets.
D = load(RR.d124, 'RONs', 'pols');
assert(all(ismember(R.rr.pols, E.POL)) && all(ismember(R.rr.on, D.pols)), 'weak19_reading:rulerows', ...
    'weak19_reading: a rule row is missing from the registered or the rule fix''s rows');
bad = {}; t0 = tic;
for si = 1:R.rr.nsets
    for p = R.rr.pols
        [kind, ag, opt] = policy_setup(p{1}, Q, sel, [], [], [], K.na);
        R0 = policy_run_set(kind, PP, K, sets(si).spec, sets(si).split, ag, opt, R.test_seed + 1000 * si);
        if ~same_rows(R0, E.RES{si, strcmp(E.POL, p{1})}), bad{end+1} = sprintf('%s off on %s', p{1}, sets(si).name); end %#ok<AGROW>
        if ismember(p{1}, R.rr.on)
            R1 = policy_run_set(kind, PP, K, sets(si).spec, sets(si).split, ag, rr_on(opt, R.rr.setting), R.test_seed + 1000 * si);
            if ~same_rows(R1, D.RONs{si, strcmp(D.pols, p{1})}), bad{end+1} = sprintf('%s on on %s', p{1}, sets(si).name); end %#ok<AGROW>
        end
    end
    fprintf('  rule rows reproduced, set %-9s (%.1f min)\n', sets(si).name, toc(t0) / 60);
end
head = {'', '=== RULE ROWS ON THE FRESH SET ===', sprintf('Reproduction %s, %.1f min:', datestr(now), toc(t0) / 60)};
if ~isempty(bad)
    rr_append(X, [head, {['NOT REPRODUCED (' strjoin(bad, ', ') '): the fresh set is not read.']}]);
    error('weak19_reading:rr_reproduce', 'weak19_reading: the rule rows do not reproduce: %s', strjoin(bad, ', '));
end
RR.lines = [head, {sprintf(['Off reproduces the registered rows and %s reproduces the rule fix''s test rows (%s) on %s: ' ...
    'exact'], R.rr.setting, strjoin(R.rr.pols, ', '), strjoin({sets(1:R.rr.nsets).name}, ', '))}];
end

function rr_mark(X, RR)
% The marker also names the rule rows read in the same read of the fresh set.
for f = {X.claim_test, X.tclaim_test, X.marker}
    read_once('write', f{1}, [splitlines(strtrim(fileread(f{1})))', {sprintf('rulerows %s, rule fix test reading %s', ...
        reg().rr.setting, RR.d124_sha)}]);
end
end

function rr_fresh(RR, X, Q, sel, PPf, Kf, fs, PPw, Kw, cs, ncs, Rd, dpn, R)
% The rule rows on the fresh single, follower and combined sets and on the fresh clean flights, off
% and with the setting, at the deployed DQN's frame draws; the registered confirmation, then the
% descriptive rows.
t0 = tic; P = R.rr.pols; nP = numel(P); ns = R.rr.nsets; C = decision_config();
F0 = cell(ns, nP); F1 = F0;
for si = 1:ns
    sd = R.fresh_seed + 1000 * si;
    for pk = 1:nP
        [kind, ag, opt] = policy_setup(P{pk}, Q, sel, [], [], [], Kf.na);
        F0{si, pk} = rr_keep(policy_run_set(kind, PPf, Kf, fs(si).spec, fs(si).split, ag, opt, sd));
        F1{si, pk} = F0{si, pk};
        if ismember(P{pk}, R.rr.on)
            F1{si, pk} = rr_keep(policy_run_set(kind, PPf, Kf, fs(si).spec, fs(si).split, ag, rr_on(opt, R.rr.setting), sd));
        end
    end
    fprintf('  rule rows, fresh set %-9s (%.1f min)\n', fs(si).name, toc(t0) / 60);
end
SW = struct();
for p = R.rr.on
    [kind, ag, opt] = policy_setup(p{1}, Q, sel, [], [], [], Kf.na);
    s = zeros(2, 0);
    for b = 1:numel(cs)
        r0 = rollout_policy(kind, PPw, Kw, cs{b}, 2, ag, opt, R.fresh_seed + 500 + b);
        r1 = rollout_policy(kind, PPw, Kw, cs{b}, 2, ag, rr_on(opt, R.rr.setting), R.fresh_seed + 500 + b);
        s = [s, [r0.switches; r1.switches]]; %#ok<AGROW>
    end
    SW.(p{1}) = s(:, 1:ncs);
end
x0 = struct(); x1 = struct();
for pk = 1:nP, x0.(P{pk}) = cat_cells(F0(:, pk)); x1.(P{pk}) = cat_cells(F1(:, pk)); end
Cl = rr_claims(struct('x0', x0, 'x1', x1, 'scen', {PPf.scen}, 'SW', SW));
lines = {sprintf('Fresh read %s | setting %s | rule fix test reading %s | fresh sets %s | clean flights %d', datestr(now), ...
    R.rr.setting, RR.d124_sha, strjoin({fs(1:ns).name}, ', '), ncs)};
lines = [lines, Cl.lines];
% Descriptive
thr = PPf.scen(x0.none.scn); m = x0.none.recoverable & x0.none.threat; g = x0.none.geom;
lines{end+1} = 'Descriptive: recovered and held among the recoverable (single + follower + combined), off -> on [95% interval of the paired difference]:';
for pk = 2:nP
    lines{end+1} = row([P{pk} ', recovered'], x0.(P{pk}).recovered, x1.(P{pk}).recovered, m, g, R.rr.seed_d + pk); %#ok<AGROW>
    lines{end+1} = row([P{pk} ', held'], x0.(P{pk}).held, x1.(P{pk}).held, m, g, R.rr.seed_d + 10 + pk); %#ok<AGROW>
end
for p = {'rule_esc', 'rule_core'}
    lines{end+1} = sprintf('%s, recovered per threat:', p{1}); %#ok<AGROW>
    for u = unique(thr(m), 'stable')
        lines{end+1} = row(['  ' u{1}], x0.(p{1}).recovered, x1.(p{1}).recovered, m & strcmp(thr, u{1}), g, R.rr.seed_d + 20); %#ok<AGROW>
    end
end
lines{end+1} = 'Fresh clean flights (system level): flights with a change, one-sided 95% bound, false changes per hour, off -> on:';
for p = R.rr.on
    s = SW.(p{1}); n = size(s, 2); k0 = sum(s(1, :) > 0); k1 = sum(s(2, :) > 0);
    G0 = false_change_rate(s(1, :), Q.H.T, 1:n, C.period_ms); G1 = false_change_rate(s(2, :), Q.H.T, 1:n, C.period_ms);
    lines{end+1} = sprintf('  %-12s %d -> %d of %d (%.2f%% -> %.2f%%; bound %.2f%% -> %.2f%%); %.1f -> %.1f per hour', p{1}, k0, k1, n, ...
        100 * k0 / n, 100 * k1 / n, 100 * cp_upper(k0, n), 100 * cp_upper(k1, n), G0.per_hour, G1.per_hour); %#ok<AGROW>
end
L = load('results/policy_evaluation.mat', 'POL', 'LBL');
POL = [P, {dpn}]; LBL = POL;
for k = 1:numel(POL), j = find(strcmp(L.POL, POL{k}), 1); if ~isempty(j), LBL{k} = L.LBL{j}; end, end
dq = cat_cells(cellfun(@rr_keep, Rd(1:ns), 'UniformOutput', false));
A0 = [cellfun(@(p) x0.(p), P, 'UniformOutput', false), {dq}];
A1 = [cellfun(@(p) x1.(p), P, 'UniformOutput', false), {dq}];
pay = payload_rate(C);
[LK0, l0] = lect_kpis(A0, POL, LBL, numel(POL), PPf.scen, pay, C.period_ms);
[LK1, l1] = lect_kpis(A1, POL, LBL, numel(POL), PPf.scen, pay, C.period_ms);
lines = [lines, {'', 'Lecturer KPIs on the fresh set, rule rows off (descriptive):'}, l0, ...
    {'', sprintf('Lecturer KPIs on the fresh set, rule rows with %s (descriptive):', R.rr.setting)}, l1];
lines{end+1} = sprintf('Rule rows done in %.1f min.', toc(t0) / 60);
read_once('save', X.rr_mat, struct('F0', {F0}, 'F1', {F1}, 'SW', SW, 'pols', {P}, 'sets', {{fs(1:ns).name}}, ...
    'setting', R.rr.setting, 'd124_sha', RR.d124_sha, 'claims', rmfield(Cl, 'lines'), 'LK0', LK0, 'LK1', LK1));
rr_append(X, [RR.lines, lines]);
fprintf('%s\n', lines{:});
end

function C = rr_claims(I)
% The registered confirmation of the rule rows. I.x0, I.x1: per policy of R.rr.pols the pooled
% episodes off and with the setting (the same episodes and frames); I.scen: the cell names; I.SW:
% per rule row the clean flights' changes (row 1 off, row 2 on).
% Claims (R.rr.claims): rule_esc's recovered among the recoverable rises; rule_core's PER reduction
% against no response rises, narrowband (tone_jamming) and wideband (jamming), on the recoverable
% episodes of the core action set. Each one-sided by the cluster bootstrap over flights, p the share
% of resample gains at or below 0 (fewer than R.boot_cl clusters: not read, p = 1); Holm across the
% claims at R.alpha. A claim is confirmed when it passes Holm and every guard of its row holds:
% rule_esc (b) every threat with at least R.min_n episodes, recovered no lower than -1.0 point,
% lower bound -2.0; (c) pooled held and recovered no lower than -0.5 point, lower bounds -1.0; (d)
% the clean flights with a change within max(5%, off's) one-sided Clopper-Pearson bound and at most
% 1 point above off's share. rule_core (e) pooled held as (c); (d).
R = reg(); t = R.thr; c = R.rr.claims; nc = numel(c); s = R.rr.seed_g;
z = I.x0.none;
nm = reshape(I.scen(z.scn), 1, []);
m = z.recoverable & z.threat; mc = z.recoverable_core & z.threat; cl = z.geom;
E = struct('name', {c.name}, 'row', {c.row}, 'n', 0, 'off', NaN, 'on', NaN, 'P', []);
for k = 1:nc
    a0 = I.x0.(c(k).row); a1 = I.x1.(c(k).row);
    if isempty(c(k).threat)
        E(k).P = rr_mean(double(a1.recovered(m)) - double(a0.recovered(m)), cl(m), c(k).seed);
        E(k).n = sum(m); E(k).off = mean(a0.recovered(m)); E(k).on = mean(a1.recovered(m));
    else
        ref = z.per_post;
        ok = mc & strcmp(nm, c(k).threat) & isfinite(a0.per_post) & isfinite(a1.per_post) & isfinite(ref);
        E(k).P = rr_ratio(a0.per_post(ok) - a1.per_post(ok), ref(ok), cl(ok), R.B, c(k).seed);
        E(k).n = sum(ok); E(k).off = 1 - sum(a0.per_post(ok)) / sum(ref(ok)); E(k).on = 1 - sum(a1.per_post(ok)) / sum(ref(ok));
    end
    if E(k).P.ncl < R.boot_cl
        E(k).P.p = 1; E(k).P.how = sprintf('%d clusters, fewer than %d: not read', E(k).P.ncl, R.boot_cl);
    end
end
p = arrayfun(@(e) e.P.p, E); p(arrayfun(@(e) ~(e.P.mean > 0), E)) = 1;
[ps, o] = sort(p); hol = false(1, nc);
for k = 1:nc
    if ps(k) <= R.alpha / (nc - k + 1), hol(o(k)) = true; else, break; end
end
% Guards of rule_esc
y0 = I.x0.rule_esc; y1 = I.x1.rule_esc;
[ph, lh] = pdiff(y1.held, y0.held, m, cl, s + 1); [pr, lr] = pdiff(y1.recovered, y0.recovered, m, cl, s + 2);
gc = ph >= t.pool_pt && lh >= t.pool_lb && pr >= t.pool_pt && lr >= t.pool_lb;
gb = true; lb_ = {};
for u = unique(nm(m), 'stable')
    mu = m & strcmp(nm, u{1});
    if sum(mu) < R.min_n, continue; end
    [pu, lu] = pdiff(y1.recovered, y0.recovered, mu, cl, s + 3);
    oku = pu >= t.thr_pt && lu >= t.thr_lb; gb = gb && oku;
    if ~oku, lb_{end+1} = sprintf('    (b) %-36s n %5d recovered %+.2f, lower bound %+.2f: FAILS', u{1}, sum(mu), 100 * pu, 100 * lu); end %#ok<AGROW>
end
[gde, lde] = clean_ok(I.SW.rule_esc, 'rule_esc');
% Guards of rule_core
[pc, lc] = pdiff(I.x1.rule_core.held, I.x0.rule_core.held, m, cl, s + 4);
ge = pc >= t.pool_pt && lc >= t.pool_lb;
[gdc, ldc] = clean_ok(I.SW.rule_core, 'rule_core');
G = struct('rule_esc', struct('b', gb, 'c', gc, 'd', gde), 'rule_core', struct('e', ge, 'd', gdc));
conf = hol & arrayfun(@(e) all(cell2mat(struct2cell(G.(e.row)))), E);
L = {sprintf(['Registered confirmation (%d claims, one-sided, Holm at %.2f; a claim is confirmed when it passes Holm and ' ...
    'every guard of its row holds):'], nc, R.alpha)};
for k = 1:nc
    if isempty(c(k).threat), what = sprintf('%s, recovered among the recoverable', c(k).row);
    else, what = sprintf('%s, PER reduction vs no response, %s', c(k).row, c(k).threat); end
    L{end+1} = sprintf(['  %-15s %-52s n %5d, %3d clusters: off %.1f%% -> on %.1f%%, gain %+.2f points, one-sided 95%% lower ' ...
        'bound %+.2f, p %.4f (%s): Holm %s'], E(k).name, what, E(k).n, E(k).P.ncl, 100 * E(k).off, 100 * E(k).on, ...
        100 * E(k).P.mean, 100 * E(k).P.lb, p(k), E(k).P.how, ternary(hol(k), 'passes', 'fails')); %#ok<AGROW>
end
L{end+1} = sprintf('  guards of rule_esc: (b) every threat with at least %d episodes: %s', R.min_n, ok_txt(gb));
L = [L, lb_];
L{end+1} = sprintf('    (c) pooled held %+.2f (lb %+.2f), recovered %+.2f (lb %+.2f): %s', 100 * ph, 100 * lh, 100 * pr, 100 * lr, ok_txt(gc));
L{end+1} = lde;
L{end+1} = sprintf('  guards of rule_core: (e) pooled held %+.2f (lb %+.2f): %s', 100 * pc, 100 * lc, ok_txt(ge));
L{end+1} = ldc;
for k = 1:nc, L{end+1} = sprintf('  -> %s: %s', E(k).name, ternary(conf(k), 'CONFIRMED', 'NOT CONFIRMED')); end %#ok<AGROW>
C = struct('claims', {E}, 'p', p, 'holm', hol, 'guards', G, 'confirmed', conf, 'lines', {L});
end

function P = rr_mean(d, cl, seed)
% Mean of the paired differences d with the cluster bootstrap's one-sided p and 95% lower bound.
R = reg();
[mu, q] = paired_stats('dist', d, cl, R.B, seed);
P = struct('mean', mu, 'p', 1, 'lb', NaN, 'ncl', numel(unique(cl(isfinite(d)))), 'how', 'bootstrap');
if ~isempty(q), P.p = mean(q <= 0); P.lb = q(max(1, round(R.alpha * R.B))); end
end

function P = rr_ratio(num, den, cl, B, seed)
% sum(num) / sum(den) of paired per-episode values, the episodes of a flight resampled together
% (boot_cluster.m's draws): p the share of resample ratios at or below 0, lb the one-sided 95%
% lower bound.
P = struct('mean', NaN, 'p', 1, 'lb', NaN, 'ncl', 0, 'how', 'bootstrap');
num = double(num(:)); den = double(den(:)); cl = cl(:);
ok = isfinite(num) & isfinite(den); num = num(ok); den = den(ok); cl = cl(ok);
if isempty(num) || sum(den) == 0, return; end
[~, ~, j] = unique(cl);
Sn = accumarray(j, num); Sd = accumarray(j, den);
P.mean = sum(Sn) / sum(Sd); P.ncl = numel(Sn);
if P.ncl < 2, return; end
rs = RandStream('mt19937ar', 'Seed', seed);
idx = randi(rs, P.ncl, P.ncl, B);
q = sort(sum(Sn(idx), 1) ./ max(sum(Sd(idx), 1), eps));
P.p = mean(q <= 0); P.lb = q(max(1, round(0.05 * B)));
end

function [ok, ln] = clean_ok(s, name)
% The rule fix's clean-flight condition on one row: row 1 off, row 2 on.
R = reg(); n = size(s, 2); k0 = sum(s(1, :) > 0); k1 = sum(s(2, :) > 0);
u0 = cp_upper(k0, n); u1 = cp_upper(k1, n);
ok = n > 0 && u1 <= max(R.bound, u0) && (k1 - k0) / n <= R.thr.fa_pts;
ln = sprintf(['    (d) %s, clean flights with a change %d -> %d of %d, one-sided bound %.2f%% -> %.2f%% (limit %.2f%%), ' ...
    'share %+.2f points (limit %+.1f): %s'], name, k0, k1, n, 100 * u0, 100 * u1, 100 * max(R.bound, u0), ...
    100 * (k1 - k0) / n, 100 * R.thr.fa_pts, ok_txt(ok));
end

function opt = rr_on(opt, s)
if ~isfield(opt, 'monitor') || ~isstruct(opt.monitor), opt.monitor = struct(); end
opt.monitor.rule_fix = s;
end

function r = rr_keep(R)
f = intersect(fieldnames(R), reg().rr.keep);
r = struct(); for i = 1:numel(f), r.(f{i}) = R.(f{i}); end
end

function ok = same_rows(a, b)
ok = isequaln(a.recovered, b.recovered) && isequaln(a.held, b.held) && isequaln(a.per_post, b.per_post) ...
    && isequaln(a.switches, b.switches);
end

function R = cat_cells(c)
R = c{1}; for i = 2:numel(c), R = cat_struct(R, c{i}); end
end

function rr_append(X, lines)
prev = {}; if isfile(X.rr_txt), prev = splitlines(strtrim(fileread(X.rr_txt)))'; end
read_once('write', X.rr_txt, [prev, lines]);
end

function r = payload_rate(C)
r = NaN;
if ~isfile('params.mat'), return; end
p = load('params.mat').params;
cyc = C.period_ms / 1000; if isfield(p, 'cycle_s'), cyc = p.cycle_s; end
r = p.bits_per_frame / cyc;
end

%% ===================== Helpers =====================
function [ok, lines] = check_rows(chk)
ok = true; lines = {};
for i = 1:size(chk, 1)
    e = isfinite(chk{i, 3}) && abs(chk{i, 2} - chk{i, 3}) <= chk{i, 4};
    ok = ok && e;
    lines{end+1} = sprintf('  %-55s %12.6g registered %12.6g: %s', chk{i, 1}, chk{i, 2}, chk{i, 3}, ternary(e, 'reproduced', 'NOT REPRODUCED')); %#ok<AGROW>
end
end

function R = cat_struct(R, Rb)
f = fieldnames(R);
for i = 1:numel(f), R.(f{i}) = [R.(f{i}), Rb.(f{i})]; end
end

function r = keep_fields(R)
f = intersect(fieldnames(R), {'scn', 's', 'r', 'geom', 'recovered', 'held', 'recoverable', 'threat', 'per_post', 'dlv_post', ...
    'switches', 'ret', 't_rec'});
r = struct(); for i = 1:numel(f), r.(f{i}) = R.(f{i}); end
end

function x = summ(x)
x = struct('held', x.held, 'rec', x.rec, 'ret', x.ret, 'fa', sum(x.sw > 0), 'n', numel(x.sw), 'fph', x.fph);
end

function t = set_txt(S)
if isempty(fieldnames(S)), t = 'off (the deployed DQN as registered)'; return; end
f = fieldnames(S);
t = strjoin(cellfun(@(n) sprintf('%s=%s', n, S.(n)), f, 'UniformOutput', false), ', ');
end

function u = cp_upper(k, n)
if n == 0, u = NaN; elseif k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

function v = field_or(S, n, d)
v = d; if isstruct(S) && isfield(S, n) && ~isempty(S.(n)), v = S.(n); end
end

function t = name_txt(n)
if isempty(n), t = 'off'; else, t = n; end
end

function t = ok_txt(c)
t = ternary(c, 'ok', 'FAILS');
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
