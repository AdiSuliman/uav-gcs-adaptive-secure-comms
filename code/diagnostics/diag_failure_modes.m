%% DIAG_FAILURE_MODES - Where and why the selected DQN fails, VALIDATION split only
% Every threat cell x Eb/N0 x geometry of the validation split, twice, in three
% jammer modes: static (no follower), follower (re-acquires the channel 2-5 cycles
% after each hop, as in training) and immediate follower (fdelay 0, the comb set of
% Liu et al.; followable threats only). Recovery among the recoverable episodes per
% threat and mode for the DQN, the DQN with escalation and rule + escalation.
% Each failed recoverable DQN episode is attributed to the first mechanism that
% applies:
%   never acted    no configuration change after onset (no confirmed alarm)
%   released       went back to no_action after acting, while the threat was on
%   channel-bound  follower on, and the configuration held most after onset
%                  contains channel_switch and does not restore without the hop
%   other          held configurations that do not restore
%
% AGENT_FILE (optional, set before running): the agent to diagnose; default
% data/trained_dqn.mat.
%
% Output: results/diag_failure_modes.txt

close all; clc;
if ~exist('AGENT_FILE', 'var'), AGENT_FILE = 'data/trained_dqn.mat'; end
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
Q = load(AGENT_FILE, 'agent', 'H', 'confirm', 'alarm_mode', 'drop_db');
PP.confirm = Q.confirm; PP.alarm_mode = Q.alarm_mode; PP.drop_db = Q.drop_db;
K = link_env('tables', PP);
VAL = 2; REPS = 2; H = Q.H;
MODES = {'static', 'follower', 'immediate'};
POL = {'dqn', 'dqn_esc', 'rule_esc'};
cells = find(~cellfun(@isempty, PP.pools(:, 1, K.na, VAL))');
cells = cells(~strcmp(PP.scen(cells), 'none'));
rep = {sprintf(['=== FAILURE MODES ON THE VALIDATION SPLIT (%s: %s %d/%d, drop %.1f dB) ===\n' ...
    'recovered among recoverable episodes, %%; DQN failures by mechanism, %% of the failed episodes'], ...
    AGENT_FILE, Q.alarm_mode, Q.confirm(1:2), Q.drop_db)};
rep{end+1} = sprintf('%-40s %-10s %5s %7s %8s %9s | %6s %6s %8s %6s', 'threat', 'mode', 'n', 'DQN', 'DQN+esc', 'rule+esc', ...
    'never', 'releas', 'channel', 'other');
T = struct('thr', {}, 'mode', {}, 'n', {}, 'rec', {}, 'why', {}, 'rel_any', {}, 'rec_rel', {}, 'rec_norel', {});
for m = 1:numel(MODES)
    cm = cells;
    if m > 1, cm = cells(K.followable(cells)); end
    specs = mode_specs(cm, PP, K, H, VAL, REPS, m, RandStream('mt19937ar', 'Seed', 99 + m));
    S = [specs{:}];
    scn = [S.scn]; s = [S.s]; r = [S.r]; onset = [S.onset]; fol = [S.follow];
    out = struct();
    for p = 1:numel(POL)
        rec = []; ok = []; tr = [];
        for b = 1:numel(specs)
            R = rollout_policy(POL{p}, PP, K, specs{b}, VAL, Q.agent, struct(), 5000 + b);
            rec = [rec, R.recovered]; ok = [ok, R.recoverable]; tr = [tr, R.cfg_trace]; %#ok<AGROW>
        end
        out.(POL{p}) = struct('rec', rec, 'ok', ok, 'tr', tr);
    end
    [why, rel] = mechanism(out.dqn, K, scn, s, r, onset, fol, VAL);
    names = unique(PP.scen(scn), 'stable');
    for i = 0:numel(names)
        if i == 0, g = true(size(scn)); nm = 'all'; else, g = strcmp(PP.scen(scn), names{i}); nm = names{i}; end
        g = g & out.dqn.ok;
        f = g & ~out.dqn.rec;
        w = arrayfun(@(k) 100 * sum(why(f) == k) / max(sum(f), 1), 1:4);
        rr = cellfun(@(pp) 100 * mean(out.(pp).rec(g & out.(pp).ok)), POL);
        rep{end+1} = sprintf('%-40s %-10s %5d %6.1f%% %7.1f%% %8.1f%% | %5.0f%% %5.0f%% %7.0f%% %5.0f%%', nm, MODES{m}, ...
            sum(g), rr, w); %#ok<SAGROW>
        T(end+1) = struct('thr', nm, 'mode', MODES{m}, 'n', sum(g), 'rec', rr, 'why', w, 'rel_any', 100 * mean(rel(g)), ...
            'rec_rel', 100 * mean(out.dqn.rec(g & rel)), 'rec_norel', 100 * mean(out.dqn.rec(g & ~rel))); %#ok<SAGROW>
    end
    rep{end+1} = ''; %#ok<SAGROW>
end
rep{end+1} = 'DQN episodes with a release to no_action while the threat was on (recoverable episodes):';
for k = find(strcmp({T.thr}, 'all'))
    rep{end+1} = sprintf('  %-10s released in %4.1f%% of the episodes; recovered %5.1f%% of those vs %5.1f%% without a release', ...
        T(k).mode, T(k).rel_any, T(k).rec_rel, T(k).rec_norel); %#ok<SAGROW>
end
fid = fopen('results/diag_failure_modes.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
save('results/diag_failure_modes.mat', 'T');

%% ===================== Local functions =====================
function specs = mode_specs(cells, PP, K, H, split, reps, m, rs)
% Every (cell, Eb/N0, geometry) of the split `reps` times in one jammer mode.
[c, s, r] = ndgrid(cells, 1:numel(PP.ebno), 1:K.nR(split));
c = repmat(c(:)', 1, reps); s = repmat(s(:)', 1, reps); r = repmat(r(:)', 1, reps);
n = numel(c); nb = ceil(n / H.NE);
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*H.NE + 1:min(b*H.NE, n); q = numel(i);
    fd = randi(rs, [2 5], 1, q);
    if m == 3, fd = zeros(1, q); end
    specs{b} = struct('scn', c(i), 's', s(i), 'r', r(i), 'onset', randi(rs, [3 10], 1, q), ...
        'follow', repmat(m > 1, 1, q), 'fdelay', fd, 'unk', false(1, q), 'T', H.T);
end
end

function [why, rel] = mechanism(D, K, scn, s, r, onset, fol, split)
% Failure mechanism of every episode (1 never acted, 2 released, 3 channel-bound,
% 4 other) and whether the policy released to no_action after acting post onset.
[T, NE] = size(D.tr);
tr = [K.na * ones(1, NE); D.tr];                 % row t+1 = configuration after cycle t
why = zeros(1, NE); rel = false(1, NE);
for i = 1:NE
    post = tr(onset(i)+1:end, i);
    acted = find(post ~= K.na, 1);
    if ~isempty(acted), rel(i) = any(post(acted:end) == K.na); end
    if isempty(acted), why(i) = 1; continue; end
    if rel(i), why(i) = 2; continue; end
    held = mode(post(acted:end));
    if fol(i) && K.hasCh(held)
        j = sub2ind(size(K.q), scn(i), s(i), K.strip(held), split, r(i));
        if ~(K.restored(j) && K.restored_plr(j)), why(i) = 3; continue; end
    end
    why(i) = 4;
end
end
