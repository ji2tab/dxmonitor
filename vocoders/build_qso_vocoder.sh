#!/bin/bash
# QSO One の D-STAR コーデックを、この機械でソースからビルドして dxmonitor のボコーダー（pipe）にする。
#   sudo bash build_qso_vocoder.sh [インストール先（既定 /opt/vocoders）]
#   前回と同じコミット・同じヘルパーのソースでビルド済みなら、ビルドを省いて動作確認だけ行う（QSO_REBUILD=1 で必ずビルド）
# ソース: github.com/greyfoxsolid/vocoder（GPL v3）。コミットを固定してビルドする（発展途上のため）。
# dxmonitor はバイナリを同梱・配布しない。ビルドしたものはこの機械の中だけで使う。
# 注意（mbelib の注記）: 実行物は特許の対象になり得る。個人の実験・アマチュア無線の範囲で使うこと。
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
QSO_REPO="https://github.com/greyfoxsolid/vocoder.git"
QSO_COMMIT="${QSO_COMMIT:-d519d0c}"
# DMR・YSF（AMBE+2 3600x2450）の音量の較正（dxmonitor の追加。2026-10-30、本物の AMBE3000 チップと比べて測定）。
#   QSO One の DMR 側は元の OP25／DroidStar のままで、実チップより符号化が +5.1 dB 大きく、復号が 6.3 dB 小さかった
#   （入力 -14〜-26 dBFS で一定。音量の揺れはチップと同じなので平滑化は入れない）。D-STAR 側の DSTAR_GAIN_ADJUST・
#   DSTAR_OUT_GAIN_DB と同じ形で、ビルドの前にソースへ当てる。0 にすると元のまま。
QSO_DMR_ENC_DB="${QSO_DMR_ENC_DB:-5.1}"     # 符号化をこの dB だけ小さく
QSO_DMR_DEC_DB="${QSO_DMR_DEC_DB:-6.3}"     # 復号をこの dB だけ大きく（int16 に丸める前に掛ける）
DEST="${1:-/opt/vocoders}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$DEST/src/qso-vocoder"
# 前回のビルドの印（コミット＋ヘルパーのソースとこのスクリプトの sha256）
STAMP="$QSO_COMMIT dmrcal=$QSO_DMR_ENC_DB/$QSO_DMR_DEC_DB $(cat "$HERE/qso_dv_dxm.cpp" "$0" | sha256sum | cut -c1-16)"

selftest() {   # 動作確認: hello と、無音フレームの復号
python3 - "$DEST/qso_dv_dxm" <<'PY'
import subprocess, struct, sys
p = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
p.stdin.write(b"H"); p.stdin.flush()
h = p.stdout.read(6); assert h[:2] == b"DV" and h[3] & 5 == 5, h
print("  ", p.stdout.read(struct.unpack("<H", h[4:6])[0]).decode())
p.stdin.write(b"D\x00\x01\x00" + bytes.fromhex("9E8D3288261A3F61E8")); p.stdin.flush()
st = p.stdout.read(9); pcm = p.stdout.read(320); assert st[0] == 0 and len(pcm) == 320
p.stdin.write(b"Q"); p.stdin.flush(); p.wait()
print("   動作確認 OK")
PY
}

if [ "${QSO_REBUILD:-0}" != 1 ] && [ -x "$DEST/qso_dv_dxm" ] && [ "$(cat "$DEST/qso_dv_dxm.stamp" 2>/dev/null)" = "$STAMP" ]; then
  echo "QSO One vocoder: ビルド済み（$QSO_COMMIT、変更なし）→ ビルドを省略"
  selftest
  echo "$DEST/qso_dv_dxm"
  exit 0
fi

mkdir -p "$DEST/src"
if [ ! -d "$SRC/.git" ]; then
  git clone -q "$QSO_REPO" "$SRC"
