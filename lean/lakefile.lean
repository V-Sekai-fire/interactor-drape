import Lake
open Lake DSL

package Cloth where

-- Every dependency is pinned in a V-Sekai-fire repo or fork.
require LeanSlang from git
  "https://github.com/V-Sekai-fire/contract-lean-slang.git" @ "60532aef8ed70cc669ecab481182d0636c9e1ac3"

-- Property testing for the AVBD specs (Cloth.Avbd.*). The existing
-- `native_decide` examples pin single fixtures; plausible quantifies
-- the same invariants over generated meshes, which is where a role or
-- offset bug would actually show up. Pinned to v4.34.0, the plausible
-- release for this project's v4.34.1 lean-toolchain, so
-- plausible-witness-dag's ladder could be adopted below.
require plausible from git
  "https://github.com/V-Sekai-fire/plausible" @ "v4.34.0"

@[default_target] lean_lib Cloth where

lean_exe emit_shaders where
  root := `EmitShaders

-- Iterative-deepening witness search over the plausible ladder. Shares
-- the `Level` shape (walkSteps / finBound / numInst) that witness-cpp
-- mirrors on the C++ side, so a property stated here and a property
-- stated there escalate the same way.
require «plausible-witness-dag» from git
  "https://github.com/V-Sekai-fire/plausible-witness-dag" @ "160b94c9c6eed3bb9ebffce919fc6f989dcafba8"

lean_exe csr_falsify where
  root := `CsrFalsify
