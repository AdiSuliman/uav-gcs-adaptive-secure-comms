function spd_d_diag(pools_file, agent_file, manifest_file, out_dir, reg_commit, docs_repo, cov_registered)
%SPD_D_DIAG  SPD-D: where the speed deficit of the deployed DQN comes from, on copies of profile 1's train
%   and validation pools. Descriptive: it chooses nothing and changes no file of the
%   pipeline; the routing table it prints is advisory.
%   spd_d_diag(pools_file, agent_file, manifest_file, out_dir, reg_commit, docs_repo, cov_registered)
%   pools_file     a copy of data/policy_pools.mat; its test, edge-speed and second test splits are emptied
%                  on load (reader_guard.m) and nothing of them is read
%   agent_file     the archived trained_dqn.mat; its sha256 must match its line in manifest_file
%   out_dir        under <repo>/results (default <repo>/results): spd_d.txt and spd_d.mat, written once
%   reg_commit     the commit that registers these readings (hex); docs_repo, if given, is checked for it
%                  (without it the log says the commit is unverified)
%   cov_registered true: a dated registration fixes the share of the coverage branch's second clause, and the
%                  branch may be raised; default false: it is printed and never raised
%   Episodes: the single threats of the pools, as evaluate_policies.m flies its single set, on the train and
%   the validation split, two onsets per flight; the deployed DQN and no response on the same episodes and
%   frame draws. The train split is in sample for the DQN and the validation split chose it; the profile has
%   three antennas, so the routing is indicative for profile 3.
%   Per episode: speed band, bank band (PP.cov), recoverable, harmed (no response does not restore the
%   geometry), recovered, the restoring set R (configurations restoring BER and packet loss) and its
%   families, the configuration the DQN ends on, and whether the flight belongs to the shadowing group.
%   The clean link's FER per flight at the working Eb/N0 points (PP.clean_fer < 0.1) feeds the Doppler row.
%   The monitor's clean reference is copied into the run folder first (reader_guard.m 'ref').
SEED_EP = 2160;                 % onset and follower draws of a split: + split
SEED_RUN = 410000;              % frame draws of a split's batches: + 1000 split + batch
t_all = tic;
root = project_root();
if nargin < 4 || isempty(out_dir), out_dir = fullfile(root, 'results'); end
if nargin < 5, reg_commit = ''; end
if nargin < 6, docs_repo = ''; end
if nargin < 7 || isempty(cov_registered), cov_registered = false; end
cov_registered = logical(cov_registered);
out_dir = reader_guard('out', out_dir, root);
reader_guard('input', pools_file, {'policy_pools.mat'});
reader_guard('input', agent_file, {'trained_dqn.mat'});
reg = reader_guard('registration', reg_commit, docs_repo);
f_txt = fullfile(out_dir, 'spd_d.txt'); f_mat = fullfile(out_dir, 'spd_d.mat');
reader_guard('once', {f_txt, f_mat});
for f = {pools_file, agent_file, manifest_file}
    if ~isfile(f{1}), error('spd_d_diag:input', 'spd_d_diag: %s not found', f{1}); end
end
if ~isfolder(out_dir), mkdir(out_dir); end

%% Inputs
h_agent = reader_guard('sha', agent_file);
h_man = reader_guard('manifest', manifest_file, 'trained_dqn.mat');
if ~strcmpi(h_agent, h_man)
    error('spd_d_diag:sha', 'spd_d_diag: %s sha256 %s differs from the manifest (%s)', agent_file, h_agent, h_man);
end
code = {'spd_d_tables.m', 'spd_d_diag.m', 'cluster_contrast.m', 'boot_cluster.m', 'reader_guard.m'};
h_code = cellfun(@(f) reader_guard('sha', which(f)), code, 'UniformOutput', false);
dp = dir(pools_file);
h_pools = reader_guard('sha', pools_file);
ref_file = reader_guard('ref', pools_file, root);
L = load(pools_file, 'PP'); PP = L.PP; clear L
PP = reader_guard('strip', PP, [1 2]);
Q = load(agent_file, 'agent', 'agents', 'gammas', 'H', 'seed_summary', 'deployed', 'det_id', 'dec', 'confirm', ...
    'alarm_mode', 'drop_db', 'maha_thr', 'rule_sel');
check_det_id(PP, Q, 'spd_d_diag');
if ~ismember(Q.deployed, {'dqn', 'dqn_esc'})
    error('spd_d_diag:deployed', 'spd_d_diag: the deployed policy is %s, not a DQN', Q.deployed);
