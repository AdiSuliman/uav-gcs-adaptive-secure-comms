# Architecture Decision Record (ADR)
**Project:** UAV-GCS Adaptive Secure Communications
**Course:** 50076 (HIT) | **Students:** Adi Suliman, Bar Dvir Hassan | **Supervisor:** Golan Ein-Tzvi
**Purpose:** Living log of key design decisions — what we chose, what we considered, why, and the source.
Each decision feeds the interim report and final book. Update on every new decision, then `git push`.

---

## D1 — Model-based simulation (no hardware, no external dataset)
**Decision:** Pure MATLAB/Simulink simulation; the simulator self-generates the labeled dataset.
**Alternatives:** SDR hardware testbed; use of a public RF dataset.
**Rationale:** Scope and risk control — hardware and field data collection are out of a one-semester capstone's reach. Framing the project as proof-of-concept with theoretical validation (BER vs Eb/N0) is the accepted de-risking path; hardware validation is named as future work.
**Sources:** Proposal risk section (#4); standard practice in UAV jamming-detection work that generates data in MATLAB/Simulink.

## D2 — MATLAB + Simulink (not Python)
**Decision:** Stay all-in on MATLAB/Simulink for the full pipeline.
**Alternatives:** Python (TensorFlow/PyTorch) with a rebuilt or bridged RF layer. Supervisor explicitly allowed switching.
**Rationale:** RF/comms modeling is a core deliverable and Communications Toolbox has no Python equivalent; RL Toolbox provides DQN with replay/target-networks out of the box (de-risks the agent); the closed loop needs comms + AI in one runtime. Python would only win if the project were AI-heavy/comms-light — it is not.

## D3 — Platform scope: small UAV, single RF link, 2.4 GHz ISM, Rician LoS (short-range)
**Decision:** Small tactical UAV over a single short-range LoS link at 2.4 GHz ISM.
**Alternatives:** Large MALE UAV (Hermes/Heron class) with SATCOM/dedicated bands.
**Rationale:** 2.4 GHz ISM + short-range LoS is physically the domain of small/commercial UAVs; MALE platforms use SATCOM and dedicated military bands. The project's "wow" comes from implementation quality (real-time closed loop, dashboard, DQN vs rule-based, regime map), not platform size. Smaller scope = tighter focus, lower risk.

## D4 — UAV velocity 18–22 m/s (nominal 20) → Doppler 160 Hz
**Decision:** Operational envelope 18–22 m/s (65–79 km/h), nominal 20 m/s. Max Doppler fd = v·fc/c = 160 Hz (normalized 1.6e-4).
**Alternatives:** Hermes/Heron cruise (~30–36 m/s) — rejected as belonging to the MALE class, inconsistent with D3.
**Rationale:** 18–22 m/s sits in the DoD Group 1 SUAS envelope (Skylark/Raven class: ~32–81 km/h). The cited anti-jamming papers (Liu, Yuan) are platform-agnostic and specify no velocity, so the value is anchored to real small-ISR platform specs, not to a paper. At 1 Msym/s the normalized Doppler stays ~1.6e-4 → deep slow/quasi-static fading across the whole envelope, so the exact value is a documentation choice, not one that changes channel behavior.
**Sources:** Elbit Skylark I and RQ-11 Raven published specifications (Group 1 SUAS).
**Amended by D25 (2026-09-21):** the operating envelope is widened to a continuous 50–120 km/h (13.9–33.3 m/s; Doppler 111–267 Hz). 72 km/h / 160 Hz stays the nominal condition.

## D5 — Modulation QPSK, symbol rate 1 Msym/s, Rician K = 10 dB
**Decision:** QPSK, 1 Msym/s, Rician K-factor 10 dB (strong LoS).
**Rationale:** QPSK is the standard baseline for a control link (good spectral efficiency, robust). K = 10 dB reflects a dominant line-of-sight component typical of a short-range UAV-GCS link. 1 Msym/s gives a realistic control-link rate and places the channel firmly in slow-fading relative to the Doppler.

## D6 — Separate Rician and AWGN blocks (not a combined channel)
**Decision:** Model multipath fading (Rician) and receiver noise (AWGN) as two distinct blocks.
**Rationale:** Keeps clean, physically-meaningful injection points for threats: fading is a channel property, noise is a receiver property, and threats are external. Separation lets each threat attach at the correct point without entangling the channel model.

## D7 — No carrier synchronizer (kept out of scope)
**Decision:** Do not implement a carrier synchronizer; keep the Rician+Doppler baseline as-is (1.43× BER degradation vs theory).
**Alternatives:** comm.CarrierSynchronizer to recover the Doppler-induced phase rotation.
**Rationale:** The 160 Hz Doppler causes a measured 1.43× BER degradation — this is a useful, documented result that motivates adaptive recovery, not a defect to fix. The project's focus is AI-based detection + adaptive decision, not PHY-layer synchronization. A synchronizer added cost and QPSK phase-ambiguity issues with no benefit to the core deliverables.

## D8 — Threat injection: signal-level additive (Approach A)
**Decision:** Inject threats as real interference waveforms added to the complex IQ signal, at the point matching each threat's physical origin.
**Alternatives:** Approach B — metric-level injection (degrade SNR / add packet-loss on the features directly, no waveform).
**Rationale:** Signal-level injection preserves BOTH scalar metrics (BER, RSSI, SNR, PLR) AND spectral features (spectrogram/PSD). Approach B is simpler but forecloses the spectrogram path the detection layer may need. This matches mainstream UAV jamming-detection practice, including work that generates the dataset in MATLAB/Simulink and feeds spectrograms to a CNN.
**Sources:** 5G jamming detection via receiver-front-end waveform injection; UAV jamming detection with MATLAB/Simulink spectrogram dataset (legitimate/compromised/noise classes); manned-unmanned interference detection defining barrage/tone/pulse jamming for a CNN; RFI datasets built by combining signal-of-interest with jammers across SNRs.

## D9 — Six base threats; eavesdropping and MITM out of scope
**Decision:** Base threats — Jamming (barrage), Spoofing, Noise Burst, Antenna Fault, Path Loss, + Reactive Jamming. Skip eavesdropping and MITM.
**Rationale:** All six are observable in link metrics. Antenna Fault and Path Loss are non-hostile faults, kept deliberately so the system learns to separate hostile interference from physical failure. Reactive Jamming is added because it maps directly to the cited smart/mobile-jammer literature (Liu, Yuan) and justifies the DQN. Eavesdropping is passive (does not change BER/RSSI/SNR — invisible to link-metric detection); MITM needs protocol-layer modeling — both are out of the link-level scope. Multi-threat (combined attacks) is reserved as a later research-contribution extension, not a base capability.
**Sources:** Communication-layer UAV threat taxonomies (jamming, replay, eavesdropping, MITM); reactive/deceptive jamming definitions; spoofing detection via Rician-K and path-loss features (confirms our channel features already support spoofing detection).

## D10 — Threat build order: barrage jamming first
**Decision:** Implement and validate barrage jamming before any other threat.
**Rationale:** It is both the simplest to implement (additive wideband noise — the full Approach-A mechanism in its cleanest form) and the easiest to detect (raises the noise floor across the whole spectrum; BER jumps, SNR drops — the class furthest from "normal"). Validating the injection mechanism on the simplest threat means every later threat is a variation on a proven base.

---
*Last updated: 2026-09-05 — after A3 baseline complete, entering A4.*
## D11 — System Objects engine (replaced commfilt2 blocks)
**Decision:** Replaced Simulink `commfilt2` RRC blocks with System Objects
(`comm.RaisedCosineTransmitFilter`/`ReceiveFilter` + `pskmod`/`pskdemod`)
wrapped in MATLAB Function blocks (same pattern as Rician injection).
**Reason:** `commfilt2` blocks injected hidden algorithmic frame-buffer delay
(measured 30-bit delay vs 20-bit theoretical) and a decimation-timing ISI floor
that locked BER at ~0.17 regardless of SNR. Verified via Python + MATLAB System
Objects: identical RRC math gives BER exactly on `berawgn` theory (delay=20 bits).
**Architecture:** Split Digital Twin — [Tx: mod+RRC] -> [channels: Rician, AWGN
graphical] -> [Rx: RRC+demod]. Preserves visual Simulink twin for the report
while giving deterministic mathematical control under the hood.
**Validated:** AWGN sweep 0-10 dB, all points on theory curve (delay=20 stable).

---
*Last updated: 2026-09-19 — after spoofing root-cause fix, one-hot DQN state, sliding-window fix, and survivability mapping.*

## D12 — Spoofing detection: root-caused and fixed at threat-injection level
**Decision:** Rewrote spoofing injection in `build_threat_model.m` to generate a real bit stream, QPSK-modulate it, and RRC-shape it — identical processing to the legitimate Tx path (a dedicated persistent filter object, separate from the Tx's, preserves filter state across calls).
**Problem it replaces:** spoofing had been injected as i.i.d. per-sample random noise (`randn(size(u))>0` applied independently to every sample), not a coherent modulated carrier. This made it spectrally indistinguishable from jamming/reactive_jamming/benign_interference — all four were effectively variants of "additive noise at different power levels." This was the true cause of spoofing's historical recall instability (53-79.5% across different runs/seeds), previously misdiagnosed as a detector-architecture or feature-space limitation.
**Alternatives considered:** CNN-LSTM detector (see D13) — built and tested as a fix for the *symptom* before the root cause was found.
**Result:** spoofing recall 53-79% → 98.7% (run 1) / 99.7% (run 2, independent retrain, different seed). Overall CNN accuracy 91.81% → 98.05%.
**Consequence:** invalidates the premise of D13 (CNN-LSTM) as a spoofing fix — the gap it was built to close no longer exists.

## D13 — CNN-LSTM comparison architecture: built, evaluated, not pursued further
**Decision:** Production detector remains CNN+scalar hybrid. CNN-LSTM was implemented, trained, and evaluated as a candidate fix for spoofing's (then-)weak recall, per proposal risk #5's named mitigation ("compare multiple model architectures").
**What was tested:** dataset expanded to 27,246 frames (`frames_per_config` 50→100) specifically to support sequence-based training; sequence windowing (`build_sequence_index.m`, `extract_spectrograms_seq.m`) with data-leakage and per-class split-imbalance fixes applied across two runs.
**Result:** CNN-LSTM underperformed CNN+scalar on spoofing by -9.8pp and -21.8pp across the two configurations tested. Once D12 (above) fixed spoofing at its true root cause, CNN alone exceeded LSTM's best result by a wide margin with far fewer parameters, making the comparison moot for production use.
**Kept in repo, not deleted:** the LSTM scripts (`*_lstm.m`, `*_seq.m`) are the actual evidence that the risk-#5 mitigation ("compare architectures") was performed, not merely asserted. `main.m`'s Phase B-exp flags remain, all defaulted false, with an explicit "NOT PURSUED FURTHER" banner.

## D14 — DQN state encoding: ordinal → one-hot
**Decision:** Replace the scalar ordinal `threat_encode` (single integer 0-8 fed directly to the network) with a 9-dim one-hot vector, appended to 4 continuous link metrics for a 13-dim state. Implemented as a single shared function, `build_dqn_state.m`, called identically by `train_dqn.m` and both closed-loop scripts.
**Problem it replaces:** a neural network reading a scalar ordinal code interprets it as continuous, causing Q-value "bleed" between adjacent, semantically-unrelated threat codes. A prior patch (v4, 2026-09-14) worked around one specific instance (antenna_fault bleeding from the adjacent benign_interference penalty code) by manually reassigning code values — a symptom fix, not a structural one, and it would need re-verification every time a new threat class or code value was added.
**Rationale for the structural fix:** one-hot removes the adjacency-bleed failure mode by construction, for all classes simultaneously, rather than by careful manual placement of a small number of integers. An unrecognized threat name yields an all-zero one-hot (not an error) — a valid "unknown threat" state where the agent must rely on the continuous link metrics alone, which is also a direct mitigation for proposal risk #13 ("system should react to functional link changes, not just the threat's name").
**Validation:** post-training Gate A/B in `train_dqn.m` (see D9's reward-shaping mechanism) — refuses to save an agent that fails either check, using each threat's real measured baseline state (not synthetic).

## D15 — KPI #3 redefinition: recovery cycles → decision latency
**Decision:** Redefine the proposal's "DQN vs rule-based recovery time" KPI from a cycles-to-convergence metric to a decision-latency metric.
**Problem it replaces:** the original `measure_kpi3_recovery_time.m` simulated a halving-based "convergence" loop that never actually called `sim()` or consulted either policy's real action choice — it produced identical results for both policies regardless of which was nominally being measured.
**Root conceptual issue:** in this system, both the DQN and the rule-based policy are single-shot, deterministic dB reductions — there is no multi-cycle dynamic process to converge. A "recovery cycles" metric does not correspond to anything the system actually does.
**Rationale:** decision latency is the metric that both matches what the system actually computes (a one-shot decision, each policy takes some wall-clock time to produce it) and is directly relevant to real-time deployability. Measured via 1000 direct calls to `rule_based_policy.m` (lookup-table speed) vs. the real neural-network inference latency recorded in `closed_loop_diagnostic_report.txt`.
**Caveat for the report:** the resulting "DQN vs rule agreement" comparison (used elsewhere as a KPI) compares only the chosen action *name* between policies — `rule_based_policy.m`'s own per-threat magnitudes are computed but never applied to any BER calculation; both policies' physical mitigation effect goes through the same `action_mitigation_db`. State this precisely — it is a decision-policy comparison, not two independently-realized countermeasure systems.

## D16 — Closed-loop sliding-window feature fix
**Decision:** `run_closed_loop_diagnostic.m` now builds the 3 temporal features (var_rssi_10, dber_dt, burst_ratio) from a real sliding window over each Simulink run's ~20 returned frames, using the same logic as `extract_spectrograms.m` (training time), instead of feeding the CNN neutral placeholder values.
**Problem it replaces:** a single-shot closed-loop run has no history, so the placeholders (0,0,1) were used as a stand-in — but the CNN was trained on real temporal features, and reactive_jamming's entire distinguishing signature is a temporal pattern (a jammer that responds with delay), not a static spectrogram shape. Closed-loop detection accuracy under the placeholder scheme was 79.6% (vs. 98.05% on the offline test set), with two failure modes at 100% across all SNR points (reactive_jamming→jamming, none→path_loss).
**Alternatives tried and rejected:** a first fix attempt built the features from all 20 available frames but without NaN-guarding — `run_dataset_sweep.m` marks the last frame's BER as NaN in every run (a delay-bits truncation artifact), and the unguarded NaN silently propagated through the network, dropping accuracy further to 66.7% with two classes at 0%.
**Final implementation:** last-valid-frame selection (`find(~isnan(ber_f),1,'last')`), NaN guards mirroring `prepare_data.m` exactly (`feats(isnan(feats))=0`), and before/after BER both averaged over all valid frames rather than compared single-frame-to-single-frame.
**Result:** closed-loop detection accuracy 79.6% → **100% (54/54)**, all 9 classes × 6 SNR points. FAR returned to its expected near-zero value (from a spurious 64.5% under the broken pipeline).

## D17 — Survivability boundary: two-map methodology (Neutralization vs. Survivability)
**Decision:** `map_survivability_boundary.m` produces two separate boundary maps rather than one: Map A restricts to mechanisms that genuinely remove the threat (`atten_reduction`, `field_reduction`); Map B includes every available mechanism, including `awgn_margin_boost`.
**Problem it replaces:** the original single-map version took the best BER across all mechanisms without distinguishing between them. `awgn_margin_boost` raises effective SNR rather than weakening the attack, so it can make the link "recover" to better-than-clean-channel performance without the threat being neutralized at all — the single map silently let this dominate, producing physically-impossible "of ceiling" figures (up to 283.8%) for the threats where it won most often (sweeping_jammer, benign_interference).
**Rationale:** proposal deliverable #7 asks for the regime where "the attack is recoverable vs. non-recoverable" — that is a statement about the attack's own persistence, which Map A answers literally. Map B is retained as the system's overall achievable ceiling (useful context: what the link can do by any means), and the divergence between the two maps *is itself* the concrete instance of the proposal's goodput/margin tradeoff discussion.
**Result:** Map A 84.6% recoverable / Map B 87.9% recoverable (a 3.3pp gap, concentrated almost entirely in path_loss and the two threats margin-boost favored most). 1 explicit gap cell identified (path_loss, level=8, SNR=10dB) where the link survives via Map B but the threat is not neutralized per Map A.
**Known limitation, documented not fixed:** path_loss at its lowest tested severity (level=4) has zero legitimate Map A data points, because the global `field_reduction` magnitude sweep (5/10/15/20/25dB) starts above that severity level — every candidate would imply unphysical signal amplification and is correctly excluded by the existing legitimacy filter. This is a coverage gap in the exploration sweep's design, not a bug in the mapping logic.

## D18 — Rx_IQ tap point fixed: post-AWGN, not pre-AWGN (major, full re-run required)
**Decision:** `build_threat_model.m`'s `Rx_IQ` workspace probe is now wired from `AWGN/1` (post-noise), matching `build_link_model.m` (A1) and `build_rician_model.m` (A3).
**Problem it replaces:** `build_threat_model.m` (A4 — the only model actually used for the dataset, CNN training, DQN, EXP, and FAR) had `Rx_IQ` wired from `Threat/1` (pre-AWGN). A1 and A3 both correctly tap post-AWGN; only A4 diverged. Discovered during a full line-by-line code review (2026-09-19), not by any test failing — the pipeline ran and reported numbers throughout, but those numbers didn't mean what they appeared to.
**Consequence:** every spectrogram used to train the CNN, and every RSSI value in the system (CNN scalar branch, DQN state, reward table, closed-loop features, FAR), was computed from a signal that never included the swept AWGN noise. BER was unaffected (computed separately from tx/rx bit streams through the full chain, AWGN included). This explains why per-SNR CNN accuracy looked remarkably flat (97.6%-98.9%) — the visual/spectral input barely changed across the SNR sweep at all; only the ground-truth `snr` scalar feature and the correctly-computed BER/PLR varied.
**Rationale for fixing rather than only documenting:** a detector whose main input channel structurally cannot see the thing (noise) it is nominally being evaluated against is not demonstrating SNR robustness — it is demonstrating that SNR wasn't visually present. Reporting 98.05% "stable across SNR" without this caveat would misrepresent what was measured. Since two of the three model builders already established the correct convention, this is a one-line fix restoring consistency, not a new design choice.
**Consequence for the project:** requires a full re-run of the downstream pipeline (A5→A6→B1→B2→B3→C2→C3, and for full consistency EXP→survivability mapping, though those are BER-based and not structurally affected). Expect per-SNR CNN accuracy to show genuine SNR-dependent degradation post-fix, which is a *more* convincing result for the report than the previous artificially-flat curve, not a weaker one.

## D19 — rule_based_policy.m's per-threat mitigation_db: documented as unused, not removed
**Decision:** keep `rule_based_policy.m`'s per-threat `mitigation_db` return value, but document explicitly (in the function header and in README/PROJECT_LOG) that it is never applied to any BER calculation.
**Problem it clarifies:** both call sites (`run_closed_loop_diagnostic.m`, `measure_kpi3_recovery_time.m`) use only the returned action *name*; the physical mitigation effect for both the DQN and the rule-based policy is computed through the shared `action_mitigation_db` (25/15/25/25 dB per action). Discovered during the 2026-09-19 code review — not a functional bug (nothing crashes or produces wrong numbers), but a naming/expectation mismatch: the per-threat values (15/10/15/8/6/9/12 dB) look like they drive the comparison and don't.
**Rationale for documenting rather than implementing a fully independent rule-based physical system:** doing so would change what "DQN-vs-rule agreement" measures (from a pure decision-policy comparison to a comparison of two differently-tuned physical systems) — a scope decision, not a bug fix. Documented as D19 so the report states precisely what was compared.

## D20 — Shared closed-loop frame extraction; FAR measurement bug fixed
**Decision:** extract the "pull all frames from one sim() call, with per-frame BER/RSSI/PLR" logic into a single shared function `extract_closed_loop_frames.m`, used by both `run_closed_loop_diagnostic.m` and `diagnose_far_measurement.m`.
**Problem it replaces:** after the D18 re-run, `diagnose_far_measurement.m` reported none->path_loss confusion at ~72-78% FAR, while `run_closed_loop_diagnostic.m` reported none at 100% correct on the same trained model. Two distinct causes were found in the FAR script:
1. It still used the pre-D16 neutral placeholder `[0,0,1]` for the temporal features — the exact bug D16 fixed in the diagnostic, which had never been propagated to this second script (a duplicated frame-extraction copy is how that happened).
2. More seriously, it rebuilt the threat model each trial but never called `set_param([modelName '/AWGN'],'SNR',...)` — so every FAR trial ran at Simulink's default AWGN level, not the intended SNR. A clean channel at the wrong (very low) SNR looks spectrally like weak path_loss, which is exactly the confusion observed.
**Rationale for a shared function rather than a third fix in place:** the sliding-window logic had now been needed in three scripts (diagnostic, with_detector implicitly, FAR); fixing it a third time in a third copy is how the drift keeps happening. One shared source (like `build_dqn_state.m`) makes a fourth recurrence impossible.
**Fix details:** `diagnose_far_measurement.m` rewritten to (a) call `extract_closed_loop_frames.m`, (b) set the AWGN SNR per trial, and (c) sweep SNR = 0/4/10 dB at N=30 each for a proper FAR-vs-SNR characterization rather than a single worst-case point.
**Result:** FAR 0.0% across all 180 trials (95% CI upper bound 3.3% by Rule of Three); none CNN detection accuracy 98.9%, benign_interference 100%. The ~72% figure was entirely a measurement artifact, not a model weakness — confirming the CNN and DQN were correct all along.

## D21 — no_action recovery reported as N/A; GPU warm-up strengthened
**Decision:** in `run_closed_loop_diagnostic.m`, when the DQN chooses `no_action`, report recovery as N/A (NaN) rather than computing a BER ratio; and strengthen the GPU warm-up so latency measurements are steady from the first real run.
**Problem it replaces (recovery):** non-hostile classes (none, benign_interference) correctly receive `no_action`, but recovery% was still computed as `(BER_before - BER_after)/BER_before` on a channel that was never modified — i.e. two independent noise draws of the same clean channel. At high SNR (BER ~1e-3), dividing the tiny random difference produced large spurious values (none = -28.9% at 10 dB) that read as a failure but were pure division noise (the sign swung both ways across SNR, the tell of noise rather than a real effect).
**Rationale:** "no action was taken, so there is nothing to recover" is the physically correct statement; N/A communicates it directly and also makes the correct no-action behavior explicit in the report table, instead of hiding it behind a confusing signed percentage. Real threats never choose no_action, so their recovery numbers are unaffected. Manually verified none chose no_action at all 6 SNR points with BER_before ≈ BER_after each time (independent confirmation of the 0% FAR from D20).
**Problem it replaces (latency):** the noise_burst latency "spike" (~11-29 ms vs ~2 ms elsewhere) was not class-specific — it was the single largest value inside the whole first (SNR=0) measurement block, an artifact of cuDNN selecting convolution kernels lazily on the first real-sized input. The single dummy warm-up pass didn't force that autotuning to finish.
**Fix (latency):** warm-up strengthened to 10 iterations with `rand` inputs (not `zeros`, which can take a fast path) plus `wait(gpuDevice)` to block until the kernels finish, before any timing starts. All latencies are now steady (~2.5-3 ms) from the first measured run; noise_burst dropped from ~11 ms to ~3 ms, and the KPI#3 mean latency is a clean 2.67 ms.

## D22 — Decision-latency measurement scope widened to include preprocessing
**Decision:** in `run_closed_loop_diagnostic.m`, "CNN latency" now times the full per-decision processing chain — spectrogram (STFT), dB conversion, normalization, image resize, tensor prep — plus the network forward pass, instead of timing only `predict()` in isolation.
**Problem it replaces:** the original `tic` was placed immediately before `predict()`, after all signal preprocessing had already run unmeasured. The comment above that block had always said "TIMED" for the whole block, but the `tic` itself didn't match the comment's intent — the reported number was inference-only, not the true reaction time a deployed system would need end-to-end.
**Rationale:** a latency figure used to argue real-time viability has to cover everything the system actually does per decision, not just the neural-network portion. DQN latency remains inference-only by design — its input (the state vector) is already numeric with no comparable preprocessing cost.
**Result:** latency figures are now higher but honest (measured mean 18.88ms / median 8.42ms in the first run after this fix) — see D23 for why that first measurement also had a large mean-median gap, and its resolution.

## D23 — spectrogram() warm-up added; mean/median latency converged
**Decision:** extend the existing CNN/DQN GPU warm-up in `run_closed_loop_diagnostic.m` and `demo_gui.m` to also call `spectrogram()` on dummy IQ data (2064 samples, matching one real frame) several times before timing starts.
**Problem it replaces:** immediately after D22 widened the measurement scope, the first full run showed mean latency (18.88ms) far above the median (8.42ms) — traced to a one-time JIT/internal-cache cost paid by MATLAB's `spectrogram()` on its first call in a session, landing on whichever threat happened to run first and skewing the mean for the whole batch. This was a measurement artifact, not a system characteristic, and the fix belongs in the warm-up procedure (matching how CNN/DQN warm-up was already handled), not as an explanation footnoted in the report.
**Result:** re-run after the fix: mean 6.09ms / median 5.67ms — a 0.42ms gap (was 10.46ms), confirming the skew was fully eliminated. This is also the number now used everywhere it's cited (KPI #3, abstract, literature comparison).

## D24 — demo_gui.m: interactive operator-console demonstration
**Decision:** build `demo_gui.m`, a self-contained MATLAB `uifigure` app for live, in-person demonstration of the full closed-loop pipeline — multi-select threat list (runs each selection in sequence), SNR control, live spectrogram and IQ-constellation (before/after mitigation), a GCS↔UAV link-status indicator that changes color with system state, CNN-confidence/latency gauges, a persistent run-history table exportable to CSV/.mat, and optional full-session video recording via `VideoWriter`. Every run calls the real pipeline (`build_threat_model.m`, `sim()`, `extract_closed_loop_frames.m`, the trained CNN and DQN, and — for any non-`no_action` decision — a second real simulation to measure actual post-mitigation BER) — nothing is mocked or precomputed.
**Architecture constraint discovered and resolved:** MATLAB nested functions (a function defined inside another) force the containing function's workspace to become "static," which then rejects script-style variable injection — this breaks any call to `init_params.m` or `build_threat_model.m` (both scripts, used as such everywhere else in the codebase) if they're invoked from a function that contains a nested function anywhere in the same file. `demo_gui.m` is therefore written with **no nested functions at all**: `demo_gui` builds the UI and stores every shared object (loaded models, parameters, UI component handles, run history, the video writer) in `fig.UserData`; every callback (`runSequence`, `runOneThreat`, `exportHistory`, etc.) is a plain top-level sibling function that retrieves what it needs via `ancestor(source,'figure').UserData`. This pattern should be reused for any future MATLAB GUI work in this codebase to avoid re-discovering the same restriction.
**Status:** built and iterated through two correctness passes (the static-workspace fix above, then two MATLAB API corrections — `uipanel` has no `FontColor` property, title-text color is `ForegroundColor`; and `'\u25CF'`-style escapes are not interpreted in MATLAB single-quoted strings, `char(9679)` must be used instead). Live-tested by Adi as of this session's end; further UI feedback pending.
**Superseded in part by D26 (2026-09-22):** the no-nested-functions architecture and `fig.UserData` pattern remain the standard; the feature set described above was replaced by the four-tab v3 console.

## D25 — UAV speed envelope 50–120 km/h (continuous) and speed-diverse training data
**Decision:** widen the UAV operating envelope from 18–22 m/s (D4) to a continuous 50–120 km/h (13.9–33.3 m/s), with Doppler fd = v·fc/c = 111–267 Hz at 2.4 GHz (≈ 2.22 Hz per km/h). Nominal stays 72 km/h (20 m/s, 160 Hz), so every script that does not sweep speed behaves as before. The detector is trained and evaluated on speed-diverse data, and a dedicated closed-loop sweep measures robustness across the envelope.
**Alternatives:** (a) keep the narrow D4 envelope — rejected: speed generalization would stay untested and the GUI speed control would remain cosmetic; (b) an integer km/h grid — rejected: the requirement is a continuous, non-integer speed; (c) feed speed to the network — rejected: a deployed receiver does not know the true speed, so robustness must come from the data (speed is stored per frame for analysis only); (d) also randomize the UAV–GCS distance — not required by the proposal, and path attenuation is already covered by the path_loss severity axis.
**Implementation:**
- `init_params.m` — `speed_kmh_min/max` (50/120), derived `v_min/v_max`, nominal unchanged.
- `run_dataset_sweep.m` — every 100-frame (threat, level, Eb/N0) block is simulated at its own random continuous speed, assigned by a Latin square over 6 speed bins so speed is correlated with neither SNR nor class; `none` is split into 5 sub-blocks per SNR so it also spans the speeds; per-frame `speed_kmh`; `rng(2026)`. The Doppler is baked into the Simulink model at build time, so this needs 270 builds (~102 min) instead of one per (threat, level).
- `extract_spectrograms.m` — a speed change starts a new run (prevents temporal-feature leakage across speeds); `prepare_data.m` carries `speed` in each split (analysis-only); `eval_detector.m` reports accuracy in 7 speed bins.
- `eval_speed_robustness.m` (new) — 8 speeds × 3 Eb/N0 × 9 threats through the real chain (Simulink → CNN → DQN → real mitigation re-simulation); ~13 min.
**Rationale:** the earlier system was trained and evaluated at a single Doppler (160 Hz); a reviewer can fairly ask whether it holds across realistic speeds. This makes the answer measurable. Consistent with D4, fading is deeply quasi-static across the whole envelope (normalized Doppler ≤ 2.7e-4 at 1 Msym/s), so mild speed sensitivity is expected; the sweep confirms it instead of assuming it. The upper end (33 m/s) now touches the 30–36 m/s cruise range that D4 had cited for larger platforms; the envelope is defined by speed rather than platform class, and the small-UAS link scope of D3 is unchanged.
**Result (2026-09-21 full re-run):** offline accuracy 96.41% (96.73% before), macro-F1 96.39%; per-speed offline accuracy 92.7–98.2% (weakest bin 50–60 km/h); closed-loop detection over 8 speeds 98.1% (212/216) with 0/48 false alarms and mean recovery 72.4% (flat at 69–74%); all four misses are antenna_fault. Side effect: reactive_jamming recall fell from 91.0% to 87.1% (untested hypothesis: extra Doppler variation blurs the temporal features that separate it from jamming).
**Scope limits:** the DQN state has no Doppler input and its reward table, EXP and SURV run at the nominal condition; the DQN was retrained in the full run but its training is speed-independent. Only detection and closed-loop behavior are speed-swept.

## D26 — demo_gui.m v3: proposal-complete operator console
**Decision:** rebuild `demo_gui.m` (D24 architecture kept) as a four-tab console covering every proposal deliverable: LIVE OPERATIONS (threat × Eb/N0 matrix, UAV speed 50–120 km/h, severity levels, UNKNOWN threshold, DQN vs rule-based, BER/RSSI timeline, verdict), KPI & RESULTS, SURVIVABILITY MAP (Map A/B), SESSION LOG.
**Problems it replaces:** (1) decision latency was timed with drawing and pauses inside `tic/toc`, so it did not match the diagnostic's number; (2) the speed field was set but never used, since the Doppler was computed once at load; (3) no DQN-vs-rule comparison, survivability map, BER/RSSI timeline, UNKNOWN-threat handling or KPI view; (4) generic diagrams that showed the same picture for different attacks.
**Design choices:**
- Latency = CNN path (spectrogram, normalization, resize, forward pass) + DQN forward pass, timed with nothing else inside the block (extends D22/D23 to the GUI).
- Speed is applied to `p.v_kmh/p.v/p.fd_max` before `build_threat_model`, so the channel sees the real Doppler.
- Recovery = mean BER over all valid frames before vs after, the same definition as the KPI. The rule-based choice gets its own real second simulation when it differs from the DQN's, so the comparison is between measured outcomes.
- UNKNOWN threat: if CNN confidence is below the slider threshold the class becomes `unknown`, the DQN state is the all-zero one-hot (link metrics only), and the rule defaults to `no_action` (proposal risk 13). The antenna_fault @ 0 dB case (31% confidence, misclassified) is the natural demonstration.
- Verdicts use the survivability-map thresholds (recoverable ≤ 2× clean BER, marginal ≤ 5×), so the live result and Map A/B share one criterion.
- `params.mat` is restored after every run via `onCleanup`; changing state (history, video writer, log file, abort flag, last run) lives in appdata, static state in `fig.UserData`; no nested functions (D24).
- Startup: `splits.mat` (>1 GB) is no longer loaded for two normalization vectors — they are cached in `data/gui_norm_stats.mat`, regenerated when `splits.mat` is newer. The GUI should be launched from a fresh MATLAB session after a full `main.m` run.
**Verification limits (stated honestly):** all changed files were syntax-parsed and the pure helper functions unit-tested outside MATLAB; the dataset sweep and speed-robustness scripts were also executed against stubbed Simulink/toolbox functions. The GUI itself was not executed by the author in MATLAB, so first-run layout or API fixes are expected; a slow-startup report on 2026-09-22 led to the cache above.
