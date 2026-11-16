// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dxmonitor project. See vocoders/LICENSE (GNU GPL v3).
// dmr_ambe_fec.h — DMR の AMBE+2（3600x2450）の 72 ビット（9 バイト、FEC 込み）⇔ 49 ビット（ambe_d）の変換。
//   72 ビット = A（Golay(24,12)）24 ＋ B（Golay(23,12)＋疑似乱数でスクランブル）23 ＋ C（保護なし）25。
//   49 ビット = A のデータ 12 ＋ B のデータ 12 ＋ C 25（mbelib の ambe_d、dsd の .amb と同じ並び）。
//   ビットの位置（A/B/C の表）は MMDVM_CM・DroidStar と同じ。疑似乱数は mbelib の式で作る。
//   dxmonitor の md380_dv.c（md380 のファームの符号化器）と試験で使う。GPL v3 or later。
#ifndef DMR_AMBE_FEC_H
#define DMR_AMBE_FEC_H
#include <stdint.h>
#include <string.h>

static const unsigned int DAF_A[24] = {0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 64, 68, 1, 5, 9, 13, 17, 21};
static const unsigned int DAF_B[23] = {25, 29, 33, 37, 41, 45, 49, 53, 57, 61, 65, 69, 2, 6, 10, 14, 18, 22, 26, 30, 34, 38, 42};
static const unsigned int DAF_C[25] = {46, 50, 54, 58, 62, 66, 70, 3, 7, 11, 15, 19, 23, 27, 31, 35, 39, 43, 47, 51, 55, 59, 63, 67, 71};

static inline int daf_get(const uint8_t *p, unsigned i) { return (p[i >> 3] >> (7 - (i & 7))) & 1; }
static inline void daf_put(uint8_t *p, unsigned i, int b) {
  if (b) p[i >> 3] |= (uint8_t)(0x80 >> (i & 7)); else p[i >> 3] &= (uint8_t)~(0x80 >> (i & 7));
}

// Golay(24,12)：データ 12 ビットを上位に置く組織符号（DroidStar の golay_24_encode と同じ生成行列）
static inline uint32_t daf_golay24_encode(uint32_t d) {
  static const uint32_t g[12] = {040006165, 020003073, 010007550, 04003664, 02001732, 01006631,
                                 0403315, 0201547, 0106706, 045227, 024476, 014353};
  uint32_t c = 0;
  for (int i = 0; i < 12; i++)
    if (d & (1u << (11 - i))) c ^= g[i];
  return c;
}
static inline uint32_t daf_golay23_encode(uint32_t d) { return daf_golay24_encode(d) >> 1; }

// Golay(23,12) の復号：シンドローム（下位 11 ビット）→ 誤りパターン（重み 3 以下。完全符号なので 2048 通りちょうど）
static uint32_t daf_syn_table[2048];
static int daf_ready = 0;
static inline uint32_t daf_syn23(uint32_t w) { return (w ^ daf_golay23_encode(w >> 11)) & 0x7FF; }
static void daf_init(void) {
  if (daf_ready) return;
  for (int i = 0; i < 2048; i++) daf_syn_table[i] = 0xFFFFFFFF;
  daf_syn_table[0] = 0;
  for (int a = 0; a < 23; a++) {
    uint32_t e1 = 1u << a;
    daf_syn_table[daf_syn23(e1)] = e1;
    for (int b = a + 1; b < 23; b++) {
      uint32_t e2 = e1 | (1u << b);
      daf_syn_table[daf_syn23(e2)] = e2;
      for (int c = b + 1; c < 23; c++) {
        uint32_t e3 = e2 | (1u << c);
        daf_syn_table[daf_syn23(e3)] = e3;
      }
    }
  }
  daf_ready = 1;
}
// 23 ビットの受信語 → データ 12 ビット。*errs に直したビット数を足す
static inline uint32_t daf_golay23_decode(uint32_t w, int *errs) {
  daf_init();
  uint32_t e = daf_syn_table[daf_syn23(w)];
  if (errs) errs[0] += __builtin_popcount(e);
  return ((w ^ e) >> 11) & 0xFFF;
}

// mbelib の疑似乱数（C0 のデータ 12 ビットから、B に重ねる 23 ビット）
static inline uint32_t daf_prng(uint32_t a12) {
  uint32_t pr = 16u * a12, m = 0;
  for (int i = 1; i < 24; i++) {
    pr = (173u * pr + 13849u) & 0xFFFF;
    m = (m << 1) | (pr >> 15);
  }
  return m;  // 上位ビットが B の先頭（B_TABLE[0]）に当たる
}

// 9 バイト（72 ビット）→ 49 ビット（bits[0..48] に 0/1）。戻り値は直したビット数
static inline int dmr_ambe72_to49(const uint8_t in9[9], uint8_t bits49[49]) {
  uint32_t a = 0, b = 0, c = 0;
  for (int i = 0; i < 24; i++) a = (a << 1) | daf_get(in9, DAF_A[i]);
  for (int i = 0; i < 23; i++) b = (b << 1) | daf_get(in9, DAF_B[i]);
  for (int i = 0; i < 25; i++) c = (c << 1) | daf_get(in9, DAF_C[i]);
  int errs = 0;
  uint32_t a12 = daf_golay23_decode(a >> 1, &errs);   // 24 ビット目（全体パリティ）は使わない
  uint32_t b12 = daf_golay23_decode(b ^ daf_prng(a12), &errs);
  for (int i = 0; i < 12; i++) bits49[i] = (a12 >> (11 - i)) & 1;
  for (int i = 0; i < 12; i++) bits49[12 + i] = (b12 >> (11 - i)) & 1;
  for (int i = 0; i < 25; i++) bits49[24 + i] = (c >> (24 - i)) & 1;
  return errs;
}

// 49 ビット → 9 バイト（72 ビット）
static inline void dmr_ambe49_to72(const uint8_t bits49[49], uint8_t out9[9]) {
  uint32_t a12 = 0, b12 = 0, c = 0;
  for (int i = 0; i < 12; i++) a12 = (a12 << 1) | (bits49[i] & 1);
  for (int i = 0; i < 12; i++) b12 = (b12 << 1) | (bits49[12 + i] & 1);
  for (int i = 0; i < 25; i++) c = (c << 1) | (bits49[24 + i] & 1);
  uint32_t a = daf_golay24_encode(a12);
  uint32_t b = daf_golay23_encode(b12) ^ daf_prng(a12);
  memset(out9, 0, 9);
  for (int i = 0; i < 24; i++) daf_put(out9, DAF_A[i], (a >> (23 - i)) & 1);
  for (int i = 0; i < 23; i++) daf_put(out9, DAF_B[i], (b >> (22 - i)) & 1);
  for (int i = 0; i < 25; i++) daf_put(out9, DAF_C[i], (c >> (24 - i)) & 1);
}
#endif
