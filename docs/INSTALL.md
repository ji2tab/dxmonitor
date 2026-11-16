# dxmcore 単体の導入手順（HAT なし）

PC・Raspberry Pi・Incus コンテナなどで、**無線機（HAT）を使わずに**ネットの受信とブラウザ PTT だけを使うための手順。

> **ホットスポット（MMDVM_HS_Hat などの HAT あり）を作るときは `dxhotspot-setup.md`**（dxhotspot のパッケージの `SETUP.md`）を使う。dxmcore もそちらの install.sh がまとめて入れる。

| 項目 | 内容 |
|---|---|
| 対象版 | dxmcore **1.8.5**（BUILD **20261116a**、パッケージ `dxmcore_1.8.5_<BUILD>.tar.gz`） |
| 最終更新 | 2026-11-15 |
| 根拠 | `source/install.sh`・`config.ini.example`・`dstar-live.service`・`live.py`・`app.py`・`dxconfig.py`・`web_config.py`・`ep_web.py`・`vocoders/build_qso_vocoder.sh`・`static/app.js`、`dxmonitor_changelog.md`・`06_config_reference.md` |
| リポジトリ | `github.com/ji2tab/dxmonitor-w`（`main`）。§1.0 の curl ワンライナー |
| 詳しい資料 | 構成 `01`／部品 `02`／仕様 `03`・`04`／ビルドと運用 `05`／設定の全キー `06`／課題 `07`／音量 `10`（`dxmonitor-docs/`） |

---

## 0. 前提

- OS: Debian・Ubuntu 系（Raspberry Pi OS も可）。x86_64 の Ubuntu ＋ Incus コンテナでも動く。
- Python 3.7 以上と openssl（install.sh が無ければ apt で入れる）。本体は Python の標準ライブラリだけで動く。
- 外向きの UDP が通る回線（受信はホールパンチで NAT を越える。§8）。
- **HAT なしでできること**: ネット側（`[mode] net`）の 3 方式への接続と受信、ブラウザ PTT（ネットが D-STAR・DMR・YSF のどれでも同じ。`ep_web.py`）。電波側は使わないので `[mode] rf = dstar`・`[hat] enable = no` のまま。無線機の UR の命令とガイダンス（音声の案内）は無線機（HAT）向けなので、単体では関係しない。
- 音声の符号化・復号は 2 つの方式のどちらか:

| `[ambe] mode` | 中身 | 要るもの |
|---|---|---|
| `server` | AMBEserver（AMBE3000／DV3000 の UDP 中継。別の機械でもよい） | AMBEserver の IP とポート（既定 2460） |
| `soft` | ソフトのボコーダー（本体には同梱しない。§3） | QSO One をこの機械でビルド（git・g++）、または DroidStar プラグイン |

---

## 1. インストール

### 1.0 git から curl でワンライナー（最短）

機械の上で直接、GitHub のリポジトリを取って `dxmcore/source/install.sh` を走らせる方法。**scp もパッケージ作りも要らない**。`install.sh` は自分のあるフォルダ（`source/`）から `/opt/dstar_ambe` へ入れるので、リポジトリを丸ごと取ってその中の `source/` で実行すればよい。

> **前提**: リポジトリが **public** であること（private のままだと匿名の curl は 404 になる。§1.0.1）。`curl`・`tar`・`sudo`・Python 3.7+ が要る（`install.sh` が足りなければ apt で入れる）。

```bash
curl -fsSL https://github.com/ji2tab/dxmonitor-w/archive/refs/heads/main.tar.gz | tar xz \
  && cd dxmonitor-w-main/dxmcore/source \
  && sudo ./install.sh
```

