function out = core_bw_rule_fix_reading(stage, varargin)
%CORE_BW_RULE_FIX_READING  Side reading of the core rule's layered answers (PP.rule_fix, rule_fix.m)
%   in the bandwidth study (experiment_core_bw.m): the lecturer's KPI 8, narrowband and wideband,
%   with the core projection of the setting rule_fix_reading.m adopted. Runs in a checkout of the
%   study's code (core-bw-p1, 75bea00) with docs/runs/core_bw_rule_fix_75bea00.patch applied, from
%   the study's tree (data/core_bw/pools.mat, params.mat, data/trained_dqn.mat,
%   data/policy_pools.mat's clean_ref, results/core_bw/); writes only under
%   results/core_bw_rule_fix/<tag> of the code's root, never into results/core_bw; the study's own
%   marker is never read or written. Validation and test are each read once per tree, whatever the
%   tag (read_once.m markers), frozen with the hash of every .m file of the checkout; every file is
%   written whole (temporary file renamed).
%   core_bw_rule_fix_reading('val', tree, tag, sel)   validation (split 1, hop rule H1): reproduces
%       the registered validation readings with the option off (W, W3 and blind_core's first
%       response, results/core_bw/validation.mat), reads the core projections keep, keep+rate,
%       keep+match against off, binds the projection of sel (rule_fix_reading.m's selection.json,
%       or a setting name) when it passes, and freezes -> selection.json, val.mat, the reading's text
%   core_bw_rule_fix_reading('test', tree, tag)       the single test reading (split 2, H1 primary
%       set) of the bound setting against the registered rows of results/core_bw/test_readings.mat:
%       first, with the option off, rule_core3, rule_core and blind_core must reproduce those rows
%       exactly, before the marker is set (any mismatch stops); then the marker and the reading;
%       nothing bound: not read
%   X = core_bw_rule_fix_reading('paths', tree, tag)
%   J = core_bw_rule_fix_reading('guard', X)          the test stage's refusals ({} none)
%   F = core_bw_rule_fix_reading('fingerprint', X)
%   p = core_bw_rule_fix_reading('project', name)     the core projection of a setting
%   A = core_bw_rule_fix_reading('adopt', x, y)       conditions (a)-(e) of readings x against y
%   Registered conditions, on the validation episodes of the recoverable scenarios (the frozen
%   list) in the fixed-total cells, H1, frame draws 54100 + 10 k, the same for off and on:
%   (a) rule_core3's narrowband PER falls: the paired mean difference and its one-sided 95% upper
%       bound below 0
%   (b) rule_core3's wideband PER: no higher than +0.005, upper bound no higher than +0.010
%   (c) rule_core3's pooled held and recovered (recoverable threat episodes): no lower than -0.5
%       point, lower bound no lower than -1.0
%   (d) rule_core3's episodes with a false change: one-sided 95% Clopper-Pearson bound within
%       max(5%, off's) and the share at most 1 point above off's
%   (e) rule_core's pooled PER: no higher than +0.005, upper bound no higher than +0.010
%   Bounds: cluster bootstrap over the flights (EP.geom), 2000 draws, fixed seeds.
switch stage
    case 'val',         stage_val(varargin{:});
    case 'test',        stage_test(varargin{:});
    case 'paths',       out = paths(varargin{:});
    case 'guard',       out = guard(varargin{:});
    case 'fingerprint', out = fingerprint(varargin{:});
    case 'project',     out = project(varargin{:});
    case 'adopt',       out = adopt(varargin{:});
    otherwise, error('core_bw_rule_fix_reading:stage', 'core_bw_rule_fix_reading: unknown stage %s', stage);
end
end

%% ===================== Registered constants =====================
function R = reg()
R.cand = {'keep', 'keep+rate', 'keep+match'};
R.rule = 'H1'; R.q = 1;
R.pols = {'none', 'rule_core3', 'rule_core', 'blind_core'};
R.val_seed = 54100; R.test_seed = 82100; R.B = 2000;
R.t = struct('per_pt', 0.005, 'per_ub', 0.010, 'pool_pt', -0.005, 'pool_lb', -0.010, 'fa_pts', 0.010, 'bound', 0.05);
end

%% ===================== Files =====================
function X = paths(tree, tag)
assert(ischar(tag) && ~isempty(regexp(tag, '^[A-Za-z0-9_]+$', 'once')), 'core_bw_rule_fix_reading:tag', ...
    'core_bw_rule_fix_reading: the tag is letters, digits and _');
X.tree = tree; X.tag = tag;
X.dir = fullfile(project_root(), 'results', 'core_bw_rule_fix', tag);
X.sel = fullfile(X.dir, 'selection.json'); X.val = fullfile(X.dir, 'val.mat');
X.txt = fullfile(X.dir, 'core_bw_rule_fix_reading.txt'); X.marker = fullfile(X.dir, 'test_read_started.txt');
X.test = fullfile(X.dir, 'test.mat');
X.claim_val = read_once('claim', 'core_bw_rule_fix', 'val', tree); X.claim_test = read_once('claim', 'core_bw_rule_fix', 'test', tree);
X.inputs = cellfun(@(f) fullfile(tree, f), {fullfile('results', 'core_bw', 'protocol.json'), ...
    fullfile('results', 'core_bw', 'recoverable.txt'), fullfile('results', 'core_bw', 'validation.mat'), ...
    fullfile('results', 'core_bw', 'test_readings.mat'), fullfile('data', 'trained_dqn.mat'), 'params.mat', 'profile.json'}, ...
    'UniformOutput', false);
X.big = cellfun(@(f) fullfile(tree, f), {fullfile('data', 'core_bw', 'pools.mat'), fullfile('data', 'policy_pools.mat')}, ...
    'UniformOutput', false);
X.S = struct('pools', fullfile('data', 'core_bw', 'pools.mat'), 'proto', fullfile('results', 'core_bw', 'protocol.json'), ...
    'recov', fullfile('results', 'core_bw', 'recoverable.txt'), 'val', fullfile('results', 'core_bw', 'validation.mat'), ...
    'res', fullfile('results', 'core_bw', 'test_readings.mat'));
X.NGEO = [12 36]; X.REPS = 2; X.NE = 64; X.T = 30; X.RULES = {'H1', 'H3', 'H4'};
end

function F = fingerprint(X)
% Every .m file of this checkout's code, the study's small inputs (SHA-256), its large ones (size, date).
F = struct('tree', read_once('tree', X.tree), 'code', read_once('code'), ...
    'inputs', {cellfun(@(f) read_once('file', f), X.inputs, 'UniformOutput', false)}, ...
    'big', {cellfun(@(f) read_once('big', f), X.big, 'UniformOutput', false)});
end

function J = guard(X)
% The test stage's refusals: no frozen selection, another tree, this tree's side test read already
% (whatever the tag), the code or the inputs changed. The study's own marker is never read or written.
J = {};
if ~isfile(X.sel), J{end+1} = 'no frozen selection (run the val stage first)'; return; end
S = jsondecode(fileread(X.sel));
F = fingerprint(X);
if ~strcmp(S.fingerprint.tree, F.tree), J{end+1} = 'the selection was frozen on another tree'; end
if isfile(X.claim_test) || isfile(X.marker), J{end+1} = 'the side test of this tree was read already'; end
if ~strcmp(S.fingerprint.code, F.code), J{end+1} = 'the code differs from the code the selection ran'; end
if ~isequal(cellstr(S.fingerprint.inputs(:))', F.inputs) || ~isequal(cellstr(S.fingerprint.big(:))', F.big)
    J{end+1} = 'the study''s inputs differ from those the selection read';
end
end

function p = project(name)
% The core projection: keep, and rate or match; st and fec lie outside the core set.
p = '';
if isempty(name), return; end
F = rule_fix('parse', name);
t = {};
if F.keep, t{end+1} = 'keep'; end
if ~isempty(F.inch), t{end+1} = F.inch; end
p = strjoin(t, '+');
end

%% ===================== Validation =====================
function stage_val(tree, tag, sel)
X = paths(tree, tag); R = reg();
assert(~isfile(X.claim_val), 'core_bw_rule_fix_reading:val_once', ...
    'core_bw_rule_fix_reading: a selection was frozen on this tree already (%s)', X.claim_val);
assert(~isfile(X.sel) && ~isfile(X.val) && ~isfile(X.txt), 'core_bw_rule_fix_reading:exists', ...
    'core_bw_rule_fix_reading: %s already holds a reading; a reading is never overwritten', X.dir);
if isfile(sel), S0 = jsondecode(fileread(sel)); bound_from = sel; set0 = S0.adopted; else, bound_from = 'given'; set0 = sel; end
proj = project(set0);
F0 = fingerprint(X);
c0 = cd(tree); back = onCleanup(@() cd(c0)); %#ok<NASGU>
t0 = tic;
W = world(X, 1);
lines = {sprintf('=== CORE_BW, RULE FIX: VALIDATION (%s, tree %s) ===', tag, tree), sprintf('Generated: %s', datestr(now)), ...
    sprintf('Setting to bind: %s (from %s), core projection %s', name_txt(set0), bound_from, name_txt(proj))};
% 0. Off: the registered validation readings reproduced (H1)
V = load(X.S.val, 'WCH', 'WCH3', 'BCH');
Rn = run_set('none', W.PP, W, 1:W.EP.n, '', R.q, 51000 + 100 * R.q);
wide = find(~W.EP.slice & ~W.EP.narrow & ~W.EP.occ); fixed = find(~W.EP.slice & ~W.EP.occ);
iw = wide(Rn.recoverable(ismember(Rn.ep, wide))); ib = fixed(Rn.recoverable(ismember(Rn.ep, fixed)));
chk = {'rule_core', 'core_wide', W.J.w.(R.rule), iw, 52000, V.WCH; 'rule_core3', 'core_wide', W.J.w3.(R.rule), iw, 52000, V.WCH3; ...
    'blind_core', 'core_blind', W.J.blind_first.(R.rule), ib, 53000, V.BCH};
ok = true;
for i = 1:size(chk, 1)
    Pp = W.PP; Pp.(chk{i, 2}) = chk{i, 3};
    Rx = run_set(chk{i, 1}, Pp, W, chk{i, 4}, '', R.q, chk{i, 5} + 100 * R.q);
    e = W.EP; j = chk{i, 4};
    [~, tab] = core_bw_rules('choose_w', chk(i, 3), e.bj(j), e.tot(j), e.geom(j), Rx.per_post(:)', Rx.dlv_post(:)', Rx.t_rec_det(:)', 2000);
    reg_tab = chk{i, 6}(R.q).table; reg_row = reg_tab(strcmp({reg_tab.W}, chk{i, 3}));
    same = abs(tab.per - reg_row.per) < 1e-12 && abs(tab.gput - reg_row.gput) < 1e-9 && isequaln(tab.trec, reg_row.trec);
    ok = ok && same;
    lines{end+1} = sprintf('Off, %s with %s %s: PER %.6f (registered %.6f), goodput %.1f (%.1f): %s', chk{i, 1}, chk{i, 2}, ...
        chk{i, 3}, tab.per, reg_row.per, tab.gput, reg_row.gput, ternary(same, 'exact', 'NOT REPRODUCED')); %#ok<AGROW>
end
if ~ok
    read_once('write', X.txt, [lines, {'The code does not reproduce the study''s registered validation readings: no candidate is read.'}]);
    error('core_bw_rule_fix_reading:reproduce', 'core_bw_rule_fix_reading: the off readings do not reproduce %s', tree);
end
% 1. The candidates against off, on the recoverable fixed-total episodes
m = recoverable_mask(W.REC, R.rule, W.EP) & ~W.EP.slice & ~W.EP.occ;
idx = find(m);
D = struct('name', {}, 'x', {});
for nm = [{''}, R.cand]
    x = struct();
    for k = 1:numel(R.pols)
        if strcmp(R.pols{k}, 'none') && ~isempty(nm{1}), continue; end
        x.(R.pols{k}) = run_set(R.pols{k}, policy_pp(W, R.pols{k}), W, idx, nm{1}, R.q, R.val_seed + 10 * (k - 1));
    end
    D(end+1) = struct('name', nm{1}, 'x', x); %#ok<AGROW>
end
for c = 2:numel(D), D(c).x.none = D(1).x.none; end
lines = [lines, {'', sprintf('Candidates against off (%d episodes of the recoverable scenarios, fixed-total cells, %s):', numel(idx), R.rule)}];
A = cell(1, numel(D));
for c = 2:numel(D)
    A{c} = adopt(D(c).x, D(1).x, W.EP);
    lines = [lines, {sprintf('  %s: %s', D(c).name, ternary(A{c}.pass, 'passes', 'not adopted'))}, A{c}.lines]; %#ok<AGROW>
end
lines = [lines, per_table(D, W.EP)];
c = find(strcmp({D.name}, proj), 1);
bound = '';
if isempty(proj), why = 'the setting adopted on the main pools has no core element: nothing to bind';
elseif isempty(c), why = sprintf('%s is not a registered core projection', proj);
elseif A{c}.pass, bound = proj; why = sprintf('%s passes: bound', proj);
else, why = sprintf('%s fails a condition: nothing bound, the registered KPI 8 stands', proj);
end
lines{end+1} = sprintf('Binding: %s. Validation done in %.1f min.', why, toc(t0) / 60);
sel_out = struct('tag', tag, 'tree', tree, 'from', bound_from, 'setting', set0, 'projection', proj, 'bound', bound, ...
    'created', datestr(now, 31), 'fingerprint', F0);
Ds = arrayfun(@(d) struct('name', d.name, 'x', structfun(@keep_fields, d.x, 'UniformOutput', false)), D);
read_once('save', X.val, struct('Ds', Ds, 'A', {A}));
read_once('write', X.txt, lines);
read_once('write', X.sel, {jsonencode(sel_out, 'PrettyPrint', true)});
read_once('write', X.claim_val, {sprintf('core_bw_rule_fix validation frozen %s', datestr(now, 31)), ['tree ' F0.tree], ...
    ['tag ' tag], ['code ' F0.code], ['bound ' name_txt(bound)]});
fprintf('%s\n', lines{:});
end

function A = adopt(x, y, EP)
% Conditions (a)-(e) of the readings x (fields rule_core3, rule_core) against y.
t = reg().t;
r3 = x.rule_core3; o3 = y.rule_core3; ep = r3.ep; cl = EP.geom(ep);
nb = EP.narrow(ep);
A = struct('pass', false, 'a', false, 'b', false, 'c', false, 'd', false, 'e', false, 'lines', {{}});
[p, ~, ub] = cboot(r3.per_post(nb) - o3.per_post(nb), cl(nb), 311);
A.a = p < 0 && ub < 0;
A.lines{end+1} = sprintf('    (a) rule_core3 narrowband PER %+.4f, upper bound %+.4f: %s', p, ub, ok_txt(A.a));
[p, ~, ub] = cboot(r3.per_post(~nb) - o3.per_post(~nb), cl(~nb), 312);
A.b = p <= t.per_pt && ub <= t.per_ub;
A.lines{end+1} = sprintf('    (b) rule_core3 wideband PER %+.4f, upper bound %+.4f: %s', p, ub, ok_txt(A.b));
mr = r3.recoverable & o3.recoverable & r3.threat;
[ph, lh] = cboot(double(r3.held(mr)) - double(o3.held(mr)), cl(mr), 313);
[pr, lr] = cboot(double(r3.recovered(mr)) - double(o3.recovered(mr)), cl(mr), 314);
A.c = ph >= t.pool_pt && lh >= t.pool_lb && pr >= t.pool_pt && lr >= t.pool_lb;
A.lines{end+1} = sprintf('    (c) rule_core3 held %+.2f points (lb %+.2f), recovered %+.2f (lb %+.2f): %s', 100 * ph, 100 * lh, ...
    100 * pr, 100 * lr, ok_txt(A.c));
n = numel(ep); kx = sum(r3.false_sw > 0); ky = sum(o3.false_sw > 0);
ux = cp_upper(kx, n); uy = cp_upper(ky, n);
A.d = ux <= max(t.bound, uy) && (kx - ky) / n <= t.fa_pts;
A.lines{end+1} = sprintf('    (d) rule_core3 episodes with a false change %d -> %d of %d, bound %.2f%% -> %.2f%%: %s', ky, kx, n, ...
    100 * uy, 100 * ux, ok_txt(A.d));
[p, ~, ub] = cboot(x.rule_core.per_post - y.rule_core.per_post, cl, 315);
A.e = p <= t.per_pt && ub <= t.per_ub;
A.lines{end+1} = sprintf('    (e) rule_core pooled PER %+.4f, upper bound %+.4f: %s', p, ub, ok_txt(A.e));
A.pass = A.a && A.b && A.c && A.d && A.e;
end

function lines = per_table(D, EP)
% PER of every policy per jamming type, and the CNN contribution rule_core3 - blind_core.
lines = {'', 'PER (mean over the episodes) per jamming type; CNN contribution rule_core3 - blind_core [95% interval]:'};
ty = {'pooled', @(e) true(size(e)); 'narrowband', @(e) EP.narrow(e); 'wideband', @(e) ~EP.narrow(e)};
for c = 1:numel(D)
    x = D(c).x; ep = x.none.ep;
    for t = 1:size(ty, 1)
        m = ty{t, 2}(ep);
        [d, lo, hi] = boot_cluster(x.rule_core3.per_post(m) - x.blind_core.per_post(m), ones(1, nnz(m)), EP.geom(ep(m)), 2000, 6);
        lines{end+1} = sprintf('  %-12s %-10s none %.4f | rule_core3 %.4f | rule_core %.4f | blind_core %.4f | CNN %+.4f [%+.4f, %+.4f]', ...
            name_txt(D(c).name), ty{t, 1}, mean(x.none.per_post(m)), mean(x.rule_core3.per_post(m)), mean(x.rule_core.per_post(m)), ...
            mean(x.blind_core.per_post(m)), d, lo, hi); %#ok<AGROW>
    end
end
end

%% ===================== Test (read once) =====================
function stage_test(tree, tag)
X = paths(tree, tag); R = reg();
J = guard(X);
if ~isempty(J), error('core_bw_rule_fix_reading:guard', 'core_bw_rule_fix_reading: the test is not read: %s', strjoin(J, '; ')); end
S = jsondecode(fileread(X.sel));
if isempty(S.bound)
    claim_test(X, S, 'nothing bound: not read');
    read_once('write', X.txt, [splitlines(strtrim(fileread(X.txt)))', {'', '=== CORE_BW, RULE FIX: TEST ===', ...
        'Nothing was bound on validation: the test is not read.'}]);
    return
end
c0 = cd(tree); back = onCleanup(@() cd(c0)); %#ok<NASGU>
t0 = tic;
W = world(X, 2);
L = load(X.S.res, 'RES');
S0 = L.RES(strcmp({L.RES.rule}, R.rule) & strcmp({L.RES.set}, 'primary'));
reg_of = @(p) S0(strcmp({S0.policy}, p)).R;
all_ep = 1:W.EP.n;
x0 = struct(); x1 = struct();
for k = 1:numel(R.pols), x0.(R.pols{k}) = reg_of(R.pols{k}); end
x1.none = x0.none;
bad = {};                                             % off first: every registered row read here, before the marker
for k = 2:numel(R.pols)
    Rr = run_set(R.pols{k}, policy_pp(W, R.pols{k}), W, all_ep, '', R.q, R.test_seed);
    if ~(isequaln(Rr.per_post, x0.(R.pols{k}).per_post) && isequaln(Rr.held, x0.(R.pols{k}).held) && ...
            isequaln(Rr.recovered, x0.(R.pols{k}).recovered) && isequaln(Rr.false_sw, x0.(R.pols{k}).false_sw))
        bad{end+1} = R.pols{k}; %#ok<AGROW>
    end
end
if ~isempty(bad)
    read_once('write', X.txt, [splitlines(strtrim(fileread(X.txt)))', {'', '=== CORE_BW, RULE FIX: TEST ===', ...
        ['Off does not reproduce the registered primary rows (' strjoin(bad, ', ') '): the test is not read.']}]);
    error('core_bw_rule_fix_reading:reproduce', 'core_bw_rule_fix_reading: off does not reproduce %s', strjoin(bad, ', '));
