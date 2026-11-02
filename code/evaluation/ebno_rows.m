function [rows, lines] = ebno_rows(rec, s, geom, thr, ebno, clean_fer, ratio_ok, label)
%EBNO_ROWS  The recovered share per Eb/N0 point (proposal KPI 4's reading, the recoverable episodes of
%   the threats), each with its 95% interval, the number of clusters behind it, its link tag and the
%   deficit split by threat. Descriptive: no verdict; EDGE's commitment (edge_map.m) is the only one
%   that is "committed".
%   rec        recovered, per recoverable threat episode (the caller selects them)
%   s          Eb/N0 index of every episode; geom its cluster (a flight geometry at an Eb/N0, the
%              bootstrap resamples whole clusters, boot_cluster.m); thr its threat, severities pooled
%   ebno       the Eb/N0 grid [dB]; clean_fer the clean link's packet loss at each point (PP.clean_fer,
%              NaN: unknown); ratio_ok the restoration test's factor (decision_config.m)
%   label      what the rows are, for the first line
%   Tags: L when ratio_ok x clean_fer >= 1 (the packet-loss half of the restoration test cannot fail),
%   J when the clean packet loss is under 0.1 (802.11a's sensitivity criterion), else M.
%   rows(k): ebno, n, rec, lo, hi (percent), clusters, tag, lb90 (the lower bound is at least 90),
%   deficit (percent of the point's episodes not recovered, per threat, summing to 100 - rec),
%   threats.
rec = double(rec(:)'); s = s(:)'; geom = geom(:)'; thr = thr(:)';
if numel(clean_fer) ~= numel(ebno), clean_fer = nan(1, numel(ebno)); end   % no clean packet loss per point: no tag
names = unique(thr, 'stable');
rows = struct('ebno', {}, 'n', {}, 'rec', {}, 'lo', {}, 'hi', {}, 'clusters', {}, 'tag', {}, 'lb90', {}, 'deficit', {}, 'threats', {});
lines = {sprintf(['%s, per Eb/N0 point: recovered among the recoverable episodes, 95%% bootstrap over flight geometries, ' ...
    'the clusters behind it, the link tag (L link-limited: the clean link loses at least half its packets; J working point: ' ...
    'under 10%%; M between) and the deficit by threat in points. Descriptive: lower bound >= 90 only says so; ' ...
    'EDGE''s commitment is the only one called committed'], label)};
for k = 1:numel(ebno)
    i = s == k;
    if ~any(i), continue; end
    [m, lo, hi] = boot_cluster(rec(i), ones(1, sum(i)), geom(i), 2000, 900 + k);
    tag = '-';
    if k <= numel(clean_fer) && ~isnan(clean_fer(k))
        if ratio_ok * clean_fer(k) >= 1, tag = 'L'; elseif clean_fer(k) < 0.1, tag = 'J'; else, tag = 'M'; end
    end
    df = arrayfun(@(t) 100 * sum(i & rec == 0 & strcmp(thr, t{1})) / sum(i), names);
    rows(end+1) = struct('ebno', ebno(k), 'n', sum(i), 'rec', 100 * m, 'lo', 100 * lo, 'hi', 100 * hi, ...
        'clusters', numel(unique(geom(i))), 'tag', tag, 'lb90', 100 * lo >= 90, 'deficit', df, 'threats', {names}); %#ok<AGROW>
    [~, o] = sort(df, 'descend'); o = o(df(o) > 0);
    lines{end+1} = sprintf('  %g dB [%s]: %.1f%% [%.1f, %.1f], %d episodes, %d clusters, lower bound >= 90: %s; deficit %.1f: %s', ...
        ebno(k), tag, 100 * m, 100 * lo, 100 * hi, sum(i), rows(end).clusters, ternary(rows(end).lb90, 'yes', 'no'), ...
        100 - 100 * m, ternary(isempty(o), '-', strjoin(arrayfun(@(j) sprintf('%s %.1f', names{j}, df(j)), o, ...
        'UniformOutput', false), ', '))); %#ok<AGROW>
end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
