> **Historical reference.** Written 2026-06-16, kept in
> `meta-project/docs/another-project.md` as `another-project.md` until moved
> here on 2026-09-19. This is one of several starting points that eventually
> became CoffeeBEANS. The plan here was browser-first (Three.js in a tab);
> CoffeeBEANS went with Electron instead, aiming at the kind of immediate,
> tinkerable experience AmigaBASIC had. Preserved as written, not corrected.

**PROJECT: Dynamic Language Game Exploration**

**Goal:** Muck about with physics, rendering, and simulations using fully
dynamic semantics (no static typing, malleable at runtime) while leveraging
modern GPU power.

**Approach:** Browser-first for rapid iteration
- **Stack:** CoffeeScript → JavaScript → Three.js/Babylon.js → WebGL/WebGPU
- **Hot paths:** WASM modules (compiled from C) for pathfinding, specific algorithms
- **Compute:** WebGPU shaders for simulation (à la Sebastian Lague's approach)
- **Deployment:** Electron if/when shipping matters

**Why this works:**
- V8 gives proper dynamic semantics (eval, runtime mutation, heterogeneous collections)
- WebGL/WebGPU access both GPUs directly
- Hot reloading is trivial
- Mature ecosystem (physics, asset loaders, etc.)
- No visual editor required - pure code
- Can drop to raw JS when CoffeeScript gets in the way

**First experiments:**
1. Spinning cube in Three.js + CoffeeScript (validate toolchain)
2. Add physics (Cannon.js or Rapier)
3. Simple compute shader (cellular automata, Conway's Life variant)
4. Sebastian-style fluid sim as GPU compute
5. Landscape generation
6. History generation (Dwarf Fortress style)

**Future path if browser feels constraining:**
- LuaJIT + Fennel + LÖVE (lighter weight, similar dynamics)
- Or: Raylib + QuickJS + custom syntax (full control, 2-3 month pilgrimage)

**Not doing:**
- Fighting static type systems (Godot/Unity/Unreal with C++/C#)
- Python syntax noise
- Mobile/console targets
- 3D modeling/2D art (use third-party assets)

