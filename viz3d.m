function viz3d(src)
%VIZ3D  3D replay of a continuous episode recorded by the operator console.
%   viz3d            newest GUI_Results/episode_*.mat
%   viz3d(file)      an episode record saved by demo_gui.m (Continuous episode tab)
%   viz3d(ep3d)      the record struct itself
%
%   Scene: the GCS, the UAV with its two receive antennas, the interferer in the
%   direction it had in the simulated flight geometry, the command link coloured
%   by the measured BER of every cycle, and the receive pattern of the UAV array
%   for the configuration in use: MRC toward the GCS, or MMSE with a null toward
%   the interferer (weights from the line-of-sight geometry). One cycle is one
%   received frame (0.516 ms), so playback is slowed down. Not to scale: the link
%   model has directions, not range.
%
%   No nested functions (same rule as demo_gui.m): static data in fig.UserData,
%   changing state in appdata.

if nargin < 1, src = []; end
ep = loadEpisode(src);
S = sceneGeometry(ep);
c = palette();

fig = uifigure('Name', sprintf('3D episode view - %s @ %g dB', niceName(ep.threat), ep.ebno), ...
    'Position', [40 40 1600 900], 'Color', c.bg);
g = uigridlayout(fig, [1 2]);
g.ColumnWidth = {'1x', 400}; g.Padding = [6 6 6 6]; g.ColumnSpacing = 6; g.BackgroundColor = c.bg;

ax = uiaxes(g); ax.Layout.Column = 1;
ui = buildPanel(g, ep, S, c);
H = buildScene(ax, ep, S, c);

fig.UserData = struct('ep', ep, 'S', S, 'c', c, 'ui', ui, 'ax', ax);
setappdata(fig, 'H', H);
setappdata(fig, 'k', 1);
setappdata(fig, 'playing', false);
setappdata(fig, 'tA', 0);

ui.playBtn.ButtonPushedFcn   = @playPause;
ui.prevBtn.ButtonPushedFcn   = @stepBack;
ui.nextBtn.ButtonPushedFcn   = @stepFwd;
ui.slider.ValueChangedFcn    = @sliderMoved;
ui.policyDD.ValueChangedFcn  = @policyChanged;
ui.camDD.ValueChangedFcn     = @cameraChanged;
ui.patChk.ValueChangedFcn    = @patternToggled;
ui.recBtn.ButtonPushedFcn    = @recordVideo;
fig.CloseRequestFcn          = @closeView;

drawTimeline(fig);
setCamera(fig, 'Overview');
renderCycle(fig, 1);
animate(fig, 0);
end

%% =====================================================================
%% ============================  DATA  =================================
%% =====================================================================

function ep = loadEpisode(src)
    if isstruct(src)
        ep = src;
    else
        if isempty(src)
            d = dir(fullfile('GUI_Results', 'episode_*.mat'));
            if isempty(d)
                error('viz3d:noEpisode', ['No episode record found. Run an episode in demo_gui ' ...
                    '(Continuous episode tab); it saves GUI_Results/episode_*.mat.']);
            end
            [~, i] = max([d.datenum]);
            src = fullfile(d(i).folder, d(i).name);
        end
        L = load(src, 'ep3d');
        if ~isfield(L, 'ep3d'), error('viz3d:badFile', '%s has no ep3d record.', src); end
        ep = L.ep3d;
    end
    ep.floor = 1e-4;
    nP = numel(ep.policies);
    ep.chan = ones(nP, ep.n);
    for i = 1:nP
        ch = 1;
        for k = 1:ep.n
            a = ep.actions{ep.T.cfg(i, k)};
            if ep.T.sw(i, k) && contains(a, 'channel_switch'), ch = ch + 1; end
            ep.chan(i, k) = ch;
        end
    end
end

function S = sceneGeometry(ep)
    % UAV at U, array axis along y. An emitter at broadside angle th is placed so
    % that its direction from the UAV makes exactly that angle with the array
    % broadside plane (sin th = y-component of the unit direction).
    S.U = [0 0 150];
    S.G = placeEmitter(S.U, ep.gcs_aoa_deg, 1100, 40);
    comps = strsplit(ep.threat, '+');
    add = {'jamming', 'reactive_jamming', 'sweeping_jammer', 'noise_burst', 'spoofing', 'benign_interference'};
    S.emit = {}; S.J = zeros(0, 3); S.th = [];
    j = 0;
    for i = 1:numel(comps)
        if any(strcmp(comps{i}, add))
            j = j + 1;
            S.emit{end+1} = comps{i};
            S.th(end+1) = ep.int_aoa_deg(min(j, numel(ep.int_aoa_deg)));
            S.J(end+1, :) = placeEmitter(S.U, S.th(end), 820, 30);
        end
    end
    S.signalSide = intersect(comps, {'path_loss', 'antenna_fault'});
    S.dwl = ep.ant_spacing_wl; S.n_rx = ep.n_rx;
    S.phi = -90:2:90; S.psi = 0:8:360; S.R0 = 110;
    [S.patMRC, S.gMRC] = arrayPattern(S, 'mrc', ep);
    [S.patMMSE, S.gMMSE] = arrayPattern(S, 'mmse', ep);
