#pragma once
#include <math.h>
/* Never exceed 342-byte 8N1 frames at the verified firmware baud. */
static double valid_target_fps(double requested){
 const double ceiling=115200.0/(342.0*10.0);
 return !isfinite(requested)||requested<1?33.0:fmin(requested,ceiling);
}
/* Skip missed slots; never replay a backlog of stale frames. */
static double next_frame_deadline(double previous,double now,double period){return fmax(previous+period,now);}
