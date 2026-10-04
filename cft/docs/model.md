# CFT model: scope and properties

The module `spec/rsdp.tla` models the memory/eviction core of the reference
implementation
([`@rsdp/core`](https://github.com/Replica-State-Discovery-Protocol/core)):
the version gate (eq. 3), the unconditional SHARE heartbeat (eq. 4), TTL
eviction (eq. 5), and the crash-stop / crash-recovery failure models
(Sect. 2.2, eq. 6). The constant `UseIncarnations` selects the gate order:
`FALSE` — the original version-only gate, `TRUE` — the lexicographic
(incarnation, version) gate of Theorem 2′. Each file in `models/` is a TLC
configuration of this module. Equation, section and theorem numbers refer to
the CFT article.

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


## Configuration settings

`CHECK_DEADLOCK FALSE` is set everywhere because the model has a bounded
horizon (`MaxClock`); end-of-time quiescence is an artifact of the bound,
not of the protocol. `SYMMETRY` appears only in `safety_n5`: symmetry
reduction is unsound under liveness checking.
