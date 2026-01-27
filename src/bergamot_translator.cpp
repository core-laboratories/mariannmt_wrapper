#include "bergamot_translator.h"
#include <string>
#include <vector>
#include <unordered_map>
#include <mutex>
#include <cstring>
#include <cstdlib>
#include <iostream>
#include <fstream>

// Bergamot translator includes
#include "translator/byte_array_util.h"
#include "translator/parser.h"
#include "translator/response.h"
#include "translator/response_options.h"
#include "translator/service.h"
#include "translator/utils.h"
#include "compact_lang_det.h"

using namespace marian::bergamot;

// 全局状态
// macOS: marian/bergamot destructors can throw during shutdown, which triggers
// std::terminate (destructors are noexcept by default) and aborts the app.
//
// Workaround: keep the model cache alive until process exit by allocating it on
// the heap on macOS, so its destructor is never run.
#if defined(__APPLE__) && !defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
static auto* model_cache = new std::unordered_map<std::string, std::shared_ptr<TranslationModel>>();
#define MODEL_CACHE (*model_cache)
#else
static std::unordered_map<std::string, std::shared_ptr<TranslationModel>> model_cache;
#define MODEL_CACHE model_cache
#endif

// NOTE(macOS):
// We intentionally avoid destroying BlockingService at process termination.
// On macOS, bergamot/marian's logger teardown can throw during shutdown, which
// triggers std::terminate from a destructor and aborts the app.
//
// Keeping the service alive until process exit avoids invoking that destructor.
static BlockingService* global_service = nullptr;
static std::mutex service_mutex;
static std::mutex translation_mutex;

// C++ 核心实现函数
namespace {
    void initializeService() {
        std::lock_guard<std::mutex> lock(service_mutex);
        
        if (global_service == nullptr) {
            BlockingService::Config blockingConfig;
            blockingConfig.cacheSize = 256;
            blockingConfig.logger.level = "off";
            global_service = new BlockingService(blockingConfig);
        }
    }
    
    void loadModelIntoCache(const std::string& cfg, const std::string& key) {
        std::lock_guard<std::mutex> lock(service_mutex);
        
        // 检查模型是否已加载（双重检查，避免重复加载）
        if (MODEL_CACHE.find(key) != MODEL_CACHE.end()) {
            return; // 模型已加载，直接返回
        }
        
        try {
            auto validate = false;  // Temporarily disable validation to avoid YAML node iterator error
            auto pathsDir = "";
            
            // 解析配置
            std::shared_ptr<marian::Options> options = parseOptionsFromString(cfg, validate, pathsDir);
            
            // 创建模型
            MODEL_CACHE[key] = std::make_shared<TranslationModel>(options);
        } catch (const std::exception &e) {
            // 重新抛出异常，让调用者处理
            throw std::runtime_error("Failed to load model " + key + ": " + e.what());
        } catch (...) {
            // 捕获所有其他异常
            throw std::runtime_error("Failed to load model " + key + ": Unknown error");
        }
    }
    
    std::vector<std::string> translateMultiple(std::vector<std::string> &&inputs, const char *key) {
        initializeService();
        
        std::string key_str(key);
        
        // 检查模型是否已加载
        if (MODEL_CACHE.find(key_str) == MODEL_CACHE.end()) {
            throw std::runtime_error("Model not loaded: " + key_str);
        }
        
        std::shared_ptr<TranslationModel> model = MODEL_CACHE[key_str];
        
        std::vector<ResponseOptions> responseOptions;
        responseOptions.reserve(inputs.size());
        for (size_t i = 0; i < inputs.size(); ++i) {
            ResponseOptions opts;
            opts.HTML = false;
            opts.qualityScores = false;
            opts.alignment = false;
            opts.sentenceMappings = false;
            responseOptions.emplace_back(opts);
        }
        
        std::lock_guard<std::mutex> translation_lock(translation_mutex);
        std::vector<Response> responses = global_service->translateMultiple(model, std::move(inputs), responseOptions);
        
        std::vector<std::string> results;
        results.reserve(responses.size());
        for (const auto &response: responses) {
            results.push_back(response.target.text);
        }
        
        return results;
    }
    
