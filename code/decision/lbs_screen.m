function out = lbs_screen(src, varargin)
%LBS_SCREEN  LB-S: validation screen of the link-budget completion (lb_complete.m) on profile 1's kept agents.
%   out = lbs_screen(src, 'registered_by', hash)
%   out = lbs_screen(src, 'registered_by', hash, 'smoke', true)
%   src            profile 1's folder, only read: data/policy_pools.mat, data/unknown_threat_agents.mat,
%                  data/trained_dqn.mat, data/clean_val_pools.mat, results/eval_detector_metrics.mat
%   registered_by  the hash of the commit that registers the screen (printed in the log)
%   smoke          path_loss and one other threat, one repetition, two clean batches: no verdict
%   reps, boot     repetitions of every flight (default 2, as experiment_unknown_threat.m) and
%                  bootstrap resamples (default 2000)
%
%   Runs from the repository folder that holds this code (the current folder), not from src: the
%   clean reference is read from data/policy_pools.mat of the current folder (clean_ber_ref.m), so
%   the four inputs are copied there with SHA-256 (lbs_inputs.m) unless a verified copy is in place,
%   and the clean reference is asserted finite before any run.
%
%   Every run is on the validation split, with profile 1's deployed decision-time settings from
%   data/trained_dqn.mat (decision_settings.m), and with the completion off and on over the same
%   episodes and frame draws:
%     - the kept leave-one-threat-out agents on the flights of the threat they were left out of, every
%       severity and Eb/N0, the detector output withheld after the onset (experiment_unknown_threat.m).
%       They never trained or checkpointed on these flights (their cells are emptied from the
%       training and validation pools there). Besides: rule + escalation.
%     - the deployed agent on the same flights, which it was selected on (descriptive), and
%     - on the clean validation flights, one 30-cycle episode per geometry and Eb/N0 from the KPI 1
%       threshold up (clean_wide_specs.m), as the false-alarm reading of train_dqn.m.
%   The go rule is lbs_verdict.m. Output: results/lbs_screen.txt, results/lbs_screen.mat (out).
ip = inputParser;
addParameter(ip, 'registered_by', '');
addParameter(ip, 'smoke', false);
addParameter(ip, 'reps', 2);
addParameter(ip, 'boot', 2000);
parse(ip, varargin{:});
o = ip.Results;
if ~ischar(o.registered_by) || isempty(regexp(o.registered_by, '^[0-9a-f]{7,40}$', 'once'))
    error('lbs_screen:registration', ['lbs_screen: pass the hash of the commit that registers the screen ' ...
        '(''registered_by''); no run starts before it']);
end
if strcmpi(char(java.io.File(src).getCanonicalPath()), char(java.io.File(pwd).getCanonicalPath()))
    error('lbs_screen:folder', 'lbs_screen: run it from the worktree of the screen, not from its source folder %s', src);
end
SPLIT = 2; NE = 64; SEED0 = 7000; SEED_B = 1150; SEED_C = 41000; N_CLEAN = 1800;
t0 = tic;
fprintf('=== LB-S: link-budget completion on profile 1''s kept agents ===\n');

%% 1. Inputs, copied with SHA-256, and the clean reference
dst = fullfile(pwd, 'data');
if isfile(fullfile(dst, 'lbs_inputs.sha256'))
    inp = lbs_inputs('verify', dst);
    fprintf('Inputs in data/ checked against data/lbs_inputs.sha256 (%.1f min)\n', toc(t0) / 60);
else
    inp = lbs_inputs('copy', fullfile(src, 'data'), dst);
    fprintf('Inputs copied from %s with SHA-256 (%.1f min)\n', fullfile(src, 'data'), toc(t0) / 60);
end
Q = load('data/trained_dqn.mat', 'agent', 'H', 'norm_in', 'seed_summary', 'confirm', 'alarm_mode', 'drop_db', 'det_id', ...
    'maha_thr', 'dec', 'deployed');
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
UA = load('data/unknown_threat_agents.mat', 'agents_loo', 'threats', 'det_id');
Cv = load('data/clean_val_pools.mat', 'CT'); CT = Cv.CT; clear Cv
check_det_id(PP, Q, 'lbs_screen');
check_det_id(PP, UA, 'lbs_screen', 'data/unknown_threat_agents.mat');
check_det_id(PP, CT, 'lbs_screen', 'data/clean_val_pools.mat');
PP = decision_settings(PP, Q);                       % the deployed settings (train_dqn.m)
cref = lbs_inputs('clean_ref', PP.ebno);
fprintf('Clean reference finite at the %d Eb/N0 points (coded-link reference %s); pools loaded (%.1f min)\n', ...
    numel(PP.ebno), ternary(cref.plr_fec, 'present', 'absent'), toc(t0) / 60);
