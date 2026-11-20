#include "gl_renderer.h"
#include "libretro.h"

#include <android/log.h>

#define GL_LOG_TAG "DosboxGlRenderer"
#define GL_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, GL_LOG_TAG, __VA_ARGS__)

namespace dosbox_host {

namespace {

const char* kVertexShader = R"(#version 300 es
layout(location = 0) in vec2 aPos;
layout(location = 1) in vec2 aTexCoord;
out vec2 vTexCoord;
void main() {
    gl_Position = vec4(aPos, 0.0, 1.0);
    vTexCoord = aTexCoord;
}
)";

const char* kFragmentShader = R"(#version 300 es
precision mediump float;
in vec2 vTexCoord;
uniform sampler2D uTex;
uniform int uSwapRB;
out vec4 fragColor;
void main() {
    vec4 c = texture(uTex, vTexCoord);
    if (uSwapRB != 0) {
        fragColor = vec4(c.b, c.g, c.r, 1.0);
    } else {
        fragColor = vec4(c.r, c.g, c.b, 1.0);
    }
}
)";

GLuint compileShader(GLenum type, const char* src) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &src, nullptr);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char logBuf[512];
        glGetShaderInfoLog(shader, sizeof(logBuf), nullptr, logBuf);
        GL_LOGE("Shader compile failed: %s", logBuf);
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

}  // namespace

GlRenderer::~GlRenderer() {
    release();
}

void GlRenderer::setWindow(ANativeWindow* window) {
    std::lock_guard<std::mutex> lk(windowMutex_);
    if (pendingWindow_) {
        ANativeWindow_release(pendingWindow_);
    }
    pendingWindow_ = window;
    if (pendingWindow_) {
        ANativeWindow_acquire(pendingWindow_);
    }
    windowChanged_ = true;
}

void GlRenderer::setLinearFilter(bool enabled) {
    linearFilter_.store(enabled, std::memory_order_relaxed);
}

bool GlRenderer::initEgl() {
    if (!activeWindow_) return false;

    display_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display_ == EGL_NO_DISPLAY || !eglInitialize(display_, nullptr, nullptr)) {
        GL_LOGE("eglInitialize failed");
        return false;
    }

    const EGLint configAttribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };
    EGLint numConfigs = 0;
    if (!eglChooseConfig(display_, configAttribs, &config_, 1, &numConfigs) || numConfigs < 1) {
        GL_LOGE("eglChooseConfig failed");
        return false;
    }

    const EGLint ctxAttribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };
    context_ = eglCreateContext(display_, config_, EGL_NO_CONTEXT, ctxAttribs);
    if (context_ == EGL_NO_CONTEXT) {
        GL_LOGE("eglCreateContext failed");
        return false;
    }

    surface_ = eglCreateWindowSurface(display_, config_, activeWindow_, nullptr);
    if (surface_ == EGL_NO_SURFACE) {
        GL_LOGE("eglCreateWindowSurface failed");
        return false;
    }

    if (!eglMakeCurrent(display_, surface_, surface_, context_)) {
        GL_LOGE("eglMakeCurrent failed");
        return false;
    }

    eglSwapInterval(display_, 0);  // Frame pacing is handled by LibretroHost
    return initGlResources();
}

bool GlRenderer::initGlResources() {
    GLuint vs = compileShader(GL_VERTEX_SHADER, kVertexShader);
    GLuint fs = compileShader(GL_FRAGMENT_SHADER, kFragmentShader);
    if (!vs || !fs) return false;

    program_ = glCreateProgram();
    glAttachShader(program_, vs);
    glAttachShader(program_, fs);
    glLinkProgram(program_);
    glDeleteShader(vs);
    glDeleteShader(fs);

    GLint linked = 0;
    glGetProgramiv(program_, GL_LINK_STATUS, &linked);
    if (!linked) {
        GL_LOGE("Program link failed");
        glDeleteProgram(program_);
        program_ = 0;
        return false;
    }

    swapRbLoc_ = glGetUniformLocation(program_, "uSwapRB");

    glGenTextures(1, &texture_);
    glBindTexture(GL_TEXTURE_2D, texture_);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    appliedLinearFilter_ = !linearFilter_.load(std::memory_order_relaxed);
    applyTextureFilter();

    texWidth_ = 0;
    texHeight_ = 0;
    texFormat_ = 0;
    return true;
}

void GlRenderer::applyTextureFilter() {
    const bool linear = linearFilter_.load(std::memory_order_relaxed);
    if (linear == appliedLinearFilter_) return;
    appliedLinearFilter_ = linear;
    const GLint mode = linear ? GL_LINEAR : GL_NEAREST;
    glBindTexture(GL_TEXTURE_2D, texture_);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, mode);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, mode);
}

