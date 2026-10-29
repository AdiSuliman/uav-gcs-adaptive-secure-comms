function PP = decision_settings(PP, S)
%DECISION_SETTINGS  The decision-time settings chosen on validation (train_dqn.m), applied to
%   the pools' settings PP before a policy runs, so every reader runs what was chosen:
%   monitor     alarm_mode, confirm, drop_db (policy_monitor.m), confirm_sweep (the sweeping
%               jammer's own confirmation, [] for none), maha_thr and unk_retain (the
%               unknown-threat threshold and its validation retention), unk_mode ('all',
%               'nonhostile': the classes the unknown-threat flag overrides)
%   rule, table rule_mmse_db (the nulling threshold), rule_slot (the quiet-slot branch),
%               rule_dwell ('run', 'group': policy_decide.m), rule_nb (the rule's answer to a
%               noise burst, {not separable, separable}), core_nb (the core rule's)
%   escalation  esc_drop (an escalation on a confirmed drop alarm read as none)
%   degradation deg_mode, ber_q (policy_monitor.m; chosen at C1d, docs/deg_fix_protocol.md)
%   S: any struct with some of these fields (a field absent keeps PP's; an empty drop_db,
%   maha_thr, alarm_mode, confirm or deg_mode keeps PP's), or data/trained_dqn.mat loaded: its
%   deployed DQN's settings (dec), else the monitor it saved (confirm, alarm_mode, drop_db,
%   maha_thr) for an agent trained before dec.
if isfield(S, 'dec') && isstruct(S.dec), S = S.dec; end
keep = {'alarm_mode', 'confirm', 'drop_db', 'maha_thr', 'deg_mode'};
for f = {'alarm_mode', 'confirm', 'drop_db', 'confirm_sweep', 'maha_thr', 'unk_retain', 'unk_mode', ...
        'rule_mmse_db', 'rule_slot', 'rule_dwell', 'esc_drop', 'rule_nb', 'core_nb', 'deg_mode', 'ber_q'}
    if ~isfield(S, f{1}) || (isempty(S.(f{1})) && ismember(f{1}, keep)), continue; end
    PP.(f{1}) = S.(f{1});
end
end
