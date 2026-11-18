function tests = test_weak19
%TEST_WEAK19  The DQN's decision-time fixes (dqn_fix.m: PP.dqn_harm, PP.dqn_hop; lb_complete.m and
%   dqn_fix.m step: PP.lb_more), their fresh test set (fresh_set_layout.m, fresh_shadow_seed.m,
%   fresh_splice.m, clean_set_layout.m 'w19', build_policy_pools.m FRESH_SET) and their side reading
%   (weak19_reading.m): off gives the base commit's actions, information, memory and stamp bit for
%   bit; on gives the designed steps under their guards; the fresh flights are no other set's; the
%   registered selection on synthetic readings; the test stage refused before the selection.
%   Synthetic traces in a temporary folder, no pools. Run from the repository root:
%   results = runtests('code/tests/test_weak19.m')
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
tc.TestData.base = 'a987d97';                                    % the commit this branch starts from
end

function teardownOnce(tc)
clear('clean_ber_ref');
cd(tc.TestData.cwd);
if isfolder(tc.TestData.tmp), rmdir(tc.TestData.tmp, 's'); end
end

%% ---------- the options ----------
function test_parse(tc)
for f = {'dqn_harm', 'dqn_hop', 'lb_more'}
    verifyFalse(tc, dqn_fix('parse', f{1}, '').on, f{1});
    verifyFalse(tc, dqn_fix('parse', f{1}, "").on, f{1});
    verifyFalse(tc, dqn_fix('parse', f{1}, []).on, f{1});
end
F = dqn_fix('parse', 'dqn_harm', 'fec'); verifyEqual(tc, {F.on, F.mode, F.name}, {true, 'fec', 'fec'});
F = dqn_fix('parse', 'dqn_hop', "rule"); verifyEqual(tc, {F.on, F.mode}, {true, 'rule'});
F = dqn_fix('parse', 'lb_more', 'step+fec'); verifyEqual(tc, {F.on, F.fec, F.step, F.name}, {true, true, true, 'fec+step'});
F = dqn_fix('parse', 'lb_more', 'step'); verifyEqual(tc, {F.fec, F.step, F.name}, {false, true, 'step'});
verifyError(tc, @() dqn_fix('parse', 'dqn_harm', 'rate'), 'dqn_fix:token');
verifyError(tc, @() dqn_fix('parse', 'dqn_hop', 'fec'), 'dqn_fix:token');
verifyError(tc, @() dqn_fix('parse', 'lb_more', 'fec+fec'), 'dqn_fix:token');
verifyError(tc, @() dqn_fix('parse', 'lb_more', 'rate'), 'dqn_fix:token');
verifyError(tc, @() dqn_fix('parse', 'other', 'q'), 'dqn_fix:field');
verifyError(tc, @() dqn_fix('parse', 'dqn_hop', 3), 'dqn_fix:value');
end

function test_off_bit_identical_to_parent(tc)
% With the three fields absent, '' and "", policy_monitor.m, policy_decide.m and lb_complete.m give the
% base commit's actions, information and last memory bit for bit, for the DQN kinds with and without
% the completion and the lost-branch gate, and for the rule with escalation, on random traces.
d = parent_dir(tc, tc.TestData.base, {'code/decision/policy_monitor.m', 'code/decision/policy_decide.m', ...
    'code/decision/lb_complete.m'});
rs = RandStream('mt19937ar', 'Seed', 23);
C = struct('tag', {}, 'PP', {}, 'X', {}, 'ag', {}, 'kind', {}, 'r', {});
for mode = {'class_drop', 'class_cusum'}
    for lbc = [false true]
        PP = mon_pp(); PP.alarm_mode = mode{1}; if strcmp(mode{1}, 'class_cusum'), PP.drop_db = 153; end
        PP.lb_complete = lbc; PP.s1_gate = lbc;
        X = random_trace(PP, 4, 40, rs); ag = random_agent(PP, rs);
        for kind = {'dqn', 'dqn_esc', 'rule_esc'}
            r = cell(1, 3);
            [r{1}.a, r{1}.i, r{1}.m] = trace_decide(PP, kind{1}, ag, X);
            P1 = PP; P1.dqn_harm = ''; P1.dqn_hop = ''; P1.lb_more = '';
            [r{2}.a, r{2}.i, r{2}.m] = trace_decide(P1, kind{1}, ag, X);
            P2 = PP; P2.dqn_harm = ""; P2.dqn_hop = ""; P2.lb_more = "";
            [r{3}.a, r{3}.i, r{3}.m] = trace_decide(P2, kind{1}, ag, X);
            C(end+1) = struct('tag', sprintf('%s lb %d %s', mode{1}, lbc, kind{1}), 'PP', PP, 'X', {X}, 'ag', ag, ...
                'kind', kind{1}, 'r', {r}); %#ok<AGROW>
        end
    end
end
addpath(d, '-begin'); clear policy_monitor policy_decide lb_complete
cl = onCleanup(@() fixture_off(d, {'policy_monitor', 'policy_decide', 'lb_complete'})); %#ok<NASGU>
verifyEqual(tc, which('policy_decide'), fullfile(d, 'policy_decide.m'));
moved = false(1, numel(C));
for k = 1:numel(C)
    [p.a, p.i, p.m] = trace_decide(C(k).PP, C(k).kind, C(k).ag, C(k).X);
    for v = 1:3
        verifyTrue(tc, isequaln(C(k).r{v}, p), sprintf('%s, variant %d', C(k).tag, v));
    end
    moved(k) = numel(unique(p.a(:))) > 1;
end
fixture_off(d, {'policy_monitor', 'policy_decide', 'lb_complete'});
verifyTrue(tc, any(moved));
end

