#include "main.h"
#include "whisper.cpp/whisper.h"

#define DR_WAV_IMPLEMENTATION
#include "whisper.cpp/examples/dr_wav.h"

#include <cstdio>
#include <chrono>
#include <string>
#include <thread>
#include <vector>
#include <cmath>
#include <iostream>
#include <stdio.h>
#include <mutex>
#ifdef __ANDROID__
#include <android/log.h>
#endif
#include "json/json.hpp"

using json = nlohmann::json;

// Cache the whisper context so we don't reload the model on every request
static whisper_context *g_ctx = nullptr;
static std::string g_model_path = "";
static std::mutex g_ctx_mutex;

#ifdef __ANDROID__
#define WHISPER_LOG_TAG "whisper_flutter_new"
#define WHISPER_LOGI(...) __android_log_print(ANDROID_LOG_INFO, WHISPER_LOG_TAG, __VA_ARGS__)
#else
#define WHISPER_LOGI(...) fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n");
#endif

char *jsonToChar(json jsonData) noexcept
{
    std::string result = jsonData.dump();
    char *ch = new char[result.size() + 1];
    strcpy(ch, result.c_str());
    return ch;
}

struct whisper_params
{
    int32_t seed = -1; // RNG seed, not used currently
    int32_t n_threads = std::min(4, (int32_t)std::thread::hardware_concurrency());

    int32_t n_processors = 1;
    int32_t offset_t_ms = 0;
    int32_t offset_n = 0;
    int32_t duration_ms = 0;
    int32_t max_context = -1;
    int32_t max_len = 0;
    int32_t best_of = 5;
    int32_t beam_size = -1;

    float word_thold = 0.01f;
    float entropy_thold = 2.40f;
    float logprob_thold = -1.00f;

    bool verbose = false;
    bool print_special_tokens = false;
    bool speed_up = false;
    bool translate = false;
    bool diarize = false;
    bool no_fallback = false;
    bool output_txt = false;
    bool output_vtt = false;
    bool output_srt = false;
    bool output_wts = false;
    bool output_csv = false;
    bool print_special = false;
    bool print_colors = false;
    bool print_progress = false;
    bool no_timestamps = false;
    bool split_on_word = false;

    std::string language = "auto";
    std::string prompt;
    std::string model = "models/ggml-tiny.bin";
    std::string audio = "samples/jfk.wav";
    std::vector<std::string> fname_inp = {};
    std::vector<std::string> fname_outp = {};
};

struct whisper_print_user_data
{
    const whisper_params *params;

    const std::vector<std::vector<float>> *pcmf32s;
};

/// Load and cache whisper context for a given model path.
/// Subsequent calls with the same model reuse the already-loaded context.
static whisper_context *get_or_load_context(const std::string &model_path, json &jsonResult) {
    if (g_ctx != nullptr && g_model_path == model_path) {
        return g_ctx;
    }

    if (g_ctx != nullptr) {
        whisper_free(g_ctx);
        g_ctx = nullptr;
    }

    g_model_path = model_path;
    g_ctx = whisper_init_from_file(model_path.c_str());
    if (g_ctx == nullptr) {
        jsonResult["@type"] = "error";
        jsonResult["message"] = "failed to load model";
    }
    return g_ctx;
}

