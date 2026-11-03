# Release preparation: 1.0.4

Validated on 2026-11-03 using Flutter 3.47.2, Dart 3.13.2 and Xcode 27.2.

## Changes

- Package, CMake and both Apple podspec versions are 1.0.4.
- Official Bergamot HEAD is pinned to `9271618ebbdc5d21ac4dc4df9e72beb7ce644774`.
- Universal macOS builds compile ARM64 and Intel dependencies separately and
  combine them into one archive. CPU flags and the external PCRE2 build now
  follow the target architecture instead of the build host.
- The shared Apple archive builder covers macOS, iOS devices and simulators.
- The daily upstream workflow also tests a universal macOS release build.
- Lock files remain excluded from Git and publication. Native revisions are
  maintained in `tool/native_sources.conf`.

## Validation

| Check                                  | Result                                                                 |
| -------------------------------------- | ---------------------------------------------------------------------- |
| Dart formatting and Flutter analysis   | Passed; no changes or issues                                           |
| Dart tests                             | 3 passed                                                               |
| Native updater safety tests            | 6 passed                                                               |
| Apple archive-builder tests            | 3 passed, covering universal macOS/simulator and ARM64 device archives |
| Standalone native runtime tests        | 5 passed with real Mozilla models                                      |
| Packaged macOS framework runtime tests | 5 passed with real Mozilla models                                      |
| Android ARM64 release example          | Built successfully                                                     |
| iOS ARM64 device release example       | Built successfully without code signing                                |
| macOS universal release example        | Built successfully for arm64 and x86_64                                |
| Apple FFI exports                      | All seven API functions present in both built frameworks               |
| Portability patch                      | Applies cleanly to the pinned official upstream sources                |
| Markdown and GitHub Actions workflows  | Lint passed                                                            |
| Publication dry run                    | 0 warnings; compressed package approximately 25 MB                     |
| Pana 0.23.19                           | 160/160; generated API docs have 0 warnings and 0 errors               |

Real-model checks cover batch translation, repeat calls and English/Spanish
pivot translation. The model files are checksum-pinned test inputs and are not
published with the package. Native runtime checks use the actual compiled
library, including the framework inside the macOS release application.

Linux and Windows native builds are configured in CI and were not executed on
this macOS host. Check those jobs before publishing.

## Artifacts

- `example/build/app/outputs/flutter-apk/app-release.apk`
- `example/build/ios/iphoneos/Runner.app`
- `example/build/macos/Build/Products/Release/mariannmt_wrapper_example.app`

These are example-app validation builds. The unsigned iOS application is not an
App Store submission artifact.

## Publication

Review and commit the release changes, then verify CI. The release tag must be
`1.0.4` exactly, without a `v` prefix, because the publishing workflow compares
the tag with `pubspec.yaml`. Pushing that tag triggers the configured pub.dev
publishing workflow.

No tag was created, nothing was pushed, and no package was published during this
release preparation. Publication validation used a clean temporary snapshot so
local uncommitted release changes did not produce misleading Git warnings.
