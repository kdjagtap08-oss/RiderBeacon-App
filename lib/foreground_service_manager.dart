import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void startForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(SmartKavachTaskHandler());
}

class SmartKavachTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    if (kDebugMode) {
      print('SmartKavach Foreground Service started: ${starter.name}');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Periodic background keep-alive
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    if (kDebugMode) {
      print('SmartKavach Foreground Service destroyed (timeout: $isTimeout)');
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data is String) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'SmartKavach • Ride Guard Active',
        notificationText: data,
      );
    }
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {}
}

class ForegroundServiceManager {
  static bool _initialized = false;

  /// Initializes communication port and service notification configuration.
  static void init() {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.initCommunicationPort();

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'smartkavach_ride_guard',
        channelName: 'SmartKavach Ride Guard',
        channelDescription:
            'Keeps crash detection and helmet sensors active while riding.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(10000), // 10s heartbeat
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Requests notification permission on Android 13+.
  static Future<void> requestPermissions() async {
    if (!Platform.isAndroid) return;

    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  /// Starts the persistent background foreground service.
  static Future<bool> startService({String initialText = 'Monitoring telematics & helmet'}) async {
    if (!Platform.isAndroid) return true;
    init();
    await requestPermissions();

    if (await FlutterForegroundTask.isRunningService) {
      return true;
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 101,
      notificationTitle: 'SmartKavach • Ride Guard Active',
      notificationText: initialText,
      callback: startForegroundCallback,
    );

    return result is ServiceRequestSuccess;
  }

  /// Updates notification text with real-time speed & status.
  static void updateNotification(String text) {
    if (!Platform.isAndroid) return;
    FlutterForegroundTask.sendDataToTask(text);
  }

  /// Stops the background service.
  static Future<bool> stopService() async {
    if (!Platform.isAndroid) return true;
    if (!await FlutterForegroundTask.isRunningService) {
      return true;
    }
    final result = await FlutterForegroundTask.stopService();
    return result is ServiceRequestSuccess;
  }

  /// Checks if service is currently running.
  static Future<bool> get isRunning async {
    if (!Platform.isAndroid) return false;
    return await FlutterForegroundTask.isRunningService;
  }
}
