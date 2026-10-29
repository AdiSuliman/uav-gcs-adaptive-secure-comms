function tests = test_lect_kpi_table
%TEST_LECT_KPI_TABLE  Tests of lect_kpi_table.m (the lecturer's KPI table, a pure reader).
%   results = runtests('code/tests/test_lect_kpi_table.m')
%   The smoke tree's policy_evaluation.mat is read from LECT_TABLE_SMOKE (default
%   C:\Users\Adi Suliman\d91q\deploy2\smoke); its test is skipped when the folder is absent.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
smoke = getenv('LECT_TABLE_SMOKE');
if isempty(smoke), smoke = 'C:\Users\Adi Suliman\d91q\deploy2\smoke'; end
tc.TestData.smoke = smoke;
end

function d = new_dir(tc)
d = tempname; mkdir(d);
tc.addTeardown(@() rmdir(d, 's'));
end

%% ---------- tests ----------
function test_empty_folder_all_pending(tc)
% No input: the table is written, every KPI reads pending and no figure is made.
d = new_dir(tc);
[T, lines] = lect_kpi_table(d);
verifyTrue(tc, isfile(fullfile(d, 'lect_kpi_table.txt')) && isfile(fullfile(d, 'lect_kpi_table.csv')));
verifyFalse(tc, any(cellfun(@(f) isfile(fullfile(d, f)), {'lect_kpi_per.png', 'lect_kpi_recovery.png', 'lect_kpi_goodput.png'})));
verifyTrue(tc, all(strncmp({T.rows.verdict}, 'pending', 7)));
verifyEqual(tc, sort(unique([T.rows.kpi])), 1:9);              % 9: the system false-alarm extension
verifyTrue(tc, any(contains(lines, 'pending (CORE_BW)')));
verifyTrue(tc, any(contains(lines, 'Link-limited points (D99): pending')));
verifyEqual(tc, numel(T.files), 2);
end

function test_missing_folder_errors(tc)
verifyError(tc, @() lect_kpi_table(fullfile(tempname, 'nope')), 'lect_kpi_table:folder');
end

function test_full_tables_and_files(tc)
% Every input present: the verdict words and intervals are the saved structs', in the proposal's
% numbering, with the network and the policy pair named on each row; three figures are written.
d = new_dir(tc);
[L, KP] = write_inputs(d, true, true);
before = file_hashes(d);
[T, lines] = lect_kpi_table(d);
verifyEqual(tc, file_hashes(d), before, 'the reader changed an input');
for f = {'lect_kpi_table.txt', 'lect_kpi_table.csv', 'lect_kpi_per.png', 'lect_kpi_recovery.png', 'lect_kpi_goodput.png'}
    verifyTrue(tc, isfile(fullfile(d, f{1})), f{1});
    if endsWith(f{1}, '.png'), verifyGreaterThan(tc, dir(fullfile(d, f{1})).bytes, 5000); end
end
Z = readtable(fullfile(d, 'lect_kpi_table.csv'), 'TextType', 'string', 'VariableNamingRule', 'preserve');
verifyEqual(tc, height(Z), numel(T.rows));
verifyEqual(tc, string(Z.Properties.VariableNames), ["kpi" "kpi_name" "target" "reading" "network" "policy" "versus" "pair_set" ...
    "action_set" "line" "episodes" "n" "value" "lo" "hi" "unit" "p90" "never_pct" "verdict" "role" "source" "note"]);
