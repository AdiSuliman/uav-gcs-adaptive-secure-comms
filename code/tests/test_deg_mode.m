function tests = test_deg_mode
%TEST_DEG_MODE  Unit tests of the degradation test's candidates (policy_monitor.m deg_mode,
%   deg_quantile.m, clean_halves.m, clean_ber_q.m, deg_adopt.m; docs/deg_fix_protocol.md), on
%   synthetic frames and a clean-link table written in a temporary folder; no pools. Run from
%   the repository root:
%   results = runtests('code/tests/test_deg_mode.m')
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
end

function teardownOnce(tc)
clear('clean_ber_ref');
cd(tc.TestData.cwd);
end

%% ---------- 'ratio': today's monitor ----------
function test_ratio_bit_identical(tc)
% Without PP.deg_mode and with 'ratio' the monitor gives the parent commit's (lect-kpi 899e1c6)
% M and memory bit for bit, cycle by cycle, on a trace with degradation, a drop, hostile
% classes, a coded link and changes that reach the link one cycle later.
[PP, X] = trace_world();
d = parent_copy(tc, 'code/decision/policy_monitor.m', '899e1c6');
addpath(d, '-begin'); clear policy_monitor
cl0 = onCleanup(@() fixture_off(d, 'policy_monitor')); %#ok<NASGU>
verifyEqual(tc, which('policy_monitor'), fullfile(d, 'policy_monitor.m'));
Oo = monitor_run(PP, X);
fixture_off(d, 'policy_monitor');
verifyNotEqual(tc, which('policy_monitor'), fullfile(d, 'policy_monitor.m'));
On = monitor_run(PP, X);
PPr = PP; PPr.deg_mode = 'ratio';
Or = monitor_run(PPr, X);
verifyTrue(tc, isequaln(Oo, On), 'default deg_mode');
verifyTrue(tc, isequaln(Oo, Or), 'deg_mode ratio');
verifyTrue(tc, any(cellfun(@(M) any(M.degraded), Oo.M)) && any(cellfun(@(M) any(M.drop_alarm), Oo.M)));
verifyTrue(tc, any(cellfun(@(M) any(~M.degraded), Oo.M)));
verifyEqual(tc, decision_config().deg_mode, 'ratio');
end

%% ---------- F1 'win' ----------
function test_win_median_lookup(tc)
% The lookup reads the median of the window's measured Eb/N0 estimates (one +3 dB frame moves
% it not), with the configuration's gain as measured, not the gain-removed drop window.
PP = mon_pp(); PP.deg_mode = 'win';
na = find(strcmp(PP.actions, 'no_action')); pc = find(strcmp(PP.actions, 'power_control'));
for cfg = [na pc]
    mem = policy_monitor('init', 1, numel(PP.actions));
    e = [10 10 10 10 13];
    for t = 1:5
        [mem, M] = policy_monitor('update', mem, mk_obs(PP, -3, e(t), 0, cfg), PP, cfg);
        mem = policy_monitor('change', mem, false);
    end
    verifyEqual(tc, M.ebno_est, 13, 'AbsTol', 1e-9);
    verifyEqual(tc, M.ebno_win, 10, 'AbsTol', 1e-9);
    verifyEqual(tc, M.deg_thr, 2 * max(clean_ber_ref(M.ebno_win, 'ber_est'), 1e-4), 'RelTol', 1e-12);
    verifyEqual(tc, mem.ebno(end), 13 - PP.cfg_gain_db(cfg), 'AbsTol', 1e-9);   % the drop's window: gain removed
    verifyEqual(tc, M.degraded, 1e-3 > M.deg_thr);
end
end

function test_win_window_resets_at_arrival(tc)
% The Eb/N0 window restarts with the BER window on the first frame received with a change:
% the lookup then reads that frame alone; while the request is on its way it keeps filling.
PP = mon_pp(); PP.deg_mode = 'win';
na = find(strcmp(PP.actions, 'no_action')); pc = find(strcmp(PP.actions, 'power_control'));
mem = policy_monitor('init', 1, numel(PP.actions));
for t = 1:6
    [mem, ~] = policy_monitor('update', mem, mk_obs(PP, -3, 4, 0, na), PP, na);
    mem = policy_monitor('change', mem, t == 6);
