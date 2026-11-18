function out = weak19_reading(stage, varargin)
%WEAK19_READING  Side reading of the DQN's decision-time fixes (dqn_fix.m: PP.dqn_harm, PP.dqn_hop;
%   lb_complete.m: PP.lb_more) on a finished tree: chosen on the VALIDATION split, frozen, then read
%   once on a FRESH test set no earlier reading flew (fresh_set_layout.m). Nothing in the tree is
%   overwritten; the fresh pools are new files of its data folder.
%   weak19_reading('val', tree, tag, d124)   validation, once per tree: first, every option off, the
%       registered readings the selection leans on are reproduced and any mismatch stops the run
%       before a candidate is read (the agent as selected: held and recovered, seed_summary; the
%       deployed form: clean validation flights with a change, lb.readings, and its false changes
%       and their rate per hour, results/dqn_training.txt; rule_sel: held, recovered and clean
%       flights); then the three steps in order, each on the setting the earlier ones adopted;
%       frozen with the hash of every .m file of this checkout and of the tree's inputs ->
%       results/weak19/<tag>/selection.json, val.mat, weak19_reading.txt, and the validation marker
%       last. d124 (optional): the rule fix's frozen selection.json of the same tree; refused when
%       its gate moved the deployed policy off the DQN (then these layers are not deployed)
%   weak19_reading('test', tree, tag)   the single test reading, once per tree: refused without the
%       frozen selection, on another tree, a second time, when the code or the inputs changed, or
%       without the fresh pools (data/fresh_test_pools.mat, data/clean_w19_pools.mat; their seeds,
%       detector and link model checked); the deployed DQN's registered rows of evaluate_policies.m's
%       first six sets are reproduced off, exactly, before the marker; then the fresh sets, the
%       deployed DQN off and with the adopted setting, paired -> test.mat, the test section
%   X = weak19_reading('paths', tree, tag)   J = weak19_reading('guard', X)
%   S = weak19_reading('select', T)          A = weak19_reading('adopt', x, y, target, W)
%   R = weak19_reading('reg')                the registered constants
%   Registered selection (fixed before any reading), on the deployed DQN as deployed (its monitor,
%   settings and the link-budget completion) over train_dqn.m's validation episodes (every cell,
%   Eb/N0 and geometry twice, seed 99, frame draws 5000 + b), a validation comb set (the jamming
%   and reactive_jamming cells on every validation flight, the follower on the new channel at the
%   hop and on frequency diversity's second carrier, as evaluate_policies.m's comb set) and the
%   clean validation flights:
%   step 1 dqn_harm: q, rule, fec against off; target: the HARMED recoverable lost-branch episodes
%          (no response does not restore them; antenna_fault, airframe_shadowing and every
%          combination holding one)
%   step 2 dqn_hop: q, rule against the step-1 setting; target: the comb set's recoverable episodes
%   step 3 lb_more: fec, step, fec+step against the step-2 setting; target: the recoverable episodes
%          whose threat holds path_loss
%   A candidate is adopted over the setting in force when
%   (a) on its target, recovered rises: the paired difference and its one-sided 95% lower bound
%       above 0
%   (b) every threat with at least 10 recoverable validation episodes, and the comb set pooled:
%       recovered falls by no more than 1.0 point, its lower bound by no more than 2.0
%   (c) pooled held and pooled recovered: no lower than -0.5 point, lower bounds no lower than -1.0
%   (d) the clean validation flights with a change: one-sided 95% Clopper-Pearson bound within
%       max(5%, the setting in force's) and the share at most 1 point above it
%   (e) the false changes per hour of flight on them at most R.fph (the registered limit)
%   Bounds: cluster bootstrap over the flights (a geometry at an Eb/N0), 2000 draws, fixed seeds.
%   Among the candidates of a step that pass, the highest pooled held; within 0.5 point the larger
%   target gain, then the higher return.
switch stage
    case 'val',    stage_val(varargin{:});
    case 'test',   stage_test(varargin{:});
    case 'paths',  out = paths(varargin{:});
    case 'guard',  out = guard(varargin{:});
    case 'select', out = select(varargin{:});
    case 'adopt',  out = adopt(varargin{:});
    case 'reg',    out = reg();
    otherwise, error('weak19_reading:stage', 'weak19_reading: unknown stage %s', stage);
end
end

%% ===================== Registered constants =====================
function R = reg()
R.steps = struct('field', {'dqn_harm', 'dqn_hop', 'lb_more'}, 'cand', {{'q', 'rule', 'fec'}, {'q', 'rule'}, ...
    {'fec', 'step', 'fec+step'}}, 'target', {'lost_harmed', 'comb', 'path_loss'});
R.lost = {'antenna_fault', 'airframe_shadowing'};
R.B = 2000; R.bound = 0.05; R.min_n = 10;
R.fph = 470;                                % false changes per hour: profile 3's registered limit (C2, dqn_training.txt)
R.thr = struct('a', 0, 'thr_pt', -0.010, 'thr_lb', -0.020, 'pool_pt', -0.005, 'pool_lb', -0.010, 'fa_pts', 0.010, 'tie', 0.005);
R.val_seed = 99; R.val_reps = 2; R.frames = 5000; R.clean_seed = 41000;
R.comb_seed = 99101; R.comb_frames = 5600;
R.test_rs = 2027; R.test_seed = 20000; R.test_sets = {'single', 'follower', 'combined', 'unknown', 'clean', 'comb'};
R.fresh_rs = 2091; R.fresh_seed = 91000; R.fresh_sets = {'single', 'follower', 'combined', 'comb'};
R.boot_seed = 1900;
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
X.claim_val = read_once('claim', 'weak19', 'val', tree); X.claim_test = read_once('claim', 'weak19', 'test', tree);
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
S = jsondecode(fileread(X.sel));
F = fingerprint(X);
if ~strcmp(S.fingerprint.tree, F.tree), J{end+1} = 'the selection was frozen on another tree'; end
if isfile(X.claim_test) || isfile(X.marker), J{end+1} = 'the fresh test set of this tree was read already'; end
if ~strcmp(S.fingerprint.code, F.code), J{end+1} = 'the code differs from the code the selection ran'; end
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
assert(~isfile(X.claim_val), 'weak19_reading:val_once', ...
    'weak19_reading: a selection was frozen on this tree already (%s): it is chosen once', X.claim_val);
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
lines{end+1} = sprintf(['Deployed form off: held %.1f%%, recovered %.1f%%, harmed lost-branch recovered %.1f%% (%d), comb ' ...
    'recovered %.1f%% (%d), path-loss family recovered %.1f%% (%d), clean flights with a change %d of %d, %.1f per hour'], ...
    100 * o.dep.held, 100 * o.dep.rec, 100 * tmean(o.dep, W, 'lost_harmed'), sum(tmask(o.dep, W, 'lost_harmed')), ...
    100 * tmean(o.dep, W, 'comb'), sum(tmask(o.dep, W, 'comb')), 100 * tmean(o.dep, W, 'path_loss'), ...
    sum(tmask(o.dep, W, 'path_loss')), sum(o.dep.sw > 0), numel(o.dep.sw), o.dep.fph);
% 1. The three steps, each on the setting the earlier ones adopted
S = struct(); y = o.dep; Vs = struct('step', {}, 'S', {}, 'names', {}, 'sum', {});
for k = 1:numel(R.steps)
    st = R.steps(k);
    rd = struct('name', {''}, 'x', y);
    for c = st.cand
        Sc = S; Sc.(st.field) = c{1};
        rd(end+1) = struct('name', c{1}, 'x', read_dqn(W, Sc, 'deployed')); %#ok<AGROW>
    end
    Sk = select(struct('read', rd, 'target', st.target, 'W', W));
    lines = [lines, {'', sprintf('Step %d, %s, against %s:', k, st.field, set_txt(S))}, Sk.lines, ...
        {sprintf('  -> %s', name_txt(rd(Sk.best).name))}]; %#ok<AGROW>
    if Sk.best > 1, S.(st.field) = rd(Sk.best).name; y = rd(Sk.best).x; end
    Vs(end+1) = struct('step', st.field, 'S', S, 'names', {{rd.name}}, 'sum', {arrayfun(@(r) summ(r.x), rd, 'UniformOutput', false)}); %#ok<AGROW>
end
lines{end+1} = sprintf('Validation done in %.1f min. Selection frozen: %s.', toc(t0) / 60, set_txt(S));
sel = struct('tag', tag, 'tree', tree, 'adopted', S, 'adopted_txt', set_txt(S), 'created', datestr(now, 31), ...
    'fingerprint', F0, 'deployed', W.Q.deployed, 'd124', D);
read_once('save', X.val, struct('Vs', Vs, 'off', summ(o.dep)));
read_once('write', X.txt, lines);
read_once('write', X.sel, {jsonencode(sel, 'PrettyPrint', true)});
read_once('write', X.claim_val, {sprintf('weak19 validation frozen %s', datestr(now, 31)), ['tree ' F0.tree], ['tag ' tag], ...
    ['code ' F0.code], ['selection ' X.sel], ['adopted ' set_txt(S)]});
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
    'recoverable', V.recoverable, 'threat', V.threat, 'r', V.r, 'cl', 1000 * W.s + V.r, ...
    'c_recovered', Vc.recovered, 'c_recoverable', Vc.recoverable & Vc.threat, 'c_cl', Vc.geom);
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
% The target episodes of a step among the readings x.
switch target
    case 'lost_harmed'
        m = x.recoverable & x.threat & x.harmed & holds(W.thr, W.R.lost);
    case 'path_loss'
        m = x.recoverable & x.threat & holds(W.thr, {'path_loss'});
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
% the world (threat per episode, registered constants).
R = reg();
n = numel(T.read);
S = struct('pass', false(1, n), 'adopt', {cell(1, n)}, 'best', 1, 'lines', {{}});
for k = 2:n
    A = adopt(T.read(k).x, T.read(1).x, T.target, T.W);
    S.adopt{k} = rmfield(A, 'lines'); S.pass(k) = A.pass;
    S.lines = [S.lines, {sprintf('  %s: %s', name_txt(T.read(k).name), ternary(A.pass, 'passes', 'not adopted'))}, A.lines];
