# GPS antenna-tracker paper (Riyandi et al. 2018) and approved IEEE 802.11 frequency-tolerance text

Note on wording: copyright handling limits me to one short verbatim quote (used in section B). Everything else is a close paraphrase with the exact numbers, clause, page and table numbers. The exact wording can be copied from the saved PDFs at the pages given. All documents below were downloaded and read in full text (pdftotext) in this session unless marked UNVERIFIED.

Files saved to `...\פרוייקט גמר\מקורות\`. Each name was checked first and nothing was overwritten:
- `V7_Riyandi2018_PID_Fuzzy_GPS_Antenna_Tracker.pdf` (JTSiskom 6(3):122-128, English, 7 pp.)
- `V7_Riyandi2018_Transient_Indonesian_Version_Antenna_Tracker.pdf` (Transient 7(2):614-620, Indonesian companion paper by the same authors, 7 pp.)
- `V7_IEEE2007_80211-2007_Std_Revision_Full.pdf` (IEEE Std 802.11-2007, approved 8 March 2007, 1320 PDF pp.)
- `V7_IEEE1999_80211a_5GHz_OFDM_PHY.pdf` (IEEE Std 802.11a-1999, approved 16 September 1999, 90 pp.)
- `V7_IEEE2009_80211n_HT_Amendment_PTAB_Exhibit.pdf` (IEEE Std 802.11n-2009, approved 11 September 2009, USPTO PTAB public exhibit stamped "SONY-1017", 537 pp.)

## (A) Riyandi, Sumardi, Prakoso 2018: GPS-based antenna tracker with fuzzy-tuned PID

### Takeaway
The full text was read from a Wayback copy of the JTSiskom PDF. The live site returned 503 "Under Maintenance" all session. The "49 km/hour" in the English abstract is a typo: the paper's own Table 9, its conclusion, and the Indonesian-language abstract of the companion Transient paper all give **60 km/h** for the 49° maximum error. The tracked object in that test was a **motorcycle** on a 142 m track roughly 18 m from the tracker, not a UAV. The tracker uses a 433 MHz Yagi-Uda (simulated gain 10 dB; no beamwidth stated) driven by GPS position telemetry at most 5 Hz. The authors attribute the growth in error with speed to that 0.2 s GPS update interval.

### Cited Findings
**Bibliographic / access**
- A. Riyandi, S. Sumardi, T. Prakoso, "PID Parameters Auto-Tuning on GPS-based Antenna Tracker Control using Fuzzy Logic", Jurnal Teknologi dan Sistem Komputer 6(3), 2018, pp. 122-128, DOI 10.14710/jtsiskom.6.3.2018.122-128. Received 26 Mar 2018, revised 29 Jul 2018, accepted 30 Jul 2018, available online 31 Jul 2018 (p.122). Read from the Wayback snapshot of 13 Dec 2025 — [JTSiskom PDF via Wayback](http://web.archive.org/web/20251213044627/https://jtsiskom.undip.ac.id/article/download/13028/12475); original [article page](https://jtsiskom.undip.ac.id/article/view/13028) (503 throughout this session); [DOI](https://doi.org/10.14710/jtsiskom.6.3.2018.122-128)
- Companion Indonesian paper by the same three authors with the same experiment and more figure detail: "Aplikasi Logika Fuzzy sebagai Auto Tuning Parameter Kontroler PID pada Pengendalian Antena Tracker Berbasis GPS", Transient 7(2), June 2018, pp. 614-620, DOI 10.14710/transient.v7i2.614-620 — [Transient article page](https://ejournal3.undip.ac.id/index.php/transient/article/view/23382); [Transient PDF](https://ejournal3.undip.ac.id/index.php/transient/article/download/23382/21360)

**Abstract discrepancy (speed of the 49° case)**
- The English abstract (JTSiskom p.122) states a maximum error of 49° "for a 49 km/hour speed object". The Transient English abstract repeats the same "49 km/hour" phrase — [JTSiskom PDF](http://web.archive.org/web/20251213044627/https://jtsiskom.undip.ac.id/article/download/13028/12475); [Transient PDF](https://ejournal3.undip.ac.id/index.php/transient/article/download/23382/21360)
- The Indonesian abstract of the Transient paper (p.614) says maximum error 49° in azimuth with an object at 60 km/jam (60 km/h) — [Transient PDF](https://ejournal3.undip.ac.id/index.php/transient/article/download/23382/21360)
- JTSiskom Table 9 (p.127), "Azimuth servo response for the various speed movement":
  - 20 km/h: tracking time 14.4 s; max error 19°; min 0°; avg 2.4°; penalty 2.22 dB
  - 40 km/h: 7.3 s; max 28°; min 0°; avg 6.8°; penalty −1.89 dB
  - 60 km/h: 5.6 s; max 49°; min 0°; avg 9.3°; penalty 6.37 dB
  
  Conclusion (p.128): the system followed the object at speeds up to 60 kmph — [JTSiskom PDF](http://web.archive.org/web/20251213044627/https://jtsiskom.undip.ac.id/article/download/13028/12475)

**Antenna type, gain, beamwidth**
- GCS antenna: 433 MHz Yagi-Uda, chosen for its directional pattern (pp.122-123). Design criteria were VSWR ≤ 2, reflection coefficient ≤ −10 dB and link budget 15 dBm — [JTSiskom PDF](http://web.archive.org/web/20251213044627/https://jtsiskom.undip.ac.id/article/download/13028/12475)
- Table 1 (p.123), "CST Studio Suite antenna simulation results": VSWR 1.078; reflection coefficient −28.436 dB; impedance 49.352 Ω (target 50); **gain 10 dB** (target 10 dB). These are simulation values, not measurements — [JTSiskom PDF](http://web.archive.org/web/20251213044627/https://jtsiskom.undip.ac.id/article/download/13028/12475)
- **No beamwidth (HPBW) is given** in either paper. A measured pattern is shown as Figure 19 (JTSiskom p.127) and Gambar 2 (Transient p.615, horizontal and vertical). The authors note the pattern is not ideal: the strongest relative field is at about ±30°, not 0°. They use this to explain the negative penalty at 40 km/h (pp.127-128) — [JTSiskom PDF](http://web.archive.org/web/20251213044627/https://jtsiskom.undip.ac.id/article/download/13028/12475); [Transient PDF](https://ejournal3.undip.ac.id/index.php/transient/article/download/23382/21360)
- How the "penalty (dB)" was computed: an SNR-style calculation from the radiation pattern. The relative field strength at the actual pointing position minus the relative field strength in the direction of the maximum error (p.127) — [JTSiskom PDF](http://web.archive.org/web/20251213044627/https://jtsiskom.undip.ac.id/article/download/13028/12475)

**Hardware, telemetry and GPS rate**
- Airborne/vehicle "data sender" (Figure 1, p.123): GPS receiver, BMP280 barometer for altitude, ATmega328P microcontroller, 433 MHz telemetry radio, 7.4 V battery — [JTSiskom PDF](http://web.archive.org/web/20251213044627/https://jtsiskom.undip.ac.id/article/download/13028/12475)
- Tracker (Figure 2, p.123):
  - STM32F103C8T6 microcontroller
  - DS04-NFC servo for azimuth and RDS3135MG servo for elevation
  - HMC5883L magnetometer for azimuth feedback and MPU-6050 for elevation feedback
  - 433 MHz telemetry radio, 11.1 V battery
  
  Pointing setpoints come from the bearing equations (Eqs. 1-4) and from Haversine distance plus altitude (Eqs. 5-10) — [JTSiskom PDF](http://web.archive.org/web/20251213044627/https://jtsiskom.undip.ac.id/article/download/13028/12475)
- Serial links: object-to-GCS 433 MHz link at 9600 bps; GUI link at 57600 baud (Transient p.616) — [Transient PDF](https://ejournal3.undip.ac.id/index.php/transient/article/download/23382/21360)
- **GPS update rate**: maximum 5 Hz, so object position was updated at most every 0.2 s. The authors give this as the reason average and maximum error grow with speed (JTSiskom p.128; Transient p.620) — [JTSiskom PDF](http://web.archive.org/web/20251213044627/https://jtsiskom.undip.ac.id/article/download/13028/12475); [Transient PDF](https://ejournal3.undip.ac.id/index.php/transient/article/download/23382/21360)
- Sensor accuracy tests (p.126; protractor and benchmark references): average magnetometer error 8.4°, MPU 0.3°, GPS 5 m. The authors judged these acceptable — [JTSiskom PDF](http://web.archive.org/web/20251213044627/https://jtsiskom.undip.ac.id/article/download/13028/12475)

**Test setup: object type, distance, speed**
- **Test 1, quadcopter** (Figure 15, p.126; Tables 7-8, p.127): the authors state that object speed and distance could not be measured. Three routes were flown. The Transient version names them circular, straight horizontal, and straight crossing over the antenna (Gambar 7, p.618).
  - Table 7, elevation, routes 1/2/3: rise time 1 / 1.08 / 1 s; max error 38 / 36 / 38°; min 0; avg 6.47 / 3.27 / 9.6°.
  - Table 8, azimuth: rise time 0.5 / 0.7 / 0.4 s; max error 91 / 83 / 76°; min 0; avg 9.76 / 4.4 / 10.2°.
  
  — [JTSiskom PDF](http://web.archive.org/web/20251213044627/https://jtsiskom.undip.ac.id/article/download/13028/12475); [Transient PDF](https://ejournal3.undip.ac.id/index.php/transient/article/download/23382/21360)
- **Cause of the quadcopter maximum errors (91° azimuth, 38° elevation):** the quadcopter changed direction sharply before the GPS updated its data (JTSiskom p.127; same statement in Transient p.618). The authors compare favourably with the 8.3° average error of an RSSI-based tracker in their reference [7] — [JTSiskom PDF](http://web.archive.org/web/20251213044627/https://jtsiskom.undip.ac.id/article/download/13028/12475)
- **Test 2, motorcycle** (Figure 16 "Motorcycle driven route", p.127; Figures 17-18; Table 9): the object rode on a motorcycle so speed and distance could be measured, at three speeds (20/40/60 km/h). Only the azimuth servo was tested, over azimuth 320° to 100° — [JTSiskom PDF](http://web.archive.org/web/20251213044627/https://jtsiskom.undip.ac.id/article/download/13028/12475)
- Figure labels:
  - JTSiskom Figure 16 shows "142 m", "35°" and N/S marks (p.127).
  - The Transient version of the same figure (Gambar 8, p.619, "Lintasan objek pada pengujian terukur") adds a label "18 m" next to "Antena", plus "Lintasan Objek" and "142 m".
  - I could not render the figure (no rasteriser available), so the geometry comes from label text only.
  
  — [JTSiskom PDF](http://web.archive.org/web/20251213044627/https://jtsiskom.undip.ac.id/article/download/13028/12475); [Transient PDF](https://ejournal3.undip.ac.id/index.php/transient/article/download/23382/21360)
- Transient Table 6 (p.620) adds the column "Jarak pada Galat Maks (m)" (distance at maximum error): 6.5 m (20 km/h), 9.7 m (40 km/h), 17.6 m (60 km/h). For each speed the text says the maximum error corresponds to an object travel distance of that many metres (p.619). Figure x-axes are "Jarak Tempuh (meter)" (distance travelled), running to about 93-102 m — [Transient PDF](https://ejournal3.undip.ac.id/index.php/transient/article/download/23382/21360)
- The Transient text also notes setpoint spikes caused by GPS data errors at 20 and 40 km/h. The tracker did not follow them because they were very short (p.619) — [Transient PDF](https://ejournal3.undip.ac.id/index.php/transient/article/download/23382/21360)

**Step-response statistics (bench)**
- Table 5 (p.125), elevation rise time, conventional PID vs fuzzy self-tuning PID:
  - setpoint 10°: 2.5 / 2.1 s
  - 30°: 2.6 / 1.9 s
  - 70°: 3.2 / 2.3 s
  - average: 2.76 / 2.1 s (difference 0.67 s)
- Table 6 (p.125), azimuth:
  - 30°: 1.4 / 0.7 s
  - 90°: 1.4 / 0.8 s
  - 180°: 1.9 / 1.2 s
  - 210°: 1.4 / 1.2 s
  - 270°: 1.5 / 0.9 s
  - average: 1.52 / 0.96 s (difference 0.56 s)
  
  — [JTSiskom PDF](http://web.archive.org/web/20251213044627/https://jtsiskom.undip.ac.id/article/download/13028/12475)

### Inferences
- The abstract's "average rise time 0.7 s azimuth / 1.08 s elevation" does not equal the averages in Tables 5-6 (0.96 s / 2.1 s). It equals the Route-2 rise times in Tables 8 and 7 (0.7 s / 1.08 s). Cite the table values, not the abstract, if rise time matters.
- The 49° case is a ground vehicle at short range, not a UAV at UAV ranges. Inferred from the labels "18 m" and "142 m" plus the 140° azimuth sweep (320° to 100°):
  - Speed × tracking time gives about 80 m (20 km/h × 14.4 s), 81 m (40 km/h × 7.3 s) and 93 m (60 km/h × 5.6 s). This matches the ~93-102 m x-axes, i.e. a near-pass of a straight track.
  - If 18 m is the closest-approach distance, the peak line-of-sight angular rate is v/d ≈ 18°/s, 35°/s and 53°/s at 20/40/60 km/h.
  - The "distance at max error" values convert to a time lag of about 1.17 s, 0.87 s and 1.06 s (6.5 m ÷ 5.56 m/s, 9.7 m ÷ 11.1 m/s, 17.6 m ÷ 16.7 m/s).
  - A ~1 s lag at ~53°/s gives an error of the order of 49°. So the 49° most plausibly comes from high angular rate at close range, combined with the 0.2 s GPS interval and the servo/controller lag.
  - The authors themselves name only the GPS update rate, not the geometry. This is my inference from figure labels and table values, not a stated finding.
- The 8.4° average magnetometer error is an azimuth feedback error floor that sits under all the azimuth results.

### Gaps
- No antenna beamwidth (HPBW) or measured gain is reported. The 10 dB gain is a CST simulation (Table 1).
- The exact geometry of Figure 16 / Gambar 8 (what "18 m" and "35°" mark) could not be confirmed visually because the figure could not be rendered. The text never states the closest-approach distance.
- The quadcopter tests give no distance, speed or altitude.
- The telemetry packet rate is not stated separately from the 5 Hz GPS rate.
- The JTSiskom landing page could not be opened (HTTP 503 throughout). The license statement on the landing page was therefore not checked.

## (B) Approved IEEE 802.11 text: transmit center frequency tolerance and symbol/chip clock tolerance (2.4 GHz and 5 GHz)

### Takeaway
Free copies of three **approved** IEEE documents were found and read: 802.11-2007 (full revision), 802.11a-1999 and 802.11n-2009. All 2.4 GHz PHYs specify **±25 ppm** for both transmit center frequency and chip/symbol clock tolerance:
- DSSS: Clause 15 in 802.11-2007
- HR/DSSS (802.11b): Clause 18 in 802.11-2007
- ERP (802.11g): Clause 19 in 802.11-2007
- HT (802.11n): Clause 20 in 802.11n-2009

The 5 GHz OFDM PHY specifies ±20 ppm (802.11a-1999). In 802.11-2007 that becomes ±20 ppm for 20/10 MHz channels and ±10 ppm for 5 MHz channels. The approved clause numbers for HR/DSSS (18.4.7.4 / 18.4.7.5) are one lower than in the P802.11b/D3.1 draft already on file (18.4.7.5 / 18.4.7.6).

### Cited Findings
**IEEE Std 802.11-2007** (revision of 802.11-1999; approved 8 March 2007; incorporates 802.11a/b/d/e/g/h/i/j). Free university-hosted copy. The live host was unreachable in this session, so it was read via the Wayback snapshot of 4 Jun 2024 — [802.11-2007 PDF (USF, via Wayback)](http://web.archive.org/web/20240604215729/http://magrawal.myweb.usf.edu/dcom/Ch8_802.11-2007.pdf); original URL http://magrawal.myweb.usf.edu/dcom/Ch8_802.11-2007.pdf
- **HR/DSSS (Clause 18, 802.11b), printed p.683 (PDF p.~731):**
  - 18.4.7.4 "Transmit center frequency tolerance". Verbatim: "The transmitted center frequency tolerance shall be ±25 ppm maximum."
  - 18.4.7.5 "Chip clock frequency tolerance": the PN code chip clock tolerance shall be better than ±25 ppm maximum. Locking (coupling) the chip clock and the transmit frequency is highly recommended for best demodulation. If they are locked, bit 2 of the SERVICE field should be set to 1 (see 18.2.3.4).
  - Operating range (18.4.6.1): 2.4-2.4835 GHz, or 2.471-2.497 GHz in Japan.
  
  — [802.11-2007 PDF](http://web.archive.org/web/20240604215729/http://magrawal.myweb.usf.edu/dcom/Ch8_802.11-2007.pdf)
- **DSSS (Clause 15, "DSSS PHY specification for the 2.4 GHz band designated for ISM applications"), printed p.569 (PDF p.~617):**
  - 15.4.7.5 "Transmit center frequency tolerance": ±25 ppm maximum.
  - 15.4.7.6 "Chip clock frequency tolerance": PN code chip clock tolerance better than ±25 ppm maximum.
  - Operating range (15.4.6.1): 2.4-2.4835 GHz, or 2.471-2.497 GHz in Japan.
  
  — [802.11-2007 PDF](http://web.archive.org/web/20240604215729/http://magrawal.myweb.usf.edu/dcom/Ch8_802.11-2007.pdf)
- **ERP (Clause 19, 802.11g; 19.1 says this PHY operates in the 2.4 GHz ISM band), printed p.703 (PDF p.~751):**
  - 19.4.7 makes the ERP transmit specifications follow 17.3.9, except for transmit power (17.3.9.1), center frequency tolerance (17.3.9.4) and symbol clock tolerance (17.3.9.5).
  - 19.4.7.2 "Transmit center frequency tolerance": ±25 PPM maximum. The carrier and the symbol clock shall come from the same (locked) reference oscillator.
  - 19.4.7.3 "Symbol clock frequency tolerance": ±25 PPM maximum, with the same locked-oscillator requirement. As a result, the PPM error of the carrier and of the symbol timing shall be the same.
  
  — [802.11-2007 PDF](http://web.archive.org/web/20240604215729/http://magrawal.myweb.usf.edu/dcom/Ch8_802.11-2007.pdf)
- **OFDM (Clause 17, "OFDM PHY specification for the 5 GHz band"), printed p.615 (PDF p.~663):**
  - 17.3.9.4 "Transmit center frequency tolerance": ±20 ppm maximum for 20 MHz and 10 MHz channels, ±10 ppm maximum for 5 MHz channels. Carrier and symbol clock derived from the same reference oscillator.
  - 17.3.9.5 "Symbol clock frequency tolerance": the same ±20 ppm / ±10 ppm values and the same oscillator requirement.
  
  — [802.11-2007 PDF](http://web.archive.org/web/20240604215729/http://magrawal.myweb.usf.edu/dcom/Ch8_802.11-2007.pdf)
- PICS rows confirm the clause mapping. HRDS23 "Transmitted center frequency tolerance" → 18.4.7.4, and HRDS24 "Chip clock frequency tolerance" → 18.4.7.5, both Mandatory (Annex A) — [802.11-2007 PDF](http://web.archive.org/web/20240604215729/http://magrawal.myweb.usf.edu/dcom/Ch8_802.11-2007.pdf)

**IEEE Std 802.11a-1999** (supplement to 802.11-1999, "High-speed Physical Layer in the 5 GHz Band"; approved 16 September 1999; PDF ISBN 0-7381-1810-9). Free copy hosted at MIT CSAIL PDOS — [802.11a-1999 PDF (MIT)](https://pdos.csail.mit.edu/archive/decouto/papers/802.11a.pdf)
- Printed p.28 (PDF p.36):
  - 17.3.9.4 "Transmit center frequency tolerance": ±20 ppm maximum; carrier and symbol clock derived from the same reference oscillator.
  - 17.3.9.5 "Symbol clock frequency tolerance": ±20 ppm maximum, same oscillator requirement.
  
  — [802.11a-1999 PDF](https://pdos.csail.mit.edu/archive/decouto/papers/802.11a.pdf)

**IEEE Std 802.11n-2009** (Amendment 5, "Enhancements for Higher Throughput", HT PHY; approved 11 September 2009; PDF ISBN 978-0-7381-6046-7). Free government copy: a USPTO PTAB public exhibit stamped "SONY-1017" — [802.11n-2009 PDF (USPTO PTACTS exhibit)](https://ptacts.uspto.gov/ptacts/public-informations/petitions/1557847/download-documents?artifactId=jXigNU4G74Mw7wY6gWXk9BjeV6SeDTn6VYIuBVXHXQFIZBOLyGvh0l0)
- Printed p.316 (exhibit stamp 350, PDF p.351):
  - 20.3.21.4 "Transmit center frequency tolerance": ±20 ppm maximum in the 5 GHz band and **±25 ppm maximum in the 2.4 GHz band**. All transmit-chain center frequencies (LO) and every transmit-chain symbol clock shall come from the same reference oscillator.
  - 20.3.21.6 "Symbol clock frequency tolerance": ±20 ppm maximum for 5 GHz bands and **±25 ppm for 2.4 GHz bands**. Center frequency and symbol clock for all transmit antennas shall come from the same reference oscillator.
  
  — [802.11n-2009 PDF](https://ptacts.uspto.gov/ptacts/public-informations/petitions/1557847/download-documents?artifactId=jXigNU4G74Mw7wY6gWXk9BjeV6SeDTn6VYIuBVXHXQFIZBOLyGvh0l0)

**Other observations**
- UNVERIFIED (search snippet only): a Keysight help page says IEEE Std 802.11b-1999 puts chip clock tolerance in paragraph 18.4.7.5. This fits the approved numbering above (18.4.7.4 center frequency, 18.4.7.5 chip clock) — [Keysight](https://www.keysight.com/us/en/lib/resources/user-manuals/chip-clock-frequency-tolerance-339378.html)
- The IEEE "Get 802" legacy URLs on the Wayback Machine (e.g. standards.ieee.org/getieee802/download/802.11b-1999.pdf, snapshots from 2005 and 2017) archive only the terms-of-use / GET-program HTML page, not the PDF. No terms were accepted — [Wayback 2005 snapshot](http://web.archive.org/web/20051210051252/http://standards.ieee.org:80/getieee802/download/802.11b-1999.pdf)

### Inferences
- Converting ±25 ppm to frequency: about ±60.9 kHz at 2.437 GHz (channel 6) and about ±62 kHz at 2.484 GHz. Two compliant stations at opposite extremes could differ by up to 50 ppm, about 122 kHz. This is my own arithmetic, not in the standard.
- The approved text has two strengths of oscillator coupling:
  - DSSS/HR-DSSS make locking the chip clock to the carrier only "highly recommended" (18.4.7.5).
  - ERP, OFDM and HT make a common reference oscillator mandatory. ERP explicitly says the ppm error of carrier and symbol timing is identical.
- 802.11-2007 is an approved consolidated revision that contains the 802.11b clauses. It can be cited as the approved source of the HR/DSSS ±25 ppm numbers, with the approved clause numbers 18.4.7.4 / 18.4.7.5 (not the D3.1 draft numbers 18.4.7.5 / 18.4.7.6).

### Gaps
- The stand-alone approved IEEE Std 802.11b-1999 amendment PDF was not obtained. The text was obtained through 802.11-2007, which incorporates it.
- 802.11-2012/2016/2020 were not obtained. In those editions the HT clauses are renumbered (20.3.20.4 in 2012 and 19.3.18.4 in 2016 per general knowledge — UNVERIFIED, not read). Whether those editions add 2.4 GHz wording to the OFDM clause was not checked.
- The exact wording of each clause other than the one quote above is in the saved PDFs at the printed pages listed.

### COULD NOT DOWNLOAD
- IEEE Std 802.11b-1999, "Higher-Speed Physical Layer Extension in the 2.4 GHz Band" (approved 16 Sep 1999). Status page: https://standards.ieee.org/ieee/802.11b/1167/ . The DOI I have from memory, 10.1109/IEEESTD.2000.90914, is UNVERIFIED. Known exhibit copies (IPR2014-00552 Ex.1006 and IPR2014-00553 Ex.1106) are on paywalled Docket Alarm: https://www.docketalarm.com/cases/PTAB/IPR2014-00553/Inter_Partes_Review_of_U.S._Pat._6754195/03-27-2014-Petitioner/Exhibit-1106-IEEE_Standard_80211b . The same exhibits may be free on USPTO PTACTS if searched by IPR number.
- IEEE Std 802.11-2012 / 802.11-2016 / 802.11-2020 full texts. Free only via the IEEE GET program, which requires an IEEE account. Not needed for the ±25 ppm values above.
