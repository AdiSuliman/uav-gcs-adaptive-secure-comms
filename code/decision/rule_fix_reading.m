function out = rule_fix_reading(stage, varargin)
%RULE_FIX_READING  Side reading of the rule's layered answers (PP.rule_fix, rule_fix.m) on a
%   finished tree's frame pools: the candidates are scored on the VALIDATION split, the
%   selection is frozen, and only then is the test split read, once, for the setting adopted.
%   Nothing is written into the tree; no file of this reading is ever overwritten.
%   rule_fix_reading('val', tree, tag)    validation, once per tree: first, with the option off,
%       every registered reading the selection leans on is reproduced and any mismatch stops the
%       run before a candidate is read: rule_sel's held, recovered and clean-flight changes
%       (trained_dqn.mat), the gate's rule (seed_summary), the core rule at C2's reference monitor
%       (the baseline of (e), results/dqn_training.txt), rule + escalation at every monitor and drop
%       threshold of C2's grid (the same file, 0.1-point print) and choose_deployed.m's verdict
%       (Q.deployed); then the candidates, the selection, the gate with the setting adopted; frozen
%       with the hash of every .m file of this checkout and of the tree's inputs ->
%       results/rule_fix/<tag>/selection.json, val.mat, rule_fix_reading.txt, each written whole
%       (read_once.m), and the tree's validation marker last
%   rule_fix_reading('test', tree, tag)   the single test reading, once per tree whatever the tag:
%       refused without the frozen selection, on another tree, a second time, or when the code or
%       the inputs changed; every registered rule row of evaluate_policies.m's first five sets is
%       reproduced with the option off before the marker is set (any mismatch stops); nothing
%       adopted: the test is not read -> test.mat, the test section of rule_fix_reading.txt
%   X = rule_fix_reading('paths', tree, tag)   the files of a reading
%   T = rule_fix_reading('registered', f, rs)   the registered rule rows of a dqn_training.txt
%   J = rule_fix_reading('guard', X)      the test stage's refusals in order ({} none)
%   F = rule_fix_reading('fingerprint', X)   the hashes the selection is frozen with
%   S = rule_fix_reading('select', R)     the registered selection over validation readings R
%   A = rule_fix_reading('adopt', x, y, fam, cx, cy, thr)   one candidate x against the setting
%       in force y (readings of rule_sel), cx and cy the core rule's; fam the target threats, thr
%       the threat of every episode
%   tree: a finished tree (data/policy_pools.mat, data/trained_dqn.mat, data/clean_val_pools.mat,
%   data/drop_threshold.mat, results/eval_detector_metrics.mat, results/policy_evaluation.mat);
%   it is read from its folder, as every stage reads its inputs. tag: the reading's name (p1, p3).
%   Registered selection (fixed before any reading):
%   step 1, the in-channel answers: keep+st, keep+st+rate, keep+st+match against off; step 2, the
%   lost-branch answer: the step-1 setting with fec against it. A candidate is adopted over the
%   setting in force when, on rule + escalation at its own monitor (rule_sel) over the validation
%   episodes of train_dqn.m (every cell, Eb/N0 and geometry twice, seed 99; frame draws 5000 + b),
%   (a) on the target threats (step 1: jamming, reactive_jamming, spoofing, tone_jamming,
%       benign_interference and every combination holding one; step 2: antenna_fault,
%       airframe_shadowing and every combination holding one), held recovery rises: the paired
%       difference and its one-sided 95% lower bound above 0
%   (b) every threat with at least 10 episodes: recovered falls by no more than 1.0 point, and its
%       one-sided 95% lower bound by no more than 2.0
%   (c) pooled held and pooled recovered: no lower than -0.5 point, lower bound no lower than -1.0
%   (d) the clean validation flights with a change: one-sided 95% Clopper-Pearson bound within
%       max(5%, the setting in force's) and the share at most 1 point above it
%   (e) the core rule (rule + escalation on the core action set at C2's reference monitor and the
%       rule's settings, as C2 read it): pooled held no lower than -0.5 point, lower bound no lower
%       than -1.0
%   Bounds: cluster bootstrap over the flights (a geometry at an Eb/N0), 2000 draws, fixed
%   seeds. Among the candidates of a step that pass, the highest pooled held; within 0.5 point
%   the higher pooled recovered, then the higher return.
switch stage
    case 'val',    stage_val(varargin{:});
    case 'test',   stage_test(varargin{:});
    case 'paths',  out = paths(varargin{:});
    case 'guard',  out = guard(varargin{:});
    case 'fingerprint', out = fingerprint(varargin{:});
    case 'select', out = select(varargin{:});
    case 'adopt',  out = adopt(varargin{:});
    case 'registered', out = registered_txt(varargin{:});
    otherwise, error('rule_fix_reading:stage', 'rule_fix_reading: unknown stage %s', stage);
end
end

%% ===================== Registered constants =====================
function R = reg()
R.cand = {'keep+st', 'keep+st+rate', 'keep+st+match'};
R.step2 = 'fec';
R.fam1 = {'jamming', 'reactive_jamming', 'spoofing', 'tone_jamming', 'benign_interference'};
R.fam2 = {'antenna_fault', 'airframe_shadowing'};
R.B = 2000; R.bound = 0.05; R.min_n = 10;
R.thr = struct('a', 0, 'thr_pt', -0.010, 'thr_lb', -0.020, 'pool_pt', -0.005, 'pool_lb', -0.010, 'fa_pts', 0.010, ...
    'tie', 0.005);
R.val_seed = 99; R.val_reps = 2; R.frames = 5000; R.clean_seed = 41000;
R.test_rs = 2027; R.test_seed = 20000; R.test_sets = {'single', 'follower', 'combined', 'unknown', 'clean'};
end

%% ===================== Files =====================
function X = paths(tree, tag)
assert(ischar(tag) && ~isempty(regexp(tag, '^[A-Za-z0-9_]+$', 'once')), 'rule_fix_reading:tag', ...
    'rule_fix_reading: the tag is letters, digits and _');
X.tree = tree; X.tag = tag;
X.dir = fullfile(project_root(), 'results', 'rule_fix', tag);
X.sel = fullfile(X.dir, 'selection.json'); X.val = fullfile(X.dir, 'val.mat');
X.txt = fullfile(X.dir, 'rule_fix_reading.txt'); X.marker = fullfile(X.dir, 'test_read_started.txt');
X.test = fullfile(X.dir, 'test.mat');
X.claim_val = read_once('claim', 'rule_fix', 'val', tree); X.claim_test = read_once('claim', 'rule_fix', 'test', tree);
X.inputs = cellfun(@(f) fullfile(tree, f), {fullfile('data', 'trained_dqn.mat'), fullfile('data', 'drop_threshold.mat'), ...
    fullfile('results', 'eval_detector_metrics.mat'), fullfile('results', 'dqn_training.txt'), 'profile.json', 'params.mat'}, ...
    'UniformOutput', false);
X.big = cellfun(@(f) fullfile(tree, f), {fullfile('data', 'policy_pools.mat'), fullfile('data', 'clean_val_pools.mat'), ...
    fullfile('results', 'policy_evaluation.mat')}, 'UniformOutput', false);
end

function F = fingerprint(X)
% Every .m file of this checkout's code, the tree's small inputs (SHA-256), its large ones (size, date).
F = struct('tree', read_once('tree', X.tree), 'code', read_once('code'), ...
    'inputs', {cellfun(@(f) read_once('file', f), X.inputs, 'UniformOutput', false)}, ...
    'big', {cellfun(@(f) read_once('big', f), X.big, 'UniformOutput', false)});
end

function J = guard(X)
% The test stage's refusals, in order: no frozen selection, another tree, the tree's test split read
% already (whatever the tag), the code or the tree's inputs not those the selection was frozen with.
J = {};
if ~isfile(X.sel), J{end+1} = 'no frozen selection (run the val stage first)'; return; end
S = jsondecode(fileread(X.sel));
F = fingerprint(X);
if ~strcmp(S.fingerprint.tree, F.tree), J{end+1} = 'the selection was frozen on another tree'; end
if isfile(X.claim_test) || isfile(X.marker), J{end+1} = 'the test split of this tree was read already'; end
if ~strcmp(S.fingerprint.code, F.code), J{end+1} = 'the code differs from the code the selection ran'; end
if ~isequal(cellstr(S.fingerprint.inputs(:))', F.inputs) || ~isequal(cellstr(S.fingerprint.big(:))', F.big)
    J{end+1} = 'the tree''s inputs differ from those the selection read';
end
end

%% ===================== Validation =====================
function stage_val(tree, tag)
X = paths(tree, tag); R = reg();
assert(~isfile(X.claim_val), 'rule_fix_reading:val_once', ...
    'rule_fix_reading: a selection was frozen on this tree already (%s): it is chosen once', X.claim_val);
assert(~isfile(X.sel) && ~isfile(X.val) && ~isfile(X.txt), 'rule_fix_reading:exists', ...
    'rule_fix_reading: %s already holds a reading; a reading is never overwritten', X.dir);
F0 = fingerprint(X);
c0 = cd(tree); back = onCleanup(@() cd(c0)); %#ok<NASGU>
t0 = tic;
W = val_world(R);
lines = {sprintf('=== RULE FIX: VALIDATION (%s, tree %s) ===', tag, tree), sprintf('Generated: %s', datestr(now)), ...
    sprintf(['Validation split only: %d episodes (every cell, Eb/N0 and geometry x%d, seed %d), %d clean validation ' ...
    'flights from %.1f dB.'], W.n, R.val_reps, R.val_seed, W.ncl, W.ebno_thr)};
% 0. Off: every registered reading the selection leans on, reproduced before any candidate
o = struct();
o.sel = read_pol(W, 'rule_sel', ''); o.dec = read_pol(W, 'rule_dec', ''); o.core = read_pol(W, 'core_ref', '');
o.dqn = read_pol(W, 'dqn_dep', '');
rs = W.Q.rule_sel; ss = W.Q.seed_summary; T = W.reg;
chk = {'rule_sel held', o.sel.held, rs.held, 1e-9; 'rule_sel recovered', o.sel.rec, rs.rec, 1e-9; ...
    'rule_sel clean flights with a change', sum(o.sel.sw > 0), round(rs.fa_w * rs.n_w), 0; ...
    'rule_sel clean flights', numel(o.sel.sw), rs.n_w, 0; ...
    'rule + escalation at the deployed settings, held', o.dec.held, field_or(ss, 'rule_held', NaN), 1e-9; ...
    'rule + escalation at the deployed settings, recovered', o.dec.rec, field_or(ss, 'rule_recovered', NaN), 1e-9; ...
    'core rule at the reference monitor, held [%]', 100 * o.core.held, T.core.held, 0.05 + 1e-9; ...
    'core rule at the reference monitor, recovered [%]', 100 * o.core.rec, T.core.rec, 0.05 + 1e-9};
if ~isnan(T.core.k), chk(end+1, :) = {'core rule clean flights with a change', sum(o.core.sw > 0), T.core.k, 0}; end
[G0, gl] = gate_grid(W, o, '');
chk = [chk; gl];
chk(end+1, :) = {sprintf('deployed policy (%s)', W.Q.deployed), double(strcmp(G0.dep, W.Q.deployed)), 1, 0};
[ok, cl] = check_rows(chk);
lines = [lines, {'Off, the registered readings reproduced (registered files: trained_dqn.mat, dqn_training.txt):'}, cl];
lines{end+1} = sprintf('Deployed DQN (%s) held %.4f (registered %.4f), clean flights with a change %d of %d (descriptive)', ...
    W.Q.deployed, o.dqn.held, field_or(ss, 'dqn_held', NaN), sum(o.dqn.sw > 0), numel(o.dqn.sw));
if ~ok
    read_once('write', X.txt, [lines, {'NOT REPRODUCED: no candidate is read and nothing is frozen.'}]);
    error('rule_fix_reading:reproduce', 'rule_fix_reading: the off readings do not reproduce %s (see %s)', tree, X.txt);
end
% 1. Step 1, then step 2
Rd = struct('name', {''}, 'sel', o.sel, 'core', o.core);
for c = R.cand, Rd(end+1) = struct('name', c{1}, 'sel', read_pol(W, 'rule_sel', c{1}), 'core', read_pol(W, 'core_ref', c{1})); end %#ok<AGROW>
S1 = select(struct('read', Rd, 'fam', {R.fam1}, 'thr', {W.thr}));
s1 = Rd(S1.best).name;
n2 = rule_fix('parse', strjoin([{s1}, {R.step2}], '+')).name; if isempty(s1), n2 = R.step2; end
R2 = [Rd(S1.best), struct('name', n2, 'sel', read_pol(W, 'rule_sel', n2), 'core', read_pol(W, 'core_ref', n2))];
S2 = select(struct('read', R2, 'fam', {R.fam2}, 'thr', {W.thr}));
adopted = R2(S2.best).name;
lines = [lines, {'', 'Step 1, in-channel answers, against off:'}, S1.lines, {sprintf('  -> %s', name_txt(s1)), '', ...
    sprintf('Step 2, lost-branch answer, %s against %s:', n2, name_txt(s1))}, S2.lines, {sprintf('  -> %s', name_txt(adopted)), ''}];
% 2. With a setting adopted: the side rows and the gate of choose_deployed.m re-read
G = struct('dep', W.Q.deployed, 'lines', {{}});
side = struct();
if ~isempty(adopted)
    for k = {'rule_dec', 'blind_dec', 'blind_core_dec', 'core_dec'}
        x0 = read_pol(W, k{1}, ''); if strcmp(k{1}, 'rule_dec'), x0 = o.dec; end
        side.(k{1}) = [summ(x0), summ(read_pol(W, k{1}, adopted))];
        lines{end+1} = sprintf('  %-16s held %.1f%% -> %.1f%%, recovered %.1f%% -> %.1f%% (side row, not a condition)', k{1}, ...
            100 * side.(k{1})(1).held, 100 * side.(k{1})(2).held, 100 * side.(k{1})(1).rec, 100 * side.(k{1})(2).rec); %#ok<AGROW>
    end
    G = gate_grid(W, o, adopted, side.rule_dec(2).held);
    lines = [lines, {''}, G.lines, {sprintf('  with the setting adopted the deployed policy %s', ternary(strcmp(G.dep, W.Q.deployed), ...
        'stays', sprintf('CHANGES to %s: the deployed rows must be re-run in evaluate_policies.m', G.dep)))}];
end
lines{end+1} = sprintf('Validation done in %.1f min. Selection frozen: %s.', toc(t0) / 60, name_txt(adopted));
sel = struct('tag', tag, 'tree', tree, 'adopted', adopted, 'step1', s1, 'created', datestr(now, 31), ...
    'fingerprint', F0, 'deployed_off', W.Q.deployed, 'deployed_on', G.dep);
read_once('save', X.val, struct('Vs', struct('S1', rmfield(S1, 'lines'), 'S2', rmfield(S2, 'lines'), 'R1', strip(Rd), ...
    'R2', strip(R2), 'side', side, 'gate', rmfield(G, 'lines'))));
read_once('write', X.txt, lines);
read_once('write', X.sel, {jsonencode(sel, 'PrettyPrint', true)});
read_once('write', X.claim_val, {sprintf('rule_fix validation frozen %s', datestr(now, 31)), ['tree ' F0.tree], ['tag ' tag], ...
    ['code ' F0.code], ['selection ' X.sel], ['adopted ' name_txt(adopted)]});
fprintf('%s\n', lines{:});
end

function [ok, lines] = check_rows(chk)
% Rows {name, read, registered, tolerance}: every one within its tolerance.
ok = true; lines = {};
for i = 1:size(chk, 1)
    e = isfinite(chk{i, 3}) && abs(chk{i, 2} - chk{i, 3}) <= chk{i, 4};
    ok = ok && e;
    lines{end+1} = sprintf('  %-60s %12.6g registered %12.6g: %s', chk{i, 1}, chk{i, 2}, chk{i, 3}, ternary(e, 'reproduced', 'NOT REPRODUCED')); %#ok<AGROW>
end
end

function W = val_world(R)
% The pools, agent, monitor inputs and validation episodes as train_dqn.m reads them, and the
% registered readings of results/dqn_training.txt.
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
K = link_env('tables', PP);
PP.pools(:, :, :, 3:end) = {[]};                            % train and validation, as train_dqn.m holds them
Q = load('data/trained_dqn.mat', 'agent', 'agents', 'gammas', 'H', 'seed_summary', 'deployed', 'rule_sel', 'dec', 'det_id', ...
    'maha_thr');
check_det_id(PP, Q, 'rule_fix_reading');
DM = 'class_drop';
if isfile('data/drop_threshold.mat')                         % train_dqn.m's monitor inputs
    Dd = load('data/drop_threshold.mat'); PP.drop_db = Dd.drop_db;
    if isfield(Dd, 'drop_alarm') && strcmp(Dd.drop_alarm, 'class_cusum'), DM = Dd.drop_alarm; PP.drop_db = Dd.cusum_db; end
    if isfield(Dd, 'MONP') && isfield(Dd.MONP, 'confirm_drop'), PP.dconf = struct('monitor', {Dd.MONP.monitor}, 'cd', {Dd.MONP.confirm_drop}); end
    if isfield(Dd, 'MONP') && isfield(Dd.MONP, 'lb_accept'), PP.lbacc = struct('monitor', {Dd.MONP.monitor}, 'la', {Dd.MONP.lb_accept}); end
    if isfield(Dd, 'confirm_sweep'), PP.confirm_sweep = Dd.confirm_sweep; end
    if isfield(Dd, 'deg_mode'), PP.deg_mode = Dd.deg_mode; PP.ber_q = Dd.ber_q; end
end
CV = load('data/clean_val_pools.mat', 'CT'); CV = CV.CT;
check_det_id(PP, CV, 'rule_fix_reading', 'data/clean_val_pools.mat');
et = PP.ebno(1);
if isfile('results/eval_detector_metrics.mat')
    Md = load('results/eval_detector_metrics.mat', 'metrics');
    if isfield(Md.metrics, 'kpi1_threshold_db') && isfinite(Md.metrics.kpi1_threshold_db), et = Md.metrics.kpi1_threshold_db; end
end
H = Q.H;
spec = full_val_spec(PP, K, H, 2, R.val_reps, RandStream('mt19937ar', 'Seed', R.val_seed));
sc = cell2mat(cellfun(@(sp) sp.scn, spec, 'UniformOutput', false));
sv = cell2mat(cellfun(@(sp) sp.s, spec, 'UniformOutput', false));
W = struct('PP', PP, 'K', K, 'Q', Q, 'CV', CV, 'H', H, 'spec', {spec}, 'thr', {PP.scen(sc)}, 's', sv, 'ebno_thr', et, ...
    'drop_mode', DM, 'n', numel(sc), 'ncl', 0, 'R', R, 'reg', registered_txt('results/dqn_training.txt', Q.rule_sel));
[~, W.ncl] = clean_wide_specs(PP, CV, et, H.T);
end

function T = registered_txt(f, rs)
% The registered validation rows of C2's report: the reference monitor of the rule settings, the
% core rule's row at the chosen settings, and rule + escalation at every monitor and drop threshold.
assert(isfile(f), 'rule_fix_reading:registered', 'rule_fix_reading: %s is missing', f);
L = splitlines(fileread(f));
i = find(contains(L, 'Rule settings on validation, rule + escalation at '''), 1);
assert(~isempty(i), 'rule_fix_reading:registered', 'rule_fix_reading: no rule-settings header in %s', f);
t = regexp(L{i}, 'escalation at ''([^'']+)''.*?, drop (\S+) ', 'tokens', 'once');
T.ref = struct('alarm', t{1}, 'drop', str2double(t{2}));
j = find(contains(L, 'core rule (rule_core'), 1);
assert(~isempty(j), 'rule_fix_reading:registered', 'rule_fix_reading: no core-rule rows in %s', f);
cn = ''; if isfield(rs, 'core_nb'), cn = rs.core_nb; end
% the settings may go on after the noise-burst answer (the lost-branch gates) before the readings
pc = ['core rule on a noise burst ' regexptranslate('escape', cn) '(, [^|]*)? \|'];
k = j + find(~cellfun(@isempty, regexp(L(j+1:end), pc, 'once')), 1);
assert(~isempty(k) && ~startsWith(strtrim(L{k}), '->'), 'rule_fix_reading:registered', ...
    'rule_fix_reading: no core-rule row at the chosen settings in %s', f);
h = regexp(L{k}, 'held ([\d.]+)%, recovered ([\d.]+)%', 'tokens', 'once');
fa = regexp(L{k}, 'FA (\d+)/(\d+)', 'tokens', 'once');
T.core = struct('held', str2double(h{1}), 'rec', str2double(h{2}), 'k', NaN);
if ~isempty(fa), T.core.k = str2double(fa{1}); end
g = regexp(L, '^\s+(\S+ \d+/\d+)\s+drop\s+(\S+) \S+\s+rule \+ escalation: held ([\d.]+)%, recovered ([\d.]+)%, return \S+, FA ([\d.]+|-)', ...
    'tokens', 'once');
g = g(~cellfun(@isempty, g));
T.grid = struct('alarm', cellfun(@(x) x{1}, g, 'UniformOutput', false), 'drop', cellfun(@(x) str2double(x{2}), g, 'UniformOutput', false), ...
    'held', cellfun(@(x) str2double(x{3}), g, 'UniformOutput', false), 'rec', cellfun(@(x) str2double(x{4}), g, 'UniformOutput', false), ...
    'fa', cellfun(@(x) str2double(x{5}), g, 'UniformOutput', false));
assert(~isempty(T.grid), 'rule_fix_reading:registered', 'rule_fix_reading: no monitor rows in %s', f);
end

function x = read_pol(W, who, fix)
% One policy on the validation episodes and the clean validation flights, with the layered
% answers fix ('' off): rule_sel (rule + escalation at its own monitor and settings), core_ref (the
% core rule at C2's reference monitor and the rule's settings, as C2 read it), rule_dec, core_dec,
% blind_dec, blind_core_dec (at the deployed DQN's settings without the release on evidence, as C2's
% gate read the rule), dqn_dep (the deployed DQN as deployed).
PP = W.PP; ag = []; opt = struct();
switch who
    case 'rule_sel', kind = 'rule_esc'; mon = W.Q.rule_sel;
    case 'core_ref'
        kind = 'rule_esc'; opt.core = true; mon = rule_settings(W.Q.rule_sel);
        PP = with_entry(W.PP, W.reg.ref.alarm, W.reg.ref.drop, W.drop_mode);
    case 'rule_dec', kind = 'rule_esc'; mon = W.Q.dec;
    case 'core_dec', kind = 'rule_esc'; mon = W.Q.dec; opt.core = true;
    case 'blind_dec', kind = 'blind_esc'; mon = W.Q.dec;
    case 'blind_core_dec', kind = 'blind_esc'; mon = W.Q.dec; opt.core = true;
    case 'dqn_dep'
        kind = W.Q.deployed; mon = W.Q.dec; ag = W.Q.agent;
        if strcmp(kind, 'rule_sel'), kind = 'rule_esc'; mon = W.Q.rule_sel; end
    otherwise, error('rule_fix_reading:who', 'rule_fix_reading: unknown policy %s', who);
end
if ~strcmp(who, 'dqn_dep') && isfield(mon, 'release_m'), mon.release_m = false; end
mon.rule_fix = fix;
x = read_with(W, kind, PP, ag, setfield(opt, 'monitor', mon)); %#ok<SFLD>
end

function x = read_with(W, kind, PP, ag, opt)
V = dqn_eval_batches(kind, PP, W.K, W.spec, ag, opt, W.R.frames, 2);
x = struct('rec', dqn_recovered(V), 'held', dqn_held(V), 'ret', mean(V.ret), 'recovered', V.recovered, 'heldv', V.held, ...
    'recoverable', V.recoverable, 'threat', V.threat, 'cl', 1000 * W.s + V.r, 'sw', clean_changes(W, kind, PP, ag, opt));
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

function [G, chk] = gate_grid(W, o, fix, held_dec)
% choose_deployed.m over C2's grid (the runs' monitor and drop entries) at the rule's settings with
% the layered answers fix; the DQN at its registered held recovery and its clean flights read here.
% Off (fix ''): chk holds every entry's held, recovered and false-alarm share against the
% registered rows (printed to 0.1 point).
ss = W.Q.seed_summary;
al = ss.alarms(:)'; dr = ss.drops(:)';
key = arrayfun(@(k) sprintf('%s|%.9g', al{k}, dr(k)), 1:numel(al), 'UniformOutput', false);
[~, iu] = unique(key, 'stable'); al = al(iu); dr = dr(iu);
Ssel = rule_settings(W.Q.rule_sel);
dqn_up = cp_upper(sum(o.dqn.sw > 0), numel(o.dqn.sw));
rr = nan(1, numel(al)); up = rr; chk = cell(0, 4);
G = struct('dep', '', 'rr', [], 'up', [], 'lines', {{sprintf('Gate of choose_deployed.m, %s:', name_txt(fix))}});
for e = 1:numel(al)
    S = Ssel; S.rule_fix = fix;
    x = read_with(W, 'rule_esc', decision_settings(with_entry(W.PP, al{e}, dr(e), W.drop_mode), S), [], struct());
    rr(e) = x.held; up(e) = cp_upper(sum(x.sw > 0), numel(x.sw));
    G.lines{end+1} = sprintf('  %-18s drop %7.1f: rule + escalation held %.1f%%, clean-flight bound %.1f%%', al{e}, dr(e), ...
        100 * rr(e), 100 * up(e));
    if isempty(fix)
        gd = [W.reg.grid.drop]; g = W.reg.grid(strcmp({W.reg.grid.alarm}, al{e}) & (abs(gd - dr(e)) < 0.051 | (isnan(gd) & isnan(dr(e)))));
        if numel(g) ~= 1, chk(end+1, :) = {sprintf('grid row %s drop %.1f found once', al{e}, dr(e)), numel(g), 1, 0}; continue; end %#ok<AGROW>
        chk = [chk; {sprintf('grid %s drop %.1f held [%%]', al{e}, dr(e)), 100 * x.held, g.held, 0.05 + 1e-9; ...
            sprintf('grid %s drop %.1f recovered [%%]', al{e}, dr(e)), 100 * x.rec, g.rec, 0.05 + 1e-9}]; %#ok<AGROW>
        if isfinite(g.fa), chk(end+1, :) = {sprintf('grid %s drop %.1f false alarms [%%]', al{e}, dr(e)), 100 * mean(x.sw > 0), g.fa, 0.05 + 1e-9}; end %#ok<AGROW>
    end
end
bs = o.dec.held; if nargin >= 4, bs = held_dec; end
gate = ss.dqn_held >= bs && dqn_up <= W.R.bound;
kd = 'dqn_esc'; if isfield(ss, 'selected_kind'), kd = ss.selected_kind; end
G.dep = choose_deployed(gate, dqn_up, rr, up, W.R.bound, ss.dqn_held, kd); G.rr = rr; G.up = up;
G.lines{end+1} = sprintf('  gate %s (DQN held %.1f%% against the rule at its settings %.1f%%), deployed %s', ...
    ternary(gate, 'PASS', 'FAIL'), 100 * ss.dqn_held, 100 * bs, G.dep);
end

function S = rule_settings(rs)
% The rule's settings of rule_sel without its monitor and readings.
S = rmfield(rs, intersect(fieldnames(rs), {'alarm', 'drop', 'rec', 'held', 'fa_w', 'n_w', 'fa_upper', 'alarm_mode', 'confirm', ...
    'drop_db', 'confirm_sweep', 'confirm_drop', 'lb_accept', 'deg_mode', 'ber_q'}));
end

function PPc = with_entry(PP, name, drop, drop_mode)
% train_dqn.m's with_entry: monitor name at drop threshold drop.
t = strsplit(name); mode = t{1}; if strcmp(mode, 'class_drop'), mode = drop_mode; end
PPc = PP; PPc.alarm_mode = mode; PPc.confirm = sscanf(t{2}, '%d/%d')';
if ~isnan(drop), PPc.drop_db = drop; end
if isfield(PP, 'dconf'), k = find(strcmp({PP.dconf.monitor}, name), 1); PPc.confirm_drop = []; if ~isempty(k), PPc.confirm_drop = PP.dconf(k).cd; end, end
if isfield(PP, 'lbacc'), k = find(strcmp({PP.lbacc.monitor}, name), 1); PPc.lb_accept = []; if ~isempty(k), PPc.lb_accept = PP.lbacc(k).la; end, end
end

%% ===================== Selection =====================
function S = select(T)
% T.read(1) the setting in force, T.read(2:end) the candidates; T.fam the target threats;
% T.thr the threat of every episode.
R = reg();
n = numel(T.read);
S = struct('pass', false(1, n), 'adopt', {cell(1, n)}, 'best', 1, 'lines', {{}});
for k = 2:n
    A = adopt(T.read(k).sel, T.read(1).sel, T.fam, T.read(k).core, T.read(1).core, T.thr);
    S.adopt{k} = rmfield(A, 'lines'); S.pass(k) = A.pass;
    S.lines = [S.lines, {sprintf('  %s: %s', name_txt(T.read(k).name), ternary(A.pass, 'passes', 'not adopted'))}, A.lines];
end
c = find(S.pass);
if isempty(c), return; end
h = arrayfun(@(k) T.read(k).sel.held, c); c = c(h >= max(h) - R.thr.tie);
r = arrayfun(@(k) T.read(k).sel.rec, c); c = c(r >= max(r));
[~, j] = max(arrayfun(@(k) T.read(k).sel.ret, c)); S.best = c(j);
end

function A = adopt(x, y, fam, cx, cy, thr)
% The registered conditions (a)-(e) of candidate x over the setting in force y.
R = reg(); t = R.thr;
thr = thr(:)';
m = x.recoverable & y.recoverable & x.threat;
inf_ = cellfun(@(s) any(ismember(strsplit(s, '+'), fam)), thr);
A = struct('pass', false, 'a', false, 'b', true, 'c', false, 'd', false, 'e', false, 'lines', {{}});
[pa, la] = pdiff(x.heldv, y.heldv, m & inf_, x.cl, 211);
A.a = pa > t.a && la > t.a;
A.lines{end+1} = sprintf('    (a) target threats, held %+.2f points, lower bound %+.2f: %s', 100 * pa, 100 * la, ok_txt(A.a));
for u = unique(thr(m), 'stable')
    mt = m & strcmp(thr, u{1});
    if sum(mt) < R.min_n, continue; end
    [p, l] = pdiff(x.recovered, y.recovered, mt, x.cl, 212);
    ok = p >= t.thr_pt && l >= t.thr_lb; A.b = A.b && ok;
    if ~ok || p ~= 0
        A.lines{end+1} = sprintf('    (b) %-36s n %5d recovered %+.2f, lower bound %+.2f: %s', u{1}, sum(mt), 100 * p, 100 * l, ok_txt(ok)); %#ok<AGROW>
    end
end
[ph, lh] = pdiff(x.heldv, y.heldv, m, x.cl, 213); [pr, lr] = pdiff(x.recovered, y.recovered, m, x.cl, 214);
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
mc = cx.recoverable & cy.recoverable & cx.threat;
[pc, lc] = pdiff(cx.heldv, cy.heldv, mc, cx.cl, 215);
A.e = pc >= t.pool_pt && lc >= t.pool_lb;
A.lines{end+1} = sprintf('    (e) core rule pooled held %+.2f (lb %+.2f): %s', 100 * pc, 100 * lc, ok_txt(A.e));
A.pass = A.a && A.b && A.c && A.d && A.e;
end

function [p, l] = pdiff(a, b, m, cl, seed)
% Paired mean difference a - b over episodes m and its one-sided 95% lower bound.
p = NaN; l = NaN;
if ~any(m), return; end
[p, l] = paired_stats('boot', double(a(m)) - double(b(m)), cl(m), reg().B, seed);
end

%% ===================== Test (read once) =====================
function stage_test(tree, tag)
X = paths(tree, tag); R = reg();
J = guard(X);
if ~isempty(J), error('rule_fix_reading:guard', 'rule_fix_reading: the test is not read: %s', strjoin(J, '; ')); end
S = jsondecode(fileread(X.sel));
if isempty(S.adopted)
    claim_test(X, S, 'nothing adopted: not read');
    read_once('write', X.txt, [splitlines(strtrim(fileread(X.txt)))', {'', '=== RULE FIX: TEST ===', ...
        'No setting was adopted on validation: the test is not read.'}]);
    return
