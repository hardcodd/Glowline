#ifndef SKYDIMO_PLUGIN_C_API_H
#define SKYDIMO_PLUGIN_C_API_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define SKYDIMO_EXPORT __declspec(dllexport)
#else
#define SKYDIMO_EXPORT __attribute__((visibility("default")))
#endif

#define SKYDIMO_NATIVE_C_ABI_MIN_VERSION 2u
#define SKYDIMO_NATIVE_C_ABI_VERSION 3u
#define SKYDIMO_NATIVE_C_ABI "skydimo-native-c-v3"
#define SKYDIMO_EFFECT_C_ABI "skydimo-effect-c-v3"
#define SKYDIMO_CONTROLLER_C_ABI "skydimo-controller-c-v3"
#define SKYDIMO_EXTENSION_C_ABI "skydimo-extension-c-v3"

#define SKYDIMO_PLUGIN_KIND_EFFECT (1u << 0)
#define SKYDIMO_PLUGIN_KIND_CONTROLLER (1u << 1)
#define SKYDIMO_PLUGIN_KIND_EXTENSION (1u << 2)

#define SKYDIMO_LOG_TRACE 0u
#define SKYDIMO_LOG_DEBUG 1u
#define SKYDIMO_LOG_INFO 2u
#define SKYDIMO_LOG_WARN 3u
#define SKYDIMO_LOG_ERROR 4u

#define SKYDIMO_DEVICE_TYPE_LIGHT 0u
#define SKYDIMO_DEVICE_TYPE_MOTHERBOARD 1u
#define SKYDIMO_DEVICE_TYPE_DRAM 2u
#define SKYDIMO_DEVICE_TYPE_GPU 3u
#define SKYDIMO_DEVICE_TYPE_COOLER 4u
#define SKYDIMO_DEVICE_TYPE_LED_STRIP 5u
#define SKYDIMO_DEVICE_TYPE_KEYBOARD 6u
#define SKYDIMO_DEVICE_TYPE_MOUSE 7u
#define SKYDIMO_DEVICE_TYPE_MOUSE_MAT 8u
#define SKYDIMO_DEVICE_TYPE_HEADSET 9u
#define SKYDIMO_DEVICE_TYPE_HEADSET_STAND 10u
#define SKYDIMO_DEVICE_TYPE_GAMEPAD 11u
#define SKYDIMO_DEVICE_TYPE_SPEAKER 12u
#define SKYDIMO_DEVICE_TYPE_VIRTUAL 13u
#define SKYDIMO_DEVICE_TYPE_STORAGE 14u
#define SKYDIMO_DEVICE_TYPE_CASE 15u
#define SKYDIMO_DEVICE_TYPE_MICROPHONE 16u
#define SKYDIMO_DEVICE_TYPE_ACCESSORY 17u
#define SKYDIMO_DEVICE_TYPE_KEYPAD 18u
#define SKYDIMO_DEVICE_TYPE_LAPTOP 19u
#define SKYDIMO_DEVICE_TYPE_MONITOR 20u
#define SKYDIMO_DEVICE_TYPE_UNKNOWN 21u

#define SKYDIMO_SEGMENT_SINGLE 0u
#define SKYDIMO_SEGMENT_LINEAR 1u
#define SKYDIMO_SEGMENT_MATRIX 2u
#define SKYDIMO_SEGMENT_PRESET 3u

#define SKYDIMO_CANDIDATE_SERIAL 1u
#define SKYDIMO_CANDIDATE_HID 2u

typedef struct SkydimoStr {
    const char* ptr;
    size_t len;
} SkydimoStr;

typedef struct SkydimoBytes {
    const uint8_t* ptr;
    size_t len;
} SkydimoBytes;

typedef struct SkydimoBytesMut {
    uint8_t* ptr;
    size_t len;
} SkydimoBytesMut;

typedef struct SkydimoRgb {
    uint8_t r;
    uint8_t g;
    uint8_t b;
} SkydimoRgb;

typedef struct SkydimoFloatSliceV1 {
    const float* ptr;
    size_t len;
} SkydimoFloatSliceV1;

typedef struct SkydimoAudioFrameV1 {
    float amplitude;
    SkydimoFloatSliceV1 bins;
} SkydimoAudioFrameV1;

typedef struct SkydimoRgbFrameV1 {
    size_t width;
    size_t height;
    const SkydimoRgb* pixels;
    size_t pixels_len;
} SkydimoRgbFrameV1;

