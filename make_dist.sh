#!/bin/bash
# dxmonitor 配布物を作る（バイナリ版）
#   使い方:  ./make_dist.sh [ソースの場所] [bin の場所] [install.sh の場所]
#     例:    ./make_dist.sh ~/DXmonitor-main ~/dxm_build/dist ~/install_bin.sh
#   出力:    ~/dxmonitor_bin_<版>_<arch>.tar.gz   ← これを配る
#   ※ /opt・サービスには触らない。読むだけ。
set -euo pipefail
ROOT="${1:-$HOME/DXmonitor-main}"
DIST="${2:-$HOME/dxm_build/dist}"
INST="${3:-$HOME/install_bin.sh}"
[ -d "$ROOT/dxmcore/source" ] || { echo "ソースが見つかりません: $ROOT"; exit 1; }
[ -d "$DIST" ] || { echo "bin が見つかりません: $DIST"; exit 1; }
[ -f "$INST" ] || { echo "install.sh（バイナリ版）が見つかりません: $INST"; exit 1; }
ROOT="$(cd "$ROOT" && pwd)"; DIST="$(cd "$DIST" && pwd)"; INST="$(cd "$(dirname "$INST")" && pwd)/$(basename "$INST")"
SRC="$ROOT/dxmcore/source"; APP="$ROOT/dxhotspot"
BUILD=$(sed -n 's/^BUILD *= *"\([^"]*\)".*/\1/p' "$SRC/live.py" | head -1)
ARCH=$(uname -m); case "$ARCH" in aarch64) PA=arm64;; x86_64) PA=x86_64;; *) PA=$ARCH;; esac
NAME="dxmonitor_bin_${BUILD}_${PA}"
OUT="$HOME/$NAME"
rm -rf "$OUT"; mkdir -p "$OUT"/{bin,app,dxmcore,scripts,systemd}

for f in dstar-live dxhotspot dxhotspot_settings; do
  [ -f "$DIST/$f" ] || { echo "$DIST/$f がありません（build_bin.sh で all を作ってください）"; exit 1; }
  install -m 755 "$DIST/$f" "$OUT/bin/$f"
done
[ -f "$DIST/dxhotspot_final" ] && install -m 755 "$DIST/dxhotspot_final" "$OUT/bin/"

install -m 755 "$INST" "$OUT/install.sh"
cp -a "$SRC/static" "$OUT/dxmcore/"
cp -a "$SRC/config.ini.example" "$SRC/dstar-live.service" "$OUT/dxmcore/"
[ -f "$SRC/NOTICE.md" ] && cp -a "$SRC/NOTICE.md" "$OUT/dxmcore/"
cp -a "$APP/app/hotspot.ini" "$OUT/app/"
cp -a "$APP/scripts/." "$OUT/scripts/"
cp -a "$APP/systemd/." "$OUT/systemd/"
for f in NOTICE.md SETUP.md; do [ -f "$APP/$f" ] && cp -a "$APP/$f" "$OUT/"; done
for f in README.md LICENSE; do [ -f "$ROOT/$f" ] && cp -a "$ROOT/$f" "$OUT/"; done
[ -f "$ROOT/NOTICE.md" ] && cp -a "$ROOT/NOTICE.md" "$OUT/NOTICE.md"

{
  echo "dxmonitor 配布物（バイナリ版）"
  echo "版        : $BUILD"
  echo "対象       : $(uname -m)（$PA）／$( . /etc/os-release 2>/dev/null; echo "$PRETTY_NAME") 以降"
  echo "作成       : $(date '+%Y-%m-%d %H:%M:%S %Z')  on $(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || uname -m)"
  echo "glibc      : $(ldd --version 2>/dev/null | head -1 | sed 's/.*) //')"
  echo
  echo "== 入れ方 =="
  echo "  tar xzf $NAME.tar.gz && cd $NAME && sudo ./install.sh"
  echo "  初回は最後に sudo reboot（UART・I2C を有効にするため）"
  echo
  echo "== bin（sha256 の先頭 16 桁）=="
  for f in "$OUT"/bin/*; do printf "  %-20s %7s  %s\n" "$(basename "$f")" "$(du -h "$f"|cut -f1)" "$(sha256sum "$f"|cut -c1-16)"; done
  echo
  echo "== 同梱していないもの =="
  echo "  ソース（.py）      … 配布しません"
  echo "  MMDVM-Host         … install.sh がこの機械でビルドします"
  echo "  ボコーダー         … 同意した人だけが取得してビルドします（NOTICE.md）"
  echo
  echo "== 動く条件 =="
  echo "  ・$PA の 64bit Linux。glibc がビルド機より新しいこと"
  echo "  ・ほかの CPU・古い OS では動きません（その機械でビルドした配布物を使ってください）"
} > "$OUT/BUILD-INFO.txt"

cd "$HOME"
tar czf "$NAME.tar.gz" "$NAME"
rm -rf "$OUT"
echo
echo "できました: $HOME/$NAME.tar.gz  ($(du -h "$HOME/$NAME.tar.gz"|cut -f1))"
tar tzf "$HOME/$NAME.tar.gz" | sed 's|^|  |'
