function out = adopt_options(varargin)
%ADOPT_OPTIONS  Adopted settings read into evaluate_policies.m (CFG.adopt), off by default.
%   A = adopt_options(cfg)     cfg: CFG of run_stage.m (a struct, or [] / absent). CFG.adopt is a
%       struct of named adoptions, each a setting string; absent, empty or '' is off. Known
%       names, in the order they apply: rule_fix (the rule's layered answers, rule_fix.m),
%       dqn_hop (the deployed DQN's hop layer; refused here: not in this checkout).
%       A: on, names (the adoptions set, in order), rule_fix (canonical setting, '' off)
%   opt = adopt_options('opt', A, name, opt)   the options of policy name (policy_setup.m) with
%       the adopted settings: rule_fix on every rule row through opt.monitor.rule_fix, as
%       rule_fix_reading.m's test stage applied it; never through Q.dec, whose drop-alarm step
%       the DQN kinds share. Any other row, or A off: opt returned unchanged
%   tf = adopt_options('rule_row', name)   name is a rule row: rule, rule_esc, blind_esc,
%       rule_core, blind_core, rule_sel, rule_core3, or one of them with a descriptive suffix
%       (_nos1gc, _s1gc, _norelm, _nos1g, _relm, _s1g; policy_setup.m)
%   s = adopt_options('note', A)   one report line naming the adopted settings
%   N = adopt_options('names')     the known adoption names, in order
if nargin >= 1 && ischar(varargin{1}) && ismember(varargin{1}, {'opt', 'rule_row', 'note', 'names'})
    switch varargin{1}
        case 'opt',      out = with_opt(varargin{2:end});
        case 'rule_row', out = rule_row(varargin{2});
        case 'note',     out = note(varargin{2});
        case 'names',    out = known();
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
A = struct('on', false, 'names', {{}}, 'rule_fix', '');
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
            error('adopt_options:dqn_hop', 'adopt_options: the adoption dqn_hop is not implemented in this checkout');
    end
    A.names{end+1} = n{1};
end
A.on = ~isempty(A.names);
end

function tf = is_off(v)
tf = isempty(v) || (isstring(v) && all(strlength(v) == 0));
end

function opt = with_opt(A, name, opt)
if ~(isstruct(A) && isfield(A, 'on') && A.on) || isempty(A.rule_fix) || ~rule_row(name), return; end
if ~isfield(opt, 'monitor') || ~isstruct(opt.monitor), opt.monitor = struct(); end
opt.monitor.rule_fix = A.rule_fix;
end

function tf = rule_row(name)
sfx = {'_nos1gc', '_s1gc', '_norelm', '_nos1g', '_relm', '_s1g'};   % policy_setup.m's order
for k = 1:numel(sfx)
    if endsWith(name, sfx{k}), name = name(1:end - numel(sfx{k})); break; end
end
tf = ismember(name, {'rule', 'rule_esc', 'blind_esc', 'rule_core', 'blind_core', 'rule_sel', 'rule_core3'});
end

function s = note(A)
s = '';
if ~(isstruct(A) && isfield(A, 'on') && A.on), return; end
s = sprintf(['Adopted settings (CFG.adopt): %s. The rule rows (rule, rule_esc, blind_esc, rule_core, blind_core, rule_sel, ' ...
    'rule_core3 and their descriptive variants) carry the rule''s layered answers %s; every other row is read as registered.'], ...
    strjoin(A.names, ', '), A.rule_fix);
end
