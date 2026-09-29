%% DIAG_FALSE_ALARMS - Clean-link false alarms and the confirmation rule, VALIDATION split only
% Part 1, monitor only (configuration held at no_action):
%   clean validation geometries: episodes with a confirmed alarm under m-of-m
%   confirmation, and what raised it (path_loss class with an Eb/N0 drop, another
%   hostile class, degradation alone);
%   threat episodes of the validation split: share confirmed after onset and the
%   delay from onset to the first confirmation, per threat.
% Part 2, deployed policy (DQN + escalation) under each confirmation rule, agents
% as trained (not retrained): recovery and weakest threat on the validation
% episodes of train_dqn.m, false alarms on the clean validation geometries, and
% what the monitor showed at each false switch.
%
% AGENT_FILES (optional, set before running): agents for part 2; default the
% deployed agent.
%
% Output: results/diag_false_alarms.txt

close all; clc;
if ~exist('AGENT_FILES', 'var'), AGENT_FILES = {'data/trained_dqn.mat'}; end
CONFIRMS = {[3 3], [4 4], [5 5]};
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
Cv = load('data/clean_val_pools.mat', 'CT'); CV = Cv.CT; clear Cv
Q0 = load(AGENT_FILES{1}, 'H', 'alarm_mode', 'drop_db');
H = Q0.H; PP.alarm_mode = Q0.alarm_mode; PP.drop_db = Q0.drop_db;
K = link_env('tables', PP);
VAL = 2; nS = numel(PP.ebno);
rep = {sprintf('=== CLEAN-LINK FALSE ALARMS AND CONFIRMATION, VALIDATION SPLIT (%s, drop %.1f dB) ===', ...
    PP.alarm_mode, PP.drop_db)};

%% Part 1a. Monitor on the clean validation geometries
[PPw, Kw] = clean_world(PP, CV);
[ss, rr] = ndgrid(1:nS, 1:CV.n_geom); ss = ss(:)'; rr = rr(:)'; n = numel(ss);
Mc = replay_batches(PPw, Kw, clean_specs(Kw, ss, rr, H), VAL, 41000);
Mc = cut(Mc, n);
rep{end+1} = sprintf('\nPart 1a. Monitor only, %d clean validation episodes (%d cycles each):', n, H.T);
rep{end+1} = sprintf('  raw alarm in %.1f%% of the cycles: path_loss class %.1f%%, other hostile class %.1f%%, degradation alone %.1f%%', ...
    100 * mean(Mc.alarm(:)), 100 * mean(Mc.src(:) == 1), 100 * mean(Mc.src(:) == 2), 100 * mean(Mc.src(:) == 3));
rep{end+1} = sprintf('  %-6s %22s | first confirmed alarm raised by: %s', 'rule', 'episodes confirmed', ...
    'path_loss class / other class / degradation alone');
for k = 1:numel(CONFIRMS)
    m = CONFIRMS{k}(1);
    [fc, src] = first_confirm(Mc, m, 1);
    hit = ~isnan(fc);
    rep{end+1} = sprintf('  %d/%d    %5.1f%% (%3d of %d) | %3d / %3d / %3d', m, m, 100 * mean(hit), sum(hit), n, ...
        sum(src(hit) == 1), sum(src(hit) == 2), sum(src(hit) == 3)); %#ok<SAGROW>
end
pl = Mc.src == 1;
rep{end+1} = sprintf('  Eb/N0 drop in the path_loss-class alarm cycles: median %.1f dB, 90th percentile %.1f dB', ...
    median(Mc.drop(pl), 'omitnan'), prctile(Mc.drop(pl), 90));

%% Part 1b. Monitor on the threat episodes of the validation split
val_spec = full_val_spec(PP, K, H, VAL, 1, RandStream('mt19937ar', 'Seed', 99));
S = [val_spec{:}]; scn = [S.scn]; onset = [S.onset];
thr = PP.scen(scn);
Mt = replay_batches(PP, K, cellfun(@(sp) setfield(sp, 'follow', false(size(sp.scn))), val_spec, 'UniformOutput', false), ...
    VAL, 5000); %#ok<SFLD>
isT = ~strcmp(thr, 'none');
names = unique(thr(isT), 'stable');
rep{end+1} = sprintf('\nPart 1b. Monitor only, %d threat episodes of the validation split (no follower):', sum(isT));
rep{end+1} = sprintf('  %-40s %s', 'threat', strjoin(cellfun(@(c) sprintf('%d/%d: confirmed, median delay', c(1), c(1)), ...
    CONFIRMS, 'UniformOutput', false), ' | '));