json transcribe(json jsonBody) noexcept
{
    whisper_params params;

    params.n_threads = jsonBody["threads"];
    params.n_processors = jsonBody["n_processors"];
    params.verbose = jsonBody["is_verbose"];
    params.translate = jsonBody["is_translate"];
    params.language = jsonBody["language"];
    params.print_special_tokens = jsonBody["is_special_tokens"];
    params.no_timestamps = jsonBody["is_no_timestamps"];
    params.model = jsonBody["model"];
    params.audio = jsonBody["audio"];
    params.split_on_word = jsonBody["split_on_word"];
    params.speed_up = jsonBody["speed_up"];
    json jsonResult;
    jsonResult["@type"] = "transcribe";

    if (params.language != "" && params.language != "auto" && whisper_lang_id(params.language.c_str()) == -1)
    {
        jsonResult["@type"] = "error";
        jsonResult["message"] = "error: unknown language = " + params.language;
        return jsonResult;
    }

    if (params.seed < 0)
    {
        params.seed = time(NULL);
    }

    // whisper init (cached between calls)
    std::lock_guard<std::mutex> lock(g_ctx_mutex);
    const bool reused_context = (g_ctx != nullptr && g_model_path == params.model);
    const auto load_start = std::chrono::steady_clock::now();
    struct whisper_context *ctx = get_or_load_context(params.model, jsonResult);
    if (ctx == nullptr) {
        return jsonResult;
    }
    const auto load_end = std::chrono::steady_clock::now();
    const auto load_ms = std::chrono::duration_cast<std::chrono::milliseconds>(load_end - load_start).count();
    std::string text_result = "";
    const auto fname_inp = params.audio;
    // WAV input
    std::vector<float> pcmf32;
    int sample_rate = 0;
    {
        drwav wav;
        if (!drwav_init_file(&wav, fname_inp.c_str(), NULL))
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = " failed to open WAV file ";
            return jsonResult;
        }

        if (wav.channels != 1 && wav.channels != 2)
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "must be mono or stereo";
            return jsonResult;
        }

        if (wav.sampleRate != WHISPER_SAMPLE_RATE)
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "WAV file  must be 16 kHz";
            return jsonResult;
        }

        if (wav.bitsPerSample != 16)
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "WAV file  must be 16 bit";
            return jsonResult;
        }

        int n = wav.totalPCMFrameCount;
        sample_rate = wav.sampleRate;

        std::vector<int16_t> pcm16;
        pcm16.resize(n * wav.channels);
        drwav_read_pcm_frames_s16(&wav, n, pcm16.data());
        drwav_uninit(&wav);

        // convert to mono, float
        pcmf32.resize(n);
        if (wav.channels == 1)
        {
            for (int i = 0; i < n; i++)
            {
                pcmf32[i] = float(pcm16[i]) / 32768.0f;
            }
        }
        else
        {
            for (int i = 0; i < n; i++)
            {
                pcmf32[i] = float(pcm16[2 * i] + pcm16[2 * i + 1]) / 65536.0f;
            }
        }
    }

    {
        if (params.language == "" && params.language == "auto")
        {
            params.language = "auto";
            params.translate = false;
        }
    }
    // run the inference
    {
        whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

        wparams.print_realtime = false;
        wparams.print_progress = false;
        wparams.print_timestamps = !params.no_timestamps;
        // wparams.print_special_tokens = params.print_special_tokens;
        wparams.translate = params.translate;
        wparams.language = params.language.c_str();
        wparams.n_threads = params.n_threads;
        wparams.split_on_word = params.split_on_word;
        wparams.speed_up = params.speed_up;

        if (params.split_on_word) {
            wparams.max_len = 1;
            wparams.token_timestamps = true;
        }

        const auto infer_start = std::chrono::steady_clock::now();
        const bool use_parallel = params.n_processors > 1 &&
            pcmf32.size() > static_cast<size_t>(WHISPER_SAMPLE_RATE) * 10;
        const int infer_result = use_parallel
            ? whisper_full_parallel(ctx, wparams, pcmf32.data(), pcmf32.size(), params.n_processors)
            : whisper_full(ctx, wparams, pcmf32.data(), pcmf32.size());
        const auto infer_end = std::chrono::steady_clock::now();
        const auto infer_ms = std::chrono::duration_cast<std::chrono::milliseconds>(infer_end - infer_start).count();

        if (sample_rate > 0) {
            const auto audio_ms = static_cast<long long>(pcmf32.size()) * 1000LL / sample_rate;
            WHISPER_LOGI(
                "transcribe model=%s reused=%d load_ms=%lld infer_ms=%lld audio_ms=%lld threads=%d procs=%d speed_up=%d parallel=%d",
                params.model.c_str(),
                reused_context ? 1 : 0,
                static_cast<long long>(load_ms),
                static_cast<long long>(infer_ms),
                audio_ms,
                params.n_threads,
                params.n_processors,
                params.speed_up ? 1 : 0,
                use_parallel ? 1 : 0
            );
        }

        if (infer_result != 0)
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "failed to process audio";
            return jsonResult;
        }

        

        // print result;
        if (!wparams.print_realtime)
        {

            const int n_segments = whisper_full_n_segments(ctx);

            std::vector<json> segmentsJson = {};

            for (int i = 0; i < n_segments; ++i)
            {
                const char *text = whisper_full_get_segment_text(ctx, i);

                std::string str(text);
                text_result += str;
                if (params.no_timestamps)
                {
                    // printf("%s", text);
                    // fflush(stdout);
                } else {
                    json jsonSegment;
                    const int64_t t0 = whisper_full_get_segment_t0(ctx, i);
                    const int64_t t1 = whisper_full_get_segment_t1(ctx, i);

                    // printf("[%s --> %s]  %s\n", to_timestamp(t0).c_str(), to_timestamp(t1).c_str(), text);

                    jsonSegment["from_ts"] = t0;
                    jsonSegment["to_ts"] = t1;
                    jsonSegment["text"] = text;

                    segmentsJson.push_back(jsonSegment);
                }
            }

            if (!params.no_timestamps) {
                jsonResult["segments"] = segmentsJson;
            }
        }
    }
    jsonResult["text"] = text_result;
    return jsonResult;
}
extern "C"
{
    FUNCTION_ATTRIBUTE
    char *request(char *body)
    {
        try
        {
            json jsonBody = json::parse(body);
            json jsonResult;

            if (jsonBody["@type"] == "getTextFromWavFile")
            {
                try
                {
                    return jsonToChar(transcribe(jsonBody));
                }
                catch (const std::exception &e)
                {
                    jsonResult["@type"] = "error";
                    jsonResult["message"] = e.what();
                    return jsonToChar(jsonResult);
                }
            }
            if (jsonBody["@type"] == "getVersion")
            {
                jsonResult["@type"] = "version";
                jsonResult["message"] = "lib version: v1.0.1";
                return jsonToChar(jsonResult);
            }

            jsonResult["@type"] = "error";
            jsonResult["message"] = "method not found";
            return jsonToChar(jsonResult);
        }
        catch (const std::exception &e)
        {
            json jsonResult;
            jsonResult["@type"] = "error";
            jsonResult["message"] = e.what();
            return jsonToChar(jsonResult);
        }
    }
}
