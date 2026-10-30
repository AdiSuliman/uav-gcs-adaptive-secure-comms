function tests = test_wf_dec
%TEST_WF_DEC  Unit tests of the decision-layer additions: the drop alarm's own confirmation
%   (confirm_drop), the rule's lost-branch gate (s1_gate), the release on evidence (release_m) and the
%   per-Eb/N0 rows (ebno_rows.m): each switch off keeps the parent commit's
%   outputs bit for bit, each on does what its entry registers, on synthetic traces and frames
%   written in a temporary folder; no pools. Run from the repository root:
%   results = runtests('code/tests/test_wf_dec.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.cwd = pwd;
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp); cd(tc.TestData.tmp);
mkdir('data');
clean_ref = struct('ebno', 0:3:15, 'ber_est', [4e-2 1.2e-2 3e-3 8e-4 2e-4 5e-5], ...
    'plr_fec', [0.3 0.1 0.03 0.01 0.003 0.001]);                 % the clean-link table clean_ber_ref.m reads
save('data/policy_pools.mat', 'clean_ref');
clear('clean_ber_ref');
tc.TestData.base = 'f6f6e03';                                    % the commit this branch starts from
end

function teardownOnce(tc)
clear('clean_ber_ref');
cd(tc.TestData.cwd);
end

%% ---------- the stage switches and the smoke's forced cells ----------
function test_options_and_force(tc)
% Every step is off without profile.json or its field; CFG overrides the file; a value that is not
% true or false stops. The forced cells name a candidate of C.confirm_drop_cand or true and are the
% smoke's only.
O = wf_options([], 'none.json');
verifyFalse(tc, any([O.dconf O.s1g O.relm O.r9]));
verifyTrue(tc, isempty(O.force.dconf) && ~O.force.s1g && ~O.force.relm);
f = [tempname '.json'];
write_text(f, '{"dconf_select": true, "s1g_select": true, "relm_select": false, "r9_print": true}');
O = wf_options([], f); verifyEqual(tc, [O.dconf O.s1g O.relm O.r9], [true true false true]);
O = wf_options(struct('relm_select', true, 'dconf_select', false), f);
verifyEqual(tc, [O.dconf O.s1g O.relm O.r9], [false true true true]);
write_text(f, '{"surv_v2": true}'); O = wf_options([], f); verifyFalse(tc, any([O.dconf O.s1g O.relm O.r9]));
write_text(f, '{"s1g_select": 1}'); verifyError(tc, @() wf_options([], f), 'wf_options:value');
write_text(f, '{"dconf_force": [1, 1], "s1g_force": true}');
F = wf_force('read', [], f);
verifyEqual(tc, F.dconf, [1 1]); verifyTrue(tc, F.s1g); verifyFalse(tc, F.relm);
verifyTrue(tc, wf_force('any', F)); verifyFalse(tc, wf_force('any', wf_force('read', [], 'none.json')));
F = wf_force('read', struct('relm_force', true), f); verifyTrue(tc, F.relm);
write_text(f, '{"dconf_force": [3, 3]}'); verifyError(tc, @() wf_force('read', [], f), 'wf_force:value');
write_text(f, '{"relm_force": "yes"}'); verifyError(tc, @() wf_force('read', [], f), 'wf_force:value');
delete(f);
F = struct('dconf', [], 's1g', true, 'relm', false);
verifyError(tc, @() wf_force('smoke', F, false, 'stage'), 'wf_force:smoke');
wf_force('smoke', F, true, 'stage');
wf_force('smoke', struct('dconf', [], 's1g', false, 'relm', false), false, 'stage');
verifyError(tc, @() wf_force('mark', {'s1_gate'}, false, 'stage'), 'wf_force:smoke');
wf_force('mark', {'s1_gate'}, true, 'stage'); wf_force('mark', {}, false, 'stage');
end

%% ---------- switches off: the parent commit's outputs bit for bit ----------
function test_monitor_parity(tc)
% policy_monitor.m: without the fields, and with confirm_drop empty and s1_gate and release_m false,
% every M and memory of the base commit's monitor, cycle by cycle; no new memory field and no new M field.
[PP, X] = trace_world();
d = parent_copy(tc, 'code/decision/policy_monitor.m', tc.TestData.base);
addpath(d, '-begin'); clear policy_monitor
cl0 = onCleanup(@() fixture_off(d, 'policy_monitor')); %#ok<NASGU>
verifyEqual(tc, which('policy_monitor'), fullfile(d, 'policy_monitor.m'));
Oo = monitor_run(PP, X);
fixture_off(d, 'policy_monitor');
verifyNotEqual(tc, which('policy_monitor'), fullfile(d, 'policy_monitor.m'));
On = monitor_run(PP, X);
P2 = PP; P2.confirm_drop = []; P2.s1_gate = false; P2.release_m = false;
Of = monitor_run(P2, X);
verifyTrue(tc, isequaln(Oo, On), 'fields absent');
verifyTrue(tc, isequaln(Oo, Of), 'fields off');
verifyTrue(tc, any(cellfun(@(M) any(M.drop_alarm), Oo.M)) && any(cellfun(@(M) any(M.confirmed), Oo.M)));
for f = {'dal', 'hm', 'qt'}, verifyFalse(tc, isfield(On.mem{end}, f{1})); end
for f = {'harm', 'quiet'}, verifyFalse(tc, isfield(On.M{end}, f{1})); end
end

function test_decide_parity(tc)
% policy_decide.m: the rule, the rule with escalation, without the detector, on the core action set
% and the table, with the fields absent and with s1_gate and release_m false and confirm_drop empty,
% give the base commit's actions and info cycle by cycle.
[PP, X] = trace_world();
na = find(strcmp(PP.actions, 'no_action'));
X.cfg0 = na * ones(1, 4);
P2 = PP; P2.confirm_drop = []; P2.s1_gate = false; P2.release_m = false;
kinds = {'rule', 'rule_esc', 'blind_esc', 'rule_esc', 'table'};
opts = {struct(), struct(), struct(), struct('core', true), table_opt(PP)};
Rn = cell(1, numel(kinds)); Rf = Rn;
for k = 1:numel(kinds)
    Rn{k} = decide_run(kinds{k}, PP, X, opts{k}); Rf{k} = decide_run(kinds{k}, P2, X, opts{k});
end
d = parent_copy(tc, 'code/decision/policy_decide.m', tc.TestData.base);
addpath(d, '-begin'); clear policy_decide
cl0 = onCleanup(@() fixture_off(d, 'policy_decide')); %#ok<NASGU>
verifyEqual(tc, which('policy_decide'), fullfile(d, 'policy_decide.m'));
moved = false(1, numel(kinds));
for k = 1:numel(kinds)
    Ro = decide_run(kinds{k}, PP, X, opts{k});
    verifyTrue(tc, isequaln(Ro, Rn{k}), sprintf('%s %d, fields absent', kinds{k}, k));
    verifyTrue(tc, isequaln(Ro, Rf{k}), sprintf('%s %d, fields off', kinds{k}, k));
    moved(k) = any(Ro.a(:) ~= na);
end
verifyTrue(tc, any(moved(1:2)));                                         % the class rule answers somewhere on the trace
end

function test_rule_and_confirm_parity(tc)
% rule_based_policy.m and monitor_confirm.m: the base commit's outputs for every argument the earlier
% callers pass; an empty harm argument is none.
A = policy_actions();
cls = {'none', 'jamming', 'noise_burst', 'path_loss', 'antenna_fault', 'airframe_shadowing', 'benign_interference', ...
    'sweeping_jammer', 'unknown'};
bud = struct('drop_db', 7, 'current', 'no_action', 'current_db', 0, 'names', {{'rate_reduce', 'power_control'}}, 'gain_db', [3 6]);
new = cell(0, 2);
for c = cls, for dg = [false true], for gn = [0 9], for dr = [false true]
    [a, r] = rule_based_policy(c{1}, dg, gn, 5, 3, dr, bud, 7.5, true, {});
    new(end+1, :) = {a, r}; %#ok<AGROW>
    [a1, r1] = rule_based_policy(c{1}, dg, gn, 5, 3, dr, bud, 7.5, true, {}, []);
    verifyEqual(tc, {a1, r1}, {a, r});
    [a2, r2] = rule_based_policy(c{1}, dg, gn, 5, 3, dr, bud, 7.5, true, {}, true);
    verifyEqual(tc, {a2, r2}, {a, r});
end, end, end, end
[Tr, ~] = confirm_world();
[c4, a4] = monitor_confirm(Tr, 'class_cusum', 18, [5 5]);
[c5, a5] = monitor_confirm(Tr, 'class_cusum', 18, [5 5], [2 6]);
[c6, a6] = monitor_confirm(Tr, 'class_cusum', 18, [5 5], [2 6], []);
newm = {c4, a4, c5, a5, c6, a6};
verifyEqual(tc, {c6, a6}, {c5, a5});                                    % an empty cdr is none
d = parent_copy(tc, 'code/decision/rule_based_policy.m', tc.TestData.base);
addpath(d, '-begin'); clear rule_based_policy
cl0 = onCleanup(@() fixture_off(d, 'rule_based_policy')); %#ok<NASGU>
old = cell(0, 2);
for c = cls, for dg = [false true], for gn = [0 9], for dr = [false true]
    [a, r] = rule_based_policy(c{1}, dg, gn, 5, 3, dr, bud, 7.5, true, {});
    old(end+1, :) = {a, r}; %#ok<AGROW>