verifyEqual(tc, sort(unique(Z.kpi))', 1:9);
% KPI 5: the saved verdict words and intervals
v = L.core.verdict;
for i = 1:numel(v)
    m = Z.kpi == 5 & Z.role == "verdict" & Z.policy == v(i).policy & contains(Z.reading, v(i).scenario);
    verifyEqual(tc, nnz(m), 1);
    verifyEqual(tc, Z.verdict(m), string(v(i).verdict));
    verifyEqual(tc, [Z.value(m) Z.lo(m) Z.hi(m)], [v(i).red_pct v(i).ci], 'RelTol', 1e-8);
    verifyEqual(tc, Z.versus(m), "none");
    verifyTrue(tc, contains(Z.network(m), "hybrid detector") && contains(Z.network(m), "not the three-state CNN"));
    verifyTrue(tc, contains(Z.pair_set(m), "rule_core"));
end
% extension and secondary rows are labelled, never verdict rows
e = Z(Z.kpi == 5 & Z.policy == "rule_esc", :);
verifyNotEmpty(tc, e); verifyTrue(tc, all(e.role == "extension"));
b = Z(Z.kpi >= 3 & Z.kpi <= 8 & Z.policy == "blind_core", :);
verifyNotEmpty(tc, b);
verifyTrue(tc, all(b.role == "secondary"));
verifyTrue(tc, all(contains(b.note, "weakened baseline")));
k8c = Z(Z.kpi == 8 & Z.versus == "blind_core" & ~contains(Z.pair_set, "CORE_BW") & contains(Z.action_set, "core"), :);
verifyNotEmpty(tc, k8c);
verifyTrue(tc, all(contains(k8c.note, "weakened baseline")));
verifyTrue(tc, all(contains(k8c.note, "CORE_BW")));
verifyTrue(tc, all(contains(Z.network(Z.policy == "blind_core"), "link metrics only")));
verifyTrue(tc, all(contains(Z.network(Z.policy == "none" & Z.kpi >= 5), "static link")));
% three-state CNN rows only in KPI 2-4
c3 = Z(contains(Z.network, "three-state CNN on spectrograms"), :);
verifyTrue(tc, all(ismember(c3.kpi, 2:4)));
verifyFalse(tc, any(contains(Z.network(Z.kpi >= 5), "three-state CNN on spectrograms")));
o = Z(Z.kpi == 2 & Z.role == "verdict", :);
verifyEqual(tc, height(o), 1);
verifyEqual(tc, [o.value o.lo o.hi], [91.5 90.1 92.8], 'RelTol', 1e-8);
verifyEqual(tc, o.verdict, "met (committed)");
verifyEqual(tc, height(Z(Z.kpi == 4 & Z.role == "verdict", :)), 2);
verifyEqual(tc, Z.verdict(Z.kpi == 3 & Z.role == "verdict"), "met (committed)");
hy = Z(Z.kpi >= 2 & Z.kpi <= 4 & contains(Z.network, "same frames as B3c"), :);
verifyTrue(tc, all(startsWith(hy.verdict, "pending")));
% KPI 1: the phy report
p1 = Z(Z.kpi == 1, :);
verifyEqual(tc, p1.verdict(p1.role == "verdict"), "PASS (2/2)");
verifyEqual(tc, sort(p1.value(p1.role == "measured"))', [0.03 0.08], 'AbsTol', 1e-12);
% system false alarms: an extension label of their own, none of them under proposal KPI 3
s = Z(Z.kpi == 9 & Z.policy == "rule_core", :);
verifyEqual(tc, height(s), 1);
verifyEqual(tc, Z.role(Z.kpi == 9 & Z.policy == "blind_esc"), "extension");
verifyTrue(tc, all(Z.kpi_name(Z.kpi == 9) == "extension: system FA (project KPI 6, D103)"));
verifyFalse(tc, any(Z.kpi == 3 & contains(Z.reading, "system false alarms")));
fr = KP.far(strcmp({KP.far.policy}, 'core: rule + escalation'));
verifyEqual(tc, s.value, 100 * fr.p, 'RelTol', 1e-8);
verifyEqual(tc, s.hi, 100 * fr.upper, 'RelTol', 1e-8);
% KPI 6: Line A rows and the D99 Line B headline
h = Z(Z.kpi == 6 & Z.role == "headline", :);
verifyNotEmpty(tc, h); verifyTrue(tc, all(h.line == "B"));
verifyTrue(tc, any(contains(lines, 'detection -> restored is set by construction')));
verifyFalse(tc, any(startsWith(Z.verdict(Z.kpi == 6), "pending")));
% KPI 6 recovery value in ms from the saved median in cycles
q = L.core.rec(strcmp({L.core.rec.set}, 'recoverable jamming episodes') & strcmp({L.core.rec.policy}, 'rule_core'));
m = Z.kpi == 6 & Z.role == "measured" & Z.policy == "rule_core" & contains(Z.reading, "onset -> detection") & Z.line == "A" ...
    & contains(Z.episodes, "recoverable jamming");
verifyEqual(tc, nnz(m), 1);
verifyEqual(tc, Z.value(m & contains(Z.episodes, "recoverable jamming episodes")), q.det.median * L.period_ms, 'AbsTol', 1e-9);
% KPI 7 and 8
g = L.core.gput(strcmp({L.core.gput.policy}, 'rule_core'));
m = Z.kpi == 7 & Z.policy == "rule_core" & contains(Z.reading, "threat episodes") & ~contains(Z.reading, "jamming") & Z.line == "A" ...
    & ~contains(Z.pair_set, "36-configuration mask");
verifyEqual(tc, [Z.value(m) Z.lo(m) Z.hi(m)], [g.bps g.ci], 'RelTol', 1e-8);
k8 = Z(Z.kpi == 8 & Z.role == "headline", :);
verifyEqual(tc, height(k8), 9);                                 % CORE_BW: pooled, narrowband, wideband x 3 readings
verifyTrue(tc, all(k8.verdict == "analysis, no target"));
verifyEqual(tc, Z.value(Z.kpi == 8 & Z.role == "headline" & contains(Z.reading, "PER reduction") & contains(Z.reading, "pooled")), 12.5, 'AbsTol', 1e-9);
bw = Z(Z.kpi == 5 & Z.role == "beside", :);
verifyEqual(tc, bw.verdict, ["MET (committed)"; "NOT MET"]);
verifyTrue(tc, any(contains(lines, 'link-limited (L) 0 dB, 3 dB | marginal (M) 6 dB, 9 dB | working point (J) 12 dB, 15 dB')));
verifyFalse(tc, any(contains(lines, 'pending (CORE_BW)')));
end

function test_far_words_follow_the_bound(tc)
% The system false-alarm word follows the one-sided 95% bound: at most 5% -> met, only the point
% estimate at most 5% -> 'point estimate only', otherwise not met. Nothing is filed under KPI 3.
d = new_dir(tc);
write_inputs(d, false, false);
S = load(fullfile(d, 'policy_evaluation.mat'));
up = [0.04 0.049 0.065 0.08 0.2]; pp = [0.02 0.03 0.05 0.07 0.15];
for j = 1:numel(S.KP.far), S.KP.far(j).p = pp(j); S.KP.far(j).upper = up(j); S.KP.far(j).k = round(pp(j) * 600); end
save(fullfile(d, 'policy_evaluation.mat'), '-struct', 'S');
[T, lines] = lect_kpi_table(d);
E = T.rows([T.rows.kpi] == 9);
verifyNumElements(tc, E, 5);
verifyTrue(tc, all(strcmp({E.role}, 'extension')));
w = containers.Map({E.policy}, {E.verdict});
verifyEqual(tc, w('none'), 'MET (bound <= 5%)');
verifyEqual(tc, w('rule_esc'), 'MET (bound <= 5%)');
verifyEqual(tc, w('blind_esc'), 'point estimate only');
verifyEqual(tc, w('rule_core'), 'NOT MET');
verifyEqual(tc, w('blind_core'), 'NOT MET');
verifyEmpty(tc, T.rows([T.rows.kpi] == 3 & strcmp({T.rows.role}, 'system')));
verifyTrue(tc, any(startsWith(lines, 'EXTENSION, not a proposal KPI: extension: system FA (project KPI 6, D103)')));
end

function test_core3_rows_headline(tc)
% CORE_BW with rule_core3 (D106): it is the headline of KPI 5 and 8 against the validation-tuned
% blind_core, rule_core is 'hybrid, secondary', rule_core3 - rule_core is descriptive.
d = new_dir(tc);
write_inputs(d, true, true);
write_bw(d, true);
[T, lines] = lect_kpi_table(d);
R = T.rows;
h = R([R.kpi] == 8 & strcmp({R.role}, 'headline'));
verifyNumElements(tc, h, 9);
verifyTrue(tc, all(strcmp({h.policy}, 'rule_core3') & strcmp({h.versus}, 'blind_core') & strcmp({h.network}, 'CNN3_LOOP')));
verifyTrue(tc, all(contains({h.pair_set}, 'validation-tuned')));
pr = h(contains({h.reading}, 'PER reduction') & contains({h.reading}, 'pooled'));
verifyEqual(tc, [pr.value pr.lo pr.hi], [12.5 7.5 17.5], 'AbsTol', 1e-9);
hy = R([R.kpi] == 8 & strcmp({R.policy}, 'rule_core') & contains({R.pair_set}, 'hybrid detector'));
verifyNumElements(tc, hy, 9);
verifyTrue(tc, all(strcmp({hy.role}, 'secondary') & contains({hy.reading}, 'hybrid, secondary') & strcmp({hy.network}, 'HYB_LOOP')));
pr = hy(contains({hy.reading}, 'PER reduction') & contains({hy.reading}, 'narrowband'));
verifyEqual(tc, pr.value, 30, 'AbsTol', 1e-9);
df = R([R.kpi] == 8 & strcmp({R.versus}, 'rule_core') & strcmp({R.policy}, 'rule_core3'));
verifyNumElements(tc, df, 9);
verifyTrue(tc, all(strcmp({df.role}, 'descriptive') & strcmp({df.verdict}, 'descriptive, no verdict word')));
verifyTrue(tc, all(contains({df.pair_set}, 'only the class source differs')));
% KPI 5: rule_core3's per-type verdicts beside C2e's; pooled a second line; rule_core secondary
b5 = R([R.kpi] == 5 & contains({R.source}, 'KP.primary'));
c3 = b5(strcmp({b5.policy}, 'rule_core3'));
verifyEqual(tc, sort({c3.role}), {'beside', 'beside', 'second_line'});
w = c3(strcmp({c3.role}, 'beside'));
verifyEqual(tc, {w.verdict}, {'MET (committed)', 'NOT MET'});
verifyTrue(tc, all(strcmp({w.network}, 'CNN3_LOOP')));
hb = b5(strcmp({b5.policy}, 'rule_core'));
verifyTrue(tc, all(strcmp({hb.role}, 'secondary') & contains({hb.reading}, 'hybrid, secondary')));
verifyFalse(tc, any(strcmp({R.verdict}, 'pending (CORE_BW)')));
% the headline sorts before the secondary rows of its KPI
roles = {R([R.kpi] == 8).role};
verifyLessThan(tc, find(strcmp(roles, 'headline'), 1, 'last'), find(strcmp(roles, 'secondary'), 1, 'first'));
txt = strjoin(lines, newline);
verifyTrue(tc, contains(txt, 'rule_core3 - rule_core is descriptive'));
verifyTrue(tc, contains(txt, 'CNN3_LOOP'));
end

function test_nan_is_not_printed_as_a_number(tc)
% A NaN in a saved struct reads 'n/a' in the text and is empty in the csv (S7 pattern).
d = new_dir(tc);
write_inputs(d, true, true);
S = load(fullfile(d, 'policy_evaluation.mat'));
S.KP.lect.core.rec(1).det.median = NaN; S.KP.lect.core.rec(1).det.p90 = NaN;
S.KP.lect.core.gput(1).norm = NaN; S.KP.lect.core.gput(1).norm_jam = NaN;
S.KP.lect.core.cnn.det(1).median = NaN; S.KP.lect.core.cnn.det(1).p90 = NaN;
for j = 1:numel(S.KP.far), S.KP.far(j).rate.per_hour = NaN; end
save(fullfile(d, 'policy_evaluation.mat'), '-struct', 'S');
C = load(fullfile(d, 'core_cnn.mat'));
C.core.metrics{2}.fa_jam = NaN; C.core.boot.fa_jam(2, :) = NaN;
save(fullfile(d, 'core_cnn.mat'), '-struct', 'C');
[T, lines] = lect_kpi_table(d);
body = lines(~startsWith(lines, 'Generated:') & ~startsWith(lines, 'Saved'));
verifyFalse(tc, any(contains(body, 'NaN')), strjoin(body(contains(body, 'NaN')), newline));
verifyFalse(tc, contains(fileread(fullfile(d, 'lect_kpi_table.csv')), 'NaN'));
verifyTrue(tc, any(contains(lines, 'n/a')));
verifyNotEmpty(tc, T.rows);
end

function test_far_note_under_600(tc)
% The word follows the bound; with fewer than 600 episodes the row says the
% project's own KPI 6 (measure_all_kpis.m) does not pass on the same counts.
d = new_dir(tc);
write_inputs(d, false, false);
T = lect_kpi_table(d);
r = T.rows([T.rows.kpi] == 9 & strcmp({T.rows.policy}, 'rule_core'));
verifyNumElements(tc, r, 1); verifyFalse(tc, contains(r.note, 'fewer than 600'));
S = load(fullfile(d, 'policy_evaluation.mat'));
for j = 1:numel(S.KP.far), S.KP.far(j).n = 300; S.KP.far(j).p = S.KP.far(j).k / 300; end
save(fullfile(d, 'policy_evaluation.mat'), '-struct', 'S');
T = lect_kpi_table(d);
r = T.rows([T.rows.kpi] == 9 & strcmp({T.rows.policy}, 'rule_core'));
verifyNumElements(tc, r, 1); verifyTrue(tc, contains(r.note, 'fewer than 600'));
verifyEqual(tc, r.n, 300);
end

function test_verdict_words_are_copied(tc)
% A saved verdict word is shown as saved, even when the numbers beside it would give another one.
d = new_dir(tc);
L = write_inputs(d, false, false, @(L) tamper(L));
[T, ~] = lect_kpi_table(d);
r = T.rows([T.rows.kpi] == 5 & strcmp({T.rows.role}, 'verdict'));
verifyEqual(tc, {r.verdict}, {'SAVED WORD A', 'SAVED WORD B'});
verifyEqual(tc, [r.value], [L.core.verdict.red_pct], 'RelTol', 1e-8);
end

function test_pending_inputs_named(tc)
% Without D99, CORE_BW and the CNN's reading each pending row names its missing file.
d = new_dir(tc);
write_inputs(d, false, false);
[T, lines] = lect_kpi_table(d);
p = T.rows(T.pending);
txt = strjoin({p.verdict}, ' | ');
verifyTrue(tc, contains(txt, 'pending (CORE_BW)'));
verifyTrue(tc, contains(txt, 'lect_kpis_by_ebno.mat'));
verifyTrue(tc, contains(txt, 'core_cnn.mat: missing'));
verifyEqual(tc, sum([p.kpi] == 8 & strcmp({p.role}, 'pending')), 1);
verifyTrue(tc, any(contains(lines, 'Link-limited points (D99): pending')));
verifyTrue(tc, isfile(fullfile(d, 'lect_kpi_per.png')));
verifyFalse(tc, any(strcmp({T.rows.role}, 'headline')));
end

function test_policy_evaluation_without_lect(tc)
% A policy_evaluation.mat of an older tip (no KP.lect): KPI 5-8 pending, no figures.
d = new_dir(tc);
[~, KP] = write_inputs(d, false, false);
KP = rmfield(KP, 'lect'); POL = {'none'}; LBL = {'no response'}; iDQN = 1; %#ok<NASGU>
save(fullfile(d, 'policy_evaluation.mat'), 'KP', 'POL', 'LBL', 'iDQN');
[T, lines] = lect_kpi_table(d);
r = T.rows(ismember([T.rows.kpi], 5:8) & strcmp({T.rows.role}, 'pending'));
r = r(~strcmp({r.verdict}, 'pending (CORE_BW)'));
verifyNumElements(tc, r, 4);
verifyTrue(tc, all(contains({r.verdict}, 'has no KP.lect')));
verifyFalse(tc, isfile(fullfile(d, 'lect_kpi_per.png')));
verifyTrue(tc, any(contains(lines, 'Figures: not written')));
end

function test_core_empty(tc)
% KP.lect without the core block (rule_core and blind_core did not run): pending core rows, full rows kept.
d = new_dir(tc);
write_inputs(d, false, false, @(L) setfield(L, 'core', []));
[T, ~] = lect_kpi_table(d);
r = T.rows(strcmp({T.rows.role}, 'pending') & ismember([T.rows.kpi], 5:8));
verifyTrue(tc, any(contains({r.verdict}, 'KP.lect.core is empty')));
verifyTrue(tc, any(strcmp({T.rows.role}, 'extension')));
verifyFalse(tc, any(strcmp({T.rows.role}, 'verdict') & ismember([T.rows.kpi], 5)));
end

function test_smoke_policy_evaluation(tc)
% The smoke tree's own policy_evaluation.mat (a scratch copy) gives a table with the KP.lect verdict words.
src = fullfile(tc.TestData.smoke, 'results', 'policy_evaluation.mat');
assumeTrue(tc, isfile(src), ['smoke tree not found: ' src]);
d = new_dir(tc);
copyfile(src, d);
f = fullfile(tc.TestData.smoke, 'results', 'phy_validation.txt');
if isfile(f), copyfile(f, d); end
S = load(fullfile(d, 'policy_evaluation.mat'), 'KP');
assumeTrue(tc, isfield(S.KP, 'lect') && ~isempty(S.KP.lect), 'the smoke KP.lect is empty');
L = S.KP.lect;
[T, ~] = lect_kpi_table(d);
r = T.rows([T.rows.kpi] == 5 & strcmp({T.rows.role}, 'verdict'));
if ~isempty(L.core)
    verifyEqual(tc, {r.verdict}, {L.core.verdict.verdict});
    verifyEqual(tc, [r.value], [L.core.verdict.red_pct], 'RelTol', 1e-8);
else
    verifyEmpty(tc, r);
end
verifyTrue(tc, isfile(fullfile(d, 'lect_kpi_per.png')) && isfile(fullfile(d, 'lect_kpi_goodput.png')) ...
    && isfile(fullfile(d, 'lect_kpi_recovery.png')));
% the mat file is left as it was
a = dir(fullfile(tc.TestData.smoke, 'results', 'policy_evaluation.mat'));
verifyEqual(tc, dir(fullfile(d, 'policy_evaluation.mat')).bytes, a.bytes);
end

function test_reader_source_is_pure(tc)
% The reader writes only lect_kpi_table.* and lect_kpi_*.png in the results folder and opens no data or test-set file.
t = fileread(fullfile(tc.TestData.root, 'code', 'evaluation', 'lect_kpi_table.m'));
code = regexprep(t, '%[^\n]*', '');
verifyEmpty(tc, regexp(code, '\<save\s*\(|\<delete\s*\(|\<movefile\s*\(|\<copyfile\s*\(|\<rmdir\s*\(|\<system\s*\(|\<evalc?\s*\(', 'once'));
verifyEmpty(tc, regexp(code, 'data[/\\]|splits|_pools|detector_predictions|\<lect_kpis\s*\(', 'once'));
w = regexp(code, 'fopen\(f, ''w''\)', 'match');
verifyNumElements(tc, w, 2);                                       % write_csv and write_lines only
verifyEmpty(tc, regexp(code, '[^\x00-\x7F]', 'once'));
end

function test_omitted_goodput_counts(tc)
% R4: every normalized goodput value of Line A says how many episodes of its set the mean leaves out
% (the episodes at 0 dB, where the clean link loses more than 90% of its packets), as D99 prints it.
d = new_dir(tc);
write_inputs(d, true, true);
[T, lines] = lect_kpi_table(d);
O = T.omitted;
verifyTrue(tc, O.ok);
verifyEqual(tc, O.points, '0 dB');
verifyEqual(tc, [O.thr; O.full; O.core; O.core36], [4 24; 4 24; 4 20; 4 24]);
verifyTrue(tc, any(strcmp(lines, ['Normalized goodput (KPI 7) is not defined where the clean link loses more than 90% of its packets ' ...
    '(link_env.m; here 0 dB): Line A''s normalized means leave out (mean ''omitnan''), of the episodes of each row, threat episodes 4 of 24; ' ...
    'recoverable jamming episodes 4 of 24 on the full action set, 4 of 20 on the core action set, 4 of 24 on the core set recoverable ' ...
    'by the 36. Goodput in bit/s keeps them; Line B has none.'])));
g = T.rows([T.rows.kpi] == 7 & strcmp({T.rows.line}, 'A'));
verifyNotEmpty(tc, g);
for i = 1:numel(g)
    if contains(g(i).reading, 'threat episodes')
        want = 'leaves out 4 of 24 episodes at 0 dB';
    elseif startsWith(g(i).action_set, 'core') && ~contains(g(i).pair_set, '36-configuration mask')
        want = 'leaves out 4 of 20 episodes at 0 dB';
    else
        want = 'leaves out 4 of 24 episodes at 0 dB';
    end
    verifyTrue(tc, contains(g(i).note, ['(mean omitnan: ' want ', where the clean link loses more than 90% of its packets)']), g(i).note);
end
verifyTrue(tc, any(strcmp({g.action_set}, '36 configurations')) && any(startsWith({g.action_set}, 'core')));
verifyTrue(tc, contains(fileread(fullfile(d, 'lect_kpi_table.csv')), 'leaves out 4 of 20 episodes at 0 dB'));
body = lines(~startsWith(lines, 'Generated:') & ~startsWith(lines, 'Saved'));
verifyFalse(tc, any(contains(body, 'NaN')));
end

function test_omitted_goodput_counts_pending_and_n_a(tc)
% Without D99 the counts are pending; without the per-Eb/N0 readings or D99's printed note the counts
% they carry read n/a, never NaN.
d = new_dir(tc);
write_inputs(d, false, false);
[T, lines] = lect_kpi_table(d);
verifyFalse(tc, T.omitted.ok);
verifyTrue(tc, any(contains(lines, 'Count pending (lect_kpis_by_ebno.mat: missing)')));
g = T.rows([T.rows.kpi] == 7 & strcmp({T.rows.line}, 'A'));
verifyNotEmpty(tc, g);
verifyTrue(tc, all(contains({g.note}, 'count pending, lect_kpis_by_ebno.mat: missing')));
% D99 without the per-Eb/N0 readings: the full mask from the printed note, the core set n/a
d = new_dir(tc);
write_inputs(d, true, true);
S = load(fullfile(d, 'lect_kpis_by_ebno.mat')); S.S = rmfield(S.S, 'rows');
save(fullfile(d, 'lect_kpis_by_ebno.mat'), '-struct', 'S');
[T, lines] = lect_kpi_table(d);
verifyEqual(tc, [T.omitted.thr; T.omitted.full; T.omitted.core36], [4 24; 4 24; 4 24]);
verifyTrue(tc, all(isnan(T.omitted.core)));
verifyTrue(tc, any(contains(lines, ['4 of 24 on the full action set, n/a of n/a on the core action set, 4 of 24 on the core set ' ...
    'recoverable by the 36'])));
body = lines(~startsWith(lines, 'Generated:') & ~startsWith(lines, 'Saved'));
verifyFalse(tc, any(contains(body, 'NaN')));
% D99 without the printed note: the threat counts n/a, the recoverable jamming counts from the readings
d = new_dir(tc);
write_inputs(d, true, true);
S = load(fullfile(d, 'lect_kpis_by_ebno.mat')); S = rmfield(S, 'lines');
save(fullfile(d, 'lect_kpis_by_ebno.mat'), '-struct', 'S');
T = lect_kpi_table(d);
verifyTrue(tc, all(isnan(T.omitted.thr)));
verifyEqual(tc, [T.omitted.full; T.omitted.core], [4 24; 4 20]);
end

%% ---------- helpers ----------
function [L, KP] = write_inputs(d, with_cnn, with_d99, mod)
% Synthetic inputs in folder d: policy_evaluation.mat (lect_kpis.m on a small world), the phy report, and
% optionally the three-state CNN's reading, the D99 outputs and CORE_BW's.
if nargin < 4, mod = []; end
POL = {'none', 'rule_esc', 'blind_esc', 'rule_core', 'blind_core'};
LBL = {'no response', 'rule + escalation', 'no detector + escalation', 'core: rule + escalation', 'core: no detector + escalation'};
[ALL, scen] = world(POL);
L = lect_kpis(ALL, POL, LBL, 2, scen, 5e4, 20);
if ~isempty(mod), L = mod(L); end
far = struct('policy', {}, 'k', {}, 'n', {}, 'p', {}, 'upper', {}, 'per_cycle', {}, 'rate', {});
kk = [0 3 9 12 30];
for j = 1:numel(POL)
    far(end+1) = struct('policy', LBL{j}, 'k', kk(j), 'n', 600, 'p', kk(j) / 600, 'upper', min(1, kk(j) / 600 + 0.015), ...
        'per_cycle', 1e-4, 'rate', struct('per_hour', 18 * j)); %#ok<AGROW>
end
KP = struct('lect', L, 'far', far, 'ebno', [0 3 6 9 12 15], 'det_id', 'abc123', 'policy_stamp', 'stamp-1'); %#ok<NASGU>
iDQN = 2; %#ok<NASGU>
save(fullfile(d, 'policy_evaluation.mat'), 'KP', 'POL', 'LBL', 'iDQN');
KP = load(fullfile(d, 'policy_evaluation.mat'), 'KP').KP;
fid = fopen(fullfile(d, 'phy_validation.txt'), 'w');
fprintf(fid, '%s\n', '=== PHY VALIDATION ===', ...
    'V1 AWGN, 1 ant             BER   8.00e-02 3.82e-02', '                           err     160154    76502', ...
    '                           th.   7.86e-02 3.75e-02', ...
    '                           gap +0.03 dB (standard error 0.02 dB) -> PASS  (bit delay found: 0)', ...
    'V2 Rician, 1 ant           BER   9.31e-02 5.18e-02', '                           err     186427   103790', ...
    '                           th.   9.26e-02 5.15e-02', ...
    '                           gap +0.08 dB (standard error 0.06 dB) -> PASS  (bit delay found: 0)');
fclose(fid);
if with_cnn
    core = synthetic_core(); %#ok<NASGU>
    save(fullfile(d, 'core_cnn.mat'), 'core');
    fid = fopen(fullfile(d, 'core_cnn.txt'), 'w');
    fprintf(fid, '%s\n', '=== THREE-STATE CNN ===', '--- The lecturer''s KPIs: every Eb/N0 ---', 'core CNN line', '', ...
        '--- Confusion matrices ---', 'x');
    fclose(fid);
end
if with_d99
    M = struct('clean_fer', [0.99 0.79 0.42 0.14 0.044 0.018], 'ratio_ok', 2, 'L', [true true false false false false], ...
        'tag', {{'L', 'L', 'M', 'M', 'J', 'J'}}); %#ok<NASGU>
    keep = ALL{1}.geom <= 3;
    LB = lect_kpis(subset(ALL, keep), POL, LBL, 2, scen, 5e4, 20);
    S = struct('mark', M, 'line_b', LB, 'rows', {omit_rows(ALL)}); %#ok<NASGU>
    lines = omit_note_lines(ALL); %#ok<NASGU>
    save(fullfile(d, 'lect_kpis_by_ebno.mat'), 'M', 'S', 'lines');
    fid = fopen(fullfile(d, 'low_ebno_mark.txt'), 'w');
    fprintf(fid, '%s\n', '# Link-limited Eb/N0 points', 'pools x', 'pools_sha256 abc', 'ratio_ok 2', ...
        'ebno_db clean_fer ratio_ok_x_clean_fer link_limited tag', '0 0.99 1.98 1 L', '3 0.79 1.58 1 L', '6 0.42 0.84 0 M', ...
        '9 0.14 0.28 0 M', '12 0.044 0.088 0 J', '15 0.018 0.036 0 J');
    fclose(fid);
    write_bw(d, false);
    KP = load(fullfile(d, 'policy_evaluation.mat'), 'KP').KP;
end
end

function R = omit_rows(ALL)
% The per-Eb/N0 readings of lect_kpis_by_ebno.mat (S.rows), reduced to the recoverable episode counts of each
% mask that lect_kpi_table.m sums.
R1 = ALL{1};
R = cell(1, 6);
rc = @(n) struct('set', {'recoverable threat episodes', 'recoverable jamming episodes'}, 'n', {n, n});
for k = 1:6
    nfull = nnz(R1.s == k & R1.recoverable & R1.threat);
    ncore = nnz(R1.s == k & R1.recoverable_core & R1.threat);
    R{k} = struct('rec', rc(nfull), 'core', struct('rec', rc(ncore), 'all36', struct('rec', rc(nfull))));
end
end

function lines = omit_note_lines(ALL)
% The note lect_kpis_by_ebno.m prints beside Line A's normalized goodput (gput_note), as the file's lines hold it.
R1 = ALL{1};
mt = R1.threat; mj = R1.recoverable & R1.threat; at0 = R1.s == 1;
lines = {'=== The lecturer''s readings by Eb/N0 ===', sprintf(['  Normalized goodput is not defined where the clean link loses ' ...
    'more than 90%% of its packets (link_env.m; here 0 dB): Line A''s normalized means leave out those %d of %d threat episodes ' ...
    '(%d of %d recoverable jamming) of the static link (mean ''omitnan''); goodput in bit/s keeps them.'], nnz(mt & at0), nnz(mt), ...
    nnz(mj & at0), nnz(mj))};
end

function write_bw(d, core3)
% CORE_BW's saved reading as experiment_core_bw.m writes it: the registered fallback (rule_core carries the
% verdicts) or, with core3, D106's (rule_core3 carries them, rule_core is the hybrid's secondary row).
if ~isfolder(fullfile(d, 'core_bw')), mkdir(fullfile(d, 'core_bw')); end
pr = struct('pooled', cnn_bw(12.5), 'narrowband', cnn_bw(20), 'wideband', cnn_bw(5));
per = struct('policy', {'rule_core', 'rule_core', 'rule_core', 'blind_core'}, 'type', {'narrowband', 'wideband', 'pooled', 'narrowband'}, ...
    'n', 40, 'red', {0.5, 0.2, 0.3, 0.1}, 'lo', {0.4, 0.1, 0.2, 0.0}, 'hi', {0.6, 0.3, 0.4, 0.2}, 'per', 0.1, 'per_ref', 0.2, ...
    'verdict', {'MET (committed)', 'NOT MET', 'MET (not committed)', 'NOT MET'}, 'primary', {true, true, false, false});
