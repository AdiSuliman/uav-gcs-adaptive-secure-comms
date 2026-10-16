# D85, part 'obs': the receiver's idle time, branch cues and a level step in the fusion, per-cycle labels, the emitter-of-opportunity reading (branch d85-obs)

Branch `d85-obs` from v7-merge `136667a` (D84 with the shadowing selection and the 450140a merge fixes). Input: the validation-only research on the weak detector classes (scratch `weak_v2`, 2026-10-12), whose recommendations 1-3 and the per-cycle label the main session adopted (items O1-O4 below). The ONSET part of D85 (the shadowing roll-in, the fault's one-frame step, the monitor's onset shape) is a separate branch; nothing here models an onset. This note is the merge input for the D85 entry of `docs/DECISIONS.md`; it does not replace it.

**Consequence for the runs:** the threat block records more (no draw moves), every frame carries the record of the idle time before it, the gated threats' labels and the dataset's cell sizes change, the fusion's row grows by 42 columns: A0, A5 and every later stage rerun (the pools' MODEL_TAG is now `v7-D85obs`).

---

## Why

On fresh D84 data (6 828 sub-runs, all 11 classes, validation folds by sub-run, nothing of the project's test sets), the detector as built (the hybrid CNN and the temporal fusion, retrained) reads per class: WLAN 62.7% [57.1, 68.2], sweeping jammer 89.5% [87.3, 91.5], path loss 65.3% [60.4, 70.1] (4 and 7 dB steps 5% and 24%), antenna fault 52.3% [43.6, 60.3], airframe shadowing 61.1% [54.3, 68.4]; the other six classes 96.6-99.8% (95% bootstrap intervals over sub-runs). Three causes, each with a physical measure the receiver already has the means to take:
- **The receiver sees 0.69 ms of every 20 ms cycle.** One frame per decision cycle leaves the receiver idle for the other 19.3 ms. A WLAN's packets (0.27-3.2 ms, Wollenberg et al.), a sweep's 5.25 ms dwell every 20-83.5 ms (Liu et al.) and noise bursts all happen mostly there; inside the frame a WLAN packet, a sweep and a barrage jammer look alike (the WLAN's errors went to none 26% and to the sweeper 6%). A radio reads each chain's RSSI while it is idle (Grimaldi et al. 2019: a CC2420 at 18.5 kHz, burst length, power, crest and ripple identify WLAN at 89-96% from INR 20 dB; Airshark: duty and pulse timing).
- **The fusion read no fading statistic of a lost branch and no step of our level.** A faulty connector keeps the link's K on its branch; a shadowed antenna loses its line of sight (K about -16 dB, Sun et al., Part IV, Fig. 12). A path-loss step is a mean shift of our received level, a two-sample test inside the window (Xie et al. 2021).
- **Labels by the frame alone.** With the idle time observed, a cycle that holds a WLAN packet or a sweep only between frames is observed with the threat on the air; the frame's 10% rule (mitigation 3) labelled it clean.

## Decision

### O1. Idle-time RSSI per antenna and its record
- **Recording in the threat block** (`build_threat_model.m`, threat_script and two local functions only): for the WLAN's packets and the noise bursts, the on-share of every RSSI bin of the idle time before each frame, from the previous frame's last sample to the frame's earliest delay-line sample, `p.idle_rssi_hz` bins per second (357 at 18.5 kHz). The schedule's events are drawn by its own switch code, in time order, before the frame's samples draw theirs, so every draw keeps its place: the frames are bit-identical with and without the recording (Results). Output 3 carries them after [actc levc], component by component; `p.idle_rssi_hz` = 0 builds the block as before.
- **The measurement** (`idle_rssi.m`, new): per bin, every emitter's mean power on every antenna, then the RSSI's own average and spread. Exact in schedule and channel: the recorded schedules; the sweeper's window from its drawn period and phase (`Gate`); the reactive jammer silent without our frame; each emitter's level and in-band cap as the block sets them (on the run's `Cap` reference, the countermeasure's levels and `inband_ref`); its channel to each antenna the block's own 32 sinusoids per antenna and delay-line tap, replicated from the block's first draws in the block's order on a stream of their own (the caller's global stream is never touched), at the bin's centre with the heading's turn and the pitch wobble; a faulty connector attenuates the antenna's whole field; the thermal floor fixed. The run's values come from the model's blocks (`idle_context.m`: Seed, Doppler, Level, AoA, Kfac, Yaw, Corr, Att, Gate, Tdl, Cap, Cal), so they are exactly the run's. The RSSI: a sample every 54 us (18.5 kHz), the mean power over the last 128 us, 1 dB steps (Grimaldi et al. 2019, CC2420: Sec. III-A, Sec. II-B, Table III), the antenna's calibration error within +-2 dB (AD9361 data sheet Rev. F, Table 1; the frame measurements' own draw), its spread Gamma(M, 1)/M with M = 1.25 MHz x 128 us = 160 complex samples (Wilson-Hilferty cube of a normal, from the flight's own 'idle' stream).
- **The record** (`idle_summary.m`, new): per idle time 24 values: busy share (a bin 3 dB over the floor constant, the frame's duty rule; Cheema & Salous 2019, eq. 1), mean level, 10th/90th percentile and peak, bursts and complete bursts, their summed lengths and squares, the gaps between bursts, contrast and ripple (Grimaldi et al.), the antennas' busy-bin levels and their spread, the first complete burst's start, the observed time. `extract_closed_loop_frames.m` computes it for every run (F.idle, F.act_idle, F.idle_R, F.idle_ctx, F.idle_on), so the dataset, the pools, the detector blocks, the latency and the console read the same record.
- **Carried through:** A5 (`run_dataset_sweep.m`: dataset.idle, act_idle, idle_amb), A6 (`extract_spectrograms.m`), B1 (`prepare_data.m`: splits and splits_fresh), B4/B4s (`detector_block.m`), the pools (`pool_cell.m`: Q.idle, Q.act_idle; `rekey_pools.m`), the episodes (`link_env.m`: obs.idle), the fusion (`fuse_classes.m` 'windows'), the closed loop (`policy_monitor.m`: a window of the records beside the others), the live console (`episode_cycle.m`, `demo_gui.m`), KPI 7 (`measure_latency.m`: the record's computation timed inside 'features').

### O2. Branch cues and the level step in the fusion (`window_cues.m`, new)
Beside temporal_evidence.m's 9 columns (unchanged, as is the agent's state), the fusion's row gets 42 columns from the same window: 16 branch cues (the weakest antenna of the window against the others: the others' K and the weakest's K less it, the moment method of Aoki & Honda 2025, eq. 2; spreads and their contrast; correlation with the others; the offset's trend, largest change, range, ends and best split; the others' common slope and residual spread, the attitude's pattern; mean est_margin and sinr_gap; the others' spread), 5 step cues (the best split of the window on the combined level of all antennas and on the monitor's Eb/N0 estimate: t statistic with the pooled spread floored at 0.5 dB, size, age) and 21 idle cues (the latest idle time and the window's: busy share and its spread, burst rate, burst length and its coefficient of variation, the gaps' coefficient of variation, the spread of the intervals between successive idle times' first bursts, levels, contrast, ripple, the antennas' spread). Sources as cited in the file: Willgert (US 8,548,029, Table 1), Heath (US 10,404,368, Table 2), Aoki & Honda 2025, Sun et al. Part IV, Xie et al. 2021, Grimaldi et al. 2019, Rayanchu et al. 2011, Cheema & Salous 2019. The antenna's place in the array is not read: D83's far-end rule is a stated assumption (no source says which antenna the airframe hides), so a cue on it would learn the model's assumption.

### O3. Per-cycle labels for the gated threats (`threat_active.m`, `fusion_target.m` and every reader)
With idle sensing the system observes the whole decision cycle, the idle time before the frame and the frame: a gated threat (the WLAN, the sweeping jammer, a combination holding one) is labelled in a cycle while it is on the air anywhere in it, act > 0 or act_idle > 0 (labels by what is on the air, proposal mitigation 3, now over the decision cycle). The first frame of a run has no idle time before it and keeps its own share. The noise bursts are labelled in every frame already (a burst lands in every frame). Readers: the dataset (A5), `detector_block.m` (B4, B4s), `det_frames.m` (the edge map's DET), `link_env.m` (K.on: a threat episode is one with the threat on the air in a frame or an idle time). The dataset's cell sizes follow (`benign_hit_share.m`, `sweep_hit_share.m` per cycle; the frame rule without idle sensing).

### O4. Fault against shadowing under an emitter of opportunity (`emitter_idle.m`, `emitter_reading.m`, new): per condition, beside KPI 1, never in it
A faulty connector attenuates everything its antenna receives; the airframe hides an antenna from the directions above its belly's horizon, so an emitter outside that region reaches the shadowed antenna like the others, and one inside it is hidden too (D86 item 2: `emitter_idle.m` draws the emitter's azimuth over the full circle and shadows it by the airframe). With an emitter in the band during the idle time, the antenna weak on our signal is also weak on the emitter for a fault, and, for shadowing, only when the emitter lies inside the hidden region. The thermal floor alone carries no such cue (a matched attenuator at 290 K keeps it; against an antenna temperature below 290 K it rises by at most about 1 dB with the 5 dB noise figure, inside the +-2 dB calibration error). A5 adds, for antenna-fault and airframe-shadowing sub-runs only, the idle records with a WLAN of the threat block's packet law at a duty uniform in 4.6-11.5% (Cheema & Salous 2019, Table 6, measured 2.4 GHz channels) and its own Rician channel, at INR 0, 10 and 20 dB (`p.amb_inr_db`; Cheema & Salous's busy threshold, -97 dBm, is about 11 dB over our -108 dBm floor). B3 (`eval_detector.m`) fits a two-class reading on the validation split's fault and shadowing frames (the branch cues with and without the emitter cues) and prints it on the test set per condition with its intervals (metrics.emitter). It is never the default link, never in the labels or KPI 1, and holds only where such an emitter is on the air. Stated: the emitter is added to the idle time only; its packets inside our frames are not simulated.

