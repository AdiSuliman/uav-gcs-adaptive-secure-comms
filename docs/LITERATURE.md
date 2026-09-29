# Literature check (2026-09-28, updated 2026-09-29)

Every source of the three proposal documents was read again before the v4 changes: the lecturer's
original proposal (seven recommended papers), the approved proposal form (six references) and the
updated proposal (twelve references). For each source: what it contributes to this project and which
design choice it supports. Short quotes are under 15 words.

## Sources of the updated proposal

| # | Source | Read | What we take from it |
|---|---|---|---|
| 1 | Oli & Mahalal, IEEE Access 2025 | full text | RF jamming rated high likelihood ("readily available equipment", SDR); jamming "can sever control links, causing crashes"; IDS latency classes of Table 8 (low < 10 ms); FHSS and dynamic frequency switching against jamming; AoA verification against spoofing; research agenda: cross-layer IDS (short term), "autonomous cyber-physical response mechanisms" (long term, 5+ years). |
| 2 | Papathanasiou et al., Appl. Sci. 2026 | full text | IDS "without the ability to prevent or mitigate them in real time"; "the loop between IDS and protocol control should be closed"; availability (RF interference) is the least studied category (27% of 37 studies) and only 2 studies go beyond detection (hopping, secondary paths, error-correcting codes); spectrogram + CNN for RF interference (Li et al. via [2]); isolation forest / one-class models for anomalies; digital twins recommended; "report robustness curves, not single-point scores"; scenario suites with concurrent attacks. |
| 3 | Tariq et al., Discover AI 2026 | full text | Multimodal jamming detector: MLP on telemetry + CNN on spectrogram images (99%) = our hybrid network; RL policies "outperform static rule-based strategies"; learned actions "constrained by rule checks and a safety shield and a deterministic fallback"; beamforming / interference nulling for link availability; zero-day claims need the class absent from training (leave-one-family-out); macro-F1 under class skew; real-time claims need measured wall-clock latency; post-attack recovery and multi-threat testing are gaps. |
| 4 | Liu et al., IEEE Commun. Lett. 2018 | full text | State = spectrum waterfall, i.e. the last M observations ("sufficiently use history spectrum information"); reward = bit rate when SINR exceeds the demodulation threshold, 0 otherwise, minus an action-change cost (0.2 R); action = a combination of frequency, power, coding and spread-spectrum decisions; jammers: sweep, comb, random, intelligent (jams the channel the user occupies most). Experience replay, epsilon-greedy. |
| 5 | Simon & Alouini, 2005 (book) | chapters used | BER of QPSK in AWGN and Rician fading, MRC with correlated branches (MGF method): link validation; conditional BER Q(sqrt(2 gamma)) maps an SNR estimate to a BER estimate. |
| 6 | Lee et al., NeurIPS 2018 | full text | Mahalanobis score with class means and tied covariance; feature ensemble over several layers (average-pooled features), weights by logistic regression on a validation set; when no OOD samples exist, validate with in-distribution vs FGSM adversarial samples ("tuned only using in-distribution" data). |
| 7 | Liu, Ting & Zhou, ICDM 2008 | known method | Isolation forest on the link features. |
| 8 | Mnih et al., Nature 2015 | known method | DQN, experience replay, target network, state stacked from the last 4 frames. |
| 9 | van Hasselt et al., AAAI 2016 | known method | Double DQN target. |
| 10 | Richards, 2014 (book) | chapters used | Ch. 6 binary (M-of-N) integration; Ch. 9 beamforming and STAP: optimum weights from the interference covariance, an N-element array nulls up to N-1 interferers, SINR loss when the interferer approaches the look direction. |
| 11 | Alshiekh et al., AAAI 2018 | known method | Shield that restricts the agent's actions. |
| 12 | Clopper & Pearson, 1934 | known method | Exact one-sided binomial bound for the false-alarm rate. |

## Lecturer's recommended papers not in the list

