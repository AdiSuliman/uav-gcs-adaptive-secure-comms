function tests = test_core_bw_adopted_kpis
%TEST_CORE_BW_ADOPTED_KPIS  core_bw_adopted_kpis.m: hand-computed goodput, recovery time, counts and
%   never-restored on synthetic episodes; the carried readers equal experiment_core_bw.m's word
%   for word; the gate passes on consistent data and catches a changed number; the reading is
%   refused when its outputs exist; inputs are untouched.
%   Run from the repository root: results = runtests('code/tests/test_core_bw_adopted_kpis.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
end

function test_rows_hand_computed(tc)
[S, EP, mask, X] = world();
[Rw, lines] = core_bw_adopted_kpis('rows', S, EP, mask, X, 1000);
r = Rw(strcmp({Rw.policy}, 'rule_core3') & strcmp({Rw.type}, 'narrowband'));
verifyEqual(tc, [r.n r.n_rec r.never r.never_rec], [2 2 0 0]);
verifyEqual(tc, [r.rec_det.median r.rec_det.p90 r.rec_det.never_pct], [2 4 0], 'AbsTol', 1e-12);
verifyEqual(tc, r.gput(1), 2000, 'AbsTol', 1e-9);
r = Rw(strcmp({Rw.policy}, 'rule_core3') & strcmp({Rw.type}, 'wideband'));
verifyEqual(tc, [r.n r.n_rec r.never r.never_rec], [3 1 2 1]);
verifyEqual(tc, [r.rec_det.median r.rec_det.p90], [2 2], 'AbsTol', 1e-12);
verifyEqual(tc, r.rec_det.never_pct, 100 * 2 / 3, 'AbsTol', 1e-9);
verifyEqual(tc, r.gput(1), 3000, 'AbsTol', 1e-9);
r = Rw(strcmp({Rw.policy}, 'rule_core3') & strcmp({Rw.type}, 'pooled'));
verifyEqual(tc, [r.n r.n_rec r.never r.never_rec], [5 3 2 1]);
verifyEqual(tc, [r.rec_det.median r.rec_det.p90 r.rec_det.never_pct], [2 4 40], 'AbsTol', 1e-12);
verifyEqual(tc, r.gput(1), 2600, 'AbsTol', 1e-9);
verifySubstring(tc, r.seg, 'detection->restored (5 cycles) 2/4 (never 40%) | goodput 2600 [');
verifyEqual(tc, numel(Rw), 12);
verifyEqual(tc, numel(lines), 12);
end

function test_carried_functions_word_for_word(tc)
% Each reader is the text of experiment_core_bw.m's, line ends aside.
a = fileread(fullfile(tc.TestData.root, 'code', 'decision', 'core_bw_adopted_kpis.m'));
b = fileread(fullfile(tc.TestData.root, 'code', 'decision', 'experiment_core_bw.m'));
for f = {'read_recoverable', 'recoverable_mask', 'get_set', 'pol', 'qstat'}
    ta = function_text(a, f{1}); tb = function_text(b, f{1});
    verifyNotEmpty(tc, ta, f{1});
    verifyEqual(tc, ta, tb, sprintf('%s differs from experiment_core_bw.m', f{1}));
end
end

function test_gate_passes_and_catches_change(tc)
[S, EP, mask, X] = world();
[T, U, KP, REC, rep, rdl] = registered(S, EP, mask, X, 1000);
G = core_bw_adopted_kpis('gate', T, U, KP, REC, rep, rdl, 1000);
verifyTrue(tc, G.pass, strjoin(G.mismatch, ' | '));
verifyEqual(tc, G.mask, mask);
T2 = T; T2.P(1).per = T2.P(1).per + 1e-12;
verifyFalse(tc, core_bw_adopted_kpis('gate', T2, U, KP, REC, rep, rdl, 1000).pass);
T3 = T; T3.x1s.rule_core3.per_post(1) = T3.x1s.rule_core3.per_post(1) + 0.01;
verifyFalse(tc, core_bw_adopted_kpis('gate', T3, U, KP, REC, rep, rdl, 1000).pass);
rep2 = rep; i = find(startsWith(rep2, '  rule_core3 pooled'), 1); rep2{i} = strrep(rep2{i}, 'goodput', 'goodputs');
verifyFalse(tc, core_bw_adopted_kpis('gate', T, U, KP, REC, rep2, rdl, 1000).pass);
rdl2 = rdl(~startsWith(rdl, '  on   CNN contribution narrowband'));
verifyFalse(tc, core_bw_adopted_kpis('gate', T, U, KP, REC, rep, rdl2, 1000).pass);
end

function test_run_refuses_existing_outputs_and_failed_gate_writes_nothing(tc)
d = tempname; mkdir(d); cleanup = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
in = fullfile(d, 'in'); out = fullfile(d, 'out'); mkdir(in); mkdir(out);
tm = fullfile(in, 'test.mat'); x = 1; save(tm, 'x');
fid = fopen(fullfile(in, 'selection.json'), 'w'); fprintf(fid, '{"bound":"keep+rate","tree":"%s"}', strrep(d, '\', '/')); fclose(fid);
fid = fopen(fullfile(in, 'core_bw_rule_fix_reading.txt'), 'w'); fprintf(fid, 'x\n'); fclose(fid);
files = dir(in); files = fullfile(in, {files(~[files.isdir]).name});
h0 = cellfun(@(f) core_bw_rules('sha', f), files, 'UniformOutput', false);
% the registered study is missing: refused as an input error, nothing written, inputs unchanged
verifyError(tc, @() core_bw_adopted_kpis('run', tm, out), 'core_bw_adopted_kpis:input');
verifyEmpty(tc, dir(fullfile(out, 'core_bw_adopted_kpis.*')));
% an existing output is refused first
fid = fopen(fullfile(out, 'core_bw_adopted_kpis.txt'), 'w'); fprintf(fid, 'old\n'); fclose(fid);
verifyError(tc, @() core_bw_adopted_kpis('run', tm, out), 'core_bw_adopted_kpis:once');
verifyEqual(tc, fileread(fullfile(out, 'core_bw_adopted_kpis.txt')), sprintf('old\n'));
h1 = cellfun(@(f) core_bw_rules('sha', f), files, 'UniformOutput', false);
verifyEqual(tc, h1, h0);
end

function test_run_end_to_end_inputs_untouched(tc)
% A synthetic study tree whose registered numbers are consistent: the reading passes, writes, and leaves every input as it was.
[S, EP, mask, X] = world();
[T, U, KP, REC, rep, rdl] = registered(S, EP, mask, X, 1000);
d = tempname; mkdir(d); cleanup = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
in = fullfile(d, 'in'); out = fullfile(d, 'out'); tree = fullfile(d, 'tree');
mkdir(in); mkdir(out); mkdir(fullfile(tree, 'results', 'core_bw'));
x1s = T.x1s; P = T.P; save(fullfile(in, 'test.mat'), 'x1s', 'P');
fid = fopen(fullfile(in, 'selection.json'), 'w'); fprintf(fid, '{"bound":"keep+rate","tree":"%s"}', strrep(tree, '\', '/')); fclose(fid);
write_text(fullfile(in, 'core_bw_rule_fix_reading.txt'), rdl);
write_text(fullfile(tree, 'results', 'core_bw', 'core_bw_report.txt'), rep);
RES = U.RES; EPs = U.EPs; meta = struct(); %#ok<NASGU>
save(fullfile(tree, 'results', 'core_bw', 'test_readings.mat'), 'RES', 'EPs', 'X', 'meta');
save(fullfile(tree, 'results', 'core_bw', 'core_bw_kpis.mat'), 'KP');
rc = {'# list'}; for i = 1:numel(REC.k), rc{end+1} = sprintf('H1 %d %d name 0 0 0 0 0 0 0 1 1', REC.k(i), REC.s(i)); end %#ok<AGROW>
write_text(fullfile(tree, 'results', 'core_bw', 'recoverable.txt'), rc);
params = struct('bits_per_frame', 1000, 'cycle_s', 1); save(fullfile(tree, 'params.mat'), 'params');
ins = {fullfile(in, 'test.mat'), fullfile(in, 'selection.json'), fullfile(in, 'core_bw_rule_fix_reading.txt'), ...
    fullfile(tree, 'results', 'core_bw', 'test_readings.mat'), fullfile(tree, 'results', 'core_bw', 'recoverable.txt'), ...
    fullfile(tree, 'results', 'core_bw', 'core_bw_kpis.mat'), fullfile(tree, 'results', 'core_bw', 'core_bw_report.txt'), ...
    fullfile(tree, 'params.mat')};
h0 = cellfun(@(f) core_bw_rules('sha', f), ins, 'UniformOutput', false);
evalc('core_bw_adopted_kpis(''run'', ins{1}, out)');
h1 = cellfun(@(f) core_bw_rules('sha', f), ins, 'UniformOutput', false);
verifyEqual(tc, h1, h0);
txt = fileread(fullfile(out, 'core_bw_adopted_kpis.txt'));
verifySubstring(tc, txt, 'G4 GATE PASS');
verifySubstring(tc, txt, 'rule_core3 wideband   n=3 n_rec=1 | never restored 2 of 3, 1 of 1');
verifyTrue(tc, isfile(fullfile(out, 'core_bw_adopted_kpis.mat')));
verifyError(tc, @() core_bw_adopted_kpis('run', ins{1}, out), 'core_bw_adopted_kpis:once');
end

%% ===================== Synthetic study =====================
function [S, EP, mask, X] = world()
% 6 episodes, 3 flights; narrowband 1-2, wideband 3-6; episode 6 is a slice cell, outside the mask.
EP = struct('n', 6, 'k', ones(1, 6), 's', ones(1, 6), 'slice', logical([0 0 0 0 0 1]), 'occ', false(1, 6), ...
    'narrow', logical([1 1 0 0 0 0]), 'geom', [1 1 2 2 3 3]);
mask = logical([1 1 1 1 1 0]);
X = struct('B', 50, 'N_RUN', 5, 'RULES', {{'H1'}}, 'TARGET', 0.3);
base = struct('ep', 1:6, 'recoverable', logical([1 1 1 0 1 1]), 'threat', logical([1 1 1 1 0 1]), 'geom', EP.geom);
R3 = base; R3.t_rec_det = [0 4 NaN 2 NaN 1]; R3.dlv_post = [1 3 0 2 7 9]; R3.per_post = [0.1 0.2 0.3 0.4 0.5 0.6];
Rc = base; Rc.t_rec_det = [1 1 1 NaN 3 0]; Rc.dlv_post = [2 2 2 1 1 1]; Rc.per_post = [0.2 0.2 0.4 0.4 0.6 0.6];
Rb = base; Rb.t_rec_det = [NaN 2 2 2 NaN NaN]; Rb.dlv_post = [0 1 2 3 4 5]; Rb.per_post = [0.3 0.1 0.2 0.5 0.4 0.7];
Rn = base; Rn.t_rec_det = NaN(1, 6); Rn.dlv_post = zeros(1, 6); Rn.per_post = [0.9 0.8 1 1 0.9 1];
S = struct('policy', {'none', 'blind_core', 'rule_core', 'rule_core3'}, 'R', {Rn, Rb, Rc, R3});
end

function [T, U, KP, REC, rep, rdl] = registered(S, EP, mask, X, pay)
% Registered readings made consistent with the module's own rows, in the formats of the report and the reading.
U = struct('RES', struct('rule', 'H1', 'set', 'primary', 'policy', {S.policy}, 'R', {S.R}), 'EPs', EP, 'X', X);
REC = struct('rule', {{'H1'}}, 'k', 1, 's', 1, 'harm', true, 'ok', true);
Pof = core_bw_adopted_kpis('per_rows', S, EP, mask, X);
[Rw, ~] = core_bw_adopted_kpis('rows', S, EP, mask, X, pay);
KP = struct('primary', struct('per', Pof, 'rec', struct(), 'gput', struct()));
rep = {'header'};
for r = Rw
    KP.primary.rec.(r.policy).(r.type) = struct('det', struct(), 'rec_det', r.rec_det);
    KP.primary.gput.(r.policy).(r.type) = r.gput;
    rep{end+1} = sprintf('  %-10s %-10s onset->detection 1/1 (never 0%%) | %s', r.policy, r.type, r.seg); %#ok<AGROW>
    if strcmp(r.type, 'pooled') && ~strcmp(r.policy, 'none')
        rep{end+1} = sprintf('  PER %-10s pooled, recoverable episodes only (n=%d): reduction', r.policy, r.n_rec); %#ok<AGROW>
    end
end
% the "on" setting: another rule_core3 per-episode PER, otherwise the same arrays
x1s = struct();
for i = 1:numel(S), x1s.(S(i).policy) = S(i).R; end
x1s.rule_core3.per_post = x1s.rule_core3.per_post * 0.5;
Son = struct('policy', fieldnames(x1s)', 'R', cellfun(@(f) x1s.(f), fieldnames(x1s)', 'UniformOutput', false));
Pon = core_bw_adopted_kpis('per_rows', Son, EP, mask, X);
T = struct('x1s', x1s, 'P', Pon);
rdl = [arrayfun(@(p) core_bw_adopted_kpis('per_text', 'off', p), Pof, 'UniformOutput', false), ...
    core_bw_adopted_kpis('cnn_text', 'off', S, EP, mask, X), ...
    arrayfun(@(p) core_bw_adopted_kpis('per_text', 'on', p), Pon, 'UniformOutput', false), ...
    core_bw_adopted_kpis('cnn_text', 'on', Son, EP, mask, X)];
end

function write_text(f, lines)
fid = fopen(f, 'w'); fprintf(fid, '%s\n', lines{:}); fclose(fid);
end

function t = function_text(src, name)
% The text of a local function: from its header line to the line before the next function or section.
L = splitlines(strrep(src, char(13), ''));
i = find(~cellfun(@isempty, regexp(L, ['^function [^\n]*\<' name '\('], 'once')), 1);
t = '';
if isempty(i), return; end
j = i + 1;
while j <= numel(L) && ~startsWith(L{j}, 'function ') && ~startsWith(L{j}, '%% '), j = j + 1; end
B = L(i:j - 1);
while ~isempty(B) && isempty(strtrim(B{end})), B(end) = []; end
t = strjoin(B, newline);
end
