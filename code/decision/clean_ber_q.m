function BQ = clean_ber_q(CV, PP, fit, alpha)
%CLEAN_BER_Q  The clean quantile tables of the degradation test (deg_quantile.m), one per alpha
%   (default C.deg_alpha), from the fit half of the clean validation geometries (clean_halves.m):
%   every Eb/N0 point of CV at no_action, every full window of C.win frames of each flight as
%   policy_monitor.m reads it there (the mean BER estimate and the median measured Eb/N0
%   estimate of the same frames; no configuration gain at no_action). A geometry counts as one
%   flight over every Eb/N0 point, though each point flies it with its own seed
%   (clean_pool_seed.m): the conservative count. Only the clean validation set is read
%   (docs/deg_fix_protocol.md).
%   CV   the clean validation pools (data/clean_val_pools.mat CT, set 'val')
%   PP   the policy pools' settings (sps, bps)
%   fit  logical over CV.runs
%   BQ   struct array over alpha: deg_quantile.m's table, with runs (the fit geometries), win
%        and source (CV.created)
C = decision_config();
if nargin < 4 || isempty(alpha), alpha = C.deg_alpha; end
if ~isfield(CV, 'set') || ~strcmp(CV.set, 'val')
    error('clean_ber_q:source', 'only the clean validation pools are read, never test or check pools');
end
if ~islogical(fit) || numel(fit) ~= numel(CV.runs), error('clean_ber_q:fit', 'fit must be logical over CV.runs'); end
na = find(strcmp(CV.actions, 'no_action'));
fr = double(CV.runs(fit)); fr = fr(:)';
jb = feature_index('log_ber'); js = feature_index('sinr'); ji = feature_index('iot');
n = numel(CV.ebno); B = cell(n, 1); E = B; G = B;
for s = 1:n
    P = CV.pools{1, s, na};
    k = ismember(double(P.run(:)), fr);
    F = double(P.feat(k, :));
    eb = F(:, js) + F(:, ji) + 10*log10(PP.sps) - 10*log10(PP.bps);    % policy_monitor.m's M.ebno_est
    [B{s}, E{s}, G{s}] = deg_quantile('windows', 10.^F(:, jb), eb, P.run(k), C.win);
end
b = vertcat(B{:}); e = vertcat(E{:}); g = vertcat(G{:});
src = ''; if isfield(CV, 'created'), src = CV.created; end
for i = 1:numel(alpha)
    Q = deg_quantile('build', b, e, g, alpha(i));
    Q.runs = fr; Q.win = C.win; Q.source = src;
    if i == 1, BQ = Q; else, BQ(i) = Q; end %#ok<AGROW>
end
end
