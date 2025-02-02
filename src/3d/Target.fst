(*
   Copyright 2019 Microsoft Research

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*)
module Target
(* The abstract syntax for the code produced by 3d *)
open FStar.All
module A = Ast
open Binding

let rec expr_eq e1 e2 =
  match fst e1, fst e2 with
  | Constant c1, Constant c2 -> c1=c2
  | Identifier i1, Identifier i2 -> A.(i1.v = i2.v)
  | App hd1 args1, App hd2 args2 -> hd1 = hd2 && exprs_eq args1 args2
  | Record t1 fields1, Record t2 fields2 -> A.(t1.v = t2.v) && fields_eq fields1 fields2
  | _ -> false
and exprs_eq es1 es2 =
  match es1, es2 with
  | [], [] -> true
  | e1::es1, e2::es2 -> expr_eq e1 e2 && exprs_eq es1 es2
  | _ -> false
and fields_eq fs1 fs2 =
  match fs1, fs2 with
  | [], [] -> true
  | (i1, e1)::fs1, (i2, e2)::fs2 ->
    A.(i1.v = i2.v)
    && fields_eq fs1 fs2
  | _ -> false
let rec parser_kind_eq k k' =
  match k.pk_kind, k'.pk_kind with
  | PK_return, PK_return -> true
  | PK_impos, PK_impos -> true
  | PK_list,  PK_list -> true
  | PK_t_at_most,  PK_t_at_most -> true
  | PK_t_exact,  PK_t_exact -> true
  | PK_base hd1, PK_base hd2 -> A.(hd1.v = hd2.v)
  | PK_filter k, PK_filter k' -> parser_kind_eq k k'
  | PK_and_then k1 k2, PK_and_then k1' k2'
  | PK_glb k1 k2, PK_glb k1' k2' ->
    parser_kind_eq k1 k1'
    && parser_kind_eq k2 k2'
  | _ -> false

// Some constants

let default_attrs = {
    is_hoisted = false;
    is_exported = false;
    should_inline = false;
    comments = []
}

let error_handler_name =
  let open A in
  let id' = {
    modul_name = None;
    name = "handle_error";
  } in
  let id = with_range id' dummy_range in
  id
  
let error_handler_decl =
  let open A in
  let error_handler_id' = {
    modul_name = Some "EverParse3d.Actions.Base";
    name = "error_handler"
  } in
  let error_handler_id = with_range error_handler_id' dummy_range in
  let typ = T_app error_handler_id KindSpec [] in
  let a = Assumption (error_handler_name, typ) in
  a, default_attrs

////////////////////////////////////////////////////////////////////////////////
// Printing the target AST in F* concrete syntax
////////////////////////////////////////////////////////////////////////////////

let maybe_mname_prefix (mname:string) (i:A.ident) =
  let open A in
  match i.v.modul_name with
  | None -> ""
  | Some s -> if s = mname then "" else Printf.sprintf "%s." s

let print_ident (i:A.ident) =
  let open A in
  match String.list_of_string i.v.name with
  | [] -> i.v.name
  | c0::_ ->
    if FStar.Char.lowercase c0 = c0
    then i.v.name
    else Ast.reserved_prefix^i.v.name

let print_maybe_qualified_ident (mname:string) (i:A.ident) =
  Printf.sprintf "%s%s" (maybe_mname_prefix mname i) (print_ident i)

let print_field_id_name (i:A.ident) =
  let open A in
  match i.v.modul_name with
  | None -> failwith "Unexpected: module name missing from the field id"
  | Some m -> Printf.sprintf "%s_%s" (String.lowercase m) i.v.name

let print_integer_type =
  let open A in
  function
   | UInt8 -> "uint8"
   | UInt16 -> "uint16"
   | UInt32 -> "uint32"
   | UInt64 -> "uint64"

let namespace_of_integer_type =
  let open A in
  function
   | UInt8 -> "UInt8"
   | UInt16 -> "UInt16"
   | UInt32 -> "UInt32"
   | UInt64 -> "UInt64"

let print_range (r:A.range) : string =
  let open A in
  Printf.sprintf "(Prims.mk_range \"%s\" %d %d %d %d)"
    (fst r).filename
    (fst r).line
    (fst r).col
    (snd r).line
    (snd r).col

let arith_op (o:op) =
  match o with
  | Plus _
  | Minus _
  | Mul _
  | Division _
  | Remainder _
  | ShiftLeft _
  | ShiftRight _
  | BitwiseAnd _
  | BitwiseOr _
  | BitwiseXor _
  | BitwiseNot _ -> true
  | _ -> false

let integer_type_of_arith_op (o:op{arith_op o}) =
  match o with
  | Plus t
  | Minus t
  | Mul t
  | Division t
  | Remainder t
  | ShiftLeft t
  | ShiftRight t
  | BitwiseAnd t
  | BitwiseOr t
  | BitwiseXor t
  | BitwiseNot t -> t

let print_arith_op_range () : ML bool =
  List.length (Options.get_equate_types_list ()) = 0

let print_arith_op
  (o:op{arith_op o})
  (r:option A.range) : ML string
  = let fn =
      match o with
      | Plus _ -> "add"
      | Minus _ -> "sub"
      | Mul _ -> "mul"
      | Division _ -> "div"
      | Remainder _ -> "rem"
      | ShiftLeft _ -> "shift_left"
      | ShiftRight _ -> "shift_right"
      | BitwiseAnd _ -> "logand"
      | BitwiseOr _ -> "logor"
      | BitwiseXor _ -> "logxor"
      | BitwiseNot _ -> "lognot"
    in

    if print_arith_op_range ()
    then
      let t =
        match integer_type_of_arith_op o with
        | A.UInt8 -> "u8"
        | A.UInt16 -> "u16"
        | A.UInt32 -> "u32"
        | A.UInt64 -> "u64"
      in
      let r = match r with | Some r -> r | None -> A.dummy_range in
      Printf.sprintf "EverParse3d.Prelude.%s_%s %s"
        t fn (print_range r)
    else
      let m =
        match integer_type_of_arith_op o with
        | A.UInt8 -> "FStar.UInt8"
        | A.UInt16 -> "FStar.UInt16"
        | A.UInt32 -> "FStar.UInt32"
        | A.UInt64 -> "FStar.UInt64"
      in
      Printf.sprintf "%s.%s" m fn

let is_infix =
  function
  | Eq
  | Neq
  | And
  | Or -> true
  | _ -> false

let print_op_with_range ropt o =
  match o with
  | Eq -> "="
  | Neq -> "<>"
  | And -> "&&"
  | Or -> "||"
  | Not -> "not"
  | Plus _
  | Minus _
  | Mul _
  | Division _
  | Remainder _
  | ShiftLeft _
  | ShiftRight _
  | BitwiseAnd _
  | BitwiseOr _
  | BitwiseXor _
  | BitwiseNot _ -> print_arith_op o ropt
  | LT t -> Printf.sprintf "FStar.%s.lt" (namespace_of_integer_type t)
  | GT t -> Printf.sprintf "FStar.%s.gt" (namespace_of_integer_type t)
  | LE t -> Printf.sprintf "FStar.%s.lte" (namespace_of_integer_type t)
  | GE t -> Printf.sprintf "FStar.%s.gte" (namespace_of_integer_type t)
  | IfThenElse -> "ite"
  | BitFieldOf i -> Printf.sprintf "get_bitfield%d" i
  | Cast from to ->
    let tfrom = print_integer_type from in
    let tto = print_integer_type to in
    if tfrom = tto
    then "EverParse3d.Prelude.id"
    else Printf.sprintf "EverParse3d.Prelude.%s_to_%s" tfrom tto
  | Ext s -> s

