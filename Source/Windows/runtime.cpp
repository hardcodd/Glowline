#include "runtime.h"
#include "capture.h"
#include "serial.h"
#include "recovery.h"
#include <chrono>
#include <memory>
#include <algorithm>

namespace glowline {
static double seconds() {
    return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch())
        .count();
}
static bool desktop_available() {
    HDESK desktop = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
    if (!desktop)
        return false;
    wchar_t name[256]{};
    DWORD needed = 0;
    bool available = GetUserObjectInformationW(desktop, UOI_NAME, name, sizeof(name), &needed) &&
                     _wcsicmp(name, L"Default") == 0;
    CloseDesktop(desktop);
    return available;
}
static std::wstring error_text() {
    try {
        throw;
    } catch (winrt::hresult_error const &e) {
        return std::wstring(e.message());
    } catch (std::exception const &e) {
        return std::wstring(winrt::to_hstring(e.what()));
    }
}
Runtime::Runtime(JsonObject const &s) {
    settings_ = winrt::to_string(s.Stringify());
    worker_ = std::thread([this] {
        try {
            run();
        } catch (...) {
            auto error = error_text();
            std::lock_guard lock(mutex_);
            status_.serial_error = error;
            status_.capture_error = error;
            status_.connected = false;
            status_.capture_ready = false;
            status_.packet.fill(0);
        }
    });
}
Runtime::~Runtime() {
    stop_ = true;
    if (worker_.joinable())
        worker_.join();
}
void Runtime::update(JsonObject const &s) {
    std::lock_guard lock(mutex_);
    settings_ = winrt::to_string(s.Stringify());
}
Status Runtime::status() {
    std::lock_guard lock(mutex_);
    return status_;
}
void Runtime::run() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    std::unique_ptr<GLPipeline, decltype(&gl_destroy)> pipeline(gl_create(), gl_destroy);
    if (!pipeline)
        throw std::bad_alloc();
    std::unique_ptr<Serial> serial;
    std::unique_ptr<Capture> capture;
    JsonObject s = normalize_settings(JsonObject{});
    std::string loaded;
    std::wstring selected_port, selected_display;
    unsigned retry = retry_;
    RecoveryBudget serial_recovery, capture_recovery;
    double started = seconds(), last_send = 0, last_capture = 0, next_output = 0, window = started;
    uint64_t window_sent = 0;
    bool previous_valid = false;
    std::array<uint8_t, 342> previous{};
    int previous_mode = -1;
    Status state;
    bool desktop = true;
    double desktop_check = 0;
    while (!stop_) {
        double begin = seconds();
        if (begin - desktop_check >= .25) {
            desktop = desktop_available();
            desktop_check = begin;
        }
        std::string incoming;
        {
            std::lock_guard lock(mutex_);
            incoming = settings_;
        }
        if (incoming != loaded) {
            s = JsonObject::Parse(winrt::to_hstring(incoming));
            loaded = incoming;
        }
        unsigned requested_retry = retry_.load();
        bool reset = retry != requested_retry;
        retry = requested_retry;
        auto port = string(s, L"port"), display = string(s, L"windowsDisplay");
        int mode = static_cast<int>(number(s, L"mode"));
        if (mode != previous_mode) {
            capture.reset();
            capture_recovery.reset();
            previous_mode = mode;
        }
        if (reset || port != selected_port || suspended_) {
            if (serial) {
                try {
                    serial->black();
                } catch (...) {
                    state.serial_error = error_text();
                }
            }
            serial.reset();
            selected_port = port;
            state.serial_error.clear();
            serial_recovery.reset();
            previous_valid = false;
        }
        if (number(s, L"mode") != 0)
            state.capture_error.clear();
        if (reset || display != selected_display || suspended_ || !desktop ||
            (number(s, L"mode") != 0 && capture)) {
            capture.reset();
            selected_display = display;
            state.capture_error.clear();
            capture_recovery.reset();
        }
        if (!suspended_ && desktop) {
            if (!serial && !port.empty() &&
                serial_recovery.ready(begin, boolean(s, L"reconnect"))) {
                try {
                    serial = std::make_unique<Serial>(port);
                    state.serial_error.clear();
                } catch (...) {
                    state.serial_error = error_text();
                    serial_recovery.failed(seconds());
                }
            }
            if (number(s, L"mode") == 0 && !capture && capture_recovery.ready(begin)) {
                try {
                    capture = std::make_unique<Capture>(display);
                    state.capture_error.clear();
                } catch (...) {
                    state.capture_error = error_text();
                    capture_recovery.failed(seconds());
                }
            }
            if (capture && begin - last_capture >= 1 / number(s, L"captureFps")) {
                try {
                    capture->poll();
                    last_capture = begin;
                } catch (...) {
                    state.capture_error = error_text();
                    capture.reset();
                    capture_recovery.failed(seconds());
                }
            }
        }
        if (seconds() >= next_output) {
            double output_started = seconds();
            SYSTEMTIME local;
            GetLocalTime(&local);
            auto controls = engine_controls(s, local.wHour * 60 + local.wMinute);
            if (suspended_ || !desktop)
                controls.enabled = 0;
            gl_render(pipeline.get(), &controls, capture ? capture->pixels.data() : nullptr,
                      capture ? capture->width : 0, capture ? capture->height : 0,
                      capture ? capture->stride : 0, capture && capture->ready, seconds(),
                      seconds() - started, state.packet.data());
            state.brightness = controls.brightness;
            if (serial && (!boolean(s, L"skipUnchanged") ||
                           gl_should_send(previous_valid, previous.data(), state.packet.data(),
                                          seconds() - last_send, number(s, L"keepaliveSeconds")))) {
                try {
                    auto write_started = seconds();
                    serial->write(state.packet.data(), state.packet.size());
                    state.write_ms = (seconds() - write_started) * 1000;
                    previous = state.packet;
                    previous_valid = true;
                    last_send = seconds();
                    state.sent++;
                    window_sent++;
                } catch (...) {
                    state.serial_error = error_text();
                    serial.reset();
                    previous_valid = false;
                    serial_recovery.failed(seconds());
                }
            }
            // Serial writes may consume one wire frame; do not add another full
            // interval after transmission or the requested rate would be halved.
            next_output = output_started + 1 / number(s, L"fps");
        }
        state.connected = bool(serial);
        state.capture_ready = capture && capture->ready;
        if (capture)
            state.captured = capture->frames;
        if (serial)
            serial_recovery.healthy(seconds());
        if (state.capture_ready)
            capture_recovery.healthy(seconds());
        if (seconds() - window >= 1) {
            state.fps = window_sent / (seconds() - window);
            window_sent = 0;
            window = seconds();
        }
        {
            std::lock_guard lock(mutex_);
            status_ = state;
        }
        double poll_interval = capture ? 1 / number(s, L"captureFps") : 1 / number(s, L"fps");
        double wait = std::min(poll_interval, std::max(0., next_output - seconds()));
        if (wait > 0)
            std::this_thread::sleep_for(std::chrono::duration<double>(wait));
    }
    if (serial && boolean(s, L"offOnQuit")) {
        try {
            serial->black();
        } catch (...) {
            std::lock_guard lock(mutex_);
            status_.serial_error = error_text();
        }
    }
}
} // namespace glowline
