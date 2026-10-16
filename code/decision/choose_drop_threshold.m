%% CHOOSE_DROP_THRESHOLD - Eb/N0-drop threshold and form of the drop alarm
% A clean link in a deep Rician fade and an attenuated link look alike in one
% frame; the drop of the Eb/N0 estimate from the episode's reference tells them
% apart. The drop raises the alarm by itself (policy_monitor.m, 'class_drop'), so every
% clean frame is a candidate false alarm. A first threshold is chosen from data, on the TRAIN
% split only: the drop of every path_loss frame (every severity) against the drop of
% every clean frame, both measured the way policy_monitor.m measures them (3-frame median
% against the reference of the clean link of the same geometry). The threshold is the
% midpoint between the 99th percentile of the clean frames and the 5th percentile of the
% path_loss frames when the two separate; otherwise the value with the largest margin
% (kept path loss minus passed clean frames), flagged as overlapping. It is the median
% window's threshold when the validation readings below admit none.
% Physics floor: moving away lowers the estimate by at most 8.69 v / d dB/s (free space,
% d(20 log10 d)/dt), at 161 km/h and the shortest distance of the grid; over the 12 cycles
% between the oldest reference cycle and the newest one the threshold must stay above it.
% Form of the alarm, on the VALIDATION split only, before train_dqn.m: the 3-cycle median
% window ('class_drop') against the window-limited CUSUM of every cycle's drop
% ('class_cusum', drop_cusum.m; Page's CUSUM, Xie et al. 2021; the window-limited estimate of
% the drop, Xie, Moustakides & Xie 2022), both on the same compensated estimate with the
% monitor's reference, alone (drop_alarm_seq.m), read through the monitor's m-of-n
% confirmation, since only a confirmed alarm lets a policy change the configuration
% (policy_mask.m, policy_decide.m): confirmed by any confirmation of C2's monitors
% (C.confirm and CFG.monitors, confirm_alarm.m; of C2's grid the 2/2 one, since 3/3, 4/5 and
% 5/5 confirm only after two consecutive alarms), so a threshold admissible here is admissible
% under every monitor of the grid. False alarms: the independent clean validation geometries
% (data/clean_val_pools.mat), one 30-cycle episode per geometry and Eb/N0 from the KPI 1
% threshold up, from a random frame, as train_dqn.m reads them; an episode with the confirmed
% alarm in some cycle is a false alarm, and a threshold is admissible when the one-sided 95%
% Clopper-Pearson bound of their share is at most 5%, KPI 6's bound, so the drop alarm alone
% never spends it. Detection: the path_loss cells of the validation split, every level,
% Eb/N0 and geometry, REPS episodes each: the same flight's clean link until the onset
% (cycle 3-10), the attenuated flight from it at the same frame positions (link_env.m);
% detected when the alarm is confirmed at or after the onset. Each form at its most
% sensitive admissible threshold; the form that detects more, within one point the one with
% the shorter mean delay; the median window on a tie, when the CUSUM has no admissible
% threshold, or without clean validation flights. The chosen form is deployed at the
% threshold it was compared at (drop_alarm_form.m; C2 tries it and more sensitive ones), the
% median window at the train-pool threshold when it has no admissible one. The CUSUM's
% thresholds are counted in cycles of a step of the smallest path-loss level at the
% statistic's full drift (D^2 / 2 per cycle, drop_cusum.m).
%
% Output: data/drop_threshold.mat (drop_db, the median window's deployed threshold, and
% drop_db_train, drop_from; drop_alarm, cusum_db, the confirmations CF and the validation
% readings VAL), results/drop_threshold.txt

clc;
fprintf('=== Eb/N0-drop threshold of the drop alarm ===\n\n');
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

%% 1. Drops per frame, clean link and path loss, every train geometry of the clean link's own
% (not the airframe-shadowing flights it flies as their reference, PP.ref_geo)
RR = 1:numel(PP.runs{TR});
if isfield(PP, 'cell_geo'), RR = PP.cell_geo{icl}{TR}; end
d_pl = []; e_pl = []; d_mis = []; e_mis = []; d_cl = []; e_cl = [];
for s = 1:nS
    C = PP.pools{icl, s, na, TR};
    for r = RR
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
    datestr(now), numel(RR)), ''};
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
rep{end+1} = sprintf('Train-pool threshold: %.1f dB (%s). At this threshold: path_loss kept %.1f%%, clean frames passed %.2f%% (misread as path_loss %.1f%%).', ...
    drop_db, how, 100*mean(d_pl >= drop_db), 100*mean(d_cl >= drop_db), 100*mean(d_mis >= drop_db));
