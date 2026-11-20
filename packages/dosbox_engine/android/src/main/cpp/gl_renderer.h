#pragma once

#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <android/native_window.h>

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <mutex>

namespace dosbox_host {

// Renders Libretro video frames directly into an Android ANativeWindow (Flutter SurfaceTexture)
// using OpenGL ES 3.0 with zero CPU color conversion.
class GlRenderer {
public:
    GlRenderer() = default;
    ~GlRenderer();

    void setWindow(ANativeWindow* window);
    void setLinearFilter(bool enabled);

    // Must be called from the emulation thread.
    void renderFrame(const void* data, unsigned width, unsigned height, size_t pitch, unsigned pixelFormat);

    // Must be called after emulation thread stops.
    void release();

private:
    bool initEgl();
    void destroyEgl();
    bool initGlResources();
    void applyTextureFilter();

    std::mutex windowMutex_;
    ANativeWindow* pendingWindow_ = nullptr;
    ANativeWindow* activeWindow_ = nullptr;
    bool windowChanged_ = false;

    EGLDisplay display_ = EGL_NO_DISPLAY;
    EGLContext context_ = EGL_NO_CONTEXT;
    EGLSurface surface_ = EGL_NO_SURFACE;
    EGLConfig config_ = nullptr;

    GLuint program_ = 0;
    GLuint texture_ = 0;
    GLint swapRbLoc_ = -1;

    unsigned texWidth_ = 0;
    unsigned texHeight_ = 0;
    unsigned texFormat_ = 0;

    std::atomic<bool> linearFilter_{false};
    bool appliedLinearFilter_ = false;
};

}  // namespace dosbox_host
