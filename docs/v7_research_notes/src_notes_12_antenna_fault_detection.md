# Source notes 12: detecting an intermittent antenna / connector fault in a multi-antenna receiver
(research only, no decisions; fork session cdaee0, 2026-10-01)

## A. Per-branch monitoring in a diversity system (patent, read via Google Patents)
US 4,506,385 A, "Radio reception path monitor for a diversity system", Rockwell International (now Boeing),
C. D. Fedde, D. L. Carter, published 1985-03-19. https://patents.google.com/patent/US4506385
- Fault mode on aircraft: "A broken antenna connector cable may provide a low impedance contact at ground level;
  however, upon attaining altitude and after a period of flight wherein the aircraft is exposed to much lower ambient
  temperature than experienced at ground level, the broken connector becomes separated and essentially appears as a high
  impedance or open contact." On the ground it lets "the broken connector to once again come into contact".
- Method: records "the occurrence of properly received signals from both diversity antenna systems simultaneously" over
  periodic intervals (10-15 min per flight segment, "hundreds or thousands of DABS interrogations"); a branch that
  decodes nothing in an interval is latched "non-functional" and stored in non-volatile memory for maintenance.

## B. Main-diversity RSSI difference (patent, read via Google Patents)
US 10,164,700 B2, "Fault detection method and fault detection device for external antenna", Huawei, filed 2016-03-31,
granted 2018-12-25. https://patents.google.com/patent/US10164700B2/en
- "the main-diversity received signal strength difference falls within a steady variation range" when no antenna is
  faulty.
- Diversity antenna fault when "the main-diversity received signal strength difference is not less than a first
  threshold"; main antenna fault when it "is not greater than a second threshold". Threshold values not given.

## C. Vibration -> connector signature at the vibration frequency (paper, read)
R. Enquebecq, S. Fouvry, E. Rubiola, M. Collet (Ecole Centrale de Lyon LTDS; FEMTO-ST), "Effect of Fretting Wear Damage
in RF Connectors Subjected to Vibration: DC Contact Resistance and Phase-noise Response".
PDF: https://publiweb.femto-st.fr/tntnet/entries/13058/documents/author/data  (venue/year not printed in the extract)
- "Vibration induces micro-displacements, leading to fretting wear damage in the contact."
- "relative fretting displacement amplitude, by fluctuating the total transmission distance, induced phase noise at the
  specific fretting frequency proportional to the fretting displacement; also, by inducing oxide debris in the
  interface, gross slip fretting wear damage decayed DC electrical contact resistance and microwave signal transmission."
- "this phase noise discontinuity is observed at the frequency equivalent to the fretting loading frequency. Different
  fretting frequencies were imposed, from 25 Hz to 150 Hz, and confirmed this." (peaks at 100 Hz "and successive
  multiples" for a 100 Hz test)
- Conclusion: "Combining DC and transmission loss analysis confirmed that the gross slip fretting wear damage occurring
  when D* > D*t also decayed the microwave signal transmission loss."
- Test: sinusoidal vibration, e.g. D* = +-45 um at 100 Hz; random excitation 1-1,600 Hz for the modal check; phase noise
  at 50 kHz offset from a 10 GHz carrier.

## D. Already in project sources
- Verbeke 2016 (W12): UAV vibration 86-672 Hz (used for fault_vib_hz).
