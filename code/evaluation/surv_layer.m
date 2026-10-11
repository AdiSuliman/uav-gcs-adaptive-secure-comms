function V = surv_layer(F, sk, TGT, B)
%SURV_LAYER  SURV of edge_map.m over the flights F: the flights some configuration recovers
%   (sk: the recoverability field of the set) among those with the threat on the air (F.on,
%   link_env.m K.on: airframe shadowing only where the attitude hides an antenna), an
%   edge_verdict.m against TGT.surv with B bootstrap draws.
m = true(size(F.geo)); if isfield(F, 'on'), m = F.on; end
V = edge_verdict(double(F.(sk)(m)), ones(sum(m), 1), F.geo(m), TGT.surv, 'ge', true, B);
end
