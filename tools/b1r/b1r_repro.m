function R = b1r_repro(cmd, varargin)
%B1R_REPRO  B1-R: the registered numbers reproduced end to end with this checkout's code on the
%   saved pools, every output in a scratch folder, compared exactly with the registered files.
%   The finished trees, the adoption overlays and the reading copies are only read.
%   R = b1r_repro('run', tag, part, out_dir [, O])
%       tag  'p1' | 'p3'      part  'light' | 'heavy'      out_dir  a folder that does not exist
%       p1 light   bw      experiment_core_bw('report') on the saved test readings (CORE_BW)
%                  sysfa   system_fa_breakdown('run') on the saved pools and the reading copy
%       p1 heavy   render  the registered policy_evaluation.mat through this code's KPI, dashboard,
%                          report-number, table and bundle renderers (ADOPT0), minutes
%                  off     evaluate_policies.m without an adoption, then KPI, dashboard, report
%                          numbers, KPI table and bundle, against the tree's registered files
%                  on      the same with CFG.adopt of the tree's overlay manifest (D124), against
%                          the overlay's on/ files; the C2e guards of adopt_reading.m
%                  lect    the lecturer table's sources and numbers against the files
%       p3 light   sysfa;   p3 heavy   render, off, on
%       Run the light part in a session started with -singleCompThread (the registered system_fa
%       header says 'threads 1') and the heavy part with MATLAB's default threads (8 are set).
%       R.rc is 0 when every comparison is ok, 1 when the only differences are additive (this code prints
%       or holds more than the registered code did) or in the renderers' outputs, 2 for any other
%       difference or a failed stage; the last printed line is
%       'B1R_<TAG> rc=<n> part=<part>'. Rows: stage, name, kind, ok, detail. Kinds: exact (bytes
%       equal), equal-fields (.mat or .json numeric fields equal, stamps aside), equal-lines
%       (text equal, 'Generated:' lines aside), rendering (an image within 0.5% of its pixels;
%       not an exact comparison), info (nothing registered to compare), DIFF-timing (only
%       time-like fields or lines differ), DIFF-additive (every registered line or field is
%       reproduced, this code prints or holds more), DIFF-wording (text whose registered lines
%       differ only in words: each such line's numbers occur, in order, on a line printed here;
%       reported, read by a person), DIFF, ERROR.
%   Compare again: R = b1r_repro('recompare', tag, src_dir, out_dir [, O]) reads the outputs a
%   'run' left in src_dir (its light and heavy folders) with this code's comparisons, runs nothing
%   and writes b1r_<tag>_<part>-recompare_summary.txt into out_dir (a new folder).
%   One stage alone: R = b1r_repro('stage', name, tag, out_dir [, O]) with name bw, sysfa, render, off, on or lect
%   (out_dir must not exist for the first stage of a folder; the stage's own folder inside must not exist).
%   Helpers: b1r_repro('compare', stage, name, mine, ref), b1r_repro('diff', A, B),
%   b1r_repro('build_root', root, tree, left_out), b1r_repro('lect_values', csv, map),
%   b1r_repro('config', tag, O)
%   Test hooks in O: eval_fn(root, cfg), render_fn(root, tab), keep_functions.
switch cmd
    case 'run',         R = run_parts(varargin{:});
    case 'recompare',   R = recompare(varargin{:});
    case 'set_aside',   [N, add] = set_aside_added(varargin{:}); R = struct('N', N, 'add', {add});
    case 'lat_age',     R = lat_age(varargin{:});
    case 'config',      R = config(varargin{:});
    case 'build_root',  build_root(varargin{:}); R = [];
    case 'compare',     R = cmp_files(varargin{:});
    case 'diff',        R = struct_diff(varargin{:});
    case 'lect_values', R = lect_values(varargin{:});
    case 'policy',      R = stage_policy(varargin{:});
    case 'stage',       R = one_stage(varargin{:});
    case 'summary',     R = summary(varargin{:});
    case 'draw_copy',   R = draw_copy(varargin{:});
    otherwise, error('b1r_repro:cmd', 'b1r_repro: unknown command %s', cmd);
end
end

%% ===================== Configuration =====================
function C = config(tag, O)
if nargin < 2 || isempty(O), O = struct(); end
assert(any(strcmp(tag, {'p1', 'p3'})), 'b1r_repro:tag', 'b1r_repro: tag is p1 or p3');
home = getenv('USERPROFILE');
wt = fullfile(home, 'uav-gcs-adaptive-secure-comms', 'worktrees');
C.tag = tag;
C.repo = fileparts(fileparts(fileparts(mfilename('fullpath'))));
if strcmp(tag, 'p1'), C.tree = fullfile(home, 'uav-gcs-v7'); else, C.tree = fullfile(home, 'uav-gcs-v7-p3'); end
C.adopt = fullfile(wt, ['adopt-' tag]);
C.rf = fullfile(C.adopt, 'results', 'rule_fix', tag);
C.ad_root = fullfile(C.rf, 'adopted');
C.sysfa = fullfile(wt, 'sysfa-read', tag);
C.bw = fullfile(home, 'uav-gcs-v7-bw');
C.lect = fullfile(wt, 'session_notes_0ff3', 'core', 'lect_table');
C.bundle_ref = fullfile(home, 'uav-gcs-v7', 'profiles');
for f = fieldnames(O)'
    if isfield(C, f{1}), C.(f{1}) = O.(f{1}); end
end
end

function L = left_out(mode)
final = {'kpi_summary.txt', 'kpi_summary.mat', 'kpi_dashboard.png', 'report_numbers.json'};
table = {'lect_kpi_table.txt', 'lect_kpi_table.csv', 'lect_kpi_per.png', 'lect_kpi_recovery.png', 'lect_kpi_goodput.png'};
c2e = {'policy_evaluation.txt', 'policy_evaluation.mat', 'policy_evaluation.png', 'policy_breakdown.png'};
L = struct('final', {final}, 'table', {table}, 'c2e', {c2e});
if strcmp(mode, 'off'), L.rel = strcat('results/', [final, table]);
else, L.rel = strcat('results/', [final, table, c2e]); end
end

function R = one_stage(name, tag, out_dir, O)
if nargin < 4, O = struct(); end
C = config(tag, O);
if ~isfolder(out_dir), mkdir(out_dir); end
switch name
    case 'bw',    R = stage_bw(C, out_dir);
    case 'sysfa', R = stage_sysfa(C, out_dir);
    case 'off',   R = stage_policy(C, 'off', out_dir, O);
    case 'render', R = stage_render(C, out_dir, O);
    case 'on',    R = stage_policy(C, 'on', out_dir, O);
    case 'lect',  R = stage_lect(C, out_dir);
    otherwise, error('b1r_repro:stage', 'b1r_repro: unknown stage %s', name);
end
for i = 1:numel(R), print_row(R(i)); end
end

%% ===================== Run =====================
function R = run_parts(tag, part, out_dir, O)
if nargin < 4 || isempty(O), O = struct(); end
C = config(tag, O);
assert(any(strcmp(part, {'light', 'heavy'})), 'b1r_repro:part', 'b1r_repro: part is light or heavy');
out_dir = char(out_dir);
assert(~isfolder(out_dir), 'b1r_repro:exists', 'b1r_repro: %s exists; a part runs once into a new folder', out_dir);
for d = {C.tree, C.bw, C.adopt, C.sysfa, C.lect, C.repo}
    assert(~strncmpi([out_dir filesep], [d{1} filesep], numel(d{1}) + 1), 'b1r_repro:inside', ...
        'b1r_repro: %s lies inside %s; the outputs go to a scratch folder', out_dir, d{1});
end
mkdir(out_dir);
stages = {'light', 'p1', {'bw', 'sysfa'}; 'light', 'p3', {'sysfa'}; 'heavy', 'p1', {'render', 'off', 'on', 'lect'}; 'heavy', 'p3', {'render', 'off', 'on'}};
names = stages{strcmp(stages(:, 1), part) & strcmp(stages(:, 2), tag), 3};
fprintf('B1R %s %s start %s\nB1R code %s HEAD %s\nB1R out %s\n', tag, part, datestr(now), C.repo, git_head(C.repo), out_dir);
s0 = tree_state(C.tree); b0 = []; if strcmp(tag, 'p1'), b0 = tree_state(C.bw); end
rows = new_rows();
for k = 1:numel(names)
    t0 = tic; fprintf('B1R stage %s start %s\n', names{k}, datestr(now));
    try
        switch names{k}
            case 'bw',     r = stage_bw(C, out_dir);
            case 'sysfa',  r = stage_sysfa(C, out_dir);
            case 'render', r = stage_render(C, out_dir, O);
            case 'off',    r = stage_policy(C, 'off', out_dir, O);
            case 'on',     r = stage_policy(C, 'on', out_dir, O);
            case 'lect',   r = stage_lect(C, out_dir);
        end
    catch e
        r = mkrow(names{k}, 'stage', 'ERROR', sprintf('%s: %s', e.identifier, e.message));
    end
    close all force
    for i = 1:numel(r), print_row(r(i)); end
    fprintf('B1R stage %s done %.1f min\n', names{k}, toc(t0) / 60);
    rows = [rows, r]; %#ok<AGROW>
    if ~isfield(O, 'keep_functions') || ~O.keep_functions, clear functions; end
end
s1 = tree_state(C.tree);
r = mkrow('all', 'tree untouched', ternary(isequal(s0, s1), 'info', 'DIFF'), ...
    sprintf('%s: %d files (results, params and profile.json hashed, data by size and date), before and after', C.tree, numel(s0)));
if ~isempty(b0), r(2) = mkrow('all', 'bw tree untouched', ternary(isequal(b0, tree_state(C.bw)), 'info', 'DIFF'), C.bw); end
for i = 1:numel(r), print_row(r(i)); end
rows = [rows, r];
R = summary(rows, tag, part, out_dir);
end

function R = recompare(tag, src, out_dir, O)
% The comparisons of a finished run read again on its outputs: nothing is built, evaluated or rendered.
if nargin < 4 || isempty(O), O = struct(); end
C = config(tag, O); O.reuse = true;
src = char(src); out_dir = char(out_dir);
assert(isfolder(src), 'b1r_repro:src', 'b1r_repro: %s is no folder', src);
assert(~isfolder(out_dir), 'b1r_repro:exists', 'b1r_repro: %s exists', out_dir);
mkdir(out_dir);
stages = {'light', 'p1', {'bw', 'sysfa'}; 'light', 'p3', {'sysfa'}; 'heavy', 'p1', {'render', 'off', 'on', 'lect'}; 'heavy', 'p3', {'render', 'off', 'on'}};
R = struct('part', {}, 'rc', {}, 'summary', {});
for part = {'light', 'heavy'}
    d = fullfile(src, part{1});
    if ~isfolder(d), continue; end
    names = stages{strcmp(stages(:, 1), part{1}) & strcmp(stages(:, 2), tag), 3};
    rows = new_rows();
    for k = 1:numel(names)
        try
            switch names{k}
                case 'bw',     r = stage_bw(C, d, O);
                case 'sysfa',  r = stage_sysfa(C, d, O);
                case 'render', r = stage_render(C, d, O);
                case 'off',    r = stage_policy(C, 'off', d, O);
                case 'on',     r = stage_policy(C, 'on', d, O);
                case 'lect',   r = stage_lect(C, d);
            end
        catch e
            r = mkrow(names{k}, 'stage', 'ERROR', sprintf('%s: %s', e.identifier, e.message));
        end
        rows = [rows, r]; %#ok<AGROW>
    end
    S = summary(rows, tag, [part{1} '-recompare'], out_dir);
    R(end+1) = struct('part', part{1}, 'rc', S.rc, 'summary', S.summary); %#ok<AGROW>
end
end

function R = summary(rows, tag, part, out_dir)
kinds = {'exact', 'equal-fields', 'equal-lines', 'rendering', 'info', 'DIFF-timing', 'DIFF-additive', 'DIFF-wording', 'DIFF', 'ERROR'};
n = cellfun(@(k) sum(strcmp({rows.kind}, k)), kinds);
bad = ~[rows.ok];
isr = contains({rows.stage}, 'render');               % the renderers' outputs: this code prints more than the registered code did
hard = bad & (strcmp({rows.kind}, 'ERROR') | (~isr & ~ismember({rows.kind}, {'DIFF-additive', 'DIFF-wording'})));
soft = bad & ~hard;
rc = 2 * any(hard) + double(~any(hard) && any(soft));
lines = cell(1, numel(rows));
for i = 1:numel(rows), lines{i} = row_text(rows(i)); end
head = {sprintf('B1R %s %s summary, %s; rc 0 all comparisons ok, 1 only additive, wording or renderer-output differences, 2 a real difference or an error', ...
    upper(tag), part, datestr(now)), ...
    strjoin(cellfun(@(k, c) sprintf('%s %d', k, c), kinds, num2cell(n), 'UniformOutput', false), ' | ')};
f = fullfile(out_dir, sprintf('b1r_%s_%s_summary.txt', tag, part));
fid = fopen(f, 'w'); fprintf(fid, '%s\n', head{:}, lines{:}); fclose(fid);
fprintf('%s\n', head{:});
fprintf('B1R_%s rc=%d part=%s\n', upper(tag), rc, part);
R = struct('rc', rc, 'hard', sum(hard), 'soft', sum(soft), 'rows', rows, 'counts', cell2struct(num2cell(n), strrep(kinds, '-', '_'), 2), 'summary', f);
end

function r = new_rows()
r = struct('stage', {}, 'name', {}, 'kind', {}, 'ok', {}, 'detail', {});
end

function r = mkrow(stage, name, kind, detail)
r = struct('stage', stage, 'name', name, 'kind', kind, 'ok', ismember(kind, {'exact', 'equal-fields', 'equal-lines', 'rendering', 'info'}), ...
    'detail', detail);
end

function t = row_text(r)
t = sprintf('  %-5s %-12s %-44s %-12s %s', ternary(r.ok, 'ok', 'FAIL'), r.stage, r.name, r.kind, cut(r.detail, 600));
end

function print_row(r)
fprintf('%s\n', row_text(r));
end

%% ===================== Stage: policy_evaluation (off | on) =====================
function rows = stage_policy(C, mode, out, O)
if nargin < 4 || isempty(O), O = struct(); end
st = ['policy_' mode]; rows = new_rows();
root = fullfile(out, mode);
LO = left_out(mode);
render_fn = hook(O, 'render_fn', @render_here);
if reused(O)
    render_fn = [];
    rows(end+1) = mkrow(st, 'reused', 'info', sprintf('the outputs in %s compared again; nothing run', root));
else
    build_root(root, C.tree, LO.rel);
    cfg = [];
    if strcmp(mode, 'on'), cfg = adopt_reading('cfg', jsondecode(fileread(fullfile(C.ad_root, 'adoption.json')))); end
    rows(end+1) = tree_draws(C, root, st);
    eval_fn = hook(O, 'eval_fn', @run_eval);
    t0 = tic;
    eval_fn(root, cfg);
    how = ', no adoption'; if ~isempty(cfg), how = [', CFG.adopt rule_fix ' cfg.adopt.rule_fix]; end
    rows(end+1) = mkrow(st, 'evaluate_policies', 'info', sprintf('ran %.1f min, %d threads%s', toc(t0) / 60, maxNumCompThreads, how));
end
if strcmp(mode, 'off'), ref = fullfile(C.tree, 'results'); else, ref = fullfile(C.ad_root, 'on', 'results'); end
for f = LO.c2e
    rows(end+1) = cmp_files(st, ['results/' f{1}], fullfile(root, 'results', f{1}), fullfile(ref, f{1})); %#ok<AGROW>
end
if strcmp(mode, 'on')
    N = load(fullfile(root, 'results', 'policy_evaluation.mat'));
    E = load(fullfile(C.tree, 'results', 'policy_evaluation.mat'));
    T = load(fullfile(C.rf, 'test.mat'));
    [N, add] = set_aside_added(N, E, fullfile(ref, 'policy_evaluation.mat'));
    rows(end+1) = mkrow(st, 'guard input', 'info', ternary(isempty(add), 'KP as written here', ...
        sprintf('KP fields this code adds (on neither the registered nor the adopted file) set aside before the guard: %s', strjoin(add, ', '))));
    strict =isfile(fullfile(C.repo, 'code', 'decision', 'rule_fix_reading.m')) && ...
        strcmp(strrep(fileread(fullfile(C.repo, 'code', 'evaluation', 'lect_kpis.m')), char(13), ''), ...
        strrep(fileread(fullfile(C.tree, 'code', 'evaluation', 'lect_kpis.m')), char(13), ''));
    G = adopt_reading('guard_c2e', N, E, T, struct('lect_strict', strict));
    for g = G.rows(:)'
        rows(end+1) = mkrow(st, ['guard ' g.file], ternary(g.ok, 'info', 'DIFF'), g.why); %#ok<AGROW>
    end
    rows(end+1) = mkrow(st, 'guard C2e', ternary(G.pass, 'info', 'DIFF'), sprintf('adopt_reading guard_c2e, lect_strict %d', strict));
    clear N E T
    rows(end+1) = lat_age(st, fullfile(ref, 'latency.mat'), fullfile(C.tree, 'results', 'latency.mat'));
end
if strcmp(mode, 'off'), bref = C.bundle_ref; else, bref = fullfile(C.ad_root, 'on', 'profiles'); end
rows = [rows, render_and_compare(C, st, root, ref, bref, LO, render_fn)];
end

function tf = reused(O)
tf = isfield(O, 'reuse') && isequal(O.reuse, true);
end

function [N, add] = set_aside_added(N, E, adopted)
% N's KP without the fields neither the registered KP nor the adopted file's KP holds: this code
% writes them (descriptive readings), the guard compares the registered fields.
add = {};
if ~isfield(N, 'KP') || ~isfield(E, 'KP'), return; end
have = fieldnames(E.KP);
if isfile(adopted)
    A = load(adopted, 'KP');
    if isfield(A, 'KP'), have = union(have, fieldnames(A.KP)); end
end
add = setdiff(fieldnames(N.KP), have)';
if ~isempty(add), N.KP = rmfield(N.KP, add); end
end

function r = lat_age(st, ref_lat, tree_lat)
% The adopted render's timing against the tree's: KPI 7 and the latency rows of the render below are
% read against the reference's latency.mat.
if ~isfile(ref_lat) || ~isfile(tree_lat), r = mkrow(st, 'render reference timing', 'info', 'no latency.mat on one side'); return; end
a = dir(ref_lat); b = dir(tree_lat);
if a.datenum < b.datenum
    t = sprintf(['the adopted render''s latency.mat (%s) is older than the tree''s (%s): KPI 7 and the latency rows ' ...
        'below are read against the older timing; the tree''s is the later LAT'], datestr(a.datenum, 'yyyy-mm-dd HH:MM'), datestr(b.datenum, 'yyyy-mm-dd HH:MM'));
else
    t = sprintf('the adopted render''s latency.mat (%s) is not older than the tree''s (%s)', datestr(a.datenum, 'yyyy-mm-dd HH:MM'), datestr(b.datenum, 'yyyy-mm-dd HH:MM'));
end
r = mkrow(st, 'render reference timing', 'info', t);
end

function rows = stage_render(C, out, O)
% The registered policy_evaluation.mat through this code's KPI, dashboard, report-number, table and bundle
% renderers (ADOPT0 of adopt_reading.m), against the tree's final-phase files.
if nargin < 3, O = struct(); end
root = fullfile(out, 'render');
LO = left_out('off');
LO.rel = strcat('results/', [LO.final, LO.table]);
fn = [];
if ~reused(O), build_root(root, C.tree, LO.rel); fn = hook(O, 'render_fn', @render_here); end
rows = render_and_compare(C, 'render', root, fullfile(C.tree, 'results'), C.bundle_ref, LO, fn);
end

function rows = render_and_compare(C, st, root, ref, bref, LO, render_fn)
rows = new_rows();
if ~strcmp(st, 'render'), st = [st '/render']; end
tab = isfile(fullfile(C.repo, 'code', 'evaluation', 'lect_kpi_table.m'));
if isempty(render_fn)
    rows(end+1) = mkrow(st, 'renderers', 'info', sprintf('not run; the outputs in %s compared again', root));
else
    err = render_fn(root, tab);
    rows(end+1) = mkrow(st, 'renderers', ternary(isempty(err), 'info', 'ERROR'), ternary(isempty(err), 'KPI, DASH, RPT, TABLE, BUNDLE ran', strjoin(err, '; ')));
end
outs = [LO.final, ternary(tab, LO.table, {})];
for f = outs
    rows(end+1) = cmp_files(st, ['results/' f{1}], fullfile(root, 'results', f{1}), fullfile(ref, f{1})); %#ok<AGROW>
end
S = load(fullfile(root, 'params.mat'));
rx = sprintf('rx%d', S.params.n_rx);
rows = [rows, cmp_tree(st, 'bundle/', fullfile(root, 'profiles', rx), fullfile(bref, rx))];
end

function fn = hook(O, name, dflt)
fn = dflt; if isfield(O, name) && ~isempty(O.(name)), fn = O.(name); end
end

function run_eval(root, cfg)
% evaluate_policies.m in root: it reads CFG (CFG.adopt) from this workspace, relative paths from the cwd.
% The copy tree_draws wrote in root runs when there is one, else this checkout's file.
c0 = cd(root); back = onCleanup(@() cd(c0)); %#ok<NASGU>
maxNumCompThreads(8);
f = 'evaluate_policies'; if isfile(fullfile(root, 'evaluate_policies.m')), f = fullfile(root, 'evaluate_policies.m'); end
if isempty(cfg), run(f); else, CFG = cfg; run(f); end %#ok<NASGU>
end

function r = tree_draws(C, root, st)
% The tree's own C2e frame draws (D124 point 7): profile 1's C2e drew 30000 + 100 x set, this code
% draws 20000 + 1000 x set. When they differ, root gets a copy of this checkout's
% evaluate_policies.m with the tree's base and step in the five draw expressions, nothing else.
src = fileread(fullfile(C.repo, 'code', 'decision', 'evaluate_policies.m'));
mine = rule_fix_reading('draws', C.repo); tree = rule_fix_reading('draws', C.tree);
if isequal(mine, tree)
    r = mkrow(st, 'frame draws', 'info', sprintf('%d + %d x set, the tree''s own and this code''s', tree)); return
end
new = draw_copy(src, mine, tree);
fid = fopen(fullfile(root, 'evaluate_policies.m'), 'w'); fwrite(fid, new, 'char'); fclose(fid);
r = mkrow(st, 'frame draws', 'info', sprintf(['%d + %d x set, the tree''s own C2e draws (D124 point 7), in a copy of ' ...
    'this code''s evaluate_policies.m in the root; this code draws %d + %d x set'], tree, mine));
end

function new = draw_copy(src, mine, tree)
% src with the draw expressions of mine replaced by tree's: the main runs once, lb_flights four times.
a = {sprintf('ag, opt, %d + %d*si);', mine), sprintf('ag, o0, %d + %d * si);', mine), sprintf('ag, o1, %d + %d * si);', mine)};
b = {sprintf('ag, opt, %d + %d*si);', tree), sprintf('ag, o0, %d + %d * si);', tree), sprintf('ag, o1, %d + %d * si);', tree)};
want = [1 2 2];
new = src;
for i = 1:3
    n = numel(strfind(new, a{i}));
    assert(n == want(i), 'b1r_repro:draws', 'b1r_repro: "%s" found %d times, expected %d', a{i}, n, want(i));
    new = strrep(new, a{i}, b{i});
end
end

function err = render_here(root, tab)
% The final phase's KPI, DASH and RPT, the KPI table where this code has it, and the bundle in root.
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

%% ===================== Stage: CORE_BW report =====================
function rows = stage_bw(C, out, O)
st = 'bw'; rows = new_rows();
root = fullfile(out, 'bw');
src = fullfile(C.bw, 'results', 'core_bw');
if nargin > 2 && reused(O)
    rows(end+1) = mkrow(st, 'reused', 'info', sprintf('the outputs in %s compared again; nothing run', root));
    rows = [rows, cmp_bw(st, root, src)];
    return
end
for f = {'protocol.json', 'recoverable.txt', 'validation.mat', 'test_readings.mat'}
    assert(isfile(fullfile(src, f{1})), 'b1r_repro:input', 'b1r_repro: %s missing', fullfile(src, f{1}));
end
mkdir(fullfile(root, 'results', 'core_bw')); mkdir(fullfile(root, 'docs'));
for f = {'protocol.json', 'recoverable.txt', 'validation.mat', 'test_readings.mat'}
    copy_keep(fullfile(src, f{1}), fullfile(root, 'results', 'core_bw', f{1}));
end
copy_keep(fullfile(C.bw, 'docs', 'core_bw_frozen.json'), fullfile(root, 'docs', 'core_bw_frozen.json'));
copy_keep(fullfile(C.bw, 'params.mat'), fullfile(root, 'params.mat'));
% experiment_core_bw works in setup_paths' repository root: a copy of this code, byte-checked
cpy = fullfile(root, 'code');
copyfile(fullfile(C.repo, 'code'), cpy);
rmdir(fullfile(cpy, 'tests'), 's');
bad = tree_diff(fullfile(C.repo, 'code'), cpy, {'tests'});
rows(end+1) = mkrow(st, 'code copy', ternary(isempty(bad), 'info', 'DIFF'), sprintf('code/ of %s without tests, %d differ', C.repo, numel(bad)));
here = fileparts(mfilename('fullpath'));
p0 = path; back = onCleanup(@() path(p0)); %#ok<NASGU>
restoredefaultpath; addpath(cpy); addpath(here);
setup_paths;
experiment_core_bw('report');
path(p0);
rows = [rows, cmp_bw(st, root, src)];
end

function rows = cmp_bw(st, root, src)
rows = new_rows();
for f = {'core_bw_report.txt', 'core_bw_kpis.mat'}
    rows(end+1) = cmp_files(st, ['results/core_bw/' f{1}], fullfile(root, 'results', 'core_bw', f{1}), fullfile(src, f{1})); %#ok<AGROW>
end
end

%% ===================== Stage: system_fa_breakdown =====================
function rows = stage_sysfa(C, out, O)
st = 'sysfa'; rows = new_rows();
od = fullfile(out, 'sysfa', 'results');
rd = fullfile(C.sysfa, 'results');
if nargin > 2 && reused(O)
    rows(end+1) = mkrow(st, 'reused', 'info', sprintf('the outputs in %s compared again; nothing run', od));
else
    mkdir(od);
    pools = fullfile(C.tree, 'data', 'policy_pools.mat');
    system_fa_breakdown('run', pools, fullfile(rd, 'policy_evaluation.mat'), fullfile(rd, 'policy_evaluation.txt'), ...
        fullfile(rd, 'trained_dqn.mat'), od, fullfile(rd, 'system_fa_breakdown.mat'));
end
for f = {'system_fa_breakdown.txt', 'system_fa_breakdown.mat'}
    rows(end+1) = cmp_files(st, ['results/' f{1}], fullfile(od, f{1}), fullfile(rd, f{1})); %#ok<AGROW>
end
end

%% ===================== Stage: lecturer table =====================
function rows = stage_lect(C, out)
st = 'lect'; rows = new_rows();
S = split_lines(fullfile(C.lect, 'sources.sha256'));
bad = {}; living = {}; n = 0;
for i = 1:numel(S)
    t = regexp(S{i}, '^([0-9a-f]{64})\s+(.+?)\s+\[\w+\]\s*$', 'tokens', 'once');
    if isempty(t), continue; end
    n = n + 1;
    if ~isfile(t{2}), bad{end+1} = [t{2} ' (absent)']; continue; end %#ok<AGROW>
    if ~strcmp(adopt_reading('sha', t{2}), t{1})
        if endsWith(lower(t{2}), {'.md', '.html.txt'}), living{end+1} = t{2}; else, bad{end+1} = [t{2} ' (changed)']; end %#ok<AGROW>
    end
end
rows(end+1) = mkrow(st, 'sources.sha256', ternary(isempty(bad), 'info', 'DIFF'), sprintf(['%d sources, %d result files changed or absent%s; ' ...
    '%d living documents (.md, notes) changed since the table was built%s'], n, numel(bad), list_text(': ', bad), numel(living), list_text(': ', living)));
map = containers.Map('KeyType', 'char', 'ValueType', 'char');
pairs = {fullfile(C.tree, 'results', 'policy_evaluation.txt'), fullfile(out, 'off', 'results', 'policy_evaluation.txt'); ...
    fullfile(C.tree, 'results', 'kpi_summary.txt'), fullfile(out, 'off', 'results', 'kpi_summary.txt'); ...
    fullfile(C.ad_root, 'on', 'results', 'policy_evaluation.txt'), fullfile(out, 'on', 'results', 'policy_evaluation.txt'); ...
    fullfile(C.ad_root, 'on', 'results', 'kpi_summary.txt'), fullfile(out, 'on', 'results', 'kpi_summary.txt'); ...
    fullfile(C.bw, 'results', 'core_bw', 'core_bw_report.txt'), fullfile(fileparts(out), 'light', 'bw', 'results', 'core_bw', 'core_bw_report.txt')};
for i = 1:size(pairs, 1)
    if isfile(pairs{i, 2}), map(norm_path(pairs{i, 1})) = pairs{i, 2}; end
end
V = lect_values(fullfile(C.lect, 'lect_numbers.csv'), map);
k = 'info'; if V.repro_missing > 0, k = 'DIFF'; elseif V.reworded > 0, k = 'DIFF-wording'; end
rows(end+1) = mkrow(st, 'lect_numbers.csv', k, ...
    sprintf(['%d numbers: %d literal on the cited line of the source file, %d derived (not literal there); %d of them cite a file ' ...
    'reproduced here; %d cited lines reworded there (the row''s numbers on one reproduced line, the words differ)%s; ' ...
    '%d cited lines missing from the reproduced file%s'], ...
    V.n, V.literal, V.derived, V.n_repro, V.reworded, list_text(': ', V.reworded_at(1:min(end, 10))), ...
    V.repro_missing, list_text(': ', V.missing(1:min(end, 10)))));
end

function V = lect_values(csv, map)
% The numbers of the table's csv against the files. literal: every printed number of the row occurs on
% its cited source line (the others are derived: a ratio, a difference). Where map holds a reproduced
% file for the source, the cited line must occur in it word for word (anywhere: this code may print
% more lines). A cited line not there word for word is reworded when one reproduced line holds every
% number of the row, else missing.
opts = detectImportOptions(csv, 'Delimiter', ',');
opts = setvartype(opts, opts.VariableNames, 'string');
opts.VariableNamingRule = 'preserve';
T = readtable(csv, opts);
cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
V = struct('n', height(T), 'literal', 0, 'derived', 0, 'n_repro', 0, 'repro_missing', 0, 'missing', {{}}, ...
    'reworded', 0, 'reworded_at', {{}});
for i = 1:height(T)
    f = char(T.source_file(i)); ln = str2double(T.source_line(i));
    nums = {};
    for c = {'value', 'ci_lo', 'ci_hi'}
        x = T.(c{1})(i);
        if ~ismissing(x) && strlength(x) > 0, nums{end+1} = char(x); end %#ok<AGROW>
    end
    L = get_lines(cache, f);
    if line_has(L, ln, nums), V.literal = V.literal + 1; else, V.derived = V.derived + 1; end
    k = norm_path(f);
    if ~isempty(map) && isKey(map, k)
        V.n_repro = V.n_repro + 1;
        R = get_lines(cache, map(k));
        if ln < 1 || ln > numel(L) || ~any(strcmp(R, L{ln}))
            at = find(arrayfun(@(j) line_has(R, j, nums), 1:numel(R)), 1);
            if ~isempty(nums) && ~isempty(at)
                V.reworded = V.reworded + 1;
                V.reworded_at{end+1} = sprintf('%s %s:%d -> line %d', char(T.id(i)), f, ln, at);
            else
                V.repro_missing = V.repro_missing + 1;
                V.missing{end+1} = sprintf('%s %s:%d', char(T.id(i)), f, ln);
            end
        end
    end
end
end

function L = get_lines(cache, f)
if isKey(cache, f), L = cache(f); return; end
if isfile(f), L = split_lines(f); else, L = {}; end
cache(f) = L;
end

function ok = line_has(L, ln, nums)
ok = ~isempty(L) && ln >= 1 && ln <= numel(L);
if ~ok, return; end
for i = 1:numel(nums)
    v = nums{i};
    ok = ok && (contains(L{ln}, v) || contains(L{ln}, regexprep(v, '^\+', '')));
end
end

function k = norm_path(p)
k = lower(strrep(char(p), '\', '/'));
k = regexprep(k, '/[^/]+/\.\./', '/');
end

%% ===================== Roots, copies, tree listings =====================
function build_root(root, tree, left_out)
% A run root of tree: params.mat, profile.json and results/ copied with their dates (less left_out,
% the outputs the run writes), data/*.mat as hard links (the attribute and content stay the tree's).
assert(~isfolder(root), 'b1r_repro:exists', 'b1r_repro: %s exists', root);
assert(~strncmpi([root filesep], [tree filesep], numel(tree) + 1), 'b1r_repro:inside', 'b1r_repro: %s lies inside %s', root, tree);
F = adopt_reading('tree_files', tree);
mkdir(root);
for i = 1:numel(F)
    src = fullfile(tree, F{i}); dst = fullfile(root, F{i});
    if startsWith(F{i}, 'data/')
        mk_parent(dst);
        java.nio.file.Files.createLink(jpath(dst), jpath(src));
        assert(java.nio.file.Files.isSameFile(jpath(dst), jpath(src)), 'b1r_repro:link', 'b1r_repro: %s is no link of %s', dst, src);
    elseif ~ismember(F{i}, left_out)
        mk_parent(dst); copy_keep(src, dst);
    end
end
end

function copy_keep(src, dst)
% A copy with the source's modification time.
mk_parent(dst);
assert(~isfile(dst), 'b1r_repro:overwrite', 'b1r_repro: %s exists', dst);
s = jpath(src); d = jpath(dst);
o = javaArray('java.nio.file.CopyOption', 1); o(1) = java.nio.file.StandardCopyOption.COPY_ATTRIBUTES;
java.nio.file.Files.copy(s, d, o);
lo = javaArray('java.nio.file.LinkOption', 0);
t = java.nio.file.Files.getLastModifiedTime(s, lo);
if ~t.equals(java.nio.file.Files.getLastModifiedTime(d, lo)), java.nio.file.Files.setLastModifiedTime(d, t); end
assert(java.nio.file.Files.size(d) == java.nio.file.Files.size(s), 'b1r_repro:copy', 'b1r_repro: the copy %s differs in size', dst);
end

function S = tree_state(tree)
% results, params and profile.json hashed, data by size and date: what a read must leave as it is.
F = adopt_reading('tree_files', tree);
S = cell(size(F));
for i = 1:numel(F)
    f = fullfile(tree, F{i});
    if startsWith(F{i}, 'data/'), d = dir(f); S{i} = sprintf('%s %d %.8f', F{i}, d.bytes, d.datenum);
    else, S{i} = sprintf('%s %s', F{i}, adopt_reading('sha', f)); end
end
end

function bad = tree_diff(a, b, skip)
% Files of folder a (less the top-level folders in skip) that differ or are absent in b, by SHA-256.
bad = {};
d = dir(fullfile(a, '**', '*')); d = d(~[d.isdir]);
for k = 1:numel(d)
    p = fullfile(d(k).folder, d(k).name); rel = p(numel(a) + 2:end);
    if any(startsWith(rel, strcat(skip, filesep))), continue; end
    q = fullfile(b, rel);
    if ~isfile(q) || ~strcmp(adopt_reading('sha', p), adopt_reading('sha', q)), bad{end+1} = rel; end %#ok<AGROW>
end
end

function rows = cmp_tree(st, prefix, mine, ref)
rows = new_rows();
if ~isfolder(ref), rows(end+1) = mkrow(st, [prefix '(folder)'], 'info', sprintf('no registered folder %s', ref)); return; end
fm = rel_files(mine); fr = rel_files(ref);
d1 = setdiff(fm, fr); d2 = setdiff(fr, fm);
rows(end+1) = mkrow(st, [prefix 'files'], ternary(isempty(d1) && isempty(d2), 'info', 'DIFF'), ...
    sprintf('%d files here, %d registered%s%s', numel(fm), numel(fr), list_text('; only here: ', d1), list_text('; only registered: ', d2)));
for f = reshape(intersect(fm, fr), 1, [])
    rows(end+1) = cmp_files(st, [prefix f{1}], fullfile(mine, f{1}), fullfile(ref, f{1})); %#ok<AGROW>
end
end

function F = rel_files(base)
F = {};
if ~isfolder(base), return; end
d = dir(fullfile(base, '**', '*')); d = d(~[d.isdir]);
for k = 1:numel(d)
    p = fullfile(d(k).folder, d(k).name); F{end+1} = strrep(p(numel(base) + 2:end), '\', '/'); end %#ok<AGROW>
F = sort(F);
end

%% ===================== Comparison =====================
function r = cmp_files(stage, name, mine, ref)
if ~isfile(mine)
    if isfile(ref), r = mkrow(stage, name, 'DIFF', 'not produced here');
    else, r = mkrow(stage, name, 'info', 'neither produced here nor registered'); end
    return
end
if ~isfile(ref), r = mkrow(stage, name, 'info', sprintf('nothing registered; sha256 %s', adopt_reading('sha', mine))); return; end
if dir(mine).bytes == dir(ref).bytes && strcmp(adopt_reading('sha', mine), adopt_reading('sha', ref))
    r = mkrow(stage, name, 'exact', 'bytes equal'); return
end
[~, ~, e] = fileparts(mine);
switch lower(e)
    case {'.mat', '.json'}
        if strcmpi(e, '.mat'), A = load(mine); B = load(ref); else, A = jsondecode(fileread(mine)); B = jsondecode(fileread(ref)); end
        D = struct_diff(A, B);
        if isempty(D), r = mkrow(stage, name, 'equal-fields', 'all fields isequaln; bytes differ (stamps, storage)');
        else
            k = diff_kind(D, '(?i)generated|created|timestamp|elapsed|runtime|wallclock|minutes|duration|datenum|date');
            if strcmp(k, 'DIFF') && all(cellfun(@(d) contains(d, '(only here)') || contains(d, '#size'), D)), k = 'DIFF-additive'; end
            r = mkrow(stage, name, k, sprintf('%d differing fields: %s', numel(D), strjoin(D(1:min(end, 12)), ' | ')));
        end
    case {'.txt', '.csv', '.md'}
        La = scrub_lines(split_lines(mine)); Lb = scrub_lines(split_lines(ref));
        if isequal(La, Lb), r = mkrow(stage, name, 'equal-lines', sprintf('%d lines equal, Generated lines aside', numel(La))); return; end
        here = La(~ismember(La, Lb)); regd = Lb(~ismember(Lb, La));
        n = min(numel(La), numel(Lb));
        k = find(~cellfun(@strcmp, La(1:n), Lb(1:n)), 1);
        det = sprintf('%d vs %d lines, first difference at line %d; %d only here%s; %d only registered%s', numel(La), numel(Lb), ...
            first_or(k, n + 1), numel(here), quote_list(here), numel(regd), quote_list(regd));
        if isempty(regd) && is_subsequence(Lb, La)
            r = mkrow(stage, name, 'DIFF-additive', ['every registered line is here, in order; ' det]);
        elseif numbers_kept(regd, here)
            r = mkrow(stage, name, 'DIFF-wording', ['the registered lines not here differ in words only: each one''s numbers ' ...
                'occur, in order, on a line printed here; ' det]);
        else
            r = mkrow(stage, name, diff_kind([here, regd], '(?i)generated:|elapsed|\(\d+(\.\d+)? min\)|created'), det);
        end
    case '.png'
        ia = imread(mine); ib = imread(ref);
        if ~isequal(size(ia), size(ib)), r = mkrow(stage, name, 'DIFF', sprintf('image sizes %s vs %s', mat2str(size(ia)), mat2str(size(ib)))); return; end
        npx = nnz(any(ia ~= ib, 3)); sh = npx / (size(ia, 1) * size(ia, 2));
        r = mkrow(stage, name, ternary(sh <= 0.005, 'rendering', 'DIFF'), sprintf('%d pixels differ (%.3f%%, rendering limit 0.5%%)', npx, 100 * sh));
    otherwise
        r = mkrow(stage, name, 'DIFF', 'bytes differ');
end
end

function k = diff_kind(D, pat)
k = 'DIFF';
if all(cellfun(@(d) ~isempty(regexp(d, pat, 'once')), D)), k = 'DIFF-timing'; end
end

function t = quote_list(c)
t = '';
if isempty(c), return; end
c = c(1:min(end, 3));
t = [' (' strjoin(cellfun(@(x) ['"' cut(strtrim(x), 110) '"'], c, 'UniformOutput', false), ' | ') ')'];
end

function v = first_or(k, d)
if isempty(k), v = d; else, v = k(1); end
end

function tf = numbers_kept(regd, here)
% Every registered-only line has a line printed here whose numbers hold its numbers in order (here
% may print more numbers on the line); a line without numbers differs in words only.
nh = cellfun(@line_numbers, here, 'UniformOutput', false);
tf = true;
for i = 1:numel(regd)
    nr = line_numbers(regd{i});
    if isempty(nr), continue; end
    if ~any(cellfun(@(h) is_subsequence(nr, h), nh)), tf = false; return; end
end
end

function c = line_numbers(s)
c = regexp(s, '(?<![A-Za-z_\d.])[-+]?\d+(\.\d+)?', 'match');  % F1, rx3, D121: names, not numbers
c = regexprep(c, '^\+', '');
end

function tf = is_subsequence(b, a)
% b occurs in a in order (a may hold more lines).
j = 1;
for i = 1:numel(a)
    if j <= numel(b) && strcmp(a{i}, b{j}), j = j + 1; end
end
tf = j > numel(b);
end

function L = scrub_lines(L)
for i = 1:numel(L)
    if startsWith(strtrim(L{i}), 'Generated:'), L{i} = 'Generated: <stamp>'; end
end
end

function D = struct_diff(A, B, p, D)
% Paths where A and B are not isequaln (NaN equal), a field named generated and 'Generated:' strings aside.
if nargin < 3, p = 'x'; D = {}; end
if numel(D) >= 200 || isequaln(A, B), return; end
if isstruct(A) && isstruct(B)
    if ~isequal(size(A), size(B)), D{end+1} = sprintf('%s#size %s vs %s', p, mat2str(size(A)), mat2str(size(B))); return; end
    fa = fieldnames(A); fb = fieldnames(B);
    for f = reshape(setdiff(fa, fb), 1, []), D{end+1} = sprintf('%s.%s (only here)', p, f{1}); end %#ok<AGROW>
    for f = reshape(setdiff(fb, fa), 1, []), D{end+1} = sprintf('%s.%s (only registered)', p, f{1}); end %#ok<AGROW>
    for i = 1:numel(A)
        for f = reshape(intersect(fa, fb), 1, [])
            if strcmpi(f{1}, 'generated'), continue; end
            if isscalar(A), q = [p '.' f{1}]; else, q = sprintf('%s(%d).%s', p, i, f{1}); end
            D = struct_diff(A(i).(f{1}), B(i).(f{1}), q, D);
        end
    end
elseif iscell(A) && iscell(B)
    if ~isequal(size(A), size(B)), D{end+1} = sprintf('%s#size %s vs %s', p, mat2str(size(A)), mat2str(size(B))); return; end
    for i = 1:numel(A), D = struct_diff(A{i}, B{i}, sprintf('%s{%d}', p, i), D); end
elseif ischar(A) && ischar(B) && startsWith(strtrim(A), 'Generated:') && startsWith(strtrim(B), 'Generated:')
    return
elseif (isnumeric(A) || islogical(A)) && (isnumeric(B) || islogical(B)) && isequal(size(A), size(B))
    m = ~(A == B | (isnan(A) & isnan(B)));
    d = double(A(m)) - double(B(m));
    D{end+1} = sprintf('%s: %d of %d values differ, max abs %.3g', p, nnz(m), numel(A), max(abs(d(~isnan(d)))));
else
    D{end+1} = sprintf('%s: %s vs %s', p, class(A), class(B));
end
end

%% ===================== Small helpers =====================
function L = split_lines(f)
s = fileread(f);
s = strrep(s, char(13), '');
L = splitlines(s);
if ~isempty(L) && isempty(L{end}), L(end) = []; end
L = reshape(L, 1, []);
end

function s = list_text(head, c)
s = '';
if ~isempty(c), s = [head strjoin(reshape(c, 1, []), ', ')]; end
end

function s = cut(s, n)
s = char(s); if numel(s) > n, s = [s(1:n) '...']; end
end

function mk_parent(f)
d = fileparts(f);
if ~isfolder(d), mkdir(d); end
end

function p = jpath(f)
p = java.io.File(char(f)).toPath();
end

function h = git_head(d)
[st, out] = system(sprintf('git --no-optional-locks -C "%s" rev-parse HEAD', d));
h = strtrim(out); if st ~= 0, h = 'unknown'; end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