fi
git -C "$SRC" fetch -q origin || true
git -C "$SRC" checkout -q -f "$QSO_COMMIT"     # 前回当てた較正を消してから当て直す
REV=$(git -C "$SRC" rev-parse --short HEAD)
echo "QSO One vocoder: $REV"

# DMR・YSF の音量の較正を当てる（mbevocoder.cpp の 3 か所。見つからなければ止める）
python3 - "$SRC/third_party/dv_codecs/DroidStar/mbe/mbevocoder.cpp" "$QSO_DMR_ENC_DB" "$QSO_DMR_DEC_DB" <<'PY'
import sys
p, enc, dec = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
s = open(p, encoding="utf-8").read()
enc_old = "encode_ambe(vocoder.param(), b, m_mbelibParms->m_cur_mp, m_mbelibParms->m_prev_mp, false, 1.0);"
enc_new = ("encode_ambe(vocoder.param(), b, m_mbelibParms->m_cur_mp, m_mbelibParms->m_prev_mp, false, "
           "1.0f + %.4ff);\t// dxmonitor: DMR loudness to a real AMBE3000 (-%.1f dB; log2 units, 6.02 dB each)" % (enc / 6.0206, enc))
out = "\t\t{ static const float kDmrOut = powf(10.0f, %.2ff / 20.0f); for (int i = 0; i < 160; i++) m_audio_out_temp_buf[i] *= kDmrOut; }\t// dxmonitor: DMR decoder +%.1f dB to a real AMBE3000\n" % (dec, dec)
d1 = "mbe_processAmbe3600x2450Framef(m_audio_out_temp_buf, &m_errs2, m_err_str, ambe_fr, ambe_d,m_mbelibParms-> m_cur_mp, m_mbelibParms->m_prev_mp, m_mbelibParms->m_prev_mp_enhanced, 3);\n"
d2 = "mbe_processAmbe2450Dataf(m_audio_out_temp_buf, &m_errs2, m_err_str, ambe_data, m_mbelibParms->m_cur_mp,m_mbelibParms->m_prev_mp, m_mbelibParms->m_prev_mp_enhanced, 3);\n"
for old, new in ((enc_old, enc_new), (d1, d1 + out), (d2, d2 + out)):
    if s.count(old) != 1:
        sys.exit("QSO One のソースが想定と違います（DMR の較正を当てられません）: " + old[:50])
    s = s.replace(old, new)
open(p, "w", encoding="utf-8").write(s)
print("   DMR・YSF の較正: 符号化 -%.1f dB／復号 +%.1f dB" % (enc, dec))
PY

B="$DEST/build"; rm -rf "$B"; mkdir -p "$B"
D="$SRC/third_party/dv_codecs/DroidStar"
INC="-I$D -I$D/mbe -I$D/imbe_vocoder -I$SRC/src"
CF="-O2 -w"
# 1 ファイルずつ（Zero 2W のメモリでも通るように）
for f in "$D"/mbe/ambe3600x2400.c "$D"/mbe/ambe3600x2450.c "$D"/mbe/ecc.c "$D"/mbe/mbelib.c; do
  gcc $CF $INC -c "$f" -o "$B/$(basename "$f").o"
done
for f in "$D"/mbe/mbevocoder.cpp "$D"/imbe_vocoder/*.cc "$SRC"/src/dv_codec_core.cpp; do
  g++ -std=c++17 $CF $INC -c "$f" -o "$B/$(basename "$f").o"
done
g++ -std=c++17 $CF $INC -DQSO_REV="\"$REV\"" -DDMR_CAL="\"-${QSO_DMR_ENC_DB}/+${QSO_DMR_DEC_DB}dB\"" -c "$HERE/qso_dv_dxm.cpp" -o "$B/qso_dv_dxm.o"
g++ -o "$DEST/qso_dv_dxm" "$B"/*.o -lm
rm -rf "$B"

selftest
echo "$STAMP" > "$DEST/qso_dv_dxm.stamp"
echo "$DEST/qso_dv_dxm"
