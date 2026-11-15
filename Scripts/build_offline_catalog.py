"""Build the bundled JumpStart/DanDan catalog. Scryfall requests are rate limited."""
import argparse
import json, pathlib, re, time, urllib.request, urllib.parse, concurrent.futures, ssl, tempfile, threading, urllib.error, unicodedata
parser = argparse.ArgumentParser()
parser.add_argument('--metadata-only', action='store_true', help='Update deck/card metadata and runtime artwork URLs without downloading artwork.')
args = parser.parse_args()
ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / 'CardService' / 'OfflineGames'
OUT.mkdir(exist_ok=True)
HEADERS = {'User-Agent':'MagicBoard-OfflineCatalog/1.0', 'Accept':'application/json'}
api_lock=threading.Lock()
last_api_request=0.0
def request(url, payload=None):
    global last_api_request
    for attempt in range(6):
        try:
            if 'api.scryfall.com' in url:
                with api_lock:
                    time.sleep(max(0, .30-(time.monotonic()-last_api_request)))
                    last_api_request=time.monotonic()
            req=urllib.request.Request(url, data=json.dumps(payload).encode() if payload else None, headers=HEADERS | ({'Content-Type':'application/json'} if payload else {}))
            with urllib.request.urlopen(req, timeout=60, context=ssl.create_default_context(cafile="/etc/ssl/cert.pem")) as r: return r.read()
        except urllib.error.HTTPError as error:
            if error.code==429 and attempt<5:
                delay=min(60,max(15,float(error.headers.get('Retry-After','30'))))
                print('Scryfall rate limit; backing off',delay,'seconds',flush=True)
                time.sleep(delay)
            elif 500<=error.code<600 and attempt<5: time.sleep(3+attempt)
            else: raise
        except Exception:
            if attempt==5: raise
            time.sleep(3+attempt)
games=[]; identifiers={}
for path in sorted((ROOT/'CardService'/'JumpStart').rglob('*.txt')) + [ROOT/'CardService'/'Dandan.txt']:
    entries=[]
    for line in path.read_text().splitlines():
        match=re.match(r'^(\d+)\s+(.+?)(?:\s+\(([^)]+)\)(?:\s+(\S+))?)?$',line.strip())
        if not match: continue
        count,name,setcode,number=match.groups()
        key='|'.join([name.lower(),(setcode or '').lower(),number or ''])
        identifier={'name':name}
        if setcode: identifier['set']=setcode.lower()
        if number: identifier={'set':setcode.lower(),'collector_number':number}
        identifiers[key]=identifier
        entries.append({'key':key,'count':int(count)})
    setcode={'Marvel Super Heroes':'MSH','JumpStart 2022':'J22','JumpStart 2025':'J25','JumpStart Avatar':'TLA','SuperJump':'SJM'}.get(path.parent.name,'JMP')
    prefix={'MSH':'Marvel · ','J22':'2022 · ','J25':'Foundations · ','TLA':'Avatar · ','SJM':'SuperJump · '}.get(setcode,'')
    games.append({'name':prefix+path.stem,'kind':'DanDân' if path.stem=='Dandan' else 'JumpStart','setCode':setcode,'entries':entries})
packets=json.loads((ROOT/'CardService'/'JumpIn'/'packets.json').read_text())
for packet in packets:
    names=packet['fixedCards']+[c['name'] for slot in packet['randomSlots'] for c in slot]
    entries=[]
    for name in sorted(set(names)):
        key=name.lower()+'|'+packet['setCode'].lower()+'|'
        identifiers[key]={'name':name,'set':packet['setCode'].lower()}
        entries.append({'key':key,'count':1})
    games.append({'name':packet['setCode']+' · '+packet['name'],'kind':'Jump In','setCode':packet['setCode'],'entries':entries})
fixing=['Plains','Island','Swamp','Mountain','Forest','Evolving Wilds','Idyllic Beachfront','Sunlit Marsh','Haunted Mire','Radiant Grove','Tangled Islet','Molten Tributary','Geothermal Bog','Wooded Ridgeline','Sacred Peaks','Contaminated Aquifer']
entries=[]
for name in fixing:
    key=name.lower()+'||';identifiers[key]={'name':name};entries.append({'key':key,'count':1})
games.append({'name':'Jump In mana fixing','kind':'Mana fixing','entries':entries})
cache=pathlib.Path(tempfile.gettempdir())/'magic-offline-source-cards.json'
if (OUT/'source-cards.json').exists(): (OUT/'source-cards.json').replace(cache)
cards=json.loads(cache.read_text()) if cache.exists() else json.loads((OUT/'catalog.json').read_text()).get('cards',{}) if (OUT/'catalog.json').exists() else {}
# Resolve Marvel names against the cached complete set records, preferring
# regular Marvel printings. This avoids one API request per supplement card.
marvel_cache=pathlib.Path(tempfile.gettempdir())/'magic-marvel-printings.json'
if marvel_cache.exists():
    def norm(value): return re.sub(r'[^a-z0-9]','',unicodedata.normalize('NFKD',value).lower())
    pool=json.loads(marvel_cache.read_text())
    pool.sort(key=lambda c:(c['set']!='msh',c.get('promo',False),c.get('full_art',False),int(re.sub(r'[^0-9]','',c['collector_number']) or '9999')))
    aliases={}
    for c in pool:
        for face in [c]+c.get('card_faces',[]):
            for field in ['name','flavor_name','printed_name']:
                if face.get(field): aliases.setdefault(norm(face[field]),c)
    for key,identifier in identifiers.items():
        if identifier.get('set')=='msh' and identifier.get('name'):
            match=aliases.get(norm(identifier['name']))
            if match: cards[key]=match
    cache.write_text(json.dumps(cards))
