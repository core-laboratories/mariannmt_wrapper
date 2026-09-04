import 'package:flutter/material.dart';
import 'dart:async';
import '../model/language.dart';
import '../model/constant.dart';
import '../model/manager.dart';
import '../services/download_service.dart';
import '../utils/utils.dart' as utils;
import '../utils/logger.dart';

/// 模型管理/下载界面
class ModelManagerScreen extends StatefulWidget {
  const ModelManagerScreen({super.key});

  @override
  State<ModelManagerScreen> createState() => _ModelManagerScreenState();
}

class _ModelManagerScreenState extends State<ModelManagerScreen> {
  final DownloadService _downloadService = DownloadService();
  StreamSubscription<Map<Language, DownloadState>>? _downloadStatesSubscription;
  Map<Language, DownloadState> _downloadStates = {};
  Map<Language, bool> _installedLanguages = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInstalledLanguages();
    _downloadStatesSubscription =
        _downloadService.modelDownloadStates.listen((states) {
      final previousStates = Map<Language, DownloadState>.from(_downloadStates);

      // 检查是否有下载完成，在更新状态之前
      bool shouldReload = false;
      Language? completedLanguage;
      for (final entry in states.entries) {
        final previousState = previousStates[entry.key];
        final currentState = entry.value;
        // 如果从下载中变为已完成，需要重新加载
        if (previousState?.isDownloading == true &&
            currentState.isCompleted == true &&
            currentState.isDownloading == false) {
          shouldReload = true;
          completedLanguage = entry.key;
          debug(
              'Download completed for ${entry.key.displayName}, will reload installed languages');
          break;
        }
      }

      setState(() {
        _downloadStates = states;
      });

      if (shouldReload && completedLanguage != null) {
        // 立即刷新一次，然后延迟再刷新一次确保文件系统同步完成
        debug(
            'Download completed for ${completedLanguage.displayName}, reloading installed languages');
        _loadInstalledLanguages();

        // 延迟再次刷新，确保所有文件都已写入磁盘
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            debug(
                'Second reload after download completion to ensure file system sync');
            _loadInstalledLanguages();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _downloadStatesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadInstalledLanguages() async {
    setState(() {
      _isLoading = true;
    });

    // 通过扫描models目录下的文件夹来检测已安装的语言
    final installedLanguagesList = await utils.getInstalledLanguages();
    final installed = <Language, bool>{};

    // 英语作为内置语言，总是被视为已安装
    installed[Language.english] = true;

    // 标记已安装的语言（从文件夹扫描结果）
    for (final language in installedLanguagesList) {
      installed[language] = true;
      debug(
          'Marked as installed from folder scan: ${language.displayName} (${language.code})');
    }

    // 对于其他语言，检查是否已安装（通过检查文件夹和文件）
    // 这样可以检测到部分安装的情况
    for (final language in Language.values) {
      if (language == Language.english) {
        continue;
      }
      if (!installed.containsKey(language) || installed[language] == false) {
        // 检查双向翻译是否都安装
        final fromInstalled = await ModelManager.isLanguagePairInstalled(
          Language.english,
          language,
        );
        final toInstalled = await ModelManager.isLanguagePairInstalled(
          language,
          Language.english,
        );
        final isFullyInstalled = fromInstalled && toInstalled;
        installed[language] = isFullyInstalled;
        if (isFullyInstalled && !installedLanguagesList.contains(language)) {
          debug(
              'Marked as installed from file check: ${language.displayName} (${language.code})');
        }
      }
    }

    setState(() {
      _installedLanguages = installed;
      _isLoading = false;
    });
  }

  List<Language> get _installedLanguageList {
    return _installedLanguages.entries
        .where((e) => e.value && e.key != Language.english)
        .map((e) => e.key)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  List<Language> get _notInstalledLanguageList {
    return _installedLanguages.entries
        .where((e) => !e.value && e.key != Language.english)
        .map((e) => e.key)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  String _getLanguageSize(Language language) {
    // 估算大小：每个模型约10MB
    int fileCount = 0;
    if (fromEnglishFiles.containsKey(language)) {
      fileCount += fromEnglishFiles[language]!.allFiles.length;
    }
    if (toEnglishFiles.containsKey(language)) {
      fileCount += toEnglishFiles[language]!.allFiles.length;
    }
    final sizeMB = (fileCount * 10).toDouble();
    if (sizeMB > 10) {
      return '${sizeMB.toInt()} MB';
    } else {
      return '${sizeMB.toStringAsFixed(2)} MB';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('语言模型管理'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadInstalledLanguages,
              child: ListView(
                children: [
                  if (_installedLanguageList.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        '已安装',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ..._installedLanguageList
                        .map((lang) => _buildLanguageItem(lang, true)),
                  ],
                  if (_notInstalledLanguageList.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        '可用',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ..._notInstalledLanguageList
                        .map((lang) => _buildLanguageItem(lang, false)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildLanguageItem(Language language, bool isInstalled) {
    final downloadState = _downloadStates[language];
    final isDownloading = downloadState?.isDownloading ?? false;
    final hasError = downloadState?.error != null;
    final isCancelled = downloadState?.isCancelled ?? false;

    return ListTile(
      title: Text(language.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('代码: ${language.code}'),
          Text('大小: ${_getLanguageSize(language)}'),
          if (isDownloading && downloadState != null)
            LinearProgressIndicator(
              value: downloadState.totalSize > 0
                  ? downloadState.downloaded / downloadState.totalSize
                  : null,
            ),
          if (isDownloading && downloadState != null)
            Text(
              '${(downloadState.downloaded / 1024 / 1024).toStringAsFixed(2)} MB / '
              '${(downloadState.totalSize / 1024 / 1024).toStringAsFixed(2)} MB',
              style: const TextStyle(fontSize: 12),
            ),
          if (hasError)
            Text(
              '错误: ${downloadState?.error}',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
        ],
      ),
      trailing: _buildActionButton(
          language, isInstalled, isDownloading, hasError, isCancelled),
    );
  }

  Widget _buildActionButton(
    Language language,
    bool isInstalled,
    bool isDownloading,
    bool hasError,
    bool isCancelled,
  ) {
    if (isDownloading) {
      return IconButton(
        icon: const Icon(Icons.cancel),
        onPressed: () {
          _downloadService.cancelModelDownload(language);
        },
        tooltip: '取消下载',
      );
    } else if (isInstalled) {
      return IconButton(
        icon: const Icon(Icons.delete),
        onPressed: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('确认删除'),
              content: Text('确定要删除 ${language.displayName} 的模型文件吗？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('删除'),
                ),
              ],
            ),
          );
          if (confirm == true) {
            // 删除整个语言文件夹（包括所有模型文件和字典文件）
            await utils.deleteLanguageDirectory(language);
            _loadInstalledLanguages();
          }
        },
        tooltip: '删除',
      );
    } else {
      return IconButton(
        icon: Icon(hasError || isCancelled ? Icons.refresh : Icons.download),
        onPressed: () {
          _downloadService.startModelDownload(language);
        },
        tooltip: hasError || isCancelled ? '重试下载' : '下载',
      );
    }
  }
}
