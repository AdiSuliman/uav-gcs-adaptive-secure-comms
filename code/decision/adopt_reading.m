function out = adopt_reading(stage, varargin)
%ADOPT_READING  Adoption of a frozen side reading into a finished tree's outputs, written beside them
%   in an overlay of this checkout, results/rule_fix/<tag>/adopted/. The tree's code, HEAD and files
%   are never written; every file of this stage is written whole and once.
%   adopt_reading('overlay', tag, tree, O)   builds the overlay, refused when it exists:
%       adoption.json   the manifest: tag, tree, tree_head, the adoptions in the order they apply
%                       ({name, setting, the SHA-256 of selection.json, val.mat, test.mat}), created
%       tree_sha256.txt the SHA-256 of the tree's registered results and inputs (results/**,
%                       params.mat, profile.json, data/*.mat)
%       overlay.txt     what the overlay changes outside itself: the read-only attribute below
%       off/, on/       two roots, each with copies of params.mat, profile.json and results/ (dates
%                       kept), less the outputs its own stages write (so none is overwritten), and
%                       data/*.mat as read-only hard links (refused across volumes; the read-only
%                       attribute belongs to the file, so the tree's data/*.mat are read-only too
%                       until the release stage)
%       The checkout's code is pinned: refused with uncommitted .m files under code/ (tests/
%       aside); its HEAD and the SHA-256 of its code/**/*.m are recorded, and every later stage
%       refuses when either moved.
%   adopt_reading('off', tag, tree, O)   ADOPT0 in off/: the tree's KPI, dashboard, report-number,
%       KPI-table and bundle code on the registered policy_evaluation.mat; every output must equal
%       the tree's final phase (the 'Generated' stamps excepted), the bundle the final phase's
%       (O.bundle_ref), the stale-file count the tree's; the code must be the tree's but for the
%       adoption's own files -> off.json, off.txt; any mismatch stops
%   adopt_reading('c2e', tag, tree, O)   ADOPT-C2e in on/: evaluate_policies.m with CFG.adopt from
%       the manifest, each rule row through its own monitor (adopt_options.m). Refused unless off
%       passed, at any thread count but C2e's (maxNumCompThreads 8), when the tree differs from
%       tree_sha256.txt, or when the code would not run from this checkout. Guards: every non-rule
%       column isequaln to the registered file (RES, ALL, RW, RS2, LBC less its rule column, KP
%       less the rule's entries); the rule columns of sets 1-5 isequaln to test.mat's 'on' rows on
%       the fields it kept; KP.lect equal to test.mat's LK1 wherever its LK0 equals the registered
%       KP.lect, with at least one value the setting changed among them (every one where the tree's
%       lect_kpis.m is the reading's); the tree's SHA-256 the same after. The descriptive rule rows
%       and sets 6 on are read once with the setting, no reference -> c2e.json (with the SHA-256 of
%       each output), c2e.txt
%   adopt_reading('gate', tag, tree, O)   val.mat's gate under the adopted setting must deploy the
%       registered deployed policy (data/trained_dqn.mat), else it stops -> gate.json, gate.txt
%   adopt_reading('render', tag, tree, O)   in on/: KPI, dashboard, report numbers, KPI table and the
%       bundle, refused unless the gate passed and the outputs c2e checked are unchanged; the stale
%       files may differ from off only by results/edge_map.mat (not re-run: the rule without the
%       layered answer, stated in on/results/adoption_note.txt) -> render.json, render.txt
%   adopt_reading('release', tag, tree, O)   gives back the write attribute of every tree data file
%       that was writable before the overlay and closes the overlay: every stage refuses after it
%       -> release.json, release.txt
%   tag: the reading's name (p1, p3); tree: the finished tree. O (optional): root (this checkout,
%   default project_root()), rf_dir (selection.json, val.mat, test.mat; default
%   results/rule_fix/<tag> of root), bundle_ref (the final phase's bundle folder; default
%   <the tree's parent>/uav-gcs-v7/profiles).
%   Order: overlay -> off -> c2e -> gate -> render, each once. A later adoption (dqn_hop) enters the
%   manifest's list after rule_fix; adopt_options.m refuses it until it is implemented, with its own
%   stages (a write-once adoption_<k>.json extending the list and its own root).
%   Helpers: X = adopt_reading('paths', tag, O); G = adopt_reading('guard_c2e', N, E, T, opt)
%   (opt.lect_strict, default true);
%   C = adopt_reading('compare', a, b); adopt_reading('write_once', f, lines);
%   D = adopt_reading('code_diff', root, tree); CFG = adopt_reading('cfg', M);
%   h = adopt_reading('sha', f); F = adopt_reading('tree_files', tree)
out = [];
switch stage
    case 'overlay',    out = stage_overlay(varargin{:});
    case 'off',        out = stage_off(varargin{:});
    case 'c2e',        out = stage_c2e(varargin{:});
    case 'gate',       out = stage_gate(varargin{:});
    case 'render',     out = stage_render(varargin{:});
    case 'release',    out = stage_release(varargin{:});
    case 'paths',      out = paths(varargin{:});
    case 'guard_c2e',  out = guard_c2e(varargin{:});
    case 'compare',    [ok, why] = compare_file(varargin{:}); out = struct('ok', ok, 'why', why);
    case 'write_once', write_once(varargin{:});
    case 'code_diff',  out = code_diff(varargin{:});
    case 'cfg',        out = cfg_of(varargin{:});
    case 'sha',        out = sha_file(varargin{:});
    case 'tree_files', out = tree_files(canon(varargin{1}));
    otherwise, error('adopt_reading:stage', 'adopt_reading: unknown stage %s', stage);
end
end

%% ===================== Registered constants =====================
function K = reg()
K.final = {'results/kpi_summary.txt', 'results/kpi_summary.mat', 'results/kpi_dashboard.png', 'results/report_numbers.json'};
K.table = {'results/lect_kpi_table.txt', 'results/lect_kpi_table.csv', 'results/lect_kpi_per.png', ...
    'results/lect_kpi_recovery.png', 'results/lect_kpi_goodput.png'};
K.render_out = [K.final, K.table];
K.c2e_out = {'results/policy_evaluation.txt', 'results/policy_evaluation.mat', 'results/policy_evaluation.png', ...
    'results/policy_breakdown.png'};
K.may_differ = {'decision/adopt_options.m', 'decision/adopt_reading.m', 'decision/evaluate_policies.m', ...
    'decision/policy_decide.m', 'decision/rule_based_policy.m', 'decision/decision_settings.m', 'decision/policy_stamp.m', ...
    'decision/rule_fix.m', 'decision/rule_fix_reading.m', 'decision/read_once.m', 'decision/core_bw_rule_fix_reading.m', ...
    'evaluation/calibration_reading.m'};
K.rule_base = {'rule', 'rule_esc', 'blind_esc', 'rule_core', 'blind_core', 'rule_sel', 'rule_core3'};
K.keep = {'scn', 's', 'r', 'geom', 'recovered', 'held', 'recoverable', 'recoverable_core', 'threat', 'per_post', ...
    'switches', 'ret', 't_rec'};
K.sets_guarded = 5;
K.stages = {'overlay', 'off', 'c2e', 'gate', 'render'};
K.threads = 8;                                        % C2e's thread count
K.code_fns = {'evaluate_policies', 'adopt_options', 'lect_kpis', 'measure_all_kpis'};
% KP fields built from the rule's columns: compared on their non-rule columns or entries only
K.kp_rule = {'per_threat', 'per_threat_sev', 'per_threat_h', 'per_threat_h_sev', 'per_ebno', 'per_aoa', 'per_speed', ...
    'per_speed_out', 'per_delay', 'far', 'far_diag', 'far_testpools', 'far_diag_testpools', 'far_cleanpools', ...
    'far_diag_cleanpools', 'far_core3', 'far_union', 'far_diag_union', 'offset', 'lect', 's1g_lines'};
K.stale_add = {'results/edge_map.mat'};               % not re-run: older than the new policy_evaluation.mat
K.stale_drop = {'results/policy_evaluation.mat'};
K.note_file = 'results/adoption_note.txt';
end

%% ===================== Files =====================
function X = paths(tag, O)
if nargin < 2 || isempty(O), O = struct(); end
assert(ischar(tag) && ~isempty(regexp(tag, '^[A-Za-z0-9_]+$', 'once')), 'adopt_reading:tag', ...
    'adopt_reading: the tag is letters, digits and _');
X.tag = tag;
X.root = canon(opt_field(O, 'root', project_root()));
X.rf = opt_field(O, 'rf_dir', fullfile(X.root, 'results', 'rule_fix', tag));
X.dir = fullfile(X.root, 'results', 'rule_fix', tag, 'adopted');
X.man = fullfile(X.dir, 'adoption.json'); X.sha = fullfile(X.dir, 'tree_sha256.txt');
X.off = fullfile(X.dir, 'off'); X.on = fullfile(X.dir, 'on'); X.logs = fullfile(X.dir, 'logs');
X.ovt = fullfile(X.dir, 'overlay.txt');
for s = {'off', 'c2e', 'gate', 'render', 'release'}
    X.v.(s{1}) = fullfile(X.dir, [s{1} '.json']); X.t.(s{1}) = fullfile(X.dir, [s{1} '.txt']);
end
end

function Sx = sources(rf)
% The frozen reading: selection.json (hashed without carriage returns: a checkout may convert line
% ends), val.mat and test.mat.
Sx = struct('dir', rf, 'sel', fullfile(rf, 'selection.json'), 'val', fullfile(rf, 'val.mat'), 'test', fullfile(rf, 'test.mat'));
for f = {Sx.sel, Sx.val, Sx.test}
    assert(isfile(f{1}), 'adopt_reading:sources', 'adopt_reading: %s is missing', f{1});
end
Sx.h = struct('selection', text_sha(Sx.sel), 'val', sha_file(Sx.val), 'test', sha_file(Sx.test));
end

function S = check_selection(Sx, tag, tree)
S = jsondecode(fileread(Sx.sel));
assert(isfield(S, 'tag') && strcmp(S.tag, tag), 'adopt_reading:selection', 'adopt_reading: %s is not the selection of %s', Sx.sel, tag);
assert(isfield(S, 'fingerprint') && isfield(S.fingerprint, 'tree') && strcmpi(S.fingerprint.tree, tree), ...
    'adopt_reading:selection', 'adopt_reading: %s was frozen on another tree (%s)', Sx.sel, field_txt(S, 'tree'));
assert(isfield(S, 'adopted') && ~isempty(S.adopted), 'adopt_reading:selection', 'adopt_reading: %s adopted nothing', Sx.sel);
F = rule_fix('parse', S.adopted);
assert(F.on && strcmp(F.name, S.adopted), 'adopt_reading:selection', 'adopt_reading: %s holds no canonical setting', Sx.sel);
end

function [M, X, Sx] = open_overlay(tag, tree, O)
% The overlay of (tag, tree) with its manifest; the frozen reading, the tree's HEAD and the checkout's
% HEAD and code as the manifest recorded them; refused once released.
X = paths(tag, O);
assert(isfile(X.man), 'adopt_reading:no_overlay', 'adopt_reading: no overlay at %s (run the overlay stage first)', X.dir);
assert(~isfile(X.v.release), 'adopt_reading:released', 'adopt_reading: the overlay %s was released; no stage runs on it', X.dir);
M = jsondecode(fileread(X.man));
assert(strcmp(M.tag, tag) && strcmpi(M.tree, tree), 'adopt_reading:tree', 'adopt_reading: the overlay %s belongs to %s', X.dir, M.tree);
names = order_of(M);
assert(strcmp(names{1}, 'rule_fix'), 'adopt_reading:order', 'adopt_reading: the first adoption is rule_fix');
if iscell(M.adoptions), A = M.adoptions{1}; else, A = M.adoptions(1); end
Sx = sources(A.source);
ok = strcmp(Sx.h.selection, A.selection_sha256) && strcmp(Sx.h.val, A.val_sha256) && strcmp(Sx.h.test, A.test_sha256);
assert(ok, 'adopt_reading:sources', 'adopt_reading: selection.json, val.mat or test.mat in %s differ from the manifest', Sx.dir);
assert(strcmp(tree_head(tree), M.tree_head), 'adopt_reading:head', 'adopt_reading: the HEAD of %s moved since the overlay', tree);
assert(isfield(M, 'checkout_code_sha256') && strcmp(tree_head(X.root), M.checkout_head) && ...
    strcmp(code_sha(X.root), M.checkout_code_sha256), 'adopt_reading:code', ...
    'adopt_reading: the HEAD or the code of the checkout %s moved since the overlay', X.root);
end

function names = order_of(M)
% The adoptions' names, every one known, in the order adopt_options.m applies them.
assert(isfield(M, 'adoptions') && ~isempty(M.adoptions), 'adopt_reading:order', 'adopt_reading: the manifest lists no adoption');
if iscell(M.adoptions), names = cellfun(@(a) a.name, M.adoptions, 'UniformOutput', false);
else, names = {M.adoptions.name}; end
[tf, loc] = ismember(names, adopt_options('names'));
assert(all(tf) && all(diff(loc) > 0), 'adopt_reading:order', 'adopt_reading: adoptions %s are not in the known order %s', ...
    strjoin(names, ', '), strjoin(adopt_options('names'), ', '));
end

function CFG = cfg_of(M)
% CFG.adopt of the manifest's adoptions, checked by adopt_options.m.
names = order_of(M);
CFG = struct('adopt', struct());
for k = 1:numel(names)
    if iscell(M.adoptions), a = M.adoptions{k}; else, a = M.adoptions(k); end
    CFG.adopt.(names{k}) = a.setting;
end
adopt_options(CFG);
end

%% ===================== Stage: overlay =====================
function M = stage_overlay(tag, tree, O)
if nargin < 3, O = struct(); end
tree = canon(tree); X = paths(tag, O); K = reg();
assert(isfolder(tree) && isfile(fullfile(tree, 'results', 'policy_evaluation.mat')) && isfile(fullfile(tree, 'data', 'trained_dqn.mat')), ...
    'adopt_reading:tree', 'adopt_reading: %s is not a finished tree (results/policy_evaluation.mat, data/trained_dqn.mat)', tree);
assert(~under(X.dir, tree) && ~under(tree, X.dir) && ~strcmpi(X.root, tree), 'adopt_reading:inside', ...
    'adopt_reading: the overlay %s would lie inside the tree %s', X.dir, tree);
assert(~isfolder(X.dir), 'adopt_reading:exists', 'adopt_reading: the overlay %s exists; it is built once', X.dir);
dirty = code_dirty(X.root);
assert(isempty(dirty), 'adopt_reading:dirty', 'adopt_reading: the checkout %s has uncommitted code: %s', X.root, strjoin(dirty, ', '));
Sx = sources(X.rf);
S = check_selection(Sx, tag, tree);
F = tree_files(tree);
H = hash_lines(tree, F);
mkdir(X.dir);
write_once(X.sha, H);
dl = F(startsWith(F, 'data/'));
ro0 = dl(cellfun(@(f) ~java.io.File(fullfile(tree, f)).canWrite(), dl));
write_once(X.ovt, {sprintf(['The data files of off/ and on/ are hard links to %s/data, made read-only. The attribute belongs ' ...
    'to the file: those %d tree files are read-only too (contents and dates unchanged; %d were read-only before). ' ...
    'adopt_reading(''release'', ''%s'', tree) gives the attribute back and closes the overlay.'], tree, numel(dl), numel(ro0), tag)});
left = struct('off', {K.render_out}, 'on', {[K.render_out, K.c2e_out]});
for r = {'off', 'on'}
    root = X.(r{1});
    for i = 1:numel(F)
        src = fullfile(tree, F{i}); dst = fullfile(root, F{i});
        if startsWith(F{i}, 'data/'), link_ro(src, dst);
        elseif ~ismember(F{i}, left.(r{1})), copy_keep(src, dst); end
    end
end
A = struct('name', 'rule_fix', 'setting', S.adopted, 'selection_sha256', Sx.h.selection, 'val_sha256', Sx.h.val, ...
    'test_sha256', Sx.h.test, 'source', Sx.dir);
M = struct('tag', tag, 'tree', tree, 'tree_head', tree_head(tree), 'checkout', X.root, 'checkout_head', tree_head(X.root), ...
    'checkout_code_sha256', code_sha(X.root), 'version', 1, 'adoptions', {{A}}, 'order', {K.stages}, 'roots', struct('off', 'off', 'on', 'on'), ...
    'left_out', left, 'data_links', {dl}, 'readonly_before', {ro0}, 'tree_sha256_file', 'tree_sha256.txt', ...
    'tree_sha256_list', sha_file(X.sha), 'n_files', numel(F), 'created', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
write_once(X.man, {jsonencode(M, 'PrettyPrint', true)});
M = jsondecode(fileread(X.man));
end

%% ===================== Stage: off (ADOPT0) =====================
function V = stage_off(tag, tree, O)
if nargin < 3, O = struct(); end
tree = canon(tree); [M, X] = open_overlay(tag, tree, O); K = reg();
assert(~isfile(X.v.off), 'adopt_reading:exists', 'adopt_reading: %s exists; ADOPT0 runs once', X.v.off);
assert(~any(cellfun(@(f) isfile(fullfile(X.off, f)), K.render_out)) && ~isfolder(fullfile(X.off, 'profiles')), ...
    'adopt_reading:exists', 'adopt_reading: %s already holds rendered outputs', X.off);
bref = opt_field(O, 'bundle_ref', fullfile(fileparts(tree), 'uav-gcs-v7', 'profiles'));
rows = struct('file', {}, 'ok', {}, 'why', {});
D = code_diff(X.root, tree);
rows(end+1) = row('code', isempty(D.bad), sprintf('differs from the tree only in the adoption''s own files (%s)%s', ...
    strjoin(D.differ, ', '), list_txt(' NOT the tree''s: ', D.bad)));
[pok, pwhy] = path_ok(X, tree);
rows(end+1) = row('path', pok, pwhy);
if all([rows.ok])
    lg = start_log(X, 'off'); %#ok<NASGU>
    tab = has_table(tree);
    s0 = snapshot(tree); b0 = dir_state(bref);
    err = render_in(X.off, tab);
    rows(end+1) = row('renderers', isempty(err), list_txt('ran: ', err));
    s1 = snapshot(tree); b1 = dir_state(bref);
    rows(end+1) = row('tree untouched', isequal(s0, s1), snap_why(s0, s1, 'the tree but .git and logs/'));
    rows(end+1) = row('bundle reference untouched', isequal(b0, b1), snap_why(b0, b1, bref));
    for f = K.final
        [ok, why] = compare_file(fullfile(X.off, f{1}), fullfile(tree, f{1}));
        rows(end+1) = row(f{1}, ok, why); %#ok<AGROW>
    end
    if tab
        for f = K.table
            if isfile(fullfile(tree, f{1})), [ok, why] = compare_file(fullfile(X.off, f{1}), fullfile(tree, f{1}));
            else, ok = isfile(fullfile(X.off, f{1})); why = 'not in the tree''s final phase: produced here, nothing to compare'; end
            rows(end+1) = row(f{1}, ok, why); %#ok<AGROW>
        end
    end
    rx = rx_dir(X.off);
    rows = [rows, compare_bundle(fullfile(X.off, 'profiles', rx), fullfile(bref, rx))];
    rows(end+1) = stale_row(fullfile(X.off, 'results', 'report_numbers.json'), fullfile(tree, 'results', 'report_numbers.json'));
end
V = verdict(X, 'off', rows, struct('bundle_ref', bref, 'code_sha256', M.checkout_code_sha256));
if ~V.pass, error('adopt_reading:off', 'adopt_reading: ADOPT0 does not reproduce the final phase (see %s); nothing further runs', X.t.off); end
end

%% ===================== Stage: c2e =====================
function V = stage_c2e(tag, tree, O)
if nargin < 3, O = struct(); end
tree = canon(tree); [M, X, Sx] = open_overlay(tag, tree, O); K = reg();
Vo = read_verdict(X.v.off);
assert(~isempty(Vo) && isequal(Vo.pass, true), 'adopt_reading:off_not_passed', ...
    'adopt_reading: ADOPT-C2e is refused: ADOPT0 has not passed (%s)', X.v.off);
assert(~isfile(X.v.c2e) && ~any(cellfun(@(f) isfile(fullfile(X.on, f)), K.c2e_out)), 'adopt_reading:exists', ...
    'adopt_reading: %s or the outputs of evaluate_policies.m in %s exist; ADOPT-C2e runs once', X.v.c2e, X.on);
nt = maxNumCompThreads;
assert(nt == K.threads, 'adopt_reading:threads', ['adopt_reading: ADOPT-C2e runs at %d threads, as C2e ran, and the ' ...
    'reproduction depends on it (maxNumCompThreads is %d; set maxNumCompThreads(%d))'], K.threads, nt, K.threads);
CFG = cfg_of(M); A = adopt_options(CFG);
L0 = read_lines(X.sha);
H0 = hash_lines(tree, tree_files(tree));
assert(isequal(H0, L0), 'adopt_reading:tree_changed', 'adopt_reading: the tree differs from %s', X.sha);
[pok, pwhy] = path_ok(X, tree);
assert(pok, 'adopt_reading:path', 'adopt_reading: ADOPT-C2e is refused: %s, not from %s', pwhy, fullfile(X.root, 'code'));
strict = isfile(fullfile(X.root, 'code', 'decision', 'rule_fix_reading.m')) && ...
    same_text(fullfile(X.root, 'code', 'evaluation', 'lect_kpis.m'), fullfile(tree, 'code', 'evaluation', 'lect_kpis.m'));
lg = start_log(X, 'c2e'); %#ok<NASGU>
rows = struct('file', {}, 'ok', {}, 'why', {});
t0 = tic; err = '';
c0 = cd(X.on);
try
    run_c2e(CFG);
catch e
    err = e.message;
end
cd(c0);
rows(end+1) = row('evaluate_policies', isempty(err), sprintf('%s; %.1f min, %d threads', ternary(isempty(err), 'ran', err), toc(t0) / 60, nt));
H1 = hash_lines(tree, tree_files(tree));
rows(end+1) = row('tree SHA-256', isequal(H1, H0), sprintf('%d files of results and inputs, before and after', numel(H0)));
if isempty(err)
    k = find(endsWith(L0, '  results/policy_evaluation.mat'), 1);
    reg_ok = ~isempty(k) && strcmp(L0{k}(1:64), sha_file(fullfile(X.off, 'results', 'policy_evaluation.mat')));
    rows(end+1) = row('registered file', reg_ok, 'the off root''s copy is the tree''s results/policy_evaluation.mat');
    N = load(fullfile(X.on, 'results', 'policy_evaluation.mat'));
    E = load(fullfile(X.off, 'results', 'policy_evaluation.mat'));
    T = load(Sx.test);
    G = guard_c2e(N, E, T, struct('lect_strict', strict));
    rows = [rows, G.rows];
end
Ho = out_hashes(X.on, K.c2e_out);
V = verdict(X, 'c2e', rows, struct('setting', A.rule_fix, 'threads', nt, 'lect_strict', strict, 'outputs', {Ho}, ...
    'code_sha256', M.checkout_code_sha256));
if ~V.pass, error('adopt_reading:c2e', 'adopt_reading: ADOPT-C2e failed its guards (see %s)', X.t.c2e); end
end

function run_c2e(CFG) %#ok<INUSD>
% evaluate_policies.m in this workspace: it reads CFG (CFG.adopt) from here.
run('evaluate_policies');
end

function G = guard_c2e(N, E, T, opt)
% The adopted file N against the registered one E and test.mat T. opt.lect_strict (default true):
% every KP.lect value the setting changed must be compared.
if nargin < 4 || ~isstruct(opt), opt = struct(); end
strict = ~isfield(opt, 'lect_strict') || isequal(opt.lect_strict, true);
K = reg(); r = struct('file', {}, 'ok', {}, 'why', {});
vs = isequal(sort(fieldnames(N)), sort(fieldnames(E)));
r(end+1) = row('variables', vs, sprintf('registered %s; adopted %s', strjoin(sort(fieldnames(E))', ', '), ...
    strjoin(sort(fieldnames(N))', ', ')));
for f = {'POL', 'LBL', 'set_names', 'iDQN', 'iThreat', 'fixed_best', 'tab', 'top_cfg'}
    if ~isfield(E, f{1}), continue; end
    e = isfield(N, f{1}) && isequaln(N.(f{1}), E.(f{1}));
    r(end+1) = row(f{1}, e, ternary(e, 'as registered', 'differs from the registered file')); %#ok<AGROW>
end
POL = E.POL; isr = cellfun(@(p) adopt_options('rule_row', p), POL);
sz = isfield(N, 'RES') && isequal(size(N.RES), size(E.RES));
r(end+1) = row('RES', sz, sprintf('%d sets x %d policies, %d rule rows', size(E.RES, 1), numel(POL), sum(isr)));
if ~sz, G = struct('pass', false, 'rows', r); return; end
nS = size(E.RES, 1);
bad = {};
for c = reshape(find(~isr), 1, [])
    for si = 1:nS
        if ~isequaln(N.RES{si, c}, E.RES{si, c}), bad{end+1} = sprintf('%s set %d', POL{c}, si); end %#ok<AGROW>
    end
    if ~isequaln(cell_at(N, 'ALL', c), cell_at(E, 'ALL', c)), bad{end+1} = sprintf('%s pooled', POL{c}); end %#ok<AGROW>
    if ~isequaln(cell_at(N, 'RW', c), cell_at(E, 'RW', c)), bad{end+1} = sprintf('%s clean pools', POL{c}); end %#ok<AGROW>
end
if ~isequal(numel(field_or(N, 'RW', {})), numel(field_or(E, 'RW', {}))), bad{end+1} = 'RW size'; end
if ~isequaln(field_or(N, 'RS2', []), field_or(E, 'RS2', [])), bad{end+1} = 'RS2 (the deployed policy, second test split)'; end
if ~isequaln(lbc_strip(field_or(N, 'LBC', [])), lbc_strip(field_or(E, 'LBC', []))), bad{end+1} = 'LBC (DQN columns)'; end
r(end+1) = row('non-rule columns', isempty(bad), sprintf('%d columns x %d sets, pooled, clean pools, RS2, LBC%s', sum(~isr), nS, ...
    list_txt('; differ: ', bad)));
if isfield(E, 'KP') && isfield(N, 'KP')
    [bad, part] = kp_guard(N.KP, E.KP, E.LBL(isr));
    r(end+1) = row('KP', isempty(bad), sprintf(['every field isequaln to the registered KP but those built from the rule''s ' ...
        'columns, compared without them%s%s'], list_txt('; compared in part: ', part), list_txt('; differ: ', bad)));
else
    r(end+1) = row('KP', isfield(E, 'KP') == isfield(N, 'KP'), 'no KP');
end
dsc = reshape(POL(isr & ~ismember(POL, K.rule_base)), 1, []);
r(end+1) = row('descriptive rule rows', true, sprintf(['%s: read once with the setting on every set, no reference ' ...
    '(no selection on them)'], ternary(isempty(dsc), 'none', strjoin(dsc, ', '))));
want = K.rule_base(ismember(K.rule_base, POL));
tp = field_or(T, 'pols', {}); if isstring(tp), tp = cellstr(tp); end; tp = reshape(tp, 1, []);
ron = field_or(T, 'RONs', {});
lay = isequal(tp, want) && size(ron, 1) == K.sets_guarded && size(ron, 2) == numel(tp) && nS >= K.sets_guarded;
r(end+1) = row('test.mat rows', lay, sprintf('test.mat holds %s over %d sets; the rule rows here %s', strjoin(tp, ', '), ...
    size(ron, 1), strjoin(want, ', ')));
if lay
    bad = {}; nf = 0;
    for pk = 1:numel(tp)
        c = find(strcmp(POL, tp{pk}), 1);
        for si = 1:K.sets_guarded
            R = N.RES{si, c}; Ro = ron{si, pk};
            fo = fieldnames(Ro); fk = intersect(fieldnames(R), K.keep);
            if ~isequal(sort(fk(:)), sort(fo(:)))
                bad{end+1} = sprintf('%s set %d: kept fields', tp{pk}, si); continue %#ok<AGROW>
            end
            for j = 1:numel(fo)
                nf = nf + 1;
                if ~isequaln(R.(fo{j}), Ro.(fo{j})), bad{end+1} = sprintf('%s set %d %s', tp{pk}, si, fo{j}); end %#ok<AGROW>
            end
        end
    end
    r(end+1) = row('rule columns, sets 1-5', isempty(bad), sprintf('%d fields isequaln to test.mat''s on rows%s', nf, ...
        list_txt('; differ: ', bad)));
end
moved = false;
for c = reshape(find(isr), 1, [])
    for si = 1:min(K.sets_guarded, nS), moved = moved || ~isequaln(N.RES{si, c}, E.RES{si, c}); end
end
r(end+1) = row('setting applied', moved, 'some rule column of sets 1-5 differs from the registered one');
if all(isfield(T, {'LK0', 'LK1'})) && isfield(E, 'KP') && isfield(E.KP, 'lect') && isfield(N, 'KP') && isfield(N.KP, 'lect')
    Q = lk_guard(N.KP.lect, E.KP.lect, T.LK0, T.LK1);
    ok = isempty(Q.bad) && Q.nch > 0 && Q.nchc > 0 && (~strict || (isempty(Q.skip_ch) && isempty(Q.disagree)));
    r(end+1) = row('KP.lect', ok, sprintf(['%d values compared with test.mat''s LK1 (where its LK0 equals the registered ' ...
        'KP.lect), %d of the %d the setting changed; %d of LK0''s values not compared (%s)%s%s%s'], Q.n, Q.nchc, Q.nch, ...
        numel(Q.skip), ternary(strict, 'strict: the tree''s lect_kpis.m is the reading''s', 'not strict'), ...
        list_txt('; changed, not compared: ', Q.skip_ch), list_txt('; registered differs from LK0: ', Q.disagree), ...
        list_txt('; differ: ', Q.bad)));
else
    r(end+1) = row('KP.lect', false, 'test.mat (LK0, LK1) or KP.lect missing');
end
G = struct('pass', all([r.ok]), 'rows', r);
end

function Q = lk_guard(Ln, Le, L0, L1)
% Every value of LK0 that equals the registered KP.lect at the same place: the adopted KP.lect holds
% LK1's value there. nch: LK0's values LK1 changes; nchc: those compared; skip: LK0's values not
% compared; skip_ch: changed ones among them; disagree: present in both, the registered value not LK0's.
[ke, ve] = flat_kv(Le, 'lect'); [k0, v0] = flat_kv(L0, 'lect'); [k1, v1] = flat_kv(L1, 'lect'); [kn, vn] = flat_kv(Ln, 'lect');
me = kv_map(ke, ve); m1 = kv_map(k1, v1); mn = kv_map(kn, vn);
Q = struct('n', 0, 'nch', 0, 'nchc', 0, 'skip', {{}}, 'skip_ch', {{}}, 'disagree', {{}}, 'bad', {{}});
for i = 1:numel(k0)
    p = k0{i};
    ch = ~isKey(m1, p) || ~isequaln(m1(p), v0{i});
    Q.nch = Q.nch + ch;
    if ~isKey(me, p) || ~isequaln(me(p), v0{i}) || ~isKey(m1, p)
        Q.skip{end+1} = p;
        if ch, Q.skip_ch{end+1} = p; end
        if isKey(me, p) && ~isequaln(me(p), v0{i}), Q.disagree{end+1} = p; end
        continue
    end
    Q.n = Q.n + 1; Q.nchc = Q.nchc + ch;
    if ~isKey(mn, p) || ~isequaln(mn(p), m1(p)), Q.bad{end+1} = p; end
end
end

function [bad, part] = kp_guard(Nk, Ek, rlbl)
% KP field by field: a field of K.kp_rule compared without the rule's columns or entries, any other
% field whole. part: the fields compared in part, and how.
K = reg(); bad = {}; part = {};
f = union(fieldnames(Ek), fieldnames(Nk));
rshow = [];
if isfield(Ek, 'show') && iscell(Ek.show), rshow = cellfun(@(p) adopt_options('rule_row', p), Ek.show); end
for j = 1:numel(f)
    if ~isfield(Ek, f{j}) || ~isfield(Nk, f{j}), bad{end+1} = [f{j} ' (on one side only)']; continue; end %#ok<AGROW>
    a = Nk.(f{j}); b = Ek.(f{j});
    if isequaln(a, b), continue; end
    if ~ismember(f{j}, K.kp_rule), bad{end+1} = f{j}; continue; end %#ok<AGROW>
    [same, how] = nonrule_equal(a, b, rshow, rlbl);
    if ~same, bad{end+1} = f{j}; else, part{end+1} = sprintf('%s (%s)', f{j}, how); end %#ok<AGROW>
end
end

function [same, how] = nonrule_equal(a, b, rshow, rlbl)
% a against b without the rule's entries: an array whose last dimension runs over KP.show, on the
% columns of the non-rule policies; a struct array with a policy label, on the non-rule labels'
% elements; anything else not compared.
if (isnumeric(a) || islogical(a)) && (isnumeric(b) || islogical(b))
    n = numel(rshow);
    if ~isequal(size(a), size(b)), same = false; how = 'size differs'; return; end
    if n > 0 && size(a, ndims(a)) == n
        A = reshape(a, [], n); B = reshape(b, [], n);
        same = isequaln(A(:, ~rshow), B(:, ~rshow)); how = 'the non-rule columns';
        return
    end
elseif isstruct(a) && isstruct(b) && isfield(a, 'policy') && isfield(b, 'policy')
    pa = {a.policy}; pb = {b.policy};
    if all(cellfun(@ischar, [pa, pb]))
        ka = ~ismember(pa, rlbl); kb = ~ismember(pb, rlbl);
        same = isequal(pa(ka), pb(kb)) && isequaln(a(ka), b(kb)); how = 'the non-rule policies'' entries';
        return
    end
end
same = true; how = 'not compared';
end

function L = lbc_strip(L)
% The link-budget completion's readings without rule + escalation's column (sets.rule) and its
% figure in the text.
if ~isstruct(L) || isempty(L), return; end
if isfield(L, 'sets') && isstruct(L.sets) && isfield(L.sets, 'rule'), L.sets = rmfield(L.sets, 'rule'); end
for f = {'lines', 'kpi'}
    if isfield(L, f{1}) && (iscellstr(L.(f{1})) || ischar(L.(f{1})))
        L.(f{1}) = regexprep(L.(f{1}), '(rule \+ escalation\s*)[^%|;]*%', '$1<rule>%');
    end
end
end

%% ===================== Stage: gate =====================
function V = stage_gate(tag, tree, O)
if nargin < 3, O = struct(); end
tree = canon(tree); [M, X, Sx] = open_overlay(tag, tree, O);
Vc = read_verdict(X.v.c2e);
assert(~isempty(Vc) && isequal(Vc.pass, true), 'adopt_reading:c2e_not_passed', ...
    'adopt_reading: the gate is refused: ADOPT-C2e has not passed (%s)', X.v.c2e);
assert(~isfile(X.v.gate), 'adopt_reading:exists', 'adopt_reading: %s exists; the gate is read once', X.v.gate);
[ook, owhy] = outputs_ok(X, Vc);
assert(ook, 'adopt_reading:c2e_outputs', 'adopt_reading: the gate is refused: %s', owhy);
S = jsondecode(fileread(Sx.sel));
Vs = load(Sx.val, 'Vs'); Vs = Vs.Vs;
Q = load(fullfile(X.on, 'data', 'trained_dqn.mat'), 'deployed');
dep = '';
if isfield(Vs, 'gate') && isfield(Vs.gate, 'dep'), dep = Vs.gate.dep; end
CFG = cfg_of(M); st = CFG.adopt.rule_fix;
rows = struct('file', {}, 'ok', {}, 'why', {});
rows(end+1) = row('setting', strcmp(S.adopted, st), sprintf('selection.json adopted %s, the manifest %s', S.adopted, st));
rows(end+1) = row('val.mat gate', strcmp(dep, Q.deployed), sprintf(['the gate of choose_deployed.m re-read on validation with ' ...
    '%s deploys %s; registered %s'], st, dep, Q.deployed));
rows(end+1) = row('selection.json', strcmp(S.deployed_on, Q.deployed) && strcmp(S.deployed_off, Q.deployed), ...
    sprintf('deployed off %s, on %s', S.deployed_off, S.deployed_on));
V = verdict(X, 'gate', rows, struct('deployed', Q.deployed));
if ~V.pass
    error('adopt_reading:gate', ['adopt_reading: under %s the gate deploys %s, registered %s: the stage stops; the deployed ' ...
        'rows would have to be re-run (ask before going on)'], st, dep, Q.deployed);
end
end

%% ===================== Stage: render =====================
function V = stage_render(tag, tree, O)
if nargin < 3, O = struct(); end
tree = canon(tree); [M, X] = open_overlay(tag, tree, O); K = reg();
Vg = read_verdict(X.v.gate);
assert(~isempty(Vg) && isequal(Vg.pass, true), 'adopt_reading:gate_not_passed', ...
    'adopt_reading: the render is refused: the gate has not passed (%s)', X.v.gate);
assert(~isfile(X.v.render) && ~any(cellfun(@(f) isfile(fullfile(X.on, f)), [K.render_out, {K.note_file}])) && ...
    ~isfolder(fullfile(X.on, 'profiles')), ...
    'adopt_reading:exists', 'adopt_reading: %s or rendered outputs in %s exist; the render runs once', X.v.render, X.on);
Vc = read_verdict(X.v.c2e);
[ook, owhy] = outputs_ok(X, Vc);
assert(ook, 'adopt_reading:c2e_outputs', 'adopt_reading: the render is refused: %s', owhy);
[pok, pwhy] = path_ok(X, tree);
assert(pok, 'adopt_reading:path', 'adopt_reading: the render is refused: %s, not from %s', pwhy, fullfile(X.root, 'code'));
lg = start_log(X, 'render'); %#ok<NASGU>
tab = has_table(tree);
s0 = snapshot(tree);
err = render_in(X.on, tab);
rows = struct('file', {}, 'ok', {}, 'why', {});
rows(end+1) = row('renderers', isempty(err), list_txt('ran: ', err));
s1 = snapshot(tree);
rows(end+1) = row('tree untouched', isequal(s0, s1), snap_why(s0, s1, 'the tree but .git and logs/'));
[ook, owhy] = outputs_ok(X, Vc);
rows(end+1) = row('c2e outputs', ook, owhy);
outs = K.final; if tab, outs = [outs, K.table]; end
for f = outs
    a = fullfile(X.on, f{1}); b = fullfile(X.off, f{1});
    if ~isfile(a), rows(end+1) = row(f{1}, false, 'not produced'); continue; end %#ok<AGROW>
    same = false; if isfile(b), same = compare_file(a, b); end
    rows(end+1) = row(f{1}, true, sprintf('SHA-256 %s; %s', sha_file(a), ternary(same, 'as off', 'differs from off'))); %#ok<AGROW>
end
st = stale_files(fullfile(X.on, 'results', 'report_numbers.json'));
s_off = stale_files(fullfile(X.off, 'results', 'report_numbers.json'));
add = setdiff(st, s_off); drop = setdiff(s_off, st);
rows(end+1) = row('stale files', isfile(fullfile(X.on, 'results', 'report_numbers.json')) && all(ismember(add, K.stale_add)) && ...
    all(ismember(drop, K.stale_drop)), sprintf('off: %s; on: %s (allowed: added %s, dropped %s)', ...
    ternary(isempty(s_off), 'none', strjoin(s_off, ', ')), ternary(isempty(st), 'none', strjoin(st, ', ')), ...
    strjoin(K.stale_add, ', '), strjoin(K.stale_drop, ', ')));
CFG = cfg_of(M);
note = {sprintf('Adopted: %s (rule_fix %s). The rule rows of policy_evaluation.mat carry it.', strjoin(order_of(M), ', '), ...
    CFG.adopt.rule_fix), ...
    ['Not carried into the deployed monitor: the rule columns of C2g, C2u and EDGE stay as registered, the rule without ' ...
    'the layered answer. The DQN rows are unchanged.'], ...
    ['results/edge_map.mat is not re-run here: result_status.m marks it stale (older than the adopted ' ...
    'policy_evaluation.mat); its rule column is the rule without the layered answer.'], ...
    sprintf('Stale files after the render (result_status.m, report_numbers.json): %s', ternary(isempty(st), 'none', strjoin(st, ', ')))};
write_once(fullfile(X.on, K.note_file), note);
V = verdict(X, 'render', rows, struct('stale', {st}, 'note', {note}, 'code_sha256', M.checkout_code_sha256));
if ~V.pass, error('adopt_reading:render', 'adopt_reading: the render failed (see %s)', X.t.render); end
end

%% ===================== Stage: release =====================
function V = stage_release(tag, tree, O)
% The write attribute back on every tree data file that had it before the overlay (through the
% off root's link: the attribute is the file's); the overlay is closed after it.
if nargin < 3, O = struct(); end
tree = canon(tree); [M, X] = open_overlay(tag, tree, O);
dl = as_cell(M.data_links); ro = as_cell(M.readonly_before);
rows = struct('file', {}, 'ok', {}, 'why', {});
for k = 1:numel(dl)
    f = dl{k}; lnk = fullfile(X.off, f); src = fullfile(tree, f);
    if ismember(f, ro)
        rows(end+1) = row(f, ~java.io.File(src).canWrite(), 'read-only before the overlay: kept read-only'); %#ok<AGROW>
        continue
    end
    ok = isfile(lnk) && java.nio.file.Files.isSameFile(jpath(lnk), jpath(src));
    if ok, ok = fileattrib(lnk, '+w'); end
    rows(end+1) = row(f, ok && java.io.File(src).canWrite(), 'writable again, as before the overlay'); %#ok<AGROW>
end
V = verdict(X, 'release', rows, struct('note', {{'The overlay is closed: every stage refuses on it.'}}));
if ~V.pass, error('adopt_reading:release', 'adopt_reading: the release failed (see %s)', X.t.release); end
end

%% ===================== Renderers =====================
function err = render_in(root, tab)
% The final phase's KPI, DASH and RPT, the KPI table where this code has it, and the bundle, in root
% (the readers take their files relative to the current folder; the bundle from root into
% root/profiles). A failed step stops the rest, as in the chain.
c0 = cd(root); back = onCleanup(@() cd(c0)); %#ok<NASGU>
steps = {'KPI', 'measure_all_kpis'; 'DASH', 'build_kpi_dashboard'; 'RPT', 'export_report_numbers'};
if tab, steps(end+1, :) = {'TABLE', ''}; end
steps(end+1, :) = {'BUNDLE', ''};
err = {};
for k = 1:size(steps, 1)
    try
        switch steps{k, 1}
            case 'TABLE',  lect_kpi_table('results');
            case 'BUNDLE', export_gui_bundle(fullfile(root, 'profiles'), root);
            otherwise,     run_script(steps{k, 2});
        end
    catch e
        err{end+1} = sprintf('%s: %s', steps{k, 1}, e.message); %#ok<AGROW>
        break
    end
    close all
end
end

function run_script(name)
run(name);
end

function tf = has_table(tree)
tf = isfile(fullfile(tree, 'code', 'evaluation', 'lect_kpi_table.m'));
end

function rx = rx_dir(root)
S = load(fullfile(root, 'params.mat'));
rx = sprintf('rx%d', S.params.n_rx);
end

%% ===================== Comparisons =====================
function [ok, why] = compare_file(a, b)
% a against b: text line by line and JSON or MAT contents with the 'Generated' stamps set aside,
% images pixel by pixel, anything else byte by byte.
ok = false; why = '';
if ~isfile(a), why = sprintf('%s absent', a); return; end
if ~isfile(b), why = sprintf('%s absent', b); return; end
if dir(a).bytes == dir(b).bytes && strcmp(sha_file(a), sha_file(b)), ok = true; why = 'equal (bytes)'; return; end
[~, ~, e] = fileparts(a);
switch lower(e)
    case '.json'
        try
            A = scrub(jsondecode(fileread(a))); B = scrub(jsondecode(fileread(b)));
        catch
            [ok, why] = compare_lines(a, b); return
        end
        ok = isequaln(A, B); if ~ok, why = first_diff(A, B); end
    case {'.txt', '.csv'}
        [ok, why] = compare_lines(a, b);
    case '.mat'
        A = scrub(load(a)); B = scrub(load(b));
        ok = isequaln(A, B); if ~ok, why = first_diff(A, B); end
    case '.png'
        ia = imread(a); ib = imread(b);
        ok = isequal(size(ia), size(ib)) && isequal(ia, ib);
        if ~ok, why = sprintf('pixels differ (%s against %s)', mat2str(size(ia)), mat2str(size(ib))); end
    otherwise
        ok = strcmp(sha_file(a), sha_file(b)); if ~ok, why = 'bytes differ'; end
end
if ok, why = 'equal'; end
end

function [ok, why] = compare_lines(a, b)
La = scrub(read_lines(a)); Lb = scrub(read_lines(b));
ok = isequal(La, Lb); why = '';
if ok, return; end
n = min(numel(La), numel(Lb)); k = find(~cellfun(@strcmp, La(1:n), Lb(1:n)), 1);
if isempty(k), why = sprintf('%d lines against %d', numel(La), numel(Lb));
else, why = sprintf('line %d: "%s" against "%s"', k, cut(La{k}), cut(Lb{k})); end
end

function x = scrub(x)
% The run's own stamps set aside: a field named generated, a line beginning with 'Generated:'.
if isstruct(x)
    f = fieldnames(x);
    for i = 1:numel(x)
        for j = 1:numel(f)
            if strcmpi(f{j}, 'generated'), x(i).(f{j}) = '<stamp>'; else, x(i).(f{j}) = scrub(x(i).(f{j})); end
        end
    end
elseif iscell(x)
    for i = 1:numel(x), x{i} = scrub(x{i}); end
elseif ischar(x) && (isrow(x) || isempty(x))
    if startsWith(strtrim(x), 'Generated:'), x = 'Generated: <stamp>'; end
elseif isstring(x)
    for i = 1:numel(x)
        if ~ismissing(x(i)) && startsWith(strtrim(x(i)), "Generated:"), x(i) = "Generated: <stamp>"; end
    end
end
end

function why = first_diff(A, B)
[ka, va] = flat_kv(A, 'x'); [kb, vb] = flat_kv(B, 'x');
mb = kv_map(kb, vb);
for i = 1:numel(ka)
    if ~isKey(mb, ka{i}) || ~isequaln(mb(ka{i}), va{i}), why = sprintf('first difference at %s', ka{i}); return; end
end
why = sprintf('first difference: %s', list_txt('', setdiff(kb, ka)));
end

function rows = compare_bundle(mine, ref)
rows = struct('file', {}, 'ok', {}, 'why', {});
if ~isfolder(ref)
    rows(end+1) = row(['bundle ' ref], false, 'no bundle of the final phase there'); return
end
fm = list_rel(mine, ''); fr = list_rel(ref, '');
d1 = setdiff(fm, fr); d2 = setdiff(fr, fm);
rows(end+1) = row('bundle files', isempty(d1) && isempty(d2), sprintf('%d files%s%s', numel(fm), list_txt('; only here: ', d1), ...
    list_txt('; only in the final phase''s: ', d2)));
for f = reshape(intersect(fm, fr), 1, [])
    [ok, why] = compare_file(fullfile(mine, f{1}), fullfile(ref, f{1}));
    rows(end+1) = row(['bundle/' f{1}], ok, why); %#ok<AGROW>
end
end

function r = stale_row(a, b)
sa = stale_files(a); sb = stale_files(b);
r = row('stale-file count', isfile(a) && isfile(b) && isequal(sort(sa), sort(sb)), ...
    sprintf('%d here (%s), %d in the tree (%s)', numel(sa), strjoin(sa, ', '), numel(sb), strjoin(sb, ', ')));
end

function s = stale_files(f)
% The files report_numbers.json flags stale (N.stale).
s = {};
if ~isfile(f), return; end
N = jsondecode(fileread(f));
if ~isfield(N, 'stale') || isempty(N.stale), return; end
x = N.stale;
if isstruct(x), s = {x.file}; elseif iscell(x), s = cellfun(@(y) y.file, x, 'UniformOutput', false); end
s = reshape(s, 1, []);
end

function D = code_diff(root, tree)
% The .m files of root/code and tree/code (tests/ aside) whose text differs, line ends aside, or
% that only one side holds; bad: those outside the adoption's own files.
K = reg();
a = m_files(fullfile(root, 'code')); b = m_files(fullfile(tree, 'code'));
differ = {};
for f = reshape(union(a, b), 1, [])
    if startsWith(f{1}, 'tests/'), continue; end
    fa = fullfile(root, 'code', f{1}); fb = fullfile(tree, 'code', f{1});
    if ~(isfile(fa) && isfile(fb)) || ~strcmp(strrep(fileread(fa), char(13), ''), strrep(fileread(fb), char(13), ''))
        differ{end+1} = f{1}; %#ok<AGROW>
    end
end
D = struct('differ', {differ}, 'bad', {setdiff(differ, K.may_differ)});
end

function F = m_files(d)
F = cell(1, 0);
if ~isfolder(d), return; end
F = list_rel(d, '');
F = F(endsWith(F, '.m'));
end

function h = code_sha(root)
% The SHA-256 of the list of root/code/**/*.m (tests/ aside), each file's SHA-256 (line ends aside:
% a checkout may convert them) and path.
F = m_files(fullfile(root, 'code')); F = F(~startsWith(F, 'tests/'));
L = cellfun(@(f) sprintf('%s  %s', text_sha(fullfile(root, 'code', f)), f), F, 'UniformOutput', false);
h = str_sha(strjoin(sort(reshape(L, 1, [])), newline));
end

function d = code_dirty(root)
% The .m files under root/code (tests/ aside) that git reports modified or untracked; none outside git.
d = {};
if strcmp(tree_head(root), 'unknown'), return; end
[st, out] = system(sprintf('git --no-optional-locks -C "%s" status --porcelain --untracked-files=all -- code', root));
assert(st == 0, 'adopt_reading:git', 'adopt_reading: git status failed in %s: %s', root, out);
L = strsplit(strrep(out, char(13), ''), newline);
L = L(~cellfun(@isempty, strtrim(L)));
L = strtrim(strrep(regexprep(L, '^.. ', ''), '"', ''));
d = L(endsWith(L, '.m') & ~startsWith(L, 'code/tests/'));
end

function [ok, why] = path_ok(X, tree)
% The decision and KPI code resolves into this checkout's code, and the tree's code is not on the path.
K = reg();
w = cellfun(@which, K.code_fns, 'UniformOutput', false);
ok = all(cellfun(@(p) ~isempty(p) && under(p, fullfile(X.root, 'code')), w)) && ~contains(lower(path), lower(fullfile(tree, 'code')));
why = sprintf('the code runs from %s', strjoin(w, ', '));
end

function tf = same_text(a, b)
tf = isfile(a) && isfile(b) && strcmp(strrep(fileread(a), char(13), ''), strrep(fileread(b), char(13), ''));
end

function H = out_hashes(root, files)
H = struct('file', {}, 'sha256', {});
for k = 1:numel(files)
    p = fullfile(root, files{k});
    if isfile(p), H(end+1) = struct('file', files{k}, 'sha256', sha_file(p)); end %#ok<AGROW>
end
end

function [ok, why] = outputs_ok(X, Vc)
% The outputs ADOPT-C2e checked (c2e.json) still hold the SHA-256 it recorded.
ok = false; why = sprintf('%s records no outputs', X.v.c2e);
if ~isstruct(Vc) || ~isfield(Vc, 'outputs') || isempty(Vc.outputs), return; end
H = Vc.outputs; if iscell(H), H = [H{:}]; end
if ~ismember('results/policy_evaluation.mat', {H.file}), why = 'c2e.json records no results/policy_evaluation.mat'; return; end
bad = {};
for k = 1:numel(H)
    p = fullfile(X.on, H(k).file);
    if ~isfile(p) || ~strcmp(sha_file(p), H(k).sha256), bad{end+1} = H(k).file; end %#ok<AGROW>
end
ok = isempty(bad);
why = sprintf('%d outputs of ADOPT-C2e%s', numel(H), ternary(ok, ' as c2e.json recorded', list_txt(' changed since: ', bad)));
end

%% ===================== Tree listing and hashes =====================
function F = tree_files(tree)
% The tree's registered results and inputs, relative with '/': results/**, params.mat, profile.json,
% data/*.mat; sorted.
F = {};
if isfolder(fullfile(tree, 'results')), F = list_rel(tree, 'results'); end
for f = {'params.mat', 'profile.json'}
    if isfile(fullfile(tree, f{1})), F{end+1} = f{1}; end %#ok<AGROW>
end
d = dir(fullfile(tree, 'data', '*.mat')); d = d(~[d.isdir]);
for k = 1:numel(d), F{end+1} = ['data/' d(k).name]; end %#ok<AGROW>
F = sort(F);
end

function H = hash_lines(tree, F)
H = cellfun(@(f) sprintf('%s  %s', sha_file(fullfile(tree, f)), f), F, 'UniformOutput', false);
end

function S = snapshot(tree)
% Every file of the tree but .git and logs/ (other processes' logs), with its size and date, and its HEAD.
F = {}; B = zeros(0, 2);
d = dir(tree);
for k = 1:numel(d)
    n = d(k).name;
    if any(strcmp(n, {'.', '..', '.git', 'logs'})), continue; end
    if d(k).isdir
        [f, b] = list_rel(tree, n); F = [F, f]; B = [B; b]; %#ok<AGROW>
    else
        F{end+1} = n; B(end+1, :) = [d(k).bytes, d(k).datenum]; %#ok<AGROW>
    end
end
[F, o] = sort(F); B = B(o, :);
S = struct('files', {F}, 'meta', B, 'head', tree_head(tree));
end

function S = dir_state(d)
% Every file under d with its size and date (empty when d is absent).
[F, B] = list_rel(d, '');
[F, o] = sort(F); B = B(o, :);
S = struct('files', {F}, 'meta', B, 'head', '');
end

function t = snap_why(s0, s1, what)
% What moved between two snapshots.
if isequal(s0, s1), t = sprintf('%s: listing, sizes, dates and HEAD the same before and after', what); return; end
[c, i0, i1] = intersect(s0.files, s1.files);
moved = c(any(s0.meta(i0, :) ~= s1.meta(i1, :), 2));
ch = [reshape(setxor(s0.files, s1.files), 1, []), reshape(moved, 1, [])];
if ~strcmp(s0.head, s1.head), ch{end+1} = 'HEAD'; end
t = sprintf('%s moved: %s', what, list_txt('', ch));
end

function [F, B] = list_rel(base, sub)
% Files under base/sub, relative to base with '/' (sub '' lists base itself), with [bytes datenum].
F = {}; B = zeros(0, 2);
if ~isfolder(fullfile(base, sub)), return; end
d = dir(fullfile(base, sub));
for k = 1:numel(d)
    n = d(k).name;
    if strcmp(n, '.') || strcmp(n, '..'), continue; end
    if isempty(sub), r = n; else, r = [sub '/' n]; end
    if d(k).isdir
        [f, b] = list_rel(base, r); F = [F, f]; B = [B; b]; %#ok<AGROW>
    else
        F{end+1} = r; B(end+1, :) = [d(k).bytes, d(k).datenum]; %#ok<AGROW>
    end
end
end

function h = tree_head(d)
% The commit checked out in d, 'unknown' outside a git checkout.
[st, out] = system(sprintf('git --no-optional-locks -C "%s" rev-parse HEAD', d));
h = regexp(out, '[0-9a-f]{40}', 'match', 'once');
if st ~= 0 || isempty(h), h = 'unknown'; end
end

function h = sha_file(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r'); assert(fid > 0, 'adopt_reading:read', 'adopt_reading: cannot read %s', f);
c = onCleanup(@() fclose(fid));
while true
    b = fread(fid, 2^26, '*uint8');
    if isempty(b), break; end
    md.update(b);
end
h = hex(md.digest());
end

function h = text_sha(f)
md = java.security.MessageDigest.getInstance('SHA-256');
s = strrep(fileread(f), char(13), '');
if ~isempty(s), md.update(unicode2native(s, 'UTF-8')); end
h = hex(md.digest());
end

function h = str_sha(s)
md = java.security.MessageDigest.getInstance('SHA-256');
if ~isempty(s), md.update(unicode2native(s, 'UTF-8')); end
h = hex(md.digest());
end

function s = hex(d)
s = lower(reshape(dec2hex(typecast(d, 'uint8'), 2)', 1, []));
end

%% ===================== Writing =====================
function copy_keep(src, dst)
% A copy with the source's attributes and modification time.
mk_parent(dst);
assert(~isfile(dst), 'adopt_reading:overwrite', 'adopt_reading: %s exists', dst);
s = jpath(src); d = jpath(dst);
o = javaArray('java.nio.file.CopyOption', 1); o(1) = java.nio.file.StandardCopyOption.COPY_ATTRIBUTES;
java.nio.file.Files.copy(s, d, o);
lo = javaArray('java.nio.file.LinkOption', 0);
t = java.nio.file.Files.getLastModifiedTime(s, lo);
if ~t.equals(java.nio.file.Files.getLastModifiedTime(d, lo)), java.nio.file.Files.setLastModifiedTime(d, t); end
assert(t.equals(java.nio.file.Files.getLastModifiedTime(d, lo)) && java.nio.file.Files.size(d) == java.nio.file.Files.size(s), ...
    'adopt_reading:copy', 'adopt_reading: the copy %s does not keep the size and date of %s', dst, src);
end

function link_ro(src, dst)
% A hard link to src at dst, on the same volume only, read-only.
mk_parent(dst);
assert(~isfile(dst), 'adopt_reading:overwrite', 'adopt_reading: %s exists', dst);
assert(same_volume(src, fileparts(dst)), 'adopt_reading:volume', ...
    'adopt_reading: %s and %s are on different volumes: no hard link, the overlay is refused', src, fileparts(dst));
java.nio.file.Files.createLink(jpath(dst), jpath(src));
assert(java.nio.file.Files.isSameFile(jpath(dst), jpath(src)), 'adopt_reading:link', 'adopt_reading: %s is no link of %s', dst, src);
[ok, msg] = fileattrib(dst, '-w');
assert(ok && ~java.io.File(dst).canWrite(), 'adopt_reading:link', 'adopt_reading: %s cannot be made read-only: %s', dst, msg);
end

function tf = same_volume(a, bdir)
fa = java.nio.file.Files.getFileStore(jpath(a)); fb = java.nio.file.Files.getFileStore(jpath(bdir));
ra = char(jpath(a).toAbsolutePath().getRoot().toString()); rb = char(jpath(bdir).toAbsolutePath().getRoot().toString());
tf = fa.equals(fb) && strcmpi(ra, rb);
end

function write_once(f, lines)
% Text written whole to a temporary file, then moved onto f; refused when f exists.
assert(~isfile(f), 'adopt_reading:overwrite', 'adopt_reading: %s exists; a file is written once', f);
mk_parent(f);
t = [f '.part'];
assert(~isfile(t), 'adopt_reading:overwrite', 'adopt_reading: %s exists', t);
fid = fopen(t, 'w'); assert(fid > 0, 'adopt_reading:write', 'adopt_reading: cannot write %s', t);
fwrite(fid, unicode2native(strjoin([reshape(lines, 1, []), {''}], newline), 'UTF-8')); fclose(fid);
java.nio.file.Files.move(jpath(t), jpath(f), javaArray('java.nio.file.CopyOption', 0));
end

function V = verdict(X, stage, rows, extra)
V = struct('stage', stage, 'pass', ~isempty(rows) && all([rows.ok]), 'rows', rows, 'created', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
for f = fieldnames(extra)', V.(f{1}) = extra.(f{1}); end
txt = {sprintf('=== ADOPTION %s: %s (%s) ===', upper(stage), ternary(V.pass, 'PASS', 'FAIL'), X.tag), sprintf('Created: %s', V.created)};
for i = 1:numel(rows)
    txt{end+1} = sprintf('  %-4s %-40s %s', ternary(rows(i).ok, 'ok', 'FAIL'), rows(i).file, rows(i).why); %#ok<AGROW>
end
if isfield(extra, 'note'), txt = [txt, {''}, reshape(extra.note, 1, [])]; end
write_once(X.v.(stage), {jsonencode(V, 'PrettyPrint', true)});
write_once(X.t.(stage), txt);
end

function V = read_verdict(f)
V = [];
if isfile(f), V = jsondecode(fileread(f)); end
end

function lg = start_log(X, stage)
f = fullfile(X.logs, sprintf('%s_%s.txt', stage, datestr(now, 'yyyymmdd_HHMMSS')));
assert(~isfile(f), 'adopt_reading:overwrite', 'adopt_reading: %s exists', f);
mk_parent(f);
diary(f); diary on;
lg = onCleanup(@() diary('off'));
end

%% ===================== Small helpers =====================
function [k, v] = flat_kv(x, p)
% Every leaf of x with its place (p.f, p(i).f, p{i}); the sizes of struct arrays and cells as leaves.
if isstruct(x)
    k = {}; v = {};
    if ~isscalar(x), k{end+1} = [p '#size']; v{end+1} = size(x); end
    f = fieldnames(x);
    for i = 1:numel(x)
        for j = 1:numel(f)
            if isscalar(x), q = [p '.' f{j}]; else, q = sprintf('%s(%d).%s', p, i, f{j}); end
            [a, b] = flat_kv(x(i).(f{j}), q); k = [k, a]; v = [v, b]; %#ok<AGROW>
        end
    end
elseif iscell(x)
    k = {[p '#size']}; v = {size(x)};
    for i = 1:numel(x)
        [a, b] = flat_kv(x{i}, sprintf('%s{%d}', p, i)); k = [k, a]; v = [v, b]; %#ok<AGROW>
    end
else
    k = {p}; v = {x};
end
end

function m = kv_map(k, v)
m = containers.Map('KeyType', 'char', 'ValueType', 'any');
for i = 1:numel(k), m(k{i}) = v{i}; end
end

function x = cell_at(S, f, c)
x = [];
if isfield(S, f) && iscell(S.(f)) && c <= numel(S.(f)), x = S.(f){c}; end
end

function c = as_cell(x)
% A decoded JSON list of names as a cell row.
if isempty(x), c = {}; elseif ischar(x), c = {x}; else, c = reshape(cellstr(x), 1, []); end
end

function v = field_or(S, f, d)
v = d; if isstruct(S) && isfield(S, f), v = S.(f); end
end

function v = opt_field(O, f, d)
v = d; if isstruct(O) && isfield(O, f) && ~isempty(O.(f)), v = O.(f); end
end

function t = field_txt(S, f)
t = '?'; if isfield(S, f) && ischar(S.(f)), t = S.(f); end
end

function r = row(name, ok, why)
r = struct('file', name, 'ok', logical(ok), 'why', why);
end

function t = list_txt(head, c)
t = ''; if ~isempty(c), t = [head strjoin(c(1:min(end, 20)), ', ') ternary(numel(c) > 20, sprintf(' (+%d)', numel(c) - 20), '')]; end
end

function L = read_lines(f)
s = strrep(fileread(f), char(13), '');
if endsWith(s, newline), s = s(1:end-1); end
L = strsplit(s, newline, 'CollapseDelimiters', false);
end

function s = cut(s)
if numel(s) > 120, s = [s(1:117) '...']; end
end

function p = canon(p)
p = char(java.io.File(char(p)).getCanonicalPath());
end

function tf = under(a, b)
% a lies inside folder b (case aside).
tf = startsWith(lower([canon(a) filesep]), lower([canon(b) filesep])) && ~strcmpi(canon(a), canon(b));
end

function p = jpath(f)
p = java.io.File(char(f)).toPath();
end

function mk_parent(f)
d = fileparts(f);
if ~isempty(d) && ~isfolder(d), mkdir(d); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
