function [PPw, Kw] = clean_world(PP, CT)
%CLEAN_WORLD  The pools with the validation split replaced by the independent clean
%   geometries of CT (clean_split.m) and their tables (link_env.m), for the clean-link
%   readings on validation (train_dqn.m, choose_drop_threshold.m). Only the split's
%   per-geometry fields and their tables are cached: the monitor settings (alarm,
%   confirmation, drop threshold, the decision-time settings) always come from the PP of this
%   call.
persistent key cache
k = sprintf('%s|%s', CT.created, PP.created);
if ~isequal(key, k)
    W = clean_split(PP, CT, 2);
    key = k; cache = struct('W', W, 'Kw', link_env('tables', W));
end
PPw = PP;
for f = {'pools', 'runs', 'event_frame', 'speed', 'cell_geo', 'cov', 'alt', 'ksig', 'ref_geo'}   % the split's per-geometry fields
    if isfield(cache.W, f{1}), PPw.(f{1}) = cache.W.(f{1}); end
end
Kw = cache.Kw;
end
