# Measured bank/roll angles and turn rates of small UAVs in real flight (plus hover channel numbers)

Scope note: every number below comes from a source that was actually opened and read (PDF text or full HTML), unless it is marked UNVERIFIED. "Digitised" means I pulled the plotted polyline coordinates out of the PDF's vector drawing data and calibrated them against the plot's own gridlines. The value is exact to plot resolution, but the paper's text does not state it. These notes make no design decisions.

PDFs saved to the sources folder (`...\פרוייקט גמר\מקורות`), all new names, nothing overwritten:
- `V7_Allen2007_NASA_TM_Autonomous_Soaring_UAV_Bank_Angle_Flight.pdf`
- `V7_Polle2026_DJI_Air3S_Hover_Tilt_Wind_Telemetry.pdf`
- `V7_Lin2026_UAV_Attitude_Jitter_A2G_NonStationarity_3GHz.pdf`
- `V7_Li2024_Ground_to_UAV_140GHz_Hovering_Roll.pdf`
- `V7_FahimRaouf2025_AERPAW_Curated_Aerial_Datasets_Attitude_Logs.pdf`

---

## Q1. A2G channel measurement campaigns with small UAVs: what roll/bank angles and turn rates were logged and reported?

### Takeaway
I found no A2G channel-sounding paper with a small fixed-wing UAV (<25 kg) that reports logged roll/bank angles or turn rates as numbers. AERPAW logs roll, pitch and yaw for its multirotor flights and documents this, but the dataset papers give the numbers only as figures or raw files. The only small-UAV comms or nav paper with a numeric measured roll figure is a GPS-signal-strength study on a small fixed-wing UAV, which says roll had a "60°" signal amplitude.

