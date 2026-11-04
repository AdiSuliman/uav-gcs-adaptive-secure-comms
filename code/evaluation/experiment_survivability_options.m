%% EXPERIMENT_SURVIVABILITY_OPTIONS - What one antenna more or an alternate path adds
% Research experiment of deliverable 7. The system flies p.n_rx UAV antennas (the
% profile), which null up to n_rx-1 interferers (an N-element array nulls up to N-1,
% Winters, Salz & Gitlin), and only when they arrive from other directions than the
% GCS. The system is compared on the recoverability question with one antenna fewer
% on the same aperture (one more for a two-antenna system) and with an alternate path:
%   n-1 antennas   the same aperture with one antenna fewer, one null fewer
%   relay path     the command reaches the UAV over a secondary path (Papathanasiou
%                  et al.: secondary communication paths, backup link; the lecturer's
%                  proposal: an alternate route), modeled as the desired signal
%                  arriving RELAY_DEG away from the GCS direction with RELAY_LOSS_DB
%                  of extra path loss; the interferers stay where they are
% Threats where the extensions can matter: the combined threats (nominal
% severity) and the directional single threats at high severity. Each (threat,
% Eb/N0) is simulated on N_GEOM random flight geometries (interferer directions
% uniform, as in the pools) under every configuration. A geometry is recoverable
% when some configuration brings BER and packet loss within 2x (+ one loss event,
% packet_share.m) of the clean link: each receiver's own clean link, and the
% system's direct link for the relay (the service the relay must give back).
%
% With "surv_v2": true in profile.json (surv_options.m, docs/surv_p3_protocol.md section 10)
% every variant is also judged against the system's clean link (surv3_judge.m), so the n-1
% shares are not upper bounds; an Eb/N0 whose clean link loses so many packets that the
% packet bound passes 100% is marked link-limited (L) and the comparison is repeated on the
% Eb/N0 without L (surv3_report.m); the single threats run at the sources' most severe level;
% the airframe-shadowing combinations fly flights selected so that the roll-in hides an
% antenna (surv3_shadow_flights.m), judged against the clean link of those flights; every
% geometry's BER, packet loss and slack are saved (surv3_metrics.m). Without it (profile 1)
% the experiment is as described above.
%
% Output: results/survivability_options.txt, data/survivability_options.mat

close all; clc;
fprintf('=== Survivability options: antenna count and relay path ===\n\n');
N_GEOM = 8; RUN_FRAMES = 20; N_WORKERS = 6; RATIO = 2;
RELAY_DEG = 60; RELAY_LOSS_DB = 3;
opt = struct('F_SUB', RUN_FRAMES, 'tw', 10, 'delay_bits', 20);
C = decision_config();
SV = surv_options();                                   % profile.json surv_v2; none for profile 1
evalc('init_params');
p0 = load('params.mat').params; p0.quiet_build = true; p0.int_aoa_random = true;
p0 = fec_rx_on(p0, fec_rx_config());           % the profile's decoder of the coded link (profile.json)
if SV.v2 && isempty(fec_rx_config()) && ~(exist('SMOKE', 'var') && SMOKE)
    error('experiment_survivability_options:fec_rx', ['surv_v2 measures the coded link with the decoder ' ...
        'profile.json states (fec_rx): "d78" or the choice of dev set C']);
end
EBNO = p0.EbNo_dB; nS = numel(EBNO);
ACTIONS = policy_actions();
vrange = [p0.speed_kmh_min p0.speed_kmh_max];
COMBOS = C.combos;
SINGLES = {'jamming', 'reactive_jamming', 'noise_burst', 'spoofing', 'sweeping_jammer', 'tone_jamming'};
iHigh = C.nominal + 1;                                 % the 'high' level
if SV.v2, iHigh = numel(C.sev_names); end              % the sources' most severe level
cases = [cellfun(@(t) struct('threat', t, 'field', '', 'level', NaN), COMBOS), ...
         cellfun(@(t) struct('threat', t, 'field', C.sev.(t).field, 'level', C.sev.(t).levels(iHigh)), SINGLES)];
nSys = p0.n_rx; nAlt = nSys - 1;
if nAlt < 2, nAlt = nSys + 1; end                      % a two-antenna system is compared with three
VAR = struct('name', {sprintf('%d antennas', nAlt), sprintf('%d antennas', nSys), 'relay path'}, 'n_rx', {nAlt, nSys, nSys}, ...
    'gcs', {0, 0, RELAY_DEG}, 'loss', {0, 0, RELAY_LOSS_DB}, 'ref', {1, 2, 2});
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    if SV.v2                                            % a shadowing combination too
        iSh = find(contains(COMBOS, 'airframe_shadowing'), 1);
        cases = cases([1 iSh end]); N_GEOM = 2; COMBOS = COMBOS([1 iSh]);
    else
        cases = cases([1 end]); N_GEOM = 2; COMBOS = COMBOS(1);
    end
