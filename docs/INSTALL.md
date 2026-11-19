# dxmonitor インストール手順（バイナリ配布）

Raspberry Pi などに、**バイナリ配布（ソースの .py は配りません）**で入れる手順です。

| 項目 | 内容 |
|---|---|
| 対象版 | dxmonitor 1.8.5（配布物 `dxmonitor_bin_<版>_<arch>.tar.gz`） |
| 最終更新 | 2026-11-19 |
| 配布先 | GitHub の Releases: `https://github.com/ji2tab/dxmonitor/releases` |
| 対象 | Raspberry Pi など 64bit（arm64）。CPU・OS の条件は配布物の `BUILD-INFO.txt` |

---

## 0. 入手と展開（コピペ 1 回）

**この機械のターミナル**で、次を丸ごと貼り付けます。最新の配布物（arm64）を自動で取得・展開し、対象 CPU・OS を表示します。**版番号を手で打つ必要はありません。**

```bash
cd ~
read A URL < <(curl -s https://api.github.com/repos/ji2tab/dxmonitor/releases \
 | python3 -c 'import json,sys
for r in json.load(sys.stdin):
 for a in r.get("assets",[]):
  if a["name"].endswith("_arm64.tar.gz"):
   print(a["name"], a["browser_download_url"]); sys.exit()')
echo "取得: $A"
curl -fsSL -o "$A" "$URL"
rm -rf "${A%.tar.gz}"; tar xzf "$A"
cd "${A%.tar.gz}"
echo "=== BUILD-INFO ==="; cat BUILD-INFO.txt
```

- 配布物は **CPU ごとに別**です（arm64 の配布物は x86_64 の PC では動きません）。
- **ビルド機より古い OS では動きません。** 上で表示される `BUILD-INFO.txt` の `glibc` の行を確認してください。
- 特定の版を入れたいときは、Releases のページで版を選び、`dxmonitor_bin_<版>_arm64.tar.gz` を落として `tar xzf` → `cd` してください。

---

## 1. 要るもの

### 機械（次のどれか。64bit の OS）
1. Raspberry Pi ＋ MMDVM_HS_Hat（GPIO 接続）＋ SSD1306 OLED
2. PC（x86_64 の Debian/Ubuntu）＋ USB の HAT アダプタ（`/dev/ttyUSB0` 等）。OLED なし
3. PC ＋ MCP2221A ＋ MMDVM_HS_Hat。OLED は MCP2221A の I2C

### ネットワーク（インストール中に接続します）
apt のリポジトリ、`github.com`（MMDVM-Host のソース）、`radioid.net`（DMRIds.dat）。

### 事前に決めておくもの（すべて後から画面の「設定」タブで変えられます）
| 項目 | 内容 |
|---|---|
| ホットスポットのコール | 無線機の RPT1 のコール部分 |
| モジュール | RPT1 の 8 文字目。英字 1 文字（`G` は不可） |
| 周波数 MHz | 単信。144〜146 / 430〜440 |
| 接続先に名乗るコール | コール＋空白＋サフィックス 1 文字 |
| 使える無線機の MY | カンマ区切り。`*` で制限しない |
| DMR ID | radioid の ID。**DMR を使うなら必須**（空のままだと DMR モードに切り替わりません）。使わないなら空 |
| カラーコード／宛先 TG | 0〜15（既定 `1`）／既定 `9` |
| 電波側／ネット側 | `dstar` / `dmr` / `ysf` |

---

## 2. 入れる

**§0 で展開したフォルダの中にいる状態**で（`cd` 済み）、次を実行します。

```bash
pwd                         # dxmonitor_bin_... の中にいることを確認
sudo ./install.sh
```

ログを残すなら:

```bash
sudo ./install.sh 2>&1 | tee ~/install_$(date +%Y%m%d_%H%M).log
```

Raspberry Pi Zero 2 W など非力な機械では 30〜60 分かかります。SSH が切れると止まるので、心配なら `tmux` の中で（取得から一気に通ります）:

