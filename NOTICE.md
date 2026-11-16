# AMBE ボコーダーについて（重要）

1. **本ソフトウェアは、ハードウェアの AMBE（DVSI 社の AMBE チップを使う AMBEserver など）で使うことを基本とします。**
2. ソフトウェアの AMBE（ソフトのボコーダー）は、本ソフトウェアに同梱も配布もしていません。
3. ソフトウェアの AMBE を使う場合は、**使用者が自己の実験・研究のために、自己の判断と責任で**入手・ビルドして使うものとします。
4. ソフトウェアの AMBE の入手・ビルド・使用、およびそれによって生じたトラブル・損害・第三者との紛争について、**本ソフトウェアの製作者は一切関与せず、いかなる責任も負いません。その責任はすべて使用者が負います。**
5. インストーラ（`dxhotspot/install.sh`）は、上記に同意すると明示したときだけ、ソフトのボコーダーの取得・ビルドを行います。同意しないとき（既定）はハードウェアの AMBE で使う設定にします。

## ハードウェアの AMBE だけで使えること（1.8.5 時点。ソースの読み取りによる。実機は未確認）

| 使い方 | ハードウェアの AMBE（AMBEserver）だけ | ソフトのボコーダーが要る |
|---|---|---|
| 同じ方式どうしの中継（D-STAR ⇔ D-STAR、DMR ⇔ DMR、YSF ⇔ YSF、DMR ⇔ YSF） | ○（音声の符号をそのまま通す） | |
| D-STAR のブラウザの受信音・ブラウザ PTT | ○（設定タブで AMBEserver の接続先を入れる） | |
| D-STAR ⇔ DMR／YSF の変換 | | ○ |
| 音声応答（ガイダンス） | | ○ |
| DMR・YSF のブラウザの受信音・ブラウザ PTT | | ○ |

---

# 第三者ソフトウェアの帰属（クレジット）

本ソフトウェアのソフトAMBE（ソフトのボコーダー）は、下記の第三者（上流）の著作物を**利用者が自分の機械でビルドして使う**ためのものです。ボコーダー本体のソースもバイナリも本ソフトウェアには同梱・配布していません（`vocoders/` にあるのは、それらを呼び出すための dxmonitor 側のヘルパーとビルド手順だけ）。各著作物の権利は、それぞれの作者・権利者に帰属します。

> 下記 `vocoders/` のヘルパー（`qso_dv_dxm.cpp`・`md380_dv.c`・`dmr_ambe_fec.h`）は、GPL v3 系のコードと組み合わせて使うため **GPL v3 or later** とします。利用・再配布の際は、各上流のライセンス本文（LICENSE/COPYING）と著作権表示を必ず保持してください。
> （本記載は法的助言ではありません。配布前に各リポジトリの最新の LICENSE を確認してください。各作者名・ライセンス版は 2026-11 時点の確認に基づきます。）
>
> GPL v3 の本文は `vocoders/LICENSE` に同梱しています。各ヘルパーの先頭には `SPDX-License-Identifier: GPL-3.0-or-later` を記載しています。

### QSO One ボコーダー
- 取得元: `github.com/greyfoxsolid/vocoder`（ライセンス: GPL v3）
- D-STAR／DMR／YSF の AMBE・AMBE+2 コーデック。内部で下記 DroidStar の mbe コーデック・OP25 由来の encoder・mbelib を用いる。
- `vocoders/build_qso_vocoder.sh` がコミットを固定してソースからビルドする。

### DroidStar / DudeStar の mbe ボコーダー
- 作者: Doug McLain（AD8DP）。ライセンス: GPL v3。
- 「mbelib ＋ OP25 AMBE encoder」をもとにした DMR/D-STAR 等の AMBE コーデック。QSO One 経由で利用。

### mbelib
- 取得元: `github.com/szechyjs/mbelib`。
- **特許ノーティス（mbelib の README より）**: このソースは教育目的で提供される、音声符号化／復号アルゴリズムの実装方法の記述です。これをコンパイル・派生して得られる実行物は、1 つ以上の特許の対象となり得ます。コンパイル・使用の前に、特許上の制限やライセンス要件の有無を必ず確認してください。
- → ソフトAMBEは、個人の実験・アマチュア無線の範囲で、利用者自身の責任で用いること。

### md380tools（MD-380 ファームの AMBE+2）
- 取得元: `github.com/travisgoodspeed/md380tools`（作者: Travis Goodspeed〔KK4VCZ〕ほか。ライセンス: GPL v3）。
- そのエミュレータと同じ方法で、MD-380 のファームウェア **D002.032** の AMBE+2 関数を呼び出す。
- **ファームウェア D002.032 は Tytera（TYT）の権利物**。本ソフトウェアには一切含めない。利用者が md380tools の手順で入手し、自分の機械の中だけで使うこと。
- `vocoders/build_md380_vocoder.sh` がコミットを固定してビルドする。

### その他
- AMBE／AMBE+2 は DVSI 社の技術です。ハードウェアAMBE（AMBEserver 等）を使う場合は、正規の AMBE チップ（DVstick/ThumbDV 等）を用いてください。
- MMDVM・MMDVM-Host（Jonathan Naylor〔G4KLX〕ほか）、OP25 プロジェクトの成果を参照しています。これらの権利は各作者に帰属します。
