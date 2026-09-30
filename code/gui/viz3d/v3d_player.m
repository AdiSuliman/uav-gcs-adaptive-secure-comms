function varargout = v3d_player(cmd, varargin)
%V3D_PLAYER  Unreal side of the 3D view: two identical arenas, one per
%   policy (A: DQN, B: the comparison), their cameras and the auto director.
%   S = v3d_player('build', world, M, opts)       opts: sz ([h w] per camera), hfov
%   [S, cam] = v3d_player('show', S, R, k, t, frac, shot)
%       playback at time t [s] in cycle k (fraction frac); shot: 'auto' or one of
%       'ground', 'overview', 'chase', 'side', 'emitter', 'tactical', 'wide'.
%       cam(s): pos, rot, hfov, uav (for callouts in the composited frame)
if nargin < 1, cmd = ''; end
switch cmd
    case 'build', varargout{1} = build(varargin{:});
    case 'show',  [varargout{1}, varargout{2}] = show(varargin{:});
    otherwise, error('v3d_player: unknown command %s', cmd);
end
end

%% ===================== Build =====================
function S = build(world, M, opts)
if ~isfield(opts, 'sz'), opts.sz = [540 960]; end
if ~isfield(opts, 'hfov'), opts.hfov = 62; end
LA = v3d_geometry('layout');
LB = LA; LB.G = LA.G + [0 12000 0];
S.L = {LA, LB};
S.off = LB.G - LA.G;
S.H = {v3d_scene('build', world, LA, 'A_'), v3d_scene('build', world, LB, 'B_')};
S.cam{1} = sim3d.sensors.IdealCamera(ActorName='CamA', ImageSize=opts.sz, HorizontalFieldOfView=opts.hfov);
S.cam{2} = sim3d.sensors.IdealCamera(ActorName='CamB', ImageSize=opts.sz, HorizontalFieldOfView=opts.hfov);
add(world, S.cam{1}); add(world, S.cam{2});
S.hfov = opts.hfov;
S.M = M;
S.alpha0 = -0.35;
S.cycle_s = 1.2;
S.psi = S.H{1}.psi;
S.phiRim = asind(sin(S.psi));
S.rimMRC = v3d_geometry('radius', LA, [], [], S.phiRim)';
S.dir = struct('shot', 'ground', 'until', 3, 'k', 0, 'from', [], 'tb', -inf, 'cur', []);
end

%% ===================== Show one frame =====================
function [S, cam] = show(S, R, k, t, frac, shot)
k = max(1, min(k, numel(R)));
V = cell(1, 2);
for s = 1:2
    V{s} = visual(S, S.L{s}, S.H{s}, R, k, s, t, frac);
    v3d_scene('update', S.H{s}, S.L{s}, V{s});
end
% camera (arena A), same relative pose in arena B
if strcmp(shot, 'auto'), S = director(S, R, k, t); name = S.dir.shot; else, name = shot; end
[pos, tgt] = shotPose(S, S.L{1}, S.H{1}, V{1}, name);
if isempty(S.dir.cur) || ~strcmp(S.dir.curName, name)
    if ~isempty(S.dir.cur), S.dir.from = S.dir.cur; S.dir.tb = t; end
    S.dir.curName = name;
end
b = min(max((t - S.dir.tb) / 0.9, 0), 1); b = b * b * (3 - 2 * b);
if b < 1 && ~isempty(S.dir.from)
    pos = (1 - b) * S.dir.from(1, :) + b * pos;
    tgt = (1 - b) * S.dir.from(2, :) + b * tgt;
end
S.dir.cur = [pos; tgt];
rot = v3d_geometry('rot_x', tgt - pos);
P = v3d_geometry('uav', S.L{1}, V{1}.alpha);
cam = struct('pos', {pos, pos + S.off}, 'rot', {rot, rot}, 'hfov', {S.hfov, S.hfov}, 'uav', {P.U, P.U + S.off});
for s = 1:2
    S.cam{s}.Translation = cam(s).pos;
    S.cam{s}.Rotation = rot;
end
end

%% ===================== Visual state of one side =====================
function V = visual(S, L, H, R, k, s, t, frac)
rec = R(k); sd = rec.side(s); act = sd.act;
V.t = t; V.alpha = S.alpha0 + t * L.speed / L.R;
V.link = sd.status;
V.power = 1 + 0.8 * contains(act, 'power_control');
V.rate = 1 - 0.55 * contains(act, 'rate_reduce');
V.fec = contains(act, 'fec_interleave');
V.freqdiv = contains(act, 'freq_diversity');
comps = strsplit(rec.threat, '+');
V.fault = rec.active && any(strcmp(comps, 'antenna_fault')) && mod(t * 1.7, 1) < 0.35;
V.pl_db = (rec.active && any(strcmp(comps, 'path_loss'))) * S.M.sev.path_loss_db;
V.em = struct('kind', {'', '', ''}, 'on', {false, false, false}, 'th', {0, 0, 0});
for j = 1:numel(rec.emit)
    slot = 1 + strcmp(rec.emit{j}, 'spoofing') + 2 * strcmp(rec.emit{j}, 'benign_interference');
    V.em(slot) = struct('kind', rec.emit{j}, 'on', true, 'th', rec.th(j));
