import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../model/language.dart';
import '../services/translation_service.dart';
import '../utils/utils.dart' as utils;
import '../utils/logger.dart';
import 'model_manager.dart';
import 'dictionary_manager.dart';

/// 翻译界面
class TranslateScreen extends StatefulWidget {
  const TranslateScreen({super.key});

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  final TextEditingController _inputController = TextEditingController();
  final TranslationService _translationService = TranslationService.instance;

  Language _fromLanguage = Language.english;
  Language _toLanguage = Language.chinese;
  String _output = '';
  bool _isTranslating = false;
  bool _isLoadingModel = false;
  bool _isModelReady = false;
  String? _error;
  Language? _detectedLanguage;
  Future<void>? _loadingModelFuture; // 防止重复加载

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChanged);
    _loadAvailableLanguages();
    _checkAndLoadModel();
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableLanguages() async {
    // 检查已安装的语言
    final installedLanguages = await utils.getInstalledLanguages();
    debug(
        'Installed languages: ${installedLanguages.map((l) => l.displayName).join(", ")}');

    // 如果目标语言未安装，尝试选择第一个已安装的语言
    if (!installedLanguages.contains(_toLanguage) &&
        installedLanguages.isNotEmpty) {
      setState(() {
        _toLanguage = installedLanguages.first;
      });
      // 语言变更后重新检查模型
      _checkAndLoadModel();
    }
  }

  /// 检查模型是否准备好，如果准备好则加载模型
  Future<void> _checkAndLoadModel() async {
    // 如果正在加载，等待当前加载完成
    if (_loadingModelFuture != null) {
      try {
        await _loadingModelFuture;
      } catch (e) {
        // 忽略错误，继续执行
      }
      return;
    }

    // 创建新的加载任务
    _loadingModelFuture = _doCheckAndLoadModel();
    try {
      await _loadingModelFuture;
    } finally {
      _loadingModelFuture = null;
    }
  }

  Future<void> _doCheckAndLoadModel() async {
    setState(() {
      _isLoadingModel = true;
      _isModelReady = false;
      _error = null;
    });

    try {
      // 检查模型是否已安装
      final isReady =
          await _translationService.isModelReady(_fromLanguage, _toLanguage);

      if (isReady) {
        // 模型已准备好，加载模型（preloadModel 内部会检查是否已加载）
        await _translationService.preloadModel(_fromLanguage, _toLanguage);
        setState(() {
          _isModelReady = true;
          _isLoadingModel = false;
        });
        debug(
            'Model loaded successfully for ${_fromLanguage.displayName} -> ${_toLanguage.displayName}');
      } else {
        // 模型未安装
        setState(() {
          _isModelReady = false;
          _isLoadingModel = false;
        });
        debug(
            'Model not ready for ${_fromLanguage.displayName} -> ${_toLanguage.displayName}');
      }
    } catch (e) {
      setState(() {
        _isModelReady = false;
        _isLoadingModel = false;
        _error = 'Failed to load model: $e';
      });
      error('Failed to check/load model: $e');
    }
  }

  void _onInputChanged() {
    final text = _inputController.text;
    if (text.isEmpty) {
      setState(() {
        _output = '';
        _error = null;
        _detectedLanguage = null;
      });
      return;
    }

    // 只有在模型准备好时才进行检测和翻译
    if (!_isModelReady || _isLoadingModel) {
      return;
    }

    // 自动检测语言
    _detectLanguage(text);

    // 自动翻译（延迟一下，避免频繁翻译）
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_inputController.text == text && text.isNotEmpty && _isModelReady) {
        _translate();
      }
    });
  }

  Future<void> _detectLanguage(String text) async {
    try {
      final detected =
          await _translationService.detectLanguage(text, _fromLanguage);
      if (detected != null && detected != _fromLanguage) {
        setState(() {
          _detectedLanguage = detected;
        });
      }
    } catch (e) {
      debug('Language detection failed: $e');
    }
  }

  Future<void> _translate() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _output = '';
        _error = null;
      });
      return;
    }

    if (_fromLanguage == _toLanguage) {
      setState(() {
        _output = text;
        _error = null;
      });
      return;
    }

    setState(() {
      _isTranslating = true;
      _error = null;
    });

    try {
      final result = await _translationService.translate(
        _fromLanguage,
        _toLanguage,
        text,
      );

      if (result.isSuccess) {
        setState(() {
          _output = result.translated;
          _error = null;
        });
      } else {
        setState(() {
          _error = result.error;
          _output = '';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Translation failed: $e';
        _output = '';
      });
    } finally {
      setState(() {
        _isTranslating = false;
      });
    }
  }

  void _swapLanguages() {
    setState(() {
      final temp = _fromLanguage;
      _fromLanguage = _toLanguage;
      _toLanguage = temp;
      // 交换输入和输出
      final tempText = _inputController.text;
      _inputController.text = _output;
      _output = tempText;
    });
    // 语言变更后重新加载模型
    _checkAndLoadModel();
    if (_isModelReady && _inputController.text.isNotEmpty) {
      _translate();
    }
  }

  void _clearInput() {
    _inputController.clear();
  }

  Future<void> _pasteFromClipboard() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboard?.text != null) {
      _inputController.text = clipboard!.text!;
    }
  }

  Future<void> _copyToClipboard() async {
    if (_output.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: _output));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('翻译'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_download),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ModelManagerScreen(),
                ),
              );
              // 从模型管理页面返回后，重新检查模型状态
              if (mounted) {
                _checkAndLoadModel();
              }
            },
            tooltip: '模型管理',
          ),
          IconButton(
            icon: const Icon(Icons.book),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DictionaryManagerScreen(),
                ),
              );
            },
            tooltip: '字典管理',
          ),
        ],
      ),
      body: Column(
        children: [
          // 语言选择行
          _buildLanguageSelectionRow(),

          // 输入区域
          Expanded(
            flex: 1,
            child: _buildInputArea(),
          ),

          // 分隔线
          const Divider(height: 1),

          // 输出区域
          Expanded(
            flex: 1,
            child: _buildOutputArea(),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSelectionRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 源语言选择
          Expanded(
            child: _buildLanguageDropdown(
              value: _fromLanguage,
              onChanged: (Language? newValue) {
                if (newValue != null) {
                  setState(() {
                    _fromLanguage = newValue;
                  });
                  // 语言变更后重新加载模型
                  _checkAndLoadModel();
                  if (_isModelReady && _inputController.text.isNotEmpty) {
                    _translate();
                  }
                }
              },
            ),
          ),

          // 交换按钮
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: _swapLanguages,
            tooltip: '交换语言',
          ),

          // 目标语言选择
          Expanded(
            child: _buildLanguageDropdown(
              value: _toLanguage,
              onChanged: (Language? newValue) {
                if (newValue != null) {
                  setState(() {
                    _toLanguage = newValue;
                  });
                  // 语言变更后重新加载模型
                  _checkAndLoadModel();
                  if (_isModelReady && _inputController.text.isNotEmpty) {
                    _translate();
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageDropdown({
    required Language value,
    required ValueChanged<Language?> onChanged,
  }) {
    return FutureBuilder<List<Language>>(
      future: _getAvailableLanguages(),
      builder: (context, snapshot) {
        final languages = snapshot.data ?? Language.values;
        // 确保列表中没有重复项（使用 Set 去重）
        final uniqueLanguages = languages.toSet().toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
        // 确保 value 在列表中，如果不在则使用 null（避免错误）
        final selectedValue = uniqueLanguages.contains(value) ? value : null;
        return DropdownButton<Language>(
          value: selectedValue,
          isExpanded: true,
          items: uniqueLanguages.map((lang) {
            return DropdownMenuItem<Language>(
              value: lang,
              child: Text(lang.displayName),
            );
          }).toList(),
          onChanged: onChanged,
        );
      },
    );
  }

  Future<List<Language>> _getAvailableLanguages() async {
    final installed = await utils.getInstalledLanguages();
    // 英语总是可用（内置）
    // 使用 Set 确保没有重复项
    final available = <Language>{Language.english};
    available.addAll(installed);
    // 转换为列表并去重（双重保险）
    final uniqueLanguages = available.toList();
    uniqueLanguages.sort((a, b) => a.displayName.compareTo(b.displayName));
    return uniqueLanguages;
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 模型加载状态提示
          if (_isLoadingModel)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '正在加载模型...',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            )
          else if (!_isModelReady)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, size: 16, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '模型未安装，请先下载模型',
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ModelManagerScreen(),
                        ),
                      );
                      // 从模型管理页面返回后，重新检查模型状态
                      if (mounted) {
                        _checkAndLoadModel();
                      }
                    },
                    child: const Text('下载', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),

          // 检测到的语言提示
          if (_detectedLanguage != null &&
              _detectedLanguage != _fromLanguage &&
              _isModelReady)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.language, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '检测到: ${_detectedLanguage!.displayName}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _fromLanguage = _detectedLanguage!;
                      });
                      _checkAndLoadModel();
                      if (_isModelReady) {
                        _translate();
                      }
                    },
                    child: const Text('使用', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),

          // 输入框
          Expanded(
            child: TextField(
              controller: _inputController,
              maxLines: null,
              expands: true,
              enabled: _isModelReady && !_isLoadingModel,
              decoration: InputDecoration(
                hintText: _isModelReady ? '输入要翻译的文本' : '请先下载并加载模型',
                border: InputBorder.none,
                suffixIcon: _inputController.text.isEmpty
                    ? IconButton(
                        icon: const Icon(Icons.paste),
                        onPressed: _isModelReady && !_isLoadingModel
                            ? _pasteFromClipboard
                            : null,
                        tooltip: '粘贴',
                      )
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _isModelReady && !_isLoadingModel
                            ? _clearInput
                            : null,
                        tooltip: '清除',
                      ),
              ),
              style: TextStyle(
                fontSize: 16,
                color: _isModelReady && !_isLoadingModel ? null : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 输出标题和操作按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '翻译结果',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              if (_output.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: _copyToClipboard,
                  tooltip: '复制',
                ),
            ],
          ),

          const SizedBox(height: 8),

          // 输出内容
          Expanded(
            child: _isTranslating
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.red, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : _output.isEmpty
                        ? const Center(
                            child: Text(
                              '翻译结果将显示在这里',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : SingleChildScrollView(
                            child: SelectableText(
                              _output,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
