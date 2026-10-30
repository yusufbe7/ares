"""Texnika miniatyuralarini model chegarasi bo'yicha kesib, 640x400 kadrga markazlab joylaydi.
Ishga tushirish: python tools/crop_thumbs.py  (render_thumbs.gd dan keyin)"""
import glob
from PIL import Image

for f in glob.glob("ui/thumbs/*.png"):
    im = Image.open(f).convert("RGBA")
    box = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    if not box:
        continue
    im = im.crop(box)
    W, H = 640, 400
    s = min(W * 0.9 / im.width, H * 0.86 / im.height)
    im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.alpha_composite(im, ((W - im.width) // 2, (H - im.height) // 2))
    out.save(f)
    print("ok", f, im.size)