```bash
sudo apt install -y tmux
tmux new -s inst
# ↓ tmux の中で、これを丸ごと貼る
cd ~
read A URL < <(curl -s https://api.github.com/repos/ji2tab/dxmonitor/releases \
 | python3 -c 'import json,sys
for r in json.load(sys.stdin):
 for a in r.get("assets",[]):
  if a["name"].endswith("_arm64.tar.gz"):
   print(a["name"], a["browser_download_url"]); sys.exit()')
curl -fsSL -o "$A" "$URL"; rm -rf "${A%.tar.gz}"; tar xzf "$A"; cd "${A%.tar.gz}"
sudo ./install.sh
# 切れたら tmux attach -t inst
```

### 聞かれること
- **局の設定** … 上の表の項目。Enter で `[ ]` 内の既定のまま。書き方が違うと理由が表示されて聞き直されます。
- **ボコーダー（3 問）** … (1) ソフトウェア AMBE を使うか（`yes` と入れたときだけ有効。Enter＝使わない＝ハードウェア AMBE 前提）、(2) QSO One をビルドするか（既定 `Y`）、(3) MD-380 のファームを使うか（既定 `N`）。最後に内容を表示して `[Y/n]` の確認。

質問を省くなら環境変数で渡せます: `sudo DXH_CALLSIGN=<コール> DXH_MODULE=D DXH_FREQ_MHZ=438.990 ./install.sh --yes`。

### 何をするのか（8 段）
0/8 局の設定を質問 → 1/8 UART・I2C を有効化・Bluetooth を無効化 → 2/8 apt でパッケージ → 3/8 実行ユーザー `dstar` を作成 → **4/8 MMDVM-Host をビルド（20〜40 分）** → 5/8 MMDVM-Host.ini を生成 → 6/8 本体・画面・設定・証明書を配置 → 7/8 ホットスポット側を配置 → 8/8 サービス登録。
4/8 でメモリが 1GB 未満なら、インストーラが一時 swap 1GB を自分で作り、終わったら消します。

### 再起動
初回は最後に「UART・I2C の設定を変えたので `sudo reboot` してください」と出ます。再起動するまで MMDVM-Host は HAT を掴めません。

### AP のパスワード
初回は Wi-Fi 予備 AP のパスワードが表示されます。**控えてください**（Wi-Fi につながらないまま起動したとき、この AP から設定できます）。後から `/opt/dxhotspot/hotspot.ini` の `[wifi] ap_password` で確認・変更できます。

---

## 3. 確認

再起動後、**この機械のターミナル**で:

```bash
systemctl is-active mmdvm-host dstar-live dxhotspot
journalctl -u mmdvm-host -u dstar-live -u dxhotspot -b --no-pager | tail -40
```

3 つとも `active` で、ログに次が出ていれば正常です。

```
[web] dstar_ambe v1.8.5  http://127.0.0.1:8080/ でライブ配信中
[hat] MMDVMHost 検出 127.0.0.1:20011
[web] 統合画面 https://0.0.0.0:443/
[oled] 表示開始 <コール> <モジュール> <周波数> / <IP>
```

**ブラウザ**で `https://<この機械の IP>/` を開きます（自己署名証明書なので警告。`http://` は `https://` に転送）。無線機の設定と最初の交信、画面の使い方は配布物に同梱の `SETUP.md` を参照。

---

## 4. 入った後の中身

| 場所 | 中身 |
|---|---|
| `/opt/dstar_ambe/` | 本体、画面（`static/`）、`config.ini`、証明書 |
| `/opt/dxhotspot/` | ホットスポット側、`hotspot.ini` |
| `/opt/MMDVMHost/` | MMDVM-Host（この機械でビルド）、`MMDVM-Host.ini`、`DMRIds.dat` |
| `/opt/vocoders/` | ボコーダー（ソフトウェア AMBE に同意したときだけ） |
| `/etc/systemd/system/` | `dstar-live`・`dxhotspot`・`mmdvm-host`・`dmrids-update.*` |

