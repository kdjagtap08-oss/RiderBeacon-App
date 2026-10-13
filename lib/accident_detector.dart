import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gyro.dart';

enum CrashSensitivity { low, normal, high }

enum AccidentState { idle, countdown, dispatched, cancelled }

class SpeedSample {
  final DateTime time;
  final double speedKmH;
  SpeedSample(this.time, this.speedKmH);
}

/// Settings for automatic crash detection & emergency response.
class AccidentSettings extends ChangeNotifier {
  static const _kEnabled = 'crash_detection_enabled';
  static const _kPoliceNumber = 'crash_police_number';
  static const _kCallPoliceNoNetwork = 'crash_call_police_no_network';
  static const _kAlwaysCallPolice = 'crash_always_call_police';
  static const _kCountdown = 'crash_countdown_sec';
  static const _kSensitivity = 'crash_sensitivity';
  static const _kGyroThreshold = 'crash_gyro_threshold';

  bool enabled = true;
  String policeNumber = '100';
  bool callPoliceOnNoNetwork = true;
  bool alwaysCallPoliceOnCrash = false;
  int countdownDuration = 15; // seconds
  CrashSensitivity sensitivity = CrashSensitivity.normal;
  double gyroThreshold = 240.0; // deg/s (MPU trigger limit)

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool(_kEnabled) ?? true;
    policeNumber = p.getString(_kPoliceNumber) ?? '100';
    callPoliceOnNoNetwork = p.getBool(_kCallPoliceNoNetwork) ?? true;
    alwaysCallPoliceOnCrash = p.getBool(_kAlwaysCallPolice) ?? false;
    countdownDuration = p.getInt(_kCountdown) ?? 15;
    final sensStr = p.getString(_kSensitivity) ?? 'normal';
    sensitivity = CrashSensitivity.values.firstWhere(
      (e) => e.name == sensStr,
      orElse: () => CrashSensitivity.normal,
    );
    gyroThreshold = p.getDouble(_kGyroThreshold) ??
        (sensitivity == CrashSensitivity.high
            ? 180.0
            : sensitivity == CrashSensitivity.low
                ? 320.0
                : 240.0);
    notifyListeners();
  }

  Future<void> update({
    bool? newEnabled,
    String? newPoliceNumber,
    bool? newCallPoliceNoNetwork,
    bool? newAlwaysCallPolice,
    int? newCountdownDuration,
    CrashSensitivity? newSensitivity,
    double? newGyroThreshold,
  }) async {
    final p = await SharedPreferences.getInstance();
    if (newEnabled != null) {
      enabled = newEnabled;
      await p.setBool(_kEnabled, enabled);
    }
    if (newPoliceNumber != null && newPoliceNumber.isNotEmpty) {
      policeNumber = newPoliceNumber;
      await p.setString(_kPoliceNumber, policeNumber);
    }
    if (newCallPoliceNoNetwork != null) {
      callPoliceOnNoNetwork = newCallPoliceNoNetwork;
      await p.setBool(_kCallPoliceNoNetwork, callPoliceOnNoNetwork);
    }
    if (newAlwaysCallPolice != null) {
      alwaysCallPoliceOnCrash = newAlwaysCallPolice;
      await p.setBool(_kAlwaysCallPolice, alwaysCallPoliceOnCrash);
    }
    if (newCountdownDuration != null) {
      countdownDuration = newCountdownDuration;
      await p.setInt(_kCountdown, countdownDuration);
    }
    if (newSensitivity != null) {
      sensitivity = newSensitivity;
      await p.setString(_kSensitivity, sensitivity.name);
      if (newGyroThreshold == null) {
        gyroThreshold = sensitivity == CrashSensitivity.high
            ? 180.0
            : sensitivity == CrashSensitivity.low
                ? 320.0
                : 240.0;
        await p.setDouble(_kGyroThreshold, gyroThreshold);
      }
    }
    if (newGyroThreshold != null) {
      gyroThreshold = newGyroThreshold;
      await p.setDouble(_kGyroThreshold, gyroThreshold);
    }
    notifyListeners();
  }
}

/// Native bridge for playing system alarm at max volume
class AlarmPlayer {
  static const _channel = MethodChannel('smart_kavach/alarm');

  static Future<void> playAlarm() async {
    try {
      await _channel.invokeMethod('playAlarm');
    } catch (e) {
      debugPrint('AlarmPlayer error: $e');
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopAlarm');
    } catch (e) {
      debugPrint('AlarmPlayer stop error: $e');
    }
  }
}

