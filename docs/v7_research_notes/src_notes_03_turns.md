# Source notes 3: turns of small airframes (measured trajectories)
(research only, no decisions; fork session cdaee0, 2026-10-01)

## 1. Fixed-wing VTOL, circular climb (read)
Y. Lyu et al., Drones 8(9):492, 2024, doi 10.3390/drones8090492 (https://www.mdpi.com/2504-446X/8/9/492).
- "Hovering preparation: the UAV ascends in a circular path with a radius of 300 m up to 300 m height, flying at a
  constant speed about 27 m/s."
- "The UAV flew along a predefined trajectory, with a constant speed of 27 m/s and a maximum transmitter-receiver
  (Tx-Rx) distance of 3 km."
- Onboard "Inertial Measurement Unit (IMU) navigation system recording the coordinates and UAV attitude"; omni Tx
  antenna "fixed below the airframe"; 36 dBm, 25 MHz, 2.7 GHz.
- The paper quotes no roll values. Kinematics of the stated circle (arithmetic, not a quote): turn rate v/R =
  27/300 rad/s = 5.2 deg/s; level coordinated-turn bank atan(v^2/(g R)) = atan(729/2943) = 13.9 deg.

## 2. Already in hand
- Sun dissertation / Sun-Matolak-Rayess Part IV: S-3B max roll 26.9 deg (medium aircraft).
- Khawaja survey: wing shadowing "generally proportional to aircraft roll angle"; small UAVs "potentially sharper
  pitch, roll, and yaw rates of change during flight".

## 2b. Small fixed-wing, 802.11a at 5 GHz (read; qualitative on banking)
C.-M. Cheng, P.-H. Hsiao, H. T. Kung, D. Vlah, "Performance Measurement of 802.11a Wireless Links from UAV to Ground
Nodes with Various Antenna Orientations", ICCCN 2006, pp. 303-308.
PDF: https://www.eecs.harvard.edu/~htk/publication/2006-icccn-cheng-hsiao-kung-vlah.pdf
- Time scale of attitude change: "it may take several hundreds of milliseconds for the bank angle of the UAV to change
  enough to appreciably affect the receiver's position in the antenna pattern."
- "when the UAV is at that distance, it is probably banking at sharp angles such that it turns back towards the ground
  nodes; at this time, the antennas are no longer cross-polarized."
- Throughput share by UAV antenna orientation (table): H 0.63101 Mbps (42.1%), HN 0.59425 Mbps (39.6%),
  V 0.23607 Mbps (15.7%), Hp 0.16682 Mbps (11.1%).
- Conclusion (abstract via search summary): for a flyover path both ends should use horizontal dipoles "with their
  respective antenna null pointing to a direction perpendicular to the UAV's flight path".
- No numeric bank angles are given.

## 3. Not found yet
- Measured bank angles or yaw rates of small fixed-wing UAVs or multirotors in a channel campaign. Vendor tilt limits
  (Parrot Mambo +-25 deg, Bebop 2 +-35 deg, from MathWorks support-package docs) are configuration limits, not
  measurements.
