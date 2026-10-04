# RSDP Crash Fault Tolerance — TLA⁺ Specification

Companion artifact for *Crash Fault Tolerance in the Replica State Discovery
Protocol: Formal Convergence Guarantees and Empirical Validation*. The
article's reference resolves to tag `crash-ft-v1`, where these files sit at
the repository root; they moved into `cft/` unchanged.

The model covers the memory/eviction core of RSDP — the version gate, the
SHARE heartbeat and TTL eviction — under crash-stop and crash-recovery
failures, and checks that:

- a stored record is never overwritten by an older one;
- a crashed node is eventually detected (strong completeness);
- the live nodes' memories eventually agree;
- a recovered node is not shadowed by its own pre-crash record. This holds
  only with the amended (incarnation, version) gate; the original gate fails
  it, which is the *version shadow* defect.

## Documentation

| Document | Content |
|---|---|
| [`docs/model.md`](docs/model.md) | what the module models and abstracts, properties and their counterparts in the article |
| [`docs/results.md`](docs/results.md) | results of every configuration; why n = 4 and n = 5 were not checked exhaustively |
| [`docs/version-shadow.md`](docs/version-shadow.md) | the defect, its counterexample and the fix |

## Files

| Path | Content |
|---|---|
| `spec/rsdp.tla` | the model |
| `models/*.cfg` | one TLC configuration per results row |
| `traces/shadow_off.trace.txt` | the version-shadow counterexample |
| `logs/` | TLC output of the reported runs |
| `Makefile` | one target per configuration |

## Running

```bash
make -k          # safety_n3, detect_n3, shadow_off, shadow_on
make shadow_on   # one configuration
```

Each target copies the chosen configuration next to the module and runs
`tlc2.TLC -workers auto`; `tla2tools.jar` is fetched to the repository root
on first use. `shadow_off` exits nonzero by design: TLC signals a found
counterexample with exit code 12. The n = 4 and n = 5 configurations
(`safety_n4-a1`, `safety_n4-a2`, `safety_n5`) run for many hours; see
[`docs/results.md`](docs/results.md).
