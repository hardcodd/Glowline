#import "capture.m"
#include <assert.h>
int main(void) { @autoreleasepool {
    SRGBCapture *capture = [SRGBCapture new];
    [capture setCaptureRate:144];
    assert(capture.requestedCaptureRate == 144);
    CVPixelBufferRef pixel = NULL;
    assert(CVPixelBufferCreate(kCFAllocatorDefault, 2, 2, kCVPixelFormatType_64RGBAHalf, NULL, &pixel) == kCVReturnSuccess);
    assert(CVPixelBufferLockBaseAddress(pixel, 0) == kCVReturnSuccess);
    for (size_t y=0;y<2;y++) for(size_t x=0;x<2;x++) {
        _Float16 rgba[4]={1,1,1,1};
        memcpy((uint8_t *)CVPixelBufferGetBaseAddress(pixel)+y*CVPixelBufferGetBytesPerRow(pixel)+x*8,rgba,sizeof(rgba));
    }
    CVPixelBufferUnlockBaseAddress(pixel, 0);
    CMVideoFormatDescriptionRef format = NULL;
    assert(CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,pixel,&format)==noErr);
    CMSampleBufferRef sample = NULL;
    CMSampleTimingInfo timing={kCMTimeInvalid,kCMTimeZero,kCMTimeInvalid};
    assert(CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,pixel,format,&timing,&sample)==noErr);
    NSArray *attachments=(__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample,YES);
    NSMutableDictionary *info=attachments.firstObject;
    info[SCStreamFrameInfoStatus]=@(SCFrameStatusComplete);
    info[SCStreamFrameInfoDisplayTime]=@(mach_absolute_time());
    [capture stream:capture.stream didOutputSampleBuffer:sample ofType:SCStreamOutputTypeScreen];
    assert(capture.ready && !capture.failed && capture.acceptedFrames==1);
    GlowlineRGB colors[731];
    [capture render:colors count:731];
    assert(colors[0].r==255 && colors[0].g==255 && colors[0].b==255);
    assert(!capture.detailMode);
    capture.detailMode=YES;
    [capture render:colors count:731];
    assert(colors[0].r==255 && colors[0].g==255 && colors[0].b==255);
    CFRelease(sample);CFRelease(format);CVPixelBufferRelease(pixel);
    [capture stream:capture.stream didStopWithError:[NSError errorWithDomain:@"GlowlineTest" code:1 userInfo:nil]];
    assert(capture.failed && !capture.ready);
    memset(colors, 255, sizeof(colors));
    [capture render:colors count:731];
    for (size_t i=0; i<731; i++) assert(colors[i].r==0 && colors[i].g==0 && colors[i].b==0);
    assert(capture.errorMessage.length > 0);
    [capture stop];
    puts("capture failure invalidation contracts passed");
} return 0; }
