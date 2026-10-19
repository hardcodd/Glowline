#pragma once
#include "ambience.h"
#include "layout.h"
#include "effects.h"
enum { GLOWLINE_MODE_COUNT=9 };
/* Stable engine settings: defaults match the accepted controller exactly. */
typedef struct {
 int enabled,mode,mirrored,offset,reverse,sideEnabled[4];
 double brightness,warmth,saturation,gamma,gain[3],sideGain[4],blackThreshold,speed;
 double gradientBalance,breathingFloor,rainbowCycles,candleFlicker,flameHeight,cometTail,auroraPink;
 GlowlineRGB primary,secondary;
} EngineControls;
static EngineControls default_controls(void){return (EngineControls){.enabled=1,.mirrored=1,.brightness=1,.warmth=.5,.saturation=1,.gamma=1,.gain={1,1,1},.sideGain={1,1,1,1},.sideEnabled={1,1,1,1},.speed=1,.gradientBalance=.5,.breathingFloor=.15,.rainbowCycles=1,.candleFlicker=1,.flameHeight=1,.cometTail=1,.auroraPink=1,.primary={255,160,64},.secondary={72,96,255}};}
static double bounded(double x,double low,double high,double fallback){return isfinite(x)?fmin(high,fmax(low,x)):fallback;}
static int led_side(size_t i){return i<15?0:i<56?1:i<71?2:3;}
static int led_enabled(size_t i,const EngineControls *c){return c->enabled&&c->sideEnabled[led_side(i)];}
static size_t mapped_grid_index(size_t i,const EngineControls *c){
 int index=((int)i+c->offset)%112;if(index<0)index+=112;size_t cell=grid_indices[index];
 return c->mirrored?cell:(cell/43)*43+42-cell%43;
}
static GlowlineRGB adjust_color(GlowlineRGB rgb,const EngineControls *c){
 if(!c->enabled)return (GlowlineRGB){0};
 double v[3]={rgb.r/255.,rgb.g/255.,rgb.b/255.};double peak=fmax(v[0],fmax(v[1],v[2]));
 if(peak<c->blackThreshold)return (GlowlineRGB){0};
 double gray=.2126*v[0]+.7152*v[1]+.0722*v[2];
 for(int i=0;i<3;i++)v[i]=pow(fmax(0,gray+(v[i]-gray)*c->saturation),c->gamma)*c->gain[i];
 double neutral=fmin(v[0],fmin(v[1],v[2]));v[1]-=neutral*c->warmth*.35;v[2]-=neutral*c->warmth;
 return (GlowlineRGB){(uint8_t)lround(bounded(v[0]*c->brightness,0,1,0)*255+1e-9),(uint8_t)lround(bounded(v[1]*c->brightness,0,1,0)*255+1e-9),(uint8_t)lround(bounded(v[2]*c->brightness,0,1,0)*255+1e-9)};
}
static GlowlineRGB hsv_rgb(double hue,double saturation,double value){
 hue-=floor(hue);double h=hue*6;int sector=(int)h;double f=h-sector,p=value*(1-saturation),q=value*(1-f*saturation),t=value*(1-(1-f)*saturation),r=value,g=t,b=p;
 switch(sector){case 1:r=q;g=value;b=p;break;case 2:r=p;g=value;b=t;break;case 3:r=p;g=q;b=value;break;case 4:r=t;g=p;b=value;break;case 5:r=value;g=p;b=q;break;}
 return (GlowlineRGB){(uint8_t)lround(r*255+1e-9),(uint8_t)lround(g*255+1e-9),(uint8_t)lround(b*255+1e-9)};
}
static GlowlineRGB mode_color(size_t i,double seconds,const EngineControls *c){
 double position=i/111.,phase=seconds*c->speed*(c->reverse?-1:1);GlowlineRGB a=c->primary,b=c->secondary;
 if(c->mode==1)return a;
 if(c->mode==2){double blend=pow(position,log(.5)/log(c->gradientBalance));return effect_mix(a,b,blend,1);}
 if(c->mode==3){double level=c->breathingFloor+(1-c->breathingFloor)*(.5-.5*cos(phase*1.25));return (GlowlineRGB){lround(a.r*level),lround(a.g*level),lround(a.b*level)};}
 if(c->mode==4)return hsv_rgb(position*c->rainbowCycles+phase*.06,1,1);
 if(c->mode==5){double light=.75+c->candleFlicker*(.12*sin(phase*2.3+position*2)+.06*sin(phase*4.1+position*5));return (GlowlineRGB){lround(255*light),lround(108*light),lround(20*light)};}
 // The mounted fire orientation flips both space and advection, preserving upward travel.
 if(c->mode==6){size_t cell=grid_indices[i];return fire_color((cell%43)/42.,1-(cell/43)/16.,-phase,c->flameHeight);}
 if(c->mode==7)return comet_color(i/112.,phase,c->reverse,a,b,c->cometTail);
 if(c->mode==8)return aurora_color(i/112.,phase,c->auroraPink);
 return a;
}
