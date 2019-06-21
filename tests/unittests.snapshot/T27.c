/* 
  This file was generated by KreMLin <https://github.com/FStarLang/kremlin>
  KreMLin invocation: krml -I ../../src/lowparse -skip-compilation -tmpdir ../unittests.snapshot -bundle LowParse.\* -drop FStar.Tactics.\* -drop FStar.Reflection.\* T10.fst T11.fst T11_z.fst T12.fst T12_z.fst T13.fst T13_x.fst T14.fst T14_x.fst T15_body.fst T15.fst T16.fst T16_x.fst T17.fst T17_x_a.fst T17_x_b.fst T18.fst T18_x_a.fst T18_x_b.fst T19.fst T1.fst T20.fst T21.fst T22_body_a.fst T22_body_b.fst T22.fst T23.fst T24.fst T24_y.fst T25_bpayload.fst T25.fst T25_payload.fst T26.fst T27.fst T28.fst T29.fst T2.fst T30.fst T31.fst T32.fst T33.fst T34.fst T35.fst T36.fst T3.fst T4.fst T5.fst T6.fst T6le.fst T7.fst T8.fst T8_z.fst T9_b.fst T9.fst Tag2.fst Tag.fst Tagle.fst -warn-error +9
  F* version: 74c6d2a5
  KreMLin version: 1bd260eb
 */

#include "T27.h"

uint32_t T27_t27_tag_validator(LowParse_Slice_slice input, uint32_t pos)
{
  if (input.len - pos < (uint32_t)3U)
    return LOWPARSE_LOW_BASE_VALIDATOR_ERROR_NOT_ENOUGH_DATA;
  else
    return pos + (uint32_t)3U;
}

uint32_t T27_t27_tag_jumper(LowParse_Slice_slice input, uint32_t pos)
{
  return pos + (uint32_t)3U;
}

FStar_Bytes_bytes T27_t27_cst;

FStar_Bytes_bytes T27___proj__Mkt27_false__item__tag(T27_t27_false projectee)
{
  return projectee.tag;
}

FStar_Bytes_bytes T27___proj__Mkt27_false__item__value(T27_t27_false projectee)
{
  return projectee.value;
}

bool T27_uu___is_T27_true(T27_t27 projectee)
{
  if (projectee.tag == T27_T27_true)
    return true;
  else
    return false;
}

uint32_t T27___proj__T27_true__item___0(T27_t27 projectee)
{
  if (projectee.tag == T27_T27_true)
    return projectee.case_T27_true;
  else
  {
    KRML_HOST_EPRINTF("KreMLin abort at %s:%d\n%s\n",
      __FILE__,
      __LINE__,
      "unreachable (pattern matches are exhaustive in F*)");
    KRML_HOST_EXIT(255U);
  }
}

bool T27_uu___is_T27_false(T27_t27 projectee)
{
  if (projectee.tag == T27_T27_false)
    return true;
  else
    return false;
}

T27_t27_false T27___proj__T27_false__item___0(T27_t27 projectee)
{
  if (projectee.tag == T27_T27_false)
    return projectee.case_T27_false;
  else
  {
    KRML_HOST_EPRINTF("KreMLin abort at %s:%d\n%s\n",
      __FILE__,
      __LINE__,
      "unreachable (pattern matches are exhaustive in F*)");
    KRML_HOST_EXIT(255U);
  }
}

uint32_t T27_t27_validator(LowParse_Slice_slice input, uint32_t pos)
{
  uint32_t pos_after_t = T27_t27_tag_validator(input, pos);
  if (LOWPARSE_LOW_BASE_VALIDATOR_MAX_LENGTH < pos_after_t)
    return pos_after_t;
  else
  {
    uint32_t len1 = FStar_Bytes_len(T27_t27_cst);
    uint32_t bi = (uint32_t)0U;
    bool bres = true;
    while (true)
    {
      uint32_t i = bi;
      bool ite;
      if (i == len1)
        ite = true;
      else
      {
        uint32_t i_ = i + (uint32_t)1U;
        uint8_t uu____0 = input.base[pos + i];
        bool res = uu____0 == FStar_Bytes_get(T27_t27_cst, i);
        bres = res;
        bi = i_;
        ite = !res;
      }
      if (ite)
        break;
    }
    bool res = bres;
    bool b = res;
    if (b)
      if (input.len - pos_after_t < (uint32_t)4U)
        return LOWPARSE_LOW_BASE_VALIDATOR_ERROR_NOT_ENOUGH_DATA;
      else
        return pos_after_t + (uint32_t)4U;
    else
      return T3_t3_validator(input, pos_after_t);
  }
}

uint32_t T27_t27_jumper(LowParse_Slice_slice input, uint32_t pos)
{
  uint32_t pos_after_t = T27_t27_tag_jumper(input, pos);
  uint32_t len1 = FStar_Bytes_len(T27_t27_cst);
  uint32_t bi = (uint32_t)0U;
  bool bres = true;
  while (true)
  {
    uint32_t i = bi;
    bool ite;
    if (i == len1)
      ite = true;
    else
    {
      uint32_t i_ = i + (uint32_t)1U;
      uint8_t uu____0 = input.base[pos + i];
      bool res = uu____0 == FStar_Bytes_get(T27_t27_cst, i);
      bres = res;
      bi = i_;
      ite = !res;
    }
    if (ite)
      break;
  }
  bool res = bres;
  bool b = res;
  if (b)
    return pos_after_t + (uint32_t)4U;
  else
    return T3_t3_jumper(input, pos_after_t);
}

uint32_t T27_t27_accessor_true(LowParse_Slice_slice input, uint32_t pos)
{
  return T27_t27_tag_jumper(input, pos);
}

uint32_t T27_t27_accessor_false(LowParse_Slice_slice input, uint32_t pos)
{
  return T27_t27_tag_jumper(input, pos);
}