- 展開先は作業フォルダ直下の `dxmonitor-w-main/`（`main` ブランチの tar。タグで入れるなら `refs/tags/<tag>` に変える）。
- 終わると `起動しました: https://<IP>:8080/`（`[web] tls = no` なら `http://`）。この後は **§2 の設定**（自局のコール・AMBEserver）を必ず行う。
- Incus コンテナに入れるときも同じ（コンテナの中で上の 1 行）。root のシェルなら `install.sh` が自動でシステムユーザー `dstar` を作って動かす。
- ソフトのボコーダー（`[ambe] mode = soft`）を使うなら、展開した `dxmonitor-w-main/dxmcore/source/vocoders/build_qso_vocoder.sh` を §3 の手順でビルドする。
- 更新も同じ 1 行でよい（`config.ini` は `install.sh` が残す）。ただし `/opt/dstar_ambe` の持ち主が実行ユーザーのままかだけ確かめる（§6）。

#### 1.0.1 リポジトリが private のとき

匿名の curl は使えない。GitHub の個人アクセストークン（PAT。`repo` 権限）を使って取る:

```bash
TOKEN=<自分のPAT>
curl -fsSL -H "Authorization: Bearer $TOKEN" \
  https://api.github.com/repos/ji2tab/dxmonitor-w/tarball/main | tar xz \
  && cd ji2tab-dxmonitor-w-*/dxmcore/source \
  && sudo ./install.sh
```

- API 版の tar は展開先の名前が `ji2tab-dxmonitor-w-<短いハッシュ>/` になる（ワイルドカードで受ける）。
- トークンを画面やログに残さないよう、`history` に残したくなければ先頭にスペースを置くか、別の端末で実行する。
- 配布を楽にするなら、リポジトリを **public にするのがいちばん簡単**（ソースは公開可能版で、秘密情報は含めていない）。

### 1.1 パッケージを送る（Mac で）

```bash
scp ~/Downloads/dxmcore_1.8.5_<BUILD>.tar.gz <ユーザー>@<機械>:~/
```

### 1.2 install.sh を実行する（機械で）

パッケージは `source/`・`docs/` を直下に持つので、専用のフォルダに展開する。

```bash
rm -rf ~/dxm && mkdir ~/dxm
tar xzf ~/dxmcore_1.8.5_<BUILD>.tar.gz -C ~/dxm
cd ~/dxm/source
sudo ./install.sh
```

`install.sh` がすること:
1. `/opt/dstar_ambe` へ全 `*.py` と画面の `static/*`（`index.html`・`style.css`・`app.js`）をコピー（古い `dmr_gateway.py`・`__pycache__` は消す）。
2. `config.ini` が無ければ `config.ini.example` から作る（あれば残す）。見本も `config.ini.example` として置く。
3. 自己署名の証明書 `cert.pem`／`key.pem` を作る（無いときだけ。SAN に LAN の IP・`<ホスト名>`・`<ホスト名>.local`、10 年）。
4. 持ち主を実行ユーザーにし、`key.pem` は 600、`config.ini` は 640。実行ユーザーは `DXM_USER` ＞ `/opt/dxhotspot` があれば `dstar` ＞ 既に入っている `dstar-live.service` の `User=` ＞ `sudo` した人の順で決める（20261101e〜）。**root にはしない**: root のシェル（`incus exec` など）で流すと `dstar` を作ってそれで動かす（20261102b〜）。
5. `dstar-live.service` の `__USER__` を実行ユーザーにして登録し、起動。最後に `起動しました: https://<IP>:8080/` と出る（`[web] tls = no` なら `http://`）。

### 1.3 画面のファイル（20261031j 以前のパッケージのときだけ）

20261031k の `install.sh` は `static/` の 3 本（`index.html`・`style.css`・`app.js`）をコピーするので、この手順は要らない。

**20261031d〜j のパッケージ**の `install.sh` は `static/*.html` しかコピーせず、`static/style.css`・`static/app.js` が入らない（画面が動かない）。それで入れた機械は手でコピーする:

```bash
sudo cp ~/dxm/source/static/* /opt/dstar_ambe/static/
sudo chown -R "$(id -un)":"$(id -un)" /opt/dstar_ambe/static      # 実行ユーザーが自分のとき
sudo systemctl restart dstar-live
```

---

## 2. 最初の設定（config.ini）

