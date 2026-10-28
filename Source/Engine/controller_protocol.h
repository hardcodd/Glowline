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

#include "controller_identity.h"

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
    /* Serial replies have no length field. Observe the complete bounded reply
     * window so a separately delivered trailer cannot escape validation. */
    while (received <= CONTROLLER_REPLY_SIZE + 2) {
        if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return false;
        int64_t remaining = deadline - ((int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000);
        if (remaining <= 0) break;
        struct pollfd port = { .fd = fd, .events = POLLIN };
        int ready = poll(&port, 1, (int)remaining);
        if (ready < 0 && errno == EINTR) continue;
        if (ready == 0) break;
        if (ready < 0 || !(port.revents & POLLIN)) return false;
        ssize_t count = read(fd, reply + received, sizeof(reply) - received);
        if (count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        if (count <= 0) return false;
        received += (size_t)count;
    }
    return controller_reply_is_compatible(reply, received);
}

#endif
