cmake_minimum_required(VERSION 3.22.1)
project(dosbox_host LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(oboe REQUIRED CONFIG)

set(SHARED_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../src")

add_library(dosbox_host SHARED
    "${SHARED_SRC_DIR}/libretro_host.cpp"
    gl_renderer.cpp
    oboe_audio.cpp
    jni_bridge.cpp
)

target_include_directories(dosbox_host PRIVATE
    "${SHARED_SRC_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}"
)

target_link_libraries(dosbox_host
    oboe::oboe
    EGL
    GLESv3
    android
    log
)

# 16KB page-size alignment for Android 15+
target_link_options(dosbox_host PRIVATE "-Wl,-z,max-page-size=16384")
