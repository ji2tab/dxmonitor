#!/bin/bash
# dxhotspot インストーラ【バイナリ版】（機械の形は自動で見分ける）
#   ソース（.py）は配りません。ロジックは bin/ の単一実行ファイル（PyInstaller）です。
#   ボコーダーは同梱せず、同意した人だけが GitHub から資材を取得してこの機械でビルドします。
#   1. Raspberry Pi ＋ MMDVM_HS_Hat（GPIO）＋ SSD1306 OLED（Raspberry Pi OS Lite 64-bit）
#   2. PC（x86_64 の Debian/Ubuntu、Incus コンテナも可）＋ USB の HAT（CH340 等、/dev/ttyUSB0）。OLED なし
#   3. PC ＋ MCP2221A（USB → UART・I2C）＋ MMDVM_HS_Hat（dxhat）。OLED は MCP2221A の I2C
#   ※ ネットのみ（モデムなし）の PC はこれではなく dxmcore 単体の install.sh（dxmcore_*.tar.gz の source/。INSTALL.md）
#   どれも:  sudo ./install.sh
#     モデムの場所を変えるとき: sudo DXH_MODEM=/dev/ttyACM0 ./install.sh
#     OLED を決めるとき:        sudo DXH_OLED=no ./install.sh（使わない）／DXH_OLED=/dev/i2c-mcp（その I2C）／DXH_OLED=auto
#   初回（UART/I2C/Bluetooth の設定を変えたとき）は最後に sudo reboot。再実行ではサービスを再起動して終わる
# 何度実行しても壊れないように作ってある（既存の ini/config はバックアップしてから作り直す）。
set -euo pipefail

# ======== 固定の設定（通常は変えない） ========
OLED_ROTATE="2"          # 初回の OLED の向き（0=標準／2=上下反転）。再実行では前回の値を引き継ぐ
MMDVM_COMMIT="43edd65"   # MMDVM-Host のピン留め（旧 ini 書式。変えないこと）
DMRIDS_URL="https://radioid.net/static/user.csv"   # コール⇔DMR ID の一覧（MMDVM-Host と共用）
RUNUSER="dstar"
# 局ごとの値（コール・周波数・許可コール・DMR ID など）はこのあと質問する（再実行時は今の値が既定）。
# あとから Web の「設定」タブでも変えられる。
# 質問を省くとき: 値を環境変数で渡して  sudo DXH_CALLSIGN=<コール> DXH_MODULE=<モジュール> ... ./install.sh --yes
#   （DXH_CALLSIGN DXH_MODULE DXH_FREQ_MHZ DXH_SESSION_CALL DXH_ALLOW_CALLS DXH_RX_OFFSET DXH_TX_OFFSET
#     DXH_DMR_ID DXH_COLOR_CODE DXH_DMR_TG DXH_NET_TO_RF DXH_NET_MODE
#     DXH_SOFT_AMBE_AGREE(yes/no。既定 no＝ハードウェアの AMBE) DXH_QSO_VOCODER(yes/no) DXH_MD380(yes/no)）
#   QSO One を必ずビルドし直すとき: QSO_REBUILD=1
# ====================================================

HERE="$(cd "$(dirname "$0")" && pwd)"
MMDVM_DIR=/opt/MMDVMHost
INI=$MMDVM_DIR/MMDVM-Host.ini
DX_DIR=/opt/dstar_ambe
OLED_DIR=/opt/dxhotspot
# バイナリ版: ソース（.py）は配らない。bin/ と素材だけを置く
BINDIR="$HERE/bin"
DXMSRC="$HERE/dxmcore"                     # static・config.ini.example・dstar-live.service
# ボコーダーの資材の取得元（同意した人だけが取りに行く。7/8 の手前で使う）
VOC_REF="${DXH_VOC_REF:-main}"
VOC_BASE="${DXH_VOC_BASE:-https://raw.githubusercontent.com/ji2tab/dxmonitor/$VOC_REF/vocoders}"
# ---- 機械の種類（Raspberry Pi の GPIO HAT か、x86_64 などの USB のモデムか）
case "$(uname -m)" in
  aarch64) PARCH=arm64 ;;
  x86_64)  PARCH=x86_64 ;;
  *) echo "64bit の aarch64（Raspberry Pi）か x86_64 が必要です。今は $(uname -m)"; exit 1 ;;
esac
IS_PI=0; grep -qi raspberry /proc/device-tree/model 2>/dev/null && IS_PI=1
# モデムの場所: 指定（DXH_MODEM）> Pi の GPIO（/dev/ttyAMA0）
#   > USB（/dev/mcp-uart＝MCP2221A を udev で固定した名前・/dev/ttyUSB0・/dev/ttyACM0・/dev/ttyUSB1 のうち在るもの）
MODEM_PORT="${DXH_MODEM:-}"
# 再実行: 前回の MMDVM-Host.ini の [Modem] UARTPort が今もある（キャラクタ機器）ならそれを使う。
#   探し直して USB の別の機器（GPS など）に変わらないように（20261102b〜。M-6）。sed に渡すので名前の文字も確かめる
if [ -z "$MODEM_PORT" ] && [ -f "$INI" ]; then
  OLD_PORT=$(sed -n '/^\[Modem\]/,/^\[/ s/^UARTPort=\([^[:space:]]*\).*/\1/p' "$INI" | head -1 || true)
  if [[ "$OLD_PORT" =~ ^/dev/[A-Za-z0-9/_.-]+$ ]] && [ -c "$OLD_PORT" ]; then
    MODEM_PORT=$OLD_PORT
    echo "モデム: 前回の $OLD_PORT を使います（変えるときは DXH_MODEM=/dev/…）"
  fi
fi
if [ -z "$MODEM_PORT" ]; then
  if [ "$IS_PI" = 1 ]; then MODEM_PORT=/dev/ttyAMA0
  else for d in /dev/mcp-uart /dev/ttyUSB0 /dev/ttyACM0 /dev/ttyUSB1; do [ -e "$d" ] && { MODEM_PORT=$d; break; }; done; fi