end
claim_test(X, S, sprintf('read for %s', S.bound));
for k = 2:numel(R.pols)
    x1.(R.pols{k}) = run_set(R.pols{k}, policy_pp(W, R.pols{k}), W, all_ep, S.bound, R.q, R.test_seed);
end
m = recoverable_mask(W.REC, R.rule, W.EP) & ~W.EP.slice & ~W.EP.occ;
lines = {'', '=== CORE_BW, RULE FIX: TEST (read once) ===', sprintf('Generated: %s | bound %s | H1 primary set, %d episodes', ...
    datestr(now), S.bound, nnz(m)), 'Off reproduces the registered primary rows (rule_core3, rule_core, blind_core): exact'};
ty = {'pooled', true(1, W.EP.n); 'narrowband', W.EP.narrow; 'wideband', ~W.EP.narrow};
P = struct('policy', {}, 'type', {}, 'n', {}, 'red', {}, 'lo', {}, 'hi', {}, 'per', {}, 'per_ref', {});
for v = 1:2
    x = x0; if v == 2, x = x1; end
    for p = {'rule_core3', 'rule_core', 'blind_core'}
        for t = 1:size(ty, 1)
            mt = m & ty{t, 2};
            [r, lo, hi] = per_reduction(x.(p{1}).per_post(mt), x.none.per_post(mt), W.EP.geom(mt), R.B, 3);
            lines{end+1} = sprintf('  %-4s %-10s %-10s PER %.4f vs %.4f static, reduction %5.1f%% [%5.1f, %5.1f]', ...
                ternary(v == 1, 'off', 'on'), p{1}, ty{t, 1}, mean(x.(p{1}).per_post(mt)), mean(x.none.per_post(mt)), ...
                100 * r, 100 * lo, 100 * hi); %#ok<AGROW>
            if v == 2, P(end+1) = struct('policy', p{1}, 'type', ty{t, 1}, 'n', nnz(mt), 'red', r, 'lo', lo, 'hi', hi, ...
                    'per', mean(x.(p{1}).per_post(mt)), 'per_ref', mean(x.none.per_post(mt))); end %#ok<AGROW>
        end
    end
    for t = 1:size(ty, 1)
        mt = m & ty{t, 2};
        [d, lo, hi] = boot_cluster(x.rule_core3.per_post(mt) - x.blind_core.per_post(mt), ones(1, nnz(mt)), W.EP.geom(mt), R.B, 6);
        lines{end+1} = sprintf('  %-4s CNN contribution %-10s rule_core3 - blind_core: PER %+.4f [%+.4f, %+.4f]', ...
            ternary(v == 1, 'off', 'on'), ty{t, 1}, d, lo, hi); %#ok<AGROW>
    end
