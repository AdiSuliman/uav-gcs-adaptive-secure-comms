# Source notes 4/5 (partial): hover channel, antenna orientation on small UAVs
(research only, no decisions; fork session cdaee0, 2026-10-01)

## Khawaja survey (already in khawaja.txt) - pointers
- "Example propagation measurements using rotorcraft and air balloons during flight and hovering are available in [30],
  [38], [48], [61]. ... UAV heights ranging from 16 m to 11 km, and link distances 16.5 m to 142 km."
- "In [38], it was observed that the PLEs for IEEE 802.11 communications were different during UAV hovering and moving
  due to different orientations of the on-board UAV antennas."
- "The antenna orientation has been shown to result in different throughputs and RSS values [37], [38], [60], [61] for
  different flight maneuvers."
- Small UAVs: "potentially sharper pitch, roll, and yaw rates of change during flight."
- References: [30] Simunek, Fontan, Pechac, IEEE TAP 61(7) 2013, 3850-3858 (time-series generator, urban low elevation);
  [37] Cheng, Hsiao, Kung, Vlah, ICCCN 2006 (802.11a, UAV antenna orientations); [38] Yanmaz, Kuschnig, Bettstetter,
  GC Wkshps 2011, 1280-1284; [48] Khawaja, Guvenc, Matolak, GLOBECOM 2016 (UWB); [60] Yanmaz et al. INFOCOM 2013,
  120-124; [61] Ahmed, Kanhere, Jha, IEEE Commun. Mag. 54(5) 2016, 52-57.

## Read in full, limited relevance
- Ahmed, Kanhere, Jha, "Link Characterization for Aerial Wireless Sensor Networks", UNSW-CSE-TR-1113, Aug 2011
  (https://cgi.cse.unsw.edu.au/~reports/papers/1113.pdf). TelosB 802.15.4 at 2.4 GHz, monopoles, 0 dBm. Static poles up
  to 4.2 m, NOT flying: "this static placement of the nodes does not capture the effect of UAV movements (e.g., the
  Doppler effect)... We do not expect Doppler effect to be severe at the mobility speed of a few km/h typical for these
  hovering UAVs." Orientation: "on average RSSI values vary up to about 10dB for the best and worst antenna orientation
  for all height variations."
- Simunek, Pechac, Fontan, "Excess Loss Model for Low Elevation Links in Urban Areas for UAVs", Radioengineering 20(3),
  2011, 561-568 (https://www.radioeng.cz/fulltexts/2011/11_03_561_568.pdf). Remote-controlled airship, 27 dBm; excess
  loss vs elevation; "invalid data due to large pitch or roll values were flagged out". No hover fade statistics.

## Leads not yet read (for orientation / overhead null / polarization)
- M. Badi, J. Wensowitch, D. Rajan, J. Camp, "Experimentally Analyzing Diverse Antenna Placements and Orientations for
  UAV Communications", IEEE TVT 69(12), 2020, 14989-15004.
- M. Badi et al., "Experimental Evaluation of Antenna Polarization and Elevation Effects on Drone Communications",
  ACM MSWiM 2019, 211-220, doi 10.1145/3345768.3355916.
- J. Chen, D. Raye, W. Khawaja, P. Sinha, I. Guvenc, "Impact of 3D UWB Antenna Radiation Pattern on Air-to-Ground Drone
  Connectivity", IEEE VTC-Fall 2018.
- N. C. Matson et al., "Effect of Antenna Orientation on the Air-to-Air Channel in Arbitrary 3D Space", SMU (SwarmNet
  2021), https://s2.smu.edu/~camp/pubs/Matson_SwarmNet2021.pdf (air-to-air, hovering Tx at 80 m, IMU roll/pitch/yaw logged).

## Topic 3 (roll angles of small airframes): no measured source found yet
- Search snippets only (vendor limits, not measurements): Parrot Mambo +-25 deg, Bebop 2 +-35 deg max tilt (MathWorks
  support-package docs). Sun's S-3B 26.9 deg max roll remains the only measured value in hand.
