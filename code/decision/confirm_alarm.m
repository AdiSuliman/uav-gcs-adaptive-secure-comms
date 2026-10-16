function c = confirm_alarm(a, CF)
%CONFIRM_ALARM  Per-cycle alarms a (E x T, oldest first, from a fresh monitor: none before
%   cycle 1) confirmed as policy_monitor.m confirms them (M.confirmed: at least m of the last
%   n cycles), by any confirmation [m n] of the rows of CF. Only a confirmed alarm lets a
%   policy change the configuration (policy_mask.m, policy_decide.m).
c = false(size(a));
for i = 1:size(CF, 1)
    c = c | movsum(double(a), [CF(i, 2) - 1, 0], 2) >= CF(i, 1);
end
end
