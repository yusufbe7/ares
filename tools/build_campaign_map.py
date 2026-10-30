"""Strategik dunyo xaritasi ma'lumotlarini yasash (Godot: res://map va res://data).

Manbalar (hammasi bepul, public domain):
  * relyef: NOAA ETOPO 2022, 60 yoy-soniya (OPeNDAP .ascii kesmasi, qadam 5 -> 5 yoy-daqiqa)
  * sun'iy yo'ldosh rasmi: NASA Blue Marble (world.200408.3x5400x2700.jpg)
  * viloyatlar, davlatlar, aholi, YaIM, shaharlar, ko'llar: Natural Earth 10m
Chiqadi:
  map/height.png        relyef: metr = (R*256 + G) / 2 - 12000
  map/province_ids.png  hudud: id = R + G*256 (0 = dengiz)
  map/satellite.jpg     yer rangi (Blue Marble, shu proyeksiyada)
  map/normal.png        relyef soyasi uchun normal xarita (yarim o'lcham)
  data/map_meta.json, provinces.json, neighbors.json (land + sea), countries.json, armies.json, bases.json
Ishlatish:
  python build_campaign_map.py <etopo.ascii|.npy> <bluemarble.jpg> <natural_earth_papka> <godot_loyiha>
"""
import json, math, os, sys, hashlib
import numpy as np
from PIL import Image
from scipy import ndimage
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mapgen_lib import *          # noqa

MIN_KM2 = 30000        # bundan kichik viloyatlar o'z davlatidagi qo'shnisi bilan birlashadi
MAX_KM2 = 240000       # bundan kattasi bo'laklarga bo'linadi
MIN_COUNTRY_KM2 = 1500 # juda kichik davlatlar (Vatikan, Monako...) qo'shni davlatga qo'shiladi
SEA_SHORT_KM = 320     # shu masofagacha bo'lgan dengiz yo'llari hammasi olinadi
ALIAS = {"KAB": "KAZ", "CNM": "CYP", "ESB": "CYP", "WSB": "CYP", "KAS": "IND", "SPI": "ARG", "USG": "CUB",
         "BJN": "COL", "SER": "COL", "SCR": "CHN", "CSI": "AUS", "ATC": "AUS", "IOA": "AUS", "PGA": "CHN"}
OIL = {"SAU", "IRQ", "KWT", "IRN", "ARE", "QAT", "LBY", "DZA", "AZE", "KAZ", "TKM", "RUS", "OMN", "BHR", "NOR", "SYR",
       "USA", "CAN", "VEN", "NGA", "AGO", "BRA", "MEX", "CHN", "GBR", "EGY", "COL", "ECU", "MYS", "IDN", "GAB", "COG", "SDN", "SSD", "YEM"}


def merge_small(unit_country, area, adj, min_km2):
    """Kichik birliklarni graf ustida birlashtiradi (rasmga tegmasdan). Natija: birlik -> ildiz."""
    parent = {u: u for u in area}
    nb = {u: {} for u in area}
    for (a, b), n in adj.items():
        if a in nb and b in nb:
            nb[a][b] = nb[a].get(b, 0) + n
            nb[b][a] = nb[b].get(a, 0) + n
    import heapq
    heap = [(area[u], u) for u in area]
    heapq.heapify(heap)
    while heap:
        ar, u = heapq.heappop(heap)
        if parent[u] != u or ar != area[u] or ar >= min_km2:
            continue
        cands = [v for v in nb[u] if parent[v] == v and unit_country[v] == unit_country[u]]
        if not cands:
            continue
        v = min(cands, key=lambda v: area[v])
        parent[u] = v
        area[v] += area[u]
        for w, n in nb[u].items():
            if w != v:
                nb[v][w] = nb[v].get(w, 0) + n
                nb[w].pop(u, None)
                nb[w][v] = nb[w].get(v, 0) + n
        nb[v].pop(u, None)
        heapq.heappush(heap, (area[v], v))
    def root(u):
        while parent[u] != u:
            u = parent[u]
        return u
    return {u: root(u) for u in area}


