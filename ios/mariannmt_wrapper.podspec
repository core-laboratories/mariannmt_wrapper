#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint mariannmt_wrapper.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'mariannmt_wrapper'
  s.version          = '1.0.3'
  s.summary          = 'Offline Marian neural machine translation for Flutter.'
  s.description      = <<-DESC
Cross-platform Flutter FFI bindings for private, on-device Marian translation.
                       DESC
  s.homepage         = 'https://github.com/core-laboratories/mariannmt_wrapper'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Core Laboratories'

  # Build the C/C++ dependencies via CMake (iOS).
  #
  # Keep build logic in src/ + third_party/; CocoaPods only invokes CMake and
  # wires the resulting static libs into the final link.
  s.script_phase = {
    :name => 'Build mariannmt_wrapper (CMake)',
    :execution_position => :before_compile,
    :shell_path => '/bin/sh',
    :script => <<-SCRIPT
set -e

python3 "${PODS_TARGET_SRCROOT}/../tool/build_ios.py" \
  --source-root "${PODS_TARGET_SRCROOT}/.." \
  --build-root "${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios"

SCRIPT
  }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    # Ensure fenv rounding macros are available for simd_utils on iOS.
    'OTHER_CPLUSPLUSFLAGS' => '$(OTHER_CFLAGS) -std=c++17 -include fenv.h',

    # iOS ARM64: ensure simd_utils uses NEON path (not x86 SSE intrinsics).
    'GCC_PREPROCESSOR_DEFINITIONS[arch=arm64]' => '$(inherited) ARM=1 FMA=1 SSE=1 USE_SIMD_UTILS=1 __ARM_NEON=1 __ARM_NEON__=1',

    # Ensure headers resolve when compiling the forwarder ObjC++ file.
    'HEADER_SEARCH_PATHS' => '$(inherited) ' \
      '"${PODS_TARGET_SRCROOT}/../third_party/bergamot-translator" ' \
      '"${PODS_TARGET_SRCROOT}/../third_party/bergamot-translator/src" ' \
      '"${PODS_TARGET_SRCROOT}/../third_party/bergamot-translator/3rd_party/marian-dev/src" ' \
      '"${PODS_TARGET_SRCROOT}/../third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party" ' \
      '"${PODS_TARGET_SRCROOT}/../third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party/ruy" ' \
      '"${PODS_TARGET_SRCROOT}/../third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party/sentencepiece/src" ' \
      '"${PODS_TARGET_SRCROOT}/../third_party/bergamot-translator/3rd_party/ssplit-cpp/src/ssplit" ' \
      '"${PODS_TARGET_SRCROOT}/../third_party/cld2/public"',

    # Link CMake-built static libraries (paths are produced by script_phase above).
    'LIBRARY_SEARCH_PATHS' => '$(inherited) ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}"',
    'OTHER_LDFLAGS' => '$(inherited) -lmariannmt_dependencies -liconv -pthread -framework Accelerate',
  }

  # Static CocoaPods integrations resolve these dependencies in the app link.
  s.user_target_xcconfig = {
    'LIBRARY_SEARCH_PATHS' => '$(inherited) ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}"',
    'OTHER_LDFLAGS' => '$(inherited) -lmariannmt_dependencies -liconv -pthread -framework Accelerate',
  }

  s.swift_version = '5.0'
end
