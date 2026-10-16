function nv = thermal_nv(p)
%THERMAL_NV  Thermal noise power per sample of every receive antenna, in model units.
%   nv = thermal_nv(p): the receiver's noise floor (kTB times its noise figure) is fixed;
%   the received fields scale with distance instead (set_link_snr.m). The unit is N0 at
%   Eb/N0 = 0 dB for our signal at unit symbol energy: 1 / p.bits_per_symbol. The AWGN
%   block of the threat link adds this variance, and the receiver measurements take it
%   as their calibration constant (extract_closed_loop_frames.m, spec_image.m).
nv = 1 / p.bits_per_symbol;
end
