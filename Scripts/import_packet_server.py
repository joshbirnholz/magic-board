"""Import server packet data; --jump-in-only leaves all JumpStart lists untouched."""
from pathlib import Path
import argparse, json, shutil
from jumpin_packet_data import parse_packets
parser=argparse.ArgumentParser()
parser.add_argument('source',nargs='?',type=Path,default=Path('/Users/compc/Xcode/TabletopSimulatorMagicBoosterPackServer'))
parser.add_argument('--jump-in-only',action='store_true')
args=parser.parse_args();source=args.source
root=Path(__file__).resolve().parents[1]
if not args.jump_in_only:
    for directory in ['JumpStart 2022','JumpStart 2025','JumpStart Avatar','SuperJump']:
        target=root/'CardService'/'JumpStart'/directory;target.mkdir(exist_ok=True)
        for path in (source/'Resources'/directory).glob('*.txt'): shutil.copyfile(path,target/path.name)
        print(directory,len(list(target.glob('*.txt'))))

packets=parse_packets((source/'Resources'/'jump-in-packet-list.html').read_text())
target=root/'CardService'/'JumpIn'/'packets.json';target.write_text(json.dumps(packets,ensure_ascii=False,indent=2)+'\n')
print('Jump In:',len(packets),'packets;',len({p['setCode'] for p in packets}),'sets')
if not args.jump_in_only:
    # Correct copied list errors against Wizards' published packet lists. The
    # published Too Many list itself totals 19; include its seventh basic Mountain.
    fixes={
     'JumpStart 2022/Primates.txt': [('3 Forest (J22) 110','2 Forest (J22) 110')],
     'JumpStart 2025/Goblins 3.txt': [('1 Hearts on Fire (J25)\n',''),('1 Fling (J25)\n',''),('1 Shock (J25)\n1 Scavenged Blade','1 Scavenged Blade')],
     'JumpStart 2025/Modified.txt': [('1 Cultivate (J25)\n',''),('1 Declare Dominance (J25)\n','')],
     'JumpStart 2025/Too Many.txt': [('2 Mountain (J25) 90','3 Mountain (J25) 90')],
    }
    import re
    for name,replacements in fixes.items():
     path=root/'CardService'/'JumpStart'/name;text=path.read_text()
     for old,new in replacements:
      assert old in text,(name,old)
      text=text.replace(old,new)
     path.write_text(text)
    for directory in ['JumpStart 2022','JumpStart 2025','JumpStart Avatar','SuperJump']:
     for path in (root/'CardService'/'JumpStart'/directory).glob('*.txt'):
      assert sum(int(m[1]) for line in path.read_text().splitlines() if (m:=re.match(r'^(\d+) ',line)))==20,path

    # Keep the app's basic-land policy when refreshing server packet lists.
    foundations={'Plains':'272','Island':'274','Swamp':'276','Mountain':'278','Forest':'280'}
    for path in (root/'CardService'/'JumpStart'/'JumpStart 2025').glob('*.txt'):
        text=re.sub(r'^(\d+) (Plains|Island|Swamp|Mountain|Forest)(?: \([^)]*\)(?: \S+)?)?$',
                    lambda m: f'{m[1]} {m[2]} (FDN) {foundations[m[2]]}',path.read_text(),flags=re.M)
        path.write_text(text)
    for path in (root/'CardService'/'JumpStart'/'SuperJump').glob('*.txt'):
        path.write_text(path.read_text().replace('Island (NEO) 285','Island (THB) 251'))
