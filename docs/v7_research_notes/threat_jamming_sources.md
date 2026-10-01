# Threat, jamming, spoofing and interference sources: range check, detection features and published defences

Research notes only (literature-review level, no design decisions, no attack construction). Re-review written 2026-10-01; replaces the incomplete earlier version of this file.

Conventions
- **L** = library folder `C:\Users\Adi Suliman\Desktop\תואר ראשון  הנדסת חשמל ואלקטרוניקה\שנה ד\פרוייקט גמר\מקורות`. A link written `<L/file.pdf>` points to that file.
- `<_extracts_threat/...>` links are relative to this notes folder (text extractions and the downloaded PDFs in `_extracts_threat/dl/`).
- All text was read from the extractions named in the assignment (`_extracts_threat/`, `_extracts_threat/dl/`, `scratchpad/src/W07b, W08, W09, W11, S_04`, and `tool-results/shahriar.txt, noubir.txt, hok.txt`). Nothing new was searched or downloaded.
- Page numbers are the printed page numbers in the PDF where the extraction keeps them. "Sec." is used where the extraction has no page markers.
- Quotes are verbatim from the extraction. Where the extraction lost a Greek letter, a minus sign or a "≥", the lost character is shown in [brackets] and flagged.
- **UNVERIFIED** = not read in the source itself during this review (memory, file name, or second-hand through another paper).
- Project claims are quoted from `C:\Users\Adi Suliman\uav-gcs-v6\docs\DECISIONS.md` (D70 line 517-518, D71 lines 582-586, D72 lines 641-647) and the ranking file `<L/דירוג מקורות וחולשות הפרויקט.md>` (read-only background).

Project claims being checked (DECISIONS.md, quoted):
- D72 line 645: "in-band interferers 30 dB (Liu et al.)" and "spoofer 30 dB, the jammer's hardware (a 0.2-3 dB advantage captures the receiver, Whitehouse et al.; the hijacker uses the jammer's radio, Mekdad et al.)".
- D72 line 647: "packets of 0.27-3.2 ms (Wollenberg et al.), channel occupancy drawn per flight in 5-86% (Cheema & Salous; Wollenberg et al.), exponential idle gaps, on the channel clock; power up to 30 dB over our signal (EIRP 20 dBm, ETSI EN 300 328, against the link budget; interference grows with altitude, Song et al.)".
- D70 line 517: "comb (every usable channel jammed at once)" attributed to Liu et al.'s jammer list.
- D71 lines 585-586: CW jammer "named in four sources (Mekdad et al. ...; Barajas et al. jam with a CW tone and list barrage, single-tone, pulse and protocol-aware jammers ...)"; "Barajas et al. measure recovery by link switching in 0.14-2.6 s".
- D72 line 641: "Jammer detection on unused/empty pilots (Pirayesh & Zeng, 2022 survey); a reactive jammer transmits only while it senses our signal (Xu et al.; Sagduyu et al.)".

---

## 1. Range verification: do Liu 2018, Whitehouse 2005, Mekdad 2024, Wollenberg 2012 and Cheema 2019 support the project's threat levels?

### Takeaway
Only part of the project's caps are backed by the text. Liu supports **one simulated point**: 30 dB jammer-over-signal power at equal 4 MHz bandwidths. It is a simulation parameter, not a measurement. Whitehouse gives capture thresholds of **0.17 dB and 1-3 dB** (both second-hand). These are *minimum* advantages and say nothing about a 30 dB spoofer. Mekdad gives **no power ratio at all**. Its hijacker used **two Crazyradio PA modules, the same model as the legitimate GCS radio, not the HackRF jammer**, so the D72 wording "the hijacker uses the jammer's radio" is not backed. The WLAN numbers come from **Wollenberg's generated lab test cases**: 3.2 ms and 268 µs frames, and 5.0 % and 85.6 % occupancy. Cheema's field measurement gives only **4.6-11.5 % duty cycle**, so the 86 % upper bound is a cabled lab load, not a field value. Cheema found the **exponential idle-time model the worst fit**, which contradicts "exponential idle gaps". Neither WLAN source gives any level relative to a desired signal; the 30 dB WLAN cap comes from other documents (ETSI, link budget, Song), which this review did not read.

### Cited Findings

