function [rB, rF, rS] = surv_runs(P, A, nr)
%SURV_RUNS  Each flight's BER, packet loss and slack of one survivability job under surv_v2
%   (pool_job.m 'surv'): P the pools of pool_cell.m {Eb/N0, configuration}, A the
%   configurations, nr the flights (run ids 1:nr, surv_flights.m). The slack is one loss event
%   of the flight (packet_share.m), as the one-flight map takes it of its run.
%   rB, rF, rS: configurations x Eb/N0 x flights.
nS = size(P, 1); nA = size(P, 2);
rB = nan(nA, nS, nr); rF = rB; rS = rB;
for s = 1:nS
    for a = 1:nA
        Q = P{s, a, 1};
        for r = 1:nr
            m = Q.run == r;
            rB(a, s, r) = mean(Q.ber(m));
            rF(a, s, r) = mean(double(Q.fer(m)));
            rS(a, s, r) = packet_share(A{a}, Q.fer(m));
        end
    end
end
end
