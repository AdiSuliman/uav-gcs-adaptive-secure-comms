function fig = v3d_live(mode, src)
%V3D_LIVE  Live 3D operations console (D57).
%   Run from the repository root:  addpath('viz3d'); v3d_live
%   v3d_live('replay', file)   plays an episode recorded by the operator console
%                              (GUI_Results/episode_*.mat, D56) or a saved session
%
%   The decision layer runs live on the measured TEST pools (v3d_engine.m): the
%   DQN agent (left) and a comparison policy (right) on the same flight geometry
%   and the same frames. From the console the operator injects any single or
%   combined threat, turns on a jammer that follows channel hops, hides the class
%   from the detector (unknown threat), plays the defense scenarios, flies the
%   right side by hand (operator vs AI), picks the camera, and saves or renders
%   the session to MP4. The Unreal window is a free camera on the DQN arena.
%
%   No nested functions: static data in fig.UserData, the running state in
%   world.UserData (shared with the simulation callbacks).
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root, fullfile(root, 'viz3d'));
M = v3d_engine('load');
SC = v3d_scenarios(M);
replay = []; rmeta = [];
if nargin >= 2 && strcmp(mode, 'replay')
    [replay, rmeta] = loadReplay(src, M);
end

world = sim3d.World(Scene='EmptyGrass', Output=@liveOutput, Update=@liveUpdate);
try world.GraphicsQuality = "epic"; catch, end
try world.EnablePacing = true; catch, end
S = v3d_player('build', world, M, struct('sz', [405 720], 'hfov', 62));
LA = S.L{1};
P0 = v3d_geometry('uav', LA, S.alpha0);
vpos = mean([LA.G; P0.U], 1) - LA.view / norm(LA.view) * 260;
vp = [];
try vp = createViewpoint(world, Name='Overview', Translation=vpos, Rotation=v3d_geometry('rot_x', mean([LA.G; P0.U], 1) - vpos)); catch, end

fig = buildUI(M, SC);
fig.UserData.world = world;
fig.UserData.root = root;
fig.CloseRequestFcn = @onClose;

G = v3d_engine('new', M, struct('s', 4, 'r', 1, 'right', 'rule', 'seed', 1));
if isempty(replay), D = v3d_hud('init', hudMeta(M, 'rule')); else, D = v3d_hud('init', rmeta); end
U = struct('M', M, 'SC', {SC}, 'S', S, 'D', D, 'G', G, 'R', [], 'replay', replay, 'rmeta', rmeta, ...
    'cmd', {{}}, 'playing', true, 'cycle_s', 1.2, 'tPlay', 0, 'tNext', 0, 'k', 0, 'every', 3, 'dt', 0.08, ...
    'clk', tic, 'wall', 0, ...
    'shot', 'auto', 'cam', [], 'fig', fig, 'vp', vp, 'right', 'rule', 'err', '', 'log', {{}}, 'epStart', 1);
world.UserData = U;
run(world, U.dt, inf);
if isempty(replay)
    logLine(fig, 'Console ready. Clean link; inject a threat or play a scenario.');
else
    ui = fig.UserData.ui;
    cellfun(@(h) set(h, 'Enable', 'off'), {ui.threat, ui.follow, ui.unk, ui.inject, ui.clear, ui.right, ui.op, ...
        ui.opBtn, ui.sc, ui.scBtn, ui.ebno, ui.geo});
    ui.newBtn.Text = 'Restart replay';
    logLine(fig, sprintf('Replay: %s (%d cycles).', rmeta.subtitle, numel(replay)));
end
end

%% ===================== Simulation callbacks =====================
function liveOutput(world, varargin)
U = world.UserData;
try
    U.k = U.k + 1;
    if U.k == 3 && ~isempty(U.vp), try setView(world, U.vp); catch, end, end
    tw = toc(U.clk);                               % playback follows the wall clock
    if U.playing, U.tPlay = U.tPlay + min(tw - U.wall, 0.5); end
    U.wall = tw;
    if U.playing && U.tPlay >= U.tNext
        U = applyCommands(U);
        rec = [];
        if isempty(U.replay)
            [U.G, rec] = v3d_engine('step', U.G, U.M);
        elseif numel(U.R) < numel(U.replay)
            rec = U.replay(numel(U.R) + 1);
        end
        if ~isempty(rec)
            if isempty(U.R), U.R = rec; else, U.R(end + 1) = rec; end
            U = logEvents(U, rec);
        end
        U.tNext = U.tNext + U.cycle_s;
    end
    if ~isempty(U.R)
        k = numel(U.R);
        frac = min(max(1 - (U.tNext - U.tPlay) / U.cycle_s, 0), 1);
        U.S.cycle_s = U.cycle_s;
        [U.S, U.cam] = v3d_player('show', U.S, U.R, k, U.tPlay, frac, U.shot);
    end
