functor TailExp(T : TAIL_TYPE) : TAIL_EXP = struct
  structure T = T
  open T
  type var = string
  type opr = string

  (* General feature functions *)
  fun qq s = "'" ^ s ^ "'" 
  fun curry f x y = f (x,y)
  fun isIn s xs = List.exists (curry (op =) s) xs
                           
  (* Some type utilities *)
  fun unScl s t =
      case unArr t of
          SOME (bt,r) => (case unifyR r (rnk 0) of
                              SOME s' => raise Fail (s' ^ " in " ^ s)
                            | NONE => bt)
        | NONE =>
          case unSi t of
              SOME _ => IntB
            | NONE => 
              let val bt = TyVarB()
              in case unify t (Arr bt (rnk 0)) of
                     SOME s' => raise Fail (s' ^ " in " ^ s)
                   | NONE => bt
              end

  fun unBinFun s ty =
      let fun err t = 
              raise Fail ("expected function type, but got " ^ prType t)
      in case unFun ty of
             SOME (t1,t) =>
             (case unFun t of
                  SOME(t2,t3) => (unScl "first function argument" t1,
                                  unScl "second function argument" t2,
                                  unScl "function result" t3)
                | NONE => err t)
           | NONE => err ty
      end

  fun unArr' s t =
      case unArr t of
          SOME p => p
        | NONE =>
          (case unSh t of
               SOME _ => (IntB,rnk 1)
             | NONE => 
               (case unVi t of
                    SOME _ => (IntB,rnk 1)
                  | NONE => 
                    let val tv = TyVarB()
                        val r = RnkVar()
                    in case unify t (Arr tv r) of
                           NONE => (tv,r)
                         | SOME _ => 
                           raise Fail ("expecting array type, but got "
                                       ^ prType t ^ " in " ^ s)
                    end))

  fun unFun' s t =
      case unFun t of
          SOME (t1,t2) => (unScl s t1, unScl s t2)
        | NONE => raise Fail ("expecting function type, but got "
                              ^ prType t ^ " in " ^ s)

  (* Expressions *)

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

  (* Environments *)
  type env = (var * typ) list

  val empEnv = nil

  fun lookup e v =
      case e of
          nil => NONE
        | (x,t)::e => if x = v then SOME t
                      else lookup e v

  fun add e v t = (v,t)::e

  (* Typing *)

  fun assert0 unify s t1 t2 =
      case unify t1 t2 of
          SOME s' => raise Fail (s' ^ " in " ^ s)
        | NONE => ()

  val assert = assert0 unify
  val assertR = assert0 unifyR
  val assertB = assert0 unifyB
  
  val assert_sub = assert0 subtype

  fun isBinOpIII opr =
      isIn opr ["addi","subi","muli","divi","maxi","mini","mod"]

  fun isBinOpDDD opr =
      isIn opr ["addd","subd","muld","divd","maxd","mind"]

  fun isBinOpIIB opr =
      isIn opr ["lti","leqi","eqi"]

  fun isBinOpDDB opr =
      isIn opr ["ltd","leqd","eqd"]

  fun isInt' t =
      case unArr t of
          SOME (bt,r) => (case unRnk r of
                              SOME 0 => isInt bt
                            | _ => false)
        | NONE => case unSi t of
                      SOME _ => true
                    | NONE => false

  fun tyVc ts =
      case ts of
          nil => Arr (TyVarB()) (rnk 1)
        | _ => 
          let val oneInt = List.foldl (fn (e,a) => a orelse isInt' e) false ts
              val t1 = hd ts
              val () = if oneInt then List.app (fn t => assert_sub "vector" t Int) ts
                       else List.app (fn t => assert "vector" t t1) (tl ts)
          in if oneInt then 
               case ts of
                   [t] => (case unSi t of
                               SOME r => Vi r
                             | NONE => Sh(rnk(length ts)))
                 | _ => Sh(rnk(length ts))
             else let val (b,r) = unArr' "vector expression" t1
                      val () = assertR "vector expression" r (rnk 0)
                  in Arr b (rnk 1)                    (* vector type *)
                  end
          end

  fun unShi t =
      case unSh t of
          SOME r => unRnk r
        | NONE => case unVi t of
                      SOME _ => SOME 1
                    | NONE => NONE

  fun unSii t =
      case unSi t of
          NONE => NONE
        | SOME r => unRnk r

  fun conssnoc sh opr t1 t2 =
      let fun default() =
              if sh then raise Fail (opr ^ "expects argument of shape type")
              else let val (b1,r1) = unArr' ("argument to " ^ opr) t1
                       val (b2,r2) = unArr' ("argument to " ^ opr) t2
                       val rv = RnkVarCon (fn i => unifyR r2 (rnk(i+1)))
                   in assertR ("arguments to " ^ opr) rv r1
                    ; assertB ("arguments to " ^ opr) b1 b2
                    ; t2
                   end
      in case unShi t2 of
             SOME r2 => (assert_sub opr t1 Int; Sh(rnk(r2+1)))
           | NONE => default()
      end

  fun type_first sh t =
      let fun default() = 
              if sh then raise Fail "firstSh expects argument of shape type"
              else let val (bt,_) = unArr' "disclose argument" t
                   in Arr bt (rnk 0)
                   end
      in case unVi t of
             SOME r => Si r
           | NONE =>
             case unSh t of
                 SOME _ => Int
               | NONE => default()
      end

  fun type_cat sh t1 t2 =
      let fun default() =
              if sh then raise Fail "catSh expects arguments of shape types"
              else let val (bt1,r1) = unArr' "first argument to catenate" t1
                       val (bt2,r2) = unArr' "second argument to catenate" t2
                   in assertB "cat" bt1 bt2
                    ; assertR "cat" r1 r2
                    ; Arr bt1 r1
                   end
      in case (unShi t1, unShi t2) of
             (SOME i1, SOME i2) => Sh(rnk(i1 + i2))
           | _ => default()
      end

  fun max (a:int) b = if a > b then a else b
  fun abs (a:int) = if a > 0 then a else ~ a

  fun type_drop sh t1 t2 =
      let fun default () =
              if sh then raise Fail "dropSh expects arguments of singleton type and shape type"
              else let val (bt,r) = unArr' "drop" t2;
                   in assert_sub "first argument to drop" t1 Int; 
                      Arr bt r
                   end
      in case (unSii t1, unShi t2) of
             (SOME r1, SOME r2) => Sh (rnk(max 0 (r2-abs r1)))
           | _ => default()
      end

  fun type_take sh t1 t2 =
      let fun default () =
              if sh then raise Fail "takeSh expects arguments of singleton and shape types"
              else (assert "take" t2 (Arr(TyVarB())(RnkVar()));            
                    t2)
      in case unSii t1 of
             SOME r => (case unArr t2 of
                            SOME (bt, _) => if isInt bt then Sh(rnk(abs r))
                                            else t2
                          | NONE => 
                            case unShi t2 of
                                SOME _ => Sh(rnk(abs r))
                              | NONE => default())
           | NONE => (assert "first argument to take" Int t1;
                      default())
      end

  fun tyOp opr ts =
      case (opr, ts) of
          ("zilde", nil) => tyVc nil
        | ("iota", [t]) =>
          (case unSi t of
               SOME n => Sh n
             | NONE => (assert_sub "iota expression" t Int;
                        Arr IntB (rnk 1)))
        | ("shape", [t]) =>
          (case unSh t of
               SOME n => Vi n
             | NONE => 
               let val (_,r) = unArr' "shape argument" t
               in Sh r
               end)
        | ("reshape", [t1,t2]) =>
          let val (bt,_) = unArr' "second argument to reshape" t2
              val r = RnkVar()
          in assert "first argument to reshape" (Sh r) t1;
             Arr bt r
          end
        | ("take",[t1,t2]) => type_take false t1 t2
        | ("takeSh",[t1,t2]) => type_take true t1 t2
        | ("drop",[t1,t2]) => type_drop false t1 t2
        | ("dropSh",[t1,t2]) => type_drop true t1 t2
        | ("cat",[t1,t2]) => type_cat false t1 t2
        | ("catSh",[t1,t2]) => type_cat true t1 t2
        | ("cons",[t1,t2]) => conssnoc false opr t1 t2
        | ("consSh",[t1,t2]) => conssnoc true opr t1 t2
        | ("snoc",[t1,t2]) => conssnoc false opr t2 t1
        | ("snocSh",[t1,t2]) => conssnoc true opr t2 t1
        | ("first",[t]) => type_first false t
        | ("firstSh",[t]) => type_first true t
        | ("reverse",[t]) => (unArr' "reverse" t; t)
        | ("transp",[t]) => (unArr' "transp" t; t)
        | ("transp2",[t1,t2]) =>
          let val (bt,r) = unArr' "transp2" t2
          in assert "first argument to transpose2" (Sh r) t1;
             t2
          end
        | ("rotate",[t1,t2]) =>
          (unArr' "rotate" t2;
           assert_sub "first argument to rotate" t1 Int;
           t2)
        | ("zipWith",[tf,t1,t2]) =>
          let val (bt1,bt2,bt) = unBinFun "first argument to zipWith" tf
              val (bt1',r1) = unArr' "zipWith first argument" t1
              val (bt2',r2) = unArr' "zipWith second argument" t2
          in assertB "first argument to zipWith" bt1 bt1'
           ; assertB "second argument to zipWith" bt2 bt2'
           ; assertR "zipWith argument ranks" r1 r2
           ; Arr bt r1
          end
        | ("reduce", [tf,tn,tv]) =>
          let val (bt1,bt2,bt) = unBinFun "first argument to reduce" tf
              val btn = unScl "reduce neutral element" tn
              val (btv,r) = unArr' "reduce argument" tv
              val () = List.app (assertB "reduce function" btn) [bt1,bt2,bt,btv]
              val rv = RnkVarCon (fn i => unifyR r (rnk(i+1)))
              val rv' = RnkVarCon (fn i => unifyR rv (rnk(i-1)))
          in assertR "reduce" rv' r
           ; Arr bt rv
          end
        | ("each", [tf,tv]) =>
          let val (bt,r) = unArr' "each" tv
              val (bt1,bt2) = unFun' "first argument to each" tf
          in assertB "each elements" bt1 bt;
             Arr bt2 r
          end
        | ("prod",[tf,tg,tn,t1,t2]) =>
          let val t = unScl "prod neutral element" tn
              val (f1,f2,f3) = unBinFun "first argument to prod" tf
              val (g1,g2,g3) = unBinFun "second argument to prod" tg
              val (v1t,r1) = unArr' "prod" t1
              val (v2t,r2) = unArr' "prod" t2
              val () = List.app (fn (t1,t2) => assertB "prod" t1 t2) 
                                [(f1,f2),(f2,f3),(f3,t),
                                 (g1,g2),(g2,g3),(g3,t),
                                 (v1t,v2t),(v2t,t)]
              val rv = RnkVar()
              val rv1 = RnkVarCon (fn i1 =>
                                      let val rv2 = RnkVarCon (fn i2 =>
                                                                  let val r = i1 + i2 - 2
                                                                  in if r < 0 then SOME "Negative rank for prod"
                                                                     else unifyR rv (rnk r)
                                                                  end)
                                      in unifyR rv2 r2
                                      end)
          in assertR "rank for prod" r1 rv1;
             Arr t rv
          end
        | ("i2d",[t]) => (assert_sub opr t Int; Double)
        | ("negi",[t]) => 
          let fun default() = (assert_sub opr t Int; Int)
          in case unSii t of
                 NONE => default()
               | SOME i => Si (rnk(~i))
          end
        | ("negd",[t]) => (assert opr Double t; Double)
        | ("iotaSh",[t]) =>
          (case unSi t of
               SOME r => Sh r
             | NONE => raise Fail (opr ^ " expects argument of singleton type"))
        | ("shapeSh", [t]) => 
          (case unSh t of
               SOME n => Vi n
             | NONE => raise Fail "shapeSh expects argument of shape type")
        | ("rotateSh",[t1,t2]) =>
          (assert_sub opr t1 Int;           
           case unSh t2 of
               SOME _ => t2
             | NONE => raise Fail (opr ^ " expects second argument to be a shape type"))
        | (_,[t1,t2]) =>
          if isBinOpIII opr then tyBin Int Int Int opr t1 t2
          else if isBinOpDDD opr then tyBin Double Double Double opr t1 t2
          else if isBinOpIIB opr then tyBin Int Int Bool opr t1 t2
          else if isBinOpDDB opr then tyBin Double Double Bool opr t1 t2
          else raise Fail ("binary operator " ^ qq opr ^ " not supported")
        | _ => raise Fail ("operator " ^ qq opr ^ ", with " 
                           ^ Int.toString (length ts) 
                           ^ " arguments, not supported")
  and tyBin t1 t2 t3 opr t1' t2' =
      (assert_sub ("first argument to " ^ opr) t1' t1;
       assert_sub ("second argument to " ^ opr) t2' t2;
       t3)

  fun tyIff (tc,t1,t2) =
      ( assert "conditional expression" Bool tc
      ; assert "else-branch" t1 t2
      ; t1)

  datatype 't report = OK of 't | ERR of string
  fun typeExp (E:env) e : typ report =
      let fun ty E e =
              case e of
                  Var(v, t0) => (case lookup E v of
                                     SOME t => (assert "var" t t0; t)
                                  |  NONE => raise Fail ("Unknown variable " ^ qq v))
                | I n => Si (rnk n)
                | D _ => Double
                | B _ => Bool
                | Iff (c,e1,e2,t0) =>
                  let val t = tyIff(ty E c,ty E e1,ty E e2)
                  in assert "if" t t0
                   ; t0
                  end
                | Vc(es,t0) =>
                  let val ts = List.map (ty E) es
                      val t = tyVc ts
                  in assert_sub "vector expression" t t0
                   ; t0
                  end
                | Let (v,t,e1,e2,t0) =>
                  (assert_sub ("let-binding of " ^ v) (ty E e1) t;
                   let val t' = ty (add E v t) e2
                   in assert "let" t' t0
                    ; t'
                   end)
                | Fn (v,t,e,t0) =>
                  let val t' = ty (add E v t) e
                  in assert "fun" t' t0;
                     Fun(t,t')
                  end
                | Op (opr, es, t0) => 
                  let val ts = List.map (ty E) es
                      val t = tyOp opr ts
                  in assert_sub opr t t0
                   ; t
                  end
      in OK(ty E e) handle Fail s => ERR s
      end

  fun typeOf e : typ =
      case e of
          Var(_,t) => t
        | I i => Si(rnk i)
        | D _ => Double
        | B _ => Bool
        | Iff(_,_,_,t) => t
        | Vc(_,t) => t
        | Op(_,_,t) => t
        | Let(_,_,_,_,t) => t
        | Fn(v,t,e,t') => Fun(t,t')

  fun isShOpr t opr =
    case (opr       , unSi t   , unVi t   , unSh t   ) of
         ("first"   , SOME _   , _        , _        ) => true
      |  ("shape"   , _        , SOME _   , _        ) => true
      |  ("take"    , _        , _        , SOME _   ) => true
      |  ("drop"    , _        , _        , SOME _   ) => true
      |  ("cat"     , _        , _        , SOME _   ) => true
      |  ("cons"    , _        , _        , SOME _   ) => true
      |  ("snoc"    , _        , _        , SOME _   ) => true
      |  ("iota"    , _        , _        , SOME _   ) => true
      |  ("rotate"  , _        , _        , SOME _   ) => true
      | _ => false

  fun prOpr t opr =
      if isShOpr t opr then opr ^ "Sh"
      else opr

  fun resolveShOpr e =
      case e of
          Var _ => e
        | I _ => e
        | D _ => e
        | B _ => e
        | Iff(e1,e2,e3,t) => Iff(resolveShOpr e1,resolveShOpr e2,resolveShOpr e3,t)
        | Vc(es,t) => Vc(List.map resolveShOpr es,t)
        | Op(opr,es,t) => Op(prOpr t opr, List.map resolveShOpr es,t)
        | Let(v,t,e1,e2,t') => Let(v,t,resolveShOpr e1,resolveShOpr e2,t')
        | Fn(v,t,e,t') => Fn(v,t,resolveShOpr e,t')

  fun Iff_e (c,e1,e2) =
      let val t0 = tyIff(typeOf c, typeOf e1, typeOf e2)
      in Iff(c,e1,e2,t0)
      end
         
  fun Vc_e es =
      let val ts = List.map typeOf es
          val t = tyVc ts
      in Vc(es,t)
      end

  fun Op_e (opr,es) =
      let val ts = List.map typeOf es
          val t = tyOp opr ts
      in Op(opr,es,t)
      end

  fun Let_e (v,t,e,e') =
      let val t' = typeOf e'
      in Let(v,t,e,e',t')
      end

  fun Fn_e (v,t,e) =
      let val t' = typeOf e
      in Fn(v,t,e,t')
      end

  datatype bv = Ib of int
              | Db of real
              | Bb of bool
              | Fb of denv * var * typ * exp * typ
  withtype denv = (var * bv Apl.t) list

  type value = bv Apl.t

  fun Dvalue v = Apl.scl (Db v)
  fun unDvalue _ = raise Fail "exp.unDvalue: not implemented"
  val Uvalue = Dvalue 0.0

  fun pr_double d =
      if d < 0.0 then "-" ^ pr_double (~d)
      else if Real.==(d,Real.posInf) then "HUGE_VAL"
      else let val s = Real.toString d
           in if CharVector.exists (fn c => c = #".") s then s
              else s ^ ".0"
           end

  fun pr_bv b =
      case b of
          Ib b => Int.toString b
        | Db b => pr_double b
        | Bb b => Bool.toString b
        | Fb _ => "fn"
                      
  fun pr_value v = Apl.pr pr_bv v

  val empDEnv = nil
  val addDE = add

  fun unIb (Ib b) = b
    | unIb _ = raise Fail "exp.unIb"
  fun unDb (Db b) = b
    | unDb _ = raise Fail "exp.unDb"
  fun unBb (Bb b) = b
    | unBb _ = raise Fail "exp.unBb"
  fun unFb (Fb b) = b
    | unFb _ = raise Fail "exp.unFb"


  fun unBase s t fi fd fb =
      let val (bt,_) = unArr' ("unBase:" ^ s) t
      in if isInt bt then fi()
         else if isDouble bt then fd()
         else if isBool bt then fb()
         else raise Fail ("exp.unBase: expecting base type: " ^ s)
      end

  fun default t =
      unBase "default" t (fn() => Ib 0) (fn() => Db 0.0) (fn() => Bb true)

  fun resType (_,_,_,_,_,_,t) = t

  fun eval DE e : value =
      case e of
          Var(x,_) =>
          (case lookup DE x of
               SOME v => v
             | NONE => raise Fail ("eval.cannot locate variable " ^ x))
        | I i => Apl.scl (Ib i)
        | D d => Apl.scl (Db d)
        | B b => Apl.scl (Bb b)
        | Iff (e1,e2,e3,t) =>
          let val b = Apl.liftU (fn Bb b => b | _ => raise Fail "eval:Iff") (eval DE e1)
          in Apl.iff(b,fn() => eval DE e2, fn() => eval DE e3)
          end
        | Vc (nil,t) => Apl.zilde (default t)
        | Vc (x::xs,t) => eval DE (Op("cons",[x, Vc(xs,t)],t))
        | Op (opr, es, t) =>
          let fun fail() = raise Fail ("exp.eval: operator " ^ opr ^ " not supported with " 
                                       ^ Int.toString (length es) ^ " arguments")
              fun tryShOpr () = if String.isSuffix "Sh" opr then
                                  let val opr' = String.substring(opr,0,size opr-2)
                                  in eval DE (Op(opr',es,t))
                                  end
                                else fail()
          in case (opr,es) of
                 ("zilde", []) => Apl.zilde (default t)
               | ("i2d", [e]) => Apl.liftU (fn Ib i => Db(real i) | _ => raise Fail "eval:i2d") (eval DE e)
               | ("negi", [e]) => Apl.liftU (fn Ib i => Ib(~i) | _ => raise Fail "eval:negi") (eval DE e)
               | ("negd", [e]) => Apl.liftU (fn Db i => Db(Real.~i) | _ => raise Fail "eval:negd") (eval DE e)
               | ("iota", [e]) => Apl.map Ib (Apl.iota (Apl.map unIb (eval DE e)))
               | ("reshape", [e1,e2]) =>
                 let val v1 = Apl.map unIb (eval DE e1)
                 in Apl.reshape(v1,eval DE e2)
                 end
               | ("shape", [e]) =>
                 let val v = Apl.shape(eval DE e)
                 in Apl.map Ib v
                 end
               | ("drop", [e1,e2]) =>
                 let val v1 = Apl.map unIb (eval DE e1)
                 in Apl.drop(v1,eval DE e2)
                 end
               | ("take", [e1,e2]) =>
                 let val v1 = Apl.map unIb (eval DE e1)
                 in Apl.take(v1,eval DE e2)
                 end
               | ("rotate", [e1,e2]) =>
                 let val v1 = Apl.map unIb (eval DE e1)
                 in Apl.rotate(v1,eval DE e2)
                 end
               | ("reverse", [e]) => Apl.reverse (eval DE e)
               | ("first", [e]) => Apl.first (eval DE e)
               | ("transp", [e]) => Apl.transpose (eval DE e)
               | ("transp2", [e1,e2]) =>
                 let val v1 = Apl.map unIb (eval DE e1)
                 in Apl.transpose2(v1,eval DE e2)
                 end
               | ("cons", [e1,e2]) => Apl.cons(eval DE e1,eval DE e2)
               | ("snoc", [e1,e2]) => Apl.snoc(eval DE e1,eval DE e2)
               | ("cat", [e1,e2]) => Apl.catenate(eval DE e1,eval DE e2)
               | ("reduce", [f,n,a]) =>
                 let val F = unFb2 DE "reduce" f
                     val n = eval DE n
                     val a = eval DE a
                 in Apl.reduce (applyBin F) n a
                 end
               | ("each", [e1,e2]) =>
                 let val (DE0,v,t,e,t') = unFb(Apl.unScl"eval:each"(eval DE e1))
                 in Apl.each (default t') (fn y => eval (addDE DE0 v y) e) (eval DE e2)
                 end
               | ("zipWith", [f,e2,e3]) =>
                 let val F = unFb2 DE "zipWith" f
                 in Apl.zipWith (default (resType F)) (applyBin F) (eval DE e2) (eval DE e3)
                 end
               | ("prod",[f,g,n,v1,v2]) =>
                 let val F = unFb2 DE "prod first" f
                     val G = unFb2 DE "prod second" g
                     val n = eval DE n
                     val v1 = eval DE v1
                     val v2 = eval DE v2
                 in Apl.dot (applyBin F) (applyBin G) n v1 v2
                 end
               | (opr,[e1,e2]) =>
                 let val v1 = eval DE e1
                     val v2 = eval DE e2
                 in if isBinOpIII opr then evalBinOpIII opr v1 v2
                    else if isBinOpDDD opr then evalBinOpDDD opr v1 v2
                    else if isBinOpIIB opr then evalBinOpIIB opr v1 v2
                    else if isBinOpDDB opr then evalBinOpDDB opr v1 v2
                    else tryShOpr()
                 end
               | (opr, _) => tryShOpr()
          end
        | Let (v,t,e1,e2,t') => eval (addDE DE v (eval DE e1)) e2
        | Fn (v,t,e,t') => Apl.scl (Fb(DE,v,t,e,t'))
  and unFb2 DE s e =
      let val (DE0,x,tx,e,_) = unFb(Apl.unScl (s ^ ", first function argument") (eval DE e))
          val (_,y,ty,e,t) = unFb(Apl.unScl (s ^ ", second function argument") (eval DE e))
      in (DE0,x,y,e,tx,ty,t)
      end
  and applyBin (DE0,x,y,e,_,_,_) (a,b) =
      let val DE0 = addDE DE0 x a
          val DE0 = addDE DE0 y b
      in eval DE0 e
      end
  and evalBinOpIII opr v1 v2 =
      let val fct = case opr of
                        "addi" => (op +)
                      | "subi" => (op -)
                      | "muli" => (op * )
                      | "divi" => (op div)
                      | "maxi" => (fn (x,y) => if x > y then x else y)
                      | "mini" => (fn (x,y) => if x < y then x else y)
                      | "mod" => (op mod)
                      | _ => raise Fail ("evalBinOpIII: unsupported int*int->int operator " ^ opr)
      in Apl.liftB (fn (b1,b2) => Ib(fct(unIb b1, unIb b2))) (v1,v2)
      end
  and evalBinOpIIB opr v1 v2 =
      let val fct = case opr of
                        "lti" => (op <)
                      | "leqi" => (op <=)
                      | "eqi" => (op =)
                      | _ => raise Fail ("evalBinOpIIB: unsupported int*int->bool operator " ^ opr)
      in Apl.liftB (fn (b1,b2) => Bb(fct(unIb b1, unIb b2))) (v1,v2)
      end
  and evalBinOpDDD opr v1 v2 =
      let val fct = case opr of
                        "addd" => (op +)
                      | "subd" => (op -)
                      | "muld" => (op * )
                      | "divd" => (op /)
                      | "maxd" => (fn (x,y) => if x > y then x else y)
                      | "mind" => (fn (x,y) => if x < y then x else y)
                      | _ => raise Fail ("evalBinOpDDD: unsupported double*double->double operator " ^ opr)
      in Apl.liftB (fn (b1,b2) => Db(fct(unDb b1, unDb b2))) (v1,v2)
      end
  and evalBinOpDDB opr v1 v2 =
      let val fct = case opr of
                        "lti" => (op <)
                      | "leqi" => (op <=)
                      | "eqi" => Real.==
                      | _ => raise Fail ("evalBinOpDDB: unsupported double*double->bool operator " ^ opr)
      in Apl.liftB (fn (b1,b2) => Bb(fct(unDb b1, unDb b2))) (v1,v2)
      end
end