let print_op = print_op_with_range None

let rec print_expr (mname:string) (e:expr) : ML string =
  match fst e with
  | Constant c ->
    A.print_constant c
  | Identifier i -> print_maybe_qualified_ident mname i
  | Record nm fields ->
    Printf.sprintf "{ %s }" (String.concat "; " (print_fields mname fields))
  | App op [e1;e2] ->
    if is_infix op
    then
      Printf.sprintf "(%s %s %s)"
                   (print_expr mname e1)
                   (print_op_with_range (Some (snd e)) (App?.hd (fst e)))
                   (print_expr mname e2)
    else
      Printf.sprintf "(%s %s %s)"
                   (print_op_with_range (Some (snd e)) (App?.hd (fst e)))
                   (print_expr mname e1)
                   (print_expr mname e2)
  | App Not [e1]
  | App (BitwiseNot _) [e1] ->
    Printf.sprintf "(%s %s)" (print_op (App?.hd (fst e))) (print_expr mname e1)
  | App IfThenElse [e1;e2;e3] ->
    Printf.sprintf
      "(if %s then %s else %s)"
      (print_expr mname e1) (print_expr mname e2) (print_expr mname e3)
  | App (BitFieldOf i) [e1;e2;e3] ->
    Printf.sprintf
      "(%s %s %s %s)"
      (print_op (BitFieldOf i))
      (print_expr mname e1) (print_expr mname e2) (print_expr mname e3)
  | App op [] ->
    print_op op
  | App op es ->
    Printf.sprintf "(%s %s)" (print_op op) (String.concat " " (print_exprs mname es))

and print_exprs (mname:string) (es:list expr) : ML (list string) =
  match es with
  | [] -> []
  | hd::tl -> print_expr mname hd :: print_exprs mname tl

and print_fields (mname:string) (fs:_) : ML (list string) =
  match fs with
  | [] -> []
  | (x, e)::tl ->
    Printf.sprintf "%s = %s" (print_ident x) (print_expr mname e)
    :: print_fields mname tl

