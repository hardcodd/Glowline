#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

enum { CONTROLLER_REPLY_SIZE = 14 };

/* Moni-A returns the six-byte model, a comma and seven device-specific bytes.
 * The suffix identifies an instance, not compatibility. This model still uses
 * the fixed 112-LED layout; the reply does not negotiate a strip length.
 * Firmware may append CR LF after the binary identity.
 */
static bool controller_reply_is_compatible(const uint8_t *reply, size_t length) {
    static const uint8_t model[] = {'S', 'K', '0', 'L', '3', '4', ','};
    if (reply == NULL || (length != CONTROLLER_REPLY_SIZE && length != CONTROLLER_REPLY_SIZE + 2))
        return false;
    if (memcmp(reply, model, sizeof(model)) != 0)
        return false;
    return length == CONTROLLER_REPLY_SIZE ||
           (reply[CONTROLLER_REPLY_SIZE] == '\r' && reply[CONTROLLER_REPLY_SIZE + 1] == '\n');
}
