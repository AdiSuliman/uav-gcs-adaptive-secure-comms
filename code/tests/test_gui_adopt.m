function tests = test_gui_adopt
%TEST_GUI_ADOPT  The operator console runs the adopted decision chain of evaluate_policies.m (CFG.adopt):
%   with no adoption named every option is the one the console had; with one, the options of the
%   deployed policy, the rule and the core rule equal evaluate_policies.m's (policy_setup.m +
%   adopt_options.m) and the per-cycle decisions on the same observations are identical; the
%   bundle's profile.json carries the adopted settings and the console reads them back.
%   Synthetic observations and a stub Q-network. Run from the repository root:
%   results = runtests('code/tests/test_gui_adopt.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.cwd = pwd;
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp); cd(tc.TestData.tmp);
tc.TestData.warn = warning('off', 'MATLAB:load:variableNotFound');
end

function teardownOnce(tc)
warning(tc.TestData.warn);
clean_ber_ref('reset');
cd(tc.TestData.cwd);
try, rmdir(tc.TestData.tmp, 's'); catch, end %#ok<NOCOM,CTCH>
end

%% ---------- off is identical ----------
function test_off_is_identical(tc)
base = {struct(), struct('core', true), struct('monitor', struct('lb_complete', true))};
offs = {adopt_options([]), adopt_options(struct('adopt', struct())), ...
    adopt_options(struct('adopt', struct('rule_fix', '', 'dqn_hop', ''))), ...
    console_policy('adopt', 'no_such_profile.json'), console_policy('adopt', write_profile(tc, 'p_plain.json', [])), ...
    console_policy('adopt', write_profile(tc, 'p_off.json', struct('rule_fix', '', 'dqn_hop', '')))};
for kd = {'dqn_esc', 'dqn', 'rule_sel'}
    D = console_policy('deployed', trained_stub(kd{1}, sel_of(kd{1})));
    for a = 1:numel(offs)
        A = offs{a};
        verifyFalse(tc, A.on);
        for w = {'deployed', 'rule', 'core'}
            for b = 1:numel(base)
                verifyTrue(tc, isequaln(console_policy('opt', D, A, w{1}, base{b}), base{b}), [kd{1} ' ' w{1}]);
            end
        end
        ctx = struct('policy', 'dqn', 'PP', struct('maha_thr', 2), 'core_rule', false);
        for w = {'dqn', 'rule', 'core'}
            verifyTrue(tc, isequaln(console_policy('adopt_ctx', D, A, w{1}, ctx), ctx), w{1});   % no ctx.opt: episode_cycle.m builds its own
        end
    end
end
end

function test_console_passes_the_options(tc)
% Every policy_decide.m call of the console carries an option, and the episode cycle reads ctx.opt.
src = strrep(fileread(which('demo_gui')), char(13), '');
calls = regexp(src, 'policy_decide\([^\n]*', 'match');
verifyNumElements(tc, calls, 6);
verifyTrue(tc, all(cellfun(@(c) contains(c, {'optD)', 'optR)', 'coreOpt)'}), calls)));
verifyNotEmpty(tc, strfind(src, 'env.adopt      = console_policy(''adopt'', ''profile.json'');'));
verifyNumElements(tc, strfind(src, 'console_policy(''adopt_ctx'''), 1);
ep = strrep(fileread(which('episode_cycle')), char(13), '');
verifyNotEmpty(tc, strfind(ep, 'if isfield(ctx, ''opt'') && ~isempty(ctx.opt), opt = ctx.opt; end'));
end

%% ---------- the console's chain is evaluate_policies.m's ----------
function test_decisions_equal_evaluation_p1(tc)
equivalence(tc, struct('rule_fix', 'keep+st+rate'));
end

function test_decisions_equal_evaluation_p3(tc)
equivalence(tc, struct('rule_fix', 'keep+st+rate', 'dqn_hop', 'rule'));
end