let print_lam (#a:Type) (f:a -> ML string) (x:lam a) : ML string =
  match x with
  | Some x, y ->
    Printf.sprintf ("(fun %s -> %s)")
      (print_ident x)
      (f y)
  | None, y -> f y

let print_expr_lam (mname:string) (x:lam expr) : ML string =
  print_lam (print_expr mname) x

let rec is_output_type (t:typ) : bool =
  match t with
  | T_app _ A.KindOutput [] -> true
  | T_pointer t -> is_output_type t
  | _ -> false

let rec is_extern_type (t:typ) : bool =
  match t with
  | T_app _ A.KindExtern [] -> true
  | T_pointer t -> is_extern_type t
  | _ -> false

(*
 * An output type is printed as the ident, or p_<ident>
 *
 * They are abstract types in the emitted F* code
 *)
let print_output_type (qual:bool) (t:typ) : ML string =
  let rec aux (t:typ)
    : ML (option string & string)
    = match t with
      | T_app id _ _ -> 
        id.v.modul_name, print_ident id
      | T_pointer t ->
        let m, i = aux t in
        m, Printf.sprintf "p_%s" i
      | _ -> failwith "Print: not an output type"
  in
  let mopt, i = aux t in
  if qual 
  then match mopt with
       | None -> i
       | Some m -> Printf.sprintf "%s.ExternalAPI.%s" m i
  else i

let rec print_typ (mname:string) (t:typ) : ML string = //(decreases t) =
  if is_output_type t
  then print_output_type true t
  else
  match t with
  | T_false -> "False"
  | T_app hd _ args ->  //output types are already handled at the beginning of print_typ
    Printf.sprintf "(%s %s)"
      (print_maybe_qualified_ident mname hd)
      (String.concat " " (print_indexes mname args))
  | T_dep_pair t1 (x, t2) ->
    Printf.sprintf "(%s:%s & %s)"
      (print_ident x)
      (print_typ mname t1)
      (print_typ mname t2)
  | T_refine t e ->
    Printf.sprintf "(refine %s %s)"
      (print_typ mname t)
      (print_expr_lam mname e)
  | T_if_else e t1 t2 ->
    Printf.sprintf "(t_ite %s (fun _ -> %s) (fun _ -> %s))"
      (print_expr mname e)
      (print_typ mname t1)
      (print_typ mname t2)
  | T_pointer t -> Printf.sprintf "bpointer (%s)" (print_typ mname t)
  | T_with_action t _
  | T_with_dep_action t _
  | T_with_comment t _ -> print_typ mname t

and print_indexes (mname:string) (is:list index) : ML (list string) = //(decreases is) =
  match is with
  | [] -> []
  | Inl t::is -> print_typ mname t::print_indexes mname is
  | Inr e::is -> print_expr mname e::print_indexes mname is

let rec print_kind (mname:string) (k:parser_kind) : Tot string =
  match k.pk_kind with
  | PK_base hd ->
    Printf.sprintf "%skind_%s"
      (maybe_mname_prefix mname hd)
      (print_ident hd)
  | PK_list ->
    "kind_nlist"
  | PK_t_at_most ->
    "kind_t_at_most"
  | PK_t_exact ->
    "kind_t_exact"
  | PK_return ->
    "ret_kind"
  | PK_impos ->
    "impos_kind"
  | PK_and_then k1 k2 ->
    Printf.sprintf "(and_then_kind %s %s)"
      (print_kind mname k1)
      (print_kind mname k2)
  | PK_glb k1 k2 ->
    Printf.sprintf "(glb %s %s)"
      (print_kind mname k1)
      (print_kind mname k2)
  | PK_filter k ->
    Printf.sprintf "(filter_kind %s)"
      (print_kind mname k)
  | PK_string ->
    "parse_string_kind"

let rec print_parser (mname:string) (p:parser) : ML string = //(decreases p) =
  match p.p_parser with
  | Parse_return v ->
    Printf.sprintf "(parse_ret %s)" (print_expr mname v)
  | Parse_app hd args ->
    Printf.sprintf "(%sparse_%s %s)" (maybe_mname_prefix mname hd) (print_ident hd) (String.concat " " (print_indexes mname args))
  | Parse_nlist e p ->
    Printf.sprintf "(parse_nlist %s %s)" (print_expr mname e) (print_parser mname p)
  | Parse_t_at_most e p ->
    Printf.sprintf "(parse_t_at_most %s %s)" (print_expr mname e) (print_parser mname p)
  | Parse_t_exact e p ->
    Printf.sprintf "(parse_t_exact %s %s)" (print_expr mname e) (print_parser mname p)
  | Parse_pair _ p1 p2 ->
    Printf.sprintf "(%s `parse_pair` %s)" (print_parser mname p1) (print_parser mname p2)
  | Parse_dep_pair _ p1 p2
  | Parse_dep_pair_with_action p1 _ p2 ->
    Printf.sprintf "(%s `parse_dep_pair` %s)"
      (print_parser mname p1)
      (print_lam (print_parser mname) p2)
  | Parse_dep_pair_with_refinement _ p1 e p2
  | Parse_dep_pair_with_refinement_and_action _ p1 e _ p2 ->
    Printf.sprintf "((%s `parse_filter` %s) `parse_dep_pair` %s)"
                   (print_parser mname p1)
                   (print_expr_lam mname e)
                   (print_lam (print_parser mname) p2)
  | Parse_map p1 e ->
    Printf.sprintf "(%s `parse_map` %s)"
      (print_parser mname p1)
      (print_expr_lam mname e)
  | Parse_refinement _ p1 e
  | Parse_refinement_with_action _ p1 e _ ->
    Printf.sprintf "(%s `parse_filter` %s)"
      (print_parser mname p1)
      (print_expr_lam mname e)
  | Parse_weaken_left p1 k ->
    Printf.sprintf "(parse_weaken_left %s %s)" (print_parser mname p1) (print_kind mname k)
  | Parse_weaken_right p1 k ->
    Printf.sprintf "(parse_weaken_right %s %s)" (print_parser mname p1) (print_kind mname k)
  | Parse_if_else e p1 p2 ->
    Printf.sprintf "(parse_ite %s (fun _ -> %s) (fun _ -> %s))"
      (print_expr mname e)
      (print_parser mname p1)
      (print_parser mname p2)
  | Parse_impos -> "(parse_impos())"
  | Parse_with_dep_action _ p _
  | Parse_with_action _ p _
  | Parse_with_comment p _ -> print_parser mname p
  | Parse_string elem zero ->
    Printf.sprintf "(parse_string %s %s)" (print_parser mname elem) (print_expr mname zero)

let rec print_reader (mname:string) (r:reader) : ML string =
  match r with
  | Read_u8 -> "read____UINT8"
  | Read_u16 -> "read____UINT16"
  | Read_u32 -> "read____UINT32"
  | Read_app hd args ->
    Printf.sprintf "(%sread_%s %s)" (maybe_mname_prefix mname hd) (print_ident hd) (String.concat " " (print_indexes mname args))
  | Read_filter r f ->
    Printf.sprintf "(read_filter %s %s)"
      (print_reader mname r)
      (print_expr_lam mname f)

let rec print_action (mname:string) (a:action) : ML string =
  let print_atomic_action (a:atomic_action)
    : ML string
    = match a with
      | Action_return e ->
        Printf.sprintf "(action_return %s)" (print_expr mname e)
      | Action_abort -> "(action_abort())"
      | Action_field_pos_64 -> "(action_field_pos_64())"
      | Action_field_pos_32 -> "(action_field_pos_32 EverParse3d.Actions.BackendFlagValue.backend_flag_value)"
      | Action_field_ptr -> "(action_field_ptr EverParse3d.Actions.BackendFlagValue.backend_flag_value)"
      | Action_field_ptr_after sz write_to ->
        Printf.sprintf "(action_field_ptr_after EverParse3d.Actions.BackendFlagValue.backend_flag_value %s %s)" (print_expr mname sz) (print_ident write_to)
      | Action_field_ptr_after_with_setter sz write_to_field write_to_obj ->
        Printf.sprintf "(action_field_ptr_after_with_setter EverParse3d.Actions.BackendFlagValue.backend_flag_value %s (%s %s))"
          (print_expr mname sz)
          (print_ident write_to_field)
          (print_expr mname write_to_obj)
      | Action_deref i ->
        Printf.sprintf "(action_deref %s)" (print_ident i)
      | Action_assignment lhs rhs ->
        Printf.sprintf "(action_assignment %s %s)" (print_ident lhs) (print_expr mname rhs)
      | Action_call f args ->
        Printf.sprintf "(mk_external_action (%s %s))" (print_ident f) (String.concat " " (List.map (print_expr mname) args))
  in
  match a with
  | Atomic_action a ->
    print_atomic_action a
  | Action_seq hd tl ->
    Printf.sprintf "(action_seq %s %s)"
                    (print_atomic_action hd)
                    (print_action mname tl)
  | Action_ite hd then_ else_ ->
    Printf.sprintf "(action_ite %s (fun _ -> %s) (fun _ -> %s))"
      (print_expr mname hd)
      (print_action mname then_)
      (print_action mname else_)
  | Action_let i a k ->
    Printf.sprintf "(action_bind \"%s\" %s (fun %s -> %s))"
                   (print_ident i)
                   (print_atomic_action a)
                   (print_ident i)
                   (print_action mname k)
  | Action_act a -> 
    Printf.sprintf "(action_act %s)" 
      (print_action mname a)
      
let rec print_validator (mname:string) (v:validator) : ML string = //(decreases v) =
  let is_unit_validator v =
    let open A in
    match v.v_validator with
    | Validate_app ({v={name="unit"}}) [] -> true
    | _ -> false
  in
  match v.v_validator with
  | Validate_return ->
    "validate_ret"

  | Validate_app hd args ->
    Printf.sprintf "(validate_eta (%svalidate_%s %s))"
                   (maybe_mname_prefix mname hd)
                   (print_ident hd)
                   (String.concat " " (print_indexes mname args))

  | Validate_nlist e p ->
    Printf.sprintf "(validate_nlist %s %s)"
                   (print_expr mname e)
                   (print_validator mname p)

  | Validate_t_at_most e p ->
    Printf.sprintf "(validate_t_at_most %s %s)"
                   (print_expr mname e)
                   (print_validator mname p)

  | Validate_t_exact e p ->
    Printf.sprintf "(validate_t_exact %s %s)"
                   (print_expr mname e)
                   (print_validator mname p)

  | Validate_nlist_constant_size_without_actions e p ->
    let n_is_const = match fst e with
    | Constant (A.Int _ _) -> true
    | _ -> false
    in
    Printf.sprintf "(validate_nlist_constant_size_without_actions %s %s %s)"
                   (if n_is_const then "true" else "false")
                   (print_expr mname e)
                   (print_validator mname p)

  | Validate_pair n1 p1 p2 ->
    Printf.sprintf "(validate_pair \"%s\" %s %s)"
                   (print_maybe_qualified_ident mname n1)
                   (print_validator mname p1)
                   (print_validator mname p2)

  | Validate_dep_pair n1 p1 r p2 ->
    Printf.sprintf "(validate_dep_pair \"%s\" %s %s %s)"
                   (print_ident n1)
                   (print_validator mname p1)
                   (print_reader mname r)
                   (print_lam (print_validator mname) p2)

  | Validate_dep_pair_with_refinement p1_is_constant_size_without_actions n1 p1 r e p2 ->
    Printf.sprintf "(validate_dep_pair_with_refinement %s \"%s\" %s %s %s %s)"
                   (if p1_is_constant_size_without_actions then "true" else "false")
                   (print_maybe_qualified_ident mname n1)
                   (print_validator mname p1)
                   (print_reader mname r)
                   (print_expr_lam mname e)
                   (print_lam (print_validator mname) p2)

  | Validate_dep_pair_with_action p1 r a p2 ->
    Printf.sprintf "(validate_dep_pair_with_action %s %s %s %s)"
                   (print_validator mname p1)
                   (print_reader mname r)
                   (print_lam (print_action mname) a)
                   (print_lam (print_validator mname) p2)

  | Validate_dep_pair_with_refinement_and_action p1_is_constant_size_without_actions n1 p1 r e a p2 ->
    Printf.sprintf "(validate_dep_pair_with_refinement_and_action %s \"%s\" %s %s %s %s %s)"
                   (if p1_is_constant_size_without_actions then "true" else "false")
                   (print_maybe_qualified_ident mname n1)
                   (print_validator mname p1)
                   (print_reader mname r)
                   (print_expr_lam mname e)
                   (print_lam (print_action mname) a)
                   (print_lam (print_validator mname) p2)

  | Validate_map p1 e ->
    Printf.sprintf "(%s `validate_map` %s)"
                   (print_validator mname p1)
                   (print_expr_lam mname e)

  | Validate_refinement n1 p1 r e ->
    begin
      if is_unit_validator p1
      then Printf.sprintf "(validate_unit_refinement %s \"checking precondition\")"
                          (print_expr_lam mname e)
      else Printf.sprintf "(validate_filter \"%s\" %s %s %s
                                            \"reading field value\" \"checking constraint\")"
                          (print_maybe_qualified_ident mname n1)
                          (print_validator mname p1)
                          (print_reader mname r)
                          (print_expr_lam mname e)
    end

  | Validate_refinement_with_action n1 p1 r e a ->
    Printf.sprintf "(validate_filter_with_action \"%s\" %s %s %s
                                            \"reading field value\" \"checking constraint\"
                                            %s)"
                   (print_maybe_qualified_ident mname n1)
                   (print_validator mname p1)
                   (print_reader mname r)
                   (print_expr_lam mname e)
                   (print_lam (print_action mname) a)

  | Validate_with_action name v a ->
    Printf.sprintf "(validate_with_success_action \"%s\" %s %s)"
                   (print_maybe_qualified_ident mname name)
                   (print_validator mname v)
                   (print_action mname a)

  | Validate_with_dep_action n v r a ->
    Printf.sprintf "(validate_with_dep_action \"%s\" %s %s %s)"
                   (print_maybe_qualified_ident mname n)
                   (print_validator mname v)
                   (print_reader mname r)
                   (print_lam (print_action mname) a)

  | Validate_weaken_left p1 k ->
    Printf.sprintf "(validate_weaken_left %s _)"
                   (print_validator mname p1)

  | Validate_weaken_right p1 k ->
    Printf.sprintf "(validate_weaken_right %s _)"
                   (print_validator mname p1)

  | Validate_if_else e v1 v2 ->
    Printf.sprintf "(validate_ite %s (fun _ -> %s) (fun _ -> %s) (fun _ -> %s) (fun _ -> %s))"
                   (print_expr mname e)
                   (print_parser mname v1.v_parser)
                   (print_validator mname v1)
                   (print_parser mname v2.v_parser)
                   (print_validator mname v2)

  | Validate_impos ->
    "(validate_impos())"

  | Validate_with_error_handler typename fieldname v ->
    Printf.sprintf "(validate_with_error_handler \"%s\" \"%s\" %s)"
                   (print_maybe_qualified_ident mname typename)
                   fieldname
                   (print_validator mname v)

  | Validate_with_comment v c ->
    let c = String.concat "\n" c in
    Printf.sprintf "(validate_with_comment \"%s\" %s)"
                   c
                   (print_validator mname v)

  | Validate_string velem relem zero ->
    Printf.sprintf "(validate_string %s %s %s)" 
                   (print_validator mname velem)
                   (print_reader mname relem)
                   (print_expr mname zero)