if ~separable, rep{end+1} = 'WARNING: the distributions overlap; the gate trades path_loss detection for false alarms.'; end
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/drop_threshold.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});

%% 4. Form of the alarm on validation: the median window against the window-limited CUSUM
VA = 2; T = 30; REPS = 4; FA_BOUND = 0.05;
D1 = decision_config().sev.path_loss.levels(1);
THC = D1^2 / 2 * (1:0.5:10);                                % CUSUM thresholds: cycles of a D1 step at full drift
CF = decision_config().confirm;                             % every confirmation of C2's monitors
if exist('CFG', 'var') && isstruct(CFG) && isfield(CFG, 'monitors')
    for mn = CFG.monitors(:)'
        tk = strsplit(mn{1}); CF(end+1, :) = sscanf(tk{2}, '%d/%d')'; %#ok<SAGROW>
    end
end
CF = unique(CF, 'rows');
EBNO_THR = PP.ebno(1);                                      % false alarms from the KPI 1 threshold up (KPI 6)
if isfile('results/eval_detector_metrics.mat')
    Md = load('results/eval_detector_metrics.mat', 'metrics');
    if isfield(Md.metrics, 'kpi1_threshold_db') && isfinite(Md.metrics.kpi1_threshold_db)
        EBNO_THR = Md.metrics.kpi1_threshold_db;
    end
    clear Md
end
CV = [];
if isfile('data/clean_val_pools.mat')
    Cv = load('data/clean_val_pools.mat', 'CT'); CV = Cv.CT; clear Cv
    check_det_id(PP, CV, 'choose_drop_threshold', 'data/clean_val_pools.mat');
end
[Ecl, Epl, Opl] = val_episodes(PP, CV, icl, iPL, na, VA, T, REPS, EBNO_THR);
FM = {'class_drop', 'class_cusum'}; GR = {THR, THC};
VAL = struct('mode', FM, 'grid', GR, 'fa_k', [], 'fa_n', size(Ecl, 1), 'fa_up', [], 'det', [], 'delay', [], 'pick', NaN);
for f = 1:2
    for j = 1:numel(GR{f})
        a = confirm_alarm(drop_alarm_seq(Ecl, FM{f}, GR{f}(j)), CF);
        VAL(f).fa_k(j) = sum(any(a, 2)); VAL(f).fa_up(j) = cp_upper(VAL(f).fa_k(j), size(Ecl, 1));
        a = confirm_alarm(drop_alarm_seq(Epl, FM{f}, GR{f}(j)), CF);
        a(Opl > (0:T-1)) = false;                            % confirmed from the onset on
        [hit, t1] = max(a, [], 2);
        VAL(f).det(j) = mean(hit); VAL(f).delay(j) = mean(t1(hit) - 1 - Opl(hit));
    end
    k = find(VAL(f).fa_up <= FA_BOUND, 1);                   % the most sensitive admissible threshold
    if ~isempty(k), VAL(f).pick = k; end
end
[drop_alarm, thr_val] = drop_alarm_form(VAL);
drop_db_train = drop_db; drop_from = 'train pools'; cusum_db = NaN;
if strcmp(drop_alarm, 'class_cusum')
    cusum_db = thr_val;
elseif isfinite(thr_val)
    drop_db = thr_val; drop_from = 'validation';
end
rv = {'', sprintf(['Form of the drop alarm on validation (alone, the monitor''s reference, confirmed %s): false ' ...
    'alarms on %d clean validation episodes (%s geometries x Eb/N0 >= %g dB, %d cycles), admissible at a one-sided ' ...
    '95%% bound <= %.0f%%; detection on %d path_loss episodes of the validation split (every level, Eb/N0 and ' ...
    'geometry, %d each, onset at cycle 3-10)'], strjoin(arrayfun(@(i) sprintf('%d/%d', CF(i, :)), 1:size(CF, 1), ...
    'UniformOutput', false), ' or '), size(Ecl, 1), n_geo(CV), EBNO_THR, T, 100 * FA_BOUND, size(Epl, 1), REPS)};
