import 'package:flutter/material.dart';
import 'dart:async';
import '../model/language.dart';
import '../model/manager.dart';
import '../services/download_service.dart';
import '../dictionary/dictionary.dart';
import '../utils/utils.dart' as utils;

/// 词典管理/下载界面
class DictionaryManagerScreen extends StatefulWidget {
  const DictionaryManagerScreen({super.key});

  @override
  State<DictionaryManagerScreen> createState() =>
      _DictionaryManagerScreenState();
}

class _DictionaryManagerScreenState extends State<DictionaryManagerScreen> {
  final DownloadService _downloadService = DownloadService();
  StreamSubscription<Map<Language, DownloadState>>? _downloadStatesSubscription;
  Map<Language, DownloadState> _dictionaryDownloadStates = {};
  Map<Language, bool> _installedDictionaries = {};
  Map<Language, bool> _installedModels = {}; // 跟踪已安装的模型
  DictionaryIndex? _dictionaryIndex;
  bool _isLoading = true;
  bool _isLoadingIndex = false;

  @override
  void initState() {
    super.initState();
    _loadInstalledDictionaries();
    _loadInstalledModels();
    _loadDictionaryIndex();
    _downloadStatesSubscription =
        _downloadService.dictionaryDownloadStates.listen((states) {
      final previousStates =
          Map<Language, DownloadState>.from(_dictionaryDownloadStates);
      setState(() {
        _dictionaryDownloadStates = states;
      });
      // 检查是否有下载完成，如果有则重新加载
      bool shouldReload = false;
      for (final entry in states.entries) {
        final previousState = previousStates[entry.key];
        if (previousState?.isDownloading == true &&
            entry.value.isCompleted == true &&
            entry.value.isDownloading == false) {
          shouldReload = true;
          break;
        }
      }
      if (shouldReload) {
        // 延迟一下，确保文件系统操作完成
        Future.delayed(const Duration(milliseconds: 500), () {
          _loadInstalledDictionaries();
          _loadInstalledModels();
        });
      }
    });
  }

  Future<void> _loadInstalledModels() async {
    // 通过扫描models目录下的文件夹来检测已安装的语言
    final installedLanguagesList = await utils.getInstalledLanguages();
    final installed = <Language, bool>{};

    // 英语作为内置语言，总是被视为已安装
    installed[Language.english] = true;

    // 标记已安装的语言
    for (final language in installedLanguagesList) {
      installed[language] = true;
    }

    // 对于其他语言，检查是否已安装
    for (final language in Language.values) {
      if (!installed.containsKey(language)) {
        // 检查双向翻译是否都安装
        final fromInstalled = await ModelManager.isLanguagePairInstalled(
          Language.english,
          language,
        );
        final toInstalled = await ModelManager.isLanguagePairInstalled(
          language,
          Language.english,
        );
        installed[language] = fromInstalled && toInstalled;
      }
    }

    setState(() {
      _installedModels = installed;
    });
  }

