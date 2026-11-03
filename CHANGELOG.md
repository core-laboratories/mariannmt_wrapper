# Changelog

## 1.0.4

- Fix universal macOS release builds by building ARM64 and x86_64 dependencies
  separately and linking one combined archive.

- Follow the latest official Bergamot upstream with a verified, pinned snapshot.
- Preserve mobile and Windows portability fixes when refreshing native sources.
- Bundle checksum-verified PCRE2 during refresh for offline consumer builds.
- Add real-model native tests and daily upstream compatibility checks that open
  update PRs only after native and Flutter platform checks pass.

## 1.0.3

- Fix iOS simulator linker errors by building every requested architecture and
  combining the native dependencies into one universal static archive.
- Select ARM/NEON or x86/intgemm configuration per target architecture.

## 1.0.2

- Maintenance release with no public API or native-engine compatibility
  changes from 1.0.1.

## 1.0.1

- Published after synchronizing the renamed package with its public repository.

## 1.0.0

- Renamed the package and public API to `mariannmt_wrapper`.
- Added Windows build support and MSVC-specific compiler configuration.
- Added reproducible vendored-source updates without Git submodules.
- Updated Dart and Flutter dependencies.
- Added automated analysis, tests, platform builds, and pub.dev publishing.
- Documented offline model loading, translation, pivot translation, and
  language detection.
