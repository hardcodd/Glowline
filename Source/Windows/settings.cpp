#include "settings.h"
#include "strings.h"
#include <windows.h>
#include <shlobj.h>
#include <algorithm>
#include <cmath>
#include <fstream>
#include <stdexcept>

// Win32 GDI aliases this name; the JSON API uses the original spelling.
#undef GetObject

namespace glowline {
using T = FieldType;
const std::vector<Field> &setting_fields() {
    static const std::vector<Field> fields = {
        {L"enabled", ui::field_enabled, T::Boolean, 1},
        {L"mode", ui::field_mode, T::Integer, 0, 0, 8},
        {L"brightness", ui::field_brightness, T::Number, 1, 0, 1},
        {L"warmth", ui::field_warmth, T::Number, .5, 0, .9},
        {L"saturation", ui::field_saturation, T::Number, 1, 0, 2},
        {L"gamma", ui::field_gamma, T::Number, 1, .5, 2.5},
        {L"redGain", ui::field_redGain, T::Number, 1, 0, 2},
        {L"greenGain", ui::field_greenGain, T::Number, 1, 0, 2},
        {L"blueGain", ui::field_blueGain, T::Number, 1, 0, 2},
        {L"blackThreshold", ui::field_blackThreshold, T::Number, 0, 0, .2},
        {L"edgeDepth", ui::field_edgeDepth, T::Number, .15, 0, .35},
        {L"detailMode", ui::field_detailMode, T::Boolean},
        {L"releaseSeconds", ui::field_releaseSeconds, T::Number, .18, 0, 1},
        {L"attackSeconds", ui::field_attackSeconds, T::Number, 0, 0, 1},
        {L"mirrored", ui::field_mirrored, T::Boolean, 1},
        {L"offset", ui::field_offset, T::Integer, 0, -111, 111},
        {L"leftEnabled", ui::field_leftEnabled, T::Boolean, 1},
        {L"topEnabled", ui::field_topEnabled, T::Boolean, 1},
        {L"rightEnabled", ui::field_rightEnabled, T::Boolean, 1},
        {L"bottomEnabled", ui::field_bottomEnabled, T::Boolean, 1},
        {L"leftGain", ui::field_leftGain, T::Number, 1, 0, 2},
        {L"topGain", ui::field_topGain, T::Number, 1, 0, 2},
        {L"rightGain", ui::field_rightGain, T::Number, 1, 0, 2},
        {L"bottomGain", ui::field_bottomGain, T::Number, 1, 0, 2},
        {L"fps", ui::field_fps, T::Number, 33.68, 5, 33.68},
        {L"captureFps", ui::field_captureFps, T::Integer, 120, 30, 240},
        {L"keepaliveSeconds", ui::field_keepaliveSeconds, T::Number, .1, .05, 1},
        {L"skipUnchanged", ui::field_skipUnchanged, T::Boolean, 1},
        {L"speed", ui::field_speed, T::Number, 1, .1, 5},
        {L"reverse", ui::field_reverse, T::Boolean},
        {L"port", ui::field_port, T::Text},
        {L"displayID", ui::field_displayID, T::Integer, 0, 0, 4294967295.},
        {L"windowsDisplay", ui::field_windowsDisplay, T::Text},
        {L"theme", ui::field_theme, T::Text, 0, 0, 0, L"dark"},
        {L"launchAtLogin", ui::field_launchAtLogin, T::Boolean, 1},
        {L"startHidden", ui::field_startHidden, T::Boolean, 1},
        {L"reconnect", ui::field_reconnect, T::Boolean, 1},
        {L"offOnQuit", ui::field_offOnQuit, T::Boolean, 1}};
    return fields;
}
const std::vector<Field> &schedule_fields() {
    static const std::vector<Field> fields = {
        {L"enabled", ui::field_enabled_schedule, T::Boolean},
        {L"dayStart", ui::field_dayStart, T::Integer, 480, 0, 1439},
        {L"nightStart", ui::field_nightStart, T::Integer, 1320, 0, 1439},
        {L"dayBrightness", ui::field_dayBrightness, T::Number, 1, 0, 1},
        {L"nightBrightness", ui::field_nightBrightness, T::Number, .5, 0, 1}};
    return fields;
}
const std::vector<Field> &effect_fields() {
    static const std::vector<Field> fields = {
        {L"speed", ui::field_speed, T::Number, 1, .1, 5},
        {L"reverse", ui::field_reverse, T::Boolean},
        {L"gradientBalance", ui::field_gradientBalance, T::Number, .5, .1, .9},
        {L"breathingFloor", ui::field_breathingFloor, T::Number, .15, 0, .8},
        {L"rainbowCycles", ui::field_rainbowCycles, T::Number, 1, .5, 3},
        {L"candleFlicker", ui::field_candleFlicker, T::Number, 1, 0, 1},
        {L"flameHeight", ui::field_flameHeight, T::Number, 1, .3, 2},
        {L"cometTail", ui::field_cometTail, T::Number, 1, .3, 2},
        {L"auroraPink", ui::field_auroraPink, T::Number, 1, 0, 2}};
    return fields;
}
double number(JsonObject const &j, const wchar_t *k) { return j.GetNamedNumber(k); }
bool boolean(JsonObject const &j, const wchar_t *k) { return j.GetNamedBoolean(k); }
std::wstring string(JsonObject const &j, const wchar_t *k) {
    return std::wstring(j.GetNamedString(k));
}
void put(JsonObject const &j, const wchar_t *k, double v) {
    j.Insert(k, JsonValue::CreateNumberValue(v));
}
void put(JsonObject const &j, const wchar_t *k, bool v) {
    j.Insert(k, JsonValue::CreateBooleanValue(v));
}
void put(JsonObject const &j, const wchar_t *k, std::wstring const &v) {
    j.Insert(k, JsonValue::CreateStringValue(v));
}
JsonObject copy(JsonObject const &j) { return JsonObject::Parse(j.Stringify()); }

static JsonObject normalize_fields(JsonObject const &src, std::vector<Field> const &fields) {
    JsonObject result;
    for (auto const &f : fields) {
        auto v = src.HasKey(f.key) ? src.Lookup(f.key) : nullptr;
        if (f.type == T::Boolean)
            put(result, f.key, v ? v.GetBoolean() : f.initial != 0);
        else if (f.type == T::Text)
            put(result, f.key, v ? std::wstring(v.GetString()) : std::wstring(f.text));
        else {
            double x = v ? v.GetNumber() : f.initial;
            if (!std::isfinite(x) || (f.type == T::Integer && std::floor(x) != x))
                throw std::runtime_error("Invalid numeric setting");
            put(result, f.key, std::clamp(x, f.minimum, f.maximum));
        }
    }
    return result;
}
static JsonObject normalize_color(JsonObject const &src, bool secondary, bool present) {
    JsonObject j;
    const wchar_t *keys[] = {L"red", L"green", L"blue"};
    const double defaults[2][3] = {{1, 160. / 255, 64. / 255}, {72. / 255, 96. / 255, 1}};
    for (int i = 0; i < 3; i++) {
        double x = present ? src.GetNamedNumber(keys[i]) : defaults[secondary][i];
        if (!std::isfinite(x))
            throw std::runtime_error("Invalid color");
        put(j, keys[i], std::clamp(x, 0., 1.));
    }
    return j;
}
static void add_colors(JsonObject const &src, JsonObject const &dst) {
    for (auto key : {L"primary", L"secondary"})
        dst.Insert(key, normalize_color(src.HasKey(key) ? src.GetNamedObject(key) : JsonObject{},
                                        std::wstring(key) == L"secondary", src.HasKey(key)));
}
JsonObject normalize_settings(JsonObject const &src) {
    auto result = normalize_fields(src, setting_fields());
    add_colors(src, result);
    result.Insert(L"brightnessSchedule",
                  normalize_fields(src.HasKey(L"brightnessSchedule")
                                       ? src.GetNamedObject(L"brightnessSchedule")
                                       : JsonObject{},
                                   schedule_fields()));
    JsonObject effects;
    if (src.HasKey(L"effectSettings")) {
        for (auto const &entry : src.GetNamedObject(L"effectSettings")) {
            auto effect = normalize_fields(entry.Value().GetObject(), effect_fields());
            add_colors(entry.Value().GetObject(), effect);
            auto key = std::wstring(entry.Key());
            if (key.size() == 1 && key[0] >= L'0' && key[0] <= L'8')
                effects.Insert(key, effect);
        }
    }
    result.Insert(L"effectSettings", effects);
    auto theme = string(result, L"theme");
    if (theme != L"dark" && theme != L"light" && theme != L"system")
        put(result, L"theme", std::wstring(L"dark"));
    auto port = string(result, L"port");
    if (!port.empty()) {
        bool valid = port.size() > 3 && port.size() <= 8 && port.substr(0, 3) == L"COM";
        for (size_t i = 3; i < port.size(); i++)
            valid = valid && port[i] >= L'0' && port[i] <= L'9';
        if (!valid || port[3] == L'0')
            put(result, L"port", std::wstring{});
    }
    return result;
}
JsonObject active_effect(JsonObject const &s) {
    auto key = std::to_wstring(static_cast<int>(number(s, L"mode")));
    auto effects = s.GetNamedObject(L"effectSettings");
    if (effects.HasKey(key))
        return copy(effects.GetNamedObject(key));
    auto result = normalize_fields(s, effect_fields());
    result.Insert(L"primary", s.GetNamedObject(L"primary"));
    result.Insert(L"secondary", s.GetNamedObject(L"secondary"));
    return result;
}
GLControls engine_controls(JsonObject const &s, int minute) {
    GLControls c{};
    auto e = active_effect(s);
    c.enabled = boolean(s, L"enabled");
    c.mode = static_cast<int>(number(s, L"mode"));
    c.mirrored = boolean(s, L"mirrored");
    c.offset = static_cast<int>(number(s, L"offset"));
    c.reverse = boolean(e, L"reverse");
    c.brightness = number(s, L"brightness");
    auto schedule = s.GetNamedObject(L"brightnessSchedule");
    int day = static_cast<int>(number(schedule, L"dayStart")),
        night = static_cast<int>(number(schedule, L"nightStart"));
    if (boolean(schedule, L"enabled") && day != night) {
        bool daytime =
            day < night ? (minute >= day && minute < night) : (minute >= day || minute < night);
        c.brightness = number(schedule, daytime ? L"dayBrightness" : L"nightBrightness");
    }
    c.warmth = number(s, L"warmth");
    c.saturation = number(s, L"saturation");
    c.gamma = number(s, L"gamma");
    const wchar_t *gains[] = {L"redGain", L"greenGain", L"blueGain"};
    const wchar_t *sides[] = {L"leftEnabled", L"topEnabled", L"rightEnabled", L"bottomEnabled"};
    const wchar_t *sideg[] = {L"leftGain", L"topGain", L"rightGain", L"bottomGain"};
    for (int i = 0; i < 3; i++)
        c.gain[i] = number(s, gains[i]);
    for (int i = 0; i < 4; i++) {
        c.side_enabled[i] = boolean(s, sides[i]);
        c.side_gain[i] = number(s, sideg[i]);
    }
    c.black_threshold = number(s, L"blackThreshold");
    c.speed = number(e, L"speed");
    c.gradient_balance = number(e, L"gradientBalance");
    c.breathing_floor = number(e, L"breathingFloor");
    c.rainbow_cycles = number(e, L"rainbowCycles");
    c.candle_flicker = number(e, L"candleFlicker");
    c.flame_height = number(e, L"flameHeight");
    c.comet_tail = number(e, L"cometTail");
    c.aurora_pink = number(e, L"auroraPink");
    c.edge_depth = number(s, L"edgeDepth");
    c.detail = boolean(s, L"detailMode");
    c.release_seconds = number(s, L"releaseSeconds");
    c.attack_seconds = number(s, L"attackSeconds");
    for (auto key : {L"primary", L"secondary"}) {
        auto color = e.GetNamedObject(key);
        uint8_t *dst = std::wstring(key) == L"primary" ? c.primary : c.secondary;
        const wchar_t *components[] = {L"red", L"green", L"blue"};
        for (int i = 0; i < 3; i++)
            dst[i] = static_cast<uint8_t>(std::lround(number(color, components[i]) * 255));
    }
    return c;
}
JsonObject default_state() {
    JsonObject state;
    put(state, L"schemaVersion", 1.);
    state.Insert(L"settings", normalize_settings(JsonObject{}));
    state.Insert(L"profiles", JsonArray{});
    return state;
}
JsonObject decode_state(std::string const &utf8) {
    if (utf8.size() >= 1000000)
        throw std::runtime_error("Settings file exceeds 1 MB");
    auto state = JsonObject::Parse(winrt::to_hstring(utf8));
    if (state.GetNamedNumber(L"schemaVersion") != 1)
        throw std::runtime_error("Unsupported settings schema");
    JsonObject result;
    put(result, L"schemaVersion", 1.);
    result.Insert(L"settings", normalize_settings(state.GetNamedObject(L"settings")));
    JsonArray profiles;
    for (auto const &p : state.GetNamedArray(L"profiles")) {
        auto src = p.GetObject();
        JsonObject dst;
        auto id = string(src, L"id");
        GUID parsed{};
        if (FAILED(CLSIDFromString((L"{" + id + L"}").c_str(), &parsed)))
            throw std::runtime_error("Invalid profile identifier");
        put(dst, L"id", id);
        put(dst, L"name", string(src, L"name"));
        dst.Insert(L"settings", normalize_settings(src.GetNamedObject(L"settings")));
        profiles.Append(dst);
    }
    result.Insert(L"profiles", profiles);
    return result;
}
std::string read_text(std::filesystem::path const &path) {
    if (std::filesystem::file_size(path) >= 1000000)
        throw std::runtime_error("Settings file exceeds 1 MB");
    std::ifstream in(path, std::ios::binary);
    if (!in)
        throw std::runtime_error("Cannot open settings");
    std::string text{std::istreambuf_iterator<char>(in), {}};
    if (in.bad())
        throw std::runtime_error("Cannot read settings");
    return text;
}
void write_text(std::filesystem::path const &path, std::string const &text) {
    auto temp = path;
    temp += L".tmp";
    {
        std::ofstream out(temp, std::ios::binary | std::ios::trunc);
        out.write(text.data(), text.size());
        out.flush();
        if (!out)
            throw std::runtime_error("Cannot write settings");
    }
    if (!MoveFileExW(temp.c_str(), path.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
        throw std::runtime_error("Cannot replace settings");
}
std::filesystem::path state_path() {
    PWSTR raw = nullptr;
    winrt::check_hresult(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &raw));
    std::filesystem::path path(raw);
    CoTaskMemFree(raw);
    path /= L"Glowline";
    std::filesystem::create_directories(path);
    return path / L"settings.json";
}
} // namespace glowline
