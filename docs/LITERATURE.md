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
| Tlili et al., Internet of Things 2024 (also approved [1]) | abstract only (paywall) | General AI-for-UAV-security survey. Not readable in full, so not cited. |

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