%% ---------- dqn_harm ----------
function test_harm_layer(tc)
% A lost branch with harm evidence held at no_action for C.esc confirmed cycles takes one step: the
% rule's answer (power_control; with space where separable), with fec_interleave, or the best Q;
% every guard is needed.
PP = mon_pp(); A = PP.actions; na = find(strcmp(A, 'no_action')); C = decision_config();
at = @(n) find(strcmp(A, n));
[M, m] = harm_state(PP, 'antenna_fault');
q = zeros(numel(A), 1); q(at('channel_switch')) = 3; q(at('power_control')) = 2;
call = @(F, M, m, g) dqn_fix('harm', na, na, M, m, PP, F, q, g, 0, 3, 6, true);
[a, acted] = call('rule', M, m, 0); verifyTrue(tc, acted); verifyEqual(tc, A{a}, 'power_control');
[a, ~] = call('rule', M, m, 8); verifyEqual(tc, A{a}, 'spatial_diversity+power_control');
[a, ~] = call('fec', M, m, 0); verifyEqual(tc, A{a}, 'power_control+fec_interleave');
[a, ~] = call('fec', M, m, 8); verifyEqual(tc, A{a}, 'spatial_diversity+power_control+fec_interleave');
[a, ~, m2] = call('q', M, m, 0); verifyEqual(tc, A{a}, 'channel_switch');
verifyTrue(tc, m2.tried(1, at('channel_switch')) && m2.tried(1, na));
[~, acted] = call('q', M, m2, 0); verifyTrue(tc, acted);         % the next not tried
[a, ~] = call('q', M, m2, 0); verifyEqual(tc, A{a}, 'power_control');
[M2, ~] = harm_state(PP, 'airframe_shadowing');
[a, acted] = call('rule', M2, m, 0); verifyTrue(tc, acted); verifyEqual(tc, A{a}, 'power_control');
% guards
G = {'harm', false; 'confirmed', false};
for k = 1:size(G, 1)
    Mx = M; Mx.(G{k, 1}) = G{k, 2};
    [~, acted] = call('rule', Mx, m, 0); verifyFalse(tc, acted, G{k, 1});
end
for c = {'none', 'jamming', 'path_loss', 'unknown'}
    [Mx, ~] = harm_state(PP, c{1});
    [~, acted] = call('rule', Mx, m, 0); verifyFalse(tc, acted, c{1});
end
B = {'conf_n', C.esc - 1; 'since', C.esc - 1; 'pend', true};
for k = 1:size(B, 1)
    mx = m; mx.(B{k, 1}) = B{k, 2};
    [~, acted] = call('rule', M, mx, 0); verifyFalse(tc, acted, B{k, 1});
end
mx = m; mx.tried(1, at('power_control')) = true;
[~, acted] = call('rule', M, mx, 0); verifyFalse(tc, acted, 'tried');
[~, acted] = dqn_fix('harm', at('power_control'), na, M, m, PP, 'rule', q, 0, 0, 3, 6, true); verifyFalse(tc, acted, 'the DQN acted');
[~, acted] = dqn_fix('harm', na, at('power_control'), M, m, PP, 'rule', q, 0, 0, 3, 6, true); verifyFalse(tc, acted, 'not at no_action');
[a, acted] = call('', M, m, 0); verifyFalse(tc, acted); verifyEqual(tc, a, na);
verifyFalse(tc, any(call('rule', rmfield(M, 'harm'), m, 0) ~= na), 'no harm reading, no step');
end

function test_harm_in_the_loop(tc)
% policy_decide.m: a DQN that holds no_action on a harmful antenna fault never moves off; with
% dqn_harm 'rule' it takes power_control once C.esc confirmed cycles passed, and the monitor reads
% the harm evidence for it alone.
PP = mon_pp(); A = PP.actions; na = find(strcmp(A, 'no_action'));
ag = const_agent(PP, 'no_action');
X = const_trace(PP, 12, -1, 8, 0, 'antenna_fault', na);
R0 = decide_run('dqn', PP, X, ag);
verifyTrue(tc, all(R0.a(:) == na));
P1 = PP; P1.dqn_harm = 'rule';
R1 = decide_run('dqn', P1, X, ag);
t = find(R1.a ~= na, 1);
verifyNotEmpty(tc, t);
verifyEqual(tc, A{R1.a(t)}, 'power_control');
verifyGreaterThanOrEqual(tc, t, decision_config().esc);
verifyTrue(tc, R1.I{t}.dh);
verifyEqual(tc, nnz(cellfun(@(I) any(I.dh), R1.I)), 1);           % one step
Xn = const_trace(PP, 12, -6, 8, 0, 'antenna_fault', na);           % a lost branch the others carry: no harm
Rn = decide_run('dqn', P1, Xn, ag);
verifyTrue(tc, all(Rn.a(:) == na));
end

