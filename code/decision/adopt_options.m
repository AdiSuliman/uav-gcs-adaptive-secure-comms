function out = adopt_options(varargin)
%ADOPT_OPTIONS  Adopted settings read into evaluate_policies.m (CFG.adopt), off by default.
%   A = adopt_options(cfg)     cfg: CFG of run_stage.m (a struct, or [] / absent). CFG.adopt is a
%       struct of named adoptions, each a setting string; absent, empty or '' is off. Known
%       names, in the order they apply: rule_fix (the rule's layered answers, rule_fix.m),
%       dqn_hop (the deployed DQN's hop layer, dqn_fix.m: 'q' or 'rule').
%       A: on, names (the adoptions set, in order), rule_fix and dqn_hop (canonical settings,
%       '' off), dqn_row (the deployed row, '' until set by 'deployed')
%   A = adopt_options('deployed', A, name)   name: the deployed policy's row (evaluate_policies.m
%       POL{iDQN}); dqn_hop applies to that row only
%   opt = adopt_options('opt', A, name, opt)   the options of policy name (policy_setup.m) with
%       the adopted settings: rule_fix on every rule row through opt.monitor.rule_fix, as
%       rule_fix_reading.m's test stage applied it; never through Q.dec, whose drop-alarm step
%       the DQN kinds share. dqn_hop on the deployed row through opt.monitor.dqn_hop, as
%       weak19_reading.m's test stage applied it (refused while the deployed row is unset). Any
%       other row, or A off: opt returned unchanged
%   opt = adopt_options('dqn', A, opt)   the DQN layers (dqn_hop) on the options of a deployed
%       DQN the caller names itself (the hybrid columns of C2g and C2u, the edge map's and KPI
%       7's deployed policy); the rule fix never: opt unchanged without a DQN layer
%   k = adopt_options('key', A)   the DQN layers for a run_cache key: {} without one, so every
%       key of a run without them stays as it was
%   tf = adopt_options('rule_row', name)   name is a rule row: rule, rule_esc, blind_esc,
%       rule_core, blind_core, rule_sel, rule_core3, or one of them with a descriptive suffix
%       (_nos1gc, _s1gc, _norelm, _nos1g, _relm, _s1g; policy_setup.m)
%   s = adopt_options('note', A)   one report line naming the adopted settings
%   s = adopt_options('note', A, 'dqn')   the same for a reader that carries the DQN layers only
%   N = adopt_options('names')     the known adoption names, in order
if nargin >= 1 && ischar(varargin{1}) && ismember(varargin{1}, {'opt', 'rule_row', 'note', 'names', 'deployed', 'dqn', 'key'})
    switch varargin{1}
        case 'opt',      out = with_opt(varargin{2:end});
        case 'rule_row', out = rule_row(varargin{2});
        case 'note',     out = note(varargin{2:end});
        case 'names',    out = known();
        case 'deployed', out = set_row(varargin{2:end});
        case 'dqn',      out = with_dqn(varargin{2:end});
        case 'key',      out = dqn_key(varargin{2});
    end
    return
end
cfg = []; if nargin >= 1, cfg = varargin{1}; end
out = parse(cfg);
end

function N = known()
N = {'rule_fix', 'dqn_hop'};
end

function A = parse(cfg)
A = struct('on', false, 'names', {{}}, 'rule_fix', '', 'dqn_hop', '', 'dqn_row', '');
if ~isstruct(cfg) || ~isfield(cfg, 'adopt') || isempty(cfg.adopt), return; end
D = cfg.adopt;
assert(isstruct(D) && isscalar(D), 'adopt_options:value', 'adopt_options: CFG.adopt is a struct of named adoptions');
bad = setdiff(fieldnames(D), known());
assert(isempty(bad), 'adopt_options:name', 'adopt_options: unknown adoption %s', strjoin(bad, ', '));
for n = known()
    if ~isfield(D, n{1}) || is_off(D.(n{1})), continue; end
    switch n{1}
        case 'rule_fix'
            F = rule_fix('parse', D.rule_fix);
            A.rule_fix = F.name;
        case 'dqn_hop'
            assert(ischar(D.dqn_hop) || (isstring(D.dqn_hop) && isscalar(D.dqn_hop)), 'adopt_options:value', ...
                'adopt_options: the setting of dqn_hop is a character string');
            F = dqn_fix('parse', 'dqn_hop', D.dqn_hop);
            A.dqn_hop = F.name;
    end
    A.names{end+1} = n{1};
end
A.on = ~isempty(A.names);
end

function tf = is_off(v)
tf = isempty(v) || (isstring(v) && all(strlength(v) == 0));
end

function tf = is_on(A)
tf = isstruct(A) && isfield(A, 'on') && A.on;
end

function tf = has_dqn(A)
tf = is_on(A) && isfield(A, 'dqn_hop') && ~isempty(A.dqn_hop);
end

function A = set_row(A, name)
assert(ischar(name) && ~isempty(name), 'adopt_options:row', 'adopt_options: the deployed row is a policy name');
A.dqn_row = name;
end

function opt = with_opt(A, name, opt)
if ~is_on(A), return; end
if ~isempty(A.rule_fix) && rule_row(name)
    if ~isfield(opt, 'monitor') || ~isstruct(opt.monitor), opt.monitor = struct(); end
    opt.monitor.rule_fix = A.rule_fix;
end
if has_dqn(A)
    assert(isfield(A, 'dqn_row') && ~isempty(A.dqn_row), 'adopt_options:row', ...
        'adopt_options: dqn_hop needs the deployed row (adopt_options(''deployed'', A, name))');
    if strcmp(name, A.dqn_row), opt = with_dqn(A, opt); end
end
end

function opt = with_dqn(A, opt)
if ~has_dqn(A), return; end
if ~isfield(opt, 'monitor') || ~isstruct(opt.monitor), opt.monitor = struct(); end
opt.monitor.dqn_hop = A.dqn_hop;
end

function k = dqn_key(A)
k = {};
if has_dqn(A), k = {['dqn_hop=' A.dqn_hop]}; end
end

function tf = rule_row(name)
sfx = {'_nos1gc', '_s1gc', '_norelm', '_nos1g', '_relm', '_s1g'};   % policy_setup.m's order
for k = 1:numel(sfx)
    if endsWith(name, sfx{k}), name = name(1:end - numel(sfx{k})); break; end
end
tf = ismember(name, {'rule', 'rule_esc', 'blind_esc', 'rule_core', 'blind_core', 'rule_sel', 'rule_core3'});
end

function s = note(A, scope)
s = '';
if ~is_on(A), return; end
if nargin >= 2 && strcmp(scope, 'dqn')
    if ~has_dqn(A), return; end
    s = sprintf(['Adopted settings (CFG.adopt): the deployed DQN''s hop layer dqn_hop=%s in the deployed policy''s ' ...
        'DQN + link-budget completion (hybrid) columns; a never-trained agent''s column with it is descriptive and not ' ...
        'registered; every other column is read as registered.'], A.dqn_hop);
    return
end
parts = {};
if ~isempty(A.rule_fix)
    parts{end+1} = sprintf(['the rule rows (rule, rule_esc, blind_esc, rule_core, blind_core, rule_sel, rule_core3 and their ' ...
        'descriptive variants) carry the rule''s layered answers %s'], A.rule_fix);
end
if ~isempty(A.dqn_hop)
    parts{end+1} = sprintf('the deployed DQN''s row (%s) carries the hop layer dqn_hop=%s', ternary(isempty(A.dqn_row), ...
        'not set', A.dqn_row), A.dqn_hop);
end
s = sprintf('Adopted settings (CFG.adopt): %s. %s; every other row is read as registered.', strjoin(A.names, ', '), ...
    upper_first(strjoin(parts, '; ')));
end

function s = upper_first(s)
if ~isempty(s), s(1) = upper(s(1)); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
