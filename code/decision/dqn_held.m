function r = dqn_held(R)
%DQN_HELD  Share of held recoveries among the recoverable threat episodes (rollout_policy.m
%   held: restored to the end but one follower re-acquisition), the edge map's REC
%   (edge_map.m); dqn_recovered.m is KPI 4's transient reading.
m = R.recoverable & R.threat;
r = mean(R.held(m));
end
