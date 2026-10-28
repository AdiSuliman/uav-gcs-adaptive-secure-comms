%% MAP_SURVIVABILITY_BOUNDARY — proposal deliverable 7 (primary research output)
% Maps, per threat, where an attack is recoverable versus non-recoverable over
% attack severity level and Eb/N0, using the system's REAL configuration set
% (policy_actions.m, one choice per domain) applied through apply_countermeasure.m.
% Every (threat, level, Eb/N0) cell is simulated with every configuration on one
% run of RUN_FRAMES frames with its own seed, shared by all configurations (common random
% numbers; identical physics simulated once, pool_cell.m, parallel workers). A cell
% is RECOVERABLE when some configuration brings BER within 2x AND packet loss (CRC)
% within 2x (+ one loss event of the run, packet_share.m) of the clean link at the same Eb/N0 (proposal KPI 4),
% MARGINAL when the best BER is within 5x, otherwise NON-RECOVERABLE. Directional
% threats are mapped for two flight geometries: interferer 42.2 deg from the
% GCS direction (separable by the antenna array) and 11.4 deg (aligned);
% path_loss and antenna_fault do not depend on the geometry; airframe shadowing is mapped
% in a coordinated turn at the bank Sun et al.'s fit pairs with the level
% (shadow_roll_band.m, the GCS abeam), where the airframe hides an antenna (shadow_hidden.m).
% The K-factor is fixed at the nominal 10 dB and the UAV antenna keeps its horizon gain
% toward the GCS (the pools draw K and altitude per flight).
%
%   Map A (without goodput loss) — configurations with full goodput
%   Map B (any configuration)    — every configuration, incl. rate_reduce and fec_interleave
%
% Gap cells (Map B recoverable/marginal, Map A non-recoverable) are the regime
% where the link survives only by trading throughput — the goodput trade-off
% named in the proposal. Each cell also records WHICH configuration achieves it.
%
% Output: results/survivability_boundary_mapA.txt, results/survivability_boundary_mapB.txt,
%         results/survivability_gap_analysis.txt, results/survivability_map_neutralization.png (Map A),
%         results/survivability_map_link.png (Map B), data/survivability_boundary.mat
%
% With "surv_v2": true in profile.json (surv_options.m, docs/surv_p3_protocol.md) every cell
% flies NR = 5 flights, the same at every level and Eb/N0 of an entry (surv_flights.m); noise
% bursts are two entries, Xu et al.'s random jammer at its most severe measured duty and
% Marti et al.'s J4 (surv_nb_entries.m); the status rule runs on the flights' means and each
% cell gets the link-limited (L), no_action (N) and saturated marks, a bootstrap interval and
% a committed verdict (surv_grid.m); the gap cells come in two classes (surv_gap_report.m).
% Without it (profile 1) the map is as described above.

close all; clc;
fprintf('=== Survivability boundary map (real configuration set) ===\n\n');

%% ========== CONFIG ==========
N_BASELINE_REPEATS = 5;       % seeded clean-link runs per Eb/N0
RUN_FRAMES         = 57;      % frames per (threat, geometry, level, Eb/N0) run, one seed shared by every configuration
RATIO_RECOVERABLE  = 2;
RATIO_MARGINAL     = 5;
BER_FLOOR          = 1e-4;    % clean reference floor, as the decision layer
N_WORKERS          = 6;
opt = struct('F_SUB', RUN_FRAMES, 'tw', 10, 'delay_bits', 20);
SV = surv_options();                      % the map's protocol (profile.json surv_v2; none for profile 1)
NR = []; if SV.v2, NR = SV.NR; end        % flights per cell under surv_v2

ACTIONS = policy_actions();
p_ref = load_params_quiet();
GEOM_AOA = p_ref.geom_aoa_deg;                   % interferer direction from the GCS [deg]: separated, aligned (init_params.m)
MECH_B = ACTIONS(~strcmp(ACTIONS, 'no_action'));
MECH_A = MECH_B(cellfun(@(a) no_goodput_loss(p_ref, a), MECH_B));
ACT_CODE = containers.Map(MECH_B, cellfun(@act_code, MECH_B, 'UniformOutput', false));

