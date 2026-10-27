function out = kpi6_fresh_marker(cmd, f, varargin)
%KPI6_FRESH_MARKER  The single reading of the fresh clean test set (P1R's KPI 6,
%   docs/p1r_protocol.md section 5). evaluate_policies.m writes the marker f
%   (results/kpi6_fresh_read_started.txt) before its first fresh flight and refuses a second
%   start unless the marker records a crash before any KPI 6 line.
%   h = kpi6_fresh_marker('sha', file)   SHA-256 of a file, as sha256sum prints it
%   st = kpi6_fresh_marker('check', f, sha)   with the other checks, before any fresh flight:
%       'new' without a marker; 'restart' when the marker is of the same pools file (sha), holds
%       no KPI 6 reading and its last event is a crash before any KPI 6 line; otherwise it stops
%       (a reading started and was not recorded as crashed before its KPI 6 line: Adi decides)
%   kpi6_fresh_marker('start', f, sha, info)   'new': writes the marker (time, the code's commit
%       and tree, the pools' SHA-256 sha, then one line per field of info: the pools file, the
%       degradation test, det_id, the policy stamp); 'restart': appends a restart line
%   kpi6_fresh_marker('crash', f, err)   appends "crash before any KPI 6 line" with the error
%   kpi6_fresh_marker('read', f)   appends "KPI 6 read": from then on every start is refused
out = [];
switch cmd
    case 'sha'
        out = file_sha(f);
    case 'check'
        sha = varargin{1};
        if ~isfile(f), out = 'new'; return; end
        L = marker_lines(f);
        if any(startsWith(L, 'KPI 6 read'))
            error('kpi6_fresh_marker:read', ['%s: the fresh clean test set was read (its flights flown, KPI 6 reached); it is read ' ...
                'once (docs/p1r_protocol.md section 4): a second reading is refused'], f);
        end
        if ~any(strcmp(L, ['pools sha256 ' sha]))
            error('kpi6_fresh_marker:pools', ['%s: a reading of another fresh pools file started (this one: %s); ' ...
                'a second reading is refused'], f, sha);
        end
        ev = L(startsWith(L, {'crash before any KPI 6 line', 'restart '}));
        if isempty(ev) || ~startsWith(ev{end}, 'crash before any KPI 6 line')
            error('kpi6_fresh_marker:started', ['%s: a reading of the fresh clean test set started and no crash before ' ...
                'its KPI 6 line is recorded (a stopped MATLAB records none): a second start is refused; Adi decides'], f);
        end
        out = 'restart';
    case 'start'
        [sha, info] = varargin{:};
        if isfile(f)
            append_line(f, sprintf('restart %s after a crash before any KPI 6 line', stamp()));
            out = 'restart';
            return
        end
        [cm, tr] = code_commit();
        lines = {'P1R: KPI 6 reading of the fresh clean test set started (docs/p1r_protocol.md section 5)', ...
            ['time ' stamp()], ['commit ' cm], ['code_tree ' tr], ['pools sha256 ' sha]};
        for k = reshape(fieldnames(info), 1, [])
            lines{end+1} = sprintf('%s %s', k{1}, val_txt(info.(k{1}))); %#ok<AGROW>
        end
        d = fileparts(f);
        if ~isempty(d) && ~isfolder(d), mkdir(d); end
        fid = fopen(f, 'w');
        assert(fid > 0, 'kpi6_fresh_marker:write', 'cannot write %s', f);
        fprintf(fid, '%s\n', lines{:}); fclose(fid);
        out = 'new';
    case 'crash'
        err = varargin{1};
        append_line(f, sprintf('crash before any KPI 6 line %s: %s', stamp(), regexprep(err.message, '\s+', ' ')));
    case 'read'
        append_line(f, sprintf('KPI 6 read %s', stamp()));
    otherwise
        error('kpi6_fresh_marker:cmd', 'kpi6_fresh_marker: unknown command %s', cmd);
end
end

function L = marker_lines(f)
L = strtrim(regexp(fileread(f), '\r?\n', 'split'));
L = L(~cellfun(@isempty, L));
end

function append_line(f, s)
fid = fopen(f, 'a');
assert(fid > 0, 'kpi6_fresh_marker:write', 'cannot write %s', f);
fprintf(fid, '%s\n', s); fclose(fid);
end

function s = stamp()
s = datestr(now, 'yyyy-mm-dd HH:MM:SS');
end

function t = val_txt(v)
if ischar(v) || isstring(v), t = char(v);
elseif isnumeric(v) || islogical(v), t = mat2str(v);
else, t = class(v);
end
end

function [cm, tr] = code_commit()
% The checkout's commit and code tree, with a note when code has local changes ('unknown'
% outside a git checkout).
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
g = sprintf('git --no-optional-locks -C "%s" ', root);
[st, o] = system([g 'rev-parse HEAD HEAD:code']);
[sd, d] = system([g 'status --porcelain --untracked-files=all -- code profile.json']);
o = strsplit(strtrim(o)); cm = 'unknown'; tr = 'unknown';
if st == 0 && numel(o) == 2, cm = o{1}; tr = o{2}; end
if st == 0 && (sd ~= 0 || ~isempty(strtrim(d))), cm = [cm ' + local changes in code or profile.json']; end
end

function h = file_sha(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
assert(fid > 0, 'kpi6_fresh_marker:read', 'cannot read %s', f);
c = onCleanup(@() fclose(fid));
while true
    b = fread(fid, 2^25, '*uint8');
    if isempty(b), break; end
    md.update(b);
end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