let print_typedef_name (mname:string) (tdn:typedef_name) : ML string =
  Printf.sprintf "%s %s"
                 (print_ident tdn.td_name)
                 (String.concat " "
                   (List.map 
                     (fun (id, t) -> 
                       Printf.sprintf "(%s:%s)"
                                      (print_ident id)
                                      (print_typ mname t))
                     tdn.td_params))

let print_typedef_typ (tdn:typedef_name) : ML string =
  Printf.sprintf "%s %s"
    (print_ident tdn.td_name)
    (String.concat " "
      (List.map (fun (id, t) -> (print_ident id)) tdn.td_params))

let print_typedef_body (mname:string) (b:typedef_body) : ML string =
  match b with
  | TD_abbrev t -> print_typ mname t
  | TD_struct fields ->
    let print_field (sf:field) : ML string =
        Printf.sprintf "%s : %s%s"
          (print_ident sf.sf_ident)
          (print_typ mname sf.sf_typ)
          (if sf.sf_dependence then " (*dep*)" else "")
    in
    let fields = String.concat ";\n" (List.map print_field fields) in
    Printf.sprintf "{\n%s\n}" fields

let print_typedef_actions_inv_and_fp (td:type_decl) =
    //we need to add output loc to the modifies locs
    //if there is an output type type parameter
    let should_add_output_loc =
      List.Tot.existsb (fun (_, t) -> is_output_type t || is_extern_type t) td.decl_name.td_params in
    let pointers =  //get only non output type pointers
      List.Tot.filter (fun (x, t) -> T_pointer? t && not (is_output_type t || is_extern_type t)) td.decl_name.td_params
    in
    let inv =
      List.Tot.fold_right
        (fun (x, t) out ->
          Printf.sprintf "((ptr_inv %s) `conj_inv` %s)"
                         (print_ident x)
                         out)
        pointers
        "true_inv"
    in
    let fp =
      List.Tot.fold_right
        (fun (x, t) out ->
          Printf.sprintf "(eloc_union (ptr_loc %s) %s)"
                         (print_ident x)
                         out)
        pointers
        (if should_add_output_loc then "output_loc" else "eloc_none")
    in
    inv, fp

let print_comments (cs:list string) : string =
  match cs with
  | [] -> ""
  | _ ->
    let c = String.concat "\\n\\\n" cs in
    Printf.sprintf " (Comment \"%s\")" c

let print_attributes (entrypoint:bool) (attrs:decl_attributes) : string =
  match attrs.comments with
  | [] ->
    if entrypoint || attrs.is_exported
    then ""
    else if attrs.should_inline
    then "inline_for_extraction noextract\n"
    else "[@ (CInline)]\n"
  | cs ->
    Printf.sprintf "[@ %s %s]\n%s"
      (print_comments cs)
      (if not entrypoint &&
          not attrs.is_exported &&
          not attrs.should_inline 
       then "(CInline)" else "")
      (if attrs.should_inline then "inline_for_extraction\n" else "")


/// Printing a decl for M.Types.fst
///
/// Print all the definitions, and for a Type_decl, only the type definition

let maybe_print_type_equality (mname:string) (td:type_decl) : ML string =
  if td.decl_name.td_entrypoint
  then
    let equate_types_list = Options.get_equate_types_list () in
    (match (List.tryFind (fun (_, m) -> m = mname) equate_types_list) with
     | Some (a, _) ->
       let typname = A.ident_name td.decl_name.td_name in
       Printf.sprintf "\n\nlet _ = assert (%s.Types.%s == %s) by (FStar.Tactics.trefl ())\n\n"
         a typname typname         
     | None -> "")
  else ""

let print_definition (mname:string) (d:decl { Definition? (fst d)} ) : ML string =
  match fst d with
  | Definition (x, [], T_app ({Ast.v={Ast.name="field_id"}}) _ _, (Constant c, _)) ->
    Printf.sprintf "[@(CMacro)%s]\nlet %s = %s <: Tot field_id by (FStar.Tactics.trivial())\n\n"
     (print_comments (snd d).comments)
     (print_field_id_name x)
     (A.print_constant c)

  | Definition (x, [], t, (Constant c, _)) ->
    Printf.sprintf "[@(CMacro)%s]\nlet %s = %s <: Tot %s\n\n"
      (print_comments (snd d).comments)
      (print_ident x)
      (A.print_constant c)
      (print_typ mname t) 
  
  | Definition (x, params, typ, expr) ->
    let x_ps = {
      td_name = x;
      td_params = params;
      td_entrypoint = false
    } in
    Printf.sprintf "%slet %s : %s = %s\n\n"
      (print_attributes false (snd d))
      (print_typedef_name mname x_ps)
      (print_typ mname typ)
      (print_expr mname expr)

let print_assumption (mname:string) (d:decl { Assumption? (fst d) } ) : ML string =
  match fst d with
  | Assumption (x, t) ->
    Printf.sprintf "assume\nval %s : %s\n\n"
      (print_ident x)      
      (print_typ mname t) 

