----------------------------- MODULE SplitBrain -----------------------------
(***************************************************************************)
(* Split-brain prevention in RSDP: authority-gated translation of          *)
(* exclusive reducers (companion artifact, split-brain article).           *)
(*                                                                         *)
(* Action <-> paper mapping:                                               *)
(*   Tick       one SHARE round: ageing, TTL eviction, delivery, version / *)
(*              incarnation gate, configuration adoption (Sect. 3.1, (1))  *)
(*   Partition  network split into side A and the rest (Sect. 5, C1)       *)
(*   Heal       partition ends (Theorem 2 ii)                              *)
(*   Crash, Restart   crash-recovery during a partition (relaxed C3)       *)
(*   Inject     administrative configuration change (Definition 4, A3)     *)
(*   Auth       authority predicate (Definition 7)                         *)
(*   Output     gated translation of the leader reducer (Definition 8)     *)
(*                                                                         *)
(* Abstractions:                                                           *)
(*   - lockstep ticks: one global Tick advances every node; no clock drift *)
(*   - slots store ages (ticks since last heard), saturating at Theta      *)
(*     (= evicted), so the state space is finite without a time horizon    *)
(*   - every node sends SHARE every tick (T_resync = 1); a link may lose   *)
(*     at most K - 1 consecutive SHAREs                                    *)
(*   - Delta: messages sent before a cut or a crash may still arrive for   *)
(*     Delta ticks afterwards (in-flight window)                           *)
(*   - authority is a derived operator, evaluated in every state           *)
(*     (T_sweep = 0)                                                       *)
(*   - reducers: leader = smallest identifier, members = identity set;     *)
(*     payloads carry only identifier, incarnation and configuration       *)
(*   - one partition and at most one heal per behaviour; the cluster       *)
(*     starts converged; crashes and restarts only during the partition    *)
(*   - configurations are drawn from a scripted list per scenario and      *)
(*     identified by their epoch, so one electorate per epoch (A3) holds   *)
(*     by construction                                                     *)
(*                                                                         *)
(* Mechanism switches (each mutation is a .cfg, never a code change):      *)
(*   GATE, AGG, ThetaR, Q, TENURE, CHECK_ADJ, CHECK_CAP, CHECK_SPACING     *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets, Sequences, TLC

CONSTANTS
    N,              \* nodes are 1..N, ordered by identifier
    Theta,          \* eviction threshold (ticks)
    ThetaR,         \* freshness threshold (ticks)
    Q,              \* quarantine: minimum tenure for a vote (ticks)
    K,              \* at most K - 1 consecutive SHARE losses per link
    Delta,          \* in-flight window after a cut or a crash (ticks)
    TRebase,        \* minimum spacing of configuration changes, A3 (ticks)
    MaxInc,         \* incarnation bound (model bound)
    RecBound,       \* bounded-response horizon after heal, Theorem 2 (ticks)
    GATE,           \* TRUE: exclusive output gated by authority (Def. 8)
    AGG,            \* "sigma": leader over Sigma; "fresh": over Fresh
    TENURE,         \* "fresh": tenure resets when a peer stops being fresh
                    \* "evict": tenure resets only on eviction or restart
    CHECK_ADJ,      \* injection requires adjacency (i)-(iii), Def. 3
    CHECK_CAP,      \* injection requires the weight cap (iv), Def. 3
    CHECK_SPACING,  \* injections at least TRebase apart, A3
    ALLOW_HEAL,     \* enable Heal
    TRACK_CLAIMS,   \* record members claims for MergeOnHeal
    SCENARIO        \* scenario name, see below

ASSUME /\ N \in Nat /\ N >= 2
       /\ ThetaR \in 1..Theta /\ K >= 1 /\ Delta >= 1
       /\ AGG \in {"sigma", "fresh"} /\ TENURE \in {"fresh", "evict"}

Node   == 1..N
NoNode == 0                 \* bottom: "no output"

Mn(a, b) == IF a < b THEN a ELSE b
Mx(S)    == CHOOSE x \in S : \A y \in S : y <= x
MinOf(S) == CHOOSE x \in S : \A y \in S : x <= y

(***************************************************************************)
(* Configurations (Definition 1). A configuration is a record with the     *)
(* electorate vot and weights w over all nodes (0 outside vot). Epoch e    *)
(* is Configs[e]; epoch 0 is the empty configuration held after restart.   *)
(***************************************************************************)
Cfg(vot, wl) == [vot |-> vot, w |-> [n \in Node |-> IF n \in vot THEN wl[n] ELSE 0]]
Unit == [n \in Node |-> 1]
EmptyCfg == [vot |-> {}, w |-> [n \in Node |-> 0]]

RECURSIVE SumW(_, _)
SumW(c, S) == IF S = {} THEN 0
              ELSE LET x == CHOOSE y \in S : TRUE IN c.w[x] + SumW(c, S \ {x})

W(c, S)   == SumW(c, S \cap c.vot)               \* Definition 2
Maj(c, S) == 2 * W(c, S) > W(c, c.vot)
Mu2(c)    == MinOf({2 * W(c, X) - W(c, c.vot) : X \in {Y \in SUBSET c.vot : Maj(c, Y)}})

Diff(c, d)  == (c.vot \ d.vot) \cup (d.vot \ c.vot)
AdjOK(c, d) == /\ Cardinality(Diff(c, d)) <= 1
               /\ \A n \in c.vot \cap d.vot : c.w[n] = d.w[n]
CapOK(c, d) == \A e \in Diff(c, d) :
                   LET with    == IF e \in c.vot THEN c ELSE d
                       without == IF e \in c.vot THEN d ELSE c
                   IN  with.w[e] <= Mu2(without)

(***************************************************************************)
(* Scenarios. Configs[1] is the initial configuration; Configs[2..] are    *)
(* the changes the administrator issues, in order, at node Injector.       *)
(* Sides lists the candidate side-A sets at partition time.                *)
(***************************************************************************)
Configs ==
    CASE SCENARIO \in {"s3any", "s3cut", "s3quar"} -> << Cfg({1,2,3}, Unit) >>
      [] SCENARIO = "s4adj"     -> << Cfg({1,2,3}, Unit), Cfg({1,2,4}, Unit) >>
      [] SCENARIO = "s4spacing" -> << Cfg({1,2,3}, Unit), Cfg({1,2,3,4}, Unit),
                                      Cfg({1,2,4}, Unit) >>
      [] SCENARIO = "s4cap"     -> << Cfg({1,2,3}, <<1,1,3,0>>),
                                      Cfg({1,2,3,4}, <<1,1,3,2>>) >>
      [] SCENARIO = "s4tie"     -> << Cfg({1,2,3,4}, Unit), Cfg({1,2,4}, Unit) >>

Sides ==
    CASE SCENARIO = "s3any"                  -> {{1}, {2}, {3}}
      [] SCENARIO \in {"s3cut", "s3quar"}     -> {{1}}
      [] SCENARIO \in {"s4adj", "s4spacing"}  -> {{1, 4}}
      [] SCENARIO = "s4cap"                  -> {{1, 2, 4}}
      [] SCENARIO = "s4tie"                  -> {{1, 2}}

CrashSet ==
    CASE SCENARIO = "s3any"  -> Node
      [] SCENARIO = "s3quar" -> {3}
      [] OTHER               -> {}

Injector == 1

VARIABLES
    alive,          \* alive[i]: node i is running
    inc,            \* inc[i]: incarnation of node i
    cfg,            \* cfg[i]: epoch of the configuration node i holds
    age,            \* age[i][j]: ticks since i last heard j; Theta = no slot
    ten,            \* ten[i][j]: tenure of j at i, saturating at Q
    selfTen,        \* selfTen[i]: ticks since i started, saturating at Q
    linc,           \* linc[i][j]: last incarnation of j seen by i (0: never)
    loss,           \* loss[i][j]: consecutive SHARE losses on link j -> i
    phase,          \* "pre", "part", "healed"
    sideA,          \* side A of the partition
    cutAge,         \* ticks since the partition, saturating at Delta
    deadAge,        \* deadAge[i]: ticks since i crashed, saturating at Delta
    pc,             \* epoch of the newest configuration issued
    sinceInject,    \* ticks since the last accepted change, saturating
    sinceHeal,      \* ticks since heal, saturating at RecBound
    anyCrash,       \* ghost: a crash has occurred
    moved,          \* ghost: moved[j] = j restarted into the other side
    injectedInPart, \* ghost: a change was accepted during the partition
    claims          \* ghost: claims[i] = members presented during partition

vars == <<alive, inc, cfg, age, ten, selfTen, linc, loss, phase, sideA,
          cutAge, deadAge, pc, sinceInject, sinceHeal, anyCrash, moved,
          injectedInPart, claims>>

(***************************************************************************)
(* Derived state: freshness, votes, authority, outputs (Definitions 5-8).  *)
(***************************************************************************)
CurCfg(i)  == IF cfg[i] = 0 THEN EmptyCfg ELSE Configs[cfg[i]]
Fresh(i)   == {j \in Node \ {i} : age[i][j] < ThetaR} \cup {i}
Vote(i)    == {j \in Fresh(i) \cap CurCfg(i).vot :
                  IF j = i THEN selfTen[i] >= Q ELSE ten[i][j] >= Q}
Auth(i)    == alive[i] /\ Maj(CurCfg(i), Vote(i))

Leader(i)  == MinOf({i} \cup {j \in Node \ {i} :
                  IF AGG = "sigma" THEN age[i][j] < Theta ELSE age[i][j] < ThetaR})
Output(i)  == IF ~alive[i] \/ (GATE /\ ~Auth(i)) THEN NoNode ELSE Leader(i)
Acting(i)  == Output(i) = i
Members(i) == {i} \cup {j \in Node \ {i} : age[i][j] < Theta}

SameSide(i, j) == phase # "part" \/ ((i \in sideA) <=> (j \in sideA))

(***************************************************************************)
(* Links. A regular link delivers unless loss is still permitted; an       *)
(* in-flight delivery (after a cut or a crash) may or may not happen.      *)
(***************************************************************************)
Regular(j, i)   == j # i /\ alive[i] /\ alive[j] /\ SameSide(i, j)
InFlight(j, i)  == /\ j # i /\ alive[i] /\ ~Regular(j, i)
                   /\ (alive[j] \/ deadAge[j] < Delta)
                   /\ (SameSide(i, j) \/ cutAge < Delta)
Optional(j, i)  == InFlight(j, i) \/ (Regular(j, i) /\ loss[i][j] < K - 1)
Mandatory(j, i) == Regular(j, i) /\ loss[i][j] = K - 1

Init ==
    /\ alive   = [i \in Node |-> TRUE]
    /\ inc     = [i \in Node |-> 1]
    /\ cfg     = [i \in Node |-> 1]
    /\ age     = [i \in Node |-> [j \in Node |-> 0]]
    /\ ten     = [i \in Node |-> [j \in Node |-> Q]]
    /\ selfTen = [i \in Node |-> Q]
    /\ linc    = [i \in Node |-> [j \in Node |-> 1]]
    /\ loss    = [i \in Node |-> [j \in Node |-> 0]]
    /\ phase = "pre" /\ sideA = {} /\ cutAge = Delta
    /\ deadAge = [i \in Node |-> Delta]
    /\ pc = 1 /\ sinceInject = TRebase /\ sinceHeal = 0
    /\ anyCrash = FALSE /\ moved = [i \in Node |-> FALSE]
    /\ injectedInPart = FALSE
    /\ claims = [i \in Node |-> {}]

(***************************************************************************)
(* One SHARE round. Slots age first (eviction at Theta), then deliveries   *)
(* are applied; a delivery to an evicted slot, or one carrying a higher    *)
(* incarnation, creates a new slot with tenure 0.                          *)
(***************************************************************************)
Tick ==
  \E O \in SUBSET {p \in Node \X Node : Optional(p[1], p[2])} :
    LET Del(j, i)     == Mandatory(j, i) \/ <<j, i>> \in O
        Acc(j, i)     == Del(j, i) /\ inc[j] >= linc[i][j]
        Aged(i, j)    == IF age[i][j] >= Theta - 1 THEN Theta ELSE age[i][j] + 1
        NewAge(i, j)  == IF Acc(j, i) THEN 0 ELSE Aged(i, j)
        NewSlot(i, j) == Acc(j, i) /\ (Aged(i, j) = Theta \/ inc[j] > linc[i][j])
        Reset(i, j)   == \/ NewSlot(i, j)
                         \/ NewAge(i, j) = Theta
                         \/ (TENURE = "fresh" /\ (age[i][j] >= ThetaR
                                                 \/ NewAge(i, j) >= ThetaR))
    IN
    /\ age' = [i \in Node |-> [j \in Node |->
                 IF j = i \/ ~alive[i] THEN age[i][j] ELSE NewAge(i, j)]]
    /\ ten' = [i \in Node |-> [j \in Node |->
                 IF j = i \/ ~alive[i] THEN ten[i][j]
                 ELSE IF Reset(i, j) THEN 0 ELSE Mn(ten[i][j] + 1, Q)]]
    /\ linc' = [i \in Node |-> [j \in Node |->
                 IF Acc(j, i) THEN inc[j] ELSE linc[i][j]]]
    /\ loss' = [i \in Node |-> [j \in Node |->
                 IF Regular(j, i) /\ ~Del(j, i) THEN loss[i][j] + 1 ELSE 0]]
    /\ cfg' = [i \in Node |->
                 IF ~alive[i] THEN cfg[i]
                 ELSE Mx({cfg[i]} \cup {cfg[j] : j \in {k \in Node : Acc(k, i)}})]
    /\ selfTen' = [i \in Node |-> IF alive[i] THEN Mn(selfTen[i] + 1, Q) ELSE selfTen[i]]
    /\ deadAge' = [i \in Node |-> IF alive[i] THEN deadAge[i] ELSE Mn(deadAge[i] + 1, Delta)]
    /\ cutAge' = IF phase = "part" THEN Mn(cutAge + 1, Delta) ELSE cutAge
    /\ sinceInject' = IF CHECK_SPACING THEN Mn(sinceInject + 1, TRebase) ELSE sinceInject
    /\ sinceHeal' = IF phase = "healed" THEN Mn(sinceHeal + 1, RecBound) ELSE sinceHeal
    /\ claims' = IF TRACK_CLAIMS /\ phase = "part"
                 THEN [i \in Node |-> IF alive[i] THEN claims[i] \cup Members(i)
                                      ELSE claims[i]]
                 ELSE claims
    /\ UNCHANGED <<alive, inc, phase, sideA, pc, anyCrash, moved, injectedInPart>>

