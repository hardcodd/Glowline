#include "../Source/Windows/core.h"
#include "../Source/Engine/half.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void require(int value, const char *message) {
    if (!value) {
        fprintf(stderr, "%s\n", message);
        exit(1);
    }
}
int main(void) {
    for (uint32_t bits = 0; bits < 65536; bits++) {
        uint16_t half = (uint16_t)bits;
        _Float16 reference;
        memcpy(&reference, &half, sizeof(reference));
        float expected = reference, actual = glowline_half_to_float((uint8_t *)&half);
        require(isnan(expected) ? isnan(actual)
                                : (actual == expected && signbit(actual) == signbit(expected)),
                "Half conversion mismatch");
    }
    GLPipeline *p = gl_create();
    require(p != NULL, "Pipeline allocation failed");
    GLControls c = {.enabled = 1,
                    .mode = 1,
                    .mirrored = 1,
                    .brightness = 1,
                    .saturation = 1,
                    .gamma = 1,
                    .gain = {1, 1, 1},
                    .side_gain = {1, 1, 1, 1},
                    .side_enabled = {1, 1, 1, 1},
                    .speed = 1,
                    .gradient_balance = .5,
                    .breathing_floor = .15,
                    .rainbow_cycles = 1,
                    .candle_flicker = 1,
                    .flame_height = 1,
                    .comet_tail = 1,
                    .aurora_pink = 1,
                    .edge_depth = .15,
                    .primary = {255, 160, 64},
                    .secondary = {72, 96, 255}};
    uint8_t packet[342], previous[342];
    gl_render(p, &c, NULL, 0, 0, 0, 0, 0, 0, packet);
    require(memcmp(packet, "Ada\0\0\x70", 6) == 0, "Packet header changed");
    for (int i = 0; i < 112; i++)
        require(memcmp(packet + 6 + i * 3, c.primary, 3) == 0, "Solid color mismatch");
    memcpy(previous, packet, sizeof(packet));
    require(!gl_should_send(1, previous, packet, .09, .1), "Duplicate frame sent early");
    require(gl_should_send(1, previous, packet, .1, .1), "Heartbeat missing");
    packet[6]--;
    require(gl_should_send(1, previous, packet, 0, .1), "Changed frame suppressed");
    c.release_seconds = .8;
    c.mode = 0;
    gl_render(p, &c, NULL, 0, 0, 0, 0, .1, .1, packet);
    for (int i = 6; i < 342; i++)
        require(packet[i] == 0, "Capture failure retained an illuminated LED");
    _Float16 pixels[344 * 136 * 4];
    for (int i = 0; i < 344 * 136; i++) {
        pixels[i * 4] = 1;
        pixels[i * 4 + 1] = 0;
        pixels[i * 4 + 2] = 0;
        pixels[i * 4 + 3] = 1;
    }
    gl_render(p, &c, (uint8_t *)pixels, 344, 136, 344 * 8, 1, 1, 1, packet);
    for (int i = 0; i < 112; i++)
        require(packet[6 + i * 3] == 255 && packet[7 + i * 3] == 0 && packet[8 + i * 3] == 0,
                "RGBA-half capture mismatch");
    c.side_enabled[0] = 0;
    gl_render(p, &c, (uint8_t *)pixels, 344, 136, 344 * 8, 1, 1.1, 1.1, packet);
    for (int i = 0; i < 15; i++)
        require(packet[6 + i * 3] == 0 && packet[7 + i * 3] == 0 && packet[8 + i * 3] == 0,
                "Disabled side faded instead of switching off");
    c.enabled = 0;
    gl_render(p, &c, NULL, 0, 0, 0, 0, 2, 2, packet);
    for (int i = 6; i < 342; i++)
        require(packet[i] == 0, "Disabled strip not black");
    const uint8_t reply[16] = {'S', 'K', '0', 'L', '3', '4', ',', 0, 1, 2, 3, 4, 5, 6, '\r', '\n'};
    require(gl_controller_reply(reply, 14) && gl_controller_reply(reply, 16),
            "Compatible controller rejected");
    require(!gl_controller_reply(reply, 13) && !gl_controller_reply(reply, 15) &&
                !gl_controller_reply(NULL, 14),
            "Malformed identity accepted");
    gl_destroy(p);
    puts("Windows portable pipeline contracts passed");
    return 0;
}
