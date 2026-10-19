#include "controls.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
static int color_distance(GlowlineRGB a,GlowlineRGB b){return abs((int)a.r-b.r)+abs((int)a.g-b.g)+abs((int)a.b-b.b);}
/* Exercise observable animation contracts rather than exact noise samples. */
static void test_new_effects(void){
 EngineControls c=default_controls();c.primary=(GlowlineRGB){255,120,20};c.secondary=(GlowlineRGB){20,80,255};
 for(int mode=6;mode<=8;mode++){
  c.mode=mode;int spatial=0,temporal=0;
  for(int frame=0;frame<300;frame++)for(size_t i=0;i<112;i++){
   double t=frame/30.;GlowlineRGB a=mode_color(i,t,&c);
   spatial+=color_distance(a,mode_color((i+1)%112,t,&c));
   temporal+=color_distance(a,mode_color(i,t+1./30,&c));
   c.speed=2;GlowlineRGB fast=mode_color(i,t/2,&c);assert(color_distance(a,fast)==0);c.speed=1;
   c.reverse=1;GlowlineRGB backwards=mode_color(mode==7?(112-i)%112:i,mode==7?t:-t,&c);assert(color_distance(a,backwards)==0);c.reverse=0;
   c.enabled=0;GlowlineRGB off=adjust_color(a,&c);assert(off.r==0&&off.g==0&&off.b==0);c.enabled=1;
  }
  assert(spatial>10000&&temporal>10000);
 }
 c.mode=6;double top=0,bottom=0;
 for(int frame=0;frame<300;frame++)for(size_t i=0;i<112;i++){
  GlowlineRGB a=mode_color(i,frame/30.,&c);assert(a.r>=a.g&&a.g>=a.b);
  if(i>=15&&i<56)top+=a.r+a.g+a.b;
  if(i>=71)bottom+=a.r+a.g+a.b;
 }
 // The owner requested a vertical flip for the mounted strip; screen mapping stays unchanged.
 assert(top>bottom*1.5);
 c.mode=7;double quarter=1./(.12*4);
 GlowlineRGB head=mode_color(28,quarter,&c),trail=mode_color(24,quarter,&c),ahead=mode_color(32,quarter,&c);
 assert(head.r>trail.r&&trail.r+trail.g+trail.b>ahead.r+ahead.g+ahead.b+100);
 // The tail crosses LED 111 -> 0 without a dark seam.
 GlowlineRGB wrapped=mode_color(111,0,&c);assert(wrapped.r>100);
 assert(color_distance(mode_color(0,.000001,&c),mode_color(0,-.000001,&c))<3);
 GlowlineRGB longTail=mode_color(6,quarter,&c);
 assert(longTail.r+longTail.g+longTail.b>70);
 c.reverse=1;assert(color_distance(head,mode_color(84,quarter,&c))==0);c.reverse=0;
 // Both palette slots affect the comet.
 for(int slot=0;slot<2;slot++){
  c.mode=7;EngineControls changed=c;if(slot==0)changed.primary=(GlowlineRGB){0,0,0};else changed.secondary=(GlowlineRGB){0,0,0};
  int difference=0;for(size_t i=0;i<112;i++)difference+=color_distance(mode_color(i,1,&c),mode_color(i,1,&changed));assert(difference>100);
 }
 // Aurora retains green, cyan and pink through the owner's warm, reduced-saturation settings.
 c=default_controls();c.mode=8;c.warmth=.7;c.saturation=.5;c.gamma=1.6;
 int green=0,cyan=0,pink=0;
 for(int frame=0;frame<600;frame++)for(size_t i=0;i<112;i++){
  GlowlineRGB color=adjust_color(mode_color(i,frame/20.,&c),&c);
  green+=color.g>color.r*1.3&&color.g>color.b*1.2&&color.g>50;
  cyan+=color.g>color.r*1.2&&color.b>color.r*1.2&&color.g>40&&color.b>40;
  pink+=color.r>color.g*1.3&&color.b>color.g*1.3&&color.r>60&&color.b>40;
 }
 assert(green>100&&cyan>100&&pink>100);
}
int main(void){
 // Characteristic controls change the intended shape without changing other modes.
 EngineControls base=default_controls(),tuned=base;
 base.mode=tuned.mode=2;tuned.gradientBalance=.8;
 assert(color_distance(mode_color(50,0,&base),mode_color(50,0,&tuned))>30);
 assert(color_distance(mode_color(0,0,&base),mode_color(0,0,&tuned))==0);
 base.mode=tuned.mode=3;tuned.breathingFloor=.7;
 assert(mode_color(0,0,&tuned).r>mode_color(0,0,&base).r+100);
 base=default_controls();base.mode=4;tuned=base;tuned.rainbowCycles=2;
 assert(color_distance(mode_color(28,0,&base),mode_color(28,0,&tuned))>100);
 base.mode=5;tuned=base;tuned.candleFlicker=0;
 assert(color_distance(mode_color(0,0,&tuned),mode_color(50,2,&tuned))==0);
 assert(color_distance(mode_color(0,0,&base),mode_color(50,2,&base))>5);
 base.mode=6;tuned=base;tuned.flameHeight=.4;
 int flameDifference=0;for(size_t i=0;i<112;i++)flameDifference+=color_distance(mode_color(i,1,&base),mode_color(i,1,&tuned));assert(flameDifference>1000);
 base.mode=7;tuned=base;tuned.cometTail=2;
 GlowlineRGB shortTail=mode_color(80,0,&base),longerTail=mode_color(80,0,&tuned);
 assert(longerTail.r+longerTail.g+longerTail.b>shortTail.r+shortTail.g+shortTail.b+50);
 base.mode=8;tuned=base;tuned.auroraPink=0;
 int pinkDifference=0;for(size_t i=0;i<112;i++)pinkDifference+=color_distance(mode_color(i,1,&base),mode_color(i,1,&tuned));assert(pinkDifference>1000);
 test_new_effects();
 EngineControls c=default_controls();assert(c.brightness==1&&c.warmth==.5&&c.mirrored&&c.mode==0);
 GlowlineRGB w=adjust_color((GlowlineRGB){255,255,255},&c);assert(w.r==255&&w.g==210&&w.b==128);
 c.warmth=.9;w=adjust_color((GlowlineRGB){255,255,255},&c);assert(w.r==255&&w.b==26&&w.g==175);
 c=default_controls();GlowlineRGB blue=adjust_color((GlowlineRGB){0,0,255},&c);assert(blue.r==0&&blue.g==0&&blue.b==255);
 c.brightness=.5;GlowlineRGB red=adjust_color((GlowlineRGB){255,0,0},&c);assert(red.r==128);c.enabled=0;assert(adjust_color(red,&c).r==0);
 c=default_controls();assert(mapped_grid_index(7,&c)==grid_indices[7]);c.mirrored=0;assert(mapped_grid_index(7,&c)==(grid_indices[7]/43)*43+42-grid_indices[7]%43);
 c=default_controls();c.offset=-1;assert(mapped_grid_index(0,&c)==grid_indices[111]);c.offset=0;c.sideEnabled[0]=0;assert(!led_enabled(7,&c)&&led_enabled(35,&c));
 c=default_controls();c.mode=1;c.primary=(GlowlineRGB){12,34,56};GlowlineRGB s=mode_color(7,0,&c);assert(s.r==12&&s.g==34&&s.b==56);
 c.mode=2;c.primary=(GlowlineRGB){255,0,0};c.secondary=(GlowlineRGB){0,0,255};s=mode_color(0,0,&c);assert(s.r==255&&s.b==0);s=mode_color(111,0,&c);assert(s.r==0&&s.b==255);
 for(int mode=1;mode<=5;mode++){c.mode=mode;for(int i=0;i<112;i++)mode_color(i,1.5,&c);}

 c=default_controls();for(int r=0;r<256;r+=7)for(int g=0;g<256;g+=7)for(int b=0;b<256;b+=7){GlowlineRGB input={r,g,b},expected=warm_rgb(input,.5),actual=adjust_color(input,&c);assert(actual.r==expected.r&&actual.g==expected.g&&actual.b==expected.b);}
 puts("control contracts passed");return 0;}
