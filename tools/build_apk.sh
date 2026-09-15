#!/usr/bin/env bash
# 打包脚本（xso）：自动递增 build number → 构建 → 带版本命名 → 备份 NAS
#
# 为什么要递增 build number：
#   Android 用 versionCode 判断"是否同一个包"。**同 versionCode 覆盖安装时，
#   部分机型（尤其国产 ROM，如 vivo/OriginOS）会直接报
#   「软件包与现有软件包存在冲突」拒绝安装**（2026-09-15 实测踩坑）。
#   本脚本每次构建自动 +1，保证新包 versionCode 恒高于已装版本。
#   （配合 gradle.properties 的 force-version-code-ignoring-abi=true：
#    split 包不再抬 base+1000*ABI、versionCode 恒等于 build 号，
#    因此"换 ABI / universal↔split 换形态"也必须靠递增 build 号来走升级
#    路径 —— 所以分发用包**禁止**用 --no-bump 构建。）
#
# 用法：
#   tools/build_apk.sh              # release universal 包（含三 ABI，约 80MB）+ 备份 NAS
#   tools/build_apk.sh --split      # release 按 ABI 拆分（arm64 约 27MB，真机推荐）
#   tools/build_apk.sh --debug      # debug 包（可接调试页，用于真机排查）
#   tools/build_apk.sh --no-backup  # 只构建，不备份
#   tools/build_apk.sh --no-bump    # 不改 build number（仅重复构建自测用，勿分发）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/app"
PUBSPEC="$APP/pubspec.yaml"
FLUTTER=/d/flutter/bin/flutter
NAS_DIR="/n/软件备份/xso"

MODE=release
SPLIT=0
DO_BACKUP=1
DO_BUMP=1
for a in "$@"; do
  case "$a" in
    --debug) MODE=debug ;;
    --release) MODE=release ;;
    --split) SPLIT=1 ;;
    --no-backup) DO_BACKUP=0 ;;
    --no-bump) DO_BUMP=0 ;;
    *) echo "未知参数: $a"; exit 1 ;;
  esac
done
if [ "$MODE" = "debug" ] && [ "$SPLIT" = "1" ]; then
  echo "--split 仅支持 release 构建，已忽略"
  SPLIT=0
fi

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
else
  if [ "$SPLIT" = "1" ]; then
    "$FLUTTER" build apk --release --split-per-abi
  else
    "$FLUTTER" build apk --release
  fi
fi

# ---- 3) 带版本命名（split 时按 ABI 各命名一份）----
MMDD=$(date +%m%d)
OUTS=()
if [ "$MODE" = "release" ] && [ "$SPLIT" = "1" ]; then
  for ABI in arm64-v8a armeabi-v7a x86_64; do
    SRC="$APP/build/app/outputs/flutter-apk/app-${ABI}-release.apk"
    if [ ! -f "$SRC" ]; then
      echo "构建产物不存在: $SRC"; exit 1
    fi
    OUT="$APP/build/app/outputs/flutter-apk/xso-${MODE}-${VER_NAME}-b${NEW_CODE}-${ABI}-${MMDD}.apk"
    cp "$SRC" "$OUT"
    OUTS+=("$OUT")
  done
else
  if [ "$MODE" = "debug" ]; then
    SRC="$APP/build/app/outputs/flutter-apk/app-debug.apk"
  else
    SRC="$APP/build/app/outputs/flutter-apk/app-release.apk"
  fi
  if [ ! -f "$SRC" ]; then
    echo "构建产物不存在: $SRC"; exit 1
  fi
  OUT="$APP/build/app/outputs/flutter-apk/xso-${MODE}-${VER_NAME}-b${NEW_CODE}-${MMDD}.apk"
  cp "$SRC" "$OUT"
  OUTS+=("$OUT")
fi
# 注意：本脚本变量是 MSYS 路径（/d/...），不能直接喂给 Windows 的 python.exe
# （它不认 /d/ 前缀，会 FileNotFoundError）。统一用 MSYS 自带的 md5sum/du。
for OUT in "${OUTS[@]}"; do
  SIZE=$(du -m "$OUT" 2>/dev/null | cut -f1)
  echo "产物: $OUT (${SIZE} MB)"
done

# ---- 4) 备份到 NAS ----
if [ "$DO_BACKUP" = "1" ]; then
  if [ -d "$NAS_DIR" ]; then
    for OUT in "${OUTS[@]}"; do
      NAME=$(basename "$OUT")
      cp "$OUT" "$NAS_DIR/$NAME"
      # 复制后校验 MD5，避免网络盘写入不完整
      echo "NAS 备份: $NAS_DIR/$NAME"
      MD5A=$(md5sum "$OUT" | awk '{print $1}')
      MD5B=$(md5sum "$NAS_DIR/$NAME" | awk '{print $1}')
      echo "MD5: $MD5A"
      if [ "$MD5A" = "$MD5B" ]; then
        echo "校验一致: 是"
      else
        echo "校验不一致（NAS 写入可能不完整）: $MD5B"; exit 1
      fi
    done
  else
    echo "NAS 目录不可用（$NAS_DIR，检查 N: 盘映射），跳过备份"
  fi
fi

echo "完成。"
