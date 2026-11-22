#!/usr/bin/env bash
# 安装 ipage-visit：把脚本放到 /opt/ipage-visit，并在 RunWisp 里注册每日任务。
#
# 需要 root：
#   - 写 /opt
#   - 改 /etc/runwisp/runwisp.toml
#   - 以 runwisp 身份 reload（RunWisp 的 unix socket 只认同 uid）
#
# 用法：
#   sudo bash install.sh
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SRC_DIR/visit_blog.py"
DEST_DIR="/opt/ipage-visit"
DEST="$DEST_DIR/visit_blog.py"
CONF="/etc/runwisp/runwisp.toml"

if [ "$(id -u)" -ne 0 ]; then
    echo "需要 root：sudo bash $0" >&2
    exit 1
fi
if [ ! -f "$SRC" ]; then
    echo "找不到 $SRC" >&2
    exit 1
fi
if [ ! -f "$CONF" ]; then
    echo "找不到 RunWisp 配置 $CONF" >&2
    exit 1
fi

echo "==> 安装脚本到 $DEST_DIR"
install -d -o runwisp -g runwisp -m 755 "$DEST_DIR"
chown runwisp:runwisp "$DEST_DIR"
if [ "$SRC" != "$DEST" ]; then
    install -o runwisp -g runwisp -m 755 "$SRC" "$DEST"
fi

echo "==> 注册 RunWisp 任务 ipage-visit"
if grep -q '^\[tasks\.ipage-visit\]' "$CONF"; then
    echo "    任务已存在，跳过"
else
    cp -a "$CONF" "$CONF.bak.$(date +%s)"
    cat >> "$CONF" <<'TOML'

[tasks.ipage-visit]
description = "每天访问 ipage 两个站点"
cron        = "17 9 * * *"
timezone    = "Asia/Shanghai"
on_overlap  = "skip"
catch_up    = 1
timeout     = "3m"
keep_runs   = 90
run         = "/usr/bin/python3 /opt/ipage-visit/visit_blog.py"
TOML
    echo "    已追加到 $CONF（原文件已备份）"
fi

echo "==> 校验配置"
runwisp validate -c "$CONF"

# CLI 必须用 runwisp 身份，并显式指定配置和数据目录：
# socket 只认同 uid，且非 root 默认数据目录是 ~/.runwisp。
rw() {
    runuser -u runwisp -- /usr/local/bin/runwisp -c "$CONF" --data /var/lib/runwisp "$@"
}

echo "==> 让 RunWisp 重新加载"
if rw reload; then
    echo "    reload 完成"
else
    echo "    reload 失败，改用 restart"
    systemctl restart runwisp
    sleep 2
fi

echo "==> 立即执行一次"
run_ok=1
if ! rw run ipage-visit; then
    run_ok=0
    echo "    首次运行失败；任务已注册，可按下面的命令重试" >&2
fi

echo
echo "完成。任务状态："
rw list

if [ "$run_ok" -eq 0 ]; then
    echo "注意：首次运行失败，请检查 /var/lib/runwisp/logs/ipage-visit/" >&2
    exit 1
fi
