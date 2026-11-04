function [S, lines] = speed_nonemitter(A, Edge, Cl, bins, B)
%SPEED_NONEMITTER  Descriptive speed lines on the non-emitter threats (D121 item 8): the deployed
%   policy's recovered share per speed band and the spread over the bands, the 161 km/h line on
%   dedicated edge-speed flights, and the clean link's packet loss per speed band (the LINK
%   reading of edge_map.m is the clean no_action packet loss), each with a 95% bootstrap over
%   flight geometries (boot_cluster.m, spread_boot.m). Read beside the registered speed lines;
%   never quoted in their place (D117). Non-emitter threats: path_loss, antenna_fault,
%   airframe_shadowing (the same threat names the AoA table of evaluate_policies.m excludes).
%   A      single set, per episode: recovered, mask (recoverable and the threat on the air),
%          speed [km/h], geom (cluster), thr (cellstr, the threat name)
%   Edge   the edge-speed set (or []): the same fields, band [lo hi] km/h of the top edge
%   Cl     the clean link under no response (or []): loss (packet loss after onset), speed, geom
%   bins   speed band edges (evaluate_policies.m: linspace of PP.speed_range); B bootstrap draws
%   S      structs of the readings; lines the printed text, ending with the model note.
if nargin < 5 || isempty(B), B = 2000; end
NE = {'path_loss', 'antenna_fault', 'airframe_shadowing'};
nb = numel(bins) - 1;
S = struct('names', {NE}, 'bins', bins, 'per_band', nan(1, nb), 'n_band', zeros(1, nb), 'spread', [NaN NaN NaN], ...
    'edge', struct('n', 0, 'pct', NaN, 'ci', [NaN NaN]), 'link', struct('n', zeros(1, nb), 'loss_pct', nan(1, nb), 'ci', nan(nb, 2)));
lines = {''};
m = A.mask(:)' & ismember(A.thr(:)', NE);
vb = zeros(1, numel(A.speed));
for b = 1:nb
    mb = m & A.speed(:)' >= bins(b) & A.speed(:)' < bins(b+1) + (b == nb);
    vb(mb) = b; S.n_band(b) = sum(mb);
    if any(mb), S.per_band(b) = 100 * mean(A.recovered(mb)); end
end
S.spread = spread_boot(double(A.recovered(:)'), vb, A.geom(:)', nb, B, 8101);
lines{end+1} = sprintf(['Non-emitter threats only (%s), single set, deployed policy, recovered among recoverable per speed band ' ...
    '(descriptive, beside the registered speed lines; D121 item 8): %s'], strjoin(NE, ', '), strjoin(arrayfun(@(b) ...
    sprintf('%.0f-%.0f km/h %s%% (%d)', bins(b), bins(b+1), num_txt(S.per_band(b)), S.n_band(b)), 1:nb, 'UniformOutput', false), ', '));
lines{end+1} = sprintf('  spread over the speed bands on them: %s points [%s, %s] (95%% bootstrap over flight geometries)', ...
    num_txt(100 * S.spread(1)), num_txt(100 * S.spread(2)), num_txt(100 * S.spread(3)));
if ~isempty(Edge)
    me = Edge.mask(:)' & ismember(Edge.thr(:)', NE) & Edge.speed(:)' >= Edge.band(1) & ...
        Edge.speed(:)' <= Edge.band(2);
    S.edge.n = sum(me);
    if any(me)
        [p, lo, hi] = boot_cluster(double(Edge.recovered(me)), ones(1, sum(me)), Edge.geom(me), B, 8103);
        S.edge.pct = 100 * p; S.edge.ci = 100 * [lo hi];
    end
    lines{end+1} = sprintf('  %.0f-%.0f km/h on dedicated flights, the same threats: %s%% [%s, %s] (%d recoverable episodes)', ...
        Edge.band, num_txt(S.edge.pct), num_txt(S.edge.ci(1)), num_txt(S.edge.ci(2)), S.edge.n);
end
if ~isempty(Cl)
    for b = 1:nb
        mb = isfinite(Cl.loss(:)') & Cl.speed(:)' >= bins(b) & Cl.speed(:)' < bins(b+1) + (b == nb);
        S.link.n(b) = sum(mb);
        if any(mb)
            [p, lo, hi] = boot_cluster(Cl.loss(mb), ones(1, sum(mb)), Cl.geom(mb), B, 8110 + b);
            S.link.loss_pct(b) = 100 * p; S.link.ci(b, :) = 100 * [lo hi];
        end
    end
    lines{end+1} = sprintf('  clean link per speed band, no-response packet loss after onset (the LINK reading, edge_map.m): %s', ...
        strjoin(arrayfun(@(b) sprintf('%.0f-%.0f km/h %s%% [%s, %s] (%d)', bins(b), bins(b+1), num_txt(S.link.loss_pct(b)), ...
        num_txt(S.link.ci(b, 1)), num_txt(S.link.ci(b, 2)), S.link.n(b)), 1:nb, 'UniformOutput', false), ', '));
end
lines{end+1} = ['  Model simplification: the attitude loss is applied to our signal only, never to the jammer received by the same ' ...
    'tilted dipoles, so under emitter threats in a bank the simulated JSR is too high by an unmeasured amount; the physics fix ' ...
    '(uav_attitude_db on the interferer path with the emitter''s bearing and elevation) changes the detector''s training frames ' ...
    'and is a candidate after profile 3, under its own registration.'];
S.lines = lines;
end

function s = num_txt(x)
if isnan(x), s = '-'; else, s = sprintf('%.1f', x); end
end
