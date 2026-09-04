#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint mariannmt_wrapper.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'mariannmt_wrapper'
  s.version          = '1.0.0'
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

SRC_DIR="${PODS_TARGET_SRCROOT}/../src"
# Put CMake build outputs next to Pods so both Pod target and user target can reference them.
BUILD_DIR="${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}"
SYS_PROC="${ARCHS%% *}"

cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" \
  -DIOS=ON \
  -DIOS_ARCH="${SYS_PROC}" \
  -DCMAKE_BUILD_TYPE="${CONFIGURATION}" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_SYSTEM_PROCESSOR="${SYS_PROC}" \
  -DCMAKE_OSX_SYSROOT="${SDKROOT}" \
  -DCMAKE_OSX_ARCHITECTURES= \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET}"

cmake --build "${BUILD_DIR}" --target mariannmt_wrapper -j 8
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
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}" ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}/lib" ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}/third_party" ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}/third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party/sentencepiece/src" ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}/third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party/ruy/ruy" ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}/third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party/ruy/ruy/profiler" ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}/third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party/ruy/third_party/cpuinfo" ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}/third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party/ruy/third_party/cpuinfo/deps/clog" ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}/third_party/bergamot-translator/3rd_party/ssplit-cpp/src"',

    'OTHER_LDFLAGS' => '$(inherited) ' \
      '-lbergamot-translator -lcld2 -lyaml-cpp -lmarian-data -lmarian -lssplit ' \
      '-lsentencepiece_train -lsentencepiece ' \
      '-lruy_context_get_ctx -lruy_context -lruy_frontend -lruy_kernel_arm -lruy_kernel_avx -lruy_kernel_avx2_fma -lruy_kernel_avx512 ' \
      '-lruy_apply_multiplier -lruy_pack_arm -lruy_pack_avx -lruy_pack_avx2_fma -lruy_pack_avx512 -lruy_prepare_packed_matrices ' \
      '-lruy_trmul -lruy_ctx -lruy_allocator -lruy_prepacked_cache -lruy_system_aligned_alloc ' \
      '-lruy_have_built_path_for_avx -lruy_have_built_path_for_avx2_fma -lruy_have_built_path_for_avx512 ' \
      '-lruy_thread_pool -lruy_blocking_counter -lruy_wait -lruy_denormal -lruy_block_map -lruy_tune -lruy_cpuinfo ' \
      '-lcpuinfo -lclog -lruy_profiler_instrumentation ' \
      '-lpcre2-8 -liconv -pthread -framework Accelerate',
  }

  # If Pods are linked statically, the final link happens in the user target (Runner).
  s.user_target_xcconfig = {
    'LIBRARY_SEARCH_PATHS' => '$(inherited) ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}" ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}/lib" ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}/third_party" ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}/third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party/sentencepiece/src" ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}/third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party/ruy/ruy" ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}/third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party/ruy/ruy/profiler" ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}/third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party/ruy/third_party/cpuinfo" ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}/third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party/ruy/third_party/cpuinfo/deps/clog" ' \
      '"${PODS_ROOT}/../.cmake-build/mariannmt_wrapper/ios/${CONFIGURATION}-${PLATFORM_NAME}-${ARCHS}/third_party/bergamot-translator/3rd_party/ssplit-cpp/src"',

    'OTHER_LDFLAGS' => '$(inherited) ' \
      '-lbergamot-translator -lcld2 -lyaml-cpp -lmarian-data -lmarian -lssplit ' \
      '-lsentencepiece_train -lsentencepiece ' \
      '-lruy_context_get_ctx -lruy_context -lruy_frontend -lruy_kernel_arm -lruy_kernel_avx -lruy_kernel_avx2_fma -lruy_kernel_avx512 ' \
      '-lruy_apply_multiplier -lruy_pack_arm -lruy_pack_avx -lruy_pack_avx2_fma -lruy_pack_avx512 -lruy_prepare_packed_matrices ' \
      '-lruy_trmul -lruy_ctx -lruy_allocator -lruy_prepacked_cache -lruy_system_aligned_alloc ' \
      '-lruy_have_built_path_for_avx -lruy_have_built_path_for_avx2_fma -lruy_have_built_path_for_avx512 ' \
      '-lruy_thread_pool -lruy_blocking_counter -lruy_wait -lruy_denormal -lruy_block_map -lruy_tune -lruy_cpuinfo ' \
      '-lcpuinfo -lclog -lruy_profiler_instrumentation ' \
      '-lpcre2-8 -liconv -pthread -framework Accelerate',
  }

  s.swift_version = '5.0'
end
