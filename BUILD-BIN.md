# dxmonitor ビルド手順書（バイナリ版）

版 20261115b 時点。2026-11-16 に Raspberry Pi Zero 2 W で実施した内容に基づく。

この文書は **配る側**（バイナリを作る人）のための手順。受け取る側の手順は `INSTALL-BIN.md`。

---

## 1. 何を作るのか

Python のロジックを PyInstaller で単一実行ファイルに固める。作るのは 3 本（＋任意で 1 本）。

| bin | 中身 | 大きさ（arm64 実測） |
|---|---|---|
| `dstar-live` | dxmcore 本体（通信・音声・Web） | 9.5 MB |
| `dxhotspot` | OLED・Wi-Fi・443 の統合画面 | 15 MB |
| `dxhotspot_settings` | インストーラが使う設定ツール | 8.8 MB |
| `dxhotspot_final` | 電源断メッセージ（任意。§7） | 約 20 MB |

**bin に入るもの** … Python 本体と標準ライブラリ、Pillow、smbus、プロジェクトの全モジュール、dxhotspot の素材（`logo.svg`・`favicon.svg`・`hs_inject.html`・`wifi.html`）。

**bin に入らないもの** … dxmcore の画面（`static/`）、設定ファイル、証明書、MMDVM-Host、ボコーダー、`DMRIds.dat`。これらは配布物の別の場所に置くか、受け取る側の機械で作る。

---

## 2. ビルドする機械

**実行する機械と同じ CPU・OS でビルドする。** PyInstaller はクロスコンパイルできない。

| 配布先 | ビルドする機械 |
|---|---|
| Raspberry Pi（64bit OS） | arm64 の Pi |
| PC（Debian/Ubuntu） | x86_64 の同系 OS |
| 32bit OS の Pi | 32bit の Pi（混在不可） |

### glibc の制約（重要）

bin は **ビルドした機械より古い glibc の機械では動かない。** 逆は動く。

- 今回のビルド機: Debian 13 trixie / **glibc 2.41**
- この bin は glibc 2.41 以上の機械でしか動かない。Bookworm（glibc 2.36）では動かない
- 広く配るなら、**対応したい中で最も古い OS でビルドする**

Bookworm 向けが要るなら Bookworm の機械で別にビルドし、2 種類配る。

**未確認**：今回の trixie ビルドを Bookworm で動かす試験は行っていない（動かないはずだが実機未検証）。

---

## 3. 準備

### 3.1 ソースを置く

GitHub から取るか、配布物を展開する。

```bash
cd ~
unzip -q DXmonitor-main.zip        # または tar xzf dxmonitor_full_<版>.tar.gz
ls DXmonitor-main/                 # dxmcore  dxhotspot  README.md  NOTICE.md  LICENSE
```

### 3.2 パッケージ

```bash
sudo apt update
sudo apt install -y python3-venv python3-dev gcc binutils python3-smbus fonts-dejavu-core
```

- `python3-smbus` … **OLED の I2C に必須**。無いと OLED が点かない bin になる（§6）
- `fonts-dejavu-core` … OLED の文字。無いと代替書体になりロゴが欠ける

`install.sh` を先に流した機械なら、どちらも入っている。

### 3.3 swap（メモリ 1GB 未満の機械は必須）

Pi Zero 2 W はメモリ 415MB、swap は zram のみ。zram は圧縮 RAM なので実メモリの足しにならない。

```bash
free -h; swapon --show
sudo fallocate -l 1G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
swapon --show
```

終わったら外す。

```bash
sudo swapoff /swapfile && sudo rm -f /swapfile
```

`build_bin.sh` は zram 以外の swap が 900MB 未満だと警告して確認を求める。

---

## 4. ビルド

```bash
chmod +x ~/build_bin.sh
~/build_bin.sh ~/DXmonitor-main          # 3 本まとめて
~/build_bin.sh ~/DXmonitor-main core     # dstar-live だけ
~/build_bin.sh ~/DXmonitor-main hotspot  # dxhotspot だけ
~/build_bin.sh ~/DXmonitor-main settings # dxhotspot_settings だけ
~/build_bin.sh ~/DXmonitor-main final    # dxhotspot_final（§7）
```

開始時にソースの場所と版を表示する。**`注意: smbus が見つかりません` が出たら中止**し、§3.2 を入れてからやり直す。

出力は `~/dxm_build/dist/`。作業はすべて `~/dxm_build/` の中（`.venv`・`build`・`dist`）で、`/opt`・systemd・動いているサービスには触らない。**ビルド中も今の dxmonitor は動き続ける。**

### 所要時間（Pi Zero 2 W 実測、2026-11-16）