Partition ==
    /\ phase = "pre"
    /\ \E S \in Sides : sideA' = S
    /\ phase' = "part"
    /\ cutAge' = 0
    /\ UNCHANGED <<alive, inc, cfg, age, ten, selfTen, linc, loss, deadAge, pc,
                   sinceInject, sinceHeal, anyCrash, moved, injectedInPart, claims>>

Heal ==
    /\ ALLOW_HEAL
    /\ phase = "part"
    /\ cutAge = Delta
    /\ phase' = "healed"
    /\ sinceHeal' = 0
    /\ claims' = IF TRACK_CLAIMS
                 THEN [i \in Node |-> IF alive[i] THEN claims[i] \cup Members(i)
                                      ELSE claims[i]]
                 ELSE claims
    /\ UNCHANGED <<alive, inc, cfg, age, ten, selfTen, linc, loss, sideA, cutAge,
                   deadAge, pc, sinceInject, anyCrash, moved, injectedInPart>>

Crash(i) ==
    /\ phase = "part" /\ cutAge = Delta
    /\ i \in CrashSet /\ alive[i]
    /\ alive' = [alive EXCEPT ![i] = FALSE]
    /\ deadAge' = [deadAge EXCEPT ![i] = 0]
    /\ anyCrash' = TRUE
    /\ UNCHANGED <<inc, cfg, age, ten, selfTen, linc, loss, phase, sideA, cutAge,
                   pc, sinceInject, sinceHeal, moved, injectedInPart, claims>>

