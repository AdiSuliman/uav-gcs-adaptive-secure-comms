function dev_d91_parfor_options(job_dir)
%DEV_D91_PARFOR_OPTIONS  Proof (P) of docs/d91_speed.md: pool_lpt.m starts the jobs in
%   pool_schedule.m's order. Jobs of known length (dev_d91_tick.m) record when they start, on
%   this process, then on a pool of one worker and on one of two, each with its own job storage
%   (job_dir, so no other session's pool is touched). One worker must start them exactly in
%   that order; with two, every job must start after all jobs two or more places before it.
%   Every result must come back at its place and, put back by the order, in job order.
%   Prints 'D91PROOF P_parfor' (this process and one worker) and 'D91PROOF P_order2' (two
%   workers; SKIPPED when that pool cannot start): PASS or FAIL; errors on a FAIL.
sha = dev_d91_code();
w = [1 5 3 5 2 4 1 3];
ord = pool_schedule(w);
S = struct('sec', 0.2 * w);
ok = isequal(ord, [2 4 6 3 8 5 1 7]);
fprintf('order %s for costs %s\n', mat2str(ord), mat2str(w));
ok = check(pool_lpt(@dev_d91_tick, S, ord, []), ord, 1, 'this process') && ok;
res2 = 'SKIPPED';
for nw = [1 2]
    try
        c = parcluster('Processes'); c.JobStorageLocation = job_dir; c.NumWorkers = nw;
        pl = parpool(c, nw);
    catch e
        if nw == 1, rethrow(e); end
        fprintf('two-worker pool not started: %s\n', e.message);
        break;
    end
    try
        r = pool_lpt(@dev_d91_tick, S, ord, pl);
    catch e
        delete(pl); rethrow(e);
    end
    delete(pl);
    okw = check(r, ord, nw, sprintf('%d worker(s)', nw));
    if nw == 1, ok = ok && okw; else, res2 = verdict(okw); end
end
fprintf('D91PROOF P_parfor %s D91CODE %s\n', verdict(ok), sha);
fprintf('D91PROOF P_order2 %s D91CODE %s\n', res2, sha);
if ~ok || strcmp(res2, 'FAIL'), error('dev_d91_parfor_options:fail', 'pool_lpt order failed'); end
end

function ok = check(r, ord, nw, where)
% Results at their places, back in job order, and the start times in the order of the places.
n = numel(ord);
R = vertcat(r{:});
t = R(:, 2) - min(R(:, 2));
ok = isequal(R(:, 1)', ord);
back = r; back(ord) = r;
ok = ok && isequal(cellfun(@(x) x(1), back), 1:n);
for i = nw + 1:n
    ok = ok && all(t(1:i - nw) <= t(i));
end
[~, started] = sort(t');
ok = ok && numel(unique(R(:, 3))) == nw;
fprintf('%s: start times %s s, jobs in the order they started %s, %d process(es): %s\n', where, ...
    mat2str(t', 3), mat2str(ord(started)), numel(unique(R(:, 3))), verdict(ok));
end

function s = verdict(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end
