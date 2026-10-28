#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Windows keeps OS resources outside the portable color/sampling pipeline. */
typedef struct {
    int enabled, mode, mirrored, offset, reverse, side_enabled[4], detail;
    double brightness, warmth, saturation, gamma, gain[3], side_gain[4];
    double black_threshold, speed, gradient_balance, breathing_floor;
    double rainbow_cycles, candle_flicker, flame_height, comet_tail, aurora_pink;
    double edge_depth, release_seconds, attack_seconds;
    uint8_t primary[3], secondary[3];
} GLControls;

typedef struct GLPipeline GLPipeline;
GLPipeline *gl_create(void);
void gl_destroy(GLPipeline *pipeline);
// Render one 342-byte Ada frame for the fixed 112-LED layout. RGBA-half input
// uses byte stride; an invalid screen capture clears colors and smoothing state.
// Calls on a pipeline must be serialized and timestamps must be monotonic.
void gl_render(GLPipeline *pipeline, const GLControls *controls, const uint8_t *rgba_half,
               size_t width, size_t height, size_t stride, int capture_valid, double now,
               double animation_seconds, uint8_t packet[342]);
int gl_controller_reply(const uint8_t *reply, size_t length);
int gl_should_send(int valid, const uint8_t *previous, const uint8_t *current, double elapsed,
                   double keepalive);
#ifdef __cplusplus
}
#endif
