function rx_d3(root, rxroot, t0)
%RX_D3  D3, the per-block genie of the delay-line receiver, and its fresh frames, on validation
%   data only, under rxroot\docs\rx_fix_rule3.md (its sha256 and that of
%   root\fix\build_threat_model.m are checked before anything runs):
%   1. the fresh frames (rule 2), on the export (field absent, own_out on), before the fix
%      file is on the path: flights 2 400 000 + k, k = 1-150 (then 151-300 while fewer than 3
%      frames), 12 dB, 100-161 km/h; a frame enters when its BER > 0.1 and its true post-MRC
%      Es/N0 >= 8 dB (own component, >= 3 clean frames of its flight); the list goes to
%      results\rx_fresh3_frames.txt with its sha256 and is committed as
%      rxroot\docs\rx_fresh3_frames.txt (that file only); a list committed before is closed
%      and kept;
%      the pool flies only if the dispatch (started at t0) has used at most 55 min;
%   2. only after that commit, and only if this harness has used at most 30 min: the text and
%      wiring guards, then the arms 'log', 'twinb', 'twinb+twinf', 'twinb+eqt' and
%      'twinb+twinf+eqt' (each with 'log', own_out on) on the 27 part-B flights with their
%      saved seeds, and the flat channel off against 'twinb+twinf+log', 'twinb+eqt+log' and
%      'twinb+twinf+eqt+log' (G4); no run starts after this harness has used 55 min;
%   3. the per-block lines, the reading of rule 1.4 and the reported lines.
%   root    the link-floor folder (src = the export, data, results, fix)
%   rxroot  the rx-ne-fix worktree (docs\rx_fix_rule3.md, code\link\build_threat_model.m)
%   t0      datenum of the dispatch's start (default: now)
% Line tags: RULE (registered hashes), RX3 (runs, fresh frames, guards, reading), RX3T (one
% line per frame and arm), RX3B (per pilot block), RX3L (the twin's lag profile per block and
% antenna).
RULE_SHA = 'd058fd366799a61632ee529938ef572347e62032e56595277d1e5981c0deeb19';
FIX_SHA = 'da8e3d9fc644495f877ab5b9b5c075d7e9d46b39ca7cab268ec85f5767d7f468';
if nargin < 3 || isempty(t0), t0 = now; end
t00 = tic;
used = @() (now - t0) * 1440;                          % minutes the dispatch has used
hused = @() toc(t00) / 60;                             % minutes this harness has used
rule = fullfile(rxroot, 'docs', 'rx_fix_rule3.md');
h = sha256_file(rule);
fprintf('RULE rx_fix_rule3.md sha256 %s\n', h);
if ~strcmp(h, RULE_SHA)
    error('rx_d3: rx_fix_rule3.md sha256 %s is not the registered %s; nothing run', h, RULE_SHA);
end
src = fullfile(root, 'src'); dat = fullfile(root, 'data'); out = fullfile(root, 'results'); fix = fullfile(root, 'fix');
hf = sha256_file(fullfile(fix, 'build_threat_model.m'));
fprintf('RULE fix build_threat_model.m sha256 %s\n', hf);
if ~strcmp(hf, FIX_SHA)
    error('rx_d3: fix build_threat_model.m sha256 %s is not the registered %s; nothing run', hf, FIX_SHA);
end
cd(src); addpath(fullfile(src, 'code')); setup_paths;
warning('off', 'Simulink:cgxe:LeakedJITEngine');
S0 = load(fullfile(dat, 'params.mat')); p0 = S0.params; p0.quiet_build = true;
p = p0; p.active_threat = 'none';
L = load(fullfile(out, 'link_floor_partA.mat')); A = L.A; L = load(fullfile(out, 'link_floor_partB.mat')); sel = L.sel;
mdl = 'UAV_GCS_Threat_Link';
[C, ~, ~] = pool_configs(p, 'none', {'no_action'}); pR = C(1).p; g_db = C(1).g_db;
assert(~isfield(pR, 'rx_ne_fix'), 'rx_d3: the params carry rx_ne_fix');
fprintf('RX3 start %s, dispatch used %.1f min, rx_dd_iter %d, n_rx %d, export file %s\n', datestr(now), used(), ...
    pR.rx_dd_iter, pR.n_rx, which('build_threat_model'));

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
    if isempty(k), fprintf('RX3 named frame %d dB run %d frame %d: not among the 27 flights\n', NM(c, :)); else, nm(c) = k; end
end
fprintf('RX3 flights %d, as-built BER27 sum %.4f\n', numel(FL), sum(cellfun(@mean, sv)));

% G2, first half: the export's script, built before the fix file is on the path
s_exp = rx_text(pR, mdl);

%% 1. The fresh frames (rule 2), on the export
[ok, cm] = fresh_frames(pR, g_db, p, mdl, out, rxroot, h, used);
if ~ok
    fprintf('RX3 D3 not started: the fresh list is not committed (rule 3, 2.4)\n');
    close_system(mdl, 0);
    fprintf('RX3 done %s (%.1f min; dispatch %.1f min)\n', datestr(now), toc(t00) / 60, used());
    return;