| | 時間 |
|---|---|
| `dstar-live` | 1 分 30 秒 |
| `dxhotspot` | 2 分 1 秒 |
| `dxhotspot_settings` | 1 分 22 秒 |
| venv 作成・pip 導入を含む全体 | **約 6 分** |

### SSH が切れると止まる

`tmux` を使うか、`nohup` でバックグラウンドに回す。

```bash
sudo apt install -y tmux
tmux new -s build
~/build_bin.sh ~/DXmonitor-main
# 切れたら tmux attach -t build
```

ログを残して所要時間を拾うなら。

```bash
sudo apt install -y moreutils
{ time ~/build_bin.sh ~/DXmonitor-main ; } 2>&1 | ts '[%H:%M:%S]' | tee ~/build_$(date +%Y%m%d_%H%M).log
```

journald には残らない（対話シェルの出力は systemd が拾わない）。後からでも概算は出せる。

```bash
stat -c '%y  %n' ~/dxm_build/.venv ~/dxm_build/dist/*
```

### 確認

```bash
ls -lh ~/dxm_build/dist/
file ~/dxm_build/dist/dstar-live        # ARM aarch64 と出ること
```

---

## 5. ビルドスクリプトの中身（要点）

`build_bin.sh` が行うこと。

1. ソースの場所と版（`live.py` の `BUILD`）を読む
2. メモリと swap を見て、足りなければ警告
3. `~/dxm_build/.venv` を **`--system-site-packages` 付き**で作る
   → apt の `python3-smbus` は pip に無いので、システムの site-packages を見せる必要がある
4. venv に PyInstaller と Pillow を入れる（システムの python3 には触らない）
5. `smbus` が import できるか確かめ、できるときだけ `--hidden-import smbus` を足す
6. `--onefile` で 3 本を作る

主な `--hidden-import`：

- `dstar-live` … `dxmcore/source/*.py` の全モジュール（関数内 import を追えないため）
- `dxhotspot` … `core`・`wifi`・`oled`・`oled_final`・`dash`・`settings`・`dxconfig`・`smbus`
- `dxhotspot_settings` … `core`・`dxconfig`

---

## 6. bin 化で起きた問題と対処（実例）

### 6.1 OLED が点かない

```
[oled] 0x3C が応答しません（i2c-1 ...: No module named 'smbus'）
```

**原因 2 つ**。`oled.py` の `import smbus` がクラスの `__init__` の中にあり、PyInstaller の解析が追えない。加えて `python3 -m venv`（素）で作った venv からは apt の `python3-smbus` が見えない。

**対処**：venv を `--system-site-packages` で作り、`--hidden-import smbus` を足す。対処後は `[oled] 表示開始 ...` が出る。

### 6.2 設定の検査表が使われない

`settings.py` の `_dxconfig()` は `dxconfig.py` が**ファイルとして存在するとき**だけ読み込む。bin には `.py` が無いので読み込めず、`settings.py` 自身のフォールバックに落ちる。

**対処 2 つ**。

- `dxhotspot` の bin に `--hidden-import dxconfig` を足す
- `settings.py` の `_dxconfig()` に凍結時（`sys.frozen`）の分岐を足す

```python
    global _DX_CHECK
    if getattr(sys, "frozen", False):
        try:
            import dxconfig
        except ImportError:
            return None
        _DX_CHECK = getattr(dxconfig, "check", None)
        return dxconfig
```

関数の後半にあった 2 つ目の `global _DX_CHECK` は削除する（残すと `SyntaxError`）。

**実測**：この 2 つを入れる前後で、`callsign`・`module`・`dmr_id`・`color_code`・`dmr_tg`・`net_mode`・`net_to_rf`・`allow_calls`・`session_call` の検査結果に差は出なかった。フォールバック表が `dxconfig` と同じ判定をしているため。検査表を一本化するための修正であって、既知の誤判定を直すものではない。

### 6.3 「説明」タブのバージョン表が空になる（仕様）

`web_config.py` の `versions_info()` が `base = os.path.dirname(os.path.abspath(__file__))` からソースの `.py` を 1 本ずつ読んで sha256 を出す作り。bin には `.py` が無いので表が空になる。`ui_build_file` も空。

ヘッダの版表示・`BUILD`・`UI_BUILD` は正しく出る。**動作に影響しない。** 直すなら `base` を `DXM_DIR` 優先にする（static の sha と UI_BUILD だけは出せる。`.py` の行はバイナリでは出せない）。

### 6.4 関数内 import の洗い出し

bin 化では関数の中や `try` の中の import が落ちる。ソース全体を洗った結果、**外部モジュールで落ちるのは `smbus` だけ**だった。残りは標準ライブラリか、`--hidden-import` で拾っているプロジェクト内のモジュール。

新しい外部モジュールを使うときは、関数内 import になっていないか確認する。

---

## 7. 電源断メッセージ（dxhotspot_final）

