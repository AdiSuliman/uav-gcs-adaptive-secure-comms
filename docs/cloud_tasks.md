# Cloud tasks for v7 (no MATLAB needed)

Start each task in its own cloud session on branch `v7-dev`. MATLAB is not available in the
cloud: these tasks are documentation and careful code with unit tests that the maintainer runs
locally. Push to the branch named in the task, never to main, no force-push, no PR. Report back:
files changed and every decision with its source quote.

Read first: docs/DECISIONS.md, docs/v7_plan.md, docs/v7_source_review.md, docs/v7_research_notes/*.md,
and `git log v6-dev..v7-dev` with its diffs. Code style: English only, short comments without
history or version tags, match the surrounding code. Never invent a number: take it from the notes,
the review or the code.

## Task 1 - D73 and citation hygiene (branch `v7-docs`, documentation and comments only)

1. Append "## D73 - v7: real receiver, flight dynamics and source-corrected severities" to
   docs/DECISIONS.md in the style of the existing entries (**Why:** / **Decision:** / **Adoption:**).
   Cover: the real receiver (quiet slot before the frame, 802.11-style short/long training, 4 pilots
   per 48 data symbols, guard; +-25 ppm per radio, IEEE 802.11-2007 18.4.7.4/18.4.7.5; unknown
   fractional arrival; LoS Doppler shift; three whitening hypotheses incl. power inversion (Ogawa);
   joint timing/frequency search on the whole training (Morelli & D'Amico; La Pan); pilot residual
   frequency; local-whitening MMSE; decision-directed passes) and why (the ideal receiver hid
   synchronization; the 30 dB fast-fading jammer limit of 3 antennas is covariance aging: Truong &
   Heath, US 6,147,985, Shepard/Argos, so the decision layer must answer it); hover 0-161 km/h and
   heading turns (Gross 57.9 deg, Allen & Lin 28.7 deg/s), low edge-speed band 0-21 km/h; the five
   approved severity corrections (spoofer 30 dB by same-radio geometry; Sun shadowing up to ~25 dB
   with hidden-antenna K -16 dB; receive correlation 0.3-0.9 per flight; open connector 26-36 dB as a
   gap-capacitance estimate; WLAN gamma idle gaps, 5-86%, ETSI + geometry, cap 30 dB); the
   antenna_fault label fix; receive-chain mismatch (Bakr; AD9361 I/Q ~54 dB image rejection); the
   Lee input pre-processing candidate; the four triples; and the rule: where no source backs a
   value, lower it to what a source backs and state the rest as the system's limit (operating
   envelope by speed, range and threat).
2. Apply the corrections under "Citation hygiene" in docs/v7_plan.md and "Twelve project claims go
   further than their sources" in docs/v7_source_review.md: append a short dated correction note to
   each affected earlier DECISIONS entry, and fix MATLAB code COMMENTS under code/ (not legacy/) that
   state those claims (e.g. "N antennas null N-1 (Shebert)" -> Winters, Salz & Gitlin 1994; Yuan's
   30 dBm is transmit power; remove any citation of the withdrawn Yu 2020; Isolation Forest
   sub-sample wording vs min(8192, N)). Do not change executable statements.

## Task 2 - adaptive adversaries and profile 3 geometry (branch `v7-adversary`)

1. Extend code/decision/link_env.m so an episode spec can carry an adversary model that decides each
   cycle, from what our link does, whether the threat is on our link (threat cell) or not (clean
   cell), as the existing follower jammer does (spec.follow / spec.fdelay / compromised()). Models,
   parameters from the notes (name any missing number as a parameter in decision_config.m and say so):
   a) threshold-adaptive reactive jammer (W01 / Sagduyu): stays after a hit with probability 0.8,
      after a miss with 0.2;
   b) pattern jammer that switches pattern after the user went unjammed (Yuan);
   c) jammer blocking the channels used in the last 5 slots (S14);
   d) intelligent reactive jammer of Li et al. 2022 (IEEE WCL 11(7)): tracks while it detects the
      transmitter, sweeps/combs otherwise.
   Write code/decision/experiment_adaptive_adversary.m (stage 'C2a' in code/run_stage.m after 'C2g'):
   deployed DQN (data/trained_dqn.mat), rule + escalation and class table on the TEST split as
   evaluate_policies.m does; recovery with 95% bootstrap over geometries; results/adaptive_adversary.
   {txt,mat}; honour SMOKE. Add unit tests to code/tests/test_core.m for each state machine on a tiny
   hand-built PP/K.
2. Profile 3 (n_rx = 4) in code/link/init_params.m: the fixed interferer directions and survivability
   geometries keep the alignment with the GCS equal on every array (n_rx 2: [44.1 -50 60] /
   [41.4 6.5]; n_rx 3: [42 -52.2 61.3] / [42.2 11.4]; targets 0.25 / 0.2 / 0.93). Alignment =
   |a_gcs^H a_int|^2 / N^2, uniform line array of N antennas over 1.2 m at 2.4 GHz, GCS at broadside,
   a_k = exp(-j 2 pi (spacing/lambda) k sin(theta)). Confirm the N = 2 and 3 values with Python, then
   add an n_rx == 4 branch with angles near the N = 3 ones, away from grating-lobe ambiguities, and a
   short comment on the computation.
