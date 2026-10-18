function order = pool_schedule(w)
%POOL_SCHEDULE  Order of the jobs of a parallel pool stage: longest first by their cost w
%   (pool_cost.m); equal costs keep their order. pool_lpt.m hands them out in this order, one
%   per free worker. Every job reseeds every random source per flight (link_seed.m), so no
%   value depends on the order or the worker.
[~, order] = sort(w(:)', 'descend');
end