/// Automatically detects motorcycle accidents via:
/// 1. Abnormal speed drops (GPS deceleration)
/// 2. Gyroscope rapid angle/angular velocity changes (BLE Helmet + Phone Gyro)
/// 3. Accelerometer high G-force impacts & abnormal tilt angles
///
/// If a crash is detected:
/// - Loud SOS alarm rings with emergency countdown
/// - Rider can cancel if safe
/// - If countdown expires:
///   * If NO network: Automatically places a direct cellular call to Police 100
///     and texts emergency contacts via offline SMS
///   * If online network: Texts contacts live location & initiates emergency call
class AccidentDetector extends ChangeNotifier {
  final AccidentSettings settings;
  final GyroFeed helmetGyro;

  AccidentState state = AccidentState.idle;
  int countdownRemaining = 15;
  String detectionReason = '';
  DateTime? _lastTriggerTime;

  // Sensor streams
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  Timer? _countdownTimer;
  Timer? _vibrationTimer;

  // Real-time sensor metrics
  double currentSpeed = 0.0;
  final List<SpeedSample> _speedHistory = [];
  double lastPhoneGForce = 1.0;
  double lastPhoneGyroDeg = 0.0;
  double lastHelmetGyroDeg = 0.0;
  double lastTiltAngleDeg = 0.0;

  // External context providers
  LatLng? Function()? locationProvider;
  List<String> Function()? contactsProvider;
  void Function(String message)? onStatusCallback;

  AccidentDetector({required this.settings, required this.helmetGyro}) {
    _initSensors();
  }

  void _initSensors() {
    try {
      _accelSub = accelerometerEventStream().listen(_onAccelerometer);
    } catch (e) {
      debugPrint('Accelerometer stream error: $e');
    }

    try {
      _gyroSub = gyroscopeEventStream().listen(_onPhoneGyro);
    } catch (e) {
      debugPrint('Gyroscope stream error: $e');
    }

    helmetGyro.addListener(_onHelmetGyro);
  }

  /// Called from Tracker whenever GPS updates speed
  void onSpeedUpdate(double speedKmH) {
    currentSpeed = speedKmH;
    final now = DateTime.now();
    _speedHistory.add(SpeedSample(now, speedKmH));

    // Keep only last 4 seconds of speed
    _speedHistory.removeWhere((s) => now.difference(s.time).inSeconds > 4);

    _evaluateAccidentConditions();
  }

  void _onAccelerometer(AccelerometerEvent event) {
    final mag = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    lastPhoneGForce = mag / 9.80665; // Convert m/s^2 to G-force

    // Approximate tilt from upright vertical (z/y orientation)
    if (mag > 0.01) {
      // Angle relative to upright plane in degrees
      final zComponent = (event.z / mag).clamp(-1.0, 1.0);
      lastTiltAngleDeg = (math.acos(zComponent) * 180.0 / math.pi);
    }

    _evaluateAccidentConditions();
  }

  void _onPhoneGyro(GyroscopeEvent event) {
    final radMag = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    final maxSingleAxis = math.max(event.x.abs(), math.max(event.y.abs(), event.z.abs()));
    final effectiveRad = math.max(radMag, maxSingleAxis);
    lastPhoneGyroDeg = effectiveRad * (180.0 / math.pi); // rad/s -> deg/s
    _evaluateAccidentConditions();
  }

  void _onHelmetGyro() {
    lastHelmetGyroDeg = helmetGyro.effectiveRotationRate;
    _evaluateAccidentConditions();
  }

  /// Calculates maximum speed seen in the last 2.5 seconds
  double _getMaxRecentSpeed() {
    if (_speedHistory.isEmpty) return currentSpeed;
    final now = DateTime.now();
    double maxS = 0;
    for (final s in _speedHistory) {
      if (now.difference(s.time).inMilliseconds <= 2500) {
        if (s.speedKmH > maxS) maxS = s.speedKmH;
      }
    }
    return maxS;
  }

