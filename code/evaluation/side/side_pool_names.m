function [nm, info] = side_pool_names(KP, R1, scen)
%SIDE_POOL_NAMES  The threat name of every episode of a saved policy_evaluation.mat without the pools file.
%   [nm, info] = side_pool_names(KP, R1)         names rebuilt from KP.threats and KP.sev_names
%   [nm, info] = side_pool_names(KP, R1, scen)   scen: PP.scen as a cellstr, used as given
%   KP  the saved KP; R1  ALL{1} (fields scn, threat, recoverable).
%   The pool cells run none, each single threat over the severities, each combined threat over its
%   severities (build_policy_pools.m). The rebuilt names are accepted only when every threat's
%   recoverable share over its episodes equals KP.recoverable_share (evaluate_policies.m) to 1e-9.
%   An unmatched rebuild, or two that name the episodes differently, is an error.
for f = {'threats', 'recoverable_share', 'sev_names'}
    if ~isfield(KP, f{1}), error('side_pool_names:field', 'side_pool_names: KP.%s is missing', f{1}); end
end
thr = cellstr(string(KP.threats(:)'));
if nargin >= 3 && ~isempty(scen)
    cand = {cellstr(string(scen(:)'))}; ncs = NaN;
else
    isc = contains(thr, '+');
    nsev = numel(KP.sev_names);
    cand = {}; ncs = [];
    for n = 1:6
        c = {'none'};
        for t = thr(~isc), c = [c, repmat(t, 1, nsev)]; end %#ok<AGROW>
        for t = thr(isc), c = [c, repmat(t, 1, n)]; end %#ok<AGROW>
        if max(R1.scn) <= numel(c) && shares_match(c, thr, KP, R1)
            cand{end+1} = c; ncs(end+1) = n; %#ok<AGROW>
        end
    end
end
if isempty(cand)
    error('side_pool_names:nomatch', ['side_pool_names: no pool-cell layout reproduces KP.recoverable_share; the threat names of the ' ...
        'episodes need PP.scen (data/policy_pools.mat, too large to load here)']);
end
for i = 2:numel(cand)
    if ~isequal(cand{i}(R1.scn), cand{1}(R1.scn))
        error('side_pool_names:ambiguous', 'side_pool_names: %d cell layouts reproduce KP.recoverable_share with different names', numel(cand));
    end
end
c = cand{1};
if ~shares_match(c, thr, KP, R1), error('side_pool_names:share', 'side_pool_names: the given PP.scen does not reproduce KP.recoverable_share'); end
nm = c(R1.scn);
info = struct('ncells', numel(c), 'combined_severities', ncs);
end

function ok = shares_match(c, thr, KP, R1)
nm = reshape(c(R1.scn), 1, []);
ok = true;
for i = 1:numel(thr)
    m = strcmp(nm, thr{i}) & logical(R1.threat(:)');
    v = NaN; if any(m), v = mean(double(R1.recoverable(m))); end
    e = KP.recoverable_share(i);
    if ~(isnan(v) && isnan(e) || abs(v - e) <= 1e-9), ok = false; return; end
end
end
