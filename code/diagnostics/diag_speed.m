%% DIAG_SPEED - Detection errors and clean-link false alarms vs UAV speed (D52 diagnostic)
% Tests the fade-duration hypothesis: a Rician fade lasts longer at low speed
% (average 4 dB fade ~4.7 frames at 50 km/h, ~1.9 frames at 120 km/h), so if
% short decisions mistake fades for attenuation, errors should grow as speed
% falls. No simulation and no training: reads the saved result files only.
%   1. False-alarm episodes of the selected DQN and of rule + escalation per
%      speed band (600 independent clean geometries, and the 4-geometry set).
%   2. Clean frames the detector reads as a threat, per speed band
%      (clean_test_pools, no_action configuration, 600 geometries).
%   3. Detector recall per class and speed band on the test split, with the
%      most frequent wrong class.
%
% Run from the project root: diag_speed (startup.m puts code/ on the path)
% Output: results/diag_speed.txt

clc;
fprintf('=== Speed diagnostic (D52) ===\n\n');

%% 1. Inputs
P  = load('results/policy_evaluation.mat', 'RES', 'RW', 'POL', 'LBL', 'iDQN', 'KP', 'set_names');
L  = load('data/policy_pools.mat', 'PP'); vr = L.PP.speed_range; ebno = L.PP.ebno; clear L
C  = load('data/clean_test_pools.mat', 'CT'); CT = C.CT; clear C
D  = load('data/trained_detector.mat', 'net', 'classes');
classes = cellstr(string(D.classes(:)'));
edges = P.KP.speed_bins; nB = numel(edges) - 1;
band = @(v) min(max(discretize(v, edges), 1), nB);
blbl = arrayfun(@(b) sprintf('%.0f-%.0f', edges(b), edges(b+1)), 1:nB, 'UniformOutput', false);
low = ebno <= 4;                                   % Eb/N0 values where the false alarms concentrate
rep = {'=== SPEED DIAGNOSTIC (D52) ===', sprintf('Generated: %s | speed bands [km/h]: %s', ...
    datestr(now), strjoin(blbl, ', ')), ''};

%% 2. False-alarm episodes vs speed
iR = find(strcmp(P.POL, 'rule_esc'));
rep{end+1} = '--- 1. False-alarm episodes (>= 1 change) per speed band ---';
RW = P.RW{P.iDQN};
vW = arrayfun(@(i) speed_of(1, RW.s(i), 3, RW.r(i), vr), 1:numel(RW.s));
rep = [rep, fa_lines('600 new geometries, selected DQN', RW.switches > 0, vW, RW.s, band, blbl, low)];
rep = [rep, fa_lines('600 new geometries, rule + escalation', P.RW{iR}.switches > 0, vW, RW.s, band, blbl, low)];
iC = find(strcmp(P.set_names, 'clean'));
R4 = P.RES{iC, P.iDQN};
rep = [rep, fa_lines('test pools (4 geometries), selected DQN', R4.switches > 0, R4.speed, R4.s, band, blbl, low)];
fa = RW.switches(:) > 0; slow = vW(:) < edges(3);
[~, pF] = fishertest([sum(fa & slow), sum(~fa & slow); sum(fa & ~slow), sum(~fa & ~slow)]);
rep{end+1} = sprintf(['  DQN, 600 geometries: below %.0f km/h %d/%d, above %d/%d (Fisher exact p = %.3f); ' ...
    'mean speed of false-alarm episodes %.1f km/h, of the others %.1f km/h'], edges(3), sum(fa & slow), ...
    sum(slow), sum(fa & ~slow), sum(~slow), pF, mean(vW(fa)), mean(vW(~fa)));
rep{end+1} = '';

%% 3. Clean frames read as a threat vs speed (600 geometries, no_action)
a0 = find(strcmp(CT.actions, 'no_action'));
V = []; K = []; S = [];
for s = 1:numel(CT.ebno)
    Q = CT.pools{1, s, a0};
    [~, k] = max(Q.probs, [], 2);
    V = [V; arrayfun(@(r) speed_of(1, s, 3, r - 300, vr), Q.run(:))]; %#ok<AGROW>
    K = [K; k(:)]; S = [S; repmat(s, numel(k), 1)]; %#ok<AGROW>
end
iN = find(strcmp(classes, 'none')); iP = find(strcmp(classes, 'path_loss')); iA = find(strcmp(classes, 'antenna_fault'));
rep{end+1} = '--- 2. Clean frames the detector reads as a threat, per speed band (600 geometries, no_action) ---';
rep{end+1} = sprintf('  %-12s %8s %10s %10s %10s %14s', 'speed', 'frames', 'not none', 'path_loss', 'ant_fault', 'not none <=4dB');
for b = 1:nB
    m = band(V) == b; ml = m & reshape(low(S), [], 1);
    rep{end+1} = sprintf('  %-12s %8d %9.2f%% %9.2f%% %9.2f%% %13.2f%%', blbl{b}, sum(m), 100*mean(K(m) ~= iN), ...
        100*mean(K(m) == iP), 100*mean(K(m) == iA), 100*mean(K(ml) ~= iN)); %#ok<SAGROW>
end
rep{end+1} = '';

%% 4. Detector recall per class and speed band (test split)
T = load('data/splits.mat', 'splits'); te = T.splits.test; clear T
probs = cnn_scores(D.net, te.X, te.feats');
[~, k] = max(probs, [], 1); k = k(:);
[~, y] = ismember(cellstr(string(te.Y(:))), classes); v = te.speed(:); run = te.run(:); clear te probs
rep{end+1} = '--- 3. Detector recall per class and speed band, test split (frames / sub-runs in brackets) ---';
rep{end+1} = sprintf('  %-20s%s   %s', 'class', sprintf('%18s', blbl{:}), 'most frequent wrong class');
for c = 1:numel(classes)
    cells = cell(1, nB);
    for b = 1:nB
        m = y == c & band(v) == b;
        cells{b} = sprintf('%5.1f%% (%d/%d)', 100*mean(k(m) == c), sum(m), numel(unique(run(m))));
    end
    wrong = k(y == c & k ~= c);
    if isempty(wrong), wtxt = '-'; else
        [u, ~, j] = unique(wrong); cnt = accumarray(j, 1); [cm, im] = max(cnt);
        wtxt = sprintf('%s (%d of %d errors)', classes{u(im)}, cm, numel(wrong));
    end
    rep{end+1} = sprintf('  %-20s%s   %s', classes{c}, sprintf('%18s', cells{:}), wtxt); %#ok<SAGROW>
end
rep{end+1} = sprintf('  all classes: %.2f%% (%d frames)', 100*mean(k == y), numel(y));

fid = fopen('results/diag_speed.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
fprintf('\nSaved results/diag_speed.txt\n');

%% ===================== Local functions =====================
function v = speed_of(sc, s, sp, r, vr)
[~, v] = pool_seed(sc, s, sp, r, vr);
end

function lines = fa_lines(name, fa, v, s, band, blbl, low)
% False-alarm episodes per speed band, all Eb/N0 and Eb/N0 <= 4 dB.
fa = fa(:); b = band(v(:)); lo = low(s(:)); lo = lo(:);
lines = {sprintf('  %s', name)};
for j = 1:numel(blbl)
    m = b == j;
    lines{end+1} = sprintf('    %-10s %3d/%3d = %5.1f%%   at <= 4 dB %3d/%3d', blbl{j}, sum(fa(m)), sum(m), ...
        100*mean(fa(m)), sum(fa(m & lo)), sum(m & lo)); %#ok<AGROW>
end
end
