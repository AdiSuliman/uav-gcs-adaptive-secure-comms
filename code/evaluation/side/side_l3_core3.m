function S = side_l3_core3(test_mat, out_dir, core_cnn_txt, poleval_txt)
%SIDE_L3_CORE3  L3 (false alarms) at system level for rule_core3 from CORE_BW's saved test readings, a labelled
%   side reading beside the classifier-level figure and the hybrid rule row's.
%   S = side_l3_core3(test_mat, out_dir, core_cnn_txt, poleval_txt)
%   test_mat      CORE_BW's results/core_bw/test_readings.mat (RES, EPs; opened read-only)
%   out_dir       a new folder; side_l3_core3.txt and .mat are written there
%   core_cnn_txt  optional: profile 1's results/core_cnn.txt (B3c), its clean false-alarm line quoted
%   poleval_txt   optional: profile 1's results/policy_evaluation.txt, the core rule row's clean line quoted
%   Clean-link episodes (scn 1, PP.scen 'none' of the study): per hop rule, set and policy the share with a
%   change and its one-sided 95% Clopper-Pearson bound. When the file holds none, it says so, and beside it,
%   labelled as not the L3 quantity, on every episode of each set:
%   (a) the first change decided on a clean frame before the onset (1 <= fc_t <= onset: the decision of
%       cycle t reads frame t - 1, rollout_policy.m; the link is clean until the onset, link_env.m); the
%       first change only, over 3-10 clean frames with the monitor's confirmation window filling;
%   (b) a change on a healthy link (false_sw > 0: no_action restores the link, link_env.m), the jammer on.
if nargin < 3, core_cnn_txt = ''; end
if nargin < 4, poleval_txt = ''; end
if ~isfile(test_mat), error('side_l3:input', 'side_l3_core3: %s not found', test_mat); end
vars = {whos('-file', test_mat).name};
miss = setdiff({'RES', 'EPs'}, vars);
if ~isempty(miss), error('side_l3:field', 'side_l3_core3: %s holds no variable %s', test_mat, strjoin(miss, ', ')); end
W = load(test_mat, 'RES', 'EPs');
RES = W.RES; EP = W.EPs;
notes = {['L3 at system level for rule_core3 (the three-state CNN in the core rule): the share of clean-link ' ...
    'episodes with a configuration change, one-sided 95% Clopper-Pearson bound'], ...
    ['clean link: scn 1 (experiment_core_bw.m: PP.scen = [none, the jammer cells]); the episode list EPs.c names ' ...
    'the cell of every episode']};
