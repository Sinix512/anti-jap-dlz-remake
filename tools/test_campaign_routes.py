"""Synthetic contract fixtures ONLY. Never submitted to the acceptance gate."""
import copy
import unittest
from campaign_routes import joint_routes, validate_chain


def fixture(mode="simulation", *, interludes=True, frozen=3600):
    start = 36 if mode == "simulation" else 40
    r = dict(index=0, town=0, completed=[], hidden_done=[], score=0, scores={},
             frozen=0, unlocked=False, flags={str(i): 0 for i in [0,3,4,9,85,91]}, money=500, item56=0)
    def full():
        return dict(campaign_index=r['index'], campaign_completed=r['completed'][:], hidden_done=r['hidden_done'][:],
                    score_total=r['score'], main_score_snapshot=r['frozen'], difficulty=1)
    d = dict(schema='dlz-natural-routes-v1', route=mode, run_id='run', chain_id=mode, fresh=True,
             creation=dict(face=103, unit=4, wuli=100, difficulty=1), initial_state=full(), errors=[], rows=[],
             route_trace=[], native_inputs=[], navigation_inputs=[], report_inputs=[],
             interlude_policy=dict(rng_seed_override=False, max_visits=64, actual_visits=0),
             ending_flow=['END','chapter35','hidden_notice','finale'], stop=dict(ok=True, boundary='process_close'))
    def trace(kind, before, extra=None):
        seq = len(d['route_trace'])
        d['route_trace'].append(dict(seq=seq, kind=kind, before=before, after=copy.deepcopy(r), extra=extra or {}, frame=seq))
        return seq
    def play(idx, score=100):
        before = full()
        launch = trace('launch', copy.deepcopy(r), dict(idx=idx, standalone=False))
        cb = copy.deepcopy(r)
        cb['score'] += score  # real report records score before the final commit
        r['score'] += score
        r['scores'][str(idx)] = score
        r['completed'].append(idx)
        if idx < 44:
            r['index'] = idx+1
        else:
            r['index'] = r['flags']['91']
        if idx >= 36:
            r['hidden_done'].append(idx)
        if idx == 35:
            r['frozen'] = r['score']
            r['unlocked'] = r['frozen'] >= 2800
        if idx == 45:
            r['item56'] += 1
        commit = trace('commit', cb, dict(idx=idx, report=dict(result_committed=True)))
        d['rows'].append(dict(idx=idx, result=dict(result='victory'),
            provenance=dict(fresh=True, difficulty=1, campaign_path=True, evidence_run_id='run', chain_id=mode, route=mode),
            state_before=before, state_after=full(), route_launch_seq=launch, route_commit_seq=commit,
            retry_attempts=[], legality=dict(errors=[]),
            campaign_flow=dict(report=dict(idx=idx, victory=True, score=score), story_errors=[], result_acknowledged=True)))
        d['report_inputs'].append(dict(kind='res://scripts/ui/OriginalVictoryReport.gd',stage='wait'))
    for idx in range(36):
        r['index'] = idx
        if idx == 30 and interludes:
            for inter,flag in [(44,3),(45,4),(46,9)]:
                b = copy.deepcopy(r)
                r['index'] = inter
                r['flags'][str(flag)] = 1
                r['flags']['91'] = idx
                resident_seq = trace('resident', b, dict(town=0))
                d['navigation_inputs'].append(dict(kind='interlude_resident', before=b, after=copy.deepcopy(r)))
                d['interlude_policy']['actual_visits'] += 1
                play(inter,0)
        play(idx, frozen-3500 if idx == 35 else 100)
    if frozen >= 2800:
        b = copy.deepcopy(r)
        r['index'] = start
        if mode == 'fiction':
            r['flags']['85'] = 2
        trace('hidden', b, dict(mode=mode))
        d['native_inputs'].append(dict(kind='hidden_choice_input',mode=mode,before=dict(frozen_score=frozen,hidden_unlocked=True)))
        for i,threshold in enumerate([2800,3000,3300,3600]):
            if frozen >= threshold:
                play(start+i,20)
    else:
        d['ending_flow'] = ['END','chapter35','finale']
    trace('close', copy.deepcopy(r),dict(ending_flow=d['ending_flow'][:]))
    d['native_inputs'].append(dict(kind='process_close_requested'))
    d['final_state'] = full()
    return d


