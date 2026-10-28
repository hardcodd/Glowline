#pragma once
#include <windows.h>
#include <gdiplus.h>
#include <array>
#include <cmath>
#include <string>
#include <stdexcept>
#include <algorithm>

namespace glowline::visual {
using Gdiplus::Color;
using Gdiplus::RectF;

// The Windows view follows Interface.swift's layout and palette. Coordinates
// are device-independent; native controls retain their keyboard/MSAA behavior.
struct Palette {
    Color canvas, sidebar, card, tile, border, text, secondary, accent, selection;
    explicit Palette(bool dark)
        : canvas(dark ? Color(17, 18, 22) : Color(246, 246, 248)),
          sidebar(dark ? Color(32, 32, 33) : Color(236, 236, 239)),
          card(dark ? Color(24, 25, 29) : Color(251, 251, 253)),
          tile(dark ? Color(30, 31, 35) : Color(242, 242, 245)),
          border(dark ? Color(43, 44, 48) : Color(220, 220, 225)),
          text(dark ? Color(226, 226, 231) : Color(31, 31, 36)),
          secondary(dark ? Color(152, 153, 159) : Color(100, 101, 110)),
          accent(dark ? Color(255, 177, 88) : Color(154, 78, 10)),
          selection(dark ? Color(58, 46, 34) : Color(246, 228, 208)) {}
};
class Canvas {
    Gdiplus::Graphics graphics_;

