function combo_miss_diag(pools_file, agent_file, manifest_file, out_dir, reg_commit, docs_repo, dry)
%COMBO_MISS_DIAG  R5: which class the monitor reads on the combined threats DET misses, on a copy of
%   profile 1's validation pools at no_action. Descriptive: no number of any
%   profile changes, no threshold is chosen from it, and 82.2% stays the combined threats' DET_h as read.
%   combo_miss_diag(pools_file, agent_file, manifest_file, out_dir, reg_commit, docs_repo)
%   pools_file     a copy of data/policy_pools.mat; every split but the validation one is emptied on load
%                  (reader_guard.m)
%   agent_file     the archived trained_dqn.mat, read for the deployed monitor's settings only
%                  (alarm mode, confirmation, drop threshold: decision_settings.m); its sha256 must match
%                  its line in manifest_file
%   out_dir        under <repo>/results (default <repo>/results): combo_miss.txt and combo_miss.mat, once
%   reg_commit     the commit that registers these readings (hex); docs_repo, if given, is checked for it
%                  (without it the log says the commit is unverified)
%   dry            true: a pair the pools do not hold is left out (a dry run on the deploy smoke's pools, which hold
%                  two of the five); default false, then a missing pair stops the run
%   Pairs: jamming+path_loss, tone_jamming+path_loss, jamming+antenna_fault, noise_burst+antenna_fault,
%   spoofing+sweeping_jammer, every severity of the pools. For each threat-active frame det_frames.m is
%   read three times, with the registered definition (hit), with one row per class under the monitor's
%   class alone (the class), and with no class counted (the drop alarm alone); the three must agree.
%   Harmed is edge_map.m's (DET_h, 82.2%): no response does not restore the flight against that flight's
%   own clean link (link_env 'flight').
%   Tables: combo_miss_tables.m.
PAIRS = {'jamming+path_loss', 'tone_jamming+path_loss', 'jamming+antenna_fault', 'noise_burst+antenna_fault', ...
    'spoofing+sweeping_jammer'};
DET_H_READ = 82.2;              % the combined threats' DET_h as read (profile 1, edge_map.m, test pools)
SEED_BOOT = 11700;              % bootstrap streams of the tables: + 10 pair + 1..3
VAL = 2;
LEVEL = {'path_loss', 'antenna_fault', 'airframe_shadowing'};
BRANCH = {'antenna_fault', 'airframe_shadowing'};
t_all = tic;
root = project_root();
if nargin < 4 || isempty(out_dir), out_dir = fullfile(root, 'results'); end
if nargin < 5, reg_commit = ''; end
if nargin < 6, docs_repo = ''; end
if nargin < 7 || isempty(dry), dry = false; end
out_dir = reader_guard('out', out_dir, root);
reader_guard('input', pools_file, {'policy_pools.mat'});
reader_guard('input', agent_file, {'trained_dqn.mat'});
reg = reader_guard('registration', reg_commit, docs_repo);
f_txt = fullfile(out_dir, 'combo_miss.txt'); f_mat = fullfile(out_dir, 'combo_miss.mat');
reader_guard('once', {f_txt, f_mat});
for f = {pools_file, agent_file, manifest_file}
    if ~isfile(f{1}), error('combo_miss_diag:input', 'combo_miss_diag: %s not found', f{1}); end
end
if ~isfolder(out_dir), mkdir(out_dir); end

%% Inputs
h_agent = reader_guard('sha', agent_file);
h_man = reader_guard('manifest', manifest_file, 'trained_dqn.mat');
if ~strcmpi(h_agent, h_man)
    error('combo_miss_diag:sha', 'combo_miss_diag: %s sha256 %s differs from the manifest (%s)', agent_file, h_agent, h_man);
end
code = {'combo_miss_tables.m', 'combo_miss_diag.m', 'det_frames.m', 'boot_cluster.m', 'reader_guard.m'};
h_code = cellfun(@(f) reader_guard('sha', which(f)), code, 'UniformOutput', false);
dp = dir(pools_file);
h_pools = reader_guard('sha', pools_file);
L = load(pools_file, 'PP'); PP = L.PP; clear L
PP = reader_guard('strip', PP, VAL);
present = PAIRS(cellfun(@(q) any(strcmp(PP.scen, q)), PAIRS));
if numel(present) < numel(PAIRS) && ~dry
    error('combo_miss_diag:pairs', 'combo_miss_diag: the pools hold no cell for %s', strjoin(setdiff(PAIRS, present, 'stable'), ', '));
