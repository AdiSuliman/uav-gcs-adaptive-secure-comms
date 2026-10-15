function w = sig_weak_db(att, yaw, t1, tt, k_db, bdy, shd, v, null_db)
%SIG_WEAK_DB  Mean power of our signal on its weakest UAV antenna in one frame [dB],
%   against our signal at the 'GCS' block (the flight-start attitude, no airframe loss).
%   w = sig_weak_db(att, yaw, t1, tt, k_db, bdy, shd, v, null_db)
%   att      'Att' block: [GCS direction, elevation, roll, pitch, wobble amp, freq, phase,
%            roll-in start, roll rate, roll at the event's start] (turn_attitude.m,
%            shadow_frame.m)
%   yaw      heading rate [deg/s]: the GCS direction and the roll at the frame start t1 [s]
%   tt       times [s] at which the pitch with its wobble is taken (the frame's ends)
%   k_db     K-factor of our signal [dB]; bdy its airframe amplitude on each antenna
%   shd      shadow_spec.m: [depth lo hi hdg_min v_min k_db evt_db el_s], depth 0 without
%            shadowing
%   v        speed [m/s]; null_db the floor of the UAV dipole (uav_dipole_db.m)
%   As the channel (build_threat_model.m): the line of sight carries the antenna's gain
%   toward the GCS at the attitude relative to its flight-start value, the diffuse part
%   does not; the antenna the airframe hides (shadow_frame.m) loses the share of the depth
%   the event has reached, and its K is the shadow's once that loss counts as an event
%   (at least evt_db), its own before. The minimum over tt and the antennas.
%#codegen
nr = numel(bdy);
[b, r] = turn_attitude(att, yaw, t1);
[~, r0] = turn_attitude(att, yaw, 0);
th = att(4) + att(5) * sin(2*pi*att(6)*tt + att(7));
ga = uav_attitude_db(att(2), b, r, th, null_db);
g0 = uav_attitude_db(att(2), att(1), r0, att(4), null_db);
gl2 = 10.^((ga - g0) / 10);
hs = 0; gs = 0; rs = 0;
if numel(att) >= 10, rs = att(10); end              % the roll at which a roll-in's event started
if shd(1) > 0
    [hs, gs] = shadow_frame(b, att(2), r, [abs(att(3)) rs], att(4), nr, shd(2:3), shd(4), v, shd(5), shd(8));
end
w = Inf;
for k = 1:nr
    K = 10^(k_db / 10); g = bdy(k)^2;
    if k == hs
        if shd(1) * gs >= shd(7), K = 10^(shd(6) / 10); end
        g = g * 10^(-shd(1) * gs / 10);
    end
    w = min(w, 10*log10(g * min(K / (K + 1) * gl2 + 1 / (K + 1))));
end
end
