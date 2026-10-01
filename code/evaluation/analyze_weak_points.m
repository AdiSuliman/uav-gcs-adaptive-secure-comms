%% ANALYZE_WEAK_POINTS - Where the detector and the decision layer lose
% Breaks the test results down by every factor (weak_points.m): the detector's
% accuracy by class, Eb/N0, severity level, UAV speed, K-factor and interferer
% direction, and every class's detection rate by the same factors; the deployed
% policy's recovery by threat, severity, Eb/N0, speed, K-factor and test set, and
% every threat's recovery by the same factors. For every cell: value, 95% interval
% (bootstrap over sub-runs or flight geometries), difference to the rest, and the
% points of the overall result it pulls down below the target. Cells whose
% interval lies entirely below or above the rest are listed as weak or strong
% points, and the pairs (class x Eb/N0, class x level, class x speed; threat x
% severity, threat x Eb/N0) are mapped.
% Output: results/weak_points.{txt,json}

close all; clc;
fprintf('=== Weak points ===\n\n');
rep = {'=== WEAK POINTS: BREAKDOWN OF THE TEST RESULTS ==='};
rep{end+1} = sprintf(['Generated: %s | value = %% of units; [95%% bootstrap over sub-runs / geometries]; deficit = ' ...
    'points of the overall result the cell pulls down below the target; weak / strong = interval entirely ' ...
    'below / above the rest.'], datestr(now));
J = struct();
SPEED = [29 48 67 86 105 124 143 161];
KB = [-5 0 5 10 15 20];

%% 1. Detector
if isfile('results/detector_predictions.mat')
    L = load('results/detector_predictions.mat', 'pred'); pr = L.pred;
    yt = cellstr(string(pr.y_true(:))); yp = cellstr(string(pr.y_pred(:)));
    ok = strcmp(yt, yp);
    DL = dataset_levels();
    lr = nan(numel(yt), 1);                              % level rank inside the class (1 = weakest)
    for t = 1:numel(DL)
        m = strcmp(yt, DL(t).name);
        [~, lr(m)] = ismember(round(pr.level(m) * 1000), round(DL(t).levels * 1000));
    end
    F = table(categorical(yt), pr.ebno(:), pr.speed(:), lr, 'VariableNames', {'class', 'ebno', 'speed', 'level_rank'});
    opt = struct('target', 90, 'bins', struct('speed', SPEED, 'k_db', KB), ...
        'pairs', {{'class', 'ebno'; 'class', 'level_rank'; 'class', 'speed'}});
    if isfield(pr, 'k_db'), F.k_db = pr.k_db(:); F.aoa_abs = abs(pr.aoa(:)); opt.bins.aoa_abs = [0 15 30 45 60 90]; end
    Wd = weak_points(100 * ok, F, pr.run(:), opt);
    rep = [rep, section('DETECTOR: accuracy per frame, every class', Wd)];
    J.detector = pack(Wd);
    cls = unique(yt, 'stable');
    for c = 1:numel(cls)
        m = strcmp(yt, cls{c});
        Fc = F(m, setdiff(F.Properties.VariableNames, {'class'}, 'stable'));
        oc = opt; oc.pairs = {'level_rank', 'ebno'};
        Wc = weak_points(100 * ok(m), Fc, pr.run(m), oc);
        rep = [rep, section(sprintf('DETECTOR: %s detected as itself', cls{c}), Wc)]; %#ok<AGROW>
        J.detector_class.(matlab.lang.makeValidName(cls{c})) = pack(Wc);
    end
end

