function h = hides_antenna(seed, v_kmh, p, geo)
%HIDES_ANTENNA  The flight's attitude lets the airframe hide a UAV antenna in some frame
%   of its run: any(d.hidden > 0) of flight_draws.m over p.cap_frames frames a cycle apart
%   (shadow_hidden.m, at the rolls the level is measured at, shadow_roll_band.m), from the
%   draws link_seed.m gives the model, before the flight is simulated. The selection of
%   the flights an airframe-shadowing cell flies (run_dataset_sweep.m, build_policy_pools.m,
%   build_check_pools.m, eval_unseen_snr.m, eval_unseen_severity.m): a flight that hides no
%   antenna is the clean link under the shadowing build.
%   seed   flight seed; v_kmh UAV speed [km/h]
%   p      params with the threat and its level set (p.active_threat, p.shadow_db)
%   geo    as flight_draws.m: ebno [dB], and alt_m, k_sig_db, aoa1_deg, rho when the
%          flight's design sets them (NaN: the seed's own)
if nargin < 4, geo = struct(); end
d = flight_draws(seed, v_kmh / 3.6 * p.carrier_freq / p.c_light, p, geo);
h = any(d.hidden > 0);
end
