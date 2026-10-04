# RSDP Fault Tolerance — TLA⁺ Specifications

Mechanized complements to the articles on the **Replica State Discovery
Protocol** (RSDP), a leaderless coordination protocol
([reference implementation](https://github.com/Replica-State-Discovery-Protocol/core)).
One folder per article, each self-contained and laid out the same way.

| Folder | Article | Status | Tag |
|---|---|---|---|
| [`cft/`](cft/) | *Crash Fault Tolerance in the Replica State Discovery Protocol: Formal Convergence Guarantees and Empirical Validation* | under review | `crash-ft-v1` |
| [`split-brain/`](split-brain/) | *Split-brain prevention in RSDP* (working title) | in preparation | `split-brain-v1` (planned) |

## Layout

```
cft/ , split-brain/
  spec/       TLA⁺ modules
  models/     one TLC configuration per checked case
  traces/     curated counterexamples
  logs/       TLC logs
  Makefile    one target per configuration
  README.md   model scope, properties, results
docs/
  CONTEXT.md                      project context, decisions, open tasks
  cft-version-shadow.md           finding of the CFT article
  split-brain-tenure-finding.md   finding of the split-brain article
```

## Running

Requires Java 11+. `tla2tools.jar` is downloaded to the repository root on
first use.

```
make cft                     # default CFT configurations
make split-brain             # split-brain configurations except the long sb_full_n3
make -C split-brain all      # everything, including sb_full_n3
make -C split-brain sb_gate_off
```

## Findings

Both articles found a defect in the protocol design through model checking
and fixed it:

- **Version shadow** (CFT): a recovered node's reset version counter made
  its SHAREs look stale; fixed by lexicographic (incarnation, version)
  comparison. [`docs/cft-version-shadow.md`](docs/cft-version-shadow.md)
- **Tenure reset** (split-brain): a peer that went stale without being
  evicted kept its tenure, allowing a dual leader right after heal; fixed by
  defining tenure as time continuously fresh.
  [`docs/split-brain-tenure-finding.md`](docs/split-brain-tenure-finding.md)

## Citing

Cite the tag of the article's release (and its Zenodo DOI once minted),
not `main`: the layout of `main` may change.
