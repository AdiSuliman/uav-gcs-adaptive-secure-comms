# Source notes 1: 802.11 transmit center frequency and clock tolerance at 2.4 GHz
(research only, no decisions; fork session cdaee0, 2026-10-01)

## Found (verbatim)
1. IEEE P802.11b/D3.1 (1999), "Higher speed physical layer in the 2.4 GHz band", draft supplement to Std 802.11-1997.
   URL: https://www.ieee802.org/11/Documents/DocumentArchives/1999_docs/90845b_p80211b-draft3.1.pdf
   - 18.4.7.5 Transmit center frequency tolerance: "The transmitted center frequency tolerance shall be ±25 ppm maximum."
   - 18.4.7.6 Chip clock frequency tolerance: "The PN code chip clock frequency tolerance shall be better than ±25 ppm
     maximum. It is highly recommended that the chip clock and the transmit frequency be locked (coupled) for optimum
     demodulation performance."
   - Status: page footer "This is an unapproved IEEE Standards Draft, subject to change". The values match the later
     sources below.
2. Anritsu application note "IEEE 802.11be Compliant TRx Characteristics Evaluation" (MT8862A), 2025-04,
   No. MT8862A_11be-E-F-2-(1.00). Cites IEEE 802.11be D7.0, 36.3.20.3 "Transmit center frequency and symbol clock
   frequency tolerance": "Tolerance 2.4 GHz band: ±25 ppm; 5/6 GHz band: ±20 ppm".
   URL: https://dl.cdn-anritsu.com/en-en/test-measurement/files/Application-Notes/Application-Note/mt8862a-11be-ef2100.pdf
3. Keysight 89600B VSA help, "Sym Clk Err (802.11b/g DSSS/CCK/PBCC)": "The 802.11b and 802.11g standards require the
   symbol clock frequency error tolerance to be ± 25 ppm maximum."
   URL: https://helpfiles.keysight.com/csg/89600B/Webhelp/Subsystems/wlan-dsss/content/dsss_symtbl_symclkerr.htm

## Not found readable
- The approved IEEE Std 802.11b-1999 / 802.11-2020 text. mentor.ieee.org blocks the fetcher (HTTP 418). The docketalarm
  copy (IPR2014-00553 Exhibit 1106) is a paywalled page viewer. Free legal route: IEEE GET Program (needs Adi's login).

## Arithmetic (for reference)
- ±25 ppm at 2.4835 GHz = ±62 kHz per side; Tx vs Rx worst case 50 ppm = ±124 kHz.