`oled_final.py` は systemd の system-shutdown 段から `/usr/lib/systemd/system-shutdown/dxhotspot-oled` 経由で**別プロセスとして**呼ばれる。`.py` を消すとこの表示（SAFE TO UNPLUG）は出なくなる。他の動作には影響せず、失敗しても電源断は止まらない設計。

出したい場合は 2 つ。

- **(a)** `/opt/dxhotspot/oled_final.py` だけ `.py` のまま残す（python3 が要る）。確実
- **(b)** `./build_bin.sh ... final` で作った `dxhotspot_final` を置き、呼び出し元を書き換える

**(b) は未確認**。シャットダウンのこの段はファイルシステムが読み出し専用で、単一実行ファイルの `/tmp` への展開に失敗する可能性がある。

---

## 8. 配布物を作る

ビルドが済んだら `make_dist.sh` で 1 本にまとめる。

```bash
~/make_dist.sh ~/DXmonitor-main ~/dxm_build/dist ~/install_bin.sh
```

出力 `~/dxmonitor_bin_<版>_<arch>.tar.gz` の構成。

```
install.sh              バイナリ版インストーラ
bin/                    dstar-live, dxhotspot, dxhotspot_settings
dxmcore/                static/, config.ini.example, dstar-live.service, NOTICE.md
app/hotspot.ini
scripts/                dxhotspot-wifi, dxhotspot-oled-final
systemd/dxhotspot.service
README.md  NOTICE.md  SETUP.md  LICENSE  BUILD-INFO.txt
```

`.py` は 1 つも入らない。`vocoders/` も入らない（§9）。

`BUILD-INFO.txt` に版・対象 CPU・OS・glibc・各 bin の sha256 を記録する。

---

## 9. ボコーダーの扱い

**配布物に入れない。** 同意した人だけが取得してビルドする。二段構え。

1. インストーラが、同意したときだけ GitHub から**ビルド用の資材 6 ファイル**を取得する
   - `build_qso_vocoder.sh`・`build_md380_vocoder.sh`・`qso_dv_dxm.cpp`・`md380_dv.c`・`dmr_ambe_fec.h`・`LICENSE`
   - これらは dxmonitor project のコード（GPL v3）
   - 取得元は `install.sh` の `VOC_BASE`。既定は `raw.githubusercontent.com/ji2tab/dxmonitor/main/dxmcore/source/vocoders`（公開リポジトリ。資材 6 ファイルだけを置いている）
2. その資材のビルドスクリプトが、**他者のコードを各作者のリポジトリから `git clone`** する
   - QSO One … `github.com/greyfoxsolid/vocoder`
   - MD-380 … `github.com/travisgoodspeed/md380tools`（ファームも取得）

**取得元のリポジトリは public である必要がある。** private だとインストーラは取得に失敗し、理由を表示してハードウェア AMBE 前提で続行する（インストールは止まらない）。

取得先を固定したいときは、リリースごとにタグを打って `DXH_VOC_REF` で指定する。

```bash
sudo DXH_VOC_REF=v20261115b ./install.sh
```

`main` のままだと、配布後にソースを直したときに取得内容がずれる。

---

## 10. 版を上げるとき

配布のたびに次をそろえる。

| ファイル | 箇所 |
|---|---|
| `dxmcore/source/live.py` | `BUILD = "2026MMDD<英字>"` |
| `dxmcore/source/static/app.js` | `const UI_BUILD='...'` |
| `README.md` | 版表記 |
| `dxmcore/docs/00_index.md` | 版表記 |

変えたモジュールの `__updated__` も上げる。`BUILD` と `UI_BUILD` が違うと画面の版表示が黄色になる。

---

## 11. 確認済みのこと／していないこと

**確認済み**（2026-11-16、Raspberry Pi Zero 2 W / Debian 13 trixie / aarch64 / Python 3.13.5 / PyInstaller 6.22.3 / glibc 2.41）

- 3 本ともビルド成功。ビルド機の痕跡（`/home/...` などのパス）が bin に残っていないことを `strings` で確認
- `dstar-live` … `DXM_DIR` を渡して起動。ボコーダー QSO One を読み込み、DSRP 受け口 20010 を開き、MMDVM-Host を検出。Web が配信
- `dxhotspot` … 統合画面（https）を配信。OLED に `JI2TAB D 438.990 / 192.168.1.31` を表示。bin 内の素材を読み込み
- `dxhotspot_settings` … `--check` が `.py` と同じ結果を返す

**していないこと**

- 他の OS バージョン（Bookworm 等）での動作
- x86_64 向け bin の実機運用
- PTT 送信、D-STAR ⇔ DMR 変換の通し試験
- `dxhotspot_final` のシャットダウン段での動作
- bin 版 `install.sh` のまっさらな機械での通し試験
