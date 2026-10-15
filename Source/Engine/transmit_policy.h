#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
/* Bound heartbeat tuning; a changed packet always bypasses the idle wait. */
static inline double valid_keepalive_seconds(double requested){
 return !isfinite(requested)?.1:fmax(.05,fmin(1.0,requested));
}
static inline bool frame_needs_send_with_keepalive(bool previous_valid,const uint8_t *previous,
                             const uint8_t *current,size_t size,double seconds_since_send,double keepalive){
 return !previous_valid||memcmp(previous,current,size)!=0||seconds_since_send>=valid_keepalive_seconds(keepalive);
}
/* Preserve the preceding policy for existing callers and rollback tests. */
static inline bool frame_needs_send(bool previous_valid,const uint8_t *previous,
                             const uint8_t *current,size_t size,double seconds_since_send){
 return frame_needs_send_with_keepalive(previous_valid,previous,current,size,seconds_since_send,.9);
}