end
geo = arrayfun(@(s) struct('seed', arrayfun(@(r) pool_seed(1, s, 13, r), 1:N_GEOM), ...
    'speed', arrayfun(@(r) nth2(@pool_seed, 1, s, 13, r, vrange), 1:N_GEOM), 'run', surv3_run_id(1:N_GEOM)), ...
    1:nS, 'UniformOutput', false);
geo_sh = []; SH = []; clean_sh = {};
if SV.v2 && any(contains({cases.threat}, 'airframe_shadowing'))
    ps = p0; ps.gcs_aoa_deg = VAR(2).gcs;               % the direct link's GCS direction, as the jobs set it
    [geo_sh, SH] = surv3_shadow_flights(ps, EBNO, N_GEOM, vrange, unique([VAR(1:2).n_rx]), RUN_FRAMES);
    fprintf('Airframe shadowing: %d flights per Eb/N0 hiding an antenna with %s antennas, %d candidates tried\n', ...
        N_GEOM, strjoin(compose('%d', SH.n_rx), ' and '), sum(SH.tried));
end

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
t0 = tic;

% Clean references of the two receivers (direct link, same geometries)
clean = cell(1, 2);
if ~SV.v2
    parfor (k = 1:2, NWP)
        p = p0; p.n_rx = VAR(k).n_rx; p.active_threat = 'none';
        P = pool_cell(p, 'none', {'no_action'}, EBNO, geo, [], opt);
        clean{k} = struct('ber', cellfun(@(Q) mean(Q.ber), P(:, 1, 1))', 'fer', cellfun(@(Q) mean(double(Q.fer)), P(:, 1, 1))');
    end
else                                                   % per geometry too; also on the shadowing flights (their reference)
    CG = {geo, geo}; KN = [1 2];
    if ~isempty(geo_sh), CG = [CG, {geo_sh, geo_sh}]; KN = [KN, 1 2]; end
    cl = cell(1, numel(KN));
    parfor (k = 1:numel(KN), NWP)
        p = p0; p.n_rx = VAR(KN(k)).n_rx; p.active_threat = 'none';
        P = pool_cell(p, 'none', {'no_action'}, EBNO, CG{k}, [], opt);
        cl{k} = surv3_clean(P(:, 1, 1), N_GEOM);
    end
    clean = cl(1:2); clean_sh = cl(3:end);
    clear cl CG
end

% Every case x option
jobs = [kron((1:numel(cases))', ones(numel(VAR), 1)), repmat((1:numel(VAR))', numel(cases), 1)];
nJ = size(jobs, 1);
rec = cell(1, nJ); best = cell(1, nJ);
w = zeros(1, nJ);
for j = 1:nJ
    c = cases(jobs(j, 1)); p = p0; p.n_rx = VAR(jobs(j, 2)).n_rx; p.active_threat = c.threat;
    if ~isempty(c.field), p.(c.field) = c.level; end
    w(j) = pool_cost(p, c.threat, ACTIONS, geo, opt);
end
ord = pool_schedule(w);                                % the longest job first, one per free worker
S = struct('cases', {cases}, 'VAR', {VAR}, 'jobs', {jobs}, 'p0', {p0}, 'ACTIONS', {ACTIONS}, 'EBNO', {EBNO}, ...
    'geo', {geo}, 'opt', {opt}, 'nS', {nS}, 'N_GEOM', {N_GEOM}, 'clean', {clean}, 'C', {C}, 'RATIO', {RATIO});
if SV.v2, S.V2 = true; S.geo_sh = geo_sh; S.clean_sh = clean_sh; end
res = pool_lpt(@(S, j) pool_job('surv3', S, j), S, ord, pl);
clear S
res(ord) = res;                                        % back in job order
if SV.v2
    met = cell(1, nJ);
    for j = 1:nJ, [rec{j}, best{j}, met{j}] = res{j}{:}; end
else
    for j = 1:nJ, [rec{j}, best{j}] = res{j}{:}; end
end
clear res