end, end, end, end
fixture_off(d, 'rule_based_policy');
verifyEqual(tc, new, old);
d = parent_copy(tc, 'code/decision/monitor_confirm.m', tc.TestData.base);
addpath(d, '-begin'); clear monitor_confirm
cl1 = onCleanup(@() fixture_off(d, 'monitor_confirm')); %#ok<NASGU>
[c4, a4] = monitor_confirm(Tr, 'class_cusum', 18, [5 5]);
[c5, a5] = monitor_confirm(Tr, 'class_cusum', 18, [5 5], [2 6]);
fixture_off(d, 'monitor_confirm');
verifyEqual(tc, newm, {c4, a4, c5, a5, c5, a5});
verifyTrue(tc, any(a4(:)));
end

function test_settings_and_stamp(tc)
% decision_settings.m carries the three settings (an empty confirm_drop clears the pools' one, a field
% absent keeps it); the stamp is the base commit's without them or with them off, and changes with each
% one set, with the smoke's forced mark too.
PP = struct('confirm_drop', [1 1], 's1_gate', false);
X = decision_settings(PP, struct('confirm_drop', [2 2], 's1_gate', true, 'release_m', true));
verifyEqual(tc, {X.confirm_drop, X.s1_gate, X.release_m}, {[2 2], true, true});
verifyEqual(tc, decision_settings(PP, struct('confirm_drop', [])).confirm_drop, []);
verifyEqual(tc, decision_settings(PP, struct('rule_slot', true)).confirm_drop, [1 1]);
verifyEqual(tc, decision_settings(PP, struct('dec', struct('s1_gate', true))).s1_gate, true);
S = struct('alarm_mode', 'class_drop', 'confirm', [3 3], 'drop_db', 4, 'maha_thr', -2, 'rule_mmse_db', 7.5, ...
    'confirm_sweep', [2 6], 'rule_nb', {{'a', 'b'}});
Q = struct('deployed', 'dqn_esc', 'alarm_mode', 'class_drop', 'confirm', [2 2], 'drop_db', 4, 'det_id', 'x', ...
    'maha_thr', -1, 'dec', S, 'rule_sel', S);
s1 = policy_stamp(Q);
d = parent_copy(tc, 'code/decision/policy_stamp.m', tc.TestData.base);
addpath(d, '-begin'); clear policy_stamp
cl0 = onCleanup(@() fixture_off(d, 'policy_stamp')); %#ok<NASGU>
s0 = policy_stamp(Q);
fixture_off(d, 'policy_stamp');
verifyEqual(tc, s1, s0);
Q2 = Q; Q2.dec.confirm_drop = []; Q2.dec.s1_gate = false; Q2.dec.release_m = false;
verifyEqual(tc, policy_stamp(Q2), s1);
st = {s1};
for v = {{'confirm_drop', [2 2]}, {'confirm_drop', [1 1]}, {'s1_gate', true}, {'release_m', true}, {'wf_forced', {'s1_gate'}}}
    Q2 = Q; Q2.dec.(v{1}{1}) = v{1}{2};
    st{end+1} = policy_stamp(Q2); %#ok<AGROW>
end
verifyEqual(tc, numel(unique(st)), numel(st));
end

%% ---------- the drop alarm's own confirmation ----------
function test_confirm_drop_crossing(tc)
% A crossing of the drop alarm confirms at k of the last n cycles: [1 1] on the cycle the alarm rises,
% [2 2] on the next, the confirmation of the monitor (5 of 5) four cycles after.
PP = mon_pp(); PP.alarm_mode = 'class_drop'; PP.drop_db = 4; PP.confirm = [5 5];
na = find(strcmp(PP.actions, 'no_action'));
T = 24; e = 12 * ones(1, T); e(13:end) = 2;
cd_ = {[], [2 2], [1 1]}; tconf = zeros(1, 3); ta = zeros(1, 3);
for c = 1:3
    P = PP; if ~isempty(cd_{c}), P.confirm_drop = cd_{c}; end
    mem = policy_monitor('init', 1, numel(P.actions)); first = NaN; alarm = NaN;
    for t = 1:T
        [mem, M] = policy_monitor('update', mem, mk_obs(P, -6, e(t), 0, na, 'none', 0), P, na);
        mem = policy_monitor('change', mem, false);
        if M.drop_alarm && isnan(alarm), alarm = t; end
        if M.confirmed && isnan(first), first = t; end
    end
    tconf(c) = first; ta(c) = alarm;
end
verifyEqual(tc, ta, ta(1) * ones(1, 3));
verifyEqual(tc, tconf, ta(1) + [4 1 0]);
P = PP; P.confirm_drop = [2 2]; P.alarm_mode = 'degraded';              % no drop alarm path under the degradation monitor
mem = policy_monitor('init', 1, numel(P.actions));
for t = 1:T
    [mem, M] = policy_monitor('update', mem, mk_obs(P, -6, e(t), 0, na, 'none', 0), P, na);
    mem = policy_monitor('change', mem, false);
end
verifyFalse(tc, M.confirmed);
end

function test_monitor_confirm_cdr(tc)
% monitor_confirm.m with cdr = [k n]: the drop alarm alone confirmed at k of the last n cycles joins the
% rest; the third output is the confirmed alarm without the drop alarm, the other paths and the sweeper's.
[Tr, ~] = confirm_world();
[c0, a0, cn0] = monitor_confirm(Tr, 'class_cusum', 18, [5 5]);
verifyTrue(tc, any(a0(1, :)) && ~any(a0(2, :)));
[c1, a1, cn1] = monitor_confirm(Tr, 'class_cusum', 18, [5 5], [], [1 1]);
[c2, a2, cn2] = monitor_confirm(Tr, 'class_cusum', 18, [5 5], [], [2 2]);
verifyEqual(tc, a1, a0); verifyEqual(tc, a2, a0);
verifyEqual(tc, c1, c0 | a0);
verifyEqual(tc, c2, c0 | (a0 & [false(2, 1), a0(:, 1:end-1)]));
oth = movsum(double(Tr.other), [4 0], 2) >= 5;
verifyEqual(tc, cn0, oth); verifyEqual(tc, cn1, oth); verifyEqual(tc, cn2, oth);
[~, ~, cs] = monitor_confirm(Tr, 'class_cusum', 18, [5 5], [2 6], [1 1]);
verifyEqual(tc, cs, oth | movsum(double(Tr.sw), [5 0], 2) >= 2);
verifyTrue(tc, any(cs(:) & ~oth(:)));
end

function test_dconf_adopts_first_admissible(tc)
% No harm anywhere and path_loss confirmed three cycles sooner: [2 2], the first candidate, is adopted
% at the most sensitive threshold of the extended grid; the monitor without it is the reference.
W = dconf_world(60, 60, 0, 0, 0);
[D, lines] = dconf_run(W, []);
C = decision_config();
verifyEqual(tc, D(1).cand, [2 2]);
verifyEqual(tc, D(1).pick, W.GF(1));
verifyEqual(tc, D(1).grid, [W.GF, W.GF(end) * C.confirm_drop_ext]);
verifyEmpty(tc, D(1).forced); verifyEmpty(tc, D(1).rule_pick);
verifyEqual(tc, D(1).ref.k, 0);
verifyTrue(tc, D(1).cands(1).ok && D(1).cands(1).ub < 0);
verifyEqual(tc, [D(1).cands(1).lat.median(1), D(1).ref.lat.median(1)], [1 4]);
verifyNotEmpty(tc, strfind(strjoin(lines, '|'), 'adopted [2 2]'));
verifyEqual(tc, numel(D(1).cands), 1);
end

function test_dconf_threshold_holds_count(tc)
% The threshold of a candidate is the most sensitive one of the extended grid whose one-sided 95%
% Clopper-Pearson bound of the fit half's clean episodes with a confirmed alarm is at most 5%: the
% fit half's dips raise it above the grid's first value, and the count it holds is the bound's.
W = dconf_world(60, 60, 8, 0, 0);
[D, ~] = dconf_run(W, []);
C = decision_config(); GX = [W.GF, W.GF(end) * C.confirm_drop_ext];
Tf = sub_tr(W.Tc, W.fit);
for i = 1:numel(D(1).cands)
    cdr = D(1).cands(i).cd;
    kf = arrayfun(@(t) sum(any(monitor_confirm(Tf, 'class_cusum', t, [5 5], [], cdr), 2)), GX);
    j = find(arrayfun(@(k) cp_up(k, 60), kf) <= 0.05, 1);
    verifyEqual(tc, D(1).cands(i).pick, GX(j), sprintf('candidate %d', i));
    verifyGreaterThan(tc, j, 1);                                       % the dips raised it
    verifyLessThanOrEqual(tc, cp_up(kf(j), 60), 0.05);
    verifyGreaterThan(tc, cp_up(kf(j - 1), 60), 0.05);                 % the next more sensitive one did not hold it
end
end

function test_dconf_rejects_harm(tc)
% Clean episodes of the check half that only the new confirmation confirms (a two-cycle dip of the
% estimate) reject both candidates: the clean count and the drop-alarm count grow; nothing is adopted and
% the monitor keeps its threshold and its grid.
W = dconf_world(60, 60, 0, 5, 0);
[D, lines] = dconf_run(W, []);
verifyEmpty(tc, D(1).cand);
verifyEqual(tc, D(1).pick, W.MONP.pick); verifyEqual(tc, D(1).grid, W.GF);
verifyEqual(tc, numel(D(1).cands), 2);
for i = 1:2
    verifyFalse(tc, D(1).cands(i).ok);
    verifyTrue(tc, any(contains(D(1).cands(i).fail, '(c)')) && any(contains(D(1).cands(i).fail, '(c''')));
    verifyGreaterThan(tc, D(1).cands(i).k, D(1).ref.k);
end
verifyNotEmpty(tc, strfind(strjoin(lines, '|'), 'not adopted'));
end