% Severity levels per threat: those of the detector dataset (dataset_levels.m), in-band
% interferers up to 30 dB over our signal (the in-band cap, Liu et al.)
clear threat_cfg                                  % scripts share the base workspace
DL = dataset_levels();
threat_cfg = struct('name', {DL.name}, 'level_field', {DL.param}, 'levels', {DL.levels});
ip = strcmp({threat_cfg.name}, 'path_loss');            % up to the measured building loss (Simunek et al. 2011,
threat_cfg(ip).levels = [threat_cfg(ip).levels, 33 42]; % 33-42 dB, Figs. 6 and 11), beyond the training levels
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    if SV.v2                                            % the noise-burst entries too, two flights per cell
        threat_cfg = threat_cfg([1 2 4]); threat_cfg(1).levels = [4 16]; threat_cfg(2).levels = [4 16];
        threat_cfg(3).levels = [7 16]; NR = 2;
    else
        threat_cfg = threat_cfg([1 4]); threat_cfg(1).levels = [4 16]; threat_cfg(2).levels = [7 16];
    end
    RUN_FRAMES = 20; opt.F_SUB = RUN_FRAMES;
end

% Map entries: directional threats once per geometry, signal-side threats once
clear maps
for t = 1:numel(threat_cfg)
    if ismember(threat_cfg(t).name, {'path_loss', 'antenna_fault', 'airframe_shadowing'}), geo_a = NaN; else, geo_a = GEOM_AOA; end
    for g = geo_a
        e = threat_cfg(t); e.aoa = g; e.base = e.name;
        if ~isnan(g), e.name = sprintf('%s @ %g deg', e.base, g); end
        if exist('maps', 'var'), maps(end+1) = e; else, maps = e; end %#ok<AGROW>
    end
end
if SV.v2, maps = surv_nb_entries(maps, p_ref); end      % noise bursts: the random jammer at its most severe duty, and J4

p0 = p_ref;
p0 = fec_rx_on(p0, fec_rx_config());       % the profile's decoder of the coded link (profile.json)
if SV.v2 && isempty(fec_rx_config()) && ~(exist('SMOKE', 'var') && SMOKE)
    error('map_survivability_boundary:fec_rx', ['surv_v2 maps the coded link with the decoder profile.json ' ...
        'states (fec_rx): "d78" or the choice of dev set C']);
end
p0.int_aoa_random = false; p0.k_random = false; p0.quiet_build = true;
p0.yaw_random = false;                  % the mapped geometries stay fixed through the run
p0.corr_random = false;
p0.gcs_aoa_random = false;              % the GCS at broadside: the mapped directions are relative to it
p0.gcs_tracked = false;                 % the GCS antenna on its axis
p0.alt_random = false;                  % no altitude: the UAV antenna's horizon gain toward the GCS
p0.jam_timing_random = false;           % the shortest sweep at phase 0: the sweeper on our channel in every frame
p0.tdl_random = false;                  % the median delay spreads (p0.tdl_ds_ns), with the delay line on
p0.cap_frames = RUN_FRAMES;             % the in-band cap holds over the whole run
SNR_points = p0.EbNo_dB;
nS = numel(SNR_points);
v_nom = p0.v_nominal * 3.6;                       % nominal cruise speed [km/h]
t0 = tic;

NWP = N_WORKERS; pl = [];
if exist('SMOKE', 'var') && SMOKE
    NWP = 0;                                            % reduced chain check: on this process, no parallel turn
else
    turn = []; parallel_turn('take'); turn = onCleanup(@() parallel_turn('give'));   % one heavy parallel stage at a time on this computer
    pl = gcp('nocreate');
    if isempty(pl) || pl.NumWorkers ~= N_WORKERS
        delete(pl); pl = parpool('Processes', N_WORKERS);
    end
    repo = pwd;
    spmd
        pool_worker_init(repo);
    end
end