fi
# OLED（I2C の SSD1306）: 指定（DXH_OLED）> Pi の内蔵 I2C > MCP2221A の I2C > なし
#   OLED_ON: 1＝使う／0＝使わない（指定）／空＝見つからない（初回は使わない、再実行は前回のまま）
#   OLED_SET: hotspot.ini の [oled] i2c_port に書く値（空＝初回は auto、再実行は前回のまま）
#   どのバスかは oled.py が動きながら探す（i2c_port = auto）。MCP2221A を抜き差しして番号が変わっても追いつく
HAS_MCP=0; grep -qi mcp2221 /sys/class/i2c-dev/*/name 2>/dev/null && HAS_MCP=1
OLED_SET=""
case "${DXH_OLED:-}" in
  no|off)       OLED_ON=0 ;;
  yes|on|auto)  OLED_ON=1; OLED_SET=auto ;;
  "")           if [ "$IS_PI" = 1 ] || [ "$HAS_MCP" = 1 ]; then OLED_ON=1; else OLED_ON=""; fi ;;
  *)            OLED_ON=1; OLED_SET="$DXH_OLED" ;;          # 番号か /dev/… の名前
esac
PLUGIN_FILE=vocoder_plugin.linux.$PARCH
PLUGIN_URL=https://raw.githubusercontent.com/wiblingen/droidstar_vocoder_plugin/main/$PLUGIN_FILE
PLUGIN_SIZE=263384          # arm64 の大きさ（x86_64 は ELF かどうかで確かめる）

say() { echo; echo "=== $* ==="; }
[ "$(id -u)" -eq 0 ] || { echo "sudo ./install.sh で実行してください"; exit 1; }
if [ "$IS_PI" = 1 ] && [ "$MODEM_PORT" = /dev/ttyAMA0 ] && [ ! -e /dev/ttyAMA0 ]; then
  echo "UART（/dev/ttyAMA0）がまだ有効になっていません。このあと有効にします（最後に sudo reboot で使えるようになります）"
else
[ -n "$MODEM_PORT" ] && [ -e "$MODEM_PORT" ] || { echo "モデムが見つかりません（${MODEM_PORT:-/dev/ttyUSB0 など}）。USB の HAT・MCP2221A をつなぐか、コンテナなら incus でデバイスを渡し、DXH_MODEM=/dev/… で指定してください"; echo "ネットのみ（モデムなし）で使うときは、この install.sh ではなく dxmcore 単体の install.sh を使ってください（dxmcore_*.tar.gz の source/install.sh。手順は INSTALL.md）"; exit 1; }
fi
echo "機械: $(uname -m)$([ "$IS_PI" = 1 ] && echo '（Raspberry Pi）')$(systemd-detect-virt -c -q 2>/dev/null && echo "（コンテナ $(systemd-detect-virt -c)）")、モデム $MODEM_PORT、OLED $(case "$OLED_ON" in 1) echo "使う（${OLED_SET:-auto}$([ "$HAS_MCP" = 1 ] && echo '・MCP2221A あり')）";; 0) echo '使わない（指定）';; *) echo 'なし（I2C が見つからない）';; esac)"
for f in "$BINDIR/dstar-live" "$BINDIR/dxhotspot" "$BINDIR/dxhotspot_settings"; do
  [ -x "$f" ] || { echo "$f がありません（この配布物が壊れています）"; exit 1; }
done
for f in "$DXMSRC/static/index.html" "$DXMSRC/config.ini.example" "$DXMSRC/dstar-live.service" "$HERE/app/hotspot.ini"; do
  [ -f "$f" ] || { echo "$f がありません（この配布物が壊れています）"; exit 1; }
done
# この機械で動く bin か（arm64 の bin を x86_64 に配った等を早めに弾く）
"$BINDIR/dxhotspot_settings" --check module D >/dev/null 2>&1 || {
  echo "bin がこの機械で動きません（$(uname -m)）。この機械と同じ CPU・OS でビルドした配布物を使ってください"; exit 1; }

cleanup_swap() { if swapon --show=NAME --noheadings 2>/dev/null | grep -q /swapbuild; then swapoff /swapbuild; fi; rm -f /swapbuild; }
# dxmcore の束は最初に root だけが読み書きできる一時フォルダ（mktemp -d は 0700）へ展開し、6/8 でもそれを使う。
# settings.py（root で動く）は dxconfig.py をここから読む（$RUNUSER が書ける $DX_DIR のコードを root で動かさない。20261102b〜。H-3）
WORK=$(mktemp -d)
cleanup() { cleanup_swap; rm -rf "$WORK"; }
trap cleanup EXIT
# バイナリ版: 展開する束は無い。設定の検査表は dxhotspot_settings が自分の中に持つ（DXH_DXCONFIG_DIR は使わない）

# ---- root が $RUNUSER の書けるフォルダ（$MMDVM_DIR・$DX_DIR・$OLED_DIR）に書くときの決まり（20261102b〜。M-9）
#   ・書く先・読む元がシンボリックリンクなら止める（$RUNUSER の権限で別のファイルを root に上書きさせない）
#   ・ini・config は $WORK（root だけ）で組み立て、最後に place で置く（一時名を O_EXCL で作る＝リンクをたどらない）
nolink() {
  local p
  for p in "$@"; do
    if [ -L "$p" ]; then
      echo "中止: $p がシンボリックリンクです（root はたどって書きません）。中身を確かめて消してから流し直してください"
      exit 1
    fi
  done
}
place() {   # place 元 先 umask … 元の中身を 先 に置き換える（持ち主は $RUNUSER。権限は umask で決める: 022→644・027→640・077→600）
  local src=$1 dst=$2 um=$3 tmp="$2.dxh-tmp.$$"
  nolink "$dst"
  rm -f "$tmp"
  ( umask "$um"; set -C; cat "$src" > "$tmp" )
  chown -h "$RUNUSER:$RUNUSER" "$tmp"
  mv -f "$tmp" "$dst"
}
backup() {  # backup 元 先 … 控え（600。root が作り、あとの chown -R で $RUNUSER のものになる）
  nolink "$1" "$2"
  rm -f "$2"
  ( umask 077; set -C; cat "$1" > "$2" )
}

# 設定の検査に python3 を使う（Debian の最小構成・コンテナには入っていないことがある）
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 を入れます"
  apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q python3 \
    || { echo "python3 を入れられません（apt-get install python3 を手で試してください）"; exit 1; }
fi

say "0/8 局の設定（Enter で [ ] 内の値のまま）"
YES=0; [ "${1:-}" = "--yes" ] && YES=1; [ -t 0 ] || YES=1
for k in CALLSIGN MODULE FREQ_MHZ SESSION_CALL ALLOW_CALLS RX_OFFSET TX_OFFSET DMR_ID COLOR_CODE DMR_TG NET_TO_RF NET_MODE; do
  printf -v "CUR_$k" '%s' ""
done
if [ -f "$INI" ] || [ -f "$DX_DIR/config.ini" ]; then
  eval "$("$BINDIR/dxhotspot_settings" --get-shell "$INI" "$DX_DIR/config.ini")"
fi
SET="$BINDIR/dxhotspot_settings"
ask() {   # ask KEY 見出し 既定値 … 検査に通るまで聞き直す。結果は DXH_KEY（export）
  local key=$1 label=$2 def=$3 v msg env="DXH_$1"
  [ -n "${!env:-}" ] && def="${!env}"
  while true; do
    if [ "$YES" = 1 ]; then v="$def"; else read -r -p "  $label [$def]: " v || true; v="${v:-$def}"; fi
    [ "$v" = "-" ] && v=""                                 # 「-」で空にする（DMR ID を消すときなど）
    if msg=$("$SET" --check "$(echo "$key" | tr 'A-Z' 'a-z')" "$v"); then
      printf -v "$env" '%s' "$msg"; export "${env?}"; return 0      # 検査済み・正規化した値
    fi
    echo "    → $msg"
    [ "$YES" = 1 ] && { echo "値が正しくありません: $env"; exit 1; }
  done
}
ask CALLSIGN     "ホットスポットのコール（RPT1 のコール部分）"      "$CUR_CALLSIGN"
ask MODULE       "モジュール（RPT1 の 8 文字目）"        "${CUR_MODULE:-D}"
ask FREQ_MHZ     "周波数 MHz（単信）"                    "$CUR_FREQ_MHZ"
ask SESSION_CALL "接続先に名乗るコール（コール＋空白＋サフィックス 1 文字）"      "${CUR_SESSION_CALL:-$DXH_CALLSIGN $DXH_MODULE}"
ask ALLOW_CALLS  "使える無線機の MY（カンマ区切り。* で制限しない）" "${CUR_ALLOW_CALLS:-$DXH_CALLSIGN}"
ask DMR_ID       "DMR ID（DMR を使わないなら空。消すときは -）" "$CUR_DMR_ID"
if [ -n "$DXH_DMR_ID" ]; then
  ask COLOR_CODE "DMR カラーコード"                      "${CUR_COLOR_CODE:-1}"
  ask DMR_TG     "DMR の宛先 TG"                         "${CUR_DMR_TG:-9}"
  ask NET_TO_RF  "電波側（dstar＝D-STAR／dmr＝DMR／ysf＝C4FM の無線機）"     "${CUR_NET_TO_RF:-dmr}"
  ask NET_MODE   "ネット側（dstar＝D-STAR の XLX・DCS／dmr＝DMR のマスター／ysf＝YSF のリフレクター）" "${CUR_NET_MODE:-dstar}"
else
  # DMR ID が無い: DMR は選べないので dstar に。YSF・D-STAR は今の値（環境変数）を残す（再実行で電波 YSF が戻らないように）
  _rf="${DXH_NET_TO_RF:-${CUR_NET_TO_RF:-dstar}}"; _net="${DXH_NET_MODE:-${CUR_NET_MODE:-dstar}}"
  [ "$_rf" = dmr ] && _rf=dstar; [ "$_net" = dmr ] && _net=dstar
  export DXH_COLOR_CODE="${CUR_COLOR_CODE:-1}" DXH_DMR_TG="${CUR_DMR_TG:-9}" DXH_NET_TO_RF="$_rf" DXH_NET_MODE="$_net"
fi
export DXH_RX_OFFSET="${DXH_RX_OFFSET:-${CUR_RX_OFFSET:-0}}" DXH_TX_OFFSET="${DXH_TX_OFFSET:-${CUR_TX_OFFSET:-0}}"
# ── AMBE ボコーダー（NOTICE.md）──
# 基本はハードウェアの AMBE（AMBEserver）。ソフトウェアの AMBE は、使用者が自己の実験・研究のために、自己の責任で使うと
# 明示したときだけ取得・ビルドする（DXH_SOFT_AMBE_AGREE=yes、または下の質問に yes。前に同意した機械は控えを引き継ぐ）。
AGREE_FILE=/opt/dxhotspot/soft_ambe_agreed
SOFT_AMBE="${DXH_SOFT_AMBE_AGREE:-$([ -f "$AGREE_FILE" ] && echo yes || echo no)}"
if [ "$YES" != 1 ]; then
  echo
  echo "  ── AMBE ボコーダーについて（重要）──"
  echo "  ・本ソフトウェアは、ハードウェアの AMBE（AMBEserver など）で使うことを基本とします。"
  echo "  ・ソフトウェアの AMBE は同梱も配布もしていません。使う場合は、使用者が自己の実験・研究のために、"
  echo "    自己の判断と責任で入手・ビルドして使うものとします。"
  echo "  ・ソフトウェアの AMBE の入手・ビルド・使用と、それによって生じたトラブル・損害・紛争について、"
  echo "    製作者は一切関与せず、いかなる責任も負いません。その責任はすべて使用者が負います。"
  echo "  ・ハードウェアの AMBE だけでは、D-STAR ⇔ DMR／YSF の変換と音声応答は使えません（NOTICE.md）。"
  read -r -p "  上記に同意して、ソフトウェアの AMBE を使いますか（同意するときは yes と入力。Enter＝使わない＝ハードウェアの AMBE）$([ "$SOFT_AMBE" = yes ] && echo '［前回: 同意済み。Enter で引き継ぐ］'): " A || true
  case "${A:-$SOFT_AMBE}" in yes|YES|Yes) SOFT_AMBE=yes;; *) SOFT_AMBE=no;; esac
fi
export DXH_SOFT_AMBE_AGREE="$SOFT_AMBE"
# QSO One のボコーダー（実チップ準拠の補正入り）をこの機械でビルドして使うか（ソースから。配布物には含めない）
QSO_VOCODER="${DXH_QSO_VOCODER:-yes}"; [ "$SOFT_AMBE" = yes ] || QSO_VOCODER=no
if [ "$YES" != 1 ] && [ "$SOFT_AMBE" = yes ]; then
  echo "  QSO One のボコーダー：github.com/greyfoxsolid/vocoder（GPL v3）をこの Pi でビルドします。"
  echo "    mbelib の注記どおり、実行物は特許の対象になり得ます。個人の実験・アマチュア無線の範囲で使ってください。"
  read -r -p "  QSO One のボコーダーをビルドして使いますか [Y/n]: " A || true
  case "${A:-Y}" in [Nn]*) QSO_VOCODER=no;; *) QSO_VOCODER=yes;; esac
fi
# MD-380 のファームウェアの AMBE+2（DMR）をボコーダーにするか（md380tools の方法。ファームは md380.org から取得。配布物には含めない）
MD380_VOCODER="${DXH_MD380:-$([ -x /opt/vocoders/md380_dv ] && echo yes || echo no)}"; [ "$SOFT_AMBE" = yes ] || MD380_VOCODER=no
if [ "$YES" != 1 ] && [ "$SOFT_AMBE" = yes ]; then
  echo "  MD-380 のファームの AMBE+2（DMR 用）：md380tools でファームウェア D002.032 を取得し、この Pi でビルドします。"
  echo "    ファームウェアは Tytera の権利物です。個人の実験・アマチュア無線の範囲で使ってください（配布しないこと）。"
  read -r -p "  DMR のボコーダーを MD-380 のファームで作りますか [$([ "$MD380_VOCODER" = yes ] && echo Y/n || echo y/N)]: " A || true
  case "${A:-$([ "$MD380_VOCODER" = yes ] && echo Y || echo N)}" in [Yy]*) MD380_VOCODER=yes;; *) MD380_VOCODER=no;; esac
fi
# Web の設定用パスワードは使わない（1.5.1〜。個人で使う前提。設定タブはパスワードなしで変更できる）
DMR_ID="$DXH_DMR_ID"
echo
echo "  局 $DXH_CALLSIGN $DXH_MODULE / $DXH_FREQ_MHZ MHz / セッション $DXH_SESSION_CALL / 許可 $DXH_ALLOW_CALLS"
if [ "$SOFT_AMBE" = yes ]; then
  echo "  ボコーダー ソフトウェアの AMBE（自己の実験・研究。責任は使用者）: $([ "$QSO_VOCODER" = yes ] && echo 'QSO One（ビルド）' || echo 'DroidStar プラグイン')$([ "$MD380_VOCODER" = yes ] && echo '、DMR は MD-380 のファーム')"
else
  echo "  ボコーダー ハードウェアの AMBE（AMBEserver。入れたあと設定タブで接続先を入れる）"
fi
echo "  DMR ID ${DXH_DMR_ID:-（使わない）} / CC $DXH_COLOR_CODE / TG $DXH_DMR_TG / モード 電波 $DXH_NET_TO_RF ⇔ ネット $DXH_NET_MODE"
if [ "$YES" != 1 ]; then
  read -r -p "  この内容で進めますか [Y/n]: " OK || true
  case "${OK:-Y}" in [Yy]*) ;; *) echo "中止しました"; exit 1;; esac
fi

say "1/8 UART・I2C を有効化、Bluetooth を無効化"
NEED_REBOOT=0
if [ "$IS_PI" != 1 ]; then
  echo "Raspberry Pi ではないので省略（USB のモデム $MODEM_PORT を使う）"
else
CMDLINE=/boot/firmware/cmdline.txt; [ -f $CMDLINE ] || CMDLINE=/boot/cmdline.txt
BOOTSUM() { cat /boot/firmware/config.txt /boot/config.txt $CMDLINE /etc/modules 2>/dev/null | md5sum; }
BOOT_BEFORE=$(BOOTSUM)
[ -e /dev/i2c-1 ] || raspi-config nonint do_i2c 0      # 有効なら呼ばない（実行中に dtparam を当てるとカーネルが警告を出す）
raspi-config nonint do_serial_cons 1
raspi-config nonint do_serial_hw 0
BOOTCFG=/boot/firmware/config.txt
[ -f $BOOTCFG ] || BOOTCFG=/boot/config.txt
grep -q '^dtoverlay=disable-bt' $BOOTCFG || echo 'dtoverlay=disable-bt' >> $BOOTCFG
systemctl disable hciuart 2>/dev/null || true
NEED_REBOOT=0; [ "$(BOOTSUM)" = "$BOOT_BEFORE" ] || NEED_REBOOT=1   # 起動設定が変わった（初回など）なら再起動が要る
fi

say "2/8 パッケージ"
PKGS="git build-essential nlohmann-json3-dev libmosquitto-dev
  mosquitto mosquitto-clients i2c-tools python3 python3-venv python3-pil
  fonts-dejavu-core openssl curl stm32flash python3-smbus
  open-jtalk open-jtalk-mecab-naist-jdic hts-voice-nitech-jp-atr503-m001 sox"
MISSING=""
for p in $PKGS; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || MISSING="$MISSING $p"; done
if [ -n "$MISSING" ]; then
  echo "導入するパッケージ:$MISSING"
  apt-get update
  apt-get install -y $PKGS
else
  echo "必要なパッケージはすべて導入済み（apt を省略）"
fi
systemctl enable --now mosquitto

say "3/8 実行ユーザー $RUNUSER"
id "$RUNUSER" >/dev/null 2>&1 || useradd -r -m -s /usr/sbin/nologin "$RUNUSER"
if [ "$OLED_ON" = 1 ] && [ "$IS_PI" != 1 ]; then   # PC の MCP2221A: /dev/i2c-* を $RUNUSER から使えるように
  getent group i2c >/dev/null || groupadd --system i2c
  if systemd-detect-virt -c -q 2>/dev/null; then
    echo "コンテナの中なので I2C の設定は母艦で行ってください（母艦で i2c-dev・hid-mcp2221 を読み込み、/dev/i2c-* をコンテナへ渡して $RUNUSER か i2c グループが読み書きできるように）"
  else
    modprobe i2c-dev 2>/dev/null || true
    modprobe hid-mcp2221 2>/dev/null || true
    echo i2c-dev > /etc/modules-load.d/dxhotspot-i2c.conf                 # 起動のたびに /dev/i2c-* を出す
    cat > /etc/udev/rules.d/60-dxhotspot-i2c.rules <<'RULE'
# dxhotspot: MCP2221A の I2C だけを i2c グループに開ける（PC の SMBus などは開けない）
SUBSYSTEM=="i2c-dev", ATTR{name}=="*MCP2221*", GROUP="i2c", MODE="0660"
RULE
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --subsystem-match=i2c-dev 2>/dev/null || true
  fi
fi
for g in dialout i2c gpio; do getent group $g >/dev/null && usermod -aG $g "$RUNUSER"; done   # 無いグループ（x86 の gpio など）は飛ばす
# Pi で UART がまだ有効でない（再起動後に出る）ときも止めない（20261102b〜。M-8）
ls -l "$MODEM_PORT" 2>/dev/null || echo "$MODEM_PORT はまだありません（UART を有効にしたので、最後の sudo reboot のあとに出ます）"

say "4/8 MMDVM-Host（#$MMDVM_COMMIT）をビルド"
# git と make は $RUNUSER で動かす（$RUNUSER が書けるフォルダの中身を root で実行しない。.git の hook などで root にならないように）
AS_RU="sudo -u $RUNUSER -H"
if [ -d $MMDVM_DIR ] && [ ! -d $MMDVM_DIR/.git ] && [ -n "$(ls -A $MMDVM_DIR 2>/dev/null)" ]; then
  mv $MMDVM_DIR "$MMDVM_DIR.old.$(date +%Y%m%d%H%M%S)"      # git でない中身（手で置いたもの）は退避して取り直す
  echo "前の $MMDVM_DIR は $MMDVM_DIR.old.* に退避しました"
fi
mkdir -p $MMDVM_DIR
chown "$RUNUSER:$RUNUSER" $MMDVM_DIR
[ -d $MMDVM_DIR/.git ] && chown -R "$RUNUSER:$RUNUSER" $MMDVM_DIR
[ -d $MMDVM_DIR/.git ] || $AS_RU git clone -q https://github.com/g4klx/MMDVMHost.git $MMDVM_DIR
$AS_RU git -C $MMDVM_DIR fetch -q origin || true
if [ "$($AS_RU git -C $MMDVM_DIR rev-parse --short=7 HEAD 2>/dev/null || true)" != "$MMDVM_COMMIT" ]; then
  # 別の版の MMDVMHost（手で入れたもの等）: 手を入れた ini は控えてから、この版に強制的に切り替える
  if [ -f "$INI" ]; then backup "$INI" "$INI.bak.$(date +%Y%m%d%H%M%S)"; fi
  $AS_RU git -C $MMDVM_DIR checkout -q -f "$MMDVM_COMMIT"
fi
# 作業フォルダは $MMDVM_DIR にしない（root の python3 - などが $RUNUSER の書けるフォルダから import しないように。20261102b〜）
cd /
# 前からある別の版（手でビルドしたものなど）は作り直す: ini の書式がこの版（#$MMDVM_COMMIT）と合わないため
if [ -x $MMDVM_DIR/MMDVM-Host ] && ! $MMDVM_DIR/MMDVM-Host -v 2>&1 | grep -q "$MMDVM_COMMIT"; then
  echo "今の MMDVM-Host は別の版: #$MMDVM_COMMIT で作り直します"
  $AS_RU make -C $MMDVM_DIR clean >/dev/null 2>&1 || true
  rm -f $MMDVM_DIR/MMDVM-Host
fi
# D-STAR の「ローカル CQ」（RPT2 がゲートウェイ宛てでない）も、単信（Duplex=0）ならネットへ出す（dxhotspot の修正）。
# MMDVM-Host は RPT2 が「コール＋G」のときだけネットへ出すので、無線機の宛先がローカル CQ だと黙って抜けない。
# 単信のホットスポットにはローカルで中継する相手がいないので、出してよい。二重（Duplex=1）は元のまま。
LOCALCQ_MARK="dxhotspot: single-frequency hotspot forwards Local CQ too"
if ! grep -q "$LOCALCQ_MARK" $MMDVM_DIR/DStarControl.cpp; then
  $AS_RU sed -i "s#m_net = ::memcmp(gateway, m_gateway, DSTAR_LONG_CALLSIGN_LENGTH) == 0;#m_net = !m_duplex || ::memcmp(gateway, m_gateway, DSTAR_LONG_CALLSIGN_LENGTH) == 0;\t// $LOCALCQ_MARK#" $MMDVM_DIR/DStarControl.cpp
  if [ "$(grep -c "$LOCALCQ_MARK" $MMDVM_DIR/DStarControl.cpp)" = 2 ]; then
    echo "MMDVM-Host: ローカル CQ もネットへ出す修正を当てました（DStarControl.cpp だけ作り直す）"
    rm -f $MMDVM_DIR/MMDVM-Host
  else
    echo "注意: ローカル CQ の修正を当てられません（MMDVM-Host のソースが想定と違う）。無線機の宛先はゲートウェイ CQ にしてください"
  fi
fi
if [ ! -x $MMDVM_DIR/MMDVM-Host ]; then
  MEM_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
  JOBS=$(nproc)
  if [ "$MEM_MB" -lt 1000 ]; then
    # Zero 2W（512MB）: 2 並列でもスワップが詰まって固まる。1 並列＋一時スワップ 1GB で組む
    JOBS=1
    if ! swapon --show=NAME --noheadings | grep -q /swapbuild; then
      fallocate -l 1G /swapbuild && chmod 600 /swapbuild && mkswap /swapbuild >/dev/null && swapon /swapbuild
    fi
  fi
  $AS_RU make -C $MMDVM_DIR -j"$JOBS"
  if swapon --show=NAME --noheadings | grep -q /swapbuild; then swapoff /swapbuild; rm -f /swapbuild; fi
fi
ls -l $MMDVM_DIR/MMDVM-Host

say "5/8 MMDVM-Host.ini を原本から生成（D-STAR 専用）"
# 新しい ini は別の名前で作り、局の値を書き終えてから置き換える（途中で失敗しても今の ini は残る）
#   組み立ては root だけの $WORK で行う（以前は $MMDVM_DIR/MMDVM-Host.ini.new。20261102b〜。M-9）
NEWINI="$WORK/MMDVM-Host.ini.new"
nolink "$INI" "$INI.orig"
rm -f "$INI.new" "$INI.new.lock" "$INI.new.orig" "$INI.new.bak.web"     # 以前の版の残り（.new に --apply して出来たもの。L-5）
# 送受信のレベルは前の [Modem] から引き継ぐ（雛形に無いキーは足す。周波数補正 RX/TXOffset は 0/8 で読んだ値を settings.py が書き戻す）
#   以前は TXLevel だけで、画面の調整カードの YSFTXLevel・手で下げた RFLevel が再実行で戻った（20261102b〜。M-7）
MODEM_KEEP_KEYS="TXLevel RFLevel YSFTXLevel DStarTXLevel DMRTXLevel RXLevel CWIdTXLevel"
KEEP_MODEM=""          # 「キー=値」の空白区切り（値は数字と . だけ。sed に渡すので）
if [ -f "$INI" ]; then
  backup "$INI" "$INI.bak.$(date +%Y%m%d%H%M%S)"
  ls -t "$INI".bak.2* 2>/dev/null | tail -n +6 | xargs -r rm -f || true      # 控えは新しい 5 つだけ残す
  for k in $MODEM_KEEP_KEYS; do
    v=$(sed -n "/^\[Modem\]/,/^\[/ s/^$k=\([0-9][0-9.]*\)[[:space:]]*\$/\1/p" "$INI" | head -1 || true)
    if [ -n "$v" ]; then KEEP_MODEM="$KEEP_MODEM $k=$v"; fi
  done
fi
keep_modem() {   # keep_modem ini … KEEP_MODEM を [Modem] に書く（無いキーは [Modem] の見出しの次に足す）
  local kv k v
  for kv in $KEEP_MODEM; do
    k=${kv%%=*}; v=${kv#*=}
    if awk -v k="$k" '/^\[/{s=$0} s=="[Modem]" && index($0, k "=")==1 {f=1} END{exit !f}' "$1"; then
      sed -i "/^\[Modem\]/,/^\[/ s/^$k=.*/$k=$v/" "$1"
    else
      sed -i "/^\[Modem\]/a $k=$v" "$1"
    fi
  done
}
$AS_RU git -C $MMDVM_DIR show HEAD:MMDVM-Host.ini > "$NEWINI"
INI_FINAL="$INI"; INI="$NEWINI"      # この先 6/8 の最後までは新しい ini を書く
# まず全モード・CW ID・ロックファイル等を 0 にしてから、D-Star と D-Star Network だけ 1 に戻す
sed -i 's/^Enable=1/Enable=0/' "$INI"
sed -i \
  -e '/^\[General\]/,/^\[/ s/^Duplex=.*/Duplex=0/' \
  -e '/^\[Modem\]/,/^\[/ s/^Protocol=.*/Protocol=uart/' \
  -e "/^\[Modem\]/,/^\[/ s|^UARTPort=.*|UARTPort=$MODEM_PORT|" \
  -e '/^\[Modem\]/,/^\[/ s/^UARTSpeed=.*/UARTSpeed=115200/' \
  -e '/^\[D-Star\]/,/^\[/ s/^Enable=.*/Enable=1/' \
  -e '/^\[D-Star\]/,/^\[/ s/^# ModeHang=10$/ModeHang=10/' \
  -e '/^\[D-Star Network\]/,/^\[/ s/^Enable=.*/Enable=1/' \
  -e '/^\[MQTT\]/,/^\[/ s/^Auth=.*/Auth=0/' \
  "$INI"
