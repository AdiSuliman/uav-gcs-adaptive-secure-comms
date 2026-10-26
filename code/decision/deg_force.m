function varargout = deg_force(op, varargin)
%DEG_FORCE  The smoke's forced degradation test (docs/p1r_protocol.md, section 6): C1d reads and
%   adopts as always, then deploys the named candidate instead, recorded beside the rule's
%   pick. Refused outside SMOKE at C1d, C2 and C2e (choose_drop_threshold.m, train_dqn.m,
%   evaluate_policies.m).
%   names = deg_force('names')        'ratio', 'win', then 'win_q:<alpha>' and
%                                     'win_q_gate:<alpha>' per C.deg_alpha
%   v = deg_force('check', v, where)  v as char if it is one of them ('' for none), else an error
%   deg_force('smoke', v, smoke, where)  an error when v is set and smoke is false
%   [DEG, line] = deg_force('apply', DEG, v, K, BQ)  C1d's DEG with candidate v of K (deg_select)
%                                     deployed: mode, name, ber_q (BQ per alpha); forced = v,
%                                     rule_pick = the name the rule adopted; line for the report
alpha = decision_config().deg_alpha;
switch op
    case 'names'
        q = arrayfun(@(a) sprintf('win_q:%g', a), alpha, 'UniformOutput', false);
        g = arrayfun(@(a) sprintf('win_q_gate:%g', a), alpha, 'UniformOutput', false);
        varargout{1} = [{'ratio', 'win'}, q, g];
    case 'check'
        v = varargin{1}; where = 'deg_force'; if numel(varargin) > 1, where = varargin{2}; end
        if isempty(v), varargout{1} = ''; return; end
        if ~(ischar(v) || (isstring(v) && isscalar(v))) || ~ismember(char(v), deg_force('names'))
            error('deg_force:value', '%s: deg_force must be one of %s', where, strjoin(deg_force('names'), ', '));
        end
        varargout{1} = char(v);
    case 'smoke'
        [v, smoke, where] = varargin{1:3};
        if ~isempty(v) && ~smoke
            error('deg_force:smoke', '%s: forced degradation test %s outside the smoke (docs/p1r_protocol.md)', where, v);
        end
    case 'apply'
        [DEG, v, K, BQ] = varargin{1:4};
        nm = arrayfun(@(k) cand_name(k, alpha), K, 'UniformOutput', false);
        c = find(strcmp(nm, v), 1);
        if isempty(c), error('deg_force:value', 'deg_force: %s is not a candidate of C1d', v); end
        DEG.rule_pick = DEG.name; DEG.forced = v;
        DEG.mode = K(c).mode; DEG.name = K(c).name; DEG.ber_q = [];
        if K(c).q > 0, DEG.ber_q = BQ(K(c).q); end
        varargout{1} = DEG;
        varargout{2} = sprintf('Degradation test FORCED (smoke only, not an adoption): %s; the rule would adopt %s', ...
            K(c).name, DEG.rule_pick);
    otherwise
        error('deg_force:op', 'deg_force: unknown operation %s', op);
end
end

function s = cand_name(k, alpha)
% The force name of candidate k of deg_select's list.
s = k.mode; if k.q > 0, s = sprintf('%s:%g', k.mode, alpha(k.q)); end
end
