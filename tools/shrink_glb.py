"""GLB ichidagi teksturalarni kichraytiradi (geometriya o'zgarmaydi): python tools/shrink_glb.py in.glb out.glb 2048
Rang teksturasi JPEG, qolganlari (normal, metall/g'adir-budurlik) PNG bo'lib qoladi."""
import io, json, struct, sys
from PIL import Image

src, dst, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
b = open(src, "rb").read()
jl = struct.unpack("<I", b[12:16])[0]
j = json.loads(b[20:20 + jl])
bin0 = 20 + jl + 8
color_imgs = {t["source"] for m in j.get("materials", []) for k in ["baseColorTexture"]
              if (t := j["textures"][m.get("pbrMetallicRoughness", {}).get(k, {}).get("index", -1)] if m.get("pbrMetallicRoughness", {}).get(k) else None)}
new_data = {}
for i, im in enumerate(j.get("images", [])):
    bv = j["bufferViews"][im["bufferView"]]
    o = bin0 + bv.get("byteOffset", 0)
    img = Image.open(io.BytesIO(b[o:o + bv["byteLength"]]))
    if max(img.size) > size:
        img = img.resize((size, size * img.size[1] // img.size[0]), Image.LANCZOS)
    out = io.BytesIO()
    if i in color_imgs:
        img.convert("RGB").save(out, "JPEG", quality=92)
        im["mimeType"] = "image/jpeg"
    else:
        img.save(out, "PNG", optimize=True)
        im["mimeType"] = "image/png"
    new_data[im["bufferView"]] = out.getvalue()
blob = bytearray()
for k, bv in enumerate(j["bufferViews"]):
    data = new_data.get(k)
    if data is None:
        o = bin0 + bv.get("byteOffset", 0)
        data = b[o:o + bv["byteLength"]]
    while len(blob) % 4:
        blob.append(0)
    bv["byteOffset"] = len(blob)
    bv["byteLength"] = len(data)
    blob += data
while len(blob) % 4:
    blob.append(0)
j["buffers"][0]["byteLength"] = len(blob)
js = json.dumps(j, separators=(",", ":")).encode()
js += b" " * ((4 - len(js) % 4) % 4)
with open(dst, "wb") as f:
    f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
    f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
    f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))
print(dst, len(js) + len(blob))
