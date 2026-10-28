#pragma once
#include "settings.h"
#include <algorithm>
#include <cmath>
#include <string>
namespace glowline {
// Match SliderScale.swift: every native tick is a real setting step,
// including the short final interval ending at 33.68 FPS.
struct SliderScale {
    double minimum, maximum, step;
    explicit SliderScale(Field const &field) : minimum(field.minimum), maximum(field.maximum) {
        std::wstring key(field.key);
        step = field.type == FieldType::Integer || key == L"fps" ? 1
               : key == L"speed" || key == L"rainbowCycles"      ? .1
               : key == L"releaseSeconds" || key == L"attackSeconds" || key == L"keepaliveSeconds"
                   ? .001
                   : .01;
    }
    int last() const { return static_cast<int>(std::ceil((maximum - minimum) / step - 1e-9)); }
    int index(double value) const {
        return std::clamp(static_cast<int>(std::round((value - minimum) / step)), 0, last());
    }
    double value(int index) const {
        return std::min(maximum, minimum + std::clamp(index, 0, last()) * step);
    }
};
} // namespace glowline