PP0 = PP; PP0.lb_complete = false;
PP1 = PP; PP1.lb_complete = true;
K = link_env('tables', PP0);
H = Q.H;
DK = 'dqn_esc'; if isfield(Q, 'deployed') && strcmp(Q.deployed, 'dqn'), DK = 'dqn'; end   % the DQN as deployed
nS = numel(PP.ebno);
P = PP.pools{find(strcmp(PP.scen, 'path_loss'), 1), 1, K.na, SPLIT};
if ~isfield(P, 'gant') || isempty(P.gant)
    error('lbs_screen:gant', 'lbs_screen: the pools carry no antenna channel gains; the completion could not act');
end
clear P
ebno_thr = PP.ebno(1); thr_from = 'the first Eb/N0 point';
mf = fullfile(src, 'results', 'eval_detector_metrics.mat');
if isfile(mf)
    Md = load(mf, 'metrics');
    if isfield(Md.metrics, 'kpi1_threshold_db') && isfinite(Md.metrics.kpi1_threshold_db)
        ebno_thr = Md.metrics.kpi1_threshold_db;
        thr_from = ['the KPI 1 threshold of results/eval_detector_metrics.mat, SHA-256 ' lbs_inputs('hash', mf)];
    end
    clear Md
end
[cspec, nc] = clean_wide_specs(PP0, CT, ebno_thr, H.T);
if ~o.smoke && nc ~= N_CLEAN
    error('lbs_screen:clean', 'lbs_screen: %d clean validation episodes at Eb/N0 >= %g dB, the screen reads %d', nc, ebno_thr, N_CLEAN);
end
threats = UA.threats;
sel = 1:numel(threats);
if o.smoke
    ipl = find(strcmp(threats, 'path_loss'), 1);
    sel = [ipl, find(~strcmp(threats, 'path_loss'), 1)];
    o.reps = 1; cspec = cspec(1:2); nc = 2 * NE;
end

%% 2. The kept agents on the flights of the threat they were left out of
rows = []; EP = struct('threat', {}, 'geom', {}, 'ok', {}, 'nt0', {}, 'nt1', {}, 'tr0', {}, 'tr1', {}, 'rule', {});
for ti = sel
    th = threats{ti};
    c = find(strcmp(PP.scen, th));
    specs = policy_episodes(c(:)', nS, K.geo(c, SPLIT), o.reps, false, true, NE, H.T, ...
        RandStream('mt19937ar', 'Seed', 500 + 100 * SPLIT + ti), [2 2]);
    ag = UA.agents_loo{ti};
    R = struct();
    R.nt0 = policy_run_set(DK, PP0, K, specs, SPLIT, ag, struct(), SEED0);
    R.nt1 = policy_run_set(DK, PP1, K, specs, SPLIT, ag, struct(), SEED0);
    R.tr0 = policy_run_set(DK, PP0, K, specs, SPLIT, Q.agent, struct(), SEED0);
    R.tr1 = policy_run_set(DK, PP1, K, specs, SPLIT, Q.agent, struct(), SEED0);
    R.rule = policy_run_set('rule_esc', PP0, K, specs, SPLIT, [], struct(), SEED0);
    [r, ok] = threat_row(th, R, o.boot, SEED_B + ti);
    rows = [rows, r]; %#ok<AGROW>
    EP(end+1) = struct('threat', th, 'geom', R.nt0.geom, 'ok', ok, 'nt0', R.nt0.recovered, 'nt1', R.nt1.recovered, ...
        'tr0', R.tr0.recovered, 'tr1', R.tr1.recovered, 'rule', R.rule.recovered); %#ok<AGROW>
    fprintf('[%d/%d] %-20s n %5d | never trained %.1f%% -> %.1f%% (%+.1f, lower bound %+.1f), completion acted in %.1f%% | trained %.1f%% -> %.1f%% | rule+esc %.1f%% (%.1f min)\n', ...
        find(sel == ti), numel(sel), th, r.n, r.off, r.on, r.d, r.lo, r.acted, r.t_off, r.t_on, r.rule, toc(t0) / 60);
end

%% 3. The deployed agent on the clean validation flights
PPc0 = clean_world(PP0, CT);
[PPc1, Kc] = clean_world(PP1, CT);
cl = []; sw = cell(1, 2); fs = cell(1, 2); lbc = [];
for v = 1:2
    PPv = PPc0; if v == 2, PPv = PPc1; end
    for b = 1:numel(cspec)
        Rb = rollout_policy(DK, PPv, Kc, cspec{b}, SPLIT, Q.agent, struct(), SEED_C + b);
        sw{v} = [sw{v}, Rb.switches]; fs{v} = [fs{v}, Rb.false_sw];
        if v == 1, cl = [cl, cspec{b}.r]; end %#ok<AGROW>
        if v == 2, lbc = [lbc, Rb.lb]; end %#ok<AGROW>
    end
    sw{v} = sw{v}(1:nc); fs{v} = fs{v}(1:nc);
