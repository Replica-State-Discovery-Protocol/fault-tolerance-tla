------------------------------- MODULE rsdp -------------------------------
(***************************************************************************)
(* Mechanized model of the RSDP memory/eviction core.                     *)
(*                                                                         *)
(* Action <-> paper mapping (Kotov & Toliupa, CFT article):                *)
(*   Deliver(i,j)  = version gate, eq. (3)                                 *)
(*   Heartbeat(i)  = unconditional SHARE cadence, eq. (4)                  *)
(*   Sweep(i)      = TTL eviction predicate, eq. (5)                       *)
(*   Crash/Recover = failure model Sect. 2.2; volatile-state loss eq. (6)  *)
(*   Newer         = original (v-only) vs amended lexicographic (inc, v)   *)
(*                   gate of Theorem 2', switched by UseIncarnations       *)
(*                                                                         *)
(* Abstractions (stated in Sect. "Mechanized complement"):                 *)
(*   - reducer replaced by identity on payload multisets (Definition 1);   *)
(*     a stored record's (inc, v) IS the payload                           *)
(*   - single global discrete clock; drift affects only quantitative       *)
(*     bounds, which TLC does not check (orderings only)                   *)
(*   - debounce not modeled (latency term, not an ordering constraint)     *)
(*   - post-GST synchrony (A2) encoded by blocking Tick while a delivery   *)
(*     or heartbeat is overdue; no message loss (k = 1 instance of A1)     *)
(*   - FIFO per-link queues, matching the AMQP carrier remark of Sect. 2   *)
(***************************************************************************)
EXTENDS Naturals, Sequences, TLC

CONSTANTS
    Nodes,              \* set of node identities (model values)
    UseIncarnations,    \* BOOLEAN: amended gate (Thm 2') vs original
    Theta,              \* eviction timeout, eq. (5)
    TResync,            \* heartbeat period, eq. (4)
    Delta,              \* post-GST delivery bound, A2
    MaxV,               \* version cap                (model bound)
    MaxInc,             \* incarnation cap            (model bound)
    MaxClock,           \* time horizon               (model bound)
    MaxQ,               \* per-link queue cap         (model bound)
    FailNodes,          \* nodes permitted to crash
    CrashWindow,        \* Crash enabled only while now < CrashWindow
    RecoverWindow       \* Recover enabled only while now < RecoverWindow

ASSUME Theta > TResync + Delta   \* accuracy condition (11), k = 1, rho = 0

VARIABLES
    now,        \* global discrete clock
    op,         \* op[i]      : node i operational?
    inc,        \* inc[i]     : node i's current incarnation (life number)
    ver,        \* ver[i]     : node i's outbound version counter
    lastHb,     \* lastHb[i]  : local time of i's last SHARE broadcast
    mem,        \* mem[i][j]  : i's record of peer j -- Sigma_i, eq. (3)
    q,          \* q[i][j]    : FIFO in-flight queue from i to j
    rejections  \* saturating flag: 1 iff a current-life share was ever
                \* discarded as stale (the version-shadow witness)

vars == <<now, op, inc, ver, lastHb, mem, q, rejections>>

(***************************************************************************)
(* Records and the gate order.  The empty slot is the bottom element       *)
(* (0, 0): every genuine payload (inc >= 1, v >= 1) exceeds it under both  *)
(* gate variants, so no empty-slot special case is needed.                 *)
(***************************************************************************)
NoRec == [inc |-> 0, v |-> 0, tau |-> 0]

Msg == [from : Nodes, inc : 1..MaxInc, v : 1..MaxV, sentAt : 0..MaxClock]

\* Amended lexicographic order of Theorem 2' when UseIncarnations,
\* the original version-only order otherwise.
Newer(mi, mv, si, sv) ==
    IF UseIncarnations
        THEN mi > si \/ (mi = si /\ mv > sv)
        ELSE mv > sv

Same(mi, mv, si, sv) ==
    IF UseIncarnations
        THEN mi = si /\ mv = sv
        ELSE mv = sv

\* Bounded-buffer append: oldest message shed when the link is full.
AppendCap(s, m) == IF Len(s) < MaxQ THEN Append(s, m) ELSE Append(Tail(s), m)

(***************************************************************************)
(* Initial state: all nodes up in their first life, empty memories,       *)
(* empty links, first heartbeat due at TResync.                            *)
(***************************************************************************)
Init ==
    /\ now = 0
    /\ op = [i \in Nodes |-> TRUE]
    /\ inc = [i \in Nodes |-> 1]
    /\ ver = [i \in Nodes |-> 1]
    /\ lastHb = [i \in Nodes |-> 0]
    /\ mem = [i \in Nodes |-> [j \in Nodes |-> NoRec]]
    /\ q = [i \in Nodes |-> [j \in Nodes |-> <<>>]]
    /\ rejections = 0

(***************************************************************************)
(* Heartbeat(i) -- eq. (4): the DEBATE handler emits a SHARE               *)
(* unconditionally each round; the version may bump (view changed) or not  *)
(* (pure heartbeat), nondeterministically, bounded by MaxV.                *)
(***************************************************************************)
Heartbeat(i) ==
    /\ op[i]
    /\ now >= lastHb[i] + TResync
    /\ \E nv \in {ver[i], IF ver[i] < MaxV THEN ver[i] + 1 ELSE ver[i]} :
        /\ ver' = [ver EXCEPT ![i] = nv]
        /\ q' = [s \in Nodes |-> [d \in Nodes |->
                    IF s = i /\ d # i
                        THEN AppendCap(q[s][d],
                                [from |-> i, inc |-> inc[i],
                                 v |-> nv, sentAt |-> now])
                        ELSE q[s][d]]]
    /\ lastHb' = [lastHb EXCEPT ![i] = now]
    /\ UNCHANGED <<now, op, inc, mem, rejections>>

(***************************************************************************)
(* Deliver(i, j) -- the version gate, eq. (3).  Receiver i consumes the    *)
(* head of the FIFO queue from j.  Three rows:                             *)
(*   newer -> replace payload, refresh tau (recompute trigger)             *)
(*   same  -> refresh tau only (the heartbeat row)                         *)
(*   stale -> discard, NO tau refresh (no liveness credit)                 *)
(* The rejections flag saturates to 1 when a discarded message belongs to  *)
(* the sender's CURRENT life while the sender is operational: the          *)
(* observable witness of the version shadow.                               *)
(***************************************************************************)
Deliver(i, j) ==
    /\ op[i]
    /\ Len(q[j][i]) > 0
    /\ LET m == Head(q[j][i])
           cur == mem[i][j]
           isNewer == Newer(m.inc, m.v, cur.inc, cur.v)
           isSame == Same(m.inc, m.v, cur.inc, cur.v)
       IN
        /\ q' = [q EXCEPT ![j][i] = Tail(@)]
        /\ mem' = [mem EXCEPT ![i][j] =
                IF isNewer THEN [inc |-> m.inc, v |-> m.v, tau |-> now]
                ELSE IF isSame THEN [@ EXCEPT !.tau = now]
                ELSE @]
        /\ rejections' =
                IF ~isNewer /\ ~isSame /\ m.inc = inc[j] /\ op[j]
                    THEN 1 ELSE rejections
    /\ UNCHANGED <<now, op, inc, ver, lastHb>>

(***************************************************************************)
(* Sweep(i) -- eq. (5): evict every record unseen for Theta.  Enabled      *)
(* only while something is expired; weak fairness makes eviction           *)
(* inevitable (strong completeness, Lemma 2).                              *)
(***************************************************************************)
Expired(i, j) == mem[i][j] # NoRec /\ now >= mem[i][j].tau + Theta

Sweep(i) ==
    /\ op[i]
    /\ \E j \in Nodes \ {i} : Expired(i, j)
    /\ mem' = [mem EXCEPT ![i] =
            [j \in Nodes |-> IF Expired(i, j) THEN NoRec ELSE mem[i][j]]]
    /\ UNCHANGED <<now, op, inc, ver, lastHb, q, rejections>>

