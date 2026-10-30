"""Okean animatsiyasini pishirish (bake): "Free Ocean simulation - Tiled" (the9thearl, CC-BY-4.0,
https://sketchfab.com/3d-models/free-ocean-simulation-tiled-ec999170128341a29dfe6d75878e2303).
GLB dagi markaziy suv bo'lagi 145x145 to'r, 249 kadr (morph target), 50x50 m, chetlari chok bermay takrorlanadi.
Har ikkinchi kadr olinadi (124 kadr) va atlas teksturaga yoziladi:
  map/ocean_disp.png    RGB = to'lqin siljishi (dx, dy, dz), oralig'i data/ocean.json da
  map/ocean_normal.png  RG = normal (x, z), B = ko'pik (to'lqin cho'qqisi: suv siqilgan joy, Jacobian < 1)
  map/ocean_color.jpg   GLB dagi suv rangi / ko'pik teksturasi (2048)
Har kadr 144x144 + 1 piksel chegara (bilinear filtr qo'shni kadrga o'tmasin), atlas 12 x 11.
Ishga tushirish: python tools/bake_ocean.py <free_ocean_simulation-tiled.glb>"""
import io, json, sys
import numpy as np
from PIL import Image
from glbread import GLB

N_GRID = 144
COLS = 12
STEP = 2
g = GLB(sys.argv[1])
p = g.j["meshes"][0]["primitives"][0]
uv = g.acc(p["attributes"]["TEXCOORD_0"])
pos = g.acc(p["attributes"]["POSITION"]).astype(np.float64)
grid = np.c_[50 * uv[:, 0] - 25, np.zeros(len(uv)), 25 - 50 * uv[:, 1]]
iu = np.rint(uv[:, 0] * N_GRID).astype(int)
iv = np.rint(uv[:, 1] * N_GRID).astype(int)
ok = (iu < N_GRID) & (iv < N_GRID)                    # oxirgi qator/ustun = birinchisi (takrorlanadi)
total = len(p["targets"])                              # 248 target + dam holat = 249 kadr (249-kadr = 0-kadr)
frames = list(range(0, total, STEP))
disp = np.zeros((len(frames), N_GRID, N_GRID, 3), np.float32)
for k, f in enumerate(frames):
    P = pos.copy()
    if f > 0:
        P += g.acc(p["targets"][f - 1]["POSITION"])
    d = P - grid
    disp[k, iv[ok], iu[ok]] = d[ok]
lo = disp.reshape(-1, 3).min(0)
hi = disp.reshape(-1, 3).max(0)
# normal va ko'pik: siljigan to'r nuqtalari bo'yicha (davriy chegara bilan)
h = 50.0 / N_GRID
nrm = np.zeros((len(frames), N_GRID, N_GRID, 3), np.float32)
for k in range(len(frames)):
    X = disp[k, :, :, 0] + np.arange(N_GRID)[None, :] * h
    Y = disp[k, :, :, 1]
    Z = disp[k, :, :, 2] - np.arange(N_GRID)[:, None] * h        # v o'qi -z tomonga
    def dd(a, ax):
        b = np.roll(a, -1, ax) - np.roll(a, 1, ax)
        if a is X and ax == 1: b = np.where(np.abs(b) > 25, b - np.sign(b) * 50, b)
        if a is Z and ax == 0: b = np.where(np.abs(b) > 25, b - np.sign(b) * 50, b)
        return b
    du = np.stack([dd(X, 1), dd(Y, 1), dd(Z, 1)], -1)
    dv = np.stack([dd(X, 0), dd(Y, 0), dd(Z, 0)], -1)
    n = np.cross(dv, du)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    n *= np.sign(n[..., 1:2])
    jac = (du[..., 0] * -dv[..., 2] - du[..., 2] * -dv[..., 0]) / (2 * h) ** 2
    foam = np.clip((1.0 - jac) * 2.2, 0, 1)
    nrm[k] = np.stack([n[..., 0] * 0.5 + 0.5, n[..., 2] * 0.5 + 0.5, foam], -1)

def atlas(arr, norm):
    rows = (len(arr) + COLS - 1) // COLS
    c = N_GRID + 2
    out = np.zeros((rows * c, COLS * c, 3), np.uint8)
    for k, a in enumerate(arr):
        v = np.clip(norm(a), 0, 1)
        v = np.pad(v, ((1, 1), (1, 1), (0, 0)), mode="wrap")        # chegara: chok bermasin
        r, cc = divmod(k, COLS)
        out[r * c:(r + 1) * c, cc * c:(cc + 1) * c] = np.rint(v * 255)
    return out

Image.fromarray(atlas(disp, lambda a: (a - lo) / (hi - lo))).save("map/ocean_disp.png", optimize=True)
Image.fromarray(atlas(nrm, lambda a: a)).save("map/ocean_normal.png", optimize=True)
im = g.j["images"][0]; bv = g.j["bufferViews"][im["bufferView"]]
o = g.bin0 + bv.get("byteOffset", 0)
Image.open(io.BytesIO(g.b[o:o + bv["byteLength"]])).convert("RGB").resize((2048, 2048), Image.LANCZOS).save("map/ocean_color.jpg", quality=90)
meta = {"_note": "tools/bake_ocean.py natijasi. Manba: Free Ocean simulation - Tiled, the9thearl, CC-BY-4.0.",
        "frames": len(frames), "cols": COLS, "grid": N_GRID, "fps": 24.0 / STEP, "tile_m": 50.0,
        "disp_min": [float(x) for x in lo], "disp_max": [float(x) for x in hi]}
json.dump(meta, open("data/ocean.json", "w"), indent=1)
print(meta)