#### 1a. In-band interference up to 30 dB JSR (Liu et al.)
- Citation in the file: X. Liu, Y. Xu, L. Jia, Q. Wu, A. Anpalagan, "Anti-jamming Communications Using Spectrum Waterfall: A Deep Reinforcement Learning Approach", arXiv:1710.04830v1, 13 Oct 2017, 4 pp. The journal version, IEEE Commun. Lett. 22(5), 2018, is **UNVERIFIED** (not printed in the file). — [Liu arXiv](https://arxiv.org/abs/1710.04830)
- It is simulation only. Sec. IV, p. 3: "the user and the jammer combat with each other in a frequency band of 20MHz, where the frequency resolution of spectrum sensing is 100kHz." — [Liu, Sec. IV p. 3](https://arxiv.org/abs/1710.04830)
- The number the project uses (Sec. IV, p. 3): "Both signal and jamming are raised cosine waveform with roll-off factor [α] = 0.3, in which jamming power is 30dBm and signal power is 0dBm." Greek letters were lost in the extraction. — [Liu, Sec. IV p. 3](https://arxiv.org/abs/1710.04830)
- Same paragraph: "The demodulation threshold [β]th at all frequency is set to be 10dB". There is no path loss, geometry, or "transmit"/"received" qualifier on either power. — [Liu, Sec. IV p. 3](https://arxiv.org/abs/1710.04830)
- Bandwidths are equal: "The bandwidth of user signal is 4MHz, and the center frequency is allowed to change in each 10ms with the step of 2MHz, which means K = 9" and "For all Jamming patterns, the instantaneous bandwidth of the jamming is set to be 4MHz." So 30 dB is also the in-band power ratio, if both powers are read as received powers. — [Liu, Sec. IV p. 3-4](https://arxiv.org/abs/1710.04830)
- Jammer set (p. 3-4): "Sweep jamming (sweep speed is 1GHz/s)", "Comb jamming (three fixed frequency signals at 2MHz, 10MHz, and 18MHz)", "Random jamming (frequency is randomly changed every 20ms with the step of 4MHz)", and "Intelligent jamming (the jammer continuously observes the probability that the user signal appears at each frequency point, and chooses the largest one as jamming channel)". — [Liu, Sec. IV](https://arxiv.org/abs/1710.04830)
- Result for comb jamming (p. 4): "Especially in the case of comb jamming, the normalized throughput is close to one after convergence, which indicates that the jamming is almost completely avoided." — [Liu, Sec. IV p. 4](https://arxiv.org/abs/1710.04830)
- The project's use (D70 line 518): "in-band threat levels up to 28 dB JSR (Liu et al. evaluate a 30 dBm jammer against a 0 dBm signal)". This wording is accurate. D72 line 645 caps detector levels at "30 dB (Liu et al.)", which matches Liu's single value. — [DECISIONS.md](<C:/Users/Adi Suliman/uav-gcs-v6/docs/DECISIONS.md>)
- **Overreach flag, comb jammer.** D70 line 517 describes Liu's comb as "every usable channel jammed at once". Liu's comb is three 4 MHz tones at 2, 10 and 18 MHz in a 20 MHz band. Liu reports that the user escapes it almost completely ("normalized throughput is close to one"). So Liu's comb leaves clean channels. — [Liu, Sec. IV p. 3-4](https://arxiv.org/abs/1710.04830); [DECISIONS.md line 517](<C:/Users/Adi Suliman/uav-gcs-v6/docs/DECISIONS.md>)

#### 1b. Counterfeit-command interference (spoofing) up to 30 dB SIR (Whitehouse et al.; Mekdad et al.)
- Whitehouse citation in the file: K. Whitehouse, A. Woo, F. Jiang, J. Polastre, D. Culler (UC Berkeley), "Exploiting The Capture Effect For Collision Detection And Recovery". The venue (EmNetS-II 2005, per the file name `V7_Whitehouse2005_Capture_Effect_Collision_Detection_EmNetS.pdf`) and the pages are **UNVERIFIED**: the extraction prints neither. — [Whitehouse PDF](<_extracts_threat/dl/whitehouse.pdf>)
- The capture-threshold sentence (Sec. 2, ~p. 2): "Depending on the type of modulation and decoding scheme, the signal strength difference required for capture to occur is estimated to be as large as 1-3dB [2] or as little as 0.17dB [26]." — [Whitehouse Sec. 2](<_extracts_threat/dl/whitehouse.pdf>)
- Both numbers are second-hand. Ref [2] is "ALOHA Packet Systems with and without Slots and Capture. ACM SIGCOMM, Computer Communication Review, 1975". Ref [26] is "P. S. Sang. On capture effect of FM demodulators. M.S. Thesis Naval Postgraduate School, Monterey, CA., March 1989". Neither was read. — [Whitehouse references](<_extracts_threat/dl/whitehouse.pdf>)
- The paper says the threshold depends on the radio: "Some radios can only tolerate interference that is much smaller than the amplitude of the captured signal while others can differentiate between signals of almost exactly the same amplitude." — [Whitehouse Sec. 2](<_extracts_threat/dl/whitehouse.pdf>)
- Own platform (Sec. 4): "433MHz Chipcon CC1000 [1] radio transceiver"; "Manchester encoding is used at the physical layer, and delivers 19.2kbps encoded bandwidth". — [Whitehouse Sec. 4](<_extracts_threat/dl/whitehouse.pdf>)
- Own measurement of the threshold (Sec. 4): "the power difference required to cause one transmitter to be received over the other one was unobservable using the 10bit ADC to sample the RSSI pin on the radio." — [Whitehouse Sec. 4](<_extracts_threat/dl/whitehouse.pdf>)
- Arrival order matters (Sec. 3): "In stronger-last collisions, however, the radio synchronizes with the weaker packet but reception fails because stronger packet later captures the channel and corrupts the tail end of the first packet. Thus, stronger-last collisions result in the loss of both packets even in the presence of capture." Their technique adds re-synchronisation on a second preamble. — [Whitehouse Sec. 3](<_extracts_threat/dl/whitehouse.pdf>)
- Indoor flood test (Sec. 5): "857 transmission, 12687 receptions, 2036 collisions and 1142 instances of capture and recovery". Also: "The closer node is stronger only 57% of the time while it is weaker 43% of the time." — [Whitehouse Sec. 5](<_extracts_threat/dl/whitehouse.pdf>)
- Mekdad citation in the file: Y. Mekdad, A. Acar, A. Aris, A. El Fergougui, M. Conti, R. Lazzeretti, S. Uluagac, "Exploring Jamming and Hijacking Attacks for Micro Aerial Drones", arXiv:2403.03858v1, 6 Mar 2024. The peer-reviewed venue is **UNVERIFIED**. — [Mekdad arXiv](https://arxiv.org/abs/2403.03858)
- Setup (Sec. IV-A): Crazyflie 2.1 and Crazyradio PA, "channel 81 with a 2 Mbits/s radio bandwidth" (2481 MHz). Threat model (Sec. III): "1 km range line-of-sight with the Crazyflie drone". — [Mekdad Sec. III-IV](https://arxiv.org/abs/2403.03858)
- Jamming attack: "we broadcast high-power interference signals (i.e., Gaussian noise) continuously over the operating radio frequency", using a HackRF One. The paper gives only transmitter gain settings, with no distance and no received power ratio. — [Mekdad Sec. IV-B](https://arxiv.org/abs/2403.03858)
- Hijacking attack. The link is first broken by a tone: "we transmit a continuous singletone signal on the frequency of the targeted radio channel, where the signal strength of the Crazyradio-sniffer module is higher than the legitimate Crazyradio module". The paper then establishes its own link "through a second Crazyradio module". No dB value is given anywhere. — [Mekdad Sec. IV-B](https://arxiv.org/abs/2403.03858)
- Hardware: "The remote attacker device has a similar configuration as the GCS." Table I lists the hijacking hardware as "Two Crazyradio PA 2.4 GHz" ($70). The HackRF One and ANT500 antenna appear only under the jamming attack ($410 total). — [Mekdad Sec. IV-B, Table I](https://arxiv.org/abs/2403.03858)
- Why the takeover works: "we cannot distinguish between a malicious and a legitimate user since both of them can establish the GCS-2UAV communication without preliminary authentication." — [Mekdad Sec. IV-B](https://arxiv.org/abs/2403.03858)
- **Overreach flags, spoofer at 30 dB.**
  - Whitehouse supports the claim that a small advantage (0.17 dB or 1-3 dB, second-hand) can be enough for capture. It contains no upper level.
  - Mekdad contains no SIR. Its hijacker used a GCS-class radio (Crazyradio PA), not "the jammer's radio" (HackRF). The takeover exploited missing authentication after the link was broken, not capture of a live link at some SIR.
  - The project's 30 dB spoofer cap is therefore a transfer of Liu's in-band 30 dB to the spoofer. It is not a value measured or evaluated for counterfeit signals in either cited paper.
  - The project's "0.2-3 dB" also rounds Whitehouse's printed "0.17dB".
  - — [Whitehouse Sec. 2](<_extracts_threat/dl/whitehouse.pdf>); [Mekdad Sec. IV-B](https://arxiv.org/abs/2403.03858); [DECISIONS.md line 645](<C:/Users/Adi Suliman/uav-gcs-v6/docs/DECISIONS.md>)
- Related thresholds in other assigned sources (all simulations):
  - Shahriar et al. for an LTE random-access preamble: "for the correlation-based detector to choose the spoofed sequence over the actual sequence(s), the (J/S)RE at the input to the base station's receiver must be greater than or equal to zero, when ignoring channel noise". With a spoofed sequence "2 dB higher than the actual sequence", the frame-level ratio is "roughly -8 dB of (J/S)F". — [Shahriar tutorial, Sec. XI, ~p. 310](https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf)
  - For OFDM timing: "when the signal power for the false preamble is higher than the true preamble, the receiver will lock on to a timing point from the false plateau" (Fig. 8 caption, p. 303). — [Shahriar tutorial p. 303](https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf)

#### 1c. Benign WLAN interference: packets 0.27-3.2 ms, occupancy 5-86 %, up to 30 dB (Wollenberg; Cheema)
- Wollenberg citation in the file: T. Wollenberg, S. Bader, A. Ahrens, "Measuring Channel Occupancy for 802.11 Wireless LAN in the 2.4 GHz ISM Band", MSWiM'12, Paphos, Cyprus, ACM, pp. 305-308. The DOI 10.1145/2387238.2387289 is inferred from the file name `2387238.2387289.pdf`. — [Wollenberg (ACM)](https://doi.org/10.1145/2387238.2387289)
- It is a cabled test bed with generated traffic (Sec. 3, p. 307): "All components except the Bluetooth module are connected with shielded RF cables and RF combiners. We use RF attenuators to compensate for the missing free-space path loss." — [Wollenberg p. 307](https://doi.org/10.1145/2387238.2387289)
- Source of the 0.27-3.2 ms and 5-86 % values (Table 2 caption, p. 307): "Average channel occupancy (standard deviation) for three test cases. A: DSSS, frame duration 3.2 ms, frame rate 10/s. B: OFDM, 268 µs, 3045/s. C: OFDM, 536 µs/40 µs (alternating), 197/s." — [Wollenberg Table 2 p. 307](https://doi.org/10.1145/2387238.2387289)

  | Case | CO_total | CO_WLAN | RXCLR |
  |---|---|---|---|
  | A | 0.050 (0.001) | 0.031 (0.001) | 0.040 (0.001) |
  | B | 0.856 (0.012) | 0.812 (0.011) | 0.858 (0.001) |
  | C | 0.079 (0.012) | 0.056 (0.001) | 0.063 (0.005) |

  — [Wollenberg Table 2 p. 307](https://doi.org/10.1145/2387238.2387289)
- The paper's general observation on frame durations (p. 306): "the duration of 802.11 frames which we found usually to be below 1 ms for OFDM transmissions". — [Wollenberg Sec. 2.2 p. 306](https://doi.org/10.1145/2387238.2387289)
- Wollenberg gives no WLAN-to-desired-signal level. Its only level statement is about instrument accuracy: "an average deviation of -0.9 dBm from the actual signal level across durations of 400 µs .. 2 ms". — [Wollenberg Sec. 3 p. 307](https://doi.org/10.1145/2387238.2387289)
- Cheema citation in the file: A. A. Cheema, S. Salous, "Spectrum Occupancy Measurements and Analysis in 2.4 GHz WLAN", Electronics 2019, 8, 1011, doi:10.3390/electronics8091011. — [Cheema (MDPI)](https://doi.org/10.3390/electronics8091011)
- Measurement conditions (Sec. 3, p. 4-5): sensing bandwidth "100 MHz centered at 2.45 GHz with a time resolution of 204.8 µsec"; "The measurements were taken during working hours from 01:15 pm to 01:35 pm in an indoor environment." That is one 20-minute indoor capture. — [Cheema Sec. 3](https://doi.org/10.3390/electronics8091011)
- Threshold (p. 6): "-97 dBm is chosen as the decision threshold which is 10 dB above the measured noise floor". Table 2 (p. 4): noise floor -107.03 dBm, NF 10.95 dB, sensitivity -95 dBm at 12.03 dB SNR, IDR 33.32 dB. — [Cheema p. 4, 6](https://doi.org/10.3390/electronics8091011)
- Measured occupancy (p. 6): "the DC values were found to be 7.4013% in channel `1`, 11.5071% in channel `12` and 4.6449% over full-sensed bandwidth. These lower DC values indicate that both channels are highly underutilized". — [Cheema p. 6](https://doi.org/10.3390/electronics8091011)
- Table 6 (p. 12, directional antennas A1-A3) gives duty-cycle values between about 3.2 % and 13.0 %. Column alignment in the extraction is ambiguous; the range is from the printed values. — [Cheema Table 6 p. 12](https://doi.org/10.3390/electronics8091011)
- Idle-time distribution, channel 1 (p. 8): "The gamma distribution provides the best fit with minimum KS distance. The estimated parameters are k = 0.4898, [θ] = 73.8318 and the mean M = 36.1628 ms". Beacons: "the arrival of the beacon packet which was observed every 100 ms". — [Cheema p. 8](https://doi.org/10.3390/electronics8091011)
- Exponential fit is worst at the native 204.8 µs resolution (Fig. 6/7 legends, Table 4, p. 8-10):
  - Channel 1: EX D=0.2693, against GM 0.1282, LN 0.1290, WB 0.1328, GP 0.1413.
  - Channel 12: EX D=0.3009, against GP 0.1277, WB 0.1342, LN 0.1349, GM 0.1465.
  - At the coarser 1.6384 and 3.2768 ms resolutions the extracted column alignment is ambiguous.
  - — [Cheema Table 4, Figs. 6-7](https://doi.org/10.3390/electronics8091011)
- **Overreach flags, WLAN model.**
  1. The 5-86 % range matches Wollenberg's lab cases A and B (CO_total 0.050 and 0.856). Cheema's measured field values are 4.6-11.5 % (omni) and about 3.2-13 % (directional). Cheema backs the low end only.
  2. 0.27 ms and 3.2 ms are the frame durations of two configured test cases (B and A), not measured packet-length distributions. Case C also used 536 µs and 40 µs frames, which the project's range does not reflect.
  3. "Exponential idle gaps" is contradicted by Cheema's fits, where EX is worst.
  4. Neither paper gives a WLAN level relative to a desired signal, so "up to 30 dB" is not backed by either. The EIRP/ETSI EN 300 328/Song et al. chain was **not read in this review: UNVERIFIED**.
  - — [Wollenberg Table 2](https://doi.org/10.1145/2387238.2387289); [Cheema p. 6, 8-10](https://doi.org/10.3390/electronics8091011); [DECISIONS.md line 647](<C:/Users/Adi Suliman/uav-gcs-v6/docs/DECISIONS.md>)

#### 1d. Other project statements checked in passing
- Barajas recovery 0.14-2.6 s (D71 line 586). Table II gives "Static-Threshold Software Switching 6.001", "Adaptive-Threshold Software Switching 2.549", and "Adaptive Hardware-Assisted Switching 0.141" s. The project's range covers the two adaptive cases and omits the 6.0 s static-threshold baseline. — [Barajas Table II](https://arxiv.org/abs/2609.05739)
- The jammer-type list attributed to Barajas (D71 line 585) is second-hand. Barajas writes "[14] introduced a feature-based and spectrogram-tailored ML pipeline that classifies four jammer types (barrage, single-tone, successive-pulse, and protocol-aware)". Barajas's own jammer is "narrowband continuous-wave (CW) tones". — [Barajas Sec. II, IV-B](https://arxiv.org/abs/2609.05739)
- Mekdad does use a single tone (see 1b), so the CW claim in D71 line 585 is backed for Mekdad. — [Mekdad Sec. IV-B](https://arxiv.org/abs/2403.03858)
- Xu's reactive-jammer definition backs D72 line 641: "we take the viewpoint that it is not necessary to jam the channel when nobody is communicating". — [Xu 2005 Sec. 2.2](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)
- Pirayesh "unused pilots" (D72 line 641). What Pirayesh describes is a massive-MIMO uplink receiver that reserves pilots "so that these unused pilots can be leveraged to estimate the jammer's channel", followed by "a linear spatial filter". That is jammer-channel *estimation for mitigation*, not detection as such. — [Pirayesh arXiv v1, Sec. III](https://arxiv.org/abs/2101.00292)

### Inferences
- Liu's 30 dB is one simulated operating point. The project's 0-30 dB range is its own spread up to that point. "Within the sources' measured ranges" would be more accurately "up to the single value the source simulated". Nothing in Liu says what happens between 0 and 30 dB, because at 30 dB in-channel (against a 10 dB demodulation threshold) the user can only escape.
- From Liu's numbers (4 MHz user channels centred 2-18 MHz in 2 MHz steps; comb tones 4 MHz wide at 2, 10 and 18 MHz), the user channels centred at 6 and 14 MHz are fully jam-free. This explains Liu's near-unity comb throughput. A comb that jams every usable channel is a different, harsher threat than Liu's.
- Wollenberg's lengths and occupancies come in self-consistent *pairs*:
  - Case A: 3.2 ms × 10/s = 3.2 % airtime, against CO_WLAN 3.1 %.
  - Case B: 0.268 ms × 3045/s = 81.6 %, against CO_WLAN 81.2 %.
  - Drawing packet length and occupancy independently (for example 3.2 ms packets at 86 %) stays inside both ranges but outside any configuration either paper measured.
- Whitehouse's arrival-order finding matters once the receiver synchronises on a preamble. A counterfeit that arrives after the legitimate preamble does not automatically win, and the outcome depends on whether the receiver re-synchronises. This is evidence about the mechanism, not about a level.

### Gaps
- No assigned source measures a counterfeit-command power ratio. A sourced upper bound for the spoofer would need a paper that measured or evaluated spoofer power over the legitimate link. None is in this set.
- No assigned source gives WLAN interference power relative to a UAV uplink signal. Song et al., ETSI EN 300 328 and the link-budget table were outside this review (UNVERIFIED).
- Whitehouse's thresholds come from FM-demodulator and ALOHA literature (refs [2], [26]), not read. Whether they apply to a coherent QPSK receiver with MMSE combining is not addressed in any assigned source.
- The Liu journal version (Commun. Lett. 2018) was not in the library. Whether its numbers differ from arXiv v1 is UNVERIFIED.

---

## 2. Detection: which measurable quantities separate interference from poor link quality or from benign traffic, and how well do they work?

### Takeaway
The strongest published discriminator is a **consistency check**: degraded delivery together with high received energy means interference, while degraded delivery with low energy means a weak link. Xu 2005 builds this from PDR versus signal strength, and versus distance. All tested jammers fall in the "jammed region" (PDR < 65 % and signal strength above the 99 % benign band).

Single statistics fail. Signal strength and carrier-sensing time miss random and reactive jammers. PDR alone confuses jamming with a dead or departed sender. A reactive jammer looks normal in carrier-sensing time.

For benign WLAN, the published quantities are:
- duty cycle and channel occupancy, estimated over windows of tens of seconds (Wollenberg 13-27 s);
- idle-time-window distributions (gamma or lognormal, with 100 ms beacon periodicity);
- the split between decodable-802.11 occupancy and total occupancy.

Measured occupancy is low (about 5-12 %), and short packets are lost at coarse time resolution.

Several sources independently propose sensing while the legitimate transmitter is silent:
- Noubir: a secret-position interruption to detect reactive jammers (proposed, not evaluated);
- Pirayesh: MCR estimates the jammer's channel ratio "when the legitimate transmitter stays silent";
- Xu: energy sampled after PDR drops.

### Cited Findings

**Xu et al. 2005: PDR / signal-strength / location consistency (measured, MICA2 motes)**
- Metrics defined in Sec. 2.1: Packet Send Ratio and Packet Delivery Ratio. Effect of jammers: "any one of the four jammers, if placed within a reasonable distance from the receiver, can cause the corresponding PDR to become close to 0." — [Xu 2005 Sec. 3.3](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)
- Single statistics fail (Sec. 3.2 summary): "both signal strength and carrier sensing time, under certain circumstances, can only detect the constant jammer and deceptive jammer. Neither of these two statistics is effective in detecting the random jammer or the reactive jammer." — [Xu 2005 Sec. 3.2](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)
- Reactive jammer and carrier sensing: "the reactive jammer produces sensing time cumulative distributions that overlap completely with the case of no background traffic." — [Xu 2005 Sec. 3.2](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)
- PDR separates jamming from congestion. Under heavy congestion "the PDR measured by the receiver is still around 78%", and in the ns-2 study 9 streams gave "PDR 74.14%". PDR alone does not separate jamming from sender failure or range loss: "it still cannot differentiate the jamming attack from other network dynamics". — [Xu 2005 Sec. 3.2-3.3](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)
- The consistency rule (Sec. 4.1): "in the first case, the signal strength is low, which is consistent with a low PDR measurement. While in the jammed case, the signal strength should be high, which contradicts the fact that the PDR is low." — [Xu 2005 Sec. 4.1](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)
- Calibration and result (Sec. 4.1, Fig. 6):
  - PDR window of 200 packets; signal strength "sampled every 1msec for 200msecs".
  - The jammed region is "(P DR, SS) values that are above the 99% signal strength confidence intervals and whose PDR values are less than 65%".
  - Result: "(P DR, SS) values for all jammers distinctively fall within the jammed-region."
  - The jammer was at "roughly -4dBm" against a source at "roughly -5dBm". These are transmit powers.
  - — [Xu 2005 Sec. 4.1, Fig. 6](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)
- Severity floor: "a nonaggressive jammer, which only marginally affects the PDR, does not cause noticeable damage to the network quality and does not need to be detected or defended against." — [Xu 2005 Sec. 3.3](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)
- Location check (Sec. 4.2, Fig. 7): jammed (PDR, distance) points "are distinctly separated from normal operation values" when the source-receiver separation is small. — [Xu 2005 Sec. 4.2](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)
- Signal-shape features (Sec. 3.1): spectral discrimination with higher-order crossings ("first two higher order crossings, D1 vs. D2", Fig. 3) on RSSI sampled every 1 ms. — [Xu 2005 Sec. 3.1](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)
- No ROC, F1 or accuracy figure is reported. The evidence is the scatter separation in Figs. 6-7. — [Xu 2005 Sec. 4](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)

**Noubir et al. 2011: interference cannot be told from poor link quality by default; secret-position silent interval (proposed)**
- Sec. 3: "Radio receivers are incapable of differentiating between malicious interference (e.g., jamming) and non-malicious interference such as direct collisions" and "This gets even harder to do for moving nodes with dynamic link quality due to multi-path fading and environmental changes." — [Noubir WiSec'11 Sec. 3](https://www.cs.umb.edu/~shengbo/paper/wisec11.pdf)
- Sec. 7: "Some mechanisms can be used to detect the presence of a reactive jammer. For example, interrupting the transmission for a short period of time within the packet (the location is cryptographically derived) or placing a training sequence at a cryptographic location within the packet allowing the receiver to detect if a jamming signal is present." — [Noubir Sec. 7](https://www.cs.umb.edu/~shengbo/paper/wisec11.pdf)
- Evaluation status: "We leave the experimental demonstration of the efficiency of the proposed mitigation mechanisms for future work." No detection performance is given for this idea. — [Noubir abstract](https://www.cs.umb.edu/~shengbo/paper/wisec11.pdf)

**Wollenberg 2012: separating 802.11 occupancy from other interference (measured, cabled)**
- Method: "we have to distinguish between channel occupancy caused by (decodable) 802.11 transmissions on the one hand and channel occupancy caused by interference on the other hand", with "COtotal [≈] COWLAN + COinterference" ([≈] lost in extraction). — [Wollenberg Sec. 1-2 p. 305-306](https://doi.org/10.1145/2387238.2387289)
- Threshold: "Instead of using a fixed threshold, we found that [θ] needs to be adjusted dynamically to reflect different CCA implementations and signal level constellations". Window: "n = 50 .. 100 (13 .. 27 s) to be a useful trade-off between accuracy and time resolution". — [Wollenberg Sec. 2.2 p. 306](https://doi.org/10.1145/2387238.2387289)
- Accuracy: "Comparing COtotal with RXCLR we see a minor overestimation ([≈] 1pp)". With a Bluetooth interferer: "For overall channel occupancies [≥] 40 % we see overestimations of up to 16 pp. COWLAN is accurate for low interference cases but drops with increasing interference." — [Wollenberg Sec. 3 p. 307](https://doi.org/10.1145/2387238.2387289)
- Interferer setup: Bluetooth frames "with a duration of 400 µs and different intervals of 625 µs, 1000 µs, 2000 µs, and 4000 µs". In Fig. 1 the interferer is "sequentially set to 0 %, 10 %, 21 %, 42 %, and 63 % duty cycle". — [Wollenberg Sec. 3, Fig. 1 p. 307-308](https://doi.org/10.1145/2387238.2387289)
- Limit: "the overall system is not well-suited to accurately describe short, bursty channel usage." — [Wollenberg Sec. 4 p. 308](https://doi.org/10.1145/2387238.2387289)

**Cheema 2019: duty cycle and idle-time statistics (measured, indoor)**
- Duty cycle definition (eq. 1, p. 5): "DC = Total time occupied by busy states / Total time occupied by both states". Measured values are 4.6-11.5 % (see 1c). — [Cheema eq. 1 p. 5; p. 6](https://doi.org/10.3390/electronics8091011)
- Time-resolution effect: "Both the time resolution of the SE and directional antennae can influence the state (idle/busy) of the signal and if not selected appropriately can produce longer idle time windows with the inability to detect short duration signals." — [Cheema Conclusions p. 13](https://doi.org/10.3390/electronics8091011)
- Signature features:
  - gamma or lognormal idle-time windows;
  - a beacon "observed every 100 ms" that makes the idle-time CDF "increase rapidly in the interval (95 ms to 100 ms)";
  - per-channel differences ("different concurrently measured channels in a radio technology may have different ITW statistics").
  - — [Cheema p. 8, 13](https://doi.org/10.3390/electronics8091011)

**Barajas et al. 2026: spectral descriptors and m-of-n confirmation (measured, ROS 2 robot)**
- Features: "five spectral descriptors were computed: mean PSD, standard deviation of PSD, maximum PSD, spectral entropy, and channel occupancy", fed to a Random Forest. — [Barajas Sec. IV-B, IV-D](https://arxiv.org/abs/2609.05739)
- Decision rules. Static: "a fixed threshold of -30 dB for 2.4 GHz operation or -18 dB for 5 GHz operation" with "Nsample = 75 consecutive above-threshold samples". ML: "set to 75% for 2.4 GHz operation and 50% for 5 GHz operation" and "three consecutive positive classifications before declaring a jamming event". — [Barajas Sec. IV-D](https://arxiv.org/abs/2609.05739)
- Measured: "a deterministic detection latency of approximately 0.6 seconds", and on jammer activation "the incoming RMS signal power experiences a sharp step-increase of over 20 dB". — [Barajas Sec. V-A](https://arxiv.org/abs/2609.05739)
- The static threshold is "heavily penalized by false triggers". No false-alarm rate, accuracy or F1 is reported. — [Barajas Sec. V-B](https://arxiv.org/abs/2609.05739)

**Pirayesh & Zeng: detection results reported in the survey (second-hand, originals not read)**
- Puñal et al. [83] (Wi-Fi) used "noise power, the time ratio of channel being busy, the time interval between two frames, the peak-to-peak signal strength, and the packet delivery ratio" with random forest. Reported: "98.4% accuracy for constant jamming and with 94.3% accuracy for reactive jamming" (simulation). — [Pirayesh arXiv v1 Sec. II](https://arxiv.org/abs/2101.00292)
- Arjoune et al. [105] (5G): features "packet error rate, packet delivery ratio, and the received signal strength"; "random forest algorithms achieve higher accuracy (95.7%)" (simulation). — [Pirayesh Sec. III](https://arxiv.org/abs/2101.00292)
- LTE PUCCH: "the energy of the received PUCCH signal is continuously monitored and compared with the signal strength of other physical channels", and "the number of consecutive errors on PUCCH decoding is tracked". — [Pirayesh Sec. III](https://arxiv.org/abs/2101.00292)
- Silent-period estimation (MCR, [75]): "the jammer's channel ratio is first estimated by the received signals at each antenna when the legitimate transmitter stays silent." — [Pirayesh Sec. II](https://arxiv.org/abs/2101.00292)

**Shahriar et al. 2015 (tutorial) and Rao 2016: detection inside OFDM systems**
- Control-channel attacks: "Detection of an attack could be as simple as detecting a sudden loss in communications from multiple users. A more complex approach would be monitoring for extra energy on the control channels." — [Shahriar tutorial Sec. XI-E p. 311](https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf)
- Rao, Sec. 3.3: for LTE, "these parameters include Channel Quality Indicator (CQI), Reference Signal Received Power (RSRP), Reference Signal Received Quality (RSRQ) and Received Signal Strength Indicator (RSSI)". The chapter "assumes that presence of the jammer on pilot tones is detected" and reports no detection performance. — [Rao MS thesis Sec. 3.3](<_extracts_threat/dl/rao_thesis.pdf>)
- Rao's "CQI Spoofing" result shows that quality *estimates* can be manipulated: "the attacker tricks the user terminal into thinking that the channel quality is good, by transmitting interference transmission only on the data locations, while deliberately avoiding the pilots." — [Rao abstract](<_extracts_threat/dl/rao_thesis.pdf>)

**Whitehouse 2005: collision detection by a second preamble (measured)**
- "A collision is detected if a preamble is found during the reception of another packet." Measured: "If t were uniformly distributed in real network scenarios, collision detection would have a 42% success rate", and recovery of "one packet in 92% of all collisions". An extension "can increase detection to nearly 92% of all collisions". — [Whitehouse Sec. 3-4](<_extracts_threat/dl/whitehouse.pdf>)

**Yu et al. 2025 and Nanayakkara et al. 2025 (marginal)**
- Yu, for injection and spoofing: "One of the methods to detect attacks of this type is to have a mechanism which allows the UAVs in the network to compare their traffic parameters with neighboring UAVs." No performance numbers are given. — [Yu 2025 survey](https://arxiv.org/abs/2504.07358)
- Nanayakkara: spectrogram object detection of drone remote controllers. CenterNet "detection accuracy of 98%", EfficientDet D0 "69%", SSD ResNet50 "48%". Captures were taken "incrementally increasing by 5 m up to a maximum of 40 m". — [Nanayakkara 2025 Sec. 3.3, 4](https://doi.org/10.70322/dav.2025.10019)

### Inferences
- Xu's consistency logic maps onto measurements the project already has: link quality (BER/PLR) against energy observed without the own signal (the quiet slot). Xu calibrates the benign region empirically with 99 % confidence bands, which gives the project a published way to state a false-alarm level for this check.
- For benign WLAN (the weakest class, F1 0.70), the sources point to statistics that need **time**, not single frames:
  - occupancy windows of 13-27 s (Wollenberg);
  - gamma or lognormal idle times and 100 ms beacons (Cheema).
  - At the measured 4.6-11.5 % duty cycles, most short observation windows contain no WLAN packet. Cheema warns that coarse time resolution hides short packets.
  - This is consistent with per-frame ambiguity at low occupancy. It is not evidence about any particular fix.
- Noubir's secret-position interruption and Pirayesh's MCR silent-period estimation are the closest published analogues to the project's quiet slot. Noubir's is unevaluated; MCR is reported only second-hand. Neither gives a detection rate.
- Rao's CQI-spoofing finding implies that any measurement window an interferer can locate (pilots, quiet slot) can be avoided or targeted to bias the receiver's estimate. This is the same reasoning Noubir uses for a cryptographically placed silent interval.

### Gaps
- No assigned source gives a ROC, false-alarm or F1 figure for separating *benign WLAN* from hostile interference. Wollenberg and Cheema measure occupancy; they do not classify.
- Puñal [83], Arjoune [105], MCR [75] and Zeng [76] are known here only through Pirayesh's summaries (UNVERIFIED in the originals).
- No source quantifies how short a signal-free interval can be and still support reliable interference detection. Note 13's SNR-wall material (Tandra & Sahai, via Shbat & Tuzlukov) is outside this assignment and was not re-read.

---

## 3. Published defences and their measured benefit

### Takeaway
- **Pilot randomisation** has simulated numbers (Shahriar tutorial and PhD). It helps under strong pilot jamming and *costs* 1-4 dB (confined bin) or 4 dB (random) at BER 0.2 when no jammer is present. At weak jamming it is worse than equally spaced pilots.
- **Rao** reports that a coordinated cyclic shift of pilot locations restores channel-estimation MSE to the jammer-free curve and improves BER "by an order of magnitude". Rao criticises full randomisation for its no-jammer loss and its initial-access cost.
- **CAF synchronisation with a known (secret) training symbol** gives "comparable performance" to Schmidl-Cox without jamming. Its errors start around -5 dB SNR, and it has "significantly lower" frequency-error rates when the attacker is at equal or higher power. The cost is complexity and a new dependence on a known symbol.
- **Sync-amble (preamble position) randomisation** with secret location is *proposed* by La Pan, with no simulated benefit.
- **Receiver-side spatial processing before synchronisation**:
  - Zeng et al., via Pirayesh: Wi-Fi decoded with jamming 20 dB stronger;
  - a multi-antenna ZigBee receiver (Pirayesh, W07b version): 100 % reception at 20 dB and a 26.7 dB mitigation gain;
  - Ogawa: a reference-free power-inversion array suppresses any strong signal, including a strong desired signal. The paper gives only a loop-gain bound.
- **Noubir's randomised probing and secret-position interruptions** are unevaluated proposals.
- **Channel switching**: Liu reaches near-unity throughput against comb jamming. Barajas measures 0.141-6.0 s recovery. Navda (via Pirayesh) restores 60 % throughput under reactive jamming.

### Cited Findings

#### 3a. Randomised or secret pilot placement (Shahriar tutorial; Shahriar PhD; Rao MS)
- Attack severity being defended against (Shahriar PhD, Fig. 4.3/4.4): "for 7 dB SJR and 12 dB SNR, the BERs are 0.08, 0.13, 0.42 for barrage jamming, pilot tone jamming and pilot tone nulling respectively". Also: "pilot jam and pilot null required 4 dB and 12 dB less power than barrage jam to cause 0.3 BER" (at 5 dB SNR). — [Shahriar PhD Ch. 1 p. 12-13; Ch. 4](<_extracts_threat/dl/shahriar_phd.pdf>)
- The defence principle (tutorial Sec. X-G p. 306): "The pilot nulling attacks can be avoided by transmitting pilot tones whose values are unknown to the attackers. In the absence of knowledge about pilot tone values, pilot nulling becomes as effective as pilot jamming that can be avoided by randomizing the pilot locations." — [Shahriar tutorial p. 306](https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf)
- PhD abstract: "The threats were mitigated by randomizing the location and value of pilot tones, causing the optimal attack to devolve into barrage jamming." — [Shahriar PhD abstract](<_extracts_threat/dl/shahriar_phd.pdf>)
- Secret placement: "a pseudorandom keystream generator to specify the locations of the pilot tones. This is seeded by a shared secret key known to members of the network, and an initialization vector changed every frame." The PhD adds: "This may not be feasible in many deployment scenarios." — [Shahriar tutorial p. 306-307](https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf); [Shahriar PhD Sec. 5.3 p. 100](<_extracts_threat/dl/shahriar_phd.pdf>)
- Simulation setup (tutorial Sec. X-H p. 307): QPSK, "256-point FFT with a cyclic prefix length of (1/8)", "every 8th subcarrier as a pilot tone", "8-tap random channel", linear-interpolation equaliser, "10 000 iterations", and "The channel between the transmitter and target is assumed to be perfectly known to the jammer." — [Shahriar tutorial p. 307](https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf)
- Measured benefit and cost, tutorial Fig. 14, pilot jamming at 0 dB JSR, BER 0.2 (p. 307):
  - No jammer: "the deterministic scheme requires 1 dB SNR, confined bin scheme requires 2 dB SNR, and the random scheme requires 5 dB SNR".
  - Under pilot jamming: "confined bin scheme requires 5 dB SNR, and completely random scheme requires 10 dB SNR".
  - — [Shahriar tutorial p. 307](https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf)
- Tutorial Fig. 15 (SNR 10 dB, p. 308):
  - Strong jamming: "At 0 dB JSR, the deterministic scheme's BER is 0.4, confined bin's BER 0.15, and random scheme's BER is 0.25."
  - Weak jamming: "At -10 dB JSR (equivalent to 10 dB of SJR), the deterministic scheme's BER is 0.01, confined bin's BER 0.02, and completely random scheme's BER is 0.1."
  - — [Shahriar tutorial p. 308](https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf)
- PhD Fig. 5.4 (SNR 5 dB):
  - Strong jamming: "at -10 dB SJR and 5 dB SNR, the conventional arrangement's BER is 0.4, confined bin's BER is 0.2, and random arrangements BER is 0.3."
  - Weak jamming: "At 20 dB SJR, the conventional, confined bin, and random arrangement's BER are 0.09, 0.15, and 0.25 respectively."
  - The two versions use different SNRs and SJR points, so their numbers should not be mixed.
  - — [Shahriar PhD p. 105-106](<_extracts_threat/dl/shahriar_phd.pdf>)
- Rao's critique: "randomizing pilot tone locations leads to sub-optimal OFDM performance in the absence of a jammer [25] and requires higher layer protocols to communicate the pilot patterns to legitimate users, which makes initial access to the cell a time-consuming procedure." — [Rao Sec. 3.1](<_extracts_threat/dl/rao_thesis.pdf>)
- Rao's alternatives and results (simulation, LTE-like parameters):
  - Cyclic shift: "the receiver can coordinate with the transmitter to cyclically shift all the pilot locations by one or more subcarriers to evade the jamming signal". Its MSE "has the same performance with jamming as without it, thus perfectly restoring the channel estimation performance". It "improves the BER performance by an order of magnitude and its performance approaches that of a jammer-free scenario".
  - RE blanking with interference cancellation "reduces its average SNR per bit (Eb/N0) by at least 3 dB" on the pilot and leaves an MSE error floor.
  - Limitation: "neither of these mitigation techniques can protect data that is being jammed when the jammer transmits continuously."
  - — [Rao Sec. 3.4](<_extracts_threat/dl/rao_thesis.pdf>)
- Attack-side numbers from Rao:
  - Simulation: a synchronous pilot jammer causes denial of service (BER > 0.25) "with a JSR of about 5 dB for all values of Eb/N0", which is about 9 dB less total power than the signal for its pilot density.
  - Experiment (USRP B210 LTE testbed): "full-band jamming of pilots needs 5 dB less power than jamming the entire downlink signal".
  - — [Rao Ch. 2, abstract](<_extracts_threat/dl/rao_thesis.pdf>)

#### 3b. Secret or agreed preambles, sync-amble randomisation, cross-ambiguity synchronisation (Shahriar tutorial; La Pan WCMC 2016; La Pan PhD 2014)
- Attack effects on Schmidl-Cox timing:
  - "the estimator starts to be impacted by noise around -10 dB and is completely lost in the noise floor around -32 dB" (tutorial Fig. 9).
  - Preamble nulling needs "the effective SNR of the preamble symbol seen at the receiver is around -30 dB" (tutorial p. 302).
  - Preamble warping "is most effective when it has equal power as the preamble at the receiver"; at much higher power "it actually can improve synchronization performance" (tutorial Fig. 10).
  - — [Shahriar tutorial p. 302-303](https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf)
- Thesis, same estimator: "The timing estimate is not adversely affected by AWGN until the SNR drops below -10 dB." The WCMC extraction reads "less than 10 dB" (p. 183); this is a lost minus sign, consistent with the thesis and the tutorial. — [La Pan thesis Ch. 3 p. 41-42](<_extracts_threat/dl/lapan_thesis.pdf>); [La Pan WCMC p. 183](https://doi.org/10.1002/wcm.2500)
- Terminology warning. La Pan's "preamble whitening" is an **attack** (noise only during the preamble), not receiver-side whitening. Its power saving over continuous noise depends on frame length: "for a required degradation of 30 dB, the value of n would have to be larger that 693 ... for a required degradation of 20 dB, the value of n only has to be larger than 69." — [La Pan WCMC p. 184](https://doi.org/10.1002/wcm.2500)
- Mitigation proposals (tutorial Sec. IX-J p. 303-304):
  - "have the transmitter and receiver agree on a specific preamble, or a set of preambles, beforehand";
  - "disguising the preamble";
  - CAF synchronisation "would not require any particular structure to the preamble-other than that it be a valid OFDM symbol. Instead, this method would require that the preamble be known to both the transmitter and the receiver";
  - "Disguising the preamble, as well as its location in time and frequency are possible ways to mitigate".
  - These are proposals with no numbers.
  - — [Shahriar tutorial p. 303-304](https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf)
- Sync-amble randomisation (WCMC Sec. 6.1 p. 188):
  - "the sync-amble location within each frame after the first can be shared as secret knowledge between the transmitter and the receiver".
  - Thesis: "draw the location of the preamble randomly, according to Sp ∼ U(1, Nfr) ... since this is the maximum entropy distribution".
  - Caveats in the thesis: "the preamble is still detectable by adversarial communications devices", "could still be vulnerable to specific attacks such as the false preamble", and it "would also require more processing at the receiver".
  - No simulated benefit is reported: WCMC says "we propose three solutions as the most viable and present some initial results regarding one of them" (the CAF).
  - — [La Pan WCMC p. 188](https://doi.org/10.1002/wcm.2500); [La Pan thesis Sec. 4.2 p. 78-80](<_extracts_threat/dl/lapan_thesis.pdf>)
- CAF results (thesis Sec. 4.3, simulation, N = 256 or 224 subcarriers, multipath plus AWGN):
  - No jammer: "Estimation errors that would preclude the receiver from performing demodulation start to arise around -5 dB SNR."
  - Abstract: the method is "shown to maintain comparable performance to other correlation based synchronization estimators while offering the benefit of a disguised preamble".
  - Against phase warping (jammer knows both channels but not the exact sequences): "In any scenario where the jammer is transmitting at a power equal to or more than the synchronization symbol, the CAF demonstrates a significantly lower frequency error estimation rate."
  - Fig. 4.13 / WCMC Fig. 12: "The CAF synchronization mitigates the power efficient attacks at the expense of acquisition complexity."
  - No numeric error rates are printed in the text; the values exist only in the figures.
  - — [La Pan thesis p. 80-84](<_extracts_threat/dl/lapan_thesis.pdf>); [La Pan WCMC p. 189](https://doi.org/10.1002/wcm.2500)
- CAF costs (WCMC p. 189): "requires a significantly higher computational burden"; "it requires a known training symbol at the receiver or a small set of known symbols ... which represents a new area of security vulnerability." — [La Pan WCMC p. 189](https://doi.org/10.1002/wcm.2500)
- Spatial-diversity synchronisation is proposed only (WCMC Sec. 6.3): "It is very possible that there is a synchronization solution that replaces the need for timing diversity in the training symbols ... with spatial diversity." — [La Pan WCMC p. 189](https://doi.org/10.1002/wcm.2500)

#### 3c. Receiver-side spatial processing / power inversion before synchronisation (Ogawa 1983; Pirayesh survey)
- Ogawa citation (printed in the file): Y. Ogawa, M. Ohmiya, K. Itoh, "Upper Bound of a Loop Gain in a Power Inversion Adaptive Array", IEEE Trans. Aerospace and Electronic Systems AES-19(5), 778-780, Sep. 1983. Correspondence item, 3 pages; OCR quality is poor. — [Ogawa (HUSCAP)](https://hdl.handle.net/2115/5972)
- Ogawa's principle (Sec. I p. 778): "A power inversion adaptive array [1, 2] is useful in mobile communication systems because it does not require information about the desired signal arrival angle." — [Ogawa p. 778](https://hdl.handle.net/2115/5972)
- The trade-off: "it nulls any strong signal. Thus, if the desired signal is strong, it is suppressed." Also: "When an interference signal is not present, the signal suppression problem is most serious." And: "a lower value of the loop gain yields a poorer interference suppression performance". — [Ogawa p. 778](https://hdl.handle.net/2115/5972)
- Ogawa's only numbers are a loop-gain bound for a required no-interference output SNR (A = -10 dB): "Assume, for example, N = 4 and the input SNR varies from - 5 dB to 10 dB. The upper bound of g for the input SNR = - 5 dB is 3.30. And the one for the input SNR = 10 dB is 0.357." It gives no interference-suppression dB figure. — [Ogawa Fig. 2, p. 779](https://hdl.handle.net/2115/5972)
- Spatial projection before synchronisation (Zeng et al. [76], CNS 2017, second-hand via Pirayesh):
  - "a jamming-resilient synchronization algorithm ... First, it alleviates the received time-domain signal using a spatial projection-based filter. Second, the conventional synchronization techniques were deployed".
  - Result on GNURadio-USRP2: "the receiver could successfully decode the desired Wi-Fi signal in the presence of 20 dB stronger [jamming] than the signals of interest".
  - The blind module "does not need any channel information".
  - — [Pirayesh arXiv v1 Sec. II (Wi-Fi anti-jamming)](https://arxiv.org/abs/2101.00292)
- Multi-antenna ZigBee receiver ([137], Pirayesh et al., second-hand; only in the later survey version W07b): "achieves 100% packet reception rate in the presence of jamming signal that is 20 dB stronger than ZigBee signal" and "an average of 26.7 dB jamming mitigation gain compared to commercial off-the-shelf ZigBee receivers". It "uses the preamble field of a ZigBee frame ... to train a neural network". — [Pirayesh W07b version](<C:/Users/ADISUL~1/AppData/Local/Temp/claude/C--Users-Adi-Suliman-uav-gcs-adaptive-secure-comms/0ff3360f-912b-4701-bfb0-77d6917b5fc3/scratchpad/src/W07b_Pirayesh2022_jamming_survey.txt>)
- MCR ([75]): the jammer's channel ratio is estimated "when the legitimate transmitter stays silent", then used with the preamble to decode. Massive-MIMO uplink ([100]): reserved unused pilots estimate the jammer's channel, followed by "a linear spatial filter". No numbers are given in the survey for these two. — [Pirayesh Sec. II (Wi-Fi anti-jamming), III](https://arxiv.org/abs/2101.00292)

#### 3d. Secret-position silent intervals and randomised probing (Noubir 2011)
- Attack efficiency (cabled USRP testbed, channel 11 at 2.462 GHz, 1470-byte UDP):
  - "eight reactive jamming pulses every second are sufficient to achieve the same network throughput degradation achieved by a periodic jammer with the jamming energy cost 100 times higher";
  - "a smart reactive jammer can maintain links at a low data rate (1 Mbps) at a minimal jamming cost (jamming only 5 - 8 packets/s)";
  - "ONOE in particular suffers from the phenomenon of congestion collapse where the nodes fail to recover from the lowest data rate even after the jammer stops jamming."
  - — [Noubir abstract, Sec. 1, Sec. 6](https://www.cs.umb.edu/~shengbo/paper/wisec11.pdf)
- Defences (Sec. 7):
  - goal "severely limiting the amount of key information that can be inferred by an adversary. This lack of information then forces the adversary to operate as a memoryless jammer";
  - "Instead of sending a probe every ten packets, the probing order should be randomized, furthermore the probed rates should not be sequential but randomly selected";
  - rate information protected by "generating a cryptographic stream based on a shared secret key and a random initialization vector";
  - the secret-position interruption quoted in Section 2.
  - All are unevaluated ("left for future work").
  - — [Noubir Sec. 7](https://www.cs.umb.edu/~shengbo/paper/wisec11.pdf)
- Related survey summary: Orakcal & Starobinski found "SampleRate RAA is more vulnerable to jamming attacks" than ARF. — [Pirayesh W07b version](<C:/Users/ADISUL~1/AppData/Local/Temp/claude/C--Users-Adi-Suliman-uav-gcs-adaptive-secure-comms/0ff3360f-912b-4701-bfb0-77d6917b5fc3/scratchpad/src/W07b_Pirayesh2022_jamming_survey.txt>)

#### 3e. Channel switching / frequency diversity (Liu; Barajas; Pirayesh; Mekdad)
- Liu (simulation): comb jamming avoided with normalized throughput "close to one after convergence". Against the intelligent jammer, the best user strategy is that "the probability of each action is almost identical" (Fig. 7). — [Liu Sec. IV p. 4](https://arxiv.org/abs/1710.04830)
- Barajas (measured, CW jammer, 2.4/5 GHz dual band, 15 runs):
  - Recovery: 6.001 s (static threshold, software), 2.549 s (ML, software), 0.141 s (two pre-associated interfaces).
  - Pooled RMS path error: 2.84 cm against 0.60 cm, "a 78.9% reduction".
  - Stated limit: "band switching can be defeated by reactive or persistent jammers that follow the link across bands [32], [33], an adversary class the continuous-wave evaluation here does not exercise".
  - — [Barajas Sec. II, V-B, V-C](https://arxiv.org/abs/2609.05739)
- Navda et al. [72] (second-hand via Pirayesh): "The reactive jamming attack can decrease Wi-Fi network throughput by 80% based on their experimental results. It was also shown that, by using the channel hopping technique, 60% Wi-Fi network throughput could be achieved". — [Pirayesh arXiv v1 Sec. II (Wi-Fi anti-jamming)](https://arxiv.org/abs/2101.00292)
- DSSS thresholds (Karishma et al. [41], second-hand): "an 802.11b Wi-Fi receiver fails to decode its received packets when received SJR < -7 dB for 1 Mbps ... and when SJR < 2 dB for 11 Mbps". — [Pirayesh Sec. II (Wi-Fi anti-jamming)](https://arxiv.org/abs/2101.00292)
- Pirayesh on link adaptation: "rate adaptation and power control techniques will not work in the presence of high power constant jamming attacks." — [Pirayesh Sec. II (Wi-Fi anti-jamming)](https://arxiv.org/abs/2101.00292)
- Mekdad lists defences without evaluating them: "channel/frequency hopping techniques, Direct Sequence Spread Spectrum (DSSS) techniques, Multiple-Input and Multiple-Output (MIMO) techniques", adding "there is no unified solution that can be effective against all classes of jamming attacks". Safe-mode actions: "emergency landing, returning home, and sending GPS location". — [Mekdad Sec. V-A](https://arxiv.org/abs/2403.03858)

#### 3f. Authentication against counterfeit commands (Dixit; Mekdad)
- Dixit: "MAVLink v2.0 ... providing enhancements against cyber threats, including message signing for cryptographic authentication and data integrity". In the testbed, decryption is "contingent upon successful verification of both the checksum and the digital signature" and "packets from unknown sources are discarded". — [Dixit 2026 Sec. I, III-IV](https://arxiv.org/abs/2606.27028)
- Dixit's prior work (second-hand): "over-the-air man-in-the-middle (MITM) and replay attacks were unsuccessful due to the integrated encryption and authentication mechanisms provided by MAVShield". — [Dixit Sec. II](https://arxiv.org/abs/2606.27028)
- Mekdad's hijack succeeded because the link had no "preliminary authentication". The hijacking defences it suggests are behavioural: "statistical analysis of the flight patterns, GPS-based detection methods, estimated position techniques based on onboard Inertial Measurement Unit (IMU)". — [Mekdad Sec. IV-B, V-A](https://arxiv.org/abs/2403.03858)

### Inferences
- The secret-pilot and secret-preamble literature (Shahriar, La Pan) is almost entirely **simulation by the same Virginia Tech group** (Clancy / McGwier / Reed). It is consistent, but not independent.
- In this set the strongest measured over-the-air results for anti-jam receivers are:
  - the multi-antenna, before-synchronisation results: 20 dB, and 26.7 dB gain;
  - Rao's LTE testbed result for the attack side.
  - The spatial results are second-hand through Pirayesh.
- Both pilot-randomisation versions agree on the *shape* of the trade-off: randomisation helps at strong jamming and hurts without it. The PhD's 5 dB-SNR numbers show the random scheme worse than conventional at 20 dB SJR (0.25 against 0.09 BER).
- Ogawa shows why a reference-free nuller needs care when the desired signal is strong. The MCR and Zeng descriptions estimate the interference while the legitimate transmitter is silent, or project it out before synchronisation, which avoids suppressing the desired signal. That reading is mine; neither paper states it in terms of Ogawa.
- Barajas's own text says switching is not evidence against followers. Its numbers are evidence against a static CW tone only.

### Gaps
- No assigned source reports a measured (over-the-air) benefit for secret pilot placement, secret preamble or sync-amble randomisation. All results are simulations, or are proposals only (La Pan's sync-amble; Noubir's silent interval).
- The CAF benefit is shown only in figures (WCMC Fig. 12; thesis Figs. 4.12-4.13). Numeric error rates could not be read from the text extraction.
- Zeng et al. [76], MCR [75] and the ZigBee receiver [137] were not read in the original. Their conditions (antenna count, jammer count, bandwidth) are UNVERIFIED.
- Ogawa gives no interference-suppression figure. Compton 1979 (the original power-inversion paper, ref [1]) was not read.

---

## 4. Per-source records and relevance verdicts

### Takeaway
- **CORE**: Xu 2005, Liu 2018, Wollenberg 2012, Cheema 2019, Shahriar tutorial 2015, La Pan WCMC 2016 / thesis 2014, Noubir 2011, Pirayesh survey.
- **SUPPORTING**: Whitehouse 2005, Mekdad 2024, Barajas 2026, Shahriar PhD 2015, Rao 2016, Ogawa 1983.
- **MARGINAL**: Yu 2025, Dixit 2026, Nanayakkara 2025.

Main issues found:
- the spoofer's 30 dB has no source;
- Mekdad's hijacker was misdescribed;
- the 86 % occupancy is lab-generated (Wollenberg), not Cheema;
- exponential idle gaps are contradicted by Cheema;
- Liu's comb jammer was misdescribed;
- Barajas has editorial-quality flags.

### Cited Findings

#### A02 Xu et al. 2005: CORE
- Citation in the file: W. Xu, W. Trappe, Y. Zhang, T. Wood (WINLAB, Rutgers), "The Feasibility of Launching and Detecting Jamming Attacks in Wireless Networks", MobiHoc'05, Urbana-Champaign, May 25-27, 2005, ACM. Pages and DOI are UNVERIFIED (not printed in the extraction). — [Xu 2005](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)
- What it measured: four jammer models (constant, deceptive, random, reactive) on MICA2 motes (CC1000); PSR and PDR (Table 1); signal-strength, carrier-sensing-time and PDR statistics; two consistency-check detectors validated on motes (Figs. 6-7). — [Xu 2005](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)
- What the project relies on: the jammer taxonomy, the reactive definition, and "low PDR with strong signal = jamming". **Backed** (Sec. 2.2, 4.1). — [Xu 2005](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)
- Not yet used:
  - the empirical 99 % confidence-band calibration of the benign (PDR, SS) region, with jammed region PDR < 65 %;
  - the location consistency check;
  - higher-order-crossing signal-shape features;
  - the finding that reactive jammers leave carrier-sensing time unchanged.
  - — [Xu 2005](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)
- Quality flags: no accuracy or false-alarm metric; low-rate mote radios (MICA2 maximum "12.364kbps"); jammer and source powers given as transmit powers. — [Xu 2005](<L/A02_Xu2005_Jamming_Attacks_Detection_MobiHoc.pdf>)

#### P04 Liu et al. 2018: CORE (for the decision layer); limited for severity
- Citation: see 1a (arXiv:1710.04830v1). — [Liu](https://arxiv.org/abs/1710.04830)
- What it evaluated: simulation of a DQN on a 200×200 spectrum waterfall against sweep, comb, random and intelligent jammers. — [Liu](https://arxiv.org/abs/1710.04830)
- Project uses:
  - 30 dB in-band cap: **backed as a single simulated value**, not a measurement.
  - Waterfall state, switching cost, combined actions: backed (Sec. II-III).
  - "Comb = every usable channel": **not backed**.
  - — [Liu](https://arxiv.org/abs/1710.04830)
- Not yet used: the 10 dB demodulation threshold as the success criterion; the uniform-action result against the intelligent jammer (Fig. 7). — [Liu](https://arxiv.org/abs/1710.04830)
- Quality flags: 4-page arXiv letter; no confidence intervals; journal version UNVERIFIED. — [Liu](https://arxiv.org/abs/1710.04830)

#### W11 / V7 Whitehouse et al. 2005: SUPPORTING
- Citation: see 1b. — [Whitehouse](<_extracts_threat/dl/whitehouse.pdf>)
- What it measured: capture-based collision detection and recovery on Mica2 / CC1000 at 433 MHz. Three-node timing sweep (42 % detection, 92 % recovery). 36-node indoor flood (capture uncorrelated with distance). — [Whitehouse](<_extracts_threat/dl/whitehouse.pdf>)
- Project uses:
  - "0.2-3 dB advantage captures": **backed second-hand** (0.17 dB, 1-3 dB from refs [2], [26]).
  - "spoofer 30 dB": **not backed**.
  - — [Whitehouse Sec. 2](<_extracts_threat/dl/whitehouse.pdf>)
- Not yet used: stronger-first versus stronger-last behaviour; collision detection by searching for a second preamble during reception. — [Whitehouse Sec. 3](<_extracts_threat/dl/whitehouse.pdf>)
- Quality flags: workshop paper; non-coherent low-rate radio; thresholds not measured by the authors ("unobservable" with their ADC). — [Whitehouse](<_extracts_threat/dl/whitehouse.pdf>)

#### N12 Mekdad et al. 2024: SUPPORTING (threat existence), not a level source
- Citation: see 1b. — [Mekdad](https://arxiv.org/abs/2403.03858)
- What it demonstrated: constant Gaussian-noise jamming and tone-plus-takeover hijacking of a Crazyflie 2.1 on 2481 MHz. Effects:
  - autonomous mode: "the Crazyflie drone crashes in the jamming and hijacking attack";
  - manual mode: "the drone holds the last command and remains in a suspended state".
  - — [Mekdad Sec. IV](https://arxiv.org/abs/2403.03858)
- Project uses:
  - CW jammer named: **backed**.
  - "the hijacker uses the jammer's radio": **not backed**; the hijacker used Crazyradio PA modules ("similar configuration as the GCS").
  - Any dB level: **not backed**; none is given.
  - — [Mekdad](https://arxiv.org/abs/2403.03858)
- Not yet used: the role of missing authentication; behavioural hijack detection (flight pattern, GPS, IMU-estimated position); safe mode. — [Mekdad Sec. V](https://arxiv.org/abs/2403.03858)
- Quality flags: arXiv; one device, one channel; qualitative outcome only. — [Mekdad](https://arxiv.org/abs/2403.03858)

#### W08 Wollenberg et al. 2012 (`2387238.2387289.pdf`): CORE for the WLAN model, with corrected attribution
- Citation: see 1c. — [Wollenberg](https://doi.org/10.1145/2387238.2387289)
- What it measured: occupancy-estimation accuracy (CO_total, CO_WLAN against the adapter's RXCLR counter) for three generated traffic cases, adjacent-channel separations 1-4, and a Bluetooth interferer at 0-63 % duty, all on a cabled test bed. — [Wollenberg](https://doi.org/10.1145/2387238.2387289)
- Project uses:
  - 0.27-3.2 ms: **backed as configured test-case frame lengths**.
  - 5-86 %: **backed by Wollenberg's lab cases A and B**, not by Cheema.
  - Levels: **not backed**.
  - Exponential gaps: **not in this paper** (fixed frame rates).
  - — [Wollenberg Table 2](https://doi.org/10.1145/2387238.2387289)
- Not yet used: the CO_total versus CO_WLAN split as a benign/other-interference discriminator; dynamic threshold; 13-27 s windows; "usually below 1 ms" OFDM frames. — [Wollenberg](https://doi.org/10.1145/2387238.2387289)
- Quality flags: 4-page short paper; generated traffic; cabled; one chipset family (Atheros 5212). — [Wollenberg](https://doi.org/10.1145/2387238.2387289)

#### W09 Cheema & Salous 2019: CORE for the WLAN model, with corrected attribution
- Citation: see 1c. — [Cheema](https://doi.org/10.3390/electronics8091011)
- What it measured: one 20-minute indoor capture (omni-directional, plus 3 directional antennas) of 2.4-2.5 GHz at 204.8 µs resolution. Duty cycles and idle-time-window distribution fits. — [Cheema](https://doi.org/10.3390/electronics8091011)
- Project uses:
  - "5-86 % (Cheema & Salous)": **only about 4.6-13 % is backed**.
  - Exponential idle gaps: **contradicted** (EX worst KS at 204.8 µs).
  - Levels: **not backed**.
  - — [Cheema p. 6, 8-12](https://doi.org/10.3390/electronics8091011)
- Not yet used: gamma (k = 0.4898, mean 36.16 ms for channel 1) or lognormal idle times; 100 ms beacon periodicity; time-resolution and direction effects on detecting short packets. — [Cheema](https://doi.org/10.3390/electronics8091011)
- Quality flags: single 20-minute indoor session; low traffic; MDPI open access. — [Cheema](https://doi.org/10.3390/electronics8091011)

#### N03 Barajas et al. 2026: SUPPORTING
- Citation in the file: L. Barajas, C. Jeardoe, J. Kim, E. Hammad (Texas A&M), "Resilient Control Loops in Autonomous Vehicles Under Adversarial Jamming via Spectral Perception and Network-Layer Failover", arXiv:2609.05739v1, 4 Sep 2026. — [Barajas](https://arxiv.org/abs/2609.05739)
- What it measured: CW jamming of a TurtleBot3 ROS 2 Wi-Fi link (2.447 / 5.200 GHz, 5.0 s emissions); detection latency (~0.6 s); recovery times; path-tracking error. — [Barajas](https://arxiv.org/abs/2609.05739)
- Project uses:
  - recovery 0.14-2.6 s: **backed** (6.0 s baseline omitted);
  - m-of-n confirmation: **backed**;
  - jammer list: **second-hand** (Li et al. [14]).
  - — [Barajas](https://arxiv.org/abs/2609.05739)
- Not yet used: the five spectral descriptors including spectral entropy and occupancy; the band-specific thresholds; the >20 dB RMS step as an observed jammer signature. — [Barajas](https://arxiv.org/abs/2609.05739)
- Quality flags:
  - very recent, non-peer-reviewed preprint;
  - the extracted text contains a leftover drafting tag "[cite: 198]" in Sec. V-B;
  - no false-alarm or accuracy numbers;
  - jammer power given only as a radio gain setting, with no distance or received SIR.
  - — [Barajas Sec. V-B](https://arxiv.org/abs/2609.05739)

#### F04 Nanayakkara et al. 2025: MARGINAL
- Citation in the file: S. Nanayakkara, S. Sumathipala, N. Karunanayake, M. Karunanayake, T. Kumara, "Smart Drone Neutralization: AI Driven RF Jamming and Modulation Detection with Software Defined Radio", doi:10.70322/dav.2025.10019 (received 22 June 2025, available online 30 October 2025). — [Nanayakkara](https://doi.org/10.70322/dav.2025.10019)
- What it evaluated: counter-drone (offensive) spectrogram detection of four 2.4 GHz RC transmitters at 5-40 m, followed by replay-type neutralisation. — [Nanayakkara](https://doi.org/10.70322/dav.2025.10019)
- The project uses nothing numeric. Detection accuracies are 98 / 69 / 48 % by model. No received JSR or defensive content. — [Nanayakkara](https://doi.org/10.70322/dav.2025.10019)
- Quality flags: offensive framing; small dataset (1600 samples). — [Nanayakkara](https://doi.org/10.70322/dav.2025.10019)

#### P13 Dixit et al. 2026: MARGINAL (protocol-level authentication only)
- Citation in the file: B. Dixit, A. Rajgor, S. Kumar, R. Patil, Ananthapadmanabhan A., G. S. Kasbekar, A. Maity, "Design and Performance Evaluation of Secure RF and WiFi-Based Communication in Drone Swarms via Testbed Implementation", arXiv:2606.27028v1, 25 Jun 2026. — [Dixit](https://arxiv.org/abs/2606.27028)
- What it measured: CPU, RAM and PDR of five ciphers on a 4-UAV swarm over 915-928 MHz RF and Wi-Fi. No jamming or interference measurement. — [Dixit](https://arxiv.org/abs/2606.27028)
- Project use (ranking file: PDR on CRC-passed packets) is consistent with the text: packets are accepted after "successful verification of both the checksum and the digital signature". — [Dixit Sec. III](https://arxiv.org/abs/2606.27028)
- Not yet used: message signing and source-ID filtering as the published defence against counterfeit commands. — [Dixit](https://arxiv.org/abs/2606.27028)
- Quality flags: arXiv; the PDR definition gives values above 100 % ("unencrypted communication achieves the highest PDR (102.52%)"); Wi-Fi mesh PDR is only about 22.7 %. — [Dixit Sec. VII](https://arxiv.org/abs/2606.27028)

#### S_04 Yu et al. 2025: MARGINAL
- Citation in the file: A. Yu, I. Kolotylo, H. A. Hashim, A. E. E. Eltoukhy, "Electronic Warfare Cyberattacks, Countermeasures and Modern Defensive Strategies of UAV Avionics: A Survey", arXiv:2504.07358v1, 10 Apr 2025. — [Yu](https://arxiv.org/abs/2504.07358)
- What it offers:
  - a qualitative taxonomy, for example "Random and Periodic Jamming Attacks - An attacker sends jamming signals for random periods of time and then remains idle for the rest of the time";
  - FH, FHSS and DSSS countermeasures;
  - neighbour comparison of traffic parameters for detection.
  - — [Yu](https://arxiv.org/abs/2504.07358)
- No numbers. It does not back any project level. — [Yu](https://arxiv.org/abs/2504.07358)

#### V7 Shahriar et al. 2015 tutorial (COMST 17(1):292-314): CORE for v7 receiver defences
- Citation printed in the file: C. Shahriar, M. La Pan, M. Lichtman, T. C. Clancy, R. McGwier, R. Tandon, S. Sodagari, J. H. Reed, "PHY-Layer Resiliency in OFDM Communications: A Tutorial", IEEE Commun. Surveys & Tutorials 17(1), First Quarter 2015, pp. 292-314. — [Shahriar tutorial](https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf)
- What it evaluated: simulations of barrage, partial-band, synchronisation (false preamble, nulling, warping, phase warping, differential scrambling), pilot jamming and nulling, and control-channel attacks; pilot-randomisation BER results (Figs. 14-15). — [Shahriar tutorial](https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf)
- No project number currently relies on it. Defensive content not yet used: see 3a, 3b and Section 2 (control-channel energy monitoring). — [Shahriar tutorial](https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf)
- Quality flags: simulation only; OFDM/LTE context rather than single-carrier QPSK; the jammer is assumed to know the channel perfectly in Sec. X-H. — [Shahriar tutorial p. 307](https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf)

#### V7 Shahriar PhD 2015: SUPPORTING (duplicates and extends the tutorial)
- Citation printed in the file: C. M. R. Shahriar, "Resilient Waveform Design for OFDM-MIMO Communication Systems", PhD dissertation, Virginia Tech, September 11, 2015 (chair T. C. Clancy). — [Shahriar PhD](<_extracts_threat/dl/shahriar_phd.pdf>)
- Adds the numbers quoted in 3a:
  - pilot jamming and nulling need 4 dB and 12 dB less power than barrage;
  - Fig. 5.4 randomisation BERs at 5 dB SNR;
  - MIMO: "channel sounding signal jamming outperforms barrage jamming by 1 dB and singularity attack outperforms barrage jamming by 3 dB at 0.3 BER".
  - — [Shahriar PhD Ch. 1, 4-5](<_extracts_threat/dl/shahriar_phd.pdf>)
- Quality flags: simulation; its numbers differ from the tutorial's because conditions differ. — [Shahriar PhD](<_extracts_threat/dl/shahriar_phd.pdf>)

#### V7 Rao MS 2016: SUPPORTING
- Citation printed in the file: R. M. Rao, "Perspectives of Jamming, Mitigation and Pattern Adaptation of OFDM Pilot Signals for the Evolution of Wireless Networks", MS thesis, Virginia Tech, September 15, 2016 (chair J. H. Reed). — [Rao](<_extracts_threat/dl/rao_thesis.pdf>)
- What it measured or evaluated: simulated multi-tone pilot jamming and mitigation (RE blanking with cancellation; cyclic pilot shift); an experimental LTE CRS-jamming testbed (USRP B210); CQI spoofing. — [Rao](<_extracts_threat/dl/rao_thesis.pdf>)
- Not yet used: coordinated pilot shifting (with its measured benefit); the critique of random pilots; the threat that quality estimates can be biased by interference that avoids pilots. — [Rao](<_extracts_threat/dl/rao_thesis.pdf>)
- Quality flags: MS thesis; LTE downlink context. — [Rao](<_extracts_threat/dl/rao_thesis.pdf>)

#### V7 Noubir et al. 2011: CORE (detection principle and secret-position idea)
- Citation printed in the file: G. Noubir, R. Rajaraman, B. Sheng, B. Thapa, "On the Robustness of IEEE802.11 Rate Adaptation Algorithms against Smart Jamming", ACM WiSec'11, June 14-17, 2011, Hamburg. Page range 97-108 is UNVERIFIED (taken from earlier note 16, not printed in this extraction). — [Noubir](https://www.cs.umb.edu/~shengbo/paper/wisec11.pdf)
- What it measured: smart (reactive) jamming of SampleRate, ONOE, AMRR and the Windows RAA on a cabled USRP / GNU Radio testbed. — [Noubir Sec. 6](https://www.cs.umb.edu/~shengbo/paper/wisec11.pdf)
- Not yet used: the secret-position interruption or training sequence; randomised probing; protection of rate information. All are unevaluated. — [Noubir Sec. 7](https://www.cs.umb.edu/~shengbo/paper/wisec11.pdf)
- Quality flags: the 802.11 bandwidth was reduced to 5 MHz in the testbed "to make the data packet transmission four times longer" (USRP limitation); cabled. — [Noubir Sec. 6](https://www.cs.umb.edu/~shengbo/paper/wisec11.pdf)

#### V7 Ogawa et al. 1983: SUPPORTING (concept only)
- Citation: see 3c. — [Ogawa](https://hdl.handle.net/2115/5972)
- What it derived: an analytic upper bound on the loop gain of a power-inversion array so that the desired signal is not suppressed when no interferer is present. — [Ogawa](https://hdl.handle.net/2115/5972)
- Not yet used: the desired-signal-suppression trade-off for reference-free nulling. — [Ogawa](https://hdl.handle.net/2115/5972)
- Quality flags: three-page correspondence; poor OCR; no interference-suppression results. — [Ogawa](https://hdl.handle.net/2115/5972)

#### V7 Pirayesh & Zeng survey: CORE as a map of defences (second-hand content)
- Citation in the file: H. Pirayesh, H. Zeng, "Jamming Attacks and Anti-Jamming Strategies in Wireless Networks: A Comprehensive Survey", arXiv:2101.00292v1, 1 Jan 2021 (`dl/pirayesh_arxiv.txt`). The scratchpad copy W07b is a later revision with **different reference numbering**. In arXiv v1, [53] is La Pan WCMC and [58] is Shahriar ICC 2012. In W07b, [53] is La Pan MILCOM 2012 and [58] is Clancy ICC 2011. The COMST 2022 journal details are UNVERIFIED. — [Pirayesh arXiv](https://arxiv.org/abs/2101.00292)
- Project use ("detection on unused pilots"): **partly backed**. The survey describes unused pilots used to estimate the jammer channel for spatial filtering. — [Pirayesh Sec. III](https://arxiv.org/abs/2101.00292)
- Not yet used: MCR silent-period estimation; spatial projection before synchronisation (20 dB); Puñal / Arjoune feature sets and accuracies; Navda channel hopping (80 % loss, 60 % restored). — [Pirayesh](https://arxiv.org/abs/2101.00292)
- Quality flags:
  - survey: all numbers are from cited works, not read here;
  - an extraction or typo in the closing discussion reads "MIMO-based jamming mitigation is not effective in jamming mitigation but also efficient in spectrum utilization". It is probably "not only effective"; the meaning was not checked against the PDF.
  - — [Pirayesh closing discussion](https://arxiv.org/abs/2101.00292)

#### V7 La Pan et al. WCMC 2016 and La Pan PhD 2014: CORE for secret preamble / CAF / sync-amble
- WCMC citation printed in the file: M. J. La Pan, T. C. Clancy, R. W. McGwier, "Physical layer orthogonal frequency-division multiplexing acquisition and timing synchronization security", Wirel. Commun. Mob. Comput. 2016; 16:177-191, DOI 10.1002/wcm.2500 (published online 18 Aug 2014). — [La Pan WCMC](https://doi.org/10.1002/wcm.2500)
- Thesis citation printed in the file: M. J. La Pan, "Security Issues for Modern Communications Systems: Fundamental Electronic Warfare Tactics for 4G Systems and Beyond", PhD dissertation, Virginia Tech, October 27, 2014 (chair T. C. Clancy). — [La Pan thesis](<_extracts_threat/dl/lapan_thesis.pdf>)
- What they evaluated (simulation): four timing attacks, two frequency attacks, the CAF synchroniser, and the proposed sync-amble randomisation. Results are in 3b. — [La Pan WCMC](https://doi.org/10.1002/wcm.2500); [La Pan thesis](<_extracts_threat/dl/lapan_thesis.pdf>)
- Quality flags: simulation only; numeric CAF benefits are in figures only; same research group as Shahriar. — [La Pan thesis](<_extracts_threat/dl/lapan_thesis.pdf>)

#### Summary table

| Source | Verdict | What it backs | Issues found |
|---|---|---|---|
| Xu 2005 (A02) | CORE | Jammer taxonomy; reactive definition; PDR versus signal-strength consistency (jammed region PDR < 65 %, SS above 99 % band) | No accuracy metric; low-rate mote radios; transmit (not received) powers |
| Liu 2018 (P04) | CORE (decision layer) | One simulated point: 30 dBm jammer against 0 dBm signal, both 4 MHz; waterfall state; switching cost | Simulation, not measurement; D70 "comb = every channel" contradicts Liu (3 tones; throughput about 1); journal version UNVERIFIED |
| Whitehouse 2005 | SUPPORTING | Capture with a small advantage: "1-3dB" or "0.17dB" (second-hand) | Gives no upper level, so 30 dB spoofer not backed; project rounds 0.17 to 0.2; arrival order (stronger-last loses both) not used |
| Mekdad 2024 (N12) | SUPPORTING | 2.4 GHz drone link broken by noise and by a single tone; takeover without authentication | No dB anywhere; hijacker used Crazyradio PA (GCS-class), not the jammer's HackRF, so D72 wording not backed |
| Wollenberg 2012 | CORE (WLAN) | Frame lengths 3.2 ms and 268 µs; occupancy 5.0 % and 85.6 % (lab cases A and B) | Lab-generated, cabled; 86 % is not from Cheema; no levels; 536/40 µs case C ignored |
| Cheema 2019 | CORE (WLAN) | Field duty cycle 4.6-11.5 % (omni), about 3-13 % (directional); gamma or lognormal idle times; 100 ms beacons | Does not back 86 %; contradicts exponential gaps (EX worst KS); no levels; one 20-minute indoor session |
| Barajas 2026 (N03) | SUPPORTING | Recovery 0.141 / 2.549 s (6.001 s static); 3-consecutive confirmation; spectral entropy and occupancy features | Preprint; "[cite: 198]" artefact; jammer list second-hand; no FA or accuracy; CW only |
| Nanayakkara 2025 (F04) | MARGINAL | Nothing the project relies on | Offensive framing; small dataset |
| Dixit 2026 (P13) | MARGINAL | PDR on checksum- and signature-verified packets; message signing | PDR above 100 % by definition; no RF threat data |
| Yu 2025 (S_04) | MARGINAL | Qualitative taxonomy | No numbers |
| Shahriar tutorial 2015 | CORE (v7) | Pilot and preamble attack effects; pilot randomisation BER trade-off; secret-keystream pilots; agreed preamble / CAF / location-hiding proposals | Simulation; jammer assumed to know the channel; OFDM context |
| Shahriar PhD 2015 | SUPPORTING | Pilot jam 4 dB and null 12 dB more efficient than barrage; randomisation BERs at 5 dB SNR | Numbers differ from tutorial (different SNR); simulation |
| Rao MS 2016 | SUPPORTING | Coordinated pilot shift restores MSE, BER order-of-magnitude better; CRS jamming 5 dB cheaper (testbed); CQI spoofing | MS thesis; LTE downlink |
| Noubir 2011 | CORE (principle) | Interference not told apart from poor link by RAAs; reactive jamming 100× more efficient; secret-position interruption idea | Mitigations unevaluated; cabled; 5 MHz bandwidth workaround |
| Ogawa 1983 | SUPPORTING | Reference-free power inversion nulls any strong signal, including the desired one; loop-gain bound | No suppression figures; poor OCR |
| Pirayesh survey | CORE (map) | Silent-period jammer-channel estimation (MCR); spatial projection before sync (20 dB); detection feature sets (98.4 / 94.3 / 95.7 %) | Second-hand; reference numbers differ between versions; "unused pilots" is estimation, not detection |
| La Pan WCMC 2016 + PhD 2014 | CORE (v7) | False preamble wins if stronger; CAF comparable without a jammer, better at SJR ≤ 0 dB (figures only); secret sync-amble (proposed) | Simulation; CAF needs a known symbol (new vulnerability); sync-amble unevaluated |

#### COULD NOT DOWNLOAD (and what covers them)
- **T. C. Clancy, "Efficient OFDM denial: Pilot jamming and pilot nulling", IEEE ICC 2011.** Not obtained. Coverage:
  - Shahriar tutorial Sec. X-A/X-B (pilot jamming and nulling formulation, pp. 304-306);
  - Shahriar PhD Ch. 4 (pilot jam 4 dB and null 12 dB less power than barrage at 0.3 BER);
  - Rao's citation of "Clancy [7, 8]" as the source of pilot-tone randomisation.
  - Whether ICC 2011 itself reports randomisation results is UNVERIFIED.
  - — [Shahriar tutorial](https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf); [Rao Sec. 3.1](<_extracts_threat/dl/rao_thesis.pdf>)
- **M. La Pan, T. C. Clancy, R. W. McGwier, "Jamming attacks against OFDM timing synchronization and signal acquisition", MILCOM 2012.** Not obtained. Covered by WCMC 2016 ("Portions of this paper were published in the IEEE Military Communications Conference (MILCOM), October 2012") and by thesis Ch. 3 (cited there as [38]). — [La Pan WCMC p. 177](https://doi.org/10.1002/wcm.2500); [La Pan thesis](<_extracts_threat/dl/lapan_thesis.pdf>)
- **M. La Pan, T. C. Clancy, R. W. McGwier, "Phase warping and differential scrambling attacks against OFDM frequency synchronization", ICASSP 2013.** Not obtained. Covered by thesis Ch. 3 (phase warping and differential scrambling simulations, pp. ~56-59, cited as [42]) and Shahriar tutorial Sec. IX-D/E, Fig. 11. — [La Pan thesis](<_extracts_threat/dl/lapan_thesis.pdf>); [Shahriar tutorial p. 303](https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf)
- **M. La Pan, M. Lichtman, T. C. Clancy, R. W. McGwier, "Protecting physical layer synchronization: mitigating attacks against OFDM acquisition", WPMC 2013.**
  - Not obtained. Covered by WCMC 2016 Sec. 6 ("others were published in the 16th international IEEE Wireless Personal Media Communications (WPMC) Conference, June 2013") and thesis Ch. 4 (CAF, sync-amble; cited as [43]).
  - The thesis reference lists the WPMC authors as "M. La Pan, T. C. Clancy, and R. W. McGwier" ("----" ditto), without Lichtman. The author list is therefore UNVERIFIED.
  - — [La Pan WCMC p. 177, 188-189](https://doi.org/10.1002/wcm.2500); [La Pan thesis bibliography](<_extracts_threat/dl/lapan_thesis.pdf>)

### Inferences
- Of the four sources the project cites for severity caps, only Liu supplies the number used, and only as a simulated value. Whitehouse and Mekdad support the *existence and ease* of counterfeit commands, not a 30 dB level. Wollenberg (a lab) rather than Cheema (the field) supplies the 86 %.
- The v7 defences listed in the project context each have at least one source in this set:
  - secret or randomised pilot placement: Shahriar, Rao;
  - secret preamble / CAF: Shahriar, La Pan;
  - randomised quiet-slot position: Noubir (proposal), La Pan sync-amble (proposal);
  - spatial whitening before synchronisation: Zeng via Pirayesh; Ogawa for the concept and its trade-off.
  - Only pilot randomisation and pilot shifting have quantitative results, and those are simulations.

### Gaps
- No source in this set measures a counterfeit-signal SIR, a WLAN-to-desired-signal level, or a benign-WLAN detection score.
- Venue and pages are UNVERIFIED for Whitehouse 2005 and Xu 2005, and the journal versions of Liu 2018 and Pirayesh are also UNVERIFIED.
- Four Clancy / La Pan conference papers were not obtained. Their content is covered only through the WCMC paper, the two theses and the tutorial.
