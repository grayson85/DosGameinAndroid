#include "gl_renderer.h"
#include "libretro_host.h"
#include "oboe_audio.h"

#include <android/log.h>
#include <android/native_window_jni.h>
#include <jni.h>

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#define JNI_LOG_TAG "DosboxEngineJNI"
#define JNI_LOGI(...) __android_log_print(ANDROID_LOG_INFO, JNI_LOG_TAG, __VA_ARGS__)
#define JNI_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, JNI_LOG_TAG, __VA_ARGS__)

namespace {

struct EngineInstance {
    dosbox_host::LibretroHost host;
    dosbox_host::GlRenderer renderer;
    std::unique_ptr<dosbox_host::OboeAudio> audio;

    EngineInstance() {
        audio = std::make_unique<dosbox_host::OboeAudio>(host.audioBuffer());
        host.setVideoCallback([this](const void* data, unsigned w, unsigned h,
                                     size_t pitch, unsigned fmt) {
            renderer.renderFrame(data, w, h, pitch, fmt);
        });
        host.setAudioConfigCallback([this](double sampleRate) {
            audio->start(static_cast<int32_t>(sampleRate));
        });
        host.setLogCallback([](int level, const char* msg) {
            if (level >= RETRO_LOG_ERROR) {
                JNI_LOGE("[core] %s", msg);
            } else {
                JNI_LOGI("[core] %s", msg);
            }
        });
    }

    ~EngineInstance() {
        host.stop();
        if (audio) audio->stop();
        renderer.release();
    }
};

std::unique_ptr<EngineInstance> g_engine;

std::string jstringToStd(JNIEnv* env, jstring s) {
    if (!s) return "";
    const char* chars = env->GetStringUTFChars(s, nullptr);
    std::string out(chars ? chars : "");
    if (chars) env->ReleaseStringUTFChars(s, chars);
    return out;
}

}  // namespace

