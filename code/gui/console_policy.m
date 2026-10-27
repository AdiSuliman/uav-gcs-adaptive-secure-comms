function varargout = console_policy(cmd, varargin)
%CONSOLE_POLICY  The deployed decision policy of the operator console (demo_gui.m, episode_cycle.m),
%   apart from the figure so that a headless run exercises the same code. The console runs what
%   train_dqn.m deployed and recorded in data/trained_dqn.mat, as evaluate_policies.m does:
%   the selected DQN with or without the escalation, or the rule fallback (rule + escalation
%   with its own monitor and settings, rule_sel).
%   D = console_policy('load', file)
%       reads deployed, seed_summary.selected_kind, rule_sel and dec from file (default
%       data/trained_dqn.mat) and returns D (see 'deployed').
%   D = console_policy('deployed', Q)
%       Q: a struct with the file's variables. D.kind 'dqn_esc' | 'dqn' | 'rule_sel';
%       D.esc the deployed escalation (rule_sel: on); D.is_rule; D.name the short name of
%       the policy ('DQN', 'deployed rule'); D.text its description, D.short a short one for
%       the header ('DQN + escalation', 'DQN, no escalation', 'rule fallback'); D.monitor the rule
%       fallback's monitor and settings ([] for a DQN); D.recorded false when the file
%       records no deployed policy (an older training): the selected kind, else the DQN with
%       escalation, is assumed. An unknown deployed kind, a DQN kind other than the selected
%       one, or a rule fallback without its settings is an error.
%   k = console_policy('kind', D, esc)
%       the policy_decide.m kind that runs D with the escalation on or off.
%   PP = console_policy('settings', D, PP, slider)
%       PP with the deployed policy's own decision-time settings (a rule fallback: its
%       monitor, evaluate_policies.m opt.monitor; a DQN: PP as given, which carries the
%       DQN's own, decision_settings.m). slider true: the operator's unknown-threat
%       threshold stays (maha_thr, unk_retain).
%   ctx = console_policy('ctx', D, esc, ctx)
%       the episode context (episode_cycle.m) of the deployed policy: its policy_decide.m kind
%       and its settings in ctx.PP.
switch cmd
    case 'load',     varargout{1} = load_deployed(varargin{:});
    case 'deployed', varargout{1} = deployed_of(varargin{:});
    case 'kind',     varargout{1} = kind_of(varargin{:});
    case 'settings', varargout{1} = settings_of(varargin{:});
    case 'ctx',      varargout{1} = episode_ctx(varargin{:});
    otherwise, error('console_policy:cmd', 'console_policy: unknown command %s', cmd);
end
end

function D = load_deployed(file)
if nargin < 1 || isempty(file), file = 'data/trained_dqn.mat'; end
want = {'deployed', 'seed_summary', 'rule_sel'};
S = struct();
v = who('-file', file);
v = want(ismember(want, v));
if ~isempty(v), S = load(file, v{:}); end
D = deployed_of(S);
end

function D = deployed_of(Q)
sel = '';
if isfield(Q, 'seed_summary') && isstruct(Q.seed_summary) && isfield(Q.seed_summary, 'selected_kind')
    sel = Q.seed_summary.selected_kind;
end
if ~isempty(sel) && ~ismember(sel, {'dqn', 'dqn_esc'})
    error('console_policy:kind', 'selected_kind %s is neither dqn nor dqn_esc', char(string(sel)));
end
recorded = isfield(Q, 'deployed') && ~isempty(Q.deployed);
if recorded
    kind = Q.deployed;
elseif ~isempty(sel)
    kind = sel;
else
    kind = 'dqn_esc';
end
if ~ischar(kind) || ~ismember(kind, {'dqn_esc', 'dqn', 'rule_sel'})
    error('console_policy:deployed', 'deployed policy %s is not dqn_esc, dqn or rule_sel', char(string(kind)));
end
if ismember(kind, {'dqn', 'dqn_esc'}) && ~isempty(sel) && ~strcmp(kind, sel)
    error('console_policy:kind', 'deployed %s but the selected DQN is %s (trained_dqn.mat)', kind, sel);
end
D = struct('kind', kind, 'recorded', recorded, 'selected_kind', sel, 'esc', ~strcmp(kind, 'dqn'), ...
    'is_rule', strcmp(kind, 'rule_sel'), 'name', 'DQN', 'text', '', 'short', '', 'monitor', []);
switch kind
    case 'dqn_esc', D.text = 'DQN with escalation'; D.short = 'DQN + escalation';
    case 'dqn',     D.text = 'DQN without escalation'; D.short = 'DQN, no escalation';
    case 'rule_sel'
        m = [];
        if isfield(Q, 'rule_sel'), m = Q.rule_sel; end
        if ~isstruct(m) || ~all(isfield(m, {'alarm_mode', 'confirm'}))
            error('console_policy:rule_sel', 'the rule fallback is deployed but trained_dqn.mat holds no rule_sel monitor');
        end
        D.monitor = m; D.name = 'deployed rule';
        D.text = 'rule + escalation with its own monitor (the DQN did not pass validation)'; D.short = 'rule fallback';
end
end

function k = kind_of(D, esc)
if D.is_rule
    k = 'rule';
else
    k = 'dqn';
end
if esc, k = [k '_esc']; end
end

function ctx = episode_ctx(D, esc, ctx)
ctx.policy = kind_of(D, esc);
ctx.PP = settings_of(D, ctx.PP, false);
end

function PP = settings_of(D, PP, slider)
if ~D.is_rule, return; end
m = D.monitor;
if slider
    for f = {'maha_thr', 'unk_retain'}
        if isfield(m, f{1}), m = rmfield(m, f{1}); end
    end
end
PP = decision_settings(PP, m);
end
