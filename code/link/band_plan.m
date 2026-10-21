function B = band_plan(p)
%BAND_PLAN  Channel plan of the bandwidth study (experiment_core_bw.m): 41 channels at
%   2401 + 2k MHz, k = 0..40, inside the 2400-2483.5 MHz band (ETSI EN 300 328).
%   The 2 MHz spacing is the nRF24L01+'s for non-overlapping channels at 2 Mb/s, our raw
%   rate (its carrier 2400 + RF_CH MHz); it is at least our occupied bandwidth, as ETSI
%   requires of a hopping separation. The plan holds 2481 MHz, the channel Mekdad et al.
%   jammed, and more than ETSI's 15 channels of an adaptive hopper.
%   B = band_plan(p): p the link params (symbol_rate, rolloff); defaults 1 Msym/s and 0.25.
%   B.f_mhz   1 x 41 channel centres [MHz]; B.k their RF index 0..40
%   B.b_ch    our occupied bandwidth (1 + roll-off) x symbol rate [MHz]
%   B.band    [2400 2483.5] MHz; B.spacing 2 MHz; B.centre index of the plan's middle channel
rs = 1e6; ro = 0.25;
if nargin > 0 && isfield(p, 'symbol_rate'), rs = p.symbol_rate; end
if nargin > 0 && isfield(p, 'rolloff'), ro = p.rolloff; end
B.k = 0:40;
B.f_mhz = 2401 + 2 * B.k;
B.spacing = 2;
B.b_ch = (1 + ro) * rs / 1e6;
B.band = [2400 2483.5];
B.centre = 21;
assert(B.f_mhz(1) - B.b_ch / 2 >= B.band(1) && B.f_mhz(end) + B.b_ch / 2 <= B.band(2), ...
    'band_plan: the plan leaves the 2400-2483.5 MHz band');
assert(B.spacing >= B.b_ch, 'band_plan: spacing %.2f MHz below the occupied bandwidth %.2f MHz', B.spacing, B.b_ch);
end
