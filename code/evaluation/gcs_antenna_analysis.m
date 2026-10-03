%% GCS_ANTENNA_ANALYSIS - What the tracked directional GCS antenna gives the command uplink
% The GCS antenna adds its gain to our signal at the UAV; the jammer is received by the
% UAV's own antennas and is not changed, so every dB of gain is a dB less jammer-to-signal
% ratio for the same jammer. In the 2.4 GHz licence-exempt band the radiated power is
% capped in the direction of strongest radiation: 100 mW e.i.r.p. in Israel (Ministry of
% Communications exemption list), as ETSI EN 300 328, which also caps the density at
% 10 mW/MHz (non-FHSS wideband): about 11 dBm for our 1.25 MHz signal, the stricter.
% The antenna therefore helps exactly as far as the radio stays below the cap: a radio
% that already reaches it with an omni gains nothing. The GCS of init_params.m is a
% low-power radio (nRF24L01+, 0 / -6 / -12 / -18 dBm) at -6 dBm, its 0 dBm step being the
% power_control action, on a 12 dBi antenna (the ground antenna of Rodriguez-Pineiro et
% al.'s air-ground measurements) on a GPS tracker. Pointing: measured mean errors 5.62 deg
% azimuth and 1.51 deg elevation (Nugroho & Dectaviansyah), half-normal, ITU-R F.1336
% main lobe G = G0 - 12 (phi/phi3)^2, phi3 = sqrt(27000 10^(-G0/10)) deg (gcs_pointing.m).
% A tracker that lost its target (GPS not fixed for 202 s at start-up, Nugroho &
% Dectaviansyah) falls back to the omni (Boeing, US 8,503,941).
% Every loss below is the same on every UAV antenna: to the detector and the policy it is
% path loss.
% Output: results/gcs_antenna.txt

S = load('params.mat'); p = S.params;
cap = p.gcs_eirp_cap_dbm;
step = p.cm_power_db;
ANT = struct('name', {'omni (fallback)', 'sector (Sun et al.)', 'tracked directional (system)', 'tracked helical (Momoh, simulated)'}, ...
    'g', {p.gcs_omni_dbi, 6.1, p.gcs_ant_dbi, 13.2}, 'plf', {0, 0, 0, 3});   % plf: circular antenna to the linear UAV dipoles
NS = 20000;

rep = {'=== DIRECTIONAL GCS ANTENNA ON THE UPLINK (Israel / ETSI e.i.r.p. cap) ===', ...
    sprintf('Radio %g dBm nominal, %+g dB power step; cap %.1f dBm e.i.r.p. for our 1.25 MHz signal. Gains relative to the omni on the same radio.', ...
    p.gcs_pt_dbm, step, cap), ''};
rep{end+1} = sprintf('%-36s %6s %10s %10s %11s %12s %14s', 'antenna', 'G dBi', 'e.i.r.p.', 'gain', 'power step', 'pointing', 'with step');
e_omni = min(p.gcs_pt_dbm + p.gcs_omni_dbi, cap);
for a = 1:numel(ANT)
    eirp = min(p.gcs_pt_dbm + ANT(a).g, cap);
    gain = eirp - ANT(a).plf - e_omni;
    pstep = max(0, min(step, cap - eirp));
    if a >= 3
        q = p; q.gcs_ant_dbi = ANT(a).g; q.gcs_tracked = true;
        [~, L] = arrayfun(@(s) gcs_pointing(s, q), 1:NS);
        pt = sprintf('%.2f/%.1f dB', mean(L), prctile(L, 99));
    else
        pt = '-';
    end
    rep{end+1} = sprintf('%-36s %6.1f %7.1f dBm %+7.1f dB %+8.1f dB %12s %+11.1f dB', ANT(a).name, ANT(a).g, eirp, ...
        gain, pstep, pt, gain + pstep - (max(0, min(step, cap - e_omni)))); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = ['pointing: mean / 99th percentile of the loss per flight. with step: gain over the omni when both use the ' ...
    'power step. The helical (circular) loses 3 dB against the linear UAV dipoles (polarization).'];
rep{end+1} = sprintf(['System: %g dBi tracked: %+.1f dB over the omni on the same radio (%.1f dB less jammer-to-signal ' ...
    'ratio for the same jammer, %.2fx the range); the power step adds %.1f dB, up to the cap. Lost target: omni ' ...
    'fallback, %.1f dB less, inside the path-loss levels. Above the cap no antenna or power adds anything: the ' ...
    'licence-exempt uplink never exceeds %.1f dBm e.i.r.p.'], p.gcs_ant_dbi, p.gcs_ant_dbi - p.gcs_omni_dbi, ...
    p.gcs_ant_dbi - p.gcs_omni_dbi, 10^((p.gcs_ant_dbi - p.gcs_omni_dbi) / 20), power_step_db(p), ...
    p.gcs_ant_dbi - p.gcs_omni_dbi, cap);
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/gcs_antenna.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