function test_dconf_rejects_slower_jamming(tc)
% A candidate that delays jamming's confirmation fails (a): the fit half's dips raise its threshold, and a
% jamming seen only by the drop alarm, as a 5 dB step, takes longer to cross it than the monitor in force.
W = dconf_world(60, 60, 8, 0, 1);
[D, ~] = dconf_run(W, []);
verifyEmpty(tc, D(1).cand);
verifyEqual(tc, numel(D(1).cands), 2);
for i = 1:2
    verifyGreaterThan(tc, D(1).cands(i).pick, W.GF(1));
    verifyTrue(tc, any(contains(D(1).cands(i).fail, '(a) jamming')), sprintf('candidate %d', i));
    verifyGreaterThan(tc, D(1).cands(i).lat.median(2), D(1).ref.lat.median(2));
end
verifyEqual(tc, D(1).grid, W.GF);
end

function test_dconf_no_admissible_threshold(tc)
% A fit half whose clean episodes alarm at every threshold of the grid holds no bound: no threshold,
% the candidate is not admissible.
W = dconf_world(60, 60, 0, 0, 0);
Tc = W.Tc; i = find(W.fit); i = i(1:30);
Tc.eg(i, 10:end) = Tc.eg(i, 10:end) - 12;                              % a lasting drop
W.Tc = Tc;
[D, ~] = dconf_run(W, []);
verifyEmpty(tc, D(1).cand);
verifyTrue(tc, isnan(D(1).cands(1).pick) && ~D(1).cands(1).ok);
verifyNotEmpty(tc, strfind(D(1).cands(1).fail{1}, 'no threshold'));
end

function test_dconf_forced(tc)
% The smoke's forced candidate is deployed whatever the rule says, at its own threshold, else the grid's
% top; the mark and the rule's pick are kept.
W = dconf_world(60, 60, 0, 0, 0);
[D, lines] = dconf_run(W, [1 1]);                                       % the rule adopts [2 2]
verifyEqual(tc, D(1).cand, [1 1]); verifyEqual(tc, D(1).forced, [1 1]); verifyEqual(tc, D(1).rule_pick, [2 2]);
verifyEqual(tc, D(1).pick, D(1).cands(2).pick); verifyEqual(tc, numel(D(1).cands), 2);
verifyNotEmpty(tc, strfind(strjoin(lines, '|'), 'FORCED for class_drop 5/5'));
verifyEqual(tc, find(D(1).grid == D(1).pick, 1), D(1).j);
W = dconf_world(60, 60, 0, 5, 0);
[D, ~] = dconf_run(W, [2 2]);                                           % the rule adopts none
verifyEqual(tc, D(1).cand, [2 2]); verifyEmpty(tc, D(1).rule_pick); verifyEqual(tc, D(1).forced, [2 2]);
W = dconf_world(60, 60, 0, 0, 0);
Tc = W.Tc; i = find(W.fit); i = i(1:30); Tc.eg(i, 10:end) = Tc.eg(i, 10:end) - 12; W.Tc = Tc;
[D, ~] = dconf_run(W, [1 1]);                                           % no threshold holds the bound
C = decision_config();
verifyEqual(tc, D(1).pick, W.GF(end) * C.confirm_drop_ext(end));
verifyEqual(tc, D(1).grid(end), D(1).pick);
end

function test_drops_of(tc)
% C2's drop thresholds of a monitor: the pick and one grid step each way; around an adopted
% confirmation's threshold on its own extended grid, on THC for a monitor without one.
C = decision_config(); D1 = C.sev.path_loss.levels(1);
THC = D1^2 / 2 * (1:0.5:10); GX = [THC, THC(end) * C.confirm_drop_ext];
MP = struct('monitor', {'class_drop 2/2', 'class_drop 5/5'}, 'pick', {THC(4), THC(10)});
verifyEqual(tc, drops_of('class_drop 2/2', MP, 'class_cusum', 36, THC, [-2 0 2], 0), THC([5 4 3]));
verifyEqual(tc, drops_of('class_drop 5/5', MP, 'class_cusum', 36, THC, [-2 0 2], 0), THC([11 10 9]));
MP(1).pick = GX(20); MP(1).grid = GX; MP(2).grid = [];
verifyEqual(tc, drops_of('class_drop 2/2', MP, 'class_cusum', 36, THC, [-2 0 2], 0), GX([21 20 19]));
verifyEqual(tc, GX(20), THC(end) * 1.25);
verifyEqual(tc, drops_of('class_drop 5/5', MP, 'class_cusum', 36, THC, [-2 0 2], 0), THC([11 10 9]));
MP(1).pick = GX(end);
verifyEqual(tc, drops_of('class_drop 2/2', MP, 'class_cusum', 36, THC, [-2 0 2], 0), GX([22 21]));
verifyEqual(tc, drops_of('class_drop 2/2', MP, 'class_cusum', 36, THC, [0 2], 0), GX([22 21]));
verifyEqual(tc, drops_of('none', [], 'class_cusum', THC(3), THC, [-2 0 2], 0), THC([4 3 2]));
MP = struct('monitor', {'m'}, 'pick', {5});
verifyEqual(tc, drops_of('m', MP, 'class_drop', 4, THC, [-2 0 2], 1), [7 5 3]);
verifyEqual(tc, drops_of('m', MP, 'class_drop', 4, THC, [-2 0 2], 4), [7 5]);
verifyTrue(tc, isnan(drops_of('m', [], 'class_drop', [], THC, [-2 0 2], 0)));
end

