# Source notes 7: optimum combining, N antennas vs L interferers
(research only, no decisions; fork session cdaee0, 2026-10-01)

## Found (verbatim, read from the paper's own text)
J. H. Winters, J. Salz, R. D. Gitlin, "The impact of antenna diversity on the capacity of wireless communication
systems", IEEE Trans. Communications, vol. 42, no. 2/3/4, pp. 1740-1751, Feb/Mar/Apr 1994.
Readable scan: https://my.ece.utah.edu/~ece6962/project/antenna_diversity.pdf
- Abstract: "for independent flat-Rayleigh fading wireless systems with N mutually interfering users, we demonstrate
  that with K+N antennas, N-1 interferers can be nulled out and K+1 path diversity improvement can be achieved by each
  of the N users."
- Introduction: "it is known that with M antennas, M-1 interferers can be nulled out [3-5]" ([3] is Winters 1984 JSAC).
- Section II (after eq. 11): "the average probability of error with optimum combining, M antennas, and N interferers
  is the same as maximal ratio combining with M-N+1 antennas and no interferers."
  Here N counts the users including the desired one (abstract: N mutually interfering users), so with L = N-1
  interferers the remaining diversity is M-L.
- Same section: "the above result is error rate performance with zero-forcing weights, whereby the interference is
  completely cancelled. In most practical systems, though, we don't need to cancel the interference, but only suppress
  it into the noise, and thus the minimum MSE combiner can achieve even better results than shown above."
- "when M=N+1, all users enjoy dual diversity, i.e., the addition of each antenna adds diversity to every user."

## Original 1984 paper (not read here)
J. H. Winters, "Optimum combining in digital mobile radio with cochannel interference", IEEE JSAC, vol. 2, no. 4,
pp. 528-539, 1984. A docketalarm copy exists (IPR2013-00306 Exhibit 1013), but it is a paywalled viewer.
