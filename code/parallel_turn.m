function owner = parallel_turn(action, f)
%PARALLEL_TURN  One heavy parallel stage at a time across MATLAB sessions on this computer.
%   parallel_turn('take')   waits until no other live session holds the turn, then takes
%                           it; while it waits it prints the holder every hour
%   parallel_turn('give')   shuts this session's worker pool and gives the turn back
%   owner = parallel_turn('owner')   the MATLAB process that holds the turn, [] when free
%   parallel_turn(action, f)         the same on the turn file f (default in tempdir)
%   The two antenna profiles run side by side: their other stages overlap, their
%   parallel simulations (6 workers each) take turns, so memory stays within limits.
%   The turn is held only by a running MATLAB process under the recorded process id
%   with the turn file written since this computer last started; a turn left by a session
%   that no longer runs, or by a process id reused after a restart, is taken over.
if nargin < 2 || isempty(f), f = fullfile(tempdir, 'uav_gcs_parallel_turn.txt'); end
me = feature('getpid');
owner = [];
switch action
    case 'take'
        boot = boot_time(); t0 = tic; said = 0;
        while true
            owner = holder(f, boot);
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
        owner = holder(f, boot_time());
    otherwise
        error('parallel_turn: action ''take'', ''give'' or ''owner''');
end
end

function owner = holder(f, boot)
% The recorded process while it holds the turn: a MATLAB process under that id, the file
% written after the last start of the computer; [] otherwise.
owner = read_owner(f);
if isempty(owner), return; end
d = dir(f);
if isempty(d) || d.datenum < boot || ~matlab_alive(owner), owner = []; end
end

function owner = read_owner(f)
owner = [];
if isfile(f)
    v = str2double(strtrim(fileread(f)));
    if isfinite(v), owner = v; end
end
end

function alive = matlab_alive(pid)
% A process with this id runs the MATLAB image.
[~, out] = system(sprintf('tasklist /FI "PID eq %d" /FI "IMAGENAME eq MATLAB.exe" /NH', pid));
alive = contains(out, sprintf(' %d ', pid));
end

function t = boot_time()
% Last start of this computer as a datenum (local time); -Inf when not reported.
t = -Inf;
[st, out] = system(['powershell -NoProfile -Command "(Get-CimInstance Win32_OperatingSystem).LastBootUpTime' ...
    '.ToString(''yyyy-MM-dd HH:mm:ss'')"']);
s = regexp(out, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}', 'match', 'once');
if st == 0 && ~isempty(s), t = datenum(s, 'yyyy-mm-dd HH:MM:SS'); end
end
