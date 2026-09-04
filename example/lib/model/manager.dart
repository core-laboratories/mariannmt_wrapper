import 'dart:io';
import 'package:path/path.dart' as path;

import 'constant.dart';
import 'language.dart';
import '../utils/logger.dart';
import '../utils/utils.dart' as utils;

/// 模型管理器
class ModelManager {
  /// 检查语言对是否已安装
  static Future<bool> isLanguagePairInstalled(
    Language from,
    Language to,
  ) async {
    debug(
      'Checking if language pair is installed: ${from.displayName} -> ${to.displayName}',
    );
    if (from == to) {
      debug('Same language, no translation needed');
      return true;
    }

    if (from == Language.english || to == Language.english) {
      LanguageFiles? files;
      Language targetLanguage; // 确定目标语言（非英语的语言）
      if (from == Language.english) {
        files = fromEnglishFiles[to];
        targetLanguage = to;
      } else {
        files = toEnglishFiles[from];
        targetLanguage = from;
      }

      if (files == null) {
        warning(
          'No model files defined for ${from.displayName} -> ${to.displayName}',
        );
        return false;
      }
      debug(
        'Checking ${files.allFiles.length} files for ${from.displayName} -> ${to.displayName}',
      );
      for (final fileName in files.allFiles) {
        final exists = await utils.modelFileExists(fileName, targetLanguage);
        if (!exists) {
          return false;
        }
      }
      info(
        'Language pair ${from.displayName} -> ${to.displayName} is installed',
      );
      return true;
    }

    // 需要枢轴翻译：from -> en -> to
    debug(
      'Pivot translation required: ${from.displayName} -> English -> ${to.displayName}',
    );
    final firstPair = await isLanguagePairInstalled(from, Language.english);
    final secondPair = await isLanguagePairInstalled(Language.english, to);
    if (!firstPair) {
      warning(
        'First pivot pair ${from.displayName} -> English is not installed',
      );
    }
    if (!secondPair) {
      warning(
        'Second pivot pair English -> ${to.displayName} is not installed',
      );
    }
    return firstPair && secondPair;
  }

  /// 获取缺失的文件列表
  static Future<List<String>> getMissingFiles(
    Language from,
    Language to,
  ) async {
    debug('Getting missing files for ${from.displayName} -> ${to.displayName}');
    if (from == to) return [];
    final missing = <String>[];

    if (from == Language.english) {
      final files = fromEnglishFiles[to];
      if (files != null) {
        for (final fileName in files.allFiles) {
          if (!await utils.modelFileExists(fileName, to)) {
            missing.add(fileName);
            debug('Missing file: $fileName');
          }
        }
      }
    } else if (to == Language.english) {
      final files = toEnglishFiles[from];
      if (files != null) {
        for (final fileName in files.allFiles) {
          if (!await utils.modelFileExists(fileName, from)) {
            missing.add(fileName);
            debug('Missing file: $fileName');
          }
        }
      }
    } else {
      // 枢轴翻译需要两个语言对
      debug('Getting missing files for pivot translation');
      missing.addAll(await getMissingFiles(from, Language.english));
      missing.addAll(await getMissingFiles(Language.english, to));
    }

    if (missing.isNotEmpty) {
      info(
        'Found ${missing.length} missing files for ${from.displayName} -> ${to.displayName}',
      );
    } else {
      debug(
        'All required files are present for ${from.displayName} -> ${to.displayName}',
      );
    }
    return missing;
  }

