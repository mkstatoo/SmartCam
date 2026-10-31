"""تنظیمات سرور؛ همه از متغیرهای محیطی خوانده می‌شوند (پیشوند DC_)."""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field


def _bool(v: str | None, default: bool) -> bool:
    if v is None:
        return default
    return v.strip().lower() in ("1", "true", "yes", "on")


@dataclass
class Settings:
    db_path: str = "data/detective.db"
    # کلید امضای کوکی ادمین. بدون آن پنل مدیریت غیرفعال می‌ماند.
    secret_key: str = ""
    admin_password: str = ""
    cookie_secure: bool = True
    trust_proxy: bool = False  # فقط پشت Nginx/Caddy خودتان روشن کنید

    package_name: str = "ir.detective.detective_camera"

    # سقف دستگاه برای هر حساب
    free_max_devices: int = 2
    pro_max_devices: int = 4

    # محدودیت‌هایی که به برنامه اعلام می‌شود (بدون نیاز به آپدیت اپ قابل تغییرند)
    free_max_cameras: int = 2
    free_max_events: int = 20
    pro_max_events: int = 300
    # اگر برنامه این مدت با سرور تماس نگیرد، مجوز «پرو» موقتاً غیرفعال می‌شود.
    # (قطع اینترنت در ایران رایج است؛ پس مقدار بلند است.)
    offline_grace_days: int = 30

    # شناسهٔ محصول -> مدت اعتبار به روز (None یعنی دائمی)
    products: dict = field(default_factory=lambda: {"pro_lifetime": None})

    # اعتبارسنجی خرید در سرور فروشگاه‌ها
    bazaar_access_token: str = ""
    myket_access_token: str = ""
    # فقط برای توسعه/تست: توکن‌هایی که با TEST- شروع شوند بدون فروشگاه پذیرفته می‌شوند.
    allow_test_purchases: bool = False

    @staticmethod
    def from_env() -> "Settings":
        e = os.environ.get
        s = Settings()
        s.db_path = e("DC_DB_PATH", s.db_path)
        s.secret_key = e("DC_SECRET_KEY", "")
        s.admin_password = e("DC_ADMIN_PASSWORD", "")
        s.cookie_secure = _bool(e("DC_COOKIE_SECURE"), True)
        s.trust_proxy = _bool(e("DC_TRUST_PROXY"), False)
        s.package_name = e("DC_PACKAGE_NAME", s.package_name)
        s.free_max_devices = int(e("DC_FREE_MAX_DEVICES", s.free_max_devices))
        s.pro_max_devices = int(e("DC_PRO_MAX_DEVICES", s.pro_max_devices))
        s.free_max_cameras = int(e("DC_FREE_MAX_CAMERAS", s.free_max_cameras))
        s.free_max_events = int(e("DC_FREE_MAX_EVENTS", s.free_max_events))
        s.pro_max_events = int(e("DC_PRO_MAX_EVENTS", s.pro_max_events))
        s.offline_grace_days = int(e("DC_OFFLINE_GRACE_DAYS", s.offline_grace_days))
        if e("DC_PRODUCTS"):
            s.products = json.loads(e("DC_PRODUCTS"))
        s.bazaar_access_token = e("DC_BAZAAR_ACCESS_TOKEN", "")
        s.myket_access_token = e("DC_MYKET_ACCESS_TOKEN", "")
        s.allow_test_purchases = _bool(e("DC_ALLOW_TEST_PURCHASES"), False)
        return s