end
c0 = cd(tree); back = onCleanup(@() cd(c0)); %#ok<NASGU>
t0 = tic;
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
Q = load('data/trained_dqn.mat', 'agent', 'agents', 'gammas', 'H', 'seed_summary', 'deployed', 'rule_sel', 'dec', 'det_id', 'maha_thr');
check_det_id(PP, Q, 'rule_fix_reading');
PP = decision_settings(PP, Q);                        % every policy at the deployed DQN's settings (evaluate_policies.m)
K = link_env('tables', PP);
E = load('results/policy_evaluation.mat', 'RES', 'POL', 'LBL', 'set_names', 'iDQN');
[sets, single_cells] = test_sets(PP, K, Q.H.T, R);
assert(isequal(E.set_names(1:numel(sets)), {sets.name}), 'rule_fix_reading:sets', ...
    'rule_fix_reading: the registered sets are not %s', strjoin({sets.name}, ', '));
pols = {'rule', 'rule_esc', 'blind_esc', 'rule_core', 'blind_core', 'rule_sel', 'rule_core3'};
pols = pols(ismember(pols, E.POL));
sel = find(Q.gammas == Q.seed_summary.selected_gamma, 1);
% Off first: every registered rule row of the five sets, before the marker
bad = {};
for si = 1:numel(sets)
    for pk = 1:numel(pols)
        [kind, ag, opt] = policy_setup(pols{pk}, Q, sel, [], [], [], K.na);
        R0 = policy_run_set(kind, PP, K, sets(si).spec, sets(si).split, ag, opt, R.test_seed + 1000 * si);
        Rg = E.RES{si, strcmp(E.POL, pols{pk})};
        if ~(isequaln(R0.recovered, Rg.recovered) && isequaln(R0.held, Rg.held) && isequaln(R0.per_post, Rg.per_post) ...
                && isequaln(R0.switches, Rg.switches))
            bad{end+1} = sprintf('%s on %s', pols{pk}, sets(si).name); %#ok<AGROW>
        end
    end
