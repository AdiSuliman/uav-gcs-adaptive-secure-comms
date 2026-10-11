function g = set_link_snr(mdl, snr_dB, p)
%SET_LINK_SNR  Received level of the threat link for a per-sample SNR of our signal.
%   g = set_link_snr(mdl, snr_dB, p): snr_dB is our signal's power per sample (1/sps at
%   unit symbol energy) over the thermal noise per sample, Eb/N0 + 10 log10(bps) -
%   10 log10(sps) plus any link-budget offset. The thermal noise stays fixed
%   (thermal_nv.m) and the gain block 'Level' scales everything the antennas receive, our
%   signal and every interferer, so Eb/N0 is our signal over thermal noise and every
%   interferer keeps its level over our received signal (JSR, INR and SIR as the sources
%   define them). g: the amplitude gain set.
g = sqrt(10^(snr_dB / 10) * p.sps * thermal_nv(p));
set_param([mdl '/Level'], 'Gain', sprintf('%.12g', g));
end
