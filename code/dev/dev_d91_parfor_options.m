function dev_d91_parfor_options(job_dir)
%DEV_D91_PARFOR_OPTIONS  pool_schedule.m on a real pool: one worker with its own job storage
%   (job_dir, so no other session's pool is touched), parfor with its options over jobs handed
%   out longest first, and the results put back in job order as the survivability stages do.
%   Prints 'D91PROOF P_parfor PASS' or errors.
c = parcluster('Processes'); c.JobStorageLocation = job_dir; c.NumWorkers = 1;
pl = parpool(c, 1);
cl = onCleanup(@() delete(pl));
w = [1 5 3 5 2]; n = numel(w);
[ord, po] = pool_schedule(w, pl, 1);
res = cell(1, n); seen = zeros(1, n);
parfor (k = 1:n, po)
    j = ord(k);
    res{k} = j^2; seen(k) = j;
end
res(ord) = res;
ok = isequal(ord, [2 4 3 5 1]) && isequal(seen, ord) && isequal(cell2mat(res), (1:n).^2) && isobject(po);
fprintf('options of class %s, order %s\n', class(po), mat2str(ord));
if ~ok, fprintf('D91PROOF P_parfor FAIL\n'); error('dev_d91_parfor_options:fail', 'parfor options failed'); end
fprintf('D91PROOF P_parfor PASS\n');
end
