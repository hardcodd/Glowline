#pragma once
#include "ambience.h"

/* Optional highlight floor, independent of edge depth and temporal smoothing.
 * Each edge cell sees only its own column/row, up to half the image. RMS peak
 * energy retains small highlights on black; squared distance falloff and a
 * 0.35 linear-light ceiling keep distant objects subordinate to edge content.
 * HDR highlights are bounded to SDR here, preventing a tiny HDR pixel from
 * flooding a zone. Disabled/zero-depth paths remain byte-identical to legacy.
 */
static void sample_reactive_edge_grid(const uint8_t *pixels,size_t fw,size_t fh,size_t stride,
    size_t width,size_t height,GlowlineRGB *out,size_t count,double depth,int detail,int early) {
    sample_edge_grid_mode(pixels,fw,fh,stride,width,height,out,count,depth,detail);
    if(!early || !isfinite(depth) || depth<=0 || !pixels || !fw || !fh ||
       width<2 || height<2 || stride<fw*8)return;

    for(size_t i=0;i<count && i<width*height;i++) {
        size_t col=i%width,row=i/width;
        if(col && col!=width-1 && row && row!=height-1)continue;
        int horizontal=row==0 || row==height-1;
        size_t extent=horizontal?fh:fw,along=horizontal?fw:fh;
        size_t cells=horizontal?width:height,cell=horizontal?col:row;
        size_t steps=(extent+1)/2;
        size_t first=cell*along/cells,last=(cell+1)*along/cells;
        if(last<=first)last=first+1;
        if(last>along)last=along;
        if(last<=first)continue;

        double energy[3]={0},peakEnergy=0;
        HueBucket buckets[12]={0};
        for(size_t d=0;d<steps;d++) {
            double falloff=fmax(0,1-2*((double)d+.5)/extent);
            double weight=falloff*falloff;
            for(size_t a=first;a<last;a++) {
                size_t x=horizontal?a:(col==0?d:fw-1-d);
                size_t y=horizontal?(row==0?d:fh-1-d):a;
                const uint8_t *rgba=pixels+y*stride+x*8;
                double rgb[3]={0};
                for(int c=0;c<3;c++) {
                    float value=glowline_half_to_float(rgba+c*2);
                    if(isfinite(value) && value>0)rgb[c]=fmin(1,value);
                }
                double peak=fmax(rgb[0],fmax(rgb[1],rgb[2]));
                for(int c=0;c<3;c++)energy[c]+=rgb[c]*peak*weight;
                peakEnergy+=peak*peak*weight;
                if(detail)detail_vote(buckets,rgb,peak*weight);
            }
        }
        if(peakEnergy<=0)continue;
        if(detail)detail_color(energy,buckets,peakEnergy);
        double huePeak=fmax(energy[0],fmax(energy[1],energy[2]));
        double level=.35*sqrt(peakEnergy/((double)steps*(last-first)));
        uint8_t channels[3]={out[i].r,out[i].g,out[i].b};
        double base[3];
        for(int c=0;c<3;c++) {
            double encoded=channels[c]/255.0;
            base[c]=encoded<=.04045?encoded/12.92:pow((encoded+.055)/1.055,2.4);
        }
        double basePeak=fmax(base[0],fmax(base[1],base[2]));
        if(level<=basePeak || huePeak<=0)continue;

        // Add only the missing highlight level; existing edge light never dims.
        for(int c=0;c<3;c++)channels[c]=linear_to_srgb8(base[c]+(level-basePeak)*energy[c]/huePeak);
        out[i]=(GlowlineRGB){channels[0],channels[1],channels[2]};
    }
}
