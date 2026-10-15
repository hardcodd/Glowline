#include "controller_protocol.h"
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <sys/socket.h>

typedef struct {
    int fd;
    const uint8_t *reply;
    size_t length;
    size_t split;
} FakeController;

static void *respond(void *context) {
    FakeController *controller = context;
    char query[6];
    size_t received = 0;
    while (received < sizeof(query)) {
        ssize_t count = read(controller->fd, query + received, sizeof(query) - received);
        assert(count > 0);
        received += (size_t)count;
    }
    assert(memcmp(query, "Moni-A", sizeof(query)) == 0);
    if (controller->split > 0) {
        assert(write(controller->fd, controller->reply, controller->split) == (ssize_t)controller->split);
        usleep(5000);
    }
    size_t remaining = controller->length - controller->split;
    if (remaining > 0) {
        assert(write(controller->fd, controller->reply + controller->split, remaining) == (ssize_t)remaining);
    }
    return NULL;
}

static void check_query(const uint8_t *reply, size_t length, size_t split, bool expected) {
    int descriptors[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, descriptors) == 0);
    FakeController controller = {descriptors[1], reply, length, split};
    pthread_t thread;
    assert(pthread_create(&thread, NULL, respond, &controller) == 0);
    assert(query_compatible_controller(descriptors[0], 60) == expected);
    assert(pthread_join(thread, NULL) == 0);
    /* The handshake must never send a lighting frame, even on rejection. */
    uint8_t extra;
    assert(recv(descriptors[1], &extra, 1, MSG_DONTWAIT) == -1);
    assert(errno == EAGAIN || errno == EWOULDBLOCK);
    close(descriptors[0]);
    close(descriptors[1]);
}

int main(void) {
    const uint8_t first[] = {'S','K','0','L','3','4',',',1,2,3,4,5,6,7};
    const uint8_t second[] = {'S','K','0','L','3','4',',',255,0,128,13,10,44,42};
    assert(controller_reply_is_compatible(first, sizeof(first)));
    assert(controller_reply_is_compatible(second, sizeof(second)));
    uint8_t terminated[17];
    memcpy(terminated, first, sizeof(first));
    terminated[14] = '\r';
    terminated[15] = '\n';
    terminated[16] = 0;
    assert(controller_reply_is_compatible(terminated, 16));
    assert(!controller_reply_is_compatible(terminated, 15));
    assert(!controller_reply_is_compatible(terminated, 17));
    terminated[15] = 'X';
    assert(!controller_reply_is_compatible(terminated, 16));
    terminated[15] = '\n';
    assert(!controller_reply_is_compatible(NULL, 0));
    for (size_t length = 0; length < sizeof(first); length++) {
        assert(!controller_reply_is_compatible(first, length));
    }
    uint8_t malformed[15];
    memcpy(malformed, first, sizeof(first));
    malformed[14] = 0;
    assert(!controller_reply_is_compatible(malformed, sizeof(malformed)));
    for (size_t index = 0; index < 7; index++) {
        memcpy(malformed, first, sizeof(first));
        malformed[index] ^= 1;
        assert(!controller_reply_is_compatible(malformed, sizeof(first)));
    }
    for (size_t split = 0; split < sizeof(first); split++) {
        check_query(first, sizeof(first), split, true);
    }
    check_query(second, sizeof(second), 6, true);
    for (size_t split = 0; split < 16; split++) {
        check_query(terminated, 16, split, true);
    }
    check_query(terminated, 15, 7, false);
    terminated[15] = 'X';
    check_query(terminated, 16, 15, false);
    terminated[15] = '\n';
    check_query(first, 7, 3, false);
    check_query(first, 0, 0, false);
    malformed[0] = 'X';
    check_query(malformed, 14, 0, false);
    memcpy(malformed, first, sizeof(first));
    check_query(malformed, 15, 0, false);
    puts("controller compatibility and fragmented handshake contracts passed");
    return 0;
}