catch e
    if isempty(U.err), U.err = e.message; logLine(U.fig, ['Error: ' e.message]); end
end
world.UserData = U;
end

function liveUpdate(world, varargin)
U = world.UserData;
if isempty(U.R) || mod(U.k, U.every) ~= 0 || ~isvalid(U.fig), return; end
try
    imA = read(U.S.cam{1}); imB = read(U.S.cam{2});
    R = U.R(U.epStart:end);
    img = v3d_hud('frame', U.D, imA, imB, R, numel(R), U.cam, struct('window', 30, 'notice', ''));
    U.fig.UserData.ui.view.ImageSource = img;
    U.fig.UserData.lastImg = img;
catch e
    if isempty(U.err), U.err = e.message; world.UserData = U; logLine(U.fig, ['Display error: ' e.message]); end
end
end

%% ===================== Commands =====================
function U = applyCommands(U)
keep = {};
nextT = numel(U.R) + 1;
for i = 1:numel(U.cmd)
    c = U.cmd{i};
    if isfield(c, 'at') && c.at > nextT - U.epStart + 1, keep{end + 1} = c; continue; end %#ok<AGROW>
    switch c.type
        case 'restart'
            U.R = []; U.epStart = 1; U.S.dir.until = 3; U.S.dir.shot = 'ground';
        case 'new'
            U.G = v3d_engine('new', U.M, struct('s', c.s, 'r', c.r, 'right', c.right, 'seed', randi(1e6)));
            U.right = c.right;
            U.D = v3d_hud('init', hudMeta(U.M, c.right));
            U.epStart = numel(U.R) + 1;
            U.S.dir.until = numel(U.R) + 3; U.S.dir.shot = 'ground';
        case 'inject'
            U.G = v3d_engine('inject', U.G, U.M, c.scn, c.follow, c.unk);
        case 'clear'
            U.G = v3d_engine('clear', U.G);
        case 'operator'
            U.G = v3d_engine('operator', U.G, c.a);
    end
end
U.cmd = keep;
end

function queue(fig, c)
w = fig.UserData.world; U = w.UserData;
U.cmd{end + 1} = c; w.UserData = U;
end

%% ===================== UI =====================
function fig = buildUI(M, SC)
fig = uifigure('Name', 'UAV-GCS link: 3D operations console', 'Position', [30 40 1700 930], 'Color', [0.06 0.07 0.1]);
g = uigridlayout(fig, [1 2]); g.ColumnWidth = {'1x', 380}; g.Padding = [8 8 8 8]; g.BackgroundColor = fig.Color;
left = uigridlayout(g, [2 1]); left.RowHeight = {'1x', 150}; left.Padding = [0 0 0 0]; left.BackgroundColor = fig.Color;
ui.view = uiimage(left); ui.view.ScaleMethod = 'fit';
ui.view.ImageSource = zeros(1080, 1920, 3, 'uint8');
ui.log = uitextarea(left, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 12, ...
    'BackgroundColor', [0.09 0.1 0.13], 'FontColor', [0.8 0.86 0.92]);
right = uigridlayout(g, [6 1]); right.RowHeight = {92, 150, 120, 86, 150, '1x'}; right.Padding = [0 0 0 0];
right.BackgroundColor = fig.Color;

names = arrayfun(@(e) sprintf('%g dB', e), M.PP.ebno, 'UniformOutput', false);
p = panel(right, 'EPISODE', [2 2]);
ui.ebno = uidropdown(p, 'Items', names, 'Value', '6 dB', 'Tooltip', 'Signal quality of the clean link (Eb/N0).');
ui.geo = uidropdown(p, 'Items', arrayfun(@(r) sprintf('Geometry %d', r), 1:M.nR, 'UniformOutput', false), ...
    'Tooltip', 'Test flight geometry: sets the direction of every interferer.');
ui.newBtn = uibutton(p, 'Text', 'New episode', 'ButtonPushedFcn', @onNew, 'Tooltip', 'Restart on a clean link.');
ui.pause = uibutton(p, 'state', 'Text', 'Pause', 'ValueChangedFcn', @onPause);