(***************************************************************************)
(* Crash(j) -- crash-stop, Sect. 2.2: silent halt, no CLOSE ever (the      *)
(* inline no-CLOSE fact); in-flight messages of the dead life linger.      *)
(* Recover(j) -- crash-recovery, eq. (6): same identity, volatile state    *)
(* lost, outbound counter reset to 1; the incarnation increments (the      *)
(* actual life number -- the ORIGINAL gate simply ignores it on the wire). *)
(* Neither action is fair: TLC explores both occurrence and absence.       *)
(***************************************************************************)
Crash(j) ==
    /\ op[j]
    /\ j \in FailNodes
    /\ now < CrashWindow
    /\ op' = [op EXCEPT ![j] = FALSE]
    /\ UNCHANGED <<now, inc, ver, lastHb, mem, q, rejections>>

Recover(j) ==
    /\ ~op[j]
    /\ now < RecoverWindow
    /\ inc[j] < MaxInc
    /\ op' = [op EXCEPT ![j] = TRUE]
    /\ inc' = [inc EXCEPT ![j] = inc[j] + 1]
    /\ ver' = [ver EXCEPT ![j] = 1]
    /\ mem' = [mem EXCEPT ![j] = [jj \in Nodes |-> NoRec]]
    /\ lastHb' = [lastHb EXCEPT ![j] =
            IF now >= TResync THEN now - TResync ELSE 0]
    /\ UNCHANGED <<now, q, rejections>>