end
[mem, M] = policy_monitor('update', mem, mk_obs(PP, -3, 5, 0, na), PP, pc);   % still on its way
verifyEqual(tc, M.ebno_win, 4, 'AbsTol', 1e-9);
mem = policy_monitor('change', mem, false);
[mem, M] = policy_monitor('update', mem, mk_obs(PP, -2, 12, 0, pc), PP, pc);   % arrival
verifyEqual(tc, M.ebno_win, 12, 'AbsTol', 1e-9);
verifyTrue(tc, all(isnan(mem.eb(1:end-1))) && all(isnan(mem.ber(1:end-1))) && all(isnan(mem.qi(1:end-1))));
verifyEqual(tc, M.ber_avg, 1e-2, 'RelTol', 1e-12);
end

function test_windows_match_monitor(tc)
% deg_quantile('windows') reads the statistic the monitor reads at no_action: on a flight
% flown cyclically from frame k0, from the C.win-th cycle on the monitor's window BER and
% window Eb/N0 equal the window ending on the frame read.
C = decision_config(); PP = mon_pp(); PP.deg_mode = 'win';
na = find(strcmp(PP.actions, 'no_action'));
rs = RandStream('mt19937ar', 'Seed', 5); n = 8;
lb = -4 + 2 * rand(rs, n, 1); sn = 5 + 3 * randn(rs, n, 1); io = rand(rs, n, 1);
[b, e, g] = deg_quantile('windows', 10.^lb, sn + io + 10*log10(PP.sps) - 10*log10(PP.bps), 7 * ones(n, 1), C.win);
verifyEqual(tc, [numel(b) numel(e)], [n n]); verifyEqual(tc, g, 7 * ones(n, 1));
k = [6 7 8 1 2];                                                % the window ending on frame 2 wraps
verifyEqual(tc, b(2), mean(10.^lb(k)), 'RelTol', 1e-12);
verifyEqual(tc, e(2), median(sn(k) + io(k) + 10*log10(PP.sps) - 10*log10(PP.bps)), 'AbsTol', 1e-12);
mem = policy_monitor('init', 1, numel(PP.actions)); k0 = 3;
for t = 1:12
    j = mod(k0 + t - 1, n) + 1;
    o = mk_obs(PP, lb(j), 0, 0, na); o.feat(feature_index('sinr')) = sn(j); o.feat(feature_index('iot')) = io(j);
    [mem, M] = policy_monitor('update', mem, o, PP, na);
    mem = policy_monitor('change', mem, false);
    if t >= C.win
        verifyEqual(tc, [M.ber_avg, M.ebno_win], [b(j), e(j)], 'AbsTol', 1e-12);
    end
end
end

