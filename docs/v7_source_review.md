# Sources back the method, not the severity

**Bottom line.** The core of the project rests on primary sources that were read and that hold up: the Mahalanobis unknown-threat score (Lee), the exact one-sided false-alarm bound (Thulin), the PHY-validation formulas (Alouini; Ramírez-Espinosa), Double DQN and preemptive shielding (van Hasselt; Alshiekh), the M − N + 1 diversity rule (Winters) and the "low delivery with strong energy means jamming" consistency check (Xu). The weak part is the threat-severity layer. Several of the caps, ranges and shapes that make the simulation "most severe within the sources" either come from a different source than the one cited, or they go beyond what the cited source measured:
- the 30 dB spoofer has no source at all;
- 86 % WLAN occupancy is a cabled lab case, not field data;
- exponential idle gaps are the worst fit in the field data that was cited for them;
- the 40 dB shadowing figure is a fading peak, not a sustained loss;
- ρ = 0.3 does not appear in Khawaja;
- the 30 dB antenna-fault depth rests on an unsourced capacitance.

For v7, the library now holds source-backed explanations and fixes for every open real-receiver failure:
- Doppler-faded 30 dB jamming: covariance aging, not too few training samples.
- Reactive jamming: sync on a secret sequence with a temporal projection (JASS).
- Pulsed jamming: the quiet slot falls in the jammer's off-time, so the receiver should estimate over the whole frame and keep its null between pulses.
- CFO bias: an outlier or bias effect from residual jamming, not estimator variance.
- Receiver dynamic range: AGC and ADC limits.

The library also has measured hover and bank-angle data. Of the 167 files, 70 can move to `נסרקו - לא בשימוש` (four of them are byte-identical duplicates). Ten reactive-jamming files have no usable notes and should stay until someone reads them.

