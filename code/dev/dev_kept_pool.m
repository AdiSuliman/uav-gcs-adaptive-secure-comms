function dev_kept_pool(job_dir)
%DEV_KEPT_POOL  pool_lpt_kept.m on a pool of one worker with its own job storage (job_dir, so no
%   other session's pool is touched): every job, saved on the worker, comes back in job order, and
%   a second start with the same inputs runs none (the kept files keep their times).
%   Prints 'KEPTPOOL PASS'; errors on a failure.
d = tempname; ord = [3 1 2]; S = struct('a', 3);
fn = @(S, j) S.a * j * pool_schedule(1);                % a job that calls a file on the path
c = parcluster('Processes'); c.JobStorageLocation = job_dir; c.NumWorkers = 1;
pl = parpool(c, 1); cl = onCleanup(@() delete(pl)); %#ok<NASGU>
r1 = pool_lpt_kept(fn, S, ord, pl, d, 'dev');
t1 = kept_times(d, numel(ord));
pause(2);
r2 = pool_lpt_kept(fn, S, ord, pl, d, 'dev');
t2 = kept_times(d, numel(ord));
ok = isequal(r1, {3, 6, 9}) && isequal(r2, r1) && isequal(t1, t2);
pool_checkpoint('clear', d);
fprintf('results %s, again %s, kept files unchanged %d\n', mat2str(cell2mat(r1)), mat2str(cell2mat(r2)), isequal(t1, t2));
if ~ok, error('dev_kept_pool:fail', 'pool_lpt_kept failed on a pool'); end
fprintf('KEPTPOOL PASS\n');
end

function t = kept_times(d, n)
t = arrayfun(@(k) dir(fullfile(d, sprintf('cell_%04d.mat', k))).datenum, 1:n);
end