end
fprintf('RX3 FRESH committed %s; D3 may start\n', cm);
if hused() > 30
    fprintf('RX3 D3 not started: the harness has used %.1f min, more than 30 (rule 3, 5.3); it runs whole later\n', hused());
    close_system(mdl, 0);
    fprintf('RX3 done %s (%.1f min; dispatch %.1f min)\n', datestr(now), toc(t00) / 60, used());
    return;
end

%% 2. The fix file, text and wiring guards (G2)
addpath(fix); clear('build_threat_model');
fprintf('RX3 fix file %s\n', which('build_threat_model'));
hb = sha256_file(fullfile(rxroot, 'code', 'link', 'build_threat_model.m'));
fprintf('RX3 fix file sha256 %s, rx-ne-fix code/link/build_threat_model.m sha256 %s, equal %d, registered %d\n', hf, hb, ...
    strcmp(hf, hb), strcmp(hf, FIX_SHA));
q = pR; sa = rx_text(q, mdl);
q.rx_ne_fix = 'off'; so = rx_text(q, mdl);
q.rx_ne_fix = 'log'; sl = rx_text(q, mdl);
q = pR; q.own_out = true; q.rx_ne_fix = 'off'; soo = rx_text(q, mdl);
g2 = [isequal(sa, s_exp), isequal(so, s_exp), isequal(soo, s_exp), isequal(strip_prints(splitlines(sl)), splitlines(so))];
fprintf('RX3 G2 absent==export %d off==export %d off(own_out)==export %d log-minus-prints==off %d\n', g2);
ARMS = {'log', 'log'; 'twinb', 'twinb+log'; 'twinb+twinf', 'twinb+twinf+log'; 'twinb+eqt', 'twinb+eqt+log'; ...
    'twinb+twinf+eqt', 'twinb+twinf+eqt+log'};
na = size(ARMS, 1);
w0 = true;
for m = {'', 'off', 'log'}
    q = pR; q.own_out = true; if ~isempty(m{1}), q.rx_ne_fix = m{1}; end
    [n3, src3] = wiring(q, mdl);
    fprintf('RX3 G2 wiring %s: twin input %d, receiver inputs %d\n', ternary(isempty(m{1}), '(absent)', m{1}), ~isempty(src3), n3);
    w0 = w0 && n3 == 2 && isempty(src3);
end
w1 = true;
for a = 2:na
    q = pR; q.own_out = true; q.rx_ne_fix = ARMS{a, 2};
    [n3, src3] = wiring(q, mdl);
    fprintf('RX3 G2 wiring %s: receiver inputs %d, third from %s\n', ARMS{a, 2}, n3, src3);
    w1 = w1 && n3 == 3 && strcmp(src3, 'LevelTw <- Threat/4');
end
% each arm's script minus its prints equals its tokens' script without 'log'
ST = cell(na, 1);
for a = 1:na
    q = pR; q.own_out = true; q.rx_ne_fix = tok_only(ARMS{a, 2});
    try
        ST{a} = core_text(rx_text(q, mdl));
    catch err
        fprintf('RX3 G2 %s build error: %s\n', q.rx_ne_fix, getReport(err, 'basic'));
        ST{a} = {'(build error)'};
    end
end
G2 = all(g2) && strcmp(hf, hb) && strcmp(hf, FIX_SHA) && w0 && w1;
fprintf('RX3 G2 text and wiring -> %s\n', pf(G2));

%% 3. The arms on the 27 flights, then the flat channel (G4); no run starts after 55 min of the harness
R = cell(na, 1); G3 = false(na, 1); g2a = false(na, 1); TR = []; late = '';
for a = 1:na
    if hused() > 55, late = ARMS{a, 1}; break; end
    q = pR; q.rx_ne_fix = ARMS{a, 2}; q.own_out = true;
    [R{a}, G3(a)] = run_arm(ARMS{a, 1}, q, g_db, FL, sv, mdl, p, a == 1);
    g2a(a) = isequal(R{a}.core, ST{a});
    fprintf('RX3 G2 arm %s: script minus prints == %s minus prints %d\n', ARMS{a, 1}, tok_only(ARMS{a, 2}), g2a(a));
    if a == 1, TR = R{a}.truth; end
    table_arm(R{a}, key, TR, R{a}.lab);
    if a == 1 && ~any(~isnan(R{1}.fer))
        fprintf('RX3 GUARDS G1 FAIL G2 %s G3 FAIL G4 not run G5 not run G6 not run -> D3 void (the log arm did not run)\n', pf(G2 && g2a(1)));
        close_system(mdl, 0);
        fprintf('RX3 done %s (%.1f min; dispatch %.1f min)\n', datestr(now), toc(t00) / 60, used());
        return;
    end
