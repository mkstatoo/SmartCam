#!/usr/bin/env python3
"""بررسی خروجی‌های ساخت و چاپ نتیجه به‌صورت annotation (::notice::) در GitHub Actions.

برای هر APK:
  - اندازه
  - امضا با apksigner (و هشدار اگر با کلید debug امضا شده باشد)
  - هم‌ترازی ELF کتابخانه‌های بومی ۶۴بیتی برای صفحهٔ ۱۶ کیلوبایتی (الزام گوگل‌پلی
    برای برنامه‌هایی که Android 15+ را هدف می‌گیرند)

استفاده:  python3 tool/check_apk.py dist/*.apk
متغیر SIGNING=release → اگر APK با کلید debug امضا شده باشد، با خطا خارج می‌شود.
"""
import glob
import os
import re
import struct
import subprocess
import sys
import zipfile

PAGE_16K = 16384


def notice(msg, level="notice"):
    print(f"::{level}::{msg}")


def find_apksigner():
    home = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or ""
    cands = sorted(glob.glob(os.path.join(home, "build-tools", "*", "apksigner")))
    return cands[-1] if cands else None


def elf_load_aligns(data):
    """مقدار p_align قطعه‌های PT_LOAD را برمی‌گرداند (فقط ELF ۶۴بیتی little-endian)."""
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        return None
    phoff = struct.unpack_from("<Q", data, 0x20)[0]
    phentsize, phnum = struct.unpack_from("<HH", data, 0x36)
    out = []
    for i in range(phnum):
        off = phoff + i * phentsize
        p_type = struct.unpack_from("<I", data, off)[0]
        if p_type == 1:  # PT_LOAD
            out.append(struct.unpack_from("<Q", data, off + 48)[0])
    return out


def check_alignment(apk):
    bad, good, skipped = [], 0, 0
    with zipfile.ZipFile(apk) as z:
        for info in z.infolist():
            m = re.match(r"lib/(arm64-v8a|x86_64)/.+\.so$", info.filename)
            if not m:
                if info.filename.endswith(".so"):
                    skipped += 1  # ABI ۳۲بیتی: الزام ۱۶ کیلوبایتی ندارد
                continue
            aligns = elf_load_aligns(z.read(info))
            if aligns is None:
                continue
            if aligns and min(aligns) < PAGE_16K:
                bad.append(f"{info.filename} (p_align={min(aligns)})")
            else:
                good += 1
    return good, bad, skipped


def main(paths):
    signer = find_apksigner()
    want_release = os.environ.get("SIGNING") == "release"
    failed = False
    for apk in paths:
        name = os.path.basename(apk)
        size_mb = os.path.getsize(apk) / 1048576
        notice(f"{name}: {size_mb:.1f} MB")

        if apk.endswith(".apk") and signer:
            r = subprocess.run([signer, "verify", "--print-certs", apk],
                               capture_output=True, text=True)
            out = r.stdout + r.stderr
            dn = re.search(r"certificate DN: (.+)", out)
            sha = re.search(r"SHA-256 digest: (\w+)", out)
            ok = r.returncode == 0
            notice(f"{name}: signature {'OK' if ok else 'INVALID'}; "
                   f"signer={dn.group(1) if dn else '?'}; "
                   f"sha256={(sha.group(1)[:16] + '…') if sha else '?'}")
            if not ok:
                failed = True
            if dn and "Android Debug" in dn.group(1):
                notice(f"{name}: signed with the DEBUG key (not publishable)", "warning")
                if want_release:
                    failed = True

        if apk.endswith(".apk"):
            good, bad, skipped = check_alignment(apk)
            if bad:
                notice(f"{name}: 16KB page-size check: {len(bad)} native lib(s) NOT aligned, "
                       f"{good} ok → " + "; ".join(bad[:5]), "warning")
            else:
                notice(f"{name}: 16KB page-size check: all {good} 64-bit native libs aligned"
                       + (f" ({skipped} 32-bit libs skipped)" if skipped else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
