%% OVERHEAD_PASS - The link while the UAV flies over the GCS
% When the UAV passes over the GCS, the GCS lies near the axis of the UAV's vertical
% omni antennas: a half-wave dipole has a null there, and on a drone the measured
% gain directly below is about 30 dB under its horizon gain (24 dB above; Badi et
% al., 2019). The pass is also the shortest distance of the flight. For every height of
% the altitude grid and every cruise distance of the Eb/N0 grid (link_distance_km.m), this
% script finds the largest drop of our signal below its cruise level along a straight
% pass over the GCS mast (overhead_drop_db.m): the free-space change plus the change of
% the dipole's gain toward the GCS. An interferer away from the GCS keeps its level, so
% the jammer-to-signal ratio rises by the same amount our signal falls. Every antenna
% loses alike: to the detector and the policy the pass is path loss.
% A pass may be flown in a turn: per speed band (the six of the commitment), the largest
% bank of a coordinated turn at its top speed (bank_angle.m at heading_rate.m's largest
% rate, up to 57.9 deg), the worst over the GCS's bearing, against the wings-level cruise
% gain. The drop of every bound is the worst over the bands; drop_level_db keeps the
% wings-level pass and drop_band_db every band.
% Overhead, the elevation of the UAV seen from the GCS changes at v / (h - mast); the only
% measured tracker lag is 49 deg at 49 km/h (Riyandi et al.), and no source measures the
% tracker's error against that rate, so each drop gets two bounds:
%   tracked  plus the mean loss of the measured pointing error (Nugroho & Dectaviansyah,
%            gcs_pointing.m)
%   lost     plus the omni fallback of a tracker that lost the UAV (gcs_ant_dbi - gcs_omni_dbi)
% A bound above the top path-loss level (22 dB) is beyond the measured levels.
% Output: results/overhead_pass.txt, results/overhead_pass.mat

S = load('params.mat'); p = S.params;
C = decision_config();
H_M   = p.alt_grid_m;                          % [m] UAV altitudes
EBNO  = p.EbNo_dB;
R0_KM = link_distance_km(EBNO, p);             % [km] cruise distance of each Eb/N0
hG    = p.gcs_h_m;
phi3  = sqrt(27000 * 10^(-p.gcs_ant_dbi / 10));
TRACK_DB = min(12 * sum((p.gcs_err_deg * sqrt(pi / 2)).^2) / phi3^2, p.gcs_floor_db);   % mean pointing loss
LOST_DB  = p.gcs_ant_dbi - p.gcs_omni_dbi;     % omni fallback
PL_TOP   = C.sev.path_loss.levels(end);        % top path-loss level [dB]
rate = rad2deg(p.v_max ./ (H_M - hG));         % elevation rate overhead at the top speed [deg/s]

VB = linspace(p.speed_kmh_min, p.speed_kmh_max, 7);    % speed bands [km/h]
BK = arrayfun(@(v) bank_top(v, p), VB(2:end));         % largest bank in each band [deg]
A0 = zeros(numel(H_M), numel(R0_KM)); AB = zeros(numel(H_M), numel(R0_KM), numel(BK));
for i = 1:numel(H_M)
    for j = 1:numel(R0_KM)
        A0(i, j) = overhead_drop_db(H_M(i), R0_KM(j), hG, p.uav_null_db);
        for b = 1:numel(BK)
            AB(i, j, b) = overhead_drop_db(H_M(i), R0_KM(j), hG, p.uav_null_db, BK(b));
        end
    end
end
A = max(AB, [], 3);
At = A + TRACK_DB; Al = A + LOST_DB;

rep = {'=== OVERHEAD PASS: our signal relative to the cruise point of the flight ===', ...
    sprintf(['Dipole pattern floored at %g dB directly below (Badi et al.); free space; GCS antenna on a %g m mast; ' ...
    'the jammer keeps its level.'], p.uav_null_db, hG), ...
    sprintf(['Bounds: tracked +%.2f dB (mean loss of the measured pointing error), lost +%g dB (omni fallback); ' ...
    '* above the %g dB top path-loss level.'], TRACK_DB, LOST_DB, PL_TOP), ''};
hd = arrayfun(@(e, r) sprintf('%g dB %.2f km', e, r), EBNO, R0_KM, 'UniformOutput', false);
tbl = {'dipole only, wings level', A0; 'dipole only, worst bank', A; 'tracked, worst bank', At; ...
    'tracker lost, worst bank', Al};
for k = 1:size(tbl, 1)
    rep{end+1} = sprintf('Largest drop below the cruise level [dB], %s:', tbl{k, 1}); %#ok<SAGROW>
    rep{end+1} = sprintf('%-10s %10s %s', 'altitude', 'deg/s', sprintf('%16s', hd{:})); %#ok<SAGROW>
    for i = 1:numel(H_M)
        x = tbl{k, 2}(i, :);
        row = arrayfun(@(v) sprintf('%.1f%s', v, repmat('*', 1, v > PL_TOP)), x, 'UniformOutput', false);
        rep{end+1} = sprintf('%-10s %10.0f %s', sprintf('%g m', H_M(i)), rate(i), sprintf('%16s', row{:})); %#ok<SAGROW>
    end
    rep{end+1} = ''; %#ok<SAGROW>
end
rep{end+1} = 'Largest drop with the dipole alone per speed band (its largest bank), over the altitudes and distances:';
for b = 1:numel(BK)
    x = AB(:, :, b);
    rep{end+1} = sprintf('  %5.1f-%5.1f km/h, bank %4.1f deg: %.1f dB', VB(b), VB(b+1), BK(b), max(x(:))); %#ok<SAGROW>
end
rep{end+1} = sprintf(['Largest drop of our signal below its cruise level during the pass: %.1f dB with the dipole ' ...
    'alone (%.1f dB wings level), %.1f dB with the tracker lost (the jammer-to-signal ratio rises by the same).'], ...
    max(A(:)), max(A0(:)), max(Al(:)));
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/overhead_pass.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
OHP = struct('alt_m', H_M, 'ebno', EBNO, 'r0_km', R0_KM, 'gcs_h_m', hG, 'null_db', p.uav_null_db, ...
    'drop_db', A, 'track_db', TRACK_DB, 'lost_db', LOST_DB, 'drop_tracked_db', At, 'drop_lost_db', Al, ...
    'drop_level_db', A0, 'drop_band_db', AB, 'band_kmh', VB, 'bank_deg', BK, ...
    'pl_top_db', PL_TOP, 'el_rate_dps', rate, 'v_kmh', p.speed_kmh_max, 'created', datestr(now));
save('results/overhead_pass.mat', 'OHP');

function b = bank_top(v_kmh, p)
% Largest bank of a coordinated turn at v_kmh [km/h]: bank_angle.m at the largest heading
% rate of heading_rate.m.
fd = v_kmh / 3.6 * p.carrier_freq / p.c_light;
v = max(v_kmh / 3.6, p.turn_v_floor);
b = bank_angle(min(rad2deg(9.81 * tand(p.roll_max_deg) / v), p.yaw_rate_max), fd, p);
end