keep_modem "$INI"
# コール⇔DMR ID の一覧（[DMR Id Lookup] File=DMRIds.dat、作業フォルダ基準）。毎日更新（DMR を使っていなければ何もしない）
cat > /usr/local/bin/dmrids-update <<UNIT
#!/bin/sh
# RF が DMR（MMDVM-Host の [DMR]）か、config.ini の [mode] に dmr があるときに要る
{ grep -A3 '^\[DMR\]' $INI_FINAL | grep -q '^Enable=1'; } || \
{ sed -n '/^\[mode\]/,/^\[/p' $DX_DIR/config.ini 2>/dev/null | grep -qE '^(rf|net) *= *dmr'; } || exit 0
# $RUNUSER で動く（dmrids-update.service の User=）。root で $RUNUSER のフォルダを触らない
curl -sfL -o $MMDVM_DIR/DMRIds.dat.new "$DMRIDS_URL" && [ -s $MMDVM_DIR/DMRIds.dat.new ] && mv -f $MMDVM_DIR/DMRIds.dat.new $MMDVM_DIR/DMRIds.dat
UNIT
chmod 755 /usr/local/bin/dmrids-update
cat > /etc/systemd/system/dmrids-update.service <<UNIT
[Unit]
Description=DMRIds.dat を更新（radioid）
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
User=$RUNUSER
ExecStart=/usr/local/bin/dmrids-update
Restart=on-failure
RestartSec=300
UNIT
cat > /etc/systemd/system/dmrids-update.timer <<UNIT
[Unit]
Description=DMRIds.dat を毎日更新
[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true
[Install]
WantedBy=timers.target
UNIT
chown -R "$RUNUSER:$RUNUSER" $MMDVM_DIR

cat > /etc/systemd/system/mmdvm-host.service <<EOF
[Unit]
Description=MMDVM-Host (D-STAR hotspot)
After=network-online.target mosquitto.service
Wants=network-online.target

[Service]
Type=simple
User=$RUNUSER
WorkingDirectory=$MMDVM_DIR
ExecStart=$MMDVM_DIR/MMDVM-Host $INI_FINAL
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

say "6/8 dxmcore（バイナリ）"
NEW_CFG=0; [ -f $DX_DIR/config.ini ] || NEW_CFG=1      # 見本から新しく作るとき（音声応答・ブラウザ送信の MY の初期値を入れる）
mkdir -p "$DX_DIR"
nolink "$DX_DIR" "$DX_DIR/static" "$DX_DIR/config.ini" "$DX_DIR/key.pem" "$DX_DIR/cert.pem" "$DX_DIR/dstar-live"
install -m 755 "$BINDIR/dstar-live" "$DX_DIR/dstar-live"
mkdir -p "$DX_DIR/static"
cp --remove-destination "$DXMSRC"/static/* "$DX_DIR/static/"
cp --remove-destination "$DXMSRC/config.ini.example" "$DX_DIR/config.ini.example"
[ -f "$DXMSRC/NOTICE.md" ] && cp --remove-destination "$DXMSRC/NOTICE.md" "$DX_DIR/"
rm -rf "$DX_DIR/__pycache__"
rm -f "$DX_DIR"/*.py                                   # 以前 .py で入れていた機械を bin に入れ替えるとき
if [ ! -f "$DX_DIR/config.ini" ]; then
  cp --remove-destination "$DXMSRC/config.ini.example" "$DX_DIR/config.ini"
  echo "config.ini を作成しました → $DX_DIR/config.ini"
else
  echo "既存の config.ini を保持しました"
fi
# 自己署名証明書（LAN の IP と hostname.local を SAN に入れる）
if [ ! -f "$DX_DIR/cert.pem" ]; then
  _IP=$(hostname -I 2>/dev/null | awk '{print $1}'); _HN=$(hostname)
  rm -f "$DX_DIR/key.pem" "$DX_DIR/cert.pem"
  _SAN="DNS:${_HN},DNS:${_HN}.local"; [ -n "$_IP" ] && _SAN="IP:${_IP},${_SAN}"
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$DX_DIR/key.pem" -out "$DX_DIR/cert.pem" -subj "/CN=dstar-live" \
    -addext "subjectAltName=${_SAN}" -addext "basicConstraints=critical,CA:TRUE" 2>/dev/null
  echo "証明書を生成しました（SAN: ${_SAN}）"
fi
chown -R "$RUNUSER":"$RUNUSER" "$DX_DIR"
chmod 600 "$DX_DIR/key.pem"; chmod 640 "$DX_DIR/config.ini"
# サービス（bin を起動。DXM_DIR で設定と static の場所を渡す＝単一実行ファイルでは必須）
sed -e "s/__USER__/${RUNUSER}/" \
    -e "s|^ExecStart=.*|ExecStart=$DX_DIR/dstar-live|" \
    "$DXMSRC/dstar-live.service" > /etc/systemd/system/dstar-live.service
grep -q '^Environment=DXM_DIR=' /etc/systemd/system/dstar-live.service \
  || sed -i "/^\[Service\]/a Environment=DXM_DIR=$DX_DIR" /etc/systemd/system/dstar-live.service
systemctl daemon-reload
systemctl enable dstar-live.service >/dev/null 2>&1 || true
systemctl stop dstar-live 2>/dev/null || true

plugin_ok() {   # arm64 は大きさ、x86_64 は ELF の 64bit かどうか
  local f=$DX_DIR/$PLUGIN_FILE
  [ -s "$f" ] || return 1
  if [ "$PARCH" = arm64 ]; then [ "$(stat -c %s "$f")" = "$PLUGIN_SIZE" ]
  else [ "$(head -c 5 "$f" | od -An -tx1 | tr -d ' \n')" = "7f454c4602" ]; fi
}
nolink "$DX_DIR/$PLUGIN_FILE"
# 取得は $WORK へ（root の curl で $DX_DIR のリンクの先に書かない。20261102b〜。M-9）
if [ "$SOFT_AMBE" = yes ] && ! plugin_ok && curl -sL -o "$WORK/$PLUGIN_FILE" "$PLUGIN_URL"; then place "$WORK/$PLUGIN_FILE" "$DX_DIR/$PLUGIN_FILE" 022; fi
if [ "$SOFT_AMBE" = yes ] && ! plugin_ok; then
  rm -f $DX_DIR/$PLUGIN_FILE
  if [ "$QSO_VOCODER" = yes ]; then echo "DroidStar プラグインを取得できません（QSO One のボコーダーで続行）"
  else echo "vocoder プラグインのダウンロードに失敗（ボコーダーがありません。QSO One を使うには DXH_QSO_VOCODER=yes）"; exit 1; fi
fi

# config.ini も $WORK の写しを書き、7/8 の最後に置く（root が $DX_DIR のリンクの先に書かない。20261102b〜。M-9）
CFG_FINAL=$DX_DIR/config.ini
nolink "$CFG_FINAL" "$CFG_FINAL.lock" "$CFG_FINAL.orig" "$CFG_FINAL.bak.web"
backup "$CFG_FINAL" "$CFG_FINAL.bak.$(date +%Y%m%d%H%M%S)"
ls -t "$CFG_FINAL".bak.2* 2>/dev/null | tail -n +6 | xargs -r rm -f || true      # 控えは新しい 5 つだけ残す
CFG=$WORK/config.ini
cat "$CFG_FINAL" > "$CFG"
[ "$SOFT_AMBE" = yes ] && sed -i -e '/^\[ambe\]/,/^\[/ s/^mode *=.*/mode = soft/' $CFG    # 同意したときだけソフト。ほかは今の設定（新規は server）のまま
sed -i \
  -e '/^\[hat\]/,/^\[/ s/^enable *=.*/enable = yes/' \
  -e '/^\[hat\]/,/^\[/ s/^allow_addr *=.*/allow_addr = 127.0.0.1/' $CFG
# ソフトのボコーダー：DroidStar プラグインを 1 件目として登録（既にあれば触らない）。
# ほかのボコーダーは利用者が任意に [vocoder.名前] を足して、Web の設定画面で選ぶ。
if [ "$SOFT_AMBE" = yes ] && [ -s $DX_DIR/$PLUGIN_FILE ] && ! grep -q '^\[vocoder\.droidstar\]' $CFG; then
  cat >> $CFG <<EOF

[vocoder.droidstar]
label = DroidStar プラグイン
type = plugin
path = $DX_DIR/$PLUGIN_FILE
gain = 2.0
EOF
fi
# [ambe] の中に vocoder が無ければ足す（ほかの節の vocoder = に引っかからないよう [ambe] の範囲だけを見る）
[ "$SOFT_AMBE" = yes ] && { sed -n '/^\[ambe\]/,/^\[/p' $CFG | grep -q '^vocoder *=' || sed -i '/^\[ambe\]/a vocoder = droidstar' $CFG; }
[ "$SOFT_AMBE" = yes ] && { mkdir -p /opt/dxhotspot; date '+%Y-%m-%d %H:%M:%S ソフトウェアの AMBE の使用に同意（自己の実験・研究。責任は使用者）' > "$AGREE_FILE"; chmod 644 "$AGREE_FILE"; }
# DMR（1.8.0 の配置: [mode] rf/net、[dmr] 共通、[dmr_rf] 電波側、[dmr_net] ネット側。無い節だけ足す。
#   1.7.x 以前の config.ini（net_to_rf などがある）は足さない。settings.py / dstar-live が dxconfig.migrate で値ごと移す）
grep -qE '^(net_to_rf|repeater_id) *=' $CFG || grep -q '^\[mode\]' $CFG || printf '\n[mode]\n# 運用モード（電波側 rf ・ ネット側 net: dstar / dmr）。画面の「運用モード」で切り替える\nrf = dstar\nnet = dstar\n' >> $CFG
grep -qE '^(net_to_rf|repeater_id) *=' $CFG || grep -q '^\[dmr\]' $CFG || printf '\n[dmr]\n# DMR の身元と共通設定（電波側・ネット側で共通）\nid =\ncolor_code = 1\nvocoder = droidstar\ntx_gain = 1.0\nrx_gain = 1.0\ndmrids = %s/DMRIds.dat\nallow_all = no\nmy_suffix = A\n' "$MMDVM_DIR" >> $CFG
[ "$SOFT_AMBE" = yes ] || grep -q '^\[vocoder\.' $CFG || sed -i '/^\[dmr\]/,/^\[/ s/^vocoder *= *droidstar *$/vocoder =/' $CFG   # ハードウェアの AMBE: 無いボコーダーを指さない
grep -q '^\[dmr_net\]' $CFG || printf '\n[dmr_net]\n# ネット側 DMR（DMR のマスターへ Homebrew 方式でつなぐ）。画面の「DMR ネット」で設定する\nnetwork = tgif\ntg = 9\nslot = 2\nrenew_sec = 300\ntg_follow = yes\nmonitor = yes\n' >> $CFG
grep -q '^\[dmr_net.tgif\]' $CFG || printf '\n[dmr_net.tgif]\nhost = tgif.network\nport = 62031\npassword =\n' >> $CFG
grep -q '^\[dmr_net.bm\]' $CFG || printf '\n[dmr_net.bm]\nhost =\nport = 62031\npassword =\noptions =\n' >> $CFG
grep -q '^\[dmr_net.xlx\]' $CFG || printf '\n[dmr_net.xlx]\n# モジュールは TG で選ぶ（4001 = A … 4026 = Z）\nnumber =\nport = 62030\npassword = passw0rd\n' >> $CFG
grep -q '^\[dmr_rf\]' $CFG || printf '\n[dmr_rf]\n# 電波側 DMR（MMDVM-Host の [DMR Network] の相手）\nnet_tg = 9\nnet_slot = 2\ngateway_port = 62031\nmmdvm_address = 127.0.0.1\nmmdvm_port = 62032\n' >> $CFG
# ボコーダーの資材を取りに行く（同意した人だけ。配布物には入れていない）
VOCDIR=""
if [ "$QSO_VOCODER" = yes ] || [ "$MD380_VOCODER" = yes ]; then
  VOCDIR="$WORK/vocoders"; mkdir -p "$VOCDIR"
  echo "ボコーダーの資材を取得します: $VOC_BASE"
  _vocok=1
  for f in build_qso_vocoder.sh build_md380_vocoder.sh qso_dv_dxm.cpp md380_dv.c dmr_ambe_fec.h LICENSE; do
    curl -fsSL --retry 2 -o "$VOCDIR/$f" "$VOC_BASE/$f" || { echo "  取得できません: $f"; _vocok=0; break; }
  done
  if [ "$_vocok" != 1 ]; then
    echo "ボコーダーの資材を取得できませんでした（取得元が非公開か、通信ができません）。"
    echo "ハードウェアの AMBE（AMBEserver）でそのまま続けます。あとから入れ直すこともできます。"
    QSO_VOCODER=no; MD380_VOCODER=no; VOCDIR=""
  fi
fi
# QSO One のボコーダー（ソースからビルド。D-STAR と DMR の両方）
if [ "$QSO_VOCODER" = yes ]; then
  if bash "$VOCDIR/build_qso_vocoder.sh" /opt/vocoders; then
    if ! grep -q '^\[vocoder\.qso\]' $CFG; then
      printf '\n[vocoder.qso]\nlabel = QSO One（この Pi でビルド）\ntype = pipe\ncommand = /opt/vocoders/qso_dv_dxm\ngain = 1.0\n' >> $CFG
      # 初めて入れたときだけ選ぶ（再実行では Web で選んだものを尊重）
      sed -i '/^\[ambe\]/,/^\[/ s/^vocoder *= *droidstar *$/vocoder = qso/' $CFG
      sed -i -e '/^\[dmr\]/,/^\[/ s/^vocoder *= *droidstar *$/vocoder = qso/' -e '/^\[dmr_rf\]/,/^\[/ s/^vocoder *= *droidstar *$/vocoder = qso/' $CFG
    fi
  else
    echo "QSO One のボコーダーのビルドに失敗（DroidStar プラグインで続行）"
  fi
fi
# MD-380 のファームの AMBE+2（DMR の符号化・復号。D-STAR には使わない）
if [ "$MD380_VOCODER" = yes ]; then
  if bash "$VOCDIR/build_md380_vocoder.sh" /opt/vocoders; then
    if ! grep -q '^\[vocoder\.md380\]' $CFG; then
      printf '\n[vocoder.md380]\nlabel = MD-380 ファーム（DMR）\ntype = pipe\ncommand = /opt/vocoders/md380_dv\nmodes = dmr\ngain = 1.0\n' >> $CFG
      sed -i -e '/^\[dmr\]/,/^\[/ s/^vocoder *=.*/vocoder = md380/' -e '/^\[dmr_rf\]/,/^\[/ s/^vocoder *=.*/vocoder = md380/' $CFG
    fi
  else
    echo "MD-380 のボコーダーのビルドに失敗（DMR は今のボコーダーのまま）"
  fi
fi
# 音声応答（UR の命令に音声で返す。ボコーダーは [ambe] vocoder と同じもの）
if [ "$NEW_CFG" = 1 ]; then sed -i '/^\[announce\]/,/^\[/ s/^enable *=.*/enable = yes/' $CFG; fi   # 見本は enable = no
grep -q '^\[announce\]' $CFG || printf '\n[announce]\nenable = yes\n# 空なら [ambe] vocoder と同じ\nvocoder =\nspeed = 1.1\nlevel_db = -20\ndelay = 1.0\n' >> $CFG
# 1.8.2: 音声応答の速さの既定を 1.3 → 1.1（旧既定のままなら置き換える。好みで変えていればそのまま）
sed -i '/^\[announce\]/,/^\[/{s/^speed *= *1\.3 *\r\?$/speed = 1.1/}' $CFG
# 局ごとの値（コール・周波数・許可コール・DMR）を MMDVM-Host.ini と config.ini に書く（Web の設定と同じ処理）
# --new-mmdvm: 作りたての ini には .orig・.bak.web を作らない（20261102b〜。L-5）
"$SET" --apply --new-mmdvm "$INI" "$CFG"
# ブラウザ送信の MY（[tx] mycall）が見本の値（MYCALL C）か空なら、接続先に名乗るコールにする
TXMY=$(sed -n '/^\[tx\]/,/^\[/ s/^mycall *= *//p' $CFG | head -1 || true)
case "$TXMY" in ""|"MYCALL C"|MYCALL*) sed -i "/^\[tx\]/,/^\[/ s/^mycall *=.*/mycall = $DXH_SESSION_CALL/" $CFG ;; esac
keep_modem "$INI"
chown -R "$RUNUSER:$RUNUSER" $MMDVM_DIR
echo "--- MMDVM-Host の有効なモード ---"
awk '/^\[/{s=$0} /^Enable=1/{print "  " s}' "$INI"
grep -nE '^(Callsign|Id|Duplex|RXFrequency|TXFrequency|RXOffset|TXOffset|Module|ColorCode)=' "$INI"
# HAT への送信先 = MMDVM-Host の DSRP LocalPort（poll や RF を待たずに送れるように。生存判定 90 秒は本体側）
LP=$(awk '/^\[/{s=$0} s=="[D-Star Network]" && /^LocalPort=/{split($0,a,"=");print a[2]}' "$INI"); LP=${LP:-20011}
if grep -q '^mmdvm_addr *=' $CFG; then sed -i "s/^mmdvm_addr *=.*/mmdvm_addr = 127.0.0.1:$LP/" $CFG
else sed -i "/^\[hat\]/a mmdvm_addr = 127.0.0.1:$LP" $CFG; fi
# 設定画面から周波数を変えるための MMDVM-Host.ini の場所
if grep -q '^mmdvm_ini *=' $CFG; then sed -i "s|^mmdvm_ini *=.*|mmdvm_ini = $INI_FINAL|" $CFG
else sed -i "/^\[hat\]/a mmdvm_ini = $INI_FINAL" $CFG; fi
chown -R "$RUNUSER:$RUNUSER" $DX_DIR
grep -nE '^(mycall|mode|vocoder|enable|allow_addr|rf_call|rf_module|allow_calls|rf|net|id|net_tg|tg|network) *=|^\[vocoder|^\[dmr|^\[mode' $CFG
grep -nE '^mmdvm_(addr|ini)' $CFG
# 局の値まで書けたので、新しい ini に置き換える
INI="$INI_FINAL"
# .orig は「dxhotspot が手を入れる前」の版。まだ無ければ今の ini を残す（以前は .new に --apply して .new.orig が出来ていた。L-5）
if [ -f "$INI" ] && [ ! -e "$INI.orig" ]; then backup "$INI" "$INI.orig"; chown -h "$RUNUSER:$RUNUSER" "$INI.orig"; fi
place "$NEWINI" "$INI" 022            # （20261102b〜。M-9）

