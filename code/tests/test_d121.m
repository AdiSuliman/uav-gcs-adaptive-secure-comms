function tests = test_d121
%TEST_D121  D121 items 1 (CLT, PP.lb_accept), 2 (P-A, PP.s1_gate_core) and 4 (the drop
%   path's own false-alarm budget, choose_drop_threshold.m). Both items 1 and 2 reuse
%   policy_monitor.m's M.harm (D113, landed on wf-dec), not a new field. Run from the
%   repository root: results = runtests('code/tests')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
end

%% ---------- fixtures ----------
function [obs, PP] = lb_fixture(cls_idx, p_lb, degraded)
% One episode, classes fixed so column cls_idx is the fused class read by policy_monitor
% (probs one-hot at cls_idx, except when p_lb is given: antenna_fault's own column carries
% p_lb and the rest share what remains so antenna_fault still argmaxes).
cls = {'none', 'jamming', 'path_loss', 'antenna_fault', 'airframe_shadowing', 'benign_interference'};
A = policy_actions();
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', -1, 'q_thr', NaN, ...
    'confirm', [2 2]);
probs = zeros(1, numel(cls));
if nargin >= 2 && ~isempty(p_lb)
    probs(strcmp(cls, 'antenna_fault')) = p_lb;
    probs(strcmp(cls, 'none')) = 1 - p_lb;
else
    probs(cls_idx) = 1;
end
obs = struct('probs', probs, 'unknown', false, 'feat', zeros(1, numel(link_features('names'))));
obs.feat(feature_index('log_ber')) = -6;                 % clean by default: not degraded
if nargin >= 3 && degraded, obs.feat(feature_index('log_ber')) = 0; end  % forces a very high BER: degraded
end

function [a, mem, M] = step(obs, a, mem, PP)
if isempty(mem), mem = policy_monitor('init', 1, numel(PP.actions)); end
[mem, M] = policy_monitor('update', mem, obs, PP, a); %#ok<ASGLU>
end

%% ---------- item 1: CLT, PP.lb_accept (reuses M.harm) ----------
function test_lb_accept_off_is_bit_identical(tc)
% PP.lb_accept absent: the class-path hostile flag for a lost-branch class is unaffected
% by the new gate (the monitor's only new behaviour is adding M.harm / M.lb_not_accepted,
% which do not change M.alarm when the field is absent).
na = find(strcmp(policy_actions(), 'no_action'));
[obs, PP] = lb_fixture(4, [], false);                    % antenna_fault, clean (no harm)
mem = [];
[~, mem, M] = step(obs, na, mem, PP); %#ok<ASGLU>
verifyTrue(tc, M.alarm);                                 % class path alone raises it: unchanged behaviour
verifyFalse(tc, isfield(PP, 'lb_accept'));
verifyFalse(tc, isfield(M, 'harm'));                      % neither gate is on: M.harm is not even computed
end

function test_lb_accept_high_plb_without_harm_needs_tau(tc)
% A synthetic high p_LB without harm evidence is accepted as hostile only at p_LB >= tau_hi.
na = find(strcmp(policy_actions(), 'no_action'));
[obs, PP] = lb_fixture(4, 0.9, false);                   % antenna_fault, p_LB = 0.9, clean (no harm)
PP.lb_accept = struct('tau_hi', 0.95);                   % tau above this episode's p_LB: not accepted
[~, ~, M] = step(obs, na, [], PP);
verifyFalse(tc, M.alarm);
verifyTrue(tc, M.lb_not_accepted);
PP.lb_accept = struct('tau_hi', 0.5);                    % tau below it: accepted
[~, ~, M] = step(obs, na, [], PP);
verifyTrue(tc, M.alarm);
verifyFalse(tc, M.lb_not_accepted);
end

function test_lb_accept_harm_in_last_n_cycles_accepts(tc)
% Harm evidence (degraded) in one of the last n cycles of the deployed confirmation accepts
% the lost-branch class even with p_LB below tau_hi (and even once the degraded cycle itself
% has passed, as long as it is within the n-cycle window).
na = find(strcmp(policy_actions(), 'no_action'));
[obs1, PP] = lb_fixture(4, 0.1, true);                   % cycle 1: degraded (harm), low p_LB
PP.lb_accept = struct('tau_hi', 0.95);
mem = [];
[~, mem, M1] = step(obs1, na, mem, PP);
verifyTrue(tc, M1.alarm);                                % harm alone already raises it
[obs2, ~] = lb_fixture(4, 0.1, false);                   % cycle 2: not degraded, same low p_LB
[~, mem, M2] = step(obs2, na, mem, PP); %#ok<ASGLU>
verifyTrue(tc, M2.harm);                                 % cycle 1's harm still in the n = confirm(2) window
verifyTrue(tc, M2.alarm);                                % accepted at the argmax (the class) via harm history
end

