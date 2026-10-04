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
P = {'channel', 'awgn', 'bits', 'threat', 'aoa', 'k', 'yaw', 'corr', 'gcsaoa', 'gcs', 'alt', 'speed', 'body', 'wobble'};
off = zeros(1, numel(P));
for i = 1:numel(P)
    [~, n] = seed_stream(12345, P{i});
    off(i) = n - seed_base(12345);
end
verifyEqual(tc, numel(unique(off)), numel(P));
verifyTrue(tc, all(off >= 0 & off < 64));
[s, r, b] = ndgrid(1:6, 1:99, 1:19);                    % every pool block that keeps its own seed range
S = arrayfun(@(si, ri, bi) pool_seed(1, si, bi, ri), s(:), r(:), b(:));
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
G = arrayfun(@(x) gcs_aoa(x, [0 1]), S);
W = cell2mat(arrayfun(@(x) hover_attitude(x, 0, p), S, 'UniformOutput', false));
W = (W(:, 1) - p.wobble_roll_deg(1)) / diff(p.wobble_roll_deg);
U = [K, A, (w + 1) / 2, rho, v, G, W];                  % the uniform behind every draw
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
% flights in every sixth of the speed range and 4 + 20 in every third of the altitude
% range at every Eb/N0, a design of 24 (the smaller second test) 4 and 8; every axis has
% one flight per stratum, the value inside it is the flight's own draw, and every value
% lies in its range. The edge-speed split flies exactly hover and 161 km/h.
p = base_params();
vr = [p.speed_kmh_min p.speed_kmh_max]; ha = p.alt_range_m; kr = p.k_range_db;
six = @(g) histcounts(g.speed, linspace(vr(1), vr(2), 7));
thr = @(g) histcounts(g.alt, linspace(ha(1), ha(2), 4));
for s = 1:6
    g1 = pool_geometries(s, 14, 1:12, vr, p, 7100000 + 100*s + 3);
    g2 = pool_geometries(s, 17, 1:60, vr, p, 7100000 + 100*s + 5);
    gc = pool_geometries(s, 17, 61:84, vr, p, 7100000 + 100*s + 15);
    verifyEqual(tc, [six(g1); six(g2); six(gc)], repmat([2; 10; 4], 1, 6));
    verifyEqual(tc, [thr(g1); thr(g2); thr(gc)], repmat([4; 20; 8], 1, 3));
    verifyEqual(tc, histcounts(g2.ksig, kr(1):5:kr(2)), 12 * ones(1, 5));    % 5-dB K bands
    for g = {g1, g2, gc}
        x = g{1}; n = numel(x.seed);
        verifyEqual(tc, sort(floor(n * (x.speed - vr(1)) / diff(vr))), 0:n-1);
        verifyEqual(tc, sort(floor(n * (x.alt - ha(1)) / diff(ha))), 0:n-1);
        verifyEqual(tc, sort(floor(n * (x.ksig - kr(1)) / diff(kr))), 0:n-1);
        verifyTrue(tc, all(x.speed > vr(1) & x.speed < vr(2) & x.alt > ha(1) & x.alt < ha(2) ...
            & x.ksig > kr(1) & x.ksig < kr(2)));
        u = rand(seed_stream(x.seed(1), 'alt'));
        k = floor(n * (x.alt(1) - ha(1)) / diff(ha));
        verifyEqual(tc, x.alt(1), ha(1) + diff(ha) * (k + u) / n, 'AbsTol', 1e-9);
    end