## Sources and derivations
- Grimaldi et al. 2019 (V7_Grimaldi2019, arXiv v3): CC2420 RSSI register a 128 us moving average (Sec. II-B), sampled at 18.5 kHz with 1 dB resolution (Sec. III-A, Table III: Ts 54 us), the burst features (length, mean power, crest, ripple), WLAN identified at 89.2-96.4% for bursts with INR of 20 dB and more (Table IV).
- Rayanchu et al. 2011, Airshark (IMC): duty cycle and pulse timing signatures (F3, F5).
- Cheema & Salous 2019 (Electronics 8, 1011): duty cycle, eq. 1; busy threshold -97 dBm, 10 dB over the measured noise floor (Sec. 5); 2.4 GHz channel duty cycles 4.6-11.5% (Table 6); gamma idle windows of shape 0.49 (Tables 4-5, the threat block's WLAN law already).
- Wollenberg et al. 2012 (MSWiM): WLAN frames 0.268-3.2 ms, occupancy 5-86% (the threat block's law, unchanged).
- AD9361 data sheet Rev. F, Table 1: RSSI accuracy +-2 dB (the calibration error, unchanged); one RSSI per receive chain (p. 33).
- Sun et al., Part IV (IEEE TVT 66(9), 2017), Fig. 12: K about 15 dB outside an event, -16 dB inside; Aoki & Honda 2025, eq. 2: the moment K; Willgert US 8,548,029 Table 1 and Heath US 10,404,368 Table 2 (as in temporal_evidence.m).
- Xie et al. 2021 (survey, JSAIT), Theorem 1 and the CUSUM/GLR family: the mean-shift test; here its two-sample form over the window.
- Derivations: the RSSI's spread Gamma(M, 1)/M, M = B T; the matched attenuator's noise, T_A / L + T0 (1 - 1/L) against T_A, with the 5 dB noise figure (T_rx 627 K): +0.0 / +0.31 / +0.57 / +0.94 dB for T_A 290 / 200 / 135 / 50 K at L = 5 dB, at most +1.32 dB at 31 dB; the idle bins, (20 ms - frame - delay line) / 54 us = 357; the per-cycle share of the sweeper, min(1, (5.25 ms + 20 ms) / T) over T in 20-83.5 ms.

## Tests (`code/tests/test_core.m`)
New: `test_idle_record_bit_identical` (WLAN and WLAN + noise bursts: frames, act and act_comp bit-identical with and without the recording; the record from the second frame on), `test_idle_rssi_quiet_slot` (jamming, WLAN, tone, jamming + antenna fault: the last idle bin against the frame's own quiet-slot IoT, median within 0.5-1 dB; the faulty antenna's emitter more than 10 dB down; the reactive jammer silent in the idle time), `test_idle_emitter_attenuation` (an emitter reaches the faulty antenna the fault's 18 dB down, the shadowing flight's antennas alike), `test_idle_summary_and_cues` (a quiet channel, a continuous jammer, a sweep's one dwell length, WLAN packets' spread lengths; no record gives zeros), `test_window_cues_branch_and_step` (the fault's K and spread against the shadowed branch's; a step's t statistic, size and age; no antenna-index cue), `test_threat_active_cycle` (the per-cycle rule, the frame rule without idle sensing, the per-cycle shares), `test_monitor_idle_window` (the monitor's fused probabilities equal fuse_classes.m's with the idle records). Updated: `test_seed_streams_disjoint` (purposes 'idle', 'amb'), `test_sweep_hit_share` and `test_dataset_balance` (the frame rule without idle sensing, the per-cycle shares with it), the fusion's row size in `test_fusion_current_frame`.

## Results

### The recording moves no draw; the idle model reads the run's own field
- Same flight with and without the recording (WLAN, WLAN + noise bursts): received IQ, act and act_comp identical to the last bit (`test_idle_record_bit_identical`; scratch check over three flights each).
- The idle model's last bin (meas off, the calibration error on) against the frame's own quiet-slot IoT, three flights per threat at 9 dB, median / 90th percentile of the absolute difference: jamming 0.26 / 0.64 dB, tone 0.12 / 0.68, WLAN 0.30 / 0.91, spoofer 0.47 / 1.78, sweeper 0.18 / 0.45, jamming + antenna fault 0.28 / 0.73, reactive jammer 0.14 / 0.35, clean link 0.15 / 0.35, antenna fault 0.19 / 0.38. The noise bursts (2.2 / 18 dB; WLAN + noise bursts 0.82 / 4.4) switch within microseconds, so the 128 us average and the 32 us slot are not the same quantity sample by sample; their schedule is the block's own and their duty matches (the prototype: on-share 0.32 / 0.66 / 0.56 / 0.77 for duties 0.32 / 0.67 / 0.56 / 0.77).

### The measured gains with the integrated code (weak_v2 validation data)
The weak_v2 data (6 828 sub-runs, D84 model, seeds 4.0-5.1 M) with the detector retrained there (folds 1-4, best epoch on fold 5); every sub-run's idle time recomputed by this branch's `idle_rssi.m` from the run's own draws and the prototype's recorded schedule, the fusion of this branch (`fuse_classes.m`, `window_cues.m`), N and lambda chosen by the same 5-fold sub-run-grouped CV on folds 5-6 (1 872 sub-runs, 39 312 frames); fold 8 (606 extra sub-runs: fault, shadowing, path loss 4 and 7 dB, WLAN) applied, never fitted on. Recall [95% bootstrap over sub-runs]:

| class | before (D84 fusion) | prototype (idle + branch + step) | integrated, frame labels | integrated, per-cycle labels (O3) |
|---|---|---|---|---|
| none | 96.6 [96.1, 97.0] (precision 88.4) | 97.3 | 97.4 [96.8, 97.9] (94.4) | 96.7 [95.9, 97.4] (91.6) |
| jamming | 98.4 | 98.1 | 98.3 | 98.3 |
| noise burst | 99.6 | 99.7 | 99.5 | 99.4 |
| reactive jamming | 99.8 | 99.9 | 99.9 | 99.8 |
| path loss | 65.3 [60.4, 70.1] | 84.4 | 84.7 [81.5, 87.7] | 84.7 [81.4, 87.6] |
| spoofing | 99.6 | 99.0 | 99.0 | 99.0 |
| antenna fault | 52.3 [43.6, 60.3] | 66.1 | 63.7 [55.4, 71.7] | 62.5 [54.0, 70.2] |
| WLAN | 62.7 [57.1, 68.2] | 90.3 | 89.7 [85.7, 93.4] | 89.5 [86.1, 93.1] |
| sweeping jammer | 89.5 [87.3, 91.5] | 95.4 | 95.2 [93.8, 96.3] | 97.8 [97.2, 98.3] |
| tone jamming | 99.3 | 99.1 | 99.1 | 99.3 |
| airframe shadowing | 61.1 [54.3, 68.4] | 80.6 | 69.2 [62.9, 74.9] | 69.7 [63.3, 75.7] |
| macro-F1 | 85.45 | 92.41 | 91.23 | 91.18 |

- By level (per-cycle labels): path loss 4 / 7 / 10 / 13 dB and up 42 / 78 / 88 / 92-95%; WLAN -12 / -8 / -4 dB and up 61 / 88 / 92-97%; sweeper 93-99% at every level; fault 5 dB 31%, 8.7 dB 57%, 12.4-23.6 dB 77-87%, 27.3 / 31 dB 59 / 32%; shadowing 55-79% by level.
- Fold 8 (never fitted on), frame / per-cycle labels: fault 66.3 / 60.0, shadowing 64.4 / 71.4, WLAN 89.3 / 90.3, path loss 4-7 dB 66.9 / 66.8, the clean frames of those runs 89.6 / 94.4 (per-cycle labels resolve the WLAN cycles the frame rule called clean while the idle time held packets).
- **Per-cycle labels (O3):** the WLAN's labelled frames 11 511 -> 19 074, the sweeper's 6 146 -> 25 181; the sweeper's recall rises to 97.8% over its larger class, the WLAN's stays.
- **The integrated branch cues against the prototype:** the gap for shadowing (80.6 -> 69.2%) is the antenna-index cue alone, left out on purpose (D83's far-end rule is a stated assumption, no source says which antenna an airframe hides, so the cue would read the model's own assumption). Added back on the same data and CV: shadowing 78.4% [72.1, 84.0], fault 65.1%; the prototype's per-antenna SINR cue adds nothing (shadowing 68.7%, fault 61.6%). Should a measured installation fix which antennas the airframe can hide, the cue is one column of `window_cues.m`.

### The fault-vs-shadowing reading per condition (O4, integrated `emitter_idle.m` and `emitter_reading.m` on the weak_v2 fault and shadowing sub-runs: fitted on fold 5, read on folds 6 and 8; 192 fault and 191 shadowing sub-runs read)

| condition (beside KPI 1, never the default) | antenna fault | airframe shadowing |
|---|---|---|
| no emitter (branch cues alone) | 77.2% [71.9, 81.5] | 72.7% [68.7, 76.6] |
| an emitter of opportunity at INR 0 dB (duty 4.6-11.5%) | 93.1% [90.3, 95.4] | 84.4% [80.9, 87.6] |
| at INR 10 dB (about Cheema & Salous's -97 dBm busy threshold) | 98.2% [97.4, 98.9] | 97.4% [96.2, 98.4] |
| at INR 20 dB | 98.5% [97.6, 99.2] | 98.1% [97.2, 98.8] |

The table was measured with an emitter the airframe did not shadow (D86 item 2 supersedes it; it is read again on the next A5). The two-class reading takes a lost branch as given (the detector's 'one branch lost' reading finds 92-97% of them, D83); it holds only where such an emitter is on the air during the idle time, which no library source measures at UAV altitude.

### Cost
- The idle model: 0.16 s per 20-frame sub-run on average over the 6 828 weak_v2 sub-runs (0.26-0.31 s with one emitter, 0.53 s with two recorded components, a few ms without an emitter), against 1.3-1.8 s for the sub-run's simulation on an unloaded machine: about +10% in A5 and in every stage that simulates frames (C1p, C1c, B4, B4s, the console). The record and the window cues add a few ms per cycle (KPI 7: inside 'features' and the policy). Simulating the idle time at the sample rate instead would push 77 200 rather than 2 752 samples per antenna per cycle through the threat and channel blocks (x29).
- Storage: 24 singles per frame (dataset, splits, pools: +96 bytes per frame); 15 more for the fault and shadowing frames of the dataset (O4).
- The fusion's row: 31 -> 73 columns (C = 11); the agent's state unchanged (temporal_evidence.m's 9 columns).

### Unit tests
`code/tests/test_core.m`, 129 tests (122 of the base, 7 new), one MATLAB process in a scratch copy of 3894940, 24.7 min: 128 pass. `test_rate_reduce_chip_level` fails as on the base (the detector-image level under rate_reduce with a 10 dB jammer is -0.93 dB against a 0.5 dB tolerance, d84_shadow.md), independent of this change.

### Smoke chain (scratch copy of 3894940, one MATLAB process, fresh data)
`run_stage('smoke', 'A0', 'A5', 'A6', 'B1', 'B2', 'B2F', 'B3n', 'B3', 'OOD', 'B4', 'B4s')`: exit 0 in 28.0 min (A5 14.6, B3n 3.7, OOD 2.4, B4 2.3, B4s 1.6). Then `run_stage('smoke', 'C1p', 'C1c', 'C1d', 'C2', 'C2e', 'C2g', 'C2u', 'EDGE', 'LAT')`: exit 0 in 363.4 min (C1p 322.9 against 260.6 for d84-shadow's smoke, C1c 33.8, C1d 0.1, C2 1.9, C2e 0.5, C2g 0.6, C2u 0.5, EDGE 1.7, LAT 1.5).
- A5 printed the per-cycle shares: the sweeper is on the air in 55.8% of the decision cycles, the WLAN in 94.1%.
- B2F selected N = 8 on the smoke.
- B3 printed the emitter-of-opportunity table on both test sets.
- C1p: airframe shadowing was on the air in 130 of the 130 flights of its cells.
- LAT, median / p95: the features (link features and the idle record) 0.22 / 0.26 ms; the deployed cycle 5.3 / 6.0 ms; the whole cycle on one CPU core 9.8 / 10.7 ms.
- Warnings: only the smoke's known ones (the DQN gate; no KPI 1 threshold for KPI 6).
- The console (demo_gui.m) started on the smoke data and loaded it in 31 s. Its live run and episode check had not reported when this was written.

Smoke numbers are not results.

## Stated, not backed by a source
- The RSSI's rate, averaging time and step are the CC2420's that Grimaldi et al. read (18.5 kHz, 128 us, 1 dB); the AD9361 data sheet in the library gives its RSSI accuracy (+-2 dB, used) but not its rate, averaging or step.
- The RSSI's spread as Gamma(M, 1)/M (Wilson-Hilferty), the delay line's taps adding in power for a noise-like emitter over a bin.
- The per-cycle label: on the air anywhere in the cycle, no minimum time (the main session's definition, mitigation 3 over the cycle); the first frame of a run by its own share.
- The emitter of opportunity: the duty of a ground site's 2.4 GHz channels (Cheema & Salous), INR conditions bracketing their busy threshold; its packets inside our frames are not simulated; no source measures such emitters at UAV altitude.
- The antenna's place in the array is left out of the fusion (D83's far-end rule is itself a stated assumption).

## Open risks
- `idle_rssi.m` replicates the threat block's first draws in threat_script's order (a faulty antenna, each component's own draws and sinusoids, the chain errors, the delay line's taps). A branch that adds or reorders draws in the threat block (the receiver branch, the onset branch) must keep that order or update `idle_rssi.m`; `test_idle_rssi_quiet_slot` fails when they part (the median difference rises to several dB). The edits here keep to threat_script's schedule recording and two local functions.
- The onset branch's attitude: `idle_context.m` reads the Att block's layout [GCS direction, elevation, roll, pitch, wobble]; the interferers' channel takes only the lever-arm phase from the roll (no attitude gain on interferers in the model), so a per-frame roll changes little there, but the block's layout must stay or `idle_context.m` follows it.
- The per-frame CNN now learns per-cycle labels: about three of four of the sweeper's labelled frames carry no in-frame evidence (its window misses our frame); the per-frame reading changes meaning, the fused decision carries those cycles through the idle cues.
- The first frame of every run (dataset, pools, console) has no idle record, as the temporal windows start partial.
- Left where they were: the WLAN at -12 dB and Eb/N0 0-3 dB (about 61%: its packets lie about 9 dB under the floor, under a 1 dB RSSI step), the 4 dB path-loss step (42% against an ideal known-onset test's 72%), antenna fault 63-66% and shadowing 69-72% in the window (their bound from the receiver's measurements of our own signal is about 71% and 83%, research weak_v2; the emitter-of-opportunity reading above is the conditional way beyond it).
- `test_rate_reduce_chip_level` fails as on the base (the detector-image level under rate_reduce with a 10 dB jammer, -0.93 dB against a 0.5 dB tolerance; d84_shadow.md).
