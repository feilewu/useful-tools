#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""在指定的时间窗内均匀下载约 1 GiB 流量，跑完自动退出。

下载源默认是华为云镜像站上的一个大文件（Ubuntu 软件包，约 475 MiB），
数据边下边丢、不占磁盘；按「配额 ÷ 窗口剩余秒数」限速，流量均匀摊满整个
时间窗。文件下完还没到配额时，会从头再下一遍。

配合 cron 每天在窗口开始时跑一次即可：
    0 1 * * * /usr/bin/python3 /path/to/idle_traffic.py --window 01:00-07:00 --quota 1G

示例：
    python3 idle_traffic.py                          # 01:00-07:00 下载 1 GiB
    python3 idle_traffic.py --window 23:00-06:00 --quota 2G
    python3 idle_traffic.py --url https://.../xxx.iso
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from datetime import datetime, time as dtime, timedelta
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

# 华为云镜像站上的大文件；也可以用 --url 换成任意直链
DEFAULT_URL = (
    "https://mirrors.huaweicloud.com/ubuntu/pool/main/l/linux-firmware/"
    "linux-firmware_20240318.git3b128b60-0ubuntu2_amd64.deb"
)

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) idle-traffic/1.0"
CHUNK = 64 * 1024          # 每次读取的字节数
LOG_INTERVAL = 30.0        # 进度日志间隔（秒）
RETRY_WAIT = 30.0          # 网络出错后的重试间隔（秒）


def log(message: str) -> None:
    print(time.strftime("[%H:%M:%S] ") + message, flush=True)


def human_size(n: float) -> str:
    for unit in ("B", "KiB", "MiB", "GiB"):
        if abs(n) < 1024 or unit == "GiB":
            return f"{int(n)} B" if unit == "B" else f"{n:.2f} {unit}"
        n /= 1024
    return f"{n:.2f} GiB"  # pragma: no cover


def parse_size(text: str) -> int:
    """把 '1G' / '500M' / '1GiB' / '1024' 解析成字节数（1024 进制）。"""
    match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*([KMGTP]?)(?:i?B)?\s*", text, re.I)
    if not match:
        raise ValueError(f"无法识别的容量: {text!r}")
    units = {"": 1, "K": 1024, "M": 1024 ** 2, "G": 1024 ** 3,
             "T": 1024 ** 4, "P": 1024 ** 5}
    return int(float(match.group(1)) * units[match.group(2).upper()])


def parse_window(text: str) -> tuple[int, int]:
    """把 '01:00-07:00' 解析成当天分钟数，允许跨午夜。"""
    match = re.fullmatch(r"\s*(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})\s*", text)
    if not match:
        raise ValueError(f"时间窗格式应为 HH:MM-HH:MM，收到 {text!r}")
    sh, sm, eh, em = (int(x) for x in match.groups())
    if sh > 23 or eh > 23 or sm > 59 or em > 59:
        raise ValueError(f"时间窗中的时间不合法: {text!r}")
    if sh * 60 + sm == eh * 60 + em:
        raise ValueError("时间窗的起止时间不能相同")
    return sh * 60 + sm, eh * 60 + em


