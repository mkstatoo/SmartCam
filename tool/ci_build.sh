#!/usr/bin/env bash
# اجرای یک دستور flutter با لاگ‌گرفتن؛ در صورت خطا بلوک خطای Gradle را به‌صورت
# annotation چاپ می‌کند (لاگ کامل Actions از این محیط قابل دانلود نیست).
#
# استفاده:  tool/ci_build.sh <برچسب> <آرگومان‌های flutter...>
#   مثال:   tool/ci_build.sh apk build apk --release
set -u
label="$1"; shift
log="build_${label}.log"

set +e
flutter "$@" 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
set -e

if [ "$code" -ne 0 ]; then
  echo "::error::[$label] flutter $* failed with exit code $code"
  if grep -q "What went wrong" "$log"; then
    sed -n '/What went wrong/,/\* Try/p' "$log" | head -12 | cut -c1-380 \
      | while IFS= read -r l; do echo "::error::$l"; done
  else
    tail -n 8 "$log" | cut -c1-380 | while IFS= read -r l; do echo "::error::$l"; done
  fi
fi
exit "$code"
