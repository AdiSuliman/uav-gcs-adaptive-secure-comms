function R = side_a5_kpi4_af(pe_mat, out_dir, tag, threat)
%SIDE_A5_KPI4_AF  P-4 root cause for one threat: the validation envelope per level beside the registered rows.
%   R = side_a5_kpi4_af(pe_mat, out_dir, tag)            threat 'antenna_fault'
%   R = side_a5_kpi4_af(pe_mat, out_dir, tag, threat)
%   pe_mat   a tree's results/policy_evaluation.mat; only its KP summary is loaded
%   Prints, per severity level: the deployed policy's validation recovered share (the envelope's
%   input), the inside/outside flag, the registered test rows per level and the harmed counts;
%   then how far the levels picked on validation sit from the test level mean (selection on
%   validation noise), and the arithmetic of the deficit (harmed against unharmed episodes).
%   Decides nothing; no test number is used to choose anything.
if nargin < 4, threat = 'antenna_fault'; end
od = side_out_dir(out_dir, pe_mat);
S = load(pe_mat, 'KP', 'POL', 'iDQN'); KP = S.KP;
iK = find(strcmp(KP.show, S.POL{S.iDQN}));          % the deployed policy's column (evaluate_policies.m)
iE = find(strcmp(KP.show, 'dqn_esc'));
assert(isscalar(iK) && isscalar(iE), 'side_a5_kpi4_af:cols', 'side_a5_kpi4_af: deployed or dqn_esc column not found');
ti = find(strcmp(KP.threats, threat));
assert(isscalar(ti), 'side_a5_kpi4_af:threat', 'side_a5_kpi4_af: %s not found once in KP.threats', threat);
lv = KP.sev_names(:)'; nV = numel(lv);
ev = KP.envelope_val(ti, :); en = logical(KP.envelope(ti, :));
ts = KP.per_threat_sev(ti, :, iK);
R = struct('tag', tag, 'threat', threat, 'levels', {lv}, 'val', ev, 'inside', en, 'test_sev', ts, ...
    'test_env', KP.per_threat_env(ti), 'test_env_ci', KP.per_threat_env_ci(ti, :), 'test_all', KP.per_threat(ti, iK), ...
    'n_h', KP.n_harmed(ti), 'test_h', KP.per_threat_h(ti, iK), 'esc_all', KP.per_threat(ti, iE), ...
    'esc_h', KP.per_threat_h(ti, iE), 'deployed', S.POL{S.iDQN}, 'env_rule', KP.env_rule);
if isfield(KP, 'envelope_val_h'), R.val_h = KP.envelope_val_h(ti, :); else, R.val_h = nan(1, nV); end
if isfield(KP, 'n_harmed_sev'), R.n_h_sev = KP.n_harmed_sev(ti, :); else, R.n_h_sev = nan(1, nV); end
R.val_inside_mean = mean(ev(en)); R.val_all_mean = mean(ev(~isnan(ev)));
R.test_inside_lv = mean(ts(en)); R.test_all_lv = mean(ts(~isnan(ts)));
L = side_header(sprintf('A5 P-4 ROOT CAUSE: %s, %s', threat, tag), pe_mat, ...
    {'validation values: the deployed policy on the validation flights (evaluate_policies.m 3b), the envelope''s input', ...
    'test values: the registered rows of the same file (quoted, not used for any choice)'});
ins = strs(en);
L{end+1} = sprintf('%-24s%s', 'level', sprintf(' %10s', lv{:}));
L{end+1} = sprintf('%-24s%s', 'validation recovered %', sprintf(' %10.1f', ev));
L{end+1} = sprintf('%-24s%s', sprintf('inside (>= %d%%)', KP.env_rule(1)), sprintf(' %10s', ins{:}));
L{end+1} = sprintf('%-24s%s', 'validation harmed %', sprintf(' %10.1f', R.val_h));
L{end+1} = sprintf('%-24s%s', 'test recovered % (reg.)', sprintf(' %10.1f', ts));
L{end+1} = sprintf('%-24s%s', 'test harmed n (reg.)', sprintf(' %10d', round(R.n_h_sev)));
L{end+1} = '';
L{end+1} = sprintf(['Validation: mean over the levels inside %.1f%%, over every level %.1f%%; test (registered): ' ...
    'levels inside %.1f%%, every level %.1f%%; inside the envelope %.1f%% [%.1f, %.1f]'], R.val_inside_mean, ...
    R.val_all_mean, R.test_inside_lv, R.test_all_lv, R.test_env, R.test_env_ci(1), R.test_env_ci(2));
rs = NaN; if isfield(KP, 'recoverable_share'), rs = KP.recoverable_share(ti); end
L{end+1} = sprintf(['Same flights, registered columns: deployed (%s) every level %.1f%%, harmed %.1f%%; the same DQN with ' ...
    'escalation (not deployed) every level %.1f%%, harmed %.1f%%'], R.deployed, R.test_all, R.test_h, R.esc_all, R.esc_h);
L{end+1} = sprintf(['Every level (registered): %.1f%%; harmed %d episodes recovered %.1f%%. Recoverable episodes ' ...
    'implied if every unharmed one recovers: %.0f; recoverable share (registered) %.4g. Equal counts mean the harmed ' ...
    'episodes carry the whole deficit (derived from the registered rows).'], R.test_all, R.n_h, R.test_h, implied_n(R), rs);
fid = fopen(fullfile(od, 'a5_kpi4_af.txt'), 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
save(fullfile(od, 'a5_kpi4_af.mat'), 'R');
fprintf('%s\n', L{:});
end

function N = implied_n(R)
% Recoverable episodes whose every-level rate equals the harmed losses alone.
N = NaN;
if R.test_all < 100, N = R.n_h * (1 - R.test_h / 100) / (1 - R.test_all / 100); end
end

function c = strs(b)
c = cell(1, numel(b));
for i = 1:numel(b), if b(i), c{i} = 'in'; else, c{i} = 'out'; end, end
end
