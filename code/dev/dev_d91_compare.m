function ok = dev_d91_compare(file_a, file_b, tag)
%DEV_D91_COMPARE  isequaln of two proof results (dev_d91_pool_run.m, dev_d91_order.m): per
%   cell info.map and n_unique, and every field of every pool (Eb/N0 x configuration x
%   split). Prints one line per cell and 'D91PROOF <tag> PASS' or 'FAIL'; errors on FAIL.
a = load(file_a); b = load(file_b);
ok = isequal(a.A, b.A) && isequal(a.eb, b.eb) && numel(a.R) == numel(b.R) && a.has_det == b.has_det;
if ~ok, fprintf('different layouts: %s, %s\n', file_a, file_b); end
for i = 1:min(numel(a.R), numel(b.R))
    ra = a.R(i); rb = b.R(i);
    ci = strcmp(ra.threat, rb.threat) && isequal(ra.info.map, rb.info.map) && ra.info.n_unique == rb.info.n_unique ...
        && isequal(size(ra.P), size(rb.P));
    bad = {}; nr = 0;
    for k = 1:numel(ra.P)
        Qa = ra.P{k}; Qb = rb.P{k};
        if ~isequal(sort(fieldnames(Qa)), sort(fieldnames(Qb))), bad{end+1} = sprintf('fields@%d', k); continue; end %#ok<AGROW>
        for f = fieldnames(Qa)'
            if ~isequaln(Qa.(f{1}), Qb.(f{1})), bad{end+1} = sprintf('%s@%d', f{1}, k); end %#ok<AGROW>
        end
        nr = nr + numel(Qa.ber);
    end
    ci = ci && isempty(bad);
    fprintf('  %-22s map %s | %d pools, %d frames, %d fields each | %s %s\n', ra.threat, mat2str(ra.info.map), numel(ra.P), ...
        nr, numel(fieldnames(ra.P{1})), ternary(ci, 'identical', 'DIFFERENT'), strjoin(unique(bad), ' '));
    ok = ok && ci;
end
fprintf('D91PROOF %s %s (detector %d)\n', tag, ternary(ok, 'PASS', 'FAIL'), a.has_det);
if ~ok, error('dev_d91_compare:fail', 'proof %s failed', tag); end
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
