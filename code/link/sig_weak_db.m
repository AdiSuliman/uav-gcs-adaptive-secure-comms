function w = sig_weak_db(att, yaw, t1, tt, k_db, bdy, shd, v, null_db)
%SIG_WEAK_DB  Mean power of our signal on its weakest UAV antenna in one frame [dB],
%   against our signal at the 'GCS' block (the flight-start attitude, no airframe loss).
%   w = sig_weak_db(att, yaw, t1, tt, k_db, bdy, shd, v, null_db)
%   att      'Att' block: [GCS direction, elevation, roll, pitch, wobble amp, freq, phase]
%   yaw      heading rate [deg/s]: the GCS direction at the frame start t1 [s]
%   tt       times [s] at which the pitch with its wobble is taken (the frame's ends)
%   k_db     K-factor of our signal [dB]; bdy its airframe amplitude on each antenna
%   shd      shadow_spec.m: [depth lo hi hdg_min v_min k_db], depth 0 without shadowing
%   v        speed [m/s]; null_db the floor of the UAV dipole (uav_dipole_db.m)
%   As the channel (build_threat_model.m): the line of sight carries the antenna's gain
%   toward the GCS at the attitude relative to its flight-start value, the diffuse part
%   does not; the antenna the airframe hides (shadow_hidden.m) loses the depth and its K
%   falls to the shadow's. The minimum over tt and the antennas.
%#codegen
nr = numel(bdy);
b = att(1) + yaw * t1;
th = att(4) + att(5) * sin(2*pi*att(6)*tt + att(7));
ga = uav_attitude_db(att(2), b, att(3), th, null_db);
g0 = uav_attitude_db(att(2), att(1), att(3), att(4), null_db);
gl2 = 10.^((ga - g0) / 10);
hs = 0;
if shd(1) > 0
    hs = shadow_hidden(b, att(2), att(3), att(4), nr, shd(2:3), shd(4), v, shd(5));
end
w = Inf;
for k = 1:nr
    K = 10^(k_db / 10); g = bdy(k)^2;
    if k == hs
        K = 10^(shd(6) / 10); g = g * 10^(-shd(1) / 10);
    end
    w = min(w, 10*log10(g * min(K / (K + 1) * gl2 + 1 / (K + 1))));
end
end
