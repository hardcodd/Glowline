#include "../Source/Windows/settings.h"
#include "../Source/Windows/capture.h"
#include "../Source/Windows/recovery.h"
#include "../Source/Windows/appearance.h"
#include "../Source/Windows/slider_scale.h"
#include <array>
#include <stdexcept>
#include <cmath>

namespace glowline {
static void require(bool value, char const *message) {
    if (!value)
        throw std::runtime_error(message);
}
// Render independently of a desktop/USB device so CI catches missing edges and zero-depth seams.
static void depth_preview_contract() {
    for (bool dark : {false, true}) {
        visual::Palette palette(dark);
        for (float depth : {0.f, .15f, .35f}) {
            Gdiplus::Bitmap bitmap(400, 200, PixelFormat32bppARGB);
            Gdiplus::Graphics target(&bitmap);
            auto dc = target.GetHDC();
            {
                visual::Canvas canvas(dc, 1);
                canvas.fill({0, 0, 400, 200}, palette.canvas);
                canvas.depth_preview({10, 10, 380, 180}, depth, palette, L"");
            }
            target.ReleaseHDC(dc);
            auto red = [&](int x, int y) {
                visual::Color color;
                require(bitmap.GetPixel(x, y, &color) == Gdiplus::Ok,
                        "Cannot read depth preview pixel");
                return static_cast<int>(color.GetR());
            };
            require(red(200, 100) == palette.tile.GetR(), "Depth preview center is not neutral");
            if (depth == 0) {
                for (auto point :
                     {POINT{200, 20}, POINT{200, 179}, POINT{20, 100}, POINT{379, 100}})
                    require(red(point.x, point.y) == palette.tile.GetR(),
                            "Zero depth still shows influence");
            } else {
                for (auto point :
                     {POINT{200, 20}, POINT{200, 179}, POINT{20, 100}, POINT{379, 100}})
                    require(std::abs(red(point.x, point.y) - palette.tile.GetR()) > 10,
                            "Depth preview is missing an edge");
                require(std::abs(red(200, 20) - red(200, 179)) <= 4,
                        "Top/bottom depth fades differ");
                require(std::abs(red(20, 100) - red(379, 100)) <= 4,
                        "Left/right depth fades differ");
                require((red(200, 50) != palette.tile.GetR()) == (depth > .15f),
                        "Depth preview does not follow the setting");
            }
            require(red(10, 10) == palette.canvas.GetR(), "Depth preview escapes rounded clipping");
        }
    }
}
void run_windows_tests() {
    depth_preview_contract();
    for (auto const *fields : {&setting_fields(), &effect_fields()})
        for (auto const &field : *fields) {
            if (field.type != FieldType::Number && field.type != FieldType::Integer)
                continue;
            if (std::wstring(field.key) == L"displayID")
                continue;
            SliderScale scale(field);
            require(scale.value(0) == field.minimum && scale.value(scale.last()) == field.maximum,
                    "Slider endpoints drifted");
            for (int i = 1; i <= scale.last(); i++) {
                require(scale.value(i) > scale.value(i - 1), "Slider has a dead keyboard step");
                require(scale.index(scale.value(i)) == i, "Slider tick round trip failed");
            }
        }
    RecoveryBudget recovery;
    require(recovery.ready(0), "Initial recovery attempt missing");
    recovery.failed(0);
    require(!recovery.ready(4.99) && recovery.ready(5), "First recovery deadline");
    recovery.failed(5);
    require(!recovery.ready(14.99) && recovery.ready(15), "Second recovery deadline");
    recovery.failed(15);
    require(!recovery.ready(34.99) && recovery.ready(35), "Third recovery deadline");
    recovery.failed(35);
    require(!recovery.ready(1000), "Recovery budget not bounded");
    recovery.healthy(1000);
    recovery.healthy(1009);
    require(!recovery.ready(1009), "Recovery replenished too soon");
    recovery.healthy(1010);
    require(recovery.ready(1010), "Healthy recovery budget did not replenish");
    auto s = normalize_settings(JsonObject{});
    auto c = engine_controls(s, 480);
    require(c.enabled && c.mode == 0 && c.primary[0] == 255 && c.primary[1] == 160 &&
                c.primary[2] == 64,
            "Defaults drifted");
    require(c.brightness == 1 && c.warmth == .5 && c.release_seconds == .18,
            "Engine defaults drifted");
    auto schedule = s.GetNamedObject(L"brightnessSchedule");
    put(schedule, L"enabled", true);
    require(engine_controls(s, 479).brightness == .5, "Night boundary");
    require(engine_controls(s, 480).brightness == 1, "Day boundary");
    require(engine_controls(s, 1320).brightness == .5, "Night start");
    put(schedule, L"dayStart", 1320.);
    put(schedule, L"nightStart", 480.);
    require(engine_controls(s, 0).brightness == 1 && engine_controls(s, 480).brightness == .5,
            "Midnight wrap");
    put(schedule, L"dayStart", 480.);
    put(s, L"brightness", .37);
    require(engine_controls(s, 900).brightness == .37,
            "Equal schedule starts must use manual brightness");
    auto effects = s.GetNamedObject(L"effectSettings");
    for (int mode = 0; mode < 9; mode++) {
        put(s, L"mode", static_cast<double>(mode));
        auto effect = active_effect(s);
        put(effect, L"speed", .4 * (mode + 1));
        effects.Insert(std::to_wstring(mode), effect);
    }
    auto state = default_state();
    state.Insert(L"settings", s);
    auto restored = decode_state(winrt::to_string(state.Stringify())).GetNamedObject(L"settings");
    for (int mode = 0; mode < 9; mode++) {
        put(restored, L"mode", static_cast<double>(mode));
        require(std::abs(engine_controls(restored, 0).speed - .4 * (mode + 1)) < 1e-8,
                "Effects not independent after persistence");
    }
    for (auto const *invalid : {L"{\"warmth\":null}", L"{\"enabled\":1}", L"{\"mode\":0.5}",
                                L"{\"effectSettings\":{\"7\":{\"speed\":\"bad\"}}}"}) {
        bool rejected = false;
        try {
            normalize_settings(JsonObject::Parse(invalid));
        } catch (...) {
            rejected = true;
        }
        require(rejected, "Invalid settings type accepted");
    }
    bool future_rejected = false;
    try {
        decode_state("{\"schemaVersion\":2,\"settings\":{},\"profiles\":[]}");
    } catch (...) {
        future_rejected = true;
    }
    require(future_rejected, "Future schema accepted");
    auto imported = normalize_settings(
        JsonObject::Parse(L"{\"port\":\"/dev/cu.usbserial-test\",\"mode\":99,\"gamma\":99}"));
    require(string(imported, L"port").empty() && number(imported, L"mode") == 8 &&
                number(imported, L"gamma") == 2.5,
            "Import validation");
    for (auto const *port : {L"COM1", L"COM12", L"COM4096"}) {
        JsonObject j;
        put(j, L"port", std::wstring(port));
        require(string(normalize_settings(j), L"port") == port, "Valid Windows port rejected");
    }
    std::array<uint8_t, 16> reply{'S', 'K', '0', 'L', '3', '4', ',',  0,
                                  1,   2,   3,   4,   5,   6,   '\r', '\n'};
    require(gl_controller_reply(reply.data(), 14) && gl_controller_reply(reply.data(), 16),
            "Identity suffix handling");
    reply[15] = 'x';
    require(!gl_controller_reply(reply.data(), 16) && !gl_controller_reply(reply.data(), 13),
            "Malformed identity accepted");
    auto pipeline = gl_create();
    require(pipeline != nullptr, "Pipeline allocation");
    c = engine_controls(normalize_settings(JsonObject{}), 0);
    c.mode = 1;
    c.warmth = 0;
    c.release_seconds = 0;
    std::array<uint8_t, 342> packet{}, previous{};
    gl_render(pipeline, &c, nullptr, 0, 0, 0, 0, 0, 0, packet.data());
    require(packet[0] == 'A' && packet[1] == 'd' && packet[2] == 'a' && packet[5] == 0x70,
            "Packet header");
    for (int i = 0; i < 112; i++)
        require(packet[6 + i * 3] == 255 && packet[7 + i * 3] == 160 && packet[8 + i * 3] == 64,
                "Solid output mismatch");
    previous = packet;
    require(!gl_should_send(1, previous.data(), packet.data(), .01, .1) &&
                gl_should_send(1, previous.data(), packet.data(), .1, .1),
            "Heartbeat contract");
    c.mode = 0;
    gl_render(pipeline, &c, nullptr, 0, 0, 0, 0, 1, 1, packet.data());
    for (size_t i = 6; i < packet.size(); i++)
        require(packet[i] == 0, "Failed capture retained stale color");
    for (int mode = 1; mode < 9; mode++) {
        c.mode = mode;
        gl_render(pipeline, &c, nullptr, 0, 0, 0, 0, mode, mode, packet.data());
        unsigned sum = 0;
        for (size_t i = 6; i < packet.size(); i++)
            sum += packet[i];
        require(sum > 0, "Effect rendered black");
    }
    c.enabled = 0;
    gl_render(pipeline, &c, nullptr, 0, 0, 0, 0, 20, 20, packet.data());
    for (size_t i = 6; i < packet.size(); i++)
        require(packet[i] == 0, "Disabled strip not black");
    gl_destroy(pipeline);
}

/* Interactive-session integration check. The test owns a temporary fullscreen
 * color surface; no controller or saved preferences are touched. */
void run_capture_test() {
    WNDCLASSW cls{};
    cls.lpfnWndProc = [](HWND window, UINT message, WPARAM w, LPARAM l) -> LRESULT {
        if (message == WM_PAINT) {
            PAINTSTRUCT paint;
            HDC dc = BeginPaint(window, &paint);
            RECT area;
            GetClientRect(window, &area);
            auto blue = GetWindowLongPtrW(window, GWLP_USERDATA) == 2;
            HBRUSH brush = CreateSolidBrush(blue ? RGB(0, 0, 255) : RGB(255, 0, 0));
            FillRect(dc, &area, brush);
            DeleteObject(brush);
            EndPaint(window, &paint);
            return 0;
        }
        return DefWindowProcW(window, message, w, l);
    };
    cls.hInstance = GetModuleHandleW(nullptr);
    cls.lpszClassName = L"GlowlineCaptureContract";
    RegisterClassW(&cls);
    MONITORINFO monitor{};
    monitor.cbSize = sizeof(monitor);
    require(GetMonitorInfoW(MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY), &monitor),
            "No primary display");
    auto rect = monitor.rcMonitor;
    HWND window =
        CreateWindowExW(WS_EX_TOPMOST, cls.lpszClassName, L"Glowline capture contract",
                        WS_POPUP | WS_VISIBLE, rect.left, rect.top, rect.right - rect.left,
                        rect.bottom - rect.top, nullptr, nullptr, cls.hInstance, nullptr);
    require(window != nullptr, "Cannot create capture test surface");
    auto pipeline = gl_create();
    try {
        Capture capture(L"");
        auto s = normalize_settings(JsonObject{});
        put(s, L"warmth", 0.);
        put(s, L"releaseSeconds", 0.);
        auto controls = engine_controls(s, 0);
        std::array<uint8_t, 342> packet{};
        for (int component : {0, 2}) {
            SetWindowLongPtrW(window, GWLP_USERDATA, component);
            RedrawWindow(window, nullptr, nullptr, RDW_INVALIDATE | RDW_UPDATENOW | RDW_ERASE);
            GdiFlush();
            auto deadline = GetTickCount64() + 15000;
            bool matched = false;
            while (GetTickCount64() < deadline) {
                MSG message;
                while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
                    TranslateMessage(&message);
                    DispatchMessageW(&message);
                }
                if (capture.poll()) {
                    gl_render(pipeline, &controls, capture.pixels.data(), capture.width,
                              capture.height, capture.stride, capture.ready,
                              GetTickCount64() / 1000., 0, packet.data());
                    matched = true;
                    for (int i = 0; i < 112; i++) {
                        auto rgb = packet.data() + 6 + i * 3;
                        if (rgb[component] < 240 || rgb[1] > 35 || rgb[2 - component] > 35)
                            matched = false;
                    }
                    if (matched)
                        break;
                }
                Sleep(8);
            }
            if (!matched) {
                throw std::runtime_error(
                    std::string(component == 0 ? "Red" : "Blue") + " capture mismatch: frames=" +
                    std::to_string(capture.frames) + " size=" + std::to_string(capture.width) +
                    "x" + std::to_string(capture.height) + " raw16=" +
                    std::to_string(*reinterpret_cast<uint16_t *>(
                        capture.pixels.data() + capture.stride * (capture.height / 2) +
                        8 * (capture.width / 2))) +
                    " first RGB=" + std::to_string(packet[6]) + "/" + std::to_string(packet[7]) +
                    "/" + std::to_string(packet[8]));
            }
        }
        require(capture.width == 344 && capture.ready && capture.frames >= 2,
                "Capture dimensions or delivery invalid");
    } catch (...) {
        gl_destroy(pipeline);
        DestroyWindow(window);
        throw;
    }
    gl_destroy(pipeline);
    DestroyWindow(window);
}
} // namespace glowline
