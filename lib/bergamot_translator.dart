import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:async';

import 'package:ffi/ffi.dart';

import 'bergamot_translator_bindings_generated.dart';

/// Bergamot 翻译器异常
class BergamotException implements Exception {
  final String message;
  final int? errorCode;

  BergamotException(this.message, [this.errorCode]);

  @override
  String toString() =>
      'BergamotException: $message${errorCode != null ? ' (code: $errorCode)' : ''}';
}

/// 语言检测结果
class DetectionResult {
  /// 语言代码（如 "en", "zh"）
  final String language;

  /// 是否可靠
  final bool isReliable;

  /// 置信度（0-100）
  final int confidence;

  DetectionResult({
    required this.language,
    required this.isReliable,
    required this.confidence,
  });

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    return DetectionResult(
      language: json['language'] as String,
      isReliable: json['isReliable'] as bool,
      confidence: json['confidence'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'language': language,
        'isReliable': isReliable,
        'confidence': confidence,
      };

  @override
  String toString() =>
      'DetectionResult(language: $language, isReliable: $isReliable, confidence: $confidence)';
}

/// 内部：后台 Isolate 调度器
///
/// 目的：将同步 FFI 调用移出 UI isolate，避免掉帧/卡顿，并降低 debug 模式下的体感延迟。
class _BergamotBackground {
  static _BergamotBackground? _instance;

  static _BergamotBackground get instance {
    _instance ??= _BergamotBackground._();
    return _instance!;
  }

  _BergamotBackground._();

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _receiveSub;
  Future<void>? _starting;

  int _nextId = 1;
  final Map<int, Completer<Object?>> _pending = {};

  Future<void> _ensureStarted() async {
    if (_sendPort != null) return;
    if (_starting != null) {
      await _starting!;
      return;
    }

    final handshake = Completer<SendPort>();
    _starting = () async {
      _receivePort ??= ReceivePort();

      // 监听来自 worker isolate 的响应（含握手 sendPort）
      _receiveSub ??= _receivePort!.listen((dynamic message) {
        if (message is SendPort) {
          _sendPort = message;
          if (!handshake.isCompleted) {
            handshake.complete(message);
          }
          return;
        }

        if (message is! Map) return;
        final id = message['id'];
        if (id is! int) return;

        final completer = _pending.remove(id);
        if (completer == null) return;

        final ok = message['ok'] == true;
        if (ok) {
          completer.complete(message['result']);
        } else {
          final err = message['error']?.toString() ?? 'Unknown error';
          completer.completeError(BergamotException(err));
        }
      });

      _isolate = await Isolate.spawn<_IsolateInit>(
        _bergamotWorkerMain,
        _IsolateInit(_receivePort!.sendPort),
        debugName: 'bergamot_translator_worker',
      );

      try {
        _sendPort = await handshake.future.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        throw BergamotException(
            'Failed to start bergamot worker isolate (timeout)');
      }
    }();

    try {
      await _starting!;
    } finally {
      _starting = null;
    }
  }

  Future<T> _call<T>(String cmd, Map<String, Object?> payload) async {
    await _ensureStarted();

    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;

    _sendPort!.send(<String, Object?>{
      'id': id,
      'cmd': cmd,
      ...payload,
    });

    final result = await completer.future;
    return result as T;
  }

  Future<void> initializeService() => _call<void>('init', const {});

  Future<void> loadModel(String cfg, String key) =>
      _call<void>('loadModel', <String, Object?>{'cfg': cfg, 'key': key});

  Future<List<String>> translateMultiple(List<String> inputs, String key) =>
      _call<List<String>>(
          'translateMultiple', <String, Object?>{'inputs': inputs, 'key': key});

  Future<List<String>> pivotMultiple(
          List<String> inputs, String firstKey, String secondKey) =>
      _call<List<String>>('pivotMultiple', <String, Object?>{
        'inputs': inputs,
        'firstKey': firstKey,
        'secondKey': secondKey,
      });