end
cl = cl(1:nc); lbc = lbc(1:nc);
d = double(sw{2} > 0) - double(sw{1} > 0);
[dm, ~, hi] = lbs_boot(d, cl, o.boot, SEED_B + 100);
clean = struct('n', nc, 'geoms', numel(unique(cl)), 'off', 100 * mean(sw{1} > 0), 'on', 100 * mean(sw{2} > 0), ...
    'k_off', sum(sw{1} > 0), 'k_on', sum(sw{2} > 0), 'd', 100 * dm, 'hi', 100 * hi, ...
    'fs_off', 100 * mean(fs{1} > 0), 'fs_on', 100 * mean(fs{2} > 0), 'acted', 100 * mean(lbc > 0));
fprintf('Clean validation flights: %d episodes, changes %.2f%% -> %.2f%% (%+.2f points) (%.1f min)\n', ...
    clean.n, clean.off, clean.on, clean.d, toc(t0) / 60);

%% 4. Verdict and report
V = lbs_verdict(rows, clean);
[cm, tr, dirty] = code_state();
rule_sha = {lbs_inputs('hash', which('lbs_verdict')), lbs_inputs('hash', which('lb_complete'))};
rep = report_lines(PP, DK, o, rows, clean, V, inp, cm, tr, dirty, rule_sha, ebno_thr, thr_from, nS, toc(t0) / 60);
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/lbs_screen.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
out = struct('rows', rows, 'clean', clean, 'verdict', V, 'inputs', inp, 'commit', cm, 'tree', tr, 'registered_by', o.registered_by, ...
    'smoke', o.smoke, 'minutes', toc(t0) / 60, 'EP', EP);
save('results/lbs_screen.mat', 'out', '-v7.3');
fprintf('\nSaved results/lbs_screen.{txt,mat} (%.1f min)\n', toc(t0) / 60);
end

%% ===================== Local functions =====================
function [r, ok] = threat_row(th, R, B, seed)
% One threat's row: the recovered share among the recoverable episodes of the threat, completion off
% and on, the paired change with its one-sided bound, the share of episodes the completion acted in.
ok = R.nt0.recoverable & R.nt0.threat;
if ~isequal(ok, R.nt1.recoverable & R.nt1.threat) || ~isequal(R.nt0.geom, R.nt1.geom) || ~isequal(R.nt0.geom, R.tr0.geom)
    error('lbs_screen:pairing', 'lbs_screen: the runs of %s do not fly the same episodes', th);
end
d = double(R.nt1.recovered(ok)) - double(R.nt0.recovered(ok));
[dm, lo, hi] = lbs_boot(d, R.nt0.geom(ok), B, seed);
r = struct('threat', th, 'n', sum(ok), 'off', 100 * mean(R.nt0.recovered(ok)), 'on', 100 * mean(R.nt1.recovered(ok)), ...
    'd', 100 * dm, 'lo', 100 * lo, 'hi', 100 * hi, 'acted', 100 * mean(R.nt1.lb(ok) > 0), ...
    't_off', 100 * mean(R.tr0.recovered(ok)), 't_on', 100 * mean(R.tr1.recovered(ok)), 'rule', 100 * mean(R.rule.recovered(ok)));
end

function [cm, tr, dirty] = code_state()
% The commit and the tree of code/ the screen runs, and whether code/ has local changes.
cm = 'unknown'; tr = 'unknown'; dirty = true;
try
    g = sprintf('git --no-optional-locks -C "%s" ', project_root());
    [s1, o1] = system([g 'rev-parse HEAD HEAD:code']);
    [s2, o2] = system([g 'status --porcelain --untracked-files=all -- code']);
    t = strsplit(strtrim(o1));
    if s1 == 0 && numel(t) == 2, cm = t{1}; tr = t{2}; end
    dirty = ~(s2 == 0 && isempty(strtrim(o2)));
catch
end
end

function rep = report_lines(PP, DK, o, rows, clean, V, inp, cm, tr, dirty, rule_sha, ebno_thr, thr_from, nS, minutes)
rep = {'=== LB-S: LINK-BUDGET COMPLETION ON PROFILE 1''S KEPT AGENTS (VALIDATION SCREEN) ==='};
rep{end+1} = sprintf('Generated: %s | code commit %s, code tree %s%s | registered by %s | %.1f min', datestr(now), cm, tr, ...
    ternary(dirty, ' + local changes in code/', ''), o.registered_by, minutes);