typedef struct SkydimoMatrixMapV1 {
    size_t width;
    size_t height;
    const int64_t* map;
    size_t map_len;
} SkydimoMatrixMapV1;

typedef struct SkydimoLayoutTransformV1 {
    uint8_t flip_horizontal;
    uint8_t flip_vertical;
} SkydimoLayoutTransformV1;

typedef struct SkydimoOutputCapabilitiesV1 {
    uint8_t editable;
    size_t min_total_leds;
    size_t max_total_leds;
    const size_t* allowed_total_leds;
    size_t allowed_total_leds_len;
} SkydimoOutputCapabilitiesV1;

typedef struct SkydimoOutputDefinitionV1 {
    SkydimoStr id;
    SkydimoStr name;
    uint32_t output_type;
    size_t leds_count;
    const SkydimoMatrixMapV1* matrix;
    SkydimoLayoutTransformV1 transform;
    SkydimoOutputCapabilitiesV1 capabilities;
    SkydimoStr default_effect;
} SkydimoOutputDefinitionV1;

typedef struct SkydimoOutputFrameV1 {
    SkydimoStr output_id;
    const SkydimoRgb* colors;
    size_t colors_len;
} SkydimoOutputFrameV1;

typedef struct SkydimoLedColorV1 {
    size_t index;
    SkydimoRgb color;
} SkydimoLedColorV1;

typedef struct SkydimoDeviceInfoV1 {
    SkydimoStr manufacturer;
    SkydimoStr model;
    SkydimoStr serial_id;
    SkydimoStr description;
    uint32_t device_type;
    SkydimoStr image_url;
    SkydimoStr controller_id;
    SkydimoStr controller_name;
    SkydimoStr device_path;
} SkydimoDeviceInfoV1;

typedef struct SkydimoHardwareCandidateV1 {
    uint32_t candidate_type;
    SkydimoStr port_key;
    SkydimoStr path;
    uint32_t vendor_id;
    uint32_t product_id;
    uint8_t has_vendor_id;
    uint8_t has_product_id;
    int32_t interface_number;
    uint8_t has_interface_number;
    SkydimoStr serial_number;
    SkydimoStr manufacturer_string;
    SkydimoStr product_string;
} SkydimoHardwareCandidateV1;

typedef struct SkydimoHostApiV1 {
    uint32_t size;
    uint32_t abi_version;
    void* host_ctx;
    void (*log)(void* host_ctx, uint32_t level, const char* ptr, size_t len);
    /*
     * Language-neutral JSON host capability calls. Prefer the typed native
     * host callbacks below for high-frequency or bulk payload operations.
     *
     * Controller methods:
     *   system.info, hid_interfaces, hid_write, hid_read,
     *   hid_send_feature_report, hid_get_feature_report,
     *   controller.register_setting, controller.get_settings,
     *   controller.trigger_setting_action
     *
     * Effect methods:
     *   hsv_to_rgb, screen.list_displays, screen.capture,
     *   audio.capture, media.album_art
     *
     * Extension methods:
     *   plugin.info, plugin.data_dir, plugin.resource_dir,
     *   system.info, page_emit, notify, register_device, lock_leds, set_leds,
     *   scope operations, tcp_*, http_*, process, hid_*
     *
     * The host writes a JSON response into response_ptr. If response_len is too
     * small, required_len receives the needed byte length and the function
     * returns a positive status. Negative status means the response JSON
     * contains an error object.
     */
    int32_t (*call_json)(
        void* host_ctx,
        const char* method_ptr,
        size_t method_len,
        const char* request_ptr,
        size_t request_len,
        uint8_t* response_ptr,
        size_t response_len,
        size_t* required_len);
    int32_t (*controller_set_device_info)(void* host_ctx, const SkydimoDeviceInfoV1* info);
    int32_t (*controller_add_output)(void* host_ctx, const SkydimoOutputDefinitionV1* output);
    size_t (*controller_output_led_count)(void* host_ctx, const char* output_id, size_t output_id_len);
    intptr_t (*controller_get_rgb_bytes)(
        void* host_ctx,
        const char* output_id,
        size_t output_id_len,
        uint8_t* out,
        size_t out_len);
    intptr_t (*controller_write)(void* host_ctx, const uint8_t* data, size_t data_len);
    intptr_t (*controller_read)(void* host_ctx, uint8_t* out, size_t out_len, uint32_t timeout_ms);
    intptr_t (*controller_hid_send_feature_report)(void* host_ctx, const uint8_t* data, size_t data_len);
    intptr_t (*controller_hid_get_feature_report)(
        void* host_ctx,
        uint8_t* out,
        size_t out_len,
        uint8_t report_id);
    int32_t (*extension_lock_leds)(
        void* host_ctx,
        const char* port_ptr,
        size_t port_len,
        const char* output_id_ptr,
        size_t output_id_len,
        const size_t* indices,
        size_t indices_len,
        size_t* locked_count,
        size_t* rejected_count);
    int32_t (*extension_unlock_leds)(
        void* host_ctx,
        const char* port_ptr,
        size_t port_len,
        const char* output_id_ptr,
        size_t output_id_len,
        const size_t* indices,
        size_t indices_len);
    int32_t (*extension_set_leds_rgb)(
        void* host_ctx,
        const char* port_ptr,
        size_t port_len,
        const char* output_id_ptr,
        size_t output_id_len,
        const SkydimoLedColorV1* colors,
        size_t colors_len);
    int32_t (*effect_audio_capture)(void* host_ctx, size_t avg_size, SkydimoAudioFrameV1* out_frame);
    int32_t (*effect_screen_capture)(void* host_ctx, size_t width, size_t height, SkydimoRgbFrameV1* out_frame);
    int32_t (*effect_album_art)(void* host_ctx, size_t width, size_t height, SkydimoRgbFrameV1* out_frame);
    int32_t (*get_plugin_id)(void* host_ctx, SkydimoStr* out_id);
} SkydimoHostApiV1;

