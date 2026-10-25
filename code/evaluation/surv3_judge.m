function [R, Bc] = surv3_judge(M, ref, ratio, floor_ber, A)
%SURV3_JUDGE  Recoverable geometries of one survivability-options job against one clean link:
%   some configuration with BER <= ratio x max(ref.ber, floor_ber) and packet loss <= ratio x
%   ref.fer + its slack (the KPI 4 rule of pool_job.m 'surv3').
%   M    per-geometry metrics (surv3_metrics.m); ref a clean link (ber, fer per Eb/N0)
%   A    the configurations, in their order
%   R    Eb/N0 x geometry; Bc the first recovering configuration in A's order ([] none)
[nS, n, ~] = size(M.ber);
R = false(nS, n); Bc = cell(nS, n);
for s = 1:nS
    bc = max(ref.ber(s), floor_ber); fc = ref.fer(s);
    for r = 1:n
        ok = reshape(M.ber(s, r, :) <= ratio * bc & M.fer(s, r, :) <= ratio * fc + M.slack(s, r, :), 1, []);
        R(s, r) = any(ok);
        if R(s, r), Bc{s, r} = A{find(ok, 1)}; end
    end
end
end
