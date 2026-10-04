# Working context (handoff)

This file brings a new session up to speed on what this repository is for,
what has been decided, what has been verified, and what remains. Read it
before changing anything.

## 1. The research programme

PhD work of Maksym Kotov (supervisor Serhii Toliupa, Taras Shevchenko
National University of Kyiv) on the **Replica State Discovery Protocol
(RSDP)**: a leaderless, agentless coordination protocol. Each node gossips
its perspective in SHARE messages, keeps the received payloads in a memory
Σ with TTL eviction, and derives the cluster state with deterministic
*state reducers*. Reference implementation:
<https://github.com/Replica-State-Discovery-Protocol/core> (TypeScript).

Articles relevant here:

| Article | Status | Artifact in this repo |
|---|---|---|
| *Crash Fault Tolerance in RSDP: Formal Convergence Guarantees and Empirical Validation* (CFT) | under review, not yet published | `cft/` |
| *Split-brain prevention in RSDP* (working title) | being drafted | `split-brain/` |

Each article must read standalone (own numbering, every symbol defined);
both later become chapters of the dissertation.

## 2. What the CFT article established

- System model: n nodes, fair-lossy links (A1), partial synchrony with
  delay bound Δ after GST (A2), bounded clock drift ρ̄, crash-stop and
  crash-recovery.
- Reducer admissibility: determinism, permutation independence,
  idempotence, history independence.
- The TTL eviction (threshold Θ, sweep period T_sweep, SHARE period
  T_resync) is an eventually perfect failure detector ◇P; closed-form
  bounds for detection and convergence.
- The **version shadow** defect and its incarnation fix
  (see [`cft-version-shadow.md`](cft-version-shadow.md)).
- Partition: each component converges and the cluster reconverges after
  heal — but **split-brain was explicitly left out of scope**. That gap is
  what the second article closes.

Defaults used in the CFT experiments: Θ = 3000 ms, T_sweep = 200 ms,
T_resync = 500 ms, D_max = 50 ms, Δ = 30 ms, ρ̄ = 0.01.

## 3. The split-brain article

### 3.1 Positioning (agreed)

Not a new theory of split-brain handling. The article adapts established
techniques — lattice/CRDT merge (Shapiro et al.; CALM), lease-style
self-fencing (Gray & Cheriton; Chubby; Raft step-down), epoch-numbered
reconfiguration with overlapping majorities (Raft single-server change;
Lamport–Malkhi–Zhou) — and shows that RSDP's **existing primitives** (TTL
memory, incarnation gate, admissibility contract, weighted voting of the
BFT article) suffice to carry them **without leader election, a replicated
log, or a consensus round**. Closest practical precedent: Akka Split Brain
Resolver, Elasticsearch `minimum_master_nodes` (no formal treatment).

### 3.2 Section status

| Section | Status |
|---|---|
| 1 Introduction and related work (merged), 28 references | drafted |
| 2 Preliminaries (restates CFT model) | to write; keep short |
| 3 Extended model (≈ 2 pages) | drafted; **needs the tenure fix (§5)** |
| 4 Partition-aware admissibility (≈ 1 page) | drafted |
| 5 Main theorems (≈ 1 page) | drafted; handover remark depends on the tenure fix |
| 6 Mechanized complement | **to write from this repo** |
| 7 Empirical evaluation | planned (simulation harness of the CFT article) |
| 8 Discussion | to write |

### 3.3 The mechanism in one page

Exclusive reducers (whose claims can be retracted by more information,
e.g. a smallest-identifier leader) are gated; partition-safe reducers
(monotone, e.g. cluster members) are not.

- **Configuration** 𝒦 = (ε, Λ, w): epoch ε, electorate Λ (a council of
  stable nodes, not the whole cluster), positive weights w. Carried in the
  SHARE payload; a node adopts any configuration with a higher epoch. A
  restarted node holds the empty configuration until it hears one.
- **Weight / majority / margin**: W(S) = sum of weights of S ∩ Λ; S is a
  majority if 2W(S) > W(Λ); the margin μ is the smallest excess of any
  majority over W(Λ)/2.
- **Adjacent configuration**: next epoch, at most one voter added or
  removed, other weights unchanged, and the voter changed weighs at most
  2μ of the electorate without it (the *weight cap*).
- **Injection**: an operator issues a change at one node; accepted only if
  that node holds authority and the change is adjacent.
- **A3**: one change per epoch, consecutive changes at least T_rebase apart
  (T_rebase ≥ convergence bound). The council changes only on durable
  topology changes, never on runtime churn.
- **Freshness**: peer heard within Θ_r, with 0 < Θ_r < Θ.
- **Tenure** (fixed rule, §5): time a peer has been *continuously fresh*;
  resets when it stops being fresh or changes incarnation. Threshold Q.
- **Authority**: the node's fresh, tenured voters form a majority of its
  configuration. Evaluated locally from Σ alone.
- **Gated translation**: an exclusive reducer still aggregates over all of
  Σ, but presents ⊥ unless the node holds authority. Aggregating over Σ
  (not over fresh peers) is what orders step-down (at Θ_r) before
  succession (at eviction, Θ).
- **Partition detection**: a peer readmitted with an unchanged incarnation
  was partitioned; with a higher one, it restarted.

Conditions (continuous time; k − 1 = tolerated consecutive SHARE losses):