extern "C" {

JNIEXPORT jstring JNICALL
Java_com_gs_dosbox_1engine_DosboxNative_nativeStartGame(
    JNIEnv* env,
    jclass /*clazz*/,
    jstring jCorePath,
    jstring jGamePath,
    jstring jSaveDir,
    jstring jSystemDir,
    jobject jSurface,
    jboolean jLinearFilter,
    jobjectArray jOptionKeys,
    jobjectArray jOptionValues) {

    g_engine.reset();
    g_engine = std::make_unique<EngineInstance>();

    ANativeWindow* window = ANativeWindow_fromSurface(env, jSurface);
    if (!window) {
        g_engine.reset();
        return env->NewStringUTF("Failed to acquire ANativeWindow from Surface");
    }
    g_engine->renderer.setLinearFilter(jLinearFilter == JNI_TRUE);
    g_engine->renderer.setWindow(window);
    ANativeWindow_release(window);  // GlRenderer acquired its own reference

    dosbox_host::HostConfig config;
    config.corePath = jstringToStd(env, jCorePath);
    config.gamePath = jstringToStd(env, jGamePath);
    config.saveDir = jstringToStd(env, jSaveDir);
    config.systemDir = jstringToStd(env, jSystemDir);

    if (jOptionKeys && jOptionValues) {
        const jsize len = env->GetArrayLength(jOptionKeys);
        for (jsize i = 0; i < len; ++i) {
            auto k = static_cast<jstring>(env->GetObjectArrayElement(jOptionKeys, i));
            auto v = static_cast<jstring>(env->GetObjectArrayElement(jOptionValues, i));
            config.coreOptions[jstringToStd(env, k)] = jstringToStd(env, v);
            env->DeleteLocalRef(k);
            env->DeleteLocalRef(v);
        }
    }

    std::string err;
    if (!g_engine->host.start(config, err)) {
        JNI_LOGE("Failed to start DOSBox host: %s", err.c_str());
        g_engine.reset();
        return env->NewStringUTF(err.c_str());
    }

    return nullptr;  // null == success
}

JNIEXPORT jfloat JNICALL
Java_com_gs_dosbox_1engine_DosboxNative_nativeGetAspectRatio(JNIEnv* /*env*/, jclass /*clazz*/) {
    return g_engine ? g_engine->host.aspectRatio() : (4.0f / 3.0f);
}

JNIEXPORT void JNICALL
Java_com_gs_dosbox_1engine_DosboxNative_nativePause(JNIEnv* /*env*/, jclass /*clazz*/) {
    if (g_engine) {
        g_engine->host.pause();
        if (g_engine->audio) g_engine->audio->pause();
    }
}

JNIEXPORT void JNICALL
Java_com_gs_dosbox_1engine_DosboxNative_nativeResume(JNIEnv* /*env*/, jclass /*clazz*/) {
    if (g_engine) {
        if (g_engine->audio) g_engine->audio->resume();
        g_engine->host.resume();
    }
}

JNIEXPORT void JNICALL
Java_com_gs_dosbox_1engine_DosboxNative_nativeStop(JNIEnv* /*env*/, jclass /*clazz*/) {
    g_engine.reset();
}

JNIEXPORT void JNICALL
Java_com_gs_dosbox_1engine_DosboxNative_nativeReset(JNIEnv* /*env*/, jclass /*clazz*/) {
    if (g_engine) g_engine->host.reset();
}

JNIEXPORT void JNICALL
Java_com_gs_dosbox_1engine_DosboxNative_nativeSetFastForward(
    JNIEnv* /*env*/, jclass /*clazz*/, jint multiplier) {
    if (g_engine) g_engine->host.setFastForward(multiplier);
}

JNIEXPORT void JNICALL
Java_com_gs_dosbox_1engine_DosboxNative_nativeSetLinearFilter(
    JNIEnv* /*env*/, jclass /*clazz*/, jboolean enabled) {
    if (g_engine) g_engine->renderer.setLinearFilter(enabled == JNI_TRUE);
}

JNIEXPORT void JNICALL
Java_com_gs_dosbox_1engine_DosboxNative_nativeUpdateCoreOption(
    JNIEnv* env, jclass /*clazz*/, jstring jKey, jstring jValue) {
    if (g_engine) {
        g_engine->host.updateCoreOption(jstringToStd(env, jKey), jstringToStd(env, jValue));
    }
}

JNIEXPORT void JNICALL
Java_com_gs_dosbox_1engine_DosboxNative_nativeSendKeyEvent(
    JNIEnv* /*env*/, jclass /*clazz*/, jint retroKey, jboolean down) {
    if (g_engine) {
        g_engine->host.sendKeyEvent(static_cast<unsigned>(retroKey), down == JNI_TRUE);
    }
}

JNIEXPORT void JNICALL
Java_com_gs_dosbox_1engine_DosboxNative_nativeSendMouseDelta(
    JNIEnv* /*env*/, jclass /*clazz*/, jint dx, jint dy) {
    if (g_engine) g_engine->host.sendMouseDelta(dx, dy);
}

JNIEXPORT void JNICALL
Java_com_gs_dosbox_1engine_DosboxNative_nativeSendMouseButton(
    JNIEnv* /*env*/, jclass /*clazz*/, jint button, jboolean down) {
    if (g_engine) g_engine->host.sendMouseButton(button, down == JNI_TRUE);
}

JNIEXPORT void JNICALL
Java_com_gs_dosbox_1engine_DosboxNative_nativeSendPointer(
    JNIEnv* /*env*/, jclass /*clazz*/, jint normX, jint normY, jboolean pressed) {
    if (g_engine) {
        g_engine->host.sendPointer(
            static_cast<int16_t>(normX), static_cast<int16_t>(normY), pressed == JNI_TRUE);
    }
}

JNIEXPORT void JNICALL
Java_com_gs_dosbox_1engine_DosboxNative_nativeSendJoypadButton(
    JNIEnv* /*env*/, jclass /*clazz*/, jint retroId, jboolean down) {
    if (g_engine) {
        g_engine->host.sendJoypadButton(static_cast<unsigned>(retroId), down == JNI_TRUE);
    }
}

JNIEXPORT jbyteArray JNICALL
Java_com_gs_dosbox_1engine_DosboxNative_nativeSaveState(JNIEnv* env, jclass /*clazz*/) {
    if (!g_engine) return nullptr;
    std::vector<uint8_t> data;
    if (!g_engine->host.serializeState(data) || data.empty()) {
        return nullptr;
    }
    jbyteArray arr = env->NewByteArray(static_cast<jsize>(data.size()));
    if (arr) {
        env->SetByteArrayRegion(arr, 0, static_cast<jsize>(data.size()),
                                reinterpret_cast<const jbyte*>(data.data()));
    }
    return arr;
}

JNIEXPORT jboolean JNICALL
Java_com_gs_dosbox_1engine_DosboxNative_nativeLoadState(
    JNIEnv* env, jclass /*clazz*/, jbyteArray jData) {
    if (!g_engine || !jData) return JNI_FALSE;
    const jsize len = env->GetArrayLength(jData);
    if (len <= 0) return JNI_FALSE;
    jbyte* bytes = env->GetByteArrayElements(jData, nullptr);
    if (!bytes) return JNI_FALSE;
    const bool ok = g_engine->host.unserializeState(
        reinterpret_cast<const uint8_t*>(bytes), static_cast<size_t>(len));
    env->ReleaseByteArrayElements(jData, bytes, JNI_ABORT);
    return ok ? JNI_TRUE : JNI_FALSE;
}

}  // extern "C"