end
pF = p; pF.tdl = false; pF.tdl_random = false;
[CF, ~, ~] = pool_configs(pF, 'none', {'no_action'}); qF = CF(1).p; gF = CF(1).g_db; qF.own_out = true;
FA = {'F-off', 'off'; 'F-twinb+twinf', 'twinb+twinf+log'; 'F-twinb+eqt', 'twinb+eqt+log'; ...
    'F-twinb+twinf+eqt', 'twinb+twinf+eqt+log'};
RF = cell(size(FA, 1), 1);
for i = 1:size(FA, 1)
    if ~isempty(late) || hused() > 55
        if isempty(late), late = FA{i, 1}; end
        break;
    end
    qF.rx_ne_fix = FA{i, 2};
    RF{i} = run_arm(FA{i, 1}, qF, gF, FL, sv, mdl, p, false);
end
if ~isempty(late)
    fprintf('RX3 arm %s not started: the harness has used %.1f min, more than 55 (rule 3, 5.3); D3 not finished, not read\n', ...
        late, hused());
    close_system(mdl, 0);
    fprintf('RX3 done %s (%.1f min; dispatch %.1f min)\n', datestr(now), toc(t00) / 60, used());
    return;
end
G2 = G2 && all(g2a);
fprintf('RX3 G2 arms: %d of %d arms are their tokens plus prints only -> G2 %s\n', nnz(g2a), na, pf(G2));
d1 = cellfun(@(x) x(1), R{1}.dsv);
G1 = numel(d1) == numel(FL) && all(d1 == 0) && R{1}.done;
fprintf('RX3 G1 as built (log) reproduces the saved frame BER on %d of %d flights (own_out on), max|d| %.1e -> %s\n', ...
    nnz(d1 == 0), numel(FL), max([d1, NaN]), pf(G1));
G4 = RF{1}.done;
dmax = [];
for i = 2:size(FA, 1)
    G4 = G4 && RF{i}.done && numel(RF{i}.z) == numel(FL);
    for k = 1:min(numel(RF{1}.z), numel(RF{i}.z))
        dz = Inf;
        if ~isempty(RF{1}.z{k}) && isequal(size(RF{i}.z{k}), size(RF{1}.z{k})) && isequal(size(RF{i}.fb{k}), size(RF{1}.fb{k}))
            dz = max([abs(RF{i}.z{k}(:) - RF{1}.z{k}(:)); abs(RF{i}.fb{k}(:) - RF{1}.fb{k}(:))]);
        end
        dmax(end + 1) = dz; %#ok<AGROW>
        fprintf('RX3 G4 %s %2d dB run %3d max|d| Rx_Z and frame BER %.1e\n', FA{i, 2}, key(k, :), dz);
    end
end
G4 = G4 && ~isempty(dmax) && all(dmax == 0);
fprintf('RX3 G4 F-off against F-twinb+twinf, F-twinb+eqt and F-twinb+twinf+eqt: %d comparisons, max|d| %.1e -> %s\n', ...
    numel(dmax), max([dmax, NaN]), pf(G4));
tb = find(startsWith(ARMS(:, 1), 'twinb'));
G5 = all(cellfun(@(x) x.truth_ok, R(tb)));
fprintf('RX3 G5 twinb arms with truth prints valid: %d of %d -> %s\n', nnz(cellfun(@(x) x.truth_ok, R(tb))), numel(tb), pf(G5));
% G6: every twinb arm's Rx_Z differs from the log arm's on at least one delay-line flight
nd = zeros(numel(tb), 1);
for i = 1:numel(tb)
    a = tb(i);
    for k = 1:min(numel(R{1}.z), numel(R{a}.z))
        nd(i) = nd(i) + (~isempty(R{1}.z{k}) && ~isempty(R{a}.z{k}) && ~isequaln(R{a}.z{k}, R{1}.z{k}));
    end
    fprintf('RX3 G6 %s Rx_Z differs from log on %d of %d flights\n', ARMS{a, 1}, nd(i), numel(FL));
end
G6 = ~isempty(tb) && all(nd > 0);
fprintf('RX3 G6 twinb arms whose Rx_Z differs from log on at least one flight: %d of %d -> %s\n', nnz(nd > 0), numel(tb), pf(G6));
for a = tb(:)', genie_level(R{a}); end

%% 4. Per-block lines, the reading
blocks(R, ARMS, key, nm, NM, TR);
reading(R, ARMS, key, nm, NM);
for a = 1:na, fprintf('RX3 G3 %s -> %s\n', ARMS{a, 1}, pf(G3(a))); end
G3 = all(G3);
fprintf('RX3 GUARDS G1 %s G2 %s G3 %s G4 %s G5 %s G6 %s -> D3 %s\n', pf(G1), pf(G2), pf(G3), pf(G4), pf(G5), pf(G6), ...
    ternary(G1 && G2 && G3 && G4 && G5 && G6, 'valid', 'void (nothing read; fix the harness or the code, rerun)'));
