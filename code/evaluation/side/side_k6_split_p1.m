function S = side_k6_split_p1(tree, out_dir)
%SIDE_K6_SPLIT_P1  D121 item 12, KPI 6 split by link K, speed band and bank, on profile 1's validation traces.
%   S = side_k6_split_p1(tree, out_dir)
%   tree     a result tree (for example profile 1's), read-only
%   out_dir  a new folder; side_k6_split_p1.txt (and .mat when it prints a saved split) are written there
%   clean_k6_split.m needs the false-change flags of the deployed agent and of the rule on the clean
%   validation flights (eval_clean_wide in train_dqn.m, sw_w > 0). The split of such a run is saved
%   in results/dqn_k6_split.mat (variable K6C, kpi6_split.m's struct). When that file exists in the
%   tree, this reader prints it. When it does not, the flags would have to be recomputed by flying the
%   agent over the clean validation flights, which needs the policy pools (data/policy_pools.mat,
%   14 GB) and the clean validation pools; that is a pool rebuild, which a side reading does not do:
%   the reader refuses and records what is missing in its output folder.
if ~isfolder(tree), error('side_k6:tree', 'side_k6_split_p1: %s is not a folder', tree); end
f = fullfile(tree, 'results', 'dqn_k6_split.mat');
inputs = {fullfile(tree, 'data', 'policy_pools.mat'), fullfile(tree, 'data', 'clean_val_pools.mat'), ...
    fullfile(tree, 'data', 'trained_dqn.mat'), fullfile(tree, 'data', 'drop_threshold.mat')};
out = side_out_dir(out_dir, [{f}, inputs]);
if ~isfile(f)
    L = {'=== D121 item 12 KPI 6 split by link K, speed and bank ===', 'side reading, decides nothing', ...
        sprintf('tree: %s', char(java.io.File(tree).getCanonicalPath())), ...
        sprintf('REFUSED: %s does not exist.', f), ...
        ['No saved per-episode false-change flags of the deployed agent on the clean validation flights exist in this tree (the ' ...
        'split is written by train_dqn.m only where the profile asks for k6_split, and this tree holds none). Recomputing them means ' ...
        'flying the agent over the clean validation flights with the policy pools loaded; that is a pool rebuild and is not done here.'], ...
        'inputs a recomputation would need:'};
    for i = 1:numel(inputs)
        d = dir(inputs{i});
        if isempty(d), L{end+1} = sprintf('  %s: absent', inputs{i}); %#ok<AGROW>
        else, L{end+1} = sprintf('  %s: %.1f MB', inputs{i}, d.bytes / 2^20); end %#ok<AGROW>
    end
    side_write(out, 'side_k6_split_p1', L);
    fprintf('%s\n', L{:});
    S = struct('status', 'refused', 'missing', f);
    error('side_k6:refused', 'side_k6_split_p1: refused, %s does not exist (a pool rebuild would be needed); see %s', f, out);
end
notes = {'D121 item 12 (descriptive, beside KPI 6''s registered reading, never in its place): the saved split of the run that wrote this file', ...
    'bins: link K < 0, 0 to < 10, >= 10 dB; speed bands; bank 0-20, 20-40, >= 40 deg; hiding geometry (kpi6_split.m)'};
L = side_header('D121 item 12 KPI 6 split, saved split', f, notes);
W = load(f, 'K6C');
if ~isfield(W, 'K6C'), error('side_k6:field', 'side_k6_split_p1: %s holds no variable K6C', f); end
K = W.K6C;
for v = 1:numel(K.var)
    x = K.var(v);
    L{end+1} = sprintf('%s:', x.name); %#ok<AGROW>
    for p = 1:size(x.k, 1)
        t = cell(1, numel(x.labels));
        for b = 1:numel(x.labels)
            t{b} = sprintf('%s %d/%d = %.1f%% [%.1f, %.1f] (%d geometries)', x.labels{b}, x.k(p, b), x.n(p, b), x.pct(p, b), ...
                x.ci(p, b, 1), x.ci(p, b, 2), x.ncl(p, b));
        end
        L{end+1} = sprintf('  row %d: %s', p, strjoin(t, ' | ')); %#ok<AGROW>
    end
end
if isfield(K, 'hide_share'), L{end+1} = sprintf('hiding geometry share %.1f%% [%.1f, %.1f]', K.hide_share); end
S = struct('status', 'printed', 'input', f, 'sha256', side_sha256(f), 'K6C', K);
side_write(out, 'side_k6_split_p1', L, S);
fprintf('%s\n', L{:});
end