function test_dconf_wiring(tc)
% The stages carry the choice: C1d saves it per monitor beside the extended grid and the forced mark and
% keeps its file as it was without the switch; C2 builds every run of a monitor with its confirmation, the
% deployed settings and the rule fallback hold it, and a forced file is the smoke's only.
src = fileread(which('choose_drop_threshold'));
verifyNotEmpty(tc, strfind(src, ['SV = {''drop_db'', ''drop_db_train'', ''drop_from'', ''separable'', ''THR'', ''kept'', ' ...
    '''leak'', ''leak_all'', ...']));
verifyNotEmpty(tc, strfind(src, ['''p95_mis'', ''p99_cl'', ''p05_pl'', ''floor_db'', ''drop_alarm'', ''cusum_db'', ''THC'', ' ...
    '''VAL'', ''CF'', ''EBNO_THR'', ''MONP'', ''confirm_sweep''};']));
verifyNotEmpty(tc, strfind(src, 'if DCx && strcmp(drop_alarm, ''class_cusum'')'));
verifyNotEmpty(tc, strfind(src, 'MONP(m).confirm_drop = DCONF(m).cand; MONP(m).grid = DCONF(m).grid;'));
verifyNotEmpty(tc, strfind(src, 'if ~isempty(DCONF(m).cand), MONP(m).pick = DCONF(m).pick; MONP(m).j = DCONF(m).j; end'));
verifyNotEmpty(tc, strfind(src, 'if ~isempty(ia), THC = DCONF(ia).grid; end'));
verifyNotEmpty(tc, strfind(src, 'if exist(''DCONF'', ''var''), SV = [SV, {''DCONF''}]; end'));
verifyNumElements(tc, strfind(src, 'dconf_step('), 1);
verifyNotEmpty(tc, strfind(src, 'wf_force(''smoke'', WFo.force'));
src = fileread(which('train_dqn'));
verifyNotEmpty(tc, strfind(src, 'PP.dconf = struct(''monitor'', {Dd.MONP.monitor}, ''cd'', {Dd.MONP.confirm_drop});'));
verifyNotEmpty(tc, strfind(src, 'if isfield(Dd, ''MONP'') && isfield(Dd.MONP, ''confirm_drop'')'));
verifyNotEmpty(tc, strfind(src, 'if isfield(PP, ''dconf''), PPc.confirm_drop = confirm_drop_of(PP, en.alarm); end'));
verifyNotEmpty(tc, strfind(src, 'if isfield(PP, ''dconf''), dec.confirm_drop = confirm_drop_of(PP, alarm_sel); end'));
verifyNotEmpty(tc, strfind(src, 'if isfield(PP, ''dconf''), rule_sel.confirm_drop = confirm_drop_of(PP, base(ir).alarm); end'));
verifyNotEmpty(tc, strfind(src, 'wf_force(''mark'', {''confirm_drop''}'));
verifyEmpty(tc, regexp(src, 'function d = drops_of', 'once'));             % its own file now
verifyNotEmpty(tc, strfind(confirm_drop_of_text(src), 'PP.dconf.monitor'));
end

%% ---------- the rule's lost-branch gate ----------
function test_harm_evidence(tc)
% M.harm: degradation, degradation without RF evidence or the drop alarm in at least one of the last n
% cycles of the confirmation; none of them: no harm; the evidence ends n cycles after it.
PP = mon_pp(); PP.s1_gate = true; PP.confirm = [3 3];
na = find(strcmp(PP.actions, 'no_action'));
lb = [-1 -6 -6 -6 -6 -6 -6 -6 -6 -6]; H = false(1, 10); D = H;
mem = policy_monitor('init', 1, numel(PP.actions));
for t = 1:10
    [mem, M] = policy_monitor('update', mem, mk_obs(PP, lb(t), 12, 0, na, 'none', 0), PP, na);
    mem = policy_monitor('change', mem, false); H(t) = M.harm; D(t) = M.degraded;
end
verifyEqual(tc, D, [true(1, 5), false(1, 5)]);                          % one bad frame stays in the BER window five cycles
verifyEqual(tc, H, [true(1, 7), false(1, 3)]);                          % and in the harm evidence three cycles more
P2 = PP; P2.deg_mode = 'win_q_gate'; P2.ber_q = struct('lo', 0, 'q', 1e-3);
mem = policy_monitor('init', 1, numel(PP.actions));
for t = 1:5
    [mem, M] = policy_monitor('update', mem, mk_obs(P2, -1, 6, 0, na, 'none', 0), P2, na);
    mem = policy_monitor('change', mem, false);
end
verifyEqual(tc, [M.degraded, M.deg_quiet, M.harm], [false true true]);   % degraded without RF evidence is harm evidence
P3 = PP; P3.alarm_mode = 'class_drop'; P3.drop_db = 4; P3.confirm = [5 5];
e = 12 * ones(1, 18); e(13:end) = 2; H = false(1, 18); A = H;
mem = policy_monitor('init', 1, numel(PP.actions));
for t = 1:18
    [mem, M] = policy_monitor('update', mem, mk_obs(P3, -6, e(t), 0, na, 'none', 0), P3, na);
    mem = policy_monitor('change', mem, false); H(t) = M.harm; A(t) = M.drop_alarm;
end
verifyEqual(tc, H, A); verifyTrue(tc, any(A) && ~A(1));                 % the drop alarm alone, confirmation of 5: kept while on
P4 = PP; P4.s1_gate = false;
mem = policy_monitor('init', 1, numel(PP.actions));
[~, M] = policy_monitor('update', mem, mk_obs(P4, -1, 12, 0, na, 'none', 0), P4, na);
verifyFalse(tc, isfield(M, 'harm'));
end

function test_s1g_gates_answer_and_escalation(tc)
% A confirmed lost-branch class without harm evidence is answered with no_action and is not stuck: the
% rule and the rule with escalation hold no_action for the whole episode; with harm evidence in the last n
% cycles, or with the gate off, the class answer follows; the other classes are answered as before.
PP = mon_pp(); PP.confirm = [2 2];
A = PP.actions; na = find(strcmp(A, 'no_action')); pc = find(strcmp(A, 'power_control'));
cs = find(strcmp(A, 'channel_switch'));
T = 15; P1 = PP; P1.s1_gate = true;
for cls = {'antenna_fault', 'airframe_shadowing'}
    X = const_trace(PP, T, -6, 12, 0, cls{1}, 0, na);
    for kind = {'rule', 'rule_esc'}
        Roff = decide_run(kind{1}, PP, X); Rgate = decide_run(kind{1}, P1, X);
        verifyEqual(tc, Roff.a(2), pc, sprintf('%s %s off', kind{1}, cls{1}));
        verifyTrue(tc, all(Rgate.a == na), sprintf('%s %s gated', kind{1}, cls{1}));
        verifyTrue(tc, all(cellfun(@(I) all(~I.escalated), Rgate.I)), sprintf('%s %s no escalation', kind{1}, cls{1}));
        verifyTrue(tc, all(cellfun(@(I) strcmp(I.cls{1}, cls{1}), Rgate.I)));
        verifyTrue(tc, Rgate.I{3}.confirmed && Rgate.I{3}.degraded == false);
    end
    Xh = const_trace(PP, T, -1, 12, 0, cls{1}, 0, na);                  % degraded: harm
    Rh = decide_run('rule_esc', P1, Xh);
    verifyEqual(tc, Rh.a(2), pc, sprintf('%s harm', cls{1}));
end
Xo = const_trace(PP, T, -6, 12, 0, 'antenna_fault', 0, na);             % escalation, gate off: the ladder follows
Rup = decide_run('rule_esc', PP, Xo);
verifyTrue(tc, any(cellfun(@(I) any(I.escalated), Rup.I)) || any(Rup.a ~= na));
Xj = const_trace(PP, T, -6, 12, 0, 'jamming', 0, na);                   % not a lost-branch class
verifyEqual(tc, decide_run('rule_esc', P1, Xj).a, decide_run('rule_esc', PP, Xj).a);
verifyEqual(tc, decide_run('rule_esc', P1, Xj).a(2), cs);
end

function test_s1g_scope(tc)
% The gate is the rule's and the rule with escalation's, without the core option: the DQN kinds, the
% table, the core rule (with its escalation) and the rule without the detector are bit-identical with it on.
PP = mon_pp(); PP.confirm = [2 2];
A = PP.actions; na = find(strcmp(A, 'no_action'));
P1 = PP; P1.s1_gate = true;
ag = dqn_stub(PP, find(strcmp(A, 'rate_reduce')));
tab = table_opt(PP);
cases = {'dqn', ag, struct(); 'dqn_esc', ag, struct(); 'table', [], tab; 'rule_esc', [], struct('core', true); ...
    'rule', [], struct('core', true); 'blind_esc', [], struct()};
for cls = {'antenna_fault', 'airframe_shadowing'}
    X = const_trace(PP, 14, -6, 12, 0, cls{1}, 0, na);
    for k = 1:size(cases, 1)
        R0 = decide_run(cases{k, 1}, PP, X, cases{k, 3}, cases{k, 2});
        R1 = decide_run(cases{k, 1}, P1, X, cases{k, 3}, cases{k, 2});
        verifyTrue(tc, isequaln(R0, R1), sprintf('%s %s', cases{k, 1}, cls{1}));
    end
end
end

function test_s1g_static(tc)
% rule_core_policy.m is the base commit's byte for byte; the gate and the release read monitor fields and
% settings only, never a truth field (healthy, harmed, sc_eff, ended); the harm field has one writer.
d = parent_copy(tc, 'code/decision/rule_core_policy.m', tc.TestData.base);
a = strrep(fileread(fullfile(d, 'rule_core_policy.m')), char(13), '');
b = strrep(fileread(which('rule_core_policy')), char(13), '');
rmdir(d, 's');
verifyEqual(tc, b, a);
bad = '\<(healthy|harmed|sc_eff|ended|truth|oracle)\>';
files = {'policy_monitor', 'policy_decide', 'rule_based_policy'};
key = 's1_gate|release_m|M\.harm|M\.quiet|quiet_cycle|release_on_evidence|hist_bits|confirm_drop|lbn|\<harm\>|\<relm\>';
for f = files
    L = strsplit(strrep(fileread(which(f{1})), char(13), ''), char(10));
    hit = L(~cellfun(@isempty, regexp(L, key, 'once')));
    verifyNotEmpty(tc, hit, f{1});
    verifyTrue(tc, all(cellfun(@isempty, regexp(hit, bad, 'once'))), f{1});
end
src = strrep(fileread(which('policy_monitor')), char(13), '');
for fn = {'hist_bits', 'quiet_cycle'}
    body = regexp(src, ['function [^\n]*' fn{1} '\(.*?(?=\nfunction |$)'], 'match', 'once');
    verifyNotEmpty(tc, body, fn{1});
    verifyEmpty(tc, regexp(body, bad, 'once'), fn{1});
end
src = strrep(fileread(which('policy_decide')), char(13), '');
body = regexp(src, 'function [^\n]*release_on_evidence\(.*?(?=\nfunction |$)', 'match', 'once');
verifyNotEmpty(tc, body); verifyEmpty(tc, regexp(body, bad, 'once'));
src = strrep(fileread(which('policy_monitor')), char(13), '');
verifyEmpty(tc, regexp(src, 'mem\.(hm|dal|qt)\s*=', 'once'));              % only hist_bits writes them, by name
verifyNumElements(tc, regexp(src, 'mem\.\(name\)\s*=', 'match'), 2);       % created, then shifted
verifyNumElements(tc, strfind(src, 'hist_bits(mem, ''hm'''), 1);
verifyNumElements(tc, strfind(src, 'hist_bits(mem, ''dal'''), 1);
verifyNumElements(tc, strfind(src, 'hist_bits(mem, ''qt'''), 1);
src = strrep(fileread(which('policy_decide')), char(13), '');
verifyNotEmpty(tc, strfind(src, 's1g = ~core && ~blind && strcmp(base, ''rule'')'));
verifyNotEmpty(tc, strfind(src, '&& ~lbn'));
src = fileread(which('evaluate_policies'));                                % the reference rows beside the DQN
verifyNotEmpty(tc, strfind(src, 'POL = [POL, {''rule_esc_nos1g''}]; LBL = [LBL, {''rule + escalation, without the lost-branch gate (the reference)''}];'));
verifyNotEmpty(tc, strfind(src, 'if s1_on, KP.s1g_lines = s1gl; end'));
verifyNotEmpty(tc, strfind(fileread(which('measure_all_kpis')), 'det = [det, P.KP.s1g_lines];'));
src = fileread(which('train_dqn'));                                        % chosen first, kept for every later step
verifyNotEmpty(tc, strfind(src, '[Sg, GROWS] = s1g_step(S0, S1STEP, evr, FA_BOUND, PK, PPr, K, val_spec, val_thr, H, CV, EBNO_THR);'));
verifyNotEmpty(tc, strfind(src, '[Ssel, SROWS] = choose_settings(Sg, STEPS, evr, FA_BOUND, PK);'));
verifyNotEmpty(tc, strfind(src, 'A = s1g_adopt(V0, V1, thr, s, sw0, sw1);'));
end

function test_s1g_adopt(tc)
% S1G stays on after the selection rule picked it only if every other threat's recovered moves by at
% least -1.0 point (lower bound -2.0) and the clean validation flights with a change fall (exact McNemar,
% p < 0.05); the lost-branch classes and their combinations are reported, never a condition.
[V0, V1, thr, s] = s1g_world();
sw0 = zeros(1, 1800); sw0(1:60) = 1; sw1 = sw0; sw1(1:40) = 0;
A = s1g_adopt(V0, V1, thr, s, sw0, sw1);
verifyTrue(tc, A.keep && A.g1 && A.g2);
verifyEqual(tc, A.p, 0.5^40, 'RelTol', 1e-9);
verifyEqual(tc, numel(A.lost), 3);                                          % antenna_fault, airframe_shadowing, a combination
verifyTrue(tc, any(contains(A.rows, 'jamming')) && ~any(contains(A.rows, 'antenna_fault')));
B1 = V1; B1.recovered(1:4) = false;                                         % jamming loses 10 points
A = s1g_adopt(V0, B1, thr, s, sw0, sw1);
verifyFalse(tc, A.g1); verifyFalse(tc, A.keep); verifyTrue(tc, A.g2);
lost = contains(thr, 'antenna_fault') | contains(thr, 'airframe_shadowing');
V2 = V1; V2.recovered(lost) = false;                                        % the lost-branch classes are not a condition
A = s1g_adopt(V0, V2, thr, s, sw0, sw1);
verifyTrue(tc, A.keep);
A = s1g_adopt(V0, V1, thr, s, sw0, sw0);                                    % nothing falls
verifyFalse(tc, A.g2); verifyEqual(tc, A.p, 1); verifyFalse(tc, A.keep);
sw1 = sw0; sw1(1:3) = 0;                                                    % three fall, none rises: p = 0.125
A = s1g_adopt(V0, V1, thr, s, sw0, sw1);
verifyEqual(tc, A.p, 0.125, 'AbsTol', 1e-12); verifyFalse(tc, A.keep);
sw1 = sw0; sw1(1:10) = 0; sw1(1801-5:1800) = 1;                              % ten fall, five rise
A = s1g_adopt(V0, V1, thr, s, sw0, sw1);
verifyFalse(tc, A.keep);
A = s1g_adopt(V0, V1, thr, s, [], []);
verifyFalse(tc, A.keep); verifyTrue(tc, any(contains(A.rows, 'not measured')));
end

function test_paired_stats(tc)
% The exact McNemar test, the Garwood bound and the cluster bootstrap on values known by hand.
verifyEqual(tc, paired_stats('mcnemar', 10, 0), 0.5^10, 'RelTol', 1e-12);
verifyEqual(tc, paired_stats('mcnemar', 3, 3), 42 / 64, 'AbsTol', 1e-12);
verifyEqual(tc, paired_stats('mcnemar', 0, 5), 1);
verifyEqual(tc, paired_stats('mcnemar', 0, 0), 1);
verifyEqual(tc, paired_stats('garwood', 0, 1), -log(0.05), 'AbsTol', 1e-12);
for k = [0 3 10]
    u = paired_stats('garwood', k, 1);                                      % P(X <= k | rate u) = 5%
    verifyEqual(tc, sum(exp(-u) * u .^ (0:k) ./ factorial(0:k)), 0.05, 'AbsTol', 1e-9);
end
verifyEqual(tc, paired_stats('garwood', 10, 200), paired_stats('garwood', 10, 1) / 200, 'RelTol', 1e-12);
x = [1 1 1 1 0 0 0 0]; cl = [1 1 2 2 3 3 4 4];
[m, lb, ub] = paired_stats('boot', x, cl, 2000, 5);
verifyEqual(tc, m, 0.5); verifyTrue(tc, lb <= m && m <= ub && lb < ub);
[m2, lb2, ub2] = paired_stats('boot', x, cl, 2000, 5);
verifyEqual(tc, [m lb ub], [m2 lb2 ub2]);                                   % a fixed seed
[m, lb, ub] = paired_stats('boot', 3 * ones(1, 6), [1 1 2 2 3 3], 500, 1);
verifyEqual(tc, [m lb ub], [3 3 3]);
[m, lb, ub] = paired_stats('boot', [1 2 3], [1 1 1], 500, 1);
verifyEqual(tc, m, 2); verifyTrue(tc, isnan(lb) && isnan(ub));             % one cluster: no interval
[m, lb] = paired_stats('boot', [1 NaN 3 5], [1 2 3 4], 500, 1);
verifyEqual(tc, m, 3); verifyFalse(tc, isnan(lb));                          % non-finite values dropped
verifyError(tc, @() paired_stats('nope'), 'paired_stats:cmd');
end

%% ---------- the release on evidence ----------
function test_quiet_cycle(tc)
% M.quiet: no alarm, no degradation (with or without RF evidence), no drop alarm, the quiet slot under
% PP.q_thr (else C.q_alarm_db) and no busy bin in the idle gap; a cycle without an idle record is not quiet.
PP = mon_pp(); PP.release_m = true;
na = find(strcmp(PP.actions, 'no_action'));
base = {-6, 12, 0, 'none', 0};
cases = {base, true; {-6, 12, 5, 'none', 0}, false; {-6, 12, 0, 'none', 0.1}, false; {-6, 12, 0, 'none', NaN}, false; ...
    {-1, 12, 0, 'none', 0}, false; {-6, 12, 0, 'jamming', 0}, false};
for k = 1:size(cases, 1)
    c = cases{k, 1};
    mem = policy_monitor('init', 1, numel(PP.actions));
    for t = 1:6
        [mem, M] = policy_monitor('update', mem, mk_obs(PP, c{1}, c{2}, c{3}, na, c{4}, c{5}), PP, na);
        mem = policy_monitor('change', mem, false);
    end
    verifyEqual(tc, M.quiet, cases{k, 2}, sprintf('case %d', k));
    verifyEqual(tc, size(mem.qt), [1 8]); verifyEqual(tc, mem.qt(end), cases{k, 2});
end
P2 = PP; P2.q_thr = 8;                                                      % the deployed quiet-slot threshold
mem = policy_monitor('init', 1, numel(PP.actions));
[~, M] = policy_monitor('update', mem, mk_obs(P2, -6, 12, 5, na, 'none', 0), P2, na);
verifyTrue(tc, M.quiet);
P3 = PP; P3.deg_mode = 'win_q_gate'; P3.ber_q = struct('lo', 0, 'q', 1e-3);   % degraded without RF evidence is not quiet
mem = policy_monitor('init', 1, numel(PP.actions));
for t = 1:5, [mem, M] = policy_monitor('update', mem, mk_obs(P3, -1, 6, 0, na, 'none', 0), P3, na); mem = policy_monitor('change', mem, false); end
verifyEqual(tc, [M.alarm, M.degraded, M.deg_quiet, M.quiet], [false false true false]);
P4 = PP; P4.alarm_mode = 'class_drop'; P4.drop_db = 4; P4.confirm = [5 5];
e = 12 * ones(1, 12); e(7:end) = 2; q = false(1, 12);
mem = policy_monitor('init', 1, numel(PP.actions));
for t = 1:12
    [mem, M] = policy_monitor('update', mem, mk_obs(P4, -6, e(t), 0, na, 'none', 0), P4, na);
    mem = policy_monitor('change', mem, false); q(t) = M.quiet;
end
verifyTrue(tc, all(q(1:6)) && ~q(end) && any(~q));                          % the drop alarm is not quiet
P5 = PP; P5.release_m = false;
[~, M] = policy_monitor('update', policy_monitor('init', 1, numel(PP.actions)), mk_obs(P5, -6, 12, 0, na, 'none', 0), P5, na);
verifyFalse(tc, isfield(M, 'quiet'));
end

function test_relm_releases_after_quiet_window(tc)
% From a configuration that keeps our channel in view the release comes on the cycle the last
% max(n, C.confirm_sweep(2)) cycles were all quiet, n the confirmation's length; the rule and the table never
% release by themselves; the DQN stub holds.
A = policy_actions(); na = find(strcmp(A, 'no_action'));
pcfg = find(strcmp(A, 'power_control')); sdi = find(strcmp(A, 'spatial_diversity'));
ag = []; opt = struct(); T = 14;
for cf = {[2 2], [8 8]}
    L = max(cf{1}(2), decision_config().confirm_sweep(2));
    for cfg0 = [pcfg sdi]
        for kind = {'rule', 'rule_esc', 'table', 'dqn', 'dqn_esc'}
            PP = mon_pp(); PP.confirm = cf{1};
            X = const_trace(PP, T, -6, 12, 0, 'none', 0, cfg0);
            if startsWith(kind{1}, 'dqn'), ag = dqn_stub(PP, cfg0); else, ag = []; end
            if strcmp(kind{1}, 'table'), opt = table_opt(PP); else, opt = struct(); end
            R0 = decide_run(kind{1}, PP, X, opt, ag);
            verifyTrue(tc, all(R0.a == cfg0), sprintf('%s: it holds without the layer', kind{1}));
            PP.release_m = true;
            R1 = decide_run(kind{1}, PP, X, opt, ag);
            verifyEqual(tc, R1.a, [cfg0 * ones(1, L - 1), na * ones(1, T - L + 1)], sprintf('%s %d, L %d', kind{1}, cfg0, L));
            rel = cellfun(@(I) I.relm, R1.I);
            verifyEqual(tc, rel, [false(1, L - 1), true, false(1, T - L)], sprintf('%s info', kind{1}));
            verifyFalse(tc, isfield(R0.I{1}, 'relm'));
        end
    end
end
end

function test_relm_holds_channel_moving_configurations(tc)
% No release from a configuration with a channel_switch or freq_diversity element, whatever else it holds.
A = policy_actions(); T = 16;
PP = mon_pp(); PP.release_m = true;
for n = {'channel_switch', 'freq_diversity', 'channel_switch+power_control', 'freq_diversity+spatial_diversity+power_control'}
    c = find(strcmp(A, n{1}));
    X = const_trace(PP, T, -6, 12, 0, 'none', 0, c);
    for kind = {'rule_esc', 'table'}
        opt = struct(); if strcmp(kind{1}, 'table'), opt = table_opt(PP); end
        R = decide_run(kind{1}, PP, X, opt);
        verifyTrue(tc, all(R.a == c), sprintf('%s %s', kind{1}, n{1}));
    end
    ag = dqn_stub(PP, c);
    verifyTrue(tc, all(decide_run('dqn_esc', PP, X, struct(), ag).a == c));
end
end

function test_relm_needs_evidence(tc)
% Every cycle of the window must be quiet: a busy bin, interference in the quiet slot (over PP.q_thr), an
% alarm, a degraded link, a drop alarm or a missing idle record starts the count again.
A = policy_actions(); na = find(strcmp(A, 'no_action')); pcfg = find(strcmp(A, 'power_control'));
PP = mon_pp(); PP.release_m = true; PP.confirm = [2 2]; T = 12;
rel = @(P, f) first_release(decide_run('rule_esc', P, make_x(P, T, f, pcfg)), na);
q0 = @(t) mk_obs(PP, -6, 12, 0, pcfg, 'none', 0);
verifyEqual(tc, rel(PP, q0), 6);
verifyEqual(tc, rel(PP, @(t) mk_obs(PP, -6, 12, 0, pcfg, 'none', 0.05 * (t == 4))), 10);    % a busy bin at cycle 4
verifyEqual(tc, rel(PP, @(t) mk_obs(PP, -6, 12, 0, pcfg, 'none', 0.05 * (t == 11))), 6);    % one at cycle 11 comes after
verifyEqual(tc, rel(PP, @(t) mk_obs(PP, -6, 12, 5 * (t == 3), pcfg, 'none', 0)), 9);        % quiet slot over the threshold at 3
P2 = PP; P2.q_thr = 8;
verifyEqual(tc, rel(P2, @(t) mk_obs(P2, -6, 12, 5 * (t == 3), pcfg, 'none', 0)), 6);        % under the deployed threshold
verifyEqual(tc, rel(PP, @(t) mk_obs(PP, -6, 12, 0, pcfg, 'none', ternary_nan(t == 2))), 8);   % no idle record at cycle 2
verifyEqual(tc, rel(PP, @(t) mk_obs(PP, -6, 12, 0, pcfg, 'none', ternary_nan(true))), NaN);
verifyEqual(tc, rel(PP, @(t) mk_obs(PP, -1, 12, 0, pcfg, 'none', 0)), NaN);                 % degraded
P3 = PP; P3.alarm_mode = 'class_drop'; P3.drop_db = 4;
e = 12 * ones(1, T); e(5:end) = 2;                                           % a drop alarm from cycle 6 on
verifyEqual(tc, rel(P3, @(t) mk_obs(P3, -6, e(t), 0, pcfg, 'none', 0)), NaN);
R = decide_run('rule_esc', PP, make_x(PP, T, @(t) mk_obs(PP, -6, 12, 0, pcfg, 'jamming', 0), pcfg));
verifyFalse(tc, any(R.a == na));
end

function test_relm_scope(tc)
% The layer is the deployed kind's: the rule, the table and the DQN get it; the core rule, the rule
% without the detector and the policies that do not read the monitor do not.
A = policy_actions(); na = find(strcmp(A, 'no_action')); rr = find(strcmp(A, 'rate_reduce'));
pcfg = find(strcmp(A, 'power_control'));
PP = mon_pp(); PP.release_m = true; PP.confirm = [2 2]; T = 12;
X = const_trace(PP, T, -6, 12, 0, 'none', 0, rr);
R = decide_run('rule_esc', PP, X, struct('core', true));
verifyTrue(tc, all(R.a == rr)); verifyTrue(tc, all(cellfun(@(I) ~any(I.relm), R.I)));
X = const_trace(PP, T, -6, 12, 0, 'none', 0, pcfg);
R = decide_run('blind_esc', PP, X);
verifyTrue(tc, all(R.a == pcfg));
R = decide_run('fixed', PP, X, struct('fixed', pcfg));
verifyTrue(tc, all(R.a == pcfg));
src = strrep(fileread(which('policy_decide')), char(13), '');
verifyNotEmpty(tc, strfind(src, 'if rm_on && ~core && ~blind && any(strcmp(base, {''dqn'', ''rule'', ''table''}))'));
end

function test_relm_adopt(tc)
% RELM is adopted only if all four hold on the validation sets: the running cost after the end falls (the
% one-sided 95% upper bound of the paired difference below 0), no threat's premature releases rise by more
% than 0.5 point or significantly, no recovery cost (held and recovered per threat at most 1 point, pooled
% held at most 0.5 point), the false-change rate within the plain DQN's one-sided Garwood bound.
[Std, Off, Per, Cln] = relm_world();
A = relm_adopt(Std, Off, Per, Cln);
verifyTrue(tc, A.a && A.b && A.c && A.d && A.adopt);
verifyEqual(tc, numel(A.lines), 5);
verifyNotEmpty(tc, strfind(A.lines{end}, 'non-inferiority margin'));
O1 = Off; O1.on.cost_end = O1.off.cost_end;                                 % no gain
A = relm_adopt(Std, O1, Per, Cln); verifyFalse(tc, A.a); verifyFalse(tc, A.adopt); verifyTrue(tc, A.b && A.c && A.d);
P1 = Per; P1.on.rel_on(find(strcmp(P1.thr, 'path_loss'), 3)) = 1;                      % three of fifty path_loss episodes release early
A = relm_adopt(Std, Off, P1, Cln); verifyFalse(tc, A.b); verifyFalse(tc, A.adopt); verifyTrue(tc, A.a && A.c && A.d);
P1 = Per; P1.on.rel_on(find(strcmp(P1.thr, 'jamming'), 1)) = 1;              % one of fifty: 2 points, p = 0.5
A = relm_adopt(Std, Off, P1, Cln); verifyFalse(tc, A.b);
P1 = Per; i = find(strcmp(P1.thr, 'path_loss')); P1.on.held(i(1:2)) = false; % held recovery of a threat falls 4 points
A = relm_adopt(Std, Off, P1, Cln); verifyFalse(tc, A.c); verifyFalse(tc, A.adopt);
S1 = Std; i = find(strcmp(S1.thr, 'jamming')); S1.on.recovered(i(1:2)) = false;   % recovered of a threat falls 4 points
A = relm_adopt(S1, Off, Per, Cln); verifyFalse(tc, A.c);
C1 = Cln; C1.sw_on(1:100) = 1;                                              % 100 false changes against 50
A = relm_adopt(Std, Off, Per, C1); verifyFalse(tc, A.d); verifyFalse(tc, A.adopt);
u0 = gammaincinv(0.95, 50 + 1) / (Cln.T * 1800);
C1 = Cln; C1.sw_on = zeros(1, 1800); C1.sw_on(1:floor(u0 * Cln.T * 1800)) = 1;  % at the bound: still within it
A = relm_adopt(Std, Off, Per, C1); verifyTrue(tc, A.d);
C1.sw_on(1:ceil(u0 * Cln.T * 1800) + 1) = 1;
A = relm_adopt(Std, Off, Per, C1); verifyFalse(tc, A.d);
end

function test_relm_wiring(tc)
% The stage glue: C2 scores the layer on the selected agent only with relm_select, the rule fallback
% keeps running without it, the descriptive rows run without it, the verdict row carries the layer.
src = fileread(which('train_dqn'));
verifyNotEmpty(tc, strfind(src, 'relm_score(PPsel, K, H, agent, sel_kind, val_spec, val_thr, CV, EBNO_THR, SPLIT_VAL)'));
verifyNotEmpty(tc, strfind(src, 'if WF.relm, dec.release_m = RELM.adopt; end'));
verifyNotEmpty(tc, strfind(src, 'if WF.relm, rule_sel.release_m = false; end'));
verifyNotEmpty(tc, strfind(src, 'A = relm_adopt(Std, Off, Per, Cln);'));
verifyNotEmpty(tc, strfind(src, 'op = struct(''rel_on'', true);'));
verifyNotEmpty(tc, strfind(src, 'so = sp; for b = 1:numel(so), so{b}.offset = so{b}.onset + 20; end'));
src = fileread(which('evaluate_policies'));
verifyNotEmpty(tc, strfind(src, 'if rm_on && startsWith(dep, ''dqn''), LBL{iDQN} = [LBL{iDQN} '', with the release on evidence'']; end'));
verifyNotEmpty(tc, strfind(src, 'xr = {''rule_esc_norelm'', ''table_norelm''};'));
verifyNotEmpty(tc, strfind(src, 'for pk = find(endsWith(POL, ''_norelm''))'));
src = fileread(which('rollout_policy'));
verifyNotEmpty(tc, strfind(src, 'if isfield(opt, ''rel_on'') && opt.rel_on'));
verifyNotEmpty(tc, strfind(src, 'R.rel_on = sum(tr.cfg == K.na & prev ~= K.na & tr.post & ~tr.ended, 1);'));
src = fileread(which('measure_all_kpis'));
verifyNotEmpty(tc, strfind(src, 'kn = find(strcmp(P.POL, [P.POL{iQ} ''_norelm'']), 1); kr0 = col(''rule_esc_norelm'');'));
end

function test_policy_setup_suffix(tc)
% A policy name with _norelm or _nos1g is the same policy with that setting switched off for the row;
% every other name is unchanged and gets no monitor option.
Q = struct('agent', 'A0', 'agents', {{'A1', 'A2'}}, 'rule_sel', struct('alarm', 'x', 'confirm', [2 2]));
tab = struct('table', [1 2 3], 'table_unknown', 1);
[k, ag, o] = policy_setup('rule_esc', Q, 2, 3, 4, tab, 1);
verifyEqual(tc, {k, ag}, {'rule_esc', 'A0'}); verifyEmpty(tc, fieldnames(o));
[k, ag, o] = policy_setup('rule_esc_norelm', Q, 2, 3, 4, tab, 1);
verifyEqual(tc, {k, ag}, {'rule_esc', 'A0'}); verifyEqual(tc, o.monitor, struct('release_m', false));
[k, ~, o] = policy_setup('rule_esc_nos1g', Q, 2, 3, 4, tab, 1);
verifyEqual(tc, k, 'rule_esc'); verifyEqual(tc, o.monitor, struct('s1_gate', false));
[k, ag, o] = policy_setup('dqn_esc_norelm', Q, 2, 3, 4, tab, 1);
verifyEqual(tc, {k, ag}, {'dqn_esc', 'A2'}); verifyFalse(tc, o.monitor.release_m);
[k, ag, o] = policy_setup('dqn_g1_norelm', Q, 2, 3, 4, tab, 1);
verifyEqual(tc, {k, ag}, {'dqn', 'A1'}); verifyFalse(tc, o.monitor.release_m);
[k, ~, o] = policy_setup('table_norelm', Q, 2, 3, 4, tab, 1);
verifyEqual(tc, k, 'table'); verifyEqual(tc, o.table, tab.table); verifyFalse(tc, o.monitor.release_m);
[k, ~, o] = policy_setup('rule_sel_norelm', Q, 2, 3, 4, tab, 1);
verifyEqual(tc, k, 'rule_esc'); verifyEqual(tc, o.monitor.alarm, 'x'); verifyFalse(tc, o.monitor.release_m);
[~, ~, o] = policy_setup('rule_core', Q, 2, 3, 4, tab, 1);
verifyEqual(tc, fieldnames(o), {'core'});
end

%% ---------- per Eb/N0 rows ----------
function test_ebno_rows(tc)
% The recovered share per Eb/N0 point with its cluster bootstrap interval, the clusters behind it, the link
% tag (L: ratio_ok x clean loss >= 1; J: under 0.1; M between), "lower bound >= 90" iff the interval says
% so, and the deficit by threat summing to what is not recovered.
ebno = [0 3 9 15]; fer = [0.8 0.3 0.01 0.001];
rec = []; s = []; g = []; thr = {};
for k = 1:3                                                                 % point 4 has no episode
    for c = 1:10
        for j = 1:4
            ok = true; t = 'a';
            if k == 1 && c <= 6 && j == 1, ok = false; t = 'a'; end
            if k == 1 && c > 6 && j == 1, ok = false; t = 'b'; end
            if k == 3 && c == 1 && j == 1, ok = false; t = 'a'; end
            rec(end+1) = ok; s(end+1) = k; g(end+1) = 1000 * k + c; thr{end+1} = t; %#ok<AGROW>
        end
    end
end
[rows, lines] = ebno_rows(rec, s, g, thr, ebno, fer, 2, 'Test');
verifyEqual(tc, numel(rows), 3); verifyEqual(tc, numel(lines), 4);
verifyEqual(tc, [rows.ebno], [0 3 9]); verifyEqual(tc, [rows.n], [40 40 40]); verifyEqual(tc, [rows.clusters], [10 10 10]);
verifyEqual(tc, [rows.rec], [75 100 97.5], 'AbsTol', 1e-9);
verifyEqual(tc, [rows.tag], 'LMJ');
verifyEqual(tc, [rows.lb90], [rows.lo] >= 90);
verifyTrue(tc, rows(2).lb90 && ~rows(1).lb90);
verifyTrue(tc, all([rows.lo] <= [rows.rec]) && all([rows.rec] <= [rows.hi]));
verifyEqual(tc, rows(1).threats, {'a', 'b'});
verifyEqual(tc, rows(1).deficit, [15 10], 'AbsTol', 1e-9);
verifyEqual(tc, sum(rows(1).deficit), 100 - rows(1).rec, 'AbsTol', 1e-9);
verifyEqual(tc, rows(3).deficit, [2.5 0], 'AbsTol', 1e-9);
verifyNotEmpty(tc, strfind(lines{2}, '[L]')); verifyNotEmpty(tc, strfind(lines{3}, 'lower bound >= 90: yes'));
verifyNotEmpty(tc, strfind(lines{1}, 'Descriptive'));
[rows2, ~] = ebno_rows(rec, s, g, thr, ebno, [], 2, 'Test');                 % no clean loss: no tag
verifyEqual(tc, [rows2.tag], '---');
[rows3, lines3] = ebno_rows(rec, s, g, thr, ebno, fer, 2, 'Test');
verifyTrue(tc, isequaln(rows, rows3) && isequal(lines, lines3));            % fixed seeds
end

function test_r9_wiring(tc)
% The rows are printed only with r9_print: C2 for the selected agent on validation, C2e for the deployed
% policy on the single test set, the KPI summary from the saved lines.
src = fileread(which('train_dqn'));
verifyNotEmpty(tc, strfind(src, 'ebno_rows(Vr.recovered(mr), sv(mr), 1000 * sv(mr) + Vr.r(mr), val_thr(mr), PP.ebno, ...'));
verifyNotEmpty(tc, strfind(src, 'if WF.r9, save(''data/trained_dqn.mat'', ''R9ROWS'', ''-append''); end'));
src = fileread(which('evaluate_policies'));
verifyNotEmpty(tc, strfind(src, '[R9ROWS, r9l] = ebno_rows(Rr.recovered(mr9), Rr.s(mr9), Rr.geom(mr9), PP.scen(Rr.scn(mr9)), PP.ebno, PP.clean_fer(:)'', ...'));
verifyNotEmpty(tc, strfind(src, 'if WF.r9, KP.ebno_rows = R9ROWS; KP.ebno_lines = r9l; end'));
src = fileread(which('measure_all_kpis'));
verifyNotEmpty(tc, strfind(src, 'if isfield(P.KP, ''ebno_lines''), det = [det, P.KP.ebno_lines]; end'));
end

%% ---------- helpers ----------
function PP = mon_pp()
% Monitor settings of the tests: the pools' configurations and classes, known gains.
A = policy_actions();
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
g = 6 * contains(A, 'power_control') + 3 * contains(A, 'rate_reduce');
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'cfg_gain_db', g);
end

