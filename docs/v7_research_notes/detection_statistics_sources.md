# Detection, open-set / OOD, change-detection and statistics sources: re-review for v7

Scope and conventions:
- **Read in full:** P06 Lee 2018, P07 Liu 2008, N07 Shebert 2023, P12 Thulin (arXiv v1 and the EJS version), W04 Xie 2022, S06 JamShield, S08 Keep It Simple, S09 Yu 2020 (withdrawn), S13 Zhong 2025, and the readable Brown 2001 copy.
- **Read in the relevant parts:** P03 Tariq 2026 (detection, imbalance, zero-day and hybrid passages of a 34-page review) and four newly downloaded papers (Hendrycks & Gimpel 2017, Liu et al. 2020, Hendrycks et al. 2019, Xie et al. 2021).
- **Project background (read-only):** the ranking file `דירוג מקורות וחולשות הפרויקט.md`, `uav-gcs-v6/docs/DECISIONS.md`, and two v6 code files used to check one point: `code/detection/run_dataset_sweep.m` and `code/link/build_threat_model.m`.
- **Quotations.** The copyright policy in this environment limits verbatim quotation, so findings are close paraphrases. Each one carries an exact locator (page, section, table, equation or algorithm) so the original sentence can be copied from the PDF. Numbers are given exactly as printed. The only verbatim fragment is two words from Brown et al. 2001.
- **UNVERIFIED** marks anything not read in the source itself.

---

## 1. What each source is, what it did, and what it reports (citation, method, data, numbers, locations)

### Takeaway
- **Core statistical and OOD methods.** The KPI 2 unknown-threat score (Mahalanobis, last hidden layer, tied covariance, Algorithm 2) and the KPI 6 exact binomial bound rest on primary sources that were read: Lee 2018, Thulin 2014 and now a readable Brown 2001. Isolation Forest rests on Liu 2008.
- **Supporting sources.** Shebert, Tariq and Zhong are applied or review sources that support framing, not specific numbers.
- **Weak sources.** JamShield and Keep It Simple are marginal preprints. Yu 2020 is withdrawn.

### Cited Findings

