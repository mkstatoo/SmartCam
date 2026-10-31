"""پنل مدیریت: جدول کاربران، آمار، مدیریت مجوز و کاربر. فقط با DC_ADMIN_PASSWORD فعال می‌شود."""
from __future__ import annotations

import csv
import hmac
import html
import io
import secrets
import time
from typing import Optional

from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, PlainTextResponse, RedirectResponse, Response

from . import security as sec

COOKIE = "dc_admin"
PAGE = 50
COOKIE_TTL = 8 * 3600


def jdate(ts: Optional[int], with_time: bool = False) -> str:
    """تاریخ شمسی (الگوریتم استاندارد جلالی) به وقت تهران."""
    if not ts:
        return "—"
    t = time.gmtime(ts + 12600)  # UTC+3:30
    gy, gm, gd = t.tm_year, t.tm_mon, t.tm_mday
    g_dm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
    gy2 = gy + 1 if gm > 2 else gy
    days = 355666 + 365 * gy + (gy2 + 3) // 4 - (gy2 + 99) // 100 + (gy2 + 399) // 400 + gd + g_dm[gm - 1]
    jy = -1595 + 33 * (days // 12053)
    days %= 12053
    jy += 4 * (days // 1461)
    days %= 1461
    if days > 365:
        jy += (days - 1) // 365
        days = (days - 1) % 365
    if days < 186:
        jm, jd = 1 + days // 31, 1 + days % 31
    else:
        jm, jd = 7 + (days - 186) // 30, 1 + (days - 186) % 30
    out = f"{jy}/{jm:02d}/{jd:02d}"
    if with_time:
        out += f" {t.tm_hour:02d}:{t.tm_min:02d}"
    return out


def ago(ts: Optional[int]) -> str:
    if not ts:
        return "—"
    d = int(time.time()) - ts
    if d < 120:
        return "همین الان"
    if d < 3600:
        return f"{d // 60} دقیقه پیش"
    if d < 86400:
        return f"{d // 3600} ساعت پیش"
    return f"{d // 86400} روز پیش"


E = html.escape

CSS = """
:root{--bg:#101114;--card:#1a1c22;--line:#2a2d36;--tx:#e8e9ee;--mut:#9aa0ae;--pri:#e8590c;--ok:#2fb36d;--bad:#e5484d;--warn:#f5a524}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--tx);font:14px/1.7 system-ui,"Segoe UI",Tahoma,sans-serif}
a{color:#ffa94d;text-decoration:none}a:hover{text-decoration:underline}
header{display:flex;align-items:center;gap:16px;padding:12px 24px;border-bottom:1px solid var(--line);background:#14161b;position:sticky;top:0;z-index:5}
header h1{font-size:16px;margin:0;flex:1}header form{margin:0}
main{max-width:1280px;margin:0 auto;padding:20px 24px 60px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-bottom:20px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px 16px}
.card b{display:block;font-size:26px;line-height:1.2}.card span{color:var(--mut);font-size:12px}
.panel{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin-bottom:20px}
.panel h2{font-size:14px;margin:0 0 12px;color:var(--mut);font-weight:600}
.bars{display:flex;align-items:flex-end;gap:6px;height:90px}
.bars div{flex:1;background:var(--pri);border-radius:4px 4px 0 0;min-height:2px;position:relative;opacity:.9}
.bars div i{position:absolute;top:-18px;inset-inline:0;text-align:center;font-style:normal;font-size:11px;color:var(--mut)}
.bar-l{display:flex;gap:6px;color:var(--mut);font-size:10px;margin-top:4px}.bar-l span{flex:1;text-align:center}
form.filters{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:12px}
input,select,button,textarea{font:inherit;color:var(--tx);background:#12141a;border:1px solid var(--line);border-radius:8px;padding:7px 10px}
button{cursor:pointer;background:var(--pri);border-color:var(--pri);color:#fff;font-weight:600}
button.sec{background:#12141a;border-color:var(--line);color:var(--tx)}button.bad{background:var(--bad);border-color:var(--bad)}
.tw{overflow:auto;border:1px solid var(--line);border-radius:12px}
table{width:100%;border-collapse:collapse;background:var(--card)}
th,td{padding:9px 12px;text-align:right;border-bottom:1px solid var(--line);white-space:nowrap}
th{position:sticky;top:0;background:#20232b;color:var(--mut);font-weight:600;font-size:12px}
tr:hover td{background:#1e2027}.num{text-align:center;font-variant-numeric:tabular-nums}
.badge{display:inline-block;padding:1px 9px;border-radius:99px;font-size:12px;font-weight:600}
.pro{background:#2b2113;color:#ffa94d;border:1px solid #5a3b12}.free{background:#1f232b;color:var(--mut);border:1px solid var(--line)}
.ban{background:#2a1517;color:#ff8a8e;border:1px solid #5e2327}.ok{color:var(--ok)}
.pager{display:flex;gap:6px;margin-top:12px;align-items:center;color:var(--mut)}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:20px}@media(max-width:900px){.grid2{grid-template-columns:1fr}}
.kv{display:grid;grid-template-columns:130px 1fr;gap:6px 12px}.kv dt{color:var(--mut)}.kv dd{margin:0}
.actions{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-bottom:10px}.actions form{display:flex;gap:6px;margin:0}
.flag{color:var(--warn)}.note{color:var(--mut);font-size:12px}
.login{max-width:340px;margin:12vh auto;padding:24px}.login input{width:100%;margin:8px 0}
.mono{font-family:ui-monospace,Consolas,monospace;direction:ltr;unicode-bidi:plaintext}
"""


def page(title: str, body: str, nav: str = "") -> HTMLResponse:
    return HTMLResponse(
        f'<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8">'
        f'<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex">'
        f"<title>{E(title)}</title><style>{CSS}</style></head><body>{nav}{body}</body></html>",
        headers={"Cache-Control": "no-store", "X-Frame-Options": "DENY"},
    )


def register_admin(app: FastAPI, ctx) -> None:
    s = ctx.s
    enabled = bool(s.admin_password and len(s.secret_key) >= 16)

    def make_cookie() -> str:
        exp = int(time.time()) + COOKIE_TTL
        nonce = secrets.token_hex(8)
        return f"{exp}.{nonce}.{sec.sign(s.secret_key, f'{exp}.{nonce}')}"

    def valid_cookie(v: Optional[str]) -> bool:
        if not enabled or not v:
            return False
        try:
            exp, nonce, sig = v.split(".")
            return int(exp) > time.time() and hmac.compare_digest(sig, sec.sign(s.secret_key, f"{exp}.{nonce}"))
        except Exception:
            return False

    def csrf_of(v: str) -> str:
        return sec.sign(s.secret_key, "csrf" + v)[:32]

    def authed(request: Request) -> Optional[str]:
        v = request.cookies.get(COOKIE)
        return v if valid_cookie(v) else None

    def need_csrf(request: Request, token: str) -> bool:
        v = authed(request)
        return bool(v) and hmac.compare_digest(token or "", csrf_of(v))

    def login_page(msg: str = "") -> HTMLResponse:
        warn = "" if enabled else '<p class="flag">پنل غیرفعال است: DC_ADMIN_PASSWORD و DC_SECRET_KEY (حداقل ۱۶ نویسه) را تنظیم کنید.</p>'
        return page(
            "ورود مدیر",
            f'<div class="login card"><h2>پنل مدیریت کارآگاه دوربین</h2>{warn}'
            f'<p class="flag">{E(msg)}</p><form method="post" action="/admin/login">'
            '<input type="password" name="password" placeholder="رمز مدیر" autofocus required>'
            "<button>ورود</button></form></div>",
        )

    def nav(v: str) -> str:
        return (
            '<header><h1>🕵️ کارآگاه دوربین — مدیریت</h1><a href="/admin">کاربران</a>'
            '<a href="/admin/export.csv">خروجی CSV</a>'
            f'<form method="post" action="/admin/logout"><input type="hidden" name="csrf" value="{csrf_of(v)}">'
            '<button class="sec">خروج</button></form></header>'
        )

    @app.get("/admin", response_class=HTMLResponse)
    def admin_home(
        request: Request, q: str = "", plan: str = "", status: str = "", sort: str = "created", p: int = 1
    ):
        v = authed(request)
        if not v:
            return login_page()
        now = int(time.time())
        with ctx.conn() as c:
            one = lambda sql, *a: c.execute(sql, a).fetchone()[0]
            total = one("SELECT COUNT(*) FROM users")
            pro = one(
                "SELECT COUNT(*) FROM licenses WHERE plan='pro' AND (pro_until IS NULL OR pro_until>?)", now
            )
            cards = [
                ("کاربران", total),
                ("پرو", pro),
                ("ثبت‌نام ۷ روز اخیر", one("SELECT COUNT(*) FROM users WHERE created_at>?", now - 7 * 86400)),
                ("فعال ۲۴ ساعت", one("SELECT COUNT(*) FROM users WHERE last_seen>?", now - 86400)),
                ("فعال ۷ روز", one("SELECT COUNT(*) FROM users WHERE last_seen>?", now - 7 * 86400)),
                ("دستگاه‌ها", one("SELECT COUNT(*) FROM devices")),
                ("خریدها", one("SELECT COUNT(*) FROM purchases")),
                ("مسدود", one("SELECT COUNT(*) FROM users WHERE banned=1")),
            ]
            # ثبت‌نام ۱۴ روز اخیر
            days = []
            for i in range(13, -1, -1):
                lo = (now // 86400 - i) * 86400
                days.append((lo, one("SELECT COUNT(*) FROM users WHERE created_at>=? AND created_at<?", lo, lo + 86400)))
            mx = max([n for _, n in days] + [1])
            bars = "".join(
                f'<div style="height:{max(2, int(n / mx * 100))}%"><i>{n or ""}</i></div>' for _, n in days
            )
            lbl = "".join(f"<span>{jdate(lo)[5:]}</span>" for lo, _ in days)

            where, args = ["1=1"], []
            if q.strip():
                where.append("(u.identifier LIKE ? OR u.display_name LIKE ? OR CAST(u.id AS TEXT)=?)")
                args += [f"%{q.strip()}%", f"%{q.strip()}%", q.strip()]
            if plan == "pro":
                where.append("COALESCE(l.plan,'free')='pro' AND (l.pro_until IS NULL OR l.pro_until>?)")
                args.append(now)
            elif plan == "free":
                where.append("(COALESCE(l.plan,'free')='free' OR (l.pro_until IS NOT NULL AND l.pro_until<=?))")
                args.append(now)
            if status == "banned":
                where.append("u.banned=1")
            elif status == "active7":
                where.append("u.last_seen>?")
                args.append(now - 7 * 86400)
            elif status == "inactive30":
                where.append("(u.last_seen IS NULL OR u.last_seen<?)")
                args.append(now - 30 * 86400)
            order = {
                "created": "u.created_at DESC",
                "seen": "u.last_seen DESC",
                "events": "ev DESC",
                "devices": "devices DESC",
            }.get(sort, "u.created_at DESC")
            since = time.strftime("%Y-%m-%d", time.gmtime(now - 30 * 86400))
            base = f"""FROM users u LEFT JOIN licenses l ON l.user_id=u.id WHERE {' AND '.join(where)}"""
            count = c.execute(f"SELECT COUNT(*) {base}", args).fetchone()[0]
            rows = c.execute(
                f"""SELECT u.*, COALESCE(l.plan,'free') plan, l.pro_until,
                 (SELECT COUNT(*) FROM devices d WHERE d.user_id=u.id) devices,
                 (SELECT cameras FROM stats_daily s WHERE s.user_id=u.id ORDER BY day DESC LIMIT 1) cams,
                 (SELECT COALESCE(SUM(ev_motion),0) FROM stats_daily s WHERE s.user_id=u.id AND day>=?) e_m,
                 (SELECT COALESCE(SUM(ev_fire),0) FROM stats_daily s WHERE s.user_id=u.id AND day>=?) e_f,
                 (SELECT COALESCE(SUM(ev_smoke),0) FROM stats_daily s WHERE s.user_id=u.id AND day>=?) e_s,
                 (SELECT COALESCE(SUM(ev_motion+ev_fire+ev_smoke),0) FROM stats_daily s WHERE s.user_id=u.id AND day>=?) ev
                 {base} ORDER BY {order} LIMIT ? OFFSET ?""",
                [since, since, since, since, *args, PAGE, (max(p, 1) - 1) * PAGE],
            ).fetchall()

        def tr(r) -> str:
            is_pro = r["plan"] == "pro" and (r["pro_until"] is None or r["pro_until"] > now)
            badge = '<span class="badge pro">پرو</span>' if is_pro else '<span class="badge free">رایگان</span>'
            st = '<span class="badge ban">مسدود</span>' if r["banned"] else '<span class="ok">فعال</span>'
            flag = ' <span class="flag" title="تعداد دستگاه زیاد">⚠</span>' if r["devices"] >= s.pro_max_devices else ""
            return (
                f'<tr><td class="num">{r["id"]}</td>'
                f'<td><a href="/admin/user/{r["id"]}" class="mono">{E(r["identifier"])}</a> {E(r["display_name"])}</td>'
                f"<td>{badge}</td><td class=\"num\">{r['devices']}{flag}</td><td class=\"num\">{r['cams'] if r['cams'] is not None else '—'}</td>"
                f'<td class="num">{r["e_m"]} / {r["e_f"]} / {r["e_s"]}</td>'
                f'<td>{ago(r["last_seen"])}</td><td>{jdate(r["created_at"])}</td><td>{st}</td></tr>'
            )

        def opt(cur: str, items) -> str:
            return "".join(f'<option value="{k}"{" selected" if k == cur else ""}>{E(t)}</option>' for k, t in items)

        pages = max(1, -(-count // PAGE))
        qs = lambda pg: f"?q={E(q)}&plan={plan}&status={status}&sort={sort}&p={pg}"
        pager = (
            f'<div class="pager">صفحهٔ {p} از {pages} ({count} کاربر)'
            + (f' <a href="{qs(p - 1)}">قبلی</a>' if p > 1 else "")
            + (f' <a href="{qs(p + 1)}">بعدی</a>' if p < pages else "")
            + "</div>"
        )
        body = f"""<main>
<div class="cards">{''.join(f'<div class="card"><b>{n}</b><span>{E(t)}</span></div>' for t, n in cards)}</div>
<div class="panel"><h2>ثبت‌نام ۱۴ روز اخیر</h2><div class="bars">{bars}</div><div class="bar-l">{lbl}</div></div>
<form class="filters" method="get" action="/admin">
<input name="q" value="{E(q)}" placeholder="جست‌وجو: ایمیل، موبایل، نام، شناسه">
<select name="plan">{opt(plan, [("", "همهٔ طرح‌ها"), ("pro", "پرو"), ("free", "رایگان")])}</select>
<select name="status">{opt(status, [("", "همهٔ وضعیت‌ها"), ("active7", "فعال ۷ روز اخیر"), ("inactive30", "غیرفعال بیش از ۳۰ روز"), ("banned", "مسدود")])}</select>
<select name="sort">{opt(sort, [("created", "جدیدترین"), ("seen", "آخرین فعالیت"), ("events", "بیشترین رویداد"), ("devices", "بیشترین دستگاه")])}</select>
<button>اعمال</button></form>
<div class="tw"><table><thead><tr><th>#</th><th>کاربر</th><th>طرح</th><th>دستگاه</th><th>دوربین</th>
<th>رویداد ۳۰ روز (حرکت/آتش/دود)</th><th>آخرین فعالیت</th><th>ثبت‌نام</th><th>وضعیت</th></tr></thead>
<tbody>{''.join(tr(r) for r in rows) or '<tr><td colspan="9" class="note">موردی نیست</td></tr>'}</tbody></table></div>{pager}</main>"""
        return page("کاربران", body, nav(v))

    @app.post("/admin/login")
    def admin_login(request: Request, password: str = Form("")):
        if not enabled:
            return login_page()
        key = "admin:" + (request.client.host if request.client else "?")
        if ctx.limiter.blocked(key):
            return login_page("تلاش‌های زیاد؛ بعداً دوباره امتحان کنید.")
        if not hmac.compare_digest(password.encode(), s.admin_password.encode()):
            ctx.limiter.fail(key)
            return login_page("رمز نادرست است.")
        ctx.limiter.reset(key)
        r = RedirectResponse("/admin", status_code=303)
        r.set_cookie(COOKIE, make_cookie(), max_age=COOKIE_TTL, httponly=True,
                     samesite="strict", secure=s.cookie_secure)
        return r

    @app.post("/admin/logout")
    def admin_logout(request: Request, csrf: str = Form("")):
        r = RedirectResponse("/admin", status_code=303)
        r.delete_cookie(COOKIE)
        return r

    @app.get("/admin/user/{uid}", response_class=HTMLResponse)
    def admin_user(request: Request, uid: int, msg: str = ""):
        v = authed(request)
        if not v:
            return login_page()
        now = int(time.time())
        with ctx.conn() as c:
            u = c.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
            if not u:
                return page("یافت نشد", f"{nav(v)}<main><p>کاربر پیدا نشد.</p></main>")
            lic = c.execute("SELECT * FROM licenses WHERE user_id=?", (uid,)).fetchone()
            devs = c.execute("SELECT * FROM devices WHERE user_id=? ORDER BY last_seen DESC", (uid,)).fetchall()
            pur = c.execute("SELECT * FROM purchases WHERE user_id=? ORDER BY created_at DESC", (uid,)).fetchall()
            st = c.execute("SELECT * FROM stats_daily WHERE user_id=? ORDER BY day DESC LIMIT 30", (uid,)).fetchall()
            au = c.execute("SELECT * FROM audit WHERE user_id=? ORDER BY ts DESC LIMIT 40", (uid,)).fetchall()
        is_pro = bool(lic) and lic["plan"] == "pro" and (lic["pro_until"] is None or lic["pro_until"] > now)
        until = "دائمی" if (lic and lic["pro_until"] is None) else jdate(lic["pro_until"] if lic else None)
        t = csrf_of(v)

        def act(label: str, action: str, cls: str = "sec", extra: str = "", confirm: str = "") -> str:
            oc = f' onclick="return confirm(\'{E(confirm)}\')"' if confirm else ""
            return (
                f'<form method="post" action="/admin/user/{uid}/act"><input type="hidden" name="csrf" value="{t}">'
                f'<input type="hidden" name="action" value="{action}">{extra}<button class="{cls}"{oc}>{E(label)}</button></form>'
            )

        dev_rows = "".join(
            f"<tr><td>{E(d['model'] or '—')}</td><td>{E(d['platform'])}</td><td>{E(d['app_version'])}</td>"
            f"<td>{E(d['store'] or '—')}</td><td>{ago(d['last_seen'])}</td></tr>" for d in devs
        )
        pur_rows = "".join(
            f"<tr><td>{E(x['store'])}</td><td>{E(x['product_id'])}</td><td>{jdate(x['created_at'], True)}</td>"
            f"<td class=\"mono\">{E(x['token'][:10])}…</td></tr>" for x in pur
        )
        st_rows = "".join(
            f"<tr><td>{E(x['day'])}</td><td class=\"num\">{x['cameras']}</td><td class=\"num\">{x['ev_motion']}</td>"
            f"<td class=\"num\">{x['ev_fire']}</td><td class=\"num\">{x['ev_smoke']}</td><td class=\"num\">{x['ev_offline']}</td>"
            f"<td class=\"num\">{x['heartbeats']}</td></tr>" for x in st
        )
        au_rows = "".join(
            f"<tr><td>{jdate(a['ts'], True)}</td><td>{E(a['actor'])}</td><td>{E(a['action'])}</td><td>{E(a['detail'])}</td></tr>"
            for a in au
        )
        body = f"""<main>
<p><a href="/admin">← بازگشت</a></p><p class="flag">{E(msg)}</p>
<div class="grid2"><div class="panel"><h2>حساب</h2><dl class="kv">
<dt>شناسه</dt><dd>{u['id']}</dd><dt>مشخصهٔ ورود</dt><dd class="mono">{E(u['identifier'])}</dd>
<dt>نام</dt><dd>{E(u['display_name']) or '—'}</dd><dt>ثبت‌نام</dt><dd>{jdate(u['created_at'], True)}</dd>
<dt>آخرین فعالیت</dt><dd>{ago(u['last_seen'])}</dd><dt>پذیرش حریم خصوصی</dt><dd>{jdate(u['consent_at'], True)}</dd>
<dt>طرح</dt><dd>{'<span class="badge pro">پرو</span> تا ' + until if is_pro else '<span class="badge free">رایگان</span>'}</dd>
<dt>وضعیت</dt><dd>{'<span class="badge ban">مسدود</span>' if u['banned'] else 'فعال'}</dd>
<dt>یادداشت</dt><dd>{E(u['note']) or '—'}</dd></dl></div>
<div class="panel"><h2>عملیات</h2><div class="actions">
{act('پرو ۳۰ روزه', 'grant_pro', extra='<input type="hidden" name="value" value="30">')}
{act('پرو ۳۶۵ روزه', 'grant_pro', extra='<input type="hidden" name="value" value="365">')}
{act('پرو دائمی', 'grant_pro', extra='<input type="hidden" name="value" value="0">')}
{act('لغو پرو', 'revoke_pro', confirm='پرو لغو شود؟')}</div>
<div class="actions">
{act('رفع مسدودی' if u['banned'] else 'مسدود کردن', 'unban' if u['banned'] else 'ban', cls='bad' if not u['banned'] else 'sec')}
{act('پاک‌کردن همهٔ دستگاه‌ها و نشست‌ها', 'reset_devices', confirm='همهٔ دستگاه‌ها خارج شوند؟')}
{act('رمز موقت جدید', 'reset_password', confirm='رمز فعلی بی‌اثر و رمز موقت ساخته شود؟')}</div>
<div class="actions">{act('ذخیرهٔ یادداشت', 'note', extra=f'<input name="value" value="{E(u["note"])}" placeholder="یادداشت">')}</div>
<div class="actions">{act('حذف کامل کاربر', 'delete', cls='bad', confirm='کاربر و همهٔ داده‌هایش حذف شود؟ برگشت‌پذیر نیست.')}</div></div></div>
<div class="grid2"><div class="panel"><h2>دستگاه‌ها ({len(devs)})</h2><div class="tw"><table><thead><tr><th>مدل</th><th>سیستم</th><th>نسخه</th><th>فروشگاه</th><th>آخرین</th></tr></thead><tbody>{dev_rows or '<tr><td colspan=5>—</td></tr>'}</tbody></table></div></div>
<div class="panel"><h2>خریدها</h2><div class="tw"><table><thead><tr><th>فروشگاه</th><th>محصول</th><th>تاریخ</th><th>توکن</th></tr></thead><tbody>{pur_rows or '<tr><td colspan=4>—</td></tr>'}</tbody></table></div></div></div>
<div class="panel"><h2>آمار ۳۰ روز اخیر</h2><div class="tw"><table><thead><tr><th>روز (میلادی)</th><th>دوربین</th><th>حرکت</th><th>آتش</th><th>دود</th><th>قطع</th><th>تماس‌ها</th></tr></thead><tbody>{st_rows or '<tr><td colspan=7>—</td></tr>'}</tbody></table></div></div>
<div class="panel"><h2>تاریخچهٔ رویدادهای حساب</h2><div class="tw"><table><thead><tr><th>زمان</th><th>عامل</th><th>رویداد</th><th>جزئیات</th></tr></thead><tbody>{au_rows or '<tr><td colspan=4>—</td></tr>'}</tbody></table></div></div></main>"""
        return page(f"کاربر {uid}", body, nav(v))

    @app.post("/admin/user/{uid}/act")
    def admin_act(
        request: Request, uid: int, action: str = Form(""), value: str = Form(""), csrf: str = Form("")
    ):
        v = authed(request)
        if not v:
            return login_page()
        if not need_csrf(request, csrf):
            return PlainTextResponse("درخواست نامعتبر (CSRF)", status_code=403)
        now = int(time.time())
        msg = ""
        with ctx.conn() as c:
            u = c.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
            if not u:
                return RedirectResponse("/admin", status_code=303)
            from .main import audit

            if action == "grant_pro":
                days = int(value or 0)
                lic = c.execute("SELECT * FROM licenses WHERE user_id=?", (uid,)).fetchone()
                if days <= 0:
                    until = None
                else:
                    cur_ok = lic and lic["plan"] == "pro" and (lic["pro_until"] is None or lic["pro_until"] > now)
                    if cur_ok and lic["pro_until"] is None:
                        until = None
                    else:
                        until = max(now, (lic["pro_until"] or 0) if cur_ok else 0) + days * 86400
                c.execute(
                    "INSERT INTO licenses(user_id,plan,pro_until,source,updated_at) VALUES(?,?,?,?,?)"
                    " ON CONFLICT(user_id) DO UPDATE SET plan='pro',pro_until=excluded.pro_until,"
                    "source='admin',updated_at=excluded.updated_at",
                    (uid, "pro", until, "admin", now),
                )
                audit(c, "admin", "grant_pro", uid, f"days={days}")
                msg = "پرو فعال شد."
            elif action == "revoke_pro":
                c.execute("UPDATE licenses SET plan='free',pro_until=NULL,source='admin',updated_at=? WHERE user_id=?", (now, uid))
                audit(c, "admin", "revoke_pro", uid)
                msg = "پرو لغو شد."
            elif action in ("ban", "unban"):
                c.execute("UPDATE users SET banned=? WHERE id=?", (1 if action == "ban" else 0, uid))
                if action == "ban":
                    c.execute("DELETE FROM sessions WHERE user_id=?", (uid,))
                audit(c, "admin", action, uid)
                msg = "انجام شد."
            elif action == "reset_devices":
                c.execute("DELETE FROM devices WHERE user_id=?", (uid,))
                c.execute("DELETE FROM sessions WHERE user_id=?", (uid,))
                audit(c, "admin", "reset_devices", uid)
                msg = "دستگاه‌ها و نشست‌ها پاک شد."
            elif action == "reset_password":
                tmp = secrets.token_urlsafe(9)
                c.execute("UPDATE users SET pw_hash=? WHERE id=?", (sec.hash_password(tmp), uid))
                c.execute("DELETE FROM sessions WHERE user_id=?", (uid,))
                audit(c, "admin", "reset_password", uid)
                msg = f"رمز موقت (فقط همین یک بار نمایش داده می‌شود): {tmp}"
                return page("رمز موقت", f'{nav(v)}<main><div class="panel"><h2>رمز موقت کاربر {uid}</h2>'
                            f'<p class="mono" style="font-size:20px">{E(tmp)}</p>'
                            f'<p class="note">آن را به کاربر بدهید و بخواهید پس از ورود تغییرش دهد.</p>'
                            f'<p><a href="/admin/user/{uid}">بازگشت</a></p></div></main>')
            elif action == "note":
                c.execute("UPDATE users SET note=? WHERE id=?", (value[:300], uid))
                audit(c, "admin", "note", uid)
                msg = "ذخیره شد."
            elif action == "delete":
                audit(c, "admin", "delete_user", uid, u["identifier"])
                c.execute("DELETE FROM users WHERE id=?", (uid,))
                return RedirectResponse("/admin", status_code=303)
        return RedirectResponse(f"/admin/user/{uid}?msg={msg}", status_code=303)

    @app.get("/admin/export.csv")
    def admin_export(request: Request):
        if not authed(request):
            return login_page()
        now = int(time.time())

        def safe(x):  # جلوگیری از اجرای فرمول در Excel
            x = "" if x is None else str(x)
            return "'" + x if x[:1] in ("=", "+", "-", "@") else x

        out = io.StringIO()
        w = csv.writer(out)
        w.writerow(["id", "identifier", "name", "plan", "pro_until", "devices", "created", "last_seen", "banned"])
        with ctx.conn() as c:
            for r in c.execute(
                "SELECT u.*, COALESCE(l.plan,'free') plan, l.pro_until,"
                " (SELECT COUNT(*) FROM devices d WHERE d.user_id=u.id) dv FROM users u"
                " LEFT JOIN licenses l ON l.user_id=u.id ORDER BY u.id"
            ):
                eff = "pro" if (r["plan"] == "pro" and (r["pro_until"] is None or r["pro_until"] > now)) else "free"
                w.writerow([r["id"], safe(r["identifier"]), safe(r["display_name"]), eff,
                            r["pro_until"] or "", r["dv"], r["created_at"], r["last_seen"] or "", r["banned"]])
        return Response(
            "﻿" + out.getvalue(), media_type="text/csv; charset=utf-8",
            headers={"Content-Disposition": "attachment; filename=users.csv"},
        )
