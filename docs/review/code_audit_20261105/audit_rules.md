# Code and folder audit: common rules (5.11.2026)

Project: MATLAB simulation of a UAV-GCS RF link that detects and overcomes RF threats (detector CNN + fusion, link model, DQN/rule decision layer, KPI evaluation, GUI). Code tree: `C:\Users\Adi Suliman\uav-gcs-v7-p3\code` (about 64k lines, git branch v7-p3 at Q3' 57a5ad2 plus later commits).

## Hard limits
1. **Read only.** No edits, no file moves or deletes, no git commands that change state (no checkout, commit, stash, worktree, branch). `git log`, `git show`, `git diff`, `git grep`, `git blame` are fine.
2. **No MATLAB.** Profile 3's chain runs from this tree for about two weeks; its workers read code files live. Nothing you propose is implemented before profile 3's KPI stage ends (about 21.11).
3. No web fetches of PDF or file URLs. No downloads.
4. Token economy: grep first, then read the needed ranges. Never read `code/tests/test_core.m` (11.8k lines) or `uav-gcs-v7-docs/docs/DECISIONS.md` whole; read ranges. No sub-agents.
5. Write only your output file (named in your brief).

## What counts as a good proposal
A proposal is worth listing only if it is **behaviour-preserving** (every saved number and every printed line the pipeline relies on stays identical) or, if it changes behaviour, it fixes a real defect (then flag it as a DEFECT, separately).

**Contracts you must not break, and must check for every proposal:**
- Printed lines that runbooks, tests and verify lists grep (for example `The kept fusion is the rule's base`, `-> rule yes`, `DEPLOY_STATE`, `##### STAGE`, `V7SMOKE`, `V7RELEASE`, `Reading: in-sample`, `B3r: start marker`). Before proposing a print change, `git grep` the exact text in `code/` and in `C:\Users\Adi Suliman\uav-gcs-logs\*.sh` and `*.ps1`.
- Saved field names in `.mat` files (readers in evaluation/KPI and the tests load them by name).
- Random-number order and seeds (any reordering of rand/randn calls changes results).
- Hash inputs: `detector_id.m`, `params_id`, `fusion_rev_id`; anything that feeds them.
- `profile.json` switches and their defaults; `run_stage.m` stage names.
- Registered rules in DECISIONS (D-entries): code that implements a registered rule must keep its exact behaviour.

**Past bugs (check every proposal against them):** `C:\Users\Adi Suliman\.claude\projects\C--Users-Adi-Suliman-uav-gcs-adaptive-secure-comms\memory\past-bugs-checklist.md` (34 lines, read it first).

**House style:** English only in code; short comments with no history, dates, decision tags or "was/now" text (a full comment pass was done on 30.09, except `legacy/`); match the surrounding code.

## What to look for
- Dead code: functions or branches no caller reaches (verify with `git grep` across `code/` and the shell scripts), stale switches that are always on/off, unused outputs and variables.
- Duplication: the same logic copied in several files (name each copy, file:line), candidates for one shared helper.
- Oversized functions or files that would be clearer split, with no behaviour change.
- Comment bloat: long or historical comments, comments restating the code, out-of-date comments that contradict the code.
- Fragile patterns: scripts run via `run('x')` that depend on workspace variables, `eval`, globals, hard-coded absolute paths, magic numbers repeated in many places, silent `try/catch` that hides errors.
- Efficiency: hot loops, repeated loads of large `.mat` files, recomputation. Estimate the saving in run hours if possible: that is the most valuable kind of finding.
- Tests: duplicated test setup, tests that test nothing, slow tests that could share fixtures.

## Output format (your output file, Markdown)
1. A short summary (5-10 lines): the state of your area and the top 5 proposals.
2. A table, one row per proposal: `id | file:line | category | what | why it is safe (which contracts you checked, how) | how to prove no harm (existing test name, or the equivalence test to add: old vs new output bit-identical on fixed seeds) | benefit | risk (low/med/high)`.
3. A separate **DEFECTS** section for anything that looks wrong in behaviour (with evidence), kept apart from the cleanups.
4. Things you looked at and decided to leave alone, one line each, with the reason.
Be concrete; no proposal without file:line. Prefer fewer, solid proposals over many speculative ones.