function test_adoption_moves_the_decisions(tc)
% The compared chains differ from the registered one on these observations, so the equivalence
% above compares something that moves: dqn_hop on the deployed DQN, the rule fix on the rule rows.
PP = mon_pp(); na = find(strcmp(PP.actions, 'no_action'));
ag = dqn_stub(PP, find(strcmp(PP.actions, 'channel_switch')));
X = const_trace(PP, 40, 0, 8, 2, 'jamming', NaN, na);
D = console_policy('deployed', trained_stub('dqn', 'dqn'));
A3 = console_policy('adopt', write_profile(tc, 'p3.json', struct('rule_fix', 'keep+st+rate', 'dqn_hop', 'rule')));
o3 = console_policy('opt', D, A3, 'deployed', struct());
verifyEqual(tc, o3, struct('monitor', struct('dqn_hop', 'rule')));
verifyNotEqual(tc, decide_run('dqn', PP, X, struct(), ag).a, decide_run('dqn', PP, X, o3, ag).a);
A1 = console_policy('adopt', write_profile(tc, 'p1.json', struct('rule_fix', 'keep+st+rate')));
verifyEqual(tc, console_policy('opt', D, A1, 'deployed', struct()), struct());      % the rule fix does not reach a DQN
o1 = console_policy('opt', D, A1, 'rule', struct());
verifyEqual(tc, o1, struct('monitor', struct('rule_fix', 'keep+st+rate')));
verifyNotEqual(tc, decide_run('rule_esc', PP, X, struct()).a, decide_run('rule_esc', PP, X, o1).a);
oc = console_policy('opt', D, A1, 'core', console_core('policy_opt'));
verifyEqual(tc, oc, struct('core', true, 'monitor', struct('rule_fix', 'keep+st+rate')));
end

function equivalence(tc, setting)
% The options and decisions of the evaluate_policies.m path (policy_setup + adopt_options on the row
% name) and of the console path (profile.json -> console_policy) on the same observations.
PP = mon_pp(); A = PP.actions; na = find(strcmp(A, 'no_action'));
ag = dqn_stub(PP, find(strcmp(A, 'channel_switch'))); ag2 = dqn_stub(PP, find(strcmp(A, 'power_control')));
sel = 2;
ev = adopt_options(struct('adopt', setting));
Ac = console_policy('adopt', write_profile(tc, 'p_run.json', setting));
verifyTrue(tc, Ac.on);
verifyEqual(tc, {Ac.rule_fix, Ac.dqn_hop, Ac.names}, {ev.rule_fix, ev.dqn_hop, ev.names});
traces = {const_trace(PP, 40, 0, 8, 2, 'jamming', NaN, na), const_trace(PP, 40, 0, 8, 2, 'tone_jamming', NaN, na), ...
    const_trace(PP, 40, 0, 8, 2, 'antenna_fault', NaN, na), const_trace(PP, 40, -6, 12, 2, 'none', NaN, na)};
% deployed rows: the console's deployed kind and the name evaluate_policies.m gives the row
rows = {'dqn_esc', 'dqn_esc'; 'dqn', sprintf('dqn_g%d', sel); 'rule_sel', 'rule_sel'};
for r = 1:size(rows, 1)
    Q = trained_stub(rows{r, 1}, sel_of(rows{r, 1})); Q.agent = ag; Q.agents = {ag2, ag};
    D = console_policy('deployed', Q);
    ADP = adopt_options('deployed', ev, rows{r, 2});
    [kind, agent, opt] = policy_setup(rows{r, 2}, Q, sel, na, na, [], na);
    opt = adopt_options('opt', ADP, rows{r, 2}, opt);
    ctx = console_policy('ctx', D, D.esc, struct('policy', 'x', 'PP', PP, 'agent', ag));
    ctx = console_policy('adopt_ctx', D, Ac, 'dqn', ctx);
    verifyEqual(tc, ctx.policy, kind, rows{r, 2});
    verifyEqual(tc, ctx.opt, console_policy('opt', D, Ac, 'deployed', struct()));
    verifyEqual(tc, ctx.PP, console_policy('settings', D, PP, false));
    for t = 1:numel(traces)
        Re = decide_run(kind, PP, traces{t}, opt, agent);       % evaluation: the monitor of a rule fallback rides in opt
        Rc = decide_run(ctx.policy, ctx.PP, traces{t}, ctx.opt, ctx.agent);
        verifyTrue(tc, isequaln(Re, Rc), sprintf('%s trace %d', rows{r, 2}, t));
    end