function o = mk_obs(PP, lb, e, qi, link, cls, occ)
% One frame of one episode: log10 BER lb, measured Eb/N0 estimate e (SINR, no interference over thermal),
% quiet-slot interference qi [dB], class cls with probability 1, received with configuration link, an idle
% record whose busy share is occ (NaN: no record).
nF = numel(link_features('names')); nC = numel(PP.classes);
p = zeros(1, nC); p(find(strcmp(PP.classes, cls), 1)) = 1;
o = struct('probs', p, 'unknown', false, 'feat', zeros(1, nF), 'cfg_link', link);
o.feat(feature_index('log_ber')) = lb;
o.feat(feature_index('sinr')) = e - (10*log10(PP.sps) - 10*log10(PP.bps));
o.feat(feature_index('q_iot')) = qi;
o.idle = nan(1, numel(idle_summary('names')));
if ~isnan(occ), o.idle(strcmp(idle_summary('names'), 'occ')) = occ; end
end

function x = ternary_nan(c)
% NaN where c holds, else a clean idle record (busy share 0).
x = 0; if c, x = NaN; end
end

function X = const_trace(PP, T, lb, e, qi, cls, occ, cfg0)
% T cycles of the same frame (mk_obs) for one episode that starts in configuration cfg0.
X = make_x(PP, T, @(t) mk_obs(PP, lb, e, qi, cfg0, cls, occ), cfg0);
end

