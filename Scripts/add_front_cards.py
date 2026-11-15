"""Add JumpStart front cards (packet theme cards) to the bundled offline catalog.

catalog["frontCards"] = {SETCODE: {theme name: normal image URL}}; each image URL is also
added to catalog["images"] so the app downloads it with the rest of the artwork at runtime.
Runs automatically at the end of build_offline_catalog.py; safe to run on its own.
"""
import json, pathlib, ssl, time, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'CardService' / 'OfflineGames' / 'catalog.json'
# Catalog JumpStart set code -> Scryfall front-card set. SuperJump has no front cards.
FRONT_SETS = {'JMP': 'fjmp', 'J22': 'fj22', 'J25': 'fj25', 'TLA': 'jtla', 'MSH': 'fmsc'}
HEADERS = {'User-Agent': 'MagicBoard-OfflineCatalog/1.0', 'Accept': 'application/json'}


def get(url):
    request = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(request, timeout=60, context=ssl.create_default_context(cafile="/etc/ssl/cert.pem")) as response:
        return json.loads(response.read())


def front_cards(code):
    cards, url = [], f'https://api.scryfall.com/cards/search?q=set:{code}&unique=prints'
    while url:
        page = get(url)
        cards += page['data']
        url = page.get('next_page')
        time.sleep(0.15)
    return cards


def main():
    catalog = json.loads(CATALOG.read_text())
    images = catalog.setdefault('images', {})
    result = {}
    for set_code, front_code in FRONT_SETS.items():
        themes = {}
        for card in front_cards(front_code):
            uris = card.get('image_uris') or (card.get('card_faces') or [{}])[0].get('image_uris') or {}
            if 'normal' not in uris:
                continue
            themes.setdefault(card['name'], uris['normal'])
            images.setdefault(uris['normal'], f"{card['id']}-normal-front.jpg")
        result[set_code] = themes
        print(set_code, front_code, len(themes), 'front cards', flush=True)
    catalog['frontCards'] = result
    temporary = CATALOG.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(catalog, ensure_ascii=False, separators=(',', ':')))
    temporary.replace(CATALOG)


if __name__ == '__main__':
    main()
