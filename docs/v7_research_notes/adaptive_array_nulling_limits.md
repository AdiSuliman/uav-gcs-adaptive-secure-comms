# Adaptive-array nulling limits: practical (estimated covariance, estimated channel) vs ideal MMSE/MVDR against a strong, fast-fading interferer

Scope note. All quotes below are verbatim from the source text I read, in a few cases extracted with pdftotext (Greek letters and sub/superscripts written out in plain text; equations transcribed as faithfully as the extraction allows). Items read only in a search snippet are marked UNVERIFIED. "Inference" items are my own calculations or reasoning, not claims made by the sources. Context numbers used in the inferences: 2.4 GHz, 161 km/h gives fd = 358 Hz; 1 Msym/s; frame of about 0.5 ms; 32-symbol quiet slot; N = 3 antennas; Rician K = 10 dB; Eb/N0 10 dB; JNR 10 dB and 30 dB. Coordinator diagnostics used in the inferences: with a static jammer channel (K_i = 40 dB) at 30 dB JSR the real receiver has 0 failures; failures are about 6% at 29 km/h, 35% at 100 km/h and 50% at 161 km/h; in failed frames the CFO estimate is off by 5 to 22 kHz.

## Q1. Sample-support loss of SMI/MVDR/MMSE (Reed-Mallett-Brennan, signal-in-training/Boroson, diagonal loading)

### Takeaway
With signal-free training, the SMI/MVDR SINR loss depends only on N and the number of snapshots n. It does not depend on the interference power: the Reed-Mallett-Brennan (RMB) law gives a Beta(n-N+2, N-1) loss with mean (N-1)/(n+1). For N = 3 and n = 32 that is a mean loss of about 0.27 dB, so 32 quiet-slot snapshots cannot explain frame failures at 30 dB JNR. Estimating the covariance with the desired signal present (MPDR, "power inversion over the training region") is different: the required sample support grows with the optimum output SNR, and the loss can reach several dB at the project's SNR.

