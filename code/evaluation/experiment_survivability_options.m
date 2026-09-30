%% EXPERIMENT_SURVIVABILITY_OPTIONS - What a third antenna or an alternate path adds
% Research experiment of deliverable 8. The system flies two UAV antennas (proposal
% item 2), which null one interferer, and only when it arrives from another
% direction than the GCS. Two extensions named in the proposal
% literature are tested on the recoverability question, without changing the system:
%   3 antennas     an N-element array nulls up to N-1 interferers (Shebert et al.)
%   relay path     the command reaches the UAV over a secondary path (Papathanasiou
%                  et al.: secondary communication paths, backup link; the lecturer's
%                  proposal: an alternate route), modeled as the desired signal
%                  arriving RELAY_DEG away from the GCS direction with RELAY_LOSS_DB
%                  of extra path loss; the interferers stay where they are
% Threats where the extensions can matter: the eight combined threats (nominal
% severity) and the directional single threats at high severity. Each (threat,
% Eb/N0) is simulated on N_GEOM random flight geometries (interferer directions
% uniform, as in the pools) under every configuration. A geometry is recoverable
% when some configuration brings BER and packet loss within 2x (+ one packet) of
% the clean link: the receiver's own clean link for 2 and 3 antennas, and the
% direct two-antenna link for the relay (the service the relay must give back).
%
% Output: results/survivability_options.txt, data/survivability_options.mat

close all; clc;
fprintf('=== Survivability options: 2 antennas, 3 antennas, relay path (D59) ===\n\n');
N_GEOM = 8; RUN_FRAMES = 20; N_WORKERS = 6; RATIO = 2;
RELAY_DEG = 60; RELAY_LOSS_DB = 3;
opt = struct('F_SUB', RUN_FRAMES, 'tw', 10, 'delay_bits', 20);
C = decision_config();
evalc('init_params');
p0 = load('params.mat').params; p0.quiet_build = true; p0.int_aoa_random = true;
EBNO = p0.EbNo_dB; nS = numel(EBNO);
ACTIONS = policy_actions();
vrange = [p0.speed_kmh_min p0.speed_kmh_max];
COMBOS = {'jamming+path_loss', 'noise_burst+antenna_fault', 'sweeping_jammer+path_loss', 'spoofing+noise_burst', ...
          'reactive_jamming+path_loss', 'jamming+antenna_fault', 'spoofing+sweeping_jammer', 'benign_interference+noise_burst'};
SINGLES = {'jamming', 'reactive_jamming', 'noise_burst', 'spoofing', 'sweeping_jammer'};
cases = [cellfun(@(t) struct('threat', t, 'field', '', 'level', NaN), COMBOS), ...
         cellfun(@(t) struct('threat', t, 'field', C.sev.(t).field, 'level', C.sev.(t).levels(3)), SINGLES)];
VAR = struct('name', {'2 antennas', '3 antennas', 'relay path'}, 'n_rx', {2, 3, 2}, ...
    'gcs', {0, 0, RELAY_DEG}, 'loss', {0, 0, RELAY_LOSS_DB}, 'ref', {1, 2, 1});
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    cases = cases([1 end]); N_GEOM = 2; COMBOS = COMBOS(1);
end
geo = arrayfun(@(s) struct('seed', arrayfun(@(r) pool_seed(1, s, 6, r), 1:N_GEOM), ...
    'speed', arrayfun(@(r) nth2(@pool_seed, 1, s, 6, r, vrange), 1:N_GEOM), 'run', 600 + (1:N_GEOM)), ...
    1:nS, 'UniformOutput', false);

pl = gcp('nocreate');
if isempty(pl) || pl.NumWorkers ~= N_WORKERS
    delete(pl); pl = parpool('Processes', N_WORKERS);
end
repo = pwd;
spmd
    pool_worker_init(repo);
end
t0 = tic;

% Clean references of the two receivers (direct link, same geometries)
clean = cell(1, 2);
parfor k = 1:2
    p = p0; p.n_rx = VAR(k).n_rx; p.active_threat = 'none';
    P = pool_cell(p, 'none', {'no_action'}, EBNO, geo, [], opt);
    clean{k} = struct('ber', cellfun(@(Q) mean(Q.ber), P(:, 1, 1))', 'fer', cellfun(@(Q) mean(double(Q.fer)), P(:, 1, 1))');
end

% Every case x option
jobs = [kron((1:numel(cases))', ones(numel(VAR), 1)), repmat((1:numel(VAR))', numel(cases), 1)];
nJ = size(jobs, 1);
rec = cell(1, nJ); best = cell(1, nJ);
parfor j = 1:nJ
    c = cases(jobs(j, 1)); v = VAR(jobs(j, 2));
    p = p0; p.n_rx = v.n_rx; p.gcs_aoa_deg = v.gcs; p.link_loss_db = v.loss; p.active_threat = c.threat;
    if ~isempty(c.field), p.(c.field) = c.level; end
    P = pool_cell(p, c.threat, ACTIONS, EBNO, geo, [], opt);
    R = false(nS, N_GEOM); Bc = cell(nS, N_GEOM);
    for s = 1:nS
        bc = max(clean{v.ref}.ber(s), C.ber_floor); fc = clean{v.ref}.fer(s);
        for r = 1:N_GEOM
            rid = 600 + r; okc = false(1, numel(ACTIONS));
            for a = 1:numel(ACTIONS)
                Q = P{s, a, 1}; m = Q.run == rid;
                okc(a) = mean(Q.ber(m)) <= RATIO * bc && mean(double(Q.fer(m))) <= RATIO * fc + 1 / max(sum(m), 1);
            end
            R(s, r) = any(okc);
            if any(okc), Bc{s, r} = ACTIONS{find(okc, 1)}; end
        end
    end
    rec{j} = R; best{j} = Bc;
end

% Report
rep = {'=== SURVIVABILITY OPTIONS: 2 ANTENNAS, 3 ANTENNAS, RELAY PATH (D59) ===', ...
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
rep{end+1} = sprintf('Clean BER, 2 antennas: %s', sprintf('%.1e ', clean{1}.ber));
rep{end+1} = sprintf('Clean BER, 3 antennas: %s', sprintf('%.1e ', clean{2}.ber));
fid = fopen('results/survivability_options.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
save('data/survivability_options.mat', 'cases', 'VAR', 'EBNO', 'rec', 'best', 'jobs', 'clean', 'T3', 'N_GEOM', ...
    'RELAY_DEG', 'RELAY_LOSS_DB');
fprintf('Saved results/survivability_options.txt (%.1f min)\n', toc(t0) / 60);

function v = nth2(f, varargin)
% Second output of f.
[~, v] = f(varargin{:});
end