| Paper | Access | Relevance |
|---|---|---|
| AI Methods for UAV Cybersecurity: A Comprehensive Survey, Drones 10(6) 400, 2026 | full text | RL: "reward engineering ... is quite complex", unstable training, safety concerns; digital twins as a future direction; explainability of RL policies is weak. Consistent with [1]-[3]; adds nothing the project needs. |
| Secure RF and WiFi Communication in Drone Swarms via Testbed, arXiv 2606.27028, 2026 | full text | Real 915 MHz MAVLink testbed; packet delivery ratio counted on packets that pass checksum and signature verification at the receiver. This is how packet loss is measured in practice (CRC-checked frames). Candidate reference if a citation is wanted for the CRC-based packet loss. |
| Nanayakkara et al., Drones Auton. Veh. 2025 (also approved [4]) | full text | Attacker side (SDR jamming of a drone link); spectrogram CNN accuracy falls at low SNR, as in our KPI 1 curve. No design input. |
| Tlili et al., Internet of Things 2024 (also approved [1]) | full text (accepted manuscript, 27 pp.) | PRISMA survey of 128 studies, no numeric ranges. UAV-to-GCS is the primary link; jamming is the second most common attack (GPS, control-stream and data-stream jamming, omnidirectional jammer); countermeasures for jamming: frequency hopping, signal filtering, interference detection (Table 4) = our channel switch, MMSE nulling and detector; F1 for unbalanced data (our macro-F1); small datasets limit generalization; isolation forest among the listed methods; AI "requires meticulous simulation before real-world deployment" (Sec. 7.3); open issue: AI that adapts to evolving threats with few labeled samples (Sec. 8), which the unknown-threat flag and new-threat learning address. Supports the design; changes nothing. |

## Added for the interim report

| Paper | Access | Relevance |
|---|---|---|
| W. Xu, W. Trappe, Y. Zhang, T. Wood, "The feasibility of launching and detecting jamming attacks in wireless networks," MobiHoc 2005, pp. 46-57 | full text (12 pp.) | Four jammer models: constant (our barrage jamming), deceptive (valid-looking packets or preambles; our spoofing), random (alternates sleep and jamming; our noise burst), reactive (quiet until it senses a transmission; our reactive jamming, "may be harder to detect"). No single measurement detects every jammer; reactive and random jammers look like normal traffic in signal-strength statistics. Packet delivery ratio measured at the receiver by the CRC check; low PDR with high signal strength = jammed, low PDR with low signal strength = distant sender (Table 2), the basis of telling jamming from path loss. A jammer that barely affects PDR need not be detected or defended against (our benign-interference rule). Countermeasures cited: channel surfing (on-demand frequency hopping), spatial retreats, error-correcting codes. |

## Added after the v4 literature search (read in full, 2026-09-29)