rep{end+1} = sprintf('Rule code SHA-256: lbs_verdict.m %s, lb_complete.m %s', rule_sha{:});
rep{end+1} = 'Inputs, copies in data/ with the SHA-256 of the source:';
for i = 1:numel(inp.files), rep{end+1} = sprintf('  %s  %s', inp.sha256{i}, inp.files{i}); end %#ok<AGROW>
ed = isfield(PP, 'esc_drop') && ~isempty(PP.esc_drop) && PP.esc_drop;
ur = NaN; if isfield(PP, 'unk_retain') && ~isempty(PP.unk_retain), ur = PP.unk_retain; end
rep{end+1} = sprintf(['Deployed settings (data/trained_dqn.mat): kind %s, monitor %s %d/%d, drop threshold %g %s, esc_drop %s ' ...
    '(registered: on), unknown retention %g (registered: 0.99), unknown threshold %g'], DK, PP.alarm_mode, PP.confirm(1), ...
    PP.confirm(2), PP.drop_db, drop_unit(PP.alarm_mode), ternary(ed, 'on', 'OFF'), ur, PP.maha_thr);
if ~ed || ~(abs(ur - 0.99) <= 1e-12)
    rep{end+1} = 'NOTE: the deployed settings differ from the registered description; the screen ran the settings of the file.';
end
rep{end+1} = '';
rep{end+1} = sprintf(['Validation split. Kept leave-one-threat-out agents on the flights of the threat they were left out ' ...
    'of (every severity, %d Eb/N0 points, %d repetitions of every flight, detector output withheld after the onset); ' ...
    'recovered = BER and packet loss <= 2x clean for 5 consecutive cycles, among the recoverable episodes of the threat. ' ...
    'Change = completion on less off on the same episodes and frame draws; the bound is the one-sided 95%% lower bound ' ...
    '(cluster bootstrap over flights, %d resamples).'], nS, o.reps, o.boot);
rep{end+1} = sprintf('%-20s %5s | %26s | %24s | %8s', 'threat', 'n', 'never trained: off, on, change [lb]', ...
    'deployed agent: off, on, chg', 'rule+esc');
for i = 1:numel(rows)
    r = rows(i);
    rep{end+1} = sprintf('%-20s %5d | %6.1f%% %6.1f%% %+6.1f [%+6.1f] | %6.1f%% %6.1f%% %+6.1f | %7.1f%%', r.threat, r.n, ...
        r.off, r.on, r.d, r.lo, r.t_off, r.t_on, r.t_on - r.t_off, r.rule); %#ok<AGROW>
end
rep{end+1} = sprintf('Share of episodes in which the completion changed the proposal (never trained): %s', ...
    strjoin(arrayfun(@(r) sprintf('%s %.1f%%', r.threat, r.acted), rows, 'UniformOutput', false), ', '));
rep{end+1} = '';
rep{end+1} = sprintf(['Clean validation flights, deployed agent: %d episodes (%d geometries, Eb/N0 >= %g dB, %s, 30 cycles): ' ...
    'episodes with a change of configuration off %d (%.2f%%), on %d (%.2f%%), change %+.2f points [one-sided 95%% upper bound ' ...
    '%+.2f]; with a change on a healthy link off %.2f%%, on %.2f%%; the completion changed a proposal in %.2f%% of the episodes.'], ...
    clean.n, clean.geoms, ebno_thr, thr_from, clean.k_off, clean.off, clean.k_on, clean.on, clean.d, clean.hi, ...
    clean.fs_off, clean.fs_on, clean.acted);
rep{end+1} = '';
rep{end+1} = 'Go rule:';
rep = [rep, cellfun(@(s) ['  ' s], V.lines, 'UniformOutput', false)];
if o.smoke, rep{end+1} = 'SMOKE run: two threats, one repetition, two clean batches; the verdict above is not a reading.'; end
rep{end+1} = '';
rep{end+1} = ['Disclosed: the 1800 clean validation flights and the deployed agent were used by profile 1''s C1d and C2 selection, ' ...
    'and the deployed agent was selected on the validation flights of the threats above, so this screen is a further use of ' ...
    'them (the deployed-agent columns are descriptive). The kept agents never trained on the flights they are read on. ' ...
    'Profile 1''s monitor is the one before the degradation fix, so the screen transfers to profile 3 qualitatively only.'];
rep{end+1} = ['Not covered: noise_burst for a never-trained agent has no class-free mapping from bursts to the coding ' ...
    'domain; its row is the agent''s training coverage.'];
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
