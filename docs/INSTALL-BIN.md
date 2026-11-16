# dxmonitor インストール手順書（バイナリ版）

版 20261115b 時点。配布物 `dxmonitor_bin_<版>_<arch>.tar.gz` を受け取った人のための手順。

作る側の手順は `BUILD-BIN.md`。

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
2. PC（x86_64 の Debian/Ubuntu）＋ USB の HAT アダプタ（/dev/ttyUSB0 等）。OLED なし
3. PC ＋ MCP2221A ＋ MMDVM_HS_Hat。OLED は MCP2221A の I2C

**配布物は CPU ごとに別です。** `BUILD-INFO.txt` の「対象」を確認してください。arm64 の配布物は PC では動きません。

### OS のバージョン

`BUILD-INFO.txt` の `glibc` の行を見てください。**配布物をビルドした機械より古い OS では動きません。**

### ネットワーク

インストール中に次へ接続します。

- apt のリポジトリ
- `github.com`（MMDVM-Host のソース。ボコーダーに同意した場合はその資材も）
- `radioid.net`（DMRIds.dat）

### 事前に決めておくもの

| 項目 | 例 |
|---|---|
| ホットスポットのコール | 自局のコール |
| モジュール | `D`（RPT1 の 8 文字目。`G` は使えない） |
| 周波数 MHz | 単信。144〜146 / 430〜440 |
| 接続先に名乗るコール | コール＋空白＋サフィックス 1 文字 |
| 使える無線機の MY | カンマ区切り。`*` で制限しない |
| DMR ID | radioid の ID。DMR を使わないなら空 |
| カラーコード | 既定 `1` |
| DMR の宛先 TG | 既定 `9` |
| 電波側 | `dstar` / `dmr` / `ysf` |
| ネット側 | `dstar` / `dmr` / `ysf` |

後から画面の「設定」タブでも変えられます。

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

### 聞かれること

**局の設定（0/8）** … 上の表の項目。Enter で `[ ]` 内の既定のまま。値が不正なら理由が出て聞き直されます。

**ボコーダー（3 問）**

1. ソフトウェア AMBE を使うか … `yes` と入れたときだけ有効。Enter＝使わない（ハードウェア AMBE 前提）
2. QSO One をビルドするか … 1 で yes のときだけ。既定 `Y`
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
| 4/8 | MMDVM-Host をビルド | **Pi Zero 2 W で 20〜40 分** |
| 5/8 | MMDVM-Host.ini を生成し局の値を書く | 数秒 |
| 6/8 | dxmcore（bin）・画面・設定・証明書を配置 | 数秒 |
| 7/8 | dxhotspot（bin）・Wi-Fi 補助・shutdown 用を配置 | 数秒 |
| 8/8 | サービス登録 | 数秒 |

4/8 でメモリが 1GB 未満なら、インストーラが一時 swap 1GB を自分で作り、終わったら消します。

### 再起動

初回は最後に「UART・I2C の設定を変えたので sudo reboot してください」と出ます。

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
ls -l /dev/ttyAMA0 /dev/i2c-1
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
| `/opt/dstar_ambe/` | `dstar-live`（bin）、`static/`、`config.ini`、`cert.pem`・`key.pem` |
| `/opt/dxhotspot/` | `dxhotspot`（bin）、`hotspot.ini` |
| `/opt/MMDVMHost/` | `MMDVM-Host`（この機械でビルド）、`MMDVM-Host.ini`、`DMRIds.dat` |
| `/opt/vocoders/` | ボコーダー（同意したときだけ） |
| `/etc/systemd/system/` | `dstar-live.service`・`dxhotspot.service`・`mmdvm-host.service`・`dmrids-update.*` |
| `/usr/local/sbin/dxhotspot-wifi` | Wi-Fi 切り替えの補助（root が要る所だけ） |

`.py` は置かれません。読めるのは設定ファイルと画面（HTML/CSS/JS）だけです。

サービスは `dstar` ユーザーで動きます。

---

## 5. バイナリ版で違うところ

| | 内容 |
|---|---|
| ソース | `.py` は配布も設置もされない |
| 画面の「説明」タブ | **バージョン表が空になる**（bin に `.py` が無いため）。ヘッダの版表示は正しく出る。動作に影響なし |
| 電源断メッセージ | `.py` が無いので「SAFE TO UNPLUG」は出ない。他に影響なし |
| 設定の変更 | 画面の「設定」タブで変更可。`.py` 版と同じ |
| ボコーダー | 同意しなければ取得しない。ハード AMBE（AMBEserver）で動く |

---

## 6. ボコーダーについて

ハードウェアの AMBE（AMBEserver）で使うのが基本です。入れたあと画面の「設定」タブで接続先を入れてください。

ソフトウェアの AMBE は**同梱していません**。使う場合は、使用者が自己の実験・研究のために、自己の判断と責任で入手・ビルドして使うものとします。その入手・ビルド・使用と、それによって生じたトラブル・損害・紛争について、製作者は一切関与せず、いかなる責任も負いません。詳しくは `NOTICE.md` を読んでください。

