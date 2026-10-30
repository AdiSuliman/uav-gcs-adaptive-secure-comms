function s = policy_stamp(Q)
%POLICY_STAMP  Identity of the deployed policy of data/trained_dqn.mat (Q): a SHA-256 hash
%   (16 hex digits) of the deployed kind, the DQN's monitor (alarm, confirmation, drop
%   threshold), the rule fallback's own monitor and settings, the selected agent's weights
%   (dqn_dense.m), the det_id of the pools it learned on, the unknown-threat threshold it ran
%   with and its decision-time settings (dec, decision_settings.m; the degradation test only when C1d
%   chose one, and the smoke's forced mark deg_forced; the drop alarm's own confirmation, the rule's
%   lost-branch gate and the release on evidence only when set, the smoke's forced cells wf_forced, so
%   earlier stamps stay). Results that
%   depend on the deployed policy store it (evaluate_policies.m, measure_latency.m, edge_map.m),
%   and the readers flag a result whose stamp is not the current one (result_status.m).
f = @(n) field_or(Q, n);
rs = f('rule_sel');
mon = {};
if isstruct(rs), mon = {field_or(rs, 'alarm_mode'), double(field_or(rs, 'confirm')), double(field_or(rs, 'drop_db'))}; end
dec = settings_of(f('dec'));
if isstruct(rs) && isfield(rs, 'rule_mmse_db'), mon{end+1} = settings_of(rs); end
w = {};
ag = f('agent');
if isstruct(ag) && isfield(ag, 'dense'), w = {ag.dense}; end
md = java.security.MessageDigest.getInstance('SHA-256');
v = {char(f('deployed')), char(f('alarm_mode')), double(f('confirm')), double(f('drop_db')), ...
    mon, w, char(f('det_id')), double(f('maha_thr'))};
if ~isempty(dec), v{end+1} = dec; end
md.update(getByteStreamFromArray(v));
h = typecast(md.digest(), 'uint8');
s = lower(reshape(dec2hex(h(1:8))', 1, []));
end

function c = settings_of(S)
% The decision-time settings of S as one cell (field order fixed), empty without them.
c = {};
if ~isstruct(S), return; end
for n = {'confirm_sweep', 'unk_mode', 'unk_retain', 'rule_mmse_db', 'rule_slot', 'rule_dwell', 'esc_drop'}
    x = field_or(S, n{1}); if islogical(x), x = double(x); end
    c{end+1} = x; %#ok<AGROW>
end
for n = {'rule_nb', 'core_nb', 'deg_mode', 'ber_q', 'deg_forced', 'confirm_drop', 'wf_forced'}   % the noise-burst answers, the degradation test, the drop alarm's confirmation and the smoke's forced cells, when set
    x = field_or(S, n{1});
    if ~isempty(x), c{end+1} = {n{1}, x}; end %#ok<AGROW>
end
for n = {'s1_gate', 'release_m'}                                   % the lost-branch gate and the release on evidence, when on
    x = field_or(S, n{1});
    if ~isempty(x) && x, c{end+1} = {n{1}, 1}; end %#ok<AGROW>
end
end

function v = field_or(S, n)
% Field n of S, empty when S has none.
if isfield(S, n), v = S.(n); else, v = []; end
end
