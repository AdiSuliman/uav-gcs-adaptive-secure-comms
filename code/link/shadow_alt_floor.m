function v_kmh = shadow_alt_floor(alt_m, ebno, p)
%SHADOW_ALT_FLOOR  The slowest UAV speed [km/h] at which the airframe can hide an antenna at
%   the level p.shadow_db with the UAV at altitude alt_m [m] and the GCS at the distance of
%   Eb/N0 ebno [dB] (link_distance_km.m, its mast p.gcs_h_m): the level's speed floor at the
%   GCS's elevation (shadow_speed_floor.m; 0 deg without an altitude or an Eb/N0, as
%   flight_draws.m), Inf where no bank the airframe flies reaches the level's band. No
%   flight below it hides an antenna (hides_antenna.m). alt_m a scalar or an array.
x = (alt_m - p.gcs_h_m) / (1000 * link_distance_km(ebno, p));
el = asind(min(x, 1));
el(~isfinite(x)) = 0;
v_kmh = reshape(shadow_speed_floor(shadow_roll_band(p.shadow_db, p), p, el(:)'), size(el));
end