p = panel(right, 'THREAT', [3 2]);
thr = M.PP.scen(M.avail(2:end));
ui.threat = uidropdown(p, 'Items', cellfun(@threatLabel, thr, 'UniformOutput', false), 'ItemsData', thr);
ui.threat.Layout.Column = [1 2];
ui.follow = uicheckbox(p, 'Text', 'Jammer follows hops', 'FontColor', [0.85 0.9 0.95], ...
    'Tooltip', 'The jammer finds the new channel 3 cycles after every channel hop.');
ui.unk = uicheckbox(p, 'Text', 'Hide the class', 'FontColor', [0.85 0.9 0.95], ...
    'Tooltip', 'The detector may not name the threat: the policies see only link quality (unknown threat).');
ui.inject = uibutton(p, 'Text', 'Inject threat', 'ButtonPushedFcn', @onInject, 'BackgroundColor', [0.75 0.2 0.18], ...
    'FontColor', 'white', 'FontWeight', 'bold');
ui.clear = uibutton(p, 'Text', 'Switch off', 'ButtonPushedFcn', @onClear);

p = panel(right, 'RIGHT SIDE (vs the DQN agent)', [3 2]);
ui.right = uidropdown(p, 'Items', {'Rules + escalation', 'No response', 'Operator (you)'}, ...
    'ItemsData', {'rule', 'none', 'operator'}, 'ValueChangedFcn', @onRight);
ui.right.Layout.Column = [1 2];
ui.op = uidropdown(p, 'Items', cellfun(@actLabel, M.PP.actions, 'UniformOutput', false), ...
    'ItemsData', num2cell(1:numel(M.PP.actions)), 'Enable', 'off');
ui.op.Layout.Column = [1 2];
ui.opBtn = uibutton(p, 'Text', 'Apply my response', 'ButtonPushedFcn', @onOperator, 'Enable', 'off');
ui.opBtn.Layout.Column = [1 2];

p = panel(right, 'DEFENSE SCENARIOS', [2 1]);
ui.sc = uidropdown(p, 'Items', {SC.title}, 'ItemsData', num2cell(1:numel(SC)));
ui.scBtn = uibutton(p, 'Text', 'Play scenario', 'ButtonPushedFcn', @onScenario);

p = panel(right, 'VIEW AND SESSION', [3 2]);
ui.shot = uidropdown(p, 'Items', {'Auto director', 'Overview', 'Chase', 'Antenna plot (side)', 'Interferer', ...
    'Top-down', 'From the GCS', 'Wide'}, 'ItemsData', {'auto', 'overview', 'chase', 'side', 'emitter', 'tactical', ...
    'ground', 'wide'}, 'ValueChangedFcn', @onShot);
ui.speed = uidropdown(p, 'Items', {'Slow (2 s/cycle)', 'Normal (1.2 s)', 'Fast (0.6 s)'}, ...
    'ItemsData', {2, 1.2, 0.6}, 'Value', 1.2, 'ValueChangedFcn', @onSpeed);
ui.save = uibutton(p, 'Text', 'Save session', 'ButtonPushedFcn', @onSave);
ui.render = uibutton(p, 'Text', 'Render session to MP4', 'ButtonPushedFcn', @onRender);
ui.snap = uibutton(p, 'Text', 'Save picture (PNG)', 'ButtonPushedFcn', @onSnap, ...
    'Tooltip', 'Saves the current full-HD frame to results/viz3d_pictures (for the report and slides).');
ui.help = uilabel(p, 'Text', 'Keys: Space pause, I inject, O off, N new, 1-8 camera', 'FontColor', [0.6 0.66 0.74], ...
    'WordWrap', 'on');

fig.UserData = struct('ui', ui, 'M', M, 'SC', SC, 'lastImg', []);
fig.KeyPressFcn = @onKey;
end

function p = panel(parent, title, sz)
pn = uipanel(parent, 'Title', title, 'BackgroundColor', [0.1 0.12 0.16], 'ForegroundColor', [0.72 0.8 0.9], ...
    'FontWeight', 'bold');
p = uigridlayout(pn, sz); p.BackgroundColor = [0.1 0.12 0.16]; p.Padding = [6 6 6 6]; p.RowSpacing = 5;
end

