# Channel and propagation sources: re-review for v6/v7 (what each proves, how the project uses it)

Research notes only. These notes make no design decisions. Written 2026-10-01.

Reading basis: every assigned source was read from its own text: a fresh `pdftotext -layout` of the library PDF, or the existing extract, plus the figure images embedded in Sun Part IV.

Text extracts made for this review are in `.../סקירת המקורות ופערי גרסה 7/_extracts_channel/`:
- sun2017_partIV.txt, lee1985.txt, dualband.txt (the Sun dissertation; byte-identical to src/W13_Sun_dissertation.txt)
- alouini.txt, p838.txt, w07.txt
- lyu2024.txt, k25_2025.txt (Aoki), banagar2020.txt, saboor2025.txt
- img/ holds the figures extracted from Sun Part IV (Figs. 8, 11, 12, 14, 16 were read from these images)

Other notes:
- W08_Khawaja2019 and 1801.01656v1.pdf are byte-identical (checked with cmp). Both are the arXiv v1 preprint.
- "Dual-Band Non-Stationary Channel Modeling..." is the Sun 2015 dissertation.
- `src/Sun_dissertation.pdf` (5.6 kB) is not a PDF. It is a saved Cloudflare "Just a moment..." HTML page. The real dissertation is the 15 MB library PDF.
- Anything not read in a source's own text is marked UNVERIFIED. Arithmetic I did myself is labelled "derived".

---

## Q1. Per source: citation, what was measured, the numbers that matter (with quotes and locations)

### Takeaway
Two sources carry the airframe-shadowing numbers: the Sun dissertation and Sun–Matolak–Rayess Part IV. Both use one medium-sized aircraft (NASA S-3B) at 968 MHz and 5.06 GHz, flying at 60-120 m/s.
- The "40 dB" is a peak instantaneous loss that includes fading.
- The sustained (median) loss per event is 10.8 dB at L-band and 15.5 dB at C-band.
- The loss grows with roll angle (Table II), events last 25-35 s on average, and the shadowed branch becomes near-Rayleigh (K drops from about 15 dB to as low as -16 dB).

Lee 1985 proves the 20-40 wavelength, N ≥ 36 local-mean rule, but only for Rayleigh fading and spatial sampling.

The new open sources measured near 2.4 GHz give small-UAV K-factors in these ranges:
- Rodríguez-Piñeiro (RP), Aoki 2025 and Saboor 2025: roughly 0-16 dB.
- Lyu's wideband first-tap values: 16-28 dB.

### Cited Findings

#### S1. Sun, Matolak, Rayess, "Air-Ground Channel Characterization for Unmanned Aircraft Systems—Part IV: Airframe Shadowing", IEEE TVT 66(9):7643-7652, Sept 2017, doi 10.1109/TVT.2017.2677884 (library file: Air-Ground_Channel_..._Part_IV_Airframe_Shadowing.pdf, read in full)

**Platform and method**
- A NASA S-3B Viking (medium-sized aircraft) with four bottom-mounted blade monopoles. "Four receiver antennas (two for each band) are mounted on the bottom of NASA's S-3B Viking airplane on the corners of a rectangle" (Sec. II).
- Antenna spacing: "The distance between L-band Rx1 and C-band Rx1 is 1.33 m, and the distance between L-band Rx1 and C-band Rx2 is 1.24 m" (Sec. II).
- The ground-site (GS) transmitters are sectored, not tracked. "sectored antennas, elevated 20 m above ground level. Antenna gains are approximately 5.1 dB in L-band and 6.1 dB in C-band. The elevation/azimuth beamwidth is 60°/120° for L-band and 35°/180° for C-band" (Sec. II).
- Sounder: dual-band DS-SS at 968 MHz and 5.06 GHz, 5 MHz and 50 MHz bandwidth, 10 W, "approximately 3000 PDPs per second" (Sec. II). — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884)

**Data set and geometry**
- "In total, data from 209 shadowing events was collected. These events occurred at link ranges between 14.4 and 27.8 km, and elevation angles between 1.4 and 2.9 degrees. The aircraft roll angle was up to 58.3°" (Sec. II).
- "All the events were inside the main beams of the GS antennas" (Sec. II).
- 209 counts receiver-events: Sec. IV says "data on 58 airframe shadowing events was collected ... 98 L-band and 111 C-band shadowing events". — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884)

**Speed and scope**
- "Flight velocity (ranging 70 to 120 m/s) was kept low to ensure an adequate PDP sampling rate".
- "our results, while taken with a specific medium-sized aircraft, should be applicable to aircraft similar in size" (Sec. II). — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884)

**Event criteria (Sec. III)**
- "1) roll angle larger than 5 degrees ... 2) the difference between heading and azimuth angles is larger than 30 degrees ... and 3) the measured path loss is at least 5 dB larger than the log-distance path loss".
- The dissertation (footnote 10) calls these thresholds "engineering judgements". — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884); [Sun 2015](https://scholarcommons.sc.edu/etd/3655)

**Example event (Palmdale FT5, Table I)**
- Roll angle "between 10.4° to 24.9°".
- "The C-band maximum shadowing loss is 28.69 dB, and this is underestimated since the minimum received power is close to or below the C-band noise floor"; "The L-band shadowing depth is 32.66 dB".
- Duration "ranges from 32.9 to 60.5 s for the four receivers".
- Table I, maximum / median loss in dB: C1 28.69/11, C2 28.14/17.72, L1 32.66/11.57, L2 32.24/13.64.
- Fig. 8 (image read): the received power ramps down and up over roughly 10-20 s at each edge. — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884)

**Diversity**
- "The diversity gain is typically less than 5 or 6 dB outside the shadowing region but can be up to 16 dB during this shadowing event."
- "The antenna separation distance in our measurement is only up to 1.8 m. We hypothesize that further separated aircraft antennas would be even more helpful."
- Fig. 11 (image): diversity gain peaks at about 15.8 dB at L-band and about 15 dB at C-band. — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884)

**K-factor during shadowing (Sec. III)**
- "K-factor is on average 15 dB without shadowing, and decreases dramatically down to -16 dB during the airframe shadowing, roughly corresponding to Rayleigh fading".
- Caveat in the paper: the K estimate during shadowing is less reliable, "since it was estimated over a distance less than our computed stationarity distance (SD) of 15 m".
- Fig. 12 (image): Rx1 dips to about -5 dB and Rx2 to about -16 dB. — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884)

**Depth statistics (Sec. IV-A)**
- "The median loss is on average 15.5 dB in C-band and 10.8 dB in L-band."
- "The maximum and mean shadowing loss are more strongly influenced by small-scale fading. The C-band maximum and mean loss are also affected by the receivers' noise floor."
- Fig. 14 (image), L-band maximum loss: Gaussian (μ=35.8, σ=7.1), GEV (k=−0.54, μ=34.4, σ=7.5), Weibull (β=6.4). The empirical CDF runs from about 17 to 47 dB. — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884)

**Depth vs roll (eq. 2, Table II)**
- Model: S(Roll) = A + n·(Roll − Roll_min) + X.
  - L-band: n = 0.09 dB/°, A = 9.6 dB, σ = 2.8 dB.
  - C-band: n = 0.25 dB/°, A = 12.4 dB, σ = 4.4 dB.
  - Roll_min 16.1°, max roll 58.3°.
- "These parameters are specific to the S-3B Viking aircraft or similar mid-sized aircraft with antennas on the bottom."
- The roll variable is the event's maximum roll angle (Table II title: "median shadowing loss versus maximum roll angle"). — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884)

**Duration (Sec. IV-B, Fig. 16 image)**
- "The durations are on average 35.2 s in C-band and 25.5 s in L-band". Gaussian fits are C (35.2, 14.2) and L (25.5, 12.1); the support is about 4-72 s.
- "the duration is over-estimated since the flight velocity was intentionally kept low".
- Duration "would be difficult to re-scale accurately to other velocities".
- Depth and duration are "nearly uncorrelated". — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884)

**Simulation model (Sec. IV-C, eqs. 4-8)**
- L_T(t) = PL(t) + L_S(t), with L_S(t) = S·f(t) − 20log10[a(t)].
- "The value S is constant for each shadowing event. The process a(t) is a Ricean small scale fading process with small K-factor (e.g., below 0 dB)".
- f(t) is a cubic spline through (0,0), (0.5,1), (1,0) of the duration.
- The algorithm allows multiple (J) non-overlapping events per run. — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884)

**Conclusion (Sec. V)**
- "The L-band maximum shadowing loss was 47 dB."
- Diversity gain "up to 16 dB here for our antennas separated by ≈1.8 m".
- Duration "reached a maximum value of 74 s for our aircraft velocities on the order of 100 m/s".
- "Future work ... could address airframe shadowing for large-sized or small-sized aircraft".
- Internal inconsistency: the abstract says "The maximum shadowing loss measured was over 35 dB". — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884)

**Literature quoted in Part IV (Sec. I)**
- At 5.7 GHz over the sea (Meng and Lee): "wing shadowing attenuations up to 28 dB with maximum aircraft (AC) roll angle of approximately 24 degrees. The use of two GS antennas separated in height by 5.55 m and horizontally by 6.46 m were unable to provide any significant spatial diversity gain".
- At 20 GHz, aircraft to satellite: "up to 15 dB attenuation, with roll angle of 45 degrees". — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884)

#### S2. R. Sun, "Dual-Band Non-Stationary Channel Modeling for the Air-Ground Channel", PhD dissertation, Univ. South Carolina, 2015 (library: "Dual-Band Non-Stationary ... Chan.pdf"; read: abstract, Secs. 2.2-2.3, 3.2.3, 3.5, 5.2.2-5.3.3, Ch. 7, Ch. 8)