サービスは `dstar` ユーザーで動きます。

---

## 5. ボコーダーについて

> **AMBE ボコーダーについて（重要）**
> - 本ソフトウェアは、**ハードウェアの AMBE（AMBEserver など）で使うことを基本**とします。入れたあと画面の「設定」タブで接続先を入れてください。
> - ソフトウェアの AMBE は**同梱していません**。使う場合は、使用者が自己の実験・研究のために、自己の判断と責任で入手・ビルドして使うものとします。その入手・ビルド・使用と、それによって生じたトラブル・損害・紛争について、**製作者は一切関与せず、いかなる責任も負いません**。詳しくは `NOTICE.md`。

- インストール時に同意しなかった場合、ボコーダーに関するものは 1 バイトも取得しません。
- ハードウェアの AMBE だけでは、D-STAR ⇔ DMR／YSF の変換と音声応答は使えません。
- 取得に失敗しても（通信不可など）インストールは止まらず、ハードウェア AMBE 前提でそのまま続けます。後から入れ直せます。

---

## 6. 入れ直す・消す

### 入れ直す（新しい版に更新する）
**§0 を実行して最新を展開 → フォルダの中で `sudo ./install.sh`** をもう一度流せば入れ替わります。設定（`config.ini`・`MMDVM-Host.ini`・`hotspot.ini`）は引き継がれ、局の設定は今の値が既定で出ます。先にバックアップ:

```bash
sudo systemctl stop dxhotspot dstar-live
sudo cp -a /opt/dstar_ambe /opt/dstar_ambe.bak.$(date +%Y%m%d)
sudo cp -a /opt/dxhotspot  /opt/dxhotspot.bak.$(date +%Y%m%d)
```

### 消す
```bash
sudo systemctl stop dxhotspot dstar-live mmdvm-host
sudo systemctl disable dxhotspot dstar-live mmdvm-host dmrids-update.timer
sudo rm -f /etc/systemd/system/{dstar-live,dxhotspot,mmdvm-host,dmrids-update}.service
sudo rm -f /etc/systemd/system/dmrids-update.timer
sudo rm -rf /opt/dstar_ambe /opt/dxhotspot /opt/MMDVMHost /opt/vocoders
sudo rm -f /usr/local/sbin/dxhotspot-wifi /usr/local/bin/dmrids-update
sudo rm -f /etc/sudoers.d/dxhotspot
sudo userdel dstar
sudo systemctl daemon-reload
```

---

## 7. うまくいかないとき

| 症状 | 見ること |
|---|---|
| `bin がこの機械で動きません` | `BUILD-INFO.txt` の「対象」。CPU 違い、または OS が古すぎる |
| `モデムが見つかりません` | USB の HAT・MCP2221A を接続。場所指定は `sudo DXH_MODEM=/dev/ttyACM0 ./install.sh`。Pi で `/dev/ttyAMA0` が未出現は正常（再起動後に現れる） |
| OLED が点かない | `sudo i2cdetect -y 1` で `0x3C` が見えるか。配線・I2C 有効化・未再起動を確認 |
| 画面が開かない | `systemctl status dxhotspot`、`sudo ss -tlnp | grep -E ':(443|80|8080)'` |
| 設定を保存できない（Permission denied） | `sudo chown -R dstar:dstar /opt/MMDVMHost` |
| モードを DMR に変えても D-STAR に戻る | DMR ID が未設定。設定タブ「自局」で DMR ID を入れて保存 |

ログ: `journalctl -u dstar-live -u dxhotspot -u mmdvm-host -f`。

---

認証はありません。LAN（や Tailscale）の誰でも接続・PTT・設定・再起動ができるので、**443/8080 をインターネットに直接公開しないでください**（外から使うなら VPN 経由）。
