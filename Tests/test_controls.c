#include "controls.h"
#include <assert.h>
#include <stdio.h>
int main(void){
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
