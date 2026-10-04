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
verifyEqual(tc, power_step_db(rmfield(p, 'gcs_ant_dbi')), p.cm_power_db);
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
% those within the false-alarm bound; else the lowest bound, committed only within it.
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
verifyEqual(tc, {d, m}, {'rule_sel', true});
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
% flights, all-success below N_MIN, false alarms against 5% at 172 flights. Two
% episodes per flight widen the interval to the hull; a rate with every flight at 100%
% takes the all-success bound. Packet loss of the clean link at 172 flights of 20
% frames: no loss and one lost frame commit, the verdict never improves as more frames
% are lost, and 5% loss is NOT COMMITTED.
vd = @(k, n) getfield(edge_verdict(double((1:n) <= k), ones(1, n), 1:n, 0.9, 'ge', true), 'verdict');
verifyEqual(tc, [vd(36, 36), vd(35, 36), vd(28, 36)], [1 0 -1]);
verifyEqual(tc, [vd(70, 72), vd(69, 72)], [1 0]);
verifyEqual(tc, vd(35, 35), 0);
fa = @(a) getfield(edge_verdict(double((1:172) <= a), ones(1, 172), 1:172, 0.05, 'le', true), 'verdict');
verifyEqual(tc, [fa(2), fa(3), fa(15), fa(16)], [1 0 0 -1]);
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
P = {'channel', 'awgn', 'bits', 'threat', 'aoa', 'k', 'yaw', 'corr', 'gcs', 'alt', 'speed'};
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
% Frame-draw seeds of the edge map's rollouts (edge_map.m: base + 1000 x (signalling
% delay index, at most 4, or base set, at most 99) + batch, below 1000): disjoint
% ranges, all below the first flight stream
b = sort(cellfun(@(x) str2double(x{1}), regexp(fileread(which('edge_map')), '(\d{5,6}) \+ 1000 \* ', 'tokens')));
verifyEqual(tc, b, [40000 90000 95000 200000]);
hi = b + 1000 * [5 5 5 100];
verifyTrue(tc, all(hi(1:end-1) <= b(2:end)));
verifyLessThan(tc, hi(end), seed_base(700001));
end

function test_draws_independent(tc)
% The draws of a flight are independent: our signal's K is uncorrelated with the
% heading rate and the other draws, and no draw repeats on another seed (the AoA of
% geometry r+12 is not the K of geometry r).
p = base_params();
[r, s, b] = ndgrid(1:99, 1:6, [5 14 16 17]);            % pool geometries, consecutive seeds along r
[S, v] = arrayfun(@(bi, si, ri) pool_seed(1, si, bi, ri, [0 1]), b(:), s(:), r(:));
K = cell2mat(arrayfun(@(x) channel_k(x, [0 1]), S, 'UniformOutput', false));
A = cell2mat(arrayfun(@(x) interferer_aoa(x, [0 1], 3), S, 'UniformOutput', false));
wmax = min(rad2deg(9.81 * tand(p.roll_max_deg) / p.turn_v_floor), p.yaw_rate_max);
w = arrayfun(@(x) heading_rate(x, 1, p), S) / wmax;     % 1 Hz: below the speed floor
rho = arrayfun(@(x) rx_correlation(x, [0 1]), S);
U = [K, A, (w + 1) / 2, rho, v];                        % the uniform behind every draw
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
p.k_random = false;
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
% receive filter, over one quiet slot: the estimation floor of thermal noise alone.
h = rcosdesign(p.rolloff, p.filter_span, p.sps, 'sqrt');
qn = p.quiet_symbols * p.sps; n0 = p.filter_span * p.sps;
rs = RandStream('mt19937ar', 'Seed', 3);
c = zeros(1, 1000);
for r = 1:numel(c)
    x = filter(h, 1, complex(randn(rs, n0 + qn, p.n_rx), randn(rs, n0 + qn, p.n_rx)));
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
verifyEqual(tc, [d1.k_int d1.aoa d1.yaw d1.rho d1.gcs_point_db], [d0.k_int d0.aoa d0.yaw d0.rho d0.gcs_point_db]);
d2 = flight_draws(77, 100, p, struct('ebno', 9, 'alt_m', NaN, 'k_sig_db', NaN, 'aoa1_deg', NaN, 'rho', NaN));
verifyEqual(tc, [d2.alt_m d2.k_sig d2.aoa d2.rho], [d0.alt_m d0.k_sig d0.aoa d0.rho]);
d4 = flight_draws(77, 100, p, struct('aoa1_deg', 12, 'rho', 0.5));
verifyEqual(tc, [d4.aoa d4.rho], [12 d0.aoa(2:end) 0.5]);
verifyEqual(tc, [d4.k_sig d4.k_int d4.yaw d4.alt_m], [d0.k_sig d0.k_int d0.yaw d0.alt_m]);
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
G = zeros(size(h)); A = G;
for i = 1:numel(h)
    d = flight_draws(1, 100, p, struct('ebno', e(i), 'alt_m', h(i)));
    G(i) = d.el_db; A(i) = d.gcs_amp;
end
verifyGreaterThanOrEqual(tc, min(G(:)), -1.1);
verifyLessThan(tc, min(G(:)), -1);                               % 120 m at 0.28 km
verifyEqual(tc, A, 10.^(G / 20), 'AbsTol', 1e-12);
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

function [PP, K] = toy_world(crc_fails)
% Frame pools of one flight: the clean link, and a jammer that only channel_switch and
% freq_diversity escape; crc_fails false lets the jammed frames pass their CRC.
A = policy_actions(); nA = numel(A); names = link_features('names');
PP = struct('actions', {A}, 'scen', {{'none', 'jamming'}}, 'ebno', [10 12], 'runs', {{101}}, 'F_SUB', 20, ...
    'classes', {{'none', 'jamming'}}, 'feat_names', {names}, 'maha_thr', 0, 'clean', [1e-6 1e-6], 'clean_fer', [0 0], ...
    'gp', ones(1, nA), 'bw', 1 + contains(A, 'freq_diversity'), 'pw', ones(1, nA), 'sps', 4, 'bps', 2);
PP.pools = cell(2, 2, nA, 1);
for sc = 1:2
    for a = 1:nA
        good = sc == 1 || contains(A{a}, 'channel_switch') || contains(A{a}, 'freq_diversity');
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