  /// Evaluates physics thresholds to detect an accident
  void _evaluateAccidentConditions() {
    if (!settings.enabled) return;
    if (state == AccidentState.countdown || state == AccidentState.dispatched) return;

    // Cooldown check (15 seconds after cancellation to avoid false re-triggers)
    if (_lastTriggerTime != null &&
        DateTime.now().difference(_lastTriggerTime!).inSeconds < 15) {
      return;
    }

    final maxRecentSpeed = _getMaxRecentSpeed();
    final speedDrop = maxRecentSpeed - currentSpeed;
    final maxGyroDeg = math.max(lastPhoneGyroDeg, lastHelmetGyroDeg);
    final minGyroDeg = settings.gyroThreshold; // Default 240.0 deg/s

    // CONDITION 0: Direct Gyroscope Threshold Breach (MPU / Helmet reads >= 240°/s)
    // Triggers immediately when gyroscope reading exceeds 240+ °/s without needing GPS speed!
    final bool gyroThresholdExceeded = maxGyroDeg >= minGyroDeg;

    // CONDITION 1: Road Deceleration + Gyro Twist (Moving at speed + sudden speed drop + twist)
    final bool speedDropWithGyro =
        (maxRecentSpeed >= 12.0 && speedDrop >= 10.0) &&
        (maxGyroDeg >= (minGyroDeg * 0.55));

    // CONDITION 2: Road Deceleration + Impact Shock
    final bool speedDropWithImpact =
        (maxRecentSpeed >= 12.0 && speedDrop >= 10.0) &&
        (lastPhoneGForce >= 2.2);

    // CONDITION 3: Violent Angular Tumble + High G-force Impact (Vehicle rollover or flip)
    final bool impactAndTumble =
        (lastPhoneGForce >= 2.4) && (maxGyroDeg >= (minGyroDeg * 0.7) || lastTiltAngleDeg > 65.0);

    if (gyroThresholdExceeded || speedDropWithGyro || speedDropWithImpact || impactAndTumble) {
      String reason = 'Accident detected: ';
      if (gyroThresholdExceeded) {
        String axisDetail = '';
        final hv = helmetGyro.values;
        if (hv != null && hv.length >= 3) {
          if (hv[0].abs() >= minGyroDeg) {
            axisDetail = ' [X-Axis: ${hv[0].toStringAsFixed(0)}°/s]';
          } else if (hv[1].abs() >= minGyroDeg) {
            axisDetail = ' [Y-Axis: ${hv[1].toStringAsFixed(0)}°/s]';
          } else if (hv[2].abs() >= minGyroDeg) {
            axisDetail = ' [Z-Axis: ${hv[2].toStringAsFixed(0)}°/s]';
          }
        }
        reason += 'Rotation (${maxGyroDeg.toStringAsFixed(0)}°/s)$axisDetail exceeded limit (${minGyroDeg.toStringAsFixed(0)}°/s)';
      } else if (speedDropWithGyro) {
        reason += 'Sudden speed drop (${speedDrop.toStringAsFixed(0)} km/h) & sharp gyro twist (${maxGyroDeg.toStringAsFixed(0)}°/s)';
      } else if (speedDropWithImpact) {
        reason += 'Sudden speed drop (${speedDrop.toStringAsFixed(0)} km/h) & severe impact (${lastPhoneGForce.toStringAsFixed(1)}G)';
      } else {
        reason += 'High impact (${lastPhoneGForce.toStringAsFixed(1)}G) with violent tilt/roll (${maxGyroDeg.toStringAsFixed(0)}°/s)';
      }

      triggerCrashAlarm(reason: reason);
    }
  }

