#include <metal_stdlib>
using namespace metal;

struct Particle { float4 position, life, color, owner; };
struct Sun { float4 position, color, motion, cloud, shape; };
struct Frame { float4 viewport, controls; uint4 counts; float4 options; };
struct Raster { float4 position [[position]]; float2 uv; float4 color; float4 data; float4 extra; float4 impact; };
constant float2 corners[6] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(-1,1),float2(1,-1),float2(1,1)};
constexpr sampler linearRepeat(filter::linear, address::repeat);
constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);

float4 clip(float2 p, constant Frame &f) { return float4(p.x*2/f.viewport.z,p.y*2,0,1); }
float noise(texture2d<float> map, float2 p) { return map.sample(linearRepeat,p/128).r; }
float fbm(texture2d<float> map, float2 p) {
    return noise(map,p)*.57+noise(map,p*2.07+17)*.28+noise(map,p*4.13-23)*.15;
}

/// Every live particle is updated once; emission overwrites only its reserved ring range.
kernel void evolve(device Particle *particles [[buffer(0)]], const device Particle *spawns [[buffer(1)]],
                   constant Frame &f [[buffer(2)]], const device Sun *suns [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    if(id>=f.counts.x)return;
    uint offset=(id+f.counts.x-f.counts.z)%f.counts.x;
    Particle p=offset<f.counts.y?spawns[offset]:particles[id];
    if(f.options.z>.5 && offset>=f.counts.y) { p.life=float4(0);particles[id]=p;return; }
    if(p.life.z<=0 || p.life.y>=p.life.z)return;
    float dt=f.controls.x;
    float2 pos=p.position.xy,vel=p.position.zw;
    if(p.color.w==1 || p.color.w==3) { vel.y-=dt*(p.color.w==3?.16:.085); vel*=exp(-dt*.10); }
    else {
        for(uint i=0;i<f.counts.w;i++) {
            Sun s=suns[i];
            if(abs(p.owner.x-s.color.w)<.1 && s.motion.y>=0 && p.owner.y<.5) {
                float2 radial=pos-s.cloud.xy;
                vel+=radial/max(.015,length(radial))*(.06+.04*sin(p.life.w));
                p.owner.y=1;
            }
            // The impact tears the broad rear shell into dust instead of preserving a ghost sun.
            if(abs(p.owner.x-s.color.w)<.1 && s.motion.y>=0 && p.color.w==0) {
                p.life.y+=dt*(1+s.motion.y*2.5);
                if(fract(p.life.w*.173)<smoothstep(.22,1.1,s.motion.y)) {
                    p.color.w=1;
                    p.life.x=min(p.life.x,.0025);
                }
            }
        }
        float2 curl=float2(sin(pos.y*31+p.life.w+f.viewport.w*.37),cos(pos.x*29-p.life.w+f.viewport.w*.29));
        vel+=curl*dt*.009;
        vel.y+=dt*(p.color.w==2?.012:.002);
        // Soft inter-cloud pressure separates colors without positional jumps.
        if(p.color.w==2) for(uint i=0;i<f.counts.w;i++) {
            Sun s=suns[i];
            if(abs(p.owner.x-s.color.w)<.1 || s.cloud.w<=0)continue;
            float2 d=pos-s.cloud.xy;
            float radius=s.cloud.z*.85;
            float distance=length(d);
            if(distance<radius)vel+=d/max(.004,distance)*(radius-distance)*s.cloud.w*dt*2.5;
        }
        vel*=exp(-dt*(p.color.w==2?.19:.4));
    }
    float limit=f.viewport.z*.5;
    if(abs(pos.x)>limit)vel.x-=sign(pos.x)*(abs(pos.x)-limit)*dt;
    if(pos.y<-.51 && p.color.w!=1 && p.color.w!=3)vel.y+=(-.51-pos.y)*dt;
    p.position=float4(pos+vel*dt,vel);
    p.life.y+=dt;
    particles[id]=p;
}

/// Local +Y points along the rear of the trajectory, including tilted small meteors.
vertex Raster starVertex(uint vid [[vertex_id]], uint instance [[instance_id]],
                         const device Sun *suns [[buffer(0)]], constant Frame &f [[buffer(1)]]) {
    Sun s=suns[instance]; Raster out;
    float meteor=s.shape.y;
    out.uv=corners[vid]*1.5;
    float2 rear=normalize(float2(-s.shape.x,1));
    float2 across=float2(rear.y,-rear.x);
    out.position=clip(s.position.xy+(across*out.uv.x+rear*out.uv.y)*s.position.z,f);
    out.color=s.color; out.data=s.position;
    out.extra=float4(s.motion.w,f.viewport.w,s.motion.z,meteor);
    out.impact=s.shape;
    return out;
}

fragment half4 starFragment(Raster in [[stage_in]], texture2d<float> map [[texture(4)]]) {
    if(in.data.w<=0)discard_fragment();
    float meteor=in.extra.w;
    float t=in.extra.y, seed=in.extra.x;
    float2 p=in.uv;

    // A tumbling, compact rock sits inside the ablation layer. No rigid pointed droplet silhouette.
    float2 q=p/float2(1-meteor*.16,1+meteor*.08);
    float d=length(q);
    if(d>1.48)discard_fragment();
    float angle=atan2(q.y,q.x);
    float rough=fbm(map,q*5+seed);
    float asymmetry=sin(angle*3+seed+t*.12)*.09+sin(angle*5-seed*.7)*.045;
    float boundary=1+(rough-.5)*mix(.045,.12,meteor)+asymmetry*meteor;
    float sd=d-boundary;
    float3 c=in.color.rgb;

    float field=noise(map,float2(angle*23+seed,t*.9+seed));
    float stream=noise(map,float2(angle*61-t*.28,d*19-t*1.6+seed));
    float filaments=pow(saturate(field*.72+stream*.62),3.0);
    float rim=exp(-abs(sd)*mix(35.0,26.0,meteor));
    float outer=exp(-max(0.0,sd)*16)*smoothstep(-.025,.025,sd);
    float facing=smoothstep(.05,.8,-q.y);
    float3 hot=mix(c,float3(1,.82,.58),.22);
    float3 light=hot*rim*(.45+filaments*1.8)*mix(1.0,.18+facing*.65,meteor);
    light+=c*outer*filaments*mix(.65,.08+facing*.18,meteor);
    if(meteor<.95 && sd>-.04) {
        // Sparse magnetic arches rise above the solar limb; they do not become a uniform neon outline.
        for(int i=0;i<3;i++) {
            float phase=seed+float(i)*2.39996;
            float theta=phase+t*.018;
            float2 radial=float2(cos(theta),sin(theta));
            float2 tangent=float2(-radial.y,radial.x);
            float height=.12+.065*(.5+.5*sin(t*.22+phase));
            float2 loop=float2(dot(q,tangent)/.13,(dot(q,radial)-.97)/height);
            float arcAngle=atan2(loop.y,loop.x);
            float distortion=.055*sin(arcAngle*7+t*.7+phase);
            float density=noise(map,float2(arcAngle*13+t*.18,phase*9));
            float arc=exp(-abs(length(loop)-1+distortion)/(0.035+density*.055));
            float outside=smoothstep(.99,1.04,d)*(1-smoothstep(1.28,1.38,d));
            float activity=smoothstep(.2,.75,.5+.5*sin(t*.15+phase*1.3));
            light+=hot*arc*outside*(1-meteor)*activity*(.25+density)*.85;
        }
    }
    // A compressed bow layer and glowing ablation rim distinguish the fast small bodies.
    float bow=exp(-abs(sd-.09)*38)*facing*meteor;
    light+=mix(c,float3(1,.76,.46),.42)*bow*1.1;

    if(sd<0) {
        float normalized=d/boundary;
        float z=sqrt(max(0.0,1-normalized*normalized));
        float2 sphere=q/(.34+z*.66);
        float2 uv=sphere*18+float2(t*.19,seed);
        float warp=fbm(map,uv*.37+float2(t*.04,-t*.03));
        float cells=fbm(map,uv+float2(warp*4,-warp*3));
        float fine=noise(map,uv*5.2+cells*2);
        float grain=smoothstep(.44,.83,fine);
        float lanes=1-abs(sin(cells*16+fine*1.2));
        float veins=pow(lanes,7.0);
        float limb=.23+.77*pow(z,.65);
        float convection=smoothstep(.22,.77,cells);
        float spots=1-smoothstep(.66,.83,noise(map,uv*.26))*.62;
        float3 solar=mix(c*.28,c*2.35+float3(.25,.12,.035),convection)*spots;
        solar+=c*veins*.65+hot*grain*.21;
        solar*=limb;

        float3 normal=normalize(float3(q/max(.1,d)*normalized,z));
        float relief=.28+.72*saturate(dot(normal,normalize(float3(-.45,-.6,.75))));
        float cracks=smoothstep(.66,.95,lanes);
        float melt=smoothstep(.46,.73,cells+fine*.13);
        float3 crust=c*(.055+.16*convection)*relief;
        float3 lava=hot*(cracks*.95+melt*.75)*(.4+.6*relief);
        float hotFace=pow(saturate(-q.y),3.0)*1.4;
        float3 meteorBody=crust+lava+(c+hot*.38)*hotFace;
        light+=mix(solar,meteorBody,meteor)*(1-smoothstep(-.012,0.0,sd));
    }
    // Fractures travel through the visible volume, so a giant does not vanish into a point-sized burst.
    float breakup=1;
    if(in.impact.z>=0) {
        float progress=saturate(in.impact.z/max(.1,in.impact.w));
        float fracture=fbm(map,q*9+seed);
        breakup=1-smoothstep(fracture-.16,fracture+.08,progress);
        float inside=1-smoothstep(-.03,.015,sd);
        float front=exp(-abs(progress-fracture)*24)*(1-progress)*inside;
        breakup=mix(1.0,breakup,inside);
        light+=hot*front*1.35;
    }
    return half4(half3(light*in.data.w*in.extra.z*breakup),1);
}

/// Cheap large halos and localized impact shells are separate from detailed solar shading.
vertex Raster haloVertex(uint vid [[vertex_id]], uint instance [[instance_id]],
                         const device Sun *suns [[buffer(0)]], constant Frame &f [[buffer(1)]]) {
    Sun s=suns[instance]; Raster out;
    float hit=s.motion.y;
    float r=s.position.z;
    float extent=hit>0?min(2.2,.20+r*1.5+hit*.45):r*5+.06;
    float2 center=hit>0?s.cloud.xy:s.position.xy;
    out.uv=corners[vid];out.position=clip(center+out.uv*extent,f);
    out.color=s.color;out.data=float4(extent,r,hit,s.position.w);out.extra=s.motion;
    return out;
}

fragment half4 haloFragment(Raster in [[stage_in]],texture2d<float> map [[texture(4)]]) {
    float2 p=in.uv*in.data.x;
    float distance=length(p);
    float hit=in.data.z;
    float3 light;
    if(hit<=0) {
        float q=distance/max(.03,in.data.y);
        light=in.color.rgb*(exp(-q*q*.55)*.16+exp(-q*1.4)*.045)*in.extra.z;
    } else {
        float r=in.data.y;
        float angle=atan2(p.y,p.x);
        float distortion=1+.045*sin(angle*7+in.extra.w)+.035*sin(angle*11-hit);
        float elliptical=length(p*float2(1,1.65))*distortion;
        float radius=hit*(.28+r*.27)+r*.32;
        float ring=exp(-pow((elliptical-radius)/(.007+hit*.013+r*.014),2))*exp(-hit*2.5);
        float core=exp(-dot(p,p*float2(1,1.4))/(.0015+r*r*.22))*exp(-hit*6);
        float turbulence=fbm(map,p*35+float2(hit*2,in.extra.w));
        light=in.color.rgb*(ring*.4*(.3+turbulence)+core*(.9+turbulence));
    }
    return half4(half3(light),1);
}

vertex Raster particleVertex(uint vid [[vertex_id]],uint instance [[instance_id]],
                             const device Particle *particles [[buffer(0)]],constant Frame &f [[buffer(1)]]) {
    Particle p=particles[instance]; Raster out;
    float a=p.life.y/max(.001,p.life.z);
    bool alive=p.life.z>0 && a<1;
    bool hot=p.color.w==1 || p.color.w==3;
    float size=p.life.x*(hot?1:(1+a*2.1))*(1+p.owner.z*.12)*(p.color.w==3?1.35:1);
    float2 uv=corners[vid];
    float angle=hot?atan2(p.position.w,p.position.z):p.life.w+a*.25;
    float2 shape=uv;
    if(p.color.w==3) { shape.x=uv.x*1.9-.45; }
    if(p.color.w==1) { shape.x*=1+min(4.0,length(p.position.zw)*7); }
    if(p.color.w==2)shape*=float2(1.15,.88);
    float2 rotated=float2(shape.x*cos(angle)-shape.y*sin(angle),shape.x*sin(angle)+shape.y*cos(angle));
    out.position=alive?clip(p.position.xy+rotated*size,f):float4(3,3,0,1);
    out.uv=p.color.w==3?shape:uv;
    out.color=p.color;out.data=float4(a,p.life.w,p.life.y,p.life.z);
    out.extra=float4(f.viewport.w,length(p.position.zw),p.owner.z,size);
    return out;
}

fragment half4 particleFragment(Raster in [[stage_in]],texture2d<float> map [[texture(4)]]) {
    float2 p=in.uv;
    float d=length(p);
    float a=in.data.x, seed=in.data.y;
    float3 c=in.color.rgb;
    float3 hot=mix(c,float3(1,.72,.34),.36);
    if(in.color.w==3) {
        // Angular molten chunks have a short evaporating flame, distinct from the fine spark field.
        float2 q=(p-float2(.3,0))*float2(1.15,1.4);
        float angle=atan2(q.y,q.x)+seed+in.data.z*1.2;
        float boundary=.72+.12*sin(angle*3)+.08*cos(angle*5);
        float rock=1-smoothstep(boundary-.04,boundary+.04,length(q));
        float cracks=pow(1-abs(sin(fbm(map,q*4+seed)*23)),4.0);
        float trailWidth=max(.08,.43+(p.x*.13));
        float flame=exp(-abs(p.y)/trailWidth)*saturate((.4-p.x)*.9)*saturate((p.x+2.4)*1.4);
        float tongues=fbm(map,float2(p.x*3-in.data.z*7,p.y*5+seed));
        flame*=smoothstep(.3,.72,tongues)*exp(-a*4);
        float cooling=pow(1-a,1.5);
        float3 light=(c*.12+hot*(cracks*2.2+.6))*rock*cooling+hot*flame*2;
        return half4(half3(light),half(saturate(rock*.82*cooling+flame*.3)));
    }
    if(d>1)discard_fragment();
    if(in.color.w==1) {
        float light=exp(-d*d*12)*pow(1-a,1.5);
        return half4(half3((c*1.9+hot*.8)*light),half(light*.25));
    }
    float z=sqrt(max(0.0,1-d*d));
    float2 uv=p*3+seed;
    float drift=in.data.z*.30;
    float front=fbm(map,uv+float2(drift,-drift*.6)+z*1.4);
    float middle=fbm(map,uv*1.19+float2(-drift*.6,drift)+z*.4+11);
    float rear=fbm(map,uv*.83+float2(drift*.4,drift*.5)-z*.9-17);
    float billow=front*.46+middle*.34+rear*.20;
    float erosion=.24+pow(a,1.05)*.53;
    float density=smoothstep(erosion,erosion+.18,billow)*pow(max(0.0,1-d*d),1.25);
    float heat=exp(-a*(in.color.w==2?8:14));
    float formation=smoothstep(0.0,.025,in.data.z);
    float shade=.34+.66*saturate(z*.65-p.x*.28+p.y*.36+(front-rear)*1.8+in.extra.z*.12);
    float rim=pow(1-z,2.0)*density;
    float alpha=density*formation*(in.color.w==2?.36:.12)*(1-a);
    float3 gas=c*(.38+shade*.85)+hot*heat*(in.color.w==2?2.4:3.0);
    gas+=c*rim*.6;
    float dust=0;
    if(in.color.w==2) dust=exp(-d*d*1600)*smoothstep(.35,.7,a)*(1-a)*2;
    return half4(half3(gas*alpha+hot*dust),half(saturate(alpha+dust*.15)));
}

vertex Raster screenVertex(uint id [[vertex_id]]) {
    Raster out;out.uv=corners[id]*.5+.5;out.position=float4(corners[id],0,1);return out;
}

fragment half4 compositeFragment(Raster in [[stage_in]],constant Frame &f [[buffer(0)]],
                                 texture2d<float> scene [[texture(0)]],texture2d<float> material [[texture(1)]]) {
    // Texture origin is top-left, while the fullscreen quad uses bottom-left UVs.
    float2 uv=float2(in.uv.x,1-in.uv.y);
    float3 light=scene.sample(linearClamp,uv).rgb;
    float2 pixel=1.0/float2(material.get_width(),material.get_height());
    float3 gas=material.sample(linearClamp,uv).rgb;
    float3 bloom=0;
    for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++)
        bloom+=material.sample(linearClamp,uv+float2(x,y)*pixel*5).rgb;
    light+=gas+bloom*.09;
    light*=f.controls.y*f.options.x;
    // Exponential tone mapping retains saturated colors while preserving bright hot cores.
    float3 mapped=1-exp(-light*1.15);
    if(f.options.y<.5) {
        float target=21.0/9.0;
        if(f.viewport.z>target && abs(in.uv.x-.5)>.5*target/f.viewport.z)mapped=0;
        if(f.viewport.z<target && abs(in.uv.y-.5)>.5*f.viewport.z/target)mapped=0;
    }
    return half4(half3(mapped),1);
}
