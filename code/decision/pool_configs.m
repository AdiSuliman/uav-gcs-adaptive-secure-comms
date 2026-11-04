function [C, map, twin] = pool_configs(p, threat, actions)
%POOL_CONFIGS  The configurations of one threat cell as pool_cell.m simulates them.
%   [C, map, twin] = pool_configs(p, threat, actions)
%   C     1 x nA struct: p (params of the configuration, seed cleared) and g_db (its Eb/N0
%         offset), apply_countermeasure.m
%   map   configuration whose frames each one takes: the first with the same physics
%         (params and offset), itself when it is the first
%   twin  configuration whose run each first of map flies: the first whose physics differs
%         from it in p.fec alone, itself when there is none. p.fec changes nothing of the run,
%         only its ground truth (closed_loop_truth.m), so the twin's frames are those of the
%         run with their own truth; 0 for a configuration that takes another's frames
nA = numel(actions);
C = struct('p', cell(1, nA), 'g_db', cell(1, nA));
map = zeros(1, nA); twin = zeros(1, nA);
keys = cell(1, nA); skeys = cell(1, nA);
for a = 1:nA
    [p2, g_db] = apply_countermeasure(p, threat, actions{a});
    p2.seed = [];
    C(a).p = p2; C(a).g_db = g_db;
    keys{a} = physics_key(p2, g_db);
    j = find(strcmp(keys(1:a-1), keys{a}) & map(1:a-1) == 1:a-1, 1);
    if ~isempty(j), map(a) = j; continue; end
    map(a) = a;
    skeys{a} = physics_key(no_fec(p2), g_db);
    j = find(strcmp(skeys(1:a-1), skeys{a}) & twin(1:a-1) == 1:a-1, 1);
    if isempty(j), twin(a) = a; else, twin(a) = j; end
end
end

function k = physics_key(p, g)
% Everything that changes the simulated link: the params and the Eb/N0 offset.
k = [jsonencode(p) sprintf('|%.6f', g)];
end

function p = no_fec(p)
if isfield(p, 'fec'), p = rmfield(p, 'fec'); end
end
