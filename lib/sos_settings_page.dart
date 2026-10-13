import 'package:flutter/material.dart';
import 'accident_detector.dart';
import 'main.dart' show Contacts, Panel, kAccent, kBg, kGood;

/// SOS & Accident Settings Page:
/// - Police emergency number (defaults to 100)
/// - "Call Police 100 if No Network" toggle
/// - "Always Call Police on Crash" toggle
/// - Alarm countdown slider (10–30s)
/// - Crash detection sensitivity (Low 320°, Normal 240°, High 180°)
/// - Gyroscope (MPU) Trigger Limit slider (100°–400°/s, default 240°/s)
/// - Emergency contacts management (Up to 3 numbers)
class SosSettingsPage extends StatefulWidget {
  const SosSettingsPage({
    super.key,
    required this.contacts,
    required this.detector,
  });

  final Contacts contacts;
  final AccidentDetector detector;

  @override
  State<SosSettingsPage> createState() => _SosSettingsPageState();
}

class _SosSettingsPageState extends State<SosSettingsPage> {
  final _ctrl = TextEditingController();
  late final TextEditingController _policeCtrl;
  String? _err;

  @override
  void initState() {
    super.initState();
    _policeCtrl = TextEditingController(
      text: widget.detector.settings.policeNumber,
    );
  }

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
    _policeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.detector.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('SOS & Accident Settings'), backgroundColor: kBg),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.contacts, s]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 🛡️ ACCIDENT DETECTION AUTOMATION SECTION
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: kAccent),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Automatic Accident Detection',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Switch(
                        value: s.enabled,
                        activeThumbColor: kGood,
                        onChanged: (v) => s.update(newEnabled: v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Detects sudden speed drops and sharp gyroscope rotation angle changes. Rings a loud alarm and triggers emergency response.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 📞 POLICE EMERGENCY CONFIGURATION
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Police & Emergency Dispatch',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),

                  // Police Number Field
                  TextField(
                    controller: _policeCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Police Emergency Number',
                      hintText: '100',
                      helperText: 'Default is 100 (National Police in India)',
                      prefixIcon: const Icon(Icons.local_police, color: kAccent),
                      filled: true,
                      fillColor: kBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) {
                      s.update(newPoliceNumber: val.trim());
                    },
                  ),
                  const SizedBox(height: 10),

                  // Quick presets for Police Number
                  Row(
                    children: [
                      const Text('Quick set: ',
                          style: TextStyle(fontSize: 12, color: Colors.white54)),
                      ActionChip(
                        label: const Text('100 (Police)'),
                        onPressed: () {
                          _policeCtrl.text = '100';
                          s.update(newPoliceNumber: '100');
                        },
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        label: const Text('112 (Universal)'),
                        onPressed: () {
                          _policeCtrl.text = '112';
                          s.update(newPoliceNumber: '112');
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 24, color: Colors.white12),

                  // Call Police if No Network Switch
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Call Police 100 if No Network',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text(
                      'If there is no internet or mobile data during a crash, immediately dial Police directly via cellular line.',
                      style: TextStyle(fontSize: 12, color: Colors.white60),
                    ),
                    value: s.callPoliceOnNoNetwork,
                    activeThumbColor: kGood,
                    onChanged: (v) => s.update(newCallPoliceNoNetwork: v),
                  ),

                  // Always Call Police Switch
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Always Call Police on Crash',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text(
                      'Directly dial police on every detected crash even if internet is active.',
                      style: TextStyle(fontSize: 12, color: Colors.white60),
                    ),
                    value: s.alwaysCallPoliceOnCrash,
                    activeThumbColor: kAccent,
                    onChanged: (v) => s.update(newAlwaysCallPolice: v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ⏱️ ALARM COUNTDOWN & SENSITIVITY
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Alarm Countdown & Sensitivity',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),

                  // Countdown Duration
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Alarm Countdown Duration:',
                          style: TextStyle(fontSize: 13, color: Colors.white70)),
                      Text('${s.countdownDuration} seconds',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: kAccent)),
                    ],
                  ),
                  Slider(
                    value: s.countdownDuration.toDouble(),
                    min: 10,
                    max: 30,
                    divisions: 4,
                    label: '${s.countdownDuration}s',
                    activeColor: kAccent,
                    onChanged: (v) => s.update(newCountdownDuration: v.toInt()),
                  ),

                  const SizedBox(height: 8),

                  // Sensitivity Segmented Buttons
                  const Text('Crash Detection Sensitivity:',
                      style: TextStyle(fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 8),
                  SegmentedButton<CrashSensitivity>(
                    segments: const [
                      ButtonSegment(
                        value: CrashSensitivity.low,
                        label: Text('Low (320°)'),
                      ),
                      ButtonSegment(
                        value: CrashSensitivity.normal,
                        label: Text('Normal (240°)'),
                      ),
                      ButtonSegment(
                        value: CrashSensitivity.high,
                        label: Text('High (180°)'),
                      ),
                    ],
                    selected: {s.sensitivity},
                    onSelectionChanged: (set) {
                      s.update(newSensitivity: set.first);
                    },
                  ),

                  const SizedBox(height: 16),

                  // Gyroscope Custom Threshold Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Gyro (MPU) Trigger Limit:',
                          style: TextStyle(fontSize: 13, color: Colors.white70)),
                      Text('${s.gyroThreshold.toStringAsFixed(0)}°/s',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: kAccent)),
                    ],
                  ),
                  Slider(
                    value: s.gyroThreshold.clamp(100.0, 400.0),
                    min: 100,
                    max: 400,
                    divisions: 15,
                    label: '${s.gyroThreshold.toStringAsFixed(0)}°/s',
                    activeColor: kAccent,
                    onChanged: (v) => s.update(newGyroThreshold: v),
                  ),
                  const Text(
                    'When your helmet or phone gyroscope rotation rate reaches or exceeds this limit, the SOS Alarm triggers immediately.',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 👥 EMERGENCY CONTACTS SECTION
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Emergency Contacts (Up to 3)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Will receive emergency SMS texts with your live GPS location on crash or manual SOS.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Contact phone number',
                          errorText: _err,
                          filled: true,
                          fillColor: kBg,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                        onPressed: _add,
                        icon: const Icon(Icons.add),
                        style: IconButton.styleFrom(
                            minimumSize: const Size(54, 54))),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 12),

            if (widget.contacts.numbers.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('No emergency contacts added yet',
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
                              const Text('Called first if online',
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
}
