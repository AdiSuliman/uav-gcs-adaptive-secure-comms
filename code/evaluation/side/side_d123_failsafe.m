function S = side_d123_failsafe(eval_mat, out_dir, label)
%SIDE_D123_FAILSAFE  Recovery time against an autopilot link-loss failsafe (D123), a labelled side reading.
%   S = side_d123_failsafe(eval_mat, out_dir, label)
%   eval_mat  a saved results/policy_evaluation.mat (opened read-only; variables ALL, POL, LBL, iDQN, KP)
%   out_dir   a new folder; side_d123.txt and side_d123.mat are written there
%   label     text for the header (for example 'profile 3')
%   Per policy: the share of recoverable threat episodes whose link is restored within 0.6 s (the
%   episode, 30 cycles), 5 s (ArduPilot FS_GCS_TIMEOUT, 250 cycles) and 10 s (PX4 COM_DL_LOSS_T, 500
%   cycles) of the 20 ms cycle, and the share never restored inside the episode (censored), with 95%
%   Clopper-Pearson intervals (episodes treated as independent) and a 95% bootstrap over flight
%   geometries of the share restored within 0.6 s.
%   Restored = BER and packet loss restored for 5 consecutive cycles (rollout_policy.m); the time
%   is read when that run is complete (its start + 4 cycles), the later of the two readings.
%   Time references, as the fields allow:
%     onset   cycles from the onset to the completed run (t_rec + 4), every policy
%     onset via detection   onset to the first confirmed alarm plus detection to the completed
%             packet-loss run (t_conf + t_rec_det + 4); an undetected episode is censored
%     from detection   t_rec_det + 4 on the episodes detected (those never restored censored)
%   Masks: the five jamming threats (the lecturer's recoverable jamming episodes, lect_kpis.m JAM),
%   and every recoverable threat episode beside it.
if nargin < 3, label = ''; end
CYC = 0.02; NRUN = 5; HOR = [30 250 500]; HN = {'0.6 s', '5 s (ArduPilot)', '10 s (PX4)'};
JAM = {'jamming', 'noise_burst', 'reactive_jamming', 'sweeping_jammer', 'tone_jamming'};
if ~isfile(eval_mat), error('side_d123:input', 'side_d123_failsafe: %s not found', eval_mat); end
out = side_out_dir(out_dir, eval_mat);
notes = {sprintf('label: %s', label), ...
    ['D123: share of recoverable episodes whose link is restored within the autopilot link-loss failsafe times; the episode is 30 cycles ' ...
    '(0.6 s), so an episode restored inside it is within both timeouts by construction and one not restored is censored at 0.6 s, ' ...
    'with no claim about 5 s or 10 s'], ...
    ['reading choices: restored = BER and packet loss restored for 5 consecutive cycles, read when the run is complete (start + 4 ' ...
    'cycles), the later reading; clock 20 ms per cycle'], ...
    ['intervals: 95% Clopper-Pearson (episodes counted as independent, the narrower reading) and a 95% bootstrap over flight ' ...
    'geometries (2000 resamples, seed 123) of the share restored within 0.6 s'], ...
    'masks: the five jamming threats among the recoverable episodes (D123), and all recoverable threat episodes beside them'};
L = side_header('D123 recovery time against an autopilot link-loss failsafe', eval_mat, notes);
W = load(eval_mat, 'ALL', 'POL', 'LBL', 'iDQN', 'KP');
for f = {'ALL', 'POL', 'KP'}
    if ~isfield(W, f{1}), error('side_d123:field', 'side_d123_failsafe: %s holds no variable %s', eval_mat, f{1}); end
end
ALL = W.ALL; POL = cellstr(string(W.POL(:)')); KP = W.KP;
LBL = POL; if isfield(W, 'LBL'), LBL = cellstr(string(W.LBL(:)')); end
iDQN = 0; if isfield(W, 'iDQN'), iDQN = double(W.iDQN); end
R1 = ALL{1};
[nm, pinfo] = side_pool_names(KP, R1);
L{end+1} = sprintf('threat names rebuilt from KP.threats (%d pool cells; reproduces KP.recoverable_share)', pinfo.ncells);
mrec = logical(R1.recoverable(:)') & logical(R1.threat(:)');
masks = {'jamming threats', mrec & ismember(nm(:)', JAM); 'all threats', mrec};
geom = R1.geom(:)';
Ttxt = 'not stored in the file (30 cycles by D123)'; if isfield(R1, 'cfg_trace'), Ttxt = sprintf('%d cycles', size(R1.cfg_trace, 1)); end
L{end+1} = sprintf('episode length: %s; policies in the file: %s', Ttxt, strjoin(POL, ', '));
for i = 1:numel(ALL), ALL{i} = rmfield_safe(ALL{i}, 'cfg_trace'); end
rows = struct('mask', {}, 'policy', {}, 'label', {}, 'role', {}, 'ref', {}, 'n', {}, 'k', {}, 'ci', {}, 'kcens', {}, 'cens_ci', {}, ...
    'boot06', {}, 'median_ms', {}, 'over_horizon', {}, 'note', {});
refs = {'onset', {'t_rec'}, @(R) R.t_rec + NRUN - 1, false; ...
        'onset via detection', {'t_conf', 't_rec_det'}, @(R) R.t_conf + R.t_rec_det + NRUN - 1, false; ...
        'from detection', {'t_conf', 't_rec_det'}, @(R) R.t_rec_det + NRUN - 1, true};
for im = 1:size(masks, 1)
    mk = masks{im, 2};
    L{end+1} = sprintf('--- mask: %s, %d recoverable episodes in %d flight geometries ---', masks{im, 1}, sum(mk), ...
        numel(unique(geom(mk)))); %#ok<AGROW>
    for pk = 1:numel(ALL)
        R = ALL{pk}; p = POL{pk};
        tag = sprintf('%s [%s]%s%s', p, LBL{pk}, role_of(p), ternary(pk == iDQN, ' = deployed', ''));
        for ir = 1:size(refs, 1)
            need = refs{ir, 2};
            miss = need(~cellfun(@(f) isfield(R, f), need));
            if ~isempty(miss)
                L{end+1} = sprintf('  %s | %s: FIELD ABSENT (%s); nothing read', tag, refs{ir, 1}, strjoin(miss, ', ')); %#ok<AGROW>
                rows(end+1) = struct('mask', masks{im, 1}, 'policy', p, 'label', LBL{pk}, 'role', role_of(p), 'ref', refs{ir, 1}, ...
                    'n', NaN, 'k', nan(1, 3), 'ci', nan(3, 2), 'kcens', NaN, 'cens_ci', [NaN NaN], 'boot06', nan(1, 3), ...
                    'median_ms', NaN, 'over_horizon', NaN, 'note', ['field absent: ' strjoin(miss, ', ')]); %#ok<AGROW>
                continue
            end
            t = refs{ir, 3}(R); t = t(:)';
            m = mk;
            if refs{ir, 4}, m = mk & isfinite(R.t_conf(:)'); end
            tt = t(m); n = numel(tt);
            k = arrayfun(@(h) sum(tt <= h), HOR); kc = sum(~isfinite(tt));
            ci = nan(3, 2);
            for h = 1:3, [ci(h, 1), ci(h, 2)] = side_cp(k(h), n); end
            [cl, ch] = side_cp(kc, n);
            b06 = [NaN NaN NaN];
            if n > 0, [b06(1), b06(2), b06(3)] = boot_cluster(double(tt <= HOR(1)), ones(1, n), geom(m), 2000, 123); end
            md = NaN; if any(isfinite(tt)), md = 1e3 * CYC * median(tt(isfinite(tt))); end
            over = sum(isfinite(tt) & tt > HOR(1));
            rows(end+1) = struct('mask', masks{im, 1}, 'policy', p, 'label', LBL{pk}, 'role', role_of(p), 'ref', refs{ir, 1}, ...
                'n', n, 'k', k, 'ci', ci, 'kcens', kc, 'cens_ci', [cl ch], 'boot06', b06, 'median_ms', md, 'over_horizon', over, ...
                'note', ''); %#ok<AGROW>
            L{end+1} = sprintf('  %s | %s (%d episodes%s)', tag, refs{ir, 1}, n, ternary(refs{ir, 4}, ', detected only', '')); %#ok<AGROW>
            L{end+1} = sprintf('      restored within %s', strjoin(arrayfun(@(h) sprintf('%s %d/%d = %.1f%% [%.1f, %.1f]', HN{h}, ...
                k(h), n, 100 * k(h) / max(n, 1), 100 * ci(h, 1), 100 * ci(h, 2)), 1:3, 'UniformOutput', false), ' | ')); %#ok<AGROW>
            L{end+1} = sprintf(['      censored (never restored inside the episode) %d/%d = %.1f%% [%.1f, %.1f]; geometry bootstrap of ' ...
                'the share within 0.6 s %.1f%% [%.1f, %.1f]; median time of the restored %.0f ms; restored later than 0.6 s: %d'], ...
                kc, n, 100 * kc / max(n, 1), 100 * cl, 100 * ch, 100 * b06, md, over); %#ok<AGROW>
        end
    end
end
L{end+1} = '';
L{end+1} = ['every episode restored inside the 30-cycle horizon is within 5 s and 10 s by construction; a censored episode is not ' ...
    'claimed to recover later'];
S = struct('label', label, 'input', eval_mat, 'sha256', side_sha256(eval_mat), 'horizon_cycles', HOR, 'cycle_s', CYC, ...
    'rows', rows, 'pool_cells', pinfo, 'policies', {POL});
side_write(out, 'side_d123', L, S);
fprintf('%s\n', L{:});
end

function s = role_of(p)
switch p
    case 'none', s = ' = static';
    case 'blind_esc', s = ' = conventional adaptive (no detector)';
    case 'rule_esc', s = ' = CNN-based adaptive (rule + escalation)';
    otherwise, s = '';
end
end

function R = rmfield_safe(R, f)
if isfield(R, f), R = rmfield(R, f); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
