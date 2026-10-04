function a = inband_cap_amp(L, PL, cap)
%INBAND_CAP_AMP  Constant of the in-band cap of one additive threat component.
%   a = inband_cap_amp(L, PL, cap) = 10^((cap - L - PL)/20): L the component's level over
%   our signal [dB], PL the path loss of our signal [dB], cap the largest level over our
%   received signal (p.inband_cap_db). The threat block scales the component by
%   min(1, a * gcs * min(bdy)), gcs the amplitude of our signal after pointing and elevation
%   loss and bdy its airframe amplitude on each antenna (flight_draws.m), so on the weakest
%   antenna it reaches min(L + PL - 20 log10(gcs min(bdy)), cap) dB over our received signal.
a = 10.^((cap - L - PL) / 20);
end
