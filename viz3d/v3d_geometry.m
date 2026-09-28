function varargout = v3d_geometry(cmd, varargin)
%V3D_GEOMETRY  Scene geometry of the Unreal 3D view (D57).
%   Not to scale: only the directions seen by the UAV array come from the link
%   model. Frame (sim3d_probe.m): x forward, y right, z up, metres; rotation
%   vectors [roll pitch yaw] in radians, pitch > 0 raises the nose (x toward z),
%   yaw > 0 turns x toward y. The grass of EmptyGrass covers x > 0 only.
%
%   L = v3d_geometry('layout')                  scene constants
%   P = v3d_geometry('uav', L, alpha)           UAV pose on its orbit around the GCS
%   [J, th] = v3d_geometry('emitter', L, P, th) ground emitter at broadside angle th [deg]
%   r = v3d_geometry('rot_z', d)                rotation taking local z to direction d
%   r = v3d_geometry('rot_x', d)                rotation taking local x to direction d (cameras)
%   zx = v3d_geometry('pattern', L, th, inr)    receive-pattern profile [z x] about the array axis
%   r = v3d_geometry('radius', L, th, inr, phi) pattern radius at broadside angles phi [deg]
%
%   The UAV orbits the GCS with its two antennas along the fuselage, so the GCS
%   stays at broadside (0 deg), as in the link model. An emitter at broadside
%   angle th sits on the ground where the direction from the UAV makes exactly
%   that angle with the broadside plane (sin th = component along the fuselage),
%   on the GCS side; it moves with the UAV so the angle holds for the episode.
switch cmd
    case 'layout',  varargout{1} = layout();
    case 'uav',     varargout{1} = uavPose(varargin{:});
    case 'emitter', [varargout{1}, varargout{2}] = emitterPos(varargin{:});
    case 'rot_z',   varargout{1} = rotZ(varargin{:});
    case 'rot_x',   varargout{1} = rotX(varargin{:});
    case 'pattern', varargout{1} = pattern(varargin{:});
    case 'radius',  varargout{1} = radius(varargin{:});
    otherwise, error('v3d_geometry: unknown command %s', cmd);
end
end

function L = layout()
L.G = [500 0 0];            % GCS foot
L.mast = 12;                % GCS antenna height [m]
L.R = 90;                   % orbit radius [m]
L.h = 35;                   % UAV altitude [m]
L.speed = 8;                % UAV speed on screen [m/s] (playback, not the model speed)
L.bank = 0.22;              % bank angle in the turn [rad]
L.uav_scale = 8;            % the stock mesh is under 1 m wingspan
L.ant_gap = 1.6;            % shown spacing of the two antennas [m]
L.d0 = L.R + 60;            % horizontal emitter distance from the UAV [m]
L.dmax = 400;
L.th_max = 84;              % larger angles cannot reach the ground within dmax
L.R0 = 14;                  % receive-pattern size [m]
L.dr_db = 25;               % pattern radius spans this many dB below the peak
L.n_rx = 2; L.dwl = 0.5; L.gcs_aoa = 0;
L.view = [150 170 -105];    % overview camera looks along this direction
L.bar_yaw = atan2(L.view(2), L.view(1));
L.farm_rot = 0.35;          % farmland grid angle (scenery)
end

function P = uavPose(L, alpha)
P.U = L.G + [L.R * cos(alpha), L.R * sin(alpha), L.h];
P.ef = [-sin(alpha), cos(alpha), 0];         % flight direction = array axis
P.ein = -[cos(alpha), sin(alpha), 0];        % horizontal, toward the GCS
P.rot = [L.bank, 0, atan2(P.ef(2), P.ef(1))];
P.ant = P.U + [-1; 1] * (L.ant_gap / 2) * P.ef - [0 0 0.6];
end

function [J, th] = emitterPos(L, P, th)
th = min(max(th, -L.th_max), L.th_max);
dh = min(max(L.d0, 1.05 * L.h * abs(tand(th))), L.dmax);
a = min(max(sind(th) * sqrt(dh^2 + L.h^2) / dh, -1), 1);
b = sqrt(1 - a^2);
J = [P.U(1:2), 0] + dh * (a * P.ef + b * P.ein);
end

function r = rotZ(d)
d = d / norm(d);
r = [0, asin(d(3)) - pi/2, atan2(d(2), d(1))];
end

function r = rotX(d)
d = d / norm(d);
r = [0, asin(d(3)), atan2(d(2), d(1))];
end

function zx = pattern(L, th, inr)
phi = linspace(-90, 90, 91);
r = radius(L, th, inr, phi);
zx = [r .* sind(phi); r .* cosd(phi)]';
end

function r = radius(L, th, inr, phi)
% Power pattern |w' a(phi)|^2 of the array, MRC (w = a_GCS) when th is empty,
% else MMSE w = (I + sum INR a a')^-1 a_GCS; radius linear in dB over L.dr_db
% (as in antenna plots, so nulls show as notches).
steer = @(t) exp(-1j * 2 * pi * L.dwl * (0:L.n_rx - 1).' * sind(t));
w = steer(L.gcs_aoa);
if ~isempty(th)
    Rm = eye(L.n_rx);
    for i = 1:numel(th)
        ai = steer(th(i));
        Rm = Rm + 10^(inr(i) / 10) * (ai * ai');
    end
    w = Rm \ w;
end
g = abs(w' * steer(phi(:)')).^2;
g0 = max(abs(w' * steer(linspace(-90, 90, 361))).^2);
r = L.R0 * max(1 + 10 * log10(max(g / g0, 1e-12)) / L.dr_db, 0.02);
end