\* Volatile state is lost; the node may come back on either side.
Restart(i) ==
    /\ phase = "part"
    /\ ~alive[i] /\ deadAge[i] = Delta /\ inc[i] < MaxInc
    /\ \E toA \in BOOLEAN :
         /\ sideA' = IF toA THEN sideA \cup {i} ELSE sideA \ {i}
         /\ moved' = [moved EXCEPT ![i] = (toA # (i \in sideA))]
    /\ alive'   = [alive EXCEPT ![i] = TRUE]
    /\ inc'     = [inc EXCEPT ![i] = inc[i] + 1]
    /\ cfg'     = [cfg EXCEPT ![i] = 0]
    /\ age'     = [age EXCEPT ![i] = [j \in Node |-> IF j = i THEN age[i][i] ELSE Theta]]
    /\ ten'     = [ten EXCEPT ![i] = [j \in Node |-> IF j = i THEN ten[i][i] ELSE 0]]
    /\ selfTen' = [selfTen EXCEPT ![i] = 0]
    /\ linc'    = [linc EXCEPT ![i] = [j \in Node |-> 0]]
    /\ loss'    = [loss EXCEPT ![i] = [j \in Node |-> 0]]
    /\ UNCHANGED <<phase, cutAge, deadAge, pc, sinceInject, sinceHeal, anyCrash,
                   injectedInPart, claims>>

