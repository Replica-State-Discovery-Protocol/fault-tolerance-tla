# RSDP Split-Brain Prevention — TLA⁺ Specification

Companion artifact for the split-brain article (working title *Split-brain
prevention in the Replica State Discovery Protocol*). Background, decisions
and open tasks: [`../docs/CONTEXT.md`](../docs/CONTEXT.md).

The question the artifact answers: does each mechanism added in the article
matter, and does the full design prevent split-brain? Every mechanism is a
constant in the configuration. Switching it off must produce a
counterexample; the full design must hold.

## Files

| Path | Content |
|---|---|
| `spec/SplitBrain.tla` | main model |
| `spec/LemmaOne.tla` | exhaustive arithmetic check of Lemma 1 |
| `models/*.cfg` | one TLC configuration per row of the results table |
| `tools/gen_models.py` | generates every `sb_*` and `w_*` configuration from one table |
| `traces/*.trace.txt` | counterexample traces of the `*_off` rows |
| `logs/*.log` | TLC output of the runs reported below |
| `run.sh` | run one configuration: `./run.sh sb_gate_off` |
| `Makefile` | `make <config>`, `make quick`, `make all`; one worker by default (`WORKERS=auto` to override) |

Regenerate configurations with `python3 tools/gen_models.py` rather than
editing them by hand, so shared constants stay identical across rows.

## Model scope

| Article | Model |
|---|---|
| SHARE heartbeat, version and incarnation gate | `Tick`: one round; every node sends every tick |
| TTL eviction at Θ | slot ages saturate at `Theta` (= evicted) |
| A1, at most k − 1 consecutive losses | per-link loss counter, `K` |
| A2, delay bound Δ | in-flight window: SHARE sent before a cut or crash may arrive for `Delta` ticks |
| configuration, injection, A3 (Defs. 1–4) | scripted configurations per scenario; `Inject` at node 1 |
| freshness, tenure, vote, authority (Defs. 5–7) | operators `Fresh`, `Vote`, `Auth` |
| gated translation (Def. 8) | `Output` of the leader reducer |
| partition, heal, crash-recovery | `Partition`, `Heal`, `Crash`, `Restart` |

Abstractions: lockstep ticks, so no clock drift (drift is covered by the
simulation in the article's empirical section); authority evaluated in
every state (T_sweep = 0); leader = smallest identifier, members = known
identifiers; payloads carry only identifier, incarnation and configuration;
one partition and at most one heal per behaviour; converged start; crashes
only during the partition; restarts may land on either side; one electorate
per epoch holds by construction (scripted configurations). Ages instead of
timestamps keep the state space finite without a time horizon. No symmetry
reduction: the leader reducer orders identifiers.

### Parameters

Discrete forms of the article's conditions (ρ̄ = 0, T_sweep = 0,
T_resync = 1):

| Condition | Discrete form | Value used |
|---|---|---|
| accuracy | Θ_r > K − 1 | `ThetaR = 2` |
| handover gap (Lemma 2) | Θ ≥ Θ_r + Δ + K − 1 (equality is safe in lockstep) | `Theta = 5` |
| quarantine (Lemma 3) | Q > Δ + Θ_r | `Q = 4` |
| recovery bound (Theorem 2) | K + Q ticks after heal | `RecBound = 6` |

`K = 2`, `Delta = 1`, `TRebase = 6`, `MaxInc = 2` throughout, except the
n = 4 rows, which use `K = 1` (loss-free; `RecBound = 5`) to bound the
delivery branching — their counterexamples do not depend on loss.

### Mechanism switches

| Constant | Values | Meaning |
|---|---|---|
| `GATE` | `TRUE` / `FALSE` | exclusive output gated by authority |
| `AGG` | `"sigma"` / `"fresh"` | leader aggregated over Σ or over fresh peers |
| `ThetaR` | 2 / 5 | separate freshness threshold, or a single threshold Θ_r = Θ |
| `Q` | 4 / 0 | quarantine on or off |
| `TENURE` | `"fresh"` / `"evict"` | tenure resets when a peer stops being fresh, or only on eviction and restart (see below) |
| `CHECK_ADJ`, `CHECK_CAP`, `CHECK_SPACING` | `TRUE` / `FALSE` | adjacency, weight cap, A3 spacing at injection |