%% ---------- dqn_hop ----------
function test_hop_layer(tc)
% A hop held for C.esc degraded cycles from its first frame under an in-channel class leaves the
% frequency domain: space where separable and the largest link budget, or the best Q without a
% frequency element; every guard is needed.
PP = mon_pp(); A = PP.actions; C = decision_config(); nA = numel(A);
at = @(n) find(strcmp(A, n));
cs = at('channel_switch');
M = struct('cls', {{'jamming'}}, 'confirmed', true, 'degraded', true);
m = struct('deg_n', C.esc, 'since', C.esc, 'pend', false, 'tried', false(1, nA));
q = zeros(nA, 1); q(at('freq_diversity')) = 5; q(at('spatial_diversity+power_control')) = 2;
call = @(F, a, cfg, M, m, g) dqn_fix('hop', a, cfg, M, m, PP, F, q, g, 6);
[a, acted] = call('rule', cs, cs, M, m, 0); verifyTrue(tc, acted); verifyEqual(tc, A{a}, 'rate_reduce+power_control');
[a, ~] = call('rule', cs, cs, M, m, 8); verifyEqual(tc, A{a}, 'spatial_diversity+rate_reduce+power_control');
[a, ~] = call('rule', cs, at('channel_switch+spatial_diversity'), M, m, 0);   % the null in use is kept
verifyEqual(tc, A{a}, 'spatial_diversity+rate_reduce+power_control');
[a, ~] = call('q', cs, cs, M, m, 0); verifyEqual(tc, A{a}, 'spatial_diversity+power_control');
[a, acted] = call('rule', at('freq_diversity'), cs, M, m, 0); verifyTrue(tc, acted, 'the DQN hops again');
verifyEqual(tc, A{a}, 'rate_reduce+power_control');
for c = {'reactive_jamming', 'spoofing', 'tone_jamming'}
    Mx = M; Mx.cls = c; [~, acted] = call('rule', cs, cs, Mx, m, 0); verifyTrue(tc, acted, c{1});
end
for c = {'none', 'benign_interference', 'antenna_fault', 'path_loss', 'sweeping_jammer'}
    Mx = M; Mx.cls = c; [~, acted] = call('rule', cs, cs, Mx, m, 0); verifyFalse(tc, acted, c{1});
end
Mx = M; Mx.confirmed = false; [~, acted] = call('rule', cs, cs, Mx, m, 0); verifyFalse(tc, acted, 'confirmed');
B = {'deg_n', C.esc - 1; 'since', C.esc - 1; 'pend', true};
for k = 1:size(B, 1)
    mx = m; mx.(B{k, 1}) = B{k, 2}; [~, acted] = call('rule', cs, cs, M, mx, 0); verifyFalse(tc, acted, B{k, 1});
end
[~, acted] = call('rule', at('power_control'), at('power_control'), M, m, 0); verifyFalse(tc, acted, 'no hop in use');
[~, acted] = call('rule', at('spatial_diversity'), cs, M, m, 0); verifyFalse(tc, acted, 'the DQN left the hop');
mx = m; mx.tried(at('rate_reduce+power_control')) = true;
[~, acted] = call('rule', cs, cs, M, mx, 0); verifyFalse(tc, acted, 'tried');
[a, acted] = call('', cs, cs, M, m, 0); verifyFalse(tc, acted); verifyEqual(tc, a, cs);
end

%% ---------- lb_more ----------
function test_lb_more_fec(tc)
% A proposal holding fec_interleave: off, the completion leaves it; with fec, power_control +
% fec_interleave where its gain covers the deficit, else the link-budget match without the code.
PP = mon_pp(); PP.lb_complete = true; A = PP.actions; C = decision_config();
at = @(n) find(strcmp(A, n)); na = at('no_action');
F = dqn_fix('parse', 'lb_more', 'fec');
m = struct('lb_dc', 3.5, 'drop_n', C.esc, 'since', C.hold, 'pend', false);
M = struct('confirmed', true, 'drop_alarm', true);
[a, acted] = lb_complete(at('fec_interleave'), na, M, m, PP); verifyFalse(tc, acted); verifyEqual(tc, A{a}, 'fec_interleave');
[a, acted] = lb_complete(at('fec_interleave'), na, M, m, PP, F); verifyTrue(tc, acted); verifyEqual(tc, A{a}, 'power_control+fec_interleave');
[a, ~] = lb_complete(at('channel_switch+fec_interleave'), na, M, m, PP, F); verifyEqual(tc, A{a}, 'channel_switch+power_control+fec_interleave');
m.lb_dc = 8;
[a, ~] = lb_complete(at('fec_interleave'), na, M, m, PP, F); verifyEqual(tc, A{a}, 'rate_reduce+power_control');
[a, ~] = lb_complete(at('power_control+fec_interleave'), na, M, m, PP, F); verifyEqual(tc, A{a}, 'rate_reduce+power_control');
[a, ~] = lb_complete(at('spatial_diversity+fec_interleave'), na, M, m, PP, F); verifyEqual(tc, A{a}, 'spatial_diversity+rate_reduce+power_control');
m.lb_dc = 5;                                                     % no fec: as without the option
for n = {'no_action', 'channel_switch', 'spatial_diversity+power_control'}
    [a0, x0] = lb_complete(at(n{1}), na, M, m, PP); [a1, x1] = lb_complete(at(n{1}), na, M, m, PP, F);
    verifyEqual(tc, [a1 x1], [a0 x0], n{1});
end
[a, ~] = lb_complete(at('fec_interleave'), na, M, m, PP, dqn_fix('parse', 'lb_more', 'step')); verifyEqual(tc, a, at('fec_interleave'));
end

function test_lb_more_step(tc)
% Where the completion did not act and the DQN keeps a configuration the link stays degraded on
% under a confirmed drop alarm: rate_reduce is added (rate_reduce+power_control in place of a code).
PP = mon_pp(); A = PP.actions; C = decision_config(); at = @(n) find(strcmp(A, n));
M = struct('confirmed', true, 'drop_alarm', true);
m = struct('lb_dc', 5, 'drop_n', C.esc, 'hq_n', C.esc, 'since', C.hold, 'pend', false);
cases = {'power_control', 'rate_reduce+power_control'; 'channel_switch+power_control', 'channel_switch+rate_reduce+power_control'; ...
    'channel_switch', 'channel_switch+rate_reduce'; 'power_control+fec_interleave', 'rate_reduce+power_control'; ...
    'freq_diversity+spatial_diversity+power_control+fec_interleave', 'freq_diversity+spatial_diversity+rate_reduce+power_control'};
