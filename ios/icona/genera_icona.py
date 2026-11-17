"""Icona dell'app Re Mida: patch tattica a scudo, nero e oro, corona + ORO 16 + JSOC.
Scrive AppIcon 1024x1024 (senza trasparenza, come vuole iOS) nell'asset catalog e un'anteprima.

  py genera_icona.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 1024
QUI = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(QUI, "..", "HeltecNav", "Assets.xcassets", "AppIcon.appiconset")
GOLD = (154, 174, 91)
GOLD_D = (84, 100, 46)
FONT = r"C:\Windows\Fonts\bahnschrift.ttf"


def font(size, weight="Bold"):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def shield(cx, top, w, h):
    """Scudo: lati dritti, fondo a punta morbida."""
    pts = []
    x0, x1 = cx - w / 2, cx + w / 2
    pts += [(x0, top + 40), (cx - w * 0.18, top), (cx + w * 0.18, top), (x1, top + 40)]
    for i in range(0, 41):
        t = i / 40
        # lato destro che scende e curva verso la punta
        x = x1 - (w / 2) * (t ** 3.4)
        y = top + 40 + (h - 40) * t
        pts.append((x, y))
    for i in range(40, -1, -1):
        t = i / 40
        x = x0 + (w / 2) * (t ** 3.4)
        y = top + 40 + (h - 40) * t
        pts.append((x, y))
    return pts


def dashed(d, pts, on, off, color, width):
    """Tratteggio a passo costante lungo la spezzata."""
    carry, drawing = 0.0, True
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        seg = math.hypot(x1 - x0, y1 - y0)
        pos = 0.0
        while pos < seg:
            step = min((on if drawing else off) - carry, seg - pos)
            a, b = pos / seg, (pos + step) / seg
            if drawing:
                d.line([(x0 + (x1 - x0) * a, y0 + (y1 - y0) * a), (x0 + (x1 - x0) * b, y0 + (y1 - y0) * b)], fill=color, width=width)
            pos += step
            carry += step
            if carry >= (on if drawing else off) - 1e-6:
                carry, drawing = 0.0, not drawing


def crown(d, cx, cy, w, color):
    h = w * 0.55
    base = cy + h / 2
    top = cy - h / 2
    pts = [(cx - w / 2, base), (cx - w / 2, top + h * 0.35), (cx - w * 0.27, top + h * 0.62),
           (cx, top), (cx + w * 0.27, top + h * 0.62), (cx + w / 2, top + h * 0.35), (cx + w / 2, base)]
    d.polygon(pts, fill=color)
    d.rectangle([cx - w / 2, base + w * 0.05, cx + w / 2, base + w * 0.15], fill=color)
    for px, py in [(cx - w / 2, top + h * 0.35), (cx, top), (cx + w / 2, top + h * 0.35)]:
        r = w * 0.06
        d.ellipse([px - r, py - r, px + r, py + r], fill=color)


def main():
    img = Image.new("RGB", (S, S), (12, 12, 10))
    # trama tessuto leggera
    tex = Image.effect_noise((S, S), 18).convert("L")
    img = Image.composite(Image.new("RGB", (S, S), (22, 21, 18)), img, tex.point(lambda v: 60 if v > 140 else 0))
    d = ImageDraw.Draw(img)

    cx, top, w, h = S / 2, 100, 760, 830
    outer = shield(cx, top, w, h)
    d.polygon(outer, fill=GOLD_D)
    inner = shield(cx, top + 22, w - 44, h - 44)
    d.polygon(inner, fill=(18, 18, 15))
    # cucitura tratteggiata
    stitch = shield(cx, top + 44, w - 88, h - 88)
    dashed(d, stitch + [stitch[0]], 26, 16, GOLD, 6)

    # fascia JSOC in alto
    d.text((cx, top + 135), "JSOC", font=font(84), fill=GOLD, anchor="mm")
    d.line([(cx - 230, top + 192), (cx + 230, top + 192)], fill=GOLD_D, width=5)

    crown(d, cx, top + 290, 250, GOLD)

    d.text((cx, top + 500), "ORO", font=font(205), fill=GOLD, anchor="mm")
    d.text((cx, top + 655), "16", font=font(104), fill=(18, 18, 15), anchor="mm",
           stroke_width=6, stroke_fill=GOLD)

    # leggero rilievo
    glow = img.filter(ImageFilter.GaussianBlur(1.2))
    img = Image.blend(img, glow, 0.35)

    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, "AppIcon.png"))
    img.resize((256, 256), Image.LANCZOS).save(os.path.join(QUI, "anteprima.png"))
    with open(os.path.join(OUT, "Contents.json"), "w") as fh:
        fh.write('{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],'
                 '"info":{"author":"xcode","version":1}}')
    with open(os.path.join(OUT, "..", "Contents.json"), "w") as fh:
        fh.write('{"info":{"author":"xcode","version":1}}')
    print("ok", OUT)


if __name__ == "__main__":
    main()