P = struct('cnn', pr, 'per', per);
if core3
    p3 = per(1:3); [p3.policy] = deal('rule_core3');
    [p3.red] = deal(0.55, 0.45, 0.5); [p3.lo] = deal(0.45, 0.35, 0.4); [p3.hi] = deal(0.65, 0.55, 0.6);
    [p3.verdict] = deal('MET (committed)', 'NOT MET', 'MET (committed)'); [p3.primary] = deal(true, true, false);
    hy = per(1:3); [hy.primary] = deal(false, false, false);
    P.per = [p3, hy, per(4)];
    P.cnn_hybrid = struct('pooled', cnn_bw(8), 'narrowband', cnn_bw(30), 'wideband', cnn_bw(2));
    P.cnn_3vs = struct('pooled', cnn_bw(4), 'narrowband', cnn_bw(-3), 'wideband', cnn_bw(1));
end
KP = struct('primary', P); %#ok<NASGU>
save(fullfile(d, 'core_bw', 'core_bw_kpis.mat'), 'KP');
end

function c = cnn_bw(red)
c = struct('per', [0.01 0 0.02], 'per_red', [red / 100 (red - 5) / 100 (red + 5) / 100], 'gput', [100 50 150], 'trec', [-1 -2 0], 'n_both', 17);
end

