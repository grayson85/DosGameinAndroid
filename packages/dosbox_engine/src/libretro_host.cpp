#include "libretro_host.h"

#include <chrono>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>

namespace dosbox_host {

LibretroHost* LibretroHost::s_active = nullptr;

LibretroHost::LibretroHost() {
    for (auto& k : keyStates_) k.store(false, std::memory_order_relaxed);
    for (auto& j : joypadStates_) j.store(false, std::memory_order_relaxed);
}

LibretroHost::~LibretroHost() {
    stop();
}

void LibretroHost::log(int level, const char* msg) {
    if (logCb_) {
        logCb_(level, msg);
    }
}

bool LibretroHost::loadCoreLibrary(const std::string& path, std::string& errorOut) {
    dlHandle_ = dlopen(path.c_str(), RTLD_LAZY | RTLD_LOCAL);
    if (!dlHandle_) {
        const char* err = dlerror();
        errorOut = std::string("dlopen failed for ") + path + ": " + (err ? err : "unknown");
        return false;
    }

    auto loadSym = [&](auto& fn, const char* name) -> bool {
        fn = reinterpret_cast<std::remove_reference_t<decltype(fn)>>(dlsym(dlHandle_, name));
        if (!fn) {
            errorOut = std::string("Missing required Libretro symbol: ") + name;
            return false;
        }
        return true;
    };

    if (!loadSym(core_.retro_init, "retro_init") ||
        !loadSym(core_.retro_deinit, "retro_deinit") ||
        !loadSym(core_.retro_api_version, "retro_api_version") ||
        !loadSym(core_.retro_get_system_info, "retro_get_system_info") ||
        !loadSym(core_.retro_get_system_av_info, "retro_get_system_av_info") ||
        !loadSym(core_.retro_set_environment, "retro_set_environment") ||
        !loadSym(core_.retro_set_video_refresh, "retro_set_video_refresh") ||
        !loadSym(core_.retro_set_audio_sample, "retro_set_audio_sample") ||
        !loadSym(core_.retro_set_audio_sample_batch, "retro_set_audio_sample_batch") ||
        !loadSym(core_.retro_set_input_poll, "retro_set_input_poll") ||
        !loadSym(core_.retro_set_input_state, "retro_set_input_state") ||
        !loadSym(core_.retro_set_controller_port_device, "retro_set_controller_port_device") ||
        !loadSym(core_.retro_reset, "retro_reset") ||
        !loadSym(core_.retro_run, "retro_run") ||
        !loadSym(core_.retro_serialize_size, "retro_serialize_size") ||
        !loadSym(core_.retro_serialize, "retro_serialize") ||
        !loadSym(core_.retro_unserialize, "retro_unserialize") ||
        !loadSym(core_.retro_load_game, "retro_load_game") ||
        !loadSym(core_.retro_unload_game, "retro_unload_game")) {
        unloadCoreLibrary();
        return false;
    }

    return true;
}

void LibretroHost::unloadCoreLibrary() {
    if (dlHandle_) {
        dlclose(dlHandle_);
        dlHandle_ = nullptr;
    }
    core_ = CoreSymbols{};
}

bool LibretroHost::start(const HostConfig& config, std::string& errorOut) {
    stop();

    saveDir_ = config.saveDir;
    systemDir_ = config.systemDir;
    {
        std::lock_guard<std::mutex> lk(optionsMutex_);
        coreOptions_ = config.coreOptions;
        optionsDirty_.store(true, std::memory_order_release);
    }

    audioBuffer_.clear();
    keyboardCallback_ = nullptr;
    pixelFormat_ = RETRO_PIXEL_FORMAT_RGB565;

    if (!loadCoreLibrary(config.corePath, errorOut)) {
        return false;
    }

    s_active = this;

    core_.retro_set_environment(&LibretroHost::environmentCb);
    core_.retro_set_video_refresh(&LibretroHost::videoRefreshCb);
    core_.retro_set_audio_sample(&LibretroHost::audioSampleCb);
    core_.retro_set_audio_sample_batch(&LibretroHost::audioSampleBatchCb);
    core_.retro_set_input_poll(&LibretroHost::inputPollCb);
    core_.retro_set_input_state(&LibretroHost::inputStateCb);

    core_.retro_init();

    struct retro_game_info gameInfo {};
    gameInfo.path = config.gamePath.c_str();
    gameInfo.data = nullptr;
    gameInfo.size = 0;
    gameInfo.meta = nullptr;

    if (!core_.retro_load_game(&gameInfo)) {
        errorOut = "retro_load_game failed for: " + config.gamePath;
        core_.retro_deinit();
        unloadCoreLibrary();
        s_active = nullptr;
        return false;
    }
    gameLoaded_ = true;

    struct retro_system_av_info avInfo {};
    core_.retro_get_system_av_info(&avInfo);
    if (avInfo.timing.fps > 1.0) {
        fps_.store(avInfo.timing.fps, std::memory_order_relaxed);
    }
    if (avInfo.timing.sample_rate > 1000.0) {
        sampleRate_.store(avInfo.timing.sample_rate, std::memory_order_relaxed);
    }
    if (avInfo.geometry.aspect_ratio > 0.1f) {
        aspectRatio_.store(avInfo.geometry.aspect_ratio, std::memory_order_relaxed);
    }

    if (audioConfigCb_) {
        audioConfigCb_(sampleRate_.load(std::memory_order_relaxed));
    }

    paused_.store(false, std::memory_order_release);
    running_.store(true, std::memory_order_release);
    emuThread_ = std::thread(&LibretroHost::emulationLoop, this);
    return true;
}

void LibretroHost::stop() {
    if (running_.exchange(false, std::memory_order_acq_rel)) {
        {
            std::lock_guard<std::mutex> lk(stateMutex_);
            paused_.store(false, std::memory_order_release);
        }
        stateCv_.notify_all();
        if (emuThread_.joinable()) {
            emuThread_.join();
        }
    }

    if (gameLoaded_ && core_.retro_unload_game) {
        core_.retro_unload_game();
        gameLoaded_ = false;
    }
    if (core_.retro_deinit) {
        core_.retro_deinit();
    }
    unloadCoreLibrary();
    if (s_active == this) {
        s_active = nullptr;
    }
}

void LibretroHost::pause() {
    std::lock_guard<std::mutex> lk(stateMutex_);
    paused_.store(true, std::memory_order_release);
    stateCv_.notify_all();
}

void LibretroHost::resume() {
    std::lock_guard<std::mutex> lk(stateMutex_);
    paused_.store(false, std::memory_order_release);
    stateCv_.notify_all();
}

void LibretroHost::reset() {
    std::lock_guard<std::mutex> lk(runMutex_);
    if (gameLoaded_ && core_.retro_reset) {
        core_.retro_reset();
    }
}

void LibretroHost::setFastForward(int multiplier) {
    if (multiplier < 1) multiplier = 1;
    if (multiplier > 8) multiplier = 8;
    fastForward_.store(multiplier, std::memory_order_relaxed);
}

void LibretroHost::updateCoreOption(const std::string& key, const std::string& value) {
    std::lock_guard<std::mutex> lk(optionsMutex_);
    coreOptions_[key] = value;
    optionsDirty_.store(true, std::memory_order_release);
}

void LibretroHost::sendKeyEvent(unsigned retroKey, bool down) {
    if (retroKey < RETROK_LAST) {
        keyStates_[retroKey].store(down, std::memory_order_relaxed);
    }
    std::lock_guard<std::mutex> lk(keyQueueMutex_);
    pendingKeys_.push_back({retroKey, down});
}

void LibretroHost::sendMouseDelta(int32_t dx, int32_t dy) {
    mouseDx_.fetch_add(dx, std::memory_order_relaxed);
    mouseDy_.fetch_add(dy, std::memory_order_relaxed);
}

void LibretroHost::sendMouseButton(int buttonIndex, bool down) {
    if (buttonIndex == 0) mouseLeft_.store(down, std::memory_order_relaxed);
    else if (buttonIndex == 1) mouseRight_.store(down, std::memory_order_relaxed);
    else if (buttonIndex == 2) mouseMiddle_.store(down, std::memory_order_relaxed);
}

void LibretroHost::sendPointer(int16_t normX, int16_t normY, bool pressed) {
    pointerX_.store(normX, std::memory_order_relaxed);
    pointerY_.store(normY, std::memory_order_relaxed);
    pointerPressed_.store(pressed, std::memory_order_relaxed);
}

void LibretroHost::sendJoypadButton(unsigned retroId, bool down) {
    if (retroId < joypadStates_.size()) {
        joypadStates_[retroId].store(down, std::memory_order_relaxed);
    }
}

bool LibretroHost::serializeState(std::vector<uint8_t>& outData) {
    std::lock_guard<std::mutex> lk(runMutex_);
    if (!gameLoaded_ || !core_.retro_serialize_size || !core_.retro_serialize) {
        return false;
    }
    const size_t size = core_.retro_serialize_size();
    if (size == 0) return false;
    outData.resize(size);
    if (!core_.retro_serialize(outData.data(), size)) {
        outData.clear();
        return false;
    }
    return true;
}

bool LibretroHost::unserializeState(const uint8_t* data, size_t size) {
    std::lock_guard<std::mutex> lk(runMutex_);
    if (!gameLoaded_ || !core_.retro_unserialize || !data || size == 0) {
        return false;
    }
    return core_.retro_unserialize(data, size);
}

void LibretroHost::flushPendingKeyEvents() {
    std::vector<PendingKeyEvent> batch;
    {
        std::lock_guard<std::mutex> lk(keyQueueMutex_);
        if (pendingKeys_.empty()) return;
        batch.swap(pendingKeys_);
    }
    if (!keyboardCallback_) return;
    for (const auto& ev : batch) {
        keyboardCallback_(ev.down, ev.key, 0, 0);
    }
}

void LibretroHost::emulationLoop() {
    using Clock = std::chrono::steady_clock;
    auto nextFrameTime = Clock::now();

    while (running_.load(std::memory_order_acquire)) {
        if (paused_.load(std::memory_order_acquire)) {
            std::unique_lock<std::mutex> lk(stateMutex_);
            stateCv_.wait(lk, [this] {
                return !running_.load(std::memory_order_acquire) ||
                       !paused_.load(std::memory_order_acquire);
            });
            nextFrameTime = Clock::now();
            continue;
        }

        {
            std::lock_guard<std::mutex> lk(runMutex_);
            flushPendingKeyEvents();
            core_.retro_run();
        }

        const double targetFps = fps_.load(std::memory_order_relaxed);
        const int ff = fastForward_.load(std::memory_order_relaxed);
        const auto frameDuration = std::chrono::microseconds(
            static_cast<int64_t>(1000000.0 / (targetFps * ff)));

        nextFrameTime += frameDuration;
        const auto now = Clock::now();
        if (nextFrameTime > now) {
            std::unique_lock<std::mutex> lk(stateMutex_);
            stateCv_.wait_until(lk, nextFrameTime, [this] {
                return !running_.load(std::memory_order_acquire) ||
                       paused_.load(std::memory_order_acquire);
            });
        } else if (now - nextFrameTime > std::chrono::milliseconds(100)) {
            // Avoid spiral of death after GC pause or heavy frame
            nextFrameTime = now;
        }
    }

    if (videoShutdownCb_) {
        videoShutdownCb_();
    }
}

bool LibretroHost::environmentCb(unsigned cmd, void* data) {
    LibretroHost* self = s_active;
    if (!self) return false;

    switch (cmd) {
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
            if (!data) return false;
            const auto fmt = *reinterpret_cast<const enum retro_pixel_format*>(data);
            if (fmt == RETRO_PIXEL_FORMAT_RGB565 || fmt == RETRO_PIXEL_FORMAT_XRGB8888) {
                self->pixelFormat_ = fmt;
                return true;
            }
            return false;
        }
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: {
            if (!data) return false;
            *reinterpret_cast<const char**>(data) = self->systemDir_.c_str();
            return true;
        }
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: {
            if (!data) return false;
            *reinterpret_cast<const char**>(data) = self->saveDir_.c_str();
            return true;
        }
        case RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK: {
            if (!data) return false;
            const auto* cb = reinterpret_cast<const struct retro_keyboard_callback*>(data);
            self->keyboardCallback_ = cb->callback;
            return true;
        }
        case RETRO_ENVIRONMENT_GET_VARIABLE: {
            if (!data) return false;
            auto* var = reinterpret_cast<struct retro_variable*>(data);
            if (!var->key) return false;
            std::lock_guard<std::mutex> lk(self->optionsMutex_);
            auto it = self->coreOptions_.find(var->key);
            if (it != self->coreOptions_.end()) {
                var->value = it->second.c_str();
                return true;
            }
            var->value = nullptr;
            return false;
        }
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: {
            if (!data) return false;
            *reinterpret_cast<bool*>(data) = self->optionsDirty_.exchange(false, std::memory_order_acq_rel);
            return true;
        }
        case RETRO_ENVIRONMENT_GET_CAN_DUPE: {
            if (!data) return false;
            *reinterpret_cast<bool*>(data) = true;
            return true;
        }
        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
            if (!data) return false;
            auto* cb = reinterpret_cast<struct retro_log_callback*>(data);
            cb->log = &LibretroHost::coreLogCb;
            return true;
        }
        case RETRO_ENVIRONMENT_SET_GEOMETRY: {
            if (!data) return false;
            const auto* geom = reinterpret_cast<const struct retro_game_geometry*>(data);
            if (geom->aspect_ratio > 0.1f) {
                self->aspectRatio_.store(geom->aspect_ratio, std::memory_order_relaxed);
            }
            return true;
        }
        case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: {
            if (!data) return false;
            const auto* av = reinterpret_cast<const struct retro_system_av_info*>(data);
            if (av->timing.fps > 1.0) {
                self->fps_.store(av->timing.fps, std::memory_order_relaxed);
            }
            if (av->timing.sample_rate > 1000.0) {
                const double prev = self->sampleRate_.exchange(av->timing.sample_rate, std::memory_order_relaxed);
                if (prev != av->timing.sample_rate && self->audioConfigCb_) {
                    self->audioConfigCb_(av->timing.sample_rate);
                }
            }
            if (av->geometry.aspect_ratio > 0.1f) {
                self->aspectRatio_.store(av->geometry.aspect_ratio, std::memory_order_relaxed);
            }
            return true;
        }
        case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
            return false;
        case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
        case RETRO_ENVIRONMENT_SET_VARIABLES:
        case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
        case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
            return true;
        default:
            return false;
    }
}