let print_decl_for_types (mname:string) (d:decl) : ML string =
  match fst d with
  | Assumption _ -> ""
  
  | Definition _ ->
    print_definition mname d

  | Type_decl td ->
    Printf.sprintf "noextract\ninline_for_extraction\ntype %s = %s\n\n"
      (print_typedef_name mname td.decl_name)
      (print_typedef_body mname td.decl_typ)
    `strcat`
    maybe_print_type_equality mname td

  | Output_type _

  | Output_type_expr _ _

  | Extern_type _

  | Extern_fn _ _ _ -> ""

/// Print a decl for M.fst
///
/// No need to print Definition(s), they are `include`d from M.Types.fst
///
/// For a Type_decl, if it is an entry point, we need to emit a definition since
///   there is a corresponding declaration in the .fsti
///   We make the definition as simply the definition in M.Types.fst

let is_type_abbreviation (td:type_decl) : bool =
  match td.decl_typ with
  | TD_abbrev _ -> true
  | TD_struct _ -> false

let print_decl_for_validators (mname:string) (d:decl) : ML string =
  match fst d with
  | Definition _ -> ""
  
  | Assumption _ ->
    print_assumption mname d

  | Type_decl td ->
    (if false //not td.decl_name.td_entrypoint
     then ""
     else if is_type_abbreviation td
     then ""
     else Printf.sprintf "noextract\ninline_for_extraction\nlet %s = %s.Types.%s  (* from corresponding Types.fst  *)\n\n"
            (print_typedef_name mname td.decl_name)
            mname
            (print_typedef_typ td.decl_name))
    `strcat`
    Printf.sprintf "noextract\ninline_for_extraction\nlet kind_%s : parser_kind %s %s = %s\n\n"
      (print_ident td.decl_name.td_name)
      (string_of_bool td.decl_parser.p_kind.pk_nz)
      (A.print_weak_kind td.decl_parser.p_kind.pk_weak_kind)
      (print_kind mname td.decl_parser.p_kind)
    `strcat`
    Printf.sprintf "noextract\nlet parse_%s : parser (kind_%s) (%s) = %s\n\n"
      (print_typedef_name mname td.decl_name)
      (print_ident td.decl_name.td_name)
      (print_typedef_typ td.decl_name)
      (print_parser mname td.decl_parser)
    `strcat`
    (let inv, fp = print_typedef_actions_inv_and_fp td in
     Printf.sprintf "%slet validate_%s = validate_weaken_inv_loc _ _ %s <: Tot (validate_with_action_t (parse_%s) %s %s %b) by    (weaken_tac())\n\n"
      (print_attributes td.decl_name.td_entrypoint (snd d))
      (print_typedef_name mname td.decl_name)
      (print_validator mname td.decl_validator)
      (print_typedef_typ td.decl_name)
      inv
      fp
      td.decl_validator.v_allow_reading)
    `strcat`
    (match td.decl_reader with
     | None -> ""
     | Some r ->
       Printf.sprintf "%sinline_for_extraction\nlet read_%s : leaf_reader (parse_%s) = %s\n\n"
         (if td.decl_name.td_entrypoint then "" else "noextract\n")
         (print_typedef_name mname td.decl_name)
         (print_typedef_typ td.decl_name)
         (print_reader mname r))
  
  | Output_type _
  | Output_type_expr _ _
  | Extern_type _
  | Extern_fn _ _ _ -> ""

let print_type_decl_signature (mname:string) (d:decl{Type_decl? (fst d)}) : ML string =
  match fst d with
  | Type_decl td ->
    if false //not td.decl_name.td_entrypoint
    then ""
    else begin
      (if is_type_abbreviation td
       then Printf.sprintf "noextract\ninline_for_extraction\ntype %s = %s.Types.%s\n\n"
              (print_typedef_name mname td.decl_name)
              mname
              (print_typedef_typ td.decl_name)
       else Printf.sprintf "noextract\ninline_for_extraction\nval %s : Type0\n\n"
              (print_typedef_name mname td.decl_name))
      `strcat`
      Printf.sprintf "noextract\ninline_for_extraction\nval kind_%s : parser_kind %s %s\n\n"
        (print_ident td.decl_name.td_name)
        (string_of_bool td.decl_parser.p_kind.pk_nz)
        (A.print_weak_kind td.decl_parser.p_kind.pk_weak_kind)
      `strcat`
      Printf.sprintf "noextract\nval parse_%s : parser (kind_%s) (%s)\n\n"
        (print_typedef_name mname td.decl_name)
        (print_ident td.decl_name.td_name)
        (print_typedef_typ td.decl_name)
      `strcat`
      (let inv, fp = print_typedef_actions_inv_and_fp td in
      Printf.sprintf "val validate_%s : validate_with_action_t (parse_%s) %s %s %b\n\n"
        (print_typedef_name mname td.decl_name)
        (print_typedef_typ td.decl_name)
        inv
        fp
        td.decl_validator.v_allow_reading)
      `strcat`
      (match td.decl_reader with
       | None -> ""
       | Some r ->
         Printf.sprintf "%sinline_for_extraction\nval read_%s : leaf_reader (parse_%s)\n\n"
           (if td.decl_name.td_entrypoint then "" else "noextract\n")
           (print_typedef_name mname td.decl_name)
           (print_typedef_typ td.decl_name))
     end

let print_decl_signature (mname:string) (d:decl) : ML string =
  match fst d with
  | Assumption _
  | Definition _ -> ""
  | Type_decl td ->
    if (snd d).is_hoisted
    then ""
    else if not ((snd d).is_exported || td.decl_name.td_entrypoint)
    then ""
    else print_type_decl_signature mname d
  | Output_type _
  | Output_type_expr _ _
  | Extern_type _
  | Extern_fn _ _ _ -> ""

let has_output_types (ds:list decl) : bool =
  List.Tot.existsb (fun (d, _) -> Output_type_expr? d) ds

let has_extern_types (ds:list decl) : bool =
  List.Tot.existsb (fun (d, _) -> Extern_type? d) ds

let has_extern_functions (ds:list decl) : bool =
  List.Tot.existsb (fun (d, _) -> Extern_fn? d) ds

let external_api_include (modul:string) (ds:list decl) : string =
  if has_output_types ds || has_extern_types ds || has_extern_functions ds
  then Printf.sprintf "open %s.ExternalAPI\n\n" modul
  else ""

let print_decls (modul: string) (ds:list decl) =
  let decls =
  Printf.sprintf
    "module %s\n\
     open EverParse3d.Prelude\n\
     open EverParse3d.Actions.All\n\
     %s\
     include %s.Types\n\n\
     #set-options \"--using_facts_from '* FStar EverParse3d.Prelude -FStar.Tactics -FStar.Reflection -LowParse'\"\n\
     %s"
     modul
     (external_api_include modul ds)
     modul
     (String.concat "\n////////////////////////////////////////////////////////////////////////////////\n"
       (ds |> List.map (print_decl_for_validators modul)
           |> List.filter (fun s -> s <> "")))
  in
  decls

let print_types_decls (modul:string) (ds:list decl) =
  let decls =
  Printf.sprintf
    "module %s.Types\n\
     open EverParse3d.Prelude\n\
     open EverParse3d.Actions.All\n\n\
     %s\
     #set-options \"--fuel 0 --ifuel 0 --using_facts_from '* -FStar.Tactics -FStar.Reflection -LowParse'\"\n\n\
     %s"
     modul
     (external_api_include modul ds)
     (String.concat "\n////////////////////////////////////////////////////////////////////////////////\n" 
       (ds |> List.map (print_decl_for_types modul)
           |> List.filter (fun s -> s <> "")))
  in
  decls

