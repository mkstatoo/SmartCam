from __future__ import annotations

import datetime as dt
import logging
import time
from typing import Optional

import httpx
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from . import db as dbm
from . import security as sec
from .config import Settings
from .stores import PurchaseRejected, StoreUnavailable, verify_purchase

log = logging.getLogger("detective")
API = "/api/v1"
SESSION_IDLE_DAYS = 180


class Ctx:
    def __init__(self, settings: Settings, http: Optional[httpx.Client] = None):
        self.s = settings
        self.http = http or httpx.Client()
        self.limiter = sec.RateLimiter(limit=8, window=900)
        # پشت CGNAT اپراتورها چند کاربر یک IP دارند؛ سقف ثبت‌نام بلندتر است.
        self.reg_limiter = sec.RateLimiter(limit=30, window=3600)

    def conn(self):
        return dbm.session(self.s.db_path)


def err(status: int, code: str, message: str, **extra):
    return HTTPException(status, detail={"code": code, "message": message, **extra})


# ---------------- مدل‌های ورودی ----------------
class DeviceIn(BaseModel):
    uid: str = Field(min_length=8, max_length=64)
    model: str = Field(default="", max_length=64)
    platform: str = Field(default="", max_length=16)
    app_version: str = Field(default="", max_length=32)
    store: str = Field(default="", max_length=16)


class RegisterIn(BaseModel):
    identifier: str = Field(max_length=200)
    password: str = Field(min_length=8, max_length=128)
    name: str = Field(default="", max_length=60)
    accept_terms: bool
    device: DeviceIn


class LoginIn(BaseModel):
    identifier: str = Field(max_length=200)
    password: str = Field(max_length=128)
    device: DeviceIn
    # اگر سقف دستگاه پر باشد، کاربر می‌تواند یکی را حذف کند
    revoke_device_id: Optional[int] = None


class EventDeltas(BaseModel):
    motion: int = Field(default=0, ge=0, le=100000)
    fire: int = Field(default=0, ge=0, le=100000)
    smoke: int = Field(default=0, ge=0, le=100000)
    offline: int = Field(default=0, ge=0, le=100000)


class HeartbeatIn(BaseModel):
    device: DeviceIn
    cameras: int = Field(default=0, ge=0, le=1000)
    events: EventDeltas = EventDeltas()


class PurchaseIn(BaseModel):
    store: str = Field(max_length=16)
    product_id: str = Field(max_length=64)
    purchase_token: str = Field(min_length=4, max_length=512)
    order_id: str = Field(default="", max_length=128)


class PasswordIn(BaseModel):
    password: str = Field(max_length=128)


