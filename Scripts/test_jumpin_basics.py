import unittest
from add_jumpin_basics import preferred_arts


class BasicArtPolicyTests(unittest.TestCase):
    def test_prefers_all_regular_arts_and_deduplicates_the_illustration(self):
        cards = [dict(name='Island', id='a', illustration_id='one', collector_number='1', full_art=False),
                 dict(name='Island', id='foil', illustration_id='one', collector_number='9', full_art=False),
                 dict(name='Island', id='b', illustration_id='two', collector_number='2', full_art=False),
                 dict(name='Island', id='c', illustration_id='three', collector_number='3', full_art=True)]
        self.assertEqual([c['id'] for c in preferred_arts(cards, 'Island')], ['a', 'b'])

    def test_uses_all_full_art_illustrations_when_regular_printings_are_absent(self):
        cards = [dict(name='Forest', id=str(i), illustration_id=str(i), collector_number=str(i), full_art=True) for i in range(3)]
        self.assertEqual(len(preferred_arts(cards, 'Forest')), 3)
        self.assertEqual(preferred_arts(cards, 'Island'), [])


if __name__ == '__main__':
    unittest.main()
