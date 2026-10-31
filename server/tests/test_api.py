import re
import httpx
import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app, now
from app import security as sec


class Store:
    """فروشگاه جعلی: رفتار را با فیلدها کنترل می‌کنیم و درخواست‌ها را ثبت می‌کنیم."""

    def __init__(self):
        self.calls = []
        self.status = 200
        self.json = {"purchaseState": 0, "consumptionState": 0}

    def __call__(self, req: httpx.Request) -> httpx.Response:
        self.calls.append(req)
        if self.status == "boom":
            raise httpx.ConnectError("down")
        return httpx.Response(self.status, json=self.json)


@pytest.fixture
def env(tmp_path):
    st = Store()
    s = Settings(
        db_path=str(tmp_path / "t.db"), secret_key="x" * 32, admin_password="adminpass-123",
        cookie_secure=False, bazaar_access_token="BZ", myket_access_token="MK",
        products={"pro_lifetime": None, "pro_year": 365},
    )
    app = create_app(s, httpx.Client(transport=httpx.MockTransport(st)))
    return TestClient(app), st, s


def dev(n=1, model="Pixel"):
    return {"uid": f"device-uid-{n:04d}", "model": model, "platform": "android", "app_version": "1.1.0", "store": "bazaar"}


def reg(c, ident="09121234567", pw="password1", n=1):
    return c.post("/api/v1/auth/register", json={"identifier": ident, "password": pw, "name": "علی",
                                                 "accept_terms": True, "device": dev(n)})


def H(tok):
    return {"Authorization": f"Bearer {tok}"}


# ---------- هویت ----------
def test_normalize():
    assert sec.normalize_identifier("۰۹۱۲ ۱۲۳ ۴۵۶۷") == ("phone", "09121234567")
    assert sec.normalize_identifier("+98 912 123 4567")[1] == "09121234567"
    assert sec.normalize_identifier("9121234567")[1] == "09121234567"
    assert sec.normalize_identifier(" A@B.com ") == ("email", "a@b.com")
    for bad in ["", "123", "a@b", "0912", "hello"]:
        with pytest.raises(ValueError):
            sec.normalize_identifier(bad)


def test_password_hash():
    h = sec.hash_password("secret123")
    assert sec.verify_password("secret123", h) and not sec.verify_password("secret124", h)
    assert "secret123" not in h


def test_register_login_flow(env):
    c, _, _ = env
    r = reg(c)
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["license"]["plan"] == "free" and j["license"]["limits"]["max_cameras"] == 2
    assert j["license"]["limits"]["fire_smoke"] is False
    # تکراری (با فرمت دیگر همان شماره)
    assert reg(c, "+989121234567").status_code == 409
    # بدون پذیرش شرایط
    r = c.post("/api/v1/auth/register", json={"identifier": "a@b.com", "password": "password1",
                                              "accept_terms": False, "device": dev(2)})
    assert r.status_code == 400 and r.json()["code"] == "terms"
    # رمز کوتاه
    assert reg(c, "b@b.com", "short").status_code == 422
    # ورود
    ok = c.post("/api/v1/auth/login", json={"identifier": "09121234567", "password": "password1", "device": dev(1)})
    assert ok.status_code == 200
    bad = c.post("/api/v1/auth/login", json={"identifier": "09121234567", "password": "nope", "device": dev(1)})
    assert bad.status_code == 401 and bad.json()["code"] == "bad_credentials"
    # کاربر ناموجود هم همان پیام
    nu = c.post("/api/v1/auth/login", json={"identifier": "09129999999", "password": "x", "device": dev(1)})
    assert nu.status_code == 401 and nu.json()["message"] == bad.json()["message"]


def test_login_rate_limit(env):
    c, _, _ = env
    reg(c)
    for _ in range(8):
        c.post("/api/v1/auth/login", json={"identifier": "09121234567", "password": "bad", "device": dev(1)})
    r = c.post("/api/v1/auth/login", json={"identifier": "09121234567", "password": "password1", "device": dev(1)})
    assert r.status_code == 429


def test_auth_required_and_logout(env):
    c, _, _ = env
    assert c.get("/api/v1/me").status_code == 401
    assert c.get("/api/v1/me", headers=H("garbage")).status_code == 401
    tok = reg(c).json()["token"]
    assert c.get("/api/v1/me", headers=H(tok)).status_code == 200
    c.post("/api/v1/auth/logout", headers=H(tok))
    assert c.get("/api/v1/me", headers=H(tok)).status_code == 401


