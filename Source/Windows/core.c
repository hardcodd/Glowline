#include "core.h"
#include "../Engine/controls.h"
#include "../Engine/transmit_policy.h"
#include "../Engine/controller_identity.h"
#include <stdlib.h>

struct GLPipeline {
    ReleaseState release[112];
};
GLPipeline *gl_create(void) { return calloc(1, sizeof(GLPipeline)); }
void gl_destroy(GLPipeline *pipeline) { free(pipeline); }

void gl_render(GLPipeline *p, const GLControls *s, const uint8_t *pixels, size_t width,
               size_t height, size_t stride, int valid, double now, double animation,
               uint8_t packet[342]) {
    EngineControls c = default_controls();
    c.enabled = s->enabled;
    c.mode = s->mode;
    c.mirrored = s->mirrored;
    c.offset = s->offset;
    c.reverse = s->reverse;
    c.brightness = s->brightness;
    c.warmth = s->warmth;
    c.saturation = s->saturation;
    c.gamma = s->gamma;
    c.blackThreshold = s->black_threshold;
    c.speed = s->speed;
    c.gradientBalance = s->gradient_balance;
    c.breathingFloor = s->breathing_floor;
    c.rainbowCycles = s->rainbow_cycles;
    c.candleFlicker = s->candle_flicker;
    c.flameHeight = s->flame_height;
    c.cometTail = s->comet_tail;
    c.auroraPink = s->aurora_pink;
    for (int i = 0; i < 3; i++)
        c.gain[i] = s->gain[i];
    for (int i = 0; i < 4; i++) {
        c.sideGain[i] = s->side_gain[i];
        c.sideEnabled[i] = s->side_enabled[i];
    }
    c.primary = (GlowlineRGB){s->primary[0], s->primary[1], s->primary[2]};
    c.secondary = (GlowlineRGB){s->secondary[0], s->secondary[1], s->secondary[2]};
    GlowlineRGB grid[731] = {0};
    if (c.mode == 0 && valid)
        sample_edge_grid_mode(pixels, width, height, stride, 43, 17, grid, 731, s->edge_depth,
                              s->detail);
    static const uint8_t header[] = {0x41, 0x64, 0x61, 0, 0, 0x70};
    memcpy(packet, header, sizeof(header));
    for (size_t i = 0; i < 112; i++) {
        GlowlineRGB raw =
            c.mode == 0 ? grid[mapped_grid_index(i, &c)] : mode_color(i, animation, &c);
        GlowlineRGB target = adjust_color(raw, &c);
        double gain = c.sideGain[led_side(i)];
        target =
            (GlowlineRGB){lround(fmin(255, target.r * gain)), lround(fmin(255, target.g * gain)),
                          lround(fmin(255, target.b * gain))};
        if (!led_enabled(i, &c) || (c.mode == 0 && !valid)) {
            memset(&p->release[i], 0, sizeof(ReleaseState));
            target = (GlowlineRGB){0};
        }
        if (s->attack_seconds > 0 && p->release[i].initialized) {
            double peak = fmax(target.r, fmax(target.g, target.b)), old = p->release[i].level;
            if (peak > old) {
                double level =
                    old + (peak - old) *
                              (1 - exp(-fmax(0, now - p->release[i].time) / s->attack_seconds));
                double scale = level / peak;
                target = (GlowlineRGB){lround(target.r * scale), lround(target.g * scale),
                                       lround(target.b * scale)};
            }
        }
        GlowlineRGB rgb = release_rgb(&p->release[i], target, now, s->release_seconds);
        packet[6 + i * 3] = rgb.r;
        packet[7 + i * 3] = rgb.g;
        packet[8 + i * 3] = rgb.b;
    }
}

int gl_controller_reply(const uint8_t *reply, size_t length) {
    return controller_reply_is_compatible(reply, length);
}
int gl_should_send(int valid, const uint8_t *previous, const uint8_t *current, double elapsed,
                   double keepalive) {
    return frame_needs_send_with_keepalive(valid, previous, current, 342, elapsed, keepalive);
}