%% ===================== UI callbacks =====================
function onNew(src, ~)
fig = ancestor(src, 'figure'); ui = fig.UserData.ui;
U = fig.UserData.world.UserData;
if ~isempty(U.replay), queue(fig, struct('type', 'restart')); logLine(fig, 'Replay restarted.'); return; end
queue(fig, struct('type', 'new', 's', find(strcmp(ui.ebno.Items, ui.ebno.Value)), ...
    'r', find(strcmp(ui.geo.Items, ui.geo.Value)), 'right', ui.right.Value));
logLine(fig, sprintf('New episode: %s, %s, right side %s.', ui.ebno.Value, ui.geo.Value, ui.right.Value));
end

function onInject(src, ~)
fig = ancestor(src, 'figure'); ui = fig.UserData.ui;
queue(fig, struct('type', 'inject', 'scn', ui.threat.Value, 'follow', ui.follow.Value, 'unk', ui.unk.Value));
logLine(fig, sprintf('Inject: %s%s%s.', threatLabel(ui.threat.Value), onOff(ui.follow.Value, ', follows hops'), ...
    onOff(ui.unk.Value, ', class hidden')));
end

function onClear(src, ~)
fig = ancestor(src, 'figure');
queue(fig, struct('type', 'clear'));
logLine(fig, 'Threat switched off.');
end

function onRight(src, ~)
fig = ancestor(src, 'figure'); ui = fig.UserData.ui;
op = strcmp(ui.right.Value, 'operator');
ui.op.Enable = onOff(op, 'on', 'off'); ui.opBtn.Enable = onOff(op, 'on', 'off');
onNew(src, []);
end

function onOperator(src, ~)
fig = ancestor(src, 'figure'); ui = fig.UserData.ui;
queue(fig, struct('type', 'operator', 'a', ui.op.Value));
logLine(fig, sprintf('Operator response: %s.', actLabel(fig.UserData.M.PP.actions{ui.op.Value})));
end

function onScenario(src, ~)
fig = ancestor(src, 'figure'); ui = fig.UserData.ui; sc = fig.UserData.SC(ui.sc.Value);
ui.ebno.Value = ui.ebno.Items{sc.s}; ui.geo.Value = ui.geo.Items{sc.r};
ui.right.Value = 'rule'; ui.op.Enable = 'off'; ui.opBtn.Enable = 'off';
queue(fig, struct('type', 'new', 's', sc.s, 'r', sc.r, 'right', 'rule'));
queue(fig, struct('type', 'inject', 'scn', sc.threat, 'follow', sc.follow, 'unk', sc.unk, 'at', sc.onset));
logLine(fig, sprintf('Scenario: %s (threat at cycle %d).', sc.title, sc.onset));
end

function onShot(src, ~)
fig = ancestor(src, 'figure'); w = fig.UserData.world; U = w.UserData;
U.shot = src.Value; w.UserData = U;
end

function onSpeed(src, ~)
fig = ancestor(src, 'figure'); w = fig.UserData.world; U = w.UserData;
U.tNext = U.tPlay + (U.tNext - U.tPlay) * src.Value / U.cycle_s;
U.cycle_s = src.Value; w.UserData = U;
end

function onPause(src, ~)
fig = ancestor(src, 'figure'); w = fig.UserData.world; U = w.UserData;
U.playing = ~src.Value; w.UserData = U;
src.Text = onOff(src.Value, 'Resume', 'Pause');
end

function f = onSave(src, ~)
fig = ancestor(src, 'figure'); w = fig.UserData.world; U = w.UserData;
R = U.R(U.epStart:end);
if isempty(U.replay), meta = hudMeta(U.M, U.right); else, meta = U.rmeta; end
d = fullfile(fig.UserData.root, 'GUI_Results'); if ~isfolder(d), mkdir(d); end
f = fullfile(d, sprintf('v3d_session_%s.mat', string(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))));
save(f, 'R', 'meta');
logLine(fig, sprintf('Session saved: %s (%d cycles).', f, numel(R)));
end

function onRender(src, ~)
fig = ancestor(src, 'figure');
f = onSave(src, []);
root = fig.UserData.root; M = fig.UserData.M;
logLine(fig, 'Rendering: the console closes and reopens when the video is ready.');
drawnow;
onClose(fig, []);
L = load(f, 'R', 'meta');
meta = L.meta; meta.T = numel(L.R);
[~, nm] = fileparts(f);
out = fullfile(root, 'results', 'viz3d_videos', [nm '.mp4']);
if ~isfolder(fileparts(out)), mkdir(fileparts(out)); end
v3d_render(L.R, meta, out, struct('M', M));
fig2 = v3d_live();
logLine(fig2, sprintf('Video ready: %s', out));
end