#### P06: Lee, Lee, Lee & Shin, "A Simple Unified Framework for Detecting Out-of-Distribution Samples and Adversarial Attacks", NeurIPS 2018
Library file is arXiv:1807.03888v2.
- **Method (§2.1, Eq. 1–2, p. 3).** Fit class-conditional Gaussians with one tied covariance to the penultimate features of a pre-trained softmax network, using empirical class means and the ML tied covariance. Score = minus the smallest Mahalanobis distance to any class mean. No retraining is needed. — [Lee 2018](https://arxiv.org/abs/1807.03888)
- **Why it works (§2.1).** A generative classifier under GDA (LDA) with a tied covariance has a posterior equivalent to a softmax classifier. Abnormal samples are argued to be better separated in feature space than in the label-overfitted softmax output. — [Lee 2018](https://arxiv.org/abs/1807.03888)
- **Two calibration techniques (§2.2, Algorithm 1, p. 4).**
  - Input pre-processing: a small signed-gradient perturbation that increases the score (Eq. 4).
  - Feature ensemble: per-layer scores combined by weights from a logistic regression fitted on validation samples.
  - Lee states that ineffective layers should receive near-zero weight. — [Lee 2018](https://arxiv.org/abs/1807.03888)
- **Algorithm 2 (class-incremental, p. 5).**
  - New class mean from its samples, and that class's own covariance.
  - Shared covariance update: Σ ← C/(C+1)·Σ + 1/(C+1)·Σ_{C+1}.
  - New classes are added without retraining the deep model. — [Lee 2018](https://arxiv.org/abs/1807.03888)
- **Table 1 (p. 6; ResNet-34 trained on CIFAR-10, SVHN as OOD).** Each row gives TNR at TPR 95% / AUROC / detection accuracy / AUPR-in / AUPR-out. — [Lee 2018](https://arxiv.org/abs/1807.03888)
  - Baseline (max softmax): 32.47 / 89.88 / 85.06 / 85.40 / 93.96.
  - ODIN: 86.55 / 96.65 / 91.08 / 92.54 / 98.52.
  - Mahalanobis with neither technique: 54.51 / 93.92 / 89.13 / 91.56 / 95.95.
  - With one technique: 92.26 / 98.30 and 91.45 / 98.37 (TNR / AUROC). Which row is input pre-processing and which is the feature ensemble could not be recovered from the text layer: UNVERIFIED mapping.
  - With both techniques: 96.42 / 99.14 / 95.75 / 98.26 / 99.60.
- **Headline numbers (Introduction, p. 2).**
  - TNR on LSUN with CIFAR-100 as in-distribution (ResNet): 45.6% (ODIN) → 90.9%.
  - CW adversarial attack: 82.9% (LID) → 95.8%.
  - DenseNet with CIFAR-100 in-distribution, LSUN as OOD: 41.2% → 91.4% (p. 7). — [Lee 2018](https://arxiv.org/abs/1807.03888)
- **Hyperparameter tuning (§3.1, p. 6).**
  - Hyperparameters are tuned on a separate validation set of 1,000 images per in/OOD pair, with nested cross-validation for the logistic weights.
  - Alternatively, they can be tuned with in-distribution samples plus FGSM adversarial samples, with no OOD data.
  - The Introduction (p. 2) claims tuning on in-distribution samples alone is enough. — [Lee 2018](https://arxiv.org/abs/1807.03888)
- **Noise magnitudes (Supplement B.1).**
  - The noise magnitude is chosen from {0, 0.0005, 0.001, 0.0014, 0.002, 0.0024, 0.005, 0.01, 0.05, 0.1, 0.2}.
  - Metrics: TNR = TN/(FP+TN) at TPR = 95%; AUROC; AUPR-in/out; detection accuracy. — [Lee 2018](https://arxiv.org/abs/1807.03888)
- **Class-incremental results (§3.3, p. 9).** After all new classes are added, AUC is:
  - 40.0% vs 32.7% (softmax) and 32.9% (Euclidean), half of CIFAR-100 as new classes.
  - 22.1% vs 15.6% and 17.1%, ImageNet classes as new.
  - Absolute new-class performance is modest. — [Lee 2018](https://arxiv.org/abs/1807.03888)
- **Datasets.** Images only (CIFAR-10/100, SVHN, TinyImageNet, LSUN). OOD sets are different image datasets, i.e. far-OOD. — [Lee 2018](https://arxiv.org/abs/1807.03888)

#### P07: Liu, Ting & Zhou, "Isolation Forest", ICDM 2008
Standard DOI 10.1109/ICDM.2008.17 (not printed in the extract).
- **Method (§2, Eq. 1–2).** Random axis-parallel splits isolate points. Anomalies, being few and different, have short average path length E(h(x)). The score is s(x,n) = 2^(−E(h(x))/c(n)), with c(n) = 2H(n−1) − 2(n−1)/n. s → 1 means anomaly; s ≈ 0.5 everywhere means no distinct anomaly. — [Liu 2008](https://doi.org/10.1109/ICDM.2008.17)
- **Settings (§4.1).**
  - Two parameters only: t (number of trees) and ψ (subsample size).
  - ψ = 2^8 = 256 is the default and generally enough; t = 100 is the default because path lengths converge well before it.
  - Height limit is ceiling(log2 ψ). Training costs O(tψ log ψ). — [Liu 2008](https://doi.org/10.1109/ICDM.2008.17)
- **Small subsamples reduce swamping and masking (§3, Fig. 4).** On Mulcross, AUC is 0.67 with the full 4096-point sample and 0.91 with ψ = 128. — [Liu 2008](https://doi.org/10.1109/ICDM.2008.17)
- **Table 3 (iForest AUC).** Http 1.00, ForestCover 0.88, Mulcross 0.97, Smtp 0.88, Shuttle 1.00, Mammography 0.86, Annthyroid 0.82, Satellite 0.71, Pima 0.67, Breastw 0.99, Arrhythmia 0.80, Ionosphere 0.85. — [Liu 2008](https://doi.org/10.1109/ICDM.2008.17)
- **Subsample size (§5.2).** AUC is near optimal at ψ = 128 (Http) and ψ = 512 (ForestCover). Processing time grows only modestly from ψ = 4 to 8192. — [Liu 2008](https://doi.org/10.1109/ICDM.2008.17)
- **Normal-only training (§5.4).**
  - Without anomalies in training, AUC drops from 0.9997 to 0.9919 on Http and from 0.8817 to 0.8802 on ForestCover.
  - Raising ψ from 256 to 8,192 (Http) and to 512 (ForestCover) restores 0.9997 and 0.884. — [Liu 2008](https://doi.org/10.1109/ICDM.2008.17)
- **High dimensions (§5.3).** iForest also suffers from the curse of dimensionality. With 506 irrelevant attributes, a Kurtosis-based attribute selection per tree helps. — [Liu 2008](https://doi.org/10.1109/ICDM.2008.17)

#### N07: Shebert, Kirk & Buehrer, "Open Set Wireless Signal Classification: Augmenting Deep Learning with Expert Feature Classifiers"
arXiv:2302.03749v1, 7 Feb 2023. The arXiv page shows no journal reference: preprint only.
- **System (Fig. 2, §II).** Energy detection, then signal isolation in time, frequency and space, then a CNN on two 65,536-point FFT magnitudes (about 1 ms at 125 MHz).
- **The hybrid is a cascade.** The CNN's top-2 classes decide which protocol expert classifiers run. Those experts use synchronization signals and a CRC check. — [Shebert 2023](https://arxiv.org/abs/2302.03749)
- **Spatial isolation (§II.B.3, Eq. 2–7, Algorithm 1).**
  - The number of signals M is estimated by thresholding covariance eigenvalues at 1.1 × the noise eigenvalue. The method can detect up to Mr − 1 signals (Mr = number of antennas).
  - MUSIC estimates the direction of arrival, then an MMSE beamformer w = R̂⁻¹a(θ̂) separates the co-frequency signals. — [Shebert 2023](https://arxiv.org/abs/2302.03749)
- **Open-set rule (§II.E, Eq. 8–9, Algorithm 2).**
  - Softmax is called unsuitable for open-set problems, because its normalization assumes the classes are collectively exhaustive.
  - Sigmoid outputs are thresholded instead (rule taken from DOC, Shu et al. 2017). — [Shebert 2023](https://arxiv.org/abs/2302.03749)
- **Data (§III).**
  - Known set: 6,720 signals (960 per standard), bootstrapped into 201,600 one-ms samples, split 80/10/10.
  - Unknown set: 480 signals, bootstrapped into 14,400.
  - Over-the-air set: 7,000 samples at 3 GHz, about 10 dB in-band SNR.
  - Training impairments: Rician K 1–10, Doppler 50–200 Hz; training SNR −5 to 20 dB in-band, test −20 to 20 dB.
  - WiFi 6 traffic is made by inserting idle periods between packets (§III.A.2). — [Shebert 2023](https://arxiv.org/abs/2302.03749)
- **Results (§IV).**
  - Closed-set CNN: about 97% above 15 dB, approaching 98.5%; 98% over the air vs 97.6% synthetic at 10 dB.
  - Co-frequency signals with a 4-element ULA (§IV.B): 2 emitters 93% at 20 dB, 3 emitters 68%. The theoretical MMSE gain is 6 dB; 3–5 dB is realized.
  - Open set (§IV.C, Fig. 8): the threshold is chosen for an 85% known-class accuracy target (threshold 6, 10 dB). AM/FM detected as unknown 100%, SC 95%, OFDM/SC-FDMA below 1%.
  - Open-set CNN cost: over 5 dB SNR loss and −7% maximum accuracy.
  - Hybrid (§IV.E, §V): 97% known and about 100% unknown at 20 dB. That is +5% (known) and +40% (unknown) vs the CNN, at 2–7× less complexity than the experts. — [Shebert 2023](https://arxiv.org/abs/2302.03749)
- **Expert-classifier false alarm (Table II).** Pfa ≈ 2^(1−n) for an n-bit CRC: LTE/NB-IoT 1.53e-5, 5G/BLE 5.96e-8, WiFi 6 3.12e-2.
- **Complexity (Table V).** CNN 36.6e6 additions; average expert 31,570e6 (known) and 55,250e6 (unknown); hybrid 7,929–15,820e6. — [Shebert 2023](https://arxiv.org/abs/2302.03749)
- **Their own limitation (§V).** Understanding the false-alarm rate of deep open-set models is open research; it currently rests on empirical analysis. — [Shebert 2023](https://arxiv.org/abs/2302.03749)

#### P03: Tariq, Ahanger & Ihsan, "Systematic review of machine and deep learning models for unmanned aerial vehicles cyber threat defense", Discover Artificial Intelligence 6:216 (2026)
Open access, DOI 10.1007/s44163-026-00960-7.
- **Review protocol.** ROBINS-I risk-of-bias tiers; studies rated Serious risk were kept as provisional (§3.1).
- **Imbalance handling (p. 15, item b).** Coded as resampling, cost-sensitive loss, threshold tuning, or macro/weighted reporting. Macro-F1 and PR-AUC are favoured when classes are skewed. — [Tariq 2026](https://doi.org/10.1007/s44163-026-00960-7)
- **Accuracy (p. 15, item c).** Treated as descriptive unless class priors and averaging rules are stated. — [Tariq 2026](https://doi.org/10.1007/s44163-026-00960-7)
- **Zero-day claims (§4.4, p. 24).** Accepted only if the target attack class was absent from training. Leave-one-family-out splits, cross-dataset tests, or normal-only learning with open-set scoring count as evidence. — [Tariq 2026](https://doi.org/10.1007/s44163-026-00960-7)
- **Hybrid detector, via its ref. [81] (p. 21, Table 8).**
  - Abdullayeva & Valikhanli (2025) combine an MLP on UAV telemetry with a CNN on GPS-signal spectrograms, classifying 5 GPS jamming types.
  - CNN branch about 94.7%, MLP 96.3%, combined 99%.
  - Tariq notes these were validated on curated or lab (SDR-generated) data, with flight validation left as future work. — [Tariq 2026](https://doi.org/10.1007/s44163-026-00960-7)
- **Other points.**
  - Many studies report accuracy and F1 but omit end-to-end latency (p. 3).
  - Learned actions should be constrained by rule checks, a safety shield and a deterministic fallback (p. 19).
  - RL controllers outperform static rule-based strategies in simulation (p. 7). — [Tariq 2026](https://doi.org/10.1007/s44163-026-00960-7)
- **Quality flags.**
  - Reference numbering is inconsistent: Table 7 tags SSRL-UAVs as [78], while ref. 78 is Sormayli et al. and the text cites SSRL-UAVs as [80].
  - Running headers carry typos ("(206) 6:21"). — [Tariq 2026](https://doi.org/10.1007/s44163-026-00960-7)

#### P12: Thulin, "The cost of using exact confidence intervals for a binomial proportion", Electronic Journal of Statistics 8 (2014) 817–840
DOI 10.1214/14-EJS909.
- **Library version.** The library file `P12_Thulin2014…` is arXiv:1303.1288v1 (6 Mar 2013), not the EJS version. The EJS version is now saved as `V7_Thulin2014_EJS_…`.
- **Two-sided Clopper–Pearson (§2.1, Eq. 1–4).**
  - It inverts the equal-tailed binomial test; the endpoints are Beta quantiles.
  - At X = 0 the two-sided interval is (0, 1 − (α/2)^(1/n)).
  - The Theorem 1 expansions are good for n ≥ 40. — [Thulin 2014](https://doi.org/10.1214/14-EJS909)
- **One-sided bound (§2.1, Eq. 5).** The one-sided upper bound solves Σ_{k≤X} C(n,k) p^k (1−p)^(n−k) = α. — [Thulin 2014](https://doi.org/10.1214/14-EJS909)
- **Why exactness (§1).** Exact methods guarantee coverage ≥ 1 − α for every p, and some regulators require them. The binomial model is often known to be exactly right. — [Thulin 2014](https://doi.org/10.1214/14-EJS909)
- **Cost of exactness (§3.3, Corollary 1).** E(L_CP) = E(L_Jeffreys) + 1/n + O(n⁻²), and = E(L_Wilson or Agresti–Coull) + 1/n + O(n^(−3/2)). At d = 0.05, exactness costs about 40 extra samples for 0.05 ≤ p0 ≤ 0.95.
- **Sample-size example (§3.2).** At p0 = 0.05, d = 0.05 the exact requirement is 329 and the approximation gives 331. — [Thulin 2014](https://doi.org/10.1214/14-EJS909)
- **Discussion (§5).** Bootstrap and MCMC methods control confidence levels only approximately, on average (§5.1). At n = 250 over p ∈ [0.01, 0.99], minimum coverage is about 0.88 for Jeffreys, 0.93 for Wilson and 0.94 for Agresti–Coull, with Jeffreys and Wilson still not above 0.94 at n = 2000 (§5.2). — [Thulin 2014](https://doi.org/10.1214/14-EJS909)

#### P12x / V7: Brown, Cai & DasGupta, "Interval Estimation for a Binomial Proportion", Statistical Science 16(2):101–133 (2001)
DOI 10.1214/ss/1009213286.
- **The Wald interval is erratic (§1–2, pp. 101–103).**
  - At p = 0.5, coverage is 0.953 at n = 17 but 0.919 at n = 40.
  - At p = 0.005, coverage is 0.945 at n = 591 and 0.792 at n = 592; Table 2 lists later unlucky n (954, 1279, 1583, 1876). — [Brown 2001](https://doi.org/10.1214/ss/1009213286)
- **Recommendations (pp. 102–103, §5).** Wilson or equal-tailed Jeffreys for n ≤ 40; Agresti–Coull for n > 40 for simplicity. — [Brown 2001](https://doi.org/10.1214/ss/1009213286)
- **Clopper–Pearson (§4.2.1, p. 113).** Coverage is always ≥ nominal but can be much larger. The authors call it "wastefully conservative" and not a good practical choice unless strict coverage is demanded; even then, better exact methods exist (Blyth–Still, Casella). — [Brown 2001](https://doi.org/10.1214/ss/1009213286)
- **One-sided intervals (p. 103).** Skewness error can exceed rounding error, so one-sided behaviour differs from two-sided. — [Brown 2001](https://doi.org/10.1214/ss/1009213286)
- **Modified Jeffreys at the boundary (§4.1.2).** U(0) = 1 − (α/2)^(1/n). — [Brown 2001](https://doi.org/10.1214/ss/1009213286)

#### W04: Xie, Moustakides & Xie, "Window-Limited CUSUM for Sequential Change Detection"
arXiv:2206.06777v2, 18 May 2023. A web search reports it as IEEE Trans. Inf. Theory 69(9), Sept 2023; the published version was not opened.
- **Classical CUSUM (§III.B, Eq. 2–4).**
  - Recursion S_t = (S_{t−1} + log f0(ξt)/f∞(ξt))⁺; stop at S_t ≥ ν.
  - CUSUM exactly minimizes Lorden's worst-case delay subject to ARL ≥ γ (Moustakides 1986, their ref. [13]).
  - Lemma 1: with ν = log γ, the delay is about log γ / I0 (I0 = KL divergence).
  - It assumes i.i.d. data before and after the change, and a known pre-change density, e.g. estimated from historical data (§III.A). — [Xie 2022](https://arxiv.org/abs/2206.06777)
- **WLCUSUM (§IV).** The unknown post-change parameter is replaced by an estimate from a sliding window of w samples. It is first-order asymptotically optimal if w → ∞ with w = o(log γ), whereas window-limited GLR needs w = Θ(log γ) (Theorem 2, Remark 7). A parallel version runs windows 1..W, so the optimal w need not be known (§VI). — [Xie 2022](https://arxiv.org/abs/2206.06777)
- **Experiments (§VII; 1,000 trials per point; Gaussian mean shift; K = 1, 5, 10; Laplace→Normal).**
  - Parallel WLCUSUM (W = 15) is close to the optimal-window WLCUSUM.
  - Window-limited GLR with too small a window (10 vs 30) degrades sharply.
  - For small shifts (θ = 0.3, barrier 0.1), WLCUSUM is better than GLR. — [Xie 2022](https://arxiv.org/abs/2206.06777)
- **Data.** No wireless or real data are used. — [Xie 2022](https://arxiv.org/abs/2206.06777)

#### S06: Panitsas, Yigit, Tassiulas, Maglaras & Canberk, "JamShield: A Machine Learning Detection System for Over-the-Air Jamming Attacks"
arXiv:2507.11483v1 (2025), preprint; venue UNVERIFIED.
- **Testbed (§II).**
  - 80 m² lab, 802.11 AP on channel 6 (2.437 GHz, 20 MHz), USRP X310 jammer.
  - Constant, random and reactive jammers. The reactive jammer triggers above −65 dBm, following Puñal et al. 2014.
  - iperf3 UDP traffic at 1 Mbps; cross-layer metrics sampled every 0.5 s. — [JamShield 2025](https://arxiv.org/abs/2507.11483)
- **Pipeline (§III).** 40 cross-layer features reduced to 20 by PCA + mutual-information voting. An AutoCM module picks among KNN/DT/LSTM/SVM/MLP/RF, with per-classifier sensitivity thresholds of 0.90–0.925. — [JamShield 2025](https://arxiv.org/abs/2507.11483)
- **Data and results (Table I, §IV).**
  - 29,896 benign records, about 3:1 benign to malicious, 70/30 split, 10-fold CV, binary task.
  - Precision 88.5%, recall 90.3%, "detection rate" 97.9%, F1 89.4%, false alarm 3.9%, misdetection 9.7%. — [JamShield 2025](https://arxiv.org/abs/2507.11483)
- **Dataset availability.** Public on GitHub and IEEE Dataport (DOI 10.21227/5hzf-w161). It holds network-driver metrics, not IQ samples. — [JamShield 2025](https://arxiv.org/abs/2507.11483)

#### S08: Oyedare, Shah, Jakubisin & Reed, "Keep It Simple: CNN Model Complexity Studies for Interference Classification Tasks"
arXiv:2303.03326v1 (2023); venue UNVERIFIED.
- **Model sizes (Table I).** Simple, medium and complex CNNs have 6.1k, 48k and 276k parameters. — [Oyedare 2023](https://arxiv.org/abs/2303.03326)
- **Main finding (Table III, Fig. 3).** The simple CNN performs close to the complex ones. Overfitting shrinks to within about 5% as the dataset grows. — [Oyedare 2023](https://arxiv.org/abs/2303.03326)
- **Interference classification (§V.B, Fig. 2).** ResNet18 reaches 97.8% on the RFI dataset (CWI, MCWI, chirp). On CRAWDAD (15 classes of 802.11b/g, 802.15.4 and Bluetooth devices) it reaches 80%. It cites multi-label interference identification (Grunau et al. 2018, ref. [9]). — [Oyedare 2023](https://arxiv.org/abs/2303.03326)

#### S09: Yu, Alhassoun & Buehrer, "Interference Classification Using Deep Neural Networks"
arXiv:2002.00533. v1 is from 3 Feb 2020; v2 (7 Apr 2020) is withdrawn, with the comment that the paper was rejected and needs more editing.
- **Content of v1 (the extract).**
  - Five interference types; PSD input beats cyclic spectrum and raw samples; the DNN beats kNN, SVM and RF.
  - Accuracy stays at or above 90% over at least a 15 dB dynamic range.
  - On combinations (Fig. 10) overall accuracy is 72.71%, with filtered noise the hardest row (46.2%). — [Yu 2020](https://arxiv.org/abs/2002.00533)

#### S13: Zhong, Cui & Ji, "Energy-based jamming pattern open set recognition via spiking wavelet transformer", PLoS ONE 20(6): e0325381 (2025)
CC BY, DOI 10.1371/journal.pone.0325381.
- **Method.**
  - STFT image, then a Spiking Wavelet Transformer, then fixed max-separation class vectors on a hypersphere (MCS).
  - Energy E(x) = −T·log Σ exp(logit/T), with T = 1 (Eq. 9).
  - Training uses cross-entropy plus a squared-hinge energy loss on auxiliary OOD data, which is Gaussian white and coloured noise (Eq. 10–11, p. 12).
  - Algorithm 1 (p. 10) computes per-class thresholds θc = μc + λσc (λ = 2.0, EMA α = 0.9, updates only when p > 0.9), but the decision uses the global θ = max_c θc (line 17). — [Zhong 2025](https://doi.org/10.1371/journal.pone.0325381)
- **Data (Tables 1–2).** 9 synthetic jamming patterns at JSR −4 to 10 dB; 6 known and 3 unknown, rotated. Combination 4 adds the Kaggle WLAN spectral-scan dataset with deceptive and constant jammers as known and the reactive jammer as unknown. — [Zhong 2025](https://doi.org/10.1371/journal.pone.0325381)
- **Results.**
  - Known classes: 99.5% average at JSR > −2 dB, 93.4% at −4 dB; unknown classes 96.4% on average (Fig. 4b, first three combinations only).
  - Table 3 (5 runs), as TNR / TPR / F1: theirs 95.36 / 99.48 / 99.35; Mahalanobis baseline 86.24 / 97.58 / 94.85; MSP+ODIN F1 97.65; OpenMax F1 94.89.
  - Latency 6.3 ms on an RTX 3090 (Table 4); ablation F1 99.30 vs 95.47 without SWT and 96.82 without MCS (Table 6). — [Zhong 2025](https://doi.org/10.1371/journal.pone.0325381)
- **Their limitation (p. 17).** The rule assumes unknown jammers raise the energy score; a low-power or masked adversary could break that. — [Zhong 2025](https://doi.org/10.1371/journal.pone.0325381)

#### New OOD and change-detection references downloaded this session (read in the parts used)
- **Hendrycks & Gimpel, ICLR 2017 (MSP baseline).**
  - The maximum softmax probability is the baseline OOD and error score.
  - Random Gaussian noise fed to an MNIST classifier gets 91% confidence (§1).
  - AUROC is not ideal when base rates differ; AUPR can be more informative (§2).
  - A footnote gives an explicitly imprecise AUROC scale: 90–100 excellent, 80–90 good, 70–80 fair, 60–70 poor. — [Hendrycks 2017](https://arxiv.org/abs/1610.02136)
- **Liu, Wang, Owens & Li, NeurIPS 2020 (energy score).**
  - E(x;f) = −T·log Σ exp(f_i/T) is parameter-free and usable on any pre-trained classifier. Its threshold is set from in-distribution data (§3.1).
  - It cuts the average FPR95 by 18.03% vs softmax on CIFAR-10 (WideResNet).
  - Energy fine-tuning with auxiliary outliers cuts FPR95 by 10.55% vs Outlier Exposure on CIFAR-100. — [Liu 2020](https://arxiv.org/abs/2010.03759)
- **Hendrycks, Mazeika & Dietterich, ICLR 2019 (Outlier Exposure).**
  - Fine-tune with an auxiliary outlier set, using cross-entropy to the uniform distribution (for class imbalance: to the class prior).
  - The outlier set must be realistic and diverse: Gaussian-noise outliers did not generalize, and synthetic anomalies worked worse than real data.
  - Example: CIFAR-10 WRN FPR95 34.94% → 9.50% when fine-tuned with OE (appendix). — [Hendrycks 2019](https://arxiv.org/abs/1812.04606)
- **L. Xie, Zou, Y. Xie & Veeravalli, IEEE JSAIT 2(2) 2021 (survey).**
  - Shewhart charts use only the current observation and lose information (§II.C-1).
  - CUSUM (Page) uses the past and gains most for small changes (§II.C-2). It is asymptotically optimal (Lorden) and exactly optimal (Moustakides; Ritov) under Lorden's criterion (§II.D-1).
  - FAR = 1/ARL (Eq. 6).
  - EWMA needs no knowledge of the pre- or post-change distributions (§II.E-2).
  - Lai's generalized CUSUM covers non-i.i.d. data (§III.A); GLR or mixture tests handle unknown post-change parameters (§II.E-1).
  - Wireless applications (§V.D) include sequential detection of channel occupancy and idleness from primary-user activity in cognitive radio. Cybersecurity applications (§V.B) include multi-channel CUSUM over multi-layer network data. — [Xie 2021](https://arxiv.org/abs/2104.04186)

### Inferences
- **Lee's evidence is far-OOD (different image datasets).** The project's held-out threats are near-OOD (same receiver, similar physics). Lee therefore supports the method, not the expected AUROC level. Shebert's §IV.C result shows the near-OOD failure mode in RF: OFDM/SC-FDMA, which resemble known standards, are almost never flagged.
- **The project uses Lee's weakest variant.** It uses last-layer Mahalanobis without input pre-processing or ensemble. In Lee's Table 1 that variant is the weakest (TNR95 54.51% vs 96.42% with both techniques), so the project's KPI 2 score is the base method of Lee, not the full method.
- **Liu §5.4 supports ψ = 8192.** It is the paper's own remedy for training without anomalies, which is exactly the project's known-frames-only setting.

### Gaps
- Lee's published NeurIPS page range and Liu's ICDM page range were not in the extracts (UNVERIFIED citation details).
- Lee Table 1 row mapping for the single-technique rows: UNVERIFIED (text layer lost the check marks).
- Xie 2022's published IEEE version was not opened (venue from a web search only).

---

## 2. Is the project's use of each source backed by the text? (overreach check)

### Takeaway
- **Mostly backed.** The Mahalanobis score, tied covariance and Algorithm 2 (Lee) are backed, and so are the Isolation Forest settings (Liu, incl. ψ = 8192 for normal-only training), the exact one-sided bound (Thulin), LOTO for zero-day claims and macro-F1 under imbalance (Tariq), and softmax unsuitability (Shebert).
- **Overreach.**
  1. Shebert's "hybrid" is a CNN→protocol-expert cascade, not a CNN+feature network.
  2. "Three antennas null two interferers (Shebert)" is only partly supported.
  3. The CNN+MLP hybrid is backed only second-hand through Tariq's ref. [81] (GPS jamming, lab data).
  4. Zhong's "per-class thresholds" collapse to a single global maximum.
  5. No assigned source backs the fused "lower of two standardized scores", the cluster bootstrap, or the multinomial-logistic temporal fusion.

### Cited Findings
- **Mahalanobis score, tied covariance.** The project uses Mahalanobis distance on the 64-d last hidden layer with a tied, shrunk covariance, citing Lee (DECISIONS lines 334, 500). Lee Eq. 1–2 back the score and the tied ML covariance. The 10% shrinkage is not in Lee, and the project already labels it as its own addition (DECISIONS line 409). — [Lee 2018](https://arxiv.org/abs/1807.03888); [DECISIONS.md](file:///C:/Users/Adi%20Suliman/uav-gcs-v6/docs/DECISIONS.md)
- **Algorithm 2.** The project's update Σ ← C/(C+1)Σ + 1/(C+1)Σ_new (DECISIONS line 509) matches Lee Algorithm 2 exactly. — [Lee 2018](https://arxiv.org/abs/1807.03888); [DECISIONS.md](file:///C:/Users/Adi%20Suliman/uav-gcs-v6/docs/DECISIONS.md)
- **Feature ensemble fitted against FGSM (DECISIONS lines 483, 496).**
  - Lee does validate on in-distribution vs FGSM samples (§3.1, Table 2 right) and expects ineffective layers to get near-zero weight (§2.2).
  - In the project the ensemble fell to AUROC 0.803 vs 0.863 for the last layer, with a −1.19 weight on the first layer. Lee's expectation did not transfer.
  - Dropping the ensemble is consistent with the evidence. — [Lee 2018](https://arxiv.org/abs/1807.03888); [DECISIONS.md](file:///C:/Users/Adi%20Suliman/uav-gcs-v6/docs/DECISIONS.md)
- **Threshold keeping 95% of known validation frames.** This matches Lee's TNR-at-TPR-95% operating point. Lee also claims tuning is possible with in-distribution samples (p. 2). Shebert sets an open-set threshold from a known-class accuracy target (85%, §IV.C), the same principle. — [Lee 2018](https://arxiv.org/abs/1807.03888); [Shebert 2023](https://arxiv.org/abs/2302.03749)
- **Isolation Forest.**
  - The project uses 100 trees, subsample min(8192, N), trained on known frames only (DECISIONS line 508).
  - Liu backs t = 100 (§4.1), and ψ = 8192 specifically for normal-only training (§5.4).
  - The ranking file still says ψ = 256 (its row "P07 … ψ=256, t=100"), which is out of date relative to the code; both values are inside Liu. — [Liu 2008](https://doi.org/10.1109/ICDM.2008.17); [DECISIONS.md](file:///C:/Users/Adi%20Suliman/uav-gcs-v6/docs/DECISIONS.md)
- **Fused score.** The fused score, the lower of two validation-standardized scores (DECISIONS lines 334, 508), is not from Liu or Lee. No assigned source backs this fusion rule. — [DECISIONS.md](file:///C:/Users/Adi%20Suliman/uav-gcs-v6/docs/DECISIONS.md)
- **Shebert as backing for "CNN with expert features (last_or_raw)" (ranking file, Shebert row).** This overreaches. Shebert's expert classifiers are protocol decoders (synchronization + CRC), run after the CNN's top-2 guess (§II.F, §IV.E). The paper does not fuse hand-crafted features into the network. What Shebert does back:
  - closed-set models absorb unknown signals into known classes (§I, Fig. 1);
  - softmax is unsuitable for open set (§II.E);
  - physics/protocol-based checks are more reliable than deep features for unknowns that resemble known classes (§IV.C, §IV.E). — [Shebert 2023](https://arxiv.org/abs/2302.03749)
- **"Three antennas null two interferers at once (Shebert et al.)" (DECISIONS line 618).** Partly supported.
  - Shebert says the eigenvalue model-order estimator can detect up to Mr − 1 co-frequency signals, and uses an MMSE beamformer to separate them (§II.B.3).
  - All experiments use a 4-element ULA. Three co-frequency emitters reached only 68% at 20 dB (§IV.B).
  - The array-theory statement (M antennas null M − 1 interferers) is better sourced to Winters (already in the library as V7_Winters_Salz_Gitlin1994, not reviewed here). — [Shebert 2023](https://arxiv.org/abs/2302.03749)
- **Hybrid detector "exactly our network" (ranking file, Tariq row).**
  - The CNN-spectrogram + MLP-features design is backed only via Tariq's summary of Abdullayeva & Valikhanli 2025 (GPS jamming, 5 classes, lab or simulated signals; p. 21, Table 8).
  - The review is a secondary source. The primary paper could not be downloaded (Elsevier returned 403; see §4). — [Tariq 2026](https://doi.org/10.1007/s44163-026-00960-7)
- **Other Tariq uses.** LOTO for zero-day claims (p. 24) and macro-F1 with class-imbalance handling (p. 15) are backed. — [Tariq 2026](https://doi.org/10.1007/s44163-026-00960-7)
- **Clopper–Pearson for KPI 6 (DECISIONS lines 377, 427).**
  - Thulin §2.1, Eq. 5 back the one-sided exact bound.
  - With 0 false alarms in 600 independent clean episodes, Eq. 5 gives p_U = 1 − 0.05^(1/600) = 0.498% (computed here).
  - Both Thulin (§1) and Brown (§4.2.1) assume i.i.d. binomial trials. The project itself found that 768 episodes from 24 channels overstated certainty (DECISIONS line 423) and moved to 600 independent geometries (line 427), which restores the assumption.
  - Brown would call Clopper–Pearson conservative but legitimate when strict coverage is required, as for a KPI claim. — [Thulin 2014](https://doi.org/10.1214/14-EJS909); [Brown 2001](https://doi.org/10.1214/ss/1009213286); [DECISIONS.md](file:///C:/Users/Adi%20Suliman/uav-gcs-v6/docs/DECISIONS.md)
- **Wilson intervals elsewhere (DECISIONS lines 260, 308).** Backed by Brown's recommendation (Wilson for small n, all three for large n). Thulin §5.2 warns that Wilson's minimum coverage can sit near 0.93 even at large n. — [Brown 2001](https://doi.org/10.1214/ss/1009213286); [Thulin 2014](https://doi.org/10.1214/14-EJS909)
- **Cluster bootstrap (`boot_cluster.m`, DECISIONS line 489).** Not covered by any assigned source. Thulin only notes that bootstrap methods control the level approximately, on average (§5.1). — [Thulin 2014](https://doi.org/10.1214/14-EJS909)
- **CUSUM (Xie 2022).** The ranking file lists Xie for a path-loss CUSUM alarm. DECISIONS lines 397 and 492 record that CUSUM was considered and dropped ("lack of a basis in the proposal literature"). Xie supplies the method basis (optimal delay at a fixed ARL) but no wireless application. So citing it is backed only if CUSUM is actually implemented. — [Xie 2022](https://arxiv.org/abs/2206.06777); [DECISIONS.md](file:///C:/Users/Adi%20Suliman/uav-gcs-v6/docs/DECISIONS.md)
- **Zhong (ranking file).**
  - Claimed "adaptive per-class thresholds": Algorithm 1 builds θc per class but classifies with the global θ = max_c θc (line 17), so per-class thresholds are not what is applied.
  - Claimed "reactive used as unknown on a real dataset": true for Combination 4, but no separate result for the reactive jammer is reported (Fig. 4b covers Combinations 1–3; Table 3 is an unspecified average). — [Zhong 2025](https://doi.org/10.1371/journal.pone.0325381)
- **Baselines the project reports without a cited source.** The project reports MSP and energy baselines (DECISIONS lines 334, 343–344). Their primary sources (Hendrycks & Gimpel 2017; Liu et al. 2020) were not in the library; both are now saved. — [Hendrycks 2017](https://arxiv.org/abs/1610.02136); [Liu 2020](https://arxiv.org/abs/2010.03759)

### Inferences
- **Hybrid-design citation.** The most defensible citation set for the hybrid design is: Tariq (review-level evidence that multimodal fusion helps) plus Abdullayeva & Valikhanli (primary, once obtained). Shebert backs only the open-set argument, not the architecture.
- **Wording for KPI 2.** The report should say that the unknown-threat score is the base Mahalanobis score of Lee et al. (Eq. 2, last hidden layer). It should not claim Lee's calibrated variant, since Lee's own Table 1 shows the gap.

### Gaps
- No source in this set backs the fused min-score rule, the cluster bootstrap, or the multinomial-logistic temporal fusion. Candidate statistics references for the cluster bootstrap (e.g., Field & Welsh 2007, JRSS-B; Davison & Hinkley 1997) are UNVERIFIED and were not downloaded; they are behind paywalls or are books.

---

## 3. Unused content that could raise antenna_fault and benign-WLAN detection and improve unknown-threat detection

### Takeaway
- **Sequential detection.** The strongest unused material is the sequential-detection theory in Xie 2022 and Xie 2021. CUSUM, WLCUSUM or EWMA on a per-cycle indicator (the same antenna dropping; quiet-slot interference present) accumulates weak, intermittent evidence optimally at a stated false-alarm rate (ARL).
- **Imbalance tools.** Threshold tuning and PR-AUC reporting under imbalance (Tariq, Hendrycks 2017).
- **Unknown-threat tools.** Energy and Outlier-Exposure training with realistic auxiliary outliers (Liu 2020, Hendrycks 2019), and physics or protocol checks for near-OOD threats (Shebert).
- **A labelling issue in the v6 code (not from any source).** This may cap antenna_fault per-frame F1.

### Cited Findings
- **CUSUM is optimal; Shewhart-style rules lose information.**
  - CUSUM minimizes the worst-case detection delay among all rules with ARL ≥ γ (Xie 2022, §III.B, Eq. 4). Delay ≈ log γ / I0, where I0 is the KL divergence between post- and pre-change per-sample distributions (Lemma 1).
  - Shewhart-type rules that look only at the current sample lose information, and CUSUM gains most when the change is small (Xie 2021, §II.C).
  - FAR = 1/ARL (Xie 2021, Eq. 6).
  - Sequential detection of channel occupancy and idleness is an established wireless use (Xie 2021, §V.D), the same structure as detecting low-occupancy WLAN. — [Xie 2022](https://arxiv.org/abs/2206.06777); [Xie 2021](https://arxiv.org/abs/2104.04186)
- **Unknown post-change parameter.** When the post-change parameter is unknown (e.g., fault duty, WLAN occupancy), WLCUSUM estimates it on a short sliding window. It stays first-order optimal with w = o(log γ), and the parallel version needs no choice of w (Xie 2022, §IV, §VI). EWMA needs no distributional knowledge at all (Xie 2021, §II.E-2). — [Xie 2022](https://arxiv.org/abs/2206.06777); [Xie 2021](https://arxiv.org/abs/2104.04186)
- **Assumptions to respect.** CUSUM theory assumes i.i.d. data before and after the change and a pre-change density known from history (Xie 2022, §III.A). Lai's generalized CUSUM covers non-i.i.d. data (Xie 2021, §III.A). — [Xie 2022](https://arxiv.org/abs/2206.06777); [Xie 2021](https://arxiv.org/abs/2104.04186)
- **Imbalance remedies (Tariq p. 15).** Resampling, cost-sensitive loss, threshold tuning, macro/weighted reporting; macro-F1 and PR-AUC favoured under skew. Hendrycks 2017 (§2) notes AUROC can mislead when base rates differ and recommends AUPR alongside it. Lee reports AUPR-in/out next to AUROC (Table 1). — [Tariq 2026](https://doi.org/10.1007/s44163-026-00960-7); [Hendrycks 2017](https://arxiv.org/abs/1610.02136); [Lee 2018](https://arxiv.org/abs/1807.03888)
- **WLAN expert detector and WLAN traffic modelling (Shebert).**
  - The WiFi expert classifier first finds packet starts with a sliding-window packet detector, then cross-correlates the L-STF/L-LTF preamble fields (§II.F.5).
  - The preamble and CRC need under 1 ms of signal; the authors used 10 ms windows to be sure of catching one (§II.H).
  - WiFi 6 traffic was simulated with randomized packet lengths and idle gaps (§III.A.2). — [Shebert 2023](https://arxiv.org/abs/2302.03749)
- **Deep open-set fails on look-alike unknowns (Shebert §IV.C).** OFDM/SC-FDMA unknowns were detected under 1% of the time. Protocol-level checks with analytic Pfa (Table II) gave near-100% unknown detection (§IV.E). — [Shebert 2023](https://arxiv.org/abs/2302.03749)
- **Energy-based detection.**
  - The energy score needs no retraining and takes its threshold from in-distribution data (§3.1). Energy fine-tuning with auxiliary outliers further lowers FPR95 (§3.3). — [Liu 2020](https://arxiv.org/abs/2010.03759)
  - The auxiliary outliers must be realistic and diverse; Gaussian-noise outliers do not generalize (Hendrycks 2019). — [Hendrycks 2019](https://arxiv.org/abs/1812.04606)
  - Zhong used exactly Gaussian and coloured noise as auxiliary OOD (p. 12), which conflicts with this. — [Zhong 2025](https://doi.org/10.1371/journal.pone.0325381)
- **Class-conditional Gaussian score under multimodal features (Zhong p. 14).** Zhong argues that Mahalanobis or Gaussian-assumption methods degrade when class features are not unimodal Gaussian. This is an explanation, not a tested claim; its own Mahalanobis baseline had F1 94.85 vs 99.35. — [Zhong 2025](https://doi.org/10.1371/journal.pone.0325381)
- **Algorithm 2 for new classes.** The new-class AUC gains are modest in absolute terms: 40.0% vs 32.7% (Lee §3.3). This is consistent with the project's 50.6–54.9% when learning reactive jamming as a new class (DECISIONS line 637). — [Lee 2018](https://arxiv.org/abs/1807.03888); [DECISIONS.md](file:///C:/Users/Adi%20Suliman/uav-gcs-v6/docs/DECISIONS.md)
- **v6 code: per-frame labels and the fault clock (read-only check).**
  - In `run_dataset_sweep.m` (lines 139–142), benign frames without a WLAN packet (act < 0.1) are relabelled clean. No equivalent relabelling exists for antenna_fault.
  - In `build_threat_model.m` (lines 231–245), the fault is open when mod(t·f_vib + φ, 1) < duty. Here f_vib and φ are drawn once per flight, and each frame's time t advances by one 20 ms decision cycle. — [run_dataset_sweep.m](file:///C:/Users/Adi%20Suliman/uav-gcs-v6/code/detection/run_dataset_sweep.m); [build_threat_model.m](file:///C:/Users/Adi%20Suliman/uav-gcs-v6/code/link/build_threat_model.m)

### Inferences
- **antenna_fault: label noise (inference from the code above, not from a source).**
  - A 0.5 ms frame overlaps an open interval with probability of about min(1, duty + 0.5 ms·f_vib).
  - The share of antenna_fault-labelled frames that are physically fault-free is therefore about 91% (duty 0.05 at 86 Hz), 55% (duty 0.3 at 300 Hz) or 6% (duty 0.6 at 672 Hz). All of them are still labelled antenna_fault.
  - Benign frames are handled differently: they are relabelled.
  - This label noise probably contributes to antenna_fault F1 0.82 and to none/antenna_fault confusion. It should be checked before any feature work.
- **antenna_fault: stroboscopic sampling (inference).**
  - Sampling a fixed f_vib once per 20 ms cycle aliases it to |f_vib − 50·round(f_vib/50)| ∈ [0, 25] Hz. Examples: 86 Hz → 14 Hz; 101 Hz → 1 Hz; 150 and 300 Hz → 0 Hz.
  - Near multiples of 50 Hz, the fault stays visible, or invisible, for long runs of consecutive cycles. A fusion window of N cycles can then miss it entirely, or see it as permanent shadowing.
  - Whether a single fixed vibration frequency per flight is physically realistic is a question for the vibration source; it is not assessed here.
  - Under this aliasing, per-cycle observations are not i.i.d., so plain CUSUM optimality does not strictly apply. WLCUSUM, EWMA or Lai's generalized CUSUM are the matching tools.
- **antenna_fault: CUSUM statistic (inference).** A natural statistic is the per-cycle log-likelihood ratio of "the same antenna is ≥ X dB below the others". The pre-change rate comes from fading on a clean link (independent across cycles after the v6 channel clock, correlation −0.25..0.10 per DECISIONS line 640). The post-change rate (≈ the duty-dependent visibility) is unknown, which is the WLCUSUM use case. This complements the existing persistence features (drop_w, same-weakest-antenna share) with an explicit ARL-calibrated threshold.
- **benign WLAN at low occupancy: CUSUM delay (inference).**
  - Treat "quiet-slot interference present in this cycle" as a Bernoulli stream: rate p0 on a clean link and p1 ≈ occupancy × P(detect) under WLAN.
  - Illustration with assumed p0 = 0.01 and ARL = 1000 cycles (20 s), using Xie's Lemma 1: p1 = 0.05 gives a delay of about 167 cycles (3.3 s); p1 = 0.10 about 48 cycles (1.0 s); p1 = 0.30 about 9 cycles (0.18 s).
  - Low-occupancy WLAN is detectable only over seconds at a controlled false-alarm rate. This is a physics-and-statistics limit, not a classifier deficiency.
- **benign WLAN: preamble correlation is likely out of reach (inference).** Shebert's preamble correlation needs the full 20 MHz WLAN band (125 MHz sampling there). The UAV link here runs at 1 Msym/s, so in-band it sees only a slice of the OFDM spectrum, which looks noise-like. Within the project's receiver, the distinguishing physics of WLAN is its on/off packet timing (0.27–3.2 ms packets, idle gaps), not its spectral shape. This supports time-envelope or gating features over spectral ones.
- **benign WLAN: the quiet slot (inference).** The quiet slot is only the last 32 symbols of each frame. A packet covering part of a frame but not the slot gives no q_iot evidence. Frames labelled benign with 10–40% packet coverage may therefore be undetectable from q_iot alone.
- **Unknown threats: auxiliary outliers (inference).** If Outlier Exposure or energy fine-tuning is considered, the auxiliary outliers must be realistic interference types that are not among the 10 threats and are never the held-out LOTO class. White or coloured noise, as in Zhong, would not satisfy Hendrycks 2019.
- **Unknown threats: windowed score (inference).** D72's "unknown-threat score over a window" (DECISIONS line 643) is a fixed-window statistic. Xie 2022 shows that recursive CUSUM-type accumulation can match or beat window-limited GLR at lower cost, especially for small changes.

### Gaps
- Not determined: whether the reported antenna_fault F1 0.82 is per-frame or on fused decisions, and the actual per-cycle drop and occupancy rates, so the illustrative CUSUM numbers rest on assumed p0 and p1.
- Sormayli et al. 2025, Sci. Rep. ("Real-time jamming detection using windowing and hybrid ML models for pre-saturation alerts", Tariq ref. 78, DOI 10.1038/s41598-025-10567-0) looks relevant to windowed detection but was not read: UNVERIFIED.
- Grunau et al. 2018 (multi-label interference identification, arXiv 1804.04395; cited by Keep It Simple) is relevant to combined threats but was not read: UNVERIFIED.

---

## 4. Missing key papers, downloads made, and the Brown 2001 copy

### Takeaway
- **The scratchpad Brown copy is the same scan.** `src\brown2001.pdf` is byte-identical to the library's `P12x_Brown2001_scanned_unreadable.pdf` (MD5 9437077222921157f26ac8292d195e2f). It is a JSTOR image scan whose text layer holds only the JSTOR cover, so copying it adds nothing.
- **A readable publisher copy is now in the library.** The 33-page text PDF from Project Euclid (101–133, with discussion) was saved, with five other open-access papers the project relies on or would cite.
- **Not freely downloadable.** Page 1954, Clopper & Pearson 1934 and the primary hybrid-detector paper.

### Cited Findings
- **Saved to the library folder `…\פרוייקט גמר\מקורות\` (names checked as new; nothing overwritten):**
  - `V7_Brown2001_Interval_Estimation_Binomial_Proportion_StatSci.pdf` (Project Euclid, text-searchable). — [Brown 2001](https://doi.org/10.1214/ss/1009213286)
  - `V7_Thulin2014_EJS_Cost_Exact_Binomial_Intervals_published.pdf`: the published EJS 8:817–840 version; the library's P12 file is arXiv v1 (2013). — [Thulin 2014](https://doi.org/10.1214/14-EJS909)
  - `V7_Hendrycks2017_MSP_Baseline_Misclassified_OOD_ICLR.pdf`: primary source for the MSP baseline the project reports. — [Hendrycks 2017](https://arxiv.org/abs/1610.02136)
  - `V7_Liu2020_Energy_Based_OOD_Detection_NeurIPS.pdf`: primary source for the energy baseline the project reports, and Zhong's ref. 4. — [Liu 2020](https://arxiv.org/abs/2010.03759)
  - `V7_Hendrycks2019_Outlier_Exposure_ICLR.pdf`: the "outlier exposure" candidate in DECISIONS line 236. — [Hendrycks 2019](https://arxiv.org/abs/1812.04606)
  - `V7_Xie2021_Sequential_Change_Detection_Survey_JSAIT.pdf`: a free, citable source for Page's CUSUM, Lorden/Moustakides optimality, FAR = 1/ARL and EWMA (Xie 2022's ref. [4]). — [Xie 2021](https://arxiv.org/abs/2104.04186)
- **Moustakides 1986 (Ann. Statist. 14(4):1379–1387, exact CUSUM optimality).** Free on Project Euclid but delivered as an image-only JSTOR scan with no text layer. It was not saved, since it could not be read here. Its result is stated in Xie 2022 (§III.B) and Xie 2021 (§II.D-1). — [Xie 2022](https://arxiv.org/abs/2206.06777)

### Inferences
- **Library hygiene.** The P12x scan can stay as the historical copy (deletion is the user's decision). The report should cite Brown from the V7 text copy and Thulin as EJS 2014 (pp. 817–840), not as the arXiv preprint.

### Gaps
- **COULD NOT DOWNLOAD:**
  - E. S. Page, "Continuous inspection schemes", Biometrika 41(1/2):100–115, 1954. DOI 10.1093/biomet/41.1-2.100; JSTOR https://www.jstor.org/stable/2333009. Paywalled (OUP/JSTOR). The free substitute is Xie 2021 (saved), which presents Page's CUSUM.
  - C. J. Clopper & E. S. Pearson, "The use of confidence or fiducial limits illustrated in the case of the binomial", Biometrika 26(4):404–413, 1934. DOI 10.1093/biomet/26.4.404; JSTOR https://www.jstor.org/stable/2331986. Paywalled. Thulin 2014 and Brown 2001 both define the interval.
  - A. Abdullayeva & O. Valikhanli, "Multimodal Deep Neural Network for UAV GPS jamming attack detection", Cyber Security and Applications 3:100094, 2025. DOI 10.1016/j.csa.2025.100094; URL https://www.sciencedirect.com/science/article/pii/S2772918425000116. ScienceDirect returned HTTP 403 to the automated download. It is the primary source behind Tariq's hybrid-detector claim; open-access status UNVERIFIED.
  - G. Lorden, "Procedures for reacting to a change in distribution", Ann. Math. Statist. 42(6):1897–1908, 1971. DOI 10.1214/aoms/1177693055. Not attempted; it is expected to be an image scan like Moustakides (UNVERIFIED). Optional.

---

## 5. Relevance verdicts and quality flags

### Takeaway
- **CORE:** Lee 2018 and Thulin 2014.
- **SUPPORTING:** Liu 2008, Brown 2001 (readable copy), Tariq 2026, Shebert 2023 and Xie 2022 (Xie only if a sequential detector is adopted), plus the new Hendrycks 2017, Liu 2020 and Xie 2021.
- **MARGINAL:** Zhong 2025, JamShield, Keep It Simple and Outlier Exposure.
- **NOT RELEVANT / not citable:** Yu 2020 (withdrawn), and the scan-only Brown copy, which the V7 copy supersedes.

### Cited Findings
- **P06 Lee 2018: CORE.** It is the KPI 2 method (Eq. 2), the tied covariance, Algorithm 2 and the TPR-95% operating point. Flag: far-OOD image evidence only; the project uses the base variant. — [Lee 2018](https://arxiv.org/abs/1807.03888)
- **P12 Thulin 2014: CORE.** Exact one-sided bound for KPI 6 (Eq. 5). Flag: the library file is arXiv v1, so cite the EJS version. — [Thulin 2014](https://doi.org/10.1214/14-EJS909)
- **P07 Liu 2008: SUPPORTING.** It backs the iForest score and settings, including ψ = 8192 for normal-only training. Flag: the project's iForest AUROC is weak (0.59–0.61, DECISIONS lines 343–344), so it is a secondary score. — [Liu 2008](https://doi.org/10.1109/ICDM.2008.17)
- **V7 Brown 2001: SUPPORTING.** It backs the Wilson/Jeffreys/Agresti–Coull choices and the conservativeness of Clopper–Pearson. The old P12x scan is unreadable. — [Brown 2001](https://doi.org/10.1214/ss/1009213286)
- **P03 Tariq 2026: SUPPORTING (framing).** It backs LOTO, macro-F1/PR-AUC under imbalance, the latency-reporting gap and shield + fallback. Flags: review only; the hybrid detector is backed second-hand; reference-number inconsistencies. — [Tariq 2026](https://doi.org/10.1007/s44163-026-00960-7)
- **N07 Shebert 2023: SUPPORTING.** It backs closed-set absorption of unknowns, softmax unsuitability, near-OOD failure of deep open-set models, MMSE spatial isolation and Mr − 1 signals. Flags: arXiv preprint only; the "hybrid" is a protocol-expert cascade. — [Shebert 2023](https://arxiv.org/abs/2302.03749)
- **W04 Xie 2022: SUPPORTING if a CUSUM or WLCUSUM detector is adopted, otherwise MARGINAL.** Flags: theory with synthetic data only; arXiv version in the library. — [Xie 2022](https://arxiv.org/abs/2206.06777)
- **S13 Zhong 2025: MARGINAL.** It offers an energy-based open-set comparison, with Mahalanobis as a weaker baseline on synthetic jamming, and the Kaggle dataset pointer.
  - Algorithm 1 applies the global max threshold despite computing per-class thresholds.
  - Its Gaussian/coloured-noise auxiliary OOD contradicts Hendrycks 2019.
  - No isolated reactive-jammer result.
  - The Table 3 caption says "four mainstream methods" for ten baselines; the ZSL-JPR baseline has no reference.
  - Text (p. 16) claims F1 variation below 0.01 at λ = 1.5, while Table 5 gives std 0.015 at λ = 1.5. — [Zhong 2025](https://doi.org/10.1371/journal.pone.0325381)
- **S06 JamShield 2025: MARGINAL.** A real 2.4 GHz 802.11 jamming dataset with constant/random/reactive jammers, but of cross-layer network metrics, not IQ, so it cannot test the spectrogram CNN directly. Flags: preprint; its 97.9% "detection rate" sits beside 90.3% recall without a definition that reconciles them. — [JamShield 2025](https://arxiv.org/abs/2507.11483)
- **S08 Keep It Simple 2023: MARGINAL.** Small CNNs suffice, which is relevant to latency (KPI 7) and model size. Flag: preprint; venue UNVERIFIED. — [Oyedare 2023](https://arxiv.org/abs/2303.03326)
- **S09 Yu 2020: NOT RELEVANT / not citable.** Withdrawn on arXiv (v2, 7 Apr 2020). — [Yu 2020](https://arxiv.org/abs/2002.00533)
- **New downloads.**
  - Hendrycks 2017: SUPPORTING (MSP baseline). — [Hendrycks 2017](https://arxiv.org/abs/1610.02136)
  - Liu 2020: SUPPORTING (energy baseline). — [Liu 2020](https://arxiv.org/abs/2010.03759)
  - Xie 2021: SUPPORTING (CUSUM, FAR = 1/ARL, EWMA). — [Xie 2021](https://arxiv.org/abs/2104.04186)
  - Hendrycks 2019: MARGINAL (candidate only). — [Hendrycks 2019](https://arxiv.org/abs/1812.04606)

### Inferences
- **Ranking file vs this review.** The ranking file's Lee 9 and Tariq 9 are consistent with this review. Its Shebert "CNN with expert features" item and its Zhong "per-class thresholds" item should be corrected. Its iForest ψ = 256 should read min(8192, N) per Liu §5.4.

### Gaps
- Venue and peer-review status of JamShield and Keep It Simple: UNVERIFIED.

---

## 6. Summary table

### Takeaway
One line per source: what it backs and what is wrong or missing.

### Cited Findings

| Source | Verdict | What it backs in the project | Issues found |
|---|---|---|---|
| P06 Lee 2018 (NeurIPS) — [link](https://arxiv.org/abs/1807.03888) | CORE | KPI 2 Mahalanobis score (Eq. 2), tied covariance (Eq. 1), Algorithm 2 new-class update, TPR-95% threshold, in-distribution-only tuning | Project uses the base variant: no input pre-processing or feature ensemble; Table 1 TNR95 54.51% vs 96.42% with both. Far-OOD image evidence only. 10% shrinkage is the project's own addition (already declared). |
| P07 Liu 2008 (ICDM) — [link](https://doi.org/10.1109/ICDM.2008.17) | SUPPORTING | iForest score; t = 100; ψ = 8192 for normal-only training (§5.4) | Ranking file still says ψ = 256. iForest AUROC weak in the project (0.59–0.61). Fused min-score rule not from Liu. |
| N07 Shebert 2023 (arXiv) — [link](https://arxiv.org/abs/2302.03749) | SUPPORTING | Closed-set absorption of unknowns; softmax unsuitable; known-accuracy-target threshold; near-OOD failure; MMSE spatial isolation; up to Mr − 1 signals | Preprint only. "Hybrid" is a CNN→protocol-expert cascade, not feature fusion. "3 antennas null 2 interferers" only partly backed (4-element ULA; 3 emitters 68%). |
| P03 Tariq 2026 (Discover AI) — [link](https://doi.org/10.1007/s44163-026-00960-7) | SUPPORTING | LOTO for zero-day (p. 24); macro-F1/PR-AUC under imbalance (p. 15); latency gap (p. 3); shield + fallback (p. 19) | Review; hybrid CNN+MLP backed only via ref. [81] (GPS jamming, lab data). Reference-number inconsistencies. |
| P12 Thulin 2014 (EJS) — [link](https://doi.org/10.1214/14-EJS909) | CORE | KPI 6 one-sided exact Clopper–Pearson bound (Eq. 5); cost of exactness | Library file is arXiv v1 (2013); EJS version now saved. Assumes i.i.d. trials. Cluster bootstrap not covered. |
| P12x / V7 Brown 2001 (Stat. Sci.) — [link](https://doi.org/10.1214/ss/1009213286) | SUPPORTING | Wilson/Jeffreys/Agresti–Coull recommendations; Clopper–Pearson conservative but valid for strict coverage | Old file and the scratchpad copy are the same unreadable scan (identical MD5). Readable V7 copy saved. |
| W04 Xie 2022 (arXiv; IEEE TIT 2023 per web search) — [link](https://arxiv.org/abs/2206.06777) | SUPPORTING if adopted, else MARGINAL | CUSUM optimality at fixed ARL; WLCUSUM for unknown post-change parameters (fault duty, WLAN occupancy) | No wireless data. CUSUM currently dropped in DECISIONS. i.i.d. assumption is strained by the fault-clock aliasing. |
| 06 Panitsas 2025 JamShield (arXiv) — [link](https://arxiv.org/abs/2507.11483) | MARGINAL | Real 2.4 GHz jamming dataset (constant/random/reactive); imbalance-aware metrics | Cross-layer metrics, not IQ. Preprint. "Detection rate" vs recall undefined. |
| 08 Oyedare 2023 Keep It Simple (arXiv) — [link](https://arxiv.org/abs/2303.03326) | MARGINAL | A compact CNN is enough (6.1k vs 276k params) | Preprint; venue UNVERIFIED. |
| 09 Yu 2020 (arXiv, withdrawn) — [link](https://arxiv.org/abs/2002.00533) | NOT RELEVANT / not citable | (PSD input; noise-like interference hardest) | Withdrawn v2 (7 Apr 2020). |
| 13 Zhong 2025 (PLoS ONE) — [link](https://doi.org/10.1371/journal.pone.0325381) | MARGINAL | Energy open-set comparison; Mahalanobis baseline weaker on synthetic jamming; Kaggle WLAN jamming data | Global θ = max θc, not per-class. Noise as auxiliary OOD contradicts OE. No isolated RJ result. Table 3 caption error. λ text vs Table 5 mismatch. Unreferenced baseline. |
| V7 Hendrycks 2017 (ICLR) — [link](https://arxiv.org/abs/1610.02136) | SUPPORTING (new) | Primary source of the MSP baseline the project reports; AUROC vs AUPR caveat | None for this use. |
| V7 Liu 2020 (NeurIPS) — [link](https://arxiv.org/abs/2010.03759) | SUPPORTING (new) | Primary source of the energy baseline; in-distribution threshold | None for this use. |
| V7 Hendrycks 2019 OE (ICLR) — [link](https://arxiv.org/abs/1812.04606) | MARGINAL (candidate) | Outlier Exposure; realistic outliers required, noise outliers fail | Only relevant if OE is adopted. |
| V7 Xie 2021 (JSAIT) — [link](https://arxiv.org/abs/2104.04186) | SUPPORTING (new) | Page CUSUM, Lorden/Moustakides optimality, FAR = 1/ARL, EWMA, non-i.i.d. CUSUM | Survey (secondary for Page 1954, which is paywalled). |

### Inferences
- **Four corrections before the report:**
  1. Phrase KPI 2 as Lee's base score.
  2. Cite Thulin as EJS and Brown from the V7 copy.
  3. Re-source the "3 antennas null 2 interferers" claim to Winters.
  4. Drop Shebert as backing for the feature-fusion architecture.
- **Antenna fault check, prior to any new method:** the per-frame label and fault-clock observations in §3.

### Gaps
- Primary hybrid-detector paper (Abdullayeva & Valikhanli 2025), Page 1954 and Clopper–Pearson 1934 not obtained (see §4).
