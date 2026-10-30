"""Hudud, davlat, qo'shin, baza ma'lumotlari va rasmlarni yozish (build_campaign_map.py dan chaqiriladi)."""
import json, math, os, hashlib
import numpy as np
from PIL import Image
from scipy import ndimage
from mapgen_lib import *          # noqa

Image.MAX_IMAGE_PIXELS = None


def satellite(path):
    """Blue Marble (butun dunyo, 90..-90) -> shu xarita qamrovi va o'lchami."""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    top = (90 - LAT1) / 180 * h
    bot = (90 - LAT0) / 180 * h
    return im.resize((W, H), Image.LANCZOS, box=(0, top, w, bot))


def resource_of(c, is_coast, hmean, hmax, lat, rgb, oil, i):
    r, g, b = rgb
    green = g - (r + b) * 0.5
    bright = (r + g + b) / 3
    desert = r > 120 and green < 6
    if c in oil and hmean < 900 and (desert or abs(lat) > 55 or i % 3 == 0):
        return "oil"
    if hmax > 2400:
        return "iron"
    if green > 10 and bright < 70:
        return "wood"
    if desert:
        return "salt" if not is_coast else "fish"
    if hmean > 1100:
        return "stone"
    if is_coast and i % 3 == 0:
        return "fish"
    return "grain"


