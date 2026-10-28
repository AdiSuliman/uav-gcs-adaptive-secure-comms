function v0_diag(pools_file, clean_file, agent_file, manifest_file, out_dir)
%V0_DIAG  Validation-only diagnostic of the deployed DQN on lost-branch threats (profile 1).
%   v0_diag(pools_file, clean_file, agent_file, manifest_file)
%   v0_diag(..., out_dir)        out_dir under <repo>/results (default <repo>/results)
%   pools_file     data/policy_pools.mat; its splits after validation are emptied on load
%   clean_file     data/clean_val_pools.mat (the independent clean validation geometries)
%   agent_file     the archived trained_dqn.mat; its sha256 must match its line in manifest_file
%   Nothing of a test split is run or read (v0_guard.m): every rollout is on split 2.
%
%   Episodes: C2's validation episodes (train_dqn.m: every (cell, Eb/N0, geometry) twice, the
%   same specification seed and frame-draw seeds) and C2's clean validation episodes (one
%   30-cycle episode per clean geometry and Eb/N0 from the KPI 6 threshold up, seeds 41000 + b).
%   Policies: no response, the deployed DQN (selected agent, no escalation), the same agent with
%   the escalation, rule + escalation, no detector + escalation, the class table and the fixed
%   configuration, all with the deployed decision-time settings.
%   Readings:
%   1  per threat, recovered and held on the harmed and the covered recoverable episodes (harmed:
%      no response does not restore the geometry, evaluate_policies.m), with counts; clean false
%      alarms per policy
%   2  lost-branch escalation triggers on the plain DQN's trace: at no_action kept by the agent, a
%      confirmed alarm, class in S, cycles since the last change >= C.esc, and one evidence form:
%      k = 1/2/3 consecutive degraded cycles, 2 of 4 and 3 of 5 degraded, the drop alarm, degraded
%      or drop alarm. S1 = {antenna_fault, airframe_shadowing}, S2 = S1 + {path_loss}. Per form:
%      (a) share harmed among the threat episodes where it fires, (b) share of the clean episodes
%      where it fires (counted, with the one-sided 95% bound), (c) share of the harmed S episodes
%      where it fires in time for a 5-cycle recovery run before the episode ends (first fire + D +
%      4 <= T: the recall ceiling), with the fire's lag from the onset
%   3  the agent's Q gap (best other configuration minus no_action) at the first fire: harmed,
%      covered, clean
%   4  DQN + escalation: escalations by path and class, release to no_action after an
%      escalation on harmed S1 episodes, held against recovered, and escalations on covered
%      episodes that turn an ok link not ok within D + 1 cycles
%   5  recovered per (threat x speed band) and (threat x Eb/N0), DQN and DQN + escalation, and
%      each threat's share of the escalation's gain and of the DQN's deficit in the top speed
%      band and at 9 dB
%   6  harmed shadowing episodes: lag of the first S class, the confirmation, the first fire and
%      the end of the harm (the last cycle no response leaves not ok)
%   Gate (fixed before the run): a form fails as the degradation evidence when (a) < 0.5 or
%   (b) > 2% (read at k = 3); the design stands as written only if some form reaches (c) >= 0.6
%   with (b) <= 2% on the harmed S episodes. V0 chooses nothing.
%   Output: <out_dir>/v0_diag.txt and v0_diag.mat
t_all = tic;
root = project_root();
if nargin < 5 || isempty(out_dir), out_dir = fullfile(root, 'results'); end
out_dir = v0_guard('out', out_dir, root);
cellfun(@(f) v0_guard('input', f), {pools_file, clean_file, agent_file});
for f = {pools_file, clean_file, agent_file, manifest_file}
    if ~isfile(f{1}), error('v0_diag:input', 'v0_diag: %s not found', f{1}); end
end
if ~isfolder(out_dir), mkdir(out_dir); end
rep = {};
rep{end+1} = '=== V0: lost-branch diagnostic of the deployed DQN, validation split only ===';
rep{end+1} = sprintf('Generated %s | code %s', datestr(now, 'yyyy-mm-dd HH:MM:SS'), git_head(root));

%% Inputs
h_agent = sha256_file(agent_file);
h_man = manifest_sha(manifest_file, 'trained_dqn.mat');
if ~strcmpi(h_agent, h_man)
    error('v0_diag:sha', 'v0_diag: %s sha256 %s differs from the manifest (%s)', agent_file, h_agent, h_man);
end
h_clean = sha256_file(clean_file);
dp = dir(pools_file);
rep{end+1} = sprintf('Agent %s sha256 %s (matches %s)', agent_file, h_agent, manifest_file);
rep{end+1} = sprintf('Clean validation pools %s sha256 %s', clean_file, h_clean);
rep{end+1} = sprintf('Pools %s, %d bytes, modified %s; splits after validation emptied on load', pools_file, dp.bytes, dp.date);
fprintf('%s\n', rep{:});

