module EverParse3d.Actions.Base
friend EverParse3d.Kinds
friend EverParse3d.Prelude
open FStar.HyperStack.ST
open LowStar.Buffer
open LowStar.BufferOps
module B = LowStar.Buffer
module I = EverParse3d.InputStream.Base
module HS = FStar.HyperStack
module HST = FStar.HyperStack.ST

module LPE = EverParse3d.ErrorCode
open FStar.Tactics.Typeclasses

module B = LowStar.Buffer
module U8 = FStar.UInt8
module P = EverParse3d.Prelude

let hinv = HS.mem -> Tot Type0
let liveness_inv = i:hinv {
  forall l h0 h1. {:pattern (i h1); (modifies l h0 h1)}  i h0 /\ modifies l h0 h1 /\ address_liveness_insensitive_locs `loc_includes` l ==> i h1
}
let mem_inv  = liveness_inv
let slice_inv = loc -> mem_inv
let inv_implies (inv0 inv1:slice_inv) =
  forall i h.
    inv0 i h ==> inv1 i h
let true_inv : slice_inv = fun _ _ -> True
let conj_inv (i0 i1:slice_inv) : slice_inv = fun sl h -> i0 sl h /\ i1 sl h
let eloc = (l: FStar.Ghost.erased B.loc { B.address_liveness_insensitive_locs `B.loc_includes` l })
let eloc_union (l1 l2:eloc) : Tot eloc = B.loc_union l1 l2
let eloc_none : eloc = B.loc_none
let eloc_includes (l1 l2:eloc) = B.loc_includes l1 l2 /\ True

let inv_implies_refl inv = ()
let inv_implies_true inv0 = ()
let inv_implies_conj inv0 inv1 inv2 h01 h02 = ()

let eloc_includes_none l = ()
let eloc_includes_union l0 l1 l2 h01 h02 = ()
let eloc_includes_refl l = ()

let bpointer a = B.pointer a
let ptr_loc #a (x:B.pointer a) : Tot eloc = B.loc_buffer x
let ptr_inv #a (x:B.pointer a) : slice_inv = fun (sl:_) h -> B.live h x


let app_ctxt = B.pointer U8.t
let app_loc (x:app_ctxt) (l:eloc) : eloc = B.loc_buffer x `loc_union` l

inline_for_extraction
noextract
let input_buffer_t = EverParse3d.InputStream.All.t

let action
  p inv l on_success a