  Future<Map<String, Object?>> detectLanguage(String text, String? hint) =>
      _call<Map<String, Object?>>(
          'detectLanguage', <String, Object?>{'text': text, 'hint': hint});

  Future<void> cleanup(bool resetService) =>
      _call<void>('cleanup', <String, Object?>{'resetService': resetService});

  void shutdown() {
    // 让所有未完成的请求尽快失败，避免退出时 await 永久悬挂。
    if (_pending.isNotEmpty) {
      final err = BergamotException('Bergamot worker shutdown');
      for (final completer in _pending.values) {
        if (!completer.isCompleted) {
          completer.completeError(err);
        }
      }
      _pending.clear();
    }

    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _receiveSub?.cancel();
    _receiveSub = null;
    _receivePort?.close();
    _receivePort = null;
  }
}

class _IsolateInit {
  final SendPort mainSendPort;
  const _IsolateInit(this.mainSendPort);
}

void _bergamotWorkerMain(_IsolateInit init) {
  final mainSendPort = init.mainSendPort;
  final port = ReceivePort();
  mainSendPort.send(port.sendPort);

  // worker isolate 内部执行同步 FFI
  port.listen((dynamic raw) {
    if (raw is! Map) return;
    final id = raw['id'];
    final cmd = raw['cmd'];
    if (id is! int || cmd is! String) return;

    Map<String, Object?> ok(Object? result) =>
        <String, Object?>{'id': id, 'ok': true, 'result': result};
    Map<String, Object?> err(Object error) =>
        <String, Object?>{'id': id, 'ok': false, 'error': error.toString()};

    try {
      switch (cmd) {
        case 'init':
          BergamotTranslator.initializeService();
          mainSendPort.send(ok(null));
          return;
        case 'loadModel':
          BergamotTranslator.loadModel(
              raw['cfg'] as String, raw['key'] as String);
          mainSendPort.send(ok(null));
          return;
        case 'translateMultiple':
          final inputs = (raw['inputs'] as List).cast<String>();
          final key = raw['key'] as String;
          final out = BergamotTranslator.translateMultiple(inputs, key);
          mainSendPort.send(ok(out));
          return;
        case 'pivotMultiple':
          final inputs = (raw['inputs'] as List).cast<String>();
          final firstKey = raw['firstKey'] as String;
          final secondKey = raw['secondKey'] as String;
          final out =
              BergamotTranslator.pivotMultiple(inputs, firstKey, secondKey);
          mainSendPort.send(ok(out));
          return;
        case 'detectLanguage':
          final text = raw['text'] as String;
          final hint = raw['hint'] as String?;
          final res = BergamotTranslator.detectLanguage(text, hint);
          mainSendPort.send(ok(<String, Object?>{
            'language': res.language,
            'isReliable': res.isReliable,
            'confidence': res.confidence,
          }));
          return;
        case 'cleanup':
          BergamotTranslator.cleanup(raw['resetService'] as bool? ?? false);
          mainSendPort.send(ok(null));
          return;
        default:
          mainSendPort.send(err('Unknown command: $cmd'));
          return;
      }
    } catch (e) {
      mainSendPort.send(err(e));
    }
  });
}

/// Bergamot 翻译器
class BergamotTranslator {
  static const String _libName = 'bergamot_translator';

  /// 动态库实例
  static ffi.DynamicLibrary? _dylib;

  /// 绑定实例
  static BergamotTranslatorBindings? _bindings;

  /// 初始化动态库
  static void _ensureInitialized() {
    if (_dylib != null && _bindings != null) return;

    _dylib = () {
      if (Platform.isMacOS || Platform.isIOS) {
        return ffi.DynamicLibrary.open('$_libName.framework/$_libName');
      }
      if (Platform.isAndroid || Platform.isLinux) {
        return ffi.DynamicLibrary.open('lib$_libName.so');
      }
      if (Platform.isWindows) {
        return ffi.DynamicLibrary.open('$_libName.dll');
      }
      throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
    }();

    _bindings = BergamotTranslatorBindings(_dylib!);
  }

