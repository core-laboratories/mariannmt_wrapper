import 'package:flutter_test/flutter_test.dart';
import 'package:mariannmt_wrapper/mariannmt_wrapper.dart';

void main() {
  test('detection result serializes without losing values', () {
    final result = DetectionResult(
      language: 'sk',
      isReliable: true,
      confidence: 98,
    );

    expect(DetectionResult.fromJson(result.toJson()).language, 'sk');
    expect(result.toJson(), <String, Object>{
      'language': 'sk',
      'isReliable': true,
      'confidence': 98,
    });
  });

  test('empty translation batches do not load the native library', () {
    expect(MarianTranslator.translateMultiple(<String>[], 'unused'), isEmpty);
    expect(
      MarianTranslator.pivotMultiple(<String>[], 'unused', 'unused'),
      isEmpty,
    );
  });

  test('exception includes an optional native error code', () {
    expect(
      MarianTranslationException('failed', 7).toString(),
      'MarianTranslationException: failed (code: 7)',
    );
  });
}