\* Only accepted changes are modelled; a rejected request changes nothing.
Inject ==
    /\ phase # "healed"
    /\ pc < Len(Configs)
    /\ alive[Injector] /\ cfg[Injector] = pc /\ Auth(Injector)
    /\ ~CHECK_ADJ     \/ AdjOK(Configs[pc], Configs[pc + 1])
    /\ ~CHECK_CAP     \/ CapOK(Configs[pc], Configs[pc + 1])
    /\ ~CHECK_SPACING \/ sinceInject >= TRebase
    /\ cfg' = [cfg EXCEPT ![Injector] = pc + 1]
    /\ pc' = pc + 1
    /\ sinceInject' = IF CHECK_SPACING THEN 0 ELSE sinceInject
    /\ injectedInPart' = (injectedInPart \/ phase = "part")
    /\ UNCHANGED <<alive, inc, age, ten, selfTen, linc, loss, phase, sideA, cutAge,
                   deadAge, sinceHeal, anyCrash, moved, claims>>

Next == \/ Tick \/ Partition \/ Heal \/ Inject
        \/ \E i \in Node : Crash(i) \/ Restart(i)

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* Properties.                                                             *)
(***************************************************************************)
TypeOK ==
    /\ alive \in [Node -> BOOLEAN]
    /\ inc \in [Node -> 1..MaxInc]
    /\ cfg \in [Node -> 0..Len(Configs)]
    /\ age \in [Node -> [Node -> 0..Theta]]
    /\ ten \in [Node -> [Node -> 0..Q]]
    /\ selfTen \in [Node -> 0..Q]
    /\ linc \in [Node -> [Node -> 0..MaxInc]]
    /\ loss \in [Node -> [Node -> 0..(K - 1)]]
    /\ phase \in {"pre", "part", "healed"}
    /\ pc \in 1..Len(Configs)

