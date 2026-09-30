function parallel_turn(action)
%PARALLEL_TURN  One heavy parallel stage at a time across MATLAB sessions on this computer.
%   parallel_turn('take')  waits until no other live session holds the turn, then takes it
%   parallel_turn('give')  shuts this session's worker pool and gives the turn back
%   The two antenna profiles run side by side: their other stages overlap, their
%   parallel simulations (6 workers each) take turns, so memory stays within limits.
%   A turn held by a session that no longer runs is taken over.
f = fullfile(tempdir, 'uav_gcs_parallel_turn.txt');
me = feature('getpid');
switch action
    case 'take'
        said = false;
        while true
            owner = read_owner(f);
            if isempty(owner) || owner == me || ~pid_alive(owner)
                fid = fopen(f, 'w'); fprintf(fid, '%d', me); fclose(fid);
                pause(2);
                if read_owner(f) == me, break; end       % two sessions wrote at once: the later write wins
            elseif ~said
                fprintf('Waiting for the parallel turn (held by MATLAB process %d)...\n', owner); said = true;
            end
            pause(30);
        end
        if said, fprintf('Parallel turn taken.\n'); end
    case 'give'
        delete(gcp('nocreate'));
        if read_owner(f) == me, delete(f); end
    otherwise
        error('parallel_turn: action ''take'' or ''give''');
end
end

function owner = read_owner(f)
owner = [];
if isfile(f)
    v = str2double(strtrim(fileread(f)));
    if isfinite(v), owner = v; end
end
end

function alive = pid_alive(pid)
[~, out] = system(sprintf('tasklist /FI "PID eq %d" /NH', pid));
alive = contains(out, sprintf(' %d ', pid));
end
