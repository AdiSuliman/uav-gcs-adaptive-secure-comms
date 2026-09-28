%% SIM3D_PROBE - Calibration of the Unreal scene API for the 3D episode view
% Run from the repository root (startup.m puts code/ on the path):  sim3d_probe
%
% Part 1 (no Unreal): constructors, properties and enumerations of the sim3d
%   classes the 3D view needs (UAV and aircraft models, ground vehicles, scenes,
%   camera, text and arrow annotations, lights).
% Part 2 (Unreal, EmptyGrass): axis markers, size and rotation tests, candidate
%   UAV and jammer models, a transparent surface of revolution, a glowing beam
%   and a vertex-coloured mesh. An ideal camera saves one PNG per test pose.
% Part 3 (Unreal, optional): one set of images per scene that opens.
%
% Output: results/viz3d_probe/probe.txt and results/viz3d_probe/*.png

close all; clc;
root = project_root();
OUT = fullfile(root, 'results', 'viz3d_probe');
if ~isfolder(OUT), mkdir(OUT); end
PROBE_SCENES = true;

fid = fopen(fullfile(OUT, 'probe.txt'), 'w');
logf(fid, '=== sim3d probe, %s, MATLAB %s ===\n\n', string(datetime('now')), version);

%% 1. Classes and enumerations
CLASSES = {'sim3d.World', 'sim3d.Actor', 'sim3d.uav.UAV', 'sim3d.uav.FixedWing', 'sim3d.uav.FixedWingUAV', ...
    'sim3d.uav.Quadrotor', 'sim3d.aerospace.SkyHogg', 'sim3d.aerospace.GeneralAviation', ...
    'sim3d.aerospace.Aircraft', 'sim3d.vehicle.air.FixedWingAircraft', 'sim3d.vehicle.air.SkyHoggAircraft', ...
    'sim3d.auto.PassengerVehicle', 'sim3d.vehicle.ground.PassengerVehicle', 'sim3d.auto.WheeledVehicle', ...
    'sim3d.sensors.IdealCamera', 'sim3d.sensors.MainCamera', 'sim3d.graphics.Text', 'sim3d.graphics.Arrow', ...
    'sim3d.graphics.PathMarker', 'sim3d.Light', 'sim3d.environment.WeatherConfiguration', ...
    'sim3d.utils.WeatherConfiguration', 'sim3d.viewer.RenderingConfigurations'};
ENUMS = {'sim3d.environment.Scenes', 'sim3d.scene.internal.SceneType', 'sim3d.auto.VehicleTypes', ...
    'sim3d.utils.ActorTypes', 'sim3d.utils.ActorColors', 'sim3d.utils.CoordinateSystem', ...
    'sim3d.utils.MobilityTypes'};

logf(fid, '--- Part 1: classes ---\n');
for i = 1:numel(CLASSES), describeClass(fid, CLASSES{i}); end
logf(fid, '\n--- Part 1: enumerations ---\n');
for i = 1:numel(ENUMS)
    m = enumMembers(ENUMS{i});
    logf(fid, '%s: %s\n', ENUMS{i}, strjoin(m, ', '));
end

%% 2. Calibration scene
logf(fid, '\n--- Part 2: calibration scene (EmptyGrass) ---\n');
world = sim3d.World(Scene='EmptyGrass', Output=@probeOutput, Update=@probeUpdate);
try
    world.GraphicsQuality = "epic";
    logf(fid, 'GraphicsQuality = epic\n');
catch err
    logf(fid, 'GraphicsQuality not set: %s\n', err.message);
end

% Axis markers: spheres 10 m along +x, +y, +z and at the origin, with labels
MK = {'X', [10 0 0], [1 0 0]; 'Y', [0 10 0], [0 1 0]; 'Z', [0 0 10], [0 0.4 1]; 'O', [0 0 0], [1 1 1]};
for i = 1:size(MK, 1)
    a = sim3d.Actor(ActorName=['Mark' MK{i, 1}], Translation=MK{i, 2});
    createShape(a, 'sphere', [1 1 1]);
    a.Color = MK{i, 3};
    add(world, a);
end
tryAdd(fid, world, 'axis labels', @() sim3d.graphics.Text(ActorName='MarkLabels', ...
    Translation=cell2mat(MK(:, 2)) + [0 0 1.8], String=["+X"; "+Y"; "+Z"; "O"], ...
    Color=cell2mat(MK(:, 3)), FontSize=[3; 3; 3; 3]));

% Rotation test: three arrows at one point with roll/pitch/yaw = 0, yaw +90, pitch +90
tryAdd(fid, world, 'rotation arrows', @() sim3d.graphics.Arrow(ActorName='RotArrows', ...
    Translation=repmat([0 -20 3], 3, 1), Rotation=[0 0 0; 0 0 pi/2; 0 pi/2 0], ...
    Color=[1 0 0; 0 1 0; 0 0.4 1], Length=[6; 6; 6]));

% Size test: a box of [4 2 1] and the smoke-test mast (cylinder [0.5 0.5 6]),
% and a long box yawed by +30 deg
shapeActor(fid, world, 'SizeBox', 'box', {[4 2 1]}, [20 0 0.5], [0 0 0], [0.9 0.9 0.2]);
shapeActor(fid, world, 'SizeMast', 'cylinder', {[0.5 0.5 6]}, [20 -8 3], [0 0 0], [0.8 0.8 0.8]);
shapeActor(fid, world, 'YawBox', 'box', {[8 0.6 0.6]}, [20 10 0.3], [0 0 pi/6], [1 0.3 0.8]);

% Transparent surface of revolution (receive-pattern candidate): a two-lobe
% profile revolved about the actor z axis
th = linspace(0, pi, 61)';
r = 4 * (0.25 + 0.75 * abs(cos(th)));
lobe = shapeActor(fid, world, 'PatternTest', 'revolution', {[r .* cos(th), r .* sin(th)], 48, false, false}, ...
    [-20 0 6], [0 0 0], [0.2 0.8 1]);
if ~isempty(lobe), lobe.Transparency = 0.55; lobe.TwoSided = true; lobe.Shininess = 0.2; end

% Glowing beam (link candidate): colour above 1 glows
beam = shapeActor(fid, world, 'GlowBeam', 'cylinder', {[0.3 0.3 20]}, [-20 12 10], [0 0 0], [0 4 1]);
if ~isempty(beam), beam.Metallic = 0; end

% Vertex-coloured mesh: a pyramid, 0-based faces as in the createMesh example
V = [-1 -1 0; 1 -1 0; 1 1 0; -1 1 0; 0 0 2];
F = [0 1 4; 1 2 4; 2 3 4; 3 0 4; 0 2 1; 0 3 2];
Nn = V - [0 0 0.7]; Nn = Nn ./ vecnorm(Nn, 2, 2);
C = [1 0 0; 0 1 0; 0 0 1; 1 1 0; 1 1 1];
try
    pm = sim3d.Actor(ActorName='MeshTest', Translation=[-20 -12 0]);
    createMesh(pm, V, Nn, F, zeros(size(V, 1), 2), C);
    pm.VertexBlend = 1;
    add(world, pm);
    logf(fid, 'MeshTest: createMesh(V, N, F, T, C) OK\n');
catch err
    logf(fid, 'MeshTest FAILED: %s\n', err.message);
end

% Candidate UAV and jammer models. FixedWingUAV and QuadrotorUAV take
% positional (name, type); the vehicle classes take name-value pairs and one
% transform row per part (row 1 = body). A model is added only when its mesh
% path resolves: Unreal aborts on an empty one.
FW = {'FixedWing', 'Fixed wing', 'Fixed Wing', 'fixedwing', 'FixedWingUAV', 'Default'};
QR = {'Quadrotor', 'QuadRotor', 'quadrotor', 'Hexarotor', 'Default'};
fwType = firstMesh(fid, 'sim3d.uav.FixedWingUAV', @(t) sim3d.uav.FixedWingUAV('FWprobe', t), FW);
qrType = firstMesh(fid, 'sim3d.uav.QuadrotorUAV', @(t) sim3d.uav.QuadrotorUAV('QRprobe', t), QR);

labels = strings(0, 1); lpos = zeros(0, 3);
MODELS = {
    'FixedWingUAV',     [30 -12 8], @() sim3d.uav.FixedWingUAV('UAVfw', fwType),                       ~isempty(fwType)
    'QuadrotorUAV',     [30  12 8], @() sim3d.uav.QuadrotorUAV('UAVqr', qrType),                       ~isempty(qrType)
    'SkyHoggAircraft',  [30 -30 8], @() sim3d.vehicle.air.SkyHoggAircraft('ActorName', 'Sky'),          true
    'FixedWingAircraft',[30  30 8], @() sim3d.vehicle.air.FixedWingAircraft('ActorName', 'FWA'),        true
    'BoxTruck',         [45 -12 0], @() sim3d.vehicle.ground.PassengerVehicle('ActorName', 'Truck', 'VehicleType', 'BoxTruck'), true
    'SmallPickupTruck', [45  12 0], @() sim3d.vehicle.ground.PassengerVehicle('ActorName', 'Pickup', 'VehicleType', 'SmallPickupTruck'), true};
for i = 1:size(MODELS, 1)
    if ~MODELS{i, 4}, logf(fid, '\n%s skipped: no valid type found\n', MODELS{i, 1}); continue; end
    if placeModel(fid, world, MODELS{i, 1}, MODELS{i, 3}, MODELS{i, 2})
        labels(end + 1, 1) = string(MODELS{i, 1}); lpos(end + 1, :) = MODELS{i, 2} + [0 0 5]; %#ok<SAGROW>
    end
end
if ~isempty(labels)
    tryAdd(fid, world, 'model labels', @() sim3d.graphics.Text(ActorName='ModelLabels', ...
        Translation=lpos, String=labels, Color=ones(numel(labels), 3), FontSize=2 * ones(numel(labels), 1)));
end

% Camera poses: position [m] and rotation [roll pitch yaw, rad]
P = struct('name', {'level', 'pitch_pos', 'pitch_neg', 'yaw_pos', 'roll_pos', 'down_pitch_pos', ...
    'down_pitch_neg', 'overview'}, ...
    'T', {[-40 0 6], [-40 0 6], [-40 0 6], [-40 0 6], [-40 0 6], [0 0 70], [0 0 70], [-45 -35 30]}, ...
    'R', {[0 0 0], [0 0.3 0], [0 -0.3 0], [0 0 0.5], [0 0.5 0], [0 pi/2 0], [0 -pi/2 0], [0 0.45 0.66]});
cam = sim3d.sensors.IdealCamera(ActorName='ProbeCam', ImageSize=[720 1280], HorizontalFieldOfView=70);
cam.Translation = P(1).T; cam.Rotation = P(1).R;
add(world, cam);
vp = [];
try
    vp = createViewpoint(world, Name='ProbeView', Translation=[-40 0 6], Rotation=[0 0.3 0]);
catch err
    logf(fid, 'createViewpoint FAILED: %s\n', err.message);
end
try
    world.EnablePacing = true;
catch err
    logf(fid, 'EnablePacing not set: %s\n', err.message);
end

DT = 0.05;
world.UserData = struct('cam', cam, 'P', P, 'H', 10, 'WARM', 40, 'HOLD_END', 160, 'k', 0, ...
    'out', OUT, 'prefix', 'calib', 'fid', fid, 'vp', vp, 'said', false);
nStep = world.UserData.WARM + numel(P) * world.UserData.H + world.UserData.HOLD_END;
logf(fid, 'Running %d steps of %.2f s\n', nStep, DT);
run(world, DT, nStep * DT);
finishRun(fid, world, nStep * DT);
close(world); delete(world); clear world

%% 3. Scenes
if PROBE_SCENES
    logf(fid, '\n--- Part 3: scenes ---\n');
    cand = {'EmptyGrass', 'OpenSurface', 'BlankScene', 'Airport'};
    PS = struct('name', {'level', 'pitch_pos', 'pitch_neg'}, 'T', {[-30 0 25], [-30 0 25], [-30 0 25]}, ...
        'R', {[0 0 0], [0 0.4 0], [0 -0.4 0]});
    for i = 1:numel(cand)
        clear w
        try
            w = sim3d.World(Scene=cand{i}, Output=@probeOutput, Update=@probeUpdate);
            c2 = sim3d.sensors.IdealCamera(ActorName='SceneCam', ImageSize=[540 960], HorizontalFieldOfView=80);
            c2.Translation = PS(1).T; c2.Rotation = PS(1).R;
            add(w, c2);
            try w.EnablePacing = true; catch, end
            w.UserData = struct('cam', c2, 'P', PS, 'H', 10, 'WARM', 60, 'HOLD_END', 0, 'k', 0, ...
                'out', OUT, 'prefix', ['scene_' cand{i}], 'fid', fid, 'vp', [], 'said', true);
            run(w, DT, (60 + numel(PS) * 10 + 2) * DT);
            finishRun(fid, w, (60 + numel(PS) * 10 + 2) * DT);
            close(w); delete(w);
            logf(fid, 'Scene %-18s OK\n', cand{i});
        catch err
            logf(fid, 'Scene %-18s FAILED: %s\n', cand{i}, err.message);
            try close(w); delete(w); catch, end
        end
    end
end

logf(fid, '\nDone. Images in %s\n', OUT);
fclose(fid);

%% ===================== Callbacks =====================
function probeOutput(world, varargin)
U = world.UserData;
try
    U.k = U.k + 1;
    if U.k == 2 && ~isempty(U.vp)
        try setView(world, U.vp); catch err, logf(U.fid, 'setView FAILED: %s\n', err.message); end
    end
    i = poseIndex(U);
    if i >= 1 && i <= numel(U.P)
        U.cam.Translation = U.P(i).T;
        U.cam.Rotation = U.P(i).R;
    elseif i > numel(U.P) && ~U.said
        fprintf('\n>>> Poses captured. Take a screenshot of the Unreal window now (viewpoint ProbeView).\n\n');
        U.said = true;
    end
catch err
    logf(U.fid, '  Output callback FAILED at step %d: %s\n', U.k, err.message);
end
world.UserData = U;
end

function probeUpdate(world, varargin)
U = world.UserData;
try
    i = poseIndex(U);
    if i >= 1 && i <= numel(U.P) && mod(U.k - U.WARM, U.H) == U.H - 1
        img = read(U.cam);
        f = fullfile(U.out, sprintf('%s_%02d_%s.png', U.prefix, i, U.P(i).name));
        imwrite(img, f);
        logf(U.fid, '  saved %s (%s %s)\n', f, class(img), mat2str(size(img)));
    end
catch err
    logf(U.fid, '  Update callback FAILED at step %d: %s\n', U.k, err.message);
end
end

function finishRun(fid, world, stopTime)
% run() returns before the simulation ends: wait for it, then report how far it got.
t0 = tic;
try
    wait(world);
catch err
    logf(fid, '  wait FAILED: %s\n', err.message);
end
while world.SimulationTime < stopTime - 0.1 && toc(t0) < 120
    pause(0.2);
end
logf(fid, '  run finished: %d callback steps, SimulationTime %.2f s, %.1f s wall\n', ...
    world.UserData.k, world.SimulationTime, toc(t0));
end

function i = poseIndex(U)
if U.k <= U.WARM, i = 0; else, i = floor((U.k - U.WARM - 1) / U.H) + 1; end
end

%% ===================== Helpers =====================
function logf(fid, varargin)
fprintf(varargin{:});
fprintf(fid, varargin{:});
end

function describeClass(fid, cn)
mc = meta.class.fromName(cn);
if isempty(mc), logf(fid, '\n%s: NOT FOUND\n', cn); return; end
sup = strjoin(arrayfun(@(s) s.Name, mc.SuperclassList, 'UniformOutput', false), ', ');
logf(fid, '\n%s  <  %s\n', cn, sup);
ml = mc.MethodList;
short = regexprep(cn, '.*\.', '');
ct = ml(strcmp({ml.Name}, short));
if ~isempty(ct), logf(fid, '  constructor inputs: %s\n', strjoin(ct(1).InputNames, ', ')); end
pl = mc.PropertyList;
pub = arrayfun(@(p) isequal(p.GetAccess, 'public') && ~p.Hidden, pl);
for p = pl(pub)'
    if p.HasDefault, d = valStr(p.DefaultValue); else, d = ''; end
    logf(fid, '  prop %-28s %s\n', p.Name, d);
end
own = arrayfun(@(m) isequal(m.Access, 'public') && ~m.Hidden && strcmp(m.DefiningClass.Name, cn), ml);
names = unique({ml(own).Name});
if ~isempty(names), logf(fid, '  methods: %s\n', strjoin(names, ', ')); end
for m = ml(own)'
    if ~strcmp(m.Name, short) && ~isempty(m.InputNames)
        logf(fid, '    %s(%s)\n', m.Name, strjoin(m.InputNames, ', '));
    end
end
end

function m = enumMembers(cn)
m = {};
mc = meta.class.fromName(cn);
if isempty(mc), m = {'NOT FOUND'}; return; end
if ~isempty(mc.EnumerationMemberList)
    m = {mc.EnumerationMemberList.Name};
else
    pl = mc.PropertyList;
    k = arrayfun(@(p) p.Constant, pl);
    m = strcat({pl(k).Name}, ' (constant)');
end
end

function describeInstance(fid, obj)
p = properties(obj);
for i = 1:numel(p)
    try v = obj.(p{i}); s = valStr(v); catch, s = '<unreadable>'; end
    logf(fid, '    %-28s %s\n', p{i}, s);
end
end

function s = valStr(v)
if ischar(v) || (isstring(v) && isscalar(v))
    s = ['"' char(v) '"'];
elseif (isnumeric(v) || islogical(v)) && numel(v) <= 8
    s = mat2str(double(v), 4);
elseif isstring(v) || iscellstr(v)
    s = ['{' strjoin(cellstr(v), ', ') '}'];
elseif isenum(v) && isscalar(v)
    s = [class(v) '.' char(v)];
elseif isstruct(v) && isscalar(v)
    s = ['struct(' strjoin(fieldnames(v), ', ') ')'];
else
    s = sprintf('<%s %s>', class(v), mat2str(size(v)));
end
end

function tryAdd(fid, world, what, make)
try
    obj = make();
    add(world, obj);
    logf(fid, '%s: OK\n', what);
catch err
    logf(fid, '%s FAILED: %s\n', what, err.message);
end
end

function a = shapeActor(fid, world, name, shape, spec, T, R, col)
a = [];
try
    a = sim3d.Actor(ActorName=name, Translation=T, Rotation=R);
    createShape(a, shape, spec{:});
    a.Color = col;
    add(world, a);
    logf(fid, '%s: createShape(''%s'') OK\n', name, shape);
catch err
    logf(fid, '%s FAILED: %s\n', name, err.message);
    a = [];
end
end

function t = firstMesh(fid, cn, make, cands)
% First candidate type whose object resolves a mesh path.
t = '';
logf(fid, '\n%s mesh types:\n', cn);
for i = 1:numel(cands)
    try
        mp = meshPath(make(cands{i}));
        logf(fid, '  %-14s -> "%s"\n', cands{i}, mp);
        if strlength(mp) > 0 && isempty(t), t = cands{i}; end
    catch err
        logf(fid, '  %-14s FAILED: %s\n', cands{i}, err.message);
    end
end
end

function mp = meshPath(obj)
mp = "";
try
    if isprop(obj, 'Config') && isstruct(obj.Config) && isfield(obj.Config, 'MeshPath')
        mp = strjoin(string(obj.Config.MeshPath), ' | ');
    end
catch
end
if strlength(mp) == 0 && isprop(obj, 'CustomMeshPath'), mp = string(obj.CustomMeshPath); end
end

function ok = placeModel(fid, world, name, make, T)
ok = false;
try
    obj = make();
    mp = meshPath(obj);
    logf(fid, '\n%s: mesh "%s"; properties:\n', name, mp);
    describeInstance(fid, obj);
    T0 = obj.Translation;
    logf(fid, '  default Translation (%d rows):\n', size(T0, 1));
    for r = 1:min(size(T0, 1), 8), logf(fid, '    %s\n', mat2str(T0(r, :), 4)); end
    if strlength(mp) == 0, logf(fid, '  NOT added: empty mesh path\n'); return; end
    T0(1, :) = T;
    obj.Translation = T0;
    add(world, obj);
    ok = true;
    logf(fid, '  added, body at %s\n', mat2str(T));
catch err
    logf(fid, '\n%s FAILED: %s\n', name, err.message);
end
end