void LibretroHost::videoRefreshCb(const void* data, unsigned width, unsigned height, size_t pitch) {
    LibretroHost* self = s_active;
    if (!self || !data || !self->videoCb_) return;
    self->videoCb_(data, width, height, pitch, self->pixelFormat_);
}

void LibretroHost::audioSampleCb(int16_t left, int16_t right) {
    LibretroHost* self = s_active;
    if (!self) return;
    int16_t frame[2] = {left, right};
    self->audioBuffer_.write(frame, 2);
}

size_t LibretroHost::audioSampleBatchCb(const int16_t* data, size_t frames) {
    LibretroHost* self = s_active;
    if (!self || !data || frames == 0) return frames;
    // Drop excess audio gracefully during fast-forward to keep ring buffer latency low
    if (self->fastForward_.load(std::memory_order_relaxed) > 1 &&
        self->audioBuffer_.availableRead() > 8192) {
        return frames;
    }
    self->audioBuffer_.write(data, frames * 2);
    return frames;
}

void LibretroHost::inputPollCb() {
    // Inputs are updated asynchronously via atomics and flushed before retro_run().
}

int16_t LibretroHost::inputStateCb(unsigned port, unsigned device, unsigned /*index*/, unsigned id) {
    LibretroHost* self = s_active;
    if (!self || port != 0) return 0;

    switch (device) {
        case RETRO_DEVICE_KEYBOARD:
            if (id < RETROK_LAST) {
                return self->keyStates_[id].load(std::memory_order_relaxed) ? 1 : 0;
            }
            return 0;

        case RETRO_DEVICE_MOUSE:
            switch (id) {
                case RETRO_DEVICE_ID_MOUSE_X:
                    return static_cast<int16_t>(self->mouseDx_.exchange(0, std::memory_order_relaxed));
                case RETRO_DEVICE_ID_MOUSE_Y:
                    return static_cast<int16_t>(self->mouseDy_.exchange(0, std::memory_order_relaxed));
                case RETRO_DEVICE_ID_MOUSE_LEFT:
                    return self->mouseLeft_.load(std::memory_order_relaxed) ? 1 : 0;
                case RETRO_DEVICE_ID_MOUSE_RIGHT:
                    return self->mouseRight_.load(std::memory_order_relaxed) ? 1 : 0;
                case RETRO_DEVICE_ID_MOUSE_MIDDLE:
                    return self->mouseMiddle_.load(std::memory_order_relaxed) ? 1 : 0;
                default:
                    return 0;
            }

        case RETRO_DEVICE_POINTER:
            switch (id) {
                case RETRO_DEVICE_ID_POINTER_X:
                    return self->pointerX_.load(std::memory_order_relaxed);
                case RETRO_DEVICE_ID_POINTER_Y:
                    return self->pointerY_.load(std::memory_order_relaxed);
                case RETRO_DEVICE_ID_POINTER_PRESSED:
                    return self->pointerPressed_.load(std::memory_order_relaxed) ? 1 : 0;
                default:
                    return 0;
            }

        case RETRO_DEVICE_JOYPAD:
            if (id < self->joypadStates_.size()) {
                return self->joypadStates_[id].load(std::memory_order_relaxed) ? 1 : 0;
            }
            return 0;

        default:
            return 0;
    }
}

void LibretroHost::coreLogCb(enum retro_log_level level, const char* fmt, ...) {
    LibretroHost* self = s_active;
    if (!self || !self->logCb_ || !fmt) return;
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    std::vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    self->logCb_(static_cast<int>(level), buf);
}

}  // namespace dosbox_host
