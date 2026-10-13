import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_kavach/accident_detector.dart';
import 'package:smart_kavach/gyro.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Accident & SOS System Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('smart_kavach/alarm'),
        (call) async => true,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/sensors/method'),
        (call) async => null,
      );
    });

    test('AccidentSettings defaults and police 100 configuration', () async {
      final settings = AccidentSettings();
      await settings.load();

      expect(settings.enabled, isTrue);
      expect(settings.policeNumber, equals('100'));
      expect(settings.callPoliceOnNoNetwork, isTrue);
      expect(settings.alwaysCallPoliceOnCrash, isFalse);
      expect(settings.countdownDuration, equals(15));
      expect(settings.sensitivity, equals(CrashSensitivity.normal));

      // Test updating settings
      await settings.update(
        newPoliceNumber: '112',
        newCountdownDuration: 20,
        newSensitivity: CrashSensitivity.high,
      );

      expect(settings.policeNumber, equals('112'));
      expect(settings.countdownDuration, equals(20));
      expect(settings.sensitivity, equals(CrashSensitivity.high));
    });

    test('GyroFeed calculates angular velocity magnitude accurately', () {
      final feed = GyroFeed();
      expect(feed.angularVelocity, equals(0.0));

      // 3D vector [100, 200, 200] -> sqrt(10000 + 40000 + 40000) = sqrt(90000) = 300
      feed.values = [100.0, 200.0, 200.0];
      expect(feed.angularVelocity, closeTo(300.0, 0.01));
    });

    test('AccidentDetector starts in idle state and triggers alarm', () {
      final settings = AccidentSettings();
      final gyro = GyroFeed();
      final detector = AccidentDetector(settings: settings, helmetGyro: gyro);

      expect(detector.state, equals(AccidentState.idle));
      expect(detector.countdownRemaining, equals(15));

      // Simulate crash trigger
      detector.triggerCrashAlarm(reason: 'Test impact & angle flip');
      expect(detector.state, equals(AccidentState.countdown));
      expect(detector.detectionReason, contains('Test impact & angle flip'));

      // Cancel alarm
      detector.cancelAlarm();
      expect(detector.state, equals(AccidentState.cancelled));

      detector.dispose();
    });

    test('AccidentDetector triggers alarm when gyro exceeds 240 deg/s threshold', () {
      final settings = AccidentSettings();
      settings.gyroThreshold = 240.0;
      final gyro = GyroFeed();
      final detector = AccidentDetector(settings: settings, helmetGyro: gyro);

      expect(detector.state, equals(AccidentState.idle));

      // Simulate MPU reading exceeding 240 deg/s
      gyro.values = [245.0, 10.0, 5.0];
      gyro.notifyListeners();

      expect(detector.state, equals(AccidentState.countdown));
      expect(detector.detectionReason, contains('exceeded limit'));

      detector.dispose();
    });
  });
}
