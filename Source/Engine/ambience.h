#pragma once
#include "linear_sampling.h"
typedef struct {double score,rgb[3];} HueBucket;
/* Soft votes across a circular hue boundary avoid splitting a single hue.
 * Neutral pixels still contribute to the mean, but never choose a hue winner. */
static void detail_vote(HueBucket buckets[12],const double rgb[3],double weight){
 double hi=fmax(rgb[0],fmax(rgb[1],rgb[2])),lo=fmin(rgb[0],fmin(rgb[1],rgb[2])),chroma=hi-lo;
 if(hi<=0||chroma<=hi*.05)return;
 double hue=hi==rgb[0]?(rgb[1]-rgb[2])/chroma:hi==rgb[1]?2+(rgb[2]-rgb[0])/chroma:4+(rgb[0]-rgb[1])/chroma;
 if(hue<0)hue+=6;
 double position=hue*2;int first=(int)floor(position);double fraction=position-first;
 for(int j=0;j<2;j++){
  HueBucket *b=&buckets[(first+j)%12];double w=weight*(j?fraction:1-fraction);
  b->score+=chroma*w;
  for(int c=0;c<3;c++)b->rgb[c]+=rgb[c]*w;
 }
}
/* Keep the mean peak level. Weak chromatic support and competing equal hues
 * fade back to the mean instead of amplifying a tiny accent or choosing ties. */
static void detail_color(double mean[3],const HueBucket buckets[12],double peakSum){
 double scores[12]={0};int winner=0;
 for(int i=0;i<12;i++){
  for(int j=-1;j<=1;j++)scores[i]+=buckets[(i+j+12)%12].score;
  if(scores[i]>scores[winner])winner=i;
 }
 double top=scores[winner],runner=0,chromaSum=0;
 for(int i=0;i<12;i++){
  chromaSum+=buckets[i].score;int distance=i>winner?i-winner:winner-i;if(distance>6)distance=12-distance;
  if(distance>2)runner=fmax(runner,scores[i]);
 }
 if(top<=0||peakSum<=0)return;
 double confidence=fmin(1,fmax(0,(top-runner)/(top*.25)));
 double support=fmin(1,fmax(0,(chromaSum/peakSum-.15)/.35));
 double blend=.9*confidence*support;if(blend<=0)return;
 double selected[3]={0};
 for(int j=-1;j<=1;j++)for(int c=0;c<3;c++)selected[c]+=buckets[(winner+j+12)%12].rgb[c];
 double peak=fmax(mean[0],fmax(mean[1],mean[2])),selectedPeak=fmax(selected[0],fmax(selected[1],selected[2]));
 if(selectedPeak<=0)return;
 for(int c=0;c<3;c++)mean[c]=mean[c]*(1-blend)+selected[c]/selectedPeak*peak*blend;
 double mixedPeak=fmax(mean[0],fmax(mean[1],mean[2]));
 if(mixedPeak>0)for(int c=0;c<3;c++)mean[c]*=peak/mixedPeak;
}
/* Linear-light depth integration keeps edge influence continuous as windows move.
 * The original cell centers remain available with depth=0. Interior cells are unused. */
static void sample_edge_grid_mode(const uint8_t *pixels,size_t fw,size_t fh,size_t stride,
 size_t width,size_t height,GlowlineRGB *out,size_t count,double depth,int detail){
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
  double sums[3]={0},weightSum=0,peakSum=0;HueBucket buckets[12]={0};
  for(size_t d=0;d<steps;d++){
   double weight=fmax(0,1-((double)d+.5)/(extent*depth));if(weight<=0)continue;
   for(size_t a=first;a<last;a++){
    size_t x=horizontal?a:(col==0?d:fw-1-d),y=horizontal?(row==0?d:fh-1-d):a;
    _Float16 rgba[4];memcpy(rgba,pixels+y*stride+x*8,sizeof(rgba));
    double rgb[3]={0};
    for(int c=0;c<3;c++){float v=rgba[c];if(isfinite(v)&&v>0){sums[c]+=v*weight;rgb[c]=v;}}
    if(detail){detail_vote(buckets,rgb,weight);peakSum+=fmax(rgb[0],fmax(rgb[1],rgb[2]))*weight;}
    weightSum+=weight;
   }
  }
  if(weightSum>0){
   double mean[3]={sums[0]/weightSum,sums[1]/weightSum,sums[2]/weightSum};
   if(detail)detail_color(mean,buckets,peakSum);
   out[i]=(GlowlineRGB){linear_to_srgb8(mean[0]),linear_to_srgb8(mean[1]),linear_to_srgb8(mean[2])};
  }
 }
}
static void sample_edge_grid(const uint8_t *pixels,size_t fw,size_t fh,size_t stride,
 size_t width,size_t height,GlowlineRGB *out,size_t count,double depth){
 sample_edge_grid_mode(pixels,fw,fh,stride,width,height,out,count,depth,0);
}
/* Warm only the shared neutral component, preserving saturated RGB primaries. */
static GlowlineRGB warm_rgb(GlowlineRGB c,double strength){
 if(!isfinite(strength))strength=0;strength=fmin(.9,fmax(0,strength));
 double neutral=fmin(c.r,fmin(c.g,c.b));
 return (GlowlineRGB){c.r,(uint8_t)lround(c.g-neutral*strength*.35),(uint8_t)lround(c.b-neutral*strength)};
}
typedef struct {double level,time;GlowlineRGB hue;int initialized;} ReleaseState;
/* Immediate attack and hue changes; only brightness falls with elapsed time.
 * A black target retains the last hue until the envelope reaches zero. */
static GlowlineRGB release_rgb(ReleaseState *s,GlowlineRGB target,double now,double seconds){
 double peak=fmax(target.r,fmax(target.g,target.b));
 double dt=s->initialized?fmax(0,now-s->time):0;
 double level=peak;
 if(s->initialized&&isfinite(seconds)&&seconds>0)level=fmax(peak,s->level*exp(-dt/seconds));
 if(level<.5)level=0;
 if(peak>0)s->hue=target;
 double huePeak=fmax(s->hue.r,fmax(s->hue.g,s->hue.b));
 s->level=level;s->time=now;s->initialized=1;
 double scale=huePeak>0?level/huePeak:0;
 return (GlowlineRGB){(uint8_t)lround(s->hue.r*scale),(uint8_t)lround(s->hue.g*scale),(uint8_t)lround(s->hue.b*scale)};
}
