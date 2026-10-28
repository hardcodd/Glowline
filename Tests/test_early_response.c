#include "early_response.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

enum { W=344, H=144, STRIDE=W*8+16, COUNT=43*17 };
static uint8_t pixels[H*STRIDE];

static void rectangle(int x0,int y0,int width,int height,float r,float g,float b) {
    for(int y=y0;y<y0+height;y++)for(int x=x0;x<x0+width;x++) {
        _Float16 rgba[4]={r,g,b,1};
        memcpy(pixels+y*STRIDE+x*8,rgba,sizeof(rgba));
    }
}

int main(void) {
    GlowlineRGB old[COUNT],off[COUNT],early[COUNT];
    for(int detail=0;detail<2;detail++) {
        memset(pixels,0,sizeof(pixels));
        rectangle(160,40,8,8,0,0,1);
        sample_edge_grid_mode(pixels,W,H,STRIDE,43,17,old,COUNT,.15,detail);
        sample_reactive_edge_grid(pixels,W,H,STRIDE,43,17,off,COUNT,.15,detail,0);
        assert(memcmp(old,off,sizeof(old))==0);
        sample_reactive_edge_grid(pixels,W,H,STRIDE,43,17,early,COUNT,.15,detail,1);
        assert(old[20].b==0 && early[20].b>0 && early[20].r==0 && early[20].g==0);
        for(int x=0;x<43;x++)if(x!=20)assert(early[x].r==0 && early[x].g==0 && early[x].b==0);
        assert(early[16*43+20].b==0);
        int far=early[20].b;
        memset(pixels,0,sizeof(pixels));rectangle(160,25,8,8,0,0,1);
        sample_reactive_edge_grid(pixels,W,H,STRIDE,43,17,early,COUNT,.15,detail,1);
        assert(early[20].b>far);

        // Different columns retain their own hues rather than a global accent.
        rectangle(240,25,8,8,1,0,0);
        sample_reactive_edge_grid(pixels,W,H,STRIDE,43,17,early,COUNT,.15,detail,1);
        assert(early[20].r==0 && early[30].b==0 && early[30].r>0);

        // Rotate the same contract through all four physical edges.
        memset(pixels,0,sizeof(pixels));rectangle(240,105,8,8,1,0,0);
        sample_reactive_edge_grid(pixels,W,H,STRIDE,43,17,early,COUNT,.15,detail,1);
        assert(early[16*43+30].r>0 && early[30].r==0);
        memset(pixels,0,sizeof(pixels));rectangle(100,56,8,3,0,1,0);
        sample_reactive_edge_grid(pixels,W,H,STRIDE,43,17,early,COUNT,.15,detail,1);
        assert(early[6*43].g>0 && early[6*43+42].g==0);
        memset(pixels,0,sizeof(pixels));rectangle(236,56,8,3,0,1,0);
        sample_reactive_edge_grid(pixels,W,H,STRIDE,43,17,early,COUNT,.15,detail,1);
        assert(early[6*43+42].g>0 && early[6*43].g==0);

        for(int level=0;level<=4;level++) {
            rectangle(0,0,W,H,level*.25,level*.125,0);
            sample_edge_grid_mode(pixels,W,H,STRIDE,43,17,old,COUNT,.15,detail);
            sample_reactive_edge_grid(pixels,W,H,STRIDE,43,17,early,COUNT,.15,detail,1);
            assert(memcmp(old,early,sizeof(old))==0);
        }
        sample_edge_grid_mode(pixels,W,H,STRIDE,43,17,old,COUNT,0,detail);
        sample_reactive_edge_grid(pixels,W,H,STRIDE,43,17,early,COUNT,0,detail,1);
        assert(memcmp(old,early,sizeof(old))==0);
    }
    sample_reactive_edge_grid(NULL,W,H,STRIDE,43,17,early,COUNT,.15,1,1);
    for(int i=0;i<COUNT;i++)assert(early[i].r==0 && early[i].g==0 && early[i].b==0);
    rectangle(0,0,W,H,NAN,INFINITY,-1);
    sample_reactive_edge_grid(pixels,W,H,STRIDE,43,17,early,COUNT,.15,1,1);
    for(int i=0;i<COUNT;i++)assert(early[i].r==0 && early[i].g==0 && early[i].b==0);

    rectangle(0,0,W,H,.3,.1,.5);
    clock_t begin=clock();
    for(int i=0;i<300;i++)sample_reactive_edge_grid(pixels,W,H,STRIDE,43,17,early,COUNT,.15,1,1);
    printf("Early-response contracts passed; CPU %.3f ms/frame, checksum %u\n",
           1000.0*(clock()-begin)/CLOCKS_PER_SEC/300,early[20].b);
    return 0;
}
