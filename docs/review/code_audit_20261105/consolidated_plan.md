# Consolidated cleanup plan (5.11.2026, verified)

Inputs: `audit_rules.md`, the four audits, `verify_run1.json` (decision, detection_link, eval_gui; harm lens then correctness lens) and `verify_run2.json` (tests/scripts/folders; harm, correctness). Spot checks made while writing (read only): `code/tests/test_d121.m:162`, `code/decision/run_cache.m:53`, p3 `profile.json`, `ood_k2_rules.m:84-100`, the DECISIONS heading order, the docs repo against origin. Lens shorthand below: H = harm, C = correctness.

## 1. Summary

- Rows: 59 cleanup rows. **13 accepted** (2 of them confirm a "leave as is" stance: P11, P14), **31 accepted with conditions**, **7 rejected**, **7 dropped** (a "wrong" verdict), **1 reclassified** as a defect fix (P9 -> DL-2). 3 numeric/orchestration candidates (N1-N3) kept out of the cleanup.
- Defects: **9 real** (7 confirmed by both lenses, 2 found by the verifiers: `test_d121.m:162` and cross-slot hand-runs), 5 split verdicts (latent or text-only), 1 not a defect (docs push: already in sync with `origin/v7-docs-d91`, checked 18:34 on 5.11 and again now, 0/0 at feb671f; the "13 commits ahead" claim is out of date).
- Lines (estimated, not counted after edit): about 1,300 removed (code ~540 incl. 198 in three retired diagnostics, comments ~400, tests ~250, scripts ~150) and about 3,000 moved out of the three largest files (build_threat_model 2,209, demo_gui 2,720, edge_map 1,861 lines). 22 dead script files archived.
- Run hours (all estimated, nothing measured yet; every B5 item starts with a measurement): pool builds of threatened cells (C1p and new closed-loop test pools) 3-10 h per chain (P1) + up to 1.5 h (P8); A4v 0.7 h (case loop only) to 5-6 h (with V12c/V13) (P2); each A5-type set build about 2.5 h wall if cores are free (P3, tier 2); C2 0.5-1.6 h only if the profiler shows >= 1 % (row 12); B3a 3-10 min (P5); EDGE about 1 min (E4) + up to 20 min unproven (E5). For P1-v2 (D119.3: C1d, C2, C2e, readers, and with detector fixes new sets) the relevant ones are row 12, P1, P3, P8, E4/E5.
- run_cache: it hashes `code/**/*.m` except `code/tests` and `code/legacy` (run_cache.m:53), so every non-test code edit invalidates cached C2/C2g/C2u runs. That is acceptable between chains. Today it costs nothing: profile 3 has no `run_cache` key and neither live tree has `data/run_cache`; it matters only if P1-v2's protocol turns it on (then it starts cold, which its new sets need anyway).
- Nothing is applied before profile 3's KPI stage ends (about 18.5-21.5.11; workers read code live, past bug 13). Work on branch `cleanup-2111` (cut from the v7-p3 tip after KPI) in a new worktree, then merge into v7-p3 and v7-dev (keeps code identity) before P1-v2's protocol is registered.
- Order: B8-now (docs, today) -> B0 -> B1 -> B2 -> BD -> B3 -> B5 (P1, P2, P8, P5, row 12, E4) -> B6 -> B7 -> final deploy queue round -> B8-rest. Tier 2 if the 21-23.11 window has room, else after P1-v2: B3w, B4, P3, E5. Tier 1 is about 42-60 h of work plus machine time.

## 2. Row decisions and batches

### 2.0 Decision per row

Equivalence harnesses named in the conditions are defined in 2.1 (EQ-G, EQ-P, EQ-E, EQ-S, EQ-K, EQ-GUI, SUITE).

**Decision layer (audit_decision.md)**

| row | what | H / C | decision | conditions or reason | batch |
|---|---|---|---|---|---|
| 1 | shared `ternary` (decision, dev) | unsafe / unsafe | ACCEPT WITH CONDITIONS | (1) one `code/ternary.m`; (2) never touch the D111-frozen `ood_k2_run.m`, `ood_k2_rules.m`; (3) `train_dqn.m` keeps its local copy (test_d107.m:874-877, 963, 1116 use it as a fixture); (4) `evaluate_policies.m` only in B3w; (5) unit equality on logical/char/cell/struct/empty inputs, SUITE, EQ-G | B3, B3w |
| 2 | shared `cp_upper` | unsafe / unsafe | ACCEPT WITH CONDITIONS | (1) `cp_upper(k, n)` = today's 1-at-n=0 form, `cp_upper(k, n, true)` = NaN-at-n=0 form; every caller keeps the form it has; (2) `train_dqn.m` and `aprime_admit.m` keep their local copies (test_d107.m:875-888 requires both present and equal); (3) `evaluate_policies.m` only in B3w; (4) `surv_grid.m` `cp_up` is another function, leave; (5) unit test old vs new for n = 0..60, k = 0..n, both forms, `isequaln`; EQ-G | B3, B3w |
| 3 | shared `cat_struct` | unsafe / wrong | DROP | `experiment_unknown_threat.m:192` has an `isempty(R)` branch the other three lack; "four identical bodies" is false | - |
| 4 | `leave_out_episodes` for C2g/C2u | unsafe / unsafe | ACCEPT WITH CONDITIONS | (1) do not reuse `policy_episodes.m` (draws `randi` per batch); (2) update test_d107.m:762-773 and test_lb.m:726-742 in the same commit, adding exactly the removed lines to their lists; (3) unit: specs and `mark` old vs new on `RandStream('mt19937ar','Seed',300+ci)` for every C2g combination and C2u threat, split 0 and > 0, `isequaln`; (4) EQ-G with all entities (B0-3; run_stage alone covers only the first entity) | B3w |
| 5 | `clean_wide_specs` in evaluate_policies | unsafe / unsafe | ACCEPT WITH CONDITIONS | (1) update test_d107.m:762-773, test_lb.m:674 and test_core.m:11507-11520 in the same commit; (2) `isequaln(specs)` for CT and F6.CT, plus an assert that `PPw.ebno` has no NaN (the one case where `find(>= -Inf)` differs); (3) EQ-G through C2e | B3w |
| 6 | `kpi1_threshold` helper | unsafe / unsafe | REJECT | four of the most pinned files (test_core.m:8644 call text, test_d107.m:999-1000 undo patch, ~45 edge_map readers) and a workspace difference (`Md` cleared in two copies only) for three small blocks | - |
| 7 | `detector_setup` helper | unsafe / unsafe | REJECT | blocks differ (core3 insert, `D` kept alive, clears); test_core.m:6222 needs `nm = split_norm();` in three builders; these are the C1p/C1c builders (a slip costs days) for an unproven -40 lines | - |
| 8 | `file_sha256` | unsafe / unsafe | ACCEPT WITH CONDITIONS | (1) only the plain file hashes: core3_model.m:29, core_bw_rules.m:206, kpi6_fresh_marker.m:102, fusion_nogo.m:47, train_core_cnn.m:491; (2) never ood_k2_rules.m (frozen), dev/m_head.m (LF flag, hashes its own source as D110 provenance), eval_detector.m:787 (file_stamp), unk_write.m, policy_stamp, detector_id, run_cache, pool_checkpoint; (3) an error-id argument so `kpi6_fresh_marker:read` and `core_bw_rules:sha` stay; (4) digest old vs new on a 1-byte file, a CRLF text and a 100 MB file; test_core.m:11415-11480, test_lb marker tests, test_ood_k2 | B3 |
| 9 | `monitor_cf` | uncertain / safe | ACCEPT WITH CONDITIONS | (1) choose_drop_threshold.m only, train_dqn.m untouched; (2) a temp variable instead of `strsplit(...){2}`; (3) unit over the four monitor names; test_d121, test_deg_mode, test_wf_dec, test_d107 (undo_small); EQ-G (C1d) | B3 |
| 10 | `SM`/`CFGX` once per script | unsafe / unsafe | REJECT | about 15 test sites grep the literal `exist('SMOKE', 'var') && SMOKE` and `cfgc` text; readability only | - |
| 11 | `per_threat_rows`/`envelope` | unsafe / unsafe | REJECT | the pairs differ in more than mask and seed (unconditional vs `if any(mr)`, `RECsh` built inside the loop, two masks HV/HA); a two-mode helper in the C2e report for an unmeasured ~-50 lines plus three guard rewrites | - |
| 12 | persistent `decision_config`, `feature_index` lookup | uncertain / uncertain | ACCEPT WITH CONDITIONS | (1) MATLAB profiler first: one `rollout_policy('dqn_esc')` batch and 10 `dqn_train_run` iterations; implement only if the two functions are >= 1 % of step time; (2) `check_burst` stays where it is (registered rule input); (3) `rollout_policy` 64 episodes x 30 steps old vs new `isequaln`; EQ-G; test_wf_dec and test_core.m:9975 parity | B5 |
| 13 | dead guards in link_env | unsafe / wrong | DROP | only 294-295 and 435 are redundant; 332-334 and 446-455 are real checks; link_env.m is text-pinned (test_d107.m:848) | - |
| 14 | decision comment tags | unsafe / unsafe | ACCEPT WITH CONDITIONS | (a) tags only in files under no whole-text or parent-line test: aprime_admit, burst_candidates (keep "D78" where it names the decoder mode), choose_drop_threshold, holm_lower, unk_guard, unk_threshold, wf_options, dconf_step, core3_check, core3_model, fa_nothreat_on, build_policy_pools (check test_core.m:3628, 3632, 5820 neighbours), experiment_core_bw, dev_fec_gates, dev_fec_burst (check test_core.m:1986, 3847 first); not policy_monitor/policy_decide (test_lb.m:700-722 list their comment lines), not m_head.m, not train_dqn/evaluate_policies/experiments; (b) dropped: lines 91-114 document fa_nothreat, not the option files; (c) train_dqn.m:43 deferred to the next train_dqn edit that updates test_d107's off-view lists anyway; (d) main.m:128-131 timing comments fixed (safe alone). Proof: diff holds only `%` lines; SUITE | B2 |
| 15 | `append_lines` | unsafe / wrong | DROP | one-line sites, a helper adds lines; test_speed_envelope.m:543-551 pins the fopen/fprintf pair | - |
| 16 | `model_tag`, cached `p0` | unsafe / unsafe | REJECT | test_core.m:3628 pins the `MODEL_TAG` literal; caching `p0` changes the params_id guards' on-disk re-reads; the parse already fails loudly | - |
| 17 | reuse readings in sensitivity/s1g_step | wrong / wrong | DROP | already "do not do"; its premise is false (profile 3 sets `s1g_select` and `s1gc_select`, so s1g_step runs twice in C2) | - |

