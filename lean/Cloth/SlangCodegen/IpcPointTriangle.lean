import LeanSlang

/-!
# `Cloth.SlangCodegen.IpcPointTriangle` — IPC barrier, cloth vertex against body triangles

GPU port of the contact term cloth-fit takes from PolyFEM (`ContactForm`, IPC log barrier), in
vertex block descent form. For each vertex `v` of the current colour and each candidate body
triangle `t` in its list:

```
c      = closest point on t to p              -- Ericson's region test
s      = |p - c|²,   ŝ = dhat²
b(s)   = -(s - ŝ)² ln(s/ŝ)                    for s < ŝ, else 0
∇_p    = κ b'(s) · 2 (p - c)
H_p    = κ max(4 s b''(s) + 2 b'(s), 0) · n nᵀ,   n = (p - c)/√s
```

`H_p` is the PSD projection of `κ (b'' ∇s∇sᵀ + b' ∇²s)`: along `n` every region of the distance
has `∇²s` eigenvalue 2, across `n` the eigenvalues are `2b'` or 0, and `b' ≤ 0`, so they clamp
to 0. The kernel also writes the vertex's smallest distance to any candidate, which the step
bound (`IpcStepClamp`) uses to keep every iterate intersection-free. That distance is capped at
the candidate search radius, so a triangle outside the list cannot be stepped through.

Bindings (set 0):
  0 positions  ro float3   1 bodyPos ro float3   2 bodyTri ro uint (3 per tri)
  3 candOffset ro uint     4 candIdx ro uint     5 gScratch rw float3
  6 hScratch rw float (6 per vertex)             7 vertPerm ro uint
  8 dMin rw float          9 params
-/

namespace Cloth.SlangCodegen.IpcPointTriangle
open LeanSlang

private def f3 : SlangType := .vec .float 3
private def u  : SlangType := .scalar .uint
private def f  : SlangType := .scalar .float
private def v (n : String) : SlangExpr := .var n
private def b (op : String) (x y : SlangExpr) : SlangExpr := .bin op x y
private def lf (x : Float) : SlangExpr := .litFloat x
private def lu (x : Nat) : SlangExpr := .litUint x
private def dot (x y : SlangExpr) : SlangExpr := .call "dot" [x, y]
private def and2 (x y : SlangExpr) : SlangExpr := b "&&" x y
private def ret (e : SlangExpr) : SlangStmt := .ret (some e)

/-- Ericson, Real-Time Collision Detection 5.1.5. -/
private def closestBody : List SlangStmt :=
  [ .declInit f3 "ab" (b "-" (v "tb") (v "ta"))
  , .declInit f3 "ac" (b "-" (v "tc") (v "ta"))
  , .declInit f3 "ap" (b "-" (v "p") (v "ta"))
  , .declInit f "d1" (dot (v "ab") (v "ap"))
  , .declInit f "d2" (dot (v "ac") (v "ap"))
  , .ifNoElse (and2 (b "<=" (v "d1") (lf 0.0)) (b "<=" (v "d2") (lf 0.0))) [ret (v "ta")]
  , .declInit f3 "bp" (b "-" (v "p") (v "tb"))
  , .declInit f "d3" (dot (v "ab") (v "bp"))
  , .declInit f "d4" (dot (v "ac") (v "bp"))
  , .ifNoElse (and2 (b ">=" (v "d3") (lf 0.0)) (b "<=" (v "d4") (v "d3"))) [ret (v "tb")]
  , .declInit f "vc" (b "-" (b "*" (v "d1") (v "d4")) (b "*" (v "d3") (v "d2")))
  , .ifNoElse (and2 (and2 (b "<=" (v "vc") (lf 0.0)) (b ">=" (v "d1") (lf 0.0))) (b "<=" (v "d3") (lf 0.0)))
      [ ret (b "+" (v "ta") (b "*" (b "/" (v "d1") (b "-" (v "d1") (v "d3"))) (v "ab"))) ]
  , .declInit f3 "cp" (b "-" (v "p") (v "tc"))
  , .declInit f "d5" (dot (v "ab") (v "cp"))
  , .declInit f "d6" (dot (v "ac") (v "cp"))
  , .ifNoElse (and2 (b ">=" (v "d6") (lf 0.0)) (b "<=" (v "d5") (v "d6"))) [ret (v "tc")]
  , .declInit f "vb" (b "-" (b "*" (v "d5") (v "d2")) (b "*" (v "d1") (v "d6")))
  , .ifNoElse (and2 (and2 (b "<=" (v "vb") (lf 0.0)) (b ">=" (v "d2") (lf 0.0))) (b "<=" (v "d6") (lf 0.0)))
      [ ret (b "+" (v "ta") (b "*" (b "/" (v "d2") (b "-" (v "d2") (v "d6"))) (v "ac"))) ]
  , .declInit f "va" (b "-" (b "*" (v "d3") (v "d6")) (b "*" (v "d5") (v "d4")))
  , .ifNoElse (and2 (and2 (b "<=" (v "va") (lf 0.0)) (b ">=" (b "-" (v "d4") (v "d3")) (lf 0.0)))
                    (b ">=" (b "-" (v "d5") (v "d6")) (lf 0.0)))
      [ .declInit f "we" (b "/" (b "-" (v "d4") (v "d3")) (b "+" (b "-" (v "d4") (v "d3")) (b "-" (v "d5") (v "d6"))))
      , ret (b "+" (v "tb") (b "*" (v "we") (b "-" (v "tc") (v "tb")))) ]
  , .declInit f "dn" (b "/" (lf 1.0) (b "+" (b "+" (v "va") (v "vb")) (v "vc")))
  , ret (b "+" (b "+" (v "ta") (b "*" (v "ab") (b "*" (v "vb") (v "dn")))) (b "*" (v "ac") (b "*" (v "vc") (v "dn"))))
  ]

