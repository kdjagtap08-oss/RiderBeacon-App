import 'dart:async';
import 'gyro.dart';
import 'crash_detector.dart';
import 'crash_countdown_dialog.dart';
import 'simulation_panel.dart';
import 'incident_feedback_sheet.dart';
import 'incident_log_service.dart';
import 'incident_log_sheet.dart';
import 'foreground_service_manager.dart';
import 'ml_crash_classifier.dart';
import 'package:another_telephony/telephony.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'group_ride_model.dart';
import 'group_ride_service.dart';
import 'convoy_calculator.dart';
import 'convoy_rider_marker.dart';
import 'group_ride_sheet.dart';
import 'convoy_crash_dialog.dart';
import 'convoy_join_dialog.dart';
import 'auth_service.dart';

const kBg = Color(0xFF0E1116);
const kCard = Color(0xFF181D25);
const kAccent = Color(0xFFFF6B2C);
const kGood = Color(0xFF3DDC97);
const kSos = Color(0xFFE5323B);

void main() => runApp(const SmartKavachApp());

class SmartKavachApp extends StatelessWidget {
  const SmartKavachApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SmartKavach',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: kBg,
          colorScheme: ColorScheme.fromSeed(
              seedColor: kAccent, brightness: Brightness.dark),
          navigationBarTheme: const NavigationBarThemeData(
              backgroundColor: kCard, indicatorColor: Color(0x33FF6B2C)),
        ),
        home: const Shell(),
      );
}

// ───────────────────────── Services ─────────────────────────

/// Phone GPS: position + speed (km/h).
class Tracker extends ChangeNotifier {
  final map = MapController();
  StreamSubscription<Position>? _sub;
  LatLng? pos;
  double speed = 0;
  String? error;

