function out = pool_lpt(fn, S, jobs, pl)
%POOL_LPT  The jobs of a parallel stage in a fixed order: out{i} = fn(S, jobs(i)).
%   Without a pool (pl empty) they run on this process in that order. On pool pl every job is
%   a future of its own (parfeval), submitted in that order; the pool runs its queue first in,
%   first out, one job per free worker, so with jobs sorted longest first (pool_schedule.m) a
%   free worker always takes the longest job left. S reaches each worker once, as a parfor
%   broadcast variable does (parallel.pool.Constant: fn gets it wrapped and takes its Value).
%   The lines a job prints are printed here when it ends. An error in a job stops the stage
%   and cancels the jobs not yet done; a pool builder's finished cells are already on disk.
n = numel(jobs); out = cell(1, n);
if isempty(pl) || n == 0
    for i = 1:n, out{i} = fn(S, jobs(i)); end
    return;
end
Sc = parallel.pool.Constant(S);
F(1:n) = parallel.FevalFuture;
for i = 1:n, F(i) = parfeval(pl, fn, 1, Sc, jobs(i)); end
cl = onCleanup(@() cancel(F)); %#ok<NASGU>
for m = 1:n
    [i, v] = fetchNext(F);
    out{i} = v;
    fprintf('%s', F(i).Diary);
end
end