# ---------- دستگاه‌ها ----------
def test_device_limit_and_revoke(env):
    c, _, _ = env  # سقف رایگان = ۲
    tok1 = reg(c).json()["token"]
    login = lambda n, **kw: c.post("/api/v1/auth/login", json={
        "identifier": "09121234567", "password": "password1", "device": dev(n), **kw})
    assert login(2).status_code == 200
    r = login(3)
    assert r.status_code == 409 and r.json()["code"] == "device_limit"
    devices = r.json()["devices"]
    assert len(devices) == 2
    # حذف یک دستگاه هنگام ورود
    r = login(3, revoke_device_id=devices[-1]["id"])
    assert r.status_code == 200, r.text
    me = c.get("/api/v1/me", headers=H(r.json()["token"])).json()
    assert len(me["devices"]) == 2


def test_removed_device_cannot_heartbeat(env):
    c, _, _ = env
    tok = reg(c).json()["token"]
    me = c.get("/api/v1/me", headers=H(tok)).json()
    c.delete(f"/api/v1/devices/{me['current_device_id']}", headers=H(tok))
    r = c.post("/api/v1/heartbeat", headers=H(tok), json={"device": dev(1)})
    # حذف دستگاه نشستش را هم می‌بندد؛ اپ هر ۴۰۱ را «خروج از حساب» تلقی می‌کند
    assert r.status_code == 401


# ---------- آمار ----------
def test_heartbeat_accumulates(env):
    c, _, s = env
    tok = reg(c).json()["token"]
    for _ in range(2):
        r = c.post("/api/v1/heartbeat", headers=H(tok), json={
            "device": dev(1), "cameras": 2, "events": {"motion": 3, "fire": 1, "smoke": 0, "offline": 1}})
        assert r.status_code == 200
    from app import db
    with db.session(s.db_path) as d:
        row = d.execute("SELECT * FROM stats_daily").fetchone()
    assert (row["ev_motion"], row["ev_fire"], row["ev_offline"], row["heartbeats"], row["cameras"]) == (6, 2, 2, 2, 2)
    # مقدار منفی/غیرمجاز رد می‌شود
    bad = c.post("/api/v1/heartbeat", headers=H(tok), json={"device": dev(1), "events": {"motion": -1}})
    assert bad.status_code == 422


# ---------- خرید ----------
def buy(c, tok, store="bazaar", product="pro_lifetime", token="TOKEN-ABCDEF"):
    return c.post("/api/v1/purchase/verify", headers=H(tok), json={
        "store": store, "product_id": product, "purchase_token": token})


def test_purchase_bazaar_ok_and_request_shape(env):
    c, st, s = env
    tok = reg(c).json()["token"]
    r = buy(c, tok)
    assert r.status_code == 200, r.text
    lic = r.json()["license"]
    assert lic["plan"] == "pro" and lic["limits"]["fire_smoke"] and lic["pro_until"] is None
    req = st.calls[0]
    assert req.method == "GET" and req.url.host == "pardakht.cafebazaar.ir"
    assert f"/validate/{s.package_name}/inapp/pro_lifetime/purchases/TOKEN-ABCDEF/" in req.url.path
    assert req.url.params["access_token"] == "BZ"
    # دومین فراخوانی برای همان توکن دوباره به فروشگاه نمی‌رود
    assert buy(c, tok).status_code == 200 and len(st.calls) == 1


def test_purchase_myket(env):
    c, st, s = env
    tok = reg(c).json()["token"]
    assert buy(c, tok, store="myket", token="MKTOKEN-1").status_code == 200
    req = st.calls[0]
    assert req.method == "POST" and req.headers["x-access-token"] == "MK"
    assert req.url.path.endswith("/purchases/products/pro_lifetime/verify")
    assert b'"tokenId"' in req.content


def test_purchase_rejections(env):
    c, st, _ = env
    tok = reg(c).json()["token"]
    st.json = {"purchaseState": 1}                      # بازپرداخت
    assert buy(c, tok).status_code == 402
    st.status, st.json = 404, {"error": "not_found"}
    assert buy(c, tok, token="OTHER-TOKEN").status_code == 402
    st.status = 500
    r = buy(c, tok, token="OTHER-2")
    assert r.status_code == 503 and r.json()["code"] == "store_unavailable"
    st.status = "boom"
    assert buy(c, tok, token="OTHER-3").status_code == 503
    assert buy(c, tok, product="hack_product").status_code == 400
    assert buy(c, tok, store="evil").status_code == 402
    me = c.get("/api/v1/me", headers=H(tok)).json()
    assert me["license"]["plan"] == "free"             # هیچ‌کدام مجوز نداده‌اند


