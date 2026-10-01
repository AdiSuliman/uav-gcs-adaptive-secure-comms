# Source notes 16: attacks on rate adaptation
(research only, no decisions; fork session cdaee0, 2026-10-01)

NOTE: in Pirayesh's reference list the rate-adaptation papers are [66]-[68]; [60],[61] are Sodagari & Clancy MIMO
pilot/singularity attacks (see notes 11).

## Pirayesh text (W07b)
- "RAAs change the transmission MCS based on the statistical information of the successful and failed decoded packets.
  The Automatic Rate Fallback (ARF) [70], SampleRate [71], and ONOE [72] are the main RAAs using in commercial Wi-Fi."
- "In [66], Noubir et al. investigated the RAAs' vulnerabilities against periodic jamming attacks. In [67] and [68],
  Orakcal et al. evaluated the performance of ARF and SampleRate RAAs under reactive jamming attacks. The simulation
  results showed that, in order to keep the throughput below a certain threshold in Wi-Fi point-to-point
  communications, higher RoJ is required in ARF RAA compared to the SampleRate RAA, where the RoJ is defined as the ratio
  of the number of jammed packets to the total number of transmitted packets. This reveals that SampleRate RAA is more
  vulnerable to jamming attacks."
- Refs: [66] G. Noubir, R. Rajaraman, B. Sheng, B. Thapa, ACM WiSec 2011, 97-108; [67] C. Orakcal, D. Starobinski,
  CROWNCOM 2012; [68] C. Orakcal, D. Starobinski, "Jamming-resistant rate adaptation in Wi-Fi networks", Performance
  Evaluation 75, 50-68, 2014.

## Noubir et al. 2011 (read, abstract) - https://www.cs.umb.edu/~shengbo/paper/wisec11.pdf
"On the Robustness of IEEE802.11 Rate Adaptation Algorithms against Smart Jamming", ACM WiSec 2011 (best paper).
- "show the existence of very efficient attacks that exploit RAA-specific vulnerabilities as well as the inherent
  weaknesses ... in particular the overt packet rate information being transmitted, predictable rate selection
  mechanism, performance anomaly ..., and the lack of interference differentiation from poor link quality".
- "these smart jamming attacks ... can be orders of magnitude more efficient than naive jamming. For example, in the case
  of SampleRate, eight reactive jamming pulses every second are sufficient to achieve the same network throughput
  degradation achieved by a periodic jammer with the jamming energy cost 100 times higher."
- "ONOE in particular suffers from the phenomenon of congestion collapse where the nodes fail to recover from the lowest
  data rate even after the jammer stops jamming."
- "we summarize fundamental reasons behind such RAA vulnerabilities and propose a preliminary set of mitigation
  techniques. We leave the experimental demonstration of the efficiency of the proposed mitigation mechanisms for future
  work."
- Section 7, "Preliminary mitigation techniques" (read):
  - Goal: "severely limiting the amount of key information that can be inferred by an adversary. This lack of
    information then forces the adversary to operate as a memoryless jammer."
  - "Concealing explicit and implicit rate information: The rate information can be protected using post-coding
    encryption ... generating a cryptographic stream based on a shared secret key and a random initialization vector."
  - "Unpredictable rate selection rules: ... the popular SampleRate protocol can easily be protected through randomized
    probing. Instead of sending a probe every ten packets, the probing order should be randomized, furthermore the probed
    rates should not be sequential but randomly selected".
  - "Interference differentiation: ... Some mechanisms can be used to detect the presence of a reactive jammer. For
    example, interrupting the transmission for a short period of time within the packet (the location is
    cryptographically derived) or placing a training sequence at a cryptographic location within the packet allowing the
    receiver to detect if a jamming signal is present."  (same idea as a silent slot inside the frame, with a secret
    position against an adversary that learns the slot)
  - Section 3 weakness: "Radio receivers are incapable of differentiating between malicious interference (e.g.,
    jamming) and non-malicious interference such as direct collisions ..., hidden terminal problem, or noise from
    spatial reuse of channels. This gets even harder to do for moving nodes with dynamic link quality due to multi-path
    fading and environmental changes."
