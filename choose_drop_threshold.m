%% CHOOSE_DROP_THRESHOLD - Eb/N0-drop threshold of the path_loss alarm from the train pools (D52, D59)
% A clean link in a deep Rician fade and an attenuated link look alike in one
% frame; the drop of the Eb/N0 estimate from the episode's reference tells them
% apart (D50). D50 set the threshold at 4 dB by assumption, which is the size
% of the fades that mislead the detector, so it filtered nothing. Here the
% threshold is chosen from data, on the TRAIN split only: the drop of every
% path_loss frame (every severity, 6 / 10 / 14 dB) against the drop of every clean
% frame the detector reads as path_loss, both measured the way
% policy_monitor.m measures them (3-frame median against the reference of the
% clean link of the same geometry). The threshold is the midpoint between the
% 95th percentile of the misread clean frames and the 5th percentile of the
% real path_loss frames when the two separate; otherwise the value with the
% largest margin (kept real minus passed misreads), flagged as overlapping.
%
% Output: data/drop_threshold.mat (drop_db), results/drop_threshold.txt

clc;
fprintf('=== Eb/N0-drop threshold of the path_loss alarm (D52) ===\n\n');
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
na = find(strcmp(PP.actions, 'no_action'));
iPL = find(strcmp(PP.scen, 'path_loss'));                  % the three severities
icl = find(strcmp(PP.scen, 'none'), 1);
kPL = find(strcmp(PP.classes, 'path_loss'));
nS = numel(PP.ebno);
TR = 1;                                                    % train split only
THR = 2:0.5:10;

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
p95_mis = prctile(d_mis, 95); p05_pl = prctile(d_pl, 5);
kept = arrayfun(@(t) mean(d_pl >= t), THR);
leak = arrayfun(@(t) mean(d_mis >= t), THR);
leak_all = arrayfun(@(t) mean(d_cl >= t), THR);
if p05_pl > p95_mis
    drop_db = round(2 * (p95_mis + p05_pl) / 2) / 2;
    how = sprintf('midpoint of the 95th percentile of misread clean frames (%.1f dB) and the 5th percentile of path_loss frames (%.1f dB)', p95_mis, p05_pl);
    separable = true;
else
    [~, j] = max(kept - leak); drop_db = THR(j);
    how = sprintf('distributions overlap (95th percentile of misread clean frames %.1f dB, 5th percentile of path_loss %.1f dB): largest margin kept - passed', p95_mis, p05_pl);
    separable = false;
end

%% 3. Report
rep = {'=== EB/N0-DROP THRESHOLD OF THE PATH_LOSS ALARM (D52, D59) ===', ...
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
rep{end+1} = sprintf('Threshold: %.1f dB (%s). At this threshold: path_loss kept %.1f%%, misread clean passed %.1f%%.', ...
    drop_db, how, 100*mean(d_pl >= drop_db), 100*mean(d_mis >= drop_db));
if ~separable, rep{end+1} = 'WARNING: the distributions overlap; the gate trades path_loss detection for false alarms.'; end
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/drop_threshold.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
save('data/drop_threshold.mat', 'drop_db', 'separable', 'THR', 'kept', 'leak', 'p95_mis', 'p05_pl');
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
