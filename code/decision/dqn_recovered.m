function r = dqn_recovered(R)
%DQN_RECOVERED  Share of recovered episodes among the recoverable threat episodes (KPI 4).
m = R.recoverable & R.threat;
r = mean(R.recovered(m));
end
