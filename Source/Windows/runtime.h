#pragma once
#include "settings.h"
#include <array>
#include <mutex>
#include <thread>
#include <atomic>

namespace glowline {
struct Status {
    std::array<uint8_t, 342> packet{};
    bool connected = false, capture_ready = false;
    uint64_t sent = 0, captured = 0;
    double fps = 0, write_ms = 0, brightness = 1;
    std::wstring serial_error, capture_error;
};
// The MTA worker owns capture, serial and pipeline state. JSON strings cross the
// apartment boundary; UI calls publish snapshots and read mutex-protected status.
class Runtime {
    std::mutex mutex_;
    std::string settings_;
    Status status_;
    std::atomic<bool> stop_{false}, suspended_{false};
    std::atomic<unsigned> retry_{0};
    std::thread worker_;
    void run();

  public:
    explicit Runtime(JsonObject const &);
    ~Runtime();
    void update(JsonObject const &);
    Status status();
    void suspend(bool value) {
        suspended_ = value;
        retry_++;
    }
    void retry() { retry_++; }
};
} // namespace glowline
