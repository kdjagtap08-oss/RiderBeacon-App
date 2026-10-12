import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kavach/ml_crash_classifier.dart';

void main() {
  group('MlCrashClassifier Unit & Latency Tests', () {
    late Map<String, List<List<double>>> fixtures;

    setUpAll(() async {
      final file = File('test/fixtures/ml_test_windows.json');
      final jsonString = await file.readAsString();
      final Map<String, dynamic> rawMap = jsonDecode(jsonString);

      fixtures = rawMap.map((key, value) {
        final list = (value as List)
            .map((sample) => (sample as List).map((numVal) => (numVal as num).toDouble()).toList())
            .toList();
        return MapEntry(key, list);
      });
    });

    test('Severe motorcycle crash produces high crash probability (>90%)', () {
      final crashWindow = fixtures['severe_crash']!;
      final probs = MlCrashClassifier.predictProbabilities(crashWindow);
      final topClass = MlCrashClassifier.predict(crashWindow);

      expect(topClass, equals(RideEventClass.severeCrash));
      expect(probs[RideEventClass.severeCrash]!, greaterThan(0.90));
    });

    test('Pothole vertical bump is classified as pothole and NOT severe crash', () {
      final potholeWindow = fixtures['pothole']!;
      final topClass = MlCrashClassifier.predict(potholeWindow);
      final probs = MlCrashClassifier.predictProbabilities(potholeWindow);

      expect(topClass, equals(RideEventClass.pothole));
      expect(probs[RideEventClass.severeCrash]!, lessThan(0.01));
    });

    test('Dropped phone is classified as droppedPhone and NOT severe crash', () {
      final dropWindow = fixtures['dropped_phone']!;
      final topClass = MlCrashClassifier.predict(dropWindow);
      final probs = MlCrashClassifier.predictProbabilities(dropWindow);

      expect(topClass, equals(RideEventClass.droppedPhone));
      expect(probs[RideEventClass.severeCrash]!, lessThan(0.01));
    });

    test('Normal riding is classified as normalRiding', () {
      final normalWindow = fixtures['normal']!;
      final topClass = MlCrashClassifier.predict(normalWindow);
      final probs = MlCrashClassifier.predictProbabilities(normalWindow);

      expect(topClass, equals(RideEventClass.normalRiding));
      expect(probs[RideEventClass.normalRiding]!, greaterThan(0.90));
    });

    test('Inference execution time is well under 1ms per window (<0.5ms)', () {
      final window = fixtures['normal']!;
      final stopwatch = Stopwatch()..start();
      const iterations = 500;
      for (int i = 0; i < iterations; i++) {
        MlCrashClassifier.predictProbabilities(window);
      }
      stopwatch.stop();

      final avgLatencyMs = stopwatch.elapsedMicroseconds / iterations / 1000.0;
      expect(avgLatencyMs, lessThan(0.5)); // Blazing fast sub-millisecond execution
    });
  });
}