end
if isempty(present), error('combo_miss_diag:pairs', 'combo_miss_diag: the pools hold none of the pairs'); end
PAIRS = present;
Q = load(agent_file, 'det_id', 'dec', 'confirm', 'alarm_mode', 'drop_db', 'maha_thr', 'deployed', 'rule_sel');
check_det_id(PP, Q, 'combo_miss_diag');
MON = Q; if strcmp(Q.deployed, 'rule_sel'), MON = Q.rule_sel; end
PP = decision_settings(PP, MON);
K = link_env('tables', PP, 'flight');
nS = numel(PP.ebno);
cls_names = reshape(cellstr(string(PP.classes)), 1, []);
ncls = numel(cls_names);
acts = cellfun(@(x) rule_based_policy(x), cls_names, 'UniformOutput', false);
fam = ismember(cls_names, LEVEL); br = ismember(cls_names, BRANCH);
none_idx = find(strcmp(cls_names, 'none'), 1); pl_all = find(strcmp(cls_names, 'path_loss'), 1);
if isempty(none_idx) || isempty(pl_all), error('combo_miss_diag:classes', 'combo_miss_diag: the detector has no class none or path_loss'); end
mode = ''; if isfield(PP, 'alarm_mode'), mode = PP.alarm_mode; end
use_drop = any(strcmp(mode, {'class_drop', 'class_cusum'}));
PPc = PP; PPc.alarm_mode = 'class';
HM = reshape(~(K.restored(:, :, K.na, VAL, :) & K.restored_plr(:, :, K.na, VAL, :)), ...
    size(K.restored, 1), size(K.restored, 2), size(K.restored, 5));
pm = struct('J', {}, 'Lc', {}, 'fam', {}, 'none_idx', {}, 'drop_used', {}, 'pl_idx', {});
for p = 1:numel(PAIRS)
    comps = strsplit(PAIRS{p}, '+');
    lev = ismember(comps, LEVEL);
    jam_acts = cellfun(@(x) rule_based_policy(x), comps(~lev), 'UniformOutput', false);
    pm(p).J = ismember(acts, jam_acts) & ~br;
    pm(p).Lc = 0; lc = comps(lev);
    if ~isempty(lc), pm(p).Lc = find(strcmp(cls_names, lc{1}), 1); end
    pm(p).fam = fam; pm(p).none_idx = none_idx;
    pm(p).pl_idx = 0; if any(strcmp(comps, 'path_loss')), pm(p).pl_idx = pl_all; end
    pm(p).drop_used = use_drop && pm(p).pl_idx > 0;
end
rep = {};
rep{end+1} = '=== R5: combined threats, which class the monitor reads where DET misses (D116 item 2), validation pools of profile 1 ===';
rep{end+1} = sprintf('Generated %s | code %s', datestr(now, 'yyyy-mm-dd HH:MM:SS'), git_head(root));
rep{end+1} = sprintf('Registration commit %s (D110-D118); rule code sha256: %s', reg, strjoin(cellfun(@(f, h) [f ' ' h], code, h_code, ...
    'UniformOutput', false), ' | '));
rep{end+1} = sprintf('Pools %s, %d bytes, modified %s, sha256 %s; every split but the validation one emptied on load', ...
    pools_file, dp.bytes, dp.date, h_pools);
rep{end+1} = sprintf('Agent %s sha256 %s (matches %s), read for the monitor''s settings only; det_id match; alarm mode %s, fusion window %d', ...
    agent_file, h_agent, manifest_file, mode, PP.fuse_N);
rep{end+1} = sprintf(['Descriptive, validation pools at no_action, no test split read; no profile 1 or profile 3 number changes and no threshold ' ...
    'is chosen from it. Pairs read: %s%s'], strjoin(PAIRS, ', '), ternary(dry, ' (DRY RUN: pairs the pools lack are left out)', ''));
rep{end+1} = ['Harmed (DET_h, DET_u): no response does not restore the flight against that flight''s own clean link, as edge_map.m ' ...
    'reads DET_h (82.2%)'];
fprintf('%s\n', rep{:});