typedef struct SkydimoEffectApiV1 {
    uint32_t size;
    int32_t (*create)(const SkydimoHostApiV1* host, void** out_instance);
    void (*destroy)(void* instance);
    int32_t (*resize)(void* instance, uint32_t width, uint32_t height, uint32_t led_count);
    int32_t (*update_params_json)(void* instance, const char* ptr, size_t len);
    int32_t (*tick)(void* instance, double elapsed_seconds, SkydimoRgb* buffer, size_t len);
    int32_t (*is_ready)(void* instance);
} SkydimoEffectApiV1;

typedef struct SkydimoControllerApiV1 {
    uint32_t size;
    int32_t (*create)(
        const SkydimoHostApiV1* host,
        const SkydimoHardwareCandidateV1* candidate,
        void** out_instance);
    void (*destroy)(void* instance);
    int32_t (*validate)(void* instance);
    int32_t (*init)(void* instance);
    int32_t (*get_device_info)(void* instance, SkydimoDeviceInfoV1* out_info);
    size_t (*get_output_count)(void* instance);
    int32_t (*get_output)(void* instance, size_t index, SkydimoOutputDefinitionV1* out_output);
    int32_t (*update)(void* instance, const SkydimoOutputFrameV1* frames, size_t frame_count);
    int32_t (*set_output_leds_count)(void* instance, const char* output_id, size_t output_id_len, size_t leds_count);
    int32_t (*update_output)(void* instance, const SkydimoOutputDefinitionV1* output);
    int32_t (*disconnect)(void* instance);
} SkydimoControllerApiV1;

typedef struct SkydimoExtensionApiV1 {
    uint32_t size;
    int32_t (*create)(const SkydimoHostApiV1* host, void** out_instance);
    void (*destroy)(void* instance);
    int32_t (*start)(void* instance);
    int32_t (*stop)(void* instance);
    int32_t (*on_scan_devices)(void* instance);
    int32_t (*on_event_json)(
        void* instance,
        const char* event_ptr,
        size_t event_len,
        const char* data_ptr,
        size_t data_len);
    int32_t (*on_page_message_json)(void* instance, const char* ptr, size_t len);
    int32_t (*on_device_frame)(
        void* instance,
        const char* port_ptr,
        size_t port_len,
        const SkydimoOutputFrameV1* frames,
        size_t frame_count);
} SkydimoExtensionApiV1;

typedef struct SkydimoPluginApiV1 {
    uint32_t size;
    uint32_t abi_version;
    uint32_t kind_mask;
    SkydimoEffectApiV1 effect;
    SkydimoControllerApiV1 controller;
    SkydimoExtensionApiV1 extension;
    void (*shutdown_plugin)(void);
} SkydimoPluginApiV1;

SKYDIMO_EXPORT int32_t skydimo_plugin_get_api(
    uint32_t requested_abi_version,
    const SkydimoHostApiV1* host,
    SkydimoPluginApiV1* out_api);

#ifdef __cplusplus
}
#endif

#endif
