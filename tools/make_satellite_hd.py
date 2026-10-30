"""Yaqinlashganda yer aniq ko'rinishi uchun yuqori aniqlikdagi sun'iy yo'ldosh rasmi.
Manba: NASA Blue Marble Next Generation, avgust 2004, 21600x10800 (public domain):
  https://eoimages.gsfc.nasa.gov/images/imagerecords/74000/74117/world.200408.3x21600x10800.jpg
Xarita qamroviga (data/map_meta.json: lat 84..-58) kesib, 16384 kenglikka (Godot teksturasi chegarasi) keltiradi.
Ishga tushirish: python tools/make_satellite_hd.py <bluemarble.jpg>   ->  map/satellite_hd.jpg"""
import json, sys
from PIL import Image

Image.MAX_IMAGE_PIXELS = None
meta = json.load(open("data/map_meta.json"))
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
top = (90 - meta["lat_max"]) / 180 * h
bot = (90 - meta["lat_min"]) / 180 * h
W = 16384
H = int(round(W * (bot - top) / w / 2) * 2)
out = im.resize((W, H), Image.LANCZOS, box=(0, top, w, bot))
out.save("map/satellite_hd.jpg", quality=90, optimize=True)
print("map/satellite_hd.jpg", out.size)