%% ========== 1. Clean-link baseline per Eb/N0 ==========
fprintf('Measuring the clean link (none), %d seeded runs per Eb/N0...\n', N_BASELINE_REPEATS);
geo_c = arrayfun(@(s) struct('seed', 700000 + (1:N_BASELINE_REPEATS), 'speed', v_nom * ones(1, N_BASELINE_REPEATS), ...
    'run', 1:N_BASELINE_REPEATS), 1:nS, 'UniformOutput', false);
pc = p0; pc.active_threat = 'none';
Pc = pool_cell(pc, 'none', {'no_action'}, SNR_points, geo_c, [], opt);
ber_clean = cellfun(@(Q) mean(Q.ber), Pc(:, 1, 1))';
fer_clean = cellfun(@(Q) mean(double(Q.fer)), Pc(:, 1, 1))';
for s = 1:nS
    fprintf('  Eb/N0=%2g dB: clean BER = %.4e, packet loss %.3f\n', SNR_points(s), ber_clean(s), fer_clean(s));
end
ber_ref = max(ber_clean, BER_FLOOR);
fprintf('\n');

%% ========== 2. Every entry x level x configuration x Eb/N0 (common seeds across configurations) ==========
nT = numel(maps); nAct = numel(ACTIONS);
jobs = zeros(0, 2);
for t = 1:nT
    for li = 1:numel(maps(t).levels), jobs(end+1, :) = [t li]; end %#ok<AGROW>
end
nJ = size(jobs, 1);
resB = cell(1, nJ); resF = cell(1, nJ); resS = cell(1, nJ);
w = zeros(1, nJ);
for j = 1:nJ
    cfg = maps(jobs(j, 1)); p = p0; p.active_threat = cfg.base; p.(cfg.level_field) = cfg.levels(jobs(j, 2));
    w(j) = pool_cost(p, cfg.base, ACTIONS, nS * RUN_FRAMES, opt);
end
ord = pool_schedule(w);                                % the longest job first, one per free worker
S = struct('jobs', {jobs}, 'maps', {maps}, 'p0', {p0}, 'RUN_FRAMES', {RUN_FRAMES}, 'v_nom', {v_nom}, 'nS', {nS}, ...
    'ACTIONS', {ACTIONS}, 'SNR_points', {SNR_points}, 'opt', {opt}, 'NR', {NR});
res = pool_lpt(@(S, j) pool_job('surv', S, j), S, ord, pl);
clear S
res(ord) = res;                                        % back in job order
for j = 1:nJ, [resB{j}, resF{j}, resS{j}] = res{j}{:}; end
clear res
if SV.v2                                               % each flight's values; their means enter the rule
    runB = resB; runF = resF;
    resB = cellfun(@(x) mean(x, 3), resB, 'UniformOutput', false);
    resF = cellfun(@(x) mean(x, 3), resF, 'UniformOutput', false);
    resS = cellfun(@(x) mean(x, 3), resS, 'UniformOutput', false);
end
ber_all = cell(1, nT); fer_all = cell(1, nT); slack_all = cell(1, nT);             % {entry}(level, configuration, snr)
for t = 1:nT
    nL = numel(maps(t).levels);
    B = nan(nL, nAct, nS); Fe = nan(nL, nAct, nS); Sl = nan(nL, nAct, nS);
    for li = 1:nL
        j = find(jobs(:, 1) == t & jobs(:, 2) == li);
        B(li, :, :) = reshape(resB{j}, [1 nAct nS]); Fe(li, :, :) = reshape(resF{j}, [1 nAct nS]);
        Sl(li, :, :) = reshape(resS{j}, [1 nAct nS]);
    end
    ber_all{t} = B; fer_all{t} = Fe; slack_all{t} = Sl;
end
if SV.v2
    ber_run = cell(1, nT); fer_run = cell(1, nT);                                  % {entry}(level, configuration, snr, flight)
    for t = 1:nT
        nL = numel(maps(t).levels); Br = nan(nL, nAct, nS, NR); Fr = Br;
        for li = 1:nL
            j = find(jobs(:, 1) == t & jobs(:, 2) == li);
            Br(li, :, :, :) = reshape(runB{j}, [1 nAct nS NR]); Fr(li, :, :, :) = reshape(runF{j}, [1 nAct nS NR]);
        end
        ber_run{t} = Br; fer_run{t} = Fr;
    end
    clear runB runF
