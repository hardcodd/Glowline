#pragma once
#include "rgb.h"
#include <math.h>

/* Callers supply blend and level in [0,1], keeping all channels in byte range. */
static GlowlineRGB effect_mix(GlowlineRGB a,GlowlineRGB b,double blend,double level){
 return (GlowlineRGB){
  lround((a.r+(b.r-a.r)*blend)*level),
  lround((a.g+(b.g-a.g)*blend)*level),
  lround((a.b+(b.b-a.b)*blend)*level)
 };
}
static double effect_hash(double x,double y){
 double n=sin(x*127.1+y*311.7)*43758.5453;
 return n-floor(n);
}
/* Smooth deterministic value noise: no mutable simulation or frame-rate dependence. */
static double effect_noise(double x,double y){
 double ix=floor(x),iy=floor(y);
 double fx=x-ix,fy=y-iy;
 fx=fx*fx*(3-2*fx);
 fy=fy*fy*(3-2*fy);
 double a=effect_hash(ix,iy),b=effect_hash(ix+1,iy);
 double c=effect_hash(ix,iy+1),d=effect_hash(ix+1,iy+1);
 return (a+(b-a)*fx)*(1-fy)+(c+(d-c)*fx)*fy;
}
/* Coordinates follow the physical monitor: y=0 at the top, y=1 at the embers.
 * Upward-advecting turbulence breaks a hot base into separate cooling tongues. */
static GlowlineRGB fire_color(double x,double y,double phase,double flameHeight){
 double height=(1-y)/flameHeight;
 double broad=effect_noise(x*5, height*2-phase*.8);
 double detail=effect_noise(x*11+3, height*4-phase*1.7);
 double heat=fmin(1,fmax(0,.42+.90*broad+.25*detail-height*.85));
 const GlowlineRGB coal={32,1,0},red={180,12,0};
 const GlowlineRGB orange={255,100,2},yellow={255,220,75};
 if(heat<.35)return effect_mix(coal,red,heat/.35,1);
 if(heat<.7)return effect_mix(red,orange,(heat-.35)/.35,1);
 return effect_mix(orange,yellow,(heat-.7)/.3,1);
}
/* A circular tail follows travel direction; the soft leading edge avoids stepping
 * between LEDs. Position is i/112 rather than i/111 to avoid a duplicate seam. */
static GlowlineRGB comet_color(double position,double phase,int reverse,GlowlineRGB a,GlowlineRGB b,double tailLength){
 double distance=(phase*.12-position)*(reverse?-1:1);
 distance-=floor(distance);
 double circular=fmin(distance,1-distance);
 double leading=(1-distance)/.018,core=circular/.018;
 double tail=fmax(exp(-distance*6/tailLength),exp(-leading*leading));
 double head=exp(-core*core);
 double colorBlend=fmax(exp(-distance*5/tailLength),exp(-leading*leading));
 GlowlineRGB trail=effect_mix(b,a,colorBlend,tail);
 return effect_mix(trail,(GlowlineRGB){255,245,225},head*.65,1);
}
/* A dedicated emerald-to-pink spectrum and two drifting curtains preserve visible
 * hue separation instead of mixing complementary user colors through gray. */
static GlowlineRGB aurora_color(double position,double phase,double pinkAmount){
 GlowlineRGB palette[]={{20,255,90},{15,245,225},{55,100,255},{170,50,255},{255,65,195},{110,245,225}};
 // 0 replaces pink with teal, 1 preserves the accepted palette, 2 extends pink into violet.
 palette[4]=effect_mix((GlowlineRGB){15,245,225},palette[4],fmin(1,pinkAmount),1);
 palette[3]=effect_mix(palette[3],palette[4],fmax(0,pinkAmount-1),1);
 double angle=position*2*M_PI;
 double ribbon=.5+.5*sin(angle*2-phase*.45+.8*sin(angle+phase*.21));
 double veil=.5+.5*sin(angle*3+phase*.27);
 double hue=position+phase*.025+.10*sin(angle-phase*.12);
 hue-=floor(hue);
 double stop=hue*6;
 int first=(int)floor(stop);
 double blend=stop-first;
 blend=blend*blend*(3-2*blend);
 return effect_mix(palette[first],palette[(first+1)%6],blend,.42+.40*ribbon+.18*veil);
}