`/opt/dstar_ambe/config.ini`。★の項目は画面の「設定」タブからも変えられる。最低限、次の 3 つを自分の値にする（`<コール>` は自局のコールサイン、`<サフィックス>` は英字 1 文字、`<AMBEserver の IP>` はその機械のアドレス）:

| 節・キー | 意味 |
|---|---|
| `[dstar] mycall` | リフレクター（XLX・DCS）に名乗るコール（7 文字＋空白＋サフィックス）。無線機と同じサフィックスは避ける |
| `[tx] mycall` | ブラウザ PTT のヘッダの MY。受信と同じコールにする |
| `[ambe] mode`・`server_ip`・`server_port` | AMBEserver を使うならそのアドレス。ソフトなら §3 |

sed で書き換える手順:

```bash
CFG=/opt/dstar_ambe/config.ini
sudo sed -i '/^\[dstar\]/,/^\[/ s/^mycall *=.*/mycall = <コール> <サフィックス>/' $CFG
sudo sed -i '/^\[tx\]/,/^\[/ s/^mycall *=.*/mycall = <コール> <サフィックス>/' $CFG
sudo sed -i '/^\[ambe\]/,/^\[/ s/^server_ip *=.*/server_ip = <AMBEserver の IP>/' $CFG
sudo systemctl restart dstar-live
```

ほかの主な既定値（`config.ini.example`）:

| 節・キー | 既定 | メモ |
|---|---|---|
| `[web] port`・`tls` | `8080`・`yes` | ブラウザ PTT（マイク）には https が要る |
| `[web] bind` | `0.0.0.0`（書いていなければ） | LAN から直接開ける。同じ機械の中だけにするなら `127.0.0.1` |
| `[dstar] session_limit_min` | `30` | 接続の上限（分）。0 で無制限 |
| `[mode] rf`・`net` | `dstar`・`dstar` | 単体では rf は dstar のまま。net は §4 |
| `[hat] enable` | `no` | 単体では no のまま |
| `[ambe] rx_level_db`・`tx_level_db` | `0`（見本には無い。無ければ既定） | 受信レベル・送信レベル（dB、-12〜+12）。設定タブ「音声」で変える。`10_audio_settings.md` |

全キーは `06_config_reference.md`。

---

## 3. ソフトのボコーダー（`[ambe] mode = soft` のとき）

> **AMBE ボコーダーについて（重要）**
> - 本ソフトウェアは、**ハードウェアの AMBE（AMBEserver など）で使うことを基本**とします。
> - ソフトウェアの AMBE（ソフトのボコーダー）は同梱も配布もしていません。使う場合は、**使用者が自己の実験・研究のために、自己の判断と責任で**入手・ビルドして使うものとします。
> - ソフトウェアの AMBE の入手・ビルド・使用と、それによって生じたトラブル・損害・紛争について、**製作者は一切関与せず、いかなる責任も負いません。その責任はすべて使用者が負います。**
> - くわしくは同梱の `NOTICE.md`。

既定は `[ambe] mode = server`（ハードウェアの AMBE。設定タブで AMBEserver の接続先を入れる）。この節は、上記に同意してソフトウェアの AMBE を使うときだけ読む（mbelib の注記どおり、実行物は特許の対象になり得る）。

### 3.1 QSO One をビルドする

github.com/greyfoxsolid/vocoder（GPL v3）をコミット固定でビルドし、`/opt/vocoders/qso_dv_dxm` を作る。DMR・YSF 側（AMBE+2）は本物の AMBE3000 に合わせる較正（符号化 −5.1 dB／復号 +6.3 dB）をビルドの前に当てる。

```bash
sudo apt-get install -y git build-essential
sudo DXH_SOFT_AMBE_AGREE=yes bash ~/dxm/source/vocoders/build_qso_vocoder.sh /opt/vocoders     # 最後に「動作確認 OK」
```

`config.ini` に登録して選ぶ:

