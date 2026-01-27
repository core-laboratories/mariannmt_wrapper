import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as path;

import '../dictionary/dictionary.dart';
import '../model/language.dart';
import '../model/constant.dart';
import '../utils/logger.dart';
import '../utils/utils.dart' as utils;

/// 下载状态
class DownloadState {
  final bool isDownloading;
  final bool isCompleted;
  final bool isCancelled;
  final int downloaded;
  final int totalSize;
  final String? error;

  const DownloadState({
    this.isDownloading = false,
    this.isCompleted = false,
    this.isCancelled = false,
    this.downloaded = 0,
    this.totalSize = 1,
    this.error,
  });

  DownloadState copyWith({
    bool? isDownloading,
    bool? isCompleted,
    bool? isCancelled,
    int? downloaded,
    int? totalSize,
    String? error,
  }) {
    return DownloadState(
      isDownloading: isDownloading ?? this.isDownloading,
      isCompleted: isCompleted ?? this.isCompleted,
      isCancelled: isCancelled ?? this.isCancelled,
      downloaded: downloaded ?? this.downloaded,
      totalSize: totalSize ?? this.totalSize,
      error: error ?? this.error,
    );
  }
}

/// 下载服务
class DownloadService {
  // 基础URL配置
  static const String _defaultTranslationModelsBaseUrl =
      'https://media.githubusercontent.com/media/mozilla/firefox-translations-models/ce0a251b3cb4e8af97986fc557b99976369cf9ca/models';
  static const String _defaultDictionaryBaseUrl =
      'https://translator.davidv.dev/dictionaries';
  static const int _dictVersion = 1;

  static final DownloadService _instance = DownloadService._();
  DownloadService._();
  factory DownloadService() {
    return _instance;
  }

  // 下载状态跟踪
  final Map<Language, DownloadState> _modelDownloadStates = {};
  final Map<Language, DownloadState> _dictionaryDownloadStates = {};

  // 下载任务跟踪（用于取消）
  final Map<Language, Future<void>> _modelDownloadTasks = {};
  final Map<Language, Future<void>> _dictionaryDownloadTasks = {};

  // 下载状态流
  final StreamController<Map<Language, DownloadState>>
      _modelDownloadStatesController =
      StreamController<Map<Language, DownloadState>>.broadcast();
  final StreamController<Map<Language, DownloadState>>
      _dictionaryDownloadStatesController =
      StreamController<Map<Language, DownloadState>>.broadcast();

  Stream<Map<Language, DownloadState>> get modelDownloadStates =>
      _modelDownloadStatesController.stream;
  Stream<Map<Language, DownloadState>> get dictionaryDownloadStates =>
      _dictionaryDownloadStatesController.stream;

  /// 更新模型下载状态
  void _updateModelDownloadState(
    Language language,
    DownloadState Function(DownloadState) update,
  ) {
    final currentState =
        _modelDownloadStates[language] ?? const DownloadState();
    _modelDownloadStates[language] = update(currentState);
    _modelDownloadStatesController.add(Map.from(_modelDownloadStates));
  }

  /// 更新字典下载状态
  void _updateDictionaryDownloadState(
    Language language,
    DownloadState Function(DownloadState) update,
  ) {
    final currentState =
        _dictionaryDownloadStates[language] ?? const DownloadState();
    _dictionaryDownloadStates[language] = update(currentState);
    _dictionaryDownloadStatesController.add(
      Map.from(_dictionaryDownloadStates),
    );
  }

  /// 开始下载语言模型
  Future<void> startModelDownload(Language language) async {
    // 如果已经在下载，不重复开始
    if (_modelDownloadStates[language]?.isDownloading == true) {
      debug('Model download already in progress for ${language.displayName}');
      return;
    }

    _updateModelDownloadState(
      language,
      (state) => state.copyWith(
        isDownloading: true,
        isCompleted: false,
        downloaded: 0,
      ),
    );

    final task = _downloadModelFiles(language);
    _modelDownloadTasks[language] = task;

    try {
      await task;
    } finally {
      _modelDownloadTasks.remove(language);
    }
  }

