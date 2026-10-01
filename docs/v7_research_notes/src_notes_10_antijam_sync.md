# Source notes 10: anti-jam synchronization (pre-acquisition nulling, robust preamble detection)
(research only, no decisions; fork session cdaee0, 2026-10-01)

## A. Power inversion = output-power minimization without a reference (read)
Y. Ogawa, M. Ohmiya, K. Itoh, "Upper Bound of a Loop Gain in a Power Inversion Adaptive Array", IEEE Trans. Aerospace
and Electronic Systems 19(5), 778-780, Sep 1983. Open: https://eprints.lib.hokudai.ac.jp/repo/huscap/all/5972/ITAES19-5.pdf
- "A power inversion adaptive array [1, 2] is useful in mobile communication systems because it does not require
  information about the desired signal arrival angle. A least mean squares (LMS) adaptive array [3, 4] uses a reference
  signal instead of arrival angle information: Consequently, the power inversion adaptive array is much easier to
  implement than the LMS adaptive array."
- "The power inversion adaptive array, however, works in such a way that it nulls any strong signal. Thus, if the
  desired signal is strong, it is suppressed. ... When an interference signal is not present, the signal suppression
  problem is most serious. The problem may be circumvented by decreasing the loop gain. However, since a lower value of
  the loop gain yields a poorer interference suppression performance, it is important to choose an appropriate value".
- [1] R. T. Compton, Jr., "The power-inversion adaptive array: Concept and performance", IEEE Trans. AES, AES-15(6),
  803-814, Nov 1979 (original, not read here).

## B. GNSS CRPA (trade article, read)
M. Jones, "Anti-jam technology: demystifying the CRPA", GPS World, 12 Apr 2017,
https://www.gpsworld.com/anti-jam-technology-demystifying-the-crpa/
- "the optimum weights can be found by taking the inverse of the data covariance matrix, and multiplying it by the
  vector of cross correlations between the primary and auxiliary antennas."
- "a CRPA is attractive, because it doesn't require you to make any changes to the GPS receiver itself: It simply
  replaces the existing antenna." (i.e. the nulling sits ahead of the unchanged receiver, so ahead of its acquisition).
- No dB numbers in the article.

## C. Jamming of OFDM timing acquisition and mitigations (read)
C. Shahriar, M. La Pan, M. Lichtman, T. C. Clancy, R. McGwier, R. Tandon, S. Sodagari, J. H. Reed, "PHY-Layer
Resiliency in OFDM Communications: A Tutorial", IEEE Commun. Surveys & Tutorials 17(1), 292-314, 2015.
Open PDF: https://uweb.engr.arizona.edu/~tandonr/journal-papers/Comm-Survey-2015.pdf  (this is Pirayesh ref [29])
- Fig. 8: "when the signal power for the false preamble is higher than the true preamble, the receiver will lock on to
  a timing point from the false plateau."
- Fig. 9: the Schmidl-Cox estimator "starts to be impacted by noise around -10 dB and is completely lost in the noise
  floor around -32 dB."
- "The preamble nulling attack is the most complex of these attacks, requiring exact preamble knowledge, channel
  estimation and extremely accurate signal generation. On the other hand, the false preamble attack only requires
  standards knowledge that dictates the structure of the preamble waveform."
- Fig. 10 (preamble warping): "most effective when it has equal power as the preamble at the receiver ... if the attack
  is sent at a much higher power than the original preamble, it actually can improve synchronization performance".
- Mitigation (Sec. IX-J): "have the transmitter and receiver agree on a specific preamble, or a set of preambles,
  beforehand to limit attacks against jammers that only have knowledge of the structure of the preamble symbols";
  "disguising the preamble"; "use the Cross Ambiguity Function (CAF) to perform the timing and frequency recovery ...
  this processing would not require any particular structure to the preamble-other than that it be a valid OFDM
  symbol. Instead, this method would require that the preamble be known to both the transmitter and the receiver";
  "Disguising the preamble, as well as its location in time and frequency are possible ways to mitigate".
- Further mitigation paper cited there: [67] M. LaPan, C. Clancy, R. W. McGwier, "Protecting physical layer
  synchronization: Mitigating attacks against OFDM acquisition", WPMC 2013 (not read).
- Related (Pirayesh refs): [53] La Pan, Clancy, McGwier, "Jamming attacks against OFDM timing synchronization and signal
  acquisition", MILCOM 2012; [54] same authors, WCMC 16(2):177-191, 2016 (open at VTechWorks handle 10919/81985, not read).