function X = make_x(PP, T, f, cfg0) %#ok<INUSL>
% T cycles of frames f(t) for episodes that start in configuration cfg0.
X = struct('obs', {cell(1, T)}, 'cfg0', cfg0);
for t = 1:T, X.obs{t} = f(t); end
end

function R = decide_run(kind, PP, X, opt, agent)
% policy_decide.m over the cycles of X, the policy's own request fed back as the configuration of the next
% cycle (no signalling delay): R.a (episodes x cycles) and R.I, the info of every cycle.
if nargin < 4, opt = struct(); end
if nargin < 5, agent = []; end
T = numel(X.obs); cfg = X.cfg0(:)'; NE = numel(cfg); mem = [];
R = struct('a', zeros(NE, T), 'I', {cell(1, T)});
for t = 1:T
    o = X.obs{t}; o.cfg_link = cfg(:);
    [a, mem, I] = policy_decide(kind, o, cfg, mem, PP, agent, opt);
    R.a(:, t) = a(:); R.I{t} = I; cfg = a(:)';
end
end

function t = first_release(R, na)
% The first cycle the request is no_action (NaN: never).
t = find(R.a(1, :) == na, 1); if isempty(t), t = NaN; end
end

function opt = table_opt(PP)
% A class -> configuration table that answers every class with power_control and none with no_action.
A = PP.actions; na = find(strcmp(A, 'no_action'));
tb = find(strcmp(A, 'power_control')) * ones(1, numel(PP.classes)); tb(1) = na;
opt = struct('table', tb, 'table_unknown', na);
end

