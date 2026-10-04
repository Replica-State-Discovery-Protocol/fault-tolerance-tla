import os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'models')
BASE = dict(N=3, SCENARIO='"s3cut"', Theta=5, ThetaR=2, Q=4, K=2, Delta=1, TRebase=6,
            MaxInc=2, RecBound=6, GATE='TRUE', AGG='"sigma"', TENURE='"fresh"',
            CHECK_ADJ='TRUE', CHECK_CAP='TRUE', CHECK_SPACING='TRUE',
            ALLOW_HEAL='FALSE', TRACK_CLAIMS='FALSE')
ORDER = list(BASE)
S = ['TypeOK', 'NoDualLeader']
C = [
 # name, overrides, invariants, comment
 ('sb_full_n3', dict(SCENARIO='"s3any"', ALLOW_HEAL='TRUE'),
  S+['ConsistentOutputs','MajorityKeepsAuth','AuthReturns'],
  'Full mechanism, n = 3: any 1|2 partition, crash and restart on either side,\n'
  'heal. Expect all invariants to HOLD.'),
 ('sb_merge_n3', dict(SCENARIO='"s3cut"', ALLOW_HEAL='TRUE', TRACK_CLAIMS='TRUE'),
  S+['MergeOnHeal','AuthReturns'],
  'Proposition 2: members claimed during a quiescent partition {1} | {2,3}\n'
  'survive the heal. Expect all invariants to HOLD.'),
 ('sb_gate_off', dict(GATE='FALSE'), S,
  'Unamended RSDP: no authority gate. Partition {1} | {2,3}.\n'
  'Expect NoDualLeader VIOLATED: node 1 keeps leading its side while\n'
  '{2,3} evict it and elect node 2.'),
 ('sb_agg_fresh', dict(AGG='"fresh"'), S,
  'Leader aggregated over Fresh instead of Sigma (Sect. 3.2). Partition {1} | {2,3}.\n'
  'Expect NoDualLeader VIOLATED: {2,3} stop counting node 1 at ThetaR and\n'
  'elect node 2 before node 1 steps down.'),
 ('sb_order_off', dict(ThetaR=5), S,
  'Single threshold, ThetaR = Theta, violating the condition of Lemma 2.\n'
  'Expect NoDualLeader VIOLATED: {2,3} evict node 1 while it still holds authority.'),
 ('sb_quar_off', dict(SCENARIO='"s3quar"', Q=0, RecBound=2), S,
  'Quarantine off (Q = 0). Partition {1} | {2,3}; node 3 crashes and restarts\n'
  'on side {1}. Expect NoDualLeader VIOLATED: node 3 is counted on both sides.'),
 ('sb_quar_on', dict(SCENARIO='"s3quar"'), S+['ConsistentOutputs'],
  'Same scenario as sb_quar_off with Q = 4 (Lemma 3). Expect all to HOLD.'),
 ('sb_tenure_evict', dict(ALLOW_HEAL='TRUE', TENURE='"evict"'), S,
  'Tenure reset only on eviction or restart (the rule stated in the draft).\n'
  'Partition {1} | {2,3}, then heal. Probes the handover after heal.'),
 ('sb_tenure_fresh', dict(ALLOW_HEAL='TRUE'), S+['ConsistentOutputs','AuthReturns'],
  'Same as sb_tenure_evict with tenure reset whenever a peer stops being fresh.'),
 ('sb_adj_off', dict(N=4, SCENARIO='"s4adj"', CHECK_ADJ='FALSE', CHECK_CAP='FALSE'), S,
  'Electorate {1,2,3}, node 4 non-voter, partition {1,4} | {2,3}. Node 1 may\n'
  'install {1,2,4} (two voters changed at once). Expect NoDualLeader VIOLATED.'),
 ('sb_adj_on', dict(N=4, SCENARIO='"s4adj"'), S+['ConsistentOutputs'],
  'Same as sb_adj_off with the adjacency check. Expect all to HOLD.'),
 ('sb_spacing_off', dict(N=4, SCENARIO='"s4spacing"', CHECK_SPACING='FALSE'), S,
  'Electorate {1,2,3}, partition {1,4} | {2,3}. Node 1 adds 4, then removes 3,\n'
  'with no spacing between the changes. Expect NoDualLeader VIOLATED.'),
 ('sb_spacing_on', dict(N=4, SCENARIO='"s4spacing"'), S+['ConsistentOutputs'],
  'Same as sb_spacing_off with the A3 spacing. Expect all to HOLD.'),
 ('sb_cap_off', dict(N=4, SCENARIO='"s4cap"', CHECK_CAP='FALSE'), S,
  'Weights 1,1,3, partition {1,2,4} | {3}. Node 1 adds node 4 with weight 2,\n'
  'above the cap 2 mu = 1. Expect NoDualLeader VIOLATED.'),
 ('sb_cap_on', dict(N=4, SCENARIO='"s4cap"'), S+['ConsistentOutputs'],
  'Same as sb_cap_off with the weight cap. Expect all to HOLD.'),
 ('sb_tie', dict(N=4, SCENARIO='"s4tie"'), S+['ConsistentOutputs'],
  'Electorate {1,2,3,4}, 2|2 partition {1,2} | {3,4}: no majority. A stale\n'
  'removal of 3 at node 1 makes {1,2} a majority of {1,2,4}. Expect all to HOLD.'),
 ('sb_rec_tight', dict(SCENARIO='"s3any"', ALLOW_HEAL='TRUE', RecBound=5), S+['AuthReturns'],
  'Tightness of the Theorem 2 bound: RecBound = K + Q - 1.\n'
  'Expect AuthReturns VIOLATED.'),
 # witnesses
 ('w_failover', dict(SCENARIO='"s3any"', ALLOW_HEAL='TRUE'), ['NoFailover'],
  'Witness for sb_full_n3: a successor leads during the partition. Expect VIOLATED.'),
 ('w_restart', dict(SCENARIO='"s3quar"'), ['NoRestartAcross'],
  'Witness for sb_quar_on: a restarted node is counted on its new side. Expect VIOLATED.'),
 ('w_lateheal', dict(SCENARIO='"s3any"', ALLOW_HEAL='TRUE'), ['NoLateHeal'],
  'Witness for sb_full_n3: heal after eviction. Expect VIOLATED.'),
 ('w_double', dict(N=4, SCENARIO='"s4spacing"'), ['NoDoubleInject'],
  'Witness for sb_spacing_on: both changes accepted. Expect VIOLATED.'),
 ('w_tie', dict(N=4, SCENARIO='"s4tie"'), ['NoTieAuthority'],
  'Witness for sb_tie: side {1,2} gains authority after the stale change. Expect VIOLATED.'),
]
for name, ov, inv, com in C:
    d = dict(BASE)
    if ov.get('N') == 4:
        d.update(K=1, RecBound=5)   # n = 4: loss-free (K = 1) to bound branching
    d.update(ov)
    lines = ['\\* ' + l for l in com.split('\n')]
    lines += ['SPECIFICATION Spec', 'CONSTANTS'] + [f'    {k} = {d[k]}' for k in ORDER]
    lines += ['INVARIANTS'] + [f'    {i}' for i in inv]
    open(os.path.join(OUT, f'{name}.cfg'), 'w').write('\n'.join(lines) + '\n')
print(len(C), 'configs')
