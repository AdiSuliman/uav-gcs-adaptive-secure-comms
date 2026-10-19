function r = dev_d91_tick(S, j)
%DEV_D91_TICK  A job of known length for the order proof (dev_d91_parfor_options.m): the time
%   it started (posix seconds), then S.sec(j) seconds of waiting. r = [j, start, process id].
if isa(S, 'parallel.pool.Constant'), S = S.Value; end
t = posixtime(datetime('now'));
pause(S.sec(j));
r = [j, t, feature('getpid')];
end
