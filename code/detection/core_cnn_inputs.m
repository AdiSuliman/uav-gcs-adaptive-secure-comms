function IN = core_cnn_inputs(CC, in, out)
%CORE_CNN_INPUTS  The files stage B3c reads (train_core_cnn.m), only ever loaded.
%   IN = core_cnn_inputs(CC) the working folder's own: CC.splits, CC.params, CC.test,
%   CC.test_params, CC.hybrid_pred and CC.hybrid_metrics (core_cnn_config.m).
%   IN = core_cnn_inputs(CC, in, out) with in a struct (CORE_CNN_IN) that names any of these
%   fields elsewhere, for example in a source profile's tree; out is the working folder, where
%   every output goes. A relative path is taken from out. An input outside out must lie in a
%   tree that does not hold out: the git checkout holding the input, else the folder above its
%   data/ or results/ folder, else its own folder. So the stage never writes into a source
%   tree; a copy inside out passes.
f = {'splits', 'params', 'test', 'test_params', 'hybrid_pred', 'hybrid_metrics'};
IN = struct();
for k = 1:numel(f), IN.(f{k}) = CC.(f{k}); end
if nargin < 2 || isempty(in), return; end
assert(isstruct(in) && isscalar(in), 'train_core_cnn:inputs', 'CORE_CNN_IN is a struct of file paths');
bad = setdiff(fieldnames(in), f);
assert(isempty(bad), 'train_core_cnn:inputs', 'CORE_CNN_IN: unknown field %s (known: %s)', ...
    strjoin(reshape(bad, 1, []), ', '), strjoin(f, ', '));
o = ci_abs(out, '');
for k = reshape(fieldnames(in), 1, [])
    p = in.(k{1});
    assert((ischar(p) && isrow(p)) || (isstring(p) && isscalar(p)), 'train_core_cnn:inputs', ...
        'CORE_CNN_IN.%s is not a file path', k{1});
    p = ci_abs(char(p), o);
    IN.(k{1}) = p;
    if ci_under(p, o), continue; end
    t = ci_tree(p);
    assert(~ci_under(o, t), 'train_core_cnn:isolation', ['the working folder %s lies in %s, the tree of ' ...
        'CORE_CNN_IN.%s (%s): run the stage in a checkout of its own, outside every source tree'], o, t, k{1}, p);
end
end

function p = ci_abs(p, base)
% Absolute, canonical path (base for a relative one).
if ~java.io.File(p).isAbsolute(), p = fullfile(base, p); end
p = char(java.io.File(p).getCanonicalPath());
if ispc, p = strrep(p, '/', '\'); end
while numel(p) > 1 && any(p(end) == '\/') && ~(ispc && numel(p) == 3 && p(2) == ':'), p(end) = []; end
end

function yes = ci_under(a, b)
% a is b or lies inside it (case-insensitive on Windows).
if ispc, a = lower(a); b = lower(b); end
yes = strcmp(a, b) || (numel(a) > numel(b) && strncmp(a, [b filesep], numel(b) + 1)) || ...
    (numel(a) > numel(b) && any(b(end) == '\/') && strncmp(a, b, numel(b)));
end

function t = ci_tree(p)
% The tree an input belongs to: its git checkout, else the folder above data/ or results/.
d = fileparts(p);
while true
    if isfolder(fullfile(d, '.git')) || isfile(fullfile(d, '.git')), t = d; return; end
    up = fileparts(d);
    if isempty(up) || strcmp(up, d), break; end
    d = up;
end
t = fileparts(p);
[up, nm] = fileparts(t);
if any(strcmpi(nm, {'data', 'results'})), t = up; end
end
