function O = wf_options(cfg, f)
%WF_OPTIONS  Which stage steps of the decision-layer additions run, all off by default: the fields of
%   this checkout's profile.json (f, default 'profile.json'), each overridden by the same field of
%   cfg (CFG of run_stage.m) when it has one.
%   dconf_select   C1d chooses the drop alarm's own confirmation per monitor (choose_drop_threshold.m)
%   s1g_select     C2 chooses the rule's lost-branch gate first among the rule settings (train_dqn.m)
%   relm_select    C2 scores the release on evidence on the selected agent (train_dqn.m)
%   r9_print       the per-Eb/N0 rows with their intervals and tags (ebno_rows.m)
%   O.dconf, O.s1g, O.relm, O.r9: logical. Without the file, or a field, a step does not run and
%   the stage's outputs are those of before. O.force: the smoke's forced cells (wf_force.m).
if nargin < 1, cfg = []; end
if nargin < 2 || isempty(f), f = 'profile.json'; end
nm = {'dconf_select', 'dconf'; 's1g_select', 's1g'; 'relm_select', 'relm'; 'r9_print', 'r9'};
O = struct('dconf', false, 's1g', false, 'relm', false, 'r9', false);
O.force = wf_force('read', cfg, f);
P = struct();
if isfile(f)
    P = jsondecode(fileread(f));
    if ~isstruct(P), P = struct(); end
end
for i = 1:size(nm, 1)
    v = [];
    if isfield(P, nm{i, 1}), v = P.(nm{i, 1}); end
    if isstruct(cfg) && isfield(cfg, nm{i, 1}), v = cfg.(nm{i, 1}); end
    if isempty(v), continue; end
    if ~(isscalar(v) && islogical(v))
        error('wf_options:value', 'wf_options: %s must be true or false', nm{i, 1});
    end
    O.(nm{i, 2}) = v;
end
end
