function rid = surv3_run_id(r)
%SURV3_RUN_ID  Run id of geometry r of experiment_survivability_options.m: 100 x its
%   seed block (13, pool_seed.m) + r, as the pools number their runs. The geometries
%   are built and their frames read back with this one id.
rid = 100 * 13 + r;
end
