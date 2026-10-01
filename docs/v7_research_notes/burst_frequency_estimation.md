# Burst-mode carrier-frequency and timing estimation, and frequency/timing estimation in multi-antenna receivers under strong interference

Scope note: the coordinator stopped the search part-way at Adi's request ("no more new sources are needed"). These notes use only what was actually read before that point. Read in full or in the relevant sections:
1. Bertolucci, Cassettari, Fanucci, "On the Frequency Carrier Offset and Symbol Timing Estimation for CCSDS 131.2-B-1 High Data-Rate Telemetry Receivers", Sensors 21 (2021) 2915, CC BY. Saved as `V7_Bertolucci2021_CCSDS_Frequency_Timing_Estimators_Sensors.pdf`.
2. Morelli and D'Amico, "Maximum Likelihood Timing and Carrier Synchronization in Burst-Mode Satellite Transmissions", EURASIP JWCN 2007, Article ID 65058, CC BY. Saved as `V7_Morelli2007_ML_Timing_Carrier_Sync_Burst_Satellite_JWCN.pdf`.
3. Rahbari, Krunz and Lazos, "Swift Jamming Attack on Frequency Offset Estimation: The Achilles' Heel of OFDM Systems", IEEE TMC 15(5), May 2016, from p. 1264. This was already in Adi's folder as `V7_Rahbari2016_Swift_Jamming_FO_Estimation_TMC.pdf`.

None of the original classic papers (Fitz 1991/1994, Luise & Reggiannini 1995, Kay 1989, Mengali & Morelli 1997, Schmidl & Cox 1997, Morelli & Mengali 1998 tutorial) could be obtained from an open source. Their formulas below come from the restatement in source 1 and are marked as such. Anything taken only from a search snippet is marked UNVERIFIED. Equation symbols were extracted with `pdftotext -enc UTF-8`. Where the extraction garbled the layout, I say so.

Context arithmetic used in the inferences: T = 1 µs (1 Msym/s), so the frequency normalized to the symbol rate is ν = f·T. ±120 kHz gives |ν| ≤ 0.12. 5–22 kHz gives ν = 0.005–0.022.

---

## (a) Burst-mode data-aided frequency estimators using several autocorrelation lags (Kay, Fitz, L&R, M&M, delay-and-multiply; Schmidl & Cox)

### Takeaway
All the lag-based DA estimators work on the modulation-stripped preamble z(k) = r(k)·s*(k). They trade estimation range against accuracy through the number of lags N:
- Fitz: |ν| < 1/(2N)
- Luise & Reggiannini (L&R): |ν| < 1/(N+1)
- Delay-and-multiply at lag D: |ν| < 1/(2D)
- Mengali & Morelli (M&M) and Kay: about |ν| < 1/2, independent of N. M&M uses differences of successive autocorrelation phases.

Fitz, L&R and M&M reach the CRB at intermediate/high SNR but differ in range and threshold. Kay is biased below about 8 dB Es/N0. The ML/periodogram estimators have the lowest threshold. Their threshold improves by about 2–3 dB per doubling of the observation length.

### Cited Findings

