#include "serial.h"
#include "core.h"
#include <array>
#include <stdexcept>
#include <algorithm>

namespace glowline {
std::vector<std::wstring> serial_ports() {
    std::vector<std::wstring> result;
    HKEY key;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"HARDWARE\\DEVICEMAP\\SERIALCOMM", 0, KEY_QUERY_VALUE,
                      &key) != ERROR_SUCCESS)
        return result;
    for (DWORD index = 0;; index++) {
        wchar_t name[256], value[256];
        DWORD length = 256, size = sizeof(value), type = 0;
        LONG status = RegEnumValueW(key, index, name, &length, nullptr, &type,
                                    reinterpret_cast<BYTE *>(value), &size);
        if (status == ERROR_NO_MORE_ITEMS)
            break;
        if (status == ERROR_SUCCESS && type == REG_SZ && size >= sizeof(wchar_t) &&
            size <= sizeof(value)) {
            value[255] = 0;
            result.emplace_back(value);
        }
    }
    RegCloseKey(key);
    std::sort(result.begin(), result.end());
    return result;
}
Serial::Serial(std::wstring const &name) {
    if (name.size() < 4 || name.size() > 8 || name.substr(0, 3) != L"COM" || name[3] == L'0')
        throw std::runtime_error("Select a COM port");
    for (size_t i = 3; i < name.size(); i++)
        if (name[i] < L'0' || name[i] > L'9')
            throw std::runtime_error("Invalid COM port");
    port_ = CreateFileW((L"\\\\.\\" + name).c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                        OPEN_EXISTING, 0, nullptr);
    if (port_ == INVALID_HANDLE_VALUE)
        throw std::runtime_error("Cannot open selected COM port (busy or disconnected)");
    try {
        original_.DCBlength = sizeof(DCB);
        if (!GetCommState(port_, &original_))
            throw std::runtime_error("Cannot read COM configuration");
        DCB config = original_;
        config.BaudRate = 115200;
        config.ByteSize = 8;
        config.Parity = NOPARITY;
        config.StopBits = ONESTOPBIT;
        config.fBinary = TRUE;
        config.fParity = FALSE;
        config.fOutxCtsFlow = FALSE;
        config.fOutxDsrFlow = FALSE;
        config.fDtrControl = DTR_CONTROL_DISABLE;
        config.fRtsControl = RTS_CONTROL_DISABLE;
        config.fDsrSensitivity = FALSE;
        config.fOutX = FALSE;
        config.fInX = FALSE;
        config.fAbortOnError = FALSE;
        config.fErrorChar = FALSE;
        config.fNull = FALSE;
        COMMTIMEOUTS timeouts{MAXDWORD, 0, 20, 0, 1500};
        if (!SetCommState(port_, &config) || !SetCommTimeouts(port_, &timeouts))
            throw std::runtime_error("Cannot configure COM port");
        if (!EscapeCommFunction(port_, CLRDTR) || !EscapeCommFunction(port_, CLRRTS))
            throw std::runtime_error("Cannot reset controller");
        Sleep(60);
        if (!EscapeCommFunction(port_, SETDTR) || !EscapeCommFunction(port_, SETRTS))
            throw std::runtime_error("Cannot start controller");
        Sleep(350);
        PurgeComm(port_, PURGE_RXCLEAR | PURGE_TXCLEAR);
        write(reinterpret_cast<uint8_t const *>("Moni-A"), 6);
        std::array<uint8_t, 128> reply{};
        size_t used = 0;
        ULONGLONG deadline = GetTickCount64() + 600;
        do {
            DWORD count = 0;
            if (!ReadFile(port_, reply.data() + used, static_cast<DWORD>(reply.size() - used),
                          &count, nullptr))
                throw std::runtime_error("Controller identity read failed");
            used += count;
            if (used > 16)
                break;
        } while (GetTickCount64() < deadline);
        if (!gl_controller_reply(reply.data(), used))
            throw std::runtime_error(
                "Unsupported or incomplete SK0L34 identity; LED writes refused");
    } catch (...) {
        SetCommState(port_, &original_);
        CloseHandle(port_);
        port_ = INVALID_HANDLE_VALUE;
        throw;
    }
}
void Serial::write(uint8_t const *bytes, size_t count) {
    DWORD errors = 0;
    COMSTAT status{};
    if (!ClearCommError(port_, &errors, &status) || errors)
        throw std::runtime_error("Serial transport error");
    // Bound queued bytes without letting stale color frames accumulate.
    auto deadline = GetTickCount64() + 1500;
    while (status.cbOutQue > 64) {
        if (GetTickCount64() >= deadline)
            throw std::runtime_error("Serial output stalled");
        Sleep(1);
        if (!ClearCommError(port_, &errors, &status) || errors)
            throw std::runtime_error("Serial queue failed");
    }
    size_t offset = 0;
    while (offset < count) {
        DWORD written = 0;
        if (!WriteFile(port_, bytes + offset, static_cast<DWORD>(count - offset), &written,
                       nullptr) ||
            !written)
            throw std::runtime_error("Serial write failed");
        offset += written;
    }
}
void Serial::black() {
    std::array<uint8_t, 342> packet{0x41, 0x64, 0x61, 0, 0, 0x70};
    write(packet.data(), packet.size());
}
Serial::~Serial() {
    if (port_ != INVALID_HANDLE_VALUE) {
        // A bounded drain avoids dropping the final blackout on normal shutdown.
        DWORD error = 0;
        COMSTAT status{};
        auto deadline = GetTickCount64() + 1500;
        while (ClearCommError(port_, &error, &status) && status.cbOutQue &&
               GetTickCount64() < deadline)
            Sleep(2);
        SetCommState(port_, &original_);
        CloseHandle(port_);
    }
}
} // namespace glowline
