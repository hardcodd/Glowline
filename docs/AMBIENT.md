# Noctiluca architecture

[Русский](AMBIENT.ru.md) · [User and build guide](USER-GUIDE.en.md)

Noctiluca runs inside the macOS application. Swift owns scene time, incoming bodies,
contacts and terrain; Metal owns detached particles after emission. The renderer
can also run offscreen without a window, serial controller or application settings.

| Source/Ambient module | Responsibility |
| --- | --- |
| `SceneDirector`, `MeteorShower` | Seeded arrival composition and shower scheduling |
| `SceneBody`, `BodyModel` | Immutable birth parameters, world-space trajectory and energy-limited stopping |
| `BodyContacts` | Swept body contacts resolved in time order |
| `SceneSimulation` | Session orchestration, arrivals, terrain contacts and frame assembly |
| `ParticleModel`, `ParticleEmitter` | Deterministic randomness, detached trails and impact ejecta |
| `Sand` | Persistent height field, conservative slumping, shock transport and melt pools |
| `SceneMath`, `SimulationFrame` | Shared math, palette conversion and GPU value layouts |
| `Camera`, `Renderer` | Projection, presentation tremors, resource ownership and render passes |
| `Window`, `IdleLaunch` | Presentation, controls, preferences and idle-session lifecycle |

Arrival decisions apply only at birth. Changing activity or color themes never bends
or recolors an existing flight. The seeded random stream and emission call order
are part of reproducibility: moving a call can change every later particle.

Terrain uses local active regions and a fixed 1/120-second physics step. Craters
persist for the session; pausing or resizing does not reset them. Only the massive
superheated class creates colored melt pools. Ordinary impacts retain solid debris.

`BodyModel` distinguishes `meteor`, `superheatedAsteroid`, `bolide` and
`showerMeteor(Member)`. Only `superheatedAsteroid` has a `lavaLake` ground impact;
the other models produce fragments. `BodyArrival` describes a scheduling request,
while `SceneBody` owns the resolved identity, flight and contact state. `TrailStyle`
is a visual choice, not a physical species. Crust appearance remains continuous
across sizes and does not override a bolide's or shower member's impact behavior.

`ParticleKind` names vapor, embers, impact gas, fragments, soil dust, ion/plasma
trails and regolith grains. `ParticleDynamics` separately names wake, ballistic,
bounced and settled states. Their raw values are the documented Metal encoding.

`ParticleGPU` is six aligned SIMD4 values (96 bytes), `BodyGPU` is nine (144 bytes),
and `FrameUniformsGPU` is five (80 bytes). Their Swift layouts and field order match
`Resources/Noctiluca.metal`. Simulation objects never cross this boundary directly.

There are at most 20 bodies, one large body and one bolide. New emission is bounded
to 4096 particles per frame. Particles live for at most six seconds in a 32768-entry
GPU ring; the full-hour self-test checks peak emission over that lifetime window.

The renderer uses three completion-protected upload slots and queue-ordered GPU
resources. Opaque terrain, bodies and chunks write depth before flashes; vapor and
the final HDR/refraction pass use that depth. CPU fingerprints alone cannot verify
the Metal boundary: run the GPU contracts and inspect displayed output too.

`build.py` discovers all Ambient Swift files. Standalone terrain/GPU commands in the
build guide explicitly include the simulation modules. Structural refactors should
preserve seeded body/particle streams and terrain snapshots as well as passing the
motion, terrain, layout, pause and actual-GPU tests.
