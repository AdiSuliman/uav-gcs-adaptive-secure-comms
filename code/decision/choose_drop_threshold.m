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
% (C.confirm and C.monitors, confirm_alarm.m; of C2's grid the 2/2 one, since 3/3, 4/5 and
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
% threshold, or without clean validation flights. The median window's reference holds the
% cycles of a drop above half the smallest path-loss level until it ends, as the CUSUM's
% does (drop_ref.m), so the two forms differ in their statistic only. The CUSUM's
% thresholds are counted in cycles of a step of the smallest path-loss level at the
% statistic's full drift (D^2 / 2 per cycle, drop_cusum.m).
% The whole monitor, per confirmation of C2's monitors (C.monitors): a policy changes the
% configuration only on a confirmed alarm (policy_mask.m), so up to its first change every
% policy flies the no_action episode, and the share of clean episodes whose no_action monitor
% confirms an alarm bounds every policy's false-alarm share on the same episodes exactly. The
% monitor runs once at no_action (monitor_trace.m) over the clean validation episodes
% train_dqn.m reads its false alarms on (clean_wide_specs.m) and over every single threat of
% the validation split; per monitor and threshold of the chosen form the alarm is rebuilt:
% the drop alarm, its reference free of every alarm cycle, or any other path (a hostile
% class but path_loss, degradation), confirmed by the monitor's m of n (monitor_confirm.m).
% Each monitor takes the most sensitive threshold whose bound is admissible (KPI 6's 5%);
% when the other paths alone break the bound no threshold can meet it, which is reported,
% and the monitor takes the least sensitive one. C2 tries each monitor's threshold and the
% steps C.drop_steps around it (train_dqn.m). The sweeping jammer's own confirmation
% (C.confirm_sweep, policy_monitor.m) is adopted when, with every monitor at its own pick, no
% monitor loses an admissible threshold or needs a less sensitive one and no single threat's
% never-confirmed share or 90th-percentile delay grows; both readings are printed.
%
% The degradation test, only with "deg_select": true in profile.json (deg_options.m; CFG.deg_select
% overrides it), before the whole monitor's reading (docs/deg_fix_protocol.md): the clean
% validation geometries split by hash into a fit half and a check half (clean_halves.m); the
% clean quantile tables from the fit half (clean_ber_q.m); per candidate in the order F1 'win',
% F2 'win_q' and F3 'win_q_gate' per alpha (C.deg_alpha), the reading of section 5 on the check
% half's clean episodes and the validation split's single threats, each monitor at its own most
% sensitive admissible threshold, beside 'ratio' on the same episodes; adopted by deg_adopt.m.
% The whole monitor's reading below then runs with the adopted test. Without the switch nothing
% of this runs and the outputs are those of before. In the smoke only (SMOKE), deg_force
% (profile.json or CFG.deg_force, deg_force.m) deploys one named candidate after the adoption,
% marked DEG.forced beside the rule's pick DEG.rule_pick (docs/p1r_protocol.md); refused otherwise.
%
% Output: data/drop_threshold.mat (drop_db, the median window's threshold alone, and
% drop_db_train, drop_from; drop_alarm, cusum_db, the confirmations CF and the validation
% readings VAL; MONP, each monitor's threshold and readings; confirm_sweep, the sweeper's
% confirmation adopted, [] when not; with deg_select deg_mode, ber_q, the adopted test and its
% quantile table ([] without one), and DEG, its readings), results/drop_threshold.txt

clc;
fprintf('=== Eb/N0-drop threshold of the drop alarm ===\n\n');
DGon = deg_options().on; if exist('CFG', 'var') && isstruct(CFG) && isfield(CFG, 'deg_select'), DGon = CFG.deg_select; end
DGf = deg_options().force; if exist('CFG', 'var') && isstruct(CFG) && isfield(CFG, 'deg_force'), DGf = deg_force('check', CFG.deg_force, 'CFG'); end
deg_force('smoke', DGf, exist('SMOKE', 'var') && SMOKE, 'choose_drop_threshold');   % before any output is written
if ~isempty(DGf) && ~(DGon && isfile('data/clean_val_pools.mat'))
    error('choose_drop_threshold:force', 'deg_force %s needs deg_select and clean validation flights', DGf);
end
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
MN = decision_config().monitors;
if exist('CFG', 'var') && isstruct(CFG) && isfield(CFG, 'monitors'), MN = CFG.monitors; end
for mn = MN(:)'
    tk = strsplit(mn{1}); CF(end+1, :) = sscanf(tk{2}, '%d/%d')'; %#ok<SAGROW>
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

%% 5. The whole monitor per confirmation: each monitor's threshold, the sweeper's confirmation
MON = MN;
fm = find(strcmp(FM, drop_alarm)); GF = GR{fm}; CS = decision_config().confirm_sweep;
DEG = [];                                                  % the degradation test chosen here (deg_options.m)
if DGon && isempty(CV)
    DEG = struct('mode', 'ratio', 'ber_q', [], 'note', 'no clean validation flights: not chosen');
    rd = {'', 'Degradation test: no clean validation flights, ''ratio'' kept (not chosen).'};
elseif DGon
    [DEG, rd] = deg_select(PP, CV, drop_alarm, GF, MON, CS, EBNO_THR, T, VA, FA_BOUND, DGf);
    PP.deg_mode = DEG.mode; PP.ber_q = DEG.ber_q;           % the monitor of the reading below and of C2
end
if DGon
    fid = fopen('results/drop_threshold.txt', 'a'); fprintf(fid, '%s\n', rd{:}); fclose(fid);
    fprintf('%s\n', rd{:});
end
MONP = struct('monitor', MON, 'cf', [], 'pick', NaN, 'j', NaN, 'admissible', false, 'k', NaN, 'n', 0, ...
    'k_other', NaN, 'lat', []);
confirm_sweep = [];
rw = {'', sprintf(['The whole monitor at no_action per confirmation (%s, %s): false alarms on the clean validation ' ...
    'episodes train_dqn.m reads (an exact bound for every policy on them), the drop alarm of the form %s or any other ' ...
    'path; delays on the single threats of the validation split, cycles from the onset to the first confirmed alarm ' ...
    '(the decision reading the threat''s first frame is 0)'], strjoin(MON, ', '), drop_alarm, drop_alarm)};
if isempty(CV)
    rw{end+1} = 'No clean validation flights: every monitor at the form''s threshold above, the sweeper''s confirmation not adopted.';
    for m = 1:numel(MON)
        tk = strsplit(MON{m}); MONP(m).cf = sscanf(tk{2}, '%d/%d')';
        MONP(m).pick = thr_val; if ~isfinite(thr_val), MONP(m).pick = drop_db; end
    end
else
    PPm = PP; PPm.alarm_mode = drop_alarm;
    [PPw, Kw] = clean_world(PPm, CV);
    [spc, ncl] = clean_wide_specs(PPm, CV, EBNO_THR, T);
    Tc = monitor_trace(PPw, Kw, spc, VA, 41000);
    Tc = trim_trace(Tc, ncl);
    PPv = PPm; PPv.pools(:, :, :, setdiff(1:numel(PP.runs), VA)) = {[]};   % the validation split only
    Kv = link_env('tables', PPv);
    sgl = find(ismember(PP.scen, PP.singles) & ~strcmp(PP.scen, 'none'));
    spv = policy_episodes(sgl, nS, Kv.geo(sgl, VA), 1, false, false, 64, T, RandStream('mt19937ar', 'Seed', 4400));
    Tv = monitor_trace(PPv, Kv, spv, VA, 4500);
    onv = Kv.on(sub2ind(size(Kv.on), Tv.scn, Tv.s, VA + 0 * Tv.s, Tv.r));
    thv = PP.scen(Tv.scn); thn = unique(thv(onv), 'stable');
    R = cell(1, 2);                                          % the sweeper's confirmation off, on
    for sw = 1:2
        cs = []; if sw == 2, cs = CS; end
        for m = 1:numel(MON)
            tk = strsplit(MON{m}); cf = sscanf(tk{2}, '%d/%d')';
            k = arrayfun(@(t) sum(any(monitor_confirm(Tc, drop_alarm, t, cf, cs), 2)), [GF, Inf]);
            up = arrayfun(@(x) cp_upper(x, ncl), k);
            j = find(up(1:end-1) <= FA_BOUND, 1);
            adm = ~isempty(j); if ~adm, j = numel(GF); end
            cv = monitor_confirm(Tv, drop_alarm, GF(j), cf, cs);
            R{sw} = [R{sw}, struct('cf', cf, 'j', j, 'pick', GF(j), 'admissible', adm, 'k', k(j), 'k_other', k(end), ...
                'lat', delays(cv, Tv.onset, thv, onv, thn))];
        end
    end
    ok = arrayfun(@(m) (~R{1}(m).admissible || R{2}(m).admissible) && R{2}(m).j <= R{1}(m).j && ...
        all(R{2}(m).lat.never <= R{1}(m).lat.never) && all(fill_inf(R{2}(m).lat.p90) <= fill_inf(R{1}(m).lat.p90)), 1:numel(MON));
    sw = 1 + all(ok); if sw == 2, confirm_sweep = CS; end
    for m = 1:numel(MON)
        MONP(m).cf = R{sw}(m).cf; MONP(m).j = R{sw}(m).j; MONP(m).pick = R{sw}(m).pick; MONP(m).admissible = R{sw}(m).admissible;
        MONP(m).k = R{sw}(m).k; MONP(m).n = ncl; MONP(m).k_other = R{sw}(m).k_other; MONP(m).lat = R{sw}(m).lat;
    end
    for s = 1:2
        rw{end+1} = sprintf('  sweeper''s own confirmation %s:', ternary(s == 1, 'off', sprintf('on, %d of %d cycles', CS))); %#ok<SAGROW>
        for m = 1:numel(MON)
            x = R{s}(m);
            rw{end+1} = sprintf(['    %-15s threshold %6.1f %-4s %s, false alarms %d/%d (bound %.2f%%); other paths alone ' ...
                '%d/%d (bound %.2f%%)'], MON{m}, x.pick, drop_unit(drop_alarm), ternary(x.admissible, 'admissible', ...
                'NONE ADMISSIBLE: the least sensitive'), x.k, ncl, 100 * cp_upper(x.k, ncl), x.k_other, ncl, ...
                100 * cp_upper(x.k_other, ncl)); %#ok<SAGROW>
            if ~x.admissible && cp_upper(x.k_other, ncl) > FA_BOUND
                rw{end+1} = sprintf(['      the other paths alone break the %.0f%% bound under %s: no drop threshold can meet ' ...
                    'KPI 6 with this monitor'], 100 * FA_BOUND, MON{m}); %#ok<SAGROW>
            end
            rw{end+1} = sprintf('      delays median / p90 / never: %s', strjoin(cellfun(@(n, a, b, c) sprintf('%s %g/%g/%.1f%%', ...
                n, a, b, c), x.lat.threat, num2cell(x.lat.median), num2cell(x.lat.p90), num2cell(100 * x.lat.never), ...
                'UniformOutput', false), ', ')); %#ok<SAGROW>
        end
    end
    rw{end+1} = sprintf(['Sweeper''s own confirmation: %s (no monitor loses an admissible threshold or needs a less ' ...
        'sensitive one, no single threat''s never share or p90 delay grows: %s)'], ternary(sw == 2, 'ADOPTED', 'not adopted'), ...
        strjoin(arrayfun(@(m) sprintf('%s %s', MON{m}, ternary(ok(m), 'yes', 'no')), 1:numel(MON), 'UniformOutput', false), ', '));
end
fid = fopen('results/drop_threshold.txt', 'a'); fprintf(fid, '%s\n', rw{:}); fclose(fid);
fprintf('%s\n', rw{:});
SV = {'drop_db', 'drop_db_train', 'drop_from', 'separable', 'THR', 'kept', 'leak', 'leak_all', ...
    'p95_mis', 'p99_cl', 'p05_pl', 'floor_db', 'drop_alarm', 'cusum_db', 'THC', 'VAL', 'CF', 'EBNO_THR', 'MONP', 'confirm_sweep'};
if ~isempty(DEG)                                           % deployed by train_dqn.m (PP.deg_mode, PP.ber_q)
    deg_mode = DEG.mode; ber_q = DEG.ber_q; SV = [SV, {'deg_mode', 'ber_q', 'DEG'}];
end
save('data/drop_threshold.mat', SV{:});
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

function T = trim_trace(T, n)
% The first n episodes of a monitor trace (the padding of the last batch dropped).
for f = fieldnames(T)'
    if size(T.(f{1}), 1) > 1, T.(f{1}) = T.(f{1})(1:n, :); else, T.(f{1}) = T.(f{1})(1:n); end
end
end

function L = delays(c, onset, thr, on, names)
% Per threat (severities pooled, episodes with the threat on the air): the cycles from the
% onset to the first confirmed alarm, the decision of cycle onset + 1 reading the threat's
% first frame (0); median, p90 (nearest rank) and the never-confirmed share.
L = struct('threat', {names}, 'n', zeros(1, numel(names)), 'median', nan(1, numel(names)), ...
    'p90', nan(1, numel(names)), 'never', zeros(1, numel(names)));
d = nan(size(c, 1), 1);
for i = 1:size(c, 1)
    k = find(c(i, onset(i) + 1:end), 1);
    if ~isempty(k), d(i) = k - 1; end
end
for q = 1:numel(names)
    m = on(:) & strcmp(thr(:), names{q}); x = sort(d(m & ~isnan(d)));
    L.n(q) = sum(m); L.never(q) = mean(isnan(d(m)));
    if ~isempty(x), L.median(q) = median(x); L.p90(q) = x(min(numel(x), max(1, round(0.9 * numel(x))))); end
end
end

function x = fill_inf(x)
x(isnan(x)) = Inf;
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

function [DEG, rw] = deg_select(PP, CV, drop_alarm, GF, MON, CS, thr, T, VA, FA, force)
% The degradation test chosen on validation (docs/deg_fix_protocol.md): the quantile tables
% from the fit half of the clean validation geometries; per candidate, 'ratio' first, the
% reading of section 5 on the check half's clean episodes and the validation split's single
% threats, the same episodes and frames for every candidate; adopted by deg_adopt.m. force
% (smoke only, deg_force.m): the candidate deployed instead, '' for the adoption.
C = decision_config(); nS = numel(PP.ebno);
[fit, chk] = clean_halves(CV.runs);
assert(~any(fit & chk) && all(fit | chk), 'choose_drop_threshold: the fit and check halves overlap');
BQ = clean_ber_q(CV, PP, fit);
K = struct('name', {'ratio', 'F1 win'}, 'mode', {'ratio', 'win'}, 'q', {0, 0});
for a = 1:numel(C.deg_alpha), K(end+1) = struct('name', sprintf('F2 win_q, alpha %g', C.deg_alpha(a)), 'mode', 'win_q', 'q', a); end %#ok<AGROW>
for a = 1:numel(C.deg_alpha), K(end+1) = struct('name', sprintf('F3 win_q_gate, alpha %g', C.deg_alpha(a)), 'mode', 'win_q_gate', 'q', a); end %#ok<AGROW>
PPm = PP; PPm.alarm_mode = drop_alarm;
[spc, ncl] = clean_wide_specs(PPm, CV, thr, T, find(chk));
PPv = PPm; PPv.pools(:, :, :, setdiff(1:numel(PP.runs), VA)) = {[]};   % the validation split only
Kv = link_env('tables', PPv);
sgl = find(ismember(PP.scen, PP.singles) & ~strcmp(PP.scen, 'none'));
spv = policy_episodes(sgl, nS, Kv.geo(sgl, VA), 1, false, false, 64, T, RandStream('mt19937ar', 'Seed', 4400));
X = cell(1, numel(K));
for c = 1:numel(K)
    bq = []; if K(c).q > 0, bq = BQ(K(c).q); end
    Pc = PPm; Pc.deg_mode = K(c).mode; Pc.ber_q = bq;
    [PPw, Kw] = clean_world(Pc, CV);
    Tc = trim_trace(monitor_trace(PPw, Kw, spc, VA, 41000), ncl);
    Pv = PPv; Pv.deg_mode = K(c).mode; Pv.ber_q = bq;
    Tv = monitor_trace(Pv, Kv, spv, VA, 4500);
    onv = Kv.on(sub2ind(size(Kv.on), Tv.scn, Tv.s, VA + 0 * Tv.s, Tv.r));
    thv = PP.scen(Tv.scn); thn = unique(thv(onv), 'stable');
    X{c} = whole_monitor(Tc, Tv, ncl, onv, thv, thn, drop_alarm, GF, MON, CS, FA);
    X{c}.quiet_clean = sum(any(Tc.quiet, 2));             % clean episodes with a cycle degraded without RF evidence
    X{c}.quiet_threat = mean(any(Tv.quiet(onv, :), 2));
end
R0 = struct('lat', [X{1}.R.lat], 'monitor', {MON});
RC = struct('lat', {}, 'bound', {});
for c = 2:numel(K), RC(end+1) = struct('lat', [X{c}.R.lat], 'bound', [X{c}.R.bound]); end %#ok<AGROW>
[pick, adm, best, fail] = deg_adopt(RC, R0, FA);
DEG = struct('mode', 'ratio', 'ber_q', [], 'name', 'ratio', 'pick', pick);
if pick > 0
    DEG.mode = K(pick + 1).mode; DEG.name = K(pick + 1).name;
    if K(pick + 1).q > 0, DEG.ber_q = BQ(K(pick + 1).q); end
end
DEG.cand = {K.name}; DEG.adm = adm; DEG.best = best; DEG.fail = fail; DEG.readings = X; DEG.BQ = BQ;
DEG.fit_runs = double(CV.runs(fit)); DEG.check_runs = double(CV.runs(chk)); DEG.n_check = ncl; DEG.monitors = MON;
% Report
rw = {'', sprintf(['Degradation test on validation (docs/deg_fix_protocol.md): quantile tables from the fit half (%d ' ...
    'clean geometries, every Eb/N0, every %d-frame window at no_action); candidates read on the check half (%d ' ...
    'geometries, %d clean episodes, Eb/N0 >= %g dB) and on the validation split''s single threats, each monitor at ' ...
    'its own most sensitive admissible threshold'], sum(fit), C.win, sum(chk), ncl, thr)};
for a = 1:numel(BQ)
    Q = BQ(a);
    rw{end+1} = sprintf('  quantile table, alpha %g (bins of >= %d cycles from >= %d flights)%s:', Q.alpha, Q.need, Q.fmin, ...
        ternary(Q.short, ' -- TOO FEW CYCLES: one bin short of the rule', '')); %#ok<AGROW>
    for i = 1:numel(Q.q)
        rw{end+1} = sprintf('    Eb/N0 [%5.1f, %5.1f) dB: %6d cycles, %3d flights, threshold %.2e', Q.lo(i), Q.hi(i), Q.n(i), ...
            Q.nf(i), Q.q(i)); %#ok<AGROW>
    end
end
for c = 1:numel(K)
    x = X{c};
    v = 'reference'; if c > 1, v = ternary(adm(c - 1), 'ADMISSIBLE', ['not admissible (' fail{c - 1} ')']); end
    rw{end+1} = sprintf('  %s: %s; sweeper''s own confirmation %s', K(c).name, v, ternary(x.sweep, 'on', 'off')); %#ok<AGROW>
    for m = 1:numel(MON)
        r = x.R(m);
        rw{end+1} = sprintf('    %-15s threshold %6.1f %-4s %s, false alarms %d/%d (bound %.2f%%); other paths alone %d/%d', ...
            MON{m}, r.pick, drop_unit(drop_alarm), ternary(r.admissible, 'admissible', 'none admissible'), r.k, ncl, ...
            100 * r.bound, r.k_other, ncl); %#ok<AGROW>
        rw{end+1} = sprintf('      delays median / p90 / never: %s', strjoin(cellfun(@(n, a, b, d) sprintf('%s %g/%g/%.1f%%', ...
            n, a, b, d), r.lat.threat, num2cell(r.lat.median), num2cell(r.lat.p90), num2cell(100 * r.lat.never), ...
            'UniformOutput', false), ', ')); %#ok<AGROW>
    end
    if strcmp(K(c).mode, 'win_q_gate')
        rw{end+1} = sprintf(['    degraded, no RF evidence (logged, no alarm): %d of %d clean episodes; %.1f%% of the ' ...
            'threat episodes'], x.quiet_clean, ncl, 100 * x.quiet_threat); %#ok<AGROW>
    end
end
if pick > 0
    how = ternary(best(pick) <= FA, sprintf('the first admissible with a bound <= %.0f%% under some monitor', 100 * FA), ...
        sprintf('no admissible candidate reaches %.0f%%: the admissible one with the lowest bound', 100 * FA));
    rw{end+1} = sprintf('Degradation test ADOPTED: %s (%s; lowest bound %.2f%%)', DEG.name, how, 100 * best(pick));
else
    rw{end+1} = 'Degradation test: no candidate admissible, ''ratio'' kept (F4 is the registered next step).';
end
if ~isempty(force)
    [DEG, ln] = deg_force('apply', DEG, force, K, BQ); rw{end+1} = ln;
end
end

function W = whole_monitor(Tc, Tv, ncl, onv, thv, thn, drop_alarm, GF, MON, CS, FA)
% Section 5's reading of one candidate: per monitor its most sensitive admissible threshold
% on the clean episodes Tc and the delays on the threats Tv, the sweeper's own confirmation
% adopted as there.
R = cell(1, 2);
for sw = 1:2
    cs = []; if sw == 2, cs = CS; end
    for m = 1:numel(MON)
        tk = strsplit(MON{m}); cf = sscanf(tk{2}, '%d/%d')';
        k = arrayfun(@(t) sum(any(monitor_confirm(Tc, drop_alarm, t, cf, cs), 2)), [GF, Inf]);
        up = arrayfun(@(x) cp_upper(x, ncl), k);
        j = find(up(1:end-1) <= FA, 1);
        adm = ~isempty(j); if ~adm, j = numel(GF); end
        cv = monitor_confirm(Tv, drop_alarm, GF(j), cf, cs);
        R{sw} = [R{sw}, struct('cf', cf, 'j', j, 'pick', GF(j), 'admissible', adm, 'k', k(j), 'k_other', k(end), ...
            'bound', up(j), 'lat', delays(cv, Tv.onset, thv, onv, thn))];
    end
end
ok = arrayfun(@(m) (~R{1}(m).admissible || R{2}(m).admissible) && R{2}(m).j <= R{1}(m).j && ...
    all(R{2}(m).lat.never <= R{1}(m).lat.never) && all(fill_inf(R{2}(m).lat.p90) <= fill_inf(R{1}(m).lat.p90)), 1:numel(MON));
sw = 1 + all(ok);
W = struct('sweep', sw == 2);
W.R = R{sw};
end
