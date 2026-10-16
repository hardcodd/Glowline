#include "ambience.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

/* Repeated horizontal patterns give each depth sample the same color mix. */
static void pattern(uint8_t *pixels,size_t stride,const GlowlineRGB *colors){
 for(size_t y=0;y<20;y++)for(size_t x=0;x<24;x++){
  GlowlineRGB c=colors[x%8];
  _Float16 rgba[4]={c.r/255.f,c.g/255.f,c.b/255.f,1};
  memcpy(pixels+y*stride+x*8,rgba,sizeof(rgba));
 }
}
int main(void){
 enum {stride=24*8+16};uint8_t pixels[20*stride];
 GlowlineRGB mean[9],detail[9],off[9],colors[8];
 for(int r=0;r<=255;r+=51)for(int g=0;g<=255;g+=51)for(int b=0;b<=255;b+=51){
  for(int i=0;i<8;i++)colors[i]=(GlowlineRGB){r,g,b};
  pattern(pixels,stride,colors);
  sample_edge_grid(pixels,24,20,stride,3,3,mean,9,.2);
  sample_edge_grid_mode(pixels,24,20,stride,3,3,off,9,.2,0);
  sample_edge_grid_mode(pixels,24,20,stride,3,3,detail,9,.2,1);
  assert(memcmp(mean,off,sizeof(mean))==0);
  assert(memcmp(mean,detail,sizeof(mean))==0);
 }
 for(int i=0;i<8;i++)colors[i]=i<5?(GlowlineRGB){255,0,0}:i<7?(GlowlineRGB){0,255,0}:(GlowlineRGB){0,0,255};
 pattern(pixels,stride,colors);
 sample_edge_grid(pixels,24,20,stride,3,3,mean,9,.2);
 assert(mean[1].r==207 && mean[1].g==137 && mean[1].b==99);
 sample_edge_grid_mode(pixels,24,20,stride,3,3,detail,9,.2,1);
 assert(detail[1].r==mean[1].r && detail[1].g<mean[1].g/2 && detail[1].b<mean[1].b/2);
 printf("mixed zone mean=%u/%u/%u detail=%u/%u/%u\n",mean[1].r,mean[1].g,mean[1].b,detail[1].r,detail[1].g,detail[1].b);
 // Balanced competing hues must not arbitrarily pick a winner.
 for(int i=0;i<8;i++)colors[i]=i<4?(GlowlineRGB){255,0,0}:(GlowlineRGB){0,255,0};
 pattern(pixels,stride,colors);
 sample_edge_grid(pixels,24,20,stride,3,3,mean,9,.2);
 sample_edge_grid_mode(pixels,24,20,stride,3,3,detail,9,.2,1);
 assert(memcmp(&mean[1],&detail[1],sizeof(mean[1]))==0);
 assert(memcmp(&mean[7],&detail[7],sizeof(mean[7]))==0);
 // A tiny colored accent must not recolor a mostly white zone.
 for(int i=0;i<8;i++)colors[i]=i==0?(GlowlineRGB){255,0,0}:(GlowlineRGB){255,255,255};
 pattern(pixels,stride,colors);
 sample_edge_grid(pixels,24,20,stride,3,3,mean,9,.2);
 sample_edge_grid_mode(pixels,24,20,stride,3,3,detail,9,.2,1);
 assert(abs((int)detail[1].g-mean[1].g)<16 && abs((int)detail[1].b-mean[1].b)<16);
 // Hue groups must join across red's circular boundary.
 for(int i=0;i<8;i++)colors[i]=i<3?(GlowlineRGB){255,8,0}:i<6?(GlowlineRGB){255,0,8}:(GlowlineRGB){0,255,0};
 pattern(pixels,stride,colors);
 sample_edge_grid_mode(pixels,24,20,stride,3,3,detail,9,.2,1);
 assert(detail[1].r>detail[1].g*3 && detail[1].r>detail[1].b*3);
 // Changing hue selection must retain the original peak brightness.
 srand(71);
 for(int test=0;test<100;test++){
  for(int i=0;i<8;i++)colors[i]=(GlowlineRGB){rand()%256,rand()%256,rand()%256};
  pattern(pixels,stride,colors);
  sample_edge_grid(pixels,24,20,stride,3,3,mean,9,.2);
  sample_edge_grid_mode(pixels,24,20,stride,3,3,detail,9,.2,1);
  for(int i=0;i<9;i++)assert(fmax(mean[i].r,fmax(mean[i].g,mean[i].b))==fmax(detail[i].r,fmax(detail[i].g,detail[i].b)));
 }
 // Zero depth remains the legacy center-point sampler, including detail mode.
 sample_edge_grid(pixels,24,20,stride,3,3,mean,9,0);
 sample_edge_grid_mode(pixels,24,20,stride,3,3,detail,9,0,1);
 assert(memcmp(mean,detail,sizeof(mean))==0);
 sample_edge_grid_mode(NULL,24,20,stride,3,3,detail,9,.2,1);
 for(int i=0;i<9;i++)assert(detail[i].r==0&&detail[i].g==0&&detail[i].b==0);
 sample_edge_grid_mode(pixels,24,20,1,3,3,detail,9,.2,1);
 for(int i=0;i<9;i++)assert(detail[i].r==0&&detail[i].g==0&&detail[i].b==0);
 for(int y=0;y<20;y++)for(int x=0;x<24;x++){
  _Float16 rgba[4]={NAN,INFINITY,-1,1};memcpy(pixels+y*stride+x*8,rgba,sizeof(rgba));
 }
 sample_edge_grid_mode(pixels,24,20,stride,3,3,detail,9,.2,1);
 for(int i=0;i<9;i++)assert(detail[i].r==0&&detail[i].g==0&&detail[i].b==0);
 // A localized source cannot light unrelated cells along the edge.
 size_t w=344,h=144;uint8_t *large=calloc(w*h,8);assert(large);
 for(size_t y=0;y<8;y++)for(size_t x=163;x<167;x++){
  _Float16 rgba[4]={0,0,1,1};memcpy(large+(y*w+x)*8,rgba,sizeof(rgba));
 }
 GlowlineRGB grid[731];sample_edge_grid_mode(large,w,h,w*8,43,17,grid,731,.12,1);
 int lit=0;for(int x=0;x<43;x++)if(grid[x].r||grid[x].g||grid[x].b)lit++;
 assert(lit==1);free(large);
 puts("detail sampling contracts passed");return 0;
}