end
% the rule and the core rule rows
Q = trained_stub('dqn', 'dqn'); Q.agent = ag; Q.agents = {ag2, ag};
D = console_policy('deployed', Q);
ADP = adopt_options('deployed', ev, sprintf('dqn_g%d', sel));
for w = {'rule', 'rule_esc', struct(); 'core', 'rule_core', console_core('policy_opt')}'
    [kind, ~, opt] = policy_setup(w{2}, Q, sel, na, na, [], na);
    opt = adopt_options('opt', ADP, w{2}, opt);
    copt = console_policy('opt', D, Ac, w{1}, w{3});
    verifyEqual(tc, copt, opt, w{2});
    verifyEqual(tc, console_policy('adopt_ctx', D, Ac, w{1}, struct()).opt, opt, w{2});
    for t = 1:numel(traces)
        verifyTrue(tc, isequaln(decide_run(kind, PP, traces{t}, opt, []), decide_run('rule_esc', PP, traces{t}, copt, [])), ...
            sprintf('%s trace %d', w{2}, t));
    end
end
end

%% ---------- the bundle ----------
function test_export_roundtrip(tc)
% export_gui_bundle writes the adopted settings of the manifests into profile.json and the console
% reads them back; none named: the registered profile.json, byte for byte.
[root, tgt] = bundle_root(tc, 'adopt_rt');
cr = clean_ref_table();
save(fullfile(root, 'data', 'policy_pools.mat'), '-struct', 'cr');
export_quiet(tgt, root);
f = fullfile(tgt, 'rx3', 'profile.json');
plain = sprintf('{"profile":"3 UAV antennas","n_rx":3}\n');
verifyEqual(tc, fileread(f), plain);
verifyFalse(tc, console_policy('adopt', f).on);
m1 = write_manifest(tc, 'm1.json', {'rule_fix'}, {'keep+st+rate'});
m3 = write_manifest(tc, 'm3.json', {'rule_fix', 'dqn_hop'}, {'keep+st+rate', 'rule'});
export_quiet(tgt, root, m1);
A = console_policy('adopt', f);
verifyEqual(tc, {A.on, A.names, A.rule_fix, A.dqn_hop}, {true, {'rule_fix'}, 'keep+st+rate', ''});
P = jsondecode(fileread(f)); verifyEqual(tc, {P.profile, P.n_rx}, {'3 UAV antennas', 3});
export_quiet(tgt, root, m3);
A = console_policy('adopt', f);
verifyEqual(tc, {A.names, A.rule_fix, A.dqn_hop}, {{'rule_fix', 'dqn_hop'}, 'keep+st+rate', 'rule'});
export_quiet(tgt, root, {m1, m3});                          % the same setting in two manifests
verifyEqual(tc, console_policy('adopt', f).dqn_hop, 'rule');
export_quiet(tgt, root);                                        % exported again without: off
verifyEqual(tc, fileread(f), plain);
mx = write_manifest(tc, 'mx.json', {'rule_fix'}, {'keep'});
verifyError(tc, @() export_quiet(tgt, root, {m1, mx}), 'export_gui_bundle:adopt');
verifyError(tc, @() export_quiet(tgt, root, fullfile(tc.TestData.tmp, 'none.json')), 'export_gui_bundle:adopt');
mb = write_manifest(tc, 'mb.json', {'dqn_hop'}, {'fec'});
verifyError(tc, @() export_quiet(tgt, root, mb), 'dqn_fix:token');
verifyEqual(tc, fileread(f), plain);                            % a refused export leaves the profile as it was
end

