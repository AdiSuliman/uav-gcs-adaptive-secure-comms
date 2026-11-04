function varargout = deg_quantile(cmd, varargin)
%DEG_QUANTILE  The clean (1 - alpha) quantile of the window BER estimate per bin of the windowed
%   Eb/N0 estimate: the degradation threshold of policy_monitor.m's deg_mode 'win_q' and
%   'win_q_gate' (docs/deg_fix_protocol.md; CFAR from the null distribution, Lopez-Benitez 2016).
%   [b, e, g] = deg_quantile('windows', ber, ebno, run, win)
%       every window of win frames of each flight, cyclic in the flight's frames as link_env.m
%       draws them (run: the flight per frame, a flight's frames in time order): b the mean BER
%       estimate, e the median measured Eb/N0 estimate, g the flight; one window per frame, the
%       one ending on it (policy_monitor.m's full window)
%   Q = deg_quantile('build', b, e, g, alpha, opt)
%       bins of opt.w0 dB on e (those with cycles), merged until each holds at least
%       round(opt.kmin / alpha) cycles from at least opt.fmin flights: the failing bin with the
%       fewest cycles (the lower on a tie) joins its neighbour with fewer cycles (the lower on a
%       tie). Q.q per bin: the value with floor(alpha n) of its n cycles above it. Q.lo, Q.hi the
%       bins' edges [dB], Q.n, Q.nf their cycles and flights, Q.short when the one bin left still
%       fails (reported, not worked around). opt defaults C.deg_bin_db, C.deg_kmin, C.deg_fmin.
%   t = deg_quantile('lookup', Q, e)
%       the threshold at Eb/N0 e: the bin with the largest lower edge at most e (the first bin
%       below every edge, the last above); NaN at NaN
switch cmd
    case 'windows'
        [varargout{1}, varargout{2}, varargout{3}] = windows(varargin{:});
    case 'build'
        varargout{1} = build(varargin{:});
    case 'lookup'
        varargout{1} = lookup(varargin{:});
    otherwise
        error('deg_quantile:cmd', 'unknown command %s', cmd);
end
end

function [b, e, g] = windows(ber, ebno, run, win)
ber = double(ber(:)); ebno = double(ebno(:)); run = double(run(:));
[u, ~, ir] = unique(run, 'stable');
B = cell(numel(u), 1); E = B; G = B;
for i = 1:numel(u)
    k = find(ir == i); n = numel(k);
    ix = k(mod((1:n)' - win + (0:win - 1), n) + 1);      % n x win, oldest first
    if n == 1, ix = ix(:)'; end
    B{i} = mean(ber(ix), 2, 'omitnan'); E{i} = median(ebno(ix), 2, 'omitnan'); G{i} = repmat(u(i), n, 1);
end
b = vertcat(B{:}); e = vertcat(E{:}); g = vertcat(G{:});
end

function Q = build(b, e, g, alpha, opt)
C = decision_config();
if nargin < 5, opt = struct(); end
w0 = field_or(opt, 'w0', C.deg_bin_db); kmin = field_or(opt, 'kmin', C.deg_kmin); fmin = field_or(opt, 'fmin', C.deg_fmin);
b = double(b(:)); e = double(e(:)); g = double(g(:));
ok = ~isnan(b) & ~isnan(e); b = b(ok); e = e(ok); g = g(ok);
assert(~isempty(b), 'deg_quantile: no clean cycle');
need = round(kmin / alpha);
[ub, ~, bin] = unique(floor(e / w0));                   % the bins with cycles, ascending
lo = ub(:)'; hi = lo + 1;                               % in units of w0
while true
    nb = numel(lo);
    n = accumarray(bin, 1, [nb 1])';
    nf = accumarray(bin, g, [nb 1], @(x) numel(unique(x)))';
    bad = find(n < need | nf < fmin);
    if isempty(bad) || nb == 1, break; end
    [~, j] = min(n(bad)); i = bad(j);
    if i == 1, o = 2; elseif i == nb, o = nb - 1; elseif n(i + 1) < n(i - 1), o = i + 1; else, o = i - 1; end
    a = min(i, o);                                      % bins a and a + 1 become one
    hi(a) = hi(a + 1); lo(a + 1) = []; hi(a + 1) = [];
    bin(bin > a) = bin(bin > a) - 1;
end
q = zeros(1, nb);
for i = 1:nb
    x = sort(b(bin == i)); m = floor(alpha * numel(x) + 1e-9);
    q(i) = x(numel(x) - m);
end
Q = struct('alpha', alpha, 'lo', lo * w0, 'hi', hi * w0, 'q', q, 'n', n, 'nf', nf, 'need', need, ...
    'fmin', fmin, 'w0', w0, 'short', ~isempty(bad));
end

function t = lookup(Q, e)
t = nan(size(e));
k = ~isnan(e);
ek = e(k); ek = double(ek(:));
i = 1 + sum(ek >= Q.lo(2:end), 2);
t(k) = Q.q(i);
end

function v = field_or(S, f, d)
v = d; if isfield(S, f) && ~isempty(S.(f)), v = S.(f); end
end
