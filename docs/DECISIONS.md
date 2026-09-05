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