say "7/8 dxhotspot（OLED ＋ HAT ダッシュボード）"
mkdir -p $OLED_DIR
rm -f $OLED_DIR/dash.html
# 置いてある名前がリンクでも、その先には書かない（消してから作る。20261102b〜。M-9）
rm -f $OLED_DIR/*.py $OLED_DIR/hs_inject.html $OLED_DIR/logo.svg $OLED_DIR/favicon.svg $OLED_DIR/wifi.html
rm -rf $OLED_DIR/__pycache__
install -m 755 "$BINDIR/dxhotspot" $OLED_DIR/dxhotspot      # 素材（logo.svg 等）は bin の中
# hotspot.ini も $WORK で組み立てて、この節の最後に置く（20261102b〜。M-9）
HSINI_FINAL=$OLED_DIR/hotspot.ini
HSINI=$WORK/hotspot.ini
nolink "$HSINI_FINAL" "$HSINI_FINAL.lock" "$HSINI_FINAL.orig" "$HSINI_FINAL.bak.web"
KEEP_ROT=""
OLD_INI=""
if [ -f "$HSINI_FINAL" ]; then
  OLD_INI="$HSINI_FINAL.bak.$(date +%Y%m%d%H%M%S)"
  backup "$HSINI_FINAL" "$OLD_INI"
  KEEP_ROT=$(sed -n 's/^rotate *= *\([0-9]*\).*/\1/p' "$OLD_INI" | head -1 || true)