D = cell(1, numel(CONFIRMS));
for k = 1:numel(CONFIRMS), D{k} = first_confirm(Mt, CONFIRMS{k}(1), onset); end
for i = 0:numel(names)
    if i == 0, g = isT; nm = 'all threats'; else, g = strcmp(thr, names{i}); nm = names{i}; end
    cells_txt = cellfun(@(d) sprintf('%5.1f%%, %3.1f cycles', 100 * mean(~isnan(d(g))), median(d(g) - onset(g), 'omitnan')), ...
        D, 'UniformOutput', false);
    rep{end+1} = sprintf('  %-40s %s', nm, strjoin(cells_txt, '          | ')); %#ok<SAGROW>
end

%% Part 2. Deployed policy under each confirmation rule (agents not retrained)
val2 = full_val_spec(PP, K, H, VAL, 2, RandStream('mt19937ar', 'Seed', 99));
thr2 = PP.scen(cell2mat(cellfun(@(sp) sp.scn, val2, 'UniformOutput', false)));
rep{end+1} = sprintf('\nPart 2. DQN + escalation, agents as trained; validation episodes of train_dqn.m, %d clean geometries:', n);
rep{end+1} = sprintf('  %-34s %-5s %9s %30s %8s | first false switch: path_loss class / other class / degradation alone', ...
    'agent', 'rule', 'recovered', 'weakest threat', 'FA');
for a = 1:numel(AGENT_FILES)
    Q = load(AGENT_FILES{a}, 'agent');
    for k = 1:numel(CONFIRMS)
        PPc = PP; PPc.confirm = CONFIRMS{k};
        V = dqn_eval_batches('dqn_esc', PPc, K, val2, Q.agent, struct(), 5000, VAL);
        [kmin, kthr] = weakest_threat(V, thr2);
        [PPcw, Kcw] = clean_world(PPc, CV);
        R = [];
        specs = clean_specs(Kcw, ss, rr, H);
        for b = 1:numel(specs)
            Rb = rollout_policy('dqn_esc', PPcw, Kcw, specs{b}, VAL, Q.agent, struct(), 41000 + b);
            Rb = rmfield(Rb, 'cfg_trace');
            if isempty(R), R = Rb; else, R = cat_fields(R, Rb); end
        end
        R = cut(R, n);
        f = R.switches > 0;
        pl_cls = find(strcmp(PP.classes, 'path_loss'));
        hostile_cls = find(~ismember(PP.classes, {'none', 'benign_interference'}));
        s1 = sum(f & R.fc_cls == pl_cls & R.fc_drop >= PP.drop_db);
        s2 = sum(f & ismember(R.fc_cls, hostile_cls) & R.fc_cls ~= pl_cls);
        s3 = sum(f) - s1 - s2;
        rep{end+1} = sprintf('  %-34s %d/%d   %8.1f%% %22s %5.1f%% %4d/%d | %3d / %3d / %3d', AGENT_FILES{a}, ...
            CONFIRMS{k}(1), CONFIRMS{k}(1), 100 * dqn_recovered(V), kthr, 100 * kmin, sum(f), n, s1, s2, s3); %#ok<SAGROW>
    end
