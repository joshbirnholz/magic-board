"""Import the published Marvel Super Heroes JumpStart themes from Wizards."""
import html, pathlib, re, ssl, urllib.request
root=pathlib.Path(__file__).resolve().parents[1]
url='https://magic.wizards.com/en/news/announcements/marvel-super-heroes-jumpstart-booster-themes'
with urllib.request.urlopen(url,context=ssl.create_default_context(cafile='/etc/ssl/cert.pem'),timeout=60) as response: page=response.read().decode()
folder=root/'CardService'/'JumpStart'/'Marvel Super Heroes'; folder.mkdir(exist_ok=True)
packets=re.findall(r'<deck-list\b[^>]*deck-title="([^"]+)"[^>]*>\s*<main-deck>(.*?)</main-deck>',page,re.S)
assert len(packets)==51, f'Expected 51 published themes, got {len(packets)}'
for title, text in packets:
    rows=[]; total=0
    for line in html.unescape(text).strip().splitlines():
        line=line.strip()
        if not line: continue
        match=re.match(r'^(\d+)\s+(.+)$',line)
        count,name=(int(match[1]),match[2]) if match else (1,line)
        # Typography in article text is not always the API's ASCII apostrophe.
        name=name.replace('’',"'")
        rows.append(f'{count} {name} (MSH)')
        total+=count
    assert total==20, (title,total)
    safe=html.unescape(title).replace('/','-')
    (folder/(safe+'.txt')).write_text('\n'.join(rows)+'\n')
print('Imported',len(packets),'Marvel Super Heroes packets')
