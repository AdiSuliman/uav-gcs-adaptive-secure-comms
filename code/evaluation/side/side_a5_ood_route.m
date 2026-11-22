function R = side_a5_ood_route(fold_dir, select_mat, out_dir, opts)
%SIDE_A5_OOD_ROUTE  Validation screen of a family-routed unknown-threat statistic on D111's saved folds.
%   R = side_a5_ood_route(fold_dir, select_mat, out_dir)
%   R = side_a5_ood_route(fold_dir, select_mat, out_dir, opts)
%   fold_dir    folder of D111's fold files fold_<h>.mat (k, known, Sv, V, Wv, F; validation only)
%   select_mat  D111's ood_k2_select.mat (A, Bd, held_out, CN, NW): the registered validation reading
%   out_dir     new output folder (a5_ood_route.txt, a5_ood_route.mat)
%   opts        nb (bootstrap draws, default 2000), nonemit (non-emitter classes), title
%   Only validation windows are read; no test set is loaded.
%   Candidates, fixed before any reading:
%     C0..C4  D111's candidates as saved in Wv (reproduced first: AUROC and bootstrap draws)
%     R1      Mondrian conformal p-value (Vovk 2012, Sec. 4, eq. 10) over three categories:
%             emitter route (the fold CNN's posterior mass on the known non-emitter classes < 0.5)
%             scored by s0; non-emitter route with a full cue window scored by the cue-Maha
%             p-value (C3); non-emitter route without a full window scored by s0. Each p-value is
%             calibrated on the fit half's known windows of its own category.
%     R1g     the same routing with D111's global p-values (no per-category calibration)
%   AUROC: lower = more novel, the selection half's known windows against the held-out threat's
%   windows (ood_k2_rules 'auroc'). Bootstrap: D111's sub-run resampling within each threat and
%   seeds (9800 + h), so C0's draws equal the saved Bd.
if nargin < 4, opts = struct(); end
nb = getf(opts, 'nb', 2000);
nonemit = getf(opts, 'nonemit', {'none', 'path_loss', 'antenna_fault', 'airframe_shadowing'});
ttl = getf(opts, 'title', 'A5 P-2 SCREEN: FAMILY-ROUTED UNKNOWN-THREAT STATISTIC (validation only)');
assert(~contains(lower(fold_dir), 'fresh') && ~contains(lower(select_mat), 'fresh'), 'side_a5_ood_route:fresh', ...
    'side_a5_ood_route: validation inputs only');
S = load(select_mat, 'A', 'Bd', 'held_out', 'CN', 'NW');
T = numel(S.held_out);
files = arrayfun(@(h) fullfile(fold_dir, sprintf('fold_%d.mat', h)), 1:T, 'UniformOutput', false);
od = side_out_dir(out_dir, [{select_mat}, files]);
L = side_header(ttl, select_mat, {sprintf('fold files: %s (fold_1..fold_%d)', fold_dir, T), ...
    'validation windows only (the selection half''s known windows against each held-out threat''s windows)', ...
    sprintf('non-emitter classes of the router: %s; route threshold 0.5 of the posterior mass', strjoin(nonemit, ', ')), ...
    sprintf('bootstrap: %d draws, sub-runs within each threat, seeds 9800 + h (D111)', nb)});
for h = 1:T, L{end+1} = sprintf('fold %d SHA-256 %s', h, side_sha256(files{h})); end %#ok<AGROW>
L{end+1} = '';
CN = [S.CN(:)', {'R1', 'R1g'}]; J = numel(CN);
A = nan(T, J); B = nan(nb, T, J); rep_err = zeros(T, 2); idn = nan(T, 2);
dg = nan(T, 4);                                   % un routed N, kn routed N, kn N&full share, check C1
for h = 1:T
    F0 = load(files{h}, 'k', 'known', 'Sv', 'V', 'Wv', 'F');
    assert(strcmp(F0.k, S.held_out{h}), 'side_a5_ood_route:fold', 'fold %d holds %s, not %s', h, F0.k, S.held_out{h});
    [u, d] = route_stat(F0, S.NW, nonemit);
    Wall = [F0.Wv, u.R1, u.R1g];
    kn = F0.F.kn(:); un = F0.F.un(:);
    for j = 1:J, A(h, j) = ood_k2_rules('auroc', Wall(kn, j), Wall(un, j)); end
    B(:, h, :) = reshape(ood_k2_rules('boot_auroc', Wall, kn, un, F0.V.run, nb, 9800 + h), nb, 1, J);
    nj = size(S.A, 2);
    rep_err(h, 1) = max(abs(A(h, 1:nj) - S.A(h, :)));
    if nb == size(S.Bd, 1), rep_err(h, 2) = max(abs(reshape(B(:, h, 1:nj), nb, nj) - reshape(S.Bd(:, h, :), nb, nj)), [], 'all'); end
    idn(h, :) = [d.c1_ok, d.c3_ok];
    dg(h, :) = [d.un_N, d.kn_N, d.kn_Nfull, d.c1_ok];
    clear F0
end
R = struct('held_out', {S.held_out}, 'CN', {CN}, 'A', A, 'mean', mean(A, 1), 'rep_err', rep_err, 'identity', idn, ...
    'diag', dg);
% Mean over threats and its 95% interval; paired difference against C0
mB = squeeze(mean(B, 2));                           % nb x J
R.ci = prctile(mB, [2.5 97.5], 1)';
R.d0 = R.mean - R.mean(1); R.d0_ci = prctile(mB - mB(:, 1), [2.5 97.5], 1)';
R.d0_lb5 = prctile(mB - mB(:, 1), 5, 1);
% Nested: the candidate with the highest mean over the other threats, read on this one
pool = [1:numel(S.CN), find(strcmp(CN, 'R1'))];
R.nest = nan(1, T); R.nest_pick = cell(1, T);
for h = 1:T
    o = setdiff(1:T, h); [~, b] = max(mean(A(o, pool), 1));
    R.nest(h) = A(h, pool(b)); R.nest_pick{h} = CN{pool(b)};
end
Bn = zeros(nb, T);
for h = 1:T, Bn(:, h) = B(:, h, strcmp(CN, R.nest_pick{h})); end
R.nest_mean = mean(R.nest); R.nest_ci = prctile(mean(Bn, 2), [2.5 97.5]);
% D111 rule (a)-(b) for R1 against C0 ((c) needs frame labels, not in the fold files)
j1 = find(strcmp(CN, 'R1'));
R.rule_a = R.mean(j1) >= R.mean(1) + 0.010 && R.d0_lb5(j1) > 0;
R.rule_b = all(A(:, j1) - A(:, 1) >= -0.03);
near = ismember(S.held_out, {'antenna_fault', 'airframe_shadowing'});
R.near = mean(A(near, :), 1); R.far = mean(A(~near, :), 1);
% Report
L{end+1} = sprintf('Reproduction of D111''s saved reading: max |AUROC - saved A| %.2g, max |boot draw - saved Bd| %.2g (C0..C4)', ...
    max(rep_err(:, 1)), max(rep_err(:, 2)));
L{end+1} = sprintf('Identity checks of the saved windows (C1 = min(p0, C3) on full windows and C3 = p0 elsewhere): %d of %d folds, %d of %d folds', ...
    sum(idn(:, 1) == 1), T, sum(idn(:, 2) == 1), T);
L{end+1} = '';
L{end+1} = sprintf('%-20s%s', 'held-out threat', sprintf(' %8s', CN{:}));
for h = 1:T, L{end+1} = sprintf('%-20s%s', S.held_out{h}, sprintf(' %8.3f', A(h, :))); end %#ok<AGROW>
L{end+1} = sprintf('%-20s%s', 'mean', sprintf(' %8.3f', R.mean));
L{end+1} = sprintf('%-20s%s', '  95% low', sprintf(' %8.3f', R.ci(:, 1)));
L{end+1} = sprintf('%-20s%s', '  95% high', sprintf(' %8.3f', R.ci(:, 2)));
L{end+1} = sprintf('%-20s%s', 'minus C0', sprintf(' %+8.3f', R.d0));
L{end+1} = sprintf('%-20s%s', 'near-OOD mean', sprintf(' %8.3f', R.near));
L{end+1} = sprintf('%-20s%s', 'far-OOD mean', sprintf(' %8.3f', R.far));
L{end+1} = '';
L{end+1} = sprintf('R1 minus C0, mean: %+.3f [%+.3f, %+.3f], one-sided 5th percentile %+.4f', R.d0(j1), R.d0_ci(j1, 1), ...
    R.d0_ci(j1, 2), R.d0_lb5(j1));
L{end+1} = sprintf('D111 rule on R1: (a) %s, (b) %s (largest loss %+.3f on %s), (c) not computable from the fold files (no frame labels)', ...
    tf(R.rule_a), tf(R.rule_b), min(A(:, j1) - A(:, 1)), S.held_out{find(A(:, j1) - A(:, 1) == min(A(:, j1) - A(:, 1)), 1)});
L{end+1} = sprintf(['Nested validation estimate (candidate with the highest mean over the other nine threats among %s, ' ...
    'read on the held-out one): mean %.3f [%.3f, %.3f]; picks %s'], strjoin(CN(pool), ', '), R.nest_mean, R.nest_ci(1), ...
    R.nest_ci(2), strjoin(R.nest_pick, ' '));
L{end+1} = sprintf('Target 0.8 on validation: R1 mean %s, R1 lower bound %s, nested %s', tf(R.mean(j1) >= 0.8), ...
    tf(R.ci(j1, 1) >= 0.8), tf(R.nest_mean >= 0.8));
L{end+1} = '';
L{end+1} = 'Router (per fold): held-out windows routed non-emitter | known windows routed non-emitter | of those, full cue window';
for h = 1:T
    L{end+1} = sprintf('  %-20s %6.1f%% %6.1f%% %6.1f%%', S.held_out{h}, 100 * dg(h, 1), 100 * dg(h, 2), 100 * dg(h, 3)); %#ok<AGROW>
end
fid = fopen(fullfile(od, 'a5_ood_route.txt'), 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
save(fullfile(od, 'a5_ood_route.mat'), 'R');
fprintf('%s\n', L{:});
end

function [u, d] = route_stat(F0, NW, nonemit)
% R1 and R1g of one fold's validation windows.
s0 = double(F0.Wv(:, 1)); c3 = double(F0.Wv(:, 4)); c1 = double(F0.Wv(:, 2));
n = numel(s0); fit = F0.F.vfit(:);
assert(size(F0.Sv.probs, 1) == numel(F0.known) && size(F0.Sv.probs, 2) == n, 'side_a5_ood_route:probs', ...
    'probs are not known classes x windows');
full = ood_cue('fill', F0.V.run, F0.V.pos) >= NW; full = full(:);
p0 = unk_stat('p', unk_stat('cal', s0(fit)), s0);
d.c1_ok = isequaln(c1(full), min(p0(full), c3(full)));
d.c3_ok = isequaln(c3(~full), p0(~full));
pn = sum(F0.Sv.probs(ismember(F0.known, nonemit), :), 1)';
N = pn >= 0.5;
ct = 1 + N .* (1 + full);                          % 1 emitter, 2 non-emitter not full, 3 non-emitter full
sc = s0; sc(ct == 3) = c3(ct == 3);               % C3 is monotone in the cue score on full windows
u.R1 = nan(n, 1);
for c = 1:3
    m = ct == c;
    if any(m), u.R1(m) = unk_stat('p', unk_stat('cal', sc(fit & m)), sc(m)); end
end
u.R1 = mondrian_nan(u.R1, s0);
u.R1g = p0; u.R1g(ct == 3) = c3(ct == 3);
d.un_N = mean(N(F0.F.un(:))); d.kn_N = mean(N(F0.F.kn(:))); d.kn_Nfull = mean(full(F0.F.kn(:) & N));
end

function u = mondrian_nan(u, s0)
u(isnan(s0)) = NaN;
end

function v = getf(S, f, d)
v = d; if isfield(S, f) && ~isempty(S.(f)), v = S.(f); end
end

function s = tf(b)
if b, s = 'yes'; else, s = 'no'; end
end
