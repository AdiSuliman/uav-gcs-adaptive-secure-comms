function mask = policy_mask(cfg, confirmed, since, nA, na)
%POLICY_MASK  Configurations a policy may choose this cycle (nA x NE).
%   Shield (Alshiekh et al., AAAI 2018), the same for training and deployment:
%   - hold: within C.hold cycles of the last change only the current
%     configuration is allowed, as for the rule and table policies (proposal
%     mitigation 8, decision hysteresis: no ping-pong between configurations)
%   - without a confirmed alarm (policy_monitor.m): keep the configuration or
%     release it to no_action
%   - with a confirmed alarm: every configuration
%   since: cycles since the last change (policy_monitor.m memory), 1 x NE.
C = decision_config();
NE = numel(cfg);
mask = repmat(confirmed(:)', nA, 1);
mask(na, :) = true;
mask(:, since(:)' < C.hold) = false;
mask(sub2ind([nA NE], cfg(:)', 1:NE)) = true;
end
