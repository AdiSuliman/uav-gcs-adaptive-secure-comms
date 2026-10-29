function varargout = system_fa_breakdown(cmd, varargin)
%SYSTEM_FA_BREAKDOWN  The system-level false alarms on clean flights (our KPI 6, an extension)
%   broken down, and the pre-onset sensitivity of the lecturer's readings (DECISIONS D103 points
%   3-6, docs/system_fa_protocol.md). Reporting only: lect_kpis.m runs unchanged on subsets of
%   the saved episodes, far_report is evaluate_policies.m's; no verdict, threshold or KPI changes.
%   system_fa_breakdown('run', pools, eval_mat, eval_txt, dqn_mat, out_dir)
%       pools     the post-M data/policy_pools.mat C2e read (PP.ebno, scen, clean_fer, det_id)
%       eval_mat, eval_txt  C2e's results/policy_evaluation.mat and .txt
%       dqn_mat   the data/trained_dqn.mat C2e read: each policy's monitor (confirmation, the
%                 sweeper's own confirmation, alarm mode), checked against KP.policy_stamp
%       out_dir   the reading copy's results folder
%       Absolute paths; the inputs are only read. The gate, then only on a pass the readings ->
%       out_dir/system_fa_breakdown.{txt,mat}. Once: refused when they exist. A failed gate writes
%       out_dir/system_fa_breakdown.gatefail.{txt,mat} (the diagnostics) and stops with
%       system_fa_breakdown:gate; it creates no reading output, so the reading stays open. The
%       header names the thread count the session really has.
%       KPI 6's flights follow KP.far_set: without it the union of C2e's clean flights (profile
%       1); 'fresh' the fresh clean test set RWf alone (P1R's C2e, evaluate_policies.m with
%       kpi6_set fresh, KP.reading 'P1R', the lecturer lines carrying P1R's label).
%   G = system_fa_breakdown('gate', E, PP, Q, txt)
%       E the variables of eval_mat, Q those of dqn_mat, txt eval_txt one cell per line. G.pass
%       when lect_kpis.m on every episode gives KP.lect and its lines of txt, far_report on
%       KPI 6's clean flights gives KP.far, KP.far_diag and their lines, and policy_stamp(Q) is
%       KP.policy_stamp; exact (isequaln), no tolerance. G.mismatch
%   [R, lines] = system_fa_breakdown('readings', E, PP, M, G)   D103 3, 4(a)-(c) and 5
%   [B, lines] = system_fa_breakdown('breakdown', E, PP, G)     D103 3(a)-(e)
%   [S, lines] = system_fa_breakdown('sensitivity', E, PP, M, G) D103 4(a)-(c)
%   [CO, lines] = system_fa_breakdown('carried', E, PP, G)      D103 5
%   [ce, am] = system_fa_breakdown('carry_counts', t_conf, mon)
%       ce: t_conf below min(m, k) - 1, an alarm cycle before the onset; am: below m - 1 but not
%       ce, the sweeper's own k-of-n path or a carried-over alarm (m-of-n the confirmation)
%   [mon, mm] = system_fa_breakdown('monitors', POL, PP, Q)    each policy's monitor as it ran
%   [p6, cmp] = system_fa_breakdown('policies', POL, iDQN)
%       p6 D103 3's six policies; cmp the policies lect_kpis.m reads but the oracle
%   pre = system_fa_breakdown('pre_onset', R)
%       first change at cycle 1..onset: the decision of cycle t reads frame t - 1, so it was
%       decided on clean frames only (rollout_policy.m)
%   M = system_fa_breakdown('mark', clean_fer, ratio_ok)        D99 R1's link-limited points
%   A = system_fa_breakdown('subset', ALL, keep)                episode i stays paired
%   [FAR, FD, lines] = system_fa_breakdown('far', RR, POL, LBL, above, T, iDQN, ebno, cls_list, period_ms)
%       evaluate_policies.m's far_report, byte for byte
%   h = system_fa_breakdown('sha', f)    SHA-256 of a file, as sha256sum prints it
switch cmd
    case 'run',          run_reading(varargin{:});
    case 'gate',         varargout{1} = gate(varargin{:});
    case 'readings',     [varargout{1}, varargout{2}] = readings(varargin{:});
    case 'breakdown',    [varargout{1}, varargout{2}] = breakdown(varargin{:});
    case 'sensitivity',  [varargout{1}, varargout{2}] = sensitivity(varargin{:});
    case 'carried',      [varargout{1}, varargout{2}] = carried(varargin{:});
    case 'carry_counts', [varargout{1}, varargout{2}] = carry_counts(varargin{:});
    case 'monitors',     [varargout{1}, varargout{2}] = monitors(varargin{:});
    case 'policies',     [varargout{1}, varargout{2}] = policy_sets(varargin{:});
    case 'pre_onset',    varargout{1} = pre_onset(varargin{:});
    case 'mark',         varargout{1} = mark(varargin{:});
    case 'subset',       varargout{1} = subset(varargin{:});
    case 'far',          [varargout{1}, varargout{2}, varargout{3}] = far_report(varargin{:});
    case 'sha',          varargout{1} = file_sha(varargin{:});
    otherwise, error('system_fa_breakdown:cmd', 'system_fa_breakdown: unknown command %s', cmd);
end
end

%% ===================== The single run =====================
function run_reading(pools, eval_mat, eval_txt, dqn_mat, out_dir)
for f = {pools, eval_mat, eval_txt, dqn_mat}
    assert(is_abs(f{1}) && isfile(f{1}), 'system_fa_breakdown:input', '%s: not an absolute path of a file', f{1});
end
assert(is_abs(out_dir) && isfolder(out_dir), 'system_fa_breakdown:input', '%s: not an absolute path of a folder', out_dir);
fo = fullfile(out_dir, 'system_fa_breakdown.txt'); fm = fullfile(out_dir, 'system_fa_breakdown.mat');
ff = fullfile(out_dir, 'system_fa_breakdown.gatefail.txt'); fg = fullfile(out_dir, 'system_fa_breakdown.gatefail.mat');
assert(~isfile(fo) && ~isfile(fm), 'system_fa_breakdown:once', '%s exists: the reading runs once', fo);
[nthr, thr_how] = thread_info();
inp = {pools, eval_mat, eval_txt, dqn_mat};
st0 = stamps(inp);

% The pools: the Eb/N0 grid, scenarios, clean packet loss (the mark) and monitor settings
h_pools = file_sha(pools);
Lp = load(pools, 'PP');
PP = struct('ebno', Lp.PP.ebno, 'scen', {Lp.PP.scen}, 'clean_fer', Lp.PP.clean_fer, 'det_id', field_or(Lp.PP, 'det_id', ''));
for f = {'alarm_mode', 'confirm', 'drop_db', 'confirm_sweep'}
    if isfield(Lp.PP, f{1}), PP.(f{1}) = Lp.PP.(f{1}); end
end
clear Lp
M = mark(PP.clean_fer, decision_config().ratio_ok);

% The trained policy, C2e's results, the gate
h_dqn = file_sha(dqn_mat); h_mat = file_sha(eval_mat); h_txt = file_sha(eval_txt);
qv = {'agent', 'deployed', 'alarm_mode', 'confirm', 'drop_db', 'rule_sel', 'det_id', 'maha_thr', 'dec'};
w = warning('off', 'MATLAB:load:variableNotFound');
Q = load(dqn_mat, qv{:});
warning(w);
E = load(eval_mat, 'ALL', 'POL', 'LBL', 'iDQN', 'KP', 'RES', 'RW', 'set_names');
fresh = isfield(E, 'KP') && far_def(E.KP);
if fresh                                             % P1R: KPI 6's flights are RWf
    w = warning('off', 'MATLAB:load:variableNotFound');
    Lf = load(eval_mat, 'RWf');
    warning(w);
    if isfield(Lf, 'RWf'), E.RWf = Lf.RWf; end
    clear Lf
end
txt = read_lines(eval_txt);
head = {['=== System-level false alarms (our KPI 6) broken down, and the pre-onset sensitivity of the lecturer''s ' ...
    'readings (D103 3-6, docs/system_fa_protocol.md): reporting only, no verdict changes ==='], ...
    sprintf('pools %s sha256 %s', pools, h_pools), sprintf('evaluation %s sha256 %s', eval_mat, h_mat), ...
    sprintf('text %s sha256 %s', eval_txt, h_txt), sprintf('trained policy %s sha256 %s', dqn_mat, h_dqn), ...
    sprintf('threads %d (%s)', nthr, thr_how)};
if fresh
    head{end+1} = sprintf(['P1R (KP.reading P1R, KP.far_set fresh): KPI 6''s flights are %s; D103 3 reads them, ' ...
        'D103 4 and 5 read test pools already read in profile 1''s C2e (second reading, descriptive)'], ...
        char(string(field_or(E.KP, 'far_src', '?'))));
end
G = gate(E, PP, Q, txt);
if ~G.pass
    lines = [{sprintf('GATE FAIL (%d mismatches): nothing of D103 3-5 is read; no reading output was written, the reading stays open', ...
        numel(G.mismatch))}, head, G.mismatch];
    keep_old(ff); keep_old(fg);
    write_lines(ff, lines);
    G = rmfield(G, 'RU');
    save(fg, 'M', 'G', 'lines', 'h_pools', 'h_mat', 'h_txt', 'h_dqn', 'nthr', 'thr_how', 'pools', 'eval_mat', 'eval_txt', 'dqn_mat');
    if fresh, far_set = 'fresh'; save(fg, 'far_set', '-append'); end
    fprintf('%s\n', lines{:});
    error('system_fa_breakdown:gate', 'the gate failed: %s', ff);
end
[R, body] = readings(E, PP, M, G);
assert(isequal(st0, stamps(inp)), 'system_fa_breakdown:inputs', 'an input changed during the reading');
lines = [{gate_pass_line(fresh)}, head, body];
write_lines(fo, lines);
G = rmfield(G, 'RU');
save(fm, 'M', 'G', 'R', 'lines', 'h_pools', 'h_mat', 'h_txt', 'h_dqn', 'nthr', 'thr_how', 'pools', 'eval_mat', 'eval_txt', 'dqn_mat');
if fresh, far_set = 'fresh'; save(fm, 'far_set', '-append'); end
fprintf('%s\n', lines{:});
fprintf('Saved %s, %s\n', fo, fm);
end

function s = gate_pass_line(fresh)
s = ['GATE PASS: lect_kpis.m reproduces KP.lect, far_report reproduces KP.far and KP.far_diag, the ' ...
    'trained policy is KP.policy_stamp, exactly'];
if fresh
    s = ['GATE PASS: lect_kpis.m reproduces KP.lect and its lines with P1R''s label, far_report on the fresh clean ' ...
        'test set (RWf, KP.far_set fresh) reproduces KP.far and KP.far_diag, the trained policy is KP.policy_stamp, exactly'];
end
end

%% ===================== Gate =====================
function G = gate(E, PP, Q, txt)
G = struct('pass', false, 'mismatch', {{}}, 'lect', [], 'lect_lines', {{}}, 'far', [], 'far_diag', [], ...
    'far_lines', {{}}, 'T', NaN, 'RU', {{}}, 'aboveU', [], 'mon', [], 'p6', [], 'cmp', []);
txt = norm_lines(txt);
need = {'ALL', 'POL', 'LBL', 'iDQN', 'KP', 'RES', 'RW', 'set_names'};
miss = need(~isfield(E, need));
if ~isempty(miss), G.mismatch = {sprintf('the evaluation lacks %s', strjoin(miss, ', '))}; return; end
KP = E.KP;
need = {'lect', 'far', 'far_diag', 'far_src', 'ebno', 'ebno_thr', 'cls_list', 'confirm', 'alarm_mode', 'policy_stamp'};
miss = need(~isfield(KP, need));
if ~isempty(miss), G.mismatch = {sprintf('KP lacks %s', strjoin(miss, ', '))}; return; end
[fresh, mm] = far_def(KP);
if ~isempty(mm), G.mismatch = mm; return; end
if ~isequal(double(KP.ebno), double(PP.ebno)), mm{end+1} = 'KP.ebno is not the pools'' Eb/N0 grid'; end
if isfield(KP, 'det_id') && ~isequal(KP.det_id, PP.det_id)
    mm{end+1} = sprintf('KP.det_id %s is not the pools'' %s', char(string(KP.det_id)), char(string(PP.det_id)));
end
st = policy_stamp(Q);
if ~isequal(st, KP.policy_stamp)
    mm{end+1} = sprintf('policy_stamp of the trained policy %s is not KP.policy_stamp %s', st, char(string(KP.policy_stamp)));
end
[mon, m2] = monitors(E.POL, PP, Q); mm = [mm, m2];
i = find(~strcmp(E.POL, 'rule_sel'), 1);
if isempty(m2) && (~isequal(mon(i).confirm, double(KP.confirm(:)')) || ~strcmp(mon(i).alarm_mode, char(KP.alarm_mode)))
    mm{end+1} = sprintf('the monitor rebuilt from the trained policy (%s, %s) is not KP''s (%s, %s)', mon(i).alarm_mode, ...
        mat2str(mon(i).confirm), char(KP.alarm_mode), mat2str(double(KP.confirm)));
end
mm = [mm, has_fields(E.ALL, E.POL, {'s', 'geom', 'scn', 'onset', 'switches', 'fc_t', 't_conf', 'recoverable', 'threat'}, 'ALL')];
if isempty(mm), mm = pairing(E.ALL, E.POL, {'s', 'geom', 'scn', 'onset'}, 'ALL'); end
if isempty(mm) && any(floor(E.ALL{1}.geom / 1000) ~= E.ALL{1}.s), mm{end+1} = 'a flight geometry (1000 s + r) spans two Eb/N0 points'; end
if ~isempty(mm), G.mismatch = mm; return; end

% lect_kpis.m on every episode: KP.lect and its lines
[Lf, lf] = lect_kpis(E.ALL, E.POL, E.LBL, E.iDQN, PP.scen, KP.lect.payload_bps, KP.lect.period_ms);
lf = norm_lines(lf);
if fresh, lf = p1r_label(lf); end
mm = [mm, differs(Lf, KP.lect, 'lect_kpis on every episode vs KP.lect')];
i = find(strcmp(txt, lf{2}));
if numel(i) ~= 1
    mm{end+1} = sprintf('the text holds lect_kpis''s header %d times, not once', numel(i));
else
    mm = [mm, block_diff(txt, lf, i - 1, 'lect_kpis''s lines')];
end

% far_report on KPI 6's clean flights: KP.far, KP.far_diag and their lines
if fresh
    [RU, aU, m2] = fresh_ru(E, PP, KP);
else
    [RU, aU, m2] = union_ru(E, PP, KP);
end
mm = [mm, m2];
if isempty(m2), m2 = pairing(RU, E.POL, {'s', 'geom', 'split'}, 'RU'); mm = [mm, m2]; end
T = 0; n = [KP.far.n]; j = find(n > 0, 1);
if ~isempty(j), T = KP.far(j).rate.cycles / n(j); end
if T ~= round(T), mm{end+1} = sprintf('KP.far gives %g cycles per episode', T); end
if isempty(m2)
    [Ff, FDf, lfar] = far_report(RU, E.POL, E.LBL, aU, T, E.iDQN, PP.ebno, KP.cls_list, KP.lect.period_ms);
    mm = [mm, differs(Ff, KP.far, 'far_report on KPI 6''s clean flights vs KP.far'), ...
        differs(FDf, KP.far_diag, 'far_report on KPI 6''s clean flights vs KP.far_diag')];
    hdr = sprintf('False alarms on the clean link, every independent clean flight: %s, %d episodes x %d cycles -> KPI 6', ...
        KP.far_src, sum(aU), T);
    if fresh
        hdr = sprintf('False alarms on the clean link, the fresh clean test set (P1R, read once): %s, %d episodes x %d cycles -> KPI 6', ...
            KP.far_src, sum(aU), T);
    end
    i = find(strcmp(txt, hdr));
    if numel(i) ~= 1
        mm{end+1} = sprintf('the text holds KPI 6''s header %d times, not once: %s', numel(i), hdr);
    else
        mm = [mm, block_diff(txt, norm_lines(lfar), i + 1, 'far_report''s lines')];
    end
    G.far = Ff; G.far_diag = FDf; G.far_lines = norm_lines(lfar);
end
[G.p6, G.cmp] = policy_sets(E.POL, E.iDQN);
G.pass = isempty(mm); G.mismatch = mm;
G.lect = Lf; G.lect_lines = lf; G.T = T; G.RU = RU; G.aboveU = aU; G.mon = mon;
end

function [mon, mm] = monitors(POL, PP, Q)
% Each policy's monitor as it ran: the pools' settings with the trained policy's
% (decision_settings.m, as evaluate_policies.m), the rule fallback's own on top (policy_decide.m
% opt.monitor); defaults as policy_monitor.m.
C = decision_config(); mm = {};
B = struct();
for f = {'alarm_mode', 'confirm', 'drop_db', 'confirm_sweep'}
    if isfield(PP, f{1}), B.(f{1}) = PP.(f{1}); end
end
B = decision_settings(B, Q);
mon = repmat(struct('alarm_mode', 'class', 'confirm', double(C.confirm(:)'), 'confirm_sweep', []), 1, numel(POL));
for pk = 1:numel(POL)
    S = B;
    if strcmp(POL{pk}, 'rule_sel')
        if ~isfield(Q, 'rule_sel') || ~isstruct(Q.rule_sel)
            mm{end+1} = 'POL holds rule_sel but the trained policy has no rule_sel'; %#ok<AGROW>
            continue
        end
        S = decision_settings(S, Q.rule_sel);
    end
    if isfield(S, 'alarm_mode') && ~isempty(S.alarm_mode), mon(pk).alarm_mode = char(S.alarm_mode); end
    if isfield(S, 'confirm') && ~isempty(S.confirm), mon(pk).confirm = double(S.confirm(:)'); end
    if isfield(S, 'confirm_sweep'), mon(pk).confirm_sweep = double(S.confirm_sweep(:)'); end
end
end

function [p6, cmp] = policy_sets(POL, iDQN)
% p6: D103 3's policies; cmp: the policies lect_kpis.m reads (kp, kr, kc), the oracle aside.
has = @(c) c(ismember(c, POL));
idx = @(c) cellfun(@(p) find(strcmp(POL, p), 1), c);
dep = POL{iDQN};
dqk = 'dqn_esc'; if startsWith(dep, 'dqn'), dqk = dep; end
p6 = idx(has(unique({'none', 'rule_esc', 'blind_esc', 'rule_core', 'blind_core', dep}, 'stable')));
cmp = idx(has(unique({'none', 'rule_esc', 'blind_esc', dqk, dep, 'rule_core', 'blind_core'}, 'stable')));
end

function mm = pairing(A, POL, f, name)
% The same episodes under every policy (fields f equal).
mm = {};
for k = 2:numel(A)
    if ~all(cellfun(@(x) isequal(A{k}.(x), A{1}.(x)), f))
        mm{end+1} = sprintf('%s{%d} (%s) does not hold the episodes of %s{1} (%s)', name, k, POL{k}, name, strjoin(f, ', ')); %#ok<AGROW>
    end
end
end

function mm = has_fields(A, POL, f, name)
mm = {};
for k = 1:numel(A)
    miss = f(~isfield(A{k}, f));
    if ~isempty(miss), mm{end+1} = sprintf('%s{%d} (%s) lacks %s', name, k, POL{k}, strjoin(miss, ', ')); end %#ok<AGROW>
end
end

function [RU, aU, mm] = union_ru(E, PP, KP)
% KPI 6's clean flights as evaluate_policies.m joins them: the test split's clean set, the
% second test split's and the clean pools' (split id 6), from the KPI 1 threshold up.
RU = {}; aU = []; mm = {};
iC = find(strcmp(E.set_names, 'clean')); iC2 = find(strcmp(E.set_names, 'clean2'));
if numel(iC) ~= 1, mm = {'set_names holds no single clean set'}; return; end
need = {'s', 'geom', 'split', 'switches', 'false_sw', 'fc_t', 'fc_cls', 'fc_deg', 'fc_dal', 'fc_drop'};
parts = {E.RES(iC, :), 'RES clean'};
if ~isempty(iC2), parts(end+1, :) = {E.RES(iC2, :), 'RES clean2'}; end
if ~isempty(E.RW), parts(end+1, :) = {E.RW, 'RW'}; end
for p = 1:size(parts, 1)
    mm = [mm, has_fields(parts{p, 1}, E.POL, need, parts{p, 2})]; %#ok<AGROW>
    for pk = 1:numel(E.POL)
        if ~isempty(setdiff(fieldnames(E.RES{iC, pk}), fieldnames(parts{p, 1}{pk})))
            mm{end+1} = sprintf('%s{%d} lacks fields of the clean set', parts{p, 2}, pk); %#ok<AGROW>
        end
    end
end
if ~isempty(mm), return; end
ebno_thr = KP.ebno_thr;
RU = E.RES(iC, :); aU = PP.ebno(RU{1}.s) >= ebno_thr;
if ~isempty(iC2)
    for pk = 1:numel(E.POL), RU{pk} = cat_struct(RU{pk}, E.RES{iC2, pk}); end
    aU = [aU, PP.ebno(E.RES{iC2, 1}.s) >= ebno_thr];
end
if ~isempty(E.RW)
    for pk = 1:numel(E.POL)
        Rw = E.RW{pk}; Rw.split(:) = 6;
        RU{pk} = cat_struct(RU{pk}, Rw);
    end
    aU = [aU, PP.ebno(E.RW{1}.s) >= ebno_thr];
end
aU = reshape(aU, 1, []);
end

function [RU, aU, mm] = fresh_ru(E, PP, KP)
% KPI 6's clean flights in P1R's C2e: the fresh clean test set alone (RWf, split id 7), from the
% KPI 1 threshold up.
RU = {}; aU = []; mm = {};
if ~isfield(E, 'RWf') || ~iscell(E.RWf) || numel(E.RWf) ~= numel(E.POL)
    mm = {'the evaluation lacks RWf, one fresh clean set per policy (KP.far_set fresh)'}; return
end
iC = find(strcmp(E.set_names, 'clean'));
if numel(iC) ~= 1, mm = {'set_names holds no single clean set'}; return; end
need = {'s', 'geom', 'split', 'switches', 'false_sw', 'fc_t', 'fc_cls', 'fc_deg', 'fc_dal', 'fc_drop'};
mm = has_fields(E.RWf, E.POL, need, 'RWf');
for pk = 1:numel(E.POL)
    if isstruct(E.RWf{pk}) && ~isempty(setdiff(fieldnames(E.RES{iC, pk}), fieldnames(E.RWf{pk})))
        mm{end+1} = sprintf('RWf{%d} lacks fields of the clean set', pk); %#ok<AGROW>
    end
end
if ~isempty(mm), return; end
for pk = 1:numel(E.POL)
    if ~all(E.RWf{pk}.split == 7), mm{end+1} = sprintf('RWf{%d} (%s) is not split id 7 throughout', pk, E.POL{pk}); end %#ok<AGROW>
end
if ~isempty(mm), return; end
RU = E.RWf;
aU = reshape(PP.ebno(RU{1}.s) >= KP.ebno_thr, 1, []);
end

function [fresh, mm] = far_def(KP)
% KPI 6's definition in KP: the union without KP.far_set; the fresh clean test set with
% KP.far_set 'fresh', which comes with KP.reading 'P1R'.
fresh = false; mm = {};
if ~isfield(KP, 'far_set'), return; end
fs = char(string(KP.far_set));
fresh = strcmp(fs, 'fresh');
if ~fresh
    mm = {sprintf('KP.far_set %s: this reader knows the union (no KP.far_set) and fresh only', fs)};
elseif ~(isfield(KP, 'reading') && strcmp(char(string(KP.reading)), 'P1R'))
    mm = {'KP.far_set fresh without KP.reading P1R'};
end
end

function L = p1r_label(L)
% P1R's lecturer lines: a second reading of test pools profile 1's C2e has read.
for i = 1:numel(L)
    if ~isempty(strtrim(L{i})), L{i} = [L{i} ' [P1R: with the fixed monitor, second reading, descriptive]']; end
end
end

function d = differs(a, b, name)
% The fields of a and b that are not equal (isequaln), one line each, then the leaves that differ.
d = {};
if isequaln(a, b), return; end
if isstruct(a) && isstruct(b) && isequal(size(a), size(b)) && isempty(setxor(fieldnames(a), fieldnames(b)))
    for f = fieldnames(a)'
        if ~isequaln({a.(f{1})}, {b.(f{1})}), d{end+1} = sprintf('%s: .%s differs', name, f{1}); end %#ok<AGROW>
    end
end
if isempty(d), d = {sprintf('%s: differs (size or fields)', name)}; end
try
    d = [d, leaf_diff(a, b, '    leaf', 12)];
catch ME                                            % the diagnostics never replace the gate's own answer
    d{end+1} = sprintf('    leaf: the diagnostics failed: %s', ME.message);
end
end

function d = leaf_diff(a, b, p, maxn)
% Where a and b differ, down to the numbers: the count, the largest absolute difference and the
% first pair at full precision (diagnostics only; the gate stays exact).
d = {};
if isequaln(a, b) || maxn <= 0, return; end
if ~strcmp(class(a), class(b)), d = {sprintf('%s: class %s vs %s', p, class(a), class(b))}; return; end
if ~isequal(size(a), size(b)), d = {sprintf('%s: size [%s] vs [%s]', p, num2str(size(a)), num2str(size(b)))}; return; end
if isstruct(a)
    fa = fieldnames(a);
    if ~isempty(setxor(fa, fieldnames(b))), d = {sprintf('%s: fields differ', p)}; return; end
    for i = 1:numel(a)
        for k = 1:numel(fa)
            q = [p '.' fa{k}];
            if numel(a) > 1, q = sprintf('%s(%d).%s', p, i, fa{k}); end
            d = [d, leaf_diff(a(i).(fa{k}), b(i).(fa{k}), q, maxn - numel(d))]; %#ok<AGROW>
            if numel(d) >= maxn, return; end
        end
    end
elseif iscell(a)
    for i = 1:numel(a)
        d = [d, leaf_diff(a{i}, b{i}, sprintf('%s{%d}', p, i), maxn - numel(d))]; %#ok<AGROW>
        if numel(d) >= maxn, return; end
    end
elseif isnumeric(a) || islogical(a)
    ne = ~(a == b | (isnan(a) & isnan(b)));
    i = find(ne, 1);
    d = {sprintf('%s: %d of %d elements differ, max |d| %.3g, first at %d: %.17g vs %.17g', p, nnz(ne), numel(a), ...
        max(abs(double(a(ne)) - double(b(ne)))), i, double(a(i)), double(b(i)))};
else
    d = {sprintf('%s: differs (%s)', p, class(a))};
end
end

function d = block_diff(txt, blk, i0, name)
% blk against the text from line i0 on.
d = {};
blk = reshape(blk, 1, []);
if i0 < 1 || i0 + numel(blk) - 1 > numel(txt)
    d = {sprintf('%s: %d lines do not fit the text from line %d', name, numel(blk), i0)}; return
end
k = find(~strcmp(txt(i0:i0 + numel(blk) - 1), blk), 1);
if ~isempty(k)
    d = {sprintf('%s: first difference at line %d of the text: "%s" vs "%s"', name, i0 + k - 1, txt{i0 + k - 1}, blk{k})};
end
end

%% ===================== Readings =====================
function [R, lines] = readings(E, PP, M, G)
[B, l1] = breakdown(E, PP, G);
[S, l2] = sensitivity(E, PP, M, G);
[CO, l3] = carried(E, PP, G);
lines = [l1, l2, l3, {'', ['4(d), mechanism D (rule settings chosen under the false-alarm filter), is read from C2''s ' ...
    'log on validation before C2e, not here (D103 4(d)).']}];
R = struct('breakdown', B, 'sensitivity', S, 'carried', CO);
end

function [B, lines] = breakdown(E, PP, G)
% D103 3(a)-(e) on KPI 6's clean flights (G.RU from the KPI 1 threshold), the six policies.
POL = E.POL; LBL = E.LBL; KP = E.KP; C = decision_config();
RU = G.RU; aU = G.aboveU; sU = RU{1}.s; nS = numel(PP.ebno); T = G.T; p6 = G.p6; n = sum(aU);
lines = {'', sprintf(['=== D103 3: system-level false alarms on clean flights (our KPI 6, an extension; never ' ...
    'lecturer KPI 3), %d clean flights x %d cycles from the KPI 1 threshold (%g dB); descriptive ==='], n, T, KP.ebno_thr), ...
    'KPI 6 as C2e printed it (reproduced by the gate; the verdict is read there, and counts every false-alarm episode):'};
fresh = far_def(KP);
src = 'same union as KPI 6 (D99 point 5''s rows, every policy)';
if fresh
    lines = [lines(1:2), {['P1R: KPI 6''s flights are the fresh clean test set (KP.far_set fresh, RWf, split id 7), ' ...
        'read once in P1R''s C2e']}, lines(3)];
    src = 'fresh clean test set, as KPI 6 (P1R, every policy)';
end
lines = [lines, G.far_lines];

% (a) per Eb/N0, one table for all six policies
nE = arrayfun(@(k) sum(aU & sU == k), 1:nS);
byE = zeros(numel(p6), nS);
hd = arrayfun(@(k) sprintf('%g dB', PP.ebno(k)), 1:nS, 'UniformOutput', false);
lines = [lines, {'', ['(a) False-alarm episodes per Eb/N0 (episodes with >= 1 change / clean flights), from the ' ...
    src ':'], sprintf('  %-46s%s%14s', 'policy', sprintf('%14s', hd{:}), 'all')}];
for j = 1:numel(p6)
    R = RU{p6(j)}; fe = aU & R.switches > 0;
    byE(j, :) = arrayfun(@(k) sum(fe & sU == k), 1:nS);
    c = arrayfun(@(k) cnt_txt(byE(j, k), nE(k)), 1:nS, 'UniformOutput', false);
    lines{end+1} = sprintf('  %-46s%s%14s', LBL{p6(j)}, sprintf('%14s', c{:}), cnt_txt(sum(fe), n)); %#ok<AGROW>
end
if any(nE == 0)
    lines{end+1} = sprintf('  -: %s, below the KPI 1 threshold, not in KPI 6', point_list(PP.ebno, find(nE == 0)));
end
for q = G.far_diag                                    % one table: far_report's rows for its two policies
    j = find(strcmp(LBL(p6), q.policy), 1);
    assert(~isempty(j) && isequal(byE(j, :), q.by_ebno) && isequal(nE, q.n_ebno), 'system_fa_breakdown:table', ...
        'the per-Eb/N0 table differs from far_report''s rows for %s', q.policy);
end

% (b) the path at the first change
lines = [lines, {'', ['(b) Path at the first change, from the change cycle''s own flags (rollout_policy.m fc_cls, fc_deg, ' ...
    'fc_dal); a confirmation built from cycles of mixed paths is attributed to the change cycle''s flags: class = a ' ...
    'hostile class (with the drop alarm modes, path_loss only with the drop alarm); degradation = degraded with ' ...
    'class none, benign_interference, unknown or path_loss without the drop alarm; drop = the drop alarm alone; no ' ...
    'flag = none of them on that cycle (confirmed from earlier cycles); overlaps beside:']}];
P = struct('policy', {}, 'n', {}, 'cls', {}, 'deg', {}, 'drop', {}, 'noflag', {}, 'unrec', {}, 'deg_by', {}, ...
    'cls_deg', {}, 'cls_drop', {}, 'deg_drop', {});
for j = 1:numel(p6)
    pk = p6(j); R = RU{pk}; fe = aU & R.switches > 0;
    [h, dg, dl, nm, un] = first_flags(R, fe, KP.cls_list, G.mon(pk).alarm_mode);
    pd = ~un & ~h & dg; pr = ~un & ~h & ~dg & dl; pz = ~un & ~h & ~dg & ~dl;
    by = cellfun(@(c) sum(pd & strcmp(nm, c)), {'none', 'benign_interference', 'unknown', 'path_loss'});
    P(j) = struct('policy', LBL{pk}, 'n', sum(fe), 'cls', sum(h), 'deg', sum(pd), 'drop', sum(pr), 'noflag', sum(pz), ...
        'unrec', sum(un), 'deg_by', by, 'cls_deg', sum(h & dg), 'cls_drop', sum(h & dl), 'deg_drop', sum(dg & dl));
    q = P(j);
    lines{end+1} = sprintf(['  %-46s %4d (%s): class %d | degradation %d (none %d, benign_interference %d, unknown %d, ' ...
        'path_loss without the drop alarm %d) | drop %d | no flag %d%s; overlaps class+degradation %d, class+drop %d, ' ...
        'degradation+drop %d'], q.policy, q.n, G.mon(pk).alarm_mode, q.cls, q.deg, by, q.drop, q.noflag, ...
        ternary(q.unrec > 0, sprintf(' | first change unrecorded %d', q.unrec), ''), q.cls_deg, q.cls_drop, q.deg_drop); %#ok<AGROW>
end

% (c) the Xu split
lines = [lines, {'', ['(c) Xu split of the false-alarm episodes: false_sw > 0, a change on a flight whose clean link passes ' ...
    'the 2x restoration test at no_action (link_env.m K.healthy, per flight, not per cycle) | switches > 0 and false_sw = ' ...
    '0, a flight whose clean link itself fails it. The verdict counts both; the split is descriptive:']}];
X = struct('policy', {}, 'n', {}, 'healthy', {}, 'unhealthy', {});
for j = 1:numel(p6)
    R = RU{p6(j)}; fe = aU & R.switches > 0;
    a = sum(fe & R.false_sw > 0); b = sum(fe & R.false_sw == 0);
    X(j) = struct('policy', LBL{p6(j)}, 'n', sum(fe), 'healthy', a, 'unhealthy', b);
    lines{end+1} = sprintf(['  %-46s %4d of %d flights: on a clean link that passes the test %d (%.2f%% of the flights) | ' ...
        'on a clean link that fails it %d (%.2f%%)'], LBL{p6(j)}, sum(fe), n, a, pct(a, n), b, pct(b, n)); %#ok<AGROW>
end

% (d) false changes per cycle and per hour beside the per-episode share
lines = [lines, {'', ['(d) False changes per cycle and per hour (far_report''s, false_change_rate.m) beside the ' ...
    'per-episode share; ARL = 1 / rate per cycle (Xie 2021: FAR = 1/ARL):']}];
iF = find(~ismember(POL, {'oracle', 'random'}));
D = struct('policy', {}, 'k', {}, 'n', {}, 'changes', {}, 'cycles', {}, 'per_cycle', {}, 'per_hour', {}, 'arl', {});
for j = 1:numel(p6)
    f = G.far(iF == p6(j)); F = f.rate;
    D(j) = struct('policy', f.policy, 'k', f.k, 'n', f.n, 'changes', F.k, 'cycles', F.cycles, 'per_cycle', F.rate, ...
        'per_hour', F.per_hour, 'arl', 1 / F.rate);
    lines{end+1} = sprintf(['  %-46s episodes %4d / %4d = %6.2f%% (upper %6.2f%%) | %d false changes in %d cycles: per ' ...
        'cycle %.4f%% (<= %.4f%%), %.0f per hour (<= %.0f), ARL %.4g cycles, one every %.3g s'], f.policy, f.k, f.n, ...
        100 * f.p, 100 * f.upper, F.k, F.cycles, 100 * F.rate, 100 * F.hi, F.per_hour, F.per_hour_hi, 1 / F.rate, F.mtbf_s); %#ok<AGROW>
end

% (e) the cycle of the first false change
w0 = C.win - 1;
lines = [lines, {'', sprintf(['(e) Cycle of the first false change (fc_t; the decision of cycle t reads frames 0..t-1, so ' ...
    'in cycles 1..%d the %d-frame BER window holds 1..%d frames, policy_monitor.m): the share there, then the ' ...
    'histogram (cycle:episodes). A start-up transient of episode starts is a simulation artefact, reported as such and ' ...
    'not removed from the reading:'], w0, C.win, w0)}];
H = struct('policy', {}, 'n', {}, 'hist', {}, 'early', {}, 'early_share', {});
for j = 1:numel(p6)
    R = RU{p6(j)}; fe = aU & R.switches > 0; fc = R.fc_t(fe);
    hc = arrayfun(@(t) sum(fc == t), 1:T);
    H(j) = struct('policy', LBL{p6(j)}, 'n', numel(fc), 'hist', hc, 'early', sum(fc <= w0), 'early_share', sum(fc <= w0) / numel(fc));
    lines{end+1} = sprintf('  %-46s %4d: in cycles 1..%d %d (%.1f%%; %d of the %d cycles) | %s', LBL{p6(j)}, numel(fc), w0, ...
        sum(fc <= w0), pct(sum(fc <= w0), numel(fc)), w0, T, hist_txt(hc)); %#ok<AGROW>
end
B = struct('policies', {LBL(p6)}, 'n_ebno', nE, 'by_ebno', byE, 'path', P, 'xu', X, 'rate', D, 'first', H, 'win', C.win);
end

function [h, dg, dl, nm, un] = first_flags(R, fe, cls_list, mode)
% The flags of the first change's cycle: h the class path (policy_monitor.m's hostile), dg
% degraded, dl the drop alarm, nm the class, un no first change recorded.
c = R.fc_cls(fe); dg = logical(R.fc_deg(fe)); dl = logical(R.fc_dal(fe));
un = c < 1;
nm = repmat({''}, 1, numel(c)); nm(~un) = cls_list(c(~un));
h = ~un & ~ismember(nm, {'none', 'benign_interference', 'unknown'});
if any(strcmp(mode, {'class_drop', 'class_cusum'})), h = h & ~(strcmp(nm, 'path_loss') & ~dl); end
if strcmp(mode, 'degraded'), h(:) = false; end
end

function s = p1r_test_note()
s = ['P1R: with the fixed monitor, second reading, descriptive: these episodes are test pools profile 1''s C2e ' ...
    'has read'];
end

function p = pre_onset(R)
% First change decided on clean frames only: the decision of cycle t reads frame t - 1, and
% frame t - 1 is clean while t - 1 < onset (link_env.m, rollout_policy.m).
p = R.fc_t > 0 & R.fc_t <= R.onset;
end

function [S, lines] = sensitivity(E, PP, M, G)
% D103 4(a)-(c): the pre-onset changes on the lecturer's recoverable jamming episodes, and
% lect_kpis.m on S0 (no change before the onset under any compared policy), pooled, on Line B
% and per Eb/N0, beside the full set.
ALL = E.ALL; POL = E.POL; LBL = E.LBL; iDQN = E.iDQN; LA = G.lect;
pay = LA.payload_bps; per_ms = LA.period_ms; nS = numel(PP.ebno);
R1 = ALL{1}; s = R1.s; Lep = M.L(s); cmp = G.cmp;
nm = reshape(PP.scen(R1.scn), 1, []);
mj = R1.recoverable & R1.threat & ismember(nm, LA.jam);
hc = isfield(R1, 'recoverable_core');
mjc = false(size(mj)); if hc, mjc = R1.recoverable_core & R1.threat & ismember(nm, LA.jam); end
pre = false(numel(cmp), numel(s));
for j = 1:numel(cmp), pre(j, :) = pre_onset(ALL{cmp(j)}); end
S0 = ~any(pre, 1);
lines = {'', ['=== D103 4: pre-onset sensitivity of the lecturer''s readings (sensitivity, descriptive; the pooled Line A ' ...
    'of C2e stays the verdict) ==='], sprintf(['A change before the onset: the first change at cycle 1..onset, decided on ' ...
    'clean frames only (the decision of cycle t reads frame t - 1), which no threat can affect. Compared policies (those ' ...
    'lect_kpis.m reads, the oracle aside): %s.'], strjoin(LBL(cmp), ', ')), ...
    sprintf('Mark (D99 R1, from the pools): %s', strjoin(arrayfun(@(k) sprintf('%g dB %s (clean loss %.3f)', ...
    PP.ebno(k), M.tag{k}, M.clean_fer(k)), 1:nS, 'UniformOutput', false), ', '))};
if far_def(E.KP), lines = [lines(1:2), {p1r_test_note()}, lines(3:end)]; end

% (a) the share with a first change before the onset
sets = {mj}; sn = {'recoverable jamming (36)'};
if hc, sets{end+1} = mjc; sn{end+1} = 'recoverable jamming (core)'; end
for v = LA.verdict
    sets{end+1} = mj & strcmp(nm, v.threat); sn{end+1} = sprintf('%s, %s (36)', v.threat, v.scenario); %#ok<AGROW>
end
lines = [lines, {'', sprintf('(a) Episodes with a first change before the onset, per policy: %s', strjoin(sn, ' | '))}];
A = struct('policy', {}, 'pre', {}, 'n', {}, 'pre_ebno', {}, 'n_ebno', {});
for j = 1:numel(cmp)
    k = arrayfun(@(i) sum(sets{i} & pre(j, :)), 1:numel(sets)); nn = cellfun(@sum, sets);
    ke = arrayfun(@(e) sum(mj & s == e & pre(j, :)), 1:nS); ne = arrayfun(@(e) sum(mj & s == e), 1:nS);
    A(j) = struct('policy', LBL{cmp(j)}, 'pre', k, 'n', nn, 'pre_ebno', ke, 'n_ebno', ne);
    lines{end+1} = sprintf('  %-46s %s', LBL{cmp(j)}, strjoin(arrayfun(@(i) sprintf('%d/%d (%.1f%%)', k(i), nn(i), ...
        pct(k(i), nn(i))), 1:numel(sets), 'UniformOutput', false), ' | ')); %#ok<AGROW>
    lines{end+1} = sprintf('  %-46s per Eb/N0, recoverable jamming (36): %s', '', strjoin(arrayfun(@(e) sprintf('%g dB %d/%d', ...
        PP.ebno(e), ke(e), ne(e)), 1:nS, 'UniformOutput', false), ' | ')); %#ok<AGROW>
end

% S0: its size and Eb/N0 composition
comp = @(m) strjoin(arrayfun(@(e) sprintf('%g dB [%s] %d/%d', PP.ebno(e), M.tag{e}, sum(m & S0 & s == e), sum(m & s == e)), ...
    1:nS, 'UniformOutput', false), ' | ');
lines = [lines, {'', sprintf(['S0, the episodes with no change before the onset under any compared policy: %d of %d ' ...
    'episodes; recoverable jamming %d of %d (36)%s'], sum(S0), numel(S0), sum(S0 & mj), sum(mj), ...
    ternary(hc, sprintf(', %d of %d (core)', sum(S0 & mjc), sum(mjc)), '')), ...
    sprintf('  composition per Eb/N0, recoverable jamming (36), in S0 / in the full set: %s', comp(mj))}];
if hc, lines{end+1} = sprintf('  composition per Eb/N0, recoverable jamming (core), in S0 / in the full set: %s', comp(mjc)); end
lines{end+1} = '  S0 is selected on pre-onset behaviour only, so not on the threat response, but on link quality: hence (c).';

% (b) lect_kpis.m on S0, pooled
LS = []; W = cell(0, 3);
lines = [lines, {'', sprintf(['(b) lect_kpis.m unchanged on S0 (%d episodes), pooled over every Eb/N0; beside Line A (C2e''s ' ...
    'lines, the verdict):'], sum(S0))}];
if any(S0)
    [LS, ls] = lect_kpis(subset(ALL, S0), POL, LBL, iDQN, PP.scen, pay, per_ms);
    lines = [lines, tag_words(norm_lines(ls), ' [sensitivity, not the verdict]')];
    [l, W] = compare_words(LA, LS); lines = [lines, {''}, l];
else
    lines{end+1} = '  S0 holds no episode: no reading.';
end

% (c) Line B and per Eb/N0, full set and S0
lines = [lines, {'', sprintf(['(c) Line B (D99: the non-L points, %s) and every Eb/N0 point, the full set beside S0; ' ...
    'descriptive. At L points recovery from detection is undefined and T_rec a BER-only test:'], point_list(PP.ebno, find(~M.L)))}];
keepB = ~Lep;
lines{end+1} = sprintf('  Line B, full set: %d episodes, %d recoverable jamming', sum(keepB), sum(keepB & mj));
[LB, l] = reading_rows(ALL, keepB, POL, LBL, iDQN, PP.scen, pay, per_ms, false, ''); lines = [lines, l];
lines{end+1} = sprintf('  Line B, S0: %d episodes, %d recoverable jamming', sum(keepB & S0), sum(keepB & S0 & mj));
[LB0, l] = reading_rows(ALL, keepB & S0, POL, LBL, iDQN, PP.scen, pay, per_ms, false, 'S0 '); lines = [lines, l];
RF = cell(1, nS); R0 = cell(1, nS);
for k = 1:nS
    kk = s == k;
    lines{end+1} = sprintf(['  Eb/N0 %g dB [%s] clean packet loss %.3f: full set %d episodes, %d recoverable jamming | ' ...
        'S0 %d, %d'], PP.ebno(k), M.tag{k}, M.clean_fer(k), sum(kk), sum(kk & mj), sum(kk & S0), sum(kk & S0 & mj)); %#ok<AGROW>
    [RF{k}, l] = reading_rows(ALL, kk, POL, LBL, iDQN, PP.scen, pay, per_ms, M.L(k), ''); lines = [lines, l]; %#ok<AGROW>
    [R0{k}, l] = reading_rows(ALL, kk & S0, POL, LBL, iDQN, PP.scen, pay, per_ms, M.L(k), 'S0 '); lines = [lines, l]; %#ok<AGROW>
end
S = struct('pre_policies', {LBL(cmp)}, 'pre', pre, 'S0', S0, 'n_S0', sum(S0), 'pre_share', A, 'lect_S0', LS, ...
    'words', {W}, 'line_b', LB, 'line_b_S0', LB0, 'rows', {RF}, 'rows_S0', {R0});
end

function [Lk, l] = reading_rows(ALL, keep, POL, LBL, iDQN, scen, pay, per_ms, isL, pre)
% lect_kpis.m on the episodes keep, as rows (full and core sets); none when keep is empty.
Lk = [];
if ~any(keep), l = {sprintf('    %sno episodes', pre)}; return; end
Lk = lect_kpis(subset(ALL, keep), POL, LBL, iDQN, scen, pay, per_ms);
l = row_lines(Lk, isL, per_ms, pre);
if ~isempty(Lk.core)
    l = [l, row_lines(Lk.core, isL, per_ms, [pre 'core: ']), row_lines(Lk.core.all36, isL, per_ms, ...
        [pre 'core (recoverable by the 36): '])];
end
end

function [CO, lines] = carried(E, PP, G)
% D103 5: confirmed alarms carried across the onset, per compared policy.
ALL = E.ALL; LBL = E.LBL; R1 = ALL{1}; LA = G.lect; per_ms = LA.period_ms;
jam = ismember(reshape(PP.scen(R1.scn), 1, []), LA.jam);
mr = R1.recoverable & R1.threat;
sets = {mr, mr & jam}; sn = {'recoverable threat episodes (36)', 'recoverable jamming episodes (36)'};
if isfield(R1, 'recoverable_core'), sets{end+1} = R1.recoverable_core & R1.threat & jam; sn{end+1} = 'recoverable jamming episodes (core)'; end
lines = {'', ['=== D103 5: confirmed alarms carried across the onset (descriptive). With an m-of-n confirmation, ' ...
    't_conf < m - 1 needs an alarm cycle before the onset; with the sweeper''s own k-of-n path, t_conf < k - 1 does. ' ...
    'Carried over: t_conf < min(m, k) - 1. Sweeper path or carried over: min(m, k) - 1 <= t_conf < m - 1, not separable ' ...
    'from the saved fields. t_conf median / p90 [cycles] (never %) with and without them ===']};
if far_def(E.KP), lines{end+1} = p1r_test_note(); end
CO = struct('policy', {}, 'confirm', {}, 'sweep', {}, 'set', {}, 'n', {}, 'detected', {}, 'carried', {}, 'sweep_or_carried', {}, ...
    't_conf', {}, 't_conf_wo', {}, 't_conf_wo_both', {});
for pk = G.cmp
    mon = G.mon(pk); R = ALL{pk};
    if startsWith(E.POL{pk}, 'blind'), mon.confirm_sweep = []; end   % every cycle reads unknown (policy_decide.m): no sweeper class
    sw = 'no sweeper path';
    if ~isempty(mon.confirm_sweep) && ~strcmp(mon.alarm_mode, 'degraded'), sw = sprintf('sweeper %d of %d', mon.confirm_sweep); end
    lines{end+1} = sprintf('  %s (monitor %s, %d of %d, %s):', LBL{pk}, mon.alarm_mode, mon.confirm, sw); %#ok<AGROW>
    for i = 1:numel(sets)
        tc = R.t_conf(sets{i});
        [ce, am] = carry_counts(tc, mon);
        q = struct('policy', LBL{pk}, 'confirm', mon.confirm, 'sweep', mon.confirm_sweep, 'set', sn{i}, 'n', numel(tc), ...
            'detected', sum(isfinite(tc)), 'carried', sum(ce), 'sweep_or_carried', sum(am), 't_conf', tstat(tc), ...
            't_conf_wo', tstat(tc(~ce)), 't_conf_wo_both', tstat(tc(~ce & ~am)));
        CO(end+1) = q; %#ok<AGROW>
        lines{end+1} = sprintf(['    %-38s %d detected of %d: carried over %d | sweeper path or carried over %d | t_conf %s; ' ...
            'without the carried-over %s; without both %s'], sn{i}, q.detected, q.n, q.carried, q.sweep_or_carried, ...
            tt(q.t_conf, per_ms), tt(q.t_conf_wo, per_ms), tt(q.t_conf_wo_both, per_ms)); %#ok<AGROW>
    end
end
end

function [ce, am] = carry_counts(tc, mon)
% ce: a confirmation no post-onset cycles alone can give; am: one only the sweeper's path
% could give from post-onset cycles (or a carried-over alarm).
m = mon.confirm(1); k = Inf;
if ~isempty(mon.confirm_sweep) && ~strcmp(mon.alarm_mode, 'degraded'), k = mon.confirm_sweep(1); end
d = isfinite(tc);
ce = d & tc < min(m, k) - 1;
am = d & ~ce & tc < m - 1;
end

function lines = row_lines(S, isL, per_ms, pre)
% One subset's readings from lect_kpis.m's output S; verdict words labelled descriptive;
% at an L point recovery from detection undefined and T_rec tagged BER-only.
w = ' (descriptive, not a verdict)';
und = 'undefined (restoration threshold >= 100%)';
lines = {};
for v = S.verdict
    if v.n == 0
        lines{end+1} = sprintf('    %sPER %s (%s): no recoverable episodes -> %s%s', pre, v.scenario, v.threat, v.verdict, w); %#ok<AGROW>
    else
        lines{end+1} = sprintf('    %sPER %s (%s), %d recoverable episodes, static PER %.2f%%: %s reduction %.1f%% [%.1f, %.1f] -> %s%s', ...
            pre, v.scenario, v.threat, v.n, v.per_ref_pct, v.label, v.red_pct, v.ci, v.verdict, w); %#ok<AGROW>
    end
end
for q = S.per
    lines{end+1} = sprintf('    %sPER five jamming threats pooled, %-40s %d episodes: %6.2f%% vs %6.2f%% static, reduction %6.1f%% [%.1f, %.1f]%s', ...
        pre, q.label, q.n, q.per_pct, q.per_ref_pct, q.red_pct, q.ci, ternary(any(strcmp(q.policy, {'rule_esc', 'rule_core'})), ...
        [' -> ' q.verdict w], '')); %#ok<AGROW>
end
for q = S.per_threat
    lines{end+1} = sprintf('    %sPER %s, %d episodes, static PER %.2f%%: reduction %s', pre, q.threat, q.n, q.per_ref_pct, ...
        strjoin(arrayfun(@(j) sprintf('%s %.1f [%.1f, %.1f]', S.per(j).label, q.red_pct(j), q.ci(j, 1), q.ci(j, 2)), ...
        1:numel(S.per), 'UniformOutput', false), ' | ')); %#ok<AGROW>
end
c = S.cnn;
rd = und;
if ~isL, rd = sprintf('%s vs %s', tt(c.rec_det(1), per_ms), tt(c.rec_det(2), per_ms)); end
lines{end+1} = sprintf(['    %sCNN contribution (%d episodes): PER reduction %.1f%% [%.1f, %.1f], goodput %+.0f bit/s ' ...
    '[%+.0f, %+.0f]; with vs without the detector: onset -> detection %s vs %s, detection -> PER restored %s'], pre, ...
    c.n, c.per_red_pct, c.per_ci, c.gput_bps, c.gput_ci, tt(c.det(1), per_ms), tt(c.det(2), per_ms), rd);
sn = unique({S.rec.set}, 'stable');
for i = 1:numel(sn)
    lines{end+1} = sprintf('    %s%s: onset -> detection | detection -> PER restored | T_rec from onset%s', pre, sn{i}, ...
        ternary(isL, ' (BER-only)', '')); %#ok<AGROW>
    for q = S.rec(strcmp({S.rec.set}, sn{i}))
        r = und;
        if ~isL, r = tt(q.rec_det, per_ms); end
        lines{end+1} = sprintf('      %-44s %d: %s | %s | %s%s', q.label, q.n, tt(q.det, per_ms), r, tt(q.t_rec, per_ms), ...
            ternary(isL, ' BER-only', '')); %#ok<AGROW>
    end
end
for q = S.gput
    lines{end+1} = sprintf('    %sgoodput %-44s threat %s [%s, %s], normalized %s | recoverable jamming %s [%s, %s], normalized %s', ...
        pre, q.label, bps(q.bps), bps(q.ci(1)), bps(q.ci(2)), nrm(q.norm), bps(q.bps_jam), bps(q.ci_jam(1)), ...
        bps(q.ci_jam(2)), nrm(q.norm_jam)); %#ok<AGROW>
end
end

function [lines, W] = compare_words(LA, LS)
% The verdict words of Line A and of S0 per reading; where they differ, both are named.
W = words(LA, LS, '');
if ~isempty(LA.core) && ~isempty(LS.core)
    W = [W; words(LA.core, LS.core, 'core action set: '); ...
        words(LA.core.all36, LS.core.all36, 'core action set, recoverable by the 36: ')];
end
d = find(~strcmp(W(:, 2), W(:, 3)));
if isempty(d)
    lines = {'Line A and S0 give the same verdict words for every reading.'};
else
    lines = {sprintf('Line A and S0 differ in verdict words for %d reading(s); Line A stays the verdict, the result sentence names both:', numel(d))};
    for i = d'
        lines{end+1} = sprintf('  %s: Line A %s (the verdict), S0 %s (sensitivity).', W{i, 1}, W{i, 2}, W{i, 3}); %#ok<AGROW>
    end
end
end

function W = words(A, B, pre)
W = cell(0, 3);
for v = A.verdict
    j = find(strcmp({B.verdict.scenario}, v.scenario), 1); wb = '-';
    if ~isempty(j), wb = B.verdict(j).verdict; end
    W(end+1, :) = {sprintf('%sPER %s (%s), %s', pre, v.scenario, v.threat, v.label), v.verdict, wb}; %#ok<AGROW>
end
for q = A.per(ismember({A.per.policy}, {'rule_esc', 'rule_core'}))
    j = find(strcmp({B.per.policy}, q.policy), 1); wb = '-';
    if ~isempty(j), wb = B.per(j).verdict; end
    W(end+1, :) = {sprintf('%sPER five jamming threats pooled, %s', pre, q.label), q.verdict, wb}; %#ok<AGROW>
end
end

function l = tag_words(l, t)
% Appends t to every line that carries a verdict word.
v = ~cellfun(@isempty, regexp(l, '-> (MET|NOT MET)', 'once'));
if any(v), l(v) = strcat(l(v), {t}); end
end

%% ===================== Mark and subsets =====================
function M = mark(clean_fer, ratio_ok)
% D99 R1: link-limited where ratio_ok x the clean packet loss >= 1; J below 0.1, M between.
f = double(clean_fer(:)');
M = struct('clean_fer', f, 'ratio_ok', ratio_ok, 'L', ratio_ok * f >= 1, 'tag', {repmat({'M'}, 1, numel(f))});
M.tag(M.L) = {'L'};
M.tag(~M.L & f < 0.1) = {'J'};
end

function A = subset(ALL, keep)
keep = logical(keep(:)');
A = ALL;
for k = 1:numel(ALL)
    f = fieldnames(ALL{k});
    for j = 1:numel(f)
        x = ALL{k}.(f{j});
        assert(size(x, 2) == numel(keep), 'system_fa_breakdown:field', ...
            'ALL{%d}.%s has %d columns, not one per episode (%d)', k, f{j}, size(x, 2), numel(keep));
        A{k}.(f{j}) = x(:, keep);
    end
end
end

%% ===================== evaluate_policies.m's far_report, byte for byte =====================
function [FAR, FD, lines] = far_report(RR, POL, LBL, above, T, iDQN, ebno, cls_list, period_ms)
% False-alarm counts per policy (episodes with >= 1 change, Clopper-Pearson
% bound; false changes per cycle and per hour, false_change_rate.m), and for the
% deployed policy and rule + escalation the false-alarm episodes per Eb/N0 and the
% trigger at the first change.
lines = {};
FAR = struct('policy', {}, 'k', {}, 'n', {}, 'p', {}, 'upper', {}, 'per_cycle', {}, 'rate', {});
for pk = 1:numel(POL)
    if any(strcmp(POL{pk}, {'oracle', 'random'})), continue; end
    R = RR{pk}; kf = sum(R.switches(above) > 0); n = sum(above);
    F = false_change_rate(R.switches(above), T, R.geom(above) + 1e6 * R.split(above), period_ms);
    FAR(end+1) = struct('policy', LBL{pk}, 'k', kf, 'n', n, 'p', kf / n, 'upper', cp_upper(kf, n), ...
        'per_cycle', F.rate, 'rate', F); %#ok<AGROW>
    lines{end+1} = sprintf(['  %-40s %4d / %4d = %6.2f%%   upper %6.2f%%   per cycle %.4f%% (<= %.4f%%), %.0f per hour ' ...
        '(<= %.0f), one every %.3g s'], LBL{pk}, kf, n, 100 * kf / n, 100 * FAR(end).upper, 100 * F.rate, 100 * F.hi, ...
        F.per_hour, F.per_hour_hi, F.mtbf_s); %#ok<AGROW>
end
nS = numel(ebno);
FD = struct('policy', {}, 'by_ebno', {}, 'n_ebno', {}, 'cls', {}, 'deg', {}, 'drop', {});
for pk = unique([iDQN, find(strcmp(POL, 'rule_esc'))], 'stable')
    R = RR{pk}; fe = above & R.switches > 0;
    byE = arrayfun(@(s) sum(fe & R.s == s), 1:nS); nE = arrayfun(@(s) sum(above & R.s == s), 1:nS);
    lines{end+1} = sprintf('  %s, false-alarm episodes per Eb/N0: %s', LBL{pk}, strjoin(arrayfun(@(s) ...
        sprintf('%g dB %d/%d', ebno(s), byE(s), nE(s)), 1:nS, 'UniformOutput', false), ' | ')); %#ok<AGROW>
    c = R.fc_cls(fe); d = R.fc_deg(fe); dr = R.fc_drop(fe); u = unique(c(c > 0));
    txt = strjoin(arrayfun(@(k) sprintf('%s %d (degraded %d, median Eb/N0 drop %.1f dB)', cls_list{k}, ...
        sum(c == k), sum(c == k & d), median(dr(c == k), 'omitnan')), u, 'UniformOutput', false), ', ');
    if isempty(txt), txt = '-'; end
    lines{end+1} = sprintf('    detector class at the first change: %s', txt); %#ok<AGROW>
    FD(end+1) = struct('policy', LBL{pk}, 'by_ebno', byE, 'n_ebno', nE, 'cls', c, 'deg', d, 'drop', dr); %#ok<AGROW>
end
end

function u = cp_upper(k, n)
% One-sided 95% Clopper-Pearson upper bound of a binomial proportion.
if k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

%% ===================== Helpers =====================
function [nthr, how] = thread_info()
% The thread count this session really has; maxNumCompThreads('automatic') is refused under
% -singleCompThread (the gated wrapper's), which keeps one.
how = 'maxNumCompThreads set to automatic';
try, maxNumCompThreads('automatic'); catch, how = 'not changeable in this session: -singleCompThread'; end
try, nthr = maxNumCompThreads; catch, nthr = NaN; how = [how '; the count is not readable']; end
end

function keep_old(f)
% A diagnostics file of an earlier failed attempt stays, under its own time.
if ~isfile(f), return; end
d = dir(f); [p, n, e] = fileparts(f);
movefile(f, fullfile(p, [n '_' datestr(d.datenum, 'yyyymmdd_HHMMSS') e]));
end

function R = cat_struct(R, Rb)
f = fieldnames(R);
for i = 1:numel(f), R.(f{i}) = [R.(f{i}), Rb.(f{i})]; end
end

function s = tstat(x)
% Median and p90 (nearest rank) of the finite values, the share of NaN (never).
x = x(:)'; f = sort(x(isfinite(x)));
s = struct('n', numel(x), 'median', NaN, 'p90', NaN, 'never_pct', 100 * mean(~isfinite(x)));
if isempty(x), s.never_pct = NaN; end
if ~isempty(f), s.median = median(f); s.p90 = f(min(numel(f), max(1, round(0.9 * numel(f))))); end
end

function s = tt(q, period_ms)
% Median / p90 of a time as lect_kpis.m prints it.
if isnan(q.median), s = sprintf('- (never %.1f%%)', q.never_pct); return; end
s = sprintf('%g / %g (%g / %g ms, never %.1f%%)', q.median, q.p90, q.median * period_ms, q.p90 * period_ms, q.never_pct);
end

function s = bps(x)
if ~isfinite(x), s = 'n/a'; elseif abs(x) >= 1e3, s = sprintf('%.2f kb/s', x / 1e3); else, s = sprintf('%.0f b/s', x); end
end

function s = nrm(x)
% Normalized goodput: n/a where the clean link loses more than 90%; above 1 it is real.
if isnan(x), s = 'n/a (clean loss > 90%)';
elseif x > 1, s = sprintf('%.3f (above 1: the clean link loses more here)', x);
else, s = sprintf('%.3f', x); end
end

function s = cnt_txt(k, n)
if n == 0, s = '-'; else, s = sprintf('%d/%d', k, n); end
end

function p = pct(k, n)
p = 100 * k / n;
if n == 0, p = NaN; end
end

function s = hist_txt(h)
k = find(h > 0);
if isempty(k), s = '-'; return; end
s = strjoin(arrayfun(@(t) sprintf('%d:%d', t, h(t)), k, 'UniformOutput', false), ' ');
end

function s = point_list(ebno, k)
if isempty(k), s = 'none'; return; end
s = strjoin(arrayfun(@(i) sprintf('%g dB', ebno(i)), k(:)', 'UniformOutput', false), ', ');
end

function h = file_sha(f)
% SHA-256 of a file, as sha256sum prints it, read in pieces of 64 MB.
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
assert(fid > 0, 'system_fa_breakdown:sha', 'cannot read %s', f);
c = onCleanup(@() fclose(fid));
while true
    b = fread(fid, 2^26, '*uint8');
    if isempty(b), break; end
    md.update(b);
end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end

function st = stamps(files)
% Size and time of each file.
st = cell(size(files));
for i = 1:numel(files)
    d = dir(files{i}); st{i} = [d.bytes, d.datenum];
end
end

function t = read_lines(f)
t = norm_lines(regexp(fileread(f), '\r?\n', 'split'));
if ~isempty(t) && isempty(t{end}), t(end) = []; end
end

function l = norm_lines(l)
l = reshape(l, 1, []);
l(cellfun(@isempty, l)) = {''};
end

function write_lines(f, lines)
fid = fopen(f, 'w');
assert(fid > 0, 'system_fa_breakdown:write', 'cannot write %s', f);
fprintf(fid, '%s\n', lines{:});
fclose(fid);
end

function y = is_abs(p)
y = ischar(p) && numel(p) > 2 && ((p(2) == ':' && any(p(3) == '\/')) || startsWith(p, '\\') || startsWith(p, '/'));
end

function v = field_or(S, f, d)
if isfield(S, f), v = S.(f); else, v = d; end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