else
  OLD_INI=$(ls -t $OLED_DIR/hotspot.ini.bak.* 2>/dev/null | head -1 || true)   # 初回は控えが無い: ls が 2 を返しても止めない（set -e・pipefail）
  if [ -n "$OLD_INI" ] && [ -L "$OLD_INI" ]; then OLD_INI=""; fi
fi
ls -t $OLED_DIR/hotspot.ini.bak.* 2>/dev/null | tail -n +6 | xargs -r rm -f || true   # 控えは新しい 5 つだけ残す（20261102b〜。L-5）
cat "$HERE/app/hotspot.ini" > "$HSINI"
# 前の [oled] の値（rotate・セイバー・暗転など）を引き継ぐ（新しいキーは既定値のまま）
if [ -n "$OLD_INI" ]; then
python3 -I - "$OLD_INI" "$HSINI" <<'PY'
import re, sys
def sect(lines):
    cur, out = "", {}
    for i, l in enumerate(lines):
        m = re.match(r"\s*\[(\w+)\]", l)
        if m:
            cur = m.group(1)
            continue
        m = re.match(r"\s*([\w.]+)\s*=\s*(.*?)\s*$", l)
        if m and cur in ("oled", "web", "general", "wifi"):   # 前回の [oled]・[web]・[general]・[wifi] を引き継ぐ
            out[cur + "." + m.group(1)] = (i, m.group(2))
    return out
