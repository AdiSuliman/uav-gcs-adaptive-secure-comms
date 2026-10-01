# Source notes 2: antenna-tracker pointing error and pointing loss
(research only, no decisions; fork session cdaee0, 2026-10-01)

## A. Pointing loss / low-gain directional pattern (read, primary, free)
Recommendation ITU-R F.1336-5 (01/2019), "Reference radiation patterns of omnidirectional, sectoral and other
antennas for the fixed and mobile services for use in sharing studies in the frequency range from 400 MHz to about
70 GHz". PDF: https://www.itu.int/dms_pubrec/itu-r/rec/f/R-REC-F.1336-5-201901-I!!PDF-E.pdf
- recommends 4: "in the frequency range from 1 GHz to about 3 GHz, the following reference radiation patterns should be
  used in cases involving stations that use low-gain antennas with circular symmetry about the 3 dB beamwidth and with
  a main lobe antenna gain less than about 20 dBi".
- recommends 4.1, eq. (4), peak side-lobe pattern (read from the Word file's equation images):
    G(phi) = G0 - 12 (phi/phi3)^2              for 0 <= phi < 1.08 phi3
    G(phi) = G0 - 14                            for 1.08 phi3 <= phi < phi1
    G(phi) = G0 - 14 - 32 log(phi/phi1)         for phi1 <= phi < phi2
    G(phi) = -8                                 for phi2 <= phi <= 180
  "phi3: the 3 dB beamwidth in azimuth and elevation of the low-gain antenna (degrees)":
    phi3 = sqrt(27 000 x 10^(-0.1 G0))  (degrees)   [square-root sign confirmed from the drawn radical in image53.wmf]
    phi1 = 1.9 phi3 (degrees);  phi2 = phi1 x 10^((G0 - 6)/32) (degrees)
- NOTE 7: the pattern "primarily applies in situations where the main lobe antenna gain is less than or equal to
  20 dBi ... Further study is required to establish the full range of frequencies and gain over which the equations
  are valid."
- So the loss for a pointing error e is 12 (e/phi3)^2 dB inside the main lobe.
  Examples: G0 = 6 dBi -> phi3 = 82 deg; 10 -> 52; 13.2 -> 36; 14 -> 33.
- Sectoral antennas, recommends 3.1.1.2: horizontal relative gain "G_hr(x_h) = -12 x_h^2 for x_h <= 0.5" (same law).

## B. Measured tracker error (not yet read in full)
1. A. Riyandi, Sumardi, T. Prakoso, "PID Parameters Auto-Tuning on GPS-based Antenna Tracker Control using Fuzzy
   Logic", Jurnal Teknologi dan Sistem Komputer (JTSiskom), Jul 2018, article 13028, Univ. Diponegoro.
   Abstract (via search index; site returned 503): minimal error 0 deg in azimuth and elevation, "maximal error of 49°
   for a 49 km/hour speed object", average rise time 0.7 s (azimuth) and 1.08 s (elevation). Directional antenna at a
   GCS, GPS-based. Distance and update rate unknown until the full text is read.
   URLs: https://jtsiskom.undip.ac.id/article/view/13028 ; PDF https://jtsiskom.undip.ac.id/article/download/13028/12475
2. Search snippet only (source not identified yet): a GPS-based tracker following a payload, "largest angular difference
   ... 8 degrees azimuth, with a mean angle difference of 4.7 degrees" (possibly undiksha JST 55069, "GPS-Based Rocket
   Payload Position Tracking System"). Unverified.
3. Momoh et al. 2025, Computer Eng. & Applications 14(3): helical 13.2 dBi (simulated); "within 0.05 degrees" is a
   simulation claim, not a measurement.

## C. Error mechanisms named in sources
- US patent 9,660,718 ("Ground terminal and UAV beam pointing..."): motor backlash and wind loading cause cumulative
  pointing errors; GPS propagation delay means the UAV has moved when the antenna is adjusted. Patent, not a measurement.