end
fprintf('Mapped %d entries x levels in %.1f min\n\n', nJ, toc(t0)/60);

%% ========== 3. Build both maps ==========
fprintf('Classifying (ratio to clean link): recoverable <= %gx (BER and packet loss), marginal <= %gx\n\n', ...
    RATIO_RECOVERABLE, RATIO_MARGINAL);
if SV.v2
    Z = struct('ok', RATIO_RECOVERABLE, 'marg', RATIO_MARGINAL, 'sat', 0.45, 'lim', 0.5, 'frames', RUN_FRAMES, ...
        'bits', p0.frame_length, 'B', 4000, 'NR', NR, 'floor', BER_FLOOR);
    grid_data_A = surv_grid(ber_all, fer_all, slack_all, ber_run, fer_run, maps, ACTIONS, MECH_A, ber_ref, fer_clean, Z);
    grid_data_B = surv_grid(ber_all, fer_all, slack_all, ber_run, fer_run, maps, ACTIONS, MECH_B, ber_ref, fer_clean, Z);
else
    grid_data_A = build_map(ber_all, fer_all, maps, ACTIONS, MECH_A, ber_ref, fer_clean, slack_all, RATIO_RECOVERABLE, RATIO_MARGINAL);
    grid_data_B = build_map(ber_all, fer_all, maps, ACTIONS, MECH_B, ber_ref, fer_clean, slack_all, RATIO_RECOVERABLE, RATIO_MARGINAL);
end

%% ========== 4. Reports ==========
if ~isfolder('results'), mkdir('results'); end   % exist(...,'dir') also finds toolbox folders on the path
if SV.v2
    report_A = surv_report(grid_data_A, ber_ref, fer_clean, SNR_points, 'MAP A — WITHOUT GOODPUT LOSS', MECH_A, ACT_CODE, Z);
else
    report_A = build_report(grid_data_A, ber_ref, SNR_points, RATIO_RECOVERABLE, RATIO_MARGINAL, ...
        'MAP A — WITHOUT GOODPUT LOSS', MECH_A, ACT_CODE);
end
write_report(report_A, 'results/survivability_boundary_mapA.txt');
if SV.v2
    report_B = surv_report(grid_data_B, ber_ref, fer_clean, SNR_points, ...
        'MAP B — ANY CONFIGURATION (incl. rate reduction and FEC)', MECH_B, ACT_CODE, Z);
else
    report_B = build_report(grid_data_B, ber_ref, SNR_points, RATIO_RECOVERABLE, RATIO_MARGINAL, ...
        'MAP B — ANY CONFIGURATION (incl. rate reduction and FEC)', MECH_B, ACT_CODE);
end
write_report(report_B, 'results/survivability_boundary_mapB.txt');
fprintf('\n--- MAP A (without goodput loss) ---\n');  fprintf('%s\n', report_A{:});
fprintf('\n--- MAP B (any configuration) ---\n');      fprintf('%s\n', report_B{:});

%% ========== 5. Gap analysis ==========
gap_report = {};
gap_report{end+1} = '=== SURVIVABILITY GAP ANALYSIS ===';
gap_report{end+1} = 'Cells where the link survives only with a goodput cost (Map B: recoverable/marginal)';
gap_report{end+1} = 'but not with any goodput-free configuration (Map A: non-recoverable): survival bought';
gap_report{end+1} = 'with throughput -- the goodput trade-off named in the proposal.';
gap_report{end+1} = '';
n_gap_total = 0;
for t = 1:nT
    gA = grid_data_A(t); gB = grid_data_B(t);
    gap_mask = (gB.status >= 1 & gB.status <= 2) & (gA.status == 3);
    n_gap = sum(gap_mask(:));
    n_gap_total = n_gap_total + n_gap;
    if n_gap == 0, continue; end
    gap_report{end+1} = sprintf('%s: %d gap cell(s)', gA.threat, n_gap); %#ok<SAGROW>
    [li_idx, s_idx] = find(gap_mask);
    for k = 1:numel(li_idx)
        li = li_idx(k); s = s_idx(k);
        gap_report{end+1} = sprintf('  level=%g, Eb/N0=%gdB: Map A %.2fx (%s) | Map B %.2fx (%s)', ...
            gA.levels(li), SNR_points(s), gA.ratio(li,s), gA.best_action{li,s}, ...
            gB.ratio(li,s), gB.best_action{li,s}); %#ok<SAGROW>
    end
