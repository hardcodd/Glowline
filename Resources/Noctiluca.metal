#include <metal_stdlib>
using namespace metal;
// Numeric encodings match ParticleKind and ParticleDynamics in Swift.
constant float particleVapor = 0;
constant float particleEmber = 1;
constant float particleImpactGas = 2;
constant float particleRockFragment = 3;
constant float particleSoilDust = 4;
constant float particleIonTrail = 5;
constant float particlePlasmaTrail = 6;
constant float particleRegolithGrain = 7;
constant float dynamicsWakeSpark = - 1;
constant float dynamicsWake = 0;
constant float dynamicsBallistic = 1;
constant float dynamicsBounced = 1.5;
constant float dynamicsSettled = 2;
struct ParticleGPU {
    float4 position, life, color, owner, orientation, angular;
}
;
struct BodyGPU {
    float4 position, color, motion, cloud, shape, spatial, contact, impactEffects, flight;
}
;
struct MeltPool {
    float4 location, shape, color;
}
;
struct FrameUniformsGPU {
    float4 viewport, controls;
    uint4 counts;
    float4 options;
    uint4 thermal;
}
;
struct Raster {
    float4 position [[position]];
    float2 uv;
    float4 color, data, extra, impact;
    float3 world, local, normal, flight;
}
;
constant float2 corners[6] = {
    float2(- 1, - 1), float2(1, - 1), float2(- 1, 1), float2(- 1, 1), float2(1, - 1), float2(1, 1)
}
;
constant float3 cameraOrigin = float3(0, .42, 0);
constant float3 cameraForward = float3(0, .28, - .96);
constant float3 cameraUp = float3(0, .96, .28);
constexpr sampler linearRepeat(filter::linear, address::repeat);
constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
float noise(texture2d < float > map, float2 p) {
    return map.sample(linearRepeat, p / 128, level(0)).r;
}
float fbm(texture2d < float > map, float2 p) {
    return noise(map, p) * .57 + noise(map, p * 2.07 + 17) * .28 + noise(map, p * 4.13 - 23) * .15;
}
float latticeNoise(float3 p) {
    p = fract(p * .1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}
float volumeNoise(texture2d < float > map, float3 p) {
    // A true XYZ lattice avoids projected stripes at the limb of a large sphere.
    float3 cell = floor(p), u = fract(p);
    u = u * u *(3 - 2 * u);
    float z0 = mix(mix(latticeNoise(cell), latticeNoise(cell + float3(1, 0, 0)), u.x),
    mix(latticeNoise(cell + float3(0, 1, 0)), latticeNoise(cell + float3(1, 1, 0)), u.x), u.y);
    float z1 = mix(mix(latticeNoise(cell + float3(0, 0, 1)), latticeNoise(cell + float3(1, 0, 1)), u.x),
    mix(latticeNoise(cell + float3(0, 1, 1)), latticeNoise(cell + float3(1, 1, 1)), u.x), u.y);
    return mix(z0, z1, u.z);
}
float activeHeight(constant FrameUniformsGPU & f) {
    return f.options.y < .5 ? min(1.0, f.viewport.z /(21.0 / 9.0)) : 1.0;
}
/// Perspective with a 0.05 near plane and 100-unit far plane, shared by every geometric pass.
float4 project(float3 world, constant FrameUniformsGPU & f) {
    float3 relative = world - cameraOrigin;
    float distance = dot(relative, cameraForward);
    float scale = activeHeight(f);
    float vertical = dot(relative, cameraUp);
    return float4(relative.x * 2 * scale / f.viewport.z, vertical * 2 * scale,
    distance *(100.0 / 99.95) - 5.0 / 99.95, distance);
}
constant uint sandSize = 1024;
constant float sandCell = .125;
float regolithHeight(float2 p) {
    float2 tile = floor(p / 3);
    float seed = fract(sin(dot(tile, float2(127.1, 311.7))) * 43758.5453);
    float2 jitter = fract(sin(dot(tile, float2(127.1, 311.7)) + float2(13, 29)) * 43758.5453);
    float2 center = tile * 3 + .9 + jitter * 1.2;
    float d = length(p - center) /(.22 + seed * .43);
    float crater =(- pow(max(0.0, 1 - d * d), 1.5) + exp(- pow((d - 1.05) / .19, 2.0)) * .3) *(.04 + seed * .09);
    return crater + .018 * sin(p.x * 1.7 + sin(p.y * 2.3)) * cos(p.y * 1.31 + sin(p.x * 2.71))
    + .009 * sin(p.x * 4.13 + p.y * 3.77);
}
/// Float4 ABI: height, x/z slopes, scorch (>0)/fresh ejecta (<0). Bilinear CPU/GPU contact sampling.
float4 sandField(float2 point, const device float4 * terrain) {
    float2 grid =(point + float2(64, 112)) / sandCell - .5;
    if (any(grid < 0) || any(grid >= float(sandSize - 1))) {
        float e = .025;
        return float4(regolithHeight(point),(regolithHeight(point + float2(e, 0)) - regolithHeight(point - float2(e, 0))) /(2 * e),
        (regolithHeight(point + float2(0, e)) - regolithHeight(point - float2(0, e))) /(2 * e), 0);
    }
    uint2 base = uint2(floor(grid));
    float2 u = fract(grid);
    float4 a = mix(terrain[base.y * sandSize + base.x], terrain[base.y * sandSize + base.x + 1], u.x);
    float4 b = mix(terrain[(base.y + 1) * sandSize + base.x], terrain[(base.y + 1) * sandSize + base.x + 1], u.x);
    return mix(a, b, u.y);
}
// Closed irregular icosahedra: twenty broken faces, shared by rendering and terrain support.
constant uint chunkTriangles[60] = {
    0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
    1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
    4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1
}
;
constant float3 chunkVertices[12] = {
    float3(- 1, 1.618, 0), float3(1, 1.618, 0), float3(- 1, - 1.618, 0), float3(1, - 1.618, 0),
    float3(0, - 1, 1.618), float3(0, 1, 1.618), float3(0, - 1, - 1.618), float3(0, 1, - 1.618),
    float3(1.618, 0, - 1), float3(1.618, 0, 1), float3(- 1.618, 0, - 1), float3(- 1.618, 0, 1)
}
;
float3 chunkCorner(uint i, float seed) {
    float radius = .4 + .16 * latticeNoise(float3(seed, i, 1));
    return chunkVertices[i] * radius * float3(.8 + .5 * fract(seed * .73), .7 + .4 * fract(seed * .19), .8 + .4 * fract(seed * .37));
}
float3 rotateChunk(float4 q, float3 v) {
    return v + 2 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}
float4 multiplyRotation(float4 a, float4 b) {
    return float4(a.w * b.xyz + b.w * a.xyz + cross(a.xyz, b.xyz), a.w * b.w - dot(a.xyz, b.xyz));
}
float chunkSupport(ParticleGPU p) {
    float bottom = 0;
    for (uint i = 0; i < 12; i ++) bottom = min(bottom, rotateChunk(p.orientation, chunkCorner(i, p.life.w)).y);
    return - bottom * p.life.x;
}
float chunkHeat(ParticleGPU p) {
    return saturate(1 - p.life.y /(p.owner.y >= dynamicsSettled ? 2.6 : max(.001, p.life.z))) *(p.owner.y >= dynamicsSettled ? p.angular.w : 1);
}
/// Deepest actual vertex contact, including terrain slope under the entire rock footprint.
float4 rockContact(ParticleGPU p, const device float4 * terrain) {
    float3 center = float3(p.position.xy, p.owner.z);
    float4 contact = float4(0, 0, 0, - 1e6);
    for (uint i = 0; i < 12; i ++) {
        float3 lever = rotateChunk(p.orientation, chunkCorner(i, p.life.w)) * p.life.x;
        float3 point = center + lever;
        float penetration = sandField(point.xz, terrain).x - point.y;
        if (penetration > contact.w) contact = float4(lever, penetration);
    }
    return contact;
}
/// Rigid contact impulses and Coulomb friction replace height following and scripted pose interpolation.
ParticleGPU evolveRock(ParticleGPU p, float dt, const device float4 * terrain) {
    if (dt <= 0) return p;
    float3 pos = float3(p.position.xy, p.owner.z), vel = float3(p.position.zw, p.owner.w);
    bool deposited = p.owner.y >= dynamicsSettled;
    if (deposited && length(vel) < .001 && length(p.angular.xyz) < .001) {
        // A resting rock stays put. Only a newly excavated gap underneath releases it again.
        if (rockContact(p, terrain).w >= - .018) {
            p.life.y += dt;
            return p;
        }
    }
    uint steps = uint(clamp(ceil(dt * 120), 1.0, 32.0));
    float h = dt / float(steps), inertia = max(.00001, p.life.x * p.life.x * .4);
    for (uint step = 0; step < steps; step ++) {
        vel.y -= 3.2 * h;
        vel *= exp(- h * .045);
        float spin = length(p.angular.xyz);
        if (spin > .0001) {
            float angle = spin * h * .5;
            p.orientation = normalize(multiplyRotation(float4(p.angular.xyz / spin * sin(angle), cos(angle)), p.orientation));
        }
        pos += vel * h;
        p.position.xy = pos.xy;
        p.owner.z = pos.z;
        if (pos.y - sandField(pos.xz, terrain).x > p.life.x * 1.5) continue;
        float4 contact = rockContact(p, terrain);
        if (contact.w < 0) continue;
        float4 field = sandField((pos + contact.xyz).xz, terrain);
        float3 normal = normalize(float3(- field.y, 1, - field.z));
        pos += normal *(contact.w / max(.3, normal.y) + .00002);
        float3 pointVelocity = vel + cross(p.angular.xyz, contact.xyz);
        float incidence = dot(pointVelocity, normal);
        if (incidence < 0) {
            float restitution = incidence < - .65 ? .20 : 0;
            float denominator = 1 + dot(normal, cross(cross(contact.xyz, normal) / inertia, contact.xyz));
            float impulse = -(1 + restitution) * incidence / max(1.0, denominator);
            vel += normal * impulse;
            p.angular.xyz += cross(contact.xyz, normal * impulse) / inertia;
            float3 tangent = pointVelocity - normal * incidence;
            float tangentSpeed = length(tangent);
            if (tangentSpeed > .0001) {
                float3 axis = tangent / tangentSpeed;
                float effective = 1 + dot(axis, cross(cross(contact.xyz, axis) / inertia, contact.xyz));
                float friction = min(impulse * .72, tangentSpeed / max(1.0, effective));
                vel -= axis * friction;
                p.angular.xyz -= cross(contact.xyz, axis * friction) / inertia;
            }
            // Dry granular contact loses spin; it does not rotate toward an arbitrary target pose.
            p.angular.xyz *= .72;
            if (! deposited) p.owner.y = dynamicsBounced;
        }
        if (length(vel) < .16 && length(p.angular.xyz) * p.life.x < .10) {
            vel = 0;
            p.angular.xyz = 0;
            if (! deposited) {
                p.angular.w = chunkHeat(p);
                p.owner.y = dynamicsSettled;
                p.life.y = 0;
                p.life.z = 8;
                deposited = true;
            }
            break;
        }
    }
    p.position = float4(pos.xy, vel.xy);
    p.owner.z = pos.z;
    p.owner.w = vel.z;
    p.life.y += dt;
    return p;
}
/// World-space deposition, ballistic debris and a two-second cooling phase after terrain contact.
kernel void evolve(device ParticleGPU * particles [[buffer(0)]], const device ParticleGPU * newParticles [[buffer(1)]],
constant FrameUniformsGPU & f [[buffer(2)]], const device BodyGPU * bodies [[buffer(3)]],
const device float4 * terrain [[buffer(4)]], uint id [[thread_position_in_grid]]) {
    if (id >= f.counts.x) return;
    uint offset =(id + f.counts.x - f.counts.z) % f.counts.x;
    ParticleGPU p = offset < f.counts.y ? newParticles[offset] : particles[id];
    if (f.options.z > .5 && offset >= f.counts.y) {
        p.life = float4(0);
        particles[id] = p;
        return;
    }
    if (p.life.z <= 0 || p.life.y >= p.life.z) return;
    float dt = f.controls.x;
    if (p.color.w == particleRockFragment) {
        particles[id] = evolveRock(p, dt, terrain);
        return;
    }
    float3 pos = float3(p.position.xy, p.owner.z), vel = float3(p.position.zw, p.owner.w);
    bool hot = p.color.w == particleEmber;
    bool grain = p.color.w == particleRegolithGrain, solid = hot || grain;
    if (solid && p.owner.y >= dynamicsSettled) {
        float4 field = sandField(pos.xz, terrain);
        pos.y = field.x + p.life.x * .35;
        p.position = float4(pos.xy, 0, 0);
        p.owner.w = 0;
        p.life.y += dt;
        particles[id] = p;
        return;
    }
    if (grain) {
        vel.y -= dt * 3.2;
        vel *= exp(- dt * .35);
    }
    else if (p.color.w == particleSoilDust) {
        vel.y -= dt * .65;
        vel *= exp(- dt * .65);
    }
    else if (p.color.w == particleEmber && p.owner.y < 0) {
        // Ablation sparks stay in the wake. They do not acquire the gravity of impact fragments.
        vel *= exp(- dt * .7);
    }
    else if (hot) {
        vel.y -= dt * 1.8;
        vel *= exp(- dt * .12);
    }
    else {
        for (uint i = 0; i < f.counts.w; i ++) {
            BodyGPU body = bodies[i];
            // A broken parent gives its already deposited wake one outward impulse.
            if (abs(p.owner.x - body.color.w) < .1 && body.shape.z >= 0 && p.owner.y < .5) {
                float3 radial = pos - float3(body.cloud.xy, body.motion.x);
                vel += normalize(radial + float3(0, .001, 0)) * .16;
                p.owner.y = dynamicsBallistic;
            }
            if (p.color.w == particleImpactGas && abs(p.owner.x - body.color.w) > .1 && body.cloud.w > 0) {
                float3 d = pos - float3(body.cloud.xy, body.motion.x);
                float r = body.cloud.z * .85, distance = length(d);
                if (distance < r) vel += d / max(.004, distance) *(r - distance) * body.cloud.w * dt;
            }
        }
        // Shared spatial eddies bend neighboring streamers together instead of shaking each grain independently.
        float3 wind = float3(sin(pos.y * 3 + pos.z * 2 + f.viewport.w * .4),
        cos(pos.x * 3 - pos.z + f.viewport.w * .3), sin(pos.z * 3 + pos.y * 2));
        if (p.color.w == particleImpactGas) wind = float3(sin(pos.y * 11 + p.life.w), cos(pos.x * 9 - p.life.w), sin(pos.z * 13 + p.life.w));
        vel += wind * dt *(p.color.w >= particleIonTrail ? .045 : .025);
        vel.y += dt *(p.color.w == particleImpactGas ? .035 : .006);
        vel *= exp(- dt *(p.color.w == particleImpactGas ? .19 : p.color.w >= particleIonTrail ? .16 : .4));
    }
    pos += vel * dt;
    float floor = sandField(pos.xz, terrain).x;
    float support = p.life.x * .35;
    if (solid && vel.y < 0 && pos.y <= floor + support) {
        pos.y = floor + support;
        float4 field = sandField(pos.xz, terrain);
        float3 normal = normalize(float3(- field.y, 1, - field.z));
        float incidence = dot(vel, normal);
        if (grain && p.owner.y < 1.4 && incidence < - .55) {
            // One damped bounce: retain some tangential motion, lose most normal energy.
            vel =(vel - normal * incidence) *(grain ? .32 : .48) - normal * incidence *(grain ? .12 : .22 + .1 * fract(p.life.w));
            p.owner.y = dynamicsBounced;
        }
        else {
            vel = 0;
            p.life.w += p.life.y * 1.2;
            p.angular = 0;
            p.owner.y = dynamicsSettled;
            p.life.y = 0;
            p.life.z = grain ? .45 : 2 + .8 * latticeNoise(float3(p.life.w, 1, 3));
        }
    }
    else if (! solid && pos.y < floor) {
        pos.y = floor + .005;
        vel.y = max(0.0, vel.y);
        p.life.y += dt * 2;
    }
    p.position = float4(pos.xy, vel.xy);
    p.owner.z = pos.z;
    p.owner.w = vel.z;
    p.life.y += dt;
    particles[id] = p;
}
/// Seeded asteroid silhouettes remain inside the event collision sphere.
float3 asteroidSurfaceOffset(float3 n, float seed, float time) {
    float3 variety = float3(latticeNoise(float3(seed, 3, 17)), latticeNoise(float3(seed, 11, 5)),
    latticeNoise(float3(seed, 29, 7)));
    uint family = uint(variety.x * 4);
    float3 axes = family == 0 ? float3(.43, 1, .61) : family == 1 ? float3(1, .46, .76)
    : family == 2 ? float3(.63, .93, .78) : float3(.91, .62, .73);
    axes *= .94 + variety.y * .06;
    float3 cut = normalize(float3(variety.y - .35, variety.z - .55, .7));
    float radial = min(1.0,(family == 2 ? .72 : .86) / max(.001, dot(n, cut)));
    radial = min(radial, .88 / max(.001, dot(n, normalize(float3(- .6, .8, variety.y - .5)))));
    float3 body = n * axes * radial;
    float rotation = seed + time *(.14 + variety.z * .12);
    body = float3(body.x * cos(rotation) + body.z * sin(rotation), body.y, - body.x * sin(rotation) + body.z * cos(rotation));
    float tilt =(variety.y - .5) * 1.4;
    return float3(body.x * cos(tilt) - body.y * sin(tilt), body.x * sin(tilt) + body.y * cos(tilt), body.z);
}
/// Tessellated asteroids have real surface depth and seeded rotating silhouettes.
vertex Raster bodyVertex(uint vid [[vertex_id]], uint instance [[instance_id]],
const device BodyGPU * bodies [[buffer(0)]], constant FrameUniformsGPU & f [[buffer(1)]],
texture2d < float > map [[texture(4)]]) {
    BodyGPU body = bodies[instance];
    Raster out = {
    }
    ;
    // Remnant sources still light the ground and their wakes; their destroyed opaque mesh has no pixels.
    if (body.position.w <= 0) {
        out.position = float4(0, 0, - 1, 1);
        return out;
    }
    out.flight = length(body.flight.xyz) > .5 ? - body.flight.xyz : normalize(float3(body.shape.x, 0, 0) - cameraUp);
    out.uv = float2(0);
    float2 grid = float2(vid % 97, vid / 97);
    float longitude = grid.x / 96 * 2 * M_PI_F, latitude = grid.y / 64 * M_PI_F;
    float3 n = float3(sin(latitude) * cos(longitude), cos(latitude), sin(latitude) * sin(longitude));
    float rotation = f.viewport.w * .075 + body.motion.w;
    float3 local = float3(n.x * cos(rotation) + n.z * sin(rotation), n.y, - n.x * sin(rotation) + n.z * cos(rotation));
    float rough = volumeNoise(map, local * 5 + body.motion.w);
    float3 rear = length(body.flight.xyz) > .5 ? body.flight.xyz : normalize(cameraUp - float3(body.shape.x, 0, 0));
    float3 across = normalize(cross(rear, - cameraForward));
    float3 face = normalize(cross(across, rear));
    float3 localShape = asteroidSurfaceOffset(n, body.motion.w, f.viewport.w);
    float3 offset =(across * localShape.x + rear * localShape.y + face * localShape.z) * body.spatial.w;
    offset *= 1 +(rough - .5) * .08;
    offset *= min(1.0, body.spatial.w / max(.00001, length(offset)));
    local = n;
    float3 world = body.spatial.xyz + offset;
    out.position = project(world, f);
    out.world = world;
    out.local = local;
    out.normal = normalize(offset);
    out.color = body.color;
    out.data = body.position;
    out.extra = float4(body.motion.w, f.viewport.w, body.motion.z, body.shape.y);
    out.impact = body.shape;
    out.uv.y = body.contact.w;
    return out;
}
/// Asteroid crust and molten fractures share the arrival hue; low crust fraction means extreme heat.
float3 bodyLight(float3 local, float3 normal, float3 color, float crustFraction, float3 flight,
float seed, float time, texture2d < float > map) {
    float3 p = local * 7 + seed + float3(0, time * .055, time * .025);
    float convection = volumeNoise(map, p);
    float footprint = max(length(dfdx(local)), length(dfdy(local)));
    float detail = saturate(1 - footprint * 35);
    float3 flow = float3(convection, volumeNoise(map, p * .7 + 19), volumeNoise(map, p * .7 - 23));
    float3 cellsPoint = p * 5 + flow * 3 + float3(time * .12, - time * .08, 0);
    float fine = volumeNoise(map, cellsPoint) * .65 + volumeNoise(map, cellsPoint * 2.03 + 17) * .35;
    float cells = smoothstep(.25, .75, mix(convection, fine, detail));
    float3 warm = mix(color, float3(1, .70, .34), .16);
    float diffuse = .12 + .88 * saturate(dot(normal, normalize(float3(- .4, .5, .8))));
    float rock = .20 + volumeNoise(map, local * 11 + seed) * .65;
    float pores = volumeNoise(map, local * 33 + seed);
    float3 crust = mix(float3(.055, .035, .025), float3(.24, .12, .065), rock) * diffuse *(.65 + .35 * pores);
    float front = pow(saturate(dot(normal, flight)), 2.5);
    float fracture = volumeNoise(map, local * 9 + flow * .8 + seed);
    float melt = smoothstep(.54, .76, fracture) *(.35 + .65 * convection);
    float3 ordinary = crust + warm *(front *(1.4 + cells * .9) + melt * .65);
    float heat = 1 - crustFraction;
    float3 fissurePoint = local * 5 + seed;
    float ridge = 1 - abs(volumeNoise(map, fissurePoint) * 2 - 1);
    float cracks = smoothstep(.80, .94, ridge);
    float plates = smoothstep(.38, .69, volumeNoise(map, local * 3.5 + seed + 23));
    float pulse = .85 + .15 * sin(time * .8 + seed + convection * 4);
    float3 molten = color *(1.4 + convection * 1.5) + sqrt(max(color, float3(0))) * cracks * .65;
    float3 incandescent = crust + color *(.18 + plates * .55) + molten * cracks * 1.5 * pulse;
    return mix(ordinary, incandescent, heat);
}
// Icosahedral sites partition a shell into irregular polygonal fracture regions without a cube grid.
constant float3 fractureSites[12] = {
    float3(0, .525731, .850651), float3(0, - .525731, .850651),
    float3(0, .525731, - .850651), float3(0, - .525731, - .850651),
    float3(.525731, .850651, 0), float3(- .525731, .850651, 0),
    float3(.525731, - .850651, 0), float3(- .525731, - .850651, 0),
    float3(.850651, 0, .525731), float3(- .850651, 0, .525731),
    float3(.850651, 0, - .525731), float3(- .850651, 0, - .525731)
}
;
fragment half4 bodyFragment(Raster in [[stage_in]], texture2d < float > map [[texture(4)]]) {
    if (in.data.w <= 0) discard_fragment();
    float3 n = normalize(in.local);
    float3 normal = normalize(in.normal);
    float3 geometric = cross(dfdx(in.world), dfdy(in.world));
    geometric *= dot(geometric, normal) < 0 ? - 1 : 1;
    normal = normalize(geometric + normal * 1e-12);
    float progress = 0, fracture = 0, fractureEdge = 1;
    if (in.impact.z >= 0) {
        progress = saturate(in.impact.z / max(.001, in.impact.w));
        if (in.uv.y > .5) {
            float nearest = - 2, second = - 2;
            uint piece = 0;
            for (uint i = 0; i < 12; i ++) {
                float alignment = dot(n, fractureSites[i]);
                if (alignment > nearest) {
                    second = nearest;
                    nearest = alignment;
                    piece = i;
                }
                else second = max(second, alignment);
            }
            fractureEdge = nearest - second;
            fracture = .1 + .8 * latticeNoise(float3(piece, in.extra.x, 3));
            if (progress > fracture + .05 ||(progress > .05 && fractureEdge < .004 + progress * .014)) discard_fragment();
        }
        else {
            fracture = volumeNoise(map, n * 9 + in.extra.x);
            if (progress > fracture + .15) discard_fragment();
        }
    }
    float3 light = bodyLight(n, normal, in.color.rgb, in.extra.w,
    in.flight, in.extra.x, in.extra.y, map);
    if (in.impact.z >= 0) {
        light += in.color.rgb * exp(- abs(progress - fracture) * 24) *(1 - progress) * .8;
        if (in.uv.y > .5) light += in.color.rgb * exp(- fractureEdge * 120) *(1 - progress) * 1.5;
    }
    return half4(half3(light * in.data.w * in.extra.z), 1);
}
/// Impact flashes use transparent world-space billboards; body glow comes from its visible mesh.
vertex Raster impactFlashVertex(uint vid [[vertex_id]], uint instance [[instance_id]],
const device BodyGPU * bodies [[buffer(0)]], constant FrameUniformsGPU & f [[buffer(1)]]) {
    BodyGPU body = bodies[instance];
    Raster out = {
    }
    ;
    if (body.shape.z < 0) {
        out.position = float4(0, 0, - 1, 1);
        return out;
    }
    float hit = body.shape.z, radius = body.spatial.w;
    float flash = body.impactEffects.x > 0 ? body.impactEffects.x : body.impactEffects.y * .55;
    float flashScale = body.impactEffects.x > 0 ? .16 : .055;
    float energyRadius = flash > 0 ? max(radius, dot(body.spatial.xyz - cameraOrigin, cameraForward) * flashScale) : radius;
    float expansion = 1 - exp(- max(0.0, hit) * 7);
    float extent = hit >= 0 ?(flash > 0 ? energyRadius *(1.2 + 8 * expansion) : radius * 1.1 + hit * .7) : radius * 3 + .08;
    float3 center = hit >= 0 ? float3(body.cloud.xy, body.motion.x) : body.spatial.xyz;
    if (hit >= 0 && flash > 0) center.y += energyRadius * expansion * .8;
    float3 world = center + float3(corners[vid].x, 0, 0) * extent + cameraUp * corners[vid].y * extent;
    out.position = project(world, f);
    out.world = world;
    out.uv = corners[vid];
    out.color = body.color;
    out.data = float4(extent, radius, hit, body.position.w);
    out.extra = body.motion;
    out.impact = body.shape;
    out.normal = float3(flash, energyRadius, body.impactEffects.y);
    out.flight = float3(body.impactEffects.x, 0, 0);
    if (length(body.flight.xyz) > .5) {
        float3 relative = body.spatial.xyz - cameraOrigin;
        float2 screen = float2(relative.x, dot(relative, cameraUp)) / dot(relative, cameraForward);
        float2 rear = float2(body.flight.x, dot(body.flight.xyz, cameraUp)) - screen * dot(body.flight.xyz, cameraForward);
        out.impact.x = - rear.x / max(.0001, rear.y);
    }
    return out;
}
fragment half4 impactFlashFragment(Raster in [[stage_in]], texture2d < float > map [[texture(4)]]) {
    if (in.data.z >= 0 && in.normal.x > 0 && dot(in.uv, in.uv) >= 1) discard_fragment();
    float2 p = in.uv * in.data.x;
    float distance = length(p), hit = in.data.z;
    float3 light;
    if (hit < 0) discard_fragment();
    float radius = hit *(.4 + in.data.y * .15) + in.data.y * .25;
    float elliptical = length(p * float2(1, 1.65));
    float ringDistance =(elliptical - radius) /(.015 + hit * .03);
    float ring = exp(- ringDistance * ringDistance) * exp(- hit * 3);
    float core = exp(- dot(p, p) /(.008 + in.data.y * in.data.y * .2)) * exp(- hit * 6);
    light = in.color.rgb *(ring * .22 *(in.flight.x > 0 ? 0 : 1) + core * .7);
    if (in.normal.x > 0) {
        // A local fireball expands rapidly; its hot core cools before the colored ejecta settle.
        float scale = max(.12, in.normal.y);
        float fireRadius = scale *(.6 + 6 *(1 - exp(- hit * 7)));
        float turbulence = fbm(map, p / scale * 5 + float2(hit * 2, in.extra.w));
        float fire = exp(- pow(distance /(fireRadius *(.7 + turbulence * .5)), 2.0) * 2.2) * exp(- hit * 1.8);
        float shockDistance =(elliptical - scale * .3 - hit * scale * 7) /(scale * .16 + hit * .12);
        float shock = exp(- shockDistance * shockDistance) * exp(- hit * 2.4) *(in.flight.x > 0 ? 0 : 1);
        float3 hot = mix(in.color.rgb, float3(1, .24, .025), .28);
        float3 rim = mix(in.color.rgb, float3(.08, .45, 1), .4);
        float whiteCore = exp(- dot(p, p) /(scale * scale * .3)) * exp(- hit * 7);
        light +=(hot * fire * 3.5 + rim * shock * 2.5 + float3(1, .88, .58) * whiteCore * 5) * in.normal.x;
        light *= 1 - smoothstep(.72, 1.0, length(in.uv));
    }
    return half4(half3(light), 1);
}
/// Compact only living rock indices; the indirect draw avoids processing empty ring slots as meshes.
kernel void gatherChunks(const device ParticleGPU * particles [[buffer(0)]], device uint * indices [[buffer(1)]],
device atomic_uint * arguments [[buffer(2)]], constant FrameUniformsGPU & f [[buffer(3)]],
uint id [[thread_position_in_grid]]) {
    if (id == 0) atomic_store_explicit(arguments, 240, memory_order_relaxed);
    if (id >= f.counts.x) return;
    ParticleGPU p = particles[id];
    if (p.color.w == particleRockFragment && p.life.z > 0 && p.life.y < p.life.z) {
        uint slot = atomic_fetch_add_explicit(arguments + 1, 1, memory_order_relaxed);
        indices[slot] = id;
    }
}
constant uint tetraFaces[12] = {
    1, 2, 3, 0, 2, 1, 0, 3, 2, 0, 1, 3
}
;
/// Twenty closed fracture cells form one rock, then detach and fall as it burns through.
vertex Raster chunkVertex(uint vid [[vertex_id]], uint instance [[instance_id]],
const device ParticleGPU * particles [[buffer(0)]], constant FrameUniformsGPU & f [[buffer(1)]],
const device uint * indices [[buffer(3)]], const device float4 * terrain [[buffer(2)]]) {
    ParticleGPU p = particles[indices[instance]];
    Raster out = {
    }
    ;
    if (p.color.w != particleRockFragment || p.life.z <= 0 || p.life.y >= p.life.z) {
        out.position = float4(0, 0, - 1, 1);
        return out;
    }
    uint cell = vid / 12, base = cell * 3;
    float3 a = chunkCorner(chunkTriangles[base], p.life.w);
    float3 b = chunkCorner(chunkTriangles[base + 1], p.life.w);
    float3 c = chunkCorner(chunkTriangles[base + 2], p.life.w);
    float3 vertices[4] = {
        float3(0), a, b, c
    }
    ;
    uint face = vid % 12 / 3 * 3;
    float3 local = vertices[tetraFaces[vid % 12]], center =(a + b + c) * .25;
    float3 normal = normalize(cross(vertices[tetraFaces[face + 1]] - vertices[tetraFaces[face]],
    vertices[tetraFaces[face + 2]] - vertices[tetraFaces[face]]));
    if (dot(normal, vertices[tetraFaces[face]] - center) < 0) normal = - normal;
    float3 position = float3(p.position.xy, p.owner.z);
    float burn = p.owner.y >= dynamicsSettled ? max(0.0, p.life.y -(.65 + .7 * latticeNoise(float3(p.life.w, cell, 8)))) : 0;
    float4 rotation = p.orientation;
    float separation = 1;
    if (burn > 0) {
        float3 origin = position + rotateChunk(rotation, center) * p.life.x;
        float3 launch = normalize(rotateChunk(rotation, center) + float3(0, .25, 0)) * p.life.x *(.5 + .5 * fract(cell * .618));
        launch.y = abs(launch.y) + p.life.x * .2;
        float height = max(0.0, origin.y - sandField(origin.xz, terrain).x);
        float flight =(launch.y + sqrt(launch.y * launch.y + 6.4 * height)) / 3.2;
        float moving = min(burn, flight);
        float3 axis = normalize(center + float3(.17, .31, .23));
        float angle = moving *(2 + fract(cell * .73) * 3);
        rotation = multiplyRotation(float4(axis * sin(angle * .5), cos(angle * .5)), rotation);
        origin += float3(launch.x * moving * 1.3, launch.y * moving - 1.6 * moving * moving, launch.z * moving * 1.3);
        separation = 1 - .65 * smoothstep(0.0, .22, burn);
        float bottom = 1e6;
        for (uint i = 0; i < 4; i ++) bottom = min(bottom, rotateChunk(rotation, vertices[i] - center).y * p.life.x * separation);
        origin.y = max(origin.y, sandField(origin.xz, terrain).x - bottom);
        position = origin - rotateChunk(rotation, center) * p.life.x * separation;
    }
    out.world = position + rotateChunk(rotation, local) * p.life.x * separation;
    out.position = project(out.world, f);
    out.normal = rotateChunk(rotation, normal);
    out.local = local;
    out.color = p.color;
    out.data = float4(chunkHeat(p), p.life.w, p.life.y, p.owner.y);
    out.extra = float4(saturate((burn - .65) / 1.7), float(cell), 0, 0);
    return out;
}
/// Identical falloff, flash energy and diffuse response integrate soil and debris under later events.
float3 surfaceIrradiance(BodyGPU body, float3 world, float3 normal, float groundHeight) {
    float3 source = body.spatial.xyz;
    source.y = max(groundHeight + .15, source.y);
    float3 delta = source - world;
    float distanceSquared = max(.08, dot(delta, delta));
    float visible = body.motion.z * body.position.w;
    float age = body.shape.z, burst = age >= 0 ? exp(- age * 2.6) : 0;
    float energy =(visible + burst * 2 *(1 + body.impactEffects.x * 5 * exp(- max(0.0, age) * 3))) * body.spatial.w * body.spatial.w
    /(distanceSquared + body.spatial.w * body.spatial.w * .4 + .12) * 7;
    return body.color.rgb * min(7.0, energy) *(.08 + .92 * saturate(dot(normal, delta * rsqrt(distanceSquared))));
}
fragment half4 chunkFragment(Raster in [[stage_in]], constant FrameUniformsGPU & f [[buffer(0)]],
const device BodyGPU * bodies [[buffer(1)]], const device MeltPool * melts [[buffer(3)]],
texture2d < float > map [[texture(4)]], texture2d < float > emberLight [[texture(5)]],
const device float4 * terrain [[buffer(2)]]) {
    float3 normal = normalize(in.normal), light = float3(.001);
    float4 field = sandField(in.world.xz, terrain);
    if (in.extra.x > 0 && latticeNoise(floor(in.local * 31) + in.data.y) < in.extra.x * .995) discard_fragment();
    for (uint i = 0; i < f.counts.w; i ++) light += surfaceIrradiance(bodies[i], in.world, normal, field.x);
    float2 lightUV =(in.world.xz + float2(64, 112)) / 128;
    light += emberLight.sample(linearClamp, lightUV).rgb *(.3 + .7 * max(0.0, normal.y));
    for (uint i = 0; i < f.thermal.x; i ++) {
        MeltPool pool = melts[i];
        float3 d = float3(pool.location.x, 0, pool.location.y) - in.world;
        float heat = saturate(1 - pool.location.w / 8) * pool.shape.w;
        light += pool.color.rgb * heat * heat * .3 /(.2 + dot(d, d));
    }
    float texture = volumeNoise(map, in.local * 18 + in.data.y);
    float3 stone = mix(float3(.23, .205, .18), float3(.34, .33, .31), in.extra.x) *(.65 + texture * .5);
    float seam = abs(volumeNoise(map, in.local * 6 + in.data.y) - .5);
    float crack =(1 - smoothstep(.012, .05, seam)) * smoothstep(.32, .65, volumeNoise(map, in.local * 13 + in.data.y + 7));
    float heat = in.data.x;
    float3 hotColor = mix(float3(1, .055, .003), mix(float3(1, .38, .035), in.color.rgb, .25), heat);
    float3 emission = hotColor * pow(heat, 1.8) *(.18 + crack * 4);
    float horizon = 1 - smoothstep(32.0, 110.0, - in.world.z);
    return half4(half3((stone * light + emission) * horizon), 1);
}
vertex Raster particleVertex(uint vid [[vertex_id]], uint instance [[instance_id]],
const device ParticleGPU * particles [[buffer(0)]], constant FrameUniformsGPU & f [[buffer(1)]],
const device float4 * terrain [[buffer(2)]]) {
    ParticleGPU p = particles[instance];
    Raster out;
    float a = p.life.y / max(.001, p.life.z);
    bool alive = p.life.z > 0 && a < 1 && p.color.w != particleRockFragment, hot = p.color.w == particleEmber;
    float size = p.life.x *(hot || p.color.w == particleRegolithGrain ? 1 :(1 + a *(p.color.w == particleSoilDust ? .65 : 2.1)));
    float angle = hot ? atan2(p.position.w, p.position.z) : p.life.w + a * .25;
    float2 shape = corners[vid];
    if (p.color.w == particleEmber) shape.x *= 1 + min(4.0, length(p.position.zw) * 2);
    if (p.color.w == particleImpactGas) shape *= float2(1.15, .88);
    float2 rotated = float2(shape.x * cos(angle) - shape.y * sin(angle), shape.x * sin(angle) + shape.y * cos(angle));
    float expansion = f.options.w > .5 ? 1.3 : 1;
    float3 world = float3(p.position.xy, p.owner.z) +(float3(rotated.x * size, 0, 0) + cameraUp * rotated.y * size) * expansion;
    if (p.color.w == particleRegolithGrain && p.owner.y >= dynamicsSettled) {
        // Resting chunks lie along the local ground rather than remaining upright camera-facing cards.
        float2 offset = float2(shape.x * cos(p.life.w) - shape.y * sin(p.life.w),
        shape.x * sin(p.life.w) + shape.y * cos(p.life.w)) * size;
        float2 point = float2(p.position.x, p.owner.z) + offset;
        world = float3(point.x, sandField(point, terrain).x + size * .35, point.y);
    }
    if (p.color.w == particleIonTrail || p.color.w == particlePlasmaTrail) {
        float3 rear = normalize(float3(p.position.zw, p.owner.w));
        float3 across = normalize(cross(rear, - cameraForward));
        // Perspective acts on the full XYZ filament, including flights toward and away from the camera.
        world = float3(p.position.xy, p.owner.z) +(across * corners[vid].x
        + rear * corners[vid].y *(p.color.w == particlePlasmaTrail ? 3.4 : 5.2)) * size * expansion;
    }
    float3 projectedWorld = world;
    if (f.options.w > .5) projectedWorld.y = - projectedWorld.y;
    out.position = alive ? project(projectedWorld, f) : float4(3, 3, 0, 1);
    out.world = world;
    out.uv = corners[vid] * expansion;
    out.color = p.color;
    out.data = float4(a, p.life.w, p.life.y, p.life.z);
    out.extra = float4(f.viewport.w, length(p.position.zw), p.owner.z, size);
    out.impact = float4(p.owner.y, 0, 0, 0);
    return out;
}
/// Cooling depends on particle age so paused fragments and their illumination remain frozen.
float3 coolingColor(float age) {
    return mix(float3(1, .035, .002), float3(1, .48, .065), exp(- age * 3));
}
/// Incandescent fragments and dusty airborne material share the same scene clock.
half4 particleLight(Raster in, texture2d < float > map, float2 p) {
    float d = length(p), a = in.data.x, seed = in.data.y;
    float3 c = in.color.rgb, hot = mix(c, float3(1, .72, .34), .36);
    if (in.color.w == particleRegolithGrain) {
        float edge = 1 - smoothstep(.45, .85, length(p * float2(1, 1.3)));
        float alpha = edge *(in.impact.x >= 2 ? pow(1 - a, 1.5) : 1);
        return half4(half3(c *(.3 + .5 * saturate(p.y + .5)) * alpha), half(alpha));
    }
    if (in.impact.x >= 2) {
        hot = coolingColor(a);
        c = hot;
    }
    if (in.color.w >= particleIonTrail) {
        float age = in.data.z;
        float2 flow = float2(p.x * 2.8, p.y * 3.6 - age * 2.1) + seed;
        float billow = fbm(map, flow);
        float curl = fbm(map, flow * .73 + float2(age * .4, - age * .3) + 17);
        float strands = pow(1 - abs(sin(p.x * 10 +(curl - .5) * 7 + p.y * 1.8)), 3.0);
        float edge = pow(saturate(1 - p.y * p.y), .8) * exp(- p.x * p.x * 3.5);
        float texture = smoothstep(.20, .72, billow) *(.30 + strands * .70);
        float fade = smoothstep(0.0, .05, age) * pow(saturate(1 - a), 1.4);
        float alpha = edge * texture * fade *(in.color.w == particlePlasmaTrail ? .055 : .10);
        float heat = exp(- a * 2.4);
        float3 light = mix(c * .6, c * 1.8 + hot * .45, heat) + c * strands * .7;
        return half4(half3(light * alpha), half(alpha));
    }
    if (in.color.w == particleSoilDust) {
        if (d > 1) discard_fragment();
        float billow = fbm(map, p * 4 + seed + in.data.z * .18);
        float alpha = smoothstep(.18 + a * .32, .65 + a * .2, billow) * pow(1 - d * d, 1.1)
        * smoothstep(0.0, .008, in.data.z) * pow(1 - a, 1.3) * .22;
        float shade = .6 + billow * .8 - p.x * .15 + p.y * .2;
        return half4(half3(c * shade * alpha), half(alpha));
    }
    if (d > 1) discard_fragment();
    if (in.color.w == particleEmber) {
        float light = exp(- d * d * 12) * pow(1 - a, 1.5);
        return half4(half3((c * 1.9 + hot * .8) * light), half(light * .25));
    }
    float z = sqrt(max(0.0, 1 - d * d));
    float2 uv = p * 3 + seed;
    float drift = in.data.z * .30;
    float front = fbm(map, uv + float2(drift, - drift * .6) + z * 1.4);
    float middle = fbm(map, uv * 1.19 + float2(- drift * .6, drift) + z * .4 + 11);
    float rear = fbm(map, uv * .83 + float2(drift * .4, drift * .5) - z * .9 - 17);
    float billow = front * .46 + middle * .34 + rear * .20;
    float erosion = .24 + pow(a, 1.05) * .53;
    float density = smoothstep(erosion, erosion + .18, billow) * pow(max(0.0, 1 - d * d), 1.25);
    float heat = exp(- a *(in.color.w == particleImpactGas ? 8 : 14));
    float formation = smoothstep(0.0, .025, in.data.z);
    float shade = .34 + .66 * saturate(z * .65 - p.x * .28 + p.y * .36 +(front - rear) * 1.8);
    float alpha = density * formation *(in.color.w == particleImpactGas ? .30 : .12) *(1 - a);
    float3 gas = c *(.38 + shade * .85) + hot * heat *(in.color.w == particleImpactGas ? 2.4 : 3.0);
    return half4(half3(gas * alpha), half(alpha));
}
/// Terrain depth, rather than a mirror pass, clips smoke and settled embers at crater rims.
fragment half4 particleFragment(Raster in [[stage_in]], texture2d < float > map [[texture(4)]],
depth2d < float > depth [[texture(3)]], constant FrameUniformsGPU & f [[buffer(0)]],
const device BodyGPU * bodies [[buffer(1)]], const device MeltPool * melts [[buffer(3)]]) {
    float4 projected = project(in.world, f);
    float2 uv = projected.xy / projected.w * float2(.5, - .5) + .5;
    if (in.position.z > depth.sample(linearClamp, uv) + .00003) discard_fragment();
    half4 material = particleLight(in, map, in.uv);
    if (in.color.w == particleSoilDust || in.color.w == particleRegolithGrain) {
        float3 illumination = float3(.004);
        for (uint i = 0; i < f.counts.w; i ++) {
            BodyGPU body = bodies[i];
            float age = body.shape.z;
            float energy = age < 0 ? body.motion.z * body.position.w : exp(- age * 1.3) *(1 + body.impactEffects.x * 3 * exp(- age * 4));
            float3 delta = body.spatial.xyz - in.world;
            illumination += body.color.rgb * energy * body.spatial.w * body.spatial.w * 5 /(dot(delta, delta) + .3);
        }
        for (uint i = 0; i < f.thermal.x; i ++) {
            MeltPool pool = melts[i];
            float2 offset = in.world.xz - pool.location.xy;
            float distance = dot(offset, offset) /(pool.location.z * pool.location.z);
            if (distance < 9) {
                float heat = pow(saturate(1 - pool.location.w / 8), 2) * pool.shape.w;
                illumination += pool.color.rgb * heat * 2 /(1 + distance * 3);
            }
        }
        material.rgb *= half3(min(float3(2), illumination));
    }
    return material;
}
/// Each hot fragment splats into a world-space light map, avoiding a per-pixel particle scan.
/// ParticleGPU buffer 0 and terrain buffer 2 are read only after the evolve compute encoder completes.
vertex Raster emberGroundVertex(uint vid [[vertex_id]], uint instance [[instance_id]],
const device ParticleGPU * particles [[buffer(0)]], constant FrameUniformsGPU & f [[buffer(1)]],
const device float4 * terrain [[buffer(2)]]) {
    ParticleGPU p = particles[instance];
    Raster out = {
    }
    ;
    bool alive = p.life.z > 0 && p.life.y < p.life.z &&(p.color.w == particleEmber || p.color.w == particleRockFragment);
    float height = p.position.y - sandField(float2(p.position.x, p.owner.z), terrain).x;
    float radius = max(.06, p.life.x *(p.color.w == particleRockFragment ? 16 : 22));
    float heat = p.color.w == particleRockFragment ? chunkHeat(p) : saturate(1 - p.life.y / max(.001, p.life.z));
    float strength = pow(heat, 1.6) * exp(- max(0.0, height) * 5);
    float2 point = float2(p.position.x, p.owner.z) + corners[vid] * radius;
    float2 uv =(point + float2(64, 112)) / 128;
    out.world = float3(point.x, 0, point.y);
    float contact = p.color.w == particleRockFragment ? exp(- max(0.0, height - chunkSupport(p)) * 18)
    *(p.owner.y >= dynamicsSettled ? 1 - smoothstep(.8, 3.2, p.life.y) : 1) : 0;
    out.position = alive &&(strength > .001 || contact > .01) ? float4(uv * float2(2, - 2) + float2(- 1, 1), 0, 1) : float4(3, 3, 0, 1);
    out.data = float4(p.life.x / radius, contact, 0, 0);
    out.uv = corners[vid];
    float3 color = p.owner.y >= dynamicsSettled ? coolingColor(1 - heat) : mix(p.color.rgb, float3(1, .4, .04), .5);
    out.color = float4(color, strength *(p.color.w == particleRockFragment ? .7 : .12));
    return out;
}
fragment half4 emberGroundFragment(Raster in [[stage_in]]) {
    float d = dot(in.uv, in.uv);
    if (d > 1) discard_fragment();
    float intensity = exp(- d * 4) * pow(1 - d, 1.5) * in.color.w * 2;
    float shadow = exp(- d / max(.00001, in.data.x * in.data.x * 2.4)) * in.data.y * .8;
    return half4(half3(in.color.rgb * intensity), half(shadow));
}
/// The perspective mesh covers the foreground and horizon; crater state remains in world coordinates.
vertex Raster sandVertex(uint vid [[vertex_id]], constant FrameUniformsGPU & f [[buffer(1)]],
const device float4 * terrain [[buffer(2)]]) {
    Raster out = {
    }
    ;
    float2 grid = float2(vid % 257, vid / 257);
    float distance = .45 * pow(260.0, grid.y / 256);
    float x =(grid.x / 256 - .5) * distance * f.viewport.z / activeHeight(f) * 1.4;
    float4 field = sandField(float2(x, - distance), terrain);
    out.world = float3(x, field.x, - distance);
    out.position = project(out.world, f);
    return out;
}
fragment half4 sandFragment(Raster in [[stage_in]], constant FrameUniformsGPU & f [[buffer(0)]],
const device BodyGPU * bodies [[buffer(1)]], texture2d < float > map [[texture(4)]],
texture2d < float > emberLight [[texture(5)]],
const device float4 * terrain [[buffer(2)]], const device MeltPool * melts [[buffer(3)]]) {
    float4 field = sandField(in.world.xz, terrain);
    float2 p = in.world.xz;
    float footprint = max(length(dfdx(p)), length(dfdy(p)));
    float2 grit = float2(noise(map, p * 28), noise(map, p * 28 + 71)) - .5;
    float3 normal = normalize(float3(- field.y + grit.x * .12 * exp(- footprint * 8), 1,
    - field.z + grit.y * .12 * exp(- footprint * 8)));
    float grain = mix(fbm(map, p * 90), .5, smoothstep(.012, .08, footprint));
    float mottling = fbm(map, p * 3.7);
    float3 albedo = mix(float3(.26, .27, .29), float3(.48, .49, .51), grain) *(.8 + mottling * .35);
    albedo *= 1 + saturate(- field.w) * .55;
    albedo *= 1 - field.w * .42;
    if (field.w > .85) albedo = mix(albedo, float3(.055, .046, .04) *(1 + grain * .35), smoothstep(.85, 1.1, field.w));
    float diffuse = .0004 + .001 * saturate(dot(normal, normalize(float3(- .8, .35, .4))));
    // Dark bowls and grazing illumination distinguish excavation from a painted circle.
    float cavity = 1 - saturate(- field.x) * .28;
    float3 light = albedo * diffuse * cavity;
    float2 lightUV =(p + float2(64, 112)) / 128;
    if (all(lightUV >= 0) && all(lightUV <= 1)) {
        light += albedo * emberLight.sample(linearClamp, lightUV).rgb *(.65 + .35 * normal.y);
    }
    for (uint i = 0; i < f.counts.w; i ++) {
        BodyGPU body = bodies[i];
        float age = body.shape.z;
        light += albedo * surfaceIrradiance(body, in.world, normal, field.x);
        // A short cooling bed of small coals anchors the impact after the airborne cloud lifts.
        if (body.contact.w > .5 && age >= 0) {
            float radius = max(.38, body.spatial.w * 1.9);
            float2 q =(p - body.contact.xz) / radius;
            float bed = exp(- dot(q, q) * 3) * exp(- age * 1.8);
            float coals = pow(smoothstep(.65, .9, noise(map, p * 210 + body.motion.w)), 3.0);
            light += float3(1, .19, .018) * bed * coals * .8;
        }
    }
    light *= 1 - emberLight.sample(linearClamp, lightUV).a * .7;
    // Molten sand and metal occupy the excavated floor. Stationary crust plates grow over a moving hot interior.
    for (uint i = 0; i < f.thermal.x; i ++) {
        MeltPool pool = melts[i];
        float2 offset = p - pool.location.xy, axis = pool.shape.xy;
        float2 q = float2(dot(offset, axis) / 1.12, dot(offset, float2(- axis.y, axis.x))) / pool.location.z;
        float radiusSquared = dot(q, q);
        if (radiusSquared > 9) continue;
        float age = pool.location.w, thermal = saturate(1 - age / 8);
        float3 warm = pool.color.rgb;
        light += albedo * warm * exp(- radiusSquared * .8) * thermal * thermal * pool.shape.w * .65;
        if (radiusSquared > 1.3) continue;
        float plates = fbm(map, q * 6 + pool.shape.z);
        float boundary = .92 +(plates - .5) * .17;
        float coverage =(1 - smoothstep(boundary - .12, boundary, sqrt(radiusSquared))) * smoothstep(.05, .4, field.w);
        // The colder shoreline seals first; fixed plates close over the moving interior.
        float cooling = age / 6 + smoothstep(.15, .95, sqrt(radiusSquared)) * .18;
        float crust = smoothstep(plates - .1, plates + .12, cooling);
        float flow = fbm(map, q * 9 + pool.shape.z + float2(age * .23, - age * .13));
        float streams = .5 + .5 * sin(q.x * 14 + q.y * 7 + flow * 7 - age * 1.3);
        float fractures = pow(1 - abs(sin(plates * 27)), 8.0);
        float3 hot = warm *(.65 + streams * .7 + flow * .3);
        float ember = pow(thermal, 1.4) *(1 - smoothstep(6.5, 8.0, age));
        light *= 1 - coverage * crust * .45;
        light += hot *((1 - crust) *(.6 + streams * .4) + fractures * .45 * thermal)
        * coverage * ember *(2 + pool.shape.w * 3);
    }
    float horizon = 1 - smoothstep(32.0, 110.0, - in.world.z);
    return half4(half3(light * horizon), 1);
}
vertex Raster screenVertex(uint id [[vertex_id]]) {
    Raster out;
    out.uv = corners[id] * .5 + .5;
    out.position = float4(corners[id], 0, 1);
    return out;
}
/// Optical path through a thin spherical pressure shell, clipped by the opaque scene depth.
/// Radius matches ShockPhysics on the host; the fixed contact point is independent of cloud drift.
float2 shockLens(float2 uv, constant FrameUniformsGPU & f, const device BodyGPU * bodies,
depth2d < float > depth, texture2d < float > map, thread float3 & glow, thread float & frontDepth) {
    float3 ray = normalize(cameraForward + float3((uv.x - .5) * f.viewport.z / activeHeight(f), 0, 0)
    + cameraUp *(.5 - uv.y) / activeHeight(f));
    float z = depth.sample(linearClamp, uv);
    float opaqueDistance =(5.0 / 99.95) / max(.000001, 100.0 / 99.95 - z) / dot(ray, cameraForward);
    float2 displacement = 0;
    glow = 0;
    frontDepth = 1;
    for (uint i = 0; i < f.counts.w; i ++) {
        BodyGPU body = bodies[i];
        float age = body.shape.z;
        if (body.impactEffects.x <= 0 || age <= 0 || age >= 1.6) continue;
        float radius = max(.08, body.spatial.w) *(.65 + 10 * age /(1 + .45 * age));
        float thickness = max(.025, radius * .055);
        float3 relative = cameraOrigin - body.contact.xyz;
        float along = dot(relative, ray);
        float closest = dot(relative, relative) - along * along;
        float outer = radius + thickness * 2.5, inner = max(.001, radius - thickness * 4);
        float discriminant = outer * outer - closest;
        if (discriminant <= 0) continue;
        float chord = sqrt(discriminant);
        float entry = max(0.0, - along - chord), exit = min(opaqueDistance, - along + chord);
        if (exit <= entry) continue;
        float path = exit - entry;
        float innerChord = sqrt(max(0.0, inner * inner - closest));
        path -= max(0.0, min(exit, - along + innerChord) - max(entry, - along - innerChord));
        float column = saturate(path / max(.001, 2 * sqrt(outer * outer - inner * inner)));
        float surface = - along - chord > 0 ? - along - chord : - along + chord;
        if (surface <= 0 || surface >= opaqueDistance) continue;
        float3 point = cameraOrigin + ray * surface;
        float3 normal = normalize(point - body.contact.xyz);
        float4 projectedPoint = project(point, f);
        frontDepth = min(frontDepth, projectedPoint.z / projectedPoint.w);
        float3 turbulence = point * 1.7 + body.motion.w + float3(age * .7, - age * 1.2, age * .3);
        float ripple = volumeNoise(map, turbulence);
        float wakeNoise = volumeNoise(map, turbulence * 1.31 + 19);
        float fade = smoothstep(0.0, .045, age) *(1 - smoothstep(.6, 1.6, age));
        // Opposite refraction gradients compress the leading front and stretch its rarefied wake.
        // Their location comes from the 3D ray'body impact parameter, never a screen-space ellipse.
        float band =(sqrt(max(0.0, closest)) - radius) / thickness;
        float compression = exp(- pow((band + .4) / 1.2, 2.0));
        float rarefaction = exp(- pow((band + 3.2) / 2.4, 2.0));
        float profile = compression - rarefaction * .72;
        if (length(relative) < inner) profile = column * .18;
        float2 projected = float2(normal.x, - dot(normal, cameraUp));
        float angularRadius = radius / max(.1, length(relative));
        float strength = min(.055, angularRadius * .14);
        float2 wake = float2(ripple - .5, wakeNoise - .5) * rarefaction * .012;
        displacement +=(projected * profile * strength *(.8 + ripple * .5) + wake)
        * float2(1 / f.viewport.z, 1) * fade;
        // Colored scattering is faint; the moving background, rather than emission, reveals the front.
        glow += mix(body.color.rgb, float3(.08, .45, 1), .4) * compression * column * fade * .022;
    }
    float magnitude = length(displacement);
    return displacement * min(1.0, .045 / max(.00001, magnitude));
}
fragment half4 compositeFragment(Raster in [[stage_in]], constant FrameUniformsGPU & f [[buffer(0)]],
texture2d < float > scene [[texture(0)]], texture2d < float > material [[texture(1)]],
depth2d < float > depth [[texture(3)]], texture2d < float > map [[texture(4)]],
const device BodyGPU * bodies [[buffer(1)]]) {
    // Move the entire composed world together; physics, illumination maps and UI remain stationary.
    float2 uv = float2(in.uv.x, 1 - in.uv.y) + float2(f.controls.z / f.viewport.z, f.controls.w);
    float3 shockGlow = 0;
    float frontDepth = 1;
    if (f.thermal.y > 0) {
        float2 offset = shockLens(uv, f, bodies, depth, map, shockGlow, frontDepth);
        float2 warped = clamp(uv + offset, float2(0), float2(1));
        // Never pull a closer silhouette across a background shell'body optical boundary.
        float there = depth.sample(linearClamp, warped);
        if (there >= frontDepth - .00001) uv = warped;
    }
    float3 light = scene.sample(linearClamp, uv).rgb;
    float2 pixel = 1.0 / float2(material.get_width(), material.get_height());
    float3 gas = material.sample(linearClamp, uv).rgb, bloom = 0;
    for (int y = - 1; y <= 1; y ++) for (int x = - 1; x <= 1; x ++)
    bloom += material.sample(linearClamp, uv + float2(x, y) * pixel * 5).rgb;
    // Diffuse the visible rocky mesh itself, rather than painting a circular proxy around it.
    float3 rockGlow = 0;
    for (uint bodyIndex = 0; bodyIndex < f.counts.w; bodyIndex ++) {
        BodyGPU body = bodies[bodyIndex];
        if (body.shape.z >= 0 || body.position.w <= 0) continue;
        float4 center = project(body.spatial.xyz, f);
        if (center.w <= .05) continue;
        float2 centerUV = center.xy / center.w * float2(.5, - .5) + .5;
        float2 radiusUV = body.spatial.w * activeHeight(f) / center.w * float2(1 / f.viewport.z, 1);
        if (any(abs(uv - centerUV) > radiusUV * 1.4)) continue;
        for (int gy = - 3; gy <= 3; gy ++) for (int gx = - 3; gx <= 3; gx ++) {
            float2 sampleUV = uv + float2(gx, gy) * radiusUV * .09;
            float sampleDepth = depth.sample(linearClamp, sampleUV);
            float distance = 5.0 /(100.0 - sampleDepth * 99.95);
            float2 clip =(sampleUV - .5) * float2(2, - 2);
            float3 point = cameraOrigin + cameraForward * distance
            + float3(1, 0, 0) * clip.x * distance * f.viewport.z /(2 * activeHeight(f))
            + cameraUp * clip.y * distance /(2 * activeHeight(f));
            if (length(point - body.spatial.xyz) > body.spatial.w * 1.12) continue;
            // Opaque foreground silhouettes must not receive light from a hidden body.
            float here = depth.sample(linearClamp, uv);
            if (here < sampleDepth - .0003) continue;
            float weight = exp(- float(gx * gx + gy * gy) * .25);
            rockGlow += scene.sample(linearClamp, sampleUV).rgb * weight * .035;
        }
    }
    float transmittance = 1 - saturate(material.sample(linearClamp, uv).a);
    light =(light + rockGlow) * transmittance + gas + bloom * .09 + shockGlow;
    light *= f.controls.y * f.options.x;
    float3 mapped = 1 - exp(- light * 1.15);
    if (f.options.y < .5) {
        float target = 21.0 / 9.0;
        if (f.viewport.z > target && abs(in.uv.x - .5) > .5 * target / f.viewport.z) mapped = 0;
        if (f.viewport.z < target && abs(in.uv.y - .5) > .5 * f.viewport.z / target) mapped = 0;
    }
    return half4(half3(mapped), 1);
}
