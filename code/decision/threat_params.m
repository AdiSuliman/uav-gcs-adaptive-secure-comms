function p = threat_params(p0, threat, sev, C)
%THREAT_PARAMS  Params of one decision-layer cell: every component of the threat
%   (a single threat or 'a+b') at severity index sev of decision_config.m.
if nargin < 4, C = decision_config(); end
p = p0; p.active_threat = threat;
if strcmp(threat, 'none'), return; end
parts = strsplit(threat, '+');
for i = 1:numel(parts)
    p.(C.sev.(parts{i}).field) = C.sev.(parts{i}).levels(sev);
end
end
