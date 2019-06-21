/* 
  This file was generated by KreMLin <https://github.com/FStarLang/kremlin>
  KreMLin invocation: krml -I ../../src/lowparse -skip-compilation -tmpdir ../unittests.snapshot -bundle LowParse.\* -drop FStar.Tactics.\* -drop FStar.Reflection.\* T10.fst T11.fst T11_z.fst T12.fst T12_z.fst T13.fst T13_x.fst T14.fst T14_x.fst T15_body.fst T15.fst T16.fst T16_x.fst T17.fst T17_x_a.fst T17_x_b.fst T18.fst T18_x_a.fst T18_x_b.fst T19.fst T1.fst T20.fst T21.fst T22_body_a.fst T22_body_b.fst T22.fst T23.fst T24.fst T24_y.fst T25_bpayload.fst T25.fst T25_payload.fst T26.fst T27.fst T28.fst T29.fst T2.fst T30.fst T31.fst T32.fst T33.fst T34.fst T35.fst T36.fst T3.fst T4.fst T5.fst T6.fst T6le.fst T7.fst T8.fst T8_z.fst T9_b.fst T9.fst Tag2.fst Tag.fst Tagle.fst -warn-error +9
  F* version: 74c6d2a5
  KreMLin version: 1bd260eb
 */

#include "kremlib.h"
#ifndef __T22_H
#define __T22_H

#include "LowParse.h"
#include "T22_body_b.h"
#include "T22_body_a.h"
#include "Tag.h"


#define T22_Body_a 0
#define T22_Body_b 1

typedef uint8_t T22_t22_tags;

typedef struct T22_t22_s
{
  T22_t22_tags tag;
  union {
    FStar_Bytes_bytes case_Body_a;
    FStar_Bytes_bytes case_Body_b;
  }
  ;
}
T22_t22;

bool T22_uu___is_Body_a(T22_t22 projectee);

FStar_Bytes_bytes T22___proj__Body_a__item___0(T22_t22 projectee);

bool T22_uu___is_Body_b(T22_t22 projectee);

FStar_Bytes_bytes T22___proj__Body_b__item___0(T22_t22 projectee);

Tag_tag T22_tag_of_t22(T22_t22 x);

uint32_t T22_t22_validator(LowParse_Slice_slice input, uint32_t pos);

uint32_t T22_t22_jumper(LowParse_Slice_slice input, uint32_t pos);

uint32_t T22_t22_accessor_a(LowParse_Slice_slice input, uint32_t pos);

uint32_t T22_t22_accessor_b(LowParse_Slice_slice input, uint32_t pos);

#define __T22_H_DEFINED
#endif