function core = synthetic_core()
% A three-state CNN reading as train_core_cnn.m saves it (readers: hybrid slot empty, windowed, per frame).
M2 = struct('cm', [95 3 1 1; 5 90 3 2; 8 6 80 6], 'n', [100 100 100], 'recall', [0.95 0.9 0.8], 'precision', [0.9 0.9 0.9], ...
    'f1', [0.92 0.9 0.84], 'macro_f1', 0.915, 'fa', 0.04, 'fa_jam', 0.02);
M3 = M2; M3.macro_f1 = 0.88; M3.fa = 0.06;
B = struct('macro_f1', [nan nan; 0.901 0.928; 0.86 0.9], 'fa', [nan nan; 0.03 0.05; 0.05 0.07], ...
    'fa_jam', [nan nan; 0.01 0.03; 0.04 0.06]);
B.recall = cat(3, [nan nan nan; 0.93 0.88 0.76; 0.9 0.85 0.7], [nan nan nan; 0.97 0.92 0.84; 0.94 0.9 0.8]);
V = {'no hybrid reading', 'no hybrid reading', 'no hybrid reading', 'no hybrid reading'; ...
    'met (committed)', 'met (committed)', 'met (not committed)', 'met (committed)'; ...
    'not met', 'met (committed)', 'not met', 'not met'};