for f = 1:2
    rv{end+1} = sprintf('  %-12s %10s %14s %10s %18s', FM{f}, 'threshold', 'false alarms', 'bound', 'detected / delay'); %#ok<SAGROW>
    for j = 1:numel(GR{f})
        rv{end+1} = sprintf('  %-12s %10.1f %8d/%-5d %9.2f%% %8.1f%% / %4.1f%s', '', GR{f}(j), VAL(f).fa_k(j), VAL(f).fa_n, ...
            100 * VAL(f).fa_up(j), 100 * VAL(f).det(j), VAL(f).delay(j), repmat('  <-', 1, j == VAL(f).pick)); %#ok<SAGROW>
    end
end
rv{end+1} = sprintf(['Form: %s (each at its most sensitive admissible threshold: the higher detection, within one ' ...
    'point the shorter delay; the median window on a tie or without an admissible CUSUM threshold)%s'], drop_alarm, ...
    ternary(isempty(Ecl), ' -- no clean validation flights: not measured', ''));
if strcmp(drop_alarm, 'class_cusum')
    rv{end+1} = sprintf('Deployed: the window-limited CUSUM at %.1f %s (validation)', cusum_db, drop_unit(drop_alarm));
else
    rv{end+1} = sprintf('Deployed: the 3-cycle median window at %.1f %s (%s; train-pool threshold %.1f dB)', drop_db, ...
        drop_unit(drop_alarm), drop_from, drop_db_train);
end
fid = fopen('results/drop_threshold.txt', 'a'); fprintf(fid, '%s\n', rv{:}); fclose(fid);
fprintf('%s\n', rv{:});
save('data/drop_threshold.mat', 'drop_db', 'drop_db_train', 'drop_from', 'separable', 'THR', 'kept', 'leak', 'leak_all', ...
    'p95_mis', 'p99_cl', 'p05_pl', 'floor_db', 'drop_alarm', 'cusum_db', 'THC', 'VAL', 'CF', 'EBNO_THR');
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

function [Ecl, Epl, Opl] = val_episodes(PP, CV, icl, iPL, na, sp, T, reps, thr)
% Eb/N0 estimates per cycle (rows: episodes) of the clean validation episodes (one per CV
% geometry and Eb/N0 from thr up, from a random frame) and of the path_loss episodes of split
% sp (the same flight's clean link before the onset Opl, the attenuated one from it).
rs = RandStream('mt19937ar', 'Seed', 4300);
Ecl = zeros(0, T); Epl = zeros(0, T); Opl = zeros(0, 1);
if ~isempty(CV)
    for s = find(PP.ebno >= thr)
        P = CV.pools{1, s, na};
        for r = 1:CV.n_geom
            k = find(P.run == CV.runs(r)); n = numel(k);
            q = mod(randi(rs, n) - 1 + (0:T-1), n) + 1;
            Ecl(end+1, :) = ebno_est(P.feat(k(q), :), PP)'; %#ok<AGROW>
        end
    end
end
for v = iPL
    for s = 1:numel(PP.ebno)
        C = PP.pools{icl, s, na, sp}; A = PP.pools{v, s, na, sp};
        if isempty(A) || isempty(A.ber), continue; end
        for r = PP.cell_geo{v}{sp}
            kc = find(C.run == PP.runs{sp}(r)); ka = find(A.run == PP.runs{sp}(r));
            if isempty(kc) || numel(kc) ~= numel(ka), continue; end
            ec = ebno_est(C.feat(kc, :), PP); ea = ebno_est(A.feat(ka, :), PP); n = numel(kc);
            for k = 1:reps
                o = randi(rs, [3 10]); q = mod(randi(rs, n) - 1 + (0:T-1), n) + 1;
                x = ec(q); x((0:T-1) >= o) = ea(q((0:T-1) >= o));
                Epl(end+1, :) = x'; Opl(end+1, 1) = o; %#ok<AGROW>
            end
        end
    end
end
end

function u = cp_upper(k, n)
% One-sided 95% Clopper-Pearson upper bound of a binomial proportion (NaN without trials).
if n == 0, u = NaN; elseif k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

function t = n_geo(CV)
if isempty(CV), t = '0'; else, t = sprintf('%d', CV.n_geom); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