end
gap_report{end+1} = '';
gap_report{end+1} = sprintf('Total gap cells: %d', n_gap_total);
if SV.v2, [gap_report, gap_cls] = surv_gap_report(grid_data_A, grid_data_B, SNR_points); end   % two classes
write_report(gap_report, 'results/survivability_gap_analysis.txt');
fprintf('\n--- GAP ANALYSIS ---\n'); fprintf('%s\n', gap_report{:});

if ~isfolder('data'), mkdir('data'); end
save('data/survivability_boundary.mat','grid_data_A','grid_data_B','ber_clean','ber_ref','fer_clean','BER_FLOOR', ...
    'SNR_points','RATIO_RECOVERABLE','RATIO_MARGINAL','MECH_A','MECH_B','ber_all','fer_all','slack_all','threat_cfg','maps', ...
    'GEOM_AOA','RUN_FRAMES','ACTIONS');
if SV.v2, save('data/survivability_boundary.mat', 'SV', 'NR', 'Z', 'ber_run', 'fer_run', 'gap_cls', '-append'); end

%% ========== 6. Figures ==========
draw_map(grid_data_A, SNR_points, 'Map A: without goodput loss (C, F, S, power control and their combinations)', ...
    'results/survivability_map_neutralization.png', SV.v2);
draw_map(grid_data_B, SNR_points, 'Map B: any configuration (incl. rate reduction and FEC)', ...
    'results/survivability_map_link.png', SV.v2);
fprintf('\nSaved results/survivability_boundary_mapA.txt, mapB.txt, gap_analysis.txt, two PNG maps\n');
fprintf('Saved data/survivability_boundary.mat (%.1f min)\n\n=== Survivability Mapping Complete ===\n', toc(t0)/60);


%% ========== LOCAL FUNCTIONS ==========

function s = ratio_txt(r)
    if r < 0.1, s = '<0.1'; elseif r < 10, s = sprintf('%.1f', r); else, s = sprintf('%.0f', r); end
end

function s = level_label(base)
    switch base
        case 'path_loss',          s = 'Extra path loss (dB)';
        case 'spoofing',           s = 'Spoofer over signal (dB)';
        case 'antenna_fault',      s = 'Antenna-fault loss (dB)';
        case 'benign_interference', s = 'Interference over signal (dB)';
        case 'airframe_shadowing', s = 'Shadowing loss (dB)';
        otherwise,                 s = 'JSR (dB)';
    end
end

function tf = no_goodput_loss(p, a)
    [~, ~, cm] = apply_countermeasure(p, 'none', a);
    tf = cm.goodput_factor == 1;
end

function c = act_code(a)
    parts = strsplit(a, '+');
    m = containers.Map({'channel_switch','freq_diversity','spatial_diversity','rate_reduce','power_control','fec_interleave'}, ...
        {'C','F','S','R','P','E'});
    c = strjoin(cellfun(@(x) m(x), parts, 'UniformOutput', false), '');
end

function p = load_params_quiet()
    evalc('init_params');
    p = load('params.mat').params;
end

