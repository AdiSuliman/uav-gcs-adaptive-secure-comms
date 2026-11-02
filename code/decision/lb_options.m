function O = lb_options(f)
%LB_OPTIONS  Whether C2 scores the link-budget completion on the selected agent and stores its
%   switch with the agent (train_dqn.m, lb_adopt.m): the optional field lb_select of this
%   checkout's profile.json (f, default 'profile.json'). O.on false without the file or the
%   field (the chain as before: no switch is stored with the agent, C2e, C2g and C2u print no
%   completion columns). O.force: the optional field lb_force, true deploys the completion in
%   the smoke only, whatever the adoption rule reads (train_dqn.m); false without it.
if nargin < 1 || isempty(f), f = 'profile.json'; end
O = struct('on', false, 'force', false);
if ~isfile(f), return; end
P = jsondecode(fileread(f));
if ~isstruct(P), return; end
if isfield(P, 'lb_select'), O.on = flag(P.lb_select, f, 'lb_select'); end
if isfield(P, 'lb_force'), O.force = flag(P.lb_force, f, 'lb_force'); end
end

function v = flag(v, f, n)
if ~(isscalar(v) && islogical(v)), error('lb_options:value', '%s: %s must be true or false', f, n); end
end
