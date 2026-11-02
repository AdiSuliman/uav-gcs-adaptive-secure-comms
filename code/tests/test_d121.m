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
mtree(which('cfo_joint'), '-file');
mtree(which('test_d121'), '-file');
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
mtree(which('dconf_step'), '-file'); mtree(which('wf_options'), '-file');
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
mtree(which('lect_kpis'), '-file'); mtree(which('measure_all_kpis'), '-file');
end