void GlRenderer::destroyEgl() {
    if (display_ != EGL_NO_DISPLAY) {
        eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (texture_) {
            glDeleteTextures(1, &texture_);
            texture_ = 0;
        }
        if (program_) {
            glDeleteProgram(program_);
            program_ = 0;
        }
        if (surface_ != EGL_NO_SURFACE) {
            eglDestroySurface(display_, surface_);
            surface_ = EGL_NO_SURFACE;
        }
        if (context_ != EGL_NO_CONTEXT) {
            eglDestroyContext(display_, context_);
            context_ = EGL_NO_CONTEXT;
        }
        eglTerminate(display_);
        display_ = EGL_NO_DISPLAY;
    }
    if (activeWindow_) {
        ANativeWindow_release(activeWindow_);
        activeWindow_ = nullptr;
    }
}

void GlRenderer::release() {
    destroyEgl();
    std::lock_guard<std::mutex> lk(windowMutex_);
    if (pendingWindow_) {
        ANativeWindow_release(pendingWindow_);
        pendingWindow_ = nullptr;
    }
    windowChanged_ = false;
}

void GlRenderer::renderFrame(
    const void* data, unsigned width, unsigned height, size_t pitch, unsigned pixelFormat) {
    if (!data || width == 0 || height == 0) return;

    {
        std::lock_guard<std::mutex> lk(windowMutex_);
        if (windowChanged_) {
            destroyEgl();
            activeWindow_ = pendingWindow_;
            pendingWindow_ = nullptr;
            windowChanged_ = false;
            if (activeWindow_) {
                ANativeWindow_setBuffersGeometry(activeWindow_, static_cast<int32_t>(width),
                                                 static_cast<int32_t>(height),
                                                 WINDOW_FORMAT_RGBA_8888);
                if (!initEgl()) {
                    destroyEgl();
                    return;
                }
            }
        }
    }

    if (display_ == EGL_NO_DISPLAY || surface_ == EGL_NO_SURFACE || !program_) return;

    const bool isXrgb8888 = (pixelFormat == RETRO_PIXEL_FORMAT_XRGB8888);
    const size_t bpp = isXrgb8888 ? 4 : 2;
    const GLint rowLength = static_cast<GLint>(pitch / bpp);

    glBindTexture(GL_TEXTURE_2D, texture_);
    applyTextureFilter();
    glPixelStorei(GL_UNPACK_ALIGNMENT, isXrgb8888 ? 4 : 2);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, rowLength);

    if (width != texWidth_ || height != texHeight_ || pixelFormat != texFormat_) {
        texWidth_ = width;
        texHeight_ = height;
        texFormat_ = pixelFormat;
        if (isXrgb8888) {
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, static_cast<GLsizei>(width),
                         static_cast<GLsizei>(height), 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
        } else {
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB565, static_cast<GLsizei>(width),
                         static_cast<GLsizei>(height), 0, GL_RGB, GL_UNSIGNED_SHORT_5_6_5, data);
        }
    } else {
        if (isXrgb8888) {
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, static_cast<GLsizei>(width),
                            static_cast<GLsizei>(height), GL_RGBA, GL_UNSIGNED_BYTE, data);
        } else {
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, static_cast<GLsizei>(width),
                            static_cast<GLsizei>(height), GL_RGB, GL_UNSIGNED_SHORT_5_6_5, data);
        }
    }
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);

    EGLint surfW = 0, surfH = 0;
    eglQuerySurface(display_, surface_, EGL_WIDTH, &surfW);
    eglQuerySurface(display_, surface_, EGL_HEIGHT, &surfH);
    glViewport(0, 0, surfW, surfH);

    static const GLfloat kQuad[] = {
        // x,    y,    u,    v  (flip V so top of DOS frame is top of texture)
        -1.0f, -1.0f, 0.0f, 1.0f,
         1.0f, -1.0f, 1.0f, 1.0f,
        -1.0f,  1.0f, 0.0f, 0.0f,
         1.0f,  1.0f, 1.0f, 0.0f,
    };

    glUseProgram(program_);
    glUniform1i(swapRbLoc_, isXrgb8888 ? 1 : 0);

    glEnableVertexAttribArray(0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), kQuad);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), kQuad + 2);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glDisableVertexAttribArray(0);
    glDisableVertexAttribArray(1);

    eglSwapBuffers(display_, surface_);
}

}  // namespace dosbox_host
