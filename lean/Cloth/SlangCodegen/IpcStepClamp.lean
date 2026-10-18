import LeanSlang

/-!
# `Cloth.SlangCodegen.IpcStepClamp` — conservative step bound for the IPC barrier

Replaces PolyFEM's CCD-filtered line search with a per-vertex bound: after a VBD solve, a
vertex may move at most `gamma · dMin[v]` from where its iteration started, where `dMin` is its
distance to the nearest body triangle at that start. With `gamma < 0.5` the vertex cannot reach
a triangle within the step, so an intersection-free start stays intersection-free.

Bindings (set 0): 0 positions rw float3, 1 xStart ro float3, 2 dMin ro float, 3 params.
-/

namespace Cloth.SlangCodegen.IpcStepClamp
open LeanSlang

private def f3 : SlangType := .vec .float 3
private def u  : SlangType := .scalar .uint
private def f  : SlangType := .scalar .float
private def v (n : String) : SlangExpr := .var n
private def b (op : String) (x y : SlangExpr) : SlangExpr := .bin op x y
private def prm (n : String) (t : SlangType) : SlangBinding :=
  { name := n, type := t, semantic := Semantic.none, binding := none, space := none }
private def gb (n : Nat) (name : String) (t : SlangType) : SlangBinding :=
  { name := name, type := t, semantic := Semantic.none, binding := some n, space := some 0 }

private def body : List SlangStmt :=
  [ .declInit u "i" (.member (v "tid") "x")
  , .ifNoElse (b ">=" (v "i") (.member (v "params") "count")) [.ret none]
  , .declInit f3 "x0" (.index (v "xStart") (v "i"))
  , .declInit f3 "d" (b "-" (.index (v "positions") (v "i")) (v "x0"))
  , .declInit f "lim" (b "*" (.member (v "params") "gamma") (.index (v "dMin") (v "i")))
  , .declInit f "len" (.call "length" [v "d"])
  , .ifNoElse (b ">" (v "len") (v "lim"))
      [ .assign (.index (v "positions") (v "i")) (b "+" (v "x0") (b "*" (v "d") (b "/" (v "lim") (v "len")))) ]
  ]

def shader : SlangShaderModule :=
  { structs := [{ name := "IpcStepClampParams", fields := [prm "count" u, prm "gamma" f] }]
  , globals := [ gb 0 "positions" (.rwBuf f3), gb 1 "xStart" (.roBuf f3), gb 2 "dMin" (.roBuf f)
               , gb 3 "params" (.const "IpcStepClampParams") ]
  , functions := [
      { attrs := [.shaderCompute, .numthreads 64 1 1], name := "main"
      , params := [{ name := "tid", type := .vec .uint 3, semantic := Semantic.svDispatchThreadId, binding := none, space := none }]
      , body := body } ] }

example : shader.entryPointName = "main" := by native_decide

end Cloth.SlangCodegen.IpcStepClamp
