function [cov, st, off] = band_cover(sp, f_mhz, b_ch)
%BAND_COVER  Which channels of the plan a jammer covers (the bandwidth study, band_plan.m).
%   [cov, st, off] = band_cover(sp, f_mhz, b_ch)
%   sp     the jammer's span [lo hi] in MHz (band_cover('span', ...))
%   f_mhz  channel centres [MHz]; b_ch our occupied bandwidth [MHz]
%   st     per channel 1 covered (our band inside the span), 0 escaped (our band clear of it,
%          touching counts as clear), 2 partial (anything else); a tone inside our band
%          covers it
%   cov    st > 0: a partial cover counts as covered, conservative against channel_switch
%   off    distance from the channel centre to the jammer's nearest frequency [MHz], 0
%          inside the span
%   sp = band_cover('span', J, f_home)  the span of jammer J (band_cells.m) when our home
%          channel is at f_home: kind 'tone' f_home +- J.half (the tone's offset range),
%          'centred' f_home +- J.half (the jammer tuned to our channel, Mekdad et al.),
%          'fixed' [J.lo J.hi] wherever our channel is
if ischar(sp) && strcmp(sp, 'span')
    J = f_mhz; fh = b_ch;
    switch J.kind
        case {'tone', 'centred'}, cov = fh + [-J.half, J.half];
        case 'fixed',             cov = [J.lo, J.hi];
        otherwise, error('band_cover:kind', 'band_cover: unknown jammer kind %s', J.kind);
    end
    return
end
lo = sp(1); hi = sp(2); h = b_ch / 2;
a = f_mhz - h; b = f_mhz + h;
st = 2 * ones(size(f_mhz));
st(b <= lo | a >= hi) = 0;
st(a >= lo & b <= hi) = 1;
if hi - lo < b_ch, st(a < lo & b > hi) = 1; end      % a span narrower than our band inside it
cov = st > 0;
off = max(0, max(lo - f_mhz, f_mhz - hi));
end
