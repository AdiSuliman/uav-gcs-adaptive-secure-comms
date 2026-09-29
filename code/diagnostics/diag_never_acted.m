%% DIAG_NEVER_ACTED - Missed alarm or agent choice? VALIDATION split only
% For path_loss and antenna_fault (static jammer mode, every cell x Eb/N0 x
% geometry of the validation split, twice), the selected DQN's episodes that never
% changed configuration after onset are replayed with the configuration held at
% no_action (identical frame draws: same seed, same configuration). Per episode:
% whether any post-onset cycle carried a CONFIRMED alarm, the alarm and
% degradation rates, the detected class, and the Eb/N0 drop the monitor saw.
% Confirmed but never acted = the agent chose no_action; never confirmed = the
% monitor missed the threat. The same replay on the independent clean validation
% geometries gives the monitor's false-alarm reference.
%
% Output: results/diag_never_acted.txt

close all; clc;
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
Q = load('data/trained_dqn.mat', 'agent', 'H', 'confirm', 'alarm_mode', 'drop_db');
PP.confirm = Q.confirm; PP.alarm_mode = Q.alarm_mode; PP.drop_db = Q.drop_db;
K = link_env('tables', PP);
VAL = 2; REPS = 2; H = Q.H;
rep = {sprintf('=== NEVER-ACTED EPISODES OF THE SELECTED DQN, VALIDATION (%s %d/%d, drop %.1f dB) ===', ...
    Q.alarm_mode, Q.confirm(1:2), Q.drop_db)};
for th = {'path_loss', 'antenna_fault'}
    cells = find(strcmp(PP.scen, th{1}));
    specs = static_specs(cells, PP, K, H, VAL, REPS, RandStream('mt19937ar', 'Seed', 100));
    for c = cells(:)'
        nv = 0; conf = 0; al = []; dg = []; dr = []; cl = {}; nrec = 0; nrec_fail = 0;
        for b = 1:numel(specs)
            sp = specs{b};
            R = rollout_policy('dqn', PP, K, sp, VAL, Q.agent, struct(), 5000 + b);
            M = replay_fixed(PP, K, sp, VAL, 5000 + b);            % no_action throughout
            for i = find(sp.scn == c & R.recoverable)
                nrec = nrec + 1;
                post = sp.onset(i):sp.T;
                if all(R.cfg_trace(post, i) == K.na)
                    nv = nv + 1; nrec_fail = nrec_fail + ~R.recovered(i);
                    conf = conf + any(M.confirmed(post, i));
                    al = [al, mean(M.alarm(post, i))]; dg = [dg, mean(M.degraded(post, i))]; %#ok<AGROW>
                    dr = [dr, median(M.drop(post, i), 'omitnan')]; %#ok<AGROW>
                    cl = [cl, M.cls(post, i)']; %#ok<AGROW>
                end
            end
        end
        [u, ~, j] = unique(cl); cnt = accumarray(j(:), 1); [cnt, o] = sort(cnt, 'descend');
        top = strjoin(arrayfun(@(k) sprintf('%s %.0f%%', u{o(k)}, 100 * cnt(k) / sum(cnt)), 1:min(3, numel(cnt)), ...
            'UniformOutput', false), ', ');
        rep{end+1} = sprintf(['%-14s %-8s (%4.1f): %3d recoverable, never acted %3d (%2d of them unrecovered) | ' ...
            'alarm confirmed in %3d of the %d | alarm %4.1f%% degraded %4.1f%% of cycles | drop median %4.1f dB | detected %s'], ...
            th{1}, PP.sev_names{PP.sev(c)}, PP.level(c), nrec, nv, nrec_fail, conf, nv, 100 * mean(al), 100 * mean(dg), ...
            median(dr, 'omitnan'), top); %#ok<SAGROW>
    end
end
fid = fopen('results/diag_never_acted.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});

%% ===================== Local functions =====================
function specs = static_specs(cells, PP, K, H, split, reps, rs)
[c, s, r] = ndgrid(cells, 1:numel(PP.ebno), 1:K.nR(split));
c = repmat(c(:)', 1, reps); s = repmat(s(:)', 1, reps); r = repmat(r(:)', 1, reps);
n = numel(c); nb = ceil(n / H.NE);
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*H.NE + 1:min(b*H.NE, n); q = numel(i);
    specs{b} = struct('scn', c(i), 's', s(i), 'r', r(i), 'onset', randi(rs, [3 10], 1, q), ...
        'follow', false(1, q), 'fdelay', 2 * ones(1, q), 'unk', false(1, q), 'T', H.T);
end
end

function M = replay_fixed(PP, K, spec, split, seed)
% The rollout of rollout_policy.m with the configuration held at no_action,
% keeping the monitor output of every cycle (same random streams, same draws).
rs = RandStream('mt19937ar', 'Seed', seed);
opt.rs = RandStream('mt19937ar', 'Seed', seed + 1); opt.fixed = K.na;
[E, obs] = link_env('reset', PP, K, spec, split, rs);
T = spec.T; NE = E.NE; mem = [];
M = struct('confirmed', false(T, NE), 'alarm', false(T, NE), 'degraded', false(T, NE), 'drop', nan(T, NE), ...
    'cls', {cell(T, NE)});
for t = 1:T
    [a, mem, d] = policy_decide('fixed', obs, E.cfg, mem, PP, [], opt);
    M.confirmed(t, :) = d.confirmed; M.degraded(t, :) = d.degraded; M.drop(t, :) = d.drop;
    M.alarm(t, :) = mem.alarm(:, end)'; M.cls(t, :) = d.cls;
    [E, ~, obs] = link_env('step', E, PP, K, a);
end
end