end
[~, vl] = core_bw_rules('per_verdicts', P, 0.30, true);
lines = [lines, {'Verdict words with the setting bound (the registered verdicts stand beside them):'}, vl];
lines{end+1} = sprintf('Test done in %.1f min.', toc(t0) / 60);
x1s = structfun(@keep_fields, x1, 'UniformOutput', false);
read_once('save', X.test, struct('x1s', x1s, 'P', P));
read_once('write', X.txt, [splitlines(strtrim(fileread(X.txt)))', lines]);
fprintf('%s\n', lines{:});
end

function claim_test(X, S, what)
% The tree's side test is spent: the per-tree marker (whatever the tag) and the tag's own.
txt = {sprintf('core_bw_rule_fix test %s %s', what, datestr(now, 31)), ['tree ' S.fingerprint.tree], ['tag ' X.tag], ...
    ['code ' S.fingerprint.code], ['selection ' X.sel]};
read_once('write', X.claim_test, txt);
read_once('write', X.marker, txt);
end

%% ===================== The study's machinery (experiment_core_bw.m at 75bea00) =====================
function W = world(X, sp)
% The study's pools, frozen choices and episodes of split sp, as experiment_core_bw.m reads them.
J = jsondecode(fileread(X.S.proto));
assert(strcmp(params_id(load('params.mat').params), J.params_id), 'core_bw_rule_fix_reading:params', ...
    'params.mat names another link model than the frozen protocol');
PP = load_pools(X.S.pools);
assert(strcmp(J.params_id, PP.params_id) && strcmp(J.det_id, PP.det_id), 'core_bw_rule_fix_reading:pools', ...
    'the pools are not those the protocol was frozen on');
core_bw_rules('core3_pools', PP, J.core3_sha256, J.core3_N);
cref = core_bw_rules('clean_ref', clean_ber_ref(9, 'ber_est'), clean_ber_ref(9, 'ber'));
assert(strcmp(J.clean_ber_est_9db, sprintf('%.17g', cref)), 'core_bw_rule_fix_reading:clean_ref', ...
    'the clean reference at 9 dB is not the one validation froze');
f = 'data/trained_dqn.mat';
v = intersect(who('-file', f), {'det_id', 'dec', 'confirm', 'alarm_mode', 'drop_db', 'maha_thr', 'H', 'model_tag'});
Q = load(f, v{:});
check_det_id(PP, Q, 'core_bw_rule_fix_reading');
PP = decision_settings(PP, Q);
p0 = load('params.mat').params; B = band_plan(p0);
K = link_env('tables', PP, 'flight');
W = struct('PP', PP, 'K', K, 'J', J, 'X', X, 'REC', read_recoverable(X.S.recov));
W.EP = episodes(X, PP, sp, B);
end

function Pp = policy_pp(W, pol)
% The frozen choices of the test stage: W (W3 for rule_core3) and blind_core's first response.
Pp = W.PP; r = reg().rule;
Pp.core_wide = W.J.w.(r); Pp.core_blind = W.J.blind_first.(r); Pp.core_wide_valid = true;   % frozen on validation
if strcmp(pol, 'rule_core3'), Pp.core_wide = W.J.w3.(r); end
end

function R = run_set(pol, PPx, W, idx, fix, q, seed0)
% One policy on the episodes idx with the layered answers fix ('' off), as experiment_core_bw.m's
% run_set (the 'sheet' residual, static jammer, split from the world).
if isempty(idx), R = struct('ep', zeros(1, 0)); return; end
na = W.K.na;
Qs = struct('agent', [], 'agents', {{}}, 'rule_sel', []);
[kind, ~, opt] = policy_setup(pol, Qs, 1, 1, 1, [], na);
if ~isempty(fix), PPx.rule_fix = fix; end
R = policy_run_set(kind, PPx, W.K, make_specs(W.X, W.EP, idx, q, false, 'sheet'), W.EP.split, [], opt, seed0);
R.ep = idx;
end

function EP = episodes(X, PP, sp, B)
% experiment_core_bw.m's episodes (75bea00), unchanged.
scen = PP.scenarios; nS = numel(PP.ebno); nG = X.NGEO(sp); T = X.T;
C = decision_config();
rs = RandStream('mt19937ar', 'Seed', 2030 + sp);
ONS = randi(rs, [3 10], nS, nG, X.REPS); FD = randi(rs, C.fdelay, nS, nG, X.REPS);
[k, s, r, e] = ndgrid(1:numel(scen), 1:nS, 1:nG, 1:X.REPS);
n = numel(k);
EP = struct('k', k(:)', 's', s(:)', 'r', r(:)', 'rep', e(:)', 'n', n, 'T', T);
EP.c = [scen(EP.k).cell] + 1;
EP.onset = ONS(sub2ind(size(ONS), EP.s, EP.r, EP.rep)); EP.fdelay = FD(sub2ind(size(FD), EP.s, EP.r, EP.rep));
EP.slice = [scen(EP.k).slice]; EP.bj = [scen(EP.k).bj]; EP.tot = [scen(EP.k).jsr_tot]; EP.inb = [scen(EP.k).jsr_in];
EP.occ = [scen(EP.k).occ];
EP.narrow = EP.bj == 0;
EP.rel = arrayfun(@(i) ~strcmp(scen(i).J.kind, 'fixed'), EP.k);
EP.home = zeros(1, n); EP.rej1 = zeros(1, n);
for q = 1:numel(X.RULES)
    EP.cover{q} = false(n, T); EP.cover30{q} = false(n, T); EP.acr{q} = ones(n, T); EP.part{q} = false(n, T);
    EP.near{q} = false(n, T); EP.err{q} = zeros(n, T, 'single');
end
for i0 = find(EP.rep == 1)
    J = scen(EP.k(i0)).J; g = PP.acr_grid{scen(EP.k(i0)).cell};
    rsh = seed_stream(PP.seed{sp}(EP.s(i0), EP.r(i0)), 'hop');
    for rep = 1:X.REPS
        i = i0 + (rep - 1) * numel(scen) * nS * nG;
        can = true(1, numel(B.f_mhz));
        if strcmp(J.kind, 'fixed'), can = band_cover(band_cover('span', J, NaN), B.f_mhz, B.b_ch); end
        h = hop_targets('home', can, [], rsh);
        c1 = hop_targets('H1', h, T, rsh, B);
        spn = band_cover('span', J, B.f_mhz(h));
        [cv, st] = band_cover(spn, B.f_mhz, B.b_ch);
        R = band_reject(J, B.f_mhz(h), B);
        li = band_reject('layer', R, g); ce = li == 0;
        assert(all(li(R > 0) > 0), 'experiment_core_bw:acr', 'an escaped channel below its cell''s lowest layer');
        lv = zeros(size(R)); er = zeros(size(R));
        [~, lv(~ce)] = ismember(g(li(~ce)), PP.acr_db);
        er(~ce) = R(~ce) - g(li(~ce));
        EP.home(i) = h; EP.rej1(i) = R(c1(1));
        for q = 1:numel(X.RULES)
            ch = c1; if q > 1, ch = hop_targets(X.RULES{q}, h, T, [], B); end
            EP.cover{q}(i, :) = ce(ch); EP.cover30{q}(i, :) = cv(ch); EP.part{q}(i, :) = st(ch) == 2;
            EP.acr{q}(i, :) = 1 + lv(ch); EP.err{q}(i, :) = er(ch);
            EP.near{q}(i, :) = ~cv(ch) & ce(ch);
        end
    end
end
EP.geom = 1000 * EP.s + EP.r;
EP.split = sp;
end

function specs = make_specs(X, EP, idx, q, follow, res)
% experiment_core_bw.m's make_specs (75bea00), unchanged.
n = numel(idx); nb = ceil(n / X.NE); pad = nb * X.NE - n;
ii = idx(mod(0:n + pad - 1, n) + 1);
specs = cell(1, nb);
for b = 1:nb
    j = ii((b - 1) * X.NE + (1:X.NE));
    sheet = strcmp(res, 'sheet');
    if sheet, cv = EP.cover{q}(j, :); else, cv = EP.cover30{q}(j, :); end
    sp = struct('scn', EP.c(j), 's', EP.s(j), 'r', EP.r(j), 'onset', EP.onset(j), 'follow', repmat(follow, 1, X.NE), ...
        'fdelay', EP.fdelay(j), 'unk', false(1, X.NE), 'T', X.T, 'cover', cv, 'cover_rel', EP.rel(j));
    if sheet, sp.acr = EP.acr{q}(j, :); end
    specs{b} = sp;
end
if nb > 0, specs{end}.n_valid = X.NE - pad; end
end

function PP = load_pools(f)
% experiment_core_bw.m's load_pools(X, true) (75bea00), unchanged.
L = load(f, 'PP'); PP = L.PP;
PP.acr_pools = cell(1, numel(PP.alt_pools));
PP.acr_have = false(size(PP.pools, 1), numel(PP.alt_pools));
for v = 1:numel(PP.alt_pools)
    Q = PP.pools; e = ~cellfun(@isempty, PP.alt_pools{v});
    Q(e) = PP.alt_pools{v}(e);
    PP.acr_pools{v} = Q;
    PP.acr_have(:, v) = any(e(:, :), 2);
end
PP = rmfield(PP, 'alt_pools');
end

function REC = read_recoverable(f)
t = strtrim(splitlines(fileread(f)));
t = t(~cellfun(@isempty, t) & ~startsWith(t, '#'));
c = cellfun(@(x) strsplit(x, ' '), t, 'UniformOutput', false);
REC = struct('rule', {cellfun(@(x) x{1}, c, 'UniformOutput', false)'}, 'k', cellfun(@(x) str2double(x{2}), c)', ...
    's', cellfun(@(x) str2double(x{3}), c)', 'harm', cellfun(@(x) str2double(x{end - 1}), c)' > 0, ...
    'ok', cellfun(@(x) str2double(x{end}), c)' > 0);
end

function m = recoverable_mask(REC, rule, EP)
j = find(strcmp(REC.rule, rule) & REC.ok);
m = false(1, EP.n);
for i = j, m = m | (EP.k == REC.k(i) & EP.s == REC.s(i)); end
end

%% ===================== Helpers =====================
function [m, lb, ub] = cboot(x, cl, seed)
% Mean of x with its one-sided 95% bounds by a cluster bootstrap (whole flights resampled).
x = double(x(:)'); cl = cl(:)'; ok = isfinite(x); x = x(ok); cl = cl(ok);
m = mean(x); lb = NaN; ub = NaN;
[u, ~, g] = unique(cl);
if numel(u) < 2, return; end
s = accumarray(g(:), x(:))'; c = accumarray(g(:), 1)';
rs = RandStream('mt19937ar', 'Seed', seed); B = reg().B; v = zeros(1, B);
for b = 1:B
    k = randi(rs, numel(u), 1, numel(u));
    v(b) = sum(s(k)) / sum(c(k));
end
v = sort(v); lb = v(max(1, round(0.05 * B))); ub = v(round(0.95 * B));
end

function r = keep_fields(R)
f = intersect(fieldnames(R), {'ep', 'scn', 'geom', 'recovered', 'held', 'recoverable', 'threat', 'per_post', 'dlv_post', ...
    't_rec_det', 'false_sw', 'switches'});
r = struct(); for i = 1:numel(f), r.(f{i}) = R.(f{i}); end
end

function u = cp_upper(k, n)
if n == 0, u = NaN; elseif k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

function t = name_txt(n)
if isempty(n), t = 'off (today''s core rule)'; else, t = n; end
end

function t = ok_txt(c)
t = ternary(c, 'ok', 'FAILS');
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