let print_decls_signature (mname: string) (ds:list decl) =
  let decls =
    Printf.sprintf
    "module %s\n\
     open EverParse3d.Prelude\n\
     open EverParse3d.Actions.All\n\
     %s\
     include %s.Types\n\n\
     %s"
     mname
     (external_api_include mname ds)
     mname
     (String.concat "\n" (ds |> List.map (print_decl_signature mname) |> List.filter (fun s -> s <> "")))
  in
  // let dummy =
  //     "let retain (x:result) : Tot (FStar.UInt64.t & bool) = field_id_of_result x, result_is_error x"
  // in
  decls // ^ "\n" ^ dummy

#push-options "--z3rlimit_factor 4"
let pascal_case name : ML string =
  let chars = String.list_of_string name in
  let has_underscore = List.mem '_' chars in
  let keep, up, low = 0, 1, 2 in
  if has_underscore then
    let what_next : ref int = alloc up in
    let rewrite_char c : ML (list FStar.Char.char) =
      match c with
      | '_' ->
        what_next := up;
        []
      | c ->
        let c_next =
          let n = !what_next in
          if n = keep then c
          else if n = up then FStar.Char.uppercase c
          else FStar.Char.lowercase c
        in
        let _ =
          if Char.uppercase c = c
          then what_next := low
          else if Char.lowercase c = c
          then what_next := keep
        in
        [c_next]
    in
    let chars = List.collect rewrite_char (String.list_of_string name) in
    String.string_of_list chars
  else if String.length name = 0
  then name
  else String.uppercase (String.sub name 0 1) ^ String.sub name 1 (String.length name - 1)

let rec print_as_c_type (t:typ) : ML string =
    let open Ast in
    match t with
    | T_pointer t ->
          Printf.sprintf "%s*" (print_as_c_type t)
    | T_app {v={name="Bool"}} _ [] ->
          "BOOLEAN"
    | T_app {v={name="UINT8"}} _ [] ->
          "uint8_t"
    | T_app {v={name="UINT16"}} _ [] ->
          "uint16_t"
    | T_app {v={name="UINT32"}} _ [] ->
          "uint32_t"
    | T_app {v={name="UINT64"}} _ [] ->
          "uint64_t"
    | T_app {v={name="PUINT8"}} _ [] ->
          "uint8_t*"
    | T_app {v={name=x}} KindSpec [] ->
          x
    | T_app {v={name=x}} _ [] ->
          pascal_case x
    | _ ->
         "__UNKNOWN__"

let error_code_macros = 
   //To be kept consistent with EverParse3d.ErrorCode.error_reason_of_result
   "#define EVERPARSE_ERROR_GENERIC 1uL\n\
    #define EVERPARSE_ERROR_NOT_ENOUGH_DATA 2uL\n\
    #define EVERPARSE_ERROR_IMPOSSIBLE 3uL\n\
    #define EVERPARSE_ERROR_LIST_SIZE_NOT_MULTIPLE 4uL\n\
    #define EVERPARSE_ERROR_ACTION_FAILED 5uL\n\
    #define EVERPARSE_ERROR_CONSTRAINT_FAILED 6uL\n\
    #define EVERPARSE_ERROR_UNEXPECTED_PADDING 7uL\n"

let print_c_entry (modul: string)
                  (env: global_env)
                  (ds:list decl)
    : ML (string & string)
    =  let default_error_handler =
         "static\n\
          void DefaultErrorHandler(\n\t\
                              const char *typename_s,\n\t\
                              const char *fieldname,\n\t\
                              const char *reason,\n\t\
                              uint64_t error_code,\n\t\
                              uint8_t *context,\n\t\
                              EverParseInputBuffer input,\n\t\
                              uint64_t start_pos)\n\
          {\n\t\
            EverParseErrorFrame *frame = (EverParseErrorFrame*)context;\n\t\
            EverParseDefaultErrorHandler(\n\t\t\
              typename_s,\n\t\t\
              fieldname,\n\t\t\
              reason,\n\t\t\
              error_code,\n\t\t\
              frame,\n\t\t\
              input,\n\t\t\
              start_pos\n\t\
            );\n\
          }" 
   in
   let input_stream_binding = Options.get_input_stream_binding () in
   let is_input_stream_buffer = HashingOptions.InputStreamBuffer? input_stream_binding in
   let wrapped_call_buffer name params =
     Printf.sprintf
       "EverParseErrorFrame frame;\n\t\
       frame.filled = FALSE;\n\t\
       %s\
       uint64_t result = %s(%s (uint8_t*)&frame, &DefaultErrorHandler, base, len, 0);\n\t\
       if (EverParseIsError(result))\n\t\
       {\n\t\t\
         if (frame.filled)\n\t\t\
         {\n\t\t\t\
           %sEverParseError(frame.typename_s, frame.fieldname, frame.reason);\n\t\t\
         }\n\t\t\
         return FALSE;\n\t\
       }\n\t\
       return TRUE;"
       (if is_input_stream_buffer then ""
        else "EverParseInputBuffer input = EverParseMakeInputBuffer(base);\n\t")
       name
       params
       modul
   in
   let wrapped_call_stream name params =
     Printf.sprintf
       "EverParseErrorFrame frame =\n\t\
             { .filled = FALSE,\n\t\
               .typename_s = \"UNKNOWN\",\n\t\
               .fieldname =  \"UNKNOWN\",\n\t\
               .reason =   \"UNKNOWN\",\n\t\
               .error_code = 0uL\n\
             };\n\
       EverParseInputBuffer input = EverParseMakeInputBuffer(base);\n\t\
       uint64_t result = %s(%s (uint8_t*)&frame, &DefaultErrorHandler, input, 0);\n\t\
       uint64_t parsedSize = EverParseGetValidatorErrorPos(result);\n\
       if (EverParseIsError(result))\n\t\
       {\n\t\t\
           EverParseHandleError(_extra, parsedSize, frame.typename_s, frame.fieldname, frame.reason, frame.error_code);\n\t\t\
       }\n\t\
       EverParseRetreat(_extra, base, parsedSize);\n\
       return parsedSize;"
       name
       params
   in
   let mk_param (name: string) (typ: string) : Tot param =
     (A.with_range (A.to_ident' name) A.dummy_range, T_app (A.with_range (A.to_ident' typ) A.dummy_range) A.KindSpec [])
   in
   let print_one_validator (d:type_decl) : ML (string & string) =
    let params = 
      d.decl_name.td_params @
      (if is_input_stream_buffer then [] else [mk_param "_extra" "EverParseExtraT"])
    in
    let print_params (ps:list param) : ML string =
      let params =
        String.concat
          ", "
          (List.map
            (fun (id, t) -> Printf.sprintf "%s %s" (print_as_c_type t) (print_ident id))
            ps)
       in
       match ps with
       | [] -> params
       | _ -> params ^ ", "
    in
    let print_arguments (ps:list param) : Tot string =
      let params =
        String.concat
          ", "
          (List.Tot.map
            (fun (id, t) ->
             if is_output_type t  //output type pointers are uint8_t* in the F* generated code
             then (print_ident id)
             else print_ident id)
            ps)
       in
       match ps with
       | [] -> params
       | _ -> params ^ ", "
    in
    let wrapper_name =
      Printf.sprintf "%s_check_%s"
        modul
        d.decl_name.td_name.A.v.A.name
      |> pascal_case
    in
    let signature =
      if is_input_stream_buffer 
      then Printf.sprintf "BOOLEAN %s(%suint8_t *base, uint32_t len)"
             wrapper_name
            (print_params params)
      else Printf.sprintf "uint64_t %s(%sEverParseInputStreamBase base)"
             wrapper_name
             (print_params params)
    in
    let validator_name =
       Printf.sprintf "%s_validate_%s"
         modul
         d.decl_name.td_name.A.v.A.name
       |> pascal_case
    in
    let impl =
      let body = 
        if is_input_stream_buffer
        then wrapped_call_buffer validator_name (print_arguments params)
        else wrapped_call_stream validator_name (print_arguments params)
      in
      Printf.sprintf "%s {\n\t%s\n}" signature body
    in
    signature ^";",
    impl
  in
  let signatures, impls =
    List.split
      (List.collect
        (fun d ->
          match fst d with
          | Type_decl d ->
            if d.decl_name.td_entrypoint
            then [print_one_validator d]
            else []
          | _ -> [])
        ds)
  in
  let header =
    Printf.sprintf
      "#include \"EverParseEndianness.h\"\n\
       %s\n\
       %s\
       #ifdef __cplusplus\n\
       extern \"C\" {\n\
       #endif\n\
       %s\n\
       #ifdef __cplusplus\n\
       }\n\
       #endif\n"
      error_code_macros
      (if has_output_types ds || has_extern_types ds
       then Printf.sprintf "#include \"%s_ExternalTypedefs.h\"\n" modul
       else "")
      (signatures |> String.concat "\n\n")
  in
  let input_stream_include = HashingOptions.input_stream_include input_stream_binding in
  let header =
    if input_stream_include = ""
    then header
    else Printf.sprintf
      "#include \"%s\"\n\
      %s"
      input_stream_include
      header
  in
  let error_callback_proto =
    if HashingOptions.InputStreamBuffer? input_stream_binding
    then Printf.sprintf "void %sEverParseError(const char *StructName, const char *FieldName, const char *Reason);"
                         modul
    else ""
  in
  let impl =
    Printf.sprintf
      "#include \"%sWrapper.h\"\n\
       #include \"EverParse.h\"\n\
       #include \"%s.h\"\n\
       %s\n\n\
       %s\n\n\
       %s\n"
      modul
      modul
      error_callback_proto
      default_error_handler
      (impls |> String.concat "\n\n")
  in
  let impl =
    if input_stream_include = ""
    then impl
    else
      Printf.sprintf
        "#include \"%s\"\n\
        %s"
        input_stream_include
        impl
  in
  header,
  impl