function test_registered_manifests_read(tc)
% The manifests of the two adoptions, where this machine holds them: the settings the console reads.
wt = fileparts(tc.TestData.root);
f1 = fullfile(wt, 'adopt-p1', 'results', 'rule_fix', 'p1', 'adopted', 'adoption.json');
f3 = fullfile(wt, 'adopt-hop-p3', 'results', 'dqn_hop', 'p3', 'adopted', 'adoption.json');
assumeTrue(tc, isfile(f1) && isfile(f3), 'the adoption manifests are not beside this checkout');
verifyEqual(tc, adopt_reading('cfg', jsondecode(fileread(f1))).adopt, struct('rule_fix', 'keep+st+rate'));
verifyEqual(tc, adopt_reading('cfg', jsondecode(fileread(f3))).adopt, struct('rule_fix', 'keep+st+rate', 'dqn_hop', 'rule'));
end

%% ---------- what the console shows of the adoption ----------
function test_adopt_line(tc)
A3 = console_policy('adopt', write_profile(tc, 'l3.json', struct('rule_fix', 'keep+st+rate', 'dqn_hop', 'rule')));
verifyEqual(tc, console_policy('adopt_line', A3), 'adopted: rule_fix=keep+st+rate (rule rows) | dqn_hop=rule (deployed DQN)');
A1 = console_policy('adopt', write_profile(tc, 'l1.json', struct('rule_fix', 'keep+st+rate')));
verifyEqual(tc, console_policy('adopt_line', A1), 'adopted: rule_fix=keep+st+rate (rule rows)');
Ah = console_policy('adopt', write_profile(tc, 'lh.json', struct('dqn_hop', 'rule')));
verifyEqual(tc, console_policy('adopt_line', Ah), 'adopted: dqn_hop=rule (deployed DQN)');
for A = {console_policy('adopt', 'no_such_profile.json'), console_policy('adopt', write_profile(tc, 'l0.json', []))}
    verifyEqual(tc, console_policy('adopt_line', A{1}), '');     % off: no line, no empty row
    verifyEqual(tc, console_policy('kpi_note', A{1}, true), '');
    verifyEqual(tc, console_policy('kpi_note', A{1}, false), '');
end
end

function test_kpi_note(tc)
A = console_policy('adopt', write_profile(tc, 'k3.json', struct('rule_fix', 'keep+st+rate', 'dqn_hop', 'rule')));
verifyEqual(tc, console_policy('kpi_note', A, true), 'KPI numbers: adopted reading (results/adoption_note.txt)');
verifyEqual(tc, console_policy('kpi_note', A, false), ...
    'KPI numbers: registered reading, without the adopted settings the live decisions use');
end

function test_lat_head(tc)
L = struct('total_dqn_median_ms', 8.046, 'total_dqn_p95_ms', 10.556, 'total_dep_median_ms', 8.62, ...
    'total_dep_p95_ms', 11.134, 'device', 'CPU');
H = console_policy('lat_head', L);
verifyEqual(tc, [H.med H.p95], [8.62 11.134]); verifyEqual(tc, H.chain, 'deployed chain');
H = console_policy('lat_head', rmfield(L, {'total_dep_median_ms', 'total_dep_p95_ms'}));
verifyEqual(tc, [H.med H.p95], [8.046 10.556]); verifyEqual(tc, H.chain, 'DQN chain');
end

function test_lat_head_is_kpi7(tc)
% the KPI 7 card equals the kpi_summary.txt headline of each adopted root
W = fullfile(fileparts(tc.TestData.root), '');
roots = {fullfile(W, 'adopt-p1-d126', 'results', 'rule_fix', 'p1', 'adopted', 'on', 'results'), ...
    fullfile(W, 'adopt-hop-p3', 'results', 'dqn_hop', 'p3', 'adopted', 'on', 'results')};
roots = roots(cellfun(@(r) isfile(fullfile(r, 'latency.mat')) && isfile(fullfile(r, 'kpi_summary.txt')), roots));
assumeNotEmpty(tc, roots, 'no adopted root beside this checkout');
for r = roots
    L = load(fullfile(r{1}, 'latency.mat'), 'LAT'); H = console_policy('lat_head', L.LAT);
    k = regexp(fileread(fullfile(r{1}, 'kpi_summary.txt')), 'KPI 7 [^\n]*?median ([\d.]+) ms, p95 ([\d.]+) ms', 'tokens', 'once');
    verifyEqual(tc, sprintf('%.2f/%.2f', H.med, H.p95), sprintf('%s/%s', k{1}, k{2}), r{1});
