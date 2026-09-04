# Marian NMT Wrapper

`mariannmt_wrapper` is a Flutter FFI plugin for private, offline neural
machine translation on Android, iOS, Linux, macOS, and Windows.

The package runs compatible Marian translation models locally. Text and model
data are passed directly to native code and are not sent to a remote
translation service.

## Features

- Offline single and batch translation
- Pivot translation through an intermediate language
- Local language detection
- Background-isolate APIs for work that should not block Flutter's UI isolate
- Native builds for Android, iOS, Linux, macOS, and Windows
- Compatible with models produced by [Mozilla Translations](https://github.com/mozilla/translations)

## Requirements

- Flutter 3.32 or newer
- Dart 3.8 or newer
- A C++17 toolchain
- CMake 3.14 or newer for desktop builds
- Visual Studio 2022 with **Desktop development with C++** for Windows

Native dependencies are included as reproducible source snapshots. Consumers
do not need Git submodules and plugin builds do not download source code.

## Installation

```yaml
dependencies:
  mariannmt_wrapper: ^1.0.0
```

## Usage

```dart
import 'package:mariannmt_wrapper/mariannmt_wrapper.dart';

Future<String> translate(String config, String text) async {
  await MarianTranslator.initializeServiceAsync();
  await MarianTranslator.loadModelAsync(config, 'en-de');

  final translated = await MarianTranslator.translateMultipleAsync(
    <String>[text],
    'en-de',
  );
  return translated.single;
}
```

The model configuration is YAML and should contain absolute paths to the model,
vocabulary, and shortlist files installed by the host application. See the
[example](example/) for a complete model-loading flow.

Call `MarianTranslator.cleanupAsync(true)` when the translation service is no
longer required. Prefer asynchronous methods in Flutter UI code because model
initialization and inference are CPU-intensive.

## Updating native sources

Upstream revisions are recorded in
[`native_sources.lock`](native_sources.lock). Maintainers can refresh the
vendored snapshots with:

```shell
./tool/update_native_sources.sh
```

The script clones exact upstream sources into a temporary directory, initializes
their required dependencies, applies the portability patch, removes Git metadata
and non-runtime material, and replaces the vendored source tree. Review and test
that change before committing it. Builds never follow an unpinned branch.

## Development

```shell
flutter pub get
dart run ffigen --config ffigen.yaml
flutter analyze
flutter test
flutter build apk --debug
flutter build linux --debug
flutter build macos --debug
flutter build windows --debug
```

Only run platform build commands on their matching host operating system.

## Model provenance

Mozilla's translation project contains the training pipeline, model registry,
and inference integration that power Firefox Translations. Model quality,
supported language pairs, model licenses, and file formats are determined by
the selected model release. Applications should preserve and display the
metadata and license shipped with each downloaded model.

## License

Licensed under the [Mozilla Public License 2.0](LICENSE).
