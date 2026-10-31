from __future__ import annotations

import hashlib
import hmac
import re
import secrets
import time
from collections import defaultdict, deque

_N, _R, _P = 2**14, 8, 1


def hash_password(pw: str) -> str:
    salt = secrets.token_bytes(16)
    dk = hashlib.scrypt(pw.encode(), salt=salt, n=_N, r=_R, p=_P, maxmem=64 * 1024 * 1024)
    return f"scrypt${_N}${_R}${_P}${salt.hex()}${dk.hex()}"


def verify_password(pw: str, stored: str) -> bool:
    try:
        _, n, r, p, salt, dk = stored.split("$")
        calc = hashlib.scrypt(
            pw.encode(), salt=bytes.fromhex(salt), n=int(n), r=int(r), p=int(p),
            maxmem=64 * 1024 * 1024,
        )
        return hmac.compare_digest(calc.hex(), dk)
    except Exception:
        return False


_DUMMY = hash_password("dummy-password-for-timing")


def dummy_verify(pw: str) -> None:
    """برای یکسان‌بودن زمان پاسخ وقتی کاربر وجود ندارد."""
    verify_password(pw, _DUMMY)


def new_token() -> str:
    return secrets.token_urlsafe(32)


def token_hash(t: str) -> str:
    return hashlib.sha256(t.encode()).hexdigest()


_FA = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
_EMAIL = re.compile(r"^[^@\s]{1,64}@[^@\s]{1,190}\.[^@\s.]{2,}$")


def normalize_identifier(raw: str) -> tuple[str, str]:
    """ایمیل یا موبایل ایران را یکدست می‌کند. خروجی: (kind, normalized)."""
    s = (raw or "").strip().translate(_FA)
    if "@" in s:
        s = s.lower()
        if not _EMAIL.match(s):
            raise ValueError("ایمیل معتبر نیست")
        return "email", s
    d = re.sub(r"[\s\-()]", "", s)
    if d.startswith("+98"):
        d = "0" + d[3:]
    elif d.startswith("0098"):
        d = "0" + d[4:]
    elif d.startswith("98") and len(d) == 12:
        d = "0" + d[2:]
    elif len(d) == 10 and d.startswith("9"):
        d = "0" + d
    if not re.fullmatch(r"09\d{9}", d):
        raise ValueError("ایمیل یا شمارهٔ موبایل معتبر نیست")
    return "phone", d


class RateLimiter:
    """محدودکنندهٔ ساده در حافظه: حداکثر [limit] خطا در [window] ثانیه برای هر کلید."""

    def __init__(self, limit: int = 8, window: int = 900):
        self.limit, self.window = limit, window
        self._h: dict[str, deque] = defaultdict(deque)

    def _prune(self, key: str, now: float) -> deque:
        q = self._h[key]
        while q and now - q[0] > self.window:
            q.popleft()
        return q

    def blocked(self, key: str) -> bool:
        return len(self._prune(key, time.time())) >= self.limit

    def fail(self, key: str) -> None:
        self._prune(key, time.time()).append(time.time())

    def reset(self, key: str) -> None:
        self._h.pop(key, None)


def sign(secret: str, msg: str) -> str:
    return hmac.new(secret.encode(), msg.encode(), hashlib.sha256).hexdigest()