```bash
CFG=/opt/dstar_ambe/config.ini
sudo tee -a $CFG >/dev/null <<'EOF'

[vocoder.qso]
label = QSO One（この機械でビルド）
type = pipe
command = /opt/vocoders/qso_dv_dxm
gain = 1.0
EOF
sudo sed -i '/^\[ambe\]/,/^\[/ s/^mode *=.*/mode = soft/' $CFG
sudo sed -i '/^\[ambe\]/,/^\[/ s/^# *vocoder *=.*/vocoder = qso/' $CFG
sudo sed -i '/^\[dmr\]/,/^\[/ s/^vocoder *=.*/vocoder = qso/' $CFG
sudo systemctl restart dstar-live
```

（`[ambe]` に `vocoder =` の行が無いとき（見本のコメント行を消した場合など）は `sudo sed -i '/^\[ambe\]/a vocoder = qso' $CFG`。）

### 3.2 DroidStar プラグイン（予備）

`vocoder_plugin.linux.arm64`（Raspberry Pi）／`vocoder_plugin.linux.x86_64`（PC）を `/opt/dstar_ambe/` に置き、`[vocoder.droidstar]`（`type = plugin`、`path = /opt/dstar_ambe/vocoder_plugin.linux.<種類>`、`gain = 2.0`）を足して選ぶ。dxhotspot の install.sh は github の wiblingen/droidstar_vocoder_plugin から取っている。声の高さ・声色が少しずれる（`07_issues.md`）。

ボコーダーは設定タブ（ソフトのボコーダー／DMR のボコーダー）で再起動なしに切り替えられる。開けなければ元のまま。

---

## 4. ネット側の方式（`[mode] net`）

| `net` | つなぐ先 | 画面の「接続先」の書き方 |
|---|---|---|
| `dstar` | D-STAR の XLX/XRF・DCS | 番号（3 桁）＋モジュール（英字 1 文字）。頭に `XLX`・`XRF`・`DCS` |
| `dmr` | DMR のマスター（TGIF・BrandMeister・XLX の DMR） | `TG`＋番号・`BM`＋番号・`XLX`＋番号＋モジュール |
| `ysf` | YSF（C4FM）のリフレクター | 番号 5 桁（頭に `YSF` も可）・名前・「ホスト:ポート」、XLX（番号＋モジュール） |

変え方は 2 通り。どちらも dstar-live が再起動する。

- **画面**: 設定タブの「NET モード」を選んで保存（単体のときだけ出る欄。ホットスポットでは運用タブの［モード変更］）。
- **ファイル**:

```bash
sudo sed -i '/^\[mode\]/,/^\[/ s/^net *=.*/net = dmr/' /opt/dstar_ambe/config.ini
sudo systemctl restart dstar-live
```

DMR を使うときは `[dmr] id`（7 桁か 9 桁）と、マスターのパスワード（`[dmr_net.tgif]`・`[dmr_net.bm]` の `password`。TGIF・BM は Self Care のホットスポット用）を設定タブで入れる。パスワードは画面のログでは伏せられる。単体には `/opt/MMDVMHost/DMRIds.dat`（`[dmr] dmrids`）が無い。無いときにブラウザ PTT の MY から ID を引けるかは**未確認**（引けなければ `[dmr] id` で出る見込み）。

**画面から保存したときの再起動**: 本体は `sudo -n systemctl restart dstar-live` を呼ぶ。実行ユーザーが root でなければ sudo の許可が要る。無ければログに「dstar-live を再起動できません（手で再起動してください）」と出るので、`sudo systemctl restart dstar-live` を手で行うか、許可を足す（ユーザー名は自分のもの）:

```bash
U=$(id -un); SC=$(command -v systemctl)
sudo tee /etc/sudoers.d/dxmonitor >/dev/null <<EOF
$U ALL=(root) NOPASSWD: $SC restart dstar-live
EOF
sudo chmod 440 /etc/sudoers.d/dxmonitor
sudo visudo -cf /etc/sudoers.d/dxmonitor
```

---

## 5. 動作確認

```bash
journalctl -u dstar-live -b --no-pager | grep -E '\[web\]|\[ambe\]'
curl -sk https://localhost:8080/config | grep -oE '"(version|build)": *"[^"]*"'
```