function grid_data = build_map(ber_all, fer_all, threat_cfg, ACTIONS, act_set, ber_clean, fer_clean, slack_all, ...
    RATIO_RECOVERABLE, RATIO_MARGINAL)
    % Recoverable: some configuration of act_set with BER <= 2x and packet loss
    % <= 2x (+ one loss event of the run, packet_share.m) of the clean link; otherwise the
    % best BER decides between marginal and non-recoverable.
    nS = numel(ber_clean);
    cols = find(ismember(ACTIONS, act_set));
    grid_data = struct('threat',{},'base',{},'aoa',{},'levels',{},'ber_best',{},'ratio',{}, ...
        'status',{},'ber_attacked',{},'best_action',{});
    for t = 1:numel(threat_cfg)
        B = ber_all{t}; Fe = fer_all{t};
        levels = threat_cfg(t).levels;
        nL = numel(levels);
        ber_best = nan(nL, nS); ratio = nan(nL, nS); status = zeros(nL, nS);
        best_action = cell(nL, nS);
        ber_attacked = squeeze(B(:, 1, :));
        if nL == 1, ber_attacked = ber_attacked(:)'; end
        for li = 1:nL
            for s = 1:nS
                okc = B(li, cols, s) <= RATIO_RECOVERABLE * ber_clean(s) & ...
                      Fe(li, cols, s) <= RATIO_RECOVERABLE * fer_clean(s) + slack_all{t}(li, cols, s);
                if any(okc)
                    cand = cols(okc); [ber_best(li,s), k] = min(B(li, cand, s)); kc = cand(k);
                    status(li,s) = 1;
                else
                    [ber_best(li,s), k] = min(B(li, cols, s)); kc = cols(k);
                    if ber_best(li,s) / ber_clean(s) <= RATIO_MARGINAL, status(li,s) = 2; else, status(li,s) = 3; end
                end
                best_action{li,s} = ACTIONS{kc};
                ratio(li,s) = ber_best(li,s) / ber_clean(s);
            end
        end
        grid_data(end+1) = struct('threat',threat_cfg(t).name,'base',threat_cfg(t).base,'aoa',threat_cfg(t).aoa, ...
            'levels',levels, 'ber_best',ber_best,'ratio',ratio,'status',status, ...
            'ber_attacked',ber_attacked,'best_action',{best_action}); %#ok<AGROW>
    end
end

function report = build_report(grid_data, ber_clean, SNR_points, RATIO_RECOVERABLE, ...
    RATIO_MARGINAL, title_str, act_set, ACT_CODE)
    nT = numel(grid_data);
    nS = numel(SNR_points);
    report = {};
    report{end+1} = sprintf('=== SURVIVABILITY BOUNDARY MAP — %s ===', title_str);
    report{end+1} = sprintf('Generated: %s', datestr(now));
    report{end+1} = sprintf('Configurations included: %d (policy_actions.m, apply_countermeasure.m)', numel(act_set));
    report{end+1} = '';
    report{end+1} = 'A state is classified by the best configuration relative to the clean link at the same Eb/N0:';
    report{end+1} = sprintf(['  RECOVERABLE (R) : BER and packet loss within %gx | MARGINAL (M) : BER within %gx | ' ...
        'NON-RECOVERABLE (X) : worse'], RATIO_RECOVERABLE, RATIO_MARGINAL);
    report{end+1} = ['Letters after the status = configuration achieving it: C channel_switch, F freq_diversity, ' ...
        'S spatial_diversity, R rate_reduce, P power_control, E fec_interleave.'];
    report{end+1} = '';
    report{end+1} = 'Clean-link reference BER per Eb/N0 (measured, floor 1e-4 = resolution of a cell):';
    for s = 1:nS
        report{end+1} = sprintf('  %2g dB : %.4e', SNR_points(s), ber_clean(s)); %#ok<AGROW>
    end
    report{end+1} = '';
    report{end+1} = '--- Boundary map, per threat (rows = severity level, cols = Eb/N0) ---';
    for t = 1:nT
        g = grid_data(t);
        report{end+1} = sprintf('%s:', g.threat); %#ok<AGROW>
        hdr = sprintf('  %-10s', 'level\SNR');
        for s = 1:nS, hdr = [hdr sprintf('%8s', sprintf('%gdB', SNR_points(s)))]; end %#ok<AGROW>
        report{end+1} = hdr; %#ok<AGROW>
        for li = 1:numel(g.levels)
            line = sprintf('  %-10g', g.levels(li));
            for s = 1:nS
                switch g.status(li,s)
                    case 1, c = 'R'; case 2, c = 'M'; case 3, c = 'X'; otherwise, c = '.';
                end
                if g.status(li,s) > 0, c = [c ACT_CODE(g.best_action{li,s})]; end %#ok<AGROW>
                line = [line sprintf('%8s', c)]; %#ok<AGROW>
            end
            report{end+1} = line; %#ok<AGROW>
        end
        n_rec = sum(g.status(:)==1); n_mar = sum(g.status(:)==2); n_non = sum(g.status(:)==3);
        n_tot = n_rec + n_mar + n_non;
        report{end+1} = sprintf('  -> recoverable %d/%d (%.0f%%) | marginal %d | non-recoverable %d', ...
            n_rec, n_tot, 100*n_rec/max(n_tot,1), n_mar, n_non); %#ok<AGROW>
        report{end+1} = ''; %#ok<AGROW>
    end
    all_status = [];
    for t = 1:nT, all_status = [all_status; grid_data(t).status(:)]; end %#ok<AGROW>
    all_status = all_status(all_status > 0);
    report{end+1} = '=== OVERALL ===';
    report{end+1} = sprintf('Total states mapped: %d', numel(all_status));
    report{end+1} = sprintf('  Recoverable     : %d (%.1f%%)', sum(all_status==1), 100*mean(all_status==1));
    report{end+1} = sprintf('  Marginal        : %d (%.1f%%)', sum(all_status==2), 100*mean(all_status==2));
    report{end+1} = sprintf('  Non-recoverable : %d (%.1f%%)', sum(all_status==3), 100*mean(all_status==3));
