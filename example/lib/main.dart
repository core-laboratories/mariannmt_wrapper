import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'services/translation_service.dart';
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
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await TranslationService.cleanup();
    return AppExitResponse.exit;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
