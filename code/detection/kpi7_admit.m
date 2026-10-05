function [ok, B] = kpi7_admit(med_ms, p95_ms)
%KPI7_ADMIT  Whether a detector cost fits the decision-cycle budget of KPI 7.
%   KPI 7 (proposal): decision latency per 20 ms cycle, median < 10 ms and p95 < 20 ms,
%   the low latency class of Oli & Mahalal (IEEE Access 2025, Table 8). The detector
%   with its unknown-threat score may take at most half of each target, median
%   <= 5 ms and p95 <= 10 ms; the other half covers the spectrogram, the link features
%   and the policy (2.0 ms median, 2.5 ms p95 measured in v6) with margin.
%   med_ms, p95_ms  detector cost per frame on the device it runs on (same size)
%   ok              true where both fit; B the budget
B = struct('median_ms', 10, 'p95_ms', 20, 'share', 0.5);
B.det_median_ms = B.share * B.median_ms;
B.det_p95_ms = B.share * B.p95_ms;
ok = med_ms <= B.det_median_ms & p95_ms <= B.det_p95_ms;
end