**Abstract (pp. vii-viii)**
- "the shadowing duration was found to be on average 30 seconds, and the shadowing loss can be as large as 40 dB."
- "these K-factors are approximately 28.7 dB in C-band and 13.1 dB in L-band".
- "the stationarity distance is approximately 15 m". — [Sun 2015](https://scholarcommons.sc.edu/etd/3655)

**Second example event (Sec. 5.3.1, Palmdale FT11; not in Part IV)**
- "The maximum roll angle was 26.9° in this AFS event."
- "The elevation angle was approximately 5.2°"; distance 20.5-22.2 km; "aircraft velocity was approximately 100 m/s".
- Table 5.10, maximum loss: C 33.9 / 33.0 dB, L 43.3 / 25.7 dB. Median: C 13.2 / 9.1 dB, L 12.9 / 6.6 dB. Duration: C 52.4 / 48.9 s, L 36.3 / 33.2 s.
- "the diversity gain is up to 20 dB in L-band and 16 dB in C-band in the AFS area". — [Sun 2015](https://scholarcommons.sc.edu/etd/3655)

**Ground-site diversity (Sec. 5.3.1)**
- "In [46], the authors experimentally analyzed the diversity gain provided by multiple GS antennas (a few meters separation distance), and found this almost useless to mitigate the airframe shadowing." — [Sun 2015](https://scholarcommons.sc.edu/etd/3655)

**Model statistics (Sec. 5.3.2)**
- Median-loss histograms: C "Gaussian (u=15.5, std 4.9)", L "Gaussian (u=10.8, std=3)". The histogram axes stop at about 25 dB (C) and 20 dB (L).
- Speed stated here: "The flight velocity was between 60 to 100 m/s". This contradicts Part IV's "70 to 120 m/s".
- Table 5.12 (loss vs duration): L-band maximum-loss slope 0.24 dB/s, A = 31 dB, σ = 6.3 dB. Durations 4.6-69.1 s (L) and 4.9-71.9 s (C). — [Sun 2015](https://scholarcommons.sc.edu/etd/3655)

**Simulation (Sec. 5.3.3)**
- "a(t) denotes a Ricean fading random variable with K=0 dB (other options are also applicable)".
- "the instantaneous shadowing loss is 5 dB at the start and stop points".
- If geometry is known, "shadowing depth S and duration D both depend upon roll and heading angles". — [Sun 2015](https://scholarcommons.sc.edu/etd/3655)

**Conclusions (Sec. 8.1)**
- "The median shadowing loss is on average 16 dB in C-band and 11 dB in L-band. The maximum loss in L-band is on average 36 dB with the maximum single L-band shadow depth recorded at 47.8 dB."
- "These durations are longer than expected for practical flights". — [Sun 2015](https://scholarcommons.sc.edu/etd/3655)

**K-factor tables (Tables 5.7-5.9), all straight flight tracks**
- Suburban: median C 28.7, L 13.8 dB.
- Hilly: C 29.6, L 12.6 dB; L-band minimum −6.3 dB (moment-based estimator).
- Mountainous: C 29.4, L 13.8 dB.
- During shadowing over Lake Erie (Sec. 5.2.3): K "dropped to below -20 dB in the shadowing area". — [Sun 2015](https://scholarcommons.sc.edu/etd/3655)

**Antenna correlation on the aircraft (Ch. 7)**
- Over freshwater, "The median value is approximately 0.9 for both bands". Median correlation in all scenarios was 0.85-0.99 (Table 7.2).
- "The spatial correlation median values decreased from 0.85 or above outside the AFS to approximately 0.6 in the AFS" (Table 7.3).
- Intra-band antennas about 1.82 m apart, bottom-mounted, "were found to be highly correlated except where the airframe shadowing occurred" (Sec. 8.1).
- Note: this is the correlation of received-amplitude vectors over the stationarity distance. It includes the LOS and two-ray structure, so it is not the diffuse-component complex correlation. — [Sun 2015](https://scholarcommons.sc.edu/etd/3655)

**Stationarity and the local-mean window (Sec. 3.5)**
- The dissertation cites Lee 1985 and states: "However, the AG channel almost always has LOS component and yields Ricean fading. Its SD has to be reconsidered."
- "The C-band SD is approximately 15 m (250 wavelengths)" (Sec. 8.1). — [Sun 2015](https://scholarcommons.sc.edu/etd/3655)

**Literature reviewed in the dissertation (secondary, Sec. 2.2)**
- [35] Welling-Dye-Rice, 2.3 GHz: "The Ricean K factor ranged from 7 to 24 dB ... Note that multipath was suppressed by using a very high gain tracking receiver antenna which yields very narrow beamwidth". One segment had "a K factor of -48 dB ... explained by strong reflections by the wing and fuselage during some specific maneuvers".
- [36] Simunek et al., 2 GHz, ground-site monopoles 1.5λ apart in an urban street: "The spatial correlation among different antennas was below 0.3."
- [44], 5.8 GHz near an airport: "0 dB for parking, 5 dB for taxiing, 10 dB for landing and 15 dB for en-route conditions". — [Sun 2015](https://scholarcommons.sc.edu/etd/3655)

#### S3. W. C. Y. Lee, "Estimate of local average power of a mobile radio signal", IEEE TVT VT-34(1):22-27, Feb 1985, doi 10.1109/T-VT.1985.24030 (library PDF, read in full)

**Abstract**
- "The measured length of a mobile radio signal necessary to obtain the local average power is determined to be in the range of 20 to 40 wavelengths. It is based on the Rayleigh distribution. The sufficient number of samples for estimating the local average power values is about 36. It is based on a 90 percent confidence interval and less than 1 dB error in estimate." — [Lee 1985](https://doi.org/10.1109/T-VT.1985.24030)

**Window length (Sec. III-C)**
- "we may choose 2L = 20λ, if we are willing to tolerable 1σ spread in a range of 1.56 dB, or 2L = 40λ tolerating spread in a range of 1 dB".
- "For the case of less than 20 wavelengths, the 1σ spread starts to increase quickly ... Averaging a piece of signal data that the length is longer than 40 wavelengths risks the smoothing out of long-term fading information." — [Lee 1985](https://doi.org/10.1109/T-VT.1985.24030)

**Sampling (Sec. IV)**
- Per-sample spread σ_r = 3.65 dB (eq. 20). N ≥ 36 (eq. 31).
- "these samples have to be uncorrelated samples".
- "d = 0.5λ (in theory), d = 0.8λ (from the measurement)".
- "40λ/36 = 1.11λ ... greater than 0.8λ". — [Lee 1985](https://doi.org/10.1109/T-VT.1985.24030)

**Conclusion (Sec. V)**
- With a direct (LOS) wave "the environment produces ... a Rician distribution. In this case, we do not need a length 2L = 40λ. However ... the direct wave component ... comes and goes ... Therefore, it is better to set a length of 2L = 40λ, and N = 36 to handle all situations." — [Lee 1985](https://doi.org/10.1109/T-VT.1985.24030)

**Context:** terrestrial base station to vehicle (the paper names no carrier frequency). Spatial averaging along a road; analog filtering is avoided in favour of samples. — [Lee 1985](https://doi.org/10.1109/T-VT.1985.24030)

#### S4. Z. Cui, C. Briso-Rodríguez, K. Guan, C. Calvo-Ramírez, B. Ai, Z. Zhong, "Measurement-Based Modeling and Analysis of UAV Air-Ground Channels at 1 and 4 GHz", IEEE AWPL 18(9):1804-1808, Sept 2019, doi 10.1109/LAWP.2019.2930547 (read from extract src/W10; the PDF is NOT in the library folder)

**Setup**
- DJI N3 hexacopter, "The UAV belongs to the type of 'small' with a weight of 4.7 kg".
- CW at 1 and 4 GHz, 30 dBm. The UAV is the transmitter; the GS receiver is on a 25 m roof, 350 m away.
- "The altitude of UAV goes from 0-24 m (±1 m)": vertical flights.
- "Because of the blockage of building with a height of 15 m, the link is NLOS when the altitude of UAV is from 0 to 11 m". — [Cui 2019](https://doi.org/10.1109/LAWP.2019.2930547)

**Path loss model (eq. 4)**
- PL0 = 40.55 + 20log10(d3D) + 20log10(f) − nLOS·h (LOS); 62.41 + ... − nNLOS·h (NLOS).
- "nLOS = 0.102 and nNLOS = 1.190 at 1 GHz and nLOS = 0.250 and nNLOS = 2.075 at 4 GHz". — [Cui 2019](https://doi.org/10.1109/LAWP.2019.2930547)

**Shadow fading (Sec. III-B)**
- "We obtain the shadowing data by averaging the instantaneous received power over a 40-wavelength sliding window [10]". [10] is Lee 1985.
- "The maximum SF can reach 18.36 and 22.41 dB at 1 and 4 GHz, respectively."
- SF is a zero-mean Gaussian; the paper reports large SF (">10 dB") under NLOS. — [Cui 2019](https://doi.org/10.1109/LAWP.2019.2930547)

**Fast fading (Sec. III-C, III-D)**
- "Since most multipath components are with low power, the fades are not severe in the selected scenario"; "the maximum fading value and fading depth under NLOS case at 1 GHz is 13.53 dB and 5.711 dB".
- Log-logistic is the best fit, ahead of Rician, Nakagami and Rayleigh.
- Table II values were not machine-readable in the extract.
- Antennas: the Tx is an approximately omnidirectional 3 dBi RM-WHF; the Rx is a λ/4 monopole (2.15 dBi). Both are vertically polarised. The E-plane patterns are shown only at 4 GHz (Fig. 3). — [Cui 2019](https://doi.org/10.1109/LAWP.2019.2930547)

#### S5. W. Khawaja, I. Guvenc, D. W. Matolak, U.-C. Fiebig, N. Schneckenburger, "A Survey of Air-to-Ground Propagation Channel Modeling for Unmanned Aerial Vehicles", arXiv:1801.01656v1 (Jan 2018)

The library holds the arXiv v1 (W08 and 1801.01656v1.pdf). The project cites "IEEE COMST 2019". The published-version details are UNVERIFIED here: the Crossref lookup returned only a 2020 Wiley book-chapter version (doi 10.1002/9781119575795.ch2). The extract khawaja.txt was read; locations below are line numbers in that extract.

**Speed**
- From FAA small-UAV rules (< 25 kg, 55 lb): "a maximum speed of 100 mph (87 knots, or 161 km/h)" (Sec. I, l.16).
- "Many of the AG channel measurements ... fixed wing aircraft with maximum speeds varying from 17 m/s to 293 m/s. The speed of rotorcraft and air balloons ... ranges from 8 m/s to 20 m/s" (l.489). — [Khawaja 2018](https://arxiv.org/abs/1801.01656)

**K-factor (Sec. on narrowband fading, l.705)**
- "In [62] ... values of K ranging from 2 dB to 10 dB were reported" (trees).
- "The mean values of K-factor for urban areas were reported to be 12 dB and 27.4 dB for L-band and C-band respectively ... hilly and mountainous terrain ... 12.8 dB and 29.4 dB ... over sea ... 12.5 dB and 31.3 dB".
- Table VI, K-factor column: "(-5)-10 | 12-27.4 in L and C band | 2-5 | 12, 28 for L and C band".
- The row mapping is ambiguous in the extract. Most likely (-5)-10 belongs to [30] Simunek-Fontán-Pechac, TAP 2013 (urban, low elevation); UNVERIFIED mapping.
- The survey is internally inconsistent: the text says 2-10 dB for trees, Table VI says 2-5. — [Khawaja 2018](https://arxiv.org/abs/1801.01656)

**Airframe shadowing (Sec. "C. Airframe Shadowing", l.915-917)**
- "such shadowing can be largely (but not always completely) alleviated by using multiple spatially separated antennas".
- "For small rotorcraft, depending on frequency and antenna placement, airframe shadowing could be minimal."
- "at frequencies of 970 and 5060 MHz, wing shadowing attenuations were generally proportional to aircraft roll angle, with maximum shadowing depths exceeding 35 dB at both frequencies. Shadowing durations depend upon flight maneuvers, but for long, slow banking turns, can exceed tens of seconds."
- Fig. 6: two bottom antennas "separated by approximately 1.2 m ... Attenuations due to airframe shadowing, along with the polarization mismatch that occurs during the aircraft maneuver, exceed approximately 30 dB". — [Khawaja 2018](https://arxiv.org/abs/1801.01656)

**Antennas**
- "With high maneuverability of UAVs during flight, omni-directional antennas are generally better suited than directional antennas. A potential major drawback of any antenna on-board UAVs is the shadowing from the body of the UAV" (l.105).
- "In the majority of measurements the antennas were mounted on the bottom of the aircraft's fuselage or wings ... This characteristic [orientation] is most important during banking turns, and when the aircraft pitch angle deviates from horizontal" (l.130).
- Table III lists UAV-side configurations with 2, 3 and 4 omni antennas. — [Khawaja 2018](https://arxiv.org/abs/1801.01656)

**Hover and non-stationarity (l.51)**
- "the characteristics of the channel could instead actually change very slowly, especially for hovering UAVs. In such a case, adverse propagation conditions, e.g., deep fades of the received signal, may last several seconds or even minutes, hence common communication techniques of interleaving or averaging would not be effective."
- l.1220: "time-invariant approximations, e.g., when a UAV is hovering above an area of static objects ... the channel is considered to be quasi stationary only for short distances". — [Khawaja 2018](https://arxiv.org/abs/1801.01656)

**Doppler (l.125)**
- MPCs from the GS surroundings "are seen all under similar angles from the aircraft. The effect of a large Doppler frequency that is constant for all MPCs should be well mitigated by frequency synchronization."
- Note: the "similar angles" sentence is about Doppler, not about antenna correlation. — [Khawaja 2018](https://arxiv.org/abs/1801.01656)

**Orientation and attitude (l.685, l.1072)**
- "[38] ... PLEs for IEEE 802.11 communications were different during UAV hovering and moving due to different orientations of the on-board UAV antennas".
- "[39] ... Spatial diversity from antennas located on the UAV was also observed, interestingly at higher elevation angles"; "[63] ... MIMO ... more robust channel for changes in antenna orientations arising from UAV maneuvering". — [Khawaja 2018](https://arxiv.org/abs/1801.01656)

#### S6. M.-S. Alouini, A. J. Goldsmith, "A Unified Approach for Calculating Error Rates of Linearly Modulated Signals over Generalized Fading Channels", IEEE Trans. Commun. 47(9):1324-1334, 1999, doi 10.1109/26.789668 (library P05, read)

- Abstract: "The analyses assume independent fading paths, which are not necessarily identically distributed."
- Footnote 2: "independent fading paths for microdiversity systems (antenna arrays) is unlikely in the presence of large-scale fading effects, such as shadowing."
- MRC over independent branches is the product of the branch MGFs. The Rice MGF is eq. 28.
- A "combined (time-shared) shadowed/unshadowed" pdf is included: "when shadowing is present, it is assumed that no direct LOS path exists and the received signal power ... is assumed to follow an exponential/log-normal (Hansen-Meno) pdf ... characterized by the shadowing time-share factor" (Sec. II-B, eqs. 12-13). — [Alouini 1999](https://doi.org/10.1109/26.789668)

#### S7. P. Ramírez-Espinosa, L. Moreno-Pozas, J. F. Paris, J. A. Cortés, E. Martos-Naya, "A New Approach to the Statistical Analysis of Non-Central Complex Gaussian Quadratic Forms with Applications", IEEE TVT 68(7):6734-6746, July 2019, doi 10.1109/TVT.2019.2916725 (library W07 = arXiv:1805.09181v2; read)

- Sec. V: MRC with P branches, gi ~ mean sqrt(Ki/(Ki+1)), covariance R_ij/sqrt((Ki+1)(Kj+1)) (eq. 34). K may differ per branch. "Considering perfect symbol synchronization and channel estimation".
- Numerical examples use exponential correlation ρ^|i−j|.
- "increasing the correlation between branches implies a considerable degradation of the system performance when the LoS is strong (large Ki factors). In fact, when ρ = 0.9, the outage probability is asymptotically higher in a strong LoS scenario than in a weak one" (Sec. V-D). — [Ramírez-Espinosa 2019](https://doi.org/10.1109/TVT.2019.2916725)

#### S8. ITU-R Recommendation P.838-3 (2005), "Specific attenuation model for rain for use in prediction methods" (library W06, read)

- γ_R = k·R^α, with k and α from curve fits over 1-1000 GHz (eqs. 2-3).
- Trap in the text extract: `pdftotext` shifts the frequency labels of Table 5 down by one row, so the "2.5" label lands on the 3 GHz row.
- I recomputed eqs. 2-3 with the Table 1 and Table 3 coefficients (derived):
  - 2.5 GHz: kH = 0.0001321, αH = 1.1209, so γ(100 mm/h) = 0.023 dB/km.
  - 2.4 GHz: kH = 0.0001244, αH = 1.1074, so 0.0204 dB/km.
- This confirms the project's values (LITERATURE.md, ranking document) are the correct 2.5 GHz row. — [ITU-R P.838-3](https://www.itu.int/rec/R-REC-P.838-3-200503-I/en)

#### S9. J. Rodríguez-Piñeiro, T. Domínguez-Bolaño, X. Cai, Z. Huang, X. Yin, "Air-to-Ground Channel Characterization for Low-Height UAVs in Realistic Network Deployments", arXiv:2007.11502v1 (2020); published IEEE TAP 69(2):992-1006, Feb 2021, doi 10.1109/TAP.2020.3016164 (library V7_RodriguezPineiro2020; extract rp.txt read)

**Setup**
- Ground transmits and the UAV receives, the same direction as our GCS-to-UAV uplink: "The ground part contains another USRP N-210 used to transmit the signals ... and two transmitter antennas, being only one used at a time".
- 2.5 GHz, 15.36 MHz (Table IV), 40 dBm.
- "0 dBi (omnidirectional, UAV and BS)", "12 dBi (directional, BS)", BS height 15 m (Table III).
- Flight heights 15-105 m; speed "the UAV of 5 m/s". — [Rodríguez-Piñeiro 2020](https://arxiv.org/abs/2007.11502)

**Directional antenna orientation (Sec. II)**
- "the effect of the radiation pattern of the directional antenna used at the BS was not removed".
- "The directional antenna is oriented so that the axis of the main lobe follows the direction of the 15 m height flight for each scenario. This way, a 0 tilt configuration was considered, being the main lobe parallel to the ground."
- The omni pattern was compensated (de-embedded). — [Rodríguez-Piñeiro 2020](https://arxiv.org/abs/2007.11502)

**Table IX K-factor, normal fits, mean (variance) in dB**

| Antenna, environment | 15 m | 25 m | 35 m | 45 m | 60 m | 75 m | 90 m | 105 m |
|---|---|---|---|---|---|---|---|---|
| Env I, omni | 15.82 | 14.46 | 12.67 | 13.50 | 11.64 | 14.35 | 15.01 | 14.02 |
| Env I, directional | 5.54 | 11.37 | 9.30 | 8.19 | 11.23 | 10.30 | 10.00 | 9.19 |
| Env II, omni | 14.58 LoS / 4.58 OLoS | 10.92 | 12.28 | 11.54 | 10.89 | 12.72 | 16.28 | 15.62 |
| Env II, directional | 12.62 LoS / 1.76 OLoS | 12.00 | 9.96 | 13.29 | 12.91 | 15.45 | 11.76 | 11.13 |

Variances are 1.73-5.56 dB². — [Rodríguez-Piñeiro 2020](https://arxiv.org/abs/2007.11502)

**Text and conclusions**
- "When the directional antenna is used at the BS, the K-factor results are in general decreased, specially for the highest flights."
- "the use of the BS antenna can slightly increase the RMS Doppler frequency spread".
- RMS Doppler spread, log10(Hz) (Table VIII): Env I omni 0.50-0.86, directional 0.99-1.40.
- Conclusions: "the Kfactor, as well as the path loss, are severely affected by the ground elements and the radiation pattern of the antenna at the BS"; "the use of a directional BS antenna ... (even for 0 tilt), limits the flight height and distance ranges, and can influence the time and frequency coherence of the channel". — [Rodríguez-Piñeiro 2020](https://arxiv.org/abs/2007.11502)

#### S10. J. Gomez-Ponce et al., "Air-to-Ground Directional Channel Sounder With 64-antenna Dual-polarized Cylindrical Array", arXiv:2103.09135 (2021); IEEE ICC Workshops 2021, doi 10.1109/ICCWorkshops50388.2021.9473627 (library V7_GomezPonce2021; extract ds.txt read)

**Setup**
- 3.5 GHz, 46 MHz, DJI Matrice 600 Pro carrying the Tx; the Rx is a 64-port array.
- Footnote: "Doppler analysis is not perform at the current stage. Drone speed is set to be ≤3m/s." — [Gomez-Ponce 2021](https://arxiv.org/abs/2103.09135)

**Hover vs static (Sec. IV)**
- Geometry: "distance between TX and RX was approximately 12 meters and the antenna of the transmitter was set to be 1.8 meters from the ground".
- "we anticipate that variations of the receive power will be higher in the hovering scenario because of the vibrations of the drone and the inability of hovering to keep the drone in exactly the same location".
- "the standard deviation for the LOS bin power is 0.08dB for the static case and 0.48dB for hovering".
- RMS delay spread mean (std) in dBs: static −78.52 (0.08), hover −79.44 (0.27).
- The pole-mounted antenna was "upside down"; the "power in the V-polarization is approximately 12dB higher than in the H-polarization". — [Gomez-Ponce 2021](https://arxiv.org/abs/2103.09135)

#### S11. M. Simunek, P. Pechac, F. P. Fontán, "Excess Loss Model for Low Elevation Links in Urban Areas for UAVs", Radioengineering 20(3):561-568, 2011 (library V7_Simunek2011; extract simunek.txt read)

**Setup**
- "Representative measurements have been performed at 2 GHz."
- A remote-controlled airship carried a monopole "on the bottom side", 27 dBm CW. It flew "from a distance of 1.2 to 6.5 km in flight levels from 150 m to 300 m above ground", "under elevation angles from 1.6° to 6.5°".
- Receiver (the GCS role) at street level in Prague, 1.5 m high, "four quarter-wave monopoles ... forming a square of side 22.5 cm (1.5λ)". — [Simunek 2011](https://www.radioeng.cz/fulltexts/2011/11_03_561_568.pdf)

**Attitude filter (Sec. 2)**
- "pitch and roll data ... were used to discard invalid sections of the data with high pitch/roll angles, as possible large polarization or antenna pattern losses could have taken place, as well as partial shadowing of the transmit antenna."
- "The acceptable limits for both angles were set to a maximum of 10°." — [Simunek 2011](https://www.radioeng.cz/fulltexts/2011/11_03_561_568.pdf)

**Processing and results**
- "a size of 4,000 wavelengths (600 m) was found to adequately remove the slow and fast variations, leaving in only the very slow variations".
- "It is rather the elevation that significantly determines the excess loss".
- "a significant gain of about 5 dB when we move away from the first building".
- Model error overall ME/STD: #1 0.14/2.71 dB, #2 0.06/2.2 dB (Tab. 1).
- The excess-loss magnitudes appear only in Figs. 6 and 11. Those figures were not machine-readable (gap). — [Simunek 2011](https://www.radioeng.cz/fulltexts/2011/11_03_561_568.pdf)

#### S12. Y. Lyu, Y. He, Z. Liang, W. Wang, J. Yu, D. Shi, "Measurement-Based Tapped Delay Line Channel Modeling for Fixed-Wing UAV Air-to-Ground Communications at S-Band", Drones 8(9):492, 2024, doi 10.3390/drones8090492 (DOWNLOADED to the library as V7_Lyu2024_FixedWing_A2G_TDL_27GHz.pdf; read in full)

**Setup**
- Fixed-wing VTOL UAV carrying the transmitter (USRP X310 and an IMU recording "the coordinates and UAV attitude").
- "36 dBm ... bandwidth of B = 25 MHz at 2.7 GHz"; "The omni-directional transmitter antenna was fixed below the airframe". Tx omni 6 dBi, Rx omni 3 dBi, both V-pol (Table 1).
- Rural area; receiver 1.5 m above ground, 35 m from the take-off point.
- "constant speed of 27 m/s and a maximum transmitter-receiver (Tx-Rx) distance of 3 km. The maximum flight height was 800 m". Table 1 says 700 m (internal inconsistency). — [Lyu 2024](https://doi.org/10.3390/drones8090492)

**Flight phases (Sec. 2.3, Table 2)**
- "Hovering preparation: the UAV ascends in a circular path with a radius of 300 m up to 300 m height, flying at a constant speed about 27 m/s".
- FS1 vertical landing: 0-40 m height, 1.2 m/s, 35-60 m range.
- FS4-FS6 steady flight: 300, 500 and 800 m height at 27 m/s. — [Lyu 2024](https://doi.org/10.3390/drones8090492)

**K-factor (Sec. 4.2, Table 4)**
- First-tap K: FS1 27.58 dB, FS2 19.78 dB, FS3 20.03 dB, FS4 15.96 dB, FS5 17.08 dB, FS6 17.23 dB.
- These are per-tap K-factors at 20-25 MHz resolution (50 ns taps), not narrowband K.
- FS1: "the UAV descending smoothly at a speed of 1.2 m/s, in the open rural environment, resulting in less severe multipath effect". — [Lyu 2024](https://doi.org/10.3390/drones8090492)

**Doppler (Sec. 4.3)**
- "The UAV descends vertically ... with a speed of 1.2 m/s, which results in a maximum Doppler frequency 10.8 Hz".
- In the circling ascent, "The Doppler frequency of LoS component varies between 89 Hz and -152 Hz"; in steady flight, "the Doppler shift of the LoS component remains constant at approximately 201 Hz".
- "the 'Jakes'- and 'flat'-type spectrum shapes show the poor performance ... The 'Bell'- and 'Gaussian'-type spectrum shapes fit the LoS component better"; "we propose to use the 'Bell'-type spectrum for the first two channel taps, and the 'Jakes'-type spectrum for the remaining taps".
- No roll or bank values are given anywhere in the paper. — [Lyu 2024](https://doi.org/10.3390/drones8090492)

#### S13 (new, found and downloaded). K. Aoki, K. Honda, "Measurement and Analysis of the Rician K-Factor for Low-Altitude UAV Air-to-Ground Communications at 2.5 GHz", Drones 9(2):86, 2025, doi 10.3390/drones9020086 (saved as V7_Aoki2025_Rician_K_LowAltitude_UAV_25GHz.pdf; read, but the PDF text layer is duplicated and partly garbled)

**Setup**
- "As the 2.4 GHz band is widely used for UAV control, we measured the received power from the UAV to the ground at 2.5 GHz".
- DJI Mavic Mini 3; half-wave dipoles at both ends; the UAV is tethered.
- Table 2: 0.3 m/s, altitude 10-30 m, measurement time 5 s (simple environment) / 10 s (complex), migration length 1.5 m / 3 m. — [Aoki 2025](https://doi.org/10.3390/drones9020086)

**Hover-like statement (Sec. 2.2)**
- "Changes in UAV attitude and position due to wind will cause changes in the scattered path power, so the received signal may fluctuate slightly, but drastic changes such as fading are not expected. In such cases, the Rician K-factor cannot be accurately estimated from the measurement data." — [Aoki 2025](https://doi.org/10.3390/drones9020086)

**Results**
- Complex environment, horizontal installation, H = 10 m: "the estimated Rician K-factor is 4.94 dB". Ray tracing gave 14.54 dB, which the authors say overestimates.
- Vertical installation: "the values obtained from the simulation and measurements remain relatively constant at approximately 0 dB".
- Conclusion: "Especially in the C environment, the communication performance was very stable with a horizontal installation".
- Limits stated by the authors: 2.5 GHz only; "the dynamic characteristics of moving UAVs remain future challenges". — [Aoki 2025](https://doi.org/10.3390/drones9020086)

#### S14 (new, downloaded). M. Banagar, H. S. Dhillon, A. F. Molisch, "Impact of UAV Wobbling on the Air-to-Ground Wireless Channel", arXiv:2004.02771v2 (2020); IEEE TVT 69(11):14025-14030, 2020, doi 10.1109/TVT.2020.3026975 (saved as V7_Banagar2020_UAV_Wobbling_A2G_Coherence.pdf; read)

- Analytic only, no measurement.
- "Although this wobbling is typically small (less than 10° [8])".
- Assumptions: hovering rotorcraft, sinusoidal pitch wobble with amplitude U[−θm, θm) and frequency U[5, 25) Hz, antenna offset aD = 40 cm, K = 11.5, threshold 0.5.
- Results: "TC = {∞, 12.26, 6.74} ms for θm = {5, 7, 10}°, respectively, when fc = 2.4 GHz"; at θm = 5°, TC = {∞, 5.18, 0.97} ms for 2.4/6/30 GHz.
- The authors: "the derived values ... should be treated as useful ballpark figures". — [Banagar 2020](https://arxiv.org/abs/2004.02771)

#### S15 (new, downloaded). A. Saboor, Z. Cui, A. Colpaert, E. Vinogradov, W. Joseph, S. Pollin, "Trajectory-Aware Air-to-Ground Channel Characterization for Low-Altitude UAVs Using MaMIMO Measurements", arXiv:2510.23465 (2025); IEEE TVT 75(8):17391-17406, 2026 per Crossref (saved as V7_Saboor2025_TrajectoryAware_A2G_MaMIMO_261GHz.pdf; skimmed: setup and K and stationarity sections)

**Setup**
- 2.61 GHz, 18 MHz; DJI Inspire 2 with a downward patch antenna; ground array of 64 elements; suburban.
- Trajectories at 49 m and 59 m (zig-zag, about 4 m/s) and a vertical ascent from 0 to 59 m. — [Saboor 2025](https://arxiv.org/abs/2510.23465)

**K-factor**
- "The K-factor increases from approximately 5 dB at low altitudes to over 15 dB at higher elevations".
- Fit K(h) = a·ln(h) + b, with a = 5.414, b = −6.639, "restricted to h ≥ 10 m". Derived: 5.8 dB at 10 m, 15.4 dB at 59 m.
- "the Nakagami model best fits the small-scale fading".
- CMD-based stationarity spans: azimuth decorrelates fastest in horizontal zig-zag flight. — [Saboor 2025](https://arxiv.org/abs/2510.23465)

### Inferences
- The S-3B shadowing numbers are the only measured airframe-shadowing statistics in hand.
  - Every source (Part IV Sec. II and Table II, Khawaja l.915) restricts them to similar-sized, bottom-antenna aircraft.
  - Khawaja even says shadowing "could be minimal" for small rotorcraft.
- Converting Table II at the measured roll extremes (derived):
  - Roll 16.1-58.3° gives median loss 9.6-13.4 dB at L-band and 12.4-22.9 dB at C-band, ± 2.8 / 4.4 dB.
  - At the FT11 roll of 26.9°: about 10.6 dB (L) and 15.1 dB (C).

### Gaps
- No measured airframe shadowing at 2.4 GHz or on small UAVs in any source read.
- Sun Part I-III (K-factor, path loss and SD details per environment) were not read (paywalled).
- Simunek 2013 TAP, the probable primary source of the K = −5 dB lower bound, was not read.
- Cui 2019 Table II and Simunek 2011 Figs. 6 and 11 numbers are figure-only and were not read.

---

## Q2. Is the project's current use of each source supported by the text? (flags: overreach, wrong numbers, out-of-range)

### Takeaway
Most citations are textually correct, but four uses go beyond what the text proves:
1. The 40 dB shadowing level is applied as a constant attenuation, on a branch that keeps its normal K. The text gives 40 dB as a peak that includes fading; the sustained median is 10.8-15.5 dB on average, and K collapses to about 0 dB or below.
2. The receive correlation ρ = 0.3 is attributed to Khawaja, who gives no such number. Sun measured high correlation on the aircraft underside.
3. "21.9 dB building blockage" is my arithmetic from Cui's intercepts. It applies only to a UAV at ground level.
4. Lee's 20-40λ rule is a spatial, Rayleigh rule. It breaks at hover and at high speed with a 20 ms cycle.

The P.838 and Alouini/W07 uses are correct.

### Cited Findings

**F1. Airframe shadowing up to 40 dB (DECISIONS D72 "Sun ... up to 40 dB, events of about 30 s"; code `dataset_levels.m` levels 5..40, `decision_config.m` 8/14/20/30/40)**
- What the project does (read-only check of v6 code): `build_threat_model.m` applies `y(:, hit_ant) = y(:, hit_ant) * 10^(-shadow_db/20)`, a constant scalar on one antenna for the whole run. The antenna keeps the flight's K drawn from −5..20 dB.
- The text-supported parts:
  - "the shadowing loss can be as large as 40 dB" and "on average 30 seconds" — [Sun 2015](https://scholarcommons.sc.edu/etd/3655), abstract.
  - Aircraft antenna diversity helps; GS diversity is "almost useless" — [Sun 2015](https://scholarcommons.sc.edu/etd/3655) Sec. 5.3.1; [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884) Sec. I.
- Overreach (a): 40 dB is a per-event maximum that includes small-scale fading. The paper itself says "The maximum and mean shadowing loss are more strongly influenced by small-scale fading" — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884) Sec. IV-A.
  - The modelled sustained depth S is the median: C ~ N(15.5, 4.9) and L ~ N(10.8, 3.0), with histograms ending at about 25 dB and 20 dB — [Sun 2015](https://scholarcommons.sc.edu/etd/3655) Figs. 5.40-5.42.
  - The source's own model adds Rician fading "with small K-factor (e.g., below 0 dB)" on top of S — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884) eq. 7.
  - So a constant 40 dB plus normal-K fading exceeds the measured sustained depth. It also double counts relative to the source's definition.
- Overreach (b): the shadowed branch's K is not lowered. Measured K falls from about 15 dB to −16 dB (Part IV) or below −20 dB (dissertation Sec. 5.2.3), and inter-antenna correlation falls to about 0.6 (dissertation Table 7.3) — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884); [Sun 2015](https://scholarcommons.sc.edu/etd/3655).
- Out of measured scope (c): frequency (968 MHz and 5.06 GHz, not 2.4 GHz) and aircraft (S-3B at 60-120 m/s, not a small UAV).
  - 2.4 GHz lies between L and C, so the frequency bracket is respected.
  - The aircraft-size scope is not: "should be applicable to aircraft similar in size" — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884). And "For small rotorcraft ... airframe shadowing could be minimal" — [Khawaja 2018](https://arxiv.org/abs/1801.01656).
- Inconsistency for citation: the headline maximum differs across the same authors' texts. Abstract of Part IV "over 35 dB"; Part IV conclusion "47 dB"; dissertation abstract "as large as 40 dB"; dissertation Sec. 8.1 "47.8 dB". Speed is also given as "70 to 120 m/s" (Part IV) vs "60 to 100 m/s" (dissertation Sec. 5.3.2) — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884); [Sun 2015](https://scholarcommons.sc.edu/etd/3655).
- D68 and D72 also say "Airframe shadowing ... lasts seconds" and "exceeds 35 dB" (from Khawaja). Both are textually fine: Khawaja says "exceeding 35 dB" and "can exceed tens of seconds" — [Khawaja 2018](https://arxiv.org/abs/1801.01656).

**F2. Path loss up to 22 dB (D72 "Cui et al. 2019: building blockage adds 21.9 dB, maximum shadow fading 22.4 dB at 4 GHz"; `dataset_levels.m` "path loss up to 22 dB (building blockage, Cui et al.)")**
- The "22.41 dB" is a verbatim number: "The maximum SF can reach 18.36 and 22.41 dB at 1 and 4 GHz" — [Cui 2019](https://doi.org/10.1109/LAWP.2019.2930547).
  - It is the peak of a zero-mean Gaussian shadow-fading term under NLOS (a deviation), not a sustained excess loss.
- The "21.9 dB" is not in the text. It is derived: 62.41 − 40.55 = 21.86 dB, the NLOS-minus-LOS intercept of eq. 4 at UAV altitude h = 0 — [Cui 2019](https://doi.org/10.1109/LAWP.2019.2930547).
  - At the heights where NLOS actually applies (0-11 m), the derived gap shrinks with h:
    - 1 GHz: 21.9 → 16.4 → 9.9 dB at h = 0 / 5 / 11 m.
    - 4 GHz: 21.9 → 12.7 → 1.8 dB.
  - So 22 dB corresponds to a 4.7 kg hexacopter on the ground behind a 15 m building at 350 m.
  - It is within the measured range (0-24 m), but at its edge, and it is not a condition of a flying UAV.
- The frequency (2.4 GHz) lies between the measured 1 and 4 GHz, so this is acceptable.
- The library holds only a text extract of Cui; the PDF is not in folder L.

**F3. K-factor −5..20 dB (D70 "Caps from the sources: K -5..20 dB (Khawaja et al.)"; init_params "foliage 2-5, urban -5..10, open L-band ~12, C-band ~28 dB")**
- −5..10 dB appears only in Khawaja Table VI, mapped most likely to [30] Simunek 2013 (urban, low elevation, about 2 GHz). That primary source is not in the library — [Khawaja 2018](https://arxiv.org/abs/1801.01656).
- "Foliage 2-5" matches Table VI, but the survey text says "2 dB to 10 dB" for the same reference.
- 12 and 28 match Table VI and Sun (L 13.1, C 28.7) — [Sun 2015](https://scholarcommons.sc.edu/etd/3655).
- At 2.3-2.7 GHz specifically:
  - 7-24 dB (Welling, via Sun Sec. 2.2, high-gain tracking antenna).
  - Means of 1.8-16.3 dB, omni and directional at 2.5 GHz — [Rodríguez-Piñeiro 2020](https://arxiv.org/abs/2007.11502).
  - About 0-5 dB at 2.5 GHz, small UAV, complex environment — [Aoki 2025](https://doi.org/10.3390/drones9020086).
  - About 5.8-15.4 dB at 2.61 GHz — [Saboor 2025](https://arxiv.org/abs/2510.23465).
  - First-tap (wideband) 16-27.6 dB at 2.7 GHz — [Lyu 2024](https://doi.org/10.3390/drones8090492).
- So both ends are inside what sources measured near 2.4 GHz. The −5 dB end rests on a secondary citation.
- Uniform −5..20 is a modelling choice. The measured distributions cluster at about 5-16 dB (inference, not a source statement).

**F4. Receive correlation ρ = 0.3 "kept (ground scatterers are seen under similar angles from the UAV, Khawaja et al.)" (D69; init_params `rx_corr = 0.3`)**
- NOT supported as a number. Khawaja's "seen all under similar angles from the aircraft" sentence (l.125) is about the Doppler of MPCs — [Khawaja 2018](https://arxiv.org/abs/1801.01656).
  - Physically, a narrow angular spread at the UAV raises spatial correlation; it does not lower it.
- The only "0.3" in these sources is the ground-site street-level array at 1.5λ: "The spatial correlation among different antennas was below 0.3" (Simunek 2012 via Sun Sec. 2.2) — [Sun 2015](https://scholarcommons.sc.edu/etd/3655).
- Measured on the aircraft underside at 1.24-1.82 m, the received-amplitude correlation has a median of 0.85-0.99 (about 0.6 during shadowing) — [Sun 2015](https://scholarcommons.sc.edu/etd/3655) Tables 7.1-7.3.
  - That metric includes the LOS term, so it is not the project's diffuse-component ρ. The comparison is not like-for-like (inference).

**F5. Local-mean window "Lee: local average over 20-40 wavelengths" (D72; `temporal_evidence.m` header)**
- The text supports the numbers: 20-40λ, N ≥ 36 uncorrelated samples spaced ≥ 0.8λ, ≤ 1 dB at 90%, Rayleigh worst case — [Lee 1985](https://doi.org/10.1109/T-VT.1985.24030).
- The project's window is n decision cycles of 20 ms, chosen by cross-validation, not a length in wavelengths. Derived at 2.4 GHz (λ = 0.125 m):
  - At 8.06 m/s, 20-40λ = 15.5-31 cycles.
  - At 44.7 m/s, it is only 2.8-5.6 cycles, giving a Lee 90% bound of 6.02/√N ≈ 2.5-3.6 dB.
  - 36 cycles at 44.7 m/s span 32 m, which exceeds Sun's 15 m stationarity distance.
  - Below 5 m/s (18 km/h), consecutive 20 ms samples are closer than 0.8λ, so they are correlated in Lee's sense. At true hover there is no spatial averaging at all.
- Sun explicitly says the window for AG "has to be reconsidered" because of LOS/Rician fading — [Sun 2015](https://scholarcommons.sc.edu/etd/3655) Sec. 3.5.
- Cui used a 40-wavelength window in an AG measurement, which supports transferring the rule to AG — [Cui 2019](https://doi.org/10.1109/LAWP.2019.2930547).

**F6. Speed 29-161 km/h ("small-UAV limit 161 km/h quoted by Khawaja"; "rotorcraft speeds of 8-20 m/s")**
- Correctly quoted. However, 161 km/h is the FAA rule for small UAVs "weighing less than 55 pounds (25 kg)", a regulatory cap, not a measured value — [Khawaja 2018](https://arxiv.org/abs/1801.01656).
- Profile 1 extends to Tlili's close-range class (25-150 kg), where this rule does not apply. That is scope overreach for heavier UAVs (inference from the quoted rule).

**F7. Antennas: "two, three and four antennas (Khawaja Table III)"; "omni suits a manoeuvring UAV"; "under the fuselage or the wings"; "1.2 m apart with more than 30 dB"**
- All supported verbatim (l.105, l.130, l.917, Table III) — [Khawaja 2018](https://arxiv.org/abs/1801.01656).
- Caveat: the ">30 dB" example includes "the polarization mismatch that occurs during the aircraft maneuver" — [Khawaja 2018](https://arxiv.org/abs/1801.01656).

**F8. Alouini & Goldsmith 1999 (LITERATURE.md [5])**
- Accurate. LITERATURE.md itself notes "Independent branches only (footnote 2)". The correlated case is correctly handed to W07 — [Alouini 1999](https://doi.org/10.1109/26.789668).
- The ranking document still lists the Simon & Alouini book as "not read". The PHY-validation formulas actually rest on P05, which was read (consistency point for the report).

**F9. Ramírez-Espinosa 2019 (LITERATURE.md [16])**
- Accurate: the model of PHY validation V5 (non-central quadratic form, exponential correlation) is Sec. V of the paper — [Ramírez-Espinosa 2019](https://doi.org/10.1109/TVT.2019.2916725).
- LITERATURE.md gives 68(7) without pages; the pages are 6734-6746.
- The paper assumes "perfect symbol synchronization and channel estimation", which matches the project's ideal-receiver validation but not the v7 real receiver.

**F10. ITU-R P.838-3 (ranking doc; LITERATURE.md)**
- Values are correct for 2.5 GHz (kH 0.0001321, αH 1.1209, kV 0.0001464, αV 1.0085), giving 0.023 dB/km at 100 mm/h.
- At 2.4 GHz the value is 0.020 dB/km (derived from eqs. 2-3). This is about 0.2 dB over 10 km, so the conclusion stands — [ITU-R P.838-3](https://www.itu.int/rec/R-REC-P.838-3-200503-I/en).

**F11. Existing short notes (scratchpad src_notes_03/04/04_05/06): corrections**
- src_notes_03 says "Sun ... S-3B max roll 26.9 deg". Wrong as a campaign maximum: 26.9° is the FT11 example event (dissertation Sec. 5.3.1). The campaign maximum is 58.3° (Part IV Sec. II; Table II), and the FT5 example spans 10.4-24.9° — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884); [Sun 2015](https://scholarcommons.sc.edu/etd/3655).
- src_notes_06 says the RP directional antenna "is a down-tilted cellular sector, not pointed at the UAV". Wrong. The text says it is "a 0 tilt configuration ... the axis of the main lobe follows the direction of the 15 m height flight" — [Rodríguez-Piñeiro 2020](https://arxiv.org/abs/2007.11502).
- The same note says "K was 2.4-10 dB LOWER" with the directional antenna. That holds only for Environment I, where the actual range is 0.41-10.28 dB (60 m: 11.64 vs 11.23).
  - In Environment II the directional K is higher at 25, 45, 60 and 75 m (+1.1 to +2.7 dB) and lower elsewhere (down to −4.5 dB).
  - The published version is IEEE TAP 69(2), 2021, not 2020 — [Rodríguez-Piñeiro 2020](https://arxiv.org/abs/2007.11502).
- src_notes_04 Banagar "<10 deg ... not verified": now verified in the text ("less than 10°") — [Banagar 2020](https://arxiv.org/abs/2004.02771).
- src_notes_04 Gomez-Ponce omits that the hovering Tx antenna was only "1.8 meters from the ground" at about 12 m range. It is a near-ground hover, not a flight-altitude one — [Gomez-Ponce 2021](https://arxiv.org/abs/2103.09135).

**F12. v7 plan items that cite these sources (v7_plan.md)**
- "shadowing on when roll > 5 deg (Sun's criterion), depth from Sun's table": overreaches.
  - The 5° figure is one of three event-detection thresholds. The others are |heading − azimuth| > 30° and a ≥ 5 dB excess. All three are "engineering judgements" — [Sun 2015](https://scholarcommons.sc.edu/etd/3655) footnote 10.
  - Table II maps the event's maximum roll to the event's median loss. It is not an instantaneous depth(roll) curve, and it is fitted only for 16.1-58.3° — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884).
- "monopole elevation pattern (Cui E-plane)": Cui's E-plane patterns are figures at 4 GHz only. The UAV antenna there is an "RM-WHF" wideband antenna; the λ/4 monopole is on the ground — [Cui 2019](https://doi.org/10.1109/LAWP.2019.2930547).
- "polarization tilt loss 20log10(cos roll)": no source in this set states the cos law (UNVERIFIED here). Khawaja and Simunek only say that polarisation mismatch occurs during maneuvers and high roll.

### Inferences
- The shadowing threat as built is "a constant, deep attenuation on one antenna". Per the sources it should look like this:
  - a slow ramp (cubic shape over 4-72 s at S-3B speeds);
  - a median depth of about 10-25 dB;
  - near-Rayleigh fading on that branch;
  - lower correlation with the other antennas.
- A 30-40 dB constant level is therefore harsher than measured in depth but easier to detect in its statistics, because a near-Rayleigh shadowed branch fluctuates more.
- Both ρ = 0.3 and the shadowing-K issue affect the diversity gain the system reports. ρ = 0.3 is optimistic for diversity if the diffuse correlation on a small airframe is high.

### Gaps
- No source here gives the diffuse-component spatial correlation for antennas on a small UAV at 2.4 GHz.
- No source gives the instantaneous roll-to-loss mapping (only the per-event maximum roll).

---

## Q3. Unused content that could fix an open weakness or support v7 (hover, turns and roll-driven shadowing, directional GCS antenna and K, non-stationarity, antenna placement)

### Takeaway
The library now contains enough measured or analytic material to drive several v7 items from sources rather than assumptions:
- a full time-domain shadowing generator (Sun eqs. 2, 4-8, depth vs roll, durations, K ≈ 0 dB fading);
- hover statistics (Khawaja: fades can last seconds to minutes; Gomez-Ponce: 0.48 dB hover jitter; Aoki: no fading at 0.3 m/s; Banagar: wobble below 10° gives coherence time of infinity, 12.3 or 6.7 ms at 2.4 GHz);
- 2.5 GHz evidence that the GCS antenna type changes K in both directions (RP), and that a tracked narrow beam suppresses multipath (Welling via Sun);
- line-of-sight Doppler and non-Jakes spectra (Lyu);
- stationarity distances (Sun 15 m, Saboor CMD).

### Cited Findings
**Roll-driven shadowing (v7 manoeuvres)**
- Time model: L_S(t) = S·f(t) − 20log10 a(t). S is per event (Gaussian, or from roll via eq. 2); f is a cubic through (0,0), (0.5,1), (1,0); a(t) is Rician with K ≤ 0 dB.
  - Start and stop are at 5 dB; multiple non-overlapping events are allowed — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884) eqs. 2-8; [Sun 2015](https://scholarcommons.sc.edu/etd/3655) Sec. 5.3.3 steps 1-8.
- Geometry gate: shadowing needs a large roll and the heading to differ from the azimuth to the GS ("not only does the roll angle have to be large enough, but the aircraft heading must also be different from the azimuth angle") — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884) Sec. III.
- "If detailed geometric information for the flight to be simulated is available, then a modified version of our algorithm must be used, in which shadowing depth S and duration D both depend upon roll and heading angles" — [Sun 2015](https://scholarcommons.sc.edu/etd/3655) Sec. 5.3.3.
- Measured turn and roll magnitudes available:
  - S-3B: roll up to 58.3°; example events 10.4-24.9° and 26.9° at about 100 m/s — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884); [Sun 2015](https://scholarcommons.sc.edu/etd/3655).
  - Meng & Lee: about 24° roll gives up to 28 dB at 5.7 GHz (via Part IV) — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884).
  - Lyu: a 300 m radius circle at 27 m/s — [Lyu 2024](https://doi.org/10.3390/drones8090492). Derived coordinated-turn bank = atan(v²/(gR)) = 13.9°, turn rate 5.2°/s.
- Polarisation during manoeuvres:
  - Simunek discarded data with roll or pitch above 10° because of "large polarization or antenna pattern losses ... as well as partial shadowing" — [Simunek 2011](https://www.radioeng.cz/fulltexts/2011/11_03_561_568.pdf).
  - Khawaja attributes part of the >30 dB example to "polarization mismatch" — [Khawaja 2018](https://arxiv.org/abs/1801.01656).
  - Aoki: horizontal vs vertical dipole installation moved K from about 0 dB to 4.94 dB in a complex environment — [Aoki 2025](https://doi.org/10.3390/drones9020086).

**Antenna placement and diversity (profile 3, 4 antennas)**
- Diversity gain under shadowing was up to 16 dB (≤ 1.8 m spacing) and up to 20 dB at L-band in FT11.
- Recommended placements: "e.g., at the end of two wings or one under the cockpit and the other under the tail or on the top" — [Sun 2015](https://scholarcommons.sc.edu/etd/3655) Sec. 5.3.1; [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884).
- Khawaja: placement should make "airframe shadowing on one antenna ... unlikely to occur at the same time as shadowing on the other(s)" — [Khawaja 2018](https://arxiv.org/abs/1801.01656).
- Ground-site diversity is "almost useless" against airframe shadowing; two GS antennas 5.55 m and 6.46 m apart gave no significant gain — [Sun 2015](https://scholarcommons.sc.edu/etd/3655); [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884).
  - This is relevant to v7 step 4: GCS antenna gain and diversity do not remove shadowing.

**Hover (v7 0-29 km/h)**
- Khawaja (l.51): deep fades "may last several seconds or even minutes ... interleaving or averaging would not be effective" — [Khawaja 2018](https://arxiv.org/abs/1801.01656).
- Gomez-Ponce: hover LOS-bin power std 0.48 dB vs 0.08 dB static, at 3.5 GHz, 12 m, Tx 1.8 m above ground — [Gomez-Ponce 2021](https://arxiv.org/abs/2103.09135).
- Aoki (0.3 m/s, 2.5 GHz): wind-driven attitude changes produce "slight" fluctuation, "drastic changes such as fading are not expected" — [Aoki 2025](https://doi.org/10.3390/drones9020086).
- Banagar: wobble below 10°. At 2.4 GHz, TC = ∞ / 12.26 / 6.74 ms for 5 / 7 / 10° (analytic, aD 40 cm, 5-25 Hz wobble) — [Banagar 2020](https://arxiv.org/abs/2004.02771).
- Lyu FS1 slow vertical descent at 1.2 m/s: maximum Doppler 10.8 Hz, first-tap K 27.58 dB — [Lyu 2024](https://doi.org/10.3390/drones8090492).
- Cui: vertical flights 0-24 m of a 4.7 kg hexacopter. The altitude-dependent PL and the LOS/NLOS switch at 11 m behind a 15 m building — [Cui 2019](https://doi.org/10.1109/LAWP.2019.2930547).

**Directional or tracked GCS antenna and K (v7 step 4)**
- RP, 2.5 GHz, ground-to-UAV direction, 0-tilt 12 dBi sector vs de-embedded omni: K lower in Env I by 0.4-10.3 dB; in Env II mixed, −4.5 to +2.7 dB.
  - RMS Doppler spread higher with the sector (log10 Hz 0.99-1.40 vs 0.50-0.86 in Env I).
  - "can influence the time and frequency coherence of the channel" — [Rodríguez-Piñeiro 2020](https://arxiv.org/abs/2007.11502).
- A tracked, very-high-gain narrow beam: "multipath was suppressed", K 7-24 dB at 2.3 GHz (Welling et al. via Sun Sec. 2.2) — [Sun 2015](https://scholarcommons.sc.edu/etd/3655).
- NASA ground sites used untracked sectors of 5.1-6.1 dBi with 60/120° and 35/180° beamwidths, and all shadowing events were in the main beam — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884).

**Non-stationarity and local mean**
- AG stationarity distance ≈ 15 m (250λ at C-band; 15 m used conservatively at L-band) — [Sun 2015](https://scholarcommons.sc.edu/etd/3655).
- Saboor: K estimated per CMD-defined quasi-stationary window, fitted K(h) = 5.414 ln h − 6.639 — [Saboor 2025](https://arxiv.org/abs/2510.23465).
- Simunek separates scales: 40λ-class averaging for slow fading vs 4000λ (600 m) for the very slow excess loss — [Simunek 2011](https://www.radioeng.cz/fulltexts/2011/11_03_561_568.pdf).
  - This is relevant to separating "path loss" from fading in the alarm.

**Real receiver (v7 step 1)**
- LOS Doppler shift of about 201 Hz at 27 m/s in steady flight, and −152..+89 Hz in the 300 m circle — [Lyu 2024](https://doi.org/10.3390/drones8090492).
- A common Doppler across MPCs "should be well mitigated by frequency synchronization" — [Khawaja 2018](https://arxiv.org/abs/1801.01656).
- "Bell"-type Doppler spectrum for the first two taps rather than Jakes — [Lyu 2024](https://doi.org/10.3390/drones8090492).
- W07 and Alouini assume perfect CSI, so they bound the real receiver from above — [Ramírez-Espinosa 2019](https://doi.org/10.1109/TVT.2019.2916725); [Alouini 1999](https://doi.org/10.1109/26.789668).

**Analytic check of the shadowing threat**
- Alouini covers independent non-identical branches (one branch at a lower mean SNR and lower K) and a time-shared shadowed/unshadowed pdf (eqs. 12-13) — [Alouini 1999](https://doi.org/10.1109/26.789668).
- W07 allows a different Ki per branch with correlation — [Ramírez-Espinosa 2019](https://doi.org/10.1109/TVT.2019.2916725).
- Together they give closed-form BER and outage for "one antenna shadowed, K ≈ 0 dB on it" against which the simulated threat can be validated.

**Path-loss threat realism**
- Cui: NLOS excess depends on UAV altitude (eq. 4 slopes) — [Cui 2019](https://doi.org/10.1109/LAWP.2019.2930547).
- Simunek: urban excess loss is set by elevation angle, not distance, and moving the GCS away from the nearest building gains about 5 dB — [Simunek 2011](https://www.radioeng.cz/fulltexts/2011/11_03_561_568.pdf).

### Inferences
- With the 20 ms channel clock of v6, "every frame an independent fade at any Doppler" (D72) is false at hover. Below about 5 m/s the per-cycle displacement is under 0.8λ.
  - Khawaja, Aoki and Gomez-Ponce all indicate a quasi-static channel with sub-dB jitter.
  - A deep fade on one antenna can persist for seconds, so it would mimic shadowing. This is exactly the confusion the v6 temporal fusion tries to resolve (temporal_evidence.m "a deep fade on one antenna looks like a hidden antenna").
  - The hover regime therefore needs its own validation of the gap_w, weak_w and drop_w evidence.
- Lowering K on a shadowed branch (Sun) would add a detectable signature, more fading on the weak antenna, distinct from a constant-loss antenna fault.
- From the RP data, a GCS sector that is not pointed at the UAV can either raise or lower K. Only a tracked narrow beam is reported to suppress multipath (Welling via Sun). A "directional GCS raises K" assumption is source-backed only for tracked beams.

### Gaps
- No measured hover K-factor or hover fade duration at 2.4 GHz.
  - Gomez-Ponce gives power std only (3.5 GHz).
  - Aoki deliberately avoided hover because K is not estimable there.
- No measured bank angles for small fixed-wing UAVs or multirotors. Lyu's 13.9° is derived from the trajectory, not measured.
- The project's sum-of-sinusoids Doppler spectrum shape (Jakes or otherwise) was not checked in code (UNVERIFIED).

---

## Q4. Important cited papers that should be in the library, and whether they are freely downloadable

### Takeaway
I downloaded four open-access PDFs into the library: Lyu 2024, Aoki 2025, Banagar 2020 and Saboor 2025.

The Matolak-Sun Part I-III journal papers, the Sun/Matolak shadowing conference papers, Meng & Lee 2012, Simunek 2013 and Simunek 2012 are paywalled. Adi's Afeka IEEE Xplore access (used for Part IV and Lee) should cover the IEEE ones.

One free NASA report covers the over-sea part of Part I.

### Cited Findings
**Downloaded and saved in folder L (names checked absent first; no existing file touched)**
1. V7_Lyu2024_FixedWing_A2G_TDL_27GHz.pdf, 5.1 MB, from the MDPI resource CDN (mdpi-res.com). mdpi.com itself returned 403 to the downloader — [Lyu 2024](https://doi.org/10.3390/drones8090492).
2. V7_Aoki2025_Rician_K_LowAltitude_UAV_25GHz.pdf, 5.5 MB, MDPI — [Aoki 2025](https://doi.org/10.3390/drones9020086).
3. V7_Banagar2020_UAV_Wobbling_A2G_Coherence.pdf, 0.5 MB, arXiv v2 — [Banagar 2020](https://arxiv.org/abs/2004.02771).
4. V7_Saboor2025_TrajectoryAware_A2G_MaMIMO_261GHz.pdf, 4.1 MB, arXiv — [Saboor 2025](https://arxiv.org/abs/2510.23465).

**Free but not downloaded (optional)**
- Matolak & Sun, "AG Channel Measurement and Modeling Results for Over-Sea Conditions", NASA/CR-2014-216674, NTRS PDF: https://ntrs.nasa.gov/api/citations/20140010366/downloads/20140010366.pdf. It covers path loss, RMS delay spread and K over sea, i.e. the measurement basis of Part I — [NTRS](https://ntrs.nasa.gov/citations/20140010366).
- Khawaja, Ozdemir, Erden, Guvenc, Matolak, "Ultra-Wideband Air-to-Ground Propagation Channel Characterization in an Open Area", arXiv:1906.04013 (IEEE TAES 56(6):4533-4555, 2020, doi 10.1109/TAES.2020.3003104).
  - Lyu cites it as analysing "propagation characteristics at different flight attitudes" for LoS/OLoS (attitude content UNVERIFIED) — [Lyu 2024](https://doi.org/10.3390/drones8090492).
  - Possibly useful for v7 attitude modelling.
- Matolak/USC Scholar Commons lists Part I as a "Postprint version" but offers no PDF download — [USC record](https://scholarcommons.sc.edu/elct_facpub/319).

### Inferences
- Priority for Adi's manual download:
  1. Simunek 2013 (the primary source of K = −5 dB).
  2. Matolak-Sun Part I and III (SD, K and correlation details per environment).
  3. Matolak et al. EuCAP 2017 and Sun-Matolak ICNS 2015 (shadowing statistics, possibly roll time series).
  4. Meng & Lee 2012 (roll vs loss at 5.7 GHz with time series).

### Gaps
- I did not attempt to bypass any paywall. Freeness of the items below is UNVERIFIED beyond the USC page check for Part I.

#### COULD NOT DOWNLOAD (paywalled or not attempted; for Adi via Afeka)
- D. W. Matolak, R. Sun, "Air-Ground Channel Characterization for Unmanned Aircraft Systems—Part I: Methods, Measurements, and Models for Over-Water Settings", IEEE TVT 66(1):26-44, 2017. DOI 10.1109/TVT.2016.2530306. https://doi.org/10.1109/TVT.2016.2530306
- R. Sun, D. W. Matolak, "... Part II: Hilly and Mountainous Settings", IEEE TVT 66(3):1913-1925, 2017. DOI 10.1109/TVT.2016.2585504. https://doi.org/10.1109/TVT.2016.2585504
- D. W. Matolak, R. Sun, "... Part III: The Suburban and Near-Urban Environments", IEEE TVT 66(8):6607-6618, 2017. DOI 10.1109/TVT.2017.2659651. https://doi.org/10.1109/TVT.2017.2659651
- R. Sun, D. W. Matolak, "Initial results for airframe shadowing in L- and C-band air-ground channels", ICNS 2015. DOI 10.1109/ICNSURV.2015.7121352. https://doi.org/10.1109/ICNSURV.2015.7121352
- D. W. Matolak, R. Sun, H. Jamal, W. Rayess, "L- and C-band airframe shadowing measurements and statistics for a medium-sized aircraft", EuCAP 2017, pp. 1429-1433. DOI 10.23919/EuCAP.2017.7928054. https://doi.org/10.23919/EuCAP.2017.7928054
- Y. S. Meng, Y. H. Lee, "Study of shadowing effect by aircraft maneuvering for air-to-ground communication", AEU Int. J. Electron. Commun. 66(1):7-11, 2012 (online 2011). DOI 10.1016/j.aeue.2011.04.006. https://doi.org/10.1016/j.aeue.2011.04.006
- M. Simunek, F. P. Fontán, P. Pechac, "The UAV Low Elevation Propagation Channel in Urban Areas: Statistical Analysis and Time-Series Generator", IEEE TAP 61(7):3850-3858, 2013. DOI 10.1109/TAP.2013.2256098. https://doi.org/10.1109/TAP.2013.2256098
- M. Simunek, P. Pechac, F. Pérez-Fontán, "Space diversity analysis for low elevation links in urban areas", EuCAP 2012, pp. 1165-1168. DOI 10.1109/EuCAP.2012.6206323. https://doi.org/10.1109/EuCAP.2012.6206323
- K. Welling, R. Dye, M. D. Rice, "Narrowband channel model for aeronautical telemetry", IEEE TAES 36(4):1371-1376, 2000 (K 7-24 dB at 2.3 GHz with a tracking antenna; cited from Sun's review; DOI not looked up)
- M. Badi, J. Wensowitch, D. Rajan, J. Camp, "Experimentally Analyzing Diverse Antenna Placements and Orientations for UAV Communications", IEEE TVT 69(12):14989-15004, 2020. DOI 10.1109/TVT.2020.3031872. https://doi.org/10.1109/TVT.2020.3031872
- Z. Cui et al., AWPL 2019 (only a text extract exists; the PDF is not in folder L). DOI 10.1109/LAWP.2019.2930547. https://doi.org/10.1109/LAWP.2019.2930547

---

## Q5. Relevance verdicts and summary

### Takeaway
- CORE: the Sun dissertation, Sun Part IV, the Khawaja survey and Cui 2019 (for the threat caps and channel ranges), and Alouini (for PHY validation).
- SUPPORTING: Lee 1985, W07, RP 2020, and the new Lyu, Aoki, Banagar and Saboor.
- MARGINAL: Gomez-Ponce, Simunek 2011 and P.838-3.

### Cited Findings (one line each; bases as cited above)
- **Sun 2015 dissertation — CORE.** The only measured airframe-shadowing statistics with roll, durations, K-drop, correlation and SD. Quality: inconsistent maxima (40 / 47.8) and speeds (60-100 vs 70-120 m/s) across texts; medium aircraft only — [Sun 2015](https://scholarcommons.sc.edu/etd/3655).
- **Sun-Matolak-Rayess 2017 Part IV — CORE.** The peer-reviewed form of the shadowing model (Table II, eqs. 2-8). Quality: abstract "over 35 dB" vs conclusion "47 dB"; 58 events counted as 209 receiver-events; figure-only parameters — [Sun 2017](https://doi.org/10.1109/TVT.2017.2677884).
- **Khawaja 2018/2019 — CORE.** Backs the K range, speeds, antenna counts and placement, and shadowing summary, plus the hover non-stationarity warning. Quality: arXiv v1 in library vs cited COMST; Table VI row mapping ambiguous; trees K 2-10 (text) vs 2-5 (table) — [Khawaja 2018](https://arxiv.org/abs/1801.01656).
- **Cui 2019 — CORE (path-loss cap) with caveats.** A measured NLOS excess and maximum SF for a small UAV between 1 and 4 GHz, plus a 40λ window in AG. Quality: "21.9 dB" is derived from the intercepts and holds at h ≈ 0 only; PDF missing from the library — [Cui 2019](https://doi.org/10.1109/LAWP.2019.2930547).
- **Alouini 1999 — CORE (validation theory).** The MGF/Craig BER basis of PHY validation. Independent branches only — [Alouini 1999](https://doi.org/10.1109/26.789668).
- **Lee 1985 — SUPPORTING.** The basis of the local-mean window. Quality: Rayleigh, terrestrial, spatial sampling; Sun says it must be reconsidered for AG — [Lee 1985](https://doi.org/10.1109/T-VT.1985.24030).
- **Ramírez-Espinosa 2019 — SUPPORTING.** Correlated non-identical Rician MRC (validation V5). Perfect CSI — [Ramírez-Espinosa 2019](https://doi.org/10.1109/TVT.2019.2916725).
- **Rodríguez-Piñeiro 2020/21 — SUPPORTING (v7 GCS antenna).** Measured omni vs 0-tilt sector K and Doppler at 2.5 GHz in the ground-to-UAV direction. Quality: arXiv v1; the published TAP version may differ — [Rodríguez-Piñeiro 2020](https://arxiv.org/abs/2007.11502).
- **Lyu 2024 — SUPPORTING (v7 turns, Doppler, receiver).** 2.7 GHz fixed-wing VTOL: circle kinematics, LOS Doppler, Bell spectrum, high K in slow descent. Quality: no roll data; Table 1 vs text altitude conflict; wideband per-tap K — [Lyu 2024](https://doi.org/10.3390/drones8090492).
- **Aoki 2025 (new) — SUPPORTING.** Small UAV at 2.5 GHz: K about 0-5 dB in a complex environment, antenna installation matters, hover gives no fading. Quality: garbled text layer; simple-environment values in figures only — [Aoki 2025](https://doi.org/10.3390/drones9020086).
- **Banagar 2020 (new) — SUPPORTING (analytic hover).** Wobble below 10° and coherence times at 2.4 GHz. Quality: model, not measurement; parameter-dependent "ballpark" — [Banagar 2020](https://arxiv.org/abs/2004.02771).
- **Saboor 2025 (new) — SUPPORTING.** 2.61 GHz K vs height fit (5.8-15.4 dB over 10-59 m) and measured non-stationarity. Quality: only skimmed; the UAV transmits to a ground array — [Saboor 2025](https://arxiv.org/abs/2510.23465).
- **Gomez-Ponce 2021 — MARGINAL.** One hover-vs-pole comparison (0.48 vs 0.08 dB) at 3.5 GHz with the Tx 1.8 m above ground. Quality: workshop paper, no Doppler, single scenario — [Gomez-Ponce 2021](https://arxiv.org/abs/2103.09135).
- **Simunek 2011 — MARGINAL.** Urban GCS excess loss vs elevation at 2 GHz, the attitude-filter rationale, 4000λ averaging. Quality: excess-loss magnitudes in figures only; an airship, not a UAV — [Simunek 2011](https://www.radioeng.cz/fulltexts/2011/11_03_561_568.pdf).
- **ITU-R P.838-3 — MARGINAL.** Shows rain at 2.4 GHz is negligible (0.020 dB/km at 100 mm/h). Values correct; beware the extraction misalignment — [ITU-R P.838-3](https://www.itu.int/rec/R-REC-P.838-3-200503-I/en).

### Inferences
- The highest-value fixes the sources support:
  1. Re-derive the shadowing level as the median S, plus K ≤ 0 dB on the shadowed branch, plus a shape over time.
  2. Re-source ρ, or flag it.
  3. Restate 22 dB as "UAV near ground behind a building".
  4. Treat hover as quasi-static (Lee windows and independent-fade assumptions fail there).

### Gaps
- Verdicts for Saboor and Aoki rest on partial reads (skim, garbled text layer).

### Summary table

| Source | Verdict | What it backs (project) | Issues found |
|---|---|---|---|
| Sun 2015 dissertation | CORE | Shadowing ≤ 40 dB, ~30 s events; aircraft diversity helps, GS diversity useless; K L ~13 / C ~29 dB; SD 15 m | 40 dB is a peak with fading; median 10.8/15.5 dB; K on the shadowed branch drops to ≈ 0 to −20 dB (not modelled); S-3B at 60-120 m/s, not a small UAV; text inconsistencies |
| Sun-Matolak-Rayess 2017 Part IV | CORE | Shadowing model (depth vs roll, durations, eqs. 2-8) for v7 manoeuvres | Abstract 35 vs conclusion 47 dB; Table II uses per-event max roll (16.1-58.3°), not instantaneous; "roll > 5°" is a detection threshold; old note's "max roll 26.9°" is wrong (58.3°) |
| Lee 1985 | SUPPORTING | Local mean over 20-40λ, N ≥ 36 (temporal fusion) | Rayleigh, spatial; at 161 km/h 20-40λ = 2.8-5.6 cycles; below 5 m/s samples are correlated; hover breaks it; Sun: reconsider for AG |
| Cui 2019 | CORE (with caveats) | Path loss cap 22 dB; 40λ window in AG | 21.9 dB is derived (62.41 − 40.55) and valid only at h ≈ 0; 22.41 dB is a peak SF deviation; PDF not in library; E-plane patterns at 4 GHz only |
| Khawaja 2018 (arXiv) | CORE | K −5..20 (Table VI); 161 km/h; 2/3/4 antennas; omni, under fuselage/wings; >35 dB shadowing; hover non-stationarity | ρ = 0.3 not in the text ("similar angles" is about Doppler); 161 km/h is the FAA < 25 kg rule; −5 dB secondary (Simunek 2013); trees 2-10 vs 2-5; "minimal for small rotorcraft" unused |
| Alouini & Goldsmith 1999 | CORE (validation) | MGF BER, MRC independent branches, PHY validation V1-V4 | Independent only (correctly noted); time-shared shadowing pdf unused |
| Ramírez-Espinosa 2019 | SUPPORTING | Correlated Rician MRC, validation V5 | Perfect CSI; pages 6734-6746 missing in LITERATURE.md |
| ITU-R P.838-3 | MARGINAL | Rain negligible at 2.4 GHz | Values correct (2.5 GHz row); text extract shifts the Table 5 labels; 2.4 GHz gives 0.020 dB/km |
| Rodríguez-Piñeiro 2020/21 | SUPPORTING | v7 GCS antenna effect on K and Doppler at 2.5 GHz | Old note wrong: 0 tilt along the route (not down-tilted); Env I −0.4..−10.3 dB, Env II mixed ±; published TAP 2021 |
| Gomez-Ponce 2021 | MARGINAL | Hover adds ~0.5 dB power jitter | 3.5 GHz, 12 m range, Tx 1.8 m above ground; single test; no Doppler |
| Simunek 2011 | MARGINAL | Urban GCS excess loss vs elevation; roll/pitch > 10° to polarisation/pattern loss | Magnitudes figure-only; airship; 2 GHz |
| Lyu 2024 (downloaded) | SUPPORTING | v7 turn kinematics (300 m, 27 m/s → 13.9° derived), LOS Doppler 201 Hz, Bell spectrum, slow-descent K 27.6 dB | No roll data; per-tap wideband K; Table 1 700 m vs text 800 m |
| Aoki 2025 (new, downloaded) | SUPPORTING | K at 2.5 GHz, small UAV: ~0 dB (vertical) to 4.94 dB (horizontal) in a complex environment; hover gives no fading | Garbled text layer; tethered at 0.3 m/s; S-environment K in figures only |
| Banagar 2020 (new, downloaded) | SUPPORTING | Hover wobble < 10°; TC at 2.4 GHz ∞/12.3/6.7 ms (5/7/10°) | Analytic; depends on aD = 40 cm and 5-25 Hz assumptions |
| Saboor 2025 (new, downloaded) | SUPPORTING | K(h) = 5.414 ln h − 6.639 at 2.61 GHz (5.8-15.4 dB); CMD non-stationarity | Skimmed only; UAV-to-ground-array direction |