\* At most one node acts as leader at any time (stronger than Theorem 1).
NoDualLeader == \A i, j \in Node : i # j => ~(Acting(i) /\ Acting(j))

\* Theorem 1: non-bottom outputs in different components coincide.
ConsistentOutputs ==
    \A i, j \in Node :
        (/\ phase = "part" /\ ~SameSide(i, j)
         /\ Output(i) # NoNode /\ Output(j) # NoNode) => Output(i) = Output(j)

\* Theorem 2 (i): a majority side keeps authority (no crashes, no changes).
MajSide(i) == 2 * W(Configs[1], {j \in Node : SameSide(i, j)}) > W(Configs[1], Configs[1].vot)
MajorityKeepsAuth ==
    (phase = "part" /\ ~anyCrash /\ pc = 1) =>
        \A i \in Node : (alive[i] /\ MajSide(i)) => Auth(i)

\* Theorem 2 (ii) as bounded response: RecBound ticks after heal, every live
\* node holds authority and all agree on the leader.
AliveSet == {i \in Node : alive[i]}
TopCfg   == Mx({cfg[i] : i \in AliveSet} \cup {0})
CorrectMajority == TopCfg > 0 /\ Maj(Configs[TopCfg], AliveSet)
AuthReturns ==
    (phase = "healed" /\ sinceHeal >= RecBound /\ CorrectMajority) =>
        /\ \A i \in AliveSet : Auth(i)
        /\ \A i, j \in AliveSet : Leader(i) = Leader(j)

\* Proposition 2: members claimed during the partition survive the heal,
\* unless the member itself is no longer alive.
MergeOnHeal ==
    (phase = "healed" /\ sinceHeal >= K) =>
        \A i \in Node, j \in AliveSet :
            \A x \in claims[i] : alive[x] => x \in Members(j)

(***************************************************************************)
(* Witnesses: each is EXPECTED to be violated, showing that the scenario   *)
(* it negates is reachable, so that a passing configuration is not vacuous.*)
(***************************************************************************)
NoFailover      == ~(phase = "part" /\ \E j \in Node : Acting(j) /\ j # 1)
NoRestartAcross == ~(\E i, j \in Node : i # j /\ alive[j] /\ moved[j] /\ j \in Vote(i))
NoStaleInject   == ~injectedInPart
NoDoubleInject  == ~(pc = 3)
NoTieAuthority  == ~(/\ phase = "part" /\ cfg[Injector] > 1 /\ Auth(Injector)
                     /\ \A j \in Node : ~SameSide(Injector, j) => age[Injector][j] >= ThetaR)
NoLateHeal      == ~(phase = "healed" /\ sinceHeal = 0 /\ \E i, j \in AliveSet : i # j /\ age[i][j] = Theta)
=============================================================================
