import LeanSlang
import Cloth.SlangCodegen.IpcPointTriangle
import Cloth.SlangCodegen.IpcStepClamp

/-! Emits the PolyFEM-port contact kernels: `lake env lean --run EmitIpc.lean <dir>`. -/

def main (args : List String) : IO Unit := do
  let dir := args.headD "out_slang"
  IO.FS.createDirAll dir
  for (n, m) in [("ipc_point_triangle", Cloth.SlangCodegen.IpcPointTriangle.shader),
                 ("ipc_step_clamp", Cloth.SlangCodegen.IpcStepClamp.shader)] do
    IO.FS.writeFile s!"{dir}/{n}.slang" (LeanSlang.emit m)
    IO.println s!"wrote {dir}/{n}.slang"
