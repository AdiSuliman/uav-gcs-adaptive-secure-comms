# Pulsed / Bursty Interference: Adaptive Arrays, Blanking/Erasure Decoding, Interleaving + FEC

Scope: how adaptive arrays and receivers handle interference whose power switches on and off within a frame, plus source-backed tracking and erasure strategies. Research notes only, with no design decisions.

Context, for relevance only: a 2.4 GHz UAV command link using QPSK at 1 Msym/s, with frames of about 1000 symbols. The receiver has 3 omni antennas and uses MMSE combining. Its covariance is estimated from a 32-symbol quiet slot or from the training region. The pulsed jammer has 16 dB JSR, a 30 % duty cycle and a 100-symbol period. It breaks 23 of 120 frames with the real receiver and none with an ideal receiver, meaning one given the true per-symbol covariance.

Conventions:
- "Read" means I read the full text: the PDF was converted with pdftotext and searched with grep.
- "Abstract only" means I read only the publisher or repository abstract.
- UNVERIFIED means the information comes only from a search snippet.
- pdftotext dropped Greek letters and some sub- and superscripts. Wherever I put a symbol back into a quote, it appears in [square brackets].

---

## Q1. Adaptive arrays vs pulsed/blinking jammers: failure mode and countermeasures

### Takeaway
The failure mode is well documented. If the covariance or jammer subspace is estimated from a subset of samples during which the jammer is silent (a quiet or training slot), the null is placed from noise only. Performance then falls to that of an unmitigated receiver.

Two kinds of countermeasure appear in the sources:
- Using the whole coherence interval or frame rather than a dedicated slot (joint estimation and detection).
- Weight-memory schemes. The TRW patent calls this "fast-attack / slow-release" nulling: the null is kept through the off-time. Hoo (1991) adds real-time change detection, a convergence time matched to the blinking rate, and recall of earlier weights.

I found no open, quantitative paper comparing RLS forgetting factors or sliding windows against a pulsed jammer.

### Cited Findings

