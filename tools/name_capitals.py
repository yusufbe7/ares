"""Mavjud ma'lumotga tuzatish: poytaxt shahri joylashgan hudud shu shahar nomini oladi.
(Kichik viloyatlar birlashtirilganda Parij hududi "Calvados" kabi nom olib qolgan edi.)
Ishga tushirish: python tools/name_capitals.py <natural_earth_papka>
build_campaign_data.py ning o'zi ham endi shunday qiladi; bu skript faqat qayta yasamasdan tuzatish uchun."""
import json, os, sys
from PIL import Image

ne = sys.argv[1]
meta = json.load(open("data/map_meta.json"))
W, H = meta["width"], meta["height"]
ids = Image.open("map/province_ids.png").convert("RGB").load()
provs = json.load(open("data/provinces.json", encoding="utf-8"))
cl = json.load(open("data/countries.json", encoding="utf-8"))
countries = cl["countries"] if isinstance(cl, dict) else cl
by_id = {p["id"]: p for p in provs}
code_of = {c["id"]: c["code"] for c in countries}
places = json.load(open(os.path.join(ne, "ne_10m_populated_places_simple.geojson"), encoding="utf-8"))["features"]
n = 0
done = set()
for f in places:
    p = f["properties"]
    if (p.get("featurecla") or "") != "Admin-0 capital":      # "alt" (ikkinchi poytaxt) emas
        continue
    lon, lat = f["geometry"]["coordinates"][:2]
    x = int((lon - meta["lon_min"]) / (meta["lon_max"] - meta["lon_min"]) * W)
    y = int((meta["lat_max"] - lat) / (meta["lat_max"] - meta["lat_min"]) * H)
    if not (0 <= x < W and 0 <= y < H):
        continue
    r, g, _ = ids[x, y]
    pid = r + g * 256
    pr = by_id.get(pid)
    if pr is None or code_of.get(pr["owner"]) != p.get("adm0_a3") or p.get("adm0_a3") in done:
        continue
    done.add(p.get("adm0_a3"))
    name = p.get("name_en") or p.get("name")
    if name and pr["name"] != name:
        print("%-28s -> %s" % (pr["name"], name))
        pr["name"] = name
        n += 1
json.dump(provs, open("data/provinces.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("renamed", n)