/// Functions for printing setters and getters for output expressions

let rec out_bt_name (t:typ) : ML string =
  match t with
  | T_app i _ _ -> A.ident_name i
  | T_pointer t -> out_bt_name t
  | _ -> failwith "Impossible, out_bt_name received a non output type!"

let out_expr_bt_name (oe:output_expr) : ML string = out_bt_name oe.oe_bt

(*
 * Walks over the output expressions AST and constructs a string
 *)
let rec out_fn_name (oe:output_expr) : ML string =
  match oe.oe_expr with
  | T_OE_id _ -> out_expr_bt_name oe
  | T_OE_star oe -> Printf.sprintf "%s_star" (out_fn_name oe)
  | T_OE_addrof oe -> Printf.sprintf "%s_addrof" (out_fn_name oe)
  | T_OE_deref oe f -> Printf.sprintf "%s_deref_%s" (out_fn_name oe) (A.ident_name f)
  | T_OE_dot oe f -> Printf.sprintf "%s_dot_%s" (out_fn_name oe) (A.ident_name f)

module H = Hashtable
type set = H.t string unit

(*
 * In the printing functions, a hashtable tracks that we print a defn. only once
 *
 * E.g. multiple output expressions may require a val decl. for types,
 *   we need to print them only once each
 *)

let rec base_output_type (t:typ) : ML A.ident =
  match t with
  | T_app id A.KindOutput [] -> id
  | T_pointer t -> base_output_type t
  | _ -> failwith "Target.base_output_type called with a non-output type"

let rec print_output_type_val (tbl:set) (t:typ) : ML string =
  let open A in
  if is_output_type t
  then let s = print_output_type false t in
       if H.try_find tbl s <> None then ""
       else let _ = H.insert tbl s () in
            match t with
            | T_app id KindOutput [] ->
              Printf.sprintf "\n\nval %s : Type0\n\n" s
            | T_pointer bt ->
              let bs = print_output_type_val tbl bt in
              bs ^ (Printf.sprintf "\n\ntype %s = bpointer %s\n\n" s (print_output_type false bt))
  else ""

// let print_output_type_c_typedef (tbl:set) (t:typ) : ML string =
//   if is_output_type t
//   then let s = pascal_case (print_output_type t) in
//        match H.try_find tbl s with
//        | Some _ -> ""
//        | None ->
//          H.insert tbl s ();
//          Printf.sprintf "\n\ntypedef %s %s;\n\n"
//            (print_as_c_type t)
//            s
//   else ""