close_system(mdl, 0);
fb = cellfun(@(x) x.fb, R, 'UniformOutput', false);
save(fullfile(out, sprintf('rx_d3_%s.mat', datestr(now, 'yyyymmdd_HHMM'))), 'fb', 'key', 'NM', 'ARMS');
fprintf('RX3 done %s (%.1f min; dispatch %.1f min)\n', datestr(now), toc(t00) / 60, used());
end

%% ===================== Fresh frames (rule 2) =====================
function [ok, cm] = fresh_frames(q0, g_db, p, mdl, out, rxroot, hrule, used)
% The fresh flights 2 400 000 + k at 12 dB, speed 100 + 61 u km/h (u from the seed's speed
% stream), everything else the flight's own draw; r1 (the export, field absent), own_out on.
% A frame enters the list when its BER > 0.1 and its true post-MRC Es/N0 >= 8 dB, calibrated
% on >= 3 clean frames of its flight (BER < 1e-3, pilot error < 0.3). Batch 2 (k = 151-300)
% runs when batch 1 gives fewer than 3 frames; the list then closes. A flight error stops it
% with nothing written or committed. ok: the list is committed (now or before); cm its commit.
ok = false; cm = '';
E = 12; VR = [100 161]; BASE = 2400000; K = {1:150, 151:300};
doc = fullfile(rxroot, 'docs', 'rx_fresh3_frames.txt'); f = fullfile(out, 'rx_fresh3_frames.txt');
[st, o] = system(sprintf('git -C "%s" rev-list -1 HEAD -- docs/rx_fresh3_frames.txt', rxroot));
if st == 0 && ~isempty(regexp(o, '^[0-9a-f]{40}', 'once'))
    cm = strtrim(o);
    hd = sha256_file(doc);
    same = ~isfile(f) || strcmp(sha256_file(f), hd);
    ln = splitlines(strrep(fileread(doc), sprintf('\r'), ''));
    hok = numel(ln) >= 2 && strcmp(ln{2}, ['# rule rx_fix_rule3.md sha256 ' hrule]);   % written under the registered rule
    fprintf(['RX3 FRESH the list is closed: commit %s, sha256 %s, results copy equal %d, header names the registered ' ...
        'rule %d; not flown again\n'], cm, hd, same, hok);
    if ~hok, fprintf('RX3 FRESH the committed list was written under another rule text (rule 3, 2.4); it is not used\n'); end
    ok = same && hok;
    return;
end
if used() > 55
    fprintf('RX3 FRESH not flown: the dispatch has used %.1f min, more than 55 (rule 3, 5.2); the pool and D3 run later\n', used());
    return;
end
% the block meets no pool seed (rule 2.1, point 2): families 1-9, Eb/N0 index 1-19, blocks 1-19
[fa, sa, ba] = ndgrid(1:9, 1:19, 1:19);
hit = arrayfun(@(fi, si, bi) any(ismember(pool_seed(fi, si, bi, 1:100), BASE + (1:300))), fa(:), sa(:), ba(:));
fprintf('RX3 FRESH seeds %d-%d meet no pool seed (families 1-9, Eb/N0 index 1-19, blocks 1-19): %d\n', BASE + 1, ...
    BASE + 300, ~any(hit));
if any(hit)
    fprintf('RX3 FRESH stopped: the seed block is not fresh; nothing flown, written or committed\n');
    return;
