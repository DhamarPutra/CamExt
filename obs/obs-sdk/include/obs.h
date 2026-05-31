#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#define EXPORT __declspec(dllexport)

// --- MOCK DEFINITIONS ---
typedef void obs_source_t;
typedef void obs_properties_t;
typedef void obs_property_t;
typedef void obs_data_t;

enum obs_source_type {
    OBS_SOURCE_TYPE_INPUT,
    OBS_SOURCE_TYPE_FILTER,
    OBS_SOURCE_TYPE_TRANSITION,
    OBS_SOURCE_TYPE_SCENE
};

#define OBS_SOURCE_VIDEO            (1 << 0)
#define OBS_SOURCE_AUDIO            (1 << 1)
#define OBS_ICON_TYPE_CAMERA        "camera"
#define OBS_COMBO_TYPE_LIST         1
#define OBS_COMBO_FORMAT_INT        1

enum video_format {
    VIDEO_FORMAT_NONE,
    VIDEO_FORMAT_I420,
    VIDEO_FORMAT_NV12,
    VIDEO_FORMAT_YUY2,
    VIDEO_FORMAT_RGBA,
    VIDEO_FORMAT_BGRA
};

struct obs_source_frame {
    uint8_t *data[8];
    uint32_t linesize[8];
    uint32_t width;
    uint32_t height;
    uint64_t timestamp;
    enum video_format format;
};

struct obs_source_info {
    const char *id;
    enum obs_source_type type;
    uint32_t output_flags;
    const char *(*get_name)(void *type_data);
    void *(*create)(obs_data_t *settings, obs_source_t *source);
    void (*destroy)(void *data);
    obs_properties_t *(*get_properties)(void *data);
    void (*update)(void *data, obs_data_t *settings);
    const char *icon_type;
};

// --- MOCK FUNCTION PROTOTYPES ---
EXPORT void obs_register_source_s(struct obs_source_info *info, size_t size);
#define obs_register_source(info) obs_register_source_s(info, sizeof(struct obs_source_info))

EXPORT void obs_source_output_video(obs_source_t *source, const struct obs_source_frame *frame);

EXPORT const char *obs_data_get_string(obs_data_t *data, const char *name);
EXPORT int64_t obs_data_get_int(obs_data_t *data, const char *name);
EXPORT bool obs_data_get_bool(obs_data_t *data, const char *name);

EXPORT obs_properties_t *obs_properties_create(void);
EXPORT obs_property_t *obs_properties_add_int(obs_properties_t *props, const char *name, const char *description, int min, int max, int step);
EXPORT obs_property_t *obs_properties_add_list(obs_properties_t *props, const char *name, const char *description, int type, int format);
EXPORT void obs_property_list_add_int(obs_property_t *p, const char *name, int64_t val);

// --- MODULE ENTRY DEFINITIONS ---
#define OBS_DECLARE_MODULE() \
    __declspec(dllexport) const char *obs_module_name(void) { return "camext"; } \
    __declspec(dllexport) void obs_module_set_pointer(void *p) { (void)p; }

#define OBS_MODULE_USE_DEFAULT_LOCALE(name, lang)

#ifdef __cplusplus
}
#endif