end

function write_report(report, path)
    fid = fopen(path,'w');
    for i=1:numel(report), fprintf(fid,'%s\n',report{i}); end
    fclose(fid);
end

function draw_map(grid_data, SNR_points, sup_title, out_path, v2)
    % v2 (surv_v2): link-limited cells in blue, "0 err" for no error, ? on cells not committed
    if nargin < 5, v2 = false; end
    nT = numel(grid_data);
    nS = numel(SNR_points);
    fig = figure('Position',[30 30 1900 780],'Color','w');
    cmap = [0.20 0.65 0.25;
            0.95 0.75 0.15;
            0.80 0.20 0.20];
    if v2, cmap = [cmap; 0.25 0.45 0.80]; end
    for t = 1:nT
        g = grid_data(t);
        subplot(2, ceil(nT/2), t);
        st = g.status;
        if v2, st(g.link_limited) = 4; end
        imagesc(st, [1 size(cmap, 1)]);
        colormap(gca, cmap);
        set(gca,'XTick',1:nS,'XTickLabel',compose('%g',SNR_points), ...
                'YTick',1:numel(g.levels),'YTickLabel',compose('%g',g.levels));
        xlabel('E_b/N_0 (dB)'); ylabel(level_label(g.base));
        title(strrep(g.threat,'_',' '), 'Interpreter','none');
        for li = 1:numel(g.levels)
            for s = 1:nS
                if ~isnan(g.ratio(li,s))
                    c = ratio_txt(g.ratio(li,s));
                    if v2 && g.ratio(li,s) == 0, c = '0 err'; end
                    if v2 && ~g.committed(li,s), c = [c '?']; end
                    text(s, li, c, ...
                        'HorizontalAlignment','center','FontSize',7,'Color','w');
                end
            end
        end
    end
    sub = ['Cell: BER of the best configuration / clean-link BER at the same E_b/N_0.  ' ...
        'Green: recoverable (BER and packet loss <= 2x clean), yellow: marginal (BER <= 5x), red: non-recoverable'];
    if v2
        sub = {sub, ['Means over the flights of a cell.  Blue: link-limited (clean packet loss >= 50%, BER alone decides); ' ...
            '0 err: no bit error; ?: not committed']};
    end
    sgtitle([{sup_title}, sub], 'Interpreter','tex', 'FontSize', 11);
    saveas(fig, out_path);
    close(fig);
end
