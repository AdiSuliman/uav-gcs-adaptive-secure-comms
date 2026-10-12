function varargout = onset_shape(G, varargin)
%ONSET_SHAPE  Shape of the onset of a lost receive branch, from the receiver's per-antenna
%   channel gains only: a step (a connector opens within one frame: an antenna fault) or a
%   ramp (the airframe enters the line of sight as the bank rolls in: airframe shadowing,
%   flight_draws.m and shadow_frame.m).
%
%   [x, F] = onset_shape(G)     the statistic of the last n cycles, as fusion evidence
%       G   E x nr x n mean channel gain of every antenna [dB] (extract_closed_loop_frames.m
%           gain_ant), oldest first, the window of temporal_evidence.m
%       x   E x 2: os_rate, os_glr (0 0 where no branch drops by C_LOST within the window)
%           os_rate  1 / R of the best fit, R the onset's length in cycles (1: a step)
%           os_glr   (SSE_step - SSE_ramp) / s^2: the best step against the best ramp
%                    longer than one cycle, in units of the residual variance (positive: a
%                    ramp fits better; -2 log of their likelihood ratio, Gaussian errors)
%       F   per window: ant (the branch), depth [dB], tau (onset cycle), R, glr, drop
%   The branch is the antenna whose offset from the median of the others (Willgert,
%   US 8,548,029, eq. 5; temporal_evidence.m off_w) is lowest over the last 3 cycles; its
%   offsets are fitted, by least squares, by a level before the onset cycle tau and a fall
%   of the depth d spread linearly over R cycles (h = min(1, max(0, (t - tau + 1) / R))),
%   tau = 2..n, R = 1..2n; a linear ramp is the neutral shape, not the simulator's own. A
%   drop needs the best step at least C_LOST deep (a branch difference above 5 dB fires
%   the diversity-imbalance indicator, Heath, US 10,404,368, Table 2; an event of airframe
%   shadowing needs 5 dB of excess loss, Sun et al., Sec. III).
%
%   [st, pf, cause] = onset_shape('latch', st, g, pf, classes, heal, thr)   one decision
%       cycle of the latched diagnosis (policy_monitor.m): st the state ([] at the start), g
%       E x nr this cycle's gains, pf E x C fused class probabilities, heal the healthy
%       cycles that close the event (decision_config.m C.heal), thr the statistic's
%       threshold (onset_shape('threshold', FM); default 0). A branch whose 3-cycle median
%       offset falls C_LOST below the median of its earlier cycles (at least 3) starts an
%       event; K_DIAG cycles later its offsets over the held history (up to N_HIST cycles,
%       the onset and the lead-in before it) are fitted as above, and the cause is latched:
%       a ramp (airframe_shadowing) when os_glr > thr, else a step (antenna_fault). While
%       latched, a fused class of antenna_fault or airframe_shadowing reads the latched
%       cause (the two classes' probability goes to it); the latch resets once the branch's
%       drop stays below C_LOST for heal cycles. cause: E x 1, 0 none or pending, 1
%       antenna_fault, 2 airframe_shadowing.
%
%   [pf, cause] = onset_shape('sequence', G, pf, classes, heal, thr)   the latch over the
%       cycles of one run (G n x nr, pf n x C), for the readings of eval_detector.m and
%       det_frames.m
%   g = onset_shape('events', G)   os_glr at the latch's diagnosis of the first event of one
%       run (G n x nr), NaN without one: the input of the threshold's choice
%   thr = onset_shape('choose', g, y)   the threshold that best tells the events' causes
%       apart, y 1 for antenna_fault and 2 for airframe_shadowing (select_fusion.m, on the
%       validation sub-runs): the largest mean of the two causes' shares read right over
%       a grid of 0.25 from -8 to 8, the one nearest 0 among equals; 0 without both causes
%   thr = onset_shape('threshold', FM)   FM.os_thr of the deployed fusion (select_fusion.m),
%       0 without one: the model that fits better
%   names = onset_shape('names')
C_LOST = 5; K_DIAG = 3; N_HIST = 20;
if ischar(G)
    switch G
        case 'names', varargout{1} = {'os_rate', 'os_glr'};
        case 'latch'
            a = varargin; if numel(a) < 6, a{6} = 0; end
            [varargout{1:nargout}] = latch(a{1:6}, C_LOST, K_DIAG, N_HIST);
        case 'sequence'
            a = varargin; if numel(a) < 5, a{5} = 0; end
            [varargout{1:nargout}] = sequence(a{1:5});
        case 'events', varargout{1} = events(varargin{:});
        case 'choose', varargout{1} = choose(varargin{:});
        case 'threshold'
            FM = varargin{1}; varargout{1} = 0;
            if isstruct(FM) && isfield(FM, 'os_thr') && ~isempty(FM.os_thr), varargout{1} = FM.os_thr; end
        otherwise, error('onset_shape: unknown command %s', G);
    end
    return
end
[E, nr, n] = size(G);
x = zeros(E, 2);
F = struct('ant', zeros(E, 1), 'depth', zeros(E, 1), 'tau', zeros(E, 1), 'R', zeros(E, 1), 'glr', zeros(E, 1));
if nr < 2 || n < 4
    varargout = {x, F}; return
end
O = offsets(double(G));                                    % E x nr x n
[~, a] = min(median(O(:, :, max(1, n - 2):n), 3), [], 2);
o = zeros(n, E);
for e = 1:E, o(:, e) = reshape(O(e, a(e), :), n, 1); end
S = fit(o);
F = struct('ant', a, 'depth', S.depth, 'tau', S.tau, 'R', S.R, 'glr', S.glr);
k = S.depth >= C_LOST;
x(k, :) = [1 ./ S.R(k), S.glr(k)];
varargout = {x, F};
end

function O = offsets(G)
% Offset of every antenna from the median of the others per cycle [dB] (E x nr x n).
[~, nr, ~] = size(G);
O = zeros(size(G));
for a = 1:nr
    O(:, a, :) = G(:, a, :) - median(G(:, setdiff(1:nr, a), :), 2);
end
end

function S = fit(o)
% Least-squares step and ramp fits of every column of o (n x E, oldest first).
[n, E] = size(o);
[tau, R] = ndgrid(2:n, 1:2 * n);
tau = tau(:)'; R = R(:)';
t = (1:n)';
H = min(1, max(0, (t - tau + 1) ./ R));                    % n x M fall shapes
Hc = H - mean(H, 1);
Sxx = sum(Hc .^ 2, 1)';                                    % M x 1
oc = o - mean(o, 1);
Syy = sum(oc .^ 2, 1);                                     % 1 x E
Sxy = Hc' * oc;                                            % M x E
b = Sxy ./ Sxx;                                            % slope: minus the depth
SSE = Syy - Sxy .^ 2 ./ Sxx;
SSE(b >= 0) = Inf;                                         % a fall only
st = R == 1;
[Ss, is] = min(SSE(st, :), [], 1);
[Sr, ir] = min(SSE(~st, :), [], 1);
[~, ia] = min(SSE, [], 1);
js = find(st); jr = find(~st);
s2 = max(min(Ss, Sr) / max(n - 3, 1), 0.25);               % residual variance, at least (0.5 dB)^2
g = (Ss - Sr) ./ s2;
g(~isfinite(g)) = 0;
S.depth = reshape(-b(sub2ind(size(b), js(is), 1:E)), E, 1);
S.depth(~isfinite(Ss)) = 0;
S.tau = reshape(tau(ia), E, 1);
S.R = reshape(R(ia), E, 1);
S.glr = reshape(g, E, 1);
S.R_ramp = reshape(R(jr(ir)), E, 1);
end

function [st, pf, cause] = latch(st, g, pf, classes, heal, thr, C_LOST, K_DIAG, N_HIST)
% One cycle of the latched diagnosis over E episodes (st.glr: the statistic at the diagnosis).
[E, nr] = size(g);
if isempty(st)
    st = struct('H', repmat(double(g), 1, 1, N_HIST), 'n', zeros(E, 1), 'on', false(E, 1), 'ant', zeros(E, 1), ...
        'ref', zeros(E, 1), 'age', zeros(E, 1), 'ok', zeros(E, 1), 'cause', zeros(E, 1), 'glr', nan(E, 1));
end
st.H = cat(3, st.H(:, :, 2:end), double(g)); st.n = min(st.n + 1, N_HIST);
cause = st.cause;
if nr < 2, return; end
O = offsets(st.H);
cur = median(O(:, :, end-2:end), 3);                       % E x nr
for e = find(~st.on & st.n >= 6)'                          % an onset: the branch falls below its earlier cycles
    ref = median(O(e, :, N_HIST - st.n(e) + 1:N_HIST - 3), 3);
    [dm, a] = max(ref - cur(e, :));
    if dm >= C_LOST
        st.on(e) = true; st.ant(e) = a; st.ref(e) = ref(a); st.age(e) = 0; st.ok(e) = 0; st.cause(e) = 0;
    end
end
on = find(st.on)';
for e = on
    st.age(e) = st.age(e) + 1;
    lost = st.ref(e) - cur(e, st.ant(e)) >= C_LOST;
    st.ok(e) = (st.ok(e) + 1) * ~lost;
    if st.ok(e) >= heal                                     % the branch has recovered: the event is over
        st.on(e) = false; st.cause(e) = 0; continue
    end
    if st.cause(e) == 0 && st.age(e) >= K_DIAG
        S = fit(reshape(O(e, st.ant(e), N_HIST - st.n(e) + 1:N_HIST), [], 1));
        st.cause(e) = 1 + (S.glr > thr); st.glr(e) = S.glr;
    end
end
cause = st.cause;
classes = cellstr(string(classes));
iF = find(strcmp(classes, 'antenna_fault'), 1); iS = find(strcmp(classes, 'airframe_shadowing'), 1);
if isempty(iF) || isempty(iS), return; end
[~, k] = max(pf, [], 2);
m = cause > 0 & (k == iF | k == iS);
if any(m)
    tot = pf(m, iF) + pf(m, iS);
    pf(m, [iF iS]) = 0;
    sh = cause(m) == 2;
    pf(find(m), iF) = tot .* ~sh; %#ok<FNDSB>
    pf(find(m), iS) = tot .* sh; %#ok<FNDSB>
end
end

function [pf, cause] = sequence(G, pf, classes, heal, thr)
% The latch over the n cycles of one run (G n x nr, pf n x C).
n = size(G, 1); cause = zeros(n, 1); st = [];
for t = 1:n
    [st, pf(t, :), cause(t)] = onset_shape('latch', st, G(t, :), pf(t, :), classes, heal, thr);
end
end

function g = events(G)
% os_glr at the latch's diagnosis of the first event of one run, NaN without one.
n = size(G, 1); st = []; g = NaN; pf = zeros(1, 1);
for t = 1:n
    [st, ~, c] = onset_shape('latch', st, G(t, :), pf, {'none'}, Inf, 0);
    if c > 0, g = st.glr; return; end
end
end

function thr = choose(g, y)
% The threshold of the largest mean share read right (a ramp above it, a step at or
% below), on a grid of 0.25 from -8 to 8, the one nearest 0 among equals.
thr = 0; g = g(:); y = y(:);
k = isfinite(g);
if ~any(y(k) == 1) || ~any(y(k) == 2), return; end
T = -8:0.25:8;
ba = arrayfun(@(t) (mean(g(k & y(:) == 1) <= t) + mean(g(k & y(:) == 2) > t)) / 2, T);
best = find(ba >= max(ba) - 1e-12);
[~, i] = min(abs(T(best)));
thr = T(best(i));
end