end
c = find(S.pass);
if isempty(c), return; end
h = arrayfun(@(k) T.read(k).x.held, c); c = c(h >= max(h) - R.thr.tie);
g = arrayfun(@(k) S.adopt{k}.gain, c); c = c(g >= max(g));
[~, j] = max(arrayfun(@(k) T.read(k).x.ret, c)); S.best = c(j);
end

function A = adopt(x, y, target, W)
% The registered conditions (a)-(e) of candidate x over the setting in force y.
R = reg(); t = R.thr;
thr = W.thr(:)';
m = x.recoverable & y.recoverable & x.threat;
A = struct('pass', false, 'a', false, 'b', true, 'c', false, 'd', false, 'e', false, 'gain', NaN, 'lines', {{}});
mt = tmask(x, W, target) & tmask(y, W, target);
if strcmp(target, 'comb')
    [pa, la] = pdiff(x.c_recovered, y.c_recovered, mt, x.c_cl, R.boot_seed + 1);
else
    [pa, la] = pdiff(x.recovered, y.recovered, mt, x.cl, R.boot_seed + 1);
end
A.gain = pa; A.a = pa > t.a && la > t.a;
A.lines{end+1} = sprintf('    (a) target %s (n %d), recovered %+.2f points, lower bound %+.2f: %s', target, sum(mt), 100 * pa, 100 * la, ok_txt(A.a));
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
A.pass = A.a && A.b && A.c && A.d && A.e;
end

