Pod::Spec.new do |s|
  s.name             = 'dosbox_engine'
  s.version          = '0.1.0'
  s.summary          = 'Cross-platform Flutter plugin wrapping C++17 LibretroHost for DOSBox-Pure.'
  s.description      = 'Provides zero-copy CVPixelBuffer/Metal rendering and AudioUnit low-latency audio for DOSBox-Pure on iOS/iPadOS.'
  s.homepage         = 'https://github.com/grayson85/DosGameinAndroid'
  s.license          = { :type => 'GPL-2.0' }
  s.author           = { 'DosBox CN' => 'dosbox-cn@example.com' }
  s.source           = { :path => '.' }

  s.source_files = 'Classes/**/*.{h,mm}'
  s.public_header_files = 'Classes/DosboxEnginePlugin.h'
  s.vendored_libraries = 'Libs/libdosbox_pure_ios.a'

  s.dependency 'Flutter'
  s.platform = :ios, '14.0'

  s.frameworks = 'AudioToolbox', 'AVFoundation', 'CoreVideo', 'CoreMedia', 'Foundation', 'UIKit'
  s.libraries = 'c++', 'z'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../src"',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) DOSBOX_STATIC_CORE=1',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64 arm64'
  }
end
