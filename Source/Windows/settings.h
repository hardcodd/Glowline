#pragma once
#include "core.h"
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Data.Json.h>
#include <filesystem>
#include <vector>
#include <string>

namespace glowline {
using winrt::Windows::Data::Json::JsonArray;
using winrt::Windows::Data::Json::JsonObject;
using winrt::Windows::Data::Json::JsonValue;
using winrt::Windows::Data::Json::JsonValueType;

enum class FieldType { Number, Integer, Boolean, Text };
struct Field {
    const wchar_t *key, *label;
    FieldType type;
    double initial = 0, minimum = 0, maximum = 0;
    const wchar_t *text = L"";
};
const std::vector<Field> &setting_fields();
const std::vector<Field> &schedule_fields();
const std::vector<Field> &effect_fields();
double number(const JsonObject &, const wchar_t *);
bool boolean(const JsonObject &, const wchar_t *);
std::wstring string(const JsonObject &, const wchar_t *);
void put(JsonObject const &, const wchar_t *, double);
void put(JsonObject const &, const wchar_t *, bool);
void put(JsonObject const &, const wchar_t *, std::wstring const &);
JsonObject copy(JsonObject const &);
// Fill schema-1 defaults, reject invalid types, clamp numeric ranges and clear non-COM ports.
// Imported settings are independent copies; windowsDisplay is separate from macOS displayID.
JsonObject normalize_settings(JsonObject const &);
JsonObject active_effect(JsonObject const &);
// Resolve the current mode and local-time brightness schedule into a portable engine snapshot.
GLControls engine_controls(JsonObject const &, int local_minute);
JsonObject decode_state(std::string const &utf8);
JsonObject default_state();
std::string read_text(std::filesystem::path const &);
// Atomically replace UTF-8 content through a sibling temporary file; failures throw.
void write_text(std::filesystem::path const &, std::string const &);
std::filesystem::path state_path();
} // namespace glowline