for k = 1:size(cases, 1)
    c = at(cases{k, 1});
    [a, acted] = dqn_fix('step', c, c, M, m, PP, false);
    verifyTrue(tc, acted, cases{k, 1}); verifyEqual(tc, A{a}, cases{k, 2}, cases{k, 1});
end
c = at('rate_reduce'); [~, acted] = dqn_fix('step', c, c, M, m, PP, false); verifyFalse(tc, acted, 'rate_reduce held');
c = at('power_control');
[~, acted] = dqn_fix('step', c, c, M, m, PP, true); verifyFalse(tc, acted, 'the completion acted');
[~, acted] = dqn_fix('step', at('rate_reduce'), c, M, m, PP, false); verifyFalse(tc, acted, 'the DQN moved');
B = {'hq_n', C.esc - 1; 'drop_n', C.esc - 1; 'since', C.hold - 1; 'pend', true; 'lb_dc', 2.9};
for k = 1:size(B, 1)
    mx = m; mx.(B{k, 1}) = B{k, 2}; [~, acted] = dqn_fix('step', c, c, M, mx, PP, false); verifyFalse(tc, acted, B{k, 1});
end
for f = {'confirmed', 'drop_alarm'}
    Mx = M; Mx.(f{1}) = false; [~, acted] = dqn_fix('step', c, c, Mx, m, PP, false); verifyFalse(tc, acted, f{1});
end
[~, acted] = dqn_fix('step', c, c, M, rmfield(m, 'hq_n'), PP, false); verifyFalse(tc, acted, 'no counter');
end

function test_monitor_counter_only_with_step(tc)
% mem.hq_n exists only with lb_more's step (and the completion): cleared on a configuration's first
% frame, counting degraded cycles.
PP = mon_pp(); PP.lb_complete = true; na = find(strcmp(PP.actions, 'no_action'));
X = const_trace(PP, 8, -1, 8, 0, 'none', na);
ag = const_agent(PP, 'no_action');
R0 = decide_run('dqn', PP, X, ag); verifyFalse(tc, isfield(R0.mem, 'hq_n'));
P1 = PP; P1.lb_more = 'fec'; R1 = decide_run('dqn', P1, X, ag); verifyFalse(tc, isfield(R1.mem, 'hq_n'));
P2 = PP; P2.lb_more = 'step'; R2 = decide_run('dqn', P2, X, ag);
verifyTrue(tc, isfield(R2.mem, 'hq_n'));
verifyEqual(tc, R2.mem.hq_n, 8);
src = fileread(which('policy_monitor'));
verifyNumElements(tc, regexp(src, 'mem\.hq_n(\([^)]*\))?\s*=(?!=)'), 4);   % its writes, all in lb_track
i0 = strfind(src, 'function mem = lb_track('); i1 = regexp(src(i0:end), '\nfunction ', 'once');
verifyNumElements(tc, regexp(src(i0:i0 + i1), 'mem\.hq_n(\([^)]*\))?\s*=(?!=)'), 4);
end

%% ---------- settings and stamp ----------
function test_settings_and_stamp(tc)
P = decision_settings(struct('a', 1), struct('dqn_harm', 'rule', 'dqn_hop', 'q', 'lb_more', 'step'));
verifyEqual(tc, {P.dqn_harm, P.dqn_hop, P.lb_more}, {'rule', 'q', 'step'});
verifyFalse(tc, isfield(decision_settings(struct('a', 1), struct('rule_fix', '')), 'dqn_harm'));
Q = stamp_q();
s0 = policy_stamp(Q);
for f = {'dqn_harm', 'dqn_hop', 'lb_more'}
    Qx = Q; Qx.dec.(f{1}) = ''; verifyEqual(tc, policy_stamp(Qx), s0, f{1});
    Qx.dec.(f{1}) = ""; verifyEqual(tc, policy_stamp(Qx), s0, f{1});
end
Qa = Q; Qa.dec.dqn_harm = 'rule'; verifyNotEqual(tc, policy_stamp(Qa), s0);
Qb = Q; Qb.dec.lb_more = 'step+fec'; Qc = Q; Qc.dec.lb_more = 'fec+step';
verifyEqual(tc, policy_stamp(Qb), policy_stamp(Qc));
verifyNotEqual(tc, policy_stamp(Qb), s0);
d = parent_dir(tc, tc.TestData.base, {'code/decision/policy_stamp.m'});
addpath(d, '-begin'); clear policy_stamp
cl = onCleanup(@() fixture_off(d, {'policy_stamp'})); %#ok<NASGU>
verifyEqual(tc, policy_stamp(Q), s0, 'the base commit''s stamp');
end

%% ---------- the fresh test set ----------
function test_fresh_layout(tc)
L = fresh_set_layout();
verifyEqual(tc, {L.fam, L.block, L.ngeo, L.lhs_seed, L.out, L.clean}, {4, 14, 24, 7400000, 'data/fresh_test_pools.mat', 'w19'});
Ls = fresh_set_layout(true);
verifyEqual(tc, {Ls.fam, Ls.block, Ls.ngeo}, {4, 18, 2}); verifyNotEqual(tc, Ls.out, L.out);
[sp, fm, fo] = clean_set_layout('w19'); verifyEqual(tc, {sp, fm, fo}, {17, [7 8 9], 'data/clean_w19_pools.mat'});
[sp, fm] = clean_set_layout('w19', true); verifyEqual(tc, {sp, fm}, {16, [7 8 9]});
own = {4, 14, 'fresh_threat'; 4, 18, 'fresh_threat'; 7, 17, 'w19'; 9, 16, 'w19'; 7, 15, 'fresh'; 1, 14, 'pools'; ...
    6, 14, 'core_bw'; 4, 15, ''; 7, 19, ''; 7, 4, ''; 4, 10, ''};