**Failure mode: estimating the jammer from a slot it does not occupy**
- Marti, Kölle & Studer, "Mitigating Smart Jammers in Multi-User MIMO", IEEE Trans. Signal Process. (arXiv:2208.01453v3, 2023). Read.
  - Problem statement (Sec. I, p. 1): "a smart jammer might jam the system only at specific time instants, such as when the UEs are transmitting data symbols, and thereby prevent the BS from estimating the jammer's channel using simple estimation algorithms." — [arXiv 2208.01453](https://arxiv.org/pdf/2208.01453)
  - Same section: "A smart jammer can evade estimation and thus circumvent mitigation by not transmitting during the training phase, for instance because it is aware of the defense mechanism or simply because it jams in short bursts only." — [arXiv 2208.01453](https://arxiv.org/pdf/2208.01453)
  - Baseline "POS" receiver (Sec. III, p. 3–4): it estimates the jammer subspace "based on ten receive samples in which the UEs do not transmit and only the jammer is active". It takes the dominant left singular vector of those samples and then projects onto the orthogonal complement. — [arXiv 2208.01453](https://arxiv.org/pdf/2208.01453)
  - When the jammer is active in that slot (Fig. 2(a)), POS "still mitigates the jammer with a loss of less than 2 dB in SNR (at 0.1% BER) compared to the jammer-free JL-LMMSE receiver." — [arXiv 2208.01453](https://arxiv.org/pdf/2208.01453)
  - When the jammer goes silent during that slot (Fig. 2(b), Sec. III): "The POS receiver's subspace estimate is thus based entirely on noise and is completely independent of the jammer's true channel j. Consequently, the mitigation mechanism fails spectacularly, yielding a bit error-rate identical to the non-mitigating LMMSE receiver." — [arXiv 2208.01453](https://arxiv.org/pdf/2208.01453)
  - Generalization (Sec. IV): "The foregoing example has demonstrated the danger of estimating the jammer's subspace (or other characteristics of the jammer, such as its spatial covariance) based on a certain subset of receive samples when facing a smart jammer." — [arXiv 2208.01453](https://arxiv.org/pdf/2208.01453)
  - Fig. 2 setup: B = 128 BS antennas, U = 32 UEs, 16-QAM, i.i.d. Rayleigh. The jammer's receive power exceeds that of the average UE by 30 dB. — [arXiv 2208.01453](https://arxiv.org/pdf/2208.01453)

**Countermeasure: whole-interval joint estimation (MAED / SO-MAED)**
- Same paper. The method "does not depend on the jammer being active during any specific period". It considers "the receive signal over an entire coherence interval at once and exploiting the fact that the jammer subspace stays fixed within that period, regardless of the jammer's activity pattern or transmit sequence" (Sec. IV). — [arXiv 2208.01453](https://arxiv.org/pdf/2208.01453)
- Four jammer types are tested (Sec. VII-A):
  - (J1) barrage
  - (J2) pilot-only
  - (J3) data-only
  - (J4) "sparse jammers that transmit i.i.d. jamming symbols during some fraction [α] of randomly selected bursts of unit length (i.e., one time slot)"
  - Duty cycle [α] "equals 1, T/K, D/K, or [α]" for these types respectively, with K = T + D.
  - Strength is defined either as total energy ratio E (Eq. 40) or as on-phase power P = E/[α] (Eq. 41).
  — [arXiv 2208.01453](https://arxiv.org/pdf/2208.01453)
- Results for QPSK with a strong jammer:
  - Fig. 5 caption: "Uncoded bit error-rate (BER) for QPSK transmission in the presence of a strong (E = 30 dB) jammer which transmits Gaussian symbols (a) during the entire coherence interval, (b) during the pilot phase only, (c) during the data phase only, or (d) in random unit-symbol bursts with a duty cycle of [α] = 20%." — [arXiv 2208.01453](https://arxiv.org/pdf/2208.01453)
  - Sec. VII-C: the jammer-oblivious LMMSE baseline is much worse in all scenarios, "with the data jamming attack turning out to be the most harmful and the pilot jamming attack the least harmful." — [arXiv 2208.01453](https://arxiv.org/pdf/2208.01453)
  - Sec. VII-C: "SO-MAED and MAED approach the performance of the jammerless and MU interference-free JL-SIMO bound to within less than 2 dB and 3 dB at 0.1% BER, respectively, in all considered scenarios." — [arXiv 2208.01453](https://arxiv.org/pdf/2208.01453)
- Cost of a dedicated jammer-estimation slot (Remark 1, Sec. III): "Reserving time slots for jammer estimation in which the UEs cannot transmit reduces the achievable data rates." — [arXiv 2208.01453](https://arxiv.org/pdf/2208.01453)

**Countermeasure: weight memory and "fast-attack / slow-release" nulling against blinking jammers (TRW patent)**
- The source is J. E. DuPree (TRW), US Patent 5,175,558, "Nulling system for constraining pulse jammer duty factors", issued 29 Dec 1992 (filed 10 Feb 1992). I read the full text: Google Patents HTML plus the PDF, with background in cols. 1–2. This is an inventor's statement in a patent and was not peer reviewed.
  - "During nulling, the communication link requires protection against jammer bursts. Coding techniques such as forward error correction coding with interleaving can provide this protection only if the duty factor of the high power bursts is less than a critical value. This critical value is a function of coding complexity and modulation format." — [US5175558](https://patents.google.com/patent/US5175558A/en)
  - "To obtain a small duty factor of the high gain state presented to the jammer by the adaptive antenna requires a fast-attack/slow-release nulling transient response. Direct approaches such as direct matrix inversion and conjugate-gradient methods, lack this 'null memory' characteristic and recover too quickly." — [US5175558](https://patents.google.com/patent/US5175558A/en)
  - "Blinking jammers may try pseudo random on-off modulation and power level control strategies. Real-time scaling, at the iteration rate, combats non-stationary power levels and retains consistent 'fast-attack' characteristics." — [US5175558](https://patents.google.com/patent/US5175558A/en)
  - "Faster nulling reduces burst lengths and therefore requires a smaller interleaver to protect the communication link until the adaptive antenna forms nulls." — [US5175558](https://patents.google.com/patent/US5175558A/en)
  - "'Slow release' of null patterns insures a guardband of low gain between jammer bursts sufficient to keep the duty-cycles in this range." — [US5175558](https://patents.google.com/patent/US5175558A/en)
  - "Fast-attack/slow-release transient characteristics depend on retaining a spread between eigenvalues of the iteration matrix in the on-off and off-states of the blinking jammer." — [US5175558](https://patents.google.com/patent/US5175558A/en)
  - Power-threshold gating: "it is more efficient to allow some margin for low powered interference and apply scaling only if the noise power level exceeds a given threshold." The abstract describes the algorithm as "a successive over-relaxation type algorithm featuring scaling, eigenvalue shifting, and adaptive memory to give a fast attack time and slow release". — [US5175558](https://patents.google.com/patent/US5175558A/en)

**Countermeasure: change detection, matched convergence time and weight recall (Howells–Applebaum)**
- Hoo, "Adaptive Satcom antenna performance against blinking jammers", IEEE AP-S Symposium (DOI 10.1109/APS.1991.175000; OpenAlex lists the year as 2002). Abstract only, read via the OpenAlex record.
  - "First, changes in the jamming environment must be detected in real time, and the information must be fed immediately to the adaptive processor. Secondly, the processor must be capable of making changes in the algorithm convergence time to match the blinking rates of jammers. The processor must then be able to recall previous weight values and to reset weights as necessary." — [DOI 10.1109/APS.1991.175000](https://doi.org/10.1109/aps.1991.175000)

**Countermeasure: single-snapshot "direct data domain" (D3) processing for transient environments**
- Sarkar, Wang, Park et al., "A deterministic least-squares approach to space-time adaptive processing (STAP)", IEEE Trans. Antennas Propag. 49(1), 2001. Abstract only.
  - "Conventional STAP generally utilizes statistical methodologies based on estimating a covariance matrix of the interference using data from secondary range cells... assumed to be wide sense stationary. However for highly transient and inhomogeneous environments the conventional statistical methodology is difficult to apply." The nonhomogeneous environment considered "could include blinking jammers". — [DOI 10.1109/8.910535](https://doi.org/10.1109/8.910535)

**Antenna array combined with pulse blanking (GNSS L5/E5)**
- Konovaltsev, De Lorenzo, Hornbostel & Enge, "Mitigation of Continuous and Pulsed Radio Interference with GNSS Antenna Arrays", ION GNSS 2008, pp. 2786–2795. Abstract only; the PDF requires authorization.
  - "In an antenna array system, more efficient mitigation of pulsed interference can be obtained by adding the spatial domain to the signal processing."
  - "The combination of the adaptive array processing with the pulse blanking has been examined showing that the simple-to-implement pulse blanking can noticeably improve the overall performance in pulsed interference scenarios."
  - MVDR (with a directional constraint) and MMSE STAP were compared, including the effect of the number of time taps.
  — [DLR elib 58351](https://elib.dlr.de/58351/)

**Classical adaptive-array analysis (UNVERIFIED)**
- R. T. Compton Jr. (Ohio State ElectroScience Lab), DTIC report ADA106545 on pulsed interference against an adaptive array. Snippet only, because DTIC returned 403 or "Under Maintenance". The search snippet paraphrased: "pulsed interference is not as great a problem for an adaptive array as previously imagined", and "desired signal envelope modulation produced by pulsed jamming being small unless the jammer arrives very close in angle to the desired signal". — UNVERIFIED, [DTIC ADA106545](https://apps.dtic.mil/sti/pdfs/ADA106545.pdf)

**Data-interval regularization for intermittent interference (UNVERIFIED)**
- A University of Surrey record on asynchronous or intermittent interference, snippet only. The snippet says conventional beamformers "designed over the training interval may lose efficiency when applied to the data interval". The proposal regularizes with "covariance matrices estimated over the data interval" and uses ML optimization of "mixed covariance matrices". — UNVERIFIED, [Surrey Open Research](https://openresearch.surrey.ac.uk/permalink/44SUR_INST/15d8lgh/alma99598021202346)

### Inferences
- The project's symptom matches the documented mechanism (Marti et al., Fig. 2(b)). A 32-symbol quiet slot, or a training region, with a 30 %-duty / 100-symbol-period jammer can be wholly or partly inside the jammer's off-time, depending on the pulse phase relative to the slot. In that case the estimated covariance lacks the jammer's spatial signature, and the MMSE weights do not null it during the on-time. This would explain why the true per-symbol covariance breaks no frames while the estimate breaks some.
- Marti et al. show that the jammer subspace stays fixed within a coherence interval even when its power switches on and off. A spatial signature collected over a longer, frame-wide window therefore contains the jammer whenever it was active at any time in the window. This holds whether the window is the whole frame or a sliding window spanning at least one jammer period (100 symbols). This is the principle behind whole-interval methods. It is my inference that a sliding window of at least one period would contain the on-time; no source tested that specific window length.
- The DuPree patent and Hoo's abstract both say an adaptive processor against blinking jammers needs memory: hold the null through the off-time, or recall earlier weights. They also call for detection of power changes and a convergence time matched to the blink rate. These are the qualitative counterparts of "power-gated updates" and "separate on/off covariances". Neither source gives numbers in the open text.

### Gaps
- I found no open source with quantitative results (dB or BER) for RLS with a forgetting factor λ, or for sliding-window SMI, against a pulsed jammer of known duty cycle and period. I also found no explicit separate-on/off-covariance design with numbers.
- I could not read Compton's classical analyses (IEEE Trans. AES 1982; Ohio State/DTIC reports) because DTIC blocked automated access. Their numbers remain UNVERIFIED.
- I did not read STAP texts (Ward 1994; Guerci) for "blinking jammer" numbers; no open copies were reached.

---

## Q2. Pulse blanking, erasure decoding and soft decisions (LLR scaling by per-symbol interference)

### Takeaway
Time-domain blanking against pulsed interference is standard in GNSS L5/E5a (DO-292) and in LDACS. A sample whose envelope power is above a threshold is set to zero. The cost model is analytic: the effective noise PSD rises by 1/(1 − bdc), plus a term for residual below-threshold interference.

For coded links, knowing which symbols are jammed (jammer state information, JSI) matters:
- With JSI, the decoder uses per-symbol noise variances in the LLRs, or erasures.
- Without JSI, the decoder uses one average variance with clipping.
- The open sources give these numbers:
  - TRW patent: rate-1/2 Viterbi with pseudo-random interleaving loses only about 1 dB up to 10 % duty with erasure decoding, but only up to 1 % with errors-only decoding (inventor's claim).
  - Brandes et al.: blanking compensation in OFDM gets within 1.2 dB of ideal.
  - GNSS hot spot: blanking duty cycle about 0.62 for a C/N0 degradation of about 5.5–6.2 dB.

### Cited Findings

**GNSS temporal blanker: definition and cost model**
- Garcia-Pena, Julien, Macabiau, Mabilleau & Durel, "GNSS degradation model in presence of continuous wave and pulsed interference", NAVIGATION 68(1):75–91, 2021 (DOI 10.1002/navi.405, open access). Read.
  - Blanker definition (p. 76): it compares "the incoming signal envelope power with a threshold and to blank (set to zero) the time samples, which are above". — [NAVI 68(1):75](https://navi.ion.org/content/navi/68/1/75.full.pdf)
  - Mechanism (p. 79): "Part of the signal is removed due to the blanking and since the impact on the removed useful signal power, (1 − [bdc])², is higher than the impact on the power of the noise, (1 − [bdc]), the equivalent N0,eff can be seen to be increased by a factor of 1/(1 − [bdc]). [bdc] is the blanker duty cycle, or in other words, the percentage of time the incoming signal is blanked." — [NAVI 68(1):75](https://navi.ion.org/content/navi/68/1/75.full.pdf)
  - Second effect, same page: "Not all the RFI signal samples have a power above the threshold; therefore, there is a part of the RFI signal that is not removed, and its influence must be added to the thermal noise". — [NAVI 68(1):75](https://navi.ion.org/content/navi/68/1/75.full.pdf)
  - Compact DO-292 model (Eq. 7, p. 80), with symbols reconstructed from the garbled extraction: N0,eff = N0/(1 − bdc) · (1 + I0,WB/N0 + R_I). Here R_I = Σ R_I,i (Eq. 8) is the total below-threshold interference-to-thermal-noise ratio, and I0,WB is continuous wideband interference. — [NAVI 68(1):75](https://navi.ion.org/content/navi/68/1/75.full.pdf)
  - Table V, p. 90, US hot spot (RTCA DO-292 table E-8), 20 MHz filter. The values are DO-292 table / DO-292 analytical / proposed / simulated:
    - bdc: 0.6121 / 0.6190 / 0.6190 / 0.6195
    - C/N0 degradation: 5.99 / 6.22 / 5.53 / 5.59 dB
    - Row labels were lost in extraction. I identified the rows from the surrounding text, which says bdc results "are the same for any" method.
    — [NAVI 68(1):75](https://navi.ion.org/content/navi/68/1/75.full.pdf)
  - Pulse rates (p. 89): DME and TACAN maximum pulse-pair repetition frequencies are "2,700 and 3,600 pairs of pulse per second, respectively". — [NAVI 68(1):75](https://navi.ion.org/content/navi/68/1/75.full.pdf)
- "GNSS L5/E5a Code Properties in the Presence of a Blanker", NAVIGATION 72(2), navi.700. UNVERIFIED (snippet only): blanking duty cycles of 0–75 % over 1 ms integration were analyzed. Auto- and cross-correlation protection is reduced but stays "superior to those of L1 C/A codes until bdc reaches approximately 60%". — UNVERIFIED, [NAVI navi.700](https://navi.ion.org/content/72/2/navi.700)

**Pulse blanking in an aeronautical data link (LDACS1, OFDM, DME interference)**
- Epple, Hoffmann & Schnell, "Modeling DME interference impact on LDACS1", ICNS 2012. The elib landing page titles it "Influence of DME Interference onto LDACS1 – Feasibility Study for Europe". Read.
  - "we focus on pulse blanking (PB), since it is easy to implement, while providing a remarkable performance gain. However, PB induces ICI, limiting the performance gain of PB." — [DLR elib 75264 PDF](https://elib.dlr.de/75264/1/177epple.pdf)
  - "When applying PB all parts of the received signal, which exceed a certain pre-defined threshold, are set to zero." The threshold "has to be selected as a trade-off". — [DLR elib 75264 PDF](https://elib.dlr.de/75264/1/177epple.pdf)
  - The link budget carries a "Blanking Loss Margin" of 6 dB (table, p. 4). Joint blanking ratio across independent DME stations: K_av = 1 − Π(1 − B_l) (Eq. 11). — [DLR elib 75264 PDF](https://elib.dlr.de/75264/1/177epple.pdf)
- Brandes, Epple & Schnell, "Compensation of the Impact of Interference Mitigation by Pulse Blanking in OFDM Systems", IEEE Globecom 2009. Abstract only; the PDF requires authorization.
  - "Consequently, only moderate improvements are achieved with pulse blanking."
  - "With real channel estimation and estimated data symbols, the ideal case with perfect channel estimation and known data symbols is approached by 1.2 dB after only three iterations."
  — [DLR elib 59449](https://elib.dlr.de/59449/)
- Schnell, Brandes, Gligorevic, Walter et al., "Interference Mitigation for Future L-band Digital Aeronautical Communications System", DASC 2008. Abstract only.
  - "two efficient methods for mitigating the impact of interference are proposed and investigated for the B-AMC system, namely pulse blanking and erasure based decoding... The impact of interference is mitigated by means of the proposed methods, resulting in a performance close to the performance in the interference-free case." No numbers in the abstract. — [DLR elib 54915](https://elib.dlr.de/54915/)
- Epple & Schnell, "Mitigation of Impulsive Interference for LDACS1 – Potentials of Blanking Nonlinearity", ICNS 2015 (DOI 10.1109/ICNSURV.2015.7121346). Abstract only.
  - "A common approach for mitigation such impulsive interference is to apply a memoryless blanking nonlinearity (BN)... Any parts of a received signal with a magnitude exceeding this threshold are considered interference and are subsequently blanked." — [DLR elib 95642](https://elib.dlr.de/95642/)

**JSI-aware LLRs vs average-variance LLRs (pulsed jamming, short codes)**
- Baldi, Bianchi, Chiaraluce, Garello, Maturo, Aguilar Sanchez & Cioni (Univ. Politecnica delle Marche / Politecnico di Torino / ESA-ESTEC), "Advanced coding schemes against jamming in telecommand links", arXiv:1310.0721, 2013. Read.
  - Pulsed jamming model (Sec. II-A): pulse "active time D and period T", duty cycle "[ρ] = D/T", "power J_P during the active time D, and zero for the remaining time T − D". The equivalent continuous jammer has J = [ρ]J_P. — [arXiv 1310.0721](https://arxiv.org/pdf/1310.0721)
  - JSI definition (Sec. VI): "For soft-decision decoding, the knowledge of the jamming state can play a relevant role. For the case of pulsed jamming, for example, to have JSI means to know the noise variance for each symbol." — [arXiv 1310.0721](https://arxiv.org/pdf/1310.0721)
  - With perfect JSI the receiver identifies the jammed fraction [ρ] and the clean fraction 1 − [ρ] and uses their separate variances. The variances are σ²_ρ = N0/2 + J0/(2ρ) and σ²_{1−ρ} = N0/2 (symbols reconstructed). — [arXiv 1310.0721](https://arxiv.org/pdf/1310.0721)
  - Without JSI: "the variance used for LLR calculation of the decoder input is always equal to the average value N0/2 + J0/2". — [arXiv 1310.0721](https://arxiv.org/pdf/1310.0721)
  - Clipping without JSI: "to limit the impact of the incorrect noise estimation a clipping threshold, equal to twice the amplitude, has been applied to the signal at the channel output". — [arXiv 1310.0721](https://arxiv.org/pdf/1310.0721)
  - Test conditions (Figs. 5–8): [ρ] = 0.5, Eb/N0 = 10 dB, variable Eb/J0, with and without ideal interleaver and JSI. Codes: (128,64) LDPC, non-binary LDPC, parallel turbo and eBCH. Exact gains are only in the figures and not quoted in the text. — [arXiv 1310.0721](https://arxiv.org/pdf/1310.0721)
  - Conclusion (Sec. VIII): "The adoption of soft-decision decoding, combined with interleaving and JSI, allows to achieve significant improvements." — [arXiv 1310.0721](https://arxiv.org/pdf/1310.0721)
  - Legacy code: the hard-decision BCH(63,56) code is "rather poor" against pulsed jamming (Figs. 1–2, Eb/J0 = 10 dB). — [arXiv 1310.0721](https://arxiv.org/pdf/1310.0721)

**Erasure vs errors-only decoding with interleaving (TRW patent)**
- DuPree, US 5,175,558 (1992), cols. 1–2. Inventor's statement, not peer reviewed.
  - "rate-1/2 Viterbi-decoded convolutional code using pseudo-random interleaving lose only one dB of margin for duty cycles of 10% or less with erasure decoding and 1% for errors-only decoding. My analyses of other, practical, burst-coded channels show similar results, except that a trade-off is allowed between power level and duty-factor." — [US5175558](https://patents.google.com/patent/US5175558A/en)

**Threshold-based erasure flagging (random bit-level jamming)**
- Ercan, Galligan, Starobinski, Médard, Duffy & Yazicigil, "GRAND-EDGE: A Universal, Jamming-resilient Algorithm with Error-and-Erasure Decoding", arXiv:2301.09778, 2023. Read.
  - Erasure flagging rule (Sec. IV): "any signal that is observed within 3 standard deviations of the modulated signal space is considered non-jammed, and is jammed otherwise." — [arXiv 2301.09778](https://arxiv.org/pdf/2301.09778)
  - Jammer model: AWGN with a variance "far greater than that of the channel AWGN". It is applied per bit with Bernoulli probability. — [arXiv 2301.09778](https://arxiv.org/pdf/2301.09778)
  - Results: with RLC(128,105), "EDGE variants lower both the Block Error Rate (BLER) and the computational complexity by up to five order of magnitude compared to the original GRAND and ORBGRAND algorithms". There is "an improvement of up to three orders of magnitude in the BLER" vs OSD. Bit-jamming probabilities were 0.02, 0.05 and 0.10. — [arXiv 2301.09778](https://arxiv.org/pdf/2301.09778)
  - Interleaving: "frame-level jamming or erasures... can also be converted to bit-level erasures by simple interleaving techniques". — [arXiv 2301.09778](https://arxiv.org/pdf/2301.09778)

### Inferences
- The Garcia-Pena model gives a closed-form price for blanking: 10·log10(1/(1 − bdc)). At bdc = 0.30 that is about 1.55 dB, before any residual below-threshold interference. I computed this from Eq. 7; it is not stated in the source for 0.30.
- The project's jammer has a 30 % duty cycle. By the patent's figures this is beyond the 10 % duty for about 1 dB loss with erasure decoding and far beyond the 1 % for errors-only decoding. The patent's numbers are for its own (unstated) power level and code. They are indicative and do not transfer directly.
- Baldi et al. define JSI as per-symbol noise-variance knowledge, which is exactly per-symbol LLR scaling. Their no-JSI fallback is a single average variance plus clipping at twice the amplitude. These two give the bracketing reference receivers for an "erasure-aware soft decision" study.

### Gaps
- I did not obtain open numbers for a single-carrier QPSK link with rate-1/2 convolutional code, pulsed jamming and JSI vs no JSI at about 30 % duty. Baldi's numbers are in figures only, and Viterbi's 1979 IEEE Comm. Mag. article was not accessible.
- I did not read Grabowski & Hegarty (ION GPS 2002) or Bastide et al. (2004) for L5 blanking numbers (paywalled ION papers).
- The Epple PhD thesis (DLR elib 101433) and Konovaltsev 2008 PDFs require DLR authorization, so they were not read.

---

## Q3. Interleaving + FEC against periodic burst interference: depth vs burst length/period

### Takeaway
Classical theory:
- A block interleaver of depth λ built on a code correcting bursts of length l corrects any single burst of length up to λl. For a single-error-correcting code, that is bursts up to λ.
- The sources also require a guard interval: in the classic burst channel the error-free gap (guardband) must be long relative to the burst. The TRW patent claims rate-1/2 RS codes plus interleavers can correct all bursts when the guardband-to-burst ratio is at least 3.
- The depth needed scales with the burst or fade duration in symbols (JPL: depth "on the order of" the fade length).
- Finite depth costs a few tenths of a dB compared with ideal interleaving in JPL's Galileo analysis.
- Real interleavers can neutralize a 100-bit burst (Baldi, 64×64 row-column interleaver).

### Cited Findings

**Interleaved-code burst correction (lecture notes)**
- NYCU course notes, "Chapter 5 Interleaving Technique and Concatenation" (CC2011), slides 3–6. Read; author not stated on the slides. λ symbols restored.
  - "Suppose C is s[a] single-error-correcting code. Then a burst of length [λ] or less, no matter where it starts, will affect no more than one digital in each roe [sic]... Hence the interleaved code C([λ]) is capable of correcting any error burst of length [λ] or less." — [NYCU CC2011 Ch.5](https://mcube.lab.nycu.edu.tw/wiki/core/uploads/Course/CC2011/5.pdf)
  - "Suppose the base code C is capable of correcting any burst of length l or less... Hence the interleaved code C([λ]) is capable of correcting any single error burst of length [λ]l or less." — [NYCU CC2011 Ch.5](https://mcube.lab.nycu.edu.tw/wiki/core/uploads/Course/CC2011/5.pdf)
  - "Convolutional interleavers are better matched for use with the class of convolutional codes." — [NYCU CC2011 Ch.5](https://mcube.lab.nycu.edu.tw/wiki/core/uploads/Course/CC2011/5.pdf)

**Guardband-to-burst ratio (TRW patent)**
- DuPree, US 5,175,558 (1992), cols. 1–2, inventor's statement.
  - "In the classic burst channel, the period between jammer bursts when the channel is error-free, is called the guardband. Rate-one half Reed-Solomon codes and interleavers can be designed to correct all burst errors with a guardband/burst-duration ratio as small as three." — [US5175558 PDF](https://patentimages.storage.googleapis.com/97/88/41/56865905b317ec/US5175558.pdf)

**Ideal vs finite interleaver against pulsed jamming (Baldi et al.)**
- Baldi et al., arXiv:1310.0721.
  - Ideal-interleaver abstraction (Sec. II-A): "if a burst of errors corresponds to a fraction [ρ] of the symbols, its impact after de-interleaving is modeled as a probability [ρ], for each symbol, of having a higher noise variance." — [arXiv 1310.0721](https://arxiv.org/pdf/1310.0721)
  - Rationale: "most of the forward error correction schemes are designed for an AWGN channel which exhibits no memory. They do not handle bursts of errors. An interleaver distributes a burst of errors among many consecutive codewords." — [arXiv 1310.0721](https://arxiv.org/pdf/1310.0721)
  - Finite interleaver (Sec. VII, Fig. 9): square R×R row-by-column interleaver over the CLTU coded bits, PTC(128,64), transfer frame M = 2048, "burst length of 100 bits", Eb/J0P = 0 dB. "We observe that the CLTU interleaver is very effective against bursts produced by pulsed jamming. For long TFs (like the one here considered) the burst is practically neutralized by the interleaver." Fig. 9 used a 64×64 interleaver. — [arXiv 1310.0721](https://arxiv.org/pdf/1310.0721)

**Depth scaled to fade duration (JPL TDA 42-96)**
- Divsalar, Simon & Yuen, "The Use of Interleaving for Reducing Radio Loss in Convolutionally Coded Systems", JPL TDA Progress Report 42-96, 1988. Read; OCR text.
  - The noisy-carrier-phase degradation is treated as "an 'amplitude fade' whose duration is on the order of 1/(B_L T_s) symbols. Thus, if we break up this 'fade' by interleaving to a depth on the order of 1/(B_L T_s), then, after deinterleaving, the degradation due to cos φ will be essentially independent from symbol to symbol." — [NTRS 19890010083](https://ntrs.nasa.gov/api/citations/19890010083/downloads/19890010083.pdf)
  - Abstract: interleaving "effectively reduces radio loss at low-loop SNRs by several decibels and at high-loop SNRs by a few tenths of a decibel." — [NTRS 19890010083](https://ntrs.nasa.gov/api/citations/19890010083/downloads/19890010083.pdf)

**Finite-depth cost (JPL TDA 42-95)**
- Cheung & Dolinar, "Performance of Galileo's Concatenated Codes With Nonideal Interleaving", JPL TDA Progress Report 42-95, 1988. Read.
  - "Galileo's depth 2 interleaving, when used with the experimental (15, 1/4) code, requires about 0.4 dB to 0.5 dB additional signal-to-noise ratio to achieve the same BER performance as the concatenated code with ideal interleaving. When used with the standard (7, 1/2) code, depth 2 interleaving requires about 0.2 dB more signal-to-noise ratio than ideal interleaving." Context: RS(255,223) outer code, with interleaving to break up Viterbi-decoder error bursts. — [NTRS 19890010972](https://ntrs.nasa.gov/api/citations/19890010972/downloads/19890010972.pdf)

**Faster nulling shortens bursts**
- DuPree, US 5,175,558: "Faster nulling reduces burst lengths and therefore requires a smaller interleaver to protect the communication link until the adaptive antenna forms nulls." — [US5175558](https://patents.google.com/patent/US5175558A/en)

### Inferences
- For the project's jammer (100-symbol period, 30 % duty), each burst is about 30 symbols and the gap about 70 symbols. The guardband/burst ratio is about 2.33, below the patent's ratio of 3 for "all burst errors" correction with rate-1/2 RS plus interleaving. The ratio is my arithmetic; the threshold is the patent's claim.
- Even an ideal interleaver does not remove the jammed fraction. It turns a 30 % on-time into about 30 % of coded symbols with high variance (Baldi's model). Whether a rate-1/2 code then decodes depends on whether those symbols are treated as erasures or low-reliability LLRs (JSI) or as full-confidence values (no JSI). See Q2.
- Following the lecture-note bound and the JPL "depth on the order of the fade length" rule, an interleaver spreading a 30-symbol burst needs a span, in coded symbols, of several jammer periods. With a 100-symbol period, roughly 10 bursts fall in a 1000-symbol frame, so a frame-length interleaver spans many periods. This is inference; no source gave a periodic-burst depth formula.

### Gaps
- I found no open source with a closed-form required interleaver depth for a periodic on/off jammer (period P, duty d) combined with a rate-1/2 convolutional code and soft or erasure Viterbi decoding. The classical results above are for a single burst with guard space, or for ideal interleaving.
- Forney's burst-channel and interleaver theory and Ramsey's optimum interleavers (IEEE Trans. IT, 1970–71) were not accessed.

### Files saved
All in `C:\Users\Adi Suliman\Desktop\תואר ראשון  הנדסת חשמל ואלקטרוניקה\שנה ד\פרוייקט גמר\מקורות`. No existing file was overwritten; each name was checked first.
- V7_Marti2023_Mitigating_Smart_Jammers_MU_MIMO.pdf
- V7_Baldi2013_Coding_Against_Jamming_Telecommand_Links.pdf
- V7_Ercan2023_GRAND_EDGE_Jamming_Erasure_Decoding.pdf
- V7_GarciaPena2021_GNSS_Degradation_Pulsed_Interference_Blanker.pdf
- V7_Epple2012_DME_Interference_LDACS1_Pulse_Blanking.pdf
- V7_NYCU2011_Ch5_Interleaving_Lecture_Notes.pdf
- V7_DuPree1992_US5175558_Nulling_Pulse_Jammer_Duty_Factors.pdf
- V7_Divsalar1988_TDA42-96_Interleaving_Convolutional_Codes.pdf
- V7_Cheung1988_TDA42-95_Galileo_Nonideal_Interleaving.pdf

### COULD NOT DOWNLOAD
| # | Title | Identifier | URL | Reason |
|---|---|---|---|---|
| 1 | R. T. Compton Jr., "The effect of a pulsed interference signal on an adaptive array" | IEEE Trans. AES-18, 1982; DOI not verified | https://apps.dtic.mil/sti/pdfs/ADA106545.pdf (related DTIC report) | DTIC returned 403 / "Under Maintenance". DTIC reports ADA136461, ADA134301, ADA134300 and ADA061137 were also blocked. |
| 2 | Konovaltsev, De Lorenzo, Hornbostel, Enge, "Mitigation of Continuous and Pulsed Radio Interference with GNSS Antenna Arrays", ION GNSS 2008 | — | https://elib.dlr.de/58351/1/Session_C6_Mitigation_Continuous_Pulsed_Konovaltsev_v3.pdf | Authorization required |
| 3 | Epple, U., PhD thesis "OFDM Receiver Concept for the Aeronautical Communications System LDACS1 to Cope with Impulsive Interference" | — | https://elib.dlr.de/101433/1/PhD-Thesis_Epple.pdf | Authorization required |
| 4 | Brandes, Epple, Schnell, "Compensation of the Impact of Interference Mitigation by Pulse Blanking in OFDM Systems", Globecom 2009 | — | https://elib.dlr.de/59449/1/PID969632.PDF | Authorization required |
| 5 | "Efficient DME/TACAN Blanking Method for GNSS-based Navigation in Civil Aviation" | HAL hal-03001697 | https://hal-enac.archives-ouvertes.fr/hal-03001697v1 | HAL bot-check page |
| 6 | Grabowski & Hegarty, "Characterization of L5 Receiver Performance Using Digital Pulse Blanking", ION GPS 2002 | — | no open copy found | — |
| 7 | Bastide et al., "Analysis of L5/E5 acquisition, tracking and data demodulation performances in presence of DME/TACAN" (2004) | — | not located | — |
| 8 | Viterbi, "Spread spectrum communications – myths and realities", IEEE Commun. Mag. 17(3):11–18, 1979 | DOI not verified | no open copy found | — |
| 9 | Hoo, "Adaptive Satcom antenna performance against blinking jammers", IEEE AP-S 1991 | 10.1109/APS.1991.175000 | https://doi.org/10.1109/aps.1991.175000 | Paywalled; abstract only |
| 10 | Sarkar et al., "A deterministic least-squares approach to STAP", IEEE TAP 2001 | 10.1109/8.910535 | https://doi.org/10.1109/8.910535 | Paywalled; abstract only |
| 11 | Surrey record on adaptive beamforming for asynchronous/intermittent interference | — | https://openresearch.surrey.ac.uk/permalink/44SUR_INST/15d8lgh/alma99598021202346 | Not resolved; snippet only |
