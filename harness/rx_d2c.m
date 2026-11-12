function rx_d2c(root, rxroot, bwroot)
%RX_D2C  D2c, the r1 census on CORE_BW's core configurations (rx_fix_rule3.md section 4): how
%   often the receiver as built (field absent) loses a frame the link should carry, on the
%   restored link of the two jammed states, on CORE_BW's validation geometries rebuilt from
%   the code. No CORE_BW data or results file is opened; blocks 14 (test), 7 (set D) and the
%   smoke blocks 16, 18 and 19 are never flown.
%   rx_d2c(root, rxroot, bwroot)
%   root    the D2c folder (rule 4.2: <main>\worktrees\d2c, this file copied there): src = a
%           read-only export of uav-gcs-v7-bw at f84384c (git archive), data\params.mat = a
%           copy of the -bw tree's params.mat, results = this harness's output
%   rxroot  the rx-ne-fix worktree (docs\rx_fix_rule3.md)
%   bwroot  the -bw tree (default C:\Users\Adi Suliman\uav-gcs-v7-bw): only its params.mat is
%           read, for its sha256
%   Cells: CORE_BW's fixed-total cells at JSR_tot 16, 23 and 30 dB of the CW tone (narrowband)
%   and of the 4, 20, 70 and 83.5 MHz barrage (wideband). Configurations, the core set without
%   no_action: CW, 4 and 20 MHz channel_switch and channel_switch+rate_reduce at the lowest
%   layer an escaped H1 hop meets (24, 12.6 and 17.5 dB, each asserted in the cell's own grid)
%   and rate_reduce; 70 and 83.5 MHz rate_reduce. Geometries: family 6, block 5, 72 per Eb/N0:
%   1-12 with CORE_BW's Latin hypercube (stream 7 200 000 + 100 s + 1), 13-72 with each
%   flight's own draws (speed uniform over the same range); 20 frames, flown as pool_cell.m
%   flies them. Clean twins: every geometry in the clean cell under no_action (the twin of
%   channel_switch) and rate_reduce (the twin of rate_reduce and channel_switch+rate_reduce).
%   Per frame: r1's BER; SINR = Es/N0_true - L, Es/N0_true the twin frame's true post-MRC Es/N0
%   (own component calibrated on >= 3 clean frames of the twin flight), L = 10 log10[tr(Rin Rs)
%   / tr(Rn Rs)] (the loss on the MRC scale) over the frame after the quiet slot behind the
%   receiver's root raised cosine, Rs of our own component (Level x Thr_sig), Rin of the AWGN
%   output less it, Rn of the AWGN output less the Level output (two sinks the harness adds;
%   the receiver is untouched); L_opt = 10 log10[lmax(Rn^-1 Rs) / lmax(Rin^-1 Rs)] reported only.
%   Eligible: SINR >= 8 dB; collapse: eligible and BER > 0.1. The unit is a realization (Eb/N0,
%   geometry, frame), counted once per state: eligible in any combination, collapse in any.
%   Per state n_s, k_s and the one-sided 95% Clopper-Pearson upper limit U_s. Pass 1 at 12 dB;
%   a state with fewer than 1200 eligible realizations flies 15 dB (pass 2), then 9 dB (pass
%   3); then the census closes.
%   Guards: G1 taps change nothing (geometry 1 of every combination without the sinks and
%   own_out, max|d| = 0 on frame BER and Rx_Z); G2 receiver blob 40dc1f9 and the params copy;
%   G3 the design, the layers and no CORE_BW file under root; G4 L <= 0.1 dB on >= 99% of the
%   clean twins' frames.
% Line tags: RULE, RX2C (runs, guards, counts, bound), RX2CF (every collapse frame).
RULE_SHA = 'd058fd366799a61632ee529938ef572347e62032e56595277d1e5981c0deeb19';
RX_BLOB = '40dc1f9a3bc52cc156130a4f198220f48ce9c1b1';
if nargin < 3 || isempty(bwroot), bwroot = 'C:\Users\Adi Suliman\uav-gcs-v7-bw'; end
t00 = tic;
h = sha256_text(fullfile(rxroot, 'docs', 'rx_fix_rule3.md'));
fprintf('RULE rx_fix_rule3.md sha256 %s\n', h);
if ~strcmp(h, RULE_SHA)
    error('rx_d2c: rx_fix_rule3.md sha256 %s is not the registered %s; nothing run', h, RULE_SHA);
end
src = fullfile(root, 'src'); dat = fullfile(root, 'data'); out = fullfile(root, 'results');
if ~isfolder(out), mkdir(out); end

%% G2: the receiver and the params copy; G3 (files): no CORE_BW data or results under root
hb = git_blob(fullfile(src, 'code', 'link', 'build_threat_model.m'));
hp = sha256_raw(fullfile(dat, 'params.mat')); hw = sha256_raw(fullfile(bwroot, 'params.mat'));
g2 = [strcmp(hb, RX_BLOB), strcmp(hp, hw)];
fprintf('RX2C G2 receiver blob %s (r1 %s) %d | params copy sha256 %s, -bw params.mat %s, equal %d\n', hb, RX_BLOB, ...
    g2(1), hp, hw, g2(2));
bad = {};
for d = {fullfile(root, 'data'), fullfile(root, 'results'), fullfile(src, 'data'), fullfile(src, 'results')}
    x = dir(fullfile(d{1}, '**', '*core_bw*'));
    bad = [bad, fullfile({x.folder}, {x.name})]; %#ok<AGROW>
end
fprintf('RX2C G3 CORE_BW data or results files under %s: %d %s\n', root, numel(bad), strjoin(bad, ', '));
g3f = isempty(bad);

cd(src); addpath(fullfile(src, 'code')); setup_paths;
disk_guard('init');       % no SDI archive; the repository is emptied before every flight (fly)
warning('off', 'Simulink:cgxe:LeakedJITEngine');
S0 = load(fullfile(dat, 'params.mat')); p0 = S0.params; p0.quiet_build = true;
assert(~isfield(p0, 'rx_ne_fix'), 'rx_d2c: the params carry rx_ne_fix');
mdl = 'UAV_GCS_Threat_Link';
fprintf('RX2C start %s, n_rx %d, rx_dd_iter %d, export file %s\n', datestr(now), p0.n_rx, p0.rx_dd_iter, which('build_threat_model'));

%% G3: CORE_BW's validation design and layers, read from its code
sx = fileread(which('experiment_core_bw'));
need = {'X.FAM = 6;', 'X.BLOCK = [5 14];', 'X.NGEO = [12 36];', 'X.LHS_SEED = 7200000;', ...
    'pool_geometries(s, X.BLOCK(sp), 1:X.NGEO(sp), vrange, p0, X.LHS_SEED + 100*s + sp, X.FAM)', ...
    'p.active_threat = c.threat; p.(c.field) = c.level;', 'q = cell_params(p0, cells(c)); q.cm_acr_db = ACR(v);', ...
    'vrange = [p0.speed_kmh_min p0.speed_kmh_max];', 'X.opt = struct(''F_SUB'', 20, ''tw'', 10, ''delay_bits'', 20);'};
sy = fileread(which('pool_cell'));
need2 = {'stop_of = @(nf) num2str((nf - 1) * p.frame_duration);', 'set_link_snr(modelName, snr_dB + g_db - loss, p2);', ...
    'fd = g.speed(r) / 3.6 * p.carrier_freq / p.c_light;', '''alt_m'', geo_value(g, ''alt'', r)', ...
    'extract_closed_loop_frames(sim(modelName, ''StopTime'', stop_of(nf)), p2, opt.delay_bits)'};
hit = [cellfun(@(x) contains(sx, x), need), cellfun(@(x) contains(sy, x), need2)];
g3c = all(hit);
fprintf('RX2C G3 the design in experiment_core_bw.m and pool_cell.m as this harness flies it: %d of %d lines -> %d\n', ...
    nnz(hit), numel(hit), g3c);
Cd = decision_config(); CORE = setdiff(Cd.core_actions, {'no_action'}, 'stable');
[cells, scen] = band_cells(p0); B = band_plan(p0);
BJ = {'cw', 0, 24; 'bw4', 4, 12.6; 'bw20', 20, 17.5; 'bw70', 70, NaN; 'bw83.5', 83.5, NaN};
TOT = [16 23 30];
J = struct('name', {}, 'c', {}, 'state', {}, 'cfg', {}, 'acr', {}, 'twin', {});
g3l = true;
for b = 1:size(BJ, 1)
    for t = TOT
        if BJ{b, 2} == 0, nmc = sprintf('cw_tot%g', t); else, nmc = sprintf('bw%g_tot%g', BJ{b, 2}, t); end
        c = find(strcmp({cells.name}, nmc));
        assert(numel(c) == 1, 'rx_d2c: cell %s not in band_cells', nmc);
        st = ternary(strcmp(cells(c).threat, 'tone_jamming'), 'narrowband', 'wideband');
        if isfinite(BJ{b, 3})
            G = band_reject('grid', band_reject('values', {scen([scen.cell] == c).J}, B));
            [dv, iv] = min(abs(G - BJ{b, 3}));
            in = ~isempty(dv) && dv < 1e-6;
            g3l = g3l && in;
            fprintf('RX2C G3 layer %s %.1f dB in the cell''s grid %s: %d\n', nmc, BJ{b, 3}, mat2str(G, 4), in);
            acr = NaN; if in, acr = G(iv); end
            J(end + 1) = struct('name', nmc, 'c', c, 'state', st, 'cfg', 'channel_switch', 'acr', acr, 'twin', 'no_action'); %#ok<AGROW>
            J(end + 1) = struct('name', nmc, 'c', c, 'state', st, 'cfg', 'channel_switch+rate_reduce', 'acr', acr, ...
                'twin', 'rate_reduce'); %#ok<AGROW>
        end
        J(end + 1) = struct('name', nmc, 'c', c, 'state', st, 'cfg', 'rate_reduce', 'acr', NaN, 'twin', 'rate_reduce'); %#ok<AGROW>
    end
end
g3a = all(ismember({J.cfg}, CORE));
fprintf('RX2C G3 %d jammed combinations, configurations in the core set %s: %d\n', numel(J), strjoin(CORE, ', '), g3a);
TW = {'no_action', 'rate_reduce'};
G3 = g3f && g3c && g3l && g3a;
G2 = all(g2);
if ~G2 || ~G3
    fprintf('RX2C GUARDS G2 %s G3 %s before any flight -> D2c void (nothing flown)\n', pf(G2), pf(G3));
    return;
end

%% Passes
EB = [12 15 9]; NMIN = 1200;
NG = 72;                  % geometries per pass: CORE_BW's 12 and 60 more of its validation block
STATES = {'narrowband', 'wideband'};
REC = zeros(0, 11);       % pass Eb/N0, combination, geometry, frame, BER, L, Es/N0, SINR, eligible, collapse, L_opt
LT = []; LTo = [];        % L and L_opt of the clean twins' frames
G1 = true; nG1 = 0; vr = [p0.speed_kmh_min p0.speed_kmh_max];
for ip = 1:numel(EB)
    e = EB(ip);
    if ip == 1
        go = STATES;
    else
        ns = cellfun(@(s) census(REC, J, s), STATES);    % eligible realizations so far
        go = STATES(ns < NMIN);
        if isempty(go), break; end
    end
    s = find(p0.EbNo_dB == e, 1);
    assert(~isempty(s), 'rx_d2c: %g dB is not on the Eb/N0 grid', e);
    g = pool_geometries(s, 5, 1:12, vr, p0, 7200000 + 100*s + 1, 6);
    sd = arrayfun(@(r) pool_seed(6, s, 5, r), 1:12);
    gok = isequal(g.seed, sd) && isequal(g.run, 500 + (1:12));
    % geometries 13-NG: the flights' own draws, the speed uniform over the same range
    gx = pool_geometries(s, 5, 13:NG, vr, p0, [], 6);
    [sx, vx] = arrayfun(@(r) pool_seed(6, s, 5, r, vr), 13:NG);
    gxok = isequal(gx.seed, sx) && isequal(gx.speed, vx) && isequal(gx.run, 500 + (13:NG)) && ...
        all(isnan([gx.alt, gx.ksig, gx.aoa1, gx.rho]));
    for fn = {'seed', 'speed', 'run', 'alt', 'ksig', 'aoa1', 'rho'}
        g.(fn{1}) = [g.(fn{1}), gx.(fn{1})];
    end
    G3 = G3 && gok && gxok;
    fprintf(['RX2C pass %d Eb/N0 %g dB (index %d), states %s; G3 seeds pool_seed(6, %d, 5, 1:12) and runs 501-512: %d; ' ...
        'geometries 13-%d own draws, seeds pool_seed(6, %d, 5, 13:%d), speeds and runs 513-%d: %d\n'], ip, e, s, ...
        strjoin(go, ', '), s, gok, NG, s, NG, 500 + NG, gxok);
    fprintf('RX2C pass %d seeds %s\n', ip, mat2str(g.seed));
    fprintf('RX2C pass %d speeds %s km/h\n', ip, mat2str(round(g.speed, 2)));
    % the clean twins: true Es/N0 per frame, and L (G4)
    ES = cell(2, NG);
    for it = 1:2
        Jt = struct('name', 'none', 'c', 0, 'state', 'clean', 'cfg', TW{it}, 'acr', NaN, 'twin', TW{it});
        [Fg, Lg, W, d1, Lo] = run_combo(Jt, p0, cells, e, g, mdl, ip == 1);
        G1 = G1 && d1 == 0; nG1 = nG1 + (ip == 1);
        for r = 1:NG
            ES{it, r} = W{r};
            LT = [LT, Lg{r}]; LTo = [LTo, Lo{r}]; %#ok<AGROW>
            fprintf('RX2C twin %-11s %g dB run %d: frames %d, clean frames %d, calibrated %d, L max %.3f dB, L_opt max %.3f dB\n', ...
                TW{it}, e, g.run(r), numel(Fg{r}.ber), W{r}.ncal, W{r}.ncal >= 3, max([Lg{r}, NaN]), max([Lo{r}, NaN]));
        end
    end
    % the jammed combinations of the states still short
    for j = find(ismember({J.state}, go))
        [Fg, Lg, ~, d1, Lo] = run_combo(J(j), p0, cells, e, g, mdl, ip == 1);
        G1 = G1 && d1 == 0; nG1 = nG1 + (ip == 1);
        it = find(strcmp(TW, J(j).twin));
        for r = 1:NG
            W = ES{it, r}; nf = min(numel(Fg{r}.ber), numel(Lg{r}));
            if W.ncal < 3
                fprintf('RX2C %s %s %g dB run %d: twin with %d calibration frames, no eligible frame\n', J(j).name, ...
                    J(j).cfg, e, g.run(r), W.ncal);
                es = nan(1, nf);
            else
                es = pad(W.es, nf);
            end
            ber = reshape(Fg{r}.ber(1:nf), 1, []); L = reshape(Lg{r}(1:nf), 1, []); lo = reshape(Lo{r}(1:nf), 1, []);
            si = es - L;
            el = si >= 8; co = el & ber > 0.1;
            REC = [REC; repmat([e, j, r], nf, 1), (1:nf)', ber(:), L(:), es(:), si(:), el(:), co(:), lo(:)]; %#ok<AGROW>
        end
        m = REC(:, 1) == e & REC(:, 2) == j;
        fprintf(['RX2C %-12s %-27s layer %5s %g dB: frames %d, eligible %d, collapse %d, median L %.1f dB (L_opt %.1f), ' ...
            'median SINR %.1f dB\n'], J(j).name, J(j).cfg, num2str(J(j).acr), e, nnz(m), nnz(REC(m, 9)), nnz(REC(m, 10)), ...
            median(REC(m, 6), 'omitnan'), median(REC(m, 11), 'omitnan'), median(REC(m, 8), 'omitnan'));
    end
end

%% Counts, collapse frames, the bound
fprintf('RX2C G1 taps change nothing: %d combinations, max|d| 0 on all -> %s\n', nG1, pf(G1));
G4 = ~isempty(LT) && mean(LT <= 0.1) >= 0.99;
fprintf('RX2C G4 clean twins: L <= 0.1 dB on %d of %d frames (%.2f%%), max %.3f dB -> %s | L_opt <= 0.1 dB on %d, max %.3f dB\n', ...
    nnz(LT <= 0.1), numel(LT), 100 * mean(LT <= 0.1), max([LT, NaN]), pf(G4), nnz(LTo <= 0.1), max([LTo, NaN]));
for j = 1:numel(J)
    m = REC(:, 2) == j;
    if ~any(m), continue; end
    fprintf('RX2C count %-12s %-27s frames: k %d n %d (frames %d, ineligible %.1f%%)\n', J(j).name, J(j).cfg, ...
        nnz(REC(m, 10)), nnz(REC(m, 9)), nnz(m), 100 * mean(REC(m, 9) == 0));
end
for i = find(REC(:, 10) == 1)'
    x = REC(i, :); jj = J(x(2));
    fprintf(['RX2CF %s %s layer %s %g dB geometry %d (run %d) frame %d SINR %.1f dB L %.1f dB L_opt %.1f dB EsN0 %.1f dB ' ...
        'BER %.4f\n'], jj.name, jj.cfg, num2str(jj.acr), x(1), x(3), 500 + x(3), x(4), x(8), x(6), x(11), x(7), x(5));
end
U = nan(1, 2);
for k = 1:2
    [n, kk, nr, nfl, kmx] = census(REC, J, STATES{k});
    U(k) = cp_upper(kk, n);
    fprintf(['RX2C BOUND %s: n_s %d eligible of %d realizations (Eb/N0, geometry, frame; ineligible %.1f%%), k_s %d ' ...
        'collapse realizations in %d flights (at most %d in one flight), U_s %.4f%% (one-sided 95%% Clopper-Pearson)%s%s\n'], ...
        STATES{k}, n, nr, 100 * (nr - n) / max(nr, 1), kk, nfl, kmx, 100 * U(k), ...
        ternary(n < NMIN, ', below the 1200 target', ''), ternary(U(k) > 0.01, ', receiver-limited (U_s > 1 pp)', ''));
    fprintf(['RX2C BOUND %s: a verdict is receiver-robust when its point and 95%% lower bound lie farther than ' ...
        'U_s / (PER_static,s - U_s) = %.4f / (PER_static,s - %.4f) from 30%%\n'], STATES{k}, U(k), U(k));
end
G = G1 && G2 && G3 && G4;
fprintf('RX2C GUARDS G1 %s G2 %s G3 %s G4 %s -> D2c %s\n', pf(G1), pf(G2), pf(G3), pf(G4), ...
    ternary(G, 'valid', 'void (nothing read; fix the harness, rerun)'));
close_system(mdl, 0);
names = {J.name}; cfgs = {J.cfg}; acr = [J.acr]; st = {J.state};
save(fullfile(out, sprintf('rx_d2c_%s.mat', datestr(now, 'yyyymmdd_HHMM'))), 'REC', 'LT', 'LTo', 'U', 'names', 'cfgs', 'acr', ...
    'st', 'G', 'NG');
fprintf('RX2C done %s (%.1f min)\n', datestr(now), toc(t00) / 60);
end

%% ===================== One combination =====================
function [Fg, Lg, W, dmax, Lo] = run_combo(Jc, p0, cells, e, g, mdl, ctrl)
% One configuration of one cell (Jc.c = 0: the clean cell) on the geometries g at Eb/N0 e, as
% pool_cell.m flies it, with own_out and the two sinks: every geometry's frames, every
% frame's L and L_opt and the true Es/N0 of the own component. ctrl: geometry 1 also flown on
% CORE_BW's own build (no sinks, own_out as the configuration sets it), max|d| on frame BER
% and Rx_Z in dmax (0 when ctrl is false).
if Jc.c == 0
    pc = p0; pc.active_threat = 'none'; th = 'none';
else
    c = cells(Jc.c); pc = p0; pc.active_threat = c.threat; pc.(c.field) = c.level; th = c.threat;
end
if isfinite(Jc.acr), pc.cm_acr_db = Jc.acr; end
[CC, ~, ~] = pool_configs(pc, th, {Jc.cfg}); q0 = CC(1).p; g_db = CC(1).g_db;
dmax = 0; t1 = tic;
if ctrl
    build_threat_model(q0);
    [F0, so0] = fly(mdl, q0, g_db, e, g, 1, pc);
    z0 = so0.get('Rx_Z');
end
q = q0; q.own_out = true;
build_threat_model(q);
add_taps(mdl);
Lf = frame_layout(q);
Fg = cell(1, numel(g.seed)); Lg = Fg; W = Fg; Lo = Fg;
for r = 1:numel(g.seed)
    [F, so] = fly(mdl, q, g_db, e, g, r, pc);
    Fg{r} = F; [Lg{r}, Lo{r}] = interf_loss(so, mdl, q, numel(F.ber), Lf); W{r} = truth(so, mdl, q, F, Lf);
    if ctrl && r == 1
        z1 = so.get('Rx_Z');
        dmax = Inf;
        if isequal(size(z1), size(z0)) && isequal(size(F.ber), size(F0.ber))
            dmax = max([abs(z1(:) - z0(:)); abs(F.ber(:) - F0.ber(:))]);
        end
        fprintf('RX2C G1 %s %s layer %s %g dB run %d: with taps against CORE_BW''s build max|d| Rx_Z and frame BER %.1e\n', ...
            Jc.name, Jc.cfg, num2str(Jc.acr), e, g.run(1), dmax);
    end
end
fprintf('RX2C %s %s layer %s %g dB: %d geometries, Eb/N0 offset %.2f dB, own_out (configuration) %d (%.1f min)\n', Jc.name, ...
    Jc.cfg, num2str(Jc.acr), e, numel(g.seed), g_db, isfield(q0, 'own_out') && q0.own_out, toc(t1) / 60);
end

function [F, so] = fly(mdl, q, g_db, e, g, r, pc)
% Geometry r at Eb/N0 e as pool_cell.m flies it: 20 frames.
disk_guard;               % empties the SDI repository of the flight before (already read); stops above 2 GB of .dmr
loss = 0; if isfield(q, 'link_loss_db'), loss = q.link_loss_db; end
set_link_snr(mdl, e + 10*log10(q.bits_per_symbol) - 10*log10(q.sps) + g_db - loss, q);
fd = g.speed(r) / 3.6 * pc.carrier_freq / pc.c_light;
link_seed(mdl, g.seed(r), fd, struct('ebno', e, 'alt_m', g.alt(r), 'k_sig_db', g.ksig(r), 'aoa1_deg', g.aoa1(r), ...
    'rho', g.rho(r), 'event_frame', NaN, 'frames', 20));
evalc('so = sim(mdl, ''StopTime'', num2str(19 * q.frame_duration));');
[F, ~] = extract_closed_loop_frames(so, q, 20);
end

function add_taps(mdl)
% The outputs of 'Level' and 'AWGN' to the workspace (the truth taps; the receiver is untouched).
add_block('simulink/Sinks/To Workspace', [mdl '/D2c_lvl'], 'Position', [700 -130 780 -100]);
add_block('simulink/Sinks/To Workspace', [mdl '/D2c_awgn'], 'Position', [700 -170 780 -140]);
set_param([mdl '/D2c_lvl'], 'VariableName', 'D2c_lvl', 'SaveFormat', 'Array');
set_param([mdl '/D2c_awgn'], 'VariableName', 'D2c_awgn', 'SaveFormat', 'Array');
add_line(mdl, 'Level/1', 'D2c_lvl/1', 'autorouting', 'on');
add_line(mdl, 'AWGN/1', 'D2c_awgn/1', 'autorouting', 'on');
end

%% ===================== Truth =====================
function [L, Lo] = interf_loss(so, mdl, q, nf, Lf)
% Per frame, over the frame after the quiet slot, behind the receiver's root raised cosine
% (its delay compensated): L, the interference's loss on the MRC scale [dB],
% sum_t s(t)' Rin s(t) / sum_t s(t)' Rn s(t) = tr(Rin Rs) / tr(Rn Rs) with s(t) our own
% component; Lo, its loss to the best linear spatial combiner [dB] (reported only).
gl = str2double(get_param([mdl '/Level'], 'Gain'));
s = so.get('Thr_sig') * gl; lv = so.get('D2c_lvl'); aw = so.get('D2c_awgn');
ns = size(s, 1); NR = size(s, 2); nf = min([nf, size(s, 3), size(lv, 3), size(aw, 3)]);
st = @(x) reshape(permute(x(:, :, 1:nf), [1 3 2]), [], NR);     % the frames in time order
xs = st(s); xi = st(aw) - xs; xn = st(aw) - st(lv);
xs = rrc(xs, q); xi = rrc(xi, q); xn = rrc(xn, q);
gd = q.filter_span * q.sps / 2;
L = nan(1, nf); Lo = L;
for f = 1:nf
    w = (f - 1) * ns + (Lf.NQ * q.sps + 1 : ns) + gd;
    w = w(w <= size(xs, 1));
    Rs = cov0(xs(w, :)); Ri = cov0(xi(w, :)); Rn = cov0(xn(w, :));
    L(f) = 10 * log10(real(trace(Ri * Rs)) / real(trace(Rn * Rs)));
    Lo(f) = 10 * log10(lmax(Rn, Rs) / lmax(Ri, Rs));
end
end

function y = rrc(x, q)
f = comm.RaisedCosineReceiveFilter('RolloffFactor', q.rolloff, 'FilterSpanInSymbols', q.filter_span, ...
    'InputSamplesPerSymbol', q.sps, 'DecimationFactor', 1);
y = f(x);
end

function R = cov0(x)
R = (x.' * conj(x)) / size(x, 1);
end

function l = lmax(Rd, Rs)
% the largest generalized eigenvalue of (Rs, Rd)
l = max(real(eig(Rd \ Rs)));
end

function own = own_signal(so, mdl, nf)
own = so.get('Thr_sig') * str2double(get_param([mdl '/Level'], 'Gain'));
own = own(:, :, 1:nf);
end

function W = truth(so, mdl, q, F, Lf)
% Per frame the true post-MRC Es/N0 of the own component, calibrated on the clean frames
% (BER < 1e-3, pilot error < 0.3; at least 3), as the D1 and D2 harnesses compute it.
nf = numel(F.ber); own = own_signal(so, mdl, nf); ns = size(own, 1);
qq = Lf.NQ * q.sps + 1 : ns;
gt = reshape(10*log10(mean(abs(own(qq, :, :)).^2, 1)), [], nf);
gts = 10*log10(sum(10.^(gt / 10), 1));
gpe = 10*log10(sum(10.^(F.gain_ant / 10) ./ F.rq, 1));
ok = F.ber < 1e-3 & F.pilot_err < 0.3;
W = struct('es', nan(1, nf), 'ncal', nnz(ok));
if nnz(ok) >= 3, W.es = gts + median(gpe(ok) - gts(ok)); end
end

%% ===================== Helpers =====================
function [n, k, nr, nfl, kmx] = census(REC, J, st)
% State st's distinct (Eb/N0, geometry, frame) realizations: nr in all, n eligible in at least
% one combination, k a collapse frame in at least one; nfl the flights (Eb/N0, geometry) that
% hold a collapse realization, kmx the most in one flight.
m = false(size(REC, 1), 1);
if ~isempty(REC), m = strcmp({J(REC(:, 2)).state}', st); end
X = REC(m, :);
[u, ~, iu] = unique(X(:, [1 3 4]), 'rows');
el = accumarray(iu, X(:, 9), [size(u, 1) 1], @max);
co = accumarray(iu, X(:, 10), [size(u, 1) 1], @max);
nr = size(u, 1); n = nnz(el); k = nnz(co);
[uf, ~, jf] = unique(u(co > 0, 1:2), 'rows');
nfl = size(uf, 1); kmx = 0;
if ~isempty(jf), kmx = max(accumarray(jf, 1)); end
end

function u = cp_upper(k, n)
% one-sided 95% Clopper-Pearson upper limit of k / n (k = 0: 1 - 0.05^(1/n))
if n == 0, u = 1; elseif k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

function v = pad(v, n)
v = [v(:)', nan(1, n)]; v = v(1:n);
end

function h = sha256_text(f)
% sha256 of a text file with its line ends as LF.
fid = fopen(f, 'r'); assert(fid > 0, 'rx_d2c: cannot read %s', f);
u = fread(fid, Inf, '*uint8'); fclose(fid);
h = digest('SHA-256', u(u ~= 13));
end

function h = sha256_raw(f)
% sha256 of a file's bytes.
fid = fopen(f, 'r'); assert(fid > 0, 'rx_d2c: cannot read %s', f);
u = fread(fid, Inf, '*uint8'); fclose(fid);
h = digest('SHA-256', u);
end

function h = git_blob(f)
% git's blob id of a text file with its line ends as LF.
fid = fopen(f, 'r'); assert(fid > 0, 'rx_d2c: cannot read %s', f);
u = fread(fid, Inf, '*uint8'); fclose(fid);
u = u(u ~= 13);
h = digest('SHA-1', [uint8(sprintf('blob %d', numel(u))) uint8(0) u(:)']);
end

function h = digest(alg, u)
md = java.security.MessageDigest.getInstance(alg);
md.update(typecast(uint8(u(:)), 'int8'));
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end

function s = pf(t)
if t, s = 'PASS'; else, s = 'FAIL'; end
end

function y = ternary(c, a, b)
if c, y = a; else, y = b; end
end