インストール時に同意しなかった場合、ボコーダーの資材は 1 バイトも取得しません。

ハードウェアの AMBE だけでは、D-STAR ⇔ DMR／YSF の変換と音声応答は使えません。

### 取得に失敗したとき

```
ボコーダーの資材を取得できませんでした（取得元が非公開か、通信ができません）。
ハードウェアの AMBE（AMBEserver）でそのまま続けます。
```

インストールは止まりません。後から入れ直せます。

---

## 7. 既に `.py` 版で動いている機械を入れ替える

同じ `install.sh` を流せば入れ替わります。設定（`config.ini`・`MMDVM-Host.ini`・`hotspot.ini`）は引き継がれ、`.py` は消されます。

**先にバックアップを取ってください。**

```bash
sudo systemctl stop dxhotspot dstar-live
sudo cp -a /opt/dstar_ambe /opt/dstar_ambe.bak.$(date +%Y%m%d)
sudo cp -a /opt/dxhotspot  /opt/dxhotspot.bak.$(date +%Y%m%d)
sudo cp -a /etc/systemd/system/dstar-live.service /etc/systemd/system/dstar-live.service.bak
sudo cp -a /etc/systemd/system/dxhotspot.service  /etc/systemd/system/dxhotspot.service.bak
```

その後に `sudo ./install.sh`。局の設定は今の値が既定で出るので、Enter で進めます。

### bin だけを差し替える（インストーラを使わない）

```bash
sudo systemctl stop dxhotspot dstar-live
sudo install -m 755 -o dstar -g dstar bin/dstar-live /opt/dstar_ambe/dstar-live
sudo install -m 755 -o dstar -g dstar bin/dxhotspot  /opt/dxhotspot/dxhotspot

sudo sed -i 's|^ExecStart=.*|ExecStart=/opt/dstar_ambe/dstar-live|' /etc/systemd/system/dstar-live.service
grep -q DXM_DIR /etc/systemd/system/dstar-live.service \
  || sudo sed -i '/^\[Service\]/a Environment=DXM_DIR=/opt/dstar_ambe' /etc/systemd/system/dstar-live.service
sudo sed -i 's|^ExecStart=.*|ExecStart=/opt/dxhotspot/dxhotspot|' /etc/systemd/system/dxhotspot.service

sudo systemctl daemon-reload
sudo systemctl start dstar-live dxhotspot
```

**`Environment=DXM_DIR=/opt/dstar_ambe` は必須です。** 単一実行ファイルでは `__file__` が一時展開先を指すため、これが無いと `config.ini` と `static/` を見失います。

動作を確認してから `.py` を消します。

```bash
sudo rm -f /opt/dstar_ambe/*.py /opt/dxhotspot/*.py
```

`static/`・設定・証明書は消さないこと。電源断メッセージを残したいなら `/opt/dxhotspot/oled_final.py` だけ残します。

---

## 8. 戻す

```bash
sudo systemctl stop dxhotspot dstar-live
sudo rm -rf /opt/dstar_ambe /opt/dxhotspot
sudo mv /opt/dstar_ambe.bak.YYYYMMDD /opt/dstar_ambe
sudo mv /opt/dxhotspot.bak.YYYYMMDD  /opt/dxhotspot
sudo cp -a /etc/systemd/system/dstar-live.service.bak /etc/systemd/system/dstar-live.service
sudo cp -a /etc/systemd/system/dxhotspot.service.bak  /etc/systemd/system/dxhotspot.service
sudo systemctl daemon-reload
sudo systemctl start dstar-live dxhotspot
```

---

## 9. うまくいかないとき

### `bin がこの機械で動きません`

配布物の CPU がこの機械と違います。`BUILD-INFO.txt` の「対象」を確認し、合うものを使ってください。glibc が古い場合も同じ症状になります。

### `モデムが見つかりません`

USB の HAT・MCP2221A をつないでください。場所を指定するなら `sudo DXH_MODEM=/dev/ttyACM0 ./install.sh`。

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

`/opt/MMDVMHost` の持ち主が `dstar` でない可能性があります。

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

---

## 10. この手順書の確認状況

**確認済み**（2026-11-16、Raspberry Pi Zero 2 W / Debian 13 trixie / MMDVM_HS_Hat / SSD1306 OLED）

- `.py` 版 `install.sh` のまっさらな機械への導入（§2 の 8 段すべて）
- 再起動後の UART・I2C の出現、MMDVM-Host の HAT 検出
- bin への差し替え（§7 後半）と動作（Web・OLED・ボコーダー・DSRP）
- バックアップからの復旧経路

**未確認**

- **バイナリ版 `install.sh` のまっさらな機械での通し試験**（この手順書の §2 そのもの）
- ボコーダー資材の GitHub からの取得（取得元 `ji2tab/dxmonitor` は公開したが、取得そのものは未試験）
- x86_64 の機械での導入
- PTT 送信、D-STAR ⇔ DMR 変換の通し試験
