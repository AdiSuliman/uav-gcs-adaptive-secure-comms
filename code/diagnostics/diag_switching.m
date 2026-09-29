%% DIAG_SWITCHING - How often each policy changes configuration, VALIDATION split only
% The selected DQN and rule + escalation on every (threat cell, Eb/N0, geometry)
% of the validation split, twice (as train_dqn.m validates). Per threat:
%   changes per episode
%   quick: share of changes made within C.hold cycles of the previous change
%          (the rule and table policies cannot do this, policy_decide.m)
%   ping-pong: episodes that leave a configuration and return to it within
%          C.hold cycles (A -> B -> A)
%   recovered: share of the recoverable episodes recovered (KPI 4 statistic)
%
% AGENT_FILE (optional, set before running): the agent to diagnose; default
% data/trained_dqn.mat.
%
% Output: results/diag_switching.txt

close all; clc;
if ~exist('AGENT_FILE', 'var'), AGENT_FILE = 'data/trained_dqn.mat'; end
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
Q = load(AGENT_FILE, 'agent', 'H', 'confirm', 'alarm_mode', 'drop_db');
PP.confirm = Q.confirm; PP.alarm_mode = Q.alarm_mode; PP.drop_db = Q.drop_db;
K = link_env('tables', PP);
C = decision_config();
VAL = 2; REPS = 2; H = Q.H;
specs = val_specs(PP, K, H, VAL, REPS, RandStream('mt19937ar', 'Seed', 99));
thr = PP.scen(cell2mat(cellfun(@(sp) sp.scn, specs, 'UniformOutput', false)));
names = unique(thr, 'stable');
POL = {'dqn', 'rule_esc'};
rep = {sprintf(['=== CONFIGURATION CHANGES ON THE VALIDATION SPLIT (%s: alarm ''%s'' %d/%d, drop %.1f dB) ===\n' ...
    'quick = change within %d cycles of the previous one; ping-pong = A -> B -> A with B held <= %d cycles'], ...
    AGENT_FILE, Q.alarm_mode, Q.confirm, Q.drop_db, C.hold, C.hold)};

for p = 1:numel(POL)
    sw = []; qk = []; pg = []; rec = []; ok = [];
    for b = 1:numel(specs)
        R = rollout_policy(POL{p}, PP, K, specs{b}, VAL, Q.agent, struct(), 5000 + b);
        [q, g] = change_pattern(R.cfg_trace, K.na, C.hold);
        sw = [sw, R.switches]; qk = [qk, q]; pg = [pg, g]; %#ok<AGROW>
        rec = [rec, R.recovered]; ok = [ok, R.recoverable]; %#ok<AGROW>
    end
    rep{end+1} = sprintf('\n--- %s ---', POL{p}); %#ok<SAGROW>
    rep{end+1} = sprintf('%-45s %6s %9s %8s %10s %10s', 'threat', 'n', 'changes', 'quick', 'ping-pong', 'recovered'); %#ok<SAGROW>
    for i = 0:numel(names)
        if i == 0, m = true(size(thr)); nm = 'all';
        else, m = strcmp(thr, names{i}); nm = names{i}; end
        mr = m & ok;
        rep{end+1} = sprintf('%-45s %6d %9.2f %7.1f%% %9.1f%% %9.1f%%', nm, sum(m), mean(sw(m)), ...
            100 * sum(qk(m)) / max(sum(sw(m)), 1), 100 * mean(pg(m)), 100 * mean(rec(mr))); %#ok<SAGROW>
    end
end
fid = fopen('results/diag_switching.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});

%% ===================== Local functions =====================
function [quick, pingpong] = change_pattern(tr, na, hold)
% Per episode: number of changes within `hold` cycles of the previous change, and
% whether a configuration was left and re-entered within `hold` cycles.
[T, NE] = size(tr);
tr = [na * ones(1, NE); tr];                     % every episode starts at no_action
quick = zeros(1, NE); pingpong = false(1, NE);
for i = 1:NE
    t = find(diff(tr(:, i)) ~= 0)';              % change cycles
    quick(i) = sum(diff(t) <= hold);
    for k = 2:numel(t)
        if t(k) - t(k-1) <= hold && tr(t(k) + 1, i) == tr(t(k-1), i), pingpong(i) = true; end
    end
end
end

function specs = val_specs(PP, K, H, split, reps, rs)
% Every (cell, Eb/N0, geometry) of the split `reps` times (as train_dqn.m).
cells = find(~cellfun(@isempty, PP.pools(:, 1, K.na, split))');
[c, s, r] = ndgrid(cells, 1:numel(PP.ebno), 1:K.nR(split));
c = repmat(c(:)', 1, reps); s = repmat(s(:)', 1, reps); r = repmat(r(:)', 1, reps);
n = numel(c); nb = ceil(n / H.NE);
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*H.NE + 1:min(b*H.NE, n); m = numel(i);
    specs{b} = struct('scn', c(i), 's', s(i), 'r', r(i), 'onset', randi(rs, [3 10], 1, m), ...
        'follow', K.followable(c(i)) & rand(rs, 1, m) < H.p_follow, 'fdelay', randi(rs, [2 5], 1, m), ...
        'unk', false(1, m), 'T', H.T);
end
end