L = load(pools_file, 'PP'); PP = L.PP; clear L
PP = v0_guard('strip', PP);
Q = load(agent_file, 'agent', 'agents', 'gammas', 'H', 'seed_summary', 'deployed', 'det_id', 'dec', 'tab', 'pools_created', 'maha_thr');
check_det_id(PP, Q, 'v0_diag');
if ~ismember(Q.deployed, {'dqn', 'dqn_esc'})
    error('v0_diag:deployed', 'v0_diag: the deployed policy is %s, not the DQN', Q.deployed);
end
PP = decision_settings(PP, Q);
K = link_env('tables', PP);
C = decision_config();
H = Q.H; T = H.T; na = K.na; VAL = 2;
sel = find(Q.gammas == Q.seed_summary.selected_gamma, 1);
ag = Q.agents{sel};
Cv = load(clean_file, 'CT'); CT = Cv.CT; clear Cv
check_det_id(PP, CT, 'v0_diag', 'data/clean_val_pools.mat');
EBNO_THR = Q.seed_summary.fa_ebno_thr;
[PPw, Kw] = clean_world(PP, CT);
v0_guard('check', PPw);
[cspecs, ncl] = clean_wide_specs(PP, CT, EBNO_THR, T);
vspecs = full_val_spec(PP, K, H, VAL, 2, RandStream('mt19937ar', 'Seed', 99));
tab = policy_table(PP, K);
FIXED = 'channel_switch+spatial_diversity+power_control';   % the best fixed configuration on the train pools
fx = find(strcmp(PP.actions, FIXED), 1);
if isempty(fx), error('v0_diag:fixed', 'v0_diag: no configuration %s', FIXED); end
rep{end+1} = sprintf(['Pools created %s (agent learned on %s), det_id match | deployed %s, selected gamma %.2f, ' ...
    'kind %s | clean episodes %d (Eb/N0 >= %g dB) | table matches the agent''s: %s'], PP.created, Q.pools_created, ...
    Q.deployed, Q.gammas(sel), Q.seed_summary.selected_kind, ncl, EBNO_THR, yesno(isequal(tab.table, Q.tab.table)));
fprintf('%s\n', rep{end});

%% Runs
POL = {'none', 'dqn', 'dqn_esc', 'rule_esc', 'blind_esc', 'table', 'fixed'};
LBL = {'no response', 'DQN (deployed)', 'DQN + escalation', 'rule + escalation', 'no detector + escalation', 'table', ...
    'fixed cs+sd+pc'};
RV = cell(1, numel(POL)); XV = RV; RC = RV; XC = RV;
for p = 1:numel(POL)
    [kind, a_, opt] = setup(POL{p}, ag, tab, na, fx);
    t1 = tic;
    [RV{p}, XV{p}] = run_set(kind, PP, K, vspecs, a_, opt, 5000, []);
    if ~strcmp(POL{p}, 'none'), [RC{p}, XC{p}] = run_set(kind, PPw, Kw, cspecs, a_, opt, 41000, ncl); end
    fprintf('  %-26s %d validation + %d clean episodes, identity with rollout_policy.m checked (%.1f min)\n', LBL{p}, ...
        numel(RV{p}.ret), ncl * ~strcmp(POL{p}, 'none'), toc(t1) / 60);
end
col = @(n) find(strcmp(POL, n));

%% Episode facts (validation)
scn = cell2mat(cellfun(@(sp) sp.scn, vspecs, 'UniformOutput', false));
s = cell2mat(cellfun(@(sp) sp.s, vspecs, 'UniformOutput', false));
r = RV{1}.r;
thr = PP.scen(scn); thr = thr(:)';
threat = ~strcmp(thr, 'none') & K.on(sub2ind(size(K.on), scn, s, VAL + 0 * s, r));
ih = sub2ind(size(K.restored), scn, s, na + 0 * s, VAL + 0 * s, r);
harmed = ~(K.restored(ih) & K.restored_plr(ih));
rec = RV{col('dqn')}.recoverable & threat;
speed = PP.speed{VAL}(sub2ind(size(PP.speed{VAL}), s, r));
Dv = RV{1}.D; t0 = RV{1}.t0;
cons = isequal(harmed(threat), ~RV{col('none')}.recovered(threat));
rep{end+1} = sprintf(['Validation: %d episodes, %d threat episodes, %d recoverable, %d harmed among them | harmed agrees ' ...
    'with no response''s recovery: %s'], numel(scn), sum(threat), sum(rec), sum(rec & harmed), yesno(cons));
