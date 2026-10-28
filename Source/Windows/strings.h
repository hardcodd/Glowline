#pragma once

// Russian localization for the Windows application.
namespace glowline {
namespace ui {
constexpr wchar_t title[] = L"Glowline";
constexpr wchar_t modes[][32] = {L"Экран", L"Один цвет", L"Градиент", L"Дыхание",        L"Радуга",
                                 L"Свеча", L"Пламя",     L"Комета",   L"Северное сияние"};
constexpr wchar_t pages[][24] = {L"Обзор",      L"Эффекты", L"Цвет",      L"Лента",
                                 L"Расписание", L"Профили", L"Приложение"};
constexpr wchar_t enable[] = L"Подсветка";
constexpr wchar_t retry[] = L"Переподключить";
constexpr wchar_t refresh[] = L"Обновить устройства";
constexpr wchar_t primary[] = L"Основной цвет…";
constexpr wchar_t secondary[] = L"Второй цвет…";
constexpr wchar_t new_profile[] = L"Сохранить новый";
constexpr wchar_t apply[] = L"Применить";
constexpr wchar_t replace[] = L"Обновить профиль";
constexpr wchar_t rename[] = L"Переименовать";
constexpr wchar_t remove[] = L"Удалить";
constexpr wchar_t import_file[] = L"Импорт JSON…";
constexpr wchar_t export_file[] = L"Экспорт JSON…";
constexpr wchar_t reset[] = L"Сбросить настройки";
constexpr wchar_t quit[] = L"Выйти";
constexpr wchar_t open[] = L"Открыть Glowline";
constexpr wchar_t error[] = L"Glowline — ошибка";
constexpr wchar_t no_port[] = L"Контроллер не выбран";
constexpr wchar_t default_display[] = L"Основной экран";
constexpr wchar_t dark[] = L"Тёмная";
constexpr wchar_t light[] = L"Светлая";
constexpr wchar_t system[] = L"Как в Windows";
constexpr wchar_t schedule_note[] =
    L"Местное время Windows. При одинаковом начале дня и ночи используется ручная яркость.";
constexpr wchar_t capture_note[] =
    L"Захват экрана: Windows Graphics Capture · линейный RGB · курсор исключён.\nИзображения не "
    L"сохраняются и не передаются по сети.";
constexpr wchar_t profile_note[] =
    L"Профиль сохраняет все настройки и независимые параметры девяти режимов.";
constexpr wchar_t port_note[] =
    L"SK0L34 · 112 светодиодов · 115200 бод. Выберите COM-порт контроллера; закройте Skydimo.";
constexpr wchar_t backup_note[] = L"Файл настроек повреждён. Исходные данные сохранены рядом с "
                                  L"settings.json; загружены стандартные настройки.";
constexpr wchar_t delete_question[] = L"Удалить выбранный профиль?";
constexpr wchar_t reset_question[] =
    L"Сбросить настройки? Профили и выбранный COM-порт сохранятся.";
constexpr wchar_t name_required[] = L"Введите непустое имя профиля.";
constexpr wchar_t bad_number[] = L"Введите число в допустимом диапазоне. Время — ЧЧ:ММ.";

inline constexpr wchar_t mode_label[] = L"Режим подсветки";
inline constexpr wchar_t display_label[] = L"Захватываемый экран";
inline constexpr wchar_t screen_mode_note[] =
    L"Режим «Экран» использует настройки захвата, цвета и ленты.";
inline constexpr wchar_t theme_label[] = L"Оформление";
inline constexpr wchar_t platform_note[] = L"Windows 11 · x64 (AMD / Intel) · 112 LED";
inline constexpr wchar_t usb_connected[] = L"USB: подключён SK0L34";
inline constexpr wchar_t usb_disconnected[] = L"USB: не подключён";
inline constexpr wchar_t fps_brightness[] = L" кадров/с  ·  яркость ";
inline constexpr wchar_t capture_active[] = L"Захват: активен · линейный RGBA-half";
inline constexpr wchar_t capture_waiting[] = L"Захват: ожидает кадр";
inline constexpr wchar_t effect_active[] = L"Автономный эффект";
inline constexpr wchar_t capture_prefix[] = L"Захват: ";
inline constexpr wchar_t field_enabled[] = L"Подсветка включена";
inline constexpr wchar_t field_mode[] = L"Режим";
inline constexpr wchar_t field_brightness[] = L"Яркость";
inline constexpr wchar_t field_warmth[] = L"Теплота";
inline constexpr wchar_t field_saturation[] = L"Насыщенность";
inline constexpr wchar_t field_gamma[] = L"Гамма";
inline constexpr wchar_t field_redGain[] = L"Красный канал";
inline constexpr wchar_t field_greenGain[] = L"Зелёный канал";
inline constexpr wchar_t field_blueGain[] = L"Синий канал";
inline constexpr wchar_t field_blackThreshold[] = L"Порог чёрного";
inline constexpr wchar_t field_edgeDepth[] = L"Глубина захвата края";
inline constexpr wchar_t field_detailMode[] = L"Детализация цвета";
inline constexpr wchar_t field_releaseSeconds[] = L"Затухание, с";
inline constexpr wchar_t field_attackSeconds[] = L"Нарастание, с";
inline constexpr wchar_t field_mirrored[] = L"Зеркальная раскладка";
inline constexpr wchar_t field_offset[] = L"Смещение светодиодов";
inline constexpr wchar_t field_leftEnabled[] = L"Левая сторона";
inline constexpr wchar_t field_topEnabled[] = L"Верхняя сторона";
inline constexpr wchar_t field_rightEnabled[] = L"Правая сторона";
inline constexpr wchar_t field_bottomEnabled[] = L"Нижняя сторона";
inline constexpr wchar_t field_leftGain[] = L"Яркость слева";
inline constexpr wchar_t field_topGain[] = L"Яркость сверху";
inline constexpr wchar_t field_rightGain[] = L"Яркость справа";
inline constexpr wchar_t field_bottomGain[] = L"Яркость снизу";
inline constexpr wchar_t field_fps[] = L"Передача, кадров/с";
inline constexpr wchar_t field_captureFps[] = L"Захват, кадров/с (предел)";
inline constexpr wchar_t field_keepaliveSeconds[] = L"Повтор кадра, с";
inline constexpr wchar_t field_skipUnchanged[] = L"Пропуск одинаковых кадров";
inline constexpr wchar_t field_speed[] = L"Скорость";
inline constexpr wchar_t field_reverse[] = L"Обратное направление";
inline constexpr wchar_t field_port[] = L"Контроллер USB";
inline constexpr wchar_t field_displayID[] = L"Идентификатор macOS";
inline constexpr wchar_t field_windowsDisplay[] = L"Экран Windows";
inline constexpr wchar_t field_theme[] = L"Оформление";
inline constexpr wchar_t field_launchAtLogin[] = L"Запуск при входе";
inline constexpr wchar_t field_startHidden[] = L"Запускать в трее";
inline constexpr wchar_t field_reconnect[] = L"Восстанавливать подключение";
inline constexpr wchar_t field_offOnQuit[] = L"Гасить ленту при выходе";
inline constexpr wchar_t field_enabled_schedule[] = L"Расписание включено";
inline constexpr wchar_t field_dayStart[] = L"Начало дня";
inline constexpr wchar_t field_nightStart[] = L"Начало ночи";
inline constexpr wchar_t field_dayBrightness[] = L"Дневная яркость";
inline constexpr wchar_t field_nightBrightness[] = L"Ночная яркость";
inline constexpr wchar_t field_gradientBalance[] = L"Баланс градиента";
inline constexpr wchar_t field_breathingFloor[] = L"Минимум дыхания";
inline constexpr wchar_t field_rainbowCycles[] = L"Витки радуги";
inline constexpr wchar_t field_candleFlicker[] = L"Мерцание свечи";
inline constexpr wchar_t field_flameHeight[] = L"Высота пламени";
inline constexpr wchar_t field_cometTail[] = L"Длина шлейфа";
inline constexpr wchar_t field_auroraPink[] = L"Розовый в сиянии";
} // namespace ui
} // namespace glowline
