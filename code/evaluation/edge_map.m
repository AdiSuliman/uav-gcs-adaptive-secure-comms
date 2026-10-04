%% EDGE_MAP - Where the system is committed: a verdict at every point of the envelope
% Reads the test pools (data/policy_pools.mat: the test and second test splits give 72
% flights per (cell, Eb/N0) to the clean link and the single threats, 36 to the combined
% threats; the edge-speed split flies hover at every level of the single threats and 161
% km/h at the nominal level), the clean-link pools of data/clean_test_pools.mat, the
% off-grid check flights of data/check_pools.mat, the leave-one-out agents of
% data/unknown_threat_agents.mat and the trained policy, all from the same detector
% (check_det_id.m). Restoration is judged against the same flight's clean link
% (link_env.m 'flight'). The deployed policy as train_dqn.m chose it (the selected DQN
% with escalation, or the rule with escalation on its own monitor) runs every flight at
% the signalling delays DLY (cycles from a decision to the first frame the link runs it
% on: the model's 1, 2, and 7, about the 141 ms switch Barajas et al. measured); no
% response, the rule with escalation, the one-step oracle, the random policy and the
% receiver alone (always-on MMSE: no request to the GCS after the onset) at the first.
% Sets: single and combined threats (static); the four followable threats with a
% follower that re-acquires the channel 0, 1 or 2 cycles after a hop (the sources'
% 1-50 ms); a jammer on every channel (comb, the jamming cells); the clean link; the
% single threats with the detector output withheld after the onset (unknown: the
% leave-one-out agent of the threat when the DQN is deployed; evidence only, no rate is
% committed for an emitter outside the detector's classes).
% Layers and targets:
%   DET    fused detection of the deployed detector (fused_class.m) on the
%          threat-active frames at no_action (threat_active.m): the class calls for
%          the countermeasure of the threat (rule_based_policy.m), for a combined
%          threat that of one of its components                                >= 90%
%   DET_h  DET on the flights whose unmitigated link is not restored (harmed)   >= 90%
%   SURV   flights some configuration restores (link_env.m); follower rows: one
%          without channel_switch; comb rows: without channel_switch and
%          freq_diversity                                                       >= 90%
%   REC    held recovery among the recoverable flights: restored for 5 cycles and
%          on every cycle after, but one follower re-acquisition of 1 + D cycles
%          (rollout_policy.m); a flight succeeds when all its episodes do      >= 90%
%   PROT   held recovery among all threat flights                              >= 90%
%   LINK_T packet loss from the start of the recovery run to the end of the episode,
%          pooled over the point     <= max(2x the same flights' clean link, 1.4%)
%   FA     clean link: flights with a configuration change (KPI 6)              <= 5%
%   LINK   clean link: packet loss at no_action. 802.11's PER < 10% at a 1000-byte
%          PSDU (Keysight AN Table 7, BER 1.3e-5) on our 129-byte frames         <= 1.4%
%   COMMITTED, the commitment, per signalling delay: PROT, DET_h, FA, LINK and LINK_T
%          COMMITTED (DET_h only not NOT COMMITTED below 36 harmed flights; FA that of
%          the claim, the clean flights of every Eb/N0 from the KPI 1 threshold up (KPI 6)
%          or from the point up for a point below it, and the point's own FA not NOT
%          COMMITTED), the deployed policy within the false-alarm bound on validation (F),
%          and no band of the point NOT COMMITTED (B): speed, altitude, K, alignment of
%          the first interferer with the GCS (directional threats), receive correlation,
%          bank and delay spread where PP.cov records them, pooled over the point and the
%          COMMITTED points above it in the distance walk (edge speeds: verdicts of
%          their own)
%   SYSTEM DET, SURV and REC COMMITTED and F (the proposal's relative criterion);
%          SYSTEM+LINK with LINK
% A point where the random policy's PROT is COMMITTED too is not attributable to the
% decision layer (r). The receiver alone (its PROT, LINK and LINK_T) is the floor
% without signalling. Horizon: held for the rest of a 0.6 s episode (at most 0.54 s
% after the onset).
% Interval and verdict: edge_verdict.m (95%, bootstrap over flights and Clopper-Pearson,
% COMMITTED / NOT COMMITTED / UNDETERMINED, at least 36 flights to commit).
% Tables per (threat, level, Eb/N0 with its distance, link_distance_km.m), per Eb/N0 for
% the clean link, and per band of each (threat, level) over the Eb/N0 from the KPI 1
% threshold up (fixed on validation; all six points without one); a band commits with
% the claim's FA and its own clean flights' FA not NOT COMMITTED. Per-point verdicts are
% for moving flights; hover is hover in calm air (a frozen channel). Edges, every layer
% apart: fixed-sequence walks that stop at the first point not COMMITTED (each "up to"
% claim keeps a 5% family error): Eb/N0 from 15 dB down (its km, and x0.63 for every
% position of a flight, link_budget_table.m), levels from the nominal one down and up,
% follower re-acquisition from 2 cycles down to 0, the run of speed and altitude bands
% around the nominal band, K down from 15-20 dB; a COMMITTED point beyond a NOT
% COMMITTED one is flagged (!), and a COMMITTED point outside every walk is reported,
% not committed. Off-grid check points (build_check_pools.m: between the Eb/N0 points at
% the nominal level, between the levels at 9 dB, 36 flights each): an "up to" edge that
% spans a check point NOT COMMITTED stops before it (x); an edge that spans none (levels
% at another Eb/N0, distance at another level) holds at the grid points it lists only.
% Overhead pass (overhead_pass.m): the path_loss commitment at the smallest level at or
% above the drop, COMMITTED when the tracker-lost bound is, NOT COMMITTED when the
% tracked bound is not; a drop above the top level is not measured. The detector beyond
% 0-15 dB and between levels: eval_unseen_snr.m and eval_unseen_severity.m.
% Level basis: the spoofer at 30 dB, the open connector and WLAN at 30 dB are assumed
% levels, the others measured; * marks a level the detector never trained on; the comb
% row is assumed (no source jams every channel).
% Output: results/edge_map.{txt,mat}, results/edge_summary.txt, results/edge_bands.png,
% results/edge_heatmap_{det,surv,rec,prot,system,commit}.png, results/link_budget.{txt,mat}

close all; clc;
fprintf('=== Edge map: a verdict at every point of the envelope ===\n\n');

%% 1. Inputs
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
if ~isfield(PP, 'cov') || ~isfield(PP, 'cell_geo') || numel(PP.runs) < 5
    error('edge_map: the pools have no second test split or flight draws (built before v7-D74); run build_policy_pools');
end
Q = load('data/trained_dqn.mat', 'agent', 'agents', 'gammas', 'H', 'seed_summary', 'confirm', 'alarm_mode', 'drop_db', ...
    'deployed', 'rule_sel', 'fa_bound_met', 'det_id');
check_det_id(PP, Q, 'edge_map');
PP.confirm = Q.confirm; PP.alarm_mode = Q.alarm_mode;           % the monitor of evaluate_policies.m
if ~isempty(Q.drop_db), PP.drop_db = Q.drop_db; end
K = link_env('tables', PP, 'flight');
C = decision_config();
p0 = load('params.mat').params;
TEST = 3; SPEED = 4; TEST2 = 5; SPL = [TEST TEST2];
T = Q.H.T; NE = 64; REPS = 2; B = 4000;
TGT = struct('det', 0.90, 'surv', 0.90, 'rec', 0.90, 'prot', 0.90, 'fa', 0.05, 'link', 0.014);
DLY = unique([C.switch_delay 2 7], 'stable');   % [cycles] signalling delays, the model's first
FDL = [0 1 2];                  % [cycles] follower re-acquisition after a hop
K_READ = -3;                    % [dB] lowest in-flight K near 2.4 GHz (Aoki et al.): second reading of the lowest band
HOVER = 'hover in calm air (attitude within +-1 deg, Lin 2026; a frozen channel)';   % what the hover flights stand for
if exist('SMOKE', 'var') && SMOKE, REPS = 1; B = 400; end       % reduced chain check (run_stage smoke)
nS = numel(PP.ebno); nC = numel(PP.scen); nD = numel(DLY);
single_cells = find(ismember(PP.scen, PP.singles) & ~strcmp(PP.scen, 'none'));
combo_cells = find(ismember(PP.scen, PP.combos));
clean_cell = K.clean;
tc = [single_cells, combo_cells]; nT = numel(tc);
foll = single_cells(K.followable(single_cells));
nom = single_cells(PP.sev(single_cells) == C.nominal);
jam = foll(ismember(PP.scen(foll), {'jamming', 'reactive_jamming'}));   % the comb row
ebno_thr = PP.ebno(1);                                % bands from the KPI 1 threshold (all six points without one)
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
dep = Q.deployed;                                     % deployed policy (train_dqn.m)
FAV = double(Q.fa_bound_met);                         % false-alarm bound met on validation: else no point commits
fixed_mmse = find(strcmp(PP.actions, 'spatial_diversity'), 1);
POL = unique({dep, 'none', 'rule_esc', 'oracle', 'random', 'fixed_mmse'}, 'stable'); nP = numel(POL);
NAMES = struct('dqn_esc', 'DQN + escalation', 'rule_sel', 'rule + escalation, own monitor', 'none', 'no response', ...
    'rule_esc', 'rule + escalation', 'oracle', 'oracle (one-step)', 'random', 'random', ...
    'fixed_mmse', 'receiver only (always-on MMSE)');
LBL = cellfun(@(p) NAMES.(p), POL, 'UniformOutput', false);
iRnd = find(strcmp(POL, 'random')); iMm = find(strcmp(POL, 'fixed_mmse'));

% Every (threat, level): label, level basis, levels the detector never trained on, an
% interferer with a direction
DL = dataset_levels();
DIRQ = {'jamming', 'noise_burst', 'reactive_jamming', 'sweeping_jammer', 'tone_jamming', 'spoofing', 'benign_interference'};
lbl = cell(1, nT); basis = repmat({'measured'}, 1, nT); between = false(1, nT); lv_txt = cell(1, nT); dirc = false(1, nT);
for i = 1:nT
    c = tc(i); comp = strsplit(PP.scen{c}, '+');
    if isscalar(comp), lv_txt{i} = sprintf('%g dB', PP.level(c)); else, lv_txt{i} = PP.sev_names{PP.sev(c)}; end
    lbl{i} = [PP.scen{c} ' ' lv_txt{i}];
    dirc(i) = any(ismember(comp, DIRQ));
    for q = comp
        lv = C.sev.(q{1}).levels(PP.sev(c));
        if strcmp(q{1}, 'antenna_fault') || (ismember(q{1}, {'spoofing', 'benign_interference'}) && lv >= 30)
            basis{i} = 'assumed';                     % no source measured the level
        end
        between(i) = between(i) || ~any(abs(DL(strcmp({DL.name}, q{1})).levels - lv) < 1e-9);
    end
end
ifo = find(ismember(tc, foll)); ij = find(ismember(tc, jam));

% Per (cell, Eb/N0, split, geometry): recoverable against a follower (a configuration
% without channel_switch restores) and harmed (no_action does not restore)
okA = K.restored & K.restored_plr;
sz = [nC nS numel(PP.runs) max(K.nR)];
RF = reshape(any(okA(:, :, ~K.hasCh, :, :), 3), sz);
HM = ~reshape(okA(:, :, K.na, :, :), sz);
clear okA

%% 2. Episodes of every policy on every flight
% Base sets (the same onsets and frame draws at every signalling delay); the deployed
% policy at every delay, every policy at the first
rs = RandStream('mt19937ar', 'Seed', 2074);
BS = struct('name', {}, 'kind', {}, 'fd', {}, 'spec', {}, 'split', {}, 'ag', {});
for sp = [SPL SPEED]
    cc = combo_cells; cw = intersect(single_cells, foll, 'stable'); cj = jam;
    if sp == SPEED, cc = []; cw = []; cj = []; end
    LS = {'single', 'static', NaN, single_cells; 'combined', 'static', NaN, cc; 'clean', 'clean', NaN, clean_cell; ...
        'comb', 'comb', 0, cj};
    for f = FDL, LS(end+1, :) = {sprintf('follow %d', f), 'follow', f, cw}; end %#ok<SAGROW>
    for k = 1:size(LS, 1)
        fol = any(strcmp(LS{k, 2}, {'follow', 'comb'}));
        reps = REPS; if strcmp(LS{k, 2}, 'clean'), reps = 1; end
        fd = []; if ~isnan(LS{k, 3}), fd = LS{k, 3} * [1 1]; end
        spec = cell_episodes(PP, LS{k, 4}, sp, reps, fol, false, NE, T, rs, fd);
        if strcmp(LS{k, 2}, 'comb')                   % on every channel: at the hop itself, both carriers
            for b = 1:numel(spec), spec{b}.comb = true(1, NE); end
        end
        if ~isempty(spec)
            BS(end+1) = struct('name', LS{k, 1}, 'kind', LS{k, 2}, 'fd', LS{k, 3}, 'spec', {spec}, 'split', sp, ...
                'ag', 0); %#ok<SAGROW>
        end
    end
end
% The unknown path: the detector output withheld after the onset; the leave-one-out
% agent of each threat when the DQN is deployed (experiment_unknown_threat.m)
U = [];
if isfile('data/unknown_threat_agents.mat')
    U = load('data/unknown_threat_agents.mat', 'agents_loo', 'threats', 'det_id');
    check_det_id(PP, U, 'edge_map');
end
if ~isempty(U) || ~strcmp(dep, 'dqn_esc')
    grp = {single_cells}; ga = 0;
    if strcmp(dep, 'dqn_esc')
        grp = cellfun(@(t) single_cells(strcmp(PP.scen(single_cells), t)), U.threats, 'UniformOutput', false);
        ga = 1:numel(U.threats);
    end
    for g = 1:numel(grp)
        for sp = SPL
            spec = cell_episodes(PP, grp{g}, sp, REPS, false, true, NE, T, rs, []);
            if ~isempty(spec)
                BS(end+1) = struct('name', 'unknown', 'kind', 'unknown', 'fd', NaN, 'spec', {spec}, 'split', sp, ...
                    'ag', ga(min(g, end))); %#ok<SAGROW>
            end
        end
    end
end
RUN = struct('b', {}, 'D', {}, 'pols', {});
for d = 1:nD
    for b = 1:numel(BS)
        if d > 1 && (BS(b).split == SPEED || any(strcmp(BS(b).kind, {'comb', 'unknown'}))), continue; end
        pols = 1:nP; if d > 1 || strcmp(BS(b).kind, 'unknown'), pols = 1; end
        RUN(end+1) = struct('b', b, 'D', DLY(d), 'pols', pols); %#ok<SAGROW>
    end
end
VAR = struct('kind', {}, 'fd', {}, 'D', {}, 'pol', {});
RES = cell(numel(RUN), nP); RV = zeros(numel(RUN), nP);   % episodes and variant of every run
t0 = tic;
for ri = 1:numel(RUN)
    bs = BS(RUN(ri).b);
    spec = bs.spec; for k = 1:numel(spec), spec{k}.delay = RUN(ri).D; end
    for pk = RUN(ri).pols
        [kind, ag, opt] = policy_setup(POL{pk}, Q, sel, [], fixed_mmse, [], K.na);
        if bs.ag > 0, ag = U.agents_loo{bs.ag}; end
        RES{ri, pk} = policy_run_set(kind, PP, K, spec, bs.split, ag, opt, 200000 + 1000 * RUN(ri).b);
        [VAR, RV(ri, pk)] = var_add(VAR, bs.kind, bs.fd, RUN(ri).D, pk);
    end
    fprintf('  %-9s %-6s D %d %6d episodes x %d policies (%.1f min)\n', bs.name, PP.splits{bs.split}, RUN(ri).D, ...
        numel(RES{ri, RUN(ri).pols(1)}.ret), numel(RUN(ri).pols), toc(t0) / 60);
end
% The clean link on the flights of data/clean_test_pools.mat, one episode per flight, the
% same onsets and frame draws at every delay
RW = cell(nD, nP); CT = [];
if isfile('data/clean_test_pools.mat')
    L = load('data/clean_test_pools.mat', 'CT'); CT = L.CT; clear L
    PPw = PP;
    PPw.pools(:) = {[]};
    PPw.pools(clean_cell, :, :, TEST) = reshape(CT.pools(1, :, :), [1 nS numel(PP.actions)]);
    PPw.runs{TEST} = CT.runs; PPw.speed{TEST} = CT.speed;
    PPw.cell_geo{clean_cell}{TEST} = 1:CT.n_geom;
    Kw = link_env('tables', PPw, 'flight');
    spec = cell_episodes(PPw, clean_cell, TEST, 1, false, false, NE, T, rs, []);
    for d = 1:nD
        for k = 1:numel(spec), spec{k}.delay = DLY(d); end
        pks = 1:nP; if d > 1, pks = 1; end
        for pk = pks
            [kind, ag, opt] = policy_setup(POL{pk}, Q, sel, [], fixed_mmse, [], K.na);
            RW{d, pk} = policy_run_set(kind, PPw, Kw, spec, TEST, ag, opt, 40000);
            VAR = var_add(VAR, 'clean', NaN, DLY(d), pk);
        end
    end
    fprintf('  clean     C1c    %6d episodes (%.1f min)\n', numel(RW{1, 1}.ret), toc(t0) / 60);
    clear PPw Kw
end
nV = numel(VAR);

%% 3. Flights
% One row per flight a threat cell or the clean link flies in the test splits and the
% edge-speed split; flight id 1e6 split + 1000 Eb/N0 + geometry (the bootstrap cluster).
% Per variant (set kind, follower delay, signalling delay, policy) one column: episodes,
% held, recovered (KPI 4), lost packets and frames after recovery; clean: flights with a
% change, episodes, changes
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
ii = sub2ind(size(K.recoverable), fc, fs, fsp, fr);
Z = zeros(nF, nV); E1 = nan(nF, 1);
FT = struct('c', fc, 'sp', fsp, 's', fs, 'r', fr, 'geo', 1e6 * fsp + 1000 * fs + fr, 'eb', reshape(PP.ebno(fs), [], 1), ...
    'speed', E1, 'alt', E1, 'ksig', E1, 'rho', E1, 'align', E1, 'bank', E1, 'ds', E1, ...
    'surv', K.recoverable(ii), 'surv_f', RF(ii), 'surv_c', K.recoverable_comb(ii), 'harm', HM(ii), ...
    'det_k', zeros(nF, 1), 'det_n', zeros(nF, 1), 'link_k', zeros(nF, 1), 'link_n', zeros(nF, 1), 'cl_k', E1, 'cl_n', E1, ...
    'ep_n', Z, 'held_k', Z, 'rec_k', Z, 'lt_k', Z, 'lt_n', Z, 'fa_k', Z, 'fa_n', Z, 'sw_k', Z);
clear Z RF HM
% Covariates of the bands (PP.cov); a band whose field the pools do not record is skipped
COV = {'alt', 'alt_m'; 'ksig', 'k_sig'; 'rho', 'rho'; 'bank', 'bank'; 'ds', 'ds_ns'};
has_cov = cellfun(@(f) all(cellfun(@(V) isfield(V, f), PP.cov([SPL SPEED]))), COV(:, 2))';
for sp = [SPL SPEED]
    m = FT.sp == sp; j = sub2ind(size(PP.speed{sp}), FT.s(m), FT.r(m));
    FT.speed(m) = PP.speed{sp}(j);
    for q = find(has_cov), FT.(COV{q, 1})(m) = PP.cov{sp}.(COV{q, 2})(j); end
    if isfield(PP.cov{sp}, 'align'), A1 = PP.cov{sp}.align(:, :, 1); FT.align(m) = A1(j); end
end
% Episodes of every run
for ri = 1:numel(RUN)
    kd = BS(RUN(ri).b).kind;
    for pk = RUN(ri).pols
        R = RES{ri, pk}; v = RV(ri, pk);
        if strcmp(kd, 'clean'), m = true(size(R.scn)); else, m = R.threat; end
        i = IDX(sub2ind(size(IDX), R.scn(m), R.s(m), R.split(m), R.r(m)));
        acc = @(x) accumarray(i(:), double(x(:)), [nF 1]);
        if strcmp(kd, 'clean')
            FT.fa_k(:, v) = FT.fa_k(:, v) + acc(R.switches(m) > 0);
            FT.fa_n(:, v) = FT.fa_n(:, v) + acc(true(1, sum(m)));
            FT.sw_k(:, v) = FT.sw_k(:, v) + acc(R.switches(m));
        else
            FT.ep_n(:, v) = FT.ep_n(:, v) + acc(true(1, sum(m)));
            FT.held_k(:, v) = FT.held_k(:, v) + acc(R.held(m));
            FT.rec_k(:, v) = FT.rec_k(:, v) + acc(R.recovered(m));
            FT.lt_k(:, v) = FT.lt_k(:, v) + acc(R.lost_rec(m));
            FT.lt_n(:, v) = FT.lt_n(:, v) + acc(R.n_rec(m));
        end
    end
end
clear RES
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
% LINK: packet loss of the clean link at no_action; every flight also carries the clean
% link of its own geometry (the LINK_T reference)
for sp = [SPL SPEED]
    for s = 1:nS
        P = PP.pools{clean_cell, s, K.na, sp};
        if isempty(P) || isempty(P.ber), continue; end
        i = flight_of(IDX, clean_cell, s, sp, P.run, PP.runs{sp});
        FT.link_k = FT.link_k + accumarray(i, double(P.fer), [nF 1]);
        FT.link_n = FT.link_n + accumarray(i, 1, [nF 1]);
    end
end
ic = IDX(sub2ind(size(IDX), clean_cell + 0 * FT.s, FT.s, FT.sp, FT.r)); m = ic > 0;
FT.cl_k(m) = FT.link_k(ic(m)); FT.cl_n(m) = FT.link_n(ic(m));
% The clean-link flights of data/clean_test_pools.mat (split id 6): draws from their seeds
CF = take_rows(FT, FT.c == clean_cell & ismember(FT.sp, SPL));
if ~isempty(CT)
    [s_, r_] = ndgrid(1:nS, 1:CT.n_geom); s_ = s_(:); r_ = r_(:); n = numel(s_);
    blk = floor((CT.runs(1) - 1) / 100);               % seed block of the clean-link flights (pool_seed.m)
    CW = blank_rows(FT, n);
    CW.c(:) = clean_cell; CW.sp(:) = 6; CW.s = s_; CW.r = r_; CW.geo = 6e6 + 1000 * s_ + r_; CW.eb = reshape(PP.ebno(s_), [], 1);
    CW.speed = CT.speed(sub2ind(size(CT.speed), s_, r_)); CW.align(:) = NaN;
    for q = 1:n
        d = flight_draws(pool_seed(1, s_(q), blk, r_(q)), CW.speed(q) / 3.6 * p0.carrier_freq / p0.c_light, p0, ...
            struct('ebno', PP.ebno(s_(q))));
        dv = struct('alt', d.alt_m, 'ksig', d.k_sig, 'rho', d.rho, 'bank', field_or_nan(d, 'bank'), ...
            'ds', field_or_nan(d, 'ds_ns'));
        for f = fieldnames(dv)', CW.(f{1})(q) = dv.(f{1})(1); end
    end
    for d = 1:nD
        for pk = find(~cellfun(@isempty, RW(d, :)))
            v = var_of(VAR, 'clean', NaN, DLY(d), pk);
            i = sub2ind([nS CT.n_geom], RW{d, pk}.s, RW{d, pk}.r);
            CW.fa_k(:, v) = accumarray(i(:), double(RW{d, pk}.switches(:) > 0), [n 1]);
            CW.fa_n(:, v) = accumarray(i(:), 1, [n 1]);
            CW.sw_k(:, v) = accumarray(i(:), double(RW{d, pk}.switches(:)), [n 1]);
        end
    end
    for s = 1:nS
        P = CT.pools{1, s, K.na};
        [~, r] = ismember(P.run, CT.runs);
        i = sub2ind([nS CT.n_geom], s + 0 * r, r);
        CW.link_k = CW.link_k + accumarray(i, double(P.fer), [n 1]);
        CW.link_n = CW.link_n + accumarray(i, 1, [n 1]);
    end
    CW.cl_k = CW.link_k; CW.cl_n = CW.link_n;
    CF = cat_rows(CF, CW);
end
CS = take_rows(FT, FT.c == clean_cell & FT.sp == SPEED);   % clean link at the edge speeds
FTi = arrayfun(@(c) take_rows(FT, FT.c == c & ismember(FT.sp, SPL)), tc, 'UniformOutput', false);
FTe = arrayfun(@(c) take_rows(FT, FT.c == c & FT.sp == SPEED), tc, 'UniformOutput', false);
fprintf('Flights: %d of the threat cells, %d of the clean link (%.1f min)\n', sum(FT.c ~= clean_cell), ...
    numel(CF.s) + numel(CS.s), toc(t0) / 60);

%% 4. Verdicts per point
% Bands of the commitment's veto and of the band tables; a covariate the pools do not
% record has no band
ev = linspace(PP.speed_range(1), PP.speed_range(2), 7);
ea = linspace(p0.alt_range_m(1), p0.alt_range_m(2), 4);
ek = p0.k_range_db(1):5:p0.k_range_db(2);
er = linspace(p0.corr_range(1), p0.corr_range(2), 4);
band = @(name, ax, lo, hi, top, veto) struct('name', name, 'axis', ax, 'lo', lo, 'hi', hi, 'top', top, 'veto', veto);
BD = struct('name', {}, 'axis', {}, 'lo', {}, 'hi', {}, 'top', {}, 'veto', {});
for b = 1:6, BD(end+1) = band(sprintf('%.0f-%.0f km/h', ev(b), ev(b+1)), 'speed', ev(b), ev(b+1), b == 6, true); end %#ok<SAGROW>
for b = 1:2
    BD(end+1) = band(sprintf('%g km/h', PP.speed_out(b, 1)), 'edge', PP.speed_out(b, 1), PP.speed_out(b, 2), true, false); %#ok<SAGROW>
end
for b = 1:3, BD(end+1) = band(sprintf('%.0f-%.0f m', ea(b), ea(b+1)), 'alt', ea(b), ea(b+1), b == 3, true); end %#ok<SAGROW>
for b = 1:5, BD(end+1) = band(sprintf('K %g..%g dB', ek(b), ek(b+1)), 'k', ek(b), ek(b+1), b == 5, true); end %#ok<SAGROW>
BD(end+1) = band(sprintf('K %g..%g dB', K_READ, ek(2)), 'k', K_READ, ek(2), false, false);   % the lowest band from K_READ
EAL = [0 0.5 0.9 1];
for b = 1:3, BD(end+1) = band(sprintf('align %g-%g', EAL(b), EAL(b+1)), 'align', EAL(b), EAL(b+1), b == 3, true); end %#ok<SAGROW>
for b = 1:3, BD(end+1) = band(sprintf('rho %.1f-%.1f', er(b), er(b+1)), 'rho', er(b), er(b+1), b == 3, true); end %#ok<SAGROW>
EBK = [0 20 40 58];                                   % [deg] bank: the largest measured on a small UAV is 57.9 (Gross et al.)
EDS = [0 100 200 300 1000];                           % [ns] RMS delay spread: medians 64-302 ns, clipped at 1 us
skipped = {};
if has_cov(4)
    for b = 1:3, BD(end+1) = band(sprintf('bank %g-%g deg', EBK(b), EBK(b+1)), 'bank', EBK(b), EBK(b+1), b == 3, true); end %#ok<SAGROW>
else
    skipped{end+1} = 'bank (PP.cov has no per-flight bank)';
end
if has_cov(5)
    for b = 1:4, BD(end+1) = band(sprintf('DS %g-%g ns', EDS(b), EDS(b+1)), 'ds', EDS(b), EDS(b+1), b == 4, true); end %#ok<SAGROW>
else
    skipped{end+1} = 'delay spread (PP.cov has no per-flight ds_ns)';
end
nB = numel(BD); iv = find([BD.veto]);

% Policy-independent layers of every point
BL = struct('det', repmat(VZ, nT, nS), 'deth', repmat(VZ, nT, nS), 'surv', repmat(VZ, nT, nS), ...
    'surv_f', repmat(VZ, nT, nS), 'surv_c', repmat(VZ, nT, nS));
for i = 1:nT
    for s = 1:nS
        F = take_rows(FTi{i}, FTi{i}.s == s);
        [BL.det(i, s), BL.deth(i, s)] = det_layers(F, TGT, B);
        BL.surv(i, s) = surv_layer(F, 'surv', TGT, B);
        if ismember(i, ifo), BL.surv_f(i, s) = surv_layer(F, 'surv_f', TGT, B); end
        if ismember(i, ij), BL.surv_c(i, s) = surv_layer(F, 'surv_c', TGT, B); end
    end
end
% The clean link per Eb/N0: FA at every signalling delay, LINK; FA of the claim of every
% point (fac: the clean flights from the KPI 1 threshold up, from the point up below it);
% the clean link in every veto band over the regions of the walks (the point s and the
% points above it, key s; the point alone, key nS + s)
CL = struct('link', repmat(VZ, 1, nS), 'fa', repmat(VZ, nD, nS), 'fac', repmat(VZ, nD, nS));
CVt = ones(nD, 2 * nS, nB);
for s = 1:nS
    F = take_rows(CF, CF.s == s);
    CL.link(s) = edge_verdict(F.link_k, F.link_n, F.geo, TGT.link, 'le', false, B);
    for d = 1:nD
        v = var_of(VAR, 'clean', NaN, DLY(d), 1);
        CL.fa(d, s) = edge_verdict(F.fa_k(:, v), F.fa_n(:, v), F.geo, TGT.fa, 'le', true, B);
    end
end
e0 = min(PP.ebno, ebno_thr);
for d = 1:nD
    v = var_of(VAR, 'clean', NaN, DLY(d), 1);
    for e = unique(e0)
        CL.fac(d, e0 == e) = fa_claim(CF, v, e, ebno_thr, TGT, B);
    end
end
FAP = vt(CL.fac); FAP(vt(CL.fa) == -1) = -1;         % FA as the commitment reads it
for d = 1:nD
    v = var_of(VAR, 'clean', NaN, DLY(d), 1);
    for key = 1:2 * nS
        F = take_rows(CF, ismember(CF.s, region(key, nS)));
        for b = iv
            if strcmp(BD(b).axis, 'align'), continue; end     % no interferer on the clean link
            Fb = take_rows(F, in_band(F, BD(b)));
            if isempty(Fb.geo), continue; end
            fa = edge_verdict(Fb.fa_k(:, v), Fb.fa_n(:, v), Fb.geo, TGT.fa, 'le', true, B);
            lk = edge_verdict(Fb.link_k, Fb.link_n, Fb.geo, TGT.link, 'le', false, B);
            if fa.verdict == -1 || lk.verdict == -1, CVt(d, key, b) = -1; end
        end
    end
end
fprintf('Clean link and policy-independent layers done (%.1f min)\n', toc(t0) / 60);

% The commitment of every row kind at every signalling delay: static (every threat row),
% follower (each re-acquisition delay) and comb (first delay only)
KND = {'static', NaN, 1:nT, 'surv'};
for f = FDL, KND(end+1, :) = {'follow', f, ifo, 'surv_f'}; end %#ok<SAGROW>
KND(end+1, :) = {'comb', 0, ij, 'surv_c'};
CR = struct('kind', {}, 'fd', {}, 'D', {}, 'd', {}, 'rows', {}, 'X', {});
DH = containers.Map();                                % DET_h of every veto band, per row and region
for d = 1:nD
    for k = 1:size(KND, 1)
        v = var_of(VAR, KND{k, 1}, KND{k, 2}, DLY(d), 1);
        if v == 0 || isempty(KND{k, 3}), continue; end
        vr = var_of(VAR, KND{k, 1}, KND{k, 2}, DLY(1), iRnd);
        X = commit_rows(FTi, KND{k, 3}, v, vr, KND{k, 4}, BL, CL.fac(d, :), CL.fa(d, :), CL.link, FAV, TGT, B, ...
            BD(iv), dirc, reshape(CVt(d, :, iv), 2 * nS, []), DH, nS);
        CR(end+1) = struct('kind', KND{k, 1}, 'fd', KND{k, 2}, 'D', DLY(d), 'd', d, 'rows', KND{k, 3}, 'X', X); %#ok<SAGROW>
    end
end
c1 = find(strcmp({CR.kind}, 'static') & [CR.d] == 1, 1); X1 = CR(c1).X;   % the deployed delay
cst = find(strcmp({CR.kind}, 'static'));              % static commitment at every delay
% The relative layers at the deployed delay, every policy's REC beside them
PT = struct('det', BL.det, 'deth', BL.deth, 'surv', BL.surv, 'rec', X1.rec, 'prot', X1.prot, 'linkt', X1.linkt, ...
    'sys', zeros(nT, nS), 'lim', {repmat({''}, nT, nS)}, 'sysl', zeros(nT, nS), 'rec_pol', nan(nT, nS, nP), ...
    'rec4_pol', nan(nT, nS, nP));
for i = 1:nT
    for s = 1:nS
        [PT.sys(i, s), PT.lim{i, s}] = all_of([BL.det(i, s).verdict, BL.surv(i, s).verdict, X1.rec(i, s).verdict, FAV], 'DSRF');
        PT.sysl(i, s) = all_of([PT.sys(i, s), CL.link(s).verdict], 'SL');
        F = take_rows(FTi{i}, FTi{i}.s == s & FTi{i}.surv);
        for pk = 1:nP
            v = var_of(VAR, 'static', NaN, DLY(1), pk);
            PT.rec_pol(i, s, pk) = sum(F.held_k(:, v)) / sum(F.ep_n(:, v));
            PT.rec4_pol(i, s, pk) = sum(F.rec_k(:, v)) / sum(F.ep_n(:, v));
        end
    end
end
% The floor without signalling: the receiver alone (PROT, LINK and LINK_T)
FL = struct('prot', repmat(VZ, nT, nS), 'linkt', repmat(VZ, nT, nS), 'v', zeros(nT, nS), 'lim', {repmat({''}, nT, nS)});
vm = var_of(VAR, 'static', NaN, DLY(1), iMm);
for i = 1:nT
    for s = 1:nS
        P = pol_layers(take_rows(FTi{i}, FTi{i}.s == s), vm, 'surv', TGT, B);
        FL.prot(i, s) = P.prot; FL.linkt(i, s) = P.linkt;
        [FL.v(i, s), FL.lim{i, s}] = all_of([P.prot.verdict, CL.link(s).verdict, P.linkt.verdict], 'PLT');
    end
end
% The unknown path (evidence only): REC and PROT of the single threats
UK = struct('rec', repmat(VZ, nT, nS), 'prot', repmat(VZ, nT, nS));
vu = var_of(VAR, 'unknown', NaN, DLY(1), 1);
if vu > 0
    for i = find(ismember(tc, single_cells))
        for s = 1:nS
            P = pol_layers(take_rows(FTi{i}, FTi{i}.s == s), vu, 'surv', TGT, B);
            UK.rec(i, s) = P.rec; UK.prot(i, s) = P.prot;
        end
    end
end
VD = struct('det', vt(PT.det), 'deth', vt(PT.deth), 'surv', vt(PT.surv), 'rec', vt(PT.rec), 'prot', vt(PT.prot), ...
    'linkt', vt(PT.linkt), 'sys', PT.sys, 'sysl', PT.sysl);
FR = arrayfun(@(s) false_change_rate(CF.sw_k(CF.s == s, var_of(VAR, 'clean', NaN, DLY(1), 1)), T, CF.geo(CF.s == s), ...
    C.period_ms), 1:nS);
FRall = false_change_rate(CF.sw_k(CF.eb >= ebno_thr, var_of(VAR, 'clean', NaN, DLY(1), 1)), T, CF.geo(CF.eb >= ebno_thr), ...
    C.period_ms);
fprintf('Verdicts per point done (%.1f min)\n', toc(t0) / 60);

%% 4b. Off-grid check points (data/check_pools.mat), the deployed policy at every delay
% (the same onsets and frame draws at every delay); FA of the claim from the grid's clean
% flights, the check point's own 36 only must not be NOT COMMITTED
CKV = struct('c', {}, 'threat', {}, 'kind', {}, 'level', {}, 's', {}, 'ebno', {}, 'det', {}, 'deth', {}, 'surv', {}, ...
    'rec', {}, 'prot', {}, 'linkt', {}, 'sys', {}, 'lim', {}, 'commit', {}, 'clim', {});
CK = [];
if isfile('data/check_pools.mat')
    L = load('data/check_pools.mat', 'CK'); CK = L.CK; clear L
    if ~strcmp(CK.det_id, PP.det_id), error('edge_map: the check pools come from another detector; rerun C1c'); end
    CK.confirm = PP.confirm; CK.alarm_mode = PP.alarm_mode; if isfield(PP, 'drop_db'), CK.drop_db = PP.drop_db; end
    Kc = link_env('tables', CK, 'flight');
    ck = find(~strcmp(CK.scen, 'none')); k0 = find(strcmp(CK.scen, 'none'), 1); nK = numel(CK.ebno);
    [kind, ag, opt] = policy_setup(dep, Q, sel, [], fixed_mmse, [], Kc.na);
    specs = {};
    [u, ~, j] = unique(cellfun(@mat2str, CK.cell_ebs(ck), 'UniformOutput', false), 'stable');
    for g = 1:numel(u)
        cg = ck(j == g); ss = CK.cell_ebs{cg(1)}; rr = CK.cell_geo{cg(1)}{1};
        specs = [specs, policy_episodes(cg, nK, rr, REPS, false, false, NE, T, rs, [], ss)]; %#ok<AGROW>
    end
    spc = policy_episodes(k0, nK, CK.cell_geo{k0}{1}, 1, false, false, NE, T, rs, [], CK.cell_ebs{k0});
    [kc, ks, kr] = deal(zeros(0, 1));
    for c = [ck k0]
        [s_, r_] = ndgrid(CK.cell_ebs{c}, CK.cell_geo{c}{1});
        kc = [kc; c + 0 * s_(:)]; ks = [ks; s_(:)]; kr = [kr; r_(:)]; %#ok<AGROW>
    end
    nKF = numel(kc);
    KI = zeros(numel(CK.scen), nK, max(Kc.nR)); KI(sub2ind(size(KI), kc, ks, kr)) = 1:nKF;
    okc = Kc.restored & Kc.restored_plr; ik = sub2ind(size(Kc.recoverable), kc, ks, 1 + 0 * kc, kr);
    hmc = ~reshape(okc(:, :, Kc.na, :, :), size(Kc.recoverable));
    Z = zeros(nKF, nD);
    KF = struct('c', kc, 's', ks, 'r', kr, 'geo', 7e6 + 1000 * ks + kr, 'surv', Kc.recoverable(ik), 'harm', hmc(ik), ...
        'det_k', zeros(nKF, 1), 'det_n', zeros(nKF, 1), 'link_k', zeros(nKF, 1), 'link_n', zeros(nKF, 1), ...
        'cl_k', nan(nKF, 1), 'cl_n', nan(nKF, 1), 'ep_n', Z, 'held_k', Z, 'rec_k', Z, 'lt_k', Z, 'lt_n', Z, 'fa_k', Z, 'fa_n', Z);
    for d = 1:nD
        for k = 1:numel(specs), specs{k}.delay = DLY(d); end %#ok<SAGROW>
        for k = 1:numel(spc), spc{k}.delay = DLY(d); end
        Rk = policy_run_set(kind, CK, Kc, specs, 1, ag, opt, 90000);
        m = Rk.threat; i = KI(sub2ind(size(KI), Rk.scn(m), Rk.s(m), Rk.r(m)));
        acc = @(x) accumarray(i(:), double(x(:)), [nKF 1]);
        KF.ep_n(:, d) = acc(true(1, sum(m))); KF.held_k(:, d) = acc(Rk.held(m)); KF.rec_k(:, d) = acc(Rk.recovered(m));
        KF.lt_k(:, d) = acc(Rk.lost_rec(m)); KF.lt_n(:, d) = acc(Rk.n_rec(m));
        Rc = policy_run_set(kind, CK, Kc, spc, 1, ag, opt, 95000);
        i = KI(sub2ind(size(KI), Rc.scn, Rc.s, Rc.r));
        KF.fa_k(:, d) = accumarray(i(:), double(Rc.switches(:) > 0), [nKF 1]); KF.fa_n(:, d) = accumarray(i(:), 1, [nKF 1]);
    end
    for c = [ck k0]
        for s = CK.cell_ebs{c}
            P = CK.pools{c, s, Kc.na, 1};
            [~, r] = ismember(P.run, CK.runs{1});
            i = KI(sub2ind(size(KI), c + 0 * r, s + 0 * r, r));
            if c == k0
                KF.link_k = KF.link_k + accumarray(i, double(P.fer), [nKF 1]);
                KF.link_n = KF.link_n + accumarray(i, 1, [nKF 1]);
                continue
            end
            k = fused_class(P.probs, struct('run', P.run, 'pos', run_pos(P.run), 'gain_ant', P.gant, 'feats_raw', P.feat), ...
                CK.fuse, CK.fuse_N);
            on = threat_active(CK.scen{c}, P.act);
            ok_c = ismember(acts, rule_based_policy(CK.scen{c}));
            KF.det_k = KF.det_k + accumarray(i, double(reshape(ok_c(k), [], 1) & on), [nKF 1]);
            KF.det_n = KF.det_n + accumarray(i, double(on), [nKF 1]);
        end
    end
    i0 = KI(sub2ind(size(KI), k0 + 0 * KF.s, KF.s, KF.r)); m = i0 > 0;
    KF.cl_k(m) = KF.link_k(i0(m)); KF.cl_n(m) = KF.link_n(i0(m));
    KFC = zeros(nD, nK); ek = min(CK.ebno, ebno_thr);   % FA of the claim at every check Eb/N0
    for d = 1:nD
        for e = unique(ek)
            V = fa_claim(CF, var_of(VAR, 'clean', NaN, DLY(d), 1), e, ebno_thr, TGT, B); KFC(d, ek == e) = V.verdict;
        end
    end
    for c = ck
        for s = CK.cell_ebs{c}
            F = take_rows(KF, KF.c == c & KF.s == s); Fc = take_rows(KF, KF.c == k0 & KF.s == s);
            [x.det, x.deth] = det_layers(F, TGT, B);
            x.surv = surv_layer(F, 'surv', TGT, B);
            lk = edge_verdict(Fc.link_k, Fc.link_n, Fc.geo, TGT.link, 'le', false, B);
            [x.commit, x.clim] = deal(zeros(1, nD), cell(1, nD));
            for d = 1:nD
                P = pol_layers(F, d, 'surv', TGT, B);
                fa = edge_verdict(Fc.fa_k(:, d), Fc.fa_n(:, d), Fc.geo, TGT.fa, 'le', true, B);
                E = edge_commit(struct('prot', P.prot.verdict, 'deth', x.deth.verdict, 'deth_n', x.deth.n, ...
                    'fa', KFC(d, s), 'fa_pt', fa.verdict, 'link', lk.verdict, 'linkt', P.linkt.verdict, 'fav', FAV), @no_veto);
                x.commit(d) = E.v; x.clim(d) = E.lim;
                if d == 1, x.rec = P.rec; x.prot = P.prot; x.linkt = P.linkt; end
            end
            [x.sys, x.lim] = all_of([x.det.verdict, x.surv.verdict, x.rec.verdict, FAV], 'DSRF');
            CKV(end+1) = struct('c', c, 'threat', CK.scen{c}, 'kind', CK.kind{c}, 'level', CK.level(c), 's', s, ...
                'ebno', CK.ebno(s), 'det', x.det, 'deth', x.deth, 'surv', x.surv, 'rec', x.rec, 'prot', x.prot, ...
                'linkt', x.linkt, 'sys', x.sys, 'lim', x.lim, 'commit', x.commit, 'clim', {x.clim}); %#ok<SAGROW>
        end
    end
    fprintf('Off-grid check points: %d at %d delays (%.1f min)\n', numel(CKV), nD, toc(t0) / 60);
end

%% 5. Bands, over the Eb/N0 from the KPI 1 threshold up (deployed policy, deployed delay)
% A band commits with the claim's FA (every clean flight from the threshold up, KPI 6)
% and its own clean flights' FA not NOT COMMITTED (96 hover flights commit only at 0)
BT = struct('det', repmat(VZ, nT, nB), 'surv', repmat(VZ, nT, nB), 'rec', repmat(VZ, nT, nB), 'prot', repmat(VZ, nT, nB), ...
    'sys', zeros(nT, nB), 'lim', {repmat({''}, nT, nB)}, 'commit', zeros(nT, nB), 'clim', {repmat({''}, nT, nB)});
CB = struct('fa', repmat(VZ, 1, nB), 'link', repmat(VZ, 1, nB));
vc1 = var_of(VAR, 'clean', NaN, DLY(1), 1); v1 = var_of(VAR, 'static', NaN, DLY(1), 1);
for b = 1:nB
    if strcmp(BD(b).axis, 'align'), continue; end         % no interferer on the clean link
    if strcmp(BD(b).axis, 'edge'), F = take_rows(CS, CS.eb >= ebno_thr); else, F = take_rows(CF, CF.eb >= ebno_thr); end
    F = take_rows(F, in_band(F, BD(b)));
    CB.fa(b) = edge_verdict(F.fa_k(:, vc1), F.fa_n(:, vc1), F.geo, TGT.fa, 'le', true, B);
    CB.link(b) = edge_verdict(F.link_k, F.link_n, F.geo, TGT.link, 'le', false, B);
end
for i = 1:nT
    for b = 1:nB
        if strcmp(BD(b).axis, 'align') && ~dirc(i), continue; end
        if strcmp(BD(b).axis, 'edge'), F = FTe{i}; else, F = FTi{i}; end
        F = take_rows(F, F.eb >= ebno_thr & in_band(F, BD(b)));
        [BT.det(i, b), dh] = det_layers(F, TGT, B);
        BT.surv(i, b) = surv_layer(F, 'surv', TGT, B);
        P = pol_layers(F, v1, 'surv', TGT, B);
        BT.rec(i, b) = P.rec; BT.prot(i, b) = P.prot;
        [BT.sys(i, b), BT.lim{i, b}] = all_of([BT.det(i, b).verdict, BT.surv(i, b).verdict, P.rec.verdict, FAV], 'DSRF');
        fa = CB.fa(b).verdict; if strcmp(BD(b).axis, 'align'), fa = 1; end
        lk = CB.link(b).verdict; if strcmp(BD(b).axis, 'align'), lk = 1; end
        E = edge_commit(struct('prot', P.prot.verdict, 'deth', dh.verdict, 'deth_n', dh.n, 'fa', CL.fac(1, nS).verdict, ...
            'fa_pt', fa, 'link', lk, 'linkt', P.linkt.verdict, 'fav', FAV), @no_veto);
        BT.commit(i, b) = E.v; BT.clim(i, b) = E.lim;
    end
end
VB = struct('det', vt(BT.det), 'surv', vt(BT.surv), 'rec', vt(BT.rec), 'prot', vt(BT.prot), 'sys', BT.sys, 'commit', BT.commit);
none_ = reshape([BT.surv.n], nT, nB) == 0;            % a band no flight of the cell falls in
for f = fieldnames(VB)', VB.(f{1})(none_) = NaN; end
fprintf('Bands done (%.1f min)\n', toc(t0) / 60);

%% 6. Edges: fixed-sequence walks, every layer apart
LAY = {'det', 'deth', 'surv', 'rec', 'prot', 'linkt', 'sys', 'sysl'};
LAYN = {'DET', 'DET_h', 'SURV', 'REC', 'PROT', 'LINK_T', 'SYSTEM', 'SYSTEM+LINK'};
down = nS:-1:1;                                       % Eb/N0 from the top down
THR = unique(PP.scen(tc), 'stable'); nTh = numel(THR);
rows_of = cellfun(@(t) sort_by_sev(find(strcmp(PP.scen(tc), t)), PP.sev(tc)), THR, 'UniformOutput', false);
ckv = @(f) [];                                        % verdicts of the check points of a layer
ckl = NaN;                                            % Eb/N0 of the level check points
if ~isempty(CKV)
    ckl = CK.e_level; s0 = find(PP.ebno == ckl, 1);
    kd = {CKV.kind}; th = {CKV.threat}; eb = [CKV.ebno]; mid = CK.sev([CKV.c]);
    ckv = @(f) check_verdicts(CKV, f);
end
% Distance (Eb/N0 from 15 dB down) and severity (from the nominal level down and up) of
% every layer at the deployed delay, and of the commitment at every delay
WK = struct('name', [LAYN, arrayfun(@(D) sprintf('COMMITTED D%d', D), DLY, 'UniformOutput', false), {'floor'}], ...
    'vd', [cellfun(@(f) VD.(f), LAY, 'UniformOutput', false), arrayfun(@(k) CR(k).X.commit, cst, 'UniformOutput', false), ...
    {FL.v}], 'ck', [cellfun(@(f) ckv(f), {'det', 'deth', 'surv', 'rec', 'prot', 'linkt', 'sys', 'sys'}, 'UniformOutput', false), ...
    arrayfun(@(d) ckv(sprintf('commit%d', d)), 1:nD, 'UniformOutput', false), {[]}]);
ED = cell(1, numel(WK)); SV = cell(1, numel(WK));
for w = 1:numel(WK)
    vd = WK(w).vd; vk = WK(w).ck;
    E = struct('edge', nan(nT, 1), 'first_not', nan(nT, 1), 'nonmono', false(nT, 1), 'check_cut', false(nT, 1));
    for i = 1:nT
        W = edge_walk(vd(i, down), PP.ebno(down));
        E.edge(i) = W.edge; E.first_not(i) = W.first_not; E.nonmono(i) = W.nonmono;
        if ~isempty(vk) && PP.sev(tc(i)) == C.nominal && ismember(tc(i), single_cells)
            xe = PP.ebno(down);
            vmk = arrayfun(@(e) check_at(vk, strcmp(kd, 'ebno') & strcmp(th, PP.scen{tc(i)}) & abs(eb - e) < 1e-9), ...
                (xe(1:end-1) + xe(2:end)) / 2);
            [E.edge(i), E.check_cut(i)] = check_point_cut(E.edge(i), xe, vmk);
        end
    end
    E.km = link_distance_km(E.edge, p0); E.km_all = LB.all_pos * E.km;
    ED{w} = E;
    S = struct('lo', nan(nTh, nS), 'hi', nan(nTh, nS), 'nonmono', false(nTh, nS), 'check_cut', false(nTh, nS));
    for t = 1:nTh
        q = rows_of{t}; x = PP.sev(tc(q)); i0 = find(x == C.nominal, 1);
        if isempty(i0), continue; end
        for s = 1:nS
            W = edge_walk(vd(q, s)', x, i0); lo = W.lo; hi = W.hi; S.nonmono(t, s) = W.nonmono;
            if ~isempty(vk) && isequal(s, s0) && ~contains(THR{t}, '+')
                lvm = @(xx) arrayfun(@(a, b) check_at(vk, strcmp(kd, 'level') & strcmp(th, THR{t}) & ...
                    abs(mid - (a + b) / 2) < 1e-9), xx(1:end-1), xx(2:end));
                xu = x(i0:end); xd = x(i0:-1:1);
                [hi, cu] = check_point_cut(hi, xu, lvm(xu)); [lo, cd] = check_point_cut(lo, xd, lvm(xd));
                S.check_cut(t, s) = cu || cd;
            end
            S.lo(t, s) = lo; S.hi(t, s) = hi;
        end
    end
    SV{w} = S;
end
wC = numel(LAYN) + (1:nD); wF = numel(WK);            % walks of the commitment and of the floor
CE = struct();
for f = {'link'}
    W = edge_walk([CL.(f{1})(down).verdict], PP.ebno(down));
    CE.(f{1}) = struct('edge', W.edge, 'first_not', W.first_not, 'nonmono', W.nonmono, 'km', link_distance_km(W.edge, p0));
end
for d = 1:nD                                          % FA as the commitment reads it
    W = edge_walk(FAP(d, down), PP.ebno(down));
    CE.fa(d) = struct('edge', W.edge, 'first_not', W.first_not, 'nonmono', W.nonmono, 'km', link_distance_km(W.edge, p0));
end
% Follower re-acquisition: from 2 cycles down to 0, per follower row, Eb/N0 and delay
FRG = struct('fmin', nan(numel(ifo), nS, nD), 'nonmono', false(numel(ifo), nS, nD));
for d = 1:nD
    kk = arrayfun(@(f) find(strcmp({CR.kind}, 'follow') & [CR.fd] == f & [CR.d] == d, 1), FDL(end:-1:1), 'UniformOutput', false);
    if any(cellfun(@isempty, kk)), continue; end
    vf = cat(3, CR([kk{:}]).X);
    for q = 1:numel(ifo)
        for s = 1:nS
            W = edge_walk(arrayfun(@(X) X.commit(q, s), vf), FDL(end:-1:1));
            FRG.fmin(q, s, d) = W.edge; FRG.nonmono(q, s, d) = W.nonmono;
        end
    end
end
% A COMMITTED point inside a walk region (the distance run of its row, or the severity
% run of its threat at its Eb/N0) is committed; outside every walk, reported only
INR = false(nT, nS, nD);
for d = 1:nD
    w = wC(d);
    for t = 1:nTh
        q = rows_of{t}; x = PP.sev(tc(q));
        for s = 1:nS
            INR(q, s, d) = INR(q, s, d) | reshape(PP.ebno(s) >= ED{w}.edge(q), [], 1);
            INR(q, s, d) = INR(q, s, d) | reshape(x >= SV{w}.lo(t, s) & x <= SV{w}.hi(t, s), [], 1);
        end
    end
end
% Speed and altitude: the run of COMMITTED bands around the nominal one; K: from 15-20 dB down
isp = find(strcmp({BD.axis}, 'speed')); iea = find(strcmp({BD.axis}, 'edge')); ial = find(strcmp({BD.axis}, 'alt'));
ik = find(strcmp({BD.axis}, 'k'));                    % five bands up, then the reading of the lowest from K_READ
i0v = find(ev(1:end-1) <= 3.6 * p0.v_nominal & 3.6 * p0.v_nominal < ev(2:end), 1);   % band of the 72 km/h cruise
RN = struct();
for f = {'det', 'surv', 'rec', 'sys', 'commit'}
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
        W = edge_walk(VB.(f{1})(i, ik(5:-1:1)), ek(5:-1:1)); E.kmin(i) = W.edge; E.k_nonmono(i) = W.nonmono;
        W = edge_walk(VB.(f{1})(i, ik([5 4 3 2 6])), [ek(5:-1:2), K_READ]); E.kmin_read(i) = W.edge;
    end
    RN.(f{1}) = E;
end

%% 7. Overhead pass: the path_loss commitment at the drop of each bound
pl = tc(strcmp(PP.scen(tc), 'path_loss'));
[lvs, o] = sort(PP.level(pl)); ip = arrayfun(@(c) find(tc == c), pl(o));
OV = nan(numel(OHP.alt_m), numel(OHP.ebno)); OLt = OV; OLl = OV;
for j = 1:numel(OHP.ebno)
    s = find(PP.ebno == OHP.ebno(j), 1);
    if isempty(s) || isempty(ip), continue; end
    for h = 1:numel(OHP.alt_m)
        [vtk, OLt(h, j)] = level_verdict(OHP.drop_tracked_db(h, j), lvs, X1.commit(ip, s));
        [vl, OLl(h, j)] = level_verdict(OHP.drop_lost_db(h, j), lvs, X1.commit(ip, s));
        if vl == 1, OV(h, j) = 1; elseif vtk == -1, OV(h, j) = -1; else, OV(h, j) = 0; end
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
% The envelope predicted on validation (evaluate_policies.m) against the commitment: a
% (threat, level) is committed when its distance walk commits a point
AGR = [];
if isfile('results/policy_evaluation.mat')
    L = load('results/policy_evaluation.mat', 'KP');
    if isfield(L.KP, 'envelope')
        AGR = zeros(2, 2);                            % rows: predicted in / out; columns: committed / not
        for i = find(ismember(tc, single_cells))
            ti = find(strcmp(L.KP.threats, PP.scen{tc(i)}), 1);
            if isempty(ti) || PP.sev(tc(i)) > size(L.KP.envelope, 2), continue; end
            a = 2 - L.KP.envelope(ti, PP.sev(tc(i))); b = 2 - ~isnan(ED{wC(1)}.edge(i));
            AGR(a, b) = AGR(a, b) + 1;
        end
    end
end
clear L

%% 9. Report
pct = @(V) cell_txt(V, '%5.1f');
hdr_e = arrayfun(@(e, d) sprintf('%g dB %.2f km', e, d), PP.ebno, km, 'UniformOutput', false);
rowl = cellfun(@(l, b, w) sprintf('%-40s %-8s', [l repmat('*', 1, w)], b), lbl, basis, num2cell(between), 'UniformOutput', false);
rep = {'=== EDGE MAP: A VERDICT AT EVERY POINT OF THE ENVELOPE ==='};
rep{end+1} = sprintf(['Generated: %s | deployed policy %s, false-alarm bound met on validation: %s | flights per ' ...
    '(cell, Eb/N0), moving flights: clean link and single threats %d, combined threats %d; edge speeds per Eb/N0: %s ' ...
    '%d at every level, 161 km/h %d at the nominal level | episodes: %d onsets per flight | signalling delays %s ' ...
    'cycles (%s ms) | follower re-acquisition %s cycles (%s ms)'], ...
    datestr(now), NAMES.(dep), ternary(FAV == 1, 'yes', 'NO (no point commits)'), numel(PP.cell_geo{tc(1)}{TEST}) + ...
    numel(PP.cell_geo{tc(1)}{TEST2}), numel(PP.cell_geo{tc(end)}{TEST}) + numel(PP.cell_geo{tc(end)}{TEST2}), HOVER, ...
    nnz(PP.speed{SPEED}(1, :) == 0), nnz(PP.speed{SPEED}(1, :) > 0), REPS, strjoin(compose('%d', DLY), '/'), ...
    strjoin(compose('%d', DLY * C.period_ms), '/'), strjoin(compose('%d', FDL), '/'), strjoin(compose('%d', FDL * C.period_ms), '/'));
rep{end+1} = sprintf(['Targets: DET, DET_h >= %g%% | SURV >= %g%% | REC, PROT >= %g%% | LINK_T <= max(2x clean, %g%%) | ' ...
    'FA <= %g%% | LINK <= %g%% | COMMITTED: PROT, DET_h, FA, LINK and LINK_T COMMITTED (DET_h only not N below %d ' ...
    'harmed flights; FA of the claim: the clean flights from %g dB up, or from the point up below it, and the ' ...
    'point''s own not N), F, no band N | SYSTEM: DET, SURV and REC COMMITTED and F | SYSTEM+LINK: and LINK'], ...
    100 * [TGT.det TGT.surv TGT.rec TGT.link TGT.fa TGT.link], N_MIN, ebno_thr);
rep{end+1} = ['Restored: BER <= 2x and packet loss <= 2x + one packet of the same flight''s clean link (BER floor 1e-4). ' ...
    'REC and PROT count held recovery: restored for 5 cycles and on every cycle to the end of the 30-cycle episode, but ' ...
    'one follower re-acquisition of 1 + D cycles: held for the rest of a 0.6 s episode (at most 0.54 s after the onset). ' ...
    'DET_h: DET on the flights whose unmitigated link is not restored. LINK_T: packet loss from the start of the ' ...
    'recovery run to the end of the episode.'];
rep{end+1} = sprintf(['Two-sided 95%% intervals (edge_verdict.m: bootstrap over flights, B = %d, Clopper-Pearson for ' ...
    'per-flight outcomes and on the effective sample size of a rate); COMMITTED needs >= %d flights. C COMMITTED, ' ...
    'N NOT COMMITTED, U UNDETERMINED.'], B, N_MIN);
rep{end+1} = sprintf(['Distance, profile A tracked (link_distance_km.m): %s; every position of a flight x%.2f (ground ' ...
    'reflection); the 0.6 F1 clearance (%.1f km at %g m) and the radio horizon never bind below %.2f km.'], ...
    strjoin(hdr_e, ' | '), LB.all_pos, min(LB.fresnel_km), LB.alt_m(1), max(km));
rep{end+1} = ['Level basis: assumed = the spoofer at 30 dB, the open connector and WLAN at 30 dB (no source measured ' ...
    'the level); * = a level the detector never trained on (between its trained levels).'];
ttl = {'DET: fused detection on the threat-active frames at no_action', 'DET_h: DET on the harmed flights', ...
    'SURV: flights some configuration recovers', 'REC: held recovery among recoverable flights, deployed policy', ...
    'PROT: held recovery among all threat flights, deployed policy', ...
    'LINK_T: packet loss after recovery, deployed policy (target max(2x clean, 1.4%))'};
for f = 1:6
    rep{end+1} = ''; %#ok<SAGROW>
    rep{end+1} = sprintf('--- %s, %% [95%% interval] flights verdict ---', ttl{f}); %#ok<SAGROW>
    rep{end+1} = sprintf('%-49s %s', '', sprintf('%-29s', hdr_e{:})); %#ok<SAGROW>
    fmt = '%5.1f'; if f == 6, fmt = '%5.2f'; end
    for i = 1:nT
        rep{end+1} = sprintf('%s %s', rowl{i}, strjoin(arrayfun(@(s) cell_txt(PT.(LAY{f})(i, s), fmt), 1:nS, ...
            'UniformOutput', false), ' ')); %#ok<SAGROW>
    end
end
for f = 7:8
    rep{end+1} = ''; %#ok<SAGROW>
    rep{end+1} = sprintf(['--- %s: verdict (not COMMITTED: D DET, S SURV, R REC, L LINK, F the false-alarm bound ' ...
        'on validation) ---'], LAYN{f}); %#ok<SAGROW>
    rep{end+1} = sprintf('%-49s %s', '', sprintf('%-16s', hdr_e{:})); %#ok<SAGROW>
    for i = 1:nT
        lm = PT.lim(i, :);
        if f == 8, lm = cellfun(@(x, s) [x repmat('L', 1, CL.link(s).verdict ~= 1)], lm, num2cell(1:nS), 'UniformOutput', false); end
        rep{end+1} = sprintf('%s %s', rowl{i}, strjoin(arrayfun(@(s) sprintf('%-15s', sprintf('%s %s', ...
            vsym(VD.(LAY{f})(i, s)), lm{s})), 1:nS, 'UniformOutput', false), ' ')); %#ok<SAGROW>
    end
end
for k = 1:numel(CR)
    x = CR(k).X; rw = CR(k).rows;
    rep{end+1} = ''; %#ok<SAGROW>
    rep{end+1} = sprintf(['--- COMMITTED, %s, signalling delay %d cycles (%d ms): verdict (not COMMITTED: P PROT, H DET_h, ' ...
        'A FA, L LINK, T LINK_T, F the false-alarm bound on validation, B a band NOT COMMITTED); r the random policy''s ' ...
        'PROT COMMITTED too ---'], set_txt(CR(k), C), CR(k).D, CR(k).D * C.period_ms); %#ok<SAGROW>
    rep{end+1} = sprintf('%-49s %s', '', sprintf('%-16s', hdr_e{:})); %#ok<SAGROW>
    for q = 1:numel(rw)
        rep{end+1} = sprintf('%s %s', rowl{rw(q)}, strjoin(arrayfun(@(s) sprintf('%-15s', sprintf('%s %s%s', ...
            vsym(x.commit(q, s)), x.lim{q, s}, repmat(' r', 1, x.rnd(q, s) == 1))), 1:nS, 'UniformOutput', false), ' ')); %#ok<SAGROW>
    end
    bf = find(~cellfun(@isempty, x.bfail));
    for q = reshape(bf, 1, [])
        [a, s] = ind2sub(size(x.bfail), q);
        rep{end+1} = sprintf('  B %s at %s: %s', lbl{rw(a)}, hdr_e{s}, x.bfail{q}); %#ok<SAGROW>
    end
end
rep{end+1} = '';
rep{end+1} = ['--- Without signalling: the receiver alone (always-on MMSE), PROT, LINK and LINK_T (not COMMITTED: P, ' ...
    'L, T) ---'];
rep{end+1} = sprintf('%-49s %s', '', sprintf('%-16s', hdr_e{:}));
for i = 1:nT
    rep{end+1} = sprintf('%s %s', rowl{i}, strjoin(arrayfun(@(s) sprintf('%-15s', sprintf('%s %s', vsym(FL.v(i, s)), ...
        FL.lim{i, s})), 1:nS, 'UniformOutput', false), ' ')); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = sprintf(['--- Follower rows: SURV against a follower (a configuration without channel_switch restores), ' ...
    'REC, PROT of the deployed policy at the deployed delay, %% [95%% interval] flights verdict ---']);
for k = find(strcmp({CR.kind}, 'follow') & [CR.d] == 1)
    for q = 1:numel(CR(k).rows)
        i = CR(k).rows(q);
        rep{end+1} = sprintf('%-49s %s', sprintf('%s, follower %d SURV', lbl{i}, CR(k).fd), strjoin(arrayfun(@(s) ...
            pct(BL.surv_f(i, s)), 1:nS, 'UniformOutput', false), ' ')); %#ok<SAGROW>
        rep{end+1} = sprintf('%-49s %s', sprintf('%s, follower %d REC', lbl{i}, CR(k).fd), strjoin(arrayfun(@(s) ...
            pct(CR(k).X.rec(q, s)), 1:nS, 'UniformOutput', false), ' ')); %#ok<SAGROW>
        rep{end+1} = sprintf('%-49s %s', sprintf('%s, follower %d PROT', lbl{i}, CR(k).fd), strjoin(arrayfun(@(s) ...
            pct(CR(k).X.prot(q, s)), 1:nS, 'UniformOutput', false), ' ')); %#ok<SAGROW>
    end
end
rep{end+1} = '';
rep{end+1} = sprintf(['--- Clean link per Eb/N0 (test and second test flights, and those of data/clean_test_pools.mat): ' ...
    'FA = flights with a change (deployed policy, per signalling delay), FAc the claim''s (the commitment''s: the ' ...
    'clean flights from %g dB up, or from the point up below it), LINK = packet loss at no_action, %% [95%% interval] ' ...
    'flights verdict ---'], ebno_thr);
for d = 1:nD
    rep{end+1} = sprintf('%-8s %s', sprintf('FA D%d', DLY(d)), strjoin(arrayfun(@(s) pct(CL.fa(d, s)), 1:nS, ...
        'UniformOutput', false), ' ')); %#ok<SAGROW>
    rep{end+1} = sprintf('%-8s %s', sprintf('FAc D%d', DLY(d)), strjoin(arrayfun(@(s) pct(CL.fac(d, s)), 1:nS, ...
        'UniformOutput', false), ' ')); %#ok<SAGROW>
end
rep{end+1} = sprintf('%-8s %s', 'LINK', strjoin(arrayfun(@(s) cell_txt(CL.link(s), '%5.2f'), 1:nS, 'UniformOutput', false), ' '));
rep{end+1} = sprintf('False changes of the deployed policy on the clean link (%d ms per cycle, 95%% upper bound):', C.period_ms);
for s = 1:nS
    rep{end+1} = sprintf('  %-16s %s', hdr_e{s}, rate_txt(FR(s))); %#ok<SAGROW>
end
rep{end+1} = sprintf('  %-16s %s', sprintf('>= %g dB', ebno_thr), rate_txt(FRall));
kc_ = find(strcmp({CR.kind}, 'comb'), 1);
if ~isempty(kc_)
    rep{end+1} = '';
    rep{end+1} = ['--- Jammer on every channel we can use (comb; level basis assumed: no source jams every channel): ' ...
        'SURV and PROT when channel switch and frequency diversity escape nothing, COMMITTED ---'];
    rep{end+1} = sprintf('%-49s %s', '', sprintf('%-29s', hdr_e{:}));
    for q = 1:numel(CR(kc_).rows)
        i = CR(kc_).rows(q);
        rep{end+1} = sprintf('%-49s %s', [lbl{i} ' SURV'], strjoin(arrayfun(@(s) pct(BL.surv_c(i, s)), 1:nS, ...
            'UniformOutput', false), ' ')); %#ok<SAGROW>
        rep{end+1} = sprintf('%-49s %s', [lbl{i} ' PROT'], strjoin(arrayfun(@(s) pct(CR(kc_).X.prot(q, s)), 1:nS, ...
            'UniformOutput', false), ' ')); %#ok<SAGROW>
        rep{end+1} = sprintf('%-49s %s', [lbl{i} ' COMMITTED'], strjoin(arrayfun(@(s) sprintf('%-28s', sprintf('%s %s', ...
            vsym(CR(kc_).X.commit(q, s)), CR(kc_).X.lim{q, s})), 1:nS, 'UniformOutput', false), ' ')); %#ok<SAGROW>
    end
end
if vu > 0
    rep{end+1} = '';
    rep{end+1} = sprintf(['--- Unknown path, evidence only (no rate is committed for an emitter outside the detector''s ' ...
        'classes): the detector output withheld after the onset, %s; REC and PROT %% [95%% interval] flights ---'], ...
        ternary(strcmp(dep, 'dqn_esc'), 'the leave-one-out agent of each threat', NAMES.(dep)));
    for i = find(ismember(tc, single_cells))
        rep{end+1} = sprintf('%-49s %s', [lbl{i} ' REC'], strjoin(arrayfun(@(s) evid_txt(UK.rec(i, s)), 1:nS, ...
            'UniformOutput', false), ' ')); %#ok<SAGROW>
        rep{end+1} = sprintf('%-49s %s', [lbl{i} ' PROT'], strjoin(arrayfun(@(s) evid_txt(UK.prot(i, s)), 1:nS, ...
            'UniformOutput', false), ' ')); %#ok<SAGROW>
    end
end
if ~isempty(CKV)
    rep{end+1} = '';
    rep{end+1} = sprintf(['--- Off-grid check points (data/check_pools.mat, %d flights each): Eb/N0 between the grid points ' ...
        'at the nominal level, levels between the trained ones at %g dB; DET_h, PROT, LINK_T %% [95%% interval] flights ' ...
        'verdict, COMMITTED per signalling delay (FA of the claim from the grid''s clean flights; the point''s own only ' ...
        'must not be NOT COMMITTED) ---'], numel(CK.runs{1}), CK.e_level);
    for q = 1:numel(CKV)
        x = CKV(q);
        rep{end+1} = sprintf('%-22s %7g dB at %4g dB (%.2f km) | %s | %s | %s | %s', x.threat, x.level, x.ebno, ...
            link_distance_km(x.ebno, p0), cell_txt(x.deth, '%5.1f'), cell_txt(x.prot, '%5.1f'), cell_txt(x.linkt, '%5.2f'), ...
            strjoin(arrayfun(@(d) sprintf('D%d %s %s', DLY(d), vsym(x.commit(d)), x.clim{d}), 1:nD, 'UniformOutput', false), ...
            ' | ')); %#ok<SAGROW>
    end
end
rep{end+1} = '';
rep{end+1} = sprintf(['--- Bands of every (threat, level), Eb/N0 >= %g dB, deployed policy at the deployed delay (edge ' ...
    'speeds: the edge-speed split, %s at every level, 161 km/h at the nominal level; COMMITTED with the claim''s FA ' ...
    'and the band''s own not NOT COMMITTED): %% flights verdict ---'], ebno_thr, HOVER);
if ~isempty(skipped), rep{end+1} = ['Bands skipped: ' strjoin(skipped, '; ')]; end
grp = arrayfun(@(a) find(strcmp({BD.axis}, a{1})), unique({BD.axis}, 'stable'), 'UniformOutput', false);
LB_ = {'det', 'surv', 'rec', 'prot'}; LBN = {'DET', 'SURV', 'REC', 'PROT', 'SYSTEM', 'COMMITTED'};
for f = 1:6
    for g = 1:numel(grp)
        ib = grp{g};
        rep{end+1} = sprintf('%s | %-49s %s', LBN{f}, '', sprintf('%-13s', BD(ib).name)); %#ok<SAGROW>
        for i = 1:nT
            if f <= 4
                x = arrayfun(@(b) band_txt(BT.(LB_{f})(i, b)), ib, 'UniformOutput', false);
            elseif f == 5
                x = arrayfun(@(b) sprintf('%-12s', [vsym_nan(VB.sys(i, b)) ' ' BT.lim{i, b}]), ib, 'UniformOutput', false);
            else
                x = arrayfun(@(b) sprintf('%-12s', [vsym_nan(VB.commit(i, b)) ' ' BT.clim{i, b}]), ib, 'UniformOutput', false);
            end
            rep{end+1} = sprintf('%s | %s %s', LBN{f}, rowl{i}, strjoin(x, ' ')); %#ok<SAGROW>
        end
    end
end
for f = {'fa', 'link'}
    rep{end+1} = sprintf('clean link %s: %s', upper(f{1}), strjoin(arrayfun(@(b) sprintf('%s %s', BD(b).name, ...
        band_txt(CB.(f{1})(b))), 1:nB, 'UniformOutput', false), ' | ')); %#ok<SAGROW>
end
fid = fopen('results/edge_map.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);

% Summary
sm = {'=== EDGE SUMMARY: WHERE THE SYSTEM IS COMMITTED ===', rep{2:7}, ''};
isg = ismember(tc, single_cells);
cnt3 = @(x, m) sprintf('%4d / %4d / %4d', sum(x(m, :) == 1, 'all'), sum(x(m, :) == -1, 'all'), sum(x(m, :) == 0, 'all'));
sm{end+1} = 'Points per layer, single threats | combined threats: COMMITTED / NOT COMMITTED / UNDETERMINED:';
for f = 1:numel(LAY)
    sm{end+1} = sprintf('  %-16s %s | %s', LAYN{f}, cnt3(VD.(LAY{f}), isg), cnt3(VD.(LAY{f}), ~isg)); %#ok<SAGROW>
end
for d = 1:nD
    x = CR(cst(d)).X;
    sm{end+1} = sprintf(['  %-16s %s | %s; inside a walk region %d, outside every walk (reported, not committed) %d; ' ...
        'not attributable to the decision layer (r) %d'], sprintf('COMMITTED D%d', DLY(d)), cnt3(x.commit, isg), ...
        cnt3(x.commit, ~isg), nnz(x.commit == 1 & INR(:, :, d)), nnz(x.commit == 1 & ~INR(:, :, d)), ...
        nnz(x.commit == 1 & x.rnd == 1)); %#ok<SAGROW>
end
sm{end+1} = sprintf('  %-16s %s | %s', 'floor (no signal)', cnt3(FL.v, isg), cnt3(FL.v, ~isg));
for k = find(~strcmp({CR.kind}, 'static'))
    sm{end+1} = sprintf('  %-16s %s', sprintf('%s D%d', set_txt(CR(k), C), CR(k).D), ...
        cnt3(CR(k).X.commit, true(numel(CR(k).rows), 1))); %#ok<SAGROW>
end
sm{end+1} = sprintf(['Each COMMITTED point holds per point (one-sided error <= 2.5%%, <= 2.1%% at a true 0.90 and 72 ' ...
    'flights); the map as a whole is not jointly controlled (common random numbers group the errors by Eb/N0 column). ' ...
    'The commitment is the walk regions, each "up to" claim at <= 5%% family error.']);
sm{end+1} = sprintf('Clean link per Eb/N0 (%s): LINK %s', strjoin(compose('%g', PP.ebno), '/'), ...
    strjoin(arrayfun(@(V) sprintf('%s(%d)', vsym(V.verdict), V.n), CL.link, 'UniformOutput', false), ' '));
for d = 1:nD
    sm{end+1} = sprintf('  FA D%d per point %s; of the claim %s; committed from 15 dB down to %s', DLY(d), ...
        strjoin(arrayfun(@(V) sprintf('%s(%d)', vsym(V.verdict), V.n), CL.fa(d, :), 'UniformOutput', false), ' '), ...
        strjoin(arrayfun(@(V) sprintf('%s(%d)', vsym(V.verdict), V.n), CL.fac(d, :), 'UniformOutput', false), ' '), ...
        edge_txt(CE.fa(d).edge, CE.fa(d).km)); %#ok<SAGROW>
end
sm{end+1} = sprintf('  LINK committed from 15 dB down to %s', edge_txt(CE.link.edge, CE.link.km));
sm{end+1} = sprintf('  False changes of the deployed policy on the clean link, Eb/N0 >= %g dB: %s', ebno_thr, rate_txt(FRall));
sm{end+1} = sprintf('  Off-grid check points COMMITTED / NOT COMMITTED / UNDETERMINED per delay: %s', strjoin(arrayfun(@(d) ...
    sprintf('D%d %d / %d / %d', DLY(d), nnz(arrayfun(@(x) x.commit(d), CKV) == 1), nnz(arrayfun(@(x) x.commit(d), CKV) == -1), ...
    nnz(arrayfun(@(x) x.commit(d), CKV) == 0)), 1:nD, 'UniformOutput', false), ' | '));
if ~isempty(AGR)
    sm{end+1} = sprintf(['  Envelope predicted on validation (evaluate_policies.m) against the commitment (D%d), single ' ...
        '(threat, level): predicted and committed %d, predicted not committed %d, not predicted committed %d, neither %d'], ...
        DLY(1), AGR(1, 1), AGR(1, 2), AGR(2, 1), AGR(2, 2));
end
sm{end+1} = '';
sm{end+1} = ['--- Distance: Eb/N0 from 15 dB down to the last COMMITTED point, its km (every position of a flight); ' ...
    'first NOT COMMITTED; ! COMMITTED beyond NOT COMMITTED; x stopped by a check point NOT COMMITTED; check points lie ' ...
    'at the nominal level only, every other edge holds at its grid points ---'];
for i = 1:nT
    x = arrayfun(@(w) sprintf('%s %s%s%s', WK(w).name, edge_txt(ED{w}.edge(i), ED{w}.km(i)), repmat(' x', 1, ED{w}.check_cut(i)), ...
        repmat(' !', 1, ED{w}.nonmono(i))), [wC wF 7 1:6], 'UniformOutput', false);
    sm{end+1} = sprintf('%s all positions %s; first N %s | %s', rowl{i}, num_txt(ED{wC(1)}.km_all(i), '%.2f km'), ...
        num_txt(ED{wC(1)}.first_not(i), '%g dB'), strjoin(x, ' | ')); %#ok<SAGROW>
end
sm{end+1} = '';
for w = [wC 7 2 5]
    sm{end+1} = sprintf(['--- Severity, %s: per threat and Eb/N0 the COMMITTED run of levels from the nominal one down ' ...
        'and up (check points at %s dB only; at the other Eb/N0 the run holds at its grid levels) ---'], WK(w).name, ...
        num_txt(ckl, '%g')); %#ok<SAGROW>
    sm{end+1} = sprintf('%-40s %s', '', sprintf('%-22s', hdr_e{:})); %#ok<SAGROW>
    for t = 1:nTh
        x = arrayfun(@(s) [sev_txt(SV{w}.lo(t, s), SV{w}.hi(t, s), SV{w}.nonmono(t, s), THR{t}, C, PP), ...
            repmat(' x', 1, SV{w}.check_cut(t, s))], 1:nS, 'UniformOutput', false);
        sm{end+1} = sprintf('%-40s %s', THR{t}, sprintf('%-22s', x{:})); %#ok<SAGROW>
    end
end
sm{end+1} = '';
sm{end+1} = sprintf(['--- Follower: the fastest re-acquisition of the COMMITTED run from %d cycles down to %d (cycles, ' ...
    'ms at %d ms per cycle), per signalling delay; none: not COMMITTED at %d cycles ---'], FDL(end), FDL(1), C.period_ms, FDL(end));
for q = 1:numel(ifo)
    x = arrayfun(@(d) sprintf('D%d %s', DLY(d), strjoin(arrayfun(@(s) fol_txt(FRG.fmin(q, s, d), FRG.nonmono(q, s, d), ...
        C.period_ms), 1:nS, 'UniformOutput', false), ' ')), 1:nD, 'UniformOutput', false);
    sm{end+1} = sprintf('%-40s %s', lbl{ifo(q)}, strjoin(x, ' | ')); %#ok<SAGROW>
end
sm{end+1} = '';
sm{end+1} = sprintf(['--- Speed, altitude, K over Eb/N0 >= %g dB: COMMITTED, SYSTEM [DET, SURV, REC]; the COMMITTED run ' ...
    'around %s and %s; %s (every level) and 161 km/h (nominal level); K down from 15-20 dB (and with the lowest band ' ...
    'from %g dB) ---'], ebno_thr, BD(isp(i0v)).name, BD(ial(2)).name, HOVER, K_READ);
for i = 1:nT
    q = [RN.commit, RN.sys, RN.det, RN.surv, RN.rec];
    sm{end+1} = sprintf('%s speed %s | hover %s, 161 km/h %s | altitude %s | K from %s (reading %s)', rowl{i}, ...
        per_layer(arrayfun(@(E) [range_txt(E.v(i, :), 'km/h') repmat(' !', 1, E.v_nonmono(i))], q, 'UniformOutput', false)), ...
        per_layer(arrayfun(@(E) vsym_nan(E.edge_v(i, 1)), q, 'UniformOutput', false)), ...
        per_layer(arrayfun(@(E) vsym_nan(E.edge_v(i, 2)), q, 'UniformOutput', false)), ...
        per_layer(arrayfun(@(E) [range_txt(E.alt(i, :), 'm') repmat(' !', 1, E.alt_nonmono(i))], q, 'UniformOutput', false)), ...
        per_layer(arrayfun(@(E) [num_txt(E.kmin(i), '%g dB') repmat(' !', 1, E.k_nonmono(i))], q, 'UniformOutput', false)), ...
        per_layer(arrayfun(@(E) num_txt(E.kmin_read(i), '%g dB'), q, 'UniformOutput', false))); %#ok<SAGROW>
end
sm{end+1} = '';
sm{end+1} = sprintf(['--- Overhead pass (overhead_pass.m, results/overhead_pass.mat): path_loss COMMITTED (D%d) at the ' ...
    'smallest level >= the drop; C when the tracker-lost bound (+%g dB) is, N when the tracked bound (+%.2f dB) is not; ' ...
    '* the lost bound above %g dB, not measured ---'], DLY(1), OHP.lost_db, OHP.track_db, OHP.pl_top_db);
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
mt = FT.c ~= clean_cell & ismember(FT.sp, SPL) & FT.surv & FT.eb >= ebno_thr;
sm{end+1} = sprintf(['Static threats at Eb/N0 >= %g dB, recoverable flights: recovered (KPI 4) | held, per policy at the ' ...
    'deployed delay: %s'], ebno_thr, strjoin(arrayfun(@(pk) sprintf('%s %.1f%% | %.1f%%', LBL{pk}, 100 * rate_of(FT, mt, ...
    var_of(VAR, 'static', NaN, DLY(1), pk), 'rec_k'), 100 * rate_of(FT, mt, var_of(VAR, 'static', NaN, DLY(1), pk), 'held_k')), ...
    1:nP, 'UniformOutput', false), '; '));
mc = CF.eb >= ebno_thr;
sm{end+1} = sprintf('False alarms of the clean link, every flight at Eb/N0 >= %g dB: %s', ebno_thr, ...
    strjoin(arrayfun(@(pk) sprintf('%s %d/%d', LBL{pk}, sum(CF.fa_k(mc, var_of(VAR, 'clean', NaN, DLY(1), pk)) > 0), ...
    sum(CF.fa_n(mc, var_of(VAR, 'clean', NaN, DLY(1), pk)) > 0)), find(arrayfun(@(pk) var_of(VAR, 'clean', NaN, DLY(1), pk), ...
    1:nP) > 0), 'UniformOutput', false), ' | '));
sm{end+1} = ['Each "up to" edge is a fixed-sequence walk at 5% family error; per-point verdicts hold per point, for ' ...
    'moving flights; an edge that spans an off-grid check point NOT COMMITTED stops before it, and an edge that spans ' ...
    'none (levels at another Eb/N0 than the check points'', distance at another level than the nominal) holds at its ' ...
    'grid points only. Hover is ' HOVER '. The policy is not measured beyond 0-15 dB; no level above the top one is ' ...
    'simulated (every top level is the source cap).'];
fid = fopen('results/edge_summary.txt', 'w'); fprintf(fid, '%s\n', sm{:}); fclose(fid);
fprintf('%s\n', sm{:});

%% 10. Figures
tx = @(V) ternary(V.n > 0, sprintf('%.0f\n%d', 100 * V.value, V.n), '-');
FIG = {'det', 'surv', 'rec', 'prot', 'system', 'commit'};
for f = 1:numel(FIG)
    switch FIG{f}
        case {'det', 'surv', 'rec', 'prot'}
            X = arrayfun(tx, PT.(FIG{f}), 'UniformOutput', false); vd = VD.(FIG{f}); nm = upper(FIG{f});
        case 'system'
            X = cellfun(@(l, V) sprintf('%s\n%d', ternary(isempty(l), 'ok', l), V.n), PT.lim, num2cell(PT.surv), ...
                'UniformOutput', false);
            vd = PT.sys; nm = 'SYSTEM';
        case 'commit'
            X = cellfun(@(l, V, r) sprintf('%s%s\n%d', ternary(isempty(l), 'ok', l), repmat(' r', 1, r == 1), V.n), X1.lim, ...
                num2cell(X1.prot), num2cell(X1.rnd), 'UniformOutput', false);
            vd = X1.commit; nm = sprintf('COMMITTED (D = %d)', DLY(1));
    end
    draw_map(sprintf('results/edge_heatmap_%s.png', FIG{f}), sprintf('%s per (threat, level) and Eb/N0, deployed policy', nm), ...
        vd, X, rows_of, THR, lv_txt, PP.ebno, km);
end
VBc = [VB.commit; [CB.fa.verdict]; [CB.link.verdict]];
fig = figure('Position', [40 40 1300, 120 + 13 * size(VBc, 1)], 'Color', 'w');
image(verdict_rgb(VBc));
set(gca, 'XTick', 1:nB, 'XTickLabel', {BD.name}, 'XTickLabelRotation', 45, 'YTick', 1:size(VBc, 1), ...
    'YTickLabel', [lbl, {'clean link FA', 'clean link LINK'}], 'FontSize', 6, 'TickLabelInterpreter', 'none');
title(sprintf(['COMMITTED per band (Eb/N0 >= %g dB), and the clean link: green COMMITTED, amber UNDETERMINED, red NOT ' ...
    'COMMITTED, white no flight'], ebno_thr), 'FontSize', 8);
saveas(fig, 'results/edge_bands.png'); close(fig);

%% 11. Save
CMS = arrayfun(@(k) struct('kind', CR(k).kind, 'fd', CR(k).fd, 'D', CR(k).D, 'cells', tc(CR(k).rows), ...
    'labels', {lbl(CR(k).rows)}, 'commit', CR(k).X.commit, 'lim', {CR(k).X.lim}, 'rnd', CR(k).X.rnd, ...
    'band_fail', {CR(k).X.bfail}, 'prot', CR(k).X.prot, 'rec', CR(k).X.rec, 'linkt', CR(k).X.linkt, 'linkt_target', CR(k).X.tgt), ...
    1:numel(CR));
EM = struct('ebno', PP.ebno, 'km', km, 'all_pos', LB.all_pos, 'targets', TGT, 'n_min', N_MIN, 'B', B, ...
    'ebno_thr', ebno_thr, 'deployed', NAMES.(dep), 'policies', {LBL}, 'cells', tc, 'labels', {lbl}, 'basis', {basis}, ...
    'between', between, 'delays', DLY, 'follower_delays', FDL, 'pt', PT, 'clean', CL, 'commit', CMS, 'floor', FL, ...
    'unknown', UK, 'bands', {BD}, 'bands_skipped', {skipped}, 'bt', BT, 'cb', CB, 'walks', {{WK.name}}, 'dist', {ED}, ...
    'clean_dist', CE, 'sev', {SV}, 'threats', {THR}, 'follower', FRG, 'inside', INR, 'runs', RN, ...
    'ohp', struct('alt_m', OHP.alt_m, 'ebno', OHP.ebno, 'r0_km', OHP.r0_km, 'verdict', OV, 'level_tracked', OLt, ...
    'level_lost', OLl), 'b4', B4, 'b4s', B4s, 'fa_bound_met', FAV == 1, 'fa_rate', {FR}, 'fa_rate_all', FRall, ...
    'fa_commit', FAP, 'hover_label', HOVER, 'check', {CKV}, 'predicted_vs_committed', AGR, 'det_id', PP.det_id, ...
    'created', datestr(now));
inom = find(ismember(tc, nom));
cnt_of = @(x, m) [sum(x(m, :) == 1, 'all'), sum(x(m, :) == -1, 'all'), sum(x(m, :) == 0, 'all')];
EDGE_NUM = struct('ebno', PP.ebno, 'km', km, 'ebno_thr', ebno_thr, 'deployed', NAMES.(dep), 'n_min', N_MIN, ...
    'targets', TGT, 'layers', {LAYN}, ...
    'counts_single', cell2mat(cellfun(@(f) cnt_of(VD.(f), isg), LAY', 'UniformOutput', false)), ...
    'counts_combined', cell2mat(cellfun(@(f) cnt_of(VD.(f), ~isg), LAY', 'UniformOutput', false)), ...
    'delays', DLY, 'commit_single', cell2mat(arrayfun(@(k) cnt_of(CR(k).X.commit, isg), cst', 'UniformOutput', false)), ...
    'commit_combined', cell2mat(arrayfun(@(k) cnt_of(CR(k).X.commit, ~isg), cst', 'UniformOutput', false)), ...
    'commit_inside', arrayfun(@(d) nnz(CR(cst(d)).X.commit == 1 & INR(:, :, d)), 1:nD), ...
    'commit_not_attributable', arrayfun(@(d) nnz(CR(cst(d)).X.commit == 1 & CR(cst(d)).X.rnd == 1), 1:nD), ...
    'floor_single', cnt_of(FL.v, isg), 'floor_combined', cnt_of(FL.v, ~isg), ...
    'cells', {lbl}, 'basis', {basis}, 'edge_commit_db', cell2mat(arrayfun(@(w) ED{w}.edge, wC, 'UniformOutput', false))', ...
    'edge_commit_km', cell2mat(arrayfun(@(w) ED{w}.km, wC, 'UniformOutput', false))', ...
    'edge_commit_km_all', cell2mat(arrayfun(@(w) ED{w}.km_all, wC, 'UniformOutput', false))', ...
    'edge_floor_db', ED{wF}.edge', 'edge_sys_db', ED{7}.edge', 'edge_sys_km', ED{7}.km', 'edge_sysl_db', ED{8}.edge', ...
    'first_not_commit_db', ED{wC(1)}.first_not', 'nominal', {lbl(inom)}, 'hover', RN.commit.edge_v(inom, 1)', ...
    'v161', RN.commit.edge_v(inom, 2)', 'hover_sys', RN.sys.edge_v(inom, 1)', 'v161_sys', RN.sys.edge_v(inom, 2)', ...
    'follower_cells', {lbl(ifo)}, 'follower_fmin', FRG.fmin, 'follower_delays', FDL, ...
    'fa_verdict', vt(CL.fa), 'fa_n', reshape([CL.fa.n], nD, nS), 'fa_claim_verdict', vt(CL.fac), ...
    'fa_claim_n', reshape([CL.fac.n], nD, nS), 'fa_commit', FAP, 'hover_label', HOVER, 'link_verdict', [CL.link.verdict], ...
    'link_n', [CL.link.n], 'fa_edge_db', [CE.fa.edge], 'link_edge_db', CE.link.edge, 'ohp_verdict', OV, 'ohp_alt_m', OHP.alt_m, ...
    'ohp_r0_km', OHP.r0_km, 'b4', B4, 'fa_bound_met', FAV == 1, 'fa_per_hour', FRall.per_hour, ...
    'fa_per_hour_hi', FRall.per_hour_hi, 'fa_mtbf_s', FRall.mtbf_s, 'check_commit', reshape([CKV.commit], nD, []), ...
    'predicted_vs_committed', AGR, 'bands_skipped', {skipped});
save('results/edge_map.mat', 'EM', 'EDGE_NUM', 'FT', 'CF', 'CS', 'VAR');
fprintf('Saved results/edge_map.{txt,mat}, results/edge_summary.txt, results/edge_bands.png, ');
fprintf('results/edge_heatmap_{%s}.png (%.1f min)\n', strjoin(FIG, ','), toc(t0) / 60);

%% ===================== Local functions =====================
function specs = cell_episodes(PP, cells, sp, reps, follow, unk, NE, T, rs, fdelay)
% Episodes of the cells on the geometries each flies in split sp (PP.cell_geo), one
% policy_episodes.m call per geometry list.
specs = {};
if isempty(cells), return; end
g = arrayfun(@(c) mat2str(PP.cell_geo{c}{sp}), cells, 'UniformOutput', false);
[u, ~, j] = unique(g, 'stable');
for k = 1:numel(u)
    cc = cells(j == k); rr = PP.cell_geo{cc(1)}{sp};
    if isempty(rr), continue; end
    specs = [specs, policy_episodes(cc, numel(PP.ebno), rr, reps, follow, unk, NE, T, rs, fdelay)]; %#ok<AGROW>
end
end

function [VAR, v] = var_add(VAR, kind, fd, D, pol)
% Column of a variant (set kind, follower delay, signalling delay, policy), added when new.
v = var_of(VAR, kind, fd, D, pol);
if v == 0, VAR(end+1) = struct('kind', kind, 'fd', fd, 'D', D, 'pol', pol); v = numel(VAR); end
end

function v = var_of(VAR, kind, fd, D, pol)
% Column of a variant, 0 when it was not run.
v = find(strcmp({VAR.kind}, kind) & arrayfun(@(x) isequaln(x.fd, fd), VAR) & [VAR.D] == D & [VAR.pol] == pol, 1);
if isempty(v), v = 0; end
end

function [det, deth] = det_layers(F, TGT, B)
% DET over the flights F and DET_h over the harmed ones.
det = edge_verdict(F.det_k, F.det_n, F.geo, TGT.det, 'ge', false, B);
m = F.harm;
deth = edge_verdict(F.det_k(m), F.det_n(m), F.geo(m), TGT.det, 'ge', false, B);
end

function V = fa_claim(CF, v, e, thr, TGT, B)
% FA of a claim that reaches Eb/N0 e, variant v: the clean flights CF of every Eb/N0
% from the KPI 1 threshold thr up (KPI 6), from e up when e lies below it.
F = take_rows(CF, CF.eb >= min(e, thr) - 1e-9);
V = edge_verdict(F.fa_k(:, v), F.fa_n(:, v), F.geo, TGT.fa, 'le', true, B);
end

function V = surv_layer(F, sk, TGT, B)
% Flights some configuration recovers (sk: the recoverability of the set).
V = edge_verdict(double(F.(sk)), ones(size(F.geo)), F.geo, TGT.surv, 'ge', true, B);
end

function P = pol_layers(F, v, sk, TGT, B)
% REC (held among the recoverable flights), PROT (held among all) and LINK_T of the
% variant in column v over the threat flights F; LINK_T's target is twice the same
% flights' clean link, at least the LINK target.
s = F.(sk);
P.rec = edge_verdict(F.held_k(s, v), F.ep_n(s, v), F.geo(s), TGT.rec, 'ge', true, B);
P.prot = edge_verdict(F.held_k(:, v), F.ep_n(:, v), F.geo, TGT.prot, 'ge', true, B);
P.tgt = max(2 * sum(F.cl_k, 'omitnan') / max(sum(F.cl_n, 'omitnan'), 1), TGT.link);
P.linkt = edge_verdict(F.lt_k(:, v), F.lt_n(:, v), F.geo, P.tgt, 'le', false, B);
end

function X = commit_rows(FTi, rows, v, vr, sk, BL, fa, fa_pt, link, fav, TGT, B, BV, dirc, cv, DH, nS)
% The commitment (edge_commit.m) of the rows (indices into the threat rows) for the
% variant in column v; vr the random policy's column (0: none); fa the claim's FA and
% fa_pt the point's own at every Eb/N0. A veto band (BV) is NOT COMMITTED when its PROT,
% DET_h or LINK_T is, or the clean link's FA or LINK in it (cv: per region key and band).
% DH caches DET_h per row and region.
nr = numel(rows); VZ = edge_verdict([], [], [], 0.9, 'ge', false);
X = struct('prot', repmat(VZ, nr, nS), 'linkt', repmat(VZ, nr, nS), 'rec', repmat(VZ, nr, nS), 'tgt', nan(nr, nS), ...
    'h', zeros(nr, nS), 'band', nan(nr, nS), 'bfail', {repmat({''}, nr, nS)}, 'commit', zeros(nr, nS), ...
    'lim', {repmat({''}, nr, nS)}, 'rnd', nan(nr, nS));
for q = 1:nr
    i = rows(q); Fi = FTi{i};
    for s = 1:nS
        F = take_rows(Fi, Fi.s == s);
        P = pol_layers(F, v, sk, TGT, B);
        X.prot(q, s) = P.prot; X.linkt(q, s) = P.linkt; X.rec(q, s) = P.rec; X.tgt(q, s) = P.tgt;
        if vr > 0
            Vr = edge_verdict(F.held_k(:, vr), F.ep_n(:, vr), F.geo, TGT.prot, 'ge', true, B); X.rnd(q, s) = Vr.verdict;
        end
    end
    L = struct('prot', vt(X.prot(q, :)), 'deth', vt(BL.deth(i, :)), 'deth_n', [BL.deth(i, :).n], 'fa', vt(fa), ...
        'fa_pt', vt(fa_pt), 'link', vt(link), 'linkt', vt(X.linkt(q, :)), 'fav', fav);
    veto = @(R) band_veto(take_rows(Fi, ismember(Fi.s, R)), v, BV, dirc(i), cv(region_key(R, nS), :), DH, ...
        sprintf('%d %s', i, mat2str(R)), TGT, B);
    E = edge_commit(L, veto);
    X.commit(q, :) = E.v; X.lim(q, :) = E.lim; X.band(q, :) = E.band; X.bfail(q, :) = E.bfail; X.h(q, :) = E.h;
end
end

function k = region_key(R, nS)
% Key of a veto region: s for the points s to nS, nS + s for the point s alone (region).
k = R(1) + nS * (isscalar(R) && R(1) < nS);
end

function [b, names] = no_veto(~)
% No band reading (a single check point or band).
b = 1; names = '';
end

function R = region(key, nS)
% Eb/N0 points of a veto region: key s the point s and every point above it, nS + s the
% point s alone.
if key <= nS, R = key:nS; else, R = key - nS; end
end

function dh = band_deth(F, BV, isdir, TGT, B)
% DET_h of every veto band over the flights F (NaN: no flight, or the band does not apply).
dh = nan(1, numel(BV));
for b = 1:numel(BV)
    if strcmp(BV(b).axis, 'align') && ~isdir, continue; end
    Fb = take_rows(F, in_band(F, BV(b)));
    if isempty(Fb.geo), continue; end
    [~, V] = det_layers(Fb, TGT, B); dh(b) = V.verdict;
end
end

function [bv, names] = band_veto(F, v, BV, isdir, cv, DH, key, TGT, B)
% -1 and the bands' names when a veto band of the flights F is NOT COMMITTED, else 1.
if ~isKey(DH, key), DH(key) = band_deth(F, BV, isdir, TGT, B); end
dh = DH(key);
bad = {};
for b = 1:numel(BV)
    if strcmp(BV(b).axis, 'align') && ~isdir, continue; end
    Fb = take_rows(F, in_band(F, BV(b)));
    if isempty(Fb.geo), continue; end
    no = cv(b) == -1 || dh(b) == -1;
    if ~no
        P = edge_verdict(Fb.held_k(:, v), Fb.ep_n(:, v), Fb.geo, TGT.prot, 'ge', true, B);
        no = P.verdict == -1;
    end
    if ~no
        tl = max(2 * sum(Fb.cl_k, 'omitnan') / max(sum(Fb.cl_n, 'omitnan'), 1), TGT.link);
        Lt = edge_verdict(Fb.lt_k(:, v), Fb.lt_n(:, v), Fb.geo, tl, 'le', false, B);
        no = Lt.verdict == -1;
    end
    if no, bad{end+1} = BV(b).name; end %#ok<AGROW>
end
bv = 1 - 2 * ~isempty(bad); names = strjoin(bad, ', ');
end

function vk = check_verdicts(CKV, f)
% Verdict of every check point in a layer: 'commit<d>' the commitment at delay d.
if startsWith(f, 'commit'), d = sscanf(f, 'commit%d'); vk = arrayfun(@(x) x.commit(d), CKV);
elseif strcmp(f, 'sys'), vk = [CKV.sys];
else, vk = arrayfun(@(x) x.(f).verdict, CKV);
end
end

function [v, lim] = all_of(vd, names)
% A conjunction: COMMITTED when every part is, NOT COMMITTED when one is not; the parts
% that are not COMMITTED.
if all(vd == 1), v = 1; elseif any(vd == -1), v = -1; else, v = 0; end
lim = names(vd ~= 1);
end

function v = check_at(vk, m)
% Verdict of the first check point where m holds, NaN when there is none.
q = find(m, 1); v = NaN; if ~isempty(q), v = vk(q); end
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
    case 'k', x = F.ksig;
    otherwise, x = F.(b.axis);
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

function S = blank_rows(S, n)
% n rows of zeros (false for a logical field) with the columns of every field of S.
f = fieldnames(S);
for i = 1:numel(f)
    if islogical(S.(f{i})), S.(f{i}) = false(n, size(S.(f{i}), 2)); else, S.(f{i}) = zeros(n, size(S.(f{i}), 2)); end
end
end

function x = field_or_nan(d, f)
if isfield(d, f), x = d.(f); else, x = NaN; end
end

function r = rate_of(F, m, v, f)
r = sum(F.(f)(m, v)) / sum(F.ep_n(m, v));
end

function v = vt(V)
v = reshape([V.verdict], size(V));
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

function s = evid_txt(V)
% value [lo, hi] n, evidence only (no verdict).
if V.n == 0, s = sprintf('%-28s', '-'); return; end
s = sprintf('%-28s', sprintf('%5.1f [%5.1f, %5.1f] %3d', 100 * V.value, 100 * V.lo, 100 * V.hi, V.n));
end

function s = band_txt(V)
if V.n == 0, s = sprintf('%-12s', '-'); else, s = sprintf('%-12s', sprintf('%.1f %d%s', 100 * V.value, V.n, vsym(V.verdict))); end
end

function s = edge_txt(e, d)
if isnan(e), s = 'none'; else, s = sprintf('%g dB (%.2f km)', e, d); end
end

function s = per_layer(x)
% The commitment's value, then SYSTEM's, DET, SURV and REC.
s = sprintf('%s; SYSTEM %s [D %s, S %s, R %s]', x{:});
end

function s = num_txt(x, f)
if isnan(x), s = '-'; else, s = sprintf(f, x); end
end

function s = set_txt(X, C)
% The row kind of a commitment set.
switch X.kind
    case 'static', s = 'static threats';
    case 'follow', s = sprintf('follower re-acquiring %d cycles (%d ms) after a hop', X.fd, X.fd * C.period_ms);
    case 'comb', s = 'jammer on every channel (assumed)';
end
end

function s = fol_txt(f, nm, period_ms)
% The fastest follower of the COMMITTED run: >= f cycles (ms).
if isnan(f), s = 'none'; else, s = sprintf('>=%d (%d ms)', f, f * period_ms); end
if nm, s = [s '!']; end
end

function t = rate_txt(F)
% False changes per cycle, per hour of flight and the mean time between them, with the
% 95% bound (false_change_rate.m).
if isnan(F.rate), t = '-'; return; end
t = sprintf('%d in %d cycles: %.2g per cycle (<= %.2g), %.0f per hour (<= %.0f), one every %.3g s (>= %.3g s)', ...
    F.k, F.cycles, F.rate, F.hi, F.per_hour, F.per_hour_hi, F.mtbf_s, F.mtbf_lo_s);
end

function s = range_txt(r, u)
if any(isnan(r)), s = 'none'; else, s = sprintf('%.0f-%.0f %s', r(1), r(2), u); end
end

function s = sev_txt(lo, hi, nm, threat, C, PP)
% The COMMITTED run of levels around the nominal one: the levels of a single threat, the
% severity names of a combined one.
if isnan(lo)
    s = 'none';
elseif contains(threat, '+')
    s = sprintf('%s..%s', PP.sev_names{lo}, PP.sev_names{hi});
else
    s = sprintf('%g..%g dB', C.sev.(threat).levels(lo), C.sev.(threat).levels(hi));
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
