import 'dart:async';
import 'dart:ui';

import 'package:bergamot_translator/bergamot_translator.dart' as bergamot;
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'screens/translate.dart';
import 'screens/model_manager.dart';
import 'screens/dictionary_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name}: ${record.time}: ${record.message}');
  });

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _exitCleanupStarted = false;

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await bergamot.BergamotTranslator.cleanupAsync(true);
    return AppExitResponse.exit;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 桌面端关闭窗口时，通常会进入 detached（具体行为取决于 Flutter 版本/嵌入层）。
    if (state == AppLifecycleState.detached) {
      _cleanupOnExit();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _cleanupOnExit() {
    if (_exitCleanupStarted) return;
    _exitCleanupStarted = true;

    // best-effort: 不阻塞退出路径；同时确保 worker isolate 被关闭，避免进程无法退出。
    unawaited(() async {
      try {
        await bergamot.BergamotTranslator.cleanupAsync(true)
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        // ignore - best effort on exit
      } finally {
        bergamot.BergamotTranslator.shutdownAsync();
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bergamot Translator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TranslateScreen(),
      routes: {
        '/translate': (context) => const TranslateScreen(),
        '/models': (context) => const ModelManagerScreen(),
        '/dictionaries': (context) => const DictionaryManagerScreen(),
      },
    );
  }
}