end
if ~isfield(PP, 'cov') || numel(PP.cov) < 2 || ~isfield(PP.cov{1}, 'bank') || ~isfield(PP.cov{2}, 'bank')
    error('spd_d_diag:cov', 'spd_d_diag: the pools record no per-flight bank (PP.cov)');
end
sel = find(Q.gammas == Q.seed_summary.selected_gamma, 1);
dep = Q.deployed; if strcmp(dep, 'dqn'), dep = sprintf('dqn_g%d', sel); end
PP = decision_settings(PP, Q);
K = link_env('tables', PP);
T = Q.H.T; NE = 64; REPS = 2; nS = numel(PP.ebno); nA = numel(PP.actions);
[kind_d, ag_d, opt_d] = policy_setup(dep, Q, sel, [], [], [], K.na);
[kind_n, ag_n, opt_n] = policy_setup('none', Q, sel, [], [], [], K.na);
single_cells = find(ismember(PP.scen, PP.singles) & ~strcmp(PP.scen, 'none'));
[sc_cfg, bud_cfg] = spd_d_tables('families', PP.actions);
okA = K.restored & K.restored_plr;
rep = {};
rep{end+1} = '=== SPD-D: speed decomposition on profile 1''s train and validation pools (D116 item 7), descriptive ===';
rep{end+1} = sprintf('Generated %s | code %s', datestr(now, 'yyyy-mm-dd HH:MM:SS'), git_head(root));
rep{end+1} = sprintf('Registration commit %s (D110-D118); rule code sha256: %s', reg, strjoin(cellfun(@(f, h) [f ' ' h], code, h_code, ...
    'UniformOutput', false), ' | '));
rep{end+1} = sprintf('Pools %s, %d bytes, modified %s, sha256 %s; the test, edge-speed and second test splits emptied on load', ...
    pools_file, dp.bytes, dp.date, h_pools);
rep{end+1} = sprintf('Agent %s sha256 %s (matches %s); deployed policy %s, selected gamma %.2f; det_id match', agent_file, h_agent, ...
    manifest_file, dep, Q.gammas(sel));
rep{end+1} = sprintf('Monitor clean reference (clean_ber_ref.m): clean_ref of the pools copied alone to %s, current folder %s, reference checked', ...
    ref_file, pwd);
rep{end+1} = ['Labels: the train split is in sample for the DQN; the validation split chose it (train_dqn.m); the profile has three ' ...
    'antennas, profile 3 four, so the routing is advisory and indicative for profile 3. Descriptive: nothing is selected on these tables.'];
rep{end+1} = sprintf('Coverage branch (C-LHS): the share of its second clause is %s in D116 item 7; the branch is %s', ...
    ternary(cov_registered, 'registered', 'not registered'), ternary(cov_registered, 'raised when met', 'printed and never raised'));
fprintf('%s\n', rep{:});

