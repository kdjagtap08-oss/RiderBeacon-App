import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'convoy_calculator.dart';
import 'group_ride_service.dart';

const kSosRed = Color(0xFFE5323B);
const kGoodGreen = Color(0xFF3DDC97);
const kAccentOrange = Color(0xFFFF6B2C);

/// High-priority alert dialog shown to convoy members when a peer triggers a crash alert.
class ConvoyCrashDialog extends StatelessWidget {
  const ConvoyCrashDialog({
    super.key,
    required this.metric,
    required this.onDismiss,
  });

  final ConvoyMemberMetric metric;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final member = metric.member;

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: const Color(0xFF181D25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: kSosRed, width: 2.5),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing Warning Icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kSosRed.withValues(alpha: 0.18),
                  border: Border.all(color: kSosRed, width: 2),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  size: 42,
                  color: kSosRed,
                ),
              ),

              const SizedBox(height: 16),

              // Title
              const Text(
                'CONVOY CRASH ALERT!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: kSosRed,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              // Rider Name & Status
              Text(
                '${member.displayName} triggered an emergency crash alert!',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Telemetry Info Box
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Distance:', style: TextStyle(color: Colors.white60, fontSize: 13)),
                        Text(
                          metric.formattedDistance,
                          style: const TextStyle(color: kGoodGreen, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Position:', style: TextStyle(color: Colors.white60, fontSize: 13)),
                        Text(
                          metric.position == RelativePosition.ahead ? 'Ahead of you' : 'Behind you',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('GPS Location:', style: TextStyle(color: Colors.white60, fontSize: 13)),
                        Text(
                          '${member.position.latitude.toStringAsFixed(4)}, ${member.position.longitude.toStringAsFixed(4)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Navigation & Call Actions
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: kAccentOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        GroupRideService.openDirectionsTo(member.position);
                      },
                      icon: const Icon(Icons.navigation, size: 18),
                      label: const Text('Directions', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (member.phoneNumber != null && member.phoneNumber!.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: kGoodGreen,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          FlutterPhoneDirectCaller.callNumber(member.phoneNumber!);
                        },
                        icon: const Icon(Icons.call, size: 18),
                        label: const Text('Call', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 10),

              // Dismiss Button
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white60,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Dismiss Alert'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