Conventions. `L/` is the library folder `...\פרוייקט גמר\מקורות\`. Project diagnostics are quoted as the coordinator gave them:
- Real receiver, 30 dB Doppler-faded jamming: about 6 % / 35 % / 50 % frame failures at 29 / 100 / 161 km/h, against 0 with a static jammer channel; failed frames show CFO errors of 5–22 kHz.
- Pulsed jammer: 23 of 120 frames broken.

## Twelve project claims go further than their sources

**Threat levels.**
- *Spoofer at 30 dB.* Whitehouse gives only the *minimum* capture advantage, **0.17 dB or 1–3 dB**, both second-hand ([Whitehouse](<L/V7_Whitehouse2005_Capture_Effect_Collision_Detection_EmNetS.pdf>)). Mekdad gives **no dB value anywhere**. Its hijacker used **two Crazyradio PA modules ("similar configuration as the GCS")**, not the HackRF jammer, and the takeover worked because the link had no authentication ([Mekdad](https://arxiv.org/abs/2403.03858)). The spoofer's 30 dB is Liu's in-band jammer value carried over to a different threat.
- *Liu's 30 dB.* It is **one simulated operating point**: a 30 dBm jammer against a 0 dBm signal, both 4 MHz wide. Liu's comb jammer is **three tones at 2, 10 and 18 MHz**, which the user escapes with normalized throughput "close to one". So D70's "every usable channel jammed at once" contradicts Liu ([Liu](https://arxiv.org/abs/1710.04830)). Yuan's 30 dBm vs 0 dBm figures are *transmit* powers in a 450 m geometry, not a received JSR ([Yuan](https://doi.org/10.1049/cmu2.12257)).
- *WLAN model.*
  - The 0.27–3.2 ms frames and 5–86 % occupancy are Wollenberg's **configured lab cases on a cabled test bed** ([Wollenberg](https://doi.org/10.1145/2387238.2387289)).
  - Cheema's field capture shows only **4.6–11.5 % duty cycle**, and the **exponential idle model is the worst fit** (KS D = 0.27–0.30). A gamma model fits best (k = 0.49, mean 36 ms), with 100 ms beacons ([Cheema](https://doi.org/10.3390/electronics8091011)).
  - Neither paper gives a WLAN level relative to the desired signal.
  - ETSI EN 300 328 caps power at 20 dBm but also at **10 dBm/MHz**, which limits a 1.25 MHz signal to about 10–11 dBm e.i.r.p. ([EN 300 328 V2.2.2](https://www.etsi.org/deliver/etsi_en/300300_300399/300328/02.02.02_60/en_300328v020202p.pdf)).
  - Song's "interference grows with altitude" is about **LTE base stations**, not WLAN ([Song](https://arxiv.org/abs/2007.00905)).

**Channel.**
- *Shadowing.* The "40 dB" is a per-event maximum that includes small-scale fading. The **median sustained loss is 10.8 dB (L-band) and 15.5 dB (C-band)**, and the shadowed branch's **K drops from about 15 dB to as low as −16 dB** ([Sun 2017](https://doi.org/10.1109/TVT.2017.2677884); [Sun 2015](https://scholarcommons.sc.edu/etd/3655)). The project instead applies a constant 40 dB and keeps the normal K. The data come from one S-3B aircraft at 60–120 m/s, and Khawaja says shadowing "could be minimal" for small rotorcraft ([Khawaja](https://arxiv.org/abs/1801.01656)).
- *Receive correlation.* ρ = 0.3 is not in Khawaja. His "similar angles" sentence is about Doppler. Sun measured **0.85–0.99** amplitude correlation on the aircraft underside, about 0.6 during shadowing ([Sun 2015](https://scholarcommons.sc.edu/etd/3655)).
- *Other channel numbers.*
  - Cui's "21.9 dB" is derived (62.41 − 40.55) and holds only for a UAV at ground level ([Cui](https://doi.org/10.1109/LAWP.2019.2930547)).
  - Lee's 20–40λ local-mean rule is a spatial, Rayleigh-fading rule. At 161 km/h it spans only 2.8–5.6 cycles, and at hover there is no spatial averaging at all ([Lee](https://doi.org/10.1109/T-VT.1985.24030)).
  - 161 km/h is the **FAA rule for UAVs under 25 kg**, not a measured speed ([Khawaja](https://arxiv.org/abs/1801.01656)).

**Antenna and fault.**
- *Fault depth.* The only RF measurement of a vibrating connector shows **0.15–0.37 dB** S21 change ([Enquebecq](https://publiweb.femto-st.fr/tntnet/entries/13058/documents/author/data)). The 0.01–0.03 pF gap capacitance behind "30 dB" has no source.
- *Fault frequency.* Verbeke's 86–672 Hz are **seven free-free modal frequencies** of one hexacopter frame. They are not a continuous range and not a connector rate ([Verbeke](<L/isma2016_0797.pdf>)).
- *Antenna pattern.* F.1336's omni pattern is validated only for **8–13 dBi** gain. Badi measured **−24 / −30 dB overhead** for drone dipoles ([F.1336-5](https://www.itu.int/dms_pubrec/itu-r/rec/f/R-REC-F.1336-5-201901-I!!PDF-E.pdf); [Badi 2019](https://s2.smu.edu/~camp/pubs/badi_acm_mswim_2019.pdf)).

**Decision and detection.**
- *Shield.* Alshiekh's convergence guarantee does not extend to a DQN ([Alshiekh](https://arxiv.org/abs/1708.08611)).
- *History length.* "History 4" is Mnih's Atari frame stack, which Mnih says is robust to 3 or 5. Yuan's argument (the history must cover the jammer's memory) is the defensible basis ([Mnih](https://doi.org/10.1038/nature14236); [Yuan](https://doi.org/10.1049/cmu2.12257)).
- *Hold rule.* W03 supports holding *frequency* changes only, not power or FEC changes ([Zhao](https://arxiv.org/abs/2511.03305)).
- *Survey statistics.* Tlili's "second most common attack" is not a count. Oli & Mahalal's "high likelihood" rating is for **GPS** jamming.
- *KPI 2 score.* It is Lee's **base variant**: TNR95 of 54.5 %, against 96.4 % with both calibration techniques ([Lee](https://arxiv.org/abs/1807.03888)).
- *Hybrid detector.* Shebert's "hybrid" is a CNN → protocol-decoder cascade, not feature fusion ([Shebert](https://arxiv.org/abs/2302.03749)). The primary hybrid source, Abdullayeva, does back CNN + feature concatenation (99 % vs 94.7 % / 96.3 %). Its feature inputs, however, are **five IQ statistics on simulated GNSS jamming**, not "UAV telemetry", and its binary baseline is degenerate ([Abdullayeva](https://doi.org/10.1016/j.csa.2025.100094)).

**Corrections that strengthen claims.**
- ±25 ppm now has approved text: IEEE 802.11-2007 clauses **18.4.7.4 / 18.4.7.5**, not the draft numbering ([802.11-2007](http://web.archive.org/web/20240604215729/http://magrawal.myweb.usf.edu/dcom/Ch8_802.11-2007.pdf)).
- Riyandi's "49° at 49 km/h" is a typo. It is **60 km/h, a motorcycle about 18 m away**, not a UAV ([Riyandi](https://doi.org/10.14710/jtsiskom.6.3.2018.122-128)).
- Cite Thulin as EJS 2014 and Brown from the readable V7 copy ([Thulin](https://doi.org/10.1214/14-EJS909)).

## The v7 receiver fails on covariance age, quiet-slot timing and residual jamming

**30 dB Doppler-faded jamming is a covariance-aging problem.**
- *Training size is not the cause.* With signal-free training, the SMI loss follows Beta(n − N + 2, N − 1) whatever the interference power is. For N = 3 and n = 32 the mean loss is about **0.27 dB** ([Besson](https://arxiv.org/pdf/2102.01421)).
- *Aging is.* A null computed earlier cancels only the part of the jammer still correlated, J0(2π f_d τ) ([Truong & Heath](https://arxiv.org/pdf/1305.6151)). At 358 Hz Doppler, Rician K = 10 dB and 30 dB JNR, the residual is roughly **+12.6 dB above noise averaged over the frame (+16.8 dB at its end)**. At 29 km/h it is about −1.7 dB, and with a static jammer about −17 dB. This model is an inference from the notes, but it tracks the 0 / 6 / 35 / 50 % failure pattern.
- *Published evidence agrees.*
  - Winters-type DMI at 184 Hz with an equal-power faded interferer lost **11 dB with an error floor**; a subspace method cut that to 5 dB ([US 6,147,985](https://patents.google.com/patent/US6147985A/en)).
  - Measured 2.4 GHz MU-MIMO kept 90 % capacity for only **1.1 ms** at pedestrian speed ([Shepard](https://yecl.org/argos/pubs/Shepard-Asilomar16.pdf)).
- *Fixes the sources support.*
  - Re-estimate or track the covariance inside the frame. The residual falls about 6 dB for every halving of the use interval.
  - Widen the null. Derivative constraints need n > (p + 1)q sensors and cost about 1 dB ([Gershman](https://new.eurasip.org/Proceedings/Eusipco/1996/paper/ap_2.pdf)). With three antennas this is barely feasible.
  - Accept hardware floors as part of realism. Null depth is limited by σ²_φ + σ²_ε independent of N ([Bakr](https://www2.eecs.berkeley.edu/Pubs/TechRpts/2009/EECS-2009-1.pdf)). IQ imbalance at 20 dB IRR cannot be nulled by linear MMSE but can be by widely-linear MMSE ([Hakkarainen](https://par.nsf.gov/servlets/purl/10228888)).
- *Corollary.* The ideal-receiver reference is over-optimistic for two separate reasons: it ignores aging, and it has no hardware floor.

**Reactive jamming defeats any fixed jammer-free slot.**
- *JASS.* For each candidate start time, JASS projects the window onto the temporal complement of a **secret randomized sync sequence**, estimates the interference subspace from what is left, and nulls it. Against jammers that are on only during the sequence, at 0, 10 and 30 dB JSR, the total error rate is about **1 %**. Its limits are flat fading only and **no frequency synchronization** ([JASS](https://arxiv.org/abs/2404.05335)).
- *Alternatives that need a quiet jammer slot.* JrRx (measured decoding with jamming 20 dB stronger) and Yan both assume a jammer that is permanent, or slow to react ([Zeng](https://www.cse.msu.edu/~hzeng/papers/zeng17_cns_jamming.pdf)).
- *Randomize what the jammer could target.* Noubir proposes a **cryptographically placed** silent interval ([Noubir](https://www.cs.umb.edu/~shengbo/paper/wisec11.pdf)), and La Pan proposes a secret sync position ([La Pan](https://doi.org/10.1002/wcm.2500)). Both are unevaluated. The project's quiet slot sits at a fixed position.
- *Concealment.* The learned defence against a threshold-adaptive reactive jammer is to *lower* transmit power. The project's action set has no such action ([Sagduyu](https://arxiv.org/abs/2510.02265)).

**Pulsed jamming breaks the quiet-slot estimate, which is a documented failure mode.**
- *Failure.* If the jammer is silent while its subspace is being estimated, mitigation "fails spectacularly", with BER equal to an unmitigated receiver ([Marti 2023](https://arxiv.org/pdf/2208.01453)).
- *Whole-interval fix.* MAED / SO-MAED estimate over the **whole coherence interval**. At 20 % duty and 30 dB they come within **2–3 dB** of the jammer-free bound ([Marti 2023](https://arxiv.org/pdf/2208.01453)).
- *Null memory.* A fast-attack / slow-release null holds through the off-time ([DuPree](https://patents.google.com/patent/US5175558A/en)).
- *Blanking cost.* N0 rises by 1/(1 − bdc), about **1.55 dB at 30 % duty** ([Garcia-Pena](https://navi.ion.org/content/navi/68/1/75.full.pdf)).
- *Soft decoding.* Per-symbol variance (JSI) LLRs with interleaving give "significant improvements". Without JSI, a single average variance plus clipping is the fallback ([Baldi](https://arxiv.org/pdf/1310.0721)).
- *Interleaving limit.* The project's guardband-to-burst ratio is 70/30 ≈ 2.3, below the patent's ratio of 3 for correcting all bursts ([DuPree](https://patents.google.com/patent/US5175558A/en)).

**The CFO bias looks like outliers from residual jamming, not estimator variance.**
- *Size of the error.* At 10 dB Es/N0 the CRB spread is about **0.96 kHz for N = 32** ([Morelli & D'Amico](https://doi.org/10.1155/2007/65058)). Errors of 5–22 kHz are therefore outliers or bias.
- *Mechanism.* A temporally correlated residual adds a **power-weighted phasor** to the autocorrelation sum and steers its angle ([Rahbari](https://doi.org/10.1109/TMC.2015.2456916)). Frequency estimators also "assume ideal timing", so a disturbed timing estimate degrades them too ([Morelli & D'Amico](https://doi.org/10.1155/2007/65058)).
- *Range limits.* To cover ±120 kHz (ν = 0.12), Fitz needs N ≤ 4 and L&R N ≤ 7; M&M reaches about ±0.5 ([Bertolucci](https://doi.org/10.3390/s21092915)).
- *Fixes.*
  - An ML / FFT grid search has the lowest outlier threshold, gaining about 3 dB per doubling of N ([Morelli & D'Amico](https://doi.org/10.1155/2007/65058)).
  - Search FO bins and keep the one with the minimum channel-estimation MSE ([Rahbari](https://doi.org/10.1109/TMC.2015.2456916)).
- *Gap.* No source quantifies the bias that residual whitening adds; this has to be shown by simulation.

**Receiver dynamic range now has concrete, sourced bounds.**
- *Standard ceiling.* 802.11 OFDM at 2.4 GHz requires correct operation up to **−20 dBm per antenna**, and DSSS up to −10 dBm ([802.11-24/2043r0](https://mentor.ieee.org/802.11/dcn/24/11-24-2043-00-00bn-pdt-phy-receiver-specification.docx)).
- *SDR transceivers.*
  - AD9361 at 2.4 GHz: IIP3 **−14 dBm**, 12-bit ADC, damage at 2.5 dBm ([AD9361](https://www.rlocman.ru/i/File/2020/07/28/AD9361.pdf)).
  - LMS7002M: a −15 dBm blocker needs about 7 dB of LNA back-off, and the noise floor rises 7–8 dB ([Lime](https://www.limemicro.com/downloads/lms7002m_measurements-v1_05.pdf)).
- *C2-class chips.* They saturate at **−18 to −9 dBm** (CC2500) or 0 dBm (nRF24L01+) ([CC2500](https://www.ti.com/lit/ds/symlink/cc2500.pdf); [nRF24L01+](https://www.sparkfun.com/datasheets/Components/SMD/nRF24L01Pluss_Preliminary_Product_Specification_v1_0.pdf)).
- *Theory.* For any ADC resolution, mutual information goes to 0 as jammer power grows. Every **6.02 dB of jamming costs one ADC bit**, whatever the AGC does ([Marti 2024](https://arxiv.org/pdf/2405.05100)).
- *Measured AGC behaviour* ([Bastide](https://enac.hal.science/hal-01021721)):
  - The AGC drops about 1 dB per dB at high AWGN levels.
  - Pulsed interference barely moves it (**−0.5 dB at +27 dB**) but clips the ADC.
  - The AGC drifts about 1 dB per day with temperature, which supports drop thresholds of 2–5 dB (Kazim uses 2 dB with 7/7 detections) ([Kazim](https://arxiv.org/pdf/2602.12688)).

## Weak detection classes need evidence across cycles, and hover and banking need measured shapes

**antenna_fault (F1 0.82).**
- *Labelling (inference from the v6 code, not from a source).* Antenna-fault frames are never relabelled. At duty 0.05 and 86 Hz, about **91 % of fault-labelled frames are physically fault-free**. A 50 Hz cycle also aliases the vibration frequency (86 Hz appears as 14 Hz). Check this before adding features.
- *What the sources support.*
  - Judge branch imbalance as a *distribution* over many samples, using its mean and its std/|mean| ratio ([Willgert](https://patents.google.com/patent/US8548029B2/en)).
  - Badi shows attitude and body losses change over seconds and affect all branches ([Badi 2020](https://s2.smu.edu/~camp/pubs/badi_tvt2020.pdf)). A one-branch step inside a frame is the distinguishing fault signature.
  - CUSUM is optimal at a fixed ARL. WLCUSUM handles an unknown fault duty ([Xie 2022](https://arxiv.org/abs/2206.06777); [Xie 2021](https://arxiv.org/abs/2104.04186)).

**Benign WLAN (F1 0.70).** It is low-information per frame.
- *Field evidence.*
  - SoNIC needs a **30 s vote** to reach 82 %, and still calls WLAN a weak link 16.2 % of the time at the edge of the zone. That is the v6 confusion ([SoNIC](https://user.it.uu.se/~frehe489/publications/hermans13sonic.pdf)).
  - Grimaldi's 89–96 % holds only at INR ≥ 20 dB, with a noise-calibrated μ + 2σ threshold ([Grimaldi](https://arxiv.org/pdf/1809.10085)).
  - Xu's (PDR, signal strength) consistency check with a 99 % benign band separates jammers ([Xu](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)).
- *Illustrative CUSUM delays.* With an assumed per-cycle hit rate of 0.05 (and 0.01 on a clean link) the delay is about 3.3 s at a 20 s ARL, and about 1 s at a hit rate of 0.10 ([Xie 2022](https://arxiv.org/abs/2206.06777)).
- *Implication.* Low-occupancy WLAN is a seconds-scale decision, not a per-frame classifier problem.

**Hover (0–29 km/h).**
- *Slow deep fades.* Fades can last seconds to minutes, so averaging and interleaving fail ([Khawaja](https://arxiv.org/abs/1801.01656)).
- *Measured attitude effect.* A hovering multirotor in calm air stays within **±1°**, with stationarity above 40 ms. In wind it moves by **tens of degrees**, stationarity drops to **1 ms**, and fades exceed **10 dB on a millisecond scale** as the line of sight sweeps a nadir null ([Lin 2026](https://signal.ejournal.org.cn/en/article/doi/10.12466/xhcl.2026.01.009)).
- *Other hover evidence.*
  - At 0.3 m/s and 2.5 GHz Aoki sees no fading, and K is about 0–5 dB ([Aoki](https://doi.org/10.3390/drones9020086)).
  - Wobble below 10° gives coherence times of ∞ / 12.3 / 6.7 ms at 2.4 GHz ([Banagar](https://arxiv.org/abs/2004.02771)).
- *Model implication.* v6's "independent fade every frame" is false below about 5 m/s.

**Bank angles.**
- *Measured small fixed-wing data.*
  - Cloud Swift, 6.8 kg, Piccolo autopilot: median **−30.7°**, peak **−53.4°**, roll-in about 30°/s, yaw rate median 17.5°/s ([Allen & Lin](https://ntrs.nasa.gov/citations/20070022339)).
  - Phastball, gyro reference: roll spans **−58° to +28°**, 95th percentile |roll| 46° ([Gross](https://doi.org/10.3390/aerospace3020014)).
- *Turn-to-loss mapping.* Sun's Table II gives the event median loss against the event's *maximum* roll (16–58°). The three event criteria, including roll > 5°, are "engineering judgements", not physics ([Sun 2017](https://doi.org/10.1109/TVT.2017.2677884)).
- *Polarization.* Badi supplies the loss law: PLF(dB) = 20 log cos δ ([Badi 2019](https://s2.smu.edu/~camp/pubs/badi_acm_mswim_2019.pdf)).

**Directional GCS antenna.**
- *Effect on K.* A 0-tilt 12 dBi sector at 2.5 GHz changed K **both ways**, from −10.3 dB to +2.7 dB ([Rodríguez-Piñeiro](https://arxiv.org/abs/2007.11502)).
- *Ground diversity.* Ground-site diversity is "almost useless" against airframe shadowing ([Sun 2015](https://scholarcommons.sc.edu/etd/3655)).
- *Measured tracker error.* **5.62° / 1.51°** in azimuth / elevation ([Nugroho](https://mev.brin.go.id/mev/article/download/404/pdf)).

**Adaptive adversary templates.**
- W01's threshold-switching reactive jammer ([Sagduyu](https://arxiv.org/abs/2510.02265)).
- Yuan's comb jammer that switches pattern after a miss ([Yuan](https://doi.org/10.1049/cmu2.12257)).

## Filtering: every top-level library file, scored for this project

Scale: 10 = a modelling number, KPI method or key v7 solution rests on it and is backed. 7–9 = directly supports a used claim or a v7 solution. 4–6 = background or second-hand. 1–3 = not useful, duplicate, superseded or withdrawn. "HOLD" means no usable note exists, so the file was not scored and is not on the move list. Duplicates were confirmed by MD5. Action: K = keep, M = move.

| File | Score | Act | Reason |
|---|---|---|---|
| 1-s2.0-S0026271421000135-main.pdf | 5 | M | Feng 2021 SMA fretting: DC resistance only, no RF dB; cannot back the 30 dB fault depth |
| 1-s2.0-S2772918425000116-main.pdf | 7 | K | Abdullayeva 2025: primary source for CNN + feature concatenation fusion (simulated GNSS data) |
| 122.pdf | 9 | K | Bastide 2003: measured AGC/ADC response to AWGN, CW and pulses; drift; chi-square ADC detector |
| 1801.01656v1.pdf | 1 | M | Byte-identical duplicate of W08_Khawaja |
| 2007.00905v1.pdf | 4 | M | Song 2020 survey: altitude-interference claim is LTE-only |
| 20070022339.pdf | 1 | M | Byte-identical duplicate of V7_Allen2007 |
| 2387238.2387289.pdf | 9 | K | Wollenberg 2012: the actual source of 0.27–3.2 ms and 5–86 % (cabled lab cases) |
| A01_Tlili2024_AI_UAV_Security_Survey_IoT.pdf | 7 | K | UAV-GCS as primary link; platform classes for profile 1 (figure unsourced) |
| A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf | 9 | K | Jammer taxonomy, reactive definition, PDR vs SS consistency check |
| Air-Ground_Channel_Characterization_for_Unmanned_Aircraft_SystemsPart_IV_Airframe_Shadowing.pdf | 9 | K | Peer-reviewed shadowing model: depth vs roll, durations, K drop |
| Dual-Band Non-Stationary Channel Modeling for the Air-Ground Chan.pdf | 9 | K | Sun dissertation: shadowing statistics, antenna correlation, 15 m stationarity |
| Estimate_of_local_average_power_of_a_mobile_radio_signal.pdf | 7 | K | Lee 1985: local-mean window basis (Rayleigh, spatial; fails at hover) |
| F04_Nanayakkara2025_Smart_Drone_Neutralization_SDR.pdf | 2 | M | Offensive counter-drone paper; nothing used |
| F05_Yuan2021_Joint_Relay_Channel_Selection_Smart_Jammer_DRL.pdf | 7 | K | Tracking jammer, history ≥ jammer memory, switching cost (30 dBm is transmit power) |
| IEEE 802.11 Physical Layer Operation and Measurement.pdf | 1 | M | Byte-identical duplicate of V7_Keysight2017 |
| L01_Drones2026_AI_Methods_UAV_Cybersecurity_Survey.pdf | 4 | M | Generic RL-weakness survey |
| N01_Yang2025_AgentBased_AntiJamming_UAV_Survey.pdf | 7 | K | Strategy taxonomy (power = confrontation; deceit); CBF safety layer |
| N02_Grekhov2026_DQN_Resilient_Drone_Markov_Jammers.pdf | 5 | M | Unreviewed manuscript; predictive-jammer template only |
| N03_Barajas2026_Resilient_Control_Loops_Jamming.pdf | 7 | K | Recovery 0.141/2.549 s (6.0 s baseline), 3-consecutive confirmation |
| N07_Shebert2023_OpenSet_Hybrid_Classification.pdf | 7 | K | Softmax unsuitable for open set; near-OOD failure; not feature fusion |
| N12_Mekdad2024_Jamming_Hijacking_Micro_Drones.pdf | 7 | K | Tone/noise jamming and unauthenticated hijack exist; no dB |
| P01_OliMahalal2025_UAV_Security_IEEEAccess.pdf | 8 | K | KPI 7 latency class (< 10 ms) |
| P02_Papathanasiou2026_UAV_GCS_Security_ApplSci.pdf | 8 | K | Research-gap framing: close the detection-to-protocol loop |
| P03_Tariq2026_ML_DL_UAV_Threat_Defense_DiscoverAI.pdf | 8 | K | LOTO for zero-day claims; macro-F1 / PR-AUC under imbalance |
| P04_Liu2018_AntiJamming_SpectrumWaterfall_DRL.pdf | 9 | K | 30 dB single simulated point; waterfall state (comb misdescribed) |
| P05_Alouini1999_Unified_Error_Rates_Fading.pdf | 10 | K | MGF BER basis of PHY validation |
| P06_Lee2018_Mahalanobis_OOD_NeurIPS.pdf | 10 | K | KPI 2 score, tied covariance, Algorithm 2 |
| P07_Liu2008_Isolation_Forest_ICDM.pdf | 7 | K | iForest settings incl. ψ = 8192 for normal-only training |
| P08_Mnih2015_DQN_Nature.pdf | 9 | K | Replay, target network, error clipping |
| P09_vanHasselt2016_Double_DQN_AAAI.pdf | 10 | K | Double-DQN target; best-checkpoint selection |
| P11_Alshiekh2018_Safe_RL_Shielding_AAAI.pdf | 10 | K | Preemptive shield; water-tank 3-step hold = D63 |
| P12_Thulin2014_Cost_Exact_Binomial_Intervals.pdf | 3 | M | arXiv v1, superseded by the EJS copy |
| P13_Dixit2026_Secure_RF_WiFi_Drone_Swarm_Testbed.pdf | 4 | M | Protocol authentication only; PDR above 100 % |
| Spectrum_Occupancy_Measurements_and_Analysis_in_24 (1).pdf | 1 | M | Byte-identical duplicate of Cheema |
| Spectrum_Occupancy_Measurements_and_Analysis_in_24.pdf | 8 | K | Cheema 2019: field duty cycle 4.6–11.5 %, gamma idle times (corrects the model) |
| V7_Ahmed2011_UNSW_TR1113_Aerial_WSN_Links.pdf | 4 | M | Static poles, technical report; orientation ±10 dB only |
| V7_Allen2007_NASA_TM_Autonomous_Soaring_UAV_Bank_Angle_Flight.pdf | 9 | K | Best measured small fixed-wing bank angles and rates |
| V7_Amuru2015_Jamming_Bandits.pdf | 5 | M | Learning-jammer model; only abstract read |
| V7_AnalogDevices2016_AD9361_Datasheet_RevF.pdf | 7 | K | IIP3 −14 dBm, 12-bit ADC, 2.5 dBm damage |
| V7_Anritsu2025_80211be_TRx_Evaluation_FreqTolerance.pdf | 3 | M | Vendor note; ±25 ppm now from approved text |
| V7_Aoki2025_Rician_K_LowAltitude_UAV_25GHz.pdf | 7 | K | K at 2.5 GHz on a small UAV; no fading when hovering |
| V7_Arquint2025_JASS_Sync_ASIC_65nm_arXiv.pdf | 6 | M | JASS hardware feasibility; JASS paper suffices |
| V7_Badi2019_Antenna_Polarization_Elevation_Drone.pdf | 9 | K | Overhead −24/−30 dB, PLF law, body loss, branch correlation |
| V7_Badi2020_Antenna_Placements_Orientations_UAV_TVT.pdf | 9 | K | Ground-to-UAV cos² elevation model, rotation loss, 0.67λ spacing |
| V7_Bakr2009_Phase_Amplitude_Errors_Array_Null_Depth.pdf | 7 | K | Null depth limited by amplitude/phase error, independent of N |
| V7_Baldi2013_Coding_Against_Jamming_Telecommand_Links.pdf | 8 | K | JSI LLRs and interleaving against pulsed jamming on telecommand links |
| V7_Banagar2020_UAV_Wobbling_A2G_Coherence.pdf | 7 | K | Hover wobble < 10° and coherence times at 2.4 GHz |
| V7_Bertolucci2021_CCSDS_Frequency_Timing_Estimators_Sensors.pdf | 8 | K | CFO estimator range/accuracy trade-off; coarse-fine design |
| V7_Besson2021_Adaptive_Multichannel_Filters_SNR_Loss_Overview.pdf | 8 | K | RMB / MPDR / diagonal-loading losses; rules out sample support |
| V7_Brown2001_Interval_Estimation_Binomial_Proportion_StatSci.pdf | 7 | K | Wilson / Clopper–Pearson choice |
| V7_Castaneda2021_BeamSlicing_Jammer_Mitigation_LowRes_ADC.pdf | 4 | M | One qualitative ADC sentence; Marti 2024 covers it |
| V7_Cheng2006_80211a_UAV_Antenna_Orientations.pdf | 5 | M | Qualitative, 5 GHz, throughput only |
| V7_Cheng2026_Fundamental_Limits_Adaptive_Beamforming_Finite_Training.pdf | 5 | M | Preprint restating RMB; Besson covers it |
| V7_Cheung1988_TDA42-95_Galileo_Nonideal_Interleaving.pdf | 5 | M | Finite-depth interleaving cost 0.2–0.5 dB, deep-space context |
| V7_Davaslioglu2024_Continual_DRL_Jamming_Forgetting.pdf | 5 | M | Forgetting framing; numbers not read |
| V7_Divsalar1988_TDA42-96_Interleaving_Convolutional_Codes.pdf | 5 | M | Depth ≈ fade length rule only |
| V7_DuPree1992_US5175558_Nulling_Pulse_Jammer_Duty_Factors.pdf | 7 | K | Null memory against blinking jammers; erasure duty limits |
| V7_ETSI_EN300328_v1.7.1_2006_24GHz_EIRP_limits.pdf | 3 | M | Superseded by V2.2.2 |
| V7_ETSI_EN300328_v2.2.2_2019_24GHz_wideband.pdf | 8 | K | 20 dBm + 10 dBm/MHz caps, MU ≤ 10 %, DAA idle ≥ 100 µs |
| V7_Enquebecq_RF_Connector_Fretting_Vibration.pdf | 8 | K | Only RF connector-fretting measurement (0.15–0.37 dB) |
| V7_Epple2012_DME_Interference_LDACS1_Pulse_Blanking.pdf | 5 | M | Blanking concept; Garcia-Pena gives the model |
| V7_Ercan2023_GRAND_EDGE_Jamming_Erasure_Decoding.pdf | 5 | M | Erasure flagging, different decoder family |
| V7_FahimRaouf2025_AERPAW_Curated_Aerial_Datasets_Attitude_Logs.pdf | 3 | M | Attitude logs exist; no numbers |
| V7_GarciaPena2021_GNSS_Degradation_Pulsed_Interference_Blanker.pdf | 8 | K | Closed-form blanking cost 1/(1 − bdc) |
| V7_Gershman1996_Robust_Beamforming_Moving_Jammer_EUSIPCO.pdf | 7 | K | Moving jammers defeat SMI; derivative-constraint widening |
| V7_Giustiniano2013_Detection_Reactive_Jamming_DSSS_WiSec.pdf | HOLD | K | No usable note (truncated); read before deciding |
| V7_GomezPonce2021_A2G_Sounder_Hover_vs_Static.pdf | 5 | M | One near-ground hover test at 3.5 GHz |
| V7_Grimaldi2019_RealTime_Interference_Identification_IoT.pdf | 7 | K | Noise-calibrated burst threshold; envelope features; WLAN TPR |
| V7_Hakkarainen2015_IQ_Imbalance_WL_Spatial_Processing_Large_Arrays.pdf | 7 | K | IQ imbalance limits linear MMSE; widely-linear fix |
| V7_Harris2017_Temporal_Analysis_LOS_Massive_MIMO_Mobility.pdf | 5 | M | Massive-MIMO CSI update rate; Shepard suffices |
| V7_Hausknecht2015_Deep_Recurrent_Q_Learning_POMDP.pdf | 6 | M | DRQN background; not adopted |
| V7_Heath2019_US10404368_Diversity_Imbalance_Detection.pdf | 6 | M | Imbalance rule without numbers; Willgert is stronger |
| V7_Hendrycks2017_MSP_Baseline_Misclassified_OOD_ICLR.pdf | 7 | K | Primary source of the reported MSP baseline |
| V7_Hendrycks2019_Outlier_Exposure_ICLR.pdf | 5 | M | Candidate only |
| V7_Hermans2013_SoNIC_Classifying_Interference_802154.pdf | 8 | K | Partial-overlap limit; 30 s voting; WLAN vs weak-link confusion |
| V7_Hong2011_DOF_Local_Wireless_Information_Plane.pdf | 5 | M | Wideband cyclostationary detection; not transferable |
| V7_Huang2010_Spatial_Interference_Cancellation_MANET_Imperfect_CSI.pdf | 5 | M | Imperfect-CSI residual, generic |
| V7_IEEE1999_80211a_5GHz_OFDM_PHY.pdf | 3 | M | 5 GHz (±20 ppm); not this band |
| V7_IEEE2007_80211-2007_Std_Revision_Full.pdf | 8 | K | Approved ±25 ppm (18.4.7.4/18.4.7.5) |
| V7_IEEE2009_80211n_HT_Amendment_PTAB_Exhibit.pdf | 6 | M | Second approved copy of the same ±25 ppm |
| V7_IEEE_802.11-11-1077r0_Yucek2011_Receiver_Max_Input_Level_TGaf.doc | 4 | M | WG comment; superseded by Fang |
| V7_IEEE_802.11-21-1563r3_Hart2022_Dynamic_Range_4kQAM.docx | 5 | M | Historical context on maximum input level |
| V7_IEEE_802.11-24-2043r0_Fang2024_PDT_PHY_Receiver_Spec_TGbn.docx | 7 | K | Current text: −20 dBm per antenna at 2.4 GHz |
| V7_IEEE_P80211b_D3.1_1999_draft_HR_DSSS.pdf | 5 | M | Unapproved draft; approved 2007 text kept |
| V7_ITU_R_F1336-5_2019_Reference_Antenna_Patterns.pdf | 8 | K | Directional / sector patterns and pointing loss (omni misuse flagged) |
| V7_Kazim2026_GNSS_Jamming_Detection_AGC_CN0_COTS.pdf | 7 | K | AGC-drop detector, 2 dB threshold, 7/7 detections |
| V7_Keysight2017_5988-5411_80211_PHY_RF_Operation_Measurement.pdf | 7 | K | Per-antenna RSSI on preamble; receiver test limits |
| V7_Kidane2025_Cross_Technology_Interference_Survey.pdf | 4 | M | Secondary survey |
| V7_Knight_Cahn_Nair2007_NavCom_Sapphire_AntiJamming_Test_Report.pdf | 6 | M | Vendor GNSS report; Bastide covers the mechanism |
| V7_LaPan2014_PhD_EW_Tactics_4G_OFDM_Sync_Attacks.pdf | 6 | M | Duplicates WCMC with more detail |
| V7_LaPan2016_OFDM_Acquisition_Timing_Sync_Security_WCMC.pdf | 8 | K | Sync attacks; CAF; secret sync position |
| V7_Li2017_Null_Broadening_Covariance_Matrix_Expansion_ACES.pdf | 6 | M | CMT null widening; little room with 3 antennas |
| V7_Li2024_Ground_to_UAV_140GHz_Hovering_Roll.pdf | 4 | M | 140 GHz; one roll value |
| V7_LimeMicro2015_LMS7002M_RF_Analog_Measurement_Results.pdf | 7 | K | Measured blocker desensitization and LNA back-off |
| V7_Lin2026_UAV_Attitude_Jitter_A2G_NonStationarity_3GHz.pdf | 8 | K | Measured hover attitude jitter → ms-scale >10 dB fades |
| V7_Liu2011_BitTrickle_Reactive_Jamming_TR.pdf | HOLD | K | No note; read before deciding |
| V7_Liu2020_Energy_Based_OOD_Detection_NeurIPS.pdf | 7 | K | Primary source of the reported energy baseline |
| V7_LopezBenitez2016_Energy_Detection_Channel_Occupancy_Rate.pdf | 6 | M | Occupancy estimate corrected for Pd/Pfa; optional |
| V7_Lunden2007_Multiple_Cyclic_Frequencies_Sensing.pdf | 4 | M | Wideband OFDM cyclostationary; numbers only in plots |
| V7_Lyu2024_FixedWing_A2G_TDL_27GHz.pdf | 7 | K | Fixed-wing LOS Doppler, Bell spectrum, circle kinematics |
| V7_Marti2023_Mitigating_Smart_Jammers_MU_MIMO.pdf | 9 | K | Pulsed-jammer failure mechanism and whole-interval fix |
| V7_Marti2023_Single_Antenna_Jammers_MIMO_OFDM.pdf | 5 | M | Delay-spread rank issue; flat model here |
| V7_Marti2024_Fundamental_Limits_Jammer_Resilient_FiniteResolution_MIMO.pdf | 8 | K | 6.02 dB per ADC bit; limit holds regardless of AGC |
| V7_Marti2024_JASS_Jammer_Resilient_Time_Sync_MIMO_arXiv.pdf | 9 | K | Key v7 reactive-jammer sync solution |
| V7_Matson2021_Antenna_Orientation_Air_to_Air.pdf | 5 | M | Capacity units only; Badi has the dB values |
| V7_Momoh2025_LowCost_Antenna_Tracking_GPS_UAV.pdf | 4 | M | Simulation-only tracker / helix |
| V7_Monk2011_US8019284_Rotor_Blade_Blockage_Blanking.pdf | 5 | M | Periodic RSSI-dip idea, no performance |
| V7_Morelli2007_ML_Timing_Carrier_Sync_Burst_Satellite_JWCN.pdf | 7 | K | Outlier threshold, CRB, timing dependence, FFT ML search |
| V7_NYCU2011_Ch5_Interleaving_Lecture_Notes.pdf | 4 | M | Lecture slides; textbook bound |
| V7_Ndili_Enge1998_GPS_Receiver_Autonomous_Interference_Detection.pdf | 6 | M | Pulsed vs CW AGC signature; Bastide covers it |
| V7_Nguyen2014_RealTime_Protocol_Aware_Reactive_Jammer_SDR.pdf | HOLD | K | Only citation key in notes; read before deciding |
| V7_Nordic2008_nRF24L01P_Product_Specification_v1.0.pdf | 7 | K | C2-class receiver: 0 dBm maximum input |
| V7_Norouzi2006_K_out_of_N_Detector_EUSIPCO.pdf | 6 | M | k-of-n background |
| V7_Noubir2011_Rate_Adaptation_Smart_Jamming_WiSec.pdf | 8 | K | Reactive-jam efficiency; secret-position silent interval |
| V7_Nugroho2018_Automatic_Antenna_Tracker_UAV_measured.pdf | 8 | K | Measured tracker error 5.62°/1.51°; start-up faults |
| V7_Ogawa1983_Power_Inversion_Adaptive_Array.pdf | 7 | K | Reference-free nulling suppresses a strong desired signal |
| V7_Olsson2022_Participatory_Sensing_GNSS_Jammer_AGC.pdf | 6 | M | AGC model and 5 dB rule; Kazim/Bastide suffice |
| V7_Pirayesh2022_Jamming_AntiJamming_Survey_COMST_arXiv.pdf | 8 | K | Map of defences; silent-period estimation; spatial pre-sync filtering |
| V7_Polle2026_DJI_Air3S_Hover_Tilt_Wind_Telemetry.pdf | 7 | K | Measured multirotor tilt in wind |
| V7_Pourranjbar2021_RL_Deceiving_Reactive_Jammers.pdf | 5 | M | Deception idea; only abstract read |
| V7_Rahbari2016_Swift_Jamming_FO_Estimation_TMC.pdf | 8 | K | Interference steers the FO estimate; FO-bin search fix |
| V7_Rao2016_MS_OFDM_Pilot_Jamming_LTE_CRS.pdf | 6 | M | LTE pilot shifting; OFDM-specific |
| V7_Rayanchu2011_Airshark_NonWiFi_RF_Device_Detection.pdf | 6 | M | Low-FPR reference, wideband sensor |
| V7_Riyandi2018_PID_Fuzzy_GPS_Antenna_Tracker.pdf | 7 | K | Tracker error vs speed (corrected: 60 km/h motorcycle) |
| V7_Riyandi2018_Transient_Indonesian_Version_Antenna_Tracker.pdf | 3 | M | Companion paper of the same experiment |
| V7_RodriguezPineiro2020_A2G_LowHeight_UAV_Directional_vs_Omni.pdf | 8 | K | Directional vs omni GCS K and Doppler at 2.5 GHz |
| V7_RohdeSchwarz2014_1MA69_WLAN_Tests_80211abg.pdf | 6 | M | Corroborates 802.11 limits; Fang/Keysight kept |
| V7_Rumpf2017_Antenna_FOM_Polarization_Loss_slides.pdf | 3 | M | Lecture slides; Badi gives the PLF law |
| V7_Saboor2025_TrajectoryAware_A2G_MaMIMO_261GHz.pdf | 6 | M | K(h) fit at 2.61 GHz; only skimmed |
| V7_Schmidt2017_Wireless_Interference_Identification_CNN.pdf | 6 | M | WLAN worst when clipped by narrow bandwidth |
| V7_Schulz2017_Massive_Reactive_Smartphone_Jamming_WiSec.pdf | HOLD | K | No note; read before deciding |
| V7_Shahriar2015_PHY_Resiliency_OFDM_Tutorial_COMST.pdf | 8 | K | Pilot / preamble attacks and defences, BER trade-offs |
| V7_Shahriar2015_PhD_Resilient_Waveform_OFDM_MIMO_Pilot_Attacks.pdf | 5 | M | Duplicates the tutorial |
| V7_Shebert2021_Open_Set_Wireless_Standard_Classification.pdf | 6 | M | Open-set trade-off; 2023 paper kept |
| V7_Shepard2016_Real_ManyAntenna_MUMIMO_Channels_Mobility.pdf | 7 | K | Measured channel aging at 2.4 GHz (1.1 ms) |
| V7_Simunek2011_Excess_Loss_Low_Elevation_UAV.pdf | 5 | M | Airship, figures only |
| V7_Smith2008_Intermittent_Fault_Location_Live_Wiring_SAE.pdf | 4 | M | Wiring arcs, not RF |
| V7_TI_CC2500_Datasheet_SWRS040C.pdf | 7 | K | C2-class saturation −18 to −9 dBm |
| V7_Tan2016_GPS_4Antenna_AntiSaturation_AntiJamming_Experiment.pdf | 6 | M | GNSS anti-saturation; receiver-level metric |
| V7_Tang2012_Sensing_Multiple_PU_Status_Changes.pdf | 6 | M | Partial-window energy detection theory |
| V7_Thulin2014_EJS_Cost_Exact_Binomial_Intervals_published.pdf | 10 | K | KPI 6 exact one-sided bound (EJS version) |
| V7_Truong2013_Channel_Aging_Massive_MIMO.pdf | 8 | K | J0 aging model behind the Doppler failure |
| V7_Vanhoef2014_Advanced_WiFi_Attacks_Commodity_Hardware_ACSAC.pdf | HOLD | K | No note; read before deciding |
| V7_Wang2025_Jamming_Resistant_UAV_Multichannel.pdf | 7 | K | Measured 2-antenna decoding at 40 dB CW; sync is hard |
| V7_Whitehouse2005_Capture_Effect_Collision_Detection_EmNetS.pdf | 7 | K | Small capture advantage; arrival order matters (no 30 dB) |
| V7_Wilhelm2011_Reactive_Jamming_How_Realistic_WiSec.pdf | HOLD | K | Only citation key in notes; read before deciding |
| V7_Wilhelm2013_Air_Dominance_Selective_Interference_arXiv.pdf | HOLD | K | No note; read before deciding |
| V7_Willgert2013_US8548029_Antenna_System_Monitoring.pdf | 7 | K | Branch-difference distribution diagnosis for antenna faults |
| V7_Winters_Salz_Gitlin1994_Antenna_Diversity_Capacity.pdf | 9 | K | M − N + 1 rule; DMI sample cost |
| V7_Wood2007_DEEJAM_Energy_Efficient_Jamming_SECON.pdf | HOLD | K | No note; read before deciding |
| V7_Xie2021_Sequential_Change_Detection_Survey_JSAIT.pdf | 8 | K | CUSUM optimality, FAR = 1/ARL, EWMA |
| V7_Yan2016_Jamming_Resilient_MIMO_Interference_Cancellation_TIFS.pdf | HOLD | K | Known only via JASS's summary; read before deciding |
| V7_Yanmaz2013_3D_Aerial_Mobility_80211_Antenna.pdf | 7 | K | Only measured 3-antenna UAV array |
| V7_Zeng2017_Jamming_Resistant_MIMO_JrRx_CNS.pdf | 7 | K | Measured spatial pre-sync filtering at 20 dB |
| V7_Zhang2017_Faulty_Antenna_Detection_Massive_MIMO.pdf | 4 | M | Different fault model (sparse corruption) |
| V7_Zhang2024_Preamble_Forgery_Injection_WiFi_TMC.pdf | HOLD | K | Only citation key in notes; read before deciding |
| V7_Zumegen2024_BeamArmor_5G_Null_Steering_AntiJamming.pdf | 6 | M | 10 dB lab nulling; Wang/Zeng are stronger |
| W01_2025_Reactive_Dynamic_Jamming_RL.pdf | 8 | K | Reactive-jammer definition; adaptive-adversary template |
| W02_Schaul2016_Prioritized_Experience_Replay.pdf | 6 | M | Candidate only |
| W03_2025_Robust_MultiTimescale_AntiJamming_State_Uncertainty.pdf | 7 | K | Frequency on the slow timescale; robustness under noisy states |
| W04_Xie2022_Window_Limited_CUSUM.pdf | 7 | K | WLCUSUM for unknown fault duty / occupancy |
| W05_2025_Fast_AntiJamming_DQN_Spectrum_Prediction.pdf | 4 | M | Does not back "history 8" |
| W06_ITU_R_P838-3_Rain_Attenuation.pdf | 7 | K | Only backing for "rain negligible" (0.020 dB/km) |
| W07_RamirezEspinosa2018_NonCentral_Quadratic_Forms_Correlated_Rician_MRC.pdf | 9 | K | PHY-validation V5 model |
| W08_Khawaja2019_A2G_Channel_Modeling_Survey.pdf | 9 | K | K range, speed, antennas, hover warning (ρ = 0.3 not in it) |
| aerospace-03-00014.pdf | 8 | K | Gross 2016: measured roll −58° to +28° |
| isma2016_0797.pdf | 9 | K | Verbeke: the 86–672 Hz modes (modal, not a continuous range) |
| דירוג מקורות וחולשות הפרויקט.md | — | K | Ranking file; excluded from the move list |

**Move list** (70 files; one per line in `reports/move_list.txt`). Four are exact duplicates: `1801.01656v1.pdf`, `20070022339.pdf`, `IEEE 802.11 Physical Layer Operation and Measurement.pdf` and `Spectrum_Occupancy_Measurements_and_Analysis_in_24 (1).pdf`. The other 66 are every file scored 1–6 in the table above. Nothing has been moved. The ten HOLD files are excluded until they are read.

## Conclusion

The pattern matters more than any single error. Wherever the project cites a source for *how* to do something (detect, bound, learn, shield, validate), the citation holds. Wherever it cites a source for *how bad* a threat is, the number has usually moved from its origin: a transmit ratio read as a received ratio, a lab case read as field data, a fading peak read as a sustained loss. The rule "most severe value within the sources' measured range" is right, but each cap must be traced to the paper that actually measured it, and some caps will shrink. Shadowing drops to a 10–25 dB median with K ≤ 0 dB. Spoofing becomes "capture at a small advantage", and the 30 dB value either needs a new source or has to go. WLAN power has to be bounded by the 10 dBm/MHz PSD limit.

For v7, the sources point to one shared cause behind three different real-receiver failures. A covariance or interference estimate taken in one place (the quiet slot) and used somewhere else is stale under Doppler, empty under pulses, and either targetable or empty under reactive jamming. Frame-wide or tracked estimation, a secret sync sequence with temporal projection, and memory of the null address that one cause from three sides. A seconds-scale sequential decision (CUSUM or voting) is the matching fix for the two weak detector classes.
