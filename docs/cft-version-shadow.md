# Finding: the version shadow (crash-fault-tolerance article)

Summary of the defect found while writing the crash-fault-tolerance
article; details and logs are in [`../cft/README.md`](../cft/README.md).

## The defect

The original version gate accepted a SHARE only if its version exceeded the
stored one. A node that crashes and recovers resets its outbound version
counter, so its first SHAREs after recovery carry versions *below* the one
its peers still store from its previous life. They are discarded as stale
and do not refresh the peer's timestamp. The recovered node stays shadowed
by its own old record until TTL eviction, and if its counter stabilises at
the stored version it is never readmitted (Theorem 2 of the article).

## How it was found

Configuration `cft/models/shadow_off.cfg` (original gate, crash-recovery)
violates `ShadowFree` in a 10-state trace
(`cft/traces/shadow_off.trace.txt`): n2 heartbeats at v = 2 and is stored;
`Crash(n2)`; `Recover(n2)` bumps the incarnation and resets the version;
the recovered node's v = 1 SHARE hits gate row 1 and is discarded.

## The fix

Each restart generates a higher incarnation number ι, and the gate compares
(ι, v) lexicographically (Theorem 2′). A recovered node's first SHARE
carries (ι_new, 1) > (ι_old, v_pre) and is admitted immediately.

## Verification

`shadow_on` differs from `shadow_off` by one constant and satisfies
`ShadowFree` over 3,286,066 distinct states; `shadow_recovery_n3` adds the
liveness properties and also holds.

The split-brain work builds on this fix: partition detection
(heal vs restart) and the quarantine of Lemma 3 both rely on incarnations.
