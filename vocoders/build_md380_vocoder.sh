#!/bin/bash
# MD-380 のファームウェアの AMBE+2 符号化器・復号器を、この機械で dxmonitor の DMR 用ボコーダー（pipe）にする。
#   sudo bash build_md380_vocoder.sh [インストール先（既定 /opt/vocoders）]
#   できるもの: <インストール先>/md380_dv（32 ビット ARM の静的バイナリ）。config.ini に次を足して使う:
#     [vocoder.md380]
#     label = MD-380 ファーム
#     type = pipe
#     command = /opt/vocoders/md380_dv
#     modes = dmr            ← DMR 専用（D-STAR の選択肢に出さない）
#     [dmr_rf]
#     vocoder = md380        ← DMR の符号化・復号（D-STAR は今のボコーダーのまま）
#
# 中身: md380tools（travisgoodspeed/md380tools、コミット固定）の emulator と同じ方法で、ファームの関数を直接呼ぶ。
#   ファームウェア D002.032 は md380tools の手順で md380.org から取得する（Tytera の権利物）。
#   dxmonitor はファームもバイナリも同梱・配布しない。この機械の中だけで使うこと。
#   前回と同じコミット・同じソースでビルド済みなら省略して動作確認だけ（MD380_REBUILD=1 で必ずビルド）。
# 必要: 32 ビット ARM を実行できること（aarch64 の Raspberry Pi OS は通常そのまま動く。動かなければ qemu-user）。
# 【重要】ソフトウェアの AMBE は、使用者が自己の実験・研究のために自己の責任で使うもの。その使用とそれによる
#   トラブルについて製作者は一切の責任を負わない（責任はすべて使用者が負う。NOTICE.md）。基本はハードウェアの AMBE。
#   このスクリプトは、同意を明示したときだけ動く（DXH_SOFT_AMBE_AGREE=yes。install.sh は同意のあとで付けて呼ぶ）。
if [ "${DXH_SOFT_AMBE_AGREE:-no}" != yes ]; then
  echo "ソフトウェアの AMBE は、使用者が自己の実験・研究のために、自己の責任で使うものです。"
  echo "その使用とそれによるトラブルについて、製作者は一切の責任を負いません（責任はすべて使用者が負います）。"
  echo "同意してビルドするときは、DXH_SOFT_AMBE_AGREE=yes を付けて実行してください。"
  exit 2
fi
set -euo pipefail
MD380_REPO="https://github.com/travisgoodspeed/md380tools.git"
MD380_COMMIT="${MD380_COMMIT:-d7f4206}"
DEST="${1:-/opt/vocoders}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$DEST/src/md380tools"
STAMP="$MD380_COMMIT $(cat "$HERE/md380_dv.c" "$HERE/dmr_ambe_fec.h" "$0" | sha256sum | cut -c1-16)"

selftest() {   # hello と、DMR の無音フレームの復号・1 秒の音の符号化→復号
python3 - "$DEST/md380_dv" <<'PY'
import math, struct, subprocess, sys
p = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
p.stdin.write(b"H"); p.stdin.flush()
h = p.stdout.read(6); assert h[:2] == b"DV" and h[3] & 4, h
print("  ", p.stdout.read(struct.unpack("<H", h[4:6])[0]).decode())
peak = 0
for f in range(50):
    pcm = struct.pack("<160h", *[int(8000 * math.sin(2 * math.pi * 700 * (f * 160 + i) / 8000)) for i in range(160)])
    p.stdin.write(b"E\x02\x01\x00" + pcm); p.stdin.flush()
    st = p.stdout.read(9); a = p.stdout.read(9); assert st[0] == 0 and len(a) == 9
    p.stdin.write(b"D\x02\x01\x00" + a); p.stdin.flush()
    st = p.stdout.read(9); out = p.stdout.read(320); assert st[0] == 0 and len(out) == 320
    if f > 10:
        peak = max(peak, max(abs(x) for x in struct.unpack("<160h", out)))
p.stdin.write(b"Q"); p.stdin.flush(); p.wait()
print("   符号化→復号の最大振幅 %d（無音でなければ OK）" % peak)
assert peak > 1000, "md380 の符号化・復号の結果が無音です"
print("   動作確認 OK")
PY
}

if [ "${MD380_REBUILD:-0}" != 1 ] && [ -x "$DEST/md380_dv" ] && [ "$(cat "$DEST/md380_dv.stamp" 2>/dev/null)" = "$STAMP" ]; then
  echo "md380_dv: ビルド済み（$MD380_COMMIT、変更なし）→ ビルドを省略"
  selftest
  echo "$DEST/md380_dv"
  exit 0
fi

# 32 ビット ARM のクロスコンパイラ（arm-linux-gnueabi。無ければ gnueabihf）
CROSS=""
for c in arm-linux-gnueabi arm-linux-gnueabihf; do command -v $c-gcc >/dev/null && { CROSS=$c; break; }; done
if [ -z "$CROSS" ]; then
  echo "32 ビット ARM のコンパイラを入れています（数分かかります）…"
  apt-get install -y gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi && CROSS=arm-linux-gnueabi \
    || { apt-get install -y gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf && CROSS=arm-linux-gnueabihf; }
fi
command -v unzip >/dev/null || apt-get install -y unzip
echo "コンパイラ: $CROSS-gcc"

mkdir -p "$DEST/src"
[ -d "$SRC/.git" ] || git clone -q "$MD380_REPO" "$SRC"
git -C "$SRC" fetch -q origin || true
git -C "$SRC" checkout -q "$MD380_COMMIT"
REV=$(git -C "$SRC" rev-parse --short HEAD)
echo "md380tools: $REV"

# ファームウェア D002.032 を取得して展開（md380tools の手順。ファイルの大きさと SHA256 を確かめる）
echo "ファームウェア D002.032 を取得・展開しています…"
make -C "$SRC/firmware" -f Makefile_orig unwrapped/D002.032.img
IMG="$SRC/firmware/unwrapped/D002.032.img"
[ -s "$IMG" ] || { echo "ファームウェアの取得に失敗しました"; exit 1; }

echo "md380_dv をビルドしています…"
B="$DEST/build-md380"; rm -rf "$B"; mkdir -p "$B"
$CROSS-objcopy -I binary "$IMG" --change-addresses=0x0800C000 --rename-section .data=.firmware \
  -O elf32-littlearm -B arm "$B/firmware.o"
$CROSS-objcopy -I binary "$SRC/cores/d02032-core.img" --change-addresses=0x20000000 --rename-section .data=.sram \
  -O elf32-littlearm -B arm "$B/ram.o"
$CROSS-gcc -static -O2 -std=gnu99 -w -DMD380_REV="\"$REV\"" -I"$HERE" -c "$HERE/md380_dv.c" -o "$B/md380_dv.o"
$CROSS-gcc -static -o "$DEST/md380_dv" "$B/md380_dv.o" "$B/firmware.o" "$B/ram.o" \
  -Xlinker --just-symbols="$SRC/applet/src/symbols_d02.032" \
  -Xlinker --section-start=.firmware=0x0800C000 -Xlinker --section-start=.sram=0x20000000 2>/dev/null
rm -rf "$B"

if ! "$DEST/md380_dv" </dev/null >/dev/null 2>&1; then
  echo "md380_dv を実行できません（32 ビット ARM を実行できない環境）。sudo apt-get install qemu-user-binfmt を試してください"
  exit 1
fi
selftest
echo "$STAMP" > "$DEST/md380_dv.stamp"
echo "$DEST/md380_dv"
