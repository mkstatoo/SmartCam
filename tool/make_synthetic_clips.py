#!/usr/bin/env python3
"""تولید کلیپ‌های «مصنوعی» فقط برای آزمودن خودِ ابزار ارزیابی (harness).

هشدار: نتیجهٔ این کلیپ‌ها هیچ ربطی به دقت واقعی روی آتش/دود واقعی ندارد.
دقت واقعی فقط با ویدیوهای خود شما سنجیده می‌شود.

استفاده: python3 tool/make_synthetic_clips.py OUT_DIR
"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

W, H, FPS = 320, 240, 10
rng = np.random.default_rng(7)  # بذر ثابت = تکرارپذیر


def bg(n):
    base = np.full((H, W, 3), (90, 95, 100), np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    base += (np.sin(xx / 17.0) * 6 + np.cos(yy / 23.0) * 6)[..., None]
    return base


def render(path, seconds, draw):
    p = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-c:v", "libx264",
         "-pix_fmt", "yuv420p", "-crf", "18", str(path)],
        stdin=subprocess.PIPE)
    base = bg(0)
    for i in range(int(seconds * FPS)):
        t = i / FPS
        f = base.copy()
        f += rng.normal(0, 1.5, f.shape)  # نویز سنسور
        f = draw(f, t)
        p.stdin.write(np.clip(f, 0, 255).astype(np.uint8).tobytes())
    p.stdin.close()
    assert p.wait() == 0


def box(f, cx, cy, w, h, color):
    x0, x1 = max(0, int(cx - w / 2)), min(W, int(cx + w / 2))
    y0, y1 = max(0, int(cy - h / 2)), min(H, int(cy + h / 2))
    if x1 > x0 and y1 > y0:
        f[y0:y1, x0:x1] = color


def flame(f, t):
    # شعلهٔ سوسوزن: بالای صفحه زرد، پایین نارنجی، مرز و ارتفاع در حال تغییر
    cx = 160 + 4 * np.sin(t * 7)
    for k in range(12):
        hh = 70 + 30 * np.sin(t * 9 + k) + rng.normal(0, 8)
        ww = 40 - k * 2.2 + 6 * np.sin(t * 13 + k * 2)
        col = (255, 90 + k * 12 + rng.integers(-20, 20), 20 + k * 4)
        box(f, cx + rng.normal(0, 3), 200 - k * 6, ww, hh * (1 - k / 14), col)
    return f


def moving(color):
    def d(f, t):
        box(f, 40 + (t * 25) % 240, 120 + 30 * np.sin(t), 40, 70, color)
        return f
    return d


def main():
    out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
    clips = []

    def add(name, secs, draw, events, note):
        render(out / f"{name}.mp4", secs, draw)
        clips.append({"path": f"{name}.mp4", "note": "SYNTHETIC: " + note,
                      "events": events})

    add("neg_static", 90, lambda f, t: f, [], "صحنهٔ ثابت با نویز، بدون رویداد")
    add("neg_lighting", 90,
        lambda f, t: f * (1 + 0.5 * min(1, max(0, (t - 20) / 5))
                          - 0.5 * min(1, max(0, (t - 60) / 5))),
        [], "تغییر ناگهانی روشنایی کل صحنه (باید حرکت حساب نشود)")

    def static_orange(f, t):
        box(f, 220, 150, 50, 60, (240, 120, 30)); return f
    add("neg_static_orange", 90, static_orange, [],
        "جسم نارنجی ثابت (نباید آتش حساب شود)")

    add("neg_moving_orange", 90,
        lambda f, t: moving((240, 120, 30))(f, t) if 20 <= t < 50 else f,
        [{"type": "motion", "start": 20, "end": 50}],
        "جسم نارنجی در حال حرکت: حرکت واقعی، آتش نیست")

    add("pos_motion", 90,
        lambda f, t: moving((30, 40, 160))(f, t) if 20 <= t < 50 else f,
        [{"type": "motion", "start": 20, "end": 50}],
        "جسم آبی در حال حرکت")

    add("pos_flame", 90,
        lambda f, t: flame(f, t) if 20 <= t < 60 else f,
        [{"type": "fire", "start": 20, "end": 60}],
        "شعلهٔ مصنوعی سوسوزن (فقط برای راستی‌آزمایی ابزار)")

    (out / "manifest.json").write_text(
        json.dumps({"analysis_fps": 2, "videos": clips}, ensure_ascii=False, indent=2),
        encoding="utf-8")
    print("ok:", out / "manifest.json")


main()