class ChangePasswordIn(BaseModel):
    old_password: str = Field(max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


# ---------------- منطق مشترک ----------------
def now() -> int:
    return int(time.time())


def today() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d")


def audit(c, actor: str, action: str, user_id: Optional[int], detail: str = "") -> None:
    c.execute(
        "INSERT INTO audit(ts,actor,action,user_id,detail) VALUES(?,?,?,?,?)",
        (now(), actor, action, user_id, detail[:500]),
    )


def effective_plan(row) -> str:
    if row is None or row["plan"] != "pro":
        return "free"
    if row["pro_until"] is not None and row["pro_until"] < now():
        return "free"
    return "pro"


def license_payload(ctx: Ctx, c, user_id: int) -> dict:
    row = c.execute("SELECT * FROM licenses WHERE user_id=?", (user_id,)).fetchone()
    plan = effective_plan(row)
    s = ctx.s
    pro = plan == "pro"
    return {
        "plan": plan,
        "pro_until": row["pro_until"] if (row and pro) else None,
        "limits": {
            "max_cameras": 1000 if pro else s.free_max_cameras,
            "fire_smoke": pro,
            "zones": pro,
            "background": pro,
            "max_events": s.pro_max_events if pro else s.free_max_events,
        },
        "offline_grace_days": s.offline_grace_days,
        "server_time": now(),
    }


def device_limit(ctx: Ctx, c, user_id: int) -> int:
    row = c.execute("SELECT * FROM licenses WHERE user_id=?", (user_id,)).fetchone()
    return ctx.s.pro_max_devices if effective_plan(row) == "pro" else ctx.s.free_max_devices


def devices_of(c, user_id: int) -> list[dict]:
    rows = c.execute(
        "SELECT id,model,platform,app_version,last_seen FROM devices WHERE user_id=? ORDER BY last_seen DESC",
        (user_id,),
    ).fetchall()
    return [dict(r) for r in rows]


def upsert_device(ctx: Ctx, c, user_id: int, d: DeviceIn, revoke_id: Optional[int] = None) -> int:
    if revoke_id is not None:
        c.execute("DELETE FROM devices WHERE id=? AND user_id=?", (revoke_id, user_id))
    r = c.execute(
        "SELECT id FROM devices WHERE user_id=? AND device_uid=?", (user_id, d.uid)
    ).fetchone()
    if r:
        c.execute(
            "UPDATE devices SET model=?,platform=?,app_version=?,store=?,last_seen=? WHERE id=?",
            (d.model, d.platform, d.app_version, d.store, now(), r["id"]),
        )
        return r["id"]
    n = c.execute("SELECT COUNT(*) FROM devices WHERE user_id=?", (user_id,)).fetchone()[0]
    if n >= device_limit(ctx, c, user_id):
        raise err(
            409, "device_limit", "سقف تعداد دستگاه‌های این حساب پر است.",
            devices=devices_of(c, user_id),
        )
    cur = c.execute(
        "INSERT INTO devices(user_id,device_uid,model,platform,app_version,store,first_seen,last_seen)"
        " VALUES(?,?,?,?,?,?,?,?)",
        (user_id, d.uid, d.model, d.platform, d.app_version, d.store, now(), now()),
    )
    return cur.lastrowid


def new_session(c, user_id: int, device_id: int) -> str:
    t = sec.new_token()
    c.execute(
        "INSERT INTO sessions(token_hash,user_id,device_id,created_at,last_used) VALUES(?,?,?,?,?)",
        (sec.token_hash(t), user_id, device_id, now(), now()),
    )
    return t


def client_ip(ctx: Ctx, request: Request) -> str:
    if ctx.s.trust_proxy:
        xff = request.headers.get("x-forwarded-for")
        if xff:
            return xff.split(",")[0].strip()
    return request.client.host if request.client else "?"


def create_app(settings: Optional[Settings] = None, http: Optional[httpx.Client] = None) -> FastAPI:
    ctx = Ctx(settings or Settings.from_env(), http)
    dbm.init_db(ctx.s.db_path)
    app = FastAPI(title="Detective Camera API", docs_url=None, redoc_url=None, openapi_url=None)
    app.state.ctx = ctx

    @app.exception_handler(HTTPException)
    async def _h(_: Request, e: HTTPException):
        body = e.detail if isinstance(e.detail, dict) else {"code": "error", "message": str(e.detail)}
        return JSONResponse(body, status_code=e.status_code)

    def current(request: Request):
        h = request.headers.get("authorization", "")
        if not h.lower().startswith("bearer "):
            raise err(401, "unauthorized", "ورود لازم است.")
        th = sec.token_hash(h[7:].strip())
        with ctx.conn() as c:
            r = c.execute(
                "SELECT s.user_id, s.device_id, s.last_used, u.banned FROM sessions s"
                " JOIN users u ON u.id=s.user_id WHERE s.token_hash=?",
                (th,),
            ).fetchone()
            if not r or now() - r["last_used"] > SESSION_IDLE_DAYS * 86400:
                raise err(401, "unauthorized", "نشست منقضی شده؛ دوباره وارد شوید.")
            if r["banned"]:
                raise err(403, "banned", "این حساب مسدود شده است.")
            if now() - r["last_used"] > 60:
                c.execute("UPDATE sessions SET last_used=? WHERE token_hash=?", (now(), th))
            return {"user_id": r["user_id"], "device_id": r["device_id"], "token_hash": th}

    # ---------------- ثبت‌نام و ورود ----------------
    @app.post(f"{API}/auth/register")
    def register(body: RegisterIn, request: Request):
        if not body.accept_terms:
            raise err(400, "terms", "پذیرش سیاست حریم خصوصی لازم است.")
        key = "reg:" + client_ip(ctx, request)
        if ctx.reg_limiter.blocked(key):
            raise err(429, "rate_limited", "تلاش‌های زیاد؛ کمی بعد دوباره امتحان کنید.")
        try:
            kind, ident = sec.normalize_identifier(body.identifier)
        except ValueError as e:
            raise err(400, "bad_identifier", str(e))
        ctx.reg_limiter.fail(key)  # هر ثبت‌نام یک واحد از سهمیه را مصرف می‌کند
        with ctx.conn() as c:
            if c.execute("SELECT 1 FROM users WHERE identifier=?", (ident,)).fetchone():
                raise err(409, "exists", "با این مشخصات قبلاً ثبت‌نام شده است؛ وارد شوید.")
            cur = c.execute(
                "INSERT INTO users(identifier,id_kind,display_name,pw_hash,created_at,last_seen,consent_at)"
                " VALUES(?,?,?,?,?,?,?)",
                (ident, kind, body.name.strip(), sec.hash_password(body.password), now(), now(), now()),
            )
            uid = cur.lastrowid
            c.execute("INSERT INTO licenses(user_id,plan,updated_at) VALUES(?,?,?)", (uid, "free", now()))
            dev = upsert_device(ctx, c, uid, body.device)
            tok = new_session(c, uid, dev)
            audit(c, "user", "register", uid, kind)
            return {"token": tok, "user": {"id": uid, "identifier": ident, "name": body.name.strip()},
                    "license": license_payload(ctx, c, uid)}

    @app.post(f"{API}/auth/login")
    def login(body: LoginIn, request: Request):
        try:
            _, ident = sec.normalize_identifier(body.identifier)
        except ValueError as e:
            raise err(400, "bad_identifier", str(e))
        key = f"login:{client_ip(ctx, request)}:{ident}"
        if ctx.limiter.blocked(key):
            raise err(429, "rate_limited", "تلاش‌های ناموفق زیاد؛ ۱۵ دقیقه بعد دوباره امتحان کنید.")
        with ctx.conn() as c:
            u = c.execute("SELECT * FROM users WHERE identifier=?", (ident,)).fetchone()
            if not u:
                sec.dummy_verify(body.password)
                ctx.limiter.fail(key)
                raise err(401, "bad_credentials", "مشخصات ورود نادرست است.")
            if not sec.verify_password(body.password, u["pw_hash"]):
                ctx.limiter.fail(key)
                raise err(401, "bad_credentials", "مشخصات ورود نادرست است.")
            if u["banned"]:
                raise err(403, "banned", "این حساب مسدود شده است.")
            ctx.limiter.reset(key)
            try:
                dev = upsert_device(ctx, c, u["id"], body.device, body.revoke_device_id)
            except HTTPException:
                c.commit()  # حذف احتمالی دستگاه قبل از خطا هم ثبت شود
                raise
            tok = new_session(c, u["id"], dev)
            c.execute("UPDATE users SET last_seen=? WHERE id=?", (now(), u["id"]))
            audit(c, "user", "login", u["id"])
            return {"token": tok, "user": {"id": u["id"], "identifier": u["identifier"], "name": u["display_name"]},
                    "license": license_payload(ctx, c, u["id"])}

    @app.post(f"{API}/auth/logout")
    def logout(cur=Depends(current)):
        with ctx.conn() as c:
            c.execute("DELETE FROM sessions WHERE token_hash=?", (cur["token_hash"],))
        return {"ok": True}

    @app.post(f"{API}/auth/change-password")
    def change_password(body: ChangePasswordIn, cur=Depends(current)):
        with ctx.conn() as c:
            u = c.execute("SELECT * FROM users WHERE id=?", (cur["user_id"],)).fetchone()
            if not sec.verify_password(body.old_password, u["pw_hash"]):
                raise err(401, "bad_credentials", "رمز فعلی نادرست است.")
            c.execute("UPDATE users SET pw_hash=? WHERE id=?", (sec.hash_password(body.new_password), u["id"]))
            # نشست‌های دیگر بسته می‌شوند
            c.execute("DELETE FROM sessions WHERE user_id=? AND token_hash<>?", (u["id"], cur["token_hash"]))
            audit(c, "user", "change_password", u["id"])
        return {"ok": True}

    # ---------------- حساب و مجوز ----------------
    @app.get(f"{API}/me")
    def me(cur=Depends(current)):
        with ctx.conn() as c:
            u = c.execute("SELECT * FROM users WHERE id=?", (cur["user_id"],)).fetchone()
            return {
                "user": {"id": u["id"], "identifier": u["identifier"], "name": u["display_name"]},
                "license": license_payload(ctx, c, u["id"]),
                "devices": devices_of(c, u["id"]),
                "current_device_id": cur["device_id"],
            }

    @app.delete(f"{API}/devices/{{device_id}}")
    def remove_device(device_id: int, cur=Depends(current)):
        with ctx.conn() as c:
            c.execute("DELETE FROM devices WHERE id=? AND user_id=?", (device_id, cur["user_id"]))
            audit(c, "user", "remove_device", cur["user_id"], str(device_id))
        return {"ok": True}

    @app.post(f"{API}/heartbeat")
    def heartbeat(body: HeartbeatIn, cur=Depends(current)):
        uid = cur["user_id"]
        with ctx.conn() as c:
            # دستگاه حذف‌شده نمی‌تواند ادامه دهد
            if not c.execute("SELECT 1 FROM devices WHERE id=? AND user_id=?", (cur["device_id"], uid)).fetchone():
                raise err(401, "device_removed", "این دستگاه از حساب حذف شده است.")
            c.execute(
                "UPDATE devices SET model=?,platform=?,app_version=?,store=?,last_seen=? WHERE id=?",
                (body.device.model, body.device.platform, body.device.app_version,
                 body.device.store, now(), cur["device_id"]),
            )
            c.execute("UPDATE users SET last_seen=? WHERE id=?", (now(), uid))
            e = body.events
            c.execute(
                "INSERT INTO stats_daily(user_id,day,cameras,ev_motion,ev_fire,ev_smoke,ev_offline,heartbeats)"
                " VALUES(?,?,?,?,?,?,?,1)"
                " ON CONFLICT(user_id,day) DO UPDATE SET cameras=excluded.cameras,"
                " ev_motion=ev_motion+excluded.ev_motion, ev_fire=ev_fire+excluded.ev_fire,"
                " ev_smoke=ev_smoke+excluded.ev_smoke, ev_offline=ev_offline+excluded.ev_offline,"
                " heartbeats=heartbeats+1",
                (uid, today(), body.cameras, e.motion, e.fire, e.smoke, e.offline),
            )
            return {"license": license_payload(ctx, c, uid)}

    @app.post(f"{API}/purchase/verify")
    def purchase_verify(body: PurchaseIn, cur=Depends(current)):
        uid = cur["user_id"]
        if body.product_id not in ctx.s.products:
            raise err(400, "bad_product", "محصول ناشناخته است.")
        with ctx.conn() as c:
            prev = c.execute(
                "SELECT * FROM purchases WHERE store=? AND token=?", (body.store, body.purchase_token)
            ).fetchone()
            if prev and prev["user_id"] not in (None, uid):
                audit(c, "system", "token_reuse", uid, f"{body.store}:{body.product_id} owner={prev['user_id']}")
                c.commit()
                raise err(409, "token_used", "این خرید قبلاً برای حساب دیگری فعال شده است.")
            if not prev:
                try:
                    verify_purchase(ctx.s, ctx.http, body.store, body.product_id, body.purchase_token)
                except PurchaseRejected as ex:
                    audit(c, "system", "purchase_rejected", uid, f"{body.store}:{ex}")
                    c.commit()
                    raise err(402, "purchase_invalid", str(ex))
                except StoreUnavailable as ex:
                    log.warning("store verification unavailable: %s", ex)
                    raise err(503, "store_unavailable",
                              "فعلاً تأیید خرید ممکن نیست؛ کمی بعد دوباره «بازیابی خرید» را بزنید.")
                c.execute(
                    "INSERT INTO purchases(user_id,store,product_id,token,order_id,created_at) VALUES(?,?,?,?,?,?)",
                    (uid, body.store, body.product_id, body.purchase_token, body.order_id, now()),
                )
            elif prev["user_id"] is None:  # مالک قبلی حسابش را حذف کرده
                c.execute("UPDATE purchases SET user_id=? WHERE id=?", (uid, prev["id"]))
            days = ctx.s.products[body.product_id]
            row = c.execute("SELECT * FROM licenses WHERE user_id=?", (uid,)).fetchone()
            if days is None:
                until = None
            else:
                base = max(now(), row["pro_until"] or 0) if effective_plan(row) == "pro" else now()
                until = base + int(days) * 86400
                if row and row["plan"] == "pro" and row["pro_until"] is None:
                    until = None  # قبلاً دائمی بوده؛ کوتاه نشود
            c.execute(
                "UPDATE licenses SET plan='pro', pro_until=?, source=?, updated_at=? WHERE user_id=?",
                (until, body.store, now(), uid),
            )
            audit(c, "user", "purchase", uid, f"{body.store}:{body.product_id}")
            return {"license": license_payload(ctx, c, uid)}

    @app.delete(f"{API}/account")
    def delete_account(body: PasswordIn, cur=Depends(current)):
        with ctx.conn() as c:
            u = c.execute("SELECT * FROM users WHERE id=?", (cur["user_id"],)).fetchone()
            if not sec.verify_password(body.password, u["pw_hash"]):
                raise err(401, "bad_credentials", "رمز نادرست است.")
            audit(c, "user", "delete_account", u["id"])
            c.execute("DELETE FROM users WHERE id=?", (u["id"],))
        return {"ok": True}

    @app.get("/healthz")
    def healthz():
        return {"ok": True}

    from .admin import register_admin

    register_admin(app, ctx)
    return app
