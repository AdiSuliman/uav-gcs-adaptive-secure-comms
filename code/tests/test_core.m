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

function test_parallel_turn_owner(tc)
% The parallel turn is held only by a running MATLAB session under the recorded id that
% started before the turn file was written: this session's fresh turn is held; a file
% dated a minute before this session started, yet after the computer's last start (as
% after a Fast Startup power-on), or the id of a process of another image (4, the
% system), is free and taken over; a session that waits prints the holder every hour.
assumeTrue(tc, ispc);
f = [tempname '.txt']; me = feature('getpid');
fid = fopen(f, 'w'); fprintf(fid, '%d', me); fclose(fid);
verifyEqual(tc, parallel_turn('owner', f), me);
[~, out] = system(sprintf(['powershell -NoProfile -Command "$e = [datetime]''1970-01-01''; ' ...
    '[long]((Get-Process -Id %d).StartTime.ToUniversalTime() - $e).TotalMilliseconds; ' ...
    '[long]((Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime() - $e).TotalMilliseconds"'], me));
t = str2double(strsplit(strtrim(out)));                 % this session's start, the computer's last start [ms]
assertNumElements(tc, t, 2);
assumeGreaterThan(tc, t(1) - 60e3, t(2));
java.io.File(f).setLastModified(t(1) - 60e3);           % a minute before this session started
verifyEmpty(tc, parallel_turn('owner', f));
fid = fopen(f, 'w'); fprintf(fid, '%d', 4); fclose(fid);
assertEmpty(tc, parallel_turn('owner', f));
verifyEqual(tc, parallel_turn('take', f), me);
verifyEqual(tc, str2double(fileread(f)), me);
parallel_turn('give', f);
verifyFalse(tc, isfile(f));
verifyEmpty(tc, parallel_turn('owner', f));
src = fileread(which('parallel_turn'));
verifyNotEmpty(tc, strfind(src, 'toc(t0) >= 3600 * said'));
verifyNotEmpty(tc, strfind(src, '*win64*'));
end

function test_latency_load_logged(tc)
% KPI 7's timings carry the machine's load before and after them (machine_load.m), in
% latency.txt and beside KPI 7, as the unknown-threat candidates' timings do.
src = fileread(which('measure_latency'));
a = strfind(src, 'ld0 = machine_load();'); b = strfind(src, 'ld1 = machine_load();');
verifyNumElements(tc, a, 1); verifyNumElements(tc, b, 1);
verifyGreaterThan(tc, a, strfind(src, '%% 2. Timed cycles'));
verifyLessThan(tc, a, strfind(src, 'for di = 1:numel(devs)'));
verifyGreaterThan(tc, b, strfind(src, 'T.(dv) = struct('));
verifyLessThan(tc, b, strfind(src, '%% 3. Report'));
verifyNotEmpty(tc, strfind(src, 'LAT.load = struct(''before'', ld0, ''after'', ld1);'));
verifyNotEmpty(tc, strfind(src, 'rep{end+1} = LAT.load_text;'));
verifyNotEmpty(tc, strfind(fileread(which('measure_all_kpis')), 'det{end+1} = Lt.load_text;'));
end

function test_gui_bundle_drops_stale(tc)
% An optional result the export does not copy, missing or stale (result_status.m), leaves
% no older copy in the bundle: the console shows none, never an older number.
root = fullfile(tc.TestData.tmp, 'bundle_root'); tgt = fullfile(tc.TestData.tmp, 'bundle_target');
mkdir(fullfile(root, 'data')); mkdir(fullfile(root, 'results'));
params = struct('n_rx', 3); save(fullfile(root, 'params.mat'), 'params');
x = 1;
for f = {'trained_detector', 'trained_dqn', 'gui_norm_stats', 'ood_thresholds', 'fusion'}
    save(fullfile(root, 'data', [f{1} '.mat']), 'x');
end
save(fullfile(root, 'results', 'eval_detector_metrics.mat'), 'x');           % current: exported
save(fullfile(root, 'results', 'kpi_summary.mat'), 'x');                     % older than its latency: stale
java.io.File(fullfile(root, 'results', 'kpi_summary.mat')).setLastModified(0);
LAT = struct('n', 1); save(fullfile(root, 'results', 'latency.mat'), 'LAT'); % no identity: stale
dst = fullfile(tgt, 'rx3'); mkdir(fullfile(dst, 'data')); mkdir(fullfile(dst, 'results'));
y = 2;                                                                       % an older bundle
old = {'results/latency.mat', 'results/kpi_summary.mat', 'results/policy_evaluation.mat', ...
    'data/survivability_boundary.mat', 'results/eval_detector_metrics.mat'};
for f = old, save(fullfile(dst, f{1}), 'y'); end
w = warning('off', 'MATLAB:load:variableNotFound'); c = onCleanup(@() warning(w));
verifyWarning(tc, @() export_gui_bundle(tgt, root), 'export_gui_bundle:stale');
for f = old(1:4), verifyFalse(tc, isfile(fullfile(dst, f{1})), f{1}); end
verifyEqual(tc, load(fullfile(dst, 'results', 'eval_detector_metrics.mat')), struct('x', 1));
verifyTrue(tc, isfile(fullfile(dst, 'data', 'fusion.mat')));
end

function test_console_shadowing_rolls_in(tc)
% The console flies airframe shadowing as the evaluated flights do: a drawn turn the UAV
% rolls into (console_scenario.m) on flights selected as the pools select theirs
% (console_flights.m, hides_antenna.m): no antenna hidden before the event's frame, one
% hidden after it, none below the speed at which the level can occur; the live run, its
% lead-in and the responses fly that flight; the episode pools carry the antennas' gains
% and read the event's frame at the onset.
p0 = base_params(); C = decision_config();
DL = dataset_levels(); sev = struct();
for t = 1:numel(DL), sev.(DL(t).name) = struct('param', DL(t).param, 'levels', DL(t).levels); end
for th = {'airframe_shadowing', 'jamming+airframe_shadowing'}
    p = console_scenario(p0, sev, th{1}, 0, 72);
    verifyTrue(tc, p.yaw_random); verifyEqual(tc, p.roll_deg, 0);
    [fl, why] = console_flights(p, 9, 72, 1000, 2);
    verifyEmpty(tc, why); verifyNumElements(tc, fl.seed, 2);
    verifyEqual(tc, [fl.k fl.nf], [C.event_frame C.event_run]);
    verifyEqual(tc, str2double(fl.stop), (C.event_run - 1) * p.frame_duration, 'RelTol', 1e-6);
    fd = 72 / 3.6 * p.carrier_freq / p.c_light;
    for s = fl.seed
        d = flight_draws(s, fd, p, fl.geo);
        verifyGreaterThan(tc, d.roll_in(2), 0);                                 % rolls in
        verifyEqual(tc, d.hidden(1:fl.k - 1), zeros(1, fl.k - 1));              % the lead-in hides nothing
        verifyTrue(tc, any(d.hidden(fl.k:C.event_count) > 0));
    end
end
p = console_scenario(p0, sev, 'airframe_shadowing', 0, 10);
[fl, why] = console_flights(p, 9, 10, 1000, 1);
verifyEmpty(tc, fl); verifyNotEmpty(tc, why);
src = fileread(which('demo_gui'));
verifyNotEmpty(tc, strfind(src, '[~, FL] = simRun(env, pl, snr_dB, fl);'));
verifyNotEmpty(tc, strfind(src, '[out, F] = simRun(env, p, snr_dB, fl);'));
verifyNotEmpty(tc, strfind(src, '[out2, F2] = simRun(env, p2, snr_dB + g_db, fl);'));
verifyNotEmpty(tc, strfind(src, 'link_seed(env.modelName, fl.seed(1), p.fd_max, fl.geo);'));
verifyNotEmpty(tc, strfind(src, 'F.gant = [F.gant; single(Fr.gain_ant(:, v)'')];'));
verifyNotEmpty(tc, strfind(src, 'if isfinite(ev), k0 = ev - 2 - N_PRE; end'));
verifyNotEmpty(tc, strfind(src, 'if ~isfield(P{1}, ''gant''), remove(M, kk{1}); end'));
end

function test_v3d_inject_resets_event(tc)
% The 3D engine reads a flight from its event's frame only while it flies a rolling-in
% one: a threat injected after shadowing that moves to a shared flight clears the flag.
M = struct('split', 3, 'avail', 1:3);
M.PP.scen = {'none', 'airframe_shadowing', 'jamming'};
M.K.clean = 1; M.K.geo = cell(3, 3); M.K.geo(:, 3) = {[1 2]; [3 4]; [1 2]};
M.K.ev = {[], [], [NaN NaN 11 11]};
G = struct('r', 1, 'events0', {{}});
G.E = struct('scn', [1 1], 'onset', [inf inf], 't', [5 5], 'follow', [false false], 'unk', [false false], ...
    'fdelay', [3 3], 'hop_live', [-inf -inf], 'r', [1 1], 'ev', [false false], 'k0', [2 2]);
G = v3d_engine('inject', G, M, 'airframe_shadowing', false, false);
verifyEqual(tc, G.r, 3); verifyEqual(tc, G.E.ev, [true true]); verifyEqual(tc, G.E.k0, [4 4]);
G = v3d_engine('inject', G, M, 'jamming', false, false);
verifyEqual(tc, G.r, 1); verifyEqual(tc, G.E.ev, [false false]);
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

function test_rule_quiet_slot(tc)
% A degraded link read as clean while the quiet slot holds interference is interference
% on our channel (low delivery at a high signal level, Xu et al.): the rule leaves the
% channel instead of the generic diversity; below the alarm, or on a healthy link, not.
C = decision_config();
verifyEqual(tc, rule_based_policy('none', true, 0, 10, 5), 'channel_switch');
verifyEqual(tc, rule_based_policy('none', true, 10, 10, 5), 'channel_switch+spatial_diversity');
verifyEqual(tc, rule_based_policy('none', true, 0, 4, 5), 'freq_diversity+power_control');
verifyEqual(tc, rule_based_policy('none', true, 10, 4, 5), 'spatial_diversity+power_control');
verifyEqual(tc, rule_based_policy('none', false, 0, 10, 5), 'no_action');
verifyEqual(tc, rule_based_policy('benign_interference', true, 0, 0, 5), 'channel_switch');
verifyEqual(tc, rule_based_policy('unknown', true, 0, 10, 5), 'freq_diversity+power_control');
verifyEqual(tc, rule_based_policy('none', true, 0, C.q_alarm_db), 'channel_switch');          % default alarm
verifyEqual(tc, rule_based_policy('none', true, 0, C.q_alarm_db, NaN), 'channel_switch');
verifyEqual(tc, rule_based_policy('none', true, 0, C.q_alarm_db - 0.1), 'freq_diversity+power_control');
% through the decision cycle: the pools' alarm PP.q_thr reaches the rule
A = policy_actions();
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
na = find(strcmp(A, 'no_action'));
for qt = [8 12]
    PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'q_thr', qt);
    obs = struct('probs', double(strcmp(cls, 'none')), 'unknown', false, ...
        'feat', zeros(1, numel(link_features('names'))));
    obs.feat(feature_index('log_ber')) = -1; obs.feat(feature_index('crc_fail')) = 1;
    obs.feat(feature_index('q_iot')) = 10;
    mem = []; a = na;
    for k = 1:4, [a, mem] = policy_decide('rule', obs, a, mem, PP, []); end
    if qt < 10, verifyEqual(tc, A{a}, 'channel_switch'); else, verifyEqual(tc, A{a}, 'freq_diversity+power_control'); end
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

%% ---------- operator console ----------
function test_console_scenario(tc)
% Every combined threat of the decision layer builds in the console: each component at
% the selected level of its own severity axis, the components the detector classes that
% count as correct, and the countermeasures act on the combination.
p0 = base_params(); C = decision_config();
DL = dataset_levels(); sev = struct();
for t = 1:numel(DL), sev.(DL(t).name) = struct('param', DL(t).param, 'levels', DL(t).levels); end
verifyTrue(tc, any(cellfun(@(x) numel(strsplit(x, '+')) == 3, C.combos)));      % the triples are there
for i = 1:numel(C.combos)
    th = C.combos{i}; parts = strsplit(th, '+');
    [p, txt, fd, comps] = console_scenario(p0, sev, th, 3, 72);
    verifyEqual(tc, p.active_threat, th);
    verifyEqual(tc, comps, parts);
    verifyTrue(tc, all(isfield(sev, parts)));                                   % every component is a detector class
    verifyEqual(tc, fd, 20 * p0.carrier_freq / p0.c_light, 'RelTol', 1e-12);
    for j = 1:numel(parts)
        sv = sev.(parts{j});
        verifyEqual(tc, p.(sv.param), sv.levels(3), th);
        verifyTrue(tc, contains(txt, sprintf('%s=%g', sv.param, sv.levels(3))), th);
    end
    pn = console_scenario(p0, sev, th, 0, 72);                                  % nominal: init_params' values
    for j = 1:numel(parts), verifyEqual(tc, pn.(sev.(parts{j}).param), p0.(sev.(parts{j}).param)); end
    p2 = apply_countermeasure(p, th, 'channel_switch+spatial_diversity');
    verifyEqual(tc, p2.active_threat, th);
end
[p, txt, ~, comps] = console_scenario(p0, sev, 'none', 5, 0);
verifyEqual(tc, comps, {'none'}); verifyEqual(tc, txt, 'nominal'); verifyEqual(tc, p.fd_max, 0);
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

function test_fec_restoration_start(tc)
% After the link turns coded (a configuration with fec_interleave reaches it after one
% without) the first coded packet is decoded on the fourth coded frame: the three frames
% before are neither restored nor restored_plr, from the arrival of the change on (the
% signalling delay first); a change between coded configurations keeps the code running.
% The cycles to recover count them and the packet loss after recovery leaves them out.
[PP, K] = toy_world(true);
A = PP.actions; na = find(strcmp(A, 'no_action')); fc = find(strcmp(A, 'fec_interleave'));
fp = find(strcmp(A, 'power_control+fec_interleave')); cf = find(strcmp(A, 'channel_switch+fec_interleave'));
for D = [0 1]
    seq = [na na fc fc fc fc fc fp fp na fc fc fc fc];
    spec = struct('scn', 1, 's', 1, 'onset', 99, 'follow', false, 'fdelay', 0, 'unk', false, 'T', numel(seq), ...
        'r', 1, 'delay', D);
    [E, ~] = link_env('reset', PP, K, spec, 1, RandStream('mt19937ar', 'Seed', 1));
    ok = false(1, numel(seq)); gap = ok;
    for t = 1:numel(seq)
        [E, ~, ~, info] = link_env('step', E, PP, K, seq(t));
        ok(t) = info.restored && info.restored_plr; gap(t) = info.fec_gap;
    end
    g = false(1, numel(seq)); g(D + [3 4 5 11 12 13]) = true; g = g(1:numel(seq));
    verifyEqual(tc, gap, g, sprintf('D %d', D));
    verifyEqual(tc, ok, ~g, sprintf('D %d', D));
end
spec = struct('scn', 2, 's', 1, 'onset', 1, 'follow', false, 'fdelay', 0, 'unk', false, 'T', 12, 'r', 1, 'delay', 0);
R = rollout_policy('fixed', PP, K, spec, 1, [], struct('fixed', cf), 3);
verifyEqual(tc, [R.recovered, R.t_rec, R.held, R.lost_rec, R.n_rec], [1 3 1 0 9]);
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
% With fec_interleave on the link the CRC packet loss decides (more lost packets in the
% window than twice the clean coded link's loss, 0 without the pools, plus one loss event
% of two packets), from the first frame received with it: two lost packets after the
% arrival are not degraded, whatever the window held before and however high the channel
% BER; a third is.
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
deg = false(1, 4);
for k = 1:4                                                      % lost, received, lost, lost
    obs.feat(feature_index('crc_fail')) = k ~= 2;
    [m, M] = policy_monitor('update', m, obs, PP, cf); m = policy_monitor('change', m, false);
    deg(k) = M.degraded;
end
verifyEqual(tc, deg, [false false false true]);
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

function test_monitor_m_of_n(tc)
% 4-of-5 confirms on the fourth hostile cycle among five with one miss; 5-of-5 needs five
% hostile cycles in a row; a confirmation longer than the alarm memory stops.
A = policy_actions();
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'confirm', [2 2], 'alarm_mode', 'class');
hos = struct('probs', double(strcmp(cls, 'jamming')), 'unknown', false, 'feat', zeros(1, numel(link_features('names'))));
hos.feat(feature_index('log_ber')) = -6;
cln = hos; cln.probs = double(strcmp(cls, 'none'));
seq = [1 1 0 1 1 1 1 1 1];
first = zeros(1, 2); cf = {[4 5], [5 5]};
for j = 1:2
    own = struct('monitor', struct('alarm_mode', 'class', 'confirm', cf{j}, 'drop_db', []));
    m = []; c = false(size(seq));
    for k = 1:numel(seq)
        o = cln; if seq(k), o = hos; end
        [~, m, d] = policy_decide('rule_esc', o, 1, m, PP, [], own);
        c(k) = d.confirmed;
    end
    first(j) = find(c, 1);
end
verifyEqual(tc, first, [5 8]);
own = struct('monitor', struct('alarm_mode', 'class', 'confirm', [3 9], 'drop_db', []));
msg = '';
try, policy_decide('rule_esc', hos, 1, [], PP, [], own); catch e, msg = e.message; end
verifyTrue(tc, contains(msg, 'alarm memory'));
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
% quiet-slot threshold gives another, and pools and agent of two detectors stop the
% reading. The unknown-threat threshold is not part of it: the pools hold every frame's
% score, the threshold is compared at decision time (PP.maha_thr) and any retention is a
% quantile of the validation statistic (unk_threshold.m, as ood_thresholds.m).
FZ = struct('FM', struct('W', ones(3, 2)), 'N', 4, 'q_thr', 5.5); ood = struct('score', 'last', 'win', 3);
id = detector_id(1, ood, FZ);
verifyEqual(tc, detector_id(1, ood, FZ), id);
verifyEqual(tc, numel(id), 16);
verifyEqual(tc, nargin('detector_id'), 3);
o2 = ood; o2.win = 4; F2 = FZ; F2.N = 5; F3 = FZ; F3.FM.W(1) = 2; F4 = FZ; F4.q_thr = 6;
ids = {id, detector_id(2, ood, FZ), detector_id(1, o2, FZ), detector_id(1, ood, F2), ...
    detector_id(1, ood, F3), detector_id(1, ood, F4)};
verifyEqual(tc, numel(unique(ids)), 6);
v = sort(randn(1000, 1));
verifyEqual(tc, unk_threshold(v, 0.95), v(ceil((1 - 0.95) * 1000))); verifyEqual(tc, unk_threshold(v, 0.99), v(ceil((1 - 0.99) * 1000)));
src = fileread(which('ood_thresholds'));
verifyNotEmpty(tc, strfind(src, '''maha'', lowq(mw, 1 - retain), ''maha_val'', sort(mw(:))'));
verifyNotEmpty(tc, strfind(src, 'q = x(max(1, ceil(frac * numel(x))));'));
for f = {'link_env', 'policy_monitor'}                  % read at decision time
    verifyNotEmpty(tc, regexp(fileread(which(f{1})), '< PP\.maha_thr', 'once'), f{1});
end
for f = {'evaluate_policies', 'experiment_unknown_threat', 'experiment_combo_generalization', 'edge_map'}
    verifyNotEmpty(tc, strfind(fileread(which(f{1})), 'decision_settings(PP, '), f{1});
end
verifyNotEmpty(tc, strfind(fileread(which('train_dqn')), 'maha_thr = dec.maha_thr;'));
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

function test_rekey_pools(tc)
% A new fusion re-keys the pools of the same detector: only fuse, fuse_N, q_thr and
% det_id change and a backup is kept; a file without the keys is left as it is. Pools of
% another detector, with a field that might depend on the fusion or with a frame field
% that is not a per-frame output stop it, the file unchanged.
d = fullfile(tc.TestData.tmp, 'rekey'); mkdir(fullfile(d, 'data'));
c0 = cd(d); back = onCleanup(@() cd(c0));
ood = struct('score', 'last', 'win', 3); classes = {'none', 'jamming'}; trained_at = 7;
save('data/trained_detector.mat', 'ood', 'classes', 'trained_at');
T = struct('retain', 0.95, 'maha', -2, 'maha_val', [-3; -1], 'win', 3, 'score', 'last');
save('data/ood_thresholds.mat', 'T');
F0 = struct('FM', struct('mu', zeros(1, 11)), 'N', 1, 'q_thr', 4);
FM = struct('mu', zeros(1, 13)); N = 12; q_thr = 4.5;
save('data/fusion.mat', 'FM', 'N', 'q_thr');
Q = struct('probs', single([0.9 0.1]), 'maha', single(0), 'feat', single([1 2]), 'ber', 0, 'run', 1);
PP = struct('pools', {{Q, []}}, 'classes', {classes}, 'maha_thr', -2, 'unk_win', 3, 'fuse', F0.FM, 'fuse_N', 1, ...
    'q_thr', 4, 'det_id', detector_id(trained_at, ood, F0), 'created', 'x');
clean_ref = struct('ebno', 1);
save('data/policy_pools.mat', 'PP', 'clean_ref', '-v7.3');
CT = struct('pools', {{Q}}, 'runs', 1);
save('data/clean_test_pools.mat', 'CT', '-v7.3');
evalc('rekey_pools({''data/policy_pools.mat'', ''data/clean_test_pools.mat''})');
L = load('data/policy_pools.mat');
keys = {'fuse', 'fuse_N', 'q_thr', 'det_id'};
verifyEqual(tc, {L.PP.fuse, L.PP.fuse_N, L.PP.q_thr}, {FM, N, q_thr});
verifyEqual(tc, L.PP.det_id, detector_id(trained_at, ood, struct('FM', FM, 'N', N, 'q_thr', q_thr)));
verifyEqual(tc, rmfield(L.PP, keys), rmfield(PP, keys));
verifyEqual(tc, L.clean_ref, clean_ref);
b = dir('data/policy_pools_before_rekey_*.mat');
verifyNumElements(tc, b, 1);
verifyEqual(tc, load(fullfile('data', b(1).name)).PP, PP);
verifyEmpty(tc, dir('data/clean_test_pools_before_rekey_*.mat'));
evalc('rekey_pools({''data/policy_pools.mat''})');                 % already keyed: nothing to do
verifyNumElements(tc, dir('data/policy_pools_before_rekey_*.mat'), 1);
P2 = PP; P2.fused = 1;
P3 = PP; P3.pools{1}.cls = 1;
P4 = PP; P4.det_id = detector_id(8, ood, F0);
for c = {{P2, 'rekey_pools:field'}, {P3, 'rekey_pools:frame'}, {P4, 'rekey_pools:detector'}}
    S = struct('PP', c{1}{1});
    save('data/policy_pools.mat', '-struct', 'S', '-v7.3');
    verifyError(tc, @() rekey_pools({'data/policy_pools.mat'}), c{1}{2});
    verifyEqual(tc, load('data/policy_pools.mat').PP, c{1}{1});
end
% another unknown-threat threshold (a retention chosen later): the same detector, re-keyed,
% its decision-time threshold and validation statistic kept
P5 = PP; P5.maha_thr = -5; P5.maha_val = single([-6; -5; -1]); P5.unk_retain = 0.99; P5.pools{1}.mmse_pred = single(3);
delete('data/policy_pools_before_rekey_*.mat');
S = struct('PP', P5);
save('data/policy_pools.mat', '-struct', 'S', '-v7.3');
evalc('rekey_pools({''data/policy_pools.mat''})');
L = load('data/policy_pools.mat');
verifyEqual(tc, {L.PP.maha_thr, L.PP.maha_val, L.PP.unk_retain, L.PP.fuse_N}, {-5, single([-6; -5; -1]), 0.99, N});
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

function test_det_layers(tc)
% DET over every flight, DET_h over the harmed ones and DET_u, the third output, over the
% unharmed ones (edge_map.m's three detection layers): 36 harmed flights detected on
% every cycle and 36 unharmed ones on none.
n = 72; harm = (1:n) <= 36;
F = struct('det_k', 10 * harm, 'det_n', 10 * ones(1, n), 'geo', 1:n, 'harm', harm);
TGT = struct('det', 0.9);
[d, dh, du] = det_layers(F, TGT, 500);
verifyEqual(tc, [d.value, dh.value, du.value, dh.n, du.n], [0.5 1 0 36 36], 'AbsTol', 1e-12);
verifyEqual(tc, [dh.verdict, du.verdict, d.verdict], [1 -1 -1]);
[d2, dh2] = det_layers(F, TGT, 500);
verifyEqual(tc, [d2.value, dh2.value], [d.value, dh.value]);
src = fileread(which('edge_map'));
verifyTrue(tc, contains(src, '[BL.det(i, s), BL.deth(i, s), BL.detu(i, s)] = det_layers(F, TGT, B);'));
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
verifyEqual(tc, numel(names), 23);
verifyEqual(tc, raw(feature_index({'q_sfm', 'q_par', 'duty', 'edges', 'est_margin'})), zeros(1, 5));   % not measured: 0
M.q_sfm = 0.01 * ones(1, n); M.q_par = 0.7 * ones(1, n); M.duty = 0.4 * ones(1, n); M.edges = 3 * ones(1, n);
M.est_margin = 12 * ones(1, n);
raw = link_features(M, 10, 10);
verifyEqual(tc, raw(feature_index({'q_sfm', 'q_par', 'duty', 'edges', 'est_margin'})), [0.01 0.7 0.4 3 12]);
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

function test_iforest_fast(tc)
% The packed isolation forest (iforest_pack.m, iforest_score.m) gives the scores of
% isanomaly: a constant predictor dropped at training, a missing value, one frame or many.
rng(2);
F = iforest([randn(600, 2), ones(600, 1), randn(600, 1)], 'NumLearners', 40, 'NumObservationsPerLearner', 256);
P = iforest_pack(F);
X = [3 * randn(4, 200), [NaN; 0; 1; 0]];
[~, a] = isanomaly(F, X');
verifyEqual(tc, iforest_score(P, X), a(:)', 'AbsTol', 1e-12);
[~, a1] = isanomaly(F, X(:, 7)');
verifyEqual(tc, iforest_score(P, X(:, 7)), a1, 'AbsTol', 1e-12);
M = struct('candidates', {{'last_or_if'}}, 'mu', {{zeros(2, 1)}}, 'P', {{eye(2)}}, ...
    'zs', struct('last', [0 1], 'iforest', [0 1]), 'forest', F);
Z = {randn(2, 201)};
S0 = ood_score_set(M, Z, X, {'last_or_if'});
M.forest_pack = P;
S1 = ood_score_set(M, Z, X, {'last_or_if'});
verifyEqual(tc, S1.last_or_if, S0.last_or_if, 'AbsTol', 1e-12);
end

function test_ood_latency_budget(tc)
% KPI 7 budget of the unknown-threat score (kpi7_admit.m): half of the 10 ms
% median and 20 ms p95 targets; the selection (ood_select.m) never picks a candidate
% over it, for the production pair nor for the nested estimate.
[ok, B] = kpi7_admit([1.2 4.9 5.1 3.0 85.8], [2.0 9.9 6.0 10.5 95.8]);
verifyEqual(tc, ok, [true true false false false]);
verifyEqual(tc, [B.det_median_ms B.det_p95_ms], [5 10]);
Mp = [0.70 0.90 0.75; 0.74 0.88 0.60; 0.68 0.91 0.80];   % threats x pairs; pair 2 best but over the budget
[b, nb] = ood_select(Mp, [true false true]);
verifyEqual(tc, b, 3);
verifyEqual(tc, nb, [1 3 1]);                         % chosen on the other threats, within the budget
[b, nb] = ood_select(Mp, true(1, 3));
verifyEqual(tc, b, 2); verifyEqual(tc, nb, [2 2 2]);
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
verifyEqual(tc, size(M.te), [NE numel(temporal_evidence('names', 0))]);
verifyTrue(tc, all(cont <= nS));
verifyFalse(tc, any(M.alarm));                       % clean class, low BER: no alarm
% the history of one episode never mixes with another's
obs.feat(2, feature_index('sinr')) = 7;
[mem, M] = policy_monitor('update', mem, obs, PP, ones(1, NE));
st = policy_state(mem, ones(1, NE), M.confirmed, nA);
nObs = nC + 14 + numel(temporal_evidence('names', 0)); isinr = nC + 5;
verifyEqual(tc, st(isinr, :), [0 7 0]);              % newest cycle
verifyEqual(tc, st(nObs + isinr, :), [0 0 0]);       % previous cycle
end

%% ---------- receiver measurements on the real link ----------
function test_slot_and_burst_measurements(tc)
% A tone is one spectral line with a constant envelope in the quiet slot (Shahriar et
% al., eq. 19); a counterfeit of our modulation is flat over its band and not constant;
% thermal noise is flat. WLAN packets fill part of a frame and their edges show inside
% it (busy share and energy edges, Cheema & Salous; Grimaldi et al.); on this flight
% every frame under Xu et al.'s random jammer (its first, 50%) shows edges; the clean link
% none.
p0 = base_params(); mdl = 'UAV_GCS_Threat_Link';
TH = {'none', 'tone_jamming', 'spoofing', 'benign_interference', 'noise_burst'};
F = struct();
for t = 1:numel(TH)
    p = p0; p.quiet_build = true; p.active_threat = TH{t}; p.seed = 11; p.benign_int_db = 12; p.spoof_sir_db = 16;
    p.cal_random = false;                       % the measurements against an exact floor (calibration: test_level_calibration)
    evalc('build_threat_model(p)');
    set_link_snr(mdl, 12 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
    link_seed(mdl, 11, 160);
    if strcmp(TH{t}, 'noise_burst'), set_param([mdl '/Gate'], 'Value', mat2str([20e-3 0 0.5 0.5])); end
    F.(TH{t}) = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(10 * p.frame_duration)), p, 20);
    close_system(mdl, 0);
end
md = @(t, f) median(F.(t).(f));
verifyGreaterThan(tc, md('none', 'q_sfm'), 0.7);
verifyLessThan(tc, md('tone_jamming', 'q_sfm'), 0.05);
verifyGreaterThan(tc, md('spoofing', 'q_sfm'), 2 * md('tone_jamming', 'q_sfm'));
verifyLessThan(tc, md('tone_jamming', 'q_par'), 2);
verifyGreaterThan(tc, md('spoofing', 'q_par'), md('tone_jamming', 'q_par') + 1.5);
verifyEqual(tc, [max(F.none.duty), max(F.none.edges)], [0 0]);
verifyEqual(tc, md('tone_jamming', 'duty'), 1);
B = F.benign_interference;
verifyTrue(tc, any(B.duty > 0 & B.duty < 1 & B.edges >= 1));
c = corrcoef(B.duty, B.act); verifyGreaterThan(tc, c(1, 2), 0.8);
verifyGreaterThanOrEqual(tc, min(F.noise_burst.edges), 1);
verifyGreaterThan(tc, md('none', 'est_margin'), 10);
end

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
    'body', 'wobble', 'cal', 'roll', 'idle', 'amb'};
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
[s, r, b, f] = ndgrid(1:6, 1:100, [4 15], [3 5]);       % clean-link geometries 101-300 (families 3 and 5)
S = [S; arrayfun(@(si, ri, bi, fi) pool_seed(fi, si, bi, ri), s(:), r(:), b(:), f(:))];
[t, li, s] = ndgrid(1:20, 1:8, 1:6);                    % survivability map: entries, levels, Eb/N0
S = [S; 900000 + 1000*t(:) + 10*li(:) + s(:); 700000 + (1:5)'];
k = (1:99999)';
S = [S; 3000000 + k; 4000000 + k; 5000000 + k];         % dataset, unseen Eb/N0 and unseen severity runs
S = [S; 3500000 + k; 4500000 + k; 5500000 + k];         % the second test set and the second B4 and B4s readings
S = [S; 6500000 + k];                                   % the third test set (B3m)
S = [S; 6000000 + k];                                   % the fourth test set (B3q)
src = fileread(which('run_dataset_sweep'));              % every dataset stream of the sweep is listed above
s0 = cellfun(@(c) str2double(c{1}), regexp(src, 'SEED0\s*=\s*(\d+);', 'tokens'));
verifyEqual(tc, sort(s0), [3000000 3500000 6000000 6500000]);
verifyEqual(tc, numel(unique(S)), numel(S));
verifyLessThan(tc, max(S), 2^26);
N = seed_base(S) + off;
verifyEqual(tc, numel(unique(N(:))), numel(N));
verifyLessThan(tc, max(N(:)), 2^32);
% The candidates of the airframe-shadowing pool flights (shadow_pool_seed.m): a range of their
% own per (group, Eb/N0, seed block), every range above every seed above, the largest below
% 2^26 and its streams below 2^32 (a flight seed owns 64 streams, so distinct seeds never
% share one); B4's and B4s' candidates lie inside their block ranges (4 550 001-4 599 999,
% 5 550 001-5 599 999), above the blocks' own seeds
[g, s, b] = ndgrid(1:8, 1:8, [1 5 10 14 16 17 18 19]);
lo = arrayfun(@(gi, si, bi) shadow_pool_seed(gi, si, bi, 1), g(:), s(:), b(:));
hi = arrayfun(@(gi, si, bi) shadow_pool_seed(gi, si, bi, 99999), g(:), s(:), b(:));
[lo, o] = sort(lo); hi = hi(o);
verifyEqual(tc, hi - lo, 99998 * ones(size(lo)));
verifyTrue(tc, all(hi(1:end-1) < lo(2:end)));
verifyGreaterThan(tc, lo(1), max(S));
verifyLessThan(tc, hi(end), 2^26);
verifyLessThan(tc, seed_base(hi(end)) + 63, 2^32);
verifyError(tc, @() shadow_pool_seed(1, 1, 4, 1), ?MException);       % the clean pools' blocks hold none
verifyError(tc, @() shadow_pool_seed(1, 1, 17, 100000), ?MException);
for f = {{'eval_unseen_snr', 'SEED_SHD  = SEED0 + 50000;'}, {'eval_unseen_severity', 'SEED_SHD = SEED0 + 50000;'}}
    src = fileread(which(f{1}{1}));
    verifyNotEmpty(tc, strfind(src, f{1}{2}), f{1}{1});
    verifyNotEmpty(tc, regexp(src, 'hiding_flight\(p, \w+(\(s\))?, SEED_SHD, jsh, 49999\)', 'once'), f{1}{1});
end
% the permutation streams of the shadowing groups' designs (build_policy_pools.m,
% build_check_pools.m) stay distinct from the designs' own and below every flight stream
[s, sp, gi, pt] = ndgrid(1:8, 1:5, 1:7, 1:2);
L = [7100000 + 100 * s(:) + 10 * (gi(:) + 1) + sp(:) + 5 * (pt(:) - 1); ...
    reshape(7100000 + 100 * (1:8)' + [1:5, 11:15], [], 1); reshape(7200000 + 100 * (1:8)' + (0:7), [], 1)];
verifyEqual(tc, numel(unique(L)), numel(L));
verifyLessThan(tc, max(L), seed_base(700001));
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
J = cell2mat(arrayfun(@(x) jam_timing(x, [0 1], [0 1], [0 0]), S, 'UniformOutput', false));
J(:, 2) = J(:, 2) ./ J(:, 1);
Kc = cell2mat(arrayfun(@(x) rand(seed_stream(x, 'cal'), 1, 3), S, 'UniformOutput', false));
Kc = [Kc, cell2mat(arrayfun(@(x) rand(seed_stream(x, 'roll'), 1, 3), S, 'UniformOutput', false))];   % the roll-in's draws
q = p; q.tdl_clip_ns = Inf;                             % no altitude: every channel on the omni fit
Z = cell2mat(arrayfun(@(x) delay_spread(x, NaN, 3, q), S, 'UniformOutput', false));
Z = 0.5 * erfc(-(log10(Z * 1e-9) - q.tdl_int_ds(1)) / sqrt(2 * q.tdl_int_ds(2)));
U = [K, A, (w + 1) / 2, rho, v, G, W, J, Z, B, Kc];     % the uniform behind every draw
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
verifyNotEmpty(tc, regexp(fileread(which('pool_layout')), 'sp == iSpd && sev\(c\) ~= nominal', 'once'));   % hover at every level
end

function test_receiver_measurements(tc)
p = base_params(); p.quiet_build = true; p.active_threat = 'none'; p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false; p.gcs_tracked = false; p.seed = 11;
p.k_random = false; p.gcs_aoa_random = false; p.body_random = false;
p.tdl = false;                                       % the measurements on the flat channel (the delay line: test_delay_line)
p.cal_random = false;                                % against an exact floor (calibration: test_level_calibration)
mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(p)');
snr = 12 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
set_link_snr(mdl, snr, p);
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
set_link_snr(mdl, snr, p);
link_seed(mdl, 11, 160);
F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(10 * p.frame_duration)), p, 20);
g = sort(F.gain_ant, 1);
verifyGreaterThan(tc, mean(g(2, :) - g(1, :) >= 15), 0.9);
verifySize(tc, F.bch, [9 * p.n_rx, F.nf]);                   % every antenna's channel record (branch_record.m)
verifyGreaterThan(tc, mean(all(isfinite(F.bch), 1)), 0.8);
verifyEqual(tc, F.bch(1:p.n_rx, :), F.gain_ant);
close_system(mdl, 0);
% an antenna hidden by the airframe stays far below the other over the frame: a turn of
% 20 deg with the GCS abeam (shadow_hidden.m)
p.active_threat = 'airframe_shadowing'; p.shadow_db = 20; p.roll_deg = 20;
evalc('build_threat_model(p)');
set_link_snr(mdl, snr, p);
link_seed(mdl, 11, 160);
F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(10 * p.frame_duration)), p, 20);
verifyGreaterThan(tc, median(F.branch_gap), 12);
verifyLessThan(tc, median(F.branch_dip), 10);         % no deep drop inside the frame, unlike a fault (> 10 dB)
verifyGreaterThan(tc, median(F.sinr_gap, 'omitnan'), 10);   % the other antenna, compared with the reference
verifyLessThan(tc, abs(median(F.sinr, 'omitnan') - sinr_clean), 3);   % the reference is the antenna the airframe does not hide
[~, hidden] = min(median(F.sinr_ant, 2, 'omitnan'));
verifyLessThan(tc, mean(F.ref == hidden), 0.1);      % the hidden antenna is not the reference
verifyEqual(tc, hidden, p.n_rx);                     % the GCS abeam: the aft end of the array
verifyEqual(tc, F.act, ones(1, F.nf));
close_system(mdl, 0);
% the attitude decides: the GCS ahead of the beam hides the aft end, behind it the front
% end; level flight hides none (no threat on the air)
for b = [40 -40]
    p.gcs_aoa_deg = b;
    evalc('build_threat_model(p)');
    set_link_snr(mdl, snr, p);
    link_seed(mdl, 11, 160);
    F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(4 * p.frame_duration)), p, 20);
    [~, hidden] = min(median(F.sinr_ant, 2, 'omitnan'));
    verifyEqual(tc, hidden, ternary_(b > 0, p.n_rx, 1));
    close_system(mdl, 0);
end
p.gcs_aoa_deg = 0; p.roll_deg = 0;
evalc('build_threat_model(p)');
set_link_snr(mdl, snr, p);
link_seed(mdl, 11, 160);
F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(4 * p.frame_duration)), p, 20);
verifyEqual(tc, F.act, zeros(1, F.nf));
verifyLessThan(tc, median(F.sinr_gap, 'omitnan'), 8);
close_system(mdl, 0);
% quiet slot: a reactive jammer is silent there, a continuous one is not
p.active_threat = 'reactive_jamming'; p.jsr_db = 16;
evalc('build_threat_model(p)');
set_link_snr(mdl, snr, p);
link_seed(mdl, 11, 160);
F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(10 * p.frame_duration)), p, 20);
verifyLessThan(tc, median(F.q_iot), 2);
verifyGreaterThan(tc, median(F.q_react), 10);
verifyLessThan(tc, abs(mean(F.coh) - coh_floor(p)), 0.06);   % silent there: thermal noise alone
close_system(mdl, 0);
p.active_threat = 'jamming';
evalc('build_threat_model(p)');
set_link_snr(mdl, snr, p);
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
    set_link_snr(mdl, E(ie) + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
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
sb = min(1, inband_cap_amp(30, 22, 30) * vertcat(D.cap_amp));
verifyLessThanOrEqual(tc, vertcat(D.cap_amp), vertcat(D.gcs_amp) .* min(vertcat(D.body_amp), [], 2) * (1 + 1e-9));   % its worst frame, the first one included
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
        verifyTrue(tc, contains(sfroot().find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/Threat']).Script, '* cap);'));
    end
    set_link_snr(mdl, 12 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
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
n = 12; nr = 3; C = 4; nF = numel(link_features('names'));
fade = 10 * log10(-log(rand(1, nr, n)));                       % Rayleigh power per cycle [dB]
sh = fade; sh(1, 2, :) = sh(1, 2, :) - 8;
P = repmat([0.7 0.1 0.1 0.1], 1, 1, n);
Fw = zeros(1, nF, n); Fw(1, feature_index('est_margin'), :) = 20;
nm = temporal_evidence('names', C); col = @(c) find(strcmp(nm, c));
xf = temporal_evidence(P, fade, Fw); xs = temporal_evidence(P, sh, Fw);
verifyEqual(tc, numel(xf), numel(nm)); verifyEqual(tc, numel(nm), C + 11);
verifyEqual(tc, xf(1:C), log([0.7 0.1 0.1 0.1]), 'AbsTol', 1e-9);
verifyGreaterThan(tc, xs(col('gap_w')), xf(col('gap_w')) + 4);           % gap of the local means
verifyGreaterThan(tc, xs(col('weak_w')), xf(col('weak_w')));             % the same antenna is the weakest
Fq = Fw; Fq(1, feature_index('q_iot'), :) = [5 5 5 0 0 0 5 5 5 0 0 0];
xq = temporal_evidence(P, fade, Fq);
verifyEqual(tc, xq(col('occ_w')), 0.5, 'AbsTol', 1e-12);                % share of cycles with quiet-slot interference
op = fade; op(1, 3, 1:3:end) = op(1, 3, 1:3:end) - 30;          % a connector open in every third cycle
xo = temporal_evidence(P, op, Fw);
verifyGreaterThan(tc, xo(col('drop_w')), 0.2);                           % the drops are counted
dp = zeros(1, n); dp(2:3:end) = 25;                            % open for part of other cycles: in-frame drops
Fd = Fw; Fd(1, feature_index('branch_dip'), :) = dp;
xp = temporal_evidence(P, fade, Fd);
verifyEqual(tc, xp(col('drop_w')), mean(dp >= 15), 'AbsTol', 0.1);
verifyLessThan(tc, xf(col('drop_w')), 0.2);                   % fading alone rarely drops 20 dB below the next
end

function test_branch_imbalance(tc)
% Willgert's reading (US 8,548,029, Table 1): a loss in series with one antenna is a
% steady offset with a small spread over its mean, a pattern effect a small mean with a
% large spread. The moment-method K (Aoki & Honda, eq. 2) follows the branch's own
% fading: a series loss keeps the line of sight, a shadowed antenna loses it.
rng(5);
n = 12; nr = 3; nF = numel(link_features('names'));
P = repmat([0.5 0.5], 1, 1, n);
nm = temporal_evidence('names', 2); col = @(c) find(strcmp(nm, c));
Fw = zeros(1, nF, n); Fw(1, feature_index('est_margin'), :) = 20;
K = 10^(15/10);                                                 % K 15 dB on every antenna
h = sqrt(K / (K + 1)) + sqrt(1 / (2 * (K + 1))) * (randn(1, nr, n) + 1j * randn(1, nr, n));
G = 20 * log10(abs(h));
Gf = G; Gf(1, 2, :) = Gf(1, 2, :) - 18;                         % an 18 dB fault
x = temporal_evidence(P, Gf, Fw);
verifyEqual(tc, x(col('off_w')), -18, 'AbsTol', 2);
verifyLessThan(tc, x(col('rat_w')), 0.3);
verifyGreaterThan(tc, x(col('k_w')), 8);
verifyEqual(tc, x(col('kv_w')), 1);
hs = sqrt(1 / 2) * (randn(1, 1, n) + 1j * randn(1, 1, n));      % shadowed: Rayleigh, 15 dB down
Gs = G; Gs(1, 2, :) = 20 * log10(abs(hs)) - 15;
xs = temporal_evidence(P, Gs, Fw);
verifyLessThan(tc, xs(col('k_w')), 5);
verifyGreaterThan(tc, xs(col('rat_w')), x(col('rat_w')));
Gp = G; Gp(1, 2, :) = Gp(1, 2, :) + reshape(4 * (-1) .^ (1:n), 1, 1, n);   % a pattern effect, +-4 dB
xp = temporal_evidence(P, Gp, Fw);
verifyLessThan(tc, abs(xp(col('off_w'))), 3);
verifyGreaterThan(tc, xp(col('rat_w')), 3);
Fl = Fw; Fl(1, feature_index('est_margin'), :) = -5;            % below the noise of its estimate: no K
xl = temporal_evidence(P, Gf, Fl);
verifyEqual(tc, [xl(col('k_w')), xl(col('kv_w'))], [0 0]);
Fb = Fw; Fb(1, feature_index('duty'), :) = linspace(0, 1, n);   % busy share of the window
xb = temporal_evidence(P, G, Fb);
verifyEqual(tc, xb(col('duty_w')), 0.5, 'AbsTol', 1e-12);
xg = temporal_evidence(P, G(:, 1, :), Fw);                     % one antenna: no other to compare
verifyEqual(tc, [xg(col('off_w')), xg(col('rat_w'))], [0 0]);
end

function test_fusion_target(tc)
% A WLAN frame without a packet keeps its per-frame label, but the fused decision is
% judged by its window: with a packet frame among the last N frames of its run the
% target is benign_interference.
cls = {'none', 'jamming', 'benign_interference'};
y   = [3 1 1 1 3 1   1 1 1];
run = [1 1 1 1 1 1   2 2 2];
pos = [1 2 3 4 5 6   3 1 2];
[yt, rk] = fusion_target(y, run, pos, 3, cls);
verifyEqual(tc, yt', [3 3 3 1 3 3   1 1 1]);
verifyEqual(tc, rk', [1 2 3 4 5 6   3 1 2]);
verifyEqual(tc, fusion_target(y, run, pos, 1, cls)', y);    % a window of one frame: the label
end

function test_fusion(tc)
% Two classes told apart only by the persistence gap: the fusion learns it. Input
% layout of fuse_classes.m: the window's C + 9 columns, then the current frame's C.
rng(4);
n = 400; y = [ones(n, 1); 2 * ones(n, 1)];
Z = [log(0.5) * ones(2 * n, 2), [randn(n, 1); 6 + randn(n, 1)], rand(2 * n, 8), log(0.5) * ones(2 * n, 2)];
FM = fuse_classes('fit', Z, y, 2, 1e-3);
[~, k] = fuse_classes('apply', FM, Z);
verifyGreaterThan(tc, mean(k == y), 0.95);
verifyError(tc, @() fuse_classes('apply', FM, Z(:, 1:end-2)), 'fuse_classes:columns');   % a fusion of another layout
end

function test_fusion_current_frame(tc)
% A sweeping jammer hits single frames. Over a window of 12 cycles the hit frame and
% its clean neighbours share the window's evidence; the current frame's own
% log-probabilities, the last C columns of the fusion input, tell them apart. The
% decision cycle (policy_monitor.m) builds the same input and the same decision.
rng(6);
C = 2; nr = 3; N = 12; nRun = 60; nF = 20; fn = link_features('names');
n = nRun * nF;
run = repelem((1:nRun)', nF); pos = repmat((1:nF)', nRun, 1);
y = ones(n, 1);
for r = 1:nRun, y((r - 1) * nF + [4 10 16] + randi([0 2], 1, 3)) = 2; end   % isolated hits, 4 frames apart or more
p2 = 0.02 + 0.38 * rand(n, 1); p2(y == 2) = 0.6 + 0.35 * rand(sum(y == 2), 1);
probs = [1 - p2, p2];
S = struct('run', run, 'pos', pos, 'gain_ant', randn(n, nr), 'feats_raw', zeros(n, numel(fn)), 'feat_names', {fn});
S.feats_raw(:, feature_index('est_margin')) = 20; S.feats_raw(:, feature_index('log_ber')) = -5;
Z = fuse_classes('windows', S, probs, N);
nT = numel(temporal_evidence('names', C)); nW = numel(window_cues('names'));
verifyEqual(tc, size(Z, 2), nT + nW + C);
verifyEqual(tc, Z(:, nT + nW + 1:end), log(probs), 'AbsTol', 1e-12);
tr = run <= nRun / 2; te = ~tr; yt = y(te);
FM = fuse_classes('fit', Z(tr, :), y(tr), C, 1e-3);
[~, k] = fuse_classes('apply', FM, Z(te, :));
verifyGreaterThan(tc, mean(k(yt == 2) == 2), 0.9);             % the hit frames
verifyGreaterThan(tc, mean(k(yt == 1) == 1), 0.9);             % their clean neighbours
Fw = fuse_classes('fit', Z(tr, 1:nT), y(tr), C, 1e-3);          % the window alone misses most hits
[~, kw] = fuse_classes('apply', Fw, Z(te, 1:nT));
verifyLessThan(tc, mean(kw(yt == 2) == 2), 0.5);
PP = struct('actions', {policy_actions()}, 'classes', {{'none', 'sweeping_jammer'}}, 'sps', 4, 'bps', 2, ...
    'maha_thr', 0, 'fuse', FM, 'fuse_N', N);
mem = policy_monitor('init', 1, numel(PP.actions));
r1 = find(run == nRun);
for j = 1:nF
    f = r1(j);
    obs = struct('probs', probs(f, :), 'unknown', false, 'feat', S.feats_raw(f, :), 'gant', S.gain_ant(f, :));
    [mem, M] = policy_monitor('update', mem, obs, PP, 1);
    verifyEqual(tc, M.probs, fuse_classes('apply', FM, Z(f, :)), 'AbsTol', 1e-9);
    verifyEqual(tc, M.cls, PP.classes(y(f)));
end
verifyEqual(tc, size(M.te), [1 nT - C]);                        % the agent's state keeps its size
end

function test_frame_rule_labels(tc)
% The per-frame network and its unknown-threat models learn what the frame itself holds (the
% frame rule: threat_active.m without the idle time); the fusion, the KPI 1 threshold and the
% readings of the system's decision keep the per-cycle labels.
act = [0 0.5 0 0.05]; ai = [0.3 0 0 0.2];
verifyEqual(tc, threat_active('sweeping_jammer', act, 1:4, 10, ai), logical([1 1 0 1]));   % per cycle
verifyEqual(tc, threat_active('sweeping_jammer', act, 1:4, 10), logical([0 1 0 0]));       % per frame
cls = {'none', 'sweeping_jammer'};
S = struct('Y', categorical([2; 2; 1; 2], 1:2, cls), 'Y_frame', categorical([1; 2; 1; 1], 1:2, cls));
F = frame_labels(S);
verifyEqual(tc, F.Y, S.Y_frame);
verifyError(tc, @() frame_labels(rmfield(S, 'Y_frame')), 'frame_labels:missing');
txt = fileread(which('run_dataset_sweep'));
verifyNotEmpty(tc, strfind(txt, 'labf(~threat_active(p.active_threat, F.act(v), v, tw)) = 1;'));
verifyNotEmpty(tc, strfind(txt, 'dataset.label_frame = D.label_frame(:);'));
verifyNotEmpty(tc, strfind(fileread(which('extract_spectrograms')), 'spec.Y_frame = categorical(ds.label_frame'));
txt = fileread(which('prepare_data'));
verifyNotEmpty(tc, strfind(txt, 'splits.(names{i}).Y_frame = sp0.Y_frame(m);'));
verifyNotEmpty(tc, strfind(txt, 'splits.test.Y_frame = sp0.Y_frame;'));          % splits_fresh.mat
verifyNotEmpty(tc, strfind(fileread(which('train_detector')), 'tr = frame_labels(sp.train); va = frame_labels(sp.val);'));
verifyNotEmpty(tc, strfind(fileread(which('ood_loto_split')), 'fresh = frame_labels(fresh);'));
verifyNotEmpty(tc, strfind(fileread(which('compare_architectures')), 'sp.test = frame_labels(sp.test);'));
for f = {'select_fusion', 'fused_class', 'detector_block', 'kpi_ebno'}            % per cycle
    verifyEmpty(tc, strfind(fileread(which(f{1})), 'frame_labels'), f{1});
end
end

function test_params_written_by_init_only(tc)
% The dataset sweep (A5, B3n) and the PHY validation (A4v) build their models in memory and
% never write params.mat, so a stop in the middle leaves A0's file; the stages that set their
% own onsets stop on a params.mat that does not put every threat on from the first frame.
for f = {'run_dataset_sweep', 'validate_phy'}
    s = fileread(which(f{1}));
    verifyEmpty(tc, strfind(s, 'save(''params.mat'''), f{1});
    verifyNotEmpty(tc, strfind(s, 'evalc(''build_threat_model(p)'')'), f{1});
    verifyEmpty(tc, strfind(s, 'evalc(''build_threat_model'')'), f{1});
end
p = base_params();
assert_frame1_onsets(p);                                         % A0's parameters pass
q = p; q.pl_onset_frames = p.pl_onset_det;
verifyError(tc, @() assert_frame1_onsets(q), 'assert_frame1_onsets:params');
q = p; q.fault_onset_frames = p.pl_onset_det;
verifyError(tc, @() assert_frame1_onsets(q), 'assert_frame1_onsets:params');
q = p; q.roll_in_frames = p.pl_onset_det;
verifyError(tc, @() assert_frame1_onsets(q), 'assert_frame1_onsets:params');
verifyError(tc, @() assert_frame1_onsets(rmfield(p, 'roll_in_frames')), 'assert_frame1_onsets:params');
for f = {'build_policy_pools', 'build_check_pools', 'build_clean_test_pools', 'measure_latency', 'threat_gallery'}
    verifyNotEmpty(tc, strfind(fileread(which(f{1})), 'assert_frame1_onsets(p0);'), f{1});
end
end

function test_monitor_class_reading(tc)
% KPI 1, its validation threshold, B4 and B4s read the monitor's class (policy_monitor.m):
% the fused class with the latched cause of a lost branch (latch_runs.m, fused_class.m), the
% fused class alone beside it. The latch over the shuffled frames of several runs is each
% run's latch in time order.
rng(3);
cls = {'none', 'antenna_fault', 'airframe_shadowing'};
n = 30; G1 = 0.3 * randn(n, 3); G1(10:end, 2) = G1(10:end, 2) - 15;   % an open connector at cycle 10
G2 = 0.3 * randn(n, 3);
P1 = repmat([0.1 0.4 0.5], n, 1); P2 = repmat([0.8 0.1 0.1], n, 1);   % the fusion leans to shadowing
[q1, c1] = onset_shape('sequence', G1, P1, cls, 5, 0);
[q2, c2] = onset_shape('sequence', G2, P2, cls, 5, 0);
o = randperm(2 * n)'; G = [G1; G2]; P = [P1; P2]; Q = [q1; q2]; Cz = [c1; c2];
run = [ones(n, 1); 2 * ones(n, 1)]; pos = [(1:n)'; (1:n)'];
[pl, cz] = latch_runs(P(o, :), run(o), pos(o), G(o, :), cls, 0, 5);
verifyEqual(tc, pl, Q(o, :), 'AbsTol', 1e-12);
verifyEqual(tc, cz, Cz(o));
verifyEqual(tc, latch_runs(P(o, :), run(o), pos(o), G(o, :), cls, 0), pl);   % the deployed heal by default
[k, kf] = fused_class(P1, struct('run', ones(n, 1), 'pos', (1:n)', 'gain_ant', G1), [], 1, cls);
verifyEqual(tc, kf, 3 * ones(n, 1));                             % the fused class alone
[~, ke] = max(q1, [], 2);
verifyEqual(tc, k, ke);                                          % the monitor's class
verifyEqual(tc, k(end), 2);                                      % the fault latched from its step
src = fileread(which('eval_detector'));
verifyNotEmpty(tc, strfind(src, ['latch_runs(double(Y_pred_prob''), sp.test.run, sp.test.pos, ' ...
    'sp.test.gain_ant, cls_names, os_thr);']));
verifyNotEmpty(tc, strfind(src, 'pv = fus.val_latch_oof;'));
verifyNotEmpty(tc, strfind(src, '''y_fused'', Y_fused'));
src = fileread(which('select_fusion'));
verifyNotEmpty(tc, strfind(src, 'val_latch_oof(m, :) = latch_runs(val_probs_oof(m, :)'));
verifyNotEmpty(tc, strfind(src, '''val_probs_oof'', ''val_latch_oof'''));
verifyNotEmpty(tc, strfind(fileread(which('detector_block')), 'G.FM, G.FN, G.classes);'));
end

function test_latch_choice(tc)
% Whether the monitor latches a lost branch's cause is a validation choice (FM.latch,
% select_fusion.m) that every reading honours alike: off, the monitor's class is the fused
% class (fused_class.m, policy_monitor.m, det_frames.m, eval_detector.m); on, or a fusion
% fitted before the choice (no flag), the latch as before.
cls = {'none', 'antenna_fault', 'airframe_shadowing'}; C = 3;
nZ = numel(temporal_evidence('names', C)) + numel(window_cues('names')) + C;
FMn = struct('W', [zeros(nZ, C); 0 0 5], 'mu', zeros(1, nZ), 'sd', ones(1, nZ), 'C', C, 'lambda', 0);   % reads shadowing
FM1 = FMn; FM1.latch = true; FM0 = FMn; FM0.latch = false;
verifyTrue(tc, onset_shape('on', FMn)); verifyTrue(tc, onset_shape('on', FM1)); verifyTrue(tc, onset_shape('on', []));
verifyFalse(tc, onset_shape('on', FM0));
% fused_class.m (KPI 1, B4, B4s)
rng(3); n = 30; nf = numel(link_features('names'));
G = 0.3 * randn(n, 3); G(10:end, 2) = G(10:end, 2) - 15;           % an open connector at cycle 10
S = struct('run', ones(n, 1), 'pos', (1:n)', 'gain_ant', G, 'feats_raw', zeros(n, nf));
P = repmat([0.2 0.3 0.5], n, 1);
[kn, kfn] = fused_class(P, S, FMn, 4, cls);
[k0, kf0] = fused_class(P, S, FM0, 4, cls);
verifyEqual(tc, kfn, 3 * ones(n, 1)); verifyEqual(tc, kf0, kfn);
verifyEqual(tc, k0, kf0);                                             % off: the fused class everywhere
verifyEqual(tc, kn(end), 2);                                          % no flag: the fault latched from its step
verifyEqual(tc, fused_class(P, S, FM1, 4, cls), kn);                  % on: as without the flag
% policy_monitor.m (the closed loop)
A = policy_actions();
for v = 1:3
    FM = {FMn, FM1, FM0}; PP = struct('actions', {A}, 'classes', {cls}, 'maha_thr', -Inf, 'sps', 4, 'bps', 2, ...
        'fuse', FM{v}, 'fuse_N', 4);
    mem = policy_monitor('init', 1, numel(A)); cl = cell(1, n);
    for t = 1:n
        obs = struct('probs', P(t, :), 'unknown', false, 'feat', zeros(1, nf), 'gant', G(t, :), 'maha', 0);
        obs.feat(feature_index('log_ber')) = -6;
        [mem, M] = policy_monitor('update', mem, obs, PP, find(strcmp(A, 'no_action')));
        cl{t} = M.cls{1};
    end
    if v < 3
        verifyEqual(tc, unique(cl(15:n)), {'antenna_fault'});
    else
        verifyEqual(tc, unique(cl), {'airframe_shadowing'});           % off: the fused class
    end
end
% det_frames.m (the edge map's DET)
ok = [strcmp(cls, 'antenna_fault'); ismember(cls, {'antenna_fault', 'airframe_shadowing'})];
Gc = 0.3 * randn(10, 3); Gf = 0.3 * randn(10, 3); Gf(:, 2) = Gf(:, 2) - 18;
mk = @(pr, Gx, act) struct('probs', repmat(pr, 10, 1), 'run', 101 * ones(10, 1), 'gant', Gx, 'feat', zeros(10, nf), ...
    'ber', zeros(10, 1), 'act', act * ones(10, 1));
PP = struct('classes', {cls}, 'fuse', FM0, 'fuse_N', 4, 'sps', 2, 'bps', 2);
[hit, ~, hit_f] = det_frames(mk([0.1 0.4 0.5], Gf, 1), mk([1 0 0], Gc, 0), 'antenna_fault', ok, PP);
verifyEqual(tc, hit, hit_f);                                          % off: the fused class
verifyFalse(tc, any(hit(:, 1)));
PP.fuse = FMn;
hit = det_frames(mk([0.1 0.4 0.5], Gf, 1), mk([1 0 0], Gc, 0), 'antenna_fault', ok, PP);
verifyTrue(tc, all(hit(5:end, 1)));                                   % no flag: the cause latched from the step
% the choice and its readings
src = fileread(which('select_fusion'));
verifyNotEmpty(tc, strfind(src, 'FM.latch = mf_latch > mf_fused;'));
verifyLessThan(tc, strfind(src, 'FM.latch = mf_latch > mf_fused;'), strfind(src, 'save(''data/fusion.mat'''));
src = fileread(which('eval_detector'));
verifyNotEmpty(tc, strfind(src, 'latch_on = onset_shape(''on'', fus.FM);'));
verifyNotEmpty(tc, strfind(src, 'pv = fus.val_probs_oof;'));
verifyNotEmpty(tc, strfind(src, '&& latch_on'));
verifyNotEmpty(tc, strfind(fileread(which('policy_monitor')), '&& onset_shape(''on'', FZ)'));
verifyNotEmpty(tc, strfind(fileread(which('det_frames')), '&& onset_shape(''on'', PP.fuse)'));
end

function test_roll_in_false_alarms(tc)
% The false-alarm reading beside KPI 1 (roll_in_false_alarms.m, eval_detector.m): the frames of
% the clean sub-runs inside their roll-in, the share read as any threat, as path_loss and as
% airframe_shadowing, next to the same shares over every frame whose target is none.
cls = {'none', 'path_loss', 'airframe_shadowing', 'jamming'};
n = 6; pos = repmat((1:n)', 3, 1); run = kron((1:3)', ones(n, 1));
P = struct('run', run, 'pos', pos, 'class_run', [ones(2 * n, 1); 3 * ones(n, 1)], ...
    'roll_in', [repmat([2 10], n, 1); zeros(n, 2); repmat([2 10], n, 1)], 'bank', [-20 * ones(n, 1); 20 * ones(2 * n, 1)]);
yt = repmat({'none'}, 3 * n, 1); yt(2 * n + 4:end) = {'airframe_shadowing'};
yp = repmat({'none'}, 3 * n, 1);
yp([1 3 4]) = {'jamming', 'path_loss', 'airframe_shadowing'};      % run 1: frame 1 before its roll-in
yp(n + 2) = {'jamming'};                                           % run 2 holds its bank from the start
yp([2 * n + 2, 2 * n + 5]) = {'path_loss', 'airframe_shadowing'};
yt = categorical(yt, cls); yp = categorical(yp, cls);
R = roll_in_false_alarms(P, yt, yp, 1);                            % frame k lies k - 1 s into its run
% run 1 rolls in from 2 s to 2 + 20 / 10 = 4 s: its frames 3, 4 and 5 (the end of the roll-in counts);
% run 2 has no roll-in, run 3 is not clean
verifyEqual(tc, [R.roll_in.n R.roll_in.n_runs], [3 1]);
verifyEqual(tc, [R.roll_in.any_pct R.roll_in.path_loss_pct R.roll_in.airframe_shadowing_pct], 100 * [2 1 1] / 3, 'AbsTol', 1e-9);
verifyEqual(tc, [R.clean.n R.clean.n_runs], [3 * n - 3, 3]);        % every frame whose target is none
verifyEqual(tc, [R.clean.any_pct R.clean.path_loss_pct R.clean.airframe_shadowing_pct], 100 * [5 2 1] / 15, 'AbsTol', 1e-9);
P.roll_in(:) = 0;                                                  % no clean sub-run rolls in
R = roll_in_false_alarms(P, yt, yp, 1);
verifyEqual(tc, [R.roll_in.n R.roll_in.n_runs], [0 0]);
verifyTrue(tc, all(isnan([R.roll_in.any_pct R.roll_in.path_loss_pct R.roll_in.airframe_shadowing_pct])));
verifyEqual(tc, R.clean.n, 3 * n - 3);
P.roll_in = repmat([2 10], 3 * n, 1); P.pos = P.pos + 100;          % every frame past the roll-in
verifyEqual(tc, roll_in_false_alarms(P, yt, yp, 1).roll_in.n, 0);
src = fileread(which('eval_detector'));
verifyNotEmpty(tc, strfind(src, 'roll_in_false_alarms(sp.test, Y_test, Y_pred, cyc_s);'));
verifyNotEmpty(tc, strfind(src, 'metrics.roll_in_false_alarms = roll_in_fa;'));
verifyNotEmpty(tc, strfind(fileread(which('run_dataset_sweep')), 'dataset.class_run = D.class_run(:);'));
verifyNotEmpty(tc, strfind(fileread(which('extract_spectrograms')), '''class_run'', ''roll_in''}'));
verifyNotEmpty(tc, strfind(fileread(which('prepare_data')), '''class_run'', ''roll_in''}'));   % test, fresh test and the folds alike
end

function test_onset_events_branch(tc)
% The latch threshold's events (select_fusion.m) are read as the deployed latch reads them:
% the deployed heal, the first diagnosis on the threat's branch. A fading dip on another
% branch before a fault's step is diagnosed first, heals and leaves the step to be scored; a
% ramp diagnosed before its labelled frame still counts; an event on another branch that
% never heals leaves none.
rng(11);
n = 30; L = 0.3 * randn(n, 3);
G = L; G(5:9, 3) = G(5:9, 3) - [3 6 9 9 6]'; G(13:end, 1) = G(13:end, 1) - 15;
verifyGreaterThan(tc, onset_shape('events', G), 0);              % the first event: the dip, ramp-like
g = onset_shape('events', G, 13, 5);
verifyLessThan(tc, g, 0);                                        % the step on the fault's branch
verifyTrue(tc, isnan(onset_shape('events', G, 13, Inf)));        % never healed: the step not reached
verifyEqual(tc, onset_shape('events', G, 13), g);                % the deployed heal by default
verifyEqual(tc, decision_config().heal, 5);
Lr = L; Lr(:, 2) = Lr(:, 2) - 15 * min(1, max(0, ((1:n)' - 5) / 12));
verifyGreaterThan(tc, onset_shape('events', Lr, 16), 0);
verifyEqual(tc, onset_shape('events', Lr, 16), onset_shape('events', Lr));   % diagnosed before its labelled frame
Gw = L; Gw(6:end, 3) = Gw(6:end, 3) - 15; Gw(13:end, 1) = Gw(13:end, 1) - 15;
verifyTrue(tc, isnan(onset_shape('events', Gw, 13)));            % another branch, lost for good
verifyNotEmpty(tc, strfind(fileread(which('select_fusion')), 'onset_shape(''events'', va.gain_ant(ix, :), j0, heal)'));
end

function test_ood_halves_stratified(tc)
% The validation halves of the unknown-threat folds (ood_loto_split.m) on A5's run and fold
% layout: every (class, Eb/N0) and (class, level) has sub-runs in both halves, the halves
% differ by at most one sub-run per (class, Eb/N0), and a class with one sub-run per cell is
% a checkerboard over level and Eb/N0.
NS = [6 6 6 6 6 13 10 46 8 8]; EB = 0:3:15; nL = 8; nC = numel(NS);
cls = [{'none'}, compose('t%d', 1:nC)];
run = []; y = []; eb = []; lv = []; rid = 0;
for c = 1:nC
    nk = 0;
    for l = 1:nL
        for e = 1:6
            for s = 1:NS(c)
                rid = rid + 1; nk = nk + 1;
                if mod(nk + l - 2, 6) + 1 == 5
                    run(end+1) = rid; y(end+1) = c + 1; eb(end+1) = EB(e); lv(end+1) = l; %#ok<AGROW>
                end
            end
        end
    end
end
for e = 1:6
    for k = 1:nL * 6
        rid = rid + 1;
        if mod(k - 1, 6) + 1 == 5, run(end+1) = rid; y(end+1) = 1; eb(end+1) = EB(e); lv(end+1) = NaN; end %#ok<AGROW>
    end
end
n = numel(run); run = run(:); y = y(:); eb = eb(:); lv = lv(:);
Yc = categorical(y, 1:nC + 1, cls);
va = struct('X', zeros(2, 2, 1, n, 'single'), 'feats', zeros(n, 1), 'Y', Yc, 'Y_frame', Yc, 'run', run, ...
    'pos', ones(n, 1), 'ebno', eb, 'level', lv);
sp = struct('train', va, 'val', va, 'norm', struct('feat_mean', 0, 'feat_std', 1), 'classes', {cls'});
[~, ~, V] = ood_loto_split(sp, va, 't1');
for c = 1:nC + 1
    m = y == c;
    for e = EB
        a = sum(m & eb == e & ~V.sel); b = sum(m & eb == e & V.sel);
        verifyGreaterThan(tc, [a b], 0); verifyLessThanOrEqual(tc, abs(a - b), 1);
    end
    for l = 1:nL * (c > 1)
        verifyGreaterThan(tc, [sum(m & lv == l & ~V.sel), sum(m & lv == l & V.sel)], 0);
    end
end
m = y == 2; [~, ie] = ismember(eb(m), EB);
verifyEqual(tc, ~V.sel(m), mod(ie + lv(m), 2) == 1);             % fit where level + Eb/N0 index is odd
end

function test_spec_only_baseline_unmasked(tc)
% The features-only baseline of the architecture comparison holds its spectrogram at zero, where
% the masking would paint noise-level bands (spec_mask.m): it trains without masking, the other
% variants with it.
rng(2); verifyGreaterThan(tc, nnz(spec_mask(zeros(128, 128, 1, 8, 'single'))), 0);
src = fileread(which('compare_architectures'));
verifyNotEmpty(tc, strfind(src, 'if strcmp(V(v).mask, ''spec''), opts.augment = false; end'));
verifyNotEmpty(tc, strfind(src, 'net = train_hybrid_net(tr, va, classes, opts);'));
end

function test_kpi2_deployed_statistic(tc)
% KPI 2's summary gives the statistic the decision cycle compares (the production score over
% its window) with its FPR95, and the nested estimate's FPR95 beside the nested AUROC.
d = fullfile(tc.TestData.tmp, 'kpi2'); mkdir(fullfile(d, 'results')); mkdir(fullfile(d, 'data'));
c0 = cd(d); back = onCleanup(@() cd(c0));
SC = {'msp', 'energy', 'iforest', 'last', 'raw'}; WIN = [2 5 8]; RETAIN = 0.95; sel = 'last'; sel_win = 5;
R = struct('held_out', {'jamming', 'tone_jamming'}, 'auroc', {[0.6 0.6 0.6 0.81 0.7], [0.6 0.6 0.6 0.83 0.7]}, ...
    'fpr95', {[0.5 0.5 0.5 0.41 0.6], [0.5 0.5 0.5 0.43 0.6]}, 'auroc_win', {0.9 * ones(5, 3), 0.9 * ones(5, 3)});
pj = repelem(4:5, 4); pw = repmat([1 WIN], 1, 2);                % (candidate, window) pairs
MpT = repmat(0.1 * (1:8), 2, 1); FpT = MpT / 10; MpV = MpT;
NEST = struct('auroc', [0.84 0.86], 'fpr95', [0.31 0.33], 'auroc_val', [0.8 0.8], 'pick', {{'last over 5', 'last over 5'}});
TEST_SET = 'second test set'; %#ok<NASGU>
save('results/ood_detection.mat', 'R', 'SC', 'sel', 'sel_win', 'NEST', 'WIN', 'RETAIN', 'MpV', 'MpT', 'FpT', 'pj', 'pw', ...
    'TEST_SET');
evalc('measure_all_kpis');
K = load('results/kpi_summary.mat', 'KPI'); k2 = K.KPI([K.KPI.id] == 2);
verifyEqual(tc, k2.value, 'mean AUROC 0.850, FPR95 0.32 (nested)');
verifyNotEmpty(tc, strfind(k2.detail{1}, ['deployed statistic: last averaged over the last 5 cycles, mean AUROC ' ...
    '0.300, FPR at 95% known kept 0.03']));
verifyNotEmpty(tc, strfind(k2.detail{1}, 'nested estimate: mean AUROC 0.850, FPR95 0.32'));
verifyNotEmpty(tc, strfind(k2.detail{2}, '(per frame)'));
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
set_link_snr(mdl, 60 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
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
set_link_snr(mdl, 60 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
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
% Per-flight RMS delay spreads, log-normal as Rodriguez-Pineiro et al.'s fits (Table VII,
% environment II, the larger of the omni and directional fits per height band): our
% signal below 25 m on the directional OLoS fit (median 302 ns, sigma 0.566 decades),
% 25-75 m and without an altitude on the omni fit (234 ns, 0.4), from 75 m on the
% directional fit (372 ns, 0.51); every interferer on the omni fit; all clipped at half the
% measured profile's 4.5 us range (2.25 us). flight_draws turns them into the delay line's
% profiles at the flight's K, and gives a flat channel without the line.
p = base_params(); p.tdl = true; p.tdl_random = true;
verifyEqual(tc, p.tdl_clip_ns, p.tdl_max_ns / 2);
n = 4000;
lo = cell2mat(arrayfun(@(s) delay_spread(s, 20, 3, p), (1:n)', 'UniformOutput', false));
hi = cell2mat(arrayfun(@(s) delay_spread(s, 60, 3, p), (1:n)', 'UniformOutput', false));
up = cell2mat(arrayfun(@(s) delay_spread(s, 80, 3, p), (1:n)', 'UniformOutput', false));
verifyEqual(tc, hi, cell2mat(arrayfun(@(s) delay_spread(s, NaN, 3, p), (1:n)', 'UniformOutput', false)));
verifyEqual(tc, up, cell2mat(arrayfun(@(s) delay_spread(s, 75, 3, p), (1:n)', 'UniformOutput', false)));
verifyEqual(tc, lo(:, 2:end), hi(:, 2:end)); verifyEqual(tc, up(:, 2:end), hi(:, 2:end));
q = @(x, f) log10(sort(x(:)) * 1e-9);
for c = {lo(:, 1), -6.52, 0.32; hi(:, 1), -6.63, 0.16; up(:, 1), -6.43, 0.26; hi(:, 2:end), -6.63, 0.16}'
    v = q(c{1}); m = numel(v);
    verifyEqual(tc, v(round(m / 2)), c{2}, 'AbsTol', 0.03);
    verifyEqual(tc, (v(round(0.75 * m)) - v(round(0.25 * m))) / (2 * 0.6745), sqrt(c{3}), 'RelTol', 0.08);
end
verifyLessThanOrEqual(tc, max([lo(:); hi(:); up(:)]), p.tdl_clip_ns);
verifyEqual(tc, mean(up(:, 1) == p.tdl_clip_ns), 0.5 * erfc((log10(p.tdl_clip_ns * 1e-9) + 6.43) / sqrt(2 * 0.26)), 'AbsTol', 0.01);
verifyEqual(tc, mean(up(:, 1) > 1000), 0.5 * erfc((-6 + 6.43) / sqrt(2 * 0.26)), 'AbsTol', 0.02);   % about a fifth above 1 us
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
gl = set_link_snr(mdl, 60, p);                          % the received level's amplitude gain
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
verifyEqual(tc, mean(abs(Y).^2, 'all') / mean(abs(X).^2, 'all') / gl^2, 1, 'AbsTol', 0.1);
p.active_threat = 'jamming'; p.jsr_db = 30; p.rician_k = 10;
e = zeros(1, 2); g = e;
for t = [false true]
    p.tdl = t;
    evalc('build_threat_model(p)');
    set_link_snr(mdl, 60, p);
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
% 4.5 us window after, the equalizer +-10 symbols, the space-time MMSE +-2 us (twice the
% 1 us clip) half a symbol apart, its window twice the 27 degrees of freedom, its
% snapshots reached by the symbols within 2 + 2 of their own; on the flat channel every
% count is 1, and so is the receiver built for it. The sync statistic has 5 taps (+-1
% symbol) and the noise floor 9 in every configuration.
p = base_params();
p.tdl = false;
t = rx_taps(p);
verifyEqual(tc, [t.lags t.ne t.nt t.window t.mh t.ns t.nn], [0 0 1 1 p.mmse_window 0 5 9]);
verifyEqual(tc, rx_taps(rmfield(p, 'tdl')), t);
p.tdl = true;
t = rx_taps(p);
verifyEqual(tc, [t.lags t.ne t.nt t.window t.mh t.ns t.nn], [2 5 21 9 64 4 5 9]);
q = p; q.tdl_max_ns = 2000; q.rx_span_ns = 500;
t = rx_taps(q);
verifyEqual(tc, [t.lags t.ne t.nt t.window t.mh], [2 2 9 5 32 3]);
q = p; q.tdl_clip_ns = 2250;                            % the channel's clip does not move the receiver
verifyEqual(tc, rx_taps(q).nt, 9);
p.quiet_build = true; p.rx_sync = 'real';
mdl = 'UAV_GCS_Threat_Link';
C = {false, 'mrc', 'NT = 1;', 'MH = 0;'; false, 'mmse', 'NT = 1;', 'MH = 0;'; ...
     true, 'mrc', 'NT = 1;', 'NE = 21;'; true, 'mmse', 'NT = 9;', 'MH = 4;'};
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
% 1 us RMS delay spread, and at the clip (2.25 us, the line's flat profile, 1.5 us), below
% 1e-3 at 12 dB; the MMSE receiver keeps a 16 dB jammer whose channel spreads 234 ns below
% 0.03 at 15 dB, and one that spreads 64 ns, nearly flat, about as well as the flat
% receiver on the flat channel at 6 dB (each frame keeps the space-time or the
% antennas-alone output by its pilots); a 30 dB jammer on the flat channel stays below
% 0.06, and one whose channel spreads 234 ns below 0.03 (the space-time sync finds the
% frame under it).
p = base_params(); p.quiet_build = true; p.rx_sync = 'real'; p.int_aoa_random = false; p.yaw_random = false;
p.corr_random = false; p.gcs_tracked = false; p.k_random = false; p.gcs_aoa_random = false; p.body_random = false;
p.tdl = true; p.tdl_random = false;
mdl = 'UAV_GCS_Threat_Link';
q = p; q.active_threat = 'none'; q.rx_combiner = 'mrc'; q.rician_k = -5; q.tdl_ds_ns = [1000 0];
verifyLessThan(tc, link_ber(mdl, q, 12, 21:23, 20), 1e-3);
q.tdl_ds_ns = [2250 0];
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
q.tdl = true; q.tdl_ds_ns = [0 234];
verifyLessThan(tc, link_ber(mdl, q, 15, 21:23, 20), 0.03);
end

function test_sync_flag(tc)
% Sync coherence and the sync-failure flag: on a clean link at 6 dB the training is found
% in every frame (coherence above p.sync_coh_min, no flag) and no frame is erased for the
% decoder (pilot error below p.erase_pilot_mse); with our signal absent from the air (the
% 'GCS' amplitude 0) every frame is flagged and erased, on the flat and the delay-line
% receivers alike. The clean frames coded (soft values, four frames per codeword) decode
% every packet, the CRC result on the second frame of each pair.
p = base_params(); p.quiet_build = true; p.rx_sync = 'real'; p.int_aoa_random = false; p.yaw_random = false;
p.corr_random = false; p.gcs_tracked = false; p.k_random = false; p.gcs_aoa_random = false; p.body_random = false;
p.tdl_random = false; p.active_threat = 'none'; p.rician_k = 10;
mdl = 'UAV_GCS_Threat_Link';
C = {false, 'mrc', [0 0]; true, 'mmse', [234 0]};
for i = 1:size(C, 1)
    p.tdl = C{i, 1}; p.rx_combiner = C{i, 2}; p.tdl_ds_ns = C{i, 3};
    evalc('build_threat_model(p)');
    set_link_snr(mdl, 6 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
    link_seed(mdl, 31, 160);
    o = sim(mdl, 'StopTime', num2str(10 * p.frame_duration));
    F = extract_closed_loop_frames(o, p, 20);
    q = p; q.fec = true;                                         % the same frames coded: every packet decoded
    Fc = extract_closed_loop_frames(o, q, 20); n2 = 2 * floor(F.nf / 2);
    verifyEqual(tc, [Fc.ber(1:n2); Fc.crc_fail(2:2:n2), zeros(1, n2 / 2)], zeros(2, n2));
    verifyTrue(tc, all(isnan(Fc.crc_fail(1:2:n2))));
    verifyGreaterThan(tc, min(F.sync_coh(2:end)), p.sync_coh_min);
    verifyEqual(tc, F.sync_fail(2:end), zeros(1, F.nf - 1));
    verifyLessThan(tc, max(F.pilot_err(2:end)), p.erase_pilot_mse);
    verifyEqual(tc, F.erase(2:end), false(1, F.nf - 1));
    set_param([mdl '/GCS'], 'Value', '0');
    F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(10 * p.frame_duration)), p, 20);
    verifyEqual(tc, F.sync_fail, ones(1, F.nf));
    verifyEqual(tc, F.erase, true(1, F.nf));
    close_system(mdl, 0);
end
end

function test_adc_frontend(tc)
% Receive front end: the AGC puts full scale adc_backoff_db to 1 dB more above the rail
% RMS (1 dB gain steps); a tone within full scale is quantized with the SQNR of a uniform
% 12-bit quantizer (step^2 / 12 per rail); samples beyond full scale are clipped to the
% outermost level; 0 bits leave the samples unchanged. A burst 20 dB above the frame's
% level that starts after the AGC windows clips for the rest of the frame with the gain
% held; with the fast attack the gain steps down 32 samples (16 averaged, 16 waited) after
% the burst's first block, on the 1 dB grid bo_db above the burst's rail RMS, and only
% those samples clip; the attack leaves a steady frame unchanged.
rs = RandStream('mt19937ar', 'Seed', 3);
N = 4000; iq = 1:500; is = 501:1000;
u = 0.01 * exp(1j * 2*pi * 0.0123 * (0:N-1).') * [1 3];
[y, fs, clip] = adc_frontend(u, 12, 12, iq, is);
lv = 20*log10(fs ./ sqrt(mean(real(u).^2)));
verifyGreaterThanOrEqual(tc, lv, 12 - 1e-9);
verifyLessThan(tc, lv, 13);
verifyEqual(tc, clip, 0);
d = fs / 2^11;
sq = 10*log10(mean(abs(u).^2) ./ mean(abs(y - u).^2));
verifyEqual(tc, sq, 10*log10(mean(abs(u).^2) ./ (2 * d.^2 / 12)), 'AbsTol', 0.5);
verifyGreaterThan(tc, sq, 60);
v = u; v(2000, 1) = 10 * fs(1) * (1 + 1j);                 % far beyond full scale
[w, ~, clip] = adc_frontend(v, 12, 12, iq, is);
verifyEqual(tc, real(w(2000, 1)), fs(1) - d(1) / 2, 'AbsTol', 1e-12);
verifyEqual(tc, clip, 2 / (2 * numel(v)));
g = complex(randn(rs, N, 2), randn(rs, N, 2));
verifyEqual(tc, adc_frontend(g, 0, 12, iq, is), g);
verifyEqual(tc, adc_frontend(g, Inf, 12, iq, is), g);
verifyEqual(tc, adc_frontend(g, 12, 12, iq, is, 6), adc_frontend(g, 12, 12, iq, is));   % steady: no step
b = g; k0 = is(end) + 1 + 16 * 63; b(k0:end, :) = 10 * b(k0:end, :);   % +20 dB from a block start
[~, ~, ch] = adc_frontend(b, 12, 12, iq, is);
[yb, fb, ca] = adc_frontend(b, 12, 12, iq, is, 6);
verifyGreaterThan(tc, ch, 0.05);
cl = abs(real(b)) >= fb | abs(imag(b)) >= fb;                     % rails beyond the final full scale
verifyLessThan(tc, mean(cl(k0 + 32:end, :), 'all'), 1e-3);
verifyLessThan(tc, ca, 32 / N);
lv = 20*log10(fb ./ sqrt(mean(real(b(k0:end, :)).^2)));
verifyGreaterThan(tc, lv, 11); verifyLessThan(tc, lv, 14);
ok = ~cl(k0 + 32:end, :);
e = abs(real(yb(k0 + 32:end, :) - b(k0 + 32:end, :)));
verifyLessThanOrEqual(tc, max(e(ok)), max(fb) / 2^11 / 2 + 1e-12);   % half a step off, at the new gain
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
% in 20-83.5 ms, its phase in [0, T), the burst phase in [0, 1); the noise bursts half the
% flights Marti et al.'s sparse jammer J4 at 20%, half Xu et al.'s random jammer at a duty
% uniform in 50-77.5%; fixed: the shortest period at phase 0, Xu et al.'s 50%. The sweeper
% covers our channel for (4 + 1.25) MHz / 1 GHz/s = 5.25 ms of each sweep; with frequency
% diversity on a carrier 25 MHz away never on both at once, on one 2 MHz away from 2 ms on.
p = base_params();
verifyEqual(tc, [p.burst_duty_range p.burst_j4], [0.5 0.775 0.2 0.5]);
W = cell2mat(arrayfun(@(s) jam_timing(s, p.sweep_period_s, p.burst_duty_range, p.burst_j4), (1:4000)', 'UniformOutput', false));
verifyTrue(tc, all(W(:, 1) >= 20e-3 & W(:, 1) <= 83.5e-3));
verifyTrue(tc, all(W(:, 2) >= 0 & W(:, 2) < W(:, 1) & W(:, 3) >= 0 & W(:, 3) < 1));
j4 = W(:, 4) == 0.2;
verifyTrue(tc, all(j4 | (W(:, 4) >= 0.5 & W(:, 4) <= 0.775)));   % Marti et al.'s 20%, or Xu et al.'s 50% to 77.5%
verifyEqual(tc, mean(j4), 0.5, 'AbsTol', 0.03);
verifyEqual(tc, mean(W(~j4, 4)), 0.6375, 'AbsTol', 0.01);
verifyEqual(tc, mean(W(:, 1)), mean(p.sweep_period_s), 'AbsTol', 1e-3);
u = rand(seed_stream(17, 'jam'), 1, 4);
T = 20e-3 + 63.5e-3 * u(1);
a = 0.2; if u(4) >= 0.5, a = 0.5 + 0.275 * (u(4) - 0.5) / 0.5; end
w = [T, T * u(2), u(3), a];
verifyEqual(tc, jam_timing(17, p.sweep_period_s, p.burst_duty_range, p.burst_j4), w, 'AbsTol', 1e-15);
d = flight_draws(17, 100, p);
verifyEqual(tc, d.jam, w, 'AbsTol', 1e-15);
p.jam_timing_random = false;
d = flight_draws(17, 100, p);
verifyEqual(tc, d.jam, [20e-3 0 0 0.5]);
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
% cells 1/share times the sub-runs. Without idle sensing (with it: test_threat_active_cycle).
p = base_params(); p.idle_rssi_hz = 0;
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
    set_link_snr(mdl, 12 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
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
% stop time (pool_cell.m) carries a whole packet. The noise bursts start on when the
% flight's draw gate(3) is below its duty gate(4), off otherwise (six flights each).
p = base_params(); p.quiet_build = true; p.active_threat = 'sweeping_jammer'; p.jsr_db = 16; p.seed = 11;
p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false; p.gcs_tracked = false; p.k_random = false;
p.gcs_aoa_random = false; p.body_random = false; p.wobble_random = false; p.jam_timing_random = false;
mdl = 'UAV_GCS_Threat_Link'; nfr = 8; gate = [25e-3 0.2e-3 0 0.5];
fs = p.symbol_rate * p.sps; ns = p.air_symbols * p.sps;
t = (0:ns-1)' / fs + (0:nfr-1) * round(p.cycle_s * fs) / fs;
for fdiv = [false true]
    q = p;
    if fdiv, q = apply_countermeasure(p, 'sweeping_jammer', 'freq_diversity+fec_interleave'); end
    evalc('build_threat_model(q)');
    set_link_snr(mdl, 15 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
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
set_link_snr(mdl, 30 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
link_seed(mdl, 11, 160);
pw = zeros(6, 2);
for s = 1:6
    for k = 1:2
        link_seed(mdl, 10 + s, 160);
        set_param([mdl '/Gate'], 'Value', mat2str([20e-3 0 0.9 * (k - 1) 0.5]));
        out = sim(mdl, 'StopTime', num2str(2 * p.frame_duration));
        Y = out.get('Rx_IQ');
        pw(s, k) = mean(abs(Y(1, :, 1)).^2);    % the first sample: a burst on (0 < 0.5) or a sleep (0.9 >= 0.5)
    end
end
ps = thermal_nv(p) * 10^(30 / 10) * p.bits_per_symbol / p.sps;   % our signal's power per sample at 30 dB
verifyGreaterThan(tc, min(pw(:, 1)), ps);                        % the burst: 16 dB over our signal in band
verifyLessThan(tc, mean(pw(:, 2)), 3 * thermal_nv(p));           % the sleep: the quiet slot's noise
close_system(mdl, 0);
end

function test_fec_packets(tc)
% FEC: one codeword per 1000 + 32-bit packet (2064 coded bits) spread over four frames, one
% packet per frame pair: every channel bit of the run carries one coded bit, every frame
% 516 bits of each of two packets, a packet's four frames are the two pairs up to the one
% it ends on, cyclic over the run. A clean run decodes every frame; both frames of a pair
% carry its packet's BER and error, in steps of 1/1032, and only the second its CRC result
% (decoded there). A frame the receiver flags is erased: one of the four frames of a
% codeword, even jammed whole, still decodes, unflagged it does not unless its soft
% values carry its low reliability; two flagged frames
% of one pair do not (half of each codeword), also across the run's wrap. Scattered errors
% are repaired, a burst only when the receiver sees it (erased by energy). A last frame
% without its pair, and a run shorter than a codeword, is NaN. Two frames per codeword:
% one flagged frame loses its packet.
p = base_params(); L = frame_layout(p); bpf = p.frame_length; nf = 20; d = p.filter_span / 2;
verifyEqual(tc, p.fec_frames, 4);
rs = RandStream('mt19937ar', 'Seed', 3);
tx = randi(rs, [0 1], nf * bpf, 1);
iq = ones(L.air * p.sps, nf);
[b, f, c, map] = fec_packets(tx, tx, iq, p, nf);
verifyEqual(tc, sort(map(:)), (1:nf * bpf)');                          % every channel bit once
fm = ceil(map / bpf);                                                    % frame of every coded bit
for k = 1:nf / 2
    verifyEqual(tc, accumarray(fm(:, k), 1, [nf 1])', 516 * ismember(1:nf, mod(2*k - 4 + (0:3), nf) + 1));
end
verifyEqual(tc, [b; f], zeros(2, nf));
verifyEqual(tc, c(2:2:nf), zeros(1, nf / 2));
verifyTrue(tc, all(isnan(c(1:2:nf))));
verifyEqual(tc, [crc32_fail(tx(1:1000), zeros(bpf, 1)), crc32_fail(tx(1:1000), [1; zeros(bpf - 1, 1)])], [0 1]);
rx = tx;
i1 = map(randperm(rs, 2 * bpf, 10), 2); rx(i1) = 1 - rx(i1);           % packet 2: scattered errors
rx(6*bpf + (1:bpf)) = 1 - rx(6*bpf + (1:bpf));                           % frame 7 inverted whole
er = false(1, nf); er(7) = true;
verifyEqual(tc, fec_packets(tx, rx, iq, p, nf, er), zeros(1, nf));       % erased: packets 4 and 5 decode
rel = ones(nf * bpf, 1); rel(6*bpf + (1:bpf)) = 0.01;                    % or entered with their low reliability
verifyEqual(tc, fec_packets(tx, rx, iq, p, nf, [], rel), zeros(1, nf));
[b, f, c] = fec_packets(tx, rx, iq, p, nf);
verifyEqual(tc, b([1:6 11:nf]), zeros(1, nf - 4));
verifyGreaterThan(tc, b([7 9]), [0 0]);                                  % unflagged: both packets lost
verifyEqual(tc, [f(7) f(8) c(8) b(8)], [1 1 1 b(7)]);
verifyTrue(tc, isnan(c(7)));
verifyEqual(tc, b(7) * bpf, round(b(7) * bpf), 'AbsTol', 1e-9);
rx2 = tx; rx2(18*bpf + (1:2*bpf)) = randi(rs, [0 1], 2*bpf, 1);         % pair 10 jammed, flagged
er2 = false(1, nf); er2([19 20]) = true;
b2 = fec_packets(tx, rx2, iq, p, nf, er2);
verifyEqual(tc, b2(3:18), zeros(1, 16));
verifyGreaterThan(tc, b2([1 19]), [0 0]);                                % packet 1 starts on the run's last pair
s = 101:250;                                                             % 150 data symbols of frame 7, random bits
k = 6*bpf + reshape([2*s - 1; 2*s], [], 1);
rx3 = tx; rx3(k) = randi(rs, [0 1], numel(k), 1);
rx3(map(randperm(rs, 2 * bpf, 60), 4)) = randi(rs, [0 1], 60, 1);      % and noise on packet 4
iq3 = iq;
for m = L.idx_data(s)' + d
    iq3((m-1)*p.sps + 1:m*p.sps, 7) = sqrt(10);                         % 10 dB above the rest: erased
end
verifyEqual(tc, fec_packets(tx, rx3, iq3, p, nf), zeros(1, nf));
b4 = fec_packets(tx(1:19*bpf), tx(1:19*bpf), iq(:, 1:19), p, 19);
verifyEqual(tc, b4(1:18), zeros(1, 18));
verifyTrue(tc, isnan(b4(19)));
verifyTrue(tc, all(isnan(fec_packets(tx(1:3*bpf), tx(1:3*bpf), iq(:, 1:3), p, 3))));
q = p; q.fec_frames = 2;
b5 = fec_packets(tx, rx2, iq, q, nf, er2);
verifyEqual(tc, b5(1:18), zeros(1, 18));
verifyGreaterThan(tc, b5(19), 0);
b6 = fec_packets(tx, tx, iq, q, nf, er);
verifyEqual(tc, b6([1:6 9:nf]), zeros(1, nf - 2));
verifyGreaterThan(tc, b6(7), 0);
end

function test_bit_reliability(tc)
% The reliability of every bit sits on its own rail of the Gray-mapped pi/4 QPSK symbol
% (pskmod): the first bit on Im(conj(g) z), the second on Re(conj(g) z), g the block's gain.
% A symbol pushed onto the real axis leaves its first bit uncertain, one pushed onto the
% imaginary axis its second; the signs of the rails give pskdemod's bits.
p = struct('frame_length', 1032);
rs = RandStream('mt19937ar', 'Seed', 3);
b = randi(rs, [0 1], p.frame_length, 1);
s = pskmod(b, 4, pi/4, 'gray', 'InputType', 'bit');
g = 0.7 * exp(1j * 0.4);
z = g * s + 0.02 * complex(randn(rs, size(s)), randn(rs, size(s)));
k1 = 40; k2 = 300;
z(k1) = g * real(s(k1)) * (1 + 0.01j);                         % Im of conj(g) z near 0
z(k2) = g * 1j * imag(s(k2)) * (1 + 0.01j);                    % Re of conj(g) z near 0
r = bit_reliability(z, p);
verifyEqual(tc, size(r), [p.frame_length, 1]);
verifyLessThan(tc, r(2*k1 - 1), 0.05 * r(2*k1));
verifyLessThan(tc, r(2*k2), 0.05 * r(2*k2 - 1));
y = conj(g) * z; k = setdiff(1:numel(s), [k1 k2]);
hb = reshape([imag(y(:)) < 0, real(y(:)) < 0]', [], 1);       % first bit from Im, second from Re
verifyEqual(tc, hb([2*k - 1, 2*k]), logical(b([2*k - 1, 2*k])));
d = pskdemod(z, 4, pi/4, 'gray', 'OutputType', 'bit');
verifyEqual(tc, d([2*k - 1, 2*k]), b([2*k - 1, 2*k]));
end

function test_sync_frequency_sign(tc)
% The space-time synchronization (st_sync on the delay line) reports the frequency offset
% with its sign: a known offset of +-30 kHz on the transmitted frames (three antennas,
% their own gains, 30 dB) is found within 1 kHz with the same sign, and every frame decodes.
p = base_params(); p.quiet_build = true; p.rx_sync = 'real'; p.int_aoa_random = false; p.yaw_random = false;
p.corr_random = false; p.gcs_tracked = false; p.k_random = false; p.gcs_aoa_random = false; p.body_random = false;
p.tdl = true; p.tdl_random = false; p.tdl_ds_ns = [234 0]; p.active_threat = 'none'; p.rx_combiner = 'mmse';
mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(p)');
link_seed(mdl, 31, 160);
o = sim(mdl, 'StopTime', num2str(4 * p.frame_duration));
X = squeeze(o.get('Tx_IQ')); tb = reshape(double(o.get('tx_bits_out')), p.frame_length, []);
ch = sfroot().find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/Rx']);
src = regexprep(ch.Script, 'function \[bits, iqa, z, Hq, Rq, sy\] = fcn\(u, txbits\)', ...
    'function [bits, iqa, z, Hq, Rq, sy] = rx_sign_check(u, txbits)', 'once');
close_system(mdl, 0);
fid = fopen(fullfile(pwd, 'rx_sign_check.m'), 'w'); fwrite(fid, src); fclose(fid);
rehash;
verifyGreaterThan(tc, rx_taps(p).nt, 1);                         % the space-time path
rs = RandStream('mt19937ar', 'Seed', 7);
G = [1, 0.8j, -0.6 + 0.3j];
fs = p.symbol_rate * p.sps; cyc = round(p.cycle_s * fs); Ns = size(X, 1);
for f0 = [-30e3 30e3]
    clear rx_sign_check
    for k = 1:min(size(X, 2), size(tb, 2))
        t = ((k - 1) * cyc + (0:Ns-1)') / fs;
        u = (X(:, k) .* exp(1j*2*pi*f0*t)) * G + sqrt(1e-3 / p.sps / 2) * complex(randn(rs, Ns, 3), randn(rs, Ns, 3));
        [bits, ~, ~, ~, ~, sy] = rx_sign_check(u, tb(:, k));
        if k > 1
            verifyLessThan(tc, abs(sy(2) - f0), 1e3, sprintf('f0 %g, frame %d', f0, k));
            verifyEqual(tc, double(bits(:)), tb(:, k), sprintf('f0 %g, frame %d', f0, k));
        end
    end
end
delete(fullfile(pwd, 'rx_sign_check.m'));
end

function test_equalizer_sync(tc)
% The MRC receiver on the delay line (its equalizer) on static channels of known paths
% (three antennas, 30 dB, the arrival and frequency given): (1, 2) the frame arrives at the
% end of the arrival window and a path 15.6 / 12.5 dB stronger follows one symbol later,
% beyond the window; (3) six paths in the three symbols before the strongest one; (4) the
% line of sight 3.25 symbols before a path 0.5 dB stronger, more than the equalizer's 2
% lags before the arrival on it. The frequency is found within 500 Hz and every frame
% decodes.
p = base_params(); p.quiet_build = true; p.rx_sync = 'real'; p.int_aoa_random = false; p.yaw_random = false;
p.corr_random = false; p.gcs_tracked = false; p.k_random = false; p.gcs_aoa_random = false; p.body_random = false;
p.tdl = true; p.tdl_random = false; p.tdl_ds_ns = [234 0]; p.active_threat = 'none'; p.rx_combiner = 'mrc';
mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(p)');
link_seed(mdl, 31, 160);
o = sim(mdl, 'StopTime', num2str(5 * p.frame_duration));
X = squeeze(o.get('Tx_IQ')); tb = reshape(double(o.get('tx_bits_out')), p.frame_length, []);
ch = sfroot().find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/Rx']);
src = regexprep(ch.Script, 'function \[bits, iqa, z, Hq, Rq, sy\] = fcn\(u, txbits\)', ...
    'function [bits, iqa, z, Hq, Rq, sy] = rx_eq_check(u, txbits)', 'once');
close_system(mdl, 0);
fid = fopen(fullfile(pwd, 'rx_eq_check.m'), 'w'); fwrite(fid, src); fclose(fid);
rehash;
verifyGreaterThan(tc, rx_taps(p).ne, 1);                         % the equalizer path
rs = RandStream('mt19937ar', 'Seed', 9);
fs = p.symbol_rate * p.sps; cyc = round(p.cycle_s * fs); Ns = size(X, 1);
kk = [0:ceil(Ns/2)-1, -floor(Ns/2):-1].';
G = [1, 0.8j, -0.6 + 0.3j; 0.5j, -0.9, 0.7];
a1 = G(1, :); a2 = 0.8 * G(1, :) + 0.6 * G(2, :);
C = {15.6, [0 4], [0.25 * a1; 1.5 * a1], 40e3; ...
     15.6, [0 4 9], [0.3 * a1; 1.5 * a2; 0.5 * a1], -40e3; ...
     1.0, [0 2 4 6 8 10 14], [0.5 * [a1; a2; a1; a2; a1; a2]; 1.5 * a1], -70e3; ...
     1.0, [0 13], [0.8 * a1; 1.0 * a2], 20e3};
for c = 1:size(C, 1)
    clear rx_eq_check
    [tau, dl, A, f0] = C{c, :};
    for k = 1:min(size(X, 2), size(tb, 2))
        t = ((k - 1) * cyc + (0:Ns-1)') / fs;
        u = complex(zeros(Ns, 3));
        for m = 1:numel(dl)
            xd = ifft(fft(X(:, k)) .* exp(-1j*2*pi*kk*(tau + dl(m))/Ns));
            u = u + xd * A(m, :);
        end
        u = u .* exp(1j*2*pi*f0*t) + sqrt(1e-3 / p.sps / 2) * complex(randn(rs, Ns, 3), randn(rs, Ns, 3));
        [bits, ~, ~, ~, ~, sy] = rx_eq_check(u, tb(:, k));
        if k > 1
            verifyLessThan(tc, abs(sy(2) - f0), 500, sprintf('case %d, frame %d', c, k));
            verifyEqual(tc, double(bits(:)), tb(:, k), sprintf('case %d, frame %d', c, k));
        end
    end
end
delete(fullfile(pwd, 'rx_eq_check.m'));
end

function test_packet_loss_once(tc)
% A loss event is the slack of the packet-loss criterion: one frame without FEC; with it
% (one packet per frame pair, both frames carrying its result, four frames per codeword)
% the run's longest run of consecutive lost packets, at most the two that share a frame,
% cyclic over the run's pairs, the same count at 20 and 56 frames. The monitor counts a
% lost coded packet once, at the second frame of its pair (decoded there: a result on
% another frame is not read), and only when the four frames of its codeword were received
% coded, so after a switch to the code the first packet counts on the fourth coded frame
% or later. A coded link's loss is read over ten frames (five packets): two lost packets,
% one event, do not degrade it and a third does, eight frames later too, while an
% uncoded link counts its last five frames.
z = zeros(1, 20); f = @(k) reshape([k; k], 1, []);                % frame pattern of packet results
verifyEqual(tc, packet_share('no_action', z), 1 / 20);
verifyEqual(tc, packet_share('power_control+fec_interleave', z), 1 / 10);
verifyEqual(tc, packet_share('fec_interleave', f([0 0 1 0 0 0 0 0 0 0])), 1 / 10);
verifyEqual(tc, packet_share('fec_interleave', f([0 0 1 1 0 0 0 0 0 0])), 2 / 10);
verifyEqual(tc, packet_share('fec_interleave', f([0 1 0 0 0 1 0 0 0 0])), 1 / 10);   % two events of one packet
verifyEqual(tc, packet_share('fec_interleave', f([0 1 1 1 0 0 0 0 0 0])), 2 / 10);   % at most Q/2
verifyEqual(tc, packet_share('fec_interleave', f([1 0 0 0 0 0 0 0 0 1])), 2 / 10);   % across the wrap
verifyEqual(tc, packet_share('fec_interleave', f([zeros(1, 26) 1 1])), 2 / 28);
verifyEqual(tc, packet_share('fec_interleave', f([0 0 1 1 0 0 0 0 0 0]), 2), 1 / 10);
A = policy_actions(); ic = find(strcmp(A, 'fec_interleave')); iu = find(strcmp(A, 'no_action'));
PP = struct('actions', {A}, 'classes', {{'none', 'jamming'}}, 'sps', 4, 'bps', 2, 'maha_thr', -Inf, 'fec_frames', 4);
nF = numel(link_features('names'));
crc = [0 0 0 1 0 1 0 0 0 0 0 0; 0 0 0 1 0 0 0 1 0 0 0 1; 0 0 0 0 0 0 0 1 0 0 0 1; 0 0 0 0 0 1 0 1 0 1 0 0];
mem = policy_monitor('init', 4, numel(A));                      % coded, coded, uncoded, coded from frame 3
cnt = false(4, 12);
for t = 1:12
    cl = [ic; ic; iu; ic]; if t < 3, cl(4) = iu; end
    obs = struct('probs', repmat([1 0], 4, 1), 'unknown', false(4, 1), 'feat', zeros(4, nF), ...
        'cfg_link', cl, 'pkt', floor((t - 1) / 2) * ones(4, 1));
    obs.feat(:, feature_index('crc_fail')) = crc(:, t);
    obs.feat(:, feature_index('log_ber')) = -6;
    [mem, M] = policy_monitor('update', mem, obs, PP, cl');
    cnt(:, t) = ~isnan(mem.crc(:, end));
    verifyTrue(tc, all(isfinite(M.plr)));                                  % no packet decoded yet: no loss seen
    if t == 6, verifyEqual(tc, [M.plr(1), M.degraded(1)], [1 0]); end
    if t == 8, verifyEqual(tc, M.plr(3), 1/5, 'AbsTol', 1e-12); end
end
verifyEqual(tc, cnt, logical([repmat([0 0 0 1 0 1 0 1 0 1 0 1], 2, 1); ones(1, 12); 1 1 0 0 0 1 0 1 0 1 0 1]));
verifyEqual(tc, M.plr, [2/5; 3/5; 2/5; 3/4], 'AbsTol', 1e-12);
verifyEqual(tc, M.degraded, [false true false true]);
PP.fec_frames = 2;                                                        % two frames: counted from the second
mem = policy_monitor('init', 1, numel(A));
for t = 1:4
    obs = struct('probs', [1 0], 'unknown', false, 'feat', zeros(1, nF), 'cfg_link', ic, 'pkt', floor((t + 1) / 2));
    [mem, ~] = policy_monitor('update', mem, obs, PP, ic);
    cnt(1, t) = ~isnan(mem.crc(end));
end
verifyEqual(tc, cnt(1, 1:4), logical([0 1 0 1]));
end

function [Y, H] = run_link(mdl, p, fd, kfac, rho, att, body, nfr)
% Received IQ (samples x antennas x frames) and channel estimates of one flight of the
% built model at seed 11, its blocks then set by hand.
link_seed(mdl, 11, fd);
set_param([mdl '/Kfac'], 'Value', mat2str(kfac));
set_param([mdl '/Corr'], 'Value', num2str(rho));
att(end+1:10) = 0;                                      % no roll-in (turn_attitude.m)
set_param([mdl '/Att'], 'Value', mat2str(att));
set_param([mdl '/Body'], 'Value', mat2str(body, 10));
out = sim(mdl, 'StopTime', num2str(nfr * p.frame_duration));
Y = out.get('Rx_IQ'); H = out.get('Rx_H');
end

function b = link_ber(mdl, p, ebno, seeds, nfr)
% BER of the built model p at Eb/N0 ebno [dB] over the flights seeds, nfr frames each.
evalc('build_threat_model(p)');
set_link_snr(mdl, ebno + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
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

%% ---------- received level, lost branches, path-loss steps, drop alarm ----------
function test_fixed_noise_floor(tc)
% The thermal noise is fixed and the received fields scale with Eb/N0: the quiet slot holds
% thermal noise at the same power at 0 and 12 dB, our signal's level rises by 12 dB, and an
% interferer keeps its level over our signal (its slot power rises with it).
p = base_params(); p.quiet_build = true; p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false;
p.gcs_tracked = false; p.k_random = false; p.gcs_aoa_random = false; p.body_random = false; p.tdl = false;
p.cal_random = false;                                   % the floor exact (calibration: test_level_calibration)
mdl = 'UAV_GCS_Threat_Link';
qn = p.quiet_symbols * p.sps;
for thr = {'none', 'jamming'}
    p.active_threat = thr{1}; p.jsr_db = 10;
    evalc('build_threat_model(p)');
    verifyEqual(tc, str2double(get_param([mdl '/AWGN'], 'Variance')), thermal_nv(p), 'RelTol', 1e-9);
    qs = zeros(1, 2); rs = zeros(1, 2); qi = zeros(1, 2);
    E = [0 12];
    for k = 1:2
        g = set_link_snr(mdl, E(k) + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
        verifyEqual(tc, g, 10^(E(k) / 20), 'RelTol', 1e-9);       % our signal's amplitude at unit symbol energy
        link_seed(mdl, 21, 160);
        out = sim(mdl, 'StopTime', num2str(8 * p.frame_duration));
        F = extract_closed_loop_frames(out, p, 20);
        U = out.get('Rx_IQ');
        qs(k) = 10*log10(mean(abs(U(1:qn, :, :)).^2, 'all'));
        rs(k) = median(F.rssi); qi(k) = median(F.q_iot);
    end
    if strcmp(thr{1}, 'none')
        verifyEqual(tc, qs, 10*log10(thermal_nv(p)) * [1 1], 'AbsTol', 0.5);   % the floor does not move
        pw = @(e) 10*log10(10^(e / 10) / p.sps + thermal_nv(p));               % our signal + noise per sample
        verifyEqual(tc, rs(2) - rs(1), pw(12) - pw(0), 'AbsTol', 1.5);
        verifyLessThan(tc, abs(qi), 1);
    else
        verifyEqual(tc, qs(2) - qs(1), 12, 'AbsTol', 1);                         % the jammer scales with our signal
        verifyEqual(tc, qi(2) - qi(1), 12, 'AbsTol', 1);
    end
    close_system(mdl, 0);
end
% the detector image keeps the absolute level: thermal noise near 0 dB over the floor of a bin
img = spec_image(sqrt(thermal_nv(p) / 2) * complex(randn(4096, 1), randn(4096, 1)), p.symbol_rate * p.sps, thermal_nv(p));
verifyEqual(tc, median(img(:)) * 80 - 25, -1.6, 'AbsTol', 1);   % the median of an exponential bin is 1.6 dB below its mean
% the AGC and the ADC follow the received level: a field n dB stronger (whole dB, the gain
% grid) gives the same quantized samples n dB stronger, with or without the fast attack
rs = RandStream('mt19937ar', 'Seed', 5);
u = complex(randn(rs, 2000, 3), randn(rs, 2000, 3)); u(900:1100, 2) = 20 * u(900:1100, 2);
for att = [Inf p.adc_attack_db]
    [y0, f0, c0] = adc_frontend(u, p.adc_bits, p.adc_backoff_db, 1:200, 201:264, att);
    for n = [-17 23]
        [y1, f1, c1] = adc_frontend(u * 10^(n / 20), p.adc_bits, p.adc_backoff_db, 1:200, 201:264, att);
        verifyEqual(tc, y1, y0 * 10^(n / 20), 'RelTol', 1e-9);
        verifyEqual(tc, [f1 c1], [f0 * 10^(n / 20) c0], 'RelTol', 1e-9);
    end
end
end

function test_fault_scales_interferer(tc)
% An open connector sits between its antenna and the receiver: it attenuates the jammer on
% that antenna as much as our signal, and the receiver's thermal noise stays.
p = base_params(); p.quiet_build = true; p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false;
p.gcs_tracked = false; p.k_random = false; p.gcs_aoa_random = false; p.body_random = false; p.tdl = false;
p.active_threat = 'jamming+antenna_fault'; p.jsr_db = 16; p.fault_atten_db = 31;
mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(p)');
set_link_snr(mdl, 12 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
link_seed(mdl, 31, 160);
out = sim(mdl, 'StopTime', num2str(6 * p.frame_duration));
F = extract_closed_loop_frames(out, p, 20);
U = out.get('Rx_IQ'); qn = p.quiet_symbols * p.sps;
qa = 10*log10(squeeze(mean(mean(abs(U(1:qn, :, :)).^2, 1), 3)));    % the slot's power per antenna: jammer + noise
[qlo, ia] = min(qa);
[~, ig] = min(mean(F.gain_ant, 2));
verifyEqual(tc, ia, ig);                                            % the jammer is low where our signal is
verifyLessThan(tc, qlo - median(qa(setdiff(1:p.n_rx, ia))), -20);
verifyLessThan(tc, qlo - 10*log10(thermal_nv(p)), 6);             % close to the thermal floor there
close_system(mdl, 0);
end

function test_path_loss_onset(tc)
% A path-loss step starts at its onset frame: no threat on the air before it, our signal's
% level drops by the loss from it on; labels and fused targets count it while the onset
% lies in the window.
p = base_params(); p.quiet_build = true; p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false;
p.gcs_tracked = false; p.k_random = false; p.gcs_aoa_random = false; p.body_random = false; p.tdl = false;
p.cal_random = false;
p.active_threat = 'path_loss'; p.path_loss_db = 14; p.pl_onset_frames = [5 5];
mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(p)');
set_link_snr(mdl, 15 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
link_seed(mdl, 41, 160);
F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(9 * p.frame_duration)), p, 20);
verifyEqual(tc, F.act(1:F.nf), double((1:F.nf) >= 5));
verifyEqual(tc, F.act_comp(1, :), F.act);
verifyEqual(tc, received_ebno(p.active_threat, 15, F.act_comp, p.path_loss_db), 15 - 14 * ((1:F.nf) >= 5));   % the received Eb/N0
pw = @(e) 10*log10(10^(e / 10) / p.sps + thermal_nv(p));                     % our signal + noise per sample
verifyEqual(tc, median(F.rssi(1:4)) - median(F.rssi(6:F.nf)), pw(15) - pw(1), 'AbsTol', 1.5);
verifyLessThan(tc, abs(median(F.q_iot)), 1);                       % the floor stays: no interference
% the onset drawn per run inside the range
p.pl_onset_frames = [2 11];
evalc('build_threat_model(p)');
on = zeros(1, 6);
for r = 1:6
    link_seed(mdl, 50 + r, 160);
    F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(11 * p.frame_duration)), p, 20);
    on(r) = find(F.act > 0, 1);
end
verifyTrue(tc, all(on >= 2 & on <= 11));
verifyGreaterThan(tc, numel(unique(on)), 1);
close_system(mdl, 0);
% labels: from the onset while the link-feature window still holds a frame before it
verifyEqual(tc, threat_active('path_loss', [0 0 1 1 1 1 1], 1:7, 3), logical([0 0 1 1 0 0 0]));
verifyEqual(tc, threat_active('path_loss', [0 1 1 1 1 1 1 1 1 1 1 1], 1:12, 10), logical([0 1 1 1 1 1 1 1 1 1 0 0]));
verifyEqual(tc, threat_active('path_loss', [1 1 1]), true(1, 3));     % without positions: every attenuated frame
% fused targets: a clean frame whose fusion window holds the onset reads path_loss
cls = {'none', 'path_loss', 'benign_interference'};
y = [1 1 2 2 1 1 1];
yt = fusion_target(y, ones(1, 7), 1:7, 4, cls);
verifyEqual(tc, yt', [1 1 2 2 2 2 1]);
verifyEqual(tc, fusion_target(y, ones(1, 7), 1:7, 1, cls)', y);
end

function test_shadow_attitude(tc)
% Airframe shadowing needs the airframe in the line of sight: the GCS above the belly's
% horizon in the body frame (banking toward it by more than its elevation), more than 30 deg
% off the heading (Sun et al., Sec. III), in an event whose deepest burial (the bank, the GCS
% abeam) is as deep as the rolls the level is measured at bury it at Sun et al.'s elevation
% (Table II, C-band fit: within 1.96 sigma of the level; the equivalent roll,
% shadow_equiv_roll.m), never while hovering; it hides the end of the array farther from
% the GCS. A fixed view banks so that its equivalent roll is the fit's.
p = base_params(); es = p.shadow_el_deg;
verifyEqual(tc, es, 2.9);
[b, r0] = shadow_roll_band(6, p);
verifyEqual(tc, b, [16.1 25.0], 'AbsTol', 0.05); verifyEqual(tc, r0, 16.1 - es, 'AbsTol', 1e-9);
[b, r0] = shadow_roll_band(15.5, p);
verifyEqual(tc, b, [16.1 57.9], 'AbsTol', 1e-9); verifyEqual(tc, r0, 16.1 + (15.5 - 12.4) / 0.25 - es, 'AbsTol', 1e-9);
verifyEqual(tc, shadow_equiv_roll(0, 0, r0, 0, es), 28.5, 'AbsTol', 1e-9);       % abeam on the horizon: the bank plus 2.9 deg
verifyEqual(tc, shadow_roll_band(15.5, p, 4) - shadow_roll_band(15.5, p, 0), [0 0]);
[~, r4] = shadow_roll_band(15.5, p, 4);
verifyEqual(tc, shadow_equiv_roll(0, 4, r4, 0, es), 28.5, 'AbsTol', 1e-9);
[b, r0] = shadow_roll_band(25, p);
verifyEqual(tc, b, [32.0 57.9], 'AbsTol', 0.05); verifyEqual(tc, r0, 57.9 - es, 'AbsTol', 1e-9);
verifyEqual(tc, shadow_roll_band(40, p), [Inf -Inf]);            % no roll supports it: never flown
B = [16.1 57.9]; v = 20; vm = p.shadow_v_min;
for el = [0 0.5 1 2 2.9]                                         % a view on the band's edge (the clamped levels) hides an antenna
    for L = [6 12.4 15.5 22.5 22.85 23 25]
        [bd, r] = shadow_roll_band(L, p, el);
        verifyEqual(tc, shadow_frame(0, el, r, r, 0, 3, bd, 30, v, vm, es), 3, sprintf('%g dB, %g deg', L, el));
        verifyEqual(tc, shadow_hidden(0, el, r, 0, 3, bd, 30, v, vm, es), 3, sprintf('%g dB, %g deg', L, el));
    end
end
for rm = [57.5 57.6 57.7 57.8]                                   % and with another bank limit
    pm = p; pm.roll_max_deg = rm; [bd, r] = shadow_roll_band(25, pm);
    verifyEqual(tc, shadow_frame(0, 0, r, r, 0, 3, bd, 30, v, vm, es), 3, sprintf('%g deg', rm));
end
verifyEqual(tc, shadow_frame(0, 0, 16.1 - es - 1e-4, 16.1 - es - 1e-4, 0, 3, B, 30, v, vm, es), 0);   % just below the band: none
verifyEqual(tc, shadow_hidden(0, 2, 20, 0, 3, B, 30, v, vm, es), 3);       % GCS abeam on the right, banking toward it: the aft end
verifyEqual(tc, shadow_hidden(0, 2, -20, 0, 3, B, 30, v, vm, es), 0);      % banking away: the belly sees it
verifyEqual(tc, shadow_hidden(0, 25, 20, 0, 3, B, 30, v, vm, es), 0);      % 25 deg below: a 20 deg bank keeps it under the belly
verifyEqual(tc, shadow_hidden(40, 2, 20, 0, 3, B, 30, v, vm, es), 3);      % ahead of the beam: the aft end
verifyEqual(tc, shadow_hidden(-40, 2, 20, 0, 3, B, 30, v, vm, es), 1);     % behind it: the front end
verifyEqual(tc, shadow_hidden(-40, 2, 20, 0, 4, B, 30, v, vm, es), 1);
verifyEqual(tc, shadow_hidden(70, 2, 20, 0, 3, B, 30, v, vm, es), 0);      % 20 deg off the nose
verifyEqual(tc, shadow_hidden(0, 2, 10, 0, 3, B, 30, v, vm, es), 0);       % buried less than at the smallest roll of the measured events
verifyEqual(tc, shadow_hidden(0, 2, 20, 0, 3, [32 57.9], 30, v, vm, es), 0);   % a burial the level is not measured at
verifyEqual(tc, shadow_hidden(0, 2, 20, 0, 3, B, 30, 7, vm, es), 0);       % hovering or holding position in wind
verifyEqual(tc, shadow_hidden(0, 15, 17, 0, 3, B, 30, v, vm, es), 0);      % 15 deg below, a 17 deg bank: 2 deg deep, not Sun's 16.1 deg roll
verifyEqual(tc, shadow_hidden(0, 15, 29, 0, 3, B, 30, v, vm, es), 3);      % 14 deg deep: as Sun's 16.9 deg roll
% the flights' draws: the hidden antenna at every frame start as the model's channel takes it
q = p; q.active_threat = 'airframe_shadowing'; q.shadow_db = 15.5;
s = shadow_spec(q);
verifyEqual(tc, s, [15.5 16.1 57.9 30 8 -16 5 2.9], 'AbsTol', 1e-9);
verifyEqual(tc, shadow_spec(p), zeros(1, 8));                           % no shadowing in the threat
for k = 1:200
    fd = 40 + 2 * k;                                                    % 5-55 m/s
    d = flight_draws(k, fd, q, struct('ebno', 9));
    vk = fd * q.c_light / q.carrier_freq;
    hs = arrayfun(@(j) shadow_hidden(d.gcs_aoa + d.yaw * (j - 1) * q.cycle_s, d.el_deg, d.roll, d.pitch, q.n_rx, ...
        s(2:3), s(4), vk, s(5), s(8)), 1:q.cap_frames);
    verifyEqual(tc, d.shadow_g > 0, hs > 0);
    verifyEqual(tc, d.hidden, hs .* (s(1) * d.shadow_g >= s(7)));    % counted from the event's 5 dB
end
verifyEqual(tc, flight_draws(3, 30, q, struct('ebno', 9)).hidden, zeros(1, q.cap_frames));   % 3.75 m/s: none
h = shadow_hit_share(q, 800);
verifyGreaterThan(tc, h, 0.15); verifyLessThan(tc, h, 0.35);
q6 = q; q6.shadow_db = 6;
verifyLessThan(tc, shadow_hit_share(q6, 800), h);                      % a level paired with fewer rolls
% the dataset flies its shadowing cells on flights that hide an antenna, one per fold
txt = fileread(which('run_dataset_sweep'));
verifyNotEmpty(tc, regexp(txt, 'while shd && ~hides_antenna\(', 'once'));
verifyNotEmpty(tc, regexp(fileread(which('hides_antenna')), 'any\(d\.hidden > 0\)', 'once'));
% the fixed views fly the bank whose equivalent roll the fit pairs with the level, the GCS
% abeam, a coordinated turn; the survivability map's view (57 frames at 72 km/h, the turn
% carrying the GCS through the beam at mid-run) hides an antenna over the whole run, the
% level's whole depth at mid-run and within 0.5 dB of it over the run
q.yaw_random = false; q.gcs_aoa_random = false; [~, q.roll_deg] = shadow_roll_band(q.shadow_db, q);
d = flight_draws(7, 100, q);
verifyEqual(tc, d.roll, 28.5 - es, 'AbsTol', 1e-9);
verifyGreaterThan(tc, d.hidden(1), 0);
verifyNotEmpty(tc, strfind(fileread(which('map_survivability_boundary')), ['p.gcs_aoa_deg = p.gcs_aoa_deg - ' ...
    'rad2deg(9.81 * tand(p.roll_deg) / max(p.v_nominal, p.turn_v_floor)) * (RUN_FRAMES - 1) * p.cycle_s / 2;']));
for L = [6 8 12 15.5 20 22.5 23 25]
    qv = q; qv.shadow_db = L; qv.alt_random = false; qv.cap_frames = 57; [~, qv.roll_deg] = shadow_roll_band(L, qv);
    qv.gcs_aoa_deg = qv.gcs_aoa_deg - rad2deg(9.81 * tand(qv.roll_deg) / max(qv.v_nominal, qv.turn_v_floor)) * 56 * qv.cycle_s / 2;
    dv = flight_draws(7, qv.v_nominal * qv.carrier_freq / qv.c_light, qv);
    verifyTrue(tc, all(dv.hidden > 0), sprintf('%g dB', L));
    verifyEqual(tc, L * dv.shadow_g(29), L, 'AbsTol', 1e-6, sprintf('%g dB', L));
    verifyGreaterThan(tc, L * min(dv.shadow_g), L - 0.5, sprintf('%g dB', L));
end
v = max(100 * q.c_light / q.carrier_freq, q.turn_v_floor);
verifyEqual(tc, d.yaw, rad2deg(9.81 * tand(q.roll_deg) / v), 'RelTol', 1e-9);
verifyEqual(tc, bank_angle(d.yaw, 100, q), q.roll_deg, 'AbsTol', 1e-9);   % above the speed floor
verifyEqual(tc, flight_draws(7, 0, q).yaw, 0);
verifyEqual(tc, flight_draws(7, 0, q).hidden, zeros(1, q.cap_frames));  % hover: a tilt, no shadowing
q.roll_deg = 0;
verifyEqual(tc, flight_draws(7, 100, q).yaw, 0);
end

function test_threat_on_air(tc)
% A threat cell whose threat never reaches the air in a geometry (airframe shadowing in
% level flight: act 0 in every frame, pool_cell.m) holds no threat episode there: link_env.m
% K.on, and the episodes rolled out on it count as no threat (dqn_eval_batches.m).
[PP, ~] = toy_world(true);
na = find(strcmp(PP.actions, 'no_action'));
for a = 1:numel(PP.actions)
    for s = 1:2
        for c = 1:2
            PP.pools{c, s, a, 1}.act = zeros(20, 1, 'single');
        end
    end
end
K = link_env('tables', PP);
verifyFalse(tc, any(K.on(:)));
PP.pools{2, 1, na, 1}.act(7) = 1;                       % on the air in one frame at the first Eb/N0
K = link_env('tables', PP);
verifyEqual(tc, squeeze(K.on(:, :, 1, 1)), logical([0 0; 1 0]));
spec = struct('scn', [2 2 1], 's', [1 2 1], 'onset', [1 1 1], 'follow', false(1, 3), 'fdelay', [0 0 0], ...
    'unk', false(1, 3), 'T', 5, 'r', [1 1 1]);
R = dqn_eval_batches('fixed', PP, K, {spec}, [], struct('fixed', na), 1, 1);
verifyEqual(tc, R.threat, logical([1 0 0]));
[PP, K] = toy_world(true);                             % pools without act: every threat cell on the air
verifyEqual(tc, squeeze(K.on(:, :, 1, 1)), logical([0 0; 1 1]));
end

function test_rule_lost_branch_and_drop(tc)
% A lost branch (fault or shadowing) takes power_control, with spatial_diversity only where
% the receiver predicts a separable interferer; a drop alarm without a class answers with
% power_control, and rate_reduce on top when the link is degraded too.
C = decision_config();
for c = {'antenna_fault', 'airframe_shadowing'}
    verifyEqual(tc, rule_based_policy(c{1}), 'power_control');
    verifyEqual(tc, rule_based_policy(c{1}, false, C.rule_mmse_db - 1), 'power_control');
    verifyEqual(tc, rule_based_policy(c{1}, false, C.rule_mmse_db), 'spatial_diversity+power_control');
end
verifyEqual(tc, rule_based_policy('none', false, 0, -Inf, 3, true), 'power_control');
verifyEqual(tc, rule_based_policy('none', true, 0, -Inf, 3, true), 'rate_reduce+power_control');
verifyEqual(tc, rule_based_policy('unknown', false, 0, -Inf, 3, true), 'power_control');
verifyEqual(tc, rule_based_policy('none', true, 0, 10, 3, true), 'channel_switch');      % interference in the slot
verifyEqual(tc, rule_based_policy('benign_interference', false, 0, -Inf, 3, true), 'no_action');
verifyEqual(tc, rule_based_policy('jamming', false, 0, -Inf, 3, true), 'channel_switch');
A = policy_actions();
verifyTrue(tc, all(ismember({'power_control', 'spatial_diversity+power_control', 'rate_reduce+power_control'}, A)));
[~, names] = branch_level({'none', 'antenna_fault', 'airframe_shadowing', 'jamming'});
verifyEqual(tc, names, {'none'; 'one_branch_lost'; 'jamming'});
end

function test_drop_alarm(tc)
% The monitor's drop alarm fires on a 4 dB step of our signal over thermal noise within a
% few cycles, and not on the clean link moving away at the largest rate, 1.4 dB/s
% (161 km/h at 0.28 km, 8.69 v / d), over 3 s.
A = policy_actions();
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'confirm', [2 2], ...
    'alarm_mode', 'class_drop', 'drop_db', 4);
o = struct('probs', double(strcmp(cls, 'none')), 'unknown', false, 'feat', zeros(1, numel(link_features('names'))));
o.feat(feature_index('log_ber')) = -6;
eb = @(e) e - 10*log10(PP.sps) + 10*log10(PP.bps);              % SINR (iot 0) for an Eb/N0 estimate e
p = base_params();
ramp = 20 / log(10) * p.v_max / (1000 * link_distance_km(15, p));
verifyLessThan(tc, ramp, 1.5);
dt = decision_config().period_ms / 1000;
seqs = {[15 * ones(1, 15), 11 * ones(1, 10)], 15 - ramp * dt * (0:149)};
first = nan(1, 2); conf = nan(1, 2);
for j = 1:2
    m = []; cfg = find(strcmp(A, 'no_action'));
    for k = 1:numel(seqs{j})
        x = o; x.feat(feature_index('sinr')) = eb(seqs{j}(k));
        [a, m, d] = policy_decide('rule_esc', x, cfg, m, PP, []);
        if d.drop_alarm && isnan(first(j)), first(j) = k; end
        if a ~= cfg && isnan(conf(j)), conf(j) = k; verifyEqual(tc, A{a}, 'power_control'); end
    end
end
verifyLessThanOrEqual(tc, first(1) - 15, 3);                     % the step at cycle 16
verifyLessThanOrEqual(tc, conf(1) - 15, 5);                      % confirmed, then the rule's dwell
verifyTrue(tc, isnan(first(2)) && isnan(conf(2)));
end

%% ---------- link, threats and dataset after the pre-launch review ----------
function test_reactive_trigger(tc)
% The reactive jammer listens to our transmitted frame (the Tx output, before any channel):
% with our signal gone at the UAV ('GCS' 0) it still jams, from the frame's first sample
% above its energy detector's threshold plus the reaction delay (3.75 us, 15 samples,
% Wilhelm et al.) to the frame's last, and is silent outside; after a path-loss step it
% keeps jamming at its fixed power.
p = base_params(); p.quiet_build = true; p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false;
p.gcs_tracked = false; p.k_random = false; p.gcs_aoa_random = false; p.body_random = false; p.tdl = false;
p.wobble_random = false; p.cal_random = false; p.rx_sync = 'ideal'; p.int_rician_k = 30;
p.chain_amp_db = 0; p.chain_phase_deg = 0; p.active_threat = 'reactive_jamming'; p.jsr_db = 30;
mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(p)');
src = sfroot().find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/Threat']).Script;
verifyNotEmpty(tc, regexp(src, 'abs\(xt\(i\)\)\^2', 'once'));            % the trigger is our transmitter's output
verifyEmpty(tc, regexp(src, 'abs\(ys\(', 'once'));
set_link_snr(mdl, 20 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
link_seed(mdl, 41, 160);
set_param([mdl '/GCS'], 'Value', '0');
out = sim(mdl, 'StopTime', num2str(3 * p.frame_duration));
close_system(mdl, 0);
X = squeeze(out.get('Tx_IQ')); Y = out.get('Rx_IQ'); nv = thermal_nv(p);
dr = round(p.reactive_delay_s * p.symbol_rate * p.sps);
verifyEqual(tc, dr, 15);
for f = 2:3
    a = find(abs(X(:, f)).^2 > p.reactive_threshold / p.sps);
    P = mean(abs(Y(:, :, f)).^2, 2);
    verifyLessThan(tc, mean(P(1:a(1) + dr - 2)), 3 * nv);              % the quiet slot and the reaction delay
    verifyGreaterThan(tc, mean(P(a(1) + dr + 1:a(end))), 300 * nv);    % on over the frame
    verifyLessThan(tc, mean(P(a(end) + 2:end)), 3 * nv);               % off after it
end
% after a 22 dB path-loss step the jammer stays on, at the power the cap fixed for the run
p.active_threat = 'reactive_jamming+path_loss'; p.jsr_db = 16; p.path_loss_db = 22; p.pl_onset_frames = [4 4];
p.rx_sync = 'real';
evalc('build_threat_model(p)');
set_link_snr(mdl, 12 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
link_seed(mdl, 41, 160);
F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(8 * p.frame_duration)), p, 20);
close_system(mdl, 0);
verifyGreaterThan(tc, min(F.q_react), 10);
verifyEqual(tc, median(F.q_react(5:F.nf)), median(F.q_react(1:3)), 'AbsTol', 2);
verifyEqual(tc, F.act, ones(1, F.nf));
verifyEqual(tc, F.act_comp(2, :), double((1:F.nf) >= 4));
verifyEqual(tc, F.lev_db(1, 5:F.nf), 30 * ones(1, F.nf - 4), 'AbsTol', 0.5);   % at the cap after the step
end

function test_inband_cap_run(tc)
% The in-band cap holds on every antenna over the run (Liu et al.: 30 dB): a 23 dB jammer
% on a flight in which the airframe hides an antenna by 20 dB reaches about 30 dB over our
% signal there (43 dB if the cap left the depth out) and about 10 dB on the others, its
% power fixed; the recorded level never exceeds the cap; and the cap's reference is our
% signal's weakest antenna over the run, the depth included (flight_draws.m, d.cap_amp).
p = base_params(); p.quiet_build = true; p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false;
p.gcs_tracked = false; p.k_random = false; p.gcs_aoa_random = false; p.body_random = false; p.tdl = false;
p.wobble_random = false; p.cal_random = false; p.rician_k = 30; p.int_rician_k = 30; p.chain_amp_db = 0;
p.chain_phase_deg = 0; p.jsr_db = 23; p.shadow_db = 20; [~, p.roll_deg] = shadow_roll_band(p.shadow_db, p);
mdl = 'UAV_GCS_Threat_Link'; nf = 20; qn = p.quiet_symbols * p.sps;
pw = zeros(3, p.n_rx);
for c = 1:3
    q = p;
    if c == 3, q.active_threat = 'airframe_shadowing'; else, q.active_threat = 'jamming+airframe_shadowing'; end
    evalc('build_threat_model(q)');
    set_link_snr(mdl, 40 + 10*log10(q.bits_per_symbol) - 10*log10(q.sps), q);
    d = link_seed(mdl, 51, 160);
    if c == 2, set_param([mdl '/GCS'], 'Value', '0'); end           % the jammer alone
    out = sim(mdl, 'StopTime', num2str((nf - 1) * q.frame_duration));
    U = out.get('Rx_IQ');
    pw(c, :) = reshape(mean(abs(U(qn+1:end, :, :)).^2, [1 3]), 1, []) - thermal_nv(q);
    if c == 1, F = extract_closed_loop_frames(out, q, 20); end
    close_system(mdl, 0);
end
hs = d.hidden(1);
verifyGreaterThan(tc, hs, 0);
verifyTrue(tc, all(d.hidden == hs));
verifyLessThan(tc, 20*log10(d.cap_amp / d.gcs_amp), -19);             % the depth is in the reference
jsr = 10*log10(pw(2, :) ./ pw(3, :)) - 10*log10(p.sps);              % in band: the jammer fills the sampled band, our signal 1 / sps of it
verifyEqual(tc, jsr(hs), 30, 'AbsTol', 1.5);
verifyEqual(tc, jsr(setdiff(1:p.n_rx, hs)), 10 * ones(1, p.n_rx - 1), 'AbsTol', 2);
verifyLessThanOrEqual(tc, max(F.lev_db(1, :)), 30 + 1e-6);
verifyGreaterThan(tc, min(F.lev_db(1, :)), 29);
verifyEqual(tc, F.act_comp(1:2, :), ones(2, F.nf));
end

function test_combination_on_air(tc)
% A combination is on the air while any of its components is: a spoofer with a sweeping
% jammer counts in every frame, the sweeper's own share kept per component; with gated
% components only the 10% rule of the gated threats holds.
verifyEqual(tc, threat_active('benign_interference+sweeping_jammer', [0 0.05 0.3 1]), [false false true true]);
verifyEqual(tc, threat_active('jamming+airframe_shadowing', [1 1]), [true true]);
verifyEqual(tc, threat_active('airframe_shadowing', [0 1]), [false true]);
p = base_params(); p.quiet_build = true; p.active_threat = 'spoofing+sweeping_jammer'; p.jsr_db = 16; p.seed = 11;
p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false; p.gcs_tracked = false; p.k_random = false;
p.gcs_aoa_random = false; p.body_random = false; p.wobble_random = false; p.jam_timing_random = false; p.tdl = false;
mdl = 'UAV_GCS_Threat_Link'; nfr = 8; gate = [25e-3 0.2e-3 0 0.5];
evalc('build_threat_model(p)');
set_link_snr(mdl, 15 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
link_seed(mdl, 11, 160);
set_param([mdl '/Gate'], 'Value', mat2str(gate));
F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str((nfr - 1) * p.frame_duration)), p, 20);
close_system(mdl, 0);
fs = p.symbol_rate * p.sps; ns = p.air_symbols * p.sps;
t = (0:ns-1)' / fs + (0:nfr-1) * round(p.cycle_s * fs) / fs;
g = sweep_window_s(p); a = mean(mod(t + gate(2), gate(1)) >= g(1) & mod(t + gate(2), gate(1)) < g(2), 1);
verifyGreaterThan(tc, nnz(a == 0), 0);
verifyEqual(tc, F.act, ones(1, nfr));                                   % the spoofer is always on the air
verifyEqual(tc, F.act_comp(1, :), ones(1, nfr));
verifyEqual(tc, F.act_comp(2, :), a, 'AbsTol', 1e-9);
verifyTrue(tc, all(isnan(F.act_comp(3, :))) && all(isnan(F.lev_db(3, :))));
verifyTrue(tc, all(isfinite(F.lev_db(1:2, :)), 'all'));
verifyEqual(tc, threat_active(p.active_threat, F.act), true(1, nfr));
end

function test_received_ebno(tc)
% The received Eb/N0 of a frame: the configured value less a path-loss step on the frames
% where it is on the air, in the dataset, the splits (the second test set too), the pools
% and the detector's blocks.
verifyEqual(tc, received_ebno('path_loss', 12, [0 0 1 1], 14), [12 12 -2 -2]);
verifyEqual(tc, received_ebno('jamming+path_loss', 12, [1 1; 0 1; NaN NaN], 14), [12 -2]);
verifyEqual(tc, received_ebno('jamming', 9, [1 1 1], 14), [9 9 9]);
verifyEqual(tc, received_ebno('none', 9, nan(3, 2), 14), [9 9]);
txt = fileread(which('run_dataset_sweep'));
verifyNotEmpty(tc, regexp(txt, 'D\.ebno_rx = \[D\.ebno_rx, received_ebno\(', 'once'));
verifyNotEmpty(tc, regexp(txt, 'dataset\.ebno_rx = ', 'once'));
verifyNotEmpty(tc, regexp(fileread(which('extract_spectrograms')), 'spec\.ebno_rx = ds\.ebno_rx', 'once'));
txt = fileread(which('prepare_data'));
verifyNotEmpty(tc, regexp(txt, 'splits\.\(names\{i\}\)\.ebno_rx = sp0\.ebno_rx\(m\)', 'once'));
verifyNotEmpty(tc, regexp(txt, 'splits\.test\.ebno_rx = sp0\.ebno_rx', 'once'));    % splits_fresh.mat
verifyNotEmpty(tc, regexp(fileread(which('pool_cell')), 'Q\.ebno_rx = \[Q\.ebno_rx', 'once'));
verifyEqual(tc, nargout('detector_block'), 4);
end

function test_dataset_balance(tc)
% Every class keeps its labelled frames: a path-loss cell N_SUB F_SUB / (TW - 1) sub-runs
% (9 labelled frames of 20), the WLAN N_SUB over its labelled share by the frame rule, the
% per-frame network's labels (about 0.58, 10), which holds the per-cycle labels' need too
% (above 0.8, at most 7), the sweeper over its (about 0.13, 46; per cycle about 0.56, 11);
% the extra sub-runs go round the folds from cell to cell, each level starting one fold
% further, so every fold holds about the same share of every Eb/N0 point.
p = base_params(); q = p; q.idle_rssi_hz = 0;
h = benign_hit_share(q);                                % the dataset's: 3000 runs of 20 frames
verifyGreaterThan(tc, h, 0.5); verifyLessThan(tc, h, 0.65);
verifyEqual(tc, round(6 / h), 10);
hc = benign_hit_share(p);                               % per decision cycle (threat_active.m with act_idle)
verifyGreaterThan(tc, hc, 0.8); verifyLessThanOrEqual(tc, round(6 / hc), 7);
verifyEqual(tc, max(round(6 / h), round(6 / hc)), 10);
hs = sweep_hit_share(q); hsc = sweep_hit_share(p);
verifyLessThan(tc, hs, hsc);
verifyEqual(tc, max(round(6 / hs), round(6 / hsc)), round(6 / hs));
verifyEqual(tc, round(6 / hs), 46, 'AbsTol', 3);
txt = fileread(which('run_dataset_sweep'));
verifyNotEmpty(tc, regexp(txt, 'round\(N_SUB \* F_SUB / \(TW - 1\)\)', 'once'));
verifyNotEmpty(tc, strfind(txt, 'q           = p0; q.idle_rssi_hz = 0;'));
verifyNotEmpty(tc, strfind(txt, 'max(round(N_SUB / hit_f), round(N_SUB / hit))'));
verifyNotEmpty(tc, strfind(txt, 'max(round(N_SUB / wlan_f), round(N_SUB / wlan))'));
verifyNotEmpty(tc, regexp(txt, 'FOLD\(nk \+ lv - 1\)', 'once'));
for ns = [8 10 13 46]                                   % fault and shadowing, WLAN, path loss, sweeper
    k = 0; fo = zeros(8, 6, ns);                        % 8 levels x 6 Eb/N0 points x ns sub-runs
    for lv = 1:8
        for e = 1:6
            for j = 1:ns, k = k + 1; fo(lv, e, j) = mod(k + lv - 2, 6) + 1; end
        end
    end
    for f = 1:6
        m = fo == f;
        verifyEqual(tc, nnz(m), 8 * ns);                                         % every fold the same share
        verifyEqual(tc, reshape(sum(m, [2 3]), 1, []), ns * ones(1, 8));          % of every level
        verifyLessThanOrEqual(tc, max(abs(reshape(sum(m, [1 3]), 1, []) - 8 * ns / 6)), 2);   % and Eb/N0 point
    end
    nf = arrayfun(@(i) numel(unique(fo(mod(i - 1, 8) + 1, ceil(i / 8), :))), 1:48);
    verifyEqual(tc, nf, 6 * ones(1, 48));                                       % every cell in every fold
end
end

function test_noise_burst_duty(tc)
% Noise bursts, one of two measured patterns per flight. Xu et al.'s random jammer at their
% duties (50% and 77.5%): bursts of U[0, 31] symbols and sleeps that give the duty, at most
% 31 symbols, so the share of the time on matches the duty, a burst lasts 15.5 symbols on
% average and a 32-symbol quiet slot is hardly ever free of it. Marti et al.'s sparse jammer
% J4 at 20%: one-symbol slots of its own clock, each jammed with probability 0.2, so a run of
% jammed slots lasts 1 / (1 - 0.2) = 1.25 symbols on average and a 32-symbol window is free
% of it with probability 0.8^32 = 0.08%.
p = base_params(); p.quiet_build = true; p.active_threat = 'noise_burst'; p.jsr_db = 30; p.seed = 11;
p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false; p.gcs_tracked = false; p.k_random = false;
p.gcs_aoa_random = false; p.body_random = false; p.wobble_random = false; p.jam_timing_random = false; p.tdl = false;
p.int_rician_k = 30; p.cal_random = false;
mdl = 'UAV_GCS_Threat_Link'; nv = thermal_nv(p);
evalc('build_threat_model(p)');
set_link_snr(mdl, 10 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
for a = [0.2 0.5 0.775]
    link_seed(mdl, 11, 160);
    set_param([mdl '/GCS'], 'Value', '0');
    set_param([mdl '/Gate'], 'Value', mat2str([20e-3 0 0.5 a]));
    Y = sim(mdl, 'StopTime', num2str(12 * p.frame_duration)).get('Rx_IQ');
    on = squeeze(mean(abs(Y).^2, 2)) > 30 * nv;                         % samples x frames
    verifyEqual(tc, mean(on, 'all'), a, 'AbsTol', 0.05 + 0.03 * (a > 0.2));
    r = diff([false; on(:); false]); len = (find(r == -1) - find(r == 1)) / p.sps;
    w = 32 * p.sps; W = reshape(on(1:floor(size(on, 1) / w) * w, :), w, []);
    free = mean(~any(W, 1));                                            % 32-symbol windows without a jammed sample
    if a == 0.2
        verifyEqual(tc, mean(len), 1 / (1 - a), 'AbsTol', 0.15);
        verifyLessThan(tc, free, 0.01);
    elseif a == 0.5
        verifyEqual(tc, mean(len), p.burst_on_sym / 2, 'AbsTol', 4);
        verifyLessThan(tc, free, 0.05);
    end
end
close_system(mdl, 0);
end

function test_shadow_burial(tc)
% Sun et al. measured their events at 1.4-2.9 deg elevation (Part IV, Sec. II), where the
% roll sets how deep the airframe lies in the line of sight; in their turns the station
% passed the beam. An event is paired with their fit by its deepest burial, the bank with the
% GCS abeam, through the equivalent roll at 2.9 deg (shadow_equiv_roll.m): their geometry
% maps onto itself; a 15 deg elevation under a 16.1 deg bank grazes the belly by 1.1 deg,
% Sun et al.'s 4 deg roll, and takes no level. Within an event the depth follows the burial
% (Sun et al.'s shape on its progress), so the whole depth lies only near the deepest
% burial, at least the band's smallest roll less 2.9 deg (13.2 deg at 16.1 deg, 29.1 deg at
% 32 deg), beyond what Sun et al.'s geometry gives at that roll anywhere off the nose (5.2
% and 12.8 deg); the dataset's shadowing flights carry exactly that share.
p = base_params(); es = p.shadow_el_deg;
verifyEqual(tc, shadow_equiv_roll(0, es, 5:5:55, 0, es), 5:5:55, 'AbsTol', 1e-9);
[e, dl] = shadow_equiv_roll(0, 15, 16.1, 0, es);
verifyEqual(tc, [dl e], [1.1 4.0], 'AbsTol', 1e-9);
verifyEqual(tc, shadow_frame(0, 15, 16.1, 16.1, 0, 3, [16.1 25], 30, 20, 8, es), 0);
smin = @(lo) asind(cosd(es) * 0.5 * sind(lo) - sind(es) * cosd(lo));    % Sun et al.'s, the GCS 30 deg off the nose
verifyEqual(tc, smin([16.1 32.0]), [5.16 12.81], 'AbsTol', 0.01);
sh = @(x) (3 * x - x .^ 3) / 2;
[Bt, E, R] = ndgrid(-90:5:60, [0 1 3 8 16 23], 16:2:57);
for i = 1:numel(Bt)
    for band = {[16.1 25.0], [32.0 57.9]}
        [k, g] = shadow_frame(Bt(i), E(i), R(i), R(i), 0, 3, band{1}, 30, 20, 8, es);
        if k == 0, continue; end
        [ep, dp] = shadow_equiv_roll(0, E(i), R(i), 0, es); [~, dl] = shadow_equiv_roll(Bt(i), E(i), R(i), 0, es);
        verifyTrue(tc, ep >= band{1}(1) && ep <= band{1}(2));
        verifyEqual(tc, g, sh(min(1, max(0, dl / dp))), 'AbsTol', 1e-9);
        if g > 0.99, verifyGreaterThan(tc, dl, max(0.9 * (band{1}(1) - es), smin(band{1}(1)))); end
    end
end
q = p; q.active_threat = 'airframe_shadowing'; q.roll_in_frames = q.pl_onset_det; q.cap_frames = 20;
for L = [6 25]
    q.shadow_db = L; s = shadow_spec(q); n = 0; k = 0;
    while n < 30
        k = k + 1;
        v = 30 + 130 * mod(k * 0.618, 1); eb = q.EbNo_dB(1 + mod(k, numel(q.EbNo_dB)));
        d = flight_draws(3100000 + k, v / 3.6 * q.carrier_freq / q.c_light, q, struct('ebno', eb));
        if ~any(d.hidden > 0), continue; end
        n = n + 1;
        att = [d.gcs_aoa d.el_deg d.roll d.pitch d.wobble d.roll_in];
        [ep, dp] = shadow_equiv_roll(0, d.el_deg, d.bank, d.pitch, es);
        verifyTrue(tc, ep >= s(2) - 1e-9 && ep <= s(3) + 1e-9);
        for j = find(d.hidden > 0)
            [bt, rt] = turn_attitude(att, d.yaw, (j - 1) * q.cycle_s);
            [~, dl] = shadow_equiv_roll(bt, d.el_deg, abs(rt), d.pitch, es);
            [~, ds] = shadow_equiv_roll(bt, d.el_deg, d.roll_in(3), d.pitch, es); ds = max(ds, 0) * (d.roll_in(3) > 0);
            verifyEqual(tc, d.shadow_g(j), sh(min(1, max(0, (dl - ds) / (dp - ds)))), 'AbsTol', 1e-9);
            if d.shadow_g(j) > 0.99, verifyGreaterThan(tc, dl, smin(s(2))); end
        end
    end
end
end

function test_los_phase_turns(tc)
% An interferer's line of sight turns with the heading, and its Doppler shift with it,
% fd sin(aoa + heading change) at every instant; its phase is that frequency's integral
% (los_phase.m): in closed form for a constant or steadily turning heading, over a roll-in
% within 2e-3 rad of a fine integral; the threat block (the frame's start, then the
% frame's frequency) and the idle time (idle_rssi.m, emitter_idle.m) take the same law.
fd = 358; t = [0 0.05 0.3 0.9 1.25 1.5 2.4]'; tt = (0:1e-6:2.4)';
for att = {[12 3 -30 0 0 0 0 0.1 25 0], [12 3 -30 0 0 0 0 -0.5 25 0], [12 3 30 0 0 0 0 -5 25 0]}
    a = att{1}; y = 15 * sign(a(3));
    [~, ~, dg] = turn_attitude(a, y, tt);
    ref = 2*pi*fd * interp1(tt, cumtrapz(tt, sind(40 + dg)), t);
    verifyEqual(tc, los_phase(40, a, y, fd, t), ref, 'AbsTol', 2e-3);
end
verifyEqual(tc, los_phase(40, [0 0 20 0 0 0 0], 10, fd, t), 2*pi*fd * (cosd(40) - cosd(40 + 10 * t)) / deg2rad(10), 'AbsTol', 1e-9);
verifyEqual(tc, los_phase(40, zeros(1, 10), 0, fd, t), 2*pi*fd * sind(40) * t, 'AbsTol', 1e-9);
a = [0 0 30 0 0 0 0 0.2 25 0]; h = 1e-5;
for t0 = [0.1 0.6 1.0 2.2]
    [~, ~, dp] = turn_attitude(a, 20, t0);
    f = (los_phase(40, a, 20, fd, t0 + h) - los_phase(40, a, 20, fd, t0 - h)) / (2 * h) / (2*pi);
    verifyEqual(tc, f, fd * sind(40 + dp), 'AbsTol', 0.5);
end
verifyNotEmpty(tc, strfind(fileread(which('build_threat_model')), ...
    'los_phase(aoa(%d), att, yaw, fd, t(1)) + 2*pi*fd*sind(aoa(%d) + dp) * (t - t(1))'));
verifyNotEmpty(tc, strfind(fileread(which('idle_rssi')), 'los_phase(ctx.aoa(c), att, ctx.yaw, ctx.fd, tq)'));
verifyNotEmpty(tc, strfind(fileread(which('emitter_idle')), 'los_phase(be, ctx.att, ctx.yaw, ctx.fd * cosd(ee(u)), tq)'));
end

function test_shadow_k_onset(tc)
% The hidden antenna keeps its own K-factor until its loss counts as an event (5 dB, Sun et
% al., Sec. III) and has the shadow's (-16 dB, Fig. 12) from then on, so the frames labelled
% clean before the onset carry no shadowed K: our signal's weakest antenna (sig_weak_db.m)
% and the channel's code alike.
p = base_params(); q = p; q.active_threat = 'airframe_shadowing'; q.shadow_db = 20;
s = shadow_spec(q); bdy = ones(1, q.n_rx); att = [0 2 30 0 0 0 0 0 25 0]; yaw = 20; kd = 15;
pre = 0; post = 0;
for t1 = 0.1:0.05:1.3
    [b, r] = turn_attitude(att, yaw, t1); [~, r0] = turn_attitude(att, yaw, 0);
    [hs, gs] = shadow_frame(b, 2, r, [30 0], 0, q.n_rx, s(2:3), s(4), 20, s(5), s(8));
    gl2 = 10^((uav_attitude_db(2, b, r, 0, -30) - uav_attitude_db(2, 0, r0, 0, -30)) / 10);
    m = @(k) 10^(k / 10) / (10^(k / 10) + 1) * gl2 + 1 / (10^(k / 10) + 1);
    x = m(kd) * ones(1, q.n_rx);
    if hs > 0
        kh = kd; if s(1) * gs >= s(7), kh = s(6); post = post + 1; else, pre = pre + 1; end
        x(hs) = 10^(-s(1) * gs / 10) * m(kh);
    end
    verifyEqual(tc, sig_weak_db(att, yaw, t1, [t1; t1], kd, bdy, s, 20, -30), 10*log10(min(x)), 'AbsTol', 1e-9);
end
verifyGreaterThan(tc, pre, 0); verifyGreaterThan(tc, post, 0);
q.quiet_build = true; mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(q)');
ch = sfroot().find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/Channel']);
src = ch.Script;
verifyNotEmpty(tc, strfind(src, sprintf('if %.6f * gs >= %.6f', 20, 5)));
verifyNotEmpty(tc, strfind(src, sprintf('Kk = %.10g;', 10^(-16 / 10))));
verifyEmpty(tc, strfind(src, 'kdb(1) + gs *'));
close_system(mdl, 0);
end

function test_roll_in_every_class(tc)
% In the detector's sub-runs (p.roll_in_frames) every turning flight rolls into its turn,
% whatever its class, from its own 'roll' stream: the clean link and every threat alike,
% the rate as roll_rate.m draws it and the start uniform over the times that put some of
% the roll-in inside the run, level flight before it; such a flight hides no antenna and
% its labels stay its threat's. Without p.roll_in_frames (the pools) a flight that the data
% place no event in holds its bank; the dataset's base params ask for the roll-in, so its
% clean class rolls in as every threat does.
p = base_params(); p.roll_in_frames = p.pl_onset_det; p.cap_frames = 20; cyc = p.cycle_s;
for thr = {'none', 'jamming', 'antenna_fault', 'path_loss'}
    q = p; q.active_threat = thr{1}; n = 0;
    for s = 1:120
        fd = (30 + 130 * mod(s * 0.618, 1)) / 3.6 * q.carrier_freq / q.c_light;
        d = flight_draws(3200000 + s, fd, q, struct('ebno', 9));
        if d.bank == 0, verifyEqual(tc, d.roll_in, [0 0 0]); continue; end
        r = rand(seed_stream(3200000 + s, 'roll'), 1, 3);
        w = roll_rate(r(1), d.bank, q); T = d.bank / w;
        verifyEqual(tc, d.roll_in, [-T + r(3) * (T + 19 * cyc), w, 0], 'AbsTol', 1e-12);
        verifyTrue(tc, all(d.hidden == 0) && isnan(d.onset_frame));
        att = [d.gcs_aoa d.el_deg d.roll d.pitch d.wobble d.roll_in];
        tf = (0:19) * cyc;
        [b0, ro] = turn_attitude(att, d.yaw, tf);
        verifyEqual(tc, b0(1), d.gcs_aoa);
        verifyEqual(tc, ro(tf <= d.roll_in(1)), zeros(1, nnz(tf <= d.roll_in(1))));
        k = tf >= d.roll_in(1) + T;
        verifyEqual(tc, ro(k), d.roll * ones(1, nnz(k)), 'AbsTol', 1e-9);
        n = n + 1;
    end
    verifyGreaterThan(tc, n, 100);
end
q = p; q.roll_in_frames = []; q.active_threat = 'none';
verifyEqual(tc, flight_draws(3200001, 300, q, struct('ebno', 9)).roll_in, [0 0 0]);
src = fileread(which('run_dataset_sweep'));
i0 = strfind(src, 'p0.roll_in_frames = p0.pl_onset_det;');
verifyNotEmpty(tc, i0);
verifyLessThan(tc, i0(1), strfind(src, 'p = p0; p.active_threat = ''none''; p.seed = [];'));
verifyLessThan(tc, i0(1), strfind(src, 'p = p0; p.active_threat = cfg.name;'));
verifyEmpty(tc, regexp(src, 'roll_in_frames = \[\]', 'once'));
q = p; q.active_threat = 'none'; q.quiet_build = true; mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(q)');
d = link_seed(mdl, 3200002, 300, struct('ebno', 9, 'alt_m', NaN, 'k_sig_db', NaN));
a = str2num(get_param([mdl '/Att'], 'Value')); %#ok<ST2NM>
verifyEqual(tc, a(8:10), d.roll_in, 'AbsTol', 1e-8);
verifyGreaterThan(tc, d.roll_in(2), 0);
close_system(mdl, 0);
end

function test_shadow_reach(tc)
% A level is flown only where the airframe can bank deep enough: with the GCS at elevation el
% the smallest bank whose equivalent roll reaches the band is lo - 2.9 + el, and a turn at
% speed v banks at most atand(min(tan(57.9 deg), w_max v / g)) (heading_rate.m), so below
% g tan(lo - 2.9 + el) / w_max (shadow_speed_floor.m at el) no flight hides an antenna, and
% none at all where that bank exceeds 57.9 deg; just above it the largest bank reaches the
% band. Seeded flights over the whole envelope at the shortest distance agree: none below
% the floor at their altitude hides one, some above it do (shadow_alt_floor.m,
% hides_antenna.m).
p = base_params(); g = 9.81; wm = deg2rad(p.yaw_rate_max); es = p.shadow_el_deg;
verifyEqual(tc, shadow_speed_floor([16.1 57.9; 32.0 57.9], p), shadow_speed_floor([16.1 57.9; 32.0 57.9], p, 0));
el = [0 2 5 10 20 23]; bd = shadow_roll_band(25, p);
vf = shadow_speed_floor(bd, p, el);
verifyEqual(tc, vf, 3.6 * max(p.shadow_v_min, g * tand(bd(1) - es + el) / wm), 'RelTol', 1e-12);
verifyEqual(tc, shadow_speed_floor(bd, p, 29), Inf);                    % 58.1 deg of bank
verifyEqual(tc, shadow_speed_floor(bd, p, 28.5), 3.6 * g * tand(bd(1) - es + 28.5) / wm, 'RelTol', 1e-12);
bmax = @(v) atand(min(tand(p.roll_max_deg), wm * v / 3.6 / g));
for i = 1:numel(el)
    verifyGreaterThanOrEqual(tc, shadow_equiv_roll(0, el(i), bmax(vf(i) + 1e-6), 0, es), bd(1) - 1e-6);
    verifyLessThan(tc, shadow_equiv_roll(0, el(i), bmax(vf(i) - 1e-3), 0, es), bd(1));
end
q = p; q.shadow_db = 25; eb = q.EbNo_dB(end); d = 1000 * link_distance_km(eb, q);
verifyEqual(tc, shadow_alt_floor([15 120; 60 90], eb, q), ...
    reshape(shadow_speed_floor(bd, q, asind(([15 60 120 90] - q.gcs_h_m) / d)), 2, 2), 'RelTol', 1e-12);
verifyEqual(tc, shadow_alt_floor(NaN, eb, q), shadow_speed_floor(bd, q));   % no altitude: the GCS on the horizon
verifyEqual(tc, shadow_alt_floor(50, NaN, q), shadow_speed_floor(bd, q));
q.active_threat = 'airframe_shadowing'; q.cap_frames = 20;
for L = [6 25]
    q.shadow_db = L; nb = 0; na = 0;
    for k = 1:500
        v = 161 * mod(k * 0.618, 1); a = q.alt_range_m(1) + diff(q.alt_range_m) * mod(k * 0.382 + 0.1, 1);
        h = hides_antenna(3300000 + k, v, q, struct('ebno', eb, 'alt_m', a, 'k_sig_db', NaN));
        r = v >= shadow_alt_floor(a, eb, q);
        verifyFalse(tc, h && ~r);
        nb = nb + ~r; na = na + h;
    end
    verifyGreaterThan(tc, nb, 50); verifyGreaterThan(tc, na, 5);
end
end

function test_level_calibration(tc)
% Each antenna's receiver reports its level within the RSSI accuracy of an AD9361-class
% radio (+-2 dB, drawn per flight from its own stream): RSSI and interference over thermal
% move by the reference antenna's error, the antenna gains by each one's; SINR and the
% decoded bits do not.
p = base_params();
d = flight_draws(17, 160, p);
verifyEqual(tc, d.cal_db, 2 * (2 * rand(seed_stream(17, 'cal'), 1, p.n_rx) - 1), 'AbsTol', 1e-12);
C = cell2mat(arrayfun(@(s) getfield(flight_draws(s, 160, p), 'cal_db'), (1:2000)', 'UniformOutput', false));
verifyTrue(tc, all(abs(C(:)) <= 2)); verifyGreaterThan(tc, max(abs(C(:))), 1.95);
p.quiet_build = true; p.active_threat = 'jamming'; p.jsr_db = 10; p.tdl = false;
mdl = 'UAV_GCS_Threat_Link';
F = cell(1, 2);
for k = 1:2
    p.cal_random = k == 2;
    evalc('build_threat_model(p)');
    set_link_snr(mdl, 12 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
    d = link_seed(mdl, 17, 160);
    F{k} = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(6 * p.frame_duration)), p, 20);
    close_system(mdl, 0);
end
verifyEqual(tc, F{1}.cal_db, zeros(1, p.n_rx));
verifyEqual(tc, F{2}.cal_db, d.cal_db, 'AbsTol', 1e-9);
verifyEqual(tc, F{2}.ref, F{1}.ref);
verifyEqual(tc, F{2}.sinr, F{1}.sinr, 'AbsTol', 1e-6);
verifyEqual(tc, F{2}.ber, F{1}.ber);
verifyEqual(tc, F{2}.rssi - F{1}.rssi, d.cal_db(F{1}.ref), 'AbsTol', 1e-6);
verifyEqual(tc, F{2}.iot - F{1}.iot, d.cal_db(F{1}.ref), 'AbsTol', 1e-6);
verifyEqual(tc, F{2}.gain_ant - F{1}.gain_ant, repmat(d.cal_db(:), 1, F{1}.nf), 'AbsTol', 1e-6);
verifyEqual(tc, F{2}.q_react, F{1}.q_react, 'AbsTol', 1e-6);
end

function test_los_doppler(tc)
% Our LoS carries the Doppler of the GCS direction, fd cos(elevation) sin(direction): the
% receiver finds +fd with the GCS ahead, -fd behind, none abeam (no oscillator offset).
p = base_params(); p.quiet_build = true; p.active_threat = 'none'; p.int_aoa_random = false; p.yaw_random = false;
p.corr_random = false; p.gcs_tracked = false; p.k_random = false; p.rician_k = 40; p.gcs_aoa_random = false;
p.body_random = false; p.wobble_random = false; p.tdl = false; p.cfo_ppm = 0;
mdl = 'UAV_GCS_Threat_Link'; fd = p.v_max * p.carrier_freq / p.c_light;
for b = [90 -90 0]
    p.gcs_aoa_deg = b;
    evalc('build_threat_model(p)');
    set_link_snr(mdl, 20 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
    link_seed(mdl, 13, fd);
    F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(5 * p.frame_duration)), p, 20);
    verifyEqual(tc, median(F.cfo_hz), fd * sind(b), 'AbsTol', 40);
    close_system(mdl, 0);
end
end

function test_citations_in_library(tc)
% The code cites only sources in the library: no Cui et al. (path loss, altitude), no
% Boeing patent (tracker fallback), no Fedde & Carter or Ginart (connector faults), no
% ministry rule (the e.i.r.p. cap is ETSI EN 300 328's); Heath's 5 dB is the imbalance
% indicator of Table 2.
f = dir(fullfile(tc.TestData.root, 'code', '**', '*.m'));
f = f(~contains({f.folder}, [filesep 'legacy']) & ~strcmp({f.name}, 'test_core.m'));
bad = {};
for i = 1:numel(f)
    t = fileread(fullfile(f(i).folder, f(i).name));
    if ~isempty(regexp(t, 'Cui et al|Boeing|8,503,941|Fedde|Ginart|Ministry of Comm|6,147,985', 'once'))
        bad{end+1} = f(i).name; %#ok<AGROW>
    end
end
verifyEmpty(tc, bad, strjoin(bad, ', '));
t = fileread(which('init_params'));
verifyNotEmpty(tc, regexp(t, 'severely degraded antenna connection', 'once'));
verifyNotEmpty(tc, regexp(t, 'Simunek et al\. 2011', 'once'));
end

%% ---------- unknown-threat statistic, KPI 1 Eb/N0, masking, timing load ----------
function test_ood_window_monitor(tc)
% The unknown-threat statistic of the offline readings (ood_window.m) is the decision
% cycle's: the mean over the last unk_win cycles of the run, partial at its start, the same
% flag cycle by cycle as policy_monitor.m; frames given out of order are put in time order,
% and every run has its own window.
A = policy_actions();
PP = struct('actions', {A}, 'classes', {{'none', 'jamming'}}, 'sps', 4, 'bps', 2, 'maha_thr', -1, 'unk_win', 5);
rng(11); mh = -1 + 0.8 * randn(1, 30);
o = struct('probs', [0.9 0.1], 'unknown', false, 'feat', zeros(1, numel(link_features('names'))));
o.feat(feature_index('log_ber')) = -6;
mem = policy_monitor('init', 1, numel(A)); cfg = find(strcmp(A, 'no_action'));
flag = false(1, 30);
for k = 1:30
    x = o; x.maha = mh(k); x.unknown = mh(k) < PP.maha_thr;
    mem = policy_monitor('update', mem, x, PP, cfg);
    flag(k) = mem.unk_now(1);
end
w = ood_window(mh, ones(1, 30), 1:30, 5);
verifyEqual(tc, flag, w' < PP.maha_thr);
verifyEqual(tc, w(1:3)', cumsum(mh(1:3)) ./ (1:3), 'AbsTol', 1e-12);   % partial windows at the start
p = randperm(30);
verifyEqual(tc, ood_window(mh(p), ones(1, 30), p, 5), w(p), 'AbsTol', 1e-12);
verifyEqual(tc, ood_window(mh, [ones(1, 15), 2 * ones(1, 15)], 1:30, 5), ...
    [ood_window(mh(1:15), ones(1, 15), [], 5); ood_window(mh(16:30), ones(1, 15), [], 5)], 'AbsTol', 1e-12);
verifyEqual(tc, ood_window(mh, ones(1, 30), [], 1), mh(:));
end

function test_ood_fold_metrics(tc)
% Every score read as the decision cycle reads it: a window over the whole sub-run in time
% order, labelled by its newest frame, so an isolated held-out frame shares its window with
% known neighbours (the held-out frames are not joined); the selection reads the
% validation frames only, and FPR95 takes its threshold from the known validation windows.
s = ones(1, 12); s([4 9]) = -2;                               % two isolated held-out frames
T = struct('run', ones(12, 1), 'pos', (1:12)', 'kn', true(12, 1), 'un', false(12, 1));
T.un([4 9]) = true; T.kn = ~T.un;
Q = ood_fold_metrics(struct('a', s), T, struct('a', s), T, {'a'}, [1 4], 0.95);
verifyEqual(tc, Q.test(1, 1), 1);                             % per frame: separated
verifyEqual(tc, Q.test(1, 2), 0.7, 'AbsTol', 1e-12);          % 4 cycles: 4 known windows above, 6 tied at 0.25
p = [12 1 5 3 9 2 4 11 6 8 7 10];                             % the same frames out of time order
T2 = struct('run', ones(12, 1), 'pos', p', 'kn', ~ismember(p', [4 9]), 'un', ismember(p', [4 9]));
Q2 = ood_fold_metrics(struct('a', s(p)), T2, struct('a', s(p)), T2, {'a'}, [1 4], 0.95);
verifyEqual(tc, Q2.test, Q.test, 'AbsTol', 1e-12);
% 'a' separates on validation, 'b' on the test frames: the selection takes 'a'
k10 = (1:10)';
V = struct('run', [ones(10, 1); 2 * ones(10, 1)], 'pos', [k10; k10], 'kn', [true(10, 1); false(10, 1)], ...
    'un', [false(10, 1); true(10, 1)]);
Sv = struct('a', [linspace(1, 2, 10), zeros(1, 10)], 'b', [linspace(1, 2, 10), 1.5 * ones(1, 10)]);
St = struct('a', [linspace(1, 2, 10), 1.5 * ones(1, 10)], 'b', [linspace(1, 2, 10), zeros(1, 10)]);
Q = ood_fold_metrics(Sv, V, St, V, {'a', 'b'}, 1, 0.95);
verifyEqual(tc, Q.val(:)', [1 0.5], 'AbsTol', 1e-12);
verifyEqual(tc, Q.test(:)', [0.5 1], 'AbsTol', 1e-12);
verifyEqual(tc, ood_select(Q.val', true(1, 2)), 1);
verifyEqual(tc, Q.thr(:)', [1 1], 'AbsTol', 1e-12);           % the lowest of 10 known validation windows
verifyEqual(tc, Q.fpr(:)', [1 0]);
end

function test_ood_loto_split(tc)
% The frames of one held-out threat: no frame of its sub-runs trains, stops the training,
% fits a model or is read as known, the frames the frame rule calls clean included; the
% known windows of the selection come from the other half of the validation sub-runs, the
% halves a checkerboard over level and Eb/N0 within each class; the labels are the frame
% rule's; the reading is the second test set, z-scored with the known training frames'
% statistics.
rng(12);
cls = {'none', 'jamming', 'spoofing'};
i = floor((0:59)' / 5); c = mod(i, 3) + 1;               % 12 sub-runs of 5 frames: none, jamming, spoofing, ...
yf = c; yf(c == 2 & mod((0:59)', 5) == 0) = 1;           % a jamming sub-run's first frame holds no jamming
lvr = 1 + mod(floor(i / 3), 2); lvr(c == 1) = NaN;      % levels 1 2 1 2 per threat, Eb/N0 0 dB then 3 dB
mk = @(r0) struct('X', rand(4, 4, 1, 60), 'feats', randn(60, 2), 'Y', categorical(cls(c), cls), ...
    'Y_frame', categorical(cls(yf), cls), 'run', r0 + i, 'pos', mod((0:59)', 5) + 1, 'ebno', 3 * floor(i / 6), ...
    'level', lvr);
sp = struct('train', mk(1), 'val', mk(101), 'norm', struct('feat_mean', [1 -1], 'feat_std', [2 3]), ...
    'classes', {cls'});
fresh = mk(201); fresh.X = fresh.X(:, :, :, 1:30); fresh.feats = fresh.feats(1:30, :);
fresh.Y = fresh.Y(1:30); fresh.Y_frame = fresh.Y_frame(1:30); fresh.run = fresh.run(1:30); fresh.pos = fresh.pos(1:30);
[tr, vfit, va, vk, te] = ood_loto_split(sp, fresh, 'jamming');
jr = 1 + [1 4 7 10];                                     % the jamming sub-runs of the training split
verifyEqual(tc, categories(tr.Y)', {'none', 'spoofing'});
verifyEqual(tc, numel(tr.Y), 40);                                % without the jamming sub-runs' clean first frames
verifyFalse(tc, any(ismember(tr.run, jr)));
verifyEqual(tc, mean(tr.feats, 1), [0 0], 'AbsTol', 1e-12);
verifyEqual(tc, std(tr.feats, 0, 1), [1 1], 'AbsTol', 1e-12);
verifyFalse(tc, any(vfit.Y == 'jamming'));
verifyFalse(tc, any(ismember(vfit.run, 100 + jr)));
verifyEqual(tc, va.sel, ismember(sp.val.run, 101 + [0 1 2 9 10 11]));   % per class: (level 1, 0 dB), (2, 3 dB)
verifyEqual(tc, va.own, ismember(sp.val.run, 100 + jr));
verifyEqual(tc, te.own, ismember(fresh.run, 200 + jr));
verifyTrue(tc, all(ismember(vfit.run, 101 + [3 5 6 8])));
verifyEqual(tc, numel(vfit.Y), 20);
verifyEqual(tc, numel(va.Y), 60);
verifyEqual(tc, sum(va.Y ~= 'jamming' & va.own), 4);             % clean by the frame rule, not known
verifyEqual(tc, numel(vfit.Y) + sum(va.sel & va.Y ~= 'jamming' & ~va.own), 40);
verifyTrue(tc, all(vk.Y == 'jamming')); verifyEqual(tc, numel(vk.Y), 16);
verifyEqual(tc, te.X, fresh.X);
verifyEqual(tc, te.Y, fresh.Y_frame(:));
src = fileread(which('eval_ood_detection'));
verifyNotEmpty(tc, strfind(src, '''kn'', ismember(yv, known) & va.sel & ~va.own'));
verifyNotEmpty(tc, strfind(src, '''kn'', ismember(yt, known) & ~te.own'));
raw = @(f) f .* sp.norm.feat_std + sp.norm.feat_mean;
k = ~ismember(sp.train.run, jr);
mu = mean(raw(sp.train.feats(k, :)), 1); sd = std(raw(sp.train.feats(k, :)), 0, 1);
verifyEqual(tc, te.feats, (raw(fresh.feats) - mu) ./ sd, 'AbsTol', 1e-12);
verifyEqual(tc, te.pos, fresh.pos);
end

function test_ood_thresholds_window(tc)
% The unknown-threat threshold is the 5% quantile of the statistic the decision cycle
% compares with it: the production score's mean over the last ood.win cycles of each
% validation sub-run; a detector with another window recomputes it.
d = fullfile(tc.TestData.tmp, 'oodthr'); mkdir(fullfile(d, 'data'));
c0 = cd(d); back = onCleanup(@() cd(c0));
[net, ood, X, F] = tiny_detector();
ood.win = 4;
run = repelem((1:10)', 8); pos = repmat((1:8)', 10, 1);
splits.val = struct('X', X, 'feats', F', 'run', run, 'pos', pos);
save('data/splits.mat', 'splits');
save('data/trained_detector.mat', 'net', 'ood');
T = ood_thresholds(0.95);
mh = ood_scores(net, ood, X, F);
mw = sort(ood_window(mh, run, pos, 4));
mf = sort(mh(:));
q = max(1, ceil((1 - 0.95) * 80));                            % the quantile's index, as ood_thresholds
verifyEqual(tc, T.maha, mw(q), 'AbsTol', 1e-12);
verifyEqual(tc, T.maha_val, mw, 'AbsTol', 1e-12);
verifyEqual(tc, T.maha_frame, mf(q), 'AbsTol', 1e-12);
verifyEqual(tc, [T.win, T.n_val], [4 80]);
verifyNotEqual(tc, T.maha, T.maha_frame);
ood.win = 1; save('data/trained_detector.mat', 'net', 'ood');
T1 = ood_thresholds(0.95);
verifyEqual(tc, [T1.win, T1.maha], [1 mf(q)], 'AbsTol', 1e-12);
end

function test_kpi_ebno(tc)
% KPI 1 reads a frame at the Eb/N0 our signal is received with: a clean frame after a
% path-loss step's window at the configured Eb/N0 less the step, in the bin of the grid
% point at or below it, beyond range below the grid; a frame judged as path_loss at the
% link's Eb/N0 when the step began; the dataset's ebno_rx when present.
cls = {'none', 'path_loss', 'jamming'};
y = {'none', 'none', 'path_loss', 'path_loss', 'path_loss', 'none', 'none', 'none'};
P = struct('ebno', [12 * ones(8, 1); 3 * ones(8, 1); 0; 6; 9; 15], ...
    'Y', categorical([y, y, {'none', 'jamming', 'none', 'none'}], cls)', ...
    'run', [ones(8, 1); 2 * ones(8, 1); (3:6)'], 'pos', [(1:8)'; (1:8)'; ones(4, 1)], ...
    'level', [10 * ones(8, 1); 13 * ones(8, 1); NaN; 30; NaN; NaN]);
[bin, eb, rx, brx] = kpi_ebno(P, P.Y, cls);
verifyEqual(tc, rx(1:8)', [12 12 2 2 2 2 2 2]);
verifyEqual(tc, eb(1:8)', [12 12 12 12 12 2 2 2]);
verifyEqual(tc, bin(1:8)', [12 12 12 12 12 0 0 0]);
verifyEqual(tc, brx(3:5)', [0 0 0]);
verifyEqual(tc, bin(9:13)', [3 3 3 3 3]);
verifyTrue(tc, all(isnan(bin(14:16))));                       % received at -10 dB: below the grid
verifyEqual(tc, bin(17:20)', [0 6 9 15]);                     % no step: the configured Eb/N0
t = P.Y; t(6) = 'path_loss';                                  % a fused target: the onset in its window
b2 = kpi_ebno(P, double(t), cls);
verifyEqual(tc, b2(6), 12);
P.ebno_rx = rx; P.ebno_rx(6:8) = 9 - 1e-12;                   % the dataset's value, a rounding below 9 dB
b3 = kpi_ebno(P, P.Y, cls);
verifyEqual(tc, b3(6:8)', [9 9 9]);
end

function test_balanced_macro_f1(tc)
% The prevalence-normalized reading: with ten times more clean frames, 5% of them read as
% the threat lower its plain precision, not its precision at equal priors; with equal
% class counts both readings agree; a class absent among the true labels is out of the mean.
cls = {'none', 'jamming'};
yt = categorical([repmat({'none'}, 1, 1000), repmat({'jamming'}, 1, 100)], cls);
yp = yt; yp(1:50) = 'jamming';
[~, f1] = balanced_macro_f1(yt, yp, cls);
pb = 1 / 1.05;                                                % R: none row [0.95 0.05], jamming row [0 1]
verifyEqual(tc, f1(2), 2 * pb / (pb + 1), 'AbsTol', 1e-12);
pp = 100 / 150;
verifyLessThan(tc, 2 * pp / (pp + 1), f1(2));
yt2 = categorical([repmat({'none'}, 1, 100), repmat({'jamming'}, 1, 100)], cls);
yp2 = yt2; yp2(1:5) = 'jamming'; yp2(150) = 'none';
cm = confusionmat(yt2, yp2, 'Order', cls); pr = diag(cm) ./ sum(cm, 1)'; rc = diag(cm) ./ sum(cm, 2);
verifyEqual(tc, balanced_macro_f1(yt2, yp2, cls), mean(2 * pr .* rc ./ (pr + rc)), 'AbsTol', 1e-12);
verifyEqual(tc, balanced_macro_f1(categorical({'none'}, cls), categorical({'jamming'}, cls), cls), 0);
end

function test_spec_mask_fill(tc)
% Masks fill with the image's thermal-noise level, the mean of a noise-only image
% (spec_image('noise'), -2.51 dB over the floor), not with 0 (25 dB below it).
rng(8); nv = 0.5;
iq = sqrt(nv / 2) * complex(randn(6000, 1), randn(6000, 1));
v = spec_image('noise');
verifyEqual(tc, v, (25 - 10 * 0.5772156649 / log(10)) / 80, 'AbsTol', 1e-9);
verifyEqual(tc, mean(spec_image(iq, 1, nv), 'all'), v, 'AbsTol', 0.01);
X = rand(128, 128, 1, 40, 'single') + 0.1;
Xm = spec_mask(X);
ch = Xm ~= X;
verifyTrue(tc, any(ch(:)));
verifyEqual(tc, unique(Xm(ch)), single(v));
verifyFalse(tc, any(Xm(:) == 0));
end

function test_ood_latency_load(tc)
% The detector's cost per candidate is timed with the machine's load logged before and
% after (machine_load.m); this MATLAB counts among the MATLAB processes.
[net, M, X, F] = tiny_detector();
L = ood_latency(net, M, X, F, 5);
verifyEqual(tc, fieldnames(L.load)', {'before', 'after'});
for f = {'before', 'after'}
    q = L.load.(f{1});
    verifyTrue(tc, isnan(q.n_matlab) || q.n_matlab >= 1);
    verifyTrue(tc, isnan(q.cpu_pct) || (q.cpu_pct >= 0 && q.cpu_pct <= 100));
    verifyGreaterThanOrEqual(tc, q.n_cpu, 1);
end
if ispc, verifyGreaterThanOrEqual(tc, L.load.before.n_matlab, 1); end
end

function test_reading_sets_and_labels(tc)
% The unknown-threat stage reads the second test set and never the dataset's test split,
% and selects on validation; the unseen-severity reading counts the windowed statistic;
% the architecture comparison reads the second test set when it exists; the image scale
% is stated as it is.
src = fileread(which('eval_ood_detection'));
verifyEqual(tc, numel(regexp(src, 'sp\.test')), 1);
verifyNotEmpty(tc, strfind(src, 'sp.test = [];'));
verifyNotEmpty(tc, strfind(src, 'data/splits_fresh.mat'));
verifyNotEmpty(tc, strfind(src, 'ood_select(MpV'));
verifyNotEmpty(tc, strfind(fileread(which('eval_unseen_severity')), 'sum(sw(on) < Tood.maha)'));
verifyNotEmpty(tc, strfind(fileread(which('compare_architectures')), 'data/splits_fresh.mat'));
verifyNotEmpty(tc, strfind(fileread(which('extract_spectrograms')), '[-25, 55] dB'));
end

function test_third_test_set(tc)
% Stage B3m builds a third test set with the dataset's recipe, the second test set's counts
% per cell and seeds of its own (6 500 000 + run id, test_seed_streams_disjoint; its own speed
% stream), and reads it once, its outputs suffixed _fresh2; the earlier readings keep theirs.
src = fileread(which('run_dataset_sweep'));
verifyNotEmpty(tc, strfind(src, 'SET2       = FRESH && exist(''FRESH_SET'', ''var'') && isequal(FRESH_SET, 2);'));
i0 = strfind(src, 'if SET2'); verifyNumElements(tc, i0, 1);
e = strfind(src(i0:end), 'end'); seg = src(i0:i0 + e(1) + 1);
verifyNotEmpty(tc, strfind(seg, 'SEED0 = 6500000; f_out = ''data/dataset_fresh2.mat'';'));
verifyEmpty(tc, strfind(seg, 'N_SUB'));                               % the second test set's counts and test fold
verifyLessThan(tc, strfind(src, 'N_SUB = 4; SEED0 = 3500000;'), i0);
verifyNumElements(tc, strfind(src, 'rng(2035'), 1);
verifyNotEmpty(tc, strfind(fileread(which('extract_spectrograms')), ...
    'f_in = ''data/dataset_fresh2.mat''; f_out = ''data/spectrograms_fresh2.mat'';'));
rs = fileread(which('run_stage'));
verifyNotEmpty(tc, strfind(rs, '''B3m'', ''build_fresh_test2'''));
verifyNotEmpty(tc, strfind(rs, 'FRESH_TEST = true; FRESH_SET = 2;'));
verifyNotEmpty(tc, strfind(rs, 'DET_TEST = ''fresh2'';'));
ed = fileread(which('eval_detector'));
verifyNotEmpty(tc, strfind(ed, 'if read_fresh2, tag = ''_fresh2''; end'));
verifyNotEmpty(tc, strfind(ed, 'Sf = load(''data/splits_fresh2.mat'');'));
verifyNotEmpty(tc, strfind(fileread(which('measure_all_kpis')), 'F.det = kpi1_file(''eval_detector_metrics'');'));
verifyEqual(tc, kpi1_set(), 'fresh2');
% B1 on the third set: data/spectrograms_fresh2.mat -> data/splits_fresh2.mat, the training
% z-score, the second test set's file untouched
d = fullfile(tc.TestData.tmp, 'fresh2'); mkdir(fullfile(d, 'data'));
c0 = cd(d); back = onCleanup(@() cd(c0));
classes = {'none'; 'jamming'}; norm = struct('feat_mean', [1 2], 'feat_std', [2 4], 'feat_names', {{'a', 'b'}}); %#ok<NASGU>
save('data/splits.mat', 'norm', 'classes');
n = 6;
spec = struct('X', zeros(8, 8, 1, n, 'single'), 'Y', categorical([1 2 1 2 1 2]', 1:2, classes), 'feats', [3 6; 5 10; 1 2; 3 6; 5 10; 1 2], ...
    'feat_names', {{'a', 'b'}}, 'fold', 6 * ones(n, 1), 'ebno', zeros(n, 1), 'speed_kmh', ones(n, 1), 'run', [1 1 2 2 3 3]', ...
    'level', ones(n, 1), 'meta', struct('frames_checked', true)); %#ok<NASGU>
save('data/spectrograms_fresh2.mat', 'spec');
FRESH_TEST = true; FRESH_SET = 2; %#ok<NASGU>
evalc('run(''prepare_data'')');
verifyTrue(tc, isfile('data/splits_fresh2.mat')); verifyFalse(tc, isfile('data/splits_fresh.mat'));
L = load('data/splits_fresh2.mat');
verifyEqual(tc, L.splits.test.feats(1, :), [1 1]);
verifyEqual(tc, L.splits.test.run, [1 1 2 2 3 3]');
end

function test_fourth_test_set(tc)
% Stage B3q builds a fourth test set with the third's recipe and seeds of its own (6 000 000 +
% run id, test_seed_streams_disjoint; its own speed stream), data only; B3r reads it once, and
% only after kpi1_set.m names it; until then every KPI 1 reader stays on the third test set.
src = fileread(which('run_dataset_sweep'));
verifyNotEmpty(tc, strfind(src, 'SET3       = FRESH && exist(''FRESH_SET'', ''var'') && isequal(FRESH_SET, 3);'));
i2 = strfind(src, 'if SET2'); i0 = strfind(src, 'if SET3'); verifyNumElements(tc, i0, 1);
verifyGreaterThan(tc, i0, i2);
e = strfind(src(i0:end), 'end'); seg = src(i0:i0 + e(1) + 1);
verifyNotEmpty(tc, strfind(seg, 'SEED0 = 6000000; f_out = ''data/dataset_fresh3.mat'';'));
verifyNotEmpty(tc, strfind(seg, 'rng(2037, ''twister'');'));
verifyEmpty(tc, strfind(seg, 'N_SUB'));                               % the second and third sets' counts and test fold
tw = cellfun(@(c) str2double(c{1}), regexp(src, 'rng\((\d+), ''twister''\)', 'tokens'));
verifyEqual(tc, sort(tw), [2027 2029 2035 2037]);                      % a speed stream per set
verifyNotEmpty(tc, strfind(fileread(which('extract_spectrograms')), ...
    'f_in = ''data/dataset_fresh3.mat''; f_out = ''data/spectrograms_fresh3.mat'';'));
rs = fileread(which('run_stage'));
verifyNotEmpty(tc, strfind(rs, '''B3q'', ''build_fresh_test3'''));
verifyNotEmpty(tc, strfind(rs, '''B3r'', ''read_fresh_test3'''));
i0 = strfind(rs, 'strcmp(name, ''build_fresh_test3'')'); i1 = strfind(rs, 'strcmp(name, ''read_fresh_test3'')');
verifyNumElements(tc, i0, 1); verifyNumElements(tc, i1, 1);
seg = rs(i0:i1);                                                      % B3q builds, never reads
verifyNotEmpty(tc, strfind(seg, 'FRESH_TEST = true; FRESH_SET = 3;'));
verifyEmpty(tc, strfind(seg, 'eval_detector')); verifyEmpty(tc, strfind(seg, 'DET_TEST'));
verifyNotEmpty(tc, strfind(rs(i1:end), 'DET_TEST = ''fresh3'';'));
% B1 on the fourth set: data/spectrograms_fresh3.mat -> data/splits_fresh3.mat, the training
% z-score, the other test sets' files untouched
d = fullfile(tc.TestData.tmp, 'fresh3'); mkdir(fullfile(d, 'data')); mkdir(fullfile(d, 'results'));
c0 = cd(d); back = onCleanup(@() cd(c0));
classes = {'none'; 'jamming'}; norm = struct('feat_mean', [1 2], 'feat_std', [2 4], 'feat_names', {{'a', 'b'}}); %#ok<NASGU>
save('data/splits.mat', 'norm', 'classes');
n = 6;
spec = struct('X', zeros(8, 8, 1, n, 'single'), 'Y', categorical([1 2 1 2 1 2]', 1:2, classes), 'feats', [3 6; 5 10; 1 2; 3 6; 5 10; 1 2], ...
    'feat_names', {{'a', 'b'}}, 'fold', 6 * ones(n, 1), 'ebno', zeros(n, 1), 'speed_kmh', ones(n, 1), 'run', [1 1 2 2 3 3]', ...
    'level', ones(n, 1), 'meta', struct('frames_checked', true)); %#ok<NASGU>
save('data/spectrograms_fresh3.mat', 'spec');
FRESH_TEST = true; FRESH_SET = 3; %#ok<NASGU>
evalc('run(''prepare_data'')');
verifyTrue(tc, isfile('data/splits_fresh3.mat'));
verifyFalse(tc, isfile('data/splits_fresh2.mat')); verifyFalse(tc, isfile('data/splits_fresh.mat'));
L = load('data/splits_fresh3.mat');
verifyEqual(tc, L.splits.test.feats(1, :), [1 1]);
verifyEqual(tc, L.splits.test.run, [1 1 2 2 3 3]');
% KPI 1 stays on the third test set while kpi1_set.m names it, even with a fourth reading on disk,
% and the fourth set is not read before
x = 1; save('results/eval_detector_metrics_fresh2.mat', 'x'); save('results/eval_detector_metrics_fresh3.mat', 'x');
verifyEqual(tc, kpi1_set(), 'fresh2');
verifyEqual(tc, kpi1_file('eval_detector_metrics'), 'results/eval_detector_metrics_fresh2.mat');
verifyError(tc, @() run_det_test('fresh3'), 'eval_detector:kpi1_set');
% Once kpi1_set.m names the fourth set: KPI 1 is read there (missing shows as missing, no
% fallback), and B3r reads it once
fid = fopen('kpi1_set.m', 'w'); fprintf(fid, 'function s = kpi1_set()\ns = ''fresh3'';\nend\n'); fclose(fid);
rehash; shadow = onCleanup(@() remove_shadow(fullfile(d, 'kpi1_set.m')));
verifyEqual(tc, kpi1_set(), 'fresh3');
verifyEqual(tc, kpi1_file('eval_detector_metrics'), 'results/eval_detector_metrics_fresh3.mat');
verifyEqual(tc, kpi1_file('detector_predictions'), 'results/detector_predictions_fresh3.mat');
verifyError(tc, @() run_det_test('fresh3'), 'eval_detector:fresh3_read');
delete('results/eval_detector_metrics_fresh3.mat'); delete('data/splits_fresh3.mat');
verifyError(tc, @() run_det_test('fresh3'), 'eval_detector:fresh3');
clear shadow
verifyEqual(tc, kpi1_set(), 'fresh2');
end

function run_det_test(DET_TEST) %#ok<INUSD>
% eval_detector with DET_TEST set, as run_stage.m runs it.
evalc('run(''eval_detector'')');
end

function remove_shadow(f)
% Removes a stand-in function file and refreshes the path cache.
if isfile(f), delete(f); end
rehash;
end

function [net, M, X, F] = tiny_detector()
% A small network with the detector's named layers and an unknown-threat model on it.
rng(5);
lg = layerGraph([imageInputLayer([8 8 1], 'Normalization', 'none', 'Name', 'img')
    convolution2dLayer(3, 2, 'Name', 'conv'); reluLayer('Name', 'relu1')
    fullyConnectedLayer(4, 'Name', 'fc_img'); concatenationLayer(1, 2, 'Name', 'cat')
    fullyConnectedLayer(4, 'Name', 'fc_m'); reluLayer('Name', 'relu_merge')
    fullyConnectedLayer(2, 'Name', 'fc_out')]);
lg = addLayers(lg, [featureInputLayer(3, 'Name', 'feat'); fullyConnectedLayer(4, 'Name', 'fc_f')]);
lg = connectLayers(lg, 'fc_f', 'cat/in2');
net = dlnetwork(lg);
X = rand(8, 8, 1, 80, 'single'); F = randn(3, 80);
M = struct('layers', {{'relu_merge'}}, 'candidates', {{'last'}}, 'score', 'last', 'mu', {{rand(4, 2)}}, ...
    'P', {{eye(4)}}, 'zs', struct('last', [0 1], 'iforest', [0 1]));
M.forest = iforest(randn(200, 3), 'NumLearners', 20, 'NumObservationsPerLearner', 64);
M.forest_pack = iforest_pack(M.forest);
end

function v = ternary_(c, a, b)
if c, v = a; else, v = b; end
end

%% ---------- known gains, link budget, evaluation identity ----------
function test_config_gain(tc)
% The known Eb/N0 gain of every configuration: the power step of power_control, the
% processing gain of rate_reduce, both together, none for the rest; from the pools when
% they carry it, from the params otherwise.
p = base_params(); A = policy_actions();
g = config_gain_db(A, p);
gr = 10*log10(p.cm_rate_factor);
for a = 1:numel(A)
    e = power_step_db(p) * contains(A{a}, 'power_control') + gr * contains(A{a}, 'rate_reduce');
    verifyEqual(tc, g(a), e, 'AbsTol', 1e-9, A{a});
end
verifyEqual(tc, config_gain_db(struct('actions', {A}, 'cfg_gain_db', 1:numel(A))), 1:numel(A));
verifyEqual(tc, config_gain_db(struct('actions', {A})), g, 'AbsTol', 1e-9);     % params.mat of this folder
verifyEqual(tc, config_gain_db({'power_control', 'rate_reduce'}, struct()), [6 10*log10(4)], 'AbsTol', 1e-9);
end

function test_monitor_known_gain(tc)
% A configuration held on a clean link and released: the frames received with
% power_control or rate_reduce+power_control carry its known gain in the Eb/N0 estimate, and
% the monitor's drop memory takes it out, so the release reads no drop and raises no alarm;
% without the compensation the release reads the gain as a drop. The estimate itself (the
% degradation reference) stays as measured.
A = policy_actions(); na = find(strcmp(A, 'no_action'));
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
p = base_params(); gk = config_gain_db(A, p);
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'confirm', [2 2], ...
    'alarm_mode', 'class_drop', 'drop_db', 3, 'cfg_gain_db', gk);
o = struct('probs', double(strcmp(cls, 'none')), 'unknown', false, 'feat', zeros(1, numel(link_features('names'))));
o.feat(feature_index('log_ber')) = -6;
e0 = 12;                                                        % Eb/N0 of the link without any gain
for c = {'power_control', 'rate_reduce+power_control'}
    ac = find(strcmp(A, c{1}));
    seq = [na * ones(1, 12), ac * ones(1, 12), na * ones(1, 8)];
    for comp = [true false]
        PPc = PP; if ~comp, PPc.cfg_gain_db = zeros(1, numel(A)); end
        m = policy_monitor('init', 1, numel(A)); dr = false(size(seq)); mx = 0;
        for t = 1:numel(seq)
            x = o; x.cfg_link = seq(t);
            x.feat(feature_index('sinr')) = e0 + gk(seq(t)) - 10*log10(4) + 10*log10(2);   % as the frame shows it
            [m, M] = policy_monitor('update', m, x, PPc, seq(t));
            m = policy_monitor('change', m, t < numel(seq) && seq(t + 1) ~= seq(t));
            dr(t) = M.drop_alarm; mx = max(mx, M.drop);
            verifyEqual(tc, M.ebno_est, e0 + gk(seq(t)), 'AbsTol', 1e-9);
        end
        if comp
            verifyFalse(tc, any(dr), c{1}); verifyLessThan(tc, mx, 1e-9);
        else
            verifyTrue(tc, any(dr(25:end)), c{1}); verifyEqual(tc, mx, gk(ac), 'AbsTol', 1e-9);
        end
    end
end
end

function test_rule_budget_match(tc)
% The rule's answer to a loss of our signal is a link-budget match: the smallest
% link-budget gain that covers the drop, the largest when none does, the configuration in
% use when it already covers it; without the budget the class mapping as before. In the
% closed loop a 3 dB step takes power_control and a 5 dB step rate_reduce, once.
p = base_params(); A = policy_actions(); gk = config_gain_db(A, p);
lb = {'power_control', 'rate_reduce', 'rate_reduce+power_control'};
B = @(d, cur) struct('drop_db', d, 'current', cur, 'current_db', gk(strcmp(A, cur)), 'names', {lb}, ...
    'gain_db', arrayfun(@(k) gk(strcmp(A, lb{k})), 1:3));
verifyEqual(tc, rule_based_policy('none', false, 0, -Inf, 3, true, B(3, 'no_action')), 'power_control');
verifyEqual(tc, rule_based_policy('none', true, 0, -Inf, 3, true, B(5, 'no_action')), 'rate_reduce');
verifyEqual(tc, rule_based_policy('unknown', false, 0, -Inf, 3, true, B(8, 'no_action')), 'rate_reduce+power_control');
verifyEqual(tc, rule_based_policy('none', false, 0, -Inf, 3, true, B(30, 'power_control')), 'rate_reduce+power_control');
verifyEqual(tc, rule_based_policy('none', false, 0, -Inf, 3, true, B(8, 'rate_reduce+power_control')), 'rate_reduce+power_control');
verifyEqual(tc, rule_based_policy('path_loss', false, 0, -Inf, 3, true, B(5, 'no_action')), 'rate_reduce');
verifyEqual(tc, rule_based_policy('path_loss', false, 0, -Inf, 3, false, B(-0.5, 'no_action')), 'no_action');
verifyEqual(tc, rule_based_policy('none', false, 0, 10, 3, true, B(5, 'no_action')), 'no_action');    % interference in the slot
verifyEqual(tc, rule_based_policy('jamming', false, 0, -Inf, 3, true, B(5, 'no_action')), 'channel_switch');
verifyEqual(tc, rule_based_policy('path_loss'), 'rate_reduce+power_control');
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'confirm', [2 2], ...
    'alarm_mode', 'class_drop', 'drop_db', 2.5, 'cfg_gain_db', gk);
o = struct('probs', double(strcmp(cls, 'none')), 'unknown', false, 'feat', zeros(1, numel(link_features('names'))));
o.feat(feature_index('log_ber')) = -6;
na = find(strcmp(A, 'no_action'));
for st = [3 5; find(strcmp(A, 'power_control')), find(strcmp(A, 'rate_reduce'))]
    m = []; cfg = na; ch = [];
    for k = 1:40
        x = o; x.cfg_link = cfg;
        x.feat(feature_index('sinr')) = 12 - st(1) * (k > 12) + gk(cfg) - 10*log10(2);
        [a, m] = policy_decide('rule_esc', x, cfg, m, PP, []);
        if a ~= cfg, ch(end+1) = a; end %#ok<AGROW>
        cfg = a;
    end
    verifyEqual(tc, ch, st(2));
end
end

function test_escalation_needs_confirmation(tc)
% Escalation, as every change of the rule and the table, waits for a confirmed alarm: with
% 5-of-5 confirmation three degraded cycles in an applied configuration do not escalate;
% the fifth does.
A = policy_actions();
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
c0 = find(strcmp(A, rule_based_policy('unknown', true, 0)));   % the rule's own answer: it keeps it
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'alarm_mode', 'class');
obs = struct('probs', zeros(1, numel(cls)), 'unknown', true, 'feat', zeros(1, numel(link_features('names'))), 'cfg_link', c0);
obs.feat(feature_index('log_ber')) = -1;
for cf = {[2 2], [5 5]}
    own = struct('monitor', struct('alarm_mode', 'class', 'confirm', cf{1}, 'drop_db', []));
    m = []; esc = 0;
    for k = 1:6
        [a, m, d] = policy_decide('rule_esc', obs, c0, m, PP, [], own);
        if d.escalated, esc = k; break; end
        verifyEqual(tc, a, c0);
    end
    verifyEqual(tc, esc, max(decision_config().esc, cf{1}(1)));
end
end

function test_rate_reduce_chip_level(tc)
% rate_reduce spreads each bit over cm_rate_factor symbols at the same rate and power:
% the simulated field is the despread link, our signal up by the processing gain,
% and the receiver's level measurements, taken before despreading, show the chip-rate
% field: rssi, the detector image and the antennas' channel gains of the same flight
% stay those of no_action, while the despread SINR and the channel estimate's margin over
% its noise (despread pilots) rise by the gain. The counterfeit spoofer, not spread like
% our signal, keeps its power: its field drops by the gain. The chip-rate field is our own
% received component scaled back exactly (Thr_sig): on the same antenna its image is
% no_action's. The reference antenna is the one of the best despread SINR, so a jammed
% receiver that works only with the gain may read another antenna; the levels are
% compared on the frames whose reference antenna is the same.
p = base_params(); p.quiet_build = true; p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false;
p.gcs_tracked = false; p.k_random = false; p.gcs_aoa_random = false; p.body_random = false; p.tdl = false;
mdl = 'UAV_GCS_Threat_Link'; fs = p.symbol_rate * p.sps; nv = thermal_nv(p);
A = {'no_action', 'rate_reduce'}; gr = 10*log10(p.cm_rate_factor);
for thr = {'none', 'jamming'}                                  % the clean link, and a 10 dB jammer
    p.active_threat = thr{1}; p.jsr_db = 10;
    [rs, sn, ga, im, em] = deal(zeros(1, 2)); FF = cell(1, 2);
    for k = 1:2
        [p2, g] = apply_countermeasure(p, thr{1}, A{k});
        evalc('build_threat_model(p2)');
        set_link_snr(mdl, 6 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps) + g, p2);
        link_seed(mdl, 31, 160);
        FF{k} = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(8 * p.frame_duration)), p2, 20);
        F = FF{k}; sn(k) = median(F.sinr); ga(k) = median(F.gain_ant(:)); em(k) = median(F.est_margin);
        close_system(mdl, 0);
    end
    same = FF{1}.ref == FF{2}.ref;                              % the same reference antenna
    verifyGreaterThanOrEqual(tc, sum(same), 4, thr{1});
    for k = 1:2
        rs(k) = median(FF{k}.rssi(same));
        im(k) = 80 * mean(cellfun(@(x) mean(spec_image(x, fs, nv), 'all'), FF{k}.iq(same)));
    end
    verifyEqual(tc, rs(2), rs(1), 'AbsTol', 0.05, thr{1});
    verifyEqual(tc, im(2), im(1), 'AbsTol', 0.05, thr{1});
    if strcmp(thr{1}, 'none')                                  % our channel's estimates (a jammed receiver's track the jammer)
        verifyEqual(tc, ga(2), ga(1), 'AbsTol', 0.5);
        verifyEqual(tc, em(2) - em(1), gr, 'AbsTol', 1);
        verifyEqual(tc, sn(2) - sn(1), gr, 'AbsTol', 1);
    end
end
p.spoof_sir_db = 3;
p3 = apply_countermeasure(p, 'spoofing', 'rate_reduce');
verifyEqual(tc, [p3.spoof_sir_db, p3.proc_gain_db], [3 - gr, gr], 'AbsTol', 1e-9);
p3 = apply_countermeasure(p, 'spoofing', 'power_control');
verifyFalse(tc, isfield(p3, 'proc_gain_db'));
end

function test_drop_step_grid(tc)
% The drop alarm's threshold is selected on validation around each monitor's own (C1d) and
% 2 dB either side, in train_dqn.m and main.m alike; the edge map, DET's drop alarm
% included, runs on the deployed policy's monitor (rule_sel's when the rule is deployed).
verifyNotEmpty(tc, strfind(fileread(which('train_dqn')), 'DROP_STEPS = CD.drop_steps;'));
verifyEqual(tc, decision_config().drop_steps, [-2 0 2]);
verifyNotEmpty(tc, regexp(fileread(which('main')), 'CFG.drop_steps\s*= \[-2 0 2\];', 'once'));
src = fileread(which('edge_map'));
verifyNotEmpty(tc, strfind(src, 'MON = Q; if strcmp(Q.deployed, ''rule_sel''), MON = Q.rule_sel; end'));
verifyNotEmpty(tc, strfind(src, 'PP = decision_settings(PP, MON);'));
end

function test_det_frames_drop(tc)
% DET of a path-loss step, alone or in a combination: with the 'class_drop' monitor
% the class path_loss counts only with the drop, so the path-loss component is detected by
% the drop alarm alone, the other components by their classes; with 'class' the fused
% class counts.
cls = {'none', 'jamming', 'path_loss'};
acts = cellfun(@(x) rule_based_policy(x), cls, 'UniformOutput', false);
nf = numel(link_features('names'));
mk = @(cl, e, n) struct('probs', repmat(double(strcmp(cls, cl)), n, 1), 'run', 101 * ones(n, 1), ...
    'gant', zeros(n, 3), 'feat', [e * ones(n, 1), zeros(n, nf - 1)], 'ber', zeros(n, 1), 'act', ones(n, 1));
Pc = mk('none', 10, 10);
PP = struct('classes', {cls}, 'fuse', [], 'fuse_N', 1, 'sps', 2, 'bps', 2, 'alarm_mode', 'class_drop', 'drop_db', 3);
ok = @(scen) [ismember(acts, cellfun(@(x) rule_based_policy(x), strsplit(scen, '+'), 'UniformOutput', false)); ...
    ismember(acts, cellfun(@(x) rule_based_policy(x), strsplit(scen, '+'), 'UniformOutput', false))];
h = det_frames(mk('path_loss', 10, 10), Pc, 'path_loss', ok('path_loss'), PP);            % the class, no drop
verifyFalse(tc, any(h(:, 1)));
h = det_frames(mk('none', 4, 10), Pc, 'path_loss', ok('path_loss'), PP);                  % a 6 dB drop, read as clean
verifyTrue(tc, all(h(2:end, 1)));
h = det_frames(mk('path_loss', 10, 10), Pc, 'jamming+path_loss', ok('jamming+path_loss'), PP);
verifyFalse(tc, any(h(:, 1)));
h = det_frames(mk('jamming', 10, 10), Pc, 'jamming+path_loss', ok('jamming+path_loss'), PP);
verifyTrue(tc, all(h(:, 1)));
PP.alarm_mode = 'class';
h = det_frames(mk('path_loss', 10, 10), Pc, 'path_loss', ok('path_loss'), PP);
verifyTrue(tc, all(h(:, 1)));
h = det_frames(mk('none', 4, 10), Pc, 'path_loss', ok('path_loss'), PP);
verifyFalse(tc, any(h(:, 1)));
end

function test_clean_split_event_frames(tc)
% A split whose geometries hold rolling-in flights (event frames) replaced by a clean pool
% larger than the split, as C2, C2e, the edge map and the diagnostics replace it
% (clean_split.m): every per-geometry field follows the clean pool's runs (event frames,
% speeds, per-flight draws, the clean cell's geometries, no reference-only geometry), the
% tables build with either reference, and no clean geometry is read as a rolling-in one (no
% event, the episode on the clean pool's own run). Runs replaced without their event frames
% stop link_env at once.
A = policy_actions(); nA = numel(A); fn = link_features('names'); n = 20;
mk = @(runs) struct('ber', zeros(n * numel(runs), 1), 'fer', zeros(n * numel(runs), 1, 'single'), ...
    'run', repelem(runs(:), n), 'probs', repmat([1 0], n * numel(runs), 1), 'maha', ones(n * numel(runs), 1), ...
    'feat', [repelem(runs(:), n), zeros(n * numel(runs), numel(fn) - 1)], 'act', zeros(n * numel(runs), 1));
PP = struct('actions', {A}, 'scen', {{'none', 'airframe_shadowing'}}, 'ebno', 9, 'runs', {{101:103, 201:203}}, ...
    'event_frame', {{nan(1, 3), [NaN 11 11]}}, 'F_SUB', n, 'classes', {{'none', 'airframe_shadowing'}}, ...
    'feat_names', {fn}, 'maha_thr', 0, 'clean', 1e-6, 'clean_fer', 0, 'gp', ones(1, nA), 'bw', ones(1, nA), ...
    'pw', ones(1, nA), 'sps', 4, 'bps', 2, 'speed', {{ones(1, 3), ones(1, 3)}}, 'cell_geo', {{{1:3, 1:3}, {1:3, 2:3}}});
cv = @(m, v) struct('alt_m', v * ones(1, m), 'k_sig', v + ones(1, m), 'yaw', zeros(1, m));
PP.cov = {cv(3, 100), cv(3, 200)}; PP.alt = {100 * ones(1, 3), 200 * ones(1, 3)}; PP.ksig = {101 * ones(1, 3), 201 * ones(1, 3)};
PP.ref_geo = {zeros(1, 0), 1};
PP.pools = cell(2, 1, nA, 2);
for sp = 1:2, for a = 1:nA, PP.pools{1, 1, a, sp} = mk(PP.runs{sp}); PP.pools{2, 1, a, sp} = mk(PP.runs{sp}); end, end
CT = struct('runs', 401:407, 'n_geom', 7, 'speed', 50 * ones(1, 7), 'cov', cv(7, 400));
CT.pools = cell(1, 1, nA);
for a = 1:nA, CT.pools{1, 1, a} = mk(CT.runs); end
W = clean_split(PP, CT, 2);
verifyEqual(tc, W.runs{2}, CT.runs);
verifyEqual(tc, W.event_frame{2}, nan(1, 7));
verifyEqual(tc, W.event_frame{1}, PP.event_frame{1});
verifyEqual(tc, [W.speed{2}; W.cell_geo{1}{2}], [CT.speed; 1:7]);
verifyEqual(tc, {W.cov{2}, W.alt{2}, W.ksig{2}}, {CT.cov, CT.cov.alt_m, CT.cov.k_sig});
verifyEmpty(tc, W.ref_geo{2});
verifyEqual(tc, {W.cov{1}, W.alt{1}, W.ksig{1}, W.ref_geo{1}}, {PP.cov{1}, PP.alt{1}, PP.ksig{1}, PP.ref_geo{1}});
W0 = clean_split(PP, rmfield(CT, {'cov', 'speed'}), 2);             % a clean pool without them: none of the old split's
verifyEqual(tc, {W0.cov{2}, W0.alt{2}, W0.ksig{2}, W0.speed{2}}, {[], [], [], []});
verifyEmpty(tc, W.pools{2, 1, 1, 2});
for ref = {'mean', 'flight'}
    K = link_env('tables', W, ref{1});
    verifyEqual(tc, K.nR, [3 7]);
    verifyTrue(tc, all(isnan(K.ev{2})));
end
spec = struct('scn', ones(1, 4), 's', ones(1, 4), 'onset', 3 * ones(1, 4), 'follow', false(1, 4), 'fdelay', 2 * ones(1, 4), ...
    'unk', false(1, 4), 'T', 30, 'r', 4:7);                          % geometries beyond the replaced split's
[E, obs] = link_env('reset', W, K, spec, 2, RandStream('mt19937ar', 'Seed', 3));
verifyFalse(tc, any(E.ev));
verifyEqual(tc, obs.feat(:, 1)', CT.runs(4:7));
B = PP; B.pools(1, :, :, 2) = CT.pools(1, :, :); B.runs{2} = CT.runs;
verifyError(tc, @() link_env('tables', B), 'link_env:event_frame');
for f = {'clean_world', 'evaluate_policies', 'edge_map', 'diag_false_alarms', 'diag_path_loss'}
    src = fileread(which(f{1}));
    verifyNotEmpty(tc, strfind(src, 'clean_split(PP, CT, '), f{1});
    verifyEmpty(tc, regexp(src, 'runs\{(2|TEST)\} = CT\.runs', 'once'), f{1});
end
verifyNotEmpty(tc, strfind(fileread(which('clean_world')), ...              % C2's cached clean world carries them all
    'for f = {''pools'', ''runs'', ''event_frame'', ''speed'', ''cell_geo'', ''cov'', ''alt'', ''ksig'', ''ref_geo''}'));
end

function test_pool_checkpoint_resume(tc)
% The pool builders keep every finished cell on disk under a key of everything its frames
% depend on (pool_checkpoint.m): a build stopped part-way, with the next cell's write cut
% off, resumes with the cells it holds, computes only the others, and gives the same result
% as an uninterrupted build; a cell of another key (another detector) is computed again; a
% cell file whose result cannot be read (only its key on disk, or cut off as a power loss
% leaves it) is computed again, and reading it stops the assembly naming it and removes it;
% every file is flushed to the disk before its rename; the output is written whole or not at
% all, and the cells are removed after it.
keys = arrayfun(@(c) pool_checkpoint('key', {'v7-tag', 'det-1', 100 + (1:3), c}), 1:5, 'UniformOutput', false);
verifyEqual(tc, numel(unique(keys)), 5);
verifyEqual(tc, pool_checkpoint('key', {'v7-tag', 'det-1', 100 + (1:3), 2}), keys{2});
job = @(c) struct('Pc', {num2cell(c * (1:6))}, 'x', sin(c * (1:1000)));
[R0, ran0] = ckpt_build('full', keys, job, Inf);
verifyEqual(tc, ran0, 1:5);
verifyError(tc, @() ckpt_build('part', keys, job, 3), 'test:stop');
fid = fopen(fullfile('part', 'cell_0004.tmp.mat'), 'w'); fwrite(fid, uint8(1:100)); fclose(fid);   % a write cut off
[R1, ran1] = ckpt_build('part', keys, job, Inf);
verifyEqual(tc, ran1, [4 5]);
verifyEqual(tc, R1, R0);
verifyEmpty(tc, dir(fullfile('part', '*.tmp.mat')));
k2 = keys; k2{2} = pool_checkpoint('key', {'v7-tag', 'det-2', 100 + (1:3), 2});
verifyEqual(tc, pool_checkpoint('todo', 'part', k2), 2);
f3 = fullfile('part', 'cell_0003.mat');
key = keys{3}; save(f3, 'key', '-v7.3');                              % its key on disk, its result not
verifyEqual(tc, pool_checkpoint('todo', 'part', keys), 3);
verifyError(tc, @() pool_checkpoint('load', 'part', 3), 'pool_checkpoint:unreadable');
verifyFalse(tc, isfile(f3));
pool_checkpoint('save', 'part', 3, keys{3}, job(3));
fid = fopen(f3, 'r'); b = fread(fid, Inf, '*uint8'); fclose(fid);
fid = fopen(f3, 'w'); fwrite(fid, b(1:floor(end / 2))); fclose(fid);  % renamed, half of it on the disk
verifyEqual(tc, pool_checkpoint('todo', 'part', keys), 3);
verifyError(tc, @() pool_checkpoint('load', 'part', 3), 'pool_checkpoint:unreadable');
verifyFalse(tc, isfile(f3));
pool_checkpoint('commit', 'out.mat', struct('PP', R1{1}, 'clean_ref', 7));
verifyEqual(tc, sort(who('-file', 'out.mat'))', {'PP', 'clean_ref'});
verifyFalse(tc, isfile('out.tmp.mat'));
pool_checkpoint('clear', 'part');
verifyFalse(tc, isfolder('part'));
src = fileread(which('pool_checkpoint'));
verifyEqual(tc, numel(regexp(src, 'flush_file\(tmp\);\s*\n\s*movefile\(tmp, ')), 2);   % a cell and the output
src = fileread(which('build_policy_pools'));
verifyNotEmpty(tc, strfind(src, 'pool_checkpoint(''key'', {MODEL_TAG, DET_ID, runs, cells(c), EBNO, ACTIONS, geoc{c}, opt, ...'));
verifyNotEmpty(tc, strfind(src, 'parfor (k = 1:numel(todo), NWP)'));
verifyNotEmpty(tc, strfind(fileread(which('pool_worker_init')), 'cd(d);'));   % the workers' own folder: the cells' path is absolute
for f = {'build_policy_pools', 'build_clean_test_pools', 'build_check_pools'}
    src = fileread(which(f{1}));
    for c = {'todo', 'save', 'load', 'commit', 'clear'}
        verifyNotEmpty(tc, strfind(src, ['pool_checkpoint(''' c{1} ''''])', [f{1} ' ' c{1}]);
    end
    verifyEmpty(tc, regexp(src, 'save\(f_out|save\(''data/policy_pools\.mat''', 'once'), f{1});
    verifyNotEmpty(tc, strfind(src, 'CKD = fullfile(pwd, ''data'', '), f{1});
end
end

function [out, ran] = ckpt_build(dirn, keys, job, stop)
% The pool builders' loop: the cells not on disk, each saved as it finishes (an error after
% cell stop), then every cell read back from disk.
todo = pool_checkpoint('todo', dirn, keys); ran = [];
for c = todo
    pool_checkpoint('save', dirn, c, keys{c}, job(c)); ran(end+1) = c; %#ok<AGROW>
    if c == stop, error('test:stop', 'stopped after cell %d', c); end
end
out = arrayfun(@(c) pool_checkpoint('load', dirn, c), 1:numel(keys), 'UniformOutput', false);
end

function test_monitor_release_fusion(tc)
% The fusion's window holds every frame's levels less the known gain of the configuration it
% was received with (policy_monitor.m): released after power_control, rate_reduce or both, a
% clean link reads no level step and the fused class stays that of no_action, while a real
% 4 dB step behind a held configuration still reads as one. Without the compensation the
% release of rate_reduce+power_control reads as a step of our level.
A = policy_actions(); na = find(strcmp(A, 'no_action')); nF = numel(link_features('names'));
p = base_params(); [gk, gw] = config_gain_db(A, p);
cls = {'none', 'path_loss'}; C = numel(cls);
nT = numel(temporal_evidence('names', C)); wn = window_cues('names'); nZ = nT + numel(wn) + C;
FM = struct('W', zeros(nZ + 1, C), 'mu', zeros(1, nZ), 'sd', ones(1, nZ), 'C', C, 'lambda', 0);
FM.W(nT + find(strcmp(wn, 'stp_db')), 2) = 2; FM.W(nT + find(strcmp(wn, 'stp_db_mon')), 2) = 2; FM.W(end, 2) = -12;
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', -Inf, 'confirm', [2 2], ...
    'alarm_mode', 'class_drop', 'drop_db', 3, 'cfg_gain_db', gk, 'pw', 10.^(gw / 10), 'fuse', FM, 'fuse_N', 5);
rng(5); T = 24; ng = 0.3 * randn(T, 3); ns = 0.3 * randn(T, 1);
    function [cl, pr, st] = relrun(PPx, seq, step)
        m = policy_monitor('init', 1, numel(A)); cl = cell(1, T); pr = zeros(T, C); st = zeros(T, 2);
        for t = 1:T
            o = struct('probs', [1 0], 'unknown', false, 'feat', zeros(1, nF), 'maha', 0);
            o.feat(feature_index('log_ber')) = -6; o.feat(feature_index('est_margin')) = 20;
            lv = -step * (t > 12);
            o.feat(feature_index('sinr')) = 12 + lv + gk(seq(t)) + ns(t) - 10*log10(4) + 10*log10(2);
            o.gant = lv + gw(seq(t)) + ng(t, :); o.cfg_link = seq(t);
            [m, M] = policy_monitor('update', m, o, PPx, seq(t));
            m = policy_monitor('change', m, t < T && seq(t + 1) ~= seq(t));
            cl{t} = M.cls{1}; pr(t, :) = M.probs;
            Z = window_cues(m.wg(:, :, end-4:end), m.wf(:, :, end-4:end), [], []);
            st(t, :) = Z([find(strcmp(wn, 'stp_db')), find(strcmp(wn, 'stp_db_mon'))]);
        end
    end
[c0, p0, s0] = relrun(PP, na * ones(1, T), 0);                         % no_action throughout
verifyEqual(tc, unique(c0), {'none'});
for c = {'power_control', 'rate_reduce', 'rate_reduce+power_control'}
    ac = find(strcmp(A, c{1}));
    [c1, p1, s1] = relrun(PP, [ac * ones(1, 12), na * ones(1, 12)], 0);
    verifyEqual(tc, unique(c1), {'none'}, c{1});
    verifyEqual(tc, p1, p0, 'AbsTol', 1e-9, c{1});
    verifyEqual(tc, s1, s0, 'AbsTol', 1e-9, c{1});
    [c2, ~, s2] = relrun(PP, ac * ones(1, T), 4);                    % a real 4 dB step behind it
    verifyTrue(tc, all(strcmp(c2(13:16), 'path_loss')), c{1});
    verifyGreaterThan(tc, min(s2(13:16, :), [], 'all'), 3, c{1});
end
PPu = PP; PPu.cfg_gain_db = zeros(1, numel(A)); PPu.pw = ones(1, numel(A));
ac = find(strcmp(A, 'rate_reduce+power_control'));
cu = relrun(PPu, [ac * ones(1, 12), na * ones(1, 12)], 0);
verifyTrue(tc, all(strcmp(cu(13:16), 'path_loss')));
end

function test_det_frames_rolling_in(tc)
% DET of a rolling-in flight (an event frame) reads it as its episodes do (link_env.m): the
% same flight's clean link before the event's frame as the lead-in, the cell's frames from it
% on; the cell's earlier frames (the jammer alone before the roll-in) never count, the fusion
% window at the event's frame holds the clean lead-in, and the drop alarm's reference is the
% lead-in's (not the clean flight's frames after the event). The edge map's LINK reads the
% reference flights the same way (event_rows.m), in its clean pool and in the check pools.
cls = {'none', 'jamming', 'path_loss', 'airframe_shadowing'}; C = numel(cls); nf = numel(link_features('names'));
n = 38; e0 = 11; is = feature_index('sinr');
oh = @(k, m) repmat(double(strcmp(cls, k)), m, 1);
mk = @(pr, act, sinr) struct('probs', pr, 'run', 101 * ones(n, 1), 'gant', zeros(n, 3), ...
    'feat', [zeros(n, is - 1), sinr(:), zeros(n, nf - is)], 'ber', zeros(n, 1), 'act', act * ones(n, 1));
nT = numel(temporal_evidence('names', C)); nZ = nT + numel(window_cues('names')) + C;
FM = struct('W', [eye(C); zeros(nZ + 1 - C, C)], 'mu', zeros(1, nZ), 'sd', ones(1, nZ), 'C', C, 'lambda', 0);
PP = struct('classes', {cls}, 'fuse', FM, 'fuse_N', 3, 'sps', 2, 'bps', 2);   % fused: the window's mean log-probabilities
P = mk([oh('jamming', e0 - 1); oh('airframe_shadowing', n - e0 + 1)], 1, 10 * ones(n, 1));
Pc = mk(oh('none', n), 0, 10 * ones(n, 1));
okn = repmat(strcmp(cls, 'none'), 2, 1);                             % rows whose class is 'none'
[~, on, hf, age] = det_frames(P, Pc, 'jamming+airframe_shadowing', okn, PP, [99 101], [NaN e0]);
verifyFalse(tc, any(on(1:e0 - 1))); verifyTrue(tc, all(on(e0:end)));
verifyTrue(tc, all(isnan(age(1:e0 - 1)))); verifyEqual(tc, age(e0:end)', 0:n - e0);
verifyTrue(tc, hf(e0, 1));                                           % the window: the clean lead-in and the event's frame
verifyFalse(tc, any(hf(e0 + 2:end, 1)));
[~, on0, hf0] = det_frames(P, Pc, 'jamming+airframe_shadowing', okn, PP);   % read from the run's first frame
verifyTrue(tc, all(on0)); verifyFalse(tc, hf0(e0, 1));
sc = 'jamming+airframe_shadowing+path_loss';
ok = repmat(ismember(cls, {'jamming', 'path_loss', 'airframe_shadowing'}), 2, 1);
PP = struct('classes', {cls}, 'fuse', [], 'fuse_N', 1, 'sps', 2, 'bps', 2, 'alarm_mode', 'class_drop', 'drop_db', 3);
Pc = mk(oh('none', n), 0, [10 * ones(e0 - 1, 1); 30 * ones(n - e0 + 1, 1)]);   % the clean flight rises after the event
for md = {'class_drop', 36; 'class_cusum', 36}'
    PP.alarm_mode = md{1}; if strcmp(md{1}, 'class_drop'), PP.drop_db = 3; else, PP.drop_db = md{2}; end
    h = det_frames(mk(oh('none', n), 1, 10 * ones(n, 1)), Pc, sc, ok, PP, 101, e0);   % no drop below the lead-in
    verifyFalse(tc, any(h(:, 1)), md{1});
    h = det_frames(mk(oh('none', n), 1, 4 * ones(n, 1)), Pc, sc, ok, PP, 101, e0);    % 6 dB below it
    verifyFalse(tc, any(h([1:e0 - 1, e0], 1)), md{1});
    verifyTrue(tc, all(h(e0 + 1:end, 1)), md{1});
end
verifyEqual(tc, find(event_rows(Pc, [99 101], [NaN e0]))', e0:n);
src = fileread(which('edge_map'));
verifyNotEmpty(tc, regexp(src, ['k = event_rows\(P, PP\.runs\{sp\}, K\.ev\{sp\}\);\s*\n[^\n]*flight_of\([^\n]*\n' ...
    '\s*FT\.link_k = FT\.link_k \+ accumarray\(i\(k\), double\(P\.fer\(k\)\), \[nF 1\]\);\s*\n' ...
    '\s*FT\.link_n = FT\.link_n \+ accumarray\(i\(k\), 1, \[nF 1\]\);'], 'once'));
verifyNotEmpty(tc, regexp(src, ['k = event_rows\(P, CK\.runs\{1\}, Kc\.ev\{1\}\);\s*\n' ...
    '\s*KF\.link_k = KF\.link_k \+ accumarray\(i\(k\), double\(P\.fer\(k\)\), \[nKF 1\]\);\s*\n' ...
    '\s*KF\.link_n = KF\.link_n \+ accumarray\(i\(k\), 1, \[nKF 1\]\);'], 'once'));
verifyEmpty(tc, regexp(src, '(FT|KF)\.link_[kn] \+ accumarray\(i, ', 'once'));   % no reference flight over every row
verifyNotEmpty(tc, strfind(src, 'det_frames(P, Pc, CK.scen{c}, ok_c, CK, CK.runs{1}, Kc.ev{1});'));
verifyNotEmpty(tc, regexp(src, 'det_frames\(P, PP\.pools\{clean_cell, s, K\.na, sp\}, PP\.scen\{c\}, ok_c, PP, PP\.runs\{sp\}, \.\.\.\s*\n\s*K\.ev\{sp\}\)', 'once'));
end

function test_drop_cusum_alarm(tc)
% The window-limited CUSUM drop alarm (drop_cusum.m: Page's recursion, the drop's size the
% mean of the last 3 drops held in the path-loss levels' range): its statistic for steps, none
% for a drop below half the smallest level; the monitor's 'class_cusum' and 'class_drop' equal
% their sequence form (drop_alarm_seq.m), the reference held while the statistic builds;
% the pass reading (drop_alarm_any.m) equals the whole sequence's; the form chosen on
% validation (drop_alarm_form.m) and read by the policies, DET and the edge map.
z = zeros(1, 3);
verifyEqual(tc, drop_cusum([z, 6 * ones(1, 4)]), [z, 18 36 54 72], 'AbsTol', 1e-9);
verifyEqual(tc, drop_cusum([z, 10 * ones(1, 4)]), [z, 42 84 84 + 20/3 * (10 - 10/3) 84 + 20/3 * (10 - 10/3) + 50], 'AbsTol', 1e-9);
verifyEqual(tc, drop_cusum(2.5 * ones(1, 30)), zeros(1, 30));        % the attitude's common change, at most 2.5 dB
A = policy_actions(); na = find(strcmp(A, 'no_action')); nF = numel(link_features('names'));
rng(7); n = 60; e = 12 + randn(6, n);
e(2, 31:end) = e(2, 31:end) - 6; e(3, 31:end) = e(3, 31:end) - 4; e(4, 31:end) = e(4, 31:end) - 10;
e(5, :) = 12 - 0.1 * (1:n); e(6, :) = 12; e(6, 21:end) = 8;        % a ramp; a noise-free 4 dB step
for md = {'class_drop', 3; 'class_cusum', 36}'
    PP = struct('actions', {A}, 'classes', {{'none', 'path_loss'}}, 'sps', 4, 'bps', 2, 'maha_thr', -Inf, ...
        'confirm', [2 2], 'alarm_mode', md{1}, 'drop_db', md{2}, 'cfg_gain_db', zeros(1, numel(A)));
    m = policy_monitor('init', 6, numel(A)); da = false(6, n);
    for t = 1:n
        o = struct('probs', repmat([1 0], 6, 1), 'unknown', false(6, 1), 'feat', zeros(6, nF));
        o.feat(:, feature_index('log_ber')) = -6;
        o.feat(:, feature_index('sinr')) = e(:, t) - 10*log10(4) + 10*log10(2);
        [m, M] = policy_monitor('update', m, o, PP, na * ones(1, 6));
        da(:, t) = M.drop_alarm';
    end
    verifyEqual(tc, da, drop_alarm_seq(e, md{1}, md{2}), md{1});
    verifyEqual(tc, drop_alarm_any(e, md{1}, md{2}), any(drop_alarm_seq([repmat(e(:, 1), 1, 20), e], md{1}, md{2}), 2), md{1});
end
verifyEqual(tc, find(da(6, :), 1), 26);                              % 6 per cycle from the step on, the reference held
verifyEqual(tc, find(drop_alarm_seq(e(6, :), 'class_drop', 3), 1), 22);
r = 12 - 0.02 * (1:1000); s = 12 * ones(1, 1000); s(500:end) = 4;
verifyEqual(tc, drop_alarm_any([r; s], 'class_cusum', 36), [false; true]);
V = struct('grid', {2:0.5:10, 18 * (1:0.5:10)}, 'pick', {3, 2}, 'det', {0.80 * ones(1, 17), 0.83 * ones(1, 19)}, ...
    'delay', {2 * ones(1, 17), 3 * ones(1, 19)});
[f, h] = drop_alarm_form(V); verifyEqual(tc, {f, h}, {'class_cusum', 27});
V(2).det(:) = 0.805; [f, h] = drop_alarm_form(V); verifyEqual(tc, {f, h}, {'class_drop', 3});   % within a point, a longer delay
V(2).delay(:) = 1.5; verifyEqual(tc, drop_alarm_form(V), 'class_cusum');
V(1).pick = NaN; V(2).det(:) = 0.5; verifyEqual(tc, drop_alarm_form(V), 'class_cusum');
V(2).pick = NaN; [f, h] = drop_alarm_form(V); verifyEqual(tc, f, 'class_drop'); verifyTrue(tc, isnan(h));
V(1).pick = 5; [f, h] = drop_alarm_form(V); verifyEqual(tc, {f, h}, {'class_drop', 4});   % the median at its own pick
src = fileread(which('train_dqn'));
verifyNotEmpty(tc, strfind(src, 'if strcmp(mode, ''class_drop''), mode = drop_mode; end'));
ln = regexp(src, '[^\n]*(?<!\w)monitor\([^\n]*', 'match');      % the local monitor's calls and definition
verifyEqual(tc, numel(ln), 4); verifyTrue(tc, all(contains(ln, {'DROP_MODE', 'drop_mode'})));
verifyNotEmpty(tc, strfind(fileread(which('choose_drop_threshold')), '''drop_alarm'', ''cusum_db'''));
verifyNotEmpty(tc, strfind(fileread(which('det_frames')), 'use_drop = any(strcmp(mode, {''class_drop'', ''class_cusum''}));'));
verifyNotEmpty(tc, strfind(fileread(which('edge_map')), 'RD = pass_cusum(OHP, thr_ohp);'));
verifyEqual(tc, {drop_unit('class_drop'), drop_unit('class_cusum')}, {'dB', 'dB^2'});
src = fileread(which('diag_path_loss'));                             % its sweep stays in the deployed form's units
verifyNotEmpty(tc, strfind(src, 'DD = Dd.THC(j:-1:max(1, j - 2));'));
for f = {'diag_path_loss', 'diag_false_alarms', 'diag_failure_modes', 'diag_never_acted', 'diag_switching', 'train_dqn'}
    verifyEmpty(tc, regexp(fileread(which(f{1})), 'drop %(\.1f|s) dB', 'once'), f{1});
end
verifyNotEmpty(tc, strfind(fileread(which('train_dqn')), 'DU = drop_unit(DROP_MODE);'));
end

function test_drop_cusum_bounded(tc)
% The CUSUM drop alarm clears when the drop ends (drop_cusum.m bounded at twice the
% threshold: its end read by the same test in reverse) and its reference resumes
% (drop_ref.m: an excursion of the statistic that returns to 0 without the alarm joins the
% reference, one that raised it does not), in the monitor as in drop_alarm_seq.m; on a noisy
% clean link the reference stays at the link's level. C1d reads both forms through the
% monitor's confirmation (confirm_alarm.m): single-cycle blips are no confirmed alarm, a
% lasting one is, and the median window is deployed at the threshold it was compared at.
z = zeros(1, 3);
verifyEqual(tc, drop_cusum([z, 10 * ones(1, 4), z], 36), [z, 42 72 72 72 22 0 0], 'AbsTol', 1e-9);
verifyEqual(tc, drop_cusum([z, 6 * ones(1, 4)], 36), drop_cusum([z, 6 * ones(1, 4)]));   % to the crossing as unbounded
R0 = [nan(1, 8), 12, 12];
[R, P, x] = drop_ref(R0, nan(1, 10), false, 8, true, 6, false);      % held while the statistic is above 0
verifyEqual(tc, R, R0); verifyEqual(tc, P(end), 8);
verifyEqual(tc, drop_ref(R, P, x, 12, true, 0, false), [nan(1, 6), 12, 12, 8, 12]);
[R, P, x] = drop_ref(R, P, x, 4, false, 40, true);                   % the excursion raised the alarm
verifyEqual(tc, drop_ref(R, P, x, 12, true, 0, false), [nan(1, 7), 12, 12, 12]);
A = policy_actions(); na = find(strcmp(A, 'no_action')); nF = numel(link_features('names'));
rng(8); n = 60; e = 12 * ones(3, n);
e(1, :) = e(1, :) + randn(1, n); e(1, 11:40) = e(1, 11:40) - 10;   % a 30-cycle 10 dB loss in 1 dB noise
e(2, 11:40) = -10; e(2, 51:end) = 6;                                 % a 30-cycle 22 dB loss, then a 6 dB step
e(3, :) = e(3, :) + randn(1, n); e(3, 21:40) = e(3, 21:40) - 6;
for md = {'class_drop', 3; 'class_cusum', 36}'
    PP = struct('actions', {A}, 'classes', {{'none', 'path_loss'}}, 'sps', 4, 'bps', 2, 'maha_thr', -Inf, ...
        'confirm', [2 2], 'alarm_mode', md{1}, 'drop_db', md{2}, 'cfg_gain_db', zeros(1, numel(A)));
    m = policy_monitor('init', 3, numel(A)); da = false(3, n); dc = da;
    for t = 1:n
        o = struct('probs', repmat([1 0], 3, 1), 'unknown', false(3, 1), 'feat', zeros(3, nF));
        o.feat(:, feature_index('log_ber')) = -6;
        o.feat(:, feature_index('sinr')) = e(:, t) - 10*log10(4) + 10*log10(2);
        [m, M] = policy_monitor('update', m, o, PP, na * ones(1, 3));
        da(:, t) = M.drop_alarm'; dc(:, t) = M.confirmed';
    end
    verifyEqual(tc, da, drop_alarm_seq(e, md{1}, md{2}), md{1});
    verifyEqual(tc, dc, confirm_alarm(da, PP.confirm), md{1});
    verifyTrue(tc, all(da(1:2, 13:40), 'all'), md{1});              % held through the loss
    verifyFalse(tc, any(da(1:2, 43:50), 'all'), md{1});             % clear within 2 cycles of its end
    verifyEqual(tc, find(da(2, 43:end), 1), 10, md{1});              % the step after it, read from the restored reference
end
[~, W] = drop_alarm_seq(e(2, :), 'class_cusum', 36);
verifyEqual(tc, W(39:42), [72 72 0 0]);
rng(9); x = 12 + 2.4 * randn(400, 100);                              % a clean link at the estimate's spread
[~, ~, dr] = drop_alarm_seq(x, 'class_cusum', 72);
verifyLessThan(tc, abs(median(dr(:, end) + median(x(:, end - 2:end), 2)) - 12), 0.6);
a = false(3, 30); a(1, [5 9 14 20]) = true; a(2, 10:11) = true; a(3, [5 7 9]) = true;
CF = [2 2; 3 3; 4 5; 5 5];                                           % C2's monitors
c = confirm_alarm(a, CF);
verifyEqual(tc, any(c, 2), [false; true; false]); verifyEqual(tc, find(c(2, :), 1), 11);
rng(10); a = rand(500, 30) < 0.3;
verifyEqual(tc, any(confirm_alarm(a, CF), 2), any(confirm_alarm(a, [2 2]), 2));
src = fileread(which('choose_drop_threshold'));
verifyNotEmpty(tc, strfind(src, 'a = confirm_alarm(drop_alarm_seq(Ecl, FM{f}, GR{f}(j)), CF);'));
verifyNotEmpty(tc, strfind(src, 'a = confirm_alarm(drop_alarm_seq(Epl, FM{f}, GR{f}(j)), CF);'));
verifyNotEmpty(tc, strfind(src, 'drop_db = thr_val; drop_from = ''validation'';'));
verifyNotEmpty(tc, strfind(fileread(which('train_dqn')), 'if isfield(Dd, ''drop_from''), DROP_FROM = Dd.drop_from; end'));
src = fileread(which('det_frames'));
verifyNotEmpty(tc, strfind(src, 'seq_cusum(ref - e(jp), ref - e(jc), C.cusum_win, dd) >= dd'));
verifyNotEmpty(tc, strfind(src, 'w0 = drop_cusum(d(t), w0, dx, thr);'));
end

function test_split_norm_memory(tc)
% The pool builders read the training z-score and the classes alone (split_norm.m: the
% top-level variables prepare_data.m writes beside the splits; a file without them read
% whole); C2 keeps the train and validation pools only, and the check-pool builder no
% frames of the policy pools.
splits = struct('train', struct('X', rand(64, 64, 1, 50)), 'norm', struct('feat_mean', 1:3, 'feat_std', 4:6, ...
    'feat_names', {{'a', 'b', 'c'}}), 'classes', {{'none'; 'jamming'}});
save('splits_old.mat', 'splits', '-v7.3');
save('splits_new.mat', 'splits', '-v7.3');
N = struct('norm', splits.norm, 'classes', {splits.classes});
save('splits_new.mat', '-struct', 'N', '-append');
for f = {'splits_old.mat', 'splits_new.mat'}
    [nm, cl] = split_norm(f{1});
    verifyEqual(tc, nm, splits.norm, f{1}); verifyEqual(tc, cl, splits.classes, f{1});
end
verifyNotEmpty(tc, strfind(fileread(which('prepare_data')), 'save(''data/splits.mat'', ''-struct'', ''N'', ''-append'');'));
for f = {'build_policy_pools', 'build_clean_test_pools', 'build_check_pools'}
    src = fileread(which(f{1}));
    verifyNotEmpty(tc, strfind(src, 'nm = split_norm();'), f{1});
    verifyEmpty(tc, strfind(src, 'load(''data/splits.mat'''), f{1});
end
verifyNotEmpty(tc, regexp(fileread(which('train_dqn')), 'K = link_env\(''tables'', PP\);\r?\nPP\.pools\(:, :, :, 3:end\) = \{\[\]\};', 'once'));
verifyNotEmpty(tc, regexp(fileread(which('build_check_pools')), 'PTAG = PP\.model_tag;[^\n]*\r?\nclear PP', 'once'));
end

function test_clean_pool_draws(tc)
% The clean-link pools keep the seeds and every per-flight draw they flew:
% geometry k takes family 1 + 2 floor((k - 1) / 100), geometry mod(k - 1, 100) + 1 of the
% block; the edge map reads the kept draws; a geometry outside 1-100 of a block stops.
for k = [1 100 101 200 201 300]
    verifyEqual(tc, clean_pool_seed(2, 15, k), pool_seed(1 + 2 * floor((k - 1) / 100), 2, 15, mod(k - 1, 100) + 1));
end
verifyError(tc, @() pool_seed(1, 1, 15, 101), ?MException);
verifyError(tc, @() pool_seed(1, 1, 15, 0), ?MException);
p = base_params();
s = arrayfun(@(k) clean_pool_seed(1, 4, k), [5 150 250]);
V = flight_cov({struct('seed', s, 'speed', [30 60 90])}, 6, p);
v = [30 60 90];
for q = 1:3
    d = flight_draws(s(q), v(q) / 3.6 * p.carrier_freq / p.c_light, p, struct('ebno', 6));
    verifyEqual(tc, [V.alt_m(q), V.k_sig(q), V.rho(q), V.bank(q), V.ds_ns(q)], [d.alt_m, d.k_sig, d.rho, d.bank, d.ds_ns(1)], ...
        'AbsTol', 1e-9);
end
src = fileread(which('edge_map'));
verifyEmpty(tc, strfind(src, 'pool_seed(1, s_(q), blk, r_(q))'));
verifyNotEmpty(tc, strfind(src, 'V = CT.cov;'));
src = fileread(which('build_clean_test_pools'));
verifyNotEmpty(tc, regexp(src, '''seed'', sds, ''cov'', V', 'once'));
end

function test_surv_on_air(tc)
% SURV counts the flights with the threat on the air: a shadowing flight whose
% attitude hides no antenna is no threat flight, recoverable or not.
TGT = struct('surv', 0.9);
F = struct('geo', (1:40)', 'surv', [true(36, 1); false(4, 1)], 'on', [true(36, 1); false(4, 1)]);
V = surv_layer(F, 'surv', TGT, 200);
verifyEqual(tc, [V.n, V.value, V.verdict], [36 1 1]);
F.on(:) = true;
V = surv_layer(F, 'surv', TGT, 200);
verifyEqual(tc, V.n, 40); verifyEqual(tc, V.value, 0.9);
verifyEqual(tc, surv_layer(rmfield(F, 'on'), 'surv', TGT, 200).n, 40);
src = fileread(which('edge_map'));
verifyNotEmpty(tc, strfind(src, '''harm'', HM(ii), ''on'', K.on(ii)'));
verifyNotEmpty(tc, strfind(src, '''harm'', hmc(ik), ''on'', Kc.on(ik)'));
end

function test_experiments_keep_on_air(tc)
% The unknown-threat and the unseen-combination experiments keep the threat flag of
% dqn_eval_batches.m (link_env.m K.on) instead of counting every episode as a threat one.
for f = {'experiment_unknown_threat', 'experiment_combo_generalization'}
    src = fileread(which(f{1}));
    verifyEmpty(tc, strfind(src, 'R.threat = true(1, n)'), f{1});
    verifyNotEmpty(tc, strfind(src, 'R.threat = R.threat(1:n) &'), f{1});
end
end

function test_clean_pool_identity(tc)
% The clean-link pools carry the detector and the link model of the pools they belong to:
% another det_id or model tag stops the reader; train_dqn.m, evaluate_policies.m
% and edge_map.m check them; a fusion re-key moves the clean pools' det_id with the pools'.
P = struct('det_id', 'a', 'model_tag', 'm1');
check_det_id(P, struct('det_id', 'a', 'model_tag', 'm1'), 'test', 'data/clean_val_pools.mat');
verifyError(tc, @() check_det_id(P, struct('det_id', 'b', 'model_tag', 'm1'), 'test', 'x'), 'check_det_id:mismatch');
verifyError(tc, @() check_det_id(P, struct('det_id', 'a', 'model_tag', 'm2'), 'test', 'x'), 'check_det_id:model');
verifyError(tc, @() check_det_id(P, struct('model_tag', 'm1'), 'test', 'x'), 'check_det_id:mismatch');
for f = {{'train_dqn', 'CV'}, {'evaluate_policies', 'CT'}, {'edge_map', 'CT'}}
    verifyNotEmpty(tc, strfind(fileread(which(f{1}{1})), sprintf('check_det_id(PP, %s, ''%s'', ''data/clean_', f{1}{2}, f{1}{1})), f{1}{1});
end
d = fullfile(tc.TestData.tmp, 'rekey_ct'); mkdir(fullfile(d, 'data'));
c0 = cd(d); back = onCleanup(@() cd(c0));
ood = struct('score', 'last', 'win', 3); classes = {'none', 'jamming'}; trained_at = 7;
save('data/trained_detector.mat', 'ood', 'classes', 'trained_at');
T = struct('retain', 0.95, 'maha', -2, 'maha_val', [-3; -1], 'win', 3, 'score', 'last'); save('data/ood_thresholds.mat', 'T');
F0 = struct('FM', struct('mu', zeros(1, 11)), 'N', 1, 'q_thr', 4);
FM = struct('mu', zeros(1, 13)); N = 12; q_thr = 4.5; save('data/fusion.mat', 'FM', 'N', 'q_thr');
Q = struct('probs', single([0.9 0.1]), 'maha', single(0), 'feat', single([1 2]), 'ber', 0, 'run', 1);
old = detector_id(trained_at, ood, F0);
PP = struct('pools', {{Q, []}}, 'classes', {classes}, 'maha_thr', -2, 'unk_win', 3, 'fuse', F0.FM, 'fuse_N', 1, ...
    'q_thr', 4, 'det_id', old, 'cfg_gain_db', [0 1], 'created', 'x');
save('data/policy_pools.mat', 'PP', '-v7.3');
CT = struct('pools', {{Q}}, 'runs', 1, 'det_id', old); save('data/clean_val_pools.mat', 'CT', '-v7.3');
CT.det_id = 'other'; save('data/clean_test_pools.mat', 'CT', '-v7.3');
evalc('rekey_pools({''data/policy_pools.mat'', ''data/clean_val_pools.mat'', ''data/clean_test_pools.mat''})');
new = detector_id(trained_at, ood, struct('FM', FM, 'N', N, 'q_thr', q_thr));
verifyEqual(tc, load('data/policy_pools.mat').PP.det_id, new);
verifyEqual(tc, load('data/clean_val_pools.mat').CT.det_id, new);
verifyEqual(tc, load('data/clean_test_pools.mat').CT.det_id, 'other');          % not of these pools: left
verifyNumElements(tc, dir('data/clean_val_pools_before_rekey_*.mat'), 1);
end

function test_result_status(tc)
% A latency, an evaluation or an edge map of another detector or deployed policy, or older
% than its inputs, is STALE; the policy stamp follows the deployed policy, its
% monitors and weights; the KPIs read the deployed chain's latency, PENDING without one.
d = fullfile(tc.TestData.tmp, 'status'); mkdir(fullfile(d, 'data')); mkdir(fullfile(d, 'results'));
c0 = cd(d); back = onCleanup(@() cd(c0));
ood = struct('score', 'last', 'win', 3); classes = {'none'}; trained_at = 7; %#ok<NASGU>
save('data/trained_detector.mat', 'ood', 'classes', 'trained_at');
T = struct('retain', 0.95, 'maha', -2, 'maha_val', [-3; -1], 'win', 3, 'score', 'last'); save('data/ood_thresholds.mat', 'T');
FM = struct('mu', zeros(1, 3)); N = 4; q_thr = 4; save('data/fusion.mat', 'FM', 'N', 'q_thr');
id = detector_id(trained_at, ood, fusion_model());
agent = struct('dense', struct('W', {{1, 2}}, 'b', {{0, 0}})); confirm = [4 5]; alarm_mode = 'class_drop'; drop_db = 5;
deployed = 'dqn_esc'; rule_sel = struct('alarm_mode', 'class_drop', 'confirm', [5 5], 'drop_db', 6); det_id = id;
maha_thr = T.maha;
save('data/trained_dqn.mat', 'agent', 'confirm', 'alarm_mode', 'drop_db', 'deployed', 'rule_sel', 'det_id', 'maha_thr');
Q = load('data/trained_dqn.mat'); st = policy_stamp(Q);
Q2 = Q; Q2.deployed = 'rule_sel'; Q3 = Q; Q3.rule_sel.drop_db = 7; Q4 = Q; Q4.agent.dense.W{1} = 3; Q5 = Q; Q5.maha_thr = -3;
verifyEqual(tc, numel(unique({st, policy_stamp(Q2), policy_stamp(Q3), policy_stamp(Q4), policy_stamp(Q5)})), 5);
pause(1.1);
LAT = struct('det_id', id, 'policy_stamp', st); save('results/latency.mat', 'LAT');
KP = struct('policy_stamp', st); save('results/policy_evaluation.mat', 'KP');
pause(1.1);
EM = struct('det_id', id, 'policy_stamp', 'zzz'); save('results/edge_map.mat', 'EM');
S = result_status();
verifyFalse(tc, status_of(S, 'results/latency.mat').stale);
verifyFalse(tc, status_of(S, 'results/policy_evaluation.mat').stale);
verifyTrue(tc, status_of(S, 'results/edge_map.mat').stale);
LAT.det_id = 'other'; save('results/latency.mat', 'LAT');
verifyTrue(tc, status_of(result_status(), 'results/latency.mat').stale);
LAT = rmfield(LAT, 'det_id'); save('results/latency.mat', 'LAT');
verifyTrue(tc, status_of(result_status(), 'results/latency.mat').stale);
verifyFalse(tc, status_of(result_status(), 'results/phy_validation.txt').present);
src = fileread(which('measure_all_kpis'));
verifyNotEmpty(tc, strfind(src, 'st7 = ''PENDING'''));
verifyNotEmpty(tc, strfind(src, 'Lt.total_dep_median_ms < 10 && Lt.total_dep_p95_ms < 20'));
src = fileread(which('measure_latency'));
verifyNotEmpty(tc, strfind(src, '[kindP, agP, optP] = policy_setup(dep, Q, sel, [], [], [], na);'));
end

function e = status_of(S, f)
% The entry of result_status.m for file f.
e = S(strcmp({S.file}, f));
end

function test_overhead_monitor_drop(tc)
% The pass over the GCS is a ramp: the monitor reads a drop as its 10-cycle
% reference minus its 3-cycle median, the same as monitor_window_drop.m; a step reads in
% full, a ramp of s dB per cycle 4.5 s; the verdict commits the path_loss level only where
% the read drop reaches the threshold, else reads the no-response PROT.
A = policy_actions();
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'alarm_mode', 'class_drop', 'drop_db', 100, ...
    'cfg_gain_db', zeros(1, numel(A)));
o = struct('probs', double(strcmp(cls, 'none')), 'unknown', false, 'feat', zeros(1, numel(link_features('names'))));
o.feat(feature_index('log_ber')) = -6;
for e = {[10 * ones(1, 12), 4 * ones(1, 10)], [10 * ones(1, 12), 10 - 0.2 * (1:60)], [10 * ones(1, 12), 10 - 3 * sin(linspace(0, pi, 40))]}
    m = policy_monitor('init', 1, numel(A)); mx = 0;
    for t = 1:numel(e{1})
        x = o; x.feat(feature_index('sinr')) = e{1}(t) - 10*log10(2);
        [m, M] = policy_monitor('update', m, x, PP, 1); m = policy_monitor('change', m, false);
        mx = max(mx, M.drop);
    end
    verifyEqual(tc, monitor_window_drop(e{1}), mx, 'AbsTol', 1e-9);
end
verifyEqual(tc, monitor_window_drop([10 * ones(1, 12), 4 * ones(1, 10)]), 6, 'AbsTol', 1e-9);
verifyEqual(tc, monitor_window_drop(10 - 0.2 * (0:59)), 0.9, 'AbsTol', 1e-9);
verifyEqual(tc, monitor_window_drop([10 * ones(1, 12), 4, 4, 10 * ones(1, 10)]), 6, 'AbsTol', 1e-9);   % a 2-cycle dip reads
verifyEqual(tc, monitor_window_drop([10 * ones(1, 12), 4, 10 * ones(1, 10)]), 0, 'AbsTol', 1e-9);      % a 1-cycle dip does not
lvs = [6 10 14]; com = [1 1 -1]; nr = [1 0 -1];
verifyEqual(tc, overhead_verdict([5 9], [true true], lvs, com, nr), 1);           % both read, both committed
verifyEqual(tc, overhead_verdict([5 13], [true true], lvs, com, nr), 0);          % the lost bound not committed
verifyEqual(tc, overhead_verdict([11 15], [true true], lvs, com, nr), -1);        % the tracked bound not
verifyEqual(tc, overhead_verdict([5 9], [false true], lvs, com, nr), 1);          % unread: no-response PROT 1 at 6 dB
verifyEqual(tc, overhead_verdict([7 9], [false true], lvs, com, nr), 0);          % unread at 10 dB: UNDETERMINED
verifyEqual(tc, overhead_verdict([11 15], [false false], lvs, com, nr), 0);       % unread: never NOT COMMITTED
[v, lt, ll] = overhead_verdict([5 20], [true true], lvs, com, nr);
verifyEqual(tc, [v lt], [0 6]); verifyTrue(tc, isnan(ll));                         % beyond the top level
p = base_params();
[A0, rel, dd] = overhead_drop_db(120, 0.56, p.gcs_h_m, p.uav_null_db);
verifyEqual(tc, A0, max(0, -min(rel)), 'AbsTol', 1e-12); verifyEqual(tc, rel(end), 0, 'AbsTol', 1e-9);
[Ab, relb] = overhead_drop_db(120, 0.56, p.gcs_h_m, p.uav_null_db, 30);
verifyEqual(tc, size(relb, 1), 72); verifyEqual(tc, Ab, max(0, -min(min(relb, [], 1))), 'AbsTol', 1e-12);
verifyEqual(tc, numel(dd), size(rel, 2));
end

function test_kpi6_union_and_intervals(tc)
% KPI 6 counts the clean flights of the second test split beside the test split's and the
% clean pools', with the threshold's source and a warning on a fallback; KPI 4 lists
% the threats outside the envelope and gives per-threat intervals, KPI 7 the speed spread
% with its bootstrap interval.
src = fileread(which('evaluate_policies'));
verifyNotEmpty(tc, strfind(src, 'sets(end+1) = struct(''name'', ''clean2'''));
verifyNotEmpty(tc, strfind(src, 'RU{pk} = cat_struct(RU{pk}, RES{iC2, pk})'));
verifyNotEmpty(tc, strfind(src, 'warning(''evaluate_policies:kpi1'''));
verifyNotEmpty(tc, strfind(src, 'warning(''evaluate_policies:cleanpools'''));
verifyNotEmpty(tc, strfind(fileread(which('measure_all_kpis')), 'threats with no level inside the envelope'));
x = [ones(1, 50), zeros(1, 50)]; bin = [ones(1, 50), 2 * ones(1, 50)]; cl = 1:100;
S = spread_boot(x, bin, cl, 2, 500, 1);
verifyEqual(tc, S(1), 1); verifyLessThanOrEqual(tc, S(2), 1); verifyEqual(tc, S(3), 1);
rs = RandStream('mt19937ar', 'Seed', 3);
x = double(rand(rs, 1, 400) < 0.8); bin = repmat(1:4, 1, 100); cl = repelem(1:100, 4);
S = spread_boot(x, bin, cl, 4, 1000, 2);
r = arrayfun(@(b) mean(x(bin == b)), 1:4);
verifyEqual(tc, S(1), max(r) - min(r), 'AbsTol', 1e-12); verifyLessThanOrEqual(tc, S(2), S(3));
verifyTrue(tc, all(S >= 0 & S <= 1));
verifyEqual(tc, spread_boot(x, zeros(size(x)), cl, 4, 100, 1), [NaN NaN NaN]);
end

function test_main_stage_list(tc)
% main.m runs every stage of run_stage.m, the edge map and the other script stages
% in a workspace of their own.
src = fileread(which('run_stage'));
t = regexp(src, '''(\w+)'', ''(\w+)''', 'tokens');
names = cellfun(@(c) c{2}, t, 'UniformOutput', false);
names = setdiff(names, {'build_fresh_test'});            % run_dataset_sweep, extract_spectrograms, prepare_data
m = fileread(which('main'));
for n = names
    verifyTrue(tc, contains(m, n{1}), n{1});
end
verifyNotEmpty(tc, strfind(m, 'run_own(''edge_map'')'));
verifyNotEmpty(tc, strfind(m, 'run_own(scr{1}, true)'));
end

function test_hover_label(tc)
% The hover rows are labelled with the attitude they fly: the tilt and wobble of
% hover_attitude.m, not calm air.
src = fileread(which('edge_map'));
verifyEmpty(tc, strfind(src, 'calm air'));
verifyNotEmpty(tc, strfind(src, 'p0.wobble_roll_deg, p0.wobble_pitch_deg, p0.wobble_amp_deg, p0.wobble_freq_hz'));
p = base_params();
verifyNotEmpty(tc, p.wobble_roll_deg); verifyNotEmpty(tc, p.wobble_freq_hz);
end

function test_episode_cycle_link(tc)
% The live decision cycle tells the monitor the configuration its frame was received with
% (the console draws each frame under the configuration in use), so the known gain comes
% out there too.
src = fileread(which('episode_cycle'));
verifyNotEmpty(tc, strfind(src, 'obs.cfg_link = prev;'));
verifyNotEmpty(tc, strfind(fileread(which('demo_gui')), '''cfg_gain_db'', config_gain_db(env.action_names, p0)'));
end

function test_params_id(tc)
% The link model's identity is fixed by the parameters' content: the same struct gives the
% same identity, any changed field another one.
p = struct('a', 1, 'b', [1 2 3], 'c', 'x');
verifyEqual(tc, params_id(p), params_id(p));
q = p; q.b(2) = 2.5;
verifyNotEqual(tc, params_id(p), params_id(q));
verifyEqual(tc, numel(params_id(p)), 32);
end

%% ---------- airframe shadowing on flights that hide an antenna ----------
function test_shadow_pool_layout(tc)
% The pools' layout (pool_layout.m): every (cell, Eb/N0) keeps its count per split (train 8,
% validation 6, test 12, second test 60, the combined threats' own 24; the edge speeds 24 at
% hover away from the nominal level and 36 at it); airframe shadowing flies flights of its
% own in every split, the levels flown at the same rolls sharing them (shadow_groups.m), a
% combination beside the single threat at its level and its own in the second test, at the
% edge speeds the 161 km/h flights of the nominal level only (no hover); the clean link
% keeps its own flights and flies the shadowing ones as their reference only.
p = base_params(); C = decision_config();
NGEO = [8 6 12 36 60]; NCOMB = [0 0 0 0 24]; NHOVER = 24; iSpd = 4;
th = {}; sev = [];
for t = {'none', 'jamming', 'airframe_shadowing'}
    v = 1:numel(C.sev_names); if strcmp(t{1}, 'none'), v = C.nominal; end
    th = [th, repmat(t, 1, numel(v))]; sev = [sev, v]; %#ok<AGROW>
end
for t = {'jamming+path_loss', 'jamming+airframe_shadowing', 'tone_jamming+spoofing+airframe_shadowing'}
    th = [th, repmat(t, 1, numel(C.combo_sev))]; sev = [sev, C.combo_sev]; %#ok<AGROW>
end
lv = nan(1, numel(th));
for c = find(contains(th, 'airframe_shadowing')), lv(c) = threat_params(p, th{c}, sev(c), C).shadow_db; end
[grp, band, glv] = shadow_groups(lv, p);
ish = find(strcmp(th, 'airframe_shadowing'));
verifyEqual(tc, grp(ish), [1 2 3 3 4]);                                % 8 | 12 | 15.5 and 20 | 25 dB
verifyEqual(tc, band, [16.1 33.0; 16.1 49.0; 16.1 57.9; 32.0 57.9], 'AbsTol', 0.05);
verifyEqual(tc, glv, [8 12 15.5 25]);
verifyEqual(tc, grp(~contains(th, 'airframe_shadowing')), zeros(1, sum(~contains(th, 'airframe_shadowing'))));
kind = 1 + contains(th, '+'); kind(strcmp(th, 'none')) = 0;
[geo, ref, nG, parts] = pool_layout(kind, grp, sev, C.nominal, NGEO, NCOMB, NHOVER, iSpd);
verifyEqual(tc, nG, [40 30 60 48 372]);
n = @(c) cellfun(@numel, geo{c});
verifyEqual(tc, n(1), [8 6 12 36 84]);                                  % the clean link's own
ij = find(strcmp(th, 'jamming'));
verifyEqual(tc, n(ij(1)), [8 6 12 24 60]);
verifyEqual(tc, n(ij(C.nominal)), [8 6 12 36 60]);
verifyEqual(tc, geo{ij(1)}{4}, 1:24);                                   % hover
for c = ish
    verifyEqual(tc, n(c), [8 6 12 12 * (sev(c) == C.nominal) 60]);      % no hover
    verifyTrue(tc, all(cellfun(@(g, r) all(ismember(g, r)), geo{c}, ref)));
end
verifyEqual(tc, geo{ish(C.nominal)}{4}, 36 + (1:12));                  % after the 24 hover and 12 at 161 km/h
verifyEqual(tc, geo{ish(3)}([1 2 3 5]), geo{ish(4)}([1 2 3 5]));      % 15.5 and 20 dB: the same rolls, the same flights
verifyEmpty(tc, intersect(geo{ish(1)}{3}, geo{ish(2)}{3}));
for c = find(strcmp(th, 'jamming+path_loss')), verifyEqual(tc, n(c), [8 6 12 0 24]); verifyEqual(tc, geo{c}{5}, 61:84); end
for c = find(contains(th, '+') & contains(th, 'airframe_shadowing'))
    verifyEqual(tc, n(c), [8 6 12 0 24]);
    for sp = 1:3, verifyEqual(tc, geo{c}{sp}, geo{ish(sev(c))}{sp}); end   % beside the single at its level
    verifyEmpty(tc, intersect(geo{c}{5}, [geo{ish(sev(c))}{5}, 1:84]));  % its own in the second test
    verifyTrue(tc, all(ismember(geo{c}{5}, ref{5})));
end
for sp = 1:5
    verifyEmpty(tc, intersect(ref{sp}, geo{1}{sp}));                    % reference only
    verifyEqual(tc, sort([geo{1}{sp}, ref{sp}]), 1:nG(sp));             % the clean link flies every geometry
    verifyEqual(tc, sort([parts([parts.split] == sp).pos]), sort(ref{sp}));
end
verifyEqual(tc, sum(arrayfun(@(q) numel(q.pos), parts)), sum(nG - [8 6 12 36 84]));
% the reduced chain check's layout
[geo, ref, nG] = pool_layout(kind, grp, sev, C.nominal, [2 2 2 2 2], [0 0 0 0 2], 1, iSpd);
verifyEqual(tc, nG, [10 10 10 3 16]);
verifyEqual(tc, cellfun(@numel, geo{ish(C.nominal)}), [2 2 2 1 2]);
verifyEqual(tc, cellfun(@numel, ref), [8 8 8 1 12]);
end

function test_shadow_selection(tc)
% The shadowing cells' own flights (pool_geometries.m with a selection): every flight hides an
% antenna at its level in some frame of the run (hides_antenna.m: flight_draws.m d.hidden
% with the draws link_seed.m sets), the candidates are tried once each in order
% (shadow_pool_seed.m), the skipped ones hide none; a Latin hypercube keeps one flight per
% stratum over the speeds shadowing is flown at; the model hides an antenna on a kept flight
% and none on a skipped one; the detector blocks of B4 and B4s select the same way.
p = base_params(); p.active_threat = 'airframe_shadowing'; p.shadow_db = 25; p.cap_frames = 20;
bd = shadow_roll_band(25, p); verifyEqual(tc, bd(1), 32.0, 'AbsTol', 0.01);
vsh = [shadow_speed_floor(bd, p), p.speed_kmh_max]; s = numel(p.EbNo_dB); eb = p.EbNo_dB(s);
fd = @(v) v / 3.6 * p.carrier_freq / p.c_light;
w = arrayfun(@(k) abs(heading_rate(k, fd(vsh(1)), p)), 1:2000);       % the heading rates drawn there stay within the measured one
verifyLessThanOrEqual(tc, max(w), p.yaw_rate_max);
bk = bank_angle(p.yaw_rate_max, fd(vsh(1)), p);                        % its turn: the smallest bank whose equivalent roll is the band's lowest,
verifyEqual(tc, bk, bd(1) - p.shadow_el_deg, 'AbsTol', 1e-9);          % the GCS on the horizon
verifyEqual(tc, shadow_equiv_roll(0, 0, bk, 0, p.shadow_el_deg), bd(1), 'AbsTol', 1e-9);
verifyEqual(tc, vsh(1), 39.2, 'AbsTol', 0.1);
[B, E] = ndgrid(linspace(0.5 * bk, bk - 1e-6, 30), [0 1 3 8 20]);
verifyFalse(tc, any(shadow_equiv_roll(0, E(:), B(:), 0, p.shadow_el_deg) >= bd(1)));   % no smaller bank reaches the band
verifyEqual(tc, shadow_speed_floor([16.1 57.9], p), 3.6 * p.shadow_v_min);   % below 8 m/s none (shadow_hidden.m)
keep = @(sd, v, a, k, o, c) hides_antenna(sd, v, p, struct('ebno', eb, 'alt_m', a, 'k_sig_db', k, 'aoa1_deg', o, 'rho', c));
sel = struct('seed', @(j, v) shadow_pool_seed(4, s, 1, j, v), 'keep', keep, 'j0', 0, 'jmax', 99999);
[g, info] = pool_geometries(s, 1, 9:16, vsh, p, [], 1, sel);           % a train split's own, at 15 dB
verifyEqual(tc, sum(info.tries), info.j);
verifyEqual(tc, g.run, 100 + (9:16));
h = false(1, info.j); sd = zeros(1, info.j);
for j = 1:info.j
    [sd(j), v] = shadow_pool_seed(4, s, 1, j, vsh);
    h(j) = keep(sd(j), v, NaN, NaN, NaN, NaN);
end
verifyEqual(tc, sd(h), g.seed);                                        % kept: exactly the candidates that hide one
verifyEqual(tc, find(h), cumsum(info.tries));
verifyTrue(tc, all(g.speed >= vsh(1) & g.speed <= vsh(2)));
for i = 1:numel(g.seed)
    d = flight_draws(g.seed(i), g.speed(i) / 3.6 * p.carrier_freq / p.c_light, p, struct('ebno', eb));
    verifyTrue(tc, any(d.hidden > 0));
    e = shadow_equiv_roll(0, d.el_deg, d.bank, d.pitch, p.shadow_el_deg);
    verifyTrue(tc, e >= 32 - 1e-9 && e <= 57.9 + 1e-9);                 % 25 dB: equivalent rolls 32.0-57.9 deg
end
verifyLessThan(tc, numel(g.seed) / info.j, 0.5);
sel.j0 = info.j;                                                        % the next flights continue the candidates
[g2, info2] = pool_geometries(s, 1, 17:20, vsh, p, [], 1, sel);
verifyEmpty(tc, intersect(g2.seed, g.seed)); verifyGreaterThan(tc, info2.j, info.j);
% a Latin hypercube of 12 selected flights: one per stratum of every axis, the speed strata
% over the speeds at which the level can be flown at the flight's altitude (from its floor
% there, shadow_alt_floor.m, up), which at 15 dB Eb/N0 rises above the group's floor; where
% it does not (6 dB at 0 dB Eb/N0) the same design as without the floor
lhs = 7100000 + 100 * s + 10 * (4 + 1) + 3; n = 12; ha = p.alt_range_m;
sel = struct('seed', @(j, v) shadow_pool_seed(4, s, 14, j, v), 'keep', keep, 'j0', 0, 'jmax', 99999, ...
    'floor', @(a) shadow_alt_floor(a, eb, p));
[gl, il] = pool_geometries(s, 14, 12 + (1:12), vsh, p, lhs, 1, sel);
vf = max(vsh(1), shadow_alt_floor(gl.alt, eb, p));
verifyGreaterThan(tc, max(vf), vsh(1) + 10);
verifyEqual(tc, sort(floor(n * (gl.speed - vf) ./ (vsh(2) - vf))), 0:n-1);
verifyEqual(tc, sort(floor(n * (gl.alt - ha(1)) / diff(ha))), 0:n-1);
verifyEqual(tc, sort(floor(n * (gl.ksig - p.k_range_db(1)) / diff(p.k_range_db))), 0:n-1);
verifyEqual(tc, sort(floor(n * (gl.rho - p.corr_range(1)) / diff(p.corr_range))), 0:n-1);
verifyTrue(tc, all(arrayfun(@(i) keep(gl.seed(i), gl.speed(i), gl.alt(i), gl.ksig(i), gl.aoa1(i), gl.rho(i)), 1:n)));
verifyEqual(tc, pool_geometries(s, 14, 12 + (1:12), vsh, p, lhs, 1, sel), gl);   % reproducible
verifyEqual(tc, sum(il.tries), il.j);
se = sel; se.j0 = il.j;                                                % the check pools' count: the next candidates, unstratified
[ge, ie] = pool_geometries(s, 14, 12 + (1:12), vsh, p, [], 1, se);
verifyEqual(tc, sum(ie.tries), ie.j - il.j);
verifyTrue(tc, all(isnan(ge.alt)) && all(ge.speed >= vsh(1) & ge.speed <= vsh(2)));
sel.floor = @(a) Inf; sel.jmax = 50;                                    % no speed reaches it: no shadowing flight claimed
verifyError(tc, @() pool_geometries(s, 14, 12 + (1:12), vsh, p, lhs, 1, sel), ?MException);
q6 = p; q6.shadow_db = 6; v6 = [shadow_speed_floor(shadow_roll_band(6, q6), q6), q6.speed_kmh_max];
k6 = @(sd, v, a, k, o, c) hides_antenna(sd, v, q6, struct('ebno', q6.EbNo_dB(1), 'alt_m', a, 'k_sig_db', k, 'aoa1_deg', o, 'rho', c));
s6 = struct('seed', @(j, v) shadow_pool_seed(1, 1, 14, j, v), 'keep', k6, 'j0', 0, 'jmax', 99999);
g6 = pool_geometries(1, 14, 1:12, v6, q6, 7100103, 1, s6);
s6.floor = @(a) shadow_alt_floor(a, q6.EbNo_dB(1), q6);
verifyEqual(tc, pool_geometries(1, 14, 1:12, v6, q6, 7100103, 1, s6), g6);
for f = {'build_policy_pools', 'build_check_pools'}
    verifyNotEmpty(tc, strfind(fileread(which(f{1})), '''floor'', @(a) shadow_alt_floor(a, eb, ps)'), f{1});
end
src = fileread(which('build_policy_pools'));
verifyNotEmpty(tc, strfind(src, '[~, ie] = pool_geometries(s, b, 1:N_COUNT, vshd(gi, :), p0, [], 1, sel);'));
verifyNotEmpty(tc, strfind(src, 'SH.count(gi, :, s) = [sum(ie.tries), N_COUNT];'));
src = fileread(which('build_check_pools'));
verifyNotEmpty(tc, strfind(src, '[~, ie] = pool_geometries(s, BLOCK, gpos{k}, vshd(k, :), p0, [], FAM, se);'));
verifyNotEmpty(tc, strfind(src, 'SH.count(k, :, s) = [sum(ie.tries), N_GEO];'));
% the model: the shadowing is on the air on a kept flight, never on a skipped one
p.quiet_build = true; mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(p)');
set_link_snr(mdl, eb + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
j0 = find(~h, 1);
[s0, v0] = shadow_pool_seed(4, s, 1, j0, vsh);
on = zeros(1, 2);
for k = 1:2
    if k == 1, [sk, vk] = deal(g.seed(1), g.speed(1)); else, [sk, vk] = deal(s0, v0); end
    link_seed(mdl, sk, vk / 3.6 * p.carrier_freq / p.c_light, struct('ebno', eb));
    F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(19 * p.frame_duration)), p, 20);
    on(k) = sum(F.act(1:F.nf) > 0);
end
close_system(mdl, 0);
verifyGreaterThan(tc, on(1), 0); verifyEqual(tc, on(2), 0);
% B4 and B4s: the next candidate of their own range that hides an antenna
q = p; q.shadow_db = 8;
[sb, vb, jb, nb] = hiding_flight(q, 9, 4550000, 0, 49999);
verifyEqual(tc, sb, 4550000 + jb); verifyEqual(tc, nb, jb);
verifyTrue(tc, hides_antenna(sb, vb, q, struct('ebno', 9, 'alt_m', NaN, 'k_sig_db', NaN)));
vk = @(k) q.speed_kmh_min + rand(seed_stream(4550000 + k, 'speed')) * (q.speed_kmh_max - q.speed_kmh_min);
verifyFalse(tc, any(arrayfun(@(k) hides_antenna(4550000 + k, vk(k), q, struct('ebno', 9, 'alt_m', NaN, 'k_sig_db', NaN)), ...
    1:jb - 1)));
[sb2, ~, jb2] = hiding_flight(q, 9, 4550000, jb, 49999);
verifyGreaterThan(tc, jb2, jb); verifyNotEqual(tc, sb2, sb);
for f = {'eval_unseen_snr', 'eval_unseen_severity'}
    verifyNotEmpty(tc, strfind(fileread(which(f{1})), 'if strcmp(cfg.name, ''airframe_shadowing'')'), f{1});
end
end

function test_cell_geometries(tc)
% Every episode runs its cell on a geometry the cell flies (PP.cell_geo, link_env.m K.geo):
% a cell with flights of its own (airframe shadowing) is drawn on them only, with the clean
% link of the same flight before the onset and as its restoration reference; the clean
% link's statistics read its own flights only, never the shadowing reference.
[PP, ~] = toy_world(true);
PP.runs = {[101 102 103]};
for k = find(~cellfun(@isempty, PP.pools(:)))'
    [c, ~, ~] = ind2sub(size(PP.pools), k);
    Q = PP.pools{k}; rr = [101 102 103]; if c == 2, rr = [102 103]; end
    f = fieldnames(Q); X = Q;
    for i = 1:numel(f), X.(f{i}) = repmat(Q.(f{i}), numel(rr), 1); end
    X.run = reshape(repmat(rr, 20, 1), [], 1);
    PP.pools{k} = X;
end
PP.cell_geo = {{1}, {[2 3]}}; PP.ref_geo = {[2 3]};
K = link_env('tables', PP, 'flight');
verifyEqual(tc, K.geo, {1; [2 3]});
verifyTrue(tc, all(isfinite(K.q(2, :, :, 1, 2:3)), 'all'));             % the jammer's flights have their clean reference
verifyTrue(tc, all(isnan(K.q(2, :, :, 1, 1)), 'all'));
spec = struct('scn', repmat([1 2], 1, 20), 's', ones(1, 40), 'onset', 3 * ones(1, 40), 'follow', false(1, 40), ...
    'fdelay', 2 * ones(1, 40), 'unk', false(1, 40), 'T', 5);
E = link_env('reset', PP, K, spec, 1, RandStream('mt19937ar', 'Seed', 3));
verifyTrue(tc, all(E.r(1:2:end) == 1) && all(ismember(E.r(2:2:end), [2 3])));
verifyEqual(tc, numel(unique(E.r(2:2:end))), 2);
[c, s, r] = flight_triples([1 2], K.geo(1:2, 1), 1:2);
verifyEqual(tc, [c; s; r], [1 1 2 2 2 2; 1 2 1 2 1 2; 1 1 2 2 3 3]);
[c, s, r] = flight_triples([1 2], 1:3, 1:2);                           % one list for every cell: ndgrid's order
[c0, s0, r0] = ndgrid([1 2], 1:2, 1:3);
verifyEqual(tc, [c; s; r], [c0(:)'; s0(:)'; r0(:)']);
specs = policy_episodes([1 2], 2, K.geo(1:2, 1), 1, false, false, 4, 5, RandStream('mt19937ar', 'Seed', 4));
x = cell2mat(cellfun(@(q) [q.scn; q.r], specs, 'UniformOutput', false));
verifyTrue(tc, all(x(2, x(1, :) == 1) == 1) && all(ismember(x(2, x(1, :) == 2), [2 3])));
verifyEqual(tc, policy_episodes([1 2], 2, 1:3, 1, false, false, 4, 5, RandStream('mt19937ar', 'Seed', 4)), ...
    policy_episodes([1 2], 2, {1:3, 1:3}, 1, false, false, 4, 5, RandStream('mt19937ar', 'Seed', 4)));
% the clean link's own flights in its statistics: the pools' clean reference, the drop
% threshold, the edge map's FA and LINK, the check points
verifyNotEmpty(tc, strfind(fileread(which('build_policy_pools')), 'own = @(Q, sp) ismember(Q.run, runs{sp}(cells(ic).geo{sp}));'));
verifyNotEmpty(tc, strfind(fileread(which('build_check_pools')), 'own = @(Q) ismember(Q.run, runs(1:N_GEO));'));
verifyNotEmpty(tc, strfind(fileread(which('choose_drop_threshold')), 'RR = PP.cell_geo{icl}{TR};'));
src = fileread(which('edge_map'));
verifyNotEmpty(tc, strfind(src, 'CF = take_rows(FT, FT.c == clean_cell & ismember(FT.sp, SPL) & ~FT.ref);'));
verifyNotEmpty(tc, strfind(src, 'CS = take_rows(FT, FT.c == clean_cell & FT.sp == SPEED & ~FT.ref);'));
verifyNotEmpty(tc, strfind(src, 'Fc = take_rows(KF, KF.c == k0 & KF.s == s & ~KF.ref);'));
for f = {'evaluate_policies', 'experiment_combo_generalization', 'experiment_unknown_threat', 'train_dqn'}
    verifyEmpty(tc, regexp(fileread(which(f{1})), '1:K\.nR\(|1:nG,|K\.nR\(TEST\), REPS', 'once'), f{1});
end
% the statement beside every shadowing reading
SH = struct('band', [16.1 57.9], 'level', 15.5, 'cell_levels', {{[15.5 20]}}, 'cell_group', [0 1 1], 'v_kmh', [28.8 161], ...
    'speed_range', [0 161], 'tried', cat(3, [40 0 50 0 100], [20 0 25 0 60]), 'kept', cat(3, [8 0 12 0 60], [8 0 12 0 60]));
[txt, share, env] = shadow_note(SH, [3 5], [3 12]);
verifyEqual(tc, share, [72 / 150, 72 / 85], 'AbsTol', 1e-12);
verifyEqual(tc, env, share * (161 - 28.8) / 161, 'AbsTol', 1e-12);
verifyNotEmpty(tc, strfind(txt, 'conditioned on such a geometry'));
verifyNotEmpty(tc, strfind(txt, '15.5/20 dB'));
verifyEmpty(tc, shadow_note(struct(), 1, 3));
SH.count = cat(3, [200 30], [300 30]);                                 % the share from the unstratified count, whatever the splits read
[txt, share, env] = shadow_note(SH, [3 5], [3 12]);
verifyEqual(tc, share, [30 / 200, 30 / 300], 'AbsTol', 1e-12);
verifyEqual(tc, env, share * (161 - 28.8) / 161, 'AbsTol', 1e-12);
verifyNotEmpty(tc, strfind(txt, 'shadow_alt_floor.m'));
end

%% ---------- D85 obs: the idle time, the window cues, the per-cycle labels ----------
function test_idle_record_bit_identical(tc)
% Recording a gated schedule's on-shares in the idle time changes no draw: with and without
% the recording (p.idle_rssi_hz 0) the same flight gives the same frames, bit for bit; the
% record holds the idle time before every frame but the first.
p = base_params(); p.quiet_build = true; p.cap_frames = 20;
for thr = {'benign_interference', 'benign_interference+noise_burst'}
    q = p; q.active_threat = thr{1}; q.benign_int_db = 10; q.jsr_db = 8; q.seed = 21;
    q0 = q; q0.idle_rssi_hz = 0;
    F0 = idle_run(q0, 4920001); F1 = idle_run(q, 4920001);
    verifyEqual(tc, F1.iq, F0.iq); verifyEqual(tc, F1.act, F0.act); verifyEqual(tc, F1.act_comp, F0.act_comp, 'AbsTol', 0);
    verifyTrue(tc, all(isnan(F0.idle), 'all'));                         % no idle sensing: no record
    verifyTrue(tc, all(isnan(F1.idle(:, 1))) && all(isfinite(F1.idle(1, 2:end))));
    verifyEqual(tc, size(F1.idle, 1), numel(idle_summary('names')));
    nc = numel(strsplit(thr{1}, '+'));
    verifyTrue(tc, all(isfinite(F1.idle_on(1:nc, :, 2:end)), 'all') && all(F1.idle_on(1:nc, :, 2:end) >= 0, 'all'));
end
close_system('UAV_GCS_Threat_Link', 0);
end

function test_idle_rssi_quiet_slot(tc)
% The idle-time model reads the threat block's own schedule, levels and channels: its last
% bin, 4.5 us before the frame's quiet slot, gives the slot's own interference over thermal
% (q_iot, 128 samples per antenna) frame by frame; a faulty connector holds the emitter the
% fault's depth down on its antenna, from the idle time after its onset frame (the block's
% own draw); a reactive jammer is silent there.
p = base_params(); p.quiet_build = true; p.cap_frames = 20;
cs = {'jamming', 'jsr_db', 16, 0.8; 'benign_interference', 'benign_int_db', 12, 1.0; 'tone_jamming', 'tone_jsr_db', 12, 0.5; ...
    'jamming+antenna_fault', 'jsr_db', 16, 1.0};
for c = 1:size(cs, 1)
    q = p; q.active_threat = cs{c, 1}; q.(cs{c, 2}) = cs{c, 3}; q.fault_atten_db = 18; q.seed = 31;
    F = idle_run(q, 4920100 + c);
    [R, ~, info] = idle_rssi(q, F.idle_ctx, double(F.idle_on), 1:F.nf, struct('meas', false));
    last = squeeze(10*log10(mean(10.^((R(end, :, :) + reshape(F.idle_ctx.cal, 1, [])) / 10), 2)));
    d = last(2:end) - F.q_iot(2:end)';
    verifyLessThan(tc, median(abs(d)), cs{c, 4}, cs{c, 1});
    if contains(cs{c, 1}, 'antenna_fault')
        m = squeeze(mean(R(:, :, 2:end), [1 3]));
        verifyLessThan(tc, m(info.hit) - median(m(setdiff(1:numel(m), info.hit))), -10);
    end
end
q = p; q.active_threat = 'jamming+antenna_fault'; q.jsr_db = 16; q.fault_atten_db = 18; q.seed = 33;
q.fault_onset_frames = [6 9];
F = idle_run(q, 4920112);
[R, ~, info] = idle_rssi(q, F.idle_ctx, double(F.idle_on), 1:F.nf, struct('meas', false));
verifyEqual(tc, info.af_on, find(F.act_comp(2, :) > 0, 1));          % the block's onset frame
m = squeeze(mean(R, 1)); dh = m(info.hit, :) - median(m(setdiff(1:size(m, 1), info.hit), :), 1);
verifyGreaterThan(tc, min(dh(2:info.af_on)), -6);                     % before the connector opens
verifyLessThan(tc, max(dh(info.af_on + 1:end)), -10);                 % after it
q = p; q.active_threat = 'reactive_jamming'; q.jsr_db = 20; q.seed = 32;
F = idle_run(q, 4920111);
verifyLessThan(tc, max(F.idle(strcmp(idle_summary('names'), 'lvl'), 2:end)), 3);   % the floor only
verifyEqual(tc, F.act_idle(2:end), zeros(1, F.nf - 1));
close_system('UAV_GCS_Threat_Link', 0);
end

function test_idle_emitter_attenuation(tc)
% An emitter in the idle time reaches the antenna behind a faulty connector the fault's
% depth down (the connector attenuates everything its antenna receives). The airframe hides
% it as it hides the GCS (emitter_idle.m: its direction drawn over the full circle, at the
% elevation of the farthest emitter that reaches the INR, emitter_elevation.m): in a right
% bank an emitter on the left reaches the antennas alike, one on the right more than 30 deg
% off the nose is hidden from the far end of the array by the level's depth.
p = base_params(); nr = p.n_rx;
ctx = struct('seed', seed_base(4920200), 'fd', 300, 'lev', 1, 'aoa', [10 -20 30], 'kfac', [10 10], 'yaw', 0, ...
    'rho', 0.5, 'att', zeros(1, 10), 'gate', [0.02 0 0 0.5], 'tdl', [ones(1, 4); zeros(18, 4)], 'cap', 1, 'cal', zeros(1, nr));
NB = floor((round(p.cycle_s * p.symbol_rate * p.sps) - p.samples_per_frame - 18) / (p.symbol_rate * p.sps / p.idle_rssi_hz));
amb = 100 * thermal_nv(p) * ones(NB, nr, 3);
q = p; q.active_threat = 'antenna_fault'; q.fault_atten_db = 18;
[R, ~, info] = idle_rssi(q, ctx, [], 1:3, struct('meas', false, 'ambient', amb));
m = 10 * log10(squeeze(mean(10 .^ (R(:, :, 2:3) / 10) - 1, [1 3])));   % the emitter over the floor
o = setdiff(1:nr, info.hit);
verifyEqual(tc, m(info.hit) - mean(m(o)), -18, 'AbsTol', 0.6);           % the chains' 0.1 dB spread aside
q = p; q.active_threat = 'airframe_shadowing'; q.shadow_db = 15.5;
R = idle_rssi(q, ctx, [], 1:3, struct('meas', false, 'ambient', amb));
m = squeeze(mean(R(:, :, 2:3), [1 3]));
verifyLessThan(tc, max(m) - min(m), 0.6);                               % the field emitter_idle.m hands it, as given
% the emitter's elevation: free space at the density cap to each INR, the flight's altitude
q.alt_random = true; h = flight_altitude(4920201, q);
dk = 10 .^ ((10 + 10*log10(1.25) + 2 + 174 - 10*log10(1.25e6) - 5 - q.amb_inr_db - 20*log10(2400) - 32.44) / 20);
verifyEqual(tc, dk, [11.16 3.53 1.117], 'AbsTol', 0.01);                % [km]
verifyEqual(tc, emitter_elevation(4920201, q, q.amb_inr_db), asind((h - q.gcs_h_m) ./ (1000 * dk)), 'AbsTol', 1e-9);
q.alt_random = false;
verifyEqual(tc, emitter_elevation(4920201, q, q.amb_inr_db), [0 0 0]);  % no altitude: on the horizon
% a held 30 deg right bank at 72 km/h, the emitter on the horizon at the INR of 20 dB
cx = ctx; cx.fd = 160; cx.att = [0 2 30 0 0 0 0 0 0 0]; cx.yaw = rad2deg(9.81 * tand(30) / 20);
F = struct('idle_ctx', cx, 'idle_on', []);
be = @(sd) -180 + 360 * [0 0 1] * rand(seed_stream(sd, 'amb'), 3, 1);
seen = [0 0];
for sd = 4920300 + (1:400)
    b = be(sd);
    hid = (b > -50 && b < -5) || (b > 5 && b < 40);
    if ~(hid || (b > 120 && b < 240)) || seen(1 + hid) >= 2, continue; end
    Z = emitter_idle(F, q, sd, 1:11);
    pa = Z(2:end, 10 + (1:nr)); busy = Z(2:end, 15) > 0;
    if nnz(busy) < 3, continue; end
    g = 10 * log10(mean(10 .^ (pa(busy, :) / 10), 1));
    if hid
        k = nr * (b > 0) + (b < 0);                                     % the far end of the array from the emitter
        verifyLessThan(tc, g(k) - median(g(setdiff(1:nr, k))), -7, sprintf('%.0f deg', b));
    else
        verifyLessThan(tc, max(g) - min(g), 6, sprintf('%.0f deg', b));
    end
    seen(1 + hid) = seen(1 + hid) + 1;
    if all(seen >= 2), break; end
end
verifyEqual(tc, seen, [2 2]);
end

function test_idle_summary_and_cues(tc)
% The record of an idle time and the window's idle cues: a quiet channel shows nothing; a
% continuous jammer occupies it all; a sweep returns with one dwell length (5.25 ms); WLAN
% packets of 0.27-3.2 ms spread their lengths.
p = base_params(); nr = p.n_rx; NB = 357; n = 12; tb = 1e3 / p.idle_rssi_hz;
nm = window_cues('names'); col = @(s) find(strcmp(nm, s));
rs = RandStream('mt19937ar', 'Seed', 3);
quiet = zeros(NB, nr, n); jam = 20 * ones(NB, nr, n);
sw = zeros(NB, nr, n); wl = zeros(NB, nr, n);
for j = 1:n
    if mod(j, 2) == 0, a = 60 + mod(17 * j, 100); sw(a:a + 96, :, j) = 15; end   % a 97-bin (5.25 ms) dwell every other cycle
    k = 3;
    while k < NB - 60
        L = randi(rs, [5 59]); wl(k:k + L - 1, :, j) = 15; k = k + L + randi(rs, [3 40]);
    end
end
recs = {quiet, jam, sw, wl}; X = zeros(4, numel(nm));
for i = 1:4
    S = idle_summary(recs{i}, p);
    verifyEqual(tc, size(S), [n numel(idle_summary('names'))]);
    X(i, :) = window_cues(zeros(1, nr, n), zeros(1, 23, n), permute(S, [3 2 1]));
end
verifyEqual(tc, X(1, col('w_occ')), 0); verifyEqual(tc, X(2, col('w_occ')), 1);
verifyLessThan(tc, X(3, col('w_bl_cv')), 0.05);
verifyEqual(tc, X(3, col('w_bl_mean')), 97 * tb, 'AbsTol', 1e-9);
verifyGreaterThan(tc, X(4, col('w_bl_cv')), 0.3);
verifyGreaterThan(tc, X(4, col('w_rate')), 5 * X(3, col('w_rate')));
Xn = window_cues(zeros(1, nr, n), zeros(1, 23, n), nan(1, numel(idle_summary('names')), n));   % no idle record
verifyEqual(tc, Xn(col('i_occ'):end), zeros(1, numel(nm) - col('i_occ') + 1));
end

function test_window_cues_branch_and_step(tc)
% A lost branch's cause in its fading: a faulty connector keeps the link's K on its branch,
% a shadowed antenna loses its line of sight (Sun et al.: K about -16 dB); a step of our
% received level inside the window is found with its size and age. (The cue over 60 cycles:
% the moment K of 12 Rayleigh samples alone scatters by several dB.)
rs = RandStream('mt19937ar', 'Seed', 5); n = 12; m60 = 60; nr = 3;
ric = @(K, m) 10 * log10(abs(sqrt(K / (K + 1)) + sqrt(1 / (K + 1)) * (randn(rs, 1, m) + 1j * randn(rs, 1, m)) / sqrt(2)).^2);
nm = window_cues('names'); col = @(s) find(strcmp(nm, s));
G = zeros(2, nr, m60);
for a = 2:nr, G(:, a, :) = reshape([ric(30, m60); ric(30, m60)], 2, 1, m60); end
G(1, 1, :) = reshape(ric(30, m60) - 15, 1, 1, m60);                     % fault: the link's K, 15 dB down
G(2, 1, :) = reshape(ric(10^(-1.6), m60) - 15, 1, 1, m60);              % shadowing: K -16 dB
X = window_cues(G, zeros(2, 23, m60), []);
verifyLessThan(tc, X(2, col('k_contrast')), X(1, col('k_contrast')) - 10);
verifyGreaterThan(tc, X(2, col('sd_contrast')), X(1, col('sd_contrast')) + 2);
Gs = repmat(reshape(0.3 * randn(rs, nr, n), 1, nr, n), 2, 1, 1);
Gs(1, :, 7:end) = Gs(1, :, 7:end) - 8;                                  % our level 8 dB down from cycle 7
X = window_cues(Gs, zeros(2, 23, n), []);
verifyGreaterThan(tc, X(1, col('stp_t')), 10); verifyLessThan(tc, X(2, col('stp_t')), 4);
verifyEqual(tc, X(1, col('stp_db')), 8, 'AbsTol', 0.5); verifyEqual(tc, X(1, col('stp_age')), 6);
verifyFalse(tc, any(strcmp(nm, 'idx_mid')));                            % the antenna's place in the array is not read
end

function test_window_cues_branch_coherence(tc)
% Branch coherence (branch_record.m records, window_cues.m): a faulty connector scales its
% antenna's whole field, so the branch's normalised correlation with the others and its
% line-of-sight share across delay stay the link's; a hidden antenna keeps only its diffuse
% part (K -16 dB, Sun et al.), correlated with the others by the receive correlation only.
% The columns do not change when the weak branch is scaled; the record's cycles start at
% the weakest antenna's step; no record gives zeros.
rs = RandStream('mt19937ar', 'Seed', 9); nr = 3; nb = window_cues('branch_window');
nm = window_cues('names'); col = @(s) find(strcmp(nm, s));
verifyEqual(tc, numel(nm), 52); verifyEqual(tc, nb, 10);
verifyEqual(tc, numel(branch_record('names', nr)), 9 * nr);
K = 10; rho = 0.5; ks = 10^(-1.6); L = chol(rho .^ abs((1:nr)' - (1:nr)), 'lower');
psi = 2 * pi * rand(rs, nr, 1);
    function B = rec(kw, gw, on)
        % nb cycles of branch records; antenna 1 has K kw and amplitude gw from cycle on
        B = zeros(1, 9 * nr, nb);
        for f = 1:nb
            kv = K * ones(nr, 1); g = ones(nr, 1);
            if f >= on, kv(1) = kw; g(1) = gw; end
            kap = kv ./ (1 + kv); d = L * (randn(rs, nr, 1) + 1j * randn(rs, nr, 1)) / sqrt(2);
            h = g .* (sqrt(kap) .* exp(1j * (psi + 2 * pi * rand(rs))) + sqrt(1 - kap) .* d);
            dl = g .* sqrt(1 - kap) .* (randn(rs, nr, 1) + 1j * randn(rs, nr, 1)) / sqrt(2) * 0.5;   % later lags: diffuse only
            B(1, :, f) = [10 * log10(abs(h).^2 + abs(dl).^2); real(h); imag(h); 1e-9 * ones(nr, 1); real(h); imag(h); ...
                1e-9 * ones(nr, 1); abs(h).^2; abs(dl).^2]';
        end
    end
Gz = zeros(1, nr, 3); Fz = zeros(1, 23, 3);
Xf = zeros(40, 52); Xs = Xf;
for t = 1:40
    Xf(t, :) = window_cues(Gz, Fz, [], rec(K, 10^(-20/20), 1));    % fault: the link's K, 20 dB down
    Xs(t, :) = window_cues(Gz, Fz, [], rec(ks, 10^(-15/20), 1));   % shadowing: K -16 dB, 15 dB down
end
verifyGreaterThan(tc, mean(Xf(:, col('coh_contrast'))), mean(Xs(:, col('coh_contrast'))) + 0.3);
verifyGreaterThan(tc, mean(Xf(:, col('coh_weak')) > Xs(:, col('coh_weak'))), 0.8);
verifyGreaterThan(tc, mean(Xf(:, col('los_contrast'))), mean(Xs(:, col('los_contrast'))) + 5);
B = rec(K, 1, 1); sc = @(B, db) scale1(B, db, nr);                   % the weak branch's field scaled
x0 = window_cues(Gz, Fz, [], sc(B, 25)); x1 = window_cues(Gz, Fz, [], sc(B, 40));
c = col('coh_weak'); verifyEqual(tc, x1(c:c + 9), x0(c:c + 9), 'AbsTol', 1e-6);
Bt = rec(K, 10^(-20/20), 5);                                              % the fault from cycle 5
xt = window_cues(Gz, Fz, [], Bt);
verifyEqual(tc, xt(col('coh_cycles')), 0.6, 'AbsTol', 1e-12);
x = window_cues(Gz, Fz, [], []); verifyEqual(tc, x(end - 9:end), zeros(1, 10));
x = window_cues(Gz, Fz, [], nan(1, 9 * nr, nb)); verifyEqual(tc, x(end - 9:end), zeros(1, 10));
end

function B = scale1(B, db, nr)
% Antenna 1's record with its field scaled by -db dB (amplitudes, powers, gain).
a = 10^(-db / 20); B(1, 1, :) = B(1, 1, :) - db;
B(1, 1 + [1 2 4 5] * nr, :) = B(1, 1 + [1 2 4 5] * nr, :) * a;
B(1, 1 + [3 6 7 8] * nr, :) = B(1, 1 + [3 6 7 8] * nr, :) * a^2;
end

function test_fusion_monitor_branch_columns(tc)
% The closed loop's fusion (policy_monitor.m) builds the same row as fuse_classes.m's
% windows, the branch-coherence columns over the last window_cues('branch_window') cycles
% included: equal fused probabilities at every cycle of a run.
rs = RandStream('mt19937ar', 'Seed', 4); n = 14; nr = 3; Nf = 3;
cls = {'none', 'antenna_fault', 'airframe_shadowing'}; A = policy_actions(); na = find(strcmp(A, 'no_action'));
nF = numel(link_features('names')); nI = numel(idle_summary('names'));
P = rand(rs, n, 3); P = P ./ sum(P, 2); Fr = randn(rs, n, nF); I = rand(rs, n, nI); I(1, :) = NaN;
B = randn(rs, n, 9 * nr); nv = [3 * nr + (1:nr), 6 * nr + (1:nr)]; B(:, nv) = 0.01 * abs(B(:, nv));
B(:, 1:nr) = 3 * randn(rs, n, nr); pw = 7 * nr + (1:2 * nr); B(:, pw) = abs(B(:, pw)) + 0.1;
nZ = numel(temporal_evidence('names', 3)) + numel(window_cues('names')) + 3;
FM = struct('W', 0.1 * randn(rs, nZ + 1, 3), 'mu', zeros(1, nZ), 'sd', ones(1, nZ), 'C', 3, 'lambda', 0);
S = struct('run', ones(n, 1), 'pos', (1:n)', 'gain_ant', zeros(n, nr), 'feats_raw', Fr, 'feat_names', {link_features('names')}, ...
    'idle', I, 'bch', B);
pc = fuse_classes('apply', FM, fuse_classes('windows', S, P, Nf));
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'fuse', FM, 'fuse_N', Nf);
m = policy_monitor('init', 1, numel(A));
for k = 1:n
    obs = struct('probs', P(k, :), 'unknown', false, 'feat', Fr(k, :), 'cfg_link', na, 'gant', zeros(1, nr), ...
        'idle', I(k, :), 'bch', B(k, :));
    [m, M] = policy_monitor('update', m, obs, PP, na); m = policy_monitor('change', m, false);
    verifyEqual(tc, M.probs, pc(k, :), 'AbsTol', 1e-10);
end
verifyGreaterThan(tc, max(abs(fuse_classes('windows', S, P, Nf) - fuse_classes('windows', rmfield(S, 'bch'), P, Nf)), [], 'all'), 0);
end

function test_threat_active_cycle(tc)
% Per decision cycle (idle sensing): a gated threat counts while it is on the air anywhere in
% the cycle, the idle time before the frame or the frame; the first frame keeps its own share;
% the other threats keep their rule; without the idle share the frame rule (10%).
verifyEqual(tc, threat_active('benign_interference', [0 0.05 0 0.5 0], [], [], [0 0 0.2 NaN NaN]), ...
    logical([0 1 1 1 0]));
verifyEqual(tc, threat_active('benign_interference', [0 0.05 0 0.5 0]), logical([0 0 0 1 0]));
verifyEqual(tc, threat_active('sweeping_jammer', [0 0 0.02], [], [], [0 0.01 0]), logical([0 1 1]));
verifyEqual(tc, threat_active('jamming', [1 1], [], [], [0 0]), logical([1 1]));
verifyEqual(tc, threat_active('path_loss', [0 1 1 1], 1:4, 3, [0 0 0 0]), logical([0 1 1 0]));
p = base_params();
h = sweep_hit_share(p);                                              % a 25.25 ms reach over 20-83.5 ms periods
T = linspace(p.sweep_period_s(1), p.sweep_period_s(end), 1001);
verifyEqual(tc, h, mean(min(1, (diff(sweep_window_s(p)) + p.cycle_s) ./ T)), 'AbsTol', 1e-12);
verifyGreaterThan(tc, h, 0.5); verifyLessThan(tc, h, 0.7);
verifyGreaterThan(tc, benign_hit_share(p, 500), 0.8);
q = p; q.idle_rssi_hz = 0;
verifyLessThan(tc, benign_hit_share(q, 500), 0.65);                 % the frame rule without idle sensing
end

function test_monitor_idle_window(tc)
% The decision cycle builds the fusion's row as fuse_classes.m does, the idle time's records
% included: the same fused probabilities frame by frame.
rng(8);
C = 2; nr = 3; N = 6; nF = 20; nRun = 30; fn = link_features('names'); nI = numel(idle_summary('names'));
n = nRun * nF; run = repelem((1:nRun)', nF); pos = repmat((1:nF)', nRun, 1);
y = 1 + (rand(n, 1) < 0.3); probs = [1 - 0.3 * y, 0.3 * y]; probs = probs ./ sum(probs, 2);
I = rand(n, nI) .* (1 + (y == 2)); I(pos == 1, :) = NaN; I(:, end - 1) = 19; I(:, end) = 20;
S = struct('run', run, 'pos', pos, 'gain_ant', randn(n, nr), 'feats_raw', randn(n, numel(fn)), 'feat_names', {fn}, 'idle', I);
Z = fuse_classes('windows', S, probs, N);
verifyEqual(tc, size(Z, 2), numel(temporal_evidence('names', C)) + numel(window_cues('names')) + C);
FM = fuse_classes('fit', Z, y, C, 1e-3);
PP = struct('actions', {policy_actions()}, 'classes', {{'none', 'benign_interference'}}, 'sps', 4, 'bps', 2, ...
    'maha_thr', -Inf, 'fuse', FM, 'fuse_N', N);
mem = policy_monitor('init', 1, numel(PP.actions));
r1 = find(run == 3);
for j = 1:nF
    f = r1(j);
    obs = struct('probs', probs(f, :), 'unknown', false, 'feat', S.feats_raw(f, :), 'gant', S.gain_ant(f, :), 'idle', I(f, :));
    [mem, M] = policy_monitor('update', mem, obs, PP, 1);
    verifyEqual(tc, M.probs, fuse_classes('apply', FM, Z(f, :)), 'AbsTol', 1e-9);
end
end

function F = idle_run(q, seed)
% One 20-frame run of the threat link at 9 dB with the idle time measured.
mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(q)');
link_seed(mdl, seed, 100 / 3.6 * q.carrier_freq / q.c_light, struct('ebno', 9, 'alt_m', NaN, 'k_sig_db', NaN));
set_link_snr(mdl, 9 + 10*log10(q.bits_per_symbol) - 10*log10(q.sps), q);
F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(20 * q.frame_duration)), q, 20);
end

%% ---------- the onset of a lost branch ----------
function test_roll_in_attitude(tc)
% A flight that holds its bank turns at its heading rate; one that rolls in flies level,
% rolls at its rate up to the bank, and its heading follows the roll as a coordinated turn
% (yaw tan(roll) / tan(bank)).
att = [12 3 25 1 0 0 0];
[b, r, dp] = turn_attitude(att, 10, [0 0.37 1.2]);
verifyEqual(tc, b, 12 + 10 * [0 0.37 1.2]); verifyEqual(tc, r, 25 * ones(1, 3)); verifyEqual(tc, dp, 10 * [0 0.37 1.2]);
verifyEqual(tc, turn_attitude([att 0 0 0], 10, 0.37), 12 + 10 * 0.37);   % rate 0: no roll-in
att = [12 3 -30 0 0 0 0 0.1 25 0];
t = (0:1e-4:3)';
[b, r, dp] = turn_attitude(att, -15, t);
verifyEqual(tc, r(t <= 0.1), zeros(sum(t <= 0.1), 1));
verifyEqual(tc, r(t >= 0.1 + 30 / 25 + 1e-9), -30 * ones(sum(t >= 0.1 + 30 / 25 + 1e-9), 1));
k = t > 0.1 & t < 1.3;
verifyEqual(tc, r(k), -25 * (t(k) - 0.1), 'AbsTol', 1e-9);
hn = cumtrapz(t, -15 * tand(abs(r)) / tand(30));                 % the coordinated turn's heading
verifyEqual(tc, dp, hn, 'AbsTol', 1e-4);
verifyEqual(tc, b - 12, dp, 'AbsTol', 1e-12);
[b0, r0] = turn_attitude([12 3 -30 0 0 0 0 -0.5 25 0], -15, 0);  % started before the run: rolled 12.5 deg at t = 0
verifyEqual(tc, [b0 r0], [12 -12.5], 'AbsTol', 1e-12);
end

function test_roll_rate_sources(tc)
% The rate of a roll-in lies between the measured roll-in of a small UAV (Allen & Lin, 30 deg
% in about 1.6 s) and the largest rate measured over a window as long as the roll-in
% (Gross et al.: 45.4 deg/s over 0.5 s, 35.5 deg/s over 1 s; linear in between).
p = base_params();
verifyEqual(tc, p.roll_rate_lo, 30 / 1.6, 'AbsTol', 1e-12);
verifyEqual(tc, p.roll_rate_win, [0.5 45.4; 1 35.5]);
verifyEqual(tc, roll_rate(0, 40, p), 30 / 1.6, 'AbsTol', 1e-12);
verifyEqual(tc, roll_rate(1, 20, p), 45.4, 'AbsTol', 1e-12);       % 20 deg within 0.5 s
verifyEqual(tc, roll_rate(1, 40, p), 35.5, 'AbsTol', 1e-12);       % 40 deg in more than 1 s
for b = 23:0.5:35
    w = roll_rate(1, b, p); T = b / w;
    verifyEqual(tc, w, 45.4 - (45.4 - 35.5) * (T - 0.5) / 0.5, 'AbsTol', 1e-9);
end
w = arrayfun(@(u) roll_rate(u, 30, p), linspace(0, 1, 50));
verifyTrue(tc, all(w >= 30 / 1.6 - 1e-12 & w <= roll_rate(1, 30, p) + 1e-12));
end

function test_shadow_onset_ramp(tc)
% Airframe shadowing ramps in as the bank rolls in: shadow_frame.m is shadow_hidden.m in a
% held bank (the whole depth with the GCS abeam, the share of its burial off the beam);
% during a roll-in the share of the depth rises from 0 where the airframe enters the line of
% sight to 1 at the bank by Sun et al.'s shape, (3x - x^3) / 2.
% flight_draws.m places the dataset's onset (the loss reaching 5 dB) at the drawn frame and
% the pools' event (the airframe's entry) just before frame 11, the clean link of the same
% flight on the same timeline.
B = [16.1 57.9]; vm = 8;
for be = [0 40 -40 70]
    for r = [10 20 -20]
        [k, g] = shadow_frame(be, 2, r, abs(r), 0, 3, B, 30, 20, vm, 2.9);
        verifyEqual(tc, k, shadow_hidden(be, 2, r, 0, 3, B, 30, 20, vm, 2.9));
        [~, dl] = shadow_equiv_roll(be, 2, abs(r), 0, 2.9); x = dl / (abs(r) - 2);   % the burial against its deepest, abeam
        if k > 0, verifyEqual(tc, g, (3 * x - x^3) / 2, 'AbsTol', 1e-9); end
        if k > 0 && be == 0, verifyEqual(tc, g, 1, 'AbsTol', 1e-12); end
    end
end
r = 2.5:0.5:30;                                                  % the GCS abeam, 2 deg below: the event from a 2 deg roll
[k, g] = shadow_frame(zeros(size(r)), 2, r, 30, 0, 3, B, 30, 20, vm, 2.9);
x = (r - 2) / 28;                                                % abeam the equivalent roll is the roll plus 0.9 deg
verifyEqual(tc, k, 3 * ones(size(r)));
verifyEqual(tc, g, (3 * x - x .^ 3) / 2, 'AbsTol', 1e-6);
[~, g2] = shadow_frame(0, 2, 16, [30 10], 0, 3, B, 30, 20, vm, 2.9);  % an event that started at a 10 deg roll
verifyEqual(tc, g2, (3 * 0.3 - 0.3^3) / 2, 'AbsTol', 1e-9);
verifyEqual(tc, shadow_frame(0, 2, 20, 10, 0, 3, B, 30, 20, vm, 2.9), 0);   % a bank the level is not flown at
p = base_params();
q = p; q.active_threat = 'airframe_shadowing'; q.shadow_db = 15.5; q.roll_in_frames = [2 11]; q.cap_frames = 20;
n = 0; f0 = []; fr = [];
for s = 1:300
    v = 30 + 130 * mod(s * 0.618, 1);
    d = flight_draws(7000000 + s, v / 3.6 * q.carrier_freq / q.c_light, q, struct('ebno', 9));
    if ~any(d.hidden > 0), continue; end
    n = n + 1;
    verifyEqual(tc, find(d.hidden > 0, 1), d.onset_frame);
    if d.onset_frame > 1, verifyLessThan(tc, q.shadow_db * d.shadow_g(d.onset_frame - 1), q.shadow_evt_db); end
    f0(end+1) = d.onset_frame; fr(end+1) = d.roll_in(2); %#ok<AGROW>
end
verifyGreaterThan(tc, n, 20);
verifyTrue(tc, all(f0 >= 2 & f0 <= 11)); verifyGreaterThan(tc, numel(unique(f0)), 5);
verifyTrue(tc, all(fr >= q.roll_rate_lo - 1e-9 & fr <= 45.4 + 1e-9));
q.roll_in_frames = [];
d = flight_draws(7000003, 1000, q, struct('ebno', 9));
verifyEqual(tc, d.roll_in, [0 0 0]); verifyTrue(tc, isnan(d.onset_frame));   % a held bank as before
q2 = p; q2.active_threat = 'none';
m = 0; geo = struct('ebno', 9, 'event_frame', 11, 'frames', 38);
for s = 1:300
    fd = (60 + 100 * mod(s * 0.618, 1)) / 3.6 * q.carrier_freq / q.c_light;
    ds = flight_draws(7100000 + s, fd, q, geo);
    if ~any(ds.hidden > 0), continue; end
    m = m + 1;
    dc = flight_draws(7100000 + s, fd, q2, geo);
    verifyEqual(tc, [dc.roll_in dc.gcs_aoa], [ds.roll_in ds.gcs_aoa]);
    verifyEqual(tc, ds.shadow_g(1:10), zeros(1, 10));
    verifyGreaterThan(tc, ds.shadow_g(11), 0); verifyLessThan(tc, ds.shadow_g(11), 0.5);
end
verifyGreaterThan(tc, m, 20);
q.roll_in_frames = [2 11];
verifyEqual(tc, flight_draws(7000003, 40, q, struct('ebno', 9)).hidden, zeros(1, 20));   % 5 m/s: no event
q.yaw_random = false; q.gcs_aoa_random = false; [~, q.roll_deg] = shadow_roll_band(q.shadow_db, q);
verifyEqual(tc, flight_draws(7, 100, q).hidden, zeros(1, 20));   % an onset asked of a fixed view: none placed
end

function test_onsets_in_the_model(tc)
% In the model an antenna fault opens within one frame at its onset (no threat before it),
% drawn per run over a range; airframe shadowing ramps in on the flight's roll-in: its frames
% count from the frame flight_draws.m places and the hidden antenna's loss deepens after it.
p = base_params(); p.quiet_build = true; p.cal_random = false;
mdl = 'UAV_GCS_Threat_Link';
q = p; q.active_threat = 'antenna_fault'; q.fault_atten_db = 18; q.fault_onset_frames = [7 7];
evalc('build_threat_model(q)');
set_link_snr(mdl, 12 + 10*log10(q.bits_per_symbol) - 10*log10(q.sps), q);
link_seed(mdl, 3000501, 160, struct('ebno', 12));
F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(14 * q.frame_duration)), q, 20);
v = 1:14;
verifyEqual(tc, F.act(v), double(v >= 7));
G = F.gain_ant(:, v); [~, h] = min(mean(G(:, 8:end), 2));
off = G(h, :) - median(G(setdiff(1:q.n_rx, h), :), 1);
verifyEqual(tc, median(off(1:6)) - median(off(7:end)), 18, 'AbsTol', 4);   % a step of the level
verifyLessThan(tc, off(7), median(off(1:6)) - 10);                         % on the onset frame itself
q.fault_onset_frames = [2 11];
evalc('build_threat_model(q)');
on = zeros(1, 6);
for s = 1:6
    link_seed(mdl, 50 + s, 160);
    F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(12 * q.frame_duration)), q, 20);
    on(s) = find(F.act > 0, 1);
end
verifyTrue(tc, all(on >= 2 & on <= 11)); verifyGreaterThan(tc, numel(unique(on)), 1);
verifyNotEmpty(tc, strfind(fileread(which('build_threat_model')), 'if fo2 > fo1'));   % no draw at the pools' [1 1]
q = p; q.active_threat = 'airframe_shadowing'; q.shadow_db = 20; q.roll_in_frames = [6 6]; q.cap_frames = 20;
evalc('build_threat_model(q)');
set_link_snr(mdl, 12 + 10*log10(q.bits_per_symbol) - 10*log10(q.sps), q);
found = 0;
for s = 1:200
    geo = struct('ebno', 12, 'alt_m', NaN, 'k_sig_db', NaN);
    if ~hides_antenna(3000000 + s, 100, q, geo), continue; end
    d = link_seed(mdl, 3000000 + s, 100 / 3.6 * q.carrier_freq / q.c_light, geo);
    F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(20 * q.frame_duration)), q, 20);
    v = 1:20;
    verifyEqual(tc, F.act(v) > 0, d.hidden(v) > 0);
    verifyEqual(tc, find(F.act > 0, 1), 6);
    G = F.gain_ant(:, v); h = d.hidden(6);
    off = G(h, :) - median(G(setdiff(1:q.n_rx, h), :), 1);
    verifyLessThan(tc, mean(off(16:20)), mean(off(1:5)) - 3);          % the loss has deepened
    found = found + 1;
    if found == 2, break; end
end
verifyEqual(tc, found, 2);
close_system(mdl, 0);
end

function test_onset_shape(tc)
% The shape of a lost branch's onset from the per-antenna gains: a step against a ramp; no
% fall, no statistic; the latched cause, the two classes' probability handed to it while the
% branch stays lost, its reset once the branch has recovered for heal cycles.
rng(11);
n = 16; G = 0.3 * randn(n, 3);
Gs = G; Gs(9:end, 2) = Gs(9:end, 2) - 15;                            % a step at cycle 9
Gr = G; Gr(:, 2) = Gr(:, 2) - 15 * min(1, max(0, ((1:n)' - 5) / 10));   % a ramp over 10 cycles from cycle 6
[xs, Fs] = onset_shape(permute(Gs, [3 2 1])); [xr, Fr] = onset_shape(permute(Gr, [3 2 1]));
verifyEqual(tc, [Fs.ant Fs.tau Fs.R], [2 9 1]); verifyEqual(tc, xs(1), 1); verifyLessThan(tc, xs(2), 2);
verifyEqual(tc, Fr.ant, 2); verifyEqual(tc, Fr.R, 10, 'AbsTol', 1); verifyGreaterThan(tc, xr(2), 2); verifyLessThan(tc, xr(1), 0.2);
verifyEqual(tc, onset_shape(permute(G, [3 2 1])), [0 0]);             % no fall
verifyEqual(tc, onset_shape(permute(Gs(1:3, :), [3 2 1])), [0 0]);     % too short a window
verifyEqual(tc, onset_shape('names'), {'os_rate', 'os_glr'});
nm = temporal_evidence('names', 2); nF = numel(link_features('names'));
x = temporal_evidence(repmat([0.5 0.5], 1, 1, n), permute(Gr, [3 2 1]), zeros(1, nF, n));
verifyEqual(tc, x(ismember(nm, {'os_rate', 'os_glr'})), xr, 'AbsTol', 1e-12);
cls = {'none', 'antenna_fault', 'airframe_shadowing'};
L = 0.3 * randn(30, 3); Ls = L; Ls(10:24, 2) = Ls(10:24, 2) - 15;     % a fault from cycle 10, back at 25
[pl, cause] = onset_shape('sequence', Ls, repmat([0.1 0.4 0.5], 30, 1), cls, 5);   % the fusion leans to shadowing
verifyEqual(tc, cause(1:10)', zeros(1, 10));
k = find(cause > 0, 1); verifyLessThanOrEqual(tc, k, 15);
verifyEqual(tc, unique(cause(k:24))', 1);
verifyEqual(tc, pl(k:24, :), repmat([0.1 0.9 0], 24 - k + 1, 1), 'AbsTol', 1e-12);
verifyEqual(tc, cause(end), 0);                                       % reset after 5 healthy cycles
Lr = L; Lr(:, 2) = Lr(:, 2) - 15 * min(1, max(0, ((1:30)' - 5) / 12));
[pl, cause] = onset_shape('sequence', Lr, repmat([0.1 0.5 0.4], 30, 1), cls, 5);
verifyEqual(tc, cause(end), 2);
verifyEqual(tc, pl(end, :), [0.1 0 0.9], 'AbsTol', 1e-12);
pn = repmat([0.8 0.1 0.1], 30, 1);
verifyEqual(tc, onset_shape('sequence', Lr, pn, cls, 5), pn);         % a fused 'none' stays
st = []; c1 = zeros(30, 1);
for t = 1:30, [st, ~, c1(t)] = onset_shape('latch', st, Lr(t, :), [0.1 0.5 0.4], cls, 5); end
verifyEqual(tc, c1, cause);                                           % one cycle at a time: the same
% the threshold: the statistic at the diagnosis, chosen on validation, 0 without a choice
verifyLessThan(tc, onset_shape('events', Ls), 0); verifyGreaterThan(tc, onset_shape('events', Lr), 0);
verifyTrue(tc, isnan(onset_shape('events', L)));                       % no event
verifyEqual(tc, onset_shape('choose', [-5 -3 -2 1 2 4], [1 1 1 2 2 2]), 0);
verifyEqual(tc, onset_shape('choose', [-6 -4 -3 -2 -1 3], [1 1 1 2 2 2]), -2.25);
verifyEqual(tc, onset_shape('choose', [-6 -4], [1 1]), 0);              % one cause only
verifyEqual(tc, [onset_shape('threshold', struct('os_thr', -1.5)), onset_shape('threshold', [])], [-1.5 0]);
[~, c3] = onset_shape('sequence', Lr, repmat([0.1 0.5 0.4], 30, 1), cls, 5, 1e3);   % above every ramp: a step
verifyEqual(tc, c3(end), 1);
verifyNotEmpty(tc, strfind(fileread(which('select_fusion')), 'FM.os_thr = onset_shape(''choose'', og, oy);'));
end

function test_monitor_onset_latch(tc)
% The monitor keeps the cause read from the onset of a lost branch while it stays lost (one
% block calling onset_shape.m): an open connector reads antenna_fault once its onset is read,
% though the fused class leans to airframe shadowing.
A = policy_actions(); nF = numel(link_features('names'));
PP = struct('actions', {A}, 'classes', {{'none', 'antenna_fault', 'airframe_shadowing'}}, 'maha_thr', -Inf, ...
    'sps', 4, 'bps', 2);
mem = policy_monitor('init', 1, numel(A));
rng(2); G = 0.3 * randn(30, 3); G(10:end, 2) = G(10:end, 2) - 18;
cl = cell(1, 30);
for t = 1:30
    obs = struct('probs', [0.1 0.4 0.5], 'unknown', false, 'feat', zeros(1, nF), 'gant', G(t, :), 'maha', 0);
    obs.feat(feature_index('log_ber')) = -6;
    [mem, M] = policy_monitor('update', mem, obs, PP, find(strcmp(A, 'no_action')));
    cl{t} = M.cls{1};
end
verifyEqual(tc, cl(1:9), repmat({'airframe_shadowing'}, 1, 9));
verifyEqual(tc, unique(cl(15:30)), {'antenna_fault'});
verifyEqual(tc, numel(strfind(fileread(which('policy_monitor')), 'onset_shape(''latch''')), 1);
end

function test_event_frame_pools(tc)
% A rolling-in flight of the pools: the episode's onset reads the run's frame where the
% airframe enters the line of sight (PP.event_frame), the cycles before it the same flight's
% clean link before the event, beyond the run's end its last 10 frames; its per-flight tables
% read the run from that frame on (event_rows.m).
A = policy_actions(); nA = numel(A); fn = link_features('names');
n = 38; E0 = 11;
PP = struct('actions', {A}, 'scen', {{'none', 'airframe_shadowing'}}, 'ebno', 9, 'runs', {{101}}, 'F_SUB', 20, ...
    'event_frame', {{E0}}, 'classes', {{'none', 'airframe_shadowing'}}, 'feat_names', {fn}, 'maha_thr', 0, ...
    'clean', 1e-6, 'clean_fer', 0, 'gp', ones(1, nA), 'bw', ones(1, nA), 'pw', ones(1, nA), 'sps', 4, 'bps', 2);
PP.pools = cell(2, 1, nA, 1);
for sc = 1:2
    F = zeros(n, numel(fn)); F(:, 1) = (1:n)' + 100 * sc;            % which frame of which cell was read
    b = zeros(n, 1); if sc == 2, b(1:E0 - 1) = 0.1; end             % only the frames before the event are bad
    for a = 1:nA
        PP.pools{sc, 1, a, 1} = struct('ber', b, 'fer', single(b > 0), 'run', 101 * ones(n, 1), ...
            'probs', repmat([sc == 1, sc == 2], n, 1), 'maha', ones(n, 1), 'feat', F, 'act', double((1:n)' >= E0) * (sc == 2));
    end
end
K = link_env('tables', PP);
verifyTrue(tc, K.healthy(2, 1, 1, 1));                               % the event's frames alone
verifyTrue(tc, K.on(2, 1, 1, 1));
verifyEqual(tc, event_rows(PP.pools{2, 1, 1, 1}, 101, E0)', (1:n) >= E0);
for on = [3 10]
    spec = struct('scn', 2, 's', 1, 'onset', on, 'follow', false, 'fdelay', 2, 'unk', false, 'T', 40, 'r', 1);
    [E, obs] = link_env('reset', PP, K, spec, 1, RandStream('mt19937ar', 'Seed', 1));
    rd = obs.feat(1);
    for t = 1:39
        [E, ~, obs] = link_env('step', E, PP, K, find(strcmp(A, 'no_action')));
        rd(end+1) = obs.feat(1); %#ok<AGROW>
    end
    verifyEqual(tc, rd(1:on), 100 + (E0 - on:E0 - 1));                 % the same flight before the event
    verifyEqual(tc, rd(on + 1), 200 + E0);                            % the onset reads the event's frame
    q = (0:39) + E0 - 1 - on; q(q >= n) = n - 10 + mod(q(q >= n) - n, 10);
    verifyEqual(tc, rd(on + 1:end), 200 + q(on + 1:end) + 1);
end
end

function test_det_frames_onset(tc)
% DET of an antenna fault is read after the same flight's clean link (the connector's step
% between them); age counts the cycles since the threat's first frame on the air; the
% monitor's class takes the cause latched from the onset (onset_shape.m), the fused class
% alone does not.
cls = {'none', 'antenna_fault', 'airframe_shadowing'}; nf = numel(link_features('names'));
ok = [strcmp(cls, 'antenna_fault'); ismember(cls, {'antenna_fault', 'airframe_shadowing'})];
rng(1); Gc = 0.3 * randn(10, 3); Gf = 0.3 * randn(10, 3); Gf(:, 2) = Gf(:, 2) - 18;
mk = @(pr, G, act) struct('probs', repmat(pr, 10, 1), 'run', 101 * ones(10, 1), 'gant', G, 'feat', zeros(10, nf), ...
    'ber', zeros(10, 1), 'act', act * ones(10, 1));
PP = struct('classes', {cls}, 'fuse', [], 'fuse_N', 4, 'sps', 2, 'bps', 2);
[hit, on, hit_f, age] = det_frames(mk([0.1 0.4 0.5], Gf, 1), mk([1 0 0], Gc, 0), 'antenna_fault', ok, PP);
verifyEqual(tc, age', 0:9); verifyTrue(tc, all(on));
verifyFalse(tc, any(hit_f(:, 1)));                                    % the fused class leans to shadowing
verifyTrue(tc, all(hit(5:end, 1)));                                   % the cause latched from the step
verifyTrue(tc, all(hit(:, 2) & hit_f(:, 2)));                         % the branch level either way
[~, ~, ~, age] = det_frames(mk([0.1 0.4 0.5], Gf, 1), [], 'airframe_shadowing', ok, PP);
verifyEqual(tc, age', 0:9);
end

function test_onset_recipes(tc)
% The dataset, the second test set, B4 and B4s fly the fault's and the shadowing's onsets
% inside their sub-runs as path loss does (frames before them clean), and those cells fly
% N_SUB F_SUB over the mean frames from an onset; the pools roll the shadowing flights in.
txt = fileread(which('run_dataset_sweep'));
verifyNotEmpty(tc, strfind(txt, 'p.fault_onset_frames = p0.pl_onset_det;'));
verifyNotEmpty(tc, strfind(txt, 'p0.roll_in_frames = p0.pl_onset_det;'));
verifyNotEmpty(tc, strfind(txt, 'round(N_SUB * F_SUB / on_frames)'));
for f = {'eval_unseen_snr', 'eval_unseen_severity'}
    s = fileread(which(f{1}));
    verifyNotEmpty(tc, strfind(s, 'p0.fault_onset_frames = p0.pl_onset_det;'), f{1});
    verifyNotEmpty(tc, strfind(s, 'p0.roll_in_frames = p0.pl_onset_det;'), f{1});
end
p = base_params();
verifyEqual(tc, p.fault_onset_frames, [1 1]); verifyEmpty(tc, p.roll_in_frames); verifyEqual(tc, p.shadow_evt_db, 5);
verifyEqual(tc, threat_active('antenna_fault', [0 0 1 1 1], 1:5, 10), logical([0 0 1 1 1]));
verifyEqual(tc, threat_active('airframe_shadowing', [0 1 1 0 1], 1:5, 10), logical([0 1 1 0 1]));
verifyEqual(tc, fusion_target([1 1 2 2 2], ones(1, 5), 1:5, 4, {'none', 'antenna_fault', 'path_loss'})', [1 1 2 2 2]);
C = decision_config();
verifyEqual(tc, [C.event_frame C.event_run C.event_count], [11 38 30]);
verifyEqual(tc, C.event_run, C.event_frame - 3 + 30);                % the latest onset's lead-in, the earliest's 27 cycles
src = fileread(which('build_policy_pools'));
verifyNotEmpty(tc, strfind(src, '''event_frame'', C.event_frame, ''frames'', C.event_count'));
verifyNotEmpty(tc, strfind(src, 'g(sp).frames(ref{sp}) = C.event_run; g(sp).event(ref{sp}) = C.event_frame;'));
verifyNotEmpty(tc, strfind(fileread(which('build_check_pools')), '''event_frame'', C.event_frame, ''frames'', C.event_count'));
end

%% ---------- the dataset's align, the predicted MMSE gain, the unknown-threat threshold ----------
function test_dataset_align_fields(tc)
% A5 keeps the flight draw of the interferer's alignment (align_gcs) apart from the
% receiver's measured align, and stops before saving when a field does not hold one entry
% per frame; A6 and B1 check the same on what they read.
txt = fileread(which('run_dataset_sweep'));
i0 = strfind(txt, 'MEAS = {'); i1 = strfind(txt, 'D = struct('); i2 = strfind(txt, 'dup = intersect');
meas = regexp(txt(i0:i1 - 1), '''(\w+)''', 'tokens'); meas = [meas{:}];
dfl = regexp(txt(i1:i2 - 1), '''(\w+)''', 'tokens'); dfl = [dfl{:}];
verifyEmpty(tc, intersect(meas, dfl));
verifyTrue(tc, ismember('align', meas) && ismember('align_gcs', dfl) && ~ismember('align', dfl));
verifyNotEmpty(tc, strfind(txt, 'D.align_gcs = [D.align_gcs, d.align(1) * o];'));
verifyEmpty(tc, regexp(txt, 'D\.align = ', 'once'));
verifyNotEmpty(tc, strfind(txt, 'dataset.align_gcs = D.align_gcs(:);'));
verifyNotEmpty(tc, strfind(txt, 'assert_frames(D, numel(D.label), ''run_dataset_sweep'', {}, 2);'));
verifyNotEmpty(tc, strfind(fileread(which('extract_spectrograms')), 'assert_frames(ds.meas, numel(ds.run)'));
verifyEqual(tc, numel(strfind(fileread(which('prepare_data')), 'assert_frames(sp0, numel(sp0.run)')), 2);
% the guard: columns (A5's rows of frames), rows, cell vectors, the last dimension of an
% array; structs and named fields skipped
S = struct('a', 1:4, 'b', ones(2, 4), 'c', {{1, 2, 3, 4}}, 'x', zeros(2, 2, 4), 'm', struct('q', 1));
assert_frames(S, 4, 'test', {}, 2);
S.a = 1:8;
verifyError(tc, @() assert_frames(S, 4, 'test', {}, 2), 'assert_frames:count');
assert_frames(struct('a', (1:4)', 'n', {{'u', 'v'}}), 4, 'test', {'n'});
end

function test_align_repair(tc)
% A dataset whose align holds the flight draw and the measurement of every sub-run (2N
% values: per sub-run the draw n times, then its n measurements) is split by
% repair_align.m into meas.align (the measurement) and align_gcs (the draw), the original
% kept; a dry run writes nothing; a second call changes nothing; a layout that does not
% hold stops it with the file untouched; the old layout fails A6's guard.
d = fullfile(tc.TestData.tmp, 'align_fix'); mkdir(fullfile(d, 'data'));
c0 = cd(d); back = onCleanup(@() cd(c0));
n = [5 3 7]; run = repelem([11; 12; 13], n); N = sum(n);
draw = [0.2 0.7 0.4]; rng(3); meas = rand(N, 1); A = []; k = 0;
for r = 1:3, A = [A; draw(r) * ones(n(r), 1); meas(k + (1:n(r)))]; k = k + n(r); end %#ok<AGROW>
dataset = struct('iq', {num2cell(rand(4, N), 1)}, 'run', run, 'label', ones(N, 1), 'align', A, ...
    'meas', struct('align', A, 'sinr', rand(N, 1)), 'meta', struct('fresh', false));
verifyError(tc, @() assert_frames(dataset.meas, N, 'A6'), 'assert_frames:count');
verifyError(tc, @() assert_frames(dataset, N, 'A6'), 'assert_frames:count');
D0 = dataset;
save('data/dataset.mat', 'dataset', '-v7.3');
R = repair_align('data/dataset.mat', true);
verifyEqual(tc, {R.state, R.n_frames, R.n_runs, R.runs_const, R.runs_vary}, {'checked', N, 3, 3, 3});
verifyEqual(tc, load('data/dataset.mat').dataset, D0);
R = repair_align('data/dataset.mat');
L = load('data/dataset.mat').dataset;
verifyEqual(tc, R.state, 'repaired');
verifyEqual(tc, L.meas.align, meas);
verifyEqual(tc, L.align_gcs, repelem(draw(:), n(:)));
verifyFalse(tc, isfield(L, 'align'));
verifyEqual(tc, {L.meas.sinr, L.run, L.iq}, {D0.meas.sinr, D0.run, D0.iq});
verifyEqual(tc, load('data/dataset_before_align_repair.mat').dataset, D0);
assert_frames(L.meas, N, 'A6'); assert_frames(L, N, 'A6');
verifyEqual(tc, repair_align('data/dataset.mat').state, 'already');
verifyEqual(tc, repair_align('data/dataset.mat', true).state, 'already');
% a draw that is not one value: stopped, nothing written
dataset = D0; dataset.meas.align(2) = 0.99; dataset.align = dataset.meas.align; B = dataset;
save('data/dataset_fresh.mat', 'dataset', '-v7.3');
verifyError(tc, @() repair_align('data/dataset_fresh.mat'), 'repair_align:layout');
verifyEqual(tc, load('data/dataset_fresh.mat').dataset, B);
verifyEmpty(tc, dir('data/dataset_fresh_*repair*'));
end

function test_mmse_predict_known_symbols(tc)
% The predicted MMSE gain over MRC (mmse_predict.m, F.mmse_pred) reads the frame's known
% symbols only: near 0 dB on the clean link (MMSE is MRC in white noise), also on the delay
% line over the pools' draws at the grid's top Eb/N0 (our own echoes add a little there),
% with few frames at the rule's threshold; and against a tone at 16 dB the
% optimum-combining gain of one directional interferer (about JMc(1 - c), Winters, Salz &
% Gitlin 1994), well above the rule's threshold, where the decision-directed mmse_gain of
% the MRC link stays low.
p = base_params(); p.quiet_build = true; p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false;
p.gcs_tracked = false; p.k_random = false; p.gcs_aoa_random = false; p.body_random = false; p.tdl = false;
p.rician_k = 10; p.int_rician_k = 10; p.rx_corr = 0.3; p.seed = 21; p.tone_jsr_db = 16;
mdl = 'UAV_GCS_Threat_Link'; C = decision_config();
G = struct();
for t = {'none', 'tone_jamming'}
    q = p; q.active_threat = t{1};
    evalc('build_threat_model(q)');
    set_link_snr(mdl, 6 + 10*log10(q.bits_per_symbol) - 10*log10(q.sps), q);
    g = []; dd = [];
    for r = 1:2
        link_seed(mdl, 2100 + r, 160);
        F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(9 * q.frame_duration)), q, 20);
        verifyEqual(tc, numel(F.mmse_pred), F.nf);
        g = [g, F.mmse_pred(2:end)]; dd = [dd, F.mmse_gain(2:end)]; %#ok<AGROW>
    end
    G.(t{1}) = [median(g), median(dd)];
end
q = p; q.active_threat = 'none'; q.tdl = true; q.tdl_random = true; q.k_random = true; q.corr_random = true;
evalc('build_threat_model(q)');
set_link_snr(mdl, 15 + 10*log10(q.bits_per_symbol) - 10*log10(q.sps), q);
g = [];
for r = 1:8
    link_seed(mdl, 2110 + r, 160);
    F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(9 * q.frame_duration)), q, 20);
    g = [g, F.mmse_pred(2:end)]; %#ok<AGROW>
end
close_system(mdl, 0);
verifyLessThan(tc, abs(G.none(1)), 1.5);
verifyLessThan(tc, abs(median(g)), 1.5);
verifyLessThanOrEqual(tc, mean(g >= C.rule_mmse_db), 0.05);
verifyGreaterThan(tc, G.tone_jamming(1), C.rule_mmse_db + 6);
verifyGreaterThan(tc, G.tone_jamming(1), G.tone_jamming(2) + 6);
end

function test_mmse_predict_search(tc)
% Where MMSE reads no SINR above 0 dB at the receiver's arrival and frequency, mmse_predict
% measures the frame where the MMSE receiver would acquire it: with the receiver's arrival
% 2 symbols off (a fractional arrival, Eb/N0 -3 dB), the arrival of the highest MMSE SINR
% of the window as each candidate measures on its own; with a 30 dB tone and the receiver's
% frequency 3 pilot alias steps off, our signal's frequency. One frame with the previous one
% as the filter's memory reads what the run reads (KPI 7 times that call).
p = base_params(); C = decision_config(); rng(7);
TM = round(p.timing_max_sym * p.sps); fp = p.symbol_rate / (p.pilot_block + p.pilot_every);
nf = 12; tau = 2 + 4 * rand(1, nf);
y = synth_frames(p, -3, tau, zeros(1, nf), -Inf);
sy = [round(tau) + 2 * p.sps; zeros(1, nf)];
[G, D] = mmse_predict(y, p, sy);
c = nan(TM + 1, nf);
for d = 0:TM
    [~, Dd] = mmse_predict(y, p, [d * ones(1, nf); zeros(1, nf)]);
    v = ~Dd.search; c(d + 1, v) = Dd.mmse_db(v);
end
verifyTrue(tc, all(D.search));
verifyLessThan(tc, abs(D.arrival - tau), 1);
verifyGreaterThan(tc, D.mmse_db, max(c, [], 1) - 0.3);
for k = 2:nf
    s2 = sy(:, k-1:k); s2(:, 1) = NaN;
    g2 = mmse_predict(y(:, :, k-1:k), p, s2);
    verifyTrue(tc, isnan(g2(1)));
    verifyEqual(tc, g2(2), G(k), 'AbsTol', 1e-9);
end
fo = 1e3 * (rand(1, nf) - 0.5);
y = synth_frames(p, 6, tau, fo, 30);
[G, D] = mmse_predict(y, p, [round(tau); fo - 3 * fp]);
verifyLessThan(tc, abs(fo - 3 * fp + D.df_hz - fo), fp / 4);
verifyLessThan(tc, abs(D.arrival - tau), 1);
verifyGreaterThan(tc, median(G), C.rule_mmse_db + 6);
end

function y = synth_frames(p, eb, tau, fo, jsr)
% Frames of our signal at arrival tau [samples, fractional] and frequency fo [Hz] on a
% Rician K 10 dB channel from 10 deg, every antenna's noise at Eb/N0 eb, and a tone jsr dB
% above our signal at 37 kHz from -40 deg (none: -Inf); samples x antennas x frames.
L = frame_layout(p); ns = L.air * p.sps; na = p.n_rx; nf = numel(tau);
h = rcosdesign(p.rolloff, p.filter_span, p.sps, 'sqrt');
t = (0:ns-1)' / (p.symbol_rate * p.sps); m = 2 * ns; k = (0:m-1)'; fr = (k - m * (k >= m / 2)) / m;
y = complex(zeros(ns, na, nf));
for f = 1:nf
    sym = L.tmpl; sym(L.idx_data) = exp(1j * pi / 4 * (2 * randi([0 3], L.n_data, 1) + 1));
    x = zeros(ns, 1); x(1:p.sps:end) = sym;
    x = ifft(fft(filter(h, 1, x), m) .* exp(-1j * 2*pi * fr * tau(f)));
    x = x(1:ns) .* exp(1j * 2*pi * fo(f) * t);
    a = sqrt(10/11) * exp(1j * (pi * (0:na-1) * sind(10) + 2*pi * rand)) + sqrt(1/22) * (randn(1, na) + 1j * randn(1, na));
    y(:, :, f) = x * a + sqrt(1 / 10^((eb + 3.01) / 10) / 2) * (randn(ns, na) + 1j * randn(ns, na));
    if isfinite(jsr)
        y(:, :, f) = y(:, :, f) + sqrt(10^(jsr / 10) / p.sps) * exp(1j * (2*pi * 37e3 * t + 2*pi * rand)) * ...
            exp(1j * pi * (0:na-1) * sind(-40));
    end
end
end

function test_latency_times_predictor(tc)
% KPI 7 times the predicted MMSE gain in the cycle: frame k on every antenna as the
% combiner sees it, frame k - 1 only the filter's memory; the observation reads its value.
src = fileread(which('measure_latency'));
verifyNotEmpty(tc, strfind(src, 't0 = tic; g = mmse_predict(x.iqa, p0, x.sy); t_pred = toc(t0);'));
verifyNotEmpty(tc, strfind(src, 'if k > 1, s2(:, 1) = NaN; end'));
verifyNotEmpty(tc, strfind(src, 'obs.mmse_pred = g(end);'));
verifyNotEmpty(tc, strfind(src, 'tm(n, :) = 1000 * [t_spec, t_feat, t_pred, t_det, t_dqn];'));
verifyNotEmpty(tc, strfind(src, '''dep'', sum(tm(1:n, 1:4), 2) + tp(1:n)'));
end

function test_policy_mmse_pred(tc)
% The rule nulls on the predicted MMSE gain of the frame's known symbols (obs.mmse_pred),
% not on the detector's decision-directed mmse_gain, at PP.rule_mmse_db when the pools set
% it (C.rule_mmse_db otherwise; no prediction: not separable); the agent's state reads the
% same value (0 dB without one); the pools carry it frame by frame to the observation.
A = policy_actions(); C = decision_config(); cls = {'none', 'jamming'};
na = find(strcmp(A, 'no_action'));
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', -Inf, 'confirm', [2 2], 'alarm_mode', 'class');
o = struct('probs', [0 1], 'unknown', false, 'feat', zeros(1, numel(link_features('names'))));
o.feat(feature_index('log_ber')) = -1; o.feat(feature_index('mmse_gain')) = 20;
x = o; x.mmse_pred = 0;
verifyEqual(tc, A{rule_cycles(x, PP, na)}, 'channel_switch');
x.mmse_pred = C.rule_mmse_db;
verifyEqual(tc, A{rule_cycles(x, PP, na)}, 'channel_switch+spatial_diversity');
P2 = PP; P2.rule_mmse_db = C.rule_mmse_db + 3;
verifyEqual(tc, A{rule_cycles(x, P2, na)}, 'channel_switch');
verifyEqual(tc, A{rule_cycles(o, PP, na)}, 'channel_switch');
verifyEqual(tc, rule_based_policy('jamming', false, 7, [], [], [], [], 8), 'channel_switch');
verifyEqual(tc, rule_based_policy('jamming', false, 8, [], [], [], [], 8), 'channel_switch+spatial_diversity');
verifyEqual(tc, rule_based_policy('jamming', false, NaN), 'channel_switch');
verifyEqual(tc, C.rule_mmse_db, 6);
mem = policy_monitor('init', 1, numel(A));
x.mmse_pred = 13.5; mem = policy_monitor('update', mem, x, PP, na);
verifyEqual(tc, mem.hist(numel(cls) + 9, 1, 1), 13.5);
mem = policy_monitor('update', mem, o, PP, na);
verifyEqual(tc, mem.hist(numel(cls) + 9, 1, 1), 0);
nA = numel(A); fn = link_features('names'); n = 20;
PL = struct('actions', {A}, 'scen', {{'none'}}, 'ebno', 9, 'runs', {{101}}, 'F_SUB', n, 'classes', {cls}, ...
    'feat_names', {fn}, 'maha_thr', 0, 'clean', 1e-6, 'clean_fer', 0, 'gp', ones(1, nA), 'bw', ones(1, nA), ...
    'pw', ones(1, nA), 'sps', 4, 'bps', 2);
PL.pools = cell(1, 1, nA, 1);
for a = 1:nA
    PL.pools{1, 1, a, 1} = struct('ber', zeros(n, 1), 'fer', zeros(n, 1, 'single'), 'run', 101 * ones(n, 1), ...
        'probs', repmat([1 0], n, 1), 'maha', ones(n, 1), 'feat', [(1:n)', zeros(n, numel(fn) - 1)], 'act', zeros(n, 1), ...
        'mmse_pred', single(100 + (1:n)'));
end
K = link_env('tables', PL);
spec = struct('scn', 1, 's', 1, 'onset', 3, 'follow', false, 'fdelay', 0, 'unk', false, 'T', 10, 'r', 1);
[E, ob] = link_env('reset', PL, K, spec, 1, RandStream('mt19937ar', 'Seed', 1));
verifyEqual(tc, ob.mmse_pred, 100 + ob.feat(1));
[~, ~, ob] = link_env('step', E, PL, K, na);
verifyEqual(tc, ob.mmse_pred, 100 + ob.feat(1));
src = fileread(which('pool_cell'));
verifyNotEmpty(tc, strfind(src, 'Q.mmse_pred = [Q.mmse_pred; single(F.mmse_pred(v)'')];'));
verifyNotEmpty(tc, strfind(fileread(which('rekey_pools')), '''bch'', ''mmse_pred''};   % pool_cell.m'));
end

function a = rule_cycles(o, PP, na)
% The rule's configuration after four cycles of the same observation from no_action.
mem = []; a = na;
for k = 1:4, [a, mem] = policy_decide('rule', o, a, mem, PP, []); end
end

%% ---------- the monitor, the drop alarm, the decision layer's settings and the KPI readings ----------
function test_a6_stamp_required(tc)
% B1 splits only spectrograms the guarded A6 built (spec.meta.frames_checked, written after
% its per-frame guards) and not older than their dataset; A6 names repair_align for a
% dataset of the layout from before align_gcs.
src = fileread(which('extract_spectrograms'));
verifyNotEmpty(tc, strfind(src, 'spec.meta.frames_checked = true;'));
src = fileread(which('prepare_data'));
verifyNotEmpty(tc, strfind(src, 'checked_a6(sp0, ''data/spectrograms.mat'', ''data/dataset.mat'');'));
verifyNotEmpty(tc, strfind(src, 'checked_a6(sp0, [''data/spectrograms_fresh'' sfx ''.mat''], [''data/dataset_fresh'' sfx ''.mat'']);'));
d = fullfile(tc.TestData.tmp, 'b1_stamp'); mkdir(fullfile(d, 'data'));
c0 = cd(d); back = onCleanup(@() cd(c0));
spec = struct('fold', [1; 5; 6], 'meta', struct('temporal_window', 10));      % built before the stamp
save('data/spectrograms.mat', 'spec', '-v7.3');
verifyError(tc, @() run_script('prepare_data'), 'prepare_data:stale');
spec.meta.frames_checked = true; save('data/spectrograms.mat', 'spec', '-v7.3');
dataset = struct('run', 1); save('data/dataset.mat', 'dataset');
java.io.File(fullfile(d, 'data', 'dataset.mat')).setLastModified(java.lang.System.currentTimeMillis() + 60e3);   % a newer dataset
verifyError(tc, @() run_script('prepare_data'), 'prepare_data:stale');
n = 4;
dataset = struct('iq', {num2cell(rand(2, n), 1)}, 'run', ones(n, 1), 'label', ones(n, 1), 'align', rand(2 * n, 1), ...
    'meas', struct('align', rand(2 * n, 1)), 'meta', struct());
save('data/dataset.mat', 'dataset', '-v7.3');
params = base_params(); save('params.mat', 'params');
verifyError(tc, @() run_script('extract_spectrograms'), 'extract_spectrograms:align');
end

function run_script(name)
% A pipeline script run in a function's workspace, as run_stage.m runs it.
run(name);
end

function test_kpi1_file(tc)
% KPI 1 is read on the third test set when its reading exists (measure_all_kpis.m), and the
% dashboard, the console, the GUI bundle and the weak points show the same set.
d = fullfile(tc.TestData.tmp, 'kpi1file'); mkdir(fullfile(d, 'results'));
c0 = cd(d); back = onCleanup(@() cd(c0));
verifyEqual(tc, kpi1_file('eval_detector_metrics'), 'results/eval_detector_metrics.mat');
x = 1; save('results/eval_detector_metrics_fresh2.mat', 'x');
verifyEqual(tc, kpi1_file('eval_detector_metrics'), 'results/eval_detector_metrics_fresh2.mat');
verifyEqual(tc, kpi1_file('detector_predictions'), 'results/detector_predictions.mat');
for f = {'measure_all_kpis', 'build_kpi_dashboard', 'demo_gui'}
    verifyNotEmpty(tc, strfind(fileread(which(f{1})), 'kpi1_file(''eval_detector_metrics'')'), f{1});
end
verifyNotEmpty(tc, strfind(fileread(which('analyze_weak_points')), 'kpi1_file(''detector_predictions'')'));
verifyNotEmpty(tc, strfind(fileread(which('export_gui_bundle')), '''results/eval_detector_metrics_fresh2.mat'''));
verifyNotEmpty(tc, strfind(fileread(which('build_kpi_dashboard')), 'set_txt(Md.metrics)'));
end

function test_decision_settings(tc)
% The settings train_dqn.m chose on validation reach every reader through
% decision_settings.m: the deployed DQN's (dec), or the monitor an agent saved before dec;
% an empty drop threshold keeps the pools'; the rule fallback's own through policy_decide's
% opt.monitor; the edge map's check flights, the console and the 3D view alike; the
% deployed policy's stamp follows them.
PP = struct('alarm_mode', 'class', 'confirm', [2 2], 'drop_db', 4, 'maha_thr', -1);
S = struct('alarm_mode', 'class_drop', 'confirm', [3 3], 'drop_db', [], 'maha_thr', -2, 'unk_mode', 'nonhostile', ...
    'rule_mmse_db', 7.5, 'rule_slot', false, 'rule_dwell', 'group', 'esc_drop', true, 'confirm_sweep', [2 6], 'unk_retain', 0.99);
X = decision_settings(PP, S);
verifyEqual(tc, {X.alarm_mode, X.confirm, X.drop_db, X.maha_thr, X.unk_mode, X.rule_mmse_db, X.rule_slot, X.rule_dwell, ...
    X.esc_drop, X.confirm_sweep, X.unk_retain}, {'class_drop', [3 3], 4, -2, 'nonhostile', 7.5, false, 'group', true, [2 6], 0.99});
Q = struct('confirm', [4 5], 'alarm_mode', 'class_cusum', 'drop_db', 36, 'maha_thr', -3);      % an agent saved before dec
X = decision_settings(PP, Q);
verifyEqual(tc, {X.confirm, X.alarm_mode, X.drop_db, X.maha_thr}, {[4 5], 'class_cusum', 36, -3});
Q.dec = S; X = decision_settings(PP, Q); verifyEqual(tc, {X.rule_mmse_db, X.drop_db}, {7.5, 4});
verifyEqual(tc, decision_settings(struct('confirm_sweep', [2 6]), struct('confirm_sweep', [])).confirm_sweep, []);
for f = {'evaluate_policies', 'experiment_unknown_threat', 'experiment_combo_generalization', 'measure_latency'}
    src = fileread(which(f{1}));
    verifyNotEmpty(tc, regexp(src, 'PPm? = decision_settings\(PPm?, Q\);', 'once'), f{1});
    verifyNotEmpty(tc, strfind(src, '''dec'''), f{1});
end
src = fileread(which('edge_map'));
verifyNotEmpty(tc, strfind(src, 'MON = Q; if strcmp(Q.deployed, ''rule_sel''), MON = Q.rule_sel; end'));
verifyNotEmpty(tc, strfind(src, 'PP = decision_settings(PP, MON);'));
verifyNotEmpty(tc, strfind(src, 'CK = decision_settings(CK, PP);'));
for f = {'demo_gui', 'v3d_engine'}
    src = fileread(which(f{1}));
    verifyNotEmpty(tc, regexp(src, 'decision_settings\((env\.)?PP, Q\)', 'once'), f{1});
    verifyNotEmpty(tc, strfind(src, '''maha_thr'', ''dec'''), f{1});
end
verifyNotEmpty(tc, strfind(fileread(which('demo_gui')), 'ui.thrSlider.Value = env.unk_retain;'));
verifyNotEmpty(tc, strfind(fileread(which('policy_decide')), 'PP = decision_settings(PP, opt.monitor);'));
Q = struct('deployed', 'dqn_esc', 'alarm_mode', 'class_drop', 'confirm', [2 2], 'drop_db', 4, 'det_id', 'x', 'maha_thr', -1, 'dec', S);
s1 = policy_stamp(Q); Q.dec.rule_mmse_db = 9;
verifyNotEqual(tc, policy_stamp(Q), s1);
end

function test_architecture_monitor_stated(tc)
% B3a states the deployed monitor (the fused class, or with the latched cause), labels the
% latch column not deployed when it is off, latches each validation fold at a threshold
% chosen on the other folds (out of fold, as select_fusion.m), and reads the fusion with its
% own further columns and target rule.
src = fileread(which('compare_architectures'));
verifyNotEmpty(tc, strfind(src, 'Deployed monitor: %s'));
verifyNotEmpty(tc, strfind(src, 'tf = fold_thresholds(sp.val, yv_cyc, cls_names, runs, fold_of_run);'));
verifyNotEmpty(tc, strfind(src, 'latch_runs(pc(m, :), va.run(m), va.pos(m), va.gain_ant(m, :), classes, tf(k));'));
verifyNotEmpty(tc, strfind(src, '''fused+latch (not deployed)'''));
verifyNotEmpty(tc, strfind(src, 'fusion_target(yv_cyc, sp.val.run, sp.val.pos, FZ.N, cls_names, FZ.FM)'));
verifyNotEmpty(tc, strfind(src, 'fuse_classes(''windows'', va, P, N, cues)'));
end

function test_window_cues_extra(tc)
% The fusion's further columns (window_cues.m 'extra'): each gap's crest and spread over its
% own floor p10 against thresholds from clean gaps (cfar), and the branch isolated by its own
% step (iso); a fusion without them keeps its row; the closed loop's monitor builds the same
% row as fuse_classes.m with them.
nm = idle_summary('names'); ci = @(s) find(strcmp(nm, s)); nF = numel(link_features('names'));
E = 2; n = 4; nr = 3; Iw = nan(E, numel(nm), n);
for e = 1:E
    for k = 1:n
        v = zeros(1, numel(nm)); v(ci('gap_ms')) = 10; v(ci('p10')) = 1; v(ci('p90')) = 1.5; v(ci('max')) = 2;
        if e == 2 && k >= 3, v(ci('max')) = 7; v(ci('p90')) = 4; end   % a weak emitter's crest over the gap's floor
        Iw(e, :, k) = v;
    end
end
opt = struct('cfar', [1.5 1 0.9], 'iso', false);
verifyEqual(tc, window_cues('extra', zeros(E, nr, n), zeros(E, nF, n), Iw, opt), [0 0 0.1 0; 0.5 0.5 2.6 1], 'AbsTol', 1e-12);
verifyEqual(tc, window_cues('extra_names', opt), {'cf_crest_hi', 'cf_spread_hi', 'cf_crest_ex', 'cf_crest_now'});
verifyEmpty(tc, window_cues('extra_names', []));
G = zeros(1, nr, 8); G(1, 2, 5:8) = -10; G(1, 3, :) = -12;           % antenna 2 steps down 10 dB; antenna 3 weakest by its mean
x = window_cues('extra', G, zeros(1, nF, 8), [], struct('iso', true, 'cfar', []));
verifyEqual(tc, x, [10 / 0.5 / sqrt(0.5), 10, 10 / 0.5 / sqrt(0.5), 0], 'AbsTol', 1e-9);
% the fusion's row with them, and the monitor's
rs = RandStream('mt19937ar', 'Seed', 5); n = 12; Nf = 4;
cls = {'none', 'antenna_fault', 'airframe_shadowing'}; A = policy_actions(); na = find(strcmp(A, 'no_action'));
P = rand(rs, n, 3); P = P ./ sum(P, 2); Fr = randn(rs, n, nF); I = 2 * rand(rs, n, numel(nm)); I(:, ci('gap_ms')) = 10; I(1, :) = NaN;
Gn = randn(rs, n, nr); Gn(7:end, 1) = Gn(7:end, 1) - 8;
S = struct('run', ones(n, 1), 'pos', (1:n)', 'gain_ant', Gn, 'feats_raw', Fr, 'feat_names', {link_features('names')}, 'idle', I);
cues = struct('cfar', [1 0.5 0.4], 'iso', true);
Zx = fuse_classes('windows', S, P, Nf, cues);
verifyEqual(tc, Zx, [fuse_classes('windows', S, P, Nf), fuse_classes('extra', S, Nf, cues)]);
verifyEqual(tc, fuse_classes('windows', S, P, Nf, fuse_classes('cues', struct('W', 1))), fuse_classes('windows', S, P, Nf));
nZ = size(Zx, 2);
FM = struct('W', 0.1 * randn(rs, nZ + 1, 3), 'mu', zeros(1, nZ), 'sd', ones(1, nZ), 'C', 3, 'lambda', 0, 'cues', cues);
verifyEqual(tc, fuse_classes('cues', FM), cues);
pc = fuse_classes('apply', FM, Zx);
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'fuse', FM, 'fuse_N', Nf);
m = policy_monitor('init', 1, numel(A));
for k = 1:n
    obs = struct('probs', P(k, :), 'unknown', false, 'feat', Fr(k, :), 'cfg_link', na, 'gant', Gn(k, :), 'idle', I(k, :));
    [m, M] = policy_monitor('update', m, obs, PP, na); m = policy_monitor('change', m, false);
    verifyEqual(tc, M.probs, pc(k, :), 'AbsTol', 1e-10);
end
verifyNotEmpty(tc, strfind(fileread(which('fused_class')), 'fuse_classes(''windows'', S, pf, N, fuse_classes(''cues'', FM))'));
verifyNotEmpty(tc, strfind(fileread(which('det_frames')), 'fuse_classes(''cues'', PP.fuse)'));
end

function test_fusion_target_age(tc)
% A path-loss onset is the fused target while the window still holds a cycle before it
% (pos - onset < N - 1, threat_active.m's rule) for a fusion fitted on that rule
% (FM.target_age, select_fusion.m with FUSION_REV); one fitted before it keeps its own
% (pos - onset < N). With FUSION_REV, N is scored on the frames no candidate's window
% relabels (all candidates share the per-cycle label there), the shortest within one standard
% error; without it the selection, its printout's scores and fusion.mat's layout are the ones
% the profiles' fusions were chosen by.
cls = {'none', 'path_loss'};
y = [1 1 2 2 1 1 1]; run = ones(1, 7); pos = 1:7;
verifyEqual(tc, fusion_target(y, run, pos, 4, cls)', [1 1 2 2 2 2 1]);
verifyEqual(tc, fusion_target(y, run, pos, 4, cls, struct('target_age', 3))', [1 1 2 2 2 1 1]);
verifyEqual(tc, fusion_target(y, run, pos, 4, cls, struct('W', 1))', [1 1 2 2 2 2 1]);
src = fileread(which('select_fusion'));
verifyNotEmpty(tc, strfind(src, 'FM.target_age = TA.target_age; FM.cues = cues;'));
verifyNotEmpty(tc, strfind(src, 'a = find(max(cv, [], 2) >= mx - se, 1);'));
verifyNotEmpty(tc, strfind(src, 'cm = true(size(y)); lab = ''the per-cycle label'';'));
verifyNotEmpty(tc, strfind(src, 'if REV, cm = all(YN == y, 2); lab = ''the frames no candidate relabels''; end'));
verifyNotEmpty(tc, strfind(src, ['save(''data/fusion.mat'', ''FM'', ''N'', ''lambda'', ''NS'', ''LAMBDA'', ''cv'', ''val_probs_oof'', ' ...
    '''val_latch_oof'', ''val_target'', ''q_thr'');']));
verifyNotEmpty(tc, strfind(src, 'if REV, save(''data/fusion.mat'', ''cvy'', ''cvo'', ''-append''); end'));
verifyNotEmpty(tc, strfind(src, 'cvy(a, b) = macro_f1(y(cm), yh(cm), C); cvo(a, b) = macro_f1(yn, yh, C);'));
verifyNotEmpty(tc, strfind(src, 'REV = exist(''FUSION_REV'', ''var'') && isequal(FUSION_REV, true);'));
verifyNotEmpty(tc, strfind(src, 'TAa = []; if REV, TAa = struct(''target_age'', NS(a) - 1); end'));
for f = {'eval_detector', 'compare_architectures', 'detector_block'}
    verifyNotEmpty(tc, regexp(fileread(which(f{1})), 'fusion_target\([^\n]*(FZ\.FM|fus\.FM|G\.FM)\)', 'once'), f{1});
end
end

function test_sweeper_confirmation(tc)
% The sweeping jammer revisits our channel once per period, on isolated cycles: with its own
% confirmation (PP.confirm_sweep = [2 6]) a 1-0-1-0 sequence of its reads confirms on the
% second read under 2/2 and 3/3, without it never; a clean sequence and another class's
% isolated reads stay unconfirmed; the detector's latency line reads it beside the class path.
A = policy_actions(); na = find(strcmp(A, 'no_action'));
cls = {'none', 'jamming', 'sweeping_jammer'};
seqs = {repmat({'sweeping_jammer', 'none'}, 1, 4), repmat({'none'}, 1, 8), repmat({'jamming', 'none'}, 1, 4)};
for cf = {[2 2], [3 3]}
    for sw = {[], [2 6]}
        PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'confirm', cf{1}, ...
            'alarm_mode', 'class', 'confirm_sweep', sw{1});
        for q = 1:3
            m = []; c = false(1, 8);
            for k = 1:8
                o = struct('probs', double(strcmp(cls, seqs{q}{k})), 'unknown', false, 'feat', zeros(1, numel(link_features('names'))));
                o.feat(feature_index('log_ber')) = -6;
                [~, m, d] = policy_decide('rule_esc', o, na, m, PP, []); c(k) = d.confirmed;
            end
            msg = sprintf('sequence %d, confirm %s, sweeper %d', q, mat2str(cf{1}), ~isempty(sw{1}));
            if q == 1 && ~isempty(sw{1}), verifyEqual(tc, find(c, 1), 3, msg); else, verifyFalse(tc, any(c), msg); end
        end
    end
end
verifyEqual(tc, decision_config().confirm_sweep, [2 6]);
verifyNotEmpty(tc, strfind(fileread(which('eval_detector')), 'cf = cf | movsum(swr(ix(j0:end)), [CS(2) - 1, 0]) >= CS(1);'));
end

function test_drop_hold_release(tc)
% The median window's reference holds the cycles of a drop above half the smallest path-loss
% level until it ends (drop_ref.m, as the CUSUM's): a 4 dB step below a 5 dB threshold is
% not absorbed, so a further 2 dB step raises the alarm; the monitor equals
% drop_alarm_seq.m with another path's alarm cycles kept out of the reference; a ramp past
% the excursion's start reads its whole depth (monitor_window_drop.m).
e = 12 * ones(1, 60); e(21:end) = 8; e(41:end) = 6;
[a, W] = drop_alarm_seq(e, 'class_drop', 5);
verifyEqual(tc, find(a, 1), 42);
verifyTrue(tc, all(W(22:41)));
A = policy_actions(); na = find(strcmp(A, 'no_action')); nF = numel(link_features('names'));
cls = {'none', 'jamming', 'path_loss'};
rng(11); n = 50; x = 12 + randn(2, n); x(:, 21:end) = x(:, 21:end) - 7; oth = false(2, n); oth(2, [5:8 30:33]) = true;
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', -Inf, 'confirm', [2 2], ...
    'alarm_mode', 'class_drop', 'drop_db', 5, 'cfg_gain_db', zeros(1, numel(A)));
m = policy_monitor('init', 2, numel(A)); da = false(2, n);
for t = 1:n
    o = struct('probs', [double(~oth(:, t)), double(oth(:, t)), zeros(2, 1)], 'unknown', false(2, 1), 'feat', zeros(2, nF));
    o.feat(:, feature_index('log_ber')) = -6;
    o.feat(:, feature_index('sinr')) = x(:, t) - 10*log10(4) + 10*log10(2);
    [m, M] = policy_monitor('update', m, o, PP, na * ones(1, 2)); m = policy_monitor('change', m, false(1, 2));
    da(:, t) = M.drop_alarm';
end
verifyEqual(tc, da, drop_alarm_seq(x, 'class_drop', 5, [], oth));
r = [12 * ones(1, 5), 12 - (1:10), 2 * ones(1, 10)];
verifyGreaterThan(tc, monitor_window_drop(r), 9.5);
verifyEqual(tc, monitor_window_drop(10 - 0.2 * (0:59)), 0.9, 'AbsTol', 1e-9);   % below the start: absorbed as before
end

function test_drop_whole_monitor(tc)
% C1d admits each monitor's drop threshold on the whole monitor (monitor_confirm.m): the drop
% alarm or any other path, confirmed by that monitor's m of n, with the sweeper's own
% confirmation when set; up to a policy's first change its episode is the no_action one
% (monitor_trace.m on the same seeds), so the first confirmation is the policy's earliest.
Tr = struct('other', false(3, 12), 'sw', false(3, 12), 'eg', 12 * ones(3, 12));
Tr.other(1, [3 4]) = true; Tr.other(2, [3 5 7]) = true; Tr.sw(2, [3 5]) = true; Tr.eg(3, 6:end) = 4;
c = @(thr, cf, cs) any(monitor_confirm(Tr, 'class_drop', thr, cf, cs), 2)';
verifyEqual(tc, c(Inf, [2 2], []), [true false false]);
verifyEqual(tc, c(6, [2 2], []), [true false true]);
verifyEqual(tc, c(6, [3 3], []), [false false true]);
verifyEqual(tc, c(Inf, [2 2], [2 6]), [true true false]);
verifyEqual(tc, c(10, [2 2], []), [true false false]);
[PP, K] = toy_world(true);
spec = struct('scn', [1 2 2], 's', [1 1 1], 'onset', [3 3 6], 'follow', false(1, 3), 'fdelay', [0 0 0], 'unk', false(1, 3), ...
    'T', 12, 'r', [1 1 1]);
T = monitor_trace(PP, K, {spec}, 1, 7);
cm = monitor_confirm(T, 'class_drop', Inf, decision_config().confirm);
R = rollout_policy('rule_esc', PP, K, spec, 1, [], struct(), 8);
for i = 1:3
    k = find(cm(i, spec.onset(i) + 1:end), 1);
    if isempty(k), verifyTrue(tc, isnan(R.t_conf(i))); else, verifyEqual(tc, R.t_conf(i), k - 1); end
end
verifyTrue(tc, any(T.other(2, :)) && ~any(T.other(1, :)));
src = fileread(which('choose_drop_threshold'));
verifyNotEmpty(tc, strfind(src, '''MONP'', ''confirm_sweep'''));
verifyNotEmpty(tc, strfind(src, 'Tc = monitor_trace(PPw, Kw, spc, VA, 41000);'));
src = fileread(which('train_dqn'));
verifyNotEmpty(tc, strfind(src, 'if isfield(Dd, ''confirm_sweep''), PP.confirm_sweep = Dd.confirm_sweep; end'));
verifyNotEmpty(tc, strfind(src, 'for dd = drops_of(ALARMS{ai}, MONP, DROP_MODE, DROP_DB, THC, DROP_STEPS, DROP_FLOOR)'));
verifyNotEmpty(tc, strfind(src, '[specs, n] = clean_wide_specs(PP, CT, ebno_thr, H.T);'));
verifyEqual(tc, decision_config().drop_steps, [-2 0 2]);
end

function test_reward_needs_plr(tc)
% The reward's restoration and the healthy link are KPI 4's test, BER and packet loss: a
% configuration that restores the BER but not the packet loss earns at most C.q_partial, a
% geometry whose no_action loses packets is not healthy; K.restored stays the BER test.
[PP, K] = toy_world(true);
A = PP.actions; na = find(strcmp(A, 'no_action')); C = decision_config();
fd = find(strcmp(A, 'freq_diversity'));
verifyEqual(tc, [K.q(2, 1, fd, 1, 1), K.healthy(1, 1, 1, 1)], [C.q_restored, true]);
PP.pools{2, 1, fd, 1}.fer(1:2:end) = 1;                        % the BER restored, half the packets lost
PP.pools{1, 1, na, 1}.fer(1:2:end) = 1;                        % the clean link's no_action loses packets
K2 = link_env('tables', PP);
verifyTrue(tc, K2.restored(2, 1, fd, 1, 1)); verifyFalse(tc, K2.restored_plr(2, 1, fd, 1, 1));
verifyEqual(tc, K2.q(2, 1, fd, 1, 1), C.q_partial);
verifyFalse(tc, K2.healthy(1, 1, 1, 1));
end

function test_held_selection(tc)
% C2 selects on held recovery (dqn_held.m, the edge map's REC): a hop-only configuration
% against a follower that re-acquires after 5 cycles recovers (KPI 4's 5 cycles) but does not
% hold, and ranks below one that holds; checkpoints, runs and the gate read it.
[PP, K] = toy_world(true);
cs = find(strcmp(PP.actions, 'channel_switch')); fd = find(strcmp(PP.actions, 'freq_diversity'));
spec = struct('scn', [2 2], 's', [1 1], 'onset', [1 1], 'follow', [true true], 'fdelay', [5 5], 'unk', [false false], ...
    'T', 30, 'r', [1 1], 'delay', 1);
Rh = rollout_policy('fixed', PP, K, spec, 1, [], struct('fixed', cs), 3); Rh.threat = true(1, 2);
Rf = rollout_policy('fixed', PP, K, spec, 1, [], struct('fixed', fd), 3); Rf.threat = true(1, 2);
verifyEqual(tc, [dqn_recovered(Rh), dqn_held(Rh), dqn_recovered(Rf), dqn_held(Rf)], [1 0 1 1]);
verifyNotEmpty(tc, strfind(fileread(which('dqn_train_run')), 'sc = dqn_held(Re) + 1e-3 * mean(Re.ret);'));
src = fileread(which('train_dqn'));
verifyNotEmpty(tc, strfind(src, 'gate = B.held >= bsel.held && B.fa_ok;'));
verifyNotEmpty(tc, strfind(src, 'top = top([X(top).held] >= max([X(top).held]) - 0.005);'));
end

function test_rule_slot_and_group_dwell(tc)
% The rule's quiet-slot branch is a setting (PP.rule_slot): off, a degraded link read as none
% with interference in the slot takes the generic answer, while the slot still keeps a drop
% alarm from the link-budget answer. The group dwell (PP.rule_dwell 'group') commits a
% proposal whose group appears in 2 of the last 4 cycles, so alternating freq_diversity and
% freq_diversity+power_control proposals commit where the consecutive dwell never does, and
% it never regresses to a configuration the one in use covers.
verifyEqual(tc, rule_based_policy('none', true, 0, 10, 5, false, [], 6, false), 'freq_diversity+power_control');
verifyEqual(tc, rule_based_policy('none', true, 0, 10, 5, false, [], 6, true), 'channel_switch');
verifyEqual(tc, rule_based_policy('none', false, 0, 10, 5, true, [], 6, false), 'no_action');
A = policy_actions(); na = find(strcmp(A, 'no_action')); cls = {'none', 'sweeping_jammer'};
fp = find(strcmp(A, 'freq_diversity+power_control'));
for dw = {'run', 'group'}
    PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'q_thr', 5, 'confirm', [2 2], ...
        'alarm_mode', 'class', 'rule_dwell', dw{1});
    m = []; a = na; trace = zeros(1, 10);
    for k = 1:10
        o = struct('probs', double(strcmp(cls, ternary_t(mod(k, 2) == 1, 'sweeping_jammer', 'none'))), 'unknown', false, ...
            'feat', zeros(1, numel(link_features('names'))));
        o.feat(feature_index('log_ber')) = -1; o.feat(feature_index('crc_fail')) = 1;
        [a, m] = policy_decide('rule', o, a, m, PP, []); trace(k) = a;
    end
    if strcmp(dw{1}, 'run'), verifyTrue(tc, all(trace == na));
    else, verifyEqual(tc, trace, [na, fp * ones(1, 9)]); end
end
end

function x = ternary_t(c, a, b)
if c, x = a; else, x = b; end
end

function test_escalation_on_drop(tc)
% With PP.esc_drop a confirmed drop alarm read as none escalates out of no_action, its first
% step the link-budget configuration with the smallest known gain covering the drop; without
% the setting the class none blocks it; a configuration whose known gain covers the drop is
% not left on degraded cycles.
A = policy_actions(); na = find(strcmp(A, 'no_action')); cls = {'none', 'jamming'}; nF = numel(link_features('names'));
g = zeros(1, numel(A)); pc = find(strcmp(A, 'power_control')); rr = find(strcmp(A, 'rate_reduce'));
rp = find(strcmp(A, 'rate_reduce+power_control')); g([pc rr rp]) = [6 3 9];
opt = struct('table', na * ones(1, 2), 'table_unknown', find(strcmp(A, 'freq_diversity')));
for ed = [false true]
    PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', -Inf, 'confirm', [2 2], ...
        'alarm_mode', 'class_drop', 'drop_db', 4, 'cfg_gain_db', g, 'esc_drop', ed);
    m = []; a = na; first = NaN;
    for k = 1:24
        o = struct('probs', [1 0], 'unknown', false, 'feat', zeros(1, nF), 'cfg_link', a);
        o.feat(feature_index('log_ber')) = -6;
        o.feat(feature_index('sinr')) = 12 - 8 * (k > 12) + g(a) - 10*log10(4) + 10*log10(2);
        b = a; [a, m] = policy_decide('table_esc', o, a, m, PP, [], opt);
        if a ~= b && isnan(first), first = a; end
    end
    if ed, verifyEqual(tc, first, rp); else, verifyTrue(tc, isnan(first)); end
end
PP.esc_drop = true; m = []; a = rp; ch = false(1, 20); opt.table_unknown = rp;   % the table keeps it on a degraded link
for k = 1:20
    o = struct('probs', [1 0], 'unknown', false, 'feat', zeros(1, nF), 'cfg_link', rp);
    o.feat(feature_index('log_ber')) = -6 + 5 * (k > 12);           % degraded cycles from 13 on
    o.feat(feature_index('sinr')) = 12 - 8 * (k > 12) + g(rp) - 10*log10(4) + 10*log10(2);
    b = a; [a, m] = policy_decide('table_esc', o, a, m, PP, [], opt); ch(k) = a ~= b;
end
verifyGreaterThan(tc, m.deg_n, decision_config().esc);             % stuck long enough to escalate but for the cover
verifyFalse(tc, any(ch));
end

function test_unknown_override_mode(tc)
% The unknown-threat flag overrides every class ('all', the default) or only a class that
% raises no alarm ('nonhostile'): a hostile class read keeps its alarm under 'nonhostile',
% none is overridden under both, and the agent's state keeps the flag either way.
A = policy_actions(); na = find(strcmp(A, 'no_action')); cls = {'none', 'jamming'};
for md = {'all', 'nonhostile'}
    PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'unk_mode', md{1});
    for c = {'none', 'jamming'}
        o = struct('probs', double(strcmp(cls, c{1})), 'unknown', true, 'maha', -1, 'feat', zeros(1, numel(link_features('names'))));
        o.feat(feature_index('log_ber')) = -6;
        [m, M] = policy_monitor('update', policy_monitor('init', 1, numel(A)), o, PP, na);
        ex = 'unknown'; if strcmp(md{1}, 'nonhostile') && strcmp(c{1}, 'jamming'), ex = 'jamming'; end
        verifyEqual(tc, M.cls{1}, ex, [md{1} ' ' c{1}]);
        verifyEqual(tc, M.alarm, strcmp(ex, 'jamming'), [md{1} ' ' c{1}]);
        verifyEqual(tc, m.hist(numel(cls) + 1, 1, 1), 1, [md{1} ' ' c{1}]);
    end
end
end

function test_threat_offset(tc)
% A threat that ends (link_env.m spec.offset): from the offset the episode flies the same
% flight's clean link; a change back to no_action decided after it is a release, no false
% switch; rollout_policy.m reads the configuration held at the end, the cycles to its
% release, the running cost held after it and the re-alarms; evaluate_policies.m reports them.
[PP, K] = toy_world(true);
fd = find(strcmp(PP.actions, 'freq_diversity'));
spec = struct('scn', 2, 's', 1, 'onset', 2, 'follow', false, 'fdelay', 0, 'unk', false, 'T', 20, 'r', 1, 'delay', 1, 'offset', 8);
[E, ~] = link_env('reset', PP, K, spec, 1, RandStream('mt19937ar', 'Seed', 1));
seq = [K.na fd fd fd fd fd fd fd fd fd K.na K.na];
[fs, rel] = deal(false(1, numel(seq))); sc = zeros(1, numel(seq));
for t = 1:numel(seq)
    [E, ~, ~, info] = link_env('step', E, PP, K, seq(t));
    fs(t) = info.false_switch; rel(t) = info.released; sc(t) = info.sc_eff;
end
verifyEqual(tc, sc, [1 2 2 2 2 2 2 1 1 1 1 1]);
verifyEqual(tc, find(rel), 11);
verifyFalse(tc, any(fs));
R = rollout_policy('fixed', PP, K, spec, 1, [], struct('fixed', fd), 3);
verifyEqual(tc, [R.cfg_end, R.rel_t, R.on_end], [fd NaN 1]);
verifyEqual(tc, R.cost_end, K.cost(fd), 'AbsTol', 1e-12);
R0 = rollout_policy('fixed', PP, K, spec, 1, [], struct('fixed', K.na), 3);
verifyEqual(tc, [R0.cfg_end, R0.rel_t, R0.on_end], [K.na 0 0]);
spec.offset = Inf; R = rollout_policy('fixed', PP, K, spec, 1, [], struct('fixed', fd), 3);
verifyTrue(tc, isnan(R.rel_t) && isnan(R.cfg_end));
verifyNotEmpty(tc, strfind(fileread(which('evaluate_policies')), 'for b = 1:numel(so), so{b}.offset = so{b}.onset + OFF_AFTER; end'));
end

function test_harmed_readings(tc)
% KPI 4 beside its proposal reading on the harmed episodes only (no response does not
% restore them), its envelope on validation alike, KPI 8 on them; the edge map's REC_h,
% PROT_h and the no-response attribution mark.
[~, K] = toy_world(true);
ih = sub2ind(size(K.restored), [1 2], [1 1], K.na * [1 1], [1 1], [1 1]);
verifyEqual(tc, ~(K.restored(ih) & K.restored_plr(ih)), [false true]);
src = fileread(which('evaluate_policies'));
verifyNotEmpty(tc, strfind(src, 'h = ~(K.restored(ih) & K.restored_plr(ih));'));
verifyNotEmpty(tc, strfind(src, 'HV = harmed(RV, K);'));
verifyNotEmpty(tc, strfind(src, '''per_threat_h'', PTh'));
verifyNotEmpty(tc, strfind(fileread(which('measure_all_kpis')), ...
    'ph = P.KP.per_threat_h(:, strcmp(P.KP.show, P.POL{iD})); n_ok = sum(ph >= 50);'));
src = fileread(which('edge_map'));
verifyNotEmpty(tc, strfind(src, 'P.prot_h = edge_verdict(F.held_k(h, v), F.ep_n(h, v), F.geo(h), TGT.prot, ''ge'', true, B);'));
verifyNotEmpty(tc, strfind(src, 'X.nresp(q, s) = Vn.verdict;'));
end

function test_dqn_deployment_kinds(tc)
% C2 scores every run with and without the escalation and may deploy the DQN without it
% ('dqn'); every reader runs the deployed kind.
Q = struct('agent', struct('k', 1), 'agents', {{struct('k', 2)}}, 'rule_sel', struct());
[kind, ag] = policy_setup('dqn', Q, 1, [], [], [], 1);
verifyEqual(tc, {kind, ag.k}, {'dqn', 1});
verifyNotEmpty(tc, strfind(fileread(which('evaluate_policies')), 'dep = Q.deployed; if strcmp(dep, ''dqn''), dep = POL{iBase}; end'));
verifyNotEmpty(tc, strfind(fileread(which('edge_map')), '''dqn'', ''DQN'''));
verifyNotEmpty(tc, strfind(fileread(which('measure_latency')), 'kindD = ''dqn_esc''; if strcmp(dep, ''dqn''), kindD = ''dqn''; end'));
for f = {'experiment_unknown_threat', 'experiment_combo_generalization'}
    verifyNotEmpty(tc, strfind(fileread(which(f{1})), 'dqn_eval_batches(DK, PP, K, specs, Q.agent'), f{1});
end
src = fileread(which('train_dqn'));
verifyNotEmpty(tc, strfind(src, 'xe = ev(''dqn_esc'', PPc, ag, struct()); xn = ev(''dqn'', PPc, ag, struct());'));
verifyNotEmpty(tc, strfind(src, ['[deployed, fa_bound_met, ir] = choose_deployed(gate, fa_up(B.fa_w, B.n_w), rr, rb_up, ' ...
    'FA_BOUND, B.held, sel_kind);']));
end

function test_rule_settings_on_validation(tc)
% The rule's settings are chosen on validation in C2 against the setting in force: the
% nulling threshold among mu + 3 sigma (+ 2 dB) of the clean validation frames' predicted
% MMSE gain, 3, 6 and 9 dB, the quiet-slot branch on and off, the dwell, the unknown flag's
% retention and override, the escalation on a drop; stored with the agent (dec, rule_sel).
src = fileread(which('train_dqn'));
verifyNotEmpty(tc, strfind(src, 'TH = [mu_s(1) + 3 * mu_s(2), mu_s(1) + 3 * mu_s(2) + 2, TH];'));
verifyNotEmpty(tc, strfind(src, 'v{end+1} = struct(''unk_mode'', md{1}, ''unk_retain'', rt, ''maha_thr'', unk_threshold(PP.maha_val, rt));'));
verifyNotEmpty(tc, strfind(src, 'for f = fieldnames(Ssel)'', rule_sel.(f{1}) = Ssel.(f{1}); end'));
verifyNotEmpty(tc, strfind(src, '''pools_created'', ''maha_thr'', ''dec'', ''-v7.3'''));
verifyNotEmpty(tc, strfind(src, 'maha_thr = dec.maha_thr;'));
end
