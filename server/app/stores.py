"""اعتبارسنجی خرید درون‌برنامه‌ای در سرور بازار و مایکت.

مهم: آدرس‌ها و روش احراز هویت زیر بر اساس مستندات عمومی هر فروشگاه نوشته شده و
در این محیط با سرور واقعی آن‌ها آزمایش نشده است. پیش از انتشار با یک خرید آزمایشی
واقعی صحت‌شان را بررسی کنید (SERVER.md).
"""
from __future__ import annotations

import httpx

from .config import Settings


class PurchaseRejected(Exception):
    """فروشگاه خرید را نمی‌شناسد یا لغو/بازپرداخت‌شده است."""


class StoreUnavailable(Exception):
    """اتصال به فروشگاه ممکن نشد یا تنظیمات سرور کامل نیست (نباید به کاربر مجوز داد/نداد)."""


def verify_purchase(
    s: Settings, http: httpx.Client, store: str, product_id: str, token: str
) -> None:
    if token.startswith("TEST-") and s.allow_test_purchases:
        return
    if store == "bazaar":
        _bazaar(s, http, product_id, token)
    elif store == "myket":
        _myket(s, http, product_id, token)
    else:
        raise PurchaseRejected("فروشگاه پشتیبانی نمی‌شود")


def _bazaar(s: Settings, http: httpx.Client, product_id: str, token: str) -> None:
    if not s.bazaar_access_token:
        raise StoreUnavailable("DC_BAZAAR_ACCESS_TOKEN تنظیم نشده است")
    url = (
        "https://pardakht.cafebazaar.ir/devapi/v2/api/validate/"
        f"{s.package_name}/inapp/{product_id}/purchases/{token}/"
    )
    try:
        r = http.get(url, params={"access_token": s.bazaar_access_token}, timeout=15)
    except httpx.HTTPError as e:
        raise StoreUnavailable(f"bazaar: {e.__class__.__name__}") from e
    if r.status_code == 404:
        raise PurchaseRejected("خرید در بازار پیدا نشد")
    if r.status_code in (401, 403):
        raise StoreUnavailable("توکن دسترسی بازار نامعتبر است")
    if r.status_code != 200:
        raise StoreUnavailable(f"bazaar HTTP {r.status_code}")
    data = _json(r)
    if "error" in data:
        if data.get("error") == "not_found":
            raise PurchaseRejected("خرید در بازار پیدا نشد")
        raise StoreUnavailable(f"bazaar: {data.get('error')}")
    # purchaseState: 0 خرید موفق، 1 لغو/بازپرداخت
    if int(data.get("purchaseState", 0)) != 0:
        raise PurchaseRejected("خرید لغو یا بازپرداخت شده است")


def _myket(s: Settings, http: httpx.Client, product_id: str, token: str) -> None:
    if not s.myket_access_token:
        raise StoreUnavailable("DC_MYKET_ACCESS_TOKEN تنظیم نشده است")
    url = (
        "https://developer.myket.ir/api/partners/applications/"
        f"{s.package_name}/purchases/products/{product_id}/verify"
    )
    try:
        r = http.post(
            url,
            json={"tokenId": token},
            headers={"X-Access-Token": s.myket_access_token},
            timeout=15,
        )
    except httpx.HTTPError as e:
        raise StoreUnavailable(f"myket: {e.__class__.__name__}") from e
    if r.status_code in (400, 404):
        raise PurchaseRejected("خرید در مایکت پیدا نشد")
    if r.status_code in (401, 403):
        raise StoreUnavailable("توکن دسترسی مایکت نامعتبر است")
    if r.status_code != 200:
        raise StoreUnavailable(f"myket HTTP {r.status_code}")
    data = _json(r)
    # purchaseState: 0 موفق، 1 ناموفق
    if int(data.get("purchaseState", 1)) != 0:
        raise PurchaseRejected("خرید در مایکت تأیید نشد")


def _json(r: httpx.Response) -> dict:
    try:
        d = r.json()
        return d if isinstance(d, dict) else {}
    except ValueError as e:
        raise StoreUnavailable("پاسخ نامعتبر از فروشگاه") from e
