# Review of Adi's three new library downloads (Abdullayeva 2025, Gross 2016, Bastide 2003) plus a duplicate check

Method: all three PDFs were read in full with `pdftotext -layout`. Page rendering was not available (no pdftoppm), so I got the figures in two other ways. Embedded raster figures were decoded straight from the PDF streams with a small Python script. Gross et al. Fig. 4 is a vector plot, so I read its plotted coordinates out of the page content stream, using the axis gridlines for calibration. All scratch files are in `extracts_adi_new/` next to this file. Nothing in the library or in any uav-gcs-* folder was changed. Local library folder: `C:\Users\Adi Suliman\Desktop\תואר ראשון  הנדסת חשמל ואלקטרוניקה\שנה ד\פרוייקט גמר\מקורות\`.

Source links used below:
- [Abdullayeva2025] = Abdullayeva & Valikhanli, Cyber Security and Applications 3 (2025) 100094, https://doi.org/10.1016/j.csa.2025.100094 (local: 1-s2.0-S2772918425000116-main.pdf, 9 pp.)
- [Gross2016] = Gross, Gu & Rhudy, Aerospace 2016, 3, 14, https://doi.org/10.3390/aerospace3020014 (local: aerospace-03-00014.pdf, 12 pp.)
- [Bastide2003] = Bastide, Akos, Macabiau & Roturier, ION GPS/GNSS 2003, pp. 2042-2053, https://enac.hal.science/hal-01021721 (local: 122.pdf, HAL cover + 12 pp.; page numbers below are the paper's own)

## Q1. Abdullayeva & Valikhanli 2025: what does it prove, and does it back the CNN-spectrogram + receiver-features hybrid detector?

### Takeaway
This is a genuine primary source for the *architecture pattern* of our detector: a CNN on a 128x128 spectrogram, a dense branch on a small vector of hand-computed signal features, concatenation fusion, and a softmax classifier. Fusion beat each branch alone (99% vs 96.25% / 94.66%). The evidence behind it is weak, though: all data is MATLAB-simulated GNSS jamming IQ from a public dataset, there is no flight or lab data, the test set is one random split of about 1,200 samples, and its tabular-feature baselines are internally inconsistent. It also **corrects the second-hand summary** we cited before. The MLP input is 5 signal features computed from the IQ, not "UAV telemetry", and the data is simulated, not "lab/SDR-generated". Verdict: **SUPPORTING**. It is CORE for one sentence only ("CNN-spectrogram + feature-MLP concatenation fusion has been used for jamming classification"), and it is not evidence for our accuracy levels or for any real-world claim.

### Cited Findings
- **Architecture, Fig. 2, p. 5 (Keras model graph, read from the embedded image).** Image branch: input 128x128x3 → Conv2D 32 (126x126) → MaxPool (63x63) → Conv2D 64 (61x61) → MaxPool (30x30) → Conv2D 64 (28x28) → Flatten (50176) → Dense 64. Feature branch: input 5 → Dense 5 → Dense 100. These merge in a Concatenate layer (164) → Dense 100 → Dense 6 (softmax). — [Abdullayeva2025](https://doi.org/10.1016/j.csa.2025.100094)
- **Fusion method, §4.3, p. 4:** "In this work, concatenation is used during the fusion process due to its simplicity and computational efficiency." Algorithm 1 (p. 6) gives Xfused = [Ximage, Xsignal], softmax, and cross-entropy loss. — [Abdullayeva2025](https://doi.org/10.1016/j.csa.2025.100094)
- **Feature branch inputs, §6.1, p. 4:** "The signal features used in this work are signal-to-noise ratio (SNR), magnitude of the signal, power of the signal, energy of the signal, and mean autocorrelation of the signal." These are computed in MATLAB (Algorithm 2, p. 6). Algorithm 2 computes magnitude and power from `meanVal` (the mean of the raw signal), not from the per-sample power. — [Abdullayeva2025](https://doi.org/10.1016/j.csa.2025.100094)
- **Data, §6.2, p. 4-5:** the dataset is the "Raw IQ dataset for GNSS GPS jamming signal classification" (Swinney & Woods 2021, Zenodo 10.5281/zenodo.4629685, ref. [21]). Its samples are "RAW IQ signals which are created in a simulation environment using Matlab software." It has 7500 samples in 6 classes (1000 train + 250 test per class), and "a total of 6000 samples are used." — [Abdullayeva2025](https://doi.org/10.1016/j.csa.2025.100094)
- **Classes (6):** No jammer, Pulse (DME), NB, AM (single), FM (single), Chirp (single) (Algorithm 1 step 3, p. 6; Fig. 1, p. 4). — [Abdullayeva2025](https://doi.org/10.1016/j.csa.2025.100094)
- **Spectrogram, §6.3, p. 5:** "We used a window size of 256 and an overlap of 128". Default images were 875x656 and were resized; "images with 128 × 128 resolution gave the best results." — [Abdullayeva2025](https://doi.org/10.1016/j.csa.2025.100094)
- **Headline results, Table 4, p. 8:** MLP 96.25% accuracy / 96.25% F1. CNN 94.66% / 94.63% F1. "Multimodal deep learning (MLP+CNN)" 99% accuracy / 99.01% precision / 99% recall / 99% F1. Training times are 7.232 s (MLP), 36 min 7 s (CNN) and 36 min 27 s (multimodal). The prediction-time column (0.102 s, 2.679 s, 3.477 s) did not extract cleanly, so which time belongs to which row is UNVERIFIED. Abstract wording: "MLP was able to detect GPS jamming attacks with 96.25 % accuracy, CNN with 94.66 % accuracy, and the proposed multimodal deep learning (MLP+CNN) with 99 % accuracy." — [Abdullayeva2025](https://doi.org/10.1016/j.csa.2025.100094)
- **Confusion matrices (Figs. 4-6, p. 7, read from the embedded images).** Each test set holds 1200 samples with unequal class counts (176-222 per class).
  - Matrix labelled "_par" with 1188/1200 correct = 99.0%. This matches the multimodal model; the remaining errors are 7 FM→AM, 3 AM→NB and 2 NB→Chirp.
  - Second "_par" matrix with 1157/1200 = 96.4%. This matches the MLP.
  - Spectrogram matrix (no suffix) with 1147/1200 = 95.6%. This is close to, but not equal to, the CNN's 94.66% in Table 4. The CNN's biggest confusion is FM→AM (19).
  - The mapping of each matrix to its figure number is inferred from the labels. — [Abdullayeva2025](https://doi.org/10.1016/j.csa.2025.100094)
- **Tabular baselines, Tables 1-2, p. 6-7.** Classical ML on the tabular features gave about 83% binary accuracy ("an average accuracy of approximately 83 %") and 23-32% multiclass accuracy. The text concludes "relying solely on machine learning methods is not sufficient." Column alignment of the per-method rows was garbled in extraction. — [Abdullayeva2025](https://doi.org/10.1016/j.csa.2025.100094)
- **Hybrid CNN-features + classical classifier, Table 3, p. 7:** 95.16-96.08% accuracy (CNN+KNN and CNN+GNB best at 96.08%). — [Abdullayeva2025](https://doi.org/10.1016/j.csa.2025.100094)
- **Scope.** The target is GNSS L1 jamming, not a command link. §2, p. 2: "traditional jamming attacks target the communication channel between the UAV and GCS." This is set apart from the GPS jamming that the paper itself treats. The hardware was a laptop (i7-8550U, Python 3.8). — [Abdullayeva2025](https://doi.org/10.1016/j.csa.2025.100094)

### Inferences
- **The binary baseline is degenerate.** With 5 jammer classes against 1 normal class, a classifier that always says "jammed" scores accuracy 5/6 = 83.33%, weighted precision (5/6)^2 = 69.44% and weighted F1 = (5/6)(10/11) = 75.76%. Table 1's rows (83.27-83.35% / 69.34-69.47% / 75.67-75.78%) match this almost exactly. So the classical binary models learned essentially nothing from the 5 features. Yet the MLP reaches 96.25% on 6 classes using the same 5 features. The paper does not explain the contradiction, so it should not be cited for "these features are informative on their own".
- **The test protocol is thin.** It is a single split of 1200 samples (about 20% of the 6000), with no repeated runs, no confidence intervals and no out-of-distribution or unseen-SNR test. The source dataset's own 250-per-class test split was apparently not used (6000 used, not 7500).
- **Correction to our earlier notes.** detection_statistics_sources.md (via Tariq 2026) says "MLP on UAV telemetry" and "lab (SDR-generated)". The primary paper shows signal features computed from the IQ, and data simulated in MATLAB. The citation wording should follow the primary paper.
- **How closely it matches our design.** It has a spectrogram CNN, a feature vector from the receiver signal and concatenation fusion, and its 128x128 input is the same as ours. It differs in the band (GNSS L1, not a 2.4 GHz QPSK command link), the size of the feature vector (5 features, ours has 18), the branch layout (single-antenna, ours combines 3 antennas with MMSE), and the threats (GNSS jammer types only, no spoofing or link threats).

### Gaps
- Optimiser, learning rate, batch size, epochs beyond "only 30 epochs" (§6.6, p. 7) and the exact train/test split are not stated. UNVERIFIED.
- The SNR range of the samples is not given in the paper, so generalisation across SNR cannot be judged from it.
- The Swinney & Woods dataset documentation was not read (no new sources).

## Q2. Gross, Gu & Rhudy 2016 (WVU Red Phastball): aircraft, measured roll/bank and roll rates, and what "60° for roll vs. 20 for pitch" means

### Takeaway
The paper is about estimating attitude from GPS signal strength. Its usable content for v7 is the **measured reference attitude** of a small fixed-wing UAV in normal flight: a Goodrich VG34 mechanical vertical gyro, 50 Hz, accurate to 0.1° (Fig. 4). I digitised Fig. 4 from its vector data. Over about 327 s the gyro roll spans **−58° to +28°**: |roll| above 45° for about 6% of the time and above 50° for about 2.5%, with a 95th percentile |roll| of about 46°. Pitch spans −11.5° to +17°. So "60° for roll vs. 20 for pitch" matches the **peak absolute excursion (amplitude ≈ ±60° / ±20°)**, not peak-to-peak (that would be about 86° and 29°). The paper gives no aircraft mass, span or speed. Verdict: **SUPPORTING** for v7 bank-angle bounds. It is one measured small-UAV roll trace with gyro-grade reference, but the flight is not described as coordinated turns, the airspeed is unknown, and it was hand-flown or autopilot-flown (not stated).

### Cited Findings
- **Platform and sensors, §3, p. 7:** "West Virginia University's (WVU's) Red Phastball Platform". The receiver was a NovAtel OEM-615 recording at 10 Hz. "the Red Phastball flew a Goodrich VG34® mechanical vertical gyroscope and the analog pitch and roll measurements were recorded using a micro-controller with a sampling rate of 50 Hz". "The VG34® reports an absolute attitude within 0.1° of the true vertical." The site was WVU Jackson's Mill, an open airfield in a valley. — [Gross2016](https://doi.org/10.3390/aerospace3020014)
- **Mass, wingspan, airspeed, flight plan.** None of these appear anywhere in the text (the full text was checked). The paper points to refs. [17-20] for the platform. — [Gross2016](https://doi.org/10.3390/aerospace3020014)
- **The "60°" quote, §4.2, p. 9:** "considering that the signal amplitude for roll is much large than for pitch (i.e., 60° for roll vs. 20 for pitch), the relative percentage errors are comparable." The term "amplitude" is not defined further. — [Gross2016](https://doi.org/10.3390/aerospace3020014)
- **Fig. 4, p. 10.** Caption: "Comparison of GPS signal strength based attitude estimate and mechanical gyroscope measurements". The roll axis runs −65° to +50° with ticks at −50/0/50, and the time axis runs 0-350 s. The legend shows VG34 = solid blue and "UKF GPS-SS Est." = dashed orange (confirmed from the drawing commands). — [Gross2016](https://doi.org/10.3390/aerospace3020014)
- **Fig. 4 digitised, VG34 roll** (1630 plotted points, 0-327 s, about 0.2 s spacing): min −57.9°, max +28.0°, mean −14.8°, SD 17.9°. |roll| percentiles: p50 10.3°, p90 40.2°, p95 45.8°, p99 53.9°. Time above |20°| 35%, above |30°| 27%, above |40°| 11%, above |45°| 6.1%, above |50°| 2.5%, above |60°| 0%. Nearly every 10-s window from 20 s to 310 s reaches −35° to −58°, so the aircraft was mostly banked one way, consistent with repeated left-hand circuits under the usual sign convention. The data come from the drawing commands of Fig. 4 (no rendering); a cross-check follows two bullets down. — [Gross2016](https://doi.org/10.3390/aerospace3020014)
- **Fig. 4 digitised, VG34 pitch:** min −11.5°, max +17.2°, mean 2.0°, SD 4.2°. — [Gross2016](https://doi.org/10.3390/aerospace3020014)
- **Cross-check of the digitisation against Table 1, p. 9.** Fig. 4 shows the Poly-ElvDep strategy (text, p. 9). From the digitised curves, mean (UKF − VG34) is −9.8° in roll and +0.6° in pitch. Table 1 gives Poly-ElvDep mean errors of −9.3° (roll) and 0.5° (pitch). The small roll difference comes from the UKF curve being clipped at the −65° axis floor. Table 1 rows as extracted (roll mean/SD, pitch mean/SD, degrees):
  - Poly-Flat: −10.4 / 5.6, 2.6 / 4.1
  - Poly-ElvDep: −9.3 / 4.3, 0.5 / 3.0
  - LUT-Flat: −8.2 / 7.6, −0.3 / 3.2
  - LUT-ElvDep: −7.0 / 7.3, −1.1 / 2.7
  This row order is consistent with the text, which says LUT has the smaller roll mean error and Poly the smoother roll. — [Gross2016](https://doi.org/10.3390/aerospace3020014)
- **Roll rates (digitised VG34, 0.2-s finite differences, noisy):** median 4.6°/s, p90 17.8°/s, p99 35.6°/s, max 67.7°/s. Over 1-s windows: median 3.5°/s, p90 15.0°/s, p99 28.0°/s, max 35.5°/s. These were derived by me; the paper reports no roll rates. — [Gross2016](https://doi.org/10.3390/aerospace3020014)
- **Process-noise values, §2.7, p. 5.** The values are 7, 1 and 3 deg/s at 10 Hz; the Greek symbols were lost in extraction. "These values were chosen by simply evaluating the maximum change of each attitude state over between 10 Hz sampling steps." "typically, the amplitude of the change in the pitch angle of a UAV is smaller than the amplitude in the change of the roll for a fixed-wing UAV doing a coordinated turn." The value-to-angle assignment (roll 7, pitch 1, yaw 3) is inferred from this sentence and the state order [φ, θ, ψ], so it is UNVERIFIED. These are filter tuning values, not measured rates. — [Gross2016](https://doi.org/10.3390/aerospace3020014)

### Inferences
- **"60° vs 20" is an amplitude, not peak-to-peak.** The measured extremes are about −58° and about +17°. Peak-to-peak would be about 86° and 29°, so "60/20" fits a rounded maximum |angle|. The paper does not define the term, so this reading is mine.
- **What it means for v7 bank angles.** Within this one source, sustained turning sits mostly at 35-45° of bank, with brief excursions to 50-58° and none beyond 60°. If v7 uses "the most severe value within the source", this source supports about 58° measured, or the authors' rounded 60°. Pair it with the existing Allen 2007 (−53°) and X8 (65°) entries in small_uav_bank_angles.md.
- **Roll-rate caution.** The 0.2-s difference rates include gyro and plot noise. The 1-s window values (p99 about 28°/s) are the more defensible roll-rate figures.

### Gaps
- Aircraft mass, airspeed and whether the flight was autopilot or RC are UNVERIFIED (not in the paper). The "about 11 kg / about 30 m/s" figures in small_uav_bank_angles.md remain from memory, so UNVERIFIED.
- Whether the turns were coordinated (zero sideslip) is not stated. Without airspeed, tan φ = v²/(gR) cannot be checked.
- The digitised values depend on Fig. 4 being drawn at full resolution. The plot spacing is 0.2 s, against 50 Hz gyro logging, so short peaks may be decimated and the true extremes could be slightly larger.

## Q3. Bastide, Akos, Macabiau & Roturier 2003: AGC response to interference, saturation, thresholds, pulsed vs CW, ADC bits

### Takeaway
This is a primary measured and simulated source for AGC/ADC behaviour under interference, for GNSS (NovAtel OEM4, plus a custom 12-bit L1/L5 monitor).
- **AWGN:** measured AGC gain falls by about 1, 3, 10, 15 and 21 dB at noise increases of 5, 10, 20, 25 and 30 dB (Fig. 5). That is sub-unity at low levels and about 1 dB/dB at high levels.
- **DME-like pulses:** the AGC barely moves, with only about 0.5 dB of drop at +27 dB pulse power and −3 dB at +40 dB (Fig. 23).
- **CW:** with 3 bits and an AGC tuned only for Gaussian noise, correlator SNR degradation is about 10 dB worse than with optimal adaptation at J/N = 20 dB (p. 4; Fig. 7).
- **Saturation:** the paper states it qualitatively. Raw 12-bit data show pulses clipping at full scale (±2047) while noise uses about ±300-500 counts (Figs. 15, 16, 21).
- **Natural drift:** the nominal AGC moves about 1 dB per day with temperature (Fig. 17), which bounds how small an AGC-drop threshold can usefully be.

Verdict: **CORE** for v7 receiver-realism (AGC/ADC) modelling and for justifying an AGC-change feature. All of it is GNSS (signal below the noise floor), so it transfers to our above-noise QPSK link only in mechanism, not in thresholds.

### Cited Findings
- **Role of the AGC, Introduction, p. 1:** AGC "may be viewed as an adaptive variable gain amplifier whose main role is to minimize quantization losses." "For GNSS receivers in which the useful signal power is below that of the thermal noise floor, the AGC is driven by the ambient noise environment rather than the signal power." — [Bastide2003](https://enac.hal.science/hal-01021721)
- **Saturation, p. 3:** "if an interferer appears it can cause saturation in the quantizer and even completely capture the process. By decreasing its gain, the AGC limits signal saturation." Also: "the larger the number of bits, the less sensitive the SNR degradation to the AGC gain setting." On the analog gain limit (p. 6): "the variable analog gain has a limited range such that the AGC gain cannot decrease below a certain fixed value. It may imply saturation in traditional AGC/ADC implementations." — [Bastide2003](https://enac.hal.science/hal-01021721)
- **Quantization loss, Table 1, p. 3** (minimum SNR degradation at optimal k = L/σ):

  | ADC bits | Minimum degradation | Optimal k |
  |---|---|---|
  | 1 | 1.96 dB | — |
  | 2 | 0.5369 dB | 0.9860 |
  | 3 | 0.1589 dB | 1.7310 |
  | 4 | 0.0138 dB | 2.2910 |
  | 5 | 0.0138 dB | 2.2910 |

  The 4-bit and 5-bit values are printed identically in the paper. Fig. 3 (p. 3) shows the degradation against k for 1-5 bits; the 2-bit curve's loss climbs back to about 1.9 dB when k is badly off (k ≥ 4). — [Bastide2003](https://enac.hal.science/hal-01021721)
- **Optimal 2-bit bin loading, Fig. 4, p. 3:** "16.35 % 33.65 % 33.65 % 16.35 %". AGC control methods: analog power measurement, conservation of the Gaussian bin shape, or mapping ADC output power to input power (p. 3). — [Bastide2003](https://enac.hal.science/hal-01021721)
- **AGC versus AWGN, Fig. 5, p. 4** (NovAtel OEM4, noise generator coupled with the live L1 antenna; read from the figure image). The AGC gain change is about 0 dB at +2 dB, −1 dB at +5, −3 dB at +10, −6 dB at +15, −10 dB at +20, −15 dB at +25 and −21 dB at +30 dB "input interfering AWGN power increase". Text: "The AWGN power increase is detected by the AGC and the receiver decreases its internal gain to conserve the optimal input signal standard deviation. The detection of potential interference is clearly possible by looking at the AGC gain variation with respect to the nominal case." — [Bastide2003](https://enac.hal.science/hal-01021721)
- **CW interference, Figs. 6-7, p. 4.** Fig. 7 shows 3-bit SNR degradation against J/N from −10 to +20 dB for three cases: "linear" (no AGC/ADC), "optimal" adaptation and "classical/blind" adaptation. Read from the figure, at J/N = 20 dB these are about −20, −14.5 and −26.5 dB. Text: "for large J/N ratios, the difference of degradation between the optimal and the classic adaptation may be large. For example, the result is about 10 dB for J/N=20 dB." Fig. 6 shows the degradation against quantizer interval for J/N = 0, 3, 9 and 12 dB (about −3 to −19 dB). — [Bastide2003](https://enac.hal.science/hal-01021721)
- **Pulsed interference and the AGC, Fig. 23, p. 11.** The source was a DME-like pulse pair, 3.5 µs half-amplitude width, 12 µs spacing, about 3300 pulse pairs/s, at 1573.0 MHz (offset 2.42 MHz), injected into the OEM4. Read from the figure, the AGC change is about −0.5 dB at +27 dB, −1 dB at +32 dB, −3 dB at +40 dB and −9.5 dB at +48 dB. Text: "As expected for pulsed signals, there is not a one-to-one change in that relationship." In C/N0 (Fig. 24), SV1 drops from 49.4 to about 41 dB-Hz and SV3 from 48.9 to about 34.5 dB-Hz at +50 dB. SV20 drops from about 42 to about 35 dB-Hz at +33 dB and to about 26 dB-Hz at +50 dB. — [Bastide2003](https://enac.hal.science/hal-01021721)
- **ADC clipping in raw data.** The monitor digitises with a 12-bit ADC, with gain set "to exercise a majority of a 12-bit ADC" (p. 7).
  - Fig. 15 (L5, real Woodside DME at 1173 MHz): pulse samples sit flat at about ±2047, i.e. clipped, against noise of about ±500.
  - Fig. 21 (injected DME-like signal): pulses reach ±2048 against nominal noise of about ±300.
  - Fig. 16 (L1): rare short pulses reach about ±2000 against noise of about ±450. These were seen in "less than 0.5% of the data sets" (p. 9).
  — [Bastide2003](https://enac.hal.science/hal-01021721)
- **Bits for blanking and dynamic range, pp. 5-6.** The cited Grabowski design used "8 bits ... to quantize the signal but the signal was eventually represented using only 3 of those 8 bits". Table 2 (5-bit ADC, 2 bits used) gives a dynamic range of 32, 16 and 8 V for 0, 1 and 2 extra resolution bits. The dynamic range formula is 2·(2^(bit_total−bit_res)−1)·Δ. The DME pulses are "about 3 µs" (p. 5). — [Bastide2003](https://enac.hal.science/hal-01021721)
- **Chi-square detector on ADC bins, pp. 6-7; Fig. 11, p. 7.** T = Σ (n_current − n_nom)² / (n_current + n_nom), with significance 0.05 interpreted as the false-alarm probability. In the CW-at-L1 test, read from the figure, the threshold is about 11.1 and T peaks at about 23. Detection runs from about 620 s to about 960 s of a ramp-up/ramp-down test. Text: "this test enables to detect interference even if a few bits are used (e.g., 2.5 for this receiver)". The paper's own claim: the ADC distribution can reveal interference that a pure AGC level hides, "Thus, even in presence of interference, the ADC distribution may seem to be nominal. However if the resolution is increased, the ADC distribution may clearly represent the distribution of the incoming signal" (p. 6). — [Bastide2003](https://enac.hal.science/hal-01021721)
- **Nominal AGC drift, p. 9; Figs. 17-18:** "the AGC gain varies periodically by about 1 dB during the test." The figure range is about 15.1-16.4 dB over 2 days, while ambient temperature ran about 50-92 °F. The cause is the antenna amplifier gain changing with temperature. The paper notes the change "is relatively minor and thus even if it was completely neglected, the current implementation would still be quite valuable for interference detection." — [Bastide2003](https://enac.hal.science/hal-01021721)
- **Conclusion, p. 11:** "The AGC system has been shown to be an accurate indicator of noise environment of the receiver. Its gain varies with respect to the present interference power and so is a valuable tool to detect them." — [Bastide2003](https://enac.hal.science/hal-01021721)

### Inferences
- **AGC slope.** Fig. 5's curve is consistent with the ideal model g·(J+N) = constant used by Olsson et al. (in receiver_dynamic_range.md). Expressed against injected-noise level, the slope is shallow until the injected noise is comparable to the thermal noise. It then approaches about 1 dB/dB: roughly 0.7 dB/dB between +10 and +20 dB, and about 1.1 dB/dB between +20 and +30 dB. These slopes are my reading of the figure, not numbers stated in the paper.
- **Pulsed versus continuous.** Low-duty pulsed jamming produces a much smaller AGC change than continuous noise of the same nominal power step (−3 dB at +40 dB for pulses, against −21 dB at +30 dB for AWGN). Its main symptom instead is ADC clipping during the pulses plus a C/N0 loss. An AGC-only detector with a 2-5 dB threshold would therefore miss weak or medium pulsed jammers that already cost 5-10 dB of C/N0 (Fig. 24, SV20 at +25 to +33 dB).
- **Natural drift sets a floor for thresholds.** With about 1 dB of daily temperature drift, an AGC-drop threshold near 2 dB has little margin unless the receiver is temperature-compensated. This supports thresholds in the 2-5 dB range rather than below.
- **Transfer to our link.** Our QPSK command link sits above the noise floor, so the AGC is driven by signal + jammer + noise, not by noise alone. The mechanisms (gain compression, clipping, quantization loss with few effective bits, the CW penalty of blind Gaussian AGC) carry over. The specific numbers (L1, OEM4, 2-3 bit tracking) do not.

### Gaps
- The x-axes of Figs. 5 and 23 are a relative "input ... power increase (dB)", not an absolute dBm or J/N. Absolute jammer power at saturation is not given.
- The OEM4 AGC loop time constant and attack/decay are not given, so no AGC time-response numbers are available.
- The ADC full-scale input power (dBm) of the monitor is not given. The OEM4's effective bits are given only as "e.g., 2.5".
- All values read from figures are approximate visual readings of the raster images (about ±0.5 dB on the AGC plots).

## Q4. Is 20070022339.pdf a duplicate of V7_Allen2007_NASA_TM_Autonomous_Soaring_UAV_Bank_Angle_Flight.pdf?

### Takeaway
Yes. The two files are byte-identical. One copy can be removed once Adi approves; nothing was deleted.

### Cited Findings
- `20070022339.pdf`: 7,533,981 bytes, MD5 `8038aaf90f042f1ff9cd2e8d36ffd398`.
- `V7_Allen2007_NASA_TM_Autonomous_Soaring_UAV_Bank_Angle_Flight.pdf`: 7,533,981 bytes, MD5 `8038aaf90f042f1ff9cd2e8d36ffd398` (identical).
- The two copies have different modification times (12:49 and 12:55 on 2026-10-01). This is local evidence from `md5sum` and `ls` on the library folder; there is no URL.

### Inferences
- `20070022339` is the NASA NTRS document ID of NASA/TM-2007-214611 (Allen & Lin). The V7_ file is a renamed copy of the same download.

### Gaps
- None.