def test_purchase_missing_server_token(tmp_path):
    s = Settings(db_path=str(tmp_path / "x.db"))
    c = TestClient(create_app(s, httpx.Client(transport=httpx.MockTransport(Store()))))
    tok = reg(c).json()["token"]
    assert buy(c, tok).status_code == 503


def test_token_cannot_be_shared(env):
    c, st, _ = env
    a = reg(c, "09121111111").json()["token"]
    b = reg(c, "09122222222", n=2).json()["token"]
    assert buy(c, a).status_code == 200
    r = buy(c, b)
    assert r.status_code == 409 and r.json()["code"] == "token_used"
    assert c.get("/api/v1/me", headers=H(b)).json()["license"]["plan"] == "free"


def test_deleted_owner_releases_token(env):
    c, _, _ = env
    a = reg(c, "09121111111").json()["token"]
    buy(c, a)
    assert c.request("DELETE", "/api/v1/account", headers=H(a), json={"password": "wrong"}).status_code == 401
    assert c.request("DELETE", "/api/v1/account", headers=H(a), json={"password": "password1"}).status_code == 200
    assert c.get("/api/v1/me", headers=H(a)).status_code == 401
    b = reg(c, "09122222222", n=2).json()["token"]
    assert buy(c, b).status_code == 200  # خریدار قانونی با حساب جدید بازیابی می‌کند


def test_year_product_extends(env):
    c, _, _ = env
    tok = reg(c).json()["token"]
    t0 = now()
    u1 = buy(c, tok, product="pro_year", token="YEAR-TOKEN-1").json()["license"]["pro_until"]
    assert abs(u1 - (t0 + 365 * 86400)) < 10
    u2 = buy(c, tok, product="pro_year", token="YEAR-TOKEN-2").json()["license"]["pro_until"]
    assert abs(u2 - (u1 + 365 * 86400)) < 10
    # خرید دائمی روی سالانه
    assert buy(c, tok, token="LIFE-TOKEN-1").json()["license"]["pro_until"] is None


def test_expired_pro_falls_back(env):
    c, _, s = env
    tok = reg(c).json()["token"]
    buy(c, tok, product="pro_year", token="YEAR-TOKEN-1")
    from app import db
    with db.session(s.db_path) as d:
        d.execute("UPDATE licenses SET pro_until=?", (now() - 5,))
    lic = c.get("/api/v1/me", headers=H(tok)).json()["license"]
    assert lic["plan"] == "free" and lic["limits"]["max_cameras"] == 2


def test_test_purchases_flag(tmp_path):
    s = Settings(db_path=str(tmp_path / "x.db"), allow_test_purchases=True)
    c = TestClient(create_app(s, httpx.Client(transport=httpx.MockTransport(Store()))))
    tok = reg(c).json()["token"]
    assert buy(c, tok, token="TEST-123").status_code == 200
    s2 = Settings(db_path=str(tmp_path / "y.db"))  # پیش‌فرض: خاموش
    c2 = TestClient(create_app(s2, httpx.Client(transport=httpx.MockTransport(Store()))))
    tok2 = reg(c2).json()["token"]
    assert buy(c2, tok2, token="TEST-123").status_code == 503


def test_change_password(env):
    c, _, _ = env
    t1 = reg(c).json()["token"]
    t2 = c.post("/api/v1/auth/login", json={"identifier": "09121234567", "password": "password1", "device": dev(2)}).json()["token"]
    assert c.post("/api/v1/auth/change-password", headers=H(t1), json={"old_password": "x", "new_password": "newpassword1"}).status_code == 401
    assert c.post("/api/v1/auth/change-password", headers=H(t1), json={"old_password": "password1", "new_password": "newpassword1"}).status_code == 200
    assert c.get("/api/v1/me", headers=H(t1)).status_code == 200
    assert c.get("/api/v1/me", headers=H(t2)).status_code == 401  # نشست دیگر بسته شد
    assert c.post("/api/v1/auth/login", json={"identifier": "09121234567", "password": "newpassword1", "device": dev(1)}).status_code == 200


