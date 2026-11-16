// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dxmonitor project. See vocoders/LICENSE (GNU GPL v3).
// md380_dv.c — MD-380 のファームウェア（D002.032）に入っている AMBE+2 の符号化器・復号器を、
//   dxmonitor のボコーダー（pipe、dv プロトコル）として使うためのヘルパー。DMR（kind 2）だけ。
//   md380tools の emulator（travisgoodspeed/md380tools、emulator/ambe.c）と同じ方法でファームの関数を呼ぶ。
//   32 ビット ARM（AArch32）用。aarch64 の Raspberry Pi OS でも、カーネルが 32 ビットの実行に対応していれば動く（静的リンク）。
//
// dv プロトコル（qso_dv_dxm と同じ。stdin/stdout）:
//   'H'                            → 'D' 'V' <proto=1> <caps> <u16 len> <id>   caps bit2 = DMR
//   'D' <kind=2> <u16 n> <n×9B>     → <status> <u32 us合計> <u32 us最大> <n×320B PCM>
//   'E' <kind=2> <u16 n> <n×320B>   → <status> <u32> <u32> <n×9B>
//   'R' <kind> <which>              → <status>   （ファームの状態は初期化できないので何もしない）
//   'Q'                             → 終了
//   9B は DMR の 72 ビット（FEC 込み）。ファームは 49 ビットで扱うので dmr_ambe_fec.h で変換する。
//
// ファームウェアは Tytera の権利物。このファイルにも dxmonitor にも含めない。利用者が自分の Pi で取得してビルドする
// （vocoders/build_md380_vocoder.sh）。GPL v3 or later。
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include "dmr_ambe_fec.h"

// ファームの関数とバッファ（md380tools の applet/src/symbols_d02.032 で番地を与える）
//   バッファは配列として宣言する（int で宣言すると、コンパイラが大きさ 4 バイトとみなして memcpy を止める）
extern short ambe_inbuffer[], ambe_outbuffer0[], ambe_outbuffer1[];
extern short ambe_outbuffer[], wav_inbuffer0[], wav_inbuffer1[];
extern int ambe_mystery, ambe_en_mystery;
int ambe_decode_wav(signed short *wavbuffer, signed int eighty, short *bitbuffer, int a4, short a5, short a6, int a7);
int ambe_encode_thing(short *bitbuffer, int a2, signed short *wavbuffer, signed int eighty, int a5, short a6, short a7, int a8);

#ifndef MD380_REV
#define MD380_REV "?"
#endif
static const char *kId = "md380_dv proto=1 dmr=md380-fw-D002.032(md380tools " MD380_REV ")";
enum { kProto = 1, kCaps = 0x04, kMaxFrames = 50, kDmr = 2 };

static int readN(void *b, size_t n) { return fread(b, 1, n, stdin) == n; }
static void writeN(const void *b, size_t n) { fwrite(b, 1, n, stdout); fflush(stdout); }
static uint32_t now_us(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (uint32_t)(t.tv_sec * 1000000u + t.tv_nsec / 1000u);
}

static void setup(void) {
  // TCRAM（ファームが使う 0x10000000 の作業領域）を用意し、ファームの領域を実行可能にする
  int fd = open("/dev/zero", O_RDONLY);
  void *tcram = mmap((void *)0x10000000, 0x20000, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
  if (tcram == MAP_FAILED) {
    fprintf(stderr, "md380_dv: mmap tcram failed (%d)\n", errno);
    exit(1);
  }
  if (mprotect((void *)0x800c000, 0xf2c00, PROT_READ | PROT_EXEC))
    fprintf(stderr, "md380_dv: mprotect failed (%d)\n", errno);
  memset(ambe_outbuffer, 0, 50);
}

static void decode1(const uint8_t in9[9], int16_t pcm[160]) {
  uint8_t b49[49];
  dmr_ambe72_to49(in9, b49);
  short *ambe = ambe_inbuffer;
  for (int i = 0; i < 49; i++) ambe[i] = b49[i];
  short *o0 = ambe_outbuffer0, *o1 = ambe_outbuffer1;
  ambe_decode_wav(o0, 80, ambe, 0, 0, 0, (int)&ambe_mystery);
  ambe_decode_wav(o1, 80, ambe, 0, 0, 1, (int)&ambe_mystery);
  memcpy(pcm, o0, 160);
  memcpy(pcm + 80, o1, 160);
}

static void encode1(const int16_t pcm[160], uint8_t out9[9]) {
  short *i0 = wav_inbuffer0, *i1 = wav_inbuffer1, *ambe = ambe_outbuffer;
  memcpy(i0, pcm, 160);
  memcpy(i1, pcm + 80, 160);
  ambe_encode_thing(ambe, 0, i0, 0x50, 0x1840, 0, 0x2000, (int)&ambe_en_mystery);
  ambe_encode_thing(ambe, 0, i1, 0x50, 0x1840, 1, 0x2000, (int)&ambe_en_mystery);
  uint8_t b49[49];
  for (int i = 0; i < 49; i++) b49[i] = ambe[i] & 1;
  dmr_ambe49_to72(b49, out9);
}

int main(void) {
  setup();
  daf_init();
  static uint8_t in[320 * kMaxFrames], out[9 + 320 * kMaxFrames];
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
      int enc = cmd == 'E';
      size_t inPer = enc ? 320 : 9, outPer = enc ? 9 : 320;
      if (n < 1 || n > kMaxFrames) return 3;
      if (!readN(in, inPer * n)) return 2;
      memset(out, 0, 9 + outPer * n);
      if (kind != kDmr) {                 // D-STAR などには対応しない（状態 1 だけ返す）
        out[0] = 1;
        writeN(out, 9);
        continue;
      }
      uint32_t total = 0, mx = 0;
      for (int i = 0; i < n; i++) {
        uint32_t t0 = now_us();
        if (enc) encode1((const int16_t *)(in + i * 320), out + 9 + i * 9);
        else decode1(in + i * 9, (int16_t *)(out + 9 + i * 320));
        uint32_t us = now_us() - t0;
        total += us;
        if (us > mx) mx = us;
      }
      for (int b = 0; b < 4; ++b) { out[1 + b] = (total >> (8 * b)) & 0xff; out[5 + b] = (mx >> (8 * b)) & 0xff; }
      writeN(out, 9 + outPer * n);
    } else if (cmd == 'R') {
      uint8_t kind, which, ok = 0;
      if (!readN(&kind, 1) || !readN(&which, 1)) return 2;
      writeN(&ok, 1);
    } else if (cmd == 'Q') {
      return 0;
    } else {
      fprintf(stderr, "md380_dv: unknown command %d\n", cmd);
      return 4;
    }
  }
  return 0;
}
