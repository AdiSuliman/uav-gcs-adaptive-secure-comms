function [cells, A, eb, opt] = dev_d91_cells(p0, C)
%DEV_D91_CELLS  Reduced cells of the d91 bit-identity proofs (docs/d91_speed.md).
%   [cells, A, eb, opt] = dev_d91_cells(p0, C): one Eb/N0 (the middle of the grid), two flights
%   of the train block, four budget configurations (no_action, fec_interleave, power_control,
%   power_control+fec_interleave) and four cells at the nominal severity: the clean link,
%   jamming, airframe shadowing on two flights of its own that roll in (C.event_run frames,
%   the event at C.event_frame, selected as build_policy_pools.m selects them) and
%   spoofing+noise_burst. cells(i): threat, p (threat_params.m), geo (pool_cell.m).
%   Runs on the code of either commit compared (only functions both have).
A = {'no_action', 'fec_interleave', 'power_control', 'power_control+fec_interleave'};
opt = struct('F_SUB', 20, 'tw', 10, 'delay_bits', 20);
si = ceil(numel(p0.EbNo_dB) / 2); eb = p0.EbNo_dB(si);
vrange = [p0.speed_kmh_min p0.speed_kmh_max];
g = pool_geometries(si, 1, 1:2, vrange, p0);
g.frames = opt.F_SUB * [1 1]; g.event = nan(1, 2);
ps = threat_params(p0, 'airframe_shadowing', C.nominal, C);
[~, band] = shadow_groups(ps.shadow_db, p0);
vr = [max(vrange(1), shadow_speed_floor(band, p0)), vrange(2)];
sel = struct('seed', @(j, v) shadow_pool_seed(1, si, 1, j, v), 'j0', 0, 'jmax', 99999, ...
    'floor', @(a) shadow_alt_floor(a, eb, ps), ...
    'keep', @(sd, v, a, kk, o, c) hides_antenna(sd, v, ps, struct('ebno', eb, 'alt_m', a, 'k_sig_db', kk, ...
    'aoa1_deg', o, 'rho', c, 'event_frame', C.event_frame, 'frames', C.event_count)));
gs = pool_geometries(si, 1, 1:2, vr, p0, [], 1, sel);
gs.frames = C.event_run * [1 1]; gs.event = C.event_frame * [1 1];
T = {'none', 'jamming', 'airframe_shadowing', 'spoofing+noise_burst'};
cells = struct('threat', T, 'p', [], 'geo', []);
for i = 1:numel(T)
    cells(i).p = threat_params(p0, T{i}, C.nominal, C);
    if strcmp(T{i}, 'airframe_shadowing'), cells(i).geo = {gs}; else, cells(i).geo = {g}; end
end
end
