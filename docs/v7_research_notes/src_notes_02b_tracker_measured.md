# Source notes 2b: measured antenna-tracker error (read in full) + tracker failure at start-up
(research only, no decisions; fork session cdaee0, 2026-10-01)

G. Nugroho, D. Dectaviansyah, "Design, manufacture and performance analysis of an automatic antenna tracker for an
unmanned aerial vehicle (UAV)", Journal of Mechatronics, Electrical Power, and Vehicular Technology 9 (2018) 32-40,
doi 10.14203/j.mev.2018.v9.32-40. Open access PDF: https://mev.brin.go.id/mev/article/download/404/pdf
- Tracker: "32-bit microcontroller and GPS with two degrees-of-freedom ... 360 degrees on azimuth axis (yaw) and 90
  degrees on elevation axis (pitch)"; pointing from the UAV's telemetry GPS and the GCS GPS (spherical law of cosines).
- Antennas: "The directional antenna used was a 6 dBi 3 element Yagi ... The omnidirectional antenna gain was 2.1 dBi.
  Both antennas were worked at a frequency of 915 to 928 MHz." GCS-tracker link 433 MHz, tracker-UAV 915 MHz.
- Test vehicle: "The antenna tracker performance was tested with a Quadcopter-type UAV".
- Measured error: "the antenna tracker could track the UAV accurately with an average error of 5.62° on Azimuth axis
  (Yaw) and 1.51° on elevation axis (Pitch), respectively."
- Start-up failure (GNSS not fixed): "there was a significant error at the beginning of the antenna tracker activation.
  That was because the GPS module had not received the position of at least 6 satellites, so that GPS status on GCS was
  still not fixed. However after 202.091 seconds the antenna tracker had worked normally and accurately."
- Also: "uncontrolled movement of the antenna tracker was often occur ... when the system was started up."
- RSSI (qualitative, Fig. 11): with the tracker "the signal quality did not fluctuate significantly"; with the high-gain
  directional antenna and no tracker it "fluctuated significantly"; with "only an omnidirectional antenna, the signal
  quality was fluctuated very significant even the lowest signal quality had occurred".
- Test distance and UAV speed are not stated in the text read.

Pairing with ITU-R F.1336-5 (src_notes_02): for a 6 dBi antenna phi3 = sqrt(27000 x 10^-0.6) = 82 deg, so a 5.62 deg
error gives 12 x (5.62/82)^2 = 0.06 dB (arithmetic, not a quote).
