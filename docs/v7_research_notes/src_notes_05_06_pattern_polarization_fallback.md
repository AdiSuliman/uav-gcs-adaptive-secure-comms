# Source notes 5/6: omni elevation pattern (overhead pass), polarization mismatch, omni fallback at the GCS
(research only, no decisions; fork session cdaee0, 2026-10-01)

## 5a. Omni (in azimuth) elevation pattern - ITU-R F.1336-5 recommends 2.1 (read)
PDF: https://www.itu.int/dms_pubrec/itu-r/rec/f/R-REC-F.1336-5-201901-I!!PDF-E.pdf
- "in the frequency range from 400 MHz to about 70 GHz, the following reference radiation patterns should be used in
  cases involving stations that use omnidirectional (in azimuth) antennas", for "elevation angles that range from -90°
  to 90°", eq. (1a)-(1c):
    G(theta) = G0 - 12 (theta/theta3)^2                          for 0 <= |theta| < theta4
    G(theta) = G0 - 12 + 10 log(k + 1)                           for theta4 <= |theta| < theta3
    G(theta) = G0 - 12 + 10 log((|theta|/theta3)^-1.5 + k)       for theta3 <= |theta| <= 90
    theta3 = 107.6 x 10^(-0.1 G0)  (degrees, 3 dB beamwidth in elevation)
    theta4 = theta3 sqrt(1 - (1/1.2) log(k + 1))
  theta = "elevation angle relative to the angle of the maximum gain"; G0 = "the maximum gain in the azimuth plane".
- recommends 2.3: "in cases involving typical antennas operating in the 400 MHz to 3 GHz range, the parameter k should
  be 0.7"; 2.4: improved side-lobe antennas k = 0.
- Arithmetic (not a quote): G0 = 2.15 dBi -> theta3 = 65.6 deg; straight below/above the antenna (|theta| = 90) with
  k = 0.7: G = 2.15 - 12 + 10 log(0.622 + 0.7) = -8.6 dBi, i.e. about 10.8 dB under the peak. With k = 0 it is
  -12 + 10 log(0.622) = -14.1 dB under the peak. (A physical dipole has a true axial null; the ITU reference pattern
  is an envelope for sharing studies.)

## 5b. Polarization mismatch
- R. C. Rumpf, EMPossible, "Topic 2 - Antenna Parameters and Figures of Merit (FOM) Continued", lecture slides
  (9/12/2017), https://empossible.net/wp-content/uploads/2018/03/Topic-2-Figures-of-Merit-Continued.pdf, slide 11:
  "The polarization loss factor quantifies the loss caused by the polarization mismatch ... The polarization loss
  factor is defined as PLF = |cos psi_p|^2 ... Where psi_p is the angle between the two vectors." (The exponent is
  lost in the PDF text extraction; the standard form is the square, as in Balanis, Antenna Theory, PLF = |rho_w . rho_a|^2.)
  Slide 12: aligned PLF = 1, rotated PLF = |cos psi|^2, orthogonal PLF = 0.
- Measured: Gomez-Ponce et al. 2021 (src_notes_04): "the power in the V-polarization is approximately 12dB higher than
  in the H-polarization" (vertically polarized Tx on a hovering drone, 3.5 GHz).

## 6. Omni + directional at the GCS
- Nugroho & Dectaviansyah 2018 (src_notes_02b): tested tracker + 6 dBi Yagi vs fixed Yagi vs 2.1 dBi omni; tracker
  needed 202 s of GNSS fix at start-up before tracking correctly.
- US 8,503,941 B2, "System and method for optimized unmanned vehicle communication using telemetry", The Boeing
  Company, D. Erdos, T. M. Mitchell, filed 2008-02-21, granted 2013-08-06 (https://patents.google.com/patent/US8503941),
  read via Google Patents (patent, not a measurement):
  - "the ability to transfer communications to an omnidirectional antenna system is also possible via the use of an
    RF amplifier" (fallback when the tracking components fail).
  - "the omnidirectional antenna may be used to communicate short range with another unmanned vehicle, while the
    tracking antenna could be used to communicate with the ground station."
  - "The UAV 12 uses its navigation system or information from a GPS satellite, as well as info on the location of the
    communications station 14, to control the servo motor system." Loss of GPS/telemetry is not addressed.
- Not read: Embention "Veronte Drone Tracker 26NM" product page (avpay.aero); per a search summary, directional + omni
  antennas, omni for short range.
