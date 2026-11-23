function capture_gui(parts, outdir)
%CAPTURE_GUI  Drives the operator console (demo_gui.m) from the bundle in the current folder and
%   captures numbered PNGs of each step into ../shots and an MP4 of them into ../gui_live_check.mp4.
%   parts: any of 'live', 'episode', 'tabs' (default all three). Prints GUICHK lines.
%   outdir: folder for shots/ and the MP4 (default: the folder of this file).
%   Run from the bundle copy, with the console code on the path.
if nargin < 1 || isempty(parts), parts = {'live', 'episode', 'tabs'}; end
if ischar(parts), parts = {parts}; end
if nargin < 2 || isempty(outdir), outdir = fileparts(mfilename('fullpath')); end
base = outdir;
G = struct('shots', fullfile(base, 'shots'), 'mp4', fullfile(base, 'gui_live_check.mp4'), 'n', 0, ...
    'method', '', 'hits', {{}}, 'tick', 0, 'pool_shot', false);
if ~isfolder(G.shots), mkdir(G.shots); end
old = dir(fullfile(G.shots, '*.png'));
if ~isempty(old)                                       % frames of an earlier dispatch: numbering goes on
    G.n = max(cellfun(@(s) sscanf(s, '%d', 1), {old.name}));
end
setappdata(0, 'GCAP', G);
fprintf('GUICHK start %s in %s, parts %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), pwd, strjoin(parts, ','));
assert(isfile('params.mat') && isfile('data/trained_dqn.mat'), 'capture_gui: run from the bundle copy');
P0 = load('params.mat').params;                        % the bundle's own parameters, before the console writes params.mat

t0 = tic;
demo_gui();
fig = findall(groot, 'Type', 'figure');
fig = fig(arrayfun(@(f) isstruct(f.UserData) && isfield(f.UserData, 'env'), fig));
assert(numel(fig) == 1, 'capture_gui: console figure not found');
fprintf('GUICHK console built in %.1f s, visible %s, position %s\n', toc(t0), char(fig.Visible), mat2str(fig.Position));
env = fig.UserData.env; ui = fig.UserData.ui;
[~, ~, note] = capture_gui_plan(env.snr_levels, env.threats, env.core);
fprintf('GUICHK %s\n', note);
params_check(P0, env.p0);
policy_check(fig);

selTab(ui, 'LIVE');
snap(fig, 'live_standby');
scan_nan(fig, 'standby');

fns = {'live', @run_live; 'episode', @run_episode; 'tabs', @run_tabs};
for k = 1:size(fns, 1)
    if ~ismember(fns{k, 1}, parts), continue; end
    try
        fns{k, 2}(fig);
    catch ME
        fprintf('GUICHK part %s error %s\n', fns{k, 1}, getReport(ME, 'basic'));
    end
end

G = getappdata(0, 'GCAP');
u = unique(G.hits);
fprintf('GUICHK nan %d\n', numel(u));
for k = 1:min(25, numel(u)), fprintf('GUICHK nan_hit %s\n', u{k}); end
write_video(G);
try, delete(fig); catch, end %#ok<NOCOM>
fprintf('GUICHK done\n');
assert(isempty(u), 'capture_gui: NaN or Inf shown in the console (%d), see GUICHK nan_hit lines', numel(u));
end

%% ---------- live ----------
function run_live(fig)
env = fig.UserData.env; ui = fig.UserData.ui;
selTab(ui, 'LIVE');
ui.recordChk.Value = false; ui.ruleChk.Value = true;
ui.sevDD.Value = 0;                                     % Nominal (baseline)
lv = env.snr_levels;
e4 = lv(find(lv == 4, 1)); if isempty(e4), e4 = lv(ceil(end / 2)); end
cleanE = unique([e4, max(lv)], 'stable');
fprintf('GUICHK live speed %.1f km/h, severity %s, Eb/N0 levels %s\n', ui.speedSpin.Value, ui.sevDD.Items{1}, mat2str(lv));
[runs, ebs] = capture_gui_plan(lv, env.threats, env.core);
for r = 1:numel(runs)
    tick_one(ui, env, runs{r}, ebs(r));
    n0 = numel(getappdata(fig, 'history'));
    t1 = tic;
    feval(ui.runBtn.ButtonPushedFcn, ui.runBtn, []);
    drawnow;
    H = getappdata(fig, 'history');
    term = termLines(ui);
    err = term(contains(term, 'ERROR'));
    fprintf('GUICHK live run %s @ %g dB took %.1f s, history %d -> %d, errors %d\n', runs{r}, ebs(r), toc(t1), n0, numel(H), numel(err));
    for k = 1:numel(err), fprintf('GUICHK live error %s\n', err{k}); end
    snap(fig, sprintf('live_%s_%gdB', runs{r}, ebs(r)));
    scan_nan(fig, sprintf('live %s %g', runs{r}, ebs(r)));
    if r == numel(cleanE)                               % only clean runs so far: no recovery value exists
        sl = strjoin(cellstr(ui.sessionLbl.Text), ' / ');
        fprintf('GUICHK summary clean-only %s\n', sl);
        fprintf('GUICHK summary_na %d\n', contains(sl, 'RULE N/A') && ~contains(sl, 'NaN') && ~contains(sl, 'Inf'));
    end
    if numel(H) > n0
        h = H{end};
        fprintf(['GUICHK live result %s @ %g dB: detected %s (%.1f%%) unknown %d | deployed %s | rule %s | core %s | ' ...
            'three-state %s | BER %.3g -> %.3g | verdict %s | latency %.2f ms\n'], h.threat, h.snr_dB, h.cnn_detected, ...
            100 * h.cnn_confidence, h.unknown, h.dqn_action, h.rule_action, h.core_action, h.state3, h.ber_before, ...
            h.ber_after_dqn, h.verdict, h.decision_latency_ms);
        fprintf('GUICHK live state label %s\n', strjoin(cellstr(ui.stateLbl.Text), ' / '));
    end
end
% the clean link: no configuration change by any policy, no false-alarm line in the terminal
H = getappdata(fig, 'history');
alarm = false; nClean = 0;
for k = 1:numel(H)
    h = H{k};
    if ~strcmp(h.threat, 'none'), continue; end
    nClean = nClean + 1;
    a = ~strcmp(h.dqn_action, 'no_action') || ~strcmp(h.rule_action, 'no_action') || ~strcmp(h.core_action, 'no_action');
    alarm = alarm || a;
end
term = termLines(ui);
fa = term(contains(lower(term), 'false alarm'));
for k = 1:numel(fa), fprintf('GUICHK clean terminal %s\n', fa{k}); end
alarm = alarm || ~isempty(fa) || nClean == 0;
fprintf('GUICHK clean runs %d\n', nClean);
fprintf('GUICHK clean alarm %d\n', alarm);
selTab(ui, 'SESSION');
snap(fig, 'session_log_after_live');
check_table_bg();
selTab(ui, 'LIVE');
end

function tick_one(ui, env, threat, ebno)
d = ui.matrixTbl.Data;
d(:, 1) = {false}; d(:, 3:end) = {false};
r = find(strcmp(env.threats, threat), 1); k = find(env.snr_levels == ebno, 1);
assert(~isempty(r) && ~isempty(k), 'capture_gui: no cell %s @ %g', threat, ebno);
d{r, 2 + k} = true;
ui.matrixTbl.Data = d;
end

function L = termLines(ui)
L = ui.termArea.Value; if ischar(L), L = {L}; end
L = cellstr(L);
end

%% ---------- episode ----------
function run_episode(fig)
env = fig.UserData.env; ui = fig.UserData.ui;
selTab(ui, 'CONTINUOUS');
ui.epThreatDD.Value = 'jamming';
lv = env.snr_levels; e4 = lv(find(lv == 4, 1)); if isempty(e4), e4 = lv(ceil(end / 2)); end
ui.epSnrDD.Value = e4; ui.epSevDD.Value = 0;
ui.epPolicyDD.Value = 'all';
ui.epPaceDD.Value = 0.15;
ui.epSeedFld.Value = 7;
fprintf('GUICHK episode jamming @ %g dB nominal, policies all, %d clean + %d attacked cycles, escalation %d, seed 7\n', ...
    e4, ui.epPreSpin.Value, ui.epPostSpin.Value, ui.epHystChk.Value);
snap(fig, 'episode_settings');
G = getappdata(0, 'GCAP'); G.pool_shot = false; G.tick = 0; setappdata(0, 'GCAP', G);
tm = timer('ExecutionMode', 'fixedSpacing', 'Period', 3, 'BusyMode', 'drop', 'TimerFcn', @(~, ~) ep_tick(fig));
start(tm);
t1 = tic;
try
    feval(ui.epRunBtn.ButtonPushedFcn, ui.epRunBtn, []);
catch ME
    fprintf('GUICHK episode error %s\n', ME.message);
end
stop(tm); delete(tm);
drawnow;
fprintf('GUICHK episode took %.1f s\n', toc(t1));
st = cellstr(ui.epStatus.Value);
for k = 1:numel(st), fprintf('GUICHK episode status %s\n', st{k}); end
fprintf('GUICHK episode cycle label %s\n', strjoin(cellstr(splitlines(string(ui.epCycleLbl.Text))), ' // '));
fprintf('GUICHK episode cycle label height %.0f px, %d lines\n', ui.epCycleLbl.Position(4), numel(splitlines(string(ui.epCycleLbl.Text))));
txt = strjoin(st, newline);
nm = regexp(txt, '(\S[^\n]*?): T_detect', 'tokens');
sw = regexp(txt, 'switches (\d+) before onset, (\d+) after', 'tokens');
for k = 1:min(numel(nm), numel(sw))
    fprintf('GUICHK episode clean switches %s %s (after onset %s)\n', strtrim(nm{k}{1}), sw{k}{1}, sw{k}{2});
end
term = termLines(ui);
err = term(contains(term, 'EPISODE ERROR') | contains(term, 'WARNING'));
for k = 1:numel(err), fprintf('GUICHK episode terminal %s\n', err{k}); end
snap(fig, 'episode_done');
scan_nan(fig, 'episode');
end

function ep_tick(fig)
try
    if ~isvalid(fig), return; end
    ui = fig.UserData.ui; G = getappdata(0, 'GCAP');
    lbl = char(ui.epCycleLbl.Text);
    st = cellstr(ui.epStatus.Value);
    if startsWith(strtrim(lbl), 'cycle') && G.tick < 12
        G.tick = G.tick + 1; setappdata(0, 'GCAP', G);
        c = regexp(lbl, 'cycle\s+(\d+)', 'tokens', 'once'); if isempty(c), c = {'x'}; end
        snap(fig, sprintf('episode_cycle_%s', c{1}));
    elseif ~G.pool_shot && any(contains(st, 'Building frame pool'))
        G.pool_shot = true; setappdata(0, 'GCAP', G);
        snap(fig, 'episode_pool_building');
    end
catch ME
    fprintf('GUICHK tick error %s\n', ME.message);
end
end

%% ---------- other tabs ----------
function run_tabs(fig)
ui = fig.UserData.ui;
selTab(ui, 'KPI');
snap(fig, 'kpi_tab');
scan_nan(fig, 'kpi');
lat = sprintf('%s | %s', char(ui.kpiVal(3).Text), char(ui.kpiSub(3).Text));
fprintf('GUICHK latency card %s\n', lat);
for k = 1:6
    fprintf('GUICHK kpi card %d %s | %s\n', k, char(ui.kpiVal(k).Text), char(ui.kpiSub(k).Text));
end
L = cellstr(ui.kLect.Value);
for k = 1:numel(L), fprintf('GUICHK kpi lecturer %s\n', L{k}); end
selTab(ui, 'SURVIVABILITY');
snap(fig, 'survivability_tab');
selTab(ui, 'SESSION');
snap(fig, 'session_log');
scan_nan(fig, 'final');
end

%% ---------- checks ----------
function check_table_bg()
% The Session Log table's empty area (below the rows) must follow the dark theme, not be white.
G = getappdata(0, 'GCAP');
f = fullfile(G.shots, sprintf('%02d_session_log_after_live.png', G.n));
if ~isfile(f), fprintf('GUICHK table_bg unknown (no shot)\n'); return; end
I = imread(f); [h, w, ~] = size(I);
px = double(squeeze(I(round(0.75 * h), round(0.40 * w), 1:3)));
fprintf('GUICHK table_bg pixel %s dark %d\n', mat2str(px'), mean(px) < 100);
end

function policy_check(fig)
env = fig.UserData.env; ui = fig.UserData.ui;
v = who('-file', 'data/trained_dqn.mat');
raw = '(not recorded)'; sel = '(none)';
if ismember('deployed', v), raw = load('data/trained_dqn.mat', 'deployed').deployed; end
if ismember('seed_summary', v)
    ss = load('data/trained_dqn.mat', 'seed_summary').seed_summary;
    if isfield(ss, 'selected_kind'), sel = ss.selected_kind; end
end
kind = raw; if strcmp(kind, '(not recorded)'), kind = sel; end
expect = containers.Map({'dqn', 'dqn_esc', 'rule_sel'}, {'DQN, no escalation', 'DQN + escalation', 'rule fallback'});
lbls = findall(fig, 'Type', 'uilabel');
hdr = '';
for k = 1:numel(lbls)
    t = char(strjoin(cellstr(lbls(k).Text), ' '));
    tok = regexp(t, 'deployed: ([^|]+?) \|', 'tokens', 'once');
    if ~isempty(tok), hdr = tok{1}; break; end
end
pdec = findall(fig, 'Type', 'uipanel');
pt = arrayfun(@(p) char(p.Title), pdec, 'UniformOutput', false);
dt = pt(startsWith(pt, '4 - DECISION'));
ok = isKey(expect, kind) && strcmp(hdr, expect(kind)) && strcmp(env.dep.kind, kind) && ...
    isequal(logical(ui.epHystChk.Value), ~strcmp(kind, 'dqn')) && ~isempty(dt) && contains(dt{1}, env.dep.name);
fprintf('GUICHK policy file deployed %s, seed_summary.selected_kind %s; console kind %s, text "%s", escalation box %d (%s), decision panel "%s"\n', ...
    raw, sel, env.dep.kind, env.dep.text, ui.epHystChk.Value, ui.epHystChk.Text, strjoin(dt, ';'));
fprintf('GUICHK policy %s deployed %s match %d\n', hdr, kind, ok);
end

function params_check(P0, p)
f0 = fieldnames(P0); f1 = fieldnames(p);
d = setxor(f0, f1);
for k = intersect(f0, f1)'
    if ~isequaln(P0.(k{1}), p.(k{1})), d{end+1} = k{1}; end %#ok<AGROW>
end
fprintf('GUICHK params bundle vs console p0 equal %d, %d fields differ: %s\n', isempty(d), numel(d), strjoin(d(:)', ','));
for k = 1:min(15, numel(d))
    a = '(absent)'; b = '(absent)';
    if isfield(P0, d{k}), a = shortval(P0.(d{k})); end
    if isfield(p, d{k}), b = shortval(p.(d{k})); end
    fprintf('GUICHK params diff %s bundle %s console %s\n', d{k}, a, b);
end
end

function s = shortval(x)
try
    if ischar(x), s = x; elseif isnumeric(x) || islogical(x), s = mat2str(x(1:min(end, 8))); else, s = class(x); end
catch
    s = class(x);
end
if numel(s) > 80, s = s(1:80); end
end

function scan_nan(fig, where)
% NaN / Inf in any text the console shows: labels, buttons, text areas, tables, menus, panel and
% tab titles, axes text and tick labels, legends; numeric values of tables and fields.
G = getappdata(0, 'GCAP');
H = findall(fig);
props = {'Text', 'Value', 'Items', 'Title', 'String', 'Data', 'XTickLabel', 'YTickLabel', 'ColumnName'};
re = '(?<![A-Za-z])(NaN|-?Inf)(?![A-Za-z])';
n0 = numel(G.hits);
for i = 1:numel(H)
    h = H(i);
    ty = get(h, 'Type');
    if ismember(ty, {'line', 'scatter', 'patch', 'image', 'bar', 'constantline', 'surface', 'area', 'stair'}), continue; end
    for p = props
        if ~isprop(h, p{1}), continue; end
        try, v = get(h, p{1}); catch, continue; end %#ok<NOCOM>
        if isa(v, 'matlab.graphics.Graphics'), continue; end
        if strcmp(p{1}, 'Value') && (isnumeric(v) || islogical(v))
            if ismember(ty, {'uieditfield', 'uispinner', 'uislider', 'uigauge', 'uiknob'}) && isnumeric(v) && any(~isfinite(v(:)))
                G.hits{end+1} = sprintf('%s [%s] %s.Value non-finite', ty, tabOf(h), p{1});
            end
            continue;
        end
        for s = flat(v)
            t = s{1};
            if isnumeric(t)
                if any(~isfinite(t(:))), G.hits{end+1} = sprintf('%s [%s] %s numeric cell non-finite', ty, tabOf(h), p{1}); end
            elseif ~isempty(regexp(t, re, 'once'))
                G.hits{end+1} = sprintf('%s [%s] %s: %s', ty, tabOf(h), p{1}, t(1:min(end, 120)));
            end
        end
    end
end
setappdata(0, 'GCAP', G);
fprintf('GUICHK scan %s: %d new hit(s)\n', where, numel(G.hits) - n0);
end

function c = flat(v)
if ischar(v), c = {v};
elseif isstring(v), c = cellstr(v(:)');
elseif iscell(v)
    c = {};
    for k = 1:numel(v), c = [c, flat(v{k})]; end %#ok<AGROW>
elseif isnumeric(v), c = {v};
else, c = {};
end
end

function t = tabOf(h)
a = ancestor(h, 'uitab');
if isempty(a), t = 'header'; else, t = strtrim(char(a.Title)); end
end

function selTab(ui, key)
t = ui.tabGroup.Children;
k = find(arrayfun(@(x) startsWith(strtrim(char(x.Title)), key), t), 1);
ui.tabGroup.SelectedTab = t(k);
drawnow;
end

%% ---------- capture ----------
function snap(fig, name)
G = getappdata(0, 'GCAP');
G.n = G.n + 1;
f = fullfile(G.shots, sprintf('%02d_%s.png', G.n, name));
drawnow; pause(0.3); drawnow;
methods = {'exportapp', 'getframe', 'exportgraphics', 'exportapp_hidden'};
if ~isempty(G.method), methods = [{G.method}, setdiff(methods, {G.method}, 'stable')]; end
done = '';
for m = methods
    try
        switch m{1}
            case 'exportapp', exportapp(fig, f);
            case 'getframe', fr = getframe(fig); imwrite(fr.cdata, f);
            case 'exportgraphics', exportgraphics(fig, f, 'Resolution', 96);
            case 'exportapp_hidden'
                v = fig.Visible; fig.Visible = 'off'; drawnow; exportapp(fig, f); fig.Visible = v;
        end
        I = imread(f);
        sd = std(double(I(:)));
        if sd > 3
            done = m{1};
            fprintf('GUICHK shot %s method %s size %dx%d std %.1f\n', f, m{1}, size(I, 2), size(I, 1), sd);
            break;
        end
        fprintf('GUICHK shot %s method %s blank (std %.2f)\n', f, m{1}, sd);
    catch ME
        fprintf('GUICHK shot %s method %s failed: %s\n', f, m{1}, ME.message);
    end
end
if isempty(done), fprintf('GUICHK shot %s none worked\n', f); else, G.method = done; end
setappdata(0, 'GCAP', G);
end

function write_video(G)
d = dir(fullfile(G.shots, '*.png'));
if isempty(d), fprintf('GUICHK video none (no frames)\n'); return; end
[~, o] = sort({d.name}); d = d(o);
I0 = imread(fullfile(d(1).folder, d(1).name));
h = 2 * floor(size(I0, 1) / 2); w = 2 * floor(size(I0, 2) / 2);
fps = 2; rep = 3;                                     % each picture held 1.5 s
if isfile(G.mp4), movefile(G.mp4, [G.mp4(1:end-4) '_prev_' datestr(now, 'yyyymmdd_HHMMSS') '.mp4']); end
vw = VideoWriter(G.mp4, 'MPEG-4'); vw.FrameRate = fps; vw.Quality = 95; open(vw);
nW = 0;
for k = 1:numel(d)
    I = imread(fullfile(d(k).folder, d(k).name));
    if size(I, 3) == 1, I = repmat(I, 1, 1, 3); end
    J = zeros(h, w, 3, 'like', I);                      % same size for every picture: crop or pad
    a = min(h, size(I, 1)); b = min(w, size(I, 2));
    J(1:a, 1:b, :) = I(1:a, 1:b, 1:3); I = J;
    for r = 1:rep, writeVideo(vw, I); nW = nW + 1; end
end
close(vw);
v = VideoReader(G.mp4);
fprintf('GUICHK video %s pictures %d frames %d fps %d duration %.1f s size %dx%d\n', G.mp4, numel(d), nW, fps, v.Duration, v.Width, v.Height);
end