  /// 初始化翻译服务
  ///
  /// 必须在调用其他方法之前调用此方法。
  ///
  /// 抛出 [BergamotException] 如果初始化失败。
  static void initializeService() {
    _ensureInitialized();
    final result = _bindings!.bergamot_initialize_service();
    if (result != 0) {
      throw BergamotException('Failed to initialize service', result);
    }
  }

  /// 初始化翻译服务（后台 Isolate 版本）
  ///
  /// 推荐在 Flutter 场景使用：避免同步 FFI 阻塞 UI isolate。
  static Future<void> initializeServiceAsync() {
    return _BergamotBackground.instance.initializeService();
  }

  /// 加载模型到缓存
  ///
  /// [cfg] 模型配置字符串（YAML格式）
  /// [key] 模型缓存键，用于后续翻译时引用此模型
  ///
  /// 抛出 [BergamotException] 如果加载失败。
  static void loadModel(String cfg, String key) {
    _ensureInitialized();
    final cfgPtr = cfg.toNativeUtf8();
    final keyPtr = key.toNativeUtf8();
    try {
      final result = _bindings!.bergamot_load_model(
        cfgPtr.cast<ffi.Char>(),
        keyPtr.cast<ffi.Char>(),
      );
      if (result != 0) {
        // 提供更详细的错误信息
        throw BergamotException(
          'Failed to load model: $key. '
          'Please check: 1) Model files exist and are accessible, '
          '2) Config YAML format is correct, '
          '3) File paths in config are absolute and valid.',
          result,
        );
      }
    } catch (e) {
      if (e is BergamotException) {
        rethrow;
      }
      throw BergamotException('Unexpected error loading model $key: $e');
    } finally {
      malloc.free(cfgPtr);
      malloc.free(keyPtr);
    }
  }

  /// 加载模型（后台 Isolate 版本）
  ///
  /// 推荐在 Flutter 场景使用：避免同步 FFI 阻塞 UI isolate。
  static Future<void> loadModelAsync(String cfg, String key) {
    return _BergamotBackground.instance.loadModel(cfg, key);
  }

  /// 批量翻译
  ///
  /// [inputs] 要翻译的文本列表
  /// [key] 模型缓存键（必须已通过 [loadModel] 加载）
  ///
  /// 返回翻译结果列表，顺序与输入列表对应。
  ///
  /// 抛出 [BergamotException] 如果翻译失败。
  static List<String> translateMultiple(List<String> inputs, String key) {
    if (inputs.isEmpty) {
      return [];
    }

    _ensureInitialized();

    // 分配输入字符串数组
    final inputPtrs =
        inputs.map((s) => s.toNativeUtf8().cast<ffi.Char>()).toList();
    final inputsArray = malloc.allocate<ffi.Pointer<ffi.Char>>(
      ffi.sizeOf<ffi.Pointer<ffi.Char>>() * inputs.length,
    );

    for (int i = 0; i < inputs.length; i++) {
      inputsArray[i] = inputPtrs[i];
    }

    final keyPtr = key.toNativeUtf8().cast<ffi.Char>();
    final outputsPtr = malloc.allocate<ffi.Pointer<ffi.Pointer<ffi.Char>>>(
      ffi.sizeOf<ffi.Pointer<ffi.Pointer<ffi.Char>>>(),
    );
    final outputCountPtr = malloc<ffi.Int32>(ffi.sizeOf<ffi.Int32>());

    try {
      final result = _bindings!.bergamot_translate_multiple(
        inputsArray,
        inputs.length,
        keyPtr,
        outputsPtr,
        outputCountPtr.cast(),
      );

      if (result != 0) {
        throw BergamotException('Failed to translate', result);
      }

      final outputCount = outputCountPtr[0];
      final outputsArray = outputsPtr.value;

      final translations = <String>[];
      for (int i = 0; i < outputCount; i++) {
        final strPtr = outputsArray[i];
        translations.add(strPtr.cast<Utf8>().toDartString());
      }

      // 释放 C 分配的内存
      _bindings!.bergamot_free_string_array(outputsArray, outputCount);

      return translations;
    } finally {
      // 释放输入字符串
      for (final ptr in inputPtrs) {
        malloc.free(ptr);
      }
      malloc.free(inputsArray);
      malloc.free(keyPtr);
      malloc.free(outputsPtr);
      malloc.free(outputCountPtr);
    }
  }