### Cited Findings
- **Gross, Gu, Rhudy (2016), "Fixed-Wing UAV Attitude Estimation Using Single Antenna GPS Signal Strength Measurements", Aerospace 3(2):14, doi:10.3390/aerospace3020014** (full HTML read in the browser pane; the PDF download was blocked by MDPI). Platform: "West Virginia University's (WVU's) Red Phastball Platform". The roll reference was "a Goodrich VG34® mechanical vertical gyroscope and the analog pitch and roll measurements were recorded using a micro-controller with a sampling rate of 50 Hz … The VG34® reports an absolute attitude within 0.1° of the true vertical." Results section, discussion of Figure 4 (verbatim): "considering that the signal amplitude for roll is much large than for pitch (i.e., 60° for roll vs. 20 for pitch), the relative percentage errors are comparable." It also says: "typically, the amplitude of the change in the pitch angle of a UAV is smaller than the amplitude in the change of the roll for a fixed-wing UAV doing a coordinated turn." The paper does not say whether "60°" means ±60° or 60° peak-to-peak. The extracted text gives no aircraft mass, span or airspeed. — [Gross et al. 2016](https://www.mdpi.com/2226-4310/3/2/14/htm)
- **AERPAW (Fahim Raouf et al., "Curated Wireless Datasets for Aerial Network Research", arXiv:2510.08752v2, 2026), §III-E, PDF p. 4:** "the vehicles generate vehicle information (e.g., latitude, longitude, altitude, roll, pitch, yaw, velocities, etc.), the low-level radio software (e.g., srsRAN) generates radio KPIs (e.g., RSRP, RSRQ, I/Q samples) … All these logs are time-stamped with a testbed-wide synchronized time-stamp". The autopilot is ArduPilot: "the autopilot firmware is ArduPilot [21], and the software is based on the MAVLink open protocol". On the AFAR dataset: it "facilitates the evaluation of directional antenna performance and gain variations due to UAV-body shadowing." I found no numeric roll/pitch statistics in the text. — [AERPAW curated datasets](https://arxiv.org/pdf/2510.08752)
- **AERPAW AADM dataset (arXiv:2602.16163v2, 2026):** the log fields include "Pitch, Roll, Yaw — UAV pitch, roll, and heading angles in radians". Figure 9(a) is captioned "UAV's roll, pitch, and yaw", but the text gives no numbers. The flights ran under a "configured speed limit of 10 m/s". — [AADM collection](https://arxiv.org/pdf/2602.16163)
- **Semkin et al. 2021 (28 GHz UAV measurement system, arXiv:2103.17149)** is qualitative only. It lists "changes in the yaw while maintaining nose direction and roll angles while hovering which could vary due to strong wind" as an error source. As future work it recommends "Verifying yaw and roll angles when the UAV is hovering, and pitch angles when the measurements are conducted in flight." — [Semkin et al.](https://arxiv.org/pdf/2103.17149)
- Already known, not redone: Sun/Matolak S-3B (manned) 26.9° max roll, Lyu et al. 2024, and Cheng et al. 2006. The Lyu PDF in the library (`V7_Lyu2024_FixedWing_A2G_TDL_27GHz.pdf`) has no hits for "roll", "bank" or "turn rate" (I checked with grep). `V7_Ahmed2011_UNSW_TR1113...` has no hits either. `V7_Yanmaz2013...` only mentions "tilt, roll" qualitatively.

### Inferences
- Lyu et al. 2024 flew 27 m/s on a 300 m radius circle. For a coordinated level turn, tan φ = v²/(gR) = 27²/(9.81·300) = 0.248, so φ ≈ 13.9°, and the turn rate is v/R ≈ 0.090 rad/s ≈ 5.2 deg/s. This is computed from geometry, not measured roll.
- The AERPAW raw logs (ArduPilot ATT messages) could give measured multirotor roll/pitch/yaw distributions, but that means processing the dataset files, not quoting a paper.

### Gaps
- I found no small fixed-wing A2G channel-sounding paper with a reported roll/bank time series or statistics. The Lyu et al. 2.7 GHz fixed-wing work and the "High altitude A2G channel for fixed-wing UAV aerial base stations" paper came up only as search-result titles (ResearchGate). I did not read them, so whether they report roll is UNVERIFIED.
- Gross et al. 2016: aircraft mass, span and speed are not in the text I extracted. The usual Phastball figures (about 11 kg, about 30 m/s) are from my memory, so UNVERIFIED.

---

## Q2. Small fixed-wing flight tests (Piccolo/Pixhawk/ArduPlane/research autopilots): bank angles actually flown in loiter/orbit/turns, and roll rates

### Takeaway
The best measured source is NASA TM-2007-214611 (Allen & Lin), Cloud Swift, 6.8 kg, Piccolo Plus autopilot. Its Figure 12 plots the measured bank angle and the body pitch and yaw rates. Digitised: about 0° (within ±9 to 17°) in cruise; while autonomously circling, a median of about −31° and a peak of about −53°; yaw rate median about 17.5 deg/s, peak about 29 deg/s; fastest roll-in about 29 to 32 deg/s. ArduPilot's own log case study for a Skywalker X8 has the measured roll reaching only about 10° under the autopilot (limit 30°) and 65° when hand-flown.

### Cited Findings
- **Allen, M.J. & Lin, V. (2007), "Guidance and Control of an Autonomous Soaring UAV", NASA/TM-2007-214611/REV1, NASA Dryden.**
  - Airframe, printed p. 4, Fig. 1 caption: "The Cloud Swift is a modified SBXC glider (RnR Products) and has a span of 4.27 m (14 ft) and a weight of 6.8 kg (15 lb)."
  - Autopilot: "hosted on a Piccolo Plus autopilot (CloudCap Technology, Hood River, Oregon) as an outer-loop guidance module computed 20 times per second."
  - Printed p. 19 (PDF p. 23): "The bank angle, pitch rate, and yaw rate are shown in figure 12 for the section of flight shown previously in figures 10 and 11. Variations in bank angle reveal the activity of the aircraft as it attempts to stay within the thermal."
  - Caption: "Figure 12. Aircraft states during soaring flight in an average thermal."
  - Plot axes: bank ±60 deg; pitch rate and yaw rate ±40 deg/s; time 0 to 250 s; a "Soaring mode switched on" marker at t ≈ 50 s.
  - **Digitised from the vector plot data** (bank about 4,700 points, about 0.05 s spacing):
    - 0 to 50 s, before soaring mode: bank −9.4° to +17.4°, median −0.6°, 90th-percentile |bank| 7.2°. Yaw rate −3.7 to +9.1 deg/s.
    - 50 to 250 s, autonomous thermal circling: bank minimum −53.4°, median −30.7°, mean −29.0° (over 60 to 250 s), 90th-percentile |bank| 43.1°, 99th-percentile 49.4°.
    - Same window: yaw rate median −17.5 deg/s, mean −16.1 deg/s, peak −28.7 deg/s. Pitch rate peak +36.9 deg/s, 99th-percentile |q| about 32 deg/s.
    - Roll rate is not plotted. The steepest change in the bank trace, at soaring entry (t ≈ 51 s), is 32 deg/s over a 0.5 s window, 29 deg/s over 1 s and 22 deg/s over 2 s.
  - Design guidance, not measurement (printed p. 15): "1. As climb improves, flatten the circle (approximately 15-20° bank angle) 2. As climb deteriorates, steepen the circle (approximately 50° bank angle) 3. If climb remains constant, keep constant bank (approximately 25-30° bank angle)". Also: "Estimated thermal radius was limited to be greater than 40 m to prevent soaring in small diameter thermals requiring high bank angle flight".
  - [NASA NTRS 20070022339](https://ntrs.nasa.gov/citations/20070022339) ([PDF](https://ntrs.nasa.gov/api/citations/20070022339/downloads/20070022339.pdf))
- **ArduPilot Plane docs, "Log Analysis Case Study: Turn Rate Adjustment"** (real log, "X8 plane using APM code 2.73"). Verbatim:
  - Commanded: "It then goes to -30 degrees, as that is the ROLL_LIMIT_DEG you have specified."
  - Measured: "The problem is that the actual roll only goes to around -10 degrees."
  - Measured, hand-flown: "When you took manual control you rolled the plane left by 65 degrees. That compares to a maximum roll angle that you have allowed the APM to use of 30 degrees."
  - This is an official doc page, not peer-reviewed, and the aircraft was mistuned (low RLL2SRV_P). — [ArduPilot case study](https://ardupilot.org/plane/docs/case-study-turn-rate.html)
- **Gross et al. 2016** (see Q1): measured roll of the WVU Red Phastball fixed-wing UAV had a "60° for roll vs. 20 for pitch" signal amplitude (mechanical vertical-gyro reference, 50 Hz). — [Gross et al. 2016](https://www.mdpi.com/2226-4310/3/2/14/htm)
- **Sources checked and rejected because they are not flight measurements:**
  - Jung & Tsiotras, IFAC 2008 (bank-to-turn control): results are from "hardware-in-the-loop simulation (HILS)", and the roll command is limited to π/6. — [GaTech PDF](https://dcsl.gatech.edu/papers/ifac08.pdf)
  - Jacquier et al., EUCASS 2022: the "30 degrees roll angle constant turn" is a simulated calibration manoeuvre on "a generic nonlinear model representative of the fight dynamics of a 50 kg fixed wings" aircraft. — [EUCASS 2022](https://www.eucass.eu/component/docindexer/?task=download&id=6479)
  - Allen 2005 (NTRS 20050041655) is the simulation precursor. — [NTRS 2005](https://ntrs.nasa.gov/api/citations/20050041655/downloads/20050041655.pdf)
  - Harms et al. 2026, dynamic soaring (EasyGlider, 1.8 m span): the real flight test exists, but I did not extract bank numbers from the text. Dynamic-soaring trajectories are also not representative of a data-link UAV. — [arXiv 2512.06610](https://arxiv.org/pdf/2512.06610)

### Inferences
- Coordinated-turn check of the digitised Allen & Lin data: with body yaw rate r ≈ ψ̇·cos φ and φ ≈ 29°, r ≈ 16.1 deg/s gives ψ̇ ≈ 18.4 deg/s. Then V = g·tan φ/ψ̇ ≈ 9.81·0.554/0.321 ≈ 17 m/s (about 61 km/h), which is plausible for a 6.8 kg motor-glider while thermalling. This airspeed is my inference; the TM text I read does not state the soaring airspeed.
- Across the measured small fixed-wing data:
  - Routine autopilot cruise: about 0 to 10° (Allen 0 to 50 s; X8 under-performing autopilot).
  - Sustained autonomous circling: about 25 to 35°, median about 30° (Allen).
  - Transient peaks: about 50 to 55° autonomous (Allen −53°), about 60 to 65° hand-flown (X8 65°, Phastball "60°" amplitude).
- At the 29 to 161 km/h band edges, the formula turn rate = g·tan(φ)/v gives:
  - φ = 30°: 40.3 deg/s at 8.06 m/s; 7.3 deg/s at 44.7 m/s.
  - φ = 53°: about 92 deg/s at 8.06 m/s (physically unlikely at that speed for most airframes); 16.6 deg/s at 44.7 m/s.

  These are arithmetic, not measurements. The only measured yaw rates found are about 16 to 29 deg/s, at about 17 m/s (inferred).

### Gaps
- No small fixed-wing paper states a measured roll rate (p) numerically. The about 29 to 32 deg/s roll-in rate above is a derivative of the digitised bank trace.
- I found no small fixed-wing loiter/orbit flight log at constant radius with stated measured bank (for example from Pixhawk/ArduPlane research papers). Searches for wind-estimation and ArduPlane loiter papers returned methods papers without numeric measured bank in the text.
- I did not fetch these, because they looked paywalled or were not found as open PDFs: Edwards 2008 (AIAA autonomous soaring flight test), Andersson et al. 2012 (J. Guid. thermal centering flight tests), Daugherty & Langelaan 2014 (the PSU PDF downloaded as only 2 pages, no flight numbers extracted). Any measured bank angles they contain are UNVERIFIED.

---

## Q3. Multirotors: measured roll/pitch (tilt) in manoeuvres or wind, and yaw rates

### Takeaway
Measured multirotor tilt from flight logs:
- DJI Air 3S (724 g), hover in 0.8 to 7.6 m/s session-mean wind: 30 s window-mean roll −17.5° to +19.3°, pitch −11.0° to +14.9°. In calibration translation up to 13 m/s the tilt reached about 20 to 22°.
- A research multirotor hovering at 40 m (Lin et al. 2026): roll and pitch within ±1° in calm air, and "tens of degrees" (pitch) in wind.
- A 4 kg multirotor (Li et al. 2024): roll "approximately 2.36 degree" in hover.

I found no measured multirotor yaw rate stated as a number.

### Cited Findings
- **Polle et al. (2026), "Horizontal wind estimation from consumer-drone hover telemetry", EGUsphere preprint, doi:10.5194/egusphere-2026-5393.**
  - Aircraft: "a DJI Air 3S weighing 724 g".
  - Data and conditions: "50 hover sessions in Bremen … Session-mean wind speeds ranged from 0.8 to 7.6 m s-1, and the highest 30 s vector-mean speed was 11.5 m s-1" (p. 1). Attitude came from flight telemetry ("Pitch and roll provided the tilt measurements"), 10 Hz.
  - Preprint p. 7, lines 125 to 129: "Observed window-mean pitch angles (-11.0 to +14.9°) and roll angles (-17.5 to +19.3°) remained within the maximum calibrated tilt magnitudes (17.7 and 21.1° in pitch, 22.1 and 20.1° in roll)".
  - Calibration: "The aircraft flew at speed steps from 1 to 13 m s-1 along each body axis". Near zero: "calibration flights began at ≈1 m s-1 (1.2-2.1° tilt)".
  - Caveat: these are 30 s window means, so instantaneous peaks are larger.
  - [EGUsphere preprint](https://egusphere.copernicus.org/preprints/2026/egusphere-2026-5393/egusphere-2026-5393.pdf)
- **Lin Zehong et al. (2026), "Measurement and Analysis of the Impact of UAV Attitude Jitter on Low-Altitude A2G Channel Non-Stationarity", Journal of Signal Processing 42(1):95-108, doi:10.12466/xhcl.2026.01.009** (full text read; Chinese).
  - Journal p. 102, my translation of the Chinese: in calm conditions, "the UAV's pitch and roll angle variations were extremely small, all within ±1 degree, the attitude was very stable". In windy conditions, "to resist the wind disturbance and maintain hover, its attitude angles (especially pitch) showed violent, rapid fluctuations of up to several tens of degrees" (原文 "高达数十度").
  - Instrumentation (journal p. 99): an external 10-axis IMU recorded "pitch, roll and heading" at 60 Hz.
  - Platform: a commercial multirotor with "6 kg" payload and "59 min" endurance (model not named).
  - The paper gives no wind speed. Its future-work section mentions wind-speed classes.
  - [J. Signal Processing article](https://signal.ejournal.org.cn/en/article/doi/10.12466/xhcl.2026.01.009)
- **Li, Da et al. (2024), "Ground-to-UAV sub-Terahertz channel measurement and modeling", arXiv:2404.02663.**
  - UAV: "featured a 70 cm wheelbase and a weight of 4 kg, with 14-inch long propellers". Attitude sensors claimed: "angular accuracy of 0.1 degree".
  - PDF p. 5: "the stability of the UAV is controlled within tight bounds. Specifically, the rolling angle of the UAV is maintained at approximately 2.36 degree during operations."
  - [arXiv 2404.02663](https://arxiv.org/pdf/2404.02663)
- AERPAW (Q1) logs multirotor roll, pitch and yaw, but the papers give no numeric statistics. — [AERPAW curated datasets](https://arxiv.org/pdf/2510.08752)
- UNVERIFIED (search snippet only, source not opened): a quadcopter wind-estimation paper (Chen et al., Oklahoma State, par.nsf.gov 10558706) stating that "Roll angles and pitch angles generally have magnitudes within the range of 0 degrees and 10 degrees". The downloaded PDF text did not contain this sentence in my grep, so treat it as unconfirmed.

### Inferences
- Measured multirotor tilt is about ±1 to 2.4° in calm hover. It is about 10 to 20° (30 s means) in moderate wind (≤7.6 m/s session mean) for a sub-kg consumer drone, with transient excursions of "tens of degrees" for a heavier research multirotor in wind.

### Gaps
- No measured multirotor yaw rate (deg/s) is stated in any source read. Polle et al. explicitly masked out "periods of intentional yaw manoeuvres". Drone-racing or aggressive-flight datasets (UZH-FPV, Blackbird) were not checked.
- Lin et al. give the windy-condition tilt only qualitatively ("tens of degrees", Fig. 6(b)). I did not digitise their figure.

---

## Q4. If nothing measured exists for small UAVs, the closest measured data

### Takeaway
Measured small-UAV data does exist (Allen & Lin 2007 for fixed-wing; Polle 2026, Lin 2026 and Li 2024 for multirotors). What is missing is a small-UAV A2G channel campaign that reports roll angles numerically together with airframe shadowing. For that combination, the closest measured data is still the Sun/Matolak S-3B work, which is manned and already known.

### Cited Findings
- Closest measured fixed-wing bank angles: Allen & Lin 2007, Cloud Swift, 6.8 kg (Q2). — [NASA TM-2007-214611](https://ntrs.nasa.gov/citations/20070022339)
- Closest measured fixed-wing roll amplitude in an RF/navigation context (GPS C/N0 vs attitude): Gross et al. 2016, "60° for roll". — [Gross et al. 2016](https://www.mdpi.com/2226-4310/3/2/14/htm)
- Closest measured roll-driven antenna-gain effect on a small UAV (multirotor, hover, 3.0 to 3.1 GHz): Lin et al. 2026. Attitude jitter sweeps the line of sight across the patch-antenna null at nadir, giving more than 10 dB power fades on millisecond scales (see Hover channel numbers). — [Lin et al. 2026](https://signal.ejournal.org.cn/en/article/doi/10.12466/xhcl.2026.01.009)

### Inferences
- Allen & Lin's thermalling bank (median about 30°, peak about 53°) exceeds the 26.9° S-3B maximum. A small UAV flown autonomously in tight circles can therefore sit beyond the manned-aircraft value, though in a soaring mission rather than a comms-relay loiter.

### Gaps
- I found no measured joint (roll angle, shadowing depth) data set for a small UAV.

---

## Hover channel numbers (scope addition)

### Takeaway
Beyond the already-known Gomez-Ponce 2021, Lin et al. 2026 is the only measured hovering-multirotor channel study found that ties channel variation to logged attitude:
- Frequency 3.0 to 3.1 GHz, 100 Msps, 40 m hover.
- Calm hover: roll and pitch within ±1°, channel stationarity interval over 40 ms.
- Windy hover: tens of degrees of attitude jitter, stationarity about 1 ms, LoS fades of more than 10 dB within milliseconds.

Li et al. 2024 (140 GHz) give a hover roll of about 2.36° and a change of SNR distribution from Rician (static) to Weibull (hover). I found no measured Doppler spread (Hz), level-crossing rate or average fade duration for a hovering UAV comms link, and no measured hover position-hold sway in metres, in any source read.

### Cited Findings
- **Lin et al. 2026, J. Signal Processing 42(1):95-108** (full text, Chinese; translations mine):
  - Sounder: "operating in the 3.0~3.1 GHz band, the self-developed transceiver baseband sampling rate is set to 100 Msps, providing 10 ns theoretical [delay resolution]" (journal p. 99).
  - Burst structure: each 1-PPS trigger starts a burst of 800 consecutive periods, "total duration about 40 ms/s", capturing "800 CIR snapshots" per window. The rate inside a burst is roughly one CIR per 50 µs; I derived that from 800 snapshots in 40 ms.
  - Logging: IMU at 60 Hz; GPS at 1 Hz.
  - Airborne antenna: peak gain 3.58 dBi at 38° from boresight, with a gain null at nadir.
  - Hover altitude: 40 m.
  - Abstract (English, verbatim): "the channel stationary time as quantified using the average power delay profile (APDP) correlation method decreased sharply from over 40 ms to as low as 1 ms."
  - Conclusion (journal p. 106, translated): attitude jitter makes the LoS sweep rapidly across the antenna that has a nadir gain null, "amplifying small angle changes into power fades of more than 10 dB on a millisecond scale".
  - Coherence bandwidth at four hover positions: medians "close to 100 MHz" and "about 4 MHz", depending on position.
  - The paper reports no Doppler spread or wind speed.
  - [J. Signal Processing article](https://signal.ejournal.org.cn/en/article/doi/10.12466/xhcl.2026.01.009) ([PDF](https://signal.ejournal.org.cn/cn/article/pdf/preview/10.12466/xhcl.2026.01.009.pdf))
- **Li et al. 2024, 140 GHz ground-to-UAV:**
  - "The maximum SNR … is 10.28 dB. It is lower than the measured value in a static station (~11.1 dB)".
  - "the SNR in the stationary state adheres to a Rician distribution … the SNR characteristics of the hovering UAV channel are best described by a Weibull distribution (goodness-of-fit metric of 0.9641 for Weibull and 0.9325 for Rician)".
  - "the rolling angle of the UAV is maintained at approximately 2.36 degree".
  - [arXiv 2404.02663](https://arxiv.org/pdf/2404.02663)
- **Semkin et al. 2021, 28 GHz** (qualitative): it notes hover yaw and roll changes in strong wind. On GPS height: "it was verified that inaccuracy can be in the order of several meters and larger than in the horizontal plane." That is GPS logging error, not physical sway. — [Semkin et al.](https://arxiv.org/pdf/2103.17149)
- Theory only, no measurement: Yang, S. & Zhang, J. (arXiv:2107.06461, rotary-wing wobbling at mmWave) asserts "mechanical wobbling in millimeter scale". It derives Doppler and ACF analytically and contains no flight measurement. — [arXiv 2107.06461](https://arxiv.org/pdf/2107.06461)
- Rodríguez-Piñeiro et al. 2021 (arXiv 2007.11502) and Cai et al. 2019 (arXiv 1901.07930) report RMS Doppler spreads from LTE A2G measurements, but for UAVs moving at about 5 to 6 m/s ("the flying speed was about 5.6 m/s"), not hovering. — [Rodríguez-Piñeiro 2021](https://arxiv.org/pdf/2007.11502); [Cai 2019](https://arxiv.org/pdf/1901.07930)
- UNVERIFIED (search snippet only): a Drones 10(10):729 paper ("Wind-Corrected Payload Assessment of a Hovering Drone via Micro-Doppler Branch Separation") reportedly found a micro-Doppler peak shifting "from approximately 340 to 430 Hz" at 7 GHz with payload. This is radar blade micro-Doppler, not a comms-channel Doppler spread. — [doi:10.3390/drones10100729](https://doi.org/10.3390/drones10100729)

### Inferences
- A stationarity interval of about 1 ms in windy hover at 3 GHz implies channel-variation rates of the order of 1 kHz. That comes from attitude-driven antenna-gain modulation, not from translational Doppler, and depends on the antenna's nadir null. This is my inference; Lin et al. do not express it as a Doppler spread.

### Gaps
- No source read reports, for a hovering UAV: Doppler spread (Hz), coherence time from a correlation threshold (beyond Lin's stationarity interval), level-crossing rate or average fade duration.
- No source read reports measured hover position-hold sway in m or m/s from flight logs. Search results returned only forum posts and RTK-accuracy studies, which I did not use.

---

## What was searched (stop condition)
- **Web searches:**
  - fixed-wing A2G roll/banking/shadowing
  - Asadpour 802.11 fixed-wing roll
  - small fixed-wing measured bank in loiter/orbit
  - AERPAW roll/pitch/yaw
  - fixed-wing wind-estimation orbits
  - multicopter tilt in wind
  - NASA autonomous soaring flight tests
  - fixed-wing link vs roll angle
  - ArduPlane loiter logs
  - Skywalker X8 roll
  - Lin 2026 J. Signal Processing
  - hovering Doppler/coherence
  - hover position-hold sway
  - Yang 2023 wobble
- **Read in full text:** about 20 PDFs and pages, those cited above plus rejected ones (ROSplane 2.0, Smith & Sanfelice UCSC loiter (theory), Asadpour MAV routing (no roll numbers), Langelaan 2007 (planning), full-duplex multi-UAV (no roll), FR1/FR3 A2G (no hover Doppler numbers)).

## COULD NOT DOWNLOAD
- Gross, J.N., Gu, Y., Rhudy, M.B., "Fixed-Wing UAV Attitude Estimation Using Single Antenna GPS Signal Strength Measurements", Aerospace 2016, 3(2):14, doi:10.3390/aerospace3020014. The MDPI PDF returned "Access Denied" to curl. I read the full HTML in the browser pane instead. URL: https://www.mdpi.com/2226-4310/3/2/14
- Edwards, D.J., "Implementation details and flight test results of an autonomous soaring controller", AIAA GNC 2008, doi:10.2514/6.2008-7244 (not attempted, paywalled; UNVERIFIED content).
- Andersson, K., Kaminer, I., et al., "Thermal centering control for autonomous soaring; stability analysis and flight test results", J. Guidance, Control, and Dynamics 35(3), 2012, doi:10.2514/1.56029 (not attempted, paywalled; UNVERIFIED content).
