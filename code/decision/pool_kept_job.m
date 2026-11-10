function out = pool_kept_job(S, j)
%POOL_KEPT_JOB  One job of pool_lpt_kept.m: S.kept_fn(S, j), saved under its key in S.kept_dir.
if isa(S, 'parallel.pool.Constant'), S = S.Value; end
pool_checkpoint('save', S.kept_dir, j, S.kept_keys{j}, S.kept_fn(S, j));
out = [];
end