  Future<void> start() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      error = 'Turn on location (GPS)';
      return notifyListeners();
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      error = 'Location permission needed';
      return notifyListeners();
    }
    _sub = Geolocator.getPositionStream(
      locationSettings:
          const LocationSettings(accuracy: LocationAccuracy.bestForNavigation),
    ).listen((f) {
      pos = LatLng(f.latitude, f.longitude);
      speed = f.speed < 0 ? 0 : f.speed * 3.6; // m/s -> km/h
      notifyListeners();
      try {
        map.move(pos!, 17);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// BLE link to the helmet's ESP32.
class HelmetLink extends ChangeNotifier {
  List<ScanResult> results = [];
  BluetoothDevice? device;
  bool scanning = false, connecting = false;
  BluetoothConnectionState state = BluetoothConnectionState.disconnected;
  StreamSubscription? _a, _b, _c;
  final gyro = GyroFeed();   

  HelmetLink() {
    _a = FlutterBluePlus.scanResults.listen((r) {
      results = r.where((e) => e.device.platformName.isNotEmpty).toList()
        ..sort((x, y) => y.rssi.compareTo(x.rssi));
      notifyListeners();
    });
    _b = FlutterBluePlus.isScanning.listen((s) {
      scanning = s;
      notifyListeners();
    });
  }

  bool get connected => state == BluetoothConnectionState.connected;
  String get name => device?.platformName ?? '';

  Future<void> scan() =>
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

  Future<void> connect(BluetoothDevice d) async {
    await FlutterBluePlus.stopScan();
    _c?.cancel();
    device = d;
    connecting = true;
    notifyListeners();
    _c = d.connectionState.listen((s) {
      if (s != BluetoothConnectionState.connected) gyro.clear();
      state = s;
      notifyListeners();
    });
    try {
      await d.connect(license: License.nonprofit, timeout: const Duration(seconds: 10));
      await gyro.attach(d);
    } catch (_) {
      device = null;
    }
    connecting = false;
    notifyListeners();
  }

  Future<void> disconnect() async {
    await device?.disconnect();
    device = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _a?.cancel();
    _b?.cancel();
    _c?.cancel();
    super.dispose();
  }
}

// ───────────────────────── Shell ─────────────────────────

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final tracker = Tracker();
  final helmet = HelmetLink();
  final contacts = Contacts();
  final crashDetector = CrashDetector();
  final authService = AuthService();
  final groupRideService = GroupRideService();
  StreamSubscription<List<ConvoyMemberMetric>>? _convoySub;
  String? _lastAlertedCrashUserId;
  bool _isShowingCountdown = false;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    ForegroundServiceManager.startService();
    tracker.start();
    contacts.load();
    crashDetector.startHardwareFeed();
    authService.init();

    tracker.addListener(_onTrackerUpdate);
    helmet.gyro.addListener(_onGyroUpdate);
    crashDetector.addListener(_onCrashUpdate);

    _convoySub = groupRideService.convoyMetricsStream.listen(_onConvoyMetricsUpdate);
  }

  void _onTrackerUpdate() {
    crashDetector.feedGpsSpeed(tracker.speed);
    if (tracker.pos != null && groupRideService.currentRide != null) {
      groupRideService.updateMyTelemetry(
        position: tracker.pos!,
        speedKmh: tracker.speed,
      );
    }
    ForegroundServiceManager.updateNotification(
        'Speed: ${tracker.speed.toStringAsFixed(1)} km/h • Helmet: ${helmet.connected ? "Connected" : "Disconnected"}');
  }

  void _onGyroUpdate() {
    final v = helmet.gyro.values;
    if (v != null && v.length == 3) {
      crashDetector.feedHelmetGyro(v[0], v[1], v[2]);
    }
  }

  void _onConvoyMetricsUpdate(List<ConvoyMemberMetric> metrics) {
    if (!mounted) return;
    for (final m in metrics) {
      if (m.position != RelativePosition.here &&
          m.member.status == RiderStatus.crashAlert &&
          _lastAlertedCrashUserId != m.member.userId) {
        _lastAlertedCrashUserId = m.member.userId;
        _showPeerCrashDialog(m);
        break;
      }
    }
  }

  void _showPeerCrashDialog(ConvoyMemberMetric metric) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ConvoyCrashDialog(
        metric: metric,
        onDismiss: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  void _onCrashUpdate() {
    if (crashDetector.state == CrashState.alertTriggered && !_isShowingCountdown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            crashDetector.state == CrashState.alertTriggered &&
            !_isShowingCountdown) {
          _showCountdownDialog();
        }
      });
    }
  }

  Future<void> _showCountdownDialog() async {
    _isShowingCountdown = true;
    if (!mounted) return;

    final mlLabel = crashDetector.lastMlPrediction != null
        ? switch (crashDetector.lastMlPrediction!) {
            RideEventClass.normalRiding => 'Normal Riding',
            RideEventClass.pothole => 'Road Shock / Pothole',
            RideEventClass.droppedPhone => 'Dropped Phone',
            RideEventClass.severeCrash => 'Severe Motorcycle Crash',
          }
        : 'Severe Motorcycle Crash (Physics Gate)';
    final mlConf = crashDetector.lastMlConfidence ?? 0.99;

    // Log the initial crash detection incident to offline storage
    IncidentLogService.logIncident(IncidentRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      type: IncidentType.crashAlert,
      latitude: tracker.pos?.latitude,
      longitude: tracker.pos?.longitude,
      speedKmh: tracker.speed,
      maxImpactG: crashDetector.lastAccelG,
      maxGyroDps: crashDetector.lastGyroMag,
      mlPrediction: mlLabel,
      mlConfidence: mlConf,
    ));

    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Crash Alert',
      pageBuilder: (dialogContext, anim1, anim2) => CrashCountdownDialog(
        totalSeconds: 15,
        onCancel: () {
          crashDetector.acknowledge();
          if (groupRideService.currentRide != null) {
            groupRideService.updateMyStatus(RiderStatus.riding);
          }
          IncidentLogService.updateLatestFeedback('Cancelled by rider');
          Navigator.of(dialogContext, rootNavigator: true).pop();
          _showFeedbackSheet();
        },
        onTimeout: () {
          IncidentLogService.logIncident(IncidentRecord(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            timestamp: DateTime.now(),
            type: IncidentType.sosDispatched,
            latitude: tracker.pos?.latitude,
            longitude: tracker.pos?.longitude,
            speedKmh: tracker.speed,
            maxImpactG: crashDetector.lastAccelG,
            maxGyroDps: crashDetector.lastGyroMag,
            mlPrediction: mlLabel,
            mlConfidence: mlConf,
          ));
          if (groupRideService.currentRide != null) {
            groupRideService.updateMyStatus(RiderStatus.crashAlert);
          }
          Navigator.of(dialogContext, rootNavigator: true).pop();
          sendSosAlert(
            context: context,
            tracker: tracker,
            contacts: contacts,
            isAutoCrashTrigger: true,
          );
        },
      ),
    );
    _isShowingCountdown = false;
  }

  void _showFeedbackSheet() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => IncidentFeedbackSheet(
        onFeedbackSelected: (reason) {
          final label = switch (reason) {
            IncidentReason.pothole => 'Road bump / pothole',
            IncidentReason.droppedPhone => 'Phone dropped / mount loose',
            IncidentReason.minorFallSafe => 'Minor fall (unhurt)',
            IncidentReason.otherFalseAlarm => 'False alarm',
            IncidentReason.dismissed => 'Resumed ride',
          };
          IncidentLogService.updateLatestFeedback(label);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Feedback logged: $label'), duration: const Duration(seconds: 2)),
          );
        },
        onSendReassuranceText: _sendReassuranceMessage,
      ),
    );
  }

  Future<void> _sendReassuranceMessage() async {
    final msg = ScaffoldMessenger.of(context);
    if (contacts.numbers.isEmpty) return;

    final sms = Telephony.instance;
    const text =
        "SmartKavach Update: I had a minor slide with my bike, but I am completely unhurt and safe! No assistance needed.";
    if (await sms.requestSmsPermissions ?? false) {
      for (final n in contacts.numbers) {
        try {
          await sms.sendSms(to: n, message: text);
        } catch (_) {}
      }
      IncidentLogService.updateLatestFeedback('Minor fall (unhurt)', reassuranceSent: true);
      msg.showSnackBar(
        const SnackBar(content: Text("'I'm Safe' reassurance text sent to contacts")),
      );
    }
  }

  @override
  void dispose() {
    _convoySub?.cancel();
    ForegroundServiceManager.stopService();
    tracker.removeListener(_onTrackerUpdate);
    helmet.gyro.removeListener(_onGyroUpdate);
    crashDetector.removeListener(_onCrashUpdate);

    tracker.dispose();
    helmet.dispose();
    contacts.dispose();
    crashDetector.dispose();
    groupRideService.dispose();
    authService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: IndexedStack(index: tab, children: [
            HomePage(
                t: tracker,
                h: helmet,
                contacts: contacts,
                crash: crashDetector,
                auth: authService,
                groupRide: groupRideService,
                openHelmet: () => setState(() => tab = 1)),
            HelmetPage(h: helmet),
          ]),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.speed), label: 'Ride'),
            NavigationDestination(
                icon: Icon(Icons.sports_motorsports), label: 'Helmet'),
          ],
        ),
      );
}