  public:
    Canvas(HDC dc, double scale) : graphics_(dc) {
        graphics_.ScaleTransform(static_cast<float>(scale), static_cast<float>(scale));
        graphics_.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
        graphics_.SetTextRenderingHint(Gdiplus::TextRenderingHintClearTypeGridFit);
        graphics_.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);
    }
    Gdiplus::Graphics &graphics() { return graphics_; }
    void fill(RectF r, Color color) {
        Gdiplus::SolidBrush brush(color);
        graphics_.FillRectangle(&brush, r);
    }
    static void rounded_path(Gdiplus::GraphicsPath &path, RectF r, float radius) {
        float d = std::min(radius * 2, std::min(r.Width, r.Height));
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.GetRight() - d, r.Y, d, d, 270, 90);
        path.AddArc(r.GetRight() - d, r.GetBottom() - d, d, d, 0, 90);
        path.AddArc(r.X, r.GetBottom() - d, d, d, 90, 90);
        path.CloseFigure();
    }
    void round(RectF r, float radius, Color color, Color border = Color(0, 0, 0, 0),
               float line = 1) {
        Gdiplus::GraphicsPath path;
        rounded_path(path, r, radius);
        Gdiplus::SolidBrush brush(color);
        graphics_.FillPath(&brush, &path);
        if (border.GetA()) {
            Gdiplus::Pen pen(border, line);
            graphics_.DrawPath(&pen, &path);
        }
    }
    void ellipse(RectF r, Color color) {
        Gdiplus::SolidBrush brush(color);
        graphics_.FillEllipse(&brush, r);
    }
    void line(float x1, float y1, float x2, float y2, Color color, float width = 1.4f) {
        Gdiplus::Pen pen(color, width);
        pen.SetStartCap(Gdiplus::LineCapRound);
        pen.SetEndCap(Gdiplus::LineCapRound);
        graphics_.DrawLine(&pen, x1, y1, x2, y2);
    }
    void text(std::wstring const &value, RectF r, float size, Color color, bool bold = false,
              Gdiplus::StringAlignment align = Gdiplus::StringAlignmentNear, bool wrap = false) {
        Gdiplus::Font font(bold ? L"Segoe UI Semibold" : L"Segoe UI", size,
                           Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
        Gdiplus::StringFormat format;
        format.SetAlignment(align);
        format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
        format.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
        if (!wrap)
            format.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);
        Gdiplus::SolidBrush brush(color);
        graphics_.DrawString(value.c_str(), static_cast<INT>(value.size()), &font, r, &format,
                             &brush);
    }
    // Illustrate the same four inward sampling regions as Mac DepthPreview.
    void depth_preview(RectF box, float depth, Palette const &palette,
                       std::wstring const &caption) {
        round(box, 10, palette.tile);
        auto saved = graphics_.Save();
        Gdiplus::GraphicsPath clip;
        rounded_path(clip, box, 10);
        graphics_.SetClip(&clip, Gdiplus::CombineModeIntersect);
        if (depth > 0) {
            Color edge(128, palette.accent.GetR(), palette.accent.GetG(), palette.accent.GetB());
            Color clear(0, palette.accent.GetR(), palette.accent.GetG(), palette.accent.GetB());
            float dx = box.Width * depth, dy = box.Height * depth;
            auto fade = [&](RectF area, Gdiplus::PointF outside, Gdiplus::PointF inside) {
                Gdiplus::LinearGradientBrush brush(outside, inside, edge, clear);
                brush.SetWrapMode(Gdiplus::WrapModeTileFlipXY);
                graphics_.FillRectangle(&brush, area);
            };
            fade({box.X, box.Y, box.Width, dy}, {box.X, box.Y}, {box.X, box.Y + dy});
            fade({box.X, box.GetBottom() - dy, box.Width, dy}, {box.X, box.GetBottom()},
                 {box.X, box.GetBottom() - dy});
            fade({box.X, box.Y, dx, box.Height}, {box.X, box.Y}, {box.X + dx, box.Y});
            fade({box.GetRight() - dx, box.Y, dx, box.Height}, {box.GetRight(), box.Y},
                 {box.GetRight() - dx, box.Y});
        }
        graphics_.Restore(saved);
        round(box, 10, Color(0, 0, 0, 0),
              Color(51, palette.accent.GetR(), palette.accent.GetG(), palette.accent.GetB()));
        text(caption, box, 10, palette.secondary, false, Gdiplus::StringAlignmentCenter);
    }
    // Small original vector icons approximate the corresponding SF Symbols;
    // they are drawn locally rather than redistributing Apple's symbol assets.
    void icon(int kind, float x, float y, float size, Color color) {
        auto saved = graphics_.Save();
        graphics_.TranslateTransform(x, y);
        graphics_.ScaleTransform(size / 24, size / 24);
        Gdiplus::Pen pen(color, 1.45f);
        pen.SetLineJoin(Gdiplus::LineJoinRound);
        if (kind == 0) { // Display.
            round({2, 3, 20, 14}, 1.5f, Color(0, 0, 0, 0), color, 1.5f);
            line(12, 17, 12, 21, color);
            line(8, 21, 16, 21, color);
        } else if (kind == 1) {
            graphics_.DrawArc(&pen, 6.f, 2.f, 12.f, 13.f, 150.f, 240.f);
            line(7, 12, 9, 18, color);
            line(17, 12, 15, 18, color);
            line(9, 18, 15, 18, color);
            line(10, 21, 14, 21, color);
        } else if (kind == 2) {
            round({2, 3, 16, 13}, 2, Color(90, color.GetR(), color.GetG(), color.GetB()));
            round({7, 8, 16, 13}, 2, color);
        } else if (kind == 3) {
            for (int i = 0; i < 3; i++) {
                float a = 5.f + i * 6;
                line(2, a + 4, 14 + i * 2.f, a + 4, color);
                graphics_.DrawArc(&pen, 12.f + i * 2, a - 2, 7.f, 6.f, 180.f, 260.f);
            }
        } else if (kind == 4) {
            for (int i = 0; i < 5; i++)
                graphics_.DrawArc(&pen, 2.f + i * 2, 3.f + i * 2, 20.f - i * 4, 22.f - i * 4, 180.f,
                                  180.f);
        } else if (kind == 5 || kind == 6) {
            Gdiplus::GraphicsPath flame;
            flame.AddBezier(12.f, 2.f, 23.f, 10.f, 23.f, 23.f, 12.f, 23.f);
            flame.AddBezier(12.f, 23.f, 1.f, 23.f, 4.f, 11.f, 7.f, 10.f);
            flame.AddBezier(7.f, 10.f, 8.f, 16.f, 13.f, 9.f, 12.f, 2.f);
            if (kind == 6) {
                Gdiplus::SolidBrush brush(color);
                graphics_.FillPath(&brush, &flame);
            } else
                graphics_.DrawPath(&pen, &flame);
        } else if (kind == 7 || kind == 9) {
            Gdiplus::PointF points[] = {{12, 1},  {15, 9}, {23, 12}, {15, 15},
                                        {12, 23}, {9, 15}, {1, 12},  {9, 9}};
            Gdiplus::SolidBrush brush(color);
            graphics_.FillPolygon(&brush, points, 8);
            if (kind == 9) {
                line(20, 1, 20, 5, color);
                line(18, 3, 22, 3, color);
            }
        } else if (kind == 8) {
            float yy[] = {12, 12, 8, 17, 3, 21, 8, 15, 10, 12, 12};
            for (int i = 0; i < 10; i++)
                line(2 + i * 2.f, yy[i], 4 + i * 2.f, yy[i + 1], color);
        } else if (kind == 10) { // Sliders.
            for (int i = 0; i < 3; i++) {
                float yy = 5.f + i * 7;
                line(2, yy, 22, yy, color);
                ellipse({i == 1 ? 13.f : 6.f, yy - 2, 4, 4}, color);
            }
        } else if (kind == 11) {
            graphics_.DrawEllipse(&pen, 3.f, 3.f, 18.f, 18.f);
            line(12, 6, 12, 12, color);
            line(12, 12, 8, 12, color);
        } else if (kind == 12) {
            line(3, 8, 3, 3, color);
            line(3, 3, 8, 3, color);
            line(16, 3, 21, 3, color);
            line(21, 3, 21, 8, color);
            line(21, 16, 21, 21, color);
            line(21, 21, 16, 21, color);
            line(8, 21, 3, 21, color);
            line(3, 21, 3, 16, color);
        } else if (kind == 13) {
            graphics_.DrawEllipse(&pen, 3.f, 3.f, 18.f, 18.f);
            Gdiplus::SolidBrush brush(color);
            graphics_.FillPie(&brush, 3.f, 3.f, 18.f, 18.f, 90.f, 180.f);
        } else if (kind == 14) {
            for (int i = 0; i < 3; i++) {
                float yy = 3.f + i * 5;
                line(3, yy + 5, 12, yy, color);
                line(12, yy, 21, yy + 5, color);
                line(3, yy + 5, 12, yy + 10, color);
                line(12, yy + 10, 21, yy + 5, color);
            }
        } else if (kind == 15) {
            graphics_.DrawEllipse(&pen, 6.f, 6.f, 12.f, 12.f);
            graphics_.DrawEllipse(&pen, 10.f, 10.f, 4.f, 4.f);
            for (int i = 0; i < 8; i++) {
                float a = i * 3.14159265f / 4;
                line(12 + std::cos(a) * 7, 12 + std::sin(a) * 7, 12 + std::cos(a) * 10,
                     12 + std::sin(a) * 10, color, 2);
            }
        } else if (kind == 16) {
            graphics_.DrawEllipse(&pen, 8.f, 8.f, 8.f, 8.f);
            for (int i = 0; i < 8; i++) {
                float a = i * 3.14159265f / 4;
                line(12 + std::cos(a) * 7, 12 + std::sin(a) * 7, 12 + std::cos(a) * 10,
                     12 + std::sin(a) * 10, color);
            }
        } else if (kind == 17) {
            round({9, 2, 6, 15}, 3, Color(0, 0, 0, 0), color);
            ellipse({7, 13, 10, 10}, color);
            line(12, 6, 12, 16, color);
        } else if (kind == 18) {
            for (int i = 0; i < 4; i++)
                round({2.f + (i % 2) * 12, 2.f + (i / 2) * 12, 8, 8}, 1, Color(0, 0, 0, 0), color);
        } else if (kind == 19) {
            graphics_.DrawArc(&pen, 3.f, 3.f, 18.f, 18.f, -45.f, 270.f);
            line(12, 1, 12, 12, color);
        } else if (kind == 20) {
            round({3, 3, 18, 18}, 3, Color(0, 0, 0, 0), color);
            line(3, 8, 21, 8, color);
        } else if (kind == 22) { // Trash.
            round({6, 7, 12, 15}, 2, Color(0, 0, 0, 0), color);
            line(4, 6, 20, 6, color);
            line(9, 3, 15, 3, color);
            line(10, 10, 10, 18, color);
            line(14, 10, 14, 18, color);
        } else {
            line(5, 12, 19, 12, color);
            line(12, 5, 12, 19, color);
        }
        graphics_.Restore(saved);
    }
    void brand(float x, float y, Color color) {
        ellipse({x + 10, y + 10, 9, 9}, color);
        for (int i = 0; i < 6; i++) {
            float a = i * 3.14159265f / 3;
            ellipse({x + 10 + 10 * std::cos(a), y + 10 + 10 * std::sin(a), 9, 9}, color);
        }
    }
};
class Session {
    ULONG_PTR token_ = 0;