**Detection and link (audit_detection_link.md)**

| row | what | H / C | decision | conditions or reason | batch |
|---|---|---|---|---|---|
| P1 | cache idle channel arrays in idle_rssi | unsafe / uncertain | ACCEPT WITH CONDITIONS | (1) key = every ctx field except lev/cap/cal/gate (`isequal` on the struct or a hash of all fields) + every p field the cached block reads (carrier_freq, c_light, cycle_s, samples_per_frame, symbol_rate, sps, idle_rssi_hz, tdl_*, n_rx, ant_spacing_wl, wobble_arm_m, int_los_doppler, active_threat) + the threat composition (components, antenna_fault, benign_occ, chain_amp/phase); (2) cache passed as an optional 4th argument of `extract_closed_loop_frames` down to `idle_measure`; 3-argument calls unchanged; the `emitter_idle.m:50` path covered; (3) lifetime one `pool_cell` call, double precision; memory measured (120-240 MB per component per cell per worker expected) and inside the RAM budget with 6 workers (past bug 11); (4) measure first: idle_rssi share of a threatened run (D91 log: 0.52 of 3.28 s); (5) proof below (B5); no C1c benefit | B5 |
| P2 | parallel validate_phy (A4v) | uncertain / safe | ACCEPT WITH CONDITIONS | (1) keep the literal `evalc('build_threat_model(p)')` (test_core.m:2523-2527); (2) V11 after the case parfor; (3) workers through `pool_worker_init` (own CacheFolder, past bug 10), launched via `parallel_turn` with a RAM check, same thread mode as the serial reference; (4) parallelise V12c rows and V13 too, else the saving is ~40 min only | B5 |
| P3 | plan + parfor in run_dataset_sweep | unsafe / safe | ACCEPT WITH CONDITIONS (tier 2) | (1) the plan pass replays the global stream exactly: one `randi(2^26-1)` per build with `p.seed = []` and the `rand()` speeds, the hide-antenna retry included; assert the global stream state after the plan equals the old loop's; (2) all source-text tests pass unchanged (test_core.m 1854, 2504, 2523-2527, 2689, 4379, 4610, 4639, 4851, 5205, 5247, 7620, 7648, 7657); if one must change, stop; (3) `ds.iq` copied to a plain cell before the parfor; own CacheFolder; (4) do it only if an A5-type stage is ahead (P1-v2's new detector test set, D119.2) | B5 |
| P4 | split build_threat_model | uncertain / safe | ACCEPT WITH CONDITIONS | (1) generator files on the path, not `link/private/` (tests use `which`), or tests use full paths; (2) rx helper text read with `fileread`, CR stripped (core.autocrlf=true), quote escapes un-doubled; (3) header prose moved to docs; (4) repoint test_core.m:4773, 7468 and `dev/dev_rx_script.m`; tests reading the generated chart scripts (test_core.m:2334, 3216-3217, 3901-3902) pass unchanged | B4 |
| P5 | duplicate validation pass in compare_architectures | safe / safe | ACCEPT | keep the call text `fused_oof(sp.val, Pv, FZ.N, FZ.lambda, tv, fold, cls_names, tf, cues, FZ.FM);` and the name `Zv` (test_head.m:195-200, test_core.m ~7975) | B5 |
| P6 | A1/A3 builders and quick_ber | uncertain / wrong | DROP | quick_ber has a live caller (`validate_new_threats.m:22`); after E10 a narrowed re-proposal needs its own check | - |
| P7 | shared helpers (detection, link) | uncertain / unsafe | ACCEPT WITH CONDITIONS | (1) never the frozen ood_k2_run.m, ood_k2_rules.m, unk_write.m, nor train_dqn.m; (2) `macro_f1` keeps its name (test_core.m:8499 pins the call text; the string-label local in eval_unseen_snr.m:259 keeps shadowing); (3) drop `k_moment` (window_cues.m is in m_head's D110 SHA record) and `lowq` (one unfrozen copy left); (4) `sign0`, `load_norm` (same name) and `ternary` in the unfrozen files; (5) unit test per helper vs old body; test_core, test_head (443-502, 604, 685, 757), test_d107; EQ-P | B3 |
| P8 | lighter link_seed | uncertain / safe | ACCEPT WITH CONDITIONS | (1) time the removable part first; (2) RandomStream/SeedSource set at build (the build already calls link_seed at its end); per run only the three seed `set_param`; (3) any block_params cache is cleared by every build; (4) coordinate with P4 (same file) | B5 |
| P9 | explicit "output absent" in extract | uncertain / uncertain | RECLASSIFIED | behaviour change in error states: handled as defect DL-2 | BD |
| P10 | dead local `cvec` | safe / safe | ACCEPT | `git grep -w cvec` empty after; one model build | B2 |
| P11 | leave eval_detector/select_fusion sections | safe / safe | ACCEPT (no change) | - | - |
| P12 | parfor in extract_spectrograms | uncertain / wrong | DROP | compare_architectures does not call spec_image; the spec_image loop is ~11 of 26-42 min of A6, not the claimed saving | - |
| P13 | comment bloat (detection, link) | unsafe / safe | ACCEPT WITH CONDITIONS | exclude fusion_adopt.m (RULE_SHA, test_head.m:637-638), k2_1_screen.m and the other D111 files, window_cues.m, fuse_classes.m, fusion_cand.m, fuse_head.m (m_head D110 record); keep `severely degraded antenna connection` and `Simunek et al. 2011` in init_params.m (test_core.m:4971-4973); keep `EXT = '';` in fusion_pick.m (test_head.m:467-468); keep d91 design names that printed strings use (eval_detector.m:151-152, 596-600); trailing comments on code lines (eval_detector.m:130, 148) lose only the comment; header prose moved to docs. Proof: `git diff -w` shows only `%` lines; test_core, test_head, test_ood_k2, test_d121 | B2 |
| P14 | private RandStream for speeds | safe / safe (C: numeric) | ACCEPT (no change) | changes the speed sequence; see section 4 | - |

**Evaluation, GUI, diagnostics (audit_eval_gui.md)**

| row | what | H / C | decision | conditions or reason | batch |
|---|---|---|---|---|---|
| E1 | shared `ternary` (evaluation, gui) | unsafe / unsafe | ACCEPT WITH CONDITIONS | (1) ebno_rows, edge_map, lect_kpis, speed_reading, weak_points; demo_gui's `ternaryTxt`/`ternaryStr` renamed to `ternary`; (2) `measure_all_kpis.m` only in B3w (test_d107.m:765-775 compares it with the base text); (3) no "no copy left" test (contradicts test_d107.m:875); (4) edge_map: check the pol_layers cut (test_core.m:930-961, "up to the next function") is unaffected; (5) the parent-commit tests that load old rule_based_policy/evaluate_policies/boot_cluster beside the new code pass; EQ-K, EQ-E, EQ-GUI | B3 |
| E2 | `file_time`, edge text, verdict-symbol helpers | safe / uncertain | ACCEPT WITH CONDITIONS | non-colliding names in `evaluation/private/` (no `write_lines`: experiment_core_bw.m:1070 has another; no plain `vsym`: edge_map.m:1699 differs); diagnostics copies stay (private/ is invisible to them); byte-compare kpi_summary.txt, edge_map.txt, edge_summary.txt; SUITE incl. test_ood_k2, test_wf_dec | B3 |
| E3 | cache of six PP fields for WEAK | safe / uncertain | REJECT | no saving on a chain run (WEAK loads the pools once per chain); a new mtime-keyed cache file is a stale-data risk (`mv` keeps mtimes; past bugs 5, 16) | - |
| E4 | recomputed edge verdicts | safe / uncertain | ACCEPT WITH CONDITIONS | (a) and (b) only; drop (c) (boot_cluster has 54 call sites incl. parfor workers and a parent bit-identity test, test_head.m:573-590); (a) assert `vn > 0` so today's error stays an error; keep the pins test_core.m:7020, 899, 6083-6084 and the pol_layers header (930-961); EQ-E with `isequaln` on EM, EDGE_NUM, FT, CF, CS, VAR; about 1 min | B5 |
| E5 | parfor over det_frames | uncertain / unsafe | ACCEPT WITH CONDITIONS (tier 2) | (1) `tic` per call first; go on only if the loop is > 10 min of EDGE; (2) pass a PP copy without pools (no 14 GB broadcast); (3) keep or update the test_core.m:6084 pin; (4) one-cell worker-memory run; (5) `isequaln` of FT.det_k, det_n, detb_k, OC against the serial run; EQ-E | B5 |
| E6 | split edge_map | uncertain / uncertain | ACCEPT WITH CONDITIONS | (1) after B0-1; (2) all local helpers to function files first; (3) one-line check that a script in `evaluation/private` is callable by name from edge_map.m, else a non-private folder; (4) the 17 source-reading tests and test_core.m:942-948, 6083-6084, 7020 pass on both layouts; EQ-E | B4 |
| E7 | split demo_gui | uncertain / uncertain | ACCEPT WITH CONDITIONS | (1) after B0-1; (2) pinned functions (simRun/applyMitigation, runEpisode, epPools, epBuildPool, boot block) found by `src_of`; (3) EQ-GUI from a bundle or export, never from a live tree (the GUI writes params.mat) | B4 |
| E8 | runOneRun helpers | safe / uncertain | ACCEPT WITH CONDITIONS | keep the differences (lead-in `leadC` with `nan(n,0)` fallback vs `F.bch`; `thermal_nv(pl)` vs `thermal_nv(p)`; the `randi` at 1104 in its place; `dqn_ms` times only the decide); drop scenarioParams' unused 3rd output; EQ-GUI with a fixed seed checking obs fields and the printed latency line; test_core.m:145-152 | B3 |
| E9 | dead `NWP` | unsafe / unsafe | ACCEPT WITH CONDITIONS | keep `pl = [];`, drop only `NWP` (and `NWP = 0` in the SMOKE branch) with no empty `if` left; test_core.m:1772 and test_smoke (SURV smoke) | B2 |
| E10 | retire 3 stale diagnostics | safe / safe | ACCEPT | `git rm` of validate_new_threats.m, diagnose_antenna_fault_reward.m, diagnose_reactive_jamming.m (198 lines) on Adi's OK (git history keeps them); grep 0 callers again at implementation; SUITE. Removes two params.mat writers (EG-3) | B2 |
| E11 | one pool-open helper | safe / uncertain | ACCEPT WITH CONDITIONS | helper returns the onCleanup and asserts `nargout == 1`; every caller holds it to stage end; `NWP = 0` SMOKE semantics and `pl = []` unchanged; builder pins (test_core.m:3628-3639, 6222, 6270, 6336) pass; real one-cell pooled run of SURV3 and of one pool builder with the `parallel_turn` take/give pair and the turn file held to stage end | B3 |
| E12 | header comment bloat | safe / uncertain | ACCEPT WITH CONDITIONS | Adi agrees (the headers carry registered reading definitions); text moved to docs, not deleted; edge_map.m header in B2; measure_all_kpis.m header and tags only in B3w (test_d107.m:765-775 base text); SUITE and every `fileread(which('edge_map'|'measure_all_kpis'))` test | B2, B3w |
| E14 | `src_of` source-reading helper | safe / uncertain | ACCEPT WITH CONDITIONS | SUITE identical on the unsplit layout; a test that `src_of` equals `fileread` for unsplit files; an explicit decision for each order/adjacency assert (test_wf_dec.m:798, test_core.m:11498-11499, 942); handle test_d107's `read_lf`/`between_text` cuts and test_core.m:930-961 | B0 |

**Tests, scripts, folders, docs (audit_tests_scripts_folders.md)**

| row | what | H / C | decision | conditions or reason | batch |
|---|---|---|---|---|---|
| T1 | shared test helpers | uncertain / safe | ACCEPT WITH CONDITIONS | merge only byte-identical bodies; keep local: test_smoke `write_text` (fwrite), test_lb `fixture_off` (cell) and `parent_dir`, test_d121 `pb_fixture_off`/`pb_parent_dir`, test_ood_k2 `mon_pp` (other signature), `mk_obs`/`trace_world`/`monitor_run`; the shared parent copy gets a new name (e.g. `parent_copy_rev`) with test_core's one-line default-rev wrapper; keep `clear('clean_ber_ref')`; after B0-4 | B1 |
| T2 | `clean_ref_fixture`, `tmp_workdir` | safe / safe | ACCEPT | order: cd into tmp, mkdir data, save, `clear('clean_ber_ref')`; 3-field struct; assert clean_ber_ref finite | B1 |
| T3 | two tests that call no project code | safe / safe | ACCEPT | replace by a source pin of measure_all_kpis.m:219-226 (rather than delete) | B1 |
| T4 | wire the seven unqueued test files | unsafe / uncertain | ACCEPT WITH CONDITIONS | (1) B0-2 first; (2) each of the seven files PASS in a fresh `git archive` export with V7_GIT_REPO set under the queue's INIT (check test_speed_envelope.m:617 params.mat, test_head data/, parses_ok path); (3) wrapper tests inside test_core only; never drop the two nested wrappers (a removed name blocks the verdict); (4) `pair()`/`verdicts()` of deploy_tests2 on the 4.11 logs show no removed-test; (5) count floors set after T3 and T6 | B1 |
| T5 | per-test duration tag | safe / safe | ACCEPT | tag `V7DUR` (no prefix overlap with V7TIMEOUT); VERDICT lines unchanged on the 4.11 logs; runner line edit after the takeover ends | B1 |
| T6 | redundant parses_ok | safe / safe | ACCEPT | keep one `parses_ok(tc, 'test_d121')` | B1 |
| T7 | one tree-text cache | safe / safe | ACCEPT | cache raw text with folder and name in setupOnce; each scan keeps its own filter | B1 |
| S1 | fold the `_mt` wrapper clone | uncertain / safe | ACCEPT WITH CONDITIONS | keep a stub `v7_d91_gated_run_mt.sh` that sets `V7G_THREADS=default` and calls the wrapper (callers: g0_mt_run.sh, p1r_launch.md, post_c2e_commands.md, post_c2e_runbook.md, gap_audit.md, g0_mt_dispatch.md:34, n6_corebw_launch.md:141); default single-thread (run_cache hashes maxNumCompThreads); Adi OKs merging the approval boundary (the runbook's standing OK names the `_mt` copy); `D91_GATED_DRY=1` diff for three slots | B6 |
| S2 | shared lib_d91.sh | uncertain / wrong | DROP | after S3 only deploy_tests2 keeps these functions; nothing left to share | - |
| S3 | archive dead queue scripts | safe / safe | ACCEPT | move scripts only (no `.log`: deploy_tests2.sh:63-64 reads the tests4 base/tip logs); 9 `*.retired_by_d91`; `tests2_after.sh` first (it would launch the live queue); after the takeover's final phase | B6 |
| S4 | remove the p2 track from the takeover | unsafe / uncertain | REJECT | track code is parametrised and file-gated, the harness has 105 p2 references, and the script has no use after the chain; archive it instead | - |
| S5 | slot table for the wrapper | uncertain / unsafe | ACCEPT WITH CONDITIONS | mapping table only (`slots.conf`: name -> profile -> path), built with the B7 move; `D91_GATED_DRY=1` for three slots; no cd check (it would block today's cross-slot practice; the hole is defect VF-2) | B6, B7 |
| F-plan | one main folder | uncertain / uncertain | ACCEPT WITH CONDITIONS | section 5 | B7 |
| docs-refresh | README/ROADMAP/LOG | - / safe | ACCEPT | section 6; keep protocols and `.txt` copies in the code branches (test_smoke, test_core.m:6470; ood_k2_rules reads `docs/d91_fresh3_read_*.txt`); main.m:398 adjusted if the stale four go | B8 |
| notes-bak | 64 `.bak*` notes | - / safe | ACCEPT (delete after Adi's OK) | rollback pointers in prose only (STOP_SOFT.md:53, p1r_launch.md:19/371, p1r_launch_fixes.md:6) | B7 |

### 2.1 Proof harnesses used by the batches

All runs on scratch worktrees under `worktrees\scratch\` (never a live tree; past bug 10), one MATLAB at a time with a free-RAM check (past bug 11), in the chain's thread mode (`-singleCompThread`, as the wrapper). "Old" = the base commit (`cleanup-base`, the v7-p3 tip after KPI); each batch is also compared with its predecessor commit.

- **SUITE**: all 10 test files (`test_core`, `test_d107`, `test_d121`, `test_deg_mode`, `test_head`, `test_lb`, `test_ood_k2`, `test_smoke`, `test_speed_envelope`, `test_wf_dec`), all PASS, with the V7RESULT name list diffed against the baseline (only the names a batch adds or removes on purpose may differ).
- **EQ-G** (decision layer): `run_stage('smoke','C1d','C2','C2e','C2g','C2u')` plus the all-entity C2g/C2u route of B0-3 with `CFG.smoke_all_entities = true`; seeds are fixed by the code. Compare with `isequaln`, fields by name: `data/trained_dqn.mat`, `data/drop_threshold.mat`, `results/policy_evaluation.mat`, `results/combo_generalization.mat`, `results/unknown_threat_policy.mat`, `data/unknown_threat_agents.mat`; `results/*.txt` byte for byte with `Generated:` and `(x min)` masked.
- **EQ-P** (pools): `run_stage('smoke','C1p','C1c')`, `isequal` of every field of the smoke `data/policy_pools.mat` and the clean pools.
- **EQ-E** (edge): `edge_map` in SMOKE mode (REPS = 1, B = 400): `isequaln` of EM, EDGE_NUM (and FT, CF, CS, VAR where named); `edge_map.txt`, `edge_summary.txt` byte for byte (masked).
- **EQ-S** (survivability): `run_stage('smoke','SURV','SURV3')`, test_core.m:1772, test_smoke.
- **EQ-K** (readers): `measure_all_kpis`, `result_status`, `export_report_numbers` on the test_core fixtures (2788, 9081) and on a copy of profile 3's final `results/`: `kpi_summary.txt` byte-identical (masked).
- **EQ-GUI**: GUI capture from `gui-bundle` (`demo_gui('rx4')`), one fixed scenario and seed, before and after; screenshots plus the printed log lines diffed.
- **UNIT**: a new `code/tests/test_cleanup_equiv.m` wrapped into test_core (T4 pattern) holding the old-vs-new unit tests named in each batch; old bodies are taken from the base commit with the shared parent-copy helper.

### 2.2 Batches (dependency order)

**B0. Test infrastructure prerequisites** (tests only; outside the run_cache hash)
- Items: B0-1 = E14 `code/tests/helpers/src_of.m` and the switch of the source-reading pins of edge_map, demo_gui, measure_all_kpis, build_threat_model (4773, 7468); B0-2 = fix `test_d121.m:162` (`git show` without `-C`, no V7_GIT_REPO fallback, exit status ignored): use the parent-copy helper with `-C` and the fallback and assert status 0; B0-3 = all-entity harness `code/tests/helpers/stage_smoke.m` that runs C2g/C2u through test_core's `run(name)` route with CFG in the caller's workspace (no production edit; DEC-1); B0-4 = find how parent_copy tests pass in a git-less export (V7_GIT_REPO is set nowhere, yet 314/314 passed on 4.11): run one parent_copy test in a `git archive` export with and without V7_GIT_REPO; B0-5 = baseline capture of SUITE, EQ-G, EQ-P, EQ-E, EQ-S, EQ-K, EQ-GUI on `cleanup-base` into `worktrees\scratch\cleanup-baseline`; B0-6 = branch `cleanup-2111` and its worktree.
- Files: `code/tests/helpers/` (new), test_core.m, test_d107.m, test_head.m, test_wf_dec.m, test_d121.m.
- Proof: SUITE identical before/after on the unsplit layout; new test `src_of == fileread` for every unsplit file; test_m_files_parse passes with the helper folder; test_d121 PASS in an export with V7_GIT_REPO set and a clear error without it (not a false compare).
- Model: Opus, high. Estimate 5-7 h.

**B1. Tests-only cleanups**: T1, T2, T3, T4, T5, T6, T7.
- Files: the 10 test files, `code/tests/helpers/`, `uav-gcs-logs\v7_d91_deploy_tests2.sh:131` (T5 runner tag; after the takeover ends).
- Proof: SUITE before/after on one tip (expected name changes: T3 and T6 removals, T4 wrapper additions, listed in the commit); a git-less export run with V7_GIT_REPO (T1, T4); `pair()`/`verdicts()` of deploy_tests2 on the 4.11 log set: same VERDICT lines, no removed-test; no production code touched, so no EQ run needed.
- Model: Opus high for T1 and T4 (git fallback, release verdict); sonnet medium for T2, T3, T5, T6, T7. Estimate 5-7 h plus about 2 h machine (one queue round, test_core about 54 min twice).

**B2. Dead code and comment bloat**: P10, E9, E10 (on Adi's OK), row 14 (a)(d), P13, E12 (edge_map header only).
- Files: link/build_threat_model.m (cvec only), evaluation/map_survivability_boundary.m:108-110, diagnostics/ (3 files out), main.m:128-131, the row 14(a) and P13 file lists, edge_map.m:2-118 (comments), the docs file that receives the moved header text.
- Proof: a check that every changed line of the comment rows is a `%` line or blank (`git diff -U0` filter); mtree parse; SUITE; EQ-S for E9; one model build for P10; `git grep` 0 callers for E10. Comment edits cannot change numbers, so no EQ-G run is needed beyond the SUITE.
- Model: sonnet medium for P10, E9, E10, row 14(d); Opus high for row 14(a), P13, E12 (pinned comment text, frozen-file list). Estimate 3-5 h.

**BD. Defect fixes** (one commit each, each with a test that fails on the old code and passes on the new): DEC-1, DL-1, DL-2 (with P9), EG-1, EG-2, EG-3, EG-5; EG-4 only on Adi's decision. Details in section 3.
- Proof: per-defect test (both directions shown); SUITE; EQ-G, EQ-P, EQ-S byte-identical on the healthy path, except the listed intended differences (DL-1: idle fields of SURV3's nAlt variant); params_id of profile 1 (n_rx 3) and profile 3 (n_rx 4) unchanged.
- Model: Opus, high. Estimate 5-7 h. A DECISIONS entry lists the behaviour-changing fixes before P1-v2's protocol (section 6).

**B3. Shared helpers** (bit-identical): rows 1, 2, 8, 9 (non-W files), P7, E1, E2, E8, E11.
- Files: new `code/ternary.m`, `code/cp_upper.m`, `code/file_sha256.m`, `code/decision/monitor_cf.m`, `code/macro_f1.m`, `code/sign0.m`, `code/load_norm.m`, `evaluation/private/*`, `code/decision/pool_open.m` (E11); the caller files listed in the rows.
- Proof: UNIT (ternary on logical/char/cell/struct/empty; cp_upper n = 0..60, k = 0..n, both forms, `isequaln`; file_sha256 digests and error ids; monitor_cf on the four names; macro_f1/sign0/load_norm on random inputs from `RandStream('mt19937ar','Seed',1)`; E2 helpers for v in {-1, 0, 1, NaN}); SUITE; EQ-G, EQ-P (sign0, E11), EQ-E, EQ-K, EQ-S, EQ-GUI (E8, E1 renames); one real pooled one-cell run of SURV3 and of one pool builder for E11.
- Model: Opus, high. Estimate 6-9 h.

**B3w. Files under whole-text guards** (tier 2): rows 1 and 2 (evaluate_policies copies), 4, 5, E1/E12 (measure_all_kpis part).
- Files: evaluate_policies.m, experiment_combo_generalization.m, experiment_unknown_threat.m, measure_all_kpis.m; guard tests test_d107.m:762-775, test_lb.m:665-743 (674, 726-742), test_core.m:11507-11520, test_speed_envelope.m:502 (check_inserts anchor).
- Proof: the guards are updated only by adding the removed lines/swaps to their explicit lists (a reviewer checks the list diff equals the removed lines, nothing else relaxed); UNIT for rows 4 and 5; SUITE; EQ-G with all entities; EQ-K for measure_all_kpis.
- Model: Opus, high. Estimate 4-6 h.

**B4. File splits** (tier 2): P4, E6, E7.
- Files: link/build_threat_model.m and its new generator files, `link/rx_block_helpers.m`, evaluation/edge_map.m and its new files, gui/demo_gui.m and `gui/private/*`; tests test_core.m:4773, 7468, `dev/dev_rx_script.m`.
- Proof: P4: `isequal` of the tx/channel/threat/rx script strings and of each chart Script read back, old vs new, over the grid ideal/real x mrc/mmse x tdl on/off x each threat x own_out on/off x 3 and 4 antennas, plus one build and `sim` on seeds 1 and 2 `isequal`; E6: EQ-E and the source-reading tests on both layouts; E7: EQ-GUI from the bundle; SUITE.
- Model: Opus, high. Estimate 8-12 h. If B4 waits, P8 lands first and the P4 string-equality proof is rerun on the later split.

**B5. Run-time optimisations, bit-identical, each measured first**: P1, P2, P8, P5, row 12, E4 (tier 1); P3, E5 (tier 2).
- Files: link/idle_rssi.m, link/extract_closed_loop_frames.m, idle_measure.m, decision/pool_cell.m (P1); link/validate_phy.m (P2); link/link_seed.m, build_threat_model.m (P8); detection/compare_architectures.m (P5); decision/decision_config.m, detection/feature_index.m (row 12); evaluation/edge_map.m (E4, E5); detection/run_dataset_sweep.m (P3).
- Proof: P1: measured idle_rssi share first; then `isequal` of every pool field cache off vs on on a smoke cell that flies one seed at two Eb/N0 and with geo overrides, with a combination threat, a tone, a WLAN with the delay line and an emitter_idle path; test_core.m:4775 anchor `los_phase(ctx.aoa(c), att, ctx.yaw, ctx.fd, tq)` verbatim; peak RAM with 6 workers; EQ-P. P2: `validate_phy('V12c', rows)` and a 2-case subset serial vs parallel, `isequal` on BER, NERR, BR, DLY; `results/phy_validation*.txt` identical minus time lines. P8: `isequal` of `sim` outputs and of `get_param` of every dialog field for seeds 1 and 2 with a rebuild between calls; EQ-P. P5: `isequal(Zv_old, Zv_new)` on one smoke call; test_core, test_head. Row 12: profiler numbers, then `rollout_policy` 64 x 30 `isequaln`; EQ-G. E4: EQ-E with FT, CF, CS, VAR. P3: SMOKE serial vs parallel `isequal` of every dataset field (speed, run, seed, fold incl.) and the printed rows; full-size plan pass reproduces the old speed sequence for one level; global stream state equal. E5: `tic` table first; `isequaln` of FT.det_k, det_n, detb_k, OC vs serial.
- Model: Opus, high. Estimate tier 1 7-11 h, tier 2 5-8 h, plus machine time for the measurements.

**B6. Scripts** (after the takeover's final phase; edit by temp file and `mv`, never in place): S3, S1, S5 (mapping), OPS-1, OPS-2, VF-2 (on Adi's decision), T5's runner line if not done.
- Files: `uav-gcs-logs\` scripts, `v7_d91_speed_gate.ps1`, `v7_d91_gated_run.sh`, `worktrees\slots\v7_d91_gated_run_mt.sh`, `v7_d91_gated_state.ps1` (VF-2), docs copies `docs/d91_speed_gate.ps1.txt`, `d91_deploy.md:332`.
- Proof: `D91_GATED_DRY=1` old vs new for the three slots (printed MATLAB command and busy-file lines identical except the intended change); `pair()`/`verdicts()` on the 4.11 logs unchanged; the gate run once with a dummy MATLAB.
- Model: sonnet, medium. Estimate 2-4 h.

**B7. Folders**: F-plan, notes-bak and the deletions Adi approves (section 5).
- Proof: `D91_GATED_DRY=1` per slot; `git worktree list` with no prunable entry; `ood_k2_rules('registered', <new docs path>, REG_COMMIT)` returns the commit; path-length check; one full deploy queue round from the new paths on the cleanup tip (this is also the final release check of all batches).
- Model: sonnet, medium. Estimate 3-5 h plus about 2 h machine.

**B8. Docs**: section 6. B8-now today in the docs repo; B8-rest after B7 and after the merge.
- Model: sonnet, medium. Estimate 1.5 h now, 2 h later.

## 3. Defects

| id | file:line | what | real? (H / C) | can it touch profile 3's running chain | fix in the window, and the test that pins it |
|---|---|---|---|---|---|
| DEC-1 | decision/run_stage.m:67-128 (`run_one`), main.m:90-96 | `CFG` never reaches run_stage scripts; main.m's CFG is silently ignored; `smoke_all_entities` has no effect under run_stage | real / real | no: main.m's values equal the built-in defaults; check the grid after C2 | B0-3 harness; then main.m either passes its CFG through a trailing struct argument of run_stage (absent in chains, so unchanged) or states that chains take their switches from profile.json (Adi picks). Test: a smoke with `CFG.smoke_all_entities = true` reaches every C2g/C2u entity; a smoke without CFG is byte-identical to today's |
| DEC-2 | cp_upper copies (row 2), evaluate_policies.m:998 | two behaviours at n = 0 (1 vs NaN); a naive merge would change numbers | not / real (latent) | only C2e, if no Eb/N0 lies above the KPI 1 threshold (logs show 0 dB, n > 0) | row 2's flagged helper; UNIT at n = 0 for both forms |
| DL-1 | link/build_threat_model.m:2204 vs init_params.m:325; idle_rssi.m:128, emitter_idle.m:96; overrides at decision/pool_job.m:61, evaluation/experiment_survivability_options.m:99, 108, 122 | `n_rx` overridden without recomputing `ant_spacing_wl`: the idle record of SURV3's nAlt variant uses the wrong spacing | real / real | yes, SURV3 pools' idle fields; no verdict reads them (surv3_metrics/judge/clean read BER/FER) | one `antenna_spacing(p)` helper used by init_params (same expression order, so params_id is unchanged for n_rx 3 and 4), antenna_defaults and every n_rx override. Test: from p0 (n_rx 4) override to 3 and 2, idle_rssi's spacing equals the model's UserData spacing; params_id of profiles 1 and 3 unchanged |
| DL-2 (+P9) | link/extract_closed_loop_frames.m:163-168, 217-221, 250-254, 257-265 | catch-all fallbacks: `F.act = ones`, last-value padding of Thr_act/Thr_comp, calibration 0 dB, all silent | real / uncertain | latent in C1p, C1c, SURV, SURV3, EDGE pools; check the first C1p cells | first count with a temporary counter how often `numel(Thr_act) < nf` in a smoke; then an explicit "output absent" test via `out.who` (keep the explicit Level `get_param` fallback for stored-out callers); padding of more than one sample warns once. Tests: a fake `out` without Thr_act falls back with a warning; a wrong-size Thr_comp errors; the fakes at test_core.m:2107, 3271 implement `who`; EQ-P identical |
| EG-1 | diagnostics/diag_path_loss.m:55 | a trailing comment swallowed two `repmat` statements; `reps` ignored | real / real | no (hand-run diagnostic) | put the statements on their own line. Test: source pin that `s = repmat(s(:)', 1, reps);` is a code line, plus `n == nS*numel(rr)*reps` on the grid lines; rerun by hand outside a live tree (DECISIONS' numbers predate the bug) |
| EG-2 | evaluation/result_status.m:30-33, 99 | a silent catch switches off the detector-identity staleness check for latency.mat and edge_map.mat | real / real | yes, at KPI/RPT/BUNDLE it could hide a wrong-detector latency.mat (EDGE guards edge_map.mat itself) | on catch, mark the identity-bearing files STALE with "detector identity not computable". Test: a fusion.mat without N flags latency.mat and edge_map.mat with that reason; recheck the test_core.m:5300-5325 fixture, which takes this path |
| EG-3 | diagnostics/diagnose_antenna_fault_reward.m:39, 71 (and :42 calls the missing `quick_ber_with_iq`), validate_new_threats.m:20, 27; gui/demo_gui.m:808, 861 | params.mat written into the current folder (no onCleanup in the two scripts) | real / real | only if one is started with cwd in the p3 tree | E10 retires the two scripts; demo_gui refuses to boot outside a bundle (a marker written by export_gui_bundle) unless given an explicit dev argument (Adi's OK: changes how the GUI starts). Test: boot in a temp folder without the marker errors with the reason |
| EG-4 | evaluation/map_survivability_boundary.m:296, experiment_survivability_options.m:40 -> init_params.m:471 | SURV and SURV3 regenerate params.mat mid-chain | not / real (latent guard gap) | yes, SURV and SURV3 are ahead; today it rewrites the same values | Adi decides (behaviour change): load params.mat and assert its params_id equals A0's instead of regenerating. Test: a changed n_rx makes the SURV smoke stop with the reason |
| EG-5 | gui/demo_gui.m:822-835, 216 | a corrupt survivability file is reported as "not found" | real / real (cosmetic) | no | log the load error or the missing fields. Test: after E7 a unit test of the private loader; before that, EQ-GUI with a corrupt file |
| OPS-1 | uav-gcs-logs\v7_d91_speed_gate.ps1:3 (header), v7_d91_gated_run.sh:28, v7_d91_deploy_tests2.sh:17, docs/d91_speed_gate.ps1.txt:29, d91_deploy.md:332 | texts say 35 GB; the code (:29) tests 28 GB, which is the registered value (D93 point 6, DECISIONS.md:1387, 1424, 1506; Adi lowered it 20.10) | real (text) / not | no behaviour change; before hand-runs check the floor | texts set to 28 (35 only by a new decision of Adi). No test: DRY output unchanged |
| OPS-2 | uav-gcs-logs\v7_d91_speed_gate.ps1:19 | literal PID 42560 in the pipeline list; a reused PID would be left out of the "other MATLAB" count | real / real | possible overcommit beside C1p/C2/EDGE if the PID is reused | after the chain: drop the literal (the `run_stage(` test covers the pipeline). Test: gate run with a dummy MATLAB |
| OPS-3 | uav-gcs-v7-docs | "13 commits ahead of origin" | not / not | no | none: in sync (0/0 at feb671f) |
| OPS-4 | speed_proofs.sh:23, tests2.sh:22, tests3.sh:30, tests4.sh:37, set4.sh:30, gated_run.sh:59, takeover.sh:98 | references to folders that no longer exist | real / not | no (dead scripts; p2 ended by p2.abandon) | S3 archives the scripts |
| VF-1 | code/tests/test_d121.m:162 | `system('git show f6f6e03:...')` without `-C` or the V7_GIT_REPO fallback, status ignored: in a git-less export it compares the file with git's error text | real (verifier; read again while writing) | no (test file; blocks the next queue verdict if T4 wires it) | B0-2; test: PASS in an export with V7_GIT_REPO, clear error without |
| VF-2 | v7_d91_gated_run.sh (one busy file per slot), v7_d91_takeover.sh:685-717 (`hand_busy` checks p3_hand.busy only), v7_d91_gated_state.ps1:27-30 (path match needs a trailing separator) | a hand-run in the p1 slot that `cd`s into the p3 tree is invisible to the p3 track | real (verifier, H lens) | yes: the takeover could start a p3 stage, or a second p3 hand-run, in the same tree (past bugs 10, 13) | after the chain, on Adi's decision: the wrapper also writes the busy file of the tree the command `cd`s into, and gated_state matches the path without the trailing separator. Test: DRY run with a cross-slot command shows both busy files |

Verifier notes not judged as defects, to read in the window: silent catches in `pool_checkpoint.m:33, 53, 86` and `clean_ref_rebuild.m:282`; train_dqn.m and evaluate_policies.m read the KPI 1 threshold without `kpi1_threshold_check` (only C1d and EDGE check it; no live mismatch); how parent_copy passes in exports (B0-4).

## 4. Numeric-change candidates (not part of the cleanup)

Each needs its own D-entry, a measurement, a fresh chain and the validation-only selection rule. None goes into `cleanup-2111`.

| id | where | what | saving (estimated) | why not a cleanup |
|---|---|---|---|---|
| N1 | decision/dqn_train_run.m:34, 57, 59 | dense matrix forwards instead of `predict` on the dlnetwork (9 calls per step) | up to ~12 % of a training, about 6.8 h per C2; unmeasured at training batch size, and the per-update extraction cost is not in it | matrix products need not match `predict` bit for bit: every agent, selection and verdict moves. Needs a micro-benchmark at batch 64 and 128 first |
| N2 | decision/dqn_eval_batches.m:5 | `parfor` over evaluation batches | up to 9-10 h per C2 claimed; the 25 % evaluation share is not traced to a log | sums differ with the thread count (run_cache.m:16, 64-65); a PP copy per worker (past bug 11); competes with parallel_turn |
| N3 | decision/run_stage.m:48 (C2g, C2u) | C2g and C2u in two MATLABs at once (disjoint outputs, same inputs) | 4-6 h wall per profile | orchestration change: 2 x the pool RAM, launcher markers for two concurrent stages (past bug 12); results unchanged if done right, but a launcher decision |
| P14 | eval_unseen_snr.m:79, 104-107, eval_unseen_severity.m:91, run_dataset_sweep.m | private RandStream for the speeds | none (robustness) | changes the speed sequence; a new-profile decision only. Nobody moves the `build_threat_model` call meanwhile |
| L-params | init_params.m:417-420 (+ mod_type, samples_per_symbol) | drop unread legacy fields | none | changes params_id: only with a full re-key |
| SIM-1 | dev/dev_d91_profile.m (measurement), link/link_seed.m | one `sim` per flight pair if the fixed compile part of `sim` is > 0.5 s | unknown | first measure StopTime 1 frame vs 20 frames; seeds are non-tunable, so FastRestart as is cannot be used |

## 5. Folders

### 5.1 Target layout (after the takeover's final phase, before P1-v2; nothing moves while a MATLAB of the tree, a `v7_d86\*_hand.busy` or `takeover.lock` exists)

```
C:\Users\Adi Suliman\uav-gcs-adaptive-secure-comms\   hub: .git, README (primary checkout)
  worktrees\
    live\        uav-gcs-v7  uav-gcs-v7-p3            pipeline trees (leaf names unchanged)
    live\slots\  (today worktrees\slots)               wrapper slots, _mt stub
    docs\        uav-gcs-v7-docs                       documentation tree
    deploy\      uav-gcs-v7-deploy  uav-gcs-d91-takeover  gui-bundle*
    protocols\   uav-gcs-lectp1  uav-gcs-lectebno  uav-gcs-sysfa
    archive\     uav-gcs-b3m-p1  uav-gcs-b3m-p3  uav-gcs-set4-p3  uav-gcs-v7-bw  p1r  lbs-p1
    dev\         registered branch worktrees (names unchanged), cleanup-2111
    scratch\     loose folders (p3timing*, p3both*, *.out, *.sha256, gui-capture, kpi_print_render, p1r-smoke), cleanup-base, cleanup-baseline
    session_notes_0ff3\                                stays (cited by path in DECISIONS.md:2926, 2935)
  ops\
    logs\        (today C:\Users\Adi Suliman\uav-gcs-logs); logs\archive\ for retired scripts
    d91q\        (today C:\Users\Adi Suliman\d91q)
```
Add `/ops/` to `.git\info\exclude` (`/worktrees/` is there). Registered trees move with `git worktree move` (same drive, no copy; it refuses locked trees), then `git worktree repair` from the hub; `uav-gcs-logs`, `d91q` and unregistered folders with `Move-Item`. Create `cleanup-2111` and the scratch trees at their final paths so B7 never moves a tree in use.

### 5.2 Move map

| old | new | references that must change (file:line) |
|---|---|---|
| `C:\Users\Adi Suliman\uav-gcs-v7` | `...\worktrees\live\uav-gcs-v7` | `uav-gcs-logs\v7_d91_takeover.sh:96` (`V7=`); `v7_d91_gated_run.sh:44` (`ROOT=`), `:59-60` (basename map -> `slots.conf`, S5); `uav-gcs-v7-p3\tools\c2e_lect_isolated.sh:26, 73`; `tools\test_c2e_lect_isolated.sh:89`; notes with runnable commands: `STOP_SOFT.md` (58 path hits, V7_GIT_REPO at :1024), `post_c2e_runbook.md` (40; V7_GIT_REPO at :222-242), `p1r_design.md` (17), `plan_v2.md` (5); registered protocols `docs\d91_deploy.md` (42), `d91_set4.md` (9), `d91_speed.md` (16), `p1r_protocol.md` (7), `c2e_lect_protocol.md` (7), `d91_fuse.md` (6): add a one-line "paths moved, see the folder map" note at the top instead of editing registered text; history scripts `docs\drive_swap\v7_finish.sh:7, 32`, `v7_resume.sh:12, 59`, `docs\runs\v7_d83_launch.sh:11, 79`, `v7_fix_resume_superseded.sh:11, 81` stay as history; MATLAB `%APPDATA%\MathWorks\MATLAB\R2026a` (bookmarks, editor state), the cluster profile's JobStorageLocation, VS Code recent folders |
| `C:\Users\Adi Suliman\uav-gcs-v7-p3` | `...\worktrees\live\uav-gcs-v7-p3` | `takeover.sh:97` (`P3=`); `gated_run.sh:44, 59`; `tools\c2e_lect_isolated.sh:32` (`SLOT=`), `:73`; `tools\test_c2e_lect_isolated.sh:72, 77`; notes with `cd('...uav-gcs-v7-p3')`; `v7_d86\p3_hand.busy` (transient text) |
| `C:\Users\Adi Suliman\uav-gcs-logs` | `...\ops\logs` | `takeover.sh:100` (`L=`), its header launch line (:90) and `v7_d91_takeover.md:164, 209, 224, 254`; `gated_run.sh:43, 47, 48`; `deploy_tests2.sh:56, 61`; `tools\c2e_lect_isolated.sh:31` (`WRAP=`), `:73`; MATLAB `-logfile` paths in the notes; archived scripts are not edited |
| `C:\Users\Adi Suliman\d91q` | `...\ops\d91q` | `v7_d91_speed_gate.ps1:12` (and comment :10); `deploy_tests2.sh:15, 58, 59`; the `gsub(/d91q[\\\/]...` regexes (deploy_tests2.sh:232-233) match the folder name and stay valid. Path budget: +34 characters; test_core.m:11-22 fails above 150 characters in the test work folder: check `...\ops\d91q\deploy2\tip\...` |
| `...\uav-gcs-v7-deploy` | `...\worktrees\deploy\uav-gcs-v7-deploy` | `deploy_tests2.sh:57` (`REPO=`) |
| `...\uav-gcs-b3m-p1`, `...\uav-gcs-b3m-p3` | `...\worktrees\archive\...` | `deploy_tests2.sh:76` (builds `uav-gcs-b3m-$DET_P` as `DET_FROM`) |
| `...\uav-gcs-set4-p3` | `...\worktrees\archive\uav-gcs-set4-p3` | `set4.sh:30` only (archived script, no edit) |
| `...\uav-gcs-v7-docs` | `...\worktrees\docs\uav-gcs-v7-docs` | not in code as a path: `ood_k2_run.m:57`, `k2_1_screen.m:35`, `ood_k2_rules.m:86-89` take `DOCS_REPO` from the command line, `profile.json` `docs_repo` (absent today) or the `V7_DOCS_REPO` environment variable: update the runbook commands that pass it (grep `DOCS_REPO` and `uav-gcs-v7-docs` in the notes) and any user environment value; `dev/m_head.m:36` is a comment; memory notes. Move only when no ood_k2/k2_1_screen phase is pending |
| `uav-gcs-lectp1`, `-lectebno`, `-sysfa`, `-d91-takeover`, `-v7-bw`, `-tip`, `-edgefix`, `-lectkpi` | per 5.1 or deleted (5.3) | no script reference (audit grep of `*.sh`, `*.ps1`, `tools`, `code`); names only in protocol docs and DECISIONS |
| `...\worktrees\slots` | `...\worktrees\live\slots` | `$M/worktrees/slots/...` in `g0_mt_dispatch.md:34`, `n6_corebw_launch.md:141`, `g0_mt_run.sh`, `p1r_launch.md`, `post_c2e_commands.md`, `post_c2e_runbook.md`, `gap_audit.md` |
| registered worktrees `...\worktrees\<name>` | `...\worktrees\dev\<name>` | grep each name in the notes before the move (for example `lectebno-read`, `p1r`) |

Checks before the move: a grep for absolute paths in every note, `profile.json`, the environment (user and machine) and the command lines of running processes; the longest path inside each live tree's `slprj` and Stateflow build folders plus 45 characters stays under 260. After: the B7 proofs (2.2).

### 5.3 Three lists

**Move as is**: uav-gcs-v7, uav-gcs-v7-p3 (git worktree move); uav-gcs-logs and d91q's `start.stamp` (Move-Item; the gate writes the stamp); uav-gcs-v7-docs; uav-gcs-v7-deploy; uav-gcs-d91-takeover (its harness is the proof of the live script); worktrees\slots; the registered branch worktrees; gui-bundle* (the GUI must start from a bundle); session_notes_0ff3 stays where it is.

**Archive** (keep, move under `archive\` or `protocols\`): uav-gcs-b3m-p1, uav-gcs-b3m-p3, uav-gcs-v7-bw (4-7 ignored data entries each: the only copy of their data and results); uav-gcs-set4-p3 (until the sha256 check below); p1r (21 GB) and lbs-p1 (13 GB) worktrees (run data); uav-gcs-lectp1, -lectebno, -sysfa (protocol branches, unmerged, 13-14 MB); the S3 scripts into `ops\logs\archive\` (logs stay in place); the superseded notes stay in `session_notes_0ff3` as history.

**Delete only after Adi's explicit OK** (each re-checked right before: `git status --porcelain --ignored` empty and `git branch -r --contains HEAD` non-empty):
- `uav-gcs-tip` (detached 85484b0 = the v7-deploy commit, on origin, 0 ignored entries, 14 MB).
- `uav-gcs-edgefix` (d91-edgefix ad92546, merged into v7-p3 and v7-dev, on origin, 0 ignored).
- `uav-gcs-lectkpi` (lect-kpi 9a14865, merged into v7-p3, on origin, 0 ignored).
- d91q exports `deploy2` 5.2 GB, `replay3` and `replay4` 3.2 GB each, `fuse` 0.7 GB, `s4` 0.7 GB: `git archive` exports the queues rebuild from git; keep `start.stamp`; first confirm no file inside is newer than its export time (no untracked results).
- the 64 `.bak*` notes (3.3 MB): the newest version of each note exists; the `.bak` names in STOP_SOFT.md:53, p1r_launch.md:19, 371 and p1r_launch_fixes.md:6 are rollback pointers in prose.
- `uav-gcs-set4-p3` (18 GB), `uav-gcs-logs\set4_out` (21 GB) and `read\p1` (13 GB): only where a sha256 compare of every `*fresh3*` (and read\p1) file shows an identical copy in a tree that stays (`uav-gcs-v7-p3\data`, `uav-gcs-v7\data`); a file with no second identical copy is archived, never deleted.
- the hub's `slprj` (0.9 GB build cache, regenerable); the hub's v5 `results` (0.4 GB) only if `git status --porcelain --ignored` shows it fully tracked in f81b772 on `origin/profile-3-antennas`.

## 6. Docs

**Now (docs repo `C:\Users\Adi Suliman\uav-gcs-v7-docs`, branch v7-docs-d91; the chain does not read it; ood_k2_rules reads only the registration commit via `git show <commit>:docs/DECISIONS.md`, so new commits are harmless; push after each change)**

README.md
1. Line 11 "Status as of 28.10.2026" -> the date of the edit, with profile 3's state (A0-B4s and B3r done on 5.11, C1p from about 6.11 02:00, chain end about 18.5-21.5.11).
2. Line 115 "Next dates": drop the 28.10 PC restart; add profile 3's KPI end, the cleanup window 21-23.11 and P1-v2's protocol registration after it.
3. Line 171 "Profile 3 ... decision layer pending" -> D110-D122 readings and deploy done, chain running.
4. Line 179 documentation map "D1-D106" -> "D1-D122".
5. CORE_BW, P1R and the interim report shown as past events with where their results are.
6. Line 205 "Last updated 28.10.2026" -> the edit date.

docs/ROADMAP.md
1. Line 3 "as of 28.10.2026 (evening)" -> the edit date.
2. "Current run (profile 1)" (line 28) -> "Current run (profile 3)": stages left and the 18.5-21.5.11 estimate.
3. "Remaining work 1: restart the PC at C2u" and "Next CORE_BW, P1R, profile 3": mark done.
4. P1R row: ended after C1d on 31.10 (D104), not 2.11-5.11.
5. Add D117/D118 (order and timeboxes), D119 (P1-v2 after profile 3), D121, D122 (profile 3 decoder).
6. Interim report "due 01.11": its real state.
7. Add the cleanup window (21-23.11, behaviour-preserving, then P1-v2 on the cleaned code) and the folder consolidation (memory note: about 21.11).

docs/PROJECT_LOG.md
1. "Where we are (28.10.2026)" -> current.
2. New v7 entries for 1-5.11: D107/D108/D109/D110 verdicts; D111-D118 registration; D121 items 1-2 deployed; macro-F1 fix (6c8b41a); smoke findings; q7 merge (967a9f1); the 4.11 deploy queue (core 54 min, p3core 53 min, 314/314 PASS); rehearsal limits (6c48b95); OHP/GCSA skipped for profile 3 (57a5ad2); B3r on 5.11; D122 decoder (fec_rx d78); D117 point 1 confirmed by Adi; the ood_k2 select hand-run.
3. "Status of the lecturer's KPIs (profile 1, 28.10.2026)" (line 283): add the P1R and CORE_BW readings or mark the table's date as its scope.
4. One entry for the 5.11 code audit and this plan (no results, pointer to `review/code_audit/`).

docs/DECISIONS.md (3,076 lines; headings D1-D122 complete)
1. Heading order: move the D107 block (now 2855-2915) and the D108 block (2132-2177) so that D106 (1984) is followed by D107, D108, D109, D110. Blocks move as text; nothing inside changes. Line numbers from 2916 on (D119-D122, the cited 2926, 2935) do not change; citations inside 2097-2915 in the notes shift (history only).
2. Heading dash style differs (D1-D118 em dash, D119-D122 " - "): leave, or normalise only after a grep shows no tool reads the text after `## Dnnn ` (code checks only `## D111 `).

**Wait**
1. After the merge: delete the stale README/DECISIONS/ROADMAP/PROJECT_LOG copies in the code branches (v7-p3's DECISIONS.md is 1,100 lines of 16.10) and change `main.m:398`, which prints them as READY; keep the protocols and the `.txt` copies (test_smoke, test_core.m:6470, `ood_k2_rules` reads `docs/d91_fresh3_read_*.txt` and the select record in the code tree).
2. After B7: the folder map in README (one section) and `docs/drive_swap/HARDCODED_PATHS.md` marked historical; hub README on the hub's primary checkout (it holds the v5 snapshot f81b772 today).
3. After BD: one DECISIONS entry listing the behaviour-changing fixes (DEC-1, DL-1, DL-2, EG-2, EG-3, EG-4 if adopted) and naming N1-N3 as unadopted candidates, before P1-v2's protocol is registered.
4. After the window: PROJECT_LOG entry for the cleanup (batches done, test rounds, measured savings), ROADMAP with P1-v2's dates.