ss = Q.seed_summary;
if strcmp(ss.selected_kind, 'dqn')
    Rd = RV{col('dqn')};
    rep{end+1} = sprintf(['C2 reproduction, selected agent without escalation: held %.2f%% (C2 %.2f%%), recovered %.2f%% ' ...
        '(C2 %.2f%%)'], 100 * mean(Rd.held(rec)), 100 * ss.dqn_held, 100 * mean(Rd.recovered(rec)), 100 * ss.dqn_recovered);
end

%% 1. Harmed and covered episodes per threat
S1 = {'antenna_fault', 'airframe_shadowing'}; S2 = [S1, {'path_loss'}];
th = unique(thr(rec), 'stable');
th = [intersect(S2, th, 'stable'), setdiff(th, S2, 'stable')];
rep{end+1} = '';
rep{end+1} = '1. Recovered / held (%) on the recoverable validation episodes, harmed and covered apart';
rep{end+1} = sprintf('   policies: %s', strjoin(LBL, ' | '));
for blk = {'harmed', 'covered'}
    hm = harmed; if strcmp(blk{1}, 'covered'), hm = ~harmed; end
    rep{end+1} = sprintf('   %s episodes: threat, n (geometries), then recovered/held per policy', blk{1}); %#ok<AGROW>
    for ti = 1:numel(th)
        m = rec & hm & strcmp(thr, th{ti});
        if ~any(m), continue; end
        v = strjoin(cellfun(@(R) sprintf('%5.1f/%5.1f', 100 * mean(R.recovered(m)), 100 * mean(R.held(m))), RV, ...
            'UniformOutput', false), '  ');
        rep{end+1} = sprintf('   %-42s %4d (%3d)  %s', th{ti}, sum(m), numel(unique(r(m))), v); %#ok<AGROW>
    end
end
m = rec;
rep{end+1} = sprintf('   pooled recoverable %-23s %4d        %s', '', sum(m), strjoin(cellfun(@(R) sprintf('%5.1f/%5.1f', ...
    100 * mean(R.recovered(m)), 100 * mean(R.held(m))), RV, 'UniformOutput', false), '  '));
fa = cellfun(@(R) sum(R.switches > 0), RC(2:end));
rep{end+1} = sprintf('   clean false alarms (episodes with a change, of %d): %s', ncl, strjoin(arrayfun(@(k) ...
    sprintf('%s %d (%.2f%%, bound %.2f%%)', LBL{k + 1}, fa(k), 100 * fa(k) / ncl, 100 * cp_upper(fa(k), ncl)), ...
    1:numel(fa), 'UniformOutput', false), ' | '));

%% 2. Evidence forms of the lost-branch trigger
FORMS = {'deg1', 'deg2', 'deg3', 'deg2of4', 'deg3of5', 'drop', 'deg_or_drop'};
FTXT = {'1 degraded cycle', '2 consecutive degraded', '3 consecutive degraded', '2 of 4 degraded', '3 of 5 degraded', ...
    'drop alarm', 'degraded or drop alarm'};
