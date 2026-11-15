import unittest
from jumpin_packet_data import merge_pages, parse_packets

def packet(name='LEGACY',set_code='OLD',modern=False):
    fixed=''.join('<li><a>Fixed '+str(i)+'</a>'+('<span class="card-drop-rate">100 %</span>' if modern else '')+'</li>' for i in range(11))
    fixed+='<li><a>Rare A</a><span class="card-drop-rate">25 %</span></li>'
    symbol='<td><span></span></td>' if modern else ''
    return f'<div class="pack" data-set-code="{set_code}" data-colors="W, U"><h2>{name}</h2><div class="card-block"><ul>{fixed}</ul></div><table class="table"><tr><td>25 %</td>{symbol}<td><a>Rare A</a></td><td>- or -</td><td>75 %</td>{symbol}<td><a>Rare B</a></td></tr></table></div>'

def page(*packets):return '<html><body>'+''.join(packets)+'</body></html>'

class JumpInPageTests(unittest.TestCase):
    def test_legacy_and_current_markup_have_identical_slots(self):
        legacy=parse_packets(page(packet()))[0]
        modern=parse_packets(page(packet(modern=True)))[0]
        self.assertEqual(legacy,modern)
        self.assertEqual(len(modern['fixedCards']),11)
        self.assertEqual(modern['colors'],['W','U'])
        self.assertEqual(modern['randomSlots'],[[{'name':'Rare A','probability':25.0},{'name':'Rare B','probability':75.0}]])

    def test_merge_keeps_archived_packets_and_is_idempotent(self):
        archive=page(packet(),packet('RETIRED','OLD'))
        current=page(packet(modern=True),packet('NEW','SOS',True))
        merged,packets,added=merge_pages(archive,current)
        self.assertEqual(len(packets),3)
        self.assertEqual([p['name'] for p in added],['NEW'])
        self.assertIn(archive.split('</body>')[0],merged)
        self.assertEqual(merge_pages(merged,current),(merged,packets,[]))

    def test_invalid_probabilities_fail_before_writing(self):
        with self.assertRaises(ValueError):parse_packets(page(packet().replace('75 %','65 %')))

if __name__=='__main__':unittest.main()
