# RSDP Split-Brain Prevention — TLA⁺ Specification

Companion artifact for the split-brain article (working title *Split-brain
prevention in the Replica State Discovery Protocol*).

During a network partition, every side of an RSDP cluster keeps running its
reducers, so a reducer that elects a leader would elect one per side. The
article adds a mechanism that lets a node present such *exclusive* outputs
only while it holds *authority* — while the voters it hears form a weighted
majority of its configuration — and that keeps this safe across voter
changes, restarts and heal.

The model answers two questions:

- **Does the full design prevent split-brain?** No two nodes act as leader
  at once, outputs on the two sides of a partition never conflict, a
  majority side keeps authority, and every node regains it within a bounded
  time after heal. All of this holds exhaustively at n = 3 with any
  partition, crashes and restarts on either side, and heal (about 10⁹
  states), and at n = 4 for each reconfiguration scenario.
- **Is each part of it necessary?** Every element of the mechanism is a
  switch in the configuration. Switching any one off produces a dual leader,
  with counterexamples of 4–9 states.

Building the model also exposed a defect in the draft's definition of
tenure; the model checks the corrected definition.

## Documentation

| Document | Content |
|---|---|
| [`docs/model.md`](docs/model.md) | the mechanism in brief, what the model covers and abstracts, parameters, switches, scenarios, properties |
| [`docs/results.md`](docs/results.md) | results of every configuration, how to read them, how to reproduce them |
| [`docs/tenure-reset.md`](docs/tenure-reset.md) | the tenure defect, its counterexample and the fix |

## Files

| Path | Content |
|---|---|
| `spec/SplitBrain.tla` | the main model |
| `spec/LemmaOne.tla` | exhaustive arithmetic check of Lemma 1 (majorities of adjacent configurations intersect) |
| `models/*.cfg` | one TLC configuration per results row |
| `tools/gen_models.py` | generates every `sb_*` and `w_*` configuration from one table |
| `traces/*.trace.txt` | counterexamples of the mutation rows |
| `logs/` | TLC output of the reported runs |
| `run.sh` | runs one configuration outside `make` |
| `Makefile` | one target per configuration, plus `quick` and `all` |

## Running

```bash
make quick          # every configuration except sb_full_n3, about 2.5 min
make sb_gate_off    # one configuration
make all            # including sb_full_n3, about 4 h on 16 cores
```

Runs use one worker by default so that counterexamples are shortest and
depths exact (`WORKERS=auto` overrides). `sb_full_n3` needs plenty of disk;
see [`docs/results.md`](docs/results.md#reproducing).