  /// 生成模型配置YAML
  static Future<String> generateConfig(Language from, Language to) async {
    debug('Generating config for ${from.displayName} -> ${to.displayName}');
    // 使用新结构：models/{language_code}/
    Language targetLanguage;
    if (from == Language.english) {
      targetLanguage = to;
    } else {
      targetLanguage = from;
    }
    final langDir = await utils.getLanguageModelDirectory(targetLanguage);
    final modelsPath = langDir.path;
    debug('Models directory path: $modelsPath');

    LanguageFiles? languageFiles;
    if (from == Language.english) {
      languageFiles = fromEnglishFiles[to];
    } else if (to == Language.english) {
      languageFiles = toEnglishFiles[from];
    }

    if (languageFiles == null) {
      error(
        'Language pair ${from.displayName} -> ${to.displayName} not supported',
      );
      throw Exception('Language pair $from -> $to not supported');
    }

    debug(
      'Using model files: model=${languageFiles.model}, srcVocab=${languageFiles.srcVocab}, tgtVocab=${languageFiles.tgtVocab}, lex=${languageFiles.lex}',
    );

    // 验证文件是否存在
    final modelFile = File(path.join(modelsPath, languageFiles.model));
    var srcVocabFile = File(path.join(modelsPath, languageFiles.srcVocab));
    final tgtVocabFile = File(path.join(modelsPath, languageFiles.tgtVocab));
    final lexFile = File(path.join(modelsPath, languageFiles.lex));

    // 对于中文，如果 srcvocab.enzh.spm 不存在，尝试使用 vocab.zhen.spm（反向模型的词汇文件）
    if (!await srcVocabFile.exists() &&
        from == Language.english &&
        to == Language.chinese) {
      final alternativeVocab = File(path.join(modelsPath, 'vocab.zhen.spm'));
      if (await alternativeVocab.exists()) {
        debug(
            'Using alternative vocab file: vocab.zhen.spm instead of ${languageFiles.srcVocab}');
        srcVocabFile = alternativeVocab;
      }
    }

    if (!await modelFile.exists()) {
      error('Model file not found: ${modelFile.path}');
      throw Exception('Model file not found: ${modelFile.path}');
    }
    if (!await srcVocabFile.exists()) {
      error('Source vocab file not found: ${srcVocabFile.path}');
      throw Exception('Source vocab file not found: ${srcVocabFile.path}');
    }
    if (!await tgtVocabFile.exists()) {
      error('Target vocab file not found: ${tgtVocabFile.path}');
      throw Exception('Target vocab file not found: ${tgtVocabFile.path}');
    }
    if (!await lexFile.exists()) {
      error('Lexical file not found: ${lexFile.path}');
      throw Exception('Lexical file not found: ${lexFile.path}');
    }

    debug(
      'All model files verified: model=${modelFile.path}, srcVocab=${srcVocabFile.path}, tgtVocab=${tgtVocabFile.path}, lex=${lexFile.path}',
    );

    final config = '''
models:
  - $modelsPath/${languageFiles.model}
vocabs:
  - $modelsPath/${languageFiles.srcVocab}
  - $modelsPath/${languageFiles.tgtVocab}
beam-size: 1
normalize: 1.0
word-penalty: 0
max-length-break: 128
mini-batch-words: 1024
max-length-factor: 2.0
skip-cost: true
cpu-threads: 1
quiet: true
quiet-translation: true
gemm-precision: int8shiftAlphaAll
alignment: soft
''';
    // info('config: \n $config');
    debug('Generated config for ${from.displayName} -> ${to.displayName}');
    return config;
  }

  /// 获取翻译对列表（用于枢轴翻译）
  static List<(Language, Language)> getTranslationPairs(
    Language from,
    Language to,
  ) {
    if (from == to) {
      debug('Same language, no translation pairs needed');
      return [];
    }
    if (from == Language.english) {
      debug('Direct translation: ${from.displayName} -> ${to.displayName}');
      return [(from, to)];
    } else if (to == Language.english) {
      debug('Direct translation: ${from.displayName} -> ${to.displayName}');
      return [(from, to)];
    } else {
      // 枢轴翻译：from -> en -> to
      debug(
        'Pivot translation: ${from.displayName} -> English -> ${to.displayName}',
      );
      return [(from, Language.english), (Language.english, to)];
    }
  }
}