### Cited Findings
- RMB law, as restated in a 2026 arXiv preprint (not yet peer-reviewed), p.1: "The classical finite-training benchmark is the Reed-Mallett-Brennan (RMB) law for sample matrix inversion (SMI) [4]: under independent complex-Gaussian training, the normalized output SINR of SMI has an exact beta distribution, and its mean loss has first-order coefficient N - 1 for an array of N sensors. This is the origin of the familiar rule of about two training snapshots per sensor for a 3-decibel (dB) loss." — [Cheng, Chen, Song 2026, arXiv:2609.06136](https://arxiv.org/pdf/2609.06136)
- Same source, eq. (28), p.6: "For n ≥ N, the SMI output-SINR ratio satisfies ρ_SMI ~ Beta(n - N + 2, N - 1), E[L_SMI(ρ)] = (N - 1)/(n + 1)." and "The distribution and mean in (28) are independent of R." Its Appendix states the law holds "for signal-free complex-Gaussian training with N ≥ 2 and n ≥ N". — [Cheng et al. 2026](https://arxiv.org/pdf/2609.06136)
- Same law in an independent overview, eqs. (19)-(21), p.5: "mvdr = Beta(N - 1, K - N + 2) with a p.d.f. given by p(ρ) = (1/B) ρ^(K-N+1) (1 - ρ)^(N-2)" [K = number of training samples]. Besson's appendix defines Beta(K1, K2) with p(B) ∝ B^(K2-1)(1 - B)^(K1-1), i.e. the reverse of the usual parameter order. The p.d.f. is the standard Beta(K-N+2, N-1), the same law as Cheng et al. Next: "The distribution of ρ_mvdr is therefore independent of Σ and depends only on N and K. It is straightforward to see that E{ρ_mvdr} = (K - N + 2)/(K + 1) so that E{ρ_mvdr} = 0.5 ⇔ K = 2N - 3 (21) which corresponds to the famous Reed-Mallet-Brennan rule [11]." — [Besson 2021, arXiv:2102.01421](https://arxiv.org/pdf/2102.01421)
- Signal in the training data (MPDR, Boroson 1980), eq. (22), p.6: ρ_mpdr =d [1 + (1 + γ^-1 SNRopt) · C²_{N-1}(0) / C²_{K-N+2}(0)]^-1, "which depends only on K, N and γ^-1 SNRopt. It is clear that the difference between the MVDR and the MPDR scenarios will be all the more pronounced that γ^-1 SNRopt is large." The C² terms are chi-square variables, and γ = 1 is the homogeneous case. — [Besson 2021](https://arxiv.org/pdf/2102.01421)
- p.7 (Fig. 2, N = 16, K = 2N): "Obviously when γ^-1 SNRopt increases a large difference is observed and ρ_mpdr is likely to take very low values which makes the interest of the adaptive filter questionable in this situation." — [Besson 2021](https://arxiv.org/pdf/2102.01421)
- Synthesis, p.10: "The least impact is achieved in the MVDR scenario where Σt = Σ and K = 2N - 3 training samples are necessary to achieve an average SNR 3dB below the optimum SNR. In the MPDR scenario where Σt = Σ + P v v^H the number of samples required to achieve convergence increases with SNRopt." — [Besson 2021](https://arxiv.org/pdf/2102.01421)
- On steering-vector or channel errors, p.6: Boroson "additionally takes into account errors about the SoI signature, i.e., Boroson derives representations of the SNR loss of w ∝ S^-1 ṽ where ṽ ≠ v for both the MVDR and MPDR scenarios." — [Besson 2021](https://arxiv.org/pdf/2102.01421)
- Diagonal loading, eq. (80), p.25. For Σ = GG^H + σ²I (rank-R interference), the loaded-SMI loss is approximately "Beta(R, K - R + 1) (80) which coincides with the distribution of the SNR loss of the eigencanceler in (62)". The text adds: "Numerical simulations tend to confirm this fact and show that diagonal loading is very efficient in low sample support with strong low-rank interference, provided that the loading level σ is chosen properly." The validity condition (p.24-25) is "the loading level is larger than the white noise power), yet much below the eigenvalues of GG^H". — [Besson 2021](https://arxiv.org/pdf/2102.01421)
- Simulation evidence that sample support stops mattering once it is moderate, while non-stationarity still matters. In Gershman et al. 1996 (32-sensor ULA, three moving jammers at INR 30 dB, training with the signal absent), "the conventional algorithms completely fail in moving jammer environment" even with L = 32 snapshots. The failure is caused by jammer motion, not by snapshot count (p.4). — [Gershman, Nickel, Böhme, EUSIPCO 1996](https://new.eurasip.org/Proceedings/Eusipco/1996/paper/ap_2.pdf)

### Inferences
- RMB for N = 3 (my calculation from eq. (28)): mean SINR ratio (n-1)/(n+1). That is 0.714 (-1.46 dB) at n = 6, 0.818 (-0.87 dB) at n = 10, 0.882 (-0.54 dB) at n = 16, 0.939 (-0.27 dB) at n = 32 and 0.969 (-0.14 dB) at n = 64. For Beta(31, 2), P(ρ < 0.5) = 32·0.5^31 - 31·0.5^32 ≈ 7.7e-9. With a signal-free 32-symbol quiet slot and a stationary jammer, finite sample support costs well under 1 dB, independent of JNR. This matches the coordinator's diagnostic that a static jammer channel gives 0 failures at 30 dB JSR.
- The MPDR case applies if the covariance is estimated by power inversion over the training region, with the desired signal present and not subtracted. A rough mean, from replacing the chi-square ratio in eq. (22) by the ratio of its means (N-1)/(K-N+2) with γ = 1, N = 3 and K = 32:
  - SNRopt = 10 dB: about 0.59 (-2.3 dB)
  - SNRopt = 13 dB: about 0.43 (-3.7 dB)
  - SNRopt = 17.8 dB: about 0.20 (-6.9 dB)

  This is an approximation, not the exact mean. Signal-in-training therefore costs several dB at the project's SNR, but this loss also does not grow with JNR. Neither sample-support mechanism explains failures that appear only at high JNR and high speed.
- Diagonal loading in the rank-1 case (R = 1), from eq. (80): mean ≈ (K-R+1)/(K+1) = 32/33 (-0.13 dB). Loading helps sample support but does nothing for a covariance that is stale (see Q2).

### Gaps
- I could not read the original RMB (1974), Boroson (1980) and Carlson (1988) papers (paywalled). Their exact wording, and Carlson's often-quoted sample-support rule for diagonal loading, are not verified. See COULD NOT DOWNLOAD.
- The exact mean of eq. (22) for N = 3, K = 32 (as opposed to my ratio-of-means approximation) was not computed.

## Q2. Null depth when the interferer channel varies between covariance estimation and use (Doppler × update interval, null filling, covariance-matrix tapers, bandwidth/dispersion)

### Takeaway
A null computed from past data cancels only the part of the interferer that is still correlated with that data. The decorrelated part acts as a "surprise interference" that is not in the training covariance, and it passes almost unattenuated. For Rayleigh/Jakes fading the correlation after delay τ is J0(2π fd τ). The classic coherence-limited form gives cancellation of about 1/(1-|ρ|²); the sources give this form for phase-noise decorrelation, and I apply it to time decorrelation. With a 3-antenna array at fd = 358 Hz over a 0.5 ms frame, this limits the useful null depth to a few dB for the diffuse (Rayleigh) part of the jammer, plus 10 dB from Rician K = 10 dB. That is enough to hold a 10 dB jammer but not a 30 dB one.

Null widening (Mailloux/Zatman/Guerci covariance tapers, derivative constraints) trades null depth and degrees of freedom for robustness. With 3 antennas there is little freedom to spare. Bandwidth/dispersion is not the limit at 1.25 MHz.

### Cited Findings
- Jakes temporal correlation and channel-aging model, eq. (14) and eq. (17), p.4: "the normalized (unit variance) discrete-time autocorrelation of fading channel coefficients is [19] rh[k] = J0(2π fD Ts |k|), (14) where J0(·) is the zeroth-order Bessel function of the first kind, Ts is the channel sampling duration, fD is the maximum Doppler shift". Also: "We denote α = J0(2π fD Ts) as a temporal correlation parameter", with the AR(1) model h[n] = α h[n-1] + e[n] (17), and "As the delay |k| increases or the user moves faster, the autocorrelation rh[k] decreases in magnitude to zero though not monotonically since there are some ripples." — [Truong & Heath 2013, arXiv:1305.6151](https://arxiv.org/pdf/1305.6151)
- Cancellation limited by inter-channel correlation (the closed form is stated for phase noise). With independent PLLs the channel correlation is e^{-δ²}. Eq. (20) gives R = P_s[1, e^{-δ²}, ...; e^{-δ²}, 1, ...], and
  - Eq. (25): ICR = (e^{-δ²} - N e^{-δ²} - 1) / ((e^{-δ²} - 1)(N e^{-δ²} + 1))
  - Eq. (26): "For N = 1, ICR_{N=1} = 1/(1 - e^{-2δ²})"
  - Eq. (27): "For N → ∞, ICR_{N→∞} = 1/(1 - e^{-δ²})"
  - Eq. (28): "the increment in ICR (in decibel) is upper-bounded to be ... ΔICR = 10 log10(1 + e^{-δ²})" and "the maximum ΔICR is around 3 dB."

  ICR is "the ratio of the received signal power of the main antenna to the beamformer output signal [7]". — [Zhou, Wang, He, Meng 2022, Sensors 22:2362](https://pmc.ncbi.nlm.nih.gov/articles/PMC8951393/)
- Covariance mismatch, i.e. interference present at use time but missing from training ("surprise interference"), eq. (25), p.7. The case is that "the data to be filtered contains a rank-one component (e.g. a surprise interference) which is not accounted for by the training samples and which falls in a null of the optimal filter w_opt", giving a loss that "depends on q^H Σt^-1 q only". Then: "With the power of this interference increasing the degradation is seen to be substantial." — [Besson 2021](https://arxiv.org/pdf/2102.01421)
- Fading-rate degradation of DMI/SMI MMSE weights (simulation, IS-136, 4 antennas, sliding-window DMI with K = 14 samples, 184 Hz = 60 mph at 1.9 GHz; my calculation of the symbol rate: 162 symbols per 6.7 ms slot, i.e. about 24.3 ksym/s):
  - Noise only: "With DMI, the required S/N for a 10^-2 BER is increased by 1.2 and 2.7 dB at 0 and 184 Hz, respectively."
  - Equal-power interferer, with "fading of both the desired and interfering signals": "With DMI, the required S/N for a 10^-2 BER is increased by 2.1 and 11 dB at 0 and 184 Hz, respectively. At 184 Hz, an error floor is seen close to the required 10^-2 BER. Thus, DMI suffers substantial degradation at high fading rates."
  - The patent's subspace method: "The degradation with 184 Hz fading has been reduced from 11 dB (with DMI) to 5 dB."
  - On window length: "With channel variation only, the degradation is shown to increase montonically with K".

  — [US 6,147,985 (Bar-David, Golden, Winters; Lucent; filed 1997), text](https://patents.google.com/patent/US6147985A/en). These are the IS-54/136 DMI results also published in Winters 1993, IEEE TVT 42(4), which I could not download.
- Measured (not simulated) sensitivity of spatial interference suppression to channel aging, Argos 96x8 MU-MIMO at 2.4/5 GHz with pedestrian mobility:
  - p.5: "with user mobility 0.90 channel coherence drops to 9.5 ms and 23 ms for 2.4 GHz and 5 GHz, respectively ... This has a huge impact on achievable capacity, as a system that estimates the user channels every 10 ms will lose an average over 50% of capacity, with dropouts as high as 80%, even with just pedestrian mobility at 5 GHz"
  - p.6: "We also find that measured channel coherence is not an accurate estimate of the channel resounding interval in a MU-MIMO system ... The 90% expected capacity ... for 2.4 and 5 GHz are 1.1 ms and 4.2 ms, respectively. For 2.4 GHz, this is over 20 times lower than the 0.9 coherence time for the same trace."

  — [Shepard, Ding, Guerra, Zhong, Asilomar 2016](https://yecl.org/argos/pubs/Shepard-Asilomar16.pdf)
- Measured, LuMaMi 100-antenna testbed at 3.7 GHz, vehicles up to 29 km/h: "For a 100 antenna system, it is found that the channel state information (CSI) update rate requirement may increase by 7 times when compared to an 8 antenna system" (abstract, p.1). — [Harris et al. 2017, arXiv:1703.04723](https://arxiv.org/pdf/1703.04723)
- Null filling with a moving interferer (simulation, 7-element line array, Gaussian jammer of 4.092 MHz, JSR 80 dB, weight update 1 ms):
  - Static: "the normalized null depth was –113 dB"
  - Rate of change 0.0023°/ms: "The normalized depth was −73.05 dB, 39.5 dB lower than that of the static scene"
  - Rate of change 0.09°/ms: "the normalized depth was only −62.72 dB", with "no obvious correlation peak ... so the signal was not captured normally"
  - Abstract: "The null formed by the spatial filtering based on the array antenna will become wider and shallower, and the anti-jamming performance will deteriorate."

  — [Wang, Chang et al. 2019, Sensors 19:1661](https://pmc.ncbi.nlm.nih.gov/articles/PMC6479994/)
- Covariance matrix taper (CMT) definition. Eq. (14): R̄ = R ⊙ T_CMT (Hadamard product). Eq. (15): T_mn = sin((m-n)Δ)/((m-n)Δ) = sinc((m-n)Δ/π), "where Δ is the perturbation factor, the magnitude of which determines the width of the null after broadening". Also: "Although the algorithm can broaden the null, it will also make the null shallow." It cites Guerci 1999 for CMT. — [Ji, He et al. 2025, Sensors 25:1499](https://pmc.ncbi.nlm.nih.gov/articles/PMC11902554/)
- CMT numbers from the same paper (simulation; ULA; jammers moving 2°/s over 2 s; ISR 90 dB; diagonal loading 10). Values are signal-direction gain / jammer-null depth in dB:

  | Case | PI | CMT | Proposed |
  |---|---|---|---|
  | Table 3, 3 elements | -0.1003 / -125.8 | -0.1004 / -54.39 | -0.09977 / -67.405 |
  | Table 5, 12 elements, 8 snapshots | — | -20.79 / -34.66 | -1.933 / -61.285 |
  | Table 5, 12 elements, 500 snapshots | — | -15.69 / -40.48 | -0.1937 / -65.635 |

  The authors also state that PI "cannot suppress jamming when there is a deviation in the jamming direction". — [Ji et al. 2025](https://pmc.ncbi.nlm.nih.gov/articles/PMC11902554/)
- Trade-off in null widening, p.1: "The performance of the adaptive arrays is severely degraded if the weights of the arrays are not able to adapt sufficiently fast to the changing (nonstationary) jamming situation or to the antenna platform motion. This issue can be handled, however, if a broad null is formed toward the direction of the interference". On CMT: "Broad nulls will be formed at all the directions of interferences adaptively, and the width of the nulls can be controlled. However, as a price, the depth of the nulls will be reduced." The source attributes CMT to Mailloux (Electronics Letters 31(10), 1995), Zatman (Electronics Letters 31(25), 1995) and Guerci (IEEE TSP 47(4), 1999). — [Li, Zhao, Ye, Li 2017, ACES Journal 32(2)](https://journals.riverpublishers.com/index.php/ACES/article/download/9733/8133/31011)
- Derivative-constraint null widening, p.1: "The performance of adaptive arrays severely degrades if the weights are not able to adapt sufficiently fast to the changing (non-stationary) jamming situation or to the antenna platform motion." The remedy "is achieved by means of artificial broadening of the null width in all jammer directions. Data-dependent sidelobe derivative constraints are used which do not require any a priori information about the jammers". Robust weight: w_rob = (R + γ B R B)^-1 a_S, with the constraint "n > (p + 1)q", i.e. more sensors than (derivative order + 1) × jammers. Cost (p.4): "we assumed γ = 1.5 which corresponds to ≈ 1 dB performance loss in the stationary case". — [Gershman, Nickel, Böhme 1996](https://new.eurasip.org/Proceedings/Eusipco/1996/paper/ap_2.pdf)
- Dispersion and rank. A single-antenna jammer with delay spread, against OFDM receivers that rely on the cyclic prefix: "the interference received on each subcarrier by a multi-antenna receiver is, in general, not confined to a subspace of dimension one ..., but of dimension L, where L is the jammer's number of channel taps", and "These findings imply that mitigating jammers with large delay spread through linear spatial filtering is infeasible." (p.1) — [Marti & Studer 2023, arXiv:2309.14059](https://arxiv.org/pdf/2309.14059)

### Inferences
- Coherence-limited cancellation applied to time variation (my reasoning, not stated by the sources). Zhou et al. eq. (26) is the special case |ρ| = e^{-δ²} of the general one-auxiliary canceller bound ICR = 1/(1-|ρ|²), where ρ is the correlation between the jammer component in the sample used to form the weights and in the sample where they are applied. With the Jakes/AR(1) model (Truong & Heath eq. (14)), a weight formed at time 0 and applied at delay τ leaves residual jammer power of about (1 - J0²(2π fd τ)) × P_diffuse. Zhou et al. eq. (28) suggests more antennas add at most about 3 dB to this bound when decorrelation is independent per channel.
- Numbers for the project (my calculation; fd = 358 Hz; τ from about 16 µs to 516 µs after the quiet slot):

  | Delay τ | 1 - J0² |
  |---|---|
  | 32 µs | 0.0026 (-25.9 dB) |
  | 100 µs | 0.025 (-16.0 dB) |
  | 250 µs | 0.149 (-8.3 dB) |
  | 500 µs | 0.498 (-3.0 dB) |
  | Frame average | 0.199 (-7.0 dB) |

  With Rician K = 10 dB only the diffuse fraction 1/(K+1) (-10.4 dB) decorrelates. Residual INR ≈ JNR - 10.4 dB + 10·log10(1 - J0²):

  | Speed (fd) | JNR | Residual INR, frame average | Residual INR, end of frame |
  |---|---|---|---|
  | 161 km/h (358 Hz) | 30 dB | +12.6 dB | +16.8 dB |
  | 161 km/h (358 Hz) | 10 dB | -7.4 dB | -3.2 dB |
  | 100 km/h (222 Hz) | 30 dB | +8.8 dB | +13.3 dB |
  | 29 km/h (64 Hz) | 30 dB | -1.7 dB | +2.9 dB |
  | K_i = 40 dB jammer, 161 km/h | 30 dB | -17.0 dB | — |

  This simple model follows the coordinator's diagnostics in direction and roughly in size:
  - no failures with a static jammer or at JNR 10 dB;
  - a few failures at 29 km/h, where the residual is near the noise level;
  - many failures at 100-161 km/h, where the residual is 9-17 dB above noise.

  The ideal receiver (true covariance and channel at each instant) has no such lag term, so it is over-optimistic for this scenario.
- Caveats on the model (my reasoning). It ignores:
  - that a 3-element array still has a spare degree of freedom (partial cancellation of the decorrelated part is possible; Zhou et al. bound that gain at about 3 dB for independent per-channel decorrelation);
  - the relative phase drift between the LOS term (Doppler fd·cos θ) and the diffuse term, which can make the effective mismatch larger than (1 - J0²)/(K+1) when the jammer LOS is near the direction of motion;
  - estimation noise.

  The trend (residual grows about as (fd·τ)² for small fd·τ, i.e. about 6 dB more residual per doubling of speed or of the use interval) follows from J0(x) ≈ 1 - x²/4.
- Comparison with Winters' DMI result. A 184 Hz Doppler with a 14-symbol window at about 24.3 ksym/s gives fd × window ≈ 0.11, and an equal-power faded interferer then caused about 11 dB degradation and an error floor. The project's fd × (use interval) is up to 358 Hz × 0.5 ms ≈ 0.18, with a 1000× stronger (30 dB) jammer. Severe degradation is consistent with that published trend.
- Null widening (CMT, derivative constraints, Zatman dispersion synthesis) spends degrees of freedom. Gershman's constraint n > (p+1)q gives n > 2 for one jammer with first-order derivatives; with n = 3 it is just possible but leaves almost nothing for the signal. The published CMT numbers show null depth falling from about -126 dB to about -54 dB for 3 elements. That is still far deeper than the 30-40 dB needed. Whether a temporal taper or a covariance averaged over the frame can cover a 0.18 fd·T decorrelation with only one spare degree of freedom is not answered by these sources.
- Bandwidth/dispersion (my calculation; no source for the formula was read). For a flat-spectrum jammer of bandwidth B and inter-element delay τ_d, the inter-channel correlation is sinc(B·τ_d). With B = 1.25 MHz:

  | Spacing | B·τ_d | Residual 1 - sinc² |
  |---|---|---|
  | d = 0.3 m | 1.25e-3 | -52.9 dB |
  | d = 0.5 m | 2.1e-3 | -48.5 dB |
  | d = 1.0 m | 4.2e-3 | -42.4 dB |

  Bandwidth is therefore far below the Doppler limit. Multipath delay spread of the jammer channel at 1 Msym/s is a separate rank-increasing mechanism (Marti & Studer), which this project's flat Rician model does not include.
- Coordinator's CFO observation (my reasoning, unsourced). After whitening with a stale covariance, the residual jammer is strong (+9 to +17 dB above noise by the estimate above) and time-varying. A pilot-based frequency estimator then sees a strong non-white component. A bias of several kHz is plausible but not quantified by any source I read. Wang et al. 2025 note that "time and carrier synchronization itself is very challenging in the presence of strong jamming signals" (p.1). — [Wang, Fang, Du, Shao 2025, arXiv:2507.14945](https://arxiv.org/pdf/2507.14945)

### Gaps
- I did not read Mailloux 1995, Zatman 1995 and 1998 ("How narrow is narrowband?") or Guerci 1999 in the original (paywalled), so their taper formulas for temporal fading and their numeric null-depth versus fd·T curves are not verified. Ward's MIT LL TR-1015 (intrinsic clutter motion taper) is free on DTIC but DTIC blocked automated download.
- No source I read gives a closed-form "null depth vs fd·T" for a fading (not angularly moving) jammer in a communications receiver. The 1/(1-J0²) form above is my combination of the Zhou et al. eq. (26) and Truong & Heath eq. (14).
- No source quantifies CFO-estimation bias caused by residual time-varying jamming.

## Q3. Channel-estimation error in MMSE/optimum combining with a strong interferer

### Takeaway
Two different errors need to be separated:
1. Error in the desired-signal channel estimate ĥ. If the covariance is right, w = R^-1 ĥ still nulls the jammer, so the error mainly costs SNR. Boroson treats this as signature mismatch.
2. Error or aging in the interferer's spatial signature, whether from explicit interferer-channel estimation, a stale covariance, or hardware. This leaks interference in proportion to the error variance times the interferer power, i.e. a floor that rises with INR.

The sources support (2) explicitly: residual-interference terms with imperfect CSI, and null depth limited by amplitude/phase errors independent of N.

### Cited Findings
- Weight or channel errors limit null depth, independent of array size, p.10: "This means that the depth of beam nulls is limited by gain and phase accuracy, and is independent of the size of the array N and the number of interferers K, as long as N > K." From the analysis (p.9-10): "the mean square error angle θ² is equal to the sum of the mean square phase error σ²_φ and the mean square amplitude error σ²_ε." Footnote 6 (p.8): "The errors can also result from uncertainties about the channel responses for both desired and interfering signals." Fig. 6 plots interference rejection (IR) against 10·log10(σ²_φ + σ²_ε), where IR is "the ratio of the interferer power after beam-nulling to the interferer power before beam-nulling". — [Bakr & Johnson 2009, UCB/EECS-2009-1](https://www2.eecs.berkeley.edu/Pubs/TechRpts/2009/EECS-2009-1.pdf)
- Least-squares interferer-channel estimation and zero-forcing (ZF) nulling. Eq. (8)-(9): ĥ_T = (1/√M) Y q_T = h_T + (1/√M) Σ h_T' x̃_T',T, where M is the training length and the sum runs over un-cancelled interferers. Eq. (10) gives the residual I_R = -(1/√M) Σ_T Σ_T' v0* h_T' x̃_T',T x_T. The text says: "CSI estimation errors result in additional interference with respect to the case of perfect CSI" (p.7). Footnote 4 (p.6): "The alternative minimum mean-square-error (MMSE) estimator requires knowledge of the covariance of the aggregate interference from the weak transmitters, which is difficult to measure accurately due to the presence of the strong interferers." — [Huang, Andrews, Guo, Heath, Berry, arXiv:0807.1773](https://arxiv.org/pdf/0807.1773)
- Signature (channel) error in SMI: Boroson's analysis covers "w ∝ S^-1 ṽ where ṽ ≠ v" (p.6). The covariance-mismatch result (eq. (25), p.7) shows loss growing with the power of the un-learned component. — [Besson 2021](https://arxiv.org/pdf/2102.01421)
- DMI with a reference signal under fading (simulation). Even with "the ideal weights" BER increases at 184 Hz "because of the channel variation over each symbol". DMI weight-estimation error "depends on the ratio K/M" (K samples, M weights), and "detection errors increase the error in the weights. Since this increases the BER, error propagation can occur, resulting in a complete loss of tracking and a large error burst that can last until the end of the time slot." — [US 6,147,985 text](https://patents.google.com/patent/US6147985A/en)

### Inferences
- My reasoning, unsourced derivation. For w = R^-1 ĥ with a correct R, a pilot-based estimate error e whose interference component is collinear with the jammer channel gets suppressed by R^-1 as well. The SINR loss is then roughly 1/(1 + N/(Np·SINR_opt)) for Np pilots, independent of INR. Channel-estimation error of the desired link alone therefore does not create a floor that grows with JNR. What does create such a floor is any mismatch between the interference subspace in R and the one present at detection time: temporal aging (Q2), hardware errors (Bakr; Q5), or interferer-channel estimation noise (Huang). Those leak about (relative error) × INR.
- Applying Bakr's θ² rule to temporal aging: a per-antenna relative error variance of (1 - J0²)/(K+1) plays the role of σ²_φ + σ²_ε, giving the same numbers as the Q2 table. So the Bakr result and the Q2 coherence argument agree in form.

### Gaps
- I found no open source with a closed-form MMSE/optimum-combining SINR floor versus INR under pilot-based channel estimation plus estimated covariance in fading. The searched candidates were paywalled or off-topic (relay/MRC studies).

## Q4. Measured (and simulated) suppression by practical small arrays against strong jammers, including fading or moving interferers

### Takeaway
Measured static-geometry results for 2-4 element practical arrays range widely:
- about 10 dB: 2-antenna 5G uplink null-steering, lab, jammer about 1 m away;
- decoding at 20 dB JSR: Wi-Fi MIMO USRP;
- decoding at 40 dB JSR against a CW tone: 2-antenna USRP, UAV-oriented;
- about 60 dB "anti-jamming": 4-antenna GNSS with 3-tap STAP, lab, receiver-level metric.

Measured results with motion exist mainly for GNSS (7-element turntable at 2°/s, chamber) and for MU-MIMO channel-aging measurements. These show suppression degrading on millisecond scales even at pedestrian speed. I found no measured null-depth curve for a 2-4 element array against a Rayleigh/Rician-fading jammer at hundreds of Hz Doppler.

### Cited Findings
- 2-antenna 5G uplink null-steering, over the air, lab, 3 USRP X300, jammer about 1 m from the eNB (p.4): "For a jammer source transmitting at 30 dBm gain, our anti-jamming solution achieves a 10 dB cancellation compared to the default base station operation with no active anti-jamming solution." Positions: "the distance between the jammer and eNB remained at about 1 meter". Conditions for near-benchmark performance: "if the jammer source is in close vicinity of the base station and therefore, the line-of-sight (LoS) path is very dominant". Jammers tested: single-tone and 5 MHz wideband OFDM. Without nulling, UL SINR fell from 14.18 dB to 2.85 dB as jammer power rose from 0 to 30 dBm (Table 1). — [Zumegen, Jain, Bharadia, HotMobile 2024](https://wcsng.ucsd.edu/files/beamarmor.pdf)
- 2-antenna USRP receiver, UAV-oriented, measured. Abstract: "with a two-antenna receiver, the proposed method can successfully decode the signal of interest even when the jamming signal is 40dB stronger than the communication signal." Test conditions (p.4): "The jamming signal is a complex exponential signal whose frequency equals to the carrier frequency. The groundtruth CFO between the transmitter and the receiver is approximately 760Hz." QPSK, 70-symbol preamble, 164-symbol frame, bench setup with signal generators (static). — [Wang, Fang, Du, Shao 2025, arXiv:2507.14945](https://arxiv.org/pdf/2507.14945)
- Wi-Fi MIMO USRP2/GNURadio testbed, measured. Abstract: "as long as JrRx has more antennas than the jammers, it can successfully decode the signals from the sender, even if the jamming signals are 20 dB stronger than the signals of interest". Results (p.8): "the pSJNR degradation is less than 3 dB when the jamming signal is 20 dB stronger than the [signal]". — [Zeng, Cao, Li, Yan, IEEE CNS 2017](https://www.cse.msu.edu/~hzeng/papers/zeng17_cns_jamming.pdf) (already saved earlier as V7_Zeng2017_Jamming_Resistant_MIMO_JrRx_CNS.pdf)
- 4-antenna GNSS, measured, 2-stage (RF anti-saturation plus "3-tap blind STAP realized by FPGA ... within the IF bandwidth (30 MHz)", p.3):
  - Setup: "a strong interference with the power 50 dB greater than the weak signal is simultaneously transmitted. The direction of arrival weak signal is θ=0°, while the strong interference illuminates in θ=45°"
  - Anti-saturation: 20-25 dB across 1571-1580 MHz (Table 1)
  - Total anti-jamming: 57-61 dB (Table 2), "Around 60 dB anti-jamming performance can be observed for interference ranging from 1570 MHz to 1580 MHz"
  - Metric: "The total anti-jamming performance can be obtained by changing the power of the interference until the terminal loses the function to locate the position." This is a receiver-level tolerance gain, not a pure null depth.
  - Anti-saturation response time 47 µs.

  — [Tan et al., CNCT 2016](https://www.atlantis-press.com/article/25870823.pdf)
- 7-element GNSS array, measured in an anechoic chamber with RF injection and over-the-air radiation, static and on a turntable (abstract):
  - "Dynamic tests simulated UAV maneuvers by placing the receiver on a turntable rotating at 2 °/s"
  - "the J/S ratio threshold for positioning failure decreased from 106 dB against a single continuous-wave jammer to 60 dB against six broadband noise jammers"
  - "In the six-jammer scenario, the system maintained a 100% positioning success rate at a J/S ratio of 70 dB while rotating, paradoxically outperforming its 60 dB static failure threshold."

  Note: these J/S figures include the GNSS despreading gain, so they are not null depths. I read the abstract only. — [Ma Liyun, Chen Yazhou, Zhang Yuxuan et al. 2025, HPLPB 37, 250107](https://www.hplpb.com.cn/en/article/doi/10.11884/HPLPB202537.250107)
- Measured channel-aging limits on spatial interference suppression (MU-MIMO): Argos (2.4 GHz, pedestrian) and LuMaMi (3.7 GHz, up to 29 km/h), quoted in Q2. — [Shepard et al. 2016](https://yecl.org/argos/pubs/Shepard-Asilomar16.pdf); [Harris et al. 2017](https://arxiv.org/pdf/1703.04723)
- STAP vs SAP with a rotating platform (ION GNSS+ 2023, Brachvogel et al.), known only from a magazine summary: "the car was rotated 360° throughout the complete measurement" and STAP "was able to process all satellites for an additional 12 seconds". No dB values were available. UNVERIFIED as to details (secondary summary) — [GPS World research roundup](https://www.gpsworld.com/?p=105611)
- Vendor and secondary claims, all UNVERIFIED (search snippets only, not read):
  - L3Harris N201 4-element CRPA "typical null depth >20 dB" — [L3Harris datasheet (snippet)](https://www.l3harris.com/sites/default/files/2020-10/antenna-n201-series-sas.pdf)
  - ST Engineering 4-element "interference suppression of up to 40 dB" — [everythingrf listing (snippet)](https://www.everythingrf.com/products/anti-jam-solutions/st-engineering/944-1966-gnss-anti-jam-antenna)
  - "three or four antenna elements ... reduce the power of an unintentional interference or jamming signal by 35–45 dB" and "8–10 dB per antenna element" — [Unmanned Systems Technology article (snippet)](https://www.unmannedsystemstechnology.com/feature/improving-uncrewed-gnss-resilience-with-crpa-technology/)
  - Stanford single-antenna null steering "about 15 dB" — [Stanford PURL (snippet)](https://purl.stanford.edu/cf484ht3939)
- Simulated dynamic GNSS results (not measured) are in Q2: Wang et al. 2019 (-113 → -73 → -63 dB with angular rate) and Ji et al. 2025 (CMT tables).

### Inferences
- Measured static suppression for practical 2-4 element arrays clusters around 10-40 dB in communications testbeds and 35-60 dB in GNSS hardware (vendor and receiver-level metrics). So 30 dB JNR is within reach of a static or quasi-static geometry. This matches the coordinator's "static jammer channel → 0 failures".
- None of the measured results involves a Rayleigh/Rician-fading jammer channel at 222-358 Hz Doppler. The only measured motion results are slow geometric changes (2°/s) or MU-MIMO channel aging at pedestrian speeds. Even those already show losses within 1-4 ms at 2.4-5 GHz (Shepard: 90% capacity kept only for 1.1 ms at 2.4 GHz). The project's fd·T is far larger, so the measured literature supports, rather than contradicts, large practical losses at 100-161 km/h.

### Gaps
- No measured null-depth (dB) versus Doppler for a fading jammer with a 2-4 element communications array was found. GNSS dynamic tests report receiver-level J/S, not null depth.
- The full HPLPB 2025 paper and the ION GNSS+ 2023 paper were not read (no further internet allowed).

## Q5. Hardware limits on null depth (channel mismatch, phase noise/independent LOs, I/Q imbalance, ADC/front-end saturation)

### Takeaway
In a real receiver, null depth has a floor set by:
- channel amplitude/phase error (leakage ≈ σ²_φ + σ²_ε, independent of N; Bakr);
- independent-LO phase noise (ICR 22-39 dB over typical phase-noise levels, gaining at most about 3 dB from more antennas; Zhou);
- I/Q imbalance (image leakage at the IRR level, typically 20 dB in the cited model, which a linear MMSE combiner "cannot effectively suppress"; Hakkarainen);
- front-end saturation (Tan).

At 30 dB JNR these floors are of the same order as the jammer, so an ideal receiver with infinite null depth is optimistic even for a static jammer if hardware is modelled. A common LO and frequency-flat mismatch (absorbed by adaptive weights) remove most of the first two.

### Cited Findings
- Phase noise with independent PLLs from a common reference clock:
  - Closed form: eq. (25)-(28) in Q2.
  - Mapping of phase-noise level to variance: "−80 dBc/Hz@1 kHz, −65 dBc/Hz@1 kHz, and −50 dBc/Hz@1 kHz. The corresponding phase noise variances are 1.27 × 10^−4, 3.40 × 10^−3, and 1.07 × 10^−1, respectively."
  - "We find that the ICR in decibel decreases logarithmically linearly with the phase noise variance."
  - "to achieve a typical ICR of 40 dB, by using three auxiliary antennas, the required phase noise variance is 7.5 × 10^−5 rad^2."
  - With a common LO: "For the first type, the phase noises are the same for all the channels. Therefore, the correlations between the array base-band signals are not affected, so a high ICR can still be achieved."
  - Test signal: single-tone interference at 2 MHz sampling.

  — [Zhou et al. 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC8951393/)
- Same paper, reviewing prior work: "In [7], the effects of channel mismatch, I/Q imbalance, and antenna mutual coupling are studied. It is shown that the interference cancellation ratio (ICR) is mainly related to the I/Q imbalance and amplitude-phase perturbations of the channel, but is almost independent of antenna mutual coupling. In [8], the effects of channel uniformity are analyzed. The simulation results show that the PI algorithm can combat channel uniformity when the channel amplitude disturbance does not exceed 7 dB." Ref [7] is Lu et al., CIE Radar 2006 (not read). — [Zhou et al. 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC8951393/)
- Amplitude and phase errors: null depth is limited by gain and phase accuracy, independent of N, with leakage ∝ σ²_φ + σ²_ε (quoted in Q3). — [Bakr & Johnson 2009](https://www2.eecs.berkeley.edu/Pubs/TechRpts/2009/EECS-2009-1.pdf)
- I/Q imbalance in multi-antenna receivers (simulation):
  - "I/Q imbalance is defined in terms of the image rejection ratio (IRR) given in decibels for a single transceiver branch by IRR = 10log10(|K1|²/|K2|²). We set IRR = 20 dB in all transceiver branches."
  - "In contrast to MRC, the LMMSE combiner provides good results also in a MU-MIMO environment due to its built-in capability for inter-user interference suppression. However, it cannot effectively suppress the inter-carrier interference which is caused by I/Q imbalance."
  - "the SINR of MRC is limited to the TX IRR in scenario 2"
  - The widely-linear WL-MMSE "yields the same SINR as a system under ideal I/Q matching, even when operating under TX+RX I/Q imbalances" (p.4)

  — [Hakkarainen, Werner, Renfors, Dandekar, Valkama 2015](https://par.nsf.gov/servlets/purl/10228888)
- Front-end saturation by a strong interferer, measured: "The strong interference working in 1574MHz makes the receiver work in the saturation area ... The saturation introduces other frequencies and leads the serious distortion into the IF front end." The RF anti-saturation stage gave about 21 dB, with 20-25 dB in Table 1. — [Tan et al. 2016](https://www.atlantis-press.com/article/25870823.pdf)
- UNVERIFIED (snippets only, sources not identified or read):
  - "a null depth of 35 dB degrades by 6 dB with a 1 degree phase error"
  - "for a rejection of -25 dB, the errors must be held to about 0.5 dB in amplitude and 2.80 degrees in phase"
  - "Fixed amplitude and phase offsets do not limit cancellation. Frequency-dependent channel-to-channel mismatches, however, do limit cancellation."

  — [search results, sources not read](https://apps.dtic.mil/sti/pdfs/ADA134596.pdf)

### Inferences
- Applying Bakr's leakage = σ²_φ + σ²_ε (my calculation):
  - 0.1 dB / 1°: about -33.6 dB
  - 0.2 dB / 2°: about -27.5 dB
  - 0.5 dB / 2.8°: about -22.3 dB

  The last is close to the UNVERIFIED "-25 dB for 0.5 dB / 2.8°", which may use a different definition. A static, frequency-flat mismatch is absorbed by adaptive weights computed from the received data. Only mismatch that differs between estimation and use (time drift, frequency-dependent mismatch across the band, independent LO phase noise) limits an adaptive null. That part is my reasoning, supported only by the UNVERIFIED snippet above.
- Phase noise with independent PLLs (Zhou eq. (26)-(27), my evaluation):
  - δ² = 1.27e-4: ICR 36.0 dB (N = 1) to 39.0 dB (N → ∞)
  - δ² = 3.4e-3: ICR 21.7 dB (N = 1) to 24.7 dB (N → ∞)

  At 30 dB JNR the first leaves the residual below noise; the second leaves it about 5-8 dB above noise. A shared LO removes this term.
- I/Q imbalance: at IRR = 20-30 dB, a 30 dB jammer leaves an image 0-10 dB above noise. A linear MMSE cannot null it simultaneously, per Hakkarainen et al. A widely-linear combiner can.
- Overall (inference): the ideal MMSE/MVDR used as the reference in the project is over-optimistic for two separate reasons:
  1. it ignores covariance aging under Doppler (dominant here, Q2);
  2. it has no hardware null-depth floor (30-40 dB class floors are typical of the cited analyses).

  A real 3-antenna receiver can plausibly hold a 30 dB JNR link for a static or slowly varying jammer with matched, common-LO hardware. It cannot hold it with a covariance estimated once per 0.5 ms frame against a jammer whose diffuse component fades at 222-358 Hz, unless the covariance or weights track within the frame.

### Gaps
- No source I read gives ADC dynamic-range or quantization limits on adaptive null depth in numbers. Only front-end saturation (Tan) is covered.
- Lu et al. 2006 (channel mismatch / I/Q / coupling numbers for GPS arrays) was not read.

#### Files saved to the sources folder (C:\Users\Adi Suliman\Desktop\תואר ראשון  הנדסת חשמל ואלקטרוניקה\שנה ד\פרוייקט גמר\מקורות)
- V7_Cheng2026_Fundamental_Limits_Adaptive_Beamforming_Finite_Training.pdf
- V7_Besson2021_Adaptive_Multichannel_Filters_SNR_Loss_Overview.pdf
- V7_Bakr2009_Phase_Amplitude_Errors_Array_Null_Depth.pdf
- V7_Tan2016_GPS_4Antenna_AntiSaturation_AntiJamming_Experiment.pdf
- V7_Hakkarainen2015_IQ_Imbalance_WL_Spatial_Processing_Large_Arrays.pdf
- V7_Gershman1996_Robust_Beamforming_Moving_Jammer_EUSIPCO.pdf
- V7_Truong2013_Channel_Aging_Massive_MIMO.pdf
- V7_Shepard2016_Real_ManyAntenna_MUMIMO_Channels_Mobility.pdf
- V7_Zumegen2024_BeamArmor_5G_Null_Steering_AntiJamming.pdf
- V7_Wang2025_Jamming_Resistant_UAV_Multichannel.pdf
- V7_Marti2023_Single_Antenna_Jammers_MIMO_OFDM.pdf
- V7_Li2017_Null_Broadening_Covariance_Matrix_Expansion_ACES.pdf
- V7_Harris2017_Temporal_Analysis_LOS_Massive_MIMO_Mobility.pdf
- V7_Huang2010_Spatial_Interference_Cancellation_MANET_Imperfect_CSI.pdf
- Already present, not re-saved: V7_Zeng2017_Jamming_Resistant_MIMO_JrRx_CNS.pdf

#### Read in full online (open access) but PDF not saved (internet stopped before download)
- Zhou, Wang, He, Meng 2022, Sensors 22:2362, DOI 10.3390/s22062362 — https://pmc.ncbi.nlm.nih.gov/articles/PMC8951393/
- Ji, He et al. 2025, Sensors 25:1499, DOI 10.3390/s25051499 — https://pmc.ncbi.nlm.nih.gov/articles/PMC11902554/
- Wang, Chang et al. 2019, Sensors 19:1661, DOI 10.3390/s19071661 — https://pmc.ncbi.nlm.nih.gov/articles/PMC6479994/
- US 6,147,985 B (Bar-David, Golden, Winters), text — https://patents.google.com/patent/US6147985A/en (PDF: https://patentimages.storage.googleapis.com/54/be/48/28793df0a5d85d/US6147985A.pdf)
- Ma Liyun et al. 2025, HPLPB 37:250107 (abstract only) — https://www.hplpb.com.cn/en/article/doi/10.11884/HPLPB202537.250107

#### COULD NOT DOWNLOAD
- Reed, Mallett, Brennan, "Rapid Convergence Rate in Adaptive Arrays," IEEE TAES AES-10(6):853-863, Nov 1974. DOI 10.1109/TAES.1974.307893. https://doi.org/10.1109/TAES.1974.307893 (paywall)
- Boroson, "Sample Size Considerations for Adaptive Arrays," IEEE TAES AES-16(4):446-451, Jul 1980. DOI 10.1109/TAES.1980.308973. https://doi.org/10.1109/TAES.1980.308973 (paywall)
- Carlson, "Covariance matrix estimation errors and diagonal loading in adaptive arrays," IEEE TAES 24(4):397-401, Jul 1988. DOI 10.1109/7.7181. https://doi.org/10.1109/7.7181 (paywall)
- Mailloux, "Covariance matrix augmentation to produce adaptive array pattern troughs," Electronics Letters 31(10):771-772, 1995 (DOI not verified). Symposium version: IEEE APS 1995 Digest vol.1 pp.102-105, DOI 10.1109/APS.1995.529973. https://doi.org/10.1109/APS.1995.529973 (paywall)
- Zatman, "Production of adaptive array troughs by dispersion synthesis," Electronics Letters 31(25):2141-2142, 1995. DOI 10.1049/el:19951486. https://doi.org/10.1049/el:19951486 (paywall)
- Zatman, "How narrow is narrowband?," IEE Proc. Radar, Sonar & Navigation 145(2):85-91, 1998. DOI 10.1049/ip-rsn:19981670. https://doi.org/10.1049/ip-rsn:19981670 (paywall)
- Guerci, "Theory and application of covariance matrix tapers for robust adaptive beamforming," IEEE TSP 47(4):977-985, 1999. DOI 10.1109/78.752596. https://doi.org/10.1109/78.752596 (paywall)
- Winters, "Signal acquisition and tracking with adaptive arrays in the digital mobile radio system IS-54 with flat fading," IEEE TVT 42(4):377-384, 1993. DOI 10.1109/25.260776. https://doi.org/10.1109/25.260776 (paywall)
- Ward, "Space-Time Adaptive Processing for Airborne Radar," MIT Lincoln Laboratory TR-1015, 1994, DTIC ADA293032. https://apps.dtic.mil/sti/pdfs/ADA293032.pdf (free, but DTIC returned "Service unavailable"/403 to automated download)
- "Adaptive Beamforming with Imperfect Arrays: Pattern Effects and Their Partial Correction," DTIC ADA267079. https://apps.dtic.mil/sti/html/tr/ADA267079/index.html (free, DTIC blocked: 403)
- Fante & Vaccaro (MITRE), "Evaluation of Adaptive Space-Time-Polarization Cancellation of Broadband Interference" and related MITRE papers. https://mitre.org/sites/default/files/publications/fante_evaluation.pdf ("Access Denied" to automated download)
- Lu, Yan, Yuan, Wu, Dai, Yuan, "The effect of channel mismatch and mutual coupling on GPS adaptive antenna array," CIE Int. Conf. on Radar 2006, pp.1-5 (DOI not known; not attempted after the internet stop)
- Brachvogel, Niestroj, Meurer et al., "Space-Time Adaptive Processing as a Solution for Mitigating Interference Using Spatially-Distributed Antenna Arrays," ION GNSS+ 2023 (DOI not known; known only via GPS World summary)