let rec print_out_expr' (oe:output_expr') : ML string =
  match oe with
  | T_OE_id id -> A.ident_to_string id
  | T_OE_star o -> Printf.sprintf "*(%s)" (print_out_expr' o.oe_expr)
  | T_OE_addrof o -> Printf.sprintf "&(%s)" (print_out_expr' o.oe_expr)
  | T_OE_deref o i -> Printf.sprintf "(%s)->%s" (print_out_expr' o.oe_expr) (A.ident_to_string i)
  | T_OE_dot o i -> Printf.sprintf "(%s).%s" (print_out_expr' o.oe_expr) (A.ident_to_string i)


(*
 * F* val for the setter for the output expression
 *)

let print_out_expr_set_fstar (tbl:set) (mname:string) (oe:output_expr) : ML string =
  let fn_name = Printf.sprintf "set_%s" (out_fn_name oe) in
  match H.try_find tbl fn_name with
  | Some _ -> ""
  | _ ->
    H.insert tbl fn_name ();
    //TODO: module name?
    let fn_arg1_t = print_typ mname oe.oe_bt in
    let fn_arg2_t =
      (*
       * If bitwidth is not None,
       *   then output the size restriction in the refinement
       * Is there a better way to output it?
       *)
      if oe.oe_bitwidth = None
      then print_typ mname oe.oe_t
      else begin
        Printf.sprintf "(i:%s{FStar.UInt.size (FStar.Integers.v i) %d})"
          (print_typ mname oe.oe_t)
          (Some?.v oe.oe_bitwidth)
      end in
    Printf.sprintf
        "\n\nval %s (_:%s) (_:%s) : external_action output_loc\n\n"
        fn_name
        fn_arg1_t
        fn_arg2_t

let rec base_id_of_output_expr (oe:output_expr) : A.ident =
  match oe.oe_expr with
  | T_OE_id id -> id
  | T_OE_star oe
  | T_OE_addrof oe
  | T_OE_deref oe _
  | T_OE_dot oe _ -> base_id_of_output_expr oe

(*
 * C defn. for the setter for the output expression
 *)

let print_out_expr_set (tbl:set) (oe:output_expr) : ML string =
  let fn_name = pascal_case (Printf.sprintf "set_%s" (out_fn_name oe)) in
  match H.try_find tbl fn_name with
  | Some _ -> ""
  | _ ->
    H.insert tbl fn_name ();
    let fn_arg1_t = print_as_c_type oe.oe_bt in
    let fn_arg1_name = base_id_of_output_expr oe in
    let fn_arg2_t = print_as_c_type oe.oe_t in
    let fn_arg2_name = "__v" in
    let fn_body = Printf.sprintf
      "%s = %s;"
      (print_out_expr' oe.oe_expr)
      fn_arg2_name in
    let fn = Printf.sprintf
      "void %s (%s %s, %s %s){\n    %s;\n}\n"
      fn_name
      fn_arg1_t
      (A.ident_name fn_arg1_name)
      fn_arg2_t
      fn_arg2_name
      fn_body in
    Printf.sprintf "\n\n%s\n\n" fn

(*
 * F* val for the getter for the output expression
 *)

let print_out_expr_get_fstar (tbl:set) (mname:string) (oe:output_expr) : ML string =
  let fn_name = Printf.sprintf "get_%s" (out_fn_name oe) in
  match H.try_find tbl fn_name with
  | Some _ -> ""
  | _ ->
    H.insert tbl fn_name ();
    let fn_arg1_t = print_typ mname oe.oe_bt in
    let fn_res = print_typ mname oe.oe_t in  //No bitfields, we could enforce?
    Printf.sprintf "\n\nval %s : %s -> %s\n\n" fn_name fn_arg1_t fn_res

(*
 * C defn. for the getter for the output expression
 *)

let print_out_expr_get(tbl:set) (oe:output_expr) : ML string =
  let fn_name = pascal_case (Printf.sprintf "get_%s" (out_fn_name oe)) in
  match H.try_find tbl fn_name with
  | Some _ -> ""
  | _ ->
    H.insert tbl fn_name ();
    let fn_arg1_t = print_as_c_type oe.oe_bt in
    let fn_arg1_name = base_id_of_output_expr oe in
    let fn_res = print_as_c_type oe.oe_t in
    let fn_body = Printf.sprintf "return %s;" (print_out_expr' oe.oe_expr) in
    let fn = Printf.sprintf "%s %s (%s %s){\n    %s;\n}\n"
      fn_res
      fn_name
      fn_arg1_t
      (A.ident_name fn_arg1_name)
      fn_body in
    Printf.sprintf "\n\n%s\n\n" fn

let output_setter_name lhs = Printf.sprintf "set_%s" (out_fn_name lhs)
let output_getter_name lhs = Printf.sprintf "get_%s" (out_fn_name lhs)
let output_base_var lhs = base_id_of_output_expr lhs

let print_external_api_fstar (modul:string) (ds:decls) : ML string =
  let tbl = H.create 10 in
  let s = String.concat "" (ds |> List.map (fun d ->
    match fst d with
    | Output_type_expr oe is_get ->
      Printf.sprintf "%s%s%s"
        (print_output_type_val tbl oe.oe_bt)
        (print_output_type_val tbl oe.oe_t)
        (if not is_get then print_out_expr_set_fstar tbl modul oe
         else print_out_expr_get_fstar tbl modul oe)
    | Extern_type i ->
      Printf.sprintf "\n\nval %s : Type0\n\n" (print_ident i)
    | Extern_fn f ret params ->
      Printf.sprintf "\n\nval %s %s (_:unit) : Stack unit (fun _ -> True) (fun h0 _ h1 -> B.modifies output_loc h0 h1)\n\n"
        (print_ident f)
        (String.concat " " (params |> List.map (fun (i, t) -> Printf.sprintf "(%s:%s)"
          (print_ident i)
          (print_typ modul t))))
    | _ -> "")) in
   Printf.sprintf
    "module %s.ExternalAPI\n\n\
     open FStar.HyperStack.ST\n\    
     open EverParse3d.Prelude\n\
     open EverParse3d.Actions.All\n\
     noextract val output_loc : eloc\n\n%s"
    modul
    s

let print_external_api_fstar_interpreter (modul:string) (ds:decls) : ML string =
  let tbl = H.create 10 in
  let s = String.concat "" (ds |> List.map (fun d ->
    match fst d with
    | Output_type_expr oe is_get ->
      Printf.sprintf "%s%s%s"
        (print_output_type_val tbl oe.oe_bt)
        (print_output_type_val tbl oe.oe_t)
        (if not is_get then print_out_expr_set_fstar tbl modul oe
         else print_out_expr_get_fstar tbl modul oe)
    | Extern_type i ->
      Printf.sprintf "\n\nval %s : Type0\n\n" (print_ident i)
    | Extern_fn f ret params ->
      Printf.sprintf "\n\nval %s %s : external_action output_loc\n"
        (print_ident f)
        (String.concat " " (params |> List.map (fun (i, t) -> Printf.sprintf "(%s:%s)"
          (print_ident i)
          (print_typ modul t))))
    | _ -> "")) in
   Printf.sprintf
    "module %s.ExternalAPI\n\n\
     open EverParse3d.Prelude\n\
     open EverParse3d.Actions.All\n\
     noextract val output_loc : eloc\n\n%s"
     modul
    s

let print_out_exprs_c modul (ds:decls) : ML string =
  let tbl = H.create 10 in
  (Printf.sprintf
     "#include<stdint.h>\n\n\
      #include \"%s_ExternalTypedefs.h\"\n\n\
      #if defined(__cplusplus)\n\
      extern \"C\" {\n\
      #endif\n\n"
     modul)
  ^
  (String.concat "" (ds |> List.map (fun d ->
     match fst d with
     | Output_type_expr oe is_get ->
       if not is_get then print_out_expr_set tbl oe
       else print_out_expr_get tbl oe
    | _ -> "")))
  ^
  ("#if defined(__cplusplus)\n\
    }\n\
   #endif\n\n")

let rec atyp_to_ttyp (t:A.typ) : ML typ =
  match t.v with
  | A.Pointer t ->
    let t = atyp_to_ttyp t in
    T_pointer t
  | A.Type_app hd _b _args ->
    T_app hd _b []

let rec print_output_types_fields (flds:list A.out_field) : ML string =
  List.fold_left (fun s fld ->
    let fld_s =
      match fld with
      | A.Out_field_named id t bopt ->
        Printf.sprintf "%s    %s%s;\n"
          (print_as_c_type (atyp_to_ttyp t))
          (A.ident_name id)
          (match bopt with
           | None -> ""
           | Some n -> ":" ^ (string_of_int n))
      | A.Out_field_anon flds is_union ->
        Printf.sprintf "%s  {\n %s };\n"
          (if is_union then "union" else "struct")
          (print_output_types_fields flds) in
    s ^ fld_s) "" flds

let print_out_typ (ot:A.out_typ) : ML string =
  let open A in
  Printf.sprintf
    "\ntypedef %s %s {\n%s\n} %s;\n"
    (if ot.out_typ_is_union then "union" else "struct")
    (pascal_case (A.ident_name ot.out_typ_names.typedef_name))
    (print_output_types_fields ot.out_typ_fields)
    (pascal_case (A.ident_name ot.out_typ_names.typedef_name))

let print_output_types_defs (modul:string) (ds:decls) : ML string =
  let defs =
    String.concat "\n\n" (List.map (fun (d, _) ->
      match d with
      | Output_type ot -> print_out_typ ot
      | _ -> "") ds) in

  Printf.sprintf
    "#ifndef __%s_OutputTypesDefs_H\n\
     #define __%s_OutputTypesDefs_H\n\n\
     #if defined(__cplusplus)\n\
     extern \"C\" {\n\
     #endif\n\n\n\
     %s\n\n\n\
     #if defined(__cplusplus)\n\
     }\n\
     #endif\n\n\
     #define __%s_OutputTypes_H_DEFINED\n\
     #endif\n"

    modul
    modul
    defs
    modul