end
rep{end+1} = sprintf('\nFalse-alarm bound (one-sided 95%%, <= 5%%): at most 20 of %d.', n);
fid = fopen('results/diag_false_alarms.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});

%% ===================== Local functions =====================
function M = replay_batches(PP, K, specs, split, seed0)
% No-action replay of every batch (the random streams of rollout_policy.m):
% per cycle and episode the raw alarm, its source, the Eb/N0 drop.
M = struct('alarm', [], 'src', [], 'drop', []);
na = K.na; dd = PP.drop_db;
for b = 1:numel(specs)
    spec = specs{b}; T = spec.T;
    rs = RandStream('mt19937ar', 'Seed', seed0 + b);
    opt.rs = RandStream('mt19937ar', 'Seed', seed0 + b + 1); opt.fixed = na;
    [E, obs] = link_env('reset', PP, K, spec, split, rs);
    mem = []; NE = E.NE;
    al = false(T, NE); src = zeros(T, NE); dr = nan(T, NE);
    for t = 1:T
        [a, mem, d] = policy_decide('fixed', obs, E.cfg, mem, PP, [], opt);
        al(t, :) = mem.alarm(:, end)';
        pl = strcmp(d.cls, 'path_loss');
        hostile = ~ismember(d.cls, {'none', 'benign_interference', 'unknown'}) & ~(pl & d.drop < dd);
        src(t, al(t, :) & hostile & pl) = 1;
        src(t, al(t, :) & hostile & ~pl) = 2;
        src(t, al(t, :) & ~hostile) = 3;
        dr(t, :) = d.drop;
        [E, ~, obs] = link_env('step', E, PP, K, a);
    end
    M.alarm = [M.alarm, al]; M.src = [M.src, src]; M.drop = [M.drop, dr];
end
end

function [fc, src] = first_confirm(M, m, t0)
% First cycle >= t0 at which the last m raw alarms were all on (m-of-m), and the
% source of that window: path_loss class if any, else another class, else degradation.
[T, n] = size(M.alarm);
if isscalar(t0), t0 = t0 * ones(1, n); end
fc = nan(1, n); src = zeros(1, n);
for e = 1:n
    for t = max(m, t0(e)):T
        w = t-m+1:t;
        if all(M.alarm(w, e))
            fc(e) = t;
            s = M.src(w, e);
            if any(s == 1), src(e) = 1; elseif any(s == 2), src(e) = 2; else, src(e) = 3; end
            break
        end
    end
end
end

function specs = clean_specs(Kw, ss, rr, H)
% One clean episode per geometry and Eb/N0 in batches of H.NE (as train_dqn.m).
n = numel(ss); NE = H.NE; nb = ceil(n / NE); pad = nb * NE - n;
k_ = mod(0:n + pad - 1, n) + 1; ss = ss(k_); rr = rr(k_);
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*NE + (1:NE);
    specs{b} = struct('scn', Kw.clean * ones(1, NE), 's', ss(i), 'onset', 3 * ones(1, NE), 'follow', false(1, NE), ...
        'fdelay', 2 * ones(1, NE), 'unk', false(1, NE), 'T', H.T, 'r', rr(i));
end
end

function X = cut(X, n)
% Drop the cyclic padding of the last batch.
f = fieldnames(X);
for i = 1:numel(f), X.(f{i}) = X.(f{i})(:, 1:n); end
end

function R = cat_fields(R, Rb)
f = fieldnames(R);
for i = 1:numel(f), R.(f{i}) = [R.(f{i}), Rb.(f{i})]; end
end

function specs = full_val_spec(PP, K, H, split, reps, rs)
% The validation episodes of train_dqn.m.
C = decision_config();
cells = find(~cellfun(@isempty, PP.pools(:, 1, K.na, split))');
[c, s, r] = ndgrid(cells, 1:numel(PP.ebno), 1:K.nR(split));
c = repmat(c(:)', 1, reps); s = repmat(s(:)', 1, reps); r = repmat(r(:)', 1, reps);
n = numel(c); nb = ceil(n / H.NE);
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*H.NE + 1:min(b*H.NE, n); m = numel(i);
    specs{b} = struct('scn', c(i), 's', s(i), 'r', r(i), 'onset', randi(rs, [3 10], 1, m), ...
        'follow', K.followable(c(i)) & rand(rs, 1, m) < H.p_follow, 'fdelay', randi(rs, C.fdelay, 1, m), ...
        'unk', false(1, m), 'T', H.T);
end
end

function [kmin, name] = weakest_threat(V, thr)
% Lowest recovery among the recoverable episodes of one threat (at least 10).
m = V.recoverable & V.threat;
u = unique(thr(m));
rec = nan(1, numel(u));
for i = 1:numel(u)
    mi = m & strcmp(thr, u{i});
    if sum(mi) >= 10, rec(i) = mean(V.recovered(mi)); end
end
[kmin, j] = min(rec);
name = u{j};
end

function [PPw, Kw] = clean_world(PP, CT)
% The pools with the validation split replaced by the independent clean geometries.
nS = numel(PP.ebno); nA = numel(PP.actions);
pools = PP.pools;
pools(:, :, :, 2) = {[]};
ic = find(strcmp(PP.scen, 'none'), 1);
pools(ic, :, :, 2) = reshape(CT.pools(1, :, :), [1 nS nA]);
runs = PP.runs; runs{2} = CT.runs;
PPw = PP; PPw.pools = pools; PPw.runs = runs;
Kw = link_env('tables', PPw);
end