%% 2. Decision layer (deployed policy, recoverable threat episodes)
if isfile('results/policy_evaluation.mat') && isfile('data/policy_pools.mat')
    E = load('results/policy_evaluation.mat', 'RES', 'POL', 'set_names');
    Lp = load('data/policy_pools.mat', 'PP'); PP = Lp.PP; clear Lp
    iD = find(strcmp(E.POL, 'dqn_esc'));
    y = []; th = {}; sv = {}; eb = []; spd = []; kd = []; st = {}; g = [];
    kr = [-5 20]; if isfield(PP, 'k_range'), kr = PP.k_range; end
    for si = 1:numel(E.set_names)
        if any(strcmp(E.set_names{si}, {'clean'})), continue; end
        R = E.RES{si, iD};
        m = R.recoverable & R.threat;
        if ~any(m), continue; end
        y = [y; 100 * double(R.recovered(m))']; %#ok<AGROW>
        th = [th; PP.scen(R.scn(m))']; %#ok<AGROW>
        sv = [sv; PP.sev_names(PP.sev(R.scn(m)))']; %#ok<AGROW>
        eb = [eb; PP.ebno(R.s(m))']; spd = [spd; R.speed(m)']; %#ok<AGROW>
        sp = find(strcmp(PP.splits, 'test'));
        blk = floor(PP.runs{sp}(R.r(m)) / 100);
        kk = arrayfun(@(s, b, r) first(channel_k(pool_seed(1, s, b, r), kr)), R.s(m), blk, R.r(m));
        kd = [kd; kk(:)]; st = [st; repmat(E.set_names(si), sum(m), 1)]; g = [g; R.geom(m)' + 1e6 * si]; %#ok<AGROW>
    end
    F = table(categorical(th), categorical(sv, PP.sev_names), eb, spd, kd, categorical(st), ...
        'VariableNames', {'threat', 'severity', 'ebno', 'speed', 'k_db', 'set'});
    opt = struct('target', 90, 'bins', struct('speed', SPEED, 'k_db', KB), ...
        'pairs', {{'threat', 'severity'; 'threat', 'ebno'; 'threat', 'speed'}});
    Wp = weak_points(y, F, g, opt);
    rep = [rep, section('DECISION LAYER: recovered among recoverable threat episodes, deployed policy', Wp)];
    J.policy = pack(Wp);
    ths = unique(th, 'stable');
    for t = 1:numel(ths)
        m = strcmp(th, ths{t});
        Ft = F(m, setdiff(F.Properties.VariableNames, {'threat'}, 'stable'));
        ot = opt; ot.pairs = {'severity', 'ebno'};
        Wt = weak_points(y(m), Ft, g(m), ot);
        rep = [rep, section(sprintf('DECISION LAYER: %s', ths{t}), Wt)]; %#ok<AGROW>
        J.policy_threat.(matlab.lang.makeValidName(ths{t})) = pack(Wt);
    end
end

if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/weak_points.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fid = fopen('results/weak_points.json', 'w'); fprintf(fid, '%s', jsonencode(J)); fclose(fid);
fprintf('%s\n', rep{1:min(end, 80)});
fprintf('\nSaved results/weak_points.{txt,json}\n');

%% ===================== Local functions =====================
function lines = section(title, W)
lines = {'', sprintf('--- %s: %.1f%% over %d units (target %g%%) ---', title, W.overall, W.n, W.target)};
all_ = {};
for k = 1:numel(W.factors)
    T = W.factors(k).cells;
    for c = 1:height(T)
        all_(end+1, :) = {T.deficit(c), sprintf('%-11s %-14s %6.1f%% [%5.1f, %5.1f] n %5d, rest %5.1f%%, pulls down %.2f pts', ...
            W.factors(k).name, T.cell{c}, T.value(c), T.lo(c), T.hi(c), T.n(c), T.rest(c), T.deficit(c))}; %#ok<AGROW>
    end
end
if ~isempty(all_)
    [~, o] = sort(cell2mat(all_(:, 1)), 'descend');
    lines{end+1} = 'Largest deficits (a cell alone at the target would add these points):';
    for i = o(1:min(8, numel(o)))'
        if all_{i, 1} > 0.05, lines{end+1} = ['  ' all_{i, 2}]; end %#ok<AGROW>
    end
end
if ~isempty(W.low), lines{end+1} = 'Weak (significantly below the rest):'; lines = [lines, strcat({'  '}, W.low)]; end
if ~isempty(W.high), lines{end+1} = 'Strong (significantly above the rest):'; lines = [lines, strcat({'  '}, W.high)]; end
for q = 1:numel(W.pairs)
    P = W.pairs(q);
    lines{end+1} = sprintf('Map %s x %s (rows %s; %% of units):', P.a, P.b, P.a); %#ok<AGROW>
    lines{end+1} = sprintf('  %-20s %s', '', sprintf('%9s', P.lb{:})); %#ok<AGROW>
    for i = 1:numel(P.la)
        lines{end+1} = sprintf('  %-20s %s', P.la{i}, sprintf('%9.1f', P.value(i, :))); %#ok<AGROW>
    end
end
end

function s = pack(W)
s = struct('overall', W.overall, 'target', W.target, 'n', W.n, 'low', {W.low}, 'high', {W.high});
for k = 1:numel(W.factors)
    T = W.factors(k).cells;
    s.factors.(W.factors(k).name) = struct('cell', {T.cell'}, 'value', T.value', 'n', T.n', 'lo', T.lo', ...
        'hi', T.hi', 'deficit', T.deficit');
end
for q = 1:numel(W.pairs)
    P = W.pairs(q);
    s.pairs.(sprintf('%s_x_%s', P.a, P.b)) = struct('rows', {P.la}, 'cols', {P.lb}, 'value', P.value, 'n', P.n);
end
end

function v = first(x)
v = x(1);
end