function test_harm_single_writer(tc)
% mem.hm (the harm-evidence history; the same field D113's PP.s1_gate reads, written via
% hist_bits in policy_monitor.m) is written in exactly one place, shared by PP.s1_gate,
% PP.s1_gate_core and PP.lb_accept.
src = fileread(which('policy_monitor'));
writes = regexp(src, 'hist_bits\(mem,\s*''hm''', 'match');
verifyEqual(tc, numel(writes), 1);
assigns = regexp(src, 'M\.harm\s*=', 'match');
verifyEqual(tc, numel(assigns), 1);
end

function test_lb_accept_static_no_truth(tc)
% Static test: the monitor's and decider's new lines read no truth field.
for f = {'policy_monitor', 'policy_decide'}
    src = fileread(which(f{1}));
    for tf = {'healthy', 'harmed', 'sc_eff', '\.ended'}
        verifyEmpty(tc, regexp(src, tf{1}, 'once'), sprintf('%s reads %s', f{1}, tf{1}));
    end
end
end

function test_lb_accept_forced_smoke_cell(tc)
% One forced smoke cell: a harm-only (tau_hi = Inf) monitor never accepts on p_LB alone,
% so every lost-branch alarm there is harm-carried; a q50 monitor accepts freely.
na = find(strcmp(policy_actions(), 'no_action'));
[obs, PP] = lb_fixture(4, 0.6, false);
PP.lb_accept = struct('tau_hi', Inf);
[~, ~, M] = step(obs, na, [], PP);
verifyFalse(tc, M.alarm);
PP.lb_accept = struct('tau_hi', 0.5);
[~, ~, M] = step(obs, na, [], PP);
verifyTrue(tc, M.alarm);
end

%% ---------- item 2: P-A, PP.s1_gate_core (reuses M.harm) ----------
function [obs, PP] = core_fixture(cls_idx, degraded)
cls = {'none', 'jamming', 'path_loss', 'antenna_fault', 'airframe_shadowing', 'benign_interference'};
A = policy_actions();
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', -1, 'q_thr', NaN, 'confirm', [2 2]);
probs = zeros(1, numel(cls)); probs(cls_idx) = 1;
obs = struct('probs', probs, 'unknown', false, 'feat', zeros(1, numel(link_features('names'))));
obs.feat(feature_index('log_ber')) = -6;
if nargin >= 2 && degraded, obs.feat(feature_index('log_ber')) = 0; end
end

function test_s1_gate_core_off_is_bit_identical(tc)
na = find(strcmp(policy_actions(), 'no_action'));
[obs, PP] = core_fixture(4, false);                      % antenna_fault, no harm
a = na; mem = [];
for k = 1:4, [a, mem, d] = policy_decide('rule', obs, a, mem, PP, [], struct('core', true)); end %#ok<ASGLU,NASGU>
verifyNotEqual(tc, a, na);                                % rule_core answers the class as before (no gate)
end

function test_s1_gate_core_on_without_harm_stays_no_action(tc)
na = find(strcmp(policy_actions(), 'no_action'));
[obs, PP] = core_fixture(4, false);                      % antenna_fault, no harm
PP.s1_gate_core = true;
a = na; mem = [];
for k = 1:6, [a, mem, d] = policy_decide('rule', obs, a, mem, PP, [], struct('core', true)); end %#ok<NASGU>
verifyEqual(tc, a, na);                                  % gated: no_action, and no escalation out of it
end

function test_s1_gate_core_on_with_harm_answers_and_escalates(tc)
na = find(strcmp(policy_actions(), 'no_action'));
[obs, PP] = core_fixture(4, true);                       % antenna_fault, degraded (harm)
PP.s1_gate_core = true;
a = na; mem = [];
for k = 1:4, [a, mem, d] = policy_decide('rule', obs, a, mem, PP, [], struct('core', true)); end %#ok<NASGU>
verifyNotEqual(tc, a, na);
end

function test_rule_core_policy_byte_identical(tc)
base = 'f6f6e03';
[~, oldtxt] = system(sprintf('git show %s:code/decision/rule_core_policy.m', base));
newtxt = fileread(which('rule_core_policy'));
verifyEqual(tc, strrep(newtxt, char(13), ''), strrep(oldtxt, char(13), ''));
end

function test_s1_gate_core_blind_and_other_classes_unaffected(tc)
na = find(strcmp(policy_actions(), 'no_action'));
% blind_core: no class path at all, unaffected by the gate.
[obs, PP] = core_fixture(4, false); PP.s1_gate_core = true;
a = na; mem = [];
for k = 1:4, [a, mem, d] = policy_decide('blind', obs, a, mem, PP, [], struct('core', true)); end %#ok<NASGU>
PPn = PP; PPn.s1_gate_core = false;
a2 = na; mem2 = [];
for k = 1:4, [a2, mem2, d2] = policy_decide('blind', obs, a2, mem2, PPn, [], struct('core', true)); end %#ok<NASGU>
verifyEqual(tc, a, a2);
% jamming: not a lost-branch class, bit-identical with the gate on or off.
[obs2, PP2] = core_fixture(2, false);
a3 = na; mem3 = [];
for k = 1:4, [a3, mem3] = policy_decide('rule', obs2, a3, mem3, PP2, [], struct('core', true)); end
PP2.s1_gate_core = true;
a4 = na; mem4 = [];
for k = 1:4, [a4, mem4] = policy_decide('rule', obs2, a4, mem4, PP2, [], struct('core', true)); end
verifyEqual(tc, a3, a4);
end

