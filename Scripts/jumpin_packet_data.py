"""Parse and merge MTGABuddy Jump In pages using only Python's standard library.

Accepts both the legacy two-cell slot tables and current symbol-cell tables.
Archived packets are retained; an existing (set, name) is never overwritten.
"""
from html.parser import HTMLParser
from pathlib import Path
import argparse, json, re, ssl, urllib.request
URL = 'https://mtgabuddy.com/en/jump-in-packet-list'

class Node:
    def __init__(self, tag='', attrs=(), start=0):
        self.tag=tag; self.attrs=dict(attrs); self.children=[]; self.content=[]; self.start=start; self.end=start
    def find(self, tag=None, cls=None):
        result=[]
        for child in self.children:
            if (tag is None or child.tag==tag) and (cls is None or cls in child.attrs.get('class','').split()): result.append(child)
            result.extend(child.find(tag,cls))
        return result
    def text(self):
        return ' '.join(' '.join(c.text() if isinstance(c,Node) else c for c in self.content).split())

class Page(HTMLParser):
    VOID={'area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr'}
    def __init__(self, source):
        super().__init__(); self.source=source; self.root=Node(); self.stack=[self.root]
        self.offsets=[0]
        for line in source.splitlines(keepends=True): self.offsets.append(self.offsets[-1]+len(line))
        self.feed(source); self.close()
    def position(self):
        line,column=self.getpos(); return self.offsets[line-1]+column
    def handle_starttag(self,tag,attrs):
        node=Node(tag,attrs,self.position()); self.stack[-1].children.append(node); self.stack[-1].content.append(node)
        if tag not in self.VOID: self.stack.append(node)
    def handle_endtag(self,tag):
        for i in range(len(self.stack)-1,0,-1):
            if self.stack[i].tag==tag:
                self.stack[i].end=self.source.find('>',self.position())+1;self.stack=self.stack[:i];break
    def handle_data(self,data): self.stack[-1].content.append(data)
    @property
    def blocks(self): return self.root.find('div','pack')

def probability(text):
    match=re.fullmatch(r'\s*(\d+(?:\.\d+)?)\s*%\s*',text)
    return float(match[1]) if match else None

def parse_packet(block):
    headings=block.find('h2')
    if not headings: raise ValueError('Packet is missing its name')
    name=headings[0].text(); set_code=block.attrs.get('data-set-code','').strip().upper()
    colors=[c.strip() for c in block.attrs.get('data-colors','').split(',') if c.strip()]
    if not set_code or not colors: raise ValueError(f'Missing set/colors: {name}')
    slots=[]
    for table in block.find('table','table'):
        for row in table.find('tr'):
            slot=[]; pending=None
            for cell in row.find('td'):
                percent=probability(cell.text())
                if percent is not None: pending=percent;continue
                links=[a for a in cell.find('a') if a.text()]
                if links and pending is not None:
                    slot.append({'name':links[0].text(),'probability':pending});pending=None
            if slot:
                if abs(sum(c['probability'] for c in slot)-100)>0.05: raise ValueError(f'Invalid slot probabilities: {set_code} {name} {slot}')
                slots.append(slot)
    fixed=[]
    for section in block.find('div','card-block'):
        for item in section.find('li'):
            rates=item.find(cls='card-drop-rate'); rate=probability(rates[0].text()) if rates else None
            if rates and '%' in rates[0].text() and rate != 100: continue
            links=[a for a in item.find('a') if a.text()]
            if links: fixed.append(links[0].text())
    count=len(fixed)+len(slots)
    if not 12<=count<=20: raise ValueError(f'Unexpected card count: {set_code} {name}: {count}')
    return {'name':name,'setCode':set_code,'colors':colors,'randomSlots':slots,'fixedCards':fixed}

def parse_packets(source):
    packets=[parse_packet(b) for b in Page(source).blocks]
    keys=[(p['setCode'],p['name']) for p in packets]
    if not packets or len(set(keys))!=len(keys): raise ValueError('Empty page or duplicate packet keys')
    return packets

def merge_pages(archive,current):
    archived=parse_packets(archive); seen={(p['setCode'],p['name']) for p in archived}; added=[]; raw=[]
    for block in Page(current).blocks:
        packet=parse_packet(block); key=(packet['setCode'],packet['name'])
        if key in seen: continue
        seen.add(key);added.append(packet);raw.append('\n'.join(line.rstrip() for line in current[block.start:block.end].split('\n')))
    marker=archive.lower().rfind('</body>')
    if marker<0: raise ValueError('Archive is missing its closing body tag')
    merged=archive if not raw else archive[:marker]+'\n<!-- Additional Jump In packets from '+URL+' -->\n'+'\n'.join(raw)+'\n'+archive[marker:]
    result=parse_packets(merged)
    if len(result)!=len(archived)+len(added): raise ValueError('Merged page did not preserve packet counts')
    return merged,result,added

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive',type=Path,required=True)
    parser.add_argument('--page',type=Path,help='Use an already-downloaded page')
    parser.add_argument('--output',type=Path,help='Write merged HTML here (defaults to archive)')
    parser.add_argument('--json',type=Path,help='Also export full packet definitions')
    args=parser.parse_args()
    page=args.page.read_text() if args.page else urllib.request.urlopen(URL,context=ssl.create_default_context(cafile='/etc/ssl/cert.pem'),timeout=60).read().decode()
    merged,packets,added=merge_pages(args.archive.read_text(),page)
    output=args.output or args.archive;temporary=output.with_suffix(output.suffix+'.tmp');temporary.write_text(merged);temporary.replace(output)
    if args.json: args.json.write_text(json.dumps(packets,ensure_ascii=False,indent=2)+'\n')
    from collections import Counter
    print('Added:',len(added),dict(Counter(p['setCode'] for p in added)))
    print('Total:',len(packets),'packets;',len({p['setCode'] for p in packets}),'sets')

if __name__=='__main__': main()