- accuracy: Θ_r > (k·T_resync/(1−ρ̄) + Δ)(1+ρ̄)
- handover gap (Lemma 2): Θ/(1+ρ̄) > Δ + (Θ_r + T_sweep + k·T_resync)/(1−ρ̄)
- quarantine (Lemma 3): Q/(1+ρ̄) ≥ Δ + (Θ_r + T_sweep)/(1−ρ̄)

With the CFT defaults: Θ_r = 1500 ms, Θ = 3000 ms, Q = 2000 ms satisfy all
three; T_rebase ≈ 3.8 s.

Results: Lemma 1 (majorities of adjacent configurations intersect);
Theorem 1 (no two components present different non-⊥ outputs; after the
step-down bound only one component presents any); Theorem 2 (a majority
keeps authority during the partition; after heal everyone regains it within
max{T_conv, T_hb + (Q + T_sweep + D_max)/(1−ρ̄)}); Proposition 2 (claims of
a partition-safe reducer survive heal); Corollary 1 combining them.

## 4. The TLA+ artifact

### 4.1 Layout

```
cft/           CFT article artifact (moved here unchanged from the repo root)
split-brain/   split-brain article artifact
  spec/          SplitBrain.tla (main model), LemmaOne.tla (Lemma 1)
  models/        one .cfg per row of the results table
  tools/         gen_models.py — generates every models/sb_*.cfg and w_*.cfg
  traces/        curated counterexamples
  logs/          TLC logs written by make
docs/          this file and the two findings
```

Edit configurations through `tools/gen_models.py`, not by hand, so the
shared constants stay identical across rows.

### 4.2 Modeling decisions

Lockstep ticks (no drift); slot ages saturating at Θ instead of timestamps
(finite state space without a horizon); SHARE every tick; at most K − 1
consecutive losses; in-flight window of Δ ticks after a cut or crash;
authority evaluated in every state (T_sweep = 0); leader = smallest id;
one partition and one heal per behaviour; converged start; crashes only
during the partition; configurations scripted per scenario. No symmetry
reduction: the leader reducer orders identifiers.

Discrete conditions (ρ̄ = 0, T_sweep = 0, T_resync = 1): Θ_r > K − 1;
Θ ≥ Θ_r + Δ + K − 1 (equality is safe in lockstep, since step-down and
eviction then happen in the same state); Q > Δ + Θ_r; recovery bound
K + Q. Chosen: Θ = 5, Θ_r = 2, Q = 4, K = 2, Δ = 1, T_rebase = 6.

### 4.3 Results — see `split-brain/README.md`

That table is authoritative. All rows have been run (2026-10-04, TLC 2.19,
16-core machine) and every row behaves as expected: each mutation and
witness is violated, each full-design row holds, including `sb_full_n3`
(1,045,001,965 distinct states, exhaustive up to TLC's fingerprint-collision
estimate of 0.018–0.33; see the note under the table).

## 5. The tenure finding (summary)

With tenure reset only on eviction or restart (the draft rule), TLC finds
a dual leader after heal in 8 states: a peer that went stale but was not
evicted keeps full tenure, so the formerly isolated node regains authority
on the first heartbeat while the other side has just elected a successor.
Fix: tenure = time continuously fresh. Full write-up:
[`split-brain-tenure-finding.md`](split-brain-tenure-finding.md).
**The article text (Definition 6, remark after Lemma 3, Theorem 2 handover
paragraph) still states the old rule and must be updated.**

## 6. Open tasks, in order

1. Tag `crash-ft-v1` on the pre-restructure `main` (`f5c6eaf`): done; push
   it before the restructure. A Zenodo release of the tag is still open. The
   CFT article's reference points at the old root-level paths; at
   camera-ready, cite the tag or DOI.
2. ~~Run every configuration and fill the results table.~~ Done; see §4.3.
   Practical notes for reruns: the small rows take about 2.5 min in total
   with one worker. `sb_full_n3` takes about 4 h on 16 cores, needs about
   170 GB of free disk for TLC's state queue (queue files are deleted only
   at checkpoints; `-checkpoint 10` keeps the peak lower), and should be started detached from any session with a
   time limit; `-recover` must be given the original run's `-fp` value.
3. ~~If any row deviates, stop and analyse.~~ No row deviated.
4. Update the article's tenure text (§5 above).
5. Write Section 6 (≈ 1 page): model and abstractions; properties mapped to
   lemmas and theorems (bounded-response form of Theorem 2, witness
   methodology); results table in the CFT format (config, n, change, fault,
   checked, result, states, depth, time); interpretation (each mechanism is
   necessary; the tenure finding; limits: n ≤ 4, no drift).
6. Tag `split-brain-v1`, Zenodo DOI, cite it as the artifact reference.
7. For a double-blind venue, submit with an anonymised mirror
   (e.g. anonymous.4open.science): the organisation name identifies the
   authors.

## 7. Writing conventions for the article

- Laconic, academic but not robotic; short sentences; no filler.
- Define every symbol where it is introduced; never rely on notation from
  the CFT article — refer to its results by name (e.g. "the version gate
  [5]").
- Numbering restarts at 1 in each article (definitions, lemmas,
  equations); use labels so chapters can be renumbered.
- Reference style:
  `N. Title / Authors. Venue. Year. Vol., no., P. URL: https://doi.org/...`
- Page budgets: Sect. 3 ≈ 2 pages, Sect. 4 ≈ 1 page, Sect. 5 ≈ 1 page,
  Sect. 6 ≈ 1 page.