end
mmse = contains(act, 'spatial_diversity');
if mmse && ~isempty(rec.th)
    V.rim = v3d_geometry('radius', L, rec.th, rec.inr, S.phiRim)';
    P = v3d_geometry('uav', L, V.alpha);
    V.fan_to = v3d_geometry('emitter', L, P, rec.th(1));
else
    V.rim = S.rimMRC;
    V.fan_to = H.A;
end
V.chan = sd.chan; V.chan2 = sd.chan2;
jam = sd.chan_jam;
if rec.active && any(strcmp(comps, 'sweeping_jammer')), jam = 1 + mod(floor(t * 3), 8); end
if rec.active && any(strcmp(comps, 'noise_burst')) && mod(floor(t * 3) * 0.618, 1) < 0.35, jam = 1:8; end
V.chan_jam = jam;
V.flash = 0;
if sd.hop, V.flash = max(0, 1 - frac * S.cycle_s / 0.6); end
V.callout = ' ';
for j = k:-1:max(1, k - 1)
    e = R(j).side(s).events;
    if ~isempty(e), V.callout = e{end}; break; end
end
end

%% ===================== Director =====================
function S = director(S, R, k, ~)
d = S.dir;
if k ~= d.k
    rec = R(k); sd = rec.side(1);
    first = rec.active && (k == 1 || ~R(k - 1).active);
    ev = strjoin(sd.events, '|');
    if first
        if isempty(rec.emit), d.shot = 'chase'; else, d.shot = 'emitter'; end
        d.until = k + 2;
    elseif sd.switched && contains(sd.act, 'spatial_diversity')
        d.shot = 'side'; d.until = k + 3;
    elseif sd.switched && contains(sd.act, 'channel_switch')
        d.shot = 'overview'; d.until = k + 3;
    elseif sd.switched
        d.shot = 'chase'; d.until = k + 3;
    elseif contains(ev, 'restored')
        d.shot = 'chase'; d.until = k + 3;
    elseif k >= d.until
        if k <= 3, d.shot = 'ground';
        elseif strcmp(d.shot, 'overview'), d.shot = 'chase'; d.until = k + 4;
        else, d.shot = 'overview'; d.until = k + 5;
        end
    end
    d.k = k;
end
S.dir = d;
end

function [pos, tgt] = shotPose(S, L, H, V, name)
P = v3d_geometry('uav', L, V.alpha);
switch name
    case 'ground'
        pos = L.G + [-45 -70 9]; tgt = P.U;
    case 'chase'
        pos = P.U - 55 * P.ef - 22 * P.ein + [0 0 14]; tgt = P.U + 12 * P.ef - [0 0 4];
    case 'side'
        dv = V.fan_to - P.U; n = dv - dot(dv, P.ef) * P.ef;
        if norm(n) < 1e-6, n = cross(P.ef, [0 0 1]); end
        m = cross(n / norm(n), P.ef);
        if m(3) < 0, m = -m; end
        pos = P.U + 48 * m / norm(m) + [0 0 4]; tgt = P.U;
    case 'emitter'
        k = find([V.em.on], 1);
        if isempty(k), [pos, tgt] = shotPose(S, L, H, V, 'overview'); return; end
        J = v3d_scene('emitterPos', H, L, V, k);
        dh = J - P.U; dh(3) = 0; dh = dh / max(norm(dh), 1e-9);
        sd = cross(dh, [0 0 1]);
        pos = J + 70 * dh + 25 * sd + [0 0 34]; tgt = 0.5 * J + 0.5 * P.U;
    case 'tactical'
        c = 0.5 * (L.G + P.U); c(3) = 0;
        pos = c + [0 0 430]; tgt = c + [0.5 0 0];
    case 'wide'
        pos = L.G + [-300 -330 230]; tgt = L.G + [60 60 0];
    otherwise   % overview
        k = find([V.em.on], 1);
        pts = [L.G; P.U];
        if ~isempty(k), pts = [pts; v3d_scene('emitterPos', H, L, V, k)]; end
        c = mean(pts, 1); c(3) = 10;
        ext = max(vecnorm(pts(:, 1:2) - c(1:2), 2, 2));
        pos = c - L.view / norm(L.view) * max(230, 1.9 * ext); tgt = c;
end
end
