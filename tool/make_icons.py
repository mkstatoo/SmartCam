#!/usr/bin/env python3
"""آیکون برنامه را تولید می‌کند (طرح اصلی: عدسی دوربین با شعله در مرکز).

خروجی‌ها (در مخزن ذخیره می‌شوند تا CI به PIL نیاز نداشته باشد):
  assets/icon/icon.png     آیکون کامل ۱۰۲۴×۱۰۲۴ (با پس‌زمینه)
  assets/icon/icon_fg.png  لایهٔ جلوی آیکون تطبیقی اندروید (پس‌زمینهٔ شفاف)

اجرا: python3 tool/make_icons.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "icon"
OUT.mkdir(parents=True, exist_ok=True)

BG = (20, 22, 27, 255)          # #14161B
RING = (232, 89, 12, 255)       # نارنجی برنامه
RING_DARK = (150, 52, 6, 255)
LENS = (11, 12, 15, 255)
FLAME_OUT = (255, 122, 24, 255)
FLAME_MID = (255, 176, 40, 255)
FLAME_IN = (255, 233, 140, 255)

SS = 2  # سوپرسمپلینگ برای لبه‌های نرم


def quad(p0, c, p1, n=24):
    pts = []
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t ** 2 * p1[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t ** 2 * p1[1]
        pts.append((x, y))
    return pts


def flame(d, cx, cy, h, color):
    """شعله: یک دایره در پایین + نوک خمیده در بالا. h = ارتفاع کل."""
    r = h * 0.30
    circ_cy = cy + h * 0.5 - r
    tip = (cx + h * 0.04, cy - h * 0.5)
    left = (cx - r, circ_cy)
    right = (cx + r, circ_cy)
    d.ellipse([cx - r, circ_cy - r, cx + r, circ_cy + r], fill=color)
    pts = quad(left, (cx - r * 0.95, circ_cy - h * 0.38), tip)
    pts += quad(tip, (cx + r * 1.15, circ_cy - h * 0.30), right)
    d.polygon(pts, fill=color)


def draw(with_bg: bool, scale: float) -> Image.Image:
    S = 1024 * SS
    img = Image.new("RGBA", (S, S), BG if with_bg else (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2
    R = S * 0.5 * scale  # شعاع بیرونی عدسی

    # حلقهٔ بیرونی (با لبهٔ تیره برای عمق)
    d.ellipse([c - R, c - R, c + R, c + R], fill=RING_DARK)
    d.ellipse([c - R * 0.975, c - R * 0.975, c + R * 0.975, c + R * 0.975], fill=RING)
    # بدنهٔ عدسی
    r2 = R * 0.80
    d.ellipse([c - r2, c - r2, c + r2, c + r2], fill=LENS)
    r3 = R * 0.66
    d.ellipse([c - r3, c - r3, c + r3, c + r3], outline=(40, 44, 52, 255), width=int(S * 0.006))

    # شعله (سه لایه)
    h = R * 1.05
    flame(d, c, c + R * 0.03, h, FLAME_OUT)
    flame(d, c, c + R * 0.10, h * 0.68, FLAME_MID)
    flame(d, c + R * 0.01, c + R * 0.17, h * 0.38, FLAME_IN)

    # بازتاب نور روی شیشه
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([c - R * 0.55, c - R * 0.62, c - R * 0.12, c - R * 0.30], fill=(255, 255, 255, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.006))
    img = Image.alpha_composite(img, glow)

    return img.resize((1024, 1024), Image.LANCZOS)


# آیکون کامل: عدسی بزرگ‌تر؛ لایهٔ تطبیقی: داخل ناحیهٔ امن ۶۶٪
draw(True, 0.78).save(OUT / "icon.png")
draw(False, 0.58).save(OUT / "icon_fg.png")
print("written:", sorted(p.name for p in OUT.iterdir()))
