# dxmonitor インストール手順書

版 20261115b 時点。

---

## 0. 入手

配布物は GitHub の **Releases**（`https://github.com/ji2tab/dxmonitor/releases`）に置いています。自分の CPU に合う `dxmonitor_bin_<版>_<arch>.tar.gz` を選びます（Raspberry Pi は `arm64`）。

**この機械のターミナル**で取るなら（`<タグ>`・`<版>` は Releases の表示に合わせる）。

```bash
curl -fLO https://github.com/ji2tab/dxmonitor/releases/download/<タグ>/dxmonitor_bin_<版>_arm64.tar.gz
```

**ブラウザ**で落とした場合は、PC から scp などでこの機械へ送ってください。

---

## 1. 要るもの

### 機械

次のどれか。64bit の OS であること。

1. Raspberry Pi ＋ MMDVM_HS_Hat（GPIO 接続）＋ SSD1306 OLED
2. PC（x86_64 の Debian/Ubuntu）＋ USB の HAT アダプタ（`/dev/ttyUSB0` 等）。OLED なし
3. PC ＋ MCP2221A ＋ MMDVM_HS_Hat。OLED は MCP2221A の I2C

**配布物は CPU ごとに別です。** `BUILD-INFO.txt` の「対象」を確認してください。arm64 の配布物は PC では動きません。

### OS のバージョン

`BUILD-INFO.txt` の `glibc` の行を見てください。**そこに書かれた版より古い OS では動きません。**

### ネットワーク

インストール中に次へ接続します。

- apt のリポジトリ
- `github.com`（MMDVM-Host のソース）
- `radioid.net`（DMRIds.dat）

### 事前に決めておくもの

| 項目 | 内容 |
|---|---|
| ホットスポットのコール | 無線機の RPT1 のコール部分 |
| モジュール | RPT1 の 8 文字目。英字 1 文字（`G` は使えない） |
| 周波数 MHz | 単信。144〜146 / 430〜440 |
| 接続先に名乗るコール | コール＋空白＋サフィックス 1 文字 |
| 使える無線機の MY | カンマ区切り。`*` で制限しない |
| DMR ID | radioid の ID。DMR を使わないなら空 |
| カラーコード | 0〜15。既定 `1` |
| DMR の宛先 TG | 既定 `9` |
| 電波側 | `dstar` / `dmr` / `ysf` |
| ネット側 | `dstar` / `dmr` / `ysf` |

すべて後から画面の「設定」タブで変えられます。

---

## 2. 入れる

**この機械のターミナル**で実行します。

```bash
tar xzf dxmonitor_bin_<版>_<arch>.tar.gz
cd dxmonitor_bin_<版>_<arch>
cat BUILD-INFO.txt          # 対象 CPU と OS を確認
sudo ./install.sh
```

ログを残すなら。

```bash
sudo ./install.sh 2>&1 | tee ~/install_$(date +%Y%m%d_%H%M).log
```

Raspberry Pi Zero 2 W など非力な機械では 30〜60 分かかります。SSH が切れると止まるので `tmux` の中で実行してください。

```bash
sudo apt install -y tmux
tmux new -s inst
cd dxmonitor_bin_<版>_<arch> && sudo ./install.sh
# 切れたら tmux attach -t inst
```

### 聞かれること

**局の設定** … 上の表の項目。Enter で `[ ]` 内の既定のまま。書き方が違うと理由が表示されて聞き直されます。

**ボコーダー（3 問）**

1. ソフトウェア AMBE を使うか … `yes` と入れたときだけ有効。Enter＝使わない（ハードウェア AMBE 前提）
2. QSO One をビルドするか … 1 で `yes` のときだけ。既定 `Y`
3. MD-380 のファームを使うか … 同上。既定 `N`

最後に内容を表示して `[Y/n]` の確認が入ります。

質問を省くなら環境変数で渡せます。

```bash
sudo DXH_CALLSIGN=<コール> DXH_MODULE=D DXH_FREQ_MHZ=438.990 ./install.sh --yes
```

### 何をするのか（8 段）

| 段 | 内容 | 時間の目安 |
|---|---|---|
| 0/8 | 局の設定を質問 | — |
| 1/8 | UART・I2C を有効化、Bluetooth を無効化 | 数秒 |
| 2/8 | apt でパッケージ導入 | 数分 |
| 3/8 | 実行ユーザー `dstar` を作成 | 数秒 |
| 4/8 | MMDVM-Host をビルド | **20〜40 分** |
| 5/8 | MMDVM-Host.ini を生成し局の値を書く | 数秒 |
| 6/8 | 本体・画面・設定・証明書を配置 | 数秒 |
| 7/8 | ホットスポット側を配置 | 数秒 |
| 8/8 | サービス登録 | 数秒 |

4/8 でメモリが 1GB 未満なら、インストーラが一時 swap 1GB を自分で作り、終わったら消します。

### 再起動

初回は最後に「UART・I2C の設定を変えたので `sudo reboot` してください」と出ます。

```bash
sudo reboot
```

