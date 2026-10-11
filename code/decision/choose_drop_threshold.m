%% CHOOSE_DROP_THRESHOLD - Eb/N0-drop threshold of the drop alarm from the train pools
% A clean link in a deep Rician fade and an attenuated link look alike in one
% frame; the drop of the Eb/N0 estimate from the episode's reference tells them
% apart. The drop raises the alarm by itself (policy_monitor.m, 'class_drop'), so every
% clean frame is a candidate false alarm. The threshold is chosen from data, on the TRAIN
% split only: the drop of every path_loss frame (every severity) against the drop of
% every clean frame, both measured the way policy_monitor.m measures them (3-frame median
% against the reference of the clean link of the same geometry). The threshold is the
% midpoint between the 99th percentile of the clean frames and the 5th percentile of the
% path_loss frames when the two separate; otherwise the value with the largest margin
% (kept path loss minus passed clean frames), flagged as overlapping. The m-of-n
% confirmation and the false-alarm bound on the validation flights follow in train_dqn.m.
% Physics floor: moving away lowers the estimate by at most 8.69 v / d dB/s (free space,
% d(20 log10 d)/dt), at 161 km/h and the shortest distance of the grid; over the 12 cycles
% between the oldest reference cycle and the newest one the threshold must stay above it.
%
% Output: data/drop_threshold.mat (drop_db), results/drop_threshold.txt

clc;
fprintf('=== Eb/N0-drop threshold of the path_loss alarm ===\n\n');
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
na = find(strcmp(PP.actions, 'no_action'));
iPL = find(strcmp(PP.scen, 'path_loss'));                  % the three severities
icl = find(strcmp(PP.scen, 'none'), 1);
kPL = find(strcmp(PP.classes, 'path_loss'));
nS = numel(PP.ebno);
TR = 1;                                                    % train split only
THR = 2:0.5:10;
p0 = load('params.mat').params;
ramp = 20 / log(10) * p0.v_max / (1000 * link_distance_km(max(PP.ebno), p0));   % [dB/s]
floor_db = ramp * 12 * decision_config().period_ms / 1000;
assert(THR(1) > floor_db, 'choose_drop_threshold: the grid starts below the moving-away drop of %.2f dB', floor_db);

%% 1. Drops per frame, clean link and path loss, every train geometry
d_pl = []; e_pl = []; d_mis = []; e_mis = []; d_cl = []; e_cl = [];
for s = 1:nS
    C = PP.pools{icl, s, na, TR};
    for r = 1:numel(PP.runs{TR})
        run = PP.runs{TR}(r);
        ic = find(C.run == run);
        if isempty(ic), continue; end
        ec = ebno_est(C.feat(ic, :), PP);
        ref = median(ec);                                  % reference: the clean link of this geometry
        dc = ref - med3(ec);
        [~, kc] = max(C.probs(ic, :), [], 2);
        d_cl = [d_cl; dc]; e_cl = [e_cl; repmat(s, numel(dc), 1)]; %#ok<AGROW>
        d_mis = [d_mis; dc(kc == kPL)]; e_mis = [e_mis; repmat(s, sum(kc == kPL), 1)]; %#ok<AGROW>
        for v = iPL                                        % same geometry under attenuation (same seeds)
            A = PP.pools{v, s, na, TR};
            ia = find(A.run == run);
            if isempty(ia), continue; end
            da = ref - med3(ebno_est(A.feat(ia, :), PP));
            d_pl = [d_pl; da]; e_pl = [e_pl; repmat(s, numel(da), 1)]; %#ok<AGROW>
        end
    end
end

%% 2. Separation and threshold
p95_mis = prctile(d_mis, 95); p05_pl = prctile(d_pl, 5); p99_cl = prctile(d_cl, 99);
kept = arrayfun(@(t) mean(d_pl >= t), THR);
leak = arrayfun(@(t) mean(d_mis >= t), THR);
leak_all = arrayfun(@(t) mean(d_cl >= t), THR);
if p05_pl > p99_cl
    drop_db = min(max(round(2 * (p99_cl + p05_pl) / 2) / 2, THR(1)), THR(end));
    how = sprintf('midpoint of the 99th percentile of the clean frames (%.1f dB) and the 5th percentile of path_loss frames (%.1f dB)', p99_cl, p05_pl);
    separable = true;