- `[web] dstar_ambe v1.8.5  https://0.0.0.0:8080/ でライブ配信中（RF DSTAR ⇔ NET …）` が出ればよい（モードは大文字。DSTAR・DMR・YSF）。
- `"version": "1.8.5"`・`"build": "20261116a"` ならパッケージどおり。
- ブラウザで `https://<IP>:8080/`（自己署名の警告は「詳細設定 → 続行」）。上部の版の表示が `v1.8.5　core 20261116a　UI 20261116a` で黄色でなければ、本体と画面がそろっている（黄色＝古いキャッシュか、§1.3 のコピー忘れ）。
- 運用タブ: Network（プルダウン）→ 接続先 →［接続］で受信、［切断］で止める。右の一覧の行はクリックで欄へ、ダブルクリックでそのまま接続。TX でブラウザから送信（https のときだけ）。画面の使い方は `03_system_spec.md` §8 と画面の「説明」タブ。

---

## 6. 更新

**Mac の Downloads から scp → 展開して cp → chown → restart → BUILD を確かめる**。

```bash
# Mac で
scp ~/Downloads/dxmcore_1.8.5_<BUILD>.tar.gz <ユーザー>@<機械>:~/

# 機械で
rm -rf ~/dxm && mkdir ~/dxm
tar xzf ~/dxmcore_1.8.5_<BUILD>.tar.gz -C ~/dxm
sudo cp ~/dxm/source/*.py /opt/dstar_ambe/
sudo cp ~/dxm/source/static/* /opt/dstar_ambe/static/
sudo chown -R "$(id -un)":"$(id -un)" /opt/dstar_ambe            # 実行ユーザー（dstar-live.service の User=）にそろえる
sudo systemctl restart dstar-live
sleep 5
curl -sk https://localhost:8080/config | grep -o '"build": *"[^"]*"'   # "build": "20261116a"
```

- `config.ini` は上書きしない（新しいキーは本体が既定値で補う。古い `[dmr] net_boost_db` は起動時に `[ambe] rx_level_db` へ移す）。
- 実行ユーザーは `grep ^User= /etc/systemd/system/dstar-live.service` で分かる。
- ボコーダーが変わった版（変更履歴に書いてある）は `sudo DXH_SOFT_AMBE_AGREE=yes bash ~/dxm/source/vocoders/build_qso_vocoder.sh /opt/vocoders` もやり直す（同じソースならビルドを省いて動作確認だけ）。
- `[web] tls = no` にしているなら `curl -s http://localhost:8080/config`。

---

## 7. Incus コンテナに入れる

```bash
# 母艦で
incus file push ~/dxmcore_1.8.5_<BUILD>.tar.gz <コンテナ>/root/
incus exec <コンテナ> -- bash -c 'rm -rf /root/dxm && mkdir /root/dxm \
  && tar xzf /root/dxmcore_1.8.5_<BUILD>.tar.gz -C /root/dxm \
  && cd /root/dxm/source && ./install.sh'
```

- `incus exec` は root で動くので、実行ユーザーは root になる（画面からの再起動に sudo の許可は要らない）。
- macvlan などで LAN の IP を割り当てると、ブラウザから `https://<コンテナの IP>:8080/` で開ける（macvlan なら母艦からは見えない。同じ LAN の別の機械から）。
- 更新は §6 と同じ（scp の代わりに `incus file push`）。

---

## 8. ポート

