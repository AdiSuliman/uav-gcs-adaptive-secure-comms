function w = pool_cost(p, threat, actions, geo, opt)
%POOL_COST  Relative run time of one pool_cell.m job, for the order of a parallel stage.
%   w = pool_cost(p, threat, actions, geo, opt): the runs the job flies (configurations
%   with a run of their own, pool_configs.m) x its frames x the cost of a frame: a clean-link
%   frame and one more share per emitter of the threat (1.75 s per 20-frame clean run, 1.15 s
%   more per emitter, timed on profile 1's pool build). geo as pool_cell.m (frames per flight:
%   geo.frames, else opt.F_SUB), or the job's frames per configuration as a number. Only the
%   order of the jobs depends on it, never a value.
[~, ~, twin] = pool_configs(p, threat, actions);
nr = sum(twin == 1:numel(actions));
if iscell(geo)
    nfr = 0;
    for s = 1:numel(geo)
        for sp = 1:numel(geo{s})
            g = geo{s}(sp);
            f = opt.F_SUB * ones(1, numel(g.seed));
            if isfield(g, 'frames'), f(isfinite(g.frames)) = g.frames(isfinite(g.frames)); end
            nfr = nfr + sum(f);
        end
    end
else
    nfr = geo;
end
parts = strsplit(threat, '+');
ne = sum(~ismember(parts, {'none', 'path_loss', 'antenna_fault', 'airframe_shadowing'}));   % emitters
w = nr * nfr * (1.75 + 1.15 * ne) / 20;
end
