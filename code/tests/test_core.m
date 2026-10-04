function tests = test_core
%TEST_CORE  Unit tests of the core functions. Run from the repository root:
%   results = runtests('code/tests')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
% Work in a temporary folder with its own Simulink cache, so the tests never
% touch the repository's params.mat or compiled model code.
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.cwd = pwd;
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp); cd(tc.TestData.tmp);
tc.TestData.cfg = Simulink.fileGenControl('getConfig');
Simulink.fileGenControl('set', 'CacheFolder', tc.TestData.tmp, 'CodeGenFolder', tc.TestData.tmp);
end

function teardownOnce(tc)
Simulink.fileGenControl('setConfig', 'config', tc.TestData.cfg);
cd(tc.TestData.cwd);
end

%% ---------- code ----------
function test_m_files_parse(tc)
% Every .m file of the code (legacy excepted) parses, so no stage stops on a syntax
% error in a file the other tests never reach.
f = dir(fullfile(tc.TestData.root, 'code', '**', '*.m'));
f = f(~contains({f.folder}, [filesep 'legacy']));
bad = {};
for i = 1:numel(f)
    t = mtree(fileread(fullfile(f(i).folder, f(i).name)));
    if strcmp(t.root.kind, 'ERR'), bad{end+1} = f(i).name; end %#ok<AGROW>
end
verifyGreaterThan(tc, numel(f), 50);
verifyEmpty(tc, bad, strjoin(bad, ', '));
end

%% ---------- configurations and countermeasures ----------
function test_actions_one_per_domain(tc)
A = policy_actions();
verifyEqual(tc, numel(A), 36);
verifyEqual(tc, numel(unique(A)), 36);
verifyTrue(tc, any(strcmp(A, 'no_action')));
verifyTrue(tc, any(strcmp(A, 'channel_switch+spatial_diversity+rate_reduce+power_control')));
verifyFalse(tc, any(contains(A, 'channel_switch') & contains(A, 'freq_diversity')));
end

function test_countermeasure_gains(tc)
p = base_params();
[~, g] = apply_countermeasure(p, 'path_loss', 'rate_reduce+power_control');
verifyEqual(tc, g, 10*log10(p.cm_rate_factor) + power_step_db(p), 'AbsTol', 1e-9);
% the power step never takes the GCS above the e.i.r.p. cap
verifyLessThanOrEqual(tc, p.gcs_pt_dbm + p.gcs_ant_dbi + power_step_db(p), p.gcs_eirp_cap_dbm + 1e-9);
verifyEqual(tc, power_step_db(rmfield(p, 'gcs_ant_dbi')), ...
    floor((p.gcs_pmax_dbm - p.gcs_papr_db - p.gcs_pt_dbm) / p.gcs_step_db) * p.gcs_step_db, 'AbsTol', 1e-12);   % the radio's own limit
p2 = apply_countermeasure(p, 'sweeping_jammer', 'freq_diversity+power_control');
verifyTrue(tc, p2.sweep_fdiv);
verifyEqual(tc, p2.jsr_db, p.jsr_db - power_step_db(p), 'AbsTol', 1e-9);
p2 = apply_countermeasure(p, 'sweeping_jammer', 'channel_switch');
verifyFalse(tc, isfield(p2, 'sweep_fdiv'));
[p2, ~, cm] = apply_countermeasure(p, 'jamming', 'channel_switch+spatial_diversity');
verifyEqual(tc, p2.jsr_db, p.jsr_db - p.cm_acr_db, 'AbsTol', 1e-9);
verifyEqual(tc, p2.rx_combiner, 'mmse');
verifyEqual(tc, cm.goodput_factor, 1);
[~, ~, cm] = apply_countermeasure(p, 'none', 'freq_diversity+power_control+fec_interleave');
verifyEqual(tc, cm.goodput_factor, p.cm_fec_rate, 'AbsTol', 1e-12);
verifyEqual(tc, cm.bw_factor, 2);
end

function test_rule_policy(tc)
verifyEqual(tc, rule_based_policy('path_loss'), 'rate_reduce+power_control');
verifyEqual(tc, rule_based_policy('jamming', false, 0), 'channel_switch');
verifyEqual(tc, rule_based_policy('jamming', false, 10), 'channel_switch+spatial_diversity');
verifyEqual(tc, rule_based_policy('none', false, 0), 'no_action');
verifyEqual(tc, rule_based_policy('none', true, 0), 'freq_diversity+power_control');
A = policy_actions(); C = decision_config();
verifyTrue(tc, all(ismember(C.ladder, A)));
for c = {'jamming', 'reactive_jamming', 'spoofing', 'sweeping_jammer', 'noise_burst', 'path_loss', ...
         'antenna_fault', 'benign_interference', 'none', 'unknown'}
    for deg = [false true]
        for gdb = [0 10]
            verifyTrue(tc, ismember(rule_based_policy(c{1}, deg, gdb), A));
        end
    end
end
end

function test_shield(tc)
m = policy_mask([3 5], [false true], [10 10], 36, 1);
verifyEqual(tc, size(m), [36 2]);
verifyEqual(tc, find(m(:, 1))', [1 3]);            % no confirmed alarm: keep or release only
verifyTrue(tc, all(m(:, 2)));                        % confirmed alarm: everything allowed
C = decision_config();
m = policy_mask([3 5 7], [true true false], [C.hold - 1, C.hold, 0], 36, 1);
verifyEqual(tc, find(m(:, 1))', 3);                 % within the hold: keep only, even with an alarm
verifyTrue(tc, all(m(:, 2)));                        % hold over
verifyEqual(tc, find(m(:, 3))', 7);
end

%% ---------- signalling delay, follower and comb jammers ----------
function test_follower_rehop_delay(tc)
% A policy that holds channel_switch against a follower: the request needs D frames,
% then fdelay good frames and D + 1 jammed ones per re-acquisition (the re-hop is asked
% on the first failed CRC, the link stays on the jammed channel until it arrives, no
% second hop while one is on its way); none at fdelay 0; at fdelay 5 the first run is
% exactly 5, so only fdelay >= 5 "recovers" by hopping alone. A re-hop is a change at
% the switch cost, and a jammed frame that passes its CRC asks for none.
[PP, K] = toy_world(true);
cs = find(strcmp(PP.actions, 'channel_switch')); T = 24;
for D = [1 2]
    for f = [0 3 4 5]
        [ok, ch] = hold_config(PP, K, cs, f, D, T);
        t = 1:T; u = mod(t - D - 1, f + D + 1);
        verifyEqual(tc, ok, t > D & u < f, sprintf('D %d, fdelay %d', D, f));
        verifyEqual(tc, find(ch(D+2:end)) + D, find(t > D & t < T & u == f), sprintf('re-hops D %d, fdelay %d', D, f));
    end
end
ok = hold_config(PP, K, cs, 5, 1, T);
verifyEqual(tc, find(~ok(2:end), 1) - 1, 5);                     % first run of good frames
spec = struct('scn', [2 2], 's', [1 1], 'onset', [1 1], 'follow', [true true], 'fdelay', [4 5], 'unk', [false false], ...
    'T', 20, 'r', [1 1], 'delay', 1);
R = rollout_policy('fixed', PP, K, spec, 1, [], struct('fixed', cs), 3);
verifyEqual(tc, R.recovered, [false true]);
R = rollout_policy('oracle', PP, K, spec, 1, [], [], 3);         % the oracle runs on the same hop rule
verifyEqual(tc, size(R.ok_post), [1 2]);
[PP0, K0] = toy_world(false);                                   % jammed frames pass their CRC
verifyEqual(tc, find(hold_config(PP0, K0, cs, 3, 1, T)), 2:4);
end

function test_held_recovery(tc)
% Held recovery: restored for 5 cycles and on every cycle to the end, but one follower
% re-acquisition of 1 + D cycles. Holding channel_switch against a follower at fdelay 5
% holds through one re-acquisition and not through two; the lost packets and frames
% count from the start of the recovery run.
[PP, K] = toy_world(true);
cs = find(strcmp(PP.actions, 'channel_switch'));
for D = [1 2]
    for T = [7 + 2 * D, 24]
        spec = struct('scn', 2, 's', 1, 'onset', 1, 'follow', true, 'fdelay', 5, 'unk', false, 'T', T, 'r', 1, 'delay', D);
        R = rollout_policy('fixed', PP, K, spec, 1, [], struct('fixed', cs), 3);
        verifyEqual(tc, [R.recovered, R.held], [true, T < 24], sprintf('D %d, T %d', D, T));
        ok = hold_config(PP, K, cs, 5, D, T);
        verifyEqual(tc, [R.lost_rec, R.n_rec], [sum(~ok(D+1:end)), T - D], sprintf('lost, D %d, T %d', D, T));
    end
end
spec = struct('scn', 2, 's', 1, 'onset', 1, 'follow', false, 'fdelay', 0, 'unk', false, 'T', 12, 'r', 1, 'delay', 1);
R = rollout_policy('fixed', PP, K, spec, 1, [], struct('fixed', cs), 3);
verifyEqual(tc, [R.recovered, R.held, R.lost_rec, R.n_rec], [1 1 0 11]);     % a static jammer: held, no loss
% the allowance is a follower's re-acquisition: the same run of 1 + D bad cycles under a
% comb jammer (on every channel from the onset, nothing to re-acquire) is not held
spec = struct('scn', 2, 's', 1, 'onset', 1, 'follow', true, 'fdelay', 5, 'unk', false, 'T', 9, 'r', 1, 'delay', 1);
R = rollout_policy('fixed', PP, K, spec, 1, [], struct('fixed', cs), 3);
spec.comb = true;
Rc = rollout_policy('fixed', PP, K, spec, 1, [], struct('fixed', cs), 3);
verifyEqual(tc, [R.recovered, R.held, Rc.recovered, Rc.held], [true true true false]);
verifyEqual(tc, [Rc.lost_rec, Rc.n_rec], [R.lost_rec, R.n_rec]);
end

function test_oracle_timing(tc)
% The one-step oracle scores the frame its choice reaches the link on (t + 1 + D), with
% the channel in use after a hop on its way (its arrival frame) and link_env.m's re-hop
% after a failed CRC: its predicted effective configuration is the link's on that frame,
% where only a hop escapes a follower (re-hops, hops on their way, re-acquisitions) and
% where frequency diversity escapes it too; there its first change reaches the link on
% the onset frame and every frame from the onset is restored.
[PP, K] = toy_world(true);
[Ph, Kh] = toy_world(true, true);                               % only channel_switch escapes
on = 9;
for D = [0 1 2 7]
    for f = [0 1 2 3 5]
        spec = struct('scn', 2, 's', 1, 'onset', on, 'follow', true, 'fdelay', f, 'unk', false, 'T', 30, 'r', 1, ...
            'delay', D);
        [~, ~, pred, eff] = oracle_run(Ph, Kh, spec);
        verifyEqual(tc, pred(1:end-D), eff(1+D:end), sprintf('hop only, D %d, fdelay %d', D, f));
        [ok, a, pred, eff] = oracle_run(PP, K, spec);
        verifyEqual(tc, pred(1:end-D), eff(1+D:end), sprintf('D %d, fdelay %d', D, f));
        verifyTrue(tc, all(ok(on:end)), sprintf('restored, D %d, fdelay %d', D, f));
        verifyEqual(tc, find(a ~= K.na, 1), on - D, sprintf('first change, D %d, fdelay %d', D, f));
    end
end
end

function test_flight_reference(tc)
% With 'flight' the restoration reference is the same flight's clean link (its BER
% floored at C.ber_floor, its packet loss): a flight whose clean link is poor is judged
% against itself, not against the mean of the train split.
[PP, K] = toy_world(true);
na = K.na;
for a = 1:numel(PP.actions)                                     % flight 101's clean link at 10 dB: BER 2e-2, half the packets
    PP.pools{1, 1, a, 1}.ber(:) = 0.02; PP.pools{1, 1, a, 1}.fer(:) = 0.5;
end
PP.pools{2, 1, na, 1}.ber(:) = 0.03;
Km = link_env('tables', PP); Kf = link_env('tables', PP, 'flight');
verifyEqual(tc, {Km.ref, Kf.ref}, {'mean', 'flight'});
verifyEqual(tc, [Km.restored(2, 1, na, 1, 1), Km.restored_plr(2, 1, na, 1, 1), Km.healthy(2, 1, 1, 1)], false(1, 3));
verifyEqual(tc, [Kf.restored(2, 1, na, 1, 1), Kf.restored_plr(2, 1, na, 1, 1), Kf.healthy(2, 1, 1, 1)], true(1, 3));
verifyEqual(tc, Kf.restored(2, 2, :, 1, 1), Km.restored(2, 2, :, 1, 1));   % a clean BER of 0 takes the floor
end

function test_comb_jammer(tc)
% A jammer on every channel takes frequency diversity's second carrier too, at its cost;
% recoverable then means a configuration without channel_switch and freq_diversity.
[PP, K] = toy_world(true);
fd = find(strcmp(PP.actions, 'freq_diversity'));
verifyEqual(tc, PP.actions{K.strip_fd(find(strcmp(PP.actions, 'freq_diversity+spatial_diversity+power_control'), 1))}, ...
    'spatial_diversity+power_control');
spec = struct('scn', [2 2], 's', [1 1], 'onset', [1 1], 'follow', [true true], 'fdelay', [0 0], 'unk', [false false], ...
    'T', 10, 'r', [1 1], 'delay', 1, 'comb', [false true]);
[E, ~] = link_env('reset', PP, K, spec, 1, RandStream('mt19937ar', 'Seed', 1));
ok = false(10, 2); rec = ok; cost = zeros(10, 2);
for t = 1:10
    [E, r, ~, info] = link_env('step', E, PP, K, fd * [1 1]);
    ok(t, :) = info.restored; rec(t, :) = info.recoverable; cost(t, :) = r;
end
verifyEqual(tc, ok(2:end, :), repmat([true false], 9, 1));
verifyEqual(tc, rec(end, :), [true false]);
verifyLessThan(tc, cost(end, 2), 0);                             % the second carrier still costs spectrum
end

function test_escalation_after_arrival(tc)
% No escalation and no hold count while the configuration requested has not reached
% the link; its first frame restarts the BER window and the degraded count, so the
% escalation waits C.esc cycles from there.
C = decision_config(); A = policy_actions();
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0);
c0 = find(strcmp(A, rule_based_policy('jamming', true, 0)));
obs = struct('probs', double(strcmp(cls, 'jamming')), 'unknown', false, 'feat', zeros(1, numel(link_features('names'))), ...
    'cfg_link', find(strcmp(A, 'no_action')));
obs.feat(feature_index('log_ber')) = -1; obs.feat(feature_index('crc_fail')) = 1;
mem = [];
for k = 1:8                                                      % requested c0, the link still on no_action
    [a, mem, d] = policy_decide('rule_esc', obs, c0, mem, PP, []);
    verifyEqual(tc, [a, d.escalated, mem.since], [c0, false, 0]);
end
obs.cfg_link = c0; obs.feat(feature_index('log_ber')) = -1.5;
esc = false(1, 8);
for k = 1:8
    [a, mem, d] = policy_decide('rule_esc', obs, c0, mem, PP, []);
    if k == 1, verifyEqual(tc, d.ber_avg, 10^-1.5, 'RelTol', 1e-9); end   % the window restarted
    esc(k) = d.escalated;
    if esc(k), break; end
    verifyEqual(tc, a, c0);
end
verifyEqual(tc, find(esc, 1), C.esc + 1);
% the hold counts from the arrival too: a change requested now waits D frames, then C.hold
m = policy_monitor('change', mem, true);
verifyEqual(tc, m.since, 0);
m = policy_monitor('update', m, obs, PP, c0 + 1);               % frame still on c0
verifyTrue(tc, m.pend);
m = policy_monitor('change', m, false); verifyEqual(tc, m.since, 0);
obs.cfg_link = c0 + 1;
m = policy_monitor('update', m, obs, PP, c0 + 1);
m = policy_monitor('change', m, false);
verifyEqual(tc, [m.since, m.pend], [1 0]);
end

function test_coded_degraded_after_arrival(tc)
% With fec_interleave on the link the CRC packet loss decides (above twice the clean
% coded link's, 0 without the pools, and at least 2 lost packets in the window), from the
% first frame received with it: one lost packet after the arrival is not degraded,
% whatever the window held before and however high the channel BER; a second is.
A = policy_actions();
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0);
na = find(strcmp(A, 'no_action')); cf = find(strcmp(A, 'fec_interleave'));
obs = struct('probs', double(strcmp(cls, 'none')), 'unknown', false, 'feat', zeros(1, numel(link_features('names'))), ...
    'cfg_link', na);
obs.feat(feature_index('log_ber')) = -1; obs.feat(feature_index('crc_fail')) = 1;
m = policy_monitor('init', 1, numel(A));
for k = 1:6                                                      % lost packets on the uncoded link
    [m, M] = policy_monitor('update', m, obs, PP, na);
    m = policy_monitor('change', m, k == 6);                     % then fec_interleave is requested
end
verifyTrue(tc, M.degraded);
[m, M] = policy_monitor('update', m, obs, PP, cf); m = policy_monitor('change', m, false);
verifyTrue(tc, m.pend && M.degraded);                            % still on its way: the uncoded frame
obs.cfg_link = cf;
deg = false(1, 3);
for k = 1:3                                                      % lost, received, lost
    obs.feat(feature_index('crc_fail')) = k ~= 2;
    [m, M] = policy_monitor('update', m, obs, PP, cf); m = policy_monitor('change', m, false);
    deg(k) = M.degraded;
end
verifyEqual(tc, deg, [false false true]);
end

function test_policy_own_monitor(tc)
% A policy's own monitor (the rule fallback of train_dqn.m) replaces the pools' one: the
% same hostile frames confirm after 2 cycles with 2-of-2 and after 3 with 3-of-3.
A = policy_actions();
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'confirm', [2 2], 'alarm_mode', 'class');
obs = struct('probs', double(strcmp(cls, 'jamming')), 'unknown', false, 'feat', zeros(1, numel(link_features('names'))));
obs.feat(feature_index('log_ber')) = -6;
own = struct('monitor', struct('alarm_mode', 'class', 'confirm', [3 3], 'drop_db', []));
[c1, c2] = deal(false(1, 4)); [m1, m2] = deal([]);
for k = 1:4
    [~, m1, d1] = policy_decide('rule_esc', obs, 1, m1, PP, []);
    [~, m2, d2] = policy_decide('rule_esc', obs, 1, m2, PP, [], own);
    c1(k) = d1.confirmed; c2(k) = d2.confirmed;