    std::vector<std::string> pivotMultiple(const char *firstKey, const char *secondKey, std::vector<std::string> &&inputs) {
        initializeService();
        
        std::string first_key_str(firstKey);
        std::string second_key_str(secondKey);
        
        // 检查模型是否已加载
        if (MODEL_CACHE.find(first_key_str) == MODEL_CACHE.end()) {
            throw std::runtime_error("First model not loaded: " + first_key_str);
        }
        if (MODEL_CACHE.find(second_key_str) == MODEL_CACHE.end()) {
            throw std::runtime_error("Second model not loaded: " + second_key_str);
        }
        
        std::shared_ptr<TranslationModel> firstModel = MODEL_CACHE[first_key_str];
        std::shared_ptr<TranslationModel> secondModel = MODEL_CACHE[second_key_str];
        
        std::vector<ResponseOptions> responseOptions;
        responseOptions.reserve(inputs.size());
        for (size_t i = 0; i < inputs.size(); ++i) {
            ResponseOptions opts;
            opts.HTML = false;
            opts.qualityScores = false;
            opts.alignment = false;
            opts.sentenceMappings = false;
            responseOptions.emplace_back(opts);
        }
        
        std::lock_guard<std::mutex> translation_lock(translation_mutex);
        std::vector<Response> responses = global_service->pivotMultiple(firstModel, secondModel, std::move(inputs), responseOptions);
        
        std::vector<std::string> results;
        results.reserve(responses.size());
        for (const auto &response: responses) {
            results.push_back(response.target.text);
        }
        
        return results;
    }
    
    struct DetectionResult {
        std::string language;
        bool isReliable;
        int confidence;
    };
    
    DetectionResult detectLanguage(const char *text, const char *language_hint = nullptr) {
        bool is_reliable;
        int text_bytes = (int) strlen(text);
        bool is_plain_text = true;
        
        CLD2::Language hint_lang = CLD2::UNKNOWN_LANGUAGE;
        if (language_hint != nullptr && strlen(language_hint) > 0) {
            hint_lang = CLD2::GetLanguageFromName(language_hint);
        }
        
        CLD2::CLDHints hints = {nullptr, nullptr, 0, hint_lang};
        CLD2::Language language3[3];
        int percent3[3];
        double normalized_score3[3];
        int chunk_bytes;
        
        CLD2::ExtDetectLanguageSummary(
                text,
                text_bytes,
                is_plain_text,
                &hints,
                0,
                language3,
                percent3,
                normalized_score3,
                nullptr,
                &chunk_bytes,
                &is_reliable
        );
        
        return DetectionResult{
                CLD2::LanguageCode(language3[0]),
                is_reliable,
                percent3[0]
        };
    }
    
    void cleanup(bool reset_service) {
        std::lock_guard<std::mutex> lock(service_mutex);
        // Do not delete global_service (see note above); just drop references.
        if (reset_service) {
            global_service = nullptr;
        }

        // Do NOT clear the model cache on macOS: destroying marian objects can
        // throw during shutdown and abort the process.
#if !defined(__APPLE__) || defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
        MODEL_CACHE.clear();
#endif
    }
}