end
end

function test_kpi1_head(tc)
verifyEqual(tc, console_policy('kpi1_head', 'macro-F1 94.93%, lowest class 84.46%, from 0 dB'), {'94.93', '84.46', '0 dB'});
verifyEmpty(tc, console_policy('kpi1_head', 'accuracy 95.0%'));
W = fileparts(tc.TestData.root);
roots = {fullfile(W, 'adopt-p1-d126', 'results', 'rule_fix', 'p1', 'adopted', 'on', 'results'), ...
    fullfile(W, 'adopt-hop-p3', 'results', 'dqn_hop', 'p3', 'adopted', 'on', 'results')};
roots = roots(cellfun(@(r) isfile(fullfile(r, 'kpi_summary.mat')), roots));
assumeNotEmpty(tc, roots, 'no adopted root beside this checkout');
for r = roots
    K = load(fullfile(r{1}, 'kpi_summary.mat'), 'KPI'); k1 = K.KPI([K.KPI.id] == 1);
    t = console_policy('kpi1_head', k1.value);
    verifyNotEmpty(tc, strfind(fileread(fullfile(r{1}, 'kpi_summary.txt')), ['macro-F1 ' t{1} '%']), r{1});
end
end

function test_console_wires_the_lines(tc)
src = strrep(fileread(which('demo_gui')), char(13), '');
verifyNotEmpty(tc, strfind(src, 'console_policy(''adopt_line'', env.adopt)'));
verifyNotEmpty(tc, strfind(src, 'console_policy(''kpi_note'', env.adopt, isfile(''results/adoption_note.txt''))'));
verifyNotEmpty(tc, strfind(src, 'decRows = {''1x'', 68}; if ~isempty(adoptTxt)'));   % off: the two-row layout as it was
verifyEqual(tc, numel(strfind(src, 'console_policy(''lat_head'', Lt)')), 2);            % the KPI 7 card and the latency plot
verifyEmpty(tc, strfind(src, 'Lt.total_dqn_median_ms'));
verifyNotEmpty(tc, strfind(src, 'console_policy(''kpi1_head'', k1.value)'));       % the KPI 1 card from the summary
end

function test_export_copies_the_adoption_note(tc)
[root, tgt] = bundle_root(tc, 'adopt_note');
cr = clean_ref_table();
save(fullfile(root, 'data', 'policy_pools.mat'), '-struct', 'cr');
note = ['Adopted: rule_fix keep+st+rate, then dqn_hop rule.' newline 'second line' newline];
fid = fopen(fullfile(root, 'results', 'adoption_note.txt'), 'w'); fprintf(fid, '%s', note); fclose(fid);
export_quiet(tgt, root);
f = fullfile(tgt, 'rx3', 'results', 'adoption_note.txt');
verifyTrue(tc, isfile(f));
verifyEqual(tc, fileread(f), note);
delete(fullfile(root, 'results', 'adoption_note.txt'));
export_quiet(tgt, root);                                        % a root without it: no older copy stays
verifyFalse(tc, isfile(f));
end

%% ---------- helpers ----------
function f = write_profile(tc, name, ad)
f = fullfile(tc.TestData.tmp, name);
P = struct('profile', '3 UAV antennas', 'n_rx', 3);
if ~isempty(ad), P.adopt = ad; end
fid = fopen(f, 'w'); fprintf(fid, '%s\n', jsonencode(P)); fclose(fid);
end

function f = write_manifest(tc, name, names, settings)
f = fullfile(tc.TestData.tmp, name);
a = cell(1, numel(names));
for k = 1:numel(names), a{k} = struct('name', names{k}, 'setting', settings{k}); end
fid = fopen(f, 'w'); fprintf(fid, '%s\n', jsonencode(struct('tag', 'x', 'adoptions', {a}))); fclose(fid);
end

