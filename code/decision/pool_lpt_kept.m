function out = pool_lpt_kept(fn, S, ord, pl, CKD, tag)
%POOL_LPT_KEPT  pool_lpt.m with each job's result kept on disk as the job ends (pool_checkpoint.m),
%   so a stage stopped at any point (a power loss, an error) resumes with the jobs it has.
%   fn     the job, fn(S, j) -> its result (pool_job.m)
%   S      the stage's variables (a struct); ord the jobs 1..n in their order (pool_schedule.m)
%   pl     the pool ([] this process); CKD the folder of the kept jobs
%   tag    the stage's name, part of every job's key
%   out{j} job j's result, in job order (not ord's). Job j's key is the SHA-256 of tag, S and j,
%   so a job is kept only from a start with the same inputs. The caller removes CKD
%   (pool_checkpoint 'clear') once its own output is saved.
n = numel(ord);
hs = pool_checkpoint('key', {tag, S});
keys = arrayfun(@(j) pool_checkpoint('key', {hs, j}), 1:n, 'UniformOutput', false);
todo = pool_checkpoint('todo', CKD, keys);
run = ord(ismember(ord, todo));
fprintf('%d of %d jobs kept from an earlier start (%s)\n', n - numel(run), n, CKD);
S.kept_fn = fn; S.kept_dir = CKD; S.kept_keys = keys;
pool_lpt(@pool_kept_job, S, run, pl);
out = cell(1, n);
for j = 1:n, out{j} = pool_checkpoint('load', CKD, j); end
end
