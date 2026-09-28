function varargout = v3d_hud(cmd, varargin)
%V3D_HUD  Composited frame of the 3D view: two camera views and the data panels (D57).
%   D = v3d_hud('init', meta)            static layer and layout (1920 x 1080)
%   img = v3d_hud('frame', D, imA, imB, R, k, cam, extra)
%       R: cycle records so far (v3d_engine), k: records shown, cam: camera
%       poses (for callouts), extra: tcyc (fraction of the current cycle),
%       window (cycles on the time axis), notice (text on the views)
%   img = v3d_hud('card', meta, lines)   title or end card
%
%   meta: title, subtitle, right (label of side 2), frame_s, T (episode
%   length, [] = rolling window), footer.
%   Everything shown comes from the records; nothing is drawn that the model
%   did not compute.
switch cmd
    case 'init',  varargout{1} = init(varargin{:});
    case 'frame', varargout{1} = frame(varargin{:});
    case 'card',  varargout{1} = card(varargin{:});
    otherwise, error('v3d_hud: unknown command %s', cmd);
end
end

%% ===================== Layout =====================
function D = init(meta)
D.meta = meta;
D.W = 1920; D.H = 1080;
D.c = colors();
D.viewA = [0 64 958 540]; D.viewB = [962 64 958 540];      % [x y w h]
D.chart = [70 650 690 220];
D.phase = [16 900 744 132];
D.det = [776 612 400 420];
D.qv = [1192 612 320 420];
D.geo = [1528 612 376 420];
D.cls = {'clean', 'jammer', 'noise bursts', 'reactive jammer', 'path loss', 'spoofer', 'antenna fault', ...
    'benign interf.', 'sweeping jammer'};
D.phases = {'CLEAN', 'THREAT', 'DETECTED', 'CONFIRMED', 'RESPONDING', 'RESTORED'};
D.pkeys = {'clean', 'threat', 'detected', 'confirmed', 'acting', 'restored'};

I = repmat(reshape(uint8(D.c.bg), 1, 1, 3), D.H, D.W);
panels = [16 612 744 424; D.det; D.qv; D.geo];
I = insertShape(I, 'FilledRectangle', panels, Color=D.c.panel, Opacity=1);
I = insertShape(I, 'Rectangle', panels, Color=D.c.edge, LineWidth=1);
I = insertText(I, [24 8], 'UAV COMMAND LINK UNDER ELECTRONIC ATTACK', Font='Bahnschrift', FontSize=26, ...
    TextColor='white', BoxOpacity=0);
I = insertText(I, [24 38], meta.subtitle, Font='Segoe UI', FontSize=15, TextColor=D.c.muted, BoxOpacity=0);
ttl = {'LINK QUALITY  (bit errors relative to a clean link)', 'WHAT THE DETECTOR SEES  (DQN side)', ...
    'AGENT''S VALUE OF EACH RESPONSE', 'WHERE THE INTERFERER IS'};
pos = [26 618; D.det(1) + 10, 618; D.qv(1) + 10, 618; D.geo(1) + 10, 618];
I = insertText(I, pos, ttl, Font='Segoe UI Semibold', FontSize=14, TextColor=D.c.title, BoxOpacity=0);
% chart axes: log scale 1x..1000x
ys = [1 2 5 10 100 1000];
for v = ys
    y = chartY(D, v);
    I = insertShape(I, 'Line', [D.chart(1) y D.chart(1) + D.chart(3) y], Color=D.c.grid, LineWidth=1);