function [root, tgt] = bundle_root(tc, name)
root = fullfile(tc.TestData.tmp, [name '_root']); tgt = fullfile(tc.TestData.tmp, [name '_target']);
mkdir(fullfile(root, 'data')); mkdir(fullfile(root, 'results'));
params = struct('n_rx', 3); save(fullfile(root, 'params.mat'), 'params');
x = 1;
for f = {'trained_detector', 'trained_dqn', 'gui_norm_stats', 'ood_thresholds'}
    save(fullfile(root, 'data', [f{1} '.mat']), 'x');
end
end

function cr = clean_ref_table()
v = [0.1 0.02 5e-3 1e-3 1e-4];
cr = struct('clean_ref', struct('ebno', [0 3 6 9 12], 'ber', v, 'ber_est', v, 'plr_fec', v));
end

function export_quiet(tgt, root, varargin)
w = warning('off', 'export_gui_bundle:stale'); c = onCleanup(@() warning(w));
export_gui_bundle(tgt, root, varargin{:});
clear c
end

function k = sel_of(deployed)
k = deployed; if strcmp(deployed, 'rule_sel'), k = 'dqn_esc'; end
end

function Q = trained_stub(deployed, selected)
Q = struct('deployed', deployed, 'seed_summary', struct('selected_kind', selected), ...
    'rule_sel', struct('alarm', 'drop', 'drop', 6, 'alarm_mode', 'drop', 'confirm', [3 3], 'drop_db', 6, ...
    'maha_thr', 3.25, 'unk_retain', 0.9, 'confirm_sweep', [], 'rec', 0.5, 'held', 0.4));
end

function PP = mon_pp()
A = policy_actions();
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
g = 4 * contains(A, 'power_control') + 6.02 * contains(A, 'rate_reduce');
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'cfg_gain_db', g, ...
    'alarm_mode', 'class_drop', 'drop_db', 4, 'confirm', [2 2], 'confirm_sweep', [2 6]);
end

function o = mk_obs(PP, lb, e, qi, link, cls, occ)
nF = numel(link_features('names')); nC = numel(PP.classes);
p = zeros(1, nC); p(find(strcmp(PP.classes, cls), 1)) = 1;
o = struct('probs', p, 'unknown', false, 'feat', zeros(1, nF), 'cfg_link', link);
o.feat(feature_index('log_ber')) = lb;
o.feat(feature_index('sinr')) = e - (10*log10(PP.sps) - 10*log10(PP.bps));
o.feat(feature_index('q_iot')) = qi;
o.idle = nan(1, numel(idle_summary('names')));
if ~isnan(occ), o.idle(strcmp(idle_summary('names'), 'occ')) = occ; end
end

function X = const_trace(PP, T, lb, e, qi, cls, occ, cfg0)
X = struct('obs', {cell(1, T)}, 'cfg0', cfg0);
for t = 1:T, X.obs{t} = mk_obs(PP, lb, e, qi, cfg0, cls, occ); end
end

function R = decide_run(kind, PP, X, opt, agent)
if nargin < 4, opt = struct(); end
if nargin < 5, agent = []; end
T = numel(X.obs); cfg = X.cfg0(:)'; NE = numel(cfg); mem = [];
R = struct('a', zeros(NE, T), 'I', {cell(1, T)});
for t = 1:T
    o = X.obs{t}; o.cfg_link = cfg(:);
    [a, mem, I] = policy_decide(kind, o, cfg, mem, PP, agent, opt);
    R.a(:, t) = a(:); R.I{t} = I; cfg = a(:)';
end
end

function ag = dqn_stub(PP, hold)
nA = numel(PP.actions); nC = numel(PP.classes);
nS = policy_state_size(nA, nC);
q0 = zeros(nA, 1); q0(1:3) = [0.5 0.4 0.3]; q0(hold) = 1;
ag = struct('dense', struct('mu', zeros(nS, 1), 'sd', ones(nS, 1), 'W', {{zeros(nA, nS)}}, 'b', {{q0}}));
end
