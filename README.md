# RSDP Crash Fault Tolerance — TLA⁺ Specification

Companion artifact for *Crash Fault Tolerance in the Replica State Discovery
Protocol*. A single module, `spec/rsdp.tla`, models the
memory/eviction core of the reference implementation
([`@rsdp/core`](https://github.com/Replica-State-Discovery-Protocol/core)):
the version gate (eq. 3), the unconditional SHARE heartbeat (eq. 4), TTL
eviction (eq. 5), and the crash-stop / crash-recovery failure models
(Sect. 2.2, eq. 6). The constant `UseIncarnations` selects the gate order:
`FALSE` — the original version-only gate, `TRUE` — the lexicographic
(incarnation, version) gate of Theorem 2′. Each file in `models/` is a TLC
configuration of this module.

## Model scope

The reducer is abstracted behind the admissibility contract (Def. 1): a
stored `(inc, v)` pair is the payload. Time is one global discrete clock;
drift enters only the quantitative bounds, which TLC does not check.
Post-GST synchrony (A2) is encoded by blocking `Tick` while a delivery or a
heartbeat is overdue; the instance is loss-free (the k = 1 case of A1).
Links are per-pair FIFO queues, matching the AMQP carrier. The aggregation
debounce is a latency term, not an ordering constraint, and is not modeled.

## Properties

| Name | Kind | Paper counterpart |
|---|---|---|
| `TypeInvariant` | invariant | well-formedness |
| `NoStaleOverwrite` | action property | gate row 1, eq. (3) |
| `EventualDetection` | liveness | strong completeness, Lemma 2 |
| `EventualAgreement` | liveness | memory-level midpoint of Theorem 1; τ excluded, cf. Prop. 1 |
| `ShadowFree` | invariant | version-shadow witness, Theorem 2 vs 2′ |

## Results

TLC 2.19, OpenJDK 21.0.11, 16 workers / 16 cores, Linux.

| Configuration | n | Gate | Checks | Distinct states | Diameter | Time | Result |
|---|---|---|---|---|---|---|---|
| `safety_n3` | 3 | original | Type, Shadow, Stale, Agreement | 294,843 | 45 | 10 s | ✓ |
| `detect_n3` | 3 | original | + Detection (crash, no recovery) | 680,347 | 56 | 32 s | ✓ |
| `shadow_off` | 3 | original | ShadowFree under crash-recovery | 8,177 to CE | 10-state trace | 1 s | ✗ violated (expected) |
| `shadow_on` | 3 | amended | same scenario, gate flipped | 3,286,066 | 56 | 16 s | ✓ |
| `shadow_recovery_n3` | 3 | amended | + Stale, Detection, Agreement under crash-recovery | 3,286,066 | 56 | 2 min 40 s | ✓ |

The `shadow_off` counterexample (`traces/shadow_off.trace.txt`) is the
version shadow reproduced mechanically in ten states: n2 heartbeats at
v = 2 and is stored by a peer; `Crash(n2)`; `Recover(n2)` — incarnation
bumps, the version counter resets per eq. (6); the recovered node's v = 1
share hits gate row 1 and is discarded without a liveness refresh.
`shadow_on` differs by exactly one constant (`diff models/shadow_*.cfg`)
and satisfies the property over the full 3.3 M-state space.

`shadow_recovery_n3` completes the argument by adding the temporal half.
Its constants are identical to `shadow_on` — amended gate, `FailNodes =
{n2}`, `MaxInc = 2`, `CrashWindow = 4`, `RecoverWindow = 6`, `MaxClock =
10`, `MaxQ = 3` — so it explores the same 3,286,066-state space, but checks
`NoStaleOverwrite`, `EventualDetection` and `EventualAgreement` on top of
the invariants. All hold, exhaustively, in 2 min 40 s (of which 1 min 07 s
is the temporal pass, deferred to the end with `-lncheck final`). This is
the liveness half of Theorem 2′: under the amended gate a cluster that
loses and regains a node re-converges — strong completeness (Lemma 2) and
memory-level agreement both survive crash-recovery, the scenario in which
the original gate produces the version shadow. It is also the only
configuration in this suite that exercises `Crash`, `Recover` and `Sweep`
together, which the `safety_n*` rows cannot: they set `FailNodes = {}`, so
crash-recovery is unreachable and `ShadowFree` holds vacuously there.

### State-space limits at n = 4 and n = 5

`safety_n5` (safety-only, symmetry-reduced, `MaxClock = 7`) was aborted
after 12 h 44 m with 442,411,232 distinct states found and the queue still
growing (sustained ~3 M states/min generated, 12 GB heap). The log is kept
as `logs/safety_n5/n5.log`.

n = 4 was attempted twice on 2026-07-26, both with liveness and without
symmetry, and both aborted.

`safety_n4-a1` (`MaxClock = 8`) ran 1 h 46 m to BFS depth 30, with
90,947,559 distinct states found and 39,471,692 still queued (~3.9 M
states/min generated); see `logs/safety_n4-a1.log`. Successive BFS level
widths were still growing monotonically at abort — levels 26 to 29 measured
5.9 M, 9.8 M, 16.7 M and 31.3 M distinct states (ratios 1.94, 1.66, 1.72,
1.87) — so the search had not yet reached its widest level. Periodic
temporal-property passes cost a further ~20 % of wall-clock and scale
linearly with the behaviour graph.

`safety_n4-a2` (`MaxClock = 7`, `MaxQ = 1`, run with `-lncheck final` so
liveness is deferred to a single pass) reached BFS depth 28 with 66,353,438
distinct states found and 26,194,090 still queued; see
`logs/safety_n4-a2.log`. It was aborted rather than exhausted: depth 28 is
the midpoint of the second heartbeat round and therefore the widest level
of that round, and level 28 alone had produced over 25 M states without
completing, with the entire third round (depths 39–54) still unexplored.
Extrapolating the round-to-round multiplier put the full space at
350 M–1 B distinct states and 10–33 h. `MaxQ = 1` is sound but has no
effect here: with `FailNodes = {}`, `Delta = 1` forces every share to be
delivered before the tick after the one it was sent in, while `TResync = 2`
keeps the sender two ticks away from its next share, so no link ever holds
two messages and the cap is never reached.

Both aborts follow from the diameter, which grows with n² rather than with
the clock horizon. Each heartbeat round costs n `Heartbeat` actions plus
the n(n−1) `Deliver` actions that drain them, and `Tick` is blocked until
nothing is overdue, so with ⌊MaxClock / TResync⌋ rounds:

    diameter ≈ MaxClock + ⌊MaxClock / TResync⌋ · n² + 1

This predicts 45 for `safety_n3` and 56 for both `detect_n3` and
`shadow_recovery_n3` (n = 3, `MaxClock = 10`), matching all three measured
values exactly. It gives ≈ 73 for `safety_n4-a1` (depth 30 at
abort, ≈ 41 %), ≈ 56 for `safety_n4-a2` (depth 28, ≈ 50 %), and ≈ 83 for
`safety_n5` (depth 23 after 12 h 44 m, ≈ 28 %). The same decomposition
explains the level-width profile: within one round of n² actions the number
of distinct partial completions rises to the round midpoint and falls
again, so BFS level widths peak mid-round rather than growing without
bound — a1's monotone growth to depth 30 and a2's peak at depth 28 are both
consistent with this.

Two constraints govern the choice of `MaxClock`. The round count is a floor
division, so the bound only changes at 4–5, 6–7, 8–9. Independently,
`Sweep` requires `now ≥ tau + Theta` and the earliest record has
`tau = TResync`, so eviction — eq. (5) — is unreachable unless

    MaxClock ≥ Theta + TResync   (= 6 for the parameters used here)

`MaxClock = 5` would therefore make the TTL eviction predicate dead code,
which is why a2 uses 7: the same three heartbeat rounds as 6, with two
ticks in which records can expire rather than one.

Exhaustive checking is therefore reported for n = 3. All configurations are
kept in `models/` for reference.

## Running

```bash
make safety_n3      # detect_n3, shadow_off, shadow_on,
                    # safety_n4-a1, safety_n4-a2, safety_n5
```

Each target copies the chosen config next to the module and runs
`tlc2.TLC -workers auto`; `tla2tools.jar` is fetched on first use.
`shadow_off` exits nonzero by design — TLC signals a found counterexample
with exit code 12. `CHECK_DEADLOCK FALSE` is set everywhere because the
model has a bounded horizon (`MaxClock`); end-of-time quiescence is an
artifact of the bound, not of the protocol. `SYMMETRY` appears only in
`safety_n5`: symmetry reduction is unsound under liveness checking.