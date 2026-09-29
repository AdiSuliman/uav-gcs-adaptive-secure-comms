%% DIAG_PATH_LOSS - Why the selected DQN misses path loss, on the VALIDATION split only
% For path_loss at each severity: share of recoverable episodes recovered, share
% where the policy never changed configuration, and the Eb/N0 drop the monitor
% saw at the first change. Then the same with other drop thresholds of the
% path_loss alarm (the agent is the one trained at the selected threshold, so
% this only shows the sensitivity), with the false alarms on the independent
% clean validation geometries for each threshold.
%
% Output: results/diag_path_loss.txt

close all; clc;
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
Q = load('data/trained_dqn.mat', 'agent', 'H', 'confirm', 'alarm_mode', 'drop_db');
Cv = load('data/clean_val_pools.mat', 'CT'); CV = Cv.CT; clear Cv
PP.confirm = Q.confirm; PP.alarm_mode = Q.alarm_mode;
K = link_env('tables', PP);
VAL = 2; NE = 64; T = Q.H.T; REPS = 4;
nS = numel(PP.ebno); nG = K.nR(VAL);
cells = find(strcmp(PP.scen, 'path_loss'));
rep = {sprintf('=== PATH LOSS ON THE VALIDATION SPLIT (selected DQN, trained with drop %.1f dB) ===', Q.drop_db)};
for dd = [Q.drop_db, 4, 3]
    PPd = PP; PPd.drop_db = dd;
    rep{end+1} = sprintf('--- drop threshold %.1f dB ---', dd); %#ok<SAGROW>
    for c = cells(:)'
        specs = val_specs(c, nS, nG, REPS, NE, T, RandStream('mt19937ar', 'Seed', 77));
        R = dqn_eval_batches('dqn', PPd, K, specs, Q.agent, struct(), 5100, VAL);
        R.s = cell2mat(cellfun(@(sp) sp.s, specs, 'UniformOutput', false));
        m = R.recoverable;
        never = m & R.switches == 0;
        rep{end+1} = sprintf('  %-8s (%2d dB): recovered %5.1f%% of %d recoverable | never acted %5.1f%% | first-change drop median %.1f dB', ...
            PP.sev_names{PP.sev(c)}, PP.level(c), 100 * mean(R.recovered(m)), sum(m), 100 * mean(never(m)), ...
            median(R.fc_drop(m & R.switches > 0), 'omitnan')); %#ok<SAGROW>
        if dd == Q.drop_db
            for s = 1:nS
                ms = m & R.s == s;
                rep{end+1} = sprintf('      Eb/N0 %2d dB: recovered %5.1f%%, never acted %5.1f%% (%d)', PP.ebno(s), ...
                    100 * mean(R.recovered(ms)), 100 * mean(never(ms)), sum(ms)); %#ok<SAGROW>
            end
        end
    end
    [fa, n] = clean_fa(PPd, CV, Q.agent, NE, T);
    rep{end+1} = sprintf('  false alarms, independent clean validation geometries: %d/%d (%.2f%%)', round(fa * n), n, 100 * fa); %#ok<SAGROW>
end
fid = fopen('results/diag_path_loss.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});

function specs = val_specs(c, nS, nG, reps, NE, T, rs)
[s, r] = ndgrid(1:nS, 1:nG); s = repmat(s(:)', 1, reps); r = repmat(r(:)', 1, reps);
n = numel(s); nb = ceil(n / NE); pad = nb * NE - n;
k_ = mod(0:n + pad - 1, n) + 1; s = s(k_); r = r(k_);
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*NE + (1:NE);
    specs{b} = struct('scn', c * ones(1, NE), 's', s(i), 'r', r(i), 'onset', randi(rs, [3 10], 1, NE), ...
        'follow', false(1, NE), 'fdelay', 2 * ones(1, NE), 'unk', false(1, NE), 'T', T);
end
end

function [fa, n] = clean_fa(PP, CT, agent, NE, T)
% One clean episode per independent validation geometry and Eb/N0 (as train_dqn.m).
nS = numel(PP.ebno); nA = numel(PP.actions);
PPw = PP; PPw.pools(:, :, :, 2) = {[]};
ic = find(strcmp(PP.scen, 'none'), 1);
PPw.pools(ic, :, :, 2) = reshape(CT.pools(1, :, :), [1 nS nA]);
PPw.runs{2} = CT.runs;
Kw = link_env('tables', PPw);
[ss, rr] = ndgrid(1:nS, 1:CT.n_geom); ss = ss(:)'; rr = rr(:)';
n = numel(ss); nb = ceil(n / NE); pad = nb * NE - n;
k_ = mod(0:n + pad - 1, n) + 1; ss = ss(k_); rr = rr(k_);
sw = [];
for b = 1:nb
    i = (b-1)*NE + (1:NE);
    spec = struct('scn', Kw.clean * ones(1, NE), 's', ss(i), 'onset', 3 * ones(1, NE), 'follow', false(1, NE), ...
        'fdelay', 2 * ones(1, NE), 'unk', false(1, NE), 'T', T, 'r', rr(i));
    Rb = rollout_policy('dqn', PPw, Kw, spec, 2, agent, struct(), 41000 + b);
    sw = [sw, Rb.switches]; %#ok<AGROW>
end
fa = mean(sw(1:n) > 0);
end
