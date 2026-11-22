function S = side_a7_clean_pool_vars(clean_files, model_file, bw_pools, out_dir)
%SIDE_A7_CLEAN_POOL_VARS  C3: the variables of the clean pools and of CORE_BW's saved inputs, and whether rule_core3's
%   clean-flight false changes can be read by replaying them, a labelled side reading (decides nothing).
%   S = side_a7_clean_pool_vars(clean_files, model_file, bw_pools, out_dir)
%   clean_files  cell of clean-pool files (data/clean_test_pools.mat, data/clean_val_pools.mat); each is loaded and its
%                nested fields are listed (these files are a few hundred MB)
%   model_file   data/core_cnn_model.mat (the three-state CNN of rule_core3); '' or missing: reported as absent
%   bw_pools     CORE_BW's data/core_bw/pools.mat: header (whos) and the small variable core3_id only, never loaded whole
%   out_dir      a new folder; side_a7_clean_pool_vars.txt and .mat are written there
%   rule_core3's class comes from the three-state CNN's window over probs3 (frames x 3 per frame, pool_cell.m, policy_monitor.m,
%   policy_decide.m: an error without obs.probs3). A replay needs probs3 in every clean pool, scored by the registered
%   model (core3_id); without it the CNN would need the frames' spectrograms (X), which pools do not keep: a rebuild.
if ischar(clean_files), clean_files = {clean_files}; end
if nargin < 2, model_file = ''; end
if nargin < 3, bw_pools = ''; end
for i = 1:numel(clean_files)
    if ~isfile(clean_files{i}), error('side_a7:input', 'side_a7_clean_pool_vars: %s not found', clean_files{i}); end
end
notes = {'the CNN path of rule_core3 reads obs.probs3 (frames x 3: clean, narrowband, wideband) in every pool (core_bw_rules core3_pools)', ...
    'a replay is possible only when the clean pools hold probs3 scored by the registered model; the CNN itself reads spectrograms the pools do not keep'};
L = side_header('C3: clean pools and CORE_BW inputs, replay or rebuild', clean_files{1}, notes);
S = struct('files', struct('file', {}, 'vars', {}, 'fields', {}, 'has_probs3', {}, 'has_image', {}, 'has_core3_id', {}));
for i = 1:numel(clean_files)
    f = clean_files{i};
    L{end+1} = sprintf('--- %s (%.1f MB, SHA-256 %s)', f, dir(f).bytes / 2^20, side_sha256(f)); %#ok<AGROW>
    w = whos('-file', f);
    L{end+1} = '  top-level variables (name, class, size):'; %#ok<AGROW>
    for k = 1:numel(w), L{end+1} = sprintf('    %-24s %-10s %s', w(k).name, w(k).class, mat2str(w(k).size)); end %#ok<AGROW>
    X = load(f);
    names = collect_names(X, '', 0);
    L{end+1} = sprintf('  nested field names (%d distinct):', numel(names)); %#ok<AGROW>
    L{end+1} = ['    ' strjoin(names, ', ')]; %#ok<AGROW>
    leaf = cellfun(@(n) n(find(n == '.', 1, 'last') + 1:end), names, 'UniformOutput', false);
    hp3 = any(strcmp(leaf, 'probs3'));
    him = any(~cellfun(@isempty, regexp(leaf, '^(X|img|image|spec|spectrogram|spectrograms)$', 'once')));
    hid = any(strcmp({w.name}, 'core3_id')) || any(strcmp(leaf, 'core3_id'));
    L{end+1} = sprintf('  probs3 present: %d | spectrogram-like field present: %d | core3_id present: %d', hp3, him, hid); %#ok<AGROW>
    L{end+1} = ''; %#ok<AGROW>
    S.files(end+1) = struct('file', f, 'vars', {{w.name}}, 'fields', {names}, 'has_probs3', hp3, 'has_image', him, 'has_core3_id', hid); %#ok<AGROW>
    clear X
end
L{end+1} = '--- three-state CNN model';
S.model = struct('file', model_file, 'present', false, 'vars', {{}});
if isempty(model_file) || ~isfile(model_file)
    L{end+1} = sprintf('  %s: absent (no three-state CNN in this profile)', model_file);
else
    w = whos('-file', model_file);
    S.model = struct('file', model_file, 'present', true, 'vars', {{w.name}});
    L{end+1} = sprintf('  %s (%.1f MB, SHA-256 %s)', model_file, dir(model_file).bytes / 2^20, side_sha256(model_file));
    for k = 1:numel(w), L{end+1} = sprintf('    %-24s %-10s %s', w(k).name, w(k).class, mat2str(w(k).size)); end %#ok<AGROW>
end
L{end+1} = '';
L{end+1} = '--- CORE_BW saved pools (header and core3_id only)';
S.bw = struct('file', bw_pools, 'present', false, 'vars', {{}}, 'core3_id', '');
if isempty(bw_pools) || ~isfile(bw_pools)
    L{end+1} = sprintf('  %s: absent', bw_pools);
else
    w = whos('-file', bw_pools);
    L{end+1} = sprintf('  %s (%.1f MB)', bw_pools, dir(bw_pools).bytes / 2^20);
    for k = 1:numel(w), L{end+1} = sprintf('    %-24s %-10s %s', w(k).name, w(k).class, mat2str(w(k).size)); end %#ok<AGROW>
    id = '';
    if any(strcmp({w.name}, 'core3_id')), t = load(bw_pools, 'core3_id'); id = t.core3_id; end
    L{end+1} = sprintf('  core3_id: %s', pick(isempty(id), 'not present', id));
    S.bw = struct('file', bw_pools, 'present', true, 'vars', {{w.name}}, 'core3_id', id);
end
L{end+1} = '';
all_p3 = ~isempty(S.files) && all([S.files.has_probs3]);
if all_p3
    verdict = 'REPLAY: every clean pool holds probs3; rule_core3 can be replayed on the saved clean pools (check core3_id against the registered model first)';
else
    verdict = ['REBUILD (P1-v2): the clean pools hold no probs3 and no spectrogram, so the three-state CNN has no input in them; ' ...
        'its scores exist only in CORE_BW''s own pools (jammer cells) and a clean-flight reading needs the clean flights re-simulated and scored'];
end
L{end+1} = verdict;
S.verdict = verdict; S.replay = all_p3;
out = side_out_dir(out_dir, clean_files);
side_write(out, 'side_a7_clean_pool_vars', L, S);
fprintf('%s\n', L{:});
end

function names = collect_names(x, pre, depth)
% Distinct dotted field names of nested structs and cells (the first elements, three levels).
names = {};
if depth > 4, return; end
if isstruct(x)
    f = fieldnames(x)';
    for i = 1:numel(f)
        nm = [pre '.' f{i}];
        if isempty(pre), nm = f{i}; end
        names{end+1} = nm; %#ok<AGROW>
        for k = 1:min(numel(x), 3)
            names = [names, collect_names(x(k).(f{i}), nm, depth + 1)]; %#ok<AGROW>
        end
    end
elseif iscell(x)
    q = find(~cellfun(@isempty, x(:)), 3)';
    for k = q
        names = [names, collect_names(x{k}, pre, depth + 1)]; %#ok<AGROW>
    end
end
names = unique(names, 'stable');
end

function s = pick(c, a, b)
if c, s = a; else, s = b; end
end
