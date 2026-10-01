# Source notes 13: detecting low-occupancy WLAN interference vs a clean channel
(research only, no decisions; fork session cdaee0, 2026-10-01)

## A. Energy-detection limit under noise-power uncertainty (SNR wall) (read)
M. S. Shbat, V. Tuzlukov, "SNR Wall Effect Alleviation by Generalized Detector Employed in Cognitive Radio Networks",
Sensors 15, 16105-16135, 2015, doi 10.3390/s150716105. https://pmc.ncbi.nlm.nih.gov/articles/PMC4541870/
(restating R. Tandra, A. Sahai, "SNR walls for signal detection", IEEE J. Sel. Topics Signal Process. 2(1), 2008)
- Eq. (41): SNR_wall^ED = (rho^2 - 1)/rho, with eq. (33) rho = 10^(0.1 epsilon), epsilon = noise-power uncertainty in dB.
- "For example, at epsilon=1 dB, the SNR_wall^ED = -3 dB, and at epsilon=0.1 dB, the SNR_wall^ED = -13 dB."
- Eq. (40): N_ED = [rho Q^-1(P_FA) - rho^-1 Q^-1(1-P_miss)]^2 / (M [SNR - (rho - rho^-1)]^2); "the sample complexity N_ED
  is inversely proportional to the squared SNR".
- (Relevance, not a decision: a signal-free interval measured by the receiver itself pins the noise power, i.e. lowers
  epsilon, which is what moves the wall.)

## B. WLAN's own detection thresholds (search summary of IEEE 802.11 CCA text; not read in the standard)
- Via search summary of IEEE 802.11-14/1518r5 (mentor.ieee.org/802.11/dcn/14/11-14-1518-05, Nov 2014; site blocks the
  fetcher): "the start of a valid OFDM transmission at a receive level equal to or greater than the minimum modulation
  and coding rate sensitivity (-82 dBm for 20 MHz channel spacing) shall cause CCA-CS to indicate busy with a
  probability > 90% within 4 us"; energy detect holds busy "for any signal 20 dB above the minimum modulation and coding
  rate sensitivity", i.e. -62 dBm for 20 MHz.
- I.e. preamble (feature) detection is specified 20 dB more sensitive than plain energy detection in 802.11 itself.

## C. Occupancy / duty-cycle measurement (bibliographic, not read)
- M. Wellens, P. Mahonen, "Lessons Learned from an Extensive Spectrum Occupancy Measurement Campaign and a Stochastic
  Duty Cycle Model", Mobile Networks and Applications 15(3), 461-474, 2010 (earlier TRIDENTCOM 2009).
- Already in project sources: Wollenberg (W08, 802.11 channel occupancy, packet lengths 0.27-3.2 ms) and Cheema
  (spectrum occupancy 5-86%).
