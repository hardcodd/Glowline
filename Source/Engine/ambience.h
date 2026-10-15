#pragma once
#include "linear_sampling.h"
/* Linear-light depth integration keeps edge influence continuous as windows move.
 * The original cell centers remain available with depth=0. Interior cells are unused. */
static void sample_edge_grid(const uint8_t *pixels,size_t fw,size_t fh,size_t stride,
 size_t width,size_t height,SkydimoRgb *out,size_t count,double depth){
 if(!isfinite(depth)||depth<=0){sample_linear_grid(pixels,fw,fh,stride,width,height,out,count);return;}
 memset(out,0,count*sizeof(*out));
 if(!pixels||!fw||!fh||width<2||height<2||stride<fw*8)return;
 depth=fmin(.35,fmax(.01,depth));
 for(size_t i=0;i<count&&i<width*height;i++){
  size_t col=i%width,row=i/width;
  if(col&&col!=width-1&&row&&row!=height-1)continue;
  int horizontal=row==0||row==height-1;
  size_t extent=horizontal?fh:fw,along=horizontal?fw:fh,cells=horizontal?width:height,cell=horizontal?col:row;
  size_t steps=(size_t)ceil(extent*depth);if(steps>extent)steps=extent;
  size_t first=cell*along/cells,last=(cell+1)*along/cells;if(last<=first)last=first+1;if(last>along)last=along;
  double sums[3]={0},weightSum=0;
  for(size_t d=0;d<steps;d++){
   double weight=fmax(0,1-((double)d+.5)/(extent*depth));if(weight<=0)continue;
   for(size_t a=first;a<last;a++){
    size_t x=horizontal?a:(col==0?d:fw-1-d),y=horizontal?(row==0?d:fh-1-d):a;
    _Float16 rgba[4];memcpy(rgba,pixels+y*stride+x*8,sizeof(rgba));
    for(int c=0;c<3;c++){float v=rgba[c];if(isfinite(v)&&v>0)sums[c]+=v*weight;}
    weightSum+=weight;
   }
  }
  if(weightSum>0)out[i]=(SkydimoRgb){linear_to_srgb8(sums[0]/weightSum),linear_to_srgb8(sums[1]/weightSum),linear_to_srgb8(sums[2]/weightSum)};
 }
}
/* Warm only the shared neutral component, preserving saturated RGB primaries. */
static SkydimoRgb warm_rgb(SkydimoRgb c,double strength){
 if(!isfinite(strength))strength=0;strength=fmin(.9,fmax(0,strength));
 double neutral=fmin(c.r,fmin(c.g,c.b));
 return (SkydimoRgb){c.r,(uint8_t)lround(c.g-neutral*strength*.35),(uint8_t)lround(c.b-neutral*strength)};
}
typedef struct {double level,time;SkydimoRgb hue;int initialized;} ReleaseState;
/* Immediate attack and hue changes; only brightness falls with elapsed time.
 * A black target retains the last hue until the envelope reaches zero. */
static SkydimoRgb release_rgb(ReleaseState *s,SkydimoRgb target,double now,double seconds){
 double peak=fmax(target.r,fmax(target.g,target.b));
 double dt=s->initialized?fmax(0,now-s->time):0;
 double level=peak;
 if(s->initialized&&isfinite(seconds)&&seconds>0)level=fmax(peak,s->level*exp(-dt/seconds));
 if(level<.5)level=0;
 if(peak>0)s->hue=target;
 double huePeak=fmax(s->hue.r,fmax(s->hue.g,s->hue.b));
 s->level=level;s->time=now;s->initialized=1;
 double scale=huePeak>0?level/huePeak:0;
 return (SkydimoRgb){(uint8_t)lround(s->hue.r*scale),(uint8_t)lround(s->hue.g*scale),(uint8_t)lround(s->hue.b*scale)};
}