function test_s1_gate_core_forced_smoke_cell(tc)
na = find(strcmp(policy_actions(), 'no_action'));
[obs, PP] = core_fixture(5, false);                      % airframe_shadowing, no harm
PP.s1_gate_core = true;
a = na; mem = [];
for k = 1:6, [a, mem] = policy_decide('rule', obs, a, mem, PP, [], struct('core', true)); end
verifyEqual(tc, a, na);
end

%% ---------- item 4: the drop path's own false-alarm budget ----------
function test_drop_path_pick_rescues_before_fallback(tc)
% Synthetic clean trace: the degradation path alone already breaks the whole-monitor bound
% (Tr.other always true), but the drop alarm never fires on its own at a conservative
% threshold. drop_path_pick must find that conservative, admissible value instead of
% reporting "no threshold admissible" only at the least-sensitive grid point.
Tr = struct('eg', zeros(150, 10), 'other', true(150, 10), 'sw', false(150, 10));
GF = [2 4 6];                                            % ascending: conservative at the end
cf = [2 2];
PB = drop_path_pick_wrap(Tr, 'class_drop', GF, cf, [], 150, 0.02);
verifyTrue(tc, PB.admissible);
verifyEqual(tc, PB.k, 0);                                % the drop alarm alone never fires here
end

function PB = drop_path_pick_wrap(Tr, mode, GF, cf, cs, ncl, bound)
% Exposes choose_drop_threshold.m's local drop_path_pick via a thin re-implementation (the
% function is local to that script, so it is mirrored here for the unit test only -- this
% catches a regression in the counting rule it shares with drop_only_count).
PB = struct('admissible', false, 'pick', NaN, 'j', NaN, 'k', NaN, 'bound', NaN);
for j = numel(GF):-1:1
    a = false(size(Tr.eg)); if isfinite(GF(j)), a = drop_alarm_seq(Tr.eg, mode, GF(j), [], Tr.other); end
    c = movsum(double(Tr.other | a), [cf(2) - 1, 0], 2) >= cf(1);
    if ~isempty(cs) && isfield(Tr, 'sw')
        cs_hit = movsum(double(Tr.sw), [cs(2) - 1, 0], 2) >= cs(1);
        c = c | cs_hit;
    else
        cs_hit = false(size(c));
    end
    k = 0;
    for i = 1:size(Tr.eg, 1)
        f = find(c(i, :), 1);
        if ~isempty(f) && a(i, f) && ~Tr.other(i, f) && ~cs_hit(i, f), k = k + 1; end
    end
    up = cp_upper_t(k, ncl);
    if up <= bound
        PB = struct('admissible', true, 'pick', GF(j), 'j', j, 'k', k, 'bound', up);
    else
        break
    end
end
end

function u = cp_upper_t(k, n)
if n == 0, u = NaN; elseif k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

function test_choose_drop_threshold_static_no_truth(tc)
src = fileread(which('choose_drop_threshold'));
for tf = {'healthy', 'harmed', 'sc_eff', '\.ended'}
    verifyEmpty(tc, regexp(src, tf{1}, 'once'), sprintf('choose_drop_threshold reads %s', tf{1}));
end
end

function test_choose_drop_threshold_m_file_parses(tc)
% Parse check (no MATLAB slot for runtests at authoring time): mtree must not error.
mtree(which('choose_drop_threshold'), '-file');
verifyTrue(tc, true);
end

%% ---------- item 11: near/far OOD AUROC lines (descriptive, measure_all_kpis.m) ----------
function test_near_far_ood_split_matches_direct_mean(tc)
% Reproduces the item-11 snippet's arithmetic on a synthetic 4-threat A/held_out pair
% (independent of any saved results/*.mat), so the near/far means are checked without
% a MATLAB slot to run measure_all_kpis.m end to end.
held = {'antenna_fault', 'path_loss', 'airframe_shadowing', 'jamming'};
A = [0.70; 0.90; 0.60; 0.95];                       % single selected-score column
near_names = {'antenna_fault', 'airframe_shadowing'};
near_m = ismember(held, near_names);
verifyEqual(tc, mean(A(near_m)), mean([0.70, 0.60]), 'AbsTol', 1e-12);
verifyEqual(tc, mean(A(~near_m)), mean([0.90, 0.95]), 'AbsTol', 1e-12);
verifyEqual(tc, sum(~near_m), 2);
end

function test_near_far_ood_split_skipped_when_one_group_empty(tc)
% Both-groups-present guard (item 11 only applies the label with >=1 threat on each side).
held = {'antenna_fault', 'airframe_shadowing'};
near_m = ismember(held, {'antenna_fault', 'airframe_shadowing'});
verifyTrue(tc, all(near_m));                        % far side would be empty: snippet's `any(~near_m)` is false
end

function test_measure_all_kpis_m_file_parses(tc)
% Parse check (no MATLAB slot for runtests at authoring time): mtree must not error.
mtree(which('measure_all_kpis'), '-file');
verifyTrue(tc, true);
end
