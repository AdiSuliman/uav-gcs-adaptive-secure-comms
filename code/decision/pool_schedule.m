function [order, po] = pool_schedule(w, pl, nwp)
%POOL_SCHEDULE  Order and hand-out of the jobs of a parallel pool stage.
%   [order, po] = pool_schedule(w, pl, nwp): order the jobs longest first by their cost w
%   (pool_cost.m; equal costs keep their order), po parfor's second argument: one job per
%   hand-out on pool pl, so a free worker always takes the longest job left (default parfor
%   hands out ranges of several), or nwp (0: on this process). Every job reseeds every
%   random source per flight (link_seed.m), so no value depends on the order or the worker.
[~, order] = sort(w(:)', 'descend');
po = nwp;
if nwp > 0
    po = parforOptions(pl, 'RangePartitionMethod', 'fixed', 'SubrangeSize', 1);
end
end