class RouteEvidenceTest(unittest.TestCase):
    def result(self,d):
        return validate_chain(d,'run',d.get('route'),d.get('route'))
    def test_complete_independent_joint(self):
        r = joint_routes([fixture(), fixture('fiction')],'run',dict(simulation='simulation',fiction='fiction'))
        self.assertTrue(r['complete'],r)
        self.assertEqual(r['won'],list(range(47)))
    def test_partial_live_shape(self):
        d = fixture()
        d['rows'] = d['rows'][:1]
        d['route_trace'] = d['route_trace'][:2]
        d['navigation_inputs'] = []
        d['report_inputs'] = d['report_inputs'][:1]
        d['native_inputs'] = []
        d['interlude_policy']['actual_visits'] = 0
        d['final_state'] = d['rows'][-1]['state_after']
        d['stop']['boundary'] = 'battle_limit'
        r = self.result(d)
        self.assertTrue(r['valid'],r)
        self.assertFalse(r['natural_terminal'])
    def test_lower_natural_thresholds_not_full47(self):
        for score,count in [(2799,0),(2800,1),(3000,2),(3300,3),(3600,4)]:
            d = fixture(frozen=score)
            r = self.result(d)
            self.assertTrue(r['valid'],r)
            self.assertEqual(len(r['hidden_won']),count)
            self.assertEqual(r['full_branch'],count==4)
    def test_union_without_interludes_is_incomplete(self):
        r = joint_routes([fixture(interludes=False),fixture('fiction',interludes=False)],'run',dict(simulation='simulation',fiction='fiction'))
        self.assertTrue(r['valid'],r)
        self.assertFalse(r['complete'])
    def test_reject_mutations(self):
        def row(d,idx):return next(r for r in d['rows'] if r['idx']==idx)
        def event(d,kind,idx=None):
            return next(e for e in d['route_trace'] if e['kind']==kind and (idx is None or e['extra'].get('idx')==idx))
        mutations = {
            'schema': lambda d:d.update(schema='old'),
            'saved_root': lambda d:d['initial_state'].update(campaign_index=8),
            'old_history': lambda d:d['initial_state'].update(campaign_completed=[0]),
            'foreign_run': lambda d:d.update(run_id='old'),
            'foreign_row': lambda d:row(d,8)['provenance'].update(chain_id='other'),
            'not_fresh': lambda d:row(d,8)['provenance'].update(fresh=False),
            'difficulty': lambda d:d['creation'].update(difficulty=0),
            'missing_main': lambda d:d['rows'].pop(8),
            'no_ack': lambda d:row(d,8)['campaign_flow'].update(result_acknowledged=False),
            'no_native_ack': lambda d:d['report_inputs'].pop(),
            'wrong_launch': lambda d:event(d,'launch',8)['extra'].update(idx=9),
            'standalone': lambda d:event(d,'launch',8)['extra'].update(standalone=True),
            'source_history': lambda d:row(d,8)['state_before'].update(campaign_completed=[7]),
            'wrong_score': lambda d:row(d,8)['state_after'].update(score_total=123456),
            'wrong_freeze': lambda d:row(d,35)['state_after'].update(main_score_snapshot=99999),
            'late_freeze': lambda d:event(d,'launch',37)['before'].update(frozen=99999),
            'wrong_branch': lambda d:row(d,36).update(idx=40),
            'no_choice': lambda d:d['native_inputs'].pop(0),
            'wrong_choice': lambda d:d['native_inputs'][0].update(mode='fiction'),
            'choice_unearned': lambda d:d['native_inputs'][0]['before'].update(frozen_score=0),
            'return_before_flag': lambda d:event(d,'launch',44)['before']['flags'].update({'3':0}),
            'false_return': lambda d:event(d,'commit',44)['after'].update(index=31),
            'wrong_one_shot': lambda d:next(e for e in d['route_trace'] if e['kind']=='resident')['before']['flags'].update({'3':1}),
            'no_native_resident': lambda d:d['navigation_inputs'].clear(),
            'reward_twice': lambda d:event(d,'commit',45)['after'].update(item56=2),
            'rng_override': lambda d:d['interlude_policy'].update(rng_seed_override=True),
            'no_close': lambda d:d['route_trace'].pop(),
            'no_jz': lambda d:d.update(ending_flow=['END','chapter35']),
            'premature_finale': lambda d:d['rows'].pop(),
            'script_errors': lambda d:d['errors'].append('stall'),
            'missing_trace': lambda d:d.pop('route_trace'),
            'empty': lambda d:d.clear(),
        }
        for name,mutate in mutations.items():
            with self.subTest(name=name):
                d=fixture();mutate(d)
                self.assertFalse(self.result(d)['valid'],name)
    def test_no_id_union_or_identity_reuse(self):
        a,b=fixture(),fixture('fiction')
        for chains,ids in [([a,a],dict(simulation='simulation',fiction='fiction')),
                           ([a,b],dict(simulation='same',fiction='same')),
                           ([a],dict(simulation='simulation',fiction='fiction'))]:
            self.assertFalse(joint_routes(chains,'run',ids)['complete'])
    def test_malformed_never_pass(self):
        for d in [None,[],{}, {'schema':'dlz-natural-routes-v1'}, fixture()|{'rows':None}]:
            self.assertFalse(validate_chain(d,'run','simulation','simulation')['valid'])

if __name__ == '__main__':
    result=unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(RouteEvidenceTest))
    if result.wasSuccessful():print('CAMPAIGN_ROUTES PASS (synthetic contract tests only)')
    raise SystemExit(not result.wasSuccessful())
