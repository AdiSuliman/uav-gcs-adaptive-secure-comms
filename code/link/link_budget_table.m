%% LINK_BUDGET_TABLE - What the simulated Eb/N0 and severities mean physically
% The link model is link-level: range enters only through Eb/N0, the jammer's range
% through the JSR, and obstruction through the path loss. This table turns them
% into distances with the free-space (Friis) loss at 2.4 GHz (link_distance_km.m) for three
% stated hardware profiles; the simulated results hold for every profile, only the
% distance attached to each Eb/N0 changes. Profile A keeps the licence-exempt cap at
% 2.4 GHz: 100 mW e.i.r.p. in Israel (Ministry of Communications), as ETSI EN 300 328,
% which also caps 10 mW/MHz (about 11 dBm for our 1.25 MHz signal). It is the GCS of
% init_params.m: a -6 dBm radio on the tracked 12 dBi antenna (6 dBm e.i.r.p., up to the
% cap with the power step), and the same radio on its omni fallback; profile A tracked is
% the distance axis of the results. Profile B is a data link in licensed spectrum;
% air-ground measurement campaigns used transmit powers of 27-44 dBm (Khawaja et al.); it
% is shown at the 120 m ceiling as an illustration only, never as a commitment.
% Per height of the altitude grid (init_params.m), with the GCS antenna on its mast:
% the radio horizon (4/3 earth radius, Sun); the distance up to which 0.6 of the first
% Fresnel zone stays clear over a smooth 4/3 earth (beyond it, up to the horizon, the loss
% exceeds free space and no library source measures it); the last null of the ground
% reflection, 2 hG h / lambda; the horizon of a ground jammer on a 1.5 m tripod; and the
% ground range of every Eb/N0. Distances never go beyond 50 km, the range of the
% close-range UAV class (Tlili et al.), the largest class the system is built for.
% Ground reflection: a specular ray of up to 0.8 of the line of sight near 2.4 GHz
% (Welling, 2.3 GHz, via Sun) nulls our signal by 20 log10(1 - 0.8) = 14 dB, 4 dB beyond
% the 10 dB margin, so every position of a flight holds only up to 10^(-4/20) = 0.63 of
% the distance of its Eb/N0.
% Output: results/link_budget.txt, results/link_budget.mat (the km axis of the results)

S   = load('params.mat'); P0 = S.params; ebno = P0.EbNo_dB;
f   = P0.carrier_freq;
C   = decision_config();
Pj  = 40;     % jammer power [dBm] (10 W)
Gj  = 3;      % jammer antenna gain [dBi]
hJ  = 1.5;    % ground jammer antenna height [m] (tripod, as in the measurements of Lyu et al. and Simunek et al.)
RHO = 0.8;    % largest specular ground ray near 2.4 GHz, of the line of sight (Welling, via Sun)
DMAX = 50;    % range of the close-range UAV class [km] (Tlili et al.)
hG  = P0.gcs_h_m;
H   = P0.alt_grid_m;
lam = P0.c_light / f;
prof = struct('name', {'A tracked GCS antenna', 'A omni fallback', 'B tactical data link'}, ...
    'Pt', {P0.gcs_pt_dbm, P0.gcs_pt_dbm, 30}, 'Gt', {P0.gcs_ant_dbi, P0.gcs_omni_dbi, 12}, ...
    'hU', {P0.alt_range_m(1), P0.alt_range_m(1), P0.alt_range_m(2)});
horizon_km = @(h1, h2) 4.12 * (sqrt(h1) + sqrt(h2));                % 4/3 earth radius, heights in m

rep = {'=== LINK BUDGET: Eb/N0 AND SEVERITIES AS DISTANCES ===', ...
    sprintf(['Common assumptions: 2.4 GHz free space; UAV %g dBi, NF %g dB; margin %g dB; %g Mb/s; ' ...
    'jammer %g dBm, %g dBi; GCS antenna on a %g m mast'], P0.lb_uav_dbi, P0.lb_nf_db, P0.lb_margin_db, ...
    P0.lb_rate_bps/1e6, Pj, Gj, hG), ''};
rep{end+1} = sprintf('%-42s %s', 'Eb/N0 per UAV antenna', sprintf('%9g dB', ebno));
d_km = zeros(numel(prof), numel(ebno));
for k = 1:numel(prof)
    P = prof(k);
    q = P0; q.gcs_pt_dbm = P.Pt; q.gcs_ant_dbi = P.Gt;
    d_km(k, :) = link_distance_km(ebno, q);                           % slant distance [km]
    hz = horizon_km(P.hU, hG);
    cells_km = arrayfun(@(x) km_txt(x, min(hz, DMAX)), d_km(k, :), 'UniformOutput', false);
    rep{end+1} = sprintf('%-42s %s', sprintf('%s (%g dBm, %g dBi)', P.name, P.Pt, P.Gt), ...
        sprintf('%11s', cells_km{:})); %#ok<SAGROW>
    rep{end+1} = sprintf('%-42s radio horizon at %g m altitude: %.0f km', '', P.hU, hz); %#ok<SAGROW>
