#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <os/lock.h>
#include "ambience.h"
#include "latency.h"
#include <mach/mach_time.h>

@interface SRGBCapture : NSObject <SCStreamOutput, SCStreamDelegate> {
 os_unfair_lock _lock;
 CVPixelBufferRef _latest;
 CaptureTiming _timing;
 BOOL _stopped;
}
@property(nonatomic,strong) SCStream *stream;
@property(nonatomic,strong) dispatch_queue_t queue;
@property(nonatomic,strong) SCStreamConfiguration *configuration;
@property(nonatomic,strong) NSCondition *frameCondition;
@property(atomic) double edgeDepth;
@property(nonatomic) uint32_t displayID;
@property(atomic) BOOL ready;
@property(atomic) uint64_t receivedFrames;
@property(atomic) uint64_t futureFrames;
@property(atomic) uint64_t acceptedFrames;
@property(atomic) BOOL failed;
@property(nonatomic) uint32_t width;
@property(nonatomic) uint32_t height;
@property(nonatomic) SkydimoHostApiV1 host;
- (void)start;
- (void)stop;
- (void)render:(SkydimoRgb *)out count:(size_t)count;
- (void)render:(SkydimoRgb *)out count:(size_t)count timing:(CaptureTiming *)timing;
- (void)setCaptureRate:(NSInteger)fps;
- (void)waitForFrameAfter:(uint64_t)displayed timeout:(double)seconds;
@end
@implementation SRGBCapture
- (instancetype)init { if((self=[super init])) {_lock=OS_UNFAIR_LOCK_INIT;_width=43;_height=17;_frameCondition=[NSCondition new];_queue=dispatch_queue_create("local.skydimo.srgb.capture",DISPATCH_QUEUE_SERIAL);}return self; }
- (void)report:(NSString *)message { const char *s=message.UTF8String;fprintf(stderr,"%s\n",s);if(self.host.log)self.host.log(self.host.host_ctx,SKYDIMO_LOG_INFO,s,strlen(s)); }
- (void)start {
 __weak SRGBCapture *weakSelf=self;
 [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:YES completionHandler:^(SCShareableContent *content,NSError *error) {
  SRGBCapture *owner=weakSelf;if(!owner)return;
  dispatch_async(owner.queue,^{
   if(owner->_stopped)return;
   if(error){owner.failed=YES;[owner report:[@"sRGB capture unavailable: " stringByAppendingString:error.description]];return;}
   SCDisplay *display=nil;for(SCDisplay *candidate in content.displays)if(candidate.displayID==(owner.displayID?:CGMainDisplayID()))display=candidate;
   if(!display)for(SCDisplay *candidate in content.displays)if(candidate.displayID==CGMainDisplayID())display=candidate;
   if(!display){owner.failed=YES;[owner report:@"sRGB capture: main display not found"];return;}
   SCContentFilter *filter=[[SCContentFilter alloc]initWithDisplay:display excludingWindows:@[]];
   SCStreamConfiguration *config=[SCStreamConfiguration new];
   config.width=344;config.height=MAX(1,(NSUInteger)llround(344.0*display.height/display.width));
   // Canonical HDR capture bypasses the SDR display-profile roundtrip that
   // clips source primaries. This does not switch the physical display to HDR.
   config.captureDynamicRange=SCCaptureDynamicRangeHDRCanonicalDisplay;
   config.pixelFormat=kCVPixelFormatType_64RGBAHalf;
   config.colorSpaceName=kCGColorSpaceExtendedLinearSRGB;
   config.minimumFrameInterval=CMTimeMake(1,120);config.queueDepth=3;config.showsCursor=NO;
   config.scalesToFit=YES;config.capturesAudio=NO;
   owner.configuration=config;
   owner.stream=[[SCStream alloc]initWithFilter:filter configuration:config delegate:owner];
   NSError *addError=nil;
   if(![owner.stream addStreamOutput:owner type:SCStreamOutputTypeScreen sampleHandlerQueue:owner.queue error:&addError]){owner.failed=YES;[owner report:addError.description];owner.stream=nil;return;}
   [owner.stream startCaptureWithCompletionHandler:^(NSError *startError){if(startError){owner.failed=YES;[owner report:startError.description];}else[owner report:@"Canonical capture started: linear sRGB RGBA-half, 344px, latest frame, no smoothing"]; }];
  });
 }];
}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
 if(type!=SCStreamOutputTypeScreen || !CMSampleBufferIsValid(sample) || _stopped)return;
 NSArray *attachments=(__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample,NO);
 NSDictionary *info=attachments.firstObject;
 NSNumber *status=info[SCStreamFrameInfoStatus],*displayed=info[SCStreamFrameInfoDisplayTime];
 uint64_t received=mach_absolute_time();self.receivedFrames++;if(displayed.unsignedLongLongValue>received)self.futureFrames++;
 if(!status||!capture_frame_metadata_valid(status.longValue,displayed.unsignedLongLongValue))return;
 CVPixelBufferRef pixel=CMSampleBufferGetImageBuffer(sample);if(!pixel)return;
 if(CVPixelBufferGetPixelFormatType(pixel)!=kCVPixelFormatType_64RGBAHalf){self.failed=YES;[self report:@"Unexpected pixel format; refusing incorrectly decoded colors"];return;}
 self.acceptedFrames++;self.ready=YES;
 CVPixelBufferRetain(pixel);
 os_unfair_lock_lock(&_lock);CVPixelBufferRef old=_latest;_latest=pixel;_timing=(CaptureTiming){displayed.unsignedLongLongValue,received};os_unfair_lock_unlock(&_lock);
 if(old)CVPixelBufferRelease(old);
 [self.frameCondition lock];[self.frameCondition broadcast];[self.frameCondition unlock];
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {self.failed=YES;[self report:error.description];}
- (void)render:(SkydimoRgb *)out count:(size_t)count {
 [self render:out count:count timing:NULL];
}
- (void)render:(SkydimoRgb *)out count:(size_t)count timing:(CaptureTiming *)timing {
 os_unfair_lock_lock(&_lock);CVPixelBufferRef pixel=_latest;if(pixel)CVPixelBufferRetain(pixel);if(timing)*timing=_timing;os_unfair_lock_unlock(&_lock);
 if(!pixel){memset(out,0,count*sizeof(*out));return;}
 if(CVPixelBufferLockBaseAddress(pixel,kCVPixelBufferLock_ReadOnly)==kCVReturnSuccess){
  sample_edge_grid(CVPixelBufferGetBaseAddress(pixel),CVPixelBufferGetWidth(pixel),CVPixelBufferGetHeight(pixel),CVPixelBufferGetBytesPerRow(pixel),self.width,self.height,out,count,self.edgeDepth);
  CVPixelBufferUnlockBaseAddress(pixel,kCVPixelBufferLock_ReadOnly);
 }
 CVPixelBufferRelease(pixel);
}
- (void)setCaptureRate:(NSInteger)fps {
 fps=MAX(30,MIN(240,fps));
 dispatch_async(self.queue,^{
  if(self->_stopped||!self.configuration)return;
  self.configuration.minimumFrameInterval=CMTimeMake(1,(int32_t)fps);
  [self.stream updateConfiguration:self.configuration completionHandler:^(NSError *error){if(error)[self report:error.description];}];
 });
}
- (void)waitForFrameAfter:(uint64_t)displayed timeout:(double)seconds {
 [self.frameCondition lock];
 os_unfair_lock_lock(&_lock);BOOL newer=_timing.displayed!=displayed;os_unfair_lock_unlock(&_lock);
 if(!newer)[self.frameCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
 [self.frameCondition unlock];
}
- (void)stop {
 dispatch_sync(self.queue,^{self->_stopped=YES;[self.stream stopCaptureWithCompletionHandler:^(NSError *error){}];self.stream=nil;});
 os_unfair_lock_lock(&_lock);CVPixelBufferRef old=_latest;_latest=NULL;os_unfair_lock_unlock(&_lock);if(old)CVPixelBufferRelease(old);
}
@end