  /// 批量翻译（后台 Isolate 版本）
  ///
  /// 推荐在 Flutter 场景使用：避免同步 FFI 阻塞 UI isolate。
  static Future<List<String>> translateMultipleAsync(
      List<String> inputs, String key) {
    return _BergamotBackground.instance.translateMultiple(inputs, key);
  }

  /// 翻译单个文本
  ///
  /// [input] 要翻译的文本
  /// [key] 模型缓存键（必须已通过 [loadModel] 加载）
  ///
  /// 返回翻译结果。
  ///
  /// 抛出 [BergamotException] 如果翻译失败。
  static String translate(String input, String key) {
    final results = translateMultiple([input], key);
    if (results.isEmpty) {
      throw BergamotException('Translation returned empty result');
    }
    return results.first;
  }

  /// 枢轴翻译（通过中间语言）
  ///
  /// [inputs] 要翻译的文本列表
  /// [firstKey] 第一个模型缓存键（源语言 -> 中间语言）
  /// [secondKey] 第二个模型缓存键（中间语言 -> 目标语言）
  ///
  /// 返回翻译结果列表，顺序与输入列表对应。
  ///
  /// 抛出 [BergamotException] 如果翻译失败。
  static List<String> pivotMultiple(
    List<String> inputs,
    String firstKey,
    String secondKey,
  ) {
    if (inputs.isEmpty) {
      return [];
    }

    _ensureInitialized();

    // 分配输入字符串数组
    final inputPtrs =
        inputs.map((s) => s.toNativeUtf8().cast<ffi.Char>()).toList();
    final inputsArray = malloc.allocate<ffi.Pointer<ffi.Char>>(
      ffi.sizeOf<ffi.Pointer<ffi.Char>>() * inputs.length,
    );

    for (int i = 0; i < inputs.length; i++) {
      inputsArray[i] = inputPtrs[i];
    }

    final firstKeyPtr = firstKey.toNativeUtf8().cast<ffi.Char>();
    final secondKeyPtr = secondKey.toNativeUtf8().cast<ffi.Char>();
    final outputsPtr = malloc.allocate<ffi.Pointer<ffi.Pointer<ffi.Char>>>(
      ffi.sizeOf<ffi.Pointer<ffi.Pointer<ffi.Char>>>(),
    );
    final outputCountPtr = malloc<ffi.Int32>(ffi.sizeOf<ffi.Int32>());

    try {
      final result = _bindings!.bergamot_pivot_multiple(
        firstKeyPtr,
        secondKeyPtr,
        inputsArray,
        inputs.length,
        outputsPtr,
        outputCountPtr.cast(),
      );

      if (result != 0) {
        throw BergamotException('Failed to pivot translate', result);
      }

      final outputCount = outputCountPtr[0];
      final outputsArray = outputsPtr.value;

      final translations = <String>[];
      for (int i = 0; i < outputCount; i++) {
        final strPtr = outputsArray[i];
        translations.add(strPtr.cast<Utf8>().toDartString());
      }

      // 释放 C 分配的内存
      _bindings!.bergamot_free_string_array(outputsArray, outputCount);

      return translations;
    } finally {
      // 释放输入字符串
      for (final ptr in inputPtrs) {
        malloc.free(ptr);
      }
      malloc.free(inputsArray);
      malloc.free(firstKeyPtr);
      malloc.free(secondKeyPtr);
      malloc.free(outputsPtr);
      malloc.free(outputCountPtr);
    }
  }

