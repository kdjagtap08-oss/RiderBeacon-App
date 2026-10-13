import 'package:flutter/material.dart';
import 'accident_detector.dart';

/// Full-screen emergency alert modal shown when an accident is detected.
/// Rings the SOS siren, counts down, and provides immediate Cancel or Dispatch actions.
class AccidentAlertModal extends StatefulWidget {
  final AccidentDetector detector;
  final VoidCallback onCancel;
  final VoidCallback onDispatchNow;

  const AccidentAlertModal({
    super.key,
    required this.detector,
    required this.onCancel,
    required this.onDispatchNow,
  });

  @override
  State<AccidentAlertModal> createState() => _AccidentAlertModalState();
}

class _AccidentAlertModalState extends State<AccidentAlertModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detector;
    final total = d.settings.countdownDuration;
    final remaining = d.countdownRemaining;
    final progress = total > 0 ? (remaining / total).clamp(0.0, 1.0) : 0.0;
    final policeNumber = d.settings.policeNumber;

    return PopScope(
      canPop: false, // Prevent accidental dismissal with Android back button
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: 0.92),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: d,
            builder: (context, _) => Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Flashing Siren Banner
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5323B),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE5323B).withValues(alpha: 0.6),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning, color: Colors.white, size: 26),
                            SizedBox(width: 10),
                            Text(
                              'ACCIDENT DETECTED',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Explanation of detection
                    Text(
                      d.detectionReason.isNotEmpty
                          ? d.detectionReason
                          : 'Abnormal speed drop & angle change detected!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.volume_up,
                              color: Color(0xFFFF6B2C), size: 18),
                          SizedBox(width: 8),
                          Text(
                            'SOS ALARM RINGING LOUDLY',
                            style: TextStyle(
                              color: Color(0xFFFF6B2C),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Circular Countdown Timer
                    SizedBox(
                      width: 190,
                      height: 190,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 14,
                              backgroundColor: Colors.white12,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFFE5323B),
                              ),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$remaining',
                                style: const TextStyle(
                                  fontSize: 68,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              const Text(
                                'SECONDS',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Offline Fallback Notice
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF181D25),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFFF6B2C).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.emergency,
                              color: Color(0xFFFF6B2C), size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Emergency Response Protocol',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'If there is NO NETWORK, app will directly call Police ($policeNumber) & text offline GPS coordinates.',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Big Cancel Button ("I AM OK")
                    SizedBox(
                      width: double.infinity,
                      height: 62,
                      child: ElevatedButton.icon(
                        onPressed: widget.onCancel,
                        icon: const Icon(Icons.check_circle_outline,
                            size: 28, color: Colors.white),
                        label: const Text(
                          'I AM OK  •  CANCEL ALARM',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3DDC97),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Send SOS Now Button (Direct override)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: widget.onDispatchNow,
                        icon: const Icon(Icons.phone_forwarded,
                            color: Color(0xFFE5323B)),
                        label: Text(
                          'SEND SOS NOW (CALL POLICE $policeNumber)',
                          style: const TextStyle(
                            color: Color(0xFFE5323B),
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: Color(0xFFE5323B), width: 1.8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
