function s = policy_stamp(Q)
%POLICY_STAMP  Identity of the deployed policy of data/trained_dqn.mat (Q): a SHA-256 hash
%   (16 hex digits) of the deployed kind, the DQN's monitor (alarm, confirmation, drop
%   threshold), the rule fallback's own monitor, the selected agent's weights (dqn_dense.m)
%   and the det_id of the pools it learned on. Results that depend on the deployed policy
%   store it (evaluate_policies.m, measure_latency.m, edge_map.m), and the readers flag a
%   result whose stamp is not the current one (result_status.m).
f = @(n) field_or(Q, n);
rs = f('rule_sel');
mon = {};
if isstruct(rs), mon = {field_or(rs, 'alarm_mode'), double(field_or(rs, 'confirm')), double(field_or(rs, 'drop_db'))}; end
w = {};
ag = f('agent');
if isstruct(ag) && isfield(ag, 'dense'), w = {ag.dense}; end
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(getByteStreamFromArray({char(f('deployed')), char(f('alarm_mode')), double(f('confirm')), double(f('drop_db')), ...
    mon, w, char(f('det_id'))}));
h = typecast(md.digest(), 'uint8');
s = lower(reshape(dec2hex(h(1:8))', 1, []));
end

function v = field_or(S, n)
% Field n of S, empty when S has none.
if isfield(S, n), v = S.(n); else, v = []; end
end
