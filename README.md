# RSDP Fault Tolerance — TLA⁺ Specifications

The **Replica State Discovery Protocol** (RSDP) is a leaderless, agentless
coordination protocol: each node gossips its view of the cluster, keeps the
views it receives with a time-to-live, and derives the cluster state locally
with deterministic reducers
([reference implementation](https://github.com/Replica-State-Discovery-Protocol/core)).

This repository holds the TLA⁺ models that accompany the articles on RSDP's
fault tolerance. Each model checks the article's central claims with the
TLC model checker, and each design change the article argues for is a
switch in the model: turned off it must produce a counterexample, turned on
the property must hold.

| Folder | Article | Status | Tag |
|---|---|---|---|
| [`cft/`](cft/) | *Crash Fault Tolerance in the Replica State Discovery Protocol: Formal Convergence Guarantees and Empirical Validation* | under review | `crash-ft-v1` |
| [`split-brain/`](split-brain/) | *Split-brain prevention in RSDP* (working title) | in preparation | `split-brain-v1` (planned) |

## Layout

Each article folder is self-contained and laid out the same way:

```
<article>/
  README.md   what the model checks, files, how to run
  docs/       model description, results, the design defect found
  spec/       TLA⁺ modules
  models/     one TLC configuration per checked case
  traces/     counterexamples cited in the docs
  logs/       TLC output of the reported runs
  Makefile    one target per configuration
```

## Running

Requires Java 11 or later and `make`. The TLA⁺ tools (`tla2tools.jar`) are
downloaded to the repository root on first use; the reported runs used
TLC 2.19.

```
make -k cft                    # default CFT configurations
make split-brain               # split-brain configurations, except sb_full_n3
make -C split-brain sb_gate_off   # a single configuration
```

Configurations that are expected to fail make TLC exit with a nonzero code;
`-k` lets `make` continue past them. Each folder's README lists its
configurations, and its `docs/results.md` the outcomes and run times.

## Findings

Model checking found one defect in the protocol design for each article,
and the fix was then checked in the same model:

- **Version shadow** (CFT): a restarted node resets its version counter, so
  its first messages looked stale to its peers and were dropped. Fixed by
  comparing (incarnation, version) pairs.
  [`cft/docs/version-shadow.md`](cft/docs/version-shadow.md)
- **Tenure reset** (split-brain): a peer that fell silent without being
  evicted kept its tenure, which allowed two leaders right after a partition
  healed. Fixed by defining tenure as the time a peer has been continuously
  fresh. [`split-brain/docs/tenure-reset.md`](split-brain/docs/tenure-reset.md)

## Citing

Cite the tag of the article's release (and its Zenodo DOI once minted), not
`main`: the layout of `main` may change. The CFT article refers to the
layout of tag `crash-ft-v1`, where its files sit at the repository root.