**Common model (Bertolucci 2021, Sec. 3, pp. 5–6)**
- Received symbols are modeled as eq. (10), r(k) = x(k)e^{j(2πΔf kTs+θ(k))} + η(k). Modulation is removed with the known sequence, eq. (11) z(k) = r(k)·s*(k). "All algorithms under assessment are considered for a Data-Aided (DA) estimation approach based on symbol values". The estimate is normalized to the symbol rate: Δf = f̂·S_rate. — [Bertolucci et al. 2021, Sensors 21:2915, pp. 5–6](https://doi.org/10.3390/s21092915) ([open PDF](https://mdpi-res.com/d_attachment/sensors/sensors-21-02915/article_deploy/sensors-21-02915.pdf))
- Autocorrelation shared by Fitz, L&R, M&M and O'Shea, eq. (16): R(m) = (1/(L−m)) Σ_{k=m}^{L−1} z(k)z*(k−m), where L is the length of the known sequence. — [Bertolucci 2021, p. 7](https://doi.org/10.3390/s21092915)

**Delay-and-multiply (single lag D), eq. (12), p. 6**
- f̂ = (1/2πD) arg Σ_{k=D}^{L−1} z(k)z*(k−D).
- "It is known not to be so precise, particularly at low SNR, but it yields unbiased results and the normalized estimation region is |f̂| < 1/2D".
- It is usually used as the coarse stage, with a low D (e.g., 2), in a coarse-fine architecture (Fig. 3). — [Bertolucci 2021, p. 6, eq. (12), Fig. 3](https://doi.org/10.3390/s21092915)

**Kay (lag 1, weighted phase differences), eqs. (13)–(14), pp. 6–7**
- f̂ = (1/2π) Σ_{k=1}^{L−1} w(k) arg{z(k)z*(k−1)}, with w(k) = (3L/2)/(L²−1)·[1 − ((2k−L)/L)²].
- "it results to be biased for SNR under about 8 dB Es/N0". — [Bertolucci 2021, pp. 6–7](https://doi.org/10.3390/s21092915)
- Date conflict: Bertolucci calls it "developed by Steven Kay in 1987". The DOI record gives IEEE Trans. ASSP 37(12):1987–1990, 1989 (the "1987" is probably the page number). — [OpenAlex record for doi:10.1109/29.45547](https://api.openalex.org/works?search=A%20fast%20and%20accurate%20single%20frequency%20estimator)
- UNVERIFIED (search snippet of the URI repository record): Kay's estimator is "more computationally efficient than the optimal maximum likelihood estimator yet attains as good performance at moderately high signal-to-noise ratios". — [URI DigitalCommons record](https://digitalcommons.uri.edu/ele_facpubs/1387) (the record has no PDF, only the DOI)

**Fitz (N lags, sum of phases), eq. (15), p. 7**
- f̂ = [1/(πN(N+1))] Σ_{m=1}^{N} arg{R(m)}.
- "known for having very accurate and unbiased estimates even at low SNR. However, it also has the narrowest estimation window (|f̂| < 1/2N)".
- N "influences both the estimation window (the higher N, the narrower the window) and the frequency RMS error (the higher N, the lower the error)". — [Bertolucci 2021, p. 7](https://doi.org/10.3390/s21092915)

**Luise & Reggiannini (N lags, phase of the sum), eq. (17), p. 7**
- f̂ = [1/(π(N+1))] arg Σ_{m=1}^{N} R(m).
- It "guarantees a fairly wide estimation range (|f̂| < 1/(N + 1)) while providing low RMS error".
- "it can be implemented using an Finite Impulse Response (FIR) filter-like architecture". It is usually the fine stage of a coarse-fine receiver.
- With a high Doppler rate, "additional logic is needed to correctly unwrap the estimates". — [Bertolucci 2021, p. 7](https://doi.org/10.3390/s21092915)

**Mengali & Morelli (N lags, weighted differences of successive autocorrelation phases), eqs. (18)–(20), p. 8**
- f̂ = (1/2π) Σ_{m=1}^{N} w(m) arg{R(m)R*(m−1)}.
- As printed: w(m) = 3((L−m)(L−m−1) − N(L−N)) / (N(4N² − 6NL + 3L² − 1). The closing parenthesis is missing in the source.
- Equivalent form, eq. (20): f̂ = (1/2π) Σ w(m)[arg{R(m)} − arg{R(m−1)}]_{2π}, where [·]_{2π} is modulo 2π.
- Its range is "close to |f̂| < 1/2" and "unlike Fitz and L&R, its estimation range does not depend on the number of autocorrelation samples. The N parameter affects the RMS error only". — [Bertolucci 2021, pp. 7–8](https://doi.org/10.3390/s21092915)
- O'Shea et al. variant (moves the arg outside the weighted sum): "the estimator shows a loss with respect to M&M … but the estimation range borders are more consistent". — [Bertolucci 2021, p. 8](https://doi.org/10.3390/s21092915)
- UNVERIFIED (search snippet of the M&M 1997 abstract): "estimation range of about ±20% of the symbol rate and accuracy close to the Cramer-Rao bound for SNR as low as 0 dB". Another snippet attributes the same sentence to L&R, so the snippet attribution is inconsistent. This ±20% figure also differs from Bertolucci's "close to |f̂| < 1/2". — [OpenAlex/IEEE record doi:10.1109/26.554282](https://doi.org/10.1109/26.554282)

**Measured comparison (Bertolucci 2021, Sec. 5, pp. 14–16)**
- Setup: 256-symbol π/2-BPSK frame marker in AWGN. The range sweeps (Fig. 15) are at Eb/N0 = −0.52 dB (Es/N0 ≈ −2 dB).
- Kay is "not usable for space applications" there. Its error rises at low SNR "for all the ranges before the 11 dB value" (Fig. 17).
- Fitz has a range "very similar" to D&M, but the estimates are "more accurate (especially at low N values)" (p. 14).
- At N = 64 or 128, Fitz, L&R and M&M "converge to very similar results" (Fig. 16, p. 15).
- "L&R shows a non-perfectly flat estimate within the estimation range, which can be up to 1.5× the lower high-N value" (p. 15).
- D&M has "a 2× higher frequency RMS error" than Fitz/L&R at N = 16 and very low SNR.
- "the difference is about 2× between the M&M w.r.t. the Fitz or L&R … for N = 16 … (i.e., 1.29× at N = 64)" (Fig. 18, p. 16). The text does not state which estimator is better. — [Bertolucci 2021, pp. 14–16, Figs. 15–18](https://doi.org/10.3390/s21092915)

**Accuracy vs CRB, threshold, timing dependence (Morelli & D'Amico 2007)**
- On the time-domain correlation schemes ([12–15] = Fitz 1991, …, L&R 1995, M&M 1997): "These methods attain the Cramer-Rao lower bound (CRB) at intermediate/high SNRs, but exhibit different performance in terms of estimation range and threshold, that is, the SNR below which large estimation errors are likely to occur." — [Morelli & D'Amico 2007, EURASIP JWCN, p. 2](https://doi.org/10.1155/2007/65058) ([open PDF](https://jwcn-eurasipjournals.springeropen.com/counter/pdf/10.1155/2007/65058.pdf))
- Dependence on timing: "they all assume ideal timing synchronization. Their performance is thus limited by the accuracy of the timing estimator." — [Morelli & D'Amico 2007, p. 2](https://doi.org/10.1155/2007/65058)
- The NDA timing estimators they cite [7–9] "can operate correctly even in the presence of carrier frequency offsets (CFOs) as large as 20% of the symbol rate". — [Morelli & D'Amico 2007, p. 2](https://doi.org/10.1155/2007/65058)
- The earlier joint ML timing/frequency/phase estimator [16] needs "negligible phase rotations during the preamble duration. This poses a stringent limit to the maximum tolerable CFO". — [Morelli & D'Amico 2007, p. 2](https://doi.org/10.1155/2007/65058)
- Their own method uses an alternating-binary preamble in three steps:
  1. Frequency by a 1-D grid search, implemented with zero-padded FFTs ("pruning factor" K).
  2. Timing in closed form.
  3. Phase in closed form.

  The FFT search step is described in the bullets around eqs. (23)–(24) on p. 5. — [Morelli & D'Amico 2007, pp. 2–5](https://doi.org/10.1155/2007/65058)
- Threshold definition: "the MLE makes large errors (outliers) … The SNR below which the outliers start to occur is referred to as the threshold of the estimator." — [Morelli & D'Amico 2007, p. 5](https://doi.org/10.1155/2007/65058)
- CRB, eq. (30), large-N approximation of eq. (27), as extracted: CRB(ν) ≈ [3/(π²N³)]·(Es/N0)⁻¹ "which represents the CRB for the estimation of the frequency of a complex sinusoid embedded in AWGN". Here N is the observation length in symbols. The layout was garbled in extraction, so check the constant on p. 5. — [Morelli & D'Amico 2007, p. 5, eqs. (27)–(30)](https://doi.org/10.1155/2007/65058)
- Simulations at N = 32 and 64: "MLE has a lower threshold than R&B, especially for N = 64". "doubling N results into a threshold decrease of approximately 3 dB with MLE, while a gain of 2 dB is observed with R&B" (Rife & Boorstyn periodogram). — [Morelli & D'Amico 2007, p. 7, Fig. 8](https://doi.org/10.1155/2007/65058)
- Their conclusion: "at intermediate/high SNR values the conventional scheme is preferable as it achieves similar performance with reduced complexity". — [Morelli & D'Amico 2007, p. 8](https://doi.org/10.1155/2007/65058)

**Repeated-training (Schmidl & Cox / 802.11-style) range vs accuracy, via Rahbari 2016 (802.11a/g STS/LTS)**
- The FO estimate is the angle of the summed lag-L products, eqs. (1)–(4). The "phase is unambiguous and correctable as long as |Δf| < 1/(2Lts) (half a subcarrier spacing)". "a longer period of a cycle reduces the range of FO that can be corrected unambiguously".
- With LTS samples four times the STS samples, "thl = ths/4 = fΔ/2".
- "The above discussion reveals a tradeoff between the accuracy and range of the correctable FO." — [Rahbari, Krunz, Lazos 2016, IEEE TMC 15(5), Sec. 2.1; local file V7_Rahbari2016_Swift_Jamming_FO_Estimation_TMC.pdf](file:///C:/Users/Adi%20Suliman/Desktop/)

### Inferences
- Range constraint for |ν| ≤ 0.12, from the range formulas above (arithmetic only):
  - Fitz: N ≤ 4 (1/(2·4) = 0.125).
  - L&R: N ≤ 7 (1/8 = 0.125).
  - D&M: D ≤ 4.
  - M&M and Kay (lag 1): about ±0.5, which covers ±0.12 with any N.
  - Repeated training with period P symbols: about ±1/(2P), so P ≤ 4 to cover ±0.12 in a single stage. Larger P or N needs a coarse stage first, as in Bertolucci's Fig. 3 coarse-fine architecture.
- Size of the reported errors relative to the CRB, using eq. (30) as extracted at Es/N0 = 10 dB:
  - N = 32 gives σ ≈ 9.6×10⁻⁴·Rs ≈ 0.96 kHz.
  - N = 64 gives σ ≈ 3.4×10⁻⁴·Rs ≈ 0.34 kHz.
  - At 0 dB both are √10 larger (≈ 3.0 kHz and 1.1 kHz).

  Errors of 5–22 kHz with zero oscillator offset are therefore much larger than the CRB-level spread at moderate SNR. They behave like outliers or a bias, not like variance. This is consistent with the threshold/outlier mechanism defined by Morelli & D'Amico, or with a biased input (see (c)).
- Phase error implied by the same frequency error for a lag-m estimator: Δφ = 2π·ν·m.
  - 22 kHz (ν = 0.022) is about 7.9° at lag 1 and about 127° at lag 16.
  - Multi-lag estimators with large m (Fitz, L&R) therefore turn a given frequency error into large phase excursions at the high lags. Wrap-around at the high lags is the mechanism behind their narrow range.

### Gaps
- The original papers were not read: Fitz 1991/1994, L&R 1995, Kay 1989, M&M 1997, Schmidl & Cox 1997, Morelli & Mengali 1998 ETT tutorial. Not obtained from any read source:
  - The closed-form variance expressions of each estimator and the optimal lag counts (e.g., the commonly cited N = L/2 for Fitz/L&R/M&M).
  - Their exact SNR thresholds.
  - Their complexity counts.
- The M&M weight w(m) as printed by Bertolucci has the factor (L−m)(L−m−1) and a missing parenthesis. It was not checked against eq. in the original M&M 1997 paper, and the index convention needs checking there.
- Schmidl & Cox: the timing metric, the plateau/ambiguity, the variance of the fractional-CFO estimate, and the second-symbol integer-CFO step were not read from any source. Only the 802.11 STS/LTS restatement in Rahbari 2016 was read.
- No source read gives an outlier probability (P_outlier vs SNR) for any of the lag estimators.

---

## (b) Frequency and timing estimation in multi-antenna receivers under strong interference / jamming

### Takeaway
Within the sources read, the only interference-specific frequency-estimation analysis is Rahbari 2016. It is single-antenna 802.11 OFDM. It shows that the FO estimate is the angle of a summed autocorrelation. An interferer present in the training region adds cross terms, and with a structured (self-correlated) jamming waveform a power-weighted phasor at the jammer's own offset. That steers the estimate. No source on joint spatial whitening + CFO, ML CFO in colored noise, MIMO-OFDM CFO under co-channel interference, or robust M-/median estimators was read before the stop.

### Cited Findings
- Random-noise jamming of the STS: the summed autocorrelation becomes eq. (8), with cross terms r̃ᵢ*ũ_{L+i} and ũᵢ*(…). "The phase and amplitude of the second and third terms in (8) … are unknown". "FO jamming with a random signal cannot provide any FO distortion guarantees to beat LTS-based FO estimation." — [Rahbari et al. 2016, Sec. 4.2.1 item 1, eq. (8)](file:///C:/Users/Adi%20Suliman/Desktop/)
- Fake preamble with "identical halves" (self-correlated jamming waveform): the receiver's autocorrelation becomes eq. (14), A_fake = e^{−jΔφab}[Σ|r̃ᵢ|² + Σ|ũᵢ|² e^{−j(Δφeb−Δφab)}]. The estimate is the angle of the sum of the desired phasor and a jammer phasor at the jammer-to-receiver offset, weighted by the jammer power. With this the adversary "can induce a bit error rate close to 0.5". — [Rahbari et al. 2016, abstract, Sec. 4.2, eqs. (12)–(14)](file:///C:/Users/Adi%20Suliman/Desktop/)
- Two mitigations Rahbari lists for the single-antenna case:
  - Skipping the short-training FO stage and searching FO bins: "Bob can tolerate channel estimation errors due to an FO estimation error of up to 15 kHz … divide the range of possible FO values into several equal-size frequency bins, each of 30 kHz bandwidth". The bin "that results in the minimum MSE in channel estimation" is chosen.
  - Relying on pilots "often gives rise to ICI … and the FO estimation will be erroneous". — [Rahbari et al. 2016, mitigation item 3 "STS Bypassing"](file:///C:/Users/Adi%20Suliman/Desktop/)
- Dependence of frequency estimation on timing (relevant when interference corrupts timing first): conventional correlation frequency estimators "all assume ideal timing synchronization. Their performance is thus limited by the accuracy of the timing estimator." — [Morelli & D'Amico 2007, p. 2](https://doi.org/10.1155/2007/65058)
- UNVERIFIED (search snippet only): in MU-MIMO OFDM uplink CFO estimation, "different CFOs from different users destroy the orthogonality among training sequences and introduce multiple access interference (MAI), which causes an irreducible error floor in the CFO estimation". — [Springer, CFO estimation for MU-MIMO OFDM uplink using CAZAC sequences (2011)](https://link.springer.com/article/10.1155/2011/570680)
- UNVERIFIED (search snippet only): multi-invariance MUSIC blind CFO estimation for OFDM with a multi-antenna receiver. — [Wireless Personal Communications, 2010](https://link.springer.com/article/10.1007/s11277-010-0135-0)

### Inferences
- From eq. (14) of Rahbari: whatever survives in the samples used by an autocorrelation estimator enters as an additive phasor. That phasor equals the residual's own lag-m autocorrelation. Two cases follow:
  - A white (temporally uncorrelated) residual mostly adds variance through the cross terms (eq. (8)).
  - A temporally correlated residual adds a mean phasor whose phase is set by the residual's own spectral centroid. That biases the angle of the sum toward it.

  This is the same arithmetic for any lag estimator (D&M, Fitz, L&R, M&M), because all use R(m).
- Morelli & D'Amico tie the frequency estimate to timing accuracy. Interference that perturbs the arrival-time estimate therefore also degrades frequency estimates that assume ideal timing. Nothing read quantifies this under jamming.

### Gaps
- Not read (search stopped). No numbers were obtained (MSE vs SIR/INR, outlier probability) on any of these topics:
  - Joint spatial whitening + CFO estimation.
  - ML CFO estimation in colored/interference-plus-noise.
  - MIMO-OFDM CFO under co-channel interference.
  - Robust (M-estimator / median / trimmed) frequency estimators.
  - Decision-directed refinement.
- Sources already in Adi's folder (`מקורות`) that are likely relevant to (b) but were NOT read in this pass:
  - V7_Marti2024_JASS_Jammer_Resilient_Time_Sync_MIMO_arXiv.pdf
  - V7_Arquint2025_JASS_Sync_ASIC_65nm_arXiv.pdf
  - V7_Marti2023_Mitigating_Smart_Jammers_MU_MIMO.pdf
  - V7_Yan2016_Jamming_Resilient_MIMO_Interference_Cancellation_TIFS.pdf
  - V7_Zeng2017_Jamming_Resistant_MIMO_JrRx_CNS.pdf
  - V7_LaPan2016_OFDM_Acquisition_Timing_Sync_Security_WCMC.pdf
  - V7_Shahriar2015_PHY_Resiliency_OFDM_Tutorial_COMST_arXiv.pdf
  - V7_Castaneda2021_BeamSlicing_Jammer_Mitigation_LowRes_ADC.pdf
  - V7_Ogawa1983_Power_Inversion_Adaptive_Array.pdf
- Rahbari 2016 DOI was not checked in this pass. The journal header reads IEEE Trans. Mobile Computing 15(5), May 2016, first page 1264.

---

## (c) How a time-varying (Doppler-faded) interferer residual after whitening biases autocorrelation-based frequency estimators

### Takeaway
No source read analyzes this directly. The closest material read:
- Rahbari 2016 (eq. (14)): a self-correlated interferer in the training window adds a power-weighted phasor to the autocorrelation sum and steers the angle estimate.
- Bertolucci 2021: L&R needs unwrapping logic under high Doppler rate (of the desired signal).

The mechanism for a Doppler-faded jammer residual below is therefore an inference, not a sourced result.

### Cited Findings
- The estimate is the angle of a sum, and a structured interferer's lag product adds a phasor at its own offset, weighted by its power: eq. (14), A_fake = e^{−jΔφab}[Σ|r̃ᵢ|² + Σ|ũᵢ|² e^{−j(Δφeb−Δφab)}]. — [Rahbari et al. 2016, eq. (14)](file:///C:/Users/Adi%20Suliman/Desktop/)
- The random-waveform cross terms have "unknown" phase and amplitude (eq. (8)). — [Rahbari et al. 2016, eq. (8)](file:///C:/Users/Adi%20Suliman/Desktop/)
- High-Doppler-rate operation of a limited-range fine estimator (L&R) needs "additional logic … to correctly unwrap the estimates and track when they fall out of |f̂|". This is about desired-signal dynamics, not an interferer. — [Bertolucci 2021, p. 7](https://doi.org/10.3390/s21092915)

### Inferences
- Hypothesis, consistent with the Rahbari eq. (14) arithmetic but not tested in any source read:
  - The whitening covariance is estimated in a 32-symbol quiet slot. The jammer channel then changes before or during the training region. The whitened output then holds a residual jammer term proportional to the channel change.
  - Over a short training block (tens of symbols at 1 µs) a channel fading at ≤ 358 Hz changes little. So the residual's lag-m autocorrelation (for m ≪ 1/(fD·T) ≈ 2800 symbols) keeps close to its lag-0 power, multiplied by the jammer waveform's own lag correlation.
  - If the jammer waveform has non-negligible lag correlation, i.e. it is not white over the receiver band, the residual adds a mean phasor at the jammer's apparent frequency. The angle of R(m) is biased in proportion to the residual-to-signal power ratio and the jammer's lag correlation.
  - This fits the observed pattern: no failures with a static jammer channel (no residual), failures with a faded channel (residual).
- Under this hypothesis the multi-lag estimators would weight the residual differently:
  - L&R sums R(m) before the angle, so the residual phasors add coherently across lags.
  - M&M takes differences of successive autocorrelation phases. A residual with slowly varying lag phase partly cancels in arg{R(m)R*(m−1)}, but not if its frequency differs from the signal's.

  This is untested reasoning, not a sourced result.
- Required size of the corrupting phasor (arithmetic): a 22 kHz error at lag 1 (≈7.9°) needs a residual phasor of roughly sin(7.9°) ≈ 0.14 of the desired lag-1 autocorrelation magnitude if it is in quadrature, and more if it is not.

### Gaps
- No source read was found that quantifies:
  - The bias of Fitz, L&R, M&M or Kay estimators from a residual interferer with a non-white spectrum.
  - The whitening residual as a function of jammer Doppler and covariance age.
  - Any MSE/outlier numbers vs SIR/INR for this case.
- Not sourced in this pass: the classic Jakes channel correlation (J0(2πfDτ)) and the stale-covariance (moving-jammer, covariance-matrix-taper/null-widening) literature that would quantify residual vs covariance age.
- Candidate original references seen only in a read bibliography (Spanish project bibliography, biblus.us.es), not read:
  - Morelli, Mengali and Vitetta, "Further results in carrier frequency estimation for transmissions over flat fading channels", IEEE Communications Letters 2(12), Dec. 1998.
  - Morelli and Mengali, "Carrier-frequency estimation for transmissions over selective channels", IEEE Trans. Commun. 48(9), Sep. 2000.

  Source: [Universidad de Sevilla project bibliography (Appendix 3)](https://biblus.us.es/bibing/proyectos/use/abreproy/10403/fichero/biblo.pdf). DOIs not checked.

### COULD NOT DOWNLOAD
No open copy was found before the stop. Further attempts were stopped at the coordinator's instruction. DOIs were confirmed through OpenAlex records. The IEEE Xplore links use the DOI suffix as the document number (the usual convention for these older IEEE papers). The DOI link is the authoritative one.

1. U. Mengali, M. Morelli, "Data-aided frequency estimation for burst digital transmission", IEEE Trans. Commun. 45(1):23–25, 1997.
   - DOI 10.1109/26.554282 — https://ieeexplore.ieee.org/document/554282
2. M. Luise, R. Reggiannini, "Carrier frequency recovery in all-digital modems for burst-mode transmissions", IEEE Trans. Commun. 43(2/3/4):1169–1178, 1995.
   - DOI 10.1109/26.380149 — https://ieeexplore.ieee.org/document/380149
   - The Aalto course copy requires a login: https://mycourses.aalto.fi/pluginfile.php/1285406/mod_folder/content/0/luise-carrier-frequency.pdf
3. M. P. Fitz, "Further results in the fast estimation of a single frequency", IEEE Trans. Commun. 42(2/3/4):862–864, 1994.
   - DOI 10.1109/TCOMM.1994.580190 — https://ieeexplore.ieee.org/document/580190
4. M. P. Fitz, "Planar filtered techniques for burst mode carrier synchronization", Proc. IEEE GLOBECOM 1991, pp. 365–369.
   - DOI 10.1109/GLOCOM.1991.188412 — https://ieeexplore.ieee.org/document/188412
5. S. Kay, "A fast and accurate single frequency estimator", IEEE Trans. ASSP 37(12):1987–1990, 1989.
   - DOI 10.1109/29.45547 — https://ieeexplore.ieee.org/document/45547
   - The URI repository record has no PDF: https://digitalcommons.uri.edu/ele_facpubs/1387
6. T. M. Schmidl, D. C. Cox, "Robust frequency and timing synchronization for OFDM", IEEE Trans. Commun. 45(12):1613–1621, 1997.
   - DOI 10.1109/26.650240 — https://ieeexplore.ieee.org/document/650240
7. M. Morelli, U. Mengali, "Feedforward frequency estimation for PSK: A tutorial review", European Trans. Telecommun. 9(2):103–116, 1998.
   - DOI 10.1002/ett.4460090203 — https://onlinelibrary.wiley.com/doi/10.1002/ett.4460090203
8. U. Mengali, A. N. D'Andrea, Synchronization Techniques for Digital Receivers (Springer/Plenum, 1997).
   - Chapter DOI 10.1007/978-1-4899-1807-9_3 appeared in search results; the chapter title is UNVERIFIED — https://doi.org/10.1007/978-1-4899-1807-9_3
9. M. Morelli, U. Mengali, G. M. Vitetta, "Further results in carrier frequency estimation for transmissions over flat fading channels", IEEE Commun. Lett. 2(12), 1998.
   - DOI not checked; search IEEE Xplore by title.
10. M. Morelli, U. Mengali, "Carrier-frequency estimation for transmissions over selective channels", IEEE Trans. Commun. 48(9), 2000.
    - DOI not checked; search IEEE Xplore by title.