end
if ~isempty(bad)
    read_once('write', X.txt, [splitlines(strtrim(fileread(X.txt)))', {'', '=== RULE FIX: TEST ===', ...
        ['Off does not reproduce the registered rows (' strjoin(bad, ', ') '): the test is not read.']}]);
    error('rule_fix_reading:reproduce', 'rule_fix_reading: off does not reproduce %s', strjoin(bad, ', '));
end
claim_test(X, S, sprintf('read for %s', S.adopted));
RON = cell(numel(sets), numel(pols));
for si = 1:numel(sets)
    for pk = 1:numel(pols)
        [kind, ag, opt] = policy_setup(pols{pk}, Q, sel, [], [], [], K.na);
        if ~isfield(opt, 'monitor') || ~isstruct(opt.monitor), opt.monitor = struct(); end
        opt.monitor.rule_fix = S.adopted;
        RON{si, pk} = policy_run_set(kind, PP, K, sets(si).spec, sets(si).split, ag, opt, R.test_seed + 1000 * si);
    end
    fprintf('  set %-9s %d policies (%.1f min)\n', sets(si).name, numel(pols), toc(t0) / 60);
end
lines = {'', '=== RULE FIX: TEST (read once) ===', sprintf('Generated: %s | setting %s | test sets %s', datestr(now), ...
    S.adopted, strjoin({sets.name}, ', ')), sprintf('Off reproduces every registered rule row (%s) on every set: exact', strjoin(pols, ', '))};
