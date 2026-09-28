function varargout = v3d_scene(cmd, varargin)
%V3D_SCENE  One arena of the Unreal 3D view and its per-frame update (D57).
%   H = v3d_scene('build', world, L, prefix)    GCS, UAV, link, receive pattern,
%       emitters, channel bar, labels and the countryside around L.G
%   v3d_scene('update', H, L, V)                one frame
%   P = v3d_scene('emitterPos', H, L, V, k)     position of emitter slot k (for cameras)
%
%   Frame state V: t [s], alpha (orbit angle), link ('ok' | 'marginal' | 'lost'),
%   power (beam width, 1 nominal), rate (packet speed, 1 nominal), fec, freqdiv,
%   fault (antenna 1 not receiving now), pl_db (path loss shown on the link),
%   rim (pattern radius per fan angle, 180 x 1), fan_to (point the fan plane
%   contains), em (1 x 3 struct: kind, on, th; slots are jammer truck, spoofer
%   pickup, civilian car), chan, chan2, chan_jam, flash (0..1, channel-hop
%   flash), callout (text above the UAV).
switch cmd
    case 'build',      varargout{1} = build(varargin{:});
    case 'update',     update(varargin{:});
    case 'emitterPos', varargout{1} = emitterPos(varargin{:});
    otherwise, error('v3d_scene: unknown command %s', cmd);
end
end

%% ===================== Build =====================
function H = build(world, L, prefix)
C = palette();
H.C = C; H.nCh = 8; H.pre = prefix;
nm = @(s) [prefix s];

H.env = v3d_environment(world, L, 7, prefix);

% Ground station: pad, shelter, mast, antenna panel, beacon
makeActor(world, nm('GcsPad'), 'box', {[16 16 0.3]}, L.G + [0 0 0.15], [0.42 0.41 0.38], false);
makeActor(world, nm('GcsHut'), 'box', {[6 2.6 2.6]}, L.G + [-4 -3.5 1.6], [0.30 0.33 0.22], false);
makeActor(world, nm('GcsHutRoof'), 'box', {[6.1 2.7 0.15]}, L.G + [-4 -3.5 2.95], [0.26 0.28 0.19], false);
makeActor(world, nm('GcsMast'), 'cylinder', {[0.5 0.5 L.mast]}, L.G + [0 0 L.mast / 2], [0.62 0.64 0.68], false);
makeActor(world, nm('GcsPanel'), 'box', {[0.4 2 2.6]}, L.G + [0.4 0 L.mast], [0.92 0.92 0.94], false);
makeActor(world, nm('GcsBeacon'), 'sphere', {[0.7 0.7 0.7]}, L.G + [0 0 L.mast + 1.7], [4 0.4 0.25], false);
H.A = L.G + [0 0 L.mast];

% UAV and its two antennas
H.uav = sim3d.uav.FixedWingUAV(nm('UAV'), 'FixedWing', 'Color', 'black');
H.uav.Scale = L.uav_scale * [1 1 1];
add(world, H.uav);
for k = 1:2
    H.ant{k} = makeActor(world, nm(sprintf('UavAnt%d', k)), 'sphere', {[0.8 0.8 0.8]}, L.G, C.ant, true);
end
H.flash = makeActor(world, nm('HopFlash'), 'sphere', {[1 1 1]}, L.G, [3 3 3], true);
H.flash.Transparency = 0.7; H.flash.Hidden = true;

% Command link: glowing core, soft sheath, packets (spheres, or cubes with FEC),
% a second carrier for frequency diversity, and the spoofer's fake link
H.beam = makeActor(world, nm('LinkBeam'), 'cylinder', {[0.6 0.6 1]}, L.G, C.ok, true);
H.sheath = makeActor(world, nm('LinkSheath'), 'cylinder', {[2.2 2.2 1]}, L.G, C.ok, true);
H.beam2 = makeActor(world, nm('LinkBeam2'), 'cylinder', {[0.45 0.45 1]}, L.G, C.ok, true);
H.fake = makeActor(world, nm('FakeLink'), 'cylinder', {[0.5 0.5 1]}, L.G, C.spoof, true);
hs = {H.beam, H.sheath, H.beam2, H.fake};
for i = 1:numel(hs), hs{i}.Metallic = 0; hs{i}.Shininess = 0; end
H.sheath.Transparency = 0.85; H.beam2.Hidden = true; H.fake.Hidden = true;
H.nPk = 6;
for k = 1:H.nPk
    H.pk{k} = makeActor(world, nm(sprintf('Packet%d', k)), 'sphere', {[1.5 1.5 1.5]}, L.G, C.ok, true);
    H.pkc{k} = makeActor(world, nm(sprintf('PacketFec%d', k)), 'box', {[1.6 1.6 1.6]}, L.G, C.ok, true);
    H.pkc{k}.Hidden = true;
    H.fk{k} = makeActor(world, nm(sprintf('FakePacket%d', k)), 'sphere', {[1.3 1.3 1.3]}, L.G, C.spoof, true);
    H.fk{k}.Hidden = true;
