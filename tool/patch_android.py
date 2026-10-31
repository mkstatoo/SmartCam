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

# minSdk = 24 + core library desugaring (لازم برای flutter_local_notifications)
DESUGAR = "com.android.tools:desugar_jdk_libs:2.1.4"
done = False
for name in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    g = root / name
    if not g.exists():
        continue
    kts = name.endswith(".kts")
    s = g.read_text(encoding="utf-8")
    orig = s
    s = re.sub(r"minSdk(Version)?\s*=?\s*(flutter\.minSdkVersion|\d+)",
               "minSdk = 24" if kts else "minSdkVersion 24", s)
    flag = "isCoreLibraryDesugaringEnabled = true" if kts else "coreLibraryDesugaringEnabled true"
    if "ibraryDesugaringEnabled" not in s:
        s = re.sub(r"(compileOptions\s*\{)", lambda m: m.group(1) + "\n        " + flag, s, count=1)
    if "coreLibraryDesugaring(" not in s and "coreLibraryDesugaring '" not in s:
        dep = (f'\ndependencies {{\n    coreLibraryDesugaring("{DESUGAR}")\n}}\n' if kts
               else f"\ndependencies {{\n    coreLibraryDesugaring '{DESUGAR}'\n}}\n")
        s += dep
    if s != orig:
        g.write_text(s, encoding="utf-8")
        done = True
print("manifest patched; gradle patched:", done)

# پلاگین‌هایی که با compileSdk قدیمی ساخته شده‌اند (مثل vibration) با وابستگی‌های
# جدید androidx ناسازگارند؛ compileSdk همهٔ زیرپروژه‌ها (جز app) را بالا می‌بریم.
SUB_KTS = """
// --- Detective Camera: compileSdk 35 for plugin subprojects ---
subprojects {
    if (project.name != "app") {
        afterEvaluate {
            extensions.findByName("android")?.withGroovyBuilder { "compileSdkVersion"(35) }
        }
    }
}
// --- end ---

"""
SUB_GROOVY = """
// --- Detective Camera: compileSdk 35 for plugin subprojects ---
subprojects {
    if (project.name != 'app') {
        afterEvaluate { p ->
            if (p.hasProperty('android')) { p.android { compileSdkVersion 35 } }
        }
    }
}
// --- end ---

"""
for name in ("android/build.gradle.kts", "android/build.gradle"):
    g = root / name
    if not g.exists():
        continue
    s = g.read_text(encoding="utf-8")
    if "Detective Camera: compileSdk" in s:
        continue
    block = SUB_KTS if name.endswith(".kts") else SUB_GROOVY
    # باید قبل از اولین `subprojects {` بیاید (پیش از evaluationDependsOn)
    m = re.search(r"^subprojects\s*\{", s, flags=re.M)
    s = s[: m.start()] + block.lstrip("\n") + s[m.start():] if m else s + block
    g.write_text(s, encoding="utf-8")
    print("root gradle patched:", name)
