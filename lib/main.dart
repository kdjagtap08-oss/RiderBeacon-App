import 'dart:async';
import 'package:another_telephony/telephony.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accident_alert_dialog.dart';
import 'accident_detector.dart';
import 'gyro.dart';
import 'sos_settings_page.dart';

export 'sos_settings_page.dart';

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
  void Function(double speed)? onSpeedChanged;

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
      onSpeedChanged?.call(speed);
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
  final settings = AccidentSettings();
  late final detector = AccidentDetector(
    settings: settings,
    helmetGyro: helmet.gyro,
  );

  int tab = 0;

  @override
  void initState() {
    super.initState();
    tracker.start();
    contacts.load();
    settings.load();

    // Connect speed & position to accident detector
    tracker.onSpeedChanged = (s) => detector.onSpeedUpdate(s);
    detector.locationProvider = () => tracker.pos;
    detector.contactsProvider = () => contacts.numbers;
    detector.onStatusCallback = (msg) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    };
  }

  @override
  void dispose() {
    detector.dispose();
    tracker.dispose();
    helmet.dispose();
    contacts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: detector,
      builder: (context, _) => Stack(
        children: [
          Scaffold(
            body: SafeArea(
              child: IndexedStack(index: tab, children: [
                HomePage(
                  t: tracker,
                  h: helmet,
                  contacts: contacts,
                  detector: detector,
                  openHelmet: () => setState(() => tab = 1),
                ),
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
          ),

          // High Priority Accident SOS Countdown Modal
          if (detector.state == AccidentState.countdown)
            Positioned.fill(
              child: AccidentAlertModal(
                detector: detector,
                onCancel: () {
                  detector.cancelAlarm();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Alarm cancelled. Safe riding!')),
                  );
                },
                onDispatchNow: () {
                  detector.dispatchEmergencyResponse(
                    location: tracker.pos,
                    emergencyContacts: contacts.numbers,
                    onStatusUpdate: (msg) {
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(msg)));
                      }
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
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

// ───────────────────────── Ride tab ─────────────────────────

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.t,
    required this.h,
    required this.contacts,
    required this.detector,
    required this.openHelmet,
  });

  final Tracker t;
  final HelmetLink h;
  final Contacts contacts;
  final AccidentDetector detector;
  final VoidCallback openHelmet;

  /// Manual SOS: 1) get location, 2) check network, 3) SMS/call Police or contacts.
  Future<void> _sos(BuildContext c) async {
    HapticFeedback.heavyImpact();
    final msg = ScaffoldMessenger.of(c);

    // 1) Location: last GPS fix, or try to get a fresh one.
    LatLng? here = t.pos;
    if (here == null) {
      try {
        final p = await Geolocator.getCurrentPosition(
            locationSettings:
                const LocationSettings(timeLimit: Duration(seconds: 5)));
        here = LatLng(p.latitude, p.longitude);
      } catch (_) {}
    }

    final where = here == null
        ? 'Location unavailable.'
        : 'Location: https://maps.google.com/?q=${here.latitude.toStringAsFixed(5)},${here.longitude.toStringAsFixed(5)}';

    // 2) Check network
    final hasNet = await detector.checkInternetNetwork();
    final policeNum = detector.settings.policeNumber;
    final text = 'SOS! I need urgent help! $where ${!hasNet ? "No network available. Alerting Police ($policeNum)." : ""}';

    // 3) SMS to contacts
    final sms = Telephony.instance;
    if (await sms.requestSmsPermissions ?? false) {
      for (final n in contacts.numbers) {
        try {
          await sms.sendSms(to: n, message: text);
        } catch (_) {}
      }
      if (contacts.numbers.isNotEmpty) {
        msg.showSnackBar(SnackBar(
            content: Text('SOS text sent to ${contacts.numbers.length} contact(s)')));
      }
    }

    // 4) Calling routing: If no network -> Call Police 100!
    if (!hasNet && detector.settings.callPoliceOnNoNetwork) {
      msg.showSnackBar(SnackBar(
          content: Text('No network detected. Calling Police ($policeNum)...')));
      await FlutterPhoneDirectCaller.callNumber(policeNum);
    } else if (contacts.numbers.isNotEmpty) {
      await FlutterPhoneDirectCaller.callNumber(contacts.numbers.first);
    } else {
      msg.showSnackBar(SnackBar(
          content: Text('No contacts configured. Calling Police ($policeNum)...')));
      await FlutterPhoneDirectCaller.callNumber(policeNum);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([t, h, contacts, detector, detector.settings]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              const Text('SmartKavach',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const Spacer(),
              // Network indicator pill
              FutureBuilder<bool>(
                future: detector.checkInternetNetwork(),
                builder: (context, snapshot) {
                  final online = snapshot.data ?? true;
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: online
                          ? kGood.withValues(alpha: 0.15)
                          : kSos.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(online ? Icons.wifi : Icons.signal_cellular_connected_no_internet_4_bar,
                            size: 13,
                            color: online ? kGood : kSos),
                        const SizedBox(width: 5),
                        Text(
                          online ? 'ONLINE' : 'OFFLINE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: online ? kGood : kSos,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ]),
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
                    builder: (_) => SosSettingsPage(
                          contacts: contacts,
                          detector: detector,
                        ))),
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
            const SizedBox(height: 16),

            // Speedometer Panel
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

            // Map Panel
            Panel(
              pad: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 180,
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
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 🛡️ ACCIDENT DETECTION SHIELD & STATUS CARD
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        detector.settings.enabled
                            ? Icons.security
                            : Icons.security_outlined,
                        color: detector.settings.enabled ? kGood : Colors.white38,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Accident Shield',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: detector.settings.enabled
                              ? kGood.withValues(alpha: 0.2)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          detector.settings.enabled ? 'ACTIVE' : 'DISABLED',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: detector.settings.enabled
                                ? kGood
                                : Colors.white38,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Automatically detects abnormal deceleration drops & gyroscope angular flips. If offline, directly calls Police 100.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 14),

                  // Real-time Sensor Telemetry Bar
                  Row(
                    children: [
                      Expanded(
                        child: _sensorStat(
                          'Decel / Speed',
                          '${t.speed.toStringAsFixed(0)} km/h',
                          Icons.speed,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _sensorStat(
                          'Gyro (Limit ${detector.settings.gyroThreshold.toStringAsFixed(0)})',
                          '${(h.connected ? h.gyro.effectiveRotationRate : detector.lastPhoneGyroDeg).toStringAsFixed(0)}°/s',
                          Icons.threed_rotation,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _sensorStat(
                          'Impact G',
                          '${detector.lastPhoneGForce.toStringAsFixed(1)}G',
                          Icons.electric_bolt,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Simulation / Test Trigger Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        detector.triggerCrashAlarm(
                          reason: 'Manual Accident Test Simulation (Safe Mode)',
                        );
                      },
                      icon: const Icon(Icons.ring_volume, size: 18),
                      label: const Text('Test Crash Alarm & Countdown'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kAccent,
                        side: const BorderSide(color: kAccent),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Gyroscope Panel
            GyroPanel(g: h.gyro),
            const SizedBox(height: 20),

            // Big Manual SOS Button
            GestureDetector(
              onLongPress: () => _sos(context),
              child: Container(
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kSos,
                  borderRadius: BorderRadius.circular(38),
                  boxShadow: [
                    BoxShadow(
                        color: kSos.withValues(alpha: 0.4), blurRadius: 24)
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

  Widget _sensorStat(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: kAccent),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.white54),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
