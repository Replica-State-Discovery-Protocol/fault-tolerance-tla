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

The `shadow_off` counterexample (`traces/shadow_off.trace.txt`) is the
version shadow reproduced mechanically in ten states: n2 heartbeats at
v = 2 and is stored by a peer; `Crash(n2)`; `Recover(n2)` — incarnation
bumps, the version counter resets per eq. (6); the recovered node's v = 1
share hits gate row 1 and is discarded without a liveness refresh.
`shadow_on` differs by exactly one constant (`diff models/shadow_*.cfg`)
and satisfies the property over the full 3.3 M-state space.

### State-space limit at n = 5

`safety_n5` (safety-only, symmetry-reduced, `MaxClock = 7`) was aborted
after 12 h 44 m with 442,411,232 distinct states found and the queue still
growing (sustained ~3 M states/min generated, 12 GB heap). Exhaustive
checking is therefore reported for n = 3; `safety_n4`, which additionally
carries liveness, was not attempted. Both configurations are kept in
`models/` for reference.

## Running

```bash
make safety_n3      # detect_n3, shadow_off, shadow_on, safety_n4, safety_n5
```

Each target copies the chosen config next to the module and runs
`tlc2.TLC -workers auto`; `tla2tools.jar` is fetched on first use.
`shadow_off` exits nonzero by design — TLC signals a found counterexample
with exit code 12. `CHECK_DEADLOCK FALSE` is set everywhere because the
model has a bounded horizon (`MaxClock`); end-of-time quiescence is an
artifact of the bound, not of the protocol. `SYMMETRY` appears only in
`safety_n5`: symmetry reduction is unsound under liveness checking.