  public:
    Session() {
        Gdiplus::GdiplusStartupInput input;
        if (Gdiplus::GdiplusStartup(&token_, &input, nullptr) != Gdiplus::Ok)
            throw std::runtime_error("Cannot initialize Windows graphics");
    }
    ~Session() { Gdiplus::GdiplusShutdown(token_); }
};
// Double buffer native paint messages; child controls use their own clipped DC.
class Paint {
    HWND window_;
    PAINTSTRUCT paint_{};
    HDC target_, memory_;
    HBITMAP bitmap_;
    HGDIOBJ original_;
    RECT size_{};

  public:
    explicit Paint(HWND window) : window_(window) {
        target_ = BeginPaint(window, &paint_);
        GetClientRect(window, &size_);
        memory_ = CreateCompatibleDC(target_);
        bitmap_ =
            CreateCompatibleBitmap(target_, std::max(1L, size_.right), std::max(1L, size_.bottom));
        original_ = SelectObject(memory_, bitmap_);
    }
    HDC dc() const { return memory_; }
    ~Paint() {
        BitBlt(target_, 0, 0, size_.right, size_.bottom, memory_, 0, 0, SRCCOPY);
        SelectObject(memory_, original_);
        DeleteObject(bitmap_);
        DeleteDC(memory_);
        EndPaint(window_, &paint_);
    }
};
} // namespace glowline::visual