def window_for(now: datetime, start_min: int, end_min: int) -> tuple[datetime, datetime]:
    """返回「本次」时间窗的起止时间。"""
    today = now.date()

    def at(day, minutes):
        return datetime.combine(day, dtime(minutes // 60, minutes % 60))

    if start_min < end_min:                       # 当天内，如 01:00-07:00
        return at(today, start_min), at(today, end_min)
    if now < at(today, end_min):                  # 跨午夜，如 23:00-06:00
        return at(today - timedelta(days=1), start_min), at(today, end_min)
    return at(today, start_min), at(today + timedelta(days=1), end_min)


def sleep_until(target: datetime) -> None:
    while True:
        seconds = (target - datetime.now()).total_seconds()
        if seconds <= 0:
            return
        time.sleep(seconds)


def download(url: str, quota: int, deadline: float, rate: float) -> int:
    """匀速下载，直到下满 quota 或到达 deadline（monotonic），返回实际字节数。"""
    sent = 0
    started = time.monotonic()
    last_log = started

    while sent < quota:
        if time.monotonic() >= deadline:
            break
        request = Request(url, headers={
            "User-Agent": USER_AGENT,
            "Accept": "*/*",
            "Accept-Encoding": "identity",
        })
        try:
            with urlopen(request, timeout=30) as response:
                while sent < quota:
                    if time.monotonic() >= deadline:
                        return sent
                    data = response.read(min(CHUNK, quota - sent))
                    if not data:          # 文件下完了，从头再下一遍
                        break
                    sent += len(data)

                    # 按平均速率限速：比计划快了就睡一会儿
                    due = started + sent / rate
                    now = time.monotonic()
                    if due > now:
                        time.sleep(max(0.0, min(due - now, deadline - now)))

                    now = time.monotonic()
                    if now - last_log >= LOG_INTERVAL:
                        last_log = now
                        elapsed = now - started
                        speed = sent / elapsed if elapsed > 0 else 0
                        log(f"已下载 {human_size(sent)} / {human_size(quota)}"
                            f"（{100 * sent / quota:.1f}%），均速 {human_size(speed)}/s")
        except HTTPError as exc:
            if exc.code in (403, 404, 410, 418):
                log(f"下载出错：{exc}；该下载源不可用，退出（可换 --url）")
                break
            if time.monotonic() >= deadline:
                break
            log(f"下载出错：{exc}；{RETRY_WAIT:.0f} 秒后重试")
            time.sleep(max(0.0, min(RETRY_WAIT, deadline - time.monotonic())))
        except (URLError, OSError, ValueError) as exc:
            if time.monotonic() >= deadline:
                break
            log(f"下载出错：{exc}；{RETRY_WAIT:.0f} 秒后重试")
            time.sleep(max(0.0, min(RETRY_WAIT, deadline - time.monotonic())))
    return sent


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="在指定时间窗内均匀下载约 1 GiB 流量（华为云镜像站）。",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--window", default="01:00-07:00",
                        help="下载时间窗 HH:MM-HH:MM，支持跨午夜")
    parser.add_argument("--quota", default="1G",
                        help="本次下载总量，如 1G / 800M（1024 进制）")
    parser.add_argument("--url", default=DEFAULT_URL,
                        help="下载直链")
    args = parser.parse_args(argv)

    try:
        start_min, end_min = parse_window(args.window)
        quota = parse_size(args.quota)
        if quota <= 0:
            raise ValueError("配额必须大于 0")
    except ValueError as exc:
        log(f"参数错误：{exc}")
        return 2

    now = datetime.now()
    start_at, end_at = window_for(now, start_min, end_min)
    if now >= end_at:
        log(f"时间窗 {args.window} 今天已经结束，退出")
        return 0
    if now < start_at:
        wait = (start_at - now).total_seconds()
        if wait > 300:
            log(f"还没到时间窗（{start_at:%m-%d %H:%M} 开始），退出")
            return 0
        log(f"马上到时间窗，等到 {start_at:%H:%M} 开始")
        sleep_until(start_at)

    remaining = (end_at - datetime.now()).total_seconds()
    if remaining <= 0:
        log("时间窗已结束，退出")
        return 0

    rate = quota / remaining
    log(f"时间窗 {start_at:%H:%M}-{end_at:%H:%M}，还剩 {remaining / 3600:.2f} 小时，"
        f"配额 {human_size(quota)}，目标速率 {human_size(rate)}/s")
    log(f"下载源：{args.url}")

    sent = 0
    try:
        sent = download(args.url, quota, time.monotonic() + remaining, rate)
    except KeyboardInterrupt:
        log("已中断")
        return 130
    finally:
        log(f"本次共下载 {human_size(sent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
