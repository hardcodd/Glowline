#pragma once
#include "settings.h"
#include <map>
#include <sstream>
#include <stdexcept>

namespace glowline {
// Use the same Russian copy as the Mac interface. Only platform-specific
// instructions differ; the resource stays usable without a repository checkout.
inline std::wstring tr(wchar_t const *key) {
    static const auto strings = [] {
        std::map<std::wstring, std::wstring> result;
        auto resource = FindResourceW(nullptr, MAKEINTRESOURCEW(2), RT_RCDATA);
        auto loaded = LoadResource(nullptr, resource);
        auto bytes = static_cast<char const *>(LockResource(loaded));
        auto size = SizeofResource(nullptr, resource);
        if (!bytes || !size)
            throw std::runtime_error("Russian interface resource is missing");
        std::istringstream lines(std::string(bytes, size));
        std::string line;
        while (std::getline(lines, line)) {
            auto separator = line.find(" = ");
            auto end = line.rfind(';');
            if (separator == std::string::npos || end == std::string::npos)
                continue;
            auto name = JsonValue::Parse(winrt::to_hstring(line.substr(0, separator))).GetString();
            auto value =
                JsonValue::Parse(winrt::to_hstring(line.substr(separator + 3, end - separator - 3)))
                    .GetString();
            result.emplace(std::wstring(name), std::wstring(value));
        }
        result[L"window.hide"] = L"Свернуть в трей";
        result[L"control.login"] = L"Запускать при входе в Windows";
        result[L"control.hidden"] = L"При входе запускать свёрнутым в трей";
        result[L"theme.system"] = L"Как в Windows";
        result[L"app.closeHelp"] =
            L"Закрытие окна оставляет свет и значок в трее. Полный выход — через меню Glowline.";
        result[L"schedule.help"] =
            L"Каждый день по местному времени Windows. Работает, пока Glowline запущен, в том "
            L"числе в трее. После сна выбирается текущий период.";
        result[L"diagnostics.logs"] = L"Открыть диагностику";
        result[L"windows.login.on"] =
            L"Включён запуск при входе для текущего пользователя Windows.";
        result[L"windows.login.off"] = L"Автоматический запуск при входе выключен.";
        result[L"windows.login.settings"] = L"Настройки автозагрузки Windows";
        return result;
    }();
    auto found = strings.find(key);
    if (found == strings.end())
        throw std::runtime_error("Missing interface translation");
    return found->second;
}
inline std::wstring field_title(Field const &field) {
    static const std::map<std::wstring, const wchar_t *> keys = {
        {L"topEnabled", L"side.top"},
        {L"leftEnabled", L"side.left"},
        {L"rightEnabled", L"side.right"},
        {L"bottomEnabled", L"side.bottom"},
        {L"brightness", L"control.brightness"},
        {L"warmth", L"control.warmth"},
        {L"saturation", L"control.saturation"},
        {L"gamma", L"control.gamma"},
        {L"redGain", L"control.red"},
        {L"greenGain", L"control.green"},
        {L"blueGain", L"control.blue"},
        {L"blackThreshold", L"control.black"},
        {L"edgeDepth", L"control.depth"},
        {L"detailMode", L"control.detailMode"},
        {L"releaseSeconds", L"control.release"},
        {L"attackSeconds", L"control.attack"},
        {L"mirrored", L"control.mirror"},
        {L"offset", L"control.offset"},
        {L"fps", L"control.fps"},
        {L"captureFps", L"control.captureRate"},
        {L"keepaliveSeconds", L"control.heartbeat"},
        {L"skipUnchanged", L"control.dedup"},
        {L"speed", L"control.speed"},
        {L"reverse", L"control.reverse"},
        {L"launchAtLogin", L"control.login"},
        {L"startHidden", L"control.hidden"},
        {L"reconnect", L"control.reconnect"},
        {L"offOnQuit", L"control.offQuit"},
        {L"enabled", L"schedule.enabled"},
        {L"dayStart", L"schedule.dayStart"},
        {L"nightStart", L"schedule.nightStart"},
        {L"dayBrightness", L"schedule.dayBrightness"},
        {L"nightBrightness", L"schedule.nightBrightness"},
        {L"gradientBalance", L"effects.gradientBalance"},
        {L"breathingFloor", L"effects.breathingFloor"},
        {L"rainbowCycles", L"effects.rainbowCycles"},
        {L"candleFlicker", L"effects.candleFlicker"},
        {L"flameHeight", L"effects.flameHeight"},
        {L"cometTail", L"effects.cometTail"},
        {L"auroraPink", L"effects.auroraPink"}};
    auto found = keys.find(field.key);
    return found == keys.end() ? std::wstring(field.label) : tr(found->second);
}
} // namespace glowline
