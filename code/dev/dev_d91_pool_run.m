function dev_d91_pool_run(out_file, src)
%DEV_D91_POOL_RUN  Proof (b) of docs/d91_speed.md, one side: pool_cell.m of the code on the
%   path over the reduced cells (dev_d91_cells.m) with the detector of src (dev_d91_det.m);
%   saves R (threat, P, info, seconds per cell) to out_file. Run once on the old commit and
%   once on the new one, then dev_d91_compare.m.
dev_d91_code();
p0 = load('params.mat').params; p0.quiet_build = true;
C = decision_config();
[cells, A, eb, opt] = dev_d91_cells(p0, C);
det = dev_d91_det(src, p0);
fprintf('pool_cell: %s\n', which('pool_cell'));
R = struct('threat', {}, 'P', {}, 'info', {}, 'sec', {});
for i = 1:numel(cells)
    t0 = tic;
    [P, info] = pool_cell(cells(i).p, cells(i).threat, A, eb, cells(i).geo, det, opt);
    R(i) = struct('threat', cells(i).threat, 'P', {P}, 'info', info, 'sec', toc(t0));
    fprintf('  %-22s %d unique configurations, map %s, %.1f s\n', cells(i).threat, info.n_unique, mat2str(info.map), R(i).sec);
end
has_det = ~isempty(det);
save(out_file, 'R', 'A', 'eb', 'has_det', '-v7.3');
fprintf('saved %s\n', out_file);
close_system('UAV_GCS_Threat_Link', 0);
end