end

% Receive pattern as an antenna plot (fan through the array axis)
H.psi = linspace(0, 2 * pi, 181)'; H.psi(end) = [];
nR = numel(H.psi);
H.fan = sim3d.Actor(ActorName=nm('PatternFan'), Translation=L.G, Mobility='Movable');
createMesh(H.fan, [0 0 0; L.R0 * [cos(H.psi) zeros(nR, 1) sin(H.psi)]], repmat([0 1 0], nR + 1, 1), ...
    [zeros(nR, 1), (1:nR)', [2:nR 1]'], zeros(nR + 1, 2), fanColors(L.R0 * ones(nR, 1), L.R0));
H.fan.VertexBlend = 1; H.fan.TwoSided = true; H.fan.Transparency = 0.25; H.fan.Metallic = 0; H.fan.Shininess = 0;
add(world, H.fan);

% Emitter slots: jammer truck, spoofer pickup, civilian car; parked by the road when idle
looks = {'BoxTruck', C.jam; 'SmallPickupTruck', C.spoof; 'Hatchback', C.benign};
H.park = L.G + [-880 0 0] + [0 70 0; 0 88 0; 0 106 0];
for k = 1:3
    em = struct();
    em.veh = sim3d.vehicle.ground.PassengerVehicle('ActorName', nm(sprintf('Emit%dVeh', k)), 'VehicleType', looks{k, 1});
    T = em.veh.Translation; T(1, :) = H.park(k, :); em.veh.Translation = T;   % a vehicle needs a pose before add, or the simulation stalls
    add(world, em.veh);
    em.mast = makeActor(world, nm(sprintf('Emit%dMast', k)), 'cylinder', {[0.3 0.3 7]}, H.park(k, :), [0.25 0.25 0.27], true);
    em.head = makeActor(world, nm(sprintf('Emit%dHead', k)), 'sphere', {[1.6 1.6 1.6]}, H.park(k, :), looks{k, 2}, true);
    em.ring = cell(1, 6);
    for j = 1:6
        r = makeActor(world, nm(sprintf('Emit%dRing%d', k, j)), 'torus', {[4 4 0.4], 0.9, 48}, H.park(k, :), looks{k, 2}, true);
        r.Transparency = 0.35; r.Metallic = 0; r.Hidden = true;
        em.ring{j} = r;
    end
    em.col = looks{k, 2};
    H.em(k) = em;
end

% Channel bar above the GCS, turned toward the overview camera
H.barPos = @(k) L.G + [0 0 L.mast + 14] + (k - (H.nCh + 1) / 2) * 3.4 * [-sin(L.bar_yaw) cos(L.bar_yaw) 0];
for k = 1:H.nCh
    H.ch{k} = makeActor(world, nm(sprintf('Chan%d', k)), 'box', {[0.3 2.8 1.8]}, H.barPos(k), C.chIdle, true);
    H.ch{k}.Rotation = [0 0 L.bar_yaw];
end

% Labels for the Unreal viewer (the rendered video draws its own)
H.lbl = sim3d.graphics.Text(ActorName=nm('Labels'), Translation=repmat(L.G, 5, 1), ...
    String=["GROUND STATION"; " "; " "; " "; " "], Color=[1 1 1; 1 1 0.6; 1 0.5 0.4; 1 0.6 1; 0.9 0.9 0.9], ...
    FontSize=[2.2; 2.6; 2.4; 2.4; 2.4]);
add(world, H.lbl);
end

%% ===================== Update =====================
function update(H, L, V)
% Properties that rarely change go through setp (sent only on change).
C = H.C;
P = v3d_geometry('uav', L, V.alpha);
H.uav.Translation = P.U;
H.uav.Rotation = P.rot;
for k = 1:2
    H.ant{k}.Translation = P.ant(k, :);
    if k == 1 && V.fault, setp(H.ant{k}, 'Color', C.dead); else, setp(H.ant{k}, 'Color', C.ant); end
