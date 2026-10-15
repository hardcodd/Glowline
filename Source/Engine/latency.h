#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
typedef struct CaptureTiming {uint64_t displayed,received;} CaptureTiming;
/* ScreenCaptureKit displayTime and mach_absolute_time share the Mach clock.
 * Invalid/missing timestamps must never turn into reassuring zero latency. */
static double mach_elapsed_ms(uint64_t from,uint64_t to,uint32_t numer,uint32_t denom){
 if(!from||to<from||!numer||!denom)return NAN;
 return (double)(to-from)*numer/denom/1e6;
}
/* Complete and started frames have pixels; idle/stopped events do not replace them. */
static bool capture_frame_status_valid(long status){return status==0||status==4;}

/* Source display timestamps can lead callback receipt on this capture path.
 * Preserve signed offsets for telemetry; timestamp order must not reject pixels. */
static double mach_signed_offset_ms(uint64_t from,uint64_t to,uint32_t numer,uint32_t denom){
 if(!from||!to||!numer||!denom)return NAN;
 return to>=from?(double)(to-from)*numer/denom/1e6:-(double)(from-to)*numer/denom/1e6;
}
static bool capture_frame_metadata_valid(long status,uint64_t displayed){
 return capture_frame_status_valid(status)&&displayed!=0;
}
