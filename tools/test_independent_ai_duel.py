#!/usr/bin/env python3
import unittest
from run_independent_ai_duel import evaluate_league

def rnd(a,b,winners,unfinished=False):
    score={n:winners.count(n) for n in ('alpha','beta')}
    winner=max(score,key=score.get) if score['alpha']!=score['beta'] and not unfinished else None
    return {'strategies':{'alpha':{'sha256':a},'beta':{'sha256':b}},
            'score':score,'winner':winner,'loser':('beta' if winner=='alpha' else 'alpha') if winner else None,
            'games':[{'winner':w,'status':'unfinished' if unfinished else 'completed'} for w in winners]}
class StopTests(unittest.TestCase):
    def test_minimum_four(self):
        self.assertFalse(evaluate_league([rnd('a','b',['alpha','beta'])])['stop'])
    def test_near_fifty(self):
        self.assertEqual(evaluate_league([rnd('a','b',['alpha','beta']),rnd('a','b',['beta','alpha'])])['reason'],'near_50_percent')
    def test_old_versions_do_not_pad_fifty(self):
        self.assertFalse(evaluate_league([rnd('a','b',['alpha','alpha']),rnd('a','c',['beta','beta'])])['stop'])
    def test_failed_four_revisions(self):
        rounds=[rnd('a',str(i),['alpha','alpha']) for i in range(5)]
        self.assertFalse(evaluate_league(rounds[:-1])['stop'])
        self.assertEqual(evaluate_league(rounds)['reason'],'four_unsuccessful_revisions')
    def test_same_source_is_not_revision(self):
        self.assertFalse(evaluate_league([rnd('a','b',['alpha','alpha'])]*5)['stop'])
    def test_winner_changes_reset_chain(self):
        rounds=[rnd('a',str(i),['alpha','alpha']) for i in range(4)]
        rounds.append(rnd('a','new',['beta','beta']))
        self.assertEqual(evaluate_league(rounds)['consecutive_unsuccessful_revisions'],0)
    def test_unfinished_is_not_win(self):
        rounds=[rnd('a','b',['alpha','beta'],unfinished=True)]*4
        self.assertEqual(evaluate_league(rounds)['decisive_games'],0)
        self.assertFalse(evaluate_league(rounds)['stop'])
    def test_unfinished_is_not_loss_but_bounds_can_preclude_round_win(self):
        rounds=[rnd('a0','b',['beta']*4)]
        for i in range(1,5):
            item=rnd('a'+str(i),'b',['beta','beta',None,None])
            item['winner']=None;item['loser']=None
            for game in item['games']:
                if game['winner'] is None:game['status']='unfinished'
            rounds.append(item)
        result=evaluate_league(rounds)
        self.assertEqual(result['reason'],'four_unsuccessful_revisions')
        self.assertEqual(rounds[-1]['score'],{'alpha':0,'beta':2})
        self.assertEqual(result['decisive_games'],0)
    def test_possible_challenger_win_does_not_count_failed(self):
        rounds=[rnd('a0','b',['beta']*4)]
        for i in range(1,5):
            item=rnd('a'+str(i),'b',['beta',None,None,None])
            item['winner']=None;item['loser']=None
            for game in item['games']:
                if game['winner'] is None:game['status']='unfinished'
            rounds.append(item)
        self.assertFalse(evaluate_league(rounds)['stop'])
    def test_pending_challenge_resets_consecutive_failure_chain(self):
        rounds=[rnd('a0','b',['beta']*4),rnd('a1','b',['beta']*4)]
        pending=rnd('a2','b',['alpha','alpha',None,None])
        pending['winner']=None;pending['loser']=None
        for game in pending['games']:
            if game['winner'] is None:game['status']='unfinished'
        rounds.append(pending)
        rounds.extend(rnd('a'+str(i),'b',['beta']*4) for i in range(3,6))
        self.assertEqual(evaluate_league(rounds)['consecutive_unsuccessful_revisions'],3)
        self.assertFalse(evaluate_league(rounds)['stop'])
    def test_successful_tie_ends_failure_chain(self):
        rounds=[rnd('a'+str(i),'b',['beta']*4) for i in range(4)]
        rounds.append(rnd('a4','b',['alpha','beta','alpha','beta']))
        result=evaluate_league(rounds)
        self.assertEqual(result['reason'],'near_50_percent')
        self.assertEqual(result['consecutive_unsuccessful_revisions'],0)
    def test_modified_winner_cannot_count(self):
        rounds=[rnd(str(i),str(i),['alpha','alpha']) for i in range(5)]
        self.assertFalse(evaluate_league(rounds)['stop'])
if __name__=='__main__': unittest.main()