function [p, l] = pdiff(a, b, m, cl, seed)
p = NaN; l = NaN;
if ~any(m), return; end
[p, l] = paired_stats('boot', double(a(m)) - double(b(m)), cl(m), reg().B, seed);
end

%% ===================== Test (read once, fresh set) =====================
function stage_test(tree, tag)
X = paths(tree, tag); R = reg();
J = guard(X);
if ~isempty(J), error('weak19_reading:guard', 'weak19_reading: the test is not read: %s', strjoin(J, '; ')); end
S = jsondecode(fileread(X.sel));
Sa = S.adopted; if isempty(Sa) || ~isstruct(Sa), Sa = struct(); end
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
% The fresh pools: checked, then the marker
FL = fresh_set_layout(false);
Lf = load(FL.out, 'FT'); PPf = fresh_splice(PP, Lf.FT); clear Lf
check_fresh_seeds(PPf, FL);
CW = load(clean_out(), 'CT'); CW = CW.CT;
check_det_id(PP, CW, 'weak19_reading', clean_out());
check_clean_seeds(CW);
hf = cellfun(@(f) read_once('file', f), X.fresh, 'UniformOutput', false);
claim_test(X, S, sprintf('read for %s', S.adopted_txt), hf);
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
lines = [lines, fresh_lines(RON, fs, PPf, Kf, SW, Q.H.T, R)];
lines{end+1} = sprintf('Test done in %.1f min.', toc(t0) / 60);
RONs = cellfun(@(r) keep_fields(r), RON, 'UniformOutput', false);
read_once('save', X.test, struct('RONs', {RONs}, 'sets', {{fs.name}}, 'SW', SW, 'adopted', S.adopted_txt, 'fresh_sha', {hf}));
read_once('write', X.txt, [splitlines(strtrim(fileread(X.txt)))', lines]);
fprintf('%s\n', lines{:});
end

function claim_test(X, S, what, hf)
txt = {sprintf('weak19 test %s %s', what, datestr(now, 31)), ['tree ' S.fingerprint.tree], ['tag ' X.tag], ...
    ['code ' S.fingerprint.code], ['inputs ' strjoin(cellstr(S.fingerprint.inputs(:))', ' ')], ['fresh ' strjoin(hf, ' ')], ...
    ['selection ' X.sel]};
read_once('write', X.claim_test, txt);
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

function lines = fresh_lines(RON, fs, PP, K, SW, T, R)
% Off -> on, paired, with the cluster-bootstrap 95% interval of the difference: the threat sets
% pooled, the harmed lost-branch episodes per threat, the path-loss family, tone_jamming+path_loss,
% every threat, the comb set; the clean flights' changes (KPI 6) and false changes per hour.
C = decision_config();
x0 = RON{1, 1}; x1 = RON{1, 2};
for si = 2:3, x0 = cat_struct(x0, RON{si, 1}); x1 = cat_struct(x1, RON{si, 2}); end
thr = PP.scen(x0.scn); m = x0.recoverable & x0.threat;
hm = harmed_of(K, x0.scn, x0.s, 3, x0.r);
lines = {'Recovered among the recoverable (single + follower + combined), off -> on [95% interval of the paired difference]:'};
lines{end+1} = row('pooled', x0.recovered, x1.recovered, m, x0.geom, R.boot_seed + 10);
lines{end+1} = row('pooled, held', x0.held, x1.held, m, x0.geom, R.boot_seed + 11);
lost = m & hm & holds(thr, R.lost);
lines{end+1} = row('harmed lost-branch episodes', x0.recovered, x1.recovered, lost, x0.geom, R.boot_seed + 12);
for u = unique(thr(lost), 'stable')
    lines{end+1} = row(['  harmed ' u{1}], x0.recovered, x1.recovered, lost & strcmp(thr, u{1}), x0.geom, R.boot_seed + 13); %#ok<AGROW>
end
pl = m & holds(thr, {'path_loss'});
lines{end+1} = row('path-loss family', x0.recovered, x1.recovered, pl, x0.geom, R.boot_seed + 14);
lines{end+1} = row('  tone_jamming+path_loss', x0.recovered, x1.recovered, m & strcmp(thr, 'tone_jamming+path_loss'), x0.geom, R.boot_seed + 15);
lines{end+1} = 'Per threat:';
for u = unique(thr(m), 'stable')
    lines{end+1} = row(['  ' u{1}], x0.recovered, x1.recovered, m & strcmp(thr, u{1}), x0.geom, R.boot_seed + 16); %#ok<AGROW>
end
ic = find(strcmp({fs.name}, 'comb'));
c0 = RON{ic, 1}; c1 = RON{ic, 2}; mc = c0.recoverable & c0.threat;
lines{end+1} = row('comb set', c0.recovered, c1.recovered, mc, c0.geom, R.boot_seed + 17);
n = size(SW, 2);
F0 = false_change_rate(SW(1, :), T, 1:n, C.period_ms); F1 = false_change_rate(SW(2, :), T, 1:n, C.period_ms);
k0 = sum(SW(1, :) > 0); k1 = sum(SW(2, :) > 0);
lines{end+1} = sprintf(['KPI 6, fresh clean flights: with a change %d -> %d of %d (one-sided 95%% bound %.2f%% -> %.2f%%, ' ...
    'against %.0f%%); false changes per hour %.1f -> %.1f'], k0, k1, n, 100 * cp_upper(k0, n), 100 * cp_upper(k1, n), ...
    100 * R.bound, F0.per_hour, F1.per_hour);
end

function t = row(name, a0, a1, m, cl, seed)
if ~any(m), t = sprintf('  %-40s n     0', name); return; end
d = double(a1(m)) - double(a0(m));
[~, lo, hi] = boot_cluster(d, ones(1, sum(m)), cl(m), 2000, seed);
t = sprintf('  %-40s n %5d  %5.1f -> %5.1f  [%+.1f, %+.1f]', name, sum(m), 100 * mean(a0(m)), 100 * mean(a1(m)), 100 * lo, 100 * hi);
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
f = intersect(fieldnames(R), {'scn', 's', 'r', 'geom', 'recovered', 'held', 'recoverable', 'threat', 'per_post', 'switches', 'ret', 't_rec'});
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
