function owner = parallel_turn(action, f)
%PARALLEL_TURN  One heavy parallel stage at a time across MATLAB sessions on this computer.
%   parallel_turn('take')   waits until no other live session holds the turn, then takes
%                           it; while it waits it prints the holder every hour
%   parallel_turn('give')   shuts this session's worker pool and gives the turn back
%   owner = parallel_turn('owner')   the MATLAB process that holds the turn, [] when free
%   parallel_turn(action, f)         the same on the turn file f (default in tempdir)
%   The two antenna profiles run side by side: their other stages overlap, their
%   parallel simulations (6 workers each) take turns, so memory stays within limits.
%   The turn is held only by a running MATLAB session (its win64 process, not the
%   launcher) under the recorded process id that started before the turn file was
%   written; a turn left by a session that no longer runs, or a process id reused by a
%   later process (after any restart, Fast Startup included), is taken over.
if nargin < 2 || isempty(f), f = fullfile(tempdir, 'uav_gcs_parallel_turn.txt'); end
me = feature('getpid');
owner = [];
switch action
    case 'take'
        t0 = tic; said = 0;
        while true
            owner = holder(f);
            if isempty(owner) || owner == me
                fid = fopen(f, 'w'); fprintf(fid, '%d', me); fclose(fid);
                pause(2);
                if read_owner(f) == me, break; end       % two sessions wrote at once: the later write wins
            elseif toc(t0) >= 3600 * said
                if said == 0
                    fprintf('Waiting for the parallel turn (held by MATLAB process %d)...\n', owner);
                else
                    fprintf('Still waiting for the parallel turn after %d h (held by MATLAB process %d).\n', said, owner);
                end
                said = said + 1;
            end
            pause(30);
        end
        if said, fprintf('Parallel turn taken.\n'); end
        owner = me;
    case 'give'
        delete(gcp('nocreate'));
        if read_owner(f) == me, delete(f); end
    case 'owner'
        owner = holder(f);
    otherwise
        error('parallel_turn: action ''take'', ''give'' or ''owner''');
end
end

function owner = holder(f)
% The recorded process while it holds the turn: a MATLAB session under that id that
% started before the turn file was written; [] otherwise. Times in UTC milliseconds.
owner = read_owner(f);
if isempty(owner), return; end
if ~(matlab_start(owner) <= java.io.File(f).lastModified()), owner = []; end
end

function owner = read_owner(f)
owner = [];
if isfile(f)
    v = str2double(strtrim(fileread(f)));
    if isfinite(v), owner = v; end
end
end

function t = matlab_start(pid)
% Start of the MATLAB session (win64 image) under this process id in UTC milliseconds
% since 1970; NaN when no such process runs.
[st, out] = system(sprintf(['powershell -NoProfile -Command "$p = Get-Process -Id %d -ErrorAction SilentlyContinue; ' ...
    'if ($p -and $p.Path -like ''*win64*'') { [long]($p.StartTime.ToUniversalTime() - [datetime]''1970-01-01'').TotalMilliseconds }"'], pid));
t = NaN;
if st == 0, t = str2double(regexp(out, '^\s*\d+\s*$', 'match', 'once')); end
end