private def prm (n : String) (t : SlangType) : SlangBinding :=
  { name := n, type := t, semantic := Semantic.none, binding := none, space := none }

private def closestFn : SlangFunctionDecl :=
  { retType := f3, name := "closestPointTriangle"
  , params := [prm "p" f3, prm "ta" f3, prm "tb" f3, prm "tc" f3], body := closestBody }

private def hAdd (k : Nat) (e : SlangExpr) : SlangStmt :=
  .assign (.index (v "hScratch") (b "+" (v "hb") (lu k)))
          (b "+" (.index (v "hScratch") (b "+" (v "hb") (lu k))) e)

private def body : List SlangStmt :=
  [ .declInit u "lane" (.member (v "tid") "x")
  , .declInit u "vi" (.index (v "vertPerm") (b "+" (v "lane") (.member (v "params") "colorOffset")))
  , .declInit f3 "p" (.index (v "positions") (v "vi"))
  , .declInit u "k0" (.index (v "candOffset") (v "vi"))
  , .declInit u "k1" (.index (v "candOffset") (b "+" (v "vi") (lu 1)))
  , .declInit f "sh" (.member (v "params") "dhat2")
  , .declInit f "kap" (.member (v "params") "kappa")
  , .declInit f3 "g" (.index (v "gScratch") (v "vi"))
  , .declInit u "hb" (b "*" (lu 6) (v "vi"))
  , .declInit f "smin" (.member (v "params") "searchR2")
  , .forCount "k" (v "k0") (v "k1")
      [ .declInit u "t" (b "*" (lu 3) (.index (v "candIdx") (v "k")))
      , .declInit f3 "c" (.call "closestPointTriangle"
          [ v "p", .index (v "bodyPos") (.index (v "bodyTri") (v "t"))
          , .index (v "bodyPos") (.index (v "bodyTri") (b "+" (v "t") (lu 1)))
          , .index (v "bodyPos") (.index (v "bodyTri") (b "+" (v "t") (lu 2))) ])
      , .declInit f3 "r" (b "-" (v "p") (v "c"))
      , .declInit f "s" (dot (v "r") (v "r"))
      , .assign (v "smin") (.call "min" [v "smin", v "s"])
      , .ifNoElse (and2 (b "<" (v "s") (v "sh")) (b ">" (v "s") (lf 1.0e-20)))
          [ .declInit f "dt" (b "-" (v "s") (v "sh"))
          , .declInit f "lr" (.call "log" [b "/" (v "s") (v "sh")])
          , .declInit f "b1" (b "-" (b "*" (b "*" (lf (-2.0)) (v "dt")) (v "lr")) (b "/" (b "*" (v "dt") (v "dt")) (v "s")))
          , .declInit f "b2" (b "+" (b "-" (b "*" (lf (-2.0)) (v "lr")) (b "/" (b "*" (lf 4.0) (v "dt")) (v "s")))
                                    (b "/" (b "*" (v "dt") (v "dt")) (b "*" (v "s") (v "s"))))
          , .assign (v "g") (b "+" (v "g") (b "*" (b "*" (b "*" (v "kap") (v "b1")) (lf 2.0)) (v "r")))
          , .declInit f "hn" (b "/" (b "*" (v "kap")
              (.call "max" [b "+" (b "*" (b "*" (lf 4.0) (v "s")) (v "b2")) (b "*" (lf 2.0) (v "b1")), lf 0.0])) (v "s"))
          , hAdd 0 (b "*" (v "hn") (b "*" (.member (v "r") "x") (.member (v "r") "x")))
          , hAdd 1 (b "*" (v "hn") (b "*" (.member (v "r") "x") (.member (v "r") "y")))
          , hAdd 2 (b "*" (v "hn") (b "*" (.member (v "r") "x") (.member (v "r") "z")))
          , hAdd 3 (b "*" (v "hn") (b "*" (.member (v "r") "y") (.member (v "r") "y")))
          , hAdd 4 (b "*" (v "hn") (b "*" (.member (v "r") "y") (.member (v "r") "z")))
          , hAdd 5 (b "*" (v "hn") (b "*" (.member (v "r") "z") (.member (v "r") "z"))) ] ]
  , .assign (.index (v "gScratch") (v "vi")) (v "g")
  , .assign (.index (v "dMin") (v "vi")) (.call "sqrt" [v "smin"])
  ]

private def gb (n : Nat) (name : String) (t : SlangType) : SlangBinding :=
  { name := name, type := t, semantic := Semantic.none, binding := some n, space := some 0 }

def shader : SlangShaderModule :=
  { structs := [{ name := "IpcPointTriangleParams"
                , fields := [prm "colorOffset" u, prm "dhat2" f, prm "kappa" f, prm "searchR2" f] }]
  , globals := [ gb 0 "positions" (.roBuf f3), gb 1 "bodyPos" (.roBuf f3), gb 2 "bodyTri" (.roBuf u)
               , gb 3 "candOffset" (.roBuf u), gb 4 "candIdx" (.roBuf u), gb 5 "gScratch" (.rwBuf f3)
               , gb 6 "hScratch" (.rwBuf f), gb 7 "vertPerm" (.roBuf u), gb 8 "dMin" (.rwBuf f)
               , gb 9 "params" (.const "IpcPointTriangleParams") ]
  , functions := [ closestFn,
      { attrs := [.shaderCompute, .numthreads 64 1 1], name := "main"
      , params := [{ name := "tid", type := .vec .uint 3, semantic := Semantic.svDispatchThreadId, binding := none, space := none }]
      , body := body } ] }

example : shader.entryPointName = "main" := by native_decide

end Cloth.SlangCodegen.IpcPointTriangle
