function L = side_header(title, in_file, notes)
%SIDE_HEADER  Header lines of a side reading: label, input path, SHA-256 and size, and the reading choices.
%   L = side_header(title, in_file, notes)   notes: cellstr of lines on the choices taken where a definition leaves one
d = dir(in_file);
if isempty(d), error('side_header:input', 'side_header: %s not found', in_file); end
L = {sprintf('=== %s ===', title), 'side reading, decides nothing', ...
    sprintf('input: %s', canon(in_file)), sprintf('input SHA-256: %s', side_sha256(in_file)), ...
    sprintf('input size: %.1f MB, written %s', d.bytes / 2^20, d.date), ...
    sprintf('read %s', datestr(now, 'yyyy-mm-dd HH:MM:SS'))};
L = [L, notes(:)'];
L{end+1} = '';
end

function p = canon(p)
p = char(java.io.File(p).getCanonicalPath());
end
