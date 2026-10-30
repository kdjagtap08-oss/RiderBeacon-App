import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kavach/crash_detector.dart';

void main() {
  group('CrashDetector State Machine & Fusion Logic', () {
    late CrashDetector detector;

    setUp(() {
      detector = CrashDetector();
    });

    tearDown(() {
      detector.dispose();
    });

    test('Initial state should be idle with 1.0g baseline', () {
      expect(detector.state, CrashState.idle);
      expect(detector.lastAccelG, 1.0);
      expect(detector.lastGyroMag, 0.0);
      expect(detector.currentSpeedKmh, 0.0);
      expect(detector.isCoolingDown, false);
    });

    test('Normal riding telemetry remains in idle state', () {
      // Normal riding: 1.05g, 15 deg/s rotation, 55 km/h
      detector.feedGpsSpeed(55.0);
      detector.feedHelmetGyro(10.0, 5.0, 8.0); // ~14 deg/s
      detector.feedAccelerometer(0.5, 0.5, 9.8); // ~1.0g

      expect(detector.state, CrashState.idle);
      expect(detector.currentSpeedKmh, 55.0);
    });

    test('Pothole with high vertical acceleration but no gyro rotation stays idle', () {
      detector.feedGpsSpeed(50.0);
      detector.feedHelmetGyro(2.0, 1.0, 2.0); // Minimal rotation (3 deg/s)
      
      // Sharp vertical pothole shock: 35 m/s^2 (~3.57g)
      detector.feedAccelerometer(2.0, 2.0, 35.0);

      expect(detector.lastAccelG, greaterThan(3.5));
      expect(detector.state, CrashState.idle); // Gyro threshold not met
    });

    test('Impact spike without subsequent speed drop resets to idle', () {
      detector.feedGpsSpeed(60.0);
      detector.feedHelmetGyro(150.0, 150.0, 100.0); // Violent rotation (~234 deg/s)

      // Impact: 32 m/s^2 (~3.26g)
      detector.feedAccelerometer(15.0, 15.0, 25.0);

      expect(detector.state, CrashState.impactSeen);
      expect(detector.speedAtImpact, 60.0);

      // Rider keeps going at 58 km/h (speed drop < 15 km/h)
      detector.feedGpsSpeed(58.0);

      // Wait for speed check window (2 seconds)
      return Future.delayed(const Duration(milliseconds: 2200), () {
        expect(detector.state, CrashState.idle);
      });
    });

    test('Full Highway Crash sequence confirms and triggers alert', () async {
      // 1. Initial highway speed
      detector.feedGpsSpeed(70.0);

      // 2. Severe impact and helmet tumble
      detector.feedHelmetGyro(180.0, 150.0, 100.0); // > 250 deg/s
      detector.feedAccelerometer(20.0, 20.0, 30.0); // ~4.16g

      expect(detector.state, CrashState.impactSeen);
      expect(detector.speedAtImpact, 70.0);

      // 3. Speed drops abruptly to 0 km/h
      detector.feedGpsSpeed(0.0);

      // Wait for speed verification window (2.1s)
      await Future.delayed(const Duration(milliseconds: 2100));
      expect(detector.state, CrashState.confirming);

      // 4. Rider is stationary during stillness window (~1g, minimal gyro)
      detector.feedHelmetGyro(1.0, 1.0, 1.0);
      detector.feedAccelerometer(0.0, 0.0, 9.81); // 1.0g

      // Wait for stillness window (3.1s)
      await Future.delayed(const Duration(milliseconds: 3100));
      expect(detector.state, CrashState.alertTriggered);

      // 5. Acknowledge disarms and enters cooldown
      detector.acknowledge();
      expect(detector.state, CrashState.idle);
      expect(detector.isCoolingDown, true);

      // 6. In cooldown, new impacts are ignored
      detector.feedHelmetGyro(200.0, 200.0, 200.0);
      detector.feedAccelerometer(40.0, 40.0, 40.0);
      expect(detector.state, CrashState.idle);
    });

    test('Motion recovery during confirming window resets to idle', () async {
      detector.feedGpsSpeed(50.0);
      detector.feedHelmetGyro(150.0, 150.0, 100.0);
      detector.feedAccelerometer(20.0, 20.0, 30.0);

      expect(detector.state, CrashState.impactSeen);

      detector.feedGpsSpeed(0.0);
      await Future.delayed(const Duration(milliseconds: 2100));
      expect(detector.state, CrashState.confirming);

      // Rider gets back up and moves violently (rotation > 25 deg/s)
      detector.feedHelmetGyro(60.0, 40.0, 30.0);
      detector.feedAccelerometer(5.0, 5.0, 18.0); // Non-rest accel (~2.0g)

      expect(detector.state, CrashState.idle);
    });
  });
}
