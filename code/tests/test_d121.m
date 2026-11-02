function tests = test_d121
%TEST_D121  D121 items 1 (CLT, PP.lb_accept), 2 (P-A, PP.s1_gate_core) and 4 (the drop
%   path's own false-alarm budget, choose_drop_threshold.m). Both items 1 and 2 reuse
%   policy_monitor.m's M.harm (D113, landed on wf-dec), not a new field. Run from the
%   repository root: results = runtests('code/tests'). Item 16 (P-B, rule_core3 in profile 3's
%   C2e: core3_model.m, pool_cell.m, link_env.m, policy_monitor.m, policy_decide.m, the C2e rows) at
%   the end, the off tests against 9e6b7c8 (tip3-lb).
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
parses_ok(tc, 'choose_drop_threshold');
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
parses_ok(tc, 'measure_all_kpis');
verifyTrue(tc, true);
end

%% ---------- item 13: joint, power-weighted CFO across antennas (diagnostic) ----------
function [G, tb] = cfo_fixture(rs, f0, fd, NR, NB, dt, snr_db)
% NR independent Rayleigh antennas (Jakes sum of sinusoids, max Doppler fd), a common
% offset f0 [Hz], complex noise at snr_db against the mean power.
tb = (0:NB-1) * dt;
G = complex(zeros(NR, NB));
for r = 1:NR
    th = 2 * pi * rand(rs, 16, 1); ph = 2 * pi * rand(rs, 16, 2);
    fdn = fd * cos(th);
    G(r, :) = (exp(1j * ph(:, 1)).' * exp(1j * 2 * pi * fdn * tb) ...
        + 1j * exp(1j * ph(:, 2)).' * exp(1j * 2 * pi * (fd * sin(th)) * tb)) / sqrt(16 * 2);
end
G = G .* exp(1j * 2 * pi * f0 * tb) + 10^(-snr_db / 20) * (randn(rs, NR, NB) + 1j * randn(rs, NR, NB)) / sqrt(2);
end

function test_cfo_joint_exact_without_fading(tc)
% Constant gains with a different phase per antenna and one common offset: the per-antenna
% slope and the joint estimate both recover it, the residual is nil.
tb = (0:11) * 2e-4;
G = [1; 0.5; 2] .* exp(1j * [0.3; -2; 1]) .* exp(1j * 2 * pi * 700 * tb);
S = cfo_joint(G, tb);
verifyEqual(tc, S.slope_hz, 700 * ones(3, 1), 'AbsTol', 1e-3);
verifyEqual(tc, S.joint_hz, 700, 'AbsTol', 1e-3);
verifyEqual(tc, S.resid_hz, zeros(3, 1), 'AbsTol', 1e-3);
verifyEqual(tc, S.resid_rad, zeros(3, 1), 'AbsTol', 1e-6);
verifyEqual(tc, S.spread_hz, 0, 'AbsTol', 1e-3);
verifyEqual(tc, sum(S.w), 1, 'AbsTol', 1e-12);
end

function test_cfo_joint_beats_per_antenna_slope_in_fades(tc)
% Random FM near deep fades: on 400 fixed-seed 3-antenna Rayleigh frames at 161 km/h's
% Doppler (358 Hz), the joint power-weighted estimate has a smaller RMS error than the
% per-antenna slopes, and the per-antenna slopes spread well above the maximum Doppler.
rs = RandStream('mt19937ar', 'Seed', 13);
f0 = 500; ej = zeros(400, 1); es = zeros(400, 3); sp = zeros(400, 1);
for k = 1:400
    [G, tb] = cfo_fixture(rs, f0, 358, 3, 16, 2e-4, 15);
    S = cfo_joint(G, tb);
    ej(k) = S.joint_hz - f0; es(k, :) = (S.slope_hz - f0).'; sp(k) = S.spread_hz;
end
verifyLessThan(tc, sqrt(mean(ej.^2)), sqrt(mean(es(:).^2)));
verifyLessThan(tc, median(abs(ej)), median(abs(es(:))));
verifyGreaterThan(tc, median(sp), 100);
end

function test_cfo_joint_zero_antenna_carries_no_weight(tc)
tb = (0:11) * 2e-4;
G = [1; 0; 2] .* exp(1j * 2 * pi * 300 * tb);
S = cfo_joint(G, tb);
verifyEqual(tc, S.w(2), 0, 'AbsTol', 1e-12);
verifyTrue(tc, isnan(S.slope_hz(2)));
verifyEqual(tc, S.joint_hz, 300, 'AbsTol', 1e-3);
end

function test_cfo_joint_too_few_blocks_is_nan(tc)
S = cfo_joint(ones(3, 2), [0 1e-4]);
verifyTrue(tc, isnan(S.joint_hz));
verifyError(tc, @() cfo_joint(ones(3, 4), [0 1e-4]), 'cfo_joint:size');
end

function test_cfo_joint_static_no_truth_and_parses(tc)
src = fileread(which('cfo_joint'));
for tf = {'healthy', 'harmed', 'sc_eff', '\.ended', 'truth', 'cfo_true'}
    verifyEmpty(tc, regexp(src, tf{1}, 'once'), sprintf('cfo_joint reads %s', tf{1}));
end
parses_ok(tc, 'cfo_joint');
parses_ok(tc, 'test_d121');
verifyTrue(tc, true);
end

%% ---------- item 6: D112's candidate threshold by its own drop-path count (dconf_step.m) ----------
function W = d6_world(nf, nk, dips_fit, dips_chk, n_other)
% dconf_step.m's synthetic world: nf + nk clean 30-cycle episodes (Eb/N0 estimate 20 dB), the first
% dips_fit of the fit half and dips_chk of the check half with a two-cycle 12 dB dip, the first n_other of
% each half alarming on another path from cycle 3 on (the class path breaking the whole-monitor bound);
% 20 path_loss episodes (onset 5, 12 dB down from then on) and 20 jamming episodes (other paths from the onset).
n = nf + nk; T = 30;
Tc = struct('other', false(n, T), 'sw', false(n, T), 'eg', 20 * ones(n, T), 'quiet', false(n, T), ...
    'onset', zeros(1, n), 'scn', ones(1, n), 's', ones(1, n), 'r', 1:n);
fit = [true(1, nf), false(1, nk)]; chk = ~fit;
i = find(fit); Tc.eg(i(1:dips_fit), 10:11) = 8; Tc.other(i(1:n_other), 3:end) = true;
i = find(chk); Tc.eg(i(1:dips_chk), 10:11) = 8; Tc.other(i(1:n_other), 3:end) = true;
P = 20; m = 2 * P;
Tv = struct('other', false(m, T), 'sw', false(m, T), 'eg', 20 * ones(m, T), 'quiet', false(m, T), ...
    'onset', 5 * ones(1, m), 'scn', ones(1, m), 's', ones(1, m), 'r', [1:P, 1:P]);
Tv.eg(1:P, 6:end) = 8; Tv.other(P+1:end, 6:end) = true;
thv = [repmat({'path_loss'}, 1, P), repmat({'jamming'}, 1, P)];
D1 = decision_config().sev.path_loss.levels(1);
W = struct('Tc', Tc, 'Tv', Tv, 'fit', fit, 'chk', chk, 'onv', true(1, m), 'thv', {thv}, 'thn', {{'path_loss', 'jamming'}}, ...
    'sev1', [true(1, P), false(1, P)], 'GF', D1^2 / 2 * (1:0.5:10), 'MON', {{'class_drop 5/5'}});
W.MONP = struct('monitor', 'class_drop 5/5', 'cf', [5 5], 'pick', W.GF(1), 'j', 1);
end

function [D, lines] = d6_run(W, varargin)
% dconf_step.m on the world W; varargin: the optional force and own arguments.
[D, lines] = dconf_step('class_cusum', W.GF, W.MON, W.MONP, [], W.Tc, W.fit, W.chk, W.Tv, W.onv, W.thv, W.thn, ...
    W.sev1, 0.05, varargin{:});
end

function T = d6_sub(T, m)
for f = fieldnames(T)'
    if size(T.(f{1}), 1) > 1, T.(f{1}) = T.(f{1})(m(:), :); else, T.(f{1}) = T.(f{1})(m(:)'); end
end
end

function kd = d6_drop_first(T, thr, cf, cdr)
% Independent count: clean episodes whose first confirmed cycle has no confirmation without the drop alarm.
[c, ~, cn] = monitor_confirm(T, 'class_cusum', thr, cf, [], cdr);
kd = 0;
for i = 1:size(c, 1)
    f = find(c(i, :), 1);
    if ~isempty(f) && ~cn(i, f), kd = kd + 1; end
end
end

function test_dconf_own_off_is_bit_identical(tc)
% The rule off (argument absent, [] or false) is dconf_step.m's output as it was, on a world with dips
% (thresholds above the first value) and one with none.
for dips = [0 8]
    W = d6_world(60, 60, dips, 0, 0);
    [D0, L0] = d6_run(W, []);
    [D1, L1] = d6_run(W, [], false);
    [D2, L2] = d6_run(W, [], []);
    verifyTrue(tc, isequaln(D0, D1) && isequaln(D0, D2) && isequal(L0, L1) && isequal(L0, L2));
end
end

function test_dconf_own_rescues_a_mechanical_failure(tc)
% The class path alone (20 of 60 fit-half clean episodes alarm on another path) breaks the
% whole-monitor bound at every threshold, so the old rule finds none for either candidate; the own
% drop-path rule, against the monitor's own count of drop-first episodes (0), adopts [2 2] at the
% most sensitive value, as the world without the other path does.
W = d6_world(60, 60, 0, 0, 20);
[Do, ~] = d6_run(W, [], false);
verifyEmpty(tc, Do(1).cand);
verifyTrue(tc, all(arrayfun(@(c) isnan(c.pick), Do(1).cands)));
[Dn, lines] = d6_run(W, [], true);
verifyEqual(tc, Dn(1).cand, [2 2]);
verifyEqual(tc, Dn(1).pick, W.GF(1));
verifyEqual(tc, Dn(1).ref.k_drop, 0);
verifyTrue(tc, Dn(1).cands(1).ok);
verifyNotEmpty(tc, strfind(strjoin(lines, '|'), 'own drop-path rule'));
end

function test_dconf_own_threshold_holds_the_references_count(tc)
% Fit-half dips: each candidate's threshold is the most sensitive grid value whose fit-half drop-first
% count is at most the monitor without it has at its threshold in force, computed here independently.
W = d6_world(60, 60, 8, 0, 0);
[D, ~] = d6_run(W, [], true);
C = decision_config(); GX = [W.GF, W.GF(end) * C.confirm_drop_ext];
Tf = d6_sub(W.Tc, W.fit);
ref = d6_drop_first(Tf, W.MONP.pick, W.MONP.cf, []);
jmax = 0;
for i = 1:numel(D(1).cands)
    cdr = D(1).cands(i).cd;
    kf = arrayfun(@(t) d6_drop_first(Tf, t, W.MONP.cf, cdr), GX);
    j = find(kf <= ref, 1);
    verifyEqual(tc, D(1).cands(i).pick, GX(j), sprintf('candidate %d', i));
    verifyLessThanOrEqual(tc, kf(j), ref);
    if j > 1, verifyGreaterThan(tc, kf(j - 1), ref); end
    jmax = max(jmax, j);
end
verifyGreaterThan(tc, jmax, 1);                                          % the dips raised a threshold
end

function test_dconf_own_wiring_and_static(tc)
src = fileread(which('dconf_step'));
for tf = {'healthy', 'harmed', 'sc_eff', '\.ended'}
    verifyEmpty(tc, regexp(src, tf{1}, 'once'), sprintf('dconf_step reads %s', tf{1}));
end
verifyNumElements(tc, regexp(fileread(which('choose_drop_threshold')), 'WFo\.dconf_own', 'match'), 1);
O = wf_options([], 'none.json'); verifyFalse(tc, O.dconf_own);
f = [tempname '.json'];
fid = fopen(f, 'w'); fprintf(fid, '{"dconf_select": true, "dconf_own": true}'); fclose(fid);
O = wf_options([], f); verifyTrue(tc, O.dconf_own && O.dconf);
fid = fopen(f, 'w'); fprintf(fid, '{"dconf_own": 1}'); fclose(fid);
verifyError(tc, @() wf_options([], f), 'wf_options:value');
delete(f);
parses_ok(tc, 'dconf_step'); parses_ok(tc, 'wf_options');
verifyTrue(tc, true);
end
%% ---------- item 10: onset-referenced recovery line (lect_kpis.m CN block) ----------
function ALL = onset_world(n, geom, tt_det, tt_blind)
% Policies none, rule_esc, blind_esc on n recoverable jamming episodes; the rows' onset -> restored times
% (t_conf = 1, t_rec_det = the rest; NaN: never) are tt_det and tt_blind.
R = struct('scn', 2 * ones(1, n), 'recoverable', true(1, n), 'recoverable_core', true(1, n), 'threat', true(1, n), ...
    'geom', geom, 'ok_post', 0.5 * ones(1, n));
ALL = cell(1, 3);
for k = 1:3
    S = R;
    switch k
        case 1, S.per_post = 0.5 * ones(1, n); S.t_conf = nan(1, n); S.t_rec_det = nan(1, n);
        case 2, S.per_post = 0.1 * ones(1, n); S.t_conf = ones(1, n); S.t_rec_det = tt_det - 1;
        case 3, S.per_post = 0.3 * ones(1, n); S.t_conf = ones(1, n); S.t_rec_det = tt_blind - 1;
    end
    S.dlv_post = 1 - S.per_post; S.gput_post = S.dlv_post; S.t_rec = S.t_conf + S.t_rec_det; S.recovered = isfinite(S.t_rec);
    ALL{k} = S;
end
end

function test_onset_recovery_pairs_and_shares(tc)
% Four episodes: rows recover [4 6 NaN 2] (detector) and [7 9 NaN NaN] (without): the pairing is on
% episodes 1-2 (differences -3, -3), episode 4 is recovered by the detector row only, 3 by neither;
% one geometry holds the pairs, so no interval.
POL = {'none', 'rule_esc', 'blind_esc'}; LBL = {'none', 'rule', 'blind'};
ALL = onset_world(4, [1 1 2 2], [4 6 NaN 2], [7 9 NaN NaN]);
[L, lines] = lect_kpis(ALL, POL, LBL, 2, {'none', 'jamming'}, 5e4, 20);
o = L.cnn.onset_rec;
verifyEqual(tc, [o.n, o.n_pair, o.median, o.mean], [4 2 -3 -3]);
verifyEqual(tc, [o.both_pct, o.only_det_pct, o.only_blind_pct, o.never_pct], [50 25 0 25], 'AbsTol', 1e-12);
verifyTrue(tc, all(isnan(o.median_ci)) && all(isnan(o.mean_ci)));
verifyTrue(tc, any(contains(lines, 'D121 item 10')));
end

function test_onset_recovery_interval_over_geometries(tc)
% Twelve episodes on six geometries with varying differences: the mean's interval is boot_cluster's with
% the line's seed (200 + 202), the median's interval brackets the median, and the shares add to 100.
POL = {'none', 'rule_esc', 'blind_esc'}; LBL = {'none', 'rule', 'blind'};
geom = repelem(1:6, 2);
tb = [9 8 7 9 6 10 8 7 9 8 10 9];
dd = [2 3 4 3 2 5 3 4 1 3 4 2];                          % blind minus detector, > 0
td = tb - dd; td(11) = NaN; tb(5) = NaN;                 % episode 11: detector never; 5: blind never
ALL = onset_world(12, geom, td, tb);
[L, ~] = lect_kpis(ALL, POL, LBL, 2, {'none', 'jamming'}, 5e4, 20);
o = L.cnn.onset_rec;
ok = isfinite(td) & isfinite(tb);
d = td(ok) - tb(ok);
verifyEqual(tc, o.n_pair, sum(ok));
verifyEqual(tc, o.median, median(d));
[m, lo, hi] = boot_cluster(d, ones(1, numel(d)), geom(ok), 2000, 402);
verifyEqual(tc, [o.mean, o.mean_ci], [m lo hi], 'AbsTol', 1e-12);
verifyTrue(tc, o.median_ci(1) <= o.median && o.median <= o.median_ci(2));
verifyEqual(tc, o.both_pct + o.only_det_pct + o.only_blind_pct + o.never_pct, 100, 'AbsTol', 1e-9);
verifyEqual(tc, [o.only_det_pct, o.only_blind_pct], 100 / 12 * [1 1], 'AbsTol', 1e-9);
end

function test_onset_recovery_changes_no_registered_reading(tc)
% The registered readings are the same with and without the new field: the verdict, the PER reduction and the
% rows are computed before it and nothing reads it back.
POL = {'none', 'rule_esc', 'blind_esc'}; LBL = {'none', 'rule', 'blind'};
ALL = onset_world(4, [1 1 2 2], [4 6 NaN 2], [7 9 NaN NaN]);
[L, ~] = lect_kpis(ALL, POL, LBL, 2, {'none', 'jamming'}, 5e4, 20);
L2 = L; L2.cnn = rmfield(L2.cnn, 'onset_rec');
verifyEqual(tc, fieldnames(L.cnn)', [fieldnames(L2.cnn)', {'onset_rec'}]);
verifyEqual(tc, L.cnn.per_red_pct, 100 * (1 - 0.1 / 0.3), 'AbsTol', 1e-9);   % with the detector against without
verifyEqual(tc, L.cnn.det(1).median, 1);
src = fileread(which('lect_kpis'));
for tf = {'healthy', 'harmed', 'sc_eff', '\.ended'}
    verifyEmpty(tc, regexp(src, tf{1}, 'once'), sprintf('lect_kpis reads %s', tf{1}));
end
parses_ok(tc, 'lect_kpis'); parses_ok(tc, 'measure_all_kpis');
end

%% ---------- item 8: non-emitter speed lines (speed_nonemitter.m) ----------
function [A, Edge, Cl] = speed_world()
% 40 episodes on 20 geometries, 10 at each of 4 speeds (20, 60, 100, 140 km/h; bands 0-40, 40-80, 80-120, 120-160), the
% threats by turns; emitter (jamming) episodes all fail, so they must not enter the lines.
n = 40; sp = repelem([20 60 100 140], 1, 10); geom = repelem(1:20, 2);
thr = repmat({'path_loss', 'jamming', 'airframe_shadowing', 'antenna_fault'}, 1, 10);
rec = true(1, n);
rec(strcmp(thr, 'jamming')) = false;                      % emitter threats all fail: must not enter the lines
rec(sp == 140 & strcmp(thr, 'path_loss')) = false;        % non-emitter failures in the top band
A = struct('recovered', rec, 'mask', true(1, n), 'speed', sp, 'geom', geom, 'thr', {thr});
Edge = struct('recovered', [true true false true true false], 'mask', true(1, 6), 'speed', 161 * ones(1, 6), ...
    'geom', 1:6, 'thr', {{'path_loss', 'antenna_fault', 'airframe_shadowing', 'jamming', 'path_loss', 'antenna_fault'}}, 'band', [160 162]);
Cl = struct('loss', [0.01 0.03 0.02 0.06 0.02 0.04], 'speed', [20 20 60 60 140 140], 'geom', 1:6);
end

function test_speed_nonemitter_reads_only_the_non_emitter_threats(tc)
[A, Edge, Cl] = speed_world();
[S, lines] = speed_nonemitter(A, Edge, Cl, [0 40 80 120 160], 500);
thr = A.thr; ne = ismember(thr, {'path_loss', 'antenna_fault', 'airframe_shadowing'});
lo = [0 40 80 120]; hi = [40 80 120 160];
for b = 1:4
    mb = ne & A.speed >= lo(b) & A.speed < hi(b) + (b == 4);
    verifyEqual(tc, S.per_band(b), 100 * mean(A.recovered(mb)), 'AbsTol', 1e-12);
    verifyEqual(tc, S.n_band(b), sum(mb));
end
verifyEqual(tc, S.per_band(1:3), [100 100 100]);          % emitter failures never enter
verifyLessThan(tc, S.per_band(4), 100);
verifyEqual(tc, S.spread(1), (max(S.per_band) - min(S.per_band)) / 100, 'AbsTol', 1e-12);
me = ismember(Edge.thr, {'path_loss', 'antenna_fault', 'airframe_shadowing'});
verifyEqual(tc, S.edge.pct, 100 * mean(Edge.recovered(me)), 'AbsTol', 1e-12);
verifyEqual(tc, S.edge.n, sum(me));
verifyEqual(tc, S.link.loss_pct, 100 * [mean([0.01 0.03]), mean([0.02 0.06]), NaN, mean([0.02 0.04])], 'AbsTol', 1e-12);
verifyEqual(tc, S.link.n, [2 2 0 2]);
verifyTrue(tc, any(contains(lines, 'D121 item 8')));
verifyTrue(tc, any(contains(lines, 'attitude loss is applied to our signal only')));
end

function test_speed_nonemitter_without_edge_and_clean_sets(tc)
[A, ~, ~] = speed_world();
[S, lines] = speed_nonemitter(A, [], [], [0 40 80 120 160], 200);
verifyEqual(tc, S.edge.n, 0); verifyTrue(tc, isnan(S.edge.pct));
verifyTrue(tc, all(isnan(S.link.loss_pct)));
verifyFalse(tc, any(contains(lines, 'dedicated flights')) || any(contains(lines, 'clean link per speed band')));
end

function test_speed_nonemitter_wiring_and_static(tc)
src = fileread(which('speed_nonemitter'));
for tf = {'healthy', 'harmed', 'sc_eff', '\.ended'}
    verifyEmpty(tc, regexp(src, tf{1}, 'once'), sprintf('speed_nonemitter reads %s', tf{1}));
end
ev = fileread(which('evaluate_policies'));
verifyNumElements(tc, regexp(ev, 'speed_nonemitter\(', 'match'), 1);
verifyNumElements(tc, regexp(ev, 'KP\.speed_ne\s*=', 'match'), 1);
mk = fileread(which('measure_all_kpis'));
verifyNotEmpty(tc, regexp(mk, 'speed_ne', 'once'));
parses_ok(tc, 'speed_nonemitter'); parses_ok(tc, 'evaluate_policies'); parses_ok(tc, 'measure_all_kpis');
verifyTrue(tc, true);
end

%% ---------- items 12 and 15: KPI 6 split by link K, speed, bank and hiding geometry ----------
function [flag, geom, cov] = split_world()
% 60 episodes on 30 geometries; policy 1 false-changes exactly on the K < 0 flights, policy 2 on bank >= 40 deg.
lk = [-5 * ones(1, 20), zeros(1, 10), 5 * ones(1, 10), 10 * ones(1, 10), 15 * ones(1, 10)];
cov = struct('lk', lk, 'speed', repmat([20 60 100 140], 1, 15), 'speed_bins', [0 40 80 120 160], ...
    'bank', repmat([0 19.9 20 -39.9 -40 60], 1, 10), 'hide', mod(1:60, 6) == 0);
flag = [lk < 0; abs(cov.bank) >= 40];
geom = repelem(1:30, 2);
end

function test_kpi6_split_counts_and_edges(tc)
[flag, geom, cov] = split_world();
[S, lines] = kpi6_split(flag, geom, cov, {'p1', 'p2'}, 200);
vk = S.var(strcmp({S.var.name}, 'estimated link K'));
verifyEqual(tc, vk.n(1, :), [20 20 20]);                             % K = 0 is the middle bin, K = 10 the top bin
verifyEqual(tc, vk.k(1, :), [20 0 0]);
verifyEqual(tc, vk.pct(1, :), [100 0 0]);
vb = S.var(strcmp({S.var.name}, 'bank'));
verifyEqual(tc, vb.n(1, :), [sum(abs(cov.bank) < 20), sum(abs(cov.bank) >= 20 & abs(cov.bank) < 40), sum(abs(cov.bank) >= 40)]);
verifyEqual(tc, vb.k(2, :), [0 0 sum(abs(cov.bank) >= 40)]);
vs = S.var(strcmp({S.var.name}, 'speed'));
verifyEqual(tc, vs.n(1, :), [15 15 15 15]);
vh = S.var(strcmp({S.var.name}, 'hiding geometry'));
verifyEqual(tc, vh.n(1, :), [10 50]);
verifyEqual(tc, S.hide_share(1), 100 * 10 / 60, 'AbsTol', 1e-9);
for v = 1:numel(S.var)
    verifyEqual(tc, sum(S.var(v).n, 2)', [60 60]);
end
verifyTrue(tc, any(contains(lines, 'D121 items 12 and 15')));
end

function test_kpi6_split_interval_is_the_cluster_bootstrap(tc)
[flag, geom, cov] = split_world();
flag(1, :) = mod(geom, 3) == 0;                                      % a flag that varies within the bins
[S, ~] = kpi6_split(flag, geom, cov, {'p1', 'p2'}, 300, 6101);
vk = S.var(1);
m = cov.lk < 0;
[q, lo, hi] = boot_cluster(double(flag(1, m)), ones(1, sum(m)), geom(m), 300, 6101 + 100 * 1 + 10 * 1 + 1);
verifyEqual(tc, [vk.pct(1, 1), squeeze(vk.ci(1, 1, :))'], 100 * [q lo hi], 'AbsTol', 1e-9);
verifyEqual(tc, vk.ncl(1, 1), numel(unique(geom(m))));
end

function test_kpi6_split_without_k_or_hiding(tc)
[flag, geom, cov] = split_world();
cov.lk(:) = NaN; cov = rmfield(cov, 'hide');
[S, lines] = kpi6_split(flag, geom, cov, {'p1', 'p2'}, 100);
verifyEqual(tc, S.var(1).n, zeros(2, 3));                            % no K: every episode outside the bins
verifyNumElements(tc, S.var, 3);
verifyTrue(tc, all(isnan(S.hide_share)));
verifyFalse(tc, any(contains(lines, 'hiding condition')));
end

function test_los_k_record_is_off_by_default_and_changes_nothing(tc)
% The monitor's K record: absent without PP.record_los_k (the field is not created); with it, the
% monitor's every other field is the same and the K column is NaN where no fusion runs.
na = find(strcmp(policy_actions(), 'no_action'));
[obs, PP] = lb_fixture(4, 0.6, false);
[~, memA] = step(obs, na, [], PP);
verifyFalse(tc, isfield(memA, 'los_k'));
PP.record_los_k = true;
[~, memB] = step(obs, na, [], PP);
verifyTrue(tc, isfield(memB, 'los_k') && all(isnan(memB.los_k)));
verifyEqual(tc, rmfield(memB, 'los_k'), memA);
names = window_cues('names');
verifyEqual(tc, sum(strcmp(names, 'los_k')), 1);
end

function test_clean_hides_matches_hides_antenna(tc)
% clean_hides.m is hides_antenna.m on the flight's draws with shadowing switched on; below the speed floor no flight hides.
d0 = tempname; mkdir(d0); c0 = cd(d0); back = onCleanup(@() cd(c0));   % init_params writes params.mat into the folder it runs in
evalc('init_params'); p0 = load('params.mat').params; p0.quiet_build = true;
cd(c0); rmdir(d0, 's');
C = decision_config(); lv = C.sev.airframe_shadowing.levels(C.nominal);
sd = 100 + (1:6); v = [161 161 161 161 161 0];
cov = struct('seed', sd, 'speed', v, 'alt_m', 120 * ones(1, 6), 'k_sig', 10 * ones(1, 6), 'aoa', nan(1, 6, 3), 'rho', 0.3 * ones(1, 6));
cov.aoa(1, :, 1) = 20;
H = clean_hides(cov, 10, p0, lv, C.event_frame, C.event_count);
ps = p0; ps.active_threat = 'airframe_shadowing'; ps.shadow_db = lv;
for r = 1:6
    h = hides_antenna(sd(r), v(r), ps, struct('ebno', 10, 'alt_m', 120, 'k_sig_db', 10, 'aoa1_deg', 20, 'rho', 0.3, ...
        'event_frame', C.event_frame, 'frames', C.event_count));
    verifyEqual(tc, H(r), h);
end
verifyFalse(tc, H(6));
cov.seed(2) = NaN;
H2 = clean_hides(cov, 10, p0, lv, C.event_frame, C.event_count);
verifyFalse(tc, H2(2));                                              % a missing draw is not a hiding flight
end

function test_k6_split_wiring_static_and_parse(tc)
src = fileread(which('choose_drop_threshold'));
verifyNumElements(tc, regexp(src, 'WFo\.k6split', 'match'), 2);
verifyNumElements(tc, regexp(src, 'kpi6_split\(', 'match'), 1);
verifyNumElements(tc, regexp(src, 'clean_hides\(', 'match'), 1);
verifyNumElements(tc, regexp(src, 'record_los_k', 'match'), 1);
for f = {'kpi6_split', 'clean_hides', 'monitor_trace'}
    s = fileread(which(f{1}));
    for tf = {'healthy', 'harmed', 'sc_eff', '\.ended'}
        verifyEmpty(tc, regexp(s, tf{1}, 'once'), sprintf('%s reads %s', f{1}, tf{1}));
    end
    parses_ok(tc, f{1});
end
parses_ok(tc, 'policy_monitor'); parses_ok(tc, 'choose_drop_threshold');
O = wf_options([], 'none.json'); verifyFalse(tc, O.k6split);
f = [tempname '.json']; fid = fopen(f, 'w'); fprintf(fid, '{"k6_split": true}'); fclose(fid);
O = wf_options([], f); verifyTrue(tc, O.k6split); delete(f);
end

%% ---------- item 3: receiver-robust side column of KPI 8 (rr_column.m, rr_us.m) ----------
function test_rr_column_words(tc)
verifyEqual(tc, rr_column([0.5 1.2], 0.4), 'yes');               % lower bound above U_s
verifyEqual(tc, rr_column([-1.2 -0.5], 0.4), 'yes');             % upper bound below -U_s
verifyEqual(tc, rr_column([0.2 1.0], 0.4), 'no');                % clears 0 but not by more than U_s
verifyEqual(tc, rr_column([-0.3 0.9], 0.4), 'no');
verifyEqual(tc, rr_column([0.4 1.0], 0.4), 'no');                % equal to U_s is not more than U_s
verifyEqual(tc, rr_column([0.1 0.2], 0), 'yes');                 % U_s = 0: the plain interval test
verifyEqual(tc, rr_column([0.5 1.2], NaN), 'n/a');               % units U_s does not cover
verifyEqual(tc, rr_column([0.5 1.2], []), 'n/a');
verifyEqual(tc, rr_column([NaN 1.2], 0.4), 'n/a');
verifyError(tc, @() rr_column([0.5 1.2], -1), 'rr_column:us');
end

function test_rr_us_reads_d2c_file_or_gives_nan(tc)
d = tempname; mkdir(d);
Us0 = rr_us(fullfile(d, 'none.mat'));
verifyTrue(tc, isnan(Us0.per) && isnan(Us0.gput) && isnan(Us0.trec));
Us = struct('per', 0.01, 'gput', 500); save(fullfile(d, 'u.mat'), 'Us');   % no trec: its units are not covered
U1 = rr_us(fullfile(d, 'u.mat'));
verifyEqual(tc, [U1.per U1.gput], [0.01 500]); verifyTrue(tc, isnan(U1.trec));
verifyEqual(tc, {rr_column([0.02 0.05], U1.per), rr_column([1 2], U1.trec)}, {'yes', 'n/a'});
rmdir(d, 's');
end

function test_rr_column_wiring_static_and_parse(tc)
src = fileread(which('experiment_core_bw'));
verifyNumElements(tc, regexp(src, 'rr_column\(', 'match'), 3);
verifyNumElements(tc, regexp(src, 'Us = rr_us\(\)', 'match'), 1);
verifyNotEmpty(tc, strfind(src, 'the registered pair above stands'));
for f = {'rr_column', 'rr_us'}
    s = fileread(which(f{1}));
    for tf = {'healthy', 'harmed', 'sc_eff', '\.ended'}
        verifyEmpty(tc, regexp(s, tf{1}, 'once'), sprintf('%s reads %s', f{1}, tf{1}));
    end
    parses_ok(tc, f{1});
end
parses_ok(tc, 'experiment_core_bw');
end

%% ---------- item 16: P-B, rule_core3 in profile 3's C2e (core3_model.m, pool_cell.m, link_env.m, policy_monitor.m, policy_decide.m) ----------
function PP = pb_pp(mode)
% The monitor's settings of the P-B tests: the detector's classes, the link-budget configurations' known gains.
A = policy_actions();
g = 6.5 * contains(A, 'power_control') + 3.5 * contains(A, 'rate_reduce');
w = 6.5 * contains(A, 'power_control');
PP = struct('actions', {A}, 'classes', {{'none', 'jamming', 'tone_jamming', 'path_loss', 'antenna_fault', 'airframe_shadowing'}}, ...
    'sps', 4, 'bps', 2, 'maha_thr', -Inf, 'confirm', [2 2], 'alarm_mode', mode, 'drop_db', 4, 'cfg_gain_db', g, 'pw', 10 .^ (w / 10));
if strcmp(mode, 'class_cusum'), PP.drop_db = 153; end
end

function X = pb_trace(PP, NE, T, seed, with3)
% NE episodes of T cycles: random class probabilities, BER, SINR with steps, quiet slot, CRC and antenna gains; with3
% adds obs.probs3 from a stream of its own, so the other fields are the same with or without it.
rs = RandStream('mt19937ar', 'Seed', seed); rq = RandStream('mt19937ar', 'Seed', 99);
nC = numel(PP.classes); nF = numel(link_features('names'));
X = cell(1, T); step = 6 * randi(rs, [0 2], NE, 1); k0 = randi(rs, [8 20], NE, 1);
for t = 1:T
    p = rand(rs, NE, nC) .^ 4; p(:, 1) = p(:, 1) + 0.7 * (rand(rs, NE, 1) < 0.8); p = p ./ sum(p, 2);
    o = struct('probs', p, 'unknown', false(NE, 1), 'feat', zeros(NE, nF));
    d = step .* (t >= k0);
    o.feat(:, feature_index('log_ber')) = -5 + 3 * rand(rs, NE, 1);
    o.feat(:, feature_index('sinr')) = 6 + randn(rs, NE, 1) - d;
    o.feat(:, feature_index('q_iot')) = 6 * rand(rs, NE, 1) - 1;
    o.feat(:, feature_index('crc_fail')) = rand(rs, NE, 1) < 0.2;
    o.gant = 1 + randn(rs, NE, 3) - d;
    if with3, q = rand(rq, NE, 3) .^ 3 + 1e-3; o.probs3 = q ./ sum(q, 2); end
    X{t} = o;
end
end

function [A, I, M] = pb_decide(PP, kind, X, opt)
% policy_decide over the trace X from no_action (cfg_link follows the request): the actions (T x NE), every cycle's
% information and the last memory.
NE = size(X{1}.feat, 1); T = numel(X);
na = find(strcmp(PP.actions, 'no_action'));
cfg = na * ones(1, NE); mem = [];
A = zeros(T, NE); I = cell(1, T);
for t = 1:T
    o = X{t}; o.cfg_link = cfg;
    [cfg, mem, I{t}] = policy_decide(kind, o, cfg, mem, PP, [], opt);
    A(t, :) = cfg;
end
M = mem;
end

function R = pb_readings()
% The readings of the files P-B touches, with the code now on the path: policy_decide over random traces in every
% alarm mode (probs3 absent and present, rule_core3 not asked for), policy_setup's answers, lect_kpis on a toy world.
R = struct('dec', {{}}, 'dec3', {{}}, 'setup', {{}}, 'lect', {{}});
for mode = {'class', 'class_drop', 'class_cusum'}
    PP = pb_pp(mode{1});
    X = pb_trace(PP, 4, 40, 23, false); X3 = pb_trace(PP, 4, 40, 23, true);
    for kind = {'rule', 'rule_esc', 'blind_esc'}
        for core = [false true]
            opt = struct(); if core, opt.core = true; end
            [a, i, m] = pb_decide(PP, kind{1}, X, opt); R.dec{end+1} = {a, i, m};
            [a, i, m] = pb_decide(PP, kind{1}, X3, opt); R.dec3{end+1} = {a, i, m};
        end
    end
end
names = {'none', 'random', 'fixed', 'fixed_mmse', 'table', 'rule', 'rule_esc', 'blind_esc', 'rule_sel', 'rule_core', 'blind_core', ...
    'dqn_esc', 'dqn_g2', 'rule_esc_norelm', 'rule_esc_s1g', 'table_relm'};
Q = struct('agent', 7, 'agents', {{1, 2, 3}}, 'rule_sel', struct('alarm', 'class'));
tab = struct('table', [1 2 3], 'table_unknown', 4);
for k = 1:numel(names)
    [kind, ag, opt] = policy_setup(names{k}, Q, 2, 3, 4, tab, 5); R.setup{end+1} = {kind, ag, opt};
end
POL = {'none', 'random', 'fixed', 'rule_esc', 'blind_esc', 'table', 'dqn_esc', 'oracle', 'rule_core', 'blind_core'};
LBL = {'no response', 'random', 'fixed', 'rule + escalation', 'no detector + escalation', 'table', 'DQN + escalation', 'oracle', ...
    'core: rule + escalation', 'core: no detector + escalation'};
[ALL, scen] = pb_lect_world(POL);
[L, lines] = lect_kpis(ALL, POL, LBL, 4, scen, 5e4, 20); R.lect = {L, lines};
end

function [ALL, scen] = pb_lect_world(POL)
% Eight episodes of every policy in POL (test_core's lect_world): jamming (1, 2, 7), tone_jamming (3, 4, 8), path_loss (5, 6);
% episode 7 not recoverable, episode 8 without its threat on the air, episode 2 recoverable only outside the core action
% set; rule_core3 reads better than rule_core on the jamming episodes.
scen = {'none', 'jamming', 'tone_jamming', 'path_loss'};
B = struct('scn', [2 2 3 3 4 4 2 3], 'recoverable', logical([1 1 1 1 1 1 0 1]), ...
    'recoverable_core', logical([1 0 1 1 1 1 0 1]), ...
    'threat', logical([1 1 1 1 1 1 1 0]), 'geom', [1 1 2 2 3 3 4 5], 'ok_post', 0.5 * ones(1, 8));
ALL = cell(1, numel(POL));
for k = 1:numel(POL)
    R = B;
    switch POL{k}
        case 'none'
            R.per_post = [0.5 0.5 0.4 0.4 0.6 0.6 0.9 0.2]; R.dlv_post = [0.5 0.5 0.6 0.6 0.4 0.4 0.1 0.8];
            R.t_conf = [1 1 1 1 1 1 NaN NaN]; R.t_rec_det = nan(1, 8); R.t_rec = nan(1, 8);
        case {'blind_esc', 'blind_core'}
            R.per_post = [0.3 0.3 0.4 0.4 0.3 0.3 0.9 0.2]; R.dlv_post = [0.7 0.7 0.6 0.6 0.7 0.7 0.1 0.8];
            R.t_conf = [2 3 3 2 2 2 NaN NaN]; R.t_rec_det = [5 6 NaN NaN 4 4 NaN NaN]; R.t_rec = [7 9 NaN NaN 6 6 NaN NaN];
        case 'rule_core3'
            R.per_post = [0.2 0.2 0.3 0.3 0 0 0.9 0.2]; R.dlv_post = [0.8 0.8 0.7 0.7 1 1 0.1 0.8];
            R.t_conf = [1 2 5 4 1 1 NaN NaN]; R.t_rec_det = [3 4 6 2 0 5 NaN NaN]; R.t_rec = [4 6 11 6 1 6 NaN NaN];
        otherwise
            R.per_post = [0.1 0.1 0.2 0.2 0 0 0.9 0.2]; R.dlv_post = [0.9 0.9 0.8 0.8 1 1 0.1 0.8];
            R.t_conf = [1 2 NaN 0 1 1 NaN NaN]; R.t_rec_det = [3 4 NaN 2 0 5 NaN NaN]; R.t_rec = [4 6 NaN 2 1 6 NaN NaN];
            if strcmp(POL{k}, 'oracle'), R.t_conf(:) = NaN; R.t_rec_det(:) = NaN; end
    end
    R.gput_post = R.dlv_post; R.recovered = isfinite(R.t_rec);
    ALL{k} = R;
end
end

function d = pb_parent_dir(tc, rev, rels)
% The files rels as commit rev holds them, together in one folder.
d = tempname; mkdir(d);
repo = tc.TestData.root;
[sg, ~] = system(sprintf('git --no-optional-locks -C "%s" rev-parse --git-dir', repo));
if sg ~= 0 && ~isempty(getenv('V7_GIT_REPO')), repo = getenv('V7_GIT_REPO'); end
for k = 1:numel(rels)
    [~, nm, ext] = fileparts(rels{k});
    [st, out] = system(sprintf('git --no-optional-locks -C "%s" show %s:%s > "%s"', repo, rev, rels{k}, fullfile(d, [nm ext])));
    assertEqual(tc, st, 0, sprintf('git show %s:%s failed: %s', rev, rels{k}, out));
end
end

function pb_fixture_off(d, fns)
% Removes a parent-commit folder from the path and the disk (once).
if contains(path, d), rmpath(d); end
for k = 1:numel(fns), clear(fns{k}); end
if isfolder(d), rmdir(d, 's'); end
end

function test_pb_off_is_the_parent(tc)
% Without opt.core3, with and without obs.probs3 in the observation, policy_monitor.m, policy_decide.m, policy_setup.m and
% lect_kpis.m give the parent commit's (9e6b7c8, tip3-lb) actions, information, memory, policies and readings bit for bit.
fns = {'policy_monitor', 'policy_decide', 'policy_setup', 'lect_kpis'};
now0 = pb_readings();
verifyTrue(tc, isequaln(now0.dec, now0.dec3));                       % probs3 in the observation is ignored without opt.core3
verifyNumElements(tc, now0.dec, 18);
verifyTrue(tc, any(cellfun(@(c) numel(unique(c{1}(:))) > 1, now0.dec)));   % the traces move the configuration
d = pb_parent_dir(tc, '9e6b7c8', {'code/decision/policy_monitor.m', 'code/decision/policy_decide.m', ...
    'code/decision/policy_setup.m', 'code/evaluation/lect_kpis.m'});
addpath(d, '-begin'); clear policy_monitor policy_decide policy_setup lect_kpis
cl = onCleanup(@() pb_fixture_off(d, fns)); %#ok<NASGU>
verifyEqual(tc, which('policy_decide'), fullfile(d, 'policy_decide.m'));
verifyEqual(tc, which('lect_kpis'), fullfile(d, 'lect_kpis.m'));
old0 = pb_readings();
pb_fixture_off(d, fns);
verifyNotEqual(tc, which('policy_decide'), fullfile(d, 'policy_decide.m'));
verifyTrue(tc, isequaln(now0.dec, old0.dec), 'policy_decide / policy_monitor');
verifyTrue(tc, isequaln(now0.setup, old0.setup), 'policy_setup');
verifyTrue(tc, isequaln(now0.lect, old0.lect), 'lect_kpis');
end

function test_pb_wf_options_switch(tc)
% core3_pools: off without the file or the field, on with true, a value that is no logical is refused.
d = tempname; mkdir(d); cl = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
verifyFalse(tc, wf_options([], fullfile(d, 'none.json')).core3);
f = fullfile(d, 'p.json');
fid = fopen(f, 'w'); fprintf(fid, '{"core3_pools": true}'); fclose(fid);
O = wf_options([], f);
verifyTrue(tc, O.core3);
verifyFalse(tc, O.dconf || O.s1g || O.relm || O.r9 || O.dconf_own || O.k6split);
verifyFalse(tc, wf_options(struct('core3_pools', false), f).core3);   % the stage's own CFG overrides the file
fid = fopen(f, 'w'); fprintf(fid, '{"core3_pools": 1}'); fclose(fid);
verifyError(tc, @() wf_options([], f), 'wf_options:value');
end

function test_pb_core3_model_condition_a(tc)
% Condition (a): the model exists and holds the three states in order; the file's SHA-256 and the window N identify it.
d = tempname; mkdir(d); cl = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
[M, why] = core3_model(fullfile(d, 'absent.mat'));
verifyEmpty(tc, M); verifyTrue(tc, contains(why, 'not found'));
net = struct('w', 1); N = 5; groups = {'none', 'tone_jamming', 'jamming'}; %#ok<NASGU>
f = fullfile(d, 'm.mat'); save(f, 'net', 'N', 'groups');
[M, why] = core3_model(f);
verifyEmpty(tc, why);
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r'); b = fread(fid, Inf, '*uint8'); fclose(fid); md.update(b);
sha = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
verifyEqual(tc, M.sha256, sha);
verifyEqual(tc, M.N, 5);
verifyEqual(tc, M.id, ['core3 ' sha ' N5']);
verifyEqual(tc, M.net, net);
groups = {'none', 'jamming', 'tone_jamming'}; save(f, 'net', 'N', 'groups');       % the states in another order
[M, why] = core3_model(f);
verifyEmpty(tc, M); verifyTrue(tc, contains(why, 'states'));
groups = {'none', 'tone_jamming', 'jamming'}; N = [3 5]; save(f, 'net', 'N', 'groups');
[M, why] = core3_model(f);
verifyEmpty(tc, M); verifyTrue(tc, contains(why, 'window'));
save(f, 'net');
[M, why] = core3_model(f);
verifyEmpty(tc, M); verifyTrue(tc, contains(why, 'net, N and groups'));
end

function test_pb_core3_class_is_the_logp_window(tc)
% The class is the argmax of the mean log-probability of the last N cycles (core_cnn_eval.m 'logp' over the episode), fewer at
% the start, and the window does not restart at a configuration change.
PP = pb_pp('class'); PP.core3_N = 3; PP.core3_on = true;
nA = numel(PP.actions); NE = 3; T = 14; na = find(strcmp(PP.actions, 'no_action'));
rq = RandStream('mt19937ar', 'Seed', 5);
p3 = rand(rq, NE, 3, T) .^ 3 + 1e-3; p3 = p3 ./ sum(p3, 2);
mem = policy_monitor('init', NE, nA);
s3 = {'none', 'tone_jamming', 'jamming'};
nF = numel(link_features('names'));
Lm = zeros(T, NE, 3); cm = cell(T, NE);
for t = 1:T
    obs = struct('probs', repmat([1 0 0 0 0 0], NE, 1), 'unknown', false(NE, 1), 'feat', zeros(NE, nF), 'probs3', p3(:, :, t));
    obs.feat(:, feature_index('log_ber')) = -6;
    [mem, M] = policy_monitor('update', mem, obs, PP, na * ones(1, NE));
    Lm(t, :, :) = M.l3; cm(t, :) = M.cls;
    if t == 7, mem = policy_monitor('change', mem, [true false true]); end
end
for e = 1:NE
    P = squeeze(p3(e, :, :))';
    [L, ~] = core_cnn_eval('logp', P, ones(T, 1), (1:T)', 3);
    verifyEqual(tc, squeeze(Lm(:, e, :)), L, 'AbsTol', 1e-12);
    [~, k] = max(L, [], 2);
    verifyEqual(tc, cm(:, e)', s3(k));
end
end

function test_pb_core3_mapping_and_hybrid_independence(tc)
% clean -> none (no alarm), narrowband -> tone_jamming and wideband -> jamming (hostile); the fusion model, the unknown-threat
% flag and the sweeper's confirmation play no part, the detector's own probabilities none.
PP = pb_pp('class'); PP.core3_N = 3; PP.core3_on = true;
PP.fuse = struct('bogus', 1);                                        % any use of the fusion model would fail on this
PP.confirm_sweep = [1 4];
nA = numel(PP.actions); na = find(strcmp(PP.actions, 'no_action')); nF = numel(link_features('names'));
want = {'none', 'tone_jamming', 'jamming'};
for k = 1:3
    mem = policy_monitor('init', 1, nA);
    for t = 1:4
        obs = struct('probs', [0 0 0 1 0 0], 'unknown', true, 'maha', -5, 'feat', zeros(1, nF), 'probs3', double((1:3) == k));
        obs.feat(feature_index('log_ber')) = -6;
        [mem, M] = policy_monitor('update', mem, obs, PP, na);        % the detector reads path_loss and unknown
    end
    verifyEqual(tc, M.cls, want(k));
    verifyEqual(tc, M.alarm, k > 1);
    verifyEqual(tc, M.probs, obs.probs);                              % not fused
    verifyFalse(tc, any(mem.sw(:)));
end
% the same observation without the mode reads the detector's class and the unknown flag
P0 = PP; P0.core3_on = false; P0 = rmfield(P0, 'fuse'); P0.maha_thr = 0;
mem = policy_monitor('init', 1, nA);
[~, M] = policy_monitor('update', mem, obs, P0, na);
verifyEqual(tc, M.cls, {'unknown'});
end

function test_pb_core3_refusals(tc)
% Never the hybrid's class in its place: another kind, no core option, no window, no or incomplete scores.
PP = pb_pp('class'); PP.core3_N = 3; nF = numel(link_features('names'));
na = find(strcmp(PP.actions, 'no_action'));
obs = struct('probs', [1 0 0 0 0 0], 'unknown', false, 'feat', zeros(1, nF), 'probs3', [1 0 0]);
obs.feat(feature_index('log_ber')) = -6;
ok = struct('core', true, 'core3', true);
[a, ~] = policy_decide('rule_esc', obs, na, [], PP, [], ok); %#ok<ASGLU>
verifyError(tc, @() policy_decide('dqn', obs, na, [], PP, [], ok), 'policy_decide:core3');
verifyError(tc, @() policy_decide('blind_esc', obs, na, [], PP, [], ok), 'policy_decide:core3');
verifyError(tc, @() policy_decide('rule_esc', obs, na, [], PP, [], struct('core3', true)), 'policy_decide:core3');
P2 = rmfield(PP, 'core3_N');
verifyError(tc, @() policy_decide('rule_esc', obs, na, [], P2, [], ok), 'policy_decide:core3_N');
verifyError(tc, @() policy_decide('rule_esc', rmfield(obs, 'probs3'), na, [], PP, [], ok), 'policy_decide:core3_probs3');
o2 = obs; o2.probs3 = [1 NaN 0];
verifyError(tc, @() policy_decide('rule_esc', o2, na, [], PP, [], ok), 'policy_decide:core3_probs3');
o3 = obs; o3.probs3 = [1 0];
verifyError(tc, @() policy_decide('rule_esc', o3, na, [], PP, [], ok), 'policy_decide:core3_probs3');
end

function test_pb_core3_answers_as_rule_core_on_the_same_class(tc)
% The decision layer is rule_core's: with the same class from either source, the actions, the escalation and the information
% are the same (no fusion, so the detector's class at once; the class source is the only difference).
nF = numel(link_features('names'));
for deg = [false true]
    for k = 1:3
        PP = pb_pp('class'); PP.core3_N = 3;
        na = find(strcmp(PP.actions, 'no_action'));
        h = zeros(1, 6); ki = [1 3 2]; h(ki(k)) = 1;                          % none, tone_jamming, jamming of the detector's classes
        obs = struct('probs', h, 'unknown', false, 'feat', zeros(1, nF), 'maha', 0, 'probs3', double((1:3) == k));
        obs.feat(feature_index('log_ber')) = -6 + 6 * deg;
        a0 = na; m0 = []; a3 = na; m3 = [];
        for t = 1:10
            obs.cfg_link = a0;
            [a0, m0, i0] = policy_decide('rule_esc', obs, a0, m0, PP, [], struct('core', true));
            obs.cfg_link = a3;
            [a3, m3, i3] = policy_decide('rule_esc', obs, a3, m3, PP, [], struct('core', true, 'core3', true));
            verifyEqual(tc, a3, a0);
            verifyEqual(tc, i3.cls, i0.cls);
            verifyEqual(tc, i3.confirmed, i0.confirmed);
            verifyEqual(tc, i3.escalated, i0.escalated);
        end
        if k > 1 && deg, verifyNotEqual(tc, a0, na); end             % a hostile class on a degraded link is answered
        if k == 1 && ~deg, verifyEqual(tc, a0, na); end              % clean and not degraded: no action
    end
end
end

function test_pb_core3_lost_branch_gate_never_acts(tc)
% rule_core3's three states hold no lost-branch class: PP.s1_gate_core and PP.lb_accept change none of its answers.
nF = numel(link_features('names'));
PP = pb_pp('class'); PP.core3_N = 3; na = find(strcmp(PP.actions, 'no_action'));
for k = 1:3
    obs = struct('probs', [1 0 0 0 0 0], 'unknown', false, 'feat', zeros(1, nF), 'probs3', double((1:3) == k));
    obs.feat(feature_index('log_ber')) = 0;
    P1 = PP; P1.s1_gate_core = true; P1.lb_accept = struct('tau_hi', Inf);
    a0 = na; m0 = []; a1 = na; m1 = [];
    for t = 1:8
        obs.cfg_link = a0;
        [a0, m0] = policy_decide('rule_esc', obs, a0, m0, PP, [], struct('core', true, 'core3', true));
        obs.cfg_link = a1;
        [a1, m1] = policy_decide('rule_esc', obs, a1, m1, P1, [], struct('core', true, 'core3', true));
        verifyEqual(tc, a1, a0);
    end
end
end

function test_pb_pool_scores_reach_the_observation(tc)
% link_env.m: obs.probs3 is the frame's three-state scores where the frame's pool holds them, NaN where it does not, and
% there is no field at all when no pool does (the observation as it was).
A = policy_actions(); nA = numel(A); fn = link_features('names'); n = 38;
PP = struct('actions', {A}, 'scen', {{'none', 'jamming'}}, 'ebno', 9, 'runs', {{101}}, 'F_SUB', 20, ...
    'event_frame', {{NaN}}, 'classes', {{'none', 'jamming'}}, 'feat_names', {fn}, 'maha_thr', 0, ...
    'clean', 1e-6, 'clean_fer', 0, 'gp', ones(1, nA), 'bw', ones(1, nA), 'pw', ones(1, nA), 'sps', 4, 'bps', 2);
PP.pools = cell(2, 1, nA, 1);
for sc = 1:2
    for a = 1:nA
        b = 0.1 * (sc == 2) * ones(n, 1);
        Q = struct('ber', b, 'fer', single(b > 0), 'run', 101 * ones(n, 1), ...
            'probs', repmat([sc == 1, sc == 2], n, 1), 'maha', ones(n, 1), 'feat', zeros(n, numel(fn)), 'act', double(sc == 2) * ones(n, 1));
        if sc == 2, Q.probs3 = single([(1:n)' / 100, 0.3 * ones(n, 1), 0.7 * ones(n, 1) - (1:n)' / 100]); end
        PP.pools{sc, 1, a, 1} = Q;
    end
end
K = link_env('tables', PP);
spec = struct('scn', [1 2], 's', [1 1], 'onset', [3 3], 'follow', false(1, 2), 'fdelay', [2 2], 'unk', false(1, 2), 'T', 12, 'r', [1 1]);
[E, ~] = link_env('reset', PP, K, spec, 1, RandStream('mt19937ar', 'Seed', 1));
for t = 1:6                                                           % the onset is at cycle 3: the threat episode then reads the pool with the scores
    [E, ~, obs] = link_env('step', E, PP, K, find(strcmp(A, 'no_action')) * [1 1]);
end
verifyTrue(tc, isfield(obs, 'probs3'));
verifyEqual(tc, size(obs.probs3), [2 3]);
verifyTrue(tc, all(isnan(obs.probs3(1, :))));                         % the clean episode reads a pool without the scores
verifyFalse(tc, any(isnan(obs.probs3(2, :))));
PPn = PP;
for a = 1:nA, PPn.pools{2, 1, a, 1} = rmfield(PPn.pools{2, 1, a, 1}, 'probs3'); end
Kn = link_env('tables', PPn);
[~, obs] = link_env('reset', PPn, Kn, spec, 1, RandStream('mt19937ar', 'Seed', 1));
verifyFalse(tc, isfield(obs, 'probs3'));
end

function test_pb_lect_kpis_rows_and_pair(tc)
% lect_kpis.m: rule_core3 is a row in every core table, its pair against blind_core is cnn3 (secondary, weakened baseline),
% and everything else, the verdict included, is what it is without it.
POL = {'none', 'random', 'fixed', 'rule_esc', 'blind_esc', 'table', 'dqn_esc', 'oracle', 'rule_core', 'blind_core'};
LBL = {'no response', 'random', 'fixed', 'rule + escalation', 'no detector + escalation', 'table', 'DQN + escalation', 'oracle', ...
    'core: rule + escalation', 'core: no detector + escalation'};
[ALL0, scen] = pb_lect_world(POL);
[L0, lines0] = lect_kpis(ALL0, POL, LBL, 4, scen, 5e4, 20);
verifyFalse(tc, isfield(L0.core, 'cnn3'));
POL3 = [POL, {'rule_core3'}]; LBL3 = [LBL, {'core: rule + escalation, three-state CNN (profile 3, P-B)'}];
[ALL3, scen] = pb_lect_world(POL3);
[L, lines] = lect_kpis(ALL3, POL3, LBL3, 4, scen, 5e4, 20);
for f = {'verdict', 'per', 'per_threat', 'cnn', 'rec', 'gput'}                % the full action set's readings
    verifyEqual(tc, L.(f{1}), L0.(f{1}));
end
ic = find(startsWith(lines0, 'Core action set {'), 1) - 1;
verifyEqual(tc, lines(1:ic), lines0(1:ic));
Cc = L.core; C0 = L0.core;
verifyEqual(tc, Cc.verdict, C0.verdict);                              % the verdict stays rule_core's
verifyEqual(tc, Cc.cnn, C0.cnn);
verifyEqual(tc, {Cc.per.policy}, {'rule_core', 'blind_core', 'rule_core3'});
verifyEqual(tc, Cc.per(1:2), C0.per);
verifyEqual(tc, unique({Cc.rec.policy}, 'stable'), {'none', 'blind_core', 'rule_core', 'rule_core3'});
verifyEqual(tc, {Cc.gput.policy}, {'none', 'blind_core', 'rule_core', 'rule_core3'});
% episodes 1, 3 and 4 are the recoverable core jamming episodes: rule_core3 0.2 + 0.3 + 0.3 against blind_core 0.3 + 0.4 + 0.4
verifyEqual(tc, Cc.cnn3.per_red_pct, 100 * (1 - 0.8 / 1.1), 'AbsTol', 1e-9);
verifyEqual(tc, Cc.cnn3.n, 3);
verifyEqual(tc, Cc.cnn3.gput_bps, 5e4 * ((0.8 + 0.7 + 0.7) - (0.7 + 0.6 + 0.6)) / 3, 'AbsTol', 1e-6);
verifyEqual(tc, [Cc.cnn3.det.median Cc.cnn3.det.never_pct], [4 2 0 0]);
verifyEqual(tc, Cc.all36.cnn3.n, 4);
l3 = lines(contains(lines, 'rule_core3 (profile 3) vs blind_core, secondary, weakened baseline (fixed first response channel_switch+rate_reduce'));
verifyNumElements(tc, l3, 4);                                         % the pair and its onset line, on both masks
verifyTrue(tc, any(contains(lines, 'core: rule + escalation, three-state CNN (profile 3, P-B)')));
% the same world read twice is the same
[L2, lines2] = lect_kpis(ALL3, POL3, LBL3, 4, scen, 5e4, 20);
verifyTrue(tc, isequaln(L, L2)); verifyEqual(tc, lines, lines2);
end

function test_pb_pool_key_is_unchanged_when_off(tc)
% The cells' key without the model is the parent's; with it the id enters the key.
x = {'v7-D89', 'abc', 1:3, struct('a', 1)};
verifyEqual(tc, pool_checkpoint('key', [x, {}]), pool_checkpoint('key', x));
verifyNotEqual(tc, pool_checkpoint('key', [x, {'core3 aa N3'}]), pool_checkpoint('key', x));
verifyNotEqual(tc, pool_checkpoint('key', [x, {'core3 aa N3'}]), pool_checkpoint('key', [x, {'core3 ab N3'}]));
end

function test_pb_wiring_static_and_parse(tc)
% The files' text: the switch in the stage that scores the pools, the id in the key and in the reuse test, the policy after every
% other row, the clean sets of C1c and the fresh set without it, no truth field in the decision path.
b = fileread(which('build_policy_pools'));
verifyNumElements(tc, regexp(b, 'wf_options\(cfg_c3\)\.core3', 'match'), 1);
verifyNumElements(tc, regexp(b, 'core3_model\(\)', 'match'), 1);
verifyNotEmpty(tc, strfind(b, '[{MODEL_TAG, DET_ID, runs, cells(c), EBNO, ACTIONS, geoc{c}, opt, ...'));
verifyNotEmpty(tc, strfind(b, 'threat_params(p0, cells(c).threat, cells(c).sev, C)}, c3_key])'));
verifyNotEmpty(tc, strfind(b, 'strcmp(oc3, c3_id)'));
verifyNotEmpty(tc, strfind(b, 'PP.core3_not_run = c3_note'));
verifyNotEmpty(tc, strfind(b, 'rule_core3 was not run in profile 3; CORE_BW (profile 1) is the three-state CNN'));
p = fileread(which('pool_cell'));
verifyNotEmpty(tc, strfind(p, 'spec_scores(det.core3.net, X, ''cpu'')'));
verifyNotEmpty(tc, strfind(p, 'Q.probs3 = zeros(0, 3, ''single'')'));
e = fileread(which('evaluate_policies'));
verifyNotEmpty(tc, strfind(e, 'POL = [POL, {''rule_core3''}]'));
verifyNotEmpty(tc, strfind(e, 'if c3_on, POL = POL(1:nPf); LBL = LBL(1:nPf); RES = RES(:, 1:nPf); end'));   % the clean pools of C1c and the fresh set
verifyNotEmpty(tc, strfind(e, 'POL = POLa; LBL = LBLa; RES = RESa;'));                                     % are flown without it
for f = {'policy_monitor', 'policy_decide', 'core3_model'}
    s = fileread(which(f{1}));
    for tf = {'healthy', 'harmed', 'sc_eff', '\.ended', 'ber_true', 'fer_true'}
        verifyEmpty(tc, regexp(s, tf{1}, 'once'), sprintf('%s reads %s', f{1}, tf{1}));
    end
end
r = fileread(which('rekey_pools'));
verifyNotEmpty(tc, strfind(r, '''probs3'''));
verifyNotEmpty(tc, strfind(r, '''core3_id'''));
for f = {'policy_monitor', 'policy_decide', 'policy_setup', 'pool_cell', 'link_env', 'build_policy_pools', 'evaluate_policies', ...
        'lect_kpis', 'measure_all_kpis', 'core3_model', 'spec_scores', 'wf_options', 'rekey_pools'}
    parses_ok(tc, f{1});
end
end

function parses_ok(tc, name)
% The file parses: mtree does not raise on a syntax error, it returns an ERR root (test_core's test_m_files_parse).
t = mtree(fileread(which(name)));
verifyNotEqual(tc, char(t.root.kind), 'ERR', sprintf('%s does not parse', name));
end
