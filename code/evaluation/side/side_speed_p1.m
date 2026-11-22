function S = side_speed_p1(eval_mat, out_dir, opt)
%SIDE_SPEED_P1  D116 item 5 speed inference on a saved policy_evaluation.mat, post hoc.
%   S = side_speed_p1(eval_mat, out_dir)
%   S = side_speed_p1(eval_mat, out_dir, opt)   opt.cell_group: PP.shadow.cell_group (1 x pool cells), the
%       airframe-shadowing group of every cell, for the permutation strata; without it the strata are the
%       Eb/N0 points only and the file says so
%   eval_mat  profile 1's results/policy_evaluation.mat (opened read-only; RES, POL, iDQN, KP)
%   out_dir   a new folder; side_speed_p1.txt and .mat are written there
%   Labelled "post hoc, added after the reading, descriptive". It reads the deployed policy's recovered
%   among the recoverable threat episodes of the test single set (RES{1, iDQN}, as evaluate_policies.m
%   calls speed_reading.m) with speed_inference.m: the band means with cluster intervals, the
%   permutation test of association and the Hall and Miller upper bound. The registered verdict of
%   the profile is not changed by it.
if nargin < 3 || isempty(opt), opt = struct(); end
if ~isfile(eval_mat), error('side_speed:input', 'side_speed_p1: %s not found', eval_mat); end
out = side_out_dir(out_dir, eval_mat);
notes = {'post hoc, added after the reading, descriptive (D116 item 5); the registered verdict is not changed by it', ...
    ['estimand: the largest minus the smallest speed-band mean of the deployed policy''s recovered among the recoverable threat ' ...
    'episodes of the test single set; 9999 resamples and permutations, seeds [3101 3102] as speed_reading.m'], ...
    'bootstrap and Hall and Miller bound: flights resampled within Eb/N0 strata (flight = split and geometry)'};
L = side_header('D116 item 5 speed inference, post hoc', eval_mat, notes);
W = load(eval_mat, 'RES', 'POL', 'iDQN', 'KP');
for f = {'RES', 'iDQN', 'KP'}
    if ~isfield(W, f{1}), error('side_speed:field', 'side_speed_p1: %s holds no variable %s', eval_mat, f{1}); end
end
iDQN = double(W.iDQN); KP = W.KP;
R1 = W.RES{1, iDQN}; Rn = W.RES{1, 1};
need = {'recovered', 'speed', 'split', 'geom', 's', 'scn'};
miss = need(~isfield(R1, need));
if ~isempty(miss)
    L{end+1} = sprintf('FIELD ABSENT in RES{1, %d}: %s; nothing read', iDQN, strjoin(miss, ', '));
    side_write(out, 'side_speed_p1', L, struct('input', eval_mat, 'sha256', side_sha256(eval_mat), 'missing', {miss}));
    fprintf('%s\n', L{:});
    error('side_speed:field', 'side_speed_p1: fields absent: %s', strjoin(miss, ', '));
end
if ~isfield(KP, 'speed_bins'), error('side_speed:bins', 'side_speed_p1: KP.speed_bins is missing'); end
edges = KP.speed_bins(:)';
mrec = logical(Rn.recoverable(:)') & logical(Rn.threat(:)');
spr = [NaN NaN NaN]; haveSpr = isfield(KP, 'speed_spread') && numel(KP.speed_spread) == 3;
if haveSpr, spr = KP.speed_spread(:)' / 100; end
cg = [];
if isfield(opt, 'cell_group'), cg = opt.cell_group; end
L{end+1} = sprintf('deployed policy: %s; test single set: %d episodes, %d recoverable threat episodes; speed bands (km/h): %s', ...
    W.POL{iDQN}, numel(R1.recovered), sum(mrec), mat2str(edges, 4));
if isempty(cg)
    L{end+1} = ['permutation strata: Eb/N0 points only. The airframe-shadowing groups (PP.shadow.cell_group) are not in this file ' ...
        'and the pools file is not loaded, so the permutation p is read without them; the bootstrap and the bound do not use them'];
else
    L{end+1} = 'permutation strata: Eb/N0 points and the shadowing groups of opt.cell_group';
end
O = struct('inference', true, 'union', 'off', 'yes', '');
ws = warning('off', 'speed_reading:point'); c = onCleanup(@() warning(ws));
[SU, lines] = speed_reading(R1, mrec, [], cg, edges, spr, O);
if haveSpr
    L{end+1} = sprintf('registered spread of the file (KP.speed_spread): %.1f points [%.1f, %.1f]; reproduced here: %s', ...
        100 * spr, ternary(SU.reproduced, 'yes', 'NO'));
else
    lines = lines(~contains(lines, 'NOT REPRODUCED'));
    L{end+1} = 'the registered spread is not in the file; the spread is read here and not compared';
end
L = [L, lines];
L{end+1} = '';
L{end+1} = 'post hoc, added after the reading, descriptive; it decides nothing';
S = struct('input', eval_mat, 'sha256', side_sha256(eval_mat), 'policy', W.POL{iDQN}, 'edges', edges, 'speed', SU, ...
    'registered_spread', spr, 'shadow_groups_used', ~isempty(cg));
side_write(out, 'side_speed_p1', L, S);
fprintf('%s\n', L{:});
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