class Panel extends StatelessWidget {
  const Panel(
      {super.key, required this.child, this.pad = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets pad;

  @override
  Widget build(BuildContext context) => Container(
        padding: pad,
        decoration: BoxDecoration(
            color: kCard, borderRadius: BorderRadius.circular(20)),
        child: child,
      );
}

/// Centralized SOS dispatch (shared by manual button and automated crash trigger).
Future<void> sendSosAlert({
  required BuildContext context,
  required Tracker tracker,
  required Contacts contacts,
  bool isAutoCrashTrigger = false,
}) async {
  HapticFeedback.heavyImpact();
  final msg = ScaffoldMessenger.of(context);
  if (contacts.numbers.isEmpty) {
    msg.showSnackBar(const SnackBar(
        content: Text('Add an emergency contact in SOS settings first')));
    return;
  }

  // 1) Location: last GPS fix, or try to get a fresh one.
  LatLng? here = tracker.pos;
  if (here == null) {
    try {
      final p = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(timeLimit: Duration(seconds: 8)));
      here = LatLng(p.latitude, p.longitude);
    } catch (_) {}
  }
  final where = here == null
      ? 'Location unavailable.'
      : 'https://maps.google.com/?q=${here.latitude.toStringAsFixed(5)},${here.longitude.toStringAsFixed(5)}';
  final prefix = isAutoCrashTrigger ? 'CRASH DETECTED!' : 'SOS!';
  final text = '$prefix I need help. My location: $where';

  // 2) SMS to every contact
  final sms = Telephony.instance;
  if (await sms.requestSmsPermissions ?? false) {
    for (final n in contacts.numbers) {
      try {
        await sms.sendSms(to: n, message: text);
      } catch (_) {}
    }
    msg.showSnackBar(SnackBar(
        content: Text('SOS sent to ${contacts.numbers.length} contact(s)')));
  } else {
    msg.showSnackBar(
        const SnackBar(content: Text('SMS permission denied, calling only')));
  }

  // 3) Call the first contact.
  await FlutterPhoneDirectCaller.callNumber(contacts.numbers.first);
}

// ───────────────────────── Ride tab ─────────────────────────

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.t,
    required this.h,
    required this.contacts,
    required this.crash,
    required this.openHelmet,
    this.auth,
    this.groupRide,
  });

  final Tracker t;
  final HelmetLink h;
  final Contacts contacts;
  final CrashDetector crash;
  final VoidCallback openHelmet;
  final AuthService? auth;
  final GroupRideService? groupRide;

  void _openConvoyDialog(BuildContext context) {
    if (auth == null || groupRide == null) return;
    showDialog(
      context: context,
      builder: (_) => ConvoyJoinDialog(
        authService: auth!,
        groupRideService: groupRide!,
        currentLocation: t.pos ?? const LatLng(19.0760, 72.8777),
      ),
    );
  }

  void _openGroupRideSheet(BuildContext context, GroupRide ride) {
    if (groupRide == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GroupRideSheet(
        ride: ride,
        metrics: groupRide!.currentMetrics,
        currentUserId: auth?.currentUser?.id ?? groupRide!.currentUserId ?? '',
        onStatusChanged: (status) => groupRide!.updateMyStatus(status),
        onShareInvite: () => GroupRideService.shareInvite(ride),
        onNavigateToMember: (member) =>
            GroupRideService.openDirectionsTo(member.position),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([t, h, contacts]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('SmartKavach',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                TextButton.icon(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const IncidentLogSheet(),
                  ),
                  icon: const Icon(Icons.history, size: 16, color: Color(0xFF3DDC97)),
                  label: const Text('Ride Log',
                      style: TextStyle(color: Color(0xFF3DDC97), fontSize: 13, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    backgroundColor: kCard,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: openHelmet,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: kCard, borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    Icon(Icons.circle,
                        size: 10, color: h.connected ? kGood : Colors.white38),
                    const SizedBox(width: 8),
                    Text(h.connected ? 'Helmet connected' : 'Connect helmet',
                        style: const TextStyle(fontSize: 13)),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SosSettingsPage(contacts: contacts))),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: kCard, borderRadius: BorderRadius.circular(20)),
                  child: const Row(children: [
                    Icon(Icons.settings, size: 14, color: kAccent),
                    SizedBox(width: 8),
                    Text('SOS settings', style: TextStyle(fontSize: 13)),
                  ]),
                ),
              ),
            ]),
            if (groupRide != null) ...[
              const SizedBox(height: 12),
              StreamBuilder<GroupRide?>(
                stream: groupRide!.rideStream,
                initialData: groupRide!.currentRide,
                builder: (context, snapshot) {
                  final activeRide = snapshot.data;
                  if (activeRide == null) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _openConvoyDialog(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: kCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: kAccent.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.groups, color: kAccent, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Ride Together (Group Convoy)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    'Track group live on map • Crash mesh alerts',
                                    style: TextStyle(fontSize: 11, color: Colors.white54),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: Colors.white38, size: 18),
                          ],
                        ),
                      ),
                    );
                  }

                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openGroupRideSheet(context, activeRide),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF19232F),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: kGood.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.groups, color: kGood, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activeRide.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Code: ${activeRide.rideCode} • ${activeRide.members.length} Riders in Convoy',
                                  style: const TextStyle(fontSize: 11, color: kGood, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.share, color: Colors.white70, size: 16),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => GroupRideService.shareInvite(activeRide),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 16),
            Panel(
              child: Column(children: [
                SizedBox(
                  width: 210,
                  height: 210,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: (t.speed / 120).clamp(0.0, 1.0),
                        strokeWidth: 14,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.white10,
                        color: kAccent,
                      ),
                    ),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(t.speed.toStringAsFixed(0),
                          style: const TextStyle(
                              fontSize: 68, fontWeight: FontWeight.w800)),
                      const Text('km/h',
                          style: TextStyle(color: Colors.white54)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 12),
                Text(
                  t.error ??
                      (t.pos == null
                          ? 'Waiting for GPS...'
                          : '${t.pos!.latitude.toStringAsFixed(5)}, ${t.pos!.longitude.toStringAsFixed(5)}'),
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Panel(
              pad: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 200,
                  child: FlutterMap(
                    mapController: t.map,
                    options: const MapOptions(
                        initialCenter: LatLng(20.5937, 78.9629),
                        initialZoom: 4),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.smartkavach',
                      ),
                      if (t.pos != null)
                        MarkerLayer(markers: [
                          Marker(
                              point: t.pos!,
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.navigation,
                                  color: kAccent, size: 36)),
                        ]),
                      if (groupRide != null)
                        StreamBuilder<List<ConvoyMemberMetric>>(
                          stream: groupRide!.convoyMetricsStream,
                          initialData: groupRide!.currentMetrics,
                          builder: (context, snap) {
                            final metrics = snap.data ?? [];
                            final otherMembers =
                                metrics.where((m) => m.position != RelativePosition.here);
                            if (otherMembers.isEmpty) return const SizedBox.shrink();

                            return MarkerLayer(
                              markers: otherMembers
                                  .map(
                                    (m) => Marker(
                                      point: m.member.position,
                                      width: 90,
                                      height: 52,
                                      child: ConvoyRiderMarker(
                                        metric: m,
                                        onTap: () {
                                          if (groupRide!.currentRide != null) {
                                            _openGroupRideSheet(
                                                context, groupRide!.currentRide!);
                                          }
                                        },
                                      ),
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
                const SizedBox(height: 16),
                GyroPanel(g: h.gyro),
                const SizedBox(height: 16),
                SimulationPanel(detector: crash),
                const SizedBox(height: 20),
            GestureDetector(
              onLongPress: () => sendSosAlert(
                context: context,
                tracker: t,
                contacts: contacts,
              ),
              child: Container(
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kSos,
                  borderRadius: BorderRadius.circular(38),
                  boxShadow: [
                    BoxShadow(color: kSos.withValues(alpha: 0.4), blurRadius: 24)
                  ],
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.sos, size: 32),
                  SizedBox(width: 10),
                  Text('HOLD FOR SOS',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                ]),
              ),
            ),
          ],
        ),
      );
}

// ───────────────────────── Helmet tab ─────────────────────────

class HelmetPage extends StatelessWidget {
  const HelmetPage({super.key, required this.h});
  final HelmetLink h;

  bool _likely(String n) {
    final s = n.toLowerCase();
    return s.contains('kavach') || s.contains('esp');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: h,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('My Helmet',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Panel(
              child: SizedBox(
                width: double.infinity,
                child: Column(children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor:
                        (h.connected ? kGood : Colors.white24).withValues(alpha: 0.2),
                    child: Icon(Icons.sports_motorsports,
                        size: 36, color: h.connected ? kGood : Colors.white54),
                  ),
                  const SizedBox(height: 12),
                  Text(
                      h.connecting
                          ? 'Connecting...'
                          : h.connected
                              ? 'Connected'
                              : 'Not connected',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(
                      h.connected
                          ? h.name
                          : 'Switch on your helmet and tap Scan',
                      style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 14),
                  if (h.connected)
                    OutlinedButton.icon(
                        onPressed: h.disconnect,
                        icon: const Icon(Icons.link_off),
                        label: const Text('Disconnect'))
                  else
                    FilledButton.icon(
                        onPressed: h.scanning || h.connecting ? null : h.scan,
                        icon: h.scanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.bluetooth_searching),
                        label: Text(
                            h.scanning ? 'Scanning...' : 'Scan for helmet')),
                ]),
              ),
            ),
            StreamBuilder<BluetoothAdapterState>(
              stream: FlutterBluePlus.adapterState,
              builder: (context, s) =>
                  (s.data == null || s.data == BluetoothAdapterState.on)
                      ? const SizedBox.shrink()
                      : const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Panel(
                              child: Row(children: [
                            Icon(Icons.bluetooth_disabled, color: kAccent),
                            SizedBox(width: 12),
                            Expanded(
                                child: Text(
                                    'Bluetooth is off. Turn it on to find your helmet.')),
                          ]))),
            ),
            if (!h.connected) ...[
              const SizedBox(height: 20),
              const Text('Nearby devices',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (h.results.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                        child: Text('No devices yet',
                            style: TextStyle(color: Colors.white38)))),
              for (final r in h.results)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    pad:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(children: [
                      Icon(Icons.bluetooth,
                          color: _likely(r.device.platformName)
                              ? kAccent
                              : Colors.white54),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.device.platformName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              Text(
                                  '${r.rssi} dBm${_likely(r.device.platformName) ? '  •  likely your helmet' : ''}',
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                            ]),
                      ),
                      TextButton(
                          onPressed:
                              h.connecting ? null : () => h.connect(r.device),
                          child: const Text('Connect')),
                    ]),
                  ),
                ),
            ],
          ],
        ),
      );
}