for i = 1:size(own, 1)
    verifyEqual(tc, pool_seed_owner(own{i, 1}, own{i, 2}), own{i, 3}, sprintf('family %d block %d', own{i, 1}, own{i, 2}));
end
end

function test_fresh_seeds_disjoint(tc)
% The fresh flights (family 4 of block 14, 24 per Eb/N0; the smoke's of block 18), the w19 clean
% flights (families 7, 8, 9 of block 17; the smoke's of block 16) and the fresh shadowing candidates
% are no seed of any other set test_core lists; all below 2^26, their streams below 2^32, and the
% fresh designs' permutation streams distinct from the pools' and the check flights'.
S = other_seeds();
[s, r] = ndgrid(1:8, 1:99);
F = arrayfun(@(si, ri) pool_seed(4, si, 14, ri), s(:), r(:));
Fs = arrayfun(@(si, ri) pool_seed(4, si, 18, ri), s(:), r(:));
[s, k] = ndgrid(1:8, 1:300);
Wc = arrayfun(@(si, ki) clean_pool_seed(si, 17, ki, [], [7 8 9]), s(:), k(:));
Ws = arrayfun(@(si, ki) clean_pool_seed(si, 16, ki, [], [7 8 9]), s(:), k(:));
N = [F; Fs; Wc; Ws];
verifyEqual(tc, numel(unique(N)), numel(N));
verifyEmpty(tc, intersect(N, S));
verifyLessThan(tc, max(N), 2000000);
[g, s] = ndgrid(1:8, 1:8);
lo = arrayfun(@(gi, si) fresh_shadow_seed(gi, si, 1), g(:), s(:)); hi = arrayfun(@(gi, si) fresh_shadow_seed(gi, si, 59999), g(:), s(:));
[lo, o] = sort(lo); hi = hi(o);
verifyTrue(tc, all(hi(1:end-1) < lo(2:end)));
verifyEqual(tc, [lo(1) hi(end)], [63000001 66839999]);
pool_hi = shadow_pool_seed(8, 8, 19, 99999); surv_lo = surv3_shadow_seed(1, 1); surv_hi = surv3_shadow_seed(8, 99999);
verifyGreaterThan(tc, lo(1), max([pool_hi, surv_hi]));
verifyLessThan(tc, surv_lo, lo(1));
verifyLessThan(tc, hi(end), 2^26);
verifyLessThan(tc, seed_base(hi(end)) + 63, 2^32);
verifyError(tc, @() fresh_shadow_seed(1, 1, 60000), ?MException);
verifyError(tc, @() fresh_shadow_seed(9, 1, 1), ?MException);
[s, sp, gi, pt] = ndgrid(1:8, 1:5, 1:7, 1:2);
L0 = [7100000 + 100 * s(:) + 10 * (gi(:) + 1) + sp(:) + 5 * (pt(:) - 1); reshape(7100000 + 100 * (1:8)' + [1:5, 11:15], [], 1); ...
    reshape(7200000 + 100 * (1:8)' + (0:7), [], 1)];
[s, gi, pt] = ndgrid(1:8, 1:7, 1:2);
L1 = [7400000 + 100 * s(:) + 10 * (gi(:) + 1) + 3 + 5 * (pt(:) - 1); 7400000 + 100 * (1:8)' + 3];
verifyEmpty(tc, intersect(L0, L1));
verifyLessThan(tc, max(L1), seed_base(700001));
end

function test_fresh_splice(tc)
% The fresh split replaces the test split alone; the other splits stay; a smoke build, another
% detector, another cell list or a flight of the tree's test split is refused.
[PP, FT] = splice_world();
P = fresh_splice(PP, FT);
verifyEqual(tc, P.pools(:, :, :, 3), FT.pools);
verifyEqual(tc, P.pools(:, :, :, [1 2]), PP.pools(:, :, :, [1 2]));
verifyEqual(tc, P.runs{3}, FT.runs); verifyEqual(tc, P.runs{1}, PP.runs{1});
verifyEqual(tc, P.cov{3}, FT.cov); verifyEqual(tc, P.cell_geo{2}{3}, FT.cell_geo{2}); verifyEqual(tc, P.cell_geo{2}{1}, PP.cell_geo{2}{1});
verifyEqual(tc, P.ngeo(3), FT.ngeo); verifyTrue(tc, all(isnan(P.mber(:, :, :, 3)), 'all'));
verifyEqual(tc, P.fresh.block, 14);
bad = {'det_id', 'x'; 'smoke', true; 'scen', {'none', 'tone_jamming'}; 'model_tag', 'other'};
for k = 1:size(bad, 1)
    Fx = FT; Fx.(bad{k, 1}) = bad{k, 2};
    verifyError(tc, @() fresh_splice(PP, Fx), 'fresh_splice:mismatch', bad{k, 1});
end
Fx = FT; Fx.cov.seed(1, 1) = PP.cov{3}.seed(2, 2);
verifyError(tc, @() fresh_splice(PP, Fx), 'fresh_splice:mismatch', 'a test flight');
end

function test_builder_wiring(tc)
% build_policy_pools.m: off, the geometry family is 1 for every split (pool_geometries.m's default)
% and the design streams are LHS_SEED's; the fresh set is laid out by fresh_set_layout.m, flies the
% test split alone, never reuses or writes data/policy_pools.mat, and draws its own shadowing
% candidates; no chain stage sets FRESH_SET or CLEAN_SET 'w19'.
src = strrep(fileread(which('build_policy_pools')), char(13), '');
for t = {'FRESH = exist(''FRESH_SET'', ''var'') && isequal(FRESH_SET, true);', ...
        'FAM = ones(1, numel(SPLITS)); LHS_B = LHS_SEED * ones(1, numel(SPLITS));', ...
        'FL = fresh_set_layout(exist(''SMOKE'', ''var'') && SMOKE);', ...
        'if FRESH, cells(c).splits = intersect(cells(c).splits, 3); end', ...
        'if ~FRESH && isfile(''data/policy_pools.mat'')', ...
        'sel.seed = @(j, v) fresh_shadow_seed(gi, s, j, v);', ...
        'pool_checkpoint(''commit'', FL.out, struct(''FT'', FT));'}
    verifyNumElements(tc, strfind(src, t{1}), 1, t{1});
end
i0 = regexp(src, 'if FRESH\s+% the fresh test split alone', 'once');
i1 = strfind(src, 'pool_checkpoint(''commit'', ''data/policy_pools.mat''');
verifyLessThan(tc, i0, i1);
verifyNotEmpty(tc, regexp(src(i0:i1), '\n    return\n', 'once'));
rs = fileread(which('run_stage')); mn = fileread(which('main'));
for t = {'FRESH_SET', '''w19'''}
    verifyEmpty(tc, strfind(rs, t{1}), t{1}); verifyEmpty(tc, strfind(mn, t{1}), t{1});
end
end

%% ---------- the reading ----------
function test_reading_registered(tc)
R = weak19_reading('reg');
verifyEqual(tc, {R.steps.field}, {'dqn_harm', 'dqn_hop', 'lb_more'});
verifyEqual(tc, {R.steps.target}, {'lost_harmed', 'comb', 'path_loss'});
verifyEqual(tc, R.steps(1).cand, {'q', 'rule', 'fec'});
verifyEqual(tc, R.fph, 470); verifyEqual(tc, R.bound, 0.05); verifyEqual(tc, R.B, 2000);
for k = 1:numel(R.steps)                                           % every candidate is a valid setting
    for c = R.steps(k).cand, verifyTrue(tc, dqn_fix('parse', R.steps(k).field, c{1}).on); end
end
verifyNotEqual(tc, R.fresh_rs, R.test_rs);
verifyNotEqual(tc, R.comb_seed, R.val_seed);
end

function test_reading_select(tc)
% (2) lifts the harmed lost-branch episodes alone: adopted; (3) the same, with path_loss down 10
% points: (b) fails; (4) the same, 60 more clean flights with a change: (d) fails; (5) the same,
% over the limit of false changes per hour: (e) fails; (6) a gain on non-target episodes only: (a)
% fails.
[T, W] = select_world();
S = weak19_reading('select', T);
verifyEqual(tc, S.pass, [false true false false false false]);
verifyEqual(tc, S.best, 2);
verifyTrue(tc, S.adopt{2}.a && S.adopt{2}.b && S.adopt{2}.c && S.adopt{2}.d && S.adopt{2}.e);
verifyFalse(tc, S.adopt{3}.b); verifyFalse(tc, S.adopt{4}.d); verifyFalse(tc, S.adopt{5}.e); verifyFalse(tc, S.adopt{6}.a);
A = weak19_reading('adopt', T.read(2).x, T.read(1).x, 'lost_harmed', W);
verifyGreaterThan(tc, A.gain, 0);
T2 = T; T2.read = T.read([1 3 4 5 6]);
S2 = weak19_reading('select', T2);
verifyEqual(tc, S2.best, 1);                                       % nothing passes: the setting in force stays
end

function test_reading_refuses_test_before_selection(tc)
tree = tempname; mkdir(tree); cl = onCleanup(@() rmdir(tree, 's')); %#ok<NASGU>
X = weak19_reading('paths', tree, 'w19test');
J = weak19_reading('guard', X);
verifyEqual(tc, J, {'no frozen selection (run the val stage first)'});
verifyError(tc, @() weak19_reading('test', tree, 'w19test'), 'weak19_reading:guard');
verifyError(tc, @() weak19_reading('paths', tree, 'bad tag'), 'weak19_reading:tag');
verifyTrue(tc, endsWith(strrep(X.fresh{1}, '\', '/'), 'data/fresh_test_pools.mat'));
verifyTrue(tc, endsWith(strrep(X.fresh{2}, '\', '/'), 'data/clean_w19_pools.mat'));
verifyNotEqual(tc, X.claim_val, X.claim_test);
verifyNotEqual(tc, X.claim_test, read_once('claim', 'rule_fix', 'test', tree));
end

%% ---------- helpers ----------
function PP = mon_pp()
A = policy_actions();
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
g = 4 * contains(A, 'power_control') + 6.02 * contains(A, 'rate_reduce');
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'cfg_gain_db', g, ...
    'alarm_mode', 'class_drop', 'drop_db', 4, 'confirm', [2 2], 'confirm_sweep', [2 6]);
end

function [M, m] = harm_state(PP, cls)
C = decision_config(); nA = numel(PP.actions);
M = struct('cls', {{cls}}, 'harm', true, 'confirmed', true, 'degraded', true);
m = struct('conf_n', C.esc, 'since', C.esc, 'pend', false, 'tried', false(1, nA));
end

function o = mk_obs(PP, lb, e, qi, link, cls)
nF = numel(link_features('names')); nC = numel(PP.classes);
p = zeros(1, nC); p(find(strcmp(PP.classes, cls), 1)) = 1;
o = struct('probs', p, 'unknown', false, 'feat', zeros(1, nF), 'cfg_link', link);
o.feat(feature_index('log_ber')) = lb;
o.feat(feature_index('sinr')) = e - (10*log10(PP.sps) - 10*log10(PP.bps));
o.feat(feature_index('q_iot')) = qi;
o.idle = nan(1, numel(idle_summary('names')));
end

function X = const_trace(PP, T, lb, e, qi, cls, cfg0)
X = struct('obs', {cell(1, T)}, 'cfg0', cfg0);
for t = 1:T, X.obs{t} = mk_obs(PP, lb, e, qi, cfg0, cls); end
end

function R = decide_run(kind, PP, X, agent)
% policy_decide.m over the cycles of X, the request fed back as the next cycle's configuration.
T = numel(X.obs); cfg = X.cfg0(:)'; NE = numel(cfg); mem = [];
R = struct('a', zeros(NE, T), 'I', {cell(1, T)}, 'mem', []);
for t = 1:T
    o = X.obs{t}; o.cfg_link = cfg(:);
    [a, mem, I] = policy_decide(kind, o, cfg, mem, PP, agent, struct());
    R.a(:, t) = a(:); R.I{t} = I; cfg = a(:)';
end
R.mem = mem;
end

function ag = const_agent(PP, name)
nA = numel(PP.actions); nS = policy_state_size(nA, numel(PP.classes));
q = zeros(nA, 1); q(strcmp(PP.actions, name)) = 1;
ag = struct('dense', struct('mu', zeros(nS, 1), 'sd', ones(nS, 1), 'W', {{zeros(2, nS), zeros(nA, 2)}}, 'b', {{zeros(2, 1), q}}));
end

function ag = random_agent(PP, rs)
nA = numel(PP.actions); nS = policy_state_size(nA, numel(PP.classes));
ag = struct('dense', struct('mu', zeros(nS, 1), 'sd', ones(nS, 1), 'W', {{0.3 * randn(rs, 16, nS), randn(rs, nA, 16)}}, ...
    'b', {{randn(rs, 16, 1), randn(rs, nA, 1)}}));
end

function X = random_trace(PP, NE, T, rs)
% NE episodes of T cycles: random class probabilities (a lost branch, a jammer and path loss
% among the likely ones), BER, SINR with steps, quiet slot, CRC and three antennas' gains.
nC = numel(PP.classes); nF = numel(link_features('names'));
lk = find(ismember(PP.classes, {'antenna_fault', 'jamming', 'path_loss', 'none'}));
X = cell(1, T); step = 6 * randi(rs, [0 2], NE, 1); k0 = randi(rs, [8 20], NE, 1); on = randi(rs, [0 1], NE, 3);
for t = 1:T
    p = rand(rs, NE, nC) .^ 4; j = lk(randi(rs, numel(lk), NE, 1));
    p(sub2ind([NE nC], (1:NE)', j(:))) = p(sub2ind([NE nC], (1:NE)', j(:))) + 0.7; p = p ./ sum(p, 2);
    o = struct('probs', p, 'unknown', false(NE, 1), 'feat', zeros(NE, nF));
    d = step .* (t >= k0);
    o.feat(:, feature_index('log_ber')) = -5 + 4 * rand(rs, NE, 1);
    o.feat(:, feature_index('sinr')) = 6 + randn(rs, NE, 1) - d;
    o.feat(:, feature_index('q_iot')) = 6 * rand(rs, NE, 1) - 1;
    o.feat(:, feature_index('crc_fail')) = rand(rs, NE, 1) < 0.2;
    o.gant = 1 + randn(rs, NE, 3) - d .* (1 + on) / 2;
    X{t} = o;
end
end

function [A, I, M] = trace_decide(PP, kind, ag, X)
NE = size(X{1}.feat, 1); T = numel(X);
na = find(strcmp(PP.actions, 'no_action'));
cfg = na * ones(1, NE); mem = [];
A = zeros(T, NE); I = cell(1, T);
for t = 1:T
    o = X{t}; o.cfg_link = cfg;
    [cfg, mem, I{t}] = policy_decide(kind, o, cfg, mem, PP, ag, struct());
    A(t, :) = cfg;
end
M = mem;
end

function Q = stamp_q()
A = policy_actions();
Q = struct('deployed', 'dqn', 'alarm_mode', 'class_drop', 'confirm', [2 2], 'drop_db', 4, 'det_id', 'd', 'maha_thr', 1, ...
    'dec', struct('confirm_sweep', [], 'unk_mode', 'all', 'unk_retain', 0.95, 'rule_mmse_db', 6, 'rule_slot', true, ...
    'rule_dwell', 'run', 'esc_drop', false, 'lb_complete', true), 'agent', struct('dense', struct('W', {{1}})), 'actions', {A});
end

function S = other_seeds()
% The flight seeds test_core's test_seed_streams_disjoint lists for the pools and the clean sets.
[s, r, b] = ndgrid(1:8, 1:99, 1:19);
S = arrayfun(@(si, ri, bi) pool_seed(1, si, bi, ri), s(:), r(:), b(:));
[s, r] = ndgrid(1:8, 1:99); S = [S; arrayfun(@(si, ri) pool_seed(2, si, 10, ri), s(:), r(:))];
[s, b] = ndgrid(1:8, [4 15]); S = [S; arrayfun(@(si, bi) pool_seed(1, si, bi, 100), s(:), b(:))];
[s, r, b, f] = ndgrid(1:8, 1:100, [4 15], [3 5]); S = [S; arrayfun(@(si, ri, bi, fi) pool_seed(fi, si, bi, ri), s(:), r(:), b(:), f(:))];
[s, r, b, f] = ndgrid(1:8, 1:100, [15 18], [7 8 9]); S = [S; arrayfun(@(si, ri, bi, fi) pool_seed(fi, si, bi, ri), s(:), r(:), b(:), f(:))];
[s, r, b] = ndgrid(1:8, 1:99, [5 7 14 16 18 19]); S = [S; arrayfun(@(si, ri, bi) pool_seed(6, si, bi, ri), s(:), r(:), b(:))];
[t, li, s] = ndgrid(1:20, 1:10, 1:6); S = [S; 900000 + 1000*t(:) + 10*li(:) + s(:); 700000 + (1:5)'];
[t, r] = ndgrid(1:20, 1:5); S = [S; 900000 + 1000*t(:) + r(:)];
k = (1:99999)'; S = [S; 3000000 + k; 4000000 + k; 5000000 + k; 3500000 + k; 4500000 + k; 5500000 + k; 6500000 + k; 6000000 + k];
end

function [PP, FT] = splice_world()
% Tree pools of two cells (none, jamming), two Eb/N0, two configurations, three splits, and a fresh
% test split of the same layout, one geometry longer.
z = @(n) cell(2, 2, 2, n);
PP = struct('scen', {{'none', 'jamming'}}, 'sev', [3 3], 'level', [NaN 1], 'ebno', [0 3], 'actions', {{'no_action', 'x'}}, ...
    'det_id', 'D', 'model_tag', 'v7', 'fec_rx', struct('mode', 'd78'), 'pools', {z(3)}, 'runs', {{101:102, 501:502, 1401:1402}}, ...
    'cov', {{struct('seed', [1 2; 3 4]), struct('seed', [5 6; 7 8]), struct('seed', [11 12; 13 14], 'alt_m', 1, 'k_sig', 2)}}, ...
    'speed', {{1, 2, 3}}, 'alt', {{1, 2, 3}}, 'ksig', {{1, 2, 3}}, 'event_frame', {{[NaN NaN], [NaN NaN], [NaN NaN]}}, ...
    'ref_geo', {{[], [], []}}, 'cell_geo', {{{1:2, 1:2, 1:2}, {1:2, 1:2, 1:2}}}, 'ngeo', [2 2 2], 'mber', zeros(2, 2, 2, 3), ...
    'mfer', zeros(2, 2, 2, 3));
PP.pools(:) = {struct('ber', 1)};
P3 = cell(2, 2, 2); P3(:) = {struct('ber', 2)};
FT = struct('pools', {P3}, 'runs', 1401:1403, 'cov', struct('seed', [21 22 23; 24 25 26], 'alt_m', 5, 'k_sig', 6), 'speed', 9, ...
    'event_frame', [NaN NaN NaN], 'ref_geo', [], 'cell_geo', {{1:3, 1:3}}, 'ngeo', 3, 'block', 14, 'fam', 4, 'lhs_seed', 7400000, ...
    'seed', {{[21 22 23], [24 25 26]}}, 'scen', {{'none', 'jamming'}}, 'sev', [3 3], 'level', [NaN 1], 'ebno', [0 3], ...
    'actions', {{'no_action', 'x'}}, 'det_id', 'D', 'model_tag', 'v7', 'fec_rx', struct('mode', 'd78'), 'smoke', false, ...
    'created', 'now');
end

function [T, W] = select_world()
% 600 validation episodes (antenna_fault harmed, jamming, path_loss; 200 each, one flight each),
% 100 comb episodes and 400 clean flights; the setting in force and five candidates.
rs = RandStream('mt19937ar', 'Seed', 7);
n = 600; thr = [repmat({'antenna_fault'}, 1, 200), repmat({'jamming'}, 1, 200), repmat({'path_loss'}, 1, 200)];
y = struct('recovered', rand(rs, 1, n) < 0.6, 'recoverable', true(1, n), 'threat', true(1, n), 'cl', 1:n, ...
    'harmed', true(1, n), 'c_recovered', rand(rs, 1, 100) < 0.7, 'c_recoverable', true(1, 100), 'c_cl', 1:100);
y.heldv = y.recovered & rand(rs, 1, n) < 0.9; y.sw = double(rand(rs, 1, 400) < 0.02); y.fph = 400;
fin = @(x) setfield(setfield(setfield(x, 'rec', mean(x.recovered)), 'held', mean(x.heldv)), 'ret', 0.5); %#ok<SFLD>
y = fin(y);
up = @(x, m, k) setfield(setfield(x, 'recovered', x.recovered | m & (cumsum(m & ~x.recovered) <= k)), 'heldv', ...
    x.heldv | m & (cumsum(m & ~x.heldv) <= k)); %#ok<SFLD>
af = strcmp(thr, 'antenna_fault'); pl = strcmp(thr, 'path_loss'); jm = strcmp(thr, 'jamming');
x2 = fin(up(y, af, 50));
x3 = x2; d = find(pl & x3.recovered, 20); x3.recovered(d) = false; x3.heldv(d) = false; x3 = fin(x3);
x4 = x2; z = find(y.sw == 0, 60); x4.sw(z) = 1;
x5 = x2; x5.fph = 471;
x6 = fin(up(y, jm, 50));
W = struct('thr', {thr}, 'R', weak19_reading('reg'));
T = struct('read', struct('name', {'', 'rule', 'fec', 'q', 'rule', 'q'}, 'x', {y, x2, x3, x4, x5, x6}), 'target', 'lost_harmed', 'W', W);
end

function d = parent_dir(tc, rev, rels)
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

function fixture_off(d, fns)
if contains(path, d), rmpath(d); end
for k = 1:numel(fns), clear(fns{k}); end
if isfolder(d), rmdir(d, 's'); end
end
