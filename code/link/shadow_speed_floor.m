function v_kmh = shadow_speed_floor(band, p)
%SHADOW_SPEED_FLOOR  The slowest UAV speed [km/h] at which airframe shadowing of a level can
%   occur: no source measures it below p.shadow_v_min (shadow_hidden.m), and a flight banks
%   only as far as its coordinated turn, tan(bank) = w v / g (bank_angle.m) with the heading
%   rate w at most p.yaw_rate_max (heading_rate.m), so below v = g tan(b) / w_max no flight
%   reaches the smallest bank b whose equivalent roll (shadow_equiv_roll.m) is the smallest
%   roll lo of the level's band (shadow_roll_band.m), and none hides an antenna at that
%   level: b = lo - p.shadow_el_deg, the GCS on the UAV's horizon.
%   band  [lo hi] rolls [deg], one row per level; p params (init_params.m names)
v = 9.81 * tand(max(band(:, 1) - p.shadow_el_deg, 0)) / deg2rad(p.yaw_rate_max);
v_kmh = 3.6 * max(p.shadow_v_min, v);
end
