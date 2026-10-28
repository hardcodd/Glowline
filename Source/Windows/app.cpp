#include "runtime.h"
#include "strings.h"
#include "capture.h"
#include "serial.h"
#include "appearance.h"
#include "slider_scale.h"
#include "localization.h"
#include <map>
#include <windowsx.h>
#include <commctrl.h>
#include <commdlg.h>
#include <shellapi.h>
#include <dwmapi.h>
#include <uxtheme.h>
#include <wtsapi32.h>
#include <winternl.h>
#include <memory>
#include <sstream>
#include <iomanip>
#include <algorithm>
#include <cmath>

// Win32 GDI aliases this name; the JSON API uses the original spelling.
#undef GetObject

namespace glowline {
void run_windows_tests();
void run_capture_test();

static std::wstring current_error() {
    try {
        throw;
    } catch (winrt::hresult_error const &e) {
        return std::wstring(e.message());
    } catch (std::exception const &e) {
        return std::wstring(winrt::to_hstring(e.what()));
    }
}
static std::wstring window_text(HWND control) {
    int n = GetWindowTextLengthW(control);
    std::wstring text(n + 1, L'\0');
    GetWindowTextW(control, text.data(), n + 1);
    text.resize(n);
    return text;
}
static void login_item(bool enabled) {
    HKEY key;
    winrt::check_win32(RegCreateKeyExW(HKEY_CURRENT_USER,
                                       L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
                                       nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr));
    LONG result;
    if (enabled) {
        wchar_t path[32768];
        DWORD length = GetModuleFileNameW(nullptr, path, 32768);
        if (!length || length == 32768) {
            RegCloseKey(key);
            throw std::runtime_error("Cannot find application path");
        }
        std::wstring command = L"\"" + std::wstring(path) + L"\" --startup";
        result = RegSetValueExW(key, L"Glowline", 0, REG_SZ,
                                reinterpret_cast<BYTE const *>(command.c_str()),
                                static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
    } else {
        result = RegDeleteValueW(key, L"Glowline");
        if (result == ERROR_FILE_NOT_FOUND)
            result = ERROR_SUCCESS;
    }
    RegCloseKey(key);
    winrt::check_win32(result);
}
class App {
    struct Binding {
        HWND input = nullptr, slider = nullptr;
        JsonObject object;
        Field field;
        bool time = false;
    };
    HWND window_ = nullptr, panel_ = nullptr, scrollbar_ = nullptr;
    struct ControlView {
        enum Kind {
            Label,
            Button,
            Toggle,
            Slider,
            Combo,
            Navigation,
            Mode,
            Scrollbar,
            Native,
            Swatch
        } kind = Label;
        visual::Color swatch;
        int icon = -1;
        float size = 12;
        bool bold = false, root = false, hover = false, canvas = false, accent = false;
        Gdiplus::StringAlignment alignment = Gdiplus::StringAlignmentNear;
    };
    struct Card {
        visual::RectF box;
        std::wstring title;
        int icon;
    };
    std::map<HWND, ControlView> views_;
    std::vector<Card> cards_;
    visual::RectF monitor_{}, depth_{};
    int stats_y_ = -1, selected_profile_ = -1, scroll_position_ = 0, rename_profile_ = -1;
    int body_x_ = 28, body_width_ = 700;
    bool resizing_ = false;
    int content_height_ = 0;
    HFONT font_ = nullptr;
    HBRUSH background_ = nullptr;
    bool dark_ = true, building_ = false, testing_ = false;
    int page_ = 0;
    double scale_ = 1;
    JsonObject state_, settings_;
    std::unique_ptr<Runtime> runtime_;
    std::filesystem::path path_;
    std::vector<HWND> controls_;
    std::vector<Binding> bindings_;
    std::vector<HWND> diagnostic_values_;
    std::vector<std::wstring> ports_;
    std::vector<Display> displays_;
    HWND port_ = nullptr, display_ = nullptr, name_ = nullptr, schedule_current_ = nullptr,
         diagnostic_error_ = nullptr;
    std::wstring notice_, initialization_error_;
    Status status_;
    NOTIFYICONDATAW tray_{};
    UINT taskbar_created_ = RegisterWindowMessageW(L"TaskbarCreated");
    int px(double value) const { return static_cast<int>(value * scale_ + .5); }
    void error(std::wstring const &text) {
        MessageBoxW(window_, text.c_str(), ui::error, MB_OK | MB_ICONERROR);
    }
    JsonObject profiles_at(int index) {
        return state_.GetNamedArray(L"profiles").GetObjectAt(index);
    }
    static LRESULT CALLBACK control_procedure(HWND child, UINT msg, WPARAM w, LPARAM l, UINT_PTR,
                                              DWORD_PTR context) {
        auto app = reinterpret_cast<App *>(context);
        if (msg == WM_SETFOCUS && !app->building_ && GetParent(child) == app->panel_ &&
            child != app->scrollbar_) {
            RECT area, viewport;
            GetWindowRect(child, &area);
            MapWindowPoints(nullptr, app->panel_, reinterpret_cast<POINT *>(&area), 2);
            GetClientRect(app->panel_, &viewport);
            int shift = area.top < 8                        ? area.top - 8
                        : area.bottom > viewport.bottom - 8 ? area.bottom - viewport.bottom + 8
                                                            : 0;
            if (shift)
                app->scroll_to(app->scroll_position_ + shift);
        }
        if (msg == WM_GETDLGCODE && GetDlgCtrlID(child) == 41 && l &&
            reinterpret_cast<MSG *>(l)->wParam == VK_RETURN)
            return DefSubclassProc(child, msg, w, l) | DLGC_WANTMESSAGE;
        if (msg == WM_KEYDOWN && w == VK_RETURN && GetDlgCtrlID(child) == 41) {
            app->command(44, 0);
            return 0;
        }
        if (app->views_.at(child).kind == ControlView::Native)
            return DefSubclassProc(child, msg, w, l);
        if (msg == WM_PAINT) {
            app->paint_control(child);
            return 0;
        }
        if (msg == WM_ERASEBKGND)
            return 1;
        if (msg == WM_MOUSEMOVE) {
            auto &view = app->views_.at(child);
            if (!view.hover) {
                view.hover = true;
                TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, child, 0};
                TrackMouseEvent(&tracking);
                InvalidateRect(child, nullptr, FALSE);
            }
        } else if (msg == WM_MOUSELEAVE) {
            app->views_.at(child).hover = false;
            InvalidateRect(child, nullptr, FALSE);
        } else if (msg == WM_SETFOCUS || msg == WM_KILLFOCUS || msg == BM_SETCHECK ||
                   msg == TBM_SETPOS || msg == WM_ENABLE || msg == WM_SETTEXT) {
            auto result = DefSubclassProc(child, msg, w, l);
            InvalidateRect(child, nullptr, FALSE);
            return result;
        }
        return DefSubclassProc(child, msg, w, l);
    }
    HWND control(wchar_t const *cls, std::wstring const &text, DWORD style, int x, int y, int w,
                 int h, int id, bool page = true) {
        if (page && std::wstring(cls) != L"SCROLLBAR")
            content_height_ = std::max(content_height_,
                                       px(y + (std::wstring(cls) == WC_COMBOBOXW ? 30 : h) + 28));
        HWND child = CreateWindowExW(
            0, cls, text.c_str(), WS_CHILD | WS_VISIBLE | style, px(x),
            px(y) - (page && std::wstring(cls) != L"SCROLLBAR" ? scroll_position_ : 0), px(w),
            px(h), page ? panel_ : window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
            GetModuleHandleW(nullptr), nullptr);
        if (!child)
            winrt::throw_last_error();
        ControlView view;
        view.root = !page;
        std::wstring name(cls);
        if (name == L"BUTTON") {
            view.kind = (style & BS_TYPEMASK) == BS_AUTOCHECKBOX ? ControlView::Toggle
                                                                 : ControlView::Button;
            SetWindowTheme(child, L"", L"");
        } else if (name == TRACKBAR_CLASSW)
            view.kind = ControlView::Slider;
        else if (name == WC_COMBOBOXW)
            view.kind = ControlView::Combo;
        else if (name == L"SCROLLBAR") {
            view.kind = ControlView::Scrollbar;
            view.canvas = true;
        }
        if (name == L"EDIT")
            view.kind = ControlView::Native;
        views_[child] = view;
        SetWindowSubclass(child, control_procedure, 1, reinterpret_cast<DWORD_PTR>(this));
        SendMessageW(child, WM_SETFONT, reinterpret_cast<WPARAM>(font_), TRUE);
        controls_.push_back(child);
        return child;
    }
    HWND label(std::wstring const &text, int x, int y, int width = 450, int height = 24,
               float size = 12, bool bold = false) {
        auto child = control(L"STATIC", text, SS_LEFT, x, y, width, height, 0);
        views_[child].size = size;
        views_[child].bold = bold;
        return child;
    }
    HWND button(std::wstring const &text, int x, int y, int width, int id, bool page = true,
                int height = 30) {
        return control(L"BUTTON", text, BS_PUSHBUTTON | WS_TABSTOP, x, y, width, height, id, page);
    }
    HWND combo(int x, int y, int w, int id, std::vector<std::wstring> const &entries,
               int selected) {
        auto c = control(WC_COMBOBOXW, L"",
                         CBS_DROPDOWNLIST | CBS_OWNERDRAWFIXED | CBS_HASSTRINGS | WS_VSCROLL |
                             WS_TABSTOP,
                         x, y, w, 280, id);
        SendMessageW(c, CB_SETITEMHEIGHT, -1, px(27));
        SendMessageW(c, CB_SETITEMHEIGHT, 0, px(29));
        for (auto const &e : entries)
            SendMessageW(c, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(e.c_str()));
        SendMessageW(c, CB_SETCURSEL, selected, 0);
        return c;
    }
    static std::wstring format(Field const &f, double value, bool time) {
        if (time) {
            wchar_t text[8];
            swprintf_s(text, L"%02d:%02d", static_cast<int>(value) / 60,
                       static_cast<int>(value) % 60);
            return text;
        }
        auto key = std::wstring(f.key);
        bool milliseconds =
            key == L"releaseSeconds" || key == L"attackSeconds" || key == L"keepaliveSeconds";
        bool multiplier = key == L"speed" || key == L"rainbowCycles";
        bool scalar =
            key == L"gamma" || key == L"fps" || f.type == FieldType::Integer || multiplier;
        std::wostringstream text;
        text << std::fixed
             << std::setprecision(milliseconds || !scalar               ? 0
                                  : f.type == FieldType::Integer        ? 0
                                  : multiplier                          ? 1
                                  : key == L"fps" && value != f.maximum ? 0
                                                                        : 2)
             << (milliseconds ? value * 1000
                 : scalar     ? value
                              : value * 100)
             << (milliseconds    ? L" мс"
                 : multiplier    ? L"×"
                 : key == L"fps" ? L" FPS"
                 : scalar        ? L""
                                 : L"%");
        return text.str();
    }
    void field(JsonObject const &object, Field const &f, int x, int y, int width = 450) {
        Binding b;
        b.object = object;
        b.field = f;
        b.time = std::wstring(f.key) == L"dayStart" || std::wstring(f.key) == L"nightStart";
        int id = 1000 + static_cast<int>(bindings_.size());
        if (f.type == FieldType::Boolean) {
            b.input = control(L"BUTTON", field_title(f), BS_AUTOCHECKBOX | WS_TABSTOP, x, y, width,
                              30, id);
            SendMessageW(b.input, BM_SETCHECK, boolean(object, f.key) ? BST_CHECKED : BST_UNCHECKED,
                         0);
        } else {
            label(field_title(f), x, y, width - (std::wstring(f.key) == L"offset" ? 180 : 112));
            double value = number(object, f.key);
            b.input =
                control(L"EDIT", format(f, value, b.time), ES_AUTOHSCROLL | ES_RIGHT | WS_TABSTOP,
                        x + width - (std::wstring(f.key) == L"offset" ? 166 : 102), y + 2,
                        std::wstring(f.key) == L"offset" ? 64 : 100, 22, id);
            if (std::wstring(f.key) == L"offset") {
                button(L"−", x + width - 92, y, 40, 26, true, 26);
                button(L"+", x + width - 44, y, 40, 27, true, 26);
            } else if (!b.time) {
                b.slider =
                    control(TRACKBAR_CLASSW, field_title(f), TBS_HORZ | TBS_NOTICKS | WS_TABSTOP, x,
                            y + 29, width, 25, 2000 + static_cast<int>(bindings_.size()));
                SendMessageW(b.slider, TBM_SETRANGE, TRUE, MAKELONG(0, SliderScale(f).last()));
                SendMessageW(b.slider, TBM_SETPOS, TRUE, SliderScale(f).index(value));
                if (std::wstring(f.key) == L"brightness") {
                    auto schedule = settings_.GetNamedObject(L"brightnessSchedule");
                    bool active = boolean(schedule, L"enabled") &&
                                  number(schedule, L"dayStart") != number(schedule, L"nightStart");
                    EnableWindow(b.input, !active);
                    EnableWindow(b.slider, !active);
                }
            }
        }
        bindings_.push_back(b);
    }
    void side_row(wchar_t const *side, wchar_t const *gain, int y) {
        field(settings_, find(setting_fields(), side), body_x_ + 22, y, 155);
        auto const &descriptor = find(setting_fields(), gain);
        Binding binding;
        binding.object = settings_;
        binding.field = descriptor;
        auto index = static_cast<int>(bindings_.size());
        int width = body_width_ - 44 - 171;
        binding.slider =
            control(TRACKBAR_CLASSW, field_title(descriptor), TBS_HORZ | TBS_NOTICKS | WS_TABSTOP,
                    body_x_ + 193, y + 2, width - 66, 25, 2000 + index);
        SliderScale scale(descriptor);
        SendMessageW(binding.slider, TBM_SETRANGE, TRUE, MAKELONG(0, scale.last()));
        SendMessageW(binding.slider, TBM_SETPOS, TRUE, scale.index(number(settings_, gain)));
        binding.input = control(L"EDIT", format(descriptor, number(settings_, gain), false),
                                ES_AUTOHSCROLL | ES_RIGHT | WS_TABSTOP, body_x_ + body_width_ - 86,
                                y + 4, 64, 22, 1000 + index);
        bindings_.push_back(binding);
    }
    Field const &find(std::vector<Field> const &fields, wchar_t const *key) {
        return *std::find_if(fields.begin(), fields.end(),
                             [&](auto const &f) { return std::wstring(f.key) == key; });
    }
    void fields(JsonObject const &object, std::vector<Field> const &descriptors,
                std::vector<std::wstring> const &keys, int y, int spacing = 70) {
        for (size_t i = 0; i < keys.size(); i++)
            field(object, find(descriptors, keys[i].c_str()), body_x_ + 22,
                  y + static_cast<int>(i) * spacing, body_width_ - 44);
    }
    void card(std::wstring const &title, int icon, int y, int height) {
        cards_.push_back({{static_cast<float>(body_x_), static_cast<float>(y),
                           static_cast<float>(body_width_), static_cast<float>(height)},
                          title,
                          icon});
        content_height_ = std::max(content_height_, px(y + height + 28));
    }
    void help(std::wstring const &text, int y, int height = 38) {
        label(text, body_x_ + 22, y, body_width_ - 44, height, 10);
    }
    int paragraph(std::wstring const &text, int y) {
        auto dc = GetDC(window_);
        Gdiplus::RectF bounds;
        {
            Gdiplus::Graphics graphics(dc);
            Gdiplus::Font font(L"Segoe UI", 10, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
            graphics.MeasureString(text.c_str(), static_cast<INT>(text.size()), &font,
                                   Gdiplus::RectF(0, 0, static_cast<float>(body_width_ - 44), 1000),
                                   &bounds);
        }
        ReleaseDC(window_, dc);
        int height = std::max(28, static_cast<int>(std::ceil(bounds.Height)) + 6);
        help(text, y, height);
        return y + height + 18;
    }
    size_t begin_card(wchar_t const *key, int icon, int &y) {
        auto index = cards_.size();
        card(tr(key), icon, y, 1);
        y += 60;
        return index;
    }
    void end_card(size_t index, int &y) {
        cards_[index].box.Height = static_cast<float>(y - cards_[index].box.Y + 4);
        y += 24;
        content_height_ = std::max(content_height_, px(y));
    }
    void row(JsonObject const &object, std::vector<Field> const &descriptors, wchar_t const *key,
             int &y, wchar_t const *help_key = nullptr) {
        auto const &descriptor = find(descriptors, key);
        field(object, descriptor, body_x_ + 22, y, body_width_ - 44);
        y += descriptor.type == FieldType::Boolean ? 48 : 72;
        if (std::wstring(key) == L"brightness") {
            auto schedule = settings_.GetNamedObject(L"brightnessSchedule");
            if (boolean(schedule, L"enabled") &&
                number(schedule, L"dayStart") != number(schedule, L"nightStart"))
                y = paragraph(tr(L"schedule.manualHint"), y);
        }
        if (help_key)
            y = paragraph(tr(help_key), y);
    }
    void sync_enabled() {
        auto schedule = settings_.GetNamedObject(L"brightnessSchedule");
        bool scheduled = boolean(schedule, L"enabled") &&
                         number(schedule, L"dayStart") != number(schedule, L"nightStart");
        for (auto const &b : bindings_) {
            std::wstring key(b.field.key);
            bool enabled = true;
            if (key == L"brightness")
                enabled = !scheduled;
            for (auto side : {L"top", L"left", L"right", L"bottom"})
                if (key == std::wstring(side) + L"Gain")
                    enabled = boolean(settings_, (std::wstring(side) + L"Enabled").c_str());
            EnableWindow(b.input, enabled);
            if (b.slider)
                EnableWindow(b.slider, enabled);
        }
    }
    void mode_grid(int y) {
        card(tr(L"mode.title"), 18, y, 294);
        int width = (body_width_ - 64) / 3;
        for (int mode = 0; mode < 9; mode++) {
            auto text = tr((L"mode." + std::to_wstring(mode)).c_str()) + L"\n" +
                        tr((L"mode.help." + std::to_wstring(mode)).c_str());
            auto c = button(text, body_x_ + 22 + (mode % 3) * (width + 10),
                            y + 57 + (mode / 3) * 75, width, 100 + mode, true, 65);
            views_[c].kind = ControlView::Mode;
            views_[c].icon = mode;
        }
    }
    void ports(int y) {
        ports_ = serial_ports();
        std::vector<std::wstring> choices{ui::no_port};
        auto selected = string(settings_, L"port");
        auto it = std::find(ports_.begin(), ports_.end(), selected);
        if (!selected.empty() && it == ports_.end()) {
            ports_.push_back(selected);
            it = ports_.end() - 1;
        }
        choices.insert(choices.end(), ports_.begin(), ports_.end());
        port_ = combo(body_x_ + 22, y, body_width_ - 44, 21, choices,
                      it == ports_.end() ? 0 : 1 + static_cast<int>(it - ports_.begin()));
        button(ui::refresh, body_x_ + 22, y + 45, 170, 22);
        button(ui::retry, body_x_ + 206, y + 45, 160, 11);
    }
    void theme() {
        auto requested = string(settings_, L"theme");
        dark_ = requested != L"light";
        if (requested == L"system") {
            DWORD light = 0, size = sizeof(light);
            if (RegGetValueW(HKEY_CURRENT_USER,
                             L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                             L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light,
                             &size) == ERROR_SUCCESS)
                dark_ = !light;
        }
        if (background_)
            DeleteObject(background_);
        background_ = CreateSolidBrush(dark_ ? RGB(24, 25, 29) : RGB(251, 251, 253));
        BOOL dark = dark_;
        DwmSetWindowAttribute(window_, 20, &dark, sizeof(dark));
        RedrawWindow(window_, nullptr, nullptr, RDW_INVALIDATE | RDW_ALLCHILDREN);
    }
    void persist(bool login_changed = false) {
        settings_ = normalize_settings(settings_);
        state_.Insert(L"settings", settings_);
        write_text(path_, winrt::to_string(state_.Stringify()));
        runtime_->update(settings_);
        if (login_changed && !testing_)
            login_item(boolean(settings_, L"launchAtLogin"));
    }
    void rebuild() {
        building_ = true;
        content_height_ = 0;
        rename_profile_ = -1;
        for (auto c : controls_)
            DestroyWindow(c);
        controls_.clear();
        views_.clear();
        bindings_.clear();
        diagnostic_values_.clear();
        cards_.clear();
        monitor_ = depth_ = {};
        stats_y_ = -1;
        port_ = display_ = name_ = schedule_current_ = diagnostic_error_ = nullptr;
        scrollbar_ = nullptr;
        RECT window, panel;
        GetClientRect(window_, &window);
        GetClientRect(panel_, &panel);
        int height = static_cast<int>(window.bottom / scale_);
        int width = static_cast<int>(window.right / scale_);
        int main_width = static_cast<int>(panel.right / scale_);
        body_width_ = std::min(920, main_width - 56);
        body_x_ = (main_width - body_width_) / 2;
        const int icons[] = {9, 10, 11, 12, 13, 14, 15};
        const wchar_t *keys[] = {L"overview", L"color",    L"schedule", L"capture",
                                 L"effects",  L"profiles", L"app"};
        for (int page = 0; page < 7; page++) {
            auto c = button(tr((std::wstring(L"page.") + keys[page]).c_str()), 20, 98 + page * 48,
                            180, 200 + page, false, 41);
            views_[c].kind = ControlView::Navigation;
            views_[c].icon = icons[page];
        }
        auto hide = button(tr(L"window.hide"), 20, height - 43, 180, 61, false, 28);
        views_[hide].icon = 20;
        auto master = control(L"BUTTON", tr(L"light.enabled"), BS_AUTOCHECKBOX | WS_TABSTOP,
                              width - 206, 17, 178, 29, 10, false);
        SendMessageW(master, BM_SETCHECK,
                     boolean(settings_, L"enabled") ? BST_CHECKED : BST_UNCHECKED, 0);
        if (page_ == 0) {
            monitor_ = {static_cast<float>(body_x_ + (body_width_ - 470) / 2), 18, 470, 195};
            label(tr(L"preview.caption"), body_x_, 222, body_width_, 25, 10);
            views_[controls_.back()].canvas = true;
            views_[controls_.back()].alignment = Gdiplus::StringAlignmentCenter;
            stats_y_ = 270;
            auto schedule = settings_.GetNamedObject(L"brightnessSchedule");
            bool active = boolean(schedule, L"enabled") &&
                          number(schedule, L"dayStart") != number(schedule, L"nightStart");
            card(tr(L"light.quick"), 10, 356, active ? 290 : 250);
            fields(settings_, setting_fields(), {L"brightness"}, 416);
            if (active)
                help(tr(L"schedule.manualHint"), 474, 30);
            fields(settings_, setting_fields(), {L"warmth"}, active ? 514 : 494);
            help(tr(L"help.warmth"), active ? 572 : 552, active ? 38 : 30);
            int footer = active ? 622 : 584;
            label(tr(L"warmth.neutral"), body_x_ + 22, footer, 130, 20, 10);
            auto accepted =
                label(tr(L"warmth.accepted"), body_x_ + 152, footer, body_width_ - 304, 20, 10);
            views_[accepted].alignment = Gdiplus::StringAlignmentCenter;
            views_[accepted].accent = true;
            auto amber =
                label(tr(L"warmth.amber"), body_x_ + body_width_ - 152, footer, 130, 20, 10);
            views_[amber].alignment = Gdiplus::StringAlignmentFar;
            mode_grid(active ? 666 : 626);
        } else if (page_ == 1) {
            int y = 28;
            auto card_index = begin_card(L"color.balance", 17, y);
            row(settings_, setting_fields(), L"warmth", y, L"help.warmth");
            auto swatch = label(L"", body_x_ + 22, y, 42, 25);
            views_[swatch].kind = ControlView::Swatch;
            double warmth = number(settings_, L"warmth");
            views_[swatch].swatch = visual::Color(255, static_cast<BYTE>(255 * (1 - warmth * .35)),
                                                  static_cast<BYTE>(255 * (1 - warmth)));
            label(tr(L"color.whitePreview"), body_x_ + 76, y, body_width_ - 350, 28, 10);
            button(tr(L"color.accepted"), body_x_ + body_width_ - 250, y, 228, 74);
            y += 50;
            row(settings_, setting_fields(), L"brightness", y);
            row(settings_, setting_fields(), L"saturation", y);
            row(settings_, setting_fields(), L"gamma", y, L"help.gamma");
            end_card(card_index, y);
            card_index = begin_card(L"color.channels", 10, y);
            for (auto key : {L"redGain", L"greenGain", L"blueGain"})
                row(settings_, setting_fields(), key, y);
            y = paragraph(tr(L"help.channels"), y);
            end_card(card_index, y);
            card_index = begin_card(L"color.dark", 13, y);
            row(settings_, setting_fields(), L"blackThreshold", y, L"help.black");
            end_card(card_index, y);
        } else if (page_ == 2) {
            int y = 28;
            auto schedule = settings_.GetNamedObject(L"brightnessSchedule");
            auto index = begin_card(L"schedule.title", 11, y);
            row(schedule, schedule_fields(), L"enabled", y);
            y = paragraph(tr(L"schedule.help"), y);
            label(tr(L"schedule.current"), body_x_ + 22, y, 130);
            SYSTEMTIME time;
            GetLocalTime(&time);
            auto c = engine_controls(settings_, time.wHour * 60 + time.wMinute);
            int day = static_cast<int>(number(schedule, L"dayStart")),
                night = static_cast<int>(number(schedule, L"nightStart"));
            bool active = boolean(schedule, L"enabled") && day != night;
            bool daytime = day < night ? (time.wHour * 60 + time.wMinute >= day &&
                                          time.wHour * 60 + time.wMinute < night)
                                       : (time.wHour * 60 + time.wMinute >= day ||
                                          time.wHour * 60 + time.wMinute < night);
            auto period = !c.enabled ? L"schedule.off"
                          : !active  ? L"schedule.manual"
                          : daytime  ? L"schedule.day"
                                     : L"schedule.night";
            schedule_current_ = label(tr(period) + L"  " +
                                          format(find(setting_fields(), L"brightness"),
                                                 c.enabled ? c.brightness : 0, false),
                                      body_x_ + 160, y, body_width_ - 182, 24, 12);
            y += 45;
            if (boolean(schedule, L"enabled") && day == night)
                y = paragraph(tr(L"schedule.invalid"), y);
            end_card(index, y);
            for (auto daytime : {true, false}) {
                index =
                    begin_card(daytime ? L"schedule.day" : L"schedule.night", daytime ? 16 : 13, y);
                row(schedule, schedule_fields(), daytime ? L"dayStart" : L"nightStart", y);
                auto const &f = find(schedule_fields(), L"dayStart");
                y = paragraph(format(f, daytime ? day : night, true) + L" — " +
                                  format(f, daytime ? night : day, true),
                              y);
                row(schedule, schedule_fields(), daytime ? L"dayBrightness" : L"nightBrightness",
                    y);
                end_card(index, y);
            }
            paragraph(tr(L"schedule.profiles"), y);
        } else if (page_ == 3) {
            int y = 28;
            auto index = begin_card(L"capture.area", 12, y);
            label(tr(L"capture.display"), body_x_ + 22, y, body_width_ - 44);
            y += 30;
            displays_ = displays();
            std::vector<std::wstring> screens{ui::default_display};
            int selected_index = 0;
            auto selected = string(settings_, L"windowsDisplay");
            for (size_t i = 0; i < displays_.size(); i++) {
                screens.push_back(displays_[i].name);
                if (displays_[i].device == selected)
                    selected_index = static_cast<int>(i) + 1;
            }
            display_ = combo(body_x_ + 22, y, body_width_ - 44, 23, screens, selected_index);
            y += 48;
            row(settings_, setting_fields(), L"detailMode", y, L"help.detailMode");
            row(settings_, setting_fields(), L"edgeDepth", y, L"help.depth");
            depth_ = {static_cast<float>(body_x_ + 22), static_cast<float>(y),
                      static_cast<float>(body_width_ - 44), 95};
            y += 113;
            row(settings_, setting_fields(), L"releaseSeconds", y, L"help.release");
            row(settings_, setting_fields(), L"attackSeconds", y, L"help.attack");
            end_card(index, y);
            index = begin_card(L"capture.layout", 0, y);
            row(settings_, setting_fields(), L"mirrored", y);
            row(settings_, setting_fields(), L"offset", y);
            y -= 24;
            const wchar_t *sides[] = {L"topEnabled", L"leftEnabled", L"rightEnabled",
                                      L"bottomEnabled"};
            const wchar_t *gains[] = {L"topGain", L"leftGain", L"rightGain", L"bottomGain"};
            for (int i = 0; i < 4; i++) {
                side_row(sides[i], gains[i], y);
                y += 48;
            }
            end_card(index, y);
            index = begin_card(L"capture.performance", 16, y);
            row(settings_, setting_fields(), L"fps", y, L"help.fps");
            label(tr(L"control.captureRate"), body_x_ + 22, y, body_width_ - 44);
            y += 30;
            std::vector<std::wstring> rates;
            int rate_index = -1;
            for (int rate : {30, 60, 90, 120, 144, 240}) {
                if (number(settings_, L"captureFps") == rate)
                    rate_index = static_cast<int>(rates.size());
                rates.push_back(std::to_wstring(rate) + L" Hz");
            }
            if (rate_index < 0) {
                rate_index = static_cast<int>(rates.size());
                rates.push_back(
                    std::to_wstring(static_cast<int>(number(settings_, L"captureFps"))) + L" Hz");
            }
            combo(body_x_ + 22, y, body_width_ - 44, 24, rates, rate_index);
            y += 48;
            row(settings_, setting_fields(), L"skipUnchanged", y);
            row(settings_, setting_fields(), L"keepaliveSeconds", y);
            y = paragraph(tr(L"help.performance"), y);
            end_card(index, y);
        } else if (page_ == 4) {
            mode_grid(28);
            int y = 342;
            int mode = static_cast<int>(number(settings_, L"mode"));
            auto effect = active_effect(settings_);
            settings_.GetNamedObject(L"effectSettings").Insert(std::to_wstring(mode), effect);
            auto title = L"effects.settings." + std::to_wstring(mode);
            auto index = begin_card(title.c_str(), mode, y);
            if (mode == 0) {
                row(settings_, setting_fields(), L"detailMode", y, L"help.detailMode");
                row(settings_, setting_fields(), L"edgeDepth", y, L"help.depth");
                depth_ = {static_cast<float>(body_x_ + 22), static_cast<float>(y),
                          static_cast<float>(body_width_ - 44), 95};
                y += 113;
            } else {
                if (mode == 1 || mode == 2 || mode == 3 || mode == 7) {
                    for (bool secondary : {false, true}) {
                        if (secondary && mode != 2 && mode != 7)
                            break;
                        auto color = effect.GetNamedObject(secondary ? L"secondary" : L"primary");
                        auto button_handle =
                            button(tr(secondary ? L"effects.secondary" : L"effects.primary"),
                                   body_x_ + 22, y, body_width_ - 44, secondary ? 31 : 30);
                        views_[button_handle].swatch =
                            visual::Color(static_cast<BYTE>(number(color, L"red") * 255),
                                          static_cast<BYTE>(number(color, L"green") * 255),
                                          static_cast<BYTE>(number(color, L"blue") * 255));
                        y += 48;
                    }
                    for (int i = 0; i < 5; i++) {
                        auto button_handle = button(tr(L"effects.swatch"), body_x_ + 22 + i * 42, y,
                                                    28, 80 + i, true, 28);
                        views_[button_handle].kind = ControlView::Swatch;
                        views_[button_handle].swatch = preset(i);
                    }
                    y += 52;
                }
                if (mode >= 3)
                    row(effect, effect_fields(), L"speed", y);
                const wchar_t *extras[] = {L"",
                                           L"",
                                           L"gradientBalance",
                                           L"breathingFloor",
                                           L"rainbowCycles",
                                           L"candleFlicker",
                                           L"flameHeight",
                                           L"cometTail",
                                           L"auroraPink"};
                const wchar_t *helps[] = {L"",
                                          L"",
                                          L"help.gradientBalance",
                                          L"help.breathingFloor",
                                          L"help.rainbowCycles",
                                          L"help.candleFlicker",
                                          L"help.flameHeight",
                                          L"help.cometTail",
                                          L"help.auroraPink"};
                if (mode >= 2)
                    row(effect, effect_fields(), extras[mode], y, helps[mode]);
                if (mode == 4 || mode == 7 || mode == 8)
                    row(effect, effect_fields(), L"reverse", y);
            }
            y = paragraph(tr(L"effects.savedSeparately"), y);
            end_card(index, y);
        } else if (page_ == 5) {
            card(tr(L"profile.create"), 21, 28, 170);
            name_ = control(L"EDIT", L"", ES_AUTOHSCROLL | WS_TABSTOP, body_x_ + 22, 91,
                            body_width_ - 190, 28, 41);
            SendMessageW(name_, EM_SETCUEBANNER, TRUE,
                         reinterpret_cast<LPARAM>(tr(L"profile.placeholder").c_str()));
            SendMessageW(name_, EM_LIMITTEXT, 60, 0);
            EnableWindow(button(tr(L"profile.save"), body_x_ + body_width_ - 150, 88, 128, 44),
                         FALSE);
            help(tr(L"profile.help"), 140, 35);
            auto profiles = state_.GetNamedArray(L"profiles");
            int library_height =
                profiles.Size() ? 88 + static_cast<int>(profiles.Size()) * 74 : 220;
            card(tr(L"profile.library"), 14, 218, library_height);
            if (profiles.Size() == 0) {
                label(tr(L"profile.empty"), body_x_ + 22, 302, body_width_ - 44, 35, 17, true);
                help(tr(L"profile.emptyHelp"), 344, 35);
            }
            for (unsigned i = 0; i < profiles.Size(); i++) {
                auto item = profiles.GetObjectAt(i);
                auto saved = item.GetNamedObject(L"settings");
                int y = 278 + static_cast<int>(i) * 74;
                auto mode = static_cast<int>(number(saved, L"mode"));
                auto emblem = label(L"", body_x_ + 22, y + 15, 24, 24);
                views_[emblem].icon = mode;
                label(string(item, L"name"), body_x_ + 56, y, body_width_ - 328, 24, 13, true);
                if (selected_profile_ == static_cast<int>(i))
                    label(L"✓", body_x_ + body_width_ - 264, y + 12, 24, 24, 15, true);
                label(tr((L"mode." + std::to_wstring(mode)).c_str()) + L" · " +
                          format(find(setting_fields(), L"brightness"),
                                 number(saved, L"brightness"), false),
                      body_x_ + 56, y + 25, body_width_ - 328, 22, 10);
                button(tr(L"profile.apply"), body_x_ + body_width_ - 190, y + 8, 120, 4000 + i);
                auto remove =
                    button(tr(L"profile.delete"), body_x_ + body_width_ - 58, y + 8, 36, 5000 + i);
                views_[remove].icon = 22;
                button(L"···", body_x_ + body_width_ - 234, y + 8, 32, 6000 + i);
            }
            int y = 238 + library_height;
            card(tr(L"profile.backup"), 14, y, 265);
            button(tr(L"profile.export"), body_x_ + 22, y + 60, 180, 48);
            button(tr(L"profile.import"), body_x_ + 214, y + 60, 180, 47);
            help(tr(L"profile.backupHelp"), y + 104, 35);
            button(tr(L"settings.reset"), body_x_ + 22, y + 159, 250, 51);
            paragraph(tr(L"reset.help"), y + 201);
        } else {
            int y = 28;
            auto index = begin_card(L"app.startup", 19, y);
            row(settings_, setting_fields(), L"launchAtLogin", y);
            y = paragraph(tr(boolean(settings_, L"launchAtLogin") ? L"windows.login.on"
                                                                  : L"windows.login.off"),
                          y);
            for (auto key : {L"startHidden", L"reconnect", L"offOnQuit"})
                row(settings_, setting_fields(), key, y);
            button(tr(L"windows.login.settings"), body_x_ + 22, y, 250, 76);
            y += 48;
            end_card(index, y);
            index = begin_card(L"app.appearance", 13, y);
            const wchar_t *themes[] = {L"system", L"dark", L"light"};
            const wchar_t *titles[] = {L"theme.system", L"theme.dark", L"theme.light"};
            const int ids[] = {72, 70, 71};
            for (int i = 0; i < 3; i++) {
                int width = (body_width_ - 44) / 3;
                auto child = button(tr(titles[i]), body_x_ + 22 + i * width, y, width, ids[i]);
                views_[child].bold = string(settings_, L"theme") == themes[i];
            }
            y += 48;
            y = paragraph(tr(L"app.closeHelp"), y);
            end_card(index, y);
            index = begin_card(L"app.device", 20, y);
            label(tr(L"device.port"), body_x_ + 22, y, body_width_ - 44);
            y += 30;
            ports(y);
            y += 94;
            y = paragraph(L"115200 baud · SK0L34", y);
            y = paragraph(tr(L"device.identityHelp"), y);
            y = paragraph(ui::capture_note, y);
            end_card(index, y);
            index = begin_card(L"app.diagnostics", 8, y);
            label(ui::platform_note, body_x_ + 22, y, body_width_ - 44, 24, 12, true);
            y += 42;
            for (auto item :
                 {std::pair{L"stat.fps", status_.fps}, std::pair{L"stat.write", status_.write_ms},
                  std::pair{L"stat.frames", static_cast<double>(status_.sent)},
                  std::pair{L"stat.capture", static_cast<double>(status_.captured)}}) {
                label(tr(item.first), body_x_ + 22, y, body_width_ - 200);
                std::wostringstream value;
                value << std::fixed
                      << std::setprecision(std::wstring(item.first) == L"stat.fps"     ? 2
                                           : std::wstring(item.first) == L"stat.write" ? 1
                                                                                       : 0)
                      << item.second;
                if (std::wstring(item.first) == L"stat.write")
                    value << L" ms";
                auto child = label(value.str(), body_x_ + body_width_ - 160, y, 138);
                views_[child].alignment = Gdiplus::StringAlignmentFar;
                diagnostic_values_.push_back(child);
                y += 34;
            }
            auto message = !notice_.empty()                ? notice_
                           : !status_.serial_error.empty() ? status_.serial_error
                                                           : status_.capture_error;
            diagnostic_error_ = label(message, body_x_ + 22, y, body_width_ - 44, 80, 10);
            y += 98;
            button(tr(L"diagnostics.logs"), body_x_ + 22, y, 190, 75);
            button(tr(L"diagnostics.files"), body_x_ + 224, y, 190, 73);
            y += 48;
            y = paragraph(tr(L"diagnostics.privacy"), y);
            button(ui::quit, body_x_ + 22, y, 140, 52);
            y += 48;
            end_card(index, y);
        }
        scrollbar_ = control(L"SCROLLBAR", L"", SBS_VERT, main_width - 10, 0, 10,
                             static_cast<int>(panel.bottom / scale_), 9000);
        views_[scrollbar_].canvas = true;
        SCROLLINFO scroll{sizeof(scroll),
                          SIF_RANGE | SIF_PAGE | SIF_POS,
                          0,
                          std::max(0, content_height_ - 1),
                          static_cast<UINT>(panel.bottom),
                          scroll_position_,
                          0};
        SetScrollInfo(panel_, SB_VERT, &scroll, FALSE);
        ShowScrollBar(panel_, SB_VERT, FALSE);
        SetScrollInfo(scrollbar_, SB_CTL, &scroll, TRUE);
        scroll.fMask = SIF_POS;
        GetScrollInfo(panel_, SB_VERT, &scroll);
        if (scroll_position_ != scroll.nPos) {
            for (auto child : controls_)
                if (GetParent(child) == panel_ && child != scrollbar_) {
                    RECT r;
                    GetWindowRect(child, &r);
                    MapWindowPoints(nullptr, panel_, reinterpret_cast<POINT *>(&r), 2);
                    SetWindowPos(child, nullptr, r.left, r.top + scroll_position_ - scroll.nPos, 0,
                                 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
                }
            scroll_position_ = scroll.nPos;
        }
        ShowWindow(scrollbar_, content_height_ > panel.bottom ? SW_SHOW : SW_HIDE);
        sync_enabled();
        theme();
        building_ = false;
        InvalidateRect(panel_, nullptr, TRUE);
        InvalidateRect(window_, nullptr, TRUE);
    }
    void change_field(size_t index, bool slider) {
        if (building_ || index >= bindings_.size())
            return;
        auto &b = bindings_[index];
        if (b.field.type == FieldType::Boolean)
            put(b.object, b.field.key, SendMessageW(b.input, BM_GETCHECK, 0, 0) == BST_CHECKED);
        else {
            double value;
            if (slider) {
                value = SliderScale(b.field).value(
                    static_cast<int>(SendMessageW(b.slider, TBM_GETPOS, 0, 0)));
            } else {
                auto text = window_text(b.input);
                if (b.time) {
                    int h, m;
                    wchar_t rest;
                    if (swscanf_s(text.c_str(), L"%d:%d%c", &h, &m, &rest, 1) != 2 || h < 0 ||
                        h > 23 || m < 0 || m > 59)
                        throw std::runtime_error("Use HH:MM (00:00–23:59)");
                    value = h * 60 + m;
                } else {
                    std::replace(text.begin(), text.end(), L',', L'.');
                    size_t end = 0;
                    double divisor = 1;
                    if (text.ends_with(L"%")) {
                        text.pop_back();
                        divisor = 100;
                    } else if (text.ends_with(L" мс")) {
                        text.resize(text.size() - 3);
                        divisor = 1000;
                    } else if (text.ends_with(L" FPS"))
                        text.resize(text.size() - 4);
                    else if (text.ends_with(L"×"))
                        text.pop_back();
                    value = std::stod(text, &end) / divisor;
                    if (end != text.size() || !std::isfinite(value) || value < b.field.minimum ||
                        value > b.field.maximum ||
                        (b.field.type == FieldType::Integer && std::floor(value) != value))
                        throw std::runtime_error("Invalid numeric setting");
                }
            }
            put(b.object, b.field.key, value);
            SetWindowTextW(b.input, format(b.field, value, b.time).c_str());
            if (b.slider)
                SendMessageW(b.slider, TBM_SETPOS, TRUE, SliderScale(b.field).index(value));
        }
        // Bindings refer to the current normalized object until a page rebuild.
        state_.Insert(L"settings", settings_);
        write_text(path_, winrt::to_string(state_.Stringify()));
        runtime_->update(settings_);
        if (!testing_ && std::wstring(b.field.key) == L"launchAtLogin")
            login_item(boolean(settings_, L"launchAtLogin"));
        sync_enabled();
        if (page_ == 1)
            for (auto &[child, view] : views_)
                if (view.kind == ControlView::Swatch) {
                    double warmth = number(settings_, L"warmth");
                    view.swatch = visual::Color(255, static_cast<BYTE>(255 * (1 - warmth * .35)),
                                                static_cast<BYTE>(255 * (1 - warmth)));
                    InvalidateRect(child, nullptr, FALSE);
                }
        if (page_ == 2 && !slider) {
            rebuild();
            return;
        }
        InvalidateRect(panel_, nullptr, FALSE);
    }
    static visual::Color preset(int index) {
        const visual::Color colors[] = {visual::Color(255, 160, 64), visual::Color(255, 77, 38),
                                        visual::Color(72, 96, 255), visual::Color(51, 255, 166),
                                        visual::Color(255, 230, 179)};
        return colors[index];
    }
    void color(bool secondary) {
        auto effect = active_effect(settings_);
        auto rgb = effect.GetNamedObject(secondary ? L"secondary" : L"primary");
        static COLORREF custom[16]{};
        CHOOSECOLORW dialog{};
        dialog.lStructSize = sizeof(dialog);
        dialog.hwndOwner = window_;
        dialog.lpCustColors = custom;
        dialog.Flags = CC_FULLOPEN | CC_RGBINIT;
        dialog.rgbResult =
            RGB(std::lround(number(rgb, L"red") * 255), std::lround(number(rgb, L"green") * 255),
                std::lround(number(rgb, L"blue") * 255));
        if (ChooseColorW(&dialog)) {
            put(rgb, L"red", GetRValue(dialog.rgbResult) / 255.);
            put(rgb, L"green", GetGValue(dialog.rgbResult) / 255.);
            put(rgb, L"blue", GetBValue(dialog.rgbResult) / 255.);
            settings_.GetNamedObject(L"effectSettings")
                .Insert(std::to_wstring(static_cast<int>(number(settings_, L"mode"))), effect);
            persist();
            rebuild();
        }
    }
    void file(bool exporting) {
        wchar_t path[32768] = L"Glowline-settings.json";
        OPENFILENAMEW dialog{};
        dialog.lStructSize = sizeof(dialog);
        dialog.hwndOwner = window_;
        dialog.lpstrFile = path;
        dialog.nMaxFile = 32768;
        dialog.lpstrFilter = L"JSON (*.json)\0*.json\0\0";
        dialog.lpstrDefExt = L"json";
        dialog.Flags = OFN_NOCHANGEDIR | OFN_PATHMUSTEXIST |
                       (exporting ? OFN_OVERWRITEPROMPT : OFN_FILEMUSTEXIST);
        if (exporting ? GetSaveFileNameW(&dialog) : GetOpenFileNameW(&dialog)) {
            if (exporting)
                write_text(path, winrt::to_string(state_.Stringify()));
            else {
                auto candidate = decode_state(read_text(path));
                state_ = candidate;
                settings_ = state_.GetNamedObject(L"settings");
                persist(true);
                rebuild();
                runtime_->retry();
            }
        }
    }
    void profile(int command) {
        auto profiles = state_.GetNamedArray(L"profiles");
        int index = selected_profile_;
        auto name = window_text(name_);
        name.erase(0, name.find_first_not_of(L" \t\r\n"));
        auto end = name.find_last_not_of(L" \t\r\n");
        if (end != std::wstring::npos)
            name.resize(end + 1);
        if (command == 44) {
            if (name.empty()) {
                error(ui::name_required);
                return;
            }
            if (name.size() > 60)
                name.resize(60);
            for (unsigned i = 0; i < profiles.Size(); i++)
                if (_wcsicmp(string(profiles.GetObjectAt(i), L"name").c_str(), name.c_str()) == 0) {
                    profiles.GetObjectAt(i).Insert(L"settings", copy(settings_));
                    selected_profile_ = static_cast<int>(i);
                    persist();
                    rebuild();
                    return;
                }
            GUID id;
            winrt::check_hresult(CoCreateGuid(&id));
            wchar_t text[40];
            StringFromGUID2(id, text, 40);
            JsonObject p;
            put(p, L"id", std::wstring(text + 1, 36));
            put(p, L"name", name);
            p.Insert(L"settings", copy(settings_));
            profiles.Append(p);
            selected_profile_ = static_cast<int>(profiles.Size()) - 1;
        } else if (index >= 0 && static_cast<unsigned>(index) < profiles.Size()) {
            auto p = profiles_at(index);
            if (command == 42)
                settings_ = copy(p.GetNamedObject(L"settings"));
            if (command == 43)
                p.Insert(L"settings", copy(settings_));
            if (command == 45) {
                if (name.empty()) {
                    error(ui::name_required);
                    return;
                }
                put(p, L"name", name);
            }
            if (command == 46 && MessageBoxW(window_, ui::delete_question, ui::title,
                                             MB_YESNO | MB_ICONQUESTION) == IDYES) {
                profiles.RemoveAt(index);
                selected_profile_ = -1;
            }
        }
        persist(command == 42);
        rebuild();
    }
    void tray_menu() {
        HMENU menu = CreatePopupMenu();
        AppendMenuW(menu, MF_STRING, 60, ui::open);
        AppendMenuW(menu, MF_STRING | (boolean(settings_, L"enabled") ? MF_CHECKED : 0), 10,
                    ui::enable);
        for (int i = 0; i < 9; i++)
            AppendMenuW(menu, MF_STRING | (number(settings_, L"mode") == i ? MF_CHECKED : 0),
                        100 + i, ui::modes[i]);
        HMENU profiles = CreatePopupMenu();
        auto saved = state_.GetNamedArray(L"profiles");
        for (unsigned i = 0; i < saved.Size() && i < 1000; i++)
            AppendMenuW(profiles, MF_STRING, 3000 + i,
                        string(saved.GetObjectAt(i), L"name").c_str());
        AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(profiles), ui::pages[5]);
        AppendMenuW(menu, MF_STRING, 52, ui::quit);
        POINT point;
        GetCursorPos(&point);
        SetForegroundWindow(window_);
        int chosen = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, point.x, point.y, 0,
                                    window_, nullptr);
        DestroyMenu(menu);
        if (chosen)
            command(chosen, 0);
        PostMessageW(window_, WM_NULL, 0, 0);
    }
    void command(int id, int notification) {
        if (building_)
            return;
        if (id == 41 && notification == EN_CHANGE) {
            auto text = window_text(name_);
            EnableWindow(GetDlgItem(panel_, 44),
                         text.find_first_not_of(L" \t\r\n") != std::wstring::npos);
            return;
        }
        if (id >= 1000 && id < 2000 &&
            (notification == BN_CLICKED || notification == EN_KILLFOCUS)) {
            change_field(id - 1000, false);
            return;
        }
        if (id >= 200 && id < 207) {
            page_ = id - 200;
            scroll_position_ = 0;
            rebuild();
            return;
        }
        if (id >= 4000 && id < 5000) {
            selected_profile_ = id - 4000;
            profile(42);
            return;
        }
        if (id >= 5000 && id < 6000) {
            selected_profile_ = id - 5000;
            profile(46);
            return;
        }
        if (id >= 6000 && id < 7000) {
            selected_profile_ = id - 6000;
            if (static_cast<unsigned>(selected_profile_) >=
                state_.GetNamedArray(L"profiles").Size())
                return;
            HMENU menu = CreatePopupMenu();
            AppendMenuW(menu, MF_STRING, 43, ui::replace);
            AppendMenuW(menu, MF_STRING, 45, ui::rename);
            AppendMenuW(menu, MF_STRING, 46, ui::remove);
            POINT point;
            GetCursorPos(&point);
            SetForegroundWindow(window_);
            int chosen = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, point.x, point.y, 0,
                                        window_, nullptr);
            DestroyMenu(menu);
            if (chosen == 45) {
                rename_profile_ = selected_profile_;
                SetWindowTextW(name_, string(profiles_at(selected_profile_), L"name").c_str());
                SetWindowTextW(GetDlgItem(panel_, 44), ui::rename);
                SetFocus(name_);
                SendMessageW(name_, EM_SETSEL, 0, -1);
            } else if (chosen)
                profile(chosen);
            return;
        }
        if (id == 44 && rename_profile_ >= 0) {
            selected_profile_ = rename_profile_;
            profile(45);
            return;
        }
        if (id >= 70 && id <= 72) {
            const wchar_t *themes[] = {L"dark", L"light", L"system"};
            put(settings_, L"theme", std::wstring(themes[id - 70]));
            persist();
            rebuild();
            return;
        }
        if (id == 74) {
            put(settings_, L"warmth", .5);
            persist();
            rebuild();
            return;
        }
        if (id >= 80 && id < 85) {
            auto effect = active_effect(settings_);
            auto color = effect.GetNamedObject(L"primary");
            auto value = preset(id - 80);
            put(color, L"red", value.GetR() / 255.);
            put(color, L"green", value.GetG() / 255.);
            put(color, L"blue", value.GetB() / 255.);
            effect.Insert(L"primary", color);
            settings_.GetNamedObject(L"effectSettings")
                .Insert(std::to_wstring(static_cast<int>(number(settings_, L"mode"))), effect);
            persist();
            rebuild();
            return;
        }
        if (id == 26 || id == 27) {
            for (size_t i = 0; i < bindings_.size(); i++)
                if (std::wstring(bindings_[i].field.key) == L"offset") {
                    auto &b = bindings_[i];
                    auto value = std::clamp(number(b.object, b.field.key) + (id == 26 ? -1 : 1),
                                            b.field.minimum, b.field.maximum);
                    SetWindowTextW(b.input, format(b.field, value, false).c_str());
                    change_field(i, false);
                    break;
                }
            return;
        }
        if (id == 24 && notification == CBN_SELCHANGE) {
            const int rates[] = {30, 60, 90, 120, 144, 240};
            auto index = SendMessageW(GetDlgItem(panel_, 24), CB_GETCURSEL, 0, 0);
            if (index >= 0 && index < 6) {
                put(settings_, L"captureFps", static_cast<double>(rates[index]));
                persist();
                rebuild();
            }
            return;
        }
        if (id == 76) {
            ShellExecuteW(window_, L"open", L"ms-settings:startupapps", nullptr, nullptr,
                          SW_SHOWNORMAL);
            return;
        }
        if (id == 75) {
            std::ostringstream text;
            text << "Glowline Windows 11 x64\nConnected: " << status_.connected
                 << "\nCapture ready: " << status_.capture_ready << "\nFPS: " << status_.fps
                 << "\nWrite ms: " << status_.write_ms << "\nSent: " << status_.sent
                 << "\nCaptured: " << status_.captured
                 << "\nUSB error: " << winrt::to_string(status_.serial_error)
                 << "\nCapture error: " << winrt::to_string(status_.capture_error) << "\n";
            auto report = path_.parent_path() / L"diagnostics.txt";
            write_text(report, text.str());
            ShellExecuteW(window_, L"open", report.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
            return;
        }
        if (id == 73) {
            ShellExecuteW(window_, L"open", path_.parent_path().c_str(), nullptr, nullptr,
                          SW_SHOWNORMAL);
            return;
        }
        if (id == 61) {
            ShowWindow(window_, SW_HIDE);
            return;
        }
        if (id == 10) {
            put(settings_, L"enabled", !boolean(settings_, L"enabled"));
            persist();
            rebuild();
        } else if (id == 11)
            runtime_->retry();
        else if (id == 21 && notification == CBN_SELCHANGE) {
            int index = static_cast<int>(SendMessageW(port_, CB_GETCURSEL, 0, 0));
            put(settings_, L"port", index > 0 ? ports_.at(index - 1) : std::wstring{});
            persist();
            rebuild();
        } else if (id == 22)
            rebuild();
        else if (id == 23 && notification == CBN_SELCHANGE) {
            int index = static_cast<int>(SendMessageW(display_, CB_GETCURSEL, 0, 0));
            put(settings_, L"windowsDisplay",
                index > 0 ? displays_.at(index - 1).device : std::wstring{});
            persist();
            rebuild();
        } else if (id == 30 || id == 31)
            color(id == 31);
        else if (id >= 42 && id <= 46)
            profile(id);
        else if (id == 47 || id == 48)
            file(id == 48);
        else if (id == 51 && MessageBoxW(window_, ui::reset_question, ui::title,
                                         MB_YESNO | MB_ICONQUESTION) == IDYES) {
            auto port = string(settings_, L"port");
            settings_ = normalize_settings(JsonObject{});
            put(settings_, L"port", port);
            persist(true);
            rebuild();
        } else if (id == 52)
            DestroyWindow(window_);
        else if (id == 60) {
            ShowWindow(window_, SW_RESTORE);
            SetForegroundWindow(window_);
        } else if (id >= 100 && id < 109) {
            put(settings_, L"mode", static_cast<double>(id - 100));
            persist();
            rebuild();
        } else if (id >= 3000 &&
                   static_cast<unsigned>(id - 3000) < state_.GetNamedArray(L"profiles").Size()) {
            settings_ = copy(profiles_at(id - 3000).GetNamedObject(L"settings"));
            persist(true);
            rebuild();
        }
    }
    void scroll_to(int target) {
        SCROLLINFO info{};
        info.cbSize = sizeof(info);
        info.fMask = SIF_POS;
        info.nPos = target;
        SetScrollInfo(panel_, SB_VERT, &info, FALSE);
        ShowScrollBar(panel_, SB_VERT, FALSE);
        GetScrollInfo(panel_, SB_VERT, &info);
        int shift = scroll_position_ - info.nPos;
        scroll_position_ = info.nPos;
        for (auto child : controls_)
            if (GetParent(child) == panel_ && child != scrollbar_) {
                RECT r;
                GetWindowRect(child, &r);
                MapWindowPoints(nullptr, panel_, reinterpret_cast<POINT *>(&r), 2);
                SetWindowPos(child, nullptr, r.left, r.top + shift, 0, 0,
                             SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
            }
        if (scrollbar_) {
            SetScrollInfo(scrollbar_, SB_CTL, &info, TRUE);
            InvalidateRect(scrollbar_, nullptr, FALSE);
        }
        InvalidateRect(panel_, nullptr, FALSE);
    }
    static LRESULT CALLBACK panel_procedure(HWND window, UINT message, WPARAM w, LPARAM l) {
        HWND parent = GetParent(window);
        auto app = reinterpret_cast<App *>(GetWindowLongPtrW(parent, GWLP_USERDATA));
        if (message == WM_PAINT && app) {
            app->paint_panel();
            return 0;
        }
        if (message == WM_COMMAND || message == WM_HSCROLL || message == WM_CTLCOLORSTATIC ||
            message == WM_CTLCOLOREDIT || message == WM_CTLCOLORBTN || message == WM_DRAWITEM ||
            message == WM_MEASUREITEM || message == WM_NOTIFY)
            return SendMessageW(parent, message, w, l);
        if (message == WM_ERASEBKGND)
            return 1;
        if (message == WM_MOUSEWHEEL) {
            int steps = std::max(1, std::abs(GET_WHEEL_DELTA_WPARAM(w)) / WHEEL_DELTA);
            for (int i = 0; i < steps * 3; i++)
                SendMessageW(window, WM_VSCROLL,
                             GET_WHEEL_DELTA_WPARAM(w) > 0 ? SB_LINEUP : SB_LINEDOWN, 0);
            return 0;
        }
        if (message == WM_VSCROLL) {
            SCROLLINFO scroll{};
            scroll.cbSize = sizeof(scroll);
            scroll.fMask = SIF_ALL;
            GetScrollInfo(window, SB_VERT, &scroll);
            if (l && LOWORD(w) == SB_THUMBTRACK) {
                SCROLLINFO native{};
                native.cbSize = sizeof(native);
                native.fMask = SIF_TRACKPOS;
                GetScrollInfo(reinterpret_cast<HWND>(l), SB_CTL, &native);
                scroll.nTrackPos = native.nTrackPos;
            }
            int target = scroll.nPos;
            switch (LOWORD(w)) {
            case SB_LINEUP:
                target -= 32;
                break;
            case SB_LINEDOWN:
                target += 32;
                break;
            case SB_PAGEUP:
                target -= scroll.nPage;
                break;
            case SB_PAGEDOWN:
                target += scroll.nPage;
                break;
            case SB_TOP:
                target = 0;
                break;
            case SB_BOTTOM:
                target = scroll.nMax;
                break;
            case SB_THUMBTRACK:
                target = scroll.nTrackPos;
                break;
            }
            if (app)
                app->scroll_to(target);
            return 0;
        }
        return DefWindowProcW(window, message, w, l);
    }
    void paint_control(HWND child) {
        auto found = views_.find(child);
        if (found == views_.end())
            return;
        auto const &v = found->second;
        visual::Paint paint(child);
        visual::Canvas c(paint.dc(), scale_);
        visual::Palette p(dark_);
        RECT pixels;
        GetClientRect(child, &pixels);
        float w = static_cast<float>(pixels.right / scale_),
              h = static_cast<float>(pixels.bottom / scale_);
        c.fill({0, 0, w, h},
               v.canvas ? p.canvas
               : v.root
                   ? (v.kind == ControlView::Navigation || GetDlgCtrlID(child) == 61 ? p.sidebar
                                                                                     : p.canvas)
                   : p.card);
        auto text = window_text(child);
        bool focused = GetFocus() == child;
        if (v.kind == ControlView::Label) {
            auto color = v.accent ? p.accent : v.size <= 11 ? p.secondary : p.text;
            if (v.icon >= 0)
                c.icon(v.icon, 2, 2, 20, p.accent);
            else
                c.text(text, {0, 0, w, h}, v.size, color, v.bold, v.alignment, h > 28);
        } else if (v.kind == ControlView::Navigation) {
            bool selected = GetDlgCtrlID(child) == 200 + page_;
            c.round({0, 0, w, h}, 10, selected ? p.selection : v.hover ? p.tile : p.sidebar);
            c.icon(v.icon, 12, 12, 17, selected ? p.accent : p.secondary);
            c.text(text, {41, 0, w - 47, h}, 13, selected ? p.accent : p.secondary, selected);
        } else if (v.kind == ControlView::Mode) {
            bool selected =
                GetDlgCtrlID(child) == 100 + static_cast<int>(number(settings_, L"mode"));
            c.round({.5f, .5f, w - 1, h - 1}, 12, selected ? p.selection : p.tile,
                    selected ? p.accent : p.border);
            c.icon(v.icon, 14, (h - 24) / 2, 24, selected ? p.accent : p.secondary);
            auto split = text.find(L'\n');
            c.text(text.substr(0, split), {50, 12, w - 58, 22}, 12, p.text, true);
            if (split != std::wstring::npos)
                c.text(text.substr(split + 1), {50, 33, w - 58, 22}, 10, p.secondary);
        } else if (v.kind == ControlView::Swatch) {
            if (GetDlgCtrlID(child) >= 80 && GetDlgCtrlID(child) < 85)
                c.ellipse({1, 1, w - 2, h - 2}, v.swatch);
            else
                c.round({1, 1, w - 2, h - 2}, 6, v.swatch, p.border);
        } else if (v.kind == ControlView::Toggle) {
            bool on = SendMessageW(child, BM_GETCHECK, 0, 0) == BST_CHECKED;
            c.text(text, {0, 0, w - 50, h}, 12, IsWindowEnabled(child) ? p.text : p.secondary);
            c.round({w - 42, (h - 22) / 2, 40, 22}, 11, on ? p.selection : p.border);
            c.ellipse({w - 40 + (on ? 18.f : 0.f), (h - 18) / 2, 18, 18},
                      on ? p.text : p.secondary);
        } else if (v.kind == ControlView::Slider) {
            RECT channel, thumb;
            SendMessageW(child, TBM_GETCHANNELRECT, 0, reinterpret_cast<LPARAM>(&channel));
            SendMessageW(child, TBM_GETTHUMBRECT, 0, reinterpret_cast<LPARAM>(&thumb));
            float left = static_cast<float>(channel.left / scale_),
                  right = static_cast<float>(channel.right / scale_);
            float center = static_cast<float>((thumb.left + thumb.right) / (2 * scale_));
            auto rail = dark_ ? visual::Color(66, 67, 72) : visual::Color(208, 209, 215);
            c.round({left, h / 2 - 2, right - left, 4}, 2, rail);
            for (float x = left + 2; x < right; x += 8)
                c.ellipse({x, h / 2 + 6, 1.4f, 1.4f}, p.border);
            c.ellipse({center - 8, h / 2 - 8, 16, 16},
                      IsWindowEnabled(child) ? p.text : p.secondary);
        } else if (v.kind == ControlView::Scrollbar) {
            SCROLLBARINFO info{};
            info.cbSize = sizeof(info);
            if (GetScrollBarInfo(child, OBJID_CLIENT, &info)) {
                c.round({3, static_cast<float>(info.xyThumbTop / scale_), 4,
                         static_cast<float>((info.xyThumbBottom - info.xyThumbTop) / scale_)},
                        2, dark_ ? visual::Color(80, 81, 88) : visual::Color(176, 177, 184));
            }
        } else if (v.kind == ControlView::Combo) {
            c.round({.5f, .5f, w - 1, h - 1}, 6, p.tile, p.border);
            c.text(text, {10, 0, w - 34, h}, 12, p.text);
            c.line(w - 20, h / 2 - 2, w - 16, h / 2 + 2, p.secondary);
            c.line(w - 16, h / 2 + 2, w - 12, h / 2 - 2, p.secondary);
        } else {
            bool plain = GetDlgCtrlID(child) == 61;
            bool color_button = GetDlgCtrlID(child) == 30 || GetDlgCtrlID(child) == 31;
            auto color = v.bold ? p.selection : v.hover ? p.border : p.tile;
            if (!plain)
                c.round({.5f, .5f, w - 1, h - 1}, 6, color, p.border);
            if (color_button)
                c.round({w - 39, 5, 30, h - 10}, 5, v.swatch, p.border);
            if (v.icon >= 0)
                c.icon(v.icon, 10, (h - 16) / 2, 16, p.secondary);
            if (v.icon != 22)
                c.text(text, {v.icon >= 0 ? 32.f : 8.f, 0, w - (v.icon >= 0 ? 40.f : 16.f), h},
                       plain ? 10.f : 12.f,
                       plain    ? p.secondary
                       : v.bold ? p.accent
                                : p.text,
                       false, Gdiplus::StringAlignmentCenter);
        }
        if (focused && !(SendMessageW(child, WM_QUERYUISTATE, 0, 0) & UISF_HIDEFOCUS))
            c.round({1.5f, 1.5f, w - 3, h - 3}, 5, visual::Color(0, 0, 0, 0), p.accent);
    }
    void paint_monitor(visual::Canvas &c) {
        if (monitor_.Width == 0)
            return;
        auto box = monitor_;
        visual::Palette p(dark_);
        bool live = status_.connected && boolean(settings_, L"enabled");
        auto color = [&](int index) {
            if (!boolean(settings_, L"enabled"))
                return visual::Color(20, 20, 22);
            if (!live)
                return visual::Color(61, 61, 65);
            auto pixel = status_.packet.data() + 6 + index * 3;
            return visual::Color(pixel[0], pixel[1], pixel[2]);
        };
        // Layered translucent rounded contours approximate the Mac's soft glow.
        if (live)
            for (int i = 18; i > 0; i--) {
                auto glow = color(35);
                visual::Color transparent(2, glow.GetR(), glow.GetG(), glow.GetB());
                c.round({box.X - i * 1.5f, box.Y - i, box.Width + i * 3, box.Height + i * 2}, 20,
                        transparent);
            }
        c.round(box, 16, visual::Color(8, 9, 11), visual::Color(55, 55, 58));
        c.round({box.X + 22, box.Y + 22, box.Width - 44, box.Height - 44}, 8,
                visual::Color(10, 11, 14));
        float gap = 2, step = (box.Width - 24) / 41;
        for (int i = 0; i < 41; i++) {
            c.round({box.X + 12 + i * step, box.Y + 12, step - gap, 4}, 2, color(15 + i));
            c.round({box.X + 12 + i * step, box.GetBottom() - 16, step - gap, 4}, 2,
                    color(111 - i));
        }
        float vertical = (box.Height - 48) / 15;
        for (int i = 0; i < 15; i++) {
            c.round({box.X + 12, box.Y + 24 + i * vertical, 4, vertical - gap}, 2, color(14 - i));
            c.round({box.GetRight() - 16, box.Y + 24 + i * vertical, 4, vertical - gap}, 2,
                    color(56 + i));
        }
        c.icon(0, box.X + box.Width / 2 - 16, box.Y + 53, 32, visual::Color(125, 126, 132));
        c.text(L"Glowline", {box.X, box.Y + 91, box.Width, 40}, 23, visual::Color(237, 237, 241),
               false, Gdiplus::StringAlignmentCenter);
        c.text(tr(L"preview.live"), {box.X, box.Y + 130, box.Width, 28}, 10,
               visual::Color(125, 125, 132), false, Gdiplus::StringAlignmentCenter);
    }
    void paint_panel() {
        visual::Paint paint(panel_);
        visual::Canvas c(paint.dc(), scale_);
        visual::Palette p(dark_);
        RECT rect;
        GetClientRect(panel_, &rect);
        c.fill({0, 0, static_cast<float>(rect.right / scale_),
                static_cast<float>(rect.bottom / scale_)},
               p.canvas);
        c.graphics().TranslateTransform(0, static_cast<float>(-scroll_position_ / scale_));
        for (auto const &card : cards_) {
            c.round(card.box, 16, p.card, p.border);
            c.icon(card.icon, card.box.X + 22, card.box.Y + 24, 16, p.secondary);
            c.text(card.title, {card.box.X + 48, card.box.Y + 19, card.box.Width - 70, 26}, 14,
                   p.text, true);
        }
        paint_monitor(c);
        if (stats_y_ >= 0) {
            auto mode = static_cast<int>(number(settings_, L"mode"));
            std::wstring values[] = {
                tr((L"mode." + std::to_wstring(mode)).c_str()),
                format(find(setting_fields(), L"brightness"),
                       boolean(settings_, L"enabled") ? status_.brightness : 0, false),
                format(find(setting_fields(), L"warmth"), number(settings_, L"warmth"), false)};
            const wchar_t *titles[] = {L"stat.mode", L"stat.brightness", L"stat.warmth"};
            int icons[] = {mode, 16, 17};
            float width = (body_width_ - 24) / 3.f;
            for (int i = 0; i < 3; i++) {
                float x = body_x_ + i * (width + 12), y = static_cast<float>(stats_y_);
                c.round({x, y, width, 66}, 12, p.card);
                c.icon(icons[i], x + 18, y + 23, 20, p.accent);
                c.text(tr(titles[i]), {x + 48, y + 11, width - 60, 20}, 10, p.secondary);
                c.text(values[i], {x + 48, y + 31, width - 60, 24}, 14, p.text, true);
            }
        }
        if (depth_.Width > 0)
            c.depth_preview(depth_, static_cast<float>(number(settings_, L"edgeDepth")), p,
                            tr(L"capture.preview"));
    }
    void paint() {
        visual::Paint paint(window_);
        visual::Canvas c(paint.dc(), scale_);
        visual::Palette p(dark_);
        RECT rect;
        GetClientRect(window_, &rect);
        float w = static_cast<float>(rect.right / scale_),
              h = static_cast<float>(rect.bottom / scale_);
        c.fill({0, 0, w, h}, p.canvas);
        c.fill({0, 0, 220, h}, p.sidebar);
        c.line(220, 0, 220, h, p.border, 1);
        c.line(220, 78, w, 78, p.border, 1);
        c.brand(24, 25, p.accent);
        c.text(L"Glowline", {67, 20, 140, 34}, 23, p.text, true);
        c.text(tr(L"brand.subtitle"), {67, 51, 140, 20}, 10, p.secondary);
        const wchar_t *keys[] = {L"overview", L"color",    L"schedule", L"capture",
                                 L"effects",  L"profiles", L"app"};
        c.text(tr((std::wstring(L"page.") + keys[page_]).c_str()), {248, 8, w - 480, 35}, 25,
               p.text, true);
        c.text(tr((std::wstring(L"subtitle.") + keys[page_]).c_str()), {248, 43, w - 500, 24}, 12,
               p.secondary);
        auto mode = static_cast<int>(number(settings_, L"mode"));
        auto rate = status_.connected
                        ? std::to_wstring(static_cast<int>(std::lround(status_.fps))) + L" FPS"
                        : tr(L"status.static");
        c.text(tr((L"mode." + std::to_wstring(mode)).c_str()) + L" · " + rate,
               {w - 310, 45, 282, 22}, 10, p.secondary, false, Gdiplus::StringAlignmentFar);
        float y = h - 174;
        c.round({20, y, 180, 116}, 12,
                dark_ ? visual::Color(39, 39, 40) : visual::Color(226, 226, 230));
        c.ellipse({34, y + 17, 6, 6}, status_.connected ? visual::Color(55, 204, 98) : p.accent);
        c.text(tr(status_.connected ? L"status.connected" : L"status.waiting"),
               {48, y + 9, 140, 23}, 10, p.text, true);
        c.text(L"SK0L34 · 112 LED", {34, y + 40, 152, 22}, 10, p.secondary);
        c.text(tr(L"sidebar.power"), {34, y + 68, 152, 40}, 10, p.secondary, false,
               Gdiplus::StringAlignmentNear, true);
    }

  public:
    explicit App(bool testing = false) : testing_(testing) {
        if (testing_) {
            wchar_t temp[MAX_PATH];
            GetTempPathW(MAX_PATH, temp);
            path_ = std::filesystem::path(temp) /
                    (L"Glowline-ui-test-" + std::to_wstring(GetCurrentProcessId()) + L".json");
        } else
            path_ = state_path();
        state_ = default_state();
        if (!testing_ && std::filesystem::exists(path_)) {
            try {
                state_ = decode_state(read_text(path_));
            } catch (...) {
                std::string bytes;
                if (std::filesystem::file_size(path_) < 1000000)
                    bytes = read_text(path_);
                // A future schema must stay untouched, including on application exit.
                JsonObject source{nullptr};
                try {
                    source = JsonObject::Parse(winrt::to_hstring(bytes));
                } catch (...) {
                }
                if (source && source.HasKey(L"schemaVersion") &&
                    source.Lookup(L"schemaVersion").ValueType() == JsonValueType::Number &&
                    source.GetNamedNumber(L"schemaVersion") > 1)
                    throw std::runtime_error(
                        "Settings were written by a newer Glowline; update the application");
                auto backup = path_;
                backup += L".corrupt-" + std::to_wstring(GetTickCount64());
                std::filesystem::copy_file(path_, backup);
                notice_ = ui::backup_note;
            }
        }
        settings_ = state_.GetNamedObject(L"settings");
        if (testing_) {
            put(settings_, L"mode", 1.);
            put(settings_, L"launchAtLogin", false);
        }
        runtime_ = std::make_unique<Runtime>(settings_);
    }
    ~App() {
        runtime_.reset();
        if (testing_) {
            std::error_code ignored;
            std::filesystem::remove(path_, ignored);
        }
        if (background_)
            DeleteObject(background_);
        if (font_)
            DeleteObject(font_);
    }
    LRESULT message(UINT msg, WPARAM w, LPARAM l) {
        if (msg == taskbar_created_) {
            Shell_NotifyIconW(NIM_ADD, &tray_);
            return 0;
        }
        switch (msg) {
        case WM_CREATE: {
            scale_ = GetDpiForWindow(window_) / 96.;
            font_ = CreateFontW(-px(12), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
            WNDCLASSW panel_class{};
            panel_class.lpfnWndProc = panel_procedure;
            panel_class.hInstance = GetModuleHandleW(nullptr);
            panel_class.lpszClassName = L"GlowlineSettingsPanel";
            panel_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
            RegisterClassW(&panel_class);
            RECT client;
            GetClientRect(window_, &client);
            panel_ = CreateWindowExW(WS_EX_CONTROLPARENT, panel_class.lpszClassName, L"",
                                     WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN, px(220), px(78),
                                     client.right - px(220),
                                     std::max(0, static_cast<int>(client.bottom) - px(78)), window_,
                                     nullptr, panel_class.hInstance, nullptr);
            if (!panel_)
                winrt::throw_last_error();
            rebuild();
            tray_.cbSize = sizeof(tray_);
            tray_.hWnd = window_;
            tray_.uID = 1;
            tray_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
            tray_.uCallbackMessage = WM_APP + 1;
            tray_.hIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(1));
            if (!tray_.hIcon)
                tray_.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
            wcscpy_s(tray_.szTip, ui::title);
            Shell_NotifyIconW(NIM_ADD, &tray_);
            WTSRegisterSessionNotification(window_, NOTIFY_FOR_THIS_SESSION);
            SetTimer(window_, 1, 200, nullptr);
            if (!testing_) {
                try {
                    login_item(boolean(settings_, L"launchAtLogin"));
                } catch (...) {
                    notice_ = current_error();
                }
            }
            return 0;
        }
        case WM_COMMAND:
            command(LOWORD(w), HIWORD(w));
            return 0;
        case WM_HSCROLL:
            for (size_t i = 0; i < bindings_.size(); i++)
                if (bindings_[i].slider == reinterpret_cast<HWND>(l)) {
                    change_field(i, true);
                    break;
                }
            return 0;
        case WM_MEASUREITEM: {
            auto item = reinterpret_cast<MEASUREITEMSTRUCT *>(l);
            if (item->CtlType == ODT_COMBOBOX) {
                item->itemHeight = px(29);
                return TRUE;
            }
            break;
        }
        case WM_DRAWITEM: {
            auto item = reinterpret_cast<DRAWITEMSTRUCT *>(l);
            if (item->CtlType != ODT_COMBOBOX)
                return FALSE;
            visual::Canvas c(item->hDC, scale_);
            visual::Palette p(dark_);
            visual::RectF r(static_cast<float>(item->rcItem.left / scale_),
                            static_cast<float>(item->rcItem.top / scale_),
                            static_cast<float>((item->rcItem.right - item->rcItem.left) / scale_),
                            static_cast<float>((item->rcItem.bottom - item->rcItem.top) / scale_));
            c.fill(r, (item->itemState & ODS_SELECTED) ? p.selection : p.card);
            std::wstring text;
            if (item->itemID != static_cast<UINT>(-1)) {
                auto n = SendMessageW(item->hwndItem, CB_GETLBTEXTLEN, item->itemID, 0);
                if (n != CB_ERR) {
                    text.resize(n + 1);
                    SendMessageW(item->hwndItem, CB_GETLBTEXT, item->itemID,
                                 reinterpret_cast<LPARAM>(text.data()));
                    text.resize(n);
                }
            }
            r.X += 10;
            r.Width -= 20;
            c.text(text, r, 12, p.text);
            return TRUE;
        }
        case WM_NOTIFY:
            return 0;
        case WM_TIMER:
            if (runtime_)
                status_ = runtime_->status();
            if (page_ == 6 && diagnostic_values_.size() == 4) {
                double values[] = {status_.fps, status_.write_ms, static_cast<double>(status_.sent),
                                   static_cast<double>(status_.captured)};
                for (int i = 0; i < 4; i++) {
                    std::wostringstream text;
                    text << std::fixed
                         << std::setprecision(i == 0   ? 2
                                              : i == 1 ? 1
                                                       : 0)
                         << values[i];
                    if (i == 1)
                        text << L" ms";
                    if (window_text(diagnostic_values_[i]) != text.str())
                        SetWindowTextW(diagnostic_values_[i], text.str().c_str());
                }
            }
            if (page_ == 6 && diagnostic_error_) {
                auto message = !notice_.empty()                ? notice_
                               : !status_.serial_error.empty() ? status_.serial_error
                                                               : status_.capture_error;
                if (window_text(diagnostic_error_) != message)
                    SetWindowTextW(diagnostic_error_, message.c_str());
            }
            if (page_ == 2 && schedule_current_) {
                auto schedule = settings_.GetNamedObject(L"brightnessSchedule");
                SYSTEMTIME time;
                GetLocalTime(&time);
                int minute = time.wHour * 60 + time.wMinute,
                    day = static_cast<int>(number(schedule, L"dayStart")),
                    night = static_cast<int>(number(schedule, L"nightStart"));
                bool active = boolean(schedule, L"enabled") && day != night;
                bool daytime = day < night ? (minute >= day && minute < night)
                                           : (minute >= day || minute < night);
                auto key = !boolean(settings_, L"enabled") ? L"schedule.off"
                           : !active                       ? L"schedule.manual"
                           : daytime                       ? L"schedule.day"
                                                           : L"schedule.night";
                auto controls = engine_controls(settings_, minute);
                auto text = tr(key) + L"  " +
                            format(find(setting_fields(), L"brightness"),
                                   controls.enabled ? controls.brightness : 0, false);
                if (window_text(schedule_current_) != text)
                    SetWindowTextW(schedule_current_, text.c_str());
            }
            InvalidateRect(window_, nullptr, FALSE);
            if (page_ == 0)
                InvalidateRect(panel_, nullptr, FALSE);
            return 0;
        case WM_PAINT:
            paint();
            return 0;
        case WM_ERASEBKGND:
            return 1;
        case WM_CTLCOLORSTATIC:
        case WM_CTLCOLOREDIT:
        case WM_CTLCOLORBTN:
            SetTextColor(reinterpret_cast<HDC>(w), dark_ ? RGB(226, 226, 231) : RGB(31, 31, 36));
            SetBkColor(reinterpret_cast<HDC>(w), dark_ ? RGB(24, 25, 29) : RGB(251, 251, 253));
            return reinterpret_cast<LRESULT>(background_);
        case WM_APP + 1:
            if (l == WM_RBUTTONUP)
                tray_menu();
            else if (l == WM_LBUTTONUP) {
                ShowWindow(window_, SW_RESTORE);
                SetForegroundWindow(window_);
            }
            return 0;
        case WM_CLOSE:
            ShowWindow(window_, SW_HIDE);
            return 0;
        case WM_QUERYENDSESSION:
            return TRUE;
        case WM_ENDSESSION:
            if (w)
                runtime_.reset();
            return 0;
        case WM_WTSSESSION_CHANGE:
            if (!runtime_)
                return 0;
            if (w == WTS_SESSION_LOCK || w == WTS_CONSOLE_DISCONNECT || w == WTS_REMOTE_DISCONNECT)
                runtime_->suspend(true);
            else if (w == WTS_SESSION_UNLOCK || w == WTS_CONSOLE_CONNECT || w == WTS_REMOTE_CONNECT)
                runtime_->suspend(false);
            return 0;
        case WM_POWERBROADCAST:
            if (!runtime_)
                return TRUE;
            if (w == PBT_APMSUSPEND)
                runtime_->suspend(true);
            else if (w == PBT_APMRESUMEAUTOMATIC)
                runtime_->suspend(false);
            return TRUE;
        case WM_SETTINGCHANGE:
            theme();
            return 0;
        case WM_ENTERSIZEMOVE:
            resizing_ = true;
            return 0;
        case WM_SIZE: {
            if (w == SIZE_MINIMIZED)
                return 0;
            RECT r;
            GetClientRect(window_, &r);
            if (panel_) {
                MoveWindow(panel_, px(220), px(78), r.right - px(220),
                           std::max(0, static_cast<int>(r.bottom) - px(78)), TRUE);
                if (!resizing_ && !building_)
                    rebuild();
            }
            InvalidateRect(window_, nullptr, TRUE);
            return 0;
        }
        case WM_EXITSIZEMOVE:
            resizing_ = false;
            rebuild();
            return 0;
        case WM_DPICHANGED: {
            scale_ = HIWORD(w) / 96.;
            if (font_)
                DeleteObject(font_);
            font_ = CreateFontW(-px(12), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
            auto rect = reinterpret_cast<RECT *>(l);
            SetWindowPos(window_, nullptr, rect->left, rect->top, rect->right - rect->left,
                         rect->bottom - rect->top, SWP_NOZORDER | SWP_NOACTIVATE);
            rebuild();
            return 0;
        }
        case WM_GETMINMAXINFO:
            reinterpret_cast<MINMAXINFO *>(l)->ptMinTrackSize = {px(980), px(690)};
            return 0;
        case WM_DESTROY:
            KillTimer(window_, 1);
            WTSUnRegisterSessionNotification(window_);
            Shell_NotifyIconW(NIM_DELETE, &tray_);
            PostQuitMessage(0);
            return 0;
        }
        return DefWindowProcW(window_, msg, w, l);
    }
    static LRESULT CALLBACK procedure(HWND window, UINT msg, WPARAM w, LPARAM l) {
        App *app = reinterpret_cast<App *>(GetWindowLongPtrW(window, GWLP_USERDATA));
        if (msg == WM_NCCREATE) {
            app = static_cast<App *>(reinterpret_cast<CREATESTRUCTW *>(l)->lpCreateParams);
            app->window_ = window;
            SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(app));
        }
        if (app) {
            try {
                return app->message(msg, w, l);
            } catch (...) {
                auto error = current_error();
                if (msg == WM_CREATE) {
                    app->initialization_error_ = error;
                    return -1;
                }
                app->error(error);
                return 0;
            }
        }
        return DefWindowProcW(window, msg, w, l);
    }
    int run(bool startup, bool verify = true) {
        WNDCLASSW cls{};
        cls.lpfnWndProc = procedure;
        cls.hInstance = GetModuleHandleW(nullptr);
        cls.lpszClassName = L"GlowlineWindow";
        cls.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        cls.hIcon = LoadIconW(cls.hInstance, MAKEINTRESOURCEW(1));
        RegisterClassW(&cls);
        double initial_scale = GetDpiForSystem() / 96.;
        RECT desktop;
        SystemParametersInfoW(SPI_GETWORKAREA, 0, &desktop, 0);
        int initial_width = std::min(static_cast<int>(1180 * initial_scale),
                                     static_cast<int>(desktop.right - desktop.left));
        int initial_height = std::min(static_cast<int>(1000 * initial_scale),
                                      static_cast<int>(desktop.bottom - desktop.top));
        HWND window =
            CreateWindowExW(0, cls.lpszClassName, ui::title, WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
                            desktop.left + (desktop.right - desktop.left - initial_width) / 2,
                            desktop.top + (desktop.bottom - desktop.top - initial_height) / 2,
                            initial_width, initial_height, nullptr, nullptr, cls.hInstance, this);
        if (!window) {
            if (!initialization_error_.empty())
                throw std::runtime_error(winrt::to_string(initialization_error_));
            winrt::throw_last_error();
        }
        if (!startup || !boolean(settings_, L"startHidden"))
            ShowWindow(window, SW_SHOW);
        if (testing_ && verify) {
            try {
                RECT bounds;
                GetWindowRect(window, &bounds);
                if (bounds.left < desktop.left || bounds.top < desktop.top ||
                    bounds.right > desktop.right || bounds.bottom > desktop.bottom)
                    throw std::runtime_error("Initial window extends beyond the work area");
                for (int page = 0; page < 7; page++) {
                    SendMessageW(GetDlgItem(window_, 200 + page), BM_CLICK, 0, 0);
                    if (page_ != page)
                        throw std::runtime_error("Sidebar button did not navigate");
                }
                page_ = 4;
                scroll_position_ = 0;
                rebuild();
                for (int mode = 0; mode < 9; mode++) {
                    SendMessageW(GetDlgItem(panel_, 100 + mode), BM_CLICK, 0, 0);
                    if (number(settings_, L"mode") != mode)
                        throw std::runtime_error("Mode tile did not select");
                }
                put(settings_, L"mode", 1.);
                persist();
                for (auto theme : {L"dark", L"system", L"light", L"system", L"dark"}) {
                    put(settings_, L"theme", std::wstring(theme));
                    rebuild();
                    if (std::wstring(theme) == L"light" && dark_)
                        throw std::runtime_error("Light theme did not apply");
                    if (std::wstring(theme) == L"dark" && !dark_)
                        throw std::runtime_error("Dark theme did not apply");
                }
                for (int page = 0; page < 7; page++) {
                    page_ = page;
                    rebuild();
                    UpdateWindow(window_);
                    if (controls_.empty())
                        throw std::runtime_error("Empty settings page");
                }
                auto base = copy(settings_);
                auto binding_index = [&](std::wstring const &key) {
                    auto found = std::find_if(bindings_.begin(), bindings_.end(),
                                              [&](auto const &b) { return key == b.field.key; });
                    if (found == bindings_.end())
                        throw std::runtime_error("Missing binding during UI audit");
                    return static_cast<size_t>(found - bindings_.begin());
                };
                auto verify_bindings = [&] {
                    std::vector<std::wstring> keys;
                    for (auto const &b : bindings_)
                        keys.push_back(b.field.key);
                    for (auto const &key : keys) {
                        auto index = binding_index(key);
                        auto descriptor = bindings_[index].field;
                        if (descriptor.type == FieldType::Boolean) {
                            bool initial = boolean(bindings_[index].object, descriptor.key);
                            SendMessageW(bindings_[index].input, BM_CLICK, 0, 0);
                            index = binding_index(key);
                            if (boolean(bindings_[index].object, descriptor.key) == initial)
                                throw std::runtime_error("Toggle did not update settings: " +
                                                         winrt::to_string(key));
                            SendMessageW(bindings_[index].input, BM_CLICK, 0, 0);
                        } else {
                            double initial = number(bindings_[index].object, descriptor.key);
                            if (bindings_[index].slider &&
                                IsWindowEnabled(bindings_[index].slider)) {
                                SliderScale scale(descriptor);
                                for (auto entry : {std::pair{VK_HOME, descriptor.minimum},
                                                   std::pair{VK_RIGHT, scale.value(1)},
                                                   std::pair{VK_END, descriptor.maximum}}) {
                                    SendMessageW(bindings_[index].slider, WM_KEYDOWN, entry.first,
                                                 0);
                                    SendMessageW(bindings_[index].slider, WM_KEYUP, entry.first, 0);
                                    if (std::abs(number(bindings_[index].object, descriptor.key) -
                                                 entry.second) > 1e-8)
                                        throw std::runtime_error(
                                            "Slider keyboard/range contract: " +
                                            winrt::to_string(key));
                                }
                            }
                            for (double value : {descriptor.minimum, descriptor.maximum, initial}) {
                                index = binding_index(key);
                                auto input = bindings_[index].input;
                                SetWindowTextW(
                                    input,
                                    format(descriptor, value, bindings_[index].time).c_str());
                                SendMessageW(panel_, WM_COMMAND,
                                             MAKEWPARAM(1000 + index, EN_KILLFOCUS),
                                             reinterpret_cast<LPARAM>(input));
                                index = binding_index(key);
                                if (std::abs(number(bindings_[index].object, descriptor.key) -
                                             value) > 1e-8)
                                    throw std::runtime_error(
                                        "Formatted setting did not round trip: " +
                                        winrt::to_string(key));
                            }
                        }
                    }
                    // Setting changes must survive a disk round trip with the same schema.
                    decode_state(read_text(path_));
                    for (size_t i = 0; i < controls_.size(); i++)
                        for (size_t j = i + 1; j < controls_.size(); j++) {
                            auto a = controls_[i], b = controls_[j];
                            if (GetParent(a) != panel_ || GetParent(b) != panel_ ||
                                a == scrollbar_ || b == scrollbar_)
                                continue;
                            RECT ar, br, intersection;
                            GetWindowRect(a, &ar);
                            GetWindowRect(b, &br);
                            if (IntersectRect(&intersection, &ar, &br))
                                throw std::runtime_error(
                                    "Settings controls overlap on page " + std::to_string(page_) +
                                    " IDs " + std::to_string(GetDlgCtrlID(a)) + "/" +
                                    std::to_string(GetDlgCtrlID(b)) + " text " +
                                    winrt::to_string(window_text(a)) + "/" +
                                    winrt::to_string(window_text(b)));
                        }
                };
                for (int page = 0; page < 7; page++) {
                    settings_ = copy(base);
                    put(settings_.GetNamedObject(L"brightnessSchedule"), L"enabled", false);
                    page_ = page;
                    scroll_position_ = 0;
                    rebuild();
                    verify_bindings();
                }
                for (int mode = 0; mode < 9; mode++) {
                    settings_ = copy(base);
                    put(settings_, L"mode", static_cast<double>(mode));
                    page_ = 4;
                    scroll_position_ = 0;
                    rebuild();
                    verify_bindings();
                }
                RECT original_window;
                GetWindowRect(window_, &original_window);
                SetWindowPos(window_, nullptr, 0, 0, px(980), px(690), SWP_NOMOVE | SWP_NOZORDER);
                for (auto theme : {L"dark", L"light"})
                    for (int page = 0; page < 7; page++) {
                        settings_ = copy(base);
                        put(settings_, L"theme", std::wstring(theme));
                        put(settings_.GetNamedObject(L"brightnessSchedule"), L"enabled", false);
                        page_ = page;
                        scroll_position_ = 0;
                        rebuild();
                        verify_bindings();
                    }
                SetWindowPos(window_, nullptr, 0, 0, original_window.right - original_window.left,
                             original_window.bottom - original_window.top,
                             SWP_NOMOVE | SWP_NOZORDER);
                settings_ = copy(base);
                page_ = 3;
                rebuild();
                for (int i = 0; i < 6; i++) {
                    auto combo = GetDlgItem(panel_, 24);
                    SendMessageW(combo, CB_SETCURSEL, i, 0);
                    SendMessageW(panel_, WM_COMMAND, MAKEWPARAM(24, CBN_SELCHANGE),
                                 reinterpret_cast<LPARAM>(combo));
                    const int rates[] = {30, 60, 90, 120, 144, 240};
                    if (number(settings_, L"captureFps") != rates[i])
                        throw std::runtime_error("Capture rate picker did not persist");
                }
                verify_bindings();
                auto offset = binding_index(L"offset");
                SetWindowTextW(bindings_[offset].input, L"0");
                change_field(offset, false);
                SendMessageW(GetDlgItem(panel_, 27), BM_CLICK, 0, 0);
                if (number(settings_, L"offset") != 1)
                    throw std::runtime_error("Offset increment failed");
                SendMessageW(GetDlgItem(panel_, 26), BM_CLICK, 0, 0);
                if (number(settings_, L"offset") != 0)
                    throw std::runtime_error("Offset decrement failed");
                for (auto invalid : {L"112", L"-112", L"1.5", L"nan", L"abc"}) {
                    SetWindowTextW(bindings_[offset].input, invalid);
                    bool rejected = false;
                    try {
                        change_field(offset, false);
                    } catch (std::exception const &) {
                        rejected = true;
                    }
                    if (!rejected || number(settings_, L"offset") != 0)
                        throw std::runtime_error("Invalid input changed a setting");
                }
                SetWindowTextW(bindings_[offset].input, L"0");
                settings_ = copy(base);
                put(settings_, L"captureFps", 150.);
                rebuild();
                if (SendMessageW(GetDlgItem(panel_, 24), CB_GETCURSEL, 0, 0) != 6 ||
                    number(settings_, L"captureFps") != 150)
                    throw std::runtime_error("Imported custom capture rate was hidden");
                settings_ = copy(base);
                persist();
                page_ = 6;
                rebuild();
                notice_ = L"Diagnostic update contract";
                SendMessageW(window_, WM_TIMER, 1, 0);
                if (window_text(diagnostic_error_) != notice_)
                    throw std::runtime_error("Diagnostic notice did not update live");
                notice_.clear();
                for (int id = 70; id <= 72; id++) {
                    SendMessageW(GetDlgItem(panel_, id), BM_CLICK, 0, 0);
                    const wchar_t *names[] = {L"dark", L"light", L"system"};
                    if (string(settings_, L"theme") != names[id - 70])
                        throw std::runtime_error("Theme button did not persist");
                }
                settings_ = copy(base);
                page_ = 4;
                put(settings_, L"mode", 1.);
                rebuild();
                for (int i = 0; i < 5; i++) {
                    SendMessageW(GetDlgItem(panel_, 80 + i), BM_CLICK, 0, 0);
                    auto controls = engine_controls(settings_, 480);
                    auto expected = preset(i);
                    if (controls.primary[0] != expected.GetR() ||
                        controls.primary[1] != expected.GetG() ||
                        controls.primary[2] != expected.GetB())
                        throw std::runtime_error("Color preset did not reach the engine");
                }
                for (int mode : {3, 7}) {
                    command(100 + mode, 0);
                    auto index = binding_index(L"speed");
                    SetWindowTextW(bindings_[index].input, mode == 3 ? L"0.7×" : L"1.8×");
                    change_field(index, false);
                }
                command(103, 0);
                if (std::abs(number(active_effect(settings_), L"speed") - .7) > 1e-8)
                    throw std::runtime_error("Per-mode speed was overwritten");
                command(107, 0);
                if (std::abs(number(active_effect(settings_), L"speed") - 1.8) > 1e-8)
                    throw std::runtime_error("Per-mode speed was not independent");
                settings_ = copy(base);
                persist();

                page_ = 3;
                scroll_position_ = 0;
                rebuild();
                scroll_to(100000);
                if (scroll_position_ <= 0)
                    throw std::runtime_error("Long page did not scroll");
                scroll_to(0);
                SetFocus(bindings_.back().input);
                RECT focused, viewport;
                GetWindowRect(bindings_.back().input, &focused);
                GetWindowRect(panel_, &viewport);
                if (scroll_position_ <= 0 || focused.bottom > viewport.bottom ||
                    focused.top < viewport.top)
                    throw std::runtime_error("Keyboard focus did not reveal the field");
                scroll_position_ = 0;
                page_ = 1;
                rebuild();
                auto &brightness =
                    *std::find_if(bindings_.begin(), bindings_.end(), [](auto const &b) {
                        return std::wstring(b.field.key) == L"brightness";
                    });
                SetWindowTextW(brightness.input, L"0.37");
                change_field(static_cast<size_t>(&brightness - bindings_.data()), false);
                auto restored = decode_state(read_text(path_));
                if (number(restored.GetNamedObject(L"settings"), L"brightness") != .37)
                    throw std::runtime_error("UI edit did not persist");
                page_ = 5;
                rebuild();
                SetWindowTextW(name_, L"UI contract");
                SetFocus(name_);
                MSG enter{};
                enter.hwnd = name_;
                enter.message = WM_KEYDOWN;
                enter.wParam = VK_RETURN;
                if (!IsDialogMessageW(window_, &enter))
                    SendMessageW(enter.hwnd, enter.message, enter.wParam, enter.lParam);
                if (state_.GetNamedArray(L"profiles").Size() != 1)
                    throw std::runtime_error("UI profile was not saved");
                SetWindowTextW(name_, L"ui CONTRACT");
                profile(44);
                if (state_.GetNamedArray(L"profiles").Size() != 1)
                    throw std::runtime_error("Same-name profile save duplicated the profile");
                put(settings_, L"brightness", .81);
                persist();
                page_ = 5;
                rebuild();
                profile(42);
                if (number(settings_, L"brightness") != .37)
                    throw std::runtime_error("UI profile did not restore");
                auto await_output = [&](bool enabled) {
                    auto deadline = GetTickCount64() + 5000;
                    do {
                        auto state = runtime_->status();
                        bool lit = std::any_of(state.packet.begin() + 6, state.packet.end(),
                                               [](uint8_t value) { return value != 0; });
                        if (lit == enabled)
                            return;
                        Sleep(5);
                    } while (GetTickCount64() < deadline);
                    throw std::runtime_error("Runtime preview did not reach requested state");
                };
                await_output(true);
                put(settings_, L"enabled", false);
                persist();
                await_output(false);
                put(settings_, L"enabled", true);
                persist();
                await_output(true);
                runtime_->suspend(true);
                await_output(false);
                runtime_->suspend(false);
                await_output(true);
                DestroyWindow(window);
                std::filesystem::remove(path_);
                return 0;
            } catch (...) {
                DestroyWindow(window);
                std::filesystem::remove(path_);
                throw;
            }
        }
        MSG msg;
        while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
            if (!IsDialogMessageW(window, &msg)) {
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
        }
        return static_cast<int>(msg.wParam);
    }
};
} // namespace glowline

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    using namespace glowline;
    winrt::init_apartment(winrt::apartment_type::single_threaded);
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    INITCOMMONCONTROLSEX controls{sizeof(controls), ICC_TAB_CLASSES | ICC_BAR_CLASSES};
    InitCommonControlsEx(&controls);
    int count = 0;
    auto args = CommandLineToArgvW(GetCommandLineW(), &count);
    std::vector<std::wstring> argv(args, args + count);
    LocalFree(args);
    try {
        visual::Session drawing;
        if (count >= 2 && argv[1] == L"--self-test") {
            run_windows_tests();
            if (count == 3)
                write_text(argv[2], "Windows settings, scheduling, effects, identity and packet "
                                    "contracts passed\n");
            return 0;
        }
        if (count == 3 && argv[1] == L"--capture-test") {
            run_capture_test();
            write_text(argv[2], "Windows Graphics Capture: red/blue frames, 344px RGBA-half, all "
                                "112 LED samples passed\n");
            return 0;
        }
        if (count == 2 && argv[1] == L"--ui-preview") {
            App app(true);
            return app.run(false, false);
        }
        if (count == 3 && argv[1] == L"--ui-test") {
            App app(true);
            app.run(false);
            write_text(
                argv[2],
                "Full UI audit: seven pages, nine effects, every binding/range/keyboard step, "
                "layout, themes, presets, profiles and suspend/resume passed\n");
            return 0;
        }
        RTL_OSVERSIONINFOW version{};
        version.dwOSVersionInfoSize = sizeof(version);
        using VersionFunction = LONG(WINAPI *)(PRTL_OSVERSIONINFOW);
        VersionFunction rtl = nullptr;
        auto address = GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion");
        static_assert(sizeof(rtl) == sizeof(address));
        memcpy(&rtl, &address, sizeof(rtl));
        if (!rtl || rtl(&version) != 0 || version.dwBuildNumber < 22000)
            throw std::runtime_error("Glowline requires Windows 11");
        HANDLE singleton = CreateMutexW(nullptr, FALSE, L"Local\\Glowline.Windows.x64");
        if (!singleton)
            winrt::throw_last_error();
        if (GetLastError() == ERROR_ALREADY_EXISTS) {
            HWND existing = FindWindowW(L"GlowlineWindow", nullptr);
            if (existing) {
                ShowWindow(existing, SW_RESTORE);
                SetForegroundWindow(existing);
            }
            CloseHandle(singleton);
            return 0;
        }
        App app;
        int result = app.run(count >= 2 && argv[1] == L"--startup");
        CloseHandle(singleton);
        return result;
    } catch (...) {
        auto error = current_error();
        if (count >= 3 && (argv[1] == L"--self-test" || argv[1] == L"--capture-test" ||
                           argv[1] == L"--ui-test")) {
            try {
                write_text(argv[2], winrt::to_string(error));
            } catch (...) {
            }
            return 1;
        }
        MessageBoxW(nullptr, error.c_str(), ui::error, MB_OK | MB_ICONERROR);
        return 1;
    }
}
