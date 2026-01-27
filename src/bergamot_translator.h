#ifndef BERGAMOT_TRANSLATOR_H
#define BERGAMOT_TRANSLATOR_H

#include <stdint.h>
#include <stddef.h>

#if _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// 语言检测结果结构体
typedef struct {
    char language[8];      // 语言代码（如 "en", "zh"）
    int is_reliable;       // 是否可靠（0/1）
    int confidence;        // 置信度（0-100）
} BergamotDetectionResult;

// 初始化翻译服务
// 返回: 0 成功, 非0 失败
FFI_PLUGIN_EXPORT int bergamot_initialize_service(void);

// 加载模型到缓存
// cfg: 模型配置字符串（JSON格式）
// key: 模型缓存键
// 返回: 0 成功, 非0 失败
FFI_PLUGIN_EXPORT int bergamot_load_model(const char* cfg, const char* key);

// 批量翻译
// inputs: 输入字符串数组
// input_count: 输入字符串数量
// key: 模型缓存键
// outputs: 输出字符串数组（调用者需要释放内存）
// output_count: 输出字符串数量
// 返回: 0 成功, 非0 失败
// 注意: outputs 需要调用 bergamot_free_string_array 释放
FFI_PLUGIN_EXPORT int bergamot_translate_multiple(
    const char** inputs,
    int input_count,
    const char* key,
    char*** outputs,
    int* output_count
);

// 枢轴翻译（通过中间语言）
// first_key: 第一个模型缓存键（源语言 -> 中间语言）
// second_key: 第二个模型缓存键（中间语言 -> 目标语言）
// inputs: 输入字符串数组
// input_count: 输入字符串数量
// outputs: 输出字符串数组（调用者需要释放内存）
// output_count: 输出字符串数量
// 返回: 0 成功, 非0 失败
// 注意: outputs 需要调用 bergamot_free_string_array 释放
FFI_PLUGIN_EXPORT int bergamot_pivot_multiple(
    const char* first_key,
    const char* second_key,
    const char** inputs,
    int input_count,
    char*** outputs,
    int* output_count
);

// 语言检测
// text: 待检测文本
// hint: 语言提示（可选，可为NULL）
// result: 检测结果结构体指针
// 返回: 0 成功, 非0 失败
FFI_PLUGIN_EXPORT int bergamot_detect_language(
    const char* text,
    const char* hint,
    BergamotDetectionResult* result
);

// 清理资源（释放所有模型和服务）
FFI_PLUGIN_EXPORT void bergamot_cleanup(int reset_service);

// 释放字符串数组内存
// array: 字符串数组指针
// count: 数组元素数量
FFI_PLUGIN_EXPORT void bergamot_free_string_array(char** array, int count);

#ifdef __cplusplus
}
#endif

#endif // BERGAMOT_TRANSLATOR_H
