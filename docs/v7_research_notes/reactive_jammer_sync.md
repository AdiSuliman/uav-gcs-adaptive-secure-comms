# Jammer-resilient time/frame synchronization and channel estimation in multi-antenna receivers: a review of receiver-side methods

Scope and method. This is a literature review of receiver algorithms and the performance their authors report. The threat appears only as a given in each paper's evaluation. The notes contain no device or attack implementation details and no design decisions.

Every source was read in full from the local library copy (`LIB` = `C:\Users\Adi Suliman\Desktop\תואר ראשון  הנדסת חשמל ואלקטרוניקה\שנה ד\פרוייקט גמר\מקורות\`, double space after ראשון) after extraction with `pdftotext -layout`. Scratch extracts are in `_extracts_sync\` next to this file. No web pages were fetched and nothing was downloaded, as the coordinator instructed. Anything not read in a source is marked **UNVERIFIED**.

Glyph restorations. The extractor drops µ/Greek glyphs. `[µs]` marks a restored unit, and in Rahbari 2016 and Yan 2016 the extractor printed "ms" or "s" where the PDF has µs. Two checks confirm this: an 802.11 STS is 0.8 µs, and Rahbari's "2:56 ms" figure is Nguyen's 2.56 µs. `[ρ]`, `[τ]`, `[γ]` mark restored symbols.

Page conventions. For IEEE journal papers (Yan, Rahbari), pages are the printed journal pages. For arXiv, CNS, WiSec and TMC-accepted copies, they are PDF pages ("p.N"), which equal the printed numbers where the copy has them. Nguyen 2014 uses the printed proceedings page.

Context arithmetic used only in the Inferences sections:
- At 1 Msym/s, 1 µs equals 1 QPSK symbol.
- If ±50 ppm is the total offset at 2.4 GHz, the CFO is up to ±120 kHz. That is 0.12 cycle (43.2°) of phase rotation per symbol, or 1.92 cycles over 16 symbols.
- Free-space propagation adds about 3.34 µs per km.

Source key (short tag, full reference, link):
- **[JASS]** G. Marti, F. Arquint, C. Studer, "Jammer-Resilient Time Synchronization in the MIMO Uplink," arXiv:2404.05335v2, 27 Jan 2025. The ASIC paper cites it as IEEE Trans. Signal Process., vol. 73, 2025. Links: https://arxiv.org/abs/2404.05335; local file `LIB\V7_Marti2024_JASS_Jammer_Resilient_Time_Sync_MIMO_arXiv.pdf`. Simulation code is stated on p.1: https://github.com/IIP-Group/JASS.
- **[ASIC]** F. Arquint, O. Castañeda, G. Marti, C. Studer, "A Jammer-Resilient 2.87 mm² 1.28 MS/s 310 mW Multi-Antenna Synchronization ASIC in 65 nm," arXiv:2511.21451v1, 26 Nov 2025. Links: https://arxiv.org/abs/2511.21451; local file `LIB\V7_Arquint2025_JASS_Sync_ASIC_65nm_arXiv.pdf`.
- **[Yan]** Q. Yan, H. Zeng, T. Jiang, M. Li, W. Lou, Y. T. Hou, "Jamming Resilient Communication Using MIMO Interference Cancellation," IEEE TIFS 11(7):1486–1499, Jul. 2016. Links: https://doi.org/10.1109/TIFS.2016.2535906; local file `LIB\V7_Yan2016_Jamming_Resilient_MIMO_Interference_Cancellation_TIFS.pdf`.
- **[Zeng]** H. Zeng, C. Cao, H. Li, Q. Yan, "Enabling Jamming-Resistant Communications in Wireless MIMO Networks," IEEE CNS 2017, pp. 1–9. The venue and pages come from JASS ref. [14]; the local copy prints no DOI. Local file: `LIB\V7_Zeng2017_Jamming_Resistant_MIMO_JrRx_CNS.pdf`.
- **[MAED]** G. Marti, T. Kölle, C. Studer, "Mitigating Smart Jammers in Multi-User MIMO," IEEE TSP 71:756–771, 2023. Links: https://arxiv.org/abs/2208.01453; local file `LIB\V7_Marti2023_Mitigating_Smart_Jammers_MU_MIMO.pdf`. Cited only.
- **[Rahbari]** H. Rahbari, M. Krunz, L. Lazos, "Swift Jamming Attack on Frequency Offset Estimation: The Achilles' Heel of OFDM Systems," IEEE TMC 15(5):1264–1278, May 2016. Links: https://doi.org/10.1109/TMC.2015.2456916; local file `LIB\V7_Rahbari2016_Swift_Jamming_FO_Estimation_TMC.pdf`.
- **[Zhang]** Z. Zhang, M. Krunz, "Preamble Forgery and Injection in Wi-Fi Networks: Attacks and Defenses," IEEE TMC, accepted version (the local copy shows "VOL. X, NO. X, 202X" and no DOI). Local file: `LIB\V7_Zhang2024_Preamble_Forgery_Injection_WiFi_TMC.pdf`.
- **[Nguyen]** D. Nguyen, C. Sahin, B. Shishkin, N. Kandasamy, K. R. Dandekar, "A Real-Time and Protocol-Aware Reactive Jamming Framework Built on Software-Defined Radios," ACM SRIF'14. Links: https://doi.org/10.1145/2627788.2627798; local file `LIB\V7_Nguyen2014_RealTime_Protocol_Aware_Reactive_Jammer_SDR.pdf`.
- **[Wilhelm]** M. Wilhelm, I. Martinovic, J. B. Schmitt, V. Lenders, "Short Paper: Reactive Jamming in Wireless Networks—How Realistic is the Threat?," ACM WiSec 2011, pp. 47–52 (pages as cited in Giustiniano 2013). Local file: `LIB\V7_Wilhelm2011_Reactive_Jamming_How_Realistic_WiSec.pdf`.
- **[Giustiniano]** D. Giustiniano, V. Lenders, J. B. Schmitt, M. Spuhler, M. Wilhelm, "Detection of Reactive Jamming in DSSS-based Wireless Networks," ACM WiSec '13. Local file: `LIB\V7_Giustiniano2013_Detection_Reactive_Jamming_DSSS_WiSec.pdf`.
- **[Bliss]** D. W. Bliss, P. A. Parker, "Temporal synchronization of MIMO wireless communication in the presence of interference," IEEE TSP 58(3):1794–1806, Mar. 2010. This reference is known only from ASIC ref. [6]. The related patent US8358716B2 (https://patents.google.com/patent/US8358716B2/en) was **not read**, because the coordinator ruled out web access.

---

## Q1. Multi-antenna synchronization that resists jamming (JASS, the JASS ASIC, Bliss & Parker): how each estimates the interference subspace without a jammer-free slot, and what detection/sync error rates each reports against JSR

### Takeaway
JASS (Marti/Arquint/Studer) is the only fully read method that synchronizes reliably when the interference is present **only while the legitimate sync sequence is on air**.

How JASS avoids needing a jammer-free slot:
- For every candidate arrival index τ, it first projects the windowed B×K receive matrix onto the temporal complement of the known sequence. This removes the legitimate signal at the true τ.
- It then estimates the interference subspace from what remains, using Î dominant eigenvectors obtained by a few power iterations.
- Finally, it nulls that subspace spatially and tests the normalized correlation against a threshold γ.

Reported performance:
- Reactive jammers that are on only during the sequence, at JSR [ρ] = 0, 10 and 30 dB (B=16, I=Î=4, K=16, SNR 0 dB): total error rate (FPR+FNR) ≈ 1% at γ = 0.375‖s‖². The unmitigated detector fails against the stronger jammers. A "null the Î strongest dimensions" baseline (BAJASS) fails against weak jammers.
- The fabricated ASIC (B=16, K=16 BPSK, up to 2 jammer antennas, 1.28 MS/s, 310 mW) matches floating-point performance.
- JASS assumes frequency-flat channels and performs **no frequency synchronization**.
- Bliss & Parker 2010 could not be read (UNVERIFIED).

### Cited Findings
**JASS: problem statement and why a jammer-free slot is not assumed**
- JASS states it is, to the authors' knowledge, the first method for reliable time synchronization in the single-user MIMO uplink while mitigating smart jammers. It detects "a randomized synchronization sequence" by fitting "a spatial filter to the time-windowed receive signal" (abstract, p.1). — [JASS p.1](https://arxiv.org/abs/2404.05335)
- The authors reject estimating the jammer channel from a fixed training set: "we cannot take for granted that the jammer is active during any specific period of time." Hence J cannot be estimated "from any fixed set of receive vectors" (Sec. III-A, p.4). — [JASS p.4](https://arxiv.org/abs/2404.05335)
- How JASS characterizes prior MIMO sync approaches (Sec. I-B, p.2; secondary descriptions, not read in the originals):
  - MCR decoding [Shen et al. 2014] tests whether receive vectors are collinear. It needs many samples when the jammer is much stronger ("500 samples are used in [7]") and works only against single-antenna jammers.
  - JrRx [Zeng 2017] nulls the jammer during synchronization, but JASS says this requires "a barrage jammer which jams permanently" so its signature can be estimated during training.
  - [Yan 2016] "depends on the assumption that the jammer's reaction time is sufficiently slow" so the preamble is not jammed.
  - El-Keyi et al. 2017 (LTE adaptive filter) still fails against full-band barrage jamming.
  - Randomizing the in-frame position of sync signals (La Pan et al. 2013; Eygi & Kurt 2020) helps only against jammers that target the sync signals alone.
  - [JASS p.2](https://arxiv.org/abs/2404.05335)

**JASS: signal model and assumptions**
- Flat-fading model: y[k] = h·s[k−L] + J·w[k] + n[k] (Eq. 1). There is one single-antenna UE, a B-antenna receiver and an I-antenna jammer with I < B. The arrival index L is unknown (Sec. II-A, p.2). — [JASS p.2](https://arxiv.org/abs/2404.05335)
- The sync sequence is s ~ CN(0, I_K) and is assumed unknown to the jammer. It may be generated from a pre-shared secret and should change after each use. If the jammer knew s, it could transmit a copy earlier than the UE and fool the receiver (Sec. II-B2, p.3).
- Footnote 2: a random BPSK sequence can replace the Gaussian one, at the cost of a non-zero failure probability in the theorem (p.3). — [JASS p.3](https://arxiv.org/abs/2404.05335)
- Strong attack model: the jammer may depend causally on the transmitted sequence, may be time-variant, and its power and antenna count may be unknown. The only restriction is that it cannot depend on future sequence symbols (Sec. II-B3, p.3). — [JASS p.3](https://arxiv.org/abs/2404.05335)
- Stated limitations (Sec. II-B4, p.3):
  - The method is "limited to frequency-flat communication channels."
  - It does time synchronization only, with no estimation of carrier frequency or sampling-rate offset; both extensions are "left for future work."
  - The conclusion repeats this (p.12).
  - [JASS p.3](https://arxiv.org/abs/2404.05335)

**JASS: the method (equation numbers as in the paper)**
- Optimization problem, Eq. (11), p.4: choose the smallest τ for which the maximum over projections P̃ (in the Grassmannian G_{B−Î}) of ‖P̃Y_τ s*‖²/‖P̃Y_τ‖_F² reaches γ. Here Y_τ = [y[τ],…,y[τ+K−1]] (Eq. 9). — [JASS p.4](https://arxiv.org/abs/2404.05335)
- **Theorem 1** (p.4): with probability one, Eq. (11) returns τ = L if five conditions hold:
  1. N0 = 0.
  2. h ∉ col(J).
  3. I ≤ Î < B.
  4. K > I+1.
  5. γ = ‖s‖².
- Consequence stated on p.4–5: success "does not depend on the jammer's behavior (including its power)", and the receiver only needs Î ≥ I, not the true I. — [JASS pp.4–5](https://arxiv.org/abs/2404.05335)
- Algorithm (Sec. III-B, Eqs. 12–17, Algs. 1–2, pp.5–6):
  - The fractional problem is replaced by a Dinkelbach-like proxy with the target value fixed at ‖s‖², with no iteration.
  - The maximizing A is given by the Î principal eigenvectors of ‖s‖²Y_τY_τᴴ − c cᴴ, where c = Y_τ s* (Eq. 17). They are computed by power iteration (Alg. 2, tmax iterations).
  - The pseudo-inverse A† is used instead of Aᴴ because few iterations leave A only approximately orthonormal. The authors observe "a significant performance decrease" with the conjugate transpose.
  - [JASS pp.5–6](https://arxiv.org/abs/2404.05335)
- **Interpretation of how the interference subspace is found without a jammer-free slot** (Sec. III-C, "Reinterpreted Algorithm 1", p.6):
  - The matrix equals ‖s‖²·(Y_τT)(Y_τT)ᴴ, where T = I_K − s*sᵀ/‖s‖² is the temporal projector onto the complement of the sequence.
  - At τ = L, T "nulls the UE transmit signal completely," so the dominant directions of Y_τT come from interference and noise only. The projection P̂ = I − AA† then nulls the jammer.
  - At τ ≠ L, the sequence is absent or misaligned. Since the jammer does not know s, the correlation stays below γ "regardless of P̂".
  - [JASS p.6](https://arxiv.org/abs/2404.05335)

**JASS: simulation setup (Sec. IV-A/B, pp.6–7)**
- B = 16, I = Î = 4, K = 16, tmax = 4.
- L is geometric with mean K²−1.
- Channels are i.i.d. Rayleigh; 3GPP 