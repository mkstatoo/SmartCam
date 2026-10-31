#!/usr/bin/env python3
"""بعد از `flutter create .` تنظیمات لازم اندروید را خودکار اعمال می‌کند:

  - مجوزها، http ساده برای دوربین‌های IP، سرویس پیش‌زمینه، نام فارسی برنامه
  - حذف مجوزهای محدودشدهٔ گوگل‌پلی (معافیت باتری، اجرای خودکار بعد از بوت)
  - minSdk = 24، core library desugaring، compileSdk ۳۵ برای پلاگین‌ها
  - امضای release از android/key.properties (در نبود آن، امضای debug)

اجرای چندبارهٔ آن بی‌خطر است (idempotent).
استفاده:  python3 tool/patch_android.py [مسیر پروژه]
"""
import re
import sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
manifest = root / "android/app/src/main/AndroidManifest.xml"

APP_LABEL = "کارآگاه دوربین"

PERMS = [
    "INTERNET", "ACCESS_NETWORK_STATE", "ACCESS_WIFI_STATE",
    "CHANGE_WIFI_MULTICAST_STATE", "CAMERA", "WAKE_LOCK", "VIBRATE",
    "POST_NOTIFICATIONS", "USE_FULL_SCREEN_INTENT", "FOREGROUND_SERVICE",
    "FOREGROUND_SERVICE_CAMERA", "FOREGROUND_SERVICE_DATA_SYNC",
]
# مجوزهایی که حتی اگر پلاگینی اضافه‌شان کند باید از مانیفست نهایی حذف شوند
# (در گوگل‌پلی «محدود» هستند و نیاز به توجیه‌نامه دارند؛ برنامه به آن‌ها نیاز ندارد).
REMOVE_PERMS = [
    "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
    "RECEIVE_BOOT_COMPLETED",
]
SERVICE = (
    '<service android:name="com.pravera.flutter_foreground_task.service.ForegroundService" '
    'android:foregroundServiceType="dataSync|camera" android:exported="false"/>'
)
TOOLS_NS = 'xmlns:tools="http://schemas.android.com/tools"'

text = manifest.read_text(encoding="utf-8")

# فضای نام tools برای tools:node="remove"
if TOOLS_NS not in text:
    text = text.replace("<manifest", f"<manifest {TOOLS_NS}", 1)

# مجوزها (فقط آن‌هایی که نیستند)، درست قبل از <application
missing = [p for p in PERMS if f'android.permission.{p}"' not in text]
block = "".join(f'    <uses-permission android:name="android.permission.{p}"/>\n' for p in missing)
rm_missing = [p for p in REMOVE_PERMS if f'android.permission.{p}" tools:node="remove"' not in text]
block += "".join(
    f'    <uses-permission android:name="android.permission.{p}" tools:node="remove"/>\n'
    for p in rm_missing
)
if block:
    text = re.sub(r"(\s*)<application", lambda m: "\n" + block + "    <application", text, count=1)

# http ساده
if "usesCleartextTraffic" not in text:
    text = text.replace("<application", '<application android:usesCleartextTraffic="true"', 1)

# نام برنامه
text = re.sub(r'(<application[^>]*?android:label=")[^"]*(")',
              lambda m: m.group(1) + APP_LABEL + m.group(2), text, count=1, flags=re.S)

# سرویس پیش‌زمینه
if "ForegroundService" not in text:
    text = text.replace("</application>", f"    {SERVICE}\n    </application>", 1)

manifest.write_text(text, encoding="utf-8")

# ---------------------------------------------------------------------------
# build.gradle(.kts) برنامه: minSdk، desugaring، امضا
# ---------------------------------------------------------------------------
DESUGAR = "com.android.tools:desugar_jdk_libs:2.1.4"

KTS_PROPS = '''val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

'''
KTS_SIGNING = '''    signingConfigs {
        create("release") {
            if (keystoreProperties.containsKey("storeFile")) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

'''
GROOVY_PROPS = '''def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

'''
GROOVY_SIGNING = '''    signingConfigs {
        release {
            if (keystoreProperties['storeFile']) {
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
                storeFile file(keystoreProperties['storeFile'])
                storePassword keystoreProperties['storePassword']
            }
        }
    }

'''

done = False
for name in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    g = root / name
    if not g.exists():
        continue
    kts = name.endswith(".kts")
    s = g.read_text(encoding="utf-8")
    orig = s

    # minSdk
    s = re.sub(r"minSdk(Version)?\s*=?\s*(flutter\.minSdkVersion|\d+)",
               "minSdk = 24" if kts else "minSdkVersion 24", s)

    # desugaring
    flag = "isCoreLibraryDesugaringEnabled = true" if kts else "coreLibraryDesugaringEnabled true"
    if "ibraryDesugaringEnabled" not in s:
        s = re.sub(r"(compileOptions\s*\{)", lambda m: m.group(1) + "\n        " + flag, s, count=1)
    if "coreLibraryDesugaring(" not in s and "coreLibraryDesugaring '" not in s:
        dep = (f'\ndependencies {{\n    coreLibraryDesugaring("{DESUGAR}")\n}}\n' if kts
               else f"\ndependencies {{\n    coreLibraryDesugaring '{DESUGAR}'\n}}\n")
        s += dep

    # امضای release
    if "keystoreProperties" not in s:
        if kts:
            s = "import java.io.FileInputStream\nimport java.util.Properties\n\n" + s
            s = re.sub(r"^android\s*\{", lambda m: KTS_PROPS + "android {", s, count=1, flags=re.M)
            s = re.sub(r"^(\s*)buildTypes\s*\{", lambda m: KTS_SIGNING + m.group(1) + "buildTypes {",
                       s, count=1, flags=re.M)
            s = s.replace(
                'signingConfig = signingConfigs.getByName("debug")',
                'signingConfig = if (keystoreProperties.containsKey("storeFile")) '
                'signingConfigs.getByName("release") else signingConfigs.getByName("debug")')
        else:
            s = re.sub(r"^android\s*\{", lambda m: GROOVY_PROPS + "android {", s, count=1, flags=re.M)
            s = re.sub(r"^(\s*)buildTypes\s*\{", lambda m: GROOVY_SIGNING + m.group(1) + "buildTypes {",
                       s, count=1, flags=re.M)
            s = s.replace(
                "signingConfig signingConfigs.debug",
                "signingConfig keystoreProperties['storeFile'] ? signingConfigs.release : signingConfigs.debug")

    if s != orig:
        g.write_text(s, encoding="utf-8")
        done = True
print("manifest patched; app gradle patched:", done)

# ---------------------------------------------------------------------------
# پلاگین‌هایی که با compileSdk قدیمی ساخته شده‌اند (مثل vibration) با وابستگی‌های
# جدید androidx ناسازگارند؛ compileSdk همهٔ زیرپروژه‌ها (جز app) را بالا می‌بریم.
# ---------------------------------------------------------------------------
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