function ag = dqn_stub(PP, hold)
% A deployed-form agent (dqn_dense.m) whose Q-values prefer configuration hold in every state.
nA = numel(PP.actions); nC = numel(PP.classes);
nS = policy_state_size(nA, nC);
q0 = zeros(nA, 1); q0(hold) = 1;
ag = struct('dense', struct('mu', zeros(nS, 1), 'sd', ones(nS, 1), 'W', {{zeros(nA, nS)}}, 'b', {{q0}}));
end

function [PP, X] = trace_world()
% Four episodes, 30 cycles: random classes, BER, SINR, quiet slot, CRC and idle records (episode 4 clean with
% a 10 dB step down at cycle 15: the drop alarm); episode 2 requests fec_interleave at cycle 6, episode 3
% power_control at 10 and no_action at 20; a request reaches the link one cycle later.
PP = mon_pp(); PP.alarm_mode = 'class_drop'; PP.drop_db = 4; PP.confirm = [2 2]; PP.confirm_sweep = [2 6];
A = PP.actions; na = find(strcmp(A, 'no_action'));
cf = find(strcmp(A, 'fec_interleave')); pc = find(strcmp(A, 'power_control'));
NE = 4; T = 30; nC = numel(PP.classes); nF = numel(link_features('names')); nI = numel(idle_summary('names'));
rs = RandStream('mt19937ar', 'Seed', 11);
REQ = na * ones(T + 1, NE); REQ(7:end, 2) = cf; REQ(11:20, 3) = pc;
LINK = [REQ(1, :); REQ(1:end-1, :)];
k0 = randi(rs, 20, 1, NE);
X = struct('obs', {cell(1, T)}, 'req', REQ, 'link', LINK);
for t = 1:T
    p = rand(rs, NE, nC) .^ 6; p(:, 1) = p(:, 1) + 0.8 * (rand(rs, NE, 1) < 0.85); p = p ./ sum(p, 2);
    o = struct('probs', p, 'unknown', false(NE, 1), 'feat', zeros(NE, nF), 'cfg_link', LINK(t, :)', ...
        'pkt', floor((k0(:) + t) / 2));
    o.feat(:, feature_index('log_ber')) = -4.5 + 2.5 * rand(rs, NE, 1);
    o.feat(:, feature_index('sinr')) = 6 + 2 * randn(rs, NE, 1) - 10 * [0 0 0 t >= 15]';
    o.feat(:, feature_index('iot')) = abs(randn(rs, NE, 1));
    o.feat(:, feature_index('q_iot')) = 6 * rand(rs, NE, 1) - 1;
    o.feat(:, feature_index('crc_fail')) = rand(rs, NE, 1) < 0.25;
    o.probs(4, :) = [1 zeros(1, nC - 1)]; o.feat(4, feature_index('log_ber')) = -6; o.feat(4, feature_index('crc_fail')) = 0;
    o.idle = nan(NE, nI); o.idle(:, 1) = 0.1 * (rand(rs, NE, 1) < 0.3);
    X.obs{t} = o;