end
setp(H.flash, 'Hidden', V.flash <= 0);
if V.flash > 0
    H.flash.Translation = P.U; H.flash.Scale = (4 + 14 * (1 - V.flash)) * [1 1 1];
    H.flash.Transparency = 0.55 + 0.4 * (1 - V.flash);
end

% Link: core, sheath, packets; path loss dims it, power widens it
d = P.U - H.A;
dim = 10 ^ (-V.pl_db / 40);
col = C.(V.link) * dim;
rb = v3d_geometry('rot_z', d);
w = V.power;
setBeam(H.beam, H.A, d, rb, [w w norm(d)], col);
setBeam(H.sheath, H.A, d, rb, [w w norm(d)], col);
setp(H.sheath, 'Transparency', 0.85 + 0.1 * (1 - dim));
setp(H.beam2, 'Hidden', ~V.freqdiv);
if V.freqdiv
    side = cross(d / norm(d), [0 0 1]); side = side / max(norm(side), 1e-9);
    setBeam(H.beam2, H.A + 2.2 * side, d, rb, [1 1 norm(d)], col);
end
for k = 1:H.nPk
    f = mod(V.t * 0.3 * V.rate + (k - 1) / H.nPk, 1);
    p = H.A + f * d;
    setp(H.pk{k}, 'Hidden', V.fec); setp(H.pkc{k}, 'Hidden', ~V.fec);
    if V.fec
        H.pkc{k}.Translation = p; H.pkc{k}.Rotation = [V.t, 0.7 * V.t, 0]; setp(H.pkc{k}, 'Color', col);
    else
        H.pk{k}.Translation = p; setp(H.pk{k}, 'Color', col); setp(H.pk{k}, 'Scale', (0.6 + 0.4 * dim) * [1 1 1]);
    end
end

% Receive pattern: fan in the plane of the array axis and fan_to
dv = V.fan_to - P.U; n = dv - dot(dv, P.ef) * P.ef;
if norm(n) < 1e-6, n = cross(P.ef, [0 0 1]); end
n = n / norm(n);
H.fan.Translation = P.U;
H.fan.Vertices = [0 0 0; V.rim .* (cos(H.psi) * n + sin(H.psi) * P.ef)];
setp(H.fan, 'VertexColors', fanColors(V.rim, L.R0));

% Emitters follow the UAV so their broadside angle holds; parked when idle
lblT = [H.A + [0 0 7]; P.U + [0 0 10]; H.park + [0 0 12]];
lblS = ["GROUND STATION"; string(V.callout); " "; " "; " "];
P2 = v3d_geometry('uav', L, V.alpha + 0.01);
fakeOn = false;
for k = 1:3
    em = H.em(k); e = V.em(k);
    if e.on
        J = v3d_geometry('emitter', L, P, e.th);
        J2 = v3d_geometry('emitter', L, P2, e.th);
        yaw = atan2(J2(2) - J(2), J2(1) - J(1));
        moveEmitter(em, J, yaw, false);
    elseif ~isParked(em)
        moveEmitter(em, H.park(k, :), 0, true);
    end
    if e.on, src = J + [0 0 10.5]; else, src = H.park(k, :) + [0 0 10.5]; end
    on = e.on && ringsOn(e.kind, V.t);
    setp(em.head, 'Color', em.col * (0.3 + 0.7 * on));
    showRings = on && ~strcmp(e.kind, 'spoofing');
    dv = P.U - src;
    if showRings, rj = v3d_geometry('rot_z', dv); end
    for j = 1:numel(em.ring)
        setp(em.ring{j}, 'Hidden', ~showRings);
        if showRings
            f = mod(V.t * 0.45 + (j - 1) / numel(em.ring), 1);
            em.ring{j}.Translation = src + f * dv; em.ring{j}.Rotation = rj;
            em.ring{j}.Scale = (1 + 2 * f) * [1 1 1];
        end
    end
    if e.on
        lblT(2 + k, :) = J + [0 0 15];
        lblS(2 + k) = sprintf('%s  %+.0f%s', upper(kindName(e.kind)), e.th, char(176));
    end
    if e.on && strcmp(e.kind, 'spoofing')
        fakeOn = true;
        setBeam(H.fake, src, dv, v3d_geometry('rot_z', dv), [1 1 norm(dv)], C.spoof);
        for j = 1:H.nPk
            H.fk{j}.Translation = src + mod(V.t * 0.33 + (j - 1) / H.nPk, 1) * dv;
        end
    end
