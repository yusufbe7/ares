"""build_campaign_map.py uchun yordamchi funksiyalar: proyeksiya, rasterlash, qo'shnilar, dengiz yo'llari."""
import math, re
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

# Butun dunyo (Antarktidasiz), equirectangular, 5 yoy-daqiqa (1 gradus = 12 piksel)
LON0, LON1, LAT0, LAT1 = -180.0, 180.0, -58.0, 84.0
W, H = 4320, 1704


def px(lon, lat):
    return ((lon - LON0) / (LON1 - LON0) * W, (LAT1 - lat) / (LAT1 - LAT0) * H)


def row_lat(y):
    return LAT1 - (y + 0.5) / H * (LAT1 - LAT0)


def km_per_px_x(lat):
    return 111.32 * math.cos(math.radians(lat)) * (LON1 - LON0) / W


KM_PER_PX_Y = 111.32 * (LAT1 - LAT0) / H


def pixel_area_km2():
    """Har bir qatordagi bitta piksel maydoni (km2), (H,) massiv."""
    lat = LAT1 - (np.arange(H) + 0.5) / H * (LAT1 - LAT0)
    return 111.32 * np.cos(np.radians(lat)) * (LON1 - LON0) / W * KM_PER_PX_Y


def load_height(path):
    """ETOPO OPeNDAP .ascii (qatorlar janubdan shimolga) yoki .npy -> (H, W), 0-qator shimolda."""
    if path.endswith(".npy"):
        return np.load(path)
    rows = {}
    for line in open(path):
        m = re.match(r"^\[(\d+)\], (.*)$", line)
        if m:
            rows[int(m.group(1))] = np.array(m.group(2).split(","), dtype=np.float32)
        elif line.startswith("z.lat"):
            break
    return np.stack([rows[i] for i in range(len(rows))])[::-1]


def polys(geom):
    if geom is None:
        return []
    if geom["type"] == "Polygon":
        return [geom["coordinates"]]
    if geom["type"] == "MultiPolygon":
        return geom["coordinates"]
    return []


def raster(features, holes=False):
    """Har bir obyekt indeksini (1..) rasmga chizadi; kichiklar keyin chiziladi (anklavlar yo'qolmasin)."""
    items = []
    for i, f in enumerate(features):
        for poly in polys(f["geometry"]):
            for ri, ring in enumerate(poly if holes else poly[:1]):
                pts = [px(x, y) for x, y in ring]
                a = 0.0
                for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
                    a += x0 * y1 - x1 * y0
                items.append((abs(a), i + 1, pts))
    items.sort(key=lambda t: -t[0])
    img = Image.new("I", (W, H), 0)
    d = ImageDraw.Draw(img)
    for _, idx, pts in items:
        if len(pts) >= 3:
            d.polygon(pts, fill=idx)
    return np.array(img, dtype=np.int32)


def adjacency(ids):
    """Qo'shni piksellar juftliklari: {(a, b): chegara uzunligi}."""
    pairs = {}
    for a, b in ((ids[:, :-1], ids[:, 1:]), (ids[:-1, :], ids[1:, :])):
        m = (a != b) & (a > 0) & (b > 0)
        if not m.any():
            continue
        x = np.minimum(a[m], b[m]).astype(np.int64)
        y = np.maximum(a[m], b[m]).astype(np.int64)
        key = x * 1_000_000 + y
        u, c = np.unique(key, return_counts=True)
        for k, n in zip(u.tolist(), c.tolist()):
            pairs[(k // 1_000_000, k % 1_000_000)] = n
    return pairs


def sea_links(pid, short_km=320.0):
    """Dengiz orqali bog'lanishlar.
    Dengiz piksellari eng yaqin sohil hududiga bo'linadi (Voronoi). Ikki hudud "dengiz zonasi" tegishgan
    joyda masofa = d1 + d2. Qisqalari (short_km dan kam) olinadi, keyin hamma quruqlik guruhlari
    bir-biriga eng qisqa dengiz yo'li bilan ulanadi (Kruskal), shunda har bir orolga borish mumkin."""
    sea = pid == 0
    dist, (iy, ix) = ndimage.distance_transform_edt(sea, return_indices=True)
    near = pid[iy, ix]
    kx = np.array([km_per_px_x(row_lat(y)) for y in range(H)], np.float32)[:, None]
    dkm = dist * (kx + KM_PER_PX_Y) * 0.5
    best = {}
    for sl_a, sl_b in (((slice(None), slice(None, -1)), (slice(None), slice(1, None))),
                       ((slice(None, -1), slice(None)), (slice(1, None), slice(None)))):
        a, b = near[sl_a], near[sl_b]
        m = sea[sl_a] & sea[sl_b] & (a != b) & (a > 0) & (b > 0)
        if not m.any():
            continue
        d = (dkm[sl_a] + dkm[sl_b])[m]
        x = np.minimum(a[m], b[m]).astype(np.int64)
        y = np.maximum(a[m], b[m]).astype(np.int64)
        key = x * 1_000_000 + y
        order = np.lexsort((d, key))
        key, d = key[order], d[order]
        first = np.r_[True, key[1:] != key[:-1]]
        for k, v in zip(key[first].tolist(), d[first].tolist()):
            kk = (k // 1_000_000, k % 1_000_000)
            if kk not in best or v < best[kk]:
                best[kk] = v
    return best


def connect_components(n, land_pairs, sea_cand, short_km):
    """Qisqa dengiz yo'llari + guruhlarni ulaydigan eng qisqa yo'llar (Kruskal). Natija: {(a,b): km}."""
    parent = list(range(n + 1))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for a, b in land_pairs:
        parent[find(a)] = find(b)
    chosen = {}
    for (a, b), d in sea_cand.items():
        if d <= short_km and (a, b) not in land_pairs:
            chosen[(a, b)] = d
            parent[find(a)] = find(b)
    for (a, b), d in sorted(sea_cand.items(), key=lambda t: t[1]):
        if find(a) != find(b):
            chosen[(a, b)] = d
            parent[find(a)] = find(b)
    return chosen


def normal_map(Z, scale=2, strength=0.012):
    """Relyefdan normal xarita (yarim o'lchamda): yorug'lik va soya uchun (shader)."""
    z = np.maximum(Z, -200.0)[::scale, ::scale].astype(np.float32)
    z = ndimage.gaussian_filter(z, 0.7)
    gy, gx = np.gradient(z)
    nx, ny, nz = -gx * strength, -gy * strength, np.ones_like(z)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([(nx / ln * 0.5 + 0.5), (ny / ln * 0.5 + 0.5), (nz / ln * 0.5 + 0.5)], -1)
    return (rgb * 255).astype(np.uint8)


def hsv_hex(h, s, v):
    import colorsys
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, s, v)
    return "#%02x%02x%02x" % (int(r * 255), int(g * 255), int(b * 255))
