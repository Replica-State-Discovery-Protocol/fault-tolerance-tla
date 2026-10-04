# Split-brain model: mechanism, scope and properties

The module `spec/SplitBrain.tla` models RSDP extended with the split-brain
prevention mechanism of the article; `spec/LemmaOne.tla` checks the
arithmetic lemma on which reconfiguration rests. Definition, lemma and
theorem numbers refer to the split-brain article.

## The mechanism in brief

RSDP reducers fall into two classes. *Partition-safe* reducers, such as
cluster membership, are monotone: their outputs from the two sides of a
partition can be merged after heal. *Exclusive* reducers, such as electing
the node with the smallest identifier as leader, make claims that more
information can retract; run independently on both sides of a partition,
they produce two leaders. The mechanism gates exclusive reducers and leaves
partition-safe ones alone.

- **Configuration.** Each node holds a configuration: an epoch number, an
  electorate of voters (a council of stable nodes, not the whole cluster)
  and positive voter weights. Configurations travel in the SHARE payload; a
  node adopts any configuration with a higher epoch. A restarted node holds
  the empty configuration until it hears one.
- **Majority and margin.** A set of nodes is a majority if its voters weigh
  more than half the electorate. The margin is the smallest amount by which
  any majority exceeds half.
- **Adjacent changes.** An operator may change the configuration only at a
  node that holds authority, to the next epoch, adding or removing at most
  one voter, leaving other weights unchanged, and with the changed voter
  weighing at most twice the margin of the electorate without it (the
  *weight cap*). Successive changes are spaced by at least the convergence
  time (assumption A3). Majorities of adjacent configurations always
  intersect (Lemma 1).
- **Freshness and tenure.** A peer is *fresh* if heard within Θ_r, a
  threshold shorter than the eviction threshold Θ. Its *tenure* is the time
  it has been continuously fresh; it resets when the peer stops being fresh
  or appears with a higher incarnation. A peer votes only once its tenure
  reaches the quarantine Q.
- **Authority.** A node holds authority if its fresh, tenured voters form a
  majority of its configuration. Each node evaluates this locally from its
  own memory.
- **Gated translation.** An exclusive reducer still aggregates over the
  node's whole memory, but its output is presented only while the node holds
  authority, and is ⊥ otherwise. Aggregating over the whole memory rather
  than over fresh peers orders step-down (at Θ_r) before succession (at
  eviction, Θ).
- **Partition or restart.** A peer readmitted with an unchanged incarnation
  was cut off by a partition; one readmitted with a higher incarnation
  restarted.

The article proves that no two partition components present different
non-⊥ outputs, that a majority side keeps authority during a partition and
every node regains it within a bounded time after heal, and that the claims
of partition-safe reducers survive heal. The model checks these claims and
shows that each element of the mechanism is necessary.

## Model scope and abstractions

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

## Parameters

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

## Mechanism switches

| Constant | Values | Meaning |
|---|---|---|
| `GATE` | `TRUE` / `FALSE` | exclusive output gated by authority |
| `AGG` | `"sigma"` / `"fresh"` | leader aggregated over Σ or over fresh peers |
| `ThetaR` | 2 / 5 | separate freshness threshold, or a single threshold Θ_r = Θ |
| `Q` | 4 / 0 | quarantine on or off |
| `TENURE` | `"fresh"` / `"evict"` | tenure resets when a peer stops being fresh, or only on eviction and restart ([`tenure-reset.md`](tenure-reset.md)) |
| `CHECK_ADJ`, `CHECK_CAP`, `CHECK_SPACING` | `TRUE` / `FALSE` | adjacency, weight cap, A3 spacing at injection |

## Scenarios

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