| 向き | ポート | 相手 | 条件 |
|---|---|---|---|
| 外向き UDP | 30001 | DExtra（XLX/XRF） | 同上 |
| 外向き UDP | 30051 | DCS | 同上 |
| 外向き UDP | 40000・12345・12346 | XLX の G3 ターミナルモード（`mode=g3` のときだけ。公開 IP の 40000 が届くこと） | 同上 |
| 外向き UDP | 62031 | TGIF・BrandMeister | net = dmr |
| 外向き UDP | 62030 | XLX の DMR 入口 | net = dmr |
| 外向き UDP | 42000 | YSF リフレクター | net = ysf |
| 外向き TCP | 5040 | TGIF の TG 切り替え API（http） | net = dmr の TGIF |
| 外向き UDP | 2460 | AMBEserver | `[ambe] mode = server` |
| 外向き TCP | 14580 | APRS-IS | `[aprs] enable = yes` |
| 外向き TCP | 443・80 | 一覧の取得（XLX・DCS・YSF の一覧など） | ― |
| 内向き TCP | 8080 | ブラウザ（Web） | `[web] port` |

詳しくは `01_system_architecture.md` §4（YSF・RefCheck は `11_changes_1.8.3.md` §1.2 が補う）。

---

## 9. 手で入れる（install.sh を使わない）

```bash
sudo mkdir -p /opt/dstar_ambe/static
sudo cp ~/dxm/source/*.py /opt/dstar_ambe/
sudo cp ~/dxm/source/static/* /opt/dstar_ambe/static/
sudo cp ~/dxm/source/config.ini.example /opt/dstar_ambe/config.ini     # §2 のとおり sed で直す
IP=$(hostname -I | awk '{print $1}'); HN=$(hostname)
sudo openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /opt/dstar_ambe/key.pem -out /opt/dstar_ambe/cert.pem -subj "/CN=dstar-live" \
  -addext "subjectAltName=IP:${IP},DNS:${HN},DNS:${HN}.local" -addext "basicConstraints=critical,CA:TRUE"
sudo chown -R "$(id -un)":"$(id -un)" /opt/dstar_ambe
sudo chmod 600 /opt/dstar_ambe/key.pem
sudo chmod 640 /opt/dstar_ambe/config.ini
sed "s/__USER__/$(id -un)/" ~/dxm/source/dstar-live.service | sudo tee /etc/systemd/system/dstar-live.service >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now dstar-live
```

ユニット（`dstar-live.service`）は `User=__USER__`、`WorkingDirectory=/opt/dstar_ambe`、`ExecStart=/usr/bin/python3 /opt/dstar_ambe/live.py`、`Restart=always`（5 秒）、`PYTHONUNBUFFERED=1`。止める・再起動するときは、送信中なら先に終端を出し、接続を正しく切ってから終わる。

---

## 10. アンインストール

```bash
sudo systemctl disable --now dstar-live
sudo rm /etc/systemd/system/dstar-live.service /etc/sudoers.d/dxmonitor
sudo systemctl daemon-reload
sudo rm -rf /opt/dstar_ambe /opt/vocoders
```

（`/etc/sudoers.d/dxmonitor` は §4 で作ったときだけある。`/opt/vocoders` は §3.1 でビルドしたときだけ。）

---

## 11. 困ったとき（要点）

| 症状 | 対処 |
|---|---|
| 画面が開かない | `journalctl -u dstar-live -n 50`。ポート・証明書・Python の版 |
| 画面が動かない・版が黄色 | 20261031j 以前のパッケージで入れたときの `static/style.css`・`app.js` の入れ忘れ（§1.3）。キャッシュなら強制再読み込み |
| NOT LINKED | 相手のリフレクターが止まっている、またはモジュールが使えない |
| 音が出ない | AMBEserver に届くか（server）／ボコーダーが開けているか（soft。設定タブと `journalctl` の `[ambe]`） |
| PTT できない | https で開いているか（マイクは https だけ） |
| 音がエコーする・二重に聞こえる | 同じ dxmcore を複数のタブ・端末で開いている。後から開いた側に警告が出るので 1 つに絞る |
| 画面で保存したのに反映されない | 再起動できていない（§4 の sudo の許可）。`sudo systemctl restart dstar-live` |
| 音が小さい・大きい | 設定タブの受信レベル・送信レベル。`10_audio_settings.md` |
| 自分で立てたリフレクターにつながらない | 家庭用ルーターの IPv4 over IPv6（`selfhost-reflector-notes.md`） |

課題の一覧は `07_issues.md`。
