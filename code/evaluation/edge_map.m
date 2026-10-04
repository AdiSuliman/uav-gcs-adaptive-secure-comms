%% EDGE_MAP - Where the system is committed: a verdict at every point of the envelope
% Reads the test pools (data/policy_pools.mat: the test and second test splits give 72
% flights per (cell, Eb/N0) to the clean link and the single threats and 36 to the
% combined threats; the edge-speed split flies the nominal level at hover and at 161
% km/h), the clean-link pools of data/clean_test_pools.mat and the trained policy. The
% deployed policy, as evaluate_policies.m picks it (the selected DQN with escalation, or
% the rule with escalation when the DQN failed its validation gate), no response, the rule
% with escalation and the one-step oracle run every flight (single set two onsets per
% flight, follower set for the four followable threats, combined set, one clean episode
% per flight; policy_episodes.m, policy_run_set.m). Layers and their targets:
%   DET   detection of the deployed detector, fused over the last cycles (fused_class.m),
%         on the threat-active frames at no_action (threat_active.m): the class calls for
%         the countermeasure of the threat (rule_based_policy.m), for a combined threat
%         that of one of its components                                       >= 90%
%   SURV  flights some configuration recovers (link_env.m)                     >= 90%
%   REC   recovered among recoverable episodes (KPI 4); a flight succeeds when
%         all its episodes recover                                             >= 90%
%   FA    clean link: flights with a configuration change (KPI 6)              <= 5%
%   LINK  clean link: packet loss at no_action. 802.11's PER < 10% at a 1000-byte
%         PSDU (Keysight AN Table 7, BER 1.3e-5) on our 129-byte frames         <= 1.4%
%   SYSTEM       DET, SURV and REC all COMMITTED (the proposal's relative criterion)
%   SYSTEM+LINK  SYSTEM and LINK at the same Eb/N0 (absolute)
% Interval and verdict: edge_verdict.m (95%, bootstrap over flights and Clopper-Pearson,
% COMMITTED / NOT COMMITTED / UNDETERMINED, at least 36 flights to commit).
% Tables per (threat, level, Eb/N0 with its distance, link_distance_km.m), per Eb/N0 for
% the clean link, and per band of each (threat, level) over the Eb/N0 from the KPI 1
% threshold up (fixed on validation): sixths of the speed range, thirds of the altitude
% range, 5-dB K bands of our signal (the lowest also from -3 dB, the lowest in-flight K
% near 2.4 GHz, Aoki et al.), hover and 161 km/h. Edges, every layer apart: fixed-sequence
% walks that stop at the first point not COMMITTED (each "up to" claim keeps a 5% family
% error): Eb/N0 from 15 dB down (its km, and x0.63 for every position of a flight,
% link_budget_table.m), levels up, the run of speed and altitude bands around the nominal
% band, K down from 15-20 dB; a COMMITTED point beyond a NOT COMMITTED one is flagged.
% Overhead pass (overhead_pass.m): the path_loss SYSTEM verdict at the smallest level at
% or above the drop, COMMITTED when the tracker-lost bound is, NOT COMMITTED when the
% tracked bound is not; a drop above the top level is not measured. The detector beyond
% 0-15 dB and between levels: eval_unseen_snr.m and eval_unseen_severity.m.
% Level basis: the spoofer at 30 dB, the open connector and WLAN at 30 dB are assumed
% levels, the others measured; * marks a level the detector never trained on.
% Output: results/edge_map.{txt,mat}, results/edge_summary.txt, results/edge_bands.png,
% results/edge_heatmap_{det,surv,rec,system}.png, results/link_budget.{txt,mat}

close all; clc;
fprintf('=== Edge map: a verdict at every point of the envelope ===\n\n');

%% 1. Inputs
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
if ~isfield(PP, 'cov') || ~isfield(PP, 'cell_geo') || numel(PP.runs) < 5
    error('edge_map: the pools have no second test split or flight draws (built before v7-D74); run build_policy_pools');
end
Q = load('data/trained_dqn.mat', 'agent', 'agents', 'gammas', 'H', 'seed_summary', 'confirm', 'alarm_mode', 'drop_db');
PP.confirm = Q.confirm; PP.alarm_mode = Q.alarm_mode;           % the monitor of evaluate_policies.m
if ~isempty(Q.drop_db), PP.drop_db = Q.drop_db; end
K = link_env('tables', PP);
C = decision_config();
p0 = load('params.mat').params;
TEST = 3; SPEED = 4; TEST2 = 5; SPL = [TEST TEST2];
T = Q.H.T; NE = 64; REPS = 2; B = 4000;
TGT = struct('det', 0.90, 'surv', 0.90, 'rec', 0.90, 'fa', 0.05, 'link', 0.014);
K_READ = -3;                    % [dB] lowest in-flight K near 2.4 GHz (Aoki et al.): second reading of the lowest band
if exist('SMOKE', 'var') && SMOKE, REPS = 1; B = 400; end       % reduced chain check (run_stage smoke)
nS = numel(PP.ebno); nC = numel(PP.scen);
single_cells = find(ismember(PP.scen, PP.singles) & ~strcmp(PP.scen, 'none'));
combo_cells = find(ismember(PP.scen, PP.combos));
clean_cell = K.clean;
tc = [single_cells, combo_cells]; nT = numel(tc);
foll = single_cells(K.followable(single_cells));
nom = single_cells(PP.sev(single_cells) == C.nominal);
ebno_thr = PP.ebno(1);                                % bands from the KPI 1 threshold (lowest Eb/N0 without one)
if isfile('results/eval_detector_metrics.mat')
    Md = load('results/eval_detector_metrics.mat', 'metrics');
    if isfield(Md.metrics, 'kpi1_threshold_db') && isfinite(Md.metrics.kpi1_threshold_db)
        ebno_thr = Md.metrics.kpi1_threshold_db;
    end
end
km = link_distance_km(PP.ebno, p0);                   % [km] distance of every Eb/N0, profile A tracked
LB = link_budget();
if isfile('results/overhead_pass.mat'), L = load('results/overhead_pass.mat', 'OHP'); OHP = L.OHP; else, OHP = overhead(); end
VZ = edge_verdict([], [], [], 0.9, 'ge', false);      % empty verdict (no flight)
N_MIN = VZ.n_min;

sel = find(Q.gammas == Q.seed_summary.selected_gamma, 1);
dep = 'dqn_esc';                                      % deployed policy: the selected DQN + escalation,
if isfield(Q.seed_summary, 'gate_pass') && ~Q.seed_summary.gate_pass
    dep = 'rule_esc';                                 % or the rule + escalation when the DQN failed its validation gate
end
POL = unique({dep, 'none', 'rule_esc', 'oracle'}, 'stable'); nP = numel(POL);
NAMES = struct('dqn_esc', 'DQN + escalation', 'none', 'no response', 'rule_esc', 'rule + escalation', ...
    'oracle', 'oracle (one-step)');
LBL = cellfun(@(p) NAMES.(p), POL, 'UniformOutput', false);

% Every (threat, level): label, level basis, levels the detector never trained on
DL = dataset_levels();
lbl = cell(1, nT); basis = repmat({'measured'}, 1, nT); between = false(1, nT); lv_txt = cell(1, nT);
for i = 1:nT
    c = tc(i); comp = strsplit(PP.scen{c}, '+');
    if isscalar(comp), lv_txt{i} = sprintf('%g dB', PP.level(c)); else, lv_txt{i} = PP.sev_names{PP.sev(c)}; end
    lbl{i} = [PP.scen{c} ' ' lv_txt{i}];
    for q = comp
        lv = C.sev.(q{1}).levels(PP.sev(c));
        if strcmp(q{1}, 'antenna_fault') || (ismember(q{1}, {'spoofing', 'benign_interference'}) && lv >= 30)
            basis{i} = 'assumed';                     % no source measured the level
        end
        between(i) = between(i) || ~any(abs(DL(strcmp({DL.name}, q{1})).levels - lv) < 1e-9);
    end
end

%% 2. Episodes of every policy on every flight
rs = RandStream('mt19937ar', 'Seed', 2074);
sets = struct('name', {}, 'spec', {}, 'split', {});
for sp = [SPL SPEED]
    cs = single_cells; cc = combo_cells;
    if sp == SPEED, cs = nom; cc = []; end
    sp_sets = {'single', cs, REPS, false; 'follower', intersect(cs, foll, 'stable'), REPS, true; ...
        'combined', cc, REPS, false; 'clean', clean_cell, 1, false};
    for k = 1:size(sp_sets, 1)
        spec = cell_episodes(PP, sp_sets{k, 2}, sp, sp_sets{k, 3}, sp_sets{k, 4}, NE, T, rs);
        if ~isempty(spec), sets(end+1) = struct('name', sp_sets{k, 1}, 'spec', {spec}, 'split', sp); end %#ok<SAGROW>
    end
end
RES = cell(numel(sets), nP);
t0 = tic;
for si = 1:numel(sets)
    for pk = 1:nP
        [kind, ag, opt] = policy_setup(POL{pk}, Q, sel, [], [], [], K.na);
        RES{si, pk} = policy_run_set(kind, PP, K, sets(si).spec, sets(si).split, ag, opt, 80000 + 1000 * si);
    end
    fprintf('  %-8s %-6s %6d episodes x %d policies (%.1f min)\n', sets(si).name, PP.splits{sets(si).split}, ...
        numel(RES{si, 1}.ret), nP, toc(t0) / 60);
end
% The clean link on the flights of data/clean_test_pools.mat, one episode per flight
RW = {}; CT = [];
if isfile('data/clean_test_pools.mat')
    L = load('data/clean_test_pools.mat', 'CT'); CT = L.CT; clear L
    PPw = PP;
    PPw.pools(:) = {[]};
    PPw.pools(clean_cell, :, :, TEST) = reshape(CT.pools(1, :, :), [1 nS numel(PP.actions)]);
    PPw.runs{TEST} = CT.runs; PPw.speed{TEST} = CT.speed;
    PPw.cell_geo{clean_cell}{TEST} = 1:CT.n_geom;
    Kw = link_env('tables', PPw);
    spec = cell_episodes(PPw, clean_cell, TEST, 1, false, NE, T, rs);
    RW = cell(1, nP);
    for pk = 1:nP
        [kind, ag, opt] = policy_setup(POL{pk}, Q, sel, [], [], [], K.na);
        RW{pk} = policy_run_set(kind, PPw, Kw, spec, TEST, ag, opt, 40000);
    end
    fprintf('  clean    C1c    %6d episodes x %d policies (%.1f min)\n', numel(RW{1}.ret), nP, toc(t0) / 60);
    clear PPw Kw
end

%% 3. Flights
% One row per flight a threat cell or the clean link flies in the test splits and the
% edge-speed split; flight id 1e6 split + 1000 Eb/N0 + geometry (the bootstrap cluster)
[fc, fsp, fs, fr] = deal(zeros(0, 1));
for c = [tc, clean_cell]
    for sp = [SPL SPEED]
        [s_, r_] = ndgrid(1:nS, PP.cell_geo{c}{sp});
        fc = [fc; c + 0 * s_(:)]; fsp = [fsp; sp + 0 * s_(:)]; fs = [fs; s_(:)]; fr = [fr; r_(:)]; %#ok<AGROW>
    end
end
nF = numel(fc);
IDX = zeros(nC, nS, numel(PP.runs), max(K.nR));
IDX(sub2ind(size(IDX), fc, fs, fsp, fr)) = 1:nF;
FT = struct('c', fc, 'sp', fsp, 's', fs, 'r', fr, 'geo', 1e6 * fsp + 1000 * fs + fr, 'eb', reshape(PP.ebno(fs), [], 1), ...
    'speed', nan(nF, 1), 'alt', nan(nF, 1), 'ksig', nan(nF, 1), ...
    'surv', K.recoverable(sub2ind(size(K.recoverable), fc, fs, fsp, fr)), 'det_k', zeros(nF, 1), 'det_n', zeros(nF, 1), ...
    'rec_k', zeros(nF, nP), 'rec_n', zeros(nF, nP), 'fa_k', zeros(nF, nP), 'fa_n', zeros(nF, nP), ...
    'link_k', zeros(nF, 1), 'link_n', zeros(nF, 1));
for sp = [SPL SPEED]
    m = FT.sp == sp; j = sub2ind(size(PP.speed{sp}), FT.s(m), FT.r(m));
    FT.speed(m) = PP.speed{sp}(j); FT.alt(m) = PP.cov{sp}.alt_m(j); FT.ksig(m) = PP.cov{sp}.k_sig(j);
end
% REC and FA of every policy
for si = 1:numel(sets)
    for pk = 1:nP
        R = RES{si, pk};
        if strcmp(sets(si).name, 'clean'), m = true(size(R.scn)); else, m = R.recoverable & R.threat; end
        i = IDX(sub2ind(size(IDX), R.scn(m), R.s(m), R.split(m), R.r(m)));
        if strcmp(sets(si).name, 'clean')
            FT.fa_k(:, pk) = FT.fa_k(:, pk) + accumarray(i(:), double(R.switches(m)' > 0), [nF 1]);
            FT.fa_n(:, pk) = FT.fa_n(:, pk) + accumarray(i(:), 1, [nF 1]);
        else
            FT.rec_k(:, pk) = FT.rec_k(:, pk) + accumarray(i(:), double(R.recovered(m)'), [nF 1]);
            FT.rec_n(:, pk) = FT.rec_n(:, pk) + accumarray(i(:), 1, [nF 1]);
        end
    end
end
% DET: fused class of every frame at no_action, against the countermeasure of the threat
acts = cellfun(@(x) rule_based_policy(x), PP.classes, 'UniformOutput', false);
for c = tc
    ok_c = ismember(acts, cellfun(@(x) rule_based_policy(x), strsplit(PP.scen{c}, '+'), 'UniformOutput', false));
    for sp = [SPL SPEED]
        for s = 1:nS
            P = PP.pools{c, s, K.na, sp};
            if isempty(P) || isempty(P.ber), continue; end
            k = fused_class(P.probs, struct('run', P.run, 'pos', run_pos(P.run), 'gain_ant', P.gant, 'feats_raw', P.feat), ...
                PP.fuse, PP.fuse_N);
            on = threat_active(PP.scen{c}, P.act);
            i = flight_of(IDX, c, s, sp, P.run, PP.runs{sp});
            FT.det_k = FT.det_k + accumarray(i, double(reshape(ok_c(k), [], 1) & on), [nF 1]);
            FT.det_n = FT.det_n + accumarray(i, double(on), [nF 1]);
        end
    end
end
% LINK: packet loss of the clean link at no_action
for sp = [SPL SPEED]
    for s = 1:nS
        P = PP.pools{clean_cell, s, K.na, sp};
        if isempty(P) || isempty(P.ber), continue; end
        i = flight_of(IDX, clean_cell, s, sp, P.run, PP.runs{sp});
        FT.link_k = FT.link_k + accumarray(i, double(P.fer), [nF 1]);
        FT.link_n = FT.link_n + accumarray(i, 1, [nF 1]);
    end
end
% The clean-link flights of data/clean_test_pools.mat (split id 6): draws from their seeds
CF = take_rows(FT, FT.c == clean_cell & ismember(FT.sp, SPL));
if ~isempty(CT)
    [s_, r_] = ndgrid(1:nS, 1:CT.n_geom); s_ = s_(:); r_ = r_(:); n = numel(s_);
    blk = floor((CT.runs(1) - 1) / 100);               % seed block of the clean-link flights (pool_seed.m)
    CW = struct('c', clean_cell + 0 * s_, 'sp', 6 + 0 * s_, 's', s_, 'r', r_, 'geo', 6e6 + 1000 * s_ + r_, ...
        'eb', reshape(PP.ebno(s_), [], 1), 'speed', CT.speed(sub2ind(size(CT.speed), s_, r_)), 'alt', nan(n, 1), ...
        'ksig', nan(n, 1), 'surv', false(n, 1), 'det_k', zeros(n, 1), 'det_n', zeros(n, 1), 'rec_k', zeros(n, nP), ...
        'rec_n', zeros(n, nP), 'fa_k', zeros(n, nP), 'fa_n', zeros(n, nP), 'link_k', zeros(n, 1), 'link_n', zeros(n, 1));
    for q = 1:n
        d = flight_draws(pool_seed(1, s_(q), blk, r_(q)), CW.speed(q) / 3.6 * p0.carrier_freq / p0.c_light, p0, ...
            struct('ebno', PP.ebno(s_(q))));
        CW.alt(q) = d.alt_m; CW.ksig(q) = d.k_sig;
    end
    for pk = 1:nP
        i = sub2ind([nS CT.n_geom], RW{pk}.s, RW{pk}.r);
        CW.fa_k(:, pk) = accumarray(i(:), double(RW{pk}.switches(:) > 0), [n 1]);
        CW.fa_n(:, pk) = accumarray(i(:), 1, [n 1]);
    end
    for s = 1:nS
        P = CT.pools{1, s, K.na};
        [~, r] = ismember(P.run, CT.runs);
        i = sub2ind([nS CT.n_geom], s + 0 * r, r);
        CW.link_k = CW.link_k + accumarray(i, double(P.fer), [n 1]);
        CW.link_n = CW.link_n + accumarray(i, 1, [n 1]);
    end
    CF = cat_rows(CF, CW);
end
CS = take_rows(FT, FT.c == clean_cell & FT.sp == SPEED);   % clean link at the edge speeds
fprintf('Flights: %d of the threat cells, %d of the clean link (%.1f min)\n', sum(FT.c ~= clean_cell), ...
    numel(CF.s) + numel(CS.s), toc(t0) / 60);

%% 4. Verdicts per point
PT = struct('det', repmat(VZ, nT, nS), 'surv', repmat(VZ, nT, nS), 'rec', repmat(VZ, nT, nS), ...
    'sys', zeros(nT, nS), 'lim', {repmat({''}, nT, nS)}, 'sysl', zeros(nT, nS), 'rec_pol', nan(nT, nS, nP));
in_pt = ismember(FT.sp, SPL);
for i = 1:nT
    for s = 1:nS
        F = take_rows(FT, FT.c == tc(i) & in_pt & FT.s == s);
        Lz = threat_layers(F, TGT, B);
        PT.det(i, s) = Lz.det; PT.surv(i, s) = Lz.surv; PT.rec(i, s) = Lz.rec; PT.sys(i, s) = Lz.sys; PT.lim{i, s} = Lz.lim;
        PT.rec_pol(i, s, :) = sum(F.rec_k(F.surv, :), 1) ./ sum(F.rec_n(F.surv, :), 1);
    end
end
CL = struct('fa', repmat(VZ, 1, nS), 'link', repmat(VZ, 1, nS));
for s = 1:nS
    Lz = clean_layers(take_rows(CF, CF.s == s), TGT, B);
    CL.fa(s) = Lz.fa; CL.link(s) = Lz.link;
end
for i = 1:nT
    for s = 1:nS, PT.sysl(i, s) = all_of([PT.sys(i, s), CL.link(s).verdict], 'SL'); end
end
VD = struct('det', reshape([PT.det.verdict], nT, nS), 'surv', reshape([PT.surv.verdict], nT, nS), ...
    'rec', reshape([PT.rec.verdict], nT, nS), 'sys', PT.sys, 'sysl', PT.sysl);
fprintf('Verdicts per point done (%.1f min)\n', toc(t0) / 60);

%% 5. Bands, over the Eb/N0 from the KPI 1 threshold up
ev = linspace(PP.speed_range(1), PP.speed_range(2), 7);
ea = linspace(p0.alt_range_m(1), p0.alt_range_m(2), 4);
ek = p0.k_range_db(1):5:p0.k_range_db(2);
band = @(name, ax, lo, hi, top) struct('name', name, 'axis', ax, 'lo', lo, 'hi', hi, 'top', top);
BD = struct('name', {}, 'axis', {}, 'lo', {}, 'hi', {}, 'top', {});
for b = 1:6, BD(end+1) = band(sprintf('%.0f-%.0f km/h', ev(b), ev(b+1)), 'speed', ev(b), ev(b+1), b == 6); end %#ok<SAGROW>
for b = 1:2, BD(end+1) = band(sprintf('%g km/h', PP.speed_out(b, 1)), 'edge', PP.speed_out(b, 1), PP.speed_out(b, 2), true); end %#ok<SAGROW>
for b = 1:3, BD(end+1) = band(sprintf('%.0f-%.0f m', ea(b), ea(b+1)), 'alt', ea(b), ea(b+1), b == 3); end %#ok<SAGROW>
for b = 1:5, BD(end+1) = band(sprintf('K %g..%g dB', ek(b), ek(b+1)), 'k', ek(b), ek(b+1), b == 5); end %#ok<SAGROW>
BD(end+1) = band(sprintf('K %g..%g dB', K_READ, ek(2)), 'k', K_READ, ek(2), false);   % the lowest band from K_READ
nB = numel(BD);
BT = struct('det', repmat(VZ, nT, nB), 'surv', repmat(VZ, nT, nB), 'rec', repmat(VZ, nT, nB), 'sys', zeros(nT, nB), ...
    'lim', {repmat({''}, nT, nB)});
base = in_pt & FT.eb >= ebno_thr; bspd = FT.sp == SPEED & FT.eb >= ebno_thr;
for i = 1:nT
    mc = FT.c == tc(i);
    for b = 1:nB
        if strcmp(BD(b).axis, 'edge'), F = take_rows(FT, mc & bspd); else, F = take_rows(FT, mc & base); end
        Lz = threat_layers(take_rows(F, in_band(F, BD(b))), TGT, B);
        BT.det(i, b) = Lz.det; BT.surv(i, b) = Lz.surv; BT.rec(i, b) = Lz.rec; BT.sys(i, b) = Lz.sys; BT.lim{i, b} = Lz.lim;
    end
end
CB = struct('fa', repmat(VZ, 1, nB), 'link', repmat(VZ, 1, nB));
for b = 1:nB
    if strcmp(BD(b).axis, 'edge'), F = take_rows(CS, CS.eb >= ebno_thr); else, F = take_rows(CF, CF.eb >= ebno_thr); end
    Lz = clean_layers(take_rows(F, in_band(F, BD(b))), TGT, B);
    CB.fa(b) = Lz.fa; CB.link(b) = Lz.link;
end
VB = struct('det', reshape([BT.det.verdict], nT, nB), 'surv', reshape([BT.surv.verdict], nT, nB), ...
    'rec', reshape([BT.rec.verdict], nT, nB), 'sys', BT.sys);
none_ = reshape([BT.surv.n], nT, nB) == 0;            % a band no flight of the cell falls in
for f = {'det', 'surv', 'rec', 'sys'}, VB.(f{1})(none_) = NaN; end
fprintf('Bands done (%.1f min)\n', toc(t0) / 60);

%% 6. Edges: fixed-sequence walks, every layer apart
LAY = {'det', 'surv', 'rec', 'sys', 'sysl'};
LAYN = {'DET', 'SURV', 'REC', 'SYSTEM', 'SYSTEM+LINK'};
down = nS:-1:1;                                       % Eb/N0 from the top down
ED = struct();
for f = 1:numel(LAY)
    E = struct('edge', nan(nT, 1), 'first_not', nan(nT, 1), 'nonmono', false(nT, 1));
    for i = 1:nT
        W = walk(VD.(LAY{f})(i, down), PP.ebno(down));
        E.edge(i) = W.edge; E.first_not(i) = W.first_not; E.nonmono(i) = W.nonmono;
    end
    E.km = link_distance_km(E.edge, p0); E.km_all = LB.all_pos * E.km;
    ED.(LAY{f}) = E;
end
CE = struct();
for f = {'fa', 'link'}
    W = walk([CL.(f{1})(down).verdict], PP.ebno(down));
    CE.(f{1}) = struct('edge', W.edge, 'first_not', W.first_not, 'nonmono', W.nonmono, 'km', link_distance_km(W.edge, p0));
end
% Severity: per threat and Eb/N0, levels from the lowest up
THR = unique(PP.scen(tc), 'stable'); nTh = numel(THR);
rows_of = cellfun(@(t) sort_by_sev(find(strcmp(PP.scen(tc), t)), PP.sev(tc)), THR, 'UniformOutput', false);
SV = struct();
for f = 1:numel(LAY)
    E = struct('edge', nan(nTh, nS), 'first_not', nan(nTh, nS), 'nonmono', false(nTh, nS));
    for t = 1:nTh
        ii = rows_of{t};
        for s = 1:nS
            W = walk(VD.(LAY{f})(ii, s)', PP.sev(tc(ii)));
            E.edge(t, s) = W.edge; E.first_not(t, s) = W.first_not; E.nonmono(t, s) = W.nonmono;
        end
    end
    SV.(LAY{f}) = E;
end
% Speed and altitude: the run of COMMITTED bands around the nominal one; K: from 15-20 dB down
isp = find(strcmp({BD.axis}, 'speed')); iea = find(strcmp({BD.axis}, 'edge')); ial = find(strcmp({BD.axis}, 'alt'));
ik = find(strcmp({BD.axis}, 'k'));                    % five bands up, then the reading of the lowest from K_READ
i0v = find(ev(1:end-1) <= 3.6 * p0.v_nominal & 3.6 * p0.v_nominal < ev(2:end), 1);   % band of the 72 km/h cruise
RN = struct();
for f = {'det', 'surv', 'rec', 'sys'}
    E = struct('v', nan(nT, 2), 'v_nonmono', false(nT, 1), 'edge_v', nan(nT, 2), 'alt', nan(nT, 2), ...
        'alt_nonmono', false(nT, 1), 'kmin', nan(nT, 1), 'kmin_read', nan(nT, 1), 'k_nonmono', false(nT, 1));
    for i = 1:nT
        W = run_around(VB.(f{1})(i, isp), i0v);
        if ~isnan(W.a), E.v(i, :) = [ev(W.a), ev(W.b + 1)]; end
        E.v_nonmono(i) = W.nonmono;
        E.edge_v(i, :) = VB.(f{1})(i, iea);
        W = run_around(VB.(f{1})(i, ial), 2);
        if ~isnan(W.a), E.alt(i, :) = [ea(W.a), ea(W.b + 1)]; end
        E.alt_nonmono(i) = W.nonmono;
        W = walk(VB.(f{1})(i, ik(5:-1:1)), ek(5:-1:1)); E.kmin(i) = W.edge; E.k_nonmono(i) = W.nonmono;
        W = walk(VB.(f{1})(i, ik([5 4 3 2 6])), [ek(5:-1:2), K_READ]); E.kmin_read(i) = W.edge;
    end
    RN.(f{1}) = E;
end

%% 7. Overhead pass: the path_loss verdict at the drop of each bound
pl = tc(strcmp(PP.scen(tc), 'path_loss'));
[lvs, o] = sort(PP.level(pl)); ip = arrayfun(@(c) find(tc == c), pl(o));
OV = nan(numel(OHP.alt_m), numel(OHP.ebno)); OLt = OV; OLl = OV;
for j = 1:numel(OHP.ebno)
    s = find(PP.ebno == OHP.ebno(j), 1);
    if isempty(s) || isempty(ip), continue; end
    for h = 1:numel(OHP.alt_m)
        [vt, OLt(h, j)] = level_verdict(OHP.drop_tracked_db(h, j), lvs, PT.sys(ip, s));
        [vl, OLl(h, j)] = level_verdict(OHP.drop_lost_db(h, j), lvs, PT.sys(ip, s));
        if vl == 1, OV(h, j) = 1; elseif vt == -1, OV(h, j) = -1; else, OV(h, j) = 0; end
    end
end

%% 8. Detector beyond the trained ranges (eval_unseen_snr.m, eval_unseen_severity.m)
B4 = []; B4s = struct('threat', {}, 'level', {}, 'value', {}, 'lo', {}, 'hi', {}, 'n', {}, 'verdict', {});
if isfile('results/unseen_snr.mat')
    L = load('results/unseen_snr.mat');
    if isfield(L, 'edge'), B4 = L.edge; end
end
if isfile('results/unseen_severity.mat')
    L = load('results/unseen_severity.mat', 'R'); Rs = L.R;
    if isfield(Rs, 'seed')
        Rb = Rs(strcmp({Rs.kind}, 'between'));
        [u, ~, j] = unique(strcat({Rb.threat}, '|', arrayfun(@(x) sprintf('%g', x), [Rb.level], 'UniformOutput', false)), 'stable');
        for q = 1:numel(u)
            x = Rb(j == q);
            V = edge_verdict([x.same_action], [x.n], 1:numel(x), TGT.det, 'ge', false, B);
            B4s(end+1) = struct('threat', x(1).threat, 'level', x(1).level, 'value', V.value, 'lo', V.lo, 'hi', V.hi, ...
                'n', V.n, 'verdict', V.verdict); %#ok<SAGROW>
        end
    end
end
clear L

%% 9. Report
pct = @(V) cell_txt(V, '%5.1f');
hdr_e = arrayfun(@(e, d) sprintf('%g dB %.2f km', e, d), PP.ebno, km, 'UniformOutput', false);
rowl = cellfun(@(l, b, w) sprintf('%-40s %-8s', [l repmat('*', 1, w)], b), lbl, basis, num2cell(between), 'UniformOutput', false);
rep = {'=== EDGE MAP: A VERDICT AT EVERY POINT OF THE ENVELOPE ==='};
rep{end+1} = sprintf(['Generated: %s | deployed policy %s | flights per (cell, Eb/N0): clean link and single threats ' ...
    '%d, combined threats %d; edge speeds %d per Eb/N0 at the nominal level | episodes: %d onsets per flight, ' ...
    'follower set for the followable threats'], datestr(now), NAMES.(dep), numel(PP.cell_geo{tc(1)}{TEST}) + ...
    numel(PP.cell_geo{tc(1)}{TEST2}), numel(PP.cell_geo{tc(end)}{TEST}) + numel(PP.cell_geo{tc(end)}{TEST2}), ...
    numel(PP.cell_geo{clean_cell}{SPEED}), REPS);
rep{end+1} = sprintf(['Targets: DET >= %g%% | SURV >= %g%% | REC >= %g%% | FA <= %g%% | LINK <= %g%% | SYSTEM: DET, SURV ' ...
    'and REC COMMITTED | SYSTEM+LINK: and LINK'], 100 * [TGT.det TGT.surv TGT.rec TGT.fa TGT.link]);
rep{end+1} = sprintf(['Two-sided 95%% intervals (edge_verdict.m: bootstrap over flights, B = %d, Clopper-Pearson for ' ...
    'per-flight outcomes); COMMITTED needs >= %d flights. C COMMITTED, N NOT COMMITTED, U UNDETERMINED.'], B, N_MIN);
rep{end+1} = sprintf(['Distance, profile A tracked (link_distance_km.m): %s; every position of a flight x%.2f (ground ' ...
    'reflection); the 0.6 F1 clearance (%.1f km at %g m) and the radio horizon never bind below %.2f km.'], ...
    strjoin(hdr_e, ' | '), LB.all_pos, min(LB.fresnel_km), LB.alt_m(1), max(km));
rep{end+1} = ['Level basis: assumed = the spoofer at 30 dB, the open connector and WLAN at 30 dB (no source measured ' ...
    'the level); * = a level the detector never trained on (between its trained levels).'];
ttl = {'DET: fused detection on the threat-active frames at no_action', 'SURV: flights some configuration recovers', ...
    'REC: recovered among recoverable episodes, deployed policy'};
for f = 1:3
    rep{end+1} = ''; %#ok<SAGROW>
    rep{end+1} = sprintf('--- %s, %% [95%% interval] flights verdict ---', ttl{f}); %#ok<SAGROW>
    rep{end+1} = sprintf('%-49s %s', '', sprintf('%-29s', hdr_e{:})); %#ok<SAGROW>
    for i = 1:nT
        rep{end+1} = sprintf('%s %s', rowl{i}, strjoin(arrayfun(@(s) pct(PT.(LAY{f})(i, s)), 1:nS, 'UniformOutput', false), ' ')); %#ok<SAGROW>
    end
end
for f = 4:5
    rep{end+1} = ''; %#ok<SAGROW>
    rep{end+1} = sprintf('--- %s: verdict (layers not COMMITTED: D DET, S SURV, R REC, L LINK) ---', LAYN{f}); %#ok<SAGROW>
    rep{end+1} = sprintf('%-49s %s', '', sprintf('%-16s', hdr_e{:})); %#ok<SAGROW>
    for i = 1:nT
        lm = PT.lim(i, :);
        if f == 5, lm = cellfun(@(x, s) [x repmat('L', 1, CL.link(s).verdict ~= 1)], lm, num2cell(1:nS), 'UniformOutput', false); end
        rep{end+1} = sprintf('%s %s', rowl{i}, strjoin(arrayfun(@(s) sprintf('%-15s', sprintf('%s %s', ...
            vsym(VD.(LAY{f})(i, s)), lm{s})), 1:nS, 'UniformOutput', false), ' ')); %#ok<SAGROW>
    end
end
rep{end+1} = '';
rep{end+1} = sprintf(['--- Clean link per Eb/N0 (test and second test flights, and those of data/clean_test_pools.mat): ' ...
    'FA = flights with a change, LINK = packet loss at no_action, %% [95%% interval] flights verdict ---']);
rep{end+1} = sprintf('%-8s %s', 'FA', strjoin(arrayfun(@(s) pct(CL.fa(s)), 1:nS, 'UniformOutput', false), ' '));
rep{end+1} = sprintf('%-8s %s', 'LINK', strjoin(arrayfun(@(s) cell_txt(CL.link(s), '%5.2f'), 1:nS, 'UniformOutput', false), ' '));
rep{end+1} = '';
rep{end+1} = sprintf(['--- Bands of every (threat, level), Eb/N0 >= %g dB (edge speeds: the edge-speed split, nominal ' ...
    'level): %% flights verdict ---'], ebno_thr);
grp = {isp(:)', iea(:)', ial(:)', ik(:)'};
for f = 1:4
    for g = 1:numel(grp)
        ib = grp{g};
        rep{end+1} = sprintf('%s | %-49s %s', LAYN{f}, '', sprintf('%-13s', BD(ib).name)); %#ok<SAGROW>
        for i = 1:nT
            if f < 4
                x = arrayfun(@(b) band_txt(BT.(LAY{f})(i, b)), ib, 'UniformOutput', false);
            else
                x = arrayfun(@(b) sprintf('%-12s', [vsym(BT.sys(i, b)) ' ' BT.lim{i, b}]), ib, 'UniformOutput', false);
            end
            rep{end+1} = sprintf('%s | %s %s', LAYN{f}, rowl{i}, strjoin(x, ' ')); %#ok<SAGROW>
        end
    end
end
for f = {'fa', 'link'}
    rep{end+1} = sprintf('clean link %s: %s', upper(f{1}), strjoin(arrayfun(@(b) sprintf('%s %s', BD(b).name, ...
        band_txt(CB.(f{1})(b))), 1:nB, 'UniformOutput', false), ' | ')); %#ok<SAGROW>
end
fid = fopen('results/edge_map.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);

% Summary
sm = {'=== EDGE SUMMARY: WHERE THE SYSTEM IS COMMITTED ===', rep{2:6}, ''};
isg = ismember(tc, single_cells);
sm{end+1} = 'Points per layer, single threats | combined threats: COMMITTED / NOT COMMITTED / UNDETERMINED:';
for f = 1:numel(LAY)
    x = VD.(LAY{f});
    sm{end+1} = sprintf('  %-12s %4d / %4d / %4d | %4d / %4d / %4d', LAYN{f}, sum(x(isg, :) == 1, 'all'), ...
        sum(x(isg, :) == -1, 'all'), sum(x(isg, :) == 0, 'all'), sum(x(~isg, :) == 1, 'all'), sum(x(~isg, :) == -1, 'all'), ...
        sum(x(~isg, :) == 0, 'all')); %#ok<SAGROW>
end
sm{end+1} = sprintf('Clean link per Eb/N0 (%s): FA %s | LINK %s', strjoin(compose('%g', PP.ebno), '/'), ...
    strjoin(arrayfun(@(V) sprintf('%s(%d)', vsym(V.verdict), V.n), CL.fa, 'UniformOutput', false), ' '), ...
    strjoin(arrayfun(@(V) sprintf('%s(%d)', vsym(V.verdict), V.n), CL.link, 'UniformOutput', false), ' '));
sm{end+1} = sprintf('  FA committed from 15 dB down to %s; LINK down to %s', edge_txt(CE.fa.edge, CE.fa.km), ...
    edge_txt(CE.link.edge, CE.link.km));
sm{end+1} = '';
sm{end+1} = ['--- Distance: Eb/N0 from 15 dB down to the last COMMITTED point, its km (every position of a flight); ' ...
    'first NOT COMMITTED; ! COMMITTED beyond NOT COMMITTED ---'];
for i = 1:nT
    x = arrayfun(@(f) sprintf('%s %s', LAYN{f}, edge_txt(ED.(LAY{f}).edge(i), ED.(LAY{f}).km(i))), 1:numel(LAY), ...
        'UniformOutput', false);
    sm{end+1} = sprintf('%s SYSTEM %s, all positions %s; first N %s%s | %s', rowl{i}, ...
        edge_txt(ED.sys.edge(i), ED.sys.km(i)), num_txt(ED.sys.km_all(i), '%.2f km'), num_txt(ED.sys.first_not(i), '%g dB'), ...
        repmat(' !', 1, any(cellfun(@(f) ED.(f).nonmono(i), LAY))), strjoin(x([1:3 5]), ' | ')); %#ok<SAGROW>
end
sm{end+1} = '';
for f = [4 1 2 3]
    sm{end+1} = sprintf(['--- Severity, %s: per threat and Eb/N0 the highest level of the COMMITTED run from the ' ...
        'lowest level ---'], LAYN{f}); %#ok<SAGROW>
    sm{end+1} = sprintf('%-40s %s', '', sprintf('%-16s', hdr_e{:})); %#ok<SAGROW>
    for t = 1:nTh
        x = arrayfun(@(s) sev_txt(SV.(LAY{f}).edge(t, s), SV.(LAY{f}).nonmono(t, s), THR{t}, C, PP), 1:nS, 'UniformOutput', false);
        sm{end+1} = sprintf('%-40s %s', THR{t}, sprintf('%-16s', x{:})); %#ok<SAGROW>
    end
end
sm{end+1} = '';
sm{end+1} = sprintf(['--- Speed, altitude, K over Eb/N0 >= %g dB: SYSTEM [DET, SURV, REC]; the COMMITTED run around %s ' ...
    'and %s; hover and 161 km/h (nominal level); K down from 15-20 dB (and with the lowest band from %g dB) ---'], ...
    ebno_thr, BD(isp(i0v)).name, BD(ial(2)).name, K_READ);
for i = 1:nT
    q = [RN.sys, RN.det, RN.surv, RN.rec];
    sm{end+1} = sprintf('%s speed %s | hover %s, 161 km/h %s | altitude %s | K from %s (reading %s)', rowl{i}, ...
        per_layer(arrayfun(@(E) [range_txt(E.v(i, :), 'km/h') repmat(' !', 1, E.v_nonmono(i))], q, 'UniformOutput', false)), ...
        per_layer(arrayfun(@(E) vsym_nan(E.edge_v(i, 1)), q, 'UniformOutput', false)), ...
        per_layer(arrayfun(@(E) vsym_nan(E.edge_v(i, 2)), q, 'UniformOutput', false)), ...
        per_layer(arrayfun(@(E) [range_txt(E.alt(i, :), 'm') repmat(' !', 1, E.alt_nonmono(i))], q, 'UniformOutput', false)), ...
        per_layer(arrayfun(@(E) [num_txt(E.kmin(i), '%g dB') repmat(' !', 1, E.k_nonmono(i))], q, 'UniformOutput', false)), ...
        per_layer(arrayfun(@(E) num_txt(E.kmin_read(i), '%g dB'), q, 'UniformOutput', false))); %#ok<SAGROW>
end
sm{end+1} = '';
sm{end+1} = sprintf(['--- Overhead pass (overhead_pass.m, results/overhead_pass.mat): path_loss SYSTEM at the smallest ' ...
    'level >= the drop; C when the tracker-lost bound (+%g dB) is, N when the tracked bound (+%.2f dB) is not; ' ...
    '* the lost bound above %g dB, not measured ---'], OHP.lost_db, OHP.track_db, OHP.pl_top_db);
x = arrayfun(@(e, r) sprintf('%g dB %.2f km', e, r), OHP.ebno, OHP.r0_km, 'UniformOutput', false);
sm{end+1} = sprintf('%-10s %s', 'altitude', sprintf('%-16s', x{:}));
for h = 1:numel(OHP.alt_m)
    x = arrayfun(@(j) sprintf('%s%s', vsym_nan(OV(h, j)), repmat('*', 1, isnan(OLl(h, j)) && ~isnan(OV(h, j)))), ...
        1:numel(OHP.ebno), 'UniformOutput', false);
    sm{end+1} = sprintf('%-10s %s', sprintf('%g m', OHP.alt_m(h)), sprintf('%-16s', x{:})); %#ok<SAGROW>
end
sm{end+1} = '';
sm{end+1} = '--- Detector beyond 0-15 dB (eval_unseen_snr.m) and between trained levels (eval_unseen_severity.m) ---';
if isempty(B4)
    sm{end+1} = '  no edge points in results/unseen_snr.mat';
else
    for c = unique({B4.cls}, 'stable')
        x = B4(strcmp({B4.cls}, c{1}));
        sm{end+1} = sprintf('  %-22s %s', c{1}, strjoin(arrayfun(@(q) sprintf('%g dB (%.2f km) %s', q.ebno, ...
            link_distance_km(q.ebno, p0), cell_txt(q, '%5.1f')), x, 'UniformOutput', false), ' | ')); %#ok<SAGROW>
    end
end
if ~isempty(B4s)
    sm{end+1} = sprintf('  between trained levels (one block per Eb/N0, fewer than %d: generalization evidence):', N_MIN);
    for q = 1:numel(B4s)
        sm{end+1} = sprintf('    %-22s %7g %s', B4s(q).threat, B4s(q).level, cell_txt(B4s(q), '%5.1f')); %#ok<SAGROW>
    end
end
sm{end+1} = '';
mt = ismember(FT.c, tc) & in_pt & FT.surv & FT.eb >= ebno_thr;
sm{end+1} = sprintf('Recovered among recoverable episodes, every threat point at Eb/N0 >= %g dB: %s', ebno_thr, ...
    strjoin(arrayfun(@(pk) sprintf('%s %.1f%%', LBL{pk}, 100 * sum(FT.rec_k(mt, pk)) / sum(FT.rec_n(mt, pk))), 1:nP, ...
    'UniformOutput', false), ' | '));
sm{end+1} = sprintf('False alarms of the clean link, every flight at Eb/N0 >= %g dB: %s', ebno_thr, ...
    strjoin(arrayfun(@(pk) sprintf('%s %d/%d', LBL{pk}, sum(CF.fa_k(CF.eb >= ebno_thr, pk) > 0), ...
    sum(CF.fa_n(CF.eb >= ebno_thr, pk) > 0)), 1:nP, 'UniformOutput', false), ' | '));
sm{end+1} = ['Each "up to" edge is a fixed-sequence walk at 5% family error; per-point verdicts hold per point. The policy ' ...
    'is not measured beyond 0-15 dB; no level above the top one is simulated (every top level is the source cap).'];
fid = fopen('results/edge_summary.txt', 'w'); fprintf(fid, '%s\n', sm{:}); fclose(fid);
fprintf('%s\n', sm{:});

%% 10. Figures
tx = @(V) ternary(V.n > 0, sprintf('%.0f\n%d', 100 * V.value, V.n), '-');
for f = 1:4
    if f < 4
        X = arrayfun(tx, PT.(LAY{f}), 'UniformOutput', false);
        nm = LAY{f};
    else
        X = cellfun(@(l, V) sprintf('%s\n%d', ternary(isempty(l), 'ok', l), V.n), PT.lim, num2cell(PT.surv), 'UniformOutput', false);
        nm = 'system';
    end
    draw_map(sprintf('results/edge_heatmap_%s.png', nm), sprintf('%s per (threat, level) and Eb/N0, deployed policy', ...
        LAYN{f}), VD.(LAY{f}), X, rows_of, THR, lv_txt, PP.ebno, km);
end
VBc = [VB.sys; [CB.fa.verdict]; [CB.link.verdict]];
fig = figure('Position', [40 40 1100, 120 + 13 * size(VBc, 1)], 'Color', 'w');
image(verdict_rgb(VBc));
set(gca, 'XTick', 1:nB, 'XTickLabel', {BD.name}, 'XTickLabelRotation', 45, 'YTick', 1:size(VBc, 1), ...
    'YTickLabel', [lbl, {'clean link FA', 'clean link LINK'}], 'FontSize', 6, 'TickLabelInterpreter', 'none');
title(sprintf(['SYSTEM per band (Eb/N0 >= %g dB), and the clean link: green COMMITTED, amber UNDETERMINED, red NOT ' ...
    'COMMITTED, white no flight'], ebno_thr), 'FontSize', 8);
saveas(fig, 'results/edge_bands.png'); close(fig);

%% 11. Save
EM = struct('ebno', PP.ebno, 'km', km, 'all_pos', LB.all_pos, 'targets', TGT, 'n_min', N_MIN, 'B', B, ...
    'ebno_thr', ebno_thr, 'deployed', NAMES.(dep), 'policies', {LBL}, 'cells', tc, 'labels', {lbl}, 'basis', {basis}, ...
    'between', between, 'pt', PT, 'clean', CL, 'bands', {BD}, 'bt', BT, 'cb', CB, 'dist', ED, 'clean_dist', CE, ...
    'sev', SV, 'threats', {THR}, 'runs', RN, 'ohp', struct('alt_m', OHP.alt_m, 'ebno', OHP.ebno, 'r0_km', OHP.r0_km, ...
    'verdict', OV, 'level_tracked', OLt, 'level_lost', OLl), 'b4', B4, 'b4s', B4s, 'created', datestr(now));
inom = find(ismember(tc, nom));
EDGE_NUM = struct('ebno', PP.ebno, 'km', km, 'ebno_thr', ebno_thr, 'deployed', NAMES.(dep), 'n_min', N_MIN, ...
    'targets', TGT, 'layers', {LAYN}, ...
    'counts_single', cell2mat(cellfun(@(f) [sum(VD.(f)(isg, :) == 1, 'all'), sum(VD.(f)(isg, :) == -1, 'all'), ...
        sum(VD.(f)(isg, :) == 0, 'all')], LAY', 'UniformOutput', false)), ...
    'counts_combined', cell2mat(cellfun(@(f) [sum(VD.(f)(~isg, :) == 1, 'all'), sum(VD.(f)(~isg, :) == -1, 'all'), ...
        sum(VD.(f)(~isg, :) == 0, 'all')], LAY', 'UniformOutput', false)), ...
    'cells', {lbl}, 'basis', {basis}, 'edge_sys_db', ED.sys.edge', 'edge_sys_km', ED.sys.km', ...
    'edge_sys_km_all', ED.sys.km_all', 'edge_sysl_db', ED.sysl.edge', 'first_not_sys_db', ED.sys.first_not', ...
    'nominal', {lbl(inom)}, 'hover', RN.sys.edge_v(inom, 1)', 'v161', RN.sys.edge_v(inom, 2)', ...
    'fa_verdict', [CL.fa.verdict], 'fa_n', [CL.fa.n], 'link_verdict', [CL.link.verdict], 'link_n', [CL.link.n], ...
    'fa_edge_db', CE.fa.edge, 'link_edge_db', CE.link.edge, 'ohp_verdict', OV, 'ohp_alt_m', OHP.alt_m, 'ohp_r0_km', OHP.r0_km, ...
    'b4', B4);
save('results/edge_map.mat', 'EM', 'EDGE_NUM', 'FT', 'CF', 'CS');
fprintf('Saved results/edge_map.{txt,mat}, results/edge_summary.txt, results/edge_bands.png, ');
fprintf('results/edge_heatmap_{det,surv,rec,system}.png (%.1f min)\n', toc(t0) / 60);

%% ===================== Local functions =====================
function specs = cell_episodes(PP, cells, sp, reps, follow, NE, T, rs)
% Episodes of the cells on the geometries each flies in split sp (PP.cell_geo), one
% policy_episodes.m call per geometry list.
specs = {};
if isempty(cells), return; end
g = arrayfun(@(c) mat2str(PP.cell_geo{c}{sp}), cells, 'UniformOutput', false);
[u, ~, j] = unique(g, 'stable');
for k = 1:numel(u)
    cc = cells(j == k); rr = PP.cell_geo{cc(1)}{sp};
    if isempty(rr), continue; end
    specs = [specs, policy_episodes(cc, numel(PP.ebno), rr, reps, follow, false, NE, T, rs)]; %#ok<AGROW>
end
end

function L = threat_layers(F, TGT, B)
% DET, SURV and REC of the deployed policy (column 1) over the flights F, and SYSTEM.
L.det = edge_verdict(F.det_k, F.det_n, F.geo, TGT.det, 'ge', false, B);
L.surv = edge_verdict(double(F.surv), ones(size(F.geo)), F.geo, TGT.surv, 'ge', true, B);
L.rec = edge_verdict(F.rec_k(F.surv, 1), F.rec_n(F.surv, 1), F.geo(F.surv), TGT.rec, 'ge', true, B);
[L.sys, L.lim] = all_of([L.det.verdict, L.surv.verdict, L.rec.verdict], 'DSR');
end

function L = clean_layers(F, TGT, B)
% FA (deployed policy) and LINK over the clean-link flights F.
L.fa = edge_verdict(F.fa_k(:, 1), F.fa_n(:, 1), F.geo, TGT.fa, 'le', true, B);
L.link = edge_verdict(F.link_k, F.link_n, F.geo, TGT.link, 'le', false, B);
end

function [v, lim] = all_of(vd, names)
% A conjunction: COMMITTED when every part is, NOT COMMITTED when one is not; the parts
% that are not COMMITTED.
if all(vd == 1), v = 1; elseif any(vd == -1), v = -1; else, v = 0; end
lim = names(vd ~= 1);
end

function W = walk(vd, x)
% Fixed-sequence walk along vd (walk order) at the values x: the last value of the
% leading COMMITTED run (NaN when the first point is not COMMITTED), the first NOT
% COMMITTED value, and whether a COMMITTED point lies beyond a NOT COMMITTED one.
i = find(vd ~= 1, 1); if isempty(i), i = numel(vd) + 1; end
W.edge = NaN; if i > 1, W.edge = x(i - 1); end
j = find(vd == -1, 1);
W.first_not = NaN; if ~isempty(j), W.first_not = x(j); end
W.nonmono = ~isempty(j) && any(vd(j+1:end) == 1);
end

function W = run_around(vd, i0)
% Contiguous run of COMMITTED bands around band i0 (NaN when i0 is not COMMITTED), and
% whether a COMMITTED band lies beyond a NOT COMMITTED one on either side.
W = struct('a', NaN, 'b', NaN, 'nonmono', false);
if vd(i0) == 1
    a = i0; while a > 1 && vd(a - 1) == 1, a = a - 1; end
    b = i0; while b < numel(vd) && vd(b + 1) == 1, b = b + 1; end
    W.a = a; W.b = b;
end
for k = {i0:numel(vd), i0:-1:1}
    x = vd(k{1}); j = find(x == -1, 1);
    W.nonmono = W.nonmono || (~isempty(j) && any(x(j+1:end) == 1));
end
end

function [v, lv] = level_verdict(drop, lvs, vds)
% Verdict at the smallest level at or above the drop; NaN beyond the top level.
k = find(lvs >= drop, 1);
if isempty(k), v = NaN; lv = NaN; else, v = vds(k); lv = lvs(k); end
end

function m = in_band(F, b)
% Flights of band b: [lo, hi), the top band of an axis closed; edge speeds exactly.
switch b.axis
    case {'speed', 'edge'}, x = F.speed;
    case 'alt', x = F.alt;
    case 'k', x = F.ksig;
end
m = x >= b.lo & (x < b.hi | (b.top & x <= b.hi));
end

function i = flight_of(IDX, c, s, sp, run, runs)
% Flight row of every frame of a pool.
[~, r] = ismember(run, runs);
i = IDX(sub2ind(size(IDX), c + 0 * r, s + 0 * r, sp + 0 * r, r));
end

function pos = run_pos(run)
% Position of every frame in its run (the frames of a run are consecutive).
st = [true; diff(run(:)) ~= 0];
i0 = find(st);
pos = (1:numel(run))' - i0(cumsum(st)) + 1;
end

function S = take_rows(S, m)
f = fieldnames(S);
for i = 1:numel(f), S.(f{i}) = S.(f{i})(m, :); end
end

function S = cat_rows(S, Sb)
f = fieldnames(S);
for i = 1:numel(f), S.(f{i}) = [S.(f{i}); Sb.(f{i})]; end
end

function ii = sort_by_sev(ii, sev)
[~, o] = sort(sev(ii)); ii = ii(o);
end

function s = vsym(v)
s = {'N', 'U', 'C'}; s = s{v + 2};
end

function s = vsym_nan(v)
if isnan(v), s = '-'; else, s = vsym(v); end
end

function s = cell_txt(V, f)
% value [lo, hi] n verdict, in %.
if V.n == 0, s = sprintf('%-28s', '-'); return; end
s = sprintf('%s [%s, %s] %3d %s', sprintf(f, 100 * V.value), sprintf(f, 100 * V.lo), sprintf(f, 100 * V.hi), V.n, ...
    vsym(V.verdict));
end

function s = band_txt(V)
if V.n == 0, s = sprintf('%-12s', '-'); else, s = sprintf('%-12s', sprintf('%.1f %d%s', 100 * V.value, V.n, vsym(V.verdict))); end
end

function s = edge_txt(e, d)
if isnan(e), s = 'none'; else, s = sprintf('%g dB (%.2f km)', e, d); end
end

function s = per_layer(x)
% SYSTEM's value, then DET, SURV and REC.
s = sprintf('%s [D %s, S %s, R %s]', x{:});
end

function s = num_txt(x, f)
if isnan(x), s = '-'; else, s = sprintf(f, x); end
end

function s = range_txt(r, u)
if any(isnan(r)), s = 'none'; else, s = sprintf('%.0f-%.0f %s', r(1), r(2), u); end
end

function s = sev_txt(e, nm, threat, C, PP)
% Highest level of the COMMITTED run: the level of a single threat, the severity name of
% a combined one.
if isnan(e)
    s = 'none';
elseif contains(threat, '+')
    s = PP.sev_names{e};
else
    s = sprintf('%g dB', C.sev.(threat).levels(e));
end
if nm, s = [s ' !']; end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end

function rgb = verdict_rgb(v)
% Colour of every verdict: red NOT COMMITTED, amber UNDETERMINED, green COMMITTED, white none.
col = [0.86 0.27 0.22; 0.98 0.80 0.30; 0.30 0.69 0.31];
rgb = ones([size(v) 3]);
for q = -1:1
    for ch = 1:3
        x = rgb(:, :, ch); x(v == q) = col(q + 2, ch); rgb(:, :, ch) = x;
    end
end
end

function draw_map(file, ttl, VD, TX, rows_of, names, ylab, ebno, km)
% One panel per threat: its levels x Eb/N0 in the verdict colours with the cell text,
% the distance of every Eb/N0 on the top axis.
nt = numel(rows_of); nc = ceil(sqrt(1.6 * nt)); nr = ceil(nt / nc);
fig = figure('Position', [30 30 300 * nc, 60 + 210 * nr], 'Color', 'w');
ax = gobjects(1, nt);
for t = 1:nt
    i = rows_of{t};
    ax(t) = subplot(nr, nc, t);
    image(ax(t), verdict_rgb(VD(i, :))); hold(ax(t), 'on');
    for a = 1:numel(i)
        for b = 1:numel(ebno)
            text(ax(t), b, a, TX{i(a), b}, 'HorizontalAlignment', 'center', 'FontSize', 6);
        end
    end
    set(ax(t), 'XTick', 1:numel(ebno), 'XTickLabel', compose('%g', ebno), 'YTick', 1:numel(i), 'YTickLabel', ylab(i), ...
        'FontSize', 7, 'TickLabelInterpreter', 'none');
    xlabel(ax(t), 'E_b/N_0 [dB]', 'FontSize', 7);
    title(ax(t), strrep(names{t}, '_', ' '), 'FontSize', 8, 'Units', 'normalized', 'Position', [0.5 1.13 0]);
end
sgtitle(fig, ttl, 'FontSize', 10);
for t = 1:nt
    ax(t).Position(4) = 0.8 * ax(t).Position(4);       % room for the distance axis and the title
    axes(fig, 'Position', ax(t).Position, 'XAxisLocation', 'top', 'Color', 'none', 'XLim', ax(t).XLim, ...
        'YTick', [], 'XTick', 1:numel(ebno), 'XTickLabel', compose('%.2f km', km), 'FontSize', 6);
end
saveas(fig, file); close(fig);
end

function LB = link_budget()
% The km axis of the results (link_budget_table.m, in its own workspace).
link_budget_table;
L = load('results/link_budget.mat', 'LB'); LB = L.LB;
end

function OHP = overhead()
% The overhead pass when its stage has not run (overhead_pass.m, in its own workspace).
overhead_pass;
L = load('results/overhead_pass.mat', 'OHP'); OHP = L.OHP;
end
