#pragma once
#include <stdint.h>
#include <string.h>

/* Decode IEEE 754 binary16 without F16C or compiler-runtime half helpers.
 * All finite values are exactly representable in binary32. Capture surfaces
 * and supported desktop CPUs use little-endian/native-endian channel words. */
static float glowline_half_to_float(const uint8_t *channel) {
    uint16_t half;
    memcpy(&half, channel, sizeof(half));
    uint32_t sign = (uint32_t)(half & 0x8000) << 16;
    uint32_t fraction = half & 0x3ff, exponent = (half >> 10) & 0x1f, bits;
    if (exponent == 0) {
        if (fraction == 0)
            bits = sign;
        else {
            int normal_exponent = -14;
            while (!(fraction & 0x400)) {
                fraction <<= 1;
                normal_exponent--;
            }
            bits = sign | ((uint32_t)(normal_exponent + 127) << 23) | ((fraction & 0x3ff) << 13);
        }
    } else if (exponent == 31)
        bits = sign | 0x7f800000 | (fraction << 13);
    else
        bits = sign | ((exponent + 112) << 23) | (fraction << 13);
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}