end
verifyEqual(tc, [find(c1, 1), find(c2, 1)], [2 3]);
end

function test_choose_deployed(tc)
% The DQN when it passed its gate; else the rule setting with the best recovery among
% those within the false-alarm bound; else the lowest bound, committed only within it. A
% bound not measured (no clean validation flights) is never met.
[d, m] = choose_deployed(true, 0.03, [0.90 0.95], [0.04 0.06], 0.05);
verifyEqual(tc, {d, m}, {'dqn_esc', true});
[d, m, ir] = choose_deployed(false, 0.03, [0.90 0.95 0.92], [0.04 0.06 0.045], 0.05);
verifyEqual(tc, {d, m, ir}, {'rule_sel', true, 3});
[d, m, ir] = choose_deployed(false, 0.03, [0.90 0.95], [0.07 0.06], 0.05);
verifyEqual(tc, {d, m, ir}, {'dqn_esc', true, 2});
[d, m] = choose_deployed(false, 0.055, [0.90 0.95], [0.07 0.06], 0.05);
verifyEqual(tc, {d, m}, {'dqn_esc', false});
[d, m] = choose_deployed(false, 0.08, [0.90 0.95], [0.07 0.06], 0.05);
verifyEqual(tc, {d, m}, {'rule_sel', false});
[d, m] = choose_deployed(false, NaN, [0.90 0.95], [NaN NaN], 0.05);          % no clean validation flights
verifyEqual(tc, {d, m}, {'rule_sel', false});
[d, m] = choose_deployed(true, NaN, [0.90 0.95], [NaN NaN], 0.05);
verifyEqual(tc, {d, m}, {'dqn_esc', false});
[d, m, ir] = choose_deployed(false, 0.03, [0.90 0.95], [0.04 NaN], 0.05);       % a measured setting first
verifyEqual(tc, {d, m, ir}, {'rule_sel', true, 1});
end

function test_false_change_rate(tc)
% False changes per cycle, per hour and between them at 20 ms; the bound reaches at
% least the Clopper-Pearson bound over all cycles.
F = false_change_rate([zeros(1, 98), 1, 2], 30, 1:100, 20);
verifyEqual(tc, [F.k, F.cycles], [3 3000]);
verifyEqual(tc, [F.rate, F.per_hour, F.mtbf_s], [1e-3, 180, 20], 'RelTol', 1e-12);
verifyGreaterThanOrEqual(tc, F.hi, betaincinv(0.975, 4, 2997) - 1e-12);
verifyEqual(tc, F.mtbf_lo_s, 0.02 / F.hi, 'RelTol', 1e-12);
F0 = false_change_rate(zeros(1, 100), 30, 1:100, 20);
verifyEqual(tc, [F0.rate, F0.hi], [0, 1 - 0.025^(1/3000)], 'AbsTol', 1e-12);
verifyEqual(tc, F0.mtbf_s, Inf);
E = false_change_rate([], 30, [], 20);
verifyTrue(tc, isnan(E.rate) && E.k == 0);
end

function test_check_point_cut(tc)
% An "up to" edge stops before the first check point NOT COMMITTED that it spans: in
% distance (Eb/N0 from the top down) and in level (from the lowest up); check points
% beyond the edge, UNDETERMINED or missing leave it.
x = 15:-3:0; vm = [1 0 -1 NaN -1];                     % between 15/12, 12/9, 9/6, 6/3, 3/0 dB
verifyEqual(tc, nthout(1:2, @check_point_cut, 3, x, vm), {9, true});
verifyEqual(tc, nthout(1:2, @check_point_cut, 9, x, vm), {9, false});
verifyEqual(tc, nthout(1:2, @check_point_cut, 12, x, vm), {12, false});
verifyEqual(tc, nthout(1:2, @check_point_cut, NaN, x, vm), {NaN, false});
verifyEqual(tc, nthout(1:2, @check_point_cut, 5, 1:5, [1 -1 1 1]), {2, true});
end

function test_detector_id(tc)
% One detector, one identity; another training time, unknown-score window, fusion or
% threshold gives another, and pools and agent of two detectors stop the reading.
FZ = struct('FM', struct('W', ones(3, 2)), 'N', 4); ood = struct('score', 'last', 'win', 3);
id = detector_id(1, ood, FZ, -2);
verifyEqual(tc, detector_id(1, ood, FZ, -2), id);
verifyEqual(tc, numel(id), 16);
o2 = ood; o2.win = 4; F2 = FZ; F2.N = 5; F3 = FZ; F3.FM.W(1) = 2;
ids = {id, detector_id(2, ood, FZ, -2), detector_id(1, o2, FZ, -2), detector_id(1, ood, F2, -2), ...
    detector_id(1, ood, F3, -2), detector_id(1, ood, FZ, -3)};
verifyEqual(tc, numel(unique(ids)), 6);
check_det_id(struct('det_id', id), struct('det_id', id), 'test');
verifyError(tc, @() check_det_id(struct('det_id', id), struct('det_id', ids{2}), 'test'), 'check_det_id:mismatch');
verifyError(tc, @() check_det_id(struct('det_id', id), struct(), 'test'), 'check_det_id:mismatch');
% every stage that reads the agent of data/trained_dqn.mat on the pools checks them
for f = {'evaluate_policies', 'experiment_unknown_threat', 'experiment_combo_generalization', 'edge_map'}
    src = fileread(which(f{1}));
    i0 = strfind(src, 'data/trained_dqn.mat'); i1 = strfind(src, sprintf('check_det_id(PP, Q, ''%s'')', f{1}));
    verifyTrue(tc, ~isempty(i0) && ~isempty(i1) && i1(1) > i0(1), f{1});
end
end

%% ---------- statistics ----------
function test_boot_cluster(tc)
rs = RandStream('mt19937ar', 'Seed', 5);
cl = repelem(1:200, 5);                              % 200 clusters of 5 correlated episodes
x = repelem(rand(rs, 1, 200) < 0.8, 5);
[m, lo, hi] = boot_cluster(double(x), ones(size(x)), cl, 2000, 1);
verifyEqual(tc, m, mean(x), 'AbsTol', 1e-12);
verifyLessThan(tc, lo, m); verifyGreaterThan(tc, hi, m);
[~, lo1, hi1] = boot_cluster(double(x), ones(size(x)), 1:numel(x), 2000, 1);
verifyGreaterThan(tc, hi - lo, hi1 - lo1);           % clustering widens the interval
end

function test_edge_verdict(tc)
% The verdict thresholds for one outcome per flight: against 0.90 at 36 and 72
% flights, all-success below N_MIN, false alarms against 5% at 172 flights (a point), 688
% (four points of a claim) and 96 (the hover clean flights of a band). Two
% episodes per flight widen the interval to the hull; a rate with every flight at 100%
% takes the all-success bound. Packet loss of the clean link at 172 flights of 20
% frames: no loss and one lost frame commit, the verdict never improves as more frames
% are lost, and 5% loss is NOT COMMITTED.
vd = @(k, n) getfield(edge_verdict(double((1:n) <= k), ones(1, n), 1:n, 0.9, 'ge', true), 'verdict');
verifyEqual(tc, [vd(36, 36), vd(35, 36), vd(28, 36)], [1 0 -1]);
verifyEqual(tc, [vd(70, 72), vd(69, 72)], [1 0]);
verifyEqual(tc, vd(35, 35), 0);
fa = @(a, n) getfield(edge_verdict(double((1:n) <= a), ones(1, n), 1:n, 0.05, 'le', true), 'verdict');
verifyEqual(tc, [fa(2, 172), fa(3, 172), fa(15, 172), fa(16, 172)], [1 0 0 -1]);
verifyEqual(tc, [fa(23, 688), fa(24, 688), fa(0, 96), fa(1, 96)], [1 0 1 0]);   % the claim's FA; hover alone
V1 = edge_verdict(double((1:72) <= 66), ones(1, 72), 1:72, 0.9, 'ge', true);
V2 = edge_verdict(double(repelem((1:72) <= 66, 2)), ones(1, 144), repelem(1:72, 2), 0.9, 'ge', true);
verifyEqual(tc, [V2.value, V2.n, V2.k], [V1.value, 72, 66], 'AbsTol', 1e-12);
verifyLessThanOrEqual(tc, V2.lo, V1.lo); verifyGreaterThanOrEqual(tc, V2.hi, V1.hi);
D = edge_verdict(20 * ones(1, 36), 20 * ones(1, 36), 1:36, 0.9, 'ge', false);
verifyEqual(tc, [D.lo, D.verdict], [0.025^(1/36), 1], 'AbsTol', 1e-9);
lk = @(m) edge_verdict(double((1:172) <= m), 20 * ones(1, 172), 1:172, 0.014, 'le', false);
L0 = lk(0);
verifyEqual(tc, [L0.lo, L0.hi], [0, 1 - 0.025^(1/3440)], 'AbsTol', 1e-9);
m = [0 1 2 5 10 20 40 80 120 172];                  % flights with one lost frame, nested
L = arrayfun(lk, m);
verifyEqual(tc, [L(1:2).verdict], [1 1]);
verifyTrue(tc, all(diff([L.verdict]) <= 0) && all(diff([L.hi]) >= 0));
verifyEqual(tc, L(end).verdict, -1);
E = edge_verdict([], [], [], 0.9, 'ge', false);
verifyEqual(tc, [E.n, E.verdict], [0 0]);
% A rate whose flights are all or nothing (fused detection) takes Clopper-Pearson on its
% effective sample size, the flights: 70 of 72 commits, 69 does not (the bootstrap alone
% would commit 69); one wrong frame in each of 30 flights is nearly independent frames
rt = @(k) edge_verdict(20 * double((1:72) <= k), 20 * ones(1, 72), 1:72, 0.9, 'ge', false);
R70 = rt(70); R69 = rt(69);
verifyEqual(tc, [R70.verdict, R69.verdict], [1 0]);
verifyLessThanOrEqual(tc, R69.lo, betaincinv(0.025, 69, 4) + 0.005);
[~, blo] = boot_cluster(20 * double((1:72) <= 69), 20 * ones(1, 72), 1:72, 4000, 74);
verifyGreaterThan(tc, blo, 0.9);
Ri = edge_verdict(20 - double((1:72) <= 30), 20 * ones(1, 72), 1:72, 0.9, 'ge', false);
verifyEqual(tc, Ri.verdict, 1);
verifyGreaterThan(tc, Ri.lo, 0.96);
end

function test_edge_walk(tc)
% Distance: from the top down to the last COMMITTED point, the first NOT COMMITTED and a
% COMMITTED point beyond it. Severity: from the nominal level down and up, so a harmless
% low level that is not COMMITTED stops only the walk down. Follower: from 2 cycles down.
W = edge_walk([1 1 0 1], [15 12 9 6]);
verifyEqual(tc, [W.edge, W.first_not, W.nonmono], [12 NaN 0]);
W = edge_walk([1 -1 1], [15 12 9]);
verifyEqual(tc, [W.edge, W.first_not, W.nonmono], [15 12 1]);
W = edge_walk([0 1 1], [15 12 9]);
verifyTrue(tc, isnan(W.edge));
W = edge_walk([0 1 1 1 -1], 1:5, 3);
verifyEqual(tc, [W.lo, W.hi, W.first_lo, W.first_hi, W.nonmono], [2 4 NaN 5 0]);
W = edge_walk([-1 1 1 1 1], 1:5, 3);
verifyEqual(tc, [W.lo, W.hi, W.first_lo], [2 5 1]);
W = edge_walk([1 1 0 1 1], 1:5, 3);
verifyTrue(tc, isnan(W.lo) && isnan(W.hi));
W = edge_walk([1 1 -1], [2 1 0]);
verifyEqual(tc, W.edge, 1);
end

