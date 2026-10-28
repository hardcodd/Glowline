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

Soil leaves ground impacts in an expanding ballistic curtain. Craters retain moderate bowls
and nearly circular low rims; thinner ejecta rays spread farther across the surface.
The simple-crater profile joins a concave bowl directly to its crest, with a broad
cubically tapering exterior shoulder. Small rim irregularities replace scalloped
outlines; appreciable elongation is reserved for grazing incidence. Cold impacts
leave fractured gray regolith rather than a soot-black floor. The visual reference
is [NASA's lunar crater overview](https://science.nasa.gov/moon/lunar-craters/);
vertical relief remains deliberately compressed to preserve later impact visibility.
Ejecta start at the struck surface, above the newly excavated bowl. `SceneBody.craterRadius`
is shared by excavation and emission. Source radius x/R grows with launch delay;
speed scales as √(gR) (x/R)^(-1/μ) (1-x/R)^p with μ=0.41 and a finite core/capped
maximum speed. Early fine material travels farther; later coarser material stays
near the rim. Angles decrease from about 48° to 34°. Soil does not inherit the
impactor's velocity. Grain radii stay below 1.3% of crater radius; dust cards
represent unresolved grain packets, not individual large fragments.
All airborne soil, dust and rigid fragments use g=3.2 scene units/s² without air
drag and exact constant-gravity displacement between contacts. Dust deposits
on contact without buoyancy, animated smoke curls or billowing size growth.
Launch duration scales with √(R/g). The contact core opens immediately; an
excavation front then expands on the same clock as the launch annulus. Each local
fracture unfolds over at most 65 ms rather than lowering the whole bowl together.
Each annulus lifts into a temporary crest before local excavation consumes it;
the crest travels outward and leaves the terminal rim in place. A broad exterior
pressure shoulder moves ahead of excavation rather than inflating on one global
clock. Delayed fallout fades in beyond 1.35 crater radii; only this thin distant
apron lands later over 180 ms windows. Arrival depends on crater size and distance.
Signed incremental edits preserve overlapping
strikes. Scorch and molten coverage follow the newly exposed ground.
Coarse regolith (world radius parameter at least 0.04) uses the existing opaque
rigid-chunk pass, including tumble, contact and friction, with no incandescent
emission. Smaller grains and broken dust use lighter particle cards. Negative
particle age schedules a launch; waiting material neither draws nor integrates
gravity, and pause freezes the delay. The first GPU frame also includes the
offset from frame start to the resolved contact, preventing pre-impact flight.
Local slope work remains active until
the final terrain packets have landed.
The velocity law follows [Housen & Holsapple (2011)](https://data.boulder.swri.edu/ksinger/Papers/Housen%26Holsapple_2011_Ejecta_from_Impact_craters_Icarus.pdf);
the qualitative size/time ordering follows [Lunar Sourcebook, chapter 4](https://www.lpi.usra.edu/publications/books/lunar_sourcebook/pdf/Chapter04.pdf).
Coefficients, fragment sizes and optical packet density are scene approximations;
this is not a calibrated hydrocode or a meter/second reconstruction of a real impact.
Crater radius uses a bounded scene approximation proportional to the fourth root
of kinetic impact energy, shared with the ejecta source (0.38...4 units).
Single-hit depth is 0.10...0.22 units; the accumulated floor stops at −0.28,
keeping later small impacts visible. New deposits stop at 0.14, below the fixed camera.
Dry slope collapse and shock transport remain conservative; initial excavation
and the artistic ejecta profile are not a complete mass-balance simulation.

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

Incoming bodies have a turbulent ablation cap ahead of flight. Fire grows with
visible speed; a separate, wider thermal cap refracts the background only for
superheated bodies, independently of speed. Both caps use world-space ray
intersections and opaque depth, disappear on contact, and freeze with scene time.
`BodyGPU.flight.xyz` is the unit rear direction; `.w` carries birth reference speed
in image heights per scene second. `FrameUniformsGPU.thermal.z` counts incoming
atmosphere sources. Neither field changes the existing aligned structure sizes.
Refraction needs visible background detail; it cannot make an empty black field
visibly bend. The benchmark includes `metal-incoming.png` for isolated fire/heat review.

`build.py` discovers all Ambient Swift files. Standalone terrain/GPU commands in the
build guide explicitly include the simulation modules. Structural refactors should
preserve seeded body/particle streams and terrain snapshots as well as passing the
motion, terrain, layout, pause and actual-GPU tests.