%% ---------- F2 'win_q': the clean quantile ----------
function test_quantile_reproduces_alpha(tc)
% On Gaussian log10 BER the fit's bins hold floor(alpha n) cycles above their threshold, the
% thresholds lie at the normal quantile, and a fresh draw exceeds them at about alpha.
rs = RandStream('mt19937ar', 'Seed', 17);
nf = 200; nc = 100; mu = -3; sg = 0.5;
g = repelem((1:nf)', nc); e = 12 * rand(rs, nf * nc, 1); lb = mu + sg * randn(rs, nf * nc, 1);
for alpha = [1e-2 1e-3]
    Q = deg_quantile('build', 10.^lb, e, g, alpha);
    verifyTrue(tc, all(Q.n >= round(10 / alpha)) && all(Q.nf >= 30) && ~Q.short);
    verifyEqual(tc, sum(Q.n), nf * nc);
    for i = 1:numel(Q.q)
        k = e >= Q.lo(i) & e < Q.hi(i);
        verifyEqual(tc, sum(10.^lb(k) > Q.q(i)), floor(alpha * sum(k) + 1e-9));
    end
    p = 0.5 * erfc((log10(Q.q) - mu) / (sg * sqrt(2)));             % true exceedance of each threshold
    verifyEqual(tc, sum(p .* Q.n) / sum(Q.n), alpha, 'AbsTol', 4 * sqrt(alpha / min(Q.n)));
    verifyEqual(tc, log10(Q.q), (mu + sg * sqrt(2) * erfinv(1 - 2 * alpha)) * ones(size(Q.q)), 'AbsTol', 0.2);
end
Q2 = deg_quantile('build', 10.^lb, e, g, 1e-2); Q3 = deg_quantile('build', 10.^lb, e, g, 1e-3);
verifyEqual(tc, numel(Q2.q), 12); verifyLessThanOrEqual(tc, numel(Q3.q), 2);   % 20,000 cycles hold at most two bins at 1e-3
end

function test_quantile_bins_merge(tc)
% A bin with fewer than 10/alpha cycles or 30 flights joins its neighbour with fewer cycles;
% the lower one first on a tie; one bin left that still fails is flagged, not widened.
mk = @(c, n, f) deal(c * ones(n, 1), mod((0:n-1)', f) + 1);
[e1, g1] = mk(0.5, 1500, 40); [e2, g2] = mk(1.5, 200, 40); [e3, g3] = mk(2.5, 1200, 40);
Q = deg_quantile('build', ones(2900, 1) * 1e-3, [e1; e2; e3], [g1; g2; g3], 1e-2);
verifyEqual(tc, [Q.lo; Q.hi; Q.n], [0 1; 1 3; 1500 1400]);          % joins the 1200-cycle neighbour
[e1, g1] = mk(0.5, 2000, 10); [e2, g2] = mk(1.5, 2000, 40); g2 = g2 + 10;
Q = deg_quantile('build', ones(4000, 1) * 1e-3, [e1; e2], [g1; g2], 1e-2);
verifyEqual(tc, [Q.lo Q.hi Q.n Q.nf], [0 2 4000 50]);                % 10 flights only: merged
[e1, g1] = mk(0.5, 600, 40); [e2, g2] = mk(1.5, 600, 40); [e3, g3] = mk(2.5, 5000, 40); [e4, g4] = mk(3.5, 600, 40);
[e5, g5] = mk(4.5, 5000, 40);
Q = deg_quantile('build', ones(11800, 1) * 1e-3, [e1; e2; e3; e4; e5], [g1; g2; g3; g4; g5], 1e-2);
verifyEqual(tc, [Q.lo; Q.n], [0 2 4; 1200 5600 5000]);                % ties: the lower bin, then the lower neighbour
Q = deg_quantile('build', ones(500, 1) * 1e-3, 3 * rand(500, 1), mod((0:499)', 50) + 1, 1e-2);
verifyEqual(tc, numel(Q.q), 1); verifyTrue(tc, Q.short);
Q = struct('lo', [0 1 4], 'q', [1e-2 1e-3 1e-4]);
verifyEqual(tc, deg_quantile('lookup', Q, [-3 0 0.99 1 3.9 4 20 NaN]), [1e-2 1e-2 1e-2 1e-3 1e-3 1e-4 1e-4 NaN]);
end

function test_halves_disjoint(tc)
% The fit and check halves split the geometries by their id's hash: disjoint, together all of
% them, 150 each of the 300 validation geometries, the same for any order of the ids.
r = 401:700;
[fit, chk] = clean_halves(r);
verifyFalse(tc, any(fit & chk)); verifyTrue(tc, all(fit | chk));
verifyEqual(tc, [sum(fit) sum(chk)], [150 150]);
p = randperm(RandStream('mt19937ar', 'Seed', 3), 300);
rp = r(p); [f2, ~] = clean_halves(rp);
verifyEqual(tc, sort(rp(f2)), sort(r(fit)));
verifyNotEqual(tc, find(fit), 1:150);                                 % not the first half by id
fam = floor((r - 401) / 100);                                          % each geometry family in both halves
verifyTrue(tc, all(arrayfun(@(k) any(fit & fam == k) && any(chk & fam == k), 0:2)));
verifyError(tc, @() clean_halves([401 401 402]), ?MException);
end

function test_clean_ber_q_fit_half_only(tc)
% The quantile tables read the fit half's flights only, every Eb/N0 point, and refuse any set
% but validation: the check half's frames can change without changing them.
PP = mon_pp();
[CV, fit] = toy_cv();
B1 = clean_ber_q(CV, PP, fit, [1e-2 1e-3]);
verifyEqual(tc, numel(B1), 2); verifyEqual(tc, B1(1).runs, double(CV.runs(fit)));
verifyEqual(tc, sum(B1(1).n), sum(fit) * 2 * 40);                    % 2 Eb/N0 points, 40 frames per flight
C2 = CV; na = find(strcmp(CV.actions, 'no_action'));
for s = 1:2
    P = C2.pools{1, s, na}; k = ~ismember(P.run, CV.runs(fit));
    P.feat(k, feature_index('log_ber')) = 0; C2.pools{1, s, na} = P;
end
verifyTrue(tc, isequaln(clean_ber_q(C2, PP, fit, [1e-2 1e-3]), B1));
C3 = CV; C3.set = 'test';
verifyError(tc, @() clean_ber_q(C3, PP, fit), 'clean_ber_q:source');
end

function test_win_q_threshold(tc)
% 'win_q' compares the window BER with the table's threshold at the window's Eb/N0, never
% below ratio_ok x deg_floor; without a table it stops.
PP = mon_pp(); PP.deg_mode = 'win_q'; PP.ber_q = struct('lo', [0 6], 'q', [3e-2 1e-5]);
na = find(strcmp(PP.actions, 'no_action'));
for c = {{2, -2, false}, {2, -1.4, true}, {9, -3.6, true}, {9, -3.8, false}}   % Eb/N0, log10 BER, degraded
    [e, lb, deg] = c{1}{:};
    mem = policy_monitor('init', 1, numel(PP.actions));
    for t = 1:5
        [mem, M] = policy_monitor('update', mem, mk_obs(PP, lb, e, 0, na), PP, na);
        mem = policy_monitor('change', mem, false);
    end
    verifyEqual(tc, M.deg_thr, max(deg_quantile('lookup', PP.ber_q, e), 2e-4), 'AbsTol', 1e-15);
    verifyEqual(tc, M.degraded, M.ber_avg > M.deg_thr);
    verifyEqual(tc, M.degraded, deg);
end
P0 = rmfield(PP, 'ber_q');
verifyError(tc, @() policy_monitor('update', policy_monitor('init', 1, numel(PP.actions)), mk_obs(PP, -2, 2, 0, na), P0, na), ...
    ?MException);
end

%% ---------- F3 'win_q_gate' ----------
function test_gate_needs_quiet_slot(tc)
% A degraded window alarms when one of its frames shows quiet-slot interference (PP.q_thr,
% else C.q_alarm_db); the same window with a quiet slot below it is degraded without RF
% evidence: logged, no alarm; interference that has left the window no longer counts.
PP = mon_pp(); PP.deg_mode = 'win_q_gate'; PP.ber_q = struct('lo', 0, 'q', 1e-3);
na = find(strcmp(PP.actions, 'no_action'));
qa = decision_config().q_alarm_db;
for c = {{[0 0 qa 0 0], true}, {[0 0 (qa - 0.1) 0 0], false}, {[qa 0 0 0 0 0], false}}
    [qs, al] = c{1}{:};
    mem = policy_monitor('init', 1, numel(PP.actions));
    for t = 1:numel(qs)
        [mem, M] = policy_monitor('update', mem, mk_obs(PP, -1, 6, qs(t), na), PP, na);
        mem = policy_monitor('change', mem, false);
    end
    verifyEqual(tc, [M.degraded, M.deg_quiet, M.alarm], [al, ~al, al]);
end
P2 = PP; P2.q_thr = 8;                                                % the deployed quiet-slot threshold
mem = policy_monitor('init', 1, numel(PP.actions));
for t = 1:5
    [mem, M] = policy_monitor('update', mem, mk_obs(PP, -1, 6, 6, na), P2, na);
    mem = policy_monitor('change', mem, false);
end
verifyEqual(tc, [M.degraded, M.deg_quiet], [false true]);
[~, ~, I] = policy_decide('rule_esc', mk_obs(PP, -1, 6, 0, na), na, [], PP, []);
verifyTrue(tc, isfield(I, 'deg_quiet') && I.deg_quiet);
P3 = PP; P3.deg_mode = 'ratio';
[~, ~, I] = policy_decide('rule_esc', mk_obs(PP, -1, 6, 0, na), na, [], P3, []);
verifyFalse(tc, isfield(I, 'deg_quiet'));
end

function test_class_drop_unchanged(tc)
% The class and drop paths do not depend on deg_mode: on a trace that no mode reads as
% degraded every output but the modes' own fields is that of 'ratio'; on the full trace the
% classes, probabilities and window evidence are the same, and every mode's alarm is the
% hostile class, the drop alarm or its own degradation.
[PP, X] = trace_world();
bq = struct('lo', 0, 'q', 1e-3);
modes = {'ratio', 'win', 'win_q', 'win_q_gate'};
Xl = X;                                                                % no degradation: low BER, no lost packet
for t = 1:numel(Xl.obs), Xl.obs{t}.feat(:, feature_index('log_ber')) = -6; Xl.obs{t}.feat(:, feature_index('crc_fail')) = 0; end
O = cell(1, 4); L = O;
for m = 1:4
    P = PP; P.deg_mode = modes{m}; P.ber_q = bq;
    O{m} = monitor_run(P, X); L{m} = monitor_run(P, Xl);
end
own = {'ebno_win', 'deg_thr', 'deg_quiet'};
for m = 2:4
    for t = 1:numel(X.obs)
        a = L{1}.M{t}; b = L{m}.M{t};
        verifyTrue(tc, isequaln(a, rmfield(b, intersect(own, fieldnames(b)))), sprintf('%s, cycle %d', modes{m}, t));
        verifyTrue(tc, isequaln(rmfield(L{1}.mem{t}, 'hist'), rmfield(L{m}.mem{t}, intersect({'hist', 'eb', 'qi'}, ...
            fieldnames(L{m}.mem{t})))));
    end
end
verifyFalse(tc, any(cellfun(@(M) any(M.degraded), L{1}.M)));
verifyTrue(tc, any(cellfun(@(M) any(M.alarm), L{1}.M)));
for m = 1:4
    for t = 1:numel(X.obs)
        M = O{m}.M{t}; R = O{1}.M{t};
        verifyTrue(tc, isequaln({M.cls, M.probs, M.te, M.ebno_est}, {R.cls, R.probs, R.te, R.ebno_est}));
        h = ~ismember(M.cls, {'none', 'benign_interference', 'unknown'}) & ~(strcmp(M.cls, 'path_loss') & ~M.drop_alarm);
        verifyEqual(tc, M.alarm, h | M.drop_alarm | M.degraded);
    end
end
end

%% ---------- adoption (choose_drop_threshold.m) ----------
function test_adoption_rule(tc)
% The first admissible candidate whose lowest bound is at most 5% is adopted; otherwise the
% admissible one with the lowest bound; none admissible keeps 'ratio'. Admissible: under every
% monitor jamming and tone_jamming lose nothing, any other threat at most 1 point of never and
% 1 cycle of p90; a threat never confirmed has an infinite delay.
lat = @(md, p9, nv) struct('threat', {{'jamming', 'tone_jamming', 'noise_burst'}}, 'n', [10 10 10], ...
    'median', md, 'p90', p9, 'never', nv);
r = lat([1 1 2], [3 3 5], [0 0 0.02]);
R0 = struct('lat', [r r], 'monitor', {{'class_drop 2/2', 'class_drop 5/5'}});
c = @(l1, l2, b) struct('lat', [l1 l2], 'bound', b);
F1 = c(r, r, [0.20 0.12]);                                            % admissible, above 5%
F2a = c(lat([1 1 2], [4 3 5], [0 0 0.02]), r, [0.03 0.2]);           % jamming p90 grows
F2b = c(r, lat([1 1 2], [3 3 6], [0 0 0.029]), [0.04 0.10]);         % within 1 point and 1 cycle
F3a = c(r, r, [0.01 0.01]);
[p, adm, best] = deg_adopt([F1 F2a F2b F3a], R0, 0.05);
verifyEqual(tc, p, 3); verifyEqual(tc, adm, [true false true true]); verifyEqual(tc, best, [0.12 0.03 0.04 0.01]);
[p, ~, ~, fail] = deg_adopt([F1 F2a], R0, 0.05);
verifyEqual(tc, p, 1); verifyEqual(tc, fail{2}, 'class_drop 2/2 jamming');   % none at 5%: the lowest admissible bound
verifyEqual(tc, deg_adopt([F2a F2a], R0, 0.05), 0);                   % none admissible: 'ratio'
verifyEqual(tc, deg_adopt([c(r, r, [0.3 0.08]), c(r, r, [0.08 0.3])], R0, 0.05), 1);   % a tie: the first
bad = {lat([1 1 2], [3 3 5], [0 0 0.031]), lat([1 1 2], [3 3 7], [0 0 0.02]), lat([1 1 2], [3 3 NaN], [0 0 0.02]), ...
    lat([1 2 2], [3 3 5], [0 0 0.02]), lat([1 1 2], [3 3 5], [0 0.001 0.02])};
for i = 1:numel(bad)
    [~, a] = deg_adopt(c(r, bad{i}, [0.01 0.01]), R0, 0.05);
    verifyFalse(tc, a, sprintf('case %d', i));
end
rn = lat([1 1 NaN], [3 3 NaN], [0 0 1]); R1 = struct('lat', [rn rn]);
[~, a] = deg_adopt(c(rn, rn, [0.01 0.01]), R1, 0.05);
verifyTrue(tc, a);                                                    % never confirmed under both: no loss
[~, a] = deg_adopt(c(lat([1 1 2], [2 2 4], [0 0 0]), r, [0.01 0.01]), R0, 0.05);
verifyTrue(tc, a);                                                    % faster is admissible
end

function test_switch_off_keeps_outputs(tc)
% Without "deg_select": true C1d runs nothing new and saves the same variables in the same
% order; the switch is read from profile.json; the clean episodes' default geometries are all.
verifyFalse(tc, deg_options('none.json').on);
f = [tempname '.json'];
write_text(f, '{"deg_select": true}'); verifyTrue(tc, deg_options(f).on);
write_text(f, '{"surv_v2": true}'); verifyFalse(tc, deg_options(f).on);
write_text(f, '{"deg_select": 1}'); verifyError(tc, @() deg_options(f), 'deg_options:value');
delete(f);
src = fileread(which('choose_drop_threshold'));
verifyNotEmpty(tc, strfind(src, ['SV = {''drop_db'', ''drop_db_train'', ''drop_from'', ''separable'', ''THR'', ''kept'', ' ...
    '''leak'', ''leak_all'', ...']));
verifyNotEmpty(tc, strfind(src, ['''p95_mis'', ''p99_cl'', ''p05_pl'', ''floor_db'', ''drop_alarm'', ''cusum_db'', ''THC'', ' ...
    '''VAL'', ''CF'', ''EBNO_THR'', ''MONP'', ''confirm_sweep''};']));
i0 = strfind(src, 'DEG = [];'); i1 = strfind(src, 'if ~isempty(DEG)'); i2 = strfind(src, 'elseif DGon');
verifyNumElements(tc, i0, 1); verifyNumElements(tc, i1, 1); verifyNumElements(tc, i2, 1);
verifyNotEmpty(tc, strfind(src, 'PP.deg_mode = DEG.mode; PP.ber_q = DEG.ber_q;'));
PP = struct('scen', {{'none', 'jamming'}}, 'ebno', [0 3 6]); CT = struct('n_geom', 5);
[s1, n1] = clean_wide_specs(PP, CT, 3, 30);
[s2, n2] = clean_wide_specs(PP, CT, 3, 30, 1:5);
verifyTrue(tc, isequaln(s1, s2) && n1 == n2 && n1 == 10);
[s3, n3] = clean_wide_specs(PP, CT, 3, 30, [2 4]);
verifyEqual(tc, n3, 4); verifyEqual(tc, unique(s3{1}.r), [2 4]);
src = fileread(which('train_dqn'));
verifyNotEmpty(tc, strfind(src, 'if isfield(Dd, ''deg_mode''), PP.deg_mode = Dd.deg_mode; PP.ber_q = Dd.ber_q; end'));
verifyNotEmpty(tc, strfind(src, 'if isfield(PP, ''deg_mode''), dec.deg_mode = PP.deg_mode; dec.ber_q = PP.ber_q; end'));
verifyNotEmpty(tc, strfind(src, 'if isfield(PP, ''deg_mode''), rule_sel.deg_mode = PP.deg_mode; rule_sel.ber_q = PP.ber_q; end'));
end

function test_settings_and_stamp(tc)
% The chosen test reaches every reader through decision_settings.m (an empty deg_mode keeps
% the pools'); the deployed policy's stamp is the parent commit's without it and changes with it.
PP = struct('deg_mode', 'ratio');
X = decision_settings(PP, struct('deg_mode', 'win_q', 'ber_q', struct('lo', 0, 'q', 1e-3)));
verifyEqual(tc, {X.deg_mode, X.ber_q.q}, {'win_q', 1e-3});
verifyEqual(tc, decision_settings(PP, struct('deg_mode', '')).deg_mode, 'ratio');
S = struct('alarm_mode', 'class_drop', 'confirm', [3 3], 'drop_db', 4, 'maha_thr', -2, 'rule_mmse_db', 7.5, ...
    'confirm_sweep', [2 6], 'rule_nb', {{'a', 'b'}});
Q = struct('deployed', 'dqn_esc', 'alarm_mode', 'class_drop', 'confirm', [2 2], 'drop_db', 4, 'det_id', 'x', ...
    'maha_thr', -1, 'dec', S, 'rule_sel', S);
s1 = policy_stamp(Q);
d = parent_copy(tc, 'code/decision/policy_stamp.m', '899e1c6');
addpath(d, '-begin'); clear policy_stamp
cl0 = onCleanup(@() fixture_off(d, 'policy_stamp')); %#ok<NASGU>
s0 = policy_stamp(Q);
fixture_off(d, 'policy_stamp');
verifyEqual(tc, s1, s0);
Q.dec.deg_mode = 'win'; Q.dec.ber_q = [];
s2 = policy_stamp(Q); verifyNotEqual(tc, s2, s1);
Q.dec.deg_mode = 'win_q'; Q.dec.ber_q = struct('lo', 0, 'q', 1e-3);
verifyNotEqual(tc, policy_stamp(Q), s2);
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

function o = mk_obs(PP, lb, e, qi, link)
% One frame: log10 BER lb, measured Eb/N0 estimate e (SINR, no interference over thermal),
% quiet-slot interference qi [dB], class none, received with configuration link.
nF = numel(link_features('names')); nC = numel(PP.classes);
o = struct('probs', [1 zeros(1, nC - 1)], 'unknown', false, 'feat', zeros(1, nF), 'cfg_link', link);
o.feat(feature_index('log_ber')) = lb;
o.feat(feature_index('sinr')) = e - (10*log10(PP.sps) - 10*log10(PP.bps));
o.feat(feature_index('q_iot')) = qi;
end

function [PP, X] = trace_world()
% Four episodes, 30 cycles: random classes, BER, SINR, quiet slot and CRC (episode 4 clean
% with a 10 dB step down at cycle 15: the drop alarm); episode 2 requests fec_interleave at cycle 6, episode 3 power_control at 10 and
% no_action at 20; a request reaches the link one cycle later.
PP = mon_pp(); PP.alarm_mode = 'class_drop'; PP.drop_db = 4; PP.confirm = [2 2]; PP.confirm_sweep = [2 6];
A = PP.actions; na = find(strcmp(A, 'no_action'));
cf = find(strcmp(A, 'fec_interleave')); pc = find(strcmp(A, 'power_control'));
NE = 4; T = 30; nC = numel(PP.classes); nF = numel(link_features('names'));
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

function [CV, fit] = toy_cv()
% Clean validation pools of 20 flights at two Eb/N0 points, 40 frames each, at no_action.
A = policy_actions(); na = find(strcmp(A, 'no_action')); nF = numel(link_features('names'));
runs = 401:420; rs = RandStream('mt19937ar', 'Seed', 9);
CV = struct('set', 'val', 'runs', runs, 'ebno', [3 9], 'actions', {A}, 'created', 'toy', 'n_geom', 20);
CV.pools = cell(1, 2, numel(A));
for s = 1:2
    F = zeros(20 * 40, nF);
    F(:, feature_index('log_ber')) = -3 - s + randn(rs, 800, 1);
    F(:, feature_index('sinr')) = 3 * s + randn(rs, 800, 1);
    CV.pools{1, s, na} = struct('run', repelem(runs, 40)', 'feat', F);
end
fit = clean_halves(runs);
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