end
rep{end+1} = sprintf('(* the free-space range exceeds the radio horizon or %g km, the close-range class)', DMAX);
rep{end+1} = sprintf('Profile A with the power step (power_control): +%.1f dB, to the %.1f dBm cap; every distance x%.2f.', ...
    power_step_db(P0), P0.gcs_eirp_cap_dbm, 10^(power_step_db(P0) / 20));
rep{end+1} = 'The distance axis is the nominal power: power_control is one of the policy''s actions.';

% Per altitude: horizon, Fresnel clearance, last two-ray null, ground jammer horizon, ground range
hz_km = horizon_km(H, hG);
fr_km = arrayfun(@(h) fresnel_km(h, hG, lam), H);
nl_km = 2 * hG * H / lam / 1e3;
jz_km = horizon_km(H, hJ);
gr_km = sqrt(max(d_km(1, :).^2 - ((H(:) - hG) / 1e3).^2, 0));         % ground range, altitude x Eb/N0 [km]
rep{end+1} = '';
rep{end+1} = sprintf(['Per altitude, GCS mast %g m (km): radio horizon; 0.6 F1 clear up to (beyond it, to the ' ...
    'horizon: no measurement, no commitment); last two-ray null; horizon of a ground jammer at %g m'], hG, hJ);
rep{end+1} = sprintf('%-10s %10s %12s %14s %16s', 'altitude', 'horizon', '0.6 F1 clear', 'last 2-ray null', 'jammer horizon');
for i = 1:numel(H)
    rep{end+1} = sprintf('%-10s %10.1f %12.1f %14.1f %16.1f', sprintf('%g m', H(i)), min(hz_km(i), DMAX), ...
        min(fr_km(i), DMAX), nl_km(i), min(jz_km(i), DMAX)); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = sprintf('Ground range of profile A tracked per altitude (km): %s', sprintf('%7g dB', ebno));
for i = 1:numel(H)
    rep{end+1} = sprintf('%-10s %s', sprintf('%g m', H(i)), sprintf('%10.2f', gr_km(i, :))); %#ok<SAGROW>
end
nl_db = -20*log10(1 - RHO);
fpos = 10^(-max(nl_db - P0.lb_margin_db, 0) / 20);
rep{end+1} = sprintf(['Ground reflection %.1f of the line of sight: nulls of %.1f dB, %.1f dB beyond the margin; ' ...
    'every position of a flight holds up to %.2f x the distance of its Eb/N0.'], RHO, nl_db, nl_db - P0.lb_margin_db, fpos);
rep{end+1} = '';
rep{end+1} = 'In-band interferer (JSR at the UAV) -> jammer distance relative to the UAV-GCS distance, profile A:';
jsr = C.sev.jamming.levels;
dj = 10.^(-(jsr - (Pj + Gj - prof(1).Pt - prof(1).Gt)) / 20);
for i = 1:numel(jsr)
    rep{end+1} = sprintf('  JSR %2g dB  ->  jammer at %.2f x the GCS distance (%.1f km when the GCS is 10 km away)', ...
        jsr(i), dj(i), 10 * dj(i)); %#ok<SAGROW>
end
rep{end+1} = '';
pl = C.sev.path_loss.levels;
rep{end+1} = sprintf(['Path loss %s dB = the signal of a UAV %s times farther, or an obstruction of that loss ' ...
    '(the %g dB top level: a near-ground, below-roofline blockage, Cui et al.).'], ...
    strjoin(arrayfun(@(x) sprintf('%g', x), pl, 'UniformOutput', false), ' / '), ...
    strjoin(arrayfun(@(x) sprintf('%.1f', 10^(x/20)), pl, 'UniformOutput', false), ' / '), pl(end));
sp = C.sev.spoofing.levels;
rep{end+1} = sprintf('Spoofer %s dB over our signal = a counterfeit transmitter %s times the GCS power at equal distance.', ...
    strjoin(arrayfun(@(x) sprintf('%g', x), sp, 'UniformOutput', false), ' / '), ...
    strjoin(arrayfun(@(x) sprintf('%.2g', 10^(x/10)), sp, 'UniformOutput', false), ' / '));
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/link_budget.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
LB = struct('ebno', ebno, 'profiles', {{prof.name}}, 'd_km', d_km, 'alt_m', H, 'gcs_h_m', hG, ...
    'horizon_km', hz_km, 'fresnel_km', fr_km, 'null_km', nl_km, 'jam_h_m', hJ, 'jam_horizon_km', jz_km, ...
    'ground_km', gr_km, 'rho', RHO, 'null_db', nl_db, 'all_pos', fpos, 'dmax_km', DMAX, 'created', datestr(now));
save('results/link_budget.mat', 'LB');

function s = km_txt(d, hz)
if d > hz, s = sprintf('>%.0f*', hz); else, s = sprintf('%.1f', d); end
end

function d = fresnel_km(hU, hG, lam)
% Largest distance [km] over which 0.6 of the first Fresnel zone stays clear above a
% smooth 4/3 earth, the clearance taken at its smallest point along the path.
Re = 4/3 * 6371e3;
x = linspace(0, 1, 4001);                         % position along the path, from the GCS
mg = @(D) min(hG + (hU - hG) * x - D^2 * x .* (1 - x) / (2 * Re) - 0.6 * sqrt(lam * D * x .* (1 - x)));
d = fzero(mg, [1, 4120 * (sqrt(hU) + sqrt(hG))]) / 1e3;
end
