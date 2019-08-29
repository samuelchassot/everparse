module Prelude
module LP = LowParse.Spec.Base
module LPC = LowParse.Spec.Combinators
module LPL = LowParse.Low.Base
module LPLC = LowParse.Low.Combinators
////////////////////////////////////////////////////////////////////////////////
// Parsers
////////////////////////////////////////////////////////////////////////////////

let parser_kind = LP.parser_kind
let parser = LP.parser
let glb (k1 k2:parser_kind) : parser_kind = LP.glb k1 k2

/// Parser: return
let ret_kind = LPC.parse_ret_kind
inline_for_extraction noextract
let parse_ret #t (v:t)
  : Tot (parser ret_kind t)
  = LPC.parse_ret #t v

/// Parser: bind
let and_then_kind k1 k2 = LPC.and_then_kind k1 k2
inline_for_extraction noextract
let parse_dep_pair #k1 (#t1: Type0) (p1: parser k1 t1)
                   #k2 (#t2: (t1 -> Tot Type0)) (p2: (x: t1) -> parser k2 (t2 x))
  : Tot (parser (and_then_kind k1 k2) (dtuple2 t1 t2) )
  = LPC.parse_dtuple2 p1 p2

/// Parser: sequencing
inline_for_extraction noextract
let parse_pair #k1 #t1 (p1:parser k1 t1)
               #k2 #t2 (p2:parser k2 t2)
  : Tot (parser (and_then_kind k1 k2) (t1 * t2))
  = LPC.nondep_then p1 p2

/// Parser: map
let injective_map a b = f:(a -> Tot b){LPC.synth_injective f}
inline_for_extraction noextract
let parse_map #k #t1 #t2 (p:parser k t1)
              (f:injective_map t1 t2)
  : Tot (parser k t2)
  = LPC.parse_synth p f

/// Parser: filter
let refine t (f:t -> bool) = x:t{f x}
let filter_kind k = LPC.parse_filter_kind k
inline_for_extraction noextract
let parse_filter #k #t (p:parser k t) (f:(t -> bool))
  : Tot (parser (LPC.parse_filter_kind k) (refine t f))
  = LPC.parse_filter #k #t p f

/// Parser: weakening kinds
let parse_weaken #k #t (p:parser k t) (k':parser_kind{k' `LP.is_weaker_than` k})
  : Tot (parser k' t)
  = LP.weaken k' p

/// Parser: unreachable, for default cases of exhaustive pattern matching
let parse_impos (_:squash False)
  : Tot (parser ret_kind False)
  = false_elim()

////////////////////////////////////////////////////////////////////////////////
// Readers
////////////////////////////////////////////////////////////////////////////////

let reader #k #t (p:parser k t) = LPLC.leaf_reader p

let read_filter (#k: parser_kind)
                (#t: Type0)
                (#p: parser k t)
                (p32: LPL.leaf_reader p)
                (f: (t -> bool))
    : LPL.leaf_reader (parse_filter p f)
    = LPLC.read_filter p32 f

////////////////////////////////////////////////////////////////////////////////
// Validators
////////////////////////////////////////////////////////////////////////////////
let validator (#k:parser_kind) (#t:Type) (p:parser k t)
  : Type
  = LPL.validator #k #t p

let validate_ret
  : validator (parse_ret ())
  = LPLC.validate_ret ()

let validate_pair #k1 #t1 (#p1:parser k1 t1) (v1:validator p1)
                  #k2 #t2 (#p2:parser k2 t2) (v2:validator p2)
  : validator (p1 `parse_pair` p2)
  = LPLC.validate_nondep_then v1 v2

let validate_dep_pair #k1 #t1 (#p1:parser k1 t1) (v1:validator p1) (r1: LPL.leaf_reader p1)
                      #k2 (#t2:t1 -> Type) (#p2:(x:t1 -> parser k2 (t2 x))) (v2:(x:t1 -> validator (p2 x)))
  : Tot (validator (p1 `parse_dep_pair` p2))
  = LPLC.validate_dtuple2 v1 r1 v2

let validate_map #k #t1 (#p:parser k t1) (v:validator p)
                    #t2 (f:injective_map t1 t2)
  : Tot (validator (p `parse_map` f))
  = LPLC.validate_synth v f ()

let validate_filter (#k:_) (#t:_) (#p:parser k t) (v:validator p) (r:LPL.leaf_reader p) (f:(t -> bool))
  : Tot (validator (p `parse_filter` f))
  = LPLC.validate_filter v r f (fun x -> f x)

let validate_weaken #k #t (#p:parser k t) (v:validator p) (k':parser_kind{k' `LP.is_weaker_than` k})
  : Tot (validator (p `parse_weaken` k'))
  = LPLC.validate_weaken k' v ()

let validate_impos (_:squash False)
  : Tot (validator (parse_impos ()))
  = false_elim()

////////////////////////////////////////////////////////////////////////////////
// Base types
////////////////////////////////////////////////////////////////////////////////

/// UInt32
module U32 = FStar.UInt32
let _UINT32 = U32.t
let kind__UINT32 = LowParse.Spec.BoundedInt.parse_u32_kind
let parse__UINT32 : parser kind__UINT32 _UINT32 = LowParse.Spec.BoundedInt.parse_u32_le
let validate__UINT32 : validator parse__UINT32 = LowParse.Low.BoundedInt.validate_u32_le ()
let read__UINT32 : LPL.leaf_reader parse__UINT32 = LowParse.Low.BoundedInt.read_u32_le

/// Lists/arrays
let nlist (n:U32.t) (t:Type) = LowParse.Spec.VCList.nlist (U32.v n) t
let nlist_kind (k:LP.parser_kind) = LowParse.Spec.VCList.parse_nlist_kind 1 k
let parse_nlist (n:U32.t) #k #t (p:parser k t) : parser (nlist_kind k) (nlist n t) = assume false; LowParse.Spec.VCList.parse_nlist (U32.v n) p
let validate_nlist (n:U32.t) #k #t (#p:parser k t) (v:validator p) : validator (parse_nlist n p) = assume false; LowParse.Low.VCList.validate_nlist n v

////////////////////////////////////////////////////////////////////////////////
//placeholders
////////////////////////////////////////////////////////////////////////////////
let _UINT8 =_UINT32
let kind__UINT8 = kind__UINT32
let parse__UINT8 = parse__UINT32
let validate__UINT8 = validate__UINT32

let sizeOf (x:'a) = 0ul
