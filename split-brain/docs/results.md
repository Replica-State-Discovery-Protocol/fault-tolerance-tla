# Split-brain model: results

Each configuration either switches one mechanism off (a *mutation*, which
must produce a counterexample), checks the full design (which must hold), or
negates a scenario to show it is reachable (a *witness*, which must be
violated, so that the passing rows are not vacuous). Scenarios, switches and
properties are described in [`model.md`](model.md). File paths below are
relative to the `split-brain/` folder.

TLC 2.19 (08 August 2024, the `tla2tools.jar` the Makefile fetches),
OpenJDK 21.0.12, Linux, 16 cores, 12 GB heap. Every row except `sb_full_n3`
runs with **one worker**: breadth-first search is then exact, so traces are
shortest counterexamples and depths are true diameters. With several workers
the verdicts and the distinct-state counts of passing rows are unchanged, but
traces can be longer and reported depths larger. Logs: `logs/<config>.log`.

## Mutations — each must be violated

| Config | n | Change | Result | Distinct states | Trace | Time |
|---|---|---|---|---|---|---|
| `lemma1_nocap` | — | no weight cap | ✗ smallest: S = {1} weight 1, e weight 2 | 1 | — | 3 s |
| `sb_gate_off` | 3 | no authority gate (unamended RSDP) | ✗ `NoDualLeader` | 973 | 7 | 1 s |
| `sb_agg_fresh` | 3 | leader over fresh peers | ✗ `NoDualLeader` | 196 | 4 | < 1 s |
| `sb_order_off` | 3 | Θ_r = Θ (Lemma 2 condition violated) | ✗ `NoDualLeader` | 985 | 7 | 1 s |
| `sb_quar_off` | 3 | Q = 0, restart across the cut | ✗ `NoDualLeader` | 5,605 | 9 | 2 s |
| `sb_tenure_evict` | 3 | draft tenure rule, heal | ✗ `NoDualLeader` | 4,400 | 8 | 2 s |
| `sb_adj_off` | 4 | two voters changed at once | ✗ `NoDualLeader` | 6,463 | 8 | 1 s |
| `sb_spacing_off` | 4 | two changes without A3 spacing | ✗ `NoDualLeader` | 10,871 | 9 | 3 s |
| `sb_cap_off` | 4 | heavy voter added | ✗ `NoDualLeader` | 1,567 | 8 | < 1 s |
| `sb_rec_tight` | 3 | `RecBound` = K + Q − 1 | ✗ `AuthReturns` | 453,371 | 9 | 59 s |

## Full design — each must hold

| Config | n | Scenario | Checks | Result | Distinct states | Depth | Time |
|---|---|---|---|---|---|---|---|
| `lemma1_cap` | — | 554 adjacent pairs | Lemma 1 | ✓ | 1 | 1 | 1 s |
| `sb_quar_on` | 3 | restart across the cut | Dual, Consistent | ✓ | 10,984 | 16 | 3 s |
| `sb_tenure_fresh` | 3 | {1} \| {2,3}, heal | Dual, Consistent, AuthReturns | ✓ | 20,968 | 10 | 15 s |
| `sb_merge_n3` | 3 | same, claims tracked | Dual, MergeOnHeal, AuthReturns | ✓ | 20,968 | 10 | 15 s |
| `sb_adj_on` | 4 | as `sb_adj_off` | Dual, Consistent | ✓ | 1,278 | 7 | 1 s |
| `sb_spacing_on` | 4 | as `sb_spacing_off` | Dual, Consistent | ✓ | 18,166 | 16 | 7 s |
| `sb_cap_on` | 4 | as `sb_cap_off` | Dual, Consistent | ✓ | 318 | 7 | < 1 s |
| `sb_tie` | 4 | stale change in a 2 \| 2 tie | Dual, Consistent | ✓ | 9,722 | 9 | 4 s |
| `sb_full_n3` | 3 | any split, crash, restart, heal | Dual, Consistent, MajorityKeepsAuth, AuthReturns | ✓ | 1,045,001,965 | ≤ 38 † | 4 h 06 min † |

† `sb_full_n3` ran with 16 workers (`WORKERS = auto` in the Makefile), so
38 is an upper bound on the diameter. The run was interrupted after 2 h and
resumed from TLC's checkpoint of 1 h 30 min (`-recover`, with the original
fingerprint polynomial `-fp 91`); the time is the checkpointed part plus the
resumed part (2 h 36 min). Peak disk use for the state queue was about
170 GB. TLC's estimate of the probability that a fingerprint collision left
a state unexplored is 0.018 (optimistic) and 0.33 (from the actual
fingerprints); the other rows are too small for this to matter.

## Witnesses — each must be violated

| Config | Shows reachable | Result | Distinct states | Trace | Time |
|---|---|---|---|---|---|
| `w_failover` | a successor leads during the partition (`s3any`) | ✗ as expected | 34,781 | 7 | 5 s |
| `w_lateheal` | heal after eviction (`s3any`) | ✗ as expected | 90,289 | 7 | 11 s |
| `w_restart` | a restarted node is counted on its new side (`s3quar`) | ✗ as expected | 2,047 | 6 | 1 s |
| `w_double` | both changes accepted under A3 (`s4spacing`) | ✗ as expected | 8,446 | 9 | 1 s |
| `w_tie` | the tie side gains authority after the stale change (`s4tie`) | ✗ as expected | 1,289 | 5 | < 1 s |

## Reading the results

- Every mechanism of the article is necessary: switching any one off
  produces a dual leader within 4–9 states.
- `sb_tenure_evict` / `sb_tenure_fresh` record a defect in the draft and
  its fix — see [`tenure-reset.md`](tenure-reset.md).
- The recovery bound of Theorem 2 is attained: `AuthReturns` holds at
  K + Q = 6 ticks (`sb_tenure_fresh`) and fails at 5 (`sb_rec_tight`), in
  the same partition-and-heal scenario.
- The full design holds exhaustively at n = 3 with any 1 | 2 split, crashes
  and restarts on either side, and heal (`sb_full_n3`, 1.05 × 10⁹ states).

## Reproducing

`make quick` runs every configuration except `sb_full_n3` in about
2.5 minutes; `make <config>` runs one, and `./run.sh <config>` runs one
outside `make`. Each run writes `logs/<config>.log`. The Makefile pipes TLC
through `tee`, so `make` does not stop at the expected counterexamples; the
verdict is in the log.

The configurations are generated by `tools/gen_models.py` from one table of
shared constants and per-row overrides, so regenerating them rather than
editing them by hand keeps the rows comparable.

`sb_full_n3` takes about 4 hours on 16 cores and needs up to about 170 GB of
free disk for TLC's state queue, whose consumed files are deleted only at
checkpoints. A long run can be resumed from its last checkpoint with
`-recover <states directory>`, given the same `-fp` value as the original
run so that fingerprints stay comparable.
