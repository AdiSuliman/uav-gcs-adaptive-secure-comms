function varargout = branch_ref(cmd, varargin)
%BRANCH_REF  Held reference of every receive branch and the window-limited CUSUM of one
%   branch's drop below it: the fusion's held columns (window_cues.m 'extra', opt.held).
%   st = branch_ref('init', E, nr)          the state of E episodes with nr antennas
%   [st, x] = branch_ref('step', st, g)      one decision cycle: g E x nr mean channel gains
%                                            [dB] (gain_ant), x E x 4 the columns
%   x = branch_ref('run', G)                 the cycles of one run, G n x nr, oldest first,
%                                            from an empty state: n x 4
%   phi = branch_ref('eff', P)               the share phi below of E windows of linear
%                                            powers P (E x nr x n)
%   names = branch_ref('names')
%
%   Per cycle each antenna's power over the mean of the other antennas' (linear; a common
%   change of our level or attitude cancels), r. Its reference is the linear mean of r over
%   the last NR = 10 reference cycles (the local mean is a linear average, Lee 1985, Sec.
%   IV; the monitor's 10-cycle reference, policy_monitor.m). The first NR_MIN = 3 cycles join
%   it as they come (the latch's 3 earlier cycles, onset_shape.m). From then on xi = r / ref
%   is tested for a drop: fading power is exponential about its mean (Rayleigh, the worst
%   case), so the log-likelihood ratio of a drop to the mean theta is
%       l = -log(theta) - xi (1 / theta - 1)
%   in Page's recursion W = min(max(0, W + phi l), 2 b) (Xie et al. 2021, eq. 2-3), with the
%   unknown theta estimated by the mean xi of the last w = C.cusum_win cycles before the
%   current one and held in the set of changes, the antenna fault's levels of the envelope
%   (decision_config.m): the window-limited CUSUM of Xie, Moustakides & Xie 2022 (eq. 6-7),
%   as drop_cusum.m does for our level. phi = (1 - rho) / (1 + rho), the share of a
%   first-order autoregressive series' samples that count as independent, rho the median
%   over the antennas of the lag-1 correlation of each one's power over the last NR cycles
%   (at least 0; branch_ref('eff', P)): slow or hovering flight repeats one fade from cycle
%   to cycle, so its cycles carry less than one independent sample each (Lee 1985, Sec. IV:
%   samples about 0.8 wavelength apart are uncorrelated). b = |log alpha| (Xie et al. 2021,
%   Sec. II-D1), alpha = 1.87%, the deployed fusion's share of clean frames read as a lost
%   branch on profile 1's validation.
%   The reference is held while a drop is under test, as drop_ref.m holds the level's: the
%   cycles since the statistic left 0 are kept aside; when it returns to 0 without having
%   reached b they join the reference, when it reached b they are the change's and are left
%   out. No reference takes a cycle in which a branch is under test (the others' mean holds
%   that branch's drop). Columns, for the antenna with the largest W: br_w its W, br_db its
%   drop below its reference over the cycles under test [dB] (0 without), br_len those
%   cycles, br_nref its reference cycles over NR.
NR = 10; NR_MIN = 3; ALPHA = 0.0187;
switch cmd
    case 'names'
        varargout{1} = {'br_w', 'br_db', 'br_len', 'br_nref'};
    case 'init'
        E = varargin{1}; nr = varargin{2}; C = decision_config();
        varargout{1} = struct('R', nan(E, nr, NR), 'H', nan(E, nr, NR), 'hs', zeros(E, nr), 'hn', zeros(E, nr), ...
            'W', zeros(E, nr), 'x', false(E, nr), 'dx', nan(E, nr, C.cusum_win), 'q', nan(E, nr, NR));
    case 'step'
        [varargout{1}, varargout{2}] = step(varargin{1}, double(varargin{2}), NR, NR_MIN, abs(log(ALPHA)));
    case 'eff'
        varargout{1} = eff_share(double(varargin{1}));
    case 'run'
        G = double(varargin{1}); [n, nr] = size(G);
        st = branch_ref('init', 1, nr); x = zeros(n, 4);
        for t = 1:n, [st, x(t, :)] = step(st, G(t, :), NR, NR_MIN, abs(log(ALPHA))); end
        varargout{1} = x;
    otherwise
        error('branch_ref: unknown command %s', cmd);
end
end

function [st, x] = step(st, g, NR, NR_MIN, b)
[E, nr] = size(g);
C = decision_config();
D = 10 .^ (-C.sev.antenna_fault.levels([end 1]) / 10);  % the set of changes: mean ratios after a drop
p = 10 .^ (g / 10);
r = zeros(E, nr);
for a = 1:nr, r(:, a) = p(:, a) ./ max(mean(p(:, setdiff(1:nr, a)), 2), realmin); end
st.q = cat(3, st.q(:, :, 2:end), p);
phi = eff_share(st.q);
nref = sum(~isnan(st.R), 3);
ref = mean(st.R, 3, 'omitnan');
xi = r ./ max(ref, realmin);
th = mean(st.dx, 3, 'omitnan'); th(isnan(th)) = D(2); th = min(max(th, D(1)), D(2));
l = phi .* (-log(th) - xi .* (1 ./ th - 1));
fill = nref < NR_MIN;                                    % a reference still being built: the cycle joins it
W = min(max(0, st.W + l), 2 * b); W(fill) = 0;
st.x = st.x | W >= b;
up = W > 0;
ok = ~any(up, 2);                                        % no branch under test: the cycle may join the references
for e = 1:E
    for a = 1:nr
        if up(e, a)
            st.H(e, a, :) = cat(3, st.H(e, a, 2:end), r(e, a));
            st.hs(e, a) = st.hs(e, a) + xi(e, a); st.hn(e, a) = st.hn(e, a) + 1;
            continue
        end
        if ok(e)
            if ~st.x(e, a) && st.hn(e, a) > 0           % an excursion back to 0 without the alarm: before any change
                h = reshape(st.H(e, a, :), 1, []); h = h(~isnan(h));
                v = [reshape(st.R(e, a, :), 1, []), h]; st.R(e, a, :) = reshape(v(end - NR + 1:end), 1, 1, NR);
            end
            st.R(e, a, :) = cat(3, st.R(e, a, 2:end), r(e, a));
        end
        st.H(e, a, :) = NaN; st.hs(e, a) = 0; st.hn(e, a) = 0; st.x(e, a) = false;
    end
end
st.W = W;
xi(fill) = NaN;
st.dx = cat(3, st.dx(:, :, 2:end), reshape(xi, E, nr, 1));
[wm, k] = max(W, [], 2);
i = sub2ind([E nr], (1:E)', k);
mx = st.hs(i) ./ max(st.hn(i), 1);
db = zeros(E, 1); m = st.hn(i) > 0; db(m) = -10 * log10(max(mx(m), 1e-6));
nref = sum(~isnan(st.R), 3);
x = [wm, db, st.hn(i), nref(i) / NR];
end

function phi = eff_share(P)
% (1 - rho) / (1 + rho) of E windows of linear powers P (E x nr x n, NaN: no cycle), rho the
% median over the antennas of the lag-1 correlation of each one's power about its mean, at
% least 0; 1 with fewer than 4 cycles.
[E, nr, ~] = size(P); phi = ones(E, 1);
for e = 1:E
    V = reshape(P(e, :, :), nr, []); V = V(:, all(~isnan(V), 1));
    if size(V, 2) < 4, continue; end
    U = V - mean(V, 2);
    d = sum(U.^2, 2); ok = d > 1e-12 * sum(V.^2, 2);
    if ~any(ok), continue; end
    rho = max(0, median(sum(U(ok, 1:end-1) .* U(ok, 2:end), 2) ./ d(ok)));
    phi(e) = (1 - rho) / (1 + rho);
end
end
