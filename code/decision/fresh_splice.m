function PP = fresh_splice(PP, FT)
%FRESH_SPLICE  The tree's pools PP with their test split (3) replaced by the fresh test set FT
%   (build_policy_pools.m with FRESH_SET, fresh_set_layout.m), so every reader of the test split
%   (link_env.m, policy_run_set.m) flies the fresh flights unchanged.
%   Refused when FT comes from another detector, link model, decoder, cell list, Eb/N0 grid or
%   configuration set, when it is a smoke build, or when a cell's fresh layout is not the one the
%   tree's split holds (the same positions per cell, the fresh set only longer). The tree's mean
%   tables of the split (mber, mfer) are set to NaN: no reader of a policy uses them.
%   PP.fresh holds FT's identity (block, family, geometries per cell, seeds, created).
chk = @(c, m) assert(c, 'fresh_splice:mismatch', 'fresh_splice: %s', m);
chk(isfield(FT, 'det_id') && isfield(PP, 'det_id') && strcmp(FT.det_id, PP.det_id), 'another detector (det_id)');
chk(strcmp(field_or(FT, 'model_tag', ''), field_or(PP, 'model_tag', '')), 'another link model (model_tag)');
chk(isequal(field_or(FT, 'fec_rx', []), field_or(PP, 'fec_rx', [])), 'another decoder of the coded link (fec_rx)');
chk(isequal(FT.scen, PP.scen) && isequal(FT.sev, PP.sev) && isequaln(FT.level, PP.level), 'another cell list');
chk(isequal(FT.ebno, PP.ebno) && isequal(FT.actions, PP.actions), 'another Eb/N0 grid or configuration set');
chk(~(isfield(FT, 'smoke') && FT.smoke), 'a smoke build is never read');
chk(strcmp(field_or(FT, 'core3_id', ''), field_or(PP, 'core3_id', '')), 'another three-state model (core3_id)');
nC = numel(PP.scen);
chk(isequal(size(FT.pools), [nC, numel(PP.ebno), numel(PP.actions)]), 'pools of another size');
for c = 1:nC
    old = PP.cell_geo{c}{3}; new = FT.cell_geo{c};
    chk(isempty(old) == isempty(new), sprintf('cell %d flies the test split in one layout only', c));
end
old = PP.cov{3}.seed; new = FT.cov.seed;
chk(~any(ismember(new(:), old(isfinite(old)))), 'a fresh flight is a flight of the tree''s test split');
PP.pools(:, :, :, 3) = FT.pools;
PP.runs{3} = FT.runs;
PP.cov{3} = FT.cov;
PP.speed{3} = FT.speed;
if isfield(PP, 'alt'), PP.alt{3} = FT.cov.alt_m; end
if isfield(PP, 'ksig'), PP.ksig{3} = FT.cov.k_sig; end
PP.event_frame{3} = FT.event_frame;
PP.ref_geo{3} = FT.ref_geo;
for c = 1:nC, PP.cell_geo{c}{3} = FT.cell_geo{c}; end
PP.ngeo(3) = FT.ngeo;
if isfield(PP, 'mber'), PP.mber(:, :, :, 3) = NaN; end
if isfield(PP, 'mfer'), PP.mfer(:, :, :, 3) = NaN; end
PP.fresh = struct('block', FT.block, 'fam', FT.fam, 'ngeo', FT.ngeo, 'lhs_seed', FT.lhs_seed, 'seed', {FT.seed}, ...
    'created', FT.created);
end

function v = field_or(S, n, d)
v = d; if isfield(S, n), v = S.(n); end
end
