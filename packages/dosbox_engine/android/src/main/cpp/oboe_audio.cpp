#include "oboe_audio.h"

#include <android/log.h>
#include <cstring>

#define AUDIO_LOG_TAG "DosboxOboeAudio"
#define AUDIO_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, AUDIO_LOG_TAG, __VA_ARGS__)

namespace dosbox_host {

OboeAudio::OboeAudio(AudioRingBuffer& ringBuffer) : ringBuffer_(ringBuffer) {}

OboeAudio::~OboeAudio() {
    stop();
}

bool OboeAudio::start(int32_t sampleRate) {
    stop();
    std::lock_guard<std::mutex> lk(streamMutex_);
    sampleRate_ = sampleRate > 8000 ? sampleRate : 44100;

    oboe::AudioStreamBuilder builder;
    builder.setDirection(oboe::Direction::Output)
        ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
        ->setSharingMode(oboe::SharingMode::Shared)
        ->setFormat(oboe::AudioFormat::I16)
        ->setChannelCount(oboe::ChannelCount::Stereo)
        ->setSampleRate(sampleRate_)
        ->setSampleRateConversionQuality(oboe::SampleRateConversionQuality::Medium)
        ->setDataCallback(this);

    oboe::Result result = builder.openStream(stream_);
    if (result != oboe::Result::OK || !stream_) {
        AUDIO_LOGE("Failed to open Oboe stream: %s", oboe::convertToText(result));
        return false;
    }

    result = stream_->requestStart();
    if (result != oboe::Result::OK) {
        AUDIO_LOGE("Failed to start Oboe stream: %s", oboe::convertToText(result));
        stream_->close();
        stream_.reset();
        return false;
    }
    return true;
}

void OboeAudio::pause() {
    std::lock_guard<std::mutex> lk(streamMutex_);
    if (stream_) {
        stream_->requestPause();
    }
}

void OboeAudio::resume() {
    std::lock_guard<std::mutex> lk(streamMutex_);
    if (stream_) {
        stream_->requestStart();
    }
}

void OboeAudio::stop() {
    std::lock_guard<std::mutex> lk(streamMutex_);
    if (stream_) {
        stream_->requestStop();
        stream_->close();
        stream_.reset();
    }
}

oboe::DataCallbackResult OboeAudio::onAudioReady(
    oboe::AudioStream* /*audioStream*/, void* audioData, int32_t numFrames) {
    auto* out = static_cast<int16_t*>(audioData);
    const size_t samplesNeeded = static_cast<size_t>(numFrames) * 2;
    const size_t samplesRead = ringBuffer_.read(out, samplesNeeded);
    if (samplesRead < samplesNeeded) {
        std::memset(out + samplesRead, 0, (samplesNeeded - samplesRead) * sizeof(int16_t));
    }
    return oboe::DataCallbackResult::Continue;
}

}  // namespace dosbox_host