  /// Triggers the emergency countdown & rings the loud SOS alarm
  void triggerCrashAlarm({String reason = 'Abnormal speed drop & tilt detected'}) {
    if (state == AccidentState.countdown) return;

    _lastTriggerTime = DateTime.now();
    detectionReason = reason;
    countdownRemaining = settings.countdownDuration;
    state = AccidentState.countdown;
    notifyListeners();

    // Start loud SOS Alarm
    _playSosAlarm();

    // Start countdown timer
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdownRemaining > 1) {
        countdownRemaining--;
        notifyListeners();
        // Periodic alert vibration
        HapticFeedback.heavyImpact();
      } else {
        countdownRemaining = 0;
        _countdownTimer?.cancel();
        _vibrationTimer?.cancel();
        // Trigger emergency response automatically
        dispatchEmergencyResponse(
          location: locationProvider?.call(),
          emergencyContacts: contactsProvider?.call() ?? const [],
          onStatusUpdate: onStatusCallback,
        );
      }
    });

    // Heavy pulsing haptics
    _vibrationTimer?.cancel();
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (state == AccidentState.countdown) {
        HapticFeedback.vibrate();
      }
    });
  }

  void _playSosAlarm() {
    AlarmPlayer.playAlarm();
  }

  void _stopSosAlarm() {
    AlarmPlayer.stop();
    _countdownTimer?.cancel();
    _vibrationTimer?.cancel();
  }

  /// User cancels false alarm ("I AM OK")
  void cancelAlarm() {
    _stopSosAlarm();
    state = AccidentState.cancelled;
    detectionReason = '';
    notifyListeners();

    // Return to idle after a moment
    Future.delayed(const Duration(seconds: 1), () {
      if (state == AccidentState.cancelled) {
        state = AccidentState.idle;
        notifyListeners();
      }
    });
  }

  /// Checks if internet network is currently reachable
  Future<bool> checkInternetNetwork() async {
    try {
      final lookup = await InternetAddress.lookup('google.com')
          .timeout(const Duration(milliseconds: 2200));
      return lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Dispatches the emergency response (Police call & Emergency SMS)
  /// - If NO network: Prioritizes calling Police 100 directly and sends offline SMS
  /// - If network available: Sends SMS to contacts and calls primary contact or Police
  Future<void> dispatchEmergencyResponse({
    LatLng? location,
    List<String> emergencyContacts = const [],
    void Function(String message)? onStatusUpdate,
  }) async {
    _stopSosAlarm();
    state = AccidentState.dispatched;
    notifyListeners();

    // 1. Determine location string
    LatLng? here = location ?? locationProvider?.call();
    final contactsList = emergencyContacts.isNotEmpty
        ? emergencyContacts
        : (contactsProvider?.call() ?? const <String>[]);
    final statusCallback = onStatusUpdate ?? onStatusCallback;
    if (here == null) {
      try {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            timeLimit: Duration(seconds: 4),
            accuracy: LocationAccuracy.high,
          ),
        );
        here = LatLng(p.latitude, p.longitude);
      } catch (_) {}
    }

    final locationText = here != null
        ? 'Location: https://maps.google.com/?q=${here.latitude.toStringAsFixed(5)},${here.longitude.toStringAsFixed(5)} (Lat: ${here.latitude.toStringAsFixed(5)}, Lng: ${here.longitude.toStringAsFixed(5)})'
        : 'Location unavailable.';

    // 2. Check network connectivity
    final bool hasNetwork = await checkInternetNetwork();
    final String policeNum = settings.policeNumber.trim().isNotEmpty
        ? settings.policeNumber.trim()
        : '100';

    // 3. Send SMS to registered emergency contacts (cellular SMS works offline without internet data)
    final smsText = 'CRASH ALERT! Abnormal impact & angle change detected on rider. '
        '$locationText. ${!hasNetwork ? "No internet network available. Calling Police ($policeNum)." : ""}';

    final telephony = Telephony.instance;
    try {
      final hasSmsPerm = await telephony.requestSmsPermissions ?? false;
      if (hasSmsPerm && contactsList.isNotEmpty) {
        for (final number in contactsList) {
          try {
            await telephony.sendSms(to: number, message: smsText);
          } catch (e) {
            debugPrint('Error sending SMS to $number: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('SMS exception: $e');
    }

    // 4. Emergency Call Routing
    // IF NO NETWORK: Directly call Police (100) via cellular voice line!
    if (!hasNetwork && settings.callPoliceOnNoNetwork) {
      statusCallback?.call('No network detected. Calling Police ($policeNum)...');
      try {
        await FlutterPhoneDirectCaller.callNumber(policeNum);
      } catch (e) {
        debugPrint('Error calling police: $e');
      }
    } else if (settings.alwaysCallPoliceOnCrash) {
      // User explicitly set to always dial police on crash
      statusCallback?.call('Calling Police ($policeNum)...');
      try {
        await FlutterPhoneDirectCaller.callNumber(policeNum);
      } catch (e) {
        debugPrint('Error calling police: $e');
      }
    } else {
      // If network is available and contacts exist, call first contact
      if (contactsList.isNotEmpty) {
        statusCallback?.call('Calling emergency contact: ${contactsList.first}...');
        try {
          await FlutterPhoneDirectCaller.callNumber(contactsList.first);
        } catch (e) {
          debugPrint('Error calling contact: $e');
        }
      } else {
        // Fallback to Police if no contacts added
        statusCallback?.call('No contacts set. Calling Police ($policeNum)...');
        try {
          await FlutterPhoneDirectCaller.callNumber(policeNum);
        } catch (e) {
          debugPrint('Error calling police: $e');
        }
      }
    }
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    helmetGyro.removeListener(_onHelmetGyro);
    _countdownTimer?.cancel();
    _vibrationTimer?.cancel();
    _stopSosAlarm();
    super.dispose();
  }
}