lines = [lines, test_lines(E, RON, pols, PP, single_cells)];
ALL0 = pooled(E.RES, 1:3); ALL1 = ALL0;
for pk = 1:numel(pols)
    c = find(strcmp(E.POL, pols{pk}));
    ALL1{c} = RON{1, pk}; for si = 2:3, ALL1{c} = cat_struct(ALL1{c}, RON{si, pk}); end
end
C = decision_config(); pay = payload_rate(C);
[LK0, l0] = lect_kpis(ALL0, E.POL, E.LBL, E.iDQN, PP.scen, pay, C.period_ms);
[LK1, l1] = lect_kpis(ALL1, E.POL, E.LBL, E.iDQN, PP.scen, pay, C.period_ms);
lines = [lines, {'', 'Lecturer KPIs, off (the registered rows):'}, l0, {'', sprintf('Lecturer KPIs, rule rows with %s:', S.adopted)}, l1];
if ~strcmp(S.deployed_on, S.deployed_off)
    lines{end+1} = sprintf(['The gate re-read on validation deploys %s instead of %s: the deployed rows and every KPI of the ' ...
        'deployed policy must be re-run through evaluate_policies.m; this reading does not replace them.'], S.deployed_on, S.deployed_off);
end
lines{end+1} = sprintf('Test done in %.1f min.', toc(t0) / 60);
RONs = cellfun(@(r) keep_fields(r), RON, 'UniformOutput', false);
read_once('save', X.test, struct('RONs', {RONs}, 'pols', {pols}, 'LK0', LK0, 'LK1', LK1));
read_once('write', X.txt, [splitlines(strtrim(fileread(X.txt)))', lines]);
fprintf('%s\n', lines{:});
end

function claim_test(X, S, what)
% The tree's test split is spent: the per-tree marker (whatever the tag) and the tag's own.
txt = {sprintf('rule_fix test %s %s', what, datestr(now, 31)), ['tree ' S.fingerprint.tree], ['tag ' X.tag], ...
    ['code ' S.fingerprint.code], ['inputs ' strjoin(cellstr(S.fingerprint.inputs(:))', ' ')], ['selection ' X.sel]};
read_once('write', X.claim_test, txt);
read_once('write', X.marker, txt);
end

function [sets, single_cells] = test_sets(PP, K, T, R)
% evaluate_policies.m's first five sets, drawn from its stream in its order.
nS = numel(PP.ebno); NE = 64; REPS = 2; TEST = 3;
single_cells = find(ismember(PP.scen, PP.singles) & ~strcmp(PP.scen, 'none'));
combo_cells = find(ismember(PP.scen, PP.combos));
G = @(cells) K.geo(cells, TEST);
rs = RandStream('mt19937ar', 'Seed', R.test_rs);
foll = single_cells(K.followable(single_cells));
sp = {policy_episodes(single_cells, nS, G(single_cells), REPS, false, false, NE, T, rs), ...
    policy_episodes(foll, nS, G(foll), REPS, true, false, NE, T, rs), ...
    policy_episodes(combo_cells, nS, G(combo_cells), REPS, false, false, NE, T, rs), ...
    policy_episodes(single_cells, nS, G(single_cells), 1, false, true, NE, T, rs), ...
    policy_episodes(K.clean, nS, G(K.clean), 1, false, false, NE, T, rs)};
sets = struct('name', R.test_sets, 'spec', sp, 'split', TEST);
end

function lines = test_lines(E, RON, pols, PP, ~)
% Recovered and held among the recoverable threat episodes per threat (threat sets pooled), off
% (registered) and on, paired, with the cluster-bootstrap interval of the difference; the
% clean set's changes.
lines = {};
A0 = pooled(E.RES, 1:3);
thr = PP.scen(A0{1}.scn);
for pk = 1:numel(pols)
    c = find(strcmp(E.POL, pols{pk}));
    x0 = A0{c}; x1 = RON{1, pk}; for si = 2:3, x1 = cat_struct(x1, RON{si, pk}); end
    m = x0.recoverable & x0.threat;
    lines{end+1} = sprintf('%s: recovered among the recoverable, off -> on [95%% interval of the paired difference]', pols{pk}); %#ok<AGROW>
    for u = unique(thr(m), 'stable')
        mt = m & strcmp(thr, u{1});
        d = double(x1.recovered(mt)) - double(x0.recovered(mt));
        [~, lo, hi] = boot_cluster(d, ones(1, sum(mt)), x0.geom(mt), 2000, 300 + pk);
        lines{end+1} = sprintf('  %-40s n %5d  %5.1f -> %5.1f  [%+.1f, %+.1f]', u{1}, sum(mt), 100 * mean(x0.recovered(mt)), ...
            100 * mean(x1.recovered(mt)), 100 * lo, 100 * hi); %#ok<AGROW>
    end
    d = double(x1.recovered(m)) - double(x0.recovered(m));
    [~, lo, hi] = boot_cluster(d, ones(1, sum(m)), x0.geom(m), 2000, 400 + pk);
    lines{end+1} = sprintf('  %-40s n %5d  %5.1f -> %5.1f  [%+.1f, %+.1f]; held %5.1f -> %5.1f', 'pooled', sum(m), ...
        100 * mean(x0.recovered(m)), 100 * mean(x1.recovered(m)), 100 * lo, 100 * hi, 100 * mean(x0.held(m)), 100 * mean(x1.held(m))); %#ok<AGROW>
    ic = numel(RON(:, pk));
    lines{end+1} = sprintf('  clean set: episodes with a change %d -> %d of %d', sum(E.RES{ic, c}.switches > 0), ...
        sum(RON{ic, pk}.switches > 0), numel(RON{ic, pk}.switches)); %#ok<AGROW>
end
end

%% ===================== Helpers =====================
function specs = full_val_spec(PP, K, H, split, reps, rs)
% train_dqn.m's validation episodes.
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

function A = pooled(RES, iset)
A = cell(1, size(RES, 2));
for pk = 1:size(RES, 2)
    A{pk} = RES{iset(1), pk};
    for si = iset(2:end), A{pk} = cat_struct(A{pk}, RES{si, pk}); end
end
end

function R = cat_struct(R, Rb)
f = fieldnames(R);
for i = 1:numel(f), R.(f{i}) = [R.(f{i}), Rb.(f{i})]; end
end

function r = keep_fields(R)
f = intersect(fieldnames(R), {'scn', 's', 'r', 'geom', 'recovered', 'held', 'recoverable', 'recoverable_core', 'threat', ...
    'per_post', 'switches', 'ret', 't_rec'});
r = struct(); for i = 1:numel(f), r.(f{i}) = R.(f{i}); end
end

function r = payload_rate(C)
r = NaN;
if ~isfile('params.mat'), return; end
p = load('params.mat').params;
cyc = C.period_ms / 1000; if isfield(p, 'cycle_s'), cyc = p.cycle_s; end
r = p.bits_per_frame / cyc;
end

function x = summ(x)
x = struct('held', x.held, 'rec', x.rec, 'ret', x.ret, 'fa', sum(x.sw > 0), 'n', numel(x.sw));
end

function R = strip(R)
for k = 1:numel(R), R(k).sel = summ(R(k).sel); R(k).core = summ(R(k).core); end
end

function u = cp_upper(k, n)
if n == 0, u = NaN; elseif k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

function v = field_or(S, n, d)
v = d; if isstruct(S) && isfield(S, n), v = S.(n); end
end

function t = name_txt(n)
if isempty(n), t = 'off (today''s rule)'; else, t = n; end
end

function t = ok_txt(c)
t = ternary(c, 'ok', 'FAILS');
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
