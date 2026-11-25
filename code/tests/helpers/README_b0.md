# Test helpers for the behaviour-preserving cleanup

Files here are not tests (no `test_` prefix, so `runtests` skips them). Each test file adds this folder
with one `addpath` in its `setupOnce`.

- `src_of(name)`: the stored text of the file behind a function or script name, equal to
  `fileread(which(name))`. The source-reading pins of `edge_map`, `demo_gui`, `measure_all_kpis` and
  `build_threat_model` call it. Order and adjacency asserts (`strfind(a) < strfind(b)`, `verifyLessThan`
  on positions, the `pol_layers` cut in test_core) keep their meaning unchanged because the text is the
  same bytes; none was relaxed. When a file is split, `src_of` is the one place that must return the
  pieces concatenated in their original order, or those asserts must name the piece they pin.
- `stage_smoke(stages, CFG)`: runs C2g / C2u in smoke mode the way `run_stage` does (`run(name)` with
  `SMOKE` set) with `CFG` in the script's workspace; default `CFG.smoke_all_entities = true`. `run_stage`
  itself hands no `CFG` to its scripts, so its smoke reaches the first entity only. Needs the smoke data
  of the chain in the current folder; it overwrites that folder's C2g/C2u results.

## How parent_copy tests pass in a git-less export

`git archive HEAD` export outside any repository, run with `V7_GIT_REPO` empty and then set to a
checkout of the repository:

| test | without V7_GIT_REPO | with V7_GIT_REPO |
|---|---|---|
| test_d121 `test_rule_core_policy_byte_identical` | fails, `git show 7bc9bfa:... failed: fatal: not a git repository` (status 128 asserted) | passes |
| test_head `test_fuse_classes_off_parent` | fails, same message | passes |

So `parent_copy` and `pb_parent_dir` do need `V7_GIT_REPO` in an export; the 4.11 runs passed because
the queue's command sets it to the deploy checkout (DECISIONS: "Profile 3's queue command sets
`V7_GIT_REPO` to the deploy checkout"; STOP_SOFT section 7). It is set in no script of this tree.
Beware of an export placed inside another repository's folder: `git -C` then finds that repository and
the fallback is never exercised.

## Proposed commands of the equivalence harnesses on this line (not run)

All from the checkout under comparison, through the gated wrapper, on a scratch copy (the smoke
overwrites `data/` and `results/`); compare against the same commands on the base commit.

- EQ-G: `run_stage('smoke','C1p','C1c','C1d','C2','C2e','C2g','C2u')` (the chain's smoke needs the pools and
  the clean reference first), then `stage_smoke()` in the same folder for the all-entity C2g/C2u.
  Compare `data/trained_dqn.mat`, `data/drop_threshold.mat`, `results/policy_evaluation.mat`,
  `results/combo_generalization.mat`, `results/unknown_threat_policy.mat`, `data/unknown_threat_agents.mat`
  with `isequaln` by field; `results/*.txt` byte for byte with `Generated:` and `(x min)` masked.
- EQ-P: `run_stage('smoke','C1p','C1c')`; `isequal` of every field of `data/policy_pools.mat` and the clean pools.
- EQ-E: `SMOKE = true; edge_map` (REPS = 1, B = 400) after the smoke chain; `isequaln` of EM, EDGE_NUM
  (and FT, CF, CS, VAR where present); `results/edge_map.txt` and `edge_summary.txt` byte for byte (masked).
- EQ-S: `run_stage('smoke','SURV','SURV3')` plus test_core's `surv_script_run` / `surv3_script_run` tests
  and test_smoke.
- EQ-K: `measure_all_kpis`, `result_status()`, `export_report_numbers` on the test_core KPI fixture tests
  (the ones calling `evalc('measure_all_kpis')`) and on a copy of the final `results/`; `kpi_summary.txt`
  byte-identical (masked).
- EQ-GUI: from a gui bundle, `demo_gui('rx4')` with one fixed scenario and seed; compare screenshots and
  the printed log lines. Never from a live tree (the GUI writes `params.mat`).