=
    (# [tcresolve ()] I.extra_t #input_buffer_t) ->
    ctxt: app_ctxt ->
    sl: input_buffer_t ->
    pos: LPE.pos_t ->
    posf: LPE.pos_t ->
    Stack a
      (requires fun h ->
        I.live sl h /\
        inv (I.footprint sl) h /\
        B.live h ctxt /\
        loc_not_unused_in h `loc_includes` app_loc ctxt l /\
        address_liveness_insensitive_locs `loc_includes` app_loc ctxt l /\
        app_loc ctxt l `loc_disjoint` I.footprint sl /\
        U64.v pos <= U64.v posf /\
        U64.v posf == Seq.length (I.get_read sl h)
      )
      (ensures fun h0 _ h1 ->
        let sl = Ghost.reveal sl in
        modifies (app_loc ctxt l) h0 h1 /\
        B.live h1 ctxt /\
        inv (I.footprint sl) h1)

module LP = LowParse.Spec.Base
module LPL = LowParse.Low.Base

unfold
let valid_consumed
  (#input_buffer_t: Type0)
  (# [tcresolve ()] inst : I.input_stream_inst input_buffer_t)
  (#k: LP.parser_kind)
  (#t: Type)
  (p: LP.parser k t)
  (h: HS.mem)
  (h': HS.mem)
  (sl: input_buffer_t)
: Tot prop
= I.live sl h /\
  I.live sl h' /\
  begin
    let s = I.get_remaining sl h in
    begin match LP.parse p s with
    | None -> False
    | Some (_, len) -> I.get_remaining sl h' `Seq.equal` Seq.slice s len (Seq.length s)
    end
  end

unfold
let valid_length
  (#input_buffer_t: Type0)
  (# [tcresolve ()] inst : I.input_stream_inst input_buffer_t)
  (#k: LP.parser_kind)
  (#t: Type)
  (p: LP.parser k t)
  (h: HS.mem)
  (sl: input_buffer_t)
  (len: int)
: Tot prop
= I.live sl h /\
  begin
    let s = I.get_remaining sl h in
    begin match LP.parse p s with
    | None -> False
    | Some (_, len') -> len == len'
    end
  end

let valid
  (#input_buffer_t: Type0)
  (# [tcresolve ()] inst : I.input_stream_inst input_buffer_t)
  (#k: LP.parser_kind)
  (#t: Type)
  (p: LP.parser k t)
  (h: HS.mem)
  (sl: input_buffer_t)
: Tot prop
= I.live sl h /\
  Some? (LP.parse p (I.get_remaining sl h))

inline_for_extraction
let error_handler = 
    typename:string ->
    fieldname:string ->
    error_reason:string ->
    error_code:U64.t ->
    ctxt: app_ctxt ->
    sl: input_buffer_t ->
    pos: LPE.pos_t ->
    Stack unit
      (requires fun h ->
        I.live sl h /\
        true_inv (I.footprint sl) h /\
        B.live h ctxt /\
        loc_not_unused_in h `loc_includes` app_loc ctxt eloc_none /\
        address_liveness_insensitive_locs `loc_includes` app_loc ctxt eloc_none /\
        app_loc ctxt eloc_none `loc_disjoint` I.footprint sl /\
        U64.v pos <= Seq.length (I.get_read sl h)
      )
      (ensures fun h0 _ h1 ->
        let sl = Ghost.reveal sl in
        modifies (app_loc ctxt eloc_none) h0 h1 /\
        B.live h1 ctxt /\
        true_inv (I.footprint sl) h1)

inline_for_extraction noextract
let validate_with_action_t' (#k:LP.parser_kind) (#t:Type) (p:LP.parser k t) (inv:slice_inv) (l:eloc) (allow_reading:bool) =
  (# [tcresolve ()] I.extra_t #input_buffer_t) ->
  (ctxt: app_ctxt) ->
  (err : error_handler) ->
  (sl: input_buffer_t) ->
  (len: I.tlen sl) ->
  (pos: LPE.pos_t) ->
  Stack U64.t
  (requires fun h ->
    I.live sl h /\
    inv (I.footprint sl) h /\
    B.live h ctxt /\
    loc_not_unused_in h `loc_includes` app_loc ctxt l /\
    address_liveness_insensitive_locs `loc_includes` app_loc ctxt l /\
    U64.v pos == Seq.length (I.get_read sl h) /\
    app_loc ctxt l `loc_disjoint` I.footprint sl
  )
  (ensures fun h res h' ->
    I.live sl h' /\
    modifies (app_loc ctxt l `loc_union` I.perm_footprint sl) h h' /\
    inv (I.footprint sl) h' /\
    B.live h' ctxt /\
    (((~ allow_reading) \/ LPE.is_error res) ==> U64.v (LPE.get_validator_error_pos res) == Seq.length (I.get_read sl h')) /\
    begin let s = I.get_remaining sl h in
    if LPE.is_success res
    then
      begin if allow_reading
      then U64.v res >= U64.v pos /\ valid_length p h sl (U64.v res - U64.v pos) /\ I.get_remaining sl h' == s
      else valid_consumed p h h' sl
      end
    else
      let s' = I.get_remaining sl h' in
      (LPE.get_validator_error_kind res <> LPE.get_validator_error_kind LPE.validator_error_action_failed ==> None? (LP.parse p s)) /\
      Seq.length s' <= Seq.length s /\
      s' `Seq.equal` Seq.slice s (Seq.length s - Seq.length s') (Seq.length s)
    end
    )

let validate_with_action_t p inv l allow_reading = validate_with_action_t' p inv l allow_reading

let validate_eta v =
  fun ctxt err sl pos -> v ctxt err sl pos

let act_with_comment
  s res a
=
  fun ctxt sl pos posf ->
  LPL.comment s;
  a ctxt sl pos posf

let leaf_reader
  #nz
  #k
  (#t: Type)
  (p: parser k t)
: Tot Type
=
  (# [FStar.Tactics.Typeclasses.tcresolve ()] _extra_t : I.extra_t #input_buffer_t ) ->
  (sl: input_buffer_t) ->
  (pos: LPE.pos_t) ->
  Stack t
  (requires (fun h ->
    valid p h sl /\
    U64.v pos == Seq.length (I.get_read sl h)
  ))
  (ensures (fun h res h' ->
    let s = I.get_remaining sl h in
    I.live sl h' /\
    modifies (I.perm_footprint sl) h h' /\
    begin match LP.parse p s with
    | None -> False
    | Some (y, len) ->
      res == y /\
      I.get_remaining sl h' == Seq.slice s len (Seq.length s)
    end
  ))

#push-options "--z3rlimit 32"

inline_for_extraction
noextract
let validate_with_success_action' (name: string) #nz #wk (#k1:parser_kind nz wk) #t1 (#p1:parser k1 t1) (#inv1:_) (#l1:eloc)
                         (v1:validate_with_action_t p1 inv1 l1 false)
                         (#inv2:_) (#l2:eloc) #b (a:action p1 inv2 l2 b bool)
  : validate_with_action_t p1 (conj_inv inv1 inv2) (l1 `eloc_union` l2) false
  = fun ctxt err input input_length start_position ->
    [@inline_let] let pos0 = start_position in
    let h0 = HST.get () in
    [@(rename_let ("positionAfter" ^ name))]
    let pos1 = v1 ctxt err input input_length pos0 in
    let h1 = HST.get () in
    modifies_address_liveness_insensitive_unused_in h0 h1;
    if LPE.is_success pos1
    then
         [@(rename_let ("action_success_" ^ name))]
         let b = a ctxt input pos0 pos1 in
         let h2 = HST.get () in
         modifies_address_liveness_insensitive_unused_in h1 h2;
         if not b
         then LPE.set_validator_error_pos LPE.validator_error_action_failed pos1
         else pos1
    else
         pos1

inline_for_extraction
noextract
let validate_drop_true
   (#k:LP.parser_kind) (#t:Type) (#p:LP.parser k t) (#inv:slice_inv) (#l:eloc) (v: validate_with_action_t' p inv l true)
: Tot (validate_with_action_t' p inv l false)
= fun ctxt err input input_length start_position ->
  [@inline_let] let pos = start_position in
  let res = v ctxt err input input_length pos in
  I.skip_if_success input pos res;
  res

inline_for_extraction
noextract
let validate_drop
   (#k:LP.parser_kind) (#t:Type) (#p:LP.parser k t) (#inv:slice_inv) (#l:eloc) #allow_reading (v: validate_with_action_t' p inv l allow_reading)
: Tot (validate_with_action_t' p inv l false)
= if allow_reading
  then validate_drop_true v
  else v

let validate_with_success_action
  name v1 a
= validate_with_success_action' name (validate_drop v1) a

inline_for_extraction noextract
let validate_with_error_handler (typename:string) 
                                (fieldname:string)
                                #nz
                                #wk
                                (#k1:parser_kind nz wk)
                                 #t1
                                (#p1:parser k1 t1)
                                (#inv1:_)
                                (#l1:eloc)
                                (#ar:_)
                                (v1:validate_with_action_t p1 inv1 l1 ar)
  : validate_with_action_t p1 inv1 l1 ar
  = fun ctxt err input input_length start_position ->
    [@inline_let] let pos0 = start_position in
    let h0 = HST.get () in
    [@(rename_let ("positionAfter" ^ typename))]
    let pos1 = v1 ctxt err input input_length pos0 in
    let h1 = HST.get () in
    modifies_address_liveness_insensitive_unused_in h0 h1;
    if LPE.is_success pos1
    then pos1
    else (
         err typename fieldname (LPE.error_reason_of_result pos1) (LPE.get_validator_error_kind pos1) ctxt input pos0;
         pos1
    )

inline_for_extraction noextract
let validate_ret
  : validate_with_action_t (parse_ret ()) true_inv eloc_none true
  = fun ctxt err input input_length start_position ->
    start_position

#push-options "--z3rlimit 32"

module LPC = LowParse.Spec.Combinators

inline_for_extraction noextract
let validate_pair
       (name1: string)
       #nz1 (#k1:parser_kind nz1 WeakKindStrongPrefix) #t1 (#p1:parser k1 t1)
       (#inv1:_) (#l1:eloc) (#ar1:_) (v1:validate_with_action_t p1 inv1 l1 ar1)
       #nz2 #wk2 (#k2:parser_kind nz2 wk2) #t2 (#p2:parser k2 t2)
       (#inv2:_) (#l2:eloc) (#ar2:_) (v2:validate_with_action_t p2 inv2 l2 ar2)
  : validate_with_action_t (p1 `parse_pair` p2) (conj_inv inv1 inv2) (l1 `eloc_union` l2) false
  = fun ctxt err input input_length start_position ->
    [@inline_let] let pos = start_position in
    let h = HST.get () in
    LPC.nondep_then_eq p1 p2 (I.get_remaining input h);
    [@(rename_let ("positionAfter" ^ name1))]
    let pos1 = validate_drop v1 ctxt err input input_length pos in
    let h1 = HST.get () in
    modifies_address_liveness_insensitive_unused_in h h1;
    if LPE.is_error pos1
    then
      pos1
    else
      validate_drop v2 ctxt err input input_length pos1

inline_for_extraction noextract
let validate_dep_pair
      (name1: string)
      #nz1 (#k1:parser_kind nz1 _) #t1 (#p1:parser k1 t1)
      #inv1 #l1 (v1:validate_with_action_t p1 inv1 l1 true) (r1: leaf_reader p1)
      #nz2 #wk2 (#k2:parser_kind nz2 wk2) (#t2:t1 -> Type) (#p2:(x:t1 -> parser k2 (t2 x)))
      #inv2 #l2 #ar2 (v2:(x:t1 -> validate_with_action_t (p2 x) inv2 l2 ar2))
  : Tot (validate_with_action_t (p1 `parse_dep_pair` p2) (conj_inv inv1 inv2) (l1 `eloc_union` l2) false)
  = fun ctxt err input input_length start_position ->
      [@inline_let] let pos = start_position in
      let h = HST.get () in
      LPC.parse_dtuple2_eq p1 p2 (I.get_remaining input h);
      [@(rename_let ("positionAfter" ^ name1))]
      let pos1 = v1 ctxt err input input_length pos in
      let h1 = HST.get() in
      if LPE.is_error pos1
      then begin
        pos1
      end
      else
        [@(rename_let ("" ^ name1))]
        let x = r1 input pos in
        let h15 = HST.get () in
        let _ = modifies_address_liveness_insensitive_unused_in h h15 in
        validate_drop (v2 x) ctxt err input input_length pos1

#pop-options

#push-options "--z3rlimit 64"
#restart-solver

inline_for_extraction noextract
let validate_dep_pair_with_refinement_and_action'
      (name1: string)
      (#nz1: _) (#k1:parser_kind nz1 _) (#t1: _) (#p1:parser k1 t1)
      (#inv1: _) (#l1: _) (v1:validate_with_action_t p1 inv1 l1 true) (r1: leaf_reader p1)
      (f: t1 -> bool)
      (#inv1': _) (#l1': _) (#b: _) (a:t1 -> action p1 inv1' l1' b bool)
      (#nz2: _) (#wk2: _) (#k2:parser_kind nz2 wk2) (#t2:refine _ f -> Type) (#p2:(x:refine _ f) -> parser k2 (t2 x))
      (#inv2: _) (#l2: _) (#ar2: _) (v2:(x:refine _ f -> validate_with_action_t (p2 x) inv2 l2 ar2))
  : Tot (validate_with_action_t
             ((p1 `LPC.parse_filter` f) `(parse_dep_pair #nz1)` p2)
             (conj_inv inv1 (conj_inv inv1' inv2))
             (l1 `eloc_union` (l1' `eloc_union` l2))
             false)
  =
  fun ctxt err input input_length startPosition ->
      let h0 = HST.get () in
      LPC.parse_dtuple2_eq' #_ #_ (p1 `LPC.parse_filter` f) #_ #t2 p2 (I.get_remaining input h0);
      LPC.parse_filter_eq p1 f (I.get_remaining input h0);
      [@(rename_let ("positionAfter" ^ name1))]
      let res = v1 ctxt err input input_length startPosition in
      let h1 = HST.get() in
      modifies_address_liveness_insensitive_unused_in h0 h1;
      if LPE.is_error res
      then begin
        res
      end
      else begin
        assert (I.get_remaining input h1 == I.get_remaining input h0);
        [@(rename_let ("" ^ name1))]
        let field_value = r1 input startPosition in
        [@(rename_let (name1 ^ "ConstraintIsOk"))]
        let ok = f field_value in
        [@(rename_let ("positionAfter" ^ name1))]
        let res1 = LPE.check_constraint_ok ok res in
        let h2 = HST.get() in
        if LPE.is_error res1
        then
          res1
        else begin
             modifies_address_liveness_insensitive_unused_in h1 h2;
             if not (a field_value ctxt input startPosition res1)
             then LPE.set_validator_error_pos LPE.validator_error_action_failed res1 //action failed
             else begin
               let h15 = HST.get () in
               let _ = modifies_address_liveness_insensitive_unused_in h0 h15 in
               validate_drop (v2 field_value) ctxt err input input_length res1
             end
        end
      end

inline_for_extraction noextract
let validate_dep_pair_with_refinement_and_action_total_zero_parser'
      (name1: string)
      (#nz1: _) (#k1:parser_kind nz1 WeakKindStrongPrefix) (#t1: _) (#p1:parser k1 t1) (r1: leaf_reader p1)
      (inv1: _) (l1: _)
      (f: t1 -> bool)
      (#inv1': _) (#l1': _) (#b: _) (a:t1 -> action p1 inv1' l1' b bool)
      (#nz2: _) (#wk2: _) (#k2:parser_kind nz2 wk2) (#t2:refine _ f -> Type) (#p2:(x:refine _ f -> parser k2 (t2 x)))
      (#inv2: _) (#l2: _) (#ar2: _) (v2:(x:refine _ f -> validate_with_action_t (p2 x) inv2 l2 ar2))
  : Pure (validate_with_action_t
             ((p1 `LPC.parse_filter` f) `(parse_dep_pair #nz1)` p2)
             (conj_inv inv1 (conj_inv inv1' inv2))
             (l1 `eloc_union` (l1' `eloc_union` l2))
             false)
         (requires (
           let open LP in
           k1.parser_kind_high == Some 0 /\
           k1.parser_kind_metadata == Some ParserKindMetadataTotal
         ))
         (ensures (fun _ -> True))
  = fun ctxt err input input_length startPosition ->
      let h0 = HST.get () in
      LPC.parse_dtuple2_eq' #_ #_ (p1 `LPC.parse_filter` f) #_ #t2 p2 (I.get_remaining input h0);
      LPC.parse_filter_eq p1 f (I.get_remaining input h0);
      [@inline_let] let _ = LP.parser_kind_prop_equiv k1 p1 in
      begin
        LowStar.Comment.comment ("Validating field " ^ name1);
        [@(rename_let ("" ^ name1))]
        let field_value = r1 input startPosition in
        [@(rename_let (name1 ^ "ConstraintIsOk"))]
        let ok = f field_value in
        [@(rename_let ("positionAfter" ^ name1))]
        let res1 = LPE.check_constraint_ok ok startPosition in
        if LPE.is_error res1
        then
             res1
        else let h2 = HST.get() in
             modifies_address_liveness_insensitive_unused_in h0 h2;
             if not (a field_value ctxt input startPosition res1)
             then LPE.set_validator_error_pos LPE.validator_error_action_failed startPosition //action failed
             else begin
               let h15 = HST.get () in
               let _ = modifies_address_liveness_insensitive_unused_in h0 h15 in
               validate_drop (v2 field_value) ctxt err input input_length res1
             end
        end

inline_for_extraction noextract
let validate_dep_pair_with_refinement_and_action
      (p1_is_constant_size_without_actions: bool)
      (name1: string)
      #nz1 (#k1:parser_kind nz1 _) #t1 (#p1:parser k1 t1)
      #inv1 #l1 (v1:validate_with_action_t p1 inv1 l1 true) (r1: leaf_reader p1)
      (f: t1 -> bool)
      #inv1' #l1' #b (a:t1 -> action p1 inv1' l1' b bool)
      #nz2 #wk2 (#k2:parser_kind nz2 wk2) (#t2:refine _ f -> Type) (#p2:(x:refine _ f -> parser k2 (t2 x)))
      #inv2 #l2 #ar2 (v2:(x:refine _ f -> validate_with_action_t (p2 x) inv2 l2 ar2))
  : Tot (validate_with_action_t ((p1 `parse_filter` f) `parse_dep_pair` p2)
                                (conj_inv inv1 (conj_inv inv1' inv2))
                                (l1 `eloc_union` (l1' `eloc_union` l2))
                                false)
  = if
      p1_is_constant_size_without_actions `LP.bool_and`
      (k1.LP.parser_kind_high = Some 0) `LP.bool_and`
      (k1.LP.parser_kind_metadata = Some LP.ParserKindMetadataTotal)
    then
      validate_dep_pair_with_refinement_and_action_total_zero_parser' name1 r1 inv1 l1 f a v2
    else
      validate_dep_pair_with_refinement_and_action' name1 v1 r1 f a v2


inline_for_extraction noextract
let validate_dep_pair_with_action
      #nz1 (#k1:parser_kind nz1 _) #t1 (#p1:parser k1 t1)
      #inv1 #l1 (v1:validate_with_action_t p1 inv1 l1 true) (r1: leaf_reader p1)
      #inv1' #l1' #b (a:t1 -> action p1 inv1' l1' b bool)
      #nz2 #wk2 (#k2:parser_kind nz2 wk2) (#t2:t1 -> Type) (#p2:(x:t1 -> parser k2 (t2 x)))
      #inv2 #l2 #ar2 (v2:(x:t1 -> validate_with_action_t (p2 x) inv2 l2 ar2))
  : Tot (validate_with_action_t
             (p1 `(parse_dep_pair #nz1)` p2)
             (conj_inv inv1 (conj_inv inv1' inv2))
             (l1 `eloc_union` (l1' `eloc_union` l2))
             false)
  = fun ctxt err input input_length startPosition ->
      let h0 = HST.get () in
      LPC.parse_dtuple2_eq' #_ #_ p1 #_ #t2 p2 (I.get_remaining input h0);
      let res = v1 ctxt err input input_length startPosition in
      let h1 = HST.get() in
      modifies_address_liveness_insensitive_unused_in h0 h1;
      if LPE.is_error res
      then begin
        res
      end
      else begin
        let field_value = r1 input startPosition in
        let h2 = HST.get() in
        modifies_address_liveness_insensitive_unused_in h1 h2;
        let action_result = a field_value ctxt input startPosition res in
        let h3 = HST.get () in
        modifies_address_liveness_insensitive_unused_in h2 h3;
        if not action_result
        then LPE.set_validator_error_pos LPE.validator_error_action_failed res //action failed
        else
               validate_drop (v2 field_value) ctxt err input input_length res
      end

inline_for_extraction noextract
let validate_dep_pair_with_refinement'
      (name1: string)
      #nz1 (#k1:parser_kind nz1 _) #t1 (#p1:parser k1 t1)
      #inv1 #l1 (v1:validate_with_action_t p1 inv1 l1 true) (r1: leaf_reader p1)
      (f: t1 -> bool)
      #nz2 #wk2 (#k2:parser_kind nz2 wk2) (#t2:refine _ f -> Type) (#p2:(x:refine _ f -> parser k2 (t2 x)))
      #inv2 #l2 #ar2 (v2:(x:refine _ f -> validate_with_action_t (p2 x) inv2 l2 ar2))
  : Tot (validate_with_action_t
             ((p1 `LPC.parse_filter` f) `(parse_dep_pair #nz1)` p2)
             (conj_inv inv1 inv2)
             (l1 `eloc_union` l2)
             false)
  = fun ctxt err input input_length startPosition ->
      let h0 = HST.get () in
      LPC.parse_dtuple2_eq' #_ #_ (p1 `LPC.parse_filter` f) #_ #t2 p2 (I.get_remaining input h0);
      LPC.parse_filter_eq p1 f (I.get_remaining input h0);
      [@(rename_let ("positionAfter" ^ name1))]
      let res = v1 ctxt err input input_length startPosition in
      let h1 = HST.get() in
      modifies_address_liveness_insensitive_unused_in h0 h1;
      if LPE.is_error res
      then begin
        res
      end
      else begin
        [@(rename_let ("" ^ name1))]
        let field_value = r1 input startPosition in
        [@(rename_let (name1 ^ "ConstraintIsOk"))]
        let ok = f field_value in
        [@(rename_let ("positionAfter" ^ name1))]
        let res1 = LPE.check_constraint_ok ok res in
        if LPE.is_error res1
        then
             res1
        else let h2 = HST.get() in
             // assert (B.modifies B.loc_none h1 h2);
             // assert (inv1' input.LPL.base h2);
             modifies_address_liveness_insensitive_unused_in h1 h2;
             // assert (loc_not_unused_in h2 `loc_includes` l1');
             // assert (valid_pos (p1 `(LPC.parse_filter #k1 #t1)` f) h0 input (uint64_to_uint32 pos) (uint64_to_uint32 res));
             let h15 = HST.get () in
             let _ = modifies_address_liveness_insensitive_unused_in h0 h15 in
             validate_drop (v2 field_value) ctxt err input input_length res1
        end

inline_for_extraction noextract
let validate_dep_pair_with_refinement_total_zero_parser'
      (name1: string)
      #nz1 (#k1:parser_kind nz1 _) #t1 (#p1:parser k1 t1)
      (inv1: _) (l1: _) (r1: leaf_reader p1)
      (f: t1 -> bool)
      #nz2 #wk2 (#k2:parser_kind nz2 wk2) (#t2:refine _ f -> Type) (#p2:(x:refine _ f -> parser k2 (t2 x)))
      #inv2 #l2 #ar2 (v2:(x:refine _ f -> validate_with_action_t (p2 x) inv2 l2 ar2))
  : Pure (validate_with_action_t
             ((p1 `LPC.parse_filter` f) `(parse_dep_pair #nz1)` p2)
             (conj_inv inv1 inv2)
             (l1 `eloc_union` l2)
             false)
         (requires (
           let open LP in
           k1.parser_kind_high == Some 0 /\
           k1.parser_kind_metadata == Some ParserKindMetadataTotal
         ))
         (ensures (fun _ -> True))
  = fun ctxt err input input_length startPosition ->
      let h0 = HST.get () in
      LPC.parse_dtuple2_eq' #_ #_ (p1 `LPC.parse_filter` f) #_ #t2 p2 (I.get_remaining input h0);
      LPC.parse_filter_eq p1 f (I.get_remaining input h0);
      [@inline_let] let _ = LP.parser_kind_prop_equiv k1 p1 in
      begin
        LowStar.Comment.comment ("Validating field " ^ name1);
        [@(rename_let ("" ^ name1))]
        let field_value = r1 input startPosition in
        [@(rename_let (name1 ^ "ConstraintIsOk"))]
        let ok = f field_value in
        [@(rename_let ("positionAfter" ^ name1))]
        let res1 = LPE.check_constraint_ok ok startPosition in
        if LPE.is_error res1
        then res1
        else let h2 = HST.get() in
             // assert (B.modifies B.loc_none h1 h2);
             // assert (inv1' input.LPL.base h2);
             modifies_address_liveness_insensitive_unused_in h0 h2;
             // assert (loc_not_unused_in h2 `loc_includes` l1');
             // assert (valid_pos (p1 `(LPC.parse_filter #k1 #t1)` f) h0 input (uint64_to_uint32 pos) (uint64_to_uint32 res));
             let h15 = HST.get () in
             let _ = modifies_address_liveness_insensitive_unused_in h0 h15 in
             validate_drop (v2 field_value) ctxt err input input_length res1
        end

inline_for_extraction noextract
let validate_dep_pair_with_refinement
      (p1_is_constant_size_without_actions: bool)
      (name1: string)
      #nz1 (#k1:parser_kind nz1 _) #t1 (#p1:parser k1 t1)
      #inv1 #l1 (v1:validate_with_action_t p1 inv1 l1 true) (r1: leaf_reader p1)
      (f: t1 -> bool)
      #nz2 #wk2 (#k2:parser_kind nz2 wk2) (#t2:refine _ f -> Type) (#p2:(x:refine _ f -> parser k2 (t2 x)))
      #inv2 #l2 #ar2 (v2:(x:refine _ f -> validate_with_action_t (p2 x) inv2 l2 ar2))
  : Tot (validate_with_action_t ((p1 `parse_filter` f) `parse_dep_pair` p2)
                                (conj_inv inv1 inv2)
                                (l1 `eloc_union` l2)
                                false)
  = if
      p1_is_constant_size_without_actions `LP.bool_and`
      (k1.LP.parser_kind_high = Some 0) `LP.bool_and`
      (k1.LP.parser_kind_metadata = Some LP.ParserKindMetadataTotal)
    then
      validate_dep_pair_with_refinement_total_zero_parser' name1 inv1 l1 r1 f v2
    else
      validate_dep_pair_with_refinement' name1 v1 r1 f v2

inline_for_extraction noextract
let validate_filter (name: string) #nz (#k:parser_kind nz _) (#t:_) (#p:parser k t)
                    #inv #l (v:validate_with_action_t p inv l true)
                    (r:leaf_reader p) (f:t -> bool) (cr:string) (cf:string)
  : Tot (validate_with_action_t #nz #WeakKindStrongPrefix (p `LPC.parse_filter` f) inv l false)
  = fun ctxt err input input_length start_position ->
    [@inline_let] let pos = start_position in
    let h = HST.get () in
    LPC.parse_filter_eq p f (I.get_remaining input h);
    [@(rename_let ("positionAfter" ^ name))]
    let res = v ctxt err input input_length pos in
    let h1 = HST.get () in
    if LPE.is_error res
    then res
    else begin
      LowStar.Comment.comment cr;
      [@(rename_let ("" ^ name))]
      let field_value = r input pos in
      LowStar.Comment.comment (normalize_term ("start: " ^cf));
      [@(rename_let (name ^ "ConstraintIsOk"))]
      let ok = f field_value in
      LowStar.Comment.comment (normalize_term ("end: " ^ cf));
      LPE.check_constraint_ok ok res
    end

inline_for_extraction noextract
let validate_filter_with_action
                    (name: string) #nz (#k:parser_kind nz _) (#t:_) (#p:parser k t)
                    #inv #l (v:validate_with_action_t p inv l true)
                    (r:leaf_reader p) (f:t -> bool) (cr:string) (cf:string)
                    (#b:bool) #inva (#la:eloc) (a: t -> action #nz #WeakKindStrongPrefix #(filter_kind k) #_ (p `LPC.parse_filter` f) inva la b bool)
  : Tot (validate_with_action_t #nz #WeakKindStrongPrefix (p `LPC.parse_filter` f) (conj_inv inv inva) (eloc_union l la) false)
  = fun ctxt err input input_length start_position ->
    [@inline_let] let pos0 = start_position in
    let h = HST.get () in
    LPC.parse_filter_eq p f (I.get_remaining input h);
    [@(rename_let ("positionAfter" ^ name))]
    let res = v ctxt err input input_length pos0 in
    let h1 = HST.get () in
    if LPE.is_error res
    then res
    else begin
      LowStar.Comment.comment cr;
      [@(rename_let ("" ^ name))]
      let field_value = r input pos0 in
      LowStar.Comment.comment (normalize_term ("start: " ^cf));
      [@(rename_let (name ^ "ConstraintIsOk"))]
      let ok = f field_value in
      LowStar.Comment.comment (normalize_term ("end: " ^ cf));
      if ok
        then let h15 = HST.get () in
             let _ = modifies_address_liveness_insensitive_unused_in h h15 in
             if a field_value ctxt input pos0 res
             then res
             else LPE.set_validator_error_pos LPE.validator_error_action_failed res
      else LPE.set_validator_error_pos LPE.validator_error_constraint_failed res
    end

inline_for_extraction noextract
let validate_with_dep_action
                    (name: string) #nz (#k:parser_kind nz _) (#t:_) (#p:parser k t)
                    #inv #l (v:validate_with_action_t p inv l true)
                    (r:leaf_reader p)
                    (#b:bool) #inva (#la:eloc) (a: t -> action p inva la b bool)
  : Tot (validate_with_action_t #nz p (conj_inv inv inva) (eloc_union l la) false)
  = fun ctxt err input input_length start_position ->
    [@inline_let] let pos0 = start_position in
    let h = HST.get () in
    [@(rename_let ("positionAfter" ^ name))]
    let res = v ctxt err input input_length pos0 in
    let h1 = HST.get () in
    if LPE.is_error res
    then res
    else begin
      [@(rename_let ("" ^ name))]
      let field_value = r input pos0 in
      let h15 = HST.get () in
      let _ = modifies_address_liveness_insensitive_unused_in h h15 in
      if a field_value ctxt input pos0 res
      then res
      else LPE.set_validator_error_pos LPE.validator_error_action_failed res
    end

inline_for_extraction noextract
let validate_weaken #nz #wk (#k:parser_kind nz wk) #t (#p:parser k t)
                    #inv #l #ar (v:validate_with_action_t p inv l ar)
                    #nz' #wk' (k':parser_kind nz' wk'{k' `is_weaker_than` k})
  : Tot (validate_with_action_t (parse_weaken p k') inv l ar)
  = fun ctxt err input input_length start_position ->
    v ctxt err input input_length start_position


/// Parser: weakening kinds

inline_for_extraction noextract
let validate_weaken_left (#nz:_) #wk (#k:parser_kind nz wk) (#t:_) (#p:parser k t)
                         (#inv:_) (#l:_) #ar (v:validate_with_action_t p inv l ar)
                         (#nz':_) #wk' (k':parser_kind nz' wk')
  : validate_with_action_t (parse_weaken_left p k') inv l ar
  = validate_weaken v (glb k' k)

/// Parser: weakening kinds

inline_for_extraction noextract
let validate_weaken_right (#nz:_) #wk (#k:parser_kind nz wk) (#t:_) (#p:parser k t)
                         (#inv:_) (#l:_) #ar (v:validate_with_action_t p inv l ar)
                         (#nz':_) #wk' (k':parser_kind nz' wk')
  : validate_with_action_t (parse_weaken_right p k') inv l ar
  = validate_weaken v (glb k k')

inline_for_extraction noextract
let validate_impos ()
  : Tot (validate_with_action_t (parse_impos ()) true_inv eloc_none true)
  = fun _ _ _ _ start_position -> LPE.set_validator_error_pos LPE.validator_error_impossible start_position

noextract inline_for_extraction
let validate_ite
  e p1 v1 p2 v2
  = fun ctxt err input input_len start_position ->
      if e 
      then validate_drop (v1 ()) ctxt err input input_len start_position
      else validate_drop (v2 ()) ctxt err input input_len start_position

module LPLL = LowParse.Spec.List

unfold
let validate_list_inv
  (#k: LPL.parser_kind)
  (#t: Type)
  (p: LPL.parser k t)
  (inv: slice_inv)
  (l: eloc)
  (g0 g1: Ghost.erased HS.mem)
  (ctxt:app_ctxt)
  (sl: input_buffer_t)
  (bres: pointer U64.t)
  (h: HS.mem)
  (stop: bool)
: GTot Type0
= let h0 = Ghost.reveal g0 in
  let h1 = Ghost.reveal g1 in
  let res = Seq.index (as_seq h bres) 0 in
  inv (I.footprint sl) h0 /\
  loc_not_unused_in h0 `loc_includes` app_loc ctxt l /\
  app_loc ctxt l `loc_disjoint` I.footprint sl /\
  app_loc ctxt l `loc_disjoint` loc_buffer bres /\
  address_liveness_insensitive_locs `loc_includes` app_loc ctxt l /\
  B.loc_buffer bres `B.loc_disjoint` I.footprint sl /\
  I.live sl h0 /\
  I.live sl h /\
  live h0 ctxt /\
  live h ctxt /\
  live h1 bres /\
  begin
    let s = I.get_remaining sl h0 in
    let s' = I.get_remaining sl h in
    Seq.length s' <= Seq.length s /\
    s' `Seq.equal` Seq.slice s (Seq.length s - Seq.length s') (Seq.length s)
  end /\
  modifies loc_none h0 h1 /\ (
  if
    LPE.is_error res
  then
    // validation *or action* failed
    stop == true /\
    U64.v (LPE.get_validator_error_pos res) == Seq.length (I.get_read sl h) /\
    (LPE.get_validator_error_kind res <> LPE.get_validator_error_kind LPE.validator_error_action_failed ==> ~ (valid (LPLL.parse_list p) h0 sl))
  else
    U64.v res == Seq.length (I.get_read sl h) /\
    (valid (LPLL.parse_list p) h0 sl <==>
     valid (LPLL.parse_list p) h sl) /\
    (stop == true ==> (valid (LPLL.parse_list p) h sl /\ Seq.length (I.get_remaining sl h) == 0))
  ) /\
  modifies (app_loc ctxt l `loc_union` loc_buffer bres `loc_union` I.perm_footprint sl) h1 h

inline_for_extraction
noextract
let validate_list_body
  (# [FStar.Tactics.Typeclasses.tcresolve ()] _extra_t : I.extra_t #input_buffer_t ) 
  (#k:LP.parser_kind)
  #t
  (#p:LP.parser k t)
  #inv #l #ar
  (v: validate_with_action_t' p inv l ar)
  (g0 g1: Ghost.erased HS.mem)
  (ctxt:app_ctxt)
  (err:error_handler)
  (sl: input_buffer_t)
  (sl_len: I.tlen sl)
  (bres: pointer U64.t)
: HST.Stack bool
  (requires (fun h -> validate_list_inv p inv l g0 g1 ctxt sl bres h false))
  (ensures (fun h res h' ->
    validate_list_inv p inv l g0 g1 ctxt sl bres h false /\
    validate_list_inv p inv l g0 g1 ctxt sl bres h' res
  ))
=
  let h = HST.get () in
  LPLL.parse_list_eq p (I.get_remaining sl h);
  let position = !* bres in
  if not (I.has sl sl_len position 1uL)
  then true
  else begin
    let h1 = HST.get () in
    modifies_address_liveness_insensitive_unused_in (Ghost.reveal g0) h1;
    let result = validate_drop v ctxt err sl sl_len position in
    upd bres 0ul result;
    LPE.is_error result
  end

inline_for_extraction
noextract
let validate_list'
  (# [FStar.Tactics.Typeclasses.tcresolve ()] _extra_t : I.extra_t #input_buffer_t ) 
  (#k:LP.parser_kind)
  #t
  (#p:LP.parser k t)
  #inv #l #ar
  (v: validate_with_action_t' p inv l ar)
  (ctxt: app_ctxt)
  (err: error_handler)
  (sl: input_buffer_t)
  (sl_len: I.tlen sl)
  (pos: LPE.pos_t)
: HST.Stack U64.t
  (requires (fun h ->
    inv (I.footprint sl) h /\
    loc_not_unused_in h `loc_includes` app_loc ctxt l /\
    app_loc ctxt l `loc_disjoint` I.footprint sl /\
    address_liveness_insensitive_locs `loc_includes` app_loc ctxt l /\
    B.live h ctxt /\
    I.live sl h /\
    U64.v pos == Seq.length (I.get_read sl h)
  ))
  (ensures (fun h res h' ->
    let s = I.get_remaining sl h in
    inv (I.footprint sl) h' /\
    B.live h' ctxt /\
    I.live sl h' /\
    begin
      let s' = I.get_remaining sl h' in
      Seq.length s' <= Seq.length s /\
      s' `Seq.equal` Seq.slice s (Seq.length s - Seq.length s') (Seq.length s)
    end /\
    begin match LP.parse (LPLL.parse_list p) s with
    | None -> LPE.is_success res == false
    | Some (_, len) ->
      if LPE.is_success res
      then I.get_remaining sl h' `Seq.equal` Seq.slice s len (Seq.length s) /\ U64.v res == Seq.length (I.get_read sl h')
      else LPE.get_validator_error_kind res == LPE.get_validator_error_kind LPE.validator_error_action_failed
    end /\
    (LPE.is_success res == false ==> U64.v (LPE.get_validator_error_pos res) == Seq.length (I.get_read sl h')) /\
    modifies (app_loc ctxt l `B.loc_union` I.perm_footprint sl) h h'
  ))
= let h0 = HST.get () in
  let g0 = Ghost.hide h0 in
  HST.push_frame ();
  let h02 = HST.get () in
  fresh_frame_modifies h0 h02;
  let result = alloca pos 1ul in
  let h1 = HST.get () in
  let g1 = Ghost.hide h1 in
  I.live_not_unused_in sl h0;
  C.Loops.do_while (validate_list_inv p inv l g0 g1 ctxt sl result) (fun _ -> validate_list_body v g0 g1 ctxt err sl sl_len result);
  let finalResult = index result 0ul in
  let h2 = HST.get () in
  HST.pop_frame ();
  let h' = HST.get () in
  assert (B.modifies (app_loc ctxt l `B.loc_union` I.perm_footprint sl) h0 h');
  LP.parser_kind_prop_equiv LPLL.parse_list_kind (LPLL.parse_list p);
  finalResult

inline_for_extraction
noextract
let validate_list
  (#k:LP.parser_kind)
  #t
  (#p:LP.parser k t)
  #inv #l #ar
  (v: validate_with_action_t' p inv l ar)
: Tot (validate_with_action_t' (LowParse.Spec.List.parse_list p) inv l false)
= fun ctxt err input input_length start_position ->
  validate_list' v ctxt err input input_length start_position

#push-options "--z3rlimit 32"
#restart-solver

module LPLF = LowParse.Low.FLData

noextract
inline_for_extraction
let validate_fldata_consumes_all
  (n:U32.t)
  (#k: LP.parser_kind)
  #t
  (#p: LP.parser k t)
  #inv #l #ar
  (v: validate_with_action_t' p inv l ar  { k.LP.parser_kind_subkind == Some LP.ParserConsumesAll })
: Tot (validate_with_action_t' (LowParse.Spec.FLData.parse_fldata p (U32.v n)) inv l false)
= fun ctxt err input input_length start_position ->
  [@inline_let] let pos = start_position in
  let h = HST.get () in
  LPLF.parse_fldata_consumes_all_correct p (U32.v n) (I.get_remaining input h);
  let hasEnoughBytes = I.has input input_length pos (Cast.uint32_to_uint64 n) in
  let h1 = HST.get () in
  modifies_address_liveness_insensitive_unused_in h h1;
  if not hasEnoughBytes
  then LPE.set_validator_error_pos LPE.validator_error_not_enough_data pos
  else begin
    let truncatedInput = I.truncate input pos (Cast.uint32_to_uint64 n) in
    let truncatedInputLength = I.truncate_len input pos (Cast.uint32_to_uint64 n) truncatedInput in
    let h2 = HST.get () in
    modifies_address_liveness_insensitive_unused_in h h2;
    I.is_prefix_of_prop truncatedInput input h2;
    assert (I.get_remaining truncatedInput h2 `Seq.equal` Seq.slice (I.get_remaining input h) 0 (U32.v n));
    let res = validate_drop v ctxt err truncatedInput truncatedInputLength pos in
    let h3 = HST.get () in
    I.is_prefix_of_prop truncatedInput input h3;
    res
  end

#pop-options

#push-options "--z3rlimit_factor 16 --z3cliopt smt.arith.nl=false"
#restart-solver

noextract
inline_for_extraction
let validate_fldata
  (n:U32.t)
  (#k: LP.parser_kind)
  #t
  (#p: LP.parser k t)
  #inv #l #ar
  (v: validate_with_action_t' p inv l ar)
: Tot (validate_with_action_t' (LowParse.Spec.FLData.parse_fldata p (U32.v n)) inv l false)
= fun ctxt err input input_length start_position ->
  [@inline_let] let pos = start_position in
  let h = HST.get () in
  let hasEnoughBytes = I.has input input_length pos (Cast.uint32_to_uint64 n) in
  let h1 = HST.get () in
  modifies_address_liveness_insensitive_unused_in h h1;
  if not hasEnoughBytes
  then LPE.set_validator_error_pos LPE.validator_error_not_enough_data pos
  else begin
    let truncatedInput = I.truncate input pos (Cast.uint32_to_uint64 n) in
    let truncatedInputLength = I.truncate_len input pos (Cast.uint32_to_uint64 n) truncatedInput in
    let h2 = HST.get () in
    modifies_address_liveness_insensitive_unused_in h h2;
    I.is_prefix_of_prop truncatedInput input h2;
    assert (I.get_remaining truncatedInput h2 `Seq.equal` Seq.slice (I.get_remaining input h) 0 (U32.v n));
    let res = validate_drop v ctxt err truncatedInput truncatedInputLength pos in
    let h3 = HST.get () in
    modifies_address_liveness_insensitive_unused_in h h3;
    I.is_prefix_of_prop truncatedInput input h3;
    if LPE.is_error res
    then res
    else begin
      let stillHasBytes = I.has truncatedInput truncatedInputLength res 1uL in
      let h4 = HST.get () in
      modifies_address_liveness_insensitive_unused_in h h4;
      if stillHasBytes
      then LPE.set_validator_error_pos LPE.validator_error_unexpected_padding res
      else res
    end
  end

#pop-options

noextract
inline_for_extraction
let validate_nlist
  (n:U32.t)
  #wk
  (#k:parser_kind true wk)
  #t
  (#p:parser k t)
  #inv #l #ar
  (v: validate_with_action_t p inv l ar)
: Tot (validate_with_action_t (parse_nlist n p) inv l false)
= validate_weaken
    #false #WeakKindStrongPrefix #(LowParse.Spec.FLData.parse_fldata_kind (U32.v n) LowParse.Spec.List.parse_list_kind) #(list t)
    (validate_fldata_consumes_all n (validate_list v))
    kind_nlist

inline_for_extraction
noextract
let validate_total_constant_size_no_read'
  (#k: LP.parser_kind)
  (#t: Type)
  (p: LP.parser k t)
  (sz: U64.t)
  (u: unit {
    k.LP.parser_kind_high == Some k.LP.parser_kind_low /\
    k.LP.parser_kind_low == U64.v sz /\
    k.LP.parser_kind_metadata == Some LP.ParserKindMetadataTotal
  })
  inv l
: Tot (validate_with_action_t' p inv l true)
= fun ctxt err input input_length start_position ->
  [@inline_let] let pos = start_position in
  let h = HST.get () in
  LP.parser_kind_prop_equiv k p; 
  let hasBytes = I.has input input_length pos sz in
  let h2 = HST.get () in
  modifies_address_liveness_insensitive_unused_in h h2;
  if hasBytes
  then pos `U64.add` sz
  else LPE.set_validator_error_pos LPE.validator_error_not_enough_data pos

inline_for_extraction
noextract
let validate_total_constant_size_no_read
  #nz #wk
  (#k: parser_kind nz wk)
  (#t: Type)
  (p: parser k t)
  (sz: U64.t)
  (u: unit {
    k.LP.parser_kind_high == Some k.LP.parser_kind_low /\
    k.LP.parser_kind_low == U64.v sz /\
    k.LP.parser_kind_metadata == Some LP.ParserKindMetadataTotal
  })
  inv l
: Tot (validate_with_action_t p inv l true)
= validate_total_constant_size_no_read' p sz u inv l

inline_for_extraction noextract
let validate_nlist_total_constant_size_mod_ok (n:U32.t) #wk (#k:parser_kind true wk) (#t: Type) (p:parser k t) inv l
  : Pure (validate_with_action_t (parse_nlist n p) inv l true)
  (requires (
    let open LP in
    k.parser_kind_subkind == Some ParserStrong /\
    k.parser_kind_high == Some k.parser_kind_low /\
    k.parser_kind_metadata == Some ParserKindMetadataTotal /\
    k.parser_kind_low < 4294967296 /\
    U32.v n % k.LP.parser_kind_low == 0
  ))
  (ensures (fun _ -> True))
= [@inline_let]
  let _ =
    parse_nlist_total_fixed_size_kind_correct n p
  in
  validate_total_constant_size_no_read' (LP.strengthen (LP.total_constant_size_parser_kind (U32.v n)) (parse_nlist n p)) (Cast.uint32_to_uint64 n) () inv l

inline_for_extraction noextract
let validate_nlist_constant_size_mod_ko (n:U32.t) (#wk: _) (#k:parser_kind true wk) #t (p:parser k t) inv l
  : Pure (validate_with_action_t (parse_nlist n p) inv l true)
  (requires (
    let open LP in
    k.parser_kind_subkind == Some ParserStrong /\
    k.parser_kind_high == Some k.parser_kind_low /\
    U32.v n % k.LP.parser_kind_low <> 0
  ))
  (ensures (fun _ -> True))
= 
  (fun ctxt err input input_length start_position ->
     [@inline_let] let pos = start_position in
     let h = FStar.HyperStack.ST.get () in
     [@inline_let]
     let f () : Lemma
       (requires (Some? (LP.parse (parse_nlist n p) (I.get_remaining input h))))
       (ensures False)
     = let sq = I.get_remaining input h in
       let sq' = Seq.slice sq 0 (U32.v n) in
       LowParse.Spec.List.list_length_constant_size_parser_correct p sq' ;
       let Some (l, _) = LP.parse (parse_nlist n p) sq in
       assert (U32.v n == FStar.List.Tot.length l `Prims.op_Multiply` k.LP.parser_kind_low) ;
       FStar.Math.Lemmas.cancel_mul_mod (FStar.List.Tot.length l) k.LP.parser_kind_low ;
       assert (U32.v n % k.LP.parser_kind_low == 0)
     in
     [@inline_let]
     let _ = Classical.move_requires f () in
     LPE.set_validator_error_pos LPE.validator_error_list_size_not_multiple pos
  )

inline_for_extraction noextract
let validate_nlist_total_constant_size' (n:U32.t) #wk (#k:parser_kind true wk) #t (p:parser k t) inv l
  : Pure (validate_with_action_t (parse_nlist n p) inv l true)
  (requires (
    let open LP in
    k.parser_kind_subkind == Some ParserStrong /\
    k.parser_kind_high == Some k.parser_kind_low /\
    k.parser_kind_metadata == Some ParserKindMetadataTotal /\
    k.parser_kind_low < 4294967296
  ))
  (ensures (fun _ -> True))
= fun ctxt err input start_position -> // n is not an integer constant, so we need to eta-expand and swap fun and if
  if n `U32.rem` U32.uint_to_t k.LP.parser_kind_low = 0ul
  then validate_nlist_total_constant_size_mod_ok n p inv l ctxt err input start_position
  else validate_nlist_constant_size_mod_ko n p inv l ctxt err input start_position

inline_for_extraction noextract
let validate_nlist_total_constant_size (n_is_const: bool) (n:U32.t) #wk (#k:parser_kind true wk) (#t: Type) (p:parser k t) inv l
: Pure (validate_with_action_t (parse_nlist n p) inv l true)
  (requires (
    let open LP in
    k.parser_kind_subkind = Some ParserStrong /\
    k.parser_kind_high = Some k.parser_kind_low /\
    k.parser_kind_metadata = Some ParserKindMetadataTotal /\
    k.parser_kind_low < 4294967296
  ))
  (ensures (fun _ -> True))
=
  if
    if k.LP.parser_kind_low = 1
    then true
    else if n_is_const
    then U32.v n % k.LP.parser_kind_low = 0
    else false
  then
    validate_nlist_total_constant_size_mod_ok n p inv l
  else if
    if n_is_const
    then U32.v n % k.LP.parser_kind_low <> 0
    else false
  then
    validate_nlist_constant_size_mod_ko n p inv l
  else
    validate_nlist_total_constant_size' n p inv l

noextract
inline_for_extraction
let validate_nlist_constant_size_without_actions
  (n_is_const: bool)
  (n:U32.t)
  #wk
  (#k:parser_kind true wk)
  #t (#p:parser k t) #inv #l #ar
  (v: validate_with_action_t p inv l ar)
: Tot (validate_with_action_t (parse_nlist n p) inv l false)
= 
  if
    let open LP in
    k.parser_kind_subkind = Some ParserStrong &&
    k.parser_kind_high = Some k.parser_kind_low &&
    k.parser_kind_metadata = Some ParserKindMetadataTotal &&
    k.parser_kind_low < 4294967296
  then
    validate_drop (validate_nlist_total_constant_size n_is_const n p inv l)
  else
    validate_nlist n v

#push-options "--z3rlimit_factor 16 --z3cliopt smt.arith.nl=false"
#restart-solver

noextract inline_for_extraction
let validate_t_at_most (n:U32.t) #nz #wk (#k:parser_kind nz wk) (#t:_) (#p:parser k t)
                       (#inv:_) (#l:_) (#ar:_) (v:validate_with_action_t p inv l ar)
  : Tot (validate_with_action_t (parse_t_at_most n p) inv l false)
  = fun ctxt err input input_length start_position ->
    [@inline_let] let pos = start_position in
    let h = HST.get () in
    let hasBytes = I.has input input_length pos (Cast.uint32_to_uint64 n) in
    let h1 = HST.get () in
    modifies_address_liveness_insensitive_unused_in h h1;
    if not hasBytes
    then
      LPE.set_validator_error_pos LPE.validator_error_not_enough_data pos
    else
      let truncatedInput = I.truncate input pos (Cast.uint32_to_uint64 n) in
      let truncatedInputLength = I.truncate_len input pos (Cast.uint32_to_uint64 n) truncatedInput in
      let h2 = HST.get () in
      let _ = modifies_address_liveness_insensitive_unused_in h h2 in
      let _ = I.is_prefix_of_prop truncatedInput input h2 in
      let _ = assert (I.get_remaining truncatedInput h2 `Seq.equal` Seq.slice (I.get_remaining input h) 0 (U32.v n)) in
      [@inline_let] let _ = LPC.nondep_then_eq p parse_all_bytes (I.get_remaining truncatedInput h2) in
      let result = validate_drop v ctxt err truncatedInput truncatedInputLength pos in
      let h3 = HST.get () in
      let _ = I.is_prefix_of_prop truncatedInput input h3 in
      if LPE.is_error result
      then result
      else begin
        let _ = I.empty truncatedInput truncatedInputLength result in
        let h4 = HST.get () in
        modifies_address_liveness_insensitive_unused_in h h4;
        let _ = I.is_prefix_of_prop truncatedInput input h4 in
        pos `U64.add` Cast.uint32_to_uint64 n
      end

#pop-options

#push-options "--z3rlimit 128 --z3cliopt smt.arith.nl=false"
#restart-solver

noextract inline_for_extraction
let validate_t_exact (n:U32.t) #nz #wk (#k:parser_kind nz wk) (#t:_) (#p:parser k t)
                       (#inv:_) (#l:_) (#ar:_) (v:validate_with_action_t p inv l ar)
  : Tot (validate_with_action_t (parse_t_exact n p) inv l false)
  = fun ctxt err input input_length start_position ->
    [@inline_let] let pos = start_position in
    let h = HST.get () in
    let hasBytes = I.has input input_length pos (Cast.uint32_to_uint64 n) in
    let h1 = HST.get () in
    modifies_address_liveness_insensitive_unused_in h h1;
    if not hasBytes
    then
      LPE.set_validator_error_pos LPE.validator_error_not_enough_data pos
    else
      let truncatedInput = I.truncate input pos (Cast.uint32_to_uint64 n) in
      let truncatedInputLength = I.truncate_len input pos (Cast.uint32_to_uint64 n) truncatedInput in
      let h2 = HST.get () in
      let _ = modifies_address_liveness_insensitive_unused_in h h2 in
      let _ = I.is_prefix_of_prop truncatedInput input h2 in
      let _ = assert (I.get_remaining truncatedInput h2 `Seq.equal` Seq.slice (I.get_remaining input h) 0 (U32.v n)) in
      [@inline_let] let _ = LPC.nondep_then_eq p parse_all_bytes (I.get_remaining truncatedInput h2) in
      let result = validate_drop v ctxt err truncatedInput truncatedInputLength pos in
      let h3 = HST.get () in
      let _ = I.is_prefix_of_prop truncatedInput input h3 in
      if LPE.is_error result
      then result
      else begin
        let stillHasBytes = I.has truncatedInput truncatedInputLength result 1uL in
        let h4 = HST.get () in
        modifies_address_liveness_insensitive_unused_in h h4;
        I.is_prefix_of_prop truncatedInput input h4;
        if stillHasBytes
        then LPE.set_validator_error_pos LPE.validator_error_unexpected_padding result
        else result
      end

#pop-options

inline_for_extraction noextract
let validate_with_comment (c:string)
                          #nz #wk (#k:parser_kind nz wk) #t (#p:parser k t)
                          #inv #l #ar (v:validate_with_action_t p inv l ar)
  : validate_with_action_t p inv l ar
  = fun ctxt err input input_length start_position ->
    LowParse.Low.Base.comment c;
    v ctxt err input input_length start_position

inline_for_extraction noextract
let validate_weaken_inv_loc #nz #wk (#k:parser_kind nz wk) #t (#p:parser k t)
                            #inv (#l:eloc) #ar
                            (inv':slice_inv{inv' `inv_implies` inv}) (l':eloc{l' `eloc_includes` l})
                            (v:validate_with_action_t p inv l ar)
  : Tot (validate_with_action_t p inv' l' ar)
  = v


////////////////////////////////////////////////////////////////////////////////
//Base types
////////////////////////////////////////////////////////////////////////////////
inline_for_extraction noextract
let read_filter #nz
                (#k: parser_kind nz WeakKindStrongPrefix)
                (#t: Type)
                (#p: parser k t)
                (p32: leaf_reader p)
                (f: (t -> bool))
    : leaf_reader (parse_filter p f)
    = fun input pos ->
        let h = HST.get () in
        assert (parse_filter p f == LPC.parse_filter #k #t p f);
        assert_norm (P.refine t f == LPC.parse_filter_refine f);
        LPC.parse_filter_eq p f (I.get_remaining input h);
        p32 input pos

inline_for_extraction noextract
let read_impos 
  : leaf_reader (parse_impos())
  = fun sl pos -> 
      false_elim ()

inline_for_extraction noextract
let validate____UINT8
  : validator parse____UINT8
  = validate_with_comment
      "Checking that we have enough space for a UINT8, i.e., 1 byte"
      (validate_total_constant_size_no_read parse____UINT8 1uL () _ _)

inline_for_extraction noextract
let lift_reader
  (#nz: _)
  (#k: parser_kind nz WeakKindStrongPrefix)
  (#t: _)
  (p: parser k t)
  (r: LPL.leaf_reader p)
  (sz32: U32.t)
  (sz: U64.t)
: Pure (leaf_reader p)
  (requires (
    U32.v sz32 == U64.v sz /\
    U64.v sz > 0 /\
    k.LP.parser_kind_subkind == Some LP.ParserStrong /\
    k.LP.parser_kind_high == Some k.LP.parser_kind_low /\
    k.LP.parser_kind_low = U64.v sz
  ))
  (ensures (fun _ -> True))
= fun input pos ->
  LP.parser_kind_prop_equiv k p;
  I.read t k p r input pos sz

inline_for_extraction noextract
let read____UINT8
  : leaf_reader parse____UINT8
= lift_reader _ LowParse.Low.Int.read_u8 1ul 1uL

inline_for_extraction noextract
let validate____UINT16BE
  : validator parse____UINT16BE
  = validate_with_comment
      "Checking that we have enough space for a UINT16BE, i.e., 2 bytes"
      (validate_total_constant_size_no_read parse____UINT16BE 2uL () _ _)

inline_for_extraction noextract
let read____UINT16BE
  : leaf_reader parse____UINT16BE
= lift_reader _ LowParse.Low.Int.read_u16 2ul 2uL

inline_for_extraction noextract
let validate____UINT32BE
  : validator parse____UINT32BE
  = validate_with_comment
      "Checking that we have enough space for a UINT32BE, i.e., 4 bytes"
      (validate_total_constant_size_no_read parse____UINT32BE 4uL () _ _)

inline_for_extraction noextract
let read____UINT32BE
  : leaf_reader parse____UINT32BE
= lift_reader _ LowParse.Low.Int.read_u32 4ul 4uL

inline_for_extraction noextract
let validate____UINT64BE
  : validator parse____UINT64BE
  = validate_with_comment
      "Checking that we have enough space for a UINT64BE, i.e., 8 bytes"
      (validate_total_constant_size_no_read parse____UINT64BE 8uL () _ _)

inline_for_extraction noextract
let read____UINT64BE
  : leaf_reader parse____UINT64BE
= lift_reader _ LowParse.Low.Int.read_u64 8ul 8uL

inline_for_extraction noextract
let validate____UINT16
  : validator parse____UINT16
  = validate_with_comment
      "Checking that we have enough space for a UINT16, i.e., 2 bytes"
      (validate_total_constant_size_no_read parse____UINT16 2uL () _ _)

inline_for_extraction noextract
let read____UINT16
  : leaf_reader parse____UINT16
= lift_reader _ LowParse.Low.BoundedInt.read_u16_le 2ul 2uL

inline_for_extraction noextract
let validate____UINT32
  : validator parse____UINT32
  = validate_with_comment
      "Checking that we have enough space for a UINT32, i.e., 4 bytes"
      (validate_total_constant_size_no_read parse____UINT32 4uL () _ _)

inline_for_extraction noextract
let read____UINT32
  : leaf_reader parse____UINT32
= lift_reader _ LowParse.Low.BoundedInt.read_u32_le 4ul 4uL

inline_for_extraction noextract
let validate____UINT64
  : validator parse____UINT64
  = validate_with_comment
      "Checking that we have enough space for a UINT64, i.e., 8 bytes"
      (validate_total_constant_size_no_read parse____UINT64 8uL () _ _)

inline_for_extraction noextract
let read____UINT64
  : leaf_reader parse____UINT64
= lift_reader _ LowParse.Low.Int.read_u64_le 8ul 8uL

inline_for_extraction noextract
let validate_unit
= fun _ _ input _ start_position -> start_position

inline_for_extraction noextract
let read_unit
= fun input pos -> ()

inline_for_extraction noextract
let validate_unit_refinement (f:unit -> bool) (cf:string)
  : validator (parse_unit `parse_filter` f)
= fun _ _ input _ start_position ->
    [@inline_let] let pos = start_position in
    let h = HST.get () in
    LPC.parse_filter_eq parse_unit f (I.get_remaining input h);
    LowStar.Comment.comment cf;
    if f ()
    then pos
    else LPE.set_validator_error_pos LPE.validator_error_constraint_failed pos


(* Reimplement validate_list_up_to with readability (but no actions) *)

module LUT = LowParse.Low.ListUpTo

unfold
let validate_list_up_to_inv
  (#k: parser_kind true WeakKindStrongPrefix)
  (#t: eqtype)
  (p: parser k t)
  (terminator: t)
  (prf: LUT.consumes_if_not_cond (cond_string_up_to terminator) p)
  (ctxt: app_ctxt)
  (sl: input_buffer_t)
  (h0: HS.mem)
  (bres: B.pointer U64.t)
  (h: HS.mem)
  (stop: bool)
: GTot Type0
=
  let res = B.deref h bres in
  let q = LUT.parse_list_up_to (cond_string_up_to terminator) p prf in
  B.live h0 bres /\
  I.live sl h0 /\
  I.live sl h /\
  B.loc_disjoint (I.footprint sl) (B.loc_buffer bres `B.loc_union` app_loc ctxt loc_none) /\
  B.loc_disjoint (B.loc_buffer bres) (app_loc ctxt loc_none) /\
  B.live h0 ctxt /\
  B.live h ctxt /\
  address_liveness_insensitive_locs `loc_includes` (app_loc ctxt loc_none) /\
  B.modifies (B.loc_buffer bres `B.loc_union` I.perm_footprint sl `B.loc_union` app_loc ctxt loc_none) h0 h /\
  begin
    let s = I.get_remaining sl h0 in
    let s' = I.get_remaining sl h in
    Seq.length s' <= Seq.length s /\
    s' `Seq.equal` Seq.slice s (Seq.length s - Seq.length s') (Seq.length s) /\
    begin if LPE.is_error res
    then
      // validation *or action* failed
      stop == true /\
      U64.v (LPE.get_validator_error_pos res) == Seq.length (I.get_read sl h) /\
      (LPE.get_validator_error_kind res <> LPE.get_validator_error_kind LPE.validator_error_action_failed ==> None? (LP.parse q s))
    else
    U64.v res == Seq.length (I.get_read sl h) /\
    begin if stop
    then valid_consumed q h0 h sl
    else match LP.parse q s, LP.parse q s' with
    | None, None -> True
    | Some (_, consumed), Some (_, consumed') -> consumed' + Seq.length s - Seq.length s' == consumed
    | _ -> False
    end end
  end

inline_for_extraction
let validate_list_up_to_body
  (# [FStar.Tactics.Typeclasses.tcresolve ()] _extra_t : I.extra_t #input_buffer_t ) 
  (#k: parser_kind true WeakKindStrongPrefix)
  (#t: eqtype)
  (#p: parser k t)
  (terminator: t)
  (prf: LUT.consumes_if_not_cond (cond_string_up_to terminator) p)
  (v: validator p)
  (r: leaf_reader p)
  (ctxt:app_ctxt)
  (err:error_handler)
  (sl: input_buffer_t)
  (sl_len: I.tlen sl)
  (h0: HS.mem)
  (bres: B.pointer U64.t)
: HST.Stack bool
  (requires (fun h ->
    validate_list_up_to_inv p terminator prf ctxt sl h0 bres h false
  ))
  (ensures (fun h stop h' ->
    validate_list_up_to_inv p terminator prf ctxt sl h0 bres h false /\
    validate_list_up_to_inv p terminator prf ctxt sl h0 bres h' stop
  ))
=
  let h = HST.get () in
  LUT.parse_list_up_to_eq (cond_string_up_to terminator) p prf (I.get_remaining sl h);
  let position = !* bres in
  let result = v ctxt err sl sl_len position in
  B.upd bres 0ul result;
  if LPE.is_error result
  then begin
    true
  end else begin
    let value = r sl position in
    cond_string_up_to terminator value
  end

inline_for_extraction
noextract
let validate_list_up_to
  (#k: parser_kind true WeakKindStrongPrefix)
  (#t: eqtype)
  (#p: parser k t)
  (v: validator p)
  (r: leaf_reader p)
  (terminator: t)
  (prf: LUT.consumes_if_not_cond (cond_string_up_to terminator) p)
: Tot (validate_with_action_t #true #WeakKindStrongPrefix (LUT.parse_list_up_to (cond_string_up_to terminator) p prf) true_inv eloc_none false)
=
  fun ctxt err sl sl_len pos ->
  let h0 = HST.get () in
  HST.push_frame ();
  let h1 = HST.get () in
  fresh_frame_modifies h0 h1;
  let bres = B.alloca pos 1ul in
  let h2 = HST.get () in
  I.live_not_unused_in sl h0;
  C.Loops.do_while
    (validate_list_up_to_inv p terminator prf ctxt sl h2 bres)
    (fun _ -> validate_list_up_to_body terminator prf v r ctxt err sl sl_len h2 bres)
    ;
  let result = B.index bres 0ul in
  HST.pop_frame ();
  result

let validate_string
  #k #t #p v r terminator
=
  LP.parser_kind_prop_equiv k p;
  validate_weaken (validate_list_up_to v r terminator (fun _ _ _ -> ())) _

let validate_all_bytes = fun _ _ input input_length start_position ->
  I.empty input input_length start_position

let validate_all_zeros =
  validate_list (validate_filter "parse_zeros" validate____UINT8 read____UINT8 is_zero "check if zero" "")


////////////////////////////////////////////////////////////////////////////////

noextract
inline_for_extraction
let action_return
      #nz #wk (#k:parser_kind nz wk) (#t:Type) (#p:parser k t)
      (#a:Type) (x:a)
  : action p true_inv eloc_none false a
  = fun _ _ _ _ -> x

noextract
inline_for_extraction
let action_bind
      (name: string)
      #nz #wk (#k:parser_kind nz wk) (#t:Type) (#p:parser k t)
      (#invf:slice_inv) (#lf:eloc)
      #bf (#a:Type) (f: action p invf lf bf a)
      (#invg:slice_inv) (#lg:eloc) #bg
      (#b:Type) (g: (a -> action p invg lg bg b))
  : Tot (action p (conj_inv invf invg) (eloc_union lf lg) (bf || bg) b)
  = fun ctxt input pos posf ->
    let h0 = HST.get () in
    [@(rename_let ("" ^ name))]
    let x = f ctxt input pos posf in
    let h1 = HST.get () in
    modifies_address_liveness_insensitive_unused_in h0 h1;
    g x ctxt input pos posf

noextract
inline_for_extraction
let action_seq
      #nz #wk (#k:parser_kind nz wk) (#t:Type) (#p:parser k t)
      (#invf:slice_inv) (#lf:eloc)
      #bf (#a:Type) (f: action p invf lf bf a)
      (#invg:slice_inv) (#lg:eloc) #bg
      (#b:Type) (g: action p invg lg bg b)
  : Tot (action p (conj_inv invf invg) (eloc_union lf lg) (bf || bg) b)
  = fun ctxt input pos posf ->
    let h0 = HST.get () in
    let _ = f ctxt input pos posf in
    let h1 = HST.get () in
    modifies_address_liveness_insensitive_unused_in h0 h1;
    g ctxt input pos posf

noextract
inline_for_extraction
let action_ite
      #nz #wk (#k:parser_kind nz wk) (#t:Type) (#p:parser k t)
      (#invf:slice_inv) (#lf:eloc)
      (guard:bool)
      #bf (#a:Type) (then_: squash guard -> action p invf lf bf a)
      (#invg:slice_inv) (#lg:eloc) #bg
      (else_: squash (not guard) -> action p invg lg bg a)
  : action p (conj_inv invf invg) (eloc_union lf lg) (bf || bg) a
  = fun ctxt input pos posf ->
      if guard 
      then then_ () ctxt input pos posf
      else else_ () ctxt input pos posf

noextract
inline_for_extraction
let action_abort
      #nz #wk (#k:parser_kind nz wk) (#t:Type) (#p:parser k t)
  : action p true_inv eloc_none false bool
  = fun _ _ _ _ -> false

noextract
inline_for_extraction
let action_field_pos_64
      #nz #wk (#k:parser_kind nz wk) (#t:Type) (#p:parser k t) (u:unit)
   : action p true_inv eloc_none false U64.t
   = fun _ _ pos _ -> pos

(* FIXME: this is now unsound in general (only valid for flat buffer)
noextract
inline_for_extraction
let action_field_ptr
      #nz #wk (#k:parser_kind nz wk) (#t:Type) (#p:parser k t) (u:unit)
   : action p true_inv eloc_none true LPL.puint8
   = fun input startPosition _ ->
       let open LowParse.Slice in
       LPL.offset input (LPL.uint64_to_uint32 startPosition)
*)

noextract
inline_for_extraction
let action_deref
      #nz #wk (#k:parser_kind nz wk) (#t:Type) (#p:parser k t)
      (#a:_) (x:B.pointer a)
   : action p (ptr_inv x) loc_none false a
   = fun _ _ _ _ -> !*x

noextract
inline_for_extraction
let action_assignment
      #nz #wk (#k:parser_kind nz wk) (#t:Type) (#p:parser k t)
      (#a:_) (x:B.pointer a) (v:a)
   : action p (ptr_inv x) (ptr_loc x) false unit
   = fun _ _ _ _ -> x *= v

(* FIXME: This is now unsound.
noextract
inline_for_extraction
let action_read_value
      #nz (#k:parser_kind nz) (#t:Type) (#p:parser k t)
      (r:leaf_reader p)
   : action p true_inv eloc_none true t
   = fun input startPosition endPosition ->
     r input (LPL.uint64_to_uint32 startPosition)
*)

noextract
inline_for_extraction
let action_weaken
      #nz #wk (#k:parser_kind nz wk) (#t:Type) (#p:parser k t)
      (#inv:slice_inv) (#l:eloc) (#b:_) (#a:_) (act:action p inv l b a)
      (#inv':slice_inv{inv' `inv_implies` inv}) (#l':eloc{l' `eloc_includes` l})
   : action p inv' l' b a
   = act

let external_action l =
  unit -> Stack unit (fun _ -> True) (fun h0 _ h1 -> B.modifies l h0 h1)

noextract
inline_for_extraction
let mk_external_action #_ #_ #_ #_ #_ #_ f = fun _ _ _ _ -> f ()

#pop-options