| Paper | Access | What we take from it |
|---|---|---|
| J. Yang et al., "Agent-based anti-jamming techniques for UAV communications in adversarial environments: A comprehensive survey," arXiv:2508.11687, 2025 (preprint) | full text (17 pp.) | Defines the UAV anti-jamming agent as a closed Perception-Decision-Action loop with feedback (Fig. 3), which is our detector, DQN with shield, configuration and monitor. Interference taxonomy: adversarial (suppressive: broadband, narrowband, sweep, pseudo-random; deceptive: spoofing, replay, redirection), mutual (spectrum sharing) and environmental (terrain, weather). Six anti-jamming strategies: confrontation (raise power), avoidance (frequency hopping, spatial isolation by beamforming), elimination (receiver-side cancellation, MIMO), concealment, deceit, bypass (alternative path); our 36 configurations combine confrontation, avoidance and elimination with FEC, the relay experiment is a bypass. Open challenges: incomplete information and novel interference patterns, real-time decisions, safety guarantees of RL, generalization to unknown jamming, concurrent (hybrid) threats. |
| A. Grekhov, V. Kharchenko, V. Kondratiuk, "Deep Q-network based resilient drone communication: Neutralizing first-order Markov jammers," arXiv:2601.06095, 2026 (preprint) | full text (13 pp.) | Reactive (tracking) jammers detect transmissions and put power on the occupied channel; a first-order Markov jammer learns the hop transitions, P(i->k) = (count(i->k)+a) / sum_m (count(i->m)+a). A vanilla DQN (16-128-128-16, replay, target network, epsilon 0.9->0.05) with reward -2*I_jammed + 1/(1+BER) + 0.02*H(p) learns near-uniform hopping: 96-97% success at JSR 1.2 and 0.5 under Rayleigh fading; predictability, not jammer power, limits reliability. BER = Q(sqrt(2*gamma)); PLR = 1-(1-BER)^L ~ L*BER; BCH FEC with t = 1-2 cuts packet loss by orders of magnitude. Limits: jam indicator known to the reward, first-order jammer only, channel choice only, no detection stage. Supports the follower jammer, FEC against packet loss and a DQN on a UAV link; our system adds detection, receiver measurements, combined configurations and a shield. |
| L. Barajas, C. Jeardoe, J. Kim, E. Hammad, "Resilient control loops in autonomous vehicles under adversarial jamming via spectral perception and network-layer failover," IEEE WF-PST 2026 (arXiv:2609.05739) | full text (7 pp.) | Closed loop on hardware (HackRF sensing, USRP B210 CW jammer, ROS 2 robot): five spectral descriptors to a Random Forest, an event declared after 3 consecutive positive classifications (our m-of-n confirmation), recovery by switching to a pre-authenticated second interface. Recovery 6.0 s (static threshold), 2.55 s (ML detector, reassociation), 0.141 s (hardware failover); 78.9% less path-tracking error. Fixed thresholds give false alarms under environmental variability. Limitation they state: band switching is defeated by reactive or persistent jammers that follow the link (our follower and comb sets). Context: about 10,000 UAVs per month reported lost to EW in the Russia-Ukraine war (IEEE Spectrum). Prior anti-jamming work is "largely simulation-bound" (our limitation). |
| S. R. Shebert, B. H. Kirk, R. M. Buehrer, "Open set wireless signal classification: Augmenting deep learning with expert feature classifiers," arXiv:2302.03749, 2023 | full text (15 pp.) | Closed-set classifiers put unknown signals into a known decision region; open-set detection tightens the regions. Softmax assumes exhaustive classes and is unsuited to open set (our MSP 0.661). A CNN alone misses unknown classes that resemble known ones (generic OFDM/SC-FDMA detected <1%), as our last-layer score misses reactive jamming; a hybrid of CNN and expert-feature (CRC-verified) classifiers detects unknown classes at nearly 100% and adds explainability, the basis of our last-layer-or-link-feature score. CRC false alarm ~2^-n. Spatial isolation: ULA steering vector a(theta), MMSE weights w = R^-1 a(theta), up to Mr-1 co-frequency signals, 4-element array ~6 dB theoretical (3-5 dB in practice), 93% with two emitters. Channel augmentation: Rician/Rayleigh, Jakes Doppler 50-200 Hz, K 1-10 (close to ours); over-the-air test 98% vs 97.6% synthetic. Open problem: false-alarm rates of open-set DL are empirical (our 95%-retention threshold). |
| Y. Mekdad et al., "Exploring jamming and hijacking attacks for micro aerial drones," arXiv:2403.03858, 2024 | full text (6 pp.) | Real attacks on a 2.4 GHz drone command link (Crazyflie, 2481 MHz): constant Gaussian jamming with a HackRF One (about 410 USD) makes the GCS lose the link; the drone crashes in autonomous mode and holds the last command in manual mode; hijacking with 70 USD of radios (CW tone, then an unauthenticated link). y(t) = x(t) + j(t). Defenses: IDS on board or at the GCS, channel hopping, DSSS, MIMO, a safe mode; "no unified solution" against all jamming classes. Supports the threat model (cheap SDR jamming of the command uplink) and the need for several countermeasures. |
| ITU-R Recommendation P.838-3, "Specific attenuation model for rain for use in prediction methods," 2005 | full text (8 pp.) | Specific attenuation gamma_R = k R^alpha (dB/km) from the rain rate R (mm/h), k and alpha from curve fits over 1-1000 GHz (eqs. 2-3), combined for polarization and elevation (eqs. 4-5). Table 5 at 2.5 GHz: kH 0.0001321, alphaH 1.1209, kV 0.0001464, alphaV 1.0085, so 100 mm/h gives 0.023 dB/km (H), about 0.2 dB over 10 km. Weather is not a threat at our 2.4 GHz band; this answers why it is not modelled. |