(***************************************************************************)
(* Tick -- global time.  Post-GST synchrony (A2) and the heartbeat cadence *)
(* are encoded as blocking conditions: time cannot pass an overdue         *)
(* delivery to a live node, nor an overdue heartbeat of a live node.       *)
(* Queues to crashed nodes do not block time (the AMQP broker buffers).    *)
(***************************************************************************)
NoOverdueHb == \A i \in Nodes : op[i] => now < lastHb[i] + TResync
NoOverdueMsg == \A i \in Nodes : op[i] =>
                    \A j \in Nodes \ {i} :
                        Len(q[j][i]) > 0 => now < Head(q[j][i]).sentAt + Delta

Tick ==
    /\ now < MaxClock
    /\ NoOverdueHb
    /\ NoOverdueMsg
    /\ now' = now + 1
    /\ UNCHANGED <<op, inc, ver, lastHb, mem, q, rejections>>

Next ==
    \/ Tick
    \/ \E i \in Nodes : Heartbeat(i)
    \/ \E i \in Nodes : \E j \in Nodes \ {i} : Deliver(i, j)
    \/ \E i \in Nodes : Sweep(i)
    \/ \E j \in Nodes : Crash(j)
    \/ \E j \in Nodes : Recover(j)

(***************************************************************************)
(* Fairness: time flows, due heartbeats fire, queued messages arrive,     *)
(* expired records are swept.  Crash and Recover are deliberately unfair.  *)
(***************************************************************************)
Fairness ==
    /\ WF_vars(Tick)
    /\ \A i \in Nodes : WF_vars(Heartbeat(i))
    /\ \A i \in Nodes : WF_vars(Sweep(i))
    /\ \A i \in Nodes : \A j \in Nodes \ {i} : WF_vars(Deliver(i, j))

Spec == Init /\ [][Next]_vars /\ Fairness

(***************************************************************************)
(* Properties                                                              *)
(***************************************************************************)

TypeInvariant ==
    /\ now \in 0..MaxClock
    /\ op \in [Nodes -> BOOLEAN]
    /\ inc \in [Nodes -> 1..MaxInc]
    /\ ver \in [Nodes -> 1..MaxV]
    /\ lastHb \in [Nodes -> 0..MaxClock]
    /\ rejections \in 0..1
    /\ \A i \in Nodes : \A j \in Nodes :
        \/ mem[i][j] = NoRec
        \/ mem[i][j] \in [inc : 1..MaxInc, v : 1..MaxV, tau : 0..MaxClock]
    /\ \A i \in Nodes : \A j \in Nodes :
        /\ Len(q[i][j]) <= MaxQ
        /\ \A k \in 1..Len(q[i][j]) : q[i][j][k] \in Msg

\* The mechanized counterpart of gate row 1: an occupied slot is only ever
\* overwritten by a strictly newer value (under the active gate order).
StaleStep ==
    \A i \in Nodes : \A j \in Nodes :
        LET old == mem[i][j]
            new == mem'[i][j]
        IN (old # NoRec /\ new # NoRec /\ (new.inc # old.inc \/ new.v # old.v))
            => Newer(new.inc, new.v, old.inc, old.v)

NoStaleOverwrite == [][StaleStep]_vars

\* Strong completeness (Lemma 2): a permanently crashed node is eventually
\* permanently absent from every correct memory.
EventualDetection ==
    \A j \in Nodes :
        (<>[](~op[j])) => (<>[](\A i \in Nodes : op[i] => mem[i][j] = NoRec))

\* Memory-level agreement (the midpoint of Theorem 1, the hypothesis of
\* Proposition 1): payloads (inc, v) compared, tau deliberately excluded.
RecEq(a, b) == a.inc = b.inc /\ a.v = b.v

AgreementNow ==
    \A i1, i2 \in Nodes :
        (op[i1] /\ op[i2]) =>
            \A j \in Nodes \ {i1, i2} : RecEq(mem[i1][j], mem[i2][j])

EventualAgreement == <>[] AgreementNow

\* The version-shadow witness (Theorem 2 vs 2'): no share of a sender's
\* current life is ever discarded as stale.  Violated by the original
\* gate under crash-recovery; holds under the amended gate.
ShadowFree == rejections = 0

\* Symmetry set for safety-only large runs (unsound for liveness checking).
NodePerms == Permutations(Nodes)

=============================================================================
