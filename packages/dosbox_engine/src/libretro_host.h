#pragma once

#include "libretro.h"
#include "ring_buffer.h"

#include <array>
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace dosbox_host {

struct HostConfig {
    std::string corePath;
    std::string gamePath;
    std::string saveDir;
    std::string systemDir;
    std::unordered_map<std::string, std::string> coreOptions;
};

using VideoFrameCallback = std::function<void(
    const void* data, unsigned width, unsigned height, size_t pitch, unsigned pixelFormat)>;
using VideoShutdownCallback = std::function<void()>;
using AudioConfigCallback = std::function<void(double sampleRate)>;
using LogCallback = std::function<void(int level, const char* msg)>;

class LibretroHost {
public:
    LibretroHost();
    ~LibretroHost();

    LibretroHost(const LibretroHost&) = delete;
    LibretroHost& operator=(const LibretroHost&) = delete;

    void setVideoCallback(VideoFrameCallback cb) { videoCb_ = std::move(cb); }
    void setVideoShutdownCallback(VideoShutdownCallback cb) { videoShutdownCb_ = std::move(cb); }
    void setAudioConfigCallback(AudioConfigCallback cb) { audioConfigCb_ = std::move(cb); }
    void setLogCallback(LogCallback cb) { logCb_ = std::move(cb); }

    bool start(const HostConfig& config, std::string& errorOut);
    void stop();
    void pause();
    void resume();
    void reset();

    void setFastForward(int multiplier);
    void updateCoreOption(const std::string& key, const std::string& value);

    // Input methods (safe to call from UI / main thread)
    void sendKeyEvent(unsigned retroKey, bool down);
    void sendMouseDelta(int32_t dx, int32_t dy);
    void sendMouseButton(int buttonIndex, bool down);  // 0=left, 1=right, 2=middle
    void sendPointer(int16_t normX, int16_t normY, bool pressed);
    void sendJoypadButton(unsigned retroId, bool down);

    // Save state methods (thread-safe with emulation loop)
    bool serializeState(std::vector<uint8_t>& outData);
    bool unserializeState(const uint8_t* data, size_t size);

    // Audio ring buffer accessor for platform audio stream (Oboe / AudioUnit)
    AudioRingBuffer& audioBuffer() { return audioBuffer_; }

    double fps() const { return fps_.load(std::memory_order_relaxed); }
    double sampleRate() const { return sampleRate_.load(std::memory_order_relaxed); }
    float aspectRatio() const { return aspectRatio_.load(std::memory_order_relaxed); }

private:
    struct CoreSymbols {
        void (*retro_init)(void) = nullptr;
        void (*retro_deinit)(void) = nullptr;
        unsigned (*retro_api_version)(void) = nullptr;
        void (*retro_get_system_info)(struct retro_system_info*) = nullptr;
        void (*retro_get_system_av_info)(struct retro_system_av_info*) = nullptr;
        void (*retro_set_environment)(retro_environment_t) = nullptr;
        void (*retro_set_video_refresh)(retro_video_refresh_t) = nullptr;
        void (*retro_set_audio_sample)(retro_audio_sample_t) = nullptr;
        void (*retro_set_audio_sample_batch)(retro_audio_sample_batch_t) = nullptr;
        void (*retro_set_input_poll)(retro_input_poll_t) = nullptr;
        void (*retro_set_input_state)(retro_input_state_t) = nullptr;
        void (*retro_set_controller_port_device)(unsigned, unsigned) = nullptr;
        void (*retro_reset)(void) = nullptr;
        void (*retro_run)(void) = nullptr;
        size_t (*retro_serialize_size)(void) = nullptr;
        bool (*retro_serialize)(void*, size_t) = nullptr;
        bool (*retro_unserialize)(const void*, size_t) = nullptr;
        bool (*retro_load_game)(const struct retro_game_info*) = nullptr;
        void (*retro_unload_game)(void) = nullptr;
    };

    struct PendingKeyEvent {
        unsigned key;
        bool down;
    };

    bool loadCoreLibrary(const std::string& path, std::string& errorOut);
    void unloadCoreLibrary();
    void emulationLoop();
    void flushPendingKeyEvents();

    // Static Libretro C callbacks
    static bool environmentCb(unsigned cmd, void* data);
    static void videoRefreshCb(const void* data, unsigned width, unsigned height, size_t pitch);
    static void audioSampleCb(int16_t left, int16_t right);
    static size_t audioSampleBatchCb(const int16_t* data, size_t frames);
    static void inputPollCb();
    static int16_t inputStateCb(unsigned port, unsigned device, unsigned index, unsigned id);
    static void coreLogCb(enum retro_log_level level, const char* fmt, ...);

    void log(int level, const char* msg);

    static LibretroHost* s_active;

    void* dlHandle_ = nullptr;
    CoreSymbols core_{};

    std::string saveDir_;
    std::string systemDir_;
    std::mutex optionsMutex_;
    std::unordered_map<std::string, std::string> coreOptions_;
    std::atomic<bool> optionsDirty_{false};

    unsigned pixelFormat_ = RETRO_PIXEL_FORMAT_RGB565;
    retro_keyboard_event_t keyboardCallback_ = nullptr;

    std::atomic<double> fps_{60.0};
    std::atomic<double> sampleRate_{44100.0};
    std::atomic<float> aspectRatio_{4.0f / 3.0f};
    std::atomic<int> fastForward_{1};

    VideoFrameCallback videoCb_;
    VideoShutdownCallback videoShutdownCb_;
    AudioConfigCallback audioConfigCb_;
    LogCallback logCb_;
    AudioRingBuffer audioBuffer_{65536};

    // Input state
    std::array<std::atomic<bool>, RETROK_LAST> keyStates_{};
    std::mutex keyQueueMutex_;
    std::vector<PendingKeyEvent> pendingKeys_;

    std::atomic<int32_t> mouseDx_{0};
    std::atomic<int32_t> mouseDy_{0};
    std::atomic<bool> mouseLeft_{false};
    std::atomic<bool> mouseRight_{false};
    std::atomic<bool> mouseMiddle_{false};

    std::atomic<int16_t> pointerX_{0};
    std::atomic<int16_t> pointerY_{0};
    std::atomic<bool> pointerPressed_{false};

    std::array<std::atomic<bool>, 16> joypadStates_{};

    // Thread lifecycle
    std::thread emuThread_;
    std::mutex runMutex_;
    std::mutex stateMutex_;
    std::condition_variable stateCv_;
    std::atomic<bool> running_{false};
    std::atomic<bool> paused_{false};
    bool gameLoaded_ = false;
};

}  // namespace dosbox_host
