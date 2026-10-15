#pragma once
#include "rgb.h"
#include <math.h>
#include <string.h>

/* Encode linear-light sRGB once, at the final SDR LED boundary. Values outside
 * the LED gamut are clipped; this is deliberately not an HDR tone mapper. */
static uint8_t linear_to_srgb8(float value){
 if(isnan(value)||value<=0)return 0;
 if(value>=1)return 255;
 float encoded=value<=0.0031308f?12.92f*value:1.055f*powf(value,1.0f/2.4f)-0.055f;
 return (uint8_t)lroundf(encoded*255.0f);
}

/* ScreenCaptureKit RGhA contains native-endian RGBA half-floats in the explicitly
 * requested extended-linear-sRGB space. Preserve padded row strides and sample
 * the same cell centers as the original physical layout. */
static void sample_linear_grid(const uint8_t *pixels,size_t fw,size_t fh,size_t stride,
                               size_t width,size_t height,GlowlineRGB *out,size_t count){
 for(size_t i=0;i<count;i++){
  if(!pixels||!fw||!fh||!width||!height||stride<fw*8||i>=width*height){out[i]=(GlowlineRGB){0,0,0};continue;}
  size_t x=((2*(i%width)+1)*fw)/(2*width),y=((2*(i/width)+1)*fh)/(2*height);
  if(x>=fw)x=fw-1;if(y>=fh)y=fh-1;
  _Float16 rgba[4];memcpy(rgba,pixels+y*stride+x*8,sizeof(rgba));
  out[i]=(GlowlineRGB){linear_to_srgb8(rgba[0]),linear_to_srgb8(rgba[1]),linear_to_srgb8(rgba[2])};
 }
}
