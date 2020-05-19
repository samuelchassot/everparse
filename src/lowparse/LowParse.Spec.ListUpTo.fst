module LowParse.Spec.ListUpTo
include LowParse.Spec.Base
open LowParse.Spec.Fuel
open LowParse.Spec.Combinators

module L = FStar.List.Tot
module Seq = FStar.Seq

let negate_cond
  (#t: Type)
  (cond: (t -> Tot bool))
  (x: t)
: Tot bool
= not (cond x)

let parse_list_up_to_t
  (#t: Type)
  (cond: (t -> Tot bool))
: Tot Type0
= list (parse_filter_refine (negate_cond cond)) & parse_filter_refine cond

let llist
  (t: Type)
  (fuel: nat)
: Tot Type
= (l: list t { L.length l < fuel })

let parse_list_up_to_fuel_t
  (#t: Type)
  (cond: (t -> Tot bool))
  (fuel: nat)
: Tot Type0
= (llist (parse_filter_refine (negate_cond cond)) fuel) & parse_filter_refine cond

inline_for_extraction
let parse_list_up_to_kind (k: parser_kind) : Tot (k' : parser_kind {k' `is_weaker_than` k }) = {
  parser_kind_low = 0;
  parser_kind_high = None;
  parser_kind_subkind = k.parser_kind_subkind;
  parser_kind_metadata = None;
}

let parse_list_up_to_payload_t
  (#t: Type)
  (cond: (t -> Tot bool))
  (fuel: nat)
  (x: t)
: Tot Type0
= if cond x
  then unit
  else parse_list_up_to_fuel_t cond fuel

let synth_list_up_to_fuel
  (#t: Type)
  (cond: (t -> Tot bool))
  (fuel: nat)
  (xy: dtuple2 t (parse_list_up_to_payload_t cond fuel))
: Tot (parse_list_up_to_fuel_t cond (fuel + 1))
= let (| x, yz |) = xy in
  if cond x
  then ([], x)
  else
    let (y, z) = (yz <: parse_list_up_to_fuel_t cond fuel) in
    (x :: y, z)

let synth_list_up_to_injective
  (#t: Type)
  (cond: (t -> Tot bool))
  (fuel: nat)
: Lemma
  (synth_injective (synth_list_up_to_fuel cond fuel))
  [SMTPat (synth_injective (synth_list_up_to_fuel cond fuel))]
= ()

let parse_list_up_to_payload
  (#t: Type)
  (cond: (t -> Tot bool))
  (fuel: nat)
  (k: parser_kind { k.parser_kind_subkind <> Some ParserConsumesAll })
  (ptail: parser (parse_list_up_to_kind k) (parse_list_up_to_fuel_t cond fuel))
  (x: t)
: Tot (parser (parse_list_up_to_kind k) (parse_list_up_to_payload_t cond fuel x))
= if cond x
  then weaken (parse_list_up_to_kind k) (parse_ret ())
  else ptail

let rec parse_list_up_to_fuel
  (#k: parser_kind)
  (#t: Type)
  (cond: (t -> Tot bool))
  (p: parser k t { k.parser_kind_subkind <> Some ParserConsumesAll })
  (fuel: nat)
: Tot (parser (parse_list_up_to_kind k) (parse_list_up_to_fuel_t cond fuel))
  (decreases fuel)
= if fuel = 0
  then fail_parser (parse_list_up_to_kind k) (parse_list_up_to_fuel_t cond fuel)
  else
    parse_dtuple2
      (weaken (parse_list_up_to_kind k) p)
      #(parse_list_up_to_kind k)
      #(parse_list_up_to_payload_t cond (fuel - 1))
      (parse_list_up_to_payload cond (fuel - 1) k (parse_list_up_to_fuel cond p (fuel - 1)))
      `parse_synth`
      synth_list_up_to_fuel cond (fuel - 1)

let parse_list_up_to_fuel_eq
  (#k: parser_kind)
  (#t: Type)
  (cond: (t -> Tot bool))
  (p: parser k t { k.parser_kind_subkind <> Some ParserConsumesAll })
  (fuel: nat)
  (b: bytes)
: Lemma
  (parse (parse_list_up_to_fuel cond p fuel) b == (
    if fuel = 0
    then None
    else match parse p b with
    | None -> None
    | Some (x, consumed) ->
      if cond x
      then Some (([], x), consumed)
      else begin match parse (parse_list_up_to_fuel cond p (fuel - 1)) (Seq.slice b consumed (Seq.length b)) with
      | None -> None
      | Some ((y, z), consumed') -> Some ((x::y, z), consumed + consumed')
      end
  ))
= if fuel = 0
  then ()
  else begin
    parse_synth_eq
      (parse_dtuple2
        (weaken (parse_list_up_to_kind k) p)
        #(parse_list_up_to_kind k)
        #(parse_list_up_to_payload_t cond (fuel - 1))
        (parse_list_up_to_payload cond (fuel - 1) k (parse_list_up_to_fuel cond p (fuel - 1))))
      (synth_list_up_to_fuel cond (fuel - 1))
      b;
    parse_dtuple2_eq'
      (weaken (parse_list_up_to_kind k) p)
      #(parse_list_up_to_kind k)
      #(parse_list_up_to_payload_t cond (fuel - 1))
      (parse_list_up_to_payload cond (fuel - 1) k (parse_list_up_to_fuel cond p (fuel - 1)))
      b
  end

let rec parse_list_up_to_fuel_indep
  (#k: parser_kind)
  (#t: Type)
  (cond: (t -> Tot bool))
  (p: parser k t { k.parser_kind_subkind <> Some ParserConsumesAll })
  (fuel: nat)
  (b: bytes)
  (xy: parse_list_up_to_fuel_t cond fuel)
  (consumed: consumed_length b)
  (fuel' : nat { L.length (fst xy) < fuel' })
: Lemma
  (requires (
    parse (parse_list_up_to_fuel cond p fuel) b == Some (xy, consumed)
  ))
  (ensures (
    parse (parse_list_up_to_fuel cond p fuel') b == Some ((fst xy, snd xy), consumed)
  ))
  (decreases fuel)
= assert (fuel > 0);
  assert (fuel' > 0);
  parse_list_up_to_fuel_eq cond p fuel b;
  parse_list_up_to_fuel_eq cond p fuel' b;
  let Some (x, consumed_x) = parse p b in
  if cond x
  then ()
  else
    let b' = Seq.slice b consumed_x (Seq.length b) in
    let Some (yz, consumed_yz) = parse (parse_list_up_to_fuel cond p (fuel - 1)) b' in
    parse_list_up_to_fuel_indep cond p (fuel - 1) b' yz consumed_yz (fuel' - 1)

let rec parse_list_up_to_fuel_length
  (#k: parser_kind)
  (#t: Type)
  (cond: (t -> Tot bool))
  (p: parser k t { k.parser_kind_subkind <> Some ParserConsumesAll })
  (prf: (
    (b: bytes) ->
    (x: t) ->
    (consumed: consumed_length b) ->
    Lemma
    (requires (parse p b == Some (x, consumed) /\ (~ (cond x))))
    (ensures (consumed > 0))
  ))
  (fuel: nat)
  (b: bytes)
: Lemma (
    match parse (parse_list_up_to_fuel cond p fuel) b with  
    | None -> True
    | Some (xy, consumed) -> L.length (fst xy) <= Seq.length b
  )
= parse_list_up_to_fuel_eq cond p fuel b;
  if fuel = 0
  then ()
  else
    match parse p b with
    | None -> ()
    | Some (x, consumed) ->
      if cond x
      then ()
      else begin
        prf b x consumed;
        parse_list_up_to_fuel_length cond p prf (fuel - 1) (Seq.slice b consumed (Seq.length b))
      end

let rec parse_list_up_to_fuel_ext
  (#k: parser_kind)
  (#t: Type)
  (cond: (t -> Tot bool))
  (p: parser k t { k.parser_kind_subkind <> Some ParserConsumesAll })
  (prf: (
    (b: bytes) ->
    (x: t) ->
    (consumed: consumed_length b) ->
    Lemma
    (requires (parse p b == Some (x, consumed) /\ (~ (cond x))))
    (ensures (consumed > 0))
  ))
  (fuel1 fuel2: nat)
  (b: bytes { Seq.length b < fuel1 /\ Seq.length b < fuel2 })
: Lemma
  (ensures (
    match parse (parse_list_up_to_fuel cond p fuel1) b, parse (parse_list_up_to_fuel cond p fuel2) b with  
    | None, None -> True
    | Some (xy1, consumed1), Some (xy2, consumed2) -> (fst xy1 <: list (parse_filter_refine (negate_cond cond)))  == (fst xy2 <: list (parse_filter_refine (negate_cond cond))) /\ snd xy1 == snd xy2 /\ consumed1 == consumed2
    | _ -> False
  ))
  (decreases fuel1)
= parse_list_up_to_fuel_eq cond p fuel1 b;
  parse_list_up_to_fuel_eq cond p fuel2 b;
  match parse p b with
  | None -> ()
  | Some (x, consumed) ->
    if cond x
    then ()
    else begin
      prf b x consumed;
      parse_list_up_to_fuel_ext cond p prf (fuel1 - 1) (fuel2 - 1) (Seq.slice b consumed (Seq.length b))
    end

let synth_list_up_to'
  (#t: Type)
  (cond: (t -> Tot bool))
  (fuel: nat)
  (xy: parse_list_up_to_fuel_t cond fuel)
: Tot (parse_list_up_to_t cond)
= (fst xy, snd xy)

let parse_list_up_to'
  (#k: parser_kind)
  (#t: Type)
  (cond: (t -> Tot bool))
  (p: parser k t { k.parser_kind_subkind <> Some ParserConsumesAll })
  (fuel: nat)
: Tot (parser (parse_list_up_to_kind k) (parse_list_up_to_t cond))
= parse_synth
    (parse_list_up_to_fuel cond p fuel)
    (synth_list_up_to' cond fuel)

let parse_list_up_to'_eq
  (#k: parser_kind)
  (#t: Type)
  (cond: (t -> Tot bool))
  (p: parser k t { k.parser_kind_subkind <> Some ParserConsumesAll })
  (fuel: nat)
  (b: bytes)
: Lemma
  (parse (parse_list_up_to' cond p fuel) b == (
    match parse (parse_list_up_to_fuel cond p fuel) b with
    | None -> None
    | Some (xy, consumed) -> Some ((fst xy, snd xy), consumed)
  ))
= 
  parse_synth_eq
    (parse_list_up_to_fuel cond p fuel)
    (synth_list_up_to' cond fuel)
    b

let close_parse_list_up_to
  (b: bytes)
: GTot (n: nat { Seq.length b < n })
= Seq.length b + 1

let parse_list_up_to_correct
  (#k: parser_kind)
  (#t: Type)
  (cond: (t -> Tot bool))
  (p: parser k t { k.parser_kind_subkind <> Some ParserConsumesAll })
  (prf: (
    (b: bytes) ->
    (x: t) ->
    (consumed: consumed_length b) ->
    Lemma
    (requires (parse p b == Some (x, consumed) /\ (~ (cond x))))
    (ensures (consumed > 0))
  ))
: Lemma
  (parser_kind_prop (parse_list_up_to_kind k) (close_by_fuel (parse_list_up_to' cond p) close_parse_list_up_to))
= close_by_fuel_correct
    (parse_list_up_to_kind k)
    (parse_list_up_to' cond p) 
    close_parse_list_up_to
    (fun fuel b ->
      parse_list_up_to'_eq cond p (close_parse_list_up_to b) b;
      parse_list_up_to'_eq cond p fuel b;
      parse_list_up_to_fuel_ext cond p prf (close_parse_list_up_to b) fuel b
    )
    (fun fuel ->
      parser_kind_prop_fuel_complete fuel (parse_list_up_to_kind k) (parse_list_up_to' cond p fuel)
    )

let consumes_if_not_cond
  (#k: parser_kind)
  (#t: Type)
  (cond: (t -> Tot bool))
  (p: parser k t)
: Tot Type
= 
    (b: bytes) ->
    (x: t) ->
    (consumed: consumed_length b) ->
    Lemma
    (requires (parse p b == Some (x, consumed) /\ (~ (cond x))))
    (ensures (consumed > 0))

let parse_list_up_to
  (#k: parser_kind)
  (#t: Type)
  (cond: (t -> Tot bool))
  (p: parser k t { k.parser_kind_subkind <> Some ParserConsumesAll })
  (prf: consumes_if_not_cond cond p)
: Tot (parser (parse_list_up_to_kind k) (parse_list_up_to_t cond))
= parse_list_up_to_correct cond p prf;
  close_by_fuel (parse_list_up_to' cond p) close_parse_list_up_to

let parse_list_up_to_eq
  (#k: parser_kind)
  (#t: Type)
  (cond: (t -> Tot bool))
  (p: parser k t { k.parser_kind_subkind <> Some ParserConsumesAll })
  (prf: consumes_if_not_cond cond p)
  (b: bytes)
: Lemma
  (parse (parse_list_up_to cond p prf) b == (
    match parse p b with
    | None -> None
    | Some (x, consumed) ->
      if cond x
      then Some (([], x), consumed)
      else begin match parse (parse_list_up_to cond p prf) (Seq.slice b consumed (Seq.length b)) with
      | None -> None
      | Some ((y, z), consumed') -> Some ((x::y, z), consumed + consumed')
      end
  ))
= let fuel = close_parse_list_up_to b in
  parse_list_up_to'_eq cond p fuel b;
  parse_list_up_to_fuel_eq cond p fuel b;
  match parse p b with
  | None -> ()
  | Some (x, consumed) ->
    if cond x
    then ()
    else begin
      prf b x consumed;
      let b' = Seq.slice b consumed (Seq.length b) in
      let fuel' = close_parse_list_up_to b' in
      parse_list_up_to'_eq cond p fuel' b' ;
      parse_list_up_to_fuel_ext cond p prf (fuel - 1) fuel' b'
    end
