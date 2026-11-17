"""Add the oracle IDs of cards with selected Scryfall Tagger oracle tags to the offline catalog, as
the bundled fallback for CardService's OracleTags (which refreshes the same lists from Scryfall's
`oracle_tags` bulk data when online).

catalog['oracle_tags'] maps a tag slug to the sorted oracle IDs of every card tagged with it or
with any of its descendant tags (e.g. `tapland` includes `cycle-guildgate`, `bounceland`, ...).

Usage: python3 Scripts/add_oracle_tags.py
"""
import gzip
import json
import pathlib
import ssl
import tempfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'CardService' / 'OfflineGames' / 'catalog.json'
# Keep in sync with OracleTags.tracked in CardService/CardService.swift.
TRACKED = ['tapland']
HEADERS = {'User-Agent': 'MagicBoard-OfflineCatalog/1.0', 'Accept': 'application/json'}
CONTEXT = ssl.create_default_context(cafile='/etc/ssl/cert.pem')


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=120, context=CONTEXT) as response:
        return response.read()


def main():
    bulk = json.loads(get('https://api.scryfall.com/bulk-data'))
    entry = next(item for item in bulk['data'] if item['type'] == 'oracle_tags')
    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / 'oracle-tags.jsonl.gz'
        path.write_bytes(get(entry['jsonl_download_uri']))
        tags = [json.loads(line) for line in gzip.open(path, 'rt')]
    by_id = {tag['id']: tag for tag in tags}
    by_slug = {tag['slug']: tag for tag in tags}

    def oracle_ids(tag, seen):
        ids = {tagging['oracle_id'] for tagging in tag['taggings'] if tagging.get('oracle_id')}
        for child in tag.get('child_ids') or []:
            if child in by_id and child not in seen:
                seen.add(child)
                ids |= oracle_ids(by_id[child], seen)
        return ids

    result = {slug: sorted(oracle_ids(by_slug[slug], {by_slug[slug]['id']})) for slug in TRACKED}
    catalog = json.loads(CATALOG.read_text())
    catalog['oracle_tags'] = result
    temporary = CATALOG.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(catalog, ensure_ascii=False, separators=(',', ':')))
    temporary.replace(CATALOG)
    for slug, ids in result.items():
        print(slug, len(ids))


if __name__ == '__main__':
    main()
