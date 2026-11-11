function [S, lines] = clean_k6_split(PP, CT, ebno_thr, T, flag, names)
%CLEAN_K6_SPLIT  KPI 6 split by the receiver's estimated link K, speed, bank and hiding geometry on the clean
%   validation flights of C2 (kpi6_split.m; descriptive, beside the registered reading, never in its place).
%   flag   policies x episodes logical, the false-change episodes of eval_clean_wide (train_dqn.m: sw_w > 0), the
%          episodes of clean_wide_specs.m(PP, CT, ebno_thr, T) in its order; names  one label per row
%   The K of a flight is the median over its cycles of the monitor's los_k at no_action (monitor_trace.m,
%   PP.record_los_k, a reading only); bank, speed and the hiding geometry (clean_hides.m, the nominal shadowing
%   level, no loss applied) are the flight's draws (CT.cov).
[specs, n] = clean_wide_specs(PP, CT, ebno_thr, T);
if size(flag, 2) ~= n
    error('clean_k6_split:size', 'clean_k6_split: %d episodes per policy, the clean validation flights are %d', size(flag, 2), n);
end
[PPw, Kw] = clean_world(PP, CT);
PPw.record_los_k = true;
Tc = monitor_trace(PPw, Kw, specs, 2, 41000);
lk = nan(1, n);
if isfield(Tc, 'lk'), lk = median(Tc.lk(1:n, :), 2, 'omitnan')'; end
s = Tc.s(1:n); r = Tc.r(1:n);
C = decision_config();
P0 = load('params.mat'); p0 = P0.params; p0.quiet_build = true;
H = clean_hides(CT.cov, CT.ebno, p0, C.sev.airframe_shadowing.levels(C.nominal), C.event_frame, C.event_count);
ix = sub2ind(size(CT.cov.bank), s, r);
cov = struct('lk', lk, 'speed', CT.cov.speed(ix), 'speed_bins', linspace(PP.speed_range(1), PP.speed_range(2), 5), ...
    'bank', CT.cov.bank(ix), 'hide', H(ix));
[S, lines] = kpi6_split(flag, 1000 * s + r, cov, names);
lines{end+1} = sprintf(['  (C2, clean validation flights, %d episodes, the changes of eval_clean_wide; the hiding condition is ' ...
    'read at the nominal shadowing level %g dB; link K needs the fusion in PP: %s)'], n, ...
    C.sev.airframe_shadowing.levels(C.nominal), ternary(any(isfinite(lk)), 'present', 'absent, K bins empty'));
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
