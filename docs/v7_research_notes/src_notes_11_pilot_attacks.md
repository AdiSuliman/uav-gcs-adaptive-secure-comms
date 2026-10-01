# Source notes 11: pilot jamming / pilot nulling and defences
(research only, no decisions; fork session cdaee0, 2026-10-01)

## Reference numbering in Pirayesh (W07b), checked against its reference list
- [29] Shahriar et al., "PHY-layer resiliency in OFDM communications: A tutorial", IEEE COMST 2015 (read, below).
- [53] La Pan, Clancy, McGwier, "Jamming attacks against OFDM timing synchronization and signal acquisition", MILCOM 2012.
- [58] T. C. Clancy, "Efficient OFDM denial: Pilot jamming and pilot nulling", IEEE ICC 2011, pp. 1-5 (not open).
- [59] Shahriar, Sodagari, Clancy, "Performance of pilot jamming on MIMO channels with imperfect synchronization", ICC 2012.
- [60] Sodagari, Clancy, "Efficient jamming attacks on MIMO channels", ICC 2012; [61] Sodagari, Clancy, "On singularity
  attacks in MIMO channels", Trans. Emerging Telecom. Tech. 26(3), 2015. Pirayesh text: "In [60] and [61], Sodagari et al.
  studied pilot jamming attack in MIMO-OFDM" / "proposed the singularity of jamming". NOTE: [60],[61] are MIMO pilot /
  singularity attacks, not rate-adaptation attacks; Pirayesh's rate-adaptation refs are [66]-[68] (see notes 16).
- Pirayesh Table III strengths/weaknesses column (column alignment in the text extraction is ambiguous):
  "Pilot jamming attack - Energy-efficient - Tight timing synchronization required"; "Pilot nulling attack - High
  effective - Applies to 802.11ac/ax and beyond" (alignment to be checked against the PDF).

## Shahriar et al. 2015 (read) - https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf
- Pilot jamming: "the adversary transmits AWGN signals only on the pilot tone's, in an attempt to raise the pilot tone's
  noise floor and thus disrupt the equalization process. It can be shown that pilot tone jamming is more power efficient
  than barrage jamming." ... "Thus it is beneficial to coherently jam pilot tones."
- Pilot nulling: "Pilot nulling has more severe consequence on the equalizer than pilot jamming. ... The goal is for H^
  to be asymptotically close to zero" ... "While pilot nulling can certainly be effective, it should be noted that
  obtaining accurate channel information is an extremely difficult task which adds much complexity to the jammer."
- Defence (Sec. X-G): "The pilot nulling attacks can be avoided by transmitting pilot tones whose values are unknown to
  the attackers. In the absence of knowledge about pilot tone values, pilot nulling becomes as effective as pilot
  jamming that can be avoided by randomizing the pilot locations."
- "Pseudorandom Keystream: The randomization of pilots should be done in such a way that only the legitimate users know
  the locations in advance, but the attackers do not. ... a pseudorandom keystream generator to specify the locations of
  the pilot tones. This is seeded by a shared secret key known to members of the network".
- Numbers (their simulation, QPSK OFDM): without jamming the random-location scheme needs 5 dB SNR (at their BER
  reference); "In the presence of pilot jamming, at 0.2 BER confined bin scheme requires 5 dB SNR, and completely random
  scheme requires 10 dB SNR." Fig. 15 (SNR 10 dB): "At 0 dB JSR, the deterministic scheme's BER is 0.4, confined bin's
  BER 0.15, and random scheme's BER is 0.25. It can be seen that at high JSR, confined bin performs best."
- Control-channel mitigation: "randomizing the locations of control channels in both time and frequency, and passing
  the location information to the user using a shared key."
