function varargout = wf_force(op, varargin)
%WF_FORCE  The smoke's forced cells of the decision-layer additions (deg_force.m's precedent): the
%   stage reads and judges as always, then deploys the named setting instead, marked as forced. Refused
%   outside SMOKE at C1d, C2 and C2e (choose_drop_threshold.m, train_dqn.m, evaluate_policies.m).
%   F = wf_force('read', cfg, f)       the fields dconf_force ([k n], one of C.confirm_drop_cand),
%                                      s1g_force and relm_force (true or false) of this checkout's
%                                      profile.json (f, default 'profile.json'), each overridden by the
%                                      same field of cfg (CFG of run_stage.m); F.dconf, F.s1g, F.relm
%                                      ([] and false when absent)
%   wf_force('smoke', F, smoke, where) an error when a cell is forced and smoke is false
%   wf_force('mark', names, smoke, where) the same for the mark dec.wf_forced of a trained agent
%   t = wf_force('any', F)             whether a cell is forced
switch op
    case 'read'
        cfg = []; f = 'profile.json';
        if numel(varargin) > 0, cfg = varargin{1}; end
        if numel(varargin) > 1 && ~isempty(varargin{2}), f = varargin{2}; end
        P = struct();
        if isfile(f)
            P = jsondecode(fileread(f));
            if ~isstruct(P), P = struct(); end
        end
        F = struct('dconf', [], 's1g', false, 'relm', false);
        v = pick(P, cfg, 'dconf_force');
        if ~isempty(v)
            cand = decision_config().confirm_drop_cand;
            if ~(isnumeric(v) && numel(v) == 2) || ~ismember(double(v(:)'), cand, 'rows')
                error('wf_force:value', 'wf_force: dconf_force must be one of %s', strjoin(arrayfun(@(i) ...
                    sprintf('[%d %d]', cand(i, :)), 1:size(cand, 1), 'UniformOutput', false), ', '));
            end
            F.dconf = double(v(:)');
        end
        for nm = {'s1g_force', 's1g'; 'relm_force', 'relm'}'
            v = pick(P, cfg, nm{1});
            if isempty(v), continue; end
            if ~(isscalar(v) && islogical(v)), error('wf_force:value', 'wf_force: %s must be true or false', nm{1}); end
            F.(nm{2}) = v;
        end
        varargout{1} = F;
    case 'any'
        F = varargin{1};
        varargout{1} = ~isempty(F.dconf) || F.s1g || F.relm;
    case 'smoke'
        [F, smoke, where] = varargin{1:3};
        if wf_force('any', F) && ~smoke
            error('wf_force:smoke', '%s: a forced cell of the decision-layer additions outside the smoke', where);
        end
    case 'mark'
        [names, smoke, where] = varargin{1:3};
        if ~isempty(names) && ~smoke
            error('wf_force:smoke', '%s: forced %s outside the smoke', where, strjoin(cellstr(names), ', '));
        end
    otherwise
        error('wf_force:op', 'wf_force: unknown operation %s', op);
end
end

function v = pick(P, cfg, n)
% Field n of the profile P, overridden by the one of cfg; [] when neither has it.
v = [];
if isfield(P, n), v = P.(n); end
if isstruct(cfg) && isfield(cfg, n), v = cfg.(n); end
end
