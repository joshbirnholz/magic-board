"""Cache Marvel set records in bulk instead of issuing per-card lookups."""
import json,pathlib,time,ssl,urllib.request,urllib.parse,urllib.error,tempfile
cache=pathlib.Path(tempfile.gettempdir())/'magic-marvel-printings.json'
if cache.exists():
 print('Using cached Marvel set records',flush=True); raise SystemExit
# Respect the preceding named-card endpoint's Retry-After before changing routes.
print('Waiting 60 seconds for the prior rate limit',flush=True)
time.sleep(60)
url='https://api.scryfall.com/cards/search?'+urllib.parse.urlencode({'q':'(set:msh or set:msc) lang:en','unique':'prints','order':'set'})
cards=[]
while url:
 for attempt in range(6):
  try:
   req=urllib.request.Request(url,headers={'User-Agent':'MagicBoard-OfflineCatalog/1.0','Accept':'application/json'})
   with urllib.request.urlopen(req,context=ssl.create_default_context(cafile='/etc/ssl/cert.pem'),timeout=60) as r: result=json.load(r)
   break
  except urllib.error.HTTPError as e:
   if e.code==429 and attempt<5:
    delay=min(60,max(15,float(e.headers.get('Retry-After','60')))); print('Backing off',delay,flush=True);time.sleep(delay)
   else: raise
 cards.extend(result['data']);print('Marvel records',len(cards),flush=True)
 url=result.get('next_page');time.sleep(.5)
cache.write_text(json.dumps(cards))
