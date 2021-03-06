(** Tail expression terms. This interface exposes the structure of
    TAIL expressions. It also provides evaluation and type
    checking/inference functionality.
*)

signature TAIL_EXP = sig
  
  structure T : TAIL_TYPE

  type rnk = T.rnk
  type typ = T.typ
  type var = string
  type opr = string
  datatype exp =
           Var of var * typ
         | I of int
         | D of real
         | B of bool
         | Iff of exp * exp * exp * typ
         | Vc of exp list * typ
         | Op of opr * exp list * typ
         | Let of var * typ * exp * exp * typ
         | Fn of var * typ * exp * typ

  type env
  val lookup   : env -> var -> typ option
  val empEnv   : env
  val add      : env -> var -> typ -> env

  datatype 't report = OK of 't | ERR of string
  val typeExp  : env -> exp -> typ report
  val resolveShOpr : exp -> exp

  val Iff_e    : exp * exp * exp -> exp
  val Vc_e     : exp list -> exp
  val Op_e     : opr * exp list -> exp
  val Let_e    : var * typ * exp * exp -> exp
  val Fn_e     : var * typ * exp -> exp
  val typeOf   : exp -> typ

  type value
  type denv
  val empDEnv  : denv
  val addDE    : denv -> var -> value -> denv
  val pr_value : value -> string
  val Dvalue   : real -> value
  val unDvalue : value -> real
  val Uvalue   : value

  val eval : denv -> exp -> value
  
end
