#!/bin/bash
# dxmonitor バイナリ・ビルド（PyInstaller 単一実行ファイル）
#   使い方:  ./build_bin.sh [ソースの場所] [all|core|hotspot|settings|final]
#     例:    ./build_bin.sh ~/DXmonitor-main
#            ./build_bin.sh ~/DXmonitor-main core
#   ソースの場所を省くと、このスクリプトと同じ場所から探す（DXmonitor-main / DXmonitor / . の順）。
#
#   作るもの（dist/ に出る）
#     dstar-live         本体（dxmcore）
#     dxhotspot          ホットスポット（OLED・Wi-Fi・443 の統合画面）
#     dxhotspot_settings インストーラが使う設定ツール（settings.py）
#     dxhotspot_final    電源断メッセージ（任意。all には含めない）
#
#   ※ 実行する機械と同じ CPU・OS でビルドすること（Pi Zero 2 W は arm64・64bit OS）。
#   ※ /opt・systemd・既存のサービスには触らない。ビルドは作業フォルダの中だけ。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-}"
if [ -z "$ROOT" ] || [ "$ROOT" = all ] || [ "$ROOT" = core ] || [ "$ROOT" = hotspot ] || [ "$ROOT" = settings ] || [ "$ROOT" = final ]; then
  WHAT="${1:-all}"
  for d in "$HERE/DXmonitor-main" "$HERE/DXmonitor" "$HERE"; do
    [ -d "$d/dxmcore/source" ] && { ROOT="$d"; break; }
  done
else
  WHAT="${2:-all}"
fi
[ -n "${ROOT:-}" ] && [ -d "$ROOT/dxmcore/source" ] || {
  echo "ソースが見つかりません。第 1 引数で場所を指定してください（例: $0 ~/DXmonitor-main）"; exit 1; }
ROOT="$(cd "$ROOT" && pwd)"
SRC="$ROOT/dxmcore/source"
APP="$ROOT/dxhotspot/app"
[ -f "$SRC/live.py" ] || { echo "$SRC/live.py がありません"; exit 1; }
[ -f "$APP/hotspotd.py" ] || { echo "$APP/hotspotd.py がありません"; exit 1; }

BUILD=$(sed -n 's/^BUILD *= *"\([^"]*\)".*/\1/p' "$SRC/live.py" | head -1)
OUT="$HERE/dxm_build"
echo "ソース: $ROOT"
echo "版:     ${BUILD:-不明}"
echo "作業先: $OUT"

# メモリが少ない機械の注意（Pi Zero 2 W は zram だけだと足りない）
MEM_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
REAL_SWAP=$(awk '$2=="file"||$2=="partition"{ if ($1 !~ /zram/) s+=$3 } END{print int(s/1024)}' /proc/swaps 2>/dev/null || echo 0)
if [ "$MEM_MB" -lt 1000 ] && [ "${REAL_SWAP:-0}" -lt 900 ]; then
  echo
  echo "注意: メモリ ${MEM_MB}MB、zram 以外の swap ${REAL_SWAP:-0}MB。途中で止まる可能性があります。"
  echo "      先に swap を 1GB 作ってください:"
  echo "        sudo fallocate -l 1G /swapfile && sudo chmod 600 /swapfile"
  echo "        sudo mkswap /swapfile && sudo swapon /swapfile"
  echo "      （終わったら sudo swapoff /swapfile && sudo rm -f /swapfile）"
  echo
  printf "このまま続けますか [y/N]: "; read -r a || true
  case "${a:-N}" in [Yy]*) ;; *) echo "中止しました"; exit 1;; esac
fi

mkdir -p "$OUT"
# 専用 venv（システムの python には入れない）
# apt で入る python3-smbus（OLED の I2C）は pip に無いので、システムの site-packages を見せる
if [ ! -d "$OUT/.venv" ]; then python3 -m venv --system-site-packages "$OUT/.venv"; fi
# shellcheck disable=SC1091
. "$OUT/.venv/bin/activate"
python -m pip install --upgrade pip >/dev/null
python -m pip install pyinstaller >/dev/null
[ "$WHAT" = core ] || python -m pip install pillow >/dev/null   # OLED 描画で使う

# OLED の I2C（apt の python3-smbus）。無ければ OLED が使えない bin になるので警告する
SMBUS=""
if python -c "import smbus" 2>/dev/null; then
  SMBUS="--hidden-import smbus"
else
  echo "注意: smbus が見つかりません（sudo apt install -y python3-smbus）。このままビルドすると OLED が点きません"
fi

PY() { pyinstaller --onefile --clean --noconfirm \
  --distpath "$OUT/dist" --workpath "$OUT/build" --specpath "$OUT/build" "$@"; }

build_core() {
  echo "=== 本体 dstar-live ==="
  local HID
  HID=$(ls "$SRC"/*.py | xargs -n1 basename | sed 's/\.py$//' | sed 's/^/--hidden-import /' | tr '\n' ' ')
  # shellcheck disable=SC2086
  PY --name dstar-live --paths "$SRC" $HID "$SRC/live.py"
}
build_hotspot() {
  echo "=== ホットスポット dxhotspot ==="
  # shellcheck disable=SC2086
  PY --name dxhotspot --paths "$APP" --paths "$SRC" $SMBUS \
    --hidden-import core --hidden-import wifi --hidden-import oled \
    --hidden-import oled_final --hidden-import dash --hidden-import settings \
    --hidden-import dxconfig \
    --add-data "$APP/hs_inject.html:." --add-data "$APP/logo.svg:." \
    --add-data "$APP/favicon.svg:." --add-data "$APP/wifi.html:." \
    "$APP/hotspotd.py"
}
build_settings() {
  echo "=== 設定ツール dxhotspot_settings（インストーラ用）==="
  # settings.py は dxmcore の dxconfig を読む。両方を探索先に入れる
  PY --name dxhotspot_settings --paths "$APP" --paths "$SRC" \
    --hidden-import core --hidden-import dxconfig \
    "$APP/settings.py"
}
build_final() {
  echo "=== 電源断メッセージ dxhotspot_final ==="
  PY --name dxhotspot_final --paths "$APP" \
    --hidden-import core --hidden-import oled "$APP/oled_final.py"
}

case "$WHAT" in
  core)     build_core ;;
  hotspot)  build_hotspot ;;
  settings) build_settings ;;
  final)    build_final ;;
  all)      build_core; build_hotspot; build_settings ;;
  *) echo "使い方: $0 [ソースの場所] [all|core|hotspot|settings|final]"; exit 2 ;;
esac

echo
echo "=== できたもの ==="
ls -lh "$OUT/dist"
echo
echo "版 ${BUILD:-不明} / $(uname -m) / $( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-不明}")"
echo "bin だけでは動きません（static・設定・外部プログラムは bin の外）。"