end
I = insertText(I, [D.chart(1) - 52 * ones(numel(ys), 1), arrayfun(@(v) chartY(D, v), ys)' - 9], ...
    arrayfun(@(v) sprintf('%gx', v), ys, 'UniformOutput', false), Font='Segoe UI', FontSize=12, ...
    TextColor=D.c.muted, BoxOpacity=0);
I = insertShape(I, 'FilledRectangle', [D.chart(1), chartY(D, 2), D.chart(3), chartY(D, 1) - chartY(D, 2)], ...
    Color=D.c.okDim, Opacity=0.35);
% detector class labels
for k = 1:9
    I = insertText(I, [D.det(1) + 12, detY(D, k) - 2], D.cls{k}, Font='Segoe UI', FontSize=13, ...
        TextColor=D.c.text, BoxOpacity=0);
end
% geometry gauge: zones by angle from the GCS direction
g = gauge(D);
zones = {[0 20], D.c.lost; [20 45], D.c.warn; [45 90], D.c.ok};
for z = 1:3
    for sgn = [-1 1]
        a = linspace(zones{z, 1}(1), zones{z, 1}(2), 16) * sgn;
        pts = [g.cx + g.r * sind(a); g.cy - g.r * cosd(a)];
        pts2 = [g.cx + (g.r - 16) * sind(fliplr(a)); g.cy - (g.r - 16) * cosd(fliplr(a))];
        I = insertShape(I, 'FilledPolygon', reshape([pts, pts2], 1, []), Color=zones{z, 2}, Opacity=0.8);
    end
end
I = insertText(I, [g.cx - 36, g.cy - g.r - 34], 'GCS 0', Font='Segoe UI', FontSize=13, TextColor='white', BoxOpacity=0);
I = insertText(I, [g.cx - g.r - 30, g.cy + 4; g.cx + g.r - 12, g.cy + 4], {'-90', '+90'}, Font='Segoe UI', ...
    FontSize=12, TextColor=D.c.muted, BoxOpacity=0);
% scoreboard header
I = insertText(I, [D.geo(1) + 14, 906; D.geo(1) + 200, 906; D.geo(1) + 290, 906], ...
    {'after the threat', 'DQN', shortName(meta.right)}, Font='Segoe UI Semibold', FontSize=13, ...
    TextColor=[D.c.muted; D.c.a; D.c.b], BoxOpacity=0);
I = insertText(I, [D.geo(1) + 14 * ones(4, 1), (932:24:1004)'], ...
    {'restored cycles', 'time to recover', 'changes', 'needless changes'}, Font='Segoe UI', FontSize=13, ...
    TextColor=D.c.text, BoxOpacity=0);
I = insertText(I, [24 1046], meta.footer, Font='Segoe UI', FontSize=13, TextColor=D.c.muted, BoxOpacity=0);
D.bg = I;
end

%% ===================== Frame =====================
function I = frame(D, imA, imB, R, k, cam, extra)
c = D.c; m = D.meta;
I = D.bg;
I(D.viewA(2) + (1:540), D.viewA(1) + (1:958), :) = fitView(imA, 540, 958);
I(D.viewB(2) + (1:540), D.viewB(1) + (1:958), :) = fitView(imB, 540, 958);
if k < 1
    if isfield(extra, 'notice') && ~isempty(extra.notice)
        I = insertText(I, [D.W / 2 - 250, 300], extra.notice, Font='Segoe UI Semibold', FontSize=22, ...
            TextColor='white', BoxColor='black', BoxOpacity=0.5);
    end
    return;
end
r = R(k);
sA = r.side(1); sB = r.side(2);

% header right
if isnan(r.speed), sp = ''; else, sp = sprintf('  |  UAV %.0f km/h', r.speed); end
if isempty(m.T), cyc = sprintf('cycle %d', r.t); else, cyc = sprintf('cycle %d / %d', r.t, m.T); end
thr = 'clean link'; if r.active, thr = threatText(r.threat); end
I = insertText(I, [1300 10; 1300 38], {sprintf('Eb/N0 %g dB%s  |  %s', r.ebno, sp, cyc), ...
    sprintf('threat: %s   |   1 cycle = 1 frame = %.3f ms, playback slowed', thr, 1000 * m.frame_s)}, ...
    Font='Segoe UI Semibold', FontSize=15, TextColor=[255 255 255; 158 173 194], BoxOpacity=0);

% view chips
I = viewChips(I, D, D.viewA, 'DQN AGENT', c.a, sA);
I = viewChips(I, D, D.viewB, upper(m.right), c.b, sB);
% callouts near the UAV in each view
for s = 1:2
    ev = lastEvent(R, k, s);
    if ~isempty(ev) && ~isempty(cam)
        if s == 1, vw = D.viewA; else, vw = D.viewB; end
        p = project(cam(s), cam(s).uav, [vw(3) vw(4)]);
        if ~isempty(p)
            p = p + vw(1:2);
            bx = min(max(p(1) + 40, vw(1) + 10), vw(1) + vw(3) - 420);
            by = min(max(p(2) - 90, vw(2) + 50), vw(2) + vw(4) - 80);
            I = insertShape(I, 'Line', [p(1) p(2) bx + 6 by + 34], Color='white', LineWidth=2);
            I = insertText(I, [bx by], wrapText(ev, 36), Font='Segoe UI Semibold', FontSize=18, ...
                TextColor='white', BoxColor=[13 18 26], BoxOpacity=0.72);
        end
    end
end
if isfield(extra, 'notice') && ~isempty(extra.notice)
    I = insertText(I, [D.W / 2 - 260, 90], extra.notice, Font='Segoe UI Semibold', FontSize=18, ...
        TextColor='white', BoxColor=[178 26 26], BoxOpacity=0.75);
end

% link-quality chart
if isempty(m.T), w = extra.window; t1 = max(1, k - w + 1); cyc = t1:k; span = w;
else, cyc = 1:k; span = m.T; t1 = 1;
end
xf = @(t) D.chart(1) + (t - t1 + 0.5) / span * D.chart(3);
on = find([R(cyc).active], 1);
if ~isempty(on)
    x = xf(cyc(on) - 0.5);
    I = insertShape(I, 'Line', [x D.chart(2) x D.chart(2) + D.chart(4)], Color=c.lostRGB, LineWidth=2);
    I = insertText(I, [x + 6, D.chart(2) + 4], 'threat on', Font='Segoe UI Semibold', FontSize=12, TextColor=c.lostRGB, BoxOpacity=0);
end
for s = [2 1]
    ratio = arrayfun(@(q) q.side(s).ratio, R(cyc));
    y = chartY(D, max(min(ratio, 1000), 1));
    x = xf(cyc);
    if s == 1, col = c.a; else, col = c.b; end
    if numel(x) > 1
        xx = reshape([x; x], 1, []); xx = xx(2:end); yy = reshape([y; y], 1, []); yy = yy(1:end - 1);
        I = insertShape(I, 'Line', reshape([xx; yy], 1, []), Color=col, LineWidth=3);
    end
    sw = find(arrayfun(@(q) q.side(s).switched, R(cyc)));
    if ~isempty(sw)
        tri = arrayfun(@(j) [x(j) - 6, D.chart(2) + D.chart(4) + 2 + 8 * (s - 1), x(j) + 6, ...
            D.chart(2) + D.chart(4) + 2 + 8 * (s - 1), x(j), D.chart(2) + D.chart(4) - 8 + 8 * (s - 1)], sw, ...
            'UniformOutput', false);
        I = insertShape(I, 'FilledPolygon', vertcat(tri{:}), Color=col, Opacity=1);
    end
end

% phase bars
I = phaseRow(I, D, 1, sA, c.a);
I = phaseRow(I, D, 2, sB, c.b);

% detector bars (DQN side)
p = sA.probs;
bars = zeros(9, 4); cols = repmat(c.bar, 9, 1);
[~, top] = max(p);
for j = 1:9
    bars(j, :) = [D.det(1) + 160, detY(D, j), max(1, round(220 * p(j))), 16];
    if j == top && ~sA.unknown, cols(j, :) = c.a; end
end
I = insertShape(I, 'FilledRectangle', bars, Color=cols, Opacity=1);
flag = {};
if sA.unknown, flag{end + 1} = 'UNKNOWN SIGNAL: class hidden, acting on link quality'; end
if sA.confirmed, flag{end + 1} = 'ALARM CONFIRMED (2 of 2): a response is allowed';
elseif r.active && sA.tConf <= 0, flag{end + 1} = 'alarm not confirmed yet: no change allowed';
end
if ~isempty(flag)
    I = insertText(I, [D.det(1) + 12 * ones(numel(flag), 1), 960 + 26 * (0:numel(flag) - 1)'], flag, ...
        Font='Segoe UI Semibold', FontSize=13, TextColor=[255 217 102], BoxOpacity=0);
end

% Q-values (DQN)
if ~isempty(sA.q)
    q = sA.q; ok = isfinite(q);
    [qs, ord] = sort(q(ok), 'descend'); idx = find(ok); idx = idx(ord);
    n = min(8, numel(idx));
    if n > 0
        lo = min(qs(1:n)); hi = qs(1);
        nb = zeros(n, 4); cq = repmat(c.bar, n, 1); lbl = cell(n, 1);
        for j = 1:n
            f = (qs(j) - lo) / max(hi - lo, 1e-9);
            nb(j, :) = [D.qv(1) + 12, 652 + 44 * (j - 1) + 20, max(4, round(20 + 270 * f)), 14];
            if idx(j) == sA.cfg, cq(j, :) = c.a; end
            lbl{j} = actShort(r, idx(j));
        end
        I = insertShape(I, 'FilledRectangle', nb, Color=cq, Opacity=1);
        I = insertText(I, [D.qv(1) + 12 * ones(n, 1), 652 + 44 * (0:n - 1)'], lbl, Font='Segoe UI Semibold', FontSize=13, ...
            TextColor=D.c.text, BoxOpacity=0);
    end
    if numel(idx) < numel(q)
        I = insertText(I, [D.qv(1) + 12, 1000], 'shield: other responses blocked until an alarm is confirmed', ...
            Font='Segoe UI Semibold', FontSize=12, TextColor=D.c.muted, BoxOpacity=0);
    end
else
    I = insertText(I, [D.qv(1) + 12, 660], 'shield: no change allowed yet', Font='Segoe UI Semibold', FontSize=13, ...
        TextColor=D.c.muted, BoxOpacity=0);
end

% geometry gauge
g = gauge(D);
if ~isempty(r.th)
    for j = 1:numel(r.th)
        a = r.th(j);
        pts = [g.cx, g.cy, g.cx + (g.r + 8) * sind(a), g.cy - (g.r + 8) * cosd(a)];
        I = insertShape(I, 'Line', pts, Color='white', LineWidth=3);
        I = insertShape(I, 'FilledCircle', [pts(3) pts(4) 8], Color=c.lostRGB, Opacity=1);
    end
    a = abs(r.th(1));
    if a < 20, txt = sprintf('%+.0f deg: almost the GCS direction, a null would cut the GCS too', r.th(1));
    elseif a < 45, txt = sprintf('%+.0f deg: close to the GCS direction, a null costs signal', r.th(1));
    else, txt = sprintf('%+.0f deg: far from the GCS direction, the antennas can null it', r.th(1));
    end
    I = insertText(I, [D.geo(1) + 14, g.cy + 34], wrapText(txt, 46), Font='Segoe UI Semibold', FontSize=13, ...
        TextColor='white', BoxOpacity=0);
else
    I = insertText(I, [D.geo(1) + 14, g.cy + 34], 'no interferer: nothing to null', Font='Segoe UI Semibold', ...
        FontSize=13, TextColor=D.c.muted, BoxOpacity=0);
end
I = insertShape(I, 'FilledCircle', [g.cx g.cy 6], Color='white', Opacity=1);

% scoreboard
vals = cell(4, 2);
for s = 1:2
    sc = r.side(s).score;
    if sc.n == 0, vals(:, s) = {'-'}; continue; end
    vals{1, s} = sprintf('%.0f%%', 100 * sc.restored / sc.n);
    if isnan(sc.t_rec), vals{2, s} = '-'; else, vals{2, s} = sprintf('%d cyc', sc.t_rec); end
    vals{3, s} = sprintf('%d', sc.switches);
    vals{4, s} = sprintf('%d', sc.false_sw);
end
I = insertText(I, [(D.geo(1) + 200) * ones(4, 1), (932:24:1004)'; (D.geo(1) + 290) * ones(4, 1), (932:24:1004)'], ...
    [vals(:, 1); vals(:, 2)], Font='Segoe UI Semibold', FontSize=13, TextColor=[repmat(c.a, 4, 1); repmat(c.b, 4, 1)], ...
    BoxOpacity=0);
end

%% ===================== Cards =====================
function I = card(meta, lines)
c = colors();
I = repmat(reshape(uint8(c.bg), 1, 1, 3), 1080, 1920);
I = insertShape(I, 'FilledRectangle', [0 470 1920 4], Color=c.a, Opacity=1);
I = insertText(I, [160 300], meta.title, Font='Bahnschrift', FontSize=54, TextColor='white', BoxOpacity=0);
I = insertText(I, [160 390], meta.subtitle, Font='Segoe UI', FontSize=26, TextColor=c.muted, BoxOpacity=0);
if ~isempty(lines)
    I = insertText(I, [160 * ones(numel(lines), 1), 520 + 48 * (0:numel(lines) - 1)'], lines, Font='Segoe UI', ...
        FontSize=26, TextColor='white', BoxOpacity=0);
end
I = insertText(I, [160 1000], meta.footer, Font='Segoe UI', FontSize=16, TextColor=c.muted, BoxOpacity=0);
end

%% ===================== Helpers =====================
function I = viewChips(I, D, vw, name, col, s)
c = D.c;
I = insertShape(I, 'FilledRectangle', [vw(1) + 12, vw(2) + 12, 8, 34], Color=col, Opacity=1);
I = insertText(I, [vw(1) + 24, vw(2) + 12], name, Font='Segoe UI Semibold', FontSize=18, TextColor='white', ...
    BoxColor=[10 13 18], BoxOpacity=0.6);
switch s.status
    case 'ok',       t = 'LINK OK'; bc = c.okRGB;
    case 'marginal', t = 'LINK DEGRADED'; bc = c.warnRGB;
    otherwise,       t = 'LINK FAILING'; bc = c.lostRGB;
end
if s.ratio < 1.05, t = sprintf('%s   clean-link errors', t);
else, t = sprintf('%s   %.3gx clean errors (%.2f%% bits)', t, s.ratio, 100 * s.ber);
end
I = insertText(I, [vw(1) + vw(3) - 12 - 11 * strlength(t), vw(2) + 12], t, Font='Segoe UI Semibold', FontSize=17, ...
    TextColor='white', BoxColor=bc, BoxOpacity=0.8);
I = insertText(I, [vw(1) + 12, vw(2) + vw(4) - 46], ['Response: ' respText(s.act)], Font='Segoe UI', FontSize=17, ...
    TextColor='white', BoxColor=[10 13 18], BoxOpacity=0.6);
end

function I = phaseRow(I, D, row, s, col)
c = D.c;
y = D.phase(2) + 10 + (row - 1) * 56;
w = floor((D.phase(3) - 20) / 6);
cur = find(strcmp(D.pkeys, s.phase), 1);
rect = zeros(6, 4); cc = repmat(c.bar, 6, 1);
for j = 1:6
    rect(j, :) = [D.phase(1) + 10 + (j - 1) * w, y, w - 4, 26];
    if j <= cur, cc(j, :) = 0.45 * col + 25; end
    if j == cur, cc(j, :) = col; end
end
I = insertShape(I, 'FilledRectangle', rect, Color=cc, Opacity=1);
I = insertText(I, [rect(:, 1) + 6, rect(:, 2) + 3], D.phases', Font='Segoe UI Semibold', FontSize=11, ...
    TextColor=repmat([13 13 20], 6, 1), BoxOpacity=0);
tt = {};
if s.tDet > 0, tt{end + 1} = sprintf('detected +%d', s.tDet); end
if s.tAct > 0, tt{end + 1} = sprintf('first response +%d', s.tAct); end
if s.tRec > 0, tt{end + 1} = sprintf('restored +%d cycles', s.tRec); end
if ~isempty(tt)
    I = insertText(I, [D.phase(1) + 10, y + 28], strjoin(tt, '   |   '), Font='Segoe UI', FontSize=12, ...
        TextColor=c.muted, BoxOpacity=0);
end
end

function ev = lastEvent(R, k, s)
ev = '';
for j = k:-1:max(1, k - 2)
    e = R(j).side(s).events;
    if ~isempty(e), ev = e{end}; return; end
    if s == 1 && ~isempty(R(j).events), ev = R(j).events{end}; return; end
end
end

function p = project(cam, X, sz)
% Pixel position of world point X in a camera view (x forward, y right, z up).
y = cam.rot(3); pch = cam.rot(2);
f = [cos(pch) * cos(y), cos(pch) * sin(y), sin(pch)];
rt = [-sin(y), cos(y), 0];
up = [-sin(pch) * cos(y), -sin(pch) * sin(y), cos(pch)];
d = X - cam.pos;
z = dot(d, f);
if z < 1, p = []; return; end
fp = (sz(1) / 2) / tand(cam.hfov / 2);
p = [sz(1) / 2 + fp * dot(d, rt) / z, sz(2) / 2 - fp * dot(d, up) / z];
if any(p < 0) || p(1) > sz(1) || p(2) > sz(2), p = []; end
end

function y = chartY(D, v)
y = D.chart(2) + D.chart(4) * (1 - log10(v) / 3);
end

function y = detY(~, k)
y = 652 + (k - 1) * 32;
end

function g = gauge(D)
g.cx = D.geo(1) + D.geo(3) / 2; g.cy = 790; g.r = 120;
end

function out = fitView(im, h, w)
if isempty(im), out = zeros(h, w, 3, 'uint8'); return; end
if size(im, 1) ~= h || size(im, 2) ~= w, im = imresize(im, [h w]); end
out = im;
end

function s = wrapText(s, n)
words = strsplit(s, ' '); lines = {''};
for i = 1:numel(words)
    if strlength(lines{end}) + strlength(words{i}) + 1 > n, lines{end + 1} = words{i}; %#ok<AGROW>
    elseif isempty(lines{end}), lines{end} = words{i};
    else, lines{end} = [lines{end} ' ' words{i}];
    end
end
s = strjoin(lines, newline);
end

function s = shortName(n)
switch lower(n)
    case 'rules + escalation', s = 'RULES';
    case 'no response',        s = 'NONE';
    case 'operator',           s = 'OPERATOR';
    otherwise,                 s = upper(n);
end
end

function s = threatText(t)
parts = strsplit(t, '+');
names = containers.Map({'jamming', 'reactive_jamming', 'sweeping_jammer', 'noise_burst', 'path_loss', 'spoofing', ...
    'antenna_fault', 'benign_interference', 'none'}, {'barrage jammer', 'reactive jammer', 'sweeping jammer', ...
    'noise bursts', 'path loss', 'spoofer', 'antenna fault', 'benign interference', 'clean link'});
s = strjoin(cellfun(@(p) names(p), parts, 'UniformOutput', false), ' + ');
end

function s = respText(a)
parts = strsplit(a, '+');
t = cell(size(parts));
for i = 1:numel(parts)
    switch parts{i}
        case 'no_action',         t{i} = 'none (normal operation)';
        case 'channel_switch',    t{i} = 'hop to a clean channel';
        case 'rate_reduce',       t{i} = 'slower data rate';
        case 'freq_diversity',    t{i} = 'two channels at once';
        case 'spatial_diversity', t{i} = 'antennas null the interferer (MMSE)';
        case 'power_control',     t{i} = 'more transmit power';
        case 'fec_interleave',    t{i} = 'error-correcting code';
        otherwise,                t{i} = parts{i};
    end
end
s = strjoin(t, ' + ');
end

function s = actShort(~, a)
names = {'no action', 'channel hop', 'lower rate', 'two channels', 'MMSE null', 'more power', 'FEC', ...
    'hop + lower rate', 'hop + power', 'hop + FEC', 'two ch + lower rate', 'two ch + power', 'two ch + FEC', ...
    'MMSE + lower rate', 'MMSE + power', 'MMSE + FEC', 'lower rate + power'};
if a <= numel(names), s = names{a}; else, s = sprintf('config %d', a); end
end

function c = colors()
c.bg = [14 18 26]; c.panel = [22 28 38]; c.edge = [44 54 70]; c.grid = [48 58 74];
c.title = [184 204 230]; c.text = [220 230 240]; c.muted = [140 158 178];
c.a = [64 199 255]; c.b = [255 158 51]; c.bar = [61 74 92];
c.okRGB = [31 158 82]; c.warnRGB = [217 140 20]; c.lostRGB = [217 46 36];
c.ok = [40 170 90]; c.warn = [220 150 30]; c.lost = [210 50 40]; c.okDim = [30 120 70];
end