def write_all(out, Z, pid, old, unit_country, unit_name, c0, places, pa, bluemarble, oil, short_km):
    N = len(old)
    os.makedirs(os.path.join(out, "map"), exist_ok=True)
    os.makedirs(os.path.join(out, "data"), exist_ok=True)
    countries = sorted({unit_country[u] for u in old})
    cid = {c: i + 1 for i, c in enumerate(countries)}
    owner = {i + 1: unit_country[u] for i, u in enumerate(old)}
    area = np.bincount(pid.ravel(), weights=pa.ravel(), minlength=N + 1)
    pixels = np.bincount(pid.ravel(), minlength=N + 1)
    # ---------------- shaharlar: aholi va poytaxtlar (Natural Earth populated places)
    city_pop = np.zeros(N + 1)
    capital = {}
    cap_name = {}                   # poytaxt joylashgan hudud shu shahar nomini oladi (Paris, Tashkent...)
    for f in places:
        p = f["properties"]
        lon, lat = f["geometry"]["coordinates"][:2]
        x, y = px(lon, lat)
        if not (0 <= x < W and 0 <= y < H):
            continue
        i = int(pid[int(y), int(x)])
        if i == 0:
            continue
        city_pop[i] += max(0, p.get("pop_max") or 0)
        cc = owner[i]
        if (p.get("featurecla") or "") == "Admin-0 capital" and p.get("adm0_a3") == cc and cc not in capital:
            capital[cc] = i
            cap_name[i] = p.get("name_en") or p.get("name") or ""
    # aholi: shahar aholisi + davlat aholisining qolgani maydon bo'yicha (POP_EST - haqiqiy son)
    cpop_city, carea = {}, {}
    for i in range(1, N + 1):
        cpop_city[owner[i]] = cpop_city.get(owner[i], 0) + city_pop[i]
        carea[owner[i]] = carea.get(owner[i], 0) + area[i]
    pop = np.zeros(N + 1)
    for i in range(1, N + 1):
        c = owner[i]
        total = c0.get(c, {}).get("pop", 0) or (cpop_city[c] * 1.6)
        scale = min(1.0, total * 0.85 / cpop_city[c]) if cpop_city[c] > 0 else 0
        rest = max(0.0, total - cpop_city[c] * scale)
        pop[i] = city_pop[i] * scale + rest * area[i] / max(carea[c], 1)
    # ---------------- qo'shnilar: quruqlik va dengiz
    adj = adjacency(pid)
    land = {(a, b) for (a, b), n in adj.items() if n >= 2}
    sea = connect_components(N, land, sea_links(pid, short_km), short_km)
    nbrs = {i: {"land": set(), "sea": {}} for i in range(1, N + 1)}
    for a, b in land:
        nbrs[a]["land"].add(b); nbrs[b]["land"].add(a)
    for (a, b), d in sea.items():
        nbrs[a]["sea"][b] = int(d); nbrs[b]["sea"][a] = int(d)
    # ---------------- hudud ma'lumotlari
    sat = satellite(bluemarble)
    sat_np = np.asarray(sat)
    coast = ndimage.binary_dilation(pid == 0) & (pid > 0)
    provinces = []
    objs = ndimage.find_objects(pid)
    for i in range(1, N + 1):
        sl = objs[i - 1]
        m = pid[sl] == i
        dloc = ndimage.distance_transform_edt(np.pad(m, 1))[1:-1, 1:-1]
        cy, cx = np.unravel_index(np.argmax(dloc), dloc.shape)
        cy += sl[0].start; cx += sl[1].start
        z = Z[sl][m]
        c = owner[i]
        lat = row_lat(cy)
        is_coast = bool(coast[sl][m].any())
        hmean, hmax = float(np.mean(np.maximum(z, 0))), float(np.max(z))
        rgb = sat_np[sl][m].reshape(-1, 3).mean(0)
        res = resource_of(c, is_coast, hmean, hmax, lat, rgb, oil, i)
        cpop = c0.get(c, {}).get("pop", 0) or 1
        provinces.append({
            "id": i, "name": cap_name.get(i) or unit_name[old[i - 1]], "owner": cid[c],
            "population": int(round(pop[i] / 1000.0)) * 1000,
            "gdp_musd": round(c0.get(c, {}).get("gdp", 0) * pop[i] / cpop, 1),
            "resource": res, "resource_amount": int(min(3, 1 + area[i] // 80000)),
            "area_km2": int(area[i]), "pixels": int(pixels[i]), "coastal": is_coast,
            "center_px": [int(cx), int(cy)], "elevation_m": int(hmean),
        })
    # ---------------- davlatlar: xira (tabiiy) ranglar, qo'shnilar har xil
    cadj = {c: set() for c in countries}
    for (a, b) in land:
        if owner[a] != owner[b]:
            cadj[owner[a]].add(owner[b]); cadj[owner[b]].add(owner[a])
    hues = [0.0, 0.33, 0.6, 0.12, 0.8, 0.5, 0.95, 0.25, 0.7, 0.05, 0.42, 0.88]
    slot = {}
    for c in sorted(countries, key=lambda c: -len(cadj[c])):
        used = {slot[o] for o in cadj[c] if o in slot}
        h = int(hashlib.md5(c.encode()).hexdigest(), 16)
        slot[c] = next((s for s in [(h + j) % len(hues) for j in range(len(hues))] if s not in used), h % len(hues))
    prov_of = {}
    for p in provinces:
        prov_of.setdefault(p["owner"], []).append(p)
    cdata, armies, bases = [], [], []
    for c in countries:
        h = int(hashlib.md5(c.encode()).hexdigest(), 16)
        mine = sorted(prov_of.get(cid[c], []), key=lambda p: -p["population"])
        cap = capital.get(c) or mine[0]["id"]
        info = c0.get(c, {"name": c, "pop": 0, "gdp": 0, "iso2": ""})
        gdp = info["gdp"] or sum(p["gdp_musd"] for p in mine)
        cdata.append({"id": cid[c], "code": c, "iso2": info["iso2"] if len(info["iso2"]) == 2 else c[:2],
                      "name": info["name"],
                      "color": hsv_hex(hues[slot[c]] + ((h % 7) - 3) * 0.012, 0.42 + (h % 4) * 0.05, 0.74 + (h % 3) * 0.05),
                      "controller": "bot", "capital": int(cap),
                      "population": int(info["pop"]), "gdp_musd": int(gdp),
                      "resources": {"gold": int(300 + math.sqrt(max(gdp, 0)) * 2.0), "supply": 40 + 10 * len(mine),
                                    "manpower": int(max(2000, info["pop"] * 0.002))}})
        # qo'shin kuchi iqtisod va aholidan (real YaIM va aholi)
        size = int(np.clip(round(1.5 * math.log10(max(gdp, 10)) + 0.6 * math.log10(max(info["pop"], 1e4))), 4, 24))
        armies.append({"owner": cid[c], "province": int(cap), "size": size})
        extra = [p for p in mine if p["id"] != cap][:min(4, len(mine) // 10)]
        for p in extra:
            armies.append({"owner": cid[c], "province": p["id"], "size": max(3, size // 2)})
        bases.append({"province": int(cap), "type": "army"})
        coastal = [p for p in mine if p["coastal"] and p["id"] != cap]
        if len(mine) >= 5 and coastal:
            bases.append({"province": coastal[0]["id"], "type": "naval"})
        others = [p for p in mine if p["id"] != cap and p not in coastal[:1]]
        if len(mine) >= 15 and others:
            bases.append({"province": others[0]["id"], "type": "air"})
    # ---------------- yozish
    v = np.clip(np.round((Z + 12000.0) * 2.0), 0, 65535).astype(np.uint32)
    Image.fromarray(np.stack([(v >> 8).astype(np.uint8), (v & 255).astype(np.uint8), np.zeros_like(v, np.uint8)], -1), "RGB") \
        .save(os.path.join(out, "map", "height.png"), optimize=True)
    blue = ((pid * 97) % 200 + 40).astype(np.uint8)
    blue[pid == 0] = 0
    Image.fromarray(np.stack([(pid & 255).astype(np.uint8), (pid >> 8).astype(np.uint8), blue], -1), "RGB") \
        .save(os.path.join(out, "map", "province_ids.png"), optimize=True)
    sat.save(os.path.join(out, "map", "satellite.jpg"), quality=90)
    Image.fromarray(normal_map(Z), "RGB").save(os.path.join(out, "map", "normal.png"), optimize=True)
    meta = {"lon_min": LON0, "lon_max": LON1, "lat_min": LAT0, "lat_max": LAT1, "width": W, "height": H,
            "province_count": N,
            "height_decode": "metres = (R*256 + G) / 2 - 12000", "id_decode": "id = R + G*256 (0 = sea)",
            "sources": ["NOAA ETOPO 2022 60 arc-second surface", "NASA Blue Marble (Aug 2004)",
                        "Natural Earth 10m admin-0 / admin-1 / populated places / lakes (public domain)"]}
    D = lambda n, o, **k: json.dump(o, open(os.path.join(out, "data", n), "w", encoding="utf-8"), ensure_ascii=False, **k)
    D("map_meta.json", meta, indent=1)
    D("provinces.json", provinces, indent=0)
    D("neighbors.json", {str(i): {"land": sorted(nbrs[i]["land"]), "sea": [[k, d] for k, d in sorted(nbrs[i]["sea"].items())]}
                         for i in range(1, N + 1)})
    D("countries.json", cdata, indent=1)
    D("armies.json", armies, indent=0)
    D("bases.json", bases, indent=0)
    print("provinces", N, "countries", len(cdata), "armies", len(armies), "sea links", len(sea),
          "km2 min/med/max", int(area[1:].min()), int(np.median(area[1:])), int(area[1:].max()))
