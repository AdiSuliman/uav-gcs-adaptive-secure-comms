function [R, d, Rx] = band_reject(J, fj, B)
%BAND_REJECT  Our receiver's effective rejection of a jammer on each channel of the plan (the
%   bandwidth study, band_plan.m), from the nRF24L01+'s selectivity at 2 Mb/s, our raw rate
%   (Nordic 2008, Table 8, ETSI EN 300 440-1, measured 0 to +-40 MHz in 1 MHz steps): C/I +7
%   dBc co-channel, +3 at 2 MHz, -17 at 4 MHz, -21 at 6 MHz, -40 beyond 12 MHz, -48 beyond
%   36 MHz, about 5 dB worse than the adjacent figures at n x 2 f_xtal (32 and 64 MHz, f_xtal
%   16 MHz). The rejection at an offset is the co-channel C/I minus the offset's, the row at
%   or below it: 4 dB from 2 MHz, 24 from 4, 28 from 6 to 12, 47 beyond 12, 55 beyond 36; 42
%   dB strictly between the measured points next to 32 MHz (31-33 MHz); past the measured
%   +-40 MHz the open > 36 MHz row (55 dB) and the footnote's n x 2 f_xtal rule at the same
%   +-1 MHz width (50 dB over 63-65 MHz); 0 below 2 MHz, where the sheet's only row is
%   co-channel. These rows are the sheet's most severe at every
%   offset from 2 MHz: the 1 Mb/s rows give 29, 39, 49 and 56 dB, Table 9 (a modulated
%   interferer) 7, 29, 35, 51 and 59 dB; at 2 Mb/s the nRF's 20 dB bandwidth is 2 MHz, ours
%   1.25 MHz.
%   The effective rejection counts the jammer's whole spectrum against the power it puts in
%   our channel when it covers it (its in-band level, jsr_inband.m), in slices no wider than
%   the sheet's 1 MHz step, each at its offset's rejection:
%       R_eff = -10 log10( sum (P_slice / P_ref) 10^(-rej(offset) / 10) )
%   a flat jammer at its in-band density over its span, a raised cosine (J.rs, J.ro) by its
%   shape, P_ref its flat part over 1 MHz; a tone, all its power at one offset of its range,
%   at the lowest rejection over that range.
%   [R, d, Rx] = band_reject(J, fj, B)
%   J   jammer (band_cells.m): kind, its span (band_cover('span', J, fj)), rs and ro
%   fj  the frequency the jammer is tuned to [MHz] (tone, centred; ignored for a fixed one)
%   B   channel plan (band_plan.m)
%   R   per channel R_eff [dB]; 0 on a covered or partial channel (band_cover.m), on one
%       clear of the jammer by under 2 MHz, and where R_eff < 2 dB: its layer at or below is
%       0 dB, the frames without channel_switch, as on a covered channel
%   d   distance from the channel centre to the jammer's nearest frequency [MHz]
%   Rx  R_eff before the 2 dB floor (0 on covered channels)
%   v = band_reject('values', Js, B)   every R > 0 the jammers Js (cell array) meet on some
%       channel of plan B, tuned to any of its channels (tone, centred) or where they sit
%   g = band_reject('grid', v)    the residual's layers for values v [dB]: ascending, each the
%       first value more than 2 dB above the layer before it, floored to 0.1 dB, so every value
%       has a layer at or below it within 2 dB
%   i = band_reject('layer', R, g)   per R its layer's index in g, the largest at or below it
%       (0 for R = 0 or below every layer)
%   r = band_reject('rows', x)    the sheet's rejection at offsets x [MHz]
if ischar(J)
    switch J
        case 'values'
            Js = fj; v = [];
            for k = 1:numel(Js)
                c = B.f_mhz; if strcmp(Js{k}.kind, 'fixed'), c = NaN; end
                for x = c, v = [v, band_reject(Js{k}, x, B)]; end %#ok<AGROW>
            end
            R = unique(v(v > 0));
        case 'grid'
            v = sort(fj(fj >= 2)); R = zeros(1, 0);
            for x = v(:)'
                if isempty(R) || x > R(end) + 2 + 1e-9, R(end + 1) = floor(10 * x + 1e-9) / 10; end %#ok<AGROW>
            end
        case 'layer'
            g = B; R = zeros(size(fj));
            for k = find(fj(:) > 0)'
                j = find(g <= fj(k) + 1e-9, 1, 'last');
                if ~isempty(j), R(k) = j; end
            end
        case 'rows'
            R = rows_db(fj);
        otherwise
            error('band_reject:cmd', 'band_reject: unknown command %s', J);
    end
    return
end
sp = band_cover('span', J, fj);
[cv, ~, d] = band_cover(sp, B.f_mhz, B.b_ch);
Rx = zeros(size(B.f_mhz));
for i = find(~cv & d >= 2)
    Rx(i) = eff_one(J, sp, fj, B.f_mhz(i));
end
R = Rx; R(R < 2) = 0;
end

function r = eff_one(J, sp, fj, fc)
% R_eff of the jammer of span sp on the channel at fc, clear of it.
S = spurs();
if strcmp(J.kind, 'tone')
    x = sort(abs(sp - fc));
    r = rows_db(x(1));
    for k = 1:size(S, 1)
        if x(1) < S(k, 1) + 1 && x(2) > S(k, 1) - 1, r = min(r, S(k, 2)); end
    end
    return
end
br = [2 4 6 12 36, S(:, 1)' - 1, S(:, 1)' + 1];              % offsets where the rejection changes
e = [sp(1):1:sp(2), sp(2), fc - br, fc + br];               % 1 MHz slices, split there
e = unique(round(e(e >= sp(1) & e <= sp(2)) * 1e9) / 1e9);
a = e(1:end - 1); b = e(2:end);
if isfield(J, 'rs') && isfinite(J.rs)
    w = rc_int(b - fj, J.rs, J.ro) - rc_int(a - fj, J.rs, J.ro);
else
    w = b - a;
end
r = -10 * log10(sum(w .* 10 .^ (-rows_db(abs((a + b) / 2 - fc)) / 10)));
end

function r = rows_db(x)
% The sheet's rejection at offsets x [MHz]: the row at or below x, the crystal's offsets 5 dB
% under the rows next to them.
r = zeros(size(x));
r(x >= 2) = 4; r(x >= 4) = 24; r(x >= 6) = 28; r(x > 12) = 47; r(x > 36) = 55;
S = spurs();
for k = 1:size(S, 1)
    m = x > S(k, 1) - 1 & x < S(k, 1) + 1;
    r(m) = min(r(m), S(k, 2));
end
end

function S = spurs()
% n x 2 f_xtal [MHz] and the rejection there [dB]: the adjacent rows' 47 and 55 less 5 dB.
S = [32 42; 64 50];
end

function F = rc_int(u, rs, ro)
% Integral from 0 to u [MHz] of a raised cosine of symbol rate rs and roll-off ro, 1 in its
% flat part: rs / 2 over each side.
a = abs(u); f1 = (1 - ro) * rs / 2; f2 = (1 + ro) * rs / 2;
F = min(a, f1);
t = a > f1;
y = min(a(t), f2) - f1;
F(t) = f1 + 0.5 * y + 0.5 * ro * rs / pi * sin(pi * y / (ro * rs));
F = sign(u) .* F;
end
