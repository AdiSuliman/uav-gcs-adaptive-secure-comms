# Weak classes of the link-state detector: low-occupancy WLAN vs none, intermittent one-branch antenna/connector fault vs none, and the "none" class

Reading conventions for these notes:
- Text in quotation marks is verbatim from the PDF text layer (pdftotext) or, for patents, from the Google Patents full-text HTML. Symbols that pdftotext dropped (Greek letters, minus signs, mu) are restored in [square brackets]. Nothing else in the quotes was changed.
- "PDF p.N" is the page index in the PDF file I read (arXiv or author copy), not the proceedings page number.
- Local copies: every PDF cited here as "saved" was copied to `...\פרוייקט גמר\מקורות\` under the V7_ name given. No existing file was overwritten.
- UNVERIFIED means the claim comes only from a search snippet. I did not read the full text.
- These notes contain findings only. There are no design decisions.

## Q1. Detecting WLAN at low occupancy or partial overlap: energy detection with a known noise floor, 802.11 feature detection, occupancy estimation, sequential and M-of-N detection, and the partial-overlap limit

### Takeaway
No source quantifies Pd/Pfa as a function of WLAN *occupancy within a short observation window*. Three things in the literature come close:
- A closed-form analysis of energy detection when the signal switches on and off inside the sensing window. Detection degrades, and gains from SNR shrink.
- Empirical evidence that a burst only partially overlapping the observation window "do[es] not carry enough information for meaningful classification".
- Methods that recover robustness by working across many observations: occupancy estimation corrected for Pd/Pfa, CUSUM with delay ≈ |log α|/KL, and M-of-N binary integration.

Cyclostationary (cyclic prefix) feature detection of WLAN reaches >85 % classification at 0 dB SNR. However, it was demonstrated with wideband capture, not with a narrowband receiver that sees only part of the 20 MHz WLAN channel.

### Cited Findings

**Energy or burst detection against a known noise floor (COTS IoT receiver)**
- Grimaldi, Mahmood & Gidlund (arXiv 1809.10085v3; IEEE Access vol. 7, 2019), burst detection on an 802.15.4 radio, PDF p.3: "The on-board burst detection engine samples the RSSI register with frequency fs = 18.5 kHz, fetching 1 dB-resolution data". Also: "Signal bursts are separated from noise in real-time using a threshold-based criteria with threshold PT = [µ]N + 2[σ]N , where [µ]N and [σ]N mean and standard deviation of the AWGN noise due to the radio front-end, such that the probability noise-triggered bursts is minimized." And: "Note that [µ]N and [σ]N are device specific and usually provided by chip manufacturer, and can also be determined via a quick calibration process. Nevertheless, a conservative choice on PT only leads to a slight loss in detection sensitivity for low-INR bursts." — [Grimaldi et al. 2019, arXiv](https://arxiv.org/pdf/1809.10085) (saved as V7_Grimaldi2019_RealTime_Interference_Identification_IoT.pdf)
- Same paper, PDF p.9, on the sensitivity/accuracy trade-off: "The selection of the threshold therefore plays a significant role in the trade-off between the sensitivity and the accuracy of the IDI system. Intuitively, the bursts with lower INR reduce their separation in the feature space, and thus reduce the identification accuracy." The paper's Table IV (PDF p.8) reports per-class rates only "FOR BURSTS WITH INR [≥] 20 DB". — [Grimaldi et al. 2019](https://arxiv.org/pdf/1809.10085)

**Signal present for only part of the sensing window (closed-form energy-detector analysis)**
- Tang, Chen, Hines & Alouini (arXiv 1204.2428, 2012), abstract, PDF p.1: "Closed-form expressions for the probabilities of false alarm and detection are derived. Numerical results show that the multiple status changes of the primary user cause considerable degradation in the sensing performance. This degradation depends on the number of changes, the primary user traffic model, the primary user traffic intensity and the signal-to-noise ratio of the received signal." — [Tang et al. 2012](https://arxiv.org/pdf/1204.2428) (saved as V7_Tang2012_Sensing_Multiple_PU_Status_Changes.pdf)
- Same paper, PDF p.3, numerical setup of Fig. 1: "the sensing period [τ] is 20 ms, the received SNR is -5 dB, the exponential traffic model is applied with the mean busy holding time [λ1]^-1 = 5 ms and the mean idle holding time [λ2]^-1 = 5 ms." — [Tang et al. 2012](https://arxiv.org/pdf/1204.2428)
- Same paper, PDF p.3, Fig. 3, with the threshold set for Pd = 0.9: "the probability of false alarm increases when N increases, indicating a degradation in the spectrum sensing performance when PU traffic with multiple status changes is considered. Moreover, although for all values of N , the spectrum sensing performance improves with the increase of the received SNR, this improvement becomes much smaller when the status change of the primary user traffic is taken into consideration." — [Tang et al. 2012](https://arxiv.org/pdf/1204.2428)
- Same paper, PDF p.3, Fig. 2, on longer holding times (lower traffic intensity): "when [λ1] and [λ2] decreases, the channel mean holding time increases. The probability that the PU changes its status during the sensing period decreases. The sensing performance therefore is less affected by the PU traffic." — [Tang et al. 2012](https://arxiv.org/pdf/1204.2428)

**Empirical partial-overlap limit for classifying a WLAN-hit observation**
- Hermans, Rensfelt & Voigt, "SoNIC" (ACM IPSN 2013), PDF p.4: "While packets of 64, 96, and 124 bytes are correctly classified with an accuracy of 80%, 79% and 70% respectively, short packets have much lower classification accuracy. This is because short packets overlap only partially with the interferer's emission, and thus often do not carry enough information for meaningful classification. The accuracy does not significantly improve when we include short packets in the training set." — [Hermans et al. 2013](https://user.it.uu.se/~frehe489/publications/hermans13sonic.pdf) (saved as V7_Hermans2013_SoNIC_Classifying_Interference_802154.pdf)
- Same paper, PDF p.4: "the packet in Fig. 2e was partially overlapped by a WiFi transmission at 6 MBit/s. Due to the short overlap, little information is available for classifying such packets." — [Hermans et al. 2013](https://user.it.uu.se/~frehe489/publications/hermans13sonic.pdf)

**Estimating occupancy (duty cycle) from many busy/idle decisions with imperfect Pd/Pfa**
- López-Benítez & Lehtomäki (2016, Univ. of Liverpool repository postprint), PDF p.2, eq. (9): "A primary channel is observed as busy when it is busy and successfully detected as such, or when it is idle but observed as busy because of a false alarm. Hence: [Ψ̂] = P(H1)P(H1|H1) + P(H0)P(H1|H0) = [Ψ]Pd([λ]) + (1 − [Ψ])Pfa([λ])". Here Ψ is the real channel occupancy rate (COR), Ψ̂ the estimate, and λ the threshold. — [López-Benítez & Lehtomäki 2016](https://livrepository.liverpool.ac.uk/3004080/1/IWSS_2016.pdf) (saved as V7_LopezBenitez2016_Energy_Detection_Channel_Occupancy_Rate.pdf)
- Same paper, PDF p.3: "This result indicates that an exact estimation of the actual COR of a primary channel is feasible if the decision threshold is selected in such a way that the resulting probabilities of detection and false alarm ... satisfy the relation expressed in (12)." It adds that this "requires not only the SNR and noise power ... to be known but also the exact COR value itself", which it solves with an iterative algorithm. — [López-Benítez & Lehtomäki 2016](https://livrepository.liverpool.ac.uk/3004080/1/IWSS_2016.pdf)
- Same paper, PDF p.5, results: "both CFAR and CSDR fail to provide accurate COR estimations." Also: "the COR estimated by the proposed ACOR method shows a remarkable accuracy for the whole range of SNR values". And: "The accuracy of ACOR depends on the accuracy of the underlying SNR estimation method." — [López-Benítez & Lehtomäki 2016](https://livrepository.liverpool.ac.uk/3004080/1/IWSS_2016.pdf)

**Feature (cyclic prefix / cyclostationary) detection of WLAN**
- Hong & Katti, "DOF" (ACM SIGCOMM 2011), PDF p.1: "for most wireless protocols, there are hidden repeating patterns that are unique and necessary for their operation. For example, Wifi uses a repeating cyclic prefix to avoid intersymbol interference between consecutive OFDM symbols." — [Hong & Katti 2011](https://web.stanford.edu/~skatti/pubs/sigcomm11-dof.pdf) (saved as V7_Hong2011_DOF_Local_Wireless_Information_Plane.pdf)
- Same paper, PDF p.2: "DOF is accurate and robust at all SNRs, it classifies co-existing radio types with greater than 85% accuracy even at SNRs as low as 0dB. On the other hand, RFDump is at most 60% accurate at SNRs lower than 8dB." Also: "DOF's spectrum occupancy estimates are more than 85% accurate at low SNRs or in the presence of interference." — [Hong & Katti 2011](https://web.stanford.edu/~skatti/pubs/sigcomm11-dof.pdf)
- Same paper, PDF p.2, on the limits of energy and preamble methods: "energy detection is not accurate at medium to low SNR, and fails if there are multiple interfering signals". Also: "preamble correlation requires coarse synchronization to the carrier frequency of the detected signal". — [Hong & Katti 2011](https://web.stanford.edu/~skatti/pubs/sigcomm11-dof.pdf)
- Same paper, PDF p.7: DOF "computes the K = 80 feature vector components by averaging over 16 windows". It notes that "prior FFT based approaches ... also have to perform this averaging to smooth the FFT and avoid false positives." PDF p.9: "WiFi, ZigBee, and Bluetooth all have packet lengths on the order of 100's of [µ]s to a few ms". The receiver was wideband: "a wideband radio that is capable of operating over the entire 100 MHz ISM band and has 4 MIMO antennas" (PDF p.2). — [Hong & Katti 2011](https://web.stanford.edu/~skatti/pubs/sigcomm11-dof.pdf)
- Lundén, Koivunen, Huttunen & Poor (arXiv 0707.0909, 2007), multi-cycle cyclostationary detectors, PDF p.5. The test signal: "The OFDM signal has 32 subcarriers and the length of the cyclic prefix is 1/4 of the useful symbol data. The subcarrier modulation employed is 16-QAM. The signal length is 100 OFDM symbols." Results are given as figures: "performance of the detectors as a function of the SNR for a constant false alarm rate of 0.05". The Fig. 1 caption reads: "The multicycle detectors achieve better performance than the single cycle detector in the low SNR regime." The Pd values are in plots only and I did not extract them. — [Lundén et al. 2007](https://arxiv.org/pdf/0707.0909) (saved as V7_Lunden2007_Multiple_Cyclic_Frequencies_Sensing.pdf)

**Frame-clustering structure of WLAN traffic (secondary source)**
- Kidane & Dargie survey (arXiv 2501.06446, 2025), PDF p.8: "in IEEE 801.11a [sic] an idle duration of 16 us (inter-frame space) will be experienced between the transmission of a data packet and the reception of an ACK packet". Also: "Qin et al. [28] observe that WiFi frames are highly clustered and there are small idle leaks within the frame clusters and large white space between frame clusters." — [Kidane & Dargie 2025](https://arxiv.org/pdf/2501.06446) (saved as V7_Kidane2025_Cross_Technology_Interference_Survey.pdf)

**Sequential detection across cycles (CUSUM)**
- Xie, Zou, Xie & Veeravalli survey (already in the sources folder as V7_Xie2021_Sequential_Change_Detection_Survey_JSAIT.pdf; I read only the passage cited here), PDF p.4: "the CUSUM procedure with a threshold b = |log [α]| is first-order asymptotically optimum for both Lorden's and Pollak's formulations. In particular, as [α] → 0, CADD(C) = WADD(C) ∼ |log [α]| / D(f1||f0)". — [Xie et al. 2021, arXiv 2104.04186](https://arxiv.org/pdf/2104.04186)

**M-of-N (binary) integration over cycles**
- Norouzi, Greco & Nayebi, "Performance evaluation of k out of n detector" (EUSIPCO 2006), PDF p.1. This is the k-of-n problem for a burst with unknown time of arrival: "Another application is in ESM systems, when the system wants to detect the existence of a swept jammer or a gated noise jammer." PDF p.3: "the best choice for the problem is to select the highest value for the threshold ... and then searching for only a single 1 in the stream of zeros and ones. But it is true only if the probability distribution of both noise and signal are Rayleigh." — [Norouzi et al. 2006](https://new.eurasip.org/Proceedings/Eusipco/Eusipco2006/papers/1568980980.pdf) (saved as V7_Norouzi2006_K_out_of_N_Detector_EUSIPCO.pdf)
- MathWorks `binaryintloss` documentation. These quotes come from a WebFetch extraction, not from a PDF: "The number of detections, M in the M-of-N integration scheme, is set to M=0.955*N^0.8 ... This value is close to the optimal value that results in the binary integration loss lower than 1.5 dB for the number of pulses, N, in the range between [5,700]." The function "assumes that you are using a square-law detector and a nonfluctuating target." — [MathWorks binaryintloss](https://www.mathworks.com/help/radar/ref/binaryintloss.html)

**How a WLAN-aware sensor handles weak WLAN energy**
- Rayanchu, Patro & Banerjee, "Airshark" (ACM IMC 2011), PDF p.5. Airshark drops samples in which it decodes a WiFi packet: "One downside to this approach is that Airshark will also report spectral samples corresponding to weak 802.11 signals that fail carrier detection." — [Rayanchu et al. 2011](https://cs.uwaterloo.ca/~brecht/courses/856/readings/interference/airshark-detecting-non-wifi-interference.pdf) (saved as V7_Rayanchu2011_Airshark_NonWiFi_RF_Device_Detection.pdf)

### Inferences
- Mapping to the project's numbers (my arithmetic, not from a source): one 0.5 ms frame against WLAN packets of 0.27–3.2 ms means a WLAN-labelled frame can contain anything from a few µs to the full 0.5 ms of WLAN energy. Since no-overlap frames were relabelled "none", the remaining WLAN class still contains frames with very small overlap fractions. SoNIC (accuracy collapses for short, partially overlapped packets) and Tang et al. (degradation with in-window status changes, small gains from SNR) both describe this regime as intrinsically low-information per observation.
- The 32-symbol quiet slot (32 µs) is far shorter than a WLAN packet. At 5 % occupancy, a WLAN burst overlaps it in only a small share of cycles. This follows from duty-cycle reasoning plus the Kidane/Qin observation that WiFi frames are clustered in time; it is not a sourced number.
- The cross-cycle methods found (COR estimation corrected by Pd/Pfa, CUSUM, M-of-N) all turn a weak per-cycle statistic into a reliable decision by accumulating evidence. CUSUM delay scales as |log α| divided by the per-cycle KL divergence. That divergence shrinks when only a fraction of cycles contain WLAN energy, which implies that low-occupancy WLAN needs longer fusion windows for the same false-alarm rate.
- DOF and Lundén demonstrate CP feature detection with wideband capture and long windows: 16 averaged FFT windows in DOF, and 100 OFDM symbols in Lundén (about 400 µs if 802.11 symbol timing were used). Whether this survives in a receiver whose bandwidth covers only part of the 20 MHz WLAN channel is not shown in any source read.

### Gaps
- No source gives Pd/Pfa versus *WLAN channel occupancy* (5–86 %) or versus overlap fraction for a sub-millisecond window. Tang et al. give closed forms for the general on/off model, but at 1 ms sample spacing and a 20 ms window.
- No source quantifies 802.11 STF/LTF preamble correlation or CP autocorrelation detectability after narrowband filtering (about 1–2 MHz) of a 20 MHz OFDM signal. The LiU lecture and patents found by search were not read (UNVERIFIED snippet: "PF<<0.1 when PD≈0.9" for STF delay-and-correlate).
- The text of the IEEE 802.11 CCA clause could not be read: the standard needs an IEEE login or GET-program access, so it was not attempted.
- ZiFi (WiFi beacon detection from ZigBee RSSI using Common Multiple Folding + CFAR) is highly relevant for low duty cycle. Only snippets were available: "< 5% total FP and FN rate", "short delay (~780 ms)" — UNVERIFIED. No PDF could be fetched (see COULD NOT DOWNLOAD).

## Q2. Wi-Fi interference classification in other narrowband/IoT receivers: features and accuracies

### Takeaway
Narrowband 2.4 GHz receivers (802.15.4, commodity WiFi, SDR) separate WLAN from other emitters and from "no interference" or "weak link" using:
- burst length, mean power, crest factor and envelope ripple;
- RSSI range and shape within the packet;
- error-burst spacing;
- duty cycle and pulse timing;
- cyclostationary signatures.

Reported WLAN accuracies:

| Source | Setting | WLAN accuracy |
|---|---|---|
| Grimaldi et al. | Per burst, INR ≥ 20 dB | 89–96 % TPR |
| SoNIC | Per packet | About 60 % |
| SoNIC | With a 30 s voting window | 82 % |
| Schmidt et al. (CNN) | 12.8 µs snapshots, SNR > −5 dB | Above 95 % on average, but worst on 802.11 because 802.11 is clipped by the limited capture bandwidth |

The recurring confusion is WLAN vs "weak link / no interferer" at the edge of the interference zone, which is the same confusion seen in v6.

### Cited Findings

**CNN on short spectral snapshots (Schmidt, Block & Meier, arXiv 1703.00737, 2017)**
- PDF p.3: "The sensing snapshot is limited to a duration of 12.8 [µ]s and therefore consists of 128 IQ-Samples." The noise model: "additive white Gaussian noise in the SNR range of -20 dB until 20 dB with the step size of 2 dB". — [Schmidt et al. 2017](https://arxiv.org/pdf/1703.00737) (saved as V7_Schmidt2017_Wireless_Interference_Identification_CNN.pdf)
- PDF p.4: "For the IEEE-802.11 b/g channels the accuracy is the worst. The IEEE-802.11 b/g signals have the biggest channel width and the most different modulations and bit rates. Therefore they are the most complex signals for the investigated classification problem." — [Schmidt et al. 2017](https://arxiv.org/pdf/1703.00737)
- PDF p.6: "In average, the accuracy exceeds 95 % for SNRs greater than -5 dB. The performance drops with wideband signals which are clipped by the limited acquisition bandwidth such as IEEE 802.11 b/g compliant packet transmissions." — [Schmidt et al. 2017](https://arxiv.org/pdf/1703.00737)

**802.15.4 node classifying corrupted packets (SoNIC, IPSN 2013)**
- Feature set, Table 1, PDF p.4. The six features are: "LQI > 90", "range(RSSI)>2 dB", "Mean error burst spacing", "Error burst spanning", "Mean normalized RSSI", and "1 - mode(RSSInormed)". Rationale, PDF p.4: "packets that are corrupted due to a weak link usually have a low LQI because channel conditions are equally poor over the whole packet reception time." Also: "Packets that are corrupted due to interference often show distinct peaks in RSSI, whereas packets received on a weak link contain little variation in signal strength." And: "WiFi mandates strict inter-frame spacings. These constraints become visible in the error bursts." — [Hermans et al. 2013](https://user.it.uu.se/~frehe489/publications/hermans13sonic.pdf)
- Per-packet accuracy, PDF p.5: "Our approach performs best for Bluetooth interference and weak links. At around 60%, accuracy is slightly lower for WiFi- and microwave-interfered packets, but it is still vastly in excess of random chance (25%)." Classifier comparison, PDF p.6, Table 3 caption: "The decision tree achieves a mean classification accuracy of 72.8%, almost on par with more powerful support vector machines (76.4%)." — [Hermans et al. 2013](https://user.it.uu.se/~frehe489/publications/hermans13sonic.pdf)
- Deployed, with voting, PDF p.8: "WiFi interference is correctly declared 82% of the time, but 16.2% of the time, SoNIC attributes the packet loss to a weak link. This is in agreement with Fig. 7b, which shows that at the edges of the interference zone, WiFi interference is misclassified as a weak link. Note that if we defined heavy packet loss as PER above 50% (instead of 20%), SoNIC correctly detects WiFi interference 95% of the time." PDF p.9, Table 4 caption: "Overall, the correct interferer is detected 87.5% of the time." — [Hermans et al. 2013](https://user.it.uu.se/~frehe489/publications/hermans13sonic.pdf)

**Real-time burst identification on COTS 802.15.4 hardware (Grimaldi et al. 2019)**
- Features, PDF p.4: "Burst length: total sample length of the detected burst"; "Burst mean power: reflecting the mean envelope power extracted on the central frequency fc"; "Crest factor: indicating the maximum envelope variation, i.e., dynamic range of the signal envelope, as, FEc = max(y) - min(y)"; "Envelope ripple: representing a measure of the maximum power variation between two consecutive samples." The full set also includes side-channel spectral features and a CCA-mode-2 feature (eight in total). — [Grimaldi et al. 2019](https://arxiv.org/pdf/1809.10085)
- Accuracy, PDF p.7: "All the methods show good accuracy in identifying 802.11 interference, with average TPR of 89.20 % (CT1), 92.74 % (CT2), 94.60 % (MSVM) and 96.42 % (RFCT)." Real environments, Table V (PDF p.8): average 802.11 identification accuracy per location ranges from 84.88 % to 100 % for RFCT across the 4+4 positions (global 92.57 % and 99.14 % for the two environments). The related-work Table II lists the method's accuracy as "90 %-97 %". — [Grimaldi et al. 2019](https://arxiv.org/pdf/1809.10085)

**Commodity-WiFi spectral sensing of non-WiFi devices (Airshark, IMC 2011)**
- Features, PDF p.2, Table 1 caption: "Features used to detect the devices include: Pulse signature (duration, bandwidth, center frequency), Spectral signature, Timing signature, Duty cycle, Pulse spread and device specific features". Duty cycle, PDF p.7: "The duty cycle D of a device is the fraction of time the device spends in "active" state. ... due to the presence of multiple devices, it is possible for the duty cycle of the bandwidth (FFT bins) used by a device to be more than its expected duty cycle. We therefore use the notion of minimum duty cycle Dmin for devices". — [Rayanchu et al. 2011](https://cs.uwaterloo.ca/~brecht/courses/856/readings/interference/airshark-detecting-non-wifi-interference.pdf)
- Performance:
  - Single device, PDF p.10: "Airshark achieves an accuracy of 98% for RSSI values as low as [−]80 dBm."
  - Four devices at once, PDF p.11: "the average detection accuracy is more than 91% for RSSI values as low as [−]80 dBm."
  - False positives, PDF p.11: "even when using 4 RF devices, operating under a wide range of signal strengths, the average FPR was 0.39% (maximum observed FPR was 1.3%)."
  - Failure mode, PDF p.11: "For lower RSSI values, in the presence of multiple RF devices, we observed that features like spectral signatures, duty cycles do not perform well".
  - Under heavy WiFi load, PDF p.12: "Detection accuracy is reduced for pulsed transmission devices (e.g., ZigBee), whereas accuracy for frequency hoppers is minimally affected."

  — [Rayanchu et al. 2011](https://cs.uwaterloo.ca/~brecht/courses/856/readings/interference/airshark-detecting-non-wifi-interference.pdf)

**Survey framing of energy-statistics classification**
- Kidane & Dargie 2025, PDF p.7: energy detection "compares some statistical aspects of the power (such as mean, max, min, average, zero-crossing, etc.) with some existing patterns to determine CTI and its potential sources." — [Kidane & Dargie 2025](https://arxiv.org/pdf/2501.06446)

**UNVERIFIED (search snippets only, not read)**
- Multi-label CNN WII (arXiv 1804.04395): "For IEEE 802.11 b/g signals the accuracy increases for cross-technology interference with at least 90%" — [arXiv 1804.04395](https://arxiv.org/pdf/1804.04395).
- 15-channel BT/ZigBee/WiFi identification "around 89.5%" with CNN/ResNet/CLDNN/LSTM — [arXiv 1905.08054](https://arxiv.org/pdf/1905.08054).

### Inferences
- Two separate sources (SoNIC Table 4 and Fig. 7b; Grimaldi's INR-threshold analysis) show that WLAN-vs-benign confusion concentrates on low-INR, edge-of-zone observations. Reported "high" WLAN accuracies are conditional on an INR floor (Grimaldi Table IV: INR ≥ 20 dB) or on heavy packet loss (SoNIC: 95 % when PER > 50 %). The v6 WLAN F1 of 0.70 is measured over all overlap levels, so it is not directly comparable.
- The features that worked in these narrowband/RSSI-limited settings are envelope-shape statistics within the observation window: range, crest factor, ripple, mode-based shape, and timing of bursts or error bursts. A spectrogram CNN may capture these implicitly. Scalar summaries such as SINR or a quiet-slot I/N average them away.

### Gaps
- No source evaluates WLAN detection in a single-carrier QPSK receiver of about 1 MHz bandwidth with a short quiet slot. The closest analogues are 802.15.4 receivers (2 MHz channel) and Schmidt's 10 MHz snapshot.
- Grimaldi's per-INR accuracy curves (Fig. 11) and SoNIC's per-location results (Fig. 7) are in figures only. I did not extract numbers from the figures.

## Q3. Detecting an intermittent fault on one diversity branch: per-branch statistics, imbalance over time, periodicity, connector diagnostics, antenna-health monitoring

### Takeaway
Operational base-station practice monitors branch imbalance, either as the distribution of per-measurement branch differences (Ericsson) or as ΔRTWP between receive branches over a user-set period (Viavi). The core rule is that fading causes short-term differences while a fault causes a large and persistent one. Ericsson adds a diagnostic split by the mean and spread of that distribution.

For intermittent and vibration-driven faults the evidence is weaker. The sources say such faults are intermittent and short: arcs of about 250–500 µs; "PIM is often intermittent". Periodic attenuation (a rotor-blade analogue) is detected from "recurring decreases in the RSSI". No source found reports Pd/Pfa for detecting an intermittent single-branch attenuation.

### Cited Findings

**Ericsson, US 8,548,029 B2 "Monitoring of an antenna system"** (inventor Stefan Willgert; priority 2006-12-11; granted 2013-10-01). All quotes are from the Google Patents full text; column and line numbers were not available from that view.
- "A reason for a first antenna branch 120 to receive a weaker signal branch 305 than the other signal branch(es) of a radio base station 100 could be that the signal branch 305 received by the first antenna branch 120 has experienced more fading than the other signal branches." — [US8548029B2](https://patents.google.com/patent/US8548029B2/en) (saved as V7_Willgert2013_US8548029_Antenna_System_Monitoring.pdf; the PDF is a scanned image)
- Averaging: "Such pre-determined lime [sic] period could typically be in the order of minutes (e.g. 2 minutes), and a typical pre-determined number of samples could for example be in the order of 1000." Ratio test: "Typical values of the end values R min and R max of the interval within which the ratio R should lie could then e.g. be [0.5:2]." — [US8548029B2](https://patents.google.com/patent/US8548029B2/en)
- Distribution-based diagnosis: "If the antenna branches 120 operate ideally, the distribution of the difference between the measurement results should be centred around zero (the ratio should be centred around 1)." Also: "Problems with the antenna equipment or losses in the radio frequency path would give a ratio of the standard deviation and the absolute value of the difference that is smaller than would be obtained if there is an antenna diagram mismatch". Table 1 (SIR_rake difference between branches) gives these thresholds:

  | Condition | Table 1 threshold |
  |---|---|
  | Swapped feeder | std > 20 dB |
  | Losses in RF path | \|average\| > 3 dB with std/\|average\| < 3 dB |
  | Antenna diagram mismatch | \|average\| ≦ 3 dB with std/\|average\| > 3 dB |
  | None of the above | std ≦ 20 dB and \|average\| ≦ 3 dB |

  Per the patent, "The actual thresholds given in Table 1 are not to be seen as absolute numbers, but as a guidance". — [US8548029B2](https://patents.google.com/patent/US8548029B2/en)
- "By performing a per-measurement comparison, the differences in signal-to-noise-and-interference ratio values between signals originating from different radio transmitters experiencing different radio conditions can be compensated for." — [US8548029B2](https://patents.google.com/patent/US8548029B2/en)

**Viavi, US 10,404,368 B2 "Method and apparatus for the detection of distortion or corruption of cellular communication signals"** (inventors Heath et al.; priority 2016-01-18; granted 2019-09-03). Quotes are from the Google Patents full text.
- "Diversity antenna imbalance alarm, when the signal strength from the multiple receive antennas 10 is significantly different for a sustained amount of time." Also: "While fading can cause short term differences, if the difference is large and stays for a while, something else is causing the problem." And: "The most common causes are a failed antenna or connecting cable in one branch." And: "These can be outright failures, such as a broken cable, but are more commonly a subtler problem such as Passive Intermodulation Distortion." — [US10404368B2](https://patents.google.com/patent/US10404368B2/en) (saved as V7_Heath2019_US10404368_Diversity_Imbalance_Detection.pdf; the PDF is a scanned image)
- Detection rule: "Measures the difference in RTWP between MIMO receive branches of the antenna 10 for that sector, over a user-selectable period, and compares that to another user-defined threshold". Also: "Diversity Imbalance; which is when the ΔRTWP is greater than a set threshold." — [US10404368B2](https://patents.google.com/patent/US10404368B2/en)
- On intermittency: "PIM is often intermittent." Also: "Intermittent problems and false alarms are a significant problem in diagnosing problems in the RAN 6." The patent gives no numeric dB threshold or duration. — [US10404368B2](https://patents.google.com/patent/US10404368B2/en)

**Periodic attenuation detected from RSSI (rotor-blade analogue). Boeing, US 8,019,284 B2 "Helicopter rotor blade blockage blanking"** (inventor Anthony D. Monk; priority 2008-12-05; granted 2011-09-13). Quotes are from the Google Patents full text.
- "A received signal strength indicator (RSSI) of the received microwave signal is repeatedly sampled." Also: "A blockage cycle is determined based on recurring decreases in the RSSI indicative of blocked time periods when at least one of the plurality of helicopter rotors is blocking the communication line of sight path." — [US8019284B2](https://patents.google.com/patent/US8019284B2/en) (saved as V7_Monk2011_US8019284_Rotor_Blade_Blockage_Blanking.pdf)
- "The predetermined amount used to identify when the recurring obstruction blocks the communication line of sight path may be expressed as a proportion such that a drop in the RSSI by a certain fraction or percentage is identified by the blanking signal generator 370 as being caused by the recurring obstruction". No detection performance is reported. — [US8019284B2](https://patents.google.com/patent/US8019284B2/en)

**Intermittent, vibration-driven interconnect faults (aircraft wiring)**
- Smith, Furse & Kuhn, "Intermittent Fault Location on Live Electrical Wiring Systems" (SAE 2008, LiveWire Test Labs / Univ. of Utah), PDF p.2: "in very dynamic electrical environments such as aircraft, the vibration, turning on/off of electrical loads, and moisture ingress can cause faults to occur in flight that cannot be replicated on the ground." PDF p.4: "It can detect arcs on live wires that last 250 microseconds or more by continuously monitoring the test wire (most arc events last about 500 microseconds)." — [Smith et al. 2008](https://my.ece.utah.edu/~cfurse/Center%20of%20Excellence/wiring_papers/SAE2008%20revised.pdf) (saved as V7_Smith2008_Intermittent_Fault_Location_Live_Wiring_SAE.pdf)

**Faulty-antenna detection in arrays (massive MIMO), for model contrast**
- Zhang, Gan, Ling & Sun (arXiv 1709.06832, 2017), PDF p.2. The fault is modelled as additive sparse corruption, not attenuation: "the distortion caused by faulty antennas is denoted by an S-sparse vector wt ... The support of wt's indicates the indices of faulty antennas, which is assumed to be arbitrary and static for a relative long period. However, at different symbol times, the magnitude of the sparse vectors may vary arbitrarily." Detection error is the Hamming distance between the true and estimated fault-index vectors, and results are given in figures only. — [Zhang et al. 2017](https://arxiv.org/pdf/1709.06832) (saved as V7_Zhang2017_Faulty_Antenna_Detection_Massive_MIMO.pdf)

**UNVERIFIED (search snippets only)**
- Cranfield, "A Carrier Signal Approach for Intermittent Fault Detection and Health Monitoring for Electronics Interconnections System". Snippet: a "fixed frequency sinusoidal signal" injected into the interconnect is modulated by the intermittent fault, and the fault is extracted "by demodulation and spectrum analysis"; the intermittency was produced "by external vibration stress on connectors". — [Cranfield record](https://dspace.lib.cranfield.ac.uk/handle/1826/9812) (HTTP 403, not read)
- A generic per-antenna rule from a patent snippet: an antenna is flagged faulty if P_i > μ + α·σ of the array power statistics, with α between 2.0 and 3.0 — source patent not identified or read.

### Inferences
- The two operational patents share one discriminant: fading gives short, symmetric branch differences, while a fault gives large, persistent differences, judged over minutes (Ericsson: about 2 min, about 1000 samples). The project's fault is intermittent at a 86–672 Hz vibration rate, so it is neither persistent at the 20 ms cycle scale nor purely random. In Ericsson's terms it would show up as a branch-difference distribution with a heavy one-sided tail (a large std relative to |mean|), not as a shifted mean. This is my mapping, not a statement in the patent.
- Arithmetic from the given numbers: at 86–672 Hz, a 0.5 ms frame spans about 0.04–0.34 vibration periods. One 20 ms cycle contains about 1.7–13 periods, but only one 0.5 ms frame is observed. Once-per-cycle sampling of branch gain (50 Hz) is far below the vibration Nyquist rate, so the vibration frequency aliases. The rotor-blade patent's approach of finding a blockage cycle from recurring RSSI decreases assumes the RSSI is sampled densely relative to the blockage period. The in-frame dip and its time position are the only densely sampled view of the vibration.

### Gaps
- No source reports Pd/Pfa (or F1) for detecting an *intermittent* single-branch attenuation against Rayleigh/Rician fading. The patents give rules but no performance numbers.
- I did not read any source on aircraft or UAV diversity-receiver antenna-health monitoring. Aeronautical-telemetry best-source selection (IRIG 106 DQM, a per-source BER estimate) came up in search only (UNVERIFIED).
- I did not read any source giving the fading-only distribution of the instantaneous branch power ratio (e.g., for independent Rayleigh branches). That reference would quantify how often a 30 dB inter-branch difference occurs without a fault.
- I found no RF-specific study of periodicity detection (autocorrelation or FFT of branch gain) at vibration frequencies with reported performance. The Cranfield carrier-modulation paper is the closest, and it was not accessible.

## Q4. Improving the "no threat" class: one-class/novelty, calibrated rejection, temporal consistency

### Takeaway
RF open-set work shows that thresholding a CNN's output to reject or route uncertain inputs trades known-class accuracy for unknown-input rejection. For example, unknown inputs are detected at >95 % for SNR > 0 dB while known-class accuracy drops from 94.5 % to 86 %. Energy scores beat max-softmax for OOD (FPR95 down 18.03 % on CIFAR-10).

For temporal consistency, the deployed reference is SoNIC's majority vote over a 30 s window. SoNIC also discards low-evidence packets (fewer than 8 corrupted symbols, 13.8 % of the test set) and returns "unknown" when fewer than 5 packets are available. M-of-N and CUSUM give the formal Pd/Pfa or delay trade-offs.

### Cited Findings
- Shebert, Martone & Buehrer, "Open Set Wireless Standard Classification Using CNNs" (arXiv 2108.01656, 2021). PDF p.4, the rule: "compare to the threshold ... If none of the values are above the threshold, the signal is from an unknown class. Otherwise, the signal belongs to the class with the largest probability." PDF p.5: "The classifier plateaus at 94.5% overall accuracy for SNR values greater than 0 dB." Also: "The open set classifier is able to identify unknown classes with over 95% accuracy for SNRs greater than 0 dB. The cost of the enhanced capabilities of the open set classifier is a reduced 86% accuracy for known classes, almost 10% lower than the closed set case." The Fig. 5 caption: "Sigmoid threshold was set at 0.9999." — [Shebert et al. 2021](https://arxiv.org/pdf/2108.01656) (saved as V7_Shebert2021_Open_Set_Wireless_Standard_Classification.pdf)
- Same paper, PDF p.5, low-SNR behaviour: "very noisy signals are dissimilar to the signals used to train the classifier, so the probabilities at the output of the sigmoid function are lower on average. Therefore, both unknown and known signals should detected as unknown at a higher rate as the SNR drops." — [Shebert et al. 2021](https://arxiv.org/pdf/2108.01656)
- Liu et al., "Energy-based Out-of-distribution Detection" (NeurIPS 2020; already in the sources folder as V7_Liu2020_Energy_Based_OOD_Detection_NeurIPS.pdf; passage read): "on WideResNet, the energy score reduces the average FPR (at 95% TPR) by 18.03% on CIFAR-10 compared to using the softmax confidence score." — [Liu et al. 2020, arXiv 2010.03759](https://arxiv.org/abs/2010.03759)
- Hendrycks & Gimpel, MSP baseline (ICLR 2017; already in the sources folder as V7_Hendrycks2017_MSP_Baseline_Misclassified_OOD_ICLR.pdf; abstract read): "Correctly classified examples tend to have greater maximum softmax probabilities than erroneously classified and out-of-distribution examples, allowing for their detection." — [Hendrycks & Gimpel 2017, arXiv 1610.02136](https://arxiv.org/abs/1610.02136)
- Temporal voting with evidence gating, from SoNIC (IPSN 2013):
  - PDF p.5–6: "To tolerate such errors, we use a voting mechanism. The voter considers recently received, corrupted packets taken from a configurable time window. The most common class of packets in the window is indicated as the interference state to the application. In our experiments, we use a window length of 30 s, which we found to give a good trade-off between fast interference detection and high confidence in the voting result."
  - PDF p.6: "the voter discards packets with less than eight corrupted symbols that are classified as interfered. In the case of the testing set, 13.8% of the packets would be discarded after classification."
  - PDF p.8: "SoNIC returns the state unknown in case there is an insufficient number (< 5) of classified packets for voting."

  — [Hermans et al. 2013](https://user.it.uu.se/~frehe489/publications/hermans13sonic.pdf)
- A low false-positive reference for "no device present": Airshark, PDF p.11, "average FPR was 0.39% (maximum observed FPR was 1.3%)". Against the AirMaestro analyzer (PDF p.12): "We observed a total of 12 (0.07%) false positives and these instances occured when operating multiple RF devices at low signal strengths." — [Rayanchu et al. 2011](https://cs.uwaterloo.ca/~brecht/courses/856/readings/interference/airshark-detecting-non-wifi-interference.pdf)
- Formal temporal rules: CUSUM delay ∼ |log α|/D(f1‖f0) ([Xie et al. 2021](https://arxiv.org/pdf/2104.04186), PDF p.4). M-of-N with M = 0.955·N^0.8, giving less than 1.5 dB loss for N in [5,700] ([MathWorks](https://www.mathworks.com/help/radar/ref/binaryintloss.html)). For an unknown-arrival burst, a high threshold with a single required hit is best under Rayleigh noise and signal ([Norouzi et al. 2006](https://new.eurasip.org/Proceedings/Eusipco/Eusipco2006/papers/1568980980.pdf), PDF p.3).
- UNVERIFIED (snippet only), arXiv 2302.03749 (open-set wireless classification with expert features): "Increasing the unknown class detector threshold results in monotonically decreasing accuracy for known classes and monotonically increasing accuracy detecting unknown classes" — [arXiv 2302.03749](https://arxiv.org/pdf/2302.03749).

### Inferences
- The project's "none" class sits between two weak, low-evidence classes: low-occupancy WLAN and an intermittent fault in its off phase. The sources show two ways the literature handles low-evidence observations. One is to abstain or route them (SoNIC "unknown", discarding packets with fewer than 8 corrupted symbols; open-set thresholds). The other is to accumulate across time (voting, M-of-N, CUSUM). Both trade latency or coverage for precision. The reported trade-offs are about −10 % known-class accuracy for +95 % unknown rejection (Shebert), and a 30 s window with "unknown" when fewer than 5 items are available (SoNIC).
- Grimaldi's noise-calibrated threshold (μN + 2σN) and Airshark's FPR numbers suggest that when the noise floor is known (here the quiet slot), "none" false alarms can be pushed below 1 %. In both sources this comes at a stated loss of low-INR sensitivity.

### Gaps
- I found no RF-specific study that reports one-class or novelty training on the *benign/no-threat* class itself (rather than on unknown emitters) with numbers.
- I found no source that quantifies calibrated rejection specifically for a three-way none / weak-WLAN / intermittent-fault confusion.

### COULD NOT DOWNLOAD (all sections)
- R. Zhou, Y. Xiong, G. Xing, L. Sun, J. Ma, "ZiFi: Wireless LAN Discovery via ZigBee Interference Signatures," ACM MobiCom 2010. DOI not verified. Tried four author or lab URLs (msu.edu, cuhk.edu.hk); all returned HTML, not a PDF. Record: https://rims.cityu-dg.edu.cn/en/publications/zifi-exploiting-cross-technology-interference-signatures-for-wire/ ; ISCAS record: https://ir.iscas.ac.cn/handle/311060/8974
- "A Carrier Signal Approach for Intermittent Fault Detection and Health Monitoring for Electronics Interconnections System" (Cranfield University). DOI not found. https://dspace.lib.cranfield.ac.uk/handle/1826/9812 returned HTTP 403.
- Toma, López-Benítez, Patel, Umebayashi, "Primary Channel Duty Cycle Estimation Under Imperfect Spectrum Sensing Based on Mean Channel Periods," IEEE GLOBECOM 2019. DOI not verified. https://portalinvestigacion.nebrija.com/documentos/6207fe2ae81eae5f9eb09676 (no free PDF found; not attempted further).
- E. Axell, E. G. Larsson, "Optimal and Sub-Optimal Spectrum Sensing of OFDM Signals in Known and Unknown Noise Variance," IEEE JSAC 29(2):290–304, 2011. DOI not verified. No free copy located in the search.
- IEEE Std 802.11-2020, clause text for CCA (energy-detect and preamble-detect thresholds). Requires an IEEE login or GET-program access, so not attempted.
