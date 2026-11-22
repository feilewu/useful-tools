#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""每天访问一次 ipage 站点（InfinityFree / ByetHost 免费主机）。

这两个站前面挂着 openresty 的反爬：

  1. 默认的 curl / python-requests / Wget UA 会被直接断连（curl 52，
     一个字节都不回）；Go-http-client 会拿到 403。
  2. 换成浏览器 UA 后，返回的是 aes.js 挑战页（约 850 字节），
     需要用页面里的 a/b/c 三个参数做一次 AES-128-CBC 解密，
     把结果写进 __test cookie，再请求一次才是真实页面。

本脚本用浏览器 UA 走完整挑战流程；失败时可用 Googlebot UA 兜底
（该 UA 会被直接放行到真实页面）。只依赖 Python 3 标准库。

用法：
    python3 visit_blog.py
    python3 visit_blog.py --json
    python3 visit_blog.py --url https://ipage.kesug.com/ --timeout 30 --retries 3

退出码：全部成功 0，任一失败 1。
"""

import argparse
import http.cookiejar
import json
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime

try:
    from zoneinfo import ZoneInfo
except ImportError:  # Python < 3.9
    ZoneInfo = None

DEFAULT_URLS = [
    "https://ipage.kesug.com/",
    "https://ipage.byethost18.com/",
]

BROWSER_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/131.0.0.0 Safari/537.36"
)
BOT_UA = "Googlebot/2.1 (+http://www.google.com/bot.html)"

MAX_BYTES = 2 * 1024 * 1024

# 挑战页：var a=toNumbers(".."),b=toNumbers(".."),c=toNumbers("..");
CHALLENGE_RE = re.compile(
    r'toNumbers\("([0-9a-fA-F]{32})"\)\s*,\s*'
    r'b\s*=\s*toNumbers\("([0-9a-fA-F]{32})"\)\s*,\s*'
    r'c\s*=\s*toNumbers\("([0-9a-fA-F]{32})"\)'
)
TITLE_RE = re.compile(r"<title[^>]*>(.*?)</title>", re.I | re.S)


# --------------------------------------------------------------------------
# AES-128-CBC（纯 Python，只用于解挑战页里那一个 16 字节分组）
# --------------------------------------------------------------------------

def _gmul(a, b):
    """GF(2^8) 乘法，AES 多项式 0x11b。"""
    p = 0
    for _ in range(8):
        if b & 1:
            p ^= a
        hi = a & 0x80
        a = (a << 1) & 0xFF
        if hi:
            a ^= 0x1B
        b >>= 1
    return p


def _rotl8(x, n):
    return ((x << n) | (x >> (8 - n))) & 0xFF


def _build_aes_tables():
    exp = [0] * 512
    log = [0] * 256
    x = 1
    for i in range(255):
        exp[i] = x
        log[x] = i
        x = _gmul(x, 3)
    for i in range(255, 512):
        exp[i] = exp[i - 255]

    inv = [0] * 256
    for a in range(1, 256):
        inv[a] = exp[255 - log[a]]

    sbox = [0] * 256
    inv_sbox = [0] * 256
    for a in range(256):
        b = inv[a]
        s = b ^ _rotl8(b, 1) ^ _rotl8(b, 2) ^ _rotl8(b, 3) ^ _rotl8(b, 4) ^ 0x63
        sbox[a] = s
        inv_sbox[s] = a
    return sbox, inv_sbox


SBOX, INV_SBOX = _build_aes_tables()


def _expand_key(key):
    w = [list(key[i:i + 4]) for i in range(0, 16, 4)]
    rcon = 1
    for i in range(4, 44):
        t = w[i - 1][:]
        if i % 4 == 0:
            t = t[1:] + t[:1]
            t = [SBOX[b] for b in t]
            t[0] ^= rcon
            rcon = _gmul(rcon, 2)
        w.append([w[i - 4][j] ^ t[j] for j in range(4)])
    return [sum(w[4 * r:4 * r + 4], []) for r in range(11)]


def _add_round_key(state, round_key):
    for i in range(16):
        state[i] ^= round_key[i]


def _inv_shift_rows(s):
    s[1], s[5], s[9], s[13] = s[13], s[1], s[5], s[9]
    s[2], s[6], s[10], s[14] = s[10], s[14], s[2], s[6]
    s[3], s[7], s[11], s[15] = s[7], s[11], s[15], s[3]


def _inv_mix_columns(s):
    for c in range(4):
        i = 4 * c
        a0, a1, a2, a3 = s[i], s[i + 1], s[i + 2], s[i + 3]
        s[i] = _gmul(a0, 14) ^ _gmul(a1, 11) ^ _gmul(a2, 13) ^ _gmul(a3, 9)
        s[i + 1] = _gmul(a0, 9) ^ _gmul(a1, 14) ^ _gmul(a2, 11) ^ _gmul(a3, 13)
        s[i + 2] = _gmul(a0, 13) ^ _gmul(a1, 9) ^ _gmul(a2, 14) ^ _gmul(a3, 11)
        s[i + 3] = _gmul(a0, 11) ^ _gmul(a1, 13) ^ _gmul(a2, 9) ^ _gmul(a3, 14)


def aes128_decrypt_block(block, key):
    if len(block) != 16 or len(key) != 16:
        raise ValueError("AES-128 需要 16 字节的明文分组和密钥")
    round_keys = _expand_key(key)
    s = list(block)
    _add_round_key(s, round_keys[10])
    for r in range(9, 0, -1):
        _inv_shift_rows(s)
        for i in range(16):
            s[i] = INV_SBOX[s[i]]
        _add_round_key(s, round_keys[r])
        _inv_mix_columns(s)
    _inv_shift_rows(s)
    for i in range(16):
        s[i] = INV_SBOX[s[i]]
    _add_round_key(s, round_keys[0])
    return bytes(s)


def aes128_cbc_decrypt_block(ciphertext, key, iv):
    """CBC 模式下解密单个分组：P1 = Dec(C1) xor IV。"""
    return bytes(a ^ b for a, b in zip(aes128_decrypt_block(ciphertext, key), iv))


# --------------------------------------------------------------------------
# HTTP
# --------------------------------------------------------------------------

def _is_challenge(body):
    return b"slowAES" in body or b"__test=" in body


def _title(body):
    m = TITLE_RE.search(body.decode("utf-8", "replace"))
    if not m:
        return ""
    return re.sub(r"\s+", " ", m.group(1)).strip()


def _solve_challenge(body):
    m = CHALLENGE_RE.search(body.decode("utf-8", "replace"))
    if not m:
        raise RuntimeError("挑战页里找不到 a/b/c 参数")
    a, b, c = (bytes.fromhex(x) for x in m.groups())
    return aes128_cbc_decrypt_block(c, a, b).hex()


def _set_test_cookie(jar, host, token, secure):
    jar.set_cookie(http.cookiejar.Cookie(
        version=0,
        name="__test",
        value=token,
        port=None,
        port_specified=False,
        domain=host,
        domain_specified=True,
        domain_initial_dot=False,
        path="/",
        path_specified=True,
        secure=secure,
        expires=None,
        discard=False,
        comment=None,
        comment_url=None,
        rest={},
        rfc2109=False,
    ))


def _make_opener(jar, insecure):
    ctx = ssl.create_default_context()
    if insecure:
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    return urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(jar),
        urllib.request.HTTPSHandler(context=ctx),
    )


def _get(opener, url, ua, timeout):
    req = urllib.request.Request(url, headers={
        "User-Agent": ua,
        "Accept": ("text/html,application/xhtml+xml,application/xml;q=0.9,"
                   "image/avif,image/webp,*/*;q=0.8"),
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        "Upgrade-Insecure-Requests": "1",
        "Connection": "close",
    })
    try:
        with opener.open(req, timeout=timeout) as resp:
            return resp.status, resp.geturl(), resp.read(MAX_BYTES)
    except urllib.error.HTTPError as exc:
        try:
            body = exc.read(MAX_BYTES)
        except Exception:
            body = b""
        return exc.code, exc.geturl() or url, body


def _visit_with_ua(base, host, scheme, ua, timeout, insecure, use_challenge):
    """一次完整访问。use_challenge=False 时只做直连（Googlebot 兜底）。"""
    jar = http.cookiejar.CookieJar()
    opener = _make_opener(jar, insecure)

    status, final, body = _get(opener, base, ua, timeout)
    if _is_challenge(body):
        if not use_challenge:
            raise RuntimeError("仍然拿到 JS 挑战页")
        token = _solve_challenge(body)
        _set_test_cookie(jar, host, token, scheme == "https")
        retry_url = base + ("&i=1" if "?" in base else "?i=1")
        status, final, body = _get(opener, retry_url, ua, timeout)
        if _is_challenge(body):
            raise RuntimeError("__test cookie 未被接受，仍是挑战页")
        via = "challenge"
    else:
        if status >= 400:
            raise RuntimeError("HTTP %s" % status)
        via = "direct"

    if status >= 400:
        raise RuntimeError("HTTP %s" % status)
    if len(body) < 200:
        raise RuntimeError("响应过短（%d 字节）" % len(body))
    return status, final, body, via


def visit(url, timeout, retries, retry_delay, ua, insecure, bot_fallback):
    started = time.time()
    parsed = urllib.parse.urlsplit(url)
    host = parsed.hostname
    if not host:
        return _result(url, False, error="URL 无法解析")

    schemes = [parsed.scheme or "https"]
    schemes.append("http" if schemes[0] == "https" else "https")
    errors = []

    path = parsed.path or "/"
    for scheme in schemes:
        base = "%s://%s%s" % (scheme, parsed.netloc, path)
        for attempt in range(1, retries + 2):
            try:
                status, final, body, via = _visit_with_ua(
                    base, host, scheme, ua, timeout, insecure, use_challenge=True
                )
                return _result(url, True, status=status, final=final, body=body,
                               via=via, elapsed=time.time() - started)
            except Exception as exc:  # noqa: BLE001 - 网络异常种类多，统一记录
                errors.append("%s try%d: %s: %s" % (scheme, attempt, type(exc).__name__, exc))
                if attempt <= retries:
                    time.sleep(retry_delay * attempt)

    # 兜底：Googlebot UA 会被直接放行到真实页面
    if bot_fallback:
        for scheme in schemes:
            base = "%s://%s%s" % (scheme, parsed.netloc, path)
            try:
                status, final, body, _ = _visit_with_ua(
                    base, host, scheme, BOT_UA, timeout, insecure, use_challenge=False
                )
                return _result(url, True, status=status, final=final, body=body,
                               via="googlebot", elapsed=time.time() - started)
            except Exception as exc:  # noqa: BLE001
                errors.append("%s googlebot: %s: %s" % (scheme, type(exc).__name__, exc))

    return _result(url, False, elapsed=time.time() - started,
                   error=" | ".join(errors[-4:]))


def _result(url, ok, status=None, final=None, body=b"", via=None,
            elapsed=0.0, error=None):
    return {
        "url": url,
        "host": urllib.parse.urlsplit(url).hostname,
        "ok": ok,
        "status": status,
        "final_url": final,
        "bytes": len(body) if body else 0,
        "title": _title(body) if body else "",
        "via": via,
        "elapsed_sec": round(elapsed, 2),
        "error": error,
    }


def _timestamp(tz_name):
    if ZoneInfo is not None:
        try:
            return datetime.now(ZoneInfo(tz_name)).strftime("%Y-%m-%d %H:%M:%S %Z")
        except Exception:
            pass
    return datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S%z")


def _print_human(results, tz_name):
    ts = _timestamp(tz_name)
    for r in results:
        if r["ok"]:
            print("%s OK   %-22s via=%-9s http=%s bytes=%-5d %.1fs title=%r" % (
                ts, r["host"], r["via"], r["status"], r["bytes"],
                r["elapsed_sec"], r["title"],
            ))
        else:
            print("%s FAIL %-22s %s" % (ts, r["host"], r["error"]))


def main(argv=None):
    p = argparse.ArgumentParser(description="每天访问一次 ipage 站点（含 JS 挑战）")
    p.add_argument("--url", action="append", dest="urls", metavar="URL",
                   help="要访问的地址，可重复；默认访问两个 ipage 站点")
    p.add_argument("--timeout", type=float, default=20.0, help="单次请求超时秒数（默认 20）")
    p.add_argument("--retries", type=int, default=2, help="每个地址的重试次数（默认 2）")
    p.add_argument("--retry-delay", type=float, default=3.0, help="重试退避基数秒（默认 3）")
    p.add_argument("--ua", default=BROWSER_UA, help="浏览器 User-Agent")
    p.add_argument("--insecure", action="store_true", help="跳过 HTTPS 证书校验")
    p.add_argument("--no-bot-fallback", action="store_true", help="禁用 Googlebot UA 兜底")
    p.add_argument("--tz", default="Asia/Shanghai", help="日志时区（默认 Asia/Shanghai）")
    p.add_argument("--json", action="store_true", help="以 JSON 输出")
    args = p.parse_args(argv)

    urls = args.urls or DEFAULT_URLS
    results = [
        visit(u, args.timeout, max(0, args.retries), args.retry_delay,
              args.ua, args.insecure, not args.no_bot_fallback)
        for u in urls
    ]

    if args.json:
        print(json.dumps(results, ensure_ascii=False, indent=2))
    else:
        _print_human(results, args.tz)
        ok = sum(1 for r in results if r["ok"])
        print("---- %d/%d 成功" % (ok, len(results)))

    return 0 if all(r["ok"] for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
