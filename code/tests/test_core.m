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
% Pool geometries never share a seed across the blocks in use; K-factors are
% reproducible per seed and stay inside the range.
blocks = [1 4 5 13 14 15 16]; S = [];
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
verifyLessThan(tc, mean(F.coh(v)), 0.2);             % thermal noise only: no spatial coherence
verifyLessThan(tc, mean(F.ber_est(v)), 1e-3);        % clean link at 12 dB
verifyLessThan(tc, max(F.branch_dip), 6);            % fading changes little within a frame, first frame included
sinr_clean = median(F.sinr(v));
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
close_system(mdl, 0);
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
w = arrayfun(@(s) heading_rate(s, 0, p), 1:200);
verifyLessThanOrEqual(tc, max(abs(w)), p.yaw_rate_max + 1e-9);
verifyEqual(tc, heading_rate(7, 300, p), heading_rate(7, 300, p));
v = p.v_max; wf = rad2deg(9.81 * tand(p.roll_max_deg) / v);
verifyLessThanOrEqual(tc, max(abs(arrayfun(@(s) heading_rate(s, v * p.carrier_freq / p.c_light, p), 1:200))), min(wf, p.yaw_rate_max) + 1e-9);
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