cls_list = [cellstr(string(PP.classes(:)')), {'unknown'}];
miss = setdiff(S2, cls_list);
if ~isempty(miss), warning('v0_diag:classes', 'v0_diag: classes not in the detector: %s', strjoin(miss, ', ')); end
XD = XV{col('dqn')}; XDc = XC{col('dqn')}; RDc = RC{col('dqn')};
SS = {S1, S2}; SN = {'S1', 'S2'};
G = [];
rep{end+1} = '';
rep{end+1} = ['2. Lost-branch trigger on the plain DQN''s trace (no_action kept by the agent, confirmed alarm, class in S, ' ...
    sprintf('since >= %d, and the evidence form)', C.esc)];
rep{end+1} = ['   (a) harmed among the recoverable threat episodes where it fires | (b) clean episodes where it fires ' ...
    '[one-sided 95% bound] | (c) harmed S episodes where it fires in time (first fire + D + 4 <= T) | lag of the ' ...
    'first fire from the onset, median / p90 | DQN recovered or in time | clean cycles a keep rule would hold'];
for si = 1:2
    inS = ismember(cls_list, SS{si});
    hS = rec & harmed & ismember(thr, SS{si});
    for fi = 1:numel(FORMS)
        tf = fire(XD, inS, FORMS{fi}, C, na);
        tfc = fire(XDc, inS, FORMS{fi}, C, na);
        fv = rec & ~isnan(tf);
        g = struct();
        g.S = SN{si}; g.form = FORMS{fi};
        g.n_fire = sum(fv); g.a = mean(harmed(fv));
        g.b_k = sum(~isnan(tfc)); g.b = g.b_k / ncl; g.b_up = cp_upper(g.b_k, ncl);
        intime = ~isnan(tf) & tf + Dv + 4 <= T;
        g.n_hS = sum(hS); g.c = mean(intime(hS));
        g.c_thr = cellfun(@(u) mean(intime(hS & strcmp(thr, u))), SS{si});
        lag = tf(hS & ~isnan(tf)) - t0(hS & ~isnan(tf)) - 1;
        g.lag_med = median(lag); g.lag_p90 = p90(lag);
        g.union = mean(RV{col('dqn')}.recovered(hS) | intime(hS));
        g.keep_share = keep_cycles(XDc, tfc, inS, C, RDc.D) / max(sum(XDc.post(:)), 1);
        qg = @(mm) qstats(XD.qgap, tf, mm);
        g.qgap = struct('harmed', qg(fv & harmed), 'covered', qg(fv & ~harmed), 'clean', qstats(XDc.qgap, tfc, true(size(tfc))));
        g.tf = tf; g.tfc = tfc;
        if isempty(G), G = g; else, G(end+1) = g; end %#ok<AGROW>
        rep{end+1} = sprintf(['   %s %-24s (a) %5.1f%% of %4d | (b) %3d = %5.2f%% [%5.2f%%] | (c) %5.1f%% of %3d (%s) | ' ...
            'lag %s / %s | union %5.1f%% | keep %.2f%%'], SN{si}, FTXT{fi}, 100 * g.a, g.n_fire, g.b_k, 100 * g.b, ...
            100 * g.b_up, 100 * g.c, g.n_hS, strjoin(cellfun(@(u, v) sprintf('%s %.1f%%', u, 100 * v), SS{si}, ...
            num2cell(g.c_thr), 'UniformOutput', false), ', '), num_txt(g.lag_med), num_txt(g.lag_p90), 100 * g.union, ...
            100 * g.keep_share); %#ok<AGROW>
    end
    mD = RV{col('dqn')}.recovered(hS);
    rep{end+1} = sprintf('   %s harmed episodes the plain DQN recovers: %.1f%% of %d', SN{si}, 100 * mean(mD), sum(hS)); %#ok<AGROW>
    fv = rec & ~isnan(G(end - numel(FORMS) + 1).tf);
    rep{end+1} = sprintf('   %s threats where %s fires (recoverable): %s', SN{si}, FTXT{1}, top_counts(thr(fv), 8)); %#ok<AGROW>
end

%% 3. Q gap at the first fire
rep{end+1} = '';
rep{end+1} = '3. Q gap (best configuration other than no_action minus no_action) at the first fire, S1: n, median [q25, q75]';
for k = find(strcmp({G.S}, 'S1'))
    q = G(k).qgap;
    rep{end+1} = sprintf('   %-24s harmed %s | covered %s | clean %s', FTXT{strcmp(FORMS, G(k).form)}, q.harmed, q.covered, ...
        q.clean); %#ok<AGROW>
end

%% 4. DQN + escalation: paths, releases and changes on covered links
XE = XV{col('dqn_esc')}; RE = RV{col('dqn_esc')}; RD = RV{col('dqn')};
rep{end+1} = '';
rep{end+1} = '4. DQN + escalation: path (i) out of no_action on a class alarm, (ii) out of a degraded configuration, (iii) drop alarm read as none';
[pe, ce] = find(XE.esc & rec & threat);
pth = XE.path(sub2ind(size(XE.path), pe, ce)); cl = XE.cls(sub2ind(size(XE.cls), pe, ce));
for pv = 1:3
    rep{end+1} = sprintf('   path %-4s %5d escalations on recoverable threat episodes; class: %s', roman(pv), sum(pth == pv), ...
        top_counts(cls_list(cl(pth == pv)), 8)); %#ok<AGROW>
end
[te, p1] = first_esc(XE);
relx = released(XE, te, na);
for u = [S1, {'path_loss'}]
    hm = rec & harmed & strcmp(thr, u{1});
    if ~any(hm), continue; end
    has = hm & ~isnan(te);
    only = hm & RE.recovered & ~RD.recovered;
    rep{end+1} = sprintf(['   %s harmed (%d): DQN rec %.1f%% held %.1f%% | +esc rec %.1f%% held %.1f%% | escalated %d; first ' ...
        'path i/ii/iii %d/%d/%d | released to no_action after it %d (rec %.1f%% held %.1f%%; not released: rec %.1f%% held ' ...
        '%.1f%%) | recovered only with escalation %d, first path i/ii/iii %d/%d/%d'], u{1}, sum(hm), ...
        100 * mean(RD.recovered(hm)), 100 * mean(RD.held(hm)), 100 * mean(RE.recovered(hm)), 100 * mean(RE.held(hm)), ...
        sum(has), sum(has & p1 == 1), sum(has & p1 == 2), sum(has & p1 == 3), sum(has & relx), ...
        100 * mean(RE.recovered(has & relx)), 100 * mean(RE.held(has & relx)), 100 * mean(RE.recovered(has & ~relx)), ...
        100 * mean(RE.held(has & ~relx)), sum(only), sum(only & p1 == 1), sum(only & p1 == 2), sum(only & p1 == 3)); %#ok<AGROW>
end
for blk = {S1, {}}
    cm = rec & ~harmed; nm = 'every threat';
    if ~isempty(blk{1}), cm = cm & ismember(thr, blk{1}); nm = 'S1 threats'; end
    [n_ok, n_bad] = esc_breaks(XE, cm, RE.D);
    rep{end+1} = sprintf(['   covered, %s (%d): +esc rec %.1f%% held %.1f%% (DQN %.1f%% / %.1f%%) | escalations on an ok link ' ...
        '%d, of which the link is not ok within D + 1 cycles of the change %d (%.1f%%)'], nm, sum(cm), ...
        100 * mean(RE.recovered(cm)), 100 * mean(RE.held(cm)), 100 * mean(RD.recovered(cm)), 100 * mean(RD.held(cm)), ...
        n_ok, n_bad, 100 * n_bad / max(n_ok, 1)); %#ok<AGROW>
end

%% 5. Speed bands and Eb/N0
bins = linspace(PP.speed_range(1), PP.speed_range(2), 5);
vb = zeros(size(speed));
for bi = 1:4, vb(speed >= bins(bi) & speed < bins(bi + 1) + (bi == 4)) = bi; end
rep{end+1} = '';
rep{end+1} = sprintf('5. Recovered (%%), DQN / DQN + escalation, recoverable validation episodes; speed bands %s km/h; Eb/N0 %s dB', ...
    strjoin(arrayfun(@(b) sprintf('%.0f-%.0f', bins(b), bins(b + 1)), 1:4, 'UniformOutput', false), ', '), ...
    strjoin(arrayfun(@(e) sprintf('%g', e), PP.ebno, 'UniformOutput', false), ', '));
for ti = 1:numel(th)
    mt = rec & strcmp(thr, th{ti});
    cb = arrayfun(@(b) pair_txt(RD, RE, mt & vb == b), 1:4, 'UniformOutput', false);
    ce5 = arrayfun(@(e) pair_txt(RD, RE, mt & s == e), 1:numel(PP.ebno), 'UniformOutput', false);
    rep{end+1} = sprintf('   %-42s %s || %s', th{ti}, strjoin(cb, ' '), strjoin(ce5, ' ')); %#ok<AGROW>
end
rep{end+1} = sprintf('   %-42s %s || %s', 'pooled', strjoin(arrayfun(@(b) pair_txt(RD, RE, rec & vb == b), 1:4, ...
    'UniformOutput', false), ' '), strjoin(arrayfun(@(e) pair_txt(RD, RE, rec & s == e), 1:numel(PP.ebno), ...
    'UniformOutput', false), ' '));
e9 = find(PP.ebno == 9, 1);
cells5 = {rec & vb == 4, 'top speed band'};
if ~isempty(e9), cells5(end+1, :) = {rec & s == e9, '9 dB'}; end
for k = 1:size(cells5, 1)
    m = cells5{k, 1}; n = sum(m);
    gain = double(RE.recovered(m)) - double(RD.recovered(m)); def = 1 - double(RD.recovered(m));
    tt = thr(m);
    u = unique(tt, 'stable');
    gc = cellfun(@(x) sum(gain(strcmp(tt, x))), u); dc = cellfun(@(x) sum(def(strcmp(tt, x))), u);
    [~, o] = sort(gc, 'descend'); [~, o2] = sort(dc, 'descend');
    rep{end+1} = sprintf('   %s (%d): escalation gain %+.1f points; by threat %s', cells5{k, 2}, n, 100 * sum(gain) / n, ...
        strjoin(arrayfun(@(j) sprintf('%s %+.1f', u{j}, 100 * gc(j) / n), o(1:min(6, end)), 'UniformOutput', false), ', ')); %#ok<AGROW>
    rep{end+1} = sprintf('   %s: DQN deficit %.1f points; by threat %s', cells5{k, 2}, 100 * sum(def) / n, ...
        strjoin(arrayfun(@(j) sprintf('%s %.1f', u{j}, 100 * dc(j) / n), o2(1:min(6, end)), 'UniformOutput', false), ', ')); %#ok<AGROW>
end

%% 6. Harmed shadowing episodes: timing
XN = XV{col('none')};
hs = find(rec & harmed & strcmp(thr, 'airframe_shadowing'));
inS1 = ismember(cls_list, S1);
iF1 = find(strcmp({G.S}, 'S1') & strcmp({G.form}, 'deg1'), 1); iF7 = find(strcmp({G.S}, 'S1') & strcmp({G.form}, 'deg_or_drop'), 1);
rep{end+1} = '';
rep{end+1} = sprintf(['6. Harmed airframe_shadowing episodes (%d): lags from the onset (decision cycles) of the first S1 class, ' ...
    'the first confirmed alarm, the first fire (1 degraded / degraded or drop), and the last frame no response leaves ' ...
    'not ok (end: the harm lasts to the episode''s end)'], numel(hs));
L6 = nan(numel(hs), 5);
for j = 1:numel(hs)
    i = hs(j); a0 = t0(i) + 1;
    L6(j, 1) = first_lag(inS1(XD.cls(a0:T, i)));
    L6(j, 2) = first_lag(XD.conf(a0:T, i));
    L6(j, 3) = G(iF1).tf(i) - a0; L6(j, 4) = G(iF7).tf(i) - a0;
    k = find(~XN.ok(t0(i):T, i), 1, 'last');            % frame t0 + k - 1, on the decision clock's lag scale
    if isempty(k), L6(j, 5) = NaN; elseif t0(i) + k - 1 == T, L6(j, 5) = Inf; else, L6(j, 5) = t0(i) + k - 1 - a0; end
    rep{end+1} = sprintf('   geometry %4d, %4.1f dB, onset cycle %2d: class %s | confirmed %s | fire %s / %s | harm ends %s | DQN %d, +esc %d', ...
        r(i), PP.ebno(s(i)), t0(i), num_txt(L6(j, 1)), num_txt(L6(j, 2)), num_txt(L6(j, 3)), num_txt(L6(j, 4)), ...
        num_txt(L6(j, 5)), RD.recovered(i), RE.recovered(i)); %#ok<AGROW>
end
if ~isempty(hs)
    he = L6(:, 5); D1 = Dv(hs)';
    rep{end+1} = sprintf(['   reaching the link before the harm ends (lag + D <= end): confirmed %d, fire %d / %d of %d; ' ...
        'class median %s, confirmed median %s'], sum(L6(:, 2) + D1 <= he), sum(L6(:, 3) + D1 <= he), ...
        sum(L6(:, 4) + D1 <= he), numel(hs), num_txt(median(L6(:, 1), 'omitnan')), num_txt(median(L6(:, 2), 'omitnan')));
end

%% Gate
rep{end+1} = '';
rep{end+1} = 'Gate (fixed before the run; V0 chooses nothing):';
for si = 1:2
    k3 = find(strcmp({G.S}, SN{si}) & strcmp({G.form}, 'deg3'), 1);
    weak = G(k3).a < 0.5 || G(k3).b > 0.02;
    rep{end+1} = sprintf('   %s, 3 consecutive degraded: (a) %.1f%%, (b) %.2f%% -> the degradation flag is %s', SN{si}, ...
        100 * G(k3).a, 100 * G(k3).b, ternary(weak, 'TOO WEAK (a < 50% or b > 2%)', 'adequate')); %#ok<AGROW>
end
pass = [G.c] >= 0.6 & [G.b] <= 0.02;
if any(pass)
    rep{end+1} = sprintf('   forms with (c) >= 60%% and (b) <= 2%%: %s -> the design stands as written', ...
        strjoin(arrayfun(@(k) sprintf('%s %s (c %.1f%%, b %.2f%%)', G(k).S, G(k).form, 100 * G(k).c, 100 * G(k).b), ...
        find(pass), 'UniformOutput', false), '; '));
else
    rep{end+1} = '   no form reaches (c) >= 60% with (b) <= 2% -> the design does not stand as written; bring the alternatives with these numbers';
end
rep{end+1} = sprintf('Total %.1f min', toc(t_all) / 60);

%% Output
fid = fopen(fullfile(out_dir, 'v0_diag.txt'), 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
G = rmfield(G, {'tf', 'tfc'});
meta = struct('scn', scn, 's', s, 'r', r, 'threat', threat, 'harmed', harmed, 'recoverable', rec, 'speed', speed, ...
    't0', t0, 'D', Dv, 'thr', {thr}, 'policies', {POL}, 'labels', {LBL}, 'forms', {FORMS}, 'cls_list', {cls_list}, ...
    'agent_sha256', h_agent, 'clean_sha256', h_clean, 'pools_file', pools_file, 'pools_bytes', dp.bytes, ...
    'pools_date', dp.date, 'pools_created', PP.created, 'ebno_thr', EBNO_THR, 'n_clean', ncl);
save(fullfile(out_dir, 'v0_diag.mat'), 'meta', 'G', 'RV', 'XV', 'RC', 'XC', 'rep', '-v7.3');
fprintf('Saved %s and v0_diag.mat\n', fullfile(out_dir, 'v0_diag.txt'));
end

%% ===================== Local functions =====================
function [kind, ag, opt] = setup(name, agent, tab, na, fx)
kind = name; ag = []; opt = struct();
switch name
    case 'none',  kind = 'fixed'; opt.fixed = na;
    case 'fixed', opt.fixed = fx;
    case 'table', opt = tab;
    case {'dqn', 'dqn_esc'}, ag = agent;
end
end

function [R, X] = run_set(kind, PP, K, specs, ag, opt, seed0, nkeep)
% Every batch on split 2 (seed seed0 + b); the first batch is checked against rollout_policy.m.
Rc = cell(1, numel(specs)); Xc = Rc;
for b = 1:numel(specs)
    [Rc{b}, Xb] = v0_trace_rollout(kind, PP, K, specs{b}, 2, ag, opt, seed0 + b);
    Xc{b} = compact(Xb);
    if b == 1
        Rr = rollout_policy(kind, PP, K, specs{1}, 2, ag, opt, seed0 + 1);
        for f = {'ret', 'switches', 'recovered', 'held', 't_rec', 'recoverable'}
            if ~isequaln(Rr.(f{1}), Rc{1}.(f{1}))
                error('v0_diag:identity', 'v0_diag: %s differs from rollout_policy.m (%s, batch 1)', f{1}, kind);
            end
        end
    end
end
R = cat_fields(Rc); X = cat_fields(Xc);
if ~isempty(nkeep)
    for f = fieldnames(R)', R.(f{1}) = R.(f{1})(:, 1:nkeep); end
    for f = fieldnames(X)', X.(f{1}) = X.(f{1})(:, 1:nkeep); end
end
end

function X = compact(X)
for f = {'cfg', 'a', 'cls', 'degn', 'confn', 'path'}, X.(f{1}) = uint8(X.(f{1})); end
for f = {'since', 'qgap'}, X.(f{1}) = single(X.(f{1})); end
end

function S = cat_fields(C)
S = C{1};
for f = fieldnames(S)'
    S.(f{1}) = cell2mat(cellfun(@(x) x.(f{1}), C, 'UniformOutput', false));
end
end

function specs = full_val_spec(PP, K, H, split, reps, rs)
% train_dqn.m's validation episodes: every (cell, Eb/N0, geometry the cell flies) of the split
% `reps` times, in batches of H.NE, onset, follower jammer and follower delay drawn per episode.
v0_guard('split', split);
C = decision_config();
cells = find(~cellfun(@isempty, PP.pools(:, 1, K.na, split))');
[c, s, r] = flight_triples(cells, K.geo(cells, split), 1:numel(PP.ebno));
c = repmat(c, 1, reps); s = repmat(s, 1, reps); r = repmat(r, 1, reps);
n = numel(c); nb = ceil(n / H.NE);
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*H.NE + 1:min(b*H.NE, n); m = numel(i);
    specs{b} = struct('scn', c(i), 's', s(i), 'r', r(i), 'onset', randi(rs, [3 10], 1, m), ...
        'follow', K.followable(c(i)) & rand(rs, 1, m) < H.p_follow, 'fdelay', randi(rs, C.fdelay, 1, m), ...
        'unk', false(1, m), 'T', H.T);
end
end

function [tf, F] = fire(X, inS, form, C, na)
% First decision cycle of every episode at which the trigger holds (NaN if never).
cls = double(X.cls);
base = X.cfg == na & X.a == na & X.conf & inS(cls) & X.since >= C.esc;
d = double(X.deg);
switch form
    case 'deg1',        E = X.degn >= 1;
    case 'deg2',        E = X.degn >= 2;
    case 'deg3',        E = X.degn >= 3;
    case 'deg2of4',     E = movsum(d, [3 0], 1) >= 2;
    case 'deg3of5',     E = movsum(d, [4 0], 1) >= 3;
    case 'drop',        E = X.dal;
    case 'deg_or_drop', E = X.deg | X.dal;
    otherwise, error('v0_diag: unknown form %s', form);
end
F = base & E;
tf = nan(1, size(F, 2));
[k, i] = find(F);
if ~isempty(k), [i, j] = unique(i, 'first'); tf(i) = k(j); end
end

function n = keep_cycles(X, tf, inS, C, D)
% Cycles a keep rule would hold off no_action on the plain DQN's class trace: from the first
% fire's arrival (tf + D) until the release reaches the link (the class out of S for C.heal
% cycles, then D more), clipped at the episode's end.
T = size(X.cls, 1); n = 0;
cls = double(X.cls);
for i = find(~isnan(tf))
    out = ~inS(cls(:, i))';
    rel = T + 1;
    run = 0;
    for t = tf(i) + 1:T
        if out(t), run = run + 1; else, run = 0; end
        if run >= C.heal, rel = t + D(i); break; end
    end
    n = n + max(0, min(T, rel - 1) - (tf(i) + D(i)) + 1);
end
end

function t = qstats(qgap, tf, m)
k = find(m & ~isnan(tf));
v = double(qgap(sub2ind(size(qgap), tf(k), k)));
v = v(isfinite(v));
if isempty(v), t = 'n 0'; return; end
v = sort(v); q = v(max(1, min(numel(v), round([0.25 0.5 0.75] * numel(v)))));
t = sprintf('n %d, %.3f [%.3f, %.3f]', numel(v), q(2), q(1), q(3));
end

function [te, p1] = first_esc(X)
te = nan(1, size(X.esc, 2)); p1 = zeros(1, size(X.esc, 2));
[k, i] = find(X.esc);
if isempty(k), return; end
[i, j] = unique(i, 'first');
te(i) = k(j); p1(i) = X.path(sub2ind(size(X.path), k(j), i));
end

function rl = released(X, te, na)
% A change to no_action decided after the first escalation.
T = size(X.a, 1); rl = false(1, numel(te));
for i = find(~isnan(te))
    k = te(i) + 1:T;
    rl(i) = any(X.a(k, i) == na & X.cfg(k, i) ~= na);
end
end

function [n_ok, n_bad] = esc_breaks(X, m, D)
% Escalations decided while the last frame was ok, and those after which the link is not ok
% on a frame within D + 1 cycles of the change reaching it.
T = size(X.esc, 1); n_ok = 0; n_bad = 0;
[k, i] = find(X.esc(:, m)); idx = find(m); i = idx(i);
for j = 1:numel(k)
    t = k(j); e = i(j);
    if t < 2 || ~X.ok(t - 1, e), continue; end
    n_ok = n_ok + 1;
    w = t + D(e):min(T, t + D(e) + 1);
    if ~isempty(w) && any(~X.ok(w, e)), n_bad = n_bad + 1; end
end
end

function t = pair_txt(RD, RE, m)
if ~any(m), t = sprintf('%13s', '-'); return; end
t = sprintf('%5.1f/%5.1f(%d)', 100 * mean(RD.recovered(m)), 100 * mean(RE.recovered(m)), sum(m));
end

function t = top_counts(c, n)
if isempty(c), t = '-'; return; end
[u, ~, j] = unique(c(:)');
k = accumarray(j(:), 1)';
[k, o] = sort(k, 'descend'); u = u(o);
t = strjoin(arrayfun(@(x) sprintf('%s %d', u{x}, k(x)), 1:min(n, numel(u)), 'UniformOutput', false), ', ');
end

function k = first_lag(v)
k = find(v, 1); if isempty(k), k = NaN; else, k = k - 1; end
end

function q = p90(x)
x = sort(x(isfinite(x)));
if isempty(x), q = NaN; else, q = x(min(numel(x), max(1, round(0.9 * numel(x))))); end
end

function t = num_txt(x)
if isnan(x), t = '-'; elseif isinf(x), t = 'end'; else, t = sprintf('%g', x); end
end

function t = roman(k)
t = {'(i)', '(ii)', '(iii)'}; t = t{k};
end

function u = cp_upper(k, n)
% One-sided 95% Clopper-Pearson upper bound.
if k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

function t = yesno(c)
if c, t = 'yes'; else, t = 'NO'; end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end

function h = sha256_file(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
if fid < 0, error('v0_diag:input', 'v0_diag: cannot open %s', f); end
c = onCleanup(@() fclose(fid));
while true
    b = fread(fid, 2^24, '*uint8');
    if isempty(b), break; end
    md.update(typecast(b, 'int8'));
end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'))', 1, []));
end

function h = manifest_sha(f, name)
% The sha256 of the manifest line that names the file.
L = splitlines(fileread(f));
k = find(endsWith(strtrim(L), ['/' name]) | endsWith(strtrim(L), ['\' name]) | endsWith(strtrim(L), [' ' name]), 1);
if isempty(k), error('v0_diag:sha', 'v0_diag: %s has no line for %s', f, name); end
h = regexp(L{k}, '^[0-9a-fA-F]{64}', 'match', 'once');
if isempty(h), error('v0_diag:sha', 'v0_diag: no sha256 on the line for %s in %s', name, f); end
end

function h = git_head(root)
[st, h] = system(sprintf('git -C "%s" rev-parse --short HEAD', root));
h = strtrim(h); if st ~= 0, h = 'unknown'; end
end
