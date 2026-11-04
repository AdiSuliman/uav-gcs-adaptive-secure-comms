function M = surv3_metrics(P, A, n)
%SURV3_METRICS  Per-geometry BER, packet loss and slack of one survivability-options job
%   (pool_job.m 'surv3' under surv_v2): P the pools of pool_cell.m {Eb/N0, configuration},
%   A the configurations, n the geometries (run ids surv3_run_id(1:n)). The slack is one loss
%   event of the geometry's run (packet_share.m). Every criterion can be read again from M.
%   M.ber, M.fer, M.slack: Eb/N0 x geometry x configuration.
nS = size(P, 1); nA = size(P, 2);
M = struct('ber', nan(nS, n, nA), 'fer', nan(nS, n, nA), 'slack', nan(nS, n, nA));
for s = 1:nS
    for a = 1:nA
        Q = P{s, a, 1};
        for r = 1:n
            m = Q.run == surv3_run_id(r);
            M.ber(s, r, a) = mean(Q.ber(m));
            M.fer(s, r, a) = mean(double(Q.fer(m)));
            M.slack(s, r, a) = packet_share(A{a}, Q.fer(m));
        end
    end
end
end