old = sect(open(sys.argv[1]).read().splitlines())
lines = open(sys.argv[2]).read().splitlines()
OLD_DEFAULTS = {("oled.saver", "clock"), ("oled.saver_after_sec", "300")}   # 以前の既定値は引き継がない（10 秒で消灯が新しい既定）
SKIP = {"web.admin_hash", "general.dxmonitor_url"}                            # これは install.sh が決め直す
for k, (i, _) in sect(lines).items():
    if k in old and (k, old[k][1]) not in OLD_DEFAULTS and k not in SKIP:
        lines[i] = "%s = %s" % (k.split(".", 1)[1], old[k][1])
open(sys.argv[2], "w").write("\n".join(lines) + "\n")
PY
fi
if [ -n "$KEEP_ROT" ]; then sed -i "s/^rotate *=.*/rotate = $KEEP_ROT/" "$HSINI"       # 前回の向き
elif [ -n "$OLED_ROTATE" ]; then sed -i "s/^rotate *=.*/rotate = $OLED_ROTATE/" "$HSINI"; fi   # 初回
# OLED を使うか（上の判定）。見つからなかったときは、初回は使わない・再実行は前回のまま（20261101c〜。以前は Pi 以外は必ず使わない）
if [ "$OLED_ON" = 1 ]; then sed -i '/^\[oled\]/,/^\[/ s/^enable *=.*/enable = yes/' "$HSINI"
elif [ "$OLED_ON" = 0 ] || [ -z "$OLD_INI" ]; then sed -i '/^\[oled\]/,/^\[/ s/^enable *=.*/enable = no/' "$HSINI"; fi
[ -z "$OLED_SET" ] || sed -i "/^\[oled\]/,/^\[/ s|^i2c_port *=.*|i2c_port = $OLED_SET|" "$HSINI"
# 予備の AP のパスワード: 無い・空・配布物の既定（dxhotspot）のままなら、この機械だけの 12 文字（英数）を作る。
#   最後に表示する。再実行では前回のもの（画面で変えたもの）を引き継ぐ（20261102b〜。M-12）
AP_PW_NEW=""
CUR_APPW=$(sed -n '/^\[wifi\]/,/^\[/ s/^ap_password *= *\(.*\)$/\1/p' "$HSINI" | head -1 || true)
CUR_APPW="${CUR_APPW%"${CUR_APPW##*[![:space:]]}"}"
if [ -z "$CUR_APPW" ] || [ "$CUR_APPW" = dxhotspot ]; then
  AP_PW_NEW=$(python3 -I -c 'import secrets, string; a = string.ascii_letters + string.digits; print("".join(secrets.choice(a) for _ in range(12)))')
  if awk '/^\[/{s=$0} s=="[wifi]" && /^ap_password *=/ {f=1} END{exit !f}' "$HSINI"; then
    sed -i "/^\[wifi\]/,/^\[/ s/^ap_password *=.*/ap_password = $AP_PW_NEW/" "$HSINI"
  elif grep -q '^\[wifi\]' "$HSINI"; then
    sed -i "/^\[wifi\]/a ap_password = $AP_PW_NEW" "$HSINI"
  else
    printf '\n[wifi]\nap_password = %s\n' "$AP_PW_NEW" >> "$HSINI"
  fi
fi
PORT=$(sed -n '/^\[web\]/,/^\[/ s/^port *= *\([0-9]*\).*/\1/p' $CFG | head -1 || true)
# dxmcore は同じ機械の中だけで待ち受け、平文 HTTP にする（外からは統合画面 443 の https だけ。暗号化は統合画面が行う）
#   TLS の二重処理（ブラウザ→443、443→8080）をやめて、Pi Zero の CPU と遅延を減らす
sed -i -E '/^\[web\]/,/^\[/ s/^tls *=.*/tls = no/' $CFG
if sed -n '/^\[web\]/,/^\[/p' $CFG | grep -qE '^bind *='; then
  sed -i -E '/^\[web\]/,/^\[/ s/^bind *=.*/bind = 127.0.0.1/' $CFG
else
  sed -i '/^\[web\]/a bind = 127.0.0.1' $CFG
fi
sed -i "s|^dxmonitor_url *=.*|dxmonitor_url = http://127.0.0.1:${PORT:-8080}|" "$HSINI"
# 管理パスワードは使わない（前の版で書いた admin_hash・settings_lock を消す）
sed -i "/^\[web\]/,/^\[/ s|^admin_hash *=.*|admin_hash =|" "$HSINI"
for K in admin_hash settings_lock; do sed -i "/^\[web\]/,/^\[/ {/^$K *=/d}" $CFG; done
# $WORK で組み立てた config.ini・hotspot.ini を置く（どちらも 640。パスワードを他のユーザーに読ませない。20261102b〜。M-9）
place "$CFG" "$CFG_FINAL" 027
CFG=$CFG_FINAL
place "$HSINI" "$HSINI_FINAL" 027
# ---- Wi-Fi の切り替え（AP への切り戻し）の下ごしらえ
install -m 755 -o root -g root "$HERE/scripts/dxhotspot-wifi" /usr/local/sbin/dxhotspot-wifi
# 電源を切る最後の段で OLED に「SAFE TO UNPLUG」を出す（systemd の system-shutdown。20261109b〜）
SDDIR=/usr/lib/systemd/system-shutdown; [ -d /usr/lib/systemd ] || SDDIR=/lib/systemd/system-shutdown
mkdir -p $SDDIR && install -m 755 -o root -g root "$HERE/scripts/dxhotspot-oled-final" $SDDIR/dxhotspot-oled
if command -v nmcli >/dev/null 2>&1; then
  # NetworkManager の「共有」（AP）が配る DHCP・DNS に dnsmasq を使う。無いと AP になれない
  for p in dnsmasq-base iw; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' \
      || DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$p" || echo "  $p を入れられませんでした（AP が使えないかもしれません）"
  done
  WIFI_CC=$(sed -n '/^\[wifi\]/,/^\[/ s/^country *= *\([A-Za-z][A-Za-z]\).*/\1/p' $OLED_DIR/hotspot.ini | head -1 || true)
  WIFI_CC=${WIFI_CC:-JP}
  command -v raspi-config >/dev/null 2>&1 && raspi-config nonint do_wifi_country "$WIFI_CC" >/dev/null 2>&1 || true
  command -v iw >/dev/null 2>&1 && iw reg set "$WIFI_CC" >/dev/null 2>&1 || true
  echo "Wi-Fi の切り替え: 使えます（nmcli、国 $WIFI_CC）。つながらないまま起動すると SSID「$(sed -n '/^\[wifi\]/,/^\[/ s/^ap_ssid *= *//p' $OLED_DIR/hotspot.ini | head -1)」の親機になります"
else
  echo "Wi-Fi の切り替え: 使いません（nmcli が無い＝NetworkManager で管理していない機械）"
fi

# Web の設定を保存したとき、変わった側のサービスだけ再起動できるようにする（この 3 つだけ）
SC=$(command -v systemctl)
cat > /etc/sudoers.d/dxhotspot <<EOF
# dxhotspot の Web 設定（/hs/settings）から使う
# このファイルは install.sh が毎回作り直す。手で足す許可は別のファイルに書くこと（poweroff・reboot は画面右上の電源ボタン用。20261109a〜）
$RUNUSER ALL=(root) NOPASSWD: $SC restart mmdvm-host, $SC restart dstar-live, $SC stop dstar-live, $SC start --no-block dmrids-update.service, $SC poweroff, $SC reboot, /usr/local/sbin/dxhotspot-wifi *
EOF
chmod 440 /etc/sudoers.d/dxhotspot
visudo -cf /etc/sudoers.d/dxhotspot >/dev/null || { rm -f /etc/sudoers.d/dxhotspot; echo "sudoers の作成に失敗（Web 設定の再起動は手動）"; }
usermod -aG systemd-journal "$RUNUSER"      # モデムの説明（ファーム）を MMDVM-Host のログから読むため
chown -R "$RUNUSER:$RUNUSER" $OLED_DIR
rm -f /etc/systemd/system/dxhotspot-oled.service
sed -e "s|^ExecStart=.*|ExecStart=$OLED_DIR/dxhotspot|" \
    "$HERE/systemd/dxhotspot.service" > /etc/systemd/system/dxhotspot.service

# 1.6.0（DMRGateway 方式）の後片付け。NET モード DMR は dxmcore 自身が受け持つ
if [ -f /etc/systemd/system/dmrgateway.service ]; then
  systemctl disable --now dmrgateway 2>/dev/null || true
  rm -f /etc/systemd/system/dmrgateway.service
  echo "DMRGateway は使わなくなったので止めました（/opt/DMRGateway は残してあります）"
fi

say "8/8 サービス登録"
systemctl daemon-reload
systemctl disable dxhotspot-oled 2>/dev/null || true
systemctl enable mmdvm-host dstar-live dxhotspot
systemctl enable dmrids-update.timer
# DMRIds.dat の取得（RF モード DMR のときだけ取得される）。初回は再起動前に揃えるため待つ。再実行では裏で行う（既にあるものを使う）
if [ -n "$DMR_ID" ]; then
  if [ "$NEED_REBOOT" = 1 ] || [ ! -s $MMDVM_DIR/DMRIds.dat ]; then
    systemctl start dmrids-update.service || echo "DMRIds.dat の取得に失敗（毎日の更新で再取得）"
  else
    systemctl start --no-block dmrids-update.service || true
  fi
fi

echo
if [ "$NEED_REBOOT" = 1 ]; then
  systemctl start mmdvm-host dstar-live dxhotspot 2>/dev/null || true
  echo "完了。UART・I2C の設定を変えたので sudo reboot してください。"
  echo "再起動後の確認: journalctl -u mmdvm-host -u dstar-live -u dxhotspot -b --no-pager | tail -60"
else
  systemctl restart mmdvm-host dstar-live dxhotspot || echo "サービスの再起動に失敗（journalctl で確認）"
  echo "完了。サービスを再起動しました（mmdvm-host dstar-live dxhotspot）。再起動（reboot）は不要です。"
  echo "確認: journalctl -u mmdvm-host -u dstar-live -u dxhotspot --since -2min --no-pager | tail -60"
fi
echo "画面: https://$(hostname -I 2>/dev/null | awk '{print $1}')/ または https://$(hostname).local/ （http は https に転送）。局の設定は画面の「設定」タブでも変えられる"
if [ "$SOFT_AMBE" != yes ]; then
  echo "ボコーダー: ハードウェアの AMBE で使う設定です。設定タブ「音量と音声」で AMBEserver の接続先を入れてください。"
  echo "  D-STAR ⇔ DMR／YSF の変換と音声応答は、ソフトのボコーダーが無いと使えません（NOTICE.md）。"
fi
# 予備の AP のパスワード（作ったときだけ。画面には出さないので、ここで控えてもらう。20261102b〜。M-12）
if [ -n "$AP_PW_NEW" ]; then
  echo
  echo "=================================================================="
  echo "  予備の AP（Wi-Fi につながらないとき）のパスワードを作りました。控えてください"
  echo "    SSID       $(sed -n '/^\[wifi\]/,/^\[/ s/^ap_ssid *= *//p' "$OLED_DIR/hotspot.ini" | head -1 || true)"
  echo "    パスワード $AP_PW_NEW"
  echo "  （$OLED_DIR/hotspot.ini の [wifi] ap_password。画面の /hs/wifi で変えられる）"
  echo "=================================================================="
fi
