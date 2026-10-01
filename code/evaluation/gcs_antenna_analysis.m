%% GCS_ANTENNA_ANALYSIS - What a directional GCS antenna gives the command uplink
% The GCS antenna adds its gain to our signal at the UAV (the jammer is received by the
% UAV's own antennas and is not changed), but in the 2.4 GHz licence-exempt band the
% radiated power is capped in the direction of strongest radiation: in Israel 100 mW
% e.i.r.p. (Ministry of Communications exemption list), as ETSI EN 300 328, which also
% caps the density at 10 mW/MHz (non-FHSS wideband) - about 11 dBm for our 1.25 MHz
% signal; the stricter of the two applies here. A radio that reaches the cap with an
% omni gains nothing toward the UAV from a directional antenna: the power has to back
% off by the extra gain. What a directional antenna then changes is how much it can
% lose: a tracked antenna points with a measured error of 5.62 deg (azimuth) and
% updates its target at most every 0.2 s (5 Hz GPS); when it has no position (GPS not
% fixed for 202 s at start-up; Nugroho & Dectaviansyah) it may point anywhere, down to
% its side-lobe floor. Patterns: ITU-R F.1336, G = G0 - 12 (e/phi3)^2 in the main lobe,
% G0 - 14 beyond it, phi3 = sqrt(27000 10^(-G0/10)) deg.
% Every loss below is the same on every UAV antenna: to the detector and the policy it
% is path loss.
% Output: results/gcs_antenna.txt

CAP_DBM = 10 + 10*log10(1.25);           % [dBm] e.i.r.p. cap of our 1.25 MHz signal (10 dBm/MHz)
G_OMNI  = 2;                             % [dBi] omni GCS antenna
ANT = struct('name', {'omni', 'sector (Sun et al.)', 'sector (Sun et al.)', 'tracked Yagi (Nugroho)', 'tracked helical (Momoh, simulated)'}, ...
    'g', {2, 5.1, 6.1, 6, 13.2}, 'tracked', {false, false, false, true, true}, 'beam_az', {360, 120, 180, NaN, NaN});
ERR_DEG = 5.62;                          % [deg] measured mean azimuth error of a GPS tracker
LAG_S   = 0.2;                           % [s] target update period (5 Hz GPS)
V_MPS   = [8 44.7];                      % [m/s] speed envelope of a turning UAV (hover floor 8 m/s) to 161 km/h
D_M     = [100 500 2000];                % [m] distances of the pass

rep = {'=== DIRECTIONAL GCS ANTENNA ON THE UPLINK (Israel / ETSI e.i.r.p. cap) ===', ...
    sprintf('Cap %.1f dBm e.i.r.p. for our 1.25 MHz signal; omni %g dBi. Gains are relative to the omni at the cap.', CAP_DBM, G_OMNI), ''};
rep{end+1} = sprintf('%-36s %8s %10s %12s %14s %14s', 'antenna', 'G0 dBi', 'phi3 deg', 'uplink gain', 'tracking loss', 'lost target');
for a = 1:numel(ANT)
    g0 = ANT(a).g;
    phi3 = sqrt(27000 * 10^(-g0 / 10));
    gain = 0;                                         % at the cap: e.i.r.p. toward the UAV unchanged
    if ANT(a).tracked
        lag = max(V_MPS) ./ D_M * LAG_S * 180/pi;     % [deg] angle the UAV moves between updates
        e = ERR_DEG + max(lag);
        trk = -min(12 * (e / phi3)^2, 14);
        lost = -14;                                   % side-lobe floor relative to the main lobe
        rep{end+1} = sprintf('%-36s %8.1f %10.0f %+11.1f dB %+12.1f dB %+12.0f dB', ANT(a).name, g0, phi3, gain, trk, lost); %#ok<SAGROW>
    else
        rep{end+1} = sprintf('%-36s %8.1f %10s %+11.1f dB %14s %14s', ANT(a).name, g0, '-', gain, '-', '-'); %#ok<SAGROW>
    end
end
rep{end+1} = '';
rep{end+1} = sprintf(['Tracking loss: measured mean error %.2f deg plus the largest lag (%.1f m/s at %g m, %.1f s) inside ' ...
    'the main lobe; a lost target falls to the side-lobe floor, %g dB under the beam.'], ERR_DEG, max(V_MPS), min(D_M), LAG_S, 14);
rep{end+1} = ['Conclusion: under the cap a directional GCS antenna gives the uplink no gain toward the UAV and only adds ' ...
    'losses when its tracker errs or loses the target (covered by the path-loss levels); an omni fallback (Boeing, ' ...
    'US 8,503,941) removes the lost-target case. Its gain counts in licensed spectrum (link_budget_table.m, profile B).'];
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/gcs_antenna.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