  @override
  void dispose() {
    _downloadStatesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadInstalledDictionaries() async {
    setState(() {
      _isLoading = true;
    });

    final installed = <Language, bool>{};

    for (final language in Language.values) {
      // 英语字典不是内置的，需要实际检查文件是否存在
      // 检查字典文件是否存在（新结构：models/{language_code}/dictionary.dict）
      final exists = await utils.dictionaryFileExists(language);
      installed[language] = exists;
    }

    setState(() {
      _installedDictionaries = installed;
      _isLoading = false;
    });
  }

  Future<void> _loadDictionaryIndex() async {
    setState(() {
      _isLoadingIndex = true;
    });

    final index = await _downloadService.fetchDictionaryIndex();
    setState(() {
      _dictionaryIndex = index;
      _isLoadingIndex = false;
    });
  }

  List<Language> get _installedDictionaryList {
    return _installedDictionaries.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  List<Language> get _availableDictionaryList {
    if (_dictionaryIndex == null) {
      return [];
    }

    // 获取所有支持的语言（已安装模型的语言 + 字典索引中的语言）
    final availableLanguages = <Language>{};

    // 添加已安装模型的语言（排除英语，因为英语模型是内置的，但字典不是）
    for (final entry in _installedModels.entries) {
      if (entry.key != Language.english) {
        availableLanguages.add(entry.key);
      }
    }

    // 添加字典索引中的所有语言（包括英语，因为英语字典不是内置的，可以下载）
    for (final langCode in _dictionaryIndex!.dictionaries.keys) {
      try {
        final language = Language.values.firstWhere(
          (lang) => lang.code == langCode,
        );
        availableLanguages.add(language);
      } catch (e) {
        // 忽略无效的语言代码
      }
    }

    // 返回未安装字典的语言（英语字典如果未安装也会显示在可用列表中）
    return availableLanguages
        .where((lang) => !(_installedDictionaries[lang] ?? false))
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  String _getDictionarySize(Language language) {
    if (_dictionaryIndex == null) {
      return '未知';
    }
    final info = _dictionaryIndex!.dictionaries[language.code];
    if (info == null) {
      return '未知';
    }
    final sizeMB = info.size / (1024.0 * 1024.0);
    if (sizeMB > 10) {
      return '${sizeMB.toInt()} MB';
    } else {
      return '${sizeMB.toStringAsFixed(2)} MB';
    }
  }

  String _getDictionaryDescription(Language language) {
    if (_dictionaryIndex == null) {
      return '';
    }
    final info = _dictionaryIndex!.dictionaries[language.code];
    if (info == null) {
      return '';
    }
    final sizeMB = info.size / (1024.0 * 1024.0);
    final entries = info.wordCount;
    final type = info.type;
    final entriesStr =
        entries > 0 ? ' - ${_humanCount(entries)} 词条 - $type' : '';
    if (sizeMB > 10) {
      return '${sizeMB.toInt()} MB$entriesStr';
    } else {
      return '${sizeMB.toStringAsFixed(2)} MB$entriesStr';
    }
  }

  String _humanCount(int v) {
    if (v < 1000) {
      return v.toString();
    } else if (v < 1000000) {
      return '${(v / 1000).round()}k';
    } else {
      final millions = v / 1000000.0;
      if (millions >= 10) {
        return '${millions.round()}m';
      } else {
        return '${millions.toStringAsFixed(2)}m';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('字典管理'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _dictionaryIndex == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          '下载字典索引（约5KB）以浏览可用字典',
                          style: TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _isLoadingIndex
                          ? const CircularProgressIndicator()
                          : ElevatedButton(
                              onPressed: _loadDictionaryIndex,
                              child: const Text('获取字典索引'),
                            ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    await _loadInstalledDictionaries();
                    await _loadInstalledModels();
                    await _loadDictionaryIndex();
                  },
                  child: ListView(
                    children: [
                      if (_installedDictionaryList.isNotEmpty) ...[
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
                        ..._installedDictionaryList
                            .map((lang) => _buildDictionaryItem(lang, true)),
                      ],
                      if (_availableDictionaryList.isNotEmpty) ...[
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
                        ..._availableDictionaryList
                            .map((lang) => _buildDictionaryItem(lang, false)),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildDictionaryItem(Language language, bool isInstalled) {
    final downloadState = _dictionaryDownloadStates[language];
    final isDownloading = downloadState?.isDownloading ?? false;
    final hasError = downloadState?.error != null;
    final isCancelled = downloadState?.isCancelled ?? false;

    return ListTile(
      title: Text(language.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('代码: ${language.code}'),
          if (isInstalled)
            Text('大小: ${_getDictionarySize(language)}')
          else
            Text(_getDictionaryDescription(language)),
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
          _downloadService.cancelDictionaryDownload(language);
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
              content: Text('确定要删除 ${language.displayName} 的字典文件吗？'),
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
            // 删除字典文件（新结构：models/{language_code}/dictionary.dict）
            await utils.deleteDictionaryFile(language);
            _loadInstalledDictionaries();
          }
        },
        tooltip: '删除',
      );
    } else {
      final info = _dictionaryIndex?.dictionaries[language.code];
      return IconButton(
        icon: Icon(hasError || isCancelled ? Icons.refresh : Icons.download),
        onPressed: () {
          _downloadService.startDictionaryDownload(
            language,
            dictionarySize: info?.size,
          );
        },
        tooltip: hasError || isCancelled ? '重试下载' : '下载',
      );
    }
  }
}
