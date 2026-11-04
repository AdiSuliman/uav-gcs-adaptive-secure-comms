function w = rr_column(ci, Us)
%RR_COLUMN  The receiver-robust side column of KPI 8 (D121 item 3, "KPI8-RR"): beside a registered
%   paired difference (rule_core3 or rule_core minus blind_core) with its 95% interval ci = [lo hi],
%   'yes' iff the interval clears 0 by more than D2c's U_s, in the units D2c gives U_s in (lower
%   bound > U_s, or upper bound < -U_s), 'no' otherwise, 'n/a' where U_s does not cover the
%   difference's units (Us empty or NaN: none given) or the interval is not finite. A side
%   reading under D121 condition 2: it never replaces the registered pair or its words.
w = 'n/a';
if isempty(Us) || ~isscalar(Us) || ~isfinite(Us), return; end
if Us < 0, error('rr_column:us', 'rr_column: U_s must be >= 0'); end
if numel(ci) ~= 2 || ~all(isfinite(ci)), return; end
if ci(1) > Us || ci(2) < -Us, w = 'yes'; else, w = 'no'; end
end
