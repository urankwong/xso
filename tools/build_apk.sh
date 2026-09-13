#!/usr/bin/env bash
# 打包脚本（xso）：自动递增 build number → 构建 → 带版本命名 → 备份 NAS
#
# 为什么要递增 build number：
#   Android 用 versionCode 判断"是否同一个包"。pubspec 里若只有 `0.1.0`
#   而没有 `+N`，flutter.versionCode 恒为 1，每次装机都会提示"已安装"，
#   部分机型（尤其国产 ROM）会直接拒绝覆盖安装。本脚本每次构建自动 +1。
#
# 用法：
#   tools/build_apk.sh              # release 包 + 备份到 NAS
#   tools/build_apk.sh --debug      # debug 包（可接调试页，用于真机排查）
#   tools/build_apk.sh --no-backup  # 只构建，不备份
#   tools/build_apk.sh --no-bump    # 不改 build number（重复构建同一版本）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/app"
PUBSPEC="$APP/pubspec.yaml"
FLUTTER=/d/flutter/bin/flutter
NAS_DIR="/n/软件备份/xso"

MODE=release
DO_BACKUP=1
DO_BUMP=1
for a in "$@"; do
  case "$a" in
    --debug) MODE=debug ;;
    --release) MODE=release ;;
    --no-backup) DO_BACKUP=0 ;;
    --no-bump) DO_BUMP=0 ;;
    *) echo "未知参数: $a"; exit 1 ;;
  esac
done

# ---- 1) 递增 build number ----
CUR=$(grep -E '^version:' "$PUBSPEC" | head -1 | sed 's/^version:[[:space:]]*//')
VER_NAME="${CUR%%+*}"
if [ "$CUR" = "$VER_NAME" ]; then
  CUR_CODE=0
else
  CUR_CODE="${CUR##*+}"
fi
NEW_CODE=$CUR_CODE
if [ "$DO_BUMP" = "1" ]; then
  NEW_CODE=$((CUR_CODE + 1))
  sed -i "s/^version: .*/version: ${VER_NAME}+${NEW_CODE}/" "$PUBSPEC"
  echo "build number: ${CUR_CODE} → ${NEW_CODE}"
else
  echo "build number: ${CUR_CODE}（未递增）"
fi

# ---- 2) 构建 ----
cd "$APP"
if [ "$MODE" = "debug" ]; then
  "$FLUTTER" build apk --debug
  SRC="$APP/build/app/outputs/flutter-apk/app-debug.apk"
else
  "$FLUTTER" build apk --release
  SRC="$APP/build/app/outputs/flutter-apk/app-release.apk"
fi

if [ ! -f "$SRC" ]; then
  echo "构建产物不存在: $SRC"; exit 1
fi

# ---- 3) 带版本命名 ----
MMDD=$(date +%m%d)
OUT_NAME="xso-${MODE}-${VER_NAME}-b${NEW_CODE}-${MMDD}.apk"
OUT="$APP/build/app/outputs/flutter-apk/$OUT_NAME"
cp "$SRC" "$OUT"
# 注意：本脚本变量是 MSYS 路径（/d/...），不能直接喂给 Windows 的 python.exe
# （它不认 /d/ 前缀，会 FileNotFoundError）。统一用 MSYS 自带的 md5sum/du。
SIZE=$(du -m "$OUT" 2>/dev/null | cut -f1)
echo "产物: $OUT (${SIZE} MB)"

# ---- 4) 备份到 NAS ----
if [ "$DO_BACKUP" = "1" ]; then
  if [ -d "$NAS_DIR" ]; then
    cp "$OUT" "$NAS_DIR/$OUT_NAME"
    # 复制后校验 MD5，避免网络盘写入不完整
    echo "NAS 备份: $NAS_DIR/$OUT_NAME"
    MD5A=$(md5sum "$OUT" | awk '{print $1}')
    MD5B=$(md5sum "$NAS_DIR/$OUT_NAME" | awk '{print $1}')
    echo "MD5: $MD5A"
    if [ "$MD5A" = "$MD5B" ]; then
      echo "校验一致: 是"
    else
      echo "校验不一致（NAS 写入可能不完整）: $MD5B"; exit 1
    fi
  else
    echo "NAS 目录不可用（$NAS_DIR，检查 N: 盘映射），跳过备份"
  fi
fi

echo "完成。"
