function R = dev_fec_burst(stage, out, rev)
%DEV_FEC_BURST  Dev set C of the coded link under intermittent interferers and the
%   pre-registered choice of the JSI decoder (docs/noise_burst_protocol.md, fec_packets.m).
%   dev_fec_burst('flights', out): link seeds 7801-7860 (dev set C, never a pool, test,
%   check, validate_phy or other dev flight), 20 frames per flight at the checkout's antenna
%   profile (its profile.json n_rx), nominal Doppler. Points: noise bursts, J4 (duty 0.2) and
%   the random jammer at duty 0.5 and 0.775 (the range's ends), at 4, 10, 16, 23 and 30 dB;
%   the sweeping jammer, the reactive jammer and WLAN at 16 and 30 dB; each at Eb/N0 9 dB under
%   no_action, power_control and spatial_diversity; D78's jammer points (16 dB under MMSE at
%   6 and 12 dB, 30 dB at 234 ns, rho 0.3, K 10 dB under MMSE at 12 and 15 dB); the clean link
%   at 0, 3 and 9 dB with K drawn under the three configurations. Per flight the truth
%   inputs (extract_closed_loop_frames.m, without antenna 1's samples), the uncoded BER and
%   pilot error of every frame and the D78 decoder's coded result (the reference). Saves
%   <out>/dev_C.mat.
%   R = dev_fec_burst('select', out, rev): the choice, in the order fixed before the run:
%     1. c per h (0, 1): the smallest on 2:0.1:12 flagging at most 1% of the clean points'
%        data symbols, against each codeword's floor (q = 0.05); flag_clean its share
%     2. thr: the smallest on 0.05:0.05:3 whose pilot error flags at most 1% of the frames
%        with uncoded BER <= 0.2 over every point; none: the frame c variants do not qualify
%     3. the variants frame (b, c, a) x h (0, 1) x erase_sym (false, true), in that tie
%        order: qualified when no D78 or clean point loses more than Q/2 packets (one loss
%        event of the coded link, packet_share.m) more than the D78 decoder; the lowest
%        packet loss pooled over the intermittent points (noise bursts, sweeping, reactive,
%        WLAN), ties to the earlier
%     4. adopted only when (dev_fec_gates.m): the clean floor at 9 dB matches the mean
%        residual within 1 dB (median over the codewords); J4 at 4 dB under no_action
%        decodes, packet loss <= 2 x that of the clean link at 9 dB (its loss floored at one
%        packet); J4 at 10 dB under no_action loses more than Q/2 packets fewer than the D78
%        decoder (the cutoff rate R0(1) there is at the edge of the K = 7 code, so its loss is
%        reported beside capacity and R0(1), McEliece and Stark 1984, Sec. IV and VII); the
%        random jammer at duty 0.775 under no_action does not decode at 10 dB or more
%        (capacity below rate 1/2 there; at 4 dB MRC can lift it above, so it is reported only)
%   rev names the decisions entry. R: the readings, the choice (rx, the profile.json value)
%   and adopt; saves <out>/dev_C_select.mat and prints the JSON of profile.json's fec_rx
%   ("d78" when not adopted).
if nargin < 2, out = []; end
if isempty(out), out = fullfile(tempdir, 'uav_gcs_dev'); end
switch stage
    case 'flights', R = flights(out);
    case 'select'
        if nargin < 3 || isempty(rev), error('dev_fec_burst:rev', 'select needs the decisions entry (rev)'); end
        R = select(out, rev);
    otherwise, error('dev_fec_burst:stage', 'unknown stage %s', stage);
end
end

function R = flights(out)
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
w = fullfile(out, 'w_fec_burst'); if ~isfolder(w), mkdir(w); end
if isfile(fullfile(root, 'profile.json')), copyfile(fullfile(root, 'profile.json'), fullfile(w, 'profile.json')); end
p0 = dev_setup('fec_burst', out, false);               % init_params there reads the copied n_rx
mdl = 'UAV_GCS_Threat_Link';
SEEDS = 7801:7860; NF = 20;
PT = dev_points(p0);
D = struct('name', {}, 'kind', {}, 'threat', {}, 'level', {}, 'config', {}, 'ebno', {}, 'p', {}, 'ber', {}, 'pe', {}, ...
    'ref_ber', {}, 'ref_fer', {}, 'T', {});
for i = 1:numel(PT)
    pt = PT(i);
    if isempty(pt.config), p2 = pt.p; g_db = 0; else, [p2, g_db] = apply_countermeasure(pt.p, pt.threat, pt.config); end
    evalc('build_threat_model(p2)');
    set_link_snr(mdl, pt.ebno + g_db + 10*log10(p2.bits_per_symbol) - 10*log10(p2.sps), p2);
    x = struct('ber', nan(numel(SEEDS), NF), 'pe', nan(numel(SEEDS), NF), 'rb', nan(numel(SEEDS), NF), ...
        'rf', nan(numel(SEEDS), NF), 'T', {cell(1, numel(SEEDS))});
    for r = 1:numel(SEEDS)
        link_seed(mdl, SEEDS(r), p2.fd_max, struct('ebno', pt.ebno));
        o = sim(mdl, 'StopTime', num2str((NF - 1) * p2.frame_duration));
        q = p2; q.fec = false;
        [F, T] = extract_closed_loop_frames(o, q, 20);
        qf = p2; qf.fec = true;
        [rb, rf] = closed_loop_truth(T, qf);              % the D78 decoder on the same frames
        n = min(NF, F.nf);
        x.ber(r, 1:n) = F.ber(1:n); x.pe(r, 1:n) = F.pilot_err(1:n); x.rb(r, 1:n) = rb(1:n); x.rf(r, 1:n) = rf(1:n);
        T.iq = []; T.zc = single(T.zc); T.tx_al = logical(T.tx_al); T.rx_al = logical(T.rx_al);
        x.T{r} = T;
    end
    D(end+1) = struct('name', pt.name, 'kind', pt.kind, 'threat', pt.threat, 'level', pt.level, 'config', pt.config, ...
        'ebno', pt.ebno, 'p', p2, 'ber', x.ber, 'pe', x.pe, 'ref_ber', x.rb, 'ref_fer', x.rf, 'T', {x.T}); %#ok<AGROW>
    fprintf('%-34s %2d dB: uncoded frames lost %4d, D78 packets lost %3d of %d\n', pt.name, pt.ebno, ...
        nnz(x.ber > 0.2), nnz(x.rf(:, 2:2:end) == 1), nnz(~isnan(x.rf(:, 2:2:end))));
    close_system(mdl, 0);
end
R = struct('D', D, 'seeds', SEEDS, 'p0', p0, 'created', datestr(now));
save(fullfile(out, 'dev_C.mat'), '-struct', 'R', '-v7.3');
end

function P = dev_points(p0)
% The points of dev set C (one Eb/N0 each).
P = struct('name', {}, 'kind', {}, 'threat', {}, 'level', {}, 'config', {}, 'ebno', {}, 'p', {});
CF = {'no_action', 'power_control', 'spatial_diversity'};
pat = {'j4', [0.2 1], [0.5 0.775]; 'r50', [0.2 0], [0.5 0.5]; 'r775', [0.2 0], [0.775 0.775]};
for k = 1:size(pat, 1)
    for L = [4 10 16 23 30]
        for c = CF
            p = p0; p.active_threat = 'noise_burst'; p.jsr_db = L; p.burst_j4 = pat{k, 2}; p.burst_duty_range = pat{k, 3};
            P(end+1) = pnt(sprintf('nb_%s_%02d_%s', pat{k, 1}, L, c{1}), 'burst', 'noise_burst', L, c{1}, 9, p); %#ok<AGROW>
        end
    end
end
oth = {'sweeping_jammer', 'jsr_db'; 'reactive_jamming', 'jsr_db'; 'benign_interference', 'benign_int_db'};
for k = 1:size(oth, 1)
    for L = [16 30]
        for c = CF
            p = p0; p.active_threat = oth{k, 1}; p.(oth{k, 2}) = L;
            P(end+1) = pnt(sprintf('%s_%02d_%s', oth{k, 1}, L, c{1}), 'burst', oth{k, 1}, L, c{1}, 9, p); %#ok<AGROW>
        end
    end
end
for eb = [6 12]                                         % D78's jammer points (dev_fec_flights.m), the combiner set directly
    p = p0; p.active_threat = 'jamming'; p.jsr_db = 16; p.rx_combiner = 'mmse'; p.tdl_random = true;
    P(end+1) = pnt('d78_j16_mmse', 'd78', 'jamming', 16, '', eb, p); %#ok<AGROW>
end
for eb = [12 15]
    p = p0; p.active_threat = 'jamming'; p.jsr_db = 30; p.rx_combiner = 'mmse'; p.tdl_random = false; p.tdl_ds_ns = [0 234];
    p.corr_random = false; p.rx_corr = 0.3; p.int_rician_k = 10;
    P(end+1) = pnt('d78_j30_234', 'd78', 'jamming', 30, '', eb, p); %#ok<AGROW>
end
for eb = [0 3 9]
    for c = CF
        p = p0; p.active_threat = 'none';
        P(end+1) = pnt(sprintf('clean_%s', c{1}), 'clean', 'none', 0, c{1}, eb, p); %#ok<AGROW>
    end
end
end

function x = pnt(name, kind, threat, level, config, ebno, p)
x = struct('name', name, 'kind', kind, 'threat', threat, 'level', level, 'config', config, 'ebno', ebno, 'p', p);
end

function R = select(out, rev)
p0 = dev_setup('fec_burst', out, false);
L = load(fullfile(out, 'dev_C.mat'), 'D'); D = L.D; clear L
Q = p0.fec_frames; q = 0.05; HS = [0 1]; CG = 2:0.1:12; TG = 0.05:0.05:3;
kind = {D.kind};
icl = find(strcmp(kind, 'clean'));
% 1. c and flag_clean per h; the floor check on the clean link at 9 dB under no_action
c = nan(1, 2); fc = nan(1, 2); fl = [];
for hi = 1:2
    cnt = zeros(1, numel(CG)); n = 0;
    for i = icl
        for r = 1:numel(D(i).T)
            T = D(i).T{r}; J = shifted(T, D(i).p, HS(hi));
            for fr = cw_frames(T.nf, Q)'
                ib = (fr' - 1) * D(i).p.frame_length + (1:D(i).p.frame_length)'; ib = ib(ib <= numel(J.res));
                s0 = jsi_floor(J.res(ib), q);
                cnt = cnt + sum(J.res_h(ib) / s0 > CG, 1); n = n + numel(ib);
                if hi == 1 && D(i).ebno == 9 && strcmp(D(i).config, 'no_action'), fl(end+1) = s0 / mean(J.res(ib)); end %#ok<AGROW>
            end
        end
    end
    sh = cnt / max(n, 1); k = find(sh <= 0.01, 1);
    if ~isempty(k), c(hi) = CG(k); fc(hi) = sh(k); end
end
floor_db = 10 * log10(median(fl));
% 2. thr
pe = cell2mat(arrayfun(@(x) x.pe(:), D, 'UniformOutput', false)'); ub = cell2mat(arrayfun(@(x) x.ber(:), D, 'UniformOutput', false)');
good = ub <= 0.2 & isfinite(pe);
thr = TG(find(arrayfun(@(t) mean(pe(good) > t), TG) <= 0.01, 1));
if isempty(thr), thr = NaN; end                       % none on the grid: frame c has no threshold, not qualified
% 3. variants, in tie order
V = struct('frame', {}, 'h', {}, 'erase_sym', {});
for f = {'b', 'c', 'a'}, for h = HS, for es = [false true], V(end+1) = struct('frame', f{1}, 'h', h, 'erase_sym', es); end, end, end %#ok<AGROW>
nV = numel(V); nP = numel(D);
lost = zeros(nV, nP); npk = zeros(1, nP); dber = nan(nV, nP); rlost = zeros(1, nP); rber = nan(1, nP);
for i = 1:nP
    k = D(i).ref_fer(:, 2:2:end); rlost(i) = nnz(k == 1); npk(i) = nnz(~isnan(k));
    b = D(i).ref_ber(:, 2:2:end); rber(i) = mean(b(~isnan(b)));
end
rx = cell(1, nV);
for v = 1:nV
    hi = V(v).h + 1;
    rx{v} = struct('mode', 'jsi', 'rev', rev, 'q', q, 'c', c(hi), 'h', V(v).h, 'erase_sym', V(v).erase_sym, ...
        'frame', V(v).frame, 'thr', NaN, 'flag_clean', NaN);
    if strcmp(V(v).frame, 'c'), rx{v}.thr = thr; rx{v}.flag_clean = fc(hi); end
    if isnan(c(hi)) || isnan(rx{v}.thr) && strcmp(V(v).frame, 'c'), lost(v, :) = Inf; continue; end
    for i = 1:nP
        qv = D(i).p; qv.fec = true; qv.fec_rx = rx{v}; bb = [];
        for r = 1:numel(D(i).T)
            T = D(i).T{r}; T.zc = double(T.zc); T.tx_al = double(T.tx_al); T.rx_al = double(T.rx_al);
            [b, f] = closed_loop_truth(T, qv);
            lost(v, i) = lost(v, i) + nnz(f(2:2:end) == 1); bb = [bb, b(2:2:end)]; %#ok<AGROW>
        end
        dber(v, i) = mean(bb(~isnan(bb)));
    end
end
ref = ismember(kind, {'d78', 'clean'}); itm = strcmp(kind, 'burst');
qual = all(lost(:, ref) - rlost(ref) <= Q / 2, 2)';
tot = sum(lost(:, itm), 2)';
cand = find(qual);
best = [];
if ~isempty(cand), [~, j] = min(tot(cand)); best = cand(j); end   % min takes the first of equals: the tie order
% 4. physics checks on the chosen variant
nm = {D.name}; noact = strcmp({D.config}, 'no_action');
ok_floor = abs(floor_db) <= 1;
ok_j4 = false; ok_j4_10 = false; dec775 = false;
if ~isempty(best)
    G = dev_fec_gates(lost(best, :), rlost, npk, nm, [D.level], {D.config}, [D.ebno], Q);
    ok_j4 = G.j4; ok_j4_10 = G.j4_10; dec775 = G.dec775;
end
adopt = ~isempty(best) && ok_floor && ok_j4 && ok_j4_10 && ~dec775;
% report
fprintf('dev set C: %d points, %d flights each\n', nP, numel(D(1).T));
fprintf('c (h 0, 1): %s, clean flagged share %s; thr %.2f; clean floor / mean residual at 9 dB %+.2f dB\n', ...
    mat2str(c), mat2str(fc, 3), thr, floor_db);
fprintf('%-6s %-2s %-6s %10s %12s\n', 'frame', 'h', 'erase', 'qualified', 'lost (int.)');
for v = 1:nV
    fprintf('%-6s %-2d %-6d %10d %12g\n', V(v).frame, V(v).h, V(v).erase_sym, qual(v), tot(v));
end
fprintf('D78 decoder, lost over the intermittent points: %d\n', sum(rlost(itm)));
if ~isempty(best)
    fprintf('\nchosen: frame %s, h %d, erase_sym %d\n%-34s %3s %8s %8s %10s %10s\n', V(best).frame, V(best).h, ...
        V(best).erase_sym, 'point', 'dB', 'D78 lost', 'JSI lost', 'D78 BER', 'JSI BER');
    for i = 1:nP
        fprintf('%-34s %3d %8d %8d %10.2e %10.2e\n', nm{i}, D(i).ebno, rlost(i), lost(best, i), rber(i), dber(best, i));
    end
    CAP = {'j4', [0.82 0.67 0.54 0.38 0.24]; 'r50', [0.62 0.53 0.51 0.50 0.50]; 'r775', [0.41 0.28 0.24 0.23 0.23]};
    LV = [4 10 16 23 30];
    fprintf(['\nno_action, packets lost and decoded BER beside the capacity (3.7) and the cutoff rate R0(1) (4.9) per\n' ...
        'coded bit (McEliece and Stark 1984; single branch in-band, ideal interleaving and JSI; rate 0.503)\n']);
    for k = 1:size(CAP, 1)
        R0 = nb_cutoff_rate(CAP{k, 1}, LV);
        for Lv = LV
            i = find(noact & strcmp(nm, sprintf('nb_%s_%02d_no_action', CAP{k, 1}, Lv)), 1);
            fprintf('  %-5s %2d dB: capacity %.2f, R0 %.2f | lost D78 %3d, JSI %3d of %3d | BER D78 %.2e, JSI %.2e\n', ...
                CAP{k, 1}, Lv, CAP{k, 2}(Lv == LV), R0(Lv == LV), rlost(i), lost(best, i), npk(i), rber(i), dber(best, i));
        end
    end
end
fprintf(['\nchecks: floor %s, J4 4 dB decodes %s, J4 10 dB loses more than Q/2 packets fewer than D78 %s, ' ...
    'random 0.775 >= 10 dB does not decode %s -> %s\n'], pf(ok_floor), pf(ok_j4), pf(ok_j4_10), pf(~dec775), ...
    ternary(adopt, 'ADOPT', 'NOT ADOPTED: profile.json fec_rx "d78"'));
if dec775, fprintf('STOP: the random jammer at duty 0.775 decodes where capacity is below the rate; look before anything else\n'); end
choice = 'd78';
if adopt, choice = rx{best}; if ~strcmp(choice.frame, 'c'), choice = rmfield(choice, {'thr', 'flag_clean'}); end, end
js = jsonencode(struct('fec_rx', choice));
fprintf('profile.json: %s\n', js);
R = struct('V', V, 'lost', lost, 'npk', npk, 'dber', dber, 'rlost', rlost, 'rber', rber, 'qual', qual, 'tot', tot, ...
    'c', c, 'flag_clean', fc, 'thr', thr, 'floor_db', floor_db, 'best', best, 'ok_floor', ok_floor, 'ok_j4', ok_j4, 'ok_j4_10', ok_j4_10, ...
    'dec775', dec775, 'adopt', adopt, 'json', js, 'names', {nm}, 'created', datestr(now));
R.choice = choice;
save(fullfile(out, 'dev_C_select.mat'), 'R');
end

function J = shifted(T, p, h)
% jsi_inputs aligned with the run's channel bits, as closed_loop_truth.m aligns them.
J = jsi_inputs(double(T.zc), p, h); n = numel(T.tx_al);
for f = {'num', 'res', 'res_h'}, J.(f{1}) = J.(f{1})(T.delay_bits+1:T.delay_bits+n); end
end

function F = cw_frames(nf, Q)
% Frames of every codeword of a run, a row each (fec_packets.m).
np = floor(nf / 2); P = Q / 2;
F = zeros(np, Q);
for k = 1:np, F(k, :) = mod(2*(k - P) + (0:Q-1), 2*np) + 1; end
end

function t = pf(x)
if x, t = 'PASS'; else, t = 'FAIL'; end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
