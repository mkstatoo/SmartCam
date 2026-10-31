#!/usr/bin/env python3
"""بعد از `flutter create .` تنظیمات لازم اندروید را خودکار اعمال می‌کند:
مجوزها، http ساده برای دوربین‌های IP، سرویس پیش‌زمینه و minSdk = 24.

استفاده:  python3 tool/patch_android.py [مسیر پروژه]
"""
import re
import sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
manifest = root / "android/app/src/main/AndroidManifest.xml"

PERMS = [
    "INTERNET", "ACCESS_NETWORK_STATE", "ACCESS_WIFI_STATE",
    "CHANGE_WIFI_MULTICAST_STATE", "CAMERA", "WAKE_LOCK", "VIBRATE",
    "POST_NOTIFICATIONS", "USE_FULL_SCREEN_INTENT", "FOREGROUND_SERVICE",
    "FOREGROUND_SERVICE_CAMERA", "FOREGROUND_SERVICE_DATA_SYNC",
    "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
]
SERVICE = (
    '<service android:name="com.pravera.flutter_foreground_task.service.ForegroundService" '
    'android:foregroundServiceType="dataSync|camera" android:exported="false"/>'
)

text = manifest.read_text(encoding="utf-8")

# مجوزها (فقط آن‌هایی که نیستند)، درست قبل از <application
missing = [p for p in PERMS if f"android.permission.{p}" not in text]
block = "".join(f'    <uses-permission android:name="android.permission.{p}"/>\n' for p in missing)
if block:
    text = re.sub(r"(\s*)<application", lambda m: "\n" + block + "    <application", text, count=1)

# http ساده
if "usesCleartextTraffic" not in text:
    text = text.replace("<application", '<application android:usesCleartextTraffic="true"', 1)

# سرویس پیش‌زمینه
if "ForegroundService" not in text:
    text = text.replace("</application>", f"    {SERVICE}\n    </application>", 1)

manifest.write_text(text, encoding="utf-8")

# minSdk = 24 (build.gradle یا build.gradle.kts)
done = False
for name in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    g = root / name
    if not g.exists():
        continue
    s = g.read_text(encoding="utf-8")
    s2 = re.sub(r"minSdk(Version)?\s*=?\s*(flutter\.minSdkVersion|\d+)", "minSdk = 24" if name.endswith(".kts") else "minSdkVersion 24", s)
    if s2 != s:
        g.write_text(s2, encoding="utf-8")
        done = True
print("manifest patched; minSdk patched:", done)
