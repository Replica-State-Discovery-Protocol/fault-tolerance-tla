# Finding: tenure must reset when a peer stops being fresh

A defect in the draft of the split-brain mechanism, found by model
checking `spec/SplitBrain.tla`. It is the split-brain counterpart of the
version shadow found for the CFT article
([`../../cft/docs/version-shadow.md`](../../cft/docs/version-shadow.md)).
Paths below are relative to the `split-brain/` folder.

## Background

The split-brain mechanism lets a node translate an exclusive reducer (for
example the leader reducer) only while it holds *authority*: while the
voters it counts form a weighted majority of its configuration. A peer is
counted only if it is

- **fresh** — heard within the freshness threshold Θ_r, which is shorter
  than the eviction threshold Θ; and
- **tenured** — known for at least the quarantine Q.

Tenure exists so that a node which has just (re)appeared cannot tip a
majority too early. The motivating case, Lemma 3 of the draft, is a voter
that crashes on one side of a partition and restarts on the other: without
tenure both sides would count it at once.

## The rule in the draft

Section 3 of the draft defined the tenure anchor κ_i(j) as the time the
slot for v_j was created for its current incarnation, so tenure reset
**only on eviction (at Θ) or on a higher incarnation (restart)**. A peer
that was silent long enough to become stale (age ≥ Θ_r) but not long enough
to be evicted (age < Θ) kept its full tenure.

## How it was found

The spec makes the reset rule a constant, `TENURE ∈ {"evict", "fresh"}`.
Configuration `sb_tenure_evict` (partition {1} | {2,3}, then heal, draft
rule) violates `NoDualLeader` in 4,400 distinct states with an 8-state
trace (`traces/sb_tenure_evict.trace.txt`).

Parameters: Θ = 5, Θ_r = 2, Q = 4, K = 2 (one consecutive loss allowed),
Δ = 1. `age[i][j]` is ticks since i last heard j (5 = evicted); `ten[i][j]`
is tenure.

| State | Action | age (rows: node 1, 2, 3) | ten | Comment |
|---|---|---|---|---|
| 1 | Init | all 0 | all 4 | converged, node 1 leads |
| 2 | Tick | ⟨0,1,1⟩ ⟨1,0,1⟩ ⟨1,1,0⟩ | all 4 | every link loses one SHARE |
| 3 | Partition | unchanged | all 4 | side A = {1} |
| 4 | Tick | ⟨0,0,2⟩ ⟨2,0,0⟩ ⟨2,0,0⟩ | all 4 | an in-flight SHARE from 2 reaches 1 after the cut; 2 and 3 last heard 1 one tick earlier |
| 5 | Tick | ⟨0,1,3⟩ ⟨3,0,1⟩ ⟨3,1,0⟩ | all 4 | node 1 sees 2 and 3 as stale and steps down — correctly |
| 6 | Tick | ⟨0,2,4⟩ ⟨4,0,0⟩ ⟨4,0,0⟩ | all 4 | 2 and 3 still hold node 1 at age 4, one tick from eviction |
| 7 | Heal | unchanged | all 4 | heal falls in the stale-but-not-evicted window |
| 8 | Tick | ⟨0,0,5⟩ ⟨5,0,1⟩ ⟨5,1,0⟩ | ⟨4,4,0⟩ ⟨0,4,4⟩ ⟨0,4,4⟩ | see below |

In state 8:

- Nodes 2 and 3 evict node 1 (age 5) and lose its first post-heal SHARE.
  Node 2 is now the smallest identifier they know and, with node 3 fresh
  and tenured, holds authority: **node 2 leads**.
- Node 1 receives node 2's SHARE. Its slot for node 2 was never evicted
  (age 2 < 5), so the delivery is an ordinary heartbeat and tenure stays 4.
  Node 2 is fresh again, {1, 2} is a majority: **node 1 leads**.

Two leaders. The root cause is the asymmetry of last-heard times across
the cut (one in-flight message is enough) combined with tenure surviving
the stale window: node 1 regains authority on the first heartbeat after
heal, before nodes 2 and 3 have heard it again.

## The fix

> The tenure of v_j at v_i is the time v_j has been **continuously fresh**
> at v_i. It resets to zero whenever v_j stops being fresh or appears with
> a higher incarnation.

A peer that returns after a silence is treated like a newcomer, whether it
restarted, was evicted, or merely went stale. In the scenario above, node
2's tenure at node 1 drops to 0 in state 5. After heal, node 1 must hear
node 2 for Q ticks before counting it; within that time nodes 2 and 3 hear
node 1, re-add it, and switch their leader to node 1, so node 2 stops
acting before node 1 starts.

The rule costs nothing in normal operation: connected peers never stop
being fresh (the lower bound on Θ_r), so their tenure never resets.

## Verification

| Config | Rule | Scenario | Result |
|---|---|---|---|
| `sb_tenure_evict` | draft (evict) | {1} \| {2,3}, heal | ✗ `NoDualLeader` violated, 8-state trace |
| `sb_tenure_fresh` | fixed (fresh) | identical except `TENURE` | ✓ `NoDualLeader`, `ConsistentOutputs`, `AuthReturns` hold (20,968 states) |
| `sb_merge_n3` | fixed | same, members claims tracked | ✓ `MergeOnHeal`, `AuthReturns` hold |
| `sb_quar_on` | fixed | node 3 crashes and restarts across the cut | ✓ holds |

`diff models/sb_tenure_evict.cfg models/sb_tenure_fresh.cfg`
shows the constant and the added invariants as the only differences. All
other split-brain configurations use the fixed rule.

## Effect on the bounds

Lemma 3's bound is unchanged: the fixed rule resets tenure at least as
often as the draft rule, so it is at least as conservative.