end
end

function O = monitor_run(PP, X)
% Every M and memory of the monitor over the trace X.
T = numel(X.obs); NE = size(X.req, 2);
O = struct('M', {cell(1, T)}, 'mem', {cell(1, T)});
mem = policy_monitor('init', NE, numel(PP.actions));
for t = 1:T
    [mem, M] = policy_monitor('update', mem, X.obs{t}, PP, X.req(t, :));
    mem = policy_monitor('change', mem, X.req(t + 1, :) ~= X.req(t, :));
    O.M{t} = M; O.mem{t} = mem;
end
end

function [Tr, onset] = confirm_world()
% Two episodes of 10 cycles for monitor_confirm.m: the first has its Eb/N0 estimate 12 dB down for two cycles
% (the CUSUM at 18 dB^2 alarms on both), another path alarming from cycle 3 and the sweeper read in
% isolated cycles; the second is clean.
eg = 20 * ones(2, 10); eg(1, 4:5) = 8;
other = false(2, 10); other(1, 3:9) = true;
sw = false(2, 10); sw(1, [2 6]) = true; sw(2, 2) = true;
Tr = struct('eg', eg, 'other', other, 'sw', sw);
onset = zeros(1, 2);
end

function W = dconf_world(nf, nk, dips_fit, dips_chk, slow)
% Synthetic traces for dconf_step.m: nf + nk clean 30-cycle episodes (fit half, check half) with the Eb/N0
% estimate constant at 20 dB, the first dips_fit of the fit half and the first dips_chk of the check half
% with a two-cycle dip of 12 dB; 20 path_loss episodes (onset 5, the estimate 12 dB down from then on, the
% smallest level) and 20 jamming episodes (the other paths alarm from the onset). slow = 1: the jamming
% episodes are seen by the drop alarm alone, as a 5 dB step, which a higher threshold takes longer to cross.
n = nf + nk; T = 30;
Tc = struct('other', false(n, T), 'sw', false(n, T), 'eg', 20 * ones(n, T), 'quiet', false(n, T), ...
    'onset', zeros(1, n), 'scn', ones(1, n), 's', ones(1, n), 'r', 1:n);
fit = [true(1, nf), false(1, nk)]; chk = ~fit;
i = find(fit); Tc.eg(i(1:dips_fit), 10:11) = 8;
i = find(chk); Tc.eg(i(1:dips_chk), 10:11) = 8;
P = 20; m = 2 * P;
Tv = struct('other', false(m, T), 'sw', false(m, T), 'eg', 20 * ones(m, T), 'quiet', false(m, T), ...
    'onset', 5 * ones(1, m), 'scn', ones(1, m), 's', ones(1, m), 'r', [1:P, 1:P]);
Tv.eg(1:P, 6:end) = 8;
Tv.other(P+1:end, 6:end) = true;
if slow, Tv.other(P+1:end, 6:end) = false; Tv.eg(P+1:end, 6:end) = 15; end
thv = [repmat({'path_loss'}, 1, P), repmat({'jamming'}, 1, P)];
D1 = decision_config().sev.path_loss.levels(1);
W = struct('Tc', Tc, 'Tv', Tv, 'fit', fit, 'chk', chk, 'onv', true(1, m), 'thv', {thv}, 'thn', {{'path_loss', 'jamming'}}, ...
    'sev1', [true(1, P), false(1, P)], 'GF', D1^2 / 2 * (1:0.5:10), 'MON', {{'class_drop 5/5'}});
W.MONP = struct('monitor', 'class_drop 5/5', 'cf', [5 5], 'pick', W.GF(1), 'j', 1);
end

function [D, lines] = dconf_run(W, force)
% dconf_step.m on the world W, one monitor at its threshold in force, no sweeper's confirmation.
[D, lines] = dconf_step('class_cusum', W.GF, W.MON, W.MONP, [], W.Tc, W.fit, W.chk, W.Tv, W.onv, W.thv, W.thn, ...
    W.sev1, 0.05, force);
end

function T = sub_tr(T, m)
% The episodes m of a monitor trace.
for f = fieldnames(T)'
    if size(T.(f{1}), 1) > 1, T.(f{1}) = T.(f{1})(m(:), :); else, T.(f{1}) = T.(f{1})(m(:)'); end
end
end

function u = cp_up(k, n)
% One-sided 95% Clopper-Pearson upper bound.
if k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

function t = confirm_drop_of_text(src)
% The local function that looks a monitor's confirmation up in PP.dconf, as text.
t = regexp(src, 'function c = confirm_drop_of\(PP, name\).*?(?=\nfunction |$)', 'match', 'once');
end

function [V0, V1, thr, s] = s1g_world()
% Validation episodes of the rule without and with the gate: 40 per threat on 40 flights, recovered by both.
names = {'jamming', 'path_loss', 'antenna_fault', 'airframe_shadowing', 'jamming+antenna_fault'};
thr = repelem(names, 40); n = numel(thr);
s = repmat(repelem(1:4, 10), 1, 5); r = repmat(repmat(1:10, 1, 4), 1, 5);
V0 = struct('recovered', true(1, n), 'recoverable', true(1, n), 'threat', true(1, n), 'r', r);
V1 = V0;
V1.recovered(strcmp(thr, 'antenna_fault')) = [true(1, 20), false(1, 20)];     % the cost on the lost-branch classes
end

function [Std, Off, Per, Cln] = relm_world()
% Validation readings of the agent without (off) and with (on) the release: the standard sets, the offset set
% (cost after the end), the persistent set (releases while the threat is on) and the clean flights.
n = 100; cl = repelem(1:20, 1, 5); thr = repmat({'jamming', 'path_loss'}, 1, 50);
ep = @() struct('recovered', true(1, n), 'held', true(1, n), 'recoverable', true(1, n), 'threat', true(1, n), ...
    'cost_end', 20 + mod(1:n, 3), 'rel_on', zeros(1, n));
Std = struct('off', ep(), 'on', ep(), 'thr', {thr}, 'cl', cl);
Off = struct('off', ep(), 'on', ep(), 'thr', {thr}, 'cl', cl);
Off.on.cost_end = Off.off.cost_end - 5 + mod(1:n, 2);
Per = struct('off', ep(), 'on', ep(), 'thr', {thr}, 'cl', cl);
sw = zeros(1, 1800); sw(1:50) = 1;
Cln = struct('sw_off', sw, 'sw_on', sw, 'T', 30, 'period_ms', 20);
end

function write_text(f, s)
fid = fopen(f, 'w'); fprintf(fid, '%s', s); fclose(fid);
end

function d = parent_copy(tc, rel, rev)
% The file rel as commit rev holds it, alone in a folder. An export without .git (the deploy
% queue's) reads the commit from the repository named by V7_GIT_REPO.
d = tempname; mkdir(d);
[~, nm, ext] = fileparts(rel);
repo = tc.TestData.root;
[sg, ~] = system(sprintf('git --no-optional-locks -C "%s" rev-parse --git-dir', repo));
if sg ~= 0 && ~isempty(getenv('V7_GIT_REPO')), repo = getenv('V7_GIT_REPO'); end
[st, out] = system(sprintf('git --no-optional-locks -C "%s" show %s:%s > "%s"', repo, rev, rel, ...
    fullfile(d, [nm ext])));
assertEqual(tc, st, 0, sprintf('git show %s:%s failed: %s', rev, rel, out));
end

function fixture_off(d, fn)
% Removes a parent-commit folder from the path and the disk (once).
if contains(path, d), rmpath(d); end
clear(fn);
if isfolder(d), rmdir(d, 's'); end
end