%% Frames
blocks = {}; agree = true;
for p = 1:numel(PAIRS)
    cells = find(strcmp(PP.scen, PAIRS{p}));
    ok_row = det_classes(cls_names, acts, PAIRS{p});
    ok1 = ok_row(1, :); if pm(p).drop_used, ok1(pl_all) = false; end
    for c = cells(:)'
        for s = 1:nS
            P = PP.pools{c, s, K.na, VAL};
            if isempty(P) || isempty(P.ber), continue; end
            Pc = PP.pools{K.clean, s, K.na, VAL};
            [hit, on, ~, age] = det_frames(P, Pc, PAIRS{p}, ok_row(1, :), PP, PP.runs{VAL}, K.ev{VAL});
            h1 = det_frames(P, Pc, PAIRS{p}, eye(ncls) == 1, PPc, PP.runs{VAL}, K.ev{VAL});
            h2 = det_frames(P, Pc, PAIRS{p}, false(1, ncls), PP, PP.runs{VAL}, K.ev{VAL});
            [~, cl] = max(h1, [], 2); cl(~any(h1, 2)) = 0;
            [~, ridx] = ismember(P.run, PP.runs{VAL});
            if any(ridx(on) == 0), error('combo_miss_diag:runs', 'combo_miss_diag: a frame of %s belongs to no validation geometry', PAIRS{p}); end
            if any(cl(on) == 0), error('combo_miss_diag:unread', 'combo_miss_diag: a threat-active frame of %s has no class', PAIRS{p}); end
            m = on(:);
            okc = ok1(cl(m)); okc = okc(:);
            agree = agree && isequal(hit(m, 1), okc | h2(m, 1));
            n = sum(m);
            hm = HM(sub2ind(size(HM), c + 0 * ridx(m), s + 0 * ridx(m), ridx(m)));
            blocks{end+1} = struct('pair', p + zeros(n, 1), 's', s + zeros(n, 1), 'flight', 1000 * s + ridx(m), 'age', age(m), ...
                'cls', cl(m), 'dr', h2(m, 1), 'hit', hit(m, 1), 'harmed', hm(:), 'on', true(n, 1)); %#ok<AGROW>
        end
    end
    fprintf('  %s: %d cells read\n', PAIRS{p}, numel(cells));
end
F = struct();
for f = fieldnames(blocks{1})'
    F.(f{1}) = cell2mat(cellfun(@(b) b.(f{1}), blocks(:), 'UniformOutput', false));
end
rep{end+1} = sprintf(['Frames: %d threat-active frames of %d pairs; the three readings of det_frames.m agree (the registered hit equals ' ...
    'the class under the monitor''s class alone or the drop alarm): %s'], numel(F.hit), numel(PAIRS), ternary(agree, 'yes', 'NO'));
fprintf('%s\n', rep{end});

%% Tables
M = struct('pairs', {PAIRS}, 'classes', {cls_names}, 'pm', pm, 'fuse_N', PP.fuse_N, 'ebno', PP.ebno, 'det_h_read', DET_H_READ);
C = struct('B', 2000, 'seed', SEED_BOOT);
T = combo_miss_tables('tables', F, M, C);
body = combo_miss_tables('lines', T, M, C);
rep{end+1} = sprintf('Total %.1f min', toc(t_all) / 60);
lines = [rep(1:end-1), {''}, body, {''}, rep(end)];

%% Output
fid = fopen(f_txt, 'w'); fprintf(fid, '%s\n', lines{:}); fclose(fid);
fprintf('\n%s\n', lines{:});
meta = struct('pools_file', pools_file, 'pools_bytes', dp.bytes, 'pools_date', dp.date, 'pools_sha256', h_pools, 'agent_sha256', h_agent, ...
    'reg_commit', reg, 'code', {code}, 'code_sha256', {h_code}, 'seed_boot', SEED_BOOT, 'alarm_mode', mode, ...
    'readings_agree', agree, 'created', PP.created);
save(f_mat, 'meta', 'F', 'M', 'C', 'T', 'lines');
fprintf('Saved %s and %s\n', f_txt, f_mat);
end

function ok = det_classes(classes, acts, scen)
% Classes DET counts for a threat (row 1) and at the branch level (row 2), as edge_map.m counts them:
% the classes whose countermeasure one of the threat's components calls for; in row 1 an antenna
% fault and airframe shadowing count only as themselves.
classes = reshape(cellstr(string(classes)), 1, []); acts = reshape(acts, 1, []);
comps = strsplit(scen, '+');
okb = ismember(acts, cellfun(@(x) rule_based_policy(x), comps, 'UniformOutput', false));
br = ismember(classes, {'antenna_fault', 'airframe_shadowing'});
ok = [okb & (~br | ismember(classes, comps)); okb];
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end

function h = git_head(root)
[st, h] = system(sprintf('git -C "%s" rev-parse --short HEAD', root));
h = strtrim(h); if st ~= 0, h = 'unknown'; end
end