function onSnap(src, ~)
fig = ancestor(src, 'figure');
img = fig.UserData.lastImg;
if isempty(img), logLine(fig, 'No frame yet.'); return; end
d = fullfile(fig.UserData.root, 'results', 'viz3d_pictures'); if ~isfolder(d), mkdir(d); end
f = fullfile(d, sprintf('frame_%s.png', string(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))));
imwrite(img, f);
logLine(fig, sprintf('Picture saved: %s', f));
end

function onKey(fig, evt)
ui = fig.UserData.ui;
shots = {'auto', 'overview', 'chase', 'side', 'emitter', 'tactical', 'ground', 'wide'};
switch evt.Key
    case 'space'
        ui.pause.Value = ~ui.pause.Value; onPause(ui.pause, []);
    case 'i'
        if strcmp(ui.inject.Enable, 'on'), onInject(ui.inject, []); end
    case 'o'
        if strcmp(ui.clear.Enable, 'on'), onClear(ui.clear, []); end
    case 'n'
        onNew(ui.newBtn, []);
    otherwise
        d = str2double(evt.Character);
        if ~isnan(d) && d >= 1 && d <= numel(shots)
            ui.shot.Value = shots{d}; onShot(ui.shot, []);
        end
end
end

function onClose(fig, ~)
try
    w = fig.UserData.world;
    close(w); delete(w);
catch
end
delete(fig);
end

%% ===================== Helpers =====================
function [R, meta] = loadReplay(src, M)
% A console episode (ep3d) or a session saved by this console (R, meta).
L = load(src);
if isfield(L, 'ep3d'), [R, meta] = v3d_replay(L.ep3d, M);
else, R = L.R; meta = L.meta; meta.T = numel(R);
end
end

function U = logEvents(U, rec)
ev = [rec.events, strcat('DQN: ', rec.side(1).events), strcat(U.D.meta.right, ': ', rec.side(2).events)];
for i = 1:numel(ev), logLine(U.fig, sprintf('[cycle %d] %s', rec.t, ev{i})); end
end

function logLine(fig, s)
if ~isvalid(fig), return; end
ui = fig.UserData.ui;
v = ui.log.Value; if ischar(v), v = {v}; end
v = [{s}; v(:)]; ui.log.Value = v(1:min(end, 200));
end

function meta = hudMeta(M, right)
meta = struct('title', 'Live operations', 'subtitle', ...
    sprintf('Live session  |  DQN agent (left) vs %s (right)', lower(rightName(right))), 'right', rightName(right), ...
    'frame_s', M.frame_s, 'T', [], 'footer', ['Not to scale: positions illustrative, directions from the link ' ...
    'model  |  measured test frames (flight geometries unseen in training), nominal severity  |  HIT capstone 50076']);
end

function s = rightName(r)
switch r
    case 'none',     s = 'No response';
    case 'operator', s = 'Operator';
    otherwise,       s = 'Rules + escalation';
end
end

function s = threatLabel(t)
parts = strsplit(t, '+');
names = containers.Map({'jamming', 'reactive_jamming', 'sweeping_jammer', 'noise_burst', 'path_loss', 'spoofing', ...
    'antenna_fault', 'benign_interference'}, {'Barrage jammer', 'Reactive jammer', 'Sweeping jammer', 'Noise bursts', ...
    'Path loss', 'Spoofer (fake GCS)', 'Antenna fault', 'Benign interference'});
s = strjoin(cellfun(@(p) names(p), parts, 'UniformOutput', false), ' + ');
end

function s = actLabel(a)
parts = strsplit(a, '+');
names = containers.Map({'no_action', 'channel_switch', 'rate_reduce', 'freq_diversity', 'spatial_diversity', ...
    'power_control', 'fec_interleave'}, {'No action', 'Channel hop', 'Lower rate', 'Two channels', 'MMSE null', ...
    'More power', 'FEC + interleaving'});
s = strjoin(cellfun(@(p) names(p), parts, 'UniformOutput', false), ' + ');
end

function s = onOff(tf, a, b)
if nargin < 3, b = ''; end
if tf, s = a; else, s = b; end
end
