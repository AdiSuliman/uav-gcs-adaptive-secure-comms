function [R, d] = band_reject(sp, f_mhz, b_ch)
%BAND_REJECT  Our receiver's rejection of a jammer on each channel of the plan (the bandwidth
%   study, band_plan.m): the nRF24L01+'s selectivity at 2 Mb/s, our raw rate (Nordic 2008,
%   Table 8, ETSI EN 300 440-1): C/I +7 dBc co-channel, +3 at 2 MHz, -17 at 4 MHz, -21 at
%   6 MHz, -40 beyond 12 MHz, -48 beyond 36 MHz, about 5 dB worse at the offsets n x 2 f_xtal
%   (32 and 64 MHz, f_xtal 16 MHz). The rejection is the co-channel C/I minus the offset's.
%   Its rows are the sheet's most severe at every offset from 2 MHz: the 1 Mb/s rows give 29,
%   39, 49 and 56 dB, Table 9 (a modulated interferer) 7, 29, 35, 51 and 59 dB; at 2 Mb/s the
%   nRF's 20 dB bandwidth is 2 MHz, ours 1.25 MHz.
%   [R, d] = band_reject(sp, f_mhz, b_ch)
%   sp     the jammer's span [lo hi] in MHz (band_cover('span', ...))
%   f_mhz  channel centres [MHz]; b_ch our occupied bandwidth [MHz]
%   R      per channel the rejection [dB], the lowest the sheet gives over the offsets the
%          jammer occupies (d up to its far edge): 4 from 2 MHz, 24 from 4, 28 from 6 to 12,
%          47 beyond 12, 55 beyond 36; 42 or 50 where it occupies 32 or 64 MHz. 0 on a
%          covered or partial channel (band_cover.m) and below 2 MHz, where the sheet's only
%          row is co-channel: such a channel counts as covered
%   d      distance from the channel centre to the jammer's nearest frequency [MHz]
%   v = band_reject('levels')         every rejection an escaped hop can take [dB]
%   v = band_reject('layers', J, B)   those jammer J (band_cells.m) meets on some channel of
%          plan B (band_plan.m): centred on any channel (tone, centred) or where it sits (fixed)
if ischar(sp)
    switch sp
        case 'levels'
            R = [4 24 28 42 47 50 55];
        case 'layers'
            J = f_mhz; B = b_ch;
            c = B.f_mhz; if strcmp(J.kind, 'fixed'), c = NaN; end
            v = [];
            for x = c, v = [v, band_reject(band_cover('span', J, x), B.f_mhz, B.b_ch)]; end %#ok<AGROW>
            R = unique(v(v > 0));
        otherwise
            error('band_reject:cmd', 'band_reject: unknown command %s', sp);
    end
    return
end
[~, st, d] = band_cover(sp, f_mhz, b_ch);
far = max(abs(f_mhz - sp(1)), abs(f_mhz - sp(2)));
R = arrayfun(@rows_db, d);
for x = [32 64]                                        % n x 2 f_xtal
    in = d <= x & far >= x;
    R(in) = min(R(in), rows_db(x) - 5);
end
R(st > 0 | d < 2) = 0;
end

function r = rows_db(x)
% The sheet's rejection at offset x [MHz], its value at the nearest row below x.
if x < 2, r = 0;
elseif x < 4, r = 4;
elseif x < 6, r = 24;
elseif x <= 12, r = 28;
elseif x <= 36, r = 47;
else, r = 55;
end
end