function test_edge_commit(tc)
% A point commits on PROT, DET_h, FA, LINK, LINK_T and the bound on validation, and no
% band NOT COMMITTED; DET_h on fewer than N_MIN harmed flights only must not fail; the
% bands pool the point and the points above it while they commit from the top, a point
% outside that run its own flights.
one = ones(1, 4);
L = struct('prot', one, 'deth', one, 'deth_n', 72 * one, 'fa', one, 'link', one, 'linkt', one, 'fav', 1);
none = @(R) deal(1, '');
X = edge_commit(L, none);
verifyEqual(tc, X.v, one); verifyTrue(tc, all(cellfun(@isempty, X.lim))); verifyEqual(tc, X.band, one);
Lh = L; Lh.deth = [0 0 -1 0]; Lh.deth_n = [10 40 10 0];
X = edge_commit(Lh, none);
verifyEqual(tc, X.v, [1 0 -1 1]); verifyEqual(tc, X.lim(2:3), {'H', 'H'}); verifyEqual(tc, X.h, [1 0 -1 1]);
Lf = L; Lf.fav = 0;
X = edge_commit(Lf, none);
verifyEqual(tc, X.v, 0 * one); verifyEqual(tc, X.lim{1}, 'F'); verifyTrue(tc, all(isnan(X.band)));
big = @(R) deal(1 - 2 * (numel(R) >= 3), 'speed');            % a band fails once 3 points pool
X = edge_commit(L, big);
verifyEqual(tc, X.v, [-1 -1 1 1]); verifyEqual(tc, X.lim{1}, 'B'); verifyEqual(tc, X.bfail(1:2), {'speed', 'speed'});
Lp = L; Lp.prot = [1 0 1 1];                                   % point 1 lies outside the run from the top
X = edge_commit(Lp, big);
verifyEqual(tc, X.v, [1 0 1 1]); verifyEqual(tc, X.lim{2}, 'P'); verifyTrue(tc, isnan(X.band(2)));
Lt = L; Lt.linkt(4) = -1; Lt.fa(3) = 0;
X = edge_commit(Lt, none);
verifyEqual(tc, X.v, [1 1 0 -1]); verifyEqual(tc, X.lim(3:4), {'A', 'T'});
% FA of the claim (pooled over its Eb/N0) decides; the point's own only must not fail
Lc = L; Lc.fa = [1 1 0 1]; Lc.fa_pt = [0 -1 0 1];
X = edge_commit(Lc, none);
verifyEqual(tc, [X.v; X.fa], [1 -1 0 1; 1 -1 0 1]); verifyEqual(tc, X.lim(2:3), {'A', 'A'});
end

%% ---------- features and state ----------
function test_features(tc)
n = 12;
M = struct('sinr', linspace(-5, 5, n), 'ber_est', logspace(-5, -1, n), 'snr_post', 1:n, 'rssi', zeros(1, n), ...
    'crc_fail', mod(1:n, 2), 'env_corr', zeros(1, n), 'iot', ones(1, n), 'coh', 0.5 * ones(1, n), ...
    'mmse_gain', 3 * ones(1, n), 'align', 0.2 * ones(1, n), 'branch_dip', 2 * ones(1, n), 'branch_gap', 25 * ones(1, n), ...
    'sinr_gap', 7 * ones(1, n));
[raw, names] = link_features(M, 10, 10);
verifyEqual(tc, numel(raw), numel(names));
verifyEqual(tc, raw(feature_index('branch_dip')), 2);
verifyEqual(tc, raw(feature_index('branch_gap')), 25);
verifyEqual(tc, raw(feature_index('sinr_gap')), 7);
verifyEqual(tc, raw(feature_index('log_ber')), log10(M.ber_est(10)), 'AbsTol', 1e-12);
verifyEqual(tc, raw(feature_index('plr')), mean(M.crc_fail(1:10)), 'AbsTol', 1e-12);
verifyEqual(tc, feature_index({'sinr', 'iot'}), [1 9]);
end

function test_ood_candidates(tc)
% Unknown-threat candidates (ood_score_set.m): a point at a class mean scores 0 on
% every Mahalanobis part, a far point scores lower, and the fused candidates are
% the lower standardized component.
rng(1);
M = struct('layers', {{'l1', 'l2'}}, 'candidates', {{'last', 'ensemble', 'raw', 'last_or_raw', 'last_or_if'}}, ...
    'score', 'last', 'mu', {{[0 5; 0 5], [0 3; 0 3]}}, 'P', {{eye(2), eye(2)}}, 'raw_mu', [0 4; 0 4; 0 4], ...
    'raw_P', eye(3), 'w', [0 0.5 0.5], 'z_mu', [0 0], 'z_sd', [1 1], ...
    'zs', struct('last', [-1 2], 'raw', [-2 4], 'iforest', [-0.5 0.1]));
M.forest = iforest(randn(500, 3), 'NumLearners', 50, 'NumObservationsPerLearner', 256);
Z = {[0 10; 0 10], [3 10; 3 10]}; Xf = [4 20; 4 20; 4 20];
S = ood_score_set(M, Z, Xf);
verifyEqual(tc, [S.last(1), S.raw(1)], [0 0]);
verifyLessThan(tc, [S.last(2), S.raw(2), S.ensemble(2)], [S.last(1), S.raw(1), S.ensemble(1)]);
verifyEqual(tc, S.last_or_raw, min((S.last + 1) / 2, (S.raw + 2) / 4), 'AbsTol', 1e-12);
verifyEqual(tc, S.last_or_if, min((S.last + 1) / 2, (S.iforest + 0.5) / 0.1), 'AbsTol', 1e-12);
T = ood_score_set(M, {[], Z{2}}, Xf, {'last'});           % the production path reads the last layer only
verifyEqual(tc, T.last, S.last);
end

function test_state_size(tc)
nA = 36; NE = 3; nC = 11;
mem = policy_monitor('init', NE, nA);
PP = struct('actions', {policy_actions()}, 'classes', {repmat({'x'}, 1, nC)}, 'sps', 4, 'bps', 2, 'maha_thr', 0);
PP.classes = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
obs = struct('probs', repmat([1 zeros(1, nC - 1)], NE, 1), 'unknown', false(NE, 1), ...
    'feat', zeros(NE, numel(link_features('names'))));
obs.feat(:, feature_index('log_ber')) = -5;
[mem, M] = policy_monitor('update', mem, obs, PP, ones(1, NE));
st = policy_state(mem, ones(1, NE), M.confirmed, nA);
[nS, cont] = policy_state_size(nA, nC);
verifyEqual(tc, size(st), [nS NE]);
verifyTrue(tc, all(cont <= nS));
verifyFalse(tc, any(M.alarm));                       % clean class, low BER: no alarm
% the history of one episode never mixes with another's
obs.feat(2, feature_index('sinr')) = 7;
[mem, M] = policy_monitor('update', mem, obs, PP, ones(1, NE));
st = policy_state(mem, ones(1, NE), M.confirmed, nA);
nObs = nC + 18; isinr = nC + 5;
verifyEqual(tc, st(isinr, :), [0 7 0]);              % newest cycle
verifyEqual(tc, st(nObs + isinr, :), [0 0 0]);       % previous cycle
end

%% ---------- receiver measurements on the real link ----------
function test_seeds_and_k(tc)
% Pool geometries never share a seed across the blocks in use (the second test 17,
% the reduced chain check 18 and 19); K-factors are reproducible per seed and stay
% inside the range.
blocks = [1 4 5 13 14 15 16 17 18 19]; S = [];
for b = blocks
    [s, r] = ndgrid(1:6, 1:99);
    S = [S; arrayfun(@(si, ri) pool_seed(1, si, b, ri), s(:), r(:))]; %#ok<AGROW>
