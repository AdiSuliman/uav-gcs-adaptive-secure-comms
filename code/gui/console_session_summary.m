function lines = console_session_summary(H, dn)
%CONSOLE_SESSION_SUMMARY  The two summary lines of the Session Log tab from the run history H (a cell
%   of the console's history entries); dn is the deployed policy's name. A mean over no finite value
%   reads 'N/A'.
if isempty(H), lines = {'No runs yet.'}; return; end
dn = upper(dn); n = numel(H);
corr = cellfun(@(h) h.cnn_correct, H); unk = cellfun(@(h) h.unknown, H);
recD = cellfun(@(h) h.rec_dqn, H);     recR = cellfun(@(h) h.rec_rule, H);
lat  = cellfun(@(h) h.decision_latency_ms, H);
both = ~isnan(recD) & ~isnan(recR);
better = sum(recD(both) > recR(both) + 1); worse = sum(recD(both) < recR(both) - 1);
same = sum(both) - better - worse;
lines = { ...
    sprintf('RUNS %d | detection %d/%d (%s) | unknown %d | mean latency %s', ...
        n, sum(corr), n, console_fmt(100*mean(corr), '%.1f%%'), sum(unk), console_fmt(mean(lat, 'omitnan'), '%.2f ms')), ...
    sprintf('mean recovery: %s %s | RULE %s | %s better/equal/worse than RULE: %d / %d / %d', ...
        dn, console_fmt(mean(recD, 'omitnan'), '%.1f%%'), console_fmt(mean(recR, 'omitnan'), '%.1f%%'), ...
        dn, better, same, worse)};
end
