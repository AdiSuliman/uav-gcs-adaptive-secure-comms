function rekey_pools(files)
%REKEY_POOLS  Gives frame pools built before a new temporal fusion (select_fusion.m,
%   data/fusion.mat) that fusion without simulating them again. A pool holds the
%   per-frame detector outputs only (pool_cell.m: build_policy_pools.m and
%   build_check_pools.m pass the detector without the fusion); the decision cycle
%   applies the fusion itself (policy_monitor.m). A new fusion therefore changes only
%   the keys PP.fuse, PP.fuse_N, PP.q_thr and PP.det_id (detector_id.m).
%   It stops, changing nothing, when the pools come from another detector network,
%   unknown-threat score or threshold, when they hold a field that is not known to be
%   independent of the fusion, or when a frame field is not a per-frame output.
%   Every file is copied to <name>_before_rekey_<time>.mat before it is saved.
%   files  pool files (default: data/policy_pools.mat, then data/check_pools.mat,
%          data/clean_val_pools.mat, data/clean_test_pools.mat, so the check pools stay
%          newer than the policy pools); a file without the keys (the clean-link pools)
%          is left as it is
%   Run from the repository root.
if nargin < 1
    files = {'data/policy_pools.mat', 'data/check_pools.mat', 'data/clean_val_pools.mat', 'data/clean_test_pools.mat'};
end
KEYS = {'fuse', 'fuse_N', 'q_thr', 'det_id'};
FRAME = {'probs', 'maha', 'feat', 'gant', 'ber', 'fer', 'crc', 'run', 'aoa', 'act'};   % pool_cell.m
KNOWN = [KEYS, {'scen', 'sev', 'level', 'sev_names', 'splits', 'cell_splits', 'cell_geo', 'threats', 'singles', ...
    'combos', 'ebno', 'actions', 'ngeo', 'ncomb', 'nhover', 'lhs', 'speed_range', 'speed_out', 'speed', 'cov', ...
    'alt', 'ksig', 'gp', 'bw', 'pw', 'pools', 'mber', 'mfer', 'clean', 'clean_fer', 'classes', 'maha_thr', ...
    'unk_win', 'F_SUB', 'fec_frames', 'runs', 'model_tag', 'aoa_random', 'k_random', 'sps', 'bps', 'feat_names', ...
    'created', 'kind', 'cell_ebs', 'ebno_grid', 'e_level', 'family', 'block'}];   % build_policy_pools.m, build_check_pools.m
D = load('data/trained_detector.mat', 'classes', 'ood', 'trained_at');
T = ood_thresholds(0.95);
FZ = fusion_model();
UW = 1; if isfield(D.ood, 'win'), UW = D.ood.win; end
classes = cellstr(string(D.classes(:)'));
new_id = detector_id(D.trained_at, D.ood, FZ, T.maha);
for i = 1:numel(files)
    f = files{i};
    if ~isfile(f), fprintf('%s: absent\n', f); continue; end
    var = intersect({'PP', 'CK'}, who('-file', f));
    if isempty(var), fprintf('%s: no detector keys, left as it is\n', f); continue; end
    L = load(f); X = L.(var{1});
    if ~all(isfield(X, KEYS)), fprintf('%s: no detector keys, left as it is\n', f); continue; end
    extra = setdiff(fieldnames(X)', KNOWN);
    if ~isempty(extra)
        error('rekey_pools:field', '%s: %s.%s may depend on the fusion; rebuild the pools', f, var{1}, strjoin(extra, ', '));
    end
    fl = cellfun(@fieldnames, X.pools(~cellfun(@isempty, X.pools)), 'UniformOutput', false);
    bad = setdiff(vertcat(cell(0, 1), fl{:}), FRAME);
    if ~isempty(bad)
        error('rekey_pools:frame', '%s: frame field %s is not a per-frame output (pool_cell.m); rebuild the pools', f, strjoin(bad, ', '));
    end
    old_id = detector_id(D.trained_at, D.ood, struct('FM', X.fuse, 'N', X.fuse_N, 'q_thr', X.q_thr), X.maha_thr);
    if ~strcmp(old_id, X.det_id) || ~isequal(X.classes, classes) || ~isequal(X.maha_thr, T.maha) || ~isequal(X.unk_win, UW)
        error('rekey_pools:detector', ['%s comes from another detector network, unknown-threat score or threshold, ' ...
            'not only another fusion; rebuild the pools'], f);
    end
    if strcmp(old_id, new_id), fprintf('%s: already keyed to this fusion\n', f); continue; end
    bak = sprintf('%s_before_rekey_%s.mat', f(1:end-4), char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
    if isfile(bak), error('rekey_pools:backup', '%s exists', bak); end
    [ok, msg] = copyfile(f, bak);
    if ~ok || dir(bak).bytes ~= dir(f).bytes, error('rekey_pools:backup', 'no backup of %s: %s', f, msg); end
    fprintf('%s: fusion %d -> %d inputs, N %d -> %d, q_thr %.2f -> %.2f dB, det_id %s -> %s (backup %s)\n', f, ...
        n_inputs(X.fuse), n_inputs(FZ.FM), X.fuse_N, FZ.N, X.q_thr, FZ.q_thr, X.det_id, new_id, bak);
    X.fuse = FZ.FM; X.fuse_N = FZ.N; X.q_thr = FZ.q_thr; X.det_id = new_id;
    L.(var{1}) = X;
    save(f, '-struct', 'L', '-v7.3');
end
end

function n = n_inputs(FM)
% Evidence columns of a fusion model, 0 without one.
n = 0; if ~isempty(FM), n = numel(FM.mu); end
end
