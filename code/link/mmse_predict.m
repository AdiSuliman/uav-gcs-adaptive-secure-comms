function [G, D] = mmse_predict(varargin)
%MMSE_PREDICT  Predicted SINR gain of MMSE over MRC combining per frame [dB], from the
%   frame's known symbols only (training and pilots, frame_layout.m), no decisions.
%   [G, D] = mmse_predict(iqa, p, sy)
%   Y = mmse_predict('snapshots', iqa, p, sy)
%   [grp, sk] = mmse_predict('groups', p)
%
%   iqa  samples x antennas x frames, the received samples as the combiner sees them
%   p    params of the run (sps, filter_span, rolloff, timing_max_sym, the frame layout,
%        cfo_ppm, carrier_freq, v_max, c_light)
%   sy   receiver output 6 (8 x frames): sy(1) the arrival [samples], sy(2) the frequency
%        offset [Hz] (zeros with the ideal receiver)
%   Snapshots: every antenna's matched-filtered samples at the receiver's symbol times and
%   frequency (NS x antennas x frames, NaN where the frame does not hold them). Groups of
%   known symbols: the short and long training and every pilot block (groups). The
%   frequency the receiver's synchronization left (a strong interferer can pull its pilot
%   tracking off by a few kHz) is measured on the pilot blocks and removed first
%   (residual_frequency). Each group but the short training is held out in turn: on the
%   known symbols of the groups within GSPAN of it, the reference correlation r = mean(y s*) and the covariance
%   R = mean(y y^H) of the same snapshots give the direct-matrix-inversion weights
%   w = R^-1 r (Winters, Salz & Gitlin 1994, eqs. 19-23) and the MRC weights r. Both combine
%   the held-out group; the SINR of each combiner is measured over the frame's held-out
%   symbols against their known values (a complex gain fitted, floor 1 / the number of
%   symbols), and G is their ratio. No symbol is judged by weights fitted on it; the reactive
%   and bursty interferers that are on the air while our signal is are in the snapshots.
%   MRC is measured at the receiver's arrival and frequency, the link as it runs. Where MMSE
%   reads no SINR above 0 dB there, the frame is searched as the MMSE receiver acquires it on
%   its own (build_threat_model.m): every arrival of the receiver's window (0 to
%   p.timing_max_sym symbols) and every frequency of its acquisition window (the oscillators'
%   +-2 p.cfo_ppm and the largest Doppler) is scored by the long training's in-sample DMI fit
%   (search). The pilot blocks' phase steps cannot tell a frequency from one p.symbol_rate /
%   (p.pilot_block + p.pilot_every) away, and a strong interferer can pull the receiver's
%   estimate several such steps off; the contiguous long training tells them apart. The two
%   best are measured as above and the higher MMSE SINR is taken when it is at least twice
%   (3 dB) the receiver's, so the largest of noisy readings at a weak link's right arrival is
%   not.
%   On the delay line G also counts the single-tap suppression of our own echoes at
%   whole-symbol lags, a few dB on low-K, long-spread links (validate_phy.m V13).
%   D: mmse_db, mrc_db (1 x frames, the measured SINRs [dB]), n_ref (held-out symbols),
%   w_mrc, w_mmse (antennas x groups x frames, the weights each group was combined with),
%   r_mmse (the reference correlations of the DMI weights), df_hz and df_mrc_hz (1 x frames,
%   the frequency removed beyond the receiver's for MMSE and MRC), arrival (the arrival MMSE
%   is measured at [samples]) and search (1 x frames, true where MMSE is measured at the
%   search's arrival and frequency), for validate_phy.m
if ischar(varargin{1})
    switch varargin{1}
        case 'snapshots', G = snapshots(varargin{2:end});
        case 'groups', [G, D] = groups(varargin{2});
        otherwise, error('mmse_predict: unknown command %s', varargin{1});
    end
    return
end
[iqa, p, sy] = varargin{:};
n0 = maxNumCompThreads(1); c0 = onCleanup(@() maxNumCompThreads(n0));   % small matrices: one thread is faster
[~, na, nf] = size(iqa);
[grp, sk] = groups(p);
[rf, base, t] = filtered(iqa, p);
nk = numel([grp{2:end}]); NS = numel(sk);
G = nan(1, nf);
D = struct('mmse_db', nan(1, nf), 'mrc_db', nan(1, nf), 'n_ref', nk, 'w_mrc', nan(na, numel(grp), nf), ...
    'w_mmse', nan(na, numel(grp), nf), 'r_mmse', nan(na, numel(grp), nf), 'df_hz', nan(1, nf), ...
    'df_mrc_hz', nan(1, nf), 'arrival', nan(1, nf), 'search', false(1, nf));
for f = 1:min(nf, size(sy, 2))
    Yf = take(rf, f, base, t, sy(1:2, f), NS, p.sps);
    if isempty(Yf), continue; end
    [Yf, D.df_mrc_hz(f)] = residual_frequency(Yf, grp, sk, p.symbol_rate);
    [sm, sr, D.w_mrc(:, :, f), D.w_mmse(:, :, f)] = measure(Yf, grp, sk);
    D.r_mmse(:, :, f) = D.w_mrc(:, :, f); D.df_hz(f) = D.df_mrc_hz(f); D.arrival(f) = round(sy(1, f));
    if sm < 1
        [sc, d, dfc, rc, wc] = search(rf, f, base, t, sy(1:2, f), D.df_hz(f), NS, grp, sk, p);
        if sc > 2 * sm
            sm = sc; D.arrival(f) = d; D.df_hz(f) = dfc; D.r_mmse(:, :, f) = rc; D.w_mmse(:, :, f) = wc; D.search(f) = true;
        end
    end
    D.mrc_db(f) = 10*log10(sr); D.mmse_db(f) = 10*log10(sm);
    G(f) = D.mmse_db(f) - D.mrc_db(f);
end
end

function [sb, db, fb, rb, wb] = search(rf, f, base, t, sy, df0, NS, grp, sk, p)
% The arrivals 0 to p.timing_max_sym symbols and the frequencies sy(2) + j fp / 4 (fp the
% pilot alias step) within the receiver's acquisition window, +-(2 p.cfo_ppm of the carrier
% + the largest Doppler) as build_threat_model.m searches it, scored by the long training's
% in-sample DMI fit q = r' R^-1 r (the share of its snapshots' power the known symbols
% explain; R does not depend on the frequency); the receiver's own alias (arrival sy(1),
% within fp / 2 of sy(2) + df0) is left out. The two best, the second at another arrival or
% more than fp / 2 away, are measured as the frame is (residual_frequency, measure); sb the
% higher MMSE SINR, at arrival db [samples] and frequency fb beyond sy(2) [Hz], with the
% reference correlations rb and the weights wb (sb = 0: none held).
sb = 0; db = NaN; fb = NaN; rb = []; wb = [];
fp = p.symbol_rate / (p.pilot_block + p.pilot_every);
fw = 2 * p.cfo_ppm * 1e-6 * p.carrier_freq + p.v_max * p.carrier_freq / p.c_light;
TM = round(p.timing_max_sym * p.sps);
[ns, ~, na] = size(rf);
kl = grp{2}(:); nl = numel(kl);
ki = base + (0:TM) + (kl - 1) * p.sps + 1;
ok = ki(1, :) >= 1 & ki(end, :) <= ns;
if ~any(ok), return; end
dv = find(ok) - 1; ki = ki(:, ok);
X = reshape(rf(ki, f, :), nl, numel(dv), na) .* exp(-1j * 2*pi * sy(2) * t(ki));
X = permute(X, [3 1 2]);
fj = (ceil(4 * (-fw - sy(2)) / fp):floor(4 * (fw - sy(2)) / fp)) * fp / 4;
if isempty(fj), return; end
S = conj(sk(kl)) .* exp(-1j * 2*pi * (0:nl-1)' * fj / p.symbol_rate) / nl;
r = pagemtimes(X, S);
R = pagemtimes(X, 'none', X, 'ctranspose') / nl;
R = R + 1e-9 * sum(real(R .* eye(na)), [1 2]) / na .* eye(na);
q = reshape(real(sum(conj(r) .* pagemldivide(R, r), 1)), numel(fj), numel(dv));
q(abs(fj - df0) < fp / 2, dv == round(sy(1))) = -Inf;
[~, o] = sort(q(:), 'descend');
[j1, i1] = ind2sub(size(q), o(1));
c = o(1);
for i = 2:numel(o)
    [j, k] = ind2sub(size(q), o(i));
    if k ~= i1 || abs(fj(j) - fj(j1)) > fp / 2, c = [c, o(i)]; break; end %#ok<AGROW>
end
for i = c(isfinite(q(c)))
    [j, k] = ind2sub(size(q), i);
    Yc = take(rf, f, base, t, [dv(k); sy(2) + fj(j)], NS, p.sps);
    if isempty(Yc), continue; end
    [Yc, dfc] = residual_frequency(Yc, grp, sk, p.symbol_rate);
    [sc, ~, rc, wc] = measure(Yc, grp, sk);
    if sc > sb, sb = sc; db = dv(k); fb = fj(j) + dfc; rb = rc; wb = wc; end
end
end

function [sm, sr, Wr, Wm] = measure(Y, grp, sk)
% The held-out SINRs of the DMI (sm) and MRC (sr) combiners over the frame's known symbols
% but the short training's (a neighbour only: groups); Wr, Wm the weights of every group.
GSPAN = 2;
na = size(Y, 2); ng = numel(grp); kall = [grp{2:end}]; nk = numel(kall);
zr = zeros(nk, 1); zm = zeros(nk, 1); Wr = nan(na, ng); Wm = Wr; j = 0;
for g = 2:ng
    kr = [grp{setdiff(max(1, g - GSPAN):min(ng, g + GSPAN), g)}];
    X = Y(kr, :).';
    r = X * conj(sk(kr)) / numel(kr);
    R = X * X' / numel(kr);
    R = (R + R') / 2 + 1e-9 * real(trace(R)) / na * eye(na);
    w = R \ r;
    k = grp{g}; i = j + (1:numel(k)); j = j + numel(k);
    zr(i) = Y(k, :) * conj(r) / max(real(r' * r), eps);
    zm(i) = Y(k, :) * conj(w) / max(real(w' * r), eps);
    Wr(:, g) = r; Wm(:, g) = w;
end
sr = sinr_fit(zr, sk(kall)); sm = sinr_fit(zm, sk(kall));
end

function Y = snapshots(iqa, p, sy)
% Every frame's snapshots at the receiver's arrival and frequency (NaN where it holds none).
[rf, base, t] = filtered(iqa, p);
[~, nf, na] = size(rf);
NS = frame_layout(p).n_sig;
Y = nan(NS, na, nf);
for f = 1:min(nf, size(sy, 2))
    Yf = take(rf, f, base, t, sy(1:2, f), NS, p.sps);
    if ~isempty(Yf), Y(:, :, f) = Yf; end
end
end

function [rf, base, t] = filtered(iqa, p)
% Every antenna's samples through the receive filter, over the whole run as the receiver
% filters them (samples x frames x antennas); base, the sample before the first training
% symbol at arrival 0 (the filter delay and the quiet slot); t, the sample times in a frame.
[ns, na, nf] = size(iqa);
h = rcosdesign(p.rolloff, p.filter_span, p.sps, 'sqrt');
rf = reshape(filter(h, 1, reshape(permute(iqa, [1 3 2]), ns * nf, na)), ns, nf, na);
base = (p.filter_span + p.quiet_symbols) * p.sps;
t = (0:ns-1)' / (p.symbol_rate * p.sps);
end

function Y = take(rf, f, base, t, sy, NS, sps)
% Frame f's NS snapshots at arrival sy(1) [samples] with the frequency offset sy(2) [Hz]
% removed ([] when the frame does not hold them).
Y = [];
if ~all(isfinite(sy)), return; end
[ns, ~, na] = size(rf);
k = base + round(sy(1)) + (0:NS-1)' * sps + 1;
if k(1) < 1 || k(end) > ns, return; end
Y = reshape(rf(k, f, :), NS, na) .* exp(-1j * 2*pi * sy(2) * t(k));
end

function [Y, df] = residual_frequency(Y, grp, sk, sr)
% The frequency left after the receiver's synchronization, from the phase step between
% consecutive pilot blocks weighed by the inverse covariance of the snapshots between them
% (the MMSE receiver's estimate, build_threat_model.m: an interferer the receiver's own
% estimate followed is suppressed there), twice; removed from the snapshots. Unambiguous
% within half the inverse of the pilot spacing.
[NS, na] = size(Y);
c = cellfun(@mean, grp(3:end)); n = numel(c);
df = 0;
if n < 2, return; end
k = (0:NS-1)';
st = find(abs(diff(c) - (c(2) - c(1))) < 1e-9);          % the steps of the common pilot spacing
for it = 1:2
    H = zeros(na, n);
    for b = 1:n, q = grp{b + 2}; H(:, b) = Y(q, :).' * conj(sk(q)) / numel(q); end
    Gc = 0;
    for b = st
        kk = round(c(b)):round(c(b + 1));
        R = Y(kk, :).' * conj(Y(kk, :)) / numel(kk);
        R = (R + R') / 2 + 1e-3 * real(trace(R)) / na * eye(na);
        Gc = Gc + H(:, b + 1)' * (R \ H(:, b));
    end
    d = -angle(Gc) / (2*pi * (c(2) - c(1)) / sr);
    Y = Y .* exp(-1j * 2*pi * d * k / sr);
    df = df + d;
end
end

function [grp, sk] = groups(p)
% Known symbols of the frame (positions from the first training symbol): the short
% training, the long training, then one group per pilot block; sk their values. The short
% training is never held out (measure): its period of p.stf_len symbols puts its power on
% p.stf_len spectral lines, so a CW tone near one of them correlates with it over all its
% repeats and would read as our signal.
L = frame_layout(p);
grp = {1:numel(L.stf), numel(L.stf) + 1:L.n_pre};
ip = L.idx_pil(:)' - L.NQ;
for b = 1:numel(ip) / p.pilot_block, grp{end+1} = ip((b-1)*p.pilot_block + (1:p.pilot_block)); end %#ok<AGROW>
sk = complex(zeros(L.n_sig, 1)); sk(1:L.n_pre) = L.pre; sk(ip) = L.pil;
end

function r = sinr_fit(z, s)
% SINR of combiner outputs z against their N known unit-power symbols s: a complex gain g
% fitted over them, the residual's power (N / (N - 1) of its mean, one gain fitted) the
% interference and noise v; |g|^2 holds v / N of estimation noise, which is taken out;
% floor 1 / N, the resolution of N symbols.
N = numel(s);
g = (s' * z) / (s' * s);
v = max(sum(abs(z - g * s).^2) / (N - 1), eps);
r = max((abs(g)^2 - v / N) / v, 1 / N);
end