%% Episodes and per-episode facts
fn = {'thr', 'split', 'geom', 's', 'speed', 'bank', 'rec', 'harmed', 'recovered', 'nR', 'r_sc', 'r_only', 'cfg_end', 'shadow_fl'};
E = cell2struct(cell(numel(fn), 1), fn(:), 1);
cons = true; n_thr = [0 0];
for sp = [1 2]
    rs = RandStream('mt19937ar', 'Seed', SEED_EP + sp);
    spec = policy_episodes(single_cells, nS, K.geo(single_cells, sp), REPS, false, false, NE, T, rs);
    t1 = tic;
    Rd = policy_run_set(kind_d, PP, K, spec, sp, ag_d, opt_d, SEED_RUN + 1000 * sp);
    Rn = policy_run_set(kind_n, PP, K, spec, sp, ag_n, opt_n, SEED_RUN + 1000 * sp);
    fprintf('  split %d: %d episodes x 2 policies (%.1f min)\n', sp, numel(Rd.ret), toc(t1) / 60);
    m = Rd.threat;
    n_thr(sp) = sum(m);
    ih = sub2ind(size(K.restored), Rd.scn, Rd.s, K.na + 0 * Rd.s, Rd.split, Rd.r);
    harmed = ~(K.restored(ih) & K.restored_plr(ih));
    cons = cons && isequal(harmed(m), ~Rn.recovered(m));
    ok = false(nA, numel(Rd.scn));
    for i = find(m)
        ok(:, i) = squeeze(okA(Rd.scn(i), Rd.s(i), :, Rd.split(i), Rd.r(i)));
    end
    [nR, r_sc, r_only] = spd_d_tables('restoring', ok, sc_cfg, bud_cfg);
    bk = PP.cov{sp}.bank;
    sh_r = [];
    for c = find(contains(PP.scen, 'airframe_shadowing'))
        sh_r = union(sh_r, K.geo{c, sp});
    end
    sh_r = setdiff(sh_r, K.geo{K.clean, sp});
    thr = reshape(PP.scen(Rd.scn), 1, []);
    blk = struct('thr', {thr(m)'}, 'split', Rd.split(m)', 'geom', Rd.geom(m)' + 1e6 * sp, 's', Rd.s(m)', 'speed', Rd.speed(m)', ...
        'bank', bk(sub2ind(size(bk), Rd.s(m), Rd.r(m)))', 'rec', Rd.recoverable(m)', 'harmed', harmed(m)', ...
        'recovered', Rd.recovered(m)', 'nR', nR(m)', 'r_sc', r_sc(m)', 'r_only', r_only(m)', 'cfg_end', Rd.cfg_final(m)', ...
        'shadow_fl', ismember(Rd.r(m), sh_r)');
    for f = fn
        if isempty(E.(f{1})), E.(f{1}) = blk.(f{1}); else, E.(f{1}) = [E.(f{1}); blk.(f{1})]; end
    end
    clear Rd Rn ok
end
E.na = K.na; E.actions = PP.actions(:)'; E.sc_cfg = sc_cfg;
rep{end+1} = sprintf(['Episodes: %d single-threat episodes on the air (train %d, validation %d), %d recoverable; two onsets per flight; ' ...
    'no response and the deployed DQN on the same draws; harmed agrees with no response''s recovery: %s'], ...
    sum(n_thr), n_thr(1), n_thr(2), sum(E.rec), ternary(cons, 'yes', 'NO'));
fprintf('%s\n', rep{end});

%% Clean-link FER at the working points
CL = struct('speed', zeros(0, 1), 'bank', zeros(0, 1), 'fer', zeros(0, 1), 'geom', zeros(0, 1));
work = find(PP.clean_fer(:)' < 0.1);
for sp = [1 2]
    for s = work
        P = PP.pools{K.clean, s, K.na, sp};
        if isempty(P) || isempty(P.ber), continue; end
        for r = K.geo{K.clean, sp}(:)'
            k = P.run == PP.runs{sp}(r);
            if ~any(k), continue; end
            CL.fer(end+1, 1) = mean(double(P.fer(k)));
            CL.speed(end+1, 1) = PP.speed{sp}(s, r);
            CL.bank(end+1, 1) = PP.cov{sp}.bank(s, r);
            CL.geom(end+1, 1) = 1e6 * sp + 1000 * s + r;
        end
    end
end
rep{end+1} = sprintf('Clean link: %d flight readings at the working Eb/N0 points (clean FER < 0.1: %s dB) for the Doppler row', ...
    numel(CL.fer), strjoin(arrayfun(@(e) sprintf('%g', e), PP.ebno(work), 'UniformOutput', false), ', '));

%% Tables
C = spd_d_tables('config', PP.speed_range);
C.cov_registered = cov_registered;
Tb = spd_d_tables('tables', E, CL, C);
body = spd_d_tables('lines', Tb, C);
rep{end+1} = sprintf('Total %.1f min', toc(t_all) / 60);
lines = [rep(1:end-1), {''}, body, {''}, rep(end)];

%% Output
fid = fopen(f_txt, 'w'); fprintf(fid, '%s\n', lines{:}); fclose(fid);
fprintf('\n%s\n', lines{:});
meta = struct('pools_file', pools_file, 'pools_bytes', dp.bytes, 'pools_date', dp.date, 'pools_sha256', h_pools, 'agent_sha256', h_agent, ...
    'deployed', dep, 'reg_commit', reg, 'code', {code}, 'code_sha256', {h_code}, 'seed_ep', SEED_EP, 'seed_run', SEED_RUN, ...
    'reps', REPS, 'cov_registered', cov_registered, 'harmed_consistent', cons, 'ebno', PP.ebno, 'clean_fer', PP.clean_fer, 'created', PP.created);
save(f_mat, 'meta', 'E', 'CL', 'Tb', 'C', 'lines');
fprintf('Saved %s and %s\n', f_txt, f_mat);
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end

function h = git_head(root)
[st, h] = system(sprintf('git -C "%s" rev-parse --short HEAD', root));
h = strtrim(h); if st ~= 0, h = 'unknown'; end
end
