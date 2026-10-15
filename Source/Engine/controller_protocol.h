#ifndef GLOWLINE_CONTROLLER_PROTOCOL_H
#define GLOWLINE_CONTROLLER_PROTOCOL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <poll.h>
#include <time.h>
#include <unistd.h>

enum { CONTROLLER_REPLY_SIZE = 14 };

/* Moni-A returns the six-byte model, a comma and seven device-specific bytes.
 * The suffix identifies an instance, not compatibility. This model still uses
 * the fixed 112-LED layout; the reply does not negotiate a strip length.
 */
static bool controller_reply_is_compatible(const uint8_t *reply, size_t length) {
    static const uint8_t model[] = {'S', 'K', '0', 'L', '3', '4', ','};
    return reply != NULL && length == CONTROLLER_REPLY_SIZE &&
        memcmp(reply, model, sizeof(model)) == 0;
}

/* Send only the identity query on an already configured, exclusive port.
 * Accumulate fragmented binary replies within one monotonic deadline. Fail
 * closed on timeout, malformed replies or I/O errors, before any LED frame.
 */
static bool query_compatible_controller(int fd, int timeout_ms) {
    if (timeout_ms <= 0 || write(fd, "Moni-A", 6) != 6) return false;
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return false;
    int64_t deadline = (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000 + timeout_ms;
    uint8_t reply[128];
    size_t received = 0;
    while (received < CONTROLLER_REPLY_SIZE) {
        if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return false;
        int64_t remaining = deadline - ((int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000);
        if (remaining <= 0) return false;
        struct pollfd port = { .fd = fd, .events = POLLIN };
        int ready = poll(&port, 1, (int)remaining);
        if (ready < 0 && errno == EINTR) continue;
        if (ready <= 0 || !(port.revents & POLLIN)) return false;
        ssize_t count = read(fd, reply + received, sizeof(reply) - received);
        if (count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        if (count <= 0) return false;
        received += (size_t)count;
    }
    return controller_reply_is_compatible(reply, received);
}

#endif