  /// 下载模型文件
  Future<void> _downloadModelFiles(Language language) async {
    try {
      // 使用新结构：models/{language_code}/
      final langDir = await utils.getLanguageModelDirectory(language);

      // 检查已存在的文件
      final existingFiles = <String>{};
      if (await langDir.exists()) {
        await for (final entity in langDir.list()) {
          if (entity is File) {
            final fileName = path.basename(entity.path);
            // 跳过字典文件
            if (fileName != 'dictionary.dict') {
              existingFiles.add(fileName);
            }
          }
        }
      }

      // 获取需要下载的文件
      final (fromSize, missingFrom) = _getMissingFilesFrom(
        existingFiles,
        language,
      );
      final (toSize, missingTo) = _getMissingFilesTo(existingFiles, language);

      var totalSize = fromSize + toSize;
      final downloadTasks = <Future<bool>>[];

      // 跟踪每个文件的下载进度
      final fileProgressMap = <String, int>{};
      int getTotalDownloaded() {
        return fileProgressMap.values.fold(0, (sum, value) => sum + value);
      }

      // 下载 to -> en 的文件
      if (missingTo.isNotEmpty) {
        final files = toEnglishFiles[language];
        if (files != null) {
          for (final fileName in missingTo) {
            final file = File(path.join(langDir.path, fileName));
            final url =
                '$_defaultTranslationModelsBaseUrl/${files.modelType.value}/${language.code}en/$fileName.gz';
            fileProgressMap[fileName] = 0;
            downloadTasks.add(
              utils.downloadAndDecompress(
                url,
                file,
                decompress: true,
                onProgress: (downloaded, total) {
                  fileProgressMap[fileName] = downloaded;
                  _updateModelDownloadState(
                    language,
                    (state) => state.copyWith(downloaded: getTotalDownloaded()),
                  );
                },
              ),
            );
          }
        }
      }

      // 下载 en -> to 的文件
      if (missingFrom.isNotEmpty) {
        final files = fromEnglishFiles[language];
        if (files != null) {
          for (final fileName in missingFrom) {
            final file = File(path.join(langDir.path, fileName));
            final url =
                '$_defaultTranslationModelsBaseUrl/${files.modelType.value}/en${language.code}/$fileName.gz';
            fileProgressMap[fileName] = 0;
            downloadTasks.add(
              utils.downloadAndDecompress(
                url,
                file,
                decompress: true,
                onProgress: (downloaded, total) {
                  fileProgressMap[fileName] = downloaded;
                  _updateModelDownloadState(
                    language,
                    (state) => state.copyWith(downloaded: getTotalDownloaded()),
                  );
                },
              ),
            );
          }
        }
      }

      // 更新总大小
      _updateModelDownloadState(
        language,
        (state) => state.copyWith(totalSize: totalSize),
      );

      // 并行执行所有下载
      if (downloadTasks.isNotEmpty) {
        info(
          'Starting ${downloadTasks.length} download jobs for ${language.displayName}',
        );
        final results = await Future.wait(downloadTasks);
        final success = results.every((result) => result);

        // 确保所有文件都已写入磁盘
        if (success) {
          // 强制同步文件系统 - 列出目录内容以确保文件系统更新
          try {
            await langDir.list().toList();
            // 额外等待一小段时间确保文件系统完全同步
            await Future.delayed(const Duration(milliseconds: 300));
          } catch (e) {
            warning('Failed to sync file system: $e');
          }
        }

        // 更新状态，触发UI刷新
        _updateModelDownloadState(
          language,
          (state) => state.copyWith(isDownloading: false, isCompleted: success),
        );

        if (success) {
          info('Model download complete: ${language.displayName}');
        } else {
          error('Model download failed: ${language.displayName}');
        }
      } else {
        _updateModelDownloadState(
          language,
          (state) => state.copyWith(isDownloading: false, isCompleted: true),
        );
      }
    } catch (e) {
      error('Model download failed for ${language.displayName}: $e');
      _updateModelDownloadState(
        language,
        (state) => state.copyWith(isDownloading: false, error: e.toString()),
      );
    }
  }

  /// 获取缺失的 from 文件
  (int, List<String>) _getMissingFilesFrom(
    Set<String> existingFiles,
    Language language,
  ) {
    final files = fromEnglishFiles[language];
    if (files == null) {
      return (0, []);
    }

    final missing = <String>[];
    int totalSize = 0;

    for (final fileName in files.allFiles) {
      if (!existingFiles.contains(fileName)) {
        missing.add(fileName);
        // 这里可以根据实际文件大小计算，暂时使用估算值
        totalSize += 10000000; // 10MB 估算
      }
    }

    return (totalSize, missing);
  }

  /// 获取缺失的 to 文件
  (int, List<String>) _getMissingFilesTo(
    Set<String> existingFiles,
    Language language,
  ) {
    final files = toEnglishFiles[language];
    if (files == null) {
      return (0, []);
    }

    final missing = <String>[];
    int totalSize = 0;

    for (final fileName in files.allFiles) {
      if (!existingFiles.contains(fileName)) {
        missing.add(fileName);
        // 这里可以根据实际文件大小计算，暂时使用估算值
        totalSize += 10000000; // 10MB 估算
      }
    }

    return (totalSize, missing);
  }

  /// 取消模型下载
  void cancelModelDownload(Language language) {
    // 注意：Dart 的 Future 无法直接取消，这里只是更新状态
    _updateModelDownloadState(
      language,
      (state) =>
          state.copyWith(isDownloading: false, isCancelled: true, error: null),
    );
    _modelDownloadTasks.remove(language);
    info('Cancelled model download for ${language.displayName}');
  }

