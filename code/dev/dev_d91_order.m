function dev_d91_order(out_dir, src)
%DEV_D91_ORDER  Proof (c) of docs/d91_speed.md: the reduced cells (dev_d91_cells.m) run as the
%   parallel loop of build_policy_pools.m runs them, twice in one process: in index order after
%   rng(1), then in the stage's order (pool_cost.m, pool_schedule.m; reversed if that is the
%   index order) after rng(99). The global stream gives every model build its own seed
%   (build_threat_model.m) and a worker runs whatever cells it is handed, so equal results
%   show that no value depends on the order, the worker or the stream. Saves order_1.mat and
%   order_2.mat in out_dir (dev_d91_compare.m layout) and compares them.
p0 = load('params.mat').params; p0.quiet_build = true;
C = decision_config();
[cells, A, eb, opt] = dev_d91_cells(p0, C);
det = dev_d91_det(src, p0);
has_det = ~isempty(det);
w = arrayfun(@(c) pool_cost(c.p, c.threat, A, c.geo, opt), cells);
o2 = pool_schedule(w, [], 0);
if isequal(o2, 1:numel(cells)), o2 = fliplr(o2); end
runs = {1:numel(cells), o2}; seeds = [1 99];
for k = 1:2
    rng(seeds(k));
    R = struct('threat', {cells.threat}, 'P', [], 'info', [], 'sec', []);
    for c = runs{k}
        t0 = tic;
        [P, info] = pool_cell(cells(c).p, cells(c).threat, A, eb, cells(c).geo, det, opt);
        R(c).P = P; R(c).info = info; R(c).sec = toc(t0);
    end
    fprintf('run %d: rng(%d), cell order %s (costs %s)\n', k, seeds(k), mat2str(runs{k}), mat2str(round(w)));
    save(fullfile(out_dir, sprintf('order_%d.mat', k)), 'R', 'A', 'eb', 'has_det', '-v7.3');
end
close_system('UAV_GCS_Threat_Link', 0);
dev_d91_compare(fullfile(out_dir, 'order_1.mat'), fullfile(out_dir, 'order_2.mat'), 'C_order');
end