end
q = q0; q.own_out = true;
build_threat_model(q);
set_link_snr(mdl, E + 10*log10(q.bits_per_symbol) - 10*log10(q.sps) + g_db, q);
Lf = frame_layout(q);
rows = {}; nfl = 0; nnc = 0; nnc0 = 0; ncand = 0; nb = 0; ta = tic;
for b = 1:numel(K)
    if b > 1 && numel(rows) >= 3, break; end
    nb = b;
    fprintf('RX3 FRESH batch %d: k %d-%d (dispatch used %.1f min)\n', b, K{b}(1), K{b}(end), used());
    for k = K{b}
        seed = BASE + k;
        v = VR(1) + rand(seed_stream(seed, 'speed')) * (VR(2) - VR(1));
        f1 = struct('e', E, 'run', k, 'seed', seed, 'speed', v);
        try
            so = sim_flight(mdl, q, p, f1, false);
            [F, ~] = extract_closed_loop_frames(so, q, 20);
            W = truth(so, mdl, q, F, Lf);
        catch err
            fprintf('RX3 FRESH k %d seed %d error: %s\n', k, seed, getReport(err, 'basic'));
            fprintf('RX3 FRESH stopped: nothing written or committed\n');
            return;
        end
        nfl = nfl + 1;
        fb = find(F.ber(:)' > 0.1);
        cal = W.ncal >= 3;
        nnc0 = nnc0 + ~cal;
        if isempty(fb), continue; end
        ncand = ncand + numel(fb); nnc = nnc + ~cal;
        fprintf('RX3 FRESH k %3d seed %d %.1f km/h: frames BER > 0.1 %s, clean frames %d, calibrated %d\n', k, seed, v, ...
            mat2str(fb), W.ncal, cal);
        for fr = fb
            es = W.es(fr);
            inn = cal && es >= 8;
            fprintf('RX3 FRESH k %3d frame %2d BER %.4f true EsN0 %5.1f dB -> %s\n', k, fr, F.ber(fr), es, ternary(inn, 'in', 'out'));
            if inn
                rows{end + 1} = sprintf('%d %d %d %d %.4f %.2f %.1f %d', E, k, seed, fr, F.ber(fr), es, v, W.ncal); %#ok<AGROW>
            end
        end
    end
end
txt = sprintf(['# rx_fresh3_frames: decision-free delay-line collapse frames on fresh validation flights (rx_fix_rule3.md section 2)\n' ...
    '# rule rx_fix_rule3.md sha256 %s\n' ...
    '# seeds 2400000 + k, k = 1-150 (batch 1), 151-300 (batch 2, only with fewer than 3 frames after batch 1); batches run %d\n' ...
    '# Eb/N0 12 dB; speed 100 + 61 u km/h, u = rand(seed_stream(seed, ''speed'')); altitude, K, interferer direction,\n' ...
    '#   correlation and event the flight''s own draws, 20 frames\n' ...
    '# link: link-floor data/params.mat, threat none, no_action (pool_configs), the export d4623ed (field absent), own_out on\n' ...
    '# criteria: r1 frame BER > 0.1 and true post-MRC Es/N0 >= 8 dB from the own component (Thr_sig), calibrated on\n' ...
    '#   >= 3 clean frames of the flight (BER < 1e-3, pilot error < 0.3); a flight with fewer gives no frame\n' ...
    '# flights examined %d (without calibration %d, %d of them with candidate frames), candidate frames %d, frames in %d\n' ...
    '# ebno_db k seed frame r1_ber true_esn0_db speed_kmh calibration_frames\n'], hrule, nb, nfl, nnc0, nnc, ncand, numel(rows));
if ~isempty(rows), txt = [txt sprintf('%s\n', rows{:})]; end
fprintf(['RX3 FRESH n %d (batches %d, flights %d, without calibration %d, %d of them with candidate frames, candidate ' ...
    'frames %d) in %.1f min\n'], numel(rows), nb, nfl, nnc0, nnc, ncand, toc(ta) / 60);
if isfile(f) && ~strcmp(strrep(fileread(f), sprintf('\r'), ''), txt)
    f2 = fullfile(out, sprintf('rx_fresh3_frames_%s.txt', datestr(now, 'yyyymmdd_HHMMSS')));
    write_text(f2, txt);
    fprintf('RX3 FRESH %s exists with other content (kept); this list went to %s; not committed\n', f, f2);
    return;
end
if ~isfile(f), write_text(f, txt); end
hl = sha256_file(f);
write_text([f '.sha256'], sprintf('%s *%s\n', hl, f));
fprintf('RX3 FRESH list %s sha256 %s\n', f, hl);
% the same text committed in rx-ne-fix, that file only
write_text(doc, txt);
msg = 'rx_fresh3_frames: the fresh delay-line collapse frames of rx_fix_rule3.md section 2, written before D3';
[s1, o1] = system(sprintf('git -C "%s" add -- docs/rx_fresh3_frames.txt', rxroot));
[s2, o2] = system(sprintf(['git -C "%s" commit -m "%s" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" ' ...
    '-- docs/rx_fresh3_frames.txt'], rxroot, msg));
[s3, o3] = system(sprintf('git -C "%s" rev-parse HEAD', rxroot));
[s4, o4] = system(sprintf('git -C "%s" show --name-only --format= HEAD', rxroot));
[s5, o5] = system(sprintf('git -C "%s" show HEAD:docs/rx_fresh3_frames.txt', rxroot));
only = strcmp(strtrim(o4), 'docs/rx_fresh3_frames.txt');
same = s5 == 0 && strcmp(strrep(o5, sprintf('\r'), ''), txt);
ok = s1 == 0 && s2 == 0 && s3 == 0 && s4 == 0 && only && same;
cm = strtrim(o3);
fprintf('RX3 FRESH commit %s: add %d commit %d, that file only %d, committed text equal %d -> %s\n', cm, s1, s2, only, ...
    same, ternary(ok, 'committed', 'FAILED'));
if ~ok, fprintf('RX3 FRESH git output: %s | %s\n', strtrim(o1), strtrim(o2)); end
end

%% ===================== One arm =====================
function [R, g3] = run_arm(lab, q, g_db, FL, sv, mdl, p, want_truth)
% One build, the flights FL with their seeds at their Eb/N0; the frames, the receiver's prints
% and (want_truth) the own component's powers. sv: the saved frame BER per flight.
R = struct('lab', lab, 'fb', {{}}, 'fer', [], 'ber', [], 'z', {{}}, 'F', {{}}, 'D', {{}}, 'dsv', {{}}, ...
    'truth', {{}}, 'done', false, 'truth_ok', false, 'nprint', 0, 'nframes', 0, 'nbit_ok', 0, 'nbit', 0, 'ntw_ok', 0, ...
    'NR', q.n_rx, 'NB', 0, 'NV', 0, 'nbits', q.frame_length, 'core', {{}}, 'tq', [], 'sr', q.symbol_rate);
g3 = false; ta = tic;
try
    build_threat_model(q);
    ch = sfroot().find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/Rx']); s = ch.Script;
catch err
    fprintf('RX3 %s build error: %s\n', lab, getReport(err, 'basic'));
    return;
end
R.core = core_text(s);
tk = {};
if isfield(q, 'rx_ne_fix'), tk = strsplit(lower(q.rx_ne_fix), '+'); end
tk = setdiff(tk, {'off'});
st = steps_on(s);
match = isempty(setxor(st, tk));
fprintf('RX3 %s tokens ON: %s (requested %s) -> match %d\n', lab, strjoin_or(st), strjoin_or(tk), match);
Lf = frame_layout(q); NB = numel(Lf.pil_center); NR = q.n_rx; R.NB = NB;
tp = rx_taps(q); NRK = sum(tp.lags) + 1; R.NV = 3 + NRK;
R.tq = [(1 + tp.lags(2) + Lf.n_pre - tp.lags(1)) / 2; Lf.pil_center(:) - Lf.NQ];   % training and block centres [symbols]
logon = any(strcmp(st, 'log')) && tp.ne > 1;   % the prints exist on the delay line only
twin = getSimulinkBlockHandle([mdl '/LevelTw']) ~= -1;
for k = 1:numel(FL)
    f1 = FL(k); e = f1.e;
    try
        set_link_snr(mdl, e + 10*log10(q.bits_per_symbol) - 10*log10(q.sps) + g_db, q);
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
            fprintf('RX3 %s %2d dB run %3d: %d print frames for %d frames (prints not used for this flight)\n', lab, e, f1.run, numel(D), nf);
            D = parse_rx('', NR, NB, R.NV);
        end
        dsv = NaN;
        if numel(sv) >= k && ~isempty(sv{k})
            n = min(nf, numel(sv{k}));
            dsv = max(abs(F.ber(1:n) - sv{k}(1:n)));
        end
        R.fb{k} = F.ber(:)'; R.fer(k) = mean(F.fer, 'omitnan'); R.ber(k) = mean(F.ber, 'omitnan');
        R.F{k} = struct('ber', F.ber(:)', 'fer', F.fer(:)', 'cfo', F.cfo_hz(:)', 'pe', F.pilot_err(:)', 'sd', F.sync_d(:)', ...
            'gain_ant', F.gain_ant, 'rq', F.rq);
        R.D{k} = D; R.dsv{k} = dsv;
        R.z{k} = so.get('Rx_Z');
        if numel(D) == nf
            nbe = arrayfun(@(x) x.s(4), D);
            R.nbit = R.nbit + nf; R.nbit_ok = R.nbit_ok + nnz(abs(nbe(:)' / q.frame_length - F.ber(:)') < 1e-12);
        end
        if want_truth, R.truth{k} = truth(so, mdl, q, F, Lf); end
        fprintf('RX3 %s %2d dB run %3d ber %.2e fer %.2f | max|d| vs saved %.1e | frames > 0.05: %s\n', lab, e, f1.run, ...
            R.ber(k), R.fer(k), dsv, mat2str(find(F.ber > 0.05)));
    catch err
        fprintf('RX3 %s %2d dB run %3d error: %s\n', lab, e, f1.run, getReport(err, 'basic'));
        R.fb{k} = []; R.fer(k) = NaN; R.ber(k) = NaN; R.D{k} = parse_rx('', NR, NB, R.NV); R.dsv{k} = NaN; R.z{k} = [];
        R.F{k} = struct('ber', [], 'fer', [], 'cfo', [], 'pe', [], 'sd', [], 'gain_ant', [], 'rq', []);
        if k == 1, fprintf('RX3 %s flight 1 failed: arm not run\n', lab); break; end
    end
end
R.done = numel(R.fb) == numel(FL) && all(~isnan(R.fer));
R.truth_ok = ~logon || (R.nbit == R.nframes && R.nbit_ok == R.nbit);   % txbits belong to the printed frames
if logon
    fprintf('RX3 %s prints: %d frames printed for %d frames; chart bit errors agree with the frame BER on %d of %d\n', ...
        lab, R.nprint, R.nframes, R.nbit_ok, R.nbit);
    fprintf('RX3 %s truth prints valid %d\n', lab, R.truth_ok);
end
tw_ok = true;
if twin
    tw_ok = R.ntw_ok == numel(FL);
    fprintf('RX3 %s twin gain equal to the gain Level on %d of %d flights\n', lab, R.ntw_ok, numel(FL));
end
nfe = sum(cellfun(@(F) sum(F.fer, 'omitnan'), R.F));
fprintf('RX3 %s FER %.4f (%d frames lost) BER sum %.4f flights %d (%.1f min)\n', lab, mean(R.fer), round(nfe), sum(R.ber), ...
    numel(R.fer), toc(ta) / 60);
fprintf('RX3 %s done\n', lab);
g3 = match && R.done && tw_ok && R.truth_ok;
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
                fprintf(['RX3 receiver prints: evalc and diary caught none; the per-step prints are dropped by the ' ...
                    'simulation target from here; the BER-based results go on\n']);
            else
                fprintf('RX3 receiver prints: evalc caught none; capture by %s from here\n', mode);
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
        case 'RXA', v = pad(v, 1 + NR); if v(1) >= 1 && v(1) <= NB, cur.a(v(1), :) = v(2:end); end
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
x = struct('y', nan(1, 7), 'p', nan(2, 6), 't', nan(1, NR + 1), 'b', nan(NB, 2 + NR), 'a', nan(NB, NR), ...
    'g', nan(1, 2 * NR), 'f', nan(1, NB), 'n', nan(1, NB), 'h', nan(1, 4), 's', nan(1, 4), 'l', nan(NB + 1, NR, NV));
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
if contains(s, 'Gb = twin_blocks(yxt,')
    st{end + 1} = 'twinb';
    if ~contains(s, 'Fb(:, b) = le_taps(Gb(:, :, b), s2, NE);'), st{end + 1} = 'eqt'; end
end
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

function genie_level(R)
% Reported only: on the clean frames (BER < 1e-3), the twin's multiple c of the receiver's
% template on the training against 1, and on the antenna-blocks where the template fits the
% twin (misfit <= -10 dB) c_b against the measured gain ga (rule 3, 1.3 (f3) and (f3b) on the
% 27 flights)
c0 = []; p0 = []; dc = []; dp = [];
for k = 1:numel(R.F)
    F = R.F{k}; D = R.D{k};
    if isempty(F.ber) || numel(D) ~= numel(F.ber), continue; end
    for f = find(F.ber < 1e-3)
        x = D(f);
        c0 = [c0, x.l(1, :, 1)]; p0 = [p0, x.l(1, :, 2)]; %#ok<AGROW>
        for b = 1:size(x.b, 1)
            for a = 1:size(x.l, 2)
                if ~(x.l(b + 1, a, 3) <= -10), continue; end
                dc(end + 1) = x.l(b + 1, a, 1) - x.b(b, 2 + a); %#ok<AGROW>
                dp(end + 1) = angle(exp(1j * (x.l(b + 1, a, 2) - x.a(b, a)))); %#ok<AGROW>
            end
        end
    end
end
fprintf(['RX3 %s genie on the clean frames: training %d frame-antennas, median |c2| %.2f dB, median |angle c| %.3f rad | ' ...
    'blocks %d antenna-blocks with misfit <= -10 dB, median |c2/ga2| %.2f dB, median |angle(c/ga)| %.3f rad\n'], R.lab, ...
    numel(c0), median(abs(c0), 'omitnan'), median(abs(p0), 'omitnan'), numel(dc), median(abs(dc), 'omitnan'), ...
    median(abs(dp), 'omitnan'));
end

%% ===================== Tables =====================
function table_arm(R, key, TR, lab)
% One RX3T line per frame of the arm.
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
        fprintf(['RX3T %s %2d dB run %3d fr %2d ber %.4f fer %d dcfo %+6.0f pe %.3f | hsel %g d %g deq-d %g fc %.0f ff %.0f jb %g Ew %.4f ' ...
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
% RX3B lines per pilot block and RX3L lines per block and antenna for the named frames, every
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
                fprintf('RX3B %s %2d dB run %3d fr %2d blk %2d rb/med %.2f built-flag %g applied %g ga2 %s ga ph %s true %s\n', ...
                    ARMS{a, 1}, key(k, 1), key(k, 2), f, b, x.b(b, 1), x.b(b, 2), x.f(b), vec(x.b(b, 3:end)), ...
                    vec(x.a(b, :)), vec(tb));
            end
            if all(isnan(x.l(:))), continue; end
            for b = 0:NB
                for an = 1:NR
                    gm = NaN; gp = NaN; if b > 0, gm = x.b(b, 2 + an); gp = x.a(b, an); end
                    fprintf('RX3L %s %2d dB run %3d fr %2d blk %2d ant %d c2 %.2f ph %.3f misfit %.2f ga2 %.2f ga ph %.3f lags %s\n', ...
                        ARMS{a, 1}, key(k, 1), key(k, 2), f, b, an, x.l(b + 1, an, 1), x.l(b + 1, an, 2), x.l(b + 1, an, 3), ...
                        gm, gp, vec(squeeze(x.l(b + 1, an, 4:end))));
                end
            end
        end
    end
end
end

function reading(R, ARMS, key, nm, NM)
% Rule 3, 1.4, computed mechanically, at one frequency: r1's when 'twinb' or 'twinb+eqt'
% recovers (BER <= 0.05) at least 2 of the three frames (n_p from 'twinb', n_e from
% 'twinb+eqt'), else the twin's (n_p from 'twinb+twinf', n_e from 'twinb+twinf+eqt'); the
% reading note decides.
na = numel(R); rec = nan(na, 6); nfe = nan(na, 1); bs = nan(na, 1);
for a = 1:na
    bs(a) = sum(R{a}.ber);
    nfe(a) = round(sum(cellfun(@(F) sum(F.fer, 'omitnan'), R{a}.F)));   % lost frames over the 27 flights
    for c = 1:6
        if nm(c) > 0 && numel(R{a}.fb) >= nm(c) && numel(R{a}.fb{nm(c)}) >= NM(c, 3)
            rec(a, c) = R{a}.fb{nm(c)}(NM(c, 3));
        end
    end
    fprintf(['RX3 READ %-15s three frames BER %s recovered %d | reported 426/9 %.3f 511/12 %.3f 411/4 %.3f | ' ...
        'FER27 %.4f (%d frames lost) BER27 sum %.4f\n'], ARMS{a, 1}, vec(rec(a, 1:3)), nnz(rec(a, 1:3) <= 0.05), ...
        rec(a, 4:6), mean(R{a}.fer), nfe(a), bs(a));
end
nrec = sum(rec(:, 1:3) <= 0.05, 2);
n = @(t) nrec(strcmp(ARMS(:, 1), t));
for t = {'twinb', 'twinb+eqt', 'twinb+twinf', 'twinb+twinf+eqt'}
    fprintf('RX3 READ %-15s recovers %d of 3\n', t{1}, n(t{1}));
end
tw = max(n('twinb'), n('twinb+eqt')) < 2;             % read at the twin's frequency
if tw, ap = 'twinb+twinf'; ae = 'twinb+twinf+eqt'; else, ap = 'twinb'; ae = 'twinb+eqt'; end
ne = n(ae); np = n(ap);
if ne >= 2 && np >= 2
    rd = 'a model that follows the shape suffices with the linear equalizer';
    cl = ['a frame-long time-varying channel per antenna and per lag, decision-free in the first pass, ' ...
        'with per-block combining and per-block equalizer design'];
elseif np >= 2
    rd = 'the equalizer design must follow the model';
    cl = 'the same class; the per-block equalizer design is a required part of it';
elseif ne >= 2
    rd = 'the model suffices; the per-block equalizer design as computed does not';
    cl = 'the same channel and per-block combining, with the training-designed equalizer kept';
else
    rd = 'none: the 21-tap linear equalizer structure is the limit';
    cl = 'the equalizer structure, designed and read under this rule';
end
fprintf('RX3 READ D3 reads (rule 3, 1.4) at %s frequency: n_e %d (%s) n_p %d (%s) -> %s | candidate class: %s\n', ...
    ternary(tw, 'the twin''s', 'r1''s'), ne, ae, np, ap, rd, cl);
fq = tw && (ne >= 2 || np >= 2);
fprintf('RX3 READ frequency (rule 3, 1.4): %s\n', ternary(fq, ['read at the twin''s frequency, not the last row: the class ' ...
    'also replaces the first-pass frequency step by an estimate that does not ride on the frozen template; stage 1d applies'], ...
    'not applied'));
% reported: the twin truth on the named frames, every arm, with the hold's phase bound
for c = 1:6
    if nm(c) == 0, continue; end
    k = nm(c); f = NM(c, 3);
    for a = 1:na
        if numel(R{a}.D) < k || numel(R{a}.D{k}) < f || numel(R{a}.F{k}.ber) < f, continue; end
        t = twin_sum(R{a}.D{k}(f), R{a}.tq, R{a}.sr);
        dc = dcfo(R{a}.F{k});
        fprintf(['RX3 READ named %2d dB run %3d frame %2d %-15s BER %.4f dcfo %+6.0f Hz | twin ga2-c2 max %.2f dB misfit max %.2f ' ...
            'train %.2f | true resid f %s Hz nonlin %.2f rad | hold phase at a segment edge pi |f| 52 / SR %s rad\n'], NM(c, :), ...
            ARMS{a, 1}, R{a}.F{k}.ber(f), dc(f), t.gerr, t.mis, t.mis0, vec0(t.fr), t.nl, vec(pi * abs(t.fr) * 52 / R{a}.sr));
    end
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
fid = fopen(f, 'r'); assert(fid > 0, 'rx_d3: cannot read %s', f);
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

function write_text(f, txt)
fid = fopen(f, 'w'); assert(fid > 0, 'rx_d3: cannot write %s', f);
fwrite(fid, txt, 'char'); fclose(fid);
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