  /// 开始下载字典
  Future<void> startDictionaryDownload(
    Language language, {
    int? dictionarySize,
  }) async {
    // 如果已经在下载，不重复开始
    if (_dictionaryDownloadStates[language]?.isDownloading == true) {
      debug(
        'Dictionary download already in progress for ${language.displayName}',
      );
      return;
    }

    _updateDictionaryDownloadState(
      language,
      (state) => state.copyWith(
        isDownloading: true,
        isCompleted: false,
        downloaded: 0,
        totalSize: dictionarySize ?? 1000000,
      ),
    );

    final task = _downloadDictionaryFile(language);
    _dictionaryDownloadTasks[language] = task;

    try {
      await task;
    } finally {
      _dictionaryDownloadTasks.remove(language);
    }
  }

  /// 下载字典文件
  Future<void> _downloadDictionaryFile(Language language) async {
    try {
      // 使用新结构：models/{language_code}/dictionary.dict
      final dictionaryFile = await utils.getLanguageDictionaryFile(language);

      if (await dictionaryFile.exists()) {
        _updateDictionaryDownloadState(
          language,
          (state) => state.copyWith(isDownloading: false, isCompleted: true),
        );
        return;
      }

      final url =
          '$_defaultDictionaryBaseUrl/$_dictVersion/${language.code}.dict';
      final success = await utils.downloadAndDecompress(
        url,
        dictionaryFile,
        decompress: false,
        onProgress: (downloaded, total) {
          // 更新下载进度
          _updateDictionaryDownloadState(
            language,
            (state) => state.copyWith(
              downloaded: downloaded,
              totalSize: total > 0 ? total : state.totalSize,
            ),
          );
        },
      );

      _updateDictionaryDownloadState(
        language,
        (state) => state.copyWith(isDownloading: false, isCompleted: success),
      );

      if (success) {
        info('Dictionary download complete: ${language.displayName}');
      } else {
        error('Dictionary download failed: ${language.displayName}');
      }
    } catch (e) {
      error('Dictionary download failed for ${language.displayName}: $e');
      _updateDictionaryDownloadState(
        language,
        (state) => state.copyWith(isDownloading: false, error: e.toString()),
      );
    }
  }

  /// 取消字典下载
  void cancelDictionaryDownload(Language language) {
    _updateDictionaryDownloadState(
      language,
      (state) =>
          state.copyWith(isDownloading: false, isCancelled: true, error: null),
    );
    _dictionaryDownloadTasks.remove(language);
    info('Cancelled dictionary download for ${language.displayName}');
  }

  /// 获取字典索引
  Future<DictionaryIndex?> fetchDictionaryIndex() async {
    try {
      final dictionaryDir = await utils.getDictionaryDirectory();
      final indexFile = File(path.join(dictionaryDir.path, 'index.json'));
      final url = '$_defaultDictionaryBaseUrl/$_dictVersion/index.json';

      // 下载索引文件
      final success = await utils.downloadAndDecompress(
        url,
        indexFile,
        decompress: false,
      );
      if (!success) {
        error('Failed to download dictionary index');
        return null;
      }

      // 读取并解析索引
      final jsonString = await indexFile.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final index = DictionaryIndex.fromJson(json);

      info('Dictionary index downloaded and parsed');
      return index;
    } catch (e) {
      error('Failed to fetch dictionary index: $e');
      return null;
    }
  }

  /// 获取模型下载状态
  DownloadState? getModelDownloadState(Language language) {
    return _modelDownloadStates[language];
  }

  /// 获取字典下载状态
  DownloadState? getDictionaryDownloadState(Language language) {
    return _dictionaryDownloadStates[language];
  }

  /// 清理临时文件
  Future<void> cleanupTempFiles() async {
    final modelsDir = await utils.getModelsDirectory();

    if (await modelsDir.exists()) {
      await for (final entity in modelsDir.list()) {
        if (entity is Directory) {
          // 清理每个语言目录下的临时文件
          await for (final file in entity.list()) {
            if (file is File && file.path.endsWith('.tmp')) {
              try {
                await file.delete();
                debug('Cleaned up temp file: ${file.path}');
              } catch (e) {
                warning('Failed to delete temp file ${file.path}: $e');
              }
            }
          }
        } else if (entity is File && entity.path.endsWith('.tmp')) {
          try {
            await entity.delete();
            debug('Cleaned up temp file: ${entity.path}');
          } catch (e) {
            warning('Failed to delete temp file ${entity.path}: $e');
          }
        }
      }
    }
  }

  /// 释放资源
  void dispose() {
    _modelDownloadStatesController.close();
    _dictionaryDownloadStatesController.close();
  }
}
