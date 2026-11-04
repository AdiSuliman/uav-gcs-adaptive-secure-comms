function S = cfo_joint(G, tb, fmax)
%CFO_JOINT  Common carrier-frequency offset of one frame from all antennas jointly, beside
%   each antenna's own phase slope (D121 item 13; a diagnostic, an input to the receiver
%   candidate that follows D3; no receiver or registered reading uses it).
%   G   NR x NB complex channel gain of every antenna at the NB pilot blocks (the phase of
%       the pilot channel at each block, as the receiver's equalizer training forms it)
%   tb  1 x NB block times [s], increasing
%   fmax  search half-width [Hz] (default 0.5 / median block spacing)
%   S.slope_hz   NR x 1  each antenna's linear-phase fit alone (least squares on its
%                unwrapped phase against tb): the model a fade breaks, since random FM
%                near a deep fade moves the phase by more than the Doppler in a block
%   S.joint_hz   the common offset: the f that maximises sum |c| cos(arg c - 2 pi f dt) over
%                every antenna's block-to-block increment c = G(k+1) conj(G(k)), so deep
%                fades carry little weight (the power-weighted phasor)
%   S.resid_hz   NR x 1  each antenna's residual slope after the common offset
%   S.resid_rad  NR x 1  rms of each antenna's residual phase about its mean (the time
%                variation a BEM or PSAM tracker would carry)
%   S.w          NR x 1  each antenna's share of the joint estimate's weight
%   S.spread_hz  max - min of slope_hz over the antennas; S.dev_hz = slope_hz - joint_hz
% Inputs only: the gains and their times.
[NR, NB] = size(G);
tb = tb(:).';
if numel(tb) ~= NB, error('cfo_joint:size', 'tb must have one time per column of G'); end
S = struct('slope_hz', nan(NR, 1), 'joint_hz', NaN, 'resid_hz', nan(NR, 1), ...
    'resid_rad', nan(NR, 1), 'w', nan(NR, 1), 'spread_hz', NaN, 'dev_hz', nan(NR, 1));
if NB < 3 || any(diff(tb) <= 0), return; end
t0 = tb - mean(tb);
for r = 1:NR
    g = G(r, :);
    if all(abs(g) > 0)
        S.slope_hz(r) = lsline(t0, unwrap(angle(g))) / (2 * pi);
    end
end
dt = diff(tb);
if nargin < 3 || isempty(fmax), fmax = 0.5 / median(dt); end
C = G(:, 2:end) .* conj(G(:, 1:end-1));                  % NR x (NB-1) increments
mag = abs(C); ang = angle(C);
J = @(f) -sum(sum(mag .* cos(ang - 2 * pi * f * dt)));
fg = linspace(-fmax, fmax, 4001);
Jg = arrayfun(J, fg);
[~, i0] = min(Jg);
lo = fg(max(1, i0 - 1)); hi = fg(min(numel(fg), i0 + 1));
S.joint_hz = fminbnd(J, lo, hi, optimset('TolX', 1e-6));
wr = sum(mag, 2);
S.w = wr / max(sum(wr), eps);
for r = 1:NR
    g = G(r, :) .* exp(-1j * 2 * pi * S.joint_hz * t0);
    if all(abs(g) > 0)
        p = unwrap(angle(g));
        S.resid_hz(r) = lsline(t0, p) / (2 * pi);
        S.resid_rad(r) = sqrt(mean((p - mean(p)).^2));
    end
end
S.spread_hz = max(S.slope_hz) - min(S.slope_hz);
S.dev_hz = S.slope_hz - S.joint_hz;
end

function b = lsline(t, p)
% Slope [rad/s] of the least-squares line through (t, p).
t = t(:); p = p(:);
tm = mean(t);
b = sum((t - tm) .* (p - mean(p))) / max(sum((t - tm).^2), eps);
end
