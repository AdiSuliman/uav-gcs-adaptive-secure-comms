function g = uav_dipole_db(th, null_db)
%UAV_DIPOLE_DB  Gain of the UAV's vertical antenna toward an elevation angle, relative to the horizon [dB].
%   g = uav_dipole_db(th, null_db): th elevation [deg] (0 horizon, 90 straight below the
%   UAV); half-wave dipole pattern (cos(pi/2 sin th) / cos th)^2, floored at null_db
%   (-30 dB, the default): a drone-to-drone link with matched polarization lost up to 30 dB
%   of RSS as the elevation angle changed (Badi et al. 2019, Sec. 4.2), the depth a real
%   mounted antenna's null reached; a link RSS change, not a single antenna's measured gain.
%   It falls faster at every angle than the cos^2 link gain measured by Badi et al. (2020).
if nargin < 2 || isempty(null_db), null_db = -30; end
g = 10*log10(max((cos(pi/2 * sind(th)) ./ max(cosd(th), 1e-9)).^2, 10^(null_db/10)));
end