  /// 枢轴翻译（后台 Isolate 版本）
  ///
  /// 推荐在 Flutter 场景使用：避免同步 FFI 阻塞 UI isolate。
  static Future<List<String>> pivotMultipleAsync(
    List<String> inputs,
    String firstKey,
    String secondKey,
  ) {
    return _BergamotBackground.instance
        .pivotMultiple(inputs, firstKey, secondKey);
  }

  /// 枢轴翻译单个文本（通过中间语言）
  ///
  /// [input] 要翻译的文本
  /// [firstKey] 第一个模型缓存键（源语言 -> 中间语言）
  /// [secondKey] 第二个模型缓存键（中间语言 -> 目标语言）
  ///
  /// 返回翻译结果。
  ///
  /// 抛出 [BergamotException] 如果翻译失败。
  static String pivot(String input, String firstKey, String secondKey) {
    final results = pivotMultiple([input], firstKey, secondKey);
    if (results.isEmpty) {
      throw BergamotException('Pivot translation returned empty result');
    }
    return results.first;
  }

  /// 检测语言
  ///
  /// [text] 待检测的文本
  /// [hint] 可选的语言提示（如 "en", "zh"），可为 null
  ///
  /// 返回 [DetectionResult] 包含检测到的语言信息。
  ///
  /// 抛出 [BergamotException] 如果检测失败。
  static DetectionResult detectLanguage(String text, [String? hint]) {
    _ensureInitialized();

    final textPtr = text.toNativeUtf8();
    final hintPtr = hint?.toNativeUtf8();
    final resultPtr = malloc.allocate<BergamotDetectionResult>(
      ffi.sizeOf<BergamotDetectionResult>(),
    );

    try {
      final result = _bindings!.bergamot_detect_language(
        textPtr.cast<ffi.Char>(),
        hintPtr?.cast<ffi.Char>() ?? ffi.Pointer<ffi.Char>.fromAddress(0),
        resultPtr,
      );

      if (result != 0) {
        throw BergamotException('Failed to detect language', result);
      }

      final detectionResult = resultPtr.ref;
      final languageBytes = detectionResult.language;
      // 将 Array<Char> 转换为字符串
      final languageList = <int>[];
      for (int i = 0; i < 8; i++) {
        final char = languageBytes[i];
        if (char == 0) break;
        languageList.add(char);
      }
      final language = String.fromCharCodes(languageList);

      return DetectionResult(
        language: language,
        isReliable: detectionResult.is_reliable != 0,
        confidence: detectionResult.confidence,
      );
    } finally {
      malloc.free(textPtr);
      if (hintPtr != null) {
        malloc.free(hintPtr);
      }
      malloc.free(resultPtr);
    }
  }

  /// 检测语言（后台 Isolate 版本）
  ///
  /// 推荐在 Flutter 场景使用：避免同步 FFI 阻塞 UI isolate。
  static Future<DetectionResult> detectLanguageAsync(String text,
      [String? hint]) async {
    final map = await _BergamotBackground.instance.detectLanguage(text, hint);
    return DetectionResult.fromJson(map);
  }

  /// 清理资源（释放所有模型和服务）
  ///
  /// 在应用程序退出前调用此方法以释放所有资源。
  static void cleanup(bool resetService) {
    if (_bindings != null) {
      _bindings!.bergamot_cleanup(resetService);
    }
  }

  /// 清理资源（后台 Isolate 版本）
  ///
  /// 清理 C++ 端资源并关闭后台 Isolate。
  static Future<void> cleanupAsync(bool resetService) async {
    await _BergamotBackground.instance.cleanup(resetService);
    _BergamotBackground.instance.shutdown();
  }

  /// 关闭后台 Isolate
  ///
  /// 仅关闭 Isolate，不清理 C++ 端资源。
  /// 通常不需要单独调用，[cleanupAsync] 会自动调用此方法。
  static void shutdownAsync() {
    _BergamotBackground.instance.shutdown();
  }
}
