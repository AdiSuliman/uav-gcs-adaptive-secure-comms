function ok = dev_d91_compare(file_a, file_b, tag)
%DEV_D91_COMPARE  isequaln of two proof results (dev_d91_pool_run.m, dev_d91_order.m): per
%   cell info.map and n_unique, and every field of every pool (Eb/N0 x configuration x
%   split). The proof covers the twins' own link_features and detector scores only when the
%   detector ran on both sides and every pool holds its features and scores for every frame.
%   Prints one line per cell and 'D91PROOF <tag> PASS', 'PARTIAL' (values identical, the
%   detector path not run) or 'FAIL', with the code's commit (dev_d91_code.m); errors on FAIL.
sha = dev_d91_code();
a = load(file_a); b = load(file_b);
ok = isequal(a.A, b.A) && isequal(a.eb, b.eb) && numel(a.R) == numel(b.R) && a.has_det == b.has_det;
if ~ok, fprintf('different layouts: %s, %s\n', file_a, file_b); end
det_ran = a.has_det && b.has_det;
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
        det_ran = det_ran && ~isempty(Qa.ber) && size(Qa.feat, 1) == numel(Qa.ber) && size(Qa.probs, 1) == numel(Qa.ber) ...
            && size(Qb.feat, 1) == numel(Qb.ber) && size(Qb.probs, 1) == numel(Qb.ber);
    end
    ci = ci && isempty(bad);
    fprintf('  %-22s map %s | %d pools, %d frames, %d fields each | %s %s\n', ra.threat, mat2str(ra.info.map), numel(ra.P), ...
        nr, numel(fieldnames(ra.P{1})), ternary(ci, 'identical', 'DIFFERENT'), strjoin(unique(bad), ' '));
    ok = ok && ci;
end
if ~ok
    v = 'FAIL';
elseif det_ran
    v = 'PASS';
else
    v = 'PARTIAL';
end
fprintf('D91PROOF %s %s (detector %d, features and scores on every frame %d) D91CODE %s\n', tag, v, a.has_det, det_ran, sha);
if ~ok, error('dev_d91_compare:fail', 'proof %s failed', tag); end
ok = det_ran;
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
