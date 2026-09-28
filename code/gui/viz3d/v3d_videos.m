%% V3D_VIDEOS - Render the defense scenarios of the 3D view to MP4 (D57)
% Run from the repository root (startup.m puts code/ on the path):  v3d_videos
% Set ONLY to a list of scenario ids to render a subset. About 4 minutes per
% scenario on the reference PC (RTX 4070).
% Output: results/viz3d_videos/<id>.mp4, showreel.mp4 (all scenarios in a row)
% and scenarios.txt (the geometries the fixed rule picked, and the outcomes)

if ~exist('ONLY', 'var'), ONLY = {}; end
root = project_root();
OUT = fullfile(root, 'results', 'viz3d_videos');
if ~isfolder(OUT), mkdir(OUT); end
M = v3d_engine('load');
SC = v3d_scenarios(M);
fid = fopen(fullfile(OUT, 'scenarios.txt'), 'w');
fprintf(fid, 'Defense scenarios (test pools; geometry = test sub-run whose first interferer direction is nearest the target)\n\n');
for i = 1:numel(SC)
    sc = SC(i);
    if ~isempty(ONLY) && ~any(strcmp(ONLY, sc.id)), continue; end
    R = v3d_engine('script', M, sc);
    meta = struct('title', sc.title, ...
        'subtitle', sprintf('%s  |  Eb/N0 %g dB  |  DQN agent (left) vs rules + escalation (right)', ...
        threatLabel(sc.threat), M.PP.ebno(sc.s)), ...
        'right', 'Rules + escalation', 'frame_s', M.frame_s, 'T', sc.T, ...
        'footer', ['Not to scale: positions illustrative, directions from the link model  |  measured test ' ...
        'frames (flight geometries unseen in training), nominal severity  |  HIT capstone 50076']);
    f = fullfile(OUT, [sc.id '.mp4']);
    v3d_render(R, meta, f, struct('M', M));
    sA = R(end).side(1).score; sB = R(end).side(2).score;
    fprintf(fid, '%-11s %-22s Eb/N0 %2g dB  geometry %d  first interferer %+6.1f deg  | restored DQN %d/%d, rules %d/%d\n', ...
        sc.id, sc.threat, M.PP.ebno(sc.s), sc.r, sc.th, sA.restored, sA.n, sB.restored, sB.n);
end
fclose(fid);

% Showreel: every rendered scenario in the order of v3d_scenarios.m
files = fullfile(OUT, strcat({SC.id}, '.mp4'));
files = files(cellfun(@isfile, files));
if numel(files) > 1
    vw = VideoWriter(fullfile(OUT, 'showreel.mp4'), 'MPEG-4'); vw.FrameRate = 30; vw.Quality = 95;
    open(vw);
    for i = 1:numel(files)
        vr = VideoReader(files{i});
        while hasFrame(vr), writeVideo(vw, readFrame(vr)); end
    end
    close(vw);
    fprintf('Showreel: %d scenarios\n', numel(files));
end

function s = threatLabel(t)
s = strrep(strrep(t, '_', ' '), '+', ' + ');
end
