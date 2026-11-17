"""Add each Jump In set's basic-land arts and runtime image URLs; no artwork download."""
import json
import pathlib
import re
import ssl
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'CardService' / 'OfflineGames' / 'catalog.json'
NAMES = ('Plains', 'Island', 'Swamp', 'Mountain', 'Forest')


def preferred_arts(cards, name):
    candidates = [c for c in cards if c['name'] == name]
    regular = [c for c in candidates if not c.get('full_art', False)]
    chosen = {}
    for card in sorted(regular or candidates, key=lambda c: (int(re.sub(r'\D', '', c['collector_number']) or 0), c['collector_number'])):
        chosen.setdefault(card.get('illustration_id') or card['id'], card)
    return list(chosen.values())


def main():
    catalog = json.loads(CATALOG.read_text())
    cache_dir = pathlib.Path('/tmp/magic-jumpin-basic-sets')
    cache_dir.mkdir(exist_ok=True)
    result = {}
    for code in sorted({p['setCode'] for p in catalog['jumpInPackets']}):
        cached = cache_dir / (code + '.json')
        if cached.exists():
            cards = json.loads(cached.read_text())
        else:
            query = 'set:' + code.lower() + ' t:basic lang:en game:paper'
            url = 'https://api.scryfall.com/cards/search?' + urllib.parse.urlencode({'q': query, 'unique': 'prints'})
            cards = []
            while url:
                request = urllib.request.Request(url, headers={'User-Agent': 'MagicBoard-OfflineCatalog/1.0', 'Accept': 'application/json'})
                with urllib.request.urlopen(request, timeout=45, context=ssl.create_default_context(cafile='/etc/ssl/cert.pem')) as response:
                    page = json.load(response)
                cards.extend(page['data'])
                url = page.get('next_page')
                time.sleep(0.3)
            cached.write_text(json.dumps(cards))
        basics = {}
        for name in NAMES:
            arts = preferred_arts(cards, name)
            if not arts:
                raise ValueError(f'{code}: no {name} printings')
            keys = []
            for card in arts:
                key = f"jumpin-basic|{code.lower()}|{card['id']}"
                keys.append(key)
                catalog['cards'][key] = card
                uris = card.get('image_uris', {})
                for kind in ('normal', 'art_crop'):
                    if kind in uris:
                        catalog['images'][uris[kind]] = f"{card['id']}-{kind}-front.jpg"
                if 'normal' in uris:
                    for kind in ('small', 'large', 'png', 'border_crop'):
                        if kind in uris:
                            catalog['images'][uris[kind]] = catalog['images'][uris['normal']]
            basics[name] = keys
        result[code] = basics
        print(code, {name: len(keys) for name, keys in basics.items()}, flush=True)
    catalog['jumpInBasics'] = result
    temporary = CATALOG.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(catalog, ensure_ascii=False, separators=(',', ':')))
    temporary.replace(CATALOG)


if __name__ == '__main__':
    main()
