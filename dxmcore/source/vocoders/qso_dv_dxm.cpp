// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dxmonitor project. See vocoders/LICENSE (GNU GPL v3).
// qso_dv_dxm.cpp — dxmonitor 用のボコーダー・ヘルパー（dv プロトコル。ambe_soft.py の PipeAmbe が使う）
//
// QSO One のコーデック（github.com/greyfoxsolid/vocoder の dv codecs：mbelib＋OP25 encoder、実チップ準拠の補正入り）を
// 利用者が自分の機械でビルドして使うためのもの。dxmonitor にはバイナリを同梱しない。
//
//   kind 0 = D-STAR  AMBE 3600x2400（9 バイト）… QSO One の qdv_dv::Codecs（補正入り）
//   kind 2 = DMR     AMBE+2 3600x2450（9 バイト、FEC 込み）… 同じライブラリの MBEVocoder::*_2450x1150
//            （dv プロトコルへの dxmonitor の拡張。caps bit2）
//
// プロトコル（little-endian、1 要求ずつ。QSO One の dv モードと同じ形）:
//   'H'                             → 'D' 'V' <proto=1> <caps> <u16 len> <id>
//   'D' <kind> <u16 n> <n×frame>    → <status> <u32 usTotal> <u32 usMax> <n×320B PCM>
//   'E' <kind> <u16 n> <n×320B>     → <status> <u32> <u32> <n×frame>
//   'R' <kind> <which>              → <status>   which: bit0 符号化器, bit1 復号器
//   'Q'                             → 終了
//
// GPL v3 or later（GPL v3+ のコードとリンクするため）。
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include "dv_codec_core.h"   // QSO One: qdv_dv::Codecs（D-STAR / P25）
#include "mbevocoder.h"      // DroidStar/QSO One: MBEVocoder（DMR 2450x1150）

namespace {
constexpr uint8_t kProto = 1;
constexpr uint8_t kCaps = 0x01 | 0x04;   // D-STAR + DMR
constexpr int kMaxFrames = 50;
constexpr int kDstar = 0, kDmr = 2;
#ifndef DMR_CAL
#define DMR_CAL "none"
#endif
const char* kId = "qso_dv_dxm proto=1 dstar=qso-one-dv(" QSO_REV ") dmr=mbevocoder-2450x1150 dmrcal(" DMR_CAL ")";

bool readN(void* b, size_t n) { return fread(b, 1, n, stdin) == n; }
void writeN(const void* b, size_t n) { fwrite(b, 1, n, stdout); fflush(stdout); }
int frameBytes(int k) { return (k == kDstar || k == kDmr) ? 9 : 0; }

struct Dmr {
  std::unique_ptr<MBEVocoder> enc, dec;
  void encode(const int16_t* pcm, uint8_t* out) {
    if (!enc) enc.reset(new MBEVocoder());
    int16_t in[160];
    memcpy(in, pcm, sizeof in);
    memset(out, 0, 9);                    // encode は OR で書くので先に消す
    enc->encode_2450x1150(in, out);
  }
  void decode(const uint8_t* f, int16_t* pcm) {
    if (!dec) dec.reset(new MBEVocoder());
    uint8_t c[9];
    memcpy(c, f, 9);
    memset(pcm, 0, 320);
    dec->decode_2450x1150(pcm, c);
  }
};
}  // namespace

int main() {
  qdv_dv::Codecs ds;
  Dmr dmr;
  std::vector<uint8_t> in, out;
  uint8_t cmd;
  while (readN(&cmd, 1)) {
    if (cmd == 'H') {
      size_t n = strlen(kId);
      uint8_t h[6] = {'D', 'V', kProto, kCaps, (uint8_t)(n & 0xff), (uint8_t)(n >> 8)};
      writeN(h, 6);
      writeN(kId, n);
    } else if (cmd == 'D' || cmd == 'E') {
      uint8_t kind, nb[2];
      if (!readN(&kind, 1) || !readN(nb, 2)) return 2;
      int n = nb[0] | (nb[1] << 8);
      int fb = frameBytes(kind);
      if (!fb || n < 1 || n > kMaxFrames) {
        fprintf(stderr, "bad request kind=%d n=%d\n", kind, n);
        return 3;
      }
      bool enc = cmd == 'E';
      size_t inPer = enc ? 320 : fb, outPer = enc ? fb : 320;
      in.resize(inPer * n);
      if (!readN(in.data(), in.size())) return 2;
      out.assign(9 + outPer * n, 0);
      uint32_t total = 0, mx = 0;
      for (int i = 0; i < n; ++i) {
        auto t0 = std::chrono::steady_clock::now();
        int16_t pcm[160];
        if (enc) {
          memcpy(pcm, &in[i * inPer], 320);
          if (kind == kDstar) ds.encode(qdv_dv::kDstar, pcm, &out[9 + i * outPer]);
          else dmr.encode(pcm, &out[9 + i * outPer]);
        } else {
          if (kind == kDstar) ds.decode(qdv_dv::kDstar, &in[i * inPer], pcm);
          else dmr.decode(&in[i * inPer], pcm);
          memcpy(&out[9 + i * outPer], pcm, 320);
        }
        uint32_t us = (uint32_t)std::chrono::duration_cast<std::chrono::microseconds>(
                          std::chrono::steady_clock::now() - t0).count();
        total += us;
        if (us > mx) mx = us;
      }
      for (int b = 0; b < 4; ++b) { out[1 + b] = (total >> (8 * b)) & 0xff; out[5 + b] = (mx >> (8 * b)) & 0xff; }
      writeN(out.data(), out.size());
    } else if (cmd == 'R') {
      uint8_t kind, which;
      if (!readN(&kind, 1) || !readN(&which, 1)) return 2;
      if (kind == kDstar) ds.reset(qdv_dv::kDstar, which);
      else if (kind == kDmr) {
        if (which & 1) dmr.enc.reset();
        if (which & 2) dmr.dec.reset();
      }
      uint8_t ok = 0;
      writeN(&ok, 1);
    } else if (cmd == 'Q') {
      return 0;
    } else {
      fprintf(stderr, "bad command %d\n", cmd);
      return 3;
    }
  }
  return 0;
}