再起動するまで MMDVM-Host は HAT を掴めません。

### AP のパスワード

初回は Wi-Fi 予備 AP のパスワードが表示されます。**控えてください。** Wi-Fi につながらないまま起動したときに、この AP から設定できます。後から `/opt/dxhotspot/hotspot.ini` の `[wifi] ap_password` で確認・変更できます。

---

## 3. 確認

再起動後、**この機械のターミナル**で。

```bash
systemctl is-active mmdvm-host dstar-live dxhotspot
journalctl -u mmdvm-host -u dstar-live -u dxhotspot -b --no-pager | tail -40
```

3 つとも `active` であること。ログに次が出ていれば正常です。

```
[web] dstar_ambe v1.8.5  http://127.0.0.1:8080/ でライブ配信中
[hat] MMDVMHost 検出 127.0.0.1:20011
[web] 統合画面 https://0.0.0.0:443/
[oled] 表示開始 <コール> <モジュール> <周波数> / <IP>
```

**ブラウザ**で `https://<この機械の IP>/` を開きます。自己署名証明書なので警告が出ます。`http://` は `https://` に転送されます。

---

## 4. 入った後の中身

| 場所 | 中身 |
|---|---|
| `/opt/dstar_ambe/` | 本体、画面（`static/`）、`config.ini`、証明書 |
| `/opt/dxhotspot/` | ホットスポット側、`hotspot.ini` |
| `/opt/MMDVMHost/` | MMDVM-Host（この機械でビルド）、`MMDVM-Host.ini`、`DMRIds.dat` |
| `/opt/vocoders/` | ボコーダー（ソフトウェア AMBE に同意したときだけ） |
| `/etc/systemd/system/` | `dstar-live.service`・`dxhotspot.service`・`mmdvm-host.service`・`dmrids-update.*` |
| `/usr/local/sbin/dxhotspot-wifi` | Wi-Fi 切り替えの補助（root が要る所だけ） |

サービスは `dstar` ユーザーで動きます。

---

## 5. ボコーダーについて

ハードウェアの AMBE（AMBEserver）で使うのが基本です。入れたあと画面の「設定」タブで接続先を入れてください。

ソフトウェアの AMBE は**同梱していません**。使う場合は、使用者が自己の実験・研究のために、自己の判断と責任で入手・ビルドして使うものとします。その入手・ビルド・使用と、それによって生じたトラブル・損害・紛争について、製作者は一切関与せず、いかなる責任も負いません。詳しくは `NOTICE.md` を読んでください。

インストール時に同意しなかった場合、ボコーダーに関するものは 1 バイトも取得しません。

ハードウェアの AMBE だけでは、D-STAR ⇔ DMR／YSF の変換と音声応答は使えません。

### 取得に失敗したとき

```
ボコーダーの資材を取得できませんでした（取得元が非公開か、通信ができません）。
ハードウェアの AMBE（AMBEserver）でそのまま続けます。
```

インストールは止まりません。後から入れ直せます。

---

## 6. 入れ直す・消す

### 入れ直す

同じ `install.sh` をもう一度流せば入れ替わります。設定（`config.ini`・`MMDVM-Host.ini`・`hotspot.ini`）は引き継がれ、局の設定は今の値が既定で出ます。

先にバックアップを取ってください。

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

UART・I2C の設定を戻すなら。

```bash
sudo raspi-config nonint do_serial_hw 1
sudo raspi-config nonint do_i2c 1
sudo sed -i '/^dtoverlay=disable-bt$/d' /boot/firmware/config.txt
sudo reboot
```

---

## 7. うまくいかないとき

### `bin がこの機械で動きません`

配布物の CPU がこの機械と違います。`BUILD-INFO.txt` の「対象」を確認し、合うものを使ってください。OS が古すぎる場合も同じ症状になります。

### `モデムが見つかりません`

USB の HAT・MCP2221A をつないでください。場所を指定するなら。

```bash
sudo DXH_MODEM=/dev/ttyACM0 ./install.sh
```

Raspberry Pi で `/dev/ttyAMA0` がまだ無い状態は正常です。インストーラが UART を有効にし、再起動後に現れます。

### OLED が点かない

```bash
ls -l /dev/i2c-*
sudo i2cdetect -y 1          # 0x3C が見えるか
journalctl -u dxhotspot -n 20 --no-pager
```

`[oled] 0x3C が応答しません` なら配線か I2C の有効化を確認してください。再起動していない場合もこれになります。

### 画面が開かない

```bash
systemctl status dxhotspot --no-pager
sudo ss -tlnp | grep -E ':(443|80|8080)'
```

### 設定を保存できない

```
書き込めません: [Errno 13] Permission denied
```

`/opt/MMDVMHost` の持ち主を確認してください。

```bash
ls -ld /opt/MMDVMHost
sudo chown -R dstar:dstar /opt/MMDVMHost
```

### ログの見方

```bash
journalctl -u dstar-live -f
journalctl -u dxhotspot -f
journalctl -u mmdvm-host -f
```
