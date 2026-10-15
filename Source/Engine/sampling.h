#pragma once
#include "rgb.h"
/* Sample cell centers without blending or channel transforms; Core applies the physical layout. */
static void sample_grid(const uint8_t *pixels, size_t fw, size_t fh, size_t stride,
                        size_t width, size_t height, GlowlineRGB *out, size_t count) {
 for (size_t i=0;i<count;i++) {
  if (!pixels || !fw || !fh || !width || !height || i>=width*height) {out[i]=(GlowlineRGB){0,0,0};continue;}
  size_t x=((2*(i%width)+1)*fw)/(2*width);
  size_t y=((2*(i/width)+1)*fh)/(2*height);
  if(x>=fw)x=fw-1; if(y>=fh)y=fh-1;
  const uint8_t *p=pixels+y*stride+x*4;
  out[i]=(GlowlineRGB){p[2],p[1],p[0]};
 }
}
