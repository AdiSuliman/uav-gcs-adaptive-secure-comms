# Source notes 4: hover channel, measured numbers
(research only, no decisions; fork session cdaee0, 2026-10-01)

## 1. USC sounder: static (pole) vs hovering drone, same spot (read in full)
J. Gomez-Ponce, T. Choi, N. A. Abbasi, A. Adame, A. Alvarado, C. Bullard, R. Shen, F. Daneshgaran, H. S. Dhillon,
A. F. Molisch, "Air-to-Ground Directional Channel Sounder With 64-antenna Dual-polarized Cylindrical Array",
arXiv:2103.09135 (Feb 2021). https://arxiv.org/pdf/2103.09135
- 3.5 GHz, 46 MHz bandwidth; DJI Matrice 600 Pro carrying the Tx; LOS courtyard.
- "we anticipate that variations of the receive power will be higher in the hovering scenario because of the vibrations
  of the drone and the inability of hovering to keep the drone in exactly the same location."
- "the standard deviation for the LOS bin power is 0.08dB for the static case and 0.48dB for hovering."
- Table III (mean, std): RMS delay spread [dBs] static -78.52 (0.08), hover -79.44 (0.27).
- "even small movements of the drone can lead to time variations of the received power ... and so decreases the
  channel coherence time" (citing Banagar et al.).
- "the power in the V-polarization is approximately 12dB higher than in the H-polarization" (Tx vertically polarized).

## 2. Hover attitude jitter, calm vs windy (abstract only)
LIN Zehong, LIANG Mengyu, LAI Jiajie, LI Jianlin, ZHANG Rui, GU Yifan, BI Suzhi, QUAN Zhi, "Measurement and Analysis of
the Impact of UAV Attitude Jitter on Low-Altitude A2G Channel Non-Stationarity", Journal of Signal Processing (Xinhao
Chuli), 2026, 42(1): 95-108, doi 10.12466/xhcl.2026.01.009.
https://signal.ejournal.org.cn/en/article/doi/10.12466/xhcl.2026.01.009
- Field measurement: hover at 40 m, calm and windy; synchronized CIR + IMU (pitch, roll, yaw) + GPS.
- Channel stationarity time: "over 40 ms" (calm) vs "as low as 1 ms" (windy).
- Mechanism: attitude instability "couples with the non-isotropic radiation characteristics of the airborne antenna",
  making "the LoS path ... rapidly sweep across the antenna's gain null" regions.
- Not in the abstract: frequency, bandwidth, airframe, jitter angles, fade depth.

## 3. Analytical (no measured numbers)
M. Banagar, H. S. Dhillon, A. F. Molisch, "Impact of UAV Wobbling on the Air-to-Ground Wireless Channel", arXiv:2004.02771
(2020), later IEEE TVT. Wiener and sinusoidal wobbling models; "even for small UAV wobbling, the coherence time of the
channel may degrade quickly". The search-engine summary says wobbling is typically < 10 deg; not verified in the paper text.

## 4. Slow vertical motion (fixed-wing VTOL, read)
Y. Lyu, Y. He, Z. Liang, W. Wang, J. Yu, D. Shi, "Measurement-Based Tapped Delay Line Channel Modeling for Fixed-Wing
UAV Air-to-Ground Communications at S-Band", Drones 8(9):492, 2024, doi 10.3390/drones8090492.
- "The UAV descends vertically ... with a speed of 1.2 m/s, which results in a maximum Doppler frequency 10.8 Hz" (2.7 GHz).
- Descent phase: amplitude "found to follow the normal distribution, which usually implies a large value of the
  K-factor".