# ---------- پنل مدیریت ----------
def admin_login(c, pw="adminpass-123"):
    return c.post("/admin/login", data={"password": pw}, follow_redirects=False)


def csrf_of(html):
    return re.search(r'name="csrf" value="([0-9a-f]+)"', html).group(1)


def test_admin_disabled_without_config(tmp_path):
    c = TestClient(create_app(Settings(db_path=str(tmp_path / "x.db"))))
    assert "غیرفعال" in c.get("/admin").text
    assert admin_login(c, "").status_code == 200  # صفحهٔ ورود، نه ریدایرکت


def test_admin_requires_login(env):
    c, _, _ = env
    assert "رمز مدیر" in c.get("/admin").text
    assert "رمز مدیر" in c.get("/admin/user/1").text
    assert c.get("/admin/export.csv").text.count("رمز مدیر") == 1
    assert "نادرست" in admin_login(c, "wrong").text


def test_admin_panel_flow(env):
    c, _, s = env
    reg(c, "09121234567")
    tok2 = reg(c, "x@y.com", n=2).json()["token"]
    c.post("/api/v1/heartbeat", headers=H(tok2), json={"device": dev(2), "cameras": 2, "events": {"motion": 5, "fire": 1}})
    assert admin_login(c).status_code == 303
    home = c.get("/admin").text
    assert "09121234567" in home and "x@y.com" in home and "رایگان" in home
    assert "5 / 1 / 0" in home
    assert "x@y.com" in c.get("/admin?q=x@y").text and "09121234567" not in c.get("/admin?q=x@y").text
    # جزئیات و CSRF
    det = c.get("/admin/user/2").text
    t = csrf_of(det)
    assert c.post("/admin/user/2/act", data={"action": "grant_pro", "value": "30", "csrf": "bad"}).status_code == 403
    r = c.post("/admin/user/2/act", data={"action": "grant_pro", "value": "30", "csrf": t}, follow_redirects=False)
    assert r.status_code == 303
    lic = c.get("/api/v1/me", headers=H(tok2)).json()["license"]
    assert lic["plan"] == "pro"
    assert "پرو" in c.get("/admin?plan=pro").text and "x@y.com" in c.get("/admin?plan=pro").text
    # لغو
    c.post("/admin/user/2/act", data={"action": "revoke_pro", "csrf": t})
    assert c.get("/api/v1/me", headers=H(tok2)).json()["license"]["plan"] == "free"
    # مسدودسازی
    c.post("/admin/user/2/act", data={"action": "ban", "csrf": t})
    assert c.get("/api/v1/me", headers=H(tok2)).status_code == 401
    assert c.post("/api/v1/auth/login", json={"identifier": "x@y.com", "password": "password1", "device": dev(2)}).status_code == 403
    c.post("/admin/user/2/act", data={"action": "unban", "csrf": t})
    # رمز موقت
    r = c.post("/admin/user/2/act", data={"action": "reset_password", "csrf": t})
    tmp = re.search(r'class="mono" style="font-size:20px">([^<]+)<', r.text).group(1)
    assert c.post("/api/v1/auth/login", json={"identifier": "x@y.com", "password": tmp, "device": dev(2)}).status_code == 200
    # خروجی CSV
    csv_text = c.get("/admin/export.csv").text
    assert "09121234567" in csv_text and csv_text.startswith("﻿id,")
    # حذف
    c.post("/admin/user/2/act", data={"action": "delete", "csrf": t})
    assert "x@y.com" not in c.get("/admin").text


def test_admin_escapes_html(env):
    c, _, _ = env
    c.post("/api/v1/auth/register", json={"identifier": "a@b.com", "password": "password1",
           "name": "<script>alert(1)</script>", "accept_terms": True, "device": dev()})
    admin_login(c)
    home = c.get("/admin").text
    assert "<script>alert(1)</script>" not in home and "&lt;script&gt;" in home


def test_csv_formula_injection_guard(env):
    c, _, _ = env
    c.post("/api/v1/auth/register", json={"identifier": "a@b.com", "password": "password1",
           "name": "=HYPERLINK(\"http://x\")", "accept_terms": True, "device": dev()})
    admin_login(c)
    assert "'=HYPERLINK" in c.get("/admin/export.csv").text


def test_healthz(env):
    c, _, _ = env
    assert c.get("/healthz").json() == {"ok": True}