end
setp(H.fake, 'Hidden', ~fakeOn);
for j = 1:H.nPk, setp(H.fk{j}, 'Hidden', ~fakeOn); end
H.lbl.Translation = lblT;
if ~isequal(H.lbl.String, lblS), H.lbl.String = lblS; end

% Channel bar: ours green, second carrier teal, jammer red, both = amber
for k = 1:H.nCh
    ours = k == V.chan || k == V.chan2;
    jam = any(k == V.chan_jam);
    if ours && jam, c = C.marginal;
    elseif k == V.chan, c = C.ok;
    elseif ours, c = C.ok2;
    elseif jam, c = C.lost;
    else, c = C.chIdle;
    end
    setp(H.ch{k}, 'Color', c);
end
end

function moveEmitter(em, J, yaw, parked)
T = em.veh.Translation; T(1, :) = J; em.veh.Translation = T;
R = em.veh.Rotation; R(1, :) = [0 0 yaw]; em.veh.Rotation = R;
em.mast.Translation = J + [0 0 6.5];
em.head.Translation = J + [0 0 10.5];
u = em.mast.UserData; if ~isstruct(u), u = struct(); end
u.parked = parked; em.mast.UserData = u;
end

function tf = isParked(em)
u = em.mast.UserData;
tf = isstruct(u) && isfield(u, 'parked') && u.parked;
end

function setp(a, prop, v)
% Set an actor property only when it changes (cache in the actor's UserData).
u = a.UserData;
if isstruct(u) && isfield(u, prop) && isequal(u.(prop), v), return; end
a.(prop) = v;
if ~isstruct(u), u = struct(); end
u.(prop) = v; a.UserData = u;
end

function P = emitterPos(H, L, V, k)
if V.em(k).on
    P = v3d_geometry('emitter', L, v3d_geometry('uav', L, V.alpha), V.em(k).th);
else
    P = H.park(k, :);
end
end

%% ===================== Helpers =====================
function setBeam(a, origin, d, rot, scale, col)
a.Translation = origin + d / 2; a.Rotation = rot; a.Scale = scale; a.Color = col;
end

function on = ringsOn(kind, t)
switch kind
    case 'reactive_jamming', on = mod(t, 1.0) < 0.45;          % only while our packets are on the air
    case 'sweeping_jammer',  on = mod(t, 2.6) < 0.5;           % dwells on our channel part of the time
    case 'noise_burst',      on = mod(floor(t * 3) * 0.618, 1) < 0.35;
    otherwise,               on = true;
end
end

function s = kindName(kind)
switch kind
    case 'jamming',             s = 'Jammer';
    case 'reactive_jamming',    s = 'Reactive jammer';
    case 'sweeping_jammer',     s = 'Sweeping jammer';
    case 'noise_burst',         s = 'Noise source';
    case 'spoofing',            s = 'Spoofer';
    case 'benign_interference', s = 'Civilian emitter';
    otherwise,                  s = kind;
end
end

function a = makeActor(world, name, shape, spec, T, col, movable)
if movable
    a = sim3d.Actor(ActorName=name, Translation=T, Mobility='Movable');
else
    a = sim3d.Actor(ActorName=name, Translation=T);
end
createShape(a, shape, spec{:});
a.Color = col;
a.Metallic = 0.05; a.Shininess = 0.15;
add(world, a);
end

function c = fanColors(rim, R0)
% Rim colour by gain, as in an antenna plot: red at a null, amber, cyan at the peak.
t = min(max(rim(:) / R0, 0), 1);
lo = [3 0.2 0.1]; mid = [2.6 1.5 0.05]; hi = [0.2 1.8 2.8];
c = (t < 0.5) .* (lo + (mid - lo) .* (t / 0.5)) + (t >= 0.5) .* (mid + (hi - mid) .* ((t - 0.5) / 0.5));
c = [hi; c];
end

function C = palette()
% Colour components above 1 glow in Unreal.
C.ok = [0.2 2.4 1.0]; C.ok2 = [0.1 1.6 1.8]; C.marginal = [2.6 1.5 0.1]; C.lost = [2.8 0.2 0.15];
C.jam = [3 0.3 0.12]; C.spoof = [1.8 0.35 2.4]; C.benign = [0.8 0.8 0.8];
C.ant = [0.3 1.8 2.6]; C.dead = [0.06 0.06 0.06]; C.chIdle = [0.5 0.53 0.58];
end