if SV.v2
    % Every variant also against the system's clean link; the report with the L marks
    rec_sys = cell(1, nJ); best_sys = cell(1, nJ);
    for j = 1:nJ
        cs = clean{2}; if contains(cases(jobs(j, 1)).threat, 'airframe_shadowing'), cs = clean_sh{2}; end
        [rec_sys{j}, best_sys{j}] = surv3_judge(met{j}, cs, RATIO, C.ber_floor, ACTIONS);
    end
    X = struct('cases', {cases}, 'VAR', {VAR}, 'EBNO', {EBNO}, 'jobs', {jobs}, 'rec', {rec}, 'rec_sys', {rec_sys}, ...
        'clean', {clean}, 'clean_sh', {clean_sh}, 'nCombo', {numel(COMBOS)}, 'N_GEOM', {N_GEOM}, ...
        'RUN_FRAMES', {RUN_FRAMES}, 'RATIO', {RATIO}, 'RELAY_DEG', {RELAY_DEG}, 'RELAY_LOSS_DB', {RELAY_LOSS_DB}, ...
        'floor', {C.ber_floor}, 'SH', {SH});
    [rep, T3, T3s, Lm, okS] = surv3_report(X);
    clear X
    fid = fopen('results/survivability_options.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
    fprintf('\n%s\n', rep{:});
    save('data/survivability_options.mat', 'cases', 'VAR', 'EBNO', 'rec', 'best', 'jobs', 'clean', 'T3', 'N_GEOM', ...
        'RELAY_DEG', 'RELAY_LOSS_DB', 'rec_sys', 'best_sys', 'met', 'T3s', 'Lm', 'okS', 'clean_sh', 'geo', 'geo_sh', ...
        'SH', 'SV', 'iHigh', 'RUN_FRAMES', 'RATIO', 'ACTIONS');
else
    % Report
    rep = {sprintf('=== SURVIVABILITY OPTIONS: %s, %s, RELAY PATH ===', upper(VAR(1).name), upper(VAR(2).name)), ...
        sprintf(['Generated: %s | %d random geometries per (threat, Eb/N0), %d frames each, every configuration | ' ...
        'recoverable = BER and packet loss within %gx of the clean link | relay: signal from %g deg off the GCS ' ...
        'direction, %g dB extra path loss'], datestr(now), N_GEOM, RUN_FRAMES, RATIO, RELAY_DEG, RELAY_LOSS_DB), ''};
    rep{end+1} = sprintf('%-34s%s', 'recoverable geometries [%]', sprintf('%14s', VAR.name));
    T3 = nan(numel(cases), numel(VAR), nS);
    for i = 1:numel(cases)
        v = zeros(1, numel(VAR));
        for k = 1:numel(VAR)
            j = find(jobs(:, 1) == i & jobs(:, 2) == k);
            v(k) = 100 * mean(rec{j}(:));
            T3(i, k, :) = 100 * mean(rec{j}, 2);
        end
        name = cases(i).threat;
        if ~isnan(cases(i).level), name = sprintf('%s (high, %g)', name, cases(i).level); end
        rep{end+1} = sprintf('%-34s%s', name, sprintf('%13.1f%%', v)); %#ok<SAGROW>
    end
    ic = 1:numel(COMBOS);
    rep{end+1} = sprintf('%-34s%s', 'combined threats, mean', sprintf('%13.1f%%', mean(mean(T3(ic, :, :), 3), 1)));
    rep{end+1} = sprintf('%-34s%s', 'single threats (high), mean', sprintf('%13.1f%%', mean(mean(T3(numel(ic)+1:end, :, :), 3), 1)));
    rep{end+1} = '';
    rep{end+1} = sprintf('Per Eb/N0, combined threats pooled [%%] (%s):', strjoin({VAR.name}, ' / '));
    for s = 1:nS
        rep{end+1} = sprintf('  %2g dB  %s', EBNO(s), strjoin(arrayfun(@(k) sprintf('%6.1f', mean(T3(ic, k, s))), ...
            1:numel(VAR), 'UniformOutput', false), ' / ')); %#ok<SAGROW>
    end
    rep{end+1} = sprintf('Clean BER, %s: %s', VAR(1).name, sprintf('%.1e ', clean{1}.ber));
    rep{end+1} = sprintf('Clean BER, %s: %s', VAR(2).name, sprintf('%.1e ', clean{2}.ber));
    fid = fopen('results/survivability_options.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
    fprintf('\n%s\n', rep{:});
    save('data/survivability_options.mat', 'cases', 'VAR', 'EBNO', 'rec', 'best', 'jobs', 'clean', 'T3', 'N_GEOM', ...
        'RELAY_DEG', 'RELAY_LOSS_DB');
end
fprintf('Saved results/survivability_options.txt (%.1f min)\n', toc(t0) / 60);

function v = nth2(f, varargin)
% Second output of f.
[~, v] = f(varargin{:});
end