end
verifyEqual(tc, pool_geometries(6, 17, 1:60, vr, p, 7100605), g2);              % reproducible
q = @(x) floor(numel(x.seed) * (x.alt - ha(1)) / diff(ha));
verifyNotEqual(tc, q(pool_geometries(1, 14, 1:12, vr, p, 7100103)), q(g1));    % own permutation per Eb/N0
verifyLessThan(tc, 7100000 + 100*6 + 15, seed_base(700001));                   % below every flight stream
p.alt_random = false;
verifyTrue(tc, all(isnan(pool_geometries(1, 17, 1:12, vr, p, 7100105).alt)));
VOUT = [0 0; 161 161];
ge = pool_geometries(1, 16, 1:24, VOUT(1 + ((1:24)' > 12), :), p);
verifyEqual(tc, ge.speed, [zeros(1, 12), 161 * ones(1, 12)]);
verifyTrue(tc, all(isnan([ge.alt ge.ksig])));
end

function test_receiver_measurements(tc)
p = base_params(); p.quiet_build = true; p.active_threat = 'none'; p.int_aoa_random = false; p.yaw_random = false; p.corr_random = false; p.gcs_tracked = false; p.seed = 11;
p.k_random = false; p.gcs_aoa_random = false; p.body_random = false;
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
% spatial coherence of the clean link on five flights, against a weak jammer on the same
% flights below: only our own signal's residual after the channel estimate is coherent
CS = 11:15; coh0 = zeros(size(CS)); coh0(1) = mean(F.coh, 'omitnan');
for k = 2:numel(CS)
    link_seed(mdl, CS(k), 160);
    Fk = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(10 * p.frame_duration)), p, 20);
    coh0(k) = mean(Fk.coh, 'omitnan');
end
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
close_system(mdl, 0);
p.active_threat = 'jamming';
evalc('build_threat_model(p)');
set_param([mdl '/AWGN'], 'SNR', num2str(snr), 'SignalPower', num2str(1/p.sps));
link_seed(mdl, 11, 160);
F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(10 * p.frame_duration)), p, 20);
verifyGreaterThan(tc, median(F.q_iot), 10);
verifyLessThan(tc, abs(median(F.q_react)), 3);
verifyGreaterThan(tc, mean(F.coh, 'omitnan'), 0.8);  % one directional source
close_system(mdl, 0);
% a jammer at a low trained level (4 dB) is clearly more coherent than the clean link
p.jsr_db = 4;
evalc('build_threat_model(p)');
set_param([mdl '/AWGN'], 'SNR', num2str(snr), 'SignalPower', num2str(1/p.sps));
coh4 = zeros(size(CS));
for k = 1:numel(CS)
    link_seed(mdl, CS(k), 160);
    F = extract_closed_loop_frames(sim(mdl, 'StopTime', num2str(10 * p.frame_duration)), p, 20);
    coh4(k) = mean(F.coh, 'omitnan');
end
verifyGreaterThan(tc, mean(coh4) - mean(coh0), 0.15);
close_system(mdl, 0);
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
d2 = flight_draws(77, 100, p, struct('ebno', 9, 'alt_m', NaN, 'k_sig_db', NaN));
verifyEqual(tc, [d2.alt_m d2.k_sig], [d0.alt_m d0.k_sig]);
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
% measured means and the pitch wobble within Banagar & Dhillon's ranges. The wobble's
% lever-arm phase k aD cos(phi) sin(pitch) (phi = 20 deg, their example) decorrelates the
% channel (ACF 0.5 at the worst phase) after 6.74 ms at 10 deg and 12.26 ms at 7 deg
% (+-30%), and never at 5 deg, as they found at 2.4 GHz.
p = base_params();
fd = @(v) v * p.carrier_freq / p.c_light;
verifyEqual(tc, hover_attitude(5, fd(p.wobble_v_max), p), zeros(1, 5));
verifyEqual(tc, hover_attitude(5, fd(p.v_max), p), zeros(1, 5));
W = cell2mat(arrayfun(@(s) hover_attitude(s, fd(3), p), (1:4000)', 'UniformOutput', false));
verifyTrue(tc, all(W(:, 1) >= p.wobble_roll_deg(1) & W(:, 1) <= p.wobble_roll_deg(2)));
verifyTrue(tc, all(W(:, 2) >= p.wobble_pitch_deg(1) & W(:, 2) <= p.wobble_pitch_deg(2)));
verifyTrue(tc, all(abs(W(:, 3)) <= p.wobble_amp_deg & W(:, 4) >= p.wobble_freq_hz(1) & W(:, 4) < p.wobble_freq_hz(2)));
d = flight_draws(5, fd(3), p);
verifyEqual(tc, [d.roll - sign(d.yaw) * d.bank, d.pitch, d.wobble], hover_attitude(5, fd(3), p), 'AbsTol', 1e-12);
d = flight_draws(5, fd(p.wobble_v_max), p);
verifyEqual(tc, [d.pitch d.wobble], zeros(1, 4));
ka = 2*pi * p.wobble_arm_m * p.carrier_freq / p.c_light;
tau = (0:0.05:30) * 1e-3;
tco = zeros(1, 3); m = [10 7 5];
for i = 1:3
    R = abs(mean(exp(1j * ka * cosd(20) * sind(W(:, 3) * m(i) / 10 .* sin(2*pi * W(:, 4) * tau))), 1));
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
