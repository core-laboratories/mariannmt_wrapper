import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../model/language.dart';
import 'logger.dart';

/// 下载进度回调
/// @param downloaded 已下载的字节数
/// @param total 总字节数
typedef DownloadProgressCallback = void Function(int downloaded, int total);

/// 下载文件（支持GZ解压）
Future<bool> downloadAndDecompress(
  String url,
  File outputFile, {
  bool decompress = false,
  DownloadProgressCallback? onProgress,
}) async {
  try {
    // 确保父目录存在
    await outputFile.parent.create(recursive: true);

    // 创建临时文件
    final tempFile = File('${outputFile.path}.tmp');

    // 使用流式下载以支持进度跟踪
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        error('Download failed with status code: ${response.statusCode}');
        return false;
      }

      final totalBytes = response.contentLength ?? 0;
      int downloadedBytes = 0;
      final sink = tempFile.openWrite();

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          if (onProgress != null && totalBytes > 0) {
            onProgress(downloadedBytes, totalBytes);
          }
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }

    // 如果需要解压
    if (decompress) {
      debug('Decompressing file: ${tempFile.path}');
      final gzBytes = await tempFile.readAsBytes();
      final archive = GZipDecoder().decodeBytes(gzBytes);
      await outputFile.writeAsBytes(archive);
      await tempFile.delete();
      info('Decompression completed: ${outputFile.path}');
    } else {
      // 重命名为最终文件
      await tempFile.rename(outputFile.path);
    }

    info('Download completed: ${outputFile.path}');
    return true;
  } catch (e) {
    error('Download error: $e');
    // 清理临时文件
    final tempFile = File('${outputFile.path}.tmp');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    if (await outputFile.exists()) {
      await outputFile.delete();
    }
    return false;
  }
}

/// 获取模型根目录
Future<Directory> getModelsDirectory() async {
  final appDir = await getApplicationDocumentsDirectory();
  final modelsDir = Directory(path.join(appDir.path, 'bergamot', 'models'));
  if (!await modelsDir.exists()) {
    debug('Creating models directory: ${modelsDir.path}');
    await modelsDir.create(recursive: true);
    info('Models directory created: ${modelsDir.path}');
  }
  return modelsDir;
}

/// 获取指定语言的模型目录
/// 新结构：models/{language_code}/
Future<Directory> getLanguageModelDirectory(Language language) async {
  final modelsDir = await getModelsDirectory();
  final langDir = Directory(path.join(modelsDir.path, language.code));
  if (!await langDir.exists()) {
    debug('Creating language model directory: ${langDir.path}');
    await langDir.create(recursive: true);
  }
  return langDir;
}

/// 获取字典目录（兼容旧结构，用于字典索引）
Future<Directory> getDictionaryDirectory() async {
  final appDir = await getApplicationDocumentsDirectory();
  final dictionaryDir =
      Directory(path.join(appDir.path, 'bergamot', 'dictionary'));
  if (!await dictionaryDir.exists()) {
    debug('Creating dictionary directory: ${dictionaryDir.path}');
    await dictionaryDir.create(recursive: true);
    info('Dictionary directory created: ${dictionaryDir.path}');
  }
  return dictionaryDir;
}

/// 获取指定语言的字典文件路径
/// 新结构：models/{language_code}/dictionary.dict
Future<File> getLanguageDictionaryFile(Language language) async {
  final langDir = await getLanguageModelDirectory(language);
  return File(path.join(langDir.path, 'dictionary.dict'));
}

/// 检查模型文件是否存在（新结构：按语言分文件夹）
Future<bool> modelFileExists(String fileName, Language language) async {
  final langDir = await getLanguageModelDirectory(language);
  final file = File(path.join(langDir.path, fileName));
  return await file.exists();
}

/// 检查字典文件是否存在（新结构：按语言分文件夹）
Future<bool> dictionaryFileExists(Language language) async {
  final dictFile = await getLanguageDictionaryFile(language);
  return await dictFile.exists();
}

/// 删除模型文件（新结构：按语言分文件夹）
Future<void> deleteModelFile(String fileName, Language language) async {
  final langDir = await getLanguageModelDirectory(language);
  final file = File(path.join(langDir.path, fileName));
  if (await file.exists()) {
    await file.delete();
  }
}

/// 删除字典文件（新结构：按语言分文件夹）
Future<void> deleteDictionaryFile(Language language) async {
  final dictFile = await getLanguageDictionaryFile(language);
  if (await dictFile.exists()) {
    await dictFile.delete();
  }
}

/// 删除整个语言文件夹（删除该语言的所有模型和字典）
Future<void> deleteLanguageDirectory(Language language) async {
  final modelsDir = await getModelsDirectory();
  final langDir = Directory(path.join(modelsDir.path, language.code));
  if (await langDir.exists()) {
    await langDir.delete(recursive: true);
    info('Deleted language directory: ${langDir.path}');
  }
}

/// 获取所有已安装的语言（通过扫描models目录下的文件夹）
Future<List<Language>> getInstalledLanguages() async {
  final modelsDir = await getModelsDirectory();
  final installed = <Language>[];

  if (!await modelsDir.exists()) {
    return installed;
  }

  await for (final entity in modelsDir.list()) {
    if (entity is Directory) {
      final langCode = path.basename(entity.path);
      // 查找对应的语言
      try {
        final language = Language.values.firstWhere(
          (lang) => lang.code == langCode,
        );
        // 检查该语言目录下是否有模型文件
        final hasFiles = await _hasModelFiles(entity);
        if (hasFiles) {
          installed.add(language);
          debug(
              'Found installed language: ${language.displayName} (${language.code})');
        } else {
          debug(
              'Language directory exists but no model files found: ${language.displayName} (${language.code})');
        }
      } catch (e) {
        // 忽略无效的语言代码（firstWhere 找不到匹配项时会抛出异常）
        debug('Invalid language code: $langCode');
      }
    }
  }

  return installed;
}

/// 检查目录下是否有模型文件
Future<bool> _hasModelFiles(Directory dir) async {
  bool hasFiles = false;
  await for (final entity in dir.list()) {
    if (entity is File) {
      final fileName = path.basename(entity.path);
      // 检查是否是模型文件（.bin, .spm等）
      if (fileName.endsWith('.bin') ||
          fileName.endsWith('.spm') ||
          (fileName.endsWith('.dict') && fileName != 'dictionary.dict')) {
        hasFiles = true;
        break;
      }
    }
  }
  return hasFiles;
}
