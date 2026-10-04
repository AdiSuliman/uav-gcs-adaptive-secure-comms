function [g, ca, cz] = uav_attitude_db(el, beta, roll, pitch, null_db)
%UAV_ATTITUDE_DB  Gain of the UAV's tilted antenna toward the GCS, polarization loss included [dB].
%   [g, ca, cz] = uav_attitude_db(el, beta, roll, pitch, null_db)
%   el      elevation of the GCS below the UAV's horizon [deg]
%   beta    broadside angle of the GCS in the horizontal plane [deg] (gcs_aoa.m); the array
%           lies along the fuselage (D58), so 0 is abeam on the right and 90 ahead
%   roll    right wing down [deg]; pitch nose up [deg]; any of them may be a vector
%   g       pattern of the vertical dipole (uav_dipole_db.m) at the angle off its tilted
%           equator, asind(|cz|), plus the polarization loss against the GCS's vertical
%           antenna: squared cosine between the two dipoles' projections on the wavefront
%           (20 log10(cos(tilt)) with the GCS ahead, Badi et al. 2019); floored at null_db
%   ca      cosine between the array axis and the GCS direction (sine of the cone angle)
%   cz      cosine between the dipole axis and the GCS direction
%   Level flight gives g = uav_dipole_db(el) and ca = cosd(el) sind(beta). A roll turns
%   the fuselage about the array axis, so only the pitch moves the array.
ux = cosd(el) .* sind(beta); uy = cosd(el) .* cosd(beta); uz = sind(el);
ca = cosd(pitch) .* ux - sind(pitch) .* uz;
cz = sind(pitch) .* cosd(roll) .* ux - sind(roll) .* uy + cosd(pitch) .* cosd(roll) .* uz;
pl = (cosd(pitch) .* cosd(roll) - cz .* uz).^2 ./ max((1 - cz.^2) .* (1 - uz.^2), 1e-12);
g = max(uav_dipole_db(asind(min(abs(cz), 1)), null_db) + 10*log10(max(min(pl, 1), 1e-12)), null_db);
end
