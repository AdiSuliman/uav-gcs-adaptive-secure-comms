function rx_d2(root, rxroot)
%RX_D2  D2, the noise-free twin of the delay-line receiver's first pass, on validation data
%   only, under rxroot\docs\rx_d2_rule.md (its sha256 and that of root\fix\build_threat_model.m
%   are checked before anything runs):
%   1. text and wiring guards: the receiver's script with the field absent or 'off' equals
%      the export's, 'log' minus its prints equals 'off', every arm's script minus its prints
%      equals its tokens' script; no twin input without a twin token, the twin input of
%      every twin arm from output 4 of the threat block;
%   2. the as-built receiver ('log') and the rungs 'twinf', 'twing' and 'twin' (each with
%      'log', own_out on) on the 27 part-B flights with their saved seeds; the as-built
%      reproduction of the saved frame BER; the flat channel off against 'twin' (G4);
%   3. the reading of the three frames, the twin's true lag profile (RXL) on the named, the
%      collapsed and 3 clean frames per flight;
%   4. the census: the same arms on the validation cells none, tone_jamming and jamming at
%      their nominal level, 10 split-2 geometries of the policy pools each.
%   root    the link-floor folder (src = the export, data, results, fix)
%   rxroot  the rx-ne-fix worktree (docs\rx_d2_rule.md, code\link\build_threat_model.m)
% Line tags: RULE (registered hashes), RXE (runs, guards, reading, census), RXET (one line per
% frame and arm), RXEB (per pilot block), RXEL (the twin's lag profile per block and antenna),
% RXEC (census counts), RXECF (the census frames the twin decodes and the as-built receiver
% loses).
RULE_SHA = '55e44f275c68867df373ef62ac12fee295c913e2cebaccd7c5956873f46fb9a8';
FIX_SHA = '7d9c9675bb0ad9a711a20bc2af7bab20c1f70d373713fa64ff6d73f49b195edd';
t00 = tic;
rule = fullfile(rxroot, 'docs', 'rx_d2_rule.md');
h = sha256_file(rule);
fprintf('RULE rx_d2_rule.md sha256 %s\n', h);
if ~strcmp(h, RULE_SHA)
    error('rx_d2: rx_d2_rule.md sha256 %s is not the registered %s; D2 not run', h, RULE_SHA);
end
src = fullfile(root, 'src'); dat = fullfile(root, 'data'); out = fullfile(root, 'results'); fix = fullfile(root, 'fix');
h = sha256_file(fullfile(fix, 'build_threat_model.m'));
fprintf('RULE fix build_threat_model.m sha256 %s\n', h);
if ~strcmp(h, FIX_SHA)
    error('rx_d2: fix build_threat_model.m sha256 %s is not the registered %s; D2 not run', h, FIX_SHA);
end
cd(src); addpath(fullfile(src, 'code')); setup_paths;
warning('off', 'Simulink:cgxe:LeakedJITEngine');
S0 = load(fullfile(dat, 'params.mat')); p0 = S0.params; p0.quiet_build = true;
p = p0; p.active_threat = 'none';
L = load(fullfile(out, 'link_floor_partA.mat')); A = L.A; L = load(fullfile(out, 'link_floor_partB.mat')); sel = L.sel;
mdl = 'UAV_GCS_Threat_Link';
[C, ~, ~] = pool_configs(p, 'none', {'no_action'}); pR = C(1).p; g_db = C(1).g_db;
assert(~isfield(pR, 'rx_ne_fix'), 'rx_d2: the params carry rx_ne_fix');
fprintf('RXE start %s, rx_dd_iter %d, n_rx %d, export file %s\n', datestr(now), pR.rx_dd_iter, pR.n_rx, which('build_threat_model'));

% the 27 flights in part B's order, their saved frames and the named frames
FL = struct('e', {}, 'run', {}, 'seed', {}, 'speed', {}); sv = {};
for ii = 1:numel(A)
    T = A(ii).T;
    for j = sel{ii}(:)'
        FL(end + 1) = struct('e', A(ii).e, 'run', T.run(j), 'seed', double(T.seed(j)), 'speed', T.speed(j)); %#ok<AGROW>
        sv{end + 1} = A(ii).frm{j}.ber(:)'; %#ok<AGROW>
    end
end
key = [[FL.e]', [FL.run]'];
NM = [12 420 5; 12 452 10; 12 459 16; 12 426 9; 9 511 12; 12 411 4];   % 1-3 the three frames, 4-6 reported only
nm = zeros(size(NM, 1), 1);
for c = 1:size(NM, 1)
    k = find(key(:, 1) == NM(c, 1) & key(:, 2) == NM(c, 2), 1);
    if isempty(k), fprintf('RXE named frame %d dB run %d frame %d: not among the 27 flights\n', NM(c, :)); else, nm(c) = k; end
end
fprintf('RXE flights %d, as-built BER27 sum %.4f\n', numel(FL), sum(cellfun(@mean, sv)));

% G2, first half: the export's script, built before the fix file is on the path
s_exp = rx_text(pR, mdl);

%% 1. The fix file, text and wiring guards (G2)
addpath(fix); clear('build_threat_model');
fprintf('RXE fix file %s\n', which('build_threat_model'));
hf = sha256_file(fullfile(fix, 'build_threat_model.m'));
hb = sha256_file(fullfile(rxroot, 'code', 'link', 'build_threat_model.m'));
fprintf('RXE fix file sha256 %s, rx-ne-fix code/link/build_threat_model.m sha256 %s, equal %d\n', hf, hb, strcmp(hf, hb));
q = pR; sa = rx_text(q, mdl);
q.rx_ne_fix = 'off'; so = rx_text(q, mdl);
q.rx_ne_fix = 'log'; sl = rx_text(q, mdl);
q = pR; q.own_out = true; q.rx_ne_fix = 'off'; soo = rx_text(q, mdl);
g2 = [isequal(sa, s_exp), isequal(so, s_exp), isequal(soo, s_exp), isequal(strip_prints(splitlines(sl)), splitlines(so))];
fprintf('RXE G2 absent==export %d off==export %d off(own_out)==export %d log-minus-prints==off %d\n', g2);
ARMS = {'log', 'log'; 'twinf', 'twinf+log'; 'twing', 'twing+log'; 'twin', 'twin+log'};
na = size(ARMS, 1);
w0 = true;
for m = {'', 'off', 'log'}
    q = pR; q.own_out = true; if ~isempty(m{1}), q.rx_ne_fix = m{1}; end
    [n3, src3] = wiring(q, mdl);
    fprintf('RXE G2 wiring %s: twin input %d, receiver inputs %d\n', ternary(isempty(m{1}), '(absent)', m{1}), ~isempty(src3), n3);
    w0 = w0 && n3 == 2 && isempty(src3);
end
w1 = true;
for a = 2:na
    q = pR; q.own_out = true; q.rx_ne_fix = ARMS{a, 2};
    [n3, src3] = wiring(q, mdl);
    fprintf('RXE G2 wiring %s: receiver inputs %d, third from %s\n', ARMS{a, 2}, n3, src3);
    w1 = w1 && n3 == 3 && strcmp(src3, 'LevelTw <- Threat/4');
end
% each arm's script minus its prints equals its tokens' script without 'log'
ST = cell(na, 1);
for a = 1:na
    q = pR; q.own_out = true; q.rx_ne_fix = tok_only(ARMS{a, 2});
    try
        ST{a} = core_text(rx_text(q, mdl));
    catch err
        fprintf('RXE G2 %s build error: %s\n', q.rx_ne_fix, getReport(err, 'basic'));
        ST{a} = {'(build error)'};
    end
end
G2 = all(g2) && strcmp(hf, hb) && w0 && w1;
fprintf('RXE G2 text and wiring -> %s\n', pf(G2));

%% 2. The arms on the 27 flights
R = cell(na, 1); G3 = false(na, 1); g2a = false(na, 1); TR = [];
for a = 1:na
    q = pR; q.rx_ne_fix = ARMS{a, 2}; q.own_out = true;
    [R{a}, G3(a)] = run_arm(ARMS{a, 1}, q, g_db, FL, sv, mdl, p, 0, a == 1);
    g2a(a) = isequal(R{a}.core, ST{a});
    fprintf('RXE G2 arm %s: script minus prints == %s minus prints %d\n', ARMS{a, 1}, tok_only(ARMS{a, 2}), g2a(a));
    if a == 1, TR = R{a}.truth; end
    table_arm(R{a}, key, TR, R{a}.lab);
    if a == 1 && ~any(~isnan(R{1}.fer))
        fprintf('RXE GUARDS G1 FAIL G2 %s G3 FAIL G4 not run -> D2 void (the log arm did not run)\n', pf(G2 && g2a(1)));
        close_system(mdl, 0);
        fprintf('RXE done %s (%.1f min)\n', datestr(now), toc(t00) / 60);
        return;
    end
end
G2 = G2 && all(g2a);
twin_train(R{strcmp(ARMS(:, 1), 'twinf')});
fprintf('RXE G2 arms: %d of %d arms are their tokens plus prints only -> G2 %s\n', nnz(g2a), na, pf(G2));
d1 = cellfun(@(x) x(1), R{1}.dsv);
G1 = numel(d1) == numel(FL) && all(d1 == 0) && R{1}.done;
fprintf('RXE G1 as built (log) reproduces the saved frame BER on %d of %d flights (own_out on), max|d| %.1e -> %s\n', ...
    nnz(d1 == 0), numel(FL), max([d1, NaN]), pf(G1));
if ~G1
    q = pR; q.rx_ne_fix = 'off'; q.own_out = true;
    Ro = run_arm('off-control', q, g_db, FL, sv, mdl, p, 0, false);
    d0 = cellfun(@(x) x(1), Ro.dsv);
    fprintf('RXE G1 control: off (no prints) reproduces %d of %d flights, max|d| %.1e\n', nnz(d0 == 0), numel(FL), max([d0, NaN]));
end

%% 3. Flat channel: off against the twin (G4)
pF = p; pF.tdl = false; pF.tdl_random = false;
[CF, ~, ~] = pool_configs(pF, 'none', {'no_action'}); qF = CF(1).p; gF = CF(1).g_db; qF.own_out = true;
qF.rx_ne_fix = 'off';
F0 = run_arm('F-off', qF, gF, FL, sv, mdl, p, 0, false);
qF.rx_ne_fix = 'twin+log';
F1 = run_arm('F-twin', qF, gF, FL, sv, mdl, p, 0, false);
dmax = [];
for k = 1:min(numel(F0.z), numel(F1.z))
    dz = Inf;
    if ~isempty(F0.z{k}) && isequal(size(F1.z{k}), size(F0.z{k})) && isequal(size(F1.fb{k}), size(F0.fb{k}))
        dz = max([abs(F1.z{k}(:) - F0.z{k}(:)); abs(F1.fb{k}(:) - F0.fb{k}(:))]);
    end
    dmax(end + 1) = dz; %#ok<AGROW>
    fprintf('RXE G4 twin+log %2d dB run %3d max|d| Rx_Z and frame BER %.1e\n', key(k, :), dz);
end
G4 = F0.done && F1.done && numel(F1.z) == numel(FL) && ~isempty(dmax) && all(dmax == 0);
fprintf('RXE G4 F-off against F-twin: %d comparisons, max|d| %.1e -> %s\n', numel(dmax), max([dmax, NaN]), pf(G4));

%% 4. Per-block lines, the twin's profiles, the reading
blocks(R, ARMS, key, nm, NM, TR);
reading(R, ARMS, key, nm, NM, TR);

%% 5. The census
[G3c, CS] = census(p0, ARMS, mdl, p);
for a = 1:na, fprintf('RXE G3 %s -> %s\n', ARMS{a, 1}, pf(G3(a))); end
fprintf('RXE G3 census builds and flights -> %s\n', pf(G3c));
G3 = all(G3) && G3c;
fprintf('RXE GUARDS G1 %s G2 %s G3 %s G4 %s -> D2 %s\n', pf(G1), pf(G2), pf(G3), pf(G4), ...
    ternary(G1 && G2 && G3 && G4, 'valid', 'void (no rung named; fix the harness, rerun)'));
close_system(mdl, 0);
save(fullfile(out, sprintf('rx_d2_%s.mat', datestr(now, 'yyyymmdd_HHMM'))), 'CS', 'key', 'NM', 'ARMS');
fprintf('RXE done %s (%.1f min)\n', datestr(now), toc(t00) / 60);
end

%% ===================== One arm =====================
function [R, g3] = run_arm(lab, q, g_db, FL, sv, mdl, p, de, want_truth)
% One build, the flights FL with their seeds at their Eb/N0 + de; the frames, the receiver's
% prints and (want_truth) the own component's powers. sv: the saved frame BER per flight
% ({} or empty entries: none).
R = struct('lab', lab, 'fb', {{}}, 'fer', [], 'ber', [], 'z', {{}}, 'F', {{}}, 'D', {{}}, 'dsv', {{}}, ...
    'truth', {{}}, 'done', false, 'truth_ok', false, 'nprint', 0, 'nframes', 0, 'nbit_ok', 0, 'nbit', 0, 'ntw_ok', 0, ...
    'NR', q.n_rx, 'NB', 0, 'NV', 0, 'nbits', q.frame_length, 'core', {{}}, 'tq', [], 'sr', q.symbol_rate);
g3 = false; ta = tic;
try
    build_threat_model(q);
    ch = sfroot().find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/Rx']); s = ch.Script;
catch err
    fprintf('RXE %s build error: %s\n', lab, getReport(err, 'basic'));
    return;
end
R.core = core_text(s);
tk = {};
if isfield(q, 'rx_ne_fix'), tk = strsplit(lower(q.rx_ne_fix), '+'); end
if any(strcmp(tk, 'twin')), tk = [tk(~strcmp(tk, 'twin')), {'twinf', 'twing'}]; end
tk = setdiff(tk, {'off'});
st = steps_on(s);
match = isempty(setxor(st, tk));
fprintf('RXE %s tokens ON: %s (requested %s) -> match %d\n', lab, strjoin_or(st), strjoin_or(tk), match);
Lf = frame_layout(q); NB = numel(Lf.pil_center); NR = q.n_rx; R.NB = NB;
tp = rx_taps(q); NRK = sum(tp.lags) + 1; R.NV = 3 + NRK;
R.tq = [(1 + tp.lags(2) + Lf.n_pre - tp.lags(1)) / 2; Lf.pil_center(:) - Lf.NQ];   % training and block centres [symbols]
logon = any(strcmp(st, 'log')) && tp.ne > 1;   % the prints exist on the delay line only
twin = getSimulinkBlockHandle([mdl '/LevelTw']) ~= -1;
for k = 1:numel(FL)
    f1 = FL(k); e = f1.e;
    try
        set_link_snr(mdl, e + de + 10*log10(q.bits_per_symbol) - 10*log10(q.sps) + g_db, q);
        if twin                                   % the twin at the received level
            set_param([mdl '/LevelTw'], 'Gain', get_param([mdl '/Level'], 'Gain'));
            R.ntw_ok = R.ntw_ok + strcmp(get_param([mdl '/LevelTw'], 'Gain'), get_param([mdl '/Level'], 'Gain'));
        end
        [so, txt] = sim_flight(mdl, q, p, f1, logon);
        [F, ~] = extract_closed_loop_frames(so, q, 20);
        nf = numel(F.ber);
        D = parse_rx(txt, NR, NB, R.NV);
        R.nprint = R.nprint + numel(D); R.nframes = R.nframes + nf;
        if numel(D) ~= nf && logon
            fprintf('RXE %s %2d dB run %3d: %d print frames for %d frames (prints not used for this flight)\n', lab, e, f1.run, numel(D), nf);
            D = parse_rx('', NR, NB, R.NV);
        end
        dsv = NaN;
        if numel(sv) >= k && ~isempty(sv{k}) && de == 0
            n = min(nf, numel(sv{k}));
            dsv = max(abs(F.ber(1:n) - sv{k}(1:n)));
        end
        R.fb{k} = F.ber(:)'; R.fer(k) = mean(F.fer, 'omitnan'); R.ber(k) = mean(F.ber, 'omitnan');
        R.F{k} = struct('ber', F.ber(:)', 'fer', F.fer(:)', 'cfo', F.cfo_hz(:)', 'pe', F.pilot_err(:)', 'sd', F.sync_d(:)', ...
            'gain_ant', F.gain_ant, 'rq', F.rq);
        R.D{k} = D; R.dsv{k} = dsv;
        R.z{k} = so.get('Rx_Z');
        if numel(D) == nf
            nb = arrayfun(@(x) x.s(4), D);
            R.nbit = R.nbit + nf; R.nbit_ok = R.nbit_ok + nnz(abs(nb(:)' / q.frame_length - F.ber(:)') < 1e-12);
        end
        if want_truth, R.truth{k} = truth(so, mdl, q, F, Lf); end
        fprintf('RXE %s %2d dB run %3d ber %.2e fer %.2f | max|d| vs saved %.1e | frames > 0.05: %s\n', lab, e, f1.run, ...
            R.ber(k), R.fer(k), dsv, mat2str(find(F.ber > 0.05)));
    catch err
        fprintf('RXE %s %2d dB run %3d error: %s\n', lab, e, f1.run, getReport(err, 'basic'));
        R.fb{k} = []; R.fer(k) = NaN; R.ber(k) = NaN; R.D{k} = parse_rx('', NR, NB, R.NV); R.dsv{k} = NaN; R.z{k} = [];
        R.F{k} = struct('ber', [], 'fer', [], 'cfo', [], 'pe', [], 'sd', [], 'gain_ant', [], 'rq', []);
        if k == 1, fprintf('RXE %s flight 1 failed: arm not run\n', lab); break; end
    end
end
R.done = numel(R.fb) == numel(FL) && all(~isnan(R.fer));
R.truth_ok = ~logon || (R.nbit == R.nframes && R.nbit_ok == R.nbit);   % txbits belong to the printed frames
if logon
    fprintf('RXE %s prints: %d frames printed for %d frames; chart bit errors agree with the frame BER on %d of %d\n', ...
        lab, R.nprint, R.nframes, R.nbit_ok, R.nbit);
    fprintf('RXE %s truth prints valid %d\n', lab, R.truth_ok);
end
tw_ok = true;
if twin
    tw_ok = R.ntw_ok == numel(FL);
    fprintf('RXE %s twin gain equal to the gain Level on %d of %d flights\n', lab, R.ntw_ok, numel(FL));
end
nfe = sum(cellfun(@(F) sum(F.fer, 'omitnan'), R.F));
fprintf('RXE %s FER %.4f (%d frames lost) BER sum %.4f flights %d (%.1f min)\n', lab, mean(R.fer), round(nfe), sum(R.ber), ...
    numel(R.fer), toc(ta) / 60);
fprintf('RXE %s done\n', lab);
g3 = match && R.done && tw_ok;
end

function [so, txt] = sim_flight(mdl, q, p, f1, want)
% One flight of 20 frames with its seed; txt = what the receiver printed.
if nargin < 5, want = false; end
fd = f1.speed / 3.6 * p.carrier_freq / p.c_light;
link_seed(mdl, f1.seed, fd, struct('ebno', f1.e, 'alt_m', NaN, 'k_sig_db', NaN, 'aoa1_deg', NaN, ...
    'rho', NaN, 'event_frame', NaN, 'frames', 20));
[so, txt] = sim_cap(mdl, num2str(19 * q.frame_duration), want);
end

function [so, txt] = sim_cap(mdl, stop, want)
% The simulation with the receiver's prints captured by evalc; when evalc catches none of a
% print build's lines, once by diary, and that way from then on.
persistent mode
if isempty(mode), mode = 'evalc'; end
if ~want
    txt = evalc('so = sim(mdl, ''StopTime'', stop);');
    return;
end
switch mode
    case 'evalc'
        txt = evalc('so = sim(mdl, ''StopTime'', stop);');
        if isempty(strfind(txt, 'RXS ')) %#ok<STREMP>
            [so, txt] = sim_diary(mdl, stop);
            if isempty(strfind(txt, 'RXS ')), mode = 'none'; else, mode = 'diary'; end %#ok<STREMP>
            if strcmp(mode, 'none')
                fprintf(['RXE receiver prints: evalc and diary caught none; the per-step prints are dropped by the ' ...
                    'simulation target from here; the BER-based results go on\n']);
            else
                fprintf('RXE receiver prints: evalc caught none; capture by %s from here\n', mode);
            end
        end
    case 'diary'
        [so, txt] = sim_diary(mdl, stop);
    otherwise
        txt = evalc('so = sim(mdl, ''StopTime'', stop);');
end
end

function [so, txt] = sim_diary(mdl, stop)
f = [tempname '.txt'];
diary(f); so = sim(mdl, 'StopTime', stop); diary('off');
txt = fileread(f);
end

function D = parse_rx(txt, NR, NB, NV)
% The receiver's RX* lines, one struct per frame (an RXS line closes a frame).
D = repmat(blank(NR, NB, NV), 0, 1);
if isempty(txt), return; end
ln = splitlines(txt); cur = blank(NR, NB, NV);
for i = 1:numel(ln)
    s = strtrim(ln{i});
    if numel(s) < 5 || ~strncmp(s, 'RX', 2) || s(4) ~= ' ', continue; end
    v = str2double(strsplit(strtrim(s(5:end))));
    switch s(1:3)
        case 'RXY', cur.y = pad(v, 7);
        case 'RXP', v = pad(v, 7); if v(1) == 1 || v(1) == 2, cur.p(v(1), :) = v(2:7); end
        case 'RXT', cur.t = pad(v, NR + 1);
        case 'RXB', v = pad(v, 3 + NR); if v(1) >= 1 && v(1) <= NB, cur.b(v(1), :) = v(2:end); end
        case 'RXG', cur.g = pad(v, 2 * NR);
        case 'RXF', cur.f = pad(v, NB);
        case 'RXN', cur.n = pad(v, NB);
        case 'RXH', cur.h = pad(v, 4);
        case 'RXL'
            v = pad(v, 2 + NV);
            if v(1) >= 0 && v(1) <= NB && v(2) >= 1 && v(2) <= NR, cur.l(v(1) + 1, v(2), :) = v(3:end); end
        case 'RXS', cur.s = pad(v, 4); D(end + 1, 1) = cur; cur = blank(NR, NB, NV); %#ok<AGROW>
    end
end
end

function x = blank(NR, NB, NV)
x = struct('y', nan(1, 7), 'p', nan(2, 6), 't', nan(1, NR + 1), 'b', nan(NB, 2 + NR), 'g', nan(1, 2 * NR), ...
    'f', nan(1, NB), 'n', nan(1, NB), 'h', nan(1, 4), 's', nan(1, 4), 'l', nan(NB + 1, NR, NV));
end

function v = pad(v, n)
v = [v(:)', nan(1, n)]; v = v(1:n);
end

function st = steps_on(s)
% The receiver steps the built script carries, read from its text.
st = {};
if contains(s, '''RXS '), st{end + 1} = 'log'; end
if contains(s, 'vsh = rxd_shadow('), st{end + 1} = 'shadow'; end
if contains(s, 'cc = cc + cq(b + 2) * conj(cq(b + 1));'), st{end + 1} = 'freq'; end
if contains(s, '                        cc = cc + Ca(:, b)'' * Ca(:, b + 1);'), st{end + 1} = 'freqa'; end
if contains(s, 'bf = -angle(gf) / (PC(2) - PC(1));'), st{end + 1} = 'freqf'; end
if contains(s, 'if rn(b) > 4 * en(b)')
    st{end + 1} = 'burstn';
elseif ~contains(s, 'if rb(b) > 4 * mr')
    st{end + 1} = 'noburst';
end
if contains(s, 'NHYP = 1;'), st{end + 1} = 'hsel1'; end
if ~contains(s, 'deq = d + jb*SPS;'), st{end + 1} = 'deq0'; end
if contains(s, 'flat_first('), st{end + 1} = 'keep'; end
if contains(s, 'bf = twin_freq(ywxt,'), st{end + 1} = 'twinf'; end
if contains(s, 'Gt = eq_train(yxt,'), st{end + 1} = 'twing'; end
end

function [n3, src3] = wiring(q, mdl)
% The receiver's number of inputs and the source of its third: 'LevelTw <- Threat/4' when the
% gain LevelTw takes output 4 of the threat block ('' without a third input).
build_threat_model(q);
pt = get_param([mdl '/Rx'], 'Ports'); n3 = pt(1); src3 = '';
if n3 >= 3
    ph = get_param([mdl '/Rx'], 'PortHandles');
    s1 = get_param(get_param(ph.Inport(3), 'Line'), 'SrcBlockHandle');
    src3 = get_param(s1, 'Name');
    if strcmp(src3, 'LevelTw')
        ph = get_param([mdl '/LevelTw'], 'PortHandles'); ln = get_param(ph.Inport(1), 'Line');
        src3 = sprintf('LevelTw <- %s/%d', get_param(get_param(ln, 'SrcBlockHandle'), 'Name'), ...
            get_param(get_param(ln, 'SrcPortHandle'), 'PortNumber'));
    end
end
close_system(mdl, 0);
end

%% ===================== Truth from the own component =====================
function own = own_signal(so, mdl, nf)
own = so.get('Thr_sig') * str2double(get_param([mdl '/Level'], 'Gain'));
own = own(:, :, 1:nf);
end

function W = truth(so, mdl, q, F, Lf)
% Per frame: every antenna's true power in the training window and in each pilot block's
% window against the frame's mean [dB]; the true post-MRC Es/N0 calibrated on the clean frames.
nf = numel(F.ber); own = own_signal(so, mdl, nf);
NR = size(own, 2); NB = numel(Lf.pil_center); sps = q.sps; NQ = Lf.NQ;
tp = rx_taps(q); RP = tp.lags(1); RQ = tp.lags(2);
ip = Lf.idx_pil(:) - NQ; pb = q.pilot_block; NS = Lf.n_sig; ns = size(own, 1);
W = struct('tr', nan(NR, nf), 'blk', nan(NR, NB, nf), 'es', nan(1, nf), 'ncal', 0);
for f = 1:nf
    d = F.sync_d(f); if ~isfinite(d), d = 0; end
    c0 = NQ * sps + round(q.filter_span / 2 * sps) + round(d);
    win = @(k1, k2) max(1, c0 + (k1 - 1) * sps + 1 - floor(sps / 2)) : min(ns, c0 + (k2 - 1) * sps + 1 + floor(sps / 2));
    pw = @(r) reshape(mean(abs(own(r, :, f)).^2, 1), [], 1);
    pfr = pw(win(1, NS));
    W.tr(:, f) = 10*log10(pw(win(1, Lf.n_pre)) ./ pfr);
    for b = 1:NB
        W.blk(:, b, f) = 10*log10(pw(win(ip((b - 1) * pb + 1) - RP, ip(b * pb) + RQ)) ./ pfr);
    end
end
qq = NQ * sps + 1 : ns;
gt = reshape(10*log10(mean(abs(own(qq, :, :)).^2, 1)), [], nf);
gts = 10*log10(sum(10.^(gt / 10), 1));
gpe = 10*log10(sum(10.^(F.gain_ant / 10) ./ F.rq, 1));
ok = F.ber < 1e-3 & F.pilot_err < 0.3;
W.ncal = nnz(ok);
if nnz(ok) >= 3, W.es = gts + median(gpe(ok) - gts(ok)); end
end

function t = twin_sum(x, tq, SR)
% From a frame's RXL and RXB lines: the largest gap between the measured |ga|^2 and the
% twin's true multiple |c|^2 over the antennas and pilot blocks [dB]; the largest share the
% template leaves of the true profile (pilot blocks, training) [dB]; every antenna's residual
% frequency of the true block phases in the receiver's frame [Hz] (LS line over the training
% and the blocks) and the largest wrapped residual around those lines [rad].
NR = size(x.l, 2);
t = struct('gerr', NaN, 'mis', NaN, 'mis0', NaN, 'fr', nan(1, NR), 'nl', NaN);
if all(isnan(x.l(:))), return; end
c2 = x.l(2:end, :, 1); ga2 = x.b(:, 3:end);
t.gerr = max(abs(ga2(:) - c2(:)));
t.mis = max(reshape(x.l(2:end, :, 3), [], 1)); t.mis0 = max(x.l(1, :, 3));
nl = 0;
for a = 1:NR
    ph = unwrap(x.l(:, a, 2));
    if any(isnan(ph)), continue; end
    cf = [tq(:), ones(numel(tq), 1)] \ ph;
    t.fr(a) = cf(1) * SR / (2*pi);
    nl = max(nl, max(abs(angle(exp(1j * (ph - [tq(:), ones(numel(tq), 1)] * cf))))));
end
t.nl = nl;
end

function twin_train(R)
% 'twinf' keeps the main samples' template, so on the training of the clean frames the twin's
% multiple c checks its level, timing and rotations against the main samples
c2 = []; ph = [];
for k = 1:numel(R.F)
    F = R.F{k}; D = R.D{k};
    if isempty(F.ber) || numel(D) ~= numel(F.ber), continue; end
    for f = find(F.ber < 1e-3 & F.pe < 0.3)
        c2 = [c2, D(f).l(1, :, 1)]; ph = [ph, D(f).l(1, :, 2)]; %#ok<AGROW>
    end
end
fprintf('RXE %s twin on the training of %d clean frame-antennas: median |c2| %.2f dB, median |angle c| %.3f rad\n', ...
    R.lab, numel(c2), median(abs(c2), 'omitnan'), median(abs(ph), 'omitnan'));
end

%% ===================== Tables =====================
function table_arm(R, key, TR, lab)
% One RXET line per frame of the arm.
for k = 1:numel(R.F)
    F = R.F{k}; D = R.D{k};
    if isempty(F.ber), continue; end
    dc = dcfo(F);
    for f = 1:numel(F.ber)
        x = blank(R.NR, R.NB, R.NV); if numel(D) >= f, x = D(f); end
        tr = nan(1, R.NR); es = NaN;
        if ~isempty(TR) && numel(TR) >= k && ~isempty(TR{k}) && size(TR{k}.tr, 2) >= f
            tr = TR{k}.tr(:, f)'; es = TR{k}.es(f);
        end
        nfl = NaN; if any(~isnan(x.f)), nfl = sum(x.f, 'omitnan'); end
        t = twin_sum(x, R.tq, R.sr);
        fprintf(['RXET %s %2d dB run %3d fr %2d ber %.4f fer %d dcfo %+6.0f pe %.3f | hsel %g d %g deq-d %g fc %.0f ff %.0f jb %g Ew %.4f ' ...
            '| p1 applied %.0f slope %.0f b %.0f a %.0f f %.0f resid %.2f | p2 applied %.0f slope %.0f b %.0f a %.0f f %.0f resid %.2f ' ...
            '| s2 %.1f Gt %s | ga max %s min %s | flags %g | sy2 %.1f sy8 %.3f pmse %.3f ' ...
            '| twin ga2-c2 max %.2f misfit max %.2f train %.2f true resid f %s Hz nonlin %.2f | true train %s EsN0 %.1f\n'], ...
            lab, key(k, 1), key(k, 2), f, F.ber(f), F.fer(f), dc(f), F.pe(f), ...
            x.y(1:7), x.p(1, :), x.p(2, :), x.t(1), vec(x.t(2:end)), vec(x.g(1:2:end)), vec(x.g(2:2:end)), nfl, ...
            x.s(1), x.s(2), x.s(3), t.gerr, t.mis, t.mis0, vec0(t.fr), t.nl, vec(tr), es);
    end
end
end

function dc = dcfo(F)
% Each frame's frequency against the flight's clean-frame median [Hz].
ok = F.ber < 1e-3 & F.pe < 0.3;
if nnz(ok) < 3, ok = F.pe < 0.3; end
dc = F.cfo - median(F.cfo(ok));
end

function blocks(R, ARMS, key, nm, NM, TR)
% RXEB lines per pilot block and RXEL lines per block and antenna for the named frames, every
% frame with BER > 0.05 in any arm and the first 3 clean frames of every flight (in 'log').
nk = numel(R{1}.F); pick = cell(nk, 1);
for k = 1:nk
    F1 = R{1}.F{k}; if isempty(F1.ber), continue; end
    cl = find(F1.ber < 1e-3 & F1.pe < 0.3, 3);
    hi = [];
    for a = 1:numel(R)
        if numel(R{a}.F) >= k && ~isempty(R{a}.F{k}.ber), hi = union(hi, find(R{a}.F{k}.ber > 0.05)); end
    end
    pick{k} = union(hi(:)', cl(:)');
end
for c = 1:size(NM, 1)
    if nm(c) > 0, pick{nm(c)} = union(pick{nm(c)}, NM(c, 3)); end
end
for k = 1:nk
    for f = pick{k}(:)'
        for a = 1:numel(R)
            if numel(R{a}.D) < k || numel(R{a}.D{k}) < f, continue; end
            x = R{a}.D{k}(f); NB = size(x.b, 1); NR = size(x.l, 2);
            for b = 1:NB
                tb = NaN; if ~isempty(TR) && numel(TR) >= k && ~isempty(TR{k}), tb = TR{k}.blk(:, b, f)'; end
                fprintf('RXEB %s %2d dB run %3d fr %2d blk %2d rb/med %.2f built-flag %g applied %g ga2 %s true %s\n', ...
                    ARMS{a, 1}, key(k, 1), key(k, 2), f, b, x.b(b, 1), x.b(b, 2), x.f(b), vec(x.b(b, 3:end)), vec(tb));
            end
            if all(isnan(x.l(:))), continue; end
            for b = 0:NB
                for an = 1:NR
                    gm = NaN; if b > 0, gm = x.b(b, 2 + an); end
                    fprintf('RXEL %s %2d dB run %3d fr %2d blk %2d ant %d c2 %.2f ph %.3f misfit %.2f ga2 %.2f lags %s\n', ...
                        ARMS{a, 1}, key(k, 1), key(k, 2), f, b, an, x.l(b + 1, an, 1), x.l(b + 1, an, 2), x.l(b + 1, an, 3), ...
                        gm, vec(squeeze(x.l(b + 1, an, 4:end))));
                end
            end
        end
    end
end
end

function reading(R, ARMS, key, nm, NM, TR)
% The rule's reading of the three frames, computed mechanically; the reading note decides.
na = numel(R); rec = nan(na, 6); nfe = nan(na, 1); bs = nan(na, 1);
for a = 1:na
    bs(a) = sum(R{a}.ber);
    nfe(a) = round(sum(cellfun(@(F) sum(F.fer, 'omitnan'), R{a}.F)));   % lost frames over the 27 flights
    for c = 1:6
        if nm(c) > 0 && numel(R{a}.fb) >= nm(c) && numel(R{a}.fb{nm(c)}) >= NM(c, 3)
            rec(a, c) = R{a}.fb{nm(c)}(NM(c, 3));
        end
    end
    fprintf('RXE READ %-6s three frames BER %s recovered %d | reported 426/9 %.3f 511/12 %.3f 411/4 %.3f | frames lost %d BER sum %.4f\n', ...
        ARMS{a, 1}, vec(rec(a, 1:3)), nnz(rec(a, 1:3) <= 0.05), rec(a, 4:6), nfe(a), bs(a));
end
nrec = sum(rec(:, 1:3) <= 0.05, 2);
names = struct('twinf', 'the frequency estimate', 'twing', 'the template estimate (Gt and the kn of ga)', ...
    'twin', 'the frequency and template estimates together');
for a = 2:na
    fprintf('RXE READ rung %-5s recovers %d of 3\n', ARMS{a, 1}, nrec(a));
end
n = @(t) nrec(strcmp(ARMS(:, 1), t));
if n('twinf') >= 2 && n('twing') >= 2, nmd = 'the frequency estimate and the template estimate (each alone)';
elseif n('twinf') >= 2, nmd = names.twinf;
elseif n('twing') >= 2, nmd = names.twing;
elseif n('twin') >= 2, nmd = names.twin;
else, nmd = 'none: the cause lies after the estimates (gain smoothing or the equalizer)';
end
fprintf('RXE READ D2 names (reading d): %s\n', nmd);
% the twin's summary on the named frames, every arm
for c = 1:6
    if nm(c) == 0, continue; end
    k = nm(c); f = NM(c, 3);
    for a = 1:na
        if numel(R{a}.D) < k || numel(R{a}.D{k}) < f || numel(R{a}.F{k}.ber) < f, continue; end
        t = twin_sum(R{a}.D{k}(f), R{a}.tq, R{a}.sr);
        dc = dcfo(R{a}.F{k});
        fprintf(['RXE READ named %2d dB run %3d frame %2d %-6s BER %.4f dcfo %+6.0f Hz | twin ga2-c2 max %.2f dB misfit max %.2f ' ...
            'train %.2f | true resid f %s Hz nonlin %.2f rad\n'], NM(c, :), ARMS{a, 1}, R{a}.F{k}.ber(f), dc(f), t.gerr, t.mis, ...
            t.mis0, vec0(t.fr), t.nl);
    end
    if ~isempty(TR) && numel(TR) >= k && ~isempty(TR{k}) && size(TR{k}.tr, 2) >= f
        gap = (TR{k}.tr(:, f) - max(TR{k}.blk(:, :, f), [], 2))';
        fprintf('RXE READ named %2d dB run %3d frame %2d true training minus strongest block per antenna %s dB\n', NM(c, :), vec(gap));
    end
end
end

%% ===================== Census =====================
function [g3, CS] = census(p0, ARMS, mdl, p)
% The arms on the validation cells none, tone_jamming and jamming (lecturer states: clean,
% narrowband, wideband) at their nominal level, on 10 split-2 geometries of the policy pools
% each (seed block 5, geometries 1-6 per Eb/N0, build_policy_pools.m): geometries 1-3 at
% 9 dB, 1-4 at 12 dB and 1-3 at 15 dB, the same for every cell. Counts per cell and rung the
% frames the rung decodes (BER <= 0.05) and the as-built receiver ('log') loses (BER > 0.1).
Cd = decision_config();
cells = {'none', 'clean'; 'tone_jamming', 'narrowband'; 'jamming', 'wideband'};
EB = [9 3; 12 4; 15 3];                                % Eb/N0 [dB] and geometries 1..n there
vr = [p0.speed_kmh_min p0.speed_kmh_max];
FL = struct('e', {}, 'run', {}, 'seed', {}, 'speed', {});
for i = 1:size(EB, 1)
    s = find(p0.EbNo_dB == EB(i, 1), 1);
    assert(~isempty(s), 'rx_d2: %g dB is not on the Eb/N0 grid', EB(i, 1));
    g = pool_geometries(s, 5, 1:6, vr, p0);
    for r = 1:EB(i, 2)
        FL(end + 1) = struct('e', EB(i, 1), 'run', g.run(r), 'seed', g.seed(r), 'speed', g.speed(r)); %#ok<AGROW>
    end
end
key = [[FL.e]', [FL.run]'];
fprintf('RXE CENSUS flights %d per cell: %s\n', numel(FL), strjoin(arrayfun(@(f) sprintf('%d/%d (seed %d, %.1f km/h)', ...
    f.e, f.run, f.seed, f.speed), FL, 'UniformOutput', false), ', '));
na = size(ARMS, 1); g3 = true;
CS = struct('cell', {}, 'state', {}, 'arm', {}, 'n', {}, 'lost_r1', {}, 'lost', {}, 'won', {}, 'harm', {}, 'fb', {});
for c = 1:size(cells, 1)
    th = cells{c, 1};
    pc = threat_params(p0, th, Cd.nominal, Cd);
    [CC, ~, ~] = pool_configs(pc, th, {'no_action'}); q = CC(1).p; g_db = CC(1).g_db;
    fprintf('RXE CENSUS cell %s (lecturer state %s), level index %d, Eb/N0 offset %.2f dB, combiner %s\n', th, cells{c, 2}, ...
        Cd.nominal, g_db, q.rx_combiner);
    RC = cell(na, 1);
    for a = 1:na
        qa = q; qa.rx_ne_fix = ARMS{a, 2}; qa.own_out = true;
        lab = sprintf('%s/%s', th, ARMS{a, 1});
        [RC{a}, ok] = run_arm(lab, qa, g_db, FL, {}, mdl, p, 0, false);
        g3 = g3 && ok;
        table_arm(RC{a}, key, [], lab);
    end
    b1 = [RC{1}.fb{:}];
    for a = 1:na
        ba = [RC{a}.fb{:}];
        n = min(numel(b1), numel(ba));
        if numel(b1) ~= numel(ba), fprintf('RXE CENSUS %s %s: %d frames against %d as built\n', th, ARMS{a, 1}, numel(ba), numel(b1)); end
        won = ba(1:n) <= 0.05 & b1(1:n) > 0.1;
        harm = ba(1:n) > 0.1 & b1(1:n) <= 0.05;
        CS(end + 1) = struct('cell', th, 'state', cells{c, 2}, 'arm', ARMS{a, 1}, 'n', n, 'lost_r1', nnz(b1(1:n) > 0.1), ...
            'lost', nnz(ba(1:n) > 0.1), 'won', nnz(won), 'harm', nnz(harm), 'fb', {RC{a}.fb}); %#ok<AGROW>
        fprintf(['RXEC %s (%s) %-6s frames %d | as built loses (BER > 0.1) %d | this arm loses %d | decodes (BER <= 0.05) ' ...
            'where as built loses %d (%.2f%% of frames) | loses where as built decodes %d\n'], th, cells{c, 2}, ARMS{a, 1}, n, ...
            nnz(b1(1:n) > 0.1), nnz(ba(1:n) > 0.1), nnz(won), 100 * nnz(won) / max(n, 1), nnz(harm));
        if a > 1 && any(won)
            fr = frame_index(RC{a}.fb, key);
            for i = find(won)
                fprintf('RXECF %s %s %2d dB run %3d fr %2d as built BER %.4f this arm %.4f\n', th, ARMS{a, 1}, fr(i, :), b1(i), ba(i));
            end
        end
    end
end
end

function fr = frame_index(fb, key)
% [Eb/N0, run, frame] of every frame of the flights' concatenated BER rows.
fr = zeros(0, 3);
for k = 1:numel(fb)
    n = numel(fb{k});
    fr = [fr; repmat(key(k, :), n, 1), (1:n)']; %#ok<AGROW>
end
end

%% ===================== Helpers =====================
function s = rx_text(q, mdl)
build_threat_model(q);
ch = sfroot().find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/Rx']);
s = ch.Script;
end

function s = strip_prints(s)
% the script without its fprintf lines and without the print-only functions appended last
k = find(startsWith(s, 'function v = rxd_'), 1);
if ~isempty(k), s = s(1:k - 1); end
s = s(~startsWith(strtrim(s), 'fprintf('));
end

function s = core_text(s)
% the script's lines without prints, print-only functions and trailing blank lines
s = strip_prints(splitlines(s));
k = find(strlength(strtrim(s)) > 0, 1, 'last');
s = s(1:k);
end

function s = tok_only(s)
% the arm's tokens without 'log'
t = setdiff(strsplit(s, '+'), {'log'}, 'stable');
if isempty(t), s = 'off'; else, s = strjoin(t, '+'); end
end

function h = sha256_file(f)
% sha256 of a text file with its line ends as LF.
fid = fopen(f, 'r'); assert(fid > 0, 'rx_d2: cannot read %s', f);
u = fread(fid, Inf, '*uint8'); fclose(fid);
u = u(u ~= 13);
try
    md = java.security.MessageDigest.getInstance('SHA-256');
    md.update(typecast(u(:), 'int8'));
    h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
catch
    t = [tempname '.bin']; fid = fopen(t, 'w'); fwrite(fid, u, 'uint8'); fclose(fid);
    [~, o] = system(['certutil -hashfile "' t '" SHA256']);
    m = regexp(strrep(o, ' ', ''), '[0-9a-fA-F]{64}', 'match', 'once');
    h = lower(m);
end
end

function s = vec(v)
s = ['[' strjoin(arrayfun(@(x) sprintf('%.2f', x), v(:)', 'UniformOutput', false), ' ') ']'];
end

function s = vec0(v)
s = ['[' strjoin(arrayfun(@(x) sprintf('%.0f', x), v(:)', 'UniformOutput', false), ' ') ']'];
end

function s = strjoin_or(c)
if isempty(c), s = '(none)'; else, s = strjoin(sort(c), '+'); end
end

function s = pf(t)
if t, s = 'PASS'; else, s = 'FAIL'; end
end

function y = ternary(c, a, b)
if c, y = a; else, y = b; end
end
