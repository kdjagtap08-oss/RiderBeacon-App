import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const kSosRed = Color(0xFFE5323B);
const kSafeGreen = Color(0xFF3DDC97);
const kDarkModalBg = Color(0xFF130507);

/// Emergency Safety Modal that overlays the app for 15 seconds
/// when a crash is flagged by the detection engine.
class CrashCountdownDialog extends StatefulWidget {
  const CrashCountdownDialog({
    super.key,
    required this.onCancel,
    required this.onTimeout,
    this.totalSeconds = 15,
  });

  final VoidCallback onCancel;
  final VoidCallback onTimeout;
  final int totalSeconds;

  @override
  State<CrashCountdownDialog> createState() => _CrashCountdownDialogState();
}

class _CrashCountdownDialogState extends State<CrashCountdownDialog>
    with SingleTickerProviderStateMixin {
  late int _remainingSeconds;
  Timer? _timer;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.totalSeconds;

    _animController = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.totalSeconds),
    )..forward();

    _triggerHaptic();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 1) {
        setState(() {
          _remainingSeconds--;
        });
        _triggerHaptic();
      } else {
        _timer?.cancel();
        _animController.stop();
        widget.onTimeout();
      }
    });
  }

  void _triggerHaptic() {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _remainingSeconds / widget.totalSeconds;

    return PopScope(
      canPop: false, // Prevent dismissing with back gesture
      child: Scaffold(
        backgroundColor: kDarkModalBg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Top Header Warning
                Column(
                  children: [
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kSosRed.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: kSosRed,
                        size: 54,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'CRASH DETECTED!',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Emergency SOS will automatically trigger if you do not respond.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),

                // Center Circular Countdown
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 16,
                          strokeCap: StrokeCap.round,
                          backgroundColor: Colors.white12,
                          color: kSosRed,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_remainingSeconds',
                            style: const TextStyle(
                              fontSize: 78,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const Text(
                            'SECONDS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Bottom Action Button: I AM OK
                Column(
                  children: [
                    Text(
                      'Calling emergency contacts in $_remainingSeconds seconds...',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 68,
                      child: ElevatedButton.icon(
                        onPressed: widget.onCancel,
                        icon: const Icon(Icons.check_circle_outline, size: 28),
                        label: const Text(
                          "I'M OK — CANCEL SOS",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kSafeGreen,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(34),
                          ),
                          elevation: 6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
