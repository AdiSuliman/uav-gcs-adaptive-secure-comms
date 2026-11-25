function out = stage_smoke(stages, CFG)
%STAGE_SMOKE  Smoke run of C2g / C2u with a CFG, for every entity.
%   out = stage_smoke() runs C2g and C2u with CFG.smoke_all_entities = true;
%   out = stage_smoke({'C2u'}, CFG) runs the named stages with the given CFG struct.
%   run_stage does not hand a CFG to the stage scripts, so its smoke runs the first
%   entity only. This runs each script the way run_stage does (run(name) with SMOKE set)
%   with CFG defined in the script's workspace. It works in the current folder, which
%   must hold the smoke data of the chain (data/policy_pools.mat, data/trained_dqn.mat);
%   the stage's outputs overwrite that folder's results.
%   out.(stage) = struct('script', name, 'entities', number of combinations / threats run).
if nargin < 1 || isempty(stages), stages = {'C2g', 'C2u'}; end
if nargin < 2, CFG = struct('smoke_all_entities', true); end
if ischar(stages) || isstring(stages), stages = cellstr(stages); end
map = struct('C2g', {{'experiment_combo_generalization', 'combos'}}, ...
    'C2u', {{'experiment_unknown_threat', 'threats'}});
out = struct();
for i = 1:numel(stages)
    st = stages{i};
    assert(isfield(map, st), 'stage_smoke: %s is not C2g or C2u', st);
    [n, ent] = run_script(map.(st){1}, map.(st){2}, CFG);
    out.(st) = struct('script', map.(st){1}, 'entities', n, 'names', {ent});
end
end

function [zz_n, zz_ent] = run_script(zz_name, zz_var, CFG) %#ok<INUSD>
% The script runs in this workspace, where SMOKE and CFG are defined as in run_stage's run_one;
% the helper's own names carry a prefix so the script cannot overwrite them.
SMOKE = true; %#ok<NASGU>
run(zz_name);
zz_n = NaN; zz_ent = {};
if exist(zz_var, 'var')
    zz_ent = eval(zz_var);
    zz_n = numel(zz_ent);
end
end
