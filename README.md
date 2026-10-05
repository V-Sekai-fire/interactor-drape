# interactor-drape

The drape stage as a godot-sandbox guest: AVBD cloth from Lean kernels, run on the CPU and on RenderingDevice.

## What it is for

The Lean tree states the AVBD cloth specs and emits the compute kernels as Slang. The guest runs those kernels on the CPU and on the GPU to drape a garment on a body, and an in-guest L-BFGS-B solves the inverse problem against a reference trace. It builds against the repositories it needs as sibling checkouts at their goal-manifest paths, and `transport-meshing-pen` builds the guest ELFs.

## Build

```sh
cd lean
lake build
lake exe emit_shaders
```

## Licence

The source files carry `Apache-2.0 OR MIT` SPDX headers; the repository has no licence file.
