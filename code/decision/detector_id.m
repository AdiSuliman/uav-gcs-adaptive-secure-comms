function id = detector_id(trained_at, ood, FZ, maha_thr)
%DETECTOR_ID  Identity of the detector behind a set of frame pools: a SHA-256 hash
%   (16 hex digits) of the training time of data/trained_detector.mat, its unknown-threat
%   score and window (ood.score, ood.win), the temporal fusion and the quiet-slot alarm
%   threshold (FZ.FM, FZ.N, FZ.q_thr, data/fusion.mat; NaN when absent) and the
%   unknown-threat threshold. build_policy_pools.m stores it in
%   PP.det_id, train_dqn.m with the agent; evaluate_policies.m and edge_map.m stop when
%   they differ (check_det_id.m).
score = ''; win = 1; qt = NaN;
if isfield(ood, 'score'), score = ood.score; end
if isfield(ood, 'win'), win = ood.win; end
if isfield(FZ, 'q_thr'), qt = FZ.q_thr; end
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(getByteStreamFromArray({double(trained_at), char(score), double(win), FZ.FM, double(FZ.N), double(qt), double(maha_thr)}));
h = typecast(md.digest(), 'uint8');
id = lower(reshape(dec2hex(h(1:8))', 1, []));
end