L = side_header('L3 at system level, rule_core3 (CORE_BW test readings)', test_mat, notes);
L = [L, quotes(core_cnn_txt, poleval_txt)];
ncl_ep = sum(EP.c == 1);
L{end+1} = sprintf('episode list: %d episodes, %d of the clean link (EPs.c == 1)', numel(EP.c), ncl_ep);
rows = struct('rule', {}, 'set', {}, 'policy', {}, 'n', {}, 'k', {}, 'share', {}, 'upper', {});
prox = struct('rule', {}, 'set', {}, 'policy', {}, 'n', {}, 'k_pre', {}, 'pre_frames', {}, 'k_healthy', {}, 'upper_pre', {});
for i = 1:numel(RES)
    R = RES(i).R;
    if ~isfield(R, 'scn') || isempty(R.scn), continue; end
    c = R.scn(:)' == 1;
    if any(c)
        k = sum(R.switches(c) > 0); n = sum(c);
        rows(end+1) = struct('rule', RES(i).rule, 'set', RES(i).set, 'policy', RES(i).policy, 'n', n, 'k', k, ...
            'share', k / n, 'upper', cp_upper(k, n)); %#ok<AGROW>
    end
    if all(isfield(R, {'fc_t', 'onset', 'false_sw'}))
        f = R.fc_t(:)'; o = R.onset(:)';
        pre = f >= 1 & f <= o;
        prox(end+1) = struct('rule', RES(i).rule, 'set', RES(i).set, 'policy', RES(i).policy, 'n', numel(f), ...
            'k_pre', sum(pre), 'pre_frames', sum(o), 'k_healthy', sum(R.false_sw(:)' > 0), ...
            'upper_pre', cp_upper(sum(pre), numel(f))); %#ok<AGROW>
    end
end
S = struct('input', test_mat, 'sha256', side_sha256(test_mat), 'flown', ~isempty(rows), 'n_clean_list', ncl_ep, ...
    'rows', {rows}, 'proxy', {prox});
if isempty(rows)
    L{end+1} = ['NOT FLOWN: CORE_BW flew no clean-link episode for any policy (every scenario of band_cells.m is a jammer ' ...
        'cell; sets primary, pipe30, follower); rule_core3''s clean false-change share cannot be read from this file. A ' ...
        'reading needs rule_core3 flown on clean flights (the study''s clean pools, split 2 only, or a new set).'];
else
    L{end+1} = 'Clean-link episodes with a change (one-sided 95% Clopper-Pearson bound):';
    for r = rows
        L{end+1} = sprintf('  %-3s %-9s %-17s %d of %d = %.2f%%, upper %.2f%%', r.rule, r.set, r.policy, r.k, r.n, ...
            100 * r.share, 100 * r.upper); %#ok<AGROW>
    end
end
L{end+1} = '';
L{end+1} = ['Not the L3 quantity, beside it (every episode of the set, the jammer on after the onset): (a) the first change ' ...
    'decided on a clean frame before the onset, of the episodes, with the clean frames read; (b) episodes with a change on a ' ...
    'healthy link (false_sw > 0):'];
for p = prox
    L{end+1} = sprintf('  %-3s %-9s %-17s (a) %d of %d (%.2f%%, upper %.2f%%) over %d clean frames | (b) %d of %d (%.2f%%)', ...
        p.rule, p.set, p.policy, p.k_pre, p.n, 100 * p.k_pre / max(p.n, 1), 100 * p.upper_pre, p.pre_frames, p.k_healthy, ...
        p.n, 100 * p.k_healthy / max(p.n, 1)); %#ok<AGROW>
end
if isempty(prox), L{end+1} = '  FIELD ABSENT (fc_t, onset, false_sw): not read'; end
out = side_out_dir(out_dir, test_mat);
side_write(out, 'side_l3_core3', L, S);
fprintf('%s\n', L{:});
end

function L = quotes(core_cnn_txt, poleval_txt)
% The two registered L3 lines it stands beside, quoted with their files.
L = {};
src = {core_cnn_txt, 'false alarms, clean frames', 'classifier level, three-state CNN (B3c, window N, official)'; ...
    poleval_txt, '^\s*core: rule \+ escalation\s+\d+ / \d+', 'system level, the hybrid core rule row (C2e clean set)'};
for i = 1:size(src, 1)
    f = src{i, 1};
    if isempty(f), L{end+1} = sprintf('beside it, %s: not given', src{i, 3}); continue; end %#ok<AGROW>
    if ~isfile(f), L{end+1} = sprintf('beside it, %s: %s not found', src{i, 3}, f); continue; end %#ok<AGROW>
    t = splitlines(fileread(f));
    j = find(~cellfun(@isempty, regexp(t, src{i, 2}, 'once')), 1);
    if isempty(j), L{end+1} = sprintf('beside it, %s: no such line in %s', src{i, 3}, f); continue; end %#ok<AGROW>
    L{end+1} = sprintf('beside it, %s: "%s" (%s line %d, SHA-256 %s)', src{i, 3}, strtrim(t{j}), f, j, side_sha256(f)); %#ok<AGROW>
end
end

function u = cp_upper(k, n)
if n == 0, u = NaN; elseif k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end
