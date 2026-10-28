#import "capture.m"
#include "controls.h"
#include "pacing.h"
#include "transmit_policy.h"
#include "controller_protocol.h"
#include <mach/mach_time.h>
#include <pthread/qos.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
static volatile sig_atomic_t stopping=0;
static void stop_signal(int signal){stopping=1;}
static double monotonic_seconds(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
/* Match the bundled serial protocol; never change the controller baud or firmware. */
static int open_controller(struct termios *original){
 const char *port=getenv("GLOWLINE_PORT");
 if(!port||!*port){fprintf(stderr,"Select the controller USB serial port in Glowline settings\n");return -1;}
 int fd=open(port,O_RDWR|O_NOCTTY|O_NONBLOCK);
 if(fd<0){perror("open controller (quit Skydimo first)");return -1;}
 if(ioctl(fd,TIOCEXCL)<0||tcgetattr(fd,original)<0){perror("exclusive controller");close(fd);return -1;}
 struct termios settings=*original;cfmakeraw(&settings);cfsetspeed(&settings,B115200);
 settings.c_cflag|=CLOCAL|CREAD;settings.c_cflag&=~(CSTOPB|PARENB|CSIZE|CRTSCTS);settings.c_cflag|=CS8;
 settings.c_cc[VMIN]=0;settings.c_cc[VTIME]=1;
 if(tcsetattr(fd,TCSANOW,&settings)<0){perror("serial settings");close(fd);return -1;}
 int bits=TIOCM_DTR|TIOCM_RTS;ioctl(fd,TIOCMBIC,&bits);usleep(60000);ioctl(fd,TIOCMBIS,&bits);usleep(350000);tcflush(fd,TCIOFLUSH);
 if(!query_compatible_controller(fd,600)){fprintf(stderr,"Unsupported or incomplete SK0L34 response; refusing LED writes\n");tcsetattr(fd,TCSANOW,original);close(fd);return -1;}
 int flags=fcntl(fd,F_GETFL);fcntl(fd,F_SETFL,flags&~O_NONBLOCK);
 fprintf(stderr,"Verified SK0L34 protocol, fixed 112-LED layout, 115200 baud\n");return fd;
}
/* A capability probe sends only the vendor identity request, then restores the verified rate. */
static BOOL verify_identity_at_rate(int fd,speed_t rate){
 struct termios settings;if(tcgetattr(fd,&settings)<0)return NO;
 cfsetspeed(&settings,rate);if(tcsetattr(fd,TCSANOW,&settings)<0)return NO;
 tcflush(fd,TCIOFLUSH);usleep(50000);
 int flags=fcntl(fd,F_GETFL);fcntl(fd,F_SETFL,flags|O_NONBLOCK);
 BOOL compatible=query_compatible_controller(fd,600);
 fcntl(fd,F_SETFL,flags);
 return compatible;
}
static BOOL write_frame(int fd,const uint8_t *bytes,size_t len){size_t offset=0;while(offset<len){ssize_t n=write(fd,bytes+offset,len-offset);if(n>0)offset+=(size_t)n;else if(n<0&&errno==EINTR)continue;else return NO;}return offset==len;}
static void wait_until(double deadline){
 double remaining=deadline-monotonic_seconds();if(remaining<=0)return;
 mach_timebase_info_data_t scale;mach_timebase_info(&scale);
 mach_wait_until(mach_absolute_time()+(uint64_t)(remaining*1e9*scale.denom/scale.numer));
}
int main(int argc,const char *argv[]){@autoreleasepool{
 BOOL captureOnly=argc==3&&strcmp(argv[1],"--capture-only")==0;
 if(argc!=2&&!captureOnly){fprintf(stderr,"Usage: ambilight-srgb [--capture-only] STATUS_JSON_PATH\n");return 2;}
 NSString *statusPath=[NSString stringWithUTF8String:argv[captureOnly?2:1]];
 signal(SIGTERM,stop_signal);signal(SIGINT,stop_signal);signal(SIGPIPE,SIG_IGN);
 struct termios original;int fd=captureOnly?-1:open_controller(&original);if(!captureOnly&&fd<0)return 3;
 if(strcmp(argv[1],"--probe-baud")==0){
  BOOL faster=verify_identity_at_rate(fd,B230400);
  BOOL restored=verify_identity_at_rate(fd,B115200);
  printf("{\"baud230400IdentityVerified\":%s,\"baud115200RestoredAndVerified\":%s}\n",faster?"true":"false",restored?"true":"false");
  tcdrain(fd);tcsetattr(fd,TCSANOW,&original);close(fd);return restored?0:5;
 }
 SRGBCapture *capture=[SRGBCapture new];
 capture.displayID=(uint32_t)strtoul(getenv("GLOWLINE_DISPLAY")?:"0",NULL,10);
 BOOL canCapture=CGPreflightScreenCaptureAccess();if(canCapture)[capture start];
 dispatch_queue_t outputQueue=dispatch_queue_create("local.skydimo.serial",DISPATCH_QUEUE_SERIAL);
 dispatch_group_t group=dispatch_group_create();
 dispatch_group_async(group,outputQueue,^{@autoreleasepool{
  pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE,0);
  uint8_t packet[342]={0x41,0x64,0x61,0x00,0x00,0x70};GlowlineRGB grid[731];
  double started=monotonic_seconds(),windowStart=started,writeTotal=0;unsigned long total=0,windowFrames=0,windowSamples=0,windowDuplicates=0,windowFresh=0;
  double sampleTotal=0,duplicateWaitTotal=0,pacingWaitTotal=0;
  double targetFps=33.68,nextDeadline=started,drainMaxMs=0,tuningRead=0;
  unsigned drainEvery=1,queueLimit=64,drains=0,maxQueued=0;BOOL drainEach=NO,queueSupported=YES,trace=NO;
  mach_timebase_info_data_t timebase;mach_timebase_info(&timebase);
  uint64_t previousSource=0;CaptureTiming pending[128];unsigned pendingCount=0;
  int traceFd=-1;NSInteger captureRate=120;BOOL skipUnchanged=YES,havePrevious=NO;uint8_t previousPacket[342]={0};double lastSentAt=0,keepaliveSeconds=.1;
  ReleaseState releaseStates[112]={0};double edgeDepth=.15,warmth=.5,releaseSeconds=.18,attackSeconds=0;EngineControls controls=default_controls();capture.edgeDepth=edgeDepth;
  NSString *tuningPath=[statusPath stringByAppendingString:@".tuning.json"];
  while(!stopping){@autoreleasepool{
   double loopNow=monotonic_seconds();
   if(loopNow-tuningRead>=.12){
    NSData *data=[NSData dataWithContentsOfFile:tuningPath];
    id candidate=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if([candidate isKindOfClass:[NSDictionary class]]){
     NSDictionary *tuning=candidate;
     if([tuning[@"edgeDepth"] isKindOfClass:[NSNumber class]])edgeDepth=fmin(.35,fmax(0,[tuning[@"edgeDepth"] doubleValue]));
     if([tuning[@"warmth"] isKindOfClass:[NSNumber class]])warmth=fmin(.9,fmax(0,[tuning[@"warmth"] doubleValue]));
     if([tuning[@"releaseSeconds"] isKindOfClass:[NSNumber class]])releaseSeconds=fmin(1,fmax(0,[tuning[@"releaseSeconds"] doubleValue]));
     capture.edgeDepth=edgeDepth;
     if([tuning[@"detailMode"] isKindOfClass:[NSNumber class]])capture.detailMode=[tuning[@"detailMode"] boolValue];
     capture.earlyResponse=[tuning[@"earlyResponse"] isKindOfClass:[NSNumber class]] && [tuning[@"earlyResponse"] boolValue];
     controls.warmth=warmth;
     if([tuning[@"enabled"] isKindOfClass:[NSNumber class]])controls.enabled=[tuning[@"enabled"] boolValue];
     if([tuning[@"mode"] isKindOfClass:[NSNumber class]])controls.mode=MAX(0,MIN(GLOWLINE_MODE_COUNT-1,[tuning[@"mode"] intValue]));
     if([tuning[@"mirrored"] isKindOfClass:[NSNumber class]])controls.mirrored=[tuning[@"mirrored"] boolValue];
     if([tuning[@"offset"] isKindOfClass:[NSNumber class]])controls.offset=MAX(-111,MIN(111,[tuning[@"offset"] intValue]));
     if([tuning[@"reverse"] isKindOfClass:[NSNumber class]])controls.reverse=[tuning[@"reverse"] boolValue];
     if([tuning[@"brightness"] isKindOfClass:[NSNumber class]])controls.brightness=bounded([tuning[@"brightness"] doubleValue],0,1,1);
     if([tuning[@"saturation"] isKindOfClass:[NSNumber class]])controls.saturation=bounded([tuning[@"saturation"] doubleValue],0,2,1);
     if([tuning[@"gamma"] isKindOfClass:[NSNumber class]])controls.gamma=bounded([tuning[@"gamma"] doubleValue],.5,2.5,1);
     if([tuning[@"blackThreshold"] isKindOfClass:[NSNumber class]])controls.blackThreshold=bounded([tuning[@"blackThreshold"] doubleValue],0,.2,0);
     if([tuning[@"speed"] isKindOfClass:[NSNumber class]])controls.speed=bounded([tuning[@"speed"] doubleValue],.1,5,1);
     if([tuning[@"gradientBalance"] isKindOfClass:[NSNumber class]])controls.gradientBalance=bounded([tuning[@"gradientBalance"] doubleValue],0.1,0.9,0.5);
     if([tuning[@"breathingFloor"] isKindOfClass:[NSNumber class]])controls.breathingFloor=bounded([tuning[@"breathingFloor"] doubleValue],0,0.8,0.15);
     if([tuning[@"rainbowCycles"] isKindOfClass:[NSNumber class]])controls.rainbowCycles=bounded([tuning[@"rainbowCycles"] doubleValue],0.5,3,1);
     if([tuning[@"candleFlicker"] isKindOfClass:[NSNumber class]])controls.candleFlicker=bounded([tuning[@"candleFlicker"] doubleValue],0,1,1);
     if([tuning[@"flameHeight"] isKindOfClass:[NSNumber class]])controls.flameHeight=bounded([tuning[@"flameHeight"] doubleValue],0.3,2,1);
     if([tuning[@"cometTail"] isKindOfClass:[NSNumber class]])controls.cometTail=bounded([tuning[@"cometTail"] doubleValue],0.3,2,1);
     if([tuning[@"auroraPink"] isKindOfClass:[NSNumber class]])controls.auroraPink=bounded([tuning[@"auroraPink"] doubleValue],0,2,1);
     if([tuning[@"attackSeconds"] isKindOfClass:[NSNumber class]])attackSeconds=bounded([tuning[@"attackSeconds"] doubleValue],0,1,0);
     for(int j=0;j<3;j++){
      NSString *gainKey=@[@"redGain",@"greenGain",@"blueGain"][j];
      if([tuning[gainKey] isKindOfClass:[NSNumber class]])controls.gain[j]=bounded([tuning[gainKey] doubleValue],0,2,1);
     }
     for(int j=0;j<4;j++){
      NSString *enableKey=@[@"leftEnabled",@"topEnabled",@"rightEnabled",@"bottomEnabled"][j];
      NSString *gainKey=@[@"leftGain",@"topGain",@"rightGain",@"bottomGain"][j];
      if([tuning[enableKey] isKindOfClass:[NSNumber class]])controls.sideEnabled[j]=[tuning[enableKey] boolValue];
      if([tuning[gainKey] isKindOfClass:[NSNumber class]])controls.sideGain[j]=bounded([tuning[gainKey] doubleValue],0,2,1);
     }
     NSArray *primary=tuning[@"primary"],*secondary=tuning[@"secondary"];
     if([primary isKindOfClass:[NSArray class]]&&primary.count==3&&[primary[0] isKindOfClass:[NSNumber class]]&&[primary[1] isKindOfClass:[NSNumber class]]&&[primary[2] isKindOfClass:[NSNumber class]])controls.primary=(GlowlineRGB){bounded([primary[0] doubleValue],0,255,0),bounded([primary[1] doubleValue],0,255,0),bounded([primary[2] doubleValue],0,255,0)};
     if([secondary isKindOfClass:[NSArray class]]&&secondary.count==3&&[secondary[0] isKindOfClass:[NSNumber class]]&&[secondary[1] isKindOfClass:[NSNumber class]]&&[secondary[2] isKindOfClass:[NSNumber class]])controls.secondary=(GlowlineRGB){bounded([secondary[0] doubleValue],0,255,0),bounded([secondary[1] doubleValue],0,255,0),bounded([secondary[2] doubleValue],0,255,0)};
     if([tuning[@"fps"] isKindOfClass:[NSNumber class]])targetFps=valid_target_fps([tuning[@"fps"] doubleValue]);
     if([tuning[@"drainEach"] isKindOfClass:[NSNumber class]])drainEach=[tuning[@"drainEach"] boolValue];
     if([tuning[@"drainEvery"] isKindOfClass:[NSNumber class]])drainEvery=MAX(1,MIN(120,[tuning[@"drainEvery"] unsignedIntValue]));
     if([tuning[@"queueLimit"] isKindOfClass:[NSNumber class]])queueLimit=MIN(342,[tuning[@"queueLimit"] unsignedIntValue]);
     if([tuning[@"captureFps"] isKindOfClass:[NSNumber class]]){NSInteger requested=MAX(30,MIN(240,[tuning[@"captureFps"] integerValue]));if(requested!=captureRate){captureRate=requested;[capture setCaptureRate:captureRate];}}
     if([tuning[@"trace"] isKindOfClass:[NSNumber class]])trace=[tuning[@"trace"] boolValue];
     if([tuning[@"keepaliveSeconds"] isKindOfClass:[NSNumber class]])keepaliveSeconds=valid_keepalive_seconds([tuning[@"keepaliveSeconds"] doubleValue]);
     if([tuning[@"skipUnchanged"] isKindOfClass:[NSNumber class]])skipUnchanged=[tuning[@"skipUnchanged"] boolValue];
     if(trace&&traceFd<0)traceFd=open([[statusPath stringByAppendingString:@".trace.jsonl"] fileSystemRepresentation],O_WRONLY|O_CREAT|O_APPEND,0600);
     if(!trace&&traceFd>=0){close(traceFd);traceFd=-1;pendingCount=0;}
    }tuningRead=loopNow;
   }
   if(!captureOnly&&!drainEach){
    double pacingStart=monotonic_seconds();wait_until(nextDeadline);pacingWaitTotal+=monotonic_seconds()-pacingStart;
    int queued=0;if(queueSupported){if(ioctl(fd,TIOCOUTQ,&queued)<0)queueSupported=NO;else maxQueued=MAX(maxQueued,(unsigned)MAX(0,queued));}
    if(queueSupported&&queued>(int)queueLimit){double begin=monotonic_seconds();if(tcdrain(fd)<0){stopping=1;break;}drainMaxMs=fmax(drainMaxMs,(monotonic_seconds()-begin)*1000);drains++;}
   }
   CaptureTiming timing={0};uint64_t sampleStart=mach_absolute_time();
   if(controls.mode==0&&capture.ready&&!capture.failed)[capture render:grid count:731 timing:&timing];else memset(grid,0,sizeof(grid));
   uint64_t sampleEnd=mach_absolute_time();windowSamples++;sampleTotal+=mach_elapsed_ms(sampleStart,sampleEnd,timebase.numer,timebase.denom);
   BOOL fresh=timing.displayed&&timing.displayed!=previousSource;
   previousSource=timing.displayed;if(fresh)windowFresh++;
   double filterNow=monotonic_seconds();
   for(size_t i=0;i<112;i++){
    GlowlineRGB raw=controls.mode==0?grid[mapped_grid_index(i,&controls)]:mode_color(i,filterNow-started,&controls);
    GlowlineRGB target=adjust_color(raw,&controls);double gain=controls.sideGain[led_side(i)];
    target=(GlowlineRGB){lround(fmin(255,target.r*gain)),lround(fmin(255,target.g*gain)),lround(fmin(255,target.b*gain))};
    if(!led_enabled(i,&controls)||(controls.mode==0&&capture.failed)){memset(&releaseStates[i],0,sizeof(ReleaseState));target=(GlowlineRGB){0};}
    if(attackSeconds>0&&releaseStates[i].initialized){
     double peak=fmax(target.r,fmax(target.g,target.b)),old=releaseStates[i].level;
     if(peak>old){double level=old+(peak-old)*(1-exp(-fmax(0,filterNow-releaseStates[i].time)/attackSeconds));double scale=level/peak;target=(GlowlineRGB){lround(target.r*scale),lround(target.g*scale),lround(target.b*scale)};}
    }
    GlowlineRGB c=release_rgb(&releaseStates[i],target,filterNow,releaseSeconds);
    packet[6+i*3]=c.r;packet[7+i*3]=c.g;packet[8+i*3]=c.b;
   }
   if(!captureOnly&&skipUnchanged&&!frame_needs_send_with_keepalive(havePrevious,previousPacket,packet,sizeof(packet),monotonic_seconds()-lastSentAt,keepaliveSeconds)){
    windowDuplicates++;double waiting=monotonic_seconds();double idleWait=fmin(.025,fmax(.001,keepaliveSeconds-(monotonic_seconds()-lastSentAt)));if(controls.mode==0&&capture.ready)[capture waitForFrameAfter:timing.displayed timeout:idleWait];else usleep((useconds_t)(idleWait*1e6));duplicateWaitTotal+=monotonic_seconds()-waiting;nextDeadline=monotonic_seconds();continue;
   }
   uint64_t submit=mach_absolute_time();
   if(trace&&fresh&&pendingCount<128)pending[pendingCount++]=timing;
   double before=monotonic_seconds();if(!captureOnly&&!write_frame(fd,packet,sizeof(packet))){perror("serial frame");stopping=1;break;}
   uint64_t writeEnd=mach_absolute_time();
   if(traceFd>=0){
    uint64_t hash=14695981039346656037ULL;unsigned sum=0,maxDelta=0;
    for(size_t i=6;i<sizeof(packet);i++){hash=(hash^packet[i])*1099511628211ULL;sum+=packet[i];if(havePrevious){unsigned delta=(unsigned)abs((int)packet[i]-(int)previousPacket[i]);maxDelta=MAX(maxDelta,delta);}}
    dprintf(traceFd,"{\"event\":\"transmit\",\"time\":%.9f,\"payloadHash\":\"%016llx\",\"channelSum\":%u,\"maxChannelDelta\":%u,\"previousValid\":%s}\n",before,(unsigned long long)hash,sum,maxDelta,havePrevious?"true":"false");
   }
   if(!captureOnly){memcpy(previousPacket,packet,sizeof(packet));havePrevious=YES;lastSentAt=monotonic_seconds();}
   if(traceFd>=0&&fresh){
    dprintf(traceFd,"{\"event\":\"submit\",\"source\":%llu,\"captureDeliveryMs\":%.6f,\"ageAtSubmitMs\":%.6f,\"sampleMs\":%.6f,\"writeMs\":%.6f,\"ageAtWriteReturnMs\":%.6f}\n",(unsigned long long)timing.displayed,mach_signed_offset_ms(timing.displayed,timing.received,timebase.numer,timebase.denom),mach_signed_offset_ms(timing.displayed,submit,timebase.numer,timebase.denom),mach_elapsed_ms(sampleStart,sampleEnd,timebase.numer,timebase.denom),mach_elapsed_ms(submit,writeEnd,timebase.numer,timebase.denom),mach_signed_offset_ms(timing.displayed,writeEnd,timebase.numer,timebase.denom));
   }
   if(!captureOnly&&(drainEach||(total+1)%drainEvery==0)){
    double begin=monotonic_seconds();if(tcdrain(fd)<0){perror("serial drain");stopping=1;break;}drainMaxMs=fmax(drainMaxMs,(monotonic_seconds()-begin)*1000);drains++;
    if(traceFd>=0){uint64_t drained=mach_absolute_time();for(unsigned i=0;i<pendingCount;i++)dprintf(traceFd,"{\"event\":\"drained\",\"source\":%llu,\"ageAtDrainUpperBoundMs\":%.6f}\n",(unsigned long long)pending[i].displayed,mach_signed_offset_ms(pending[i].displayed,drained,timebase.numer,timebase.denom));}pendingCount=0;
   }
   if(captureOnly)usleep(8333);
   nextDeadline=next_frame_deadline(nextDeadline,monotonic_seconds(),1.0/targetFps);
   writeTotal+=monotonic_seconds()-before;total++;windowFrames++;
   double now=monotonic_seconds();if(now-windowStart>=1){
    NSMutableArray *colors=[NSMutableArray arrayWithCapacity:112];
    for(size_t i=0;i<112;i++)[colors addObject:@[@(packet[6+i*3]),@(packet[7+i*3]),@(packet[8+i*3])]];
    NSDictionary *state=@{@"edgeDepth":@(edgeDepth),@"detailMode":@(capture.detailMode),@"warmth":@(warmth),@"releaseSeconds":@(releaseSeconds),@"keepaliveSeconds":@(keepaliveSeconds),@"captureReceived":@(capture.receivedFrames),@"captureFuture":@(capture.futureFrames),@"captureAccepted":@(capture.acceptedFrames),@"sampleCalls":@(windowSamples),@"freshSamples":@(windowFresh),@"duplicateSkips":@(windowDuplicates),@"duplicateWaitMs":@(duplicateWaitTotal*1000),@"pacingWaitMs":@(pacingWaitTotal*1000),@"samplingTotalMs":@(sampleTotal),@"windowSeconds":@(now-windowStart),@"effect":captureOnly?@"srgb_capture_verification":@"srgb_capture_standalone",@"captureColorSpace":@"extended-linear-sRGB",@"captureDynamicRange":@"canonicalHDR",@"pid":@(getpid()),@"serialVerified":@(!captureOnly),@"fps":captureOnly?@0:@(windowFrames/(now-windowStart)),@"averageFps":captureOnly?@0:@(total/(now-started)),@"brightness":@(controls.brightness*100),@"mirrored":@(controls.mirrored),@"mode":@(controls.mode),@"enabled":@(controls.enabled),@"captureReady":@(capture.ready&&!capture.failed),@"captureFailed":@(capture.failed),@"captureError":capture.errorMessage?:@"",@"displayID":@(capture.displayID),@"framesRendered":@(total),@"framesSent":captureOnly?@0:@(total),@"targetFps":@(targetFps),@"captureFps":@(captureRate),@"skipUnchanged":@(skipUnchanged),@"drainEvery":@(drainEvery),@"queueSupported":@(queueSupported),@"maxQueuedBytes":@(maxQueued),@"drainMaxMs":@(drainMaxMs),@"drains":@(drains),@"drainEach":@(drainEach),@"queueLimit":@(queueLimit),@"baud":@115200,@"writeMs":@(writeTotal/windowFrames*1000),@"timestamp":@([[NSDate date]timeIntervalSince1970]),@"colors":colors};
    NSMutableDictionary *reported=[state mutableCopy];reported[@"earlyResponse"]=@(capture.earlyResponse);
    NSData *data=[NSJSONSerialization dataWithJSONObject:reported options:0 error:nil];[data writeToFile:statusPath options:NSDataWritingAtomic error:nil];windowFrames=0;windowSamples=0;windowFresh=0;windowDuplicates=0;sampleTotal=0;duplicateWaitTotal=0;pacingWaitTotal=0;windowStart=now;writeTotal=0;maxQueued=0;drainMaxMs=0;drains=0;
   }
  }}
  if(traceFd>=0)close(traceFd);
 }});
 while(!stopping){if(getenv("GLOWLINE_PARENT")&&getppid()!=(pid_t)atoi(getenv("GLOWLINE_PARENT"))){stopping=1;break;}[[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];}
 dispatch_group_wait(group,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC));[capture stop];if(fd>=0){tcdrain(fd);tcsetattr(fd,TCSANOW,&original);close(fd);}return 0;
}}
