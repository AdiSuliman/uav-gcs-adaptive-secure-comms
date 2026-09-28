function out = v3d_render(R, meta, out, opts)
%V3D_RENDER  Render an episode of the 3D view to MP4 (D57).
%   out = v3d_render(R, meta, out, opts)
%   R     cycle records (v3d_engine 'script', a recorded live session, or v3d_replay)
%   meta  title, subtitle, right (label of side 2), frame_s, T, footer (v3d_hud)
%   opts  cycle_s (playback seconds per decision cycle, 1.2), fps (30), intro
%         (s, 3), outro (s, 5), shot ('auto'), M (v3d_engine 'load' output)
%
%   Two identical arenas in Unreal (DQN and the comparison policy), one camera
%   each, composited side by side with the data panels, title and end cards.
if nargin < 4, opts = struct(); end
opts = defaults(opts, struct('cycle_s', 1.2, 'fps', 30, 'intro', 3, 'outro', 5, 'shot', 'auto', 'warm', 90));
if ~isfield(opts, 'M'), opts.M = v3d_engine('load'); end
if ~isfield(meta, 'T') || isempty(meta.T), meta.T = numel(R); end
fps = opts.fps;
nPlay = ceil(numel(R) * opts.cycle_s * fps);

vw = VideoWriter(out, 'MPEG-4'); vw.FrameRate = fps; vw.Quality = 95;
open(vw);
cleanupV = onCleanup(@() close(vw));
card = v3d_hud('card', meta, {});
for i = 1:round(opts.intro * fps), writeVideo(vw, card); end

world = sim3d.World(Scene='EmptyGrass', Output=@renderOutput, Update=@renderUpdate);
try world.GraphicsQuality = "epic"; catch, end
S = v3d_player('build', world, opts.M, struct('sz', [540 960], 'hfov', 62));
S.cycle_s = opts.cycle_s;
U = struct('S', S, 'D', v3d_hud('init', meta), 'R', R, 'vw', vw, 'k', 0, 'warm', opts.warm, ...
    'n', nPlay, 'fps', fps, 'cycle_s', opts.cycle_s, 'shot', opts.shot, 'cam', [], 'err', '', 'kc', 1, 'frac', 0);
world.UserData = U;
total = (opts.warm + nPlay + 2) / fps;
run(world, 1 / fps, total);
t0 = tic;
try wait(world); catch, end
while world.SimulationTime < total - 1.5 / fps && toc(t0) < 3600, pause(0.2); end
err = world.UserData.err;
close(world); delete(world);
if ~isempty(err), warning('v3d_render: %s', err); end

sc = R(end).side;
lines = {sprintf('DQN agent:  restored %s of the cycles after the threat, %s, %d changes', pct(sc(1).score), ...
    recTxt(sc(1).score), sc(1).score.switches), ...
    sprintf('%s:  restored %s, %s, %d changes', meta.right, pct(sc(2).score), recTxt(sc(2).score), sc(2).score.switches), ...
    '', 'One episode on a test flight geometry the agent never trained on.', ...
    'Test-set statistics over all episodes are in the project report.'};
endCard = v3d_hud('card', meta, lines);
for i = 1:round(opts.outro * fps), writeVideo(vw, endCard); end
clear cleanupV
fprintf('Rendered %s (%d cycles)\n', out, numel(R));
end

%% ===================== Callbacks =====================
function renderOutput(world, varargin)
U = world.UserData;
try
    U.k = U.k + 1;
    i = U.k - U.warm;
    t = max(i - 1, 0) / U.fps;
    kc = min(floor(t / U.cycle_s) + 1, numel(U.R));
    frac = mod(t, U.cycle_s) / U.cycle_s;
    [U.S, U.cam] = v3d_player('show', U.S, U.R, kc, t, frac, U.shot);
    U.kc = kc; U.frac = frac;
catch e
    if isempty(U.err), U.err = sprintf('output step %d: %s', U.k, e.message); end
end
world.UserData = U;
end

function renderUpdate(world, varargin)
U = world.UserData;
i = U.k - U.warm;
if i < 1 || i > U.n, return; end
try
    imA = read(U.S.cam{1}); imB = read(U.S.cam{2});
    img = v3d_hud('frame', U.D, imA, imB, U.R, U.kc, U.cam, struct('tcyc', U.frac));
    writeVideo(U.vw, img);
catch e
    if isempty(U.err), U.err = sprintf('update step %d: %s', U.k, e.message); world.UserData = U; end
end
end

%% ===================== Helpers =====================
function o = defaults(o, d)
f = fieldnames(d);
for i = 1:numel(f), if ~isfield(o, f{i}), o.(f{i}) = d.(f{i}); end, end
end

function s = pct(sc)
if sc.n == 0, s = '-'; else, s = sprintf('%.0f%%', 100 * sc.restored / sc.n); end
end

function s = recTxt(sc)
if isnan(sc.t_rec), s = 'never recovered for 3 cycles in a row'; else, s = sprintf('recovered after %d cycles', sc.t_rec); end
end
