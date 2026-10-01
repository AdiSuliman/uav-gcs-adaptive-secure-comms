# Antenna, platform and receiver-hardware sources: what each proves and how it helps (re-review, 2026-10-01)

Conventions. `L/` = library folder `C:\Users\Adi Suliman\Desktop\תואר ראשון  הנדסת חשמל ואלקטרוניקה\שנה ד\פרוייקט גמר\מקורות\`.
Text extracts made for this review are in `_extracts_antenna/` next to this file (mr2021.txt, mr2021_utf8.txt,
enquebecq_utf8.txt, ginart2012.txt, badi2019.txt, badi2020.txt, yanmaz2013.txt, en300328_v222.txt). Quotes are verbatim from the
PDF text; symbols lost in extraction are restored only where a UTF-8 re-extraction showed them. "Inference" = my arithmetic or
reasoning, not in the source. UNVERIFIED = not read in a source during this review. No design decisions are made here.

## Q1. What each assigned source measured or derived, with the numbers that matter (per source)

### Takeaway
Of the 17 assigned sources, only a few carry measured numbers that the project can use directly: Verbeke 2016 (frame modes
86-672 Hz), the two connector-fretting papers (DC resistance in mOhm to Ohm, S21 change 0.15-0.37 dB, a phase-noise spur at the
vibration frequency), Nugroho 2018 (tracker error 5.62 deg / 1.51 deg, 202 s GNSS start-up fault), ITU-R F.1336-5 (pattern
envelopes), Winters 1994 (M-N+1 diversity rule), the 802.11b draft / Anritsu (+-25 ppm) and ETSI EN 300 328 (EIRP and PSD caps).
Cheng 2006, Ahmed 2011 and Matson 2021 are qualitative or throughput-only for antenna orientation; Momoh 2025 and Lourenco 2025
are simulation-only; Keysight is a vendor tutorial.

### Cited Findings

#### S1. Feng et al. 2021, SMA connector fretting (NEW, read in full)
Citation: C. Feng, X. Lin, J. Hu, B. Shen, Z. Hu, F. Zhu, "Study on the influence of fretting wear on electrical performance of
SMA connector", Microelectronics Reliability 118 (2021) 114047, doi 10.1016/j.microrel.2021.114047 (L/1-s2.0-S0026271421000135-main.pdf).
- Object and method: DC only. "an RTS-8 digital four-probe tester and an RS485 digital voltmeter that had the resolution of 1 μV ... the constant current source provided a size of 100 mA constant current" (§2) — [Feng 2021 §2](https://doi.org/10.1016/j.microrel.2021.114047). No RF, S-parameter or dB measurement anywhere in the paper.
- Test ranges: "a relatively large amplitude (greater than 100 μm) and a relatively small frequency (no more than 30 Hz) were applied in the experiments" (§2); tested 1, 2, 10, 20, 30 Hz at 100, 200, 500, 800 μm (§3.1-3.2, Figs 3-11) — [Feng 2021 §2-3](https://doi.org/10.1016/j.microrel.2021.114047).
- Failure criterion and range: "the fewer cycles required to reach the threshold (5mΩ)" (Abstract); "The maximum value measured by the voltmeter used in the experiment is 20 mV. When the measured voltage continues to exceed the range of the voltmeter for a period, it is regarded as the end of the experiment" (§2); "the resistance increased rapidly until it exceeded the range (200 mΩ)" (§3.2) — [Feng 2021](https://doi.org/10.1016/j.microrel.2021.114047).
- Measured values (30 Hz, 500 μm): "The resistance value between the contacts at the beginning of the experiment was about 2.33 mΩ ... The minimum value was about 1.58 mΩ ... The contact resistance value reached 5 mΩ when the vibration frequency was about 84,000 times. Subsequently, the amplitude of contact resistance changed significantly and rapidly" (§3.1); cycles to 5 mΩ: 41,000 / 91,000 / 504,000 for peak insertion force 3.45 / 2.45 / 1.4 N (§3.2, Fig. 7); 77,100 / 299,400 / 314,500 for stable force 2.50 / 1.66 / 1.54 N (§3.2, Fig. 8) — [Feng 2021 §3](https://doi.org/10.1016/j.microrel.2021.114047).
- Degradation stages: run-in (resistance falls), stable wear (slow rise), then "the resistance greatly increased, and the fluctuations shown in the overall trend were stepped into wider range" (§3.2) — [Feng 2021 §3.2](https://doi.org/10.1016/j.microrel.2021.114047).
- Intermittency is mentioned only as background, not measured: "the relative contact between the contacts caused by fretting Displacement can also cause momentary breaks in electrical contact" (§1) — [Feng 2021 §1](https://doi.org/10.1016/j.microrel.2021.114047).
- Frequency effect, stated two ways: "Lower the frequency enhanced the pin wear" (Abstract; Conclusion: "The lower the frequency, the faster the pin wears") versus "The vibration frequency had little effect" (§3.2 Discussion, on cycles to 5 mΩ) — [Feng 2021](https://doi.org/10.1016/j.microrel.2021.114047).
- Cited papers of interest: [17] Carvou & Ben Jemaa, "Statistical study of voltage fluctuations in power connectors during fretting vibration", IEEE TCAPT 32(2) 2009 (the only cited work on fluctuation statistics) — [Feng 2021 refs](https://doi.org/10.1016/j.microrel.2021.114047).

#### S2. Enquebecq et al. 2015, RF connector fretting: DC resistance, S21 and phase noise (V7_Enquebecq)
Citation: R. Enquebecq, S. Fouvry, E. Rubiola, M. Collet, L. Petit, J. Legrand, L. Boillot (Ecole Centrale de Lyon LTDS,
FEMTO-ST, Radiall), "Effect of Fretting Wear Damage in RF Connectors Subjected to Vibration: DC Contact Resistance and
Phase-noise Response", IEEE Holm Conference on Electrical Contacts, 2015 (page footer "978-1-4673-9341-6/15/$31.00 ©2015 IEEE")
(L/V7_Enquebecq_RF_Connector_Fretting_Vibration.pdf; [FEMTO-ST copy](https://publiweb.femto-st.fr/tntnet/entries/13058/documents/author/data)).
The venue was missing from src_notes_12; it is resolved here.
- Test: "Frequency was set at 100 Hz and the relative displacement of the pin part was controlled using a laser sensor" (§III.A); random excitation "between 1 and 1,600 Hz" for the modal check (§IV.A); S21 by VNA, "Loss at 10 GHz and ECR were measured every 10,000 cycles" (§IV.C) — [Enquebecq 2015](https://publiweb.femto-st.fr/tntnet/entries/13058/documents/author/data).
- Slip threshold: "the D*t transition of the studied connector was about ±35 µm. Above this vibration displacement amplitude, a significant increase in ECR was observed" (§IV.B) — [Enquebecq 2015](https://publiweb.femto-st.fr/tntnet/entries/13058/documents/author/data).
- Measured RF loss (the key number): "whereas at the sliding transition ∆* = ±30 µm the ECR variation ∆R was less than 1.6×10-4 Ω and the ∆S21 loss parameter variation was around 0.15 dB, they rose to respectively 3.4 Ω and 0.37 dB at ∆* = 45 µm" (§IV.C, after 15×10^6 cycles) — [Enquebecq 2015](https://publiweb.femto-st.fr/tntnet/entries/13058/documents/author/data).
- Phase noise: "At the end of the test after 15 million cycles, the white noise due to wear had increased by approximately 40 dB. The amplitude of the fundamental peak (100 Hz) remained constant" (§IV.D); at 50 kHz offset from 10 GHz, phase noise rose from "-1.6×102" to "-1×102 dB" and ECR from "1.10-3 Ω" to "10-2 Ω" after 6×10^5 cycles (§IV.D) — [Enquebecq 2015](https://publiweb.femto-st.fr/tntnet/entries/13058/documents/author/data).
- Periodic signature: "this phase noise discontinuity is observed at the frequency equivalent to the fretting loading frequency. Different fretting frequencies were imposed, from 25 Hz to 150 Hz, and confirmed this" (peaks "at 100 Hz and succesive multiples"); its "intensity ... is proportionnal to the fretting displacement amplitude D*" and is "independent of contact degradation" (§IV.E, §V) — [Enquebecq 2015](https://publiweb.femto-st.fr/tntnet/entries/13058/documents/author/data).
- No open-circuit, dropout or intermittent-break measurement in the paper.

#### S3. Verbeke & Debruyne 2016, UAV multirotor frame vibration (isma2016_0797.pdf; extract W12)
Citation: J. Verbeke, S. Debruyne (KU Leuven), "Vibration analysis of a UAV multirotor frame", Proceedings of ISMA2016 including
USD2016, pp. 2329-2338 (L/isma2016_0797.pdf).
- Platform: "a six armed multirotor (hexacopter) made by Quadframe" (§1) — [Verbeke 2016 §1](L/isma2016_0797.pdf).
- Excitation source: "Both the axial and radial vibrations are determined at different rotational speeds, ranging from 200 to 14500 rpm" (§2.1); "The rotation frequency during this test is 86 Hz, corresponding to 5160 rpm" (Fig. 4, 10" plastic propeller); "the registered radial vibration force amplitude ranges from 0.1 N at 500 rpm to 5.9 N at 4000 rpm (8" plastic propeller). The stated (nearly) quadratic relation ... clearly indicates propeller unbalance" (§2.1); spectra combined "in a bandwidth of 600 Hz" (§2.2) — [Verbeke 2016 §2](L/isma2016_0797.pdf).
- Modal results (the project's 86-672 Hz): Table 1, "Experimentally determined resonance frequencies and damping ratios of complete hexacopter frame": modes 1-7 at 86, 93, 106, 120, 312, 339, 672 Hz, damping 1.58, 1.38, 1.41, 1.22, 0.85, 0.76, 0.72 %; frame "elastically suspended" and hammer-excited, "In a frequency range of 800 Hz, 7 resonance mode shapes can clearly be defined" (§3.2); FE match within 0.05-2.85 %, MAC 0.79-0.95 (Table 2) — [Verbeke 2016 §3-4](L/isma2016_0797.pdf).
- Clamped single arm: "The bending mode occurs at 130 Hz while the second one has a frequency of 984 Hz" (§3.1) — [Verbeke 2016 §3.1](L/isma2016_0797.pdf).
- No in-flight acceleration amplitudes in the text: "Current research efforts focus on accurate real-time in-flight vibration measurements" (§5) — [Verbeke 2016 §5](L/isma2016_0797.pdf).
- Nothing about antennas, connectors or RF.

#### S4. Song, Zeng, Xu, Jin 2020, survey of UAV communication prototypes (2007.00905v1.pdf; extract W14)
Citation: Q. Song, Y. Zeng, J. Xu, S. Jin, "A Survey of Prototype and Experiment for UAV Communications", arXiv:2007.00905v1
(Sci China Inf Sci, for review) — [arXiv](https://arxiv.org/abs/2007.00905).
- COTS platforms (Table 1): DJI Inspire 2 26 m/s, Matrice 200 22.5 m/s (2.4/5.8 GHz); Cumulus One 16.1 m/s; UX11 15 m/s; DATAhawk 27.78 m/s (2.4 GHz, 868 MHz) — [Song 2020 §2.1](https://arxiv.org/abs/2007.00905).
- Table 2 (columns misaligned in the extract): WiFi row 2.4/5 GHz, "LoS link", 29 dBm; LoRa 5-20 dBm; LTE 15-23 dBm; SDR >10 dBm — [Song 2020 §2.2](https://arxiv.org/abs/2007.00905).
- Altitude and interference, cellular context only: "as the UAV altitude increases, the number of detectable base stations at the UAV increases, and the received power ... gets stronger. However, UAV's received SINR degrades, mainly due to the increased interference" (§5.1, on LTE measurements of [19]) — [Song 2020 §5.1](https://arxiv.org/abs/2007.00905).
- Antenna facts quoted from measurements it surveys: "Receivers with four antennas were installed at the bottom of the aircraft in a rectangular pattern ... All antennas were vertically polarized" ([56-58], NASA S-3B campaigns); "A vertically polarized, dual band omni-directional vertical antenna with 3dBi gain" ([42]); [37] "found that the altitude and antenna orientation were critical for coverage" (LoRa) (§3.1, §2.2) — [Song 2020](https://arxiv.org/abs/2007.00905).

#### S5. Keysight application note, IEEE 802.11 PHY operation and measurement ('IEEE 802.11 Physical Layer Operation and Measurement.pdf'; extract W15)
Citation: Keysight Technologies, "IEEE 802.11 Wireless LAN PHY Layer (RF) Operation and Measurement", Application Note 5988-5411EN,
"Published in USA, December 5, 2017", "Formerly known as Application Note 1380-2" (L/IEEE 802.11 Physical Layer Operation and Measurement.pdf). Vendor tutorial.
- Per-antenna RSSI is a standard receiver function: "Diversity reception is used to reduce the effect of nulls on signal levels. A Receive Signal Strength Indication (RSSI) test, made during the short training sequence, determines which path is switched in for a particular burst" (§1.2.2) — [Keysight AN 5988-5411EN §1.2.2](L/IEEE%20802.11%20Physical%20Layer%20Operation%20and%20Measurement.pdf).
- Preamble use: "The preamble is used by the receiver to adapt to the input signal. This may involve frequency and phase error equalizing, as well as time alignment" (§1.3 area, p. 9) — [Keysight AN](L/IEEE%20802.11%20Physical%20Layer%20Operation%20and%20Measurement.pdf).
- Burst lengths: "usually in the range of a few hundred microseconds to one milli-second. The 802.11b CCA ... specifies the longest possible 5.5 Mbps frame--3.65 ms" (p. 9) — [Keysight AN](L/IEEE%20802.11%20Physical%20Layer%20Operation%20and%20Measurement.pdf).
- Antenna-port match: "A port match of 10 dB (VSWR~2:1) is often used ... this can produce signal variations of up to ±1 dB" (§3.3) — [Keysight AN §3.3](L/IEEE%20802.11%20Physical%20Layer%20Operation%20and%20Measurement.pdf).
- Channel agility: "the operating channel frequency has 224 µs to settle within ±60 kHz of its final value" (p. 22) — [Keysight AN](L/IEEE%20802.11%20Physical%20Layer%20Operation%20and%20Measurement.pdf).
- Receiver limits (Tables 6-8): 802.11b sensitivity -76 dBm, FER < 8 % (1024-byte PSDU, 11 Mbps CCK); max input -10 dBm; 802.11b adjacent-channel rejection 35 dB; 802.11a sensitivity -82 dBm at 6 Mbps; CCA detection "< 4 µs for 802.11a and <25 µs ... for 802.11b" (§6.5-6.8) — [Keysight AN §6](L/IEEE%20802.11%20Physical%20Layer%20Operation%20and%20Measurement.pdf).
- PSD: "In Japan, the maximum transmitted power is expressed as 10 mW/MHz" (§3.4.3) — [Keysight AN §3.4.3](L/IEEE%20802.11%20Physical%20Layer%20Operation%20and%20Measurement.pdf).
- The note contains no "ppm" value (searched); its clause numbers refer to "IEEE Std 802.11b/D8.0, Sept 2001" (Appendix E ref. 2) — [Keysight AN App. E](L/IEEE%20802.11%20Physical%20Layer%20Operation%20and%20Measurement.pdf).

#### S6. Lourenco & Grilo 2025, null steering in a UAV swarm (נסרקו - לא בשימוש/05_...; extract S_05)
Citation: M. Lourenco, A. Grilo, "Anti-Jamming based on Null-Steering Antennas and Intelligent UAV Swarm Behavior",
arXiv:2511.18086v1, 22 Nov 2025 — [arXiv](https://arxiv.org/abs/2511.18086).
- Simulation only; the pattern is a script: "The antenna radiation pattern, implemented in a script, adjusts gain according to the null direction, as shown in Fig. 4" (§IV.A). No null depth, no element count, no array geometry in the text — [Lourenco 2025 §IV.A](https://arxiv.org/abs/2511.18086).
- Table I: λ0 0.125 m, bandwidth 20 MHz, UAV Tx 20 dBm, "Jammer interference power 100 dBm" (as printed), noise -100 dBm, Ld0 30 dB at 1 m, n = 2.7, vmax 20 m/s, 4 UAVs — [Lourenco 2025 Table I](https://arxiv.org/abs/2511.18086).
- Results are capacity/fitness ratios ("fitness improvements between +112% and +210,000%") — [Lourenco 2025 §V.A](https://arxiv.org/abs/2511.18086).
- Cites [8] Bhunia, Regis, Sengupta, "Distributed adaptive beam nulling to survive against jamming in 3D UAV mesh networks", Computer Networks 137 (2018) 83-97 — [Lourenco 2025 refs](https://arxiv.org/abs/2511.18086).

#### S7. ITU-R F.1336-5 (01/2019), reference patterns (V7_ITU_R_F1336-5; extracts f1336.txt, f1336raw.txt)
Citation: Recommendation ITU-R F.1336-5, "Reference radiation patterns of omnidirectional, sectoral and other antennas for the
fixed and mobile services for use in sharing studies in the frequency range from 400 MHz to about 70 GHz" — [ITU PDF](https://www.itu.int/dms_pubrec/itu-r/rec/f/R-REC-F.1336-5-201901-I!!PDF-E.pdf).
- Purpose: "The reference radiation patterns should be used in interference assessments, when particular information concerning the real antennas are not available" (Scope); NOTE 1: "It is essential that every effort be made to utilize the actual antenna pattern" — [F.1336-5](https://www.itu.int/dms_pubrec/itu-r/rec/f/R-REC-F.1336-5-201901-I!!PDF-E.pdf).
- Omni (recommends 2.1, eq. 1a-1c): θ3 = 107.6 × 10^(-0.1 G0); "in cases involving typical antennas operating in the 400 MHz to 3 GHz range, the parameter k should be 0.7" (2.3); k = 0 for improved side-lobe antennas (2.4); k = 0.7 represents "side-lobe levels about 13.5 dB below the level of the main lobe" (Annex 1) — [F.1336-5](https://www.itu.int/dms_pubrec/itu-r/rec/f/R-REC-F.1336-5-201901-I!!PDF-E.pdf).
- Validity of the omni pattern (Annex 1 §3): "A reference radiation pattern has been presented for omnidirectional antennas exhibiting a gain between 8 dBi and 13 dBi ... derived on the basis of theoretical considerations of the radiation pattern of a collinear array of dipoles ... Further work is required to determine the range of gain over which the reference radiation pattern is appropriate" — [F.1336-5 Annex 1](https://www.itu.int/dms_pubrec/itu-r/rec/f/R-REC-F.1336-5-201901-I!!PDF-E.pdf).
- Low-gain directional (recommends 4, 1-3 GHz, "main lobe antenna gain less than about 20 dBi"): G = G0 - 12(φ/φ3)^2 for φ < 1.08 φ3; φ3 = sqrt(27 000 × 10^(-0.1 G0)); φ1 = 1.9 φ3; φ2 = φ1 × 10^((G0-6)/32); NOTE 7 "Further study is required to establish the full range of frequencies and gain over which the equations are valid" — [F.1336-5 rec. 4](https://www.itu.int/dms_pubrec/itu-r/rec/f/R-REC-F.1336-5-201901-I!!PDF-E.pdf).
- Sectoral (recommends 3.1, 400 MHz-6 GHz): Ghr(xh) = -12 xh^2 for xh <= 0.5; kh = 0.8 typical; beamwidth-gain relation for sectors < ~120 deg azimuth: θ3 = 31 000 × 10^(-0.1 G0)/φ3 (eq. 3a, "on a provisional basis"); NOTE 2: k values "derived from many measured sectoral antenna patterns in the 700 MHz to around 6 GHz frequency range" — [F.1336-5 rec. 3](https://www.itu.int/dms_pubrec/itu-r/rec/f/R-REC-F.1336-5-201901-I!!PDF-E.pdf).

#### S8. Winters, Salz, Gitlin 1994, antenna diversity capacity (V7_Winters_Salz_Gitlin1994; extract ad.txt)
Citation: J. H. Winters, J. Salz, R. D. Gitlin, "The impact of antenna diversity on the capacity of wireless communication
systems", IEEE Trans. Commun. 42(2/3/4), pp. 1740-1751, 1994 — [readable scan](https://my.ece.utah.edu/~ece6962/project/antenna_diversity.pdf).
- Abstract: "for independent flat-Rayleigh fading wireless systems with N mutually interfering users, we demonstrate that with K+N antennas, N-1 interferers can be nulled out and K+1 path diversity improvement can be achieved by each of the N users" — [Winters 1994](https://my.ece.utah.edu/~ece6962/project/antenna_diversity.pdf).
- §II: "the nulling-out of other users results only in reduced diversity benefits. But even when M=N+1, all users enjoy dual diversity"; zero-forcing result, and "the minimum MSE combiner can achieve even better results than shown above"; interferers in practice "are usually much weaker than the desired signal" — [Winters 1994 §II](https://my.ece.utah.edu/~ece6962/project/antenna_diversity.pdf).
- Independence assumption: elements of C are "independent, zero-mean, complex Gaussian ... provided the antenna elements are sufficiently separated. This separation is typically about half a wavelength at the mobile ... and several wavelengths at the base station" (§II.B) — [Winters 1994 §II.B](https://my.ece.utah.edu/~ece6962/project/antenna_diversity.pdf).
- Experiment (§III): fading simulator (not over the air), "3 users, a 24 channel Rayleigh fading simulator, 8 receive antennas", QPSK, LMS, "fading rate ... up to 81 Hz", 2 kbps, equal-power users, "desired-signal-to-interference-power ratio was -3 dB"; A/D limited to 6 bits, which "did not allow verification of the 6-fold diversity improvement" — [Winters 1994 §III](https://my.ece.utah.edu/~ece6962/project/antenna_diversity.pdf).
- Estimated weights (§IV, IS-54): DMI converges "(less than a 3 dB SNR degradation) to the optimum weights with only 2ML samples"; "with 2 antennas and 1 interferer, DMI can acquire and track both the desired signal and interferer in IS-54, with the performance of optimum combining within 1 dB of the predicted ideal tracking performance"; "For weight acquisition, we will use the known 28 bit synchronization sequence as the reference signal" — [Winters 1994 §IV](https://my.ece.utah.edu/~ece6962/project/antenna_diversity.pdf).

#### S9. Nugroho & Dectaviansyah 2018, measured antenna tracker (V7_Nugroho2018; extract mev.txt)
Citation: G. Nugroho, D. Dectaviansyah, "Design, manufacture and performance analysis of an automatic antenna tracker for an
unmanned aerial vehicle (UAV)", J. Mechatronics, Electrical Power, and Vehicular Technology 9 (2018) 32-40 — [MEV PDF](https://mev.brin.go.id/mev/article/download/404/pdf).
- Hardware: 32-bit controller, GPS, 2 DOF, "360 degrees on azimuth axis (yaw) and 90 degrees on elevation axis (pitch)"; "6 dBi 3 element Yagi"; omni "2.1 dBi"; "915 to 928 MHz"; GPS chipset LEA-6H "has an accuracy of approximately 3 meters"; gear output speeds 39.5 RPM (azimuth) and 30.0 RPM (elevation) (Table 1) — [Nugroho 2018](https://mev.brin.go.id/mev/article/download/404/pdf).
- Measured: "average error of 5.62° on Azimuth axis (Yaw) and 1.51° on elevation axis (Pitch)" with "a Quadcopter-type UAV" (§III.G, Conclusion) — [Nugroho 2018](https://mev.brin.go.id/mev/article/download/404/pdf).
- Failure modes: "uncontrolled movement of the antenna tracker was often occur ... when the system was started up"; "the GPS module had not received the position of at least 6 satellites, so that GPS status on GCS was still not fixed. However after 202.091 seconds the antenna tracker had worked normally" (§III.G) — [Nugroho 2018](https://mev.brin.go.id/mev/article/download/404/pdf).
- RSSI (Fig. 11, qualitative): tracker steady; fixed high-gain antenna "fluctuated significantly"; omni "fluctuated very significant even the lowest signal quality had occurred" — [Nugroho 2018 §III.H](https://mev.brin.go.id/mev/article/download/404/pdf).
- Not stated: test distance, UAV speed, telemetry update rate.

#### S10. Momoh et al. 2025, low-cost GPS antenna tracking (V7_Momoh2025; extract momoh.txt)
Citation: M. O. Momoh, C. C. Ibe, A. Mohammed, G. E. Abbe, K. P. Ter, J. A. Obari, H. I. Bulama, "A Low-cost Antenna Tracking System
Integrated with GPS for UAVs", Computer Engineering and Applications 14(3), Oct 2025 (L/V7_Momoh2025_LowCost_Antenna_Tracking_GPS_UAV.pdf).
- Helix: 2.4 GHz, 8 turns, 208 mm, "Polarization circular" (Table 1); "Simulated radiation patterns ... with a peak gain of 13.2 dBi"; "Simulated axial ratio ... below 1.05dB" (§6.1, MATLAB Antenna Toolbox) — [Momoh 2025 §2, §6.1](L/V7_Momoh2025_LowCost_Antenna_Tracking_GPS_UAV.pdf).
- GPS: PA1616S, "up to 10 location updates a second"; "accuracy of ±2 meters"; "align the antenna to within 0.05 degrees" (§3.1, §6.2; stated under "SIMULATION RESULTS") — [Momoh 2025 §6.2](L/V7_Momoh2025_LowCost_Antenna_Tracking_GPS_UAV.pdf).
- Redundancy: two algorithms, "Signal Strength Gradient Tracking" and "GPS Tracking"; "To improve accuracy and provide redundancy in case of system failure, GPS is integrated" (Abstract, §4) — [Momoh 2025](L/V7_Momoh2025_LowCost_Antenna_Tracking_GPS_UAV.pdf).
- Control: tuned PID settles "in 2.654 seconds" (simulated step response, §6.4) — [Momoh 2025 §6.4](L/V7_Momoh2025_LowCost_Antenna_Tracking_GPS_UAV.pdf).

#### S11. Cheng, Hsiao, Kung, Vlah 2006, 802.11a UAV-to-ground with antenna orientations (V7_Cheng2006; extract cheng.txt)
Citation: C.-M. Cheng, P.-H. Hsiao, H. T. Kung, D. Vlah, "Performance Measurement of 802.11a Wireless Links from UAV to Ground
Nodes with Various Antenna Orientations", Proc. ICCCN 2006 (L/V7_Cheng2006_80211a_UAV_Antenna_Orientations.pdf).
- Setup: 5 GHz ("channel 56 in the 802.11a band", 18 dBm), fixed wing (Senior Telemaster), "approximately at 50-yard altitude and at 40 miles per hour"; 2 dBi dipoles and 7 dBi Netgate omni; distances up to "300 to 350 meters" (§II-III) — [Cheng 2006](L/V7_Cheng2006_80211a_UAV_Antenna_Orientations.pdf).
- Overhead/near-field null (qualitative): "when the distance is small, the vertically oriented dipole antennas on the transmitter and the receiver are more likely to be in each other's null, resulting in worse performance" (§III) — [Cheng 2006 §III](L/V7_Cheng2006_80211a_UAV_Antenna_Orientations.pdf).
- Polarization with bank: the cross-polarized pair "performs quite well, especially at the farthest distance ... it is probably banking at sharp angles ... at this time, the antennas are no longer cross-polarized" (§III) — [Cheng 2006 §III](L/V7_Cheng2006_80211a_UAV_Antenna_Orientations.pdf).
- Numbers are throughput only (Table I: H-H elevated 433 kbps ... V-VN 110 kbps; Table II flyover H 42.1 %, HN 39.6 %, V 15.7 %, Hp 11.1 %); path-loss slope -1.8029 (exponent < 2) — [Cheng 2006](L/V7_Cheng2006_80211a_UAV_Antenna_Orientations.pdf).
- Narrow vertical beams hurt: "most poor performers were VN antennas ... their narrow horizontal beam patterns were largely underneath the UAV" — [Cheng 2006 §V](L/V7_Cheng2006_80211a_UAV_Antenna_Orientations.pdf).

#### S12. Ahmed, Kanhere, Jha 2011, UNSW-CSE-TR-1113 (V7_Ahmed2011; extract unsw.txt)
Citation: N. Ahmed, S. S. Kanhere, S. Jha, "Link Characterization for Aerial Wireless Sensor Networks", Technical Report
UNSW-CSE-TR-1113, Aug 2011 (L/V7_Ahmed2011_UNSW_TR1113_Aerial_WSN_Links.pdf). Technical report (not peer reviewed).
- Not flown: "static plastic poles ... (4.2m is the maximum height used in the experiments) ... does not capture the effect of UAV movements" (§1); TelosB, 2.4 GHz ZigBee channel 26, 0 dBm, noise floor -90 to -93 dBm (§3) — [Ahmed 2011](L/V7_Ahmed2011_UNSW_TR1113_Aerial_WSN_Links.pdf).
- Orientation: "RSSI values vary up to about 10dB for the best and worst antenna orientation for all height variations" (§3.2); receiver re-orientation "increases by about 6dB" (§3.2) — [Ahmed 2011 §3.2](L/V7_Ahmed2011_UNSW_TR1113_Aerial_WSN_Links.pdf).
- Antenna count: "for UAVs that can keep a stable antenna orientation ... a single antenna might suffice, but in general a minimum of two, and probably more, antennas would be required for reliable communication in arbitrary directions" (§4) — [Ahmed 2011 §4](L/V7_Ahmed2011_UNSW_TR1113_Aerial_WSN_Links.pdf).
- Calibration: two of eight nodes differed by "+/- 2dB" in receiver response (§3.1) — [Ahmed 2011 §3.1](L/V7_Ahmed2011_UNSW_TR1113_Aerial_WSN_Links.pdf).

#### S13. Matson et al. 2021, antenna orientation on the air-to-air channel (V7_Matson2021; extract matson.txt)
Citation: N. C. Matson, S. M. Hashir, S. Song, D. Rajan, J. Camp, "Effect of Antenna Orientation on the Air-to-Air Channel in
Arbitrary 3D Space", IEEE SwarmNet 2021 workshop — [SMU PDF](https://s2.smu.edu/~camp/pubs/Matson_SwarmNet2021.pdf).
- Setup: Tx hover at 80 m, Rx at 114 positions, ~20 m radius, 22.5 deg steps, "2.484 GHz", VERT2450 omni "3 dBi", one H and one V antenna per drone (§II) — [Matson 2021](https://s2.smu.edu/~camp/pubs/Matson_SwarmNet2021.pdf).
- Result: VV best near 0 deg elevation; "for the locations where the vertical displacement is high, i.e. elevation angles close to ±90 or the 'poles', the average capacity is much lower"; HH best near the poles (§V.A) — [Matson 2021 §V](https://s2.smu.edu/~camp/pubs/Matson_SwarmNet2021.pdf).
- Selection gain in capacity units: best-pair median "over 16 bits/s/Hz"; fixed pairs "none of which are more than 15"; IQR 2.1 vs 2.8-4.0; best-pair minimum 12.4 bits/s/Hz (§V.B) — [Matson 2021 §V.B](https://s2.smu.edu/~camp/pubs/Matson_SwarmNet2021.pdf).
- No dB-per-angle values in the text; cites the dB-level studies [21] Badi 2019 and [22] Badi 2020 (downloaded, S18-S19).

#### S14. ETSI EN 300 328 V1.7.1 (2006-10) (V7_ETSI_EN300328_v1.7.1; extract en300328.txt)
- 4.3.1.2: "The equivalent isotropic radiated power (e.i.r.p.) shall be equal to or less than -10 dBW (100 mW). This limit shall apply for any combination of power level and intended antenna assembly" — [EN 300 328 V1.7.1](L/V7_ETSI_EN300328_v1.7.1_2006_24GHz_EIRP_limits.pdf).
- 4.3.2.2: "For wide band modulations other then FHSS (e.g. DSSS, OFDM, etc.), the maximum e.i.r.p. spectral density is limited to 10 mW per MHz"; 4.2.2: modulations that are not FHSS "shall be considered equivalent to DSSS" — [EN 300 328 V1.7.1](L/V7_ETSI_EN300328_v1.7.1_2006_24GHz_EIRP_limits.pdf).
- 4.3.5.2: "A medium access protocol shall be implemented by the equipment" — [EN 300 328 V1.7.1](L/V7_ETSI_EN300328_v1.7.1_2006_24GHz_EIRP_limits.pdf).
- Superseded: the current harmonised version is V2.2.2 (2019-07), downloaded (S17).

#### S15. IEEE P802.11b/D3.1 (1999), draft HR/DSSS PHY (V7_IEEE_P80211b_D3.1; extract d31.txt)
URL: [ieee802.org archive](https://www.ieee802.org/11/Documents/DocumentArchives/1999_docs/90845b_p80211b-draft3.1.pdf). Draft: "This is an unapproved IEEE Standards Draft, subject to change".
- 18.4.7.5: "The transmitted center frequency tolerance shall be ±25 ppm maximum." 18.4.7.6: "The PN code chip clock frequency tolerance shall be better than ±25 ppm maximum. It is highly recommended that the chip clock and the transmit frequency be locked (coupled)" — [P802.11b/D3.1](https://www.ieee802.org/11/Documents/DocumentArchives/1999_docs/90845b_p80211b-draft3.1.pdf).
- Table 15: "1000 mW USA FCC 15.247; 100 mW (EIRP) Europe ETS 300-328; 10 mW/MHz Japan" (18.4.7.1); power control for > 100 mW (18.4.7.3) — [P802.11b/D3.1](https://www.ieee802.org/11/Documents/DocumentArchives/1999_docs/90845b_p80211b-draft3.1.pdf).
- Preamble: "The SYNC field shall consist of 128 bits of scrambled '1' bits. This field is provided so the receiver can perform the necessary synchronization operations"; short preamble SYNC 56 bits; "aPreambleLength 144 µs using long preamble, or 72 µs using short preamble" — [P802.11b/D3.1](https://www.ieee802.org/11/Documents/DocumentArchives/1999_docs/90845b_p80211b-draft3.1.pdf).
- Receiver: FER < 8×10^-2 at -76 dBm (18.4.8.1); max input -10 dBm (18.4.8.2); adjacent-channel rejection >= 35 dB (18.4.8.3); EVM limit 0.35; MIB "dot11DiversitySupport", PICS "Receive antenna diversity 18.4.6.7 M" — [P802.11b/D3.1](https://www.ieee802.org/11/Documents/DocumentArchives/1999_docs/90845b_p80211b-draft3.1.pdf).

#### S16. Anritsu 2025, 802.11be TRx evaluation (V7_Anritsu2025; extract anritsu.txt)
Citation: Anritsu, "IEEE 802.11be Compliant TRx Characteristics Evaluation", MT8862A application note, "2025-04 ... No. MT8862A_11be-E-F-2-(1.00)" — [Anritsu PDF](https://dl.cdn-anritsu.com/en-en/test-measurement/files/Application-Notes/Application-Note/mt8862a-11be-ef2100.pdf). Vendor note citing a draft (802.11be D7.0).
- "Tolerance 2.4 GHz band: ±25 ppm; 5/6 GHz band: ±20 ppm" (Transmit center frequency and symbol clock frequency tolerance) — [Anritsu 2025](https://dl.cdn-anritsu.com/en-en/test-measurement/files/Application-Notes/Application-Note/mt8862a-11be-ef2100.pdf).
- Clause number is inconsistent inside the note: the item list gives "36.3.20.4.3 Transmit center frequency and symbol clock frequency tolerance", the figure caption gives "36.3.20.3" — [Anritsu 2025](https://dl.cdn-anritsu.com/en-en/test-measurement/files/Application-Notes/Application-Note/mt8862a-11be-ef2100.pdf).
- EVM table (D7.0): MCS1 QPSK 1/2 -10 dB (31.6 %) — [Anritsu 2025 Table 1](https://dl.cdn-anritsu.com/en-en/test-measurement/files/Application-Notes/Application-Note/mt8862a-11be-ef2100.pdf).

#### S17. Rumpf 2017 lecture slides, antenna figures of merit (V7_Rumpf2017; extract emp.txt)
Citation: R. C. Rumpf, EE-4382/5306 Antenna Engineering, "Topic 2 - Antenna Parameters and Figures of Merit (FOM) Continued", 9/12/2017 — [EMPossible PDF](https://empossible.net/wp-content/uploads/2018/03/Topic-2-Figures-of-Merit-Continued.pdf). Lecture slides (secondary; cites Balanis 4th ed.).
- "The polarization loss factor quantifies the loss caused by the polarization mismatch"; "PLF = |cos ψp|^?" (exponent lost in the text layer; the square is confirmed by Badi 2019, S18: "PLF (dB) = 20 log(cos(δ))") — [Rumpf 2017](https://empossible.net/wp-content/uploads/2018/03/Topic-2-Figures-of-Merit-Continued.pdf).
- Friis with reflection efficiencies (1-|Γ|^2) and PLF (slides 22-23) — [Rumpf 2017](https://empossible.net/wp-content/uploads/2018/03/Topic-2-Figures-of-Merit-Continued.pdf).

#### Additional sources read and downloaded in this review (cited by the assigned ones)
- S18. M. Badi, J. Wensowitch, D. Rajan, J. Camp, "Experimental Evaluation of Antenna Polarization and Elevation Effects on Drone Communications", ACM MSWiM 2019, pp. 211-220 (Matson ref. [21]); saved as L/V7_Badi2019_Antenna_Polarization_Elevation_Drone.pdf — [SMU PDF](https://s2.smu.edu/~camp/pubs/badi_acm_mswim_2019.pdf).
  - 2.5 GHz, air-to-air, Tx hover 80 m, dh = 20 m at 0 deg: VD-VD "increases from around −87 dBm to −67 dBm (20 dB increase) when the receiving drone moves from −56.3◦ to 0◦ ... decreases from -67 dBm to -85 dBm (18 dB decrease) [to +56◦], until it reaches around -91 dBm as it reaches exactly above the transmitting drone (+90◦) ... −90◦ ... -97 dBm"; "movement of the receiving drone at different elevation angles can reduce the signal level by up to 30 dB" (§4.2) — [Badi 2019 §4](https://s2.smu.edu/~camp/pubs/badi_acm_mswim_2019.pdf).
  - At +90 deg a horizontal antenna gets "-85.8 dBm, where VD results in an average RSS of -98 dBm (approx. 12 dB higher RSS at H)"; "PLF (dB) = 20 log(cos(δ))" (§4.2) — [Badi 2019 §4.2](https://s2.smu.edu/~camp/pubs/badi_acm_mswim_2019.pdf).
  - Body effects (anechoic): Table 1 body-induced loss azimuth max 10.96 dB (avg 3.03), elevation max 18.72 dB (avg 4.13); body reduces XPD "by an average of 14.5 dB" (§2) — [Badi 2019 §2](https://s2.smu.edu/~camp/pubs/badi_acm_mswim_2019.pdf).
  - Branch correlation (two receive antennas on one drone): VU-VU 0.61, VU-VD 0.62, orthogonal pairs "around 0.2", only VD-VD above 0.7 (§4.3) — [Badi 2019 §4.3](https://s2.smu.edu/~camp/pubs/badi_acm_mswim_2019.pdf).
- S19. M. Badi et al., "Experimentally Analyzing Diverse Antenna Placements and Orientations for UAV Communications", IEEE Trans. Veh. Technol. 69(12), 2020, pp. 14989-15004 (Matson ref. [22]); author-posted IEEE version, saved as L/V7_Badi2020_Antenna_Placements_Orientations_UAV_TVT.pdf — [SMU PDF](https://s2.smu.edu/~camp/pubs/badi_tvt2020.pdf).
  - Ground-to-drone: "The trans[mitter] is located on the tripod at a height of 1 m above ground ... fixed horizontal distance of dh = 20 m"; elevation pattern model "|GV V | = cos2(θ)"; worked example "10 log(cos(θ)4) ... =10 dB" between 26.5 and 56.3 deg (§III, §V.C) — [Badi 2020](https://s2.smu.edu/~camp/pubs/badi_tvt2020.pdf).
  - Rotation (facing away from the ground Tx): "shadowing can reach up to 9 dB with a standard deviation of up to σs = 6.36 dB"; VV rotational loss "from a range of 1 to 2.5 dB at θ = 3◦ to the range of 5 to 7.5 dB at θ = 55◦"; at θ = 90 deg "no change in average RSS was observed" (§V.D) — [Badi 2020 §V.D](https://s2.smu.edu/~camp/pubs/badi_tvt2020.pdf).
  - "the drone body ... rendering the common assumption of a constant azimuth radiation pattern invalid"; loss "up to 10.25 dB when the same antennas are mounted on a drone"; "ground reflections can cause a degradation in the K-factor by up to 10 dB"; "an antenna spacing of 0.67λ results in a correlation coefficient of less than 0.7 regardless of antenna orientation ... diversity gains in the range of 9.5 to 11.5 dB" (Abstract, §I) — [Badi 2020](https://s2.smu.edu/~camp/pubs/badi_tvt2020.pdf).
- S20. E. Yanmaz, R. Kuschnig, C. Bettstetter, "Achieving Air-Ground Communications in 802.11 Networks with Three-Dimensional Aerial Mobility", IEEE INFOCOM 2013 mini-conference (Matson ref. [16]); saved as L/V7_Yanmaz2013_3D_Aerial_Mobility_80211_Antenna.pdf — [AAU PDF](https://mobile.aau.at/publications/yanmaz-2013-infocom-3Dconnectivity.pdf).
  - 5.24 GHz, quadrotor; "a triangular, horizontal three-antenna configuration ... dipole antennas with 2 dBi gain and 3 dB beamwidth of 360◦ and 75◦ ... Simple selection combining"; "the VV setup suffers as ϕ decreases (i.e., as the UAV ascends on the sphere surface)" while HHH "can sustain a high RSS"; around the AP the HHH RSS averaged -65 dBm "with a standard deviation of 2.5 dB"; path-loss exponents 2.01 / 2.03 (§III-V) — [Yanmaz 2013](https://mobile.aau.at/publications/yanmaz-2013-infocom-3Dconnectivity.pdf).
- S21. ETSI EN 300 328 V2.2.2 (2019-07), current harmonised version; saved as L/V7_ETSI_EN300328_v2.2.2_2019_24GHz_wideband.pdf — [ETSI PDF](https://www.etsi.org/deliver/etsi_en/300300_300399/300328/02.02.02_60/en_300328v020202p.pdf).
  - 4.3.2.2.3: "The RF output power for non-FHSS equipment shall be equal to or less than 20 dBm ... This limit shall apply for any combination of power level and intended antenna assembly"; 4.3.2.3.3: "The maximum Power Spectral Density for non-FHSS equipment is 10 dBm per MHz" — [EN 300 328 V2.2.2](https://www.etsi.org/deliver/etsi_en/300300_300399/300328/02.02.02_60/en_300328v020202p.pdf).
  - Non-adaptive equipment at >= 10 dBm e.i.r.p.: "The Tx-sequence time shall be equal to or less than 10 ms. The minimum Tx-gap time ... with a minimum of 3,5 ms" (4.3.2.4.3); "MU = (Pout / 100 mW) × DC ... The maximum Medium Utilization factor for non-adaptive non-FHSS equipment shall be 10 %" (4.3.2.5) — [EN 300 328 V2.2.2](https://www.etsi.org/deliver/etsi_en/300300_300399/300328/02.02.02_60/en_300328v020202p.pdf).
  - Adaptive (DAA): "The Channel Occupancy Time shall be less than 40 ms. Each such transmission sequence shall be followed by an Idle Period ... of minimum 5 % of the Channel Occupancy Time with a minimum of 100 µs"; threshold "-70 dBm/MHz" for 20 dBm e.i.r.p.; "beamforming gain (Y) shall not be taken into account" (4.3.2.6.2.2); LBT frame-based COT "1 ms to 10 ms", CCA "not less than 18 µs" (4.3.2.6.3.2.2) — [EN 300 328 V2.2.2](https://www.etsi.org/deliver/etsi_en/300300_300399/300328/02.02.02_60/en_300328v020202p.pdf).
- S22. FCC 47 CFR 15.247, read via Cornell LII: "(b)(3) ... 2400-2483.5 MHz ...: 1 Watt"; "(b)(4) The conducted output power limit ... is based on the use of antennas with directional gains that do not exceed 6 dBi"; "(c)(1)(i) ... used exclusively for fixed, point-to-point operations may employ transmitting antennas with directional gain greater than 6 dBi provided the maximum conducted output power ... is reduced by 1 dB for every 3 dB"; "(e) ... shall not be greater than 8 dBm in any 3 kHz band" — [47 CFR 15.247 (LII)](https://www.law.cornell.edu/cfr/text/47/15.247).
- S23. A. E. Ginart et al. (Impact Technologies, NASA Ames), "Sensing and Characterization of EMI During Intermittent Connector Anomalies", IEEE Aerospace Conference 2012 (©2012 IEEE, 978-1-4577-0557-1) — read only, not saved (host not in the allowed list) — [NASA DASHlink PDF](https://c3.ndc.nasa.gov/dashlink/static/media/publication/Ginart_et_al._-_2012_-_Sensing_and_characterization_of_EMI_during_intermittent_connector_anomalies.pdf).
  - "Table 1 - Connector Failure Modes: Open 61 %, Poor contact 23 %, Short 16 %"; "The two main stress factors ... are vibration and differences in thermal expansion" (§2) — [Ginart 2012](https://c3.ndc.nasa.gov/dashlink/static/media/publication/Ginart_et_al._-_2012_-_Sensing_and_characterization_of_EMI_during_intermittent_connector_anomalies.pdf).
  - DC power connector (MIL-DTL-5015) with forced disconnection "at variable speeds of up to 20 Hz"; slow cycle "approximately 125 ms, whereas the disconnection time was 45ms"; one event "lasted about 80 µs" (§3-4) — [Ginart 2012](https://c3.ndc.nasa.gov/dashlink/static/media/publication/Ginart_et_al._-_2012_-_Sensing_and_characterization_of_EMI_during_intermittent_connector_anomalies.pdf).

### Inferences
- The only sources with RF numbers for a vibrating connector (S1 has none, S2 has one) put fretting degradation at fractions of a dB, not tens of dB.
- Verbeke's 86-672 Hz are free-free modal frequencies of one hexacopter frame, not measured operating vibration and not connector rates.
- The dB-level overhead and polarization numbers come from the two downloaded Badi papers, not from the assigned Cheng, Ahmed or Matson papers.

### Gaps
- No assigned or downloaded source measures an intermittent open of an RF connector in dB, its duration, or its rate under vibration.
- No source gives in-flight vibration amplitude at an antenna connector on a UAV, so the Enquebecq slip threshold (+-35 μm at the pin) cannot be tied to flight.
- Fedde (US 4,506,385) and Huawei (US 10,164,700) patents in src_notes_12 were not re-read in this review (UNVERIFIED here).

## Q2. Is the project's current use of each source backed by the text? (30 dB, 86-672 Hz and other numbers)

### Takeaway
The 86-672 Hz range is inside what Verbeke measured, but it is a set of seven frame resonances, not a measured connector-opening rate.
The 30 dB fault depth has no measured backing in any source read. It is a capacitance calculation whose 0.01-0.03 pF input has no
source. The two connector papers measure 0.15-0.37 dB S21 change and mOhm-to-Ohm resistance. ETSI's 20 dBm figure ignores the
10 dBm/MHz PSD limit that binds a 1 Msym/s signal. The F.1336 omni formula applied to a 2.15 dBi antenna lies outside its stated
8-13 dBi validation range. The +-25 ppm and the tracker numbers are backed.

### Cited Findings
- Project use (DECISIONS D72; init_params.m): "Antenna fault as a connector opening at an airframe vibration frequency drawn per flight in 86-672 Hz (motor and frame modes of a multirotor, Verbeke & Debruyne), open for the duty cycle, 30 dB while open (an open contact couples only through its gap capacitance: 0.01-0.03 pF at 2.4 GHz in 50 ohm gives 26-36 dB)"; `fault_duty = 0.3`, decision layer up to 60 % (D71) — [DECISIONS.md D72](C:/Users/Adi%20Suliman/uav-gcs-v6/docs/DECISIONS.md).
- 86-672 Hz versus Verbeke: Table 1 lists exactly seven modes (86, 93, 106, 120, 312, 339, 672 Hz) of the "elastically suspended" frame under hammer excitation; operating excitation was characterized only as force spectra at 200-14500 rpm, combined "in a bandwidth of 600 Hz" — [Verbeke 2016 §2-3](L/isma2016_0797.pdf). The 86 Hz end is also the rotor frequency of one radial-force test ("86 Hz, corresponding to 5160 rpm") — [Verbeke 2016 §2.1](L/isma2016_0797.pdf).
- 30 dB versus the connector papers: S21 change 0.15 dB (+-30 μm) and 0.37 dB (+-45 μm, gross slip, 15×10^6 cycles, 10 GHz); ΔR 3.4 Ω — [Enquebecq 2015 §IV.C](https://publiweb.femto-st.fr/tntnet/entries/13058/documents/author/data). DC resistance 1.58-5 mΩ, test end at > 200 mΩ, no RF measurement — [Feng 2021 §2-3](https://doi.org/10.1016/j.microrel.2021.114047). Momentary breaks are named but not measured — [Feng 2021 §1](https://doi.org/10.1016/j.microrel.2021.114047).
- Open is the commonest connector failure (61 %), in a DC/aircraft-power context without a dB value — [Ginart 2012 Table 1](https://c3.ndc.nasa.gov/dashlink/static/media/publication/Ginart_et_al._-_2012_-_Sensing_and_characterization_of_EMI_during_intermittent_connector_anomalies.pdf).
- Vibration frequencies tested in the connector papers: 1-30 Hz (Feng 2021); 100 Hz wear tests and 25-150 Hz spur tests (Enquebecq 2015) — [Feng 2021](https://doi.org/10.1016/j.microrel.2021.114047); [Enquebecq 2015](https://publiweb.femto-st.fr/tntnet/entries/13058/documents/author/data).
- ETSI "EIRP 20 dBm" (D72 benign interference; v7 cap): the 20 dBm limit holds, but so does "10 dBm per MHz" PSD for every non-FHSS signal — [EN 300 328 V2.2.2 4.3.2.2-4.3.2.3](https://www.etsi.org/deliver/etsi_en/300300_300399/300328/02.02.02_60/en_300328v020202p.pdf); V1.7.1 has the same 100 mW / 10 mW per MHz pair — [EN 300 328 V1.7.1 4.3.1.2, 4.3.2.2](L/V7_ETSI_EN300328_v1.7.1_2006_24GHz_EIRP_limits.pdf).
- FCC 36 dBm (gcs_directional_notes): 1 W conducted with up to 6 dBi; the 1-dB-per-3-dB relief is "exclusively for fixed, point-to-point operations"; PSD 8 dBm per 3 kHz — [47 CFR 15.247](https://www.law.cornell.edu/cfr/text/47/15.247).
- Song et al. 2020 for "interference grows with altitude" (D72 benign WLAN): the text supports it only for LTE base stations seen by a cellular-connected UAV — [Song 2020 §5.1](https://arxiv.org/abs/2007.00905).
- F.1336 omni pattern for the UAV omni overhead null (src_notes_05_06, G0 = 2.15 dBi): F.1336 states the pattern was shown valid for "a gain between 8 dBi and 13 dBi" (collinear arrays) — [F.1336-5 Annex 1 §3](https://www.itu.int/dms_pubrec/itu-r/rec/f/R-REC-F.1336-5-201901-I!!PDF-E.pdf). Measured 2.5 GHz dipole links show 24-30 dB at +-90 deg versus 0 deg (A2A) — [Badi 2019 §4.2](https://s2.smu.edu/~camp/pubs/badi_acm_mswim_2019.pdf).
- +-25 ppm (v7 receiver): backed by the 802.11b draft (18.4.7.5/18.4.7.6) and Anritsu for 802.11be D7.0 — [P802.11b/D3.1](https://www.ieee802.org/11/Documents/DocumentArchives/1999_docs/90845b_p80211b-draft3.1.pdf); [Anritsu 2025](https://dl.cdn-anritsu.com/en-en/test-measurement/files/Application-Notes/Application-Note/mt8862a-11be-ef2100.pdf). The Keysight note in the library has no ppm figure; src_notes_01 cites a different Keysight document (89600B help web page) — [Keysight AN 5988-5411EN](L/IEEE%20802.11%20Physical%20Layer%20Operation%20and%20Measurement.pdf).
- Tracker: 5.62/1.51 deg measured on a quadcopter at 915 MHz — [Nugroho 2018](https://mev.brin.go.id/mev/article/download/404/pdf); 0.05 deg and 13.2 dBi are simulation outputs — [Momoh 2025 §6](L/V7_Momoh2025_LowCost_Antenna_Tracking_GPS_UAV.pdf).
- MRC/MMSE with 2-3 antennas losing diversity when nulling (D41) agrees with "the average probability of error with optimum combining, M antennas, and N interferers is the same as maximal ratio combining with M-N+1 antennas" — [Winters 1994 §II](https://my.ece.utah.edu/~ece6962/project/antenna_diversity.pdf); the result assumes independent flat Rayleigh fading — [Winters 1994 §II.B](https://my.ece.utah.edu/~ece6962/project/antenna_diversity.pdf).
- Lourenco 2025 is listed as "screened ... but not used" in LITERATURE.md; no number from it is used — [LITERATURE.md](C:/Users/Adi%20Suliman/uav-gcs-v6/docs/LITERATURE.md).

### Inferences
- Capacitive-gap arithmetic checks (series C between two 50 Ω ports, |S21| = 2Z0/|2Z0 + 1/(jωC)|): 0.01 pF gives 36.4 dB and 0.03 pF gives 26.9 dB at 2.4 GHz; 30 dB needs about 0.021 pF. The calculation is sound; its capacitance range is UNVERIFIED, since no read source gives the gap capacitance of an open SMA contact.
- A series resistance R in a 50 Ω line costs 20 log10(1 + R/100) dB: 0.2 Ω gives 0.017 dB, 3.4 Ω gives 0.29 dB (consistent with Enquebecq's measured 0.37 dB), and 30 dB needs about 3.1 kΩ. Fretting-level resistance cannot produce 30 dB. Only a true open (kΩ or capacitive) can, and no read source measures how often or for how long that happens under vibration.
- The sources therefore support two different fault signatures. (a) Wear: slow, sub-dB attenuation, rising phase noise, and a phase spur at the vibration frequency and its harmonics. (b) Momentary opens: named in Feng 2021 and counted as the dominant failure mode in Ginart 2012, with depth, duty and rate unmeasured. Fedde's patent (per src_notes_12, not re-read) describes a third kind: a temperature-driven open that persists for a flight segment.
- "Drawn per flight in 86-672 Hz" is within the measured range in the sense of the user's rule. Physically, a frame with 0.72-1.58 % damping (Q = 1/(2ζ) of about 32-69, half-power bandwidth of about 2.7 Hz at 86 Hz and 9.7 Hz at 672 Hz) responds strongly only near its seven modes. Frequencies between modes (for example 130-300 Hz or 340-670 Hz) are not measured modes. The 672 Hz mode lies above the 600 Hz excitation band that Verbeke used. Rotor 1P excitation spans 3.3-242 Hz (200-14 500 rpm). Verbeke is a hexacopter; it says nothing about fixed-wing airframes in profile 1's 29-161 km/h envelope.
- ETSI PSD arithmetic: a 1 Msym/s RRC-0.25 signal occupies about 1.25 MHz, so 10 dBm/MHz caps it at roughly 10-11 dBm e.i.r.p., not 20 dBm. The 20 dBm figure is reachable only by signals of about 10 MHz or wider, such as the 20 MHz WLAN in D72, for which 20 dBm is consistent. FCC's 8 dBm/3 kHz allows about 34 dBm over 1.25 MHz, so the FCC cap stays at 30 dBm conducted / 36 dBm e.i.r.p.
- Under V2.2.2, a non-adaptive uplink above 10 dBm e.i.r.p. must keep MU <= 10 % (for example 20 dBm at <= 10 % duty) and Tx-sequences <= 10 ms. An adaptive (DAA) one needs idle periods of at least 100 µs. The project's 32-symbol quiet slot is 32 µs (5.8 %), so it meets the 5 % share but not the 100 µs minimum. This matters only if the uplink is meant to be ETSI-conformant.
- Pointing loss with F.1336 rec. 4: 5.62 deg error costs 0.06 dB at 6 dBi (φ3 = 82 deg), 0.29 dB at 13.2 dBi (36 deg) and 0.35 dB at 14 dBi (33 deg). rec. 4 degenerates below G0 = 6 dBi (φ2 < φ1), so 6 dBi is its effective lower edge. A 5-6 dBi sector belongs to rec. 3, the sectoral pattern.
- Overhead null: for a 2.15 dBi omni at 90 deg, F.1336 (k = 0.7) gives -10.8 dB relative to the peak. Badi 2019 measured about -24 dB (+90 deg) and -30 dB (-90 deg) relative to 0 deg at 2.5 GHz. Of that, about 3.5 dB is extra distance (30 m vs 20 m, assuming the +-90 deg points sit 30 m above or below), leaving about 20-27 dB of pattern, polarization and body effect. The F.1336 envelope is an upper bound for sharing studies. As a link-loss model it is optimistic and outside its gain range.
- Frequency offset: +-25 ppm at each end gives up to 50 ppm, about 120-124 kHz at 2.4-2.4835 GHz, or about 0.12 cycle (about 45 deg) per symbol at 1 Msym/s. That is roughly 340 times the 358 Hz maximum Doppler of the envelope, so v7 synchronization is dominated by oscillator offset, not Doppler.

### Gaps
- No source for the 0.01-0.03 pF gap capacitance, the open duty (0.08-0.6) or one open per vibration cycle.
- No source for in-flight vibration at the antenna mounting points of a fixed-wing UAV.
- The approved IEEE 802.11b-1999 / 802.11-2020 text was not read; the +-25 ppm rests on a draft and a vendor note.

## Q3. Unused content that could raise antenna_fault detection (F1 0.82) or support v7 items

### Takeaway
Two kinds of unused content are physically sound. For the fault: per-branch observables measured during known symbols
(Keysight, 802.11b), periodicity at a narrow set of frame modes (Verbeke damping), long-interval per-branch decode statistics
(Fedde, per src_notes_12), and the fact that body and polarization losses are slow and attitude-locked while vibration toggles are
fast (Badi). For v7: measured overhead-null and polarization numbers (Badi 2019/2020, Yanmaz 2013), tracker slew and start-up
behaviour (Nugroho), preamble-based weight estimation and its sample cost (Winters), and the ETSI PSD/adaptivity rules.

### Cited Findings
- Per-branch RSSI on the preamble is standard WLAN practice: "A Receive Signal Strength Indication (RSSI) test, made during the short training sequence, determines which path is switched in for a particular burst" — [Keysight AN §1.2.2](L/IEEE%20802.11%20Physical%20Layer%20Operation%20and%20Measurement.pdf); the 802.11b PICS lists "Receive antenna diversity" as mandatory and reports "the antenna used for receive (RX_ANTENNA), RSSI, and SQ" — [P802.11b/D3.1](https://www.ieee802.org/11/Documents/DocumentArchives/1999_docs/90845b_p80211b-draft3.1.pdf).
- A narrowband periodic driver: modes with "Damping ratio (%) 1.58 ... 0.72" — [Verbeke 2016 Table 1](L/isma2016_0797.pdf); connector disturbance appears "at the frequency equivalent to the fretting loading frequency" and "successive multiples" — [Enquebecq 2015 §IV.E](https://publiweb.femto-st.fr/tntnet/entries/13058/documents/author/data).
- Progressive severity: resistance fluctuation range "stepped into wider range" in the last wear stage — [Feng 2021 §3.2](https://doi.org/10.1016/j.microrel.2021.114047); white phase noise "+40 dB" after 15×10^6 cycles — [Enquebecq 2015 §IV.D](https://publiweb.femto-st.fr/tntnet/entries/13058/documents/author/data).
- Static per-branch offsets that are not faults: VSWR 2:1 gives "signal variations of up to ±1 dB" — [Keysight AN §3.3](L/IEEE%20802.11%20Physical%20Layer%20Operation%20and%20Measurement.pdf); node-to-node receiver spread "+/- 2dB" — [Ahmed 2011 §3.1](L/V7_Ahmed2011_UNSW_TR1113_Aerial_WSN_Links.pdf).
- Benign confounders that look like a weak branch: drone body loss up to 10.96 dB (azimuth) and 18.72 dB (elevation) — [Badi 2019 Table 1](https://s2.smu.edu/~camp/pubs/badi_acm_mswim_2019.pdf); facing-away shadowing up to 9 dB, rotational loss 5-7.5 dB at 55 deg — [Badi 2020 §V.D](https://s2.smu.edu/~camp/pubs/badi_tvt2020.pdf); orientation alone up to ~10 dB — [Ahmed 2011 §3.2](L/V7_Ahmed2011_UNSW_TR1113_Aerial_WSN_Links.pdf).
- v7 overhead pass and polarization tilt: VV loss model cos^2 per antenna (10 dB from 26.5 to 56.3 deg) — [Badi 2020 §III](https://s2.smu.edu/~camp/pubs/badi_tvt2020.pdf); +-90 deg A2A -24/-30 dB, H beats V by 12 dB overhead, PLF(dB) = 20 log cos δ — [Badi 2019 §4.2](https://s2.smu.edu/~camp/pubs/badi_acm_mswim_2019.pdf); banking can undo cross-polarization — [Cheng 2006 §III](L/V7_Cheng2006_80211a_UAV_Antenna_Orientations.pdf); horizontal triangular three-antenna array keeps RSS steady over elevation 10-85 deg (std 2.5 dB) — [Yanmaz 2013 §IV](https://mobile.aau.at/publications/yanmaz-2013-infocom-3Dconnectivity.pdf); none of four fixed H/V pairs is best over all 3D space — [Matson 2021 §VI](https://s2.smu.edu/~camp/pubs/Matson_SwarmNet2021.pdf).
- v7 directional GCS: circular-polarized helix 13.2 dBi (simulated) — [Momoh 2025 §6.1](L/V7_Momoh2025_LowCost_Antenna_Tracking_GPS_UAV.pdf); tracker slew 39.5 / 30 RPM, GNSS 3 m, 202 s start-up error — [Nugroho 2018](https://mev.brin.go.id/mev/article/download/404/pdf); RSS-gradient plus GPS as redundant pointing — [Momoh 2025 §4](L/V7_Momoh2025_LowCost_Antenna_Tracking_GPS_UAV.pdf).
- v7 receiver: DMI weights within 3 dB of optimum "with only 2ML samples", sync sequence as reference — [Winters 1994 §IV](https://my.ece.utah.edu/~ece6962/project/antenna_diversity.pdf); 128/56-bit SYNC, 144/72 µs preamble — [P802.11b/D3.1](https://www.ieee802.org/11/Documents/DocumentArchives/1999_docs/90845b_p80211b-draft3.1.pdf).

### Inferences
- Time scales for antenna_fault: frames are about 0.55 ms long and 20 ms apart, while the vibration period is 1.49-11.6 ms. One frame therefore sees at most one transition. Consecutive frames sample the vibration phase at random (frames are spaced well beyond a vibration period), so periodicity at 86-672 Hz cannot be recovered from one frame per cycle. The chance that a frame sees any open is roughly duty + frame/period: about 0.35 at 86 Hz and about 0.67 at 672 Hz for duty 0.3. At low vibration frequencies most frames look clean, which is consistent with the detector's weakness. Seeing the periodicity directly would need several milliseconds of contiguous per-branch gain (three periods at 86 Hz is about 35 ms), sampled per 32-symbol block. Whether the real uplink is contiguous between decision frames decides whether that is available.
- The discriminator the sources support is time-scale and spatial-structure based, not depth based. Body shadowing, rotation and polarization losses change with attitude and elevation over seconds (Badi). A vibration-driven open toggles at 86-672 Hz and is confined to one branch. A per-branch step of 20-30 dB inside a frame, with no matching change on the other branches, is the fault signature.
- The Enquebecq phase spur is real but tiny at 2.4 GHz: +-45 μm of path is about 0.13 deg in air, or about 0.19 deg in PTFE coax. It is not a usable feature against channel phase noise.
- Per-branch CRC or decode statistics over long windows (Fedde, as summarized in src_notes_12) target the slowly worsening wear stage (Feng, Enquebecq), which a 20 ms detector does not see.
- Polarization: a linear UAV dipole against a circular GCS helix loses a fixed 3 dB (PLF 0.5) at any roll angle. This is the textbook linear-to-circular result, not stated in Rumpf or Momoh (UNVERIFIED in the read texts). It trades the cos^2 roll dependence for a constant loss, and the helix gain is simulated only.
- Tracker kinematics: a UAV at 161 km/h (44.7 m/s) crossing at 100 m demands about 25.6 deg/s. Nugroho's 39.5 RPM azimuth output (about 237 deg/s) covers that, except near zenith, where the azimuth rate is unbounded (the keyhole problem). Start-up without a GNSS fix (202 s) and uncontrolled motion are the two measured failure modes; omni fallback is supported only by the Boeing patent in src_notes_05_06.

### Gaps
- No measured per-branch RF signature of an intermittent connector open: no dB depth, no duration distribution, no relation to vibration level.
- No source gives the UAV antenna's measured elevation pattern at 2.4 GHz on a fixed-wing airframe. Badi is a 2.5 GHz quadcopter, Cheng a 5 GHz fixed wing.
- No source measures tracker error versus UAV speed or range (Nugroho gives neither); the JTSiskom 49 deg at 49 km/h remains UNVERIFIED (src_notes_02).

## Q4. Important cited papers: downloaded, and those that could not be downloaded

### Takeaway
Four freely available, directly useful documents were added to the library. Six others are paywalled or on hosts outside the
allowed list.

### Cited Findings
- Downloaded into L/ (new names checked first; nothing overwritten):
  - V7_Badi2019_Antenna_Polarization_Elevation_Drone.pdf (cited by Matson 2021 [21]) — [SMU](https://s2.smu.edu/~camp/pubs/badi_acm_mswim_2019.pdf)
  - V7_Badi2020_Antenna_Placements_Orientations_UAV_TVT.pdf (Matson 2021 [22]; author-posted IEEE version) — [SMU](https://s2.smu.edu/~camp/pubs/badi_tvt2020.pdf)
  - V7_Yanmaz2013_3D_Aerial_Mobility_80211_Antenna.pdf (Matson 2021 [16]) — [AAU](https://mobile.aau.at/publications/yanmaz-2013-infocom-3Dconnectivity.pdf)
  - V7_ETSI_EN300328_v2.2.2_2019_24GHz_wideband.pdf (current version of the assigned V1.7.1) — [ETSI](https://www.etsi.org/deliver/etsi_en/300300_300399/300328/02.02.02_60/en_300328v020202p.pdf)
- COULD NOT DOWNLOAD:
  - Bhunia, Regis, Sengupta, "Distributed adaptive beam nulling to survive against jamming in 3D UAV mesh networks", Computer Networks 137 (2018) 83-97, doi 10.1016/j.comnet.2018.03.011 (Lourenco [8]); the only free copy is on an author's Cloudinary page, which is not an allowed host: https://res.cloudinary.com/regisin/image/upload/v1618536153/comnet_18_e09630fddb.pdf — [search result](https://archive.cps-vo.org/node/54535)
  - Yanmaz, Kuschnig, Bettstetter, "Channel measurements over 802.11a-based UAV-to-ground links", IEEE GLOBECOM Workshops 2011, pp. 1280-1284 (Matson [15]; the two-antenna precursor); AAU URL returned 404: https://www.itec.aau.at/bib/files/WIUAV2011_Yanmaz.pdf
  - J. H. Winters, "Optimum combining in digital mobile radio with cochannel interference", IEEE JSAC 2(4) 528-539, 1984, doi 10.1109/JSAC.1984.1146095 (Winters 1994 [3]); paywalled.
  - E. Carvou, N. Ben Jemaa, "Statistical study of voltage fluctuations in power connectors during fretting vibration", IEEE TCAPT 32(2) 268-272, 2009, doi 10.1109/TCAPT.2009.2019633 (Feng 2021 [17]); paywalled.
  - S. Fouvry, P. Jedrzejczyk, P. Chalandon, O. Alquier, "From fretting to connector vibration tests: a 'transfer function' approach", ICEC 2014, VDE (Enquebecq [14]); paywalled: https://www.vde-verlag.de/proceedings-en/453624043.html
  - Auburn ETD "High Frequency Behavior of Electrical Contact Subjected to Vibration Induced Fretting Corrosion" (university repository; server refused connection): https://etd.auburn.edu/handle/10415/6426
  - Ginart et al. 2012 (S23): read, not saved; NASA DASHlink host is outside the allowed list; IEEE Aerospace Conference 2012.
- Not needed: ITU-R F.699 and F.1245 (cited by F.1336 for > 20 dBi and for average patterns) — [F.1336-5 noting](https://www.itu.int/dms_pubrec/itu-r/rec/f/R-REC-F.1336-5-201901-I!!PDF-E.pdf).

### Inferences
- Of the downloads, Badi 2019/2020 are the most valuable for v7: measured dB values for the overhead null, polarization, body loss and branch correlation at 2.5 GHz on small drones. Yanmaz 2013 is the only measured three-antenna UAV array in the set, though at 5.24 GHz with selection combining.

### Gaps
- EIA-364-46 (microsecond discontinuity test; definition "10 ohms or greater lasting for one microsecond or longer" from a search snippet only) is a paywalled standard; UNVERIFIED.

## Q5. Relevance verdicts, quality flags and summary

### Takeaway
CORE: Verbeke 2016, Enquebecq 2015, Winters 1994, ITU-R F.1336-5, Nugroho 2018, ETSI EN 300 328, P802.11b/D3.1, plus the downloaded
Badi 2019/2020. SUPPORTING: Feng 2021, Anritsu, Keysight, Cheng, Matson, Yanmaz 2013, Ahmed, FCC. MARGINAL: Song 2020, Momoh, Rumpf,
Ginart. NOT RELEVANT as a numeric source: Lourenco 2025.

### Cited Findings
- Simulation-only flags: Lourenco "implemented in a script" — [Lourenco 2025](https://arxiv.org/abs/2511.18086); Momoh "Simulated radiation patterns", 0.05 deg under "SIMULATION RESULTS" — [Momoh 2025](L/V7_Momoh2025_LowCost_Antenna_Tracking_GPS_UAV.pdf).
- Draft and vendor flags: P802.11b/D3.1 "unapproved IEEE Standards Draft" — [D3.1](https://www.ieee802.org/11/Documents/DocumentArchives/1999_docs/90845b_p80211b-draft3.1.pdf); Anritsu cites 802.11be "draft 7.0" — [Anritsu 2025](https://dl.cdn-anritsu.com/en-en/test-measurement/files/Application-Notes/Application-Note/mt8862a-11be-ef2100.pdf); Keysight application note — [Keysight AN](L/IEEE%20802.11%20Physical%20Layer%20Operation%20and%20Measurement.pdf).
- Superseded flag: EN 300 328 V1.7.1 (2006) under the R&TTE Directive; current V2.2.2 (2019) under Directive 2014/53/EU — [V2.2.2 §1](https://www.etsi.org/deliver/etsi_en/300300_300399/300328/02.02.02_60/en_300328v020202p.pdf).

### Inferences
- Lourenco is still useful as a pointer to Bhunia 2018. Song 2020's altitude-interference statement should be cited only for cellular links.

### Gaps
- None beyond those listed in Q1-Q4.

### Summary table

| Source | Verdict | What it backs | Issues found |
|---|---|---|---|
| Feng 2021 MR 118:114047 (SMA fretting, NEW) | SUPPORTING | Fretting raises SMA contact resistance from about 2 mΩ to 5 mΩ and beyond 200 mΩ; wear stages; "momentary breaks" exist (named only) | DC only, no dB; 1-30 Hz at 100-800 μm, far from UAV frame modes; does NOT support 30 dB (a 200 mΩ series R gives about 0.02 dB); abstract and discussion disagree on the frequency effect |
| Enquebecq 2015 IEEE Holm (RF connector fretting) | CORE (fault physics) | Measured S21 change 0.15 dB (+-30 μm) and 0.37 dB (+-45 μm) at 10 GHz; ΔR 3.4 Ω; phase spur at the vibration frequency and harmonics (25-150 Hz); white phase noise +40 dB | Wear, not opens; 10 GHz; 100 Hz only; contradicts 30 dB as a fretting value; the venue was missing in src_notes_12 |
| Verbeke 2016 ISMA (hexacopter frame) | CORE (for the 86-672 Hz bound) | Seven frame modes 86-672 Hz, damping 0.72-1.58 %; rotor 200-14 500 rpm; 86 Hz = 5160 rpm test | Modal (free-free, hammer), not operating vibration nor connector rate; continuous draw covers unmeasured gaps between modes; 672 Hz above the 600 Hz excitation band; multirotor only |
| Song 2020 arXiv 2007.00905 (prototype survey) | MARGINAL | COTS speeds 15-27.8 m/s; WiFi 29 dBm; altitude-interference effect for LTE | "Interference grows with altitude" is cellular-only, extrapolated to WLAN in D72 |
| Keysight AN 5988-5411EN (802.11 PHY) | SUPPORTING (vendor) | Per-antenna RSSI on preamble; preamble for frequency/phase/timing; burst lengths; VSWR +-1 dB; receiver test limits | No ppm value (src_notes_01 cites a different Keysight document); clause numbers per 802.11b D8.0 |
| Lourenco 2025 arXiv 2511.18086 (null steering, swarm) | NOT RELEVANT (numeric) | Pointer to Bhunia 2018 | Simulation; no null depth or array data; "Jammer interference power 100 dBm" as printed |
| ITU-R F.1336-5 (2019) | CORE (pattern envelopes) | Directional low-gain pattern and 12(e/φ3)^2 pointing loss; sector pattern; omni k = 0.7 | Envelopes for sharing studies; omni pattern validated for 8-13 dBi only (2.15 dBi overhead-null use is out of range); rec. 4 ill-defined below 6 dBi |
| Winters, Salz, Gitlin 1994 | CORE | M antennas null M-1 interferers, leaving M-N+1 diversity; MMSE better than ZF; DMI needs about 2ML samples within 3 dB | Independent flat Rayleigh with equal-power users; the experiment used a fading simulator; project uses Rician with ρ = 0.3 |
| Nugroho 2018 JMEV (tracker, measured) | CORE (tracker) | Error 5.62/1.51 deg; 202 s GNSS-unfixed fault; start-up uncontrolled motion; slew 39.5/30 RPM; GNSS 3 m | 915 MHz, 6 dBi Yagi, quadcopter; distance, speed and update rate not given |
| Momoh 2025 CEA 14(3) (tracker, helix) | MARGINAL | Helix 13.2 dBi (sim.), circular polarization; RSS-gradient + GPS redundancy | Simulation-only; 0.05 deg is a simulation claim |
| Cheng 2006 ICCCN (802.11a UAV orientations) | SUPPORTING (qualitative) | Vertical dipoles in each other's null at short range (overhead); banking undoes cross-polarization; narrow vertical beams fail | 5 GHz; throughput only, no dB per angle |
| Ahmed 2011 UNSW TR-1113 | SUPPORTING (weak) | Orientation changes RSSI by up to about 10 dB; at least two antennas recommended | Static poles at 4.2 m or lower, TelosB PCB antenna; technical report |
| Matson 2021 SwarmNet (A2A orientation) | SUPPORTING | Low VV capacity near +-90 deg; H/V selection steadies capacity | Air-to-air, 20 m; capacity units only; dB values are in Badi 2019/2020 |
| Enquebecq / Feng together vs 30 dB | — | — | 30 dB rests on an unsourced 0.01-0.03 pF gap; no read source measures open depth, duty or rate |
| ETSI EN 300 328 V1.7.1 (2006) | CORE (regulatory), superseded | 100 mW e.i.r.p. and 10 mW/MHz e.i.r.p. density | Superseded by V2.2.2; the PSD limit caps a 1.25 MHz signal near 10-11 dBm, not 20 dBm |
| ETSI EN 300 328 V2.2.2 (2019) [downloaded] | CORE (regulatory) | 20 dBm e.i.r.p., 10 dBm/MHz; MU <= 10 % or DAA/LBT for > 10 dBm; COT < 40 ms, idle >= 100 µs | Continuous uplink at > 10 dBm needs adaptivity or a duty limit; the 32 µs quiet slot is below the 100 µs DAA idle minimum |
| FCC 47 CFR 15.247 (LII) | SUPPORTING | 1 W conducted, 6 dBi, giving 36 dBm e.i.r.p.; PtP relief only for fixed links; 8 dBm/3 kHz | Verified via Cornell LII (eCFR blocked) |
| IEEE P802.11b/D3.1 (1999) | CORE (frequency tolerance) | +-25 ppm carrier and chip clock; SYNC 128/56 bits; -76 dBm sensitivity; ACR 35 dB | Unapproved draft (approved text not read) |
| Anritsu 2025 (802.11be) | SUPPORTING (vendor) | +-25 ppm at 2.4 GHz, +-20 ppm at 5/6 GHz | Cites draft D7.0; clause number inconsistent (36.3.20.3 vs 36.3.20.4.3) |
| Rumpf 2017 slides | MARGINAL | PLF definition; Friis with PLF | Lecture slides; exponent lost in text (square confirmed by Badi 2019) |
| Badi 2019 MSWiM [downloaded] | CORE (v7 overhead null, polarization) | +-90 deg: -24/-30 dB versus 0 deg at 2.5 GHz; H beats V by 12 dB overhead; PLF 20 log cos δ; body loss up to 18.7 dB; branch correlation 0.2-0.62 | Air-to-air quadcopter; distance also changes with angle |
| Badi 2020 IEEE TVT [downloaded] | CORE (v7 ground-to-UAV) | cos^2 elevation model per antenna; ground-to-drone rotational loss 1-7.5 dB; facing-away shadowing up to 9 dB; K reduced by 10 dB near ground; 0.67λ spacing ρ < 0.7 | Author-posted IEEE copy; 2.5 GHz; 20 m range |
| Yanmaz 2013 INFOCOM [downloaded] | SUPPORTING | Horizontal triangular three-antenna array steadies RSS over elevation (std 2.5 dB); VV degrades as the UAV climbs; α of about 2.0 | 5.24 GHz; selection combining |
| Ginart 2012 IEEE Aerospace [read only] | MARGINAL | Open = 61 % of connector failures; vibration and thermal expansion are the main stresses | DC power connectors, forced disconnection; not saved (host) |
