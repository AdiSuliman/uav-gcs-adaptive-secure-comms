function mask = policy_mask(cfg, confirmed, nA, na)
%POLICY_MASK  Configurations a policy may choose this cycle (nA x NE) (D45).
%   Shield (Alshiekh et al., AAAI 2018): without a confirmed alarm
%   (policy_monitor.m) the policy can only keep its configuration or release it
%   to no_action; with one, every configuration is allowed. False alarms are
%   then set by the detector and the confirmation rule, as for the rule policy.
NE = numel(cfg);
mask = repmat(confirmed(:)', nA, 1);
mask(sub2ind([nA NE], cfg(:)', 1:NE)) = true;
mask(na, :) = true;
end
