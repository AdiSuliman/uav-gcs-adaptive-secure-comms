function S = side_a7_fa_breakdown(txt_file, out_dir)
%SIDE_A7_FA_BREAKDOWN  C5: reprint of the system-level false-alarm breakdown (D103 3) from a saved system_fa_breakdown.txt,
%   a labelled side reading. Nothing is recomputed except the check that the per-Eb/N0 counts of table (a) add up to its
%   "all" column.
%   S = side_a7_fa_breakdown(txt_file, out_dir)
%   txt_file  a profile's system_fa_breakdown.txt (system_fa_breakdown.m output; opened read-only)
%   out_dir   a new folder; side_a7_fa_breakdown.txt and .mat are written there
if ~isfile(txt_file), error('side_a7:input', 'side_a7_fa_breakdown: %s not found', txt_file); end
t = splitlines(fileread(txt_file));
a = find(startsWith(t, '=== D103 3'), 1);
b = find(startsWith(t, '=== D103 4'), 1);
if isempty(a) || isempty(b) || b <= a, error('side_a7:field', 'side_a7_fa_breakdown: %s has no D103 3 section', txt_file); end
sec = t(a:b - 1);
while ~isempty(sec) && isempty(strtrim(sec{end})), sec(end) = []; end
notes = {sprintf('section D103 3 of the file, lines %d-%d, copied verbatim below; a count n/N is flights with at least one false change', a, a + numel(sec) - 1)};
L = side_header('C5: system-level false alarms on clean flights (D103 3)', txt_file, notes);
L = [L, sec(:)'];
L{end+1} = '';
% table (a): policy, six per-Eb/N0 counts, all
h = find(contains(sec, '(a) False-alarm episodes per Eb/N0'), 1);
rows = struct('policy', {}, 'k', {}, 'n', {}, 'k_all', {}, 'n_all', {}, 'sum_ok', {});
if ~isempty(h)
    for i = h + 2:numel(sec)
        if isempty(strtrim(sec{i})), break; end
        tok = regexp(sec{i}, '(\d+)/(\d+)', 'tokens');
        nm = strtrim(regexprep(sec{i}, '\s+\d+/\d+.*$', ''));
        if numel(tok) < 2, continue; end
        kn = str2double([tok{:}]);
        kk = reshape(kn, 2, [])';
        rows(end+1) = struct('policy', nm, 'k', kk(1:end-1, 1)', 'n', kk(1:end-1, 2)', 'k_all', kk(end, 1), 'n_all', kk(end, 2), ...
            'sum_ok', sum(kk(1:end-1, 1)) == kk(end, 1) && sum(kk(1:end-1, 2)) == kk(end, 2)); %#ok<AGROW>
    end
end
L{end+1} = sprintf('Check of table (a): %d policy rows read, per-Eb/N0 counts add up to the "all" column in %d', numel(rows), sum([rows.sum_ok]));
S = struct('input', txt_file, 'sha256', side_sha256(txt_file), 'first_line', a, 'last_line', a + numel(sec) - 1, ...
    'section', {sec}, 'table_a', rows);
out = side_out_dir(out_dir, txt_file);
side_write(out, 'side_a7_fa_breakdown', L, S);
fprintf('%s\n', L{:});
end
