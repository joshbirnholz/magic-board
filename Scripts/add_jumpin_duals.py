"""Add each Jump In set's common two-color dual lands (and DMU's, the fallback cycle) to the
offline catalog, as the server's JumpInParser.addLands does; no artwork download.

catalog['jumpInDuals'] maps a set code to {color pair (sorted WUBRG letters, e.g. "UW"): card key}.
"""
import json
import pathlib
import re
import ssl
import tempfile
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'CardService' / 'OfflineGames' / 'catalog.json'
FALLBACK = 'DMU'
COLORS = 'WUBRG'
STARTER_PROMOS = {'starterdeck', 'startercollection'}


def pair_key(colors):
    return ''.join(sorted(colors, key=COLORS.index))


def duals_by_pair(cards):
    """One common land per two-color pair: regular frames first, then the lowest collector number."""
    chosen = {}
    def order(card):
        return (card.get('full_art', False), int(re.sub(r'\D', '', card['collector_number']) or 0), card['collector_number'])
    for card in sorted(cards, key=order):
        produced = [c for c in card.get('produced_mana', []) if c in COLORS]
        if card.get('rarity') != 'common' or 'Land' not in card.get('type_line', '') or len(set(produced)) != 2:
            continue
        # Starter-product-only reprints (BLB's two gainlands, FDN's guildgates) aren't part of the
        # set's own land cycle. FDN's gainlands carry the same promo type but are in boosters.
        if STARTER_PROMOS & set(card.get('promo_types') or []) and not card.get('booster', True):
            continue
        chosen.setdefault(pair_key(set(produced)), card)
    return chosen


def fetch(code, cache_dir):
    cached = cache_dir / (code + '.json')
    if cached.exists():
        return json.loads(cached.read_text())
    query = f'set:{code.lower()} t:land r:c produces=2 lang:en game:paper'
    url = 'https://api.scryfall.com/cards/search?' + urllib.parse.urlencode({'q': query, 'unique': 'prints'})
    cards = []
    while url:
        request = urllib.request.Request(url, headers={'User-Agent': 'MagicBoard-OfflineCatalog/1.0', 'Accept': 'application/json'})
        try:
            with urllib.request.urlopen(request, timeout=45, context=ssl.create_default_context(cafile='/etc/ssl/cert.pem')) as response:
                page = json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 404:  # Scryfall: no cards match.
                break
            raise
        cards.extend(page['data'])
        url = page.get('next_page')
        time.sleep(0.3)
    cached.write_text(json.dumps(cards))
    return cards


def main():
    catalog = json.loads(CATALOG.read_text())
    cache_dir = pathlib.Path(tempfile.gettempdir()) / 'magic-jumpin-dual-sets'
    cache_dir.mkdir(exist_ok=True)
    result = {}
    for code in sorted({p['setCode'] for p in catalog['jumpInPackets']} | {FALLBACK}):
        duals = {}
        for pair, card in duals_by_pair(fetch(code, cache_dir)).items():
            key = f"jumpin-dual|{code.lower()}|{card['id']}"
            catalog['cards'][key] = card
            uris = card.get('image_uris', {})
            for kind in ('normal', 'art_crop'):
                if kind in uris:
                    catalog['images'][uris[kind]] = f"{card['id']}-{kind}-front.jpg"
            if 'normal' in uris:
                for kind in ('small', 'large', 'png', 'border_crop'):
                    if kind in uris:
                        catalog['images'][uris[kind]] = catalog['images'][uris['normal']]
            duals[pair] = key
        if duals:
            result[code] = duals
        print(code, sorted(duals), flush=True)
    if len(result.get(FALLBACK, {})) != 10:
        raise ValueError(f'{FALLBACK} fallback cycle is incomplete: {sorted(result.get(FALLBACK, {}))}')
    catalog['jumpInDuals'] = result
    temporary = CATALOG.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(catalog, ensure_ascii=False, separators=(',', ':')))
    temporary.replace(CATALOG)


if __name__ == '__main__':
    main()