Also downloaded and screened (abstract, introduction, conclusion) but not used: Yu et al. 2025 (avionics EW: ADS-B, TCAS), Lourenco and Grilo 2025 (null steering in swarms, covered by Richards), Panitsas et al. 2025 (JamShield), the 2023 CNN-complexity study, Yu et al. 2020 (withdrawn by the author), Nagib et al. 2022 (safe DRL for RAN slicing), Ceviz et al. 2023 (FANET routing), Zhong et al. 2025 (radar jamming open set), Zhang et al. 2025 (DRQN under limited CSI). Files in the project's `מקורות` folder, outside the repository.

## Approved-form references not in the updated list

| Paper | Access | Relevance |
|---|---|---|
| Yuan et al., IET Commun. 2021 | full text (open) | Double DQN against a mobile, smart (tracking) jammer; state from local observations and history (LSTM for relay, spectrum waterfall for channel); packet success rate and normalized throughput as metrics; anti-jamming toolbox: power control, frequency hopping, beamforming. Supports the follower jammer, Double DQN and history in the state; overlaps with [4]. |
| Yu et al., IEEE AESM 2024 | paywall | Not readable in full. |
| Alsadie, IET Inf. Secur. 2025 | full text | Broad survey; RL for self-adaptive security at high computational cost. No design input. |

## What the v4 changes rest on

| Change | Basis |
|---|---|
| Packet loss from a CRC check of every frame | [2] (protocol meta-signals for the IDS), swarm testbed (checksum-verified delivery), standard link practice |
| BER as the receiver's estimate (post-combining SNR estimate mapped through the QPSK formula) | [5]; proposal item 5 ("SINR estimated at the receiver") |
| Decision-directed SINR and envelope correlation (no transmitted waveform at the receiver) | [5]; proposal risk 8 keeps only the channel-estimation assumption |
| Spatial features of the two antennas (interference correlation, angle to the GCS channel, predicted MMSE gain) | [10] Ch. 9; [1] AoA verification; [3] interference nulling |
| History of the last cycles in the agent's state | [4], [8], Yuan et al. |
| Reward = link restored (<= 2x clean) minus costs | [4] reward (rate when SINR above threshold, minus action-change cost); proposal mitigation 2 |
| Combined configurations: one choice per domain (frequency, space, link budget) | [4] ("combination decisions of frequency, power, coding"); proposal item 7 |
| Multi-layer Mahalanobis, weights without OOD samples | [6] |
| Evaluation over severities, geometries and concurrent threats; robustness curves | [2]; proposal KPIs |
| Bootstrap over independent runs | proposal mitigation 5 |
| Unknown-threat score chosen among Mahalanobis candidates by leave-one-threat-out, nested estimate | [6]; [3] (zero-day claims need the class absent from training) |
| New threat learned as a class without retraining (mean and tied-covariance update) | [6], Algorithm 2 |
| Isolation forest: 100 trees, subsample min(8192, N), trained on known data only | [7] |
| Alarm confirmed on m of n cycles, m-of-n chosen on validation | [10] Ch. 6 |
| Shield: a new configuration only after a confirmed alarm | [11] (preemptive shield) |
| Per-antenna channel dip as a feature | [10] Ch. 9 (per-element channel estimates of the array) |
| Survivability map up to 28 dB JSR | [4] (30 dBm jammer against a 0 dBm signal) |

Ranges: the link's 2.4 GHz band, 50–120 km/h and Eb/N0 0–10 dB (about 15.7 to 5 km by the link budget, `link_budget_table.m`) are within those of the sources (Nanayakkara et al.: 2.4 GHz drone links and an SNR range of −10 to 20 dB in the literature; [4]: jamming up to 30 dB above the signal); the surveys [1]–[3] give no numeric ranges. No range needed widening.

Dropped for lack of a basis in these sources: CUSUM change detection, finer power and rate levels,
a recurrent (GRU) Q-network.
