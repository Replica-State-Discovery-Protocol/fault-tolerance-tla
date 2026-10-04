------------------------------ MODULE LemmaOne ------------------------------
(***************************************************************************)
(* Exhaustive check of Lemma 1 (adjacent majorities intersect).            *)
(*                                                                         *)
(* Two configurations that differ by one voter e are compared: S, the      *)
(* electorate without e, and T = S \cup {e}. Adding e and removing e give  *)
(* the same pair (S, T), so one check covers both directions. Voters are   *)
(* interchangeable, so S = 1..m and e = m + 1 without loss of generality.  *)
(*                                                                         *)
(* A violation is a majority X of S and a majority Y of T with X, Y        *)
(* disjoint. With CAP = TRUE only pairs satisfying the weight cap          *)
(* w(e) <= 2 mu(S) are enumerated and none must exist; with CAP = FALSE    *)
(* all pairs are enumerated and a violation is expected.                   *)
(*                                                                         *)
(* Weights are doubled throughout to keep the margin integral:             *)
(* Mu2 = 2 mu = min { 2 W(X) - W(S) : X a majority of S }.                 *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets, TLC

CONSTANTS
    MaxSize,    \* largest smaller electorate |S|; |T| = |S| + 1
    MaxW,       \* weights range over 1..MaxW
    CAP         \* TRUE: enumerate only pairs satisfying the weight cap

VARIABLE ce     \* None, or the smallest violation found

RECURSIVE SumW(_, _)
SumW(w, X) == IF X = {} THEN 0
              ELSE LET x == CHOOSE y \in X : TRUE IN w[x] + SumW(w, X \ {x})

Maj(w, L, X) == 2 * SumW(w, X) > SumW(w, L)

Majorities(w, L) == {X \in SUBSET L : Maj(w, L, X)}

Mu2(w, L) ==
    LET M == {2 * SumW(w, X) - SumW(w, L) : X \in Majorities(w, L)}
    IN  CHOOSE k \in M : \A j \in M : k <= j

\* One case: |S| = m, weights for 1..m+1 (voter m+1 is e).
Cases == UNION { {[m |-> m, w |-> w] : w \in [1..(m + 1) -> 1..MaxW]}
                 : m \in 1..MaxSize }

CapHolds(c) == c.w[c.m + 1] <= Mu2(c.w, 1..c.m)

Checked == {c \in Cases : ~CAP \/ CapHolds(c)}

Violations(c) ==
    LET pairs == Majorities(c.w, 1..c.m) \X Majorities(c.w, 1..(c.m + 1))
    IN  {[m |-> c.m, w |-> c.w, X |-> p[1], Y |-> p[2]] :
            p \in {q \in pairs : q[1] \cap q[2] = {}}}

AllViolations == UNION {Violations(c) : c \in Checked}

ASSUME PrintT(<<"cases enumerated", Cardinality(Checked)>>)

None == [m |-> 0, w |-> <<>>, X |-> {}, Y |-> {}]

Init == ce = IF AllViolations = {} THEN None
             ELSE CHOOSE v \in AllViolations :
                    \A u \in AllViolations : v.m <= u.m

Spec == Init /\ [][UNCHANGED ce]_ce

NoViolation == ce = None
=============================================================================
