function g = sweep_window_s(p)
%SWEEP_WINDOW_S  Part of every sweep in which the sweeping jammer is on our channel [s].
%   g = sweep_window_s(p): [start end] from the moment its band reaches our channel. Its
%   instantaneous band (p.sweep_bw_hz) overlaps our signal's ((1 + roll-off) x symbol rate)
%   for (jammer band + our band) / sweep speed: 5.25 ms at 4 MHz, 1.25 MHz and 1 GHz/s.
%   With frequency diversity (p.sweep_fdiv) a frame is lost only while both carriers are
%   inside the jammer's band at once: the second carrier, p.fdiv_spacing_hz away, is
%   reached spacing / speed later, so the window starts there; it is empty from a spacing
%   of the two bands' sum up.
bw = p.sweep_bw_hz + p.symbol_rate * (1 + p.rolloff);
g = [0, bw / p.sweep_speed_hz_s];
if isfield(p, 'sweep_fdiv') && p.sweep_fdiv
    g(1) = min(p.fdiv_spacing_hz / p.sweep_speed_hz_s, g(2));
end
end
