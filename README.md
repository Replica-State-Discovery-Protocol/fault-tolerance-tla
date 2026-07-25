# RSDP Crash Fault Tolerance — Mechanized Complement

TLA⁺ specification and TLC model configurations accompanying the article
*Crash Fault Tolerance in the Replica State Discovery Protocol* (Kotov & Toliupa).

A single module, `spec/rsdp.tla`, models the memory/eviction core of the
reference implementation ([`@rsdp/core`](https://github.com/Replica-State-Discovery-Protocol/core)):
the version gate (paper eq. 3), the unconditional SHARE heartbeat (eq. 4),
TTL eviction (eq. 5), and the crash-stop / crash-recovery failure models
(Sect. 2.2, eq. 6). The gate order is parameterized by the constant
`UseIncarnations`: `FALSE` = the original version-only gate, `TRUE` = the
amended lexicographic gate of Theorem 2′. Every model in `models/` is a TLC
configuration of this one module.

## Abstractions

- The reducer is abstracted behind the admissibility contract (Definition 1):
  a stored record's `(inc, v)` pair *is* the payload.
- One global discrete clock; drift affects only quantitative bounds, which
  TLC does not check (orderings only).
- Post-GST synchrony (A2) is encoded by blocking `Tick` while a delivery or
  heartbeat is overdue; the instance is loss-free (k = 1 case of A1).
- Per-link FIFO queues, matching the AMQP carrier remark of Sect. 2.
- The aggregation debounce is not modeled (a latency term, not an ordering).

## Properties

| Name | Kind | Paper counterpart |
|---|---|---|
| `TypeInvariant` | invariant | well-formedness |
| `NoStaleOverwrite` | action property | gate row 1 (eq. 3) |
| `EventualDetection` | liveness | strong completeness, Lemma 2 |
| `EventualAgreement` | liveness | memory-level midpoint of Theorem 1 / hypothesis of Prop. 1 (τ excluded) |
| `ShadowFree` | invariant | version-shadow witness, Theorem 2 vs 2′ |

## Verified results (TLC 2.20, OpenJDK 17, 8 workers)

| Configuration | n | Gate | Checks | Distinct states | Diameter | Time | Result |
|---|---|---|---|---|---|---|---|
| `safety_n3` | 3 | original | Type, Shadow, Stale, Agreement | 294,843 | 45 | 1 m 52 s | ✅ |
| `detect_n3` | 3 | original | + Detection (crash, no recovery) | 680,347 | 56 | 4 m 23 s | ✅ |
| `shadow_off` | 3 | **original** | ShadowFree under crash-recovery | 2,559 (BFS to CE) | 9-state trace | 2 s | ❌ **version shadow found** |
| `shadow_on` | 3 | **amended** | identical config, gate flipped | 3,286,066 | 56 | 3 m 12 s | ✅ |
| `safety_n4` | 4 | original | as `safety_n3` | — | — | long run | (run locally) |
| `safety_n5` | 5 | original | safety only + symmetry | — | — | long run | (run locally) |

The `shadow_off` counterexample (committed at `traces/shadow_off.trace.txt`)
is the version shadow rediscovered mechanically in 9 states: heartbeat at
v = 2 stored by a peer → `Crash(n2)` → `Recover(n2)` (incarnation bumps,
counter resets per eq. 6) → the recovered node's v = 1 share is discarded by
gate row 1 without a liveness refresh. `shadow_on` differs from `shadow_off`
by exactly one constant (`diff models/shadow_*.cfg`) and satisfies the same
property over 3.3 M states.

## Running

VS Code: open `spec/rsdp.tla`, `Ctrl+Shift+P` → *TLA+: Check model with TLC*,
pick a config from `models/`.

CLI (recommended for the results table):

```bash
make safety_n3        # or: detect_n3, shadow_off, shadow_on, safety_n4, safety_n5
```

Each target copies the chosen `.cfg` next to the module and invokes
`tlc2.TLC -workers auto`. `tla2tools.jar` is fetched automatically on first
use. Expect `safety_n4` (liveness at n = 4) to run for a long time;
`safety_n5` is safety-only with symmetry reduction for that reason —
symmetry is unsound under liveness checking and is therefore used nowhere else.

`CHECK_DEADLOCK FALSE` is set in every config: the model has a bounded time
horizon (`MaxClock`), so end-of-time quiescence is an artifact of the bound,
not of the protocol.