core = struct('test_set', 'data/splits_fresh3.mat', 'N', 5, 'states', {{'clean', 'narrowband jamming', 'wideband jamming'}}, ...
    'metrics', {{[], M2, M3}}, 'boot', B, 'verdicts', {V}, 'thr', struct('macro_f1', 0.85, 'recall', 0.85, 'false_alarm', 0.05));
end

function [ALL, scen] = world(POL)
% 24 episodes in six flight geometries, jamming, tone_jamming and noise_burst threats; per-policy PER and timing.
scen = {'none', 'jamming', 'tone_jamming', 'noise_burst'};
rs = RandStream('mt19937ar', 'Seed', 7);
n = 24;
base = struct('scn', repmat([2 3 4], 1, 8), 'recoverable', true(1, n), 'recoverable_core', [true(1, 20) false(1, 4)], ...
    'threat', true(1, n), 'geom', repelem(1:6, 4), 'ok_post', 0.5 * ones(1, n), 'gput_post', 0.5 * ones(1, n), 's', repelem(1:6, 4));
per0 = 0.5 + 0.4 * rand(rs, 1, n);
ALL = cell(1, numel(POL));
for k = 1:numel(POL)
    R = base;
    switch POL{k}
        case 'none', f = 1; dl = 0.2;
        case 'rule_esc', f = 0.3; dl = 0.7;
        case 'rule_core', f = 0.35; dl = 0.65;
        otherwise, f = 0.6; dl = 0.45;
    end
    R.per_post = min(1, per0 * f .* (0.9 + 0.2 * rand(rs, 1, n)));
    R.dlv_post = dl * (1 - R.per_post);
    R.t_conf = ceil(1 + 4 * rand(rs, 1, n)); R.t_rec_det = ceil(1 + 8 * rand(rs, 1, n)); R.t_rec = R.t_conf + R.t_rec_det;
    if strcmp(POL{k}, 'none'), R.t_conf(:) = NaN; R.t_rec_det(:) = NaN; R.t_rec(:) = NaN; end
    if startsWith(POL{k}, 'blind'), R.t_conf(1:5) = NaN; R.t_rec_det(1:5) = NaN; end
    R.t_rec_det(3) = NaN;
    ALL{k} = R;
end
end

function A = subset(ALL, keep)
A = cellfun(@(R) sub1(R, keep), ALL, 'UniformOutput', false);
end

function R = sub1(R, keep)
for f = fieldnames(R)'
    if numel(R.(f{1})) == numel(keep), R.(f{1}) = R.(f{1})(keep); end
end
end

function L = tamper(L)
L.core.verdict(1).verdict = 'SAVED WORD A';
L.core.verdict(2).verdict = 'SAVED WORD B';
end

function h = file_hashes(d)
% SHA-256 of every file in d (names and bytes of the inputs; the reader's own outputs are left out).
f = dir(d); f = f(~[f.isdir]);
f = f(~startsWith({f.name}, 'lect_kpi_'));
h = struct();
for i = 1:numel(f)
    p = fullfile(f(i).folder, f(i).name);
    fid = fopen(p, 'r'); x = fread(fid, Inf, '*uint8'); fclose(fid);
    md = java.security.MessageDigest.getInstance('SHA-256');
    md.update(typecast(x, 'int8'));
    h.(matlab.lang.makeValidName(f(i).name)) = reshape(dec2hex(typecast(md.digest(), 'uint8'))', 1, []);
end
h.core_bw_n = numel(dir(fullfile(d, 'core_bw')));
end
