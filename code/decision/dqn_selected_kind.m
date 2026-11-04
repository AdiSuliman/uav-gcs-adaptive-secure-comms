function k = dqn_selected_kind(Q)
%DQN_SELECTED_KIND  The selected DQN's kind, 'dqn' or 'dqn_esc' (train_dqn.m).
%   k = dqn_selected_kind(Q): Q.seed_summary.selected_kind; a file without it falls back to
%   Q.deployed ('dqn' keeps the plain kind, anything else is 'dqn_esc'). The deployed policy
%   can be the rule fallback while the selected DQN is plain.
k = 'dqn_esc';
if isfield(Q, 'seed_summary') && isstruct(Q.seed_summary) && isfield(Q.seed_summary, 'selected_kind')
    if strcmp(Q.seed_summary.selected_kind, 'dqn'), k = 'dqn'; end
elseif isfield(Q, 'deployed') && strcmp(Q.deployed, 'dqn')
    k = 'dqn';
end
end
