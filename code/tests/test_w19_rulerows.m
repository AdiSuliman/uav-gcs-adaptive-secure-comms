function tests = test_w19_rulerows
%TEST_W19_RULEROWS  The rule rows read in the same read of the fresh set (weak19_reading.m 'test' with
%   'rulerows') and the recorded code amendment: without the option the test stage runs the base
%   commit's statements unchanged and every other function of the reader is the base's; the
%   amendment proves the frozen hash again from the base copies; the registered confirmation on
%   synthetic readings. Temporary folders only, no pools. Run from the repository root:
%   results = runtests('code/tests/test_w19_rulerows.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.base = 'c689c21';                                    % the commit this branch starts from
end

%% ---------- off: the base's statements ----------
function test_off_runs_the_base_statements(tc)
% stage_test without the option: every line that names the option is the option's parse or a
% one-line block under RR.on; the other lines are the base's, in the base's order. Every other
% function of the base is unchanged; reg, paths and the entry only gain lines; guard gains the
% amendment's alternative alone.
B0 = blocks(git_text(tc, tc.TestData.base, 'code/decision/weak19_reading.m'));
B1 = blocks(fileread(which('weak19_reading')));
s0 = B0.stage_test; s1 = B1.stage_test;
verifyEqual(tc, s1{1}, 'function stage_test(tree, tag, varargin)');
rr = s1(contains(s1, 'RR'));
verifyTrue(tc, all(~cellfun(@isempty, regexp(rr, '^(RR = rr_option\(varargin\);|if RR\.on, [^;]+; end)$', 'once'))), ...
    strjoin(rr, newline));
k1 = s1(~contains(s1, 'RR'));
verifyEqual(tc, k1(2:end), s0(2:end));
verifyFalse(tc, weak19_reading('rr_option', {}).on);
g0 = B0.guard; g1 = B1.guard;
old = "if ~strcmp(S.fingerprint.code, F.code), J{end+1} = 'the code differs from the code the selection ran'; end";
verifyEqual(tc, sum(strcmp(g0, old)), 1);
i = find(contains(g1, 'amended(X, S.fingerprint.code, F.code)'));
verifyNumElements(tc, i, 1);
verifyEqual(tc, g1{i + 1}, '    J{end+1} = ''the code differs from the code the selection ran'';');
verifyEqual(tc, g1{i + 2}, 'end');
verifyEqual(tc, g1([1:i - 1, i + 3:end]), g0(~strcmp(g0, old)));
for f = fieldnames(B0)'
    switch f{1}
        case {'stage_test', 'guard'}
        case {'reg', 'paths', 'weak19_reading'}
            verifyTrue(tc, is_subseq(B0.(f{1}), B1.(f{1})), f{1});
        otherwise
            verifyTrue(tc, isfield(B1, f{1}), f{1});
            verifyEqual(tc, B1.(f{1}), B0.(f{1}), f{1});
    end
end
end

function test_option(tc)
O = weak19_reading('rr_option', {});
verifyEqual(tc, {O.on, O.d124}, {false, ''});
O = weak19_reading('rr_option', {'rulerows', 'C:\x\test.mat'});
verifyEqual(tc, {O.on, O.d124}, {true, 'C:\x\test.mat'});
O = weak19_reading('rr_option', {"rulerows", "t.mat"}); verifyTrue(tc, O.on);
verifyError(tc, @() weak19_reading('rr_option', {'rules', 'x'}), 'weak19_reading:option');
verifyError(tc, @() weak19_reading('rr_option', {'rulerows'}), 'weak19_reading:option');
verifyError(tc, @() weak19_reading('rr_option', {'rulerows', 3}), 'weak19_reading:option');
end

function test_refusals(tc)
% The option is parsed before anything; the guard refuses before the selection; amend refuses
% without a frozen selection. Nothing is written.
tree = tempname; mkdir(tree); cl = onCleanup(@() rmdir(tree, 's')); %#ok<NASGU>
verifyError(tc, @() weak19_reading('test', tree, 'w19rr', 'other', 'x.mat'), 'weak19_reading:option');
verifyError(tc, @() weak19_reading('test', tree, 'w19rr', 'rulerows', 'x.mat'), 'weak19_reading:guard');
verifyError(tc, @() weak19_reading('amend', tree, 'w19rr', tree, 'a reason long enough to pass'), 'weak19_reading:amend');
X = weak19_reading('paths', tree, 'w19rr');
verifyFalse(tc, isfolder(X.dir), 'nothing written in the checkout');
verifyTrue(tc, startsWith(X.rr_txt, X.dir) && startsWith(X.rr_mat, X.dir) && startsWith(X.amend, X.dir));
end

function test_registered(tc)
R = weak19_reading('reg');
verifyEqual(tc, R.rr.setting, 'keep+st+rate');
verifyTrue(tc, rule_fix('parse', R.rr.setting).on);
verifyEqual(tc, R.rr.pols, {'none', 'rule_esc', 'blind_esc', 'rule_core', 'blind_core'});
verifyEqual(tc, R.rr.on, R.rr.pols(2:end));
verifyEqual(tc, R.rr.nsets, 3);
verifyEqual(tc, R.fresh_sets(1:R.rr.nsets), {'single', 'follower', 'combined'});
verifyEqual(tc, R.test_sets(1:R.rr.nsets), {'single', 'follower', 'combined'});
verifyEqual(tc, {R.rr.claims.name}, {'esc_recovered', 'core_narrowband', 'core_wideband'});
verifyEqual(tc, {R.rr.claims.row}, {'rule_esc', 'rule_core', 'rule_core'});
verifyEqual(tc, {R.rr.claims.threat}, {'', 'tone_jamming', 'jamming'});
verifyEqual(tc, R.rr.tag, 'p3');
verifyEqual(tc, numel(R.rr.d124_sha), 64);
verifyEqual(tc, R.amend_allowed, {'decision/weak19_reading.m', 'tests/test_w19_rulerows.m'});
verifyEqual(tc, R.amend_base_rev(1:7), tc.TestData.base);
% the bootstrap seeds: distinct, and none of the deployed DQN's reading (1900-1926, 1950)
sd = [R.rr.claims.seed, R.rr.seed_g + (1:4), R.rr.seed_d + [2:5, 12:15, 20]];
verifyEqual(tc, numel(unique([R.rr.claims.seed, R.rr.seed_g + (1:4)])), 7);
verifyFalse(tc, any(sd >= R.boot_seed & sd <= R.boot_seed + 26) || any(sd == R.flip_seed));
end

%% ---------- the amendment ----------
function test_code_at_is_read_once(tc)
verifyEqual(tc, weak19_reading('code_at', fullfile(tc.TestData.root, 'code')), read_once('code'));
verifyEqual(tc, weak19_reading('code_at', [fullfile(tc.TestData.root, 'code') filesep]), read_once('code'));
end

function test_amend_proof(tc)
% The changed and added files of the registered list: putting the base copies back gives the base
% hash; any other change, or a file outside the list, breaks the proof.
w = tempname; mkdir(w); cl = onCleanup(@() rmdir(w, 's')); %#ok<NASGU>
b = fullfile(w, 'base', 'code'); c = fullfile(w, 'cur', 'code'); f = fullfile(w, 'amend_base');
wr(fullfile(b, 'decision', 'a.m'), sprintf('x = 1;\n'));
wr(fullfile(b, 'decision', 'weak19_reading.m'), sprintf('old\n'));
wr(fullfile(c, 'decision', 'a.m'), sprintf('x = 1;\r\n'));             % line ends alone: no change
wr(fullfile(c, 'decision', 'weak19_reading.m'), sprintf('new\n'));
wr(fullfile(c, 'tests', 'test_w19_rulerows.m'), sprintf('t\n'));
D = weak19_reading('code_diff', c, b);
verifyEqual(tc, D.changed, {'decision/weak19_reading.m'});
verifyEqual(tc, D.added, {'tests/test_w19_rulerows.m'});
verifyEmpty(tc, D.removed);
hb = weak19_reading('code_at', b); hc = weak19_reading('code_at', c);
verifyNotEqual(tc, hb, hc);
wr(fullfile(f, 'decision', 'weak19_reading.m'), sprintf('old\r\n'));
sub = struct('drop', {D.added}, 'replace', {D.changed}, 'from', f);
verifyEqual(tc, weak19_reading('code_at', c, sub), hb);
A = struct('from', hb, 'to', hc, 'changed', {D.changed}, 'added', {D.added});
verifyTrue(tc, weak19_reading('amend_ok', A, c, f, hb, hc));
verifyTrue(tc, weak19_reading('amend_ok', jsondecode(jsonencode(A)), c, f, hb, hc));   % as read back from amend.json
verifyFalse(tc, weak19_reading('amend_ok', A, c, f, hb, repmat('0', 1, 64)));          % another pair
A2 = A; A2.changed = {'decision/a.m', 'decision/weak19_reading.m'};
verifyFalse(tc, weak19_reading('amend_ok', A2, c, f, hb, hc));                          % a file outside the list
wr(fullfile(c, 'decision', 'a.m'), sprintf('x = 2;\n'));                                 % a change the record does not name
hc2 = weak19_reading('code_at', c); A3 = A; A3.to = hc2;
verifyFalse(tc, weak19_reading('amend_ok', A3, c, f, hb, hc2));
D2 = weak19_reading('code_diff', c, b);
verifyEqual(tc, D2.changed, {'decision/a.m', 'decision/weak19_reading.m'});
delete(fullfile(c, 'decision', 'a.m'));
D3 = weak19_reading('code_diff', c, b); verifyEqual(tc, D3.removed, {'decision/a.m'});
end

%% ---------- the registered confirmation ----------
function test_ratio(tc)
P = weak19_reading('rr_ratio', [1 1 0 0], [2 2 2 2], 1:4, 2000, 1);
verifyEqual(tc, P.mean, 0.25, 'AbsTol', 1e-12); verifyEqual(tc, P.ncl, 4);
verifyEqual(tc, P.p, 1 / 16, 'AbsTol', 0.02);                     % all four draws from the two zero clusters
P = weak19_reading('rr_ratio', [1 1 NaN], [1 1 1], [7 7 8], 2000, 1);
verifyEqual(tc, [P.mean, P.ncl, P.p], [1, 1, 1]); verifyTrue(tc, isnan(P.lb));
P = weak19_reading('rr_ratio', 0.15 * ones(1, 40), ones(1, 40), 1:40, 2000, 1);
verifyEqual(tc, [P.p, P.lb], [0, 0.15], 'AbsTol', 1e-12);
P = weak19_reading('rr_ratio', [], [], [], 2000, 1); verifyEqual(tc, P.p, 1); verifyTrue(tc, isnan(P.mean));
end

function test_claims(tc)
[I, i, scn] = claims_world();
C = weak19_reading('rr_claims', I);
verifyEqual(tc, C.holm, [true true true]); verifyEqual(tc, C.confirmed, [true true true]);
verifyEqual(tc, [C.claims.n], [1200 400 400]);
verifyEqual(tc, C.claims(1).P.mean, 0.2, 'AbsTol', 1e-12);
verifyEqual(tc, [C.claims(2:3).off], [0.4 0.4], 'AbsTol', 1e-12);
verifyEqual(tc, [C.claims(2:3).on], [0.55 0.55], 'AbsTol', 1e-12);
verifyEqual(tc, C.claims(2).P.mean, 0.15, 'AbsTol', 1e-12);
verifyNotEmpty(tc, strfind(strjoin(C.lines, ' '), 'CONFIRMED'));
% no gain on rule + escalation: its claim fails, Holm still passes the two others
J = I; J.x1.rule_esc = J.x0.rule_esc;
C = weak19_reading('rr_claims', J); verifyEqual(tc, C.confirmed, [false true true]);
% the core rule adds 30 clean flights with a change: (d) fails, both core claims fall
J = I; J.SW.rule_core(2, 5:34) = 1;
C = weak19_reading('rr_claims', J); verifyEqual(tc, C.confirmed, [true false false]); verifyFalse(tc, C.guards.rule_core.d);
% the core rule's held falls 10 points: (e) fails
J = I; J.x1.rule_core.held = J.x0.rule_core.held & mod(i, 20) >= 2;
C = weak19_reading('rr_claims', J); verifyEqual(tc, C.confirmed, [true false false]); verifyFalse(tc, C.guards.rule_core.e);
% one threat loses about 30 points under rule + escalation: (b) fails
J = I; a = scn == 3; J.x1.rule_esc.recovered(a) = I.x0.rule_esc.recovered(a) & mod(i(a), 2) == 0;
J.x1.rule_esc.held = J.x1.rule_esc.recovered;
C = weak19_reading('rr_claims', J); verifyFalse(tc, C.guards.rule_esc.b); verifyEqual(tc, C.confirmed, [false true true]);
% ten flights only: no claim is read
J = I; J.x0.none.geom = repelem(1:10, 120);
C = weak19_reading('rr_claims', J); verifyEqual(tc, C.confirmed, [false false false]);
verifyNotEmpty(tc, strfind(strjoin(C.lines, ' '), 'not read'));
% a loss is never a gain
J = I; J.x1.rule_core.per_post = 0.7 * ones(1, 1200);
C = weak19_reading('rr_claims', J); verifyEqual(tc, C.holm, [true false false]);
end

%% ---------- helpers ----------
function [I, i, scn] = claims_world()
% 1200 recoverable threat episodes in 60 flights of 20 (tone_jamming, jamming, antenna_fault in
% turn); rule + escalation recovers 60% off and 80% on in every flight; the core rule's PER 0.6 off
% and 0.45 on against 1 without response; 400 clean flights, 4 with a change, off and on.
n = 1200; i = 1:n; scn = repmat(1:3, 1, n / 3);
base = struct('scn', scn, 'geom', repelem(1:60, 20), 'recoverable', true(1, n), 'recoverable_core', true(1, n), ...
    'threat', true(1, n));
mk = @(rec, per) setfield(setfield(setfield(base, 'recovered', rec), 'held', rec), 'per_post', per); %#ok<SFLD>
off = mod(i, 5) < 3; on = mod(i, 5) < 4;
x0.none = mk(false(1, n), ones(1, n)); x1.none = x0.none;
x0.rule_esc = mk(off, 0.6 * ones(1, n)); x1.rule_esc = mk(on, 0.6 * ones(1, n));
x0.blind_esc = mk(off, 0.6 * ones(1, n)); x1.blind_esc = x0.blind_esc;
x0.rule_core = mk(off, 0.6 * ones(1, n)); x1.rule_core = mk(off, 0.45 * ones(1, n));
x0.blind_core = mk(off, 0.6 * ones(1, n)); x1.blind_core = x0.blind_core;
sw = zeros(2, 400); sw(:, 1:4) = 1;
I = struct('x0', x0, 'x1', x1, 'scen', {{'tone_jamming', 'jamming', 'antenna_fault'}}, ...
    'SW', struct('rule_esc', sw, 'blind_esc', sw, 'rule_core', sw, 'blind_core', sw));
end

function B = blocks(txt)
% The functions of a file by name: from the function line to the line before the next one, without
% trailing blank and section lines.
L = splitlines(strrep(txt, char(13), ''))';
s = [find(startsWith(L, 'function ')), numel(L) + 1];
B = struct();
for k = 1:numel(s) - 1
    b = L(s(k):s(k + 1) - 1);
    while ~isempty(b) && (isempty(strtrim(b{end})) || startsWith(b{end}, '%%')), b(end) = []; end
    B.(function_name(b{1})) = b;
end
end

function n = function_name(line)
% The name on a function line: the word after 'function', past an output list and its '='.
s = strtrim(line(numel('function') + 1:end));
e = strfind(s, '='); p = strfind(s, '(');
if ~isempty(e) && (isempty(p) || e(1) < p(1)), s = strtrim(s(e(1) + 1:end)); end
n = regexp(s, '^[A-Za-z]\w*', 'match', 'once');
assert(~isempty(n), 'test_w19_rulerows:fname', 'no function name on: %s', line);
end

function ok = is_subseq(a, b)
% Every line of a appears in b, in a's order.
j = 1; ok = true;
for k = 1:numel(a)
    while j <= numel(b) && ~strcmp(a{k}, b{j}), j = j + 1; end
    if j > numel(b), ok = false; return; end
    j = j + 1;
end
end

function txt = git_text(tc, rev, rel)
f = [tempname '.txt'];
repo = tc.TestData.root;
[sg, ~] = system(sprintf('git --no-optional-locks -C "%s" rev-parse --git-dir', repo));
if sg ~= 0 && ~isempty(getenv('V7_GIT_REPO')), repo = getenv('V7_GIT_REPO'); end
[st, out] = system(sprintf('git --no-optional-locks -C "%s" show %s:%s > "%s"', repo, rev, rel, f));
assertEqual(tc, st, 0, sprintf('git show %s:%s failed: %s', rev, rel, out));
txt = fileread(f); delete(f);
end

function wr(f, s)
d = fileparts(f); if ~isfolder(d), mkdir(d); end
fid = fopen(f, 'w'); fwrite(fid, s); fclose(fid);
end