// ───────────────────────── SOS settings ─────────────────────────

/// Emergency numbers, saved on the phone.
class Contacts extends ChangeNotifier {
  static const _key = 'sos_numbers';
  List<String> numbers = [];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    numbers = p.getStringList(_key) ?? [];
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, numbers);
    notifyListeners();
  }

  Future<void> add(String n) {
    numbers = [...numbers, n];
    return _save();
  }

  Future<void> remove(String n) {
    numbers = numbers.where((x) => x != n).toList();
    return _save();
  }
}

class SosSettingsPage extends StatefulWidget {
  const SosSettingsPage({super.key, required this.contacts});
  final Contacts contacts;

  @override
  State<SosSettingsPage> createState() => _SosSettingsPageState();
}

class _SosSettingsPageState extends State<SosSettingsPage> {
  final _ctrl = TextEditingController();
  String? _err;

  Future<void> _add() async {
    final n = _ctrl.text.replaceAll(RegExp(r'[^0-9+]'), '');
    final c = widget.contacts;
    if (n.replaceAll('+', '').length < 7) {
      return setState(() => _err = 'Enter a valid phone number');
    }
    if (c.numbers.contains(n)) return setState(() => _err = 'Already added');
    if (c.numbers.length >= 3) {
      return setState(() => _err = 'Maximum 3 contacts');
    }
    await c.add(n);
    _ctrl.clear();
    setState(() => _err = null);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('SOS settings'), backgroundColor: kBg),
        body: ListenableBuilder(
          listenable: widget.contacts,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Panel(
                child: Text(
                    'When you hold the SOS button, the app texts your live location to all contacts and calls the first one. Add up to 3 numbers.',
                    style: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Emergency contact number',
                      errorText: _err,
                      filled: true,
                      fillColor: kCard,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    style: IconButton.styleFrom(minimumSize: const Size(56, 56))),
              ]),
              const SizedBox(height: 16),
              if (widget.contacts.numbers.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                        child: Text('No contacts yet',
                            style: TextStyle(color: Colors.white38)))),
              for (var i = 0; i < widget.contacts.numbers.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(children: [
                      const Icon(Icons.phone, color: kAccent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.contacts.numbers[i],
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              if (i == 0)
                                const Text('Called first',
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                            ]),
                      ),
                      IconButton(
                          onPressed: () =>
                              widget.contacts.remove(widget.contacts.numbers[i]),
                          icon: const Icon(Icons.delete_outline)),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      );
}