### Scenarios

Nodes 1 < 2 < 3 < 4 by identifier; side A is listed first.

| Scenario | n | Electorate (weights) | Partition | Script / faults |
|---|---|---|---|---|
| `s3any` | 3 | {1,2,3} | any 1 \| 2 split | any node may crash and restart on either side |
| `s3cut` | 3 | {1,2,3} | {1} \| {2,3} | — |
| `s3quar` | 3 | {1,2,3} | {1} \| {2,3} | node 3 may crash and restart |
| `s4adj` | 4 | {1,2,3}, 4 non-voter | {1,4} \| {2,3} | change to {1,2,4} (two voters at once) |
| `s4spacing` | 4 | {1,2,3} | {1,4} \| {2,3} | add 4, then remove 3 |
| `s4cap` | 4 | {1,2,3} (1,1,3) | {1,2,4} \| {3} | add 4 with weight 2 (cap is 1) |
| `s4tie` | 4 | {1,2,3,4} | {1,2} \| {3,4} | remove 3 (stale change in a tie) |

## Properties

| Name | Kind | Article counterpart |
|---|---|---|
| `TypeOK` | invariant | well-formedness |
| `NoDualLeader` | invariant | no two live nodes act as leader at once; stronger than Theorem 1 (also covers handover after heal) |
| `ConsistentOutputs` | invariant | Theorem 1: non-⊥ outputs in different components coincide |
| `MajorityKeepsAuth` | invariant | Theorem 2 (i) |
| `AuthReturns` | bounded response | Theorem 2 (ii): `RecBound` ticks after heal every live node holds authority and agrees on the leader |
| `MergeOnHeal` | invariant | Proposition 2: members claimed during the partition survive heal |
| `NoViolation` (LemmaOne) | constant-level | Lemma 1, exhaustive for \|S\| ≤ 5, weights 1..3 |
| `No*` witnesses | expected violation | the scenario they negate is reachable, so passing rows are not vacuous |

## Results

TLC 2.19 (08 August 2024, the `tla2tools.jar` the Makefile fetches),
OpenJDK 21.0.12, Linux, 16 cores, 12 GB heap. Every row except `sb_full_n3`
runs with **one worker**: breadth-first search is then exact, so traces are
shortest counterexamples and depths are true diameters. With several workers
the verdicts and the distinct-state counts of passing rows are unchanged, but
traces can be longer and reported depths larger. Logs: `logs/<config>.log`.

### Mutations — each must be violated

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

### Full design — each must hold

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

### Witnesses — each must be violated

| Config | Shows reachable | Result | Distinct states | Trace | Time |
|---|---|---|---|---|---|
| `w_failover` | a successor leads during the partition (`s3any`) | ✗ as expected | 34,781 | 7 | 5 s |
| `w_lateheal` | heal after eviction (`s3any`) | ✗ as expected | 90,289 | 7 | 11 s |
| `w_restart` | a restarted node is counted on its new side (`s3quar`) | ✗ as expected | 2,047 | 6 | 1 s |
| `w_double` | both changes accepted under A3 (`s4spacing`) | ✗ as expected | 8,446 | 9 | 1 s |
| `w_tie` | the tie side gains authority after the stale change (`s4tie`) | ✗ as expected | 1,289 | 5 | < 1 s |

### Reading the results

- Every mechanism of the article is necessary: switching any one off
  produces a dual leader within 4–9 states.
- `sb_tenure_evict` / `sb_tenure_fresh` record a defect in the draft and
  its fix — see [`../docs/split-brain-tenure-finding.md`](../docs/split-brain-tenure-finding.md).
- The recovery bound of Theorem 2 is attained: `AuthReturns` holds at
  K + Q = 6 ticks (`sb_tenure_fresh`) and fails at 5 (`sb_rec_tight`), in
  the same partition-and-heal scenario.
- The full design holds exhaustively at n = 3 with any 1 | 2 split, crashes
  and restarts on either side, and heal (`sb_full_n3`, 1.05 × 10⁹ states).
- Limits: n ≤ 4, no drift, loss-free at n = 4, one partition per behaviour.