def main(etopo, bluemarble, ne, out):
    Z = load_height(etopo)
    assert Z.shape == (H, W), Z.shape
    pa = pixel_area_km2()[:, None] * np.ones((1, W), np.float32)
    G = lambda n: json.load(open(os.path.join(ne, n + ".geojson"), encoding="utf-8"))["features"]
    adm1, adm0, places = G("ne_10m_admin_1_states_provinces"), G("ne_10m_admin_0_countries"), G("ne_10m_populated_places_simple")
    lakes = [f for f in G("ne_10m_lakes") if (f["properties"].get("scalerank") or 9) <= 3]
    ids = raster(adm1)
    ids[raster(lakes) > 0] = 0
    # sohil bo'yidagi dengizga chiqib qolgan piksellar (relyef dengiz tubi) dengizga qaytariladi
    near_sea = ndimage.binary_dilation(ids == 0, iterations=2)
    ids[(Z < -10) & near_sea & (ids > 0)] = 0
    unit_country = {i + 1: ALIAS.get(f["properties"]["adm0_a3"], f["properties"]["adm0_a3"]) for i, f in enumerate(adm1)}
    unit_name = {i + 1: (f["properties"].get("name_en") or f["properties"].get("name") or "?") for i, f in enumerate(adm1)}
    c0 = {}
    for f in adm0:
        p = f["properties"]
        c0[p["ADM0_A3"]] = {"name": p.get("NAME_EN") or p["NAME"], "pop": float(p.get("POP_EST") or 0),
                             "gdp": float(p.get("GDP_MD") or 0), "iso2": p.get("ISO_A2_EH") or p.get("ISO_A2") or ""}
    # ---------------- maydonlar (km2) va juda kichik davlatlarni qo'shnisiga qo'shish
    n_units = len(adm1) + 1
    uarea = np.bincount(ids.ravel(), weights=pa.ravel(), minlength=n_units)
    adj = adjacency(ids)
    carea = {}
    for u in np.nonzero(uarea)[0]:
        if u:
            carea[unit_country[u]] = carea.get(unit_country[u], 0) + uarea[u]
    remap = np.arange(max(n_units, ids.max() + 1), dtype=np.int32)
    coms = ndimage.center_of_mass(np.ones_like(ids), ids, range(n_units))
    for c, a in sorted(carea.items(), key=lambda t: t[1]):
        if a >= MIN_COUNTRY_KM2:
            continue
        units = [u for u in np.nonzero(uarea)[0] if u and unit_country[u] == c]
        border = {}
        for (x, y), n in adj.items():
            if x in units and unit_country[y] != c: border[y] = border.get(y, 0) + n
            if y in units and unit_country[x] != c: border[x] = border.get(x, 0) + n
        if border:
            tgt = max(border, key=border.get)
        else:   # orol davlat: eng yaqin katta davlat birligi
            cy, cx = coms[units[0]]
            big = [u for u in np.nonzero(uarea)[0] if u and carea.get(unit_country[u], 0) >= MIN_COUNTRY_KM2]
            tgt = min(big, key=lambda u: (coms[u][0] - cy) ** 2 + (coms[u][1] - cx) ** 2)
        for u in units:
            remap[u] = tgt
            unit_country[u] = unit_country[tgt]
    ids = remap[ids]
    # ---------------- viloyatlarni hudud qilib birlashtirish (graf ustida, tez)
    uarea = np.bincount(ids.ravel(), weights=pa.ravel(), minlength=ids.max() + 1)
    area = {int(u): float(uarea[u]) for u in np.nonzero(uarea)[0] if u}
    root = merge_small(unit_country, area, adjacency(ids), MIN_KM2)
    remap = np.arange(ids.max() + 1, dtype=np.int32)
    biggest = {}                    # birlashgan hudud nomi = eng katta viloyat nomi
    for u, r in root.items():
        remap[u] = r
        if r not in biggest or uarea[u] > uarea[biggest[r]]:
            biggest[r] = u
    for r, u in biggest.items():
        unit_name[r] = unit_name[u]
    label = remap[ids]
    # orollar: o'z davlatidagi eng yaqin hududga (chegarasi bo'lmasa ham)
    uarea = np.bincount(label.ravel(), weights=pa.ravel(), minlength=label.max() + 1)
    alive = [int(u) for u in np.nonzero(uarea)[0] if u]
    coms = dict(zip(alive, ndimage.center_of_mass(np.ones_like(label), label, alive)))
    remap = np.arange(label.max() + 1, dtype=np.int32)
    for u in sorted(alive, key=lambda u: uarea[u]):
        if uarea[u] >= MIN_KM2 * 0.35:
            continue
        same = [v for v in alive if v != u and remap[v] == v and unit_country[v] == unit_country[u] and uarea[v] >= MIN_KM2 * 0.35]
        if same:
            v = min(same, key=lambda v: (coms[v][0] - coms[u][0]) ** 2 + ((coms[v][1] - coms[u][1]) * math.cos(math.radians(row_lat(coms[u][0])))) ** 2)
            remap[u] = v
    label = remap[label]
    # katta hududlarni bo'lish (k-means, maydonga qarab)
    from sklearn.cluster import KMeans
    uarea = np.bincount(label.ravel(), weights=pa.ravel(), minlength=label.max() + 1)
    next_id = int(label.max()) + 1
    objs = ndimage.find_objects(label)
    for u in [int(u) for u in np.nonzero(uarea)[0] if u and uarea[u] > MAX_KM2]:
        sl = objs[u - 1]
        ys, xs = np.nonzero(label[sl] == u)
        ys = ys + sl[0].start; xs = xs + sl[1].start
        k = int(math.ceil(uarea[u] / (MAX_KM2 * 0.55)))
        lat = row_lat(ys.mean())
        pts = np.stack([xs * math.cos(math.radians(lat)), ys], 1)
        km = KMeans(n_clusters=k, n_init=2, random_state=1).fit(pts[::max(1, len(pts) // 40000)])
        lab = km.predict(pts)
        base = unit_name[u]
        my, mx = ys.mean(), xs.mean()
        def compass(c):
            cx, cy = c[0] / math.cos(math.radians(lat)), c[1]
            ns = "North " if cy < my - 12 else ("South " if cy > my + 12 else "")
            ew = "West" if cx < mx - 12 else ("East" if cx > mx + 12 else ("Central" if not ns else ""))
            return (ns + ew).strip() or "Central"
        names = {}
        for j in range(k):
            nm = "%s %s" % (base, compass(km.cluster_centers_[j]))
            names[nm] = names.get(nm, 0) + 1
            if names[nm] > 1:
                nm = "%s %d" % (nm, names[nm])
            if j == 0:
                unit_name[u] = nm
                continue
            m = lab == j
            label[ys[m], xs[m]] = next_id
            unit_country[next_id] = unit_country[u]
            unit_name[next_id] = nm
            next_id += 1
    # bo'linishdan uzilib qolgan mayda bo'laklar qo'shniga
    objs = ndimage.find_objects(label)
    for u in range(1, len(objs) + 1):
        if objs[u - 1] is None:
            continue
        sl = tuple(slice(max(0, s.start - 1), s.stop + 1) for s in objs[u - 1])
        sub = label[sl]
        lab, n = ndimage.label(sub == u)
        if n > 1:
            sizes = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
            keep = int(np.argmax(sizes)) + 1
            for k in range(1, n + 1):
                if k != keep and sizes[k - 1] < 12:
                    m = lab == k
                    ring = ndimage.binary_dilation(m) & ~m
                    nbv = sub[ring]
                    nbv = nbv[(nbv > 0) & (nbv != u)]
                    sub[m] = np.bincount(nbv).argmax() if nbv.size else 0
    # ---------------- yangi ketma-ket id lar
    old = [int(u) for u in np.unique(label) if u > 0]
    rm = np.zeros(label.max() + 1, np.int32)
    for i, u in enumerate(old):
        rm[u] = i + 1
    pid = rm[label]
    N = len(old)
    assert N < 65536
    from build_campaign_data import write_all
    write_all(out, Z, pid, old, unit_country, unit_name, c0, places, pa, bluemarble, OIL, SEA_SHORT_KM)


if __name__ == "__main__":
    main(*sys.argv[1:5])
