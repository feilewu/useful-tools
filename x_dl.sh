#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
用法: $0 <推文URL> <输出路径>

  推文URL    : 例如 https://x.com/user/status/1234567890
  输出路径   : 目录 + 文件名，例如 /data/videos/clip.mp4 或 ./clip
               文件名可带可不带扩展名，最终扩展名由实际格式决定

Cookie 文件:
  默认读取脚本同目录下的 x.com_cookies.txt
  也可用环境变量覆盖: YTDLP_COOKIES=/path/to/cookies.txt $0 ...

依赖: yt-dlp（必需）, ffmpeg（可选，用于合并最高画质音视频）
EOF
  exit 1
}

[ $# -eq 2 ] || usage

URL="$1"
OUT_PATH="$2"

command -v yt-dlp >/dev/null 2>&1 || { echo "错误: 未找到 yt-dlp，请先安装"; exit 1; }

# ---------- 定位脚本所在目录（绝对路径） ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- 解析输出路径 ----------
OUT_DIR="$(dirname "$OUT_PATH")"
OUT_BASE="$(basename "$OUT_PATH")"

# 如果用户给了已知视频扩展名，去掉它，剩下的作为 stem
STEM="$OUT_BASE"
for ext in mp4 mkv webm mov flv m4v; do
  if [[ "$OUT_BASE" == *."$ext" ]]; then
    STEM="${OUT_BASE%.*}"
    break
  fi
done
[ -n "$STEM" ] || { echo "错误: 输出文件名为空"; exit 1; }

mkdir -p "$OUT_DIR"

# ---------- Cookie 逻辑 ----------
# 优先级：环境变量 YTDLP_COOKIES > 脚本同目录 x.com_cookies.txt
COOKIE_FILE=""
if [[ -n "${YTDLP_COOKIES:-}" ]]; then
  COOKIE_FILE="$YTDLP_COOKIES"
elif [[ -f "$SCRIPT_DIR/x.com_cookies.txt" ]]; then
  COOKIE_FILE="$SCRIPT_DIR/x.com_cookies.txt"
fi

COOKIE_ARGS=()
if [[ -n "$COOKIE_FILE" ]]; then
  if [[ ! -f "$COOKIE_FILE" ]]; then
    echo "错误: 指定的 Cookie 文件不存在: $COOKIE_FILE"
    exit 1
  fi
  if [[ ! -r "$COOKIE_FILE" ]]; then
    echo "错误: Cookie 文件不可读: $COOKIE_FILE"
    exit 1
  fi
  COOKIE_ARGS=(--cookies "$COOKIE_FILE")
  echo "🍪 使用 Cookie 文件: $COOKIE_FILE"
else
  echo "ℹ️  未找到 Cookie 文件，将以匿名身份下载"
  echo "    如需登录，请把 x.com_cookies.txt 放到: $SCRIPT_DIR/x.com_cookies.txt"
fi

# ---------- 根据 ffmpeg 是否存在选择格式策略 ----------
if command -v ffmpeg >/dev/null 2>&1; then
  # 有 ffmpeg：分别取最佳视频轨 + 最佳音频轨再合并，分辨率最高
  FORMAT="bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best[ext=mp4]/best"
  MERGE_ARGS=(--merge-output-format mp4)
else
  # 没 ffmpeg：只能下单文件（通常已合并，但画质可能不是最高）
  FORMAT="best[ext=mp4]/best"
  MERGE_ARGS=()
  echo "⚠️  未找到 ffmpeg，将下载单文件格式（可能不是最高分辨率）"
  echo "    建议: apt install -y ffmpeg  或  apk add ffmpeg"
fi

# ---------- 开始下载 ----------
echo
echo "URL      : $URL"
echo "输出模板 : $OUT_DIR/$STEM.%(ext)s"
echo "开始下载..."
echo

yt-dlp \
  -f "$FORMAT" \
  "${MERGE_ARGS[@]}" \
  --no-playlist \
  -o "$OUT_DIR/$STEM.%(ext)s" \
  "${COOKIE_ARGS[@]}" \
  "$URL"

echo
echo "✅ 完成。实际输出文件："
ls -lh "$OUT_DIR/$STEM".* 2>/dev/null || true