else
    [~, j] = max(kept - leak_all); drop_db = THR(j);
    how = sprintf('distributions overlap (99th percentile of the clean frames %.1f dB, 5th percentile of path_loss %.1f dB): largest margin kept - passed', p99_cl, p05_pl);
    separable = false;
end

%% 3. Report
rep = {'=== EB/N0-DROP THRESHOLD OF THE DROP ALARM ===', ...
    sprintf('Generated: %s | train pools, no_action, %d geometries per Eb/N0 | drop = clean reference - 3-frame median', ...
    datestr(now), numel(PP.runs{TR})), ''};
rep{end+1} = sprintf('Frames: path_loss %d | clean %d, of which read as path_loss %d (%.2f%%)', numel(d_pl), ...
    numel(d_cl), numel(d_mis), 100 * numel(d_mis) / numel(d_cl));
rep{end+1} = sprintf('Drop percentiles 5 / 50 / 95 [dB]: path_loss %.1f / %.1f / %.1f | clean read as path_loss %.1f / %.1f / %.1f | all clean %.1f / %.1f / %.1f', ...
    prctile(d_pl, [5 50 95]), prctile(d_mis, [5 50 95]), prctile(d_cl, [5 50 95]));
rep{end+1} = '';
rep{end+1} = sprintf('%-10s %16s %22s %16s', 'threshold', 'path_loss kept', 'misread clean passed', 'all clean passed');
for j = 1:numel(THR)
    rep{end+1} = sprintf('%7.1f dB %15.1f%% %21.2f%% %15.2f%%', THR(j), 100*kept(j), 100*leak(j), 100*leak_all(j)); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = 'Per Eb/N0, median drop [dB]: path_loss | clean read as path_loss (count)';
for s = 1:nS
    rep{end+1} = sprintf('  %2d dB   %5.1f | %5.1f (%d)', PP.ebno(s), median(d_pl(e_pl == s)), ...
        median(d_mis(e_mis == s)), sum(e_mis == s)); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = sprintf('Moving away: at most %.2f dB/s (161 km/h, %.2f km), %.2f dB over 12 cycles, below every threshold of the grid.', ...
    ramp, link_distance_km(max(PP.ebno), p0), floor_db);
rep{end+1} = sprintf('Threshold: %.1f dB (%s). At this threshold: path_loss kept %.1f%%, clean frames passed %.2f%% (misread as path_loss %.1f%%).', ...
    drop_db, how, 100*mean(d_pl >= drop_db), 100*mean(d_cl >= drop_db), 100*mean(d_mis >= drop_db));
if ~separable, rep{end+1} = 'WARNING: the distributions overlap; the gate trades path_loss detection for false alarms.'; end
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/drop_threshold.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
save('data/drop_threshold.mat', 'drop_db', 'separable', 'THR', 'kept', 'leak', 'leak_all', 'p95_mis', 'p99_cl', 'p05_pl', 'floor_db');
fprintf('\nSaved data/drop_threshold.mat, results/drop_threshold.txt\n');

%% ===================== Local functions =====================
function e = ebno_est(F, PP)
% Eb/N0 estimate of policy_monitor.m: SINR + interference over thermal.
F = double(F);
e = F(:, feature_index('sinr')) + F(:, feature_index('iot')) + 10*log10(PP.sps) - 10*log10(PP.bps);
end

function m = med3(e)
% Cyclic 3-frame running median (the monitor keeps the last 3 cycles).
n = numel(e); m = zeros(n, 1);
for i = 1:n
    m(i) = median(e(mod(i - 3:i - 1, n) + 1));
end
end
