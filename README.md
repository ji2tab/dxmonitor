# dxmonitor（バイナリ配布）

D-STAR・DMR・YSF のホットスポット（MMDVM_HS_Hat）とネット接続をまとめたソフトの、**バイナリ配布用のリポジトリ**です。ソース（`.py`）は置いていません。

## 入手と導入

| | |
|---|---|
| 配布物 | [Releases](https://github.com/ji2tab/dxmonitor/releases) の `dxmonitor_bin_<版>_<arch>.tar.gz` |
| 入れ方 | [`docs/INSTALL-BIN.md`](docs/INSTALL-BIN.md) |
| 作り方（配る側） | [`docs/BUILD-BIN.md`](docs/BUILD-BIN.md) |

対象: Raspberry Pi（64bit OS）＋ MMDVM_HS_Hat ＋ SSD1306 OLED。配布物は CPU と OS（glibc）ごとに別です。同梱の `BUILD-INFO.txt` で確認してください。

## 構成

```
README.md  NOTICE.md  LICENSE
docs/
  INSTALL-BIN.md     導入の手順（受け取る側）
  BUILD-BIN.md       配布物の作り方（配る側）
tools/
  install_bin.sh     バイナリ版インストーラの原本（配布物の中では install.sh）
  make_dist.sh       配布物（tar.gz）を作る
vocoders/            ソフトウェア AMBE のビルド用資材（6 ファイル。GPL v3）
```

`vocoders/` は、インストール時にソフトウェア AMBE に同意した人だけが `install.sh` 経由で取得します。同意しなければ取得しません。

## AMBE ボコーダーについて（重要）

- ハードウェアの AMBE（AMBEserver など）で使うことを基本とします。AMBE のボコーダー本体は含みません。
- ソフトウェアの AMBE は、使用者が自己の実験・研究のために、自己の判断と責任で入手・ビルドして使うものとします。インストーラは、同意を明示したときだけ資材を取得・ビルドします。
- その入手・ビルド・使用と、それによって生じたトラブル・損害・紛争について、製作者は一切関与せず、いかなる責任も負いません。その責任はすべて使用者が負います。

くわしくは [`NOTICE.md`](NOTICE.md)。