end

function P = placeEmitter(U, th, L, zmin)
    h = U(3);
    dy = L * sind(th);
    r2 = (L * cosd(th))^2;
    dz = -min(h - zmin, 0.85 * sqrt(r2));
    dx = -sqrt(max(r2 - dz^2, 0));
    P = U + [dx dy dz];
end

function inr = emitterINR(ep, name)
    % Interference-to-noise ratio per antenna [dB], from Eb/N0 and the severity.
    switch name
        case 'spoofing',            inr = ep.ebno - ep.sev.spoof_sir_db;
        case 'benign_interference', inr = ep.ebno + ep.sev.benign_int_db;
        otherwise,                  inr = ep.ebno + ep.sev.jsr_db;
    end
end

function a = steer(S, th)
    a = exp(-1j * 2*pi * S.dwl * (0:S.n_rx-1).' * sind(th));
end

function [P, gfun] = arrayPattern(S, kind, ep)
    % Power pattern |w^H a(phi)|^2 of the UAV array, normalised to its maximum,
    % as a surface of revolution about the array axis (y), centred on the UAV.
    ag = steer(S, ep.gcs_aoa_deg);
    if strcmp(kind, 'mmse') && ~isempty(S.th)
        R = eye(S.n_rx);
        for i = 1:numel(S.th)
            ai = steer(S, S.th(i));
            R = R + 10^(emitterINR(ep, S.emit{i}) / 10) * (ai * ai');
        end
        w = R \ ag;
    else
        w = ag;
    end
    gfun = @(th) abs(w' * steer(S, th)).^2;
    g = arrayfun(gfun, S.phi);
    gn = g / max(g);
    [PH, PS] = meshgrid(S.phi, S.psi);
    GN = repmat(gn, numel(S.psi), 1);
    r = S.R0 * sqrt(GN);
    P.X = S.U(1) - r .* cosd(PH) .* cosd(PS);
    P.Y = S.U(2) + r .* sind(PH);
    P.Z = S.U(3) + r .* cosd(PH) .* sind(PS);
    P.C = max(10*log10(max(GN, 1e-6)), -30);
end

%% =====================================================================
%% ============================  SCENE  ================================
%% =====================================================================

function H = buildScene(ax, ep, S, c)
    hold(ax, 'on');
    ax.Color = c.sky; ax.XColor = 'none'; ax.YColor = 'none'; ax.ZColor = 'none';
    ax.DataAspectRatio = [1 1 1]; ax.Clipping = 'off';
    ax.XLim = [-1250 950]; ax.YLim = [-950 950]; ax.ZLim = [0 480];
    colormap(ax, turbo); clim(ax, [-30 0]);
    title(ax, sprintf('%s  |  Eb/N0 %g dB  |  %s  |  %.0f km/h', niceName(ep.threat), ep.ebno, ep.sev_txt, ep.v_kmh), ...
        'Color', c.dark, 'FontSize', 13);

    [Xg, Yg] = meshgrid(linspace(-1250, 950, 45), linspace(-950, 950, 40));
    surface(ax, Xg, Yg, zeros(size(Xg)), 'FaceColor', c.ground, 'EdgeColor', c.groundEdge, 'EdgeAlpha', 0.35, ...
        'FaceLighting', 'none');
    light(ax, 'Position', [-0.5 -1 1.5], 'Style', 'infinite');

    % GCS
    gg = hgtransform(ax);
    makeBox(gg, [S.G(1) S.G(2) 12], [40 30 24], c.gcsBody);
    mastTop = S.G(3);
    makeCyl(gg, [S.G(1) S.G(2) 24], 2.5, mastTop - 24, c.metal);
    makeSphere(gg, [S.G(1) S.G(2) mastTop], 7, c.gcs);
    H.gcsTip = [S.G(1) S.G(2) mastTop];
    text(ax, S.G(1), S.G(2), mastTop + 45, 'GCS', 'Color', c.dark, 'FontWeight', 'bold', 'FontSize', 13, ...
        'HorizontalAlignment', 'center');

    % UAV
    H.uav = hgtransform(ax);
    H.rotors = buildDrone(H.uav, c.uavBody, c.rotor);
    [H.ant1, H.ant2] = buildAntennas(H.uav, c);
    H.uav.Matrix = makehgtform('translate', S.U) * makehgtform('scale', 1.6);
    H.uavRx = S.U - [0 0 14];
    text(ax, S.U(1), S.U(2), S.U(3) + 55, 'UAV', 'Color', c.dark, 'FontWeight', 'bold', 'FontSize', 13, ...
        'HorizontalAlignment', 'center');
    quiver3(ax, S.U(1) + 40, S.U(2), S.U(3), 150, 0, 0, 0, 'Color', c.dark, 'LineWidth', 2, 'MaxHeadSize', 0.6);
    text(ax, S.U(1) + 200, S.U(2), S.U(3) + 12, sprintf('%.0f km/h, f_D %.0f Hz', ep.v_kmh, ep.fd_hz), ...
        'Color', c.dark, 'FontSize', 10);
    line(ax, [S.U(1) S.U(1)], [S.U(2) - 70 S.U(2) + 70], [S.U(3) S.U(3)] - 14, 'Color', c.dark, ...
        'LineStyle', ':', 'LineWidth', 1);
    text(ax, S.U(1), S.U(2) + 80, S.U(3) - 14, 'array axis', 'Color', c.dark, 'FontSize', 9);

    % receive pattern
    H.pat = surface(ax, S.patMRC.X, S.patMRC.Y, S.patMRC.Z, S.patMRC.C, 'FaceColor', 'interp', ...
        'FaceAlpha', 0.30, 'EdgeColor', 'none', 'FaceLighting', 'none');

    % command link (main, second carrier for frequency diversity) and packets
    Rx = H.uavRx;
    H.link = line(ax, [H.gcsTip(1) Rx(1)], [H.gcsTip(2) Rx(2)], [H.gcsTip(3) Rx(3)], 'Color', c.green, 'LineWidth', 3);
    H.link2 = line(ax, [H.gcsTip(1) Rx(1)], [H.gcsTip(2) Rx(2)] + 14, [H.gcsTip(3) Rx(3)] + 8, 'Color', c.green, ...
        'LineWidth', 2, 'LineStyle', '--', 'Visible', 'off');
    H.pkt = line(ax, nan, nan, nan, 'LineStyle', 'none', 'Marker', 's', 'MarkerSize', 7, ...
        'MarkerFaceColor', c.green, 'MarkerEdgeColor', c.dark);
    mid = (H.gcsTip + Rx) / 2;
    H.linkTxt = text(ax, mid(1), mid(2) - 30, mid(3) + 40, '', 'Color', c.dark, 'FontSize', 11, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center');

    % interferers
    H.jam = struct('beam', {}, 'pulse', {}, 'core', {}, 'label', {}, 'angle', {});
    for i = 1:size(S.J, 1)
        J = S.J(i, :);
        col = emitterColor(S.emit{i}, c);
        if J(3) > 60
            jt = hgtransform(ax);
            buildDrone(jt, c.jamBody, c.rotor);
            jt.Matrix = makehgtform('translate', J) * makehgtform('scale', 1.1);
            core = makeSphere(ax, J - [0 0 8], 6, c.idle);
            kind = 'airborne';
        else
            makeBox(ax, [J(1) J(2) 8], [34 20 16], c.jamBody);
            makeCyl(ax, [J(1) J(2) 16], 2, J(3) - 16, c.metal);
            core = makeSphere(ax, J, 7, c.idle);
            kind = 'ground';
        end
        beam = line(ax, [J(1) Rx(1)], [J(2) Rx(2)], [J(3) Rx(3)], 'Color', col, 'LineWidth', 2, 'Visible', 'off');
        pulse = line(ax, nan, nan, nan, 'LineStyle', 'none', 'Marker', 'o', 'MarkerSize', 8, ...
            'MarkerFaceColor', col, 'MarkerEdgeColor', 'none');
        lbl = text(ax, J(1), J(2), J(3) + 45, sprintf('%s (%s)', upper(niceName(S.emit{i})), kind), ...
            'Color', c.dark, 'FontWeight', 'bold', 'FontSize', 11, 'HorizontalAlignment', 'center');
        dirv = (J - S.U) / norm(J - S.U);
        ang = line(ax, S.U(1) + [0 90*dirv(1)], S.U(2) + [0 90*dirv(2)], S.U(3) + [0 90*dirv(3)], ...
            'Color', col, 'LineStyle', ':', 'LineWidth', 1.5);
        text(ax, S.U(1) + 100*dirv(1), S.U(2) + 100*dirv(2), S.U(3) + 100*dirv(3), ...
            sprintf('%+.0f%s', S.th(i), char(176)), 'Color', col * 0.6, 'FontWeight', 'bold', 'FontSize', 11);
        H.jam(i) = struct('beam', beam, 'pulse', pulse, 'core', core, 'label', lbl, 'angle', ang);
    end
    H.J = S.J;
    gdir = (S.G - S.U) / norm(S.G - S.U);
    line(ax, S.U(1) + [0 90*gdir(1)], S.U(2) + [0 90*gdir(2)], S.U(3) + [0 90*gdir(3)], ...
        'Color', c.gcs, 'LineStyle', ':', 'LineWidth', 1.5);
    hold(ax, 'off');
    ax.Interactions = [rotateInteraction zoomInteraction panInteraction];
end

function rot = buildDrone(parent, bodyCol, rotorCol)
    makeBox(parent, [0 0 0], [12 12 5], bodyCol);
    arms = hgtransform(parent);
    arms.Matrix = makehgtform('zrotate', pi/4);
    makeBox(arms, [0 0 1], [26 2 1.5], bodyCol);
    makeBox(arms, [0 0 1], [2 26 1.5], bodyCol);
    rot = gobjects(1, 4);
    d = [1 1; -1 1; -1 -1; 1 -1] * 9;
    for i = 1:4
        rot(i) = hgtransform(parent);
        [x, y] = pol2cart(linspace(0, 2*pi, 25), 6.5);
        patch(x, y, 0.3 * ones(size(x)), rotorCol, 'Parent', rot(i), 'FaceAlpha', 0.35, 'EdgeColor', 'none');
        makeBox(rot(i), [0 0 0.5], [13 1.2 0.4], rotorCol * 0.6);
        rot(i).UserData = [d(i, :) 3.5];
        rot(i).Matrix = makehgtform('translate', rot(i).UserData);
    end
end

function [a1, a2] = buildAntennas(parent, c)
    for y = [-6 6]
        makeCyl(parent, [0 y -9], 0.5, 6.5, c.metal);
    end
    a1 = makeSphere(parent, [0 -6 -9], 1.3, c.ant);
    a2 = makeSphere(parent, [0 6 -9], 1.3, c.ant);
end

function h = makeBox(parent, ctr, sz, col)
    [X, Y, Z] = ndgrid([-0.5 0.5]);
    V = [X(:) * sz(1) + ctr(1), Y(:) * sz(2) + ctr(2), Z(:) * sz(3) + ctr(3)];
    F = [1 3 7 5; 2 4 8 6; 1 2 6 5; 3 4 8 7; 1 2 4 3; 5 6 8 7];
    h = patch('Parent', parent, 'Vertices', V, 'Faces', F, 'FaceColor', col, 'EdgeColor', 'none', 'FaceLighting', 'gouraud');
end

function h = makeCyl(parent, base, r, len, col)
    [x, y, z] = cylinder(r, 14);
    h = surface(x + base(1), y + base(2), z * len + base(3), 'Parent', parent, 'FaceColor', col, 'EdgeColor', 'none', ...
        'FaceLighting', 'gouraud');
end

function h = makeSphere(parent, ctr, r, col)
    [x, y, z] = sphere(16);
    h = surface(r*x + ctr(1), r*y + ctr(2), r*z + ctr(3), 'Parent', parent, 'FaceColor', col, 'EdgeColor', 'none', ...
        'FaceLighting', 'gouraud');
end

%% =====================================================================
%% ============================  PANEL  ================================
%% =====================================================================

function ui = buildPanel(g, ep, S, c)
    p = uipanel(g, 'BackgroundColor', c.panel, 'BorderType', 'none'); p.Layout.Column = 2;
    q = uigridlayout(p, [16 3]);
    q.RowHeight = {26, 36, 36, 26, 30, 24, 24, 24, 40, 44, 40, '1x', 30, 30, 30, 48};
    q.ColumnWidth = {'1x', '1x', '1x'}; q.Padding = [10 8 10 8]; q.RowSpacing = 4; q.BackgroundColor = c.panel;
    L = @(txt, row, varargin) placeLbl(q, txt, row, c, varargin{:});

    L('3D EPISODE VIEW', 1, 'FontSize', 15, 'FontWeight', 'bold');
    L(sprintf('%s, %s | Eb/N0 %g dB | %.0f km/h (f_D %.0f Hz)', niceName(ep.threat), ep.sev_txt, ep.ebno, ...
        ep.v_kmh, ep.fd_hz), 2, 'FontColor', c.mut, 'WordWrap', 'on');
    if isempty(S.th)
        geo = sprintf('No interferer (signal-side condition) | geometry seed %d', ep.seed_geom);
    else
        geo = sprintf('Interferer %s from the GCS direction | geometry seed %d', ...
            strjoin(arrayfun(@(t) sprintf('%+.0f%s', t, char(176)), S.th, 'UniformOutput', false), ', '), ep.seed_geom);
    end
    L(geo, 3, 'FontColor', c.mut, 'WordWrap', 'on');

    placeLbl(q, 'Policy shown', 4, c, 'FontColor', c.mut);
    ui.policyDD = uidropdown(q, 'Items', upper(ep.policies), 'ItemsData', 1:numel(ep.policies), 'Value', 1, ...
        'Tooltip', 'Which policy of the recorded episode drives the scene. Both saw identical frames.');
    ui.policyDD.Layout.Row = 4; ui.policyDD.Layout.Column = [2 3];

    ui.cycle  = L('', 5, 'FontSize', 13, 'FontWeight', 'bold');
    ui.truth  = L('', 6);
    ui.det    = L('', 7);
    ui.cfg    = L('', 8, 'FontWeight', 'bold');
    ui.link   = L('', 9, 'FontSize', 13, 'FontWeight', 'bold', 'WordWrap', 'on');
    ui.rx     = L('', 10, 'WordWrap', 'on');
    ui.q      = L('', 11, 'FontColor', c.mut, 'FontSize', 10, 'WordWrap', 'on');

    ui.tl = uiaxes(q); ui.tl.Layout.Row = 12; ui.tl.Layout.Column = [1 3];
    ui.tl.Color = c.axBg; ui.tl.XColor = c.mut; ui.tl.YColor = c.mut; ui.tl.GridColor = c.mut;
    ui.tl.FontSize = 9; ui.tl.YScale = 'log'; grid(ui.tl, 'on'); box(ui.tl, 'on');

    ui.prevBtn = mkBtn(q, char(9664), 13, 1, c, 'Previous cycle');
    ui.playBtn = mkBtn(q, 'PLAY', 13, 2, c, 'Play / pause');
    ui.nextBtn = mkBtn(q, char(9654), 13, 3, c, 'Next cycle');
    ui.slider = uislider(q, 'Limits', [1 max(ep.n, 2)], 'Value', 1, 'MajorTicks', [], 'MinorTicks', [], ...
        'Tooltip', 'Jump to a cycle');
    ui.slider.Layout.Row = 14; ui.slider.Layout.Column = [1 3];
    ui.speedDD = uidropdown(q, 'Items', {'0.25 s / cycle', '0.5 s / cycle', '1 s / cycle', '2 s / cycle'}, ...
        'ItemsData', [0.25 0.5 1 2], 'Value', 0.5, 'Tooltip', 'Playback time of one decision cycle');
    ui.speedDD.Layout.Row = 15; ui.speedDD.Layout.Column = 1;
    ui.camDD = uidropdown(q, 'Items', {'Overview', 'UAV close-up', 'Top view', 'From the GCS'}, 'Value', 'Overview', ...
        'Tooltip', 'Camera preset (you can also rotate and zoom with the mouse)');
    ui.camDD.Layout.Row = 15; ui.camDD.Layout.Column = 2;
    ui.patChk = uicheckbox(q, 'Text', 'Rx pattern', 'Value', true, 'FontColor', c.txt, ...
        'Tooltip', 'Show the receive pattern of the two UAV antennas');
    ui.patChk.Layout.Row = 15; ui.patChk.Layout.Column = 3;
    ui.recBtn = mkBtn(q, 'RECORD MP4', 16, 1, c, 'Replays the whole episode and saves it as an MP4 video');
    ui.note = L(sprintf(['Not to scale: the link model has directions, not range. One cycle = one frame ' ...
        '(%.3f ms); playback slowed down.'], 1e3 * ep.frame_s), 16, 'FontColor', c.mut, 'FontSize', 9, 'WordWrap', 'on');
    ui.note.Layout.Column = [2 3];
end

function lbl = placeLbl(q, txt, row, c, varargin)
    lbl = uilabel(q, 'Text', txt, 'FontColor', c.txt, 'FontSize', 11, varargin{:});
    lbl.Layout.Row = row; lbl.Layout.Column = [1 3];
end

function b = mkBtn(q, txt, row, col, c, tip)
    b = uibutton(q, 'Text', txt, 'FontWeight', 'bold', 'BackgroundColor', c.accent, 'FontColor', [0.03 0.06 0.12], ...
        'Tooltip', tip);
    b.Layout.Row = row; b.Layout.Column = col;
end

%% =====================================================================
%% ===========================  RENDER  ================================
%% =====================================================================

function renderCycle(fig, k)
    D = fig.UserData; ep = D.ep; S = D.S; c = D.c; ui = D.ui; H = getappdata(fig, 'H');
    i = ui.policyDD.Value;
    k = max(1, min(ep.n, round(k)));
    setappdata(fig, 'k', k);
    cfg = ep.T.cfg(i, k); act = ep.actions{cfg};
    onset = k > ep.n_pre;
    ber = max(ep.T.ber(i, k), ep.floor); ratio = ber / max(ep.ber_clean, ep.floor);
    [stTxt, stCol] = linkStatus(ratio, onset, c);

    % link
    pw = contains(act, 'power_control'); pl = onset && any(strcmp(S.signalSide, 'path_loss'));
    H.link.Color = stCol; H.link.LineWidth = 3 + 3*pw - 1.8*(pl && ~pw);
    H.link.LineStyle = ternary(pl, '--', '-');
    H.link2.Visible = onoff(contains(act, 'freq_diversity')); H.link2.Color = stCol;
    H.pkt.MarkerFaceColor = stCol;
    H.pkt.Marker = ternary(contains(act, 'fec_interleave'), 'd', 's');
    extra = '';
    if pl, extra = sprintf('  (attenuation %g dB)', ep.sev.path_loss_db); end
    H.linkTxt.String = sprintf('CH %d%s', ep.chan(i, k), extra);

    % interferers
    avoid = contains(act, 'channel_switch') || contains(act, 'freq_diversity');
    for j = 1:numel(H.jam)
        col = emitterColor(S.emit{j}, c);
        H.jam(j).core.FaceColor = ternary(onset, col, c.idle);
        H.jam(j).beam.Visible = onoff(onset);
        H.jam(j).beam.LineStyle = ternary(avoid, ':', '-');
        H.jam(j).beam.LineWidth = ternary(avoid, 1, 2.5);
        H.jam(j).beam.Color = ternary(avoid, 0.5*col + 0.5*[1 1 1], col);
        H.jam(j).pulse.Visible = onoff(onset && ~avoid);
        H.jam(j).label.String = sprintf('%s%s', upper(niceName(S.emit{j})), ...
            ternary(onset, ternary(avoid, ' - off our channel', ' - ACTIVE'), ' - idle'));
    end

    % receiver pattern
    mm = contains(act, 'spatial_diversity');
    P = ternary(mm, S.patMMSE, S.patMRC);
    set(H.pat, 'XData', P.X, 'YData', P.Y, 'ZData', P.Z, 'CData', P.C, 'Visible', onoff(ui.patChk.Value));
    if mm, gf = S.gMMSE; else, gf = S.gMRC; end
    if isempty(S.th)
        rxTxt = ternary(mm, 'Receiver: MMSE combining (no interferer to null)', 'Receiver: MRC, beam toward the GCS');
    else
        rel = 10*log10(max(gf(S.th(1)), 1e-12) / gf(ep.gcs_aoa_deg));
        rxTxt = sprintf('Receiver: %s | gain toward the interferer %.0f dB relative to the GCS', ...
            ternary(mm, 'MMSE, null steered at the interferer', 'MRC, beam toward the GCS'), rel);
    end

    % panel
    nClean = ep.n_pre;
    if onset, ph = sprintf('attack +%d', k - nClean); else, ph = 'clean link'; end
    ui.cycle.Text = sprintf('Cycle %d / %d  (%s)   t = %.2f ms', k, ep.n, ph, 1e3 * k * ep.frame_s);
    ui.truth.Text = ['Real condition:  ' niceName(ep.classes{ep.truth(k)})];
    detTxt = sprintf('Detector:  %s (%.0f%%)', niceName(ep.classes{ep.T.det(i, k)}), 100 * ep.T.conf(i, k));
    if ep.T.unk(i, k), detTxt = [detTxt '  | UNKNOWN flag']; end
    ui.det.Text = detTxt;
    ui.det.FontColor = ternary(ep.T.det(i, k) == ep.truth(k), c.txt, c.amber);
    ui.cfg.Text = sprintf('Configuration:  %s%s', niceName(act), ternary(ep.T.sw(i, k), '   << changed', ''));
    ui.cfg.FontColor = ternary(ep.T.sw(i, k), c.cyan, c.txt);
    ui.link.Text = sprintf('BER %s = %.1fx clean  ->  %s', sciTxt(ep.T.ber(i, k)), ratio, stTxt);
    ui.link.FontColor = stCol;
    ui.rx.Text = rxTxt;
    q = squeeze(ep.T.q(i, k, :));
    if all(isnan(q))
        ui.q.Text = '';
    else
        [qs, o] = sort(q, 'descend'); o = o(isfinite(qs)); o = o(1:min(3, numel(o)));
        ui.q.Text = ['Q-values (top 3): ' strjoin(arrayfun(@(a) sprintf('%s %.2f', niceName(ep.actions{a}), q(a)), ...
            o(:)', 'UniformOutput', false), '  |  ')];
    end
    ui.slider.Value = min(max(k, ui.slider.Limits(1)), ui.slider.Limits(2));
    H.cursor.Value = k;
    setappdata(fig, 'H', H);
end

function animate(fig, tA)
    % Moving parts inside a cycle: rotors, packets on the link, interferer pulses.
    D = fig.UserData; ep = D.ep; S = D.S; ui = D.ui; H = getappdata(fig, 'H');
    k = getappdata(fig, 'k'); i = ui.policyDD.Value;
    onset = k > ep.n_pre;
    for r = 1:numel(H.rotors)
        H.rotors(r).Matrix = makehgtform('translate', H.rotors(r).UserData) * makehgtform('zrotate', 25*tA + r);
    end
    gp = ep.goodput(ep.T.cfg(i, k));
    np = max(2, round(8 * gp));
    s = mod(0.45 * gp * tA + (0:np-1) / np, 1);
    A = H.gcsTip; B = H.uavRx;
    set(H.pkt, 'XData', A(1) + s*(B(1)-A(1)), 'YData', A(2) + s*(B(2)-A(2)), 'ZData', A(3) + s*(B(3)-A(3)));
    for j = 1:numel(H.jam)
        on = onset && emitterOn(S.emit{j}, tA);
        J = H.J(j, :);
        u = mod(0.8 * tA + (0:4) / 5, 1);
        set(H.jam(j).pulse, 'XData', J(1) + u*(B(1)-J(1)), 'YData', J(2) + u*(B(2)-J(2)), ...
            'ZData', J(3) + u*(B(3)-J(3)), 'MarkerSize', 6 + 6*on);
        col = emitterColor(S.emit{j}, D.c);
        H.jam(j).pulse.MarkerFaceColor = ternary(on, col, 0.3*col + 0.7*D.c.sky);
    end
    if onset && any(strcmp(S.signalSide, 'antenna_fault'))
        faulty = mod(tA, 1) < ep.sev.fault_duty;
        H.ant1.FaceColor = ternary(faulty, D.c.red, D.c.ant);
    else
        H.ant1.FaceColor = D.c.ant;
    end
end

function on = emitterOn(name, tA)
    switch name
        case 'sweeping_jammer', on = mod(tA, 2) < 0.30;     % dwells on our channel 15% of the time
        case 'noise_burst',     on = mod(tA, 1) < 0.30;     % bursts, 30% duty
        otherwise,              on = true;
    end
end

function drawTimeline(fig)
    D = fig.UserData; ep = D.ep; c = D.c; ax = D.ui.tl; H = getappdata(fig, 'H');
    i = D.ui.policyDD.Value;
    cla(ax); hold(ax, 'on');
    for j = 1:numel(ep.policies)
        if j == i, continue; end
        semilogy(ax, 1:ep.n, max(ep.T.ber(j, :), ep.floor), '-', 'Color', c.mut, 'LineWidth', 1);
    end
    semilogy(ax, 1:ep.n, max(ep.T.ber(i, :), ep.floor), '-o', 'Color', c.accent, 'MarkerSize', 3, ...
        'MarkerFaceColor', c.accent, 'LineWidth', 1.5);
    yline(ax, 2 * max(ep.ber_clean, ep.floor), '--', 'Color', c.green, 'Label', '2x clean', 'FontSize', 8);
    if ep.n_pre < ep.n
        xline(ax, ep.n_pre + 0.5, '-', 'Color', c.red, 'Label', 'onset', 'FontSize', 8);
    end
    H.cursor = xline(ax, 1, '-', 'Color', c.txt, 'LineWidth', 1.5);
    hold(ax, 'off');
    ax.XLim = [1 max(ep.n, 2)]; ax.YLim = [ep.floor * 0.8, 1];
    title(ax, sprintf('BER per cycle (%s)', upper(ep.policies{i})), 'Color', c.txt, 'FontSize', 10);
    setappdata(fig, 'H', H);
end

function setCamera(fig, mode)
    D = fig.UserData; ax = D.ax; S = D.S;
    ax.CameraTargetMode = 'auto'; ax.CameraPositionMode = 'auto'; ax.CameraViewAngleMode = 'auto';
    switch mode
        case 'UAV close-up'
            ax.CameraTarget = S.U; ax.CameraPosition = S.U + [-330 -380 200]; ax.CameraViewAngle = 34;
        case 'Top view'
            view(ax, 0, 90);
        case 'From the GCS'
            ax.CameraPosition = S.G + [-160 -60 120]; ax.CameraTarget = S.U; ax.CameraViewAngle = 38;
        otherwise
            view(ax, -38, 24);
    end
    ax.CameraUpVector = [0 0 1];
end

%% =====================================================================
%% ==========================  CALLBACKS  ==============================
%% =====================================================================

function playPause(btn, ~)
    fig = ancestor(btn, 'figure');
    if getappdata(fig, 'playing')
        setappdata(fig, 'playing', false);
        return;
    end
    ui = fig.UserData.ui; ep = fig.UserData.ep;
    setappdata(fig, 'playing', true); btn.Text = 'PAUSE';
    k = getappdata(fig, 'k');
    if k >= ep.n, k = 1; end
    nSub = 12;
    while isvalid(fig) && getappdata(fig, 'playing') && k <= ep.n
        renderCycle(fig, k);
        dt = ui.speedDD.Value / nSub;
        for s = 1:nSub
            if ~isvalid(fig) || ~getappdata(fig, 'playing'), break; end
            tA = getappdata(fig, 'tA') + dt;
            setappdata(fig, 'tA', tA);
            animate(fig, tA);
            drawnow limitrate;
            pause(dt);
        end
        k = k + 1;
    end
    if isvalid(fig)
        setappdata(fig, 'playing', false); btn.Text = 'PLAY';
    end
end

function stepBack(btn, ~)
    fig = ancestor(btn, 'figure'); setappdata(fig, 'playing', false);
    renderCycle(fig, getappdata(fig, 'k') - 1); animate(fig, getappdata(fig, 'tA'));
end

function stepFwd(btn, ~)
    fig = ancestor(btn, 'figure'); setappdata(fig, 'playing', false);
    renderCycle(fig, getappdata(fig, 'k') + 1); animate(fig, getappdata(fig, 'tA'));
end

function sliderMoved(sl, ~)
    fig = ancestor(sl, 'figure'); setappdata(fig, 'playing', false);
    renderCycle(fig, sl.Value); animate(fig, getappdata(fig, 'tA'));
end

function policyChanged(dd, ~)
    fig = ancestor(dd, 'figure');
    drawTimeline(fig); renderCycle(fig, getappdata(fig, 'k')); animate(fig, getappdata(fig, 'tA'));
end

function cameraChanged(dd, ~)
    setCamera(ancestor(dd, 'figure'), dd.Value);
end

function patternToggled(chk, ~)
    fig = ancestor(chk, 'figure'); H = getappdata(fig, 'H');
    H.pat.Visible = onoff(chk.Value);
end

function recordVideo(btn, ~)
    fig = ancestor(btn, 'figure'); ep = fig.UserData.ep; ax = fig.UserData.ax;
    setappdata(fig, 'playing', false);
    if ~exist('GUI_Results', 'dir'), mkdir('GUI_Results'); end
    fn = fullfile('GUI_Results', sprintf('episode3d_%s_%gdB_%s.mp4', ep.threat, ep.ebno, datestr(now, 'yyyymmdd_HHMMSS')));
    vw = VideoWriter(fn, 'MPEG-4'); vw.FrameRate = 24; vw.Quality = 90;
    open(vw); cleanup = onCleanup(@() close(vw)); %#ok<NASGU>
    btn.Enable = 'off'; btn.Text = 'RECORDING...';
    nSub = 12; sz = [];
    for k = 1:ep.n
        renderCycle(fig, k);
        for s = 1:nSub
            tA = getappdata(fig, 'tA') + 0.5 / nSub; setappdata(fig, 'tA', tA);
            animate(fig, tA); drawnow;
            img = grabFrame(ax);
            if isempty(sz), sz = size(img); end
            writeVideo(vw, fitFrame(img, sz));
        end
    end
    btn.Enable = 'on'; btn.Text = 'RECORD MP4';
    fig.UserData.ui.q.Text = ['Video saved: ' fn];
end

function img = grabFrame(ax)
    try
        F = getframe(ax); img = F.cdata;
    catch
        tmp = [tempname '.png'];
        exportgraphics(ax, tmp, 'Resolution', 100);
        img = imread(tmp); delete(tmp);
    end
end

function out = fitFrame(img, sz)
    out = zeros(sz, 'uint8');
    r = min(sz(1), size(img, 1)); cc = min(sz(2), size(img, 2));
    out(1:r, 1:cc, :) = img(1:r, 1:cc, 1:3);
end

function closeView(fig, ~)
    setappdata(fig, 'playing', false);
    delete(fig);
end

%% =====================================================================
%% ============================  UTILS  ================================
%% =====================================================================

function [txt, col] = linkStatus(ratio, onset, c)
    if ratio <= 2
        txt = ternary(onset, 'RESTORED', 'NOMINAL'); col = c.green;
    elseif ratio <= 5
        txt = 'MARGINAL'; col = c.amber;
    else
        txt = 'DEGRADED'; col = c.red;
    end
end

function col = emitterColor(name, c)
    switch name
        case 'spoofing',            col = c.orange;
        case 'benign_interference', col = c.purp;
        otherwise,                  col = c.red;
    end
end

function s = sciTxt(x)
    if ~isfinite(x) || x <= 0, s = '0'; else, s = sprintf('%.1e', x); end
end

function s = niceName(x)
    s = strrep(strrep(x, '_', ' '), '+', ' + ');
end

function v = ternary(cond, a, b)
    if cond, v = a; else, v = b; end
end

function s = onoff(tf)
    if tf, s = 'on'; else, s = 'off'; end
end

function c = palette()
    c.bg = [0.055 0.066 0.090]; c.panel = [0.105 0.120 0.160]; c.axBg = [0.072 0.086 0.120];
    c.txt = [0.90 0.92 0.96]; c.mut = [0.62 0.66 0.74]; c.accent = [0.30 0.62 0.98];
    c.green = [0.18 0.72 0.40]; c.amber = [0.95 0.66 0.15]; c.red = [0.88 0.22 0.22];
    c.orange = [0.98 0.52 0.12]; c.purp = [0.60 0.38 0.90]; c.cyan = [0.30 0.80 0.85];
    c.sky = [0.80 0.88 0.96]; c.ground = [0.62 0.70 0.55]; c.groundEdge = [0.50 0.58 0.45];
    c.dark = [0.10 0.12 0.18]; c.metal = [0.55 0.57 0.60]; c.gcs = [0.20 0.45 0.85];
    c.gcsBody = [0.78 0.80 0.84]; c.uavBody = [0.22 0.24 0.28]; c.rotor = [0.35 0.37 0.40];
    c.ant = [0.95 0.85 0.20]; c.jamBody = [0.40 0.18 0.18]; c.idle = [0.55 0.55 0.55];
end
