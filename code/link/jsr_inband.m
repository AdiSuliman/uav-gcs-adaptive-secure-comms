function L = jsr_inband(jsr_tot, bj_mhz, mode, p)
%JSR_INBAND  In-band level of a jammer of total power JSR_tot over our signal (the bandwidth
%   study, experiment_core_bw.m), as the link model's level fields read it.
%   L = jsr_inband(jsr_tot, bj_mhz)   closed form [dB]: a CW tone (bj_mhz 0) keeps its whole
%       power in our channel, L = JSR_tot (tone_jsr_db); a flat noise jammer of width bj_mhz
%       that covers our channel puts the share R_s / B_J of its power in it,
%       L = JSR_tot - 10 log10(B_J / R_s) (jsr_db). The model's two fields are equal in band
%       after the matched filter (a tone of tone_jsr_db carries 1/sps of the window's noise
%       power at the same jsr_db, build_threat_model.m), so no other factor enters.
%   L = jsr_inband(jsr_tot, bj_mhz, 'numeric')  the same from the integral of our matched
%       filter's raised-cosine response over a flat jammer centred on our channel: the check
%       of the closed form, and the value of a jammer narrower than our band
%   T = jsr_inband(L, bj_mhz, 'total')  the inverse: the total power of an in-band level
%   p  optional link params (symbol_rate, rolloff); defaults 1 Msym/s and 0.25.
%   Liu et al. define the ratio by total powers (a 30 dBm jammer against a 0 dBm signal).
if nargin < 3 || isempty(mode), mode = 'closed'; end
rs = 1; ro = 0.25;
if nargin > 3 && isfield(p, 'symbol_rate'), rs = p.symbol_rate / 1e6; end
if nargin > 3 && isfield(p, 'rolloff'), ro = p.rolloff; end
bj = bj_mhz;
switch mode
    case 'closed'
        L = jsr_tot - 10 * log10(max(bj, rs) / rs) .* (bj > 0);
    case 'total'
        L = jsr_tot + 10 * log10(max(bj, rs) / rs) .* (bj > 0);
    case 'numeric'
        jt = jsr_tot + 0 * bj; b = bj + 0 * jsr_tot;
        L = jt;
        for i = find(b(:)' > 0)
            f = linspace(-b(i) / 2, b(i) / 2, 200001);
            L(i) = jt(i) + 10 * log10(trapz(f, rc(f, rs, ro)) / b(i));
        end
    otherwise
        error('jsr_inband:mode', 'jsr_inband: unknown mode %s', mode);
end
end

function P = rc(f, rs, ro)
% Raised-cosine power response of the matched filter, 1 in its flat part: its integral is rs.
a = abs(f); f1 = (1 - ro) * rs / 2; f2 = (1 + ro) * rs / 2;
P = double(a <= f1);
t = a > f1 & a <= f2;
P(t) = 0.5 * (1 + cos(pi / (ro * rs) * (a(t) - f1)));
end