// C FFI 接口实现
extern "C" {

FFI_PLUGIN_EXPORT int bergamot_initialize_service(void) {
    try {
        initializeService();
        return 0;
    } catch (const std::exception &e) {
        std::cerr << "[bergamot_initialize_service] Error: " << e.what() << std::endl;
        return -1;
    }
}

FFI_PLUGIN_EXPORT int bergamot_load_model(const char* cfg, const char* key) {
    if (cfg == nullptr || key == nullptr) {
        std::cerr << "[bergamot_load_model] Error: cfg or key parameter is invalid" << std::endl;
        return -1;
    }
    
    try {
        std::string cfg_str(cfg);
        std::string key_str(key);
        
        // 确保服务已初始化
        initializeService();
        
        // 加载模型
        loadModelIntoCache(cfg_str, key_str);
        return 0;
    } catch (const std::exception &e) {
        std::cerr << "[bergamot_load_model] Error: " << e.what() << std::endl;
        return -1;
    } catch (...) {
        std::cerr << "[bergamot_load_model] Error: Unknown error" << std::endl;
        return -1;
    }
}

FFI_PLUGIN_EXPORT int bergamot_translate_multiple(
    const char** inputs,
    int input_count,
    const char* key,
    char*** outputs,
    int* output_count
) {
    if (inputs == nullptr || input_count <= 0 || key == nullptr || outputs == nullptr || output_count == nullptr) {
        std::cerr << "[bergamot_translate_multiple] Error: inputs parameter is invalid" << std::endl;
        return -1;
    }
    
    try {
        std::vector<std::string> cpp_inputs;
        cpp_inputs.reserve(input_count);
        
        for (int i = 0; i < input_count; i++) {
            if (inputs[i] != nullptr) {
                cpp_inputs.emplace_back(inputs[i]);
            } else {
                cpp_inputs.emplace_back("");
            }
        }
        
        std::vector<std::string> translations = translateMultiple(std::move(cpp_inputs), key);
        
        // 分配输出数组
        char** result_array = (char**)malloc(translations.size() * sizeof(char*));
        if (result_array == nullptr) {
            return -1;
        }
        
        for (size_t i = 0; i < translations.size(); ++i) {
            size_t len = translations[i].length();
            result_array[i] = (char*)malloc((len + 1) * sizeof(char));
            if (result_array[i] == nullptr) {
                // 清理已分配的内存
                for (size_t j = 0; j < i; ++j) {
                    free(result_array[j]);
                }
                free(result_array);
                return -1;
            }
            strncpy(result_array[i], translations[i].c_str(), len);
            result_array[i][len] = '\0';
        }
        
        *outputs = result_array;
        *output_count = (int)translations.size();
        return 0;
    } catch (const std::exception &e) {
        std::cerr << "[bergamot_translate_multiple] Error: " << e.what() << std::endl;
        return -1;
    } catch (...) {
        std::cerr << "[bergamot_translate_multiple] Error: Unknown error" << std::endl;
        return -1;
    }
}

FFI_PLUGIN_EXPORT int bergamot_pivot_multiple(
    const char* first_key,
    const char* second_key,
    const char** inputs,
    int input_count,
    char*** outputs,
    int* output_count
) {
    if (first_key == nullptr || second_key == nullptr || inputs == nullptr || 
        input_count <= 0 || outputs == nullptr || output_count == nullptr) {
        std::cerr << "[bergamot_pivot_multiple] Error: inputs parameter is invalid" << std::endl;
        return -1;
    }
    
    try {
        std::vector<std::string> cpp_inputs;
        cpp_inputs.reserve(input_count);
        
        for (int i = 0; i < input_count; i++) {
            if (inputs[i] != nullptr) {
                cpp_inputs.emplace_back(inputs[i]);
            } else {
                cpp_inputs.emplace_back("");
            }
        }
        
        std::vector<std::string> translations = pivotMultiple(first_key, second_key, std::move(cpp_inputs));
        
        // 分配输出数组
        char** result_array = (char**)malloc(translations.size() * sizeof(char*));
        if (result_array == nullptr) {
            return -1;
        }
        
        for (size_t i = 0; i < translations.size(); ++i) {
            size_t len = translations[i].length();
            result_array[i] = (char*)malloc((len + 1) * sizeof(char));
            if (result_array[i] == nullptr) {
                // 清理已分配的内存
                for (size_t j = 0; j < i; ++j) {
                    free(result_array[j]);
                }
                free(result_array);
                return -1;
            }
            strncpy(result_array[i], translations[i].c_str(), len);
            result_array[i][len] = '\0';
        }
        
        *outputs = result_array;
        *output_count = (int)translations.size();
        return 0;
    } catch (const std::exception &e) {
        std::cerr << "[bergamot_pivot_multiple] Error: " << e.what() << std::endl;
        return -1;
    }
}

FFI_PLUGIN_EXPORT int bergamot_detect_language(
    const char* text,
    const char* hint,
    BergamotDetectionResult* result
) {
    if (text == nullptr || result == nullptr) {
        std::cerr << "[bergamot_detect_language] Error: text or result parameter is invalid" << std::endl;
        return -1;
    }
    
    try {
        DetectionResult detection = detectLanguage(text, hint);
        
        // 复制语言代码
        strncpy(result->language, detection.language.c_str(), sizeof(result->language) - 1);
        result->language[sizeof(result->language) - 1] = '\0';
        
        result->is_reliable = detection.isReliable ? 1 : 0;
        result->confidence = detection.confidence;
        
        return 0;
    } catch (const std::exception &e) {
        std::cerr << "[bergamot_detect_language] Error: " << e.what() << std::endl;
        return -1;
    }
}

FFI_PLUGIN_EXPORT void bergamot_cleanup(int reset_service) {
    cleanup(reset_service != 0);
}

FFI_PLUGIN_EXPORT void bergamot_free_string_array(char** array, int count) {
    if (array == nullptr || count <= 0) {
        std::cerr << "[bergamot_free_string_array] Error: array or count is invalid" << std::endl;
        return;
    }
    
    for (int i = 0; i < count; i++) {
        if (array[i] != nullptr) {
            free(array[i]);
        }
    }
    free(array);
}

} // extern "C"

