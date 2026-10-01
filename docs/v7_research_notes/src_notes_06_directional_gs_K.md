# Source notes 6a: ground antenna type vs measured K-factor and Doppler (directional vs omni)
(research only, no decisions; fork session cdaee0, 2026-10-01)

J. Rodriguez-Pineiro, T. Dominguez-Bolano, X. Cai, Z. Huang, X. Yin, "Air-to-Ground Channel Characterization for
Low-Height UAVs in Realistic Network Deployments", IEEE Trans. Antennas Propag., 2020. arXiv: https://arxiv.org/abs/2007.11502
- Setup (Table I): 2.5 GHz; 40 dBm; "0 dBi (omnidirectional, UAV and BS)", "12 dBi (directional, BS)", BS height 15 m;
  UAV flight heights 15-105 m; UAV speed 5 m/s ("coherent with the low speed considered for the UAV of 5 m/s").
- "the effect of the radiation pattern of the directional antenna used at the BS was not removed because we are
  interested" in the realistic deployment (the directional antenna is a down-tilted cellular sector, not pointed at
  the UAV; "the UAV can receive contributions from the main lobe" only at larger horizontal distance).
- K-factor fits (normal, (mean, variance), dB), Environment I:
    omni:        15 m 15.82 | 25 m 14.46 | 35 m 12.67 | 45 m 13.50 | 60 m 11.64 | 75 m 14.35 | 90 m 15.01 | 105 m 14.02
    directional: 15 m  5.54 | 25 m 11.37 | 35 m  9.30 | 45 m  8.19 | 60 m 11.23 | 75 m 10.30 | 90 m 10.00 | 105 m 9.19
  i.e. with this non-pointed 12 dBi sector, the measured K was 2.4-10 dB LOWER than with the omni.
- RMS Doppler spread fits (log10 Hz, (mean, variance)): Env I omni 0.50-0.86, directional 0.99-1.40; Env II similar
  (values in Table VIII).
- Conclusions: "The channel characteristics that are more dependent with the flight height and the UAV-BS distance are
  the path loss and the Ricean K-Factor."

Contrast (already in gcs_directional_notes.md): Sun dissertation's review of [35] (2.3 GHz): multipath "suppressed by
using a very high gain tracking receiver antenna which yields very narrow beamwidth" -> a tracked, pointed beam raises K;
a fixed sector with the UAV off its main lobe can lower it (this paper).
