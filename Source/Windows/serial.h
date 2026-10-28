#pragma once
#include <windows.h>
#include <string>
#include <vector>
#include <cstdint>

namespace glowline {
std::vector<std::wstring> serial_ports();
/* Exclusive 115200/8N1 connection. No LED writes before the complete bounded
 * identity window passes. Destruction restores the previous DCB. */
class Serial {
    HANDLE port_ = INVALID_HANDLE_VALUE;
    DCB original_{};

  public:
    explicit Serial(std::wstring const &name);
    ~Serial();
    void write(uint8_t const *bytes, size_t count);
    void black();
    Serial(Serial const &) = delete;
    Serial &operator=(Serial const &) = delete;
};
} // namespace glowline
