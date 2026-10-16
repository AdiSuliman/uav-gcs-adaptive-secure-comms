function e = emitter_elevation(seed, p, inr)
%EMITTER_ELEVATION  Elevation of an emitter of opportunity below the UAV's horizon [deg].
%   e = emitter_elevation(seed, p, inr): at each INR [dB] over the receiver's floor, 0
%   without an altitude (p.alt_random off). The emitter radiates our band at the
%   licence-exempt density cap (ETSI EN 300 328, 10 dBm per MHz, the cap of our own radio,
%   p.gcs_psd_dbm_mhz), the strongest such emitter and so the farthest at a given INR: free
%   space to the UAV's antenna (p.lb_uav_dbi) at the floor kTB with the noise figure
%   (link_distance_km.m's law) plus the INR; its antenna on a mast as the GCS's (p.gcs_h_m),
%   the UAV at the flight's altitude (flight_altitude.m), a flat earth (the earth's curvature
%   would put it lower in the sky still). The farthest emitter is the lowest, the most often
%   above the belly's horizon in a bank (emitter_idle.m).
e = zeros(size(inr));
if ~p.alt_random, return; end
h = flight_altitude(seed, p);
B = p.symbol_rate * (1 + p.rolloff);
pe = p.gcs_psd_dbm_mhz + 10*log10(B / 1e6);               % its power in our band [dBm]
pr = -174 + 10*log10(B) + p.lb_nf_db + inr;              % at the UAV [dBm]
d = 10.^((pe + p.lb_uav_dbi - pr - 20*log10(p.carrier_freq / 1e6) - 32.44) / 20);   % [km]
e = asind(min((h - p.gcs_h_m) ./ (1000 * d), 1));
end