keys=[k for k in identifiers if k not in cards]
# Fetch individual identifiers in batches. The API preserves found-card order.
for i in range(0,len(keys),75):
    batch=keys[i:i+75]
    result=json.loads(request('https://api.scryfall.com/cards/collection',{'identifiers':[identifiers[k] for k in batch]}))
    found=result.get('data',[])
    for key in batch:
        ident=identifiers[key]
        hit=next((c for c in found if (c['set']==ident.get('set',c['set']) and (c['collector_number']==ident['collector_number'] if 'collector_number' in ident else c['name'].lower()==ident['name'].lower()))),None)
        if not hit:
            time.sleep(.12)
            lookup={'exact':key.split('|')[0]}
            if ident.get('set')=='msh': lookup['set']='msc'
            query=urllib.parse.urlencode(lookup)
            try: hit=json.loads(request('https://api.scryfall.com/cards/named?'+query))
            except Exception:
                hit=json.loads(request('https://api.scryfall.com/cards/named?'+urllib.parse.urlencode({'exact':key.split('|')[0]})))
        cards[key]=hit
    cache.write_text(json.dumps(cards))
    print('Metadata', min(i+75,len(keys)), '/',len(keys),flush=True)
    time.sleep(.15)
# Include the actual tokens referenced by bundled cards' rules text.
while True:
    known={c['id'] for c in cards.values()}
    related=sorted({part['id'] for c in cards.values() for part in c.get('all_parts',[]) if part.get('component')=='token'} - known)
    if not related: break
    for i in range(0,len(related),75):
        result=json.loads(request('https://api.scryfall.com/cards/collection',{'identifiers':[{'id':v} for v in related[i:i+75]]}))
        found=result.get('data',[])
        if not found: raise RuntimeError('Referenced tokens could not be loaded')
        for token in found: cards['related|'+token['id']]=token
        cache.write_text(json.dumps(cards))
        time.sleep(.15)
tokens=[{'key':k,'count':1} for k in cards if k.startswith('related|')]
if tokens: games.append({'name':'Tokens used by preloaded games','kind':'Tokens','entries':tokens})
# Keep a URL -> filename map so all existing image loaders can use the bundle.
images={}; downloads={}
for c in cards.values():
    for face in [c]+c.get('card_faces',[]):
        uris=face.get('image_uris',{})
        for kind in ['normal','art_crop']:
            if kind in uris:
                url=uris[kind]; filename=f"{c['id']}-{kind}-{c.get('card_faces',[]).index(face) if face in c.get('card_faces',[]) else 'front'}.jpg"
                images[url]=filename; downloads[filename]=url
        # Small/large/PNG callers can use the bundled normal image offline.
        if 'normal' in uris:
            for kind in ['small','large','png','border_crop']:
                if kind in uris: images[uris[kind]]=images[uris['normal']]
# Artwork is NOT bundled; the app downloads it at runtime from the catalog's URL map.
# This local copy only lets the script validate URLs; it lives outside the bundled folder.
ART=ROOT/'CardService'/'OfflineArtworkSource'
if not args.metadata_only: ART.mkdir(exist_ok=True)
def download(item):
    filename,url=item; target=ART/filename
    valid=False
    if target.exists() and target.stat().st_size >= 2:
        with target.open('rb') as existing:
            existing.seek(-2,2); valid=existing.read()==b'\xff\xd9'
    if not valid:
        temporary=target.with_suffix('.part')
        temporary.write_bytes(request(url))
        temporary.replace(target)
if not args.metadata_only:
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for n,_ in enumerate(pool.map(download, downloads.items()),1):
            if n%100==0: print('Artwork',n,'/',len(downloads),flush=True)
manifest=OUT/'.catalog.json.tmp'
manifest.write_text(json.dumps({'games':games,'cards':cards,'images':images,'jumpInPackets':packets},ensure_ascii=False,separators=(',',':')))
manifest.replace(OUT/'catalog.json')
print('Complete:',len(games),'games,',len({c['id'] for c in cards.values()}),'cards,',len(downloads),'images',flush=True)
# Packet theme cards for the packet chooser (keeps them across catalog rebuilds).
import subprocess, sys
subprocess.run([sys.executable, str(ROOT/'Scripts'/'add_front_cards.py')], check=True)