end
verifyEqual(tc, numel(unique(S)), numel(S));
k1 = channel_k(12345, [-5 20]); k2 = channel_k(12345, [-5 20]);
verifyEqual(tc, k1, k2);
K = cell2mat(arrayfun(@(s) channel_k(s, [-5 20]), (1:500)', 'UniformOutput', false));
verifyTrue(tc, all(K(:) >= -5 & K(:) <= 20));
end

function test_surv3_run_ids(tc)
% The survivability-options experiment builds its geometries and reads their frames back
% with one run id per geometry, the pools' numbering in its seed block 13.
r = 1:99;
verifyEqual(tc, surv3_run_id(r), 100 * 13 + r);
txt = fileread(which('experiment_survivability_options'));
verifyGreaterThanOrEqual(tc, numel(strfind(txt, 'surv3_run_id(')), 2);
end

function test_seed_streams_disjoint(tc)
% Every purpose of every flight seed draws from its own stream: the purpose offsets
% are distinct and below 64, and the flight seeds of every family are distinct and
% below 2^26.
P = {'channel', 'awgn', 'bits', 'threat', 'aoa', 'ds', 'k', 'yaw', 'corr', 'gcsaoa', 'gcs', 'jam', 'alt', 'speed', ...
    'body', 'wobble'};
off = zeros(1, numel(P));
for i = 1:numel(P)
    [~, n] = seed_stream(12345, P{i});
    off(i) = n - seed_base(12345);
end
verifyEqual(tc, numel(unique(off)), numel(P));
verifyTrue(tc, all(off >= 0 & off < 64));
[s, r, b] = ndgrid(1:6, 1:99, 1:19);                    % every pool block that keeps its own seed range
S = arrayfun(@(si, ri, bi) pool_seed(1, si, bi, ri), s(:), r(:), b(:));
[s, r] = ndgrid(1:6, 1:99);                             % the off-grid check flights (family 2, block 10)
S = [S; arrayfun(@(si, ri) pool_seed(2, si, 10, ri), s(:), r(:))];
[s, b] = ndgrid(1:6, [4 15]);                           % the 100th clean-link geometry
S = [S; arrayfun(@(si, bi) pool_seed(1, si, bi, 100), s(:), b(:))];
[t, li, s] = ndgrid(1:20, 1:8, 1:6);                    % survivability map: entries, levels, Eb/N0
S = [S; 900000 + 1000*t(:) + 10*li(:) + s(:); 700000 + (1:5)'];
k = (1:99999)';
S = [S; 3000000 + k; 4000000 + k; 5000000 + k];         % dataset, unseen Eb/N0 and unseen severity runs
verifyEqual(tc, numel(unique(S)), numel(S));
verifyLessThan(tc, max(S), 2^26);
N = seed_base(S) + off;
verifyEqual(tc, numel(unique(N(:))), numel(N));
verifyLessThan(tc, max(N(:)), 2^32);
% Frame-draw seeds of the edge map's rollouts (edge_map.m: one base per set, the same at
% every signalling delay, + batch below 1000; the base sets 200 000 + 1000 x set, at
% most 99): disjoint ranges, all below the first flight stream
src = fileread(which('edge_map'));
b = sort(cellfun(@(x) str2double(x{1}), regexp(src, 'policy_run_set\([^\n]*opt, (\d{5,6})', 'tokens')));
verifyEqual(tc, b, [40000 90000 95000 200000]);
verifyEmpty(tc, regexp(src, 'policy_run_set\([^\n]*\* d\)', 'once'));
hi = b + 1000 * [1 1 1 100];
verifyTrue(tc, all(hi(1:end-1) <= b(2:end)));
verifyLessThan(tc, hi(end), seed_base(700001));
end

function test_draws_independent(tc)
% The draws of a flight are independent: our signal's K is uncorrelated with the
% heading rate and the other draws (the hover attitude and wobble and the airframe loss
% included), and no draw repeats on another seed (the AoA of geometry r+12 is not the K
% of geometry r).
p = base_params();
[r, s, b] = ndgrid(1:99, 1:6, [5 14 16 17]);            % pool geometries, consecutive seeds along r
[S, v] = arrayfun(@(bi, si, ri) pool_seed(1, si, bi, ri, [0 1]), b(:), s(:), r(:));
K = cell2mat(arrayfun(@(x) channel_k(x, [0 1]), S, 'UniformOutput', false));
A = cell2mat(arrayfun(@(x) interferer_aoa(x, [0 1], 3), S, 'UniformOutput', false));
wmax = min(rad2deg(9.81 * tand(p.roll_max_deg) / p.turn_v_floor), p.yaw_rate_max);
w = arrayfun(@(x) heading_rate(x, 1, p), S) / wmax;     % 1 Hz: below the speed floor
rho = arrayfun(@(x) rx_correlation(x, [0 1]), S);
G = arrayfun(@(x) gcs_aoa(x, [0 1]), S);
W = cell2mat(arrayfun(@(x) hover_attitude(x, 0, p), S, 'UniformOutput', false));
am = min([p.wobble_amp_deg * ones(size(W, 1), 1), p.wobble_pitch_lim_deg(2) - W(:, 2), W(:, 2) - p.wobble_pitch_lim_deg(1)], [], 2);
W = [(W(:, 1) - p.wobble_roll_deg(1)) / diff(p.wobble_roll_deg), (W(:, 2) - p.wobble_pitch_deg(1)) / diff(p.wobble_pitch_deg), ...
    (W(:, 3) ./ am + 1) / 2, (W(:, 4) - p.wobble_freq_hz(1)) / diff(p.wobble_freq_hz), W(:, 5) / (2*pi)];
bm = p.body_loss_db; cn = @(x) 0.5 * erfc(-(x - bm(1)) / (bm(2) * sqrt(2)));
B = (cn(cell2mat(arrayfun(@(x) body_loss(x, 3, bm), S, 'UniformOutput', false))) - cn(bm(3))) / (cn(bm(4)) - cn(bm(3)));
J = cell2mat(arrayfun(@(x) jam_timing(x, [0 1]), S, 'UniformOutput', false));
J(:, 2) = J(:, 2) ./ J(:, 1);
q = p; q.tdl_clip_ns = Inf;                             % no altitude: every channel on the omni fit
Z = cell2mat(arrayfun(@(x) delay_spread(x, NaN, 3, q), S, 'UniformOutput', false));
Z = 0.5 * erfc(-(log10(Z * 1e-9) - q.tdl_int_ds(1)) / sqrt(2 * q.tdl_int_ds(2)));
U = [K, A, (w + 1) / 2, rho, v, G, W, J, Z, B];         % the uniform behind every draw
c = corrcoef(K(:, 1), w);
verifyLessThan(tc, abs(c(1, 2)), 0.1);
C = corrcoef(U);
verifyLessThan(tc, max(abs(C(~eye(size(C))))), 0.1);
i = find(r(:) <= 87);
verifyTrue(tc, all(A(i + 12, 1) ~= K(i, 1)));
verifyGreaterThan(tc, min(diff(sort(U(:)))), 1e-12);
end

function test_lhs_nested(tc)
% The test (12) and second test (60) designs of build_policy_pools.m put 2 + 10
% flights in every sixth of the speed range and of the first interferer's direction, and
% 4 + 20 in every third of the altitude range and of the receive correlation at every
% Eb/N0, a design of 24 (the smaller second test) 4 and 8; every axis has one flight per
% stratum, the value inside it is the flight's own draw, and every value lies in its
% range. The edge-speed split flies exactly hover (the first 24) and 161 km/h; the
% check flights of build_check_pools.m are a design of 36 in a family of their own.
p = base_params();
vr = [p.speed_kmh_min p.speed_kmh_max]; ha = p.alt_range_m; kr = p.k_range_db; ar = p.int_aoa_range_deg; cr = p.corr_range;
six = @(x, rg) histcounts(x, linspace(rg(1), rg(2), 7));
thr = @(x, rg) histcounts(x, linspace(rg(1), rg(2), 4));
for s = 1:6
    g1 = pool_geometries(s, 14, 1:12, vr, p, 7100000 + 100*s + 3);
    g2 = pool_geometries(s, 17, 1:60, vr, p, 7100000 + 100*s + 5);
    gc = pool_geometries(s, 17, 61:84, vr, p, 7100000 + 100*s + 15);
    G = [g1, g2, gc];
    verifyEqual(tc, cell2mat(arrayfun(@(x) six(x.speed, vr), G', 'UniformOutput', false)), repmat([2; 10; 4], 1, 6));
    verifyEqual(tc, cell2mat(arrayfun(@(x) six(x.aoa1, ar), G', 'UniformOutput', false)), repmat([2; 10; 4], 1, 6));
    verifyEqual(tc, cell2mat(arrayfun(@(x) thr(x.alt, ha), G', 'UniformOutput', false)), repmat([4; 20; 8], 1, 3));
    verifyEqual(tc, cell2mat(arrayfun(@(x) thr(x.rho, cr), G', 'UniformOutput', false)), repmat([4; 20; 8], 1, 3));
    verifyEqual(tc, histcounts(g2.ksig, kr(1):5:kr(2)), 12 * ones(1, 5));    % 5-dB K bands
    for g = {g1, g2, gc}
        x = g{1}; n = numel(x.seed);
        verifyEqual(tc, sort(floor(n * (x.speed - vr(1)) / diff(vr))), 0:n-1);
        verifyEqual(tc, sort(floor(n * (x.alt - ha(1)) / diff(ha))), 0:n-1);
        verifyEqual(tc, sort(floor(n * (x.ksig - kr(1)) / diff(kr))), 0:n-1);
        verifyEqual(tc, sort(floor(n * (x.aoa1 - ar(1)) / diff(ar))), 0:n-1);
        verifyEqual(tc, sort(floor(n * (x.rho - cr(1)) / diff(cr))), 0:n-1);
        verifyTrue(tc, all(x.speed > vr(1) & x.speed < vr(2) & x.alt > ha(1) & x.alt < ha(2) ...
            & x.ksig > kr(1) & x.ksig < kr(2) & x.aoa1 > ar(1) & x.aoa1 < ar(2) & x.rho > cr(1) & x.rho < cr(2)));
        u = rand(seed_stream(x.seed(1), 'alt'));
        k = floor(n * (x.alt(1) - ha(1)) / diff(ha));
        verifyEqual(tc, x.alt(1), ha(1) + diff(ha) * (k + u) / n, 'AbsTol', 1e-9);
        u = rand(seed_stream(x.seed(1), 'aoa'));
        k = floor(n * (x.aoa1(1) - ar(1)) / diff(ar));
        verifyEqual(tc, x.aoa1(1), ar(1) + diff(ar) * (k + u) / n, 'AbsTol', 1e-9);
        d = flight_draws(x.seed(1), 100, p, struct('aoa1_deg', x.aoa1(1), 'rho', x.rho(1)));
        verifyEqual(tc, [d.aoa(1) d.rho], [x.aoa1(1) x.rho(1)]);
    end
end
verifyEqual(tc, pool_geometries(6, 17, 1:60, vr, p, 7100605), g2);              % reproducible
q = @(x) floor(numel(x.seed) * (x.alt - ha(1)) / diff(ha));
verifyNotEqual(tc, q(pool_geometries(1, 14, 1:12, vr, p, 7100103)), q(g1));    % own permutation per Eb/N0
verifyLessThan(tc, 7200000 + 100*6, seed_base(700001));                        % below every flight stream
gk = pool_geometries(1, 10, 1:36, vr, p, 7200100, 2);                          % check flights
verifyEqual(tc, gk.seed, arrayfun(@(r) pool_seed(2, 1, 10, r), 1:36));
verifyEqual(tc, [six(gk.speed, vr), thr(gk.alt, ha), six(gk.aoa1, ar), thr(gk.rho, cr)], [6 * ones(1, 6), 12 * ones(1, 3), ...
    6 * ones(1, 6), 12 * ones(1, 3)]);
p.alt_random = false; p.int_aoa_random = false; p.corr_random = false;
x = pool_geometries(1, 17, 1:12, vr, p, 7100105);
verifyTrue(tc, all(isnan([x.alt x.aoa1 x.rho])));
VOUT = [0 0; 161 161]; NHOVER = 24;
ge = pool_geometries(1, 16, 1:36, VOUT(1 + ((1:36)' > NHOVER), :), p);
verifyEqual(tc, ge.speed, [zeros(1, 24), 161 * ones(1, 12)]);
verifyTrue(tc, all(isnan([ge.alt ge.ksig ge.aoa1 ge.rho])));
txt = fileread(which('build_policy_pools'));
verifyNotEmpty(tc, regexp(txt, 'NHOVER = 24;', 'once'));
verifyNotEmpty(tc, regexp(txt, 'sp == iSpd && cells\(c\).sev ~= C.nominal', 'once'));   % hover at every level
end

function test_receiver_measurements(tc)
p = base_params(); p.quiet_build = true; p.active_threat = 'none'; p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false; p.gcs_tracked = false; p.seed = 11;
p.k_random = false; p.gcs_aoa_random = false; p.body_random = false;
p.tdl = false;                                       % the measurements on the flat channel (the delay line: test_delay_line)
mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(p)');
snr = 12 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
set_param([mdl '/AWGN'], 'SNR', num2str(snr), 'SignalPower', num2str(1/p.sps));
link_seed(mdl, 11, 160);
out = sim(mdl, 'StopTime', num2str(10 * p.frame_duration));
F = extract_closed_loop_frames(out, p, 20);
v = ~isnan(F.ber);
verifyEqual(tc, F.crc_fail(v), F.fer(v));            % CRC detects every errored frame here
txb = double(squeeze(out.get('tx_bits_out'))); txi = squeeze(out.get('Tx_IQ'));
txf = comm.RaisedCosineTransmitFilter('RolloffFactor', p.rolloff, 'FilterSpanInSymbols', p.filter_span, ...
    'OutputSamplesPerSymbol', p.sps);
L = frame_layout(p);
sd = reshape(pskmod(txb(:), 4, pi/4, 'gray', 'InputType', 'bit'), L.n_data, []);
sy = repmat(L.tmpl, 1, size(sd, 2)); sy(L.idx_data, :) = sd;    % quiet slot, training, data and pilots, guard
verifyLessThan(tc, max(abs(txf(sy(:)) - txi(:))), 1e-12);
verifyEqual(tc, F.ber(v), zeros(1, sum(v)));                    % the real receiver finds every frame at 12 dB
verifyLessThan(tc, max(abs(F.cfo_hz)), 2 * p.cfo_ppm * 1e-6 * p.carrier_freq + 1e3);
verifyEqual(tc, sum(~isnan(F.ber)), F.nf);                     % every frame complete: bits aligned per frame
verifyLessThan(tc, abs(median(F.q_iot)), 1.5);                 % nothing but thermal noise in the quiet slot
verifyLessThan(tc, mean(F.ber_est(v)), 1e-3);        % clean link at 12 dB
verifyLessThan(tc, max(F.branch_dip), 6);            % fading changes little within a frame, first frame included
sinr_clean = median(F.sinr(v));
% quiet-slot spatial coherence of the clean link: thermal noise alone, at the floor of
% matched-filtered white noise over the same slot at every Eb/N0; the flights' noise is
% the same at every Eb/N0, so any signal of ours in the slot would move it
EQ = [-3 0 6 12 18 24]; CS = 11:13;
coh0 = quiet_coh(mdl, p, EQ, CS);
verifyLessThan(tc, max(abs(coh0 - coh_floor(p))), 0.04);
verifyLessThan(tc, max(coh0) - min(coh0), 0.01);
% the flight's draws reach the blocks: first stream seed, and our signal's amplitude with
% the UAV antenna's gain toward the GCS at 120 m and 0.28 km
d = link_seed(mdl, 11, 160, struct('ebno', 15, 'alt_m', 120));
verifyEqual(tc, str2double(get_param([mdl '/Seed'], 'Value')), seed_base(11));
verifyEqual(tc, d.el_db, uav_dipole_db(asind(110 / (1000 * link_distance_km(15, p)))), 'AbsTol', 1e-12);
verifyEqual(tc, str2double(get_param([mdl '/GCS'], 'Value')), 10^(d.el_db / 20), 'RelTol', 1e-6);
close_system(mdl, 0);
% an open connector: one antenna stays tens of dB below the others in every frame
p.active_threat = 'antenna_fault'; p.fault_atten_db = 31;
evalc('build_threat_model(p)');
set_param([mdl '/AWGN'], 'SNR', num2str(snr), 'SignalPower', num2str(1/p.sps));
link_seed(mdl, 11, 160);
F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(10 * p.frame_duration)), p, 20);
g = sort(F.gain_ant, 1);
verifyGreaterThan(tc, mean(g(2, :) - g(1, :) >= 15), 0.9);
close_system(mdl, 0);
% an antenna hidden by the airframe stays far below the other over the frame
p.active_threat = 'airframe_shadowing'; p.shadow_db = 20;
evalc('build_threat_model(p)');
set_param([mdl '/AWGN'], 'SNR', num2str(snr), 'SignalPower', num2str(1/p.sps));
link_seed(mdl, 11, 160);
F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(10 * p.frame_duration)), p, 20);
verifyGreaterThan(tc, median(F.branch_gap), 12);
verifyLessThan(tc, median(F.branch_dip), 10);         % no deep drop inside the frame, unlike a fault (> 10 dB)
verifyGreaterThan(tc, median(F.sinr_gap, 'omitnan'), 10);   % the other antenna, compared with the reference
verifyLessThan(tc, abs(median(F.sinr, 'omitnan') - sinr_clean), 3);   % the reference is the antenna the airframe does not hide
[~, hidden] = min(median(F.sinr_ant, 2, 'omitnan'));
verifyLessThan(tc, mean(F.ref == hidden), 0.1);      % the hidden antenna is not the reference
% the hidden antenna is drawn per run: different antennas are hit over ten runs
hit = zeros(1, 10);
for r = 1:10
    link_seed(mdl, 10 + r, 160);
    F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(4 * p.frame_duration)), p, 20);
    [~, hit(r)] = min(median(F.sinr_ant, 2, 'omitnan'));
end
verifyGreaterThanOrEqual(tc, numel(unique(hit)), 2);
close_system(mdl, 0);
% quiet slot: a reactive jammer is silent there, a continuous one is not
p.active_threat = 'reactive_jamming'; p.jsr_db = 16;
evalc('build_threat_model(p)');
set_param([mdl '/AWGN'], 'SNR', num2str(snr), 'SignalPower', num2str(1/p.sps));
link_seed(mdl, 11, 160);
F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(10 * p.frame_duration)), p, 20);
verifyLessThan(tc, median(F.q_iot), 2);
verifyGreaterThan(tc, median(F.q_react), 10);
verifyLessThan(tc, abs(mean(F.coh) - coh_floor(p)), 0.06);   % silent there: thermal noise alone
close_system(mdl, 0);
p.active_threat = 'jamming';
evalc('build_threat_model(p)');
set_param([mdl '/AWGN'], 'SNR', num2str(snr), 'SignalPower', num2str(1/p.sps));
link_seed(mdl, 11, 160);
F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(10 * p.frame_duration)), p, 20);
verifyGreaterThan(tc, median(F.q_iot), 10);
verifyLessThan(tc, abs(median(F.q_react)), 3);
% one directional source: the jammer (16 dB) on the clean link's flights is near 1 at
% every Eb/N0; at the lowest trained level (0 dB) it follows its ratio to the noise
% (JSR + 3 dB + Eb/N0): above the floor everywhere, rising with Eb/N0 and with JSR
c16 = quiet_coh(mdl, p, EQ, CS);
verifyGreaterThan(tc, min(c16), 0.9);
close_system(mdl, 0);
p.jsr_db = 0;
evalc('build_threat_model(p)');
c0 = quiet_coh(mdl, p, EQ, CS);
verifyGreaterThan(tc, min(c0 - coh0), 0.2);
verifyGreaterThan(tc, c0(EQ == 12) - c0(1), 0.3);
verifyGreaterThan(tc, min(diff(c0)), -0.01);
verifyGreaterThan(tc, c16(1) - c0(1), 0.3);
verifyGreaterThan(tc, min(c16 - c0), -0.01);
close_system(mdl, 0);
end

function c = quiet_coh(mdl, p, E, seeds)
% Mean quiet-slot coherence of 10-frame flights (seeds) at every Eb/N0 of E [dB].
c = zeros(numel(seeds), numel(E));
for ie = 1:numel(E)
    set_param([mdl '/AWGN'], 'SNR', num2str(E(ie) + 10*log10(p.bits_per_symbol) - 10*log10(p.sps)), ...
        'SignalPower', num2str(1/p.sps));
    for k = 1:numel(seeds)
        link_seed(mdl, seeds(k), 160);
        F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(10 * p.frame_duration)), p, 20);
        c(k, ie) = mean(F.coh);
    end
end
c = mean(c, 1);
end

function c = coh_floor(p)
% Mean pairwise coherence of independent white noise on the antennas after the
% receive filter, over the quiet slot from its first sample whose filter memory lies in
% the slot (as extract_closed_loop_frames.m): the estimation floor of thermal noise alone.
h = rcosdesign(p.rolloff, p.filter_span, p.sps, 'sqrt');
qn = p.quiet_symbols * p.sps; n0 = p.filter_span * p.sps;
rs = RandStream('mt19937ar', 'Seed', 3);
c = zeros(1, 1000);
for r = 1:numel(c)
    x = filter(h, 1, complex(randn(rs, qn, p.n_rx), randn(rs, qn, p.n_rx)));
    R = x(n0+1:end, :)' * x(n0+1:end, :);
    g = abs(R) ./ sqrt(real(diag(R)) * real(diag(R))');
    c(r) = mean(g(triu(true(p.n_rx), 1)));
end
c = mean(c);
end

%% ---------- altitude, distance and the in-band cap ----------
function test_altitude(tc)
% altitude drawn per seed inside the range and reproducible; finite geometry fields
% replace the seed's altitude and K, and nothing else
p = base_params();
h = arrayfun(@(s) flight_altitude(s, p), 1:2000);
verifyTrue(tc, all(h >= p.alt_range_m(1) & h <= p.alt_range_m(2)));
verifyGreaterThan(tc, std(h), 0.25 * diff(p.alt_range_m));      % spread over the range (uniform: 0.29)
verifyEqual(tc, flight_altitude(77, p), flight_altitude(77, p));
d0 = flight_draws(77, 100, p);
verifyEqual(tc, d0.alt_m, flight_altitude(77, p));
verifyEqual(tc, d0.el_db, 0);                                   % no distance: no elevation term
d1 = flight_draws(77, 100, p, struct('ebno', 9, 'alt_m', 50, 'k_sig_db', 3));
verifyEqual(tc, [d1.alt_m d1.k_sig], [50 3]);
verifyEqual(tc, [d1.k_int d1.aoa d1.yaw d1.rho d1.gcs_point_db d1.gcs_aoa d1.bank d1.roll d1.pitch d1.wobble d1.body_db], ...
    [d0.k_int d0.aoa d0.yaw d0.rho d0.gcs_point_db d0.gcs_aoa d0.bank d0.roll d0.pitch d0.wobble d0.body_db]);
d2 = flight_draws(77, 100, p, struct('ebno', 9, 'alt_m', NaN, 'k_sig_db', NaN, 'aoa1_deg', NaN, 'rho', NaN));
verifyEqual(tc, [d2.alt_m d2.k_sig d2.aoa d2.rho], [d0.alt_m d0.k_sig d0.aoa d0.rho]);
d4 = flight_draws(77, 100, p, struct('aoa1_deg', 12, 'rho', 0.5));
verifyEqual(tc, [d4.aoa d4.rho], [12 d0.aoa(2:end) 0.5]);
verifyEqual(tc, [d4.k_sig d4.k_int d4.yaw d4.alt_m d4.gcs_aoa d4.bank d4.body_db], ...
    [d0.k_sig d0.k_int d0.yaw d0.alt_m d0.gcs_aoa d0.bank d0.body_db]);
p.alt_random = false;
d3 = flight_draws(77, 100, p, struct('ebno', 9));
verifyTrue(tc, isnan(d3.alt_m));
verifyEqual(tc, d3.el_db, 0);
end

function test_elevation_gain(tc)
% distance of an Eb/N0 (profile A, tracked GCS antenna) and the UAV dipole's gain toward
% the GCS: at most about 1 dB over the altitude range and the Eb/N0 grid
p = base_params();
verifyEqual(tc, link_distance_km(0, p), 1.575, 'AbsTol', 0.005);
verifyEqual(tc, link_distance_km(15, p), 0.280, 'AbsTol', 0.001);
verifyEqual(tc, uav_dipole_db(0), 0, 'AbsTol', 1e-12);
verifyEqual(tc, uav_dipole_db(90), -30, 'AbsTol', 1e-9);
verifyLessThan(tc, diff(uav_dipole_db([30 60])), 0);
p.gcs_tracked = false;
[h, e] = ndgrid(p.alt_range_m(1):5:p.alt_range_m(2), p.EbNo_dB);
G = zeros(size(h)); A = G; T = G;
for i = 1:numel(h)
    d = flight_draws(1, 100, p, struct('ebno', e(i), 'alt_m', h(i)));
    G(i) = d.el_db; A(i) = d.gcs_amp; T(i) = d.att_db;
    verifyEqual(tc, T(i), uav_attitude_db(d.el_deg, d.gcs_aoa, d.roll, d.pitch, p.uav_null_db), 'AbsTol', 1e-12);
end
verifyGreaterThanOrEqual(tc, min(G(:)), -1.1);
verifyLessThan(tc, min(G(:)), -1);                               % 120 m at 0.28 km
verifyEqual(tc, A, 10.^(T / 20), 'AbsTol', 1e-12);               % the gain at the flight's attitude
p.yaw_random = false;                                            % level flight: the elevation gain alone
d = flight_draws(1, 100, p, struct('ebno', 15, 'alt_m', 120));
verifyEqual(tc, d.att_db, d.el_db, 'AbsTol', 1e-12);
end

function test_inband_cap(tc)
% No additive component above the cap over our received signal, whatever its path loss
% and gain; below the cap the component is untouched; a countermeasure lowers a capped
% emitter by its own amount.
verifyEqual(tc, inband_cap_amp(23, 18, 30), 10^(-11/20), 'RelTol', 1e-12);
[L, PL, G] = ndgrid(-12:2:30, [0 6 14 22], [0 -0.4 -1 -6 -15]);   % level, path loss, gain of our signal [dB]
s = min(1, inband_cap_amp(L, PL, 30) .* 10.^(G / 20));             % the threat block's scale
verifyEqual(tc, L + PL - G + 20*log10(s), min(L + PL - G, 30), 'AbsTol', 1e-9);
verifyEqual(tc, s(L + PL - G <= 30), ones(nnz(L + PL - G <= 30), 1), 'AbsTol', 1e-12);
% with the airframe loss: no antenna of any drawn flight above the cap
q = base_params();
D = arrayfun(@(x) flight_draws(x, 100, q, struct('ebno', 15, 'alt_m', 120)), 1:2000);
ga = 20*log10(vertcat(D.gcs_amp) .* vertcat(D.body_amp));             % our signal on each antenna [dB]
sb = min(1, inband_cap_amp(30, 22, 30) * vertcat(D.gcs_amp) .* min(vertcat(D.body_amp), [], 2));
verifyLessThanOrEqual(tc, max(30 + 22 + 20*log10(sb) - ga, [], 'all'), 30 + 1e-9);
verifyGreaterThan(tc, max(max(ga, [], 2) - min(ga, [], 2)), 3);      % the antennas differ
p = base_params(); p.jsr_db = 23; p.path_loss_db = 18;
p2 = apply_countermeasure(p, 'jamming+path_loss', 'power_control');
verifyEqual(tc, p2.inband_ref.jsr_db, 23);
verifyEqual(tc, p2.jsr_db, 23 - power_step_db(p), 'AbsTol', 1e-9);
% in the model: a 30 dB jammer against a 22 dB path loss reaches 30 dB, not 52 dB, over our signal
p = base_params(); p.quiet_build = true; p.active_threat = 'jamming+path_loss'; p.jsr_db = 30; p.path_loss_db = 22;
p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false; p.gcs_tracked = false; p.seed = 11;
mdl = 'UAV_GCS_Threat_Link';
q = zeros(1, 2);
for k = 1:2
    if k == 2, p.inband_cap_db = Inf; end
    evalc('build_threat_model(p)');
    if k == 1   % the threat block caps on the weakest antenna
        verifyTrue(tc, contains(sfroot().find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/Threat']).Script, '* gcs * min(bdy))'));
    end
    set_param([mdl '/AWGN'], 'SNR', num2str(12 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps)), 'SignalPower', num2str(1/p.sps));
    link_seed(mdl, 11, 160);
    F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(4 * p.frame_duration)), p, 20);
    q(k) = median(F.q_iot);
    close_system(mdl, 0);
end
verifyEqual(tc, q(2) - q(1), 22, 'AbsTol', 1.5);
end

function test_overhead_drop(tc)
% largest drop of an overhead pass: 22.9 dB at 300 m without a mast, none at 15 m
verifyEqual(tc, overhead_drop_db(120, 0.56, 10, -30), 15.6, 'AbsTol', 0.2);
verifyEqual(tc, overhead_drop_db(300, 0.5, 0, -30), 22.9, 'AbsTol', 0.1);
verifyLessThan(tc, arrayfun(@(r) overhead_drop_db(15, r, 10, -30), [0.28 0.4 0.56 0.79 1.12 1.58]), 1e-9);
verifyGreaterThan(tc, overhead_drop_db(120, 0.28, 10, -30), overhead_drop_db(60, 0.28, 10, -30));
% banked over the GCS (the largest measured bank, 57.9 deg): 26.9 dB at 120 m and 0.28 km
% against the wings-level cruise gain; no bank is the level pass, and more bank drops more
verifyEqual(tc, overhead_drop_db(120, 0.28, 10, -30, 57.9), 26.9, 'AbsTol', 0.1);
verifyEqual(tc, overhead_drop_db(120, 0.28, 10, -30, 0), overhead_drop_db(120, 0.28, 10, -30));
verifyGreaterThan(tc, overhead_drop_db(60, 0.4, 10, -30, 45), overhead_drop_db(60, 0.4, 10, -30, 20));
end

%% ---------- temporal evidence and fusion ----------
function test_temporal_evidence(tc)
% Fading: independent per cycle, the weakest antenna changes and the local means
% agree; a hidden antenna stays 8 dB down in every cycle.
rng(3);
n = 12; nr = 3; C = 4;
fade = 10 * log10(-log(rand(1, nr, n)));                       % Rayleigh power per cycle [dB]
sh = fade; sh(1, 2, :) = sh(1, 2, :) - 8;
P = repmat([0.7 0.1 0.1 0.1], 1, 1, n);
Q = zeros(1, n);
xf = temporal_evidence(P, fade, Q); xs = temporal_evidence(P, sh, Q);
verifyEqual(tc, numel(xf), C + 4);
verifyEqual(tc, xf(1:C), log([0.7 0.1 0.1 0.1]), 'AbsTol', 1e-9);
verifyGreaterThan(tc, xs(C + 1), xf(C + 1) + 4);              % gap of the local means
verifyGreaterThan(tc, xs(C + 2), xf(C + 2));                  % the same antenna is the weakest
xq = temporal_evidence(P, fade, [5 5 5 0 0 0 5 5 5 0 0 0]);
verifyEqual(tc, xq(C + 3), 0.5, 'AbsTol', 1e-12);             % share of cycles with quiet-slot interference
op = fade; op(1, 3, 1:3:end) = op(1, 3, 1:3:end) - 30;          % a connector open in every third cycle
xo = temporal_evidence(P, op, Q);
verifyGreaterThan(tc, xo(C + 4), 0.2);                        % the drops are counted
dp = zeros(1, n); dp(2:3:end) = 25;                            % open for part of other cycles: in-frame drops
xp = temporal_evidence(P, fade, Q, dp);
verifyEqual(tc, xp(C + 4), mean(dp >= 15), 'AbsTol', 0.1);
verifyLessThan(tc, xf(C + 4), 0.2);                            % fading alone rarely drops 20 dB below the next
end

function test_fusion(tc)
% Two classes told apart only by the persistence gap: the fusion learns it.
rng(4);
n = 400; y = [ones(n, 1); 2 * ones(n, 1)];
Z = [log(0.5) * ones(2 * n, 2), [randn(n, 1); 6 + randn(n, 1)], rand(2 * n, 2)];
FM = fuse_classes('fit', Z, y, 2, 1e-3);
[~, k] = fuse_classes('apply', FM, Z);
verifyGreaterThan(tc, mean(k == y), 0.95);
end

function test_pre_features(tc)
% Lee et al.'s input pre-processing moves inputs toward the closest known class: the
% smallest Mahalanobis distance of the last layer drops for most inputs
rng(4);
lg = layerGraph([imageInputLayer([8 8 1], 'Normalization', 'none', 'Name', 'img')
    convolution2dLayer(3, 2, 'Name', 'conv'); reluLayer('Name', 'relu1')
    fullyConnectedLayer(4, 'Name', 'fc_img'); concatenationLayer(1, 2, 'Name', 'cat')
    fullyConnectedLayer(4, 'Name', 'fc_m'); reluLayer('Name', 'relu_merge')
    fullyConnectedLayer(2, 'Name', 'fc_out')]);
lg = addLayers(lg, [featureInputLayer(3, 'Name', 'feat'); fullyConnectedLayer(4, 'Name', 'fc_f')]);
lg = connectLayers(lg, 'fc_f', 'cat/in2');
net = dlnetwork(lg);
X = rand(8, 8, 1, 40); F = randn(3, 40);
M = struct('layers', {{'relu_merge'}}, 'mu', {{rand(4, 2)}}, 'P', {{eye(4)}}, 'eps_pre', [0 0]);
d = @(Z) min([sum((Z - M.mu{1}(:, 1)).^2, 1); sum((Z - M.mu{1}(:, 2)).^2, 1)], [], 1);
d0 = d(pre_features(net, M, X, F, [0 0]));
d1 = d(pre_features(net, M, X, F, [0.01 0.05]));
verifyGreaterThan(tc, mean(d1 < d0 | d0 == 0), 0.8);
end

function test_frame_layout(tc)
% quiet slot first, then training, data and pilots without overlap, a guard at the end
p = base_params();
L = frame_layout(p);
verifyEqual(tc, numel(unique([L.idx_data; L.idx_pil])), L.n_data + L.n_pil);
verifyGreaterThan(tc, min([L.idx_data; L.idx_pil]), L.NQ + L.n_pre);
verifyLessThanOrEqual(tc, max([L.idx_data; L.idx_pil]), L.NQ + L.n_sig);
verifyEqual(tc, L.air, L.NQ + L.n_sig + L.G);
verifyEqual(tc, nnz(L.tmpl(1:L.NQ)), 0);
verifyEqual(tc, nnz(L.tmpl(end - L.G + 1:end)), 0);
verifyEqual(tc, abs(L.tmpl(L.NQ + (1:L.n_pre))), ones(L.n_pre, 1), 'AbsTol', 1e-12);
verifyEqual(tc, L.n_pil / (L.n_pil + L.n_data), p.pilot_block / (p.pilot_block + p.pilot_every), 'AbsTol', 0.01);
verifyEqual(tc, p.air_symbols, L.air);
end

function test_heading_rate(tc)
% turns stay within the measured bank angle and yaw rate; same seed, same rate
p = base_params();
w = arrayfun(@(s) heading_rate(s, 1, p), 1:200);
verifyLessThanOrEqual(tc, max(abs(w)), p.yaw_rate_max + 1e-9);
verifyEqual(tc, heading_rate(7, 300, p), heading_rate(7, 300, p));
v = p.v_max; wf = rad2deg(9.81 * tand(p.roll_max_deg) / v);
verifyLessThanOrEqual(tc, max(abs(arrayfun(@(s) heading_rate(s, v * p.carrier_freq / p.c_light, p), 1:200))), min(wf, p.yaw_rate_max) + 1e-9);
end

function test_hover_no_yaw(tc)
% a hovering UAV (no Doppler) does not turn: no source gives a hover yaw rate
p = base_params();
verifyEqual(tc, arrayfun(@(s) heading_rate(s, 0, p), 1:200), zeros(1, 200));
[sd, v] = pool_seed(1, 3, 16, 7, [0 0]);                % a hover flight of the edge-speed pools
verifyEqual(tc, heading_rate(sd, v / 3.6 * p.carrier_freq / p.c_light, p), 0);
verifyNotEqual(tc, heading_rate(sd, 1, p), 0);
end

function test_gcs_pointing(tc)
% same seed, same loss; mean loss as the F.1336 main lobe gives for the measured errors
p = base_params();
verifyEqual(tc, gcs_pointing(5, p), gcs_pointing(5, p));
[g, L] = arrayfun(@(s) gcs_pointing(s, p), 1:4000);
verifyEqual(tc, g, 10.^(-L / 20), 'AbsTol', 1e-12);
verifyTrue(tc, all(L >= 0 & L <= p.gcs_floor_db));
phi3 = sqrt(27000 * 10^(-p.gcs_ant_dbi / 10));
verifyEqual(tc, mean(L), 12 * sum((p.gcs_err_deg * sqrt(pi / 2)).^2) / phi3^2, 'RelTol', 0.1);
p.gcs_tracked = false;
verifyEqual(tc, gcs_pointing(5, p), 1);
end

%% ---------- flight geometry: GCS direction, bank, airframe, attitude in wind ----------
function test_gcs_direction(tc)
% The GCS direction is drawn per flight over every broadside angle, reproducible, added to
% p.gcs_aoa_deg (the relay path) and fixed when the draw is off; each interferer's
% alignment is taken against the GCS's cone angle.
p = base_params();
b = arrayfun(@(s) gcs_aoa(s, p.gcs_aoa_range_deg), 1:4000);
verifyTrue(tc, all(b >= -90 & b <= 90));
verifyEqual(tc, histcounts(b, -90:45:90) / 4000, 0.25 * ones(1, 4), 'AbsTol', 0.03);
verifyEqual(tc, gcs_aoa(9, p.gcs_aoa_range_deg), gcs_aoa(9, p.gcs_aoa_range_deg));
d = flight_draws(9, 100, p, struct('ebno', 9, 'alt_m', 90));
verifyEqual(tc, d.gcs_aoa, gcs_aoa(9, p.gcs_aoa_range_deg));
[~, ca] = uav_attitude_db(d.el_deg, d.gcs_aoa, d.roll, d.pitch, p.uav_null_db);
verifyEqual(tc, ca, cosd(d.el_deg) * sind(d.gcs_aoa), 'AbsTol', 1e-12);     % no pitch above 8 m/s
st = @(c) exp(-1j * 2*pi * p.ant_spacing_wl * (0:p.n_rx-1)' * c);
verifyEqual(tc, d.align, abs(st(ca)' * st(sind(d.aoa))).^2 / p.n_rx^2, 'AbsTol', 1e-12);
p.gcs_aoa_deg = 60;
verifyEqual(tc, getfield(flight_draws(9, 100, p), 'gcs_aoa'), 60 + d.gcs_aoa, 'AbsTol', 1e-12);
p.gcs_aoa_random = false;
verifyEqual(tc, getfield(flight_draws(9, 100, p), 'gcs_aoa'), 60);
end

function test_bank_angle(tc)
% Bank of a coordinated turn: the largest measured (57.9 deg) at 161 km/h at the largest
% rate, 45.6 deg at 72 km/h under the yaw-rate cap, 0 at hover; every flight's roll is its
% bank to the side of the turn.
p = base_params();
fd = @(v) v * p.carrier_freq / p.c_light;
wmax = min(rad2deg(9.81 * tand(p.roll_max_deg) / p.v_max), p.yaw_rate_max);
verifyEqual(tc, bank_angle(wmax, fd(p.v_max), p), p.roll_max_deg, 'AbsTol', 1e-9);
verifyEqual(tc, bank_angle(-p.yaw_rate_max, fd(20), p), 45.6, 'AbsTol', 0.05);
verifyEqual(tc, bank_angle(p.yaw_rate_max, 0, p), 0);
for v = [0 20 p.v_max]
    C = arrayfun(@(s) flight_draws(s, fd(v), p), 1:200, 'UniformOutput', false); D = [C{:}];
    verifyLessThanOrEqual(tc, max([D.bank]), p.roll_max_deg + 1e-9);
    if v > 0
        verifyEqual(tc, [D.roll], sign([D.yaw]) .* [D.bank], 'AbsTol', 1e-12);
        verifyGreaterThan(tc, mean([D.bank] > 30), 0.3);         % fast flights often bank past 30 deg
    else
        verifyEqual(tc, [D.bank], zeros(1, 200));
    end
end
end

function test_attitude_gain(tc)
% Gain of the tilted UAV antenna toward the GCS: the level pattern without tilt; with the
% GCS abeam the pattern at the bank (-6.98 dB at 57.9 deg), with the GCS ahead the
% polarization loss 20 log10(cos(bank)) (Badi et al.); outside the turn at 120 m and
% 0.28 km 17 dB below level, the inside less; the floor; never above the horizon gain.
[E, B] = ndgrid(0:5:60, -90:15:90);
[g, ca] = uav_attitude_db(E, B, 0, 0, -30);
verifyEqual(tc, g, uav_dipole_db(E), 'AbsTol', 1e-9);
verifyEqual(tc, ca, cosd(E) .* sind(B), 'AbsTol', 1e-12);
verifyEqual(tc, uav_attitude_db(0, 0, 57.9, 0, -30), -6.98, 'AbsTol', 0.01);
verifyEqual(tc, uav_attitude_db(0, 0, -57.9, 0, -30), uav_attitude_db(0, 0, 57.9, 0, -30), 'AbsTol', 1e-12);
verifyEqual(tc, uav_attitude_db(0, 90, 57.9, 0, -30), 20*log10(cosd(57.9)), 'AbsTol', 1e-9);
verifyEqual(tc, uav_attitude_db(0, 90, 0, 30, -30), uav_dipole_db(30), 'AbsTol', 1e-9);   % the nose up, the GCS ahead
h = asind(110 / (1000 * link_distance_km(15, base_params())));
verifyEqual(tc, uav_attitude_db(h, 0, -57.9, 0, -30) - uav_dipole_db(h), -17.1, 'AbsTol', 0.2);
verifyGreaterThan(tc, uav_attitude_db(h, 0, 57.9, 0, -30), uav_attitude_db(h, 0, -57.9, 0, -30));
verifyEqual(tc, uav_attitude_db(0, 0, 90, 0, -30), -30, 'AbsTol', 1e-9);
rs = RandStream('mt19937ar', 'Seed', 3); u = rand(rs, 1e4, 4);
g = uav_attitude_db(90 * u(:, 1), 180 * u(:, 2) - 90, 120 * u(:, 3) - 60, 60 * u(:, 4) - 30, -30);
verifyTrue(tc, all(g <= 1e-9 & g >= -30));
end

function test_body_loss(tc)
% Airframe loss per antenna inside Badi et al.'s measured 0.016-10.96 dB; the spread
% between the strongest and weakest of three antennas from the measured mean and SD
% (median 3.3 dB, 95th percentile 6.8 dB); only the spread reaches our signal.
p = base_params();
B = cell2mat(arrayfun(@(s) body_loss(s, 3, p.body_loss_db), (1:20000)', 'UniformOutput', false));
verifyTrue(tc, all(B(:) >= p.body_loss_db(3) & B(:) <= p.body_loss_db(4)));
S = sort(max(B, [], 2) - min(B, [], 2));
verifyEqual(tc, S(10000), 3.3, 'AbsTol', 0.2);
verifyEqual(tc, S(19000), 6.8, 'AbsTol', 0.3);
verifyEqual(tc, body_loss(4, 3, p.body_loss_db), body_loss(4, 3, p.body_loss_db));
d = flight_draws(4, 100, p);
verifyEqual(tc, d.body_db, body_loss(4, p.n_rx, p.body_loss_db));
verifyEqual(tc, -20*log10(d.body_amp), d.body_db - mean(d.body_db), 'AbsTol', 1e-12);
p.body_random = false;
verifyEqual(tc, getfield(flight_draws(4, 100, p), 'body_amp'), ones(1, p.n_rx));
end

function test_hover_wobble(tc)
% Attitude in wind: none from 8 m/s up; below, the static tilt within Polle et al.'s
% measured means and the pitch wobble within Banagar & Dhillon's ranges, the pitch with
% its wobble within Polle et al.'s largest calibrated tilts. Banagar & Dhillon's wobble,
% its lever-arm phase k aD cos(phi) sin(pitch) (phi = 20 deg, their example),
% decorrelates the channel (ACF 0.5 at the worst phase) after 6.74 ms at 10 deg and
% 12.26 ms at 7 deg (+-30%), and never at 5 deg, as they found at 2.4 GHz.
p = base_params();
fd = @(v) v * p.carrier_freq / p.c_light;
verifyEqual(tc, hover_attitude(5, fd(p.wobble_v_max), p), zeros(1, 5));
verifyEqual(tc, hover_attitude(5, fd(p.v_max), p), zeros(1, 5));
W = cell2mat(arrayfun(@(s) hover_attitude(s, fd(3), p), (1:4000)', 'UniformOutput', false));
verifyTrue(tc, all(W(:, 1) >= p.wobble_roll_deg(1) & W(:, 1) <= p.wobble_roll_deg(2)));
verifyTrue(tc, all(W(:, 2) >= p.wobble_pitch_deg(1) & W(:, 2) <= p.wobble_pitch_deg(2)));
verifyTrue(tc, all(abs(W(:, 3)) <= p.wobble_amp_deg & W(:, 4) >= p.wobble_freq_hz(1) & W(:, 4) < p.wobble_freq_hz(2)));
verifyTrue(tc, all(W(:, 2) + abs(W(:, 3)) <= p.wobble_pitch_lim_deg(2) + 1e-9 & ...
    W(:, 2) - abs(W(:, 3)) >= p.wobble_pitch_lim_deg(1) - 1e-9));
verifyGreaterThan(tc, max(abs(W(:, 3))), 9.5);                 % the full wobble where the tilt leaves room
verifyLessThan(tc, max(W(:, 2) + abs(W(:, 3))), 21.1 + 1e-9);
d = flight_draws(5, fd(3), p);
verifyEqual(tc, [d.roll - sign(d.yaw) * d.bank, d.pitch, d.wobble], hover_attitude(5, fd(3), p), 'AbsTol', 1e-12);
d = flight_draws(5, fd(p.wobble_v_max), p);
verifyEqual(tc, [d.pitch d.wobble], zeros(1, 4));
ka = 2*pi * p.wobble_arm_m * p.carrier_freq / p.c_light;
tau = (0:0.05:30) * 1e-3;
tco = zeros(1, 3); m = [10 7 5];
A = 2 * rand(RandStream('mt19937ar', 'Seed', 5), size(W, 1), 1) - 1;   % their amplitude, uniform in +-m
for i = 1:3
    R = abs(mean(exp(1j * ka * cosd(20) * sind(A * m(i) .* sin(2*pi * W(:, 4) * tau))), 1));
    j = find(R <= 0.5, 1); tco(i) = Inf; if ~isempty(j), tco(i) = tau(j); end
end
verifyEqual(tc, tco(1:2), [6.74 12.26] * 1e-3, 'RelTol', 0.3);
verifyEqual(tc, tco(3), Inf);
end

function test_channel_geometry(tc)
% Our signal in the model: the LoS arrives at the GCS's cone angle set at run time, the
% diffuse part is centred on the GCS direction, the airframe loss scales each antenna,
% the antenna gain toward the GCS follows the pitch, and at hover the wobble decorrelates
% the channel between frames 20 ms apart while a calm hover keeps it frozen.
p = base_params(); p.quiet_build = true; p.active_threat = 'none'; p.rx_sync = 'ideal'; p.seed = 11;
p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false; p.gcs_tracked = false; p.k_random = false;
p.gcs_aoa_random = false; p.body_random = false; p.wobble_random = false; p.chain_amp_db = 0; p.chain_phase_deg = 0;
mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(p)');
set_param([mdl '/AWGN'], 'SNR', num2str(60 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps)), 'SignalPower', num2str(1/p.sps));
n = p.n_rx; fs = p.symbol_rate * p.sps; fdx = p.v_max * p.carrier_freq / p.c_light;
st = @(c) exp(-1j * 2*pi * p.ant_spacing_wl * (0:n-1)' * c) / sqrt(n);
Y = run_link(mdl, p, 160, [60 10], 0.3, [40 30 zeros(1, 5)], ones(1, n), 4);
v = lead_dir(Y);
verifyGreaterThan(tc, abs(st(cosd(30) * sind(40))' * v)^2, 0.99);    % the cone angle, not the azimuth
verifyLessThan(tc, abs(st(sind(40))' * v)^2, 0.5);
Y = run_link(mdl, p, fdx, [-60 10], 0.9, [40 30 zeros(1, 5)], ones(1, n), 20);
verifyGreaterThan(tc, abs(st(cosd(30) * sind(40))' * lead_dir(Y))^2, 0.9);
b = [0 -6 4 -2]; b = b(1:n);
Y = run_link(mdl, p, 160, [60 10], 0.3, zeros(1, 7), 10.^(b / 20), 4);
pw = 10*log10(mean(abs(Y).^2, [1 3]));
verifyEqual(tc, pw - pw(1), b - b(1), 'AbsTol', 0.2);
% hovering, the GCS ahead at 30 deg below: the pitch wobble moves the antenna gain by
% the pattern at 30 deg + pitch, frame by frame
a0 = [90 30 0 0 0 0 0]; aw = [90 30 0 0 10 15 0];
Y0 = run_link(mdl, p, 0, [60 10], 0.3, a0, ones(1, n), 10);
Yw = run_link(mdl, p, 0, [60 10], 0.3, aw, ones(1, n), 10);
[ns, ~, nf] = size(Y0);
t = (0:ns-1)' / fs + (0:nf-1) * round(p.cycle_s * fs) / fs;
g = uav_attitude_db(30, 90, 0, 10 * sin(2*pi * 15 * t), p.uav_null_db) - uav_attitude_db(30, 90, 0, 0, p.uav_null_db);
verifyEqual(tc, 10*log10(squeeze(mean(sum(abs(Yw).^2, 2), 1) ./ mean(sum(abs(Y0).^2, 2), 1)))', ...
    10*log10(mean(10.^(g / 10), 1)), 'AbsTol', 0.05);
[~, H0] = run_link(mdl, p, 0, [10 10], 0.3, a0, ones(1, n), 10);
[~, Hw] = run_link(mdl, p, 0, [10 10], 0.3, aw, ones(1, n), 10);
verifyGreaterThan(tc, frame_corr(H0), 0.99);
verifyLessThan(tc, frame_corr(Hw), 0.7);
close_system(mdl, 0);
end

function test_interferer_channel(tc)
% An interferer's LoS carries the Doppler shift of its direction: against the same flight
% hovering, its phase advances 2 pi fd sin(aoa) per second; its diffuse part is centred on
% its own direction.
p = base_params(); p.quiet_build = true; p.active_threat = 'jamming'; p.jsr_db = 30; p.rx_sync = 'ideal'; p.seed = 11;
p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false; p.gcs_tracked = false; p.k_random = false;
p.gcs_aoa_random = false; p.body_random = false; p.wobble_random = false; p.chain_amp_db = 0; p.chain_phase_deg = 0;
mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(p)');
set_param([mdl '/AWGN'], 'SNR', num2str(60 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps)), 'SignalPower', num2str(1/p.sps));
n = p.n_rx; fs = p.symbol_rate * p.sps; fdx = p.v_max * p.carrier_freq / p.c_light;
Y1 = run_link(mdl, p, fdx, [10 60], 0.3, zeros(1, 7), ones(1, n), 10);
Y0 = run_link(mdl, p, 0, [10 60], 0.3, zeros(1, 7), ones(1, n), 10);
[ns, ~, nf] = size(Y1);
t = (0:ns-1)' / fs + (0:nf-1) * round(p.cycle_s * fs) / fs;
z = squeeze(Y1(:, 1, :) .* conj(Y0(:, 1, :)));
coh = @(f) abs(sum(z .* exp(-1j * 2*pi * f * t), 'all')) / sum(abs(z), 'all');
verifyGreaterThan(tc, coh(fdx * sind(p.int_aoa_deg(1))), 0.98);
verifyLessThan(tc, coh(0), 0.5);
st = @(c) exp(-1j * 2*pi * p.ant_spacing_wl * (0:n-1)' * c) / sqrt(n);
Y = run_link(mdl, p, fdx, [10 -60], 0.9, zeros(1, 7), ones(1, n), 20);
verifyGreaterThan(tc, abs(st(sind(p.int_aoa_deg(1)))' * lead_dir(Y))^2, 0.9);
close_system(mdl, 0);
end

function test_tdl_profile(tc)
% The delay line's diffuse profile: exponential on taps 250 ns apart with unit power, and
% with the LoS on tap 0 at the K-factor the composite RMS delay spread is the target; a
% spread the 4.5 us window cannot hold at that K gets the flat profile (767 ns at
% K 10 dB); no spread puts it all on tap 0.
tau = (0:18)' * 250;
for k = [-5 2 10]
    q = 1 / (10^(k/10) + 1);
    for ds = [64 138 234 302 372]
        [a, r] = tdl_profile(ds, k, 19, 250);
        P = a.^2;
        verifyEqual(tc, sum(P), 1, 'AbsTol', 1e-12);
        verifyEqual(tc, P(2:end) ./ P(1:end-1), P(2) / P(1) * ones(18, 1), 'RelTol', 1e-9);
        w = [1 - q + q * P(1); q * P(2:end)];
        verifyEqual(tc, [r, sqrt(sum(w .* tau.^2) - sum(w .* tau)^2)], [ds ds], 'RelTol', 1e-6);
    end
end
[a, r] = tdl_profile(1000, 10, 19, 250);
verifyEqual(tc, a, ones(19, 1) / sqrt(19), 'AbsTol', 1e-12);
verifyEqual(tc, r, 767.4, 'AbsTol', 0.1);
verifyEqual(tc, tdl_profile(0, 10, 19, 250), [1; zeros(18, 1)]);
verifyEqual(tc, tdl_profile(300, 10, 1, 250), 1);
end

function test_delay_spread(tc)
% Per-flight RMS delay spreads, log-normal as Rodriguez-Pineiro et al.'s fits: our signal
% below 25 m on the directional OLoS fit (median 302 ns, sigma 0.566 decades), above it
% and without an altitude on the omni fit (234 ns, 0.4), every interferer on the omni fit,
% all clipped at 1 us. flight_draws turns them into the delay line's profiles at the
% flight's K, and gives a flat channel without the line.
p = base_params(); p.tdl = true; p.tdl_random = true;
n = 4000;
lo = cell2mat(arrayfun(@(s) delay_spread(s, 20, 3, p), (1:n)', 'UniformOutput', false));
hi = cell2mat(arrayfun(@(s) delay_spread(s, 60, 3, p), (1:n)', 'UniformOutput', false));
verifyEqual(tc, hi, cell2mat(arrayfun(@(s) delay_spread(s, NaN, 3, p), (1:n)', 'UniformOutput', false)));
verifyEqual(tc, lo(:, 2:end), hi(:, 2:end));
q = @(x, f) log10(sort(x(:)) * 1e-9);
for c = {lo(:, 1), -6.52, 0.32; hi(:, 1), -6.63, 0.16; hi(:, 2:end), -6.63, 0.16}'
    v = q(c{1}); m = numel(v);
    verifyEqual(tc, v(round(m / 2)), c{2}, 'AbsTol', 0.03);
    verifyEqual(tc, (v(round(0.75 * m)) - v(round(0.25 * m))) / (2 * 0.6745), sqrt(c{3}), 'RelTol', 0.08);
end
verifyLessThanOrEqual(tc, max([lo(:); hi(:)]), p.tdl_clip_ns);
verifyEqual(tc, mean(lo(:, 1) == p.tdl_clip_ns), 0.5 * erfc((-6 + 6.52) / sqrt(2 * 0.32)), 'AbsTol', 0.02);
d = flight_draws(5, 100, p, struct('ebno', 9, 'alt_m', 20, 'k_sig_db', 2));
ds = delay_spread(5, 20, numel(p.int_aoa_deg), p);
verifyEqual(tc, size(d.tdl), [19, 1 + numel(p.int_aoa_deg)]);
verifyEqual(tc, sum(d.tdl.^2, 1), ones(1, size(d.tdl, 2)), 'AbsTol', 1e-12);
verifyEqual(tc, d.ds_ns(1), ds(1), 'RelTol', 1e-6);
verifyTrue(tc, all(d.ds_ns(2:end) <= ds(2:end) + 1e-6));
p.tdl = false;
d = flight_draws(5, 100, p);
verifyEqual(tc, [d.tdl; d.ds_ns], [ones(1, 1 + numel(p.int_aoa_deg)); zeros(1, 1 + numel(p.int_aoa_deg))]);
end

function test_delay_line(tc)
% In the model with the delay line: our channel's correlation across frequency follows
% the profile (K 0 dB, 500 ns: the LoS share plus every tap's power at its delay) and the
% received power stays the flat channel's; an interferer's channel is spread too, so in
% the quiet slot its spatial covariance gains a second eigenvalue the flat channel lacks,
% and its waveform runs from before the frame, so the slot's first samples hold its full
% power; every other waveform runs over the line as well.
p = base_params(); p.quiet_build = true; p.active_threat = 'none'; p.rx_sync = 'ideal'; p.seed = 11;
p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false; p.gcs_tracked = false; p.k_random = false;
p.gcs_aoa_random = false; p.body_random = false; p.wobble_random = false; p.chain_amp_db = 0; p.chain_phase_deg = 0;
p.tdl = true; p.tdl_random = false; p.tdl_ds_ns = [500 500]; p.rician_k = 0; p.int_rician_k = 0;
mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(p)');
set_param([mdl '/AWGN'], 'SNR', '60', 'SignalPower', num2str(1/p.sps));
Y = []; X = [];
for s = 1:10                                            % fd 50 Hz: frames 20 ms apart fade apart
    d = link_seed(mdl, s, 50);
    out = sim(mdl, 'StopTime', num2str(30 * p.frame_duration));
    Y = cat(3, Y, out.get('Rx_IQ')); X = cat(3, X, out.get('Tx_IQ'));
end
close_system(mdl, 0);
fs = p.symbol_rate * p.sps; ns = size(Y, 1);
f = ((0:ns-1)' - floor(ns/2)) * fs / ns;
P = d.tdl(:, 1).^2; m = (0:numel(P)-1)';
for df = [0.25 0.5] * 1e6
    k = round(df * ns / fs); v = find(abs(f) <= 0.45e6 & abs(f + k * fs / ns) <= 0.45e6);
    num = 0; den = 0;
    for fr = 1:size(Y, 3)
        H = fftshift(fft(Y(:, :, fr)), 1) ./ fftshift(fft(X(:, 1, fr)));
        num = num + sum(H(v + k, :) .* conj(H(v, :)), 'all'); den = den + sum(abs(H(v, :)).^2, 'all');
    end
    verifyEqual(tc, abs(num / den), abs(0.5 + 0.5 * sum(P .* exp(-1j * 2*pi * k * fs / ns * m * 250e-9))), 'AbsTol', 0.06);
end
verifyEqual(tc, mean(abs(Y).^2, 'all') / mean(abs(X).^2, 'all'), 1, 'AbsTol', 0.1);
p.active_threat = 'jamming'; p.jsr_db = 30; p.rician_k = 10;
e = zeros(1, 2); g = e;
for t = [false true]
    p.tdl = t;
    evalc('build_threat_model(p)');
    set_param([mdl '/AWGN'], 'SNR', '60', 'SignalPower', num2str(1/p.sps));
    link_seed(mdl, 11, 0);
    out = sim(mdl, 'StopTime', num2str(40 * p.frame_duration));
    Y = out.get('Rx_IQ');
    R = 0;
    for fr = 1:size(Y, 3), R = R + Y(1:128, :, fr).' * conj(Y(1:128, :, fr)); end
    l = sort(real(eig((R + R') / 2)), 'descend');
    e(1 + t) = l(2) / l(1);
    g(1 + t) = mean(abs(Y(1:4, :, :)).^2, 'all') / mean(abs(Y(40:120, :, :)).^2, 'all');
    close_system(mdl, 0);
end
verifyLessThan(tc, e(1), 1e-3);
verifyGreaterThan(tc, e(2), 0.05);
verifyEqual(tc, g(2), 1, 'AbsTol', 0.15);
% the other waveforms run over the line too
p.active_threat = 'reactive_jamming+spoofing+benign_interference'; p.tdl_random = true;
evalc('build_threat_model(p)');
link_seed(mdl, 11, 160);
out = sim(mdl, 'StopTime', num2str(3 * p.frame_duration));
verifyTrue(tc, all(isfinite(out.get('Rx_IQ')), 'all'));
close_system(mdl, 0);
end

function test_rx_taps(tc)
% The real receiver's taps span the delay line's delays: MRC lags 2 before and the line's
% 4.5 us window after, the equalizer +-5 symbols, the space-time MMSE +-2 us (twice the
% 1 us clip) half a symbol apart, its window twice the 27 degrees of freedom; on the flat
% channel every count is 1, and so is the receiver built for it.
p = base_params();
p.tdl = false;
t = rx_taps(p);
verifyEqual(tc, [t.lags t.ne t.nt t.window], [0 0 1 1 p.mmse_window]);
verifyEqual(tc, rx_taps(rmfield(p, 'tdl')), t);
p.tdl = true;
t = rx_taps(p);
verifyEqual(tc, [t.lags t.ne t.nt t.window], [2 5 11 9 64]);
q = p; q.tdl_max_ns = 2000; q.tdl_clip_ns = 500;
t = rx_taps(q);
verifyEqual(tc, [t.lags t.ne t.nt t.window], [2 2 5 5 32]);
p.quiet_build = true; p.rx_sync = 'real';
mdl = 'UAV_GCS_Threat_Link';
C = {false, 'mrc', 'NT = 1;', 'NE = 1;'; false, 'mmse', 'NT = 1;', 'NE = 1;'; ...
     true, 'mrc', 'NT = 1;', 'NE = 11;'; true, 'mmse', 'NT = 9;', 'NE = 1;'};
for i = 1:size(C, 1)
    p.tdl = C{i, 1}; p.rx_combiner = C{i, 2};
    evalc('build_threat_model(p)');
    ch = sfroot().find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/Rx']);
    verifyTrue(tc, contains(ch.Script, C{i, 3}) && contains(ch.Script, C{i, 4}));
    close_system(mdl, 0);
end
end

function test_receiver_delay_spread(tc)
% The real receiver on the delay line, three flights at 160 Hz: MRC over the antennas and
% the channel's lags with the linear MMSE equalizer keeps a clean link at K -5 dB and a
% 1 us RMS delay spread below 1e-3 at 12 dB; the MMSE receiver keeps a 16 dB jammer whose
% channel spreads 234 ns below 0.03 at 15 dB, and one that spreads 64 ns, nearly flat,
% about as well as the flat receiver on the flat channel at 6 dB (each frame keeps the
% space-time or the antennas-alone output by its pilots); a 30 dB jammer on the flat
% channel stays below 0.06.
p = base_params(); p.quiet_build = true; p.rx_sync = 'real'; p.int_aoa_random = false; p.yaw_random = false;
p.corr_random = false; p.gcs_tracked = false; p.k_random = false; p.gcs_aoa_random = false; p.body_random = false;
p.tdl = true; p.tdl_random = false;
mdl = 'UAV_GCS_Threat_Link';
q = p; q.active_threat = 'none'; q.rx_combiner = 'mrc'; q.rician_k = -5; q.tdl_ds_ns = [1000 0];
verifyLessThan(tc, link_ber(mdl, q, 12, 21:23, 20), 1e-3);
q = p; q.active_threat = 'jamming'; q.jsr_db = 16; q.rx_combiner = 'mmse'; q.rician_k = 10; q.int_rician_k = 10;
q.tdl_ds_ns = [0 234];
verifyLessThan(tc, link_ber(mdl, q, 15, 21:23, 20), 0.03);
q.tdl_ds_ns = [0 64];
b64 = link_ber(mdl, q, 6, 21:23, 20);
q.tdl = false;
verifyLessThan(tc, b64, 1.5 * link_ber(mdl, q, 6, 21:23, 20));
q.jsr_db = 30;
verifyLessThan(tc, link_ber(mdl, q, 15, 21:23, 20), 0.06);
end

function test_power_cap(tc)
% The licence-exempt density cap of 10 dBm in any 1 MHz (ETSI EN 300 328) on our RRC
% signal: 95.5% of its power in the central 1 MHz, so 10.20 dBm; the AD9361-class radio
% steps up by its largest 0.25 dB step under it, +4.0 dB to 10.0 dBm e.i.r.p.; on the omni
% its 7.5 dBm CW output, less our waveform's peak-to-average ratio (4-6 dB for RRC QPSK at
% a 0.25 roll-off; no lower than the model's own transmit filter shows), binds first. The
% share also from the transmit filter's own spectrum, and one frame per cycle within the
% standard's limits for non-adaptive equipment.
p = base_params();
[cap, share] = eirp_cap_dbm(10, 0.25, 1e6);
verifyEqual(tc, share, 0.75 + 2 * (0.25/4 + 0.25/(2*pi)), 'AbsTol', 1e-12);
verifyEqual(tc, cap, 10.20, 'AbsTol', 0.01);
verifyEqual(tc, p.gcs_eirp_cap_dbm, cap, 'AbsTol', 1e-12);
verifyEqual(tc, power_step_db(p), 4.0, 'AbsTol', 1e-12);
verifyEqual(tc, p.gcs_pt_dbm + p.gcs_ant_dbi + power_step_db(p), 10.0, 'AbsTol', 1e-12);
N = 2^16; os = 64;
H = abs(fft(rcosdesign(p.rolloff, 40, os, 'sqrt'), N)).^2;
f = (0:N-1) / N * os * p.symbol_rate; f = min(f, os * p.symbol_rate - f);
verifyEqual(tc, sum(H(f <= 0.5e6)) / sum(H), share, 'AbsTol', 2e-3);
q = p; q.gcs_ant_dbi = p.gcs_omni_dbi;
verifyEqual(tc, power_step_db(q), floor((p.gcs_pmax_dbm - p.gcs_papr_db - p.gcs_pt_dbm) / 0.25) * 0.25, 'AbsTol', 1e-12);
verifyEqual(tc, p.gcs_papr_db, papr_db(p));
verifyTrue(tc, p.gcs_papr_db > 4 && p.gcs_papr_db < 6);
txf = comm.RaisedCosineTransmitFilter('RolloffFactor', p.rolloff, 'FilterSpanInSymbols', p.filter_span, ...
    'OutputSamplesPerSymbol', p.sps);
y = txf(pskmod(randi(RandStream('mt19937ar', 'Seed', 2), [0 3], 4096, 1), 4, pi/4));
a = abs(y(p.filter_span * p.sps + 1:end)).^2;
verifyLessThanOrEqual(tc, 10*log10(max(a) / mean(a)), p.gcs_papr_db + 0.3);
o = rmfield(p, {'gcs_pmax_dbm', 'gcs_step_db'}); o.cm_power_db = 6; o.gcs_eirp_cap_dbm = 10 + 10*log10(1.25);
verifyEqual(tc, power_step_db(o), 10*log10(1.25) + 4, 'AbsTol', 1e-12);    % without the radio fields: its next step under the cap
ton = p.air_symbols / p.symbol_rate;
verifyLessThanOrEqual(tc, ton, 10e-3);                                       % Tx-sequence
verifyGreaterThanOrEqual(tc, p.cycle_s - ton, max(ton, 3.5e-3));             % Tx-gap
verifyLessThanOrEqual(tc, 10^((p.gcs_eirp_cap_dbm - 20) / 10) * ton / p.cycle_s, 0.1);   % medium utilisation
end

function test_jam_timing(tc)
% Gated jammers per flight, from the flight's own 'jam' stream: the sweep period uniform
% in 20-83.5 ms, its phase in [0, T), the burst phase in [0, 1); fixed: the shortest period
% at phase 0. The sweeper covers our channel for (4 + 1.25) MHz / 1 GHz/s = 5.25 ms of
% each sweep; with frequency diversity on a carrier 25 MHz away never on both at once, on
% one 2 MHz away from 2 ms on.
p = base_params();
W = cell2mat(arrayfun(@(s) jam_timing(s, p.sweep_period_s), (1:4000)', 'UniformOutput', false));
verifyTrue(tc, all(W(:, 1) >= 20e-3 & W(:, 1) <= 83.5e-3));
verifyTrue(tc, all(W(:, 2) >= 0 & W(:, 2) < W(:, 1) & W(:, 3) >= 0 & W(:, 3) < 1));
verifyEqual(tc, mean(W(:, 1)), mean(p.sweep_period_s), 'AbsTol', 1e-3);
u = rand(seed_stream(17, 'jam'), 1, 3);
T = 20e-3 + 63.5e-3 * u(1);
verifyEqual(tc, jam_timing(17, p.sweep_period_s), [T, T * u(2), u(3)], 'AbsTol', 1e-15);
d = flight_draws(17, 100, p);
verifyEqual(tc, d.jam, [T, T * u(2), u(3)], 'AbsTol', 1e-15);
p.jam_timing_random = false;
d = flight_draws(17, 100, p);
verifyEqual(tc, d.jam, [20e-3 0 0]);
verifyEqual(tc, sweep_window_s(p), [0 5.25e-3], 'AbsTol', 1e-15);
p.sweep_fdiv = true;
g = sweep_window_s(p);
verifyGreaterThanOrEqual(tc, g(1), g(2));
p.fdiv_spacing_hz = 2e6;
verifyEqual(tc, sweep_window_s(p), [2e-3 5.25e-3], 'AbsTol', 1e-15);
verifyEqual(tc, threat_active('sweeping_jammer', [0 0.05 0.1 1]), [false false true true]);   % labels as the WLAN's
end

function test_sweep_hit_share(tc)
% The sweeping jammer counts in about 13% of the frames (Liu et al.'s 5.25 ms window per
% 20-83.5 ms sweep): the share the frames of seeded flights, a cycle apart on the channel
% clock, have with at least 10% of their air time inside the window; the dataset flies its
% cells 1/share times the sub-runs.
p = base_params();
h = sweep_hit_share(p);
verifyGreaterThan(tc, h, 0.10); verifyLessThan(tc, h, 0.16);
g = sweep_window_s(p); ta = p.air_symbols / p.symbol_rate;
J = cell2mat(arrayfun(@(x) jam_timing(x, p.sweep_period_s), (1:4000)', 'UniformOutput', false));
t = (0:19) * p.cycle_s + linspace(0, ta, 200)';                  % air time of 20 frames
on = zeros(4000, 20);
for i = 1:4000
    u = mod(t + J(i, 2), J(i, 1));
    on(i, :) = mean(u >= g(1) & u < g(2), 1);
end
verifyEqual(tc, mean(on(:) >= 0.1), h, 'AbsTol', 0.01);
verifyEqual(tc, round(6 / h), 45, 'AbsTol', 3);
end

function test_receiver_coherence_tdl(tc)
% With the delay line, the production channel, the quiet slot of a jammer at a low
% trained level (4 dB) is still more coherent than the clean link's on the same five
% flights.
p = base_params(); p.quiet_build = true; p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false;
p.gcs_tracked = false; p.seed = 11; p.k_random = false; p.gcs_aoa_random = false; p.body_random = false;
p.tdl = true;
mdl = 'UAV_GCS_Threat_Link';
CS = 11:15; coh = zeros(2, numel(CS)); thr = {'none', 'jamming'};
for j = 1:2
    p.active_threat = thr{j}; p.jsr_db = 4;
    evalc('build_threat_model(p)');
    set_param([mdl '/AWGN'], 'SNR', num2str(12 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps)), 'SignalPower', num2str(1/p.sps));
    for k = 1:numel(CS)
        link_seed(mdl, CS(k), 160);
        F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(10 * p.frame_duration)), p, 20);
        coh(j, k) = mean(F.coh, 'omitnan');
    end
    close_system(mdl, 0);
end
verifyGreaterThan(tc, mean(coh(2, :)) - mean(coh(1, :)), 0.10);
end

function test_gated_jammers(tc)
% In the model, on the channel clock (frames 20 ms apart): the sweeping jammer is on the
% samples whose time falls in its window of the sweep, with the flight's period and phase
% of the 'Gate' block, so a frame is hit whole, in part or not at all, and its on-air
% share is the share of the window; the frames outside are clean. With frequency
% diversity (25 MHz) it never hits, and with FEC every frame of a run with the pools'
% stop time (pool_cell.m) carries a whole packet. The noise bursts start at the flight's
% phase.
p = base_params(); p.quiet_build = true; p.active_threat = 'sweeping_jammer'; p.jsr_db = 16; p.seed = 11;
p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false; p.gcs_tracked = false; p.k_random = false;
p.gcs_aoa_random = false; p.body_random = false; p.wobble_random = false; p.jam_timing_random = false;
mdl = 'UAV_GCS_Threat_Link'; nfr = 8; gate = [25e-3 0.2e-3 0];
fs = p.symbol_rate * p.sps; ns = p.air_symbols * p.sps;
t = (0:ns-1)' / fs + (0:nfr-1) * round(p.cycle_s * fs) / fs;
for fdiv = [false true]
    q = p;
    if fdiv, q = apply_countermeasure(p, 'sweeping_jammer', 'freq_diversity+fec_interleave'); end
    evalc('build_threat_model(q)');
    set_param([mdl '/AWGN'], 'SNR', num2str(15 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps)), 'SignalPower', num2str(1/p.sps));
    link_seed(mdl, 11, 160);
    set_param([mdl '/Gate'], 'Value', mat2str(gate));
    F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str((nfr - 1) * p.frame_duration)), q, 20);   % frames at 0 .. stop
    g = sweep_window_s(q); ph = mod(t + gate(2), gate(1));
    a = mean(ph >= g(1) & ph < g(2), 1);
    verifyEqual(tc, F.nf, nfr);
    verifyEqual(tc, F.act, a, 'AbsTol', 1e-9);
    if fdiv
        verifyEqual(tc, F.act, zeros(1, nfr));
        verifyEqual(tc, F.ber, zeros(1, nfr));
    else
        verifyEqual(tc, [nnz(a == 1), nnz(a == 0), nnz(a > 0 & a < 1)], [2 5 1]);
        verifyGreaterThan(tc, min(F.ber(a == 1)), 1e-2);
        verifyLessThan(tc, mean(F.ber(a == 0)), 1e-3);
    end
    close_system(mdl, 0);
end
p.active_threat = 'noise_burst';
evalc('build_threat_model(p)');
set_param([mdl '/AWGN'], 'SNR', num2str(30 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps)), 'SignalPower', num2str(1/p.sps));
link_seed(mdl, 11, 160);
pw = zeros(1, 2);
for k = 1:2
    set_param([mdl '/Gate'], 'Value', mat2str([20e-3 0 0.5 * (k - 1)]));
    out = sim(mdl, 'StopTime', num2str(2 * p.frame_duration));
    Y = out.get('Rx_IQ');
    pw(k) = mean(abs(Y(1:100, 1, 1)).^2);       % the first frame's quiet slot: bursts from sample 0 at phase 0, from 200 at 0.5
end
verifyGreaterThan(tc, 10*log10(pw(1) / pw(2)), 10);
close_system(mdl, 0);
end

function test_fec_packets(tc)
% FEC: one codeword per 1000 + 32-bit packet over two frames (2064 coded bits, two frames
% of channel bits). A clean run decodes every frame; both frames carry their packet's BER
% and error, in steps of 1/1032, and only the second its CRC result (decoded there); a
% packet's result does not change with another packet's errors; scattered errors are
% repaired, a burst only when the receiver sees it (erased), a whole jammed frame not; a
% last frame without its pair is NaN.
p = base_params(); L = frame_layout(p); bpf = p.frame_length; nf = 20; d = p.filter_span / 2;
rs = RandStream('mt19937ar', 'Seed', 3);
tx = randi(rs, [0 1], nf * bpf, 1);
iq = ones(L.air * p.sps, nf);
[b, f, c] = fec_packets(tx, tx, iq, p, nf);
verifyEqual(tc, [b; f], zeros(2, nf));
verifyEqual(tc, c(2:2:nf), zeros(1, nf / 2));
verifyTrue(tc, all(isnan(c(1:2:nf))));
verifyEqual(tc, [crc32_fail(tx(1:1000), zeros(bpf, 1)), crc32_fail(tx(1:1000), [1; zeros(bpf - 1, 1)])], [0 1]);
rx = tx;
i1 = randperm(rs, 2 * bpf, 10); rx(i1) = 1 - rx(i1);                   % packet 1: scattered errors
rx(2*bpf + (1:bpf)) = randi(rs, [0 1], bpf, 1);                          % frame 3 jammed whole
[b, f, c] = fec_packets(tx, rx, iq, p, nf);
verifyEqual(tc, b([1 2 5:nf]), zeros(1, nf - 2));
verifyGreaterThan(tc, b(3), 0);
verifyEqual(tc, [f(3) f(4) c(4)], [1 1 1]);
verifyEqual(tc, b(4), b(3));
verifyTrue(tc, isnan(c(3)));
verifyEqual(tc, b(3) * bpf, round(b(3) * bpf), 'AbsTol', 1e-9);
rx2 = rx; rx2(8*bpf + (1:2*bpf)) = randi(rs, [0 1], 2*bpf, 1);         % packet 5 jammed
b2 = fec_packets(tx, rx2, iq, p, nf);
verifyEqual(tc, b2([1:8 11:nf]), b([1:8 11:nf]));
verifyGreaterThan(tc, b2(9), 0);
s = 101:250;                                                             % 150 data symbols of frame 7, random bits
k = 6*bpf + reshape([2*s - 1; 2*s], [], 1);
rx3 = tx; rx3(k) = randi(rs, [0 1], numel(k), 1);
iq3 = iq;
for m = L.idx_data(s)' + d
    iq3((m-1)*p.sps + 1:m*p.sps, 7) = sqrt(10);                         % 10 dB above the rest: erased
end
b3 = fec_packets(tx, rx3, iq, p, nf);
verifyGreaterThan(tc, b3(7), 0);
b3 = fec_packets(tx, rx3, iq3, p, nf);
verifyEqual(tc, b3, zeros(1, nf));
b4 = fec_packets(tx(1:19*bpf), tx(1:19*bpf), iq(:, 1:19), p, 19);
verifyEqual(tc, b4(1:18), zeros(1, 18));
verifyTrue(tc, isnan(b4(19)));
end

function test_packet_loss_once(tc)
% A lost packet is one packet: the slack of the packet-loss criterion is two frames with
% FEC (a packet over two frames) and one frame without; the monitor counts a lost coded
% packet once, at its second frame (decoded there: a result on its first frame is not
% read), so one lost packet does not degrade a coded link and two do, while an uncoded
% link counts its frames.
verifyEqual(tc, packet_share({'no_action', 'power_control+fec_interleave'}, 20), [1 2] / 20);
verifyEqual(tc, packet_share('fec_interleave', 57), 2 / 56);
A = policy_actions(); ic = find(strcmp(A, 'fec_interleave')); iu = find(strcmp(A, 'no_action'));
PP = struct('actions', {A}, 'classes', {{'none', 'jamming'}}, 'sps', 4, 'bps', 2, 'maha_thr', -Inf);
nF = numel(link_features('names'));
crc = [0 0 0 0 1 1 0 0; 0 0 0 0 1 1 1 1; 0 0 0 0 1 1 0 0];               % coded, coded, uncoded episode
mem = policy_monitor('init', 3, numel(A));
for t = 1:8
    obs = struct('probs', repmat([1 0], 3, 1), 'unknown', false(3, 1), 'feat', zeros(3, nF), ...
        'cfg_link', [ic; ic; iu], 'pkt', floor((t - 1) / 2) * ones(3, 1));
    obs.feat(:, feature_index('crc_fail')) = crc(:, t);
    obs.feat(:, feature_index('log_ber')) = -6;
    [mem, M] = policy_monitor('update', mem, obs, PP, [ic ic iu]);
    if t == 5, verifyEqual(tc, M.plr, [0; 0; 1/5], 'AbsTol', 1e-12); end
end
verifyEqual(tc, M.plr, [1/3; 2/3; 2/5], 'AbsTol', 1e-12);
verifyEqual(tc, M.degraded, [false true false]);
end

function [Y, H] = run_link(mdl, p, fd, kfac, rho, att, body, nfr)
% Received IQ (samples x antennas x frames) and channel estimates of one flight of the
% built model at seed 11, its blocks then set by hand.
link_seed(mdl, 11, fd);
set_param([mdl '/Kfac'], 'Value', mat2str(kfac));
set_param([mdl '/Corr'], 'Value', num2str(rho));
set_param([mdl '/Att'], 'Value', mat2str(att));
set_param([mdl '/Body'], 'Value', mat2str(body, 10));
out = sim(mdl, 'StopTime', num2str(nfr * p.frame_duration));
Y = out.get('Rx_IQ'); H = out.get('Rx_H');
end

function b = link_ber(mdl, p, ebno, seeds, nfr)
% BER of the built model p at Eb/N0 ebno [dB] over the flights seeds, nfr frames each.
evalc('build_threat_model(p)');
set_param([mdl '/AWGN'], 'SNR', num2str(ebno + 10*log10(p.bits_per_symbol) - 10*log10(p.sps)), ...
    'SignalPower', num2str(1/p.sps));
e = 0; n = 0;
for s = seeds
    link_seed(mdl, s, 160);
    out = sim(mdl, 'StopTime', num2str(nfr * p.frame_duration));
    tx = double(squeeze(out.get('tx_bits_out'))); rx = double(squeeze(out.get('rx_bits_out')));
    L = min(numel(tx), numel(rx));
    e = e + sum(tx(1:L) ~= rx(1:L)); n = n + L;
end
close_system(mdl, 0);
b = e / n;
end

function v = lead_dir(Y)
% Leading eigenvector of the spatial covariance of samples x antennas x frames.
R = 0;
for f = 1:size(Y, 3), R = R + Y(:, :, f).' * conj(Y(:, :, f)); end
[V, D] = eig((R + R') / 2);
[~, i] = max(real(diag(D)));
v = V(:, i);
end

function c = frame_corr(H)
% Correlation of the first channel estimate of consecutive frames (antennas x blocks x frames).
h = squeeze(H(:, 1, :));
c = abs(sum(sum(conj(h(:, 1:end-1)) .* h(:, 2:end)))) / sum(vecnorm(h(:, 1:end-1)) .* vecnorm(h(:, 2:end)));
end

function p = base_params()
evalc('init_params');
p = load('params.mat').params;
end

function c = nthout(k, f, varargin)
% Outputs k of f(varargin{:}) in a cell array.
out = cell(1, max(k));
[out{:}] = f(varargin{:});
c = out(k);
end

function [PP, K] = toy_world(crc_fails, hop_only)
% Frame pools of one flight: the clean link, and a jammer that only channel_switch and
% freq_diversity escape (hop_only: channel_switch alone); crc_fails false lets the jammed
% frames pass their CRC.
if nargin < 2, hop_only = false; end
A = policy_actions(); nA = numel(A); names = link_features('names');
PP = struct('actions', {A}, 'scen', {{'none', 'jamming'}}, 'ebno', [10 12], 'runs', {{101}}, 'F_SUB', 20, ...
    'classes', {{'none', 'jamming'}}, 'feat_names', {names}, 'maha_thr', 0, 'clean', [1e-6 1e-6], 'clean_fer', [0 0], ...
    'gp', ones(1, nA), 'bw', 1 + contains(A, 'freq_diversity'), 'pw', ones(1, nA), 'sps', 4, 'bps', 2);
PP.pools = cell(2, 2, nA, 1);
for sc = 1:2
    for a = 1:nA
        good = sc == 1 || contains(A{a}, 'channel_switch') || (~hop_only && contains(A{a}, 'freq_diversity'));
        F = zeros(20, numel(names)); F(:, feature_index('crc_fail')) = ~good && crc_fails;
        F(:, feature_index('log_ber')) = log10(max(0.1 * ~good, 1e-6));
        PP.pools(sc, :, a, 1) = {struct('ber', repmat(0.1 * ~good, 20, 1), 'fer', repmat(single(~good), 20, 1), ...
            'run', 101 * ones(20, 1), 'probs', repmat(double([sc == 1, sc == 2]), 20, 1), 'maha', ones(20, 1), 'feat', F)};
    end
end
K = link_env('tables', PP);
end

function [ok, ch] = hold_config(PP, K, a, fdelay, D, T)
% A follower episode in which the policy holds configuration a from the onset (the
% first cycle): frames restored, and the cycles with a change or a hop.
spec = struct('scn', 2, 's', 1, 'onset', 1, 'follow', true, 'fdelay', fdelay, 'unk', false, 'T', T, 'r', 1, 'delay', D);
[E, ~] = link_env('reset', PP, K, spec, 1, RandStream('mt19937ar', 'Seed', 1));
ok = false(1, T); ch = ok;
for t = 1:T
    [E, ~, ~, info] = link_env('step', E, PP, K, a);
    ok(t) = info.restored; ch(t) = info.changed;
end
end

function [ok, a, pred, eff] = oracle_run(PP, K, spec)
% An episode driven by the one-step oracle (oracle_action.m): frames restored, its
% choices, the effective configuration it predicts for the frame each choice reaches
% the link on, and the link's effective configuration of every frame.
[E, ~] = link_env('reset', PP, K, spec, 1, RandStream('mt19937ar', 'Seed', 1));
[ok, a, pred, eff] = deal(zeros(1, spec.T));
for t = 1:spec.T
    [a(t), pred(t)] = oracle_action(E, K);
    [E, ~, ~, info] = link_env('step', E, PP, K, a(t));
    ok(t) = info.restored && info.restored_plr; eff(t) = info.cfg_eff;
